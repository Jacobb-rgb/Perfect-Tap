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
			Size = UDim2.new(1, -10, 0.4, 0),
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

return Bubble
