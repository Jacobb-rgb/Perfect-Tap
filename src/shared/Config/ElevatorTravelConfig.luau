--[[
	The elevator's travel cinematic (owner 2026-11-15, "ROBLOX ELEVATOR TRAVEL
	ANIMATION"): one timeline shared by the server (ElevatorService: when the
	character moves, how long a rider counts as riding) and the client
	(Controllers/ElevatorTravelController drives Builders/ElevatorCabinStage,
	Builders/ElevatorArrivalFx and UI/ElevatorTravelView), plus every mine's
	arrival look.

	Seconds from the server's "Depart":
	  PHASE 1  0.0-0.7   preparation at the stop the player stands at (the floor
	                     window still open): the picked card glows, PREPARING
	                     ELEVATOR..., the cage lamp turns up, a yellow warning light
	                     flashes twice, a small shake, a mechanical clunk
	  PHASE 2  0.7-1.5   inside: a short dip to black, the camera stands in the cabin
	                     (built over the real cage), the steel doors slide shut over
	                     the mine being left, the screen over the doors shows the
	                     target floor; the doors meet with a thud
	  PHASE 3  1.5-~4    the ride: a jolt, the shaft rushes past the windows (rock,
	                     crystals, beams, lamps; a landing band at every floor
	                     passed), dust, glowing motes, light streaks, a rumble, the
	                     lights flicker now and then, the digital counter counts to
	                     the target; the server moves the character behind the shut
	                     doors (DoorsShut + 0.1)
	  PHASE 4  ~4-~5.8   arrival: the cabin brakes (a screech, a bump), one flash, the
	                     cabin now stands at the target stop, ARRIVED! and the mine's
	                     name, the doors open on the real floor with its own effects,
	                     the camera pulls back to the player, the controls come back
	The ride grows a little with the floors travelled (Travel + PerFloor for every
	floor after the first, at most TravelMax): 5.4-5.8 s in all. The arrival
	waits for the server's "Arrive" (the character stands at the target stop):
	until then the shaft keeps rushing (at most FailSafe seconds, then the client
	gives the game back).

	Reduce motion (UI/Motion.reduced): no shake, jolt or flicker, no flash (the
	lights swell instead), no light streaks or electric arcs, fewer particles, and
	fades instead of the camera's glides.
]]

local ElevatorTravelConfig = {}

ElevatorTravelConfig.Timing = {
	Enter = 0.7, -- PHASE 2: the window closes, the dip to black starts
	DipOut = 0.12, -- seconds to black
	DipIn = 0.2, -- seconds back from black (the camera is in the cabin by then)
	DoorsCloseAt = 0.95, -- the doors start to close
	DoorsShut = 1.5, -- the doors meet (PHASE 3: the ride starts with a jolt)
	SpeedUp = 0.45, -- the shaft gets up to speed
	Travel = 1.9, -- seconds of ride for one floor ...
	PerFloor = 0.1, -- ... and this much more for every floor after the first ...
	TravelMax = 2.3, -- ... at most
	TickLead = 0.3, -- the counter's first tick comes this long after the jolt at the soonest
	Brake = 0.5, -- PHASE 4: the shaft slows to a stop
	OpenDelay = 0.3, -- the doors start to open this long after the stop
	DoorsOpen = 0.6, -- seconds the doors take to open
	ExitDelay = 0.45, -- the camera starts back to the player this long after the doors start to open
	Exit = 0.75, -- seconds the camera takes back to the player (the end)
	Prepare = { 0.05, 0.4 }, -- PHASE 1: the warning light's two flashes start here ...
	FlashOn = 0.14, -- ... and stay lit this long (about 2.6 flashes a second at most)
	Flicker = 0.08, -- a light flicker in the ride lasts this long
	FailSafe = 6, -- the arrival waits this long at most for the server's "Arrive"
}

-- The server keeps a rider "riding" until this long before the client's end (never later than the
-- client: a player who taps a floor right after the doors opened is never refused).
ElevatorTravelConfig.HoldMargin = 0.35

-- The shaft's top speed (studs a second) and the camera.
ElevatorTravelConfig.ShaftSpeed = 62
ElevatorTravelConfig.Fov = 70
ElevatorTravelConfig.Shake = {
	Prepare = 0.035, -- studs (PHASE 1, the window still open)
	Ride = 0.045, -- the rumble while the shaft rushes
	Jolt = 0.16, -- the dip when the cabin starts
	Bump = 0.14, -- the dip when it stops
	Turn = 0.25, -- degrees of roll per stud of shake
}

export type Tick = { Time: number, Floor: number }

export type Plan = {
	From: number,
	To: number,
	Floors: number, -- floors travelled (1 at least)
	Down: boolean, -- deeper (a higher floor index)
	Enter: number,
	DipMid: number, -- the screen is black: the camera moves into the cabin
	DoorsCloseAt: number,
	DoorsShut: number,
	TravelStart: number,
	BrakeAt: number,
	StopAt: number,
	DoorsOpenAt: number,
	OpenedAt: number,
	ExitAt: number,
	EndAt: number,
	Ticks: { Tick },
	Flickers: { number },
}

-- Seconds of ride between the doors meeting and the brake, for `floors` floors travelled.
function ElevatorTravelConfig.travelTime(floors: number): number
	local timing = ElevatorTravelConfig.Timing
	local n = math.max(1, math.floor(floors))
	return math.min(timing.TravelMax, timing.Travel + timing.PerFloor * (n - 1))
end

-- A whole floor index from the network (nil for junk).
local function floorOf(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local n = math.floor(value)
	return if n >= 1 and n <= 99 then n else nil
end

--[[
	The timeline of a ride from floor `from` to floor `to` (junk falls back to
	sane values: an unknown start = one floor away). Pure: the client plays it,
	the server reads its end, the Lune previews pose it.
]]
function ElevatorTravelConfig.plan(from: any, to: any): Plan
	local timing = ElevatorTravelConfig.Timing
	local target = floorOf(to) or 1
	local start = floorOf(from) or (if target > 1 then target - 1 else target + 1)
	if start == target then
		start = if target > 1 then target - 1 else target + 1
	end
	local floors = math.abs(target - start)
	local travelStart = timing.DoorsShut
	local brakeAt = travelStart + ElevatorTravelConfig.travelTime(floors)
	local stopAt = brakeAt + timing.Brake
	local openAt = stopAt + timing.OpenDelay
	local exitAt = openAt + timing.ExitDelay
	-- one tick per floor, spread evenly from TickLead after the jolt to the middle of the brake
	local ticks: { Tick } = {}
	local first = travelStart + timing.TickLead
	local last = brakeAt + timing.Brake * 0.5
	local spacing = (last - first) / floors
	local step = if target > start then 1 else -1
	for k = 1, floors do
		table.insert(ticks, { Time = first + spacing * (k - 0.5), Floor = start + step * k })
	end
	-- two short flickers in the ride (never in the jolt or the brake)
	local flickers: { number } = {}
	for _, at in { travelStart + 0.85, brakeAt - 0.45 } do
		if at > travelStart + timing.SpeedUp and at + timing.Flicker < brakeAt then
			table.insert(flickers, at)
		end
	end
	return {
		From = start,
		To = target,
		Floors = floors,
		Down = target > start,
		Enter = timing.Enter,
		DipMid = timing.Enter + timing.DipOut,
		DoorsCloseAt = timing.DoorsCloseAt,
		DoorsShut = timing.DoorsShut,
		TravelStart = travelStart,
		BrakeAt = brakeAt,
		StopAt = stopAt,
		DoorsOpenAt = openAt,
		OpenedAt = openAt + timing.DoorsOpen,
		ExitAt = exitAt,
		EndAt = exitAt + timing.Exit,
		Ticks = ticks,
		Flickers = flickers,
	}
end

-- Seconds from "Depart" the server keeps the rider riding (one ride at a time).
function ElevatorTravelConfig.hold(from: any, to: any): number
	return ElevatorTravelConfig.plan(from, to).EndAt - ElevatorTravelConfig.HoldMargin
end

-- Seconds the client still plays after a late "Arrive" (from the brake to the end), less the margin.
function ElevatorTravelConfig.arriveTail(): number
	local plan = ElevatorTravelConfig.plan(1, 2)
	return plan.EndAt - plan.BrakeAt - ElevatorTravelConfig.HoldMargin
end

-- The floor the counter shows at `t` (the floor left until the first tick).
function ElevatorTravelConfig.floorAt(plan: Plan, t: number): number
	local floor = plan.From
	for _, tick in plan.Ticks do
		if t >= tick.Time then
			floor = tick.Floor
		end
	end
	return floor
end

---------------------------------------------------------------- the mines' arrivals

export type Theme = {
	Light: Color3, -- the arrival light in front of the doors, the cabin's lights once the doors open
	Glow: Color3, -- the screen's digits and the door seams on the way there, ARRIVED!'s edge
	Pulse: number, -- the arrival light pulses this many times a second (0 = one smooth swell)
	Dust: Color3?, -- slow dust clouds rolling in through the doors
	Motes: Color3?, -- glowing motes drifting by the doors ...
	MotesRise: number, -- ... this fast upward (studs a second; below 0 they fall like glitter)
	Sparks: Color3?, -- a burst of quick sparks as the doors open
	Pebbles: Color3?, -- small rocks tumble down in front of the doors
	Crystals: Color3?, -- crystal shards grow out of the ground by the doors
	Ring: Color3?, -- a glowing ring runs out over the ground (gold details)
	Arcs: Color3?, -- short electric arcs crackle by the doors (never with Reduce motion)
	Core: Color3?, -- a glowing core hangs over the doorway and pulses with the light
	Sound: string, -- a SoundConfig key played as the doors open
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- By MineFloors floor Id (the game's own names: Greystone Quarry ... Heartstone Core).
ElevatorTravelConfig.Themes = {
	-- Greystone Quarry: brown dust, small rocks, warm light
	Quarry = {
		Light = rgb(255, 196, 128),
		Glow = rgb(255, 170, 90),
		Pulse = 0,
		Dust = rgb(150, 112, 76),
		Motes = rgb(255, 214, 160),
		MotesRise = 1.5,
		Pebbles = rgb(132, 120, 108),
		Sound = "ElevatorArriveQuarry",
	},
	-- Ember Caves: glowing embers, sparks, red light
	EmberCaves = {
		Light = rgb(255, 84, 40),
		Glow = rgb(255, 120, 40),
		Pulse = 0,
		Dust = rgb(70, 34, 28),
		Motes = rgb(255, 140, 40),
		MotesRise = 4,
		Sparks = rgb(255, 196, 90),
		Sound = "ElevatorArriveEmber",
	},
	-- Deep Hollow: blue crystals, cool blue motes, blue light
	DeepHollow = {
		Light = rgb(90, 186, 255),
		Glow = rgb(62, 200, 220),
		Pulse = 0,
		Motes = rgb(150, 226, 255),
		MotesRise = 1.2,
		Crystals = rgb(62, 200, 230),
		Sound = "ElevatorArriveHollow",
	},
	-- Sunken Palace: golden glitter, glowing gold details, warm golden light
	SunkenPalace = {
		Light = rgb(255, 200, 96),
		Glow = rgb(255, 196, 58),
		Pulse = 0,
		Motes = rgb(255, 214, 90),
		MotesRise = -1.5,
		Sparks = rgb(255, 236, 160),
		Ring = rgb(255, 200, 70),
		Sound = "ElevatorArrivePalace",
	},
	-- Stormglass Rift: purple energy, electric sparks, violet light
	StormglassRift = {
		Light = rgb(168, 108, 255),
		Glow = rgb(190, 140, 255),
		Pulse = 0,
		Motes = rgb(186, 132, 255),
		MotesRise = 2.5,
		Sparks = rgb(236, 222, 255),
		Arcs = rgb(214, 190, 255),
		Sound = "ElevatorArriveStorm",
	},
	-- Heartstone Core: magenta energy, a pulsing light, a glowing core
	HeartstoneCore = {
		Light = rgb(255, 60, 170),
		Glow = rgb(255, 90, 200),
		Pulse = 1.6,
		Motes = rgb(255, 110, 210),
		MotesRise = 3,
		Core = rgb(255, 120, 220),
		Sound = "ElevatorArriveCore",
	},
} :: { [string]: Theme }

-- A floor Id with no theme of its own (a floor added later) gets this one.
ElevatorTravelConfig.DefaultTheme = "Quarry"

function ElevatorTravelConfig.theme(floorId: string?): Theme
	local theme = if floorId then ElevatorTravelConfig.Themes[floorId] else nil
	return theme or ElevatorTravelConfig.Themes[ElevatorTravelConfig.DefaultTheme]
end

-- The arrival's light over time (0..1; `since` = seconds after the stop): it swells in as the doors
-- open and dies away; a pulsing theme beats on top. Reduce motion: no beat, a slower swell.
function ElevatorTravelConfig.arrivalLight(theme: Theme, since: number, reduced: boolean): number
	if since < 0 then
		return 0
	end
	local rise = if reduced then 0.5 else 0.25
	local swell = math.clamp(since / rise, 0, 1)
	local fade = 1 - math.clamp((since - 1.1) / 1.2, 0, 1)
	local level = swell * fade
	if theme.Pulse > 0 and not reduced then
		level *= 0.7 + 0.3 * math.cos(since * theme.Pulse * 2 * math.pi)
	end
	return level
end

-- Seconds the arrival's effects keep playing after the stop (then the client takes them away).
ElevatorTravelConfig.ArrivalTime = 2.6

return ElevatorTravelConfig
