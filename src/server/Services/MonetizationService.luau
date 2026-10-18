--[[
	MonetizationService: the game's one MarketplaceService.ProcessReceipt
	callback (docs/COMPLIANCE.md "Process receipts safely"). Product ids:
	MonetizationConfig (id 0 = not created yet: never prompted, never matched).

	Grant handlers register by product Kind in their service's init():
	  MonetizationService.register("Hoverboard", function(player, data, product): boolean)
	A handler changes the save (no yields) and returns true when the product is
	granted (also when there was nothing new to give, e.g. a board already
	owned: the purchase is used up, never retried forever).

	A receipt is decided like this (MonetizationService.decide):
	  - the player is not in this server, or their save isn't loaded here
	    (DataService.get is nil: only the server holding the ProfileStore
	    session lock has it)                         -> NotProcessedYet
	  - the same PurchaseId is being decided right now -> NotProcessedYet
	  - the PurchaseId is already in data.Purchases  -> PurchaseGranted, once
	    the save holding it went through (granted here but the save failed:
	    save again first; still failing -> NotProcessedYet)
	  - unknown product or no handler, or the handler refuses -> NotProcessedYet
	  - else: grant, data.Purchases[PurchaseId] = os.time(), PurchaseCount + 1,
	    DataService.changed, DataService.saveNow; PurchaseGranted only when the
	    save succeeded, else NotProcessedYet (Roblox calls again; the id is
	    already recorded, so the next call only retries the save)
	Never grants from PromptProductPurchaseFinished. DataService keeps the
	Purchases record bounded (the last 100 ids).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

export type Grant = (player: Player, data: { [string]: any }, product: MonetizationConfig.Product) -> boolean

local grants: { [string]: Grant } = {}
-- purchase ids granted in this server whose save hasn't gone through yet
local unsaved: { [string]: boolean } = {}
-- purchase ids being decided right now (Roblox may call again while a save yields)
local inFlight: { [string]: boolean } = {}
local findPlayer: (userId: number) -> Player? = function(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- Registers the grant handler of a product Kind (MonetizationConfig.Product.Kind).
function MonetizationService.register(kind: string, grant: Grant)
	grants[kind] = grant
end

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
	local product = MonetizationConfig.byId(productId)
	local grant = if product then grants[product.Kind] else nil
	if not product or not grant then
		warn(`[MonetizationService] no product / handler for product id {tostring(productId)}`)
		return NOT_YET
	end
	-- grant and record with no yield in between
	if not grant(player, data, product) then
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

-- Internals for the Lune tests only (tests/MonetizationService.spec.luau).
MonetizationService._test = {
	setFindPlayer = function(fn: (number) -> Player?)
		findPlayer = fn
	end,
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
		findPlayer = function(userId: number): Player?
			return Players:GetPlayerByUserId(userId)
		end
	end,
	grants = grants,
}

function MonetizationService.init()
	-- grant handlers register in their own services' init()
end

function MonetizationService.start()
	-- exactly one ProcessReceipt callback in the game; set after every init() registered its handler
	MarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision
		return MonetizationService.decide(receipt)
	end
end

return MonetizationService
