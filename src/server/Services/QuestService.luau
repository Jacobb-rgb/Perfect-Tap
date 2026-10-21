--[[
	QuestService: the daily / weekly quests and the 7-day login streak
	(docs/plans/DAILY_QUESTS_PLAN.md; numbers in Shared/Config/QuestConfig,
	rules in Shared/Quests/QuestLogic).

	- data.Quests is brought up to date (QuestLogic.refresh: new dailies at
	  00:00 UTC, a new weekly on Monday, broken lists rerolled) on load
	  (after the paid-random policy is known, so capsule quests are offered
	  where allowed), on every claim, in the State provider and by a loop
	  every QuestConfig.CheckSeconds that only compares day numbers.
	- QuestAction ("Claim", { Kind, Index, Day? / Week? }) / ("Streak"):
	    1. a quick check (nothing to claim never reaches PolicyService), then
	       the policy (may yield);
	    2. with no yield from here on: check again, mark Claimed (streak:
	       Day / Last) BEFORE granting, grant, DataService.changed;
	    3. QuestReward + ActionResult { Action = "Quest", Op, Ok = true }.
	  Refused: ActionResult { Ok = false, Reason = a QuestConfig.Reasons code }.
	  Two quick claims can't both pass: the check and the write are one step.
	- Rewards (QuestConfig): coins = seconds of podium income (never under
	  the floor, EconomyService.award "Quest"), shards (Shards.add), a luck
	  boost (BoostConfig.extend, capped; the seconds past the cap are paid
	  as coins), a free capsule (CapsuleService.grantFree, not quiet: its
	  CapsuleResult plays the opening). Where every capsule is a restricted
	  paid random item, Triple Lucky and the capsule become coins (the wheel
	  does the same). A streak day with a capsule is refused with
	  "InventoryFull" while the golem inventory has no room (the day stays
	  claimable, nothing is paid instead); only an opening that still fails
	  pays the capsule's coin value (Full = true).
	- StateService provider: snapshot.Quests = QuestLogic.view (rewards
	  priced at the current income, reset times as os.time()).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local QuestConfig = require(Shared.Config.QuestConfig)
local WheelConfig = require(Shared.Config.WheelConfig)
local QuestLogic = require(Shared.Quests.QuestLogic)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Guard = require(script.Parent.Parent.Guard)
local Policy = require(script.Parent.Parent.Policy)
local Shards = require(script.Parent.Parent.Shards)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PodiumService = require(script.Parent.PodiumService)
local StateService = require(script.Parent.StateService)

local QuestService = {}

-- CapsuleService's free opening (WheelService.FreeCapsules has the contract).
export type FreeCapsules = {
	grantFree: (player: Player, capsuleId: string, count: number?, quiet: boolean?, paid: boolean?) -> (any, any),
}

export type Reward = {
	Kind: string, -- "Daily" | "Weekly" | "Streak"
	Index: number?,
	Day: number?,
	Coins: number?,
	Shards: number?,
	Boost: string?,
	Seconds: number?,
	Capsule: string?,
	Golem: { Id: number, Kind: string }?,
	Full: boolean?,
}

-- Swappable for the Lune tests.
local clock: () -> number = os.time
local capsules: FreeCapsules? = nil
local capsulesKnown = false

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

local function incomeOf(player: Player, data: { [string]: any }): number
	local ok, value = pcall(PodiumService.incomeOf, player, data)
	return if ok and finite(value) and value > 0 then value else 0
end

local function levelOf(data: { [string]: any }): number
	return BlasterData.get(data.BlasterLevel).Level
end

-- The capsule package's service (looked up once; nil: this place has none).
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

-- Brings the player's quests up to date. `restricted`: the policy answer
-- (nil: the cached one, strict until known). Returns true when it changed.
function QuestService.ensure(player: Player, data: { [string]: any }, restricted: boolean?): boolean
	local strict = if restricted == nil then Policy.cached(player).PaidRandomRestricted else restricted
	return QuestLogic.refresh(record(data, "Quests"), {
		UserId = player.UserId,
		Now = clock(),
		Level = levelOf(data),
		Income = incomeOf(player, data),
		Stats = record(data, "Stats"),
		Capsules = not CapsuleConfig.allRestricted(strict),
	})
end

---------------------------------------------------------------- rewards

local function pay(player: Player, data: { [string]: any }, amount: number, result: Reward)
	local coins = math.max(0, math.floor(amount))
	if coins > 0 then
		EconomyService.award(player, coins, "Quest")
		result.Coins = (result.Coins or 0) + coins
	end
end

local function grantCapsule(player: Player, data: { [string]: any }, capsuleId: string, noCapsules: boolean, result: Reward)
	result.Capsule = capsuleId
	local fallback = WheelConfig.capsuleFallbackCoins(capsuleId, BlasterData.priceLevel(data))
	local service = if noCapsules then nil else freeCapsules()
	if not service then
		pay(player, data, fallback, result)
		result.Full = true
		return
	end
	local ok, opened, reason = pcall(service.grantFree, player, capsuleId, 1, false, false)
	local golems = if ok and type(opened) == "table" then opened.Golems else nil
	local golem = if type(golems) == "table" then golems[1] else nil
	if type(golem) == "table" and type(golem.Id) == "number" and type(golem.Kind) == "string" then
		result.Golem = { Id = golem.Id, Kind = golem.Kind }
		return
	end
	if not ok then
		warn("[QuestService] CapsuleService.grantFree: " .. tostring(opened))
	elseif reason ~= "InventoryFull" then
		warn("[QuestService] CapsuleService.grantFree refused: " .. tostring(reason))
	end
	-- a full inventory (or a failed opening) pays the capsule's coins, never a second roll
	pay(player, data, fallback, result)
	result.Full = true
end

-- Pays a QuestConfig reward into the save (no yield) and fills `result`.
local function grant(player: Player, data: { [string]: any }, reward: QuestConfig.Reward, noCapsules: boolean, result: Reward)
	local income = incomeOf(player, data)
	local level = levelOf(data)
	if reward.Coins then
		pay(player, data, QuestLogic.coins(reward.Coins, income, level), result)
	end
	if reward.Shards and reward.Shards > 0 then
		Shards.add(data, reward.Shards)
		result.Shards = reward.Shards
	end
	local boost = reward.Boost
	local seconds = reward.BoostSeconds or 0
	if boost and seconds > 0 then
		local fallback = QuestConfig.LuckyFallbackSeconds
		if boost == "TripleLucky" and noCapsules then
			-- Triple Lucky only helps capsules: coins instead
			pay(player, data, QuestLogic.coins(fallback, income, level), result)
		else
			local now = clock()
			local boosts = record(data, "Boosts")
			local before = math.max(now, BoostConfig.untilOf(boosts, boost))
			local untilTime = BoostConfig.extend(boosts, boost, seconds, now, true)
			local added = math.max(0, untilTime - before)
			result.Boost = boost
			result.Seconds = added
			Bonuses.invalidate(player)
			if added < seconds then
				-- the seconds past the stack cap: that share of the fallback coins
				pay(player, data, QuestLogic.coins(fallback, income, level) * (seconds - added) / seconds, result)
			end
		end
	end
	if reward.Capsule then
		grantCapsule(player, data, reward.Capsule, noCapsules, result)
	end
end

local function refuse(player: Player, op: string, reason: string, index: number?)
	Net.fire("ActionResult", player, { Action = "Quest", Op = op, Ok = false, Reason = reason, Index = index })
end

local function rewardOf(kind: QuestLogic.Kind): QuestConfig.Reward
	return if kind == "Weekly" then QuestConfig.WeeklyReward else QuestConfig.DailyReward
end

-- Does paying this reward need the paid-random policy (a capsule or Triple Lucky)?
local function needsPolicy(reward: QuestConfig.Reward): boolean
	return reward.Capsule ~= nil or reward.Boost == "TripleLucky"
end

local function noCapsulesFor(player: Player, reward: QuestConfig.Reward): boolean
	if not needsPolicy(reward) then
		return false
	end
	return CapsuleConfig.allRestricted(Policy.paidRandomRestricted(player))
end

--[[
	Claims a finished quest. Returns the reward, or nil + a reason
	(QuestConfig.Reasons). Yields only before the check (the policy).
]]
function QuestService.claim(player: Player, kind: QuestLogic.Kind, index: number, number: number?): (Reward?, string?)
	local before = DataService.get(player)
	if not before then
		return nil, "NoData"
	end
	QuestService.ensure(player, before)
	local _, early = QuestLogic.check(record(before, "Quests"), kind, index, before.Stats, number)
	if early then
		return nil, early
	end
	local reward = rewardOf(kind)
	local noCapsules = noCapsulesFor(player, reward)
	-- from here on nothing yields: check, mark claimed, grant
	local data = DataService.get(player)
	if not data or not player.Parent then
		return nil, "NoData"
	end
	QuestService.ensure(player, data)
	local entry, reason = QuestLogic.claim(record(data, "Quests"), kind, index, data.Stats, number)
	if not entry then
		return nil, reason
	end
	local result: Reward = { Kind = kind, Index = index }
	grant(player, data, reward, noCapsules, result)
	DataService.changed(player)
	return result, nil
end

-- Claims today's login streak day. Returns the reward, or nil + a reason.
function QuestService.claimStreak(player: Player): (Reward?, string?)
	local before = DataService.get(player)
	if not before then
		return nil, "NoData"
	end
	local nextDay = QuestLogic.streakNext(before.Streak, clock())
	if not nextDay then
		return nil, "Tomorrow"
	end
	local prize = QuestConfig.Streak[nextDay]
	local noCapsules = noCapsulesFor(player, prize)
	local data = DataService.get(player)
	if not data or not player.Parent then
		return nil, "NoData"
	end
	if prize.Capsule and not noCapsules and GolemConfig.room(data.Golems) < 1 then
		-- the capsule waits: the day stays unclaimed until there is room (never coins instead)
		return nil, "InventoryFull"
	end
	local day = QuestLogic.streakClaim(record(data, "Streak"), clock())
	if not day then
		return nil, "Tomorrow"
	end
	local result: Reward = { Kind = "Streak", Day = day }
	grant(player, data, QuestConfig.Streak[day], noCapsules, result)
	DataService.changed(player)
	return result, nil
end

local function onAction(player: Player, action: any, payload: any)
	if action == "Streak" then
		local result, reason = QuestService.claimStreak(player)
		if result then
			Net.fire("QuestReward", player, result)
			Net.fire("ActionResult", player, { Action = "Quest", Op = "Streak", Ok = true })
		else
			refuse(player, "Streak", reason or "NoData")
		end
		return
	end
	if action ~= "Claim" then
		return
	end
	local args = Guard.table(payload, 4)
	if not args then
		return
	end
	local kind: QuestLogic.Kind? = if args.Kind == "Daily" then "Daily" elseif args.Kind == "Weekly" then "Weekly" else nil
	if not kind then
		return
	end
	local index = if kind == "Weekly" then 1 else Guard.integer(args.Index, 1, QuestConfig.DailyCount)
	if not index then
		return
	end
	local number = Guard.integer(if kind == "Weekly" then args.Week else args.Day, 0, 1e7)
	local result, reason = QuestService.claim(player, kind, index, number)
	if result then
		Net.fire("QuestReward", player, result)
		Net.fire("ActionResult", player, { Action = "Quest", Op = "Claim", Ok = true, Index = index })
	else
		refuse(player, "Claim", reason or "NoData", index)
	end
end

---------------------------------------------------------------- the client's view

local function provide(player: Player, data: { [string]: any }, snapshot: { [string]: any })
	-- (a stale list is brought up to date here too: the next save keeps it)
	QuestService.ensure(player, data)
	snapshot.Quests =
		QuestLogic.view(record(data, "Quests"), data.Streak, data.Stats, clock(), levelOf(data), incomeOf(player, data), Format.money)
end

-- Every player online: new quests after midnight (only day numbers compared).
local function check()
	local now = clock()
	local today, week = QuestLogic.day(now), QuestLogic.week(now)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		local quests = if data then data.Quests else nil
		-- (a new day also makes the streak claimable again: the push shows both)
		local stale = type(quests) ~= "table" or quests.Day ~= today or quests.Week ~= week
		if data and stale then
			QuestService.ensure(player, data)
			DataService.changed(player)
		end
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/Quests.spec.luau).
QuestService._test = {
	action = onAction,
	provide = provide,
	check = check,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setCapsules = function(service: FreeCapsules?)
		capsules = service
		capsulesKnown = true
	end,
	reset = function()
		clock = os.time
		capsules = nil
		capsulesKnown = false
	end,
}

function QuestService.init()
	Net.on("QuestAction", onAction)
	StateService.addProvider(provide)
end

function QuestService.start()
	DataService.onLoaded(function(player: Player, data: { [string]: any })
		-- the policy first (yields): capsule quests are offered where they are allowed
		local restricted = Policy.paidRandomRestricted(player)
		if player.Parent and DataService.get(player) == data and QuestService.ensure(player, data, restricted) then
			DataService.changed(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(QuestConfig.CheckSeconds)
			local ok, err = pcall(function(): any
				check()
				return nil
			end)
			if not ok then
				warn("[QuestService] check failed: " .. tostring(err))
			end
		end
	end)
end

return QuestService
