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

	The pixel look (owner 2026-10-22, PopTheme):
	  short words use the pixel font and shrink to fit their box (Pop.fit);
	  every face gets a darker lip along its bottom and a light gradient edge
	  inside its outline;
	  lattice   the diagonal lattice pattern over a paint;
	  gleam     a light band that UI/PixelFx sweeps across a face now and then.
	Motion marks for Controllers/PixelFxController (Pop.fxTag: attribute
	PixelFx):
	  Spin   rays turn;
	  Gleam  a light band sweeps across;
	  Lean   an icon tilts while its button is hovered;
	  Press  hover grows, press squishes.

	The round look (owner 2026-10-27, the UI pack reel; PopTheme.Look =
	"Round", the default): the word font is Fredoka One with a thick dark
	edge (the "pixel" names stay: PopTheme.Pixel is the look's word font,
	Pop.isPixel tells a word from a sentence); faces are clean (no lattice);
	  bandPattern  a header band's fine diagonal stripes, then dressBand;
	  dressBand    the band in its window's colour (PopTheme.Windows by the
	               ScreenGui's name) with a big faded copy of its icon;
	  bandIcon     the window's icon on the left of the title;
	  heading      "- FEATURED -" in white;
	  tile         a dark HUD tile with the tile's colour on its lip and edge.
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

-- The black edge thickness for a text size (the round look: the reel's thick dark outline).
function Pop.edgeFor(size: number): number
	if PopTheme.round() then
		return if size >= 44 then 4.5 elseif size >= 28 then 3.5 elseif size >= 18 then 2.8 elseif size >= 13 then 2.2 else 1.6
	end
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

-- Whether a font is the look's word font (pixel: Press Start 2P; round: Fredoka One Bold, a
-- sentence is Fredoka One Regular: the same face).
function Pop.isPixel(font: Font): boolean
	return font.Family == PopTheme.Pixel.Family and font.Weight == PopTheme.Pixel.Weight
end

-- Marks an instance for Controllers/PixelFxController: attribute PixelFx = Spin / Gleam / Lean / Press.
function Pop.fxTag(instance: Instance, kind: string)
	instance:SetAttribute("PixelFx", kind)
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
	local light = UIKit.new("UIStroke", {
		Name = "Light",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = 2.5,
		Transparency = 0,
	}, rim)
	-- (the reels' inner edge: bright along the top, fading out toward the lip)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.25),
			NumberSequenceKeypoint.new(1, 0.85),
		}),
	}, light)
	return rim
end

--[[
	The pattern over a face. Since the pixel reels (2026-10-22) that is the
	diagonal lattice (Pop.lattice: frames, no upload needed); a faint one
	over dark bodies and wells (`transparency` 0.5 and more). `corner` and
	`tile` belonged to the old stud picture and are kept for the callers.
	A header band's pattern (`transparency` under 0.4: every window's band
	asks for 0.35) is Pop.bandPattern in the round look, whose other faces
	are clean (the reel): only the clip, which holds the gleam.
]]
function Pop.studs(frame: GuiObject, corner: number, transparency: number?, tile: number?, z: number?): GuiObject?
	local t = transparency or 0
	if PopTheme.round() then
		if t < 0.4 then
			return Pop.bandPattern(frame, z)
		end
		-- (the reel's faces: Roblox's faint "L" studs, when the stud picture shows)
		local clip = Pop.lattice(frame, z, 1)
		Pop.roundStuds(clip, z or frame.ZIndex, if t >= 0.5 then 0.9 else 0.84)
		return clip
	end
	local faint = t >= 0.5
	return Pop.lattice(frame, z, if faint then 0.94 else PopTheme.Lattice, if faint then 34 else nil)
end

-- The old raised-stud picture over a face (IconAssets ui_studs); nil until it is uploaded.
function Pop.studImage(frame: GuiObject, corner: number, transparency: number?, tile: number?, z: number?): ImageLabel?
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

--[[
	The reels' diagonal lattice over a paint: thin light lines both ways.
	Drawn by a clipping frame "Lattice" (inset `inset` units inside the
	outline) holding, per direction, frames turned 45 degrees whose gradient
	paints six lines each (a UIGradient holds 20 keys). The clip also holds
	the face's gleam (Pop.gleam). Returns the clip.
]]
function Pop.lattice(frame: GuiObject, z: number?, transparency: number?, gap: number?): Frame
	local old = frame:FindFirstChild("Lattice")
	if old then
		old:Destroy()
	end
	local inset = 3
	local clip = UIKit.new("Frame", {
		Name = "Lattice",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
		ZIndex = z or frame.ZIndex,
	}, frame)
	local step = gap or PopTheme.LatticeGap
	local t = transparency or PopTheme.Lattice
	if t >= 1 then
		return clip -- (no lines: the clip only, for a gleam)
	end
	-- the uploaded tile: one picture, any size
	if IconAssets.textureShows("ui_lattice") then
		local tile = UIKit.new("ImageLabel", {
			Name = "Lines",
			BackgroundTransparency = 1,
			ImageTransparency = t,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(step * 2, step * 2),
			Size = UDim2.fromScale(1, 1),
			ZIndex = z or frame.ZIndex,
		}, clip)
		IconAssets.applyTexture(tile, "ui_lattice")
		return clip
	end
	-- frames until then: always LatticeBands bands a way of one fixed size, so the parts
	-- never depend on the face's size (a window laid out again for a phone keeps them;
	-- they cover faces up to about 900 units of width + height, a faint gap beyond)
	local count = PopTheme.LatticeBands
	local seg = step * 6
	local reach = 1400
	local half = math.min(0.03, 1.6 / seg)
	local keys = { NumberSequenceKeypoint.new(0, 1) }
	for i = 1, 6 do
		local c = (i - 0.5) / 6
		table.insert(keys, NumberSequenceKeypoint.new(c - half, 1))
		table.insert(keys, NumberSequenceKeypoint.new(c, t))
		table.insert(keys, NumberSequenceKeypoint.new(c + half, 1))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 1))
	local lines = NumberSequence.new(keys)
	for _, rotation in { 45, -45 } do
		local ux, uy = math.cos(math.rad(rotation)), math.sin(math.rad(rotation))
		for j = 1, count do
			local along = (j - (count + 1) / 2) * seg
			local band = UIKit.new("Frame", {
				Name = "Lines",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, math.floor(ux * along + 0.5), 0.5, math.floor(uy * along + 0.5)),
				Rotation = rotation,
				Size = UDim2.fromOffset(seg, math.ceil(reach) + 8),
				ZIndex = z or frame.ZIndex,
			}, clip)
			UIKit.new("UIGradient", { Transparency = lines }, band)
		end
	end
	return clip
end

--[[
	The round look's header band (the reel): a "Lattice" clip (it holds the
	gleam too) with a fine light checker over the whole band (thin lines
	both ways, like the reel's studded paint), then Pop.dressBand (the
	window's flat colour, its darker lip and faded icon). The lines are
	frames of a fixed size, so a band laid out again keeps them (they cover
	bands up to about 1400 units wide). Returns the clip.
]]
-- The round look's studs: IconAssets' ui_studs tile (Roblox's "L" studs, our own picture) inside a clip;
-- nothing until it is uploaded (the previews draw it). Returns the picture or nil.
function Pop.roundStuds(clip: GuiObject, z: number, transparency: number): ImageLabel?
	if not IconAssets.textureShows("ui_studs") then
		return nil
	end
	local old = clip:FindFirstChild("Studs")
	if old then
		old:Destroy()
	end
	local studs = UIKit.new("ImageLabel", {
		Name = "Studs",
		BackgroundTransparency = 1,
		ImageTransparency = transparency,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(PopTheme.StudTile, PopTheme.StudTile),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, clip)
	IconAssets.applyTexture(studs, "ui_studs")
	return studs
end

function Pop.bandPattern(frame: GuiObject, z: number?): Frame
	local clip = Pop.lattice(frame, z, 1)
	-- (the reel's band: Roblox studs; the fine checker until the stud picture is uploaded)
	if Pop.roundStuds(clip, z or frame.ZIndex, 0.72) then
		Pop.dressBand(frame)
		return clip
	end
	local step = PopTheme.CheckerGap
	local seg = step * 6
	local half = math.min(0.03, 0.8 / seg) -- (lines about 1.6 units wide)
	local t = PopTheme.Checker
	local keys = { NumberSequenceKeypoint.new(0, 1) }
	for i = 1, 6 do
		local c = (i - 0.5) / 6
		table.insert(keys, NumberSequenceKeypoint.new(c - half, 1))
		table.insert(keys, NumberSequenceKeypoint.new(c, t))
		table.insert(keys, NumberSequenceKeypoint.new(c + half, 1))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 1))
	local lines = NumberSequence.new(keys)
	-- (upright lines: bands of `seg` side by side across the width; lying ones: two bands
	-- across the height, enough for a band up to 2 * seg tall)
	local across = math.ceil(1400 / seg)
	for j = 1, across do
		local band = UIKit.new("Frame", {
			Name = "Checker",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset((j - 1) * seg, 0),
			Size = UDim2.new(0, seg, 1, 0),
			ZIndex = z or frame.ZIndex,
		}, clip)
		UIKit.new("UIGradient", { Transparency = lines }, band)
	end
	for j = 1, 2 do
		local band = UIKit.new("Frame", {
			Name = "Checker",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, (j - 1) * seg),
			Size = UDim2.new(1, 0, 0, seg),
			ZIndex = z or frame.ZIndex,
		}, clip)
		UIKit.new("UIGradient", { Transparency = lines, Rotation = 90 }, band)
	end
	Pop.dressBand(frame)
	return clip
end

-- The name of the ScreenGui an instance is under (nil before it is parented to one).
function Pop.guiName(instance: Instance): string?
	local gui = if instance:IsA("ScreenGui") then instance else instance:FindFirstAncestorOfClass("ScreenGui")
	return if gui then gui.Name else nil
end

-- Which window an instance is in: the attribute Window on it or its nearest ancestor that has one, else its ScreenGui's name.
function Pop.windowKey(instance: Instance): string?
	local at: Instance? = instance
	while at and not at:IsA("ScreenGui") do
		local value = at:GetAttribute("Window")
		if type(value) == "string" then
			return value
		end
		at = at.Parent
	end
	return Pop.guiName(instance)
end

-- A window's round-look header (PopTheme.Windows by ScreenGui name); nil in the pixel look or for a window not listed.
function Pop.windowLook(key: string?): PopTheme.WindowLook?
	if not PopTheme.round() or key == nil then
		return nil
	end
	return PopTheme.Windows[key]
end

-- A window's header paint: its round-look colour, else `fallback` (the view's own).
function Pop.windowPaint(key: string?, fallback: string | Paint): string | Paint
	local look = Pop.windowLook(key)
	return if look then look.Paint else fallback
end

--[[
	Dresses a header band in its window's round look (nothing in the pixel
	look or for a window PopTheme.Windows doesn't list): the band's face
	(the band, or the face it clips over) repainted flat in the window's
	colour, and a big faded copy of the window's icon in the band's middle
	(Pop.watermark). `key` is the window's ScreenGui name (default: the
	attribute Window on the band or its nearest ancestor that has one, else
	its ScreenGui's name; Window = "" keeps a box's own colour: a red
	confirm box inside a window). Returns the look.
]]
function Pop.dressBand(band: GuiObject, key: string?): PopTheme.WindowLook?
	local look = Pop.windowLook(key or Pop.windowKey(band))
	if not look then
		return nil
	end
	local parent = band.Parent
	local face: GuiObject? = if band:FindFirstChild("Paint")
		then band
		elseif parent and parent:IsA("GuiObject") and parent:FindFirstChild("Paint") then parent
		else nil
	if face then
		Pop.bandPaint(face, look.Paint)
		face:SetAttribute("WindowPaint", look.Paint)
	end
	Pop.watermark(band, look.Icon)
	return look
end

-- A round-look band's flat colour: between a paint's top and bottom (the reel's bands are one colour).
function Pop.bandColor(paint: string | Paint): Color3
	local p = Pop.paint(paint)
	return p.Top:Lerp(p.Bottom, 0.62)
end

--[[
	Paints a header band the reel's way: one flat colour, a darker lip along
	its bottom (PopTheme.BandLip of its height), no light rim.
]]
function Pop.bandPaint(face: GuiObject, paint: string | Paint)
	local color = Pop.bandColor(paint)
	local deep = Pop.paint(paint).Bottom:Lerp(Color3.new(0, 0, 0), 0.42)
	local gradient = face:FindFirstChild("Paint") :: UIGradient?
	if gradient then
		local cut = 1 - PopTheme.BandLip
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(cut - 0.001, color),
			ColorSequenceKeypoint.new(cut, deep),
			ColorSequenceKeypoint.new(1, deep),
		})
	end
	local rim = face:FindFirstChild("Rim")
	if rim and rim:IsA("GuiObject") then
		rim.Visible = false
	end
	face:SetAttribute("Lip", PopTheme.BandLip)
end

--[[
	The big faded copy of a window's icon in its header band (the reel),
	inside the band's clip so it is cut at the band's edges; nothing shows
	until the icon's sheet is uploaded (previews draw it).
]]
function Pop.watermark(band: GuiObject, icon: string): ImageLabel
	local old = band:FindFirstChild("Watermark", true)
	if old then
		old:Destroy()
	end
	local holder = band:FindFirstChild("Lattice") or band
	local mark = UIKit.new("ImageLabel", {
		Name = "Watermark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ImageTransparency = PopTheme.Watermark,
		Position = UDim2.fromScale(0.5, 0.56),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.new(0, 190, 1.7, 0), -- (Fit: a square 1.7 bands tall, at most 190 units)
		Visible = IconAssets.shows(icon),
		ZIndex = band.ZIndex,
	}, holder)
	IconAssets.apply(mark, icon)
	mark:SetAttribute("Icon", icon)
	return mark
end

--[[
	The round look's top-row button picture (the reel's Shop / Spawn / Plot
	tabs): a big faded copy of `icon` over the button's left end, inside the
	face's clip so its edges cut it; the word stays centred over it. Hidden
	until the icon's sheet is uploaded (previews draw it). Returns it.
]]
function Pop.tabMark(button: GuiObject, icon: string, height: number): ImageLabel
	local clip = button:FindFirstChild("Lattice") :: GuiObject?
	local holder: GuiObject = clip or button
	local old = holder:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	local pic = math.floor(height * 1.25)
	local mark = UIKit.new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		ImageTransparency = PopTheme.TabMark,
		Position = UDim2.new(0, -math.floor(pic * 0.22), 0.5, math.floor(height * 0.18)),
		Rotation = -10,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(pic, pic),
		Visible = IconAssets.shows(icon),
		ZIndex = holder.ZIndex,
	}, holder)
	IconAssets.apply(mark, icon)
	mark:SetAttribute("Icon", icon)
	return mark
end

--[[
	The window's icon on the left of its title (the reel), `size` units
	square; hidden until the icon's sheet is uploaded (previews draw it).
	Pop.iconRoom says how far the title moves right for it.
]]
function Pop.bandIcon(parent: Instance, icon: string, size: number, props: Props?): ImageLabel
	local image = UIKit.new("ImageLabel", {
		Name = "BandIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		Visible = IconAssets.shows(icon),
		ZIndex = 6,
	}, parent)
	IconAssets.apply(image, icon)
	image:SetAttribute("Icon", icon)
	Pop.fxTag(image, "Lean")
	apply(image, props)
	return image
end

-- How far a title moves right for its band icon (0 when there is none or it is hidden).
function Pop.iconRoom(icon: ImageLabel?): number
	if icon == nil or not icon.Visible then
		return 0
	end
	return icon.Size.X.Offset + 6
end

-- The round look's broad light stripes across a header band ("//", the reel's shine: a wide
-- and a thin one either side of the faded icon).
function Pop.shineStripes(band: GuiObject, z: number?)
	for i, s in { { 0.3, 30 }, { 0.36, 12 }, { 0.68, 30 }, { 0.74, 12 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.74,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(s[1], 0.5),
			Rotation = 24,
			Size = UDim2.new(0, s[2], 2.6, 0),
			ZIndex = z or band.ZIndex,
		}, band)
	end
end

--[[
	A gleam: a light band turned 20 degrees, parked left of the face inside
	its Lattice clip (PixelFx "Gleam": PixelFxController sweeps it across now and
	then). Returns the band.
]]
function Pop.gleam(frame: GuiObject, z: number?): Frame
	local clip = (frame:FindFirstChild("Lattice") :: Frame?) or Pop.lattice(frame, z, 1)
	local band = UIKit.new("Frame", {
		Name = "Gleam",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(-0.3, 0, 0.5, 0),
		Rotation = 20,
		Size = UDim2.new(0, 40, 3, 0),
		ZIndex = z or clip.ZIndex,
	}, clip)
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(0.65, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, band)
	Pop.fxTag(band, "Gleam")
	return band
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
	-- (a pixel title shrinks to fit: the shadow shrinks the same way)
	local fit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if fit then
		fit:Clone().Parent = shade
	end
	return shade
end

--[[
	White chunky text with a black edge: the pixel font for a short word, the
	round font for a sentence (wrapped or long; or the FontFace `props` names).
]]
function Pop.text(parent: Instance, text: string, size: number, props: Props?): TextLabel
	-- (a sentence - wrapped, or longer than PopTheme.PixelMax letters - stays round: readable)
	local sentence = (props ~= nil and props.TextWrapped == true) or (utf8.len(text) or #text) > PopTheme.PixelMax
	local label = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 6),
		FontFace = if sentence then PopTheme.Font else PopTheme.Pixel,
		Text = text,
		TextSize = size,
		TextColor3 = PopTheme.Ink,
		TextWrapped = false,
		ZIndex = 4,
	}, parent)
	Pop.edge(label, Pop.edgeFor(size))
	apply(label, props)
	Pop.fit(label, size)
	if not sentence and (props == nil or props.FontFace == nil) then
		-- (a word filled in later that turns out to be a sentence goes round too; the game
		-- only: the Lune previews have no signals)
		pcall(function()
			label:GetPropertyChangedSignal("Text"):Connect(function()
				Pop.sentence(label, size)
			end)
		end)
	end
	return label
end

--[[
	Sets a Pop.text label's size limits (round-font sizes: a pixel label gets them
	times PopTheme.PixelScale, never under PixelMin). Reuses the label's one
	UITextSizeConstraint (Pop.fit's), never a second one.
]]
function Pop.limit(label: TextLabel, max: number, min: number?)
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not limit then
		limit = UIKit.new("UITextSizeConstraint", { Name = "Fit" }, label)
	end
	local l = limit :: UITextSizeConstraint
	local k = if Pop.isPixel(label.FontFace) then PopTheme.PixelScale else 1
	local top = math.max(PopTheme.PixelMin, math.floor(max * k + 0.5))
	l.MaxTextSize = top
	l.MinTextSize = math.min(top, math.max(if k < 1 then PopTheme.PixelMin else 1, math.floor((min or 1) * k + 0.5)))
end

-- Makes a Pop.text label round for good (a status line, a hint): no scaling, Pop.sentence leaves it alone.
function Pop.round(label: TextLabel, size: number?)
	label:SetAttribute("Round", true)
	label.FontFace = PopTheme.Font
	label.TextScaled = false
	label.TextTruncate = Enum.TextTruncate.None
	local word = label:GetAttribute("WordSize")
	label.TextSize = size or (if type(word) == "number" then word else label.TextSize)
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit:Destroy()
	end
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.LineJoinMode = Enum.LineJoinMode.Round
	end
end

-- A pixel label whose text grew into a sentence turns round (and back for a short word).
function Pop.sentence(label: TextLabel, size: number)
	if label:GetAttribute("Round") == true then
		return -- (a view made it round on purpose: Pop.round)
	end
	local long = (utf8.len(label.Text) or #label.Text) > PopTheme.PixelMax
	local pixel = Pop.isPixel(label.FontFace)
	if long and pixel then
		label.FontFace = PopTheme.Font
		label.TextSize = size
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = size
		end
	elseif not long and not pixel then
		label.FontFace = PopTheme.Pixel
		Pop.fit(label, size)
	end
end

--[[
	The pixel font is wide (a letter is 1 em): a pixel word is drawn at
	PopTheme.PixelScale of `size` and shrinks to fit its box instead of
	spilling out of it. Wrapped and automatically sized labels are left alone.
]]
function Pop.fit(label: TextLabel, size: number)
	if not Pop.isPixel(label.FontFace) or label.TextWrapped or label.AutomaticSize ~= Enum.AutomaticSize.None then
		return
	end
	local max = math.max(8, math.floor(size * PopTheme.PixelScale + 0.5))
	label:SetAttribute("WordSize", size) -- (the size Pop.text was given: Pop.setPrice measures with it)
	label.TextSize = max
	label.TextScaled = true
	-- (never smaller than PopTheme.PixelMin: a word that still doesn't fit ends in "...")
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not limit then
		limit = UIKit.new("UITextSizeConstraint", { Name = "Fit" }, label)
	end
	local l = limit :: UITextSizeConstraint
	l.MaxTextSize = max
	l.MinTextSize = math.min(max, PopTheme.PixelMin)
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		-- (square corners suit the pixel letters; the round font keeps a round edge)
		edge.LineJoinMode = if PopTheme.round() then Enum.LineJoinMode.Round else Enum.LineJoinMode.Miter
	end
end

--[[
	A one-line word that must stay readable in its `w` x `h` box (review
	2026-10-22: a golem bonus "+13.8% MINING", a pen income "+$1.23K/s"
	were about 7 pt on a 568x320 phone): pixel letters (Pop.fit at `size`)
	while they fit at `floor` design units or more, else the round font
	(it is narrower) when it is bigger, at most `roundMax`. A pixel letter
	is 1 em wide, a round capital about 0.6 em (the round look's words are
	round too: PopTheme.PixelAdvance). Returns true when round.
]]
function Pop.fitOrRound(label: TextLabel, size: number, roundMax: number, floor: number, w: number, h: number): boolean
	local n = math.max(1, utf8.len(label.Text) or #label.Text)
	local pixelSize = math.min(
		math.max(8, math.floor(size * PopTheme.PixelScale + 0.5)),
		math.floor(w / (n * PopTheme.PixelAdvance)),
		math.floor(h / PopTheme.PixelLine)
	)
	local roundSize = math.min(roundMax, math.floor(w / (n * 0.6)), math.floor(h / 1.2))
	if pixelSize >= floor or roundSize <= pixelSize then
		label:SetAttribute("Round", nil)
		label.FontFace = PopTheme.Pixel
		Pop.fit(label, size)
		return false
	end
	Pop.round(label, roundSize)
	label.TextTruncate = Enum.TextTruncate.AtEnd -- (cut rather than spilled)
	return true
end

-- A heading in a PopTheme.Titles gradient (top -> bottom) with a black edge.
function Pop.title(parent: Instance, text: string, size: number, colors: string | { Color3 }, props: Props?): TextLabel
	local keys = if type(colors) == "table" then colors else (PopTheme.Titles[colors] or PopTheme.Titles.White)
	local label = Pop.text(parent, text, size, { Name = "Title" })
	UIKit.new("UIGradient", { Color = ColorSequence.new(keys[1], keys[#keys]), Rotation = 90 }, label)
	apply(label, props)
	return label
end

-- the small words Title Case leaves lower case (not the first one)
local SMALL = {
	a = true,
	an = true,
	["and"] = true,
	at = true,
	by = true,
	["for"] = true,
	["in"] = true,
	of = true,
	on = true,
	["or"] = true,
	the = true,
	to = true,
}

--[[
	A title's words in the round look: an ALL CAPS text in Title Case ("MY
	GOLEMS" -> "My Golems", "HALL OF FAME" -> "Hall of Fame",
	"FORGEMASTER'S PASS" -> "Forgemaster's Pass", "2X MONEY" -> "2x Money");
	a text with small letters already is left as it is. The pixel look
	keeps its capitals.
]]
function Pop.caption(text: string): string
	if not PopTheme.round() or string.find(text, "%l") then
		return text
	end
	local first = true
	return (
		string.gsub(text, "%S+", function(word: string): string
			local lower = string.lower(word)
			local out: string
			if not first and SMALL[lower] then
				out = lower
			else
				-- the first letter up (after any leading signs or digits), the rest down
				local at = string.find(lower, "%a") or 1
				out = string.sub(lower, 1, at - 1) .. string.upper(string.sub(lower, at, at)) .. string.sub(lower, at + 1)
				-- a word that starts with a digit or is a multiplier keeps its small x: "2x Money", "x2"
				if string.match(lower, "^%d") or string.match(lower, "^x%d") then
					out = lower
				end
			end
			first = false
			return out
		end)
	)
end

-- A section heading's words: "- Gamepass -" in the round look (Title Case, the reel), else as they are.
function Pop.section(text: string): string
	if PopTheme.round() and text ~= "" and string.sub(text, 1, 2) ~= "- " then
		return "- " .. Pop.caption(text) .. " -"
	end
	return text
end

-- "-- PASSES --": a section heading `width` wide.
function Pop.heading(parent: Instance, text: string, colors: string, size: number, props: Props?): TextLabel
	-- (the reels: a pixel word over the list, "GAMEPASSES"; the round look: white "- PASSES -")
	local round = PopTheme.round()
	local heading =
		Pop.title(parent, Pop.section(text), if round then math.floor(size * 0.8) else size, if round then "White" else colors, {
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
local function faceGradient(paint: Paint, lip: number?): ColorSequence
	-- (the reels: a smooth light-to-deep paint, then a darker lip along the bottom)
	local l = lip or 0
	if l <= 0 then
		return ColorSequence.new(paint.Top, paint.Bottom)
	end
	local deep = paint.Bottom:Lerp(Color3.new(0, 0, 0), 0.3)
	local cut = 1 - l
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, paint.Top),
		ColorSequenceKeypoint.new(cut - 0.001, paint.Bottom),
		ColorSequenceKeypoint.new(cut, deep),
		ColorSequenceKeypoint.new(1, deep),
	})
end

-- The lip's height in design units for a face `h` units tall.
function Pop.lipUnits(h: number): number
	return math.clamp(math.floor(h * PopTheme.Lip + 0.5), 3, 9)
end

-- The lip's share of a face's height (3..9 design units; a scale-sized face gets 0.1).
function Pop.lipFor(frame: GuiObject): number
	local h = frame.Size.Y.Offset
	if frame.Size.Y.Scale ~= 0 or h <= 0 then
		return 0.1
	end
	return math.clamp(math.floor(h * PopTheme.Lip + 0.5), 3, 9) / h
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
	-- (glossy false: a flat band, no lip - headers, bars)
	local lip = if glossy == false then 0 else Pop.lipFor(frame)
	frame:SetAttribute("Lip", lip)
	g.Color = faceGradient(p, lip)
	-- the light edge just inside the black border
	if rim ~= false then
		Pop.rim(frame, Pop.rimColor(p), corner or PopTheme.Corner, 3, frame.ZIndex)
	end
	return g
end

-- A paint's light edge: its top colour lifted toward white.
function Pop.rimColor(paint: Paint): Color3
	return paint.Top:Lerp(Color3.new(1, 1, 1), 0.6)
end

-- A dark tile's gradient: dark grey, warming toward its lip in the tile's colour.
local function darkGradient(paint: Paint, lip: number): ColorSequence
	-- (measured on the reel: slate all the way down, a thin band of the tile's colour at the bottom)
	local dark = PopTheme.TileDark
	local cut = 1 - math.clamp(lip, 0.04, 0.06)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, dark.Top),
		ColorSequenceKeypoint.new(cut - 0.001, dark.Bottom),
		ColorSequenceKeypoint.new(cut, paint.Bottom),
		ColorSequenceKeypoint.new(1, paint.Bottom:Lerp(Color3.new(0, 0, 0), 0.2)),
	})
end

--[[
	The round look's dark HUD tile face (the reel): a dark grey gradient, a
	lip along the bottom in the tile's colour (`paint`) and the light edge
	inside the outline in the tile's colour, brightest along the bottom.
	Pop.repaint keeps it dark (it recolours the lip and the edge).
]]
function Pop.darkTile(frame: GuiObject, paint: string | Paint, corner: number)
	Pop.face(frame, PopTheme.TileDark, corner)
	frame:SetAttribute("DarkTile", true)
	frame.BackgroundTransparency = 0.06 -- (the reel's tiles let the world through a touch)
	local border = frame:FindFirstChild("Border") :: UIStroke?
	if border then
		border.Thickness = 2.5 -- (measured: 3.3 px at 1080p)
	end
	local rim = frame:FindFirstChild("Rim")
	local light = if rim then rim:FindFirstChild("Light") else nil
	local fade = if light then light:FindFirstChildOfClass("UIGradient") else nil
	if fade then
		fade.Rotation = 270 -- (bright along the bottom, fading up)
	end
	Pop.repaint(frame, paint)
end

-- Recolours a painted frame (a button that turns grey, a selected tab).
function Pop.repaint(frame: GuiObject, paint: string | Paint, glossy: boolean?)
	local p = Pop.paint(paint)
	if frame:GetAttribute("Cell") == true then
		Pop.cellAccent(frame, p.Top) -- (a dark cell keeps its face: the colour rides its inner edge)
		return
	end
	if frame:GetAttribute("TwoTone") == true then
		Pop.twoTone(frame, p)
		return
	end
	local dark = frame:GetAttribute("DarkTile") == true
	local gradient = frame:FindFirstChild("Paint") :: UIGradient?
	if gradient then
		local lip = frame:GetAttribute("Lip")
		local l = if glossy == false then 0 elseif type(lip) == "number" then lip else 0
		gradient.Color = if dark then darkGradient(p, l) else faceGradient(p, l)
	end
	local rim = frame:FindFirstChild("Rim")
	local light = if rim then rim:FindFirstChild("Light") else nil
	if light and light:IsA("UIStroke") then
		light.Color = if dark then p.Top else Pop.rimColor(p)
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
	if size.X >= 120 then
		Pop.gleam(button, 4)
	end
	Pop.text(button, text, math.floor(math.min(size.Y * 0.56, 40)), {
		Name = "Label",
		Size = UDim2.new(1, -10, 0.9, 0), -- (above the lip; a scale: a layout may resize the button)
		Position = UDim2.fromOffset(5, 0),
		TextScaled = false,
		ZIndex = 5,
	})
	Pop.fxTag(button, "Press")
	apply(button, props)
	return button
end

-- About how wide a word is in the pixel font at Pop.text's `size` (design units).
function Pop.textWidth(text: string, size: number): number
	return math.ceil(utf8.len(text) or #text) * size * PopTheme.PixelScale * PopTheme.PixelAdvance + 6
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
	-- (the round look: the reel's lime price buttons)
	Pop.face(button, if PopTheme.round() then PopTheme.Paints.Lime else PopTheme.Price)
	Pop.studs(button, PopTheme.Corner, 0.45, 28, 4)
	Pop.gleam(button, 4)
	Pop.fxTag(button, "Press")
	local row = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.9, 0), -- (above the lip; a scale: a layout may resize the button)
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
	local words = Pop.priceWords(robux, text)
	Pop.text(row, words, textSize, {
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Pop.textWidth(words, textSize), textSize + 6),
		ZIndex = 6,
	})
	-- (the round look: the reel's "R$179" words, no mark)
	mark.Visible = robux ~= nil and not PopTheme.round()
	apply(button, props)
	return button
end

-- A price button's words: "R$179" in the round look (the reel), else the amount after the mark; `text` without one.
function Pop.priceWords(robux: number?, text: string?): string
	if robux then
		return if PopTheme.round() then "R$" .. tostring(robux) else tostring(robux)
	end
	return text or ""
end

-- Sets a price button's amount (nil: `text` without the mark).
function Pop.setPrice(button: GuiObject, robux: number?, text: string?)
	local row = button:FindFirstChild("Row")
	if not row then
		return
	end
	local mark = row:FindFirstChild("Mark") :: ImageLabel?
	local amount = row:FindFirstChild("Amount") :: TextLabel?
	local words = Pop.priceWords(robux, text)
	if mark then
		mark.Visible = robux ~= nil and not PopTheme.round()
	end
	if amount then
		amount.Text = words
		-- (measured with the size the label was built with: TextSize is already the fitted one)
		amount.Size = UDim2.fromOffset(Pop.textWidth(words, Pop.wordSize(amount)), amount.Size.Y.Offset)
	end
end

-- How wide a label's text is in design units, in the label's own font (pixel or round).
function Pop.measure(label: TextLabel): number
	if Pop.isPixel(label.FontFace) then
		return Pop.textWidth(label.Text, Pop.wordSize(label))
	end
	return math.ceil(utf8.len(label.Text) or #label.Text) * label.TextSize * 0.55 + 6
end

-- The size a Pop.text label was built with (its attribute WordSize; else its TextSize).
function Pop.wordSize(label: TextLabel): number
	local word = label:GetAttribute("WordSize")
	return if type(word) == "number" then word else label.TextSize
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
	Icon: ImageLabel?, -- the round look's icon left of the title (Pop.bandIcon)
}

--[[
	A window: a bright header band (`paint`, green by default) with diagonal
	shine stripes, the title on the left and the red X on the right, over a
	dark grey body. `size` in design units; `band` the header's height.
	The round look: the band in the window's own colour (PopTheme.Windows by
	the ScreenGui's name, Pop.dressBand), its icon left of the title.
]]
function Pop.window(parent: Instance, title: string, size: Vector2, band: number?, paint: (string | Paint)?): Window
	local h = band or 76
	local round = PopTheme.round()
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
	-- (the reel: a thin near-black frame, the band and the body straight inside it)
	local rim = if round then 3 else 4
	Pop.border(root, rim)

	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(rim, h),
		Size = UDim2.new(1, -2 * rim, 1, -(h + rim)),
		ZIndex = 1,
	}, root)
	UIKit.corner(body, if round then 3 else 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, body)
	-- the body's studs (the photos' dark studded floor) and a shade under the header
	Pop.studs(body, 4, 0.5, 36, 1)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		Visible = not round, -- (the reel's band ends in its own darker lip)
		ZIndex = 1,
	}, body)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.45, 1),
	}, shade)

	local head = UIKit.new("Frame", {
		Name = "Header",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 0, h - 2 * rim),
		ClipsDescendants = true,
		ZIndex = 2,
	}, root)
	Pop.face(head, paint or "Green", 4, false)
	local headBorder = head:FindFirstChild("Border") :: UIStroke
	headBorder.Thickness = if round then 0 else 3
	headBorder.Enabled = not round
	-- (the pixel reels: the lattice over the band, a gleam now and then; no stripes;
	-- the round look: the fine checker, broad light stripes, the window's flat colour, its
	-- darker lip and faded icon)
	head.Size = UDim2.fromOffset(size.X - 2 * rim, h - 2 * rim)
	Pop.studs(head, 4, 0.35, 40, 3)
	if round then
		Pop.shineStripes(head, 3)
	end
	Pop.gleam(head, 3)
	head.Size = UDim2.new(1, -2 * rim, 0, h - 2 * rim)
	-- the window's icon (the round look): a little bigger than the band, over its left end
	local look = Pop.windowLook(Pop.windowKey(parent))
	local icon = if look then Pop.bandIcon(root, look.Icon, h + 2, { Position = UDim2.new(0, 4, 0, math.floor(h / 2) - 1) }) else nil
	local room = Pop.iconRoom(icon)
	local left = if room > 0 then room + 1 elseif round then 12 else 16
	local titleLabel = Pop.text(head, Pop.caption(title), math.floor(h * (if round then 0.4 else 0.6)), {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, left, 0.5, -(if round then 2 else 0)),
		Size = UDim2.new(1, -(h + 14 + left), 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	Pop.shadow(titleLabel, if round then 3 else nil)
	-- (44 pt on a phone at the compact bands; the reel's X on a PC band: 48 of 73 units, 15 in)
	local x = if round and h < 80 then math.floor(h * 0.66) else math.floor(h * 0.82)
	local close = Pop.close(root, x, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, if round then -15 else -10, 0, math.floor(h / 2) - (if round then 2 else 0)),
	})
	return { Root = root, Header = head, Title = titleLabel, Close = close, Body = body, Icon = icon }
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
	Pop.fxTag(holder, "Spin")
	return holder
end

--[[
	The round look's two-tone card paint (the reel's Store cards): the
	paint's light top in the top-left corner to its deep bottom in the
	bottom-right, no lip, and a deeper edge just inside the black outline.
]]
function Pop.twoTone(frame: GuiObject, paint: string | Paint)
	local p = Pop.paint(paint)
	frame:SetAttribute("TwoTone", true)
	frame:SetAttribute("Lip", 0)
	local gradient = frame:FindFirstChild("Paint") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(p.Top, p.Bottom)
		gradient.Rotation = 35
	end
	local rim = frame:FindFirstChild("Rim")
	local light = if rim then rim:FindFirstChild("Light") else nil
	if light and light:IsA("UIStroke") then
		light.Color = p.Bottom:Lerp(Color3.new(0, 0, 0), 0.22)
		light.Thickness = 3
		local fade = light:FindFirstChildOfClass("UIGradient")
		if fade then
			fade:Destroy() -- (an even edge all round)
		end
	end
end

--[[
	The round look's dark item cell (the reel's index and inventory grids):
	paints `frame` a dark slate gradient with a near-black outline, two
	broad faint diagonal stripes, and a thin inner edge in `accent` (a
	rarity's colour; none: a quiet grey). The cell keeps its face when a
	view repaints it (Pop.repaint: the colour goes to the edge). Returns the
	stripes' clip ("Lattice", it holds a gleam too).
]]
function Pop.cellFace(frame: GuiObject, accent: Color3?, corner: number?): Frame
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame:SetAttribute("Cell", true)
	frame:SetAttribute("Lip", 0)
	local r = corner or 6
	local c = frame:FindFirstChildOfClass("UICorner")
	if c then
		c.CornerRadius = UDim.new(0, r)
	else
		UIKit.corner(frame, r)
	end
	local border = frame:FindFirstChild("Border") :: UIStroke?
	if border then
		border.Thickness = 2.5
		border.Color = PopTheme.Outline
	else
		Pop.border(frame, 2.5)
	end
	local gradient = frame:FindFirstChild("Paint") :: UIGradient?
	if not gradient then
		gradient = UIKit.new("UIGradient", { Name = "Paint", Rotation = 90 }, frame)
	end
	local g = gradient :: UIGradient
	g.Rotation = 90
	g.Color = ColorSequence.new(PopTheme.CellTop, PopTheme.CellBottom)
	local clip = Pop.lattice(frame, frame.ZIndex, 1)
	for i, s in { { 0.32, 0.22 }, { 0.72, 0.12 } } do
		UIKit.new("Frame", {
			Name = "CellStripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.94,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(s[1], 0.5),
			Rotation = 35,
			Size = UDim2.fromScale(s[2], 2),
			ZIndex = frame.ZIndex,
		}, clip)
	end
	Pop.rim(frame, accent or Color3.fromRGB(70, 78, 92), r, 3, frame.ZIndex)
	Pop.cellAccent(frame, accent or Color3.fromRGB(70, 78, 92))
	return clip
end

-- A dark cell's inner edge colour (a rarity's, a picked cell's gold).
function Pop.cellAccent(frame: GuiObject, color: Color3)
	local rim = frame:FindFirstChild("Rim")
	local light = if rim then rim:FindFirstChild("Light") else nil
	if light and light:IsA("UIStroke") then
		light.Color = color
		light.Thickness = 1.5
		light.Transparency = 0.15
		local fade = light:FindFirstChildOfClass("UIGradient")
		if fade then
			fade:Destroy()
		end
	end
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
	apply(button, props)
	Pop.face(button, paint, PopTheme.Corner)
	local p = Pop.paint(paint)
	local round = PopTheme.round()
	if round then
		Pop.twoTone(button, p)
	end
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
	if rays then
		Pop.fxTag(rays, "Spin")
	else
		-- (the round look: the reel's strong sunburst, broad light wedges)
		Pop.rays(button, centre, if round then 12 else 10, long, if round then 0.5 else 0.6, 2)
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
	-- (the pixel reels: no sparkles, the rays turn instead)
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
			for _, corner in
				{
					Vector3.new(half.X, half.Y, half.Z),
					Vector3.new(-half.X, half.Y, half.Z),
					Vector3.new(half.X, -half.Y, half.Z),
					Vector3.new(half.X, half.Y, -half.Z),
					Vector3.new(-half.X, -half.Y, half.Z),
					Vector3.new(-half.X, half.Y, -half.Z),
					Vector3.new(half.X, -half.Y, -half.Z),
					Vector3.new(-half.X, -half.Y, -half.Z),
				}
			do
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
	Pop.gleam(button, 3)
	Pop.fxTag(button, "Press")
	-- (the pixel reels' wide buttons: a big picture over the left end, leaning on hover)
	local pic = math.floor(size.Y * 1.12)
	local shows = IconAssets.shows(icon)
	local image = UIKit.new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, -math.floor(pic * 0.12), 0.46, 0),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(pic, pic),
		Visible = shows,
		ZIndex = 4,
	}, button)
	IconAssets.apply(image, icon)
	image:SetAttribute("Icon", icon)
	Pop.fxTag(image, "Lean")
	local left = if shows then math.floor(pic * 0.9) else 8
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
	-- (the pixel reels' square buttons: radius 10 of 100, the lattice, a
	-- sunburst turning behind the picture, the picture leaning on hover;
	-- the round look: Pop.darkTile, the reel's dark tiles)
	face.Size = UDim2.fromOffset(s, s)
	local paint = Pop.paint(o.Paint)
	if PopTheme.round() then
		Pop.darkTile(face, paint, math.max(3, math.floor(s * 0.05))) -- (measured: radius ~5.6 px of 116)
		face:SetAttribute("TilePaint", if type(o.Paint) == "string" then o.Paint else nil)
	else
		Pop.face(face, o.Paint, math.floor(s * 0.12))
	end
	face.Size = UDim2.fromScale(1, 1)
	local clip = Pop.studs(face, 10, 0.45, 30, 2) :: Frame
	if not PopTheme.round() then
		local rays = Pop.rays(clip, UDim2.fromScale(0.5, 0.42), 8, math.floor(s * 0.75), 0.55, 2)
		for _, ray in rays:GetChildren() do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = paint.Top:Lerp(Color3.new(1, 1, 1), 0.75)
			end
		end
	end
	local round = PopTheme.round()
	local icon = UIKit.new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		-- (the reel's tiles: the picture 68 % of the tile, from 19 % down)
		Position = UDim2.new(0.5, 0, if round then 0.47 else 0.44, 0),
		ScaleType = Enum.ScaleType.Fit,
		Size = if round then UDim2.fromScale(0.72, 0.72) else UDim2.fromScale(0.8, 0.8),
		ZIndex = 3,
	}, face)
	IconAssets.apply(icon, o.Icon)
	icon:SetAttribute("Icon", o.Icon)
	Pop.fxTag(icon, "Lean")
	Pop.fxTag(face, "Press")
	local hasPicture = IconAssets.shows(o.Icon)
	icon.Visible = hasPicture
	-- (the word sits on the tile's bottom edge, half out: the pictures stay big)
	Pop.text(face, o.Label, math.floor(s * (if hasPicture then 0.2 else 0.26)), {
		Name = "Label",
		AnchorPoint = if hasPicture then Vector2.new(0.5, 0.5) else Vector2.new(0.5, 0.5),
		Position = if hasPicture then UDim2.new(0.5, 0, if round then 0.86 else 0.9, 0) else UDim2.fromScale(0.5, 0.5),
		-- (relative to the tile: the word grows when a layout makes the tile bigger)
		Size = if hasPicture then UDim2.new(1.04, 0, 0.22, 0) else UDim2.new(1, -8, 0.34, 0),
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
	Secret = "Purple", -- the SECRET ores (Rarity.Secret, outside Rarity.List)
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
		amount.Size = UDim2.fromOffset(Pop.textWidth(text, Pop.wordSize(amount)), amount.Size.Y.Offset)
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
