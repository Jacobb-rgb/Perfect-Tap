--[[
	The "Store card" UI kit (Config/CardTheme): the owner's new look for every
	window, from the store photos he sent (2026-10-20).

	  window   dark slate frame, an olive -> gold striped header band with a
	           cream title and a red X, a dark body for the content
	  card     a dark button with a glowing coloured border (CardTheme.Glows;
	           Rainbow runs the border through the rainbow), a soft glow
	           behind its picture and a few sparkles
	  title    comic-font text with a colour gradient and a dark edge
	  text     cream comic-font text with a dark edge
	  price    the green Robux price (robux icon + number), bottom right
	  pill     a bright HUD button with an icon and a word ("Shop")

	Pictures are the 3D icons (Bubble.icon: an emoji stands in until the
	owner uploads the icon sheets).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CardTheme = require(Shared.Config.CardTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local Card = {}

type Props = { [string]: any }

local function apply(instance: Instance, props: Props?)
	if props then
		local target: any = instance
		for key, value in props do
			target[key] = value
		end
	end
end

-- A dark edge around a text's glyphs.
function Card.edge(label: GuiObject, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = CardTheme.Edge,
		Thickness = thickness or CardTheme.TextEdge,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
end

-- Cream comic-font text with a dark edge.
function Card.text(parent: Instance, text: string, size: number, props: Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 6),
		FontFace = CardTheme.Font,
		Text = text,
		TextSize = size,
		TextColor3 = CardTheme.Ink,
		TextWrapped = true,
		ZIndex = 4,
	}, parent)
	Card.edge(label, if size >= 24 then CardTheme.TextEdge + 0.5 else CardTheme.TextEdge)
	apply(label, props)
	return label
end

-- Comic-font title in a glow's colour gradient (top -> bottom) with a dark edge.
function Card.title(parent: Instance, text: string, size: number, glowName: string | CardTheme.Glow, props: Props?): TextLabel
	local glow = if type(glowName) == "table" then glowName else (CardTheme.Glows[glowName] or CardTheme.Glows.Orange)
	local label = Card.text(parent, text, size, { Name = "Title", TextColor3 = Color3.new(1, 1, 1), TextWrapped = false })
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(glow.Top, glow.Bottom),
		Rotation = 90,
	}, label)
	local titleEdge = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	titleEdge.Thickness = CardTheme.TextEdge + 1
	apply(label, props)
	return label
end

-- A 3D picture (Bubble.icon) of `size` design units.
function Card.picture(parent: Instance, name: string, size: number, props: Props?): ImageLabel
	return Bubble.icon(parent, name, size, props)
end

-- Small four-point stars around a picture, at fixed spots (seeded, the same every build).
function Card.sparkles(parent: Instance, color: Color3, count: number, seed: number)
	-- a tiny seeded generator (the same spots every build, in Studio and the previews)
	local state = seed % 2147483647
	local function next01(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	local function between(a: number, b: number): number
		return a + (b - a) * next01()
	end
	for i = 1, count do
		local size = math.floor(between(12, 22.99))
		UIKit.new("TextLabel", {
			Name = "Sparkle" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(between(0.08, 0.92), between(0.12, 0.78)),
			Size = UDim2.fromOffset(size, size),
			FontFace = CardTheme.NumberFont,
			Text = "✦",
			TextSize = size,
			TextColor3 = color,
			TextTransparency = between(0.1, 0.45),
			ZIndex = 2,
		}, parent)
	end
end

--[[
	A card: a dark button with a glowing border in `glowName`'s colour, a soft
	glow in the middle (behind the picture) and sparkles. Its children go on
	top (ZIndex 3+). Returns the button.
]]
-- A glow from one colour (a data colour: a star blaster's light).
function Card.glowFrom(color: Color3): CardTheme.Glow
	return { Edge = color, Top = color:Lerp(Color3.new(1, 1, 1), 0.55), Bottom = color }
end

function Card.card(parent: Instance, glowName: string | CardTheme.Glow, props: Props?): TextButton
	local glow = if type(glowName) == "table" then glowName else (CardTheme.Glows[glowName] or CardTheme.Glows.Orange)
	local button = UIKit.new("TextButton", {
		Name = "Card",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1), -- (the gradient below gives the colour: it multiplies)
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 2,
		Selectable = true,
	}, parent)
	UIKit.corner(button, CardTheme.CardCorner)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(CardTheme.CardTop, CardTheme.Card),
		Rotation = 90,
	}, button)
	local edge = UIKit.new("UIStroke", {
		Name = "Glow",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = glow.Edge,
		Thickness = CardTheme.EdgeThickness,
	}, button)
	if glow.Rainbow then
		local keys = {}
		for i, color in CardTheme.RainbowKeys do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#CardTheme.RainbowKeys - 1), color))
		end
		UIKit.new("UIGradient", { Color = ColorSequence.new(keys), Rotation = 30 }, edge)
	end
	-- the soft glow behind the picture: a big faint disc in the glow colour
	local halo = UIKit.new("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = if glow.Rainbow then CardTheme.Glows.Gold.Edge else glow.Edge,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(120, 120), -- (Card.halo sizes it to the picture)
		ZIndex = 2,
	}, button)
	UIKit.corner(halo, 999)
	apply(button, props)
	return button
end

-- About how wide a number is in the round number font (design units).
function Card.digitsWidth(text: string, size: number): number
	return math.ceil(#text * size * 0.62 + 6)
end

-- Puts a card's glow disc behind a picture of `size` at `position`.
function Card.halo(card: Instance, position: UDim2, size: number)
	local halo = card:FindFirstChild("Halo") :: Frame?
	if halo then
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = position
		halo.Size = UDim2.fromOffset(math.floor(size * 1.15), math.floor(size * 1.15))
	end
end

-- The green Robux price at a card's bottom right ("49" with the robux mark).
function Card.price(parent: Instance, robux: number, size: number, props: Props?): Frame
	local row = UIKit.new("Frame", {
		Name = "Price",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -8, 1, -6),
		Size = UDim2.fromOffset(size * 4, size + 8),
		ZIndex = 4,
	}, parent)
	UIKit.list(row, Enum.FillDirection.Horizontal, 4, {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local mark = Bubble.icon(row, "robux", size + 2, { LayoutOrder = 1, ZIndex = 5, ImageColor3 = CardTheme.Price })
	mark.Name = "Robux"
	local amount = Card.text(row, tostring(robux), size, {
		Name = "Amount",
		Size = UDim2.fromOffset(Card.digitsWidth(tostring(robux), size), size + 6),
		LayoutOrder = 2,
		TextColor3 = CardTheme.Price,
		TextWrapped = false,
		FontFace = CardTheme.NumberFont,
		ZIndex = 5,
	})
	local amountEdge = amount:FindFirstChildOfClass("UIStroke") :: UIStroke
	amountEdge.Color = CardTheme.PriceEdge
	apply(row, props)
	return row
end

export type Window = {
	Root: Frame,
	Header: Frame,
	Title: TextLabel,
	Close: TextButton,
	Body: Frame,
}

--[[
	A window: the slate frame, the striped header band with the title and a
	red X, and the dark body under it (Body: the content area). `size` in
	design units; `header` the band's height.
]]
function Card.window(parent: Instance, title: string, size: Vector2, header: number?): Window
	local band = header or 64
	local root = UIKit.new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CardTheme.Window,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Active = true,
		ZIndex = 1,
	}, parent)
	UIKit.corner(root, CardTheme.Corner)
	UIKit.new("UIStroke", { Color = CardTheme.WindowEdge, Thickness = CardTheme.EdgeThickness }, root)

	local head = UIKit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, band),
		ClipsDescendants = true,
		ZIndex = 2,
	}, root)
	UIKit.corner(head, CardTheme.Corner)
	local keys = {}
	for i, color in CardTheme.Header do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#CardTheme.Header - 1), color))
	end
	UIKit.new("UIGradient", { Color = ColorSequence.new(keys) }, head)
	-- the square bottom of the band (the corner rounds only the window's top)
	local foot = UIKit.new("Frame", {
		Name = "Foot",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, CardTheme.Corner),
		ZIndex = 2,
	}, head)
	UIKit.new("UIGradient", { Color = ColorSequence.new(keys) }, foot)
	-- faint diagonal stripes across the band
	for i = 0, math.ceil(size.X / 26) do
		UIKit.new("Frame", {
			Name = "Stripe",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = CardTheme.HeaderStripe,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 14 + i * 26, 0.5, 0),
			Rotation = 35,
			Size = UDim2.new(0, 8, 0, band * 2),
			ZIndex = 3,
		}, head)
	end
	local titleLabel = Card.text(head, title, math.floor(band * 0.62), {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		Size = UDim2.new(1, -120, 1, -8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 5,
	})
	local titleStroke = titleLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
	titleStroke.Thickness = 3
	local closeSize = math.floor(band * 0.78)
	local close = UIKit.new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		AutoButtonColor = true,
		BackgroundColor3 = CardTheme.Close,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -10, 0, math.floor(band / 2)),
		Size = UDim2.fromOffset(closeSize, closeSize),
		FontFace = CardTheme.NumberFont,
		Text = "X",
		TextSize = math.floor(closeSize * 0.62),
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
	}, root)
	UIKit.corner(close, 8)
	UIKit.new("UIStroke", { Color = CardTheme.CloseEdge, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, close)
	Card.edge(close, 2)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(214, 214, 214)),
		Rotation = 90,
	}, close)

	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = CardTheme.Body,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, band + 8),
		Size = UDim2.new(1, -20, 1, -(band + 18)),
		ZIndex = 1,
	}, root)
	UIKit.corner(body, CardTheme.CardCorner)
	return { Root = root, Header = head, Title = titleLabel, Close = close, Body = body }
end

--[[
	A bright HUD pill: an icon and a word on a saturated button with a darker
	edge and a shine (the owner's phone photo: the green "Shop" with a cart).
	Returns the button.
]]
function Card.pill(parent: Instance, text: string, icon: string, color: Color3, dark: Color3, size: Vector2, props: Props?): TextButton
	local button = UIKit.new("TextButton", {
		Name = "Pill",
		AutoButtonColor = true,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size.X, size.Y),
		Text = "",
		ZIndex = 3,
	}, parent)
	UIKit.corner(button, 6)
	UIKit.new("UIStroke", { Color = dark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.51, Color3.fromRGB(226, 226, 226)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 210, 210)),
		}),
		Rotation = 90,
	}, button)
	local pic = math.floor(size.Y * 0.78)
	Card.picture(button, icon, pic, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		ZIndex = 4,
	})
	Card.text(button, text, math.floor(size.Y * 0.52), {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, pic + 14, 0.5, 0),
		Size = UDim2.new(1, -(pic + 20), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		FontFace = CardTheme.NumberFont,
		ZIndex = 4,
	})
	apply(button, props)
	return button
end

return Card
