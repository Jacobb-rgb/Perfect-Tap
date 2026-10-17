--[[
	ENCHANT: the small mystic workshop behind UPGRADES, past the pink
	trees, design v2: perks for blasters; in the concept v2 metal and neon
	language: a gunmetal module (wall-banners with violet bands, a facade of
	two violet-lit windows and a wide door frame between chunky corner
	pillars with light bevel caps, the orange band and blue neon edges, an
	overhang roof with violet and blue neon edges over a light bevel cap,
	the orange band on the floor plinth, blue neon roof edges), a big deep
	violet crystal with two smaller ones in a dark rock socket on a bevelled
	holder on the roof, the ENCHANT sign box over the door and, in
	front of it, the rune table (table-display) with a glowing top (BasePart
	tag EnchantCounter) under floating crystals (tag Spin), lantern pillars
	with violet slots at the front corners. The crystals use deep colors so
	they glow purple, not pink-white.
	Local frame: 16 wide, 16 tall, 12 deep, front = -Z.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Enchant = {}

local C = Kit.C
local rgb = Color3.fromRGB

-- Deep crystal colors with explicit tips: Style's pale tips and the light
-- CrystalPurple/Pink bloom to pink-white blobs.
local DEEP_PURPLE, DEEP_PURPLE_TIP = rgb(112, 40, 226), rgb(146, 84, 240)
local DEEP_PINK, DEEP_PINK_TIP = rgb(206, 40, 150), rgb(226, 86, 176)
local DEEP_BLUE, DEEP_BLUE_TIP = rgb(36, 88, 236), rgb(76, 128, 246)
-- the roof crystal: deep violet over a darker rock socket
-- (the neon boost blooms a redder violet such as 110, 40, 230 to pink)
local ROOF_VIOLET, ROOF_VIOLET_TIP = rgb(76, 30, 214), rgb(104, 62, 232)
local ROOF_ROCK = rgb(46, 24, 90)

local FLOOR = 0.5
local HUT_FRONT = -0.6 -- facade center
local HUT_BACK = 5.0 -- back wall center
local WALL_TOP = 9.0
local ROOF_TOP = 9.8

function Enchant.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("EnchantShop")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local violet = C.CrystalPurple

	-- floor panel with a violet front edge
	Style.block(m, at(0, FLOOR / 2, -0.2), Vector3.new(15.4, FLOOR, 11.4), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Tech.glow(m, at(0, FLOOR - 0.12, -5.94), Vector3.new(15.0, 0.2, 0.12), violet)
	Kit.bit(m, at(0, FLOOR - 0.36, -5.93), Vector3.new(15.4, 0.22, 0.1), Tech.Band)

	-- the module: side and back wall-banners with violet bands
	local h = WALL_TOP - FLOOR
	local depth = HUT_BACK - HUT_FRONT
	for _, side in { -1, 1 } do
		Tech.wall(m, at(side * 5.6, FLOOR, (HUT_FRONT + HUT_BACK) / 2) * CFrame.Angles(0, -side * math.pi / 2, 0), depth + 1.0, h, 1.0, {
			Cap = false,
			Band = C.AwningPurple,
			BandY = 0.3,
		})
	end
	Tech.wall(m, at(0, FLOOR, HUT_BACK) * CFrame.Angles(0, math.pi, 0), 12.2, h, 1.0, { Cap = false, Band = C.AwningPurple, BandY = 0.3 })
	-- facade: two violet-lit windows and the wide door frame
	for _, side in { -1, 1 } do
		Tech.windowWall(m, at(side * 3.95, FLOOR, HUT_FRONT), 2.3, h, 1.0, {
			WindowWidth = 1.5,
			WindowBottom = 2.2,
			WindowTop = 5.8,
			Frame = C.AwningPurple,
			Lit = violet,
		})
	end
	Tech.doorFrame(m, at(0, FLOOR, HUT_FRONT), 5.6, h, 1.0, {
		OpeningWidth = 3.8,
		OpeningHeight = 6.0,
		Frame = C.AwningPurple,
		Neon = Tech.Neon,
	})
	-- chunky corner pillars on the facade: light bevel caps, the orange band
	-- and blue neon edges (the gunmetal frame of the other modules)
	for _, side in { -1, 1 } do
		Tech.pillar(m, at(side * 5.95, FLOOR, HUT_FRONT - 0.35), WALL_TOP - FLOOR, 1.3, { Studs = false })
	end
	-- inside: a glowing rune circle on the floor and a bookshelf
	Tech.disc(m, at(0, FLOOR + 0.03, 2.2).Position, 0.06, 3.4, C.CrystalViolet, Kit.NEON)
	Kit.bit(m, at(0, FLOOR + 4.2, HUT_BACK - 0.56), Vector3.new(10.0, 8.0, 0.1), Tech.MetalDeep)
	Style.block(m, at(0, FLOOR + 2.4, HUT_BACK - 0.95), Vector3.new(4.4, 4.8, 0.8), Tech.Metal)
	local books = { C.AwningRed, C.CrystalBlue, C.LeafGreenDark, C.AwningPurple, C.Gold, C.WoodLight }
	for i, color in books do
		local row = if i <= 3 then FLOOR + 1.5 else FLOOR + 3.3
		local x = -1.3 + ((i - 1) % 3) * 1.3
		Kit.bit(m, at(x, row + 0.6, HUT_BACK - 1.4), Vector3.new(0.9, 1.2, 0.5), color)
	end

	-- overhang roof with violet and blue neon edges
	local roofZ, roofD = 2.0, 8.0
	Style.block(m, at(0, (WALL_TOP + ROOF_TOP) / 2, roofZ), Vector3.new(13.4, ROOF_TOP - WALL_TOP, roofD), Tech.Metal, nil, Style.solid())
	Kit.block(
		m,
		at(0, ROOF_TOP + 0.2, roofZ - roofD / 2 + 0.25),
		Vector3.new(13.4, 0.4, 0.5),
		Tech.MetalLight,
		nil,
		Style.tiny({ CastShadow = true })
	)
	for _, side in { -1, 1 } do
		Kit.block(
			m,
			at(side * 6.45, ROOF_TOP + 0.2, roofZ),
			Vector3.new(0.5, 0.4, roofD),
			Tech.MetalLight,
			nil,
			Style.tiny({ CastShadow = true })
		)
	end
	Tech.glow(m, at(0, (WALL_TOP + ROOF_TOP) / 2, roofZ - roofD / 2 - 0.06), Vector3.new(13.4, 0.3, 0.12), violet)
	Tech.channel(m, at(0, ROOF_TOP + 0.42, roofZ - roofD / 2 - 0.14), 13.4, Tech.EDGE)
	Tech.underBevel(m, at(0, WALL_TOP - 0.3, roofZ - roofD / 2 + 0.3), Vector3.new(13.4, 0.6, 0.6), Tech.MetalLight)
	-- thick blue neon roof edges down both sides (the module's outline), in
	-- dark channels
	for _, side in { -1, 1 } do
		Tech.channel(m, at(side * 6.84, ROOF_TOP + 0.42, roofZ) * CFrame.Angles(0, -side * math.pi / 2, 0), roofD, Tech.EDGE)
	end

	-- the big deep violet crystal (with two smaller ones) rising out of a
	-- dark violet rock socket in a bevelled holder on the roof
	-- on the roof's left back corner, so it rises beside the sign box, not behind it
	local holder = Tech.pedestal(m, at(4.3, ROOF_TOP, 3.2), 3.0, 0.8, { Neon = violet })
	Kit.block(
		m,
		holder * CFrame.Angles(0, math.pi / 4, 0) * CFrame.new(0, 0.35, 0),
		Vector3.new(2.1, 0.7, 2.1),
		ROOF_ROCK,
		nil,
		Style.tiny()
	)
	Style.crystal(m, holder * CFrame.new(0, 0.2, 0), 5.0, 2.0, ROOF_VIOLET, ROOF_VIOLET_TIP)
	Style.crystal(m, holder * CFrame.new(0.9, 0.2, 0.2) * CFrame.Angles(0, 0, -0.4), 2.6, 0.9, ROOF_VIOLET, ROOF_VIOLET_TIP)
	Style.crystal(m, holder * CFrame.new(-1.0, 0.2, 0.3) * CFrame.Angles(0, 0, 0.4), 2.4, 0.9, DEEP_BLUE, DEEP_BLUE_TIP)

	-- ENCHANT sign box over the door (white letters, violet studs); round 2:
	-- raised a stud so the whole box clears UPGRADES' roofline from the hero
	-- camera (no cut "...NT" fragment over the roof)
	Tech.sign(m, at(0, 12.6, HUT_FRONT - 1.1), "ENCHANT", 8.6, 2.1, { StudColor = violet })

	-- the rune table: a table-display with violet stripes and a glowing top (the counter)
	local tz = -3.6
	Style.block(m, at(0, FLOOR + 0.2, tz), Vector3.new(4.2, 0.4, 2.4), Tech.MetalDark, nil, Style.solid())
	Style.block(m, at(0, FLOOR + 1.35, tz), Vector3.new(3.6, 2.3, 1.8), Tech.Metal, nil, Style.solid())
	for _, x in { -1.45, 1.45 } do
		Kit.bit(m, at(x, FLOOR + 1.35, tz - 0.93), Vector3.new(0.35, 1.8, 0.08), C.AwningPurple)
	end
	for i, x in { -0.6, 0, 0.6 } do
		local color = if i == 2 then C.CrystalCyan else C.CrystalPink
		Kit.glow(m, at(x, FLOOR + 1.6, tz - 0.94) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.34, 0.34, 0.05), color)
	end
	Style.block(m, at(0, FLOOR + 2.6, tz), Vector3.new(4.3, 0.3, 2.5), Tech.MetalLight, nil, Style.solid())
	local counter = Kit.block(m, at(0, FLOOR + 2.8, tz), Vector3.new(3.6, 0.2, 1.9), violet, Kit.NEON, Style.solid({ CastShadow = false }))
	counter.Name = "EnchantCounter"
	Kit.tag(counter, "EnchantCounter")
	Style.light(counter, violet, 16, 1.6)
	-- an open spell book and two potions on the table
	Kit.bit(m, at(-1.2, FLOOR + 2.92, tz + 0.2) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.3, 0.1, 0.95), C.AwningRed)
	Kit.bit(m, at(-1.2, FLOOR + 3.0, tz + 0.2) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.2, 0.08, 0.85), C.FlowerWhite)
	for i, x in { 1.0, 1.5 } do
		Kit.glow(m, at(x, FLOOR + 3.2, tz + 0.1 * i), Vector3.new(0.35, 0.55, 0.35), if i == 1 then C.CrystalCyan else C.CrystalPink)
		Kit.bit(m, at(x, FLOOR + 3.55, tz + 0.1 * i), Vector3.new(0.2, 0.18, 0.2), Tech.MetalLight)
	end

	-- floating crystals over the table (turn and bob on the client)
	local float = Style.model("FloatingCrystals", m)
	local mid = Style.crystal(float, at(0, 4.6, tz), 1.9, 0.7, DEEP_PURPLE, DEEP_PURPLE_TIP)
	Style.crystal(float, at(1.2, 5.0, tz) * CFrame.Angles(0, 0, -0.35), 1.2, 0.5, DEEP_PINK, DEEP_PINK_TIP)
	Style.crystal(float, at(-1.2, 4.9, tz) * CFrame.Angles(0, 0, 0.35), 1.2, 0.5, DEEP_BLUE, DEEP_BLUE_TIP)
	local core = mid[1]
	Style.emitter(core, "Sparkle", C.CrystalPink, 3)
	float.PrimaryPart = core
	float:SetAttribute("SpinSpeed", 0.5)
	float:SetAttribute("BobHeight", 0.35)
	float:SetAttribute("BobSpeed", 1.1)
	Style.streaming(float, "Atomic")
	Kit.tag(float, "Spin")

	-- the enchanter behind the table
	Kit.npc(m, at(0, FLOOR, -1.6), {
		Name = "Enchanter",
		Shirt = C.AwningPurple,
		Robe = C.AwningPurple,
		Hair = C.SkyTop,
		Beard = C.FlowerWhite,
	})

	-- lantern pillars with violet slots at the front corners, a deep purple crystal cluster
	-- and a violet container beside the module
	for _, side in { -1, 1 } do
		Tech.lanternPillar(m, at(side * 6.6, FLOOR, -4.6), 5.4, 1.2, { Slot = violet })
	end
	Style.crystalCluster(m, at(4.5, FLOOR, -2.6), 2.6, DEEP_PURPLE, rng, { Count = 3, TipLerp = 0.12 })
	Tech.container(m, at(-6.5, FLOOR, -2.7), 2.6, 1.3, C.AwningPurple)
end

return Enchant
