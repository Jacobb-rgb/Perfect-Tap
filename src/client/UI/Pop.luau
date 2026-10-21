--[[
	The bright "Pop" UI kit (Config/PopTheme): the owner's egg-game photos
	(2026-10-20 evening). Pure builders (only Instance creation), so the Lune
	previews run them too.

	  text      white chunky text with a black edge
	  title     a heading in a gradient (PopTheme.Titles) with a black edge
	  heading   "-- PASSES --": a section heading across a list
	  face      paints a frame / button: the gradient, the black border and a
	            glossy top half
	  button    a painted button with a word on it
	  price     the green Robux button ("99" with the robux mark)
	  close     the red square X
	  window    the bright header band (diagonal shine stripes, the title on
	            the left, the X on the right) over a dark grey body
	  card      a painted card with light rays behind its picture
	  rays      light rays from a point (cards, the wheel, banners)
	  tag       a small label box ("New!", "OWNED")
	  ribbon    a tilted gold "BEST VALUE!" ribbon on a card's corner
	  check     the Fast Spin checkbox
	  model     a 3D picture: a ViewportFrame showing a model (the game) inside
	            an ImageLabel whose Icon attribute names the preview picture
	  tile      a left HUD tile: a painted square, the icon inside, the word
	            at the bottom

	No emoji anywhere (owner: "bez emoji, jenom text").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local UIKit = require(script.Parent.UIKit)

local Pop = {}

type Props = { [string]: any }
export type Paint = PopTheme.Paint

local function apply(instance: Instance, props: Props?)
	if props then
		local target: any = instance
		for key, value in props do
			target[key] = value
		end
	end
end

-- A paint by name (PopTheme.Paints) or the paint itself.
function Pop.paint(name: string | Paint): Paint
	if type(name) == "table" then
		return name
	end
	return PopTheme.Paints[name] or PopTheme.Paints.Slate
end

-- The black edge thickness for a text size.
function Pop.edgeFor(size: number): number
	return if size >= 44 then 4 elseif size >= 26 then 3 elseif size >= 20 then 2.5 else 1.6
end

-- A black edge around a text's glyphs.
function Pop.edge(label: GuiObject, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = PopTheme.Outline,
		Thickness = thickness or 2.5,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
end

-- A black border around a frame.
function Pop.border(frame: GuiObject, thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Name = "Border",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or PopTheme.Outline,
		Thickness = thickness or PopTheme.Edge,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, frame)
end

--[[
	The "glow" pieces (owner 2026-10-21: "everything must glow, light edges,
	cool backgrounds", his Roblox shop photos):
	  rim      a light line just inside a face's black border
	  studs    the raised-stud texture over a face (IconAssets ui_studs; only
	           once uploaded, nothing before)
	  fx       a soft texture: rays, glow, sparkle, shine (IconAssets ui_fx);
	           the kit draws frame stand-ins until it is uploaded
	  shadow   a dark copy under a static title (the photos' 3D titles)
]]
function Pop.rim(frame: GuiObject, color: Color3, corner: number, inset: number?, z: number?): Frame
	local old = frame:FindFirstChild("Rim")
	if old then
		old:Destroy()
	end
	local i = inset or 3
	local rim = UIKit.new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(i, i),
		Size = UDim2.new(1, -2 * i, 1, -2 * i),
		ZIndex = z or frame.ZIndex,
	}, frame)
	UIKit.corner(rim, math.max(2, corner - i))
	UIKit.new("UIStroke", {
		Name = "Light",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = 2.5,
		Transparency = 0.05,
	}, rim)
	return rim
end

-- The stud texture over a face (tiles of `tile` units); nil until it is uploaded.
function Pop.studs(frame: GuiObject, corner: number, transparency: number?, tile: number?, z: number?): ImageLabel?
	if not IconAssets.textureShows("ui_studs") then
		return nil
	end
	local studs = UIKit.new("ImageLabel", {
		Name = "Studs",
		BackgroundTransparency = 1,
		ImageTransparency = transparency or 0,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile or 40, tile or 40),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or frame.ZIndex,
	}, frame)
	IconAssets.applyTexture(studs, "ui_studs")
	UIKit.corner(studs, corner)
	return studs
end

-- A soft texture picture (fx_rays / fx_glow / fx_sparkle / fx_shine), nil when it won't show.
function Pop.fx(parent: Instance, name: string, props: Props?): ImageLabel?
	if not IconAssets.textureShows(name) then
		return nil
	end
	local image = UIKit.new("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 2,
	}, parent)
	IconAssets.applyTexture(image, name)
	apply(image, props)
	return image
end

-- A four-point sparkle (the fx_sparkle texture, or two thin turned frames before it is uploaded).
function Pop.sparkle(parent: Instance, at: UDim2, size: number, z: number?, transparency: number?)
	local t = transparency or 0.1
	local made = Pop.fx(parent, "fx_sparkle", {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = t,
		Position = at,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z or 3,
	})
	if made then
		return
	end
	for i, rot in { 0, 90 } do
		local bar = UIKit.new("Frame", {
			Name = "Sparkle" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = t,
			BorderSizePixel = 0,
			Position = at,
			Rotation = rot + 45,
			Size = UDim2.fromOffset(math.max(2, math.floor(size * 0.14)), math.floor(size * 0.7)),
			ZIndex = z or 3,
		}, parent)
		UIKit.corner(bar, 999)
	end
end

-- A dark copy just under a static title: the photos' chunky 3D titles.
function Pop.shadow(label: TextLabel, offset: number?): TextLabel
	local parent = label.Parent :: Instance
	local shade = UIKit.new("TextLabel", {
		Name = label.Name .. "Shadow",
		AnchorPoint = label.AnchorPoint,
		BackgroundTransparency = 1,
		FontFace = label.FontFace,
		Position = label.Position + UDim2.fromOffset(0, offset or 4),
		Rotation = label.Rotation,
		Size = label.Size,
		Text = label.Text,
		TextColor3 = PopTheme.Outline,
		TextScaled = label.TextScaled,
		TextSize = label.TextSize,
		TextTransparency = 0.35,
		TextWrapped = label.TextWrapped,
		TextXAlignment = label.TextXAlignment,
		TextYAlignment = label.TextYAlignment,
		Visible = label.Visible,
		ZIndex = math.max(1, label.ZIndex - 1),
	}, parent)
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	UIKit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = PopTheme.Outline,
		Thickness = if edge then edge.Thickness else 3,
		Transparency = 0.35,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, shade)
	return shade
end

-- White chunky text with a black edge.
function Pop.text(parent: Instance, text: string, size: number, props: Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 6),
		FontFace = PopTheme.Font,
		Text = text,
		TextSize = size,
		TextColor3 = PopTheme.Ink,
		TextWrapped = false,
		ZIndex = 4,
	}, parent)
	Pop.edge(label, Pop.edgeFor(size))
	apply(label, props)
	return label
end

-- A heading in a PopTheme.Titles gradient (top -> bottom) with a black edge.
function Pop.title(parent: Instance, text: string, size: number, colors: string | { Color3 }, props: Props?): TextLabel
	local keys = if type(colors) == "table" then colors else (PopTheme.Titles[colors] or PopTheme.Titles.White)
	local label = Pop.text(parent, text, size, { Name = "Title" })
	UIKit.new("UIGradient", { Color = ColorSequence.new(keys[1], keys[#keys]), Rotation = 90 }, label)
	apply(label, props)
	return label
end

-- "-- PASSES --": a section heading `width` wide.
function Pop.heading(parent: Instance, text: string, colors: string, size: number, props: Props?): TextLabel
	local heading = Pop.title(parent, "-- " .. text .. " --", size, colors, {
		Name = "Heading",
		FontFace = PopTheme.Heavy,
		Size = UDim2.new(1, 0, 0, size + 14),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	apply(heading, props)
	heading.ZIndex = math.max(heading.ZIndex, 5)
	Pop.shadow(heading)
	return heading
end

-- The two-tone gradient of a face: `paint` top -> bottom with a glossy step
-- at the middle (the photos' buttons).
local function faceGradient(paint: Paint, glossy: boolean?): ColorSequence
	if glossy == false then
		return ColorSequence.new(paint.Top, paint.Bottom)
	end
	local mid = paint.Top:Lerp(paint.Bottom, 0.42)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, paint.Top),
		ColorSequenceKeypoint.new(0.48, mid),
		ColorSequenceKeypoint.new(0.52, mid:Lerp(paint.Bottom, 0.35)),
		ColorSequenceKeypoint.new(1, paint.Bottom),
	})
end

--[[
	Paints `frame` (a Frame or a button): white background (the gradient
	gives the colour: it multiplies), rounded corners, the black border.
	Returns the gradient (callers recolour it: Pop.repaint).
]]
function Pop.face(frame: GuiObject, paint: string | Paint, corner: number?, glossy: boolean?, rim: boolean?): UIGradient
	local p = Pop.paint(paint)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	if not frame:FindFirstChildOfClass("UICorner") then
		UIKit.corner(frame, corner or PopTheme.Corner)
	end
	if not frame:FindFirstChild("Border") then
		Pop.border(frame)
	end
	local gradient = frame:FindFirstChild("Paint") :: UIGradient?
	if not gradient then
		gradient = UIKit.new("UIGradient", { Name = "Paint", Rotation = 90 }, frame)
	end
	local g = gradient :: UIGradient
	g.Color = faceGradient(p, glossy)
	-- the light edge just inside the black border
	if rim ~= false then
		Pop.rim(frame, Pop.rimColor(p), corner or PopTheme.Corner, 3, frame.ZIndex)
	end
	return g
end

-- A paint's light edge: its top colour lifted toward white.
function Pop.rimColor(paint: Paint): Color3
	return paint.Top:Lerp(Color3.new(1, 1, 1), 0.45)
end

-- Recolours a painted frame (a button that turns grey, a selected tab).
function Pop.repaint(frame: GuiObject, paint: string | Paint, glossy: boolean?)
	local p = Pop.paint(paint)
	local gradient = frame:FindFirstChild("Paint") :: UIGradient?
	if gradient then
		gradient.Color = faceGradient(p, glossy)
	end
	local rim = frame:FindFirstChild("Rim")
	local light = if rim then rim:FindFirstChild("Light") else nil
	if light and light:IsA("UIStroke") then
		light.Color = Pop.rimColor(p)
	end
end

-- A painted button with `text` on it. Returns the button (its label is "Label").
function Pop.button(parent: Instance, text: string, paint: string | Paint, size: Vector2, props: Props?): TextButton
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromOffset(size.X, size.Y),
		Selectable = true,
		ZIndex = 4,
	}, parent)
	Pop.face(button, paint)
	Pop.studs(button, PopTheme.Corner, 0.45, 28, 4)
	Pop.text(button, text, math.floor(math.min(size.Y * 0.56, 40)), {
		Name = "Label",
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(5, 0),
		TextScaled = false,
		ZIndex = 5,
	})
	apply(button, props)
	return button
end

-- About how wide a word is in the chunky font (design units).
function Pop.textWidth(text: string, size: number): number
	return math.ceil(utf8.len(text) or #text) * size * 0.6 + 4
end

--[[
	The green Robux button: the robux mark and the price, centred. `robux`
	nil shows `text` instead (Coming soon / OWNED). Returns the button; its
	parts are "Mark" and "Amount".
]]
function Pop.price(parent: Instance, robux: number?, size: Vector2, props: Props?, text: string?): TextButton
	local button = UIKit.new("TextButton", {
		Name = "Price",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromOffset(size.X, size.Y),
		Selectable = true,
		ZIndex = 4,
	}, parent)
	Pop.face(button, PopTheme.Price)
	Pop.studs(button, PopTheme.Corner, 0.45, 28, 4)
	local row = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}, button)
	UIKit.list(row, Enum.FillDirection.Horizontal, 4, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local textSize = math.floor(math.min(size.Y * 0.62, 44))
	local mark = UIKit.new("ImageLabel", {
		Name = "Mark",
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(textSize + 2, textSize + 2),
		ZIndex = 6,
	}, row)
	IconAssets.apply(mark, "robux")
	mark:SetAttribute("Icon", "robux")
	local words = if robux then tostring(robux) else (text or "")
	Pop.text(row, words, textSize, {
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Pop.textWidth(words, textSize), textSize + 6),
		ZIndex = 6,
	})
	mark.Visible = robux ~= nil
	apply(button, props)
	return button
end

-- Sets a price button's amount (nil: `text` without the mark).
function Pop.setPrice(button: GuiObject, robux: number?, text: string?)
	local row = button:FindFirstChild("Row")
	if not row then
		return
	end
	local mark = row:FindFirstChild("Mark") :: ImageLabel?
	local amount = row:FindFirstChild("Amount") :: TextLabel?
	local words = if robux then tostring(robux) else (text or "")
	if mark then
		mark.Visible = robux ~= nil
	end
	if amount then
		amount.Text = words
		amount.Size = UDim2.fromOffset(Pop.textWidth(words, amount.TextSize), amount.Size.Y.Offset)
	end
end

-- The red square X. Returns the button.
function Pop.close(parent: Instance, size: number, props: Props?): TextButton
	local button = UIKit.new("TextButton", {
		Name = "Close",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromOffset(size, size),
		Selectable = true,
		ZIndex = 6,
	}, parent)
	Pop.face(button, PopTheme.Close, 4)
	Pop.text(button, "X", math.floor(size * 0.66), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		FontFace = PopTheme.Heavy,
		ZIndex = 7,
	})
	apply(button, props)
	return button
end

export type Window = {
	Root: Frame,
	Header: Frame,
	Title: TextLabel,
	Close: TextButton,
	Body: Frame,
}

--[[
	A window: a bright header band (`paint`, green by default) with diagonal
	shine stripes, the title on the left and the red X on the right, over a
	dark grey body. `size` in design units; `band` the header's height.
]]
function Pop.window(parent: Instance, title: string, size: Vector2, band: number?, paint: (string | Paint)?): Window
	local h = band or 76
	local root = UIKit.new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Active = true,
		ZIndex = 1,
	}, parent)
	UIKit.corner(root, PopTheme.WindowCorner)
	Pop.border(root, 4)

	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, h),
		Size = UDim2.new(1, -8, 1, -(h + 4)),
		ZIndex = 1,
	}, root)
	UIKit.corner(body, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, body)
	-- the body's studs (the photos' dark studded floor) and a shade under the header
	Pop.studs(body, 4, 0.5, 36, 1)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 1,
	}, body)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.45, 1),
	}, shade)

	local head = UIKit.new("Frame", {
		Name = "Header",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, h - 8),
		ClipsDescendants = true,
		ZIndex = 2,
	}, root)
	Pop.face(head, paint or "Green", 4, false)
	local headBorder = head:FindFirstChild("Border") :: UIStroke
	headBorder.Thickness = 3
	Pop.studs(head, 4, 0.35, 40, 3)
	-- the shine: a light top strip and wide diagonal stripes
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 2,
	}, head)
	local stripes = { { 0.62, 46 }, { 0.70, 22 }, { 0.80, 14 } }
	for i, s in stripes do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 0, h * 2.4),
			ZIndex = 2,
		}, head)
	end
	local titleLabel = Pop.text(head, title, math.floor(h * 0.6), {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.new(1, -(h + 30), 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	Pop.shadow(titleLabel)
	local x = math.floor(h * 0.82)
	local close = Pop.close(root, x, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, math.floor(h / 2)),
	})
	return { Root = root, Header = head, Title = titleLabel, Close = close, Body = body }
end

--[[
	Light rays from `center` (scale of the parent): `count` long thin bars
	that fade toward the middle, under everything else (ZIndex `z`). The
	parent should clip (ClipsDescendants).
]]
function Pop.rays(parent: Instance, center: UDim2, count: number, length: number, transparency: number?, z: number?): Frame
	local holder = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = center,
		Size = UDim2.fromOffset(length * 2, length * 2),
		ZIndex = z or 2,
	}, parent)
	local fade = transparency or 0.6
	for i = 1, count do
		local ray = UIKit.new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * (180 / count),
			Size = UDim2.fromOffset(length * 2, math.max(6, math.floor(length * 0.16))),
			ZIndex = z or 2,
		}, holder)
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, fade),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(0.7, fade),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
	end
	return holder
end

--[[
	A painted card: the paint, light rays behind where the picture goes
	(`rayCenter`, default upper middle), the black border. It clips its
	rays. Children go on top (ZIndex 4+). Returns the button.
]]
function Pop.card(parent: Instance, paint: string | Paint, props: Props?, rayCenter: UDim2?): TextButton
	local button = UIKit.new("TextButton", {
		Name = "Card",
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		Selectable = true,
		ZIndex = 2,
	}, parent)
	Pop.face(button, paint, PopTheme.Corner, false)
	apply(button, props)
	local p = Pop.paint(paint)
	local size = button.Size
	local short = math.min(size.X.Offset, size.Y.Offset)
	local long = math.max(size.X.Offset, size.Y.Offset, 120)
	local centre = rayCenter or UDim2.fromScale(0.5, 0.4)
	-- the light burst behind the picture: the rays texture (or bars), a big soft glow
	local rays = Pop.fx(button, "fx_rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 0.35,
		Position = centre,
		Size = UDim2.fromOffset(long * 2.2, long * 2.2),
		ZIndex = 2,
	})
	if not rays then
		Pop.rays(button, centre, 10, long, 0.6, 2)
	end
	local glow = Pop.fx(button, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = p.Top:Lerp(Color3.new(1, 1, 1), 0.6),
		ImageTransparency = 0.3,
		Position = centre,
		Size = UDim2.fromOffset(math.floor(short * 1.1), math.floor(short * 1.1)),
		ZIndex = 2,
	})
	if not glow then
		for i, k in { 0.62, 0.42 } do
			local disc = UIKit.new("Frame", {
				Name = "Glow" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = if i == 1 then 0.8 else 0.7,
				BorderSizePixel = 0,
				Position = centre,
				Size = UDim2.fromOffset(math.floor(short * k), math.floor(short * k)),
				ZIndex = 2,
			}, button)
			UIKit.corner(disc, 999)
		end
	end
	-- the studs over the paint, then the light edge on top of them
	Pop.studs(button, PopTheme.Corner, 0.5, 44, 3)
	local rim = button:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	-- a few sparkles around the picture (fixed spots per card size: the same every build)
	local seed = (size.X.Offset * 31 + size.Y.Offset * 17) % 997 + 1
	local function next01(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for _ = 1, 3 do
		local sx = 0.12 + next01() * 0.76
		local sy = 0.08 + next01() * 0.5
		Pop.sparkle(button, UDim2.fromScale(sx, sy), math.floor(14 + next01() * 14), 3, 0.15 + next01() * 0.3)
	end
	return button
end

-- A rainbow paint across a frame (left -> right), replacing its paint.
function Pop.rainbow(frame: GuiObject)
	local keys = {}
	for i, color in PopTheme.Rainbow do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#PopTheme.Rainbow - 1), color))
	end
	local gradient = frame:FindFirstChild("Paint") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(keys)
		gradient.Rotation = 0
	end
end

-- A small label box ("New!", "OWNED"): white text on `paint`.
function Pop.tag(parent: Instance, text: string, paint: string | Paint, size: Vector2, props: Props?): Frame
	local frame = UIKit.new("Frame", {
		Name = "Tag",
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 6,
	}, parent)
	Pop.face(frame, paint, 4)
	Pop.text(frame, text, math.floor(size.Y * 0.66), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
	})
	apply(frame, props)
	return frame
end

-- The tilted gold "BEST VALUE!" ribbon over a card's top-right corner.
function Pop.ribbon(parent: Instance, text: string, width: number): Frame
	local ribbon = Pop.tag(parent, text, "Yellow", Vector2.new(width, 30), {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 12),
		Rotation = 8,
		ZIndex = 8,
	})
	local label = ribbon:FindFirstChild("Label") :: TextLabel
	label.TextColor3 = Color3.fromRGB(40, 30, 10)
	local edge = label:FindFirstChild("Edge") :: UIStroke
	edge.Color = Color3.new(1, 1, 1)
	edge.Thickness = 1.5
	label.ZIndex = 9
	return ribbon
end

-- The checkbox (Fast Spin): a dark square with a green tick when on.
function Pop.check(parent: Instance, on: boolean, size: number, props: Props?): TextButton
	local box = UIKit.new("TextButton", {
		Name = "Check",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromOffset(size, size),
		Selectable = true,
		ZIndex = 4,
	}, parent)
	Pop.face(box, if on then "Green" else "Slate", 6)
	Pop.text(box, "", math.floor(size * 0.8), {
		Name = "Tick",
		Size = UDim2.fromScale(1, 1),
		FontFace = PopTheme.Heavy,
		ZIndex = 5,
	})
	Pop.setCheck(box, on)
	apply(box, props)
	return box
end

function Pop.setCheck(box: GuiObject, on: boolean)
	Pop.repaint(box, if on then "Green" else "Slate")
	local tick = box:FindFirstChild("Tick") :: TextLabel?
	if tick then
		tick.Text = if on then "V" else ""
	end
	box:SetAttribute("On", on)
end

--[[
	A 3D picture `size` design units square: an ImageLabel named "Picture"
	(attribute Icon = `icon`: the preview renders that picture) holding a
	ViewportFrame "View" that shows `model` in the game. The camera looks at
	the model's bounds from `from` (a direction; default front-left, a bit
	from above). `model` nil leaves the view empty (filled later: Pop.show).
]]
function Pop.model(parent: Instance, icon: string, size: number, model: Model?, props: Props?, from: Vector3?): ImageLabel
	local picture = UIKit.new("ImageLabel", {
		Name = "Picture",
		BackgroundTransparency = 1,
		Image = "",
		Size = UDim2.fromOffset(size, size),
		ZIndex = 4,
	}, parent)
	picture:SetAttribute("Icon", icon)
	local view = UIKit.new("ViewportFrame", {
		Name = "View",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 4,
	}, picture)
	apply(picture, props)
	if model then
		Pop.show(view, model, from)
	end
	return picture
end

-- The bounds (center, radius) of every part in a model.
local function bounds(model: Instance): (Vector3, number)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local cf = part.CFrame
			local half = part.Size * 0.5
			for _, corner in {
				Vector3.new(half.X, half.Y, half.Z),
				Vector3.new(-half.X, half.Y, half.Z),
				Vector3.new(half.X, -half.Y, half.Z),
				Vector3.new(half.X, half.Y, -half.Z),
				Vector3.new(-half.X, -half.Y, half.Z),
				Vector3.new(-half.X, half.Y, -half.Z),
				Vector3.new(half.X, -half.Y, -half.Z),
				Vector3.new(-half.X, -half.Y, -half.Z),
			} do
				local at = cf * corner
				lo = Vector3.new(math.min(lo.X, at.X), math.min(lo.Y, at.Y), math.min(lo.Z, at.Z))
				hi = Vector3.new(math.max(hi.X, at.X), math.max(hi.Y, at.Y), math.max(hi.Z, at.Z))
			end
		end
	end
	if lo.X > hi.X then
		return Vector3.zero, 1
	end
	return (lo + hi) * 0.5, math.max(0.5, (hi - lo).Magnitude * 0.5)
end

-- Puts `model` in a ViewportFrame with a camera that frames it.
function Pop.show(view: ViewportFrame, model: Model, from: Vector3?)
	for _, old in view:GetChildren() do
		if old:IsA("Model") or old:IsA("Camera") then
			old:Destroy()
		end
	end
	model.Parent = view
	local center, radius = bounds(model)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local dir = (from or Vector3.new(-0.55, 0.42, -1)).Unit
	local at = center + dir * (radius / math.sin(math.rad(15)) * 0.95)
	camera.CFrame = CFrame.lookAt(at, center)
	camera.Parent = view
	pcall(function()
		view.CurrentCamera = camera
	end)
end

--[[
	A bright HUD pill: a picture and a word ("Shop" with the cart, the owner's
	photo). With no uploaded picture the word fills the pill (no emoji).
	Returns the button.
]]
function Pop.pill(parent: Instance, text: string, icon: string, paint: string | Paint, size: Vector2, props: Props?): TextButton
	local button = UIKit.new("TextButton", {
		Name = "Pill",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromOffset(size.X, size.Y),
		Selectable = true,
		ZIndex = 3,
	}, parent)
	Pop.face(button, paint)
	Pop.studs(button, PopTheme.Corner, 0.45, 28, 3)
	local pic = math.floor(size.Y * 0.84)
	local shows = IconAssets.shows(icon)
	local image = UIKit.new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 6, 0.5, 0),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(pic, pic),
		Visible = shows,
		ZIndex = 4,
	}, button)
	IconAssets.apply(image, icon)
	image:SetAttribute("Icon", icon)
	local left = if shows then pic + 10 else 8
	Pop.text(button, text, math.floor(size.Y * 0.56), {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, left, 0.5, 0),
		Size = UDim2.new(1, -(left + 8), 1, 0),
		TextXAlignment = if shows then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	apply(button, props)
	return button
end

export type TileSpec = {
	Name: string,
	Label: string,
	Icon: string,
	Paint: string | Paint,
	Size: number,
	LayoutOrder: number?,
}

--[[
	A left HUD tile (the owner's tile photo): a painted rounded square, the
	icon inside it, the word in white with a black edge at the bottom. With no
	uploaded picture the word sits in the middle, bigger (no emoji). Returns
	the button (its Parent is the holder frame, like Bubble.tile's).
]]
function Pop.tile(parent: Instance, o: TileSpec): (TextButton, Frame)
	local s = o.Size
	local holder = UIKit.new("Frame", {
		Name = o.Name,
		BackgroundTransparency = 1,
		LayoutOrder = o.LayoutOrder or 0,
		Size = UDim2.fromOffset(s, s),
	}, parent)
	local face = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Selectable = true,
		ZIndex = 2,
	}, holder)
	Pop.face(face, o.Paint, 10)
	Pop.studs(face, 10, 0.45, 30, 2)
	-- a lighter inner rim (the photo's tiles)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(5, 4),
		Size = UDim2.new(1, -10, 0.4, 0),
		ZIndex = 2,
	}, face)
	local icon = UIKit.new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, math.floor(s * 0.04)),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(math.floor(s * 0.74), math.floor(s * 0.74)),
		ZIndex = 3,
	}, face)
	IconAssets.apply(icon, o.Icon)
	icon:SetAttribute("Icon", o.Icon)
	local hasPicture = IconAssets.shows(o.Icon)
	icon.Visible = hasPicture
	Pop.text(face, o.Label, math.floor(s * (if hasPicture then 0.2 else 0.26)), {
		Name = "Label",
		AnchorPoint = if hasPicture then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5),
		Position = if hasPicture then UDim2.new(0.5, 0, 1, -2) else UDim2.fromScale(0.5, 0.5),
		-- (relative to the tile: the word grows when a layout makes the tile bigger)
		Size = if hasPicture then UDim2.new(1, -6, 0.26, 0) else UDim2.new(1, -8, 0.34, 0),
		TextScaled = true,
		ZIndex = 4,
	})
	face:SetAttribute("NoPicture", not hasPicture)
	return face :: TextButton, holder
end

--[[
	Window kit (owner 2026-10-21: "every window new, modern, colourful,
	clean items, Roblox style"): the pieces every window is rebuilt from.
	  rarityPaint  a bright paint per rarity (Common slate .. Mythic pink)
	  coinButton   the gold coin-price button (a drawn coin, the amount)
	  tabs         a row of bright tabs: the picked one painted, the rest slate
	  chip         a small round label ("LV 3", "NEW", "x2")
	  bar          a progress bar: a dark well, a glossy painted fill, a word
	  well         a dark studded inset that groups things inside a window
]]
Pop.RarityPaints = {
	Common = "Slate",
	Uncommon = "Green",
	Rare = "Blue",
	Epic = "Purple",
	Legendary = "Yellow",
	Mythic = "Pink",
} :: { [string]: string }

function Pop.rarityPaint(rarity: string?): Paint
	return Pop.paint(if rarity then (Pop.RarityPaints[rarity] or "Slate") else "Slate")
end

-- A drawn gold coin (a round face, a darker ring, a "$") `size` units across.
function Pop.coin(parent: Instance, size: number, props: Props?): Frame
	local coin = UIKit.new("Frame", {
		Name = "Coin",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 6,
	}, parent)
	UIKit.corner(coin, 999)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 236, 120), Color3.fromRGB(240, 160, 20)), Rotation = 90 }, coin)
	Pop.border(coin, 2)
	local inner = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = 6,
	}, coin)
	UIKit.corner(inner, 999)
	UIKit.new("UIStroke", { Color = Color3.fromRGB(196, 120, 10), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inner)
	Pop.text(coin, "$", math.floor(size * 0.62), {
		Name = "Mark",
		Size = UDim2.fromScale(1, 1),
		FontFace = PopTheme.Heavy,
		TextColor3 = Color3.fromRGB(255, 250, 220),
		ZIndex = 7,
	})
	apply(coin, props)
	return coin
end

-- The gold coin-price button ("$2.5K" with a drawn coin). Returns the button; its word is "Amount".
function Pop.coinButton(parent: Instance, text: string, size: Vector2, props: Props?): TextButton
	local button = UIKit.new("TextButton", {
		Name = "CoinButton",
		AutoButtonColor = true,
		Text = "",
		Size = UDim2.fromOffset(size.X, size.Y),
		Selectable = true,
		ZIndex = 4,
	}, parent)
	Pop.face(button, "Yellow")
	Pop.studs(button, PopTheme.Corner, 0.45, 28, 4)
	local textSize = math.floor(math.min(size.Y * 0.56, 40))
	local row = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}, button)
	UIKit.list(row, Enum.FillDirection.Horizontal, 5, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	Pop.coin(row, textSize + 2, { LayoutOrder = 1 })
	Pop.text(row, text, textSize, {
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Pop.textWidth(text, textSize), textSize + 6),
		ZIndex = 6,
	})
	apply(button, props)
	return button
end

-- A coin button's amount, and whether the player can afford it (grey when not).
function Pop.setCoinButton(button: GuiObject, text: string, affordable: boolean)
	local row = button:FindFirstChild("Row")
	local amount = if row then row:FindFirstChild("Amount") :: TextLabel? else nil
	if amount then
		amount.Text = text
		amount.Size = UDim2.fromOffset(Pop.textWidth(text, amount.TextSize), amount.Size.Y.Offset)
	end
	Pop.repaint(button, if affordable then "Yellow" else PopTheme.Gray)
end

export type TabSpec = { Id: string, Label: string, Paint: (string | Paint)? }

-- A row of bright tabs; the picked one is painted and a little taller. Returns id -> button.
function Pop.tabs(parent: Instance, list: { TabSpec }, selected: string, size: Vector2, props: Props?): { [string]: TextButton }
	local row = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(#list * (size.X + 8), size.Y + 6),
		ZIndex = 4,
	}, parent)
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Bottom })
	apply(row, props)
	local out: { [string]: TextButton } = {}
	for i, tab in list do
		local button = Pop.button(row, tab.Label, tab.Paint or "Blue", size, { Name = tab.Id, LayoutOrder = i })
		button:SetAttribute("TabPaint", if type(tab.Paint) == "string" then tab.Paint else "Blue")
		out[tab.Id] = button
	end
	Pop.selectTab(out, selected)
	return out
end

-- Paints the picked tab, greys the rest.
function Pop.selectTab(tabs: { [string]: TextButton }, selected: string)
	for id, button in tabs do
		local on = id == selected
		local paint = (button:GetAttribute("TabPaint") :: string?) or "Blue"
		Pop.repaint(button, if on then paint else "Slate")
		local label = button:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextTransparency = if on then 0 else 0.25
		end
	end
end

-- A small round label ("LV 3", "NEW").
function Pop.chip(parent: Instance, text: string, paint: string | Paint, size: Vector2, props: Props?): Frame
	local chip = Pop.tag(parent, text, paint, size, props)
	chip.Name = "Chip"
	local corner = chip:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, math.floor(size.Y / 2))
	end
	local rim = chip:FindFirstChild("Rim")
	if rim then
		rim:Destroy()
	end
	return chip
end

-- A progress bar: a dark well, a glossy painted fill and a word on top.
function Pop.bar(parent: Instance, fraction: number, paint: string | Paint, size: Vector2, text: string?, props: Props?): Frame
	local well = UIKit.new("Frame", {
		Name = "Bar",
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 4,
	}, parent)
	UIKit.corner(well, math.floor(size.Y / 2))
	Pop.border(well, 3)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
		ZIndex = 4,
	}, well)
	Pop.face(fill, paint, math.floor(size.Y / 2), true, false)
	local fillBorder = fill:FindFirstChild("Border")
	if fillBorder then
		fillBorder:Destroy()
	end
	Pop.text(well, text or "", math.floor(size.Y * 0.6), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	})
	apply(well, props)
	return well
end

function Pop.setBar(bar: GuiObject, fraction: number, text: string?)
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		fill.Visible = fraction > 0.001
	end
	local label = bar:FindFirstChild("Label") :: TextLabel?
	if label and text then
		label.Text = text
	end
end

-- A dark studded inset grouping things inside a window (lists, details, odds).
function Pop.well(parent: Instance, props: Props?): Frame
	local well = UIKit.new("Frame", {
		Name = "Well",
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
	UIKit.corner(well, PopTheme.WindowCorner)
	Pop.border(well, 3)
	apply(well, props)
	Pop.studs(well, PopTheme.WindowCorner, 0.6, 36, well.ZIndex)
	return well
end

return Pop
