--[[
	The words and the frame of the elevator's travel cinematic on screen
	(owner 2026-11-15; timeline in Config/ElevatorTravelConfig). Pure builder +
	pose: ElevatorTravelController poses it every frame of a ride, the Lune
	previews pose it too.

	  PREPARING ELEVATOR...  an amber pill at the bottom while the stop gets
	                         ready (the floor window is still open above it);
	                         its dots run
	  dip                    a short dip to black as the camera steps into the
	                         cabin (and where the camera cuts instead of gliding:
	                         Reduce motion's way out, a floor with no stop)
	  bars                   cinema bars slide in at the top and the bottom for
	                         the ride and out at the end; the bottom one names
	                         the way: "DOWN TO FLOOR 4 · SUNKEN PALACE"
	  ARRIVED!               pops in at the stop with the mine's name in its
	                         colour and its floor under it, then fades
	Reduce motion: fades instead of pops and slides, the dots stand still.

	Text sizes are for the 720-unit design height; Scale (a UIScale on the
	gui's root) follows HudController.uiScale on phones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ElevatorTravelConfig = require(Shared.Config.ElevatorTravelConfig)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)

local View = {}

type Plan = ElevatorTravelConfig.Plan

export type Refs = {
	Gui: ScreenGui,
	Dip: Frame,
	TopBar: Frame,
	BottomBar: Frame,
	Way: TextLabel, -- in the bottom bar
	Scaled: Frame, -- holds what follows the HUD scale
	Scale: UIScale,
	Prepare: Frame,
	PrepareScale: UIScale,
	PrepareText: TextLabel,
	Arrived: Frame,
	ArrivedScale: UIScale,
	Word: TextLabel,
	Name: TextLabel,
	Floor: TextLabel,
	Abort: number?, -- the plan time a ride was cut short (a dip back from black)
}

export type Info = {
	Name: string, -- the target mine
	Floor: number,
	Glow: Color3, -- the mine's colour
	Down: boolean,
	Reduced: boolean,
	CutAt: number?, -- a dip here too (Reduce motion's way out, a floor with no stop)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local INK = rgb(16, 18, 30)
local AMBER_TOP = rgb(255, 214, 92)
local AMBER_LOW = rgb(255, 150, 36)

View.BarHeight = 0.085 -- of the screen's height, each bar

local function frame(parent: Instance, name: string, props: { [string]: any }): Frame
	local f: Frame = UIKit.new("Frame", { Name = name, BorderSizePixel = 0 }, parent)
	local target: any = f
	for key, value in props do
		target[key] = value
	end
	return f
end

local function edge(label: TextLabel, thickness: number, color: Color3)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = thickness
		stroke.Color = color
	end
end

function View.build(): Refs
	local gui: ScreenGui = UIKit.new("ScreenGui", {
		Name = "TerraForgeElevatorTravel",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 72, -- over the floor window (60) and the HUD
		Enabled = false,
	})
	local top = frame(gui, "TopBar", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, View.BarHeight),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 2,
	})
	local bottom = frame(gui, "BottomBar", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, View.BarHeight),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 2,
	})
	local way = UIKit.label(bottom, "", 22, {
		Name = "Way",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.7),
		TextScaled = true,
		TextWrapped = false,
		ZIndex = 3,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 12 }, way)
	local scaled = frame(gui, "Scaled", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	local scale: UIScale = UIKit.new("UIScale", { Name = "Scale", Scale = 1 }, scaled)
	-- PREPARING ELEVATOR... (an amber pill with a dark edge, the Pop look)
	local prepare = frame(scaled, "Prepare", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(430, 64),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 5,
	})
	UIKit.corner(prepare, 32)
	UIKit.new("UIGradient", { Color = ColorSequence.new(AMBER_TOP, AMBER_LOW), Rotation = 90 }, prepare)
	UIKit.stroke(prepare, 4, INK)
	local prepareScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, prepare)
	local prepareText = UIKit.label(prepare, "PREPARING ELEVATOR...", 30, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.TitleFont,
		TextColor3 = WHITE,
		TextWrapped = false,
		ZIndex = 6,
	})
	edge(prepareText, 3, INK)
	-- ARRIVED! with the mine's name and floor
	local arrived = frame(scaled, "Arrived", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(760, 190),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	})
	local arrivedScale: UIScale = UIKit.new("UIScale", { Scale = 1 }, arrived)
	local word = UIKit.label(arrived, "ARRIVED!", 78, {
		Name = "Word",
		Size = UDim2.new(1, 0, 0, 92),
		FontFace = Theme.TitleFont,
		TextColor3 = WHITE,
		TextWrapped = false,
		ZIndex = 6,
	})
	edge(word, 5, INK)
	local name = UIKit.label(arrived, "", 44, {
		Name = "MineName",
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, 56),
		FontFace = Theme.TitleFont,
		TextWrapped = false,
		ZIndex = 6,
	})
	edge(name, 4, INK)
	local floor = UIKit.label(arrived, "", 26, {
		Name = "Floor",
		Position = UDim2.fromOffset(0, 148),
		Size = UDim2.new(1, 0, 0, 34),
		TextColor3 = rgb(226, 232, 248),
		TextWrapped = false,
		ZIndex = 6,
	})
	edge(floor, 3, INK)
	local dip = frame(gui, "Dip", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
	})
	return {
		Gui = gui,
		Dip = dip,
		TopBar = top,
		BottomBar = bottom,
		Way = way,
		Scaled = scaled,
		Scale = scale,
		Prepare = prepare,
		PrepareScale = prepareScale,
		PrepareText = prepareText,
		Arrived = arrived,
		ArrivedScale = arrivedScale,
		Word = word,
		Name = name,
		Floor = floor,
		Abort = nil,
	}
end

-- The pill and the words follow the HUD scale (phones); `bottomInset` keeps the pill off the home bar.
function View.layout(refs: Refs, uiScale: number, bottomInset: number)
	refs.Scale.Scale = uiScale
	refs.Prepare.Position = UDim2.new(0.5, 0, 1, -(28 + bottomInset / math.max(uiScale, 0.1)))
end

-- "DOWN TO FLOOR 4 · SUNKEN PALACE"
function View.wayText(info: Info): string
	return `{if info.Down then "DOWN" else "UP"} TO FLOOR {info.Floor} · {string.upper(info.Name)}`
end

-- "PREPARING ELEVATOR..." with its dots running (standing still with reduced motion).
function View.prepareText(t: number, reduced: boolean): string
	local dots = if reduced then 3 else math.floor(t * 6) % 4
	return "PREPARING ELEVATOR" .. string.rep(".", dots)
end

-- Sets the words of a ride (the target mine).
function View.setRide(refs: Refs, info: Info)
	refs.Abort = nil
	refs.Way.Text = View.wayText(info)
	refs.Way.TextColor3 = info.Glow:Lerp(WHITE, 0.55)
	refs.Name.Text = string.upper(info.Name)
	refs.Name.TextColor3 = info.Glow:Lerp(WHITE, 0.15)
	refs.Floor.Text = `FLOOR {info.Floor}`
	local stroke = refs.Word:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = info.Glow:Lerp(INK, 0.55)
	end
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function easeOut(x: number): number
	local u = clamp01(x)
	return 1 - (1 - u) * (1 - u)
end

local function backOut(x: number): number
	local u = clamp01(x)
	local c1 = 1.70158
	local y = u - 1
	return 1 + (c1 + 1) * y * y * y + c1 * y * y
end

-- How black the screen is at `t` (0..1): the dip into the cabin, a cut's dip, a cut short ride's way back.
function View.dipAt(plan: Plan, t: number, info: Info, abort: number?): number
	local timing = ElevatorTravelConfig.Timing
	local function dip(at: number): number
		if t < at then
			return 0
		end
		if t < at + timing.DipOut then
			return (t - at) / timing.DipOut
		end
		return 1 - clamp01((t - at - timing.DipOut) / timing.DipIn)
	end
	local level = dip(plan.Enter)
	local cutAt = info.CutAt
	if cutAt then
		level = math.max(level, dip(cutAt))
	end
	if abort then
		-- (the game came back at once behind black; it clears over a short fade)
		level = math.max(level, 1 - clamp01((t - abort) / 0.35))
	end
	return level
end

-- How far the cinema bars are in (0..1).
function View.barsAt(plan: Plan, t: number): number
	if t < plan.Enter then
		return 0
	end
	local into = easeOut((t - plan.Enter) / 0.35)
	local out = clamp01((t - plan.ExitAt) / 0.45)
	return into * (1 - easeOut(out))
end

local function fadeText(label: TextLabel, transparency: number)
	label.TextTransparency = transparency
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = transparency
	end
end

--[[
	The overlay `t` seconds into a ride: the pill, the dip, the bars and the
	way, ARRIVED! with the mine's name.
]]
function View.pose(refs: Refs, plan: Plan, t: number, info: Info)
	local reduced = info.Reduced
	-- PREPARING ELEVATOR... while the stop gets ready (it goes with the dip)
	local prepareShown = t >= 0 and t < plan.Enter + ElevatorTravelConfig.Timing.DipOut
	refs.Prepare.Visible = prepareShown
	if prepareShown then
		refs.PrepareText.Text = View.prepareText(t, reduced)
		refs.PrepareScale.Scale = if reduced then 1 else 0.85 + 0.15 * backOut(t / 0.22)
		local out = clamp01((t - plan.Enter) / ElevatorTravelConfig.Timing.DipOut)
		refs.Prepare.BackgroundTransparency = out
		fadeText(refs.PrepareText, out)
		local stroke = refs.Prepare:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = out
		end
	end
	-- the dip to black
	local dip = View.dipAt(plan, t, info, refs.Abort)
	refs.Dip.Visible = dip > 0.001
	refs.Dip.BackgroundTransparency = 1 - dip
	-- the cinema bars (a fade instead of the slide with reduced motion)
	local bars = View.barsAt(plan, t)
	if reduced then
		refs.TopBar.Position = UDim2.fromScale(0.5, View.BarHeight)
		refs.BottomBar.Position = UDim2.fromScale(0.5, 1 - View.BarHeight)
		refs.TopBar.BackgroundTransparency = 1 - bars
		refs.BottomBar.BackgroundTransparency = 1 - bars
	else
		refs.TopBar.Position = UDim2.fromScale(0.5, View.BarHeight * bars)
		refs.BottomBar.Position = UDim2.fromScale(0.5, 1 - View.BarHeight * bars)
		refs.TopBar.BackgroundTransparency = 0
		refs.BottomBar.BackgroundTransparency = 0
	end
	refs.TopBar.Visible = bars > 0.001
	refs.BottomBar.Visible = bars > 0.001
	-- the way in the bottom bar during the ride
	local wayIn = clamp01((t - plan.DoorsShut) / 0.3) * (1 - clamp01((t - plan.StopAt) / 0.25))
	refs.Way.Visible = wayIn > 0.001
	fadeText(refs.Way, 1 - wayIn)
	-- ARRIVED! pops in at the stop, holds, fades by the end
	local since = t - plan.StopAt
	local shown = since >= 0 and t < plan.EndAt
	refs.Arrived.Visible = shown
	if shown then
		local out = clamp01((t - (plan.EndAt - 0.3)) / 0.3)
		if reduced then
			refs.ArrivedScale.Scale = 1
			local fade = math.max(1 - clamp01(since / 0.3), out)
			fadeText(refs.Word, fade)
			fadeText(refs.Name, fade)
			fadeText(refs.Floor, fade)
		else
			refs.ArrivedScale.Scale = 0.55 + 0.45 * backOut(since / 0.32)
			local nameIn = 1 - clamp01((since - 0.12) / 0.2)
			fadeText(refs.Word, out)
			fadeText(refs.Name, math.max(nameIn, out))
			fadeText(refs.Floor, math.max(nameIn, out))
		end
	end
end

return View
