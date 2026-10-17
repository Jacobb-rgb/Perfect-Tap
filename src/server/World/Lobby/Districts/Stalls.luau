--[[
	SHOP (the Gear shop) and UPGRADES (the Tech shop): the concept v2 sci-fi
	shop modules either side of the Great Forge (docs/art/lobby_concept_v2.webp).
	Both share one module built from Kenney Space Station shapes (Tech kit):
	  - a massive bevelled dark gunmetal header frame across the whole front
	    whose face is the big glowing sign box (SHOP + a shopping cart /
	    UPGRADES + a gear outline), chamfered upper corners, a thick blue
	    neon tube along its outline, a light top lip and an orange band
	  - chunky end pylons carrying the header (bevelled corbels under its
	    overhang), each with an inset display-wall screen and blue neon edges
	  - a facade of display bays (wall-window-banners: dark backdrops in a
	    thin neon frame, a deep blue glow at their foot, the goods on a warm
	    glow plate under a light strip) either side of a wall-door-wide frame
	  - cyan glass showcases (table-display: four neon corner posts, a lit
	    floor plate) in front of the pylons, a display-wall screen on the
	    side that faces the spawn, shelves of goods inside, the counter in
	    the door = the hook part (ShopCounter / UpgradeCounter)
	  - a finished back: two wall-banner panels (the orange band at two
	    heights), neon corner tubes, a framed glass window with a warm glow
	    behind it, vents, pipes, roof containers with a pipe loop
	The module fills its LobbyLayout footprint: a 20 wide piece has one
	display bay per side; from 27 studs wide every side gets a second bay:
	a slim mid pylon with its own showcase and a second window.
	UPGRADES is the sister module: purple frames and purple/blue neon
	accents, machine models in the showcases and on the shelves.

	Local frame (LobbyLayout piece, 20 x 20 x 14): front = -Z (toward the
	plaza), seen from the front local +X is on the viewer's left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
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
local HEADER = rgb(70, 76, 98)
local HEADER_LIP = rgb(150, 158, 182)
local SIGN_Y, SIGN_H = 13.55, 4.6
local COUNTER_Z = 0.9
local COUNTER_TOP = FLOOR + 3.3
local SHELF_Z = 5.05
local SHELVES = { FLOOR + 2.8, FLOOR + 5.2 }
local CASE_Z = -5.85 -- porch showcases (in front of the pylons)
local TWO_BAYS = 13.5 -- half width from which every side gets a second display bay
local DEEP_GLOW = rgb(14, 40, 150) -- the deep blue glow at the foot of the window backdrops
-- screen glyph colors: deep enough to stay colored under bloom
local GLYPH_WARM = rgb(255, 170, 40)
local GLYPH_BLUE = rgb(20, 150, 255)
local GEAR_PURPLE = rgb(120, 50, 255)

export type House = {
	Counter: Part,
	Interior: CFrame, -- floor point behind the counter (keeper spot)
	-- display floors of the porch showcases: +X outer, -X outer, then (two
	-- bays) +X mid, -X mid
	Cases: { CFrame },
	-- display floors behind the windows: +X inner, -X inner, then (two
	-- bays) +X outer, -X outer
	Windows: { CFrame },
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
	  SignLight                   the second light goes to the sign (it faces
	                              away from the sun), else to the porch strip
	  ScreenSide                  +1 / -1: the side wall that faces the spawn
	  Screen                      screen color
	  BackGlow                    warm glow behind the back window
]]
local function house(m: Model, cf: CFrame, hw: number, rng: Rng.Rng, opts: Opts): House
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local frame: Color3 = opts.Frame
	local accent: Color3 = opts.Accent
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
		Tech.glow(m, at(side * (hw - 0.08), FLOOR - 0.15, -0.1), Vector3.new(0.12, 0.2, 13.4), Tech.Neon)
	end

	-- facade: the display bays' window walls and the wide door frame, a lintel over them
	for _, side in { -1, 1 } do
		for _, bay in windowBays do
			Tech.windowWall(m, at(side * bay.X, FLOOR, FACADE_Z), bay.W, DOOR_H, 1.0, {
				WindowWidth = bay.W - 1.0,
				WindowBottom = 1.5,
				WindowTop = 6.4,
				Frame = frame,
			})
		end
	end
	Tech.doorFrame(m, at(0, FLOOR, FACADE_Z), 2 * DOOR_HALF, DOOR_H, 1.0, {
		OpeningWidth = DOOR_W,
		OpeningHeight = DOOR_H,
		Frame = frame,
		Neon = Tech.Tube,
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
		Style.vary(Tech.Metal, rng, 0.02),
		nil,
		Style.solid()
	)
	Kit.bit(m, at(0, FLOOR + DOOR_H + lintelH * 0.6, FACADE_Z - 0.56), Vector3.new(lintelW, 0.6, 0.12), Tech.Band)
	Tech.glow(m, at(0, FLOOR + DOOR_H + 0.22, FACADE_Z - 0.58), Vector3.new(lintelW, 0.3, 0.14), Tech.Tube)

	-- side wall-banners (the roof covers their tops)
	local wallTall = WALL_TOP - FLOOR
	local sideLen = (BACK_Z + 0.5) - (FACADE_Z - 0.5)
	local sideZ = ((BACK_Z + 0.5) + (FACADE_Z - 0.5)) / 2
	for _, side in { -1, 1 } do
		Tech.wall(m, at(side * sideX, FLOOR, sideZ) * CFrame.Angles(0, -side * math.pi / 2, 0), sideLen, wallTall, 1.0, {
			Cap = false,
			BandY = 0.3,
		})
	end

	-- the finished back: two wall-banner panels with the orange band at two
	-- heights and a dark seam pilaster, neon tubes on the back corners, a
	-- framed glass window with a warm glow behind it, two vents, two pipes
	local backZ = BACK_Z + 0.5
	local panelW = hw - 0.25
	for i, side in { 1, -1 } do
		Tech.wall(m, at(side * panelW / 2, FLOOR, BACK_Z) * CFrame.Angles(0, math.pi, 0), panelW, wallTall, 1.0, {
			Cap = false,
			BandY = if i == 1 then 0.3 else 0.62,
		})
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
		Tech.glow(m, at(side * (hw - 0.27), FLOOR + wallTall / 2, backZ + 0.02), Vector3.new(Tech.TUBE, wallTall, Tech.TUBE), Tech.Tube)
	end
	local wx = 0.36 * hw
	local wy = FLOOR + 5.6
	Kit.bit(m, at(wx, wy, backZ + 0.1), Vector3.new(4.0, 2.9, 0.2), Tech.MetalLight)
	Tech.glow(m, at(wx, wy, backZ + 0.22), Vector3.new(3.3, 2.2, 0.06), opts.BackGlow or rgb(214, 96, 26))
	Kit.block(m, at(wx, wy, backZ + 0.3), Vector3.new(3.4, 2.3, 0.1), Tech.CaseGlass, Kit.GLASS, Style.tiny({ Transparency = 0.7 }))
	Kit.bit(m, at(wx, wy, backZ + 0.38), Vector3.new(0.18, 2.3, 0.06), Tech.MetalLight)
	Kit.bit(m, at(wx, wy + 0.25, backZ + 0.38), Vector3.new(3.4, 0.14, 0.06), Tech.MetalLight)
	Kit.bit(m, at(wx, wy - 1.55, backZ + 0.25), Vector3.new(4.4, 0.24, 0.5), Tech.Band)
	for _, f in { 0.26, 0.62 } do
		local x = -f * hw
		Kit.block(m, at(x, FLOOR + 7.7, backZ + 0.2), Vector3.new(2.6, 1.6, 0.4), Tech.MetalDark, nil, Style.tiny({ CastShadow = true }))
		Kit.bit(m, at(x, FLOOR + 7.7, backZ + 0.42), Vector3.new(2.2, 0.2, 0.06), Tech.MetalDeep)
	end
	for _, dx in { 1.9, 2.7 } do
		Tech.disc(m, at(hw - dx, 5.4, backZ + 0.35).Position, 10.4, 0.5, Tech.MetalLight, nil, Style.tiny({ CastShadow = true }))
	end
	Kit.bit(m, at(hw - 2.3, FLOOR + 3.2, backZ + 0.3), Vector3.new(1.6, 0.4, 0.6), Tech.Band)

	-- inside: dark lining with a neon strip, the warm ceiling panel (one light)
	Kit.bit(m, at(0, FLOOR + 4.6, BACK_Z - 0.56), Vector3.new(W - 2.6, 8.6, 0.1), Tech.MetalDark)
	Tech.glow(m, at(0, FLOOR + 8.4, BACK_Z - 0.63), Vector3.new(W - 2.6, 0.2, 0.08), accent)
	local lamp = Tech.glow(m, at(0, WALL_TOP - 0.09, 2.4), Vector3.new(W - 11, 0.16, 2.6), C.Lamp)
	lamp.Name = "CeilingLamp"
	Style.light(lamp, C.Lamp, 20, 1.6)

	-- roof slab behind the header with a light back rim and neon edges
	local roofZ0 = HEAD_Z1
	local roofD = (BACK_Z + 0.5) - roofZ0
	Style.block(
		m,
		at(0, (WALL_TOP + ROOF_TOP) / 2, roofZ0 + roofD / 2),
		Vector3.new(W - 0.2, ROOF_TOP - WALL_TOP, roofD),
		Style.vary(Tech.Metal, rng, 0.02),
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
	Tech.glow(m, at(0, WALL_TOP + 0.4, BACK_Z + 0.62), Vector3.new(W - 0.2, Tech.TUBE, 0.16), Tech.Tube)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * (hw - 0.08), WALL_TOP + 0.4, roofZ0 + roofD / 2), Vector3.new(0.16, Tech.TUBE, roofD), Tech.Tube)
	end

	-- the pylons: foot, shaft, orange band, blue neon edges and a bevelled
	-- corbel under the header's overhang; the end pylons carry an inset
	-- display-wall screen, the slim mid pylons a column of orange studs
	local pz = (PYLON_Z0 + PYLON_Z1) / 2
	local pd = PYLON_Z1 - PYLON_Z0
	local pylonScreens: { CFrame } = {}
	for _, side in { 1, -1 } do
		for _, py in pylons do
			local x = side * py.X
			local pw = py.W
			Style.block(m, at(x, 0.4, pz), Vector3.new(pw + 0.4, 0.8, pd + 0.4), Tech.MetalDark, nil, Style.solid())
			Style.block(m, at(x, HEAD_Y0 / 2, pz), Vector3.new(pw, HEAD_Y0, pd), Style.vary(Tech.Metal, rng, 0.02), nil, Style.solid())
			Kit.bit(m, at(x, 2.5, PYLON_Z0 - 0.06), Vector3.new(pw + 0.04, 0.7, 0.12), Tech.Band)
			if py.Outer then
				local sc = at(x, 6.6, PYLON_Z0 - 0.1)
				Kit.bit(m, sc, Vector3.new(pw - 0.65, 4.8, 0.2), Tech.MetalDeep)
				local screen = Tech.glow(m, sc * CFrame.new(0, 0, -0.08), Vector3.new(pw - 1.15, 4.2, 0.08), opts.Screen)
				screen.Name = "Screen"
				table.insert(pylonScreens, sc * CFrame.new(0, 0, -0.14))
			else
				Tech.studs(m, cf, Vector3.new(x, 4.6, PYLON_Z0 - 0.04), Vector3.new(x, 8.2, PYLON_Z0 - 0.04), 3, 0.42)
			end
			for _, ex in { -1, 1 } do
				Tech.glow(m, at(x + ex * (pw / 2 - 0.02), 5.5, PYLON_Z0 - 0.02), Vector3.new(0.34, 8.8, 0.34), Tech.Tube)
			end
			Tech.underBevel(m, at(x, HEAD_Y0 - 0.7, PYLON_Z0 - 0.7), Vector3.new(pw, 1.4, 1.4), Tech.MetalLight)
		end
	end

	-- the header frame: a massive block with chamfered upper corners, the sign
	-- box set into its face, a thick neon tube along its outline, light top
	-- and bottom lips, a finished back face
	local hd = HEAD_Z1 - HEAD_Z0
	local hz = (HEAD_Z0 + HEAD_Z1) / 2
	local mainTop = HEAD_Y1 - HEAD_CHAMFER
	local topW = W - 2 * HEAD_CHAMFER
	Style.block(m, at(0, (HEAD_Y0 + mainTop) / 2, hz), Vector3.new(W, mainTop - HEAD_Y0, hd), HEADER, nil, Style.decor())
	Style.block(m, at(0, (mainTop + HEAD_Y1) / 2, hz), Vector3.new(topW, HEAD_CHAMFER, hd), HEADER, nil, Style.decor())
	local hcf = at(0, 0, hz)
	for _, side in { -1, 1 } do
		-- the 45 degree chamfer: a right triangle with its vertical leg at the top block's end
		Tech.flatTri(m, hcf, side * topW / 2, mainTop, side, HEAD_CHAMFER, HEAD_CHAMFER, hd, HEADER, nil, Style.decor())
	end
	Kit.bit(m, at(0, HEAD_Y1 + 0.15, hz), Vector3.new(topW + 0.2, 0.3, hd + 0.3), HEADER_LIP)
	Kit.block(m, at(0, HEAD_Y0 + 0.25, HEAD_Z0 - 0.15), Vector3.new(W + 0.2, 0.5, 0.5), HEADER_LIP, nil, Style.tiny({ CastShadow = true }))
	-- thick neon tube along the outline (sides, chamfers, top)
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
		Tech.line(m, face, q[1], q[2], q[3], q[4], t, -0.12, Tech.Tube, nil, 0.3)
	end
	-- the back face (seen over the roof from behind): a light panel with a band
	Kit.bit(m, at(0, (WALL_TOP + ROOF_TOP) / 2 + 3.2, HEAD_Z1 + 0.07), Vector3.new(W - 4.4, 4.2, 0.14), Tech.MetalLight)
	Kit.bit(m, at(0, ROOF_TOP + 2.0, HEAD_Z1 + 0.16), Vector3.new(W - 4.4, 0.5, 0.08), Tech.Band)
	-- the porch light strip under the header
	local under = Tech.glow(m, at(0, HEAD_Y0 - 0.08, HEAD_Z0 + 0.6), Vector3.new(W - 6, 0.16, 0.3), accent)
	if not opts.SignLight then
		Style.light(under, C.Lamp, 16, 1.2)
	end

	-- the big glowing sign box set into the header face (it grows with a
	-- wider module so the header never looks empty)
	local signW: number = opts.SignWidth + math.max(0, hw - 10) * 0.8
	local _, iconAt = Tech.sign(m, at(0, SIGN_Y, HEAD_Z0 - 0.02), opts.Sign, signW, SIGN_H, {
		Icon = opts.IconWidth or 4.6,
		IconLeft = opts.IconLeft,
		Casing = false,
		Studs = false,
		Margin = 0.35,
		Light = if opts.SignLight then 16 else nil,
		LightColor = C.GlowText,
		LightDist = 0.8, -- the footprint ends 1 stud in front of the header
	})

	-- roof clutter behind the header: an orange container-tall, a gunmetal
	-- one with a pipe loop down to the roof
	Tech.container(m, at(-0.66 * hw, ROOF_TOP, 3.6), 2.8, 1.7, Tech.Band)
	local cx = 0.56 * hw
	Tech.container(m, at(cx, ROOF_TOP, 3.9), 2.4, 1.5, Tech.Metal)
	local pipeY = ROOF_TOP + 1.6
	Tech.rod(m, at(cx - 0.7, pipeY, 3.9).Position, at(cx - 2.8, pipeY, 3.9).Position, 0.4, Tech.MetalLight)
	Tech.rod(m, at(cx - 2.8, pipeY + 0.2, 3.9).Position, at(cx - 2.8, ROOF_TOP, 3.9).Position, 0.4, Tech.MetalLight)
	Tech.disc(m, at(cx - 2.8, ROOF_TOP + 0.1, 3.9).Position, 0.2, 0.8, Tech.Band)

	-- the counter in the door (table-display style, the hook is its top)
	Style.block(m, at(0, FLOOR + 1.55, COUNTER_Z), Vector3.new(6.4, 3.1, 1.4), Tech.Metal, nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.2, COUNTER_Z), Vector3.new(6.7, 0.4, 1.7), Tech.MetalDark)
	for _, x in { -2.6, 2.6 } do
		Kit.bit(m, at(x, FLOOR + 1.6, COUNTER_Z - 0.72), Vector3.new(0.4, 2.4, 0.08), frame)
	end
	Tech.glow(m, at(0, FLOOR + 1.6, COUNTER_Z - 0.73), Vector3.new(3.4, 0.24, 0.08), Tech.Neon)
	local counter =
		Style.block(m, at(0, COUNTER_TOP - 0.15, COUNTER_Z - 0.05), Vector3.new(6.9, 0.3, 1.9), Tech.MetalLight, nil, Style.solid())
	Tech.glow(m, at(0, COUNTER_TOP - 0.17, COUNTER_Z - 1.04), Vector3.new(6.9, 0.2, 0.1), Tech.Neon)

	-- shelves on the back wall with neon edges
	for _, y in SHELVES do
		Kit.bit(m, at(0, y - 0.15, SHELF_Z), Vector3.new(W - 3.2, 0.3, 1.1), Tech.MetalLight)
		Tech.glow(m, at(0, y - 0.2, SHELF_Z - 0.58), Vector3.new(W - 3.2, 0.12, 0.08), Tech.Neon)
	end

	-- display plinths behind the windows: the goods stand on a warm glow
	-- plate under a light strip, in front of a dark backdrop with a thin
	-- neon frame and a deep blue glow at its foot (a bright full backdrop
	-- reads as a hole to the sky and turns the goods into silhouettes)
	local windows: { CFrame } = {}
	local inner: { CFrame }, outer: { CFrame } = {}, {}
	for bi, bay in windowBays do
		for _, side in { 1, -1 } do
			local x = side * bay.X
			local pw = bay.W - 1.1
			Style.block(m, at(x, FLOOR + 0.8, -0.4), Vector3.new(pw, 1.6, 1.4), Tech.MetalDark)
			Tech.glow(m, at(x, FLOOR + 1.52, -1.12), Vector3.new(pw, 0.16, 0.08), Tech.Neon)
			Tech.glow(m, at(x, FLOOR + 1.63, -0.45), Vector3.new(pw - 0.4, 0.06, 1.0), Tech.CaseLight)
			local bw, bh = bay.W - 0.7, 4.6
			Kit.bit(m, at(x, FLOOR + 4.0, 0.6), Vector3.new(bw, bh, 0.1), Tech.MetalDeep)
			Tech.glow(m, at(x, FLOOR + 4.0 + bh / 2 - 0.06, 0.52), Vector3.new(bw, 0.12, 0.06), Tech.Tube)
			for _, ex in { -1, 1 } do
				Tech.glow(m, at(x + ex * (bw / 2 - 0.06), FLOOR + 4.0, 0.52), Vector3.new(0.12, bh, 0.06), Tech.Tube)
			end
			Tech.glow(m, at(x, FLOOR + 2.15, 0.52), Vector3.new(bw - 0.24, 1.1, 0.06), DEEP_GLOW)
			Tech.glow(m, at(x, FLOOR + 5.78, -1.05), Vector3.new(bay.W - 1.2, 0.08, 0.24), Tech.CaseLight)
			table.insert(if bi == 1 then inner else outer, at(x, FLOOR + 1.66, -0.45))
		end
	end
	for _, w in inner do
		table.insert(windows, w)
	end
	for _, w in outer do
		table.insert(windows, w)
	end

	-- cyan glass showcases on the porch, in front of the pylons (end pylons first)
	local cases: { CFrame } = {}
	for pass = 1, 2 do
		for _, py in pylons do
			if py.Outer == (pass == 1) then
				local x = if py.Outer then hw - 2.1 else py.X
				for _, side in { 1, -1 } do
					table.insert(cases, Tech.showcase(m, at(side * x, FLOOR, CASE_Z), 3.0, 2.0, 2.0, { Case = 2.2, Stripe = frame }))
				end
			end
		end
	end

	-- the display screen on the side wall that faces the spawn
	local s: number = opts.ScreenSide
	local screenAt = at(s * (sideX + 0.65), FLOOR + 5.4, 2.2) * CFrame.Angles(0, -s * math.pi / 2, 0)
	Tech.screen(m, screenAt, 3.6, 4.2, opts.Screen)

	return {
		Counter = counter,
		Interior = at(0, FLOOR, 2.8),
		Cases = cases,
		Windows = windows,
		Shelves = SHELVES,
		ScreenAt = screenAt,
		PylonScreens = pylonScreens,
		IconAt = iconAt,
		HalfWidth = hw,
	}
end

---------------------------------------------------------------- gear (SHOP)

-- Miner's helmet with a big head lamp. `base` = bottom center, s = scale.
local function helmet(parent: Instance, base: CFrame, color: Color3, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	Kit.bit(parent, at(0, 0.4, 0.05), Vector3.new(1.0, 0.66, 1.0) * k, color)
	Kit.bit(parent, at(0, 0.8, 0.05), Vector3.new(0.66, 0.2, 0.66) * k, color:Lerp(C.FlowerWhite, 0.2))
	Kit.bit(parent, at(0, 0.1, -0.04), Vector3.new(1.24, 0.16, 1.3) * k, color:Lerp(Kit.Dark, 0.3))
	Kit.bit(parent, at(0, 0.44, -0.5), Vector3.new(0.56, 0.5, 0.16) * k, C.Iron)
	-- a small orange lens disc (a big pale lamp blooms to a white blob)
	Tech.faceDisc(parent, at(0, 0.44, -0.6), 0.08 * k, 0.3 * k, Tech.Lens, Kit.NEON)
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
	Kit.bit(parent, at(0, 0.42, -0.34), Vector3.new(0.56, 0.42, 0.12) * k, C.Brass)
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
		Kit.bit(parent, base * CFrame.new(x * k, 0.6 * k, 0), Vector3.new(0.32, 0.72, 0.36) * k, C.AwningRed)
		Kit.bit(parent, base * CFrame.new(x * k, 1.08 * k, 0), Vector3.new(0.34, 0.26, 0.38) * k, C.FlowerWhite)
	end
	Kit.bit(parent, base * CFrame.new(0, 0.16 * k, 0), Vector3.new(1.04, 0.32, 0.36) * k, C.AwningRed)
end

local function gearShop(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("Shop")
	local m = Style.model(piece.Id, parent)
	local h = house(m, cf, piece.Size.X / 2, rng, {
		Sign = "SHOP",
		SignWidth = 14.4,
		IconLeft = false,
		Frame = Tech.Band,
		Accent = Tech.Warm,
		ScreenSide = 1,
		Screen = rgb(22, 66, 205),
	})
	h.Counter.Name = "ShopCounter"
	Kit.tag(h.Counter, "ShopCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the shopping cart on the header sign (viewer's right)
	local iconAt = h.IconAt
	if iconAt then
		Tech.cartIcon(m, iconAt, 4.0, C.GlowEdge)
	end

	-- gear on the counter, in the windows and in the porch showcases
	local top = COUNTER_TOP
	helmet(m, at(2.0, top, COUNTER_Z - 0.1), C.LeafYellow, 1.2)
	magnet(m, at(-2.2, top, COUNTER_Z - 0.1), 1.2)
	helmet(m, h.Cases[1] * CFrame.new(0.15, 0, 0.1), C.LeafYellow, 1.25)
	backpack(m, h.Cases[2] * CFrame.new(0.55, 0, 0.1), C.AwningRed)
	magnet(m, h.Cases[2] * CFrame.new(-0.75, 0, 0), 1.1)
	backpack(m, h.Windows[1] * CFrame.new(0.75, 0, 0), C.LeafGreenDark)
	helmet(m, h.Windows[1] * CFrame.new(-0.8, 0, 0), C.Gold, 1.3)
	boots(m, h.Windows[2] * CFrame.new(0.8, 0, 0), C.Copper)
	glove(m, h.Windows[2] * CFrame.new(-0.85, 0, 0), C.LeafOrange)
	-- the second display bays (wide module only)
	if h.Cases[3] then
		boots(m, h.Cases[3] * CFrame.new(0, 0, 0.1), C.Iron, 1.3)
		glove(m, h.Cases[4] * CFrame.new(0.4, 0, 0.1), C.Copper, 1.3)
		magnet(m, h.Cases[4] * CFrame.new(-0.6, 0, 0), 1.0)
		helmet(m, h.Windows[3] * CFrame.new(0, 0, 0), C.IronLight, 1.3)
		backpack(m, h.Windows[4] * CFrame.new(0, 0, 0), C.Wood, 1.3)
	end
	-- shelves: helmets, boots, packs, a magnet
	local low, high = h.Shelves[1], h.Shelves[2]
	helmet(m, at(5.6, low, SHELF_Z), C.LeafYellow, 1.2)
	helmet(m, at(3.4, low, SHELF_Z), C.IronLight, 1.2)
	boots(m, at(-3.6, low, SHELF_Z), C.Iron, 1.2)
	backpack(m, at(4.6, high, SHELF_Z), C.Wood, 1.2)
	glove(m, at(-3.0, high, SHELF_Z), C.Copper, 1.2)
	magnet(m, at(-5.4, high, SHELF_Z), 1.2)

	-- the side screen shows a helmet with a shining lamp, the pylon screens
	-- a helmet and a magnet (deep glyph colors: no white blobs)
	local sc = h.ScreenAt * CFrame.new(0, -0.2, -0.08)
	Kit.glow(m, sc * CFrame.new(0, 0.2, 0), Vector3.new(2.0, 1.3, 0.06), GLYPH_WARM)
	Kit.glow(m, sc * CFrame.new(0, -0.5, -0.02), Vector3.new(2.6, 0.3, 0.06), C.Ember)
	Tech.faceDisc(m, sc * CFrame.new(0, 0.3, -0.05), 0.06, 0.5, Tech.Lens, Kit.NEON)
	for i, ps in h.PylonScreens do
		Kit.glow(m, ps * CFrame.new(0, 0.9, 0), Vector3.new(0.9, 0.7, 0.04), if i == 1 then GLYPH_WARM else C.AwningRed)
		Kit.glow(m, ps * CFrame.new(0, -1.0, 0), Vector3.new(0.8, 0.9, 0.04), GLYPH_BLUE)
	end

	-- the outfitter behind the counter
	Kit.npc(m, h.Interior * CFrame.new(-1.4, 0, 0), {
		Name = "Outfitter",
		Shirt = C.LeafOrangeDark,
		Pants = C.WoodDark,
		Apron = C.Wood,
		Hair = C.TrunkDark,
	})
end

---------------------------------------------------------------- machines (UPGRADES)

-- Little Kenney-style machine models for the Tech shop. `base` = bottom
-- center, s = scale (1.5 = display size).
local function miniConveyor(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	Kit.bit(parent, at(0, 0.2, 0), Vector3.new(1.8, 0.4, 0.9) * k, C.Iron)
	Kit.bit(parent, at(0, 0.44, 0), Vector3.new(1.8, 0.08, 0.7) * k, Kit.Dark)
	for _, z in { -0.48, 0.48 } do
		Kit.bit(parent, at(0, 0.5, z), Vector3.new(1.9, 0.2, 0.14) * k, C.Hazard)
	end
	Kit.bit(parent, at(0.3, 0.7, 0), Vector3.new(0.45, 0.45, 0.45) * k, C.Copper)
end

-- Furnace: dark iron body, a molten mouth, a chimney with a cap.
local function miniFurnace(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	Kit.bit(parent, at(0, 0.08, 0), Vector3.new(1.3, 0.16, 1.1) * k, C.Hazard)
	Kit.bit(parent, at(0, 0.62, 0), Vector3.new(1.1, 0.92, 0.95) * k, C.Iron)
	Kit.bit(parent, at(0, 0.52, -0.46), Vector3.new(0.74, 0.56, 0.08) * k, C.IronLight)
	Kit.glow(parent, at(0, 0.5, -0.5), Vector3.new(0.56, 0.4, 0.06) * k, C.Molten)
	Kit.bit(parent, at(0.28, 1.4, 0.18), Vector3.new(0.3, 0.7, 0.3) * k, C.IronLight)
	Kit.bit(parent, at(0.28, 1.78, 0.18), Vector3.new(0.42, 0.12, 0.42) * k, C.Copper)
end

-- Tank: a copper drum with a brass band, a cap and a green gauge.
local function miniTank(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local p = base.Position
	local up = base.UpVector
	Kit.disc(parent, p + up * 0.62 * k, 1.24 * k, 0.9 * k, C.Copper, nil, Style.tiny())
	Kit.disc(parent, p + up * 0.85 * k, 0.16 * k, 1.0 * k, C.Brass, nil, Style.tiny())
	Kit.disc(parent, p + up * 1.32 * k, 0.16 * k, 0.56 * k, C.IronLight, nil, Style.tiny())
	Kit.glow(parent, base * CFrame.new(0, 0.5 * k, -0.47 * k), Vector3.new(0.26, 0.26, 0.06) * k, C.LeafGreen)
end

-- Cleaner arch: two legs, a beam with a brass nozzle and a green lamp.
local function miniCleaner(parent: Instance, base: CFrame, s: number?)
	local k = s or 1.5
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	for _, x in { -0.6, 0.6 } do
		Kit.bit(parent, at(x, 0.6, 0), Vector3.new(0.28, 1.2, 0.7) * k, C.IronLight)
	end
	Kit.bit(parent, at(0, 1.28, 0), Vector3.new(1.5, 0.28, 0.75) * k, C.IronLight)
	Kit.bit(parent, at(0, 0.98, 0), Vector3.new(0.5, 0.36, 0.36) * k, C.Brass)
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
		Frame = C.AwningPurple,
		Accent = C.CrystalPurple,
		ScreenSide = -1,
		Screen = rgb(70, 50, 210),
		BackGlow = rgb(120, 50, 220),
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

	-- machines for sale: counter, windows, showcases and shelves
	local top = COUNTER_TOP
	miniConveyor(m, at(1.6, top, COUNTER_Z - 0.1), 1.1)
	miniTank(m, at(-1.8, top, COUNTER_Z - 0.1), 1.1)
	miniFurnace(m, h.Cases[1] * CFrame.new(0.1, 0, 0.05), 1.15)
	miniCleaner(m, h.Cases[2] * CFrame.new(0, 0, 0.05), 1.25)
	miniTank(m, h.Windows[1] * CFrame.new(0.9, 0, 0))
	miniFurnace(m, h.Windows[1] * CFrame.new(-0.7, 0, 0), 1.3)
	miniCleaner(m, h.Windows[2] * CFrame.new(0.55, 0, 0), 1.2)
	miniTank(m, h.Windows[2] * CFrame.new(-1.0, 0, 0), 1.2)
	-- the second display bays (wide module only)
	if h.Cases[3] then
		miniTank(m, h.Cases[3] * CFrame.new(0, 0, 0.05), 1.3)
		miniConveyor(m, h.Cases[4] * CFrame.new(0, 0, 0.05), 1.0)
		miniCleaner(m, h.Windows[3] * CFrame.new(0, 0, 0), 1.2)
		miniFurnace(m, h.Windows[4] * CFrame.new(0, 0, 0), 1.3)
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

	-- Forgemaster Ulda behind the counter
	Kit.npc(m, h.Interior * CFrame.new(1.4, 0, 0), {
		Name = "Forgemaster Ulda",
		Tag = "Forgemaster Ulda",
		Shirt = C.RoofDark,
		Pants = C.StoneDeep,
		Apron = C.WoodDark,
		Goggles = C.Brass,
		Hair = C.LeafOrangeDark,
	})
end

function Stalls.build(parent: Instance, rng: Rng.Rng)
	gearShop(parent, rng)
	techShop(parent, rng)
end

return Stalls
