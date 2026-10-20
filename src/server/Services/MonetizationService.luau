--[[
	MonetizationService: everything bought with Robux (docs/COMPLIANCE.md).
	Ids and kinds: MonetizationConfig (Id 0 = not created yet: never prompted,
	never checked, never matched). Handlers register by the entry's Grant in
	their service's init().

	Game passes (Kind "GamePass": bought once, owned forever):
	  MonetizationService.registerPass(grant, { grant = fn, revoke = fn })
	    grant(player, data, entry): boolean   give what the pass gives; true
	                                          when something changed (no yield,
	                                          idempotent: it runs on every load)
	    revoke(player, data, entry): boolean? take back only what the pass gave
	                                          (Roblox says it isn't owned any
	                                          more: a refund); false = nothing changed
	  - Every time a save loads (DataService.onLoaded) a spawned task asks
	    MarketplaceService:UserOwnsGamePassAsync for each live pass, in pcall,
	    up to CheckTries times with a growing pause (RetryDelay, x2), never
	    holding the load up and giving up quietly when the player leaves.
	    Owned -> grant. A successful "not owned" -> revoke. A check that keeps
	    failing changes nothing.
	  - PromptGamePassPurchaseFinished(player, passId, wasPurchased) on the
	    server: grant when wasPurchased and passId is a live pass entry.
	  - MonetizationService.owns(player, key): the session's answer (true only
	    once Roblox or a purchase said so).
	  - DataService.changed after every change (the saves don't need an extra
	    write: ownership is checked again on the next load).

	Developer products (Kind "Product", bought again and again): the game's one
	MarketplaceService.ProcessReceipt callback (MonetizationService.decide):
	  MonetizationService.register(grant, function(player, data, entry): boolean)
	  - the player is not in this server, or their save isn't loaded here
	    (DataService.get is nil: only the server holding the ProfileStore
	    session lock has it)                         -> NotProcessedYet
	  - the same PurchaseId is being decided right now -> NotProcessedYet
	  - the PurchaseId is already in data.Purchases  -> PurchaseGranted, once
	    the save holding it went through (granted here but the save failed:
	    save again first; still failing -> NotProcessedYet)
	  - not a live "Product" entry, no handler, or the handler refuses
	                                                 -> NotProcessedYet
	  - else: grant, data.Purchases[PurchaseId] = os.time(), PurchaseCount + 1,
	    DataService.changed, DataService.saveNow; PurchaseGranted only when the
	    save succeeded, else NotProcessedYet (Roblox calls again; the id is
	    already recorded, so the next call only retries the save)
	Game passes never go through ProcessReceipt. Nothing is granted from
	PromptProductPurchaseFinished. DataService keeps Purchases bounded.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local DataService = require(script.Parent.DataService)
local Receipts = require(script.Parent.Parent.Receipts)

local MonetizationService = {}

export type Grant = (player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry) -> boolean
export type PassHandler = {
	grant: (player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry) -> boolean,
	revoke: (player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry) -> boolean?,
}

MonetizationService.CheckTries = 4 -- UserOwnsGamePassAsync attempts per pass and load
MonetizationService.RetryDelay = 2 -- seconds before the 2nd attempt (then x2)

local grants: { [string]: Grant } = {}
local passHandlers: { [string]: PassHandler } = {}
-- the session's pass answers: [player][entry key] = owned (nil = not known yet)
local passOwned: { [Player]: { [string]: boolean } } = {}
-- purchase ids granted in this server whose save hasn't gone through yet
local unsaved: { [string]: boolean } = {}
-- purchase ids being decided right now (Roblox may call again while a save yields)
local inFlight: { [string]: boolean } = {}

-- test seams (MonetizationService._test)
local findPlayer: (userId: number) -> Player? = function(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end
local ownsGamePass: (userId: number, passId: number) -> boolean = function(userId: number, passId: number): boolean
	return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
end
local pause: (seconds: number) -> () = function(seconds: number)
	task.wait(seconds)
end

-- Registers the ProcessReceipt handler of a developer product Grant.
function MonetizationService.register(grant: string, handler: Grant)
	grants[grant] = handler
end

-- Registers the grant / revoke handlers of a game pass Grant.
function MonetizationService.registerPass(grant: string, handler: PassHandler)
	passHandlers[grant] = handler
end

-- True once Roblox (or a purchase in this session) said the player owns the pass `key`.
function MonetizationService.owns(player: Player, key: string): boolean
	local known = passOwned[player]
	return known ~= nil and known[key] == true
end

---------------------------------------------------------------- game passes

local function remember(player: Player, key: string, owned: boolean)
	local known = passOwned[player]
	if not known then
		known = {}
		passOwned[player] = known
	end
	known[key] = owned
end

-- Applies a pass answer to the save: grant when owned, revoke otherwise. True when the save changed.
local function applyPass(player: Player, entry: MonetizationConfig.Entry, owned: boolean): boolean
	remember(player, entry.Key, owned)
	local data = DataService.get(player)
	local handler = passHandlers[entry.Grant or ""]
	if not data or not handler then
		return false
	end
	local ok, changed = pcall(function(): boolean
		if owned then
			return handler.grant(player, data, entry) == true
		end
		return handler.revoke(player, data, entry) ~= false
	end)
	if not ok then
		warn(`[MonetizationService] pass {entry.Key} failed: {changed}`)
		return false
	end
	if changed then
		DataService.changed(player)
	end
	return changed
end

-- Asks Roblox whether the player owns the pass: true / false, or nil when every try failed
-- (or the player left).
local function checkPass(player: Player, entry: MonetizationConfig.Entry): boolean?
	local delay = MonetizationService.RetryDelay
	for attempt = 1, MonetizationService.CheckTries do
		if not player.Parent then
			return nil
		end
		local ok, result = pcall(ownsGamePass, player.UserId, entry.Id)
		if ok and type(result) == "boolean" then
			return result
		end
		if attempt < MonetizationService.CheckTries then
			pause(delay)
			delay *= 2
		end
	end
	if player.Parent then
		warn(`[MonetizationService] couldn't check pass {entry.Key} for {player.Name}; trying again next load`)
	end
	return nil
end

-- Checks every live pass of a player whose save just loaded (yields: run it in its own task).
local function checkAll(player: Player)
	for _, entry in MonetizationConfig.list("GamePass") do
		if MonetizationConfig.isLive(entry.Id) and passHandlers[entry.Grant or ""] then
			local owned = checkPass(player, entry)
			if owned ~= nil and player.Parent and DataService.get(player) then
				applyPass(player, entry, owned)
			end
		end
	end
end

-- MarketplaceService.PromptGamePassPurchaseFinished (server): grant a live pass just bought.
local function onPassPurchaseFinished(player: Player, passId: any, wasPurchased: any)
	if wasPurchased ~= true then
		return
	end
	local entry = MonetizationConfig.byId(passId, "GamePass")
	if not entry then
		return
	end
	applyPass(player, entry, true)
end

---------------------------------------------------------------- developer products

local function purchaseKey(value: any): string?
	if type(value) == "string" and #value > 0 and #value <= 128 then
		return value
	elseif type(value) == "number" and value == value then
		return tostring(value)
	end
	return nil
end

local function decideFor(player: Player, data: { [string]: any }, id: string, productId: any): Enum.ProductPurchaseDecision
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local purchases = data.Purchases
	if type(purchases) ~= "table" then
		purchases = {}
		data.Purchases = purchases
	end
	if purchases[id] ~= nil then
		-- granted before: only confirm once the save holding it went through
		if unsaved[id] then
			if not DataService.saveNow(player) then
				return NOT_YET
			end
			unsaved[id] = nil
		end
		return GRANTED
	end
	local entry = MonetizationConfig.byId(productId, "Product")
	local grant = if entry then grants[entry.Grant or ""] else nil
	if not entry or not grant then
		warn(`[MonetizationService] no product / handler for product id {tostring(productId)}`)
		return NOT_YET
	end
	-- grant and record with no yield in between: a handler that yields is cancelled and refused
	local thread = coroutine.create(grant)
	local ran, granted = coroutine.resume(thread, player, data, entry)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		warn(`[MonetizationService] the {entry.Grant} grant handler yielded: refused (handlers must not yield)`)
		return NOT_YET
	end
	if not ran then
		error(granted, 0)
	end
	if granted ~= true then
		return NOT_YET
	end
	purchases[id] = os.time()
	local count = tonumber(data.PurchaseCount)
	data.PurchaseCount = (if count and count == count then math.floor(count) else 0) + 1
	unsaved[id] = true
	DataService.changed(player)
	if not DataService.saveNow(player) then
		return NOT_YET
	end
	unsaved[id] = nil
	return GRANTED
end

-- The ProcessReceipt decision for a receipt ({ PlayerId, PurchaseId, ProductId, ... }).
function MonetizationService.decide(receipt: any): Enum.ProductPurchaseDecision
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	if type(receipt) ~= "table" then
		return NOT_YET
	end
	local userId = receipt.PlayerId
	local id = purchaseKey(receipt.PurchaseId)
	if type(userId) ~= "number" or not id then
		return NOT_YET
	end
	if inFlight[id] then
		return NOT_YET
	end
	local player = findPlayer(userId)
	if not player then
		return NOT_YET
	end
	-- loaded only on the server that holds the player's session lock
	local data = DataService.get(player)
	if not data then
		return NOT_YET
	end
	inFlight[id] = true
	local ok, result = pcall(decideFor, player, data, id, receipt.ProductId)
	inFlight[id] = nil
	if not ok then
		warn(`[MonetizationService] receipt {id} failed: {result}`)
		return NOT_YET
	end
	return result
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/MonetizationService.spec.luau).
MonetizationService._test = {
	setFindPlayer = function(fn: (number) -> Player?)
		findPlayer = fn
	end,
	-- replaces MarketplaceService:UserOwnsGamePassAsync (it may error like the real one)
	setOwnsGamePass = function(fn: (number, number) -> boolean)
		ownsGamePass = fn
	end,
	-- replaces task.wait between the pass check tries
	setPause = function(fn: (number) -> ())
		pause = fn
	end,
	checkAll = checkAll,
	purchaseFinished = onPassPurchaseFinished,
	isUnsaved = function(id: string): boolean
		return unsaved[id] == true
	end,
	setInFlight = function(id: string, on: boolean)
		if on then
			inFlight[id] = true
		else
			inFlight[id] = nil
		end
	end,
	reset = function()
		table.clear(unsaved)
		table.clear(inFlight)
		table.clear(passOwned)
		findPlayer = function(userId: number): Player?
			return Players:GetPlayerByUserId(userId)
		end
		ownsGamePass = function(userId: number, passId: number): boolean
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end
		pause = function(seconds: number)
			task.wait(seconds)
		end
	end,
	grants = grants,
	passHandlers = passHandlers,
}

function MonetizationService.init()
	-- grant handlers register in their own services' init(); the checks run after the loads
	DataService.onLoaded(function(player: Player)
		task.spawn(checkAll, player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished)
	Players.PlayerRemoving:Connect(function(player: Player)
		passOwned[player] = nil
	end)
end

-- The live passes and products nothing grants yet (no handler for their Grant).
function MonetizationService.unhandled(): { string }
	local missing: { string } = {}
	for _, entry in MonetizationConfig.List do
		if MonetizationConfig.isLive(entry.Id) then
			local grant = entry.Grant or ""
			local handled = if entry.Kind == "GamePass" then passHandlers[grant] ~= nil else grants[grant] ~= nil
			if not handled then
				table.insert(missing, entry.Key)
			end
		end
	end
	return missing
end

function MonetizationService.start()
	-- exactly one ProcessReceipt callback in the game; set after every init() registered its handler
	MarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision
		return MonetizationService.decide(receipt)
	end
	-- the receipts gate (src/server/Receipts.luau) opens only when every live pass and product
	-- has a handler, so a live id whose grant isn't written yet (step 8) is never sold
	local missing = MonetizationService.unhandled()
	if #missing == 0 then
		Receipts.setReady(true)
	else
		warn(`[MonetizationService] receipts stay closed: no handler for {table.concat(missing, ", ")}`)
	end
end

return MonetizationService
