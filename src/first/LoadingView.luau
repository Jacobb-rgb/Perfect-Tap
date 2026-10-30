--[[
	The loading screen's look (LoadingScreen.client.luau runs it, the preview
	builds it too: tools/lune/lib/loading_preview.luau). Plain instances
	only, no services.

	A dark voxel stone wall over a lava glow, the DEEP TERRA logo in the
	middle (the uploaded image, or the text logo: stone DEEP, molten TERRA,
	the crossed-hammers emblem and the MINE • CLEAN • SMELT • BUILD ribbon),
	and the light UI's chunky pills under it (navy outline, white face, a
	lip and a gloss): the progress bar with its green fill, the status line,
	the tip with a gold TIP chip, and the SKIP button in the bottom right
	corner (a gamepad glyph next to it while a controller is in use).

	Everything sits on a design canvas (LoadingConfig.Design) under the
	ScreenGui's UIScale; apply() sizes it for the screen.
]]

local LoadingConfig = require(script.Parent.LoadingConfig)

export type Refs = {
	Gui: ScreenGui,
	Scale: UIScale,
	Backdrop: Frame,
	Embers: Frame,
	Logo: Frame,
	Bottom: Frame,
	Bar: Frame,
	TipPill: Frame,
	TipChip: Frame,
	Fill: Frame,
	Status: TextLabel,
	Tip: TextLabel,
	Skip: TextButton,
	SkipGlyph: ImageLabel,
	SkipKey: TextLabel,
}

local LoadingView = {}

-- the light UI's tokens (BubbleTheme on ui/light; ReplicatedFirst can't require it)
LoadingView.Navy = Color3.fromRGB(27, 29, 51)
LoadingView.White = Color3.fromRGB(255, 255, 255)
LoadingView.Tint = Color3.fromRGB(234, 241, 251)
LoadingView.Dark = Color3.fromRGB(38, 48, 79)
LoadingView.Soft = Color3.fromRGB(104, 117, 150)
LoadingView.Gold = Color3.fromRGB(255, 203, 46)
LoadingView.GreenTop = Color3.fromRGB(128, 240, 140)
LoadingView.GreenBase = Color3.fromRGB(47, 201, 90)
LoadingView.Shadow = Color3.fromRGB(15, 18, 40)

-- the logo's colours (NAHRAJ_DO_ROBLOXU/obchod/logo_terra_forge.png)
local INK = Color3.fromRGB(27, 20, 18)
local STONE_TOP = Color3.fromRGB(241, 240, 246)
local STONE_BASE = Color3.fromRGB(107, 106, 128)
local MOLTEN = {
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 243, 160)),
	ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 207, 58)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 138, 20)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 50, 10)),
}
local AMBER = Color3.fromRGB(255, 176, 46)

local LUCKY = Font.fromEnum(Enum.Font.LuckiestGuy)
local FREDOKA = Font.fromEnum(Enum.Font.FredokaOne)

local function frame(parent: Instance, name: string, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = props.Color or LoadingView.White
	f.BackgroundTransparency = props.Transparency or 0
	f.AnchorPoint = props.Anchor or Vector2.new(0, 0)
	f.Position = props.Position or UDim2.new()
	f.Size = props.Size or UDim2.fromScale(1, 1)
	f.Rotation = props.Rotation or 0
	f.ZIndex = props.Z or 1
	f.Parent = parent
	return f
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number, color: Color3, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
end

local function gradient(parent: Instance, keys: { ColorSequenceKeypoint }, rotation: number, fade: { NumberSequenceKeypoint }?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(keys)
	g.Rotation = rotation
	if fade then
		g.Transparency = NumberSequence.new(fade)
	end
	g.Parent = parent
end

local function two(a: Color3, b: Color3): { ColorSequenceKeypoint }
	return { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) }
end

local function label(parent: Instance, name: string, text: string, font: Font, color: Color3, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = text
	l.FontFace = font
	l.TextColor3 = color
	l.TextScaled = props.Scaled ~= false
	l.TextSize = props.TextSize or 24
	l.TextWrapped = props.Wrap == true
	l.TextXAlignment = props.AlignX or Enum.TextXAlignment.Center
	l.AnchorPoint = props.Anchor or Vector2.new(0, 0)
	l.Position = props.Position or UDim2.new()
	l.Size = props.Size or UDim2.fromScale(1, 1)
	l.ZIndex = props.Z or 1
	l.Parent = parent
	if props.Max then
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = props.Max
		limit.MinTextSize = props.Min or 1
		limit.Parent = l
	end
	return l
end

-- A chunky light-UI body (shadow, lip, face, gloss) filling `parent`; returns the face.
function LoadingView.chunky(parent: Frame, top: Color3, base: Color3, lip: Color3, z: number): Frame
	local round = UDim.new(0.5, 0)
	local shadow = frame(parent, "Shadow", { Color = LoadingView.Shadow, Transparency = 0.72, Position = UDim2.fromOffset(0, 9), Z = z })
	corner(shadow, round)
	local lipF = frame(parent, "Lip", { Color = lip, Position = UDim2.fromOffset(0, 5), Z = z + 1 })
	corner(lipF, round)
	stroke(lipF, 3.5, LoadingView.Navy, true)
	local face = frame(parent, "Face", { Color = LoadingView.White, Z = z + 2 })
	corner(face, round)
	stroke(face, 3.5, LoadingView.Navy, true)
	gradient(face, two(top, base), 90)
	local gloss = frame(parent, "Gloss", {
		Transparency = 0.72,
		Position = UDim2.new(0, 5, 0, 4),
		Size = UDim2.new(1, -10, 0.4, 0),
		Z = z + 3,
	})
	corner(gloss, round)
	return face
end

---------------------------------------------------------------- the backdrop

local STONES = { Color3.fromRGB(46, 40, 58), Color3.fromRGB(38, 33, 49), Color3.fromRGB(54, 46, 66), Color3.fromRGB(33, 28, 42) }

local function backdrop(gui: ScreenGui): Frame
	local bg = frame(gui, "Backdrop", { Color = LoadingView.White, Z = 1 })
	gradient(bg, {
		ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 30, 46)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(26, 20, 30)),
		ColorSequenceKeypoint.new(0.82, Color3.fromRGB(62, 24, 16)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 52, 14)),
	}, 90)
	-- voxel stone blocks: two loose rows along the top, a broken ledge along the bottom
	local blocks = frame(bg, "Stones", { Transparency = 1, Z = 2 })
	local n = 0
	for row, y in { 0.0, 0.11 } do
		for i = 0, 9 do
			n += 1
			local w = 0.1 + (n * 37 % 5) * 0.012
			local stone = frame(blocks, "Stone", {
				Color = STONES[(n % #STONES) + 1],
				Position = UDim2.fromScale(i * 0.1 + (row - 1) * 0.05 - 0.02, y + (n * 13 % 3) * 0.012),
				Size = UDim2.fromScale(w, 0.1),
				Z = 2,
			})
			corner(stone, UDim.new(0, 6))
		end
	end
	for i = 0, 7 do
		local h = 0.07 + (i * 29 % 4) * 0.025
		local rock = frame(blocks, "Ledge", {
			Color = STONES[(i % #STONES) + 1],
			Anchor = Vector2.new(0, 1),
			Position = UDim2.fromScale(i * 0.13 - 0.02, 1),
			Size = UDim2.fromScale(0.15, h),
			Z = 3,
		})
		corner(rock, UDim.new(0, 8))
	end
	-- the lava seam under the ledge and its glow
	local glow =
		frame(bg, "LavaGlow", { Anchor = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.42), Z = 2 })
	gradient(glow, two(Color3.fromRGB(255, 120, 30), Color3.fromRGB(255, 70, 10)), 90, {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.7, 0.7),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	local seam =
		frame(bg, "LavaSeam", { Anchor = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 10), Z = 4 })
	gradient(seam, {
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 96, 20)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 214, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 96, 20)),
	}, 0)
	return bg
end

---------------------------------------------------------------- the logo

local function hammer(parent: Frame, angle: number)
	-- a transparent arm turned about the emblem's centre: the handle and the head
	local arm = frame(parent, "Hammer", { Transparency = 1, Rotation = angle, Z = 7 })
	local handle = frame(arm, "Handle", {
		Color = LoadingView.White,
		Anchor = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.13, 0.62),
		Z = 7,
	})
	corner(handle, UDim.new(0, 4))
	stroke(handle, 3, INK, true)
	gradient(handle, two(Color3.fromRGB(196, 122, 58), Color3.fromRGB(122, 61, 26)), 0)
	local head = frame(arm, "Head", {
		Color = LoadingView.White,
		Anchor = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromScale(0.5, 0.2),
		Z = 8,
	})
	corner(head, UDim.new(0, 5))
	stroke(head, 3, INK, true)
	gradient(head, two(Color3.fromRGB(233, 232, 242), Color3.fromRGB(93, 92, 116)), 90)
end

-- A word of the text logo: a dark depth copy under the gradient face with a thick ink edge.
local function word(parent: Frame, name: string, text: string, y: number, height: number, keys: { ColorSequenceKeypoint })
	local box = frame(parent, name, {
		Transparency = 1,
		Anchor = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, y),
		Size = UDim2.fromScale(1, height),
		Z = 5,
	})
	local depth = label(box, "Depth", text, LUCKY, INK, { Position = UDim2.fromScale(0, 0.07), Z = 5 })
	stroke(depth, 7, INK)
	local face = label(box, "Face", text, LUCKY, LoadingView.White, { Z = 6 })
	stroke(face, 7, INK)
	gradient(face, keys, 90)
end

local function textLogo(logo: Frame)
	local emblem = frame(logo, "Emblem", {
		Color = INK,
		Anchor = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.2, 0.36),
		Z = 6,
	})
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = emblem
	corner(emblem, UDim.new(0.5, 0))
	stroke(emblem, 5, AMBER, true)
	local ember = frame(emblem, "Ember", {
		Anchor = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		Z = 6,
	})
	corner(ember, UDim.new(0.5, 0))
	gradient(ember, MOLTEN, 90)
	hammer(emblem, -42)
	hammer(emblem, 42)
	word(logo, "Deep", "DEEP", 0.31, 0.28, two(STONE_TOP, STONE_BASE))
	word(logo, "Terra", "TERRA", 0.55, 0.38, MOLTEN)
	local ribbon = frame(logo, "Ribbon", {
		Color = LoadingView.White,
		Anchor = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.62, 0.11),
		Z = 6,
	})
	corner(ribbon, UDim.new(0, 14))
	stroke(ribbon, 4, AMBER, true)
	gradient(ribbon, two(Color3.fromRGB(59, 44, 79), Color3.fromRGB(36, 26, 51)), 90)
	label(ribbon, "Words", "MINE • CLEAN • SMELT • BUILD", FREDOKA, Color3.fromRGB(255, 244, 224), {
		Anchor = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.66),
		Z = 7,
	})
end

---------------------------------------------------------------- the pills

function LoadingView.build(): Refs
	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = gui

	local bg = backdrop(gui)
	local embers = frame(gui, "Embers", { Transparency = 1, Z = 4 })

	local logo = frame(gui, "Logo", {
		Transparency = 1,
		Anchor = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(860, 430),
		Z = 5,
	})
	local id = LoadingConfig.logoId()
	if id then
		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.BackgroundTransparency = 1
		image.Image = id
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromScale(1, 1)
		image.ZIndex = 6
		image.Parent = logo
	else
		textLogo(logo)
	end

	-- the bottom block: status, bar, tip
	local bottom = frame(gui, "Bottom", {
		Transparency = 1,
		Anchor = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(760, 170),
		Z = 10,
	})
	local status = label(bottom, "Status", "Loading the world... 0%", FREDOKA, LoadingView.White, {
		Size = UDim2.new(1, 0, 0, 30),
		Z = 12,
		Max = 26,
	})
	stroke(status, 2.5, LoadingView.Navy)

	local bar = frame(bottom, "Bar", { Transparency = 1, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 34), Z = 10 })
	LoadingView.chunky(bar, LoadingView.White, LoadingView.Tint, Color3.fromRGB(196, 206, 228), 10)
	local track = frame(bar, "Track", { Transparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), Z = 14 })
	local fill = frame(track, "Fill", { Size = UDim2.fromScale(0.02, 1), Z = 14 })
	corner(fill, UDim.new(0.5, 0))
	gradient(fill, two(LoadingView.GreenTop, LoadingView.GreenBase), 90)
	local shine = frame(fill, "Shine", { Transparency = 0.6, Position = UDim2.new(0, 4, 0, 2), Size = UDim2.new(1, -8, 0.35, 0), Z = 15 })
	corner(shine, UDim.new(0.5, 0))

	local pill = frame(bottom, "TipPill", { Transparency = 1, Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 58), Z = 10 })
	LoadingView.chunky(pill, LoadingView.White, LoadingView.Tint, Color3.fromRGB(196, 206, 228), 10)
	local chip = frame(pill, "TipChip", {
		Transparency = 1,
		Anchor = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(70, 36),
		Z = 14,
	})
	local chipFace = LoadingView.chunky(chip, Color3.fromRGB(255, 226, 120), LoadingView.Gold, Color3.fromRGB(214, 160, 20), 14)
	chipFace.Name = "ChipFace"
	local chipText = label(chip, "Label", "TIP", LUCKY, LoadingView.White, {
		Anchor = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.7),
		Z = 19,
	})
	stroke(chipText, 2.5, LoadingView.Navy)
	local tip = label(pill, "Tip", LoadingConfig.Tips[1], FREDOKA, LoadingView.Dark, {
		Anchor = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 92, 0.5, 0),
		Size = UDim2.new(1, -110, 0, 40),
		AlignX = Enum.TextXAlignment.Left,
		Wrap = true,
		Max = 22,
		Z = 14,
	})

	-- SKIP: bottom right, hidden until LoadingConfig.SkipAfter
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.BackgroundTransparency = 1
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 1, -24)
	skip.Size = UDim2.fromOffset(150, LoadingConfig.SkipDesignHeight)
	skip.ZIndex = 20
	skip.Visible = false
	skip.Parent = gui
	local skipBody = frame(skip, "Body", { Transparency = 1, Z = 20 })
	LoadingView.chunky(skipBody, LoadingView.White, LoadingView.Tint, Color3.fromRGB(196, 206, 228), 20)
	local skipText = label(skip, "Label", "SKIP", LUCKY, LoadingView.Dark, {
		Anchor = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.55),
		Z = 25,
	})
	skipText.Name = "Label"
	-- the gamepad glyph left of the button (the platform's own image, else a lettered key)
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(1, 0.5)
	glyph.Position = UDim2.new(0, -8, 0.5, 0)
	glyph.Size = UDim2.fromOffset(40, 40)
	glyph.ZIndex = 25
	glyph.Visible = false
	glyph.Parent = skip
	local key = label(skip, "Key", "A", LUCKY, LoadingView.White, {
		Anchor = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Z = 25,
	})
	key.BackgroundTransparency = 0
	key.BackgroundColor3 = LoadingView.GreenBase
	key.Visible = false
	corner(key, UDim.new(0.5, 0))
	stroke(key, 2.5, LoadingView.Navy)

	return {
		Gui = gui,
		Scale = scale,
		Backdrop = bg,
		Embers = embers,
		Logo = logo,
		Bottom = bottom,
		Bar = bar,
		TipPill = pill,
		TipChip = chip,
		Fill = fill,
		Status = status,
		Tip = tip,
		Skip = skip,
		SkipGlyph = glyph,
		SkipKey = key,
	}
end

local function maxText(l: TextLabel, size: number)
	local limit = l:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit.MaxTextSize = math.floor(size)
	end
end

-- Sizes everything for a layout (LoadingConfig.layout).
function LoadingView.apply(refs: Refs, layout: LoadingConfig.Layout)
	refs.Scale.Scale = layout.Scale
	local canvas, margin, k = layout.Canvas, layout.Margin, layout.TextBoost
	-- the bottom block (status, bar, tip), its text larger on small touch screens
	local height = 170 * k
	refs.Status.Size = UDim2.new(1, 0, 0, 30 * k)
	maxText(refs.Status, 26 * k)
	refs.Bar.Position = UDim2.fromOffset(0, 38 * k)
	refs.Bar.Size = UDim2.new(1, 0, 0, 34 * k)
	refs.TipPill.Position = UDim2.fromOffset(0, 96 * k)
	refs.TipPill.Size = UDim2.new(1, 0, 0, 58 * k)
	refs.TipChip.Position = UDim2.new(0, 10 * k, 0.5, 0)
	refs.TipChip.Size = UDim2.fromOffset(70 * k, 36 * k)
	refs.Tip.Position = UDim2.new(0, 92 * k, 0.5, 0)
	refs.Tip.Size = UDim2.new(1, -110 * k, 0, 44 * k)
	maxText(refs.Tip, 22 * k)
	-- SKIP in the bottom right corner beside the block, or over it on a narrow screen
	local skipW = math.max(150, layout.SkipHeight * 2.4)
	local glyph = 56
	local width = math.min(760 * k, canvas.X - 2 * (skipW + margin + glyph))
	local skipY = -margin
	if width < 520 then
		width = math.min(760 * k, canvas.X - margin * 2)
		skipY = -margin - height - 16
	end
	refs.Bottom.Size = UDim2.fromOffset(width, height)
	refs.Bottom.Position = UDim2.new(0.5, 0, 1, -margin)
	refs.Skip.Size = UDim2.fromOffset(skipW, layout.SkipHeight)
	refs.Skip.Position = UDim2.new(1, -margin, 1, skipY)
	-- the logo (2:1, its ribbon hangs 6 % under it) centred in the space above the block
	local free = canvas.Y - margin * 2 - height - 16
	local logoW = math.max(200, math.min(layout.LogoWidth, free * 2 / 1.12))
	refs.Logo.Size = UDim2.fromOffset(logoW, logoW / 2)
	refs.Logo.Position = UDim2.new(0.5, 0, 0, margin + free / 2 - logoW * 0.015)
end

function LoadingView.setProgress(refs: Refs, progress: number, done: boolean)
	local p = math.clamp(progress, 0, 1)
	refs.Fill.Size = UDim2.fromScale(math.max(0.04, p), 1)
	refs.Status.Text = if done then "Ready!" else string.format("Loading the world... %d%%", math.floor(p * 100))
end

function LoadingView.setTip(refs: Refs, text: string)
	refs.Tip.Text = text
end

-- Shows SKIP; `input` = "Gamepad" | "Touch" | "Mouse"; `glyph` = the platform's ButtonA image ("" = none).
function LoadingView.showSkip(refs: Refs, visible: boolean, input: string, glyph: string)
	refs.Skip.Visible = visible
	local pad = input == "Gamepad"
	refs.SkipGlyph.Visible = pad and glyph ~= ""
	refs.SkipGlyph.Image = glyph
	refs.SkipKey.Visible = pad and glyph == ""
end

return LoadingView
