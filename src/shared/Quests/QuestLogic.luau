--[[
	The rules of the daily / weekly quests and the 7-day login streak (pure:
	no services, no yields; QuestService, the client and the Lune tests use
	it). Numbers: Shared/Config/QuestConfig; design: docs/plans/DAILY_QUESTS_PLAN.md.

	Saved shapes (DataTemplate):
	  data.Quests = { Day, Daily = { Entry }, Week, Weekly = { Entry } }
	  Entry       = { Id, Base, Goal, Claimed }   (Base: the Stat when given)
	  data.Streak = { Day = 1..7 (the last day claimed, 0 = never), Last = UTC day number }

	  day(now) / week(now)       UTC day number; week number (changes Monday 00:00 UTC)
	  goal(def, level, income)   a quest's goal for this player (nil: not offered)
	  roll(kind, userId, n, ctx) the seeded pick for that day / week
	  refresh(record, ctx)       rerolls stale lists (new day / week, broken save); true = changed
	  progress(entry, stats)     0..Goal
	  claim(record, kind, index, stats, number) the checks of a claim (no reward)
	  coins(seconds, income, level) a coin reward
	  streakNext(streak, now)    the day a claim would give (nil: claimed today)
	  view(...)                  what the client draws (StateService provider)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(Shared.Config.QuestConfig)
local BlasterData = require(Shared.Config.BlasterData)
local Rng = require(Shared.Util.Rng)

local QuestLogic = {}

export type Kind = "Daily" | "Weekly"

export type Entry = { Id: string, Base: number, Goal: number, Claimed: boolean }

export type Record = {
	Day: number,
	Daily: { Entry },
	Week: number,
	Weekly: { Entry },
}

export type Streak = { Day: number, Last: number }

-- What a roll needs to know about the player.
export type Context = {
	UserId: number,
	Now: number,
	Level: number, -- blaster level
	Income: number, -- podium income per second
	Stats: { [string]: any },
	Capsules: boolean, -- may capsule quests be offered (paid random items allowed)
}

local DAY = QuestConfig.DaySeconds

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function whole(n: any): number
	return if finite(n) then math.floor(n) else 0
end

-- UTC day number (00:00 UTC starts a new one).
function QuestLogic.day(now: number): number
	return math.floor(now / DAY)
end

-- Week number: day 0 (1970-01-01) was a Thursday, so +3 makes Monday the first day.
function QuestLogic.week(now: number): number
	return math.floor((QuestLogic.day(now) + 3) / 7)
end

-- Seconds until the dailies reset (next 00:00 UTC).
function QuestLogic.dailyLeft(now: number): number
	return (QuestLogic.day(now) + 1) * DAY - now
end

-- Seconds until the weekly resets (next Monday 00:00 UTC).
function QuestLogic.weeklyLeft(now: number): number
	return ((QuestLogic.week(now) + 1) * 7 - 3) * DAY - now
end

-- "5h 12m" / "3d 4h" / "12m" for a countdown.
function QuestLogic.countdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d = math.floor(s / DAY)
	local h = math.floor((s % DAY) / 3600)
	local m = math.floor((s % 3600) / 60)
	if d > 0 then
		return `{d}d {h}h`
	elseif h > 0 then
		return `{h}h {m}m`
	end
	return `{math.max(m, 1)}m`
end

-- A round goal: 1-20 as is, then two significant digits, the second one a
-- multiple of 5 from 30 on (25, 35, 170, 1200, 3500, ...).
function QuestLogic.nice(n: number): number
	if not finite(n) or n < 1 then
		return 1
	end
	if n <= 20 then
		return math.floor(n + 0.5)
	end
	local magnitude = 10 ^ math.floor(math.log10(n))
	local step = magnitude / 10
	if n / magnitude >= 3 then
		step *= 5
	end
	return math.max(step, math.floor(n / step + 0.5) * step)
end

-- The blaster level as a whole 1..MaxLevel.
local function levelOf(level: any): number
	return math.clamp(whole(level), 1, BlasterData.MaxLevel)
end

-- A quest's goal for this player, or nil when it isn't offered to them.
function QuestLogic.goal(def: QuestConfig.QuestDef, level: number, income: number): number?
	local l = levelOf(level)
	if l < (def.MinLevel or 1) then
		return nil
	end
	if def.Income then
		if not finite(income) or income <= 0 then
			return nil
		end
		return QuestLogic.nice(income * def.Income)
	end
	local amount = def.Amount or 1
	return QuestLogic.nice(amount * (1 + (def.Growth or 0) * (l - 1)))
end

local function poolOf(kind: Kind): { QuestConfig.QuestDef }
	return if kind == "Weekly" then QuestConfig.Weekly else QuestConfig.Daily
end

local function countOf(kind: Kind): number
	return if kind == "Weekly" then QuestConfig.WeeklyCount else QuestConfig.DailyCount
end

local function statOf(stats: { [string]: any }?, name: string): number
	local value = if type(stats) == "table" then stats[name] else nil
	return if finite(value) then math.max(0, value) else 0
end

--[[
	The seeded pick for one day (Daily) or week (Weekly): `count` different
	quests by weight, the same for the same player, number and offer (level,
	income > 0, capsules). Entries start at the current Stats.
]]
function QuestLogic.roll(kind: Kind, ctx: Context): { Entry }
	local number = if kind == "Weekly" then QuestLogic.week(ctx.Now) else QuestLogic.day(ctx.Now)
	local rng = Rng.new(`quests:{whole(ctx.UserId)}:{if kind == "Weekly" then "w" else "d"}{number}`)
	local offered: { { Def: QuestConfig.QuestDef, Goal: number } } = {}
	for _, def in poolOf(kind) do
		local goal = QuestLogic.goal(def, ctx.Level, ctx.Income)
		if goal and not (def.Capsules and not ctx.Capsules) then
			table.insert(offered, { Def = def, Goal = goal })
		end
	end
	local picked: { Entry } = {}
	for _ = 1, countOf(kind) do
		local total = 0
		for _, o in offered do
			total += o.Def.Weight or 1
		end
		if total <= 0 then
			break
		end
		local roll = rng:next() * total
		local index = #offered
		for i, o in offered do
			roll -= o.Def.Weight or 1
			if roll < 0 then
				index = i
				break
			end
		end
		local chosen = table.remove(offered, index) :: any
		table.insert(picked, {
			Id = chosen.Def.Id,
			Base = statOf(ctx.Stats, chosen.Def.Stat),
			Goal = chosen.Goal,
			Claimed = false,
		})
	end
	return picked
end

-- Is a saved list sane for its kind (the right count of known, different quests)?
local function saneList(list: any, kind: Kind): boolean
	if type(list) ~= "table" or #list ~= countOf(kind) then
		return false
	end
	local seen: { [string]: boolean } = {}
	local pool: { [string]: boolean } = {}
	for _, def in poolOf(kind) do
		pool[def.Id] = true
	end
	for _, entry in list do
		if type(entry) ~= "table" or type(entry.Id) ~= "string" or not pool[entry.Id] or seen[entry.Id] then
			return false
		end
		if not finite(entry.Base) or entry.Base < 0 or not finite(entry.Goal) or entry.Goal < 1 then
			return false
		end
		if type(entry.Claimed) ~= "boolean" then
			return false
		end
		seen[entry.Id] = true
	end
	return true
end

--[[
	Brings data.Quests up to date for ctx.Now: new dailies on a new UTC day,
	a new weekly on a new week, and a broken list rerolled. A Stat that went
	below its Base (a rolled-back save) moves the Base down. Returns true
	when it changed anything (the caller saves: DataService.changed).
]]
function QuestLogic.refresh(record: { [string]: any }, ctx: Context): boolean
	local changed = false
	local today = QuestLogic.day(ctx.Now)
	local week = QuestLogic.week(ctx.Now)
	if record.Day ~= today or not saneList(record.Daily, "Daily") then
		record.Day = today
		record.Daily = QuestLogic.roll("Daily", ctx)
		changed = true
	end
	if record.Week ~= week or not saneList(record.Weekly, "Weekly") then
		record.Week = week
		record.Weekly = QuestLogic.roll("Weekly", ctx)
		changed = true
	end
	for _, list in { record.Daily, record.Weekly } do
		for _, entry in list do
			local def = QuestConfig.ById[entry.Id]
			local now = statOf(ctx.Stats, def.Stat)
			if now < entry.Base then
				entry.Base = now
				changed = true
			end
		end
	end
	return changed
end

-- How far a quest is (0..Goal).
function QuestLogic.progress(entry: Entry, stats: { [string]: any }?): number
	local def = QuestConfig.ById[entry.Id]
	if not def then
		return 0
	end
	return math.clamp(statOf(stats, def.Stat) - entry.Base, 0, entry.Goal)
end

function QuestLogic.done(entry: Entry, stats: { [string]: any }?): boolean
	return QuestLogic.progress(entry, stats) >= entry.Goal
end

--[[
	The checks of a claim, with no reward: "Daily" index 1..DailyCount or
	"Weekly" (index 1). `number` is the day (week) the client saw: another
	one is "Stale". Marks the entry Claimed and returns it, or nil + a
	QuestConfig.Reasons code.
]]
function QuestLogic.check(
	record: { [string]: any },
	kind: Kind,
	index: number,
	stats: { [string]: any }?,
	number: number?
): (Entry?, string?)
	local list = if kind == "Weekly" then record.Weekly else record.Daily
	local current = if kind == "Weekly" then record.Week else record.Day
	if number ~= nil and number ~= current then
		return nil, "Stale"
	end
	local entry = if type(list) == "table" then list[index] else nil
	if type(entry) ~= "table" or not QuestConfig.ById[entry.Id] then
		return nil, "BadQuest"
	end
	if entry.Claimed then
		return nil, "Claimed"
	end
	if not QuestLogic.done(entry, stats) then
		return nil, "NotDone"
	end
	return entry, nil
end

-- check, then marks the entry Claimed (before any reward is paid).
function QuestLogic.claim(
	record: { [string]: any },
	kind: Kind,
	index: number,
	stats: { [string]: any }?,
	number: number?
): (Entry?, string?)
	local entry, reason = QuestLogic.check(record, kind, index, stats, number)
	if entry then
		entry.Claimed = true
	end
	return entry, reason
end

---------------------------------------------------------------- rewards

-- The coin floor of a reward of `seconds` at a blaster level.
function QuestLogic.coinFloor(seconds: number, level: number): number
	local l = levelOf(level)
	local nextBlaster = BlasterData.ByLevel[math.min(l + 1, BlasterData.MaxLevel)]
	local recipe = nextBlaster and nextBlaster.Recipe
	local forge = if recipe then recipe.Coins else 0
	local base = math.max(QuestConfig.MinCoins, QuestConfig.FloorShare * forge)
	return math.floor(base * seconds / QuestConfig.FloorSeconds)
end

-- Coins for `seconds` of podium income, never under the floor.
function QuestLogic.coins(seconds: number, income: number, level: number): number
	local perSecond = if finite(income) and income > 0 then math.min(income, 1e27) else 0
	return math.max(QuestLogic.coinFloor(seconds, level), math.floor(perSecond * seconds))
end

---------------------------------------------------------------- the login streak

local function streakOf(streak: any): Streak
	if type(streak) ~= "table" then
		return { Day = 0, Last = -1 }
	end
	return {
		Day = math.clamp(whole(streak.Day), 0, #QuestConfig.Streak),
		Last = if finite(streak.Last) then math.floor(streak.Last) else -1,
	}
end

-- The streak day a claim now would give (1..7), or nil (claimed today already).
function QuestLogic.streakNext(streak: any, now: number): number?
	local s = streakOf(streak)
	local today = QuestLogic.day(now)
	if s.Last >= today then
		return nil
	end
	if s.Last == today - 1 and s.Day >= 1 then
		return s.Day % #QuestConfig.Streak + 1
	end
	return 1
end

-- Claims today's streak day into `streak` (saved record). Returns the day, or nil.
function QuestLogic.streakClaim(streak: { [string]: any }, now: number): number?
	local nextDay = QuestLogic.streakNext(streak, now)
	if not nextDay then
		return nil
	end
	streak.Day = nextDay
	streak.Last = QuestLogic.day(now)
	return nextDay
end

-- Which streak day the calendar highlights and which are done: the cells 1..7
-- show done for the days of the current run.
function QuestLogic.streakCells(streak: any, now: number): (number, number, boolean)
	local s = streakOf(streak)
	local nextDay = QuestLogic.streakNext(streak, now)
	if nextDay then
		-- today's cell is nextDay; the run before it is done (a broken run shows none)
		return nextDay, nextDay - 1, true
	end
	return s.Day, s.Day, false
end

---------------------------------------------------------------- the client's view

local function format(text: string, goal: number, money: (number) -> string, isIncome: boolean): string
	return string.format(text, if isIncome then money(goal) else tostring(goal))
end

--[[
	What the client draws (snapshot.Quests), with rewards priced at this
	income. `money` formats coins (Format.money).
]]
function QuestLogic.view(
	record: { [string]: any },
	streak: any,
	stats: { [string]: any }?,
	now: number,
	level: number,
	income: number,
	money: (number) -> string
): { [string]: any }
	local function entries(list: any, reward: QuestConfig.Reward): { any }
		local out = {}
		for i, entry in (if type(list) == "table" then list else {}) do
			local def = QuestConfig.ById[entry.Id]
			if def then
				table.insert(out, {
					Index = i,
					Id = entry.Id,
					Text = format(def.Text, entry.Goal, money, def.Income ~= nil),
					Short = def.Short,
					Paint = def.Paint,
					Icon = def.Icon,
					Progress = QuestLogic.progress(entry, stats),
					Goal = entry.Goal,
					Money = def.Income ~= nil,
					Claimed = entry.Claimed == true,
					Coins = if reward.Coins then QuestLogic.coins(reward.Coins, income, level) else nil,
					Shards = reward.Shards,
					Boost = reward.Boost,
					BoostSeconds = reward.BoostSeconds,
				})
			end
		end
		return out
	end
	local today, done, canClaim = QuestLogic.streakCells(streak, now)
	local days = {}
	for _, d in QuestConfig.Streak do
		table.insert(days, {
			Day = d.Day,
			Label = d.Label,
			Icon = d.Icon,
			Paint = d.Paint,
			Coins = if d.Coins then QuestLogic.coins(d.Coins, income, level) else nil,
			Shards = d.Shards,
			Boost = d.Boost,
			BoostSeconds = d.BoostSeconds,
			Capsule = d.Capsule,
		})
	end
	return {
		Day = record.Day,
		Week = record.Week,
		-- os.time() of the resets (absolute: the section doesn't change every second)
		DailyEnds = now + QuestLogic.dailyLeft(now),
		WeeklyEnds = now + QuestLogic.weeklyLeft(now),
		Daily = entries(record.Daily, QuestConfig.DailyReward),
		Weekly = entries(record.Weekly, QuestConfig.WeeklyReward),
		Streak = { Today = today, Done = done, CanClaim = canClaim, Days = days },
	}
end

-- How many things wait to be claimed in a view (the side menu's badge).
function QuestLogic.claimable(view: any): number
	if type(view) ~= "table" then
		return 0
	end
	local count = 0
	for _, key in { "Daily", "Weekly" } do
		local list = view[key]
		if type(list) == "table" then
			for _, q in list do
				if type(q) == "table" and not q.Claimed and type(q.Progress) == "number" and q.Progress >= (q.Goal or math.huge) then
					count += 1
				end
			end
		end
	end
	local streak = view.Streak
	if type(streak) == "table" and streak.CanClaim == true then
		count += 1
	end
	return count
end

return QuestLogic
