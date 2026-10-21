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
	    The passes giving an OfflinePerks perk go first (the offline payout
	    waits for them), then by key. Owned -> grant. A successful "not
	    owned" -> revoke, except for a pass bought in this session (Roblox
	    may answer from before the purchase: a check in flight while the
	    player bought it; a refund shows on a later load). A check that
	    keeps failing changes nothing and is asked again RecheckDelay later,
	    up to Rechecks more rounds while the player stays.
	  - PromptGamePassPurchaseFinished(player, passId, wasPurchased) on the
	    server: grant when wasPurchased and passId is a live pass entry.
	  - MonetizationService.owns(player, key): the session's answer (true only
	    once Roblox or a purchase said so). passesChecked(player): the load's
	    first round is done. onPassesChecked(fn): after that round, and after
	    every later round that answered a pass. perkAtJoin(player, perk): did
	    a pass the player owned when they joined give the perk (nil while
	    unknown)? PodiumService's offline payout uses it, so Night Shift and
	    the Podiums pass count even when a check is late.
	  - Grant "Perks" (registered here, registerPerks): the entry's Perks list
	    as player attributes (src/server/Perks.luau). Session-only, set again
	    on every load, never consumed; a revoke clears only the perks no
	    other pass the player owns gives.
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
	  - else: grant, data.Purchases[PurchaseId] = os.time(),
	    data.PurchaseLog[PurchaseId] = { Product = Key, At = os.time() },
	    PurchaseCount + 1 (all in one step with no yield), DataService.changed,
	    DataService.saveNow; PurchaseGranted only when the save succeeded,
	    else NotProcessedYet (Roblox calls again; the id is already recorded,
	    so the next call only retries the save)
	  Off policy (MonetizationConfig's step 8 contract): a known product is
	  granted whatever the player's PolicyService answer (a paid random
	  product for a restricted player is granted and logged); a receipt no
	  live entry matches (an id still 0 here, an unknown id), a missing
	  handler or a handler that can't take it yet is never acknowledged
	  without the item (NotProcessedYet, Roblox delivers it again) and
	  logged once per purchase and reason with the player id, product id and
	  purchase id. Clients can prompt any product themselves: nothing here
	  trusts a prompt.
	Game passes never go through ProcessReceipt. Nothing is granted from
	PromptProductPurchaseFinished. DataService keeps Purchases bounded.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local DataService = require(script.Parent.DataService)
local Perks = require(script.Parent.Parent.Perks)
local Policy = require(script.Parent.Parent.Policy)
local Receipts = require(script.Parent.Parent.Receipts)

local MonetizationService = {}

export type Grant = (player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry) -> boolean
export type PassHandler = {
	grant: (player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry) -> boolean,
	revoke: (player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry) -> boolean?,
}

MonetizationService.CheckTries = 4 -- UserOwnsGamePassAsync attempts per pass and load
MonetizationService.RetryDelay = 2 -- seconds before the 2nd attempt (then x2)
MonetizationService.RecheckDelay = 60 -- seconds before a pass whose check kept failing is asked again
MonetizationService.Rechecks = 5 -- such later rounds per load (then: the next load)
-- the perks the offline payout depends on (PodiumService): passes giving them are checked first
MonetizationService.OfflinePerks = { "OfflineExtension", "Podiums" }

local grants: { [string]: Grant } = {}
local passHandlers: { [string]: PassHandler } = {}
-- the session's pass answers: [player][entry key] = owned (nil = not known yet)
local passOwned: { [Player]: { [string]: boolean } } = {}
-- passes bought in this session (PromptGamePassPurchaseFinished): [player][entry key] = true
local bought: { [Player]: { [string]: boolean } } = {}
-- the checks' answers only (never a purchase): [player][entry key] = owned when they joined
local joinOwned: { [Player]: { [string]: boolean } } = {}
-- purchase ids granted in this server whose save hasn't gone through yet
local unsaved: { [string]: boolean } = {}
-- purchase ids being decided right now (Roblox may call again while a save yields)
local inFlight: { [string]: boolean } = {}
-- off-policy lines already logged in this server ("purchaseId|reason")
local logged: { [string]: boolean } = {}
local loggedCount = 0
-- players whose load-time pass checks are done, and who waits for that
local checked: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local checkedCallbacks: { (Player) -> () } = {}

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
local logLine: (text: string) -> () = function(text: string)
	warn(text)
end

-- Logs a receipt that arrived off policy, once per purchase and reason (Roblox delivers
-- a pending receipt again and again): player id, product id, purchase id, why.
local function offPolicy(userId: any, productId: any, purchaseId: string, reason: string)
	local key = `{purchaseId}|{reason}`
	if logged[key] then
		return
	end
	if loggedCount >= 1000 then
		table.clear(logged)
		loggedCount = 0
	end
	logged[key] = true
	loggedCount += 1
	logLine(
		`[MonetizationService] receipt off policy ({reason}): player {tostring(userId)}, product {tostring(productId)}, purchase {purchaseId}`
	)
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

-- True once this session knows whether the player owns the pass `key` (a check answered).
function MonetizationService.known(player: Player, key: string): boolean
	local known = passOwned[player]
	return known ~= nil and known[key] ~= nil
end

---------------------------------------------------------------- game passes

local function mark(map: { [Player]: { [string]: boolean } }, player: Player, key: string, value: boolean)
	local known = map[player]
	if not known then
		known = {}
		map[player] = known
	end
	known[key] = value
end

local function remember(player: Player, key: string, owned: boolean)
	mark(passOwned, player, key, owned)
end

local function boughtNow(player: Player, key: string): boolean
	local mine = bought[player]
	return mine ~= nil and mine[key] == true
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
		warn(`[MonetizationService] couldn't check pass {entry.Key} for {player.Name}; trying again later`)
	end
	return nil
end

-- Does the pass give one of these perks?
local function givesAny(entry: MonetizationConfig.Entry, perks: { string }): boolean
	local own = entry.Perks
	if not own then
		return false
	end
	for _, perk in perks do
		if table.find(own, perk) then
			return true
		end
	end
	return false
end

-- The live passes with a handler, in check order: the ones giving an OfflinePerks perk
-- first (the offline payout waits for them), then the rest, each part by key.
local function checkList(): { MonetizationConfig.Entry }
	local first: { MonetizationConfig.Entry } = {}
	local rest: { MonetizationConfig.Entry } = {}
	for _, entry in MonetizationConfig.list("GamePass") do
		if MonetizationConfig.isLive(entry.Id) and passHandlers[entry.Grant or ""] then
			if givesAny(entry, MonetizationService.OfflinePerks) then
				table.insert(first, entry)
			else
				table.insert(rest, entry)
			end
		end
	end
	for _, entry in rest do
		table.insert(first, entry)
	end
	return first
end

-- Asks Roblox about each pass and applies the answers. Returns the passes whose check kept failing.
local function checkRound(player: Player, entries: { MonetizationConfig.Entry }): { MonetizationConfig.Entry }
	local failed: { MonetizationConfig.Entry } = {}
	for _, entry in entries do
		if not player.Parent then
			break
		end
		local owned = checkPass(player, entry)
		if owned == nil then
			table.insert(failed, entry)
		elseif player.Parent and DataService.get(player) and (owned or not boughtNow(player, entry.Key)) then
			-- (a pass bought while or before this check ran keeps its purchase: Roblox may
			-- answer from before it, so only a "not owned" waits for a later load; an "owned"
			-- still grants: a pass bought while the save was loading had nothing to grant into)
			if not boughtNow(player, entry.Key) then
				mark(joinOwned, player, entry.Key, owned) -- (perkAtJoin: never for a pass bought this session)
			end
			applyPass(player, entry, owned)
		end
	end
	return failed
end

local function notifyChecked(player: Player)
	for _, callback in checkedCallbacks do
		task.spawn(callback, player)
	end
end

-- Checks every live pass of a player whose save just loaded, then asks again later
-- for the ones whose check kept failing (yields: run it in its own task).
local function checkAll(player: Player)
	checked[player] = nil
	local failed = checkRound(player, checkList())
	checked[player] = true
	notifyChecked(player)
	for _ = 1, MonetizationService.Rechecks do
		if #failed == 0 or not player.Parent then
			return
		end
		pause(MonetizationService.RecheckDelay)
		if not player.Parent then
			return
		end
		local before = #failed
		failed = checkRound(player, failed)
		if #failed < before then
			notifyChecked(player)
		end
	end
end

-- Are the pass checks of this player's load done (owned passes granted)?
function MonetizationService.passesChecked(player: Player): boolean
	return checked[player] == true
end

-- callback(player) once the first round of a load's pass checks is done, and again after
-- every later round that answered a pass whose check had failed.
function MonetizationService.onPassesChecked(callback: (Player) -> ())
	table.insert(checkedCallbacks, callback)
end

--[[
	Did the player own a pass giving `perk` when they joined? true once a check
	said so; false once every live pass giving it answered "not owned" (a pass
	bought in this session counts as not owned then: Roblox sells a pass once);
	nil while one of them hasn't answered (not checked yet, or its check kept
	failing). PodiumService's offline payout waits for it, and tops up when a
	late answer says owned.
]]
function MonetizationService.perkAtJoin(player: Player, perk: string): boolean?
	local answers = joinOwned[player]
	local unknown = false
	for _, entry in MonetizationConfig.list("GamePass") do
		local perks = entry.Perks
		if perks and table.find(perks, perk) and MonetizationConfig.isLive(entry.Id) and passHandlers[entry.Grant or ""] then
			local answer = if answers then answers[entry.Key] else nil
			if answer == true then
				return true
			elseif answer == nil and not boughtNow(player, entry.Key) then
				unknown = true
			end
		end
	end
	return if unknown then nil else false
end

---------------------------------------------------------------- the "Perks" passes

-- Does another pass the player owns (this session) give `perk`?
local function perkFromOther(player: Player, perk: string, exceptKey: string): boolean
	for _, other in MonetizationConfig.list("GamePass") do
		if other.Key ~= exceptKey and other.Grant == "Perks" and other.Perks and table.find(other.Perks, perk) then
			if MonetizationService.owns(player, other.Key) then
				return true
			end
		end
	end
	return false
end

-- Pass handler "Perks" grant: the entry's perks as attributes. True when one changed.
local function grantPerks(player: Player, _data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local changed = false
	local perks: { string } = entry.Perks or {}
	for _, perk in perks do
		if not Perks.has(player, perk) then
			Perks.set(player, perk, true)
			changed = true
		end
	end
	return changed
end

-- Pass handler "Perks" revoke: clears the entry's perks no other owned pass gives.
local function revokePerks(player: Player, _data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local changed = false
	local perks: { string } = entry.Perks or {}
	for _, perk in perks do
		if Perks.has(player, perk) and not perkFromOther(player, perk, entry.Key) then
			Perks.set(player, perk, false)
			changed = true
		end
	end
	return changed
end

-- Registers the "Perks" pass handler (init(); idempotent).
function MonetizationService.registerPerks()
	MonetizationService.registerPass("Perks", { grant = grantPerks, revoke = revokePerks })
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
	mark(bought, player, entry.Key, true)
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
	if not entry then
		-- an id still 0 in MonetizationConfig, or one this build doesn't sell: kept pending
		offPolicy(player.UserId, productId, id, "no live product with this id: paste it into MonetizationConfig")
		return NOT_YET
	end
	local grant = grants[entry.Grant or ""]
	if not grant then
		offPolicy(player.UserId, productId, id, `no handler for {entry.Key} (Grant {tostring(entry.Grant)})`)
		return NOT_YET
	end
	local policy = Policy.cached(player)
	if entry.PaidRandom and policy.PaidRandomRestricted then
		-- the player paid: granted anyway (a client can prompt any product itself)
		local why = if policy.Known then "the player's policy restricts them" else "the player's policy isn't known yet"
		offPolicy(player.UserId, productId, id, `{entry.Key} is a paid random item and {why}; granted`)
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
		offPolicy(player.UserId, productId, id, `the {entry.Grant} handler can't take {entry.Key} yet`)
		return NOT_YET
	end
	local log = data.PurchaseLog
	if type(log) ~= "table" then
		log = {}
		data.PurchaseLog = log
	end
	log[id] = { Product = entry.Key, At = os.time() }
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

-- The player left: drop their session's pass answers.
local function forget(player: Player)
	passOwned[player] = nil
	bought[player] = nil
	joinOwned[player] = nil
	checked[player] = nil
end

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
	-- replaces warn for the off-policy and gate lines
	setLog = function(fn: (string) -> ())
		logLine = fn
	end,
	checkAll = checkAll,
	purchaseFinished = onPassPurchaseFinished,
	-- what PlayerRemoving does (a later load of the same fake player is a new session)
	forget = forget,
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
		table.clear(bought)
		table.clear(joinOwned)
		table.clear(logged)
		loggedCount = 0
		table.clear(checked)
		logLine = function(text: string)
			warn(text)
		end
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
	-- grant handlers register in their own services' init() (the "Perks" passes here);
	-- the checks run after the loads
	MonetizationService.registerPerks()
	DataService.onLoaded(function(player: Player)
		task.spawn(checkAll, player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished)
	Players.PlayerRemoving:Connect(forget)
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

--[[
	Opens the receipts gate (src/server/Receipts.luau) only when every live
	pass and product has a handler, so a live id nothing grants is never
	sold; otherwise it stays (or goes) closed. Returns whether it is open.
	Also warns about a live coin pack while CoinPacksEnabled is false (its
	receipts would wait: never sold in game, but a client can prompt it).
]]
function MonetizationService.openGate(): boolean
	local missing = MonetizationService.unhandled()
	local open = #missing == 0
	Receipts.setReady(open)
	if not open then
		logLine(`[MonetizationService] receipts stay closed: no handler for {table.concat(missing, ", ")}`)
	end
	if not MonetizationConfig.coinsBuyable() then
		for _, entry in MonetizationConfig.List do
			if entry.CoinPack and MonetizationConfig.isLive(entry.Id) then
				logLine(`[MonetizationService] coin pack {entry.Key} has a live id but CoinPacksEnabled is false: its receipts wait`)
			end
		end
	end
	return open
end

function MonetizationService.start()
	-- exactly one ProcessReceipt callback in the game; set after every init() registered its handler
	MarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision
		return MonetizationService.decide(receipt)
	end
	MonetizationService.openGate()
end

return MonetizationService
