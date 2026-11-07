--[[
	NightShiftService: Night Shift (owner 2026-11-07), what comes with an absence
	besides the podiums' coins (PodiumService).

	- onReturn (PodiumService's hook, with every payout of an absence): a long
	  enough one earns the crate (NightShiftConfig.earnsCrate, data.NightShift).
	  Returns { Crate, PenFull } for the window. It also runs when no window opens
	  (a player leaving during the first seconds): the crate stays earned.
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
local NightShiftConfig = require(Shared.Config.NightShiftConfig)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local ArtifactService = require(script.Parent.ArtifactService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PenService = require(script.Parent.PenService)
local PodiumService = require(script.Parent.PodiumService)

local NightShiftService = {}

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

-- See the header. `seconds` away, `extended`: the OfflineExtension perk.
function NightShiftService.onReturn(player: Player, data: { [string]: any }, seconds: number, _extended: boolean): { [string]: any }
	local night = recordOf(data)
	local now = NightShiftService.clock()
	if NightShiftConfig.earnsCrate(night, seconds, now) then
		night.Ready = true
		night.CrateAt = now
		DataService.changed(player)
	end
	return { Crate = night.Ready == true, PenFull = penFull(data) }
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
