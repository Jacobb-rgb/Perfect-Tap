--[[
	SHOP (the Gear shop) and UPGRADES (the Tech shop): the concept v2 sci-fi
	shop modules either side of the Great Forge (docs/art/lobby_concept_v2.webp).
	Both share one module built from Kenney Space Station shapes (Tech kit):
	  - a massive bevelled dark gunmetal header frame across the whole front
	    whose face is the big glowing sign box (SHOP + a shopping cart /
	    UPGRADES + a gear outline), chamfered upper corners, a thick blue
	    neon tube in a dark channel along its outline, a light top lip, a
	    light bevel lip under its front edge and an orange band
	  - chunky end pylons carrying the header (bevelled corbels under its
	    overhang, light bevel lips on their feet), each with an inset
	    display-wall screen showing an item icon and blue neon edges
	  - a facade of light gunmetal face panels (the recesses and seams stay
	    dark) with open lit display bays (wall-window-banners without glass)
	    either side of a wall-door-wide frame: each bay holds a glass case on
	    a plinth with a neon front edge, a warm floor glow, a small neon
	    plinth under one big item, a light strip under the case lid and a
	    glowing back panel behind it, so the bays read as lit shop windows
	  - cyan glass showcases (table-display: four neon corner posts, a lit
	    floor plate, a glowing back panel, a small neon plinth) in front of
	    the pylons, a display-wall screen on the side that faces the spawn,
	    shelves of goods inside, the counter in the door = the hook part
	    (ShopCounter / UpgradeCounter)
	  - a finished sci-fi back: two wall-banner panels (the orange band at
	    two heights), neon corner tubes, a display-wall-wide screen in a
	    gunmetal bezel with a thin neon frame, two vent grilles on the
	    orange band, pipes, the roof edge tube in a dark channel, roof
	    containers
	The module fills its LobbyLayout footprint: a 20 wide piece has one
	display bay per side; from 27 studs wide every side gets a second bay:
	a slim mid pylon with its own showcase and a second open bay (the wide
	build drops the mid pylons' light studs to stay part-neutral).
	UPGRADES is the sister module: purple frames and purple/blue neon
	accents, a violet bay glow, machine models in the showcases and bays.
	(perf pass 1) On a two-bay side the pieces both bays have at the same
	place run on as one longer block hidden behind the mid pylon and the
	wall between the windows: the wall below and above the windows, the
	jambs either side of the mid pylon, the foot strip, and inside the bays
	the dark glass, the plinth with its neon edge and floor glow, the case
	lid and its light strip; the glass case stays one per window (seen at
	an angle from the porch, each window's item keeps a glass end at the
	jamb); the door jambs reach over the inner bay jambs (all of them
	BAY_JAMB wide); one back wall carries both orange bands; the mid
	pylons skip the foot lip and orange band their showcase's stand hides
	(Tech.leaveOut: the Districts spec checks they stay hidden).
	Shop / Upgrades: 427 / 444 -> 398 / 415 parts. Known, accepted: from
	the door, looking at an angle through bay 1, the shared lid and plinth
	glow run on under the jamb toward bay 2 (they ended at the jamb).

	Local frame (LobbyLayout piece, 20 x 20 x 14): front = -Z (toward the
	plaza), seen from the front local +X is on the viewer's left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local ShopkeeperConfig = require(Shared.Config.ShopkeeperConfig)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Stalls = {}

type Opts = { [string]: any }

local C = Kit.C
local rgb = Color3.fromRGB

local FLOOR = 0.6 -- floor top
local FACADE_Z = -1.7 -- facade wall center (front face at -2.2)
local BACK_Z = 6.1 -- back wall center (back face at 6.6)
local WALL_TOP = 10.4
local ROOF_TOP = 11.2
local DOOR_W, DOOR_H = 5.4, 7.0 -- door opening
local DOOR_HALF = 3.1 -- half width of the door frame
local PYLON_Z0, PYLON_Z1 = -4.8, -1.2 -- pylon front and back
local HEAD_Y0, HEAD_Y1 = WALL_TOP, 17.0 -- the header frame
local HEAD_Z0, HEAD_Z1 = -6.2, -3.2 -- header front and back faces
local HEAD_CHAMFER = 1.6
-- the header frame: a dark gunmetal (between Tech.Metal and MetalLight) that
-- stays dark in full sun, the light lip keeps the bevel readable
local HEADER = rgb(36, 39, 54)
local HEADER_LIP = Tech.MetalLight -- (light metal only for lips, bolts and trims)
-- the facade face panels (walls, pylons, lintel, cornice): dark gunmetal
-- (concept v2: dark frames, glowing neon outlines; light plastic panels
-- read as toy boxes in the sun), MetalDeep for the recesses
local FACE = Tech.MetalDark
-- the opaque dark glass of the display bays behind the porch showcases
local DARK_GLASS = rgb(16, 24, 44)
local SIGN_Y, SIGN_H = 13.55, 4.6
local COUNTER_Z = 0.9
local COUNTER_TOP = FLOOR + 3.3
local SHELF_Z = 5.05
local SHELVES = { FLOOR + 2.8, FLOOR + 5.2 }
local CASE_Z = -5.82 -- porch showcases (in front of the pylons)
-- (lobby fix round 3: the porch showcases about 1.4 times as big)
local CASE_W, CASE_D, CASE_H, CASE_GLASS = 4.2, 2.4, 2.2, 3.0
local TWO_BAYS = 13.5 -- half width from which every side gets a second display bay
-- the open display bays: the opening (heights above the floor), the glass
-- case on its plinth (the plinth top level with the sill top) and the
-- glowing back panel behind it
local BAY_Y0, BAY_Y1 = 1.5, 6.4
local BAY_PLINTH = 2.3 -- the item sits in the middle of the opening
local BAY_CASE = 2.5
local BAY_Z = 0.1 -- case center (the facade's back face is at -1.2)
local BAY_D = 2.4 -- plinth depth
local BAY_BACK_Z = 1.5
-- the jamb either side of a bay window (the window is the bay's width less
-- two jambs); the door jambs and the shared blocks of a two-bay side meet
-- at it (perf pass 1)
local BAY_JAMB = 0.5

-- The facade wall's plane and heights (local frame), for the Districts spec.
Stalls.Facade = { Z = FACADE_Z, Depth = 1.0, Floor = FLOOR, DoorHeight = DOOR_H, BayJamb = BAY_JAMB }
-- screen glyph colors: deep enough to stay colored under bloom
local GLYPH_BLUE = rgb(20, 150, 255)
local GEAR_PURPLE = rgb(116, 46, 153) -- neon at ~60% value: a saturated violet gear, no starburst
local UPG_TUBE = rgb(170, 80, 255) -- UPGRADES' violet tubes (its own identity, not SHOP's blue; round 2: bright enough to glow)
local UPG_NEON = rgb(150, 50, 220)
local UPG_PINK = rgb(255, 70, 200) -- (round 3) the pink neon plates under UPGRADES' showcase items
-- saturated goods that read at plaza distance
local HELMET = rgb(255, 196, 18)
local BOOTS = rgb(222, 38, 38)
local PACK = rgb(36, 178, 72)
local MAGNET = rgb(226, 30, 40)
local LENS = rgb(255, 226, 160) -- the helmet's warm white lamp lens (small: no white blob)

export type House = {
	Counter: Part,
	Interior: CFrame, -- floor point behind the counter (keeper spot)
	-- display floors of the porch showcases: +X outer, -X outer, then (two
	-- bays) +X mid, -X mid
	Cases: { CFrame },
	-- display floors of the bay cases: +X inner, -X inner, then (two bays)
	-- +X outer, -X outer
	Windows: { CFrame },
	ItemScale: number, -- item scale that fills about 70% of a bay case
	Shelves: { number }, -- shelf top heights
	ScreenAt: CFrame, -- center of the side screen (front = outward)
	PylonScreens: { CFrame }, -- centers of the end pylon screens (+X first)
	IconAt: CFrame?, -- icon panel of the header sign
	HalfWidth: number,
}

type Bay = { X: number, W: number } -- a window wall (center and width, +X side)
type Pylon = { X: number, W: number, Outer: boolean }

-- The display bays and pylons of one side (+X; the other side mirrors them).
local function bays(hw: number): ({ Bay }, { Pylon })
	if hw < TWO_BAYS then
		local pw = 2.4
		local ww = hw - DOOR_HALF - pw
		return { { X = DOOR_HALF + ww / 2, W = ww } }, { { X = hw - pw / 2, W = pw, Outer = true } }
	end
	local pw, mw = 2.2, 1.6
	local ww = (hw - DOOR_HALF - pw - mw) / 2
	return {
		{ X = DOOR_HALF + ww / 2, W = ww },
		{ X = DOOR_HALF + ww + mw + ww / 2, W = ww },
	}, {
		{ X = DOOR_HALF + ww + mw / 2, W = mw, Outer = false },
		{ X = hw - pw / 2, W = pw, Outer = true },
	}
end

--[[
	The shared shop module. opts:
	  Sign, SignWidth, IconLeft   header sign text, width, icon panel side
	  Frame                       window/door frame color (Kenney band)
	  Accent                      neon accent (porch light, floor edge)
	  SignLight                   true: the second light goes to the sign (it
	                              faces away from the sun); "Flood": a
	                              floodlight on the stall in front lights it
	                              (Fronts); else it goes to the porch strip
	  ScreenSide                  +1 / -1: the side wall that faces the spawn
	  Screen                      screen color
	  BayGlow                     the glowing back panel of the open bays
	  Plinth                      the small neon plinths under the items
	  CaseBack                    the glowing back panel inside the showcases
	  Tube, Neon                  the thick neon tubes and the thin neon lines
	                              (default Tech.Tube / Tech.Neon: blue)
	  FrameNeon                   a thin neon line inside the bay window frames
	  Header                      the header frame color (default HEADER)
]]
local function house(m: Model, cf: CFrame, hw: number, rng: Rng.Rng, opts: Opts): House
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local frame: Color3 = opts.Frame
	local accent: Color3 = opts.Accent
	local tube: Color3 = opts.Tube or Tech.Tube
	local neonLine: Color3 = opts.Neon or Tech.Neon
	local header: Color3 = opts.Header or HEADER
	local windowBays, pylons = bays(hw)
	local outerPylon = pylons[#pylons]
	local sideX = hw - 0.75 -- side wall centers (outer faces at +-hw - 0.25)
	local W = 2 * hw

	-- floor panel: dark slab, lighter tiles inside, neon edges
	Style.block(m, at(0, FLOOR / 2, 0), Vector3.new(W - 0.2, FLOOR, 13.8), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.02, 2.2), Vector3.new(W - 2.8, 0.04, 7.8), Tech.Metal)
	Kit.bit(m, at(0, FLOOR + 0.02, -4.4), Vector3.new(W - 7.6, 0.04, 4.0), Tech.Metal)
	Tech.glow(m, at(0, FLOOR - 0.15, -6.92), Vector3.new(W - 0.6, 0.2, 0.12), accent)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * (hw - 0.08), FLOOR - 0.15, -0.1), Vector3.new(0.12, 0.2, 13.4), neonLine)
	end

	-- facade: the open display bays (window walls without glass) and the
	-- wide door frame in light face panels, a lintel over them
	-- (perf pass 1: on a two-bay side the wall pieces both bays share run on
	-- as one block behind the mid pylon, see the header)
	local twoBays = #windowBays == 2
	for _, side in { -1, 1 } do
		for bi, bay in windowBays do
			-- (the jamb toward the door is local -side, toward the outer pylon +side)
			local noJamb: { [number]: boolean } = {}
			if twoBays then
				noJamb[-side] = true -- bay 1: the door jamb reaches over it; bay 2: the shared block
				if bi == 1 then
					noJamb[side] = true -- the shared block behind the mid pylon
				end
			end
			Tech.windowWall(m, at(side * bay.X, FLOOR, FACADE_Z), bay.W, DOOR_H, 1.0, {
				Color = FACE,
				WindowWidth = bay.W - 2 * BAY_JAMB,
				WindowBottom = BAY_Y0,
				WindowTop = BAY_Y1,
				Frame = frame,
				Glass = false,
				FrameNeon = opts.FrameNeon,
				NoBelow = twoBays,
				NoAbove = twoBays,
				NoFoot = twoBays,
				NoJamb = noJamb,
			})
		end
		if twoBays then
			local b1, b2 = windowBays[1], windowBays[2]
			local x0 = b1.X - b1.W / 2 + BAY_JAMB -- the door jamb reaches this far (JambExtra)
			local x1 = b2.X + b2.W / 2
			local span, mid = x1 - x0, side * (x0 + x1) / 2
			Style.block(m, at(mid, FLOOR + BAY_Y0 / 2, FACADE_Z), Vector3.new(span, BAY_Y0, 1.0), FACE, nil, Style.solid())
			Style.block(
				m,
				at(mid, FLOOR + (BAY_Y1 + DOOR_H) / 2, FACADE_Z),
				Vector3.new(span, DOOR_H - BAY_Y1, 1.0),
				FACE,
				nil,
				Style.solid()
			)
			-- bay 1's outer jamb, the wall behind the mid pylon and bay 2's inner jamb
			local j0, j1 = b1.X + b1.W / 2 - BAY_JAMB, b2.X - b2.W / 2 + BAY_JAMB
			Style.block(
				m,
				at(side * (j0 + j1) / 2, FLOOR + (BAY_Y0 + BAY_Y1) / 2, FACADE_Z),
				Vector3.new(j1 - j0, BAY_Y1 - BAY_Y0, 1.0),
				FACE,
				nil,
				Style.solid()
			)
			local f0 = b1.X - b1.W / 2
			Kit.bit(m, at(side * (f0 + x1) / 2, FLOOR + 0.4, FACADE_Z - 0.7), Vector3.new(x1 - f0, 0.8, 0.4), Tech.MetalDark)
		end
	end
	Tech.doorFrame(m, at(0, FLOOR, FACADE_Z), 2 * DOOR_HALF, DOOR_H, 1.0, {
		Color = FACE,
		OpeningWidth = DOOR_W,
		OpeningHeight = DOOR_H,
		Frame = frame,
		Neon = tube,
		JambExtra = if twoBays then BAY_JAMB else nil,
	})
	-- chamfered upper corners make the door read as the concept's bevelled
	-- opening (a frame turned upside down: its "up" points down the jambs)
	local doorTop = at(0, FLOOR + DOOR_H, FACADE_Z) * CFrame.Angles(0, 0, math.pi)
	for _, side in { -1, 1 } do
		Tech.flatTri(m, doorTop, -side * DOOR_W / 2, 0, side, 0.9, 0.9, 1.14, frame)
	end
	local lintelH = WALL_TOP - FLOOR - DOOR_H
	local lintelW = 2 * (outerPylon.X - outerPylon.W / 2)
	Style.block(
		m,
		at(0, FLOOR + DOOR_H + lintelH / 2, FACADE_Z),
		Vector3.new(lintelW, lintelH, 1.0),
		Style.vary(FACE, rng, 0.02),
		nil,
		Style.solid()
	)
	Kit.bit(m, at(0, FLOOR + DOOR_H + lintelH * 0.6, FACADE_Z - 0.56), Vector3.new(lintelW, 0.6, 0.12), Tech.Band)
	Tech.glow(m, at(0, FLOOR + DOOR_H + 0.22, FACADE_Z - 0.58), Vector3.new(lintelW, 0.3, 0.14), tube)

	-- side wall-banners (the roof covers their tops)
	local wallTall = WALL_TOP - FLOOR
	local sideLen = (BACK_Z + 0.5) - (FACADE_Z - 0.5)
	local sideZ = ((BACK_Z + 0.5) + (FACADE_Z - 0.5)) / 2
	for _, side in { -1, 1 } do
		Tech.wall(m, at(side * sideX, FLOOR, sideZ) * CFrame.Angles(0, -side * math.pi / 2, 0), sideLen, wallTall, 1.0, {
			Color = FACE,
			Cap = false,
			BandY = 0.3,
		})
	end

	-- the finished sci-fi back: two wall-banner panels with the orange band
	-- at two heights and a dark seam pilaster, neon tubes on the back
	-- corners, a display-wall-wide screen in a gunmetal bezel with a thin
	-- neon frame, two vent grilles on the high orange band, two pipes
	local backZ = BACK_Z + 0.5
	local panelW = hw - 0.25
	local bandY = { 0.3, 0.62 }
	-- (perf pass 1) one wall (slab, foot, bevel) under both panels' bands
	Tech.wall(m, at(0, FLOOR, BACK_Z) * CFrame.Angles(0, math.pi, 0), 2 * panelW, wallTall, 1.0, {
		Cap = false,
		Band = false,
	})
	for i, side in { 1, -1 } do
		-- (Tech.wall's band: BandY of the height, on the back face)
		local bh = math.clamp(wallTall * 0.1, 0.5, 1.1)
		Kit.bit(m, at(side * panelW / 2, FLOOR + bandY[i] * wallTall, BACK_Z + 0.56), Vector3.new(panelW, bh, 0.12), Tech.Band)
	end
	Kit.block(
		m,
		at(0, FLOOR + wallTall / 2, backZ + 0.15),
		Vector3.new(0.8, wallTall, 0.3),
		Tech.MetalDark,
		nil,
		Style.tiny({ CastShadow = true })
	)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * (hw - 0.27), FLOOR + wallTall / 2, backZ + 0.02), Vector3.new(Tech.TUBE, wallTall, Tech.TUBE), tube)
	end
	local wx = 0.36 * hw
	local wy = FLOOR + 6.3
	local sw, sh = 4.6, 2.8
	Kit.block(m, at(wx, wy, backZ + 0.15), Vector3.new(sw + 0.7, sh + 0.7, 0.3), Tech.MetalDark, nil, Style.tiny({ CastShadow = true }))
	local backScreen = Tech.glow(m, at(wx, wy, backZ + 0.32), Vector3.new(sw, sh, 0.08), opts.Screen)
	backScreen.Name = "Screen"
	-- the shop's name on the screen (seen from the road behind)
	Tech.label(m, at(wx, wy, backZ + 0.4) * CFrame.Angles(0, math.pi, 0), opts.Sign, sw - 0.8, sh - 0.9, C.GlowText)
	for _, sy in { -1, 1 } do
		Tech.glow(m, at(wx, wy + sy * (sh / 2 + 0.2), backZ + 0.33), Vector3.new(sw + 0.4, 0.14, 0.08), neonLine)
		Tech.glow(m, at(wx + sy * (sw / 2 + 0.2), wy, backZ + 0.33), Vector3.new(0.14, sh + 0.54, 0.08), neonLine)
	end
	local ventY = FLOOR + bandY[2] * wallTall
	for _, f in { 0.26, 0.62 } do
		local x = -f * hw
		-- a vent grille: a light frame, a dark slot and a slat across it
		Kit.block(m, at(x, ventY, backZ + 0.2), Vector3.new(2.4, 1.5, 0.4), Tech.MetalLight, nil, Style.tiny({ CastShadow = true }))
		Kit.bit(m, at(x, ventY, backZ + 0.42), Vector3.new(2.0, 1.0, 0.06), Tech.MetalDeep)
		Kit.bit(m, at(x, ventY, backZ + 0.46), Vector3.new(2.0, 0.2, 0.06), Tech.Metal)
	end
	for _, dx in { 1.9, 2.7 } do
		Tech.disc(m, at(hw - dx, 5.4, backZ + 0.35).Position, 10.4, 0.5, Tech.MetalLight, nil, Style.tiny({ CastShadow = true }))
	end
	Kit.bit(m, at(hw - 2.3, FLOOR + 3.2, backZ + 0.3), Vector3.new(1.6, 0.4, 0.6), Tech.Band)

	-- inside: dark lining with a neon strip, the warm ceiling panel (one light)
	Kit.bit(m, at(0, FLOOR + 4.6, BACK_Z - 0.56), Vector3.new(W - 2.6, 8.6, 0.1), Tech.MetalDark)
	Tech.glow(m, at(0, FLOOR + 8.4, BACK_Z - 0.63), Vector3.new(W - 2.6, 0.2, 0.08), accent)
	local lamp = Tech.glow(m, at(0, WALL_TOP - 0.09, 2.4), Vector3.new(W - 11, 0.16, 2.6), C.LampAmber)
	lamp.Name = "CeilingLamp"
	Style.light(lamp, C.LampAmber, 20, 0.9)

	-- roof slab behind the header with a light back rim; thick neon roof-edge
	-- tubes in dark channels along its back and sides
	local roofZ0 = HEAD_Z1
	local roofD = (BACK_Z + 0.5) - roofZ0
	Style.block(
		m,
		at(0, (WALL_TOP + ROOF_TOP) / 2, roofZ0 + roofD / 2),
		Vector3.new(W - 0.2, ROOF_TOP - WALL_TOP, roofD),
		Style.vary(Tech.MetalDark, rng, 0.02),
		nil,
		Style.solid()
	)
	Kit.block(
		m,
		at(0, ROOF_TOP + 0.2, BACK_Z + 0.25),
		Vector3.new(W - 0.2, 0.4, 0.5),
		Tech.MetalLight,
		nil,
		Style.tiny({ CastShadow = true })
	)
	local edgeY = WALL_TOP + 0.4
	Tech.channel(m, at(0, edgeY, backZ + 0.24) * CFrame.Angles(0, math.pi, 0), W - 0.2, Tech.EDGE, tube)
	for _, side in { -1, 1 } do
		Tech.channel(
			m,
			at(side * (hw + 0.02), edgeY, roofZ0 + roofD / 2) * CFrame.Angles(0, -side * math.pi / 2, 0),
			roofD,
			Tech.EDGE,
			tube
		)
	end

	-- the pylons: foot with a light bevel lip, a light face shaft, orange
	-- band, blue neon edges and a bevelled corbel under the header's
	-- overhang; the end pylons carry an inset display-wall screen, the slim
	-- mid pylons (wide module) stay plain
	local pz = (PYLON_Z0 + PYLON_Z1) / 2
	local pd = PYLON_Z1 - PYLON_Z0
	local pylonScreens: { CFrame } = {}
	for _, side in { 1, -1 } do
		for _, py in pylons do
			local x = side * py.X
			local pw = py.W
			Style.block(m, at(x, 0.4, pz), Vector3.new(pw + 0.4, 0.8, pd + 0.4), Tech.MetalDark, nil, Style.solid())
			-- (perf pass 1) the foot lip and the orange band only on the end
			-- pylons: a mid pylon's lower front hides behind its showcase's stand
			local lip, lipSize = at(x, 0.95, PYLON_Z0 - 0.1), Vector3.new(pw + 0.4, 0.3, 0.2)
			if py.Outer then
				Tech.bevel(m, lip, lipSize, Tech.MetalLight)
			else
				Tech.leaveOut(m, lip, lipSize, "PylonLip")
			end
			Style.block(m, at(x, HEAD_Y0 / 2, pz), Vector3.new(pw, HEAD_Y0, pd), Style.vary(FACE, rng, 0.02), nil, Style.solid())
			local band, bandSize = at(x, 2.5, PYLON_Z0 - 0.06), Vector3.new(pw + 0.04, 0.7, 0.12)
			if py.Outer then
				Kit.bit(m, band, bandSize, Tech.Band)
			else
				Tech.leaveOut(m, band, bandSize, "PylonBand")
			end
			if py.Outer then
				local sc = at(x, 6.6, PYLON_Z0 - 0.1)
				Kit.bit(m, sc, Vector3.new(pw - 0.65, 4.8, 0.2), Tech.MetalDeep)
				local screen = Tech.glow(m, sc * CFrame.new(0, 0, -0.08), Vector3.new(pw - 1.15, 4.2, 0.08), opts.Screen)
				screen.Name = "Screen"
				table.insert(pylonScreens, sc * CFrame.new(0, 0, -0.14))
			end
			for _, ex in { -1, 1 } do
				Tech.glow(m, at(x + ex * (pw / 2 - 0.02), 5.5, PYLON_Z0 - 0.02), Vector3.new(0.34, 8.8, 0.34), tube)
			end
			Tech.underBevel(m, at(x, HEAD_Y0 - 0.7, PYLON_Z0 - 0.7), Vector3.new(pw, 1.4, 1.4), Tech.MetalLight)
			if py.Outer then
				-- (round 3) the armored corner: a 45 degree chamfer block on the
				-- pylon's outer front edge with a vertical neon strip on its face
				local corner = at(side * (hw - 0.82), HEAD_Y0 / 2, PYLON_Z0 + 0.5) * CFrame.Angles(0, -side * math.pi / 4, 0)
				Style.block(m, corner, Vector3.new(1.5, HEAD_Y0, 1.5), Style.vary(header, rng, 0.02), nil, Style.decor())
				Tech.glow(m, corner * CFrame.new(0, 0.3, -0.78), Vector3.new(0.3, HEAD_Y0 - 2.4, 0.08), tube).Name = "CornerGlow"
			end
		end
	end

	-- the header frame: a massive block with chamfered upper corners, the sign
	-- box set into its face, a thick neon tube in a dark channel along its
	-- outline, light top and bottom lips, a finished back face
	local hd = HEAD_Z1 - HEAD_Z0
	local hz = (HEAD_Z0 + HEAD_Z1) / 2
	local mainTop = HEAD_Y1 - HEAD_CHAMFER
	local topW = W - 2 * HEAD_CHAMFER
	Style.block(m, at(0, (HEAD_Y0 + mainTop) / 2, hz), Vector3.new(W, mainTop - HEAD_Y0, hd), header, nil, Style.decor())
	Style.block(m, at(0, (mainTop + HEAD_Y1) / 2, hz), Vector3.new(topW, HEAD_CHAMFER, hd), header, nil, Style.decor())
	local hcf = at(0, 0, hz)
	for _, side in { -1, 1 } do
		-- the 45 degree chamfer: a right triangle with its vertical leg at the top block's end
		Tech.flatTri(m, hcf, side * topW / 2, mainTop, side, HEAD_CHAMFER, HEAD_CHAMFER, hd, header, nil, Style.decor())
	end
	Kit.bit(m, at(0, HEAD_Y1 + 0.15, hz), Vector3.new(topW + 0.2, 0.3, hd + 0.3), HEADER_LIP)
	Kit.block(m, at(0, HEAD_Y0 + 0.25, HEAD_Z0 - 0.15), Vector3.new(W + 0.2, 0.5, 0.5), HEADER_LIP, nil, Style.tiny({ CastShadow = true }))
	-- a light bevel lip under the header's front edge, between the end pylons
	Tech.underBevel(m, at(0, HEAD_Y0 - 0.2, HEAD_Z0 + 0.3), Vector3.new(lintelW, 0.4, 0.6), Tech.MetalLight)
	-- (round 3) an angled cornice overhanging the header's top front edge,
	-- a neon line along its nose
	Tech.underBevel(m, at(0, HEAD_Y1 - 0.45, HEAD_Z0 - 0.35), Vector3.new(topW, 0.9, 0.7), header)
	Tech.glow(m, at(0, HEAD_Y1 - 0.08, HEAD_Z0 - 0.66), Vector3.new(topW, 0.14, 0.1), tube).Name = "CorniceGlow"
	-- thick neon tube along the outline (sides, chamfers, top), each line in
	-- a dark MetalDeep channel a little wider than the tube
	local face = at(0, 0, HEAD_Z0)
	local t = Tech.TUBE
	local outline = {
		{ hw - t / 2, HEAD_Y0 + 0.6, hw - t / 2, mainTop },
		{ hw - t / 2, mainTop, topW / 2, HEAD_Y1 - t / 2 },
		{ topW / 2, HEAD_Y1 - t / 2, -topW / 2, HEAD_Y1 - t / 2 },
		{ -topW / 2, HEAD_Y1 - t / 2, -hw + t / 2, mainTop },
		{ -hw + t / 2, mainTop, -hw + t / 2, HEAD_Y0 + 0.6 },
	}
	for _, q in outline do
		Tech.line(m, face, q[1], q[2], q[3], q[4], t + 0.3, -0.06, Tech.MetalDeep, Enum.Material.SmoothPlastic, 0.12)
		Tech.line(m, face, q[1], q[2], q[3], q[4], t, -0.16, tube, nil, 0.2)
	end
	-- the back face (seen over the roof from behind): a light panel with a band
	Kit.bit(m, at(0, (WALL_TOP + ROOF_TOP) / 2 + 3.2, HEAD_Z1 + 0.07), Vector3.new(W - 4.4, 4.2, 0.14), Tech.MetalLight)
	Kit.bit(m, at(0, ROOF_TOP + 2.0, HEAD_Z1 + 0.16), Vector3.new(W - 4.4, 0.5, 0.08), Tech.Band)
	-- the porch light strip under the header
	local under = Tech.glow(m, at(0, HEAD_Y0 - 0.08, HEAD_Z0 + 0.85), Vector3.new(W - 6, 0.16, 0.3), accent)
	if not opts.SignLight then
		Style.light(under, C.LampAmber, 16, 0.9)
	end

	-- the big glowing sign box set into the header face (it grows with a
	-- wider module so the header never looks empty)
	local signW: number = opts.SignWidth + math.max(0, hw - 10) * 0.8
	-- (round 3: a protruding sign casing 1.25 deep, a deep neon frame with a
	-- bright core strip: the frame reads as a glowing tube)
	local _, iconAt = Tech.sign(m, at(0, SIGN_Y, HEAD_Z0 - 0.55), opts.Sign, signW, SIGN_H, {
		Icon = opts.IconWidth or 4.6,
		IconLeft = opts.IconLeft,
		CasingDepth = 1.25,
		Studs = false,
		Margin = 0.35,
		Lip = 0.3,
		Light = if opts.SignLight == true then 16 else nil,
		Frame = opts.SignFrame or tube,
		Core = opts.SignCore,
		LightColor = C.GlowText,
		LightDist = 0.4, -- the footprint ends 1 stud in front of the header
	})

	-- roof clutter behind the header: a dark roof box, two vent blocks, an
	-- orange container-tall and a gunmetal one (depth over the roof line)
	Kit.block(m, at(0.08 * hw, ROOF_TOP + 1.0, 1.4), Vector3.new(0.34 * W, 2.0, 3.2), Tech.MetalDeep, nil, Style.decor())
	for _, f in { -0.3, 0.42 } do
		Kit.block(m, at(f * hw, ROOF_TOP + 0.45, 5.0), Vector3.new(1.6, 0.9, 1.4), Tech.MetalDark, nil, Style.tiny({ CastShadow = true }))
	end
	Tech.container(m, at(-0.66 * hw, ROOF_TOP, 3.6), 2.8, 1.7, Tech.Band)
	Tech.container(m, at(0.56 * hw, ROOF_TOP, 3.9), 2.4, 1.5, Tech.Metal)

	-- the counter in the door (table-display style, the hook is its top)
	Style.block(m, at(0, FLOOR + 1.55, COUNTER_Z), Vector3.new(6.4, 3.1, 1.4), Tech.Metal, nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.2, COUNTER_Z), Vector3.new(6.7, 0.4, 1.7), Tech.MetalDark)
	for _, x in { -2.6, 2.6 } do
		Kit.bit(m, at(x, FLOOR + 1.6, COUNTER_Z - 0.72), Vector3.new(0.4, 2.4, 0.08), frame)
	end
	Tech.glow(m, at(0, FLOOR + 1.6, COUNTER_Z - 0.73), Vector3.new(3.4, 0.24, 0.08), neonLine)
	local counter =
		Style.block(m, at(0, COUNTER_TOP - 0.15, COUNTER_Z - 0.05), Vector3.new(6.9, 0.3, 1.9), Tech.MetalLight, nil, Style.solid())
	Tech.glow(m, at(0, COUNTER_TOP - 0.17, COUNTER_Z - 1.04), Vector3.new(6.9, 0.2, 0.1), neonLine)

	-- shelves on the back wall with neon edges
	for _, y in SHELVES do
		Kit.bit(m, at(0, y - 0.15, SHELF_Z), Vector3.new(W - 3.2, 0.3, 1.1), Tech.MetalLight)
		Tech.glow(m, at(0, y - 0.2, SHELF_Z - 0.58), Vector3.new(W - 3.2, 0.12, 0.08), neonLine)
	end

	-- the open lit bays: a glass case on a plinth with a neon front edge, a
	-- warm floor glow, a small neon plinth for one big item, a light strip
	-- under the case lid, and a glowing back panel behind the case
	local windows: { CFrame } = {}
	local inner: { CFrame }, outer: { CFrame } = {}, {}
	local plinthColor: Color3 = opts.Plinth or neonLine
	local caseTop = FLOOR + BAY_PLINTH + BAY_CASE
	-- One bay's case furniture (`x` = center, `w` = the bay width); on a
	-- two-bay side once for both bays together (x, w over both: the part
	-- between them hides behind the wall between the windows), except the
	-- glass case: one per window (`glassAt` = their centers, `glassW` = a
	-- window bay's width), so each window's case has its own glass ends.
	local function bayCase(x: number, w: number, glassAt: { number }, glassW: number)
		local cw = w - 1.0 -- plinth width
		-- opaque dark glass behind the case (the lit item is the light)
		Kit.block(m, at(x, FLOOR + 4.15, BAY_BACK_Z), Vector3.new(w - 0.7, 4.9, 0.1), DARK_GLASS, nil, Style.tiny({ Reflectance = 0.18 })).Name =
			"BayGlass"
		Kit.bit(m, at(x, FLOOR + BAY_PLINTH / 2, BAY_Z), Vector3.new(cw, BAY_PLINTH, BAY_D), Tech.MetalDark)
		Tech.glow(m, at(x, FLOOR + BAY_PLINTH - 0.12, BAY_Z - BAY_D / 2 - 0.03), Vector3.new(cw, 0.14, 0.08), neonLine)
		Tech.glow(m, at(x, FLOOR + BAY_PLINTH + 0.03, BAY_Z), Vector3.new(cw - 0.4, 0.06, BAY_D - 0.4), Tech.CaseLight)
		for _, gx in glassAt do
			local glass = Kit.block(
				m,
				at(gx, FLOOR + BAY_PLINTH + BAY_CASE / 2, BAY_Z),
				Vector3.new(glassW - 1.2, BAY_CASE, BAY_D - 0.2),
				Tech.CaseGlass,
				Kit.GLASS,
				-- clearer than the porch cases: the bay's frame already reads as
				-- a case, the item keeps its saturated color
				Style.tiny({ Transparency = 0.84 })
			)
			glass.Name = "BayCase"
		end
		Kit.bit(m, at(x, caseTop + 0.12, BAY_Z), Vector3.new(cw, 0.24, BAY_D), Tech.MetalLight)
		Tech.glow(m, at(x, caseTop - 0.08, BAY_Z - BAY_D / 2 + 0.4), Vector3.new(cw - 0.6, 0.12, 0.3), Tech.CaseLight)
	end
	for _, side in { 1, -1 } do
		if twoBays then
			local b1, b2 = windowBays[1], windowBays[2]
			local x0, x1 = b1.X - b1.W / 2, b2.X + b2.W / 2
			bayCase(side * (x0 + x1) / 2, x1 - x0, { side * b1.X, side * b2.X }, b1.W)
		else
			for _, bay in windowBays do
				bayCase(side * bay.X, bay.W, { side * bay.X }, bay.W)
			end
		end
	end
	for bi, bay in windowBays do
		for _, side in { 1, -1 } do
			local x = side * bay.X
			local cw = bay.W - 1.0
			-- the small neon plinth under each bay's item
			Tech.glow(m, at(x, FLOOR + BAY_PLINTH + 0.16, BAY_Z), Vector3.new(math.min(1.9, cw - 1.0), 0.2, 1.3), plinthColor).Name =
				"BayPlinth"
			table.insert(if bi == 1 then inner else outer, at(x, FLOOR + BAY_PLINTH + 0.26, BAY_Z))
		end
	end
	for _, w in inner do
		table.insert(windows, w)
	end
	for _, w in outer do
		table.insert(windows, w)
	end

	-- cyan glass showcases on the porch, in front of the pylons (end pylons
	-- first): a glowing back panel and a small neon plinth light the goods
	local cases: { CFrame } = {}
	for pass = 1, 2 do
		for _, py in pylons do
			if py.Outer == (pass == 1) then
				local x = if py.Outer then hw - CASE_W / 2 else py.X
				for _, side in { 1, -1 } do
					table.insert(
						cases,
						Tech.showcase(m, at(side * x, FLOOR, CASE_Z), CASE_W, CASE_D, CASE_H, {
							Case = CASE_GLASS,
							Stripe = frame,
							Plinth = plinthColor,
							Backlight = opts.CaseBack,
						})
					)
				end
			end
		end
	end

	-- the display screen on the side wall that faces the spawn
	local s: number = opts.ScreenSide
	local screenAt = at(s * (sideX + 0.65), FLOOR + 5.4, 2.2) * CFrame.Angles(0, -s * math.pi / 2, 0)
	Tech.screen(m, screenAt, 3.6, 4.2, opts.Screen)

	local firstBay = windowBays[1]
	return {
		Counter = counter,
		Interior = at(0, FLOOR, 2.8),
		Cases = cases,
		Windows = windows,
		ItemScale = math.min(1.65, (firstBay.W - 1.2) * 0.5),
		Shelves = SHELVES,
		ScreenAt = screenAt,
		PylonScreens = pylonScreens,
		IconAt = iconAt,
		HalfWidth = hw,
	}
end

---------------------------------------------------------------- neon showcase items

-- (round 3) one bright neon item per porch showcase: a crystal, a pickaxe
-- head or a coin, chosen by the case index. `base` = the display floor.
local SHOP_ITEM = { rgb(60, 220, 255), rgb(255, 180, 40), rgb(255, 196, 64) }
local UPG_ITEM = { rgb(255, 90, 220), rgb(170, 90, 255), rgb(255, 196, 64) }
local function neonItem(parent: Instance, base: CFrame, index: number, colors: { Color3 })
	local kind = (index - 1) % 3 + 1
	if kind == 1 then
		-- a glowing crystal with two small side shards
		Style.crystal(parent, base * CFrame.new(0, 0.05, 0.1), 2.0, 0.75, colors[1], nil, 0.15)
		Style.crystal(parent, base * CFrame.new(0.55, 0.05, 0.2) * CFrame.Angles(0, 0, -0.35), 1.1, 0.42, colors[1], nil, 0.15)
	elseif kind == 2 then
		-- a pickaxe head: a curved glowing head on a short dark haft
		Kit.bit(parent, base * CFrame.new(0, 0.7, 0.1), Vector3.new(0.24, 1.4, 0.24), C.WoodDark)
		for _, side in { -1, 1 } do
			Kit.glow(
				parent,
				base * CFrame.new(side * 0.55, 1.35, 0.1) * CFrame.Angles(0, 0, side * 0.35),
				Vector3.new(1.0, 0.3, 0.3),
				colors[2]
			)
		end
	else
		-- a big gold coin standing on edge, a light star on its face
		Tech.faceDisc(parent, base * CFrame.new(0, 0.85, 0.05), 0.24, 1.5, colors[3], Kit.NEON)
		Kit.bit(
			parent,
			base * CFrame.new(0, 0.85, -0.1) * CFrame.Angles(0, 0, math.pi / 4),
			Vector3.new(0.5, 0.5, 0.06),
			rgb(255, 236, 150)
		)
	end
end

---------------------------------------------------------------- gear (SHOP)

-- Miner's helmet with a big head lamp and a white lens. `base` = bottom
-- center, s = scale, lit = a glowing top stripe (display pieces: the
-- helmet keeps its color in the shade).
local function helmet(parent: Instance, base: CFrame, color: Color3, s: number?, lit: boolean?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	Kit.bit(parent, at(0, 0.4, 0.05), Vector3.new(1.0, 0.66, 1.0) * k, color)
	if lit then
		Kit.glow(parent, at(0, 0.8, 0.05), Vector3.new(0.66, 0.2, 0.66) * k, color)
	else
		Kit.bit(parent, at(0, 0.8, 0.05), Vector3.new(0.66, 0.2, 0.66) * k, color:Lerp(C.FlowerWhite, 0.2))
	end
	Kit.bit(parent, at(0, 0.1, -0.04), Vector3.new(1.24, 0.16, 1.3) * k, color:Lerp(Kit.Dark, 0.3))
	Kit.bit(parent, at(0, 0.44, -0.5), Vector3.new(0.56, 0.5, 0.16) * k, C.Iron)
	Tech.faceDisc(parent, at(0, 0.44, -0.6), 0.08 * k, 0.24 * k, LENS, Kit.NEON)
end

local function boots(parent: Instance, base: CFrame, color: Color3, s: number?)
	local k = s or 1.5
	for _, x in { -0.34, 0.34 } do
		Kit.bit(parent, base * CFrame.new(x * k, 0.6 * k, 0.12 * k), Vector3.new(0.48, 0.9, 0.52) * k, color)
		Kit.bit(parent, base * CFrame.new(x * k, 0.16 * k, -0.12 * k), Vector3.new(0.54, 0.32, 1.0) * k, color:Lerp(Kit.Dark, 0.45))
	end
end

local function backpack(parent: Instance, base: CFrame, color: Color3, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	Kit.bit(parent, at(0, 0.6, 0), Vector3.new(1.0, 1.2, 0.62) * k, color)
	Kit.bit(parent, at(0, 1.1, -0.04), Vector3.new(1.06, 0.36, 0.7) * k, color:Lerp(Kit.Dark, 0.35))
	Kit.glow(parent, at(0, 0.42, -0.34), Vector3.new(0.56, 0.42, 0.12) * k, Tech.GoldGlow)
	for _, x in { -0.36, 0.36 } do
		Kit.bit(parent, at(x, 0.62, -0.33), Vector3.new(0.13, 1.1, 0.1) * k, C.WoodDark)
	end
end

local function glove(parent: Instance, base: CFrame, color: Color3, s: number?)
	local k = s or 1.5
	Kit.bit(parent, base * CFrame.new(0, 0.5 * k, 0), Vector3.new(0.62, 0.72, 0.34) * k, color)
	Kit.bit(parent, base * CFrame.new(0.42 * k, 0.48 * k, 0), Vector3.new(0.24, 0.38, 0.3) * k, color)
	Kit.bit(parent, base * CFrame.new(0, 0.12 * k, 0), Vector3.new(0.74, 0.24, 0.42) * k, color:Lerp(Kit.Dark, 0.4))
end

-- U-magnet: red legs and base, white tips.
local function magnet(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	for _, x in { -0.36, 0.36 } do
		Kit.bit(parent, base * CFrame.new(x * k, 0.6 * k, 0), Vector3.new(0.32, 0.72, 0.36) * k, MAGNET)
		Kit.bit(parent, base * CFrame.new(x * k, 1.08 * k, 0), Vector3.new(0.34, 0.26, 0.38) * k, C.FlowerWhite)
	end
	Kit.bit(parent, base * CFrame.new(0, 0.16 * k, 0), Vector3.new(1.04, 0.32, 0.36) * k, MAGNET)
end

local function gearShop(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("Shop")
	local m = Style.model(piece.Id, parent)
	local h = house(m, cf, piece.Size.X / 2, rng, {
		Sign = "SHOP",
		SignWidth = 14.4,
		IconLeft = false,
		Frame = Tech.MetalDeep,
		FrameNeon = Tech.Neon,
		Accent = Tech.Warm,
		-- the sign faces away from the sun: a floodlight on Tobin's stall in
		-- front (Fronts) lights its letters evenly (white, not lavender grey)
		SignLight = "Flood",
		ScreenSide = 1,
		Screen = rgb(22, 66, 205),
		BayGlow = rgb(16, 48, 150),
		Plinth = C.GlowEdgeDeep,
		CaseBack = rgb(40, 110, 255),
		SignFrame = C.GlowEdgeDeep,
		SignCore = C.GlowCore,
	})
	h.Counter.Name = "ShopCounter"
	Kit.tag(h.Counter, "ShopCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the shopping cart on the header sign (viewer's right)
	local iconAt = h.IconAt
	if iconAt then
		Tech.cartIcon(m, iconAt, 4.0, Tech.Neon)
	end

	-- one big saturated item per lit bay and per porch showcase (about 70%
	-- of the case): a yellow helmet with a white lamp lens and red boots in
	-- the bays, a green backpack and a red/white magnet on the porch
	local k = h.ItemScale
	local top = COUNTER_TOP
	helmet(m, at(2.0, top, COUNTER_Z - 0.1), C.LeafYellow, 1.2)
	magnet(m, at(-2.2, top, COUNTER_Z - 0.1), 1.2)
	helmet(m, h.Windows[1] * CFrame.new(0, 0, 0.05), HELMET, k, true)
	boots(m, h.Windows[2] * CFrame.new(0, 0, 0.1), BOOTS, k * 1.05)
	-- (round 3) one bright neon item per porch showcase: a crystal, a
	-- pickaxe head, a coin
	for i, c in h.Cases do
		neonItem(m, c, i, SHOP_ITEM)
	end
	if h.Windows[3] then
		backpack(m, h.Windows[3], PACK, k)
		boots(m, h.Windows[4] * CFrame.new(0, 0, 0.1), BOOTS, k)
	end
	-- shelves: helmets, boots, packs, a magnet
	local low, high = h.Shelves[1], h.Shelves[2]
	helmet(m, at(5.6, low, SHELF_Z), C.LeafYellow, 1.2)
	helmet(m, at(3.4, low, SHELF_Z), C.IronLight, 1.2)
	boots(m, at(-3.6, low, SHELF_Z), C.Iron, 1.2)
	backpack(m, at(4.6, high, SHELF_Z), C.Wood, 1.2)
	glove(m, at(-3.0, high, SHELF_Z), C.Copper, 1.2)
	magnet(m, at(-5.4, high, SHELF_Z), 1.2)

	-- the side screen shows a whole gold coin; the end pylon screens show a
	-- coin (the pylon that faces the spawn) and a boot icon (deep glyph
	-- colors: no white blobs)
	local sc = h.ScreenAt * CFrame.new(0, 0, -0.1)
	Tech.faceDisc(m, sc, 0.08, 2.4, C.Gold)
	Tech.faceDisc(m, sc * CFrame.new(0, 0, -0.06), 0.06, 1.5, C.Brass)
	Kit.bit(m, sc * CFrame.new(0, 0, -0.11), Vector3.new(0.3, 1.0, 0.04), C.Gold)
	for i, ps in h.PylonScreens do
		if i == 1 then
			-- a whole gold coin (a helmet glyph read as an orange "L" from afar)
			Tech.faceDisc(m, ps * CFrame.new(0, 0.45, -0.02), 0.06, 0.95, C.Gold)
			Tech.faceDisc(m, ps * CFrame.new(0, 0.45, -0.06), 0.05, 0.6, C.Brass)
		else
			-- (round 3: a gold pickaxe, the old boot glyph read as a lone orange "L")
			Style.icon(m, ps * CFrame.new(0, 0.35, -0.04), "Pickaxe", 1.5, Tech.GoldGlow, Kit.NEON)
		end
		Kit.glow(m, ps * CFrame.new(0, -1.15, 0), Vector3.new(0.8, 0.8, 0.04), GLYPH_BLUE)
	end

	-- the shopkeeper golem behind the counter (ShopkeeperController), in the
	-- door's middle, its big head clear of the counter, standing on a step
	-- the counter hides (1.2 up: its head shows over the goods on the counter)
	ShopkeeperConfig.mark(h.Counter, h.Interior * CFrame.new(0, 1.2, 1.1), "Gear")
end

---------------------------------------------------------------- machines (UPGRADES)

-- Little Kenney-style machine models for the Tech shop in saturated
-- colors that read at plaza distance. `base` = bottom center, s = scale.
local function miniConveyor(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	Kit.bit(parent, at(0, 0.2, 0), Vector3.new(1.8, 0.4, 0.9) * k, C.IronLight)
	Kit.bit(parent, at(0, 0.44, 0), Vector3.new(1.8, 0.08, 0.7) * k, Kit.Dark)
	for _, z in { -0.48, 0.48 } do
		Kit.bit(parent, at(0, 0.5, z), Vector3.new(1.9, 0.2, 0.14) * k, C.Hazard)
	end
	Kit.glow(parent, at(0.3, 0.7, 0), Vector3.new(0.45, 0.45, 0.45) * k, C.Molten)
end

-- Furnace: a light steel body on an orange base, a big molten mouth, an
-- orange chimney.
local function miniFurnace(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	Kit.bit(parent, at(0, 0.08, 0), Vector3.new(1.3, 0.16, 1.1) * k, C.Hazard)
	Kit.bit(parent, at(0, 0.62, 0), Vector3.new(1.1, 0.92, 0.95) * k, C.IronLight)
	Kit.bit(parent, at(0, 0.52, -0.46), Vector3.new(0.8, 0.62, 0.08) * k, Kit.Dark)
	Kit.glow(parent, at(0, 0.5, -0.5), Vector3.new(0.64, 0.46, 0.06) * k, C.Molten)
	Kit.bit(parent, at(0.28, 1.4, 0.18), Vector3.new(0.3, 0.7, 0.3) * k, C.LeafOrange)
	Kit.bit(parent, at(0.28, 1.78, 0.18), Vector3.new(0.42, 0.12, 0.42) * k, C.Iron)
end

-- Tank: a copper drum with a brass band, a cap and a green gauge.
local function miniTank(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local p = base.Position
	local up = base.UpVector
	Kit.disc(parent, p + up * 0.62 * k, 1.24 * k, 0.9 * k, C.Copper, nil, Style.tiny())
	Kit.disc(parent, p + up * 0.85 * k, 0.16 * k, 1.0 * k, C.Gold, nil, Style.tiny())
	Kit.disc(parent, p + up * 1.32 * k, 0.16 * k, 0.56 * k, C.IronLight, nil, Style.tiny())
	Kit.glow(parent, base * CFrame.new(0, 0.5 * k, -0.47 * k), Vector3.new(0.32, 0.32, 0.06) * k, C.LeafGreen)
end

-- Cleaner arch: two orange legs, a beam with a brass nozzle, a cyan water
-- jet and a green lamp.
local function miniCleaner(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	for _, x in { -0.6, 0.6 } do
		Kit.bit(parent, at(x, 0.6, 0), Vector3.new(0.28, 1.2, 0.7) * k, C.LeafOrange)
	end
	Kit.bit(parent, at(0, 1.28, 0), Vector3.new(1.5, 0.28, 0.75) * k, C.IronLight)
	Kit.bit(parent, at(0, 0.98, 0), Vector3.new(0.5, 0.36, 0.36) * k, C.Gold)
	Kit.glow(parent, at(0, 0.5, 0), Vector3.new(0.22, 0.6, 0.22) * k, C.CrystalCyan)
	Kit.glow(parent, at(0.5, 1.56, 0), Vector3.new(0.22, 0.3, 0.22) * k, C.LeafGreen)
	Kit.bit(parent, at(0, 0.12, 0), Vector3.new(1.5, 0.24, 0.75) * k, Kit.Dark)
end

local function techShop(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("Upgrades")
	local m = Style.model(piece.Id, parent)
	local h = house(m, cf, piece.Size.X / 2, rng, {
		Sign = "UPGRADES",
		SignWidth = 15.6,
		IconWidth = 4.2,
		IconLeft = true,
		Frame = Tech.MetalDeep,
		FrameNeon = UPG_NEON,
		Accent = UPG_NEON,
		Tube = UPG_TUBE,
		Neon = UPG_NEON,
		Header = rgb(30, 26, 44),
		ScreenSide = -1,
		Screen = rgb(70, 50, 210),
		BayGlow = rgb(64, 28, 160),
		Plinth = UPG_PINK,
		CaseBack = rgb(120, 80, 255),
		SignCore = rgb(255, 200, 245),
	})
	h.Counter.Name = "UpgradeCounter"
	Kit.tag(h.Counter, "UpgradeCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the gear on the header sign (viewer's left): a crisp purple outline
	-- with the cart's line weight (a filled neon gear blooms to a starburst)
	local iconAt = h.IconAt
	if iconAt then
		Tech.gearIcon(m, iconAt, 3.6, GEAR_PURPLE)
	end
	-- (round 3) UPGRADES' own crest: two exhaust stacks on the roof behind
	-- the header, a band, a light rim, a violet neon ring and smoke
	for _, side in { -1, 1 } do
		local sx = side * (h.HalfWidth - 3.2)
		local stackH = 7.8
		local base = at(sx, ROOF_TOP, -1.7)
		Tech.disc(m, (base * CFrame.new(0, stackH / 2, 0)).Position, stackH, 1.5, Tech.MetalDark, nil, Style.decor())
		Tech.disc(m, (base * CFrame.new(0, stackH * 0.35, 0)).Position, 0.6, 1.7, Tech.Band)
		Tech.disc(m, (base * CFrame.new(0, stackH - 0.9, 0)).Position, 0.3, 1.65, UPG_TUBE, Kit.NEON).Name = "StackGlow"
		local rim = Tech.disc(m, (base * CFrame.new(0, stackH + 0.15, 0)).Position, 0.3, 1.8, Tech.MetalLight)
		Style.emitter(rim, "Smoke", nil, 2)
	end

	-- machines for sale: one big machine per bay and showcase, small ones
	-- on the counter and the shelves
	local k = h.ItemScale
	local top = COUNTER_TOP
	miniConveyor(m, at(1.6, top, COUNTER_Z - 0.1), 1.1)
	miniTank(m, at(-1.8, top, COUNTER_Z - 0.1), 1.1)
	miniFurnace(m, h.Windows[1] * CFrame.new(0, 0, 0.05), k * 0.72)
	miniCleaner(m, h.Windows[2] * CFrame.new(0, 0, 0.05), k * 0.78)
	-- (round 3) one bright neon item per porch showcase on a pink plate
	for i, c in h.Cases do
		neonItem(m, c, i, UPG_ITEM)
	end
	if h.Windows[3] then
		miniTank(m, h.Windows[3], k * 0.9)
		miniConveyor(m, h.Windows[4] * CFrame.new(0, 0, 0.05), k * 0.8)
	end
	local low, high = h.Shelves[1], h.Shelves[2]
	miniFurnace(m, at(5.4, low, SHELF_Z), 1.2)
	miniConveyor(m, at(-3.4, low, SHELF_Z), 1.2)
	miniTank(m, at(3.0, high, SHELF_Z), 1.2)
	miniCleaner(m, at(-4.4, high, SHELF_Z), 1.2)

	-- the side screen (toward the spawn) shows a gear outline, the pylon
	-- screens a furnace mouth and a tank gauge
	Style.icon(m, h.ScreenAt * CFrame.new(0, 0, -0.12), "Gear", 3.0, GLYPH_BLUE, Kit.NEON)
	for i, ps in h.PylonScreens do
		Kit.glow(m, ps * CFrame.new(0, 0.9, 0), Vector3.new(0.9, 0.6, 0.04), if i == 1 then C.Molten else C.LeafGreen)
		Kit.glow(m, ps * CFrame.new(0, -1.0, 0), Vector3.new(0.8, 0.9, 0.04), GEAR_PURPLE)
	end

	-- the shopkeeper golem behind the counter (ShopkeeperController), on a hidden step
	ShopkeeperConfig.mark(h.Counter, h.Interior * CFrame.new(0, 1.0, 1.0), "Tech")
end

function Stalls.build(parent: Instance, rng: Rng.Rng)
	gearShop(parent, rng)
	techShop(parent, rng)
end

return Stalls
