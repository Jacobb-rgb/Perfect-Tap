--[[
	SHOP (the Gear shop) and UPGRADES (the Tech shop): the concept v2 sci-fi
	shop modules either side of the Great Forge (docs/art/lobby_concept_v2.webp).
	Both share one module built from Kenney Space Station shapes (Tech kit):
	a gunmetal floor panel, side and back wall-banners, a facade of two
	wall-window-banners (glass display windows lit from inside) and a
	wall-door-wide frame, a City Kit overhang roof on round corner pillars
	with blue neon outlines and a warm under-strip, and the big glowing sign
	box on the roof (SHOP + a shopping cart icon / UPGRADES + a gear icon).
	Glass showcases on the porch, a display-wall screen on the side that
	faces the spawn, shelves of goods inside. The counter in the door is the
	hook part (ShopCounter / UpgradeCounter).

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

local FLOOR = 0.6 -- floor top
local FACADE_Z = -1.7 -- facade wall center (front face at -2.2)
local SIDE_X = 9.25 -- side wall centers (outer faces at +-9.75)
local BACK_Z = 6.1 -- back wall center (back face at 6.6)
local WALL_TOP = 10.4
local ROOF_TOP = 11.4
local DOOR_W, DOOR_H = 6.0, 7.2 -- door opening
local WIN_X = 6.225 -- window wall centers
local WIN_W = 5.05
local COUNTER_Z = 0.9
local COUNTER_TOP = FLOOR + 3.3
local SHELF_Z = 5.05
local SHELVES = { FLOOR + 2.8, FLOOR + 5.2 }
local SIGN_Y, SIGN_H = 14.85, 4.8
local CASE_X, CASE_Z = 5.7, -4.8 -- porch showcases

export type House = {
	Counter: Part,
	Interior: CFrame, -- floor point behind the counter (keeper spot)
	Cases: { CFrame }, -- display floors of the porch showcases (+X first)
	Windows: { CFrame }, -- display floors behind the windows (+X first)
	Shelves: { number }, -- shelf top heights
	ScreenAt: CFrame, -- center of the side screen (front = outward)
	IconAt: CFrame?, -- icon panel of the roof sign
}

--[[
	The shared shop module. opts:
	  Sign, SignWidth, IconLeft   roof sign text, width, icon panel side
	  Frame                       window/door frame color (Kenney band)
	  Accent                      neon accent (under-strip, floor edge)
	  SignLight                   the second light goes to the sign (it faces
	                              away from the sun), else to the porch strip
	  ScreenSide                  +1 / -1: the side wall that faces the spawn
	  Screen                      screen color
	  Backdrop                    neon backdrop color behind the windows
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
	Kit.bit(m, at(0, FLOOR + 0.02, -4.6), Vector3.new(15.6, 0.04, 4.0), Tech.Metal)
	Tech.glow(m, at(0, FLOOR - 0.15, -6.92), Vector3.new(19.4, 0.16, 0.1), accent)
	for _, side in { -1, 1 } do
		Tech.glow(m, at(side * 9.92, FLOOR - 0.15, -0.1), Vector3.new(0.1, 0.16, 13.4), Tech.Neon)
	end

	-- facade: two window walls, the wide door, one lintel over all three
	local wallH = DOOR_H
	for _, side in { -1, 1 } do
		Tech.windowWall(m, at(side * WIN_X, FLOOR, FACADE_Z), WIN_W, wallH, 1.0, {
			WindowWidth = 3.7,
			WindowBottom = 1.5,
			WindowTop = 6.4,
			Frame = frame,
		})
	end
	Tech.doorFrame(m, at(0, FLOOR, FACADE_Z), 7.4, wallH, 1.0, {
		OpeningWidth = DOOR_W,
		OpeningHeight = DOOR_H,
		Frame = frame,
		Neon = Tech.Neon,
	})
	local lintelH = WALL_TOP - FLOOR - DOOR_H
	Style.block(
		m,
		at(0, FLOOR + DOOR_H + lintelH / 2, FACADE_Z),
		Vector3.new(17.5, lintelH, 1.0),
		Style.vary(Tech.Metal, rng, 0.02),
		nil,
		Style.solid()
	)
	Kit.bit(m, at(0, FLOOR + DOOR_H + lintelH * 0.55, FACADE_Z - 0.56), Vector3.new(17.5, 0.7, 0.12), Tech.Band)
	Tech.glow(m, at(0, FLOOR + DOOR_H + 0.2, FACADE_Z - 0.56), Vector3.new(17.5, 0.18, 0.1), Tech.Neon)

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
	-- inside: dark lining with a neon strip, the warm ceiling panel (one light)
	Kit.bit(m, at(0, FLOOR + 4.6, BACK_Z - 0.56), Vector3.new(17.4, 8.6, 0.1), Tech.MetalDark)
	Tech.glow(m, at(0, FLOOR + 8.4, BACK_Z - 0.63), Vector3.new(17.4, 0.18, 0.06), accent)
	local lamp = Tech.glow(m, at(0, WALL_TOP - 0.09, 2.4), Vector3.new(9.0, 0.16, 2.6), C.Lamp)
	lamp.Name = "CeilingLamp"
	Style.light(lamp, C.Lamp, 20, 1.4)

	-- overhang roof (City Kit detail-overhang-wide): slab, a chunky front
	-- fascia with neon lines top and bottom, light side rims, neon side edges
	local roofY = (WALL_TOP + ROOF_TOP) / 2
	Style.block(m, at(0, roofY, -0.15), Vector3.new(19.8, ROOF_TOP - WALL_TOP, 13.7), Style.vary(Tech.Metal, rng, 0.02), nil, Style.solid())
	local fascia = at(0, (WALL_TOP - 0.5 + ROOF_TOP + 0.6) / 2, -6.6)
	Style.block(m, fascia, Vector3.new(19.8, ROOF_TOP - WALL_TOP + 1.1, 0.8), Style.vary(Tech.Metal, rng, 0.02), nil, Style.solid())
	Kit.bit(m, fascia * CFrame.new(0, 1.05, 0), Vector3.new(19.9, 0.4, 1.0), Tech.MetalLight)
	Tech.glow(m, fascia * CFrame.new(0, 0.42, -0.43), Vector3.new(19.8, 0.2, 0.08), Tech.Neon)
	Tech.glow(m, fascia * CFrame.new(0, -0.62, -0.43), Vector3.new(19.8, 0.24, 0.08), Tech.Neon)
	Kit.block(m, at(0, ROOF_TOP + 0.25, 6.45), Vector3.new(19.8, 0.5, 0.5), Tech.MetalLight, nil, Style.tiny({ CastShadow = true }))
	for _, side in { -1, 1 } do
		Kit.block(
			m,
			at(side * 9.65, ROOF_TOP + 0.25, 0.1),
			Vector3.new(0.5, 0.5, 12.2),
			Tech.MetalLight,
			nil,
			Style.tiny({ CastShadow = true })
		)
		Tech.glow(m, at(side * 9.93, roofY - 0.12, -0.15), Vector3.new(0.08, 0.26, 13.7), Tech.Neon)
	end
	local under = Tech.glow(m, at(0, WALL_TOP - 0.62, -6.1), Vector3.new(16.6, 0.14, 0.22), accent)
	if not opts.SignLight then
		Style.light(under, C.Lamp, 16, 1.1)
	end

	-- chunky square pillars carry the roof front
	for _, side in { -1, 1 } do
		Tech.pillar(m, at(side * 8.95, FLOOR, -6.05), WALL_TOP - 0.5 - FLOOR, 1.7)
	end

	-- the big glowing sign box on the roof, on two dark feet
	local signX = 0
	local signW: number = opts.SignWidth
	-- a sign facing away from the sun gets the module's second light (a sign lamp)
	local _, iconAt = Tech.sign(m, at(signX, SIGN_Y, -5.4), opts.Sign, signW, SIGN_H, {
		Icon = 4.8,
		IconLeft = opts.IconLeft,
		Light = if opts.SignLight then 16 else nil,
		LightColor = C.GlowText,
	})
	for _, x in { -signW * 0.32, signW * 0.32 } do
		Style.block(m, at(signX + x, ROOF_TOP + 0.25, -5.0), Vector3.new(1.4, 0.5, 1.0), Tech.MetalDark)
	end

	-- roof clutter behind the sign: an orange container, a vent box, an antenna
	Tech.container(m, at(-7.0, ROOF_TOP, 4.0), 3.0, 1.8, Tech.Band)
	Style.block(m, at(6.2, ROOF_TOP + 0.6, 4.2), Vector3.new(3.2, 1.2, 2.2), Tech.MetalLight)
	for _, x in { 5.5, 6.9 } do
		Kit.bit(m, at(x, ROOF_TOP + 0.65, 3.05), Vector3.new(0.9, 0.7, 0.1), Tech.MetalDeep)
	end
	Kit.bit(m, at(8.4, ROOF_TOP + 1.7, 5.6), Vector3.new(0.22, 3.4, 0.22), Tech.MetalLight)
	Tech.glow(m, at(8.4, ROOF_TOP + 3.5, 5.6), Vector3.new(0.45, 0.45, 0.45), accent)

	-- the counter in the door (table-display style, the hook is its top)
	Style.block(m, at(0, FLOOR + 1.55, COUNTER_Z), Vector3.new(6.4, 3.1, 1.4), Tech.Metal, nil, Style.solid())
	Kit.bit(m, at(0, FLOOR + 0.2, COUNTER_Z), Vector3.new(6.7, 0.4, 1.7), Tech.MetalDark)
	for _, x in { -2.6, 2.6 } do
		Kit.bit(m, at(x, FLOOR + 1.6, COUNTER_Z - 0.72), Vector3.new(0.4, 2.4, 0.08), frame)
	end
	Tech.glow(m, at(0, FLOOR + 1.6, COUNTER_Z - 0.72), Vector3.new(3.4, 0.16, 0.06), Tech.Neon)
	local counter =
		Style.block(m, at(0, COUNTER_TOP - 0.15, COUNTER_Z - 0.05), Vector3.new(6.9, 0.3, 1.9), Tech.MetalLight, nil, Style.solid())
	Tech.glow(m, at(0, COUNTER_TOP - 0.15, COUNTER_Z - 1.03), Vector3.new(6.9, 0.12, 0.08), Tech.Neon)

	-- shelves on the back wall with neon edges
	for _, y in SHELVES do
		Kit.bit(m, at(0, y - 0.15, SHELF_Z), Vector3.new(16.8, 0.3, 1.1), Tech.MetalLight)
		Tech.glow(m, at(0, y - 0.2, SHELF_Z - 0.58), Vector3.new(16.8, 0.1, 0.06), Tech.Neon)
	end

	-- display plinths behind the windows, lit from behind by a glowing panel
	local windows = {}
	for _, side in { 1, -1 } do
		local x = side * WIN_X
		Style.block(m, at(x, FLOOR + 0.8, -0.4), Vector3.new(3.4, 1.6, 1.4), Tech.MetalDark)
		Tech.glow(m, at(x, FLOOR + 1.55, -1.12), Vector3.new(3.4, 0.1, 0.06), Tech.Neon)
		Tech.glow(m, at(x, FLOOR + 4.0, 0.6), Vector3.new(3.8, 4.6, 0.1), opts.Backdrop)
		table.insert(windows, at(x, FLOOR + 1.6, -0.4))
	end

	-- glass showcases on the porch (table-display with a case)
	local cases = {}
	for _, side in { 1, -1 } do
		table.insert(cases, Tech.showcase(m, at(side * CASE_X, FLOOR, CASE_Z), 3.2, 2.0, 2.3, { Case = 1.9, Stripe = frame }))
	end

	-- the display screen on the side wall that faces the spawn
	local s: number = opts.ScreenSide
	local screenAt = at(s * (SIDE_X + 0.65), FLOOR + 5.4, 1.6) * CFrame.Angles(0, -s * math.pi / 2, 0)
	Tech.screen(m, screenAt, 3.6, 4.2, opts.Screen)

	return {
		Counter = counter,
		Interior = at(0, FLOOR, 2.8),
		Cases = cases,
		Windows = windows,
		Shelves = SHELVES,
		ScreenAt = screenAt,
		IconAt = iconAt,
	}
end

---------------------------------------------------------------- gear (SHOP)

-- Miner's helmet with a head lamp. `base` = bottom center.
local function helmet(parent: Instance, base: CFrame, color: Color3)
	Kit.bit(parent, base * CFrame.new(0, 0.38, 0), Vector3.new(1.05, 0.7, 1.05), color)
	Kit.bit(parent, base * CFrame.new(0, 0.82, 0), Vector3.new(0.7, 0.2, 0.7), color:Lerp(C.FlowerWhite, 0.2))
	Kit.bit(parent, base * CFrame.new(0, 0.08, -0.08), Vector3.new(1.3, 0.16, 1.4), color:Lerp(Kit.Dark, 0.25))
	Kit.glow(parent, base * CFrame.new(0, 0.42, -0.57), Vector3.new(0.42, 0.36, 0.12), C.Lamp)
end

local function boots(parent: Instance, base: CFrame, color: Color3)
	for _, x in { -0.34, 0.34 } do
		Kit.bit(parent, base * CFrame.new(x, 0.55, 0.12), Vector3.new(0.5, 1.0, 0.55), color)
		Kit.bit(parent, base * CFrame.new(x, 0.17, -0.15), Vector3.new(0.55, 0.34, 1.0), color:Lerp(Kit.Dark, 0.3))
	end
end

local function backpack(parent: Instance, base: CFrame, color: Color3)
	Kit.bit(parent, base * CFrame.new(0, 0.6, 0), Vector3.new(1.0, 1.2, 0.65), color)
	Kit.bit(parent, base * CFrame.new(0, 1.12, -0.02), Vector3.new(1.04, 0.32, 0.7), color:Lerp(Kit.Dark, 0.3))
	Kit.bit(parent, base * CFrame.new(0, 0.45, -0.36), Vector3.new(0.62, 0.45, 0.12), C.Brass)
end

local function glove(parent: Instance, base: CFrame, color: Color3)
	Kit.bit(parent, base * CFrame.new(0, 0.45, 0), Vector3.new(0.62, 0.7, 0.36), color)
	Kit.bit(parent, base * CFrame.new(0.42, 0.42, 0), Vector3.new(0.24, 0.36, 0.3), color)
	Kit.bit(parent, base * CFrame.new(0, 0.1, 0), Vector3.new(0.72, 0.22, 0.42), color:Lerp(Kit.Dark, 0.3))
end

local function magnet(parent: Instance, base: CFrame)
	for _, x in { -0.36, 0.36 } do
		Kit.bit(parent, base * CFrame.new(x, 0.62, 0), Vector3.new(0.34, 0.75, 0.36), C.AwningRed)
		Kit.bit(parent, base * CFrame.new(x, 1.1, 0), Vector3.new(0.36, 0.24, 0.38), C.IronLight)
	end
	Kit.bit(parent, base * CFrame.new(0, 0.17, 0), Vector3.new(1.06, 0.34, 0.36), C.AwningRed)
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
		Screen = C.GlowBoard,
		Backdrop = Color3.fromRGB(46, 92, 190),
	})
	h.Counter.Name = "ShopCounter"
	Kit.tag(h.Counter, "ShopCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the shopping cart on the roof sign (viewer's right)
	local iconAt = h.IconAt
	if iconAt then
		Tech.cartIcon(m, iconAt, 4.1, C.GlowEdge)
	end

	-- gear on the counter, in the windows and in the porch showcases
	local top = COUNTER_TOP
	helmet(m, at(2.2, top, COUNTER_Z - 0.1), C.LeafYellow)
	glove(m, at(-0.4, top, COUNTER_Z - 0.1), C.Copper)
	magnet(m, at(-2.4, top, COUNTER_Z - 0.1))
	helmet(m, h.Cases[1] * CFrame.new(-0.6, 0, 0), C.LeafYellow)
	helmet(m, h.Cases[1] * CFrame.new(0.7, 0, 0.1), C.IronLight)
	backpack(m, h.Cases[2] * CFrame.new(-0.6, 0, 0), C.AwningRed)
	boots(m, h.Cases[2] * CFrame.new(0.8, 0, 0), C.Wood)
	backpack(m, h.Windows[1] * CFrame.new(0.7, 0, 0), C.LeafGreenDark)
	helmet(m, h.Windows[1] * CFrame.new(-0.8, 0, 0), C.Gold)
	boots(m, h.Windows[2] * CFrame.new(0.8, 0, 0), C.Copper)
	glove(m, h.Windows[2] * CFrame.new(-0.8, 0, 0), C.LeafOrange)
	-- shelves: helmet tiers, boots, packs, gloves, magnets
	local low, high = h.Shelves[1], h.Shelves[2]
	helmet(m, at(6.4, low, SHELF_Z), C.LeafYellow)
	helmet(m, at(4.6, low, SHELF_Z), C.IronLight)
	helmet(m, at(2.8, low, SHELF_Z), C.Gold)
	boots(m, at(-3.4, low, SHELF_Z), C.Copper)
	boots(m, at(-5.8, low, SHELF_Z), C.Iron)
	backpack(m, at(5.6, high, SHELF_Z), C.AwningRed)
	backpack(m, at(3.4, high, SHELF_Z), C.Wood)
	glove(m, at(-3.0, high, SHELF_Z), C.LeafOrange)
	magnet(m, at(-5.2, high, SHELF_Z))

	-- the side screen shows a helmet with a shining lamp
	local sc = h.ScreenAt * CFrame.new(0, -0.2, -0.08)
	Kit.glow(m, sc * CFrame.new(0, 0.2, 0), Vector3.new(2.0, 1.3, 0.06), C.LeafYellow)
	Kit.glow(m, sc * CFrame.new(0, -0.5, -0.02), Vector3.new(2.6, 0.3, 0.06), C.LeafOrange)
	Kit.glow(m, sc * CFrame.new(0, 0.3, -0.04), Vector3.new(0.55, 0.45, 0.06), C.FlowerWhite)

	-- the outfitter behind the counter
	Kit.npc(m, h.Interior * CFrame.new(-1.4, 0, 0), {
		Name = "Outfitter",
		Shirt = C.LeafOrangeDark,
		Pants = C.WoodDark,
		Apron = C.Wood,
		Hair = C.TrunkDark,
	})

	-- porch: an orange container beside the left showcase
	Tech.container(m, at(8.4, FLOOR, -3.2), 2.4, 1.3, Tech.Band)
end

---------------------------------------------------------------- machines (UPGRADES)

-- Little Kenney-style machine models for the Tech shop. `base` = bottom center.
local function miniConveyor(parent: Instance, base: CFrame)
	Kit.bit(parent, base * CFrame.new(0, 0.2, 0), Vector3.new(1.8, 0.4, 0.9), C.Iron)
	Kit.bit(parent, base * CFrame.new(0, 0.44, 0), Vector3.new(1.8, 0.08, 0.7), Kit.Dark)
	for _, z in { -0.48, 0.48 } do
		Kit.bit(parent, base * CFrame.new(0, 0.5, z), Vector3.new(1.9, 0.2, 0.14), C.Hazard)
	end
	Kit.bit(parent, base * CFrame.new(0.3, 0.68, 0), Vector3.new(0.4, 0.4, 0.4), C.Copper)
end

local function miniFurnace(parent: Instance, base: CFrame)
	Kit.bit(parent, base * CFrame.new(0, 0.6, 0), Vector3.new(1.2, 1.2, 1.0), C.Copper)
	Kit.glow(parent, base * CFrame.new(0, 0.5, -0.5), Vector3.new(0.6, 0.45, 0.08), C.Molten)
	Kit.bit(parent, base * CFrame.new(0.3, 1.5, 0.15), Vector3.new(0.35, 0.7, 0.35), C.Iron)
	Kit.bit(parent, base * CFrame.new(0, 0.08, 0), Vector3.new(1.3, 0.16, 1.1), C.Hazard)
end

local function miniTank(parent: Instance, base: CFrame)
	local p = base.Position
	Kit.disc(parent, p + Vector3.new(0, 0.7, 0), 1.4, 0.95, C.Copper, nil, Style.tiny())
	Kit.disc(parent, p + Vector3.new(0, 0.95, 0), 0.16, 1.05, C.Brass, nil, Style.tiny())
	Kit.disc(parent, p + Vector3.new(0, 1.48, 0), 0.16, 0.6, C.IronLight, nil, Style.tiny())
end

local function miniCleaner(parent: Instance, base: CFrame)
	for _, x in { -0.65, 0.65 } do
		Kit.bit(parent, base * CFrame.new(x, 0.6, 0), Vector3.new(0.3, 1.2, 0.8), C.IronLight)
	end
	Kit.bit(parent, base * CFrame.new(0, 1.3, 0), Vector3.new(1.6, 0.3, 0.8), C.IronLight)
	Kit.bit(parent, base * CFrame.new(0, 0.95, 0), Vector3.new(1.0, 0.4, 0.4), C.Brass)
	Kit.glow(parent, base * CFrame.new(0.6, 1.62, 0), Vector3.new(0.22, 0.34, 0.22), C.LeafGreen)
	Kit.bit(parent, base * CFrame.new(0, 0.12, 0), Vector3.new(1.6, 0.24, 0.8), Kit.Dark)
end

local function techShop(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("Upgrades")
	local m = Style.model(piece.Id, parent)
	local h = house(m, cf, rng, {
		Sign = "UPGRADES",
		SignWidth = 16.6,
		IconLeft = true,
		Frame = C.AwningPurple,
		Accent = C.CrystalPurple,
		ScreenSide = -1,
		Screen = C.GlowBoard,
		Backdrop = Color3.fromRGB(96, 60, 186),
	})
	h.Counter.Name = "UpgradeCounter"
	Kit.tag(h.Counter, "UpgradeCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the gear on the roof sign (viewer's left)
	local iconAt = h.IconAt
	if iconAt then
		Style.icon(m, iconAt * CFrame.new(0, 0, -0.1), "Gear", 3.9, C.GlowEdge, Kit.NEON)
	end

	-- machines for sale: counter, windows, showcases and shelves
	local top = COUNTER_TOP
	miniConveyor(m, at(1.6, top, COUNTER_Z - 0.1))
	miniTank(m, at(-1.8, top, COUNTER_Z - 0.1))
	miniFurnace(m, h.Cases[1])
	miniCleaner(m, h.Cases[2])
	miniTank(m, h.Windows[1] * CFrame.new(0.8, 0, 0))
	miniFurnace(m, h.Windows[1] * CFrame.new(-0.7, 0, 0))
	miniCleaner(m, h.Windows[2] * CFrame.new(0.6, 0, 0))
	miniTank(m, h.Windows[2] * CFrame.new(-0.9, 0, 0))
	local low, high = h.Shelves[1], h.Shelves[2]
	miniFurnace(m, at(5.6, low, SHELF_Z))
	miniTank(m, at(3.4, low, SHELF_Z))
	miniConveyor(m, at(-3.0, low, SHELF_Z))
	miniCleaner(m, at(-5.6, low, SHELF_Z))
	miniConveyor(m, at(5.0, high, SHELF_Z))
	miniFurnace(m, at(2.4, high, SHELF_Z))
	miniTank(m, at(-2.6, high, SHELF_Z))
	miniConveyor(m, at(-5.2, high, SHELF_Z))

	-- the side screen (toward the spawn) shows a turning gear
	Style.icon(m, h.ScreenAt * CFrame.new(0, 0, -0.12), "Gear", 3.0, C.CrystalPurple, Kit.NEON)

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

	-- porch: a purple-banded container beside the right showcase
	Tech.container(m, at(-8.4, FLOOR, -3.2), 2.4, 1.3, C.AwningPurple)
end

function Stalls.build(parent: Instance, rng: Rng.Rng)
	gearShop(parent, rng)
	techShop(parent, rng)
end

return Stalls
