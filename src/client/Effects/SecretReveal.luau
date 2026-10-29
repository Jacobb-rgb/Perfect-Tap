--[[
	SecretReveal: the jackpot screen of a SECRET ore (owner 2026-10-29: "u
	nich musime udelat nejake cool animace ... inspiruj se pet simulatorem";
	his answers to the concept: the jackpot plays when the player CLEANS the
	sparkly dirty ore, "udělej to ještě mnohem mnohem víc cool"). Pure
	builder + pose (SecretRevealController plays it when the cleaning's dirt
	bursts, the Lune previews pose the same frames); nothing runs on its own.
	The build-up happens in the world before it (the cleaning: light leaking
	through the dirt, the shell shaking, heartbeats); this screen starts at
	the BOOM.

	The show (seconds; rarer = bigger, SecretOreConfig Stars 1..3, Tiers):
	  0     one gold-white flash (the shared 2.5 a second cap), a shockwave
	        ring (more rings a moment apart at 2 and 3 stars), the screen
	        darkens (3 stars: deep space with twinkling stars), the ore pops
	        out big, whirling, its moving parts alive (SecretOreFx), the
	        viewport camera pulls back
	  0.05  "SECRET!" slams down from big, rainbow letters; two layers of rays
	        (near-black and rainbow, RevealFx's "Secret" tier), a third gold
	        layer at 2 and 3 stars; confetti, twinkling sparkles round the ore
	  0.3   its name, the SECRET pill with its stars and the chance slide up,
	        NEW! on a first find; 3 stars: a gold ONE IN A MILLION! ribbon
	  Hold  it flies into the backpack button (Fly), everything else fades
	A tap skips to the flight from SkipAfter (the controller moves t on).

	  build()                     -> View (Gui = ScreenGui "TerraForgeSecret",
	                                 DisplayOrder 46, hidden)
	  setOre(view, oreId, info)   info = { Chance = "1 in 4,000", New = true }
	  pose(view, t, opts)         -> done; opts = { Screen = Vector2 (px),
	                                 Scale = the HUD's UI scale, Target =
	                                 the bag's middle (px, nil = fade in place),
	                                 Reduced = Motion.reduced(), Phone = true
	                                 for fewer rays and pieces }
	  total(stars), shake(t, stars) -> the camera nudge (0..1) for the world
	Until Animace's RevealFx (Effects/RevealFx, the egg hatch family) is on
	main the rays, flash and banner are drawn here with its "Secret" values
	(20 rays, (14,10,22) and a rainbow drifting 0.25 turn/s, layers +45 /
	-30 degrees a second, flash (255,240,200) <= 0.9 opaque, gone in 0.45 s;
	Montserrat: headline 64 Heavy with rainbow letters and a 5-unit edge,
	name 46 Heavy, a 34 tall round pill, the chance 22 Bold).
	Reduce motion: no flash, shockwaves, confetti, sparkles or spin; the rays
	stand still, words fade in at full size, the ore fades out where it is.
	Perf: everything is built once (build); a secret ore's model once per ore
	(setOre keeps them: there are 6). A pose sets transforms and colours.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local OreData = require(Config:WaitForChild("OreData"))
local PopTheme = require(Config:WaitForChild("PopTheme"))
local SecretOreConfig = require(Config:WaitForChild("SecretOreConfig"))
local Builders = Shared:WaitForChild("Builders")
local ItemBuilder = require(Builders:WaitForChild("ItemBuilder"))
local SecretOreShapes = require(Builders:WaitForChild("SecretOreShapes"))
local SecretOreFx = require(Builders:WaitForChild("SecretOreFx"))
local UIKit = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIKit"))
local RevealKit = require(script.Parent:WaitForChild("RevealKit"))

local SecretReveal = {}

export type Tier = {
	Hold: number, -- seconds until it flies into the bag
	Shocks: { number }, -- when each shockwave ring starts
	Gold: boolean, -- the third (gold) ray layer
	Confetti: number,
	Twinkles: number,
	Cosmos: boolean, -- deep space behind it, the ONE IN A MILLION! ribbon
	Shake: number, -- the world camera's nudge at the BOOM (0..1)
}

SecretReveal.Tiers = {
	{ Hold = 3.6, Shocks = { 0 }, Gold = false, Confetti = 28, Twinkles = 8, Cosmos = false, Shake = 0.5 },
	{ Hold = 4.2, Shocks = { 0, 0.3 }, Gold = true, Confetti = 36, Twinkles = 12, Cosmos = false, Shake = 0.7 },
	{ Hold = 5.2, Shocks = { 0, 0.3, 0.6 }, Gold = true, Confetti = 44, Twinkles = 16, Cosmos = true, Shake = 0.9 },
} :: { Tier }

SecretReveal.Fly = 0.7
SecretReveal.SkipAfter = 0.8 -- a tap skips to the flight from here
SecretReveal.Center = UDim2.fromScale(0.5, 0.42) -- the middle of it all (RevealFx's Center)
SecretReveal.DimTo = 0.28 -- the dark overlay's transparency at its darkest (3 stars: SpaceTo)
SecretReveal.SpaceTo = 0.06
SecretReveal.OreSize = 320 -- design units: the 3D ore's viewport
SecretReveal.PhoneConfetti = 16
SecretReveal.PhoneTwinkles = 6
SecretReveal.SpaceStars = 44
SecretReveal.Fov = 30
SecretReveal.FlashColor = RevealKit.Style.FlashColor
SecretReveal.Dark = RevealKit.Style.Dark
SecretReveal.Gold = RevealKit.Style.Gold

export type Info = { Chance: string?, New: boolean? }

export type Opts = {
	Screen: Vector2,
	Scale: number,
	Target: Vector2?,
	Reduced: boolean?,
	Phone: boolean?,
	Flash: boolean?, -- false: no flash (another reveal flashed less than RevealKit.FlashGap ago)
}

type Piece = { Frame: Frame, Dir: Vector2, Speed: number, Spin: number, Delay: number }
type Twinkle = { Frame: Frame, Scale: UIScale, At: Vector2, Phase: number }

export type View = {
	Gui: ScreenGui,
	Dim: Frame,
	Space: { Frame },
	Flash: Frame,
	Stage: Frame,
	Scale: UIScale,
	Rays: RevealKit.Rays,
	Glow: Frame,
	Halo: Frame,
	Shocks: { Frame },
	OreHolder: Frame,
	OreScale: UIScale,
	View: ViewportFrame,
	Camera: Camera,
	Models: { [string]: Model },
	Rigs: { [Model]: SecretOreFx.Rig },
	Radius: { [Model]: number },
	OreId: string?,
	Stars: number,
	New: boolean,
	Headline: Frame,
	HeadScale: UIScale,
	HeadLabel: TextLabel,
	HeadEdge: UIGradient,
	Ribbon: Frame,
	RibbonScale: UIScale,
	Info: Frame,
	Name: TextLabel,
	Pill: Frame,
	PillText: TextLabel,
	Chance: TextLabel,
	NewTag: Frame,
	NewScale: UIScale,
	Hint: TextLabel,
	Confetti: { Piece },
	Twinkles: { Twinkle },
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

-- The tier of a secret ore (1 star for an unknown one).
function SecretReveal.tierOf(stars: number?): Tier
	return SecretReveal.Tiers[math.clamp(stars or 1, 1, #SecretReveal.Tiers)]
end

-- How long the whole show of a `stars` secret takes.
function SecretReveal.total(stars: number?): number
	return SecretReveal.tierOf(stars).Hold + SecretReveal.Fly + 0.1
end

-- The world camera's nudge at `t` (0..1): a hard kick at every shockwave, dying out fast.
function SecretReveal.shake(t: number, stars: number?): number
	local tier = SecretReveal.tierOf(stars)
	local trauma = 0
	for k, at in tier.Shocks do
		local dt = t - at
		if dt >= 0 and dt < 0.6 then
			trauma = math.max(trauma, tier.Shake * (if k == 1 then 1 else 0.6) * (1 - dt / 0.6) ^ 2)
		end
	end
	return trauma
end

local fade = RevealKit.fade
local rainbowSequence = RevealKit.rainbow
local hue = RevealKit.hue
local word = RevealKit.word

--[[
	A built item made still for a viewport: its visible parts and its moving
	parts (SecretOreFx: a blinking lid is see-through until it blinks), no
	welds, sparkles, lights or floor disc, anchored, its middle at the
	origin. Returns how far its farthest corner reaches from the middle.
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
		local moving = part:GetAttribute("Move") ~= nil
		if part.Name == "Floor" or (part.Transparency >= 0.99 and not moving) then
			part:Destroy()
			continue
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		table.insert(kept, part)
		if part.Transparency >= 0.99 then
			continue
		end
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

local function disc(parent: Instance, name: string, size: number, color: Color3, z: number): Frame
	local frame = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	}, parent)
	round(frame)
	return frame
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
	-- deep space (3 stars): little stars all over the screen, twinkling
	local space = {}
	for k = 1, SecretReveal.SpaceStars do
		local size = 2 + (k * 7) % 4
		local star = UIKit.new("Frame", {
			Name = "Star" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if k % 5 == 0 then SecretReveal.Gold else WHITE,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(((k * 0.618034) % 1), ((k * 0.381966 + 0.13) % 1)),
			Size = UDim2.fromOffset(size, size),
			Visible = false,
			ZIndex = 1,
		}, gui)
		round(star)
		table.insert(space, star)
	end
	local stage = UIKit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = SecretReveal.Center,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 2,
	}, gui)
	local scale = UIKit.new("UIScale", { Scale = 1 }, stage)
	local rays = RevealKit.rays(stage, 2)
	local halo = disc(stage, "Halo", 560, SecretReveal.FlashColor, 4)
	local glow = disc(stage, "Glow", 320, WHITE, 4)
	-- shockwave rings: thick, fast, thinning as they fly out
	local shocks = RevealKit.rings(stage, 3, 5)
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
	-- twinkling sparkles round the ore: a thin cross that grows, turns and shrinks
	local twinkles: { Twinkle } = {}
	for k = 1, SecretReveal.Tiers[#SecretReveal.Tiers].Twinkles do
		local a = k * 2.399963 -- the golden angle: spread round the ore
		local r = 170 + (k * 37) % 120
		local frame = UIKit.new("Frame", {
			Name = "Twinkle" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(44, 44),
			Visible = false,
			ZIndex = 7,
		}, stage)
		local color = if k % 3 == 0 then SecretReveal.Gold else WHITE
		for _, size in { Vector2.new(44, 6), Vector2.new(6, 44) } do
			local arm = UIKit.new("Frame", {
				Name = "Arm",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size.X, size.Y),
				ZIndex = 7,
			}, frame)
			round(arm)
		end
		table.insert(twinkles, {
			Frame = frame,
			Scale = UIKit.new("UIScale", { Scale = 0 }, frame),
			At = Vector2.new(math.cos(a) * r, math.sin(a) * r * 0.8),
			Phase = (k * 0.37) % 1,
		})
	end
	-- NEW! on a first find: a tilted gold sticker at the ore's top right
	local newTag = UIKit.new("Frame", {
		Name = "New",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 214, 64),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(130, -118),
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
		Position = UDim2.fromOffset(0, -212),
		Size = UDim2.fromOffset(440, 96),
		Visible = false,
		ZIndex = 8,
	}, stage)
	local headScale = UIKit.new("UIScale", { Scale = 1 }, headline)
	local headLabel = word(headline, "Text", "SECRET!", 64, true, 8)
	headLabel.Position = UDim2.fromScale(0.5, 0.5)
	headLabel.Size = UDim2.fromScale(1, 1)
	headLabel.Rotation = -6
	headLabel.TextColor3 = WHITE
	UIKit.textStroke(headLabel, 5, PopTheme.Outline)
	local headEdge = UIKit.new("UIGradient", { Color = rainbowSequence(0), Rotation = 0 }, headLabel)
	-- 3 stars: a gold ribbon over the headline
	local ribbon = UIKit.new("Frame", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = SecretReveal.Gold,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -282),
		Size = UDim2.fromOffset(330, 40),
		Visible = false,
		ZIndex = 8,
	}, stage)
	UIKit.corner(ribbon, 12)
	UIKit.stroke(ribbon, 3, PopTheme.Outline)
	local ribbonScale = UIKit.new("UIScale", { Scale = 1 }, ribbon)
	local ribbonWord = word(ribbon, "Text", "ONE IN A MILLION!", 24, true, 9)
	ribbonWord.Position = UDim2.fromScale(0.5, 0.5)
	ribbonWord.Size = UDim2.fromScale(1, 1)
	ribbonWord.TextColor3 = WHITE
	UIKit.textStroke(ribbonWord, 3, PopTheme.Outline)
	-- under the ore: name, the SECRET pill with its stars, the chance
	local info = UIKit.new("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 160),
		Size = UDim2.fromOffset(560, 150),
		Visible = false,
		ZIndex = 8,
	}, stage)
	local name = word(info, "Name", "", 46, true, 8)
	name.Position = UDim2.new(0.5, 0, 0, 28)
	name.Size = UDim2.new(1, 0, 0, 58)
	name.TextColor3 = WHITE
	UIKit.textStroke(name, 4, PopTheme.Outline)
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(196, 34),
		ZIndex = 8,
	}, info)
	round(pill)
	UIKit.stroke(pill, 3, PopTheme.Outline)
	UIKit.new("UIGradient", { Color = rainbowSequence(0), Rotation = 0 }, pill)
	local pillText = word(pill, "Text", "SECRET", 22, true, 9)
	pillText.Position = UDim2.fromScale(0.5, 0.5)
	pillText.Size = UDim2.fromScale(1, 1)
	pillText.TextColor3 = WHITE
	UIKit.textStroke(pillText, 3, PopTheme.Outline)
	local chance = word(info, "Chance", "", 22, false, 8)
	chance.Position = UDim2.new(0.5, 0, 0, 118)
	chance.Size = UDim2.new(1, 0, 0, 28)
	chance.TextColor3 = WHITE
	UIKit.textStroke(chance, 2, PopTheme.Outline)
	local hint = word(stage, "Hint", "Tap to continue", 20, false, 9)
	hint.Position = UDim2.fromOffset(0, 316)
	hint.TextColor3 = WHITE
	hint.TextTransparency = 1
	UIKit.textStroke(hint, 2, PopTheme.Outline)
	-- confetti: a fixed spray (the same every time), coloured by the rainbow (and gold)
	local confetti: { Piece } = {}
	for k = 1, SecretReveal.Tiers[#SecretReveal.Tiers].Confetti do
		local a = (k * 137.508) % 360
		local frame = UIKit.new("Frame", {
			Name = "Confetti" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if k % 7 == 0 then SecretReveal.Gold else SecretOreShapes.Rainbow[(k - 1) % #SecretOreShapes.Rainbow + 1],
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(if k % 3 == 0 then 10 else 16, if k % 3 == 0 then 10 else 8),
			Visible = false,
			ZIndex = 5, -- out from behind the ore
		}, stage)
		table.insert(confetti, {
			Frame = frame,
			Dir = Vector2.new(math.cos(math.rad(a)), math.sin(math.rad(a)) * 0.8 - 0.35),
			Speed = 460 + (k * 53) % 300,
			Spin = ((k * 97) % 720) - 360,
			Delay = (k % 5) * 0.03,
		})
	end
	return {
		Gui = gui,
		Dim = dim,
		Space = space,
		Flash = RevealKit.flash(gui, 5),
		Stage = stage,
		Scale = scale,
		Rays = rays,
		Glow = glow,
		Halo = halo,
		Shocks = shocks,
		OreHolder = oreHolder,
		OreScale = oreScale,
		View = view,
		Camera = camera,
		Models = {},
		Rigs = {},
		Radius = {},
		OreId = nil,
		Stars = 1,
		New = false,
		Headline = headline,
		HeadScale = headScale,
		HeadLabel = headLabel,
		HeadEdge = headEdge,
		Ribbon = ribbon,
		RibbonScale = ribbonScale,
		Info = info,
		Name = name,
		Pill = pill,
		PillText = pillText,
		Chance = chance,
		NewTag = newTag,
		NewScale = newScale,
		Hint = hint,
		Confetti = confetti,
		Twinkles = twinkles,
	}
end

-- The secret ore to reveal next (its model is built the first time, then kept).
function SecretReveal.setOre(view: View, oreId: string, info: Info?)
	local ore = OreData.get(oreId)
	if not view.Models[oreId] then
		local model = ItemBuilder.display({ K = "Clean", O = oreId, G = SecretOreConfig.Grade }, CFrame.new(), oreId)
		local reach = still(model)
		view.Models[oreId] = model
		view.Rigs[model] = SecretOreFx.rig(model, CFrame.identity)
		view.Radius[model] = reach
	end
	local secret = SecretOreConfig.ByOre[oreId]
	view.OreId = oreId
	view.Stars = if secret then secret.Stars else 1
	view.New = info ~= nil and info.New == true
	view.Name.Text = ore.Name
	view.PillText.Text = "SECRET " .. string.rep("★", view.Stars)
	view.Pill.Size = UDim2.fromOffset(176 + 22 * view.Stars, 34)
	view.Chance.Text = if info and info.Chance then info.Chance elseif secret then SecretOreConfig.chanceText(secret.OneIn) else ""
end

-- Shows the current ore's model in the viewport.
local function showModel(view: View): Model?
	local id = view.OreId
	if not id then
		return nil
	end
	local want = view.Models[id]
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

-- One frame `t` seconds after the BOOM. Returns true when it is over (the gui is then disabled).
function SecretReveal.pose(view: View, t: number, opts: Opts): boolean
	local reduced = opts.Reduced == true
	local phone = opts.Phone == true
	local tier = SecretReveal.tierOf(view.Stars)
	local hold = tier.Hold
	if t >= hold + SecretReveal.Fly + 0.1 or t < 0 then
		view.Gui.Enabled = false
		return t >= 0
	end
	view.Gui.Enabled = true
	view.Scale.Scale = opts.Scale
	local leave = span(t, hold, hold + 0.35) -- everything but the ore fades out
	local stay = 1 - leave

	-- the dark (3 stars: deep space)
	local dark = easeOut(span(t, 0, 0.14)) * stay
	local darkest = if tier.Cosmos then SecretReveal.SpaceTo else SecretReveal.DimTo
	view.Dim.BackgroundTransparency = 1 - (1 - darkest) * dark
	for k, star in view.Space do
		local on = tier.Cosmos and stay > 0 and (not phone or k % 2 == 0)
		star.Visible = on
		if on then
			local twinkle = if reduced then 0.5 else 0.5 + 0.5 * math.sin(t * (2 + k % 5) + k)
			star.BackgroundTransparency = 1 - (0.25 + 0.75 * twinkle) * dark
		end
	end

	-- the flash (once, at the BOOM; the caller took its slot: RevealKit.takeFlash)
	RevealKit.poseFlash(view.Flash, if reduced or opts.Flash == false then -1 else t / RevealKit.Style.FlashTime)

	-- shockwaves: one ring per tier step, the first white-gold, the others rainbow
	for k, ring in view.Shocks do
		local at = tier.Shocks[k]
		local u = if at and not reduced then (t - at) / 0.62 else -1
		local color = if k == 1 then SecretReveal.FlashColor:Lerp(hue(t * 0.6), math.clamp(u, 0, 1)) else hue(k * 0.33 + u * 0.5)
		RevealKit.poseRing(ring, u, color)
	end

	-- the ore: pops out big, whirls, breathes; its moving parts are alive
	local model = showModel(view)
	local reach = if model then view.Radius[model] or 1 else 1
	if model and view.Rigs[model] then
		SecretOreFx.pose(view.Rigs[model], CFrame.identity, t, reduced)
	end
	local pop = span(t, 0, 0.4)
	local size = if reduced then 1 else 0.55 + 0.45 * easeOutBack(pop)
	size += if reduced then 0 else math.sin(t * 2.4) * 0.025
	local away = Vector2.zero
	local gone = 0
	if t >= hold then
		local u = span(t, hold, hold + SecretReveal.Fly)
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
	-- the viewport camera: a fast whirl and a pull back at the BOOM, then a steady turn
	local turn = 0
	local pull = 1
	if not reduced then
		turn = t * 1.1 + math.pi * 2 * easeOut(span(t, 0, 0.8))
		pull = 0.72 + 0.28 * easeOut(span(t, 0, 0.9))
		if t >= hold then
			turn += (t - hold) * 9
		end
	end
	local from = CFrame.Angles(0, turn, 0):VectorToWorldSpace(VIEW_FROM)
	local distance = reach / math.tan(math.rad(SecretReveal.Fov) / 2) * 1.08 * pull
	view.Camera.CFrame = CFrame.lookAt(from * distance, Vector3.zero)

	-- rays: two layers turning opposite ways (near-black and drifting rainbow), a gold one behind
	local grow = if reduced then span(t, 0, 0.3) else easeOutBack(span(t, 0.02, 0.45))
	RevealKit.poseRays(view.Rays, t, grow, leave, { Phone = phone, Reduced = reduced, Gold = tier.Gold })
	-- the warm glow behind the ore, a beat at every shockwave
	local swell = 0
	for _, at in tier.Shocks do
		local u = span(t, at, at + 0.4)
		if u > 0 and u < 1 then
			swell = math.max(swell, math.sin(u * math.pi))
		end
	end
	view.Glow.BackgroundColor3 = SecretReveal.FlashColor
	view.Glow.BackgroundTransparency = 0.66 - 0.3 * swell * (if reduced then 0 else 1) + 0.34 * leave
	view.Halo.BackgroundColor3 = if tier.Cosmos then SecretReveal.Gold else SecretReveal.FlashColor
	view.Halo.BackgroundTransparency = 0.86 + 0.14 * leave

	-- sparkles twinkling round the ore
	local twinkles = if phone then SecretReveal.PhoneTwinkles else tier.Twinkles
	for k, tw in view.Twinkles do
		local on = not reduced and k <= twinkles and stay > 0 and t > 0.15
		tw.Frame.Visible = on
		if on then
			local u = ((t - 0.15) * 0.9 + tw.Phase) % 1
			tw.Scale.Scale = math.sin(u * math.pi) ^ 2 * (0.7 + 0.3 * (k % 3))
			tw.Frame.Rotation = u * 90
			tw.Frame.Position = UDim2.fromOffset(tw.At.X, tw.At.Y)
		end
	end

	-- confetti: out from the middle, falling and turning, gone after 2.2 s
	local pieces = if phone then SecretReveal.PhoneConfetti else tier.Confetti
	for k, piece in view.Confetti do
		local dt = t - piece.Delay
		local on = not reduced and k <= pieces and dt > 0 and dt < 2.2
		piece.Frame.Visible = on
		if on then
			local fly = piece.Dir * piece.Speed * dt * (1 - 0.35 * math.min(dt, 1.4))
			local fall = 260 * dt * dt
			piece.Frame.Position = UDim2.fromOffset(fly.X, fly.Y + fall)
			piece.Frame.Rotation = piece.Spin * dt
			piece.Frame.BackgroundTransparency = span(dt, 1.5, 2.2)
		end
	end

	-- SECRET! slams down from big (a squash on impact), its rainbow drifting
	local slam = span(t, 0.05, 0.27)
	view.Headline.Visible = stay > 0
	if view.Headline.Visible then
		local s: number
		if reduced then
			s = 1
		elseif slam < 1 then
			s = 2.6 - 1.6 * slam * slam
		else
			local after = t - 0.27
			s = 1 + 0.12 * math.exp(-after * 9) * math.cos(after * 30) + 0.03 * math.sin(t * 5)
		end
		view.HeadScale.Scale = s
		fade(view.Headline, if reduced then 1 - span(t, 0, 0.3) * stay else math.max(leave, 1 - slam * 3))
		view.HeadEdge.Rotation = (t * 120) % 360
		view.HeadEdge.Color = rainbowSequence(t * 3)
	end
	-- 3 stars: the gold ONE IN A MILLION! ribbon
	local ribbonIn = span(t, 0.35, 0.65)
	view.Ribbon.Visible = tier.Cosmos and ribbonIn > 0 and stay > 0
	if view.Ribbon.Visible then
		view.RibbonScale.Scale = if reduced then 1 else easeOutBack(ribbonIn) * (1 + 0.04 * math.sin(t * 6))
		view.Ribbon.BackgroundTransparency = leave
		fade(view.Ribbon, leave)
	end
	-- name, pill and chance slide up under it
	local infoIn = span(t, 0.3, 0.64)
	view.Info.Visible = infoIn > 0 and stay > 0
	if view.Info.Visible then
		local rise = if reduced then 0 else 26 * (1 - easeOut(infoIn))
		view.Info.Position = UDim2.fromOffset(0, 160 + rise)
		fade(view.Info, 1 - infoIn * stay)
	end
	-- NEW! (a first find)
	local newIn = span(t, 0.58, 0.86)
	view.NewTag.Visible = view.New and newIn > 0 and stay > 0
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
