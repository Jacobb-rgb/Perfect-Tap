--[[
	Bubble UI kit: the light, playful look (Config/BubbleTheme). Pure builders
	(only Instance creation), so the same code runs in the Lune preview tools.

	Every chunky element is a "body": a holder frame with a soft shadow, a darker
	lip (the 3D edge), the coloured face on top (gradient + outline) and a gloss
	strip. Tiles carry a 3D picture icon (Config/IconAssets) that pops out above
	the face, with the label over the bottom edge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local IconAssets = require(Shared.Config.IconAssets)
local UIKit = require(script.Parent.UIKit)

local Bubble = {}

export type Props = UIKit.Props
export type Role = Theme.Role

Bubble.new = UIKit.new

local function apply(instance: Instance, props: Props?)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
end

function Bubble.role(name: string): Role
	return Theme.Roles[name] or Theme.Roles.Plain
end

function Bubble.corner(parent: Instance, radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) }, parent)
end

function Bubble.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or Theme.Stroke,
		Color = color or Theme.Outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function Bubble.textStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Thickness = thickness or Theme.TextStroke,
		Color = color or Theme.Outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

function Bubble.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return UIKit.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, parent)
end

-- White text with the dark outline (the default on coloured faces).
function Bubble.text(parent: Instance, text: string, size: number, props: Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = Theme.White,
		FontFace = Theme.Font,
		TextWrapped = false,
	}, parent)
	apply(label, props)
	Bubble.textStroke(label, if size >= 26 then 3 else Theme.TextStroke)
	return label
end

-- Dark text without an outline (on white faces).
function Bubble.ink(parent: Instance, text: string, size: number, props: Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = Theme.Ink,
		FontFace = Theme.Font,
		TextWrapped = false,
	}, parent)
	apply(label, props)
	return label
end

-- A 3D picture icon (empty until the owner uploads it, see IconAssets).
function Bubble.icon(parent: Instance, name: string, size: number, props: Props?): ImageLabel
	local image = UIKit.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = IconAssets.image(name),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
	}, parent)
	image:SetAttribute("Icon", name)
	apply(image, props)
	return image
end

--[[
	The chunky body. `size` is the face size; the holder is `Theme.Lip` taller so
	the lip shows under the face. Returns the holder (place/size it in layouts)
	and the face (a TextButton when `clickable`, else a Frame) for the content.
]]
export type BodyOptions = { Name: string?, Corner: number?, Clickable: boolean?, Gloss: boolean? }

function Bubble.body(parent: Instance, role: Role, size: Vector2, opts: BodyOptions?): (Frame, GuiObject)
	local o: BodyOptions = opts or {}
	local corner = o.Corner or Theme.Corner
	local holder = UIKit.new("Frame", {
		Name = o.Name or "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y + Theme.Lip),
	}, parent)
	local shadow = UIKit.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Theme.Shadow,
		BackgroundTransparency = Theme.ShadowTransparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, Theme.Lip + 4),
		Size = UDim2.new(1, 0, 0, size.Y),
		ZIndex = 1,
	}, holder)
	Bubble.corner(shadow, corner)
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = role.Lip,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, Theme.Lip),
		Size = UDim2.new(1, 0, 0, size.Y),
		ZIndex = 1,
	}, holder)
	Bubble.corner(lip, corner)
	Bubble.stroke(lip)
	local face: GuiObject
	if o.Clickable then
		face = UIKit.new("TextButton", {
			Name = "Face",
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, size.Y),
			ZIndex = 2,
		}, holder)
	else
		face = UIKit.new("Frame", {
			Name = "Face",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, size.Y),
			ZIndex = 2,
		}, holder)
	end
	Bubble.corner(face, corner)
	Bubble.stroke(face)
	Bubble.gradient(face, role.Top, role.Base)
	if o.Gloss ~= false then
		local gloss = UIKit.new("Frame", {
			Name = "Gloss",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = Theme.GlossTransparency,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(5, 4),
			-- 40 % of short faces; tall cards and panels keep a thin strip
			Size = if size.Y > 0 and size.Y <= 90 then UDim2.new(1, -10, 0.4, 0) else UDim2.new(1, -10, 0, 30),
			ZIndex = 2,
		}, face)
		Bubble.corner(gloss, math.max(4, corner - 5))
	end
	return holder, face
end

-- Small red notification badge on the top-right corner of a face.
function Bubble.badge(face: GuiObject, text: string): Frame
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 5,
	}, face)
	Bubble.corner(badge, 14)
	Bubble.stroke(badge, 3)
	Bubble.text(badge, text, 18, { Size = UDim2.fromScale(1, 1), ZIndex = 6 })
	return badge
end

export type TileOptions = {
	Name: string,
	Label: string,
	Icon: string,
	Role: string,
	Size: number,
	Badge: string?,
	LayoutOrder: number?,
}

-- Square menu tile: icon popping out on top, label over the bottom edge.
function Bubble.tile(parent: Instance, o: TileOptions): (TextButton, Frame)
	local s = o.Size
	local holder, face = Bubble.body(parent, Bubble.role(o.Role), Vector2.new(s, s), { Name = o.Name, Clickable = true })
	holder.LayoutOrder = o.LayoutOrder or 0
	Bubble.icon(face, o.Icon, math.floor(s * 0.86), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -math.floor(s * 0.16)),
	})
	Bubble.text(face, o.Label, math.floor(s * 0.2), {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.new(1, -6, 0, math.floor(s * 0.25)),
		TextScaled = true,
		ZIndex = 4,
	})
	if o.Badge then
		Bubble.badge(face, o.Badge)
	end
	return face :: TextButton, holder
end

-- A role from one data colour (rarity, capsule shell): lighter top, darker lip.
function Bubble.roleFrom(base: Color3): Role
	local h, sat, v = base:ToHSV()
	return {
		Top = Color3.fromHSV(h, sat * 0.55, math.min(1, v * 1.08 + 0.1)),
		Base = base,
		Lip = Color3.fromHSV(h, math.min(1, sat * 1.05 + 0.05), v * 0.6),
	}
end

local function roleOf(r: string | Role): Role
	if type(r) == "string" then
		return Bubble.role(r)
	end
	return r
end

-- Rough width of a text line (design units) for rows that centre an icon + text.
function Bubble.textWidth(text: string, size: number): number
	return math.ceil(#text * size * 0.56)
end

-- A centred row: a 3D icon and a text (prices: coin or Robux + amount).
function Bubble.iconText(parent: Instance, icon: string, text: string, size: number, props: Props?, ink: boolean?): Frame
	local row = UIKit.new("Frame", {
		Name = "IconText",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 6),
		ZIndex = 4,
	}, parent)
	apply(row, props)
	UIKit.list(row, Enum.FillDirection.Horizontal, 3, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	Bubble.icon(row, icon, size + 8, { LayoutOrder = 1, ZIndex = 5 })
	local textProps: Props = {
		Name = "Text",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Bubble.textWidth(text, size), size + 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}
	if ink then
		Bubble.ink(row, text, size, textProps)
	else
		Bubble.text(row, text, size, textProps)
	end
	return row
end

export type ButtonOptions = {
	Name: string?,
	Text: string,
	Role: string | Role,
	Size: Vector2,
	Icon: string?, -- 3D icon left of the text
	Price: string?, -- second line (with PriceIcon)
	PriceIcon: string?,
	TextSize: number?,
	Corner: number?,
	LayoutOrder: number?,
}

-- Chunky button; with a Price the text sits on top and the price row under it.
function Bubble.button(parent: Instance, o: ButtonOptions): (TextButton, Frame)
	local holder, face = Bubble.body(parent, roleOf(o.Role), o.Size, {
		Name = o.Name or o.Text,
		Corner = o.Corner or 16,
		Clickable = true,
	})
	holder.LayoutOrder = o.LayoutOrder or 0
	local ts = o.TextSize or 24
	if o.Price then
		Bubble.text(face, o.Text, ts, {
			Name = "Label",
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0.5, -2),
			ZIndex = 4,
		})
		Bubble.iconText(face, o.PriceIcon or "coin", o.Price, math.floor(ts * 0.86), {
			Name = "Price",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -6),
		})
	elseif o.Icon then
		local iconSize = math.floor(o.Size.Y * 0.95)
		Bubble.icon(face, o.Icon, iconSize, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, -3),
		})
		Bubble.text(face, o.Text, ts, {
			Name = "Label",
			Position = UDim2.fromOffset(iconSize, 0),
			Size = UDim2.new(1, -iconSize - 8, 1, 0),
			ZIndex = 4,
		})
	else
		Bubble.text(face, o.Text, ts, { Name = "Label", Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	end
	return face :: TextButton, holder
end

-- Flat pill with text (chances, counters): white with ink text unless a role is given.
function Bubble.chip(parent: Instance, text: string, size: Vector2, textSize: number, role: (string | Role)?, props: Props?): Frame
	local r = if role then roleOf(role) else nil
	local chip = UIKit.new("Frame", {
		Name = "Chip",
		BackgroundColor3 = if r then r.Base else Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 4,
	}, parent)
	apply(chip, props)
	Bubble.corner(chip, size.Y // 2)
	Bubble.stroke(chip, 2.5)
	if r then
		Bubble.text(chip, text, textSize, { Name = "Text", Size = UDim2.fromScale(1, 1), ZIndex = 5 })
	else
		Bubble.ink(chip, text, textSize, { Name = "Text", Size = UDim2.fromScale(1, 1), ZIndex = 5 })
	end
	return chip
end

export type WindowOptions = {
	Name: string,
	Title: string,
	Icon: string,
	Role: string,
	Size: Vector2,
	HeaderHeight: number?,
	TitleSize: number?,
}

export type Window = {
	Holder: Frame,
	Panel: GuiObject,
	Header: Frame,
	Title: TextLabel,
	Body: Frame,
	Close: TextButton,
}

Bubble.WindowCorner = 26

--[[
	A window: white panel (lip + shadow), a header band in the window's own
	colour with a 3D icon popping out on the left, the title, and a red X on the
	top-right corner. Centred on its parent; content goes into Body (padded).
]]
function Bubble.window(parent: Instance, o: WindowOptions): Window
	local hh = o.HeaderHeight or 68
	local role = Bubble.role(o.Role)
	local holder, panel = Bubble.body(parent, Bubble.role("Plain"), o.Size, {
		Name = o.Name,
		Corner = Bubble.WindowCorner,
		Gloss = false,
	})
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	local header = UIKit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, hh),
		ZIndex = 3,
	}, panel)
	Bubble.corner(header, Bubble.WindowCorner)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, role.Top),
			ColorSequenceKeypoint.new(0.5, role.Base),
			ColorSequenceKeypoint.new(1, role.Base),
		}),
		Rotation = 90,
	}, header)
	UIKit.new("Frame", {
		Name = "Fill", -- squares the header's bottom corners
		BackgroundColor3 = role.Base,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.5),
		ZIndex = 3,
	}, header)
	UIKit.new("Frame", {
		Name = "Line",
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = 3,
	}, header)
	local gloss = UIKit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 5),
		Size = UDim2.new(1, -20, 0.36, 0),
		ZIndex = 3,
	}, header)
	Bubble.corner(gloss, 12)
	local iconSize = hh + 34
	Bubble.icon(header, o.Icon, iconSize, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, -12),
		ZIndex = 5,
	})
	local title = Bubble.text(header, o.Title, o.TitleSize or 38, {
		Name = "Title",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(iconSize + 8, 4),
		Size = UDim2.new(1, -iconSize - 90, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local close, closeHolder = Bubble.button(panel, { Name = "Close", Text = "X", Role = "Danger", Size = Vector2.new(54, 54), TextSize = 32, Corner = 16 })
	closeHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	closeHolder.Position = UDim2.new(1, -12, 0, 10)
	closeHolder.ZIndex = 6
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, hh + 3),
		Size = UDim2.new(1, 0, 1, -hh - 3),
		ZIndex = 2,
	}, panel)
	UIKit.padding(body, 16)
	return { Holder = holder, Panel = panel, Header = header, Title = title, Body = body, Close = close }
end

export type CardOptions = {
	Name: string,
	Label: string,
	Icon: string,
	Color: Color3, -- rarity / data colour of the card face
	Chip: string, -- the pill on the bottom edge (chance, value, level)
	ChipRole: (string | Role)?, -- coloured chip (else white with ink text)
	Badge: string?,
	Size: Vector2,
	NameSize: number,
	ChipSize: number,
	Selected: boolean?,
	LayoutOrder: number?,
}

-- Grid card: 3D icon popping out of the top, the name, a chip on the bottom edge.
function Bubble.card(parent: Instance, o: CardOptions): (TextButton, Frame)
	local size = o.Size
	local holder, face = Bubble.body(parent, Bubble.roleFrom(o.Color), Vector2.new(size.X, size.Y - Theme.Lip), {
		Name = o.Name,
		Corner = 16,
		Clickable = true,
	})
	holder.LayoutOrder = o.LayoutOrder or 0
	local iconSize = math.floor(size.X * 0.66)
	Bubble.icon(face, o.Icon, iconSize, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -12),
	})
	Bubble.text(face, o.Label, o.NameSize, {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(o.ChipSize + 8) // 2 - 3),
		Size = UDim2.new(1, -8, 0, o.NameSize + 2),
		TextScaled = true,
		ZIndex = 4,
	})
	Bubble.chip(face, o.Chip, Vector2.new(math.floor(size.X * 0.66), o.ChipSize + 8), o.ChipSize, o.ChipRole, {
		Name = "Chance",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
	})
	if o.Badge then
		Bubble.badge(face, o.Badge)
	end
	if o.Selected then
		Bubble.select(face, true)
	end
	return face :: TextButton, holder
end

-- Gold outline on the selected tab / card / slot (false = the plain outline).
function Bubble.select(face: GuiObject, selected: boolean)
	local stroke = face:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then Theme.Gold else Theme.Outline
		stroke.Thickness = if selected then 5 else Theme.Stroke
	end
end

export type Tab = { Id: string, Label: string, Icon: string, Role: (string | Role)? }

-- A row of tabs: the selected one in its colour with a gold outline, the rest plain.
function Bubble.tabs(parent: Instance, tabs: { Tab }, selected: string, size: Vector2, textSize: number, props: Props?): { [string]: TextButton }
	local row = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size.Y + Theme.Lip),
	}, parent)
	apply(row, props)
	UIKit.list(row, Enum.FillDirection.Horizontal, 12)
	local out = {}
	for i, tab in tabs do
		local on = tab.Id == selected
		local face = Bubble.button(row, {
			Name = tab.Id,
			Text = tab.Label,
			Role = if on then (tab.Role or "Plain") else "Plain",
			Size = size,
			Icon = tab.Icon,
			TextSize = textSize,
			LayoutOrder = i,
		})
		if on then
			Bubble.select(face, true)
		else
			local label = face:FindFirstChild("Label") :: TextLabel
			label.TextColor3 = Theme.InkSoft
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = false
				stroke.Transparency = 1
			end
		end
		out[tab.Id] = face
	end
	return out
end

-- An inner panel (light tint, outlined, no lip) filling `size` (UDim2) at `position`.
function Bubble.inset(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local frame = UIKit.new("Frame", {
		Name = name,
		BackgroundColor3 = Theme.PanelTint,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		ZIndex = 2,
	}, parent)
	Bubble.corner(frame, 20)
	Bubble.stroke(frame, 3)
	return frame
end

-- A scrolling grid of cards inside `parent` (room on top for the popping icons).
function Bubble.grid(parent: Instance, cell: Vector2, gap: Vector2, props: Props?): ScrollingFrame
	local scroll = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.InkSoft,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		ZIndex = 3,
	}, parent)
	apply(scroll, props)
	local pad = UIKit.padding(scroll, 4)
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 18)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap.X, gap.Y),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	return scroll
end

return Bubble
