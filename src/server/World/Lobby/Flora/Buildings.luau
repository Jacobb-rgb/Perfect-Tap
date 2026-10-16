--[[
	Flora town buildings kit: the shapes of Kenney's City Kit (commercial)
	and Space Station Kit rebuilt from Roblox parts (never meshes), in the
	lobby palette.

	  City Kit       storeys split by thick protruding bands, a darker ground
	                 floor, rows of framed windows, a parapet roof with a
	                 recessed deck and rooftop boxes, domes and water tanks,
	                 awnings and overhangs on thin posts, parasols
	  Space Station  thick dark metal corner frames, a colored banner band
	                 across the wall, framed door openings
	  concept v2     blue neon edge strips and roof lines, glowing signs,
	                 display windows (docs/art/lobby_concept_v2.webp)
	  concept v1     stone ground floors, jettied plaster-and-timber upper
	                 floors, slate gable roofs, chimneys, warm lit windows

	A building body is a box on the ground: `Body = { cf, w, d }` with cf at
	the bottom center, LookVector = the front, w along local X, d along
	local Z. Window glow is Neon (no lights). Pure builders (Instance
	creation only), deterministic from the rng.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)

local C = Style.C
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local rgb = Color3.fromRGB

local Buildings = {}

-- Local colors (concept v2 metal and slate; everything else is Style.C).
Buildings.Colors = {
	Metal = rgb(46, 50, 66), -- thick dark metal frames, plinths, parapets
	MetalEdge = rgb(104, 112, 140), -- lit metal trims, antenna masts
	Panel = rgb(118, 126, 150), -- tech wall panels (mid)
	PanelDark = rgb(80, 86, 108), -- tech ground floors
	PanelLight = rgb(146, 154, 176), -- light tech panels
	Plaster = rgb(234, 220, 194), -- cozy upper floors
	PlasterWarm = rgb(240, 200, 150), -- warm plaster variant
	Slate = rgb(70, 78, 108), -- slate roofs (the red roof stays the Great Forge's)
	SlateDark = rgb(48, 54, 78),
	SlateLight = rgb(104, 114, 148),
	Deck = rgb(56, 60, 78), -- flat roof decks
	Display = rgb(110, 196, 255), -- glowing display windows (Neon)
	Window = rgb(255, 178, 90), -- warm lit window panes (Neon; deeper than Lamp so rows of them do not bloom white)
	DoorLeaf = rgb(40, 42, 54),
}
local K = Buildings.Colors

export type Body = { cf: CFrame, w: number, d: number }

-- Storey heights: ground floor and upper floors.
Buildings.Ground = 6.5
Buildings.Upper = 5

function Buildings.height(floors: number): number
	return Buildings.Ground + (floors - 1) * Buildings.Upper
end

function Buildings.box(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	props: { [string]: any }?
): Part
	return Style.block(parent, cf, size, color, material, props)
end

local function glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3): Part
	return Style.block(parent, cf, size, color, NEON, Style.tiny())
end

--[[
	One wall of a body: a CFrame on the wall surface at ground level with
	LookVector pointing outward (local X runs along the wall), and the
	wall's width. side: "Front", "Back", "Left" (local -X), "Right" (+X).
]]
function Buildings.face(body: Body, side: string): (CFrame, number)
	if side == "Front" then
		return body.cf * CFrame.new(0, 0, -body.d / 2), body.w
	elseif side == "Back" then
		return body.cf * CFrame.new(0, 0, body.d / 2) * CFrame.Angles(0, math.pi, 0), body.w
	elseif side == "Right" then
		return body.cf * CFrame.new(body.w / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), body.d
	end
	return body.cf * CFrame.new(-body.w / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), body.d
end

-- A body standing on top of / next to another (same frame, new size, shifted).
function Buildings.sub(body: Body, x: number, z: number, w: number, d: number): Body
	return { cf = body.cf * CFrame.new(x, 0, z), w = w, d = d }
end

---------------------------------------------------------------- windows and doors

--[[
	A row of lit windows on a wall: one dark frame strip with `count` neon
	panes in front of it (the gaps read as mullions). `span` = strip width,
	`y` = pane center height. count + 1 parts.
]]
function Buildings.windowRow(
	parent: Instance,
	wall: CFrame,
	y: number,
	count: number,
	span: number,
	paneH: number,
	frame: Color3,
	pane: Color3?,
	x: number?
): { Part }
	local cx = x or 0
	local gap = 0.6
	local paneW = (span - gap * (count + 1)) / count
	local parts = {}
	table.insert(
		parts,
		Style.block(parent, wall * CFrame.new(cx, y, -0.15), Vector3.new(span, paneH + gap * 2, 0.3), frame, nil, Style.tiny())
	)
	for i = 1, count do
		local px = cx - span / 2 + gap + paneW / 2 + (i - 1) * (paneW + gap)
		local p = glow(parent, wall * CFrame.new(px, y, -0.34), Vector3.new(paneW, paneH, 0.12), pane or K.Window)
		p.Name = "WindowGlow"
		table.insert(parts, p)
	end
	return parts
end

-- One framed window (City Kit: thick frame, glowing pane). 2 parts.
function Buildings.window(parent: Instance, wall: CFrame, x: number, y: number, w: number, h: number, frame: Color3, pane: Color3?): Part
	Style.block(parent, wall * CFrame.new(x, y, -0.15), Vector3.new(w + 1, h + 1, 0.3), frame, nil, Style.tiny())
	local p = glow(parent, wall * CFrame.new(x, y, -0.34), Vector3.new(w, h, 0.12), pane or K.Window)
	p.Name = "WindowGlow"
	return p
end

--[[
	Door: a dark leaf in a frame (two jambs and a lintel), standing on
	`y0`. `neon` makes the frame a glowing blue Space Station door frame.
	A small lit transom over the leaf. 5 parts.
]]
function Buildings.door(
	parent: Instance,
	wall: CFrame,
	x: number,
	y0: number,
	w: number,
	h: number,
	frame: Color3,
	leaf: Color3,
	neon: boolean?
)
	local mat = if neon then NEON else SMOOTH
	Style.block(parent, wall * CFrame.new(x, y0 + h / 2, -0.12), Vector3.new(w, h, 0.24), leaf, nil, Style.tiny())
	glow(parent, wall * CFrame.new(x, y0 + h - 0.7, -0.27), Vector3.new(w * 0.6, 0.6, 0.1), C.Lamp)
	Style.block(parent, wall * CFrame.new(x - w / 2 - 0.3, y0 + h / 2, -0.2), Vector3.new(0.6, h, 0.4), frame, mat, Style.tiny())
	Style.block(parent, wall * CFrame.new(x + w / 2 + 0.3, y0 + h / 2, -0.2), Vector3.new(0.6, h, 0.4), frame, mat, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, y0 + h + 0.3, -0.2), Vector3.new(w + 1.2, 0.6, 0.4), frame, mat, Style.tiny())
end

-- Wall lamp: an iron arm and a glowing box (no light). 2 parts.
function Buildings.wallLamp(parent: Instance, wall: CFrame, x: number, y: number)
	Style.block(parent, wall * CFrame.new(x, y, -0.45), Vector3.new(0.3, 0.3, 0.9), C.Iron, nil, Style.tiny())
	local g = glow(parent, wall * CFrame.new(x, y - 0.45, -0.85), Vector3.new(0.7, 0.8, 0.7), C.Lamp)
	g.Name = "LanternGlow"
end

---------------------------------------------------------------- shells

export type TechOpts = {
	Floors: number,
	Accent: Color3?, -- the Space Station banner band
	Wall: Color3?,
	Ground: Color3?,
	Neon: Color3?, -- corner edge strips (default GlowEdge); Edges = false skips them
	Edges: boolean?,
	Corners: boolean?, -- thick metal corner frames (default true)
}

--[[
	Space Station / City Kit tech block: metal plinth, dark ground floor,
	panel upper floors, thick metal storey bands, a banner band, metal
	corner frames with blue neon strips on their outer edges. Returns the
	wall top height. 9-15 parts.
]]
function Buildings.techShell(parent: Instance, body: Body, o: TechOpts, rng: Rng.Rng): number
	local w, d = body.w, body.d
	local G, U = Buildings.Ground, Buildings.Upper
	local H = Buildings.height(o.Floors)
	local cf = body.cf
	Style.block(parent, cf * CFrame.new(0, 0.3, 0), Vector3.new(w + 0.9, 0.6, d + 0.9), K.Metal, nil, Style.solid())
	Style.block(
		parent,
		cf * CFrame.new(0, G / 2, 0),
		Vector3.new(w, G, d),
		Style.vary(o.Ground or K.PanelDark, rng, 0.03),
		nil,
		Style.solid()
	)
	if o.Floors > 1 then
		Style.block(
			parent,
			cf * CFrame.new(0, G + (H - G) / 2, 0),
			Vector3.new(w, H - G, d),
			Style.vary(o.Wall or K.Panel, rng, 0.03),
			nil,
			Style.solid()
		)
	end
	-- banner band under the first storey band (wraps all four walls)
	Style.block(parent, cf * CFrame.new(0, G - 0.95, 0), Vector3.new(w + 0.24, 0.9, d + 0.24), o.Accent or C.Hazard, nil, Style.tiny())
	-- thick storey bands
	for f = 1, o.Floors - 1 do
		local y = G + (f - 1) * U
		Style.block(parent, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.7, 0.6, d + 0.7), K.Metal, nil, Style.ghost())
	end
	if o.Corners ~= false then
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				Style.block(
					parent,
					cf * CFrame.new(sx * w / 2, H / 2 + 0.3, sz * d / 2),
					Vector3.new(1.1, H - 0.6, 1.1),
					K.Metal,
					nil,
					Style.decor()
				)
			end
		end
		if o.Edges ~= false then
			-- concept v2 neon outlines: a glowing strip on the outer edge of every corner frame
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					glow(
						parent,
						cf * CFrame.new(sx * (w / 2 + 0.55), H / 2 + 0.6, sz * (d / 2 + 0.55)),
						Vector3.new(0.26, H - 1.8, 0.26),
						o.Neon or C.GlowEdge
					)
				end
			end
		end
	end
	return H
end

export type CozyOpts = {
	Floors: number,
	Stone: Color3?,
	Plaster: Color3?,
	Timber: Color3?,
	Quoins: boolean?, -- light stone corner blocks on the ground floor
}

--[[
	Concept v1 town house: stone ground floor on a plinth, a jettied
	plaster upper part with timber corner posts and beams. Returns the
	top of the walls. 7-11 parts.
]]
function Buildings.cozyShell(parent: Instance, body: Body, o: CozyOpts, rng: Rng.Rng): number
	local w, d = body.w, body.d
	local G = Buildings.Ground
	local H = Buildings.height(o.Floors)
	local cf = body.cf
	local timber = o.Timber or C.WoodDark
	Style.block(
		parent,
		cf * CFrame.new(0, 0.35, 0),
		Vector3.new(w + 0.8, 0.7, d + 0.8),
		Style.vary(C.StoneDark, rng, 0.04),
		nil,
		Style.solid()
	)
	Style.block(parent, cf * CFrame.new(0, G / 2, 0), Vector3.new(w, G, d), Style.vary(o.Stone or C.Stone, rng, 0.04), nil, Style.solid())
	if o.Quoins ~= false then
		for _, sx in { -1, 1 } do
			Style.block(
				parent,
				cf * CFrame.new(sx * w / 2, G / 2 + 0.3, -d / 2),
				Vector3.new(1, G - 0.6, 1),
				C.StoneLight,
				nil,
				Style.tiny()
			)
		end
	end
	if o.Floors > 1 then
		local jw, jd = w + 0.5, d + 0.5
		Style.block(parent, cf * CFrame.new(0, G, 0), Vector3.new(w + 1, 0.6, d + 1), timber, nil, Style.ghost())
		Style.block(
			parent,
			cf * CFrame.new(0, G + 0.3 + (H - G - 0.3) / 2, 0),
			Vector3.new(jw, H - G - 0.3, jd),
			Style.vary(o.Plaster or K.Plaster, rng, 0.03),
			nil,
			Style.solid()
		)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				Style.block(
					parent,
					cf * CFrame.new(sx * jw / 2, G + (H - G) / 2, sz * jd / 2),
					Vector3.new(0.6, H - G, 0.6),
					timber,
					nil,
					Style.tiny()
				)
			end
		end
		Style.block(parent, cf * CFrame.new(0, H, 0), Vector3.new(w + 1, 0.5, d + 1), timber, nil, Style.ghost())
	end
	return H
end

---------------------------------------------------------------- roofs

--[[
	City Kit flat roof: a parapet slab with a darker deck inset on top,
	optional neon line along the front rim. Returns the deck height. 2-3 parts.
]]
function Buildings.flatRoof(parent: Instance, body: Body, top: number, neonFront: Color3?, rim: Color3?): number
	local cf = body.cf
	Style.block(parent, cf * CFrame.new(0, top + 0.45, 0), Vector3.new(body.w + 0.8, 0.9, body.d + 0.8), rim or K.Metal, nil, Style.decor())
	Style.block(parent, cf * CFrame.new(0, top + 0.95, 0), Vector3.new(body.w - 0.6, 0.12, body.d - 0.6), K.Deck, nil, Style.tiny())
	if neonFront then
		glow(parent, cf * CFrame.new(0, top + 0.3, -body.d / 2 - 0.47), Vector3.new(body.w + 0.8, 0.22, 0.12), neonFront)
	end
	return top + 1
end

--[[
	Slate gable roof with plaster (or timber) gable ends, ridge along the
	body's local X (pass a body turned a quarter for a gable-front house).
	Overhangs: 0.6 at the gables, ~0.9 at the eaves. 5 parts.
]]
function Buildings.gableRoof(parent: Instance, body: Body, eave: number, h: number, infill: Color3, slate: Color3?)
	local w, half = body.w, body.d / 2
	local base = body.cf * CFrame.new(0, eave, 0)
	local p = Style.decor()
	Geo.wedge(parent, base * CFrame.new(0, h / 2, -half / 2), Vector3.new(w, h, half), infill, SMOOTH, p)
	Geo.wedge(parent, base * CFrame.new(0, h / 2, half / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, h, half), infill, SMOOTH, p)
	local a = math.atan2(h, half)
	local len = math.sqrt(h * h + half * half)
	for _, s in { -1, 1 } do
		local mid = Vector3.new(0, h / 2, s * half / 2)
		local n = Vector3.new(0, math.cos(a), s * math.sin(a))
		local down = Vector3.new(0, -math.sin(a), s * math.cos(a))
		local c = mid + n * 0.25 + down * 0.3
		Style.block(
			parent,
			base * CFrame.new(c) * CFrame.Angles(s * a, 0, 0),
			Vector3.new(w + 1.2, 0.5, len + 0.6),
			slate or K.Slate,
			nil,
			p
		)
	end
	Style.block(
		parent,
		base * CFrame.new(0, h + 0.2, 0),
		Vector3.new(w + 1.4, 0.55, 1),
		K.SlateDark,
		nil,
		Style.tiny({ CastShadow = true })
	)
end

--[[
	Stepped voxel hip roof: shrinking slate slabs (lightest on top), like
	the concept's tiled tower caps. Returns the top height. `steps` parts.
]]
function Buildings.steppedRoof(parent: Instance, body: Body, top: number, steps: number, colors: { Color3 }?): number
	local shades = colors or { K.SlateDark, K.Slate, K.SlateLight }
	local y = top
	for i = 1, steps do
		local f = 1 - (i - 1) * 0.3
		local h = 0.9
		Style.block(
			parent,
			body.cf * CFrame.new(0, y + h / 2, 0),
			Vector3.new(body.w * f + 0.8, h, body.d * f + 0.8),
			shades[math.min(i, #shades)],
			nil,
			if i == 1 then Style.decor() else Style.tiny({ CastShadow = true })
		)
		y += h
	end
	return y
end

---------------------------------------------------------------- awnings and overhangs

--[[
	City Kit overhang over a shop front: a slab sloping slightly outward
	with a front lip, on two thin posts; `neon` adds a glowing lip line.
	`wall` = the wall frame, `y` = slab height, `depth` = reach. 4-5 parts.
]]
function Buildings.overhang(
	parent: Instance,
	wall: CFrame,
	x: number,
	y: number,
	w: number,
	depth: number,
	color: Color3,
	posts: boolean?,
	neon: Color3?
)
	local slab = wall * CFrame.new(x, y, -depth / 2) * CFrame.Angles(math.rad(-6), 0, 0)
	Style.block(parent, slab, Vector3.new(w, 0.35, depth), color, nil, Style.ghost())
	Style.block(parent, wall * CFrame.new(x, y - 0.35, -depth + 0.15), Vector3.new(w, 0.7, 0.3), color, nil, Style.tiny())
	if neon then
		glow(parent, wall * CFrame.new(x, y - 0.35, -depth + 0.02), Vector3.new(w - 0.2, 0.2, 0.08), neon)
	end
	if posts then
		for _, sx in { -1, 1 } do
			Style.block(
				parent,
				wall * CFrame.new(x + sx * (w / 2 - 0.3), (y - 0.6) / 2, -depth + 0.3),
				Vector3.new(0.3, y - 0.6, 0.3),
				K.Metal,
				nil,
				Style.tiny()
			)
		end
	end
end

-- Striped awning (concept v1 stalls): `stripes` sloped slabs. stripes parts.
function Buildings.awning(
	parent: Instance,
	wall: CFrame,
	x: number,
	y: number,
	w: number,
	depth: number,
	a: Color3,
	b: Color3,
	stripes: number
)
	Style.awning(parent, wall * CFrame.new(x, y, 0), w, depth, 1.4, a, b, { Stripes = stripes, Scallops = false })
end

---------------------------------------------------------------- rooftop and wall details

-- City Kit rooftop box (AC unit) with a fan disc. 2 parts.
function Buildings.vent(parent: Instance, at: CFrame, rng: Rng.Rng)
	local w, d = rng:range(1.6, 2.2), rng:range(1.4, 1.8)
	Style.block(parent, at * CFrame.new(0, 0.6, 0), Vector3.new(w, 1.2, d), K.PanelLight, nil, Style.tiny({ CastShadow = true }))
	Geo.cylinder(parent, (at * CFrame.new(0, 1.25, 0)).Position, 0.12, math.min(w, d) * 0.7, K.Metal, SMOOTH, Style.tiny())
end

-- City Kit rooftop dome (a half-buried ball). 1 part.
function Buildings.dome(parent: Instance, at: CFrame, size: number)
	Geo.ball(parent, (at * CFrame.new(0, size * 0.1, 0)).Position, size, K.PanelLight, SMOOTH, Style.tiny())
end

-- City Kit water tank on a stand (building-l). 4 parts.
function Buildings.waterTank(parent: Instance, at: CFrame, size: number?)
	local s = size or 3
	Style.block(parent, at * CFrame.new(0, 0.6, 0), Vector3.new(s * 0.8, 1.2, s * 0.8), K.Metal, nil, Style.tiny({ CastShadow = true }))
	local p = at.Position
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.45, 0), s * 0.9, s, C.Wood, SMOOTH, Style.tiny({ CastShadow = true }))
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.45, 0), 0.3, s + 0.12, C.Iron, SMOOTH, Style.tiny())
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.95, 0), 0.3, s * 1.1, K.SlateDark, SMOOTH, Style.tiny())
end

-- Antenna mast with a crossbar and a glowing tip. 3 parts.
function Buildings.antenna(parent: Instance, at: CFrame, h: number, tip: Color3)
	Style.block(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(0.3, h, 0.3), K.MetalEdge, nil, Style.tiny())
	Style.block(parent, at * CFrame.new(0, h * 0.7, 0), Vector3.new(1.8, 0.2, 0.2), K.MetalEdge, nil, Style.tiny())
	glow(parent, at * CFrame.new(0, h + 0.3, 0), Vector3.new(0.6, 0.6, 0.6), tip)
end

-- Stone chimney with a dark cap. 2 parts.
function Buildings.chimney(parent: Instance, at: CFrame, h: number, rng: Rng.Rng)
	Style.block(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(1.4, h, 1.4), Style.vary(C.StoneDark, rng, 0.05), nil, Style.decor())
	Style.block(parent, at * CFrame.new(0, h + 0.2, 0), Vector3.new(1.9, 0.4, 1.9), C.StoneDeep, nil, Style.tiny())
end

--[[
	Hanging cloth banner (concept v2's red forge banners): a metal rod, the
	cloth and a gold stripe near the bottom. `wall` = wall frame. 3 parts.
]]
function Buildings.banner(parent: Instance, wall: CFrame, x: number, top: number, w: number, h: number, color: Color3)
	Style.block(parent, wall * CFrame.new(x, top, -0.35), Vector3.new(w + 0.6, 0.3, 0.3), K.Metal, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, top - h / 2, -0.3), Vector3.new(w, h, 0.15), color, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, top - h + 0.7, -0.4), Vector3.new(w, 0.35, 0.1), C.Gold, nil, Style.tiny())
end

--[[
	Glowing sign standing on a roof edge on two metal legs (concept v2's big
	neon signs). `at` = the bottom center of the sign (on the roof), front =
	LookVector. 7 parts.
]]
function Buildings.roofSign(parent: Instance, at: CFrame, text: string, w: number, h: number): Part
	for _, sx in { -1, 1 } do
		Style.block(parent, at * CFrame.new(sx * w * 0.3, 0.5, 0.35), Vector3.new(0.35, 1.2, 0.35), K.Metal, nil, Style.tiny())
	end
	local board = Style.sign(parent, at * CFrame.new(0, 1 + h / 2, 0), text, w, h, { Kind = "Glow", Depth = 0.5 })
	board.Name = "TownSign"
	board.CanCollide = false
	return board
end

-- Glowing sign flat on a wall (`wall` frame, center height y, `out` = gap to the wall). 5 parts.
function Buildings.wallSign(parent: Instance, wall: CFrame, x: number, y: number, text: string, w: number, h: number, out: number?): Part
	local board = Style.sign(parent, wall * CFrame.new(x, y, -0.25 - (out or 0.1)), text, w, h, { Kind = "Glow", Depth = 0.5 })
	board.Name = "TownSign"
	board.CanCollide = false
	return board
end

-- City Kit parasol: a pole, a canopy of two turned slabs and a round foot. 4 parts.
function Buildings.parasol(parent: Instance, at: CFrame, color: Color3)
	Style.block(parent, at * CFrame.new(0, 0.1, 0), Vector3.new(1.4, 0.2, 1.4), K.PanelLight, nil, Style.tiny())
	Style.block(parent, at * CFrame.new(0, 1.4, 0), Vector3.new(0.25, 2.6, 0.25), K.Metal, nil, Style.tiny())
	Style.block(parent, at * CFrame.new(0, 2.8, 0), Vector3.new(3.2, 0.4, 3.2), color, nil, Style.tiny({ CastShadow = true }))
	Style.block(
		parent,
		at * CFrame.new(0, 3.05, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(2.2, 0.35, 2.2),
		color,
		nil,
		Style.tiny()
	)
end

return Buildings
