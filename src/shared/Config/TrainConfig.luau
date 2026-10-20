--[[
	Per-player ore trains (design v2, docs/plans/STEP2_PLAN.md).

	You throw ore into the Mine Station hopper (quarry floor) or a Mine Lift
	(Ember Caves, Deep Hollow); it becomes your train's cargo. The train
	leaves when it is full, when you press Send, or AutoDepartSeconds after
	the last load. It rolls out of the station into a tunnel in the quarry
	wall, comes out of a tunnel on the south coast, runs north along the
	coastal railway behind the bases to your Train Stop and pours the ore into
	your Ore Pen. The server only keeps times; clients animate the trip from
	those times (Timeline shares).
]]

local WorldLayout = require(script.Parent.WorldLayout)
local BaseLayout = require(script.Parent.BaseLayout)
local MineFloors = require(script.Parent.MineFloors)

export type Level = { Value: number, Price: number }

local TrainConfig = {}

-- Cargo slots per capacity level (index 1 = level 0, the starting train).
TrainConfig.Capacity = {
	{ Value = 8, Price = 0 },
	{ Value = 12, Price = 2000 },
	{ Value = 18, Price = 15000 },
	{ Value = 26, Price = 120000 },
	{ Value = 36, Price = 900000 },
	{ Value = 50, Price = 6e6 },
} :: { Level }

-- Trip seconds (station -> your stop) per speed level (index 1 = level 0).
TrainConfig.Speed = {
	{ Value = 30, Price = 0 },
	{ Value = 25, Price = 3000 },
	{ Value = 21, Price = 25000 },
	{ Value = 17, Price = 200000 },
	{ Value = 14, Price = 1.5e6 },
	{ Value = 12, Price = 10e6 },
} :: { Level }

-- The Express perk (one-time Robux upgrade, sign at every base).
TrainConfig.Express = { SpeedMult = 2, CapacityMult = 1.5 }

TrainConfig.AutoDepartSeconds = 25 -- after the last load, a train with cargo leaves by itself
TrainConfig.MinTripSeconds = 5 -- no upgrade makes a trip shorter than this
TrainConfig.ReturnSeconds = 6 -- the empty train rolls back before it can load again (the station shows "returning")
TrainConfig.DeliveryRetry = 3 -- seconds between tries when the pen is full
TrainConfig.MaxCargoSaved = 80 -- hard cap per save (Cargo + TripCargo), DataStore safety
TrainConfig.MaxTripSpan = 600 -- clients refuse a TrainTrip with ArriveAt - DepartAt above this (the server never sends one)

-- The prompts on every Mine Station / Mine Lift PromptPoint (shared contract,
-- docs/plans/STEP2_PLAN.md): UIOffset = (0, slot * PromptSlotHeight). Load and
-- Send are the server's (tagged PromptTag, attribute Action = "Load" | "Send"),
-- Panel is the client's own untagged "Train" prompt. No two share a slot.
TrainConfig.PromptTag = "TrainPrompt"
TrainConfig.PromptSlotHeight = 72 -- UIOffset pixels per slot (the machine prompts' step)
TrainConfig.PromptSlots = { Load = 0, Send = 1, Panel = 2 }

-- What a client shows when (share of the trip, 0..1).
TrainConfig.Timeline = {
	QuarryLeg = { 0, 0.15 }, -- station -> quarry wall portal (visible)
	Underground = { 0.15, 0.7 }, -- hidden
	CoastLeg = { 0.7, 0.95 }, -- south portal -> your Train Stop (visible)
	Unload = { 0.95, 1 }, -- the wagon tips into the pen
}

---------------------------------------------------------------- world

local QUARRY_Y = WorldLayout.Quarry.Min.Y -- -12, the quarry floor
local RAIL_X = 104 + BaseLayout.RailZ -- plots sit at x = +-104; the rail runs at plot-local z = RailZ

-- Mine Station on the quarry floor, east of the ramp bottom (the ramp is x -8..8, z -112..-140).
TrainConfig.Station = {
	Platform = { Center = Vector3.new(26, QUARRY_Y, -147), Size = Vector3.new(28, 1.2, 6) },
	Hopper = Vector3.new(26, QUARRY_Y, -147), -- bottom center of the station hopper (the intake)
	HopperSize = Vector3.new(7, 5, 5),
	PromptPoint = Vector3.new(20, QUARRY_Y + 3, -144),
}

-- The quarry line: through the station from the west to the east wall portal.
TrainConfig.QuarryLine = {
	Vector3.new(-72, QUARRY_Y, -156),
	Vector3.new(72, QUARRY_Y, -156),
}
TrainConfig.QuarryStop = Vector3.new(26, QUARRY_Y, -156) -- where trains wait at the station

-- Coastal lines behind the bases, from the south portal north to a buffer stop.
TrainConfig.SouthPortalZ = 126
TrainConfig.BufferZ = -100
TrainConfig.CoastWest = { Vector3.new(-RAIL_X, 0, 126), Vector3.new(-RAIL_X, 0, -100) }
TrainConfig.CoastEast = { Vector3.new(RAIL_X, 0, 126), Vector3.new(RAIL_X, 0, -100) }

-- Where the lines' visible parts end (Railway builds them there, the client
-- hides the trains at the same planes and stops them short of the buffers).
TrainConfig.PortalInset = 6 -- the quarry tunnel mouths stand this far in front of the quarry line's ends
TrainConfig.BufferGap = 1.7 -- the coastal buffer stops' face, past the coastal lines' ends

-- Mine Lifts: throw ore in down in the caves, it goes into your train's cargo.
-- One per mine floor 2-5, where the floor area leaves room for it (MineFloors.LiftSpots).
local function liftAt(index: number): Vector3
	return MineFloors.liftPosition(index) or Vector3.zero
end
TrainConfig.Lifts = {
	{ Id = "EmberCaves", Position = liftAt(2), Size = Vector3.new(6, 5, 6) },
	{ Id = "DeepHollow", Position = liftAt(3), Size = Vector3.new(6, 5, 6) },
	{ Id = "SunkenPalace", Position = liftAt(4), Size = Vector3.new(6, 5, 6) },
	{ Id = "HeartstoneCore", Position = liftAt(5), Size = Vector3.new(6, 5, 6) },
}

-- (Rocks and big decorations stay off the track, the station and the lifts:
-- their boxes are in WorldLayout.KeepOut.)

---------------------------------------------------------------- helpers

local function levelOf(list: { Level }, level: any): Level
	local n = if type(level) == "number" and level == level then math.floor(level) else 0
	return list[math.clamp(n, 0, #list - 1) + 1]
end

function TrainConfig.maxLevel(list: { Level }): number
	return #list - 1
end

-- Cargo slots for a capacity level (Express adds half).
function TrainConfig.capacity(level: any, express: boolean): number
	local base = levelOf(TrainConfig.Capacity, level).Value
	return if express then math.floor(base * TrainConfig.Express.CapacityMult) else base
end

-- Trip seconds for a speed level (Express halves it; `cut` = the share cut off,
-- the rebirth's Express Rails: Bonuses TrainTimeCutPct, at most half), never
-- under MinTripSeconds.
function TrainConfig.tripSeconds(level: any, express: boolean, cut: number?): number
	local base = levelOf(TrainConfig.Speed, level).Value
	local seconds = if express then base / TrainConfig.Express.SpeedMult else base
	local share = if type(cut) == "number" and cut == cut then math.clamp(cut, 0, 0.5) else 0
	return math.max(TrainConfig.MinTripSeconds, seconds * (1 - share))
end

-- Price of the next level of an upgrade (nil when maxed).
function TrainConfig.nextPrice(list: { Level }, level: any): number?
	local n = if type(level) == "number" and level == level then math.floor(level) else 0
	local nextEntry = list[math.clamp(n, 0, #list) + 2]
	return if nextEntry then nextEntry.Price else nil
end

-- Which coastal line serves a plot (west plots have x < 0).
function TrainConfig.lineFor(plot: WorldLayout.Plot): { Vector3 }
	return if plot.Center.X < 0 then TrainConfig.CoastWest else TrainConfig.CoastEast
end

-- Where a plot's train stops on its coastal line.
function TrainConfig.stopFor(plot: WorldLayout.Plot): Vector3
	local line = TrainConfig.lineFor(plot)
	return Vector3.new(line[1].X, 0, plot.Center.Z)
end

return TrainConfig
