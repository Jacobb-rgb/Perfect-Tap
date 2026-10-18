--[[
	WheelService: the free daily wheel of fortune (step 7, SPIN & WIN in
	town; every rule and number lives in Shared/Config/WheelConfig).

	- EmberChest (tag WheelConfig.Tag, the chest at the top of the SPIN & WIN
	  stairs inside the SpinWheel model): this service adds a "Spin & Win"
	  prompt (F / gamepad Y) on it; it opens the wheel screen (OpenUI "Wheel"
	  { Chest }). The screen shows the 8 segments with their exact odds
	  (and the ore prize's and the capsules' own odds) and the countdown.
	  The spin itself works from anywhere (the HUD's FREE SPIN! chip).
	- WheelAction ("Spin"): when WheelConfig.ready(data.Wheel.NextSpinAt):
	    1. the paid-random policy (src/server/Policy.luau; it may yield on the
	       first ask, so it is asked BEFORE the check and write step): players
	       who can't buy any capsule spin the wheel with Substitutes
	       (WheelConfig.segments(CapsuleConfig.allRestricted(restricted)));
	    2. with no yield from here on: check ready, save NextSpinAt = now +
	       CooldownSeconds and Stats.WheelSpins + 1 BEFORE granting, pick the
	       segment (a seeded Random), grant the prize, DataService.changed;
	    3. WheelResult (Net) tells the client where the wheel stops.
	  Not ready (or no save): ActionResult { Action = "Wheel", Op = "Spin",
	  Ok = false, Reason = "NotReady" }. Junk actions are dropped. Two quick
	  Spins can't both pass: the check and the write happen in one step.
	  The cooldown and the prize live in the same save, so a crash before the
	  next autosave loses both together (never a prize without the cooldown).
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
	  The free spin is not a paid random item (it can't be bought), but its
	  odds are always shown; no rewards for likes or favorites.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local WheelConfig = require(Shared.Config.WheelConfig)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Policy = require(script.Parent.Parent.Policy)
local Shards = require(script.Parent.Parent.Shards)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
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
	  CapsuleService.grantFree(player, capsuleId, count?, quiet?)
	      -> (Result?, reason?)
	opens `count` (default 1) capsules of that kind for free with no yield
	(no price, not paid; the player's Triple Lucky counts; Stats.
	CapsulesOpened, DataService.changed and its own side effects) and returns
	its CapsuleResult { Capsule, Count, Golems = { { Id, Kind } }, Lucky,
	Free = true }, or nil + "InventoryFull" (no room) / "BadCapsule".
	The wheel calls grantFree(player, capsuleId, 1, true):
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
	(CapsuleConfig.roll + GolemConfig.add).
]]
export type FreeCapsules = {
	grantFree: (player: Player, capsuleId: string, count: number?, quiet: boolean?) -> (any, any),
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

-- Opens the free capsule (see FreeCapsules above): through the capsule
-- package when this place has one (never a second roll here), else here.
local function openFree(player: Player, data: { [string]: any }, capsuleId: string): Opened
	local service = freeCapsules()
	if service then
		local ok, result, reason = pcall(service.grantFree, player, capsuleId, 1, true)
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
	local entry = if golemKind then GolemConfig.add(golems, golemKind) else nil
	if not entry then
		return { Golem = nil, Lucky = false, Full = false, Reveal = false }
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
		local opened = openFree(player, data, capsuleId)
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
			award(player, WheelConfig.capsuleFallbackCoins(capsuleId, data.BlasterLevel), result)
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
			award(player, WheelConfig.oreFallbackCoins(context), result)
		end
	elseif kind == "Shards" then
		local amount = segment.Amount or 0
		Shards.add(data, amount)
		result.Amount = amount
	end
end

--[[
	The free daily spin for `player` (see the header). Returns the result, or
	nil + "NotReady". Yields only before the check (the policy answer).
]]
function WheelService.spin(player: Player): (Result?, string?)
	local restricted = Policy.paidRandomRestricted(player)
	local noCapsules = CapsuleConfig.allRestricted(restricted)
	-- from here on nothing yields: check, save the cooldown, grant
	local data = DataService.get(player)
	if not data or not player.Parent then
		return nil, "NotReady"
	end
	local wheel = record(data, "Wheel")
	local now = math.floor(clock())
	if not WheelConfig.ready(wheel.NextSpinAt, now) then
		return nil, "NotReady"
	end
	wheel.NextSpinAt = now + WheelConfig.CooldownSeconds
	bump(data, "WheelSpins")
	openings[player] = nil -- an older capsule prize's opening never plays after a new spin
	local segment = WheelConfig.pick(random(), noCapsules)
	local result: Result = {
		Segment = segment.Index,
		Id = segment.Id,
		Kind = segment.Kind,
		NextSpinAt = wheel.NextSpinAt,
	}
	grant(player, data, segment, result, now)
	DataService.changed(player)
	return result, nil
end

-- "Reveal": the waiting CapsuleResult of this player's capsule prize, once.
local function reveal(player: Player)
	local opening = openings[player]
	openings[player] = nil
	if opening and timer() - opening.At <= WheelService.RevealSeconds and player.Parent then
		Net.fire("CapsuleResult", player, opening.Payload)
	end
end

local function onAction(player: Player, action: any)
	if action == "Reveal" then
		reveal(player)
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
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = WheelService.PromptName
	prompt.ActionText = "Spin & Win"
	prompt.ObjectText = "Daily Wheel"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = WheelService.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = point
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
