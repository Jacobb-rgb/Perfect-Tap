--[[
	BoostService: the luck boosts (step 6, BoostConfig): Triple Lucky
	(golem capsules) and Hexa Lucky (mining), bought in the Boosts view
	(BoostView: the HUD chip under the coins, later the side menu).

	- BoostAction (Net, rate limited) (action, arg):
	    "BuyCoins" { Id: a BoostConfig.CoinOffers id }  coins top a boost up:
	               BoostConfig.coinQuote (the price at the player's blaster
	               level; "NoEffect" when no mine the player can reach has a
	               Rare+ ore (Hexa Lucky), "CoinLimit" while CoinBuyBelow or
	               more is left, "Full" past MaxStackSeconds), then the coins
	               are spent and BoostConfig.extend(capped = true) writes the
	               new until-time, all in one step with no yield.
	    "BuyRobux" { Id: a BoostConfig.RobuxOffers id }  answered with
	               PurchasePrompt { Product, Status } (promptPurchase:
	               "ComingSoon" while the product id is 0 or step 8's
	               receipts gate (src/server/Receipts.luau) is off, "Restricted" where
	               paid random items are restricted, "Full" when the pack
	               would pass MaxStackSeconds, else MarketplaceService's
	               prompt and "Prompted"). NEVER granted here: step 8's
	               ProcessReceipt adds the time (the "Boost" handler,
	               registerGrants: BoostConfig.extend uncapped).
	  Every other request the server reads gets one ActionResult
	  { Action = "Boost", Op, Ok, Reason?, Id? } (Reason: a
	  BoostConfig.Reasons code); a successful buy also pushes State
	  (DataService.changed) and a "Reward" toast.
	- Paid random items: a Robux pack always is one, a coin offer only while
	  coins can be bought with Robux (BoostConfig.isPaidRandom). For those
	  the player's policy (src/server/Policy.luau, PolicyService) is read
	  BEFORE the quote / spend / write step (it may yield on the first
	  call); restricted players get "Restricted" (the client hides them).
	  Policy.prefetch runs for every player on join, so the client's
	  PaidRandomRestricted attribute is known early.
	- Expiry: a running boost ends by the clock (data.Boosts holds
	  os.time() seconds), not by a save change, so this service pushes a
	  fresh State (Bonuses invalidated) right after each boost runs out and
	  tells the player with a toast. One timer per player, for the soonest
	  expiry; every save change re-plans it.
	- promptPurchase(player, key, owned?, full?) is the one place this
	  package asks MarketplaceService for a prompt (EnchantService uses it
	  for the Mythic enchants' game passes too).
	- The effects reach the game through src/server/Bonuses.luau (the
	  built-in "Boosts" provider reads data.Boosts; this service registers
	  the same provider under the same name, so it is counted once).
	- Coming soon: an effect only another package reads (Triple Lucky: the
	  capsules; the Prospector / Golem Bond / Magnetism enchants: artifacts,
	  golems, the Ore Magnet) can't be bought until that package's service
	  is in the game (BoostService.Consumers, comingSoon): the server answers
	  "ComingSoon" and the views show it (the ReplicatedStorage attribute
	  BoostService.SoonAttribute lists those ids), so nobody pays for an
	  effect nothing uses yet. Rewards (add) are never held back.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local BoostConfig = require(Shared.Config.BoostConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local Policy = require(script.Parent.Parent.Policy)
local Receipts = require(script.Parent.Parent.Receipts)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)

local BoostService = {}

local MAX_PAYLOAD = 4
local MAX_ID_LENGTH = 32
-- seconds after an expiry before the State push (the clocks may differ a little)
local EXPIRY_GRACE = 0.5

-- Swappable for the Lune tests.
local clock: () -> number = os.time
local delay: (seconds: number, fn: () -> ()) -> () = function(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end
local prompter: (player: Player, product: MonetizationConfig.Product) -> () = function(player, product)
	if product.Kind == "GamePass" then
		MarketplaceService:PromptGamePassPurchase(player, product.Id)
	else
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end
end

-- player -> the expiry (os.time() second) the pending timer is for (weak
-- keys: a player who left is never kept by a late plan)
local planned: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

--[[
	The boosts (BoostConfig kinds) and enchants (EnchantConfig ids) whose
	effect only another package's service reads (steps 6 and 7 are built in
	parallel), and that service's module name in Services. Until it is in
	the game they are coming soon (see the header).
]]
BoostService.Consumers = {
	TripleLucky = "CapsuleService", -- reads Bonuses.tripleLucky when a capsule opens
	Prospector = "ArtifactService", -- listens to MiningService.onArtifactRoll
	GolemBond = "GolemService", -- the equipped golems' bonuses
	Magnetism = "GearService", -- the Ore Magnet gear it adds to
} :: { [string]: string }
-- ReplicatedStorage attribute: the coming-soon ids, comma-separated (BoostView.soonSet reads it)
BoostService.SoonAttribute = "TerraForgeComingSoon"

-- Swappable for the Lune tests: is the service module `name` in the game?
local function realHasService(name: string): boolean
	local services = script.Parent
	return services ~= nil and services:FindFirstChild(name) ~= nil
end
local hasService: (name: string) -> boolean = realHasService

---------------------------------------------------------------- answers

local function answer(player: Player, op: string, ok: boolean, reason: string?, id: string?)
	Net.fire("ActionResult", player, { Action = "Boost", Op = op, Ok = ok, Reason = reason, Id = id })
end

-- "5:00", "1h 05m"
local function timeText(seconds: number): string
	return Format.seconds(seconds)
end

--[[
	Asks MarketplaceService to show the purchase prompt for MonetizationConfig
	product `key`, or says why not, and answers the client with
	PurchasePrompt { Product = key, Status }. `owned` / `full` as in
	MonetizationConfig.promptStatus. The player's paid-random policy is read
	only for a PaidRandom product (it may yield on the first call). "Prompt"
	becomes "ComingSoon" until step 8 turns the receipts gate on
	(Receipts.setReady). Returns the Status sent. Nothing is ever granted
	here (step 8).
]]
function BoostService.promptPurchase(player: Player, key: string, owned: boolean?, full: boolean?): string
	local product = MonetizationConfig.get(key)
	local restricted = false
	if product and product.PaidRandom then
		restricted = Policy.paidRandomRestricted(player)
	end
	-- the one receipts gate: nothing is prompted before step 8 grants receipts
	-- and passes (a live id would take Robux and give nothing)
	local status = Receipts.gate(MonetizationConfig.promptStatus(key, restricted, owned, full))
	if status == "Prompt" and product then
		local ok, err = pcall(function()
			prompter(player, product)
		end)
		if ok then
			status = "Prompted"
		else
			warn(`[BoostService] purchase prompt for {key} failed: {err}`)
			status = "Unknown"
		end
	end
	if player.Parent then
		Net.fire("PurchasePrompt", player, { Product = key, Status = status })
	end
	return status
end

-- Is boost kind / enchant `id` coming soon (its consumer isn't in the game yet)?
function BoostService.comingSoon(id: any): boolean
	local service = if type(id) == "string" then BoostService.Consumers[id] else nil
	return service ~= nil and not hasService(service)
end

-- The coming-soon ids, sorted.
function BoostService.soonIds(): { string }
	local list: { string } = {}
	for id in BoostService.Consumers do
		if BoostService.comingSoon(id) then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

---------------------------------------------------------------- expiry

-- Plans the State push for the player's soonest boost expiry (re-planned
-- on every save change; a timer whose expiry is no longer the planned one
-- does nothing).
local function plan(player: Player)
	-- a save change after the player left (a beforeRelease callback) plans nothing
	if not player.Parent then
		planned[player] = nil
		return
	end
	local data = DataService.get(player)
	local now = clock()
	local expiry = if data then BoostConfig.nextExpiry(data.Boosts, now) else nil
	if expiry == nil then
		planned[player] = nil
		return
	end
	if planned[player] == expiry then
		return
	end
	planned[player] = expiry
	delay(math.max(0, expiry - now) + EXPIRY_GRACE, function()
		if planned[player] ~= expiry then
			return
		end
		planned[player] = nil
		if not player.Parent then
			return
		end
		local current = DataService.get(player)
		if not current then
			return
		end
		-- the boosts that ended at this moment (for the toast)
		local names = {}
		for _, kindId in BoostConfig.KindIds do
			if BoostConfig.untilOf(current.Boosts, kindId) == expiry then
				table.insert(names, BoostConfig.Kinds[kindId].Name)
			end
		end
		Bonuses.invalidate(player)
		StateService.push(player)
		if #names > 0 then
			Net.fire("Notify", player, { Text = `{table.concat(names, " and ")} ran out.`, Kind = "Info" })
		end
		plan(player)
	end)
end
BoostService.plan = plan

---------------------------------------------------------------- granting

--[[
	Adds `seconds` of boost `kindId` to the player's save (from now, or from
	the end of the running one) and pushes State. `capped`: never past
	MaxStackSeconds from now (coin buys, the wheel); a Robux receipt (step 8)
	passes false: paid time is never lost. Returns the new until-time, or
	nil when the save isn't loaded or the kind is unknown. No yield.
]]
function BoostService.add(player: Player, kindId: string, seconds: number, capped: boolean): number?
	local data = DataService.get(player)
	if not data or not BoostConfig.Kinds[kindId] then
		return nil
	end
	local boosts = data.Boosts
	if type(boosts) ~= "table" then
		boosts = {}
		data.Boosts = boosts
	end
	local untilTime = BoostConfig.extend(boosts, kindId, seconds, clock(), capped)
	DataService.changed(player)
	return untilTime
end

--[[
	The "Boost" receipt handler (MonetizationService.register; step 8
	contract): the product's Seconds of its Boost kind, added uncapped
	(BoostConfig.extend capped = false: paid time is never lost) from now or
	from the end of the running boost. False (nothing written) for an entry
	without a known kind or seconds. No yield.
]]
local function grantBoost(player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local kindId = entry.Boost
	local seconds = entry.Seconds
	local kind = if kindId then BoostConfig.Kinds[kindId] else nil
	if not kind or not kindId or type(seconds) ~= "number" or seconds <= 0 then
		return false
	end
	local boosts = data.Boosts
	if type(boosts) ~= "table" then
		boosts = {}
		data.Boosts = boosts
	end
	local now = clock()
	local untilTime = BoostConfig.extend(boosts, kindId, seconds, now, false)
	Net.fire("Notify", player, {
		Text = `{kind.Name}: +{timeText(seconds)} ({timeText(untilTime - now)} left). Thank you!`,
		Kind = "Reward",
	})
	return true
end

-- Registers the "Boost" receipt handler (init(); idempotent).
function BoostService.registerGrants()
	MonetizationService.register("Boost", grantBoost)
end

---------------------------------------------------------------- requests

-- BoostAction "BuyCoins" { Id }.
local function buyCoins(player: Player, id: string)
	local offer = BoostConfig.OfferById[id]
	if not offer or offer.Product ~= nil or not DataService.get(player) then
		answer(player, "BuyCoins", false, "BadOffer", id)
		return
	end
	if BoostService.comingSoon(offer.Boost) then
		answer(player, "BuyCoins", false, "ComingSoon", id)
		return
	end
	-- the policy (may yield) is read before the quote / spend / write step
	if BoostConfig.isPaidRandom(id) and Policy.paidRandomRestricted(player) then
		answer(player, "BuyCoins", false, "Restricted", id)
		return
	end
	local data = DataService.get(player)
	if not data then
		answer(player, "BuyCoins", false, "BadOffer", id)
		return
	end
	-- from here on: no yield
	local now = clock()
	local vip = Perks.has(player, "ForgeVip")
	local price, reason = BoostConfig.coinQuote(data.Boosts, id, data.BlasterLevel, vip, now, BlasterData.priceLevel(data))
	if price == nil then
		answer(player, "BuyCoins", false, reason or "BadOffer", id)
		return
	end
	local boosts = data.Boosts
	if type(boosts) ~= "table" then
		boosts = {}
		data.Boosts = boosts
	end
	if not EconomyService.spend(player, price, "Boost:" .. id) then
		answer(player, "BuyCoins", false, "NoCoins", id)
		return
	end
	local untilTime = BoostConfig.extend(boosts, offer.Boost, offer.Seconds, now, true)
	DataService.changed(player)
	answer(player, "BuyCoins", true, nil, id)
	local kind = BoostConfig.Kinds[offer.Boost]
	Net.fire("Notify", player, {
		Text = `{kind.Name}: +{timeText(offer.Seconds)} ({timeText(untilTime - now)} left)`,
		Kind = "Reward",
	})
end

-- BoostAction "BuyRobux" { Id }: answered with PurchasePrompt (refusals
-- before the prompt step: ActionResult).
local function buyRobux(player: Player, id: string)
	local offer = BoostConfig.OfferById[id]
	local data = DataService.get(player)
	local product = if offer then offer.Product else nil
	if not offer or not product or not data then
		answer(player, "BuyRobux", false, "BadOffer", id)
		return
	end
	if BoostService.comingSoon(offer.Boost) then
		answer(player, "BuyRobux", false, "ComingSoon", id)
		return
	end
	if not BoostConfig.hasEffect(offer.Boost, data.BlasterLevel, Perks.has(player, "ForgeVip")) then
		answer(player, "BuyRobux", false, "NoEffect", id)
		return
	end
	local full = not BoostConfig.canExtend(data.Boosts, offer.Boost, offer.Seconds, clock())
	BoostService.promptPurchase(player, product, false, full)
end

local function onBoostAction(player: Player, action: any, payload: any)
	local args = Guard.table(payload, MAX_PAYLOAD)
	local id = if args then Guard.string(args.Id, MAX_ID_LENGTH) else nil
	if action == "BuyCoins" then
		buyCoins(player, id or "")
	elseif action == "BuyRobux" then
		buyRobux(player, id or "")
	else
		answer(player, if type(action) == "string" and #action <= 16 then action else "", false, "BadOffer", id)
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/BoostService.spec.luau).
BoostService._test = {
	boostAction = onBoostAction,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setDelay = function(fn: (number, () -> ()) -> ())
		delay = fn
	end,
	setPrompter = function(fn: (Player, MonetizationConfig.Product) -> ())
		prompter = fn
	end,
	planned = function(player: any): number?
		return planned[player]
	end,
	setHasService = function(fn: (string) -> boolean)
		hasService = fn
	end,
	reset = function()
		clock = os.time
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end
		prompter = function(player, product)
			if product.Kind == "GamePass" then
				MarketplaceService:PromptGamePassPurchase(player, product.Id)
			else
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end
		end
		table.clear(planned)
		hasService = realHasService
	end,
}

function BoostService.init()
	-- what is coming soon is known once the services are loaded (the client reads it)
	ReplicatedStorage:SetAttribute(BoostService.SoonAttribute, table.concat(BoostService.soonIds(), ","))
	Net.on("BoostAction", onBoostAction)
	-- step 8: Triple / Hexa Lucky receipts (uncapped paid time)
	BoostService.registerGrants()
	-- the running boosts' stats (the same provider as Bonuses' built-in one,
	-- under the same name: counted once)
	Bonuses.register("Boosts", function(_player, data, now)
		return BoostConfig.stats(data.Boosts, now)
	end)
	DataService.onChanged(plan)
	DataService.onLoaded(function(player: Player)
		plan(player)
	end)
end

function BoostService.start()
	-- the paid-random policy is asked for early, so the client knows what to show
	Players.PlayerAdded:Connect(Policy.prefetch)
	for _, player in Players:GetPlayers() do
		Policy.prefetch(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		planned[player] = nil
	end)
end

return BoostService
