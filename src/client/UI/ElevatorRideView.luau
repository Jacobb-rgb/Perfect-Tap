--[[
	The elevator ride on screen (owner 2026-10-18: "make some animation during
	that transfer"). Pure builder + pure timing; ElevatorController drives it
	(ElevatorRideView.pose every frame of the ride, a few property writes).

	  doors      two full-screen steel door halves in the panel's style (navy
	             glass windows in a neon frame, hazard stripe, glowing inner
	             edges) slam shut with a thud and a short shake
	  indicator  a panel at the top centre: an arrow (down = deeper, up = back
	             up), "FLOOR" and the big floor number in the floor's card
	             colour, and a column of five floor dots; the number ticks one
	             floor at a time from the floor you left to the target
	  ride       light strips sweep through the door windows and along the
	             screen-edge rails in the ride direction (lights pass upward
	             when going down), a gentle rumble shake
	  arrival    once the server says "Arrive" and the ride lasted at least
	             its Duration: ding, the doors slide open on the new floor and
	             a banner "FLOOR 4 · SUNKEN PALACE" in the floor colour slides
	             in and out

	Timeline (seconds from "Depart"): the doors shut by Close; ticks between
	Close + TickLead and MinRide - TickLead; the doors start opening at
	OpenAt (>= MinRide, after "Arrive"; FailSafe seconds later without it);
	the banner follows. Reduced motion: the doors and the numbers only (no
	shake, sweeps or bobbing arrow).

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

export type Refs = {
	Gui: ScreenGui,
	Root: Frame, -- moves for the shake
	DoorLeft: Frame,
	DoorRight: Frame,
	Seam: Frame,
	Strips: { Frame }, -- light strips in the door windows
	Runners: { Frame }, -- bright segments on the screen-edge rails
	Indicator: Frame,
	IndicatorScale: UIScale,
	Arrow: Frame,
	Number: TextLabel,
	FloorLabel: TextLabel,
	Dots: { Frame },
	Banner: Frame,
	BannerScale: UIScale,
	BannerStroke: UIStroke,
	BannerText: TextLabel,
	UiScale: number,
	TopInset: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local INK = rgb(10, 12, 26)
local NEON = rgb(70, 170, 255)
local NEON_BRIGHT = rgb(120, 210, 255)
local NAVY_TOP = rgb(26, 34, 72)
local NAVY_BOTTOM = rgb(12, 16, 38)
local TEXT_SOFT = rgb(196, 208, 236)
local HAZARD = rgb(255, 196, 52)

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
}

ElevatorRideView.IndicatorSize = Vector2.new(320, 132)
ElevatorRideView.BannerSize = Vector2.new(760, 100)
local STRIPS = 3 -- per window
local SHAKE_ROOM = 16 -- the root is this much bigger on each side, so a shake never shows an edge

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

-- "^" of two bars (the indicator's arrow is two of them, turned for "Down").
local function chevron(parent: Instance, cy: number, color: Color3)
	local box = frame(parent, "Chevron", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, cy),
		Size = UDim2.fromScale(0.8, 0.4),
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
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.2, 0) }, bar)
	end
end

-- One full-screen door half; `left` = the left half. Returns the door, its window strips and its rail runner.
local function door(root: Frame, left: boolean): (Frame, { Frame }, Frame)
	local d = frame(root, if left then "DoorLeft" else "DoorRight", {
		AnchorPoint = Vector2.new(if left then 0 else 1, 0),
		Size = UDim2.new(0.5, 14, 1, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
	})
	gradient(d, { rgb(118, 132, 168), rgb(84, 96, 128), rgb(50, 58, 82) }, 90)
	local inner = if left then 1 else 0
	local outer = 1 - inner
	-- panel lines and a lighter band near the seam
	for _, y in { 0.12, 0.8 } do
		frame(d, "Groove", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.new(0.84, 0, 0, 4),
			BackgroundColor3 = rgb(32, 38, 56),
		})
	end
	local band = frame(d, "Band", {
		AnchorPoint = Vector2.new(inner, 0),
		Position = UDim2.new(inner, if left then -20 else 20, 0, 0),
		Size = UDim2.new(0, 34, 1, 0),
		BackgroundColor3 = rgb(140, 154, 190),
		BackgroundTransparency = 0.55,
	})
	band.ZIndex = 2
	-- the window: navy glass in a neon frame; light strips sweep through it
	local window = frame(d, "Window", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.44, 0.48),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
	})
	UIKit.corner(window, 18)
	gradient(window, { rgb(22, 34, 78), rgb(12, 18, 46), rgb(8, 12, 30) }, 90)
	UIKit.stroke(window, 4, NEON_BRIGHT)
	local strips: { Frame } = {}
	for i = 1, STRIPS do
		local strip = frame(window, "Strip", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, i / (STRIPS + 1)),
			Size = UDim2.fromScale(1.1, 0.07),
			BackgroundColor3 = rgb(130, 215, 255),
			BackgroundTransparency = 0.2,
		})
		frame(strip, "Core", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 0.35),
			BackgroundColor3 = WHITE,
		})
		table.insert(strips, strip)
	end
	-- the glass's shine
	local shine = frame(window, "Shine", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.3, 0.5),
		Size = UDim2.fromScale(0.08, 1.2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.85,
	})
	shine.ZIndex = 2
	-- a call plate under the window: up on the left door, down on the right
	local plate = frame(d, "Plate", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.75),
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
	-- hazard stripe at the bottom
	local hazard = frame(d, "Hazard", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.91),
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
	-- the glowing inner edge (where the halves meet)
	frame(d, "Edge", {
		AnchorPoint = Vector2.new(inner, 0),
		Position = UDim2.fromScale(inner, 0),
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = NEON_BRIGHT,
	})
	frame(d, "EdgeGlow", {
		AnchorPoint = Vector2.new(inner, 0),
		Position = UDim2.fromScale(inner, 0),
		Size = UDim2.new(0, 20, 1, 0),
		BackgroundColor3 = NEON,
		BackgroundTransparency = 0.6,
	})
	return d, strips, runner
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
	local left, leftStrips, leftRunner = door(root, true)
	local right, rightStrips, rightRunner = door(root, false)
	local strips: { Frame } = {}
	for _, list in { leftStrips, rightStrips } do
		for _, strip in list do
			table.insert(strips, strip)
		end
	end
	local seam = frame(root, "Seam", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 12, 1, 0),
		BackgroundColor3 = NEON_BRIGHT,
		ZIndex = 3,
	})

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
	UIKit.stroke(glow, 10, NEON, 0.6)
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
	chevron(arrow, 0.32, NEON_BRIGHT)
	chevron(arrow, 0.68, NEON_BRIGHT)
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
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
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
		Strips = strips,
		Runners = { leftRunner, rightRunner },
		Indicator = indicator,
		IndicatorScale = indicatorScale,
		Arrow = arrow,
		Number = number,
		FloorLabel = floorLabel,
		Dots = dots,
		Banner = banner,
		BannerScale = bannerScale,
		BannerStroke = bannerStroke,
		BannerText = bannerText,
		UiScale = 1,
		TopInset = 36,
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

-- The banner text and colours for the ride's target floor.
function ElevatorRideView.setRide(refs: Refs, ride: Ride)
	local color = ElevatorView.floorColor(ride.To)
	refs.BannerText.Text = ElevatorRideView.bannerText(ride.To, ride.Name)
	refs.BannerText.TextColor3 = color:Lerp(WHITE, 0.15)
	refs.BannerStroke.Color = color
end

---------------------------------------------------------------- the pose

--[[
	The overlay `t` seconds into `ride`: door positions, shake, light sweeps,
	the indicator (slides in, ticks, slides out), the banner. Cheap: a few
	dozen property writes.
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
	refs.Seam.Visible = c >= 0.999
	refs.Seam.BackgroundTransparency = if motion then 0.15 + 0.3 * (0.5 + 0.5 * math.sin(t * 7)) else 0.2
	-- light strips: going down the lights pass upward, going up they pass downward
	local down = ElevatorRideView.direction(ride.From, ride.To) == "Down"
	for i, strip in refs.Strips do
		local k = (i - 1) % STRIPS
		local p = (t * 0.9 + k / STRIPS) % 1
		local y = if down then 1 - p else p
		strip.Position = UDim2.fromScale(0.5, -0.1 + 1.2 * y)
		strip.Visible = riding and motion
	end
	for _, runner in refs.Runners do
		local p = (t * 1.4) % 1
		local y = if down then 1 - p else p
		runner.Position = UDim2.fromScale(0.5, -0.1 + 1.2 * y)
		runner.Visible = riding and motion
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
	local k = inK * (1 - outK)
	local restY = SHAKE_ROOM + refs.TopInset + 14 * s + size.Y * s / 2
	refs.Indicator.Visible = k > 0
	refs.Indicator.Position = UDim2.new(0.5, 0, 0, restY - (1 - k) * (restY + size.Y * s))
	local number = ElevatorRideView.numberAt(ride, t)
	local color = ElevatorView.floorColor(number)
	refs.Number.Text = tostring(number)
	refs.Number.TextColor3 = color
	refs.Arrow.Rotation = if down then 180 else 0
	local bob = if motion and riding then math.sin(t * 9) * 4 else 0
	refs.Arrow.Position = UDim2.new(0.5, 0, 0.5, if down then bob else -bob)
	for i, dot in refs.Dots do
		local current = i == number
		dot.Size = if current then UDim2.fromOffset(18, 18) else UDim2.fromOffset(10, 10)
		dot.BackgroundTransparency = if current then 0 else 0.55
	end
	-- the banner slides in from the left after the ding, holds, slides out to the right
	local x: number? = nil
	if openAt then
		local b = t - (openAt + timing.BannerDelay)
		if b >= 0 and b < timing.BannerIn then
			x = -0.6 + 1.1 * backOut(b / timing.BannerIn)
		elseif b >= timing.BannerIn and b < timing.BannerIn + timing.BannerHold then
			x = 0.5
		elseif b >= timing.BannerIn + timing.BannerHold and b < timing.BannerIn + timing.BannerHold + timing.BannerOut then
			x = 0.5 + 1.1 * easeIn((b - timing.BannerIn - timing.BannerHold) / timing.BannerOut)
		end
	end
	refs.Banner.Visible = x ~= nil
	if x then
		refs.Banner.Position = UDim2.fromScale(x, 0.5)
	end
end

return ElevatorRideView
