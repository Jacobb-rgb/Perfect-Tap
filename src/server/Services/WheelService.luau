--[[
	WheelService: the daily wheel of fortune (step 7, SPIN & WIN in town;
	every rule and number lives in Shared/Config/WheelConfig): the free
	daily spin and the spins bought with Robux (owner 2026-10-20).

	- EmberChest (tag WheelConfig.Tag, the chest at the top of the SPIN & WIN
	  stairs inside the SpinWheel model): this service adds a "Spin & Win"
	  prompt (E / gamepad Y) on it; it opens the wheel screen (OpenUI "Wheel"
	  { Chest }). The screen shows the 8 segments with their exact odds
	  (and the ore prize's and the capsules' own odds) and the countdown.
	  The spin itself works from anywhere (the HUD's FREE SPIN! chip).
	- WheelAction ("Spin"): when the free spin is ready
	  (WheelConfig.ready(data.Wheel.NextSpinAt)) or the player holds bought
	  spins (data.Wheel.Spins):
	    1. the paid-random policy (src/server/Policy.luau; it may yield on the
	       first ask, so it is asked BEFORE the check and write step): players
	       who can't buy any capsule spin the wheel with Substitutes
	       (WheelConfig.segments(CapsuleConfig.allRestricted(restricted)));
	    2. with no yield from here on: check again; the FREE spin first (save
	       NextSpinAt = now + CooldownSeconds), else ONE bought spin
	       (Spins - 1; it ignores the cooldown and leaves NextSpinAt alone;
	       refused with "Restricted" where paid random items are restricted,
	       and with "InventoryFull" when the golem inventory has no room: a
	       bought spin never swaps a capsule prize for coins; the bought
	       spins stay in the save), then Stats.WheelSpins + 1, all
	       BEFORE granting; pick the segment (a seeded Random), grant the
	       prize, DataService.changed;
	    3. WheelResult (Net) tells the client where the wheel stops (Paid,
	       Spins = bought spins left).
	  No spin to use (or no save): ActionResult { Action = "Wheel", Op =
	  "Spin", Ok = false, Reason = "NotReady" | "Restricted" |
	  "InventoryFull" }. Junk actions
	  are dropped. Two quick Spins can't both pass: the check and the write
	  happen in one step. The spin used and the prize live in the same save,
	  so a crash before the next autosave loses both together (never a prize
	  without the cooldown or the bought spin).
	- WheelAction ("Buy", { Count = 1 | 5 | 10 }): the BUY SPINS row's
	  product (WheelConfig.Packs -> MonetizationConfig WheelSpins1/5/10) is
	  prompted through BoostService.promptPurchase (the policy first: a paid
	  random item, "Restricted" where restricted; "Full" when the spins held
	  would pass WheelConfig.MaxSpins or the golem inventory is full (a
	  bought spin couldn't be used); "ComingSoon" while the id is 0 or the
	  receipts gate is shut), answered with PurchasePrompt { Product, Status }.
	  Nothing is granted here. Junk counts are dropped.
	- The "WheelSpins" receipt handler (MonetizationService.register,
	  registerGrants in init): Spins += the product's Spins, never refused
	  and never cut (MaxSpins is only the prompt's "Full"; a receipt of a
	  player who is restricted now still credits: MonetizationService logs
	  it), a thank-you Notify; MonetizationService saves and records it.
	- WheelAction ("Reveal"): the wheel screen showed a capsule prize's card
	  (the client sends it only while the screen is open): the server sends
	  that spin's CapsuleResult { Free = true } once, so the capsule opening
	  (capsule package) plays after the wheel, and never for a player who
	  closed the screen (the golem is in their inventory either way; the
	  toast told them). It grants nothing. Kept RevealSeconds, then dropped.
	  Only when nobody sent that CapsuleResult yet (see FreeCapsules).
	- Prizes (WheelConfig):
	    Coins    EconomyService.award(WheelConfig.coins(segment, podium income))
	    Boost    BoostConfig.extend(data.Boosts, kind, Seconds, now, capped)
	             (the save is the boosts' only state: whatever runs the
	             boosts reads data.Boosts; Bonuses drops its cache on the
	             data change); WheelResult.Seconds = the seconds really added.
	             A boost already near its MaxStackSeconds cap: the seconds
	             that didn't fit are paid as coins (boostFallbackCoins: that
	             share of the Coins segment's prize), WheelResult.Coins
	    Capsule  one capsule of that kind opened for free right away: through
	             CapsuleService.grantFree(player, capsule, 1, quiet = true)
	             when the capsule package is in the place (its own side
	             effects then run too; FreeCapsules below), else here
	             (CapsuleConfig.roll with the player's Triple Lucky +
	             GolemConfig.add, Stats.CapsulesOpened + 1); WheelResult.Golem.
	             The opening plays on "Reveal" (above). Full golem inventory:
	             FallbackShare coins (WheelConfig.capsuleFallbackCoins),
	             WheelResult.Coins + Full = true; a failed opening pays the
	             same coins (no Full) and never rolls a second time
	    Ore      a dirty (Raw) Rare+ ore (WheelConfig.pickOre) into the Ore
	             Pen (PenService.store), Stats.WheelOres + 1 (TutorialConfig:
	             a wheel ore in the pen isn't ore the train brought home);
	             WheelResult.DirtyOre = true only, WHICH
	             ore stays secret until cleaned. Full pen: the expected raw
	             value (oreFallbackCoins); no candidate: the Coins segment's
	             coins (both as WheelResult.Coins)
	    Shards   Shards.add(data, Amount)
	  The free spin can't be bought; bought spins make the wheel a paid
	  random item (WheelConfig header): its odds are always shown, on the
	  wheel and in Details; no rewards for likes or favorites.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local PromptConfig = require(Shared.Config.PromptConfig)
local WheelConfig = require(Shared.Config.WheelConfig)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Guard = require(script.Parent.Parent.Guard)
local Policy = require(script.Parent.Parent.Policy)
local Shards = require(script.Parent.Parent.Shards)
local BoostService = require(script.Parent.BoostService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local PenService = require(script.Parent.PenService)
local PodiumService = require(script.Parent.PodiumService)

local WheelService = {}

WheelService.PromptName = "WheelPrompt"
WheelService.PointName = "WheelPromptPoint"
WheelService.PromptDistance = 12
-- seconds a capsule prize's opening waits for the client's "Reveal"
WheelService.RevealSeconds = 60

--[[
	The capsule package's free opening, when this place has it (its real
	contract, Capsules package step 7):
	  CapsuleService.grantFree(player, capsuleId, count?, quiet?, paid?)
	      -> (Result?, reason?)
	opens `count` (default 1) capsules of that kind with no price and no
	yield (the player's Triple Lucky counts; Stats.CapsulesOpened,
	DataService.changed and its own side effects) and returns its
	CapsuleResult { Capsule, Count, Golems = { { Id, Kind } }, Lucky,
	Free = true }, or nil + "InventoryFull" (no room) / "BadCapsule".
	`paid`: the prize of a BOUGHT spin: the golems are saved Paid = true
	and Locked (a golem from a Robux purchase), analytics Source "PaidSpin".
	The wheel calls grantFree(player, capsuleId, 1, true, result.Paid):
	  - QuietFree = true on the service: `quiet` is honored, the service
	    sends NO CapsuleResult; the wheel sends it on "Reveal" (after its
	    own prize card), so the opening never spoils the turning disc.
	  - no QuietFree (an older capsule package, which ignores `quiet`): the
	    service has already sent the CapsuleResult itself; the wheel never
	    sends it again (no double opening; the client closes the wheel
	    screen when a free opening starts).
	  - nil + "InventoryFull": the wheel's coin share instead (Full = true).
	  - any other reason, or an error: the coin share too, never a second
	    roll here (a partly done grant must not add a second golem).
	Only a place with no CapsuleService at all opens the capsule here
	(CapsuleConfig.roll + GolemConfig.add; a bought spin's golem Paid and
	Locked the same way).
]]
export type FreeCapsules = {
	grantFree: (player: Player, capsuleId: string, count: number?, quiet: boolean?, paid: boolean?) -> (any, any),
	QuietFree: boolean?,
}

export type Result = {
	Segment: number,
	Id: string,
	Kind: WheelConfig.PrizeKind,
	NextSpinAt: number,
	Amount: number?,
	Boost: string?,
	Seconds: number?,
	Capsule: string?,
	Golem: { Id: number, Kind: string }?,
	Lucky: boolean?,
	DirtyOre: boolean?,
	Coins: number?,
	Full: boolean?, -- a capsule prize paid as coins because the golem inventory was full
	Paid: boolean, -- a bought spin was used (else the free one)
	Spins: number, -- bought spins left
}

-- How a free capsule opened (openFree).
type Opened = {
	Golem: { Id: number, Kind: string }?,
	Lucky: boolean,
	Full: boolean, -- no golem: the inventory was full (else: the opening failed)
	Reveal: boolean, -- the wheel sends the CapsuleResult on "Reveal" (nobody sent it yet)
}

-- Swappable for the Lune tests.
local clock: () -> number = os.time
local rng: Random? = nil
local function nextRoll(): number
	local r = rng or Random.new()
	rng = r
	return r:NextNumber()
end
local random: () -> number = nextRoll
local timer: () -> number = os.clock
local capsules: FreeCapsules? = nil
local capsulesKnown = false -- looked up (capsules nil then: this place has none)

local hooked: { [Instance]: boolean } = {}
-- player -> the CapsuleResult waiting for "Reveal" and when it was won (timer())
local openings: { [Player]: { Payload: { [string]: any }, At: number } } = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function record(data: { [string]: any }, key: string): { [string]: any }
	local value = data[key]
	if type(value) ~= "table" then
		value = {}
		data[key] = value
	end
	return value
end

local function bump(data: { [string]: any }, stat: string)
	local stats = record(data, "Stats")
	local n = stats[stat]
	stats[stat] = (if finite(n) then n else 0) + 1
end

-- The player's podium income per second (0 when it can't be read).
local function incomeOf(player: Player, data: { [string]: any }): number
	local ok, value = pcall(PodiumService.incomeOf, player, data)
	return if ok and finite(value) and value > 0 then value else 0
end

local function award(player: Player, amount: number, result: Result)
	local coins = math.max(0, math.floor(amount))
	if coins > 0 then
		EconomyService.award(player, coins, "Wheel")
	end
	result.Coins = coins
end

-- The ore prize's context for this player (WheelConfig.OreContext).
function WheelService.oreContext(player: Player, data: { [string]: any }): WheelConfig.OreContext
	return {
		BlasterLevel = if finite(data.BlasterLevel) then data.BlasterLevel else 1,
		BestIncome = WheelConfig.bestIncome(data.Discovered),
	}
end

-- Coins for the boost seconds that didn't fit under BoostConfig.MaxStackSeconds:
-- that share of the Coins segment's prize at this income (0 when all fit).
function WheelService.boostFallbackCoins(segment: WheelConfig.Segment, added: number, incomePerSecond: number): number
	local wanted = segment.Seconds or 0
	if wanted <= 0 then
		return 0
	end
	local missing = math.clamp(wanted - math.max(0, added), 0, wanted)
	if missing <= 0 then
		return 0
	end
	local full = WheelConfig.coins(WheelConfig.ById.Coins, incomePerSecond)
	return math.floor(full * missing / wanted)
end

-- The capsule package's service with grantFree, when there is one (looked up once).
local function freeCapsules(): FreeCapsules?
	if capsulesKnown then
		return capsules
	end
	local module = script.Parent:FindFirstChild("CapsuleService")
	local found: FreeCapsules? = nil
	if module and module:IsA("ModuleScript") then
		local ok, service = pcall(require, module :: any)
		if ok and type(service) == "table" and type((service :: any).grantFree) == "function" then
			found = service :: any
		end
	end
	capsules = found
	capsulesKnown = true
	return found
end

-- The first golem of a CapsuleResult-like table (nil: none / malformed).
local function firstGolem(result: any): { Id: number, Kind: string }?
	local golems = if type(result) == "table" then result.Golems else nil
	local g = if type(golems) == "table" then golems[1] else nil
	if type(g) == "table" and type(g.Id) == "number" and type(g.Kind) == "string" then
		return { Id = g.Id, Kind = g.Kind }
	end
	return nil
end

-- Opens the wheel's capsule (see FreeCapsules above): through the capsule
-- package when this place has one (never a second roll here), else here.
-- `paid`: a bought spin's prize (the golem is saved Paid and Locked).
local function openFree(player: Player, data: { [string]: any }, capsuleId: string, paid: boolean): Opened
	local service = freeCapsules()
	if service then
		local ok, result, reason = pcall(service.grantFree, player, capsuleId, 1, true, paid)
		if not ok then
			warn("[WheelService] CapsuleService.grantFree: " .. tostring(result))
			return { Golem = nil, Lucky = false, Full = false, Reveal = false }
		end
		local golem = firstGolem(result)
		if golem then
			local lucky = type(result) == "table" and result.Lucky == true
			return { Golem = golem, Lucky = lucky, Full = false, Reveal = service.QuietFree == true }
		end
		if reason ~= "InventoryFull" then
			warn("[WheelService] CapsuleService.grantFree refused: " .. tostring(reason))
		end
		return { Golem = nil, Lucky = false, Full = reason == "InventoryFull", Reveal = false }
	end
	local golems = record(data, "Golems")
	if GolemConfig.room(golems) < 1 then
		return { Golem = nil, Lucky = false, Full = true, Reveal = false }
	end
	local lucky = Bonuses.tripleLucky(Bonuses.stats(player))
	local golemKind = CapsuleConfig.roll(capsuleId, lucky, random())
	local entry = if golemKind then GolemConfig.add(golems, golemKind, false, paid) else nil
	if not entry then
		return { Golem = nil, Lucky = false, Full = false, Reveal = false }
	end
	if paid then
		entry.Locked = true -- a golem from a Robux purchase (CapsuleService does the same)
	end
	bump(data, "CapsulesOpened")
	return { Golem = { Id = entry.Id, Kind = entry.Kind }, Lucky = lucky, Full = false, Reveal = true }
end

-- Grants a segment's prize into the save (no yield) and fills `result`.
local function grant(player: Player, data: { [string]: any }, segment: WheelConfig.Segment, result: Result, now: number)
	local kind = segment.Kind
	if kind == "Coins" then
		local amount = WheelConfig.coins(segment, incomeOf(player, data))
		EconomyService.award(player, amount, "Wheel")
		result.Amount = amount
	elseif kind == "Boost" then
		local boostKind = segment.Boost or ""
		local boosts = record(data, "Boosts")
		local before = math.max(now, BoostConfig.untilOf(boosts, boostKind))
		local untilTime = BoostConfig.extend(boosts, boostKind, segment.Seconds or 0, now, true)
		local added = math.max(0, untilTime - before)
		result.Boost = boostKind
		result.Seconds = added
		Bonuses.invalidate(player)
		-- the seconds past the stack cap: coins instead (never an empty prize)
		local coins = WheelService.boostFallbackCoins(segment, added, incomeOf(player, data))
		if coins > 0 then
			award(player, coins, result)
		end
	elseif kind == "Capsule" then
		local capsuleId = segment.Capsule or ""
		result.Capsule = capsuleId
		local opened = openFree(player, data, capsuleId, result.Paid)
		local golem = opened.Golem
		if golem then
			result.Golem = golem
			result.Lucky = opened.Lucky
			if opened.Reveal then
				openings[player] = {
					Payload = { Capsule = capsuleId, Count = 1, Golems = { golem }, Lucky = opened.Lucky, Free = true },
					At = timer(),
				}
			end
		else
			award(player, WheelConfig.capsuleFallbackCoins(capsuleId, BlasterData.priceLevel(data)), result)
			if opened.Full then
				result.Full = true
			end
		end
	elseif kind == "Ore" then
		local context = WheelService.oreContext(player, data)
		local oreId = WheelConfig.pickOre(random(), context)
		if not oreId then
			award(player, WheelConfig.coins(WheelConfig.ById.Coins, incomeOf(player, data)), result)
		elseif PenService.store(player, { K = "Raw", O = oreId }) then
			result.DirtyOre = true
			-- (the tutorial counts the pen's ore as "came home by train" only without these)
			bump(data, "WheelOres")
		else
			-- what Tobin would pay this player dirty: with their sell bonus
			award(player, Bonuses.sellAmount(Bonuses.stats(player), WheelConfig.oreFallbackCoins(context)), result)
		end
	elseif kind == "Shards" then
		local amount = segment.Amount or 0
		Shards.add(data, amount)
		result.Amount = amount
	end
end

--[[
	One spin for `player` (see the header): the free one when it is ready,
	else one bought spin. Returns the result, or nil + "NotReady" (no spin to
	use) / "Restricted" (only bought spins, and paid random items are
	restricted for this player). Yields only before the check (the policy
	answer).
]]
function WheelService.spin(player: Player): (Result?, string?)
	-- nothing to spin never reaches PolicyService (security audit S1)
	local before = DataService.get(player)
	if not before then
		return nil, "NotReady"
	end
	local held = record(before, "Wheel")
	if not WheelConfig.ready(held.NextSpinAt, math.floor(clock())) and WheelConfig.heldSpins(held) <= 0 then
		return nil, "NotReady"
	end
	local restricted = Policy.paidRandomRestricted(player)
	local noCapsules = CapsuleConfig.allRestricted(restricted)
	-- from here on nothing yields: check, save the spin used, grant
	local data = DataService.get(player)
	if not data or not player.Parent then
		return nil, "NotReady"
	end
	local wheel = record(data, "Wheel")
	local now = math.floor(clock())
	local paid = false
	if WheelConfig.ready(wheel.NextSpinAt, now) then
		-- the free spin first (restricted players too: it can't be bought)
		wheel.NextSpinAt = now + WheelConfig.CooldownSeconds
	else
		local spins = WheelConfig.heldSpins(wheel)
		if spins <= 0 then
			return nil, "NotReady"
		elseif restricted then
			-- a paid random item: kept in the save, never spun where restricted
			return nil, "Restricted"
		elseif not noCapsules and GolemConfig.room(data.Golems) < 1 then
			-- a bought spin never swaps a capsule prize for coins: refused before
			-- it is used (the spin stays saved; the free spin still pays coins)
			return nil, "InventoryFull"
		end
		-- a bought spin ignores the cooldown (NextSpinAt stays)
		wheel.Spins = spins - 1
		paid = true
	end
	bump(data, "WheelSpins")
	openings[player] = nil -- an older capsule prize's opening never plays after a new spin
	local segment = WheelConfig.pick(random(), noCapsules)
	local result: Result = {
		Segment = segment.Index,
		Id = segment.Id,
		Kind = segment.Kind,
		NextSpinAt = wheel.NextSpinAt,
		Paid = paid,
		Spins = WheelConfig.heldSpins(wheel),
	}
	grant(player, data, segment, result, now)
	DataService.changed(player)
	return result, nil
end

---------------------------------------------------------------- bought spins

-- The "WheelSpins" receipt handler: all of the product's spins, never refused
-- for a big count and never cut (MaxSpins is only the prompt's "Full"). No yield.
local function grantSpins(player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local spins = entry.Spins
	if type(spins) ~= "number" or spins < 1 or spins ~= math.floor(spins) or DataService.get(player) ~= data then
		return false
	end
	local wheel = record(data, "Wheel")
	local total = WheelConfig.heldSpins(wheel) + spins
	wheel.Spins = total
	Net.fire("Notify", player, {
		Text = `+{spins} wheel spin{if spins == 1 then "" else "s"}: you have {total}. Thank you!`,
		Kind = "Reward",
	})
	return true
end

-- Registers the "WheelSpins" receipt handler (init(); idempotent).
function WheelService.registerGrants()
	MonetizationService.register("WheelSpins", grantSpins)
end

-- Is there no room in the golem inventory for a bought spin's capsule prize?
-- (Capsules are on the wheel unless every capsule is restricted, and a
-- restricted player can't buy or use bought spins anyway.)
function WheelService.inventoryBlocks(data: { [string]: any }?): boolean
	return data ~= nil and not CapsuleConfig.allRestricted(false) and GolemConfig.room(data.Golems) < 1
end

-- "Buy" { Count }: prompts the BUY SPINS row's product (the policy, "Full"
-- and the receipts gate first; PurchasePrompt answers). "Full": past
-- WheelConfig.MaxSpins held, or a full golem inventory (a bought spin
-- couldn't be used: WheelConfig.Reasons.InventoryFull; the client says
-- which). Returns the status (nil: no such row, nothing answered).
function WheelService.buy(player: Player, count: number): string?
	local pack = WheelConfig.packFor(count)
	if not pack then
		return nil
	end
	local data = DataService.get(player)
	local held = if data then WheelConfig.heldSpins(data.Wheel) else 0
	local full = held + pack.Count > WheelConfig.MaxSpins or WheelService.inventoryBlocks(data)
	return BoostService.promptPurchase(player, pack.Product, false, full)
end

-- "Reveal": the waiting CapsuleResult of this player's capsule prize, once.
local function reveal(player: Player)
	local opening = openings[player]
	openings[player] = nil
	if opening and timer() - opening.At <= WheelService.RevealSeconds and player.Parent then
		Net.fire("CapsuleResult", player, opening.Payload)
	end
end

local function onAction(player: Player, action: any, payload: any)
	if action == "Reveal" then
		reveal(player)
		return
	end
	if action == "Buy" then
		local args = Guard.table(payload, 2)
		local count = if args then Guard.integer(args.Count, 1, 10) else nil
		if count and WheelConfig.packFor(count) then
			WheelService.buy(player, count)
		end
		return
	end
	if action ~= "Spin" then
		return
	end
	local result, reason = WheelService.spin(player)
	if result then
		Net.fire("WheelResult", player, result)
	else
		Net.fire("ActionResult", player, { Action = "Wheel", Op = "Spin", Ok = false, Reason = reason })
	end
end

---------------------------------------------------------------- the EmberChest prompt

local function openView(player: Player, chest: BasePart)
	if DataService.get(player) then
		Net.fire("OpenUI", player, "Wheel", { Chest = chest })
	end
end

-- The chest's prompt part: the model's PrimaryPart ("Chest"), or the part itself.
local function chestPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		local primary = instance.PrimaryPart
		if primary then
			return primary
		end
		local chest = instance:FindFirstChild("Chest")
		if chest and chest:IsA("BasePart") then
			return chest
		end
		return instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function hookChest(instance: Instance)
	if hooked[instance] then
		return
	end
	local part = chestPart(instance)
	if not part then
		return
	end
	hooked[instance] = true
	local old = part:FindFirstChild(WheelService.PointName)
	if old then
		old:Destroy()
	end
	local point = Instance.new("Attachment")
	point.Name = WheelService.PointName
	point.CFrame = CFrame.new(0, part.Size.Y / 2 + 1, 0)
	point.Parent = part
	local prompt = PromptConfig.make({
		Name = WheelService.PromptName,
		ActionText = "Spin & Win",
		ObjectText = "Daily Wheel",
		Distance = WheelService.PromptDistance,
		Parent = point,
	})
	prompt.Triggered:Connect(function(player: Player)
		openView(player, part)
	end)
end

local function unhookChest(instance: Instance)
	hooked[instance] = nil
	local part = chestPart(instance)
	local point = part and part:FindFirstChild(WheelService.PointName)
	if point then
		point:Destroy()
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/Wheel.spec.luau).
WheelService._test = {
	action = onAction,
	hookChest = hookChest,
	open = openView,
	grantSpins = grantSpins,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setRandom = function(fn: () -> number)
		random = fn
	end,
	setTimer = function(fn: () -> number)
		timer = fn
	end,
	setCapsules = function(service: FreeCapsules?)
		capsules = service
		capsulesKnown = true
	end,
	reset = function()
		table.clear(hooked)
		table.clear(openings)
		clock = os.time
		rng = nil
		random = nextRoll
		timer = os.clock
		capsules = nil
		capsulesKnown = false
	end,
}

function WheelService.init()
	Net.on("WheelAction", onAction)
	-- step 8: the bought spins' receipts
	WheelService.registerGrants()
end

function WheelService.start()
	-- the wheel screen hides the paid-random substitutes only once the policy is known
	Players.PlayerAdded:Connect(Policy.prefetch)
	Players.PlayerRemoving:Connect(function(player: Player)
		openings[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		Policy.prefetch(player)
	end
	-- the map is built in WorldService.init, so the EmberChest exists by now
	for _, instance in CollectionService:GetTagged(WheelConfig.Tag) do
		hookChest(instance)
	end
	CollectionService:GetInstanceAddedSignal(WheelConfig.Tag):Connect(hookChest)
	CollectionService:GetInstanceRemovedSignal(WheelConfig.Tag):Connect(unhookChest)
end

return WheelService
