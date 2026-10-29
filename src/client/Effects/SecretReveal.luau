--[[
	SecretReveal: the jackpot screen when a SECRET ore drops (owner
	2026-10-29: "u nich musime udelat nejake cool animace ... inspiruj se
	pet simulatorem"). Pure builder + pose (SecretRevealController plays it,
	the Lune preview tools/lune/export_secret_reveal.luau poses the same
	frames); nothing runs on its own.

	The sequence (seconds, SecretReveal.* below):
	  0     the screen darkens (Dim)
	  0.35  a black silhouette of the ore turns in the middle, three heartbeats
	        (Thumps), each one bigger, a ring flies off every beat
	  Burst a gold-white flash (one: within the shared 2.5 a second cap), the
	        ore shows itself big and spinning, two layers of rays turn behind
	        it (near-black and rainbow, like RevealFx's "Secret" tier),
	        confetti, "SECRET!" pops over it, its name, a SECRET pill and the
	        chance ("1 in 4,000") slide up under it, NEW! on a first find
	  Hold  it flies into the backpack button (Fly), everything else fades
	A tap skips to the flight from SkipAfter (the controller moves t on).

	  build()                     -> View (Gui = ScreenGui "TerraForgeSecret",
	                                 DisplayOrder 46, hidden)
	  setOre(view, oreId, info)   info = { Chance = "1 in 4,000", New = true }
	  pose(view, t, opts)         -> done; opts = { Screen = Vector2 (px),
	                                 Scale = the HUD's UI scale, Target =
	                                 the bag's middle (px, nil = fade in place),
	                                 Reduced = Motion.reduced(), Phone = true
	                                 for fewer rays and confetti }

	Until Animace's RevealFx (Effects/RevealFx, the egg hatch family) is on
	main the rays, flash and banner are drawn here with its "Secret" values:
	20 rays (10 bars) alternating (14,10,22) and rainbow hues drifting 0.25
	turn/s, two layers (+45 / -30 degrees a second), flash (255,240,200) at
	most 0.9 opaque fading in 0.45 s; Montserrat: headline 64 Heavy white with
	a 5-unit rainbow edge, name 46 Heavy with a 4-unit edge, a 34 tall round
	pill, the chance 22 Bold.
	Reduce motion: no flash, beats, confetti or spin; the rays stand still,
	words fade in at full size and the ore fades out where it is.
	Perf: everything is built once (build); a secret ore's model once per ore
	(setOre keeps them: there are 6). A pose sets transforms and colours only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local OreData = require(Config:WaitForChild("OreData"))
local PopTheme = require(Config:WaitForChild("PopTheme"))
local SecretOreConfig = require(Config:WaitForChild("SecretOreConfig"))
local ItemBuilder = require(Shared:WaitForChild("Builders"):WaitForChild("ItemBuilder"))
local SecretOreShapes = require(Shared:WaitForChild("Builders"):WaitForChild("SecretOreShapes"))
local UIKit = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIKit"))

local SecretReveal = {}

SecretReveal.Dim = 0.35 -- seconds: the screen darkens
SecretReveal.Thumps = { 0.62, 1.02, 1.38 } -- the hidden ore's heartbeats
SecretReveal.Burst = 1.62 -- the flash: the secret shows itself
SecretReveal.Hold = 4.7 -- from here it flies into the bag
SecretReveal.Fly = 0.7
SecretReveal.Total = SecretReveal.Hold + SecretReveal.Fly + 0.1
SecretReveal.SkipAfter = SecretReveal.Burst + 0.45 -- a tap skips to the flight from here
SecretReveal.Center = UDim2.fromScale(0.5, 0.42) -- the middle of it all (RevealFx's Center)
SecretReveal.DimTo = 0.28 -- the dark overlay's transparency at its darkest
SecretReveal.OreSize = 300 -- design units: the 3D ore's viewport
SecretReveal.RayLength = 820 -- design units, end to end through the middle
SecretReveal.Bars = { Front = 10, Back = 8, Phone = 6 } -- a bar is two rays
SecretReveal.Confetti = { Full = 28, Phone = 16 }
SecretReveal.Fov = 30
SecretReveal.FlashColor = Color3.fromRGB(255, 240, 200)
SecretReveal.Dark = Color3.fromRGB(14, 10, 22)

export type Info = { Chance: string?, New: boolean? }

export type Opts = {
	Screen: Vector2,
	Scale: number,
	Target: Vector2?,
	Reduced: boolean?,
	Phone: boolean?,
}

type Piece = { Frame: Frame, Dir: Vector2, Speed: number, Spin: number, Delay: number }

export type View = {
	Gui: ScreenGui,
	Dim: Frame,
	Flash: Frame,
	Stage: Frame,
	Scale: UIScale,
	Front: { Frame },
	Back: { Frame },
	Glow: Frame,
	Halo: Frame,
	Rings: { Frame },
	OreHolder: Frame,
	OreScale: UIScale,
	View: ViewportFrame,
	Camera: Camera,
	Models: { [string]: Model },
	Shadows: { [string]: Model },
	Radius: { [Model]: number },
	OreId: string?,
	New: boolean,
	Headline: Frame,
	HeadScale: UIScale,
	HeadLabel: TextLabel,
	HeadEdge: UIGradient,
	Info: Frame,
	Name: TextLabel,
	Pill: Frame,
	Chance: TextLabel,
	NewTag: Frame,
	NewScale: UIScale,
	Hint: TextLabel,
	Confetti: { Piece },
}

local WHITE = Color3.new(1, 1, 1)
local VIEW_FROM = Vector3.new(-0.5, 0.32, -1).Unit
local LIGHT = Vector3.new(-0.16, -0.74, 0.65).Unit
local CORNERS = {
	Vector3.new(1, 1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, -1, -1),
}

local function span(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function easeOut(x: number): number
	return 1 - (1 - x) ^ 3
end

local function easeInOut(x: number): number
	return if x < 0.5 then 4 * x * x * x else 1 - (-2 * x + 2) ^ 3 / 2
end

local function easeOutBack(x: number): number
	local c1, c3 = 2.0, 3.0
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function round(frame: Frame)
	UIKit.corner(frame, 999)
end

-- Fades every word, edge and filled box under `root` (alpha 0 = shown, 1 = gone).
local function fade(root: Instance, alpha: number)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextTransparency = alpha
		elseif d:IsA("UIStroke") then
			d.Transparency = alpha
		elseif d:IsA("Frame") then
			d.BackgroundTransparency = alpha
		end
	end
end

local function rainbowSequence(shift: number): ColorSequence
	local colors = SecretOreShapes.Rainbow
	local keys = {}
	for k = 0, #colors do
		local color = colors[(k + math.floor(shift)) % #colors + 1]
		table.insert(keys, ColorSequenceKeypoint.new(k / #colors, color))
	end
	return ColorSequence.new(keys)
end

-- A rainbow hue at turn `x` (0..1), bright enough to read on black.
local function hue(x: number): Color3
	return Color3.fromHSV(x % 1, 0.72, 1)
end

--[[
	A built item made still for a viewport: only its visible parts (no welds,
	sparkles or lights), anchored, its middle at the origin. Returns how far
	its farthest corner reaches from the middle.
]]
local function still(model: Model): number
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Parent = model
			table.insert(parts, d)
		end
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			for _, extra in d:GetChildren() do
				extra:Destroy()
			end
		else
			d:Destroy()
		end
	end
	local kept: { BasePart } = {}
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in parts do
		if part.Transparency >= 0.99 then
			part:Destroy()
			continue
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		table.insert(kept, part)
		local half = part.Size / 2
		for _, corner in CORNERS do
			local at = part.CFrame * (corner * half)
			lo = Vector3.new(math.min(lo.X, at.X), math.min(lo.Y, at.Y), math.min(lo.Z, at.Z))
			hi = Vector3.new(math.max(hi.X, at.X), math.max(hi.Y, at.Y), math.max(hi.Z, at.Z))
		end
	end
	if #kept == 0 then
		return 1
	end
	local middle = CFrame.new(-(lo + hi) / 2)
	local reach = 0.5
	for _, part in kept do
		part.CFrame = middle * part.CFrame
		local half = part.Size / 2
		for _, corner in CORNERS do
			reach = math.max(reach, (part.CFrame * (corner * half)).Magnitude)
		end
	end
	return reach
end

-- The same model all black: the "???" the player sees before the flash.
local function shadowOf(model: Model): Model
	local shadow = model:Clone()
	for _, d in shadow:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = SecretReveal.Dark
			d.Material = Enum.Material.SmoothPlastic
			d.Reflectance = 0
			d.Transparency = 0
		end
	end
	shadow.Name = model.Name .. "_Shadow"
	return shadow
end

local function bar(parent: Instance, name: string, width: number, z: number): Frame
	local frame = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, SecretReveal.RayLength),
		ZIndex = z,
	}, parent)
	-- bright near the middle, gone at both ends
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, frame)
	return frame
end

local function word(parent: Instance, name: string, text: string, size: number, heavy: boolean, z: number): TextLabel
	return UIKit.new("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", if heavy then Enum.FontWeight.Heavy else Enum.FontWeight.Bold),
		Text = text,
		TextColor3 = PopTheme.Ink,
		TextSize = size,
		Size = UDim2.fromOffset(math.max(200, #text * size * 0.8), size * 1.25),
		ZIndex = z,
	}, parent)
end

function SecretReveal.build(): View
	local gui = UIKit.new("ScreenGui", {
		Name = "TerraForgeSecret",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 46,
		Enabled = false,
	})
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = SecretReveal.Dark,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, gui)
	local stage = UIKit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = SecretReveal.Center,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 2,
	}, gui)
	local scale = UIKit.new("UIScale", { Scale = 1 }, stage)
	local front, back = {}, {}
	for k = 1, SecretReveal.Bars.Back do
		table.insert(back, bar(stage, "Back" .. k, 40, 2))
	end
	for k = 1, SecretReveal.Bars.Front do
		table.insert(front, bar(stage, "Ray" .. k, 70, 3))
	end
	local halo = UIKit.new("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = SecretReveal.FlashColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(520, 520),
		ZIndex = 4,
	}, stage)
	round(halo)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(300, 300),
		ZIndex = 4,
	}, stage)
	round(glow)
	local rings = {}
	for k = 1, #SecretReveal.Thumps do
		local ring = UIKit.new("Frame", {
			Name = "Beat" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(240, 240),
			Visible = false,
			ZIndex = 4,
		}, stage)
		round(ring)
		UIKit.new("UIStroke", { Color = Color3.fromRGB(190, 140, 255), Thickness = 6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
		UIKit.new("UIScale", { Scale = 1 }, ring)
		table.insert(rings, ring)
	end
	-- the ore: a viewport, the camera turns round it
	local oreHolder = UIKit.new("Frame", {
		Name = "Ore",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(SecretReveal.OreSize, SecretReveal.OreSize),
		ZIndex = 6,
	}, stage)
	local oreScale = UIKit.new("UIScale", { Scale = 1 }, oreHolder)
	local view = UIKit.new("ViewportFrame", {
		Name = "View",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(160, 154, 170),
		LightColor = Color3.fromRGB(255, 248, 236),
		LightDirection = LIGHT,
		ZIndex = 6,
	}, oreHolder)
	local camera = Instance.new("Camera")
	camera.FieldOfView = SecretReveal.Fov
	camera.Parent = view
	view.CurrentCamera = camera
	-- NEW! on a first find: a tilted gold sticker at the ore's top right
	local newTag = UIKit.new("Frame", {
		Name = "New",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 214, 64),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(120, -112),
		Rotation = 12,
		Size = UDim2.fromOffset(92, 40),
		Visible = false,
		ZIndex = 9,
	}, stage)
	UIKit.corner(newTag, 10)
	UIKit.stroke(newTag, 3, PopTheme.Outline)
	local newScale = UIKit.new("UIScale", { Scale = 1 }, newTag)
	local newWord = word(newTag, "Text", "NEW!", 24, true, 10)
	newWord.Position = UDim2.fromScale(0.5, 0.5)
	newWord.Size = UDim2.fromScale(1, 1)
	UIKit.textStroke(newWord, 2, PopTheme.Outline)
	-- "SECRET!" over the ore: rainbow letters with a thick dark edge
	local headline = UIKit.new("Frame", {
		Name = "Headline",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, -205),
		Size = UDim2.fromOffset(420, 90),
		Visible = false,
		ZIndex = 8,
	}, stage)
	local headScale = UIKit.new("UIScale", { Scale = 1 }, headline)
	local headLabel = word(headline, "Text", "SECRET!", 64, true, 8)
	headLabel.Position = UDim2.fromScale(0.5, 0.5)
	headLabel.Size = UDim2.fromScale(1, 1)
	headLabel.Rotation = -6
	UIKit.textStroke(headLabel, 5, PopTheme.Outline)
	local headEdge = UIKit.new("UIGradient", { Color = rainbowSequence(0), Rotation = 0 }, headLabel)
	-- under the ore: name, the SECRET pill, the chance
	local info = UIKit.new("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 150),
		Size = UDim2.fromOffset(560, 150),
		Visible = false,
		ZIndex = 8,
	}, stage)
	local name = word(info, "Name", "", 46, true, 8)
	name.Position = UDim2.new(0.5, 0, 0, 28)
	name.Size = UDim2.new(1, 0, 0, 58)
	UIKit.textStroke(name, 4, PopTheme.Outline)
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(176, 34),
		ZIndex = 8,
	}, info)
	round(pill)
	UIKit.stroke(pill, 3, PopTheme.Outline)
	UIKit.new("UIGradient", { Color = rainbowSequence(0), Rotation = 0 }, pill)
	local pillText = word(pill, "Text", "SECRET", 22, true, 9)
	pillText.Position = UDim2.fromScale(0.5, 0.5)
	pillText.Size = UDim2.fromScale(1, 1)
	UIKit.textStroke(pillText, 3, PopTheme.Outline)
	local chance = word(info, "Chance", "", 22, false, 8)
	chance.Position = UDim2.new(0.5, 0, 0, 118)
	chance.Size = UDim2.new(1, 0, 0, 28)
	UIKit.textStroke(chance, 2, PopTheme.Outline)
	local hint = word(stage, "Hint", "Tap to continue", 20, false, 9)
	hint.Position = UDim2.fromOffset(0, 306)
	hint.TextTransparency = 1
	UIKit.textStroke(hint, 2, PopTheme.Outline)
	-- confetti: a fixed spray (the same every time), coloured by the rainbow
	local confetti: { Piece } = {}
	for k = 1, SecretReveal.Confetti.Full do
		local a = (k * 137.508) % 360
		local frame = UIKit.new("Frame", {
			Name = "Confetti" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = SecretOreShapes.Rainbow[(k - 1) % #SecretOreShapes.Rainbow + 1],
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(if k % 3 == 0 then 10 else 16, if k % 3 == 0 then 10 else 8),
			Visible = false,
			ZIndex = 5, -- out from behind the ore
		}, stage)
		table.insert(confetti, {
			Frame = frame,
			Dir = Vector2.new(math.cos(math.rad(a)), math.sin(math.rad(a)) * 0.8 - 0.35),
			Speed = 420 + (k * 53) % 260,
			Spin = ((k * 97) % 720) - 360,
			Delay = (k % 5) * 0.03,
		})
	end
	return {
		Gui = gui,
		Dim = dim,
		Flash = UIKit.new("Frame", {
			Name = "Flash",
			BackgroundColor3 = SecretReveal.FlashColor,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
		}, gui),
		Stage = stage,
		Scale = scale,
		Front = front,
		Back = back,
		Glow = glow,
		Halo = halo,
		Rings = rings,
		OreHolder = oreHolder,
		OreScale = oreScale,
		View = view,
		Camera = camera,
		Models = {},
		Shadows = {},
		Radius = {},
		OreId = nil,
		New = false,
		Headline = headline,
		HeadScale = headScale,
		HeadLabel = headLabel,
		HeadEdge = headEdge,
		Info = info,
		Name = name,
		Pill = pill,
		Chance = chance,
		NewTag = newTag,
		NewScale = newScale,
		Hint = hint,
		Confetti = confetti,
	}
end

-- The secret ore to reveal next (its model and black copy are built the first time, then kept).
function SecretReveal.setOre(view: View, oreId: string, info: Info?)
	local ore = OreData.get(oreId)
	if not view.Models[oreId] then
		local model = ItemBuilder.display({ K = "Clean", O = oreId, G = SecretOreConfig.Grade }, CFrame.new(), oreId)
		local reach = still(model)
		local shadow = shadowOf(model)
		view.Models[oreId] = model
		view.Shadows[oreId] = shadow
		view.Radius[model] = reach
		view.Radius[shadow] = reach
	end
	view.OreId = oreId
	view.New = info ~= nil and info.New == true
	view.Name.Text = ore.Name
	local secret = SecretOreConfig.ByOre[oreId]
	view.Chance.Text = if info and info.Chance then info.Chance elseif secret then SecretOreConfig.chanceText(secret.OneIn) else ""
end

-- Shows one of the ore's two models (the black one before the flash).
local function showModel(view: View, shadow: boolean): Model?
	local id = view.OreId
	if not id then
		return nil
	end
	local want = if shadow then view.Shadows[id] else view.Models[id]
	for _, child in view.View:GetChildren() do
		if child:IsA("Model") and child ~= want then
			child.Parent = nil
		end
	end
	if want and want.Parent ~= view.View then
		want.Parent = view.View
	end
	return want
end

-- One frame `t` seconds in. Returns true when it is over (the gui is then disabled).
function SecretReveal.pose(view: View, t: number, opts: Opts): boolean
	local reduced = opts.Reduced == true
	if t >= SecretReveal.Total then
		view.Gui.Enabled = false
		return true
	end
	view.Gui.Enabled = true
	view.Scale.Scale = opts.Scale
	local burst = SecretReveal.Burst
	local revealed = t >= burst
	local leave = span(t, SecretReveal.Hold, SecretReveal.Hold + 0.35) -- everything but the ore fades out
	local stay = 1 - leave

	-- the dark overlay
	local dark = span(t, 0, SecretReveal.Dim) * stay
	view.Dim.BackgroundTransparency = 1 - (1 - SecretReveal.DimTo) * dark

	-- the flash (once, at the burst)
	local f = span(t, burst, burst + 0.45)
	local flashing = not reduced and t >= burst and f < 1
	view.Flash.BackgroundTransparency = if flashing then 1 - 0.9 * (1 - easeOut(f)) else 1

	-- the ore: the black one turns and beats, then the real one pops and spins
	local model = showModel(view, not revealed)
	local reach = if model then view.Radius[model] or 1 else 1
	local size: number
	if not revealed then
		size = 0.5 + 0.28 * easeOut(span(t, SecretReveal.Dim * 0.5, burst))
		if not reduced then
			for k, at in SecretReveal.Thumps do
				local beat = span(t, at, at + 0.24)
				if beat > 0 and beat < 1 then
					size += math.sin(beat * math.pi) * (0.08 + k * 0.05)
				end
			end
		end
	else
		local pop = span(t, burst, burst + 0.38)
		size = if reduced then 1 else 0.78 + 0.22 * easeOutBack(pop)
		size += if reduced then 0 else math.sin((t - burst) * 2.4) * 0.025
	end
	local away = Vector2.zero
	local gone = 0
	if t >= SecretReveal.Hold then
		local u = span(t, SecretReveal.Hold, SecretReveal.Hold + SecretReveal.Fly)
		if opts.Target and not reduced then
			-- an arc into the bag, shrinking
			local middle = Vector2.new(opts.Screen.X * SecretReveal.Center.X.Scale, opts.Screen.Y * SecretReveal.Center.Y.Scale)
			local to = (opts.Target - middle) / math.max(opts.Scale, 0.01)
			local e = easeInOut(u)
			away = to * e + Vector2.new(0, -120 * math.sin(u * math.pi))
			size *= 1 - 0.86 * e
		else
			gone = u
		end
	end
	view.OreHolder.Position = UDim2.fromOffset(away.X, away.Y)
	view.OreScale.Scale = size
	view.View.ImageTransparency = gone
	-- the camera: slow turn while hidden, a fast whirl at the burst, then a steady spin
	local turn = 0
	if not reduced then
		turn = t * 1.1
		if revealed then
			turn += math.pi * 2 * easeOut(span(t, burst, burst + 0.7))
		end
		if t >= SecretReveal.Hold then
			turn += (t - SecretReveal.Hold) * 9
		end
	end
	local from = CFrame.Angles(0, turn, 0):VectorToWorldSpace(VIEW_FROM)
	local distance = reach / math.tan(math.rad(SecretReveal.Fov) / 2) * 1.08
	view.Camera.CFrame = CFrame.lookAt(from * distance, Vector3.zero)

	-- beats: a ring flies off every heartbeat
	for k, ring in view.Rings do
		local at = SecretReveal.Thumps[k]
		local u = span(t, at, at + 0.55)
		local on = not reduced and not revealed and u > 0 and u < 1
		ring.Visible = on
		if on then
			local ringScale = ring:FindFirstChildOfClass("UIScale") :: UIScale
			local ringStroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
			ringScale.Scale = 0.7 + 1.3 * easeOut(u)
			ringStroke.Transparency = u
		end
	end

	-- rays: two layers turning opposite ways, near-black and drifting rainbow
	local grow = if revealed then (if reduced then span(t, burst, burst + 0.3) else easeOutBack(span(t, burst, burst + 0.42))) else 0
	local front = if opts.Phone then SecretReveal.Bars.Phone else #view.Front
	for k, frame in view.Front do
		local on = revealed and k <= front and stay > 0
		frame.Visible = on
		if on then
			local spin = if reduced then 0 else (t - burst) * 45
			frame.Rotation = (k - 1) * 180 / front + spin
			frame.Size = UDim2.fromOffset(70, SecretReveal.RayLength * grow)
			frame.BackgroundColor3 = if k % 2 == 1 then SecretReveal.Dark else hue((k - 1) / front + t * 0.25)
			frame.BackgroundTransparency = leave
		end
	end
	for k, frame in view.Back do
		local on = revealed and not opts.Phone and stay > 0
		frame.Visible = on
		if on then
			local spin = if reduced then 0 else -(t - burst) * 30
			frame.Rotation = (k - 0.5) * 180 / #view.Back + spin
			frame.Size = UDim2.fromOffset(40, SecretReveal.RayLength * 0.86 * grow)
			frame.BackgroundColor3 = hue((k - 1) / #view.Back + 0.5 + t * 0.25)
			frame.BackgroundTransparency = 0.45 + 0.55 * leave
		end
	end
	-- the glow behind the ore: a violet pulse while hidden, warm white after
	if revealed then
		view.Glow.BackgroundColor3 = SecretReveal.FlashColor
		view.Glow.BackgroundTransparency = 0.66 + 0.34 * leave
		view.Halo.BackgroundTransparency = 0.88 + 0.12 * leave
	else
		local pulse = 0.5 + 0.5 * math.sin(t * 7)
		view.Glow.BackgroundColor3 = Color3.fromRGB(120, 70, 220)
		view.Glow.BackgroundTransparency = 1 - (0.14 + 0.1 * pulse) * span(t, SecretReveal.Dim * 0.5, SecretReveal.Dim + 0.2)
		view.Halo.BackgroundTransparency = 1
	end

	-- confetti: out from the middle, falling and turning, gone after 2 s
	local pieces = if opts.Phone then SecretReveal.Confetti.Phone else #view.Confetti
	for k, piece in view.Confetti do
		local dt = t - burst - piece.Delay
		local on = revealed and not reduced and k <= pieces and dt > 0 and dt < 2.1
		piece.Frame.Visible = on
		if on then
			local fly = piece.Dir * piece.Speed * dt * (1 - 0.35 * math.min(dt, 1.4))
			local fall = 260 * dt * dt
			piece.Frame.Position = UDim2.fromOffset(fly.X, fly.Y + fall)
			piece.Frame.Rotation = piece.Spin * dt
			piece.Frame.BackgroundTransparency = span(dt, 1.4, 2.1)
		end
	end

	-- SECRET! pops over the ore, its rainbow edge turning
	local headIn = span(t, burst + 0.08, burst + 0.46)
	view.Headline.Visible = revealed and stay > 0
	if view.Headline.Visible then
		view.HeadScale.Scale = if reduced then 1 else easeOutBack(headIn) * (1 + 0.03 * math.sin((t - burst) * 5))
		fade(view.Headline, if reduced then 1 - headIn * stay else leave)
		view.HeadEdge.Rotation = (t * 120) % 360
		view.HeadEdge.Color = rainbowSequence(t * 3)
	end
	-- name, pill and chance slide up under it
	local infoIn = span(t, burst + 0.32, burst + 0.68)
	view.Info.Visible = revealed and infoIn > 0 and stay > 0
	if view.Info.Visible then
		local rise = if reduced then 0 else 26 * (1 - easeOut(infoIn))
		view.Info.Position = UDim2.fromOffset(0, 150 + rise)
		fade(view.Info, 1 - infoIn * stay)
	end
	-- NEW! (a first find)
	local newIn = span(t, burst + 0.62, burst + 0.9)
	view.NewTag.Visible = view.New and revealed and newIn > 0 and stay > 0
	if view.NewTag.Visible then
		view.NewScale.Scale = if reduced then 1 else easeOutBack(newIn)
		view.NewTag.BackgroundTransparency = leave
		fade(view.NewTag, leave)
	end
	-- the tap hint
	view.Hint.TextTransparency = 1 - 0.7 * span(t, SecretReveal.SkipAfter + 0.4, SecretReveal.SkipAfter + 0.8) * stay
	local hintEdge = view.Hint:FindFirstChildOfClass("UIStroke")
	if hintEdge then
		hintEdge.Transparency = view.Hint.TextTransparency
	end
	return false
end

return SecretReveal
