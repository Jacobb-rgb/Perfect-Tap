--[[
	Flora town buildings kit: the shapes of Kenney's City Kit (commercial)
	and Space Station Kit rebuilt from Roblox parts (never meshes), in the
	lobby palette.

	  City Kit       storeys split by thick protruding bands, a darker ground
	                 floor, rows of framed windows, setback upper boxes
	                 (building-d), wide low blocks with long window rows
	                 (building-k), parapet roofs with recessed decks, rooftop
	                 boxes, domes and water tanks, awnings and overhangs
	  Space Station  dark metal corner frames, round corner pillars with an
	                 orange band (wall-corner-round-banner), a tall orange
	                 banner band across the ground floor (wall-banner),
	                 orange window and door frames (wall-window-banner,
	                 wall-door-wide-banner), container-tall, pipe rings
	  concept v2     dark charcoal metal walls, thin blue neon outlines and
	                 roof lines, warm lit windows, dark navy signs with white
	                 text, a blue neon frame and an icon
	                 (docs/art/lobby_concept_v2.webp)
	  concept v1     stone ground floors, jettied plaster upper floors with
	                 dark half-timbering, window boxes with flowers, hanging
	                 lanterns, slate gable roofs, chimneys

	A building body is a box on the ground: `Body = { cf, w, d }` with cf at
	the bottom center, LookVector = the front, w along local X, d along
	local Z. Glow is Neon (no lights); big glowing planes are avoided (they
	bloom to white in the renders), so display glass is SmoothPlastic with
	one thin neon strip. Pure builders (Instance creation only),
	deterministic from the rng.
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

-- Local colors (concept v2 metal, slate and signs; everything else is Style.C).
Buildings.Colors = {
	Metal = rgb(34, 37, 50), -- thick dark metal frames, plinths, parapets, storey bands
	MetalEdge = rgb(104, 112, 140), -- lit metal trims, antenna masts, pipe rings
	Panel = rgb(86, 92, 118), -- tech upper walls (slate charcoal, concept v2; darker than the old pale panels, light enough not to read black in the shade)
	PanelDark = rgb(60, 64, 86), -- tech ground floors
	PanelLight = rgb(118, 126, 152), -- thin accent bands (storey bands), round corner pillars
	Plaster = rgb(228, 206, 168), -- cozy upper floors
	PlasterWarm = rgb(236, 190, 140), -- warm plaster variant
	Slate = rgb(70, 78, 108), -- slate roofs (the red roof stays the Great Forge's)
	SlateDark = rgb(48, 54, 78),
	SlateLight = rgb(104, 114, 148),
	Deck = rgb(52, 56, 72), -- flat roof decks
	Glass = rgb(44, 104, 180), -- display glass (SmoothPlastic: no bloom)
	Window = rgb(236, 138, 52), -- warm lit window panes (Neon; deep amber so they glow warm, not white)
	WindowDark = rgb(28, 36, 58), -- unlit window glass (SmoothPlastic)
	EdgeNeon = rgb(48, 150, 255), -- the thin blue outline strips (a deeper blue than GlowEdge: no white bloom)
	SignNeon = rgb(40, 128, 240), -- sign frames
	Amber = rgb(255, 150, 40), -- sign icons (deeper than Gold / Lamp)
	DoorLeaf = rgb(30, 32, 42),
	SignBoard = rgb(16, 24, 56), -- dark navy sign boards
	SignText = rgb(214, 228, 255), -- light blue-white letters (pure white blooms in the sun)
}
local K = Buildings.Colors

export type Body = { cf: CFrame, w: number, d: number }

-- Storey heights: ground floor and upper floors.
Buildings.Ground = 7
Buildings.Upper = 5

function Buildings.height(floors: number): number
	return Buildings.Ground + (floors - 1) * Buildings.Upper
end

-- Window center height of floor f (1 = the ground floor).
function Buildings.floorY(f: number): number
	if f <= 1 then
		return 3.1
	end
	return Buildings.Ground + (f - 2) * Buildings.Upper + Buildings.Upper * 0.52
end

local function glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3): Part
	return Style.block(parent, cf, size, color, NEON, Style.tiny())
end
Buildings.glow = glow

--[[
	Is the window pane at this world position lit? About three in four are:
	a fixed hash of the position, so whole facades never read as one
	glowing block and the build stays deterministic.
]]
function Buildings.lit(cf: CFrame): boolean
	local p = cf.Position
	local h = math.floor(p.X * 1.7 + p.Z * 2.3 + p.Y * 0.9)
	return h % 4 ~= 0
end

-- A window pane: lit (warm Neon, named WindowGlow) or dark glass (Window).
local function pane(parent: Instance, cf: CFrame, size: Vector3, color: Color3?, forceLit: boolean?): Part
	if forceLit or color ~= nil or Buildings.lit(cf) then
		local p = glow(parent, cf, size, color or K.Window)
		p.Name = "WindowGlow"
		return p
	end
	local p = Style.block(parent, cf, size, K.WindowDark, nil, Style.tiny())
	p.Name = "Window"
	return p
end

--[[
	One wall of a body: a CFrame on the wall surface at ground level with
	LookVector pointing outward (local X runs along the wall), and the
	wall's width. side: "Front", "Back", "Left" (local -X), "Right" (+X).
	Seen from outside, the wall's local +X is on the viewer's LEFT.
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
	A row of lit windows on a wall: one frame strip with `count` neon panes
	in front of it (the gaps read as mullions). `span` = strip width,
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
	color: Color3?,
	x: number?
): { Part }
	local cx = x or 0
	local gap = 0.7
	local paneW = (span - gap * (count + 1)) / count
	local parts = {}
	table.insert(
		parts,
		Style.block(parent, wall * CFrame.new(cx, y, -0.15), Vector3.new(span, paneH + gap * 2, 0.3), frame, nil, Style.tiny())
	)
	for i = 1, count do
		local px = cx - span / 2 + gap + paneW / 2 + (i - 1) * (paneW + gap)
		table.insert(parts, pane(parent, wall * CFrame.new(px, y, -0.34), Vector3.new(paneW, paneH, 0.12), color, i == 1 and count >= 3))
	end
	return parts
end

--[[
	One framed window (City Kit: thick frame, a pane lit or dark). Pass
	C.Hazard as the frame for a Space Station banner window; `lit` forces
	the pane to glow. 2 parts.
]]
function Buildings.window(parent: Instance, wall: CFrame, x: number, y: number, w: number, h: number, frame: Color3, lit: boolean?): Part
	Style.block(parent, wall * CFrame.new(x, y, -0.15), Vector3.new(w + 1, h + 1, 0.3), frame, nil, Style.tiny())
	return pane(parent, wall * CFrame.new(x, y, -0.34), Vector3.new(w, h, 0.12), nil, lit)
end

--[[
	Space Station display wall: a dark metal frame, SmoothPlastic glass
	(no bloom), one thin neon strip along the top and a sill with two small
	goods in front of the glass. 6 parts.
]]
function Buildings.display(parent: Instance, wall: CFrame, x: number, y: number, w: number, h: number, goods: Color3?)
	Style.block(parent, wall * CFrame.new(x, y, -0.15), Vector3.new(w + 1, h + 1, 0.3), K.Metal, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, y, -0.34), Vector3.new(w, h, 0.12), K.Glass, nil, Style.tiny())
	glow(parent, wall * CFrame.new(x, y + h / 2 - 0.2, -0.44), Vector3.new(w - 0.4, 0.15, 0.08), K.EdgeNeon)
	Style.block(parent, wall * CFrame.new(x, y - h / 2 + 0.15, -0.5), Vector3.new(w, 0.3, 0.5), K.MetalEdge, nil, Style.tiny())
	local g = goods or C.CrystalPurple
	Style.block(parent, wall * CFrame.new(x - w * 0.22, y - h / 2 + 0.65, -0.55), Vector3.new(0.6, 0.7, 0.4), g, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x + w * 0.22, y - h / 2 + 0.55, -0.55), Vector3.new(0.8, 0.5, 0.4), C.Gold, nil, Style.tiny())
end

--[[
	Door: a dark leaf in a frame (two jambs and a lintel, SmoothPlastic),
	standing on `y0`, with a small lit transom. `line` adds a thin neon
	line inside the frame (concept v2 door outline). 5 parts, 8 with a line.
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
	line: Color3?
)
	Style.block(parent, wall * CFrame.new(x, y0 + h / 2, -0.12), Vector3.new(w, h, 0.24), leaf, nil, Style.tiny())
	glow(parent, wall * CFrame.new(x, y0 + h - 0.6, -0.27), Vector3.new(w * 0.56, 0.5, 0.1), C.Lamp)
	Style.block(parent, wall * CFrame.new(x - w / 2 - 0.3, y0 + h / 2, -0.2), Vector3.new(0.6, h, 0.4), frame, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x + w / 2 + 0.3, y0 + h / 2, -0.2), Vector3.new(0.6, h, 0.4), frame, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, y0 + h + 0.3, -0.2), Vector3.new(w + 1.2, 0.6, 0.4), frame, nil, Style.tiny())
	if line then
		-- 0.15 neon line on the inner edge of the frame, standing just proud of it
		glow(parent, wall * CFrame.new(x - w / 2 - 0.08, y0 + h / 2, -0.43), Vector3.new(0.15, h - 0.1, 0.06), line)
		glow(parent, wall * CFrame.new(x + w / 2 + 0.08, y0 + h / 2, -0.43), Vector3.new(0.15, h - 0.1, 0.06), line)
		glow(parent, wall * CFrame.new(x, y0 + h + 0.08, -0.43), Vector3.new(w + 0.31, 0.15, 0.06), line)
	end
end

-- Wall lamp: an iron arm and a glowing box (no light). 2 parts.
function Buildings.wallLamp(parent: Instance, wall: CFrame, x: number, y: number)
	Style.block(parent, wall * CFrame.new(x, y, -0.45), Vector3.new(0.3, 0.3, 0.9), C.Iron, nil, Style.tiny())
	local g = glow(parent, wall * CFrame.new(x, y - 0.45, -0.85), Vector3.new(0.6, 0.7, 0.6), C.Lamp)
	g.Name = "LanternGlow"
end

--[[
	Hanging lantern by a door (concept v1): a bracket arm, a dark cap and a
	glowing box (Neon, no light). 3 parts.
]]
function Buildings.hangingLantern(parent: Instance, wall: CFrame, x: number, y: number)
	Style.block(parent, wall * CFrame.new(x, y, -0.45), Vector3.new(0.25, 0.25, 0.9), C.Iron, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, y - 0.3, -0.85), Vector3.new(0.8, 0.25, 0.8), C.Iron, nil, Style.tiny())
	local g = glow(parent, wall * CFrame.new(x, y - 0.8, -0.85), Vector3.new(0.55, 0.8, 0.55), C.Lamp)
	g.Name = "LanternGlow"
end

-- Window box with flower cubes under a window (concept v1). 3 parts.
function Buildings.windowBox(parent: Instance, wall: CFrame, x: number, y: number, w: number, flower: Color3)
	Style.block(parent, wall * CFrame.new(x, y, -0.45), Vector3.new(w, 0.5, 0.7), C.Wood, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, y + 0.4, -0.45), Vector3.new(w - 0.3, 0.35, 0.5), C.LeafGreenDark, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, y + 0.65, -0.5), Vector3.new(w - 0.8, 0.4, 0.4), flower, nil, Style.tiny())
end

--[[
	Dark half-timber strips across a plaster wall between y0 and y1:
	`posts` vertical studs spread over the wall plus one diagonal brace.
	posts + 1 parts.
]]
function Buildings.halfTimber(parent: Instance, wall: CFrame, width: number, y0: number, y1: number, posts: number, out: number?)
	local z = -(out or 0) - 0.1
	local h = y1 - y0
	for i = 1, posts do
		local x = -width / 2 + width * i / (posts + 1)
		Style.block(parent, wall * CFrame.new(x, y0 + h / 2, z), Vector3.new(0.35, h, 0.2), C.WoodDark, nil, Style.tiny())
	end
	-- one brace in the first bay
	local bay = width / (posts + 1)
	local len = math.sqrt(bay * bay + h * h)
	local a = math.atan2(h, bay)
	Style.block(
		parent,
		wall * CFrame.new(-width / 2 + bay / 2, y0 + h / 2, z) * CFrame.Angles(0, 0, a),
		Vector3.new(len - 0.3, 0.3, 0.18),
		C.WoodDark,
		nil,
		Style.tiny()
	)
end

---------------------------------------------------------------- shells

export type TechOpts = {
	Floors: number,
	Accent: Color3?, -- the Space Station banner band (default orange)
	Wall: Color3?,
	Ground: Color3?,
	Neon: Color3?, -- front corner outline strips (default EdgeNeon); Edges = false skips them
	Edges: boolean?,
	Corners: string?, -- "Square" (default), "Round" (round front pillars with a banner ring), "None"
	Lines: boolean?, -- a thin neon line under every storey band on the front (concept v2 outlines)
}

--[[
	Space Station / City Kit tech block: metal plinth, dark ground floor,
	charcoal upper floors, a 1.6 tall orange banner band across the ground
	floor (under the first storey band), thick metal storey bands and
	corners: square metal frames, or round front pillars with an orange
	band and a cap ring (wall-corner-round-banner). Thin blue neon strips
	outline the front corners. Returns the wall top height. 9-17 parts.
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
	-- the Space Station banner band (wraps all four walls under the first storey band)
	Style.block(parent, cf * CFrame.new(0, G - 1.1, 0), Vector3.new(w + 0.24, 1.6, d + 0.24), o.Accent or C.Hazard, nil, Style.decor())
	-- storey bands: thin light accent bands between the dark wall and the metal frames
	for f = 1, o.Floors - 1 do
		local y = G + (f - 1) * U
		Style.block(parent, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.5, 0.5, d + 0.5), K.PanelLight, nil, Style.ghost())
		if o.Lines and f > 1 then
			glow(parent, cf * CFrame.new(0, y - 0.34, -d / 2 - 0.05), Vector3.new(w - 1.2, 0.12, 0.08), o.Neon or K.EdgeNeon)
		end
	end
	local corners = o.Corners or "Square"
	local neon = if o.Edges == false then nil else (o.Neon or K.EdgeNeon)
	if corners == "Square" then
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
			if neon then
				-- concept v2 outline: a thin glowing strip on the outer edge of the front frames
				glow(parent, cf * CFrame.new(sx * (w / 2 + 0.56), H / 2 + 0.6, -(d / 2 + 0.56)), Vector3.new(0.15, H - 2, 0.15), neon)
			end
		end
	elseif corners == "Round" then
		for _, sx in { -1, 1 } do
			-- back corners: square frames
			Style.block(
				parent,
				cf * CFrame.new(sx * w / 2, H / 2 + 0.3, d / 2),
				Vector3.new(1.1, H - 0.6, 1.1),
				K.Metal,
				nil,
				Style.decor()
			)
			-- front corners: round pillar, orange banner ring at the band height, a metal cap ring
			local p = (cf * CFrame.new(sx * w / 2, 0, -d / 2)).Position
			Geo.cylinder(parent, p + Vector3.new(0, H / 2 + 0.3, 0), H - 0.6, 1.8, K.PanelLight, SMOOTH, Style.decor())
			Geo.cylinder(parent, p + Vector3.new(0, G - 1.1, 0), 1.6, 2.1, o.Accent or C.Hazard, SMOOTH, Style.tiny())
			Geo.cylinder(parent, p + Vector3.new(0, H - 0.2, 0), 0.5, 2.1, K.Metal, SMOOTH, Style.tiny())
			if neon then
				local out = (cf * CFrame.new(sx * (w / 2 + 0.66), 0, -(d / 2 + 0.66))).Position
				glow(
					parent,
					CFrame.new(out + Vector3.new(0, (G + H) / 2, 0)) * (cf - cf.Position),
					Vector3.new(0.16, H - G - 1, 0.16),
					neon
				)
			end
		end
	end
	return H
end

--[[
	City Kit setback box (building-d): a smaller block standing on a roof
	deck at `y0` with its own storey band at the bottom and `floors`
	storeys of `U`. Returns its top. 2 parts.
]]
function Buildings.setback(parent: Instance, body: Body, y0: number, floors: number, wall: Color3?, rng: Rng.Rng): number
	local h = floors * Buildings.Upper
	Style.block(
		parent,
		body.cf * CFrame.new(0, y0 + h / 2, 0),
		Vector3.new(body.w, h, body.d),
		Style.vary(wall or K.Panel, rng, 0.03),
		nil,
		Style.decor()
	)
	Style.block(parent, body.cf * CFrame.new(0, y0 + 0.3, 0), Vector3.new(body.w + 0.5, 0.6, body.d + 0.5), K.Metal, nil, Style.ghost())
	return y0 + h
end

export type CozyOpts = {
	Floors: number,
	Stone: Color3?,
	Plaster: Color3?,
	Timber: Color3?,
	Quoins: boolean?, -- light stone corner blocks on the ground floor
	Timbering: number?, -- half-timber studs per plaster wall (front, back, sides); 0 = none
}

--[[
	Concept v1 town house: stone ground floor on a plinth, a jettied
	plaster upper part with timber corner posts and beams and dark
	half-timbering on the front and back. Returns the top of the walls.
	7-17 parts.
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
		-- 0.9 wide and stopping under the jetty band (no faces shared with it)
		local top = G - 0.35
		for _, sx in { -1, 1 } do
			Style.block(
				parent,
				cf * CFrame.new(sx * w / 2, 0.7 + (top - 0.7) / 2, -d / 2),
				Vector3.new(0.9, top - 0.7, 0.9),
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
		local studs = o.Timbering or 2
		if studs > 0 then
			local jetty = Buildings.sub(body, 0, 0, jw, jd)
			for _, side in { "Front", "Back" } do
				local wall, ww = Buildings.face(jetty, side)
				Buildings.halfTimber(parent, wall, ww - 0.6, G + 0.3, H - 0.25, studs)
			end
		end
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
		glow(parent, cf * CFrame.new(0, top + 0.3, -body.d / 2 - 0.46), Vector3.new(body.w + 0.6, 0.16, 0.1), neonFront)
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
	`wall` = the wall frame, `y` = slab height, `depth` = reach. 3-5 parts.
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
		glow(parent, wall * CFrame.new(x, y - 0.35, -depth - 0.03), Vector3.new(w - 0.4, 0.15, 0.06), neon)
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
	glow(parent, at * CFrame.new(0, h + 0.25, 0), Vector3.new(0.5, 0.5, 0.5), tip)
end

-- Stone chimney with a dark cap. 2 parts.
function Buildings.chimney(parent: Instance, at: CFrame, h: number, rng: Rng.Rng)
	Style.block(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(1.4, h, 1.4), Style.vary(C.StoneDark, rng, 0.05), nil, Style.decor())
	Style.block(parent, at * CFrame.new(0, h + 0.2, 0), Vector3.new(1.9, 0.4, 1.9), C.StoneDeep, nil, Style.tiny())
end

--[[
	Space Station container-tall: an upright drum with two metal rings and
	a cap (`at` = ground center). 4 parts.
]]
function Buildings.container(parent: Instance, at: Vector3, h: number, color: Color3)
	local dia = 1.9
	local body = Geo.cylinder(parent, at + Vector3.new(0, h / 2, 0), h, dia, color, SMOOTH, Style.decor())
	body.Name = "Container"
	for _, f in { 0.22, 0.72 } do
		Geo.cylinder(parent, at + Vector3.new(0, h * f, 0), 0.4, dia + 0.25, K.MetalEdge, SMOOTH, Style.tiny())
	end
	Geo.cylinder(parent, at + Vector3.new(0, h + 0.15, 0), 0.3, dia - 0.3, K.Metal, SMOOTH, Style.tiny())
end

--[[
	Space Station pipe up a wall with a colored pipe ring (pipe-ring-colored):
	a vertical pipe, an orange ring and a top bend stub. 3 parts.
]]
function Buildings.pipe(parent: Instance, wall: CFrame, x: number, y0: number, y1: number)
	local p = (wall * CFrame.new(x, 0, -0.5)).Position
	Geo.cylinder(parent, p + Vector3.new(0, (y0 + y1) / 2, 0), y1 - y0, 0.6, K.MetalEdge, SMOOTH, Style.tiny())
	Geo.cylinder(parent, p + Vector3.new(0, y0 + (y1 - y0) * 0.35, 0), 0.6, 0.85, C.Hazard, SMOOTH, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, y1, -0.3), Vector3.new(0.6, 0.6, 0.8), K.MetalEdge, nil, Style.tiny())
end

--[[
	Hanging cloth banner (concept v2's forge banners): a metal rod, the
	cloth and a gold stripe near the bottom. `wall` = wall frame. 3 parts.
]]
function Buildings.banner(parent: Instance, wall: CFrame, x: number, top: number, w: number, h: number, color: Color3)
	Style.block(parent, wall * CFrame.new(x, top, -0.35), Vector3.new(w + 0.6, 0.3, 0.3), K.Metal, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, top - h / 2, -0.3), Vector3.new(w, h, 0.15), color, nil, Style.tiny())
	Style.block(parent, wall * CFrame.new(x, top - h + 0.7, -0.4), Vector3.new(w, 0.35, 0.1), C.Gold, nil, Style.tiny())
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

-- Wooden bench (seat on two legs). 3 parts.
function Buildings.bench(parent: Instance, at: CFrame)
	Style.block(parent, at * CFrame.new(0, 0.95, 0), Vector3.new(3, 0.3, 1), C.Wood, nil, Style.decor())
	for _, sx in { -1, 1 } do
		Style.block(parent, at * CFrame.new(sx * 1.2, 0.4, 0), Vector3.new(0.3, 0.8, 0.9), C.WoodDark, nil, Style.tiny())
	end
end

---------------------------------------------------------------- signs

-- A cut gem (crown bar over a diamond). 2 parts.
local function gemIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	glow(parent, cf * CFrame.new(0, s * 0.22, 0), Vector3.new(s * 0.62, s * 0.16, 0.3), color)
	glow(parent, cf * CFrame.new(0, -s * 0.08, 0) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(s * 0.42, s * 0.42, 0.3), color)
end

-- A mug with foam and a handle (the inn). 3 parts.
local function mugIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	glow(parent, cf * CFrame.new(s * 0.06, -s * 0.06, 0), Vector3.new(s * 0.42, s * 0.5, 0.3), color)
	Style.block(parent, cf * CFrame.new(s * 0.06, s * 0.24, 0), Vector3.new(s * 0.5, s * 0.14, 0.3), C.AwningWhite, nil, Style.tiny())
	-- the handle on the viewer's right (a frame's local -X)
	glow(parent, cf * CFrame.new(-s * 0.24, -s * 0.06, 0), Vector3.new(s * 0.14, s * 0.3, 0.3), color)
end

--[[
	Concept v2 neon sign: a dark navy text board with white letters, an
	icon board on the viewer's left with a glowing icon, a thin blue neon
	frame around both (standing in front of the boards, no shared faces)
	and a dark metal backing plate. `at` = the center of the whole sign
	(text + icon), front = LookVector. icon: a Style.icon kind, or "Gem",
	"Mug". ~12 parts. Returns the text board (named TownSign).
]]
function Buildings.sign(parent: Instance, at: CFrame, text: string, textW: number, h: number, icon: string?, iconColor: Color3?): Part
	local iconW = if icon then h else 0
	local total = textW + iconW
	local depth = 0.5
	-- seen from the front the frame's local +X is the viewer's left: the icon goes at +X
	local textAt = at * CFrame.new(-iconW / 2, 0, 0)
	local board = Style.sign(parent, textAt, text, textW, h, {
		Kind = "Glow",
		Depth = depth,
		Frame = false,
		BoardColor = K.SignBoard,
		TextColor = K.SignText,
	})
	board.Name = "TownSign"
	board.CanCollide = false
	-- backing plate
	Style.block(parent, at * CFrame.new(0, 0, depth / 2 + 0.2), Vector3.new(total + 0.6, h + 0.6, 0.4), K.Metal, nil, Style.tiny())
	-- neon frame, in front of the boards and straddling their edges
	local t = 0.16
	local z = -depth / 2 - 0.1
	local frame = K.SignNeon
	glow(parent, at * CFrame.new(0, h / 2, z), Vector3.new(total + t, t, 0.2), frame)
	glow(parent, at * CFrame.new(0, -h / 2, z), Vector3.new(total + t, t, 0.2), frame)
	glow(parent, at * CFrame.new(-total / 2, 0, z), Vector3.new(t, h - t, 0.2), frame)
	glow(parent, at * CFrame.new(total / 2, 0, z), Vector3.new(t, h - t, 0.2), frame)
	if icon then
		local iconAt = at * CFrame.new(total / 2 - iconW / 2, 0, 0)
		Style.block(parent, iconAt, Vector3.new(iconW - 0.02, h - 0.02, depth), K.SignBoard, nil, Style.tiny())
		glow(parent, at * CFrame.new(total / 2 - iconW, 0, z), Vector3.new(t, h - t, 0.2), frame)
		local front = iconAt * CFrame.new(0, 0, -depth / 2 - 0.15)
		local color = iconColor or K.SignNeon
		local s = h * 0.8
		if icon == "Gem" then
			gemIcon(parent, front, s, color)
		elseif icon == "Mug" then
			mugIcon(parent, front, s, color)
		else
			Style.icon(parent, front, icon, s, color, NEON)
		end
	end
	return board
end

--[[
	The sign standing on a roof on two metal legs (`at` = bottom center of
	the sign on the roof, front = LookVector). ~14 parts.
]]
function Buildings.roofSign(parent: Instance, at: CFrame, text: string, textW: number, h: number, icon: string?, iconColor: Color3?): Part
	local total = textW + (if icon then h else 0)
	for _, sx in { -1, 1 } do
		Style.block(parent, at * CFrame.new(sx * total * 0.3, 0.55, 0.45), Vector3.new(0.35, 1.1, 0.35), K.Metal, nil, Style.tiny())
	end
	return Buildings.sign(parent, at * CFrame.new(0, 1.1 + h / 2 + 0.45, 0), text, textW, h, icon, iconColor)
end

-- The sign flat on a wall (`wall` frame, center x/y of the whole sign, `out` = board center off the wall). ~12 parts.
function Buildings.wallSign(
	parent: Instance,
	wall: CFrame,
	x: number,
	y: number,
	text: string,
	textW: number,
	h: number,
	icon: string?,
	iconColor: Color3?,
	out: number?
): Part
	return Buildings.sign(parent, wall * CFrame.new(x, y, -(out or 0.7)), text, textW, h, icon, iconColor)
end

return Buildings
