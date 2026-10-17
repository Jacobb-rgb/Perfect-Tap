--[[
	Flora town buildings kit: the shapes of Kenney's City Kit (commercial)
	and Space Station Kit rebuilt from Roblox parts (never meshes), in the
	lobby palette.

	  City Kit       chunky 2-3 storey blocks, storey bands and cornices,
	                 framed windows with a mullion bar and a sill, setback
	                 upper boxes (building-d), long blocks (building-k),
	                 rooftop boxes, domes, water tanks, parasols with a
	                 street table, awning-wide bars and overhang-wide trays
	  Space Station  round corner pillars with an orange band
	                 (wall-corner-round-banner), the orange wall-banner band
	                 at the first floor line, display-wall screens,
	                 table-display-planet, balcony-rail, container-tall,
	                 dish antennas
	  concept v2     TWO-TONE tech blocks: a dark gunmetal frame (corner
	                 pillars, plinth, storey bands and a cornice with a
	                 lighter bevel cap, all standing ~1 stud out of the
	                 wall) around light steel panels, blue neon along the
	                 frame's outer edges and under the cornice and the
	                 storey bands, lit display cases (recessed glass, a
	                 glare strip, a neon shelf light, goods on stands), big
	                 dark navy signs with light letters and an icon
	                 (docs/art/lobby_concept_v2.webp)
	  concept v1     warm cobble ground floors with chunky staggered stone
	                 blocks and big quoins, jettied plaster upper floors
	                 with dark half-timbering, window boxes, caged
	                 lanterns, red, shingle, terracotta or slate roofs

	Scale: the ground storey is 9 studs and every street door at least
	6 x 3 (an R15 avatar is ~5.2 tall), upper storeys 5.

	A building body is a box on the ground: `Body = { cf, w, d }` with cf at
	the bottom center, LookVector = the front, w along local X, d along
	local Z (the WALL box; tech frames stand `Out` studs beyond it). Glow is
	Neon (no lights). Same-facing faces of different colours never share a
	plane (no z-fighting): every pair is offset by at least 0.03 studs
	(tests/LobbyFlora.spec.luau checks it). Pure builders (Instance
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

-- Local colors (concept v2 steel and signs, concept v1 stone; everything else is Style.C).
Buildings.Colors = {
	Metal = rgb(34, 37, 50), -- thin dark trims (sign backs, cages)
	Gun = rgb(44, 48, 64), -- concept v2 gunmetal frame: pillars, plinths, storey bands, cornices
	GunCap = rgb(178, 186, 210), -- the lighter bevel cap on a cornice
	Frame = rgb(84, 90, 118), -- mid steel (legs, masts)
	MetalEdge = rgb(112, 120, 148), -- rails, rings
	Panel = rgb(198, 204, 222), -- light steel panels between the dark frames (light enough to read light in the shade)
	PanelDark = rgb(172, 178, 200), -- ground floor panels and shopfront walls
	PanelLight = rgb(226, 230, 242), -- window frames, sills, light trims
	Plaster = rgb(228, 206, 168), -- cozy upper floors
	PlasterWarm = rgb(236, 190, 140),
	StoneWarm = rgb(150, 142, 132), -- cozy ground floors (warm cobble, concept v1)
	StoneCourse = rgb(184, 174, 158), -- lighter stone blocks and quoins
	StonePlinth = rgb(112, 104, 98),
	StoneCap = rgb(84, 78, 76), -- chimney caps
	Slate = rgb(104, 108, 128), -- slate roofs (a neutral grey: blue slate reads black-navy in the shade)
	SlateDark = rgb(78, 82, 100),
	SlateLight = rgb(134, 138, 156),
	Terracotta = rgb(204, 104, 66),
	Shingle = rgb(150, 92, 64), -- warm brown wooden shingles (concept v1)
	Deck = rgb(70, 76, 96), -- flat roof decks
	Glass = rgb(58, 112, 186), -- display glass (SmoothPlastic: no bloom)
	-- (lobby fix round 3: a deep amber, the panes no longer blow out to white-yellow)
	Window = rgb(255, 130, 40), -- warm lit window panes
	WindowDark = rgb(70, 95, 140), -- unlit glass (reads as glass, not as a hole)
	Glare = rgb(176, 206, 240), -- glare strips on glass
	EdgeNeon = rgb(48, 150, 255), -- concept v2 contours (deeper than GlowEdge: no white bloom)
	SignNeon = rgb(40, 128, 240), -- sign frames
	Amber = rgb(230, 120, 30), -- sign icons (deep amber: the core stays orange, no white blob)
	LampAmber = rgb(255, 150, 62), -- lantern cubes (round 3: the plaza's amber glass tone, no white blob)
	Shelf = rgb(255, 176, 92), -- display shelf lights
	DoorLeaf = rgb(44, 48, 66),
	SignBoard = rgb(16, 24, 56), -- dark navy sign boards
	SignText = rgb(214, 228, 255), -- light blue-white letters (pure white blooms in the sun)
	MugBody = rgb(214, 128, 40), -- the inn mug (SmoothPlastic amber glass)
	Foam = rgb(250, 244, 228),
}
local K = Buildings.Colors

export type Body = { cf: CFrame, w: number, d: number }

-- Storey heights: ground floor and upper floors.
Buildings.Ground = 9
Buildings.Upper = 5

-- How far the gunmetal frame (corner pillars) stands out of a tech wall.
Buildings.Out = 1

-- Neon contour thickness.
Buildings.Contour = 0.34

function Buildings.height(floors: number): number
	return Buildings.Ground + (floors - 1) * Buildings.Upper
end

-- Window center height of floor f (1 = the ground floor).
function Buildings.floorY(f: number): number
	if f <= 1 then
		return 4.6
	end
	return Buildings.Ground + (f - 2) * Buildings.Upper + 2.7
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

-- A body raised to height y (for setbacks and rooftop boxes).
function Buildings.raise(body: Body, y: number): Body
	return { cf = body.cf * CFrame.new(0, y, 0), w = body.w, d = body.d }
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
	Frame: Color3?, -- the frame plate (default PanelLight; C.WoodDark on the cozy houses, C.Hazard = banner window)
	Dark: number?, -- index of the one unlit pane (default: all lit)
	Mullion: boolean?, -- the transom bar across the panes (default true)
	Sill: boolean?, -- default true
	Color: Color3?, -- pane glow color
	X: number?, -- row center along the wall
}

--[[
	A row of City Kit windows: one frame plate, `count` panes in front of it
	(the plate between them reads as the mullions), a transom bar across
	the panes and a light sill. `span` = plate width, `y` = pane center.
	count + 3 parts.
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
	local gap = 0.5
	local paneW = (span - gap * (count + 1)) / count
	local frame = opts.Frame or K.PanelLight
	local parts = {}
	table.insert(parts, trim(parent, wall * CFrame.new(cx, y, -0.15), Vector3.new(span, paneH + gap * 2, 0.3), frame))
	for i = 1, count do
		local px = cx - span / 2 + gap + paneW / 2 + (i - 1) * (paneW + gap)
		table.insert(parts, pane(parent, wall * CFrame.new(px, y, -0.33), Vector3.new(paneW, paneH, 0.1), opts.Dark == i, opts.Color))
	end
	if opts.Mullion ~= false then
		-- (round 3: a dark transom across the panes)
		table.insert(parts, trim(parent, wall * CFrame.new(cx, y + paneH * 0.12, -0.44), Vector3.new(span - 0.4, 0.16, 0.12), C.WoodDark))
	end
	if opts.Sill ~= false then
		local bottom = y - paneH / 2 - gap
		table.insert(
			parts,
			trim(
				parent,
				wall * CFrame.new(cx, bottom + 0.05, -0.28),
				Vector3.new(span + 0.4, 0.22, 0.52),
				if frame == C.WoodDark then C.Wood else K.PanelLight
			)
		)
	end
	return parts
end

-- One framed window (frame plate, pane, a transom bar on tall windows, a sill). 3-4 parts.
function Buildings.window(parent: Instance, wall: CFrame, x: number, y: number, w: number, h: number, o: WindowOpts?): Part
	local opts: WindowOpts = o or {}
	local frame = opts.Frame or K.PanelLight
	trim(parent, wall * CFrame.new(x, y, -0.15), Vector3.new(w + 0.8, h + 0.8, 0.3), frame)
	-- (round 3) a smaller glowing pane behind a dark mullion cross
	local p = pane(parent, wall * CFrame.new(x, y, -0.33), Vector3.new(w * 0.88, h * 0.88, 0.1), opts.Dark == 1, opts.Color)
	if opts.Mullion ~= false and h >= 1.0 then
		trim(parent, wall * CFrame.new(x, y + h * 0.1, -0.44), Vector3.new(w * 0.9, 0.16, 0.12), C.WoodDark)
		trim(parent, wall * CFrame.new(x, y, -0.44), Vector3.new(0.16, h * 0.9, 0.12), C.WoodDark)
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
	DoorW: number?, -- default 3.2 (doors are at least 6 x 3)
	DoorSide: number?, -- +1: the door at the wall's local +X end (viewer's left), -1 the other end
	Glass: boolean?, -- the display case (default true)
	Neon: Color3?, -- the neon frame (default EdgeNeon)
	Frame: Color3?, -- the shopfront wall plate (default PanelLight)
	Bay: boolean?, -- a loading bay: a roll-up door over the whole front
}

export type Shop = { Sill: CFrame, GlassW: number }

--[[
	Ground-floor shopfront (Space Station wall-door-wide + a v2 glass
	display case): a gunmetal frame plate 6.8 tall, a 3.2 x 6 door leaf with
	an amber transom, the display glass set back behind a thick neon frame
	(two jambs and a head) with a diagonal glare strip, a neon shelf light
	and a light sill for the goods (`Buildings.goods`). `x` = center along
	the wall, `w` = width. Returns the sill frame (goods stand on it) and
	the glass width. 7-12 parts.
]]
function Buildings.shopfront(parent: Instance, wall: CFrame, x: number, w: number, o: ShopOpts?): Shop
	local opts: ShopOpts = o or {}
	local h = 6.8
	local y0 = 0.6
	trim(parent, wall * CFrame.new(x, y0 + h / 2, -0.15), Vector3.new(w, h, 0.3), opts.Frame or K.PanelLight)
	local side = opts.DoorSide or 1
	local doorW = if opts.Door == false then 0 else (opts.DoorW or 3.2)
	local doorX = x + side * (w / 2 - doorW / 2 - 0.45)
	if opts.Bay then
		doorW = w - 1.2
		doorX = x
		local bay = trim(parent, wall * CFrame.new(x, y0 + 3, -0.36), Vector3.new(doorW, 6, 0.12), C.HazardDark)
		bay.Name = "Door"
		for i = 1, 4 do
			trim(parent, wall * CFrame.new(x, y0 + i * 1.2, -0.45), Vector3.new(doorW - 0.2, 0.16, 0.06), K.MetalEdge)
		end
		local t = glow(parent, wall * CFrame.new(x, y0 + 6.3, -0.34), Vector3.new(doorW - 0.6, 0.32, 0.08), K.LampAmber)
		t.Name = "DoorGlow"
	elseif doorW > 0 then
		local leaf = trim(parent, wall * CFrame.new(doorX, y0 + 3, -0.36), Vector3.new(doorW, 6, 0.12), K.DoorLeaf)
		leaf.Name = "Door"
		-- a narrow lit pane in the leaf and the amber transom over it
		glow(parent, wall * CFrame.new(doorX, y0 + 4, -0.44), Vector3.new(doorW * 0.36, 2.2, 0.06), K.Window)
		local t = glow(parent, wall * CFrame.new(doorX, y0 + 6.3, -0.34), Vector3.new(doorW - 0.3, 0.32, 0.08), K.LampAmber)
		t.Name = "DoorGlow"
	end
	local glassW = w - (if doorW > 0 then doorW + 1.35 else 0.9)
	local glassX = if doorW > 0 then x - side * (doorW + 0.45) / 2 else x
	local sill = wall * CFrame.new(glassX, 1.8, -0.62)
	if opts.Glass ~= false and not opts.Bay and glassW > 0.8 then
		-- the glass sits behind the neon jambs; goods stand on the sill in front of it
		local g = trim(parent, wall * CFrame.new(glassX, 4.1, -0.34), Vector3.new(glassW, 4.4, 0.1), K.Glass)
		g.Name = "DisplayGlass"
		trim(
			parent,
			wall * CFrame.new(glassX - glassW * 0.18, 4.3, -0.4) * CFrame.Angles(0, 0, -0.5),
			Vector3.new(0.24, math.min(3.6, glassW * 1.2), 0.03),
			K.Glare
		)
		glow(parent, wall * CFrame.new(glassX, 6.05, -0.5), Vector3.new(glassW - 0.3, 0.16, 0.1), K.Shelf)
		trim(parent, wall * CFrame.new(glassX, 1.6, -0.5), Vector3.new(glassW + 0.3, 0.4, 0.9), K.PanelLight)
	end
	-- the neon frame: two jambs and a head around the whole shopfront
	local n = opts.Neon or K.EdgeNeon
	local t = Buildings.Contour
	for _, sx in { -1, 1 } do
		glow(parent, wall * CFrame.new(x + sx * (w / 2 + t / 2), y0 + h / 2, -0.45), Vector3.new(t, h, 0.32), n)
	end
	glow(parent, wall * CFrame.new(x, y0 + h + t / 2, -0.45), Vector3.new(w + 2 * t, t, 0.32), n)
	return { Sill = sill, GlassW = glassW }
end

--[[
	Goods in a display case (`at` = the sill top, LookVector = out):
	"Gem" a pink cut gem on a dark stand, "Flask" a glowing flask, "Pickaxe"
	a pickaxe on a stand, "Ingot" a gold bar, "Planet" a Space Station
	table-display-planet, "Cart" a little ore cart. 1-3 parts.
]]
function Buildings.goods(parent: Instance, at: CFrame, kind: string, color: Color3?)
	if kind == "Gem" then
		trim(parent, at * CFrame.new(0, 0.3, 0), Vector3.new(0.7, 0.6, 0.6), K.Gun)
		glow(parent, at * CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.75, 0.75, 0.4), color or C.CrystalPink)
	elseif kind == "Flask" then
		glow(parent, at * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.8, 0.8, 0.5), color or C.CrystalCyan)
		trim(parent, at * CFrame.new(0, 1.25, 0), Vector3.new(0.3, 0.6, 0.3), K.PanelLight)
	elseif kind == "Pickaxe" then
		local tilt = at * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, 0.35)
		trim(parent, tilt, Vector3.new(0.18, 1.8, 0.18), C.Wood)
		trim(parent, tilt * CFrame.new(0, 0.8, 0), Vector3.new(1.3, 0.26, 0.26), color or C.IronLight)
	elseif kind == "Ingot" then
		trim(parent, at * CFrame.new(0, 0.2, 0), Vector3.new(1.0, 0.4, 0.5), color or C.Gold)
		trim(parent, at * CFrame.new(0.15, 0.55, 0), Vector3.new(0.8, 0.3, 0.45), color or C.Gold)
	elseif kind == "Planet" then
		Buildings.planetTable(parent, at, 1)
	elseif kind == "Cart" then
		trim(parent, at * CFrame.new(0, 0.45, 0), Vector3.new(1.3, 0.6, 0.7), C.Iron)
		trim(parent, at * CFrame.new(0, 0.85, 0), Vector3.new(1.0, 0.3, 0.5), color or C.Copper)
		trim(parent, at * CFrame.new(0, 0.12, 0), Vector3.new(1.0, 0.24, 0.72), K.Metal)
	end
end

--[[
	A cozy door (concept v1): a wooden leaf in a dark frame (two jambs and
	a lintel). Street doors are at least 3 x 6. 4 parts.
]]
function Buildings.door(parent: Instance, wall: CFrame, x: number, y0: number, w: number, h: number, frame: Color3, leaf: Color3)
	local door = trim(parent, wall * CFrame.new(x, y0 + h / 2, -0.12), Vector3.new(w, h, 0.24), leaf)
	door.Name = "Door"
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
	Dark half-timber studs across a plaster wall between y0 and y1:
	`posts` vertical studs spread over the wall, and optionally one
	diagonal brace in bay `brace` (1 = the bay at the wall's local -X end,
	posts + 1 = the +X end). Recipes pick a bay without a window.
	posts (+1) parts.
]]
function Buildings.halfTimber(parent: Instance, wall: CFrame, width: number, y0: number, y1: number, posts: number, brace: number?)
	local z = -0.1
	local h = y1 - y0
	for i = 1, posts do
		local x = -width / 2 + width * i / (posts + 1)
		trim(parent, wall * CFrame.new(x, y0 + h / 2, z), Vector3.new(0.35, h, 0.2), C.WoodDark)
	end
	if brace then
		local bay = width / (posts + 1)
		local len = math.sqrt(bay * bay + h * h)
		local a = math.atan2(h, bay)
		trim(
			parent,
			wall * CFrame.new(-width / 2 + bay * (brace - 0.5), y0 + h / 2, z - 0.02) * CFrame.Angles(0, 0, a),
			Vector3.new(len - 0.3, 0.3, 0.18),
			C.WoodDark
		)
	end
end

---------------------------------------------------------------- shells

export type TechOpts = {
	Floors: number,
	Accent: Color3?, -- the Space Station wall-banner band at the first floor line (default orange)
	Wall: Color3?,
	Ground: Color3?,
	Neon: Color3?, -- contour color (default EdgeNeon)
	NeonFaces: { string }?, -- faces whose frame edges glow (default { "Front" })
	Corners: string?, -- "Square" (default), "Round" (round front pillars with a banner ring)
	Cornice: boolean?, -- the gunmetal cornice with a bevel cap and a deck (default true; false under a gable roof)
	Out: number?, -- how far the pillars stand out of the walls (default Buildings.Out; 0.7-0.8 on narrow sites)
}

--[[
	Concept v2 two-tone tech block (Space Station / City Kit): light steel
	walls (a slightly darker ground storey) framed by dark gunmetal: a
	plinth, four corner pillars standing `Out` (1 stud) out of both walls,
	storey bands Out - 0.2 out, and a cornice Out + 0.2 out with a lighter
	bevel cap (Out + 0.3: the building's outer extent) and a dark deck
	inset. The orange wall-banner band wraps the walls under the
	first storey band. Blue neon runs along the frame: up the outer edge of
	every pillar next to a NeonFace, under the cornice and under the upper
	storey bands on the NeonFaces. Returns the wall top and the roof deck
	height. 14-26 parts.
]]
function Buildings.techShell(parent: Instance, body: Body, o: TechOpts, rng: Rng.Rng): (number, number)
	local w, d = body.w, body.d
	local G, U = Buildings.Ground, Buildings.Upper
	local H = Buildings.height(o.Floors)
	local cf = body.cf
	local t = Buildings.Contour
	local out = o.Out or Buildings.Out
	local P = out + 0.4 -- pillar size: embedded 0.4 in the walls
	local band = out - 0.2
	local faces: { string } = o.NeonFaces or { "Front" }
	local neon = o.Neon or K.EdgeNeon
	Style.block(parent, cf * CFrame.new(0, 0.45, 0), Vector3.new(w + 2 * out + 0.3, 0.9, d + 2 * out + 0.3), K.Gun, nil, Style.solid())
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
	Style.block(parent, cf * CFrame.new(0, G - 0.75, 0), Vector3.new(w + 0.24, 0.8, d + 0.24), o.Accent or C.Hazard, nil, Style.decor())
	-- gunmetal storey bands; neon lines under the upper ones on the neon faces
	for f = 1, o.Floors - 1 do
		local y = G + (f - 1) * U
		Style.block(parent, cf * CFrame.new(0, y, 0), Vector3.new(w + 2 * band, 0.6, d + 2 * band), K.Gun, nil, Style.ghost())
		if f > 1 then
			for _, side in faces do
				local wall, ww = Buildings.face(body, side)
				glow(parent, wall * CFrame.new(0, y - 0.3 - t / 2 - 0.03, -band + 0.05), Vector3.new(ww - 0.9, t, 0.16), neon)
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
		for _, sz in { -1, 1 } do
			local round = corners == "Round" and sz < 0
			local edge = out
			if round then
				-- Space Station wall-corner-round-banner: a gunmetal drum with an orange band
				local p = (cf * CFrame.new(sx * w / 2, 0, -d / 2)).Position
				Geo.cylinder(parent, p + Vector3.new(0, (H + 0.3) / 2, 0), H + 0.3, 2 * out + 0.4, K.Gun, SMOOTH, Style.decor())
				Geo.cylinder(parent, p + Vector3.new(0, G - 0.75, 0), 1.1, 2 * out + 0.7, o.Accent or C.Hazard, SMOOTH, Style.tiny())
				edge = (out + 0.2) * 0.72
			else
				Style.block(
					parent,
					cf * CFrame.new(sx * (w / 2 + out - P / 2), (H + 0.3) / 2, sz * (d / 2 + out - P / 2)),
					Vector3.new(P, H + 0.3, P),
					K.Gun,
					nil,
					Style.decor()
				)
			end
			if lit(sx, sz) then
				-- the contour: a neon strip up the pillar's outer edge, from the plinth to the cornice
				glow(parent, cf * CFrame.new(sx * (w / 2 + edge), (H + 0.9) / 2, sz * (d / 2 + edge)), Vector3.new(t, H - 0.9, t), neon)
			end
		end
	end
	if o.Cornice == false then
		return H, H
	end
	Style.block(parent, cf * CFrame.new(0, H + 0.6, 0), Vector3.new(w + 2 * out + 0.4, 1.2, d + 2 * out + 0.4), K.Gun, nil, Style.decor())
	Style.block(
		parent,
		cf * CFrame.new(0, H + 1.375, 0),
		Vector3.new(w + 2 * out + 0.6, 0.35, d + 2 * out + 0.6),
		K.GunCap,
		nil,
		Style.ghost()
	)
	trim(parent, cf * CFrame.new(0, H + 1.6, 0), Vector3.new(w + 0.2, 0.2, d + 0.2), K.Deck)
	local wide = Buildings.sub(body, 0, 0, w + 2 * out + 0.4, d + 2 * out + 0.4)
	for _, side in faces do
		local wall, ww = Buildings.face(wide, side)
		glow(parent, wall * CFrame.new(0, H + t / 2 + 0.04, -0.045), Vector3.new(ww + 0.1, t, 0.09), neon)
	end
	return H, H + 1.7
end

--[[
	City Kit setback box (building-d) on a roof deck at `y0`, `h` tall, in
	the same two-tone language: light steel walls, two gunmetal front
	pillars, a gunmetal cornice with a bevel cap and a neon line on the
	`neonFaces`. Returns its deck height. 6-8 parts.
]]
function Buildings.setback(parent: Instance, body: Body, y0: number, h: number, rng: Rng.Rng, neonFaces: { string }?): number
	local cf = body.cf * CFrame.new(0, y0, 0)
	local w, d = body.w, body.d
	Style.block(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), Style.vary(K.Panel, rng, 0.02), nil, Style.decor())
	for _, sx in { -1, 1 } do
		Style.block(
			parent,
			cf * CFrame.new(sx * (w / 2 - 0.28), h / 2, -d / 2 + 0.25),
			Vector3.new(1.24, h + 0.6, 1.24),
			K.Gun,
			nil,
			Style.decor()
		)
	end
	Style.block(parent, cf * CFrame.new(0, h + 0.45, 0), Vector3.new(w + 1.4, 0.9, d + 1.4), K.Gun, nil, Style.decor())
	Style.block(parent, cf * CFrame.new(0, h + 1.05, 0), Vector3.new(w + 1.6, 0.3, d + 1.6), K.GunCap, nil, Style.ghost())
	local t = Buildings.Contour
	local wide = Buildings.sub(Buildings.raise(body, y0), 0, 0, w + 1.4, d + 1.4)
	local lit: { string } = neonFaces or { "Front" }
	for _, side in lit do
		local wall, ww = Buildings.face(wide, side)
		glow(parent, wall * CFrame.new(0, h + t / 2 + 0.04, -0.045), Vector3.new(ww + 0.1, t, 0.09), K.EdgeNeon)
	end
	return y0 + h + 1.2
end

export type CozyOpts = {
	Floors: number,
	Stone: Color3?,
	Plaster: Color3?,
	Timber: Color3?,
	Timbering: number?, -- half-timber studs per plaster wall (front, back); 0 = none
	Brace: number?, -- the bay of the diagonal half-timber brace on the front (nil = none)
	StoneFaces: { string }?, -- faces with the chunky stone blocks (default Front, Left, Right)
}

--[[
	Concept v1 town house: a warm cobble ground floor on a plinth with
	chunky staggered stone blocks on the street faces and big two-stone
	quoins on every corner that stand out of the wall, a jettied plaster
	upper part (one or two storeys) with timber corner posts, beams between
	the storeys and dark half-timbering on the front and back. Returns the
	top of the walls. 22-34 parts.
]]
function Buildings.cozyShell(parent: Instance, body: Body, o: CozyOpts, rng: Rng.Rng): number
	local w, d = body.w, body.d
	local G, U = Buildings.Ground, Buildings.Upper
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
	-- chunky staggered stone blocks near the corners (two low, one high)
	local stoneFaces: { string } = o.StoneFaces or { "Front", "Left", "Right" }
	for _, side in stoneFaces do
		local wall, ww = Buildings.face(body, side)
		local blocks = {
			{ x = ww / 2 - 1.9, y = 1.55, w = 2.1, h = 1.0 },
			{ x = -(ww / 2 - 2.3), y = 1.3, w = 1.7, h = 0.9 },
			{ x = -(ww / 2 - 1.75), y = 7.15, w = 1.6, h = 0.9 },
		}
		for i, b in blocks do
			-- the two low blocks only when the wall is wide enough to keep them apart
			if i ~= 2 or (blocks[1].x - blocks[1].w / 2) - (b.x + b.w / 2) > 0.3 then
				trim(parent, wall * CFrame.new(b.x, b.y, -0.12), Vector3.new(b.w, b.h, 0.2), K.StoneCourse)
			end
		end
	end
	-- big quoins: two stones per corner (0.45-0.7 out of the walls), the lower one long along X, the upper long along Z
	local top = G - 0.35
	local foot = 0.74
	local split = foot + (top - foot) * 0.48
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local lowH, highH = split - foot, top - split - 0.06
			Style.block(
				parent,
				cf * CFrame.new(sx * w / 2, foot + lowH / 2, sz * d / 2),
				Vector3.new(1.4, lowH, 0.9),
				K.StoneCourse,
				nil,
				Style.decor({ CastShadow = false })
			)
			Style.block(
				parent,
				cf * CFrame.new(sx * w / 2, split + 0.06 + highH / 2, sz * d / 2),
				Vector3.new(0.9, highH, 1.4),
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
		-- beams between the upper storeys and under the eaves
		for f = 2, o.Floors - 1 do
			trim(parent, cf * CFrame.new(0, G + (f - 1) * U, 0), Vector3.new(jw + 0.2, 0.4, jd + 0.2), timber)
		end
		Style.block(parent, cf * CFrame.new(0, H, 0), Vector3.new(w + 1, 0.5, d + 1), timber, nil, Style.ghost())
		local studs = o.Timbering or 2
		if studs > 0 then
			local jetty = Buildings.sub(body, 0, 0, jw, jd)
			for _, side in { "Front", "Back" } do
				local wall, ww = Buildings.face(jetty, side)
				Buildings.halfTimber(parent, wall, ww - 0.6, G + 0.3, H - 0.25, studs, if side == "Front" then o.Brace else nil)
			end
		end
	end
	return H
end

---------------------------------------------------------------- roofs

--[[
	City Kit flat roof for the cozy wings: a parapet slab and a dark deck
	inset. Returns the deck height. 2 parts.
]]
function Buildings.flatRoof(parent: Instance, body: Body, top: number, rim: Color3?): number
	local cf = body.cf
	Style.block(
		parent,
		cf * CFrame.new(0, top + 0.45, 0),
		Vector3.new(body.w + 0.8, 0.9, body.d + 0.8),
		rim or K.PanelLight,
		nil,
		Style.decor()
	)
	trim(parent, cf * CFrame.new(0, top + 0.95, 0), Vector3.new(body.w - 0.6, 0.12, body.d - 0.6), K.Deck)
	return top + 1
end

--[[
	Gable roof with gable-end infill, ridge along the body's local X (pass
	a body turned a quarter for a gable-front house). Overhangs: 0.6 at the
	gables, ~0.9 at the eaves. `slate` = the roof colour, `ridge` = the
	ridge cap. 5 parts.
]]
function Buildings.gableRoof(
	parent: Instance,
	body: Body,
	eave: number,
	h: number,
	infill: Color3,
	slate: Color3?,
	ridge: Color3?,
	tight: boolean?
)
	local w, half = body.w, body.d / 2
	local base = body.cf * CFrame.new(0, eave, 0)
	local p = Style.decor()
	-- `tight`: short overhangs and thinner slabs for the narrow row houses (0.35 at the gables, ~0.4 at the eaves)
	local gable = if tight then 0.35 else 0.6
	local ext = if tight then 0.12 else 0.3
	local thick = if tight then 0.36 else 0.5
	Geo.wedge(parent, base * CFrame.new(0, h / 2, -half / 2), Vector3.new(w, h, half), infill, SMOOTH, p)
	Geo.wedge(parent, base * CFrame.new(0, h / 2, half / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(w, h, half), infill, SMOOTH, p)
	local a = math.atan2(h, half)
	local len = math.sqrt(h * h + half * half)
	for _, s in { -1, 1 } do
		local mid = Vector3.new(0, h / 2, s * half / 2)
		local n = Vector3.new(0, math.cos(a), s * math.sin(a))
		local down = Vector3.new(0, -math.sin(a), s * math.cos(a))
		local c = mid + n * (thick / 2) + down * ext
		Style.block(
			parent,
			base * CFrame.new(c) * CFrame.Angles(s * a, 0, 0),
			Vector3.new(w + 2 * gable, thick, len + 2 * ext),
			slate or K.Slate,
			nil,
			p
		)
	end
	Style.block(
		parent,
		base * CFrame.new(0, h + 0.2, 0),
		Vector3.new(w + 2 * gable + 0.2, 0.55, 1),
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
	City Kit detail-overhang-wide over a shop front: a tray on the wall (a
	slab with a raised front lip) and a neon line along the lip. 3 parts.
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
	Geo.cylinder(parent, (at * CFrame.new(0, 1.25, 0)).Position, 0.12, math.min(w, d) * 0.7, K.Gun, SMOOTH, Style.tiny())
end

-- City Kit rooftop dome (a half-buried ball). 1 part.
function Buildings.dome(parent: Instance, at: CFrame, size: number, color: Color3?)
	Geo.ball(parent, (at * CFrame.new(0, size * 0.1, 0)).Position, size, color or K.PanelLight, SMOOTH, Style.tiny())
end

-- City Kit water tank on a stand (building-l). 4 parts.
function Buildings.waterTank(parent: Instance, at: CFrame, size: number?)
	local s = size or 3
	Style.block(parent, at * CFrame.new(0, 0.6, 0), Vector3.new(s * 0.8, 1.2, s * 0.8), K.Gun, nil, Style.tiny({ CastShadow = true }))
	local p = at.Position
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.45, 0), s * 0.9, s, C.Wood, SMOOTH, Style.tiny({ CastShadow = true }))
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.45, 0), 0.3, s + 0.12, C.Iron, SMOOTH, Style.tiny())
	Geo.cylinder(parent, p + Vector3.new(0, 1.2 + s * 0.95, 0), 0.3, s * 1.1, K.SlateDark, SMOOTH, Style.tiny())
end

--[[
	Space Station dish antenna: a mast, a tilted dish (a thin disc facing
	the frame's front and up) and a small beacon tip (0.3: no white blob).
	3 parts.
]]
function Buildings.antenna(parent: Instance, at: CFrame, h: number, tip: Color3)
	trim(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(0.3, h, 0.3), K.MetalEdge)
	Geo.make(
		"Part",
		Style.tiny({
			Shape = Enum.PartType.Cylinder,
			CFrame = at * CFrame.new(0, h * 0.62, -0.35) * CFrame.Angles(math.rad(35), 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Size = Vector3.new(0.18, 2.2, 2.2),
			Color = K.PanelLight,
			Material = SMOOTH,
		}),
		parent
	)
	glow(parent, at * CFrame.new(0, h + 0.15, 0), Vector3.new(0.3, 0.3, 0.3), tip)
end

-- Stone chimney (light stone courses) with a darker cap. 2 parts.
function Buildings.chimney(parent: Instance, at: CFrame, h: number, rng: Rng.Rng)
	Style.block(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(1.5, h, 1.5), Style.vary(K.StoneCourse, rng, 0.04), nil, Style.decor())
	trim(parent, at * CFrame.new(0, h + 0.2, 0), Vector3.new(2, 0.4, 2), K.StoneCap)
end

--[[
	Space Station container-tall: an upright drum with two metal rings and
	a cap (`at` = ground center). 4 parts.
]]
function Buildings.container(parent: Instance, at: Vector3, h: number, color: Color3, dia: number?)
	local dd = dia or 1.9
	local body = Geo.cylinder(parent, at + Vector3.new(0, h / 2, 0), h, dd, color, SMOOTH, Style.decor())
	body.Name = "Container"
	for _, f in { 0.22, 0.72 } do
		Geo.cylinder(parent, at + Vector3.new(0, h * f, 0), 0.4, dd + 0.25, K.MetalEdge, SMOOTH, Style.tiny())
	end
	Geo.cylinder(parent, at + Vector3.new(0, h + 0.15, 0), 0.3, dd - 0.3, K.Gun, SMOOTH, Style.tiny())
end

--[[
	Space Station display-wall-wide beside a door: a gunmetal frame and a
	glowing orange screen (`wall` frame, x, y = screen center). 2 parts.
]]
function Buildings.displayWall(parent: Instance, wall: CFrame, x: number, y: number, w: number?, h: number?)
	local sw, sh = w or 1.6, h or 1.1
	trim(parent, wall * CFrame.new(x, y, -0.2), Vector3.new(sw + 0.5, sh + 0.5, 0.4), K.Gun)
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
	light top rail (`at` = the deck point under the rail middle,
	LookVector = outward). 2 parts.
]]
function Buildings.balconyRail(parent: Instance, at: CFrame, w: number)
	trim(parent, at * CFrame.new(0, 0.45, 0), Vector3.new(w, 0.5, 0.3), C.Hazard)
	trim(parent, at * CFrame.new(0, 0.88, 0.03), Vector3.new(w + 0.1, 0.36, 0.42), K.PanelLight)
end

--[[
	Hanging cloth banner (concept v2's forge banners): a metal rod, the
	cloth and a gold stripe near the bottom. `wall` = wall frame, `out` =
	the cloth's distance from the wall. 3 parts.
]]
function Buildings.banner(parent: Instance, wall: CFrame, x: number, top: number, w: number, h: number, color: Color3, out: number?)
	local z = -(out or 0.3)
	trim(parent, wall * CFrame.new(x, top, z - 0.05), Vector3.new(w + 0.6, 0.3, 0.3), K.Metal)
	trim(parent, wall * CFrame.new(x, top - h / 2, z), Vector3.new(w, h, 0.15), color)
	trim(parent, wall * CFrame.new(x, top - h + 0.7, z - 0.12), Vector3.new(w, 0.35, 0.1), C.Gold)
end

--[[
	City Kit detail-parasol-a at street level: a round white cafe table on
	a foot, the pole through it and a two-slab canopy (`at` = ground
	center). 5 parts.
]]
function Buildings.parasol(parent: Instance, at: CFrame, color: Color3, size: number?)
	local s = size or 3.4
	Geo.cylinder(parent, (at * CFrame.new(0, 0.1, 0)).Position, 0.2, 1.1, K.Gun, SMOOTH, Style.tiny())
	Geo.cylinder(parent, (at * CFrame.new(0, 1.6, 0)).Position, 0.2, 2.0, C.AwningWhite, SMOOTH, Style.tiny()).Name = "CafeTable"
	trim(parent, at * CFrame.new(0, 2.85, 0), Vector3.new(0.22, 5.5, 0.22), K.Metal)
	-- the canopy: a low pyramid of four wedges (one per side), tips meeting at the pole
	local h = s * 0.32
	for i = 0, 3 do
		local turn = at * CFrame.new(0, 4.9 + h / 2, 0) * CFrame.Angles(0, i * math.pi / 2, 0)
		Geo.wedge(parent, turn * CFrame.new(0, 0, -s / 4), Vector3.new(s, h, s / 2), color, SMOOTH, Style.tiny({ CastShadow = i == 0 }))
	end
end

-- A little stool by a cafe table. 1 part.
function Buildings.stool(parent: Instance, at: Vector3)
	Geo.cylinder(parent, at + Vector3.new(0, 0.5, 0), 1.0, 0.9, C.Wood, SMOOTH, Style.tiny())
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
	A small ore cart (`at` = ground center, LookVector = along the cart): a
	tub with a copper band, an ore load and two axles. 5 parts.
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

--[[
	Rooftop jib crane (Factory / Space Station structure): a gunmetal mast,
	a long boom toward the frame's -Z (LookVector), a counterweight, a
	hazard band, a cable and a hanging crate (`at` = the deck point under
	the mast). 7 parts.
]]
function Buildings.crane(parent: Instance, at: CFrame, h: number, reach: number)
	Style.block(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(0.8, h, 0.8), K.Gun, nil, Style.tiny({ CastShadow = true }))
	trim(parent, at * CFrame.new(0, h * 0.3, 0), Vector3.new(0.9, 0.6, 0.9), C.Hazard)
	local boomY = h + 0.3
	Style.block(
		parent,
		at * CFrame.new(0, boomY, -reach / 2 + 1),
		Vector3.new(0.6, 0.6, reach + 2),
		C.Hazard,
		nil,
		Style.tiny({ CastShadow = true })
	)
	trim(parent, at * CFrame.new(0, boomY, 1.6), Vector3.new(1.2, 1.1, 1.0), K.Gun)
	trim(parent, at * CFrame.new(0, boomY + 0.8, 0), Vector3.new(0.5, 1.0, 0.5), K.Gun)
	trim(parent, at * CFrame.new(0, boomY - 1.4, -reach + 0.4), Vector3.new(0.12, 2.6, 0.12), K.Metal)
	trim(parent, at * CFrame.new(0, boomY - 3.2, -reach + 0.4), Vector3.new(1.2, 1.0, 1.2), C.WoodLight)
end

---------------------------------------------------------------- signs

--[[
	A faceted cut gem: a wide trapezoid crown (a block between two wedges)
	over an inverted triangle pavilion (two wedges), and a small white
	highlight on the flat table. `cf` = center, front = LookVector. 6 parts.
]]
local function gemIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	local d = 0.3
	local crownH = s * 0.24
	local crownY = s * 0.16
	local table_ = s * 0.36
	local slope = s * 0.18
	local p = Style.tiny()
	glow(parent, cf * CFrame.new(0, crownY, 0), Vector3.new(table_, crownH, d), color)
	-- crown sides: tall face toward the table, sloping down to the girdle
	Geo.wedge(
		parent,
		cf * CFrame.new(table_ / 2 + slope / 2, crownY, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		Vector3.new(d, crownH, slope),
		color,
		NEON,
		p
	)
	Geo.wedge(
		parent,
		cf * CFrame.new(-table_ / 2 - slope / 2, crownY, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(d, crownH, slope),
		color,
		NEON,
		p
	)
	-- pavilion: two upside-down wedges meeting at the culet point
	local girdle = table_ + slope * 2
	local pavH = s * 0.5
	local pavY = crownY - crownH / 2 - pavH / 2
	Geo.wedge(
		parent,
		cf * CFrame.new(girdle / 4, pavY, 0) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi),
		Vector3.new(d, pavH, girdle / 2),
		color:Lerp(Color3.new(0, 0, 0), 0.18),
		NEON,
		p
	)
	Geo.wedge(
		parent,
		cf * CFrame.new(-girdle / 4, pavY, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi),
		Vector3.new(d, pavH, girdle / 2),
		color,
		NEON,
		p
	)
	trim(
		parent,
		cf * CFrame.new(-table_ * 0.12, crownY + crownH * 0.18, -d / 2 - 0.04),
		Vector3.new(table_ * 0.5, crownH * 0.28, 0.06),
		C.FlowerWhite
	)
end

--[[
	The inn's mug: an amber SmoothPlastic body with a neon rim, a wide C
	handle (two arms and a grip) and a white foam cap overhanging the rim
	with a bump on top. 7 parts.
]]
local function mugIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	local bw, bh = s * 0.44, s * 0.5
	local body = cf * CFrame.new(s * 0.1, -s * 0.1, 0)
	glow(parent, body, Vector3.new(bw, bh, 0.34), color)
	glow(parent, body * CFrame.new(0, bh / 2 - 0.1, -0.04), Vector3.new(bw + 0.06, 0.16, 0.38), color)
	glow(parent, body * CFrame.new(0, -bh / 2 + 0.1, -0.04), Vector3.new(bw + 0.06, 0.12, 0.38), color)
	-- the handle on the viewer's right (a frame's local -X)
	local hx = -bw / 2 - s * 0.1
	trim(parent, body * CFrame.new(hx, bh * 0.22, 0), Vector3.new(s * 0.22, s * 0.08, 0.3), K.MugBody)
	trim(parent, body * CFrame.new(hx, -bh * 0.22, 0), Vector3.new(s * 0.22, s * 0.08, 0.3), K.MugBody)
	trim(parent, body * CFrame.new(hx - s * 0.08, 0, 0), Vector3.new(s * 0.08, bh * 0.52, 0.3), K.MugBody)
	-- foam: wider than the body, with a bump
	trim(parent, body * CFrame.new(0, bh / 2 + s * 0.06, -0.08), Vector3.new(bw + s * 0.12, s * 0.14, 0.4), K.Foam)
end

-- A lab flask (round body, neck, a white rim). 3 parts.
local function flaskIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	glow(parent, cf * CFrame.new(0, -s * 0.16, 0) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(s * 0.42, s * 0.42, 0.3), color)
	glow(parent, cf * CFrame.new(0, s * 0.22, 0), Vector3.new(s * 0.16, s * 0.36, 0.3), color)
	trim(parent, cf * CFrame.new(0, s * 0.42, -0.05), Vector3.new(s * 0.3, s * 0.1, 0.36), C.AwningWhite)
end

-- A cart icon (tub, load, two wheels). 4 parts.
local function cartIcon(parent: Instance, cf: CFrame, s: number, color: Color3)
	glow(parent, cf * CFrame.new(0, s * 0.02, 0), Vector3.new(s * 0.7, s * 0.3, 0.3), color)
	trim(parent, cf * CFrame.new(0, s * 0.22, -0.02), Vector3.new(s * 0.56, s * 0.12, 0.32), C.Copper)
	for _, sx in { -1, 1 } do
		trim(parent, cf * CFrame.new(sx * s * 0.2, -s * 0.24, -0.02), Vector3.new(s * 0.18, s * 0.18, 0.32), K.PanelLight)
	end
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
	"Mug", "Flask", "Cart". ~12-18 parts. Returns the text board (named
	TownSign, attribute Span = the whole sign's width).
]]
function Buildings.sign(parent: Instance, at: CFrame, text: string, textW: number, h: number, icon: string?, iconColor: Color3?): Part
	-- a narrow icon board leaves the letters as much width as possible
	local iconW = if icon then h * 0.74 else 0
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
	board:SetAttribute("Span", total)
	-- backing plate
	trim(parent, at * CFrame.new(0, 0, depth / 2 + 0.2), Vector3.new(total + 0.6, h + 0.6, 0.4), K.Metal)
	local t = math.clamp(h * 0.08, 0.2, 0.32)
	local z = -depth / 2 - 0.1
	signFrame(parent, at, total, h, z, t, 0.2, K.SignNeon)
	if icon then
		local iconAt = at * CFrame.new(total / 2 - iconW / 2, 0, 0)
		trim(parent, iconAt, Vector3.new(iconW - 0.02, h - 0.02, depth), K.SignBoard)
		glow(parent, at * CFrame.new(total / 2 - iconW, 0, z), Vector3.new(t, h - t, 0.2), K.SignNeon)
		-- (the big mug stands a little further out: it overlaps the neon frame)
		local front = iconAt * CFrame.new(0, 0, -depth / 2 - (if icon == "Mug" then 0.2 else 0.15))
		local color = iconColor or K.Amber
		local s = if icon == "Mug" then iconW * 1.5 else iconW * 0.94
		if icon == "Gem" then
			gemIcon(parent, front, s, color)
		elseif icon == "Mug" then
			mugIcon(parent, front, s, color)
		elseif icon == "Flask" then
			flaskIcon(parent, front, s, color)
		elseif icon == "Cart" then
			cartIcon(parent, front, s, color)
		else
			Style.icon(parent, front, icon, s, color, NEON)
		end
	end
	return board
end

-- The sign flat on a wall (`wall` frame, center x/y of the whole sign, `out` = board center off the wall). ~12-18 parts.
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
	Blade sign: a double-sided neon board standing on a roof deck on two
	gunmetal legs, turned perpendicular to the facade so the street, the
	plaza and the hero camera all read it (`at` = bottom center on the
	deck, LookVector = the front face; `legs` = false hangs it from its top
	edge). The neon frame is deeper than the board, so it frames both
	faces. 5-7 parts. Returns the board (BladeSign).
]]
function Buildings.bladeSign(parent: Instance, at: CFrame, text: string, w: number, h: number, legs: boolean?): Part
	local foot = 0
	if legs ~= false then
		foot = 1.1
		for _, sx in { -1, 1 } do
			trim(parent, at * CFrame.new(sx * w * 0.3, 0.55, 0), Vector3.new(0.4, 1.1, 0.4), K.Gun)
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
	signFrame(parent, center, w, h, 0, math.clamp(h * 0.08, 0.2, 0.3), 0.62, K.SignNeon)
	return board
end

return Buildings
