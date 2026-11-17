--[[
	ShopFx: the shop v3 "WOW" look (owner 2026-11-11, the concept
	docs/art/shop_v3_concept/shop_wow.html), made smooth and light the same
	evening (owner: "cool and smooth, with cool animations, not laggy"):

	  Themes      one colour world per tab (header band, body, glow, bolts)
	  Cards       the card paints (light -> mid -> deep, the concept's c-*)
	  face        a painted face: gradient, round corners, the thick dark outline
	  drop        the dark slab under a face (the "lip" the concept draws 6-8 px down)
	  gloss / rim the light half-moon over a card's top, the light edge inside its outline
	  text        white chunky text (Fredoka One) with a dark edge (a dark copy under the big ones)
	  priceButton the 3D Robux button (green / gold / red / purple / grey), a shine sweeps it
	  sticker     "BEST VALUE!" on a card's top edge; chip: a dark label pill
	  mythicRim   a rainbow outline that runs round a Mythic card
	  icon        a picture from the shop icon sheet (IconAssets.Shop)
	  stickerPicture a golem's, an egg's or a pass item's drawn sticker (IconAssets.StickerSheets)
	  wheel / x2  a spin wheel and the "x2" badge drawn from frames

	Effects are ONE ImageLabel each, cut from the effects picture
	(IconAssets.ShopFx: sunburst rays, glow, sparkle, flame, a patch of
	studs, three bolts), tinted with ImageColor3. Until that picture is
	uploaded: plain gradients (no rays, no studs), one soft disc for a glow,
	and the icon sheet's bolt and sparkle. (Its drifting dots are not used
	since the owner's look in Studio, 2026-11-12: "take the dotted square
	away".)

	Motion: TweenService only, the engine moves everything every frame; no
	Lua runs per frame. Things carry the attribute ShopFx (a mark):
	  Rays     the sunburst turns (Rotation, linear, endless)
	  Shine    a buy button's light band sweeps across (UIGradient Offset)
	  Rim      the Mythic rainbow outline runs (UIGradient Rotation; a Mythic
	           tile's rarity word too)
	  Bolt     a lightning bolt flashes now and then (ImageTransparency)
	  Sparkle  a sparkle twinkles (its UIScale "Pulse")
	  Pulse    a BEST VALUE button breathes (its UIScale "Pulse")
	  Float    a tab's hero picture floats up and down (Position); with the
	           attribute Swing it rocks as it floats (Rotation, the same
	           tween), with Wobble it wobbles now and then like an egg about
	           to hatch (Rotation, Elastic: still most of the time)
	  Bob      the open tab bobs (its Lift's Position)
	  Idle     a golem's or an egg's picture bobs and rocks (Position and
	           Rotation in one tween; each one on a page a little slower than
	           the one before, half of them the other way round: never in step)
	  Glow     a glow breathes (its transparency)
	  Wiggle   a sticker, a badge, a count or the open tab's icon rocks
	           gently about its tilt (Rotation)
	  Sheen    a card's diagonal gloss band (UIGradient Offset): the cards of
	           a page one after another, in the same order every round
	  Glint    the SHOP title's light band (UIGradient Offset)
	  Rise     a theme particle drifts along its Path and fades in and out
	           (Position, linear and repeating, and ImageTransparency: the
	           jump back happens while it is invisible)
	loopsUnder(roots) reads the marks into Loop specs (none under a hidden
	gui; a phone skips the Ambient ones), play(loops) starts one endless
	tween each, stop(playing) cancels them and puts everything at rest;
	sample(loop, t) is the same curve in Lua (the previews' video and the
	tests). open / close / fadeOut / recolor / slideIn / popIn / bindPress
	are the window's one-shot tweens (open pop with a ray burst, close shrink,
	a tab's colours fading over, its page sliding in, its cards popping in
	one after another, hover 1.04 and press 0.94; a card also rises and its
	light edge brightens); cascade (the title drops in, the tabs pop in one
	after another, the X spins in), popIcon (the picked tab's icon) and
	celebrate (a bought card flashes and pops, stars fly out of it) too.
	Reduce motion: nothing plays (ShopFx.quiet), the static look stays.

	Pure builders (only Instance creation): the Lune previews run them too.
	No emoji anywhere.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local IconAssets = require(Shared.Config.IconAssets)
local AnimConfig = require(Shared.Config.AnimConfig)
local UIKit = require(script.Parent.UIKit)
local Motion = require(script.Parent.Motion)

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

-- The dark slab under a face, `down` units lower (as wide as the face with its 4-unit outline).
function ShopFx.drop(parent: Instance, corner: number, down: number, z: number, props: Props?): Frame
	local drop = UIKit.new("Frame", {
		Name = "Drop",
		BackgroundColor3 = ShopFx.DropColor,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-4, down - 4),
		Size = UDim2.new(1, 8, 1, 8),
		ZIndex = z,
	}, parent)
	UIKit.corner(drop, corner + 4)
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
	White chunky text with a dark edge (UIStroke) and, from ShadowMin up, a
	dark copy `drop` units under it (the concept's text-shadow; small words
	keep only their edge: fewer instances). `size` is the text size; the
	edge is about a ninth of it. Returns the label; the copy is its sibling
	"<Name>Shadow" (ShopFx.setText changes both).
]]
ShopFx.ShadowMin = 20
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
	if down > 0 and size >= ShopFx.ShadowMin then
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

---------------------------------------------------------------- light (one sprite each)

-- A random number source in [0, 1) from a seed (the concept's: the same picture every time).
function ShopFx.random(seed: number): () -> number
	local s = math.max(1, math.floor(seed) % 2147483647)
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

-- An effect sprite (IconAssets.ShopFx: white, tinted with ImageColor3), nil until the picture shows.
function ShopFx.sprite(parent: Instance, name: string, props: Props?): ImageLabel?
	if not IconAssets.shopFxShows(name) then
		return nil
	end
	local image = UIKit.new("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 2,
	}, parent)
	IconAssets.applyShopFx(image, name)
	apply(image, props)
	return image
end

--[[
	The sunburst behind a picture (`size` across, its middle at `center`; the
	parent clips), tinted `color`; it turns (mark "Rays", one turn in
	`period` seconds). Nil before the effects picture is uploaded: no
	wedges, the plain paint stays.
]]
function ShopFx.rays(
	parent: Instance,
	center: UDim2,
	size: number,
	transparency: number,
	z: number,
	color: Color3?,
	period: number?
): ImageLabel?
	local rays = ShopFx.sprite(parent, "rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = color or WHITE,
		ImageTransparency = transparency,
		Position = center,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	})
	if rays then
		rays:SetAttribute("ShopFx", "Rays")
		rays:SetAttribute("Period", period or 24)
	end
	return rays
end

-- A soft glow `radius` round (the glow sprite; before the upload one soft disc).
function ShopFx.glow(parent: Instance, center: UDim2, radius: number, color: Color3, z: number, strength: number?): GuiObject
	local s = math.clamp(strength or 1, 0, 1)
	local sprite = ShopFx.sprite(parent, "glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = color,
		ImageTransparency = 1 - 0.85 * s,
		Position = center,
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		ZIndex = z,
	})
	if sprite then
		return sprite
	end
	local disc = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - 0.32 * s,
		BorderSizePixel = 0,
		Position = center,
		Size = UDim2.fromOffset(math.floor(radius * 1.3), math.floor(radius * 1.3)),
		ZIndex = z,
	}, parent)
	UIKit.corner(disc, 999)
	return disc
end

--[[
	Classic Roblox top studs over a w x h face (the Studs UI pack look): the
	studs patch (12 x 12) in squares `stud` x 12 across, side by side. The
	last column and row are CUT to the face (a smaller image showing that
	share of the patch, ImageRectSize), so nothing draws past w x h even
	where the parent can't clip: Roblox ignores ClipsDescendants under a
	turned GuiObject (the tilted X drew a whole patch past the window's
	edge, owner's Studio 2026-11-12). The previews read the cut from the
	attribute "Crop" (the share shown, x and y). A handful of images
	instead of hundreds of frames. Nil before the effects picture is
	uploaded (a plain band).
]]
function ShopFx.studs(parent: Instance, w: number, h: number, stud: number, transparency: number, z: number): Frame?
	if not IconAssets.shopFxShows("studs") then
		return nil
	end
	local holder = UIKit.new("Frame", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent)
	local patch = stud * 12
	local cols = math.max(1, math.ceil(w / patch))
	local rows = math.max(1, math.ceil(h / patch))
	local cell = IconAssets.ShopFx.Cells.studs
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local pw = math.min(patch, w - c * patch)
			local ph = math.min(patch, h - r * patch)
			local image = ShopFx.sprite(holder, "studs", {
				Name = "Patch",
				ImageTransparency = transparency,
				Position = UDim2.fromOffset(c * patch, r * patch),
				Size = UDim2.fromOffset(pw, ph),
				ZIndex = z,
			})
			if image and (pw < patch or ph < patch) then
				local sx, sy = pw / patch, ph / patch
				image.ImageRectSize = Vector2.new(cell[3] * sx, cell[4] * sy)
				image:SetAttribute("Crop", Vector2.new(sx, sy))
			end
		end
	end
	return holder
end

--[[
	A lightning bolt `height` tall with its middle at `at`, turned `rotation`,
	tinted `color` (variant 1..3 of the effects picture). It flashes now and
	then (mark "Bolt": dark most of the time, a quick flash every `period`
	seconds). Before the upload the icon sheet's bolt stands in, smaller
	(`fallback` false: nothing, for the bolts on cards).
]]
function ShopFx.bolt(
	parent: Instance,
	at: UDim2,
	height: number,
	rotation: number,
	color: Color3,
	variant: number,
	z: number,
	period: number?,
	fallback: boolean?
): ImageLabel?
	local name = "bolt" .. tostring(math.clamp(math.floor(variant), 1, 3))
	local image = ShopFx.sprite(parent, name, {
		Name = "Bolt",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = color,
		Position = at,
		Rotation = rotation,
		Size = UDim2.fromOffset(math.floor(height * 0.375), height),
		ZIndex = z,
	})
	if not image and fallback ~= false then
		image = ShopFx.icon(parent, "bolt", math.floor(math.min(height * 0.32, 74)), {
			Name = "Bolt",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at,
			Rotation = rotation * 0.4 + 12,
			ZIndex = z,
		})
	end
	if image then
		image:SetAttribute("ShopFx", "Bolt")
		image:SetAttribute("Period", period or 5)
		image:SetAttribute("Rest", ShopFx.BoltRest)
		image.ImageTransparency = ShopFx.BoltRest
	end
	return image
end
ShopFx.BoltRest = 0.35 -- a bolt at rest (Reduce motion, a still preview): softly lit

--[[
	A sparkle at `at`, `size` across, tinted `color`: the effects picture's
	soft one, else the icon sheet's (already uploaded), else two thin bars.
	It twinkles (mark "Sparkle": its UIScale "Pulse").
]]
function ShopFx.sparkle(parent: Instance, at: UDim2, size: number, color: Color3, z: number, phase: number?): GuiObject
	local props: Props = {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	}
	-- (the effects one takes the tint; the icon sheet's keeps its own colours)
	local image: GuiObject?
	if IconAssets.shopFxShows("sparkle") then
		props.ImageColor3 = color
		image = ShopFx.sprite(parent, "sparkle", props)
	else
		image = ShopFx.icon(parent, "sparkle", size, props)
	end
	local sparkle: GuiObject
	if image then
		sparkle = image
	else
		local holder = UIKit.new("Frame", {
			Name = "Sparkle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = at,
			Size = UDim2.fromOffset(size, size),
			ZIndex = z,
		}, parent)
		for i, rot in { 0, 90 } do
			local bar = UIKit.new("Frame", {
				Name = "Bar" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Rotation = rot,
				Size = UDim2.new(1, 0, 0.14, 0),
				ZIndex = z,
			}, holder)
			UIKit.corner(bar, 999)
		end
		sparkle = holder
	end
	UIKit.new("UIScale", { Name = "Pulse", Scale = 1 }, sparkle)
	sparkle:SetAttribute("ShopFx", "Sparkle")
	sparkle:SetAttribute("Phase", phase or 0)
	return sparkle
end

-- A flame tongue standing on `at` (its bottom middle), w x h, tinted `color` (a rounded frame before the upload).
function ShopFx.flame(parent: Instance, at: UDim2, w: number, h: number, color: Color3, transparency: number, z: number): GuiObject
	local image = ShopFx.sprite(parent, "flame", {
		Name = "Flame",
		AnchorPoint = Vector2.new(0.5, 1),
		ImageColor3 = color,
		ImageTransparency = transparency,
		Position = at,
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
	})
	if image then
		return image
	end
	local frame = UIKit.new("Frame", {
		Name = "Flame",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = math.max(transparency, 0.45),
		BorderSizePixel = 0,
		Position = at + UDim2.fromOffset(0, math.floor(h * 0.2)),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
	}, parent)
	UIKit.corner(frame, math.floor(w / 2))
	return frame
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
			Offset = Vector2.new(ShopFx.ShineFrom, 0),
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
	-- (held by its middle: hover and press scale it about its centre, over its slab)
	local face = UIKit.new("TextButton", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Selectable = true,
		ZIndex = z + 1,
	}, holder)
	local amount, small = dressButton(face, robux, size, style, z, label, text, true)
	ShopFx.bindPress(face, face)
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
	holder:SetAttribute("ShopFx", "Wiggle") -- (it rocks gently about its tilt)
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
	A golem, an egg or a pass item (the podium, the train, the hoverboard) as
	its drawn sticker (IconAssets.StickerSheets: `name` is the shop's picture
	name, golem_<Kind> / capsule_<Id> / podium / train / board_<Id>) `size`
	square, or nil when it won't show (its image isn't uploaded, or it has no
	sticker: the callers keep the live 3D model). One image, no 3D view.
]]
function ShopFx.stickerPicture(parent: Instance, name: string, size: number, props: Props?): ImageLabel?
	if not IconAssets.shopStickerShows(name) then
		return nil
	end
	local image = UIKit.new("ImageLabel", {
		Name = "Picture",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 4,
	}, parent)
	IconAssets.applyShopSticker(image, name)
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
	badge:SetAttribute("ShopFx", "Wiggle")
	return badge
end

---------------------------------------------------------------- living things (marks only: the motion moves them)

--[[
	A card's gloss: a white band over the whole card (its corners, over its
	picture and words) that the motion sweeps across now and then (mark
	"Sheen": the page's cards one after another). Ambient: a phone keeps its
	cards still. At rest the band waits off the card (nothing shows).
]]
function ShopFx.sheen(holder: Instance, corner: number, z: number): Frame
	local sheen = UIKit.new("Frame", {
		Name = "Sheen",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, holder)
	UIKit.corner(sheen, corner)
	local band = UIKit.new("UIGradient", {
		Name = "Sweep",
		Rotation = 22,
		Offset = Vector2.new(ShopFx.SweepFrom, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.38, 1),
			NumberSequenceKeypoint.new(0.47, 0.72),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(0.53, 0.72),
			NumberSequenceKeypoint.new(0.62, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sheen)
	band:SetAttribute("ShopFx", "Sheen")
	band:SetAttribute("Ambient", true)
	return sheen
end

--[[
	The SHOP title's light band: a copy of `label`'s words over it in warm
	white, all clear but a slanted band (mark "Glint": it slides across now
	and then; at rest it waits off the word). Returns the copy ("<Name>Glint").
]]
ShopFx.GlintColor = hex("#ffd84a")
function ShopFx.glint(label: TextLabel): TextLabel
	local copy = UIKit.new("TextLabel", {
		Name = label.Name .. "Glint",
		AnchorPoint = label.AnchorPoint,
		BackgroundTransparency = 1,
		FontFace = label.FontFace,
		Position = label.Position,
		Rotation = label.Rotation,
		Size = label.Size,
		Text = label.Text,
		TextColor3 = ShopFx.GlintColor,
		TextSize = label.TextSize,
		TextXAlignment = label.TextXAlignment,
		TextYAlignment = label.TextYAlignment,
		Visible = label.Visible,
		ZIndex = label.ZIndex + 1,
	}, label.Parent)
	local band = UIKit.new("UIGradient", {
		Name = "Glint",
		Rotation = 20,
		Offset = Vector2.new(ShopFx.SweepFrom, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.47, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.05),
			NumberSequenceKeypoint.new(0.53, 0.35),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, copy)
	band:SetAttribute("ShopFx", "Glint")
	return copy
end

--[[
	A theme particle for a tab's page (an ember, a gold sparkle, a spark, a
	coin): one picture with its middle at `at`, `size` across, that runs
	`path` (design units) every `period` seconds, fading in and out on the
	way (mark "Rise", brightest at `peak` transparency); invisible at rest.
	`picture` "shop_<name>" is a shop sheet icon (its own colours), else an
	effect sprite tinted `color`. Ambient: a phone skips it. Nil when its
	picture won't show.
]]
function ShopFx.particle(
	parent: Instance,
	picture: string,
	at: UDim2,
	size: number,
	path: Vector2,
	period: number,
	color: Color3,
	peak: number,
	z: number
): ImageLabel?
	local props: Props = {
		Name = "Mote",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 1,
		Position = at,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	}
	local image: ImageLabel?
	if string.sub(picture, 1, 5) == "shop_" then
		image = ShopFx.icon(parent, string.sub(picture, 6), size, props)
	else
		props.ImageColor3 = color
		image = ShopFx.sprite(parent, picture, props)
	end
	if image then
		image:SetAttribute("ShopFx", "Rise")
		image:SetAttribute("Path", path)
		image:SetAttribute("Period", period)
		image:SetAttribute("Peak", peak)
		image:SetAttribute("Ambient", true)
	end
	return image
end

---------------------------------------------------------------- motion (TweenService only)

ShopFx.ShineFrom = -1.6 -- a buy button's light band at rest (left of the face)
ShopFx.ShineTo = 2.4
ShopFx.ShineTime = 3 -- one sweep every 3 s (across the face in about 0.9 s)
ShopFx.ShineStagger = 0.5 -- (the next button's starts that much further off: the sweeps drift apart)
ShopFx.RimTime = 2.4 -- the Mythic rim: one turn
ShopFx.RimRest = 30
ShopFx.BoltDark = 6 -- (a transparency over 1 shows nothing: a bolt flashes in the last sixth of each half)
ShopFx.BoltPeak = 0.04
ShopFx.SparkleTime = 1.1
ShopFx.PulsePeak = 1.05
ShopFx.PulseTime = 0.8
ShopFx.FloatRise = 6
ShopFx.FloatTime = 1.7
ShopFx.BobRise = 3
ShopFx.BobTime = 0.9
ShopFx.Hover = 1.04
ShopFx.Press = 0.94
ShopFx.PressTime = 0.1
-- (the shop's motion v2, owner 2026-11-12: "improve the animations, add more things"; still clean and smooth)
ShopFx.IdleRise = 4 -- a golem's or an egg's soft bob (design units)
ShopFx.IdleSwing = 3 -- and its sway, degrees each way (the same tween: it rocks as it bobs)
ShopFx.IdleTime = 1.5 -- one way; each picture on a page IdleSpread slower than the one before
ShopFx.IdleSpread = 0.09
ShopFx.WobbleSwing = 8 -- a hero egg's hatch wobble (degrees at its peak)
ShopFx.WobbleTime = 1.8 -- one way (Elastic in, reversing: still about 2 s, then a quick rock)
ShopFx.GlowFade = 0.35 -- a glow breathes this much fainter
ShopFx.GlowTime = 1.3
ShopFx.WiggleSwing = 3 -- a sticker's, a badge's, a count's wiggle (degrees each way)
ShopFx.WiggleTime = 0.95
ShopFx.SweepFrom = -1.2 -- a gloss band at rest: off its face (UIGradient Offset X)
ShopFx.SweepTo = 1.2 -- (past the face's other side)
ShopFx.SheenEvery = 6 -- the cards' gloss: a round across the page every 6 s
ShopFx.SheenCross = 0.8 -- over one card in 0.8 s
ShopFx.SheenGap = 0.3 -- the next card's 0.3 s later (always the same order)
ShopFx.SheenLead = 0.9 -- (the first one after the cards' pop-in)
ShopFx.GlintEvery = 4.5 -- the SHOP title's light band
ShopFx.GlintCross = 0.85
ShopFx.GlintLead = 0.7
ShopFx.RisePeak = 0.2 -- a particle at its brightest
ShopFx.Lift = 5 -- a card under the mouse or the gamepad's selection rises this much
ShopFx.LightOn = 0.1 -- and its light edge brightens to this
ShopFx.GlowOn = 0.2 -- and its glow by this

export type Track = { Property: string, From: any, To: any, Rest: any }

export type Loop = {
	Kind: string, -- the mark it came from
	Target: Instance,
	Property: string,
	From: any,
	To: any,
	Rest: any, -- its value when nothing plays
	Time: number, -- seconds one way
	Style: string, -- Enum.EasingStyle's name
	Direction: string, -- Enum.EasingDirection's name
	Reverses: boolean,
	Also: { Track }?, -- more properties the same tween moves (an idle golem's sway with its bob)
}

export type Playing = { Tweens: { any }, Loops: { Loop } }

-- Is the shop's motion off now (Reduce motion, or Config/AnimConfig.PixelFx off)?
function ShopFx.quiet(): boolean
	return Motion.reduced() or AnimConfig.PixelFx ~= true
end

export type TweenMaker = (
	instance: Instance,
	time: number,
	style: string,
	direction: string,
	goal: { [string]: any },
	repeats: number,
	reverses: boolean,
	delay: number
) -> any
local fakeTweens: TweenMaker? = nil
local fakeDelays: ((seconds: number, fn: () -> ()) -> ())? = nil

-- (tests and previews) every tween ShopFx makes goes to `maker` instead (nil: TweenService).
function ShopFx.useTweens(maker: TweenMaker?)
	fakeTweens = maker
end

-- (previews) ShopFx's few one-off timers (a burst hidden, a celebration cleared) go to `delayer`
-- instead of task.delay (nil: task.delay): the motion video runs them on its own clock.
function ShopFx.useDelays(delayer: ((seconds: number, fn: () -> ()) -> ())?)
	fakeDelays = delayer
end

-- Runs `fn` once after `seconds` (task.delay; a preview's own clock).
local function later(seconds: number, fn: () -> ())
	local fake = fakeDelays
	if fake then
		fake(seconds, fn)
	else
		task.delay(seconds, fn)
	end
end

-- The one place ShopFx makes a tween; it plays at once. Nil when TweenService can't (Lune).
local function tween(
	instance: Instance,
	time: number,
	style: string,
	direction: string,
	goal: { [string]: any },
	repeats: number?,
	reverses: boolean?,
	delay: number?
): any
	local fake = fakeTweens
	if fake then
		local made = fake(instance, time, style, direction, goal, repeats or 0, reverses == true, delay or 0)
		if made and made.Play then
			made:Play()
		end
		return made
	end
	local ok, made = pcall(function()
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(
			time,
			(Enum.EasingStyle :: any)[style],
			(Enum.EasingDirection :: any)[direction],
			repeats or 0,
			reverses == true,
			delay or 0
		)
		local t = TweenService:Create(instance, info, goal)
		t:Play()
		return t
	end)
	return if ok then made else nil
end

local function set(target: Instance, property: string, value: any)
	(target :: any)[property] = value
end

-- A mark's base value, read once (a restart never drifts: Rays from its first Rotation, Float / Bob from its Position).
local function base(target: GuiObject, property: string): any
	local stored = target:GetAttribute("Base")
	if stored ~= nil then
		return stored
	end
	local value = (target :: any)[property]
	target:SetAttribute("Base", value)
	return value
end

-- One Loop (typed: the marks' literals stay plain strings and instances).
local function newLoop(
	kind: string,
	target: Instance,
	property: string,
	from: any,
	to: any,
	rest: any,
	time: number,
	style: string,
	direction: string,
	reverses: boolean
): Loop
	return {
		Kind = kind,
		Target = target,
		Property = property,
		From = from,
		To = to,
		Rest = rest,
		Time = time,
		Style = style,
		Direction = direction,
		Reverses = reverses,
		Also = nil,
	}
end

local function scaleOf(target: Instance): UIScale?
	local found = target:FindFirstChild("Pulse")
	return if found and found:IsA("UIScale") then found else nil
end

-- A base value of one property, read once (attribute "Base<Property>": a restart never drifts;
-- the newer marks keep one per property, an idle picture has two).
local function baseOf(target: Instance, property: string): any
	local name = "Base" .. property
	local stored = target:GetAttribute(name)
	if stored ~= nil then
		return stored
	end
	local value = (target :: any)[property]
	target:SetAttribute(name, value)
	return value
end

local function numberAttr(target: Instance, name: string, default: number): number
	local value = target:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function track(property: string, from: any, to: any, rest: any): Track
	return { Property = property, From = from, To = to, Rest = rest }
end

--[[
	A light band across a face (a card's Sheen, the title's Glint): its
	UIGradient Offset runs from far left to past the right in `every`
	seconds at one speed, so the band crosses the face (SweepFrom ..
	SweepTo) in `cross` seconds, `start` seconds into each round; the jump
	back happens far off the face. Same `every` for all: the bands keep their
	order forever (no drift).
]]
local function sweepLoop(kind: string, gradient: Instance, every: number, cross: number, start: number): Loop
	local speed = (ShopFx.SweepTo - ShopFx.SweepFrom) / cross
	local from = ShopFx.SweepFrom - speed * start
	local rest = Vector2.new(ShopFx.SweepFrom, 0)
	return newLoop(kind, gradient, "Offset", Vector2.new(from, 0), Vector2.new(from + speed * every, 0), rest, every, "Linear", "In", false)
end

--[[
	The endless loops of everything marked under `roots` (and the roots
	themselves): one Loop per mark (two for a particle, its drift and its
	fade; two for a hero egg, its float and its wobble). `compact` (a
	phone): no ambient marks (attribute Ambient: the bolts round the window,
	the frame's sparkles, the pages' particles, the cards' gloss, the small
	pictures' idling). A hidden gui and everything in it gets none (a hidden
	card, an owned pass's price, a banner that isn't shown).
]]
function ShopFx.loopsUnder(roots: { Instance }, compact: boolean?): { Loop }
	local loops: { Loop } = {}
	local shines, sheens, idles, wiggles = 0, 0, 0, 0
	local function take(d: Instance)
		local kind = d:GetAttribute("ShopFx")
		if type(kind) ~= "string" then
			return
		end
		if compact and d:GetAttribute("Ambient") == true then
			return
		end
		local phase = d:GetAttribute("Phase")
		local p = if type(phase) == "number" then phase else 0
		local period = d:GetAttribute("Period")
		if kind == "Rays" and d:IsA("GuiObject") then
			local from = base(d, "Rotation") :: number
			local time = if type(period) == "number" then period else 24
			table.insert(loops, newLoop(kind, d, "Rotation", from, from + 360, from, time, "Linear", "In", false))
		elseif kind == "Shine" and d:IsA("UIGradient") then
			-- (each button's band starts a little further off than the last, at the same speed: the
			-- buttons shine one after another, never all at once)
			local rest = Vector2.new(ShopFx.ShineFrom, 0)
			local from = rest - Vector2.new((shines % 4) * ShopFx.ShineStagger, 0)
			local time = ShopFx.ShineTime * (ShopFx.ShineTo - from.X) / (ShopFx.ShineTo - ShopFx.ShineFrom)
			shines += 1
			table.insert(loops, newLoop(kind, d, "Offset", from, Vector2.new(ShopFx.ShineTo, 0), rest, time, "Linear", "In", false))
		elseif kind == "Rim" and d:IsA("UIGradient") then
			table.insert(loops, newLoop(kind, d, "Rotation", 0, 360, ShopFx.RimRest, ShopFx.RimTime, "Linear", "In", false))
		elseif kind == "Bolt" and (d:IsA("ImageLabel") or d:IsA("ImageButton")) then
			local rest = d:GetAttribute("Rest")
			local half = (if type(period) == "number" then period else 5) / 2
			local still = if type(rest) == "number" then rest else ShopFx.BoltRest
			table.insert(loops, newLoop(kind, d, "ImageTransparency", ShopFx.BoltDark, ShopFx.BoltPeak, still, half, "Quad", "In", true))
		elseif kind == "Sparkle" or kind == "Pulse" then
			local scale = scaleOf(d)
			if scale then
				if kind == "Sparkle" then
					table.insert(loops, newLoop(kind, scale, "Scale", 0.35, 1.1, 1, ShopFx.SparkleTime + p * 0.17, "Sine", "InOut", true))
				else
					table.insert(loops, newLoop(kind, scale, "Scale", 1, ShopFx.PulsePeak, 1, ShopFx.PulseTime, "Sine", "InOut", true))
				end
			end
		elseif (kind == "Float" or kind == "Bob") and d:IsA("GuiObject") then
			local from = base(d, "Position") :: UDim2
			local rise = if kind == "Float" then numberAttr(d, "Rise", ShopFx.FloatRise) else ShopFx.BobRise
			local time = if kind == "Float" then ShopFx.FloatTime else ShopFx.BobTime
			local loop = newLoop(kind, d, "Position", from, from + UDim2.fromOffset(0, -rise), from, time, "Sine", "InOut", true)
			table.insert(loops, loop)
			local wobble, swing = d:GetAttribute("Wobble"), d:GetAttribute("Swing")
			if kind == "Float" and type(wobble) == "number" then
				-- an egg about to hatch: still most of the time, then a quick rock (Elastic in, reversing)
				local rot = baseOf(d, "Rotation") :: number
				table.insert(loops, newLoop("Wobble", d, "Rotation", rot, rot + wobble, rot, ShopFx.WobbleTime, "Elastic", "In", true))
			elseif kind == "Float" and type(swing) == "number" then
				-- (it rocks as it floats: the same tween)
				local rot = baseOf(d, "Rotation") :: number
				loop.Also = { track("Rotation", rot - swing, rot + swing, rot) }
			end
		elseif kind == "Idle" and d:IsA("GuiObject") then
			-- (each one a little slower than the one before, every second one from the top and every
			-- other pair leaning the other way: a row of golems never moves in step)
			local i = idles
			idles += 1
			local pos = baseOf(d, "Position") :: UDim2
			local rot = baseOf(d, "Rotation") :: number
			local up = pos + UDim2.fromOffset(0, -numberAttr(d, "Rise", ShopFx.IdleRise))
			local swing = numberAttr(d, "Swing", ShopFx.IdleSwing)
			local lean = if (i // 2) % 2 == 0 then swing else -swing
			local time = ShopFx.IdleTime * (1 + ShopFx.IdleSpread * (i % 5))
			local loop = if i % 2 == 0
				then newLoop(kind, d, "Position", pos, up, pos, time, "Sine", "InOut", true)
				else newLoop(kind, d, "Position", up, pos, pos, time, "Sine", "InOut", true)
			loop.Also = { track("Rotation", rot - lean, rot + lean, rot) }
			table.insert(loops, loop)
		elseif kind == "Glow" and d:IsA("GuiObject") then
			local property = if d:IsA("ImageLabel") or d:IsA("ImageButton") then "ImageTransparency" else "BackgroundTransparency"
			local rest = baseOf(d, property) :: number
			local faint = math.min(1, rest + numberAttr(d, "Fade", ShopFx.GlowFade))
			table.insert(loops, newLoop(kind, d, property, rest, faint, rest, ShopFx.GlowTime, "Sine", "InOut", true))
		elseif kind == "Wiggle" and d:IsA("GuiObject") then
			local i = wiggles
			wiggles += 1
			local rot = baseOf(d, "Rotation") :: number
			local swing = numberAttr(d, "Swing", ShopFx.WiggleSwing)
			local lean = if i % 2 == 0 then swing else -swing
			local time = ShopFx.WiggleTime * (1 + 0.14 * (i % 4))
			table.insert(loops, newLoop(kind, d, "Rotation", rot - lean, rot + lean, rot, time, "Sine", "InOut", true))
		elseif kind == "Sheen" and d:IsA("UIGradient") then
			local room = ShopFx.SheenEvery - ShopFx.SheenCross
			local start = (ShopFx.SheenLead + sheens * ShopFx.SheenGap) % room
			sheens += 1
			table.insert(loops, sweepLoop(kind, d, ShopFx.SheenEvery, ShopFx.SheenCross, start))
		elseif kind == "Glint" and d:IsA("UIGradient") then
			table.insert(loops, sweepLoop(kind, d, ShopFx.GlintEvery, ShopFx.GlintCross, ShopFx.GlintLead))
		elseif kind == "Rise" and (d:IsA("ImageLabel") or d:IsA("ImageButton")) then
			local path = d:GetAttribute("Path")
			if typeof(path) == "Vector2" then
				local pos = baseOf(d, "Position") :: UDim2
				local round = numberAttr(d, "Period", 3)
				local peak = numberAttr(d, "Peak", ShopFx.RisePeak)
				local to = pos + UDim2.fromOffset((path :: Vector2).X, (path :: Vector2).Y)
				table.insert(loops, newLoop(kind, d, "Position", pos, to, pos, round, "Linear", "In", false))
				-- (clear at both ends of the drift, brightest half way: the jump back is never seen)
				table.insert(loops, newLoop(kind, d, "ImageTransparency", 1, peak, 1, round / 2, "Sine", "InOut", true))
			end
		end
	end
	local function walk(d: Instance)
		if d:IsA("GuiObject") and not d.Visible then
			return
		end
		take(d)
		for _, child in d:GetChildren() do
			walk(child)
		end
	end
	for _, root in roots do
		walk(root)
	end
	return loops
end

-- Starts one endless tween per loop (from its From). Nothing when the shop is quiet.
function ShopFx.play(loops: { Loop }): Playing
	local playing: Playing = { Tweens = {}, Loops = loops }
	if ShopFx.quiet() then
		playing.Loops = {}
		return playing
	end
	for _, loop in loops do
		set(loop.Target, loop.Property, loop.From)
		local goal = { [loop.Property] = loop.To }
		local also: { Track } = loop.Also or {}
		for _, more in also do
			set(loop.Target, more.Property, more.From)
			goal[more.Property] = more.To
		end
		local made = tween(loop.Target, loop.Time, loop.Style, loop.Direction, goal, -1, loop.Reverses, 0)
		if made then
			table.insert(playing.Tweens, made)
		end
	end
	return playing
end

-- Cancels a play() and puts its things at rest.
function ShopFx.stop(playing: Playing?)
	if not playing then
		return
	end
	for _, made in playing.Tweens do
		pcall(function()
			made:Cancel()
		end)
	end
	for _, loop in playing.Loops do
		if loop.Target.Parent then
			set(loop.Target, loop.Property, loop.Rest)
			local also: { Track } = loop.Also or {}
			for _, more in also do
				set(loop.Target, more.Property, more.Rest)
			end
		end
	end
	table.clear(playing.Tweens)
	table.clear(playing.Loops)
end

local function lerpValue(from: any, to: any, u: number): any
	if type(from) == "number" then
		return from + (to - from) * u
	elseif typeof(from) == "Vector2" then
		return (from :: Vector2):Lerp(to :: Vector2, u)
	elseif typeof(from) == "UDim2" then
		return (from :: UDim2):Lerp(to :: UDim2, u)
	end
	return if u < 0.5 then from else to
end

--[[
	A loop's value `t` seconds after it started (the same curve the tween
	runs: the previews' video, the tests); `property` one of its Also tracks
	(an idle picture's Rotation) instead of its own.
]]
function ShopFx.sample(loop: Loop, t: number, property: string?): any
	local period = math.max(loop.Time, 1e-6)
	local k: number
	if loop.Reverses then
		local cycle = (t % (2 * period)) / period
		k = if cycle <= 1 then cycle else 2 - cycle
	else
		k = (t % period) / period
	end
	local u = Motion.ease(loop.Style, loop.Direction, k)
	if property and property ~= loop.Property then
		local also: { Track } = loop.Also or {}
		for _, more in also do
			if more.Property == property then
				return lerpValue(more.From, more.To, u)
			end
		end
		return nil
	end
	return lerpValue(loop.From, loop.To, u)
end

---------------------------------------------------------------- one-shot motion (open, close, tabs, cards, buttons)

-- A UIScale named `name` on `gui` (made once).
local function scaleOn(gui: Instance, name: string): UIScale
	local found = gui:FindFirstChild(name)
	if found and found:IsA("UIScale") then
		return found
	end
	return UIKit.new("UIScale", { Name = name, Scale = 1 }, gui)
end

--[[
	The window opens: it pops from 0.82 (Back out), the dim fades in, a burst
	of rays (`burst`: an image behind the window) flashes out and fades.
	Quiet: it just shows.
]]
function ShopFx.open(group: GuiObject, dim: GuiObject?, dimTo: number, burst: GuiObject?)
	local pop = scaleOn(group, "OpenPop")
	if ShopFx.quiet() then
		pop.Scale = 1
		if dim then
			dim.BackgroundTransparency = dimTo
		end
		if burst then
			burst.Visible = false
		end
		return
	end
	pop.Scale = 0.82
	tween(pop, 0.34, "Back", "Out", { Scale = 1 })
	if dim then
		dim.BackgroundTransparency = 1
		tween(dim, 0.2, "Quad", "Out", { BackgroundTransparency = dimTo })
	end
	if burst then
		-- (it grows out past the window's edges, bright at first, fading as it goes)
		local grow = scaleOn(burst, "Burst")
		burst.Visible = true
		grow.Scale = 0.6
		burst.Rotation = 0
		if burst:IsA("ImageLabel") then
			burst.ImageTransparency = 0.05
			tween(burst, 0.6, "Quad", "In", { ImageTransparency = 1 })
			tween(burst, 0.6, "Quad", "Out", { Rotation = 30 })
		else
			burst.BackgroundTransparency = 0.5
			tween(burst, 0.6, "Quad", "Out", { BackgroundTransparency = 1 })
		end
		tween(grow, 0.6, "Quad", "Out", { Scale = 2 })
		-- (gone once it has faded: a later open's burst keeps its own)
		local shot = (tonumber(burst:GetAttribute("Shot")) or 0) + 1
		burst:SetAttribute("Shot", shot)
		later(0.65, function()
			if burst:GetAttribute("Shot") == shot then
				burst.Visible = false
			end
		end)
	end
end

-- The window at rest, open (a close's shrink and the dim's fade put back).
function ShopFx.rest(group: GuiObject, dim: GuiObject?, dimTo: number)
	local pop = group:FindFirstChild("OpenPop")
	if pop and pop:IsA("UIScale") then
		pop.Scale = 1
	end
	if dim then
		dim.BackgroundTransparency = dimTo
	end
end

-- The window closes: it shrinks to 0.86 as the dim fades, then `done`. Quiet: `done` at once.
function ShopFx.close(group: GuiObject, dim: GuiObject?, done: () -> ())
	local pop = scaleOn(group, "OpenPop")
	if ShopFx.quiet() then
		pop.Scale = 1
		done()
		return
	end
	tween(pop, 0.14, "Quad", "In", { Scale = 0.86 })
	if dim then
		tween(dim, 0.14, "Quad", "In", { BackgroundTransparency = 1 })
	end
	later(0.15, done)
end

-- A layer fades out over what is under it (a tab's old colours over its new ones).
function ShopFx.fadeOut(layer: GuiObject, time: number?)
	if ShopFx.quiet() then
		layer.BackgroundTransparency = 1
		return
	end
	layer.BackgroundTransparency = 0
	tween(layer, time or 0.28, "Quad", "Out", { BackgroundTransparency = 1 })
end

-- A colour moves to `color` (a glow's BackgroundColor3, a bolt's ImageColor3).
function ShopFx.recolor(gui: GuiObject, property: string, color: Color3)
	if ShopFx.quiet() then
		set(gui, property, color)
		return
	end
	tween(gui, 0.3, "Quad", "Out", { [property] = color })
end

-- A page slides in from `dx` units to the right of where it rests.
function ShopFx.slideIn(page: GuiObject, rest: UDim2, dx: number)
	if ShopFx.quiet() then
		page.Position = rest
		return
	end
	page.Position = rest + UDim2.fromOffset(dx, 0)
	tween(page, 0.26, "Quad", "Out", { Position = rest })
end

-- Cards pop in one after another (each holder's UIScale "Scale": 0.85 -> 1, Back out).
function ShopFx.popIn(holders: { GuiObject })
	for i, holder in holders do
		local scale = scaleOn(holder, "Scale")
		if ShopFx.quiet() then
			scale.Scale = 1
		else
			scale.Scale = 0.85
			tween(scale, 0.3, "Back", "Out", { Scale = 1 }, 0, false, math.min(0.35, (i - 1) * 0.035))
		end
	end
end

-- The picked tab's picture pops (its UIScale "Pop": from small, Back out). Quiet: it just shows.
ShopFx.IconPopFrom = 0.45
function ShopFx.popIcon(icon: GuiObject)
	local pop = scaleOn(icon, "Pop")
	if ShopFx.quiet() then
		pop.Scale = 1
		return
	end
	pop.Scale = ShopFx.IconPopFrom
	tween(pop, 0.36, "Back", "Out", { Scale = 1 })
end

export type Cascade = {
	Drops: { GuiObject }, -- the title (and its copies): they drop into place
	Pops: { GuiObject }, -- the basket and the tabs, left to right: they pop in one after another
	Spin: GuiObject?, -- the X: it spins in
}

ShopFx.CascadeDrop = 26 -- the title drops this far
ShopFx.DropTime = 0.2
ShopFx.PopTime = 0.16
ShopFx.PopStart = 0.02
ShopFx.PopStep = 0.018 -- (seven pops: the last one starts at 0.13 s)
ShopFx.SpinDelay = 0.04
ShopFx.SpinTime = 0.24 -- (the whole cascade is over by 0.3 s)

--[[
	As the window opens its header comes in: the title drops into place, the
	basket and the tabs pop in one after another (their UIScale "Scale"),
	the X spins in (Rotation, from half a turn back, and its "Scale"); all
	Back out, over by 0.3 s. Quiet: all at rest at once.
]]
function ShopFx.cascade(parts: Cascade)
	local quiet = ShopFx.quiet()
	for _, gui in parts.Drops do
		local rest = baseOf(gui, "Position") :: UDim2
		if quiet then
			gui.Position = rest
		else
			gui.Position = rest + UDim2.fromOffset(0, -ShopFx.CascadeDrop)
			tween(gui, ShopFx.DropTime, "Back", "Out", { Position = rest })
		end
	end
	for i, gui in parts.Pops do
		local scale = scaleOn(gui, "Scale")
		if quiet then
			scale.Scale = 1
		else
			scale.Scale = 0.3
			tween(scale, ShopFx.PopTime, "Back", "Out", { Scale = 1 }, 0, false, ShopFx.PopStart + (i - 1) * ShopFx.PopStep)
		end
	end
	local spin = parts.Spin
	if spin then
		local rest = baseOf(spin, "Rotation") :: number
		local scale = scaleOn(spin, "Scale")
		if quiet then
			spin.Rotation = rest
			scale.Scale = 1
		else
			spin.Rotation = rest - 180
			scale.Scale = 0.3
			tween(spin, ShopFx.SpinTime, "Back", "Out", { Rotation = rest }, 0, false, ShopFx.SpinDelay)
			tween(scale, ShopFx.SpinTime, "Back", "Out", { Scale = 1 }, 0, false, ShopFx.SpinDelay)
		end
	end
end

ShopFx.CelebratePop = 1.12 -- a bought card pops from this
ShopFx.PrizeCount = 12 -- stars (or coins) out of it, at most
ShopFx.PrizeTime = 0.75

--[[
	A purchase from the shop went through: `target` (a card, or a banner's
	buy button) flashes white and pops from CelebratePop back to 1 (its
	UIScale "Scale"), and PrizeCount `picture`s (a shop sheet icon: "star",
	"coin"; else the effects sparkle in gold) fly out of its middle (`at`,
	in `layer`, the window's front) in a ring, spinning and fading; all gone
	after PrizeTime. Quiet: nothing. Returns the flash and the prizes (the
	specs).
]]
function ShopFx.celebrate(target: GuiObject, corner: number, layer: Instance, at: UDim2, picture: string, seed: number?): { GuiObject }
	local made: { GuiObject } = {}
	if ShopFx.quiet() then
		return made
	end
	local pop = scaleOn(target, "Scale")
	pop.Scale = ShopFx.CelebratePop
	tween(pop, 0.42, "Back", "Out", { Scale = 1 })
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 16,
	}, target)
	UIKit.corner(flash, corner)
	tween(flash, 0.45, "Quad", "Out", { BackgroundTransparency = 1 })
	table.insert(made, flash)
	local rand = ShopFx.random(seed or 7)
	local count = ShopFx.PrizeCount
	for i = 1, count do
		local angle = (i - 1) / count * 2 * math.pi + (rand() - 0.5) * 0.4
		local far = 110 + rand() * 90
		local size = math.floor(26 + rand() * 16)
		local props: Props = {
			Name = "Prize",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at,
			Rotation = math.floor(rand() * 60 - 30),
			Size = UDim2.fromOffset(math.floor(size * 0.4), math.floor(size * 0.4)),
			ZIndex = 30,
		}
		local image = ShopFx.icon(layer, picture, size, props)
		if not image then
			props.ImageColor3 = hex("#ffe27a")
			image = ShopFx.sprite(layer, "sparkle", props)
		end
		if image then
			local goal = {
				Position = at + UDim2.fromOffset(math.floor(math.cos(angle) * far), math.floor(math.sin(angle) * far * 0.8)),
				Rotation = image.Rotation + (if i % 2 == 0 then 140 else -140),
				Size = UDim2.fromOffset(size, size),
			}
			tween(image, ShopFx.PrizeTime, "Quad", "Out", goal)
			tween(image, ShopFx.PrizeTime, "Quad", "In", { ImageTransparency = 1 })
			table.insert(made, image)
		end
	end
	later(ShopFx.PrizeTime + 0.05, function()
		for _, gui in made do
			gui:Destroy()
		end
	end)
	return made
end

export type PressLook = {
	Lift: number?, -- a card rises this much under the mouse or the gamepad's selection
	Light: UIStroke?, -- its light edge brightens (ShopFx.LightOn)
	Glow: GuiObject?, -- its glow too (by ShopFx.GlowOn)
}

--[[
	`target` hovered (the mouse, or a gamepad's selection) or held (a press,
	a touch): 1.04 / 0.94 (its UIScale "Scale"); with `look` a hovered card
	also rises (its AnchorPoint: the layout's Position stays its own) and
	its light edge and glow brighten. Quiet: all at rest at once.
]]
function ShopFx.hover(target: GuiObject, hovered: boolean, held: boolean, look: PressLook?)
	local scale = scaleOn(target, "Scale")
	local quiet = ShopFx.quiet()
	local raised = hovered and not quiet
	local goal = if quiet then 1 elseif held then ShopFx.Press elseif hovered then ShopFx.Hover else 1
	if quiet then
		scale.Scale = 1
	else
		tween(scale, ShopFx.PressTime, "Quad", "Out", { Scale = goal })
	end
	if not look then
		return
	end
	local function move(gui: Instance, property: string, value: any)
		if quiet then
			set(gui, property, value)
		else
			tween(gui, ShopFx.PressTime + 0.04, "Quad", "Out", { [property] = value })
		end
	end
	local lift = look.Lift or 0
	if lift > 0 then
		local anchor = baseOf(target, "AnchorPoint") :: Vector2
		local h = target.Size.Y.Offset
		local up = if raised and h > 0 then lift / h else 0
		move(target, "AnchorPoint", Vector2.new(anchor.X, anchor.Y + up))
	end
	local light = look.Light
	if light then
		local rest = baseOf(light, "Transparency") :: number
		move(light, "Transparency", if raised then ShopFx.LightOn else rest)
	end
	local glow = look.Glow
	if glow then
		local property = if glow:IsA("ImageLabel") then "ImageTransparency" else "BackgroundTransparency"
		local rest = baseOf(glow, property) :: number
		move(glow, property, if raised then math.max(0, rest - ShopFx.GlowOn) else rest)
	end
end

--[[
	Hover 1.04 (the mouse, or a gamepad's selection) and press 0.94 on
	`button`, scaling `target` (a UIScale "Scale" on it; held by its middle);
	`look`: a card also rises and brightens while hovered (ShopFx.hover). A
	touch only presses. The motion watcher leaves it alone (attribute
	Motion = "None"). Quiet: nothing moves. (Connections need the game: Lune
	skips them.)
]]
function ShopFx.bindPress(button: GuiButton, target: GuiObject, look: PressLook?)
	button:SetAttribute("Motion", "None")
	scaleOn(target, "Scale")
	local hovered, held = false, false
	local function go()
		ShopFx.hover(target, hovered, held, look)
	end
	pcall(function()
		local UserInputService = game:GetService("UserInputService")
		local function mouse(): boolean
			local last = UserInputService:GetLastInputType()
			return last == Enum.UserInputType.MouseMovement or last.Name:sub(1, 11) == "MouseButton"
		end
		button.MouseEnter:Connect(function()
			if mouse() then
				hovered = true
				go()
			end
		end)
		button.MouseLeave:Connect(function()
			hovered, held = false, false
			go()
		end)
		button.SelectionGained:Connect(function()
			hovered = true
			go()
		end)
		button.SelectionLost:Connect(function()
			hovered, held = false, false
			go()
		end)
		button.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
				held = true
				go()
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
				held = false
				hovered = hovered and kind ~= Enum.UserInputType.Touch
				go()
			end
		end)
	end)
end

return ShopFx
