--[[
	The elevator ride on screen (owner 2026-10-18: "make some animation during
	that transfer"; "people must be hooked at first sight"). Pure builder +
	pure timing; ElevatorController drives it (ElevatorRideView.pose every
	frame of the ride: positions of a few dozen reused Frames, colours only
	when the tint changes; nothing is created during the ride).

	  doors      two full-screen steel door halves in the panel's style: a
	             vertical steel gradient, a darker inner frame with rows of
	             rivets, a window, a call plate (up / down), a stripe in the
	             target floor's colour, the hazard stripe and a thin neon edge
	             on the seam; they slam shut with a thud and a short shake
	  windows    the shaft passing by: rock bands scroll in the ride direction
	             (going down the wall moves up), tinted by the floor being
	             passed (MineFloors palettes: 1 slate + copper, 2 basalt + lava
	             cracks, 3 lagoon teal + cyan crystals, 4 palace violet + gold
	             trim, 5 core magenta + pink crystals) with crystal glints and
	             one lamp passing per floor; the tint cross-fades at each tick
	  indicator  a panel at the top centre: chevrons flowing in the ride
	             direction, "FLOOR" and the big number in the floor's card
	             colour (a glow pulse and a little pop at every tick), a column
	             of floor dots that light up in their colours as you pass them
	  ride       speed lines along the screen edges and a running light on the
	             edge rails in the ride direction, a gentle rumble shake
	  arrival    once the server says "Arrive" and the ride lasted at least
	             its Duration: ding, the doors slide open on the new floor and
	             a banner "FLOOR 4 · SUNKEN PALACE" in the floor colour slides
	             in and out

	Timeline (seconds from "Depart"): the doors shut by Close; ticks between
	Close + TickLead and MinRide - TickLead; the doors start opening at
	OpenAt (>= MinRide, after "Arrive"; FailSafe seconds later without it);
	the banner follows. Reduced motion: no scrolling, shake, speed lines or
	pops: the doors, the tint changes and the numbers only.

	The doors fill the screen (no UIScale on this gui); the indicator and the
	banner carry their own UIScale (ElevatorRideView.layout) so they follow
	the HUD scale on phones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared.Config.MineFloors)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
local ElevatorView = require(script.Parent.ElevatorView)

local ElevatorRideView = {}

export type Direction = "Down" | "Up"

export type Ride = {
	From: number, -- the floor the ride starts on
	To: number, -- the target floor
	Name: string, -- the target floor's name
	Close: number, -- seconds the doors take to shut
	MinRide: number, -- the doors stay shut at least this long (seconds from the start)
	OpenAt: number?, -- when the doors start to open (nil = still riding)
	Reduced: boolean, -- reduced motion
}

export type Tick = { Time: number, Floor: number }

-- one rock band of a window: the band, its crack / trim line and its glints
export type Band = {
	Frame: Frame,
	Start: number,
	Height: number,
	Shade: number,
	Vein: Frame,
	VeinGlow: Frame,
	Glints: { Frame },
	Halos: { Frame },
}

export type Window = {
	Frame: Frame,
	Shaft: Frame,
	Bands: { Band },
	Lamp: Frame,
	LampGlow: Frame,
}

export type Refs = {
	Gui: ScreenGui,
	Root: Frame, -- moves for the shake
	DoorLeft: Frame,
	DoorRight: Frame,
	Seam: Frame,
	Windows: { Window },
	FloorStripes: { Frame },
	Runners: { Frame }, -- bright segments on the screen-edge rails
	SpeedLines: { Frame },
	Indicator: Frame,
	IndicatorScale: UIScale,
	IndicatorGlow: UIStroke,
	Arrow: Frame,
	Chevrons: { Frame }, -- flowing in the arrow box, tip first
	Number: TextLabel,
	FloorLabel: TextLabel,
	Dots: { Frame },
	Banner: Frame,
	BannerScale: UIScale,
	BannerStroke: UIStroke,
	BannerText: TextLabel,
	UiScale: number,
	TopInset: number,
	TintKey: string, -- the tint last painted (colours change only when it does)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = rgb(10, 12, 26)
local NEON = rgb(70, 170, 255)
local NEON_BRIGHT = rgb(120, 210, 255)
local NAVY_TOP = rgb(26, 34, 72)
local NAVY_BOTTOM = rgb(12, 16, 38)
local TEXT_SOFT = rgb(196, 208, 236)
local HAZARD = rgb(255, 196, 52)
local STEEL_FRAME = rgb(36, 42, 64)

ElevatorRideView.Timing = {
	Close = 0.42, -- the doors slam shut (at most the server's DoorsClose - 0.05)
	Open = 0.45, -- the doors slide open
	TickLead = 0.15, -- no tick right after the thud or right before the ding
	FailSafe = 6, -- the doors open by themselves this long after MinRide without "Arrive"
	IndicatorIn = 0.3,
	IndicatorOut = 0.3,
	BannerDelay = 0.05,
	BannerIn = 0.28,
	BannerHold = 1.0,
	BannerOut = 0.3,
	Thud = 0.3, -- the thud's shake fades over this long
	TintFade = 0.28, -- the window tint cross-fades over this long after a tick
	Pulse = 0.3, -- the indicator's glow pulse and pop fade over this long
	SpeedUp = 0.3, -- the shaft wall gets up to speed over this long after the thud
}

ElevatorRideView.IndicatorSize = Vector2.new(320, 132)
ElevatorRideView.BannerSize = Vector2.new(760, 100)
ElevatorRideView.ShaftSpeed = 2.2 -- window heights of rock wall per second
local SHAKE_ROOM = 16 -- the root is this much bigger on each side, so a shake never shows an edge
-- the rock bands of a window (heights in window heights; they loop, so the sum must be >= 1 + the biggest)
local BANDS = { 0.24, 0.3, 0.22, 0.28, 0.26 }
local BAND_CYCLE = 1.3
-- speed lines per screen side: x (pixels from the edge), length (screen heights), phase
local SPEED_LINES = { { 20, 0.14, 0 }, { 44, 0.2, 0.37 }, { 30, 0.1, 0.71 }, { 62, 0.16, 0.18 }, { 52, 0.12, 0.55 } }
local CHEVRONS = 3

---------------------------------------------------------------- pure timing

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function easeIn(x: number): number
	return x * x
end

local function easeOut(x: number): number
	return 1 - (1 - x) * (1 - x)
end

local function backOut(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local y = x - 1
	return 1 + c3 * y * y * y + c1 * y * y
end

-- "Down" when the target is deeper (a higher floor index), else "Up".
function ElevatorRideView.direction(from: number, to: number): Direction
	return if to >= from then "Down" else "Up"
end

--[[
	A ride from the server's "Depart": `duration` = the least seconds of ride,
	`doorsClose` = when the server moves the character (the doors must be shut
	by then). Junk numbers fall back to sane ones.
]]
function ElevatorRideView.newRide(from: any, to: number, name: string, duration: any, doorsClose: any, reduced: boolean): Ride
	local timing = ElevatorRideView.Timing
	local start = if type(from) == "number" and from == from and from >= 1 then math.floor(from) else to
	local shut = if type(doorsClose) == "number" and doorsClose == doorsClose
		then math.clamp(doorsClose - 0.05, 0.15, timing.Close)
		else timing.Close
	local least = if type(duration) == "number" and duration == duration then math.clamp(duration, 0.5, 6) else 2
	return {
		From = start,
		To = to,
		Name = name,
		Close = shut,
		MinRide = math.max(least, shut + 0.6),
		OpenAt = nil,
		Reduced = reduced,
	}
end

-- One tick per floor travelled, spread over the ride (the number changes at each).
function ElevatorRideView.ticks(ride: Ride): { Tick }
	local steps = math.abs(ride.To - ride.From)
	local list: { Tick } = {}
	if steps == 0 then
		return list
	end
	local first = ride.Close + ElevatorRideView.Timing.TickLead
	local last = ride.MinRide - ElevatorRideView.Timing.TickLead
	local spacing = math.max(0, last - first) / steps
	local step = if ride.To > ride.From then 1 else -1
	for k = 1, steps do
		table.insert(list, { Time = first + spacing * (k - 0.5), Floor = ride.From + step * k })
	end
	return list
end

-- The floor number the indicator shows at `t`.
function ElevatorRideView.numberAt(ride: Ride, t: number): number
	local number = ride.From
	for _, tick in ElevatorRideView.ticks(ride) do
		if t >= tick.Time then
			number = tick.Floor
		end
	end
	return number
end

-- How shut the doors are at `t` (0 = open, 1 = shut).
function ElevatorRideView.closedness(ride: Ride, t: number): number
	if t < ride.Close then
		return easeIn(clamp01(t / ride.Close))
	end
	local openAt = ride.OpenAt
	if not openAt or t < openAt then
		return 1
	end
	return 1 - easeOut(clamp01((t - openAt) / ElevatorRideView.Timing.Open))
end

-- Should the doors start opening now? (after "Arrive" and the least ride time, or the fail-safe)
function ElevatorRideView.shouldOpen(ride: Ride, t: number, arrived: boolean): boolean
	if ride.OpenAt then
		return false
	end
	return (arrived and t >= ride.MinRide) or t >= ride.MinRide + ElevatorRideView.Timing.FailSafe
end

-- When the controls come back: the doors are open.
function ElevatorRideView.openedAt(ride: Ride): number
	return (ride.OpenAt or math.huge) + ElevatorRideView.Timing.Open
end

-- When the overlay is done (the banner has left).
function ElevatorRideView.doneAt(ride: Ride): number
	local timing = ElevatorRideView.Timing
	local openAt = ride.OpenAt or math.huge
	return math.max(openAt + timing.Open, openAt + timing.BannerDelay + timing.BannerIn + timing.BannerHold + timing.BannerOut)
end

-- "FLOOR 4 · SUNKEN PALACE"
function ElevatorRideView.bannerText(floor: number, name: string): string
	return `FLOOR {floor} · {string.upper(name)}`
end

-- The last tick at or before `t` (nil before the first).
function ElevatorRideView.lastTick(ride: Ride, t: number): Tick?
	local found: Tick? = nil
	for _, tick in ElevatorRideView.ticks(ride) do
		if t >= tick.Time then
			found = tick
		end
	end
	return found
end

-- Seconds between two ticks (the ride's shut time when there is none).
function ElevatorRideView.tickSpacing(ride: Ride): number
	local steps = math.abs(ride.To - ride.From)
	local first = ride.Close + ElevatorRideView.Timing.TickLead
	local last = ride.MinRide - ElevatorRideView.Timing.TickLead
	if steps == 0 then
		return math.max(0.3, ride.MinRide - ride.Close)
	end
	return math.max(0.2, (last - first) / steps)
end

--[[
	The windows' tint at `t`: the floor being left, the floor being passed and
	how far the cross-fade between their colours is (1 = all the second).
]]
function ElevatorRideView.tintAt(ride: Ride, t: number): (number, number, number)
	local tick = ElevatorRideView.lastTick(ride, t)
	if not tick then
		return ride.From, ride.From, 1
	end
	local step = if ride.To > ride.From then 1 else -1
	return tick.Floor - step, tick.Floor, clamp01((t - tick.Time) / ElevatorRideView.Timing.TintFade)
end

-- The indicator's tick pulse at `t` (1 right at a tick, fading to 0).
function ElevatorRideView.pulseAt(ride: Ride, t: number): number
	local tick = ElevatorRideView.lastTick(ride, t)
	if not tick then
		return 0
	end
	return 1 - clamp01((t - tick.Time) / ElevatorRideView.Timing.Pulse)
end

-- How far the shaft wall has moved (window heights): up to speed after the thud, frozen once the doors open.
function ElevatorRideView.travel(ride: Ride, t: number): number
	local stop = ride.OpenAt or math.huge
	local u = math.min(t, stop) - ride.Close
	if u <= 0 then
		return 0
	end
	local ramp = ElevatorRideView.Timing.SpeedUp
	local distance = if u < ramp then u * u / (2 * ramp) else ramp / 2 + (u - ramp)
	return distance * ElevatorRideView.ShaftSpeed
end

-- The shaft colours of a floor (MineFloors palette; floors past the list use the last one).
export type Shaft = { Back: Color3, Bands: { Color3 }, Vein: Color3, Glint: Color3, Glint2: Color3, Lamp: Color3 }

function ElevatorRideView.shaftColors(floor: number): Shaft
	local list = MineFloors.List
	local index = math.clamp(floor, 1, #list)
	local p = list[index].Palette
	return {
		Back = p.Dark:Lerp(BLACK, 0.2),
		Bands = {
			p.Mid:Lerp(p.Light, 0.2),
			p.Mid:Lerp(p.Dark, 0.3),
			p.Light:Lerp(p.Mid, 0.1),
			p.Mid:Lerp(p.Light, 0.4),
			p.Dark:Lerp(p.Mid, 0.25),
		},
		Vein = p.Accent,
		Glint = p.Crystal,
		Glint2 = p.Crystal2,
		Lamp = p.Accent:Lerp(WHITE, 0.55),
	}
end

---------------------------------------------------------------- building

local function frame(parent: Instance, name: string, props: { [string]: any }): Frame
	local f: Frame = UIKit.new("Frame", { Name = name, BorderSizePixel = 0 }, parent)
	local target: any = f
	for key, value in props do
		target[key] = value
	end
	return f
end

local function gradient(parent: Instance, keys: { Color3 }, rotation: number)
	local points = {}
	for i, color in keys do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#keys - 1), color))
	end
	UIKit.new("UIGradient", { Color = ColorSequence.new(points), Rotation = rotation }, parent)
end

local function round(parent: Instance, scale: number)
	UIKit.new("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

-- "^" of two bars (the indicator's arrow is three of them, turned for "Down").
local function chevron(parent: Instance, cy: number, color: Color3): Frame
	local box = frame(parent, "Chevron", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, cy),
		Size = UDim2.fromScale(0.8, 0.34),
		BackgroundTransparency = 1,
	})
	for _, spec in { { 0.32, -42 }, { 0.68, 42 } } do
		local bar = frame(box, "Ink", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], 0.56),
			Size = UDim2.fromScale(0.62, 0.42),
			BackgroundColor3 = color,
			Rotation = spec[2],
		})
		round(bar, 0.2)
	end
	return box
end

-- where each band's crack / trim line and its two glints sit (band-relative)
local VEINS = { { 0.36, 0.32, 0.62 }, { 0.62, 0.58, 0.7 }, { 0.42, 0.72, 0.5 }, { 0.55, 0.36, 0.78 }, { 0.32, 0.62, 0.56 } }
local GLINTS = {
	{ { 0.18, 0.4 }, { 0.8, 0.66 } },
	{ { 0.72, 0.3 }, { 0.26, 0.74 } },
	{ { 0.52, 0.5 }, { 0.88, 0.28 } },
	{ { 0.14, 0.7 }, { 0.64, 0.34 } },
	{ { 0.84, 0.56 }, { 0.36, 0.26 } },
}

-- A door window: the shaft wall (rock bands, cracks, crystal glints, a lamp) behind glass.
local function window(d: Frame): Window
	local win = frame(d, "Window", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.44, 0.5),
		BackgroundColor3 = BLACK,
		ClipsDescendants = true,
	})
	UIKit.corner(win, 18)
	local shaft = frame(win, "Shaft", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(20, 22, 34) })
	local bands: { Band } = {}
	local start = 0
	for i, height in BANDS do
		local band = frame(shaft, "Band", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, start),
			Size = UDim2.fromScale(1.04, height + 0.006),
			BackgroundColor3 = WHITE,
		})
		-- lit from above: the band darkens toward its foot
		UIKit.new("UIGradient", { Color = ColorSequence.new(WHITE, rgb(185, 185, 185)), Rotation = 90 }, band)
		-- the band's crack / trim line, glowing (lava, copper, gold, glow moss, pink)
		local spec = VEINS[i]
		local veinGlow = frame(band, "VeinGlow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.new(spec[3] + 0.04, 0, 0, 12),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72,
		})
		round(veinGlow, 0.5)
		local vein = frame(band, "Vein", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.new(spec[3], 0, 0, 4),
			BackgroundColor3 = WHITE,
		})
		round(vein, 0.5)
		local glints: { Frame } = {}
		local halos: { Frame } = {}
		for k, spot in GLINTS[i] do
			local size = if k == 1 then 17 else 12
			local halo = frame(band, "Halo", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spot[1], spot[2]),
				Size = UDim2.fromOffset(size * 2.4, size * 2.4),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.78,
			})
			round(halo, 0.5)
			table.insert(halos, halo)
			local glint = frame(band, "Glint", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spot[1], spot[2]),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = WHITE,
				Rotation = 45,
			})
			frame(glint, "Core", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.36, 0.36),
				BackgroundColor3 = WHITE,
			})
			table.insert(glints, glint)
		end
		table.insert(
			bands,
			{ Frame = band, Start = start, Height = height, Shade = i, Vein = vein, VeinGlow = veinGlow, Glints = glints, Halos = halos }
		)
		start += height
	end
	-- the lamp passing once per floor (its glow under it)
	local lampGlow = frame(win, "LampGlow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
	})
	local lamp = frame(win, "Lamp", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.035),
		BackgroundColor3 = WHITE,
	})
	-- depth: darker glass at the top and the bottom, then the glass's shine
	for _, y in { 0, 1 } do
		frame(win, "Depth", {
			AnchorPoint = Vector2.new(0.5, y),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromScale(1, 0.16),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.5,
		})
	end
	frame(win, "Shine", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.24, 0.5),
		Size = UDim2.fromScale(0.035, 1.2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.9,
	})
	UIKit.stroke(win, 4, NEON_BRIGHT)
	return { Frame = win, Shaft = shaft, Bands = bands, Lamp = lamp, LampGlow = lampGlow }
end

-- One full-screen door half; `left` = the left half. Returns the door, its window, its floor stripe and its rail runner.
local function door(root: Frame, left: boolean): (Frame, Window, Frame, Frame)
	local d = frame(root, if left then "DoorLeft" else "DoorRight", {
		AnchorPoint = Vector2.new(if left then 0 else 1, 0),
		Size = UDim2.new(0.5, 14, 1, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
	})
	gradient(d, { rgb(132, 146, 182), rgb(96, 108, 142), rgb(58, 66, 92) }, 90)
	local inner = if left then 1 else 0
	local outer = 1 - inner
	-- brushed steel: a lighter band near the seam
	frame(d, "Band", {
		AnchorPoint = Vector2.new(inner, 0),
		Position = UDim2.new(inner, if left then -20 else 20, 0, 0),
		Size = UDim2.new(0, 34, 1, 0),
		BackgroundColor3 = rgb(150, 164, 200),
		BackgroundTransparency = 0.6,
	})
	-- the darker inner frame with rows of rivets (the root reaches SHAKE_ROOM past the screen)
	local panel = frame(d, "Frame", {
		Position = UDim2.fromOffset(if left then 22 + SHAKE_ROOM else 22, 22 + SHAKE_ROOM),
		Size = UDim2.new(1, -(44 + SHAKE_ROOM), 1, -(44 + SHAKE_ROOM * 2)),
		BackgroundTransparency = 1,
	})
	UIKit.corner(panel, 16)
	UIKit.stroke(panel, 5, STEEL_FRAME)
	for _, row in { 0, 1 } do
		for k = 1, 8 do
			local rivet = frame(panel, "Rivet", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(k / 9, 0, row, if row == 0 then 16 else -16),
				Size = UDim2.fromOffset(12, 12),
				BackgroundColor3 = WHITE,
			})
			round(rivet, 0.5)
			gradient(rivet, { rgb(196, 206, 230), rgb(96, 106, 136) }, 90)
			UIKit.stroke(rivet, 1.5, INK, 0.35)
		end
	end
	local win = window(d)
	-- a call plate under the window: up on the left door, down on the right
	local plate = frame(d, "Plate", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.745),
		Size = UDim2.fromOffset(84, 46),
		BackgroundColor3 = rgb(12, 18, 44),
	})
	UIKit.corner(plate, 12)
	UIKit.stroke(plate, 3, NEON_BRIGHT)
	local mark = frame(plate, "Mark", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Rotation = if left then 0 else 180,
	})
	chevron(mark, 0.5, NEON_BRIGHT)
	-- a stripe in the target floor's colour along the seam (setRide)
	local stripe = frame(d, "FloorStripe", {
		AnchorPoint = Vector2.new(inner, 0.5),
		Position = UDim2.new(inner, if left then -34 else 34, 0.42, 0),
		Size = UDim2.new(0, 10, 0.42, 0),
		BackgroundColor3 = WHITE,
	})
	UIKit.corner(stripe, 6)
	UIKit.stroke(stripe, 2, INK)
	-- hazard stripe at the bottom
	local hazard = frame(d, "Hazard", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.9),
		Size = UDim2.new(0.84, 0, 0, 26),
		BackgroundColor3 = INK,
	})
	UIKit.corner(hazard, 6)
	for i = 0, 9 do
		if i % 2 == 0 then
			frame(hazard, "Stripe", {
				Position = UDim2.fromScale(i / 10, 0),
				Size = UDim2.fromScale(0.1, 1),
				BackgroundColor3 = HAZARD,
			})
		end
	end
	-- the outer rail (screen edge) with a running light
	local rail = frame(d, "Rail", {
		AnchorPoint = Vector2.new(outer, 0),
		Position = UDim2.new(outer, if left then SHAKE_ROOM else -SHAKE_ROOM, 0, 0),
		Size = UDim2.new(0, 16, 1, 0),
		BackgroundColor3 = rgb(16, 22, 48),
		ClipsDescendants = true,
	})
	local runner = frame(rail, "Runner", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 8, 0.18, 0),
		BackgroundColor3 = NEON_BRIGHT,
	})
	UIKit.corner(runner, 4)
	-- the thin neon edge on the seam
	frame(d, "EdgeGlow", {
		AnchorPoint = Vector2.new(inner, 0),
		Position = UDim2.fromScale(inner, 0),
		Size = UDim2.new(0, 16, 1, 0),
		BackgroundColor3 = NEON,
		BackgroundTransparency = 0.65,
	})
	frame(d, "Edge", {
		AnchorPoint = Vector2.new(inner, 0),
		Position = UDim2.fromScale(inner, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = NEON_BRIGHT,
	})
	return d, win, stripe, runner
end

function ElevatorRideView.build(): Refs
	local gui: ScreenGui = UIKit.new("ScreenGui", {
		Name = "TerraForgeElevatorRide",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 58,
		Enabled = false,
	})
	local root = frame(gui, "Root", {
		Position = UDim2.fromOffset(-SHAKE_ROOM, -SHAKE_ROOM),
		Size = UDim2.new(1, SHAKE_ROOM * 2, 1, SHAKE_ROOM * 2),
		BackgroundTransparency = 1,
	})
	local left, leftWindow, leftStripe, leftRunner = door(root, true)
	local right, rightWindow, rightStripe, rightRunner = door(root, false)
	local seam = frame(root, "Seam", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = NEON_BRIGHT,
		ZIndex = 3,
	})
	-- speed lines along both screen edges
	local lines: { Frame } = {}
	for side = 0, 1 do
		for _, spec in SPEED_LINES do
			local line = frame(root, "SpeedLine", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(side, if side == 0 then SHAKE_ROOM + spec[1] else -(SHAKE_ROOM + spec[1]), 0.5, 0),
				Size = UDim2.new(0, 3, spec[2], 0),
				BackgroundColor3 = NEON_BRIGHT,
				BackgroundTransparency = 0.45,
				ZIndex = 4,
				Visible = false,
			})
			round(line, 0.5)
			table.insert(lines, line)
		end
	end

	-- the floor indicator
	local size = ElevatorRideView.IndicatorSize
	local indicator = frame(root, "Indicator", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = WHITE,
		ZIndex = 5,
	})
	UIKit.corner(indicator, 24)
	gradient(indicator, { NAVY_TOP, rgb(18, 24, 54), NAVY_BOTTOM }, 90)
	UIKit.stroke(indicator, 4, NEON_BRIGHT)
	local indicatorScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, indicator)
	local glow = frame(indicator, "Glow", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	UIKit.corner(glow, 24)
	local glowStroke = UIKit.stroke(glow, 12, NEON, 0.6)
	local arrowBox = frame(indicator, "ArrowBox", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(82, 82),
		BackgroundColor3 = rgb(10, 14, 34),
	})
	UIKit.corner(arrowBox, 18)
	UIKit.stroke(arrowBox, 2, NEON, 0.3)
	local arrow = frame(arrowBox, "Arrow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		BackgroundTransparency = 1,
	})
	local chevrons: { Frame } = {}
	for i = 1, CHEVRONS do
		table.insert(chevrons, chevron(arrow, 0.25 * i, NEON_BRIGHT))
	end
	local floorLabel = UIKit.label(indicator, "FLOOR", 20, {
		Name = "FloorLabel",
		Position = UDim2.fromOffset(112, 12),
		Size = UDim2.fromOffset(150, 24),
		TextColor3 = TEXT_SOFT,
		TextWrapped = false,
	})
	local number = UIKit.label(indicator, "1", 80, {
		Name = "Number",
		Position = UDim2.fromOffset(112, 40),
		Size = UDim2.fromOffset(150, 84),
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local numberStroke = number:FindFirstChildOfClass("UIStroke")
	if numberStroke then
		numberStroke.Thickness = 4
		numberStroke.Color = INK
	end
	local dots: { Frame } = {}
	for i = 1, #MineFloors.List do
		local dot = frame(indicator, "Dot" .. i, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(size.X - 30, 22 + (i - 1) * (size.Y - 44) / math.max(1, #MineFloors.List - 1)),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = ElevatorView.floorColor(i),
		})
		round(dot, 0.5)
		UIKit.stroke(dot, 2, INK)
		table.insert(dots, dot)
	end

	-- the arrival banner
	local bannerSize = ElevatorRideView.BannerSize
	local banner = frame(root, "Banner", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(bannerSize.X, bannerSize.Y),
		BackgroundColor3 = WHITE,
		ZIndex = 6,
		Visible = false,
	})
	UIKit.corner(banner, 26)
	gradient(banner, { NAVY_TOP, rgb(18, 24, 54), NAVY_BOTTOM }, 90)
	local bannerStroke = UIKit.stroke(banner, 5, NEON_BRIGHT)
	local bannerScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, banner)
	local bannerText = UIKit.label(banner, "", 46, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		TextScaled = true,
		TextWrapped = false,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 48, MinTextSize = 18 }, bannerText)
	UIKit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 24),
		PaddingRight = UDim.new(0, 24),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 8),
	}, bannerText)
	local bannerTextStroke = bannerText:FindFirstChildOfClass("UIStroke")
	if bannerTextStroke then
		bannerTextStroke.Thickness = 3
		bannerTextStroke.Color = INK
	end

	local refs: Refs = {
		Gui = gui,
		Root = root,
		DoorLeft = left,
		DoorRight = right,
		Seam = seam,
		Windows = { leftWindow, rightWindow },
		FloorStripes = { leftStripe, rightStripe },
		Runners = { leftRunner, rightRunner },
		SpeedLines = lines,
		Indicator = indicator,
		IndicatorScale = indicatorScale,
		IndicatorGlow = glowStroke,
		Arrow = arrow,
		Chevrons = chevrons,
		Number = number,
		FloorLabel = floorLabel,
		Dots = dots,
		Banner = banner,
		BannerScale = bannerScale,
		BannerStroke = bannerStroke,
		BannerText = bannerText,
		UiScale = 1,
		TopInset = 36,
		TintKey = "",
	}
	return refs
end

-- The indicator and the banner follow the HUD scale; `topInset` = pixels kept free at the top (Roblox's bar).
function ElevatorRideView.layout(refs: Refs, uiScale: number, topInset: number)
	refs.UiScale = uiScale
	refs.TopInset = topInset
	refs.IndicatorScale.Scale = uiScale
	refs.BannerScale.Scale = uiScale
end

-- The banner text, the doors' floor stripes and colours for the ride's target floor.
function ElevatorRideView.setRide(refs: Refs, ride: Ride)
	local color = ElevatorView.floorColor(ride.To)
	refs.BannerText.Text = ElevatorRideView.bannerText(ride.To, ride.Name)
	refs.BannerText.TextColor3 = color:Lerp(WHITE, 0.15)
	refs.BannerStroke.Color = color
	for _, stripe in refs.FloorStripes do
		stripe.BackgroundColor3 = color
	end
	refs.TintKey = ""
end

-- Paints the windows for the cross-fade from floor `a`'s shaft to floor `b`'s (`k` = 0..1).
local function paintTint(refs: Refs, a: number, b: number, k: number)
	local ca = ElevatorRideView.shaftColors(a)
	local cb = ElevatorRideView.shaftColors(b)
	local function mix(x: Color3, y: Color3): Color3
		return x:Lerp(y, k)
	end
	for _, win in refs.Windows do
		win.Shaft.BackgroundColor3 = mix(ca.Back, cb.Back)
		for _, band in win.Bands do
			band.Frame.BackgroundColor3 = mix(ca.Bands[band.Shade], cb.Bands[band.Shade])
			local vein = mix(ca.Vein, cb.Vein)
			band.Vein.BackgroundColor3 = vein
			band.VeinGlow.BackgroundColor3 = vein
			for g, glint in band.Glints do
				local glow = if g == 1 then mix(ca.Glint, cb.Glint) else mix(ca.Glint2, cb.Glint2)
				glint.BackgroundColor3 = glow
				band.Halos[g].BackgroundColor3 = glow
			end
		end
		local lamp = mix(ca.Lamp, cb.Lamp)
		win.Lamp.BackgroundColor3 = lamp
		win.LampGlow.BackgroundColor3 = lamp
	end
end

---------------------------------------------------------------- the pose

--[[
	The overlay `t` seconds into `ride`: doors, shake, the shaft in the
	windows, speed lines, the indicator (slides in, ticks with a pulse, slides
	out), the banner. Positions of reused Frames every frame; colours only
	when the windows' tint changes.
]]
function ElevatorRideView.pose(refs: Refs, ride: Ride, t: number)
	local timing = ElevatorRideView.Timing
	local c = ElevatorRideView.closedness(ride, t)
	refs.DoorLeft.Visible = c > 0
	refs.DoorRight.Visible = c > 0
	refs.DoorLeft.Position = UDim2.fromScale(-0.56 * (1 - c), 0)
	refs.DoorRight.Position = UDim2.fromScale(1 + 0.56 * (1 - c), 0)
	local openAt = ride.OpenAt
	local riding = t >= ride.Close and (openAt == nil or t < openAt)
	local motion = not ride.Reduced
	local down = ElevatorRideView.direction(ride.From, ride.To) == "Down"
	refs.Seam.Visible = c >= 0.999
	refs.Seam.BackgroundTransparency = if motion then 0.15 + 0.3 * (0.5 + 0.5 * math.sin(t * 7)) else 0.2
	-- the windows: the shaft wall scrolls (going down it moves up), one lamp per floor
	local a, b, k = ElevatorRideView.tintAt(ride, t)
	local key = `{a}:{b}:{math.floor(k * 20 + 0.5)}`
	if key ~= refs.TintKey then
		refs.TintKey = key
		paintTint(refs, a, b, k)
	end
	local travel = if motion then ElevatorRideView.travel(ride, t) else 0
	local sign = if down then -1 else 1
	local spacing = ElevatorRideView.tickSpacing(ride)
	local ticks = ElevatorRideView.ticks(ride)
	local first = if ticks[1] then ticks[1].Time else ride.Close + spacing / 2
	local phase = ((t - first) / spacing + 0.5) % 1
	local lampY = if down then 1.15 - 1.3 * phase else -0.15 + 1.3 * phase
	for _, win in refs.Windows do
		for _, band in win.Bands do
			local y = ((band.Start + sign * travel) % BAND_CYCLE) - (BAND_CYCLE - 1)
			band.Frame.Position = UDim2.fromScale(0.5, y)
		end
		win.Lamp.Position = UDim2.fromScale(0.5, lampY)
		win.LampGlow.Position = UDim2.fromScale(0.5, lampY)
		win.Lamp.Visible = riding and motion
		win.LampGlow.Visible = riding and motion
	end
	for _, runner in refs.Runners do
		local p = (t * 1.4) % 1
		local y = if down then 1 - p else p
		runner.Position = UDim2.fromScale(0.5, -0.1 + 1.2 * y)
		runner.Visible = riding and motion
	end
	-- speed lines streak along the screen edges in the ride direction
	for i, line in refs.SpeedLines do
		local spec = SPEED_LINES[(i - 1) % #SPEED_LINES + 1]
		local p = (spec[3] + t * 2.6) % 1
		local y = if down then 1.1 - 1.2 * p else -0.1 + 1.2 * p
		local x = line.Position.X
		line.Position = UDim2.new(x.Scale, x.Offset, y, 0)
		line.Visible = riding and motion
	end
	-- shake: a thud when the doors meet, a gentle rumble while riding
	local dx, dy = 0, 0
	if motion then
		local since = t - ride.Close
		local amp = 0
		if since >= 0 and since < timing.Thud then
			amp = 9 * (1 - since / timing.Thud)
		elseif riding then
			amp = 1.6
		end
		dx = math.sin(t * 61) * amp
		dy = math.cos(t * 47) * amp * 0.8
	end
	refs.Root.Position = UDim2.fromOffset(-SHAKE_ROOM + dx, -SHAKE_ROOM + dy)
	-- the indicator slides down from the top, and back up once the doors open
	local s = refs.UiScale
	local size = ElevatorRideView.IndicatorSize
	local inK = easeOut(clamp01((t - 0.05) / timing.IndicatorIn))
	local outK = if openAt then easeIn(clamp01((t - openAt) / timing.IndicatorOut)) else 0
	local slide = inK * (1 - outK)
	local restY = SHAKE_ROOM + refs.TopInset + 14 * s + size.Y * s / 2
	refs.Indicator.Visible = slide > 0
	refs.Indicator.Position = UDim2.new(0.5, 0, 0, restY - (1 - slide) * (restY + size.Y * s))
	local number = ElevatorRideView.numberAt(ride, t)
	local color = ElevatorView.floorColor(number)
	refs.Number.Text = tostring(number)
	refs.Number.TextColor3 = color
	-- every tick: a glow pulse in the floor's colour and a little pop
	local pulse = if motion then ElevatorRideView.pulseAt(ride, t) else 0
	refs.IndicatorScale.Scale = s * (1 + 0.1 * pulse)
	refs.IndicatorGlow.Transparency = 0.6 - 0.5 * pulse
	refs.IndicatorGlow.Color = NEON:Lerp(color, pulse)
	-- the chevrons flow toward the arrow's tip (the arrow turns for "Down")
	refs.Arrow.Rotation = if down then 180 else 0
	local flowing = motion and riding
	for i, chev in refs.Chevrons do
		local p = if flowing then (t * 1.6 + (i - 1) / CHEVRONS) % 1 else 1 - i / (CHEVRONS + 1)
		chev.Position = UDim2.fromScale(0.5, 0.88 - 0.76 * p)
		local light = if flowing then math.sin(p * math.pi) else 1
		for _, bar in chev:GetChildren() do
			if bar:IsA("Frame") then
				bar.BackgroundTransparency = 0.9 * (1 - light)
			end
		end
	end
	-- the dots of the floors passed so far light up in their colours
	for i, dot in refs.Dots do
		local current = i == number
		local passed = (i - ride.From) * (number - i) >= 0
		dot.Size = if current then UDim2.fromOffset(18, 18) elseif passed then UDim2.fromOffset(12, 12) else UDim2.fromOffset(9, 9)
		dot.BackgroundTransparency = if passed then 0 else 0.7
	end
	-- the banner slides in from the left after the ding, holds, slides out to the right
	local x: number? = nil
	if openAt then
		local bt = t - (openAt + timing.BannerDelay)
		if bt >= 0 and bt < timing.BannerIn then
			x = -0.6 + 1.1 * backOut(bt / timing.BannerIn)
		elseif bt >= timing.BannerIn and bt < timing.BannerIn + timing.BannerHold then
			x = 0.5
		elseif bt >= timing.BannerIn + timing.BannerHold and bt < timing.BannerIn + timing.BannerHold + timing.BannerOut then
			x = 0.5 + 1.1 * easeIn((bt - timing.BannerIn - timing.BannerHold) / timing.BannerOut)
		end
	end
	refs.Banner.Visible = x ~= nil
	if x then
		refs.Banner.Position = UDim2.fromScale(x, 0.5)
	end
end

return ElevatorRideView
