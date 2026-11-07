--[[
	NightShiftService: Night Shift (owner 2026-11-07), what the base does while
	the player is away besides the podiums' coins (PodiumService).

	- onReturn (PodiumService's hook, when the welcome-back window would open):
	    the machines finish ore from the pen for (seconds away, capped) x the
	    offline rate (Machines/NightShiftLine). Only with the sorting billboard
	    on and a belt on the PEN chute: that is the ore they would have got.
	    A long enough absence earns the crate (NightShiftConfig.earnsCrate,
	    data.NightShift). Returns { Made?, Crate? } for the window, nil if
	    neither. Made = { Total, Bars, List = up to ListMax rows, best first }.
	    No yields: the pen's list changes in one step.
	- NightCrate (the window's Open Crate): if one waits, rolls NightShiftConfig
	  .pick and pays: coins, dirty ores into the pen (no room: what Tobin would
	  pay for them dirty) or a relic (a zone with none left: the coins). Answer
	  NightCrateResult. A crate not opened waits for the next return.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local MachineData = require(Shared.Config.MachineData)
local NightShiftConfig = require(Shared.Config.NightShiftConfig)
local NightShiftLine = require(Shared.Machines.NightShiftLine)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local ArtifactService = require(script.Parent.ArtifactService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PenService = require(script.Parent.PenService)
local PodiumService = require(script.Parent.PodiumService)

local NightShiftService = {}

NightShiftService.ListMax = 5 -- rows of "Collected for you"

-- (tests) rolls and the wall clock
NightShiftService.random = math.random
NightShiftService.clock = os.time

local function recordOf(data: { [string]: any }): { [string]: any }
	local night = data.NightShift
	if type(night) ~= "table" then
		night = { CrateAt = 0, Ready = false }
		data.NightShift = night
	end
	return night
end

-- Would the sorting billboard send the pen's ore? (it needs a belt on the PEN chute)
local function lineOn(data: { [string]: any }): boolean
	local upgrades = data.Upgrades
	local automation = if type(upgrades) == "table" then tonumber(upgrades.PenAutomation) else nil
	if not automation or automation < EconomyConfig.PenAutomation.Billboard or not PenService.autoSortOn(data) then
		return false
	end
	local chute = BaseLayout.Chutes.Pen
	local placed = data.PlacedMachines
	if type(placed) == "table" then
		for _, entry in placed do
			local info = if type(entry) == "table" and type(entry.Id) == "string" then MachineData.ById[entry.Id] else nil
			if info and info.IsConveyor and entry.X == chute.X and entry.Z == chute.Z then
				return true
			end
		end
	end
	return false
end

local function runMachines(data: { [string]: any }, work: number): { [string]: any }?
	local storage = data.Storage
	if type(storage) ~= "table" or not lineOn(data) then
		return nil
	end
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	local capacity = EconomyConfig.penCapacity(upgrades.PenLevel, GameConfig.MaxStoredItems)
	local report = NightShiftLine.run(storage, NightShiftLine.line(data), work, capacity, data.KeepMode, data.KeepList, function(machineId)
		local machine = MachineData.ById[machineId]
		return if machine and machine.QualityLevels
			then MachineData.gradeOdds(EconomyConfig.upgradeLevel(data, machineId, "Quality"))
			else nil
	end, NightShiftService.random)
	if report.Total == 0 then
		return nil
	end
	local rows = {}
	for _, row in report.Made do
		table.insert(rows, row)
	end
	local function worth(row: any): number
		return ItemData.value(row.K, row.O, row.G)
	end
	table.sort(rows, function(a, b)
		local va, vb = worth(a), worth(b)
		if va ~= vb then
			return va > vb
		end
		return `{a.K}{a.O}{a.G}` < `{b.K}{b.O}{b.G}`
	end)
	local list = {}
	for k = 1, math.min(NightShiftService.ListMax, #rows) do
		list[k] = rows[k]
	end
	return { Total = report.Total, Bars = report.Bars, List = list }
end

-- See the header. `seconds` away, `extended`: the OfflineExtension perk.
function NightShiftService.onReturn(player: Player, data: { [string]: any }, seconds: number, extended: boolean): { [string]: any }?
	local work = math.min(seconds, EconomyConfig.offlineHours(extended) * 3600) * EconomyConfig.offlineRate(extended)
	local made = runMachines(data, work)
	local night = recordOf(data)
	local now = NightShiftService.clock()
	local earned = NightShiftConfig.earnsCrate(night, seconds, now)
	if earned then
		night.Ready = true
		night.CrateAt = now
	end
	if made or earned then
		DataService.changed(player)
	end
	if not made and night.Ready ~= true then
		return nil
	end
	return { Made = made, Crate = night.Ready == true }
end

local function payCoins(player: Player, data: { [string]: any }, result: { [string]: any })
	local amount = NightShiftConfig.coins(PodiumService.incomeOf(player, data))
	EconomyService.award(player, amount, "NightCrate")
	result.Prize = "Coins"
	result.Amount = amount
end

local function payOres(player: Player, data: { [string]: any }, result: { [string]: any })
	local floor = NightShiftConfig.floorFor(tonumber(data.BlasterLevel) or 1)
	local stored, coins = 0, 0
	for _ = 1, NightShiftConfig.Crate.OreCount do
		local oreId = NightShiftConfig.pickOre(floor, NightShiftService.random())
		if PenService.store(player, { K = "Raw", O = oreId }) then
			stored += 1
			-- (the tutorial counts the pen's ore as "came home by train" only without these)
			local stats = data.Stats
			if type(stats) == "table" then
				stats.WheelOres = (tonumber(stats.WheelOres) or 0) + 1
			end
		else
			coins += Bonuses.sellAmount(Bonuses.stats(player), ItemData.value("Raw", oreId))
		end
	end
	if coins > 0 then
		EconomyService.award(player, coins, "NightCrate")
		result.Amount = coins
	end
	result.Prize = "Ores"
	result.Ores = stored
end

local function payRelic(player: Player, data: { [string]: any }, result: { [string]: any })
	local floor = NightShiftConfig.floorFor(tonumber(data.BlasterLevel) or 1)
	local id = ArtifactConfig.pick(floor.ZoneId, NightShiftService.random())
	if id and ArtifactService.find(player, floor.ZoneId, nil, id) then
		result.Prize = "Relic"
		result.Artifact = id
	else
		payCoins(player, data, result)
	end
end

-- NightCrate: see the header. Returns the answer.
function NightShiftService.open(player: Player): { [string]: any }
	local data = DataService.get(player)
	local night = if data then recordOf(data) else nil
	if not data or not night or night.Ready ~= true then
		return { Ok = false }
	end
	night.Ready = false
	local result: { [string]: any } = { Ok = true }
	local prize = NightShiftConfig.pick(NightShiftService.random())
	if prize == "Ores" then
		payOres(player, data, result)
	elseif prize == "Relic" then
		payRelic(player, data, result)
	else
		payCoins(player, data, result)
	end
	DataService.changed(player)
	return result
end

function NightShiftService.init()
	PodiumService.onReturn(NightShiftService.onReturn)
end

function NightShiftService.start()
	Net.on("NightCrate", function(player)
		Net.fire("NightCrateResult", player, NightShiftService.open(player))
	end)
end

return NightShiftService
