--[[
	ShopFx: the shop v3 "WOW" look's effects (owner 2026-11-11, the concept
	docs/art/shop_v3_concept/shop_wow.html: "add styles, colours, glows,
	lightning in the background, make it mega cool"), built from plain
	frames so the shop looks good before any picture is uploaded:

	  Themes      one colour world per tab (header band, body, glow, bolts)
	  Cards       the card paints (light -> mid -> deep, the concept's c-*)
	  face        a painted face: gradient, round corners, the thick dark outline
	  drop        the dark slab under a face (the "lip" the concept draws 6-8 px down)
	  gloss / rim the light half-moon over a card's top, the light edge inside its outline
	  text        white chunky text (Fredoka One) with a dark edge and a dark copy under it
	  rays        light rays turning behind a picture (thin bars, gradient-faded ends)
	  bolt        a jagged lightning bolt from rotated frame segments (it flashes)
	  sparkle     a four-point star (it pulses), dots (particles), glow (soft discs)
	  studs       classic Roblox top studs from small round frames (header and tabs)
	  priceButton the 3D green Robux button (gold / red / purple / grey), a shine sweeps it
	  sticker     "BEST VALUE!" on a card's top edge; chip: a dark label pill
	  mythicRim   a rainbow outline that runs round a Mythic card
	  icon        a picture from the shop icon sheet (IconAssets.Shop), nil until uploaded
	  wheel / x2  a spin wheel and the "x2" badge drawn from frames

	Motion (one Heartbeat connection while the shop is open, 30 steps a
	second; start / focus / stop): the rays turn, the bolts flash, a shine
	sweeps the buy buttons, the open tab bobs, the Mythic rims run, the
	sparkles pulse: a 2 s loop like the concept's frame(t). Things mark
	themselves with the attribute ShopFx ("Rays", "Bolt", "Shine", "Rim",
	"Sparkle"); start() finds them under the roots it is given. The pure
	timing functions (rayAngle, boltOn, shineOffset, bob, rimAngle,
	sparkleScale) and boltPoints have Lune tests (tests/ShopFx.spec.luau).

	Pure builders (only Instance creation): the Lune previews run them too.
	No emoji anywhere.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local IconAssets = require(Shared.Config.IconAssets)
local UIKit = require(script.Parent.UIKit)

local ShopFx = {}

type Props = { [string]: any }

local hex = Color3.fromHex
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

ShopFx.Font = Font.fromEnum(Enum.Font.FredokaOne)
ShopFx.Outline = hex("#1a1030") -- every outline and text edge (the concept's ink)
ShopFx.DropColor = hex("#0c0828") -- the slab under faces

local function apply(instance: Instance, props: Props?)
	if props then
		local target: any = instance
		for key, value in props do
			target[key] = value
		end
	end
end

---------------------------------------------------------------- colours

export type Theme = {
	Head: { Color3 }, -- the header band, top -> bottom
	Body: { Color3 }, -- the window body, top -> bottom
	Glow: Color3, -- the window's glow and the aura behind it
	Bolt: Color3, -- the lightning
	Bolt2: Color3, -- the second lightning colour (sparkles too)
	Title: Color3, -- the low end of the SHOP title's gradient
	Tab: { Color3 }, -- the tab's own face
	TabGlow: Color3,
}

-- one colour world per tab (the concept's THEMES and TABS)
ShopFx.Themes = {
	Featured = {
		Head = { hex("#ff7aa8"), hex("#ff2a6a"), hex("#c80a4a") },
		Body = { hex("#a8166a"), hex("#5a0a46"), hex("#2a0632") },
		Glow = hex("#ff3c8c"),
		Bolt = hex("#ff9ad0"),
		Bolt2 = hex("#ffd84a"),
		Title = hex("#ffd0e4"),
		Tab = { hex("#ff9ac0"), hex("#ff2a6a"), hex("#c80a4a") },
		TabGlow = hex("#ff5096"),
	},
	Golems = {
		Head = { hex("#d29aff"), hex("#9a3cff"), hex("#6a14d8") },
		Body = { hex("#6a2ad8"), hex("#3a1490"), hex("#1a0a4a") },
		Glow = hex("#aa5aff"),
		Bolt = hex("#d6a6ff"),
		Bolt2 = hex("#7ff4ff"),
		Title = hex("#e8d0ff"),
		Tab = { hex("#dcaaff"), hex("#9a3cff"), hex("#6a14d8") },
		TabGlow = hex("#b464ff"),
	},
	Blasters = {
		Head = { hex("#7ae8ff"), hex("#1aa2ff"), hex("#0a5ad8") },
		Body = { hex("#1a5ae0"), hex("#0c2a8a"), hex("#060e3a") },
		Glow = hex("#28b4ff"),
		Bolt = hex("#9af4ff"),
		Bolt2 = hex("#ffffff"),
		Title = hex("#bff0ff"),
		Tab = { hex("#8aeeff"), hex("#1aa2ff"), hex("#0a5ad8") },
		TabGlow = hex("#3cc8ff"),
	},
	Passes = {
		Head = { hex("#fff07a"), hex("#ffb41a"), hex("#e8780a") },
		Body = { hex("#7a2ad0"), hex("#44148a"), hex("#1e0a48") },
		Glow = hex("#ffbe28"),
		Bolt = hex("#ffe07a"),
		Bolt2 = hex("#ffffff"),
		Title = hex("#fff3b0"),
		Tab = { hex("#fff27a"), hex("#ffb41a"), hex("#e8780a") },
		TabGlow = hex("#ffc83c"),
	},
	Boosts = {
		Head = { hex("#b4ff6a"), hex("#3fd02a"), hex("#1a9a18") },
		Body = { hex("#1e9a3a"), hex("#0c5a28"), hex("#052a14") },
		Glow = hex("#5aff5a"),
		Bolt = hex("#c8ff8a"),
		Bolt2 = hex("#fff27a"),
		Title = hex("#e6ffc8"),
		Tab = { hex("#c0ff7a"), hex("#3fd02a"), hex("#1a9a18") },
		TabGlow = hex("#78ff5a"),
	},
	Cash = {
		Head = { hex("#e6ff7a"), hex("#8cd62a"), hex("#3a9a18") },
		Body = { hex("#1aa060"), hex("#0a6a40"), hex("#033020") },
		Glow = hex("#8cff50"),
		Bolt = hex("#fff27a"),
		Bolt2 = hex("#c8ff8a"),
		Title = hex("#f6ffd0"),
		Tab = { hex("#eaff8a"), hex("#8cd62a"), hex("#3a9a18") },
		TabGlow = hex("#beff5a"),
	},
} :: { [string]: Theme }

-- the card paints: light -> mid -> deep (the concept's c-* classes); Rainbow has six
ShopFx.Cards = {
	Green = { hex("#a6ff6a"), hex("#3fd02a"), hex("#1e9a18") },
	Blue = { hex("#8ae0ff"), hex("#2f8cff"), hex("#1d4fc6") },
	Purple = { hex("#e6a6ff"), hex("#a64dff"), hex("#6418c8") },
	Pink = { hex("#ffb0dc"), hex("#ff4fa3"), hex("#c8106a") },
	Orange = { hex("#ffd88a"), hex("#ff9a2a"), hex("#d8540a") },
	Gold = { hex("#fff6b0"), hex("#ffcf2a"), hex("#e8880a") },
	Red = { hex("#ffa496"), hex("#ff4a4a"), hex("#b4142a") },
	Teal = { hex("#9affee"), hex("#20d6b8"), hex("#0a8a7a") },
	Navy = { hex("#8a9cff"), hex("#3a46c8"), hex("#1a1f78") },
	Night = { hex("#3a3a9a"), hex("#1a1a5a"), hex("#0a0a2a") },
	Cyber = { hex("#3ad8ff"), hex("#1a5aff"), hex("#2a0a8a") },
	Mythic = { hex("#ff5a6a"), hex("#8a0a3a"), hex("#1a0420") },
	Royal = { hex("#c68aff"), hex("#7a2ae0"), hex("#3a0a90") }, -- the Forgemaster's Pass
	Amber = { hex("#fff27a"), hex("#ffb41a"), hex("#e0700a") }, -- the 2x Money band
	Fire = { hex("#ffb02a"), hex("#ff5a1a"), hex("#c8143a"), hex("#5a0a3a"), hex("#2a0628") }, -- the limited banner
	Rainbow = { hex("#ff6a8a"), hex("#ffb84a"), hex("#ffe94a"), hex("#5ff07a"), hex("#4ac8ff"), hex("#a86aff") },
} :: { [string]: { Color3 } }

-- the running rim and rainbow rays
ShopFx.RainbowRim = { hex("#ff3a6a"), hex("#ffa53a"), hex("#ffe84a"), hex("#5ff07a"), hex("#4ac8ff"), hex("#a86aff"), hex("#ff3a6a") }

export type ButtonStyle = { Top: Color3, Mid: Color3, Low: Color3, Lip: Color3, Ink: Color3 }

-- the 3D buy buttons (the concept's .btn classes)
ShopFx.Buttons = {
	Green = { Top = hex("#a4ff5a"), Mid = hex("#4fd62a"), Low = hex("#2aa61a"), Lip = hex("#1f8a12"), Ink = hex("#0b3a05") },
	Gold = { Top = hex("#fff27a"), Mid = hex("#ffc21a"), Low = hex("#f0900a"), Lip = hex("#c06a00"), Ink = hex("#5a2c00") },
	Red = { Top = hex("#ff8a7a"), Mid = hex("#f0383a"), Low = hex("#c41c26"), Lip = hex("#8e0c18"), Ink = hex("#4a060c") },
	Purple = { Top = hex("#e0a0ff"), Mid = hex("#a64dff"), Low = hex("#7424d8"), Lip = hex("#4e14a0"), Ink = hex("#2a0a5a") },
	Grey = { Top = hex("#d8dce8"), Mid = hex("#b8bdcc"), Low = hex("#9aa0b6"), Lip = hex("#6a7088"), Ink = hex("#2a2e3c") },
} :: { [string]: ButtonStyle }

-- the stickers on the cards' top edges (the concept's .rib classes): { top, bottom, ink }
ShopFx.Stickers = {
	Pink = { hex("#ff8ab0"), hex("#f0186a"), ShopFx.Outline },
	Gold = { hex("#fff27a"), hex("#ffb21a"), hex("#5a2c00") },
	Blue = { hex("#8ae6ff"), hex("#2a8cff"), ShopFx.Outline },
	Green = { hex("#b4ff6a"), hex("#3fd02a"), hex("#0b3a05") },
	Red = { hex("#ff8a7a"), hex("#e0262f"), hex("#4a060c") },
} :: { [string]: { Color3 } }

-- A ColorSequence through `colors`, evenly spaced (or at `times`).
function ShopFx.sequence(colors: { Color3 }, times: { number }?): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, color in colors do
		local t = if times then times[i] else (i - 1) / (#colors - 1)
		table.insert(keys, ColorSequenceKeypoint.new(t, color))
	end
	return ColorSequence.new(keys)
end

-- A paint's colours a share darker (the tabs that are not open).
function ShopFx.darker(colors: { Color3 }, share: number): { Color3 }
	local out = {}
	for _, color in colors do
		table.insert(out, color:Lerp(BLACK, share))
	end
	return out
end

---------------------------------------------------------------- faces

-- A UIGradient on `parent` through `colors` (Rotation 90: top -> bottom).
function ShopFx.gradient(parent: Instance, colors: { Color3 }, rotation: number?, name: string?): UIGradient
	return UIKit.new("UIGradient", {
		Name = name or "Paint",
		Color = ShopFx.sequence(colors),
		Rotation = rotation or 90,
	}, parent)
end

--[[
	A face's colours with the concept's dark inner band along the bottom
	(inset 0 -8px 0 rgba(0,0,0,0.22)): the paint top -> deep, then a darker
	band `lip` units of `height` tall.
]]
function ShopFx.faceSequence(colors: { Color3 }, height: number, lip: number?): ColorSequence
	local band = lip or 0
	if band <= 0 or height <= band * 2 then
		return ShopFx.sequence(colors)
	end
	local cut = 1 - band / height
	local keys = {}
	for i, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1) * (cut - 0.002), color))
	end
	local deep = colors[#colors]:Lerp(BLACK, 0.22)
	table.insert(keys, ColorSequenceKeypoint.new(cut, deep))
	table.insert(keys, ColorSequenceKeypoint.new(1, deep))
	return ColorSequence.new(keys)
end

--[[
	Paints `frame`: white background (the gradient gives the colour), round
	corners, the thick dark outline. `rotation` turns the gradient (70: the
	concept's 160deg card light from the top-left).
]]
function ShopFx.face(frame: GuiObject, colors: { Color3 }, corner: number, stroke: number?, rotation: number?): UIGradient
	frame.BackgroundColor3 = WHITE
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	UIKit.corner(frame, corner)
	if (stroke or 4) > 0 then
		UIKit.new("UIStroke", {
			Name = "Border",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = ShopFx.Outline,
			Thickness = stroke or 4,
			LineJoinMode = Enum.LineJoinMode.Round,
		}, frame)
	end
	return ShopFx.gradient(frame, colors, rotation or 90)
end

-- Repaints a face built by ShopFx.face (or a button's).
function ShopFx.repaint(frame: GuiObject, colors: { Color3 })
	local paint = frame:FindFirstChild("Paint")
	if paint and paint:IsA("UIGradient") then
		paint.Color = ShopFx.sequence(colors)
	end
end

-- The dark slab under a face (`size` and `at` its face's; `down` units lower).
function ShopFx.drop(parent: Instance, corner: number, down: number, z: number, props: Props?): Frame
	local drop = UIKit.new("Frame", {
		Name = "Drop",
		BackgroundColor3 = ShopFx.DropColor,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, down),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent)
	UIKit.corner(drop, corner)
	UIKit.new("UIStroke", {
		Name = "Border",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = ShopFx.DropColor,
		Thickness = 4,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, drop)
	apply(drop, props)
	return drop
end

-- The light half-moon over the top of a card (the concept's .gloss).
function ShopFx.gloss(parent: Instance, corner: number, z: number, share: number?): Frame
	local gloss = UIKit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(5, 4),
		Size = UDim2.new(1, -10, share or 0.38, 0),
		ZIndex = z,
	}, parent)
	UIKit.corner(gloss, math.max(4, corner - 4))
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0.97),
		}),
	}, gloss)
	return gloss
end

-- The light edge just inside a face's outline (inset 0 0 0 3px rgba(255,255,255,0.35)).
function ShopFx.rim(parent: Instance, corner: number, z: number, transparency: number?): Frame
	local rim = UIKit.new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = z,
	}, parent)
	UIKit.corner(rim, math.max(2, corner - 2))
	UIKit.new("UIStroke", {
		Name = "Light",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = WHITE,
		Thickness = 2.5,
		Transparency = transparency or 0.62,
	}, rim)
	return rim
end

---------------------------------------------------------------- text

export type TextProps = Props

--[[
	White chunky text with a dark edge (UIStroke) and a dark copy `drop`
	units under it (the concept's text-shadow). `size` is the text size; the
	edge is about a ninth of it. Returns the label; the copy is its sibling
	"<Name>Shadow" (ShopFx.setText changes both).
]]
function ShopFx.text(parent: Instance, text: string, size: number, props: Props?, ink: Color3?, drop: number?): TextLabel
	local edge = math.clamp(size / 9, 1.5, 6)
	local label = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		FontFace = ShopFx.Font,
		Size = UDim2.new(1, 0, 0, size + 6),
		Text = text,
		TextColor3 = WHITE,
		TextSize = size,
		ZIndex = 6,
	}, parent)
	UIKit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = ink or ShopFx.Outline,
		Thickness = edge,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	apply(label, props)
	local down = drop or math.clamp(math.floor(size / 9 + 0.5), 1, 6)
	if down > 0 then
		local shadow = UIKit.new("TextLabel", {
			Name = label.Name .. "Shadow",
			AnchorPoint = label.AnchorPoint,
			BackgroundTransparency = 1,
			FontFace = label.FontFace,
			Position = label.Position + UDim2.fromOffset(0, down),
			Rotation = label.Rotation,
			Size = label.Size,
			Text = label.Text,
			TextColor3 = ink or ShopFx.Outline,
			TextScaled = label.TextScaled,
			TextSize = label.TextSize,
			TextWrapped = label.TextWrapped,
			TextXAlignment = label.TextXAlignment,
			TextYAlignment = label.TextYAlignment,
			Visible = label.Visible,
			ZIndex = math.max(1, label.ZIndex - 1),
		}, parent)
		UIKit.new("UIStroke", {
			Name = "Edge",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Color = ink or ShopFx.Outline,
			Thickness = edge,
			LineJoinMode = Enum.LineJoinMode.Round,
		}, shadow)
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			limit:Clone().Parent = shadow
		end
	end
	return label
end

-- A text whose letters run through `colors` top -> bottom (the concept's gradient titles).
function ShopFx.title(
	parent: Instance,
	text: string,
	size: number,
	colors: { Color3 },
	props: Props?,
	ink: Color3?,
	drop: number?
): TextLabel
	local label = ShopFx.text(parent, text, size, props, ink, drop)
	UIKit.new("UIGradient", { Name = "Fill", Color = ShopFx.sequence(colors), Rotation = 90 }, label)
	return label
end

-- Keeps a text from growing past `max` or shrinking under `min` when it is TextScaled (and its copy).
function ShopFx.limit(label: TextLabel, max: number, min: number?)
	local targets: { TextLabel } = { label }
	local shadow = ShopFx.shadowOf(label)
	if shadow then
		table.insert(targets, shadow)
	end
	for _, target in targets do
		target.TextScaled = true
		local found = target:FindFirstChildOfClass("UITextSizeConstraint")
		local limit: UITextSizeConstraint = if found then found else UIKit.new("UITextSizeConstraint", { Name = "Fit" }, target)
		limit.MaxTextSize = max
		limit.MinTextSize = math.min(max, min or 8)
	end
end

-- The dark copy under a ShopFx.text label (nil when it has none).
function ShopFx.shadowOf(label: TextLabel): TextLabel?
	local parent = label.Parent
	local shadow = if parent then parent:FindFirstChild(label.Name .. "Shadow") else nil
	return if shadow and shadow:IsA("TextLabel") then shadow else nil
end

-- Changes a ShopFx.text label's words (and its copy's).
function ShopFx.setText(label: TextLabel, text: string)
	label.Text = text
	local shadow = ShopFx.shadowOf(label)
	if shadow then
		shadow.Text = text
	end
end

-- Shows or hides a ShopFx.text label and its copy.
function ShopFx.setVisible(label: TextLabel, visible: boolean)
	label.Visible = visible
	local shadow = ShopFx.shadowOf(label)
	if shadow then
		shadow.Visible = visible
	end
end

-- Moves a ShopFx.text label (and its copy, `down` units under it).
function ShopFx.place(label: TextLabel, at: UDim2, size: UDim2?)
	local shadow = ShopFx.shadowOf(label)
	local down = if shadow then shadow.Position.Y.Offset - label.Position.Y.Offset else 0
	label.Position = at
	if size then
		label.Size = size
	end
	if shadow then
		shadow.Position = at + UDim2.fromOffset(0, down)
		shadow.Size = label.Size
	end
end

-- How wide a word is in Fredoka One at `size` (design units, an estimate).
function ShopFx.textWidth(text: string, size: number): number
	return math.ceil((utf8.len(text) or #text) * size * 0.56 + size * 0.3)
end

---------------------------------------------------------------- light

-- A random number source in [0, 1) from a seed (the concept's: the same picture every time).
function ShopFx.random(seed: number): () -> number
	local s = math.max(1, math.floor(seed) % 2147483647)
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

--[[
	Light rays from `center` (in the parent): `count` bars through the
	middle, faded at both ends and a little at the centre, `length` from the
	centre to a tip. Rainbow rays when `colors` has several colours. A
	holder the motion turns (ShopFx "Rays"). The parent should clip.
]]
function ShopFx.rays(
	parent: Instance,
	center: UDim2,
	count: number,
	length: number,
	transparency: number,
	z: number,
	colors: { Color3 }?
): Frame
	local holder = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = center,
		Size = UDim2.fromOffset(length * 2, length * 2),
		ZIndex = z,
	}, parent)
	holder:SetAttribute("ShopFx", "Rays")
	local fade = math.clamp(transparency, 0, 1)
	local middle = math.min(1, fade + (1 - fade) * 0.35)
	local width = math.max(6, math.floor(length * 0.2))
	for i = 1, count do
		local color = if colors and #colors > 0 then colors[(i - 1) % #colors + 1] else WHITE
		local ray = UIKit.new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * (180 / count),
			Size = UDim2.fromOffset(length * 2, width),
			ZIndex = z,
		}, holder)
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.16, math.min(1, fade + (1 - fade) * 0.6)),
				NumberSequenceKeypoint.new(0.4, fade),
				NumberSequenceKeypoint.new(0.5, middle),
				NumberSequenceKeypoint.new(0.6, fade),
				NumberSequenceKeypoint.new(0.84, math.min(1, fade + (1 - fade) * 0.6)),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
	end
	return holder
end

-- A soft glow: three discs fading out from the middle (the concept's .glowdisc).
function ShopFx.glow(parent: Instance, center: UDim2, radius: number, color: Color3, z: number, strength: number?): Frame
	local holder = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = center,
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		ZIndex = z,
	}, parent)
	local s = math.clamp(strength or 1, 0, 1)
	for i, k in { 1, 0.68, 0.38 } do
		local disc = UIKit.new("Frame", {
			Name = "Disc" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BackgroundTransparency = 1 - (0.16 + 0.1 * i) * s,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k),
			ZIndex = z,
		}, holder)
		UIKit.corner(disc, 999)
	end
	return holder
end

--[[
	The jagged line of a bolt from `a` to `b` (the concept's midpoint
	displacement): 2^depth segments, each middle point pushed up to `disp`
	/ 2 sideways (halved every level). Pure: the same `rand` gives the same bolt.
]]
function ShopFx.boltPoints(a: Vector2, b: Vector2, disp: number, depth: number, rand: () -> number): { Vector2 }
	if depth <= 0 then
		return { a, b }
	end
	local mid = (a + b) / 2 + Vector2.new((rand() - 0.5) * disp, (rand() - 0.5) * disp)
	local left = ShopFx.boltPoints(a, mid, disp / 2, depth - 1, rand)
	local right = ShopFx.boltPoints(mid, b, disp / 2, depth - 1, rand)
	for i = 2, #right do
		table.insert(left, right[i])
	end
	return left
end

-- One segment of a bolt: a white core with a coloured edge, round ends.
local function segment(parent: Instance, p: Vector2, q: Vector2, width: number, color: Color3, z: number, glow: boolean)
	local d = q - p
	local length = d.Magnitude
	if length < 0.5 then
		return
	end
	local mid = (p + q) / 2
	local angle = math.deg(math.atan2(d.Y, d.X))
	if glow then
		local haze = UIKit.new("Frame", {
			Name = "Haze",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(mid.X, mid.Y),
			Rotation = angle,
			Size = UDim2.fromOffset(length + width * 3, width * 3.2),
			ZIndex = z,
		}, parent)
		UIKit.corner(haze, 999)
	end
	local core = UIKit.new("Frame", {
		Name = "Seg",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(mid.X, mid.Y),
		Rotation = angle,
		Size = UDim2.fromOffset(length + width * 0.6, math.max(1.5, width * 0.45)),
		ZIndex = z,
	}, parent)
	UIKit.corner(core, 999)
	UIKit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = math.max(1, width * 0.45),
		LineJoinMode = Enum.LineJoinMode.Round,
	}, core)
end

--[[
	A lightning bolt from `a` to `b` (in the parent's units): the main
	jagged line (2^depth segments, glowing unless `haze` is false),
	`branches` short forks, `width` units thick. A holder over the whole
	parent that the motion flashes (ShopFx "Bolt", attribute Phase: when in
	the second it flashes). A segment is 3 to 5 instances: the long bolts
	behind the window take depth 4, the ones on cards 3 and no haze.
]]
function ShopFx.bolt(
	parent: Instance,
	a: Vector2,
	b: Vector2,
	color: Color3,
	width: number,
	seed: number,
	branches: number,
	z: number,
	phase: number?,
	depth: number?,
	haze: boolean?
): Frame
	local holder = UIKit.new("Frame", {
		Name = "Bolt",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent)
	holder:SetAttribute("ShopFx", "Bolt")
	holder:SetAttribute("Phase", phase or 0)
	local rand = ShopFx.random(seed)
	local length = (b - a).Magnitude
	local points = ShopFx.boltPoints(a, b, length * 0.42, depth or 4, rand)
	for i = 1, #points - 1 do
		segment(holder, points[i], points[i + 1], width, color, z, haze ~= false)
	end
	local dir = math.atan2(b.Y - a.Y, b.X - a.X)
	for _ = 1, branches do
		local k = math.clamp(math.floor(#points * (0.2 + rand() * 0.6)), 1, #points)
		local from = points[k]
		local angle = dir + (if rand() < 0.5 then -1 else 1) * (0.5 + rand() * 0.6)
		local reach = length * (0.18 + rand() * 0.22)
		local to = from + Vector2.new(math.cos(angle), math.sin(angle)) * reach
		local fork = ShopFx.boltPoints(from, to, reach * 0.4, 2, rand)
		for i = 1, #fork - 1 do
			segment(holder, fork[i], fork[i + 1], width * 0.55, color, z, false)
		end
	end
	return holder
end

-- Recolours a bolt (a tab's other world).
function ShopFx.tintBolt(holder: Instance, color: Color3)
	for _, part in holder:GetChildren() do
		if part.Name == "Haze" and part:IsA("Frame") then
			part.BackgroundColor3 = color
		elseif part.Name == "Seg" then
			local edge = part:FindFirstChild("Edge")
			if edge and edge:IsA("UIStroke") then
				edge.Color = color
			end
		end
	end
end

--[[
	A four-point sparkle at `at` (`size` across): two bars that fade to sharp
	tips, a bright middle and a soft glow. Its UIScale pulses (ShopFx
	"Sparkle", attribute Phase).
]]
function ShopFx.sparkle(parent: Instance, at: UDim2, size: number, color: Color3, z: number, phase: number?): Frame
	local holder = UIKit.new("Frame", {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = at,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	}, parent)
	holder:SetAttribute("ShopFx", "Sparkle")
	holder:SetAttribute("Phase", phase or 0)
	UIKit.new("UIScale", { Name = "Pulse", Scale = 1 }, holder)
	local halo = UIKit.new("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		ZIndex = z,
	}, holder)
	UIKit.corner(halo, 999)
	for i, rot in { 0, 90 } do
		local bar = UIKit.new("Frame", {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = rot,
			Size = UDim2.new(1, 0, 0.16, 0),
			ZIndex = z,
		}, holder)
		UIKit.corner(bar, 999)
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.35),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.65, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, bar)
	end
	local core = UIKit.new("Frame", {
		Name = "Core",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.18, 0.18),
		ZIndex = z,
	}, holder)
	UIKit.corner(core, 999)
	return holder
end

-- `count` small dots scattered over a w x h area (the concept's particles).
function ShopFx.dots(
	parent: Instance,
	count: number,
	w: number,
	h: number,
	colors: { Color3 },
	seed: number,
	z: number,
	max: number?
): Frame
	local holder = UIKit.new("Frame", {
		Name = "Dots",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent)
	local rand = ShopFx.random(seed)
	for i = 1, count do
		local size = 2 + math.floor(rand() * (max or 5))
		local dot = UIKit.new("Frame", {
			Name = "Dot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = colors[(i - 1) % #colors + 1],
			BackgroundTransparency = 0.25 + rand() * 0.5,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(math.floor(rand() * w), math.floor(rand() * h)),
			Size = UDim2.fromOffset(size, size),
			ZIndex = z,
		}, holder)
		UIKit.corner(dot, 999)
	end
	return holder
end

--[[
	Classic Roblox top studs over a w x h face (the Studs UI pack look): a
	grid of round frames `spacing` apart, each lit top-left and shaded
	bottom-right. Only for the header band and the tabs: a few hundred
	frames, never the cards.
]]
function ShopFx.studs(parent: Instance, w: number, h: number, spacing: number, transparency: number, z: number): Frame
	local holder = UIKit.new("Frame", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent)
	local d = math.floor(spacing * 0.62)
	local cols = math.max(1, math.floor(w / spacing))
	local rows = math.max(1, math.floor(h / spacing))
	local x0 = (w - (cols - 1) * spacing) / 2
	local y0 = (h - (rows - 1) * spacing) / 2
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local stud = UIKit.new("Frame", {
				Name = "Stud",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = transparency,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(math.floor(x0 + c * spacing), math.floor(y0 + r * spacing)),
				Size = UDim2.fromOffset(d, d),
				ZIndex = z,
			}, holder)
			UIKit.corner(stud, 999)
			UIKit.new("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, WHITE),
					ColorSequenceKeypoint.new(0.5, WHITE),
					ColorSequenceKeypoint.new(1, BLACK),
				}),
				Rotation = 45,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.45, 0.6),
					NumberSequenceKeypoint.new(1, 0.15),
				}),
			}, stud)
		end
	end
	return holder
end

-- Two broad light diagonal stripes across a band (the concept's header .shards).
function ShopFx.shards(parent: Instance, z: number)
	for i, s in { { 0.3, 72 }, { 0.7, 37 } } do
		UIKit.new("Frame", {
			Name = "Shard" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.84,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(s[1], 0.5),
			Rotation = 28,
			Size = UDim2.new(0, s[2], 2.4, 0),
			ZIndex = z,
		}, parent)
	end
end

---------------------------------------------------------------- buttons, stickers, chips

ShopFx.ButtonCorner = 13
ShopFx.ButtonDrop = 5

export type PriceButton = {
	Holder: Frame, -- the caller places it
	Face: TextButton, -- the clickable face
	Amount: TextLabel, -- the price
	Label: TextLabel?, -- the small line over a two-line button's price ("3 Golems")
}

--[[
	The 3D Robux button: a dark slab under it, the style's gradient with a
	darker lip, a light line along its top, a shine the motion sweeps across
	(ShopFx "Shine"), the robux mark and the price in white with a dark edge
	in the style's ink. `label` makes it two lines (a small word over the
	price). `robux` nil shows `text` instead (OWNED).
]]
-- The 3D button's face (a TextButton, or a Frame for a tag that is no button): its paint,
-- the light line, the shine (shine false: none), the small line and the price. Returns the amount and the line.
local function dressButton(
	face: GuiObject,
	robux: number?,
	size: Vector2,
	style: string,
	z: number,
	label: string?,
	text: string?,
	shines: boolean
): (TextLabel, TextLabel?)
	local s = ShopFx.Buttons[style] or ShopFx.Buttons.Green
	ShopFx.face(face, { s.Top, s.Mid, s.Low }, ShopFx.ButtonCorner, 4)
	local paint = face:FindFirstChild("Paint") :: UIGradient
	paint.Color = ShopFx.faceSequence({ s.Top, s.Mid, s.Low }, size.Y, math.max(4, math.floor(size.Y * 0.11)))
	face:SetAttribute("Style", style)
	-- the light line along the top (inset 0 3px 0 rgba(255,255,255,0.6))
	local top = UIKit.new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -16, 0, 3),
		ZIndex = z + 1,
	}, face)
	UIKit.corner(top, 999)
	if shines then
		-- the shine: a tilted light band the motion slides across
		local shine = UIKit.new("Frame", {
			Name = "Shine",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 1,
		}, face)
		UIKit.corner(shine, ShopFx.ButtonCorner)
		local sweep = UIKit.new("UIGradient", {
			Name = "Sweep",
			Rotation = 18,
			Offset = Vector2.new(ShopFx.shineOffset(0), 0),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0.3),
				NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, shine)
		sweep:SetAttribute("ShopFx", "Shine")
	end
	local lip = math.max(4, math.floor(size.Y * 0.11))
	local small: TextLabel? = nil
	local rowTop = 0
	if label then
		local smallSize = math.floor(size.Y * 0.27)
		small = ShopFx.text(face, label, smallSize, {
			Name = "Label",
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.new(1, -8, 0, smallSize + 4),
			ZIndex = z + 3,
		}, s.Ink, 1)
		rowTop = smallSize + 2
	end
	local row = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, rowTop),
		Size = UDim2.new(1, 0, 1, -(lip + rowTop)),
		ZIndex = z + 3,
	}, face)
	UIKit.list(row, Enum.FillDirection.Horizontal, 4, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local textSize = math.floor(math.min((size.Y - lip - rowTop) * 0.74, 40))
	local mark = UIKit.new("ImageLabel", {
		Name = "Mark",
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(math.floor(textSize * 0.95), math.floor(textSize * 0.95)),
		ZIndex = z + 3,
	}, row)
	IconAssets.apply(mark, "robux")
	mark:SetAttribute("Icon", "robux")
	local words = if robux then ShopFx.robuxText(robux) else (text or "")
	local amount = ShopFx.text(row, words, textSize, {
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(ShopFx.textWidth(words, textSize), textSize + 4),
		ZIndex = z + 3,
	}, s.Ink, 0)
	mark.Visible = robux ~= nil
	return amount, small
end

function ShopFx.priceButton(
	parent: Instance,
	robux: number?,
	size: Vector2,
	style: string,
	props: Props?,
	label: string?,
	text: string?
): PriceButton
	local holder = UIKit.new("Frame", {
		Name = "Price",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 6,
	}, parent)
	apply(holder, props)
	local z = holder.ZIndex
	ShopFx.drop(holder, ShopFx.ButtonCorner, ShopFx.ButtonDrop, z)
	local face = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Selectable = true,
		ZIndex = z + 1,
	}, holder)
	local amount, small = dressButton(face, robux, size, style, z, label, text, true)
	return { Holder = holder, Face = face, Amount = amount, Label = small }
end

-- A tag drawn like a buy button that is no button ("OWNED"): the same face, no shine. Returns its holder.
function ShopFx.buttonTag(parent: Instance, text: string, size: Vector2, style: string, props: Props?): Frame
	local holder = UIKit.new("Frame", {
		Name = "Tag",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 6,
	}, parent)
	apply(holder, props)
	local z = holder.ZIndex
	ShopFx.drop(holder, ShopFx.ButtonCorner, ShopFx.ButtonDrop, z)
	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
	}, holder)
	dressButton(face, nil, size, style, z, nil, text, false)
	return holder
end

-- "1,499" (the price on a button).
function ShopFx.robuxText(robux: number): string
	local n = math.floor(robux)
	local text = tostring(n)
	while true do
		local swapped, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = swapped
		if count == 0 then
			break
		end
	end
	return text
end

-- Sets a price button's amount (nil: `text` without the mark).
function ShopFx.setPrice(face: Instance, robux: number?, text: string?)
	local row = face:FindFirstChild("Row")
	if not row then
		return
	end
	local mark = row:FindFirstChild("Mark")
	local amount = row:FindFirstChild("Amount")
	local words = if robux then ShopFx.robuxText(robux) else (text or "")
	if mark and mark:IsA("GuiObject") then
		mark.Visible = robux ~= nil
	end
	if amount and amount:IsA("TextLabel") then
		amount.Text = words
		amount.Size = UDim2.fromOffset(ShopFx.textWidth(words, amount.TextSize), amount.Size.Y.Offset)
	end
end

-- Repaints a price button's face in another style (a locked STAR blaster: grey).
function ShopFx.setStyle(face: GuiObject, style: string)
	if face:GetAttribute("Style") == style then
		return
	end
	local s = ShopFx.Buttons[style] or ShopFx.Buttons.Green
	face:SetAttribute("Style", style)
	local paint = face:FindFirstChild("Paint")
	if paint and paint:IsA("UIGradient") then
		local holder = face.Parent
		local h = if holder and holder:IsA("GuiObject") then holder.Size.Y.Offset else 0
		h = if h > 0 then h else 50
		paint.Color = ShopFx.faceSequence({ s.Top, s.Mid, s.Low }, h, math.max(4, math.floor(h * 0.11)))
	end
	for _, d in face:GetDescendants() do
		if d:IsA("UIStroke") and d.Name == "Edge" then
			d.Color = s.Ink
		end
	end
end

--[[
	A sticker on a card's top edge ("BEST VALUE!", the concept's .rib): a
	tilted pill in `style` with a dark slab under it, the words in white
	with a dark edge. `at` is its middle. Returns the holder.
]]
function ShopFx.sticker(parent: Instance, text: string, style: string, at: UDim2, size: number, rotation: number?, z: number?): Frame
	local s = ShopFx.Stickers[style] or ShopFx.Stickers.Pink
	local w = ShopFx.textWidth(text, size) + math.floor(size * 1.1)
	local h = math.floor(size * 1.55)
	local holder = UIKit.new("Frame", {
		Name = "Sticker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = at,
		Rotation = rotation or -4,
		Size = UDim2.fromOffset(w, h),
		ZIndex = z or 12,
	}, parent)
	local zz = holder.ZIndex
	ShopFx.drop(holder, math.floor(h * 0.42), 4, zz)
	local face = UIKit.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		ZIndex = zz + 1,
	}, holder)
	ShopFx.face(face, { s[1], s[2] }, math.floor(h * 0.42), 3)
	ShopFx.text(face, text, size, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		ZIndex = zz + 3,
	}, s[3], 1)
	return holder
end

-- A dark label pill ("5 min of income", "ENDS NOV 30"): `w` x `h`, the text `size`.
function ShopFx.chip(parent: Instance, text: string, w: number, h: number, size: number, props: Props?, colors: { Color3 }?): Frame
	local chip = UIKit.new("Frame", {
		Name = "Chip",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(w, h),
		ZIndex = 8,
	}, parent)
	apply(chip, props)
	ShopFx.face(chip, colors or { hex("#2c1a5c"), hex("#140a30") }, math.floor(h * 0.4), 3)
	if not colors then
		chip.BackgroundTransparency = 0.18
	end
	ShopFx.text(chip, text, size, {
		Name = "Label",
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		ZIndex = chip.ZIndex + 2,
	}, nil, 1)
	return chip
end

-- The label inside a ShopFx.chip.
function ShopFx.chipLabel(chip: Instance): TextLabel?
	local label = chip:FindFirstChild("Label")
	return if label and label:IsA("TextLabel") then label else nil
end

--[[
	A rainbow outline that runs round a face (the concept's Mythic frame): the
	face's dark outline turns into the rainbow; the motion turns its
	gradient (ShopFx "Rim").
]]
function ShopFx.mythicRim(face: GuiObject, thickness: number?)
	local border = face:FindFirstChild("Border")
	local stroke: UIStroke = if border and border:IsA("UIStroke")
		then border
		else UIKit.new("UIStroke", { Name = "Border", ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, face)
	stroke.Color = WHITE
	stroke.Thickness = thickness or 5
	local rainbow = UIKit.new("UIGradient", {
		Name = "Rainbow",
		Color = ShopFx.sequence(ShopFx.RainbowRim),
		Rotation = 30,
	}, stroke)
	rainbow:SetAttribute("ShopFx", "Rim")
end

---------------------------------------------------------------- pictures

--[[
	A picture from the shop icon sheet (IconAssets.Shop: the concept's own
	sticker icons) `size` square, or nil when it won't show (the sheet isn't
	uploaded yet: the callers fall back to a live 3D model, a drawn picture
	or the words).
]]
function ShopFx.icon(parent: Instance, name: string, size: number, props: Props?): ImageLabel?
	if not IconAssets.shopShows(name) then
		return nil
	end
	local image = UIKit.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 7,
	}, parent)
	IconAssets.applyShop(image, name)
	apply(image, props)
	return image
end

--[[
	A spin wheel drawn from frames (the Wheel Spins card before the icon
	sheet is uploaded): eight coloured petals round a hub, a dark ring and the
	red pointer on top. `size` across.
]]
function ShopFx.wheel(parent: Instance, size: number, props: Props?): Frame
	local holder = UIKit.new("Frame", {
		Name = "Wheel",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 7,
	}, parent)
	apply(holder, props)
	local z = holder.ZIndex
	local r = size / 2
	local base = UIKit.new("Frame", {
		Name = "Base",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, holder)
	UIKit.corner(base, 999)
	UIKit.new("UIStroke", { Name = "Border", Color = ShopFx.Outline, Thickness = math.max(3, size * 0.05) }, base)
	-- four bars through the hub (a Roblox frame turns about its own middle), each two colours:
	-- eight coloured spokes with white wedges between them
	local colors =
		{ hex("#ff4f7a"), hex("#ffa53a"), hex("#ffe84a"), hex("#5ff07a"), hex("#4ac8ff"), hex("#7a6aff"), hex("#c86aff"), hex("#ff6ad8") }
	for i = 1, 4 do
		local bar = UIKit.new("Frame", {
			Name = "Spoke" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * 45 + 22.5,
			Size = UDim2.fromOffset(math.floor(r * 0.78), math.floor(r * 1.86)),
			ZIndex = z + 1,
		}, base)
		UIKit.corner(bar, math.floor(r * 0.2))
		UIKit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, colors[i]),
				ColorSequenceKeypoint.new(0.499, colors[i]),
				ColorSequenceKeypoint.new(0.501, colors[i + 4]),
				ColorSequenceKeypoint.new(1, colors[i + 4]),
			}),
			Rotation = 90,
		}, bar)
	end
	-- (the petals' turned corners would poke out: a white ring over the edge holds them in)
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.94),
		ZIndex = z + 2,
	}, holder)
	UIKit.corner(ring, 999)
	UIKit.new("UIStroke", { Name = "Edge", Color = WHITE, Thickness = math.max(3, size * 0.06) }, ring)
	local hub = UIKit.new("Frame", {
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = hex("#ffe05a"),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.22, 0.22),
		ZIndex = z + 3,
	}, holder)
	UIKit.corner(hub, 999)
	UIKit.new("UIStroke", { Name = "Border", Color = ShopFx.Outline, Thickness = math.max(2, size * 0.035) }, hub)
	local pointer = UIKit.new("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = hex("#ff4a4a"),
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, math.floor(size * 0.02)),
		Rotation = 45,
		Size = UDim2.fromOffset(math.floor(size * 0.16), math.floor(size * 0.16)),
		ZIndex = z + 3,
	}, holder)
	UIKit.corner(pointer, 3)
	UIKit.new("UIStroke", { Name = "Border", Color = ShopFx.Outline, Thickness = math.max(2, size * 0.03) }, pointer)
	return holder
end

-- The red "x2" badge (the 2x Money pass), `size` wide.
function ShopFx.x2(parent: Instance, size: number, props: Props?): Frame
	local badge = UIKit.new("Frame", {
		Name = "X2",
		Rotation = 8,
		Size = UDim2.fromOffset(size, math.floor(size * 0.66)),
		ZIndex = 9,
	}, parent)
	apply(badge, props)
	ShopFx.face(badge, { hex("#ff6262"), hex("#cf2a3a") }, math.floor(size * 0.12), 3)
	ShopFx.text(badge, "x2", math.floor(size * 0.46), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		ZIndex = badge.ZIndex + 2,
	}, nil, 1)
	return badge
end

---------------------------------------------------------------- motion (pure timing)

ShopFx.Loop = 2 -- seconds: the concept's loop
ShopFx.RaySpeed = 20 -- degrees a second (the rays repeat every 20 degrees in the concept)
ShopFx.StepRate = 1 / 30

-- The rays' turn at `t` seconds (from `base`).
function ShopFx.rayAngle(t: number, base: number?): number
	return ((base or 0) + t * ShopFx.RaySpeed) % 360
end

-- Is a bolt with `phase` lit at `t`? Two quick flashes a second (the concept's frame(t)).
function ShopFx.boltOn(t: number, phase: number?): boolean
	local p = (t + (phase or 0)) % 1
	return p < 0.09 or (p > 0.15 and p < 0.22)
end

-- The shine's UIGradient offset at `t`: from left of the button to right of it once every Loop
-- (it crosses the face in about 0.85 s, then rests off it).
function ShopFx.shineOffset(t: number): number
	local u = (t % ShopFx.Loop) / ShopFx.Loop
	return -1.1 + 2.8 * u
end

-- The open tab's bob at `t` (design units, up and down 3).
function ShopFx.bob(t: number): number
	return math.sin(t * math.pi) * 3
end

-- The Mythic rim's gradient turn at `t` (a full turn every 2 s).
function ShopFx.rimAngle(t: number): number
	return (30 + t * 180) % 360
end

-- A sparkle's size at `t` (0.45 .. 1).
function ShopFx.sparkleScale(t: number, phase: number?): number
	return 0.45 + 0.55 * math.abs(math.sin(t * math.pi + (phase or 0) * 1.3))
end

---------------------------------------------------------------- motion (the driver)

export type Driver = {
	focus: (page: Instance?, bob: GuiObject?) -> (),
	stop: () -> (),
	step: (t: number) -> (), -- (tests and previews: one frame at t)
	running: () -> boolean,
}

type Lists = {
	Rays: { GuiObject },
	RayBase: { [GuiObject]: number },
	Bolts: { GuiObject },
	BoltPhase: { [GuiObject]: number },
	Shines: { UIGradient },
	Rims: { UIGradient },
	Sparkles: { GuiObject },
	SparklePhase: { [GuiObject]: number },
}

local function emptyLists(): Lists
	return { Rays = {}, RayBase = {}, Bolts = {}, BoltPhase = {}, Shines = {}, Rims = {}, Sparkles = {}, SparklePhase = {} }
end

local function collect(roots: { Instance }): Lists
	local lists = emptyLists()
	for _, root in roots do
		for _, d in root:GetDescendants() do
			local kind = d:GetAttribute("ShopFx")
			if kind == nil then
				continue
			end
			if kind == "Rays" and d:IsA("GuiObject") then
				table.insert(lists.Rays, d)
				lists.RayBase[d] = d.Rotation
			elseif kind == "Bolt" and d:IsA("GuiObject") then
				table.insert(lists.Bolts, d)
				local phase = d:GetAttribute("Phase")
				lists.BoltPhase[d] = if type(phase) == "number" then phase else 0
			elseif kind == "Shine" and d:IsA("UIGradient") then
				table.insert(lists.Shines, d)
			elseif kind == "Rim" and d:IsA("UIGradient") then
				table.insert(lists.Rims, d)
			elseif kind == "Sparkle" and d:IsA("GuiObject") then
				table.insert(lists.Sparkles, d)
				local phase = d:GetAttribute("Phase")
				lists.SparklePhase[d] = if type(phase) == "number" then phase else 0
			end
		end
	end
	return lists
end

local function stepLists(lists: Lists, t: number)
	for _, ray in lists.Rays do
		ray.Rotation = ShopFx.rayAngle(t, lists.RayBase[ray])
	end
	for _, bolt in lists.Bolts do
		local on = ShopFx.boltOn(t, lists.BoltPhase[bolt])
		if bolt.Visible ~= on then
			bolt.Visible = on
		end
	end
	if #lists.Shines > 0 then
		local offset = Vector2.new(ShopFx.shineOffset(t), 0)
		for _, shine in lists.Shines do
			shine.Offset = offset
		end
	end
	if #lists.Rims > 0 then
		local angle = ShopFx.rimAngle(t)
		for _, rim in lists.Rims do
			rim.Rotation = angle
		end
	end
	for _, sparkle in lists.Sparkles do
		local phase = lists.SparklePhase[sparkle]
		local pulse = sparkle:FindFirstChild("Pulse")
		if pulse and pulse:IsA("UIScale") then
			pulse.Scale = ShopFx.sparkleScale(t, phase)
		end
		sparkle.Rotation = (t * 45 + phase * 30) % 360
	end
end

-- Puts everything a driver moved back at rest (bolts lit, shines off the buttons).
local function rest(lists: Lists)
	for _, bolt in lists.Bolts do
		bolt.Visible = true
	end
	local off = Vector2.new(ShopFx.shineOffset(0), 0)
	for _, shine in lists.Shines do
		shine.Offset = off
	end
	for _, sparkle in lists.Sparkles do
		local pulse = sparkle:FindFirstChild("Pulse")
		if pulse and pulse:IsA("UIScale") then
			pulse.Scale = 1
		end
	end
end

--[[
	Starts the shop's motion: everything marked under `fixed` (the window's
	own effects) and under `page` (the open tab's cards), and the open tab
	`bob`. `quiet()` true (Reduce motion) puts it at rest and ends it.
	One Heartbeat connection, 30 steps a second; stop() disconnects it.
]]
function ShopFx.start(fixed: { Instance }, page: Instance?, bob: GuiObject?, quiet: (() -> boolean)?): Driver
	local base = collect(fixed)
	local current = collect(if page then { page } else {})
	local bobbing: GuiObject? = bob
	local bobAt: UDim2? = if bob then bob.Position else nil
	local connection: RBXScriptConnection? = nil
	local started = os.clock()
	local acc = 0

	local function step(t: number)
		stepLists(base, t)
		stepLists(current, t)
		local b = bobbing
		if b and bobAt then
			b.Position = bobAt + UDim2.fromOffset(0, math.floor(ShopFx.bob(t) + 0.5)) -- (offsets are whole units)
		end
	end

	local function stop()
		local c = connection
		connection = nil
		if c then
			c:Disconnect()
		end
		rest(base)
		rest(current)
		local b = bobbing
		if b and bobAt then
			b.Position = bobAt
		end
	end

	local function focus(newPage: Instance?, newBob: GuiObject?)
		rest(current)
		local b = bobbing
		if b and bobAt then
			b.Position = bobAt
		end
		current = collect(if newPage then { newPage } else {})
		bobbing = newBob
		bobAt = if newBob then newBob.Position else nil
	end

	local ok = pcall(function()
		local RunService = game:GetService("RunService")
		connection = RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			if acc < ShopFx.StepRate then
				return
			end
			acc = 0
			if quiet and quiet() then
				stop()
				return
			end
			step(os.clock() - started)
		end)
	end)
	if not ok then
		connection = nil
	end

	return {
		focus = focus,
		stop = stop,
		step = step,
		running = function(): boolean
			return connection ~= nil
		end,
	}
end

return ShopFx
