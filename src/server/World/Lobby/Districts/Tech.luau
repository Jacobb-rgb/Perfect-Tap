--[[
	Sci-fi building kit of the Districts package (visual upgrade, concept v2:
	docs/art/lobby_concept_v2.webp). Kenney Space Station Kit shapes, see
	docs/art/kenney_refs/space_station_kit.jpg, and City Kit commercial
	details, see docs/art/kenney_refs/city_kit.jpg, rebuilt from Roblox
	parts, never meshes:

	  wall           wall-banner: slab, bevelled foot and cap, the colored band
	  windowWall     wall-window-banner: a wall with a framed glass window
	  doorFrame      wall-door-wide-banner: jambs, lintel, colored U frame
	  roundPillar    wall-corner-round-banner: round pillar, band, neon strip
	  screen         display-wall(-wide): thick bezel, glowing screen, tabs
	  showcase       table-display: stand, band stripes, glass case on top
	  pedestal       table-display-planet: bevelled square pedestal
	  stairs         stairs + stairs-handrail
	  container      container-tall
	  computer       computer-screen
	  parasol        detail-parasol (City Kit)
	  sign           big glowing sign box: chunky casing, chamfered blue
	                 neon frame, white letters, optional icon panel
	  lanternPillar  dark pillar with glowing slots (concept v2 lanterns)
	  ring           thick mechanical ring (n blocks) with a neon inner edge
	  crown          gold crown pictogram (solid band, three touching points)
	  flatTri        one-wedge right triangle in a plane (chamfers, crown points)

	Look: thick dark gunmetal frames with lighter bevels, glowing blue neon
	outlines (Neon parts), warm orange accents. Frames: `base` = bottom
	center, front = LookVector (local -Z); seen from the front local +X is
	on the viewer's left. Pure builders (Instance creation only).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Style = require(script.Parent.Parent.Style)

local Tech = {}

type Opts = { [string]: any }

local C = Style.C
local rgb = Color3.fromRGB
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass

-- Gunmetal shades of the sci-fi modules (three shades + a deep recess
-- color, slightly blue like the concept's frames), the Kenney orange band
-- and the glass tint. Glows reuse Style.C (GlowEdge blue, Fire orange).
Tech.Metal = rgb(66, 72, 92)
Tech.MetalDark = rgb(44, 48, 64)
Tech.MetalDeep = rgb(27, 29, 41)
Tech.MetalLight = rgb(112, 120, 144)
Tech.Band = C.Hazard
-- a deeper neon blue than Style.C.GlowEdge: thin neon lines stay blue under
-- bloom instead of washing out to white
Tech.Neon = rgb(40, 130, 255)
-- the thick neon tubes (frames, roof edges, ring edges): a deep electric
-- blue, so a 0.3-0.45 stud tube stays saturated blue under the neon boost
-- and bloom instead of washing out to pastel periwinkle in daylight
Tech.Tube = rgb(8, 44, 200)
Tech.TUBE = 0.36 -- thick tube size; thin trims stay 0.12-0.2
Tech.EDGE = 0.45 -- the roof-edge and frame tubes set in a dark channel (Tech.channel)
Tech.Warm = C.Fire
Tech.Lens = rgb(255, 150, 50) -- small warm lamp lenses (sign lamps): orange, not white
Tech.GoldGlow = rgb(200, 116, 14) -- neon gold (crowns) that blooms to warm gold, not white
Tech.Glass = rgb(150, 200, 250)
Tech.GlassClear = 0.85 -- window glass transparency: the goods behind show through
-- showcase glass: a cyan tint and a lower transparency, so each case reads
-- as a lit glass box from the plaza (concept v2), the goods still show
Tech.CaseGlass = rgb(120, 200, 255)
Tech.CaseClear = 0.66
Tech.CaseLight = rgb(255, 186, 104) -- thin warm light strips inside showcases and windows
Tech.Board = rgb(16, 30, 78) -- sign boards and screens behind white letters
Tech.Screen = rgb(30, 92, 214) -- glowing screens (deep enough to stay blue under bloom)

---------------------------------------------------------------- basics

local function block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: Opts?): Part
	return Style.block(parent, cf, size, color, material, props)
end

-- small detail: no collision, no shadow
local function bit(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return Style.block(parent, cf, size, color, material, Style.tiny())
end

function Tech.glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3?): Part
	return Style.block(parent, cf, size, color or Tech.Neon, NEON, Style.tiny())
end
local glow = Tech.glow

--[[
	A neon tube set in a dark channel (concept v2: saturated electric blue
	with dark lines on both sides): a MetalDeep backing strip 0.12 thick,
	`pad` wider than the tube on both sides of its thin axis, right behind
	the tube. `cf` = tube center, the tube's visible face = LookVector
	(local -Z), the tube's long axis = local X (`along` = "Y": local Y).
	Returns the tube. 2 parts.
]]
function Tech.channel(parent: Instance, cf: CFrame, length: number, thickness: number, color: Color3?, along: string?, pad: number?): Part
	local p = pad or 0.16
	local depth = 0.16
	local tubeSize: Vector3, backSize: Vector3
	if along == "Y" then
		tubeSize = Vector3.new(thickness, length, depth)
		backSize = Vector3.new(thickness + 2 * p, length, 0.12)
	else
		tubeSize = Vector3.new(length, thickness, depth)
		backSize = Vector3.new(length, thickness + 2 * p, 0.12)
	end
	bit(parent, cf * CFrame.new(0, 0, depth / 2 + 0.04), backSize, Tech.MetalDeep)
	return glow(parent, cf, tubeSize, color or Tech.Tube)
end

-- A ramp wedge: full face down and back (+Z), sloping down toward the front.
function Tech.bevel(parent: Instance, cf: CFrame, size: Vector3, color: Color3, props: Opts?): WedgePart
	return Geo.wedge(parent, cf, size, color, SMOOTH, props or Style.tiny({ CastShadow = true }))
end

-- An underside bevel (corbel): full face up and back, rising toward the front.
function Tech.underBevel(parent: Instance, cf: CFrame, size: Vector3, color: Color3, props: Opts?): WedgePart
	return Geo.wedge(parent, cf * CFrame.Angles(0, 0, math.pi), size, color, SMOOTH, props or Style.tiny())
end

-- A bar (box) from point a to point b; `up` = a hint for its local Y axis.
function Tech.bar(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	width: number,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?,
	up: Vector3?
): Part
	local d = b - a
	local z = -d.Unit
	local hint = up or Vector3.new(0, 1, 0)
	if math.abs(hint:Dot(z)) > 0.99 then
		hint = Vector3.new(1, 0, 0)
	end
	local x = hint:Cross(z).Unit
	local y = z:Cross(x)
	local cf = CFrame.fromMatrix((a + b) / 2, x, y, z)
	return Style.block(parent, cf, Vector3.new(width, depth, d.Magnitude), color, material, props or Style.tiny())
end

-- A round rod (cylinder) from point a to point b.
function Tech.rod(parent: Instance, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?, props: Opts?): Part
	local d = b - a
	local x = d.Unit
	local up = if math.abs(x.Y) > 0.99 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local z = x:Cross(up).Unit
	local y = z:Cross(x)
	local p: Opts = props or Style.tiny()
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.fromMatrix((a + b) / 2, x, y, z)
	p.Size = Vector3.new(d.Magnitude, diameter, diameter)
	p.Color = color
	p.Material = material or SMOOTH
	return Geo.make("Part", p, parent)
end

-- Upright cylinder centered at `position`.
function Tech.disc(
	parent: Instance,
	position: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?
): Part
	return Geo.cylinder(parent, position, height, diameter, color, material or SMOOTH, props or Style.tiny())
end

-- Cylinder whose axis is the frame's Z axis (a disc facing the frame's front).
function Tech.faceDisc(
	parent: Instance,
	cf: CFrame,
	thickness: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?
): Part
	local p: Opts = props or Style.tiny()
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	p.Size = Vector3.new(thickness, diameter, diameter)
	p.Color = color
	p.Material = material or SMOOTH
	return Geo.make("Part", p, parent)
end

-- A line of light studs (small orange neon cubes) from local point a to b in `cf`.
function Tech.studs(parent: Instance, cf: CFrame, a: Vector3, b: Vector3, count: number, size: number?, color: Color3?)
	local s = size or 0.35
	for i = 0, count - 1 do
		local t = if count == 1 then 0.5 else i / (count - 1)
		Tech.glow(parent, cf * CFrame.new(a:Lerp(b, t)), Vector3.new(s, s, 0.16), color or Tech.Warm)
	end
end

---------------------------------------------------------------- walls

--[[
	wall-banner: a slab with a bevelled foot, the colored band and a lighter
	cap with an underside bevel. `base` = bottom center, front face at
	local z = -depth/2. opts: Color, Band (Color3 | false), BandY (0..1),
	BandHeight, BandNeon (boolean), Cap (default true), Foot (default true),
	TopNeon (Color3: neon line along the cap's front edge). 4-7 parts.
]]
function Tech.wall(parent: Instance, base: CFrame, width: number, height: number, depth: number, opts: Opts?): Part
	local o: Opts = opts or {}
	local slab =
		block(parent, base * CFrame.new(0, height / 2, 0), Vector3.new(width, height, depth), o.Color or Tech.Metal, nil, Style.solid())
	local fz = -depth / 2
	if o.Foot ~= false then
		block(
			parent,
			base * CFrame.new(0, 0.4, fz - 0.2),
			Vector3.new(width, 0.8, 0.4),
			Tech.MetalDark,
			nil,
			Style.tiny({ CastShadow = true })
		)
		Tech.bevel(parent, base * CFrame.new(0, 0.95, fz - 0.2), Vector3.new(width, 0.3, 0.4), Tech.MetalDark)
	end
	if o.Band ~= false then
		local bh = o.BandHeight or math.clamp(height * 0.1, 0.5, 1.1)
		local material = if o.BandNeon then NEON else SMOOTH
		bit(
			parent,
			base * CFrame.new(0, (o.BandY or 0.28) * height, fz - 0.06),
			Vector3.new(width, bh, 0.12),
			o.Band or Tech.Band,
			material
		)
	end
	if o.Cap ~= false then
		local capH = 0.7
		block(
			parent,
			base * CFrame.new(0, height - capH / 2, fz - 0.17),
			Vector3.new(width, capH, 0.34),
			Tech.MetalLight,
			nil,
			Style.tiny({ CastShadow = true })
		)
		Tech.underBevel(parent, base * CFrame.new(0, height - capH - 0.17, fz - 0.17), Vector3.new(width, 0.34, 0.34), Tech.MetalLight)
		if o.TopNeon then
			glow(parent, base * CFrame.new(0, height - 0.18, fz - 0.4), Vector3.new(width, Tech.TUBE, 0.16), o.TopNeon)
		end
	end
	return slab
end

--[[
	wall-window-banner: a wall with a framed window. `base` = bottom center.
	opts: Color, WindowWidth, WindowBottom, WindowTop (local heights),
	Frame (inner frame color, default the orange band), Glass (default
	true; false = an open bay), Lit (Color3: a glowing neon pane instead of
	glass), Foot. Returns the pane (or nil). 8-10 parts.
]]
function Tech.windowWall(parent: Instance, base: CFrame, width: number, height: number, depth: number, opts: Opts?): Part?
	local o: Opts = opts or {}
	local color = o.Color or Tech.Metal
	local ow = o.WindowWidth or width * 0.66
	local y0 = o.WindowBottom or height * 0.25
	local y1 = o.WindowTop or height * 0.8
	local jw = (width - ow) / 2
	local p = Style.solid()
	block(parent, base * CFrame.new(0, y0 / 2, 0), Vector3.new(width, y0, depth), color, nil, p)
	block(parent, base * CFrame.new(0, (y1 + height) / 2, 0), Vector3.new(width, height - y1, depth), color, nil, Style.solid())
	for _, side in { -1, 1 } do
		block(
			parent,
			base * CFrame.new(side * (ow / 2 + jw / 2), (y0 + y1) / 2, 0),
			Vector3.new(jw, y1 - y0, depth),
			color,
			nil,
			Style.solid()
		)
	end
	local frame = o.Frame or Tech.Band
	local t = 0.36
	local fd = depth + 0.12
	-- a U frame (top and sides) on a deep sill: the sill is the frame's
	-- bottom bar and the ledge in front of the wall in one block (the
	-- Kenney frame's thick bottom)
	bit(parent, base * CFrame.new(0, y1 - t / 2, 0), Vector3.new(ow, t, fd), frame)
	for _, side in { -1, 1 } do
		bit(parent, base * CFrame.new(side * (ow / 2 - t / 2), (y0 + y1) / 2, 0), Vector3.new(t, y1 - y0 - 2 * t, fd), frame)
	end
	bit(parent, base * CFrame.new(0, y0 + t / 2 - 0.15, -0.14), Vector3.new(ow + 0.4, t + 0.3, fd + 0.28), frame)
	if o.Foot ~= false then
		bit(parent, base * CFrame.new(0, 0.4, -depth / 2 - 0.2), Vector3.new(width, 0.8, 0.4), Tech.MetalDark)
	end
	local inner: Color3? = o.FrameNeon
	if inner then
		-- a thin neon line inside the U frame (top and both sides)
		local z = -fd / 2 - 0.03
		local h = y1 - y0 - t
		glow(parent, base * CFrame.new(0, y1 - t - 0.07, z), Vector3.new(ow - 2 * t, 0.14, 0.08), inner)
		for _, side in { -1, 1 } do
			glow(parent, base * CFrame.new(side * (ow / 2 - t - 0.07), y0 + t / 2 + h / 2, z), Vector3.new(0.14, h - 0.14, 0.08), inner)
		end
	end
	local pane: Part? = nil
	if o.Lit then
		pane = glow(parent, base * CFrame.new(0, (y0 + y1) / 2, 0.1), Vector3.new(ow - 2 * t, y1 - y0 - 2 * t, 0.12), o.Lit)
	elseif o.Glass ~= false then
		pane = block(
			parent,
			base * CFrame.new(0, (y0 + y1) / 2, 0),
			Vector3.new(ow - 2 * t + 0.1, y1 - y0 - 2 * t + 0.1, 0.16),
			o.GlassColor or Tech.Glass,
			GLASS,
			Style.decor({ Transparency = Tech.GlassClear, CastShadow = false })
		)
	end
	return pane
end

--[[
	wall-door-wide-banner: two jambs, a lintel and a colored U frame around
	a wide opening. `base` = bottom center. opts: Color, OpeningWidth,
	OpeningHeight, Frame (color), Neon (Color3: a neon line inside the U).
	7-10 parts.
]]
function Tech.doorFrame(parent: Instance, base: CFrame, width: number, height: number, depth: number, opts: Opts?)
	local o: Opts = opts or {}
	local color = o.Color or Tech.Metal
	local ow = o.OpeningWidth or width * 0.7
	local oh = o.OpeningHeight or height * 0.75
	local jw = (width - ow) / 2
	for _, side in { -1, 1 } do
		block(parent, base * CFrame.new(side * (ow / 2 + jw / 2), oh / 2, 0), Vector3.new(jw, oh, depth), color, nil, Style.solid())
	end
	if height > oh + 0.05 then
		block(parent, base * CFrame.new(0, (oh + height) / 2, 0), Vector3.new(width, height - oh, depth), color, nil, Style.solid())
	end
	local frame = o.Frame or Tech.Band
	local t = 0.4
	local fd = depth + 0.14
	for _, side in { -1, 1 } do
		bit(parent, base * CFrame.new(side * (ow / 2 - t / 2), oh / 2, 0), Vector3.new(t, oh, fd), frame)
	end
	bit(parent, base * CFrame.new(0, oh - t / 2, 0), Vector3.new(ow, t, fd), frame)
	if o.Neon then
		local z = -depth / 2 - 0.1
		for _, side in { -1, 1 } do
			glow(parent, base * CFrame.new(side * (ow / 2 - t - 0.14), (oh - t) / 2, z), Vector3.new(0.28, oh - t, 0.12), o.Neon)
		end
		glow(parent, base * CFrame.new(0, oh - t - 0.14, z), Vector3.new(ow - 2 * t, 0.28, 0.12), o.Neon)
	end
end

--[[
	wall-corner-round-banner: a round pillar with a dark foot, the colored
	band, a light cap and a vertical neon strip on its front. 5 parts.
	opts: Band (Color3), Neon (Color3 | false), Color.
]]
function Tech.roundPillar(parent: Instance, base: CFrame, height: number, diameter: number, opts: Opts?): Part
	local o: Opts = opts or {}
	local p = base.Position
	local up = base.UpVector
	local core = Tech.disc(parent, p + up * (height / 2), height, diameter, o.Color or Tech.Metal, nil, Style.solid())
	Tech.disc(parent, p + up * 0.35, 0.7, diameter + 0.34, Tech.MetalDark)
	Tech.disc(parent, p + up * (height * 0.26), 0.9, diameter + 0.12, o.Band or Tech.Band)
	Tech.disc(parent, p + up * (height - 0.3), 0.6, diameter + 0.34, Tech.MetalLight, nil, Style.tiny({ CastShadow = true }))
	if o.Neon ~= false then
		local h = height - 2.3
		glow(parent, base * CFrame.new(0, 1.0 + h / 2 + 0.5, -diameter / 2 + 0.02), Vector3.new(0.3, h, 0.14), o.Neon or Tech.Neon)
	end
	return core
end

--[[
	Chunky square pillar (concept v2 frames): a dark foot, a gunmetal shaft
	with the orange band, blue neon strips on its two front corners, two
	orange light studs and a light cap with an underside bevel. `base` =
	bottom center. opts: Band, Neon (Color3 | false), Studs (default true).
	8-10 parts.
]]
function Tech.pillar(parent: Instance, base: CFrame, height: number, width: number, opts: Opts?): Part
	local o: Opts = opts or {}
	local w = width
	block(parent, base * CFrame.new(0, 0.4, 0), Vector3.new(w + 0.5, 0.8, w + 0.5), Tech.MetalDark, nil, Style.solid())
	local shaft = block(parent, base * CFrame.new(0, height / 2, 0), Vector3.new(w, height, w), Tech.Metal, nil, Style.solid())
	bit(parent, base * CFrame.new(0, height * 0.24, 0), Vector3.new(w + 0.12, 0.8, w + 0.12), o.Band or Tech.Band)
	block(
		parent,
		base * CFrame.new(0, height - 0.35, 0),
		Vector3.new(w + 0.5, 0.7, w + 0.5),
		Tech.MetalLight,
		nil,
		Style.tiny({ CastShadow = true })
	)
	Tech.underBevel(parent, base * CFrame.new(0, height - 0.95, -w / 2 - 0.12), Vector3.new(w + 0.5, 0.5, 0.25), Tech.MetalLight)
	if o.Neon ~= false then
		local y0, y1 = height * 0.24 + 0.6, height - 1.3
		for _, sx in { -1, 1 } do
			glow(
				parent,
				base * CFrame.new(sx * w / 2, (y0 + y1) / 2, -w / 2),
				Vector3.new(Tech.TUBE, y1 - y0, Tech.TUBE),
				o.Neon or Tech.Tube
			)
		end
	end
	if o.Studs ~= false then
		for _, y in { height * 0.5, height * 0.68 } do
			glow(parent, base * CFrame.new(0, y, -w / 2 - 0.04), Vector3.new(0.4, 0.4, 0.1), Tech.Warm)
		end
	end
	return shaft
end

--[[
	Dark lantern pillar with glowing slots (concept v2): a foot, a dark
	shaft with a warm neon slot on the front and both sides, a cap with a
	blue neon ring under it. Returns the front slot. 7 parts.
]]
function Tech.lanternPillar(parent: Instance, base: CFrame, height: number, width: number, opts: Opts?): Part
	local o: Opts = opts or {}
	local w = width
	block(parent, base * CFrame.new(0, 0.3, 0), Vector3.new(w + 0.5, 0.6, w + 0.5), Tech.MetalDark, nil, Style.solid())
	block(parent, base * CFrame.new(0, height / 2, 0), Vector3.new(w, height - 0.6, w), o.Color or Tech.MetalDeep, nil, Style.solid())
	local slotH = (height - 1.8) * 0.6
	local sy = height * 0.55
	local slot = glow(parent, base * CFrame.new(0, sy, -w / 2 - 0.02), Vector3.new(w * 0.3, slotH, 0.1), o.Slot or Tech.Warm)
	slot.Name = "LanternGlow"
	for _, side in { -1, 1 } do
		glow(parent, base * CFrame.new(side * (w / 2 + 0.02), sy, 0), Vector3.new(0.1, slotH, w * 0.3), o.Slot or Tech.Warm)
	end
	block(
		parent,
		base * CFrame.new(0, height - 0.05, 0),
		Vector3.new(w + 0.45, 0.5, w + 0.45),
		Tech.Metal,
		nil,
		Style.tiny({ CastShadow = true })
	)
	glow(parent, base * CFrame.new(0, height - 0.4, 0), Vector3.new(w + 0.12, 0.18, w + 0.12), o.Ring or Tech.Neon)
	return slot
end

---------------------------------------------------------------- screens and displays

--[[
	display-wall(-wide): a thick bevelled bezel around a glowing screen,
	two tabs on top. `cf` = screen center, front = LookVector. Returns the
	screen. opts: Bezel (color), Tabs (default true), Bars (Color3: two
	darker content stripes). 4-6 parts.
]]
function Tech.screen(parent: Instance, cf: CFrame, width: number, height: number, color: Color3, opts: Opts?): Part
	local o: Opts = opts or {}
	block(parent, cf * CFrame.new(0, 0, 0.26), Vector3.new(width + 0.7, height + 0.7, 0.5), o.Bezel or Tech.MetalDark, nil, Style.decor())
	local screen = glow(parent, cf * CFrame.new(0, 0, 0), Vector3.new(width, height, 0.1), color)
	screen.Name = "Screen"
	if o.Tabs ~= false then
		for _, side in { -1, 1 } do
			bit(parent, cf * CFrame.new(side * width * 0.3, height / 2 + 0.5, 0.26), Vector3.new(0.7, 0.3, 0.4), Tech.MetalLight)
		end
	end
	if o.Bars then
		for i, y in { 0.18, -0.12 } do
			bit(
				parent,
				cf * CFrame.new(-width * 0.08, height * y, -0.06),
				Vector3.new(width * (if i == 1 then 0.6 else 0.45), height * 0.08, 0.04),
				o.Bars
			)
		end
	end
	return screen
end

--[[
	table-display with a glass case: a gunmetal stand with orange corner
	stripes, a light rim with a neon front line and (opts.Case = height) a
	cyan-tinted glass box framed by four thin neon corner posts and a capped
	frame, a warm light strip in its top and a glowing floor plate under the
	goods, so the case reads as a lit glass box. `base` = bottom center.
	Returns the CFrame of the display floor (items go there). opts: Neon,
	Stripe, Case, Light, Top (Color3: a glowing top instead of glass),
	Plinth (Color3: a small neon plinth under the item), Backlight (Color3:
	a glowing back panel inside the case). 7-16 parts.
]]
function Tech.showcase(parent: Instance, base: CFrame, width: number, depth: number, height: number, opts: Opts?): CFrame
	local o: Opts = opts or {}
	local neon = o.Neon or Tech.Neon
	block(parent, base * CFrame.new(0, 0.2, 0), Vector3.new(width, 0.4, depth), Tech.MetalDark, nil, Style.solid())
	block(parent, base * CFrame.new(0, height / 2, 0), Vector3.new(width - 0.5, height - 0.4, depth - 0.5), Tech.Metal, nil, Style.solid())
	for _, side in { -1, 1 } do
		bit(
			parent,
			base * CFrame.new(side * (width / 2 - 0.45), height / 2, -depth / 2 + 0.2),
			Vector3.new(0.4, height - 0.8, 0.1),
			o.Stripe or Tech.Band
		)
	end
	block(parent, base * CFrame.new(0, height - 0.18, 0), Vector3.new(width + 0.2, 0.36, depth + 0.2), Tech.MetalLight, nil, Style.solid())
	glow(parent, base * CFrame.new(0, height - 0.2, -depth / 2 - 0.16), Vector3.new(width + 0.2, 0.24, 0.12), neon)
	if o.Top then
		glow(parent, base * CFrame.new(0, height + 0.02, 0), Vector3.new(width - 0.5, 0.06, depth - 0.5), o.Top)
	end
	local ch: number? = o.Case
	local floor = height
	if ch then
		-- the glowing floor plate under the goods
		glow(parent, base * CFrame.new(0, height + 0.03, 0), Vector3.new(width - 0.7, 0.06, depth - 0.7), o.Light or Tech.CaseLight)
		floor = height + 0.06
		if o.Plinth then
			-- a small neon plinth under the item: it lights the goods from below
			local pw, pd = math.min(1.7, width * 0.55), math.min(1.2, depth * 0.6)
			glow(parent, base * CFrame.new(0, floor + 0.1, 0.05), Vector3.new(pw, 0.2, pd), o.Plinth)
			floor += 0.2
		end
		if o.Backlight then
			-- a glowing back panel inside the case: the case reads as a lit box
			glow(parent, base * CFrame.new(0, height + ch / 2, depth / 2 - 0.22), Vector3.new(width - 0.6, ch - 0.3, 0.08), o.Backlight)
		end
		local glass = block(
			parent,
			base * CFrame.new(0, height + ch / 2, 0),
			Vector3.new(width - 0.3, ch, depth - 0.3),
			Tech.CaseGlass,
			GLASS,
			Style.decor({ Transparency = Tech.CaseClear, CastShadow = false })
		)
		glass.Name = "Showcase"
		bit(parent, base * CFrame.new(0, height + ch + 0.14, 0), Vector3.new(width, 0.28, depth), Tech.MetalLight)
		-- four thin neon corner posts frame the glass
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				glow(
					parent,
					base * CFrame.new(sx * (width / 2 - 0.16), height + ch / 2, sz * (depth / 2 - 0.16)),
					Vector3.new(0.14, ch, 0.14),
					neon
				)
			end
		end
		glow(parent, base * CFrame.new(0, height + ch + 0.14, -depth / 2 - 0.06), Vector3.new(width, 0.2, 0.1), neon)
		-- the light strip under the case lid, along its front edge: it shows
		-- through the glass and lights the goods from the front
		glow(
			parent,
			base * CFrame.new(0, height + ch - 0.08, -depth / 2 + 0.4),
			Vector3.new(width - 0.6, 0.12, 0.3),
			o.Light or Tech.CaseLight
		)
	end
	return base * CFrame.new(0, floor, 0)
end

--[[
	table-display-planet: a bevelled square pedestal (dark foot slab, four
	sloped sides, a top block) with a neon disc on top. `base` = bottom
	center. Returns the CFrame of the top. 7 parts.
]]
function Tech.pedestal(parent: Instance, base: CFrame, size: number, height: number, opts: Opts?): CFrame
	local o: Opts = opts or {}
	local top = size * 0.62
	local slopeH = math.min(0.9, height * 0.35)
	local footH = height - slopeH
	block(parent, base * CFrame.new(0, footH / 2, 0), Vector3.new(size, footH, size), o.Color or Tech.MetalDark, nil, Style.solid())
	local w = (size - top) / 2
	for k = 0, 3 do
		local side = base * CFrame.Angles(0, k * math.pi / 2, 0)
		Tech.bevel(parent, side * CFrame.new(0, footH + slopeH / 2, -(top / 2 + w / 2)), Vector3.new(top, slopeH, w), o.Slope or Tech.Metal)
	end
	block(parent, base * CFrame.new(0, footH + slopeH / 2, 0), Vector3.new(top, slopeH, top), o.Slope or Tech.Metal, nil, Style.solid())
	Tech.disc(parent, (base * CFrame.new(0, height + 0.03, 0)).Position, 0.1, top * 0.8, o.Neon or Tech.Neon, NEON)
	return base * CFrame.new(0, height, 0)
end

--[[
	stairs + stairs-handrail: `steps` solid steps climbing toward local +Z
	from `base` (bottom center of the first step's front edge), each with
	an orange nose strip, and (opts.Rails) orange round handrails on posts
	at both sides. Returns the top height. 2 parts per step + 6 for rails.
]]
function Tech.stairs(parent: Instance, base: CFrame, width: number, rise: number, run: number, steps: number, opts: Opts?): number
	local o: Opts = opts or {}
	local back = run * steps + (o.Extra or 0)
	for i = 1, steps do
		local top = rise * i
		local z0 = run * (i - 1)
		block(
			parent,
			base * CFrame.new(0, top / 2, (z0 + back) / 2),
			Vector3.new(width, top, back - z0),
			o.Color or Tech.Metal,
			nil,
			Style.solid()
		)
		bit(parent, base * CFrame.new(0, top - 0.07, z0 + 0.14), Vector3.new(width - 0.3, 0.16, 0.3), o.Nose or Tech.Band)
	end
	if o.Rails then
		local railH = 2.6
		for _, side in { -1, 1 } do
			local x = side * (width / 2 - 0.3)
			local z1, z2 = run * 0.5, run * (steps - 0.5) + (o.RailExtra or 0)
			local y1, y2 = rise, rise * steps
			for _, q in { { z1, y1 }, { z2, y2 } } do
				bit(parent, base * CFrame.new(x, q[2] + railH / 2, q[1]), Vector3.new(0.28, railH, 0.28), Tech.MetalLight)
			end
			local a = (base * CFrame.new(x, y1 + railH, z1 - 0.3)).Position
			local b = (base * CFrame.new(x, y2 + railH, z2 + 0.3)).Position
			Tech.rod(parent, a, b, 0.42, o.Rail or Tech.Band)
		end
	end
	return rise * steps
end

--[[
	container-tall: an upright drum with two light bands, a light top cap
	and a dark foot. `base` = bottom center. 5 parts.
]]
function Tech.container(parent: Instance, base: CFrame, height: number, diameter: number, color: Color3, opts: Opts?): Part
	local o: Opts = opts or {}
	local p = base.Position
	local up = base.UpVector
	local body = Tech.disc(parent, p + up * (height / 2), height - 0.3, diameter, color, nil, o.Props or Style.decor())
	for _, f in { 0.28, 0.72 } do
		Tech.disc(parent, p + up * (height * f), 0.4, diameter + 0.2, Tech.MetalLight)
	end
	Tech.disc(parent, p + up * (height - 0.12), 0.25, diameter * 0.82, Tech.MetalLight)
	Tech.disc(parent, p + up * 0.15, 0.3, diameter * 0.9, Tech.MetalDark)
	return body
end

--[[
	computer-screen: a foot, a stand, a console with three glowing buttons
	and a tilted screen in a thick bezel. `base` = bottom center. Returns
	the screen. 9 parts.
]]
function Tech.computer(parent: Instance, base: CFrame, width: number, color: Color3?, opts: Opts?): Part
	local o: Opts = opts or {}
	local s = width / 2.4
	block(parent, base * CFrame.new(0, 0.15 * s, 0), Vector3.new(1.6, 0.3, 1.4) * s, Tech.MetalDark, nil, Style.decor())
	block(parent, base * CFrame.new(0, 1.0 * s, 0.1 * s), Vector3.new(0.6, 1.5, 0.6) * s, Tech.MetalDark, nil, Style.decor())
	local console = base * CFrame.new(0, 1.85 * s, -0.25 * s) * CFrame.Angles(0.3, 0, 0)
	bit(parent, console, Vector3.new(2.0, 0.35, 1.0) * s, Tech.MetalLight)
	for i, c in { C.CrystalCyan, C.LeafYellow, C.AwningRed } do
		glow(parent, console * CFrame.new((i - 2) * 0.5 * s, 0.2 * s, 0), Vector3.new(0.32, 0.1, 0.32) * s, c)
	end
	local sc = base * CFrame.new(0, 3.0 * s, 0.25 * s) * CFrame.Angles(-0.12, 0, 0)
	block(parent, sc * CFrame.new(0, 0, 0.12 * s), Vector3.new(2.4, 1.7, 0.3) * s, Tech.MetalDark, nil, Style.decor())
	local screen = glow(parent, sc * CFrame.new(0, 0, -0.04 * s), Vector3.new(2.0, 1.3, 0.06) * s, color or Tech.Screen)
	screen.Name = "Screen"
	if o.Bars then
		bit(parent, sc * CFrame.new(-0.2 * s, 0.25 * s, -0.09 * s), Vector3.new(1.2, 0.14, 0.03) * s, o.Bars)
		bit(parent, sc * CFrame.new(-0.4 * s, -0.05 * s, -0.09 * s), Vector3.new(0.8, 0.14, 0.03) * s, o.Bars)
	end
	return screen
end

--[[
	detail-parasol (City Kit): a pole with a two-tier octagonal canopy and a
	little round table. `base` = bottom center. 6 parts.
]]
function Tech.parasol(parent: Instance, base: CFrame, height: number, diameter: number, color: Color3, rim: Color3?)
	local p = base.Position
	local up = base.UpVector
	bit(parent, base * CFrame.new(0, height / 2, 0), Vector3.new(0.3, height, 0.3), Tech.MetalLight)
	Tech.disc(parent, p + up * height, 0.4, diameter, color, nil, Style.ghost())
	Tech.disc(parent, p + up * (height + 0.42), 0.5, diameter * 0.56, color:Lerp(Color3.new(1, 1, 1), 0.15), nil, Style.ghost())
	Tech.disc(parent, p + up * (height - 0.3), 0.25, diameter + 0.1, rim or C.AwningWhite)
	Tech.disc(parent, p + up * 2.4, 0.22, diameter * 0.42, C.AwningWhite, nil, Style.decor())
	Tech.disc(parent, p + up * 0.12, 0.24, 1.6, Tech.MetalDark)
end

---------------------------------------------------------------- rings

--[[
	A thick mechanical ring in the plane of `cf` (its axis = cf.LookVector):
	`n` gunmetal blocks between radius `inner` and the polygon apothem
	`outer`, a lighter front lip, a blue neon inner edge and (opts.Studs)
	orange light studs on every other block. opts: Depth, Color, Neon,
	Tube (inner neon edge thickness), AllStuds (a stud on every block),
	Studs (Color3), Lip (default true), OuterNeon (Color3: the front lip
	becomes a second neon line along the outer rim, the concept's double
	neon channel). ~3-4 parts per block.
]]
function Tech.ring(parent: Instance, cf: CFrame, inner: number, outer: number, n: number, opts: Opts?)
	local o: Opts = opts or {}
	local depth = o.Depth or 1.6
	local band = outer - inner
	local tan = math.tan(math.pi / n)
	local len = 2 * outer * tan
	for k = 0, n - 1 do
		local a = k * 2 * math.pi / n
		local seg = cf * CFrame.Angles(0, 0, a)
		block(
			parent,
			seg * CFrame.new(0, inner + band / 2, 0),
			Vector3.new(len, band, depth),
			if k % 2 == 0 then o.Color or Tech.Metal else (o.Color or Tech.Metal):Lerp(Tech.MetalDark, 0.35),
			nil,
			o.Props or Style.decor()
		)
		if o.OuterNeon then
			local t: number = o.Tube or Tech.TUBE
			glow(parent, seg * CFrame.new(0, outer - t * 0.9, -depth / 2 - 0.1), Vector3.new(len - 0.02, t * 0.8, 0.2), o.OuterNeon)
		elseif o.Lip ~= false then
			bit(parent, seg * CFrame.new(0, outer - 0.3, -depth / 2 - 0.12), Vector3.new(len - 0.1, 0.6, 0.24), Tech.MetalLight)
		end
		local tube: number = o.Tube or Tech.TUBE
		glow(
			parent,
			seg * CFrame.new(0, inner + tube / 2, -depth / 2 - 0.1),
			Vector3.new(2 * (inner + tube / 2) * tan + 0.06, tube, 0.2),
			o.Neon or Tech.Tube
		)
		if o.Studs and (o.AllStuds or k % 2 == 1) then
			glow(parent, seg * CFrame.new(0, inner + band * 0.55, -depth / 2 - 0.08), Vector3.new(0.5, 0.5, 0.14), o.Studs)
		end
	end
end

---------------------------------------------------------------- signs

-- One straight segment of a flat outline in the plane of `cf` (local x, y points).
local function line(
	parent: Instance,
	cf: CFrame,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	t: number,
	z: number,
	color: Color3,
	material: Enum.Material?,
	depth: number?
): Part
	local a = (cf * CFrame.new(x1, y1, z)).Position
	local b = (cf * CFrame.new(x2, y2, z)).Position
	local d = b - a
	local mid = cf * CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, z)
	local angle = math.atan2(y2 - y1, x2 - x1)
	local part = Style.block(
		parent,
		mid * CFrame.Angles(0, 0, angle),
		Vector3.new(d.Magnitude + t * 0.6, t, depth or 0.14),
		color,
		material or NEON,
		Style.tiny()
	)
	return part
end
Tech.line = line

-- A chamfered rectangle outline (8 bars) of half sizes hw, hh, chamfer c.
function Tech.outline(parent: Instance, cf: CFrame, hw: number, hh: number, c: number, t: number, z: number, color: Color3)
	local pts = {
		{ hw - c, hh },
		{ -hw + c, hh },
		{ -hw, hh - c },
		{ -hw, -hh + c },
		{ -hw + c, -hh },
		{ hw - c, -hh },
		{ hw, -hh + c },
		{ hw, hh - c },
	}
	for i = 1, #pts do
		local a, b = pts[i], pts[i % #pts + 1]
		line(parent, cf, a[1], a[2], b[1], b[2], t, z, color)
	end
end

--[[
	A shopping cart pictogram (neon bars) centered at `cf`, size `s`; the
	handle is on the viewer's left like the concept's SHOP sign. 11 parts.
]]
function Tech.cartIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	local t = s * 0.075
	local z = -0.05
	-- handle grip and the slanted left side down to the base rail
	line(parent, cf, 0.47 * s, 0.4 * s, 0.33 * s, 0.4 * s, t, z, color)
	line(parent, cf, 0.33 * s, 0.4 * s, 0.17 * s, -0.22 * s, t, z, color)
	-- basket: top edge, bottom edge, right side (slanted), one inner rib each way
	line(parent, cf, 0.26 * s, 0.16 * s, -0.44 * s, 0.16 * s, t, z, color)
	line(parent, cf, 0.19 * s, -0.12 * s, -0.33 * s, -0.12 * s, t, z, color)
	line(parent, cf, -0.44 * s, 0.16 * s, -0.33 * s, -0.12 * s, t, z, color)
	line(parent, cf, 0.22 * s, 0.02 * s, -0.39 * s, 0.02 * s, t * 0.7, z, color)
	line(parent, cf, -0.09 * s, 0.16 * s, -0.08 * s, -0.12 * s, t * 0.7, z, color)
	-- base rail and two wheels
	line(parent, cf, 0.17 * s, -0.24 * s, -0.36 * s, -0.24 * s, t, z, color)
	for _, x in { 0.08, -0.28 } do
		local w = cf * CFrame.new(x * s, -0.37 * s, z) * CFrame.Angles(0, 0, math.pi / 4)
		Style.block(parent, w, Vector3.new(0.15 * s, 0.15 * s, 0.14), color, NEON, Style.tiny())
	end
end

-- A regular polygon outline (n neon bars) of radius r around `cf`; the
-- first side is centered at angle `a0` (radians from local +Y).
local function polygon(parent: Instance, cf: CFrame, n: number, r: number, t: number, z: number, color: Color3, a0: number?)
	local start = (a0 or 0) - math.pi / n
	for k = 0, n - 1 do
		local a = start + k * 2 * math.pi / n
		local b = a + 2 * math.pi / n
		line(parent, cf, -r * math.sin(a), r * math.cos(a), -r * math.sin(b), r * math.cos(b), t, z, color)
	end
end
Tech.polygon = polygon

--[[
	A gear pictogram as a crisp outline (the same line weight as the cart):
	an octagon ring, 8 square teeth and a small diamond hub, centered at
	`cf`, size `s`. Neon outlines keep their teeth under bloom where a
	filled gear turns into a white starburst. 17 parts.
]]
function Tech.gearIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	local t = s * 0.075
	local z = -0.05
	local r = s * 0.3
	polygon(parent, cf, 8, r, t, z, color)
	for k = 0, 7 do
		local a = k * math.pi / 4
		local tooth = cf * CFrame.Angles(0, 0, a) * CFrame.new(0, r * math.cos(math.pi / 8) + s * 0.08, z)
		Style.block(parent, tooth, Vector3.new(s * 0.13, s * 0.15, 0.14), color, NEON, Style.tiny())
	end
	Style.block(
		parent,
		cf * CFrame.new(0, 0, z) * CFrame.Angles(0, 0, math.pi / 4),
		Vector3.new(s * 0.14, s * 0.14, 0.14),
		color,
		NEON,
		Style.tiny()
	)
end

--[[
	A scanner pictogram: an octagon scan ring (like the machine's ring),
	a crosshair with a gap in the middle and a center dot, centered at
	`cf`, size `s`. 13 parts.
]]
function Tech.scanIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	local t = s * 0.07
	local z = -0.05
	local r = s * 0.3
	polygon(parent, cf, 8, r, t, z, color)
	for k = 0, 3 do
		local a = k * math.pi / 2
		local ux, uy = -math.sin(a), math.cos(a)
		line(parent, cf, ux * s * 0.12, uy * s * 0.12, ux * s * 0.46, uy * s * 0.46, t, z, color)
	end
	Style.block(
		parent,
		cf * CFrame.new(0, 0, z) * CFrame.Angles(0, 0, math.pi / 4),
		Vector3.new(t * 1.6, t * 1.6, 0.14),
		color,
		NEON,
		Style.tiny()
	)
end

-- A flat right triangle in the XY plane of `cf` (thickness `d` along Z):
-- the right angle at local (x0, y0), the vertical leg up to (x0, y0 + h),
-- the horizontal leg to (x0 + dir * bw, y0). One WedgePart.
function Tech.flatTri(
	parent: Instance,
	cf: CFrame,
	x0: number,
	y0: number,
	dir: number,
	bw: number,
	h: number,
	d: number,
	color: Color3,
	material: Enum.Material?,
	props: Opts?
): WedgePart
	local at = cf * CFrame.new(x0 + dir * bw / 2, y0 + h / 2, 0) * CFrame.Angles(0, -dir * math.pi / 2, 0)
	return Geo.wedge(parent, at, Vector3.new(d, h, bw), color, material or SMOOTH, props or Style.tiny())
end

--[[
	A crown pictogram: a solid gold band, three points that touch at their
	feet (the outer ones with straight outer edges, a taller middle one),
	ball tips and gems on the band. `cf` = bottom center of the band, front
	= LookVector; w wide and about 0.95 w tall. opts: Depth (default
	0.25 w), Gem (Color3), Neon (glowing gold). 11 parts.
]]
function Tech.crown(parent: Instance, cf: CFrame, w: number, color: Color3?, opts: Opts?)
	local o: Opts = opts or {}
	local gold = color or C.Gold
	local d = o.Depth or w * 0.25
	local bandH = w * 0.28
	local outerH, midH = w * 0.38, w * 0.54
	local material = if o.Neon then NEON else SMOOTH
	local p = Style.tiny()
	Style.block(parent, cf * CFrame.new(0, bandH / 2, 0), Vector3.new(w, bandH, d), gold, material, p)
	-- outer points (straight outer edge) and the two halves of the middle point
	for _, side in { -1, 1 } do
		Tech.flatTri(parent, cf, side * w / 2, bandH - 0.01, -side, w / 4, outerH, d * 0.9, gold, material, p)
		Tech.flatTri(parent, cf, 0, bandH - 0.01, side, w / 4, midH, d * 0.9, gold, material, p)
	end
	-- ball tips
	local tip = w * 0.2
	for _, q in { { -w / 2 + tip * 0.3, outerH }, { 0, midH }, { w / 2 - tip * 0.3, outerH } } do
		Geo.ball(parent, (cf * CFrame.new(q[1], bandH + q[2], 0)).Position, tip, gold, material, Style.tiny())
	end
	-- a big middle gem and two small side gems on the band
	local gem = w * 0.2
	glow(
		parent,
		cf * CFrame.new(0, bandH / 2, -d / 2 - 0.03) * CFrame.Angles(0, 0, math.pi / 4),
		Vector3.new(gem, gem, 0.08),
		o.Gem or C.AwningRed
	)
	for _, x in { -0.31, 0.31 } do
		glow(parent, cf * CFrame.new(x * w, bandH / 2, -d / 2 - 0.03), Vector3.new(w * 0.11, w * 0.11, 0.08), C.CrystalBlue)
	end
end

-- Small labels (boards under this height) get light letters with a solid
-- dark outline: a blue frame-colored stroke smears at distance. The big
-- hero signs keep the glowing frame-colored outline.
Tech.SmallLabel = 2.6

-- Letters on a thin board (no frame). `cf` = board center. 1 part.
function Tech.label(parent: Instance, cf: CFrame, text: string, width: number, height: number, color: Color3?, depth: number?): Part
	local small = height < Tech.SmallLabel
	return Style.sign(parent, cf, text, width, height, {
		Kind = "Glow",
		Frame = false,
		TextColor = color or (if small then C.GlowText else nil),
		BoardColor = Tech.Board,
		Depth = depth or 0.12,
		StrokeColor = if small then Tech.Board else nil,
		StrokeTransparency = if small then 0 else nil,
	})
end

--[[
	Big glowing sign box (concept v2): a chunky gunmetal casing with a light
	top lip and a dark bottom lip, a dark navy board with white letters and
	a chamfered blue neon frame. `cf` = board center, front = LookVector.
	opts:
	  TextColor   letter color (default GlowText)
	  Words       { { Text, Width, Color? } }: separate word plates side by
	              side (viewer's left first) instead of one text, e.g. a blue
	              "&" between orange words; the widths keep the letters the
	              same height
	  Frame       neon frame color (default the thick tube blue)
	  Icon        icon panel width: the letters take the rest; the panel
	              sits on the viewer's right (IconLeft = true: left)
	  Casing      false: no casing (the sign is set into a header that is
	              its casing)
	  Studs       orange light studs in the casing corners (default true)
	  DoubleSided letters on the back too
	  Back        the casing's back: true = a light frame lip with an
	              orange band, a string = that text on a navy back board in
	              a light frame lip (signs seen from behind); BackFrame =
	              true adds the front's thin chamfered neon frame around it
	  Light       range: an invisible floodlight anchor LightDist (2.5) in
	              front of the board with a PointLight that lights the
	              letters (signs that face away from the sun); LightColor
	Returns the text board and the icon panel center (or nil). 14-22 parts.
]]
function Tech.sign(parent: Instance, cf: CFrame, text: string, width: number, height: number, opts: Opts?): (Part, CFrame?)
	local o: Opts = opts or {}
	local iconW: number = o.Icon or 0
	local textW = width - iconW
	-- seen from the front local +X is the viewer's left
	local iconSide = if o.IconLeft then 1 else -1
	local textX = -iconSide * iconW / 2
	local board: Part
	local words: { Opts }? = o.Words
	if words then
		board = bit(parent, cf * CFrame.new(textX, 0, 0), Vector3.new(textW, height, 0.5), o.Board or Tech.Board)
		board.Name = "Sign"
		local total = 0
		for _, word in words do
			total += word.Width
		end
		local x = textX + total / 2
		for _, word in words do
			local ww: number = word.Width
			Tech.label(parent, cf * CFrame.new(x - ww / 2, 0, -0.3), word.Text, ww, height, word.Color or o.TextColor)
			x -= ww
		end
	else
		local small = height < Tech.SmallLabel
		board = Style.sign(parent, cf * CFrame.new(textX, 0, 0), text, textW, height, {
			Kind = "Glow",
			Frame = false,
			TextColor = o.TextColor,
			BoardColor = o.Board or Tech.Board,
			Depth = 0.5,
			DoubleSided = o.DoubleSided,
			StrokeColor = if small then Tech.Board else nil,
			StrokeTransparency = if small then 0 else nil,
		})
	end
	local iconAt: CFrame? = nil
	if iconW > 0 then
		local at = cf * CFrame.new(iconSide * textW / 2, 0, 0)
		bit(parent, at, Vector3.new(iconW, height, 0.5), o.Board or Tech.Board)
		iconAt = at * CFrame.new(0, 0, -0.25)
	end
	-- casing, lips and the back
	local m: number = o.Margin or 0.55 -- casing margin around the board
	local casingD = o.CasingDepth or 1.1
	local casing = o.Casing ~= false
	if casing then
		local lip: number = o.Lip or 0.34
		block(
			parent,
			cf * CFrame.new(0, 0, casingD / 2 - 0.18),
			Vector3.new(width + 2 * m, height + 2 * m, casingD),
			Tech.Metal,
			nil,
			Style.decor()
		)
		bit(
			parent,
			cf * CFrame.new(0, height / 2 + m + lip / 2, casingD / 2 - 0.18),
			Vector3.new(width + 2 * m + 0.3, lip, casingD + 0.3),
			Tech.MetalLight
		)
		bit(
			parent,
			cf * CFrame.new(0, -height / 2 - m - lip / 2, casingD / 2 - 0.18),
			Vector3.new(width + 2 * m + 0.3, lip, casingD + 0.3),
			Tech.MetalDark
		)
		local back = o.Back
		if back then
			local bz = casingD - 0.18
			bit(parent, cf * CFrame.new(0, 0, bz + 0.07), Vector3.new(width + 2 * m - 0.5, height + 2 * m - 0.5, 0.14), Tech.MetalLight)
			if type(back) == "string" then
				local backCf = cf * CFrame.new(0, 0, bz + 0.2) * CFrame.Angles(0, math.pi, 0)
				Tech.label(parent, backCf, back, width - 0.3, height - 0.2, o.TextColor)
				if o.BackFrame then
					-- the back words get the front's thin chamfered neon frame too
					local bhw, bhh = (width - 0.3) / 2 + 0.06, (height - 0.2) / 2 + 0.06
					Tech.outline(parent, backCf, bhw, bhh, math.min(bhh * 0.45, 0.6), 0.16, -0.09, o.Frame or Tech.Tube)
				end
			else
				bit(parent, cf * CFrame.new(0, -height * 0.15, bz + 0.17), Vector3.new(width + 2 * m - 0.5, height * 0.18, 0.08), Tech.Band)
			end
		end
	end
	-- chamfered neon frame
	local t = math.clamp(math.min(width, height) * 0.08, 0.3, 0.45)
	local hw, hh = width / 2 - t / 2 + 0.05, height / 2 - t / 2 + 0.05
	Tech.outline(parent, cf, hw, hh, math.min(hh * 0.45, 0.9), t, -0.32, o.Frame or Tech.Tube)
	if o.Studs ~= false then
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				glow(
					parent,
					cf * CFrame.new(sx * (width / 2 + m * 0.5), sy * (height / 2 + m * 0.5), -0.22),
					Vector3.new(0.3, 0.3, 0.12),
					o.StudColor or Tech.Warm
				)
			end
		end
	end
	local range: number? = o.Light
	if range then
		-- a floodlight in front of the board lights the letters and the casing
		-- (signs that face away from the sun): an invisible anchor, so nothing
		-- hangs under or over the sign (the wheel's pointer, the header lips)
		local lamp = block(
			parent,
			cf * CFrame.new(0, 0, -(o.LightDist or 2.5)),
			Vector3.new(0.2, 0.2, 0.2),
			Tech.Lens,
			nil,
			Style.tiny({ Transparency = 1 })
		)
		lamp.Name = "SignLamp"
		Style.light(lamp, o.LightColor or C.LampAmber, range, 1.4)
	end
	return board, iconAt
end

return Tech
