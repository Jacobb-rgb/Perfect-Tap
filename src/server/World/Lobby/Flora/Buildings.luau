--[[
	Flora town buildings kit: the shapes of Kenney's City Kit (commercial)
	and Space Station Kit rebuilt from Roblox parts (never meshes), in the
	lobby palette.

	  City Kit       chunky 2-3 storey blocks (height ~1.4x the width),
	                 light storey bands and parapets, framed windows with a
	                 light frame, a mullion bar and a sill, setback upper
	                 boxes (building-d), long low blocks (building-k),
	                 rooftop boxes, domes, water tanks and parasols,
	                 awning-wide bars and overhang-wide trays
	  Space Station  corner frames, round corner pillars with an orange
	                 band (wall-corner-round-banner), the orange wall-banner
	                 band at the first floor line, display-wall screens,
	                 table-display-planet, balcony-rail, container-tall,
	                 pipe rings, dish antennas
	  concept v2     mid steel-grey blocks with lighter bevels, thick blue
	                 neon contours (corners, parapet edge, storey lines and
	                 a frame around every shopfront), big dark navy signs
	                 with light text and an icon, orange accents
	                 (docs/art/lobby_concept_v2.webp)
	  concept v1     warm cobble ground floors with lighter stone courses
	                 and quoins, jettied plaster upper floors with dark
	                 half-timbering, window boxes, caged lanterns, red,
	                 terracotta or slate roofs with a red ridge

	A building body is a box on the ground: `Body = { cf, w, d }` with cf at
	the bottom center, LookVector = the front, w along local X, d along
	local Z. Glow is Neon (no lights). Same-facing faces of different
	colours never share a plane (no z-fighting): every pair is offset by
	at least 0.03 studs (tests/LobbyFlora.spec.luau checks it). Pure
	builders (Instance creation only), deterministic from the rng.
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

-- Local colors (concept v2 steel and signs, concept v1 stone; everything else is Style.C).
Buildings.Colors = {
	Metal = rgb(34, 37, 50), -- thin dark trims only (door leaves, sign backs, caps)
	Frame = rgb(84, 90, 118), -- corner frames and plinths: mid steel, grey even in the shade
	MetalEdge = rgb(112, 120, 148), -- masts, rails, pipe rings
	Panel = rgb(140, 148, 176), -- tech upper walls (concept v2 steel grey; the hero sees them in the shade)
	PanelDark = rgb(108, 114, 144), -- tech ground floors
	PanelLight = rgb(184, 192, 218), -- bevels: parapets, storey bands, window frames, sills
	Plaster = rgb(228, 206, 168), -- cozy upper floors
	PlasterWarm = rgb(236, 190, 140),
	StoneWarm = rgb(150, 142, 132), -- cozy ground floors (warm cobble, concept v1)
	StoneCourse = rgb(180, 170, 154), -- lighter stone courses and quoins
	StonePlinth = rgb(112, 104, 98),
	Slate = rgb(104, 108, 128), -- slate roofs (a neutral grey: blue slate reads black-navy in the shade)
	SlateDark = rgb(78, 82, 100),
	SlateLight = rgb(134, 138, 156),
	Terracotta = rgb(204, 104, 66),
	Shingle = rgb(150, 92, 64), -- warm brown wooden shingles (concept v1)
	ShingleDark = rgb(124, 74, 52),
	Deck = rgb(84, 90, 112), -- flat roof decks
	Glass = rgb(64, 124, 196), -- display glass (SmoothPlastic: no bloom)
	Window = rgb(236, 138, 52), -- warm lit window panes (Neon, deep amber: no white bloom)
	WindowDark = rgb(70, 95, 140), -- unlit glass (reads as glass, not as a hole)
	Glare = rgb(160, 192, 232), -- the glare strip on unlit glass
	EdgeNeon = rgb(48, 150, 255), -- concept v2 contours (deeper than GlowEdge: no white bloom)
	SignNeon = rgb(40, 128, 240), -- sign frames
	Amber = rgb(255, 150, 40), -- sign icons
	LampAmber = rgb(255, 165, 70), -- lantern cubes (deep amber, small: no white blob)
	DoorLeaf = rgb(44, 48, 66),
	SignBoard = rgb(16, 24, 56), -- dark navy sign boards
	SignText = rgb(214, 228, 255), -- light blue-white letters (pure white blooms in the sun)
}
local K = Buildings.Colors

export type Body = { cf: CFrame, w: number, d: number }

-- Storey heights: ground floor and upper floors.
Buildings.Ground = 7
Buildings.Upper = 5

-- Neon contour thickness (concept v2: thick enough to read from the hero camera).
Buildings.Contour = 0.4

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

-- A plain block without collision or shadow (trims, frames).
local function trim(parent: Instance, cf: CFrame, size: Vector3, color: Color3): Part
	return Style.block(parent, cf, size, color, nil, Style.tiny())
end
Buildings.trim = trim

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

local function has(list: { string }?, item: string): boolean
	return list ~= nil and table.find(list, item) ~= nil
end

---------------------------------------------------------------- windows and doors

--[[
	A window pane: lit (warm Neon, named WindowGlow) or unlit glass (light
	blue SmoothPlastic with a thin glare strip, named Window). 1-2 parts.
]]
local function pane(parent: Instance, cf: CFrame, size: Vector3, dark: boolean?, color: Color3?): Part
	if not dark then
		local p = glow(parent, cf, size, color or K.Window)
		p.Name = "WindowGlow"
		return p
	end
	local p = trim(parent, cf, size, K.WindowDark)
	p.Name = "Window"
	trim(parent, cf * CFrame.new(-size.X * 0.25, size.Y * 0.08, -size.Z / 2 - 0.035), Vector3.new(0.16, size.Y * 0.62, 0.03), K.Glare)
	return p
end

export type WindowOpts = {
	Frame: Color3?, -- the light frame plate (default PanelLight; C.Hazard = Space Station banner window)
	Dark: number?, -- index of the one unlit pane (default: all lit)
	Mullion: boolean?, -- the transom bar across the panes (default true)
	Sill: boolean?, -- default true
	Color: Color3?, -- pane glow color
	X: number?, -- row center along the wall
}

--[[
	A row of City Kit windows: one light frame plate, `count` panes in
	front of it (the plate between them reads as the mullions), a light
	transom bar across the panes (the cross mullion, the panes sit 0.06
	behind it) and a sill. `span` = plate width, `y` = pane center. count + 3
	parts.
]]
function Buildings.windowRow(
	parent: Instance,
	wall: CFrame,
	y: number,
	count: number,
	span: number,
	paneH: number,
	o: WindowOpts?
): { Part }
	local opts: WindowOpts = o or {}
	local cx = opts.X or 0
	local gap = 0.55
	local paneW = (span - gap * (count + 1)) / count
	local frame = opts.Frame or K.PanelLight
	local parts = {}
	table.insert(parts, trim(parent, wall * CFrame.new(cx, y, -0.15), Vector3.new(span, paneH + gap * 2, 0.3), frame))
	for i = 1, count do
		local px = cx - span / 2 + gap + paneW / 2 + (i - 1) * (paneW + gap)
		table.insert(parts, pane(parent, wall * CFrame.new(px, y, -0.33), Vector3.new(paneW, paneH, 0.1), opts.Dark == i, opts.Color))
	end
	if opts.Mullion ~= false then
		table.insert(parts, trim(parent, wall * CFrame.new(cx, y + paneH * 0.18, -0.44), Vector3.new(span - 0.4, 0.14, 0.12), frame))
	end
	if opts.Sill ~= false then
		local bottom = y - paneH / 2 - gap
		table.insert(parts, trim(parent, wall * CFrame.new(cx, bottom + 0.05, -0.28), Vector3.new(span + 0.4, 0.22, 0.52), K.PanelLight))
	end
	return parts
end

--[[
	One framed window (City Kit: a light frame, a pane lit or unlit, a sill,
	a transom bar on tall windows). Pass C.Hazard as the frame for a Space
	Station banner window or C.WoodDark on the cozy houses. 3-4 parts.
]]
function Buildings.window(parent: Instance, wall: CFrame, x: number, y: number, w: number, h: number, o: WindowOpts?): Part
	local opts: WindowOpts = o or {}
	local frame = opts.Frame or K.PanelLight
	trim(parent, wall * CFrame.new(x, y, -0.15), Vector3.new(w + 0.8, h + 0.8, 0.3), frame)
	local p = pane(parent, wall * CFrame.new(x, y, -0.33), Vector3.new(w, h, 0.1), opts.Dark == 1, opts.Color)
	if opts.Mullion ~= false and h >= 1.6 then
		trim(parent, wall * CFrame.new(x, y + h * 0.18, -0.44), Vector3.new(w + 0.2, 0.14, 0.12), frame)
	end
	if opts.Sill ~= false then
		trim(
			parent,
			wall * CFrame.new(x, y - h / 2 - 0.35, -0.28),
			Vector3.new(w + 1.1, 0.22, 0.52),
			if frame == C.WoodDark then C.Wood else K.PanelLight
		)
	end
	return p
end

export type ShopOpts = {
	Door: boolean?, -- default true
	DoorW: number?,
	DoorSide: number?, -- +1: the door at the wall's local +X end (viewer's left), -1 the other end
	Glass: boolean?, -- the display glass (default true)
	Goods: { Color3 }?, -- the two goods on the display sill
	Neon: Color3?, -- the neon frame (default EdgeNeon)
	Frame: Color3?, -- the dark frame plate (default Frame)
	Bay: boolean?, -- a loading bay: the door fills the front, slats instead of a leaf
}

--[[
	Ground-floor shopfront (Space Station wall-door-wide + display wall,
	concept v2): a steel frame plate, a dark door leaf with an amber
	transom, SmoothPlastic display glass on a light sill with two goods,
	and a thick neon frame around the whole front (two jambs and a head,
	like the SHOP stall). `x` = center along the wall, `w` = width (the
	neon frame adds 0.4 each side). Returns the sill frame (goods sit on
	it at y 1.5). 6-11 parts.
]]
function Buildings.shopfront(parent: Instance, wall: CFrame, x: number, w: number, o: ShopOpts?): CFrame
	local opts: ShopOpts = o or {}
	local h = 4.6
	local y0 = 0.6
	trim(parent, wall * CFrame.new(x, y0 + h / 2, -0.15), Vector3.new(w, h, 0.3), opts.Frame or K.Frame)
	local side = opts.DoorSide or 1
	local doorW = if opts.Door == false then 0 else (opts.DoorW or 2)
	local doorX = x + side * (w / 2 - doorW / 2 - 0.45)
	if opts.Bay then
		doorW = w - 1.2
		doorX = x
		trim(parent, wall * CFrame.new(x, y0 + 1.95, -0.36), Vector3.new(doorW, 3.9, 0.12), C.HazardDark)
		for i = 1, 3 do
			trim(parent, wall * CFrame.new(x, y0 + i * 1.0, -0.45), Vector3.new(doorW - 0.2, 0.14, 0.06), K.MetalEdge)
		end
		local t = glow(parent, wall * CFrame.new(x, y0 + 4.2, -0.34), Vector3.new(doorW - 0.6, 0.3, 0.08), K.LampAmber)
		t.Name = "DoorGlow"
	elseif doorW > 0 then
		trim(parent, wall * CFrame.new(doorX, y0 + 1.9, -0.36), Vector3.new(doorW, 3.8, 0.12), K.DoorLeaf)
		local t = glow(parent, wall * CFrame.new(doorX, y0 + 4.15, -0.34), Vector3.new(doorW - 0.3, 0.35, 0.08), K.LampAmber)
		t.Name = "DoorGlow"
	end
	local glassW = w - (if doorW > 0 then doorW + 1.35 else 0.9)
	local glassX = if doorW > 0 then x - side * (doorW + 0.45) / 2 else x
	local sill = wall * CFrame.new(glassX, 1.35, -0.5)
	if opts.Glass ~= false and not opts.Bay and glassW > 0.8 then
		trim(parent, wall * CFrame.new(glassX, 2.9, -0.36), Vector3.new(glassW, 2.8, 0.12), K.Glass)
		trim(parent, sill, Vector3.new(glassW + 0.3, 0.3, 0.7), K.PanelLight)
		local goods = opts.Goods
		if goods and glassW >= 2.2 then
			for i, color in goods do
				local gx = (if i == 1 then -1 else 1) * glassW * 0.24
				local gh = if i == 1 then 0.7 else 0.5
				trim(parent, sill * CFrame.new(gx, 0.15 + gh / 2, -0.13), Vector3.new(if i == 1 then 0.6 else 0.8, gh, 0.4), color)
			end
		end
	end
	-- the neon frame: two jambs and a head around the whole shopfront
	local n = opts.Neon or K.EdgeNeon
	local t = Buildings.Contour
	for _, sx in { -1, 1 } do
		glow(parent, wall * CFrame.new(x + sx * (w / 2 + t / 2), y0 + h / 2, -0.2), Vector3.new(t, h, 0.2), n)
	end
	glow(parent, wall * CFrame.new(x, y0 + h + t / 2, -0.2), Vector3.new(w + 2 * t, t, 0.2), n)
	return sill
end

--[[
	A cozy door (concept v1): a wooden leaf in a dark frame (two jambs and
	a lintel), no glowing transom (the caged lantern beside it is the
	light). 4 parts.
]]
function Buildings.door(parent: Instance, wall: CFrame, x: number, y0: number, w: number, h: number, frame: Color3, leaf: Color3)
	trim(parent, wall * CFrame.new(x, y0 + h / 2, -0.12), Vector3.new(w, h, 0.24), leaf)
	for _, sx in { -1, 1 } do
		trim(parent, wall * CFrame.new(x + sx * (w / 2 + 0.3), y0 + h / 2, -0.2), Vector3.new(0.6, h, 0.4), frame)
	end
	trim(parent, wall * CFrame.new(x, y0 + h + 0.3, -0.21), Vector3.new(w + 1.2, 0.6, 0.42), frame)
end

--[[
	Caged lantern (concept v1, no white blob): a small deep-amber Neon cube
	inside a dark metal cage (cap, base and two crossed bars through the
	cube). `at` = the cube center. 4 parts.
]]
function Buildings.cagedLamp(parent: Instance, at: CFrame, s: number?): Part
	local k = s or 1
	trim(parent, at * CFrame.new(0, 0.36 * k, 0), Vector3.new(0.8 * k, 0.22 * k, 0.8 * k), K.Metal)
	trim(parent, at * CFrame.new(0, -0.34 * k, 0), Vector3.new(0.62 * k, 0.14 * k, 0.62 * k), K.Metal)
	local g = glow(parent, at, Vector3.new(0.42 * k, 0.5 * k, 0.42 * k), K.LampAmber)
	g.Name = "LanternGlow"
	trim(parent, at * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.64 * k, 0.56 * k, 0.07 * k), K.Metal)
	return g
end

-- Hanging lantern by a door: an iron bracket arm and a caged lamp. 5 parts.
function Buildings.hangingLantern(parent: Instance, wall: CFrame, x: number, y: number)
	trim(parent, wall * CFrame.new(x, y, -0.5), Vector3.new(0.22, 0.22, 1), C.Iron)
	Buildings.cagedLamp(parent, wall * CFrame.new(x, y - 0.75, -0.9))
end

-- Window box with flower cubes under a window (concept v1). 3 parts.
function Buildings.windowBox(parent: Instance, wall: CFrame, x: number, y: number, w: number, flower: Color3)
	trim(parent, wall * CFrame.new(x, y, -0.5), Vector3.new(w, 0.5, 0.74), C.Wood)
	trim(parent, wall * CFrame.new(x, y + 0.38, -0.47), Vector3.new(w - 0.3, 0.3, 0.5), C.LeafGreenDark)
	trim(parent, wall * CFrame.new(x, y + 0.62, -0.55), Vector3.new(w - 0.9, 0.4, 0.4), flower)
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
		trim(parent, wall * CFrame.new(x, y0 + h / 2, z), Vector3.new(0.35, h, 0.2), C.WoodDark)
	end
	-- one brace in the first bay
	local bay = width / (posts + 1)
	local len = math.sqrt(bay * bay + h * h)
	local a = math.atan2(h, bay)
	trim(
		parent,
		wall * CFrame.new(-width / 2 + bay / 2, y0 + h / 2, z - 0.02) * CFrame.Angles(0, 0, a),
		Vector3.new(len - 0.3, 0.3, 0.18),
		C.WoodDark
	)
end

---------------------------------------------------------------- shells

export type TechOpts = {
	Floors: number,
	Accent: Color3?, -- the Space Station wall-banner band at the first floor line (default orange)
	Wall: Color3?,
	Ground: Color3?,
	Neon: Color3?, -- contour color (default EdgeNeon)
	NeonFaces: { string }?, -- faces whose corners and storey lines glow (default { "Front" })
	Corners: string?, -- "Square" (default), "Round" (round front pillars with a banner ring), "None"
	Skip: string?, -- "Left" / "Right": no corner frames on that side (a wing joins there)
	Plinth: boolean?, -- default true
}

--[[
	Space Station / City Kit tech block: a steel plinth, a PanelDark ground
	floor, Panel upper floors, the orange wall-banner band at the first floor
	line, light storey bands, steel corner frames (or round front pillars
	with an orange band and a cap ring), and the concept v2 contours: a
	0.4 neon strip on every corner of the NeonFaces and a neon storey line
	under every upper storey band on them. Returns the wall top height.
	10-20 parts.
]]
function Buildings.techShell(parent: Instance, body: Body, o: TechOpts, rng: Rng.Rng): number
	local w, d = body.w, body.d
	local G, U = Buildings.Ground, Buildings.Upper
	local H = Buildings.height(o.Floors)
	local cf = body.cf
	local t = Buildings.Contour
	local faces: { string } = o.NeonFaces or { "Front" }
	local neon = o.Neon or K.EdgeNeon
	if o.Plinth ~= false then
		Style.block(parent, cf * CFrame.new(0, 0.3, 0), Vector3.new(w + 0.9, 0.6, d + 0.9), K.Frame, nil, Style.solid())
	end
	Style.block(
		parent,
		cf * CFrame.new(0, G / 2, 0),
		Vector3.new(w, G, d),
		Style.vary(o.Ground or K.PanelDark, rng, 0.02),
		nil,
		Style.solid()
	)
	if o.Floors > 1 then
		Style.block(
			parent,
			cf * CFrame.new(0, G + (H - G) / 2, 0),
			Vector3.new(w, H - G, d),
			Style.vary(o.Wall or K.Panel, rng, 0.02),
			nil,
			Style.solid()
		)
	end
	-- the Space Station wall-banner band (wraps all four walls under the first storey band)
	Style.block(parent, cf * CFrame.new(0, G - 0.7, 0), Vector3.new(w + 0.24, 1.3, d + 0.24), o.Accent or C.Hazard, nil, Style.decor())
	-- storey bands: light bevels; neon storey lines under the upper ones on the neon faces
	for f = 1, o.Floors - 1 do
		local y = G + (f - 1) * U
		Style.block(parent, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.5, 0.5, d + 0.5), K.PanelLight, nil, Style.ghost())
		if f > 1 then
			for _, side in faces do
				local wall, ww = Buildings.face(body, side)
				glow(parent, wall * CFrame.new(0, y - 0.25 - t / 2 - 0.04, -0.15), Vector3.new(ww - 1.2, t, 0.16), neon)
			end
		end
	end
	local corners = o.Corners or "Square"
	local function lit(sx: number, sz: number): boolean
		local lr = if sx < 0 then "Left" else "Right"
		local fb = if sz < 0 then "Front" else "Back"
		return has(faces, lr) or has(faces, fb)
	end
	for _, sx in { -1, 1 } do
		local skip = (o.Skip == "Left" and sx < 0) or (o.Skip == "Right" and sx > 0)
		for _, sz in { -1, 1 } do
			if not skip then
				local round = corners == "Round" and sz < 0
				if corners ~= "None" and not round then
					-- a square steel frame (0.3 proud of both walls) up into the parapet
					Style.block(
						parent,
						cf * CFrame.new(sx * (w / 2 - 0.1), (H + 0.9) / 2, sz * (d / 2 - 0.1)),
						Vector3.new(0.8, H - 0.3, 0.8),
						K.Frame,
						nil,
						Style.decor()
					)
				elseif round then
					local p = (cf * CFrame.new(sx * w / 2, 0, -d / 2)).Position
					Geo.cylinder(parent, p + Vector3.new(0, (H + 0.9) / 2, 0), H - 0.3, 1.8, K.PanelLight, SMOOTH, Style.decor())
					Geo.cylinder(parent, p + Vector3.new(0, G - 0.7, 0), 1.3, 2.1, o.Accent or C.Hazard, SMOOTH, Style.tiny())
				end
				if lit(sx, sz) then
					-- the contour: a thick neon strip on the outer edge of the corner
					local off = if corners == "Round" and sz < 0 then 0.75 else 0.3
					glow(parent, cf * CFrame.new(sx * (w / 2 + off), (H + 0.6) / 2, sz * (d / 2 + off)), Vector3.new(t, H - 1, t), neon)
				end
			end
		end
	end
	return H
end

--[[
	City Kit setback box (building-d): a smaller block standing on a roof
	deck at `y0` with a steel band at its foot. Returns its top. 2 parts.
]]
function Buildings.setback(parent: Instance, body: Body, y0: number, h: number, wall: Color3?, rng: Rng.Rng): number
	Style.block(
		parent,
		body.cf * CFrame.new(0, y0 + h / 2, 0),
		Vector3.new(body.w, h, body.d),
		Style.vary(wall or K.Panel, rng, 0.02),
		nil,
		Style.decor()
	)
	Style.block(parent, body.cf * CFrame.new(0, y0 + 0.28, 0), Vector3.new(body.w + 0.4, 0.5, body.d + 0.4), K.Frame, nil, Style.ghost())
	return y0 + h
end

export type CozyOpts = {
	Floors: number,
	Stone: Color3?,
	Plaster: Color3?,
	Timber: Color3?,
	Timbering: number?, -- half-timber studs per plaster wall (front, back); 0 = none
}

--[[
	Concept v1 town house: a warm cobble ground floor on a plinth with two
	lighter stone courses and quoins on all four corners, a jettied plaster
	upper part with timber corner posts and beams and dark half-timbering
	on the front and back. Returns the top of the walls. 12-20 parts.
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
		Style.vary(K.StonePlinth, rng, 0.03),
		nil,
		Style.solid()
	)
	Style.block(
		parent,
		cf * CFrame.new(0, G / 2, 0),
		Vector3.new(w, G, d),
		Style.vary(o.Stone or K.StoneWarm, rng, 0.03),
		nil,
		Style.solid()
	)
	-- two lighter stone courses wrapping the ground floor
	for _, y in { 2.4, 4.7 } do
		trim(parent, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.12, 0.38, d + 0.12), K.StoneCourse)
	end
	-- quoins on all four corners, stopping under the jetty band
	local top = G - 0.35
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Style.block(
				parent,
				cf * CFrame.new(sx * w / 2, 0.7 + (top - 0.7) / 2, sz * d / 2),
				Vector3.new(0.9, top - 0.7, 0.9),
				K.StoneCourse,
				nil,
				Style.decor({ CastShadow = false })
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
				trim(parent, cf * CFrame.new(sx * jw / 2, G + (H - G) / 2, sz * jd / 2), Vector3.new(0.6, H - G - 0.1, 0.6), timber)
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
	City Kit flat roof: a light parapet slab with a darker deck inset on top
	and a thick neon line along the parapet's foot on every face in
	`neonFaces`. Returns the deck height. 2-6 parts.
]]
function Buildings.flatRoof(parent: Instance, body: Body, top: number, neonFaces: { string }?, rim: Color3?, neon: Color3?): number
	local cf = body.cf
	local t = Buildings.Contour
	Style.block(
		parent,
		cf * CFrame.new(0, top + 0.45, 0),
		Vector3.new(body.w + 0.8, 0.9, body.d + 0.8),
		rim or K.PanelLight,
		nil,
		Style.decor()
	)
	trim(parent, cf * CFrame.new(0, top + 0.95, 0), Vector3.new(body.w - 0.6, 0.12, body.d - 0.6), K.Deck)
	if neonFaces then
		local wide = Buildings.sub(body, 0, 0, body.w + 0.8, body.d + 0.8)
		for _, side in neonFaces do
			local wall, ww = Buildings.face(wide, side)
			glow(parent, wall * CFrame.new(0, top + t / 2 + 0.04, -0.08), Vector3.new(ww + 0.2, t, 0.16), neon or K.EdgeNeon)
		end
	end
	return top + 1
end

--[[
	Gable roof with gable-end infill, ridge along the body's local X (pass
	a body turned a quarter for a gable-front house). Overhangs: 0.6 at the
	gables, ~0.9 at the eaves. `slate` = the roof colour (slate, red or
	terracotta), `ridge` = the ridge cap (a red one on slate roofs, like
	the v2 forge). 5 parts.
]]
function Buildings.gableRoof(parent: Instance, body: Body, eave: number, h: number, infill: Color3, slate: Color3?, ridge: Color3?)
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
		ridge or C.RoofDark,
		nil,
		Style.tiny({ CastShadow = true })
	)
end

--[[
	Stepped voxel cap: shrinking slabs (lightest on top), like the
	concept's tiled tower caps. Returns the top height. `steps` parts.
]]
function Buildings.steppedRoof(parent: Instance, body: Body, top: number, steps: number, colors: { Color3 }?, h: number?): number
	local shades = colors or { K.SlateDark, K.Slate, K.SlateLight }
	local y = top
	local sh = h or 0.9
	for i = 1, steps do
		local f = 1 - (i - 1) * 0.3
		Style.block(
			parent,
			body.cf * CFrame.new(0, y + sh / 2, 0),
			Vector3.new(body.w * f + 0.8, sh, body.d * f + 0.8),
			shades[math.min(i, #shades)],
			nil,
			if i == 1 then Style.decor() else Style.tiny({ CastShadow = true })
		)
		y += sh
	end
	return y
end

---------------------------------------------------------------- awnings and overhangs

--[[
	City Kit detail-awning-wide: a long coloured canopy bar sloping out from
	the wall with a darker front lip. `y` = the height at the wall. 2 parts.
]]
function Buildings.awningWide(parent: Instance, wall: CFrame, x: number, y: number, w: number, depth: number, color: Color3)
	local a = math.rad(10)
	local slab = wall * CFrame.new(x, y - math.sin(a) * depth / 2, -depth / 2) * CFrame.Angles(-a, 0, 0)
	Style.block(parent, slab, Vector3.new(w, 0.3, depth), color, nil, Style.ghost())
	trim(
		parent,
		wall * CFrame.new(x, y - math.sin(a) * depth - 0.2, -depth + 0.07),
		Vector3.new(w + 0.1, 0.5, 0.2),
		color:Lerp(Color3.new(0, 0, 0), 0.25)
	)
end

--[[
	City Kit detail-overhang-wide over a shop front: a light tray on the
	wall (a slab with a raised front lip) and a neon line along the lip.
	3 parts.
]]
function Buildings.overhang(parent: Instance, wall: CFrame, x: number, y: number, w: number, depth: number, color: Color3, neon: Color3?)
	Style.block(parent, wall * CFrame.new(x, y, -depth / 2), Vector3.new(w, 0.3, depth), color, nil, Style.ghost())
	trim(parent, wall * CFrame.new(x, y + 0.25, -depth + 0.15), Vector3.new(w + 0.1, 0.8, 0.3), color)
	glow(parent, wall * CFrame.new(x, y + 0.1, -depth - 0.06), Vector3.new(w - 0.4, Buildings.Contour, 0.12), neon or K.EdgeNeon)
end

-- Striped awning (concept v1 stalls): `stripes` sloped slabs side by side. stripes parts.
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
	local drop = 1.4
	local angle = math.atan2(drop, depth)
	local len = math.sqrt(depth * depth + drop * drop)
	local sw = w / stripes
	for i = 0, stripes - 1 do
		local cx = x - w / 2 + sw * (i + 0.5)
		local mid = wall * CFrame.new(cx, y - drop / 2, -depth / 2) * CFrame.Angles(-angle, 0, 0)
		Style.block(parent, mid, Vector3.new(sw, 0.3, len), if i % 2 == 0 then a else b, nil, Style.ghost())
	end
end

---------------------------------------------------------------- rooftop and wall details

-- City Kit rooftop box (AC unit) with a fan disc. 2 parts.
function Buildings.vent(parent: Instance, at: CFrame, rng: Rng.Rng)
	local w, d = rng:range(1.6, 2.2), rng:range(1.4, 1.8)
	Style.block(parent, at * CFrame.new(0, 0.6, 0), Vector3.new(w, 1.2, d), K.PanelLight, nil, Style.tiny({ CastShadow = true }))
	Geo.cylinder(parent, (at * CFrame.new(0, 1.25, 0)).Position, 0.12, math.min(w, d) * 0.7, K.Frame, SMOOTH, Style.tiny())
end

-- City Kit rooftop dome (a half-buried ball). 1 part.
function Buildings.dome(parent: Instance, at: CFrame, size: number, color: Color3?)
	Geo.ball(parent, (at * CFrame.new(0, size * 0.1, 0)).Position, size, color or K.PanelLight, SMOOTH, Style.tiny())
end

-- City Kit water tank on a stand (building-l). 4 parts.
function Buildings.waterTank(parent: Instance, at: CFrame, size: number?)
	local s = size or 3
	Style.block(parent, at * CFrame.new(0, 0.6, 0), Vector3.new(s * 0.8, 1.2, s * 0.8), K.Frame, nil, Style.tiny({ CastShadow = true }))
	local p = at.Position
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.45, 0), s * 0.9, s, C.Wood, SMOOTH, Style.tiny({ CastShadow = true }))
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.45, 0), 0.3, s + 0.12, C.Iron, SMOOTH, Style.tiny())
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.95, 0), 0.3, s * 1.1, K.SlateDark, SMOOTH, Style.tiny())
end

--[[
	Space Station dish antenna: a mast, a tilted dish (a thin disc facing
	the frame's front and up) and a glowing beacon tip. 3 parts.
]]
function Buildings.antenna(parent: Instance, at: CFrame, h: number, tip: Color3)
	trim(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(0.3, h, 0.3), K.MetalEdge)
	Geo.make(
		"Part",
		Style.tiny({
			Shape = Enum.PartType.Cylinder,
			CFrame = at * CFrame.new(0, h * 0.62, -0.35) * CFrame.Angles(math.rad(35), 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Size = Vector3.new(0.18, 1.9, 1.9),
			Color = K.PanelLight,
			Material = SMOOTH,
		}),
		parent
	)
	glow(parent, at * CFrame.new(0, h + 0.25, 0), Vector3.new(0.5, 0.5, 0.5), tip)
end

-- Stone chimney with a dark cap. 2 parts.
function Buildings.chimney(parent: Instance, at: CFrame, h: number, rng: Rng.Rng)
	Style.block(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(1.4, h, 1.4), Style.vary(K.StonePlinth, rng, 0.05), nil, Style.decor())
	trim(parent, at * CFrame.new(0, h + 0.2, 0), Vector3.new(1.9, 0.4, 1.9), C.StoneDeep)
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
	Geo.cylinder(parent, at + Vector3.new(0, h + 0.15, 0), 0.3, dia - 0.3, K.Frame, SMOOTH, Style.tiny())
end

--[[
	Space Station pipe up a wall with a colored pipe ring (pipe-ring-colored):
	a vertical pipe, an orange ring and a top bend stub. 3 parts.
]]
function Buildings.pipe(parent: Instance, wall: CFrame, x: number, y0: number, y1: number)
	local p = (wall * CFrame.new(x, 0, -0.5)).Position
	Geo.cylinder(parent, p + Vector3.new(0, (y0 + y1) / 2, 0), y1 - y0, 0.6, K.MetalEdge, SMOOTH, Style.tiny())
	Geo.cylinder(parent, p + Vector3.new(0, y0 + (y1 - y0) * 0.35, 0), 0.6, 0.85, C.Hazard, SMOOTH, Style.tiny())
	trim(parent, wall * CFrame.new(x, y1, -0.3), Vector3.new(0.6, 0.6, 0.8), K.MetalEdge)
end

--[[
	Space Station display-wall-wide beside a door: a steel frame and a
	glowing orange screen (`wall` frame, x, y = screen center). 2 parts.
]]
function Buildings.displayWall(parent: Instance, wall: CFrame, x: number, y: number, w: number?, h: number?)
	local sw, sh = w or 1.6, h or 1.1
	trim(parent, wall * CFrame.new(x, y, -0.2), Vector3.new(sw + 0.5, sh + 0.5, 0.4), K.Frame)
	local s = glow(parent, wall * CFrame.new(x, y, -0.43), Vector3.new(sw, sh, 0.08), C.Hazard)
	s.Name = "Screen"
end

--[[
	Space Station table-display-planet on a sill or deck (`at` = the foot):
	a light base, a glowing planet and a tilted ring. 3 parts.
]]
function Buildings.planetTable(parent: Instance, at: CFrame, s: number?)
	local k = s or 1
	trim(parent, at * CFrame.new(0, 0.18 * k, 0), Vector3.new(0.9 * k, 0.36 * k, 0.7 * k), K.PanelLight)
	local planet = at * CFrame.new(0, 0.36 * k + 0.32 * k, 0)
	Geo.ball(parent, planet.Position, 0.56 * k, C.CrystalBlue, NEON, Style.tiny())
	Geo.make(
		"Part",
		Style.tiny({
			Shape = Enum.PartType.Cylinder,
			CFrame = planet * CFrame.Angles(0, 0, math.pi / 2 + 0.35),
			Size = Vector3.new(0.06, 1.0 * k, 1.0 * k),
			Color = C.Gold,
			Material = SMOOTH,
		}),
		parent
	)
end

--[[
	Space Station balcony-rail along a deck edge: an orange plate and a
	light rounded-looking top rail (`at` = the deck point under the rail
	middle, LookVector = outward). 2 parts.
]]
function Buildings.balconyRail(parent: Instance, at: CFrame, w: number)
	trim(parent, at * CFrame.new(0, 0.45, 0), Vector3.new(w, 0.5, 0.3), C.Hazard)
	trim(parent, at * CFrame.new(0, 0.88, 0.03), Vector3.new(w + 0.1, 0.36, 0.42), K.PanelLight)
end

--[[
	Hanging cloth banner (concept v2's forge banners): a metal rod, the
	cloth and a gold stripe near the bottom. `wall` = wall frame. 3 parts.
]]
function Buildings.banner(parent: Instance, wall: CFrame, x: number, top: number, w: number, h: number, color: Color3)
	trim(parent, wall * CFrame.new(x, top, -0.35), Vector3.new(w + 0.6, 0.3, 0.3), K.Metal)
	trim(parent, wall * CFrame.new(x, top - h / 2, -0.3), Vector3.new(w, h, 0.15), color)
	trim(parent, wall * CFrame.new(x, top - h + 0.7, -0.42), Vector3.new(w, 0.35, 0.1), C.Gold)
end

-- City Kit parasol: a foot, a pole and a two-slab canopy. 4 parts.
function Buildings.parasol(parent: Instance, at: CFrame, color: Color3)
	trim(parent, at * CFrame.new(0, 0.1, 0), Vector3.new(1.4, 0.2, 1.4), K.PanelLight)
	trim(parent, at * CFrame.new(0, 1.4, 0), Vector3.new(0.25, 2.6, 0.25), K.Metal)
	Style.block(parent, at * CFrame.new(0, 2.8, 0), Vector3.new(3.2, 0.4, 3.2), color, nil, Style.tiny({ CastShadow = true }))
	trim(parent, at * CFrame.new(0, 3.05, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(2.2, 0.35, 2.2), color)
end

-- Wooden bench (seat on two legs). 3 parts.
function Buildings.bench(parent: Instance, at: CFrame)
	Style.block(parent, at * CFrame.new(0, 0.95, 0), Vector3.new(3, 0.3, 1), C.Wood, nil, Style.decor())
	for _, sx in { -1, 1 } do
		trim(parent, at * CFrame.new(sx * 1.2, 0.4, 0), Vector3.new(0.3, 0.8, 0.9), C.WoodDark)
	end
end

-- A crate on the ground (`at` = ground point in the frame). 3 parts.
function Buildings.crate(parent: Instance, at: CFrame, s: number, rng: Rng.Rng)
	local cf = at * CFrame.Angles(0, rng:range(-0.2, 0.2), 0)
	local props = if s < 1.2 then Style.tiny() else Style.decor()
	Style.block(parent, cf * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), Style.vary(C.WoodLight, rng, 0.05), nil, props)
	trim(parent, cf * CFrame.new(0, s / 2, 0), Vector3.new(s + 0.1, s * 0.2, s + 0.1), C.WoodDark)
	trim(parent, cf * CFrame.new(0, s / 2, 0), Vector3.new(s * 0.2, s + 0.1, s + 0.1), C.WoodDark)
end

-- A wooden barrel with two iron hoops (`at` = ground center). 3 parts.
function Buildings.barrel(parent: Instance, at: Vector3, rng: Rng.Rng, h: number?)
	local bh = h or 2
	Geo.cylinder(parent, at + Vector3.new(0, bh / 2, 0), bh, 1.5, Style.vary(C.Wood, rng, 0.05), SMOOTH, Style.decor())
	for _, f in { 0.22, 0.78 } do
		Geo.cylinder(parent, at + Vector3.new(0, bh * f, 0), 0.2, 1.6, C.Iron, SMOOTH, Style.tiny())
	end
end

--[[
	A small ore cart on the lane (`at` = ground center, LookVector = along
	the cart): a tub with a copper band, an ore load and two axles. 5 parts.
]]
function Buildings.cart(parent: Instance, at: CFrame, load: Color3)
	Style.block(parent, at * CFrame.new(0, 1.25, 0), Vector3.new(2.2, 1.2, 3), C.Iron, nil, Style.decor())
	trim(parent, at * CFrame.new(0, 1.55, 0), Vector3.new(2.36, 0.3, 3.16), C.Copper)
	trim(parent, at * CFrame.new(0, 1.95, 0), Vector3.new(1.7, 0.4, 2.4), load)
	for _, z in { -0.9, 0.9 } do
		Geo.make(
			"Part",
			Style.tiny({
				Shape = Enum.PartType.Cylinder,
				CFrame = at * CFrame.new(0, 0.45, z),
				Size = Vector3.new(2.5, 0.9, 0.9),
				Color = K.Metal,
				Material = SMOOTH,
			}),
			parent
		)
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
	trim(parent, cf * CFrame.new(s * 0.06, s * 0.24, -0.05), Vector3.new(s * 0.5, s * 0.14, 0.36), C.AwningWhite)
	-- the handle on the viewer's right (a frame's local -X)
	glow(parent, cf * CFrame.new(-s * 0.24, -s * 0.06, 0), Vector3.new(s * 0.14, s * 0.3, 0.3), color)
end

-- A lab flask (round body, neck, a glowing liquid line). 3 parts.
local function flaskIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	glow(parent, cf * CFrame.new(0, -s * 0.16, 0) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(s * 0.42, s * 0.42, 0.3), color)
	glow(parent, cf * CFrame.new(0, s * 0.22, 0), Vector3.new(s * 0.16, s * 0.36, 0.3), color)
	trim(parent, cf * CFrame.new(0, s * 0.42, -0.05), Vector3.new(s * 0.3, s * 0.1, 0.36), C.AwningWhite)
end

-- The neon frame of a sign board, in front of the board (`z`) and straddling its edges. 4 parts.
local function signFrame(parent: Instance, at: CFrame, total: number, h: number, z: number, t: number, depth: number, color: Color3)
	glow(parent, at * CFrame.new(0, h / 2, z), Vector3.new(total + t, t, depth), color)
	glow(parent, at * CFrame.new(0, -h / 2, z), Vector3.new(total + t, t, depth), color)
	glow(parent, at * CFrame.new(-total / 2, 0, z), Vector3.new(t, h - t, depth), color)
	glow(parent, at * CFrame.new(total / 2, 0, z), Vector3.new(t, h - t, depth), color)
end

--[[
	Concept v2 neon sign: a dark navy text board with light letters, an
	icon board on the viewer's left with a glowing icon, a neon frame
	around both (standing in front of the boards, no shared faces) and a
	dark metal backing plate. `at` = the center of the whole sign
	(text + icon), front = LookVector. icon: a Style.icon kind, or "Gem",
	"Mug", "Flask". ~12 parts. Returns the text board (named TownSign).
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
	trim(parent, at * CFrame.new(0, 0, depth / 2 + 0.2), Vector3.new(total + 0.6, h + 0.6, 0.4), K.Metal)
	local t = math.clamp(h * 0.09, 0.18, 0.3)
	local z = -depth / 2 - 0.1
	signFrame(parent, at, total, h, z, t, 0.2, K.SignNeon)
	if icon then
		local iconAt = at * CFrame.new(total / 2 - iconW / 2, 0, 0)
		trim(parent, iconAt, Vector3.new(iconW - 0.02, h - 0.02, depth), K.SignBoard)
		glow(parent, at * CFrame.new(total / 2 - iconW, 0, z), Vector3.new(t, h - t, 0.2), K.SignNeon)
		local front = iconAt * CFrame.new(0, 0, -depth / 2 - 0.15)
		local color = iconColor or K.SignNeon
		local s = h * 0.8
		if icon == "Gem" then
			gemIcon(parent, front, s, color)
		elseif icon == "Mug" then
			mugIcon(parent, front, s, color)
		elseif icon == "Flask" then
			flaskIcon(parent, front, s, color)
		else
			Style.icon(parent, front, icon, s, color, NEON)
		end
	end
	return board
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

--[[
	Rooftop blade sign: a double-sided neon board standing on a roof deck
	on two steel legs, turned perpendicular to the facade so the street,
	the plaza and the hero camera all read it (`at` = bottom center on the
	deck, LookVector = the front face; `legs` = false stands it directly on
	a balcony slab). The neon frame is deeper than the board, so it frames
	both faces. 5-7 parts. Returns the board (BladeSign).
]]
function Buildings.bladeSign(parent: Instance, at: CFrame, text: string, w: number, h: number, legs: boolean?): Part
	local foot = 0
	if legs ~= false then
		foot = 1.1
		for _, sx in { -1, 1 } do
			trim(parent, at * CFrame.new(sx * w * 0.3, 0.55, 0), Vector3.new(0.35, 1.1, 0.35), K.Frame)
		end
	end
	local center = at * CFrame.new(0, foot + h / 2, 0)
	local board = Style.sign(parent, center, text, w, h, {
		Kind = "Glow",
		Depth = 0.4,
		Frame = false,
		DoubleSided = true,
		BoardColor = K.SignBoard,
		TextColor = K.SignText,
	})
	board.Name = "BladeSign"
	board.CanCollide = false
	signFrame(parent, center, w, h, 0, math.clamp(h * 0.1, 0.2, 0.3), 0.62, K.SignNeon)
	return board
end

return Buildings
