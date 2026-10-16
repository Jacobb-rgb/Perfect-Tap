--[[
	ENCHANT: the small mystic workshop behind UPGRADES, past the pink trees
	(design v2: perks for blasters). A dark stone hut with a purple roof and
	a crystal on the ridge, purple-lit windows, an ENCHANT sign over the
	door and, in front of it, the rune table with a glowing top (BasePart
	tag EnchantCounter) under floating crystals (tag Spin).
	Local frame: 16 wide, 16 tall, 12 deep, front = -Z.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Enchant = {}

local C = Kit.C

local HUT_FRONT = -0.6
local HUT_BACK = 5.0
local WALL_TOP = 9.0

function Enchant.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("EnchantShop")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	Style.block(m, at(0, 0.25, -0.2), Vector3.new(15.4, 0.5, 11.4), Style.vary(C.StoneDark, rng, 0.03), nil, Style.solid())

	-- the hut: dark stone walls, a door opening with two lit windows beside it
	local h = WALL_TOP - 0.5
	local depth = HUT_BACK - HUT_FRONT
	local wallOpts = { Cap = false, Density = 0.35, Color = C.StoneDark }
	Style.stoneWall(m, at(0, 0.5, HUT_BACK) * CFrame.Angles(0, math.pi, 0), Vector3.new(11, h, 0.8), rng, wallOpts)
	for _, side in { -1, 1 } do
		Style.stoneWall(
			m,
			at(side * 5.1, 0.5, (HUT_FRONT + HUT_BACK) / 2) * CFrame.Angles(0, -side * math.pi / 2, 0),
			Vector3.new(depth, h, 0.8),
			rng,
			wallOpts
		)
		-- front piers beside the door
		Style.stoneWall(m, at(side * 3.85, 0.5, HUT_FRONT), Vector3.new(2.7, h, 0.8), rng, {
			Cap = false,
			Density = 0.3,
			Color = C.StoneDark,
			Courses = false,
		})
		Style.window(m, at(side * 3.85, 4.4, HUT_FRONT - 0.45), 1.3, 1.9, { Color = C.CrystalPurple })
	end
	Style.block(m, at(0, 7.5, HUT_FRONT), Vector3.new(5.2, 3.0, 0.8), C.StoneDeep)
	-- inside: a glowing rune circle on the floor and a bookshelf
	Kit.disc(m, at(0, 0.53, 2.2).Position, 0.06, 3.4, C.CrystalViolet, Kit.NEON, Style.tiny())
	Style.block(m, at(0, 2.9, HUT_BACK - 0.85), Vector3.new(4.4, 4.8, 0.8), C.WoodDark)
	local books = { C.AwningRed, C.CrystalBlue, C.LeafGreenDark, C.AwningPurple, C.Gold, C.WoodLight }
	for i, color in books do
		local row = if i <= 3 then 2.0 else 3.8
		local x = -1.3 + ((i - 1) % 3) * 1.3
		Kit.bit(m, at(x, row + 0.6, HUT_BACK - 1.3), Vector3.new(0.9, 1.2, 0.5), color)
	end

	-- purple roof with a crystal on the ridge
	Style.gableRoof(m, at(0, WALL_TOP, 2.0), 13, 7.0, 4.2, {
		Color = C.AwningPurple,
		Dark = C.CloudPurple,
		Trim = C.StoneDeep,
	})
	Style.crystal(m, at(0, WALL_TOP + 4.6, 2.0), 2.2, 0.9, C.CrystalPurple)

	-- ENCHANT sign over the door
	Kit.neonSign(m, at(0, 7.65, HUT_FRONT - 0.65), "ENCHANT", 7.6, 2.0, C.SkyTop, C.CrystalPurple, { Depth = 0.5 })

	-- the rune table: stone base, purple cloth with runes, glowing top (the counter)
	local tz = -3.6
	Style.block(m, at(0, 1.7, tz), Vector3.new(3.8, 2.4, 2.0), C.StoneDeep, nil, Style.solid())
	Style.block(m, at(0, 3.05, tz), Vector3.new(4.3, 0.3, 2.5), C.AwningPurple, nil, Style.solid())
	Kit.bit(m, at(0, 2.45, tz - 1.3), Vector3.new(4.3, 1.1, 0.12), C.AwningPurple)
	Kit.bit(m, at(0, 1.92, tz - 1.33), Vector3.new(4.3, 0.15, 0.13), C.Gold)
	for i, x in { -1.3, 0, 1.3 } do
		local color = if i == 2 then C.CrystalCyan else C.CrystalPink
		Kit.glow(m, at(x, 2.5, tz - 1.39) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.4, 0.4, 0.05), color)
	end
	local counter = Kit.block(m, at(0, 3.3, tz), Vector3.new(3.6, 0.2, 1.9), C.CrystalPurple, Kit.NEON, Style.solid({ CastShadow = false }))
	counter.Name = "EnchantCounter"
	Kit.tag(counter, "EnchantCounter")
	Style.light(counter, C.CrystalPurple, 16, 1.6)
	-- an open spell book and two potions on the table
	Kit.bit(m, at(-1.2, 3.42, tz + 0.2) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.3, 0.1, 0.95), C.AwningRed)
	Kit.bit(m, at(-1.2, 3.5, tz + 0.2) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.2, 0.08, 0.85), C.FlowerWhite)
	for i, x in { 1.0, 1.5 } do
		Kit.glow(m, at(x, 3.7, tz + 0.1 * i), Vector3.new(0.35, 0.55, 0.35), if i == 1 then C.CrystalCyan else C.CrystalPink)
		Kit.bit(m, at(x, 4.05, tz + 0.1 * i), Vector3.new(0.2, 0.18, 0.2), C.WoodLight)
	end

	-- floating crystals over the table (turn and bob on the client)
	local float = Style.model("FloatingCrystals", m)
	local mid = Style.crystal(float, at(0, 4.6, tz), 1.9, 0.7, C.CrystalPurple)
	Style.crystal(float, at(1.2, 5.0, tz) * CFrame.Angles(0, 0, -0.35), 1.2, 0.5, C.CrystalPink)
	Style.crystal(float, at(-1.2, 4.9, tz) * CFrame.Angles(0, 0, 0.35), 1.2, 0.5, C.CrystalBlue)
	local core = mid[1]
	Style.emitter(core, "Sparkle", C.CrystalPink, 3)
	float.PrimaryPart = core
	float:SetAttribute("SpinSpeed", 0.5)
	float:SetAttribute("BobHeight", 0.35)
	float:SetAttribute("BobSpeed", 1.1)
	Style.streaming(float, "Atomic")
	Kit.tag(float, "Spin")

	-- the enchanter behind the table
	Kit.npc(m, at(0, 0.5, -1.5), {
		Name = "Enchanter",
		Shirt = C.AwningPurple,
		Robe = C.AwningPurple,
		Hair = C.SkyTop,
		Beard = C.FlowerWhite,
	})

	-- purple lanterns at the door, a crystal cluster and a crate beside the hut
	for _, side in { -1, 1 } do
		Kit.hangingLamp(m, at(side * 4.6, 8.85, HUT_FRONT - 1.0), C.CrystalPurple)
	end
	Style.crystalCluster(m, at(5.6, 0.5, -2.8), 3.4, C.CrystalPurple, rng, { Count = 3 })
	Kit.crate(m, at(-6.4, 0.5, -3.4), 2.0, rng)
	Kit.crate(m, at(-6.4, 2.5, -3.4), 1.4, rng, C.AwningPurple)
end

return Enchant
