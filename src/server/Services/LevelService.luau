--[[
	LevelService: the player LEVEL (rules and numbers: Config/LevelConfig).

	- Every LevelConfig.TickSeconds it looks at each loaded player's
	  counters (LevelConfig.counters: stats, machines, upgrades...) and pays
	  XP for what grew (LevelConfig.collect). No other service calls in.
	- A gain fires XpGain { Gain, Level, Xp, Need } (the client's orbs fly
	  into the bar). Each level up pays coins (EconomyService.award, source
	  "Level") and fires LevelUp { Level, Coins, Bonus, Increase, Milestone, Next }
	  (the client's juicy moment). At most LevelConfig.MaxShownLevels
	  moments per gain; the rest are paid quietly.
	- An old save's first look (Level.Ready = false) backfills its XP
	  silently: no coins, no moment.
	- The level gives +1 % podium income each (EconomyService.addIncomeBonus
	  "Level", capped by LevelConfig.BonusCap), shows as the player attribute
	  Level, in the State snapshot (Level = { Level, Xp, Need, Bonus }) and
	  on the HALL OF FAME's LEVEL board (LeaderboardService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared.Config.LevelConfig)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PodiumService = require(script.Parent.PodiumService)
local StateService = require(script.Parent.StateService)

local LevelService = {}

LevelService.Attribute = "Level"

export type Up = { Level: number, Coins: number, Bonus: number, Increase: number, Milestone: boolean, Next: number }

local function levelOf(data: { [string]: any }?): number
	local record = if data then data.Level else nil
	local level = if type(record) == "table" then record.Level else nil
	return if type(level) == "number" and level == level then math.clamp(math.floor(level), 1, LevelConfig.MaxLevel) else 1
end
LevelService.levelOf = levelOf

-- One look at a player's save: XP for what grew, level ups paid. Returns the
-- XP gained and the level ups (for the tests; `income` = podium coins / s).
function LevelService.step(data: { [string]: any }, income: number): (number, { Up }, boolean)
	local record = LevelConfig.sanitize(data)
	local now = LevelConfig.counters(data)
	if not record.Ready then
		-- a save from before levels: everything it did so far, silently
		record.Seen = now
		record.Ready = true
		LevelConfig.add(record, LevelConfig.backfill(now))
		return 0, {}, true
	end
	local gained = LevelConfig.collect(record, now)
	if gained <= 0 then
		return 0, {}, false
	end
	local ups: { Up } = {}
	for _, level in LevelConfig.add(record, gained) do
		table.insert(ups, {
			Level = level,
			Coins = LevelConfig.coinsFor(level, income),
			Bonus = LevelConfig.bonusFor(level),
			Increase = LevelConfig.bonusFor(level) - LevelConfig.bonusFor(level - 1), -- 0 past the cap
			Milestone = LevelConfig.isMilestone(level),
			Next = LevelConfig.need(level),
		})
	end
	return gained, ups, true
end

local function look(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local ok, income = pcall(PodiumService.incomeOf, player, data)
	local gained, ups, changed = LevelService.step(data, if ok and type(income) == "number" then income else 0)
	if not changed then
		return
	end
	local record = data.Level
	player:SetAttribute(LevelService.Attribute, record.Level)
	for _, up in ups do
		EconomyService.award(player, up.Coins, "Level", true)
	end
	DataService.changed(player)
	if gained > 0 then
		Net.fire("XpGain", player, {
			Gain = gained,
			Level = record.Level,
			Xp = record.Xp,
			Need = LevelConfig.need(record.Level),
		})
	end
	for i, up in ups do
		-- many levels at once (a big counter jump): the last few get a moment
		if i > #ups - LevelConfig.MaxShownLevels then
			Net.fire("LevelUp", player, up)
		end
	end
end
LevelService._look = look

function LevelService.init()
	EconomyService.addIncomeBonus(function(player: Player): number
		return LevelConfig.bonusFor(levelOf(DataService.get(player)))
	end, "Level")
	StateService.addProvider(function(_player: Player, data: { [string]: any }, snapshot: { [string]: any })
		local record = LevelConfig.sanitize(data)
		snapshot.Level = {
			Level = record.Level,
			Xp = math.floor(record.Xp),
			Need = LevelConfig.need(record.Level),
			Bonus = LevelConfig.bonusFor(record.Level),
		}
	end)
end

function LevelService.start()
	DataService.onLoaded(function(player: Player, _data: { [string]: any })
		look(player)
		local data = DataService.get(player)
		if data then
			player:SetAttribute(LevelService.Attribute, levelOf(data))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(LevelConfig.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(look :: (Player) -> any, player)
				if not ok then
					warn(`[LevelService] {player.Name}: {err}`)
				end
			end
		end
	end)
end

return LevelService
