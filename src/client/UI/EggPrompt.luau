--[[
	EggPrompt: the eggs' big round E (owner 2026-10-28, round 2: "yes, a big
	E; make it even cooler"), the look of his egg-game photos drawn with our
	kit, for the "Buy Egg!" ProximityPrompt of the egg you stand at (Style
	Custom on that prompt only, EggPanel.BigE: the keys, the hold and
	the trigger stay Roblox's own).

	        Buy Egg!          white, a dark edge
	      .--------.
	     (    E     )         a big white disc, a thick dark ring, a big E
	      '--------'          (a gamepad: its button's glyph; touch: "Tap")
	        $2,500            the price under it

	- Cool: a soft ring of light behind the disc that breathes (Glow,
	  GlowScale: EggPanel.GlowPeriod), a light band sweeping across the disc
	  now and then (Shine: a UIGradient Offset, ShineEvery seconds apart) and a
	  squash when it is pressed (Press). EggPanelController plays them, never
	  with Reduce motion (then it only fades).
	- The disc is a button: a tap (or a click) holds the prompt
	  (InputHoldBegin / InputHoldEnd, EggPanelController), 96 units: 59 pt
	  at the phone scale, past the 44 pt touch target.
	- A BillboardGui (PlayerGui, AlwaysOnTop) centred on the prompt's point;
	  laid out in design units, scaled like the HUD (setScale).

	Pure: only Instance creation (the Lune specs and previews run it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopTheme = require(Shared.Config.PopTheme)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local EggPanel = require(script.Parent.EggPanel)

local EggPrompt = {}

EggPrompt.Disc = 96 -- the white disc (design units)
EggPrompt.GlowSize = 136 -- the ring of light behind it
EggPrompt.Width = 220
EggPrompt.Height = 206
EggPrompt.ShineEvery = 2.6 -- seconds from one sweep to the next (EggPanelController)
EggPrompt.ShineTime = 0.55

local rgb = Color3.fromRGB
local INK = PopTheme.Outline

export type Refs = {
	Gui: BillboardGui,
	Root: Frame,
	Scale: UIScale,
	Title: TextLabel,
	Disc: TextButton,
	Press: UIScale,
	Key: TextLabel,
	Glyph: ImageLabel,
	Shine: UIGradient,
	Glow: Frame,
	GlowRing: UIStroke,
	GlowScale: UIScale,
	Price: TextLabel,
	Fades: { EggPanel.Fade },
}

function EggPrompt.build(): Refs
	local gui = UIKit.new("BillboardGui", {
		Name = "TerraForgeEggPrompt",
		Active = true,
		AlwaysOnTop = true,
		ClipsDescendants = false,
		Enabled = false,
		LightInfluence = 0,
		MaxDistance = 1000,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(EggPrompt.Width, EggPrompt.Height),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: BillboardGui
	local root = UIKit.new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(EggPrompt.Width, EggPrompt.Height),
	}, gui) :: Frame
	local scale = UIKit.new("UIScale", { Name = "Fit", Scale = 1 }, root) :: UIScale
	local title = Pop.text(root, "Buy Egg!", 28, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 6,
	})
	local discY = 36 + 8 + EggPrompt.Disc / 2
	-- the ring of light: a thick soft stroke round an empty circle, breathing
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(EggPrompt.Width / 2, discY),
		Size = UDim2.fromOffset(EggPrompt.GlowSize, EggPrompt.GlowSize),
		ZIndex = 2,
	}, root) :: Frame
	UIKit.corner(glow, 999)
	local ring = UIKit.new("UIStroke", {
		Name = "Ring",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.new(1, 1, 1),
		Thickness = 7,
		Transparency = 0.45,
	}, glow) :: UIStroke
	local glowScale = UIKit.new("UIScale", { Name = "Breathe", Scale = 1 }, glow) :: UIScale
	-- the disc: white, a thick dark ring, the key
	local disc = UIKit.new("TextButton", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(EggPrompt.Width / 2, discY),
		Selectable = false,
		Size = UDim2.fromOffset(EggPrompt.Disc, EggPrompt.Disc),
		Text = "",
		ZIndex = 4,
	}, root) :: TextButton
	UIKit.corner(disc, 999)
	Pop.border(disc, 6)
	local press = UIKit.new("UIScale", { Name = "Press", Scale = 1 }, disc) :: UIScale
	-- the light band (white -> a cool tint -> white, swept across by its Offset)
	local shine = UIKit.new("UIGradient", {
		Name = "Shine",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.42, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, rgb(206, 232, 255)),
			ColorSequenceKeypoint.new(0.58, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
		}),
		Offset = Vector2.new(-1, 0),
		Rotation = 25,
	}, disc) :: UIGradient
	local key = UIKit.new("TextLabel", {
		Name = "Key",
		BackgroundTransparency = 1,
		FontFace = PopTheme.Pixel,
		Size = UDim2.fromScale(1, 1),
		Text = "E",
		TextColor3 = INK,
		TextSize = 60,
		ZIndex = 5,
	}, disc) :: TextLabel
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = "",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		Visible = false,
		ZIndex = 5,
	}, disc) :: ImageLabel
	local price = Pop.text(root, "", 24, {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(EggPrompt.Width / 2, discY + EggPrompt.Disc / 2 + 12),
		Size = UDim2.fromOffset(EggPrompt.Width, 32),
		ZIndex = 6,
	})
	return {
		Gui = gui,
		Root = root,
		Scale = scale,
		Title = title,
		Disc = disc,
		Press = press,
		Key = key,
		Glyph = glyph,
		Shine = shine,
		Glow = glow,
		GlowRing = ring,
		GlowScale = glowScale,
		Price = price,
		Fades = EggPanel.fadesOf(root),
	}
end

-- The billboard's size for the HUD's scale.
function EggPrompt.setScale(refs: Refs, scale: number)
	refs.Gui.Size = UDim2.fromOffset(math.ceil(EggPrompt.Width * scale), math.ceil(EggPrompt.Height * scale))
	refs.Scale.Scale = scale
end

-- The key on the disc: a keyboard letter ("E"), a gamepad glyph (`image`), or "Tap" on touch.
function EggPrompt.setKey(refs: Refs, text: string, image: string?)
	local hasImage = image ~= nil and image ~= ""
	refs.Key.Text = text
	refs.Key.TextSize = if #text > 1 then 30 else 60
	refs.Key.Visible = not hasImage
	refs.Glyph.Image = image or ""
	refs.Glyph.Visible = hasImage
end

-- The words: the action over the disc, the price under it (red when the player can't pay it).
function EggPrompt.setText(refs: Refs, action: string, price: string, affordable: boolean)
	refs.Title.Text = action
	refs.Price.Text = price
	refs.Price.TextColor3 = if affordable then Color3.new(1, 1, 1) else rgb(255, 120, 120)
end

-- The ring of light's colour (the egg's glow).
function EggPrompt.setGlow(refs: Refs, color: Color3)
	refs.Glow.BackgroundColor3 = color
	refs.GlowRing.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
end

-- 0 = shown, 1 = gone.
function EggPrompt.setFade(refs: Refs, alpha: number)
	EggPanel.applyFades(refs.Fades, alpha)
end

return EggPrompt
