--[[
	SHOP (the Gear shop) and UPGRADES (the Tech shop): the concept's two
	stone market stalls either side of the Great Forge. Both share one
	house: stone walls on a plinth, a counter under a striped awning, a
	flat roof with a crenellated cornice and a glowing blue sign on top.

	Local frame of a stall (LobbyLayout piece, 20 x 20 x 14): front = -Z
	(toward the plaza), seen from the front local +X is on the viewer's
	left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Stalls = {}

type Opts = { [string]: any }

local C = Kit.C

-- Depth of the house (z from FRONT to BACK); the awning hangs in front of it.
local FRONT = -2.9
local BACK = 6.6
local WALL_TOP = 9.9
local COUNTER_TOP = 3.8
local SIGN_Y, SIGN_H = 13.1, 4.0 -- the glowing roof sign (center height, board height)

export type House = {
	Counter: Part,
	Interior: CFrame, -- floor point behind the counter (keeper spot)
}

--[[
	The shared stall house. opts:
	  AwningA, AwningB  stripe colors
	  Sign              sign text; SignWidth; SignX (sign center x)
	  Trim              neon color for edge trims (Tech shop) or nil
]]
local function house(m: Model, cf: CFrame, rng: Rng.Rng, opts: Opts): House
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- plinth and porch
	Style.block(m, at(0, 0.25, 0), Vector3.new(19.8, 0.5, 13.8), Style.vary(C.StoneDark, rng, 0.03), nil, Style.solid())
	Kit.bit(m, at(0, 0.52, -5.0), Vector3.new(16.4, 0.06, 3.6), C.FlagDark)

	-- stone walls (decorated outside faces)
	local depth = BACK - FRONT
	local midZ = (BACK + FRONT) / 2
	local wallH = WALL_TOP - 0.5
	for _, side in { -1, 1 } do
		Style.stoneWall(
			m,
			at(side * 9.15, 0.5, midZ) * CFrame.Angles(0, -side * math.pi / 2, 0),
			Vector3.new(depth, wallH, 1.3),
			rng,
			{ Cap = false, Density = 0.45, Color = C.StoneDeep }
		)
		-- front pilaster (lighter stone) with two accent bricks
		Style.block(m, at(side * 9.15, 0.5 + wallH / 2, FRONT), Vector3.new(1.5, wallH, 1.5), Style.vary(C.Stone, rng, 0.03))
		Kit.bit(m, at(side * 9.15, 2.4, FRONT - 0.78), Vector3.new(1.1, 1, 0.12), C.StoneLight)
		Kit.bit(m, at(side * 9.15, 6.6, FRONT - 0.78), Vector3.new(1.1, 1, 0.12), C.StoneLight)
	end
	Style.stoneWall(m, at(0, 0.5, BACK - 0.4) * CFrame.Angles(0, math.pi, 0), Vector3.new(17.0, wallH, 0.8), rng, {
		Cap = false,
		Density = 0.25,
		Color = C.StoneDark,
	})
	-- warm plank lining behind the shelves
	Kit.bit(m, at(0, 4.2, BACK - 0.86), Vector3.new(16.6, 7.2, 0.12), C.WoodLight)

	-- front lintel, cornice, roof and merlons
	Style.block(m, at(0, 8.3, FRONT + 0.3), Vector3.new(16.9, 1.1, 1.0), C.WoodDark)
	Style.block(m, at(0, 10.3, FRONT - 0.05), Vector3.new(19.8, 0.9, 1.3), Style.vary(C.StoneDeep, rng, 0.03), nil, Style.solid())
	Style.block(m, at(0, 10.3, BACK - 0.6), Vector3.new(19.8, 0.9, 1.2), Style.vary(C.StoneDeep, rng, 0.03), nil, Style.solid())
	for _, side in { -1, 1 } do
		Style.block(
			m,
			at(side * 9.3, 10.3, midZ),
			Vector3.new(1.2, 0.9, depth - 1.2),
			Style.vary(C.StoneDeep, rng, 0.03),
			nil,
			Style.solid()
		)
	end
	Style.block(m, at(0, 10.1, midZ), Vector3.new(18.4, 0.5, depth - 1), C.Stone, nil, Style.solid())
	for _, spot in { { 9.1, FRONT + 0.1 }, { -9.1, FRONT + 0.1 }, { 9.1, 2.6 }, { -9.1, 2.6 }, { 9.1, BACK - 0.7 }, { -9.1, BACK - 0.7 } } do
		Style.block(m, at(spot[1], 11.15, spot[2]), Vector3.new(1.5, 0.8, 1.5), Style.vary(C.Stone, rng, 0.04), nil, Style.decor())
	end

	-- counter
	Style.block(m, at(0, 2.0, FRONT + 0.55), Vector3.new(16.6, 3.0, 1.5), Style.vary(C.Wood, rng, 0.03), nil, Style.solid())
	local counter = Style.block(m, at(0, COUNTER_TOP - 0.2, FRONT + 0.5), Vector3.new(17.0, 0.4, 2.0), C.WoodLight, nil, Style.solid())
	for _, x in { -5.6, 0, 5.6 } do
		Kit.bit(m, at(x, 2.0, FRONT - 0.25), Vector3.new(0.45, 2.7, 0.12), C.WoodDark)
	end
	if opts.Trim then
		Kit.glow(m, at(0, COUNTER_TOP + 0.02, FRONT - 0.55), Vector3.new(17.0, 0.2, 0.2), opts.Trim)
		Kit.glow(m, at(0, 9.82, FRONT - 0.72), Vector3.new(19.8, 0.24, 0.24), opts.Trim)
		for _, side in { -1, 1 } do
			Kit.glow(m, at(side * 9.62, 0.5 + wallH / 2, FRONT - 0.78), Vector3.new(0.26, wallH, 0.26), opts.Trim)
		end
	end

	-- shelves inside
	for _, y in { 3.6, 6.0 } do
		Kit.bit(m, at(0, y, BACK - 1.45), Vector3.new(15.6, 0.3, 1.1), C.WoodDark)
	end

	-- striped awning over the counter (7 stripes like the concept)
	Style.awning(m, at(0, 9.7, FRONT - 0.1), 18.4, 3.9, 2.8, opts.AwningA, opts.AwningB, { Stripes = 7 })

	-- the glowing blue sign on the roof
	Kit.glowSign(m, at(opts.SignX or 0, SIGN_Y, FRONT + 0.3), opts.Sign, opts.SignWidth or 10, SIGN_H, rng)

	-- lights: one warm lamp inside, lanterns under the awning ends
	Kit.hangingLamp(m, at(0, 9.85, 1.6), C.Lamp, 18)
	return { Counter = counter, Interior = at(0, 0.5, 1.2) }
end

---------------------------------------------------------------- gear (SHOP)

-- Miner's helmet with a head lamp. `base` = bottom center.
local function helmet(parent: Instance, base: CFrame, color: Color3)
	Kit.bit(parent, base * CFrame.new(0, 0.32, 0), Vector3.new(1.0, 0.6, 1.0), color)
	Kit.bit(parent, base * CFrame.new(0, 0.07, 0), Vector3.new(1.25, 0.14, 1.25), color:Lerp(Kit.Dark, 0.2))
	Kit.glow(parent, base * CFrame.new(0, 0.36, -0.55), Vector3.new(0.38, 0.32, 0.12), C.Lamp)
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
		AwningA = C.AwningPink,
		AwningB = C.AwningWhite,
		Sign = "SHOP",
		SignWidth = 12,
	})
	h.Counter.Name = "ShopCounter"
	Kit.tag(h.Counter, "ShopCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- gear on the counter (helmets glow like the concept's lit goods)
	local top = COUNTER_TOP
	helmet(m, at(5.8, top, FRONT + 0.4), C.LeafYellow)
	boots(m, at(3.2, top, FRONT + 0.5), C.Wood)
	backpack(m, at(-2.6, top, FRONT + 0.6), C.LeafGreenDark)
	magnet(m, at(-5.4, top, FRONT + 0.5))
	glove(m, at(0.6, top, FRONT + 0.4), C.Copper)
	-- shelves: three helmet tiers, boots, packs, gloves, magnets
	local z = BACK - 1.45
	helmet(m, at(5.2, 3.75, z), C.LeafYellow)
	helmet(m, at(3.4, 3.75, z), C.IronLight)
	helmet(m, at(1.6, 3.75, z), C.Gold)
	boots(m, at(-1.4, 3.75, z), C.Copper)
	boots(m, at(-4.0, 3.75, z), C.Iron)
	backpack(m, at(5.0, 6.15, z), C.AwningRed)
	backpack(m, at(2.8, 6.15, z), C.Wood)
	glove(m, at(0.4, 6.15, z), C.LeafOrange)
	magnet(m, at(-2.0, 6.15, z))
	magnet(m, at(-4.6, 6.15, z))

	-- the outfitter behind the counter
	Kit.npc(m, h.Interior * CFrame.new(-1.5, 0, 0), {
		Name = "Outfitter",
		Shirt = C.LeafOrangeDark,
		Pants = C.WoodDark,
		Apron = C.Wood,
		Hair = C.TrunkDark,
	})

	-- lanterns under the awning ends (one lit) and crates/barrels on the porch
	Kit.hangingLamp(m, at(8.2, 8.0, -5.4), C.Lamp, 14)
	Kit.hangingLamp(m, at(-8.2, 8.0, -5.4), C.Lamp)
	Style.barrel(m, at(-8.4, 0.5, -5.6).Position, rng)
	Kit.crate(m, at(8.4, 0.5, -5.6), 2.2, rng)
	Kit.crate(m, at(8.4, 2.7, -5.6), 1.6, rng, C.Wood)

	-- roof: a crate and a blue crystal on the back corners (concept)
	Kit.crate(m, at(-7.0, 10.35, BACK - 2.2), 2.0, rng)
	Style.crystal(m, at(7.2, 10.35, BACK - 2.4), 2.8, 1.2, C.CrystalBlue)
	Style.crystal(m, at(8.1, 10.35, BACK - 1.8) * CFrame.Angles(0, 0, -0.35), 1.6, 0.8, C.CrystalCyan)
end

---------------------------------------------------------------- machines (UPGRADES)

-- Little Kenney-style machine models for the Tech shop shelves. `base` = bottom center.
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
		AwningA = C.AwningPurple,
		AwningB = C.AwningWhite,
		Sign = "UPGRADES",
		SignWidth = 12.4,
		SignX = -2.2,
		Trim = C.GlowEdge,
	})
	h.Counter.Name = "UpgradeCounter"
	Kit.tag(h.Counter, "UpgradeCounter")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- gear icon board left of the sign (viewer's left = local +X)
	local iconAt = at(6.9, SIGN_Y, FRONT + 0.3)
	Style.block(m, iconAt, Vector3.new(SIGN_H - 0.2, SIGN_H - 0.2, 0.6), C.GlowBoard)
	Style.block(m, iconAt * CFrame.new(0, 0, 0.35), Vector3.new(SIGN_H + 0.7, SIGN_H + 0.7, 0.5), Style.vary(C.StoneDark, rng, 0.03))
	Style.icon(m, iconAt * CFrame.new(0, 0, -0.45), "Gear", 3.2, C.GlowEdge, Kit.NEON)

	-- machines for sale: on the counter and the shelves
	local top = COUNTER_TOP
	miniConveyor(m, at(5.4, top, FRONT + 0.5))
	miniFurnace(m, at(2.4, top, FRONT + 0.5))
	miniCleaner(m, at(-2.2, top, FRONT + 0.5))
	miniTank(m, at(-5.4, top, FRONT + 0.5))
	local z = BACK - 1.45
	miniFurnace(m, at(5.2, 3.75, z))
	miniTank(m, at(3.2, 3.75, z))
	miniConveyor(m, at(0.6, 3.75, z))
	miniCleaner(m, at(-2.6, 3.75, z))
	miniTank(m, at(-5.0, 3.75, z))
	miniConveyor(m, at(4.6, 6.15, z))
	miniFurnace(m, at(1.6, 6.15, z))
	miniCleaner(m, at(-1.6, 6.15, z))
	miniConveyor(m, at(-4.6, 6.15, z))

	-- a workbench with a blue screen at the side
	Style.block(m, at(-7.2, 1.7, 2.4), Vector3.new(2.2, 2.4, 3.6), C.Wood)
	Kit.bit(m, at(-7.4, 4.0, 2.6), Vector3.new(0.4, 1.8, 2.6), C.Iron)
	Kit.glow(m, at(-7.15, 4.0, 2.6), Vector3.new(0.1, 1.4, 2.2), C.CrystalBlue)

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

	-- the blue chip panel on the side wall that faces the spawn (local -X)
	Kit.bit(m, at(-9.86, 5.4, 1.6), Vector3.new(0.18, 3.4, 3.8), C.Iron)
	local screen = Kit.glow(m, at(-9.95, 5.4, 1.6), Vector3.new(0.08, 2.8, 3.2), C.GlowEdge)
	for _, y in { 4.9, 5.9 } do
		Kit.bit(m, at(-9.98, y, 1.6), Vector3.new(0.05, 0.22, 2.2), C.GlowBoard)
	end
	Kit.bit(m, at(-9.98, 5.4, 1.6), Vector3.new(0.05, 1.6, 0.22), C.GlowBoard)
	Style.light(screen, C.GlowEdge, 12, 1.2)

	-- lanterns under the awning (glow only) and a gear crate on the porch
	Kit.hangingLamp(m, at(8.2, 8.0, -5.4), C.Lamp)
	Kit.hangingLamp(m, at(-8.2, 8.0, -5.4), C.Lamp)
	Kit.crate(m, at(-8.4, 0.5, -5.6), 2.2, rng)
	Kit.crate(m, at(8.4, 0.5, -5.6), 2.0, rng, C.Wood)

	-- roof clutter: a tank and pipe stub (Kenney factory flavor)
	Kit.disc(m, at(-7.0, 11.6, BACK - 2.3).Position, 2.5, 2.0, C.Copper)
	Kit.disc(m, at(-7.0, 12.0, BACK - 2.3).Position, 0.3, 2.2, C.Brass, nil, Style.tiny())
	Kit.crate(m, at(7.2, 10.35, BACK - 2.2), 2.0, rng)
end

function Stalls.build(parent: Instance, rng: Rng.Rng)
	gearShop(parent, rng)
	techShop(parent, rng)
end

return Stalls
