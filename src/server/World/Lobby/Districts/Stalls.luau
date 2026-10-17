--[[
	SHOP (the Gear shop) and UPGRADES (the Tech shop): the concept v2 sci-fi
	shop modules either side of the Great Forge (docs/art/lobby_concept_v2.webp).
	Both share one module built from Kenney Space Station shapes (Tech kit):
	  - a massive bevelled header frame across the whole front whose face is
	    the big glowing sign box (SHOP + a shopping cart / UPGRADES + a gear),
	    chamfered upper corners, a thick blue neon tube along its outline, a
	    light top lip and an orange band
	  - chunky end pylons carrying the header (bevelled corbels under its
	    overhang), each with an inset display-wall screen and blue neon edges
	  - a facade of two wall-window-banners (display windows lit from inside
	    by a glowing backdrop and a light strip) and a wall-door-wide frame
	  - glass showcases (table-display with a lit glass case) in front of
	    the pylons, a display-wall screen on the side that faces the spawn,
	    shelves of goods inside, the counter in the door = the hook part
	    (ShopCounter / UpgradeCounter)
	  - a finished back: vents, pipes, a lit wall-window panel, a neon edge
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
local SIDE_X = 9.25 -- side wall centers (outer faces at +-9.75)
local BACK_Z = 6.1 -- back wall center (back face at 6.6)
local WALL_TOP = 10.4
local ROOF_TOP = 11.2
local DOOR_W, DOOR_H = 5.4, 7.0 -- door opening
local WIN_X, WIN_W = 5.35, 4.5 -- window wall centers and width
local PYLON_X, PYLON_W = 8.8, 2.4 -- end pylons (x 7.6 .. 10)
local PYLON_Z0, PYLON_Z1 = -4.8, -1.2 -- pylon front and back
local HEAD_Y0, HEAD_Y1 = WALL_TOP, 17.0 -- the header frame
local HEAD_Z0, HEAD_Z1 = -6.2, -3.2 -- header front and back faces
local HEAD_CHAMFER = 1.6
local HEADER = Color3.fromRGB(112, 120, 146) -- the header frame: a lighter gunmetal than the walls
local HEADER_LIP = Color3.fromRGB(150, 158, 182)
local SIGN_Y, SIGN_H = 13.55, 4.6
local COUNTER_Z = 0.9
local COUNTER_TOP = FLOOR + 3.3
local SHELF_Z = 5.05
local SHELVES = { FLOOR + 2.8, FLOOR + 5.2 }
local CASE_X, CASE_Z = 7.9, -5.85 -- porch showcases (in front of the pylons)

export type House = {
	Counter: Part,
	Interior: CFrame, -- floor point behind the counter (keeper spot)
	Cases: { CFrame }, -- display floors of the porch showcases (+X first)
	Windows: { CFrame }, -- display floors behind the windows (+X first)
	Shelves: { number }, -- shelf top heights
	ScreenAt: CFrame, -- center of the side screen (front = outward)
	PylonScreens: { CFrame }, -- centers of the pylon screens (+X first)
	IconAt: CFrame?, -- icon panel of the header sign
}

--[[
	The shared shop module. opts:
	  Sign, SignWidth, IconLeft   header sign text, width, icon panel side
	  Frame                       window/door frame color (Kenney band)
	  Accent                      neon accent (porch light, floor edge)
	  SignLight                   the second light goes to the sign (it faces
	                              away from the sun), else to the porch strip
	  ScreenSide                  +1 / -1: the side wall that faces the spawn
	  Screen                      screen color
	  Backdrop                    glowing backdrop color behind the windows
]]
local function house(m: Model, cf: CFrame, rng: Rng.Rng, opts: Opts): House
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local frame: Color3 = opts.Frame
	local accent: Color3 = opts.Accent

	-- floor panel: dark slab, lighter tiles inside, neon edges
	Style.block(m, at(0, FLOOR / 2, 0), Vector3.new(19.8, FLOOR, 13.8), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.02, 2.2), Vector3.new(17.2, 0.04, 7.8), Tech.Metal)
	Kit.bit(m, at(0, FLOOR + 0.02, -4.4), Vector3.new(12.4, 0.04, 4.0), Tech.Metal)
	Tech.glow(m, at(0, FLOOR - 0.15, -6.92), Vector3.new(19.4, 0.2, 0.12), accent)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * 9.92, FLOOR - 0.15, -0.1), Vector3.new(0.12, 0.2, 13.4), Tech.Neon)
	end

	-- facade: two window walls and the wide door frame, a lintel over them
	for _, side in { -1, 1 } do
		Tech.windowWall(m, at(side * WIN_X, FLOOR, FACADE_Z), WIN_W, DOOR_H, 1.0, {
			WindowWidth = 3.5,
			WindowBottom = 1.5,
			WindowTop = 6.4,
			Frame = frame,
		})
	end
	Tech.doorFrame(m, at(0, FLOOR, FACADE_Z), 6.2, DOOR_H, 1.0, {
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
	local lintelW = 2 * (PYLON_X - PYLON_W / 2)
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

	-- side and back wall-banners (the roof covers their tops)
	local wallTall = WALL_TOP - FLOOR
	local sideLen = (BACK_Z + 0.5) - (FACADE_Z - 0.5)
	local sideZ = ((BACK_Z + 0.5) + (FACADE_Z - 0.5)) / 2
	for _, side in { -1, 1 } do
		Tech.wall(m, at(side * SIDE_X, FLOOR, sideZ) * CFrame.Angles(0, -side * math.pi / 2, 0), sideLen, wallTall, 1.0, {
			Cap = false,
			BandY = 0.3,
		})
	end
	Tech.wall(m, at(0, FLOOR, BACK_Z) * CFrame.Angles(0, math.pi, 0), 19.5, wallTall, 1.0, { Cap = false, BandY = 0.3 })
	-- the finished back: a lit wall-window panel, two vents, two pipes
	local backZ = BACK_Z + 0.5
	Kit.bit(m, at(3.6, FLOOR + 6.2, backZ + 0.1), Vector3.new(4.0, 2.8, 0.2), Tech.MetalLight)
	Tech.glow(m, at(3.6, FLOOR + 6.2, backZ + 0.22), Vector3.new(3.2, 2.0, 0.08), rgb(36, 84, 200))
	Kit.bit(m, at(3.6, FLOOR + 6.2, backZ + 0.27), Vector3.new(0.2, 2.0, 0.06), Tech.MetalLight)
	for _, x in { -2.6, -6.2 } do
		Kit.block(m, at(x, FLOOR + 7.2, backZ + 0.2), Vector3.new(2.6, 1.6, 0.4), Tech.MetalDark, nil, Style.tiny({ CastShadow = true }))
		Kit.bit(m, at(x, FLOOR + 7.2, backZ + 0.42), Vector3.new(2.2, 0.2, 0.06), Tech.MetalDeep)
	end
	for _, x in { 8.1, 7.3 } do
		Tech.disc(m, at(x, 5.4, backZ + 0.35).Position, 10.4, 0.5, Tech.MetalLight, nil, Style.tiny({ CastShadow = true }))
	end
	Kit.bit(m, at(7.7, FLOOR + 3.2, backZ + 0.3), Vector3.new(1.6, 0.4, 0.6), Tech.Band)

	-- inside: dark lining with a neon strip, the warm ceiling panel (one light)
	Kit.bit(m, at(0, FLOOR + 4.6, BACK_Z - 0.56), Vector3.new(17.4, 8.6, 0.1), Tech.MetalDark)
	Tech.glow(m, at(0, FLOOR + 8.4, BACK_Z - 0.63), Vector3.new(17.4, 0.2, 0.08), accent)
	local lamp = Tech.glow(m, at(0, WALL_TOP - 0.09, 2.4), Vector3.new(9.0, 0.16, 2.6), C.Lamp)
	lamp.Name = "CeilingLamp"
	Style.light(lamp, C.Lamp, 20, 1.6)

	-- roof slab behind the header with a light back rim and neon edges
	local roofZ0 = HEAD_Z1
	local roofD = (BACK_Z + 0.5) - roofZ0
	Style.block(
		m,
		at(0, (WALL_TOP + ROOF_TOP) / 2, roofZ0 + roofD / 2),
		Vector3.new(19.8, ROOF_TOP - WALL_TOP, roofD),
		Style.vary(Tech.Metal, rng, 0.02),
		nil,
		Style.solid()
	)
	Kit.block(m, at(0, ROOF_TOP + 0.2, BACK_Z + 0.25), Vector3.new(19.8, 0.4, 0.5), Tech.MetalLight, nil, Style.tiny({ CastShadow = true }))
	Tech.glow(m, at(0, WALL_TOP + 0.4, BACK_Z + 0.62), Vector3.new(19.8, Tech.TUBE, 0.16), Tech.Tube)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * 9.92, WALL_TOP + 0.4, roofZ0 + roofD / 2), Vector3.new(0.16, Tech.TUBE, roofD), Tech.Tube)
	end

	-- the end pylons: foot, shaft, orange band, an inset display-wall screen
	-- with blue neon edges, a bevelled corbel under the header's overhang
	local pz = (PYLON_Z0 + PYLON_Z1) / 2
	local pd = PYLON_Z1 - PYLON_Z0
	local pylonScreens = {}
	for _, side in { 1, -1 } do
		local x = side * PYLON_X
		Style.block(m, at(x, 0.4, pz), Vector3.new(PYLON_W + 0.4, 0.8, pd + 0.4), Tech.MetalDark, nil, Style.solid())
		Style.block(m, at(x, HEAD_Y0 / 2, pz), Vector3.new(PYLON_W, HEAD_Y0, pd), Style.vary(Tech.Metal, rng, 0.02), nil, Style.solid())
		Kit.bit(m, at(x, 2.5, PYLON_Z0 - 0.06), Vector3.new(PYLON_W + 0.04, 0.7, 0.12), Tech.Band)
		local sc = at(x, 6.6, PYLON_Z0 - 0.1)
		Kit.bit(m, sc, Vector3.new(1.75, 4.8, 0.2), Tech.MetalDeep)
		local screen = Tech.glow(m, sc * CFrame.new(0, 0, -0.08), Vector3.new(1.25, 4.2, 0.08), opts.Screen)
		screen.Name = "Screen"
		table.insert(pylonScreens, sc * CFrame.new(0, 0, -0.14))
		for _, ex in { -1, 1 } do
			Tech.glow(m, at(x + ex * (PYLON_W / 2 - 0.02), 5.5, PYLON_Z0 - 0.02), Vector3.new(0.34, 8.8, 0.34), Tech.Tube)
		end
		Tech.underBevel(m, at(x, HEAD_Y0 - 0.7, PYLON_Z0 - 0.7), Vector3.new(PYLON_W, 1.4, 1.4), Tech.MetalLight)
	end

	-- the header frame: a massive block with chamfered upper corners, the sign
	-- box set into its face, a thick neon tube along its outline, light top
	-- and bottom lips, a finished back face
	local hd = HEAD_Z1 - HEAD_Z0
	local hz = (HEAD_Z0 + HEAD_Z1) / 2
	local mainTop = HEAD_Y1 - HEAD_CHAMFER
	local topW = 20 - 2 * HEAD_CHAMFER
	Style.block(m, at(0, (HEAD_Y0 + mainTop) / 2, hz), Vector3.new(20, mainTop - HEAD_Y0, hd), HEADER, nil, Style.decor())
	Style.block(m, at(0, (mainTop + HEAD_Y1) / 2, hz), Vector3.new(topW, HEAD_CHAMFER, hd), HEADER, nil, Style.decor())
	local hcf = at(0, 0, hz)
	for _, side in { -1, 1 } do
		-- the 45 degree chamfer: a right triangle with its vertical leg at the top block's end
		Tech.flatTri(m, hcf, side * topW / 2, mainTop, side, HEAD_CHAMFER, HEAD_CHAMFER, hd, HEADER, nil, Style.decor())
	end
	Kit.bit(m, at(0, HEAD_Y1 + 0.15, hz), Vector3.new(topW + 0.2, 0.3, hd + 0.3), HEADER_LIP)
	Kit.block(m, at(0, HEAD_Y0 + 0.25, HEAD_Z0 - 0.15), Vector3.new(20.2, 0.5, 0.5), HEADER_LIP, nil, Style.tiny({ CastShadow = true }))
	-- thick neon tube along the outline (sides, chamfers, top)
	local face = at(0, 0, HEAD_Z0)
	local t = Tech.TUBE
	local outline = {
		{ 10 - t / 2, HEAD_Y0 + 0.6, 10 - t / 2, mainTop },
		{ 10 - t / 2, mainTop, topW / 2, HEAD_Y1 - t / 2 },
		{ topW / 2, HEAD_Y1 - t / 2, -topW / 2, HEAD_Y1 - t / 2 },
		{ -topW / 2, HEAD_Y1 - t / 2, -10 + t / 2, mainTop },
		{ -10 + t / 2, mainTop, -10 + t / 2, HEAD_Y0 + 0.6 },
	}
	for _, q in outline do
		Tech.line(m, face, q[1], q[2], q[3], q[4], t, -0.12, Tech.Tube, nil, 0.3)
	end
	-- the back face (seen over the roof from behind): a light panel with a band
	Kit.bit(m, at(0, (WALL_TOP + ROOF_TOP) / 2 + 3.2, HEAD_Z1 + 0.07), Vector3.new(15.6, 4.2, 0.14), Tech.MetalLight)
	Kit.bit(m, at(0, ROOF_TOP + 2.0, HEAD_Z1 + 0.16), Vector3.new(15.6, 0.5, 0.08), Tech.Band)
	-- the porch light strip under the header
	local under = Tech.glow(m, at(0, HEAD_Y0 - 0.08, HEAD_Z0 + 0.6), Vector3.new(14.0, 0.16, 0.3), accent)
	if not opts.SignLight then
		Style.light(under, C.Lamp, 16, 1.2)
	end

	-- the big glowing sign box set into the header face
	local signW: number = opts.SignWidth
	local _, iconAt = Tech.sign(m, at(0, SIGN_Y, HEAD_Z0 - 0.02), opts.Sign, signW, SIGN_H, {
		Icon = opts.IconWidth or 4.6,
		IconLeft = opts.IconLeft,
		Casing = false,
		Studs = false,
		Margin = 0.35,
		Light = if opts.SignLight then 16 else nil,
		LightColor = C.GlowText,
	})

	-- roof clutter behind the header: an orange container and a vent box
	Tech.container(m, at(-6.6, ROOF_TOP, 3.6), 2.8, 1.7, Tech.Band)
	Style.block(m, at(5.6, ROOF_TOP + 0.6, 3.8), Vector3.new(3.2, 1.2, 2.2), Tech.MetalLight)
	Kit.bit(m, at(5.6, ROOF_TOP + 0.65, 2.65), Vector3.new(2.6, 0.5, 0.1), Tech.MetalDeep)

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
		Kit.bit(m, at(0, y - 0.15, SHELF_Z), Vector3.new(16.8, 0.3, 1.1), Tech.MetalLight)
		Tech.glow(m, at(0, y - 0.2, SHELF_Z - 0.58), Vector3.new(16.8, 0.12, 0.08), Tech.Neon)
	end

	-- display plinths behind the windows: a bright glowing backdrop behind
	-- them and a light strip inside the window top light the goods
	local windows = {}
	for _, side in { 1, -1 } do
		local x = side * WIN_X
		Style.block(m, at(x, FLOOR + 0.8, -0.4), Vector3.new(3.4, 1.6, 1.4), Tech.MetalDark)
		Tech.glow(m, at(x, FLOOR + 1.52, -1.12), Vector3.new(3.4, 0.16, 0.08), Tech.Neon)
		Tech.glow(m, at(x, FLOOR + 4.0, 0.6), Vector3.new(3.8, 4.6, 0.1), opts.Backdrop)
		Tech.glow(m, at(x, FLOOR + 5.78, -1.05), Vector3.new(3.3, 0.08, 0.24), Tech.CaseLight)
		table.insert(windows, at(x, FLOOR + 1.6, -0.45))
	end

	-- glass showcases on the porch, in front of the pylons
	local cases = {}
	for _, side in { 1, -1 } do
		table.insert(cases, Tech.showcase(m, at(side * CASE_X, FLOOR, CASE_Z), 3.0, 2.0, 2.0, { Case = 2.2, Stripe = frame }))
	end

	-- the display screen on the side wall that faces the spawn
	local s: number = opts.ScreenSide
	local screenAt = at(s * (SIDE_X + 0.65), FLOOR + 5.4, 2.2) * CFrame.Angles(0, -s * math.pi / 2, 0)
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
	Kit.glow(parent, at(0, 0.44, -0.6), Vector3.new(0.42, 0.36, 0.08) * k, C.LeafYellowLight)
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
	local h = house(m, cf, rng, {
		Sign = "SHOP",
		SignWidth = 14.4,
		IconLeft = false,
		Frame = Tech.Band,
		Accent = Tech.Warm,
		SignLight = true,
		ScreenSide = 1,
		Screen = rgb(22, 66, 205),
		Backdrop = rgb(30, 116, 255),
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
	-- shelves: helmets, boots, packs, a magnet
	local low, high = h.Shelves[1], h.Shelves[2]
	helmet(m, at(5.6, low, SHELF_Z), C.LeafYellow, 1.2)
	helmet(m, at(3.4, low, SHELF_Z), C.IronLight, 1.2)
	boots(m, at(-3.6, low, SHELF_Z), C.Iron, 1.2)
	backpack(m, at(4.6, high, SHELF_Z), C.Wood, 1.2)
	glove(m, at(-3.0, high, SHELF_Z), C.Copper, 1.2)
	magnet(m, at(-5.4, high, SHELF_Z), 1.2)

	-- the side screen shows a helmet with a shining lamp, the pylon screens
	-- a helmet and a magnet
	local sc = h.ScreenAt * CFrame.new(0, -0.2, -0.08)
	Kit.glow(m, sc * CFrame.new(0, 0.2, 0), Vector3.new(2.0, 1.3, 0.06), C.LeafYellow)
	Kit.glow(m, sc * CFrame.new(0, -0.5, -0.02), Vector3.new(2.6, 0.3, 0.06), C.LeafOrange)
	Kit.glow(m, sc * CFrame.new(0, 0.3, -0.04), Vector3.new(0.55, 0.45, 0.06), C.FlowerWhite)
	for i, ps in h.PylonScreens do
		Kit.glow(m, ps * CFrame.new(0, 0.9, 0), Vector3.new(0.9, 0.7, 0.04), if i == 1 then C.LeafYellow else C.AwningRed)
		Kit.glow(m, ps * CFrame.new(0, -1.0, 0), Vector3.new(0.8, 0.9, 0.04), C.CrystalCyan)
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
	local h = house(m, cf, rng, {
		Sign = "UPGRADES",
		SignWidth = 15.6,
		IconWidth = 4.2,
		IconLeft = true,
		Frame = C.AwningPurple,
		Accent = C.CrystalPurple,
		ScreenSide = -1,
		Screen = rgb(70, 50, 210),
		Backdrop = rgb(132, 60, 255),
	})
	h.Counter.Name = "UpgradeCounter"
	Kit.tag(h.Counter, "UpgradeCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the gear on the header sign (viewer's left)
	local iconAt = h.IconAt
	if iconAt then
		Style.icon(m, iconAt * CFrame.new(0, 0, -0.1), "Gear", 3.6, C.GlowEdge, Kit.NEON)
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
	local low, high = h.Shelves[1], h.Shelves[2]
	miniFurnace(m, at(5.4, low, SHELF_Z), 1.2)
	miniConveyor(m, at(-3.4, low, SHELF_Z), 1.2)
	miniTank(m, at(3.0, high, SHELF_Z), 1.2)
	miniCleaner(m, at(-4.4, high, SHELF_Z), 1.2)

	-- the side screen (toward the spawn) shows a gear, the pylon screens a
	-- furnace mouth and a tank gauge
	Style.icon(m, h.ScreenAt * CFrame.new(0, 0, -0.12), "Gear", 3.0, C.CrystalPurple, Kit.NEON)
	for i, ps in h.PylonScreens do
		Kit.glow(m, ps * CFrame.new(0, 0.9, 0), Vector3.new(0.9, 0.6, 0.04), if i == 1 then C.Molten else C.LeafGreen)
		Kit.glow(m, ps * CFrame.new(0, -1.0, 0), Vector3.new(0.8, 0.9, 0.04), C.CrystalPurple)
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
