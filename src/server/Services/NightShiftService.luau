--[[
	NightShiftService: Night Shift (owner 2026-11-07), what comes with an absence
	besides the podiums' coins (PodiumService).

	- onReturn (PodiumService's hook, with every payout of an absence):
	    the machines work the Ore Feeder's ore for (seconds away, capped) x the
	    offline rate (Machines/FeederNight; owner 2026-11-07: only ore the
	    player put in the feeder, never the pen by itself); what comes out goes
	    into the pen. Ore that comes out of the dirt is discovered, quietly. A
	    long enough absence earns the crate (NightShiftConfig.earnsCrate,
	    data.NightShift). Returns { Made?, Why?, Crate, PenFull } for the
	    window: Made = { Fed, Total, Bars, List = up to ListMax rows, best
	    first, Left = ores still in the feeders, PenStopped }; an Iron Box
	    on the plot keeps what the player keeps (MachineData.keeps); Why = why the machines made nothing ("NoFeeder" | "Empty" |
	    "NoMachines" | "PenFull" | "Nothing"). It also runs when no window opens
	    (a player leaving during the first seconds). No yields: the feeders'
	    queues and the pen's list change in one step.
	- NightCrate (the window's Open Crate): if one waits, rolls NightShiftConfig
	  .pick and pays: coins, dirty ores into the pen (no room: what Tobin would
	  pay for them dirty) or a relic (a zone with none left: the coins). Answer
	  NightCrateResult. A crate not opened waits for the next return.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local MachineData = require(Shared.Config.MachineData)
local FeederNight = require(Shared.Machines.FeederNight)
local NightShiftConfig = require(Shared.Config.NightShiftConfig)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Discovery = require(script.Parent.Parent.Discovery)
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

-- Is there no room in the pen for the crate's ores?
local function penFull(data: { [string]: any }): boolean
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	local count = if type(data.Storage) == "table" then #data.Storage else 0
	return count + NightShiftConfig.Crate.OreCount > EconomyConfig.penCapacity(upgrades.PenLevel, GameConfig.MaxStoredItems)
end

local function floorOf(data: { [string]: any }): any
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	return NightShiftConfig.floorFor(tonumber(data.BlasterLevel) or 1, upgrades.Elevator == true)
end

-- Has the player placed a machine that passes `test`?
local function hasPlaced(data: { [string]: any }, test: (any) -> boolean): boolean
	local placed = data.PlacedMachines
	if type(placed) ~= "table" then
		return false
	end
	for _, entry in placed do
		local info = if type(entry) == "table" and type(entry.Id) == "string" then MachineData.ById[entry.Id] else nil
		if info and test(info) then
			return true
		end
	end
	return false
end

local function isFeeder(info: any): boolean
	return info.Behaviour == "Feeder"
end

local function isIronBox(info: any): boolean
	return info.Id == "IronBox"
end

-- The live feeders show their new counts (FeederService, looked up on use).
local function refreshFeeders(player: Player)
	pcall(function()
		local FeederService = require(script.Parent.FeederService) :: any
		FeederService.refresh(player)
	end)
end

-- What the machines made from the feeders' ore (nil: nothing) and why not.
local function runFeeders(player: Player, data: { [string]: any }, work: number): ({ [string]: any }?, string?)
	if not hasPlaced(data, isFeeder) then
		return nil, "NoFeeder"
	end
	local queues = FeederNight.queues(data)
	if #queues == 0 then
		return nil, "Empty"
	end
	local line = FeederNight.line(data)
	-- (review 11-10: the Iron Box keeps what the player keeps, at night too)
	local keep = if hasPlaced(data, isIronBox)
		then function(desc: any): boolean
			return MachineData.keeps(data.KeepMode, data.KeepList, desc)
		end
		else nil
	if next(line) == nil and not keep then
		return nil, "NoMachines"
	end
	if type(data.Storage) ~= "table" then
		data.Storage = {}
	end
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	local capacity = EconomyConfig.penCapacity(upgrades.PenLevel, GameConfig.MaxStoredItems)
	if #data.Storage >= capacity then
		return nil, "PenFull"
	end
	local report = FeederNight.run(queues, data.Storage, line, work, capacity, function(machineId)
		local machine = MachineData.ById[machineId]
		return if machine and machine.QualityLevels
			then MachineData.gradeOdds(EconomyConfig.upgradeLevel(data, machineId, "Quality"))
			else nil
	end, NightShiftService.random, keep)
	if report.Fed == 0 then
		return nil, if report.RoomStopped then "PenFull" else "Nothing"
	end
	local left = 0
	for _, queue in queues do
		left += #queue
	end
	for oreId in report.Cleaned do
		Discovery.mark(player, data, oreId, true)
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
	return {
		Fed = report.Fed,
		Total = report.Total,
		Bars = report.Bars,
		List = list,
		Left = left, -- ores still in the feeders
		PenStopped = report.RoomStopped, -- the pen had no room for more
	},
		nil
end

-- See the header. `seconds` away, `extended`: the OfflineExtension perk.
function NightShiftService.onReturn(player: Player, data: { [string]: any }, seconds: number, extended: boolean): { [string]: any }
	local work = math.min(seconds, EconomyConfig.offlineHours(extended) * 3600) * EconomyConfig.offlineRate(extended)
	local made, why = runFeeders(player, data, work)
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
	if made then
		refreshFeeders(player)
	end
	return { Made = made, Why = why, Crate = night.Ready == true, PenFull = penFull(data) }
end

local function payCoins(player: Player, data: { [string]: any }, result: { [string]: any })
	local amount = NightShiftConfig.coins(PodiumService.incomeOf(player, data))
	EconomyService.award(player, amount, "NightCrate")
	result.Prize = "Coins"
	result.Amount = amount
end

local function payOres(player: Player, data: { [string]: any }, result: { [string]: any })
	local floor = floorOf(data)
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
	local floor = floorOf(data)
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
