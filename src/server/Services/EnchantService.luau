--[[
	EnchantService: the Enchant shop (step 6, EnchantConfig) at the rune
	table in town (tag EnchantCounter, a BasePart: the table top).

	- The counter: this service adds an "Enchant" prompt at runtime on the
	  customer side (-Z) of the table top; it opens the enchant view
	  (OpenUI "Enchant" { Counter }).
	- EnchantAction (Net, rate limited) (action, arg):
	    "Buy"  { Id, Currency = "Coins" | "Shards" | "Robux", Tier }: the
	           next tier of an enchant. Tier must be the tier the card shows
	           being bought (= owned + 1; EnchantConfig.quote, "Stale"
	           otherwise), so a double tap never buys two tiers. Only within
	           EnchantConfig.Range of an EnchantCounter ("TooFar"; the client
	           closes the view nearer than that). Coins go through
	           EconomyService.spend, shards through src/server/Shards.luau.
	           "Robux" (the two Mythics' 20 R$ game passes) is answered with
	           PurchasePrompt (BoostService.promptPurchase: "ComingSoon"
	           while the pass id is 0) and NEVER granted here (step 8 grants
	           a pass's enchant on join and after the purchase).
	           A newly bought enchant goes into the first free open slot.
	    "Slot" { Slot = 1..MaxSlots, Id = an owned enchant id, or nil / ""
	           to empty the slot } (EnchantConfig.setSlot): free, anywhere.
	  Every request the server reads gets one ActionResult { Action =
	  "Enchant", Op, Ok, Reason?, Id?, Level? } (Level: the new tier after a
	  buy), except a valid Robux buy (PurchasePrompt). A successful buy also
	  sends a "Reward" toast; every change ends with DataService.changed.
	- Odds boosters (EnchantConfig.OddsBoost: Lucky, Prospector,
	  Starbreaker) change the odds of random results: the client's card
	  shows the new odds in numbers (BoostConfig.preview with
	  EnchantConfig.nextDelta) before any buy. Buying one is a paid random
	  item with Robux (Starbreaker's pass) and, while coins can be bought
	  with Robux, with coins / shards too (EnchantConfig.isPaidRandom): for
	  those the player's policy (src/server/Policy.luau, may yield) is read
	  BEFORE the quote / spend / write step, and restricted players get
	  "Restricted" (the client hides those buttons).
	- Atomic: after the policy read nothing yields: quote, spend, grant and
	  slot happen in one step, and the record's tables are made before the
	  price is taken, so nothing can fail after the payment.
	- The effects reach the game through src/server/Bonuses.luau: the
	  built-in "Enchants" provider (EnchantConfig.stats of the open slots);
	  this service registers the same provider under the same name (counted
	  once).
	- Coming soon: Prospector, Golem Bond and Magnetism are refused with
	  "ComingSoon" while the package that reads their effect (artifacts,
	  golems, the Ore Magnet) isn't in the game (BoostService.comingSoon).
	- EnchantService.onBought(callback): stats / analytics / tutorial hooks,
	  (player, enchantId, tier, currency) after every paid buy.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnchantConfig = require(Shared.Config.EnchantConfig)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Guard = require(script.Parent.Parent.Guard)
local Policy = require(script.Parent.Parent.Policy)
local Shards = require(script.Parent.Parent.Shards)
local BoostService = require(script.Parent.BoostService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local EnchantService = {}

export type BoughtCallback = (Player, string, number, string) -> ...any

EnchantService.Tag = EnchantConfig.Tag
EnchantService.Range = EnchantConfig.Range
EnchantService.PromptName = "EnchantPrompt"
EnchantService.PointName = "EnchantPromptPoint"

local PROMPT_DISTANCE = 12
local MAX_PAYLOAD = 6
local MAX_ID_LENGTH = 32

local counters: { BasePart } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local boughtCallbacks: { BoughtCallback } = {}

-- Listeners: (player, enchantId, newTier, currency) after every paid buy.
function EnchantService.onBought(callback: BoughtCallback)
	table.insert(boughtCallbacks, callback)
end

---------------------------------------------------------------- range

-- Distance from a point to the surface of a part's box (0 inside).
local function distanceToPart(part: BasePart, position: Vector3): number
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The EnchantCounter the player stands at (within `range`), or nil.
function EnchantService.counterNear(player: Player, range: number): BasePart?
	local root = Guard.rootPart(player)
	if not root then
		return nil
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, counter in counters do
		if counter.Parent then
			local distance = distanceToPart(counter, root.Position)
			if distance <= range and distance < bestDistance then
				best, bestDistance = counter, distance
			end
		end
	end
	return best
end

---------------------------------------------------------------- answers

local function answer(player: Player, op: string, ok: boolean, reason: string?, id: string?, level: number?)
	Net.fire("ActionResult", player, { Action = "Enchant", Op = op, Ok = ok, Reason = reason, Id = id, Level = level })
end

-- The toast after a buy: "Lucky II bought and put in slot 2!"
function EnchantService.boughtText(id: string, tier: number, slot: number?): string
	local enchant = EnchantConfig.ById[id]
	local name = if enchant then enchant.Name else id
	local tiers = EnchantConfig.tiers(id)
	local full = if tiers > 1 then `{name} {EnchantConfig.TierNames[tier] or tostring(tier)}` else name
	if slot then
		return `{full} is in slot {slot} of your blaster!`
	end
	if tier > 1 then
		return `{full}: your enchant got stronger!`
	end
	return `{full} bought! Put it in a slot to use it.`
end

-- The record, made (with its tables) when it's missing or broken.
local function enchantsOf(data: { [string]: any }): { [string]: any }
	local enchants = data.Enchants
	if type(enchants) ~= "table" then
		enchants = {}
		data.Enchants = enchants
	end
	if type(enchants.Owned) ~= "table" then
		enchants.Owned = {}
	end
	if type(enchants.Slots) ~= "table" then
		local slots = {}
		for i = 1, EnchantConfig.MaxSlots do
			slots[i] = ""
		end
		enchants.Slots = slots
	end
	return enchants
end

-- Is `id` in one of the open slots?
local function slotOf(enchants: { [string]: any }, blasterLevel: any, id: string): number?
	local slots = enchants.Slots
	if type(slots) ~= "table" then
		return nil
	end
	for i = 1, EnchantConfig.unlockedSlots(blasterLevel) do
		if slots[i] == id then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------- buying

--[[
	EnchantAction "Buy" for a player at a counter: returns (ok, reason?,
	tier?, slot?). Reasons: EnchantConfig.Reasons codes ("Robux" = a valid
	Robux buy: the caller prompts). No range check here. The policy read
	(only for a paid random buy) is the only yield, before the quote.
]]
function EnchantService.buy(player: Player, id: any, currency: any, tier: any): (boolean, string?, number?, number?)
	if type(id) ~= "string" or not EnchantConfig.ById[id] or not DataService.get(player) then
		return false, "BadItem", nil, nil
	end
	if type(currency) ~= "string" or not EnchantConfig.Currencies[currency] then
		return false, "BadCurrency", nil, nil
	end
	-- an enchant whose effect only a package that isn't in the game yet reads
	if BoostService.comingSoon(id) then
		return false, "ComingSoon", nil, nil
	end
	local restricted = false
	if EnchantConfig.isPaidRandom(id, currency) then
		restricted = Policy.paidRandomRestricted(player)
	end
	local data = DataService.get(player)
	if not data then
		return false, "BadItem", nil, nil
	end
	-- from here on: no yield
	local price, reason = EnchantConfig.quote(data.Enchants, id, currency, tier, restricted)
	if price == nil then
		return false, reason or "BadItem", nil, nil
	end
	local enchants = enchantsOf(data)
	local before = EnchantConfig.tierOf(enchants, id)
	if currency == "Coins" then
		if not EconomyService.spend(player, price, "Enchant:" .. id) then
			return false, "NoCoins", nil, nil
		end
	elseif not Shards.spend(data, price) then
		return false, "NoShards", nil, nil
	end
	local newTier = EnchantConfig.grant(enchants, id)
	-- a new enchant goes straight into the first free open slot
	local slot = slotOf(enchants, data.BlasterLevel, id)
	if before == 0 and not slot then
		local free = EnchantConfig.firstFreeSlot(enchants, data.BlasterLevel)
		if free and EnchantConfig.setSlot(enchants, data.BlasterLevel, free, id) then
			slot = free
		end
	end
	DataService.changed(player)
	for _, callback in boughtCallbacks do
		task.spawn(callback, player, id, newTier, currency)
	end
	return true, nil, newTier, if before == 0 then slot else nil
end

local function onBuy(player: Player, args: { [any]: any }?)
	local id = if args then Guard.string(args.Id, MAX_ID_LENGTH) else nil
	local currency = if args then Guard.string(args.Currency, 8) else nil
	local tier = if args then Guard.integer(args.Tier, 1, 99) else nil
	if not id or not EnchantConfig.ById[id] or not DataService.get(player) then
		answer(player, "Buy", false, "BadItem", id)
		return
	end
	if not EnchantService.counterNear(player, EnchantService.Range) then
		answer(player, "Buy", false, "TooFar", id)
		return
	end
	local ok, reason, newTier, slot = EnchantService.buy(player, id, currency, tier)
	if reason == "Robux" then
		local product = EnchantConfig.ById[id].Product
		if product then
			BoostService.promptPurchase(player, product, false, false)
			return
		end
		reason = "BadCurrency"
	end
	if not ok or not newTier then
		answer(player, "Buy", false, reason or "BadItem", id)
		return
	end
	answer(player, "Buy", true, nil, id, newTier)
	Net.fire("Notify", player, { Text = EnchantService.boughtText(id, newTier, slot), Kind = "Reward" })
end

-- EnchantAction "Slot" { Slot, Id }: free, anywhere.
local function onSlot(player: Player, args: { [any]: any }?)
	local data = DataService.get(player)
	local rawId = if args then args.Id else nil
	local id = if rawId == nil then "" else Guard.string(rawId, MAX_ID_LENGTH)
	local slot = if args then Guard.integer(args.Slot, 1, EnchantConfig.MaxSlots) else nil
	if not data or id == nil then
		answer(player, "Slot", false, "BadItem", nil)
		return
	end
	if slot == nil then
		answer(player, "Slot", false, "BadSlot", id)
		return
	end
	-- validated before anything is written (a broken record is only rebuilt for a real change)
	if slot > EnchantConfig.unlockedSlots(data.BlasterLevel) then
		answer(player, "Slot", false, "Locked", id)
		return
	end
	if id ~= "" then
		if not EnchantConfig.ById[id] then
			answer(player, "Slot", false, "BadItem", id)
			return
		end
		if EnchantConfig.tierOf(data.Enchants, id) < 1 then
			answer(player, "Slot", false, "NotOwned", id)
			return
		end
	end
	local ok, reason = EnchantConfig.setSlot(enchantsOf(data), data.BlasterLevel, slot, id)
	if not ok then
		answer(player, "Slot", false, reason or "BadSlot", id)
		return
	end
	DataService.changed(player)
	answer(player, "Slot", true, nil, id)
end

local function onEnchantAction(player: Player, action: any, payload: any)
	local args = Guard.table(payload, MAX_PAYLOAD)
	if action == "Buy" then
		onBuy(player, args)
	elseif action == "Slot" then
		onSlot(player, args)
	else
		local id = if args then Guard.string(args.Id, MAX_ID_LENGTH) else nil
		answer(player, if type(action) == "string" and #action <= 16 then action else "", false, "BadItem", id)
	end
end

---------------------------------------------------------------- the counter

local function openView(player: Player, counter: BasePart)
	if not DataService.get(player) or not EnchantService.counterNear(player, EnchantService.Range) then
		return
	end
	Net.fire("OpenUI", player, "Enchant", { Counter = counter })
end

-- Forgets counters that left the game (the lobby was rebuilt).
local function pruneCounters()
	for i = #counters, 1, -1 do
		local counter = counters[i]
		if not counter.Parent then
			table.remove(counters, i)
			hooked[counter] = nil
		end
	end
end

local function hookCounter(counter: Instance)
	pruneCounters()
	if hooked[counter] or not counter:IsA("BasePart") then
		return
	end
	hooked[counter] = true
	local part = counter :: BasePart
	table.insert(counters, part)
	local old = part:FindFirstChild(EnchantService.PointName)
	if old then
		old:Destroy()
	end
	-- the prompt sits on the customer side (-Z) of the table top
	local point = Instance.new("Attachment")
	point.Name = EnchantService.PointName
	point.CFrame = CFrame.new(0, part.Size.Y / 2 + 0.6, -part.Size.Z / 2)
	point.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = EnchantService.PromptName
	prompt.ActionText = "Enchant"
	prompt.ObjectText = "Blaster Enchants"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = point
	prompt.Triggered:Connect(function(player: Player)
		openView(player, part)
	end)
end

local function unhookCounter(counter: Instance)
	local index = table.find(counters, counter :: any)
	if index then
		table.remove(counters, index)
	end
	hooked[counter] = nil
	local point = counter:FindFirstChild(EnchantService.PointName)
	if point then
		point:Destroy()
	end
	pruneCounters()
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/EnchantService.spec.luau).
EnchantService._test = {
	enchantAction = onEnchantAction,
	hookCounter = hookCounter,
	unhookCounter = unhookCounter,
	open = openView,
	counters = function(): { BasePart }
		return table.clone(counters)
	end,
	reset = function()
		table.clear(counters)
		table.clear(boughtCallbacks)
	end,
}

function EnchantService.init()
	Net.on("EnchantAction", onEnchantAction)
	-- the slotted enchants' stats (the same provider as Bonuses' built-in
	-- one, under the same name: counted once)
	Bonuses.register("Enchants", function(_player, data, _now)
		return EnchantConfig.stats(data.Enchants, data.BlasterLevel)
	end)
end

function EnchantService.start()
	-- the map is built in WorldService.init, so the rune table exists by now
	for _, instance in CollectionService:GetTagged(EnchantService.Tag) do
		hookCounter(instance)
	end
	CollectionService:GetInstanceAddedSignal(EnchantService.Tag):Connect(hookCounter)
	CollectionService:GetInstanceRemovedSignal(EnchantService.Tag):Connect(unhookCounter)
end

return EnchantService
