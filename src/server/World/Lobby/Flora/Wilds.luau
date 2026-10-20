--[[
	Wilds (owner 2026-10-20, nature chat: "on the green places around the map
	a few pebbles, flowers, small bushes or some secrets", from his nature
	sheet): small voxel nature pieces for the free lawns, and a handful of
	hidden secret spots near the island's edges.

	  Pieces    pebbles, mossy rocks, standing stones, tall grass, flower
	            patches (tulips, daisies, bluebells, lavender, wildflowers),
	            berry and blossom bushes, ferns, stumps, fallen logs, mushrooms
	  Secrets   a lost miner's camp, a half-buried treasure chest, a fairy
	            ring of mushrooms around a crystal, a fossil skeleton in the
	            dirt, a Kaldrum rune stone

	It runs after the Meadow and uses its free-ground index (Meadow.index /
	free / allowed), so it never stands on a road, a plot, a stall apron or
	an ore outcrop. Pure decoration: no collision, no raycasts, no shadows,
	no lights (the camp fire and the runes glow with Neon only).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)
local Meadow = require(script.Parent.Meadow)

local C = Style.C
local NEON = Enum.Material.Neon

local Wilds = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Wilds.Colors = {
	Rock = rgb(146, 146, 152),
	RockLight = rgb(186, 184, 182),
	RockDark = rgb(106, 106, 114),
	Moss = rgb(96, 156, 58),
	MossDark = rgb(66, 120, 46),
	Stem = rgb(84, 160, 64),
	Leaf = rgb(76, 150, 56),
	Berry = rgb(222, 40, 62),
	Blossom = rgb(255, 168, 210),
	CapRed = rgb(222, 52, 46),
	CapBrown = rgb(160, 104, 62),
	CapSpot = rgb(252, 246, 236),
	MushStem = rgb(240, 228, 206),
	Bone = rgb(238, 228, 202),
	BoneDark = rgb(196, 182, 152),
	Canvas = rgb(232, 210, 160),
	CanvasDark = rgb(204, 178, 126),
	Rune = rgb(96, 232, 255),
	Cattail = rgb(118, 74, 42),
}
local W = Wilds.Colors

type Builder = (parent: Instance, p: Vector3, rng: Rng.Rng) -> Model

-- A small decoration block (no collision, no shadow).
local function bit(parent: Instance, cf: CFrame, size: Vector3, color: Color3, rng: Rng.Rng?, material: Enum.Material?): Part
	local c = if rng then Style.vary(color, rng, 0.05) else color
	return Style.block(parent, cf, size, c, material, Style.tiny())
end

local function yawAt(p: Vector3, rng: Rng.Rng): CFrame
	return CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi * 2), 0)
end

---------------------------------------------------------------- stones

-- 3 pebbles, the biggest with a lighter chip and now and then a moss cap.
local function pebbles(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("Pebbles", parent)
	for i = 1, 3 do
		local s = if i == 1 then rng:range(1.1, 1.5) else rng:range(0.5, 0.85)
		local off = if i == 1 then Vector3.new(0, 0, 0) else Vector3.new(rng:range(-1.5, 1.5), 0, rng:range(-1.5, 1.5))
		local cf = CFrame.new(p + off + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(0, rng:range(0, math.pi), 0) * Geo.randomTilt(rng, 0.15)
		bit(m, cf, Vector3.new(s * 1.25, s * 0.7, s), if i == 1 then W.Rock elseif rng:chance(0.5) then W.RockLight else W.RockDark, rng)
		if i == 1 then
			if rng:chance(0.5) then
				bit(m, cf * CFrame.new(0, s * 0.38, 0), Vector3.new(s * 0.9, 0.14, s * 0.7), W.Moss, rng)
			else
				bit(m, cf * CFrame.new(s * 0.2, s * 0.4, -s * 0.1), Vector3.new(s * 0.7, s * 0.3, s * 0.6), W.RockLight, rng)
			end
		end
	end
	return m
end

-- A boulder of two chunks with a light top, a moss blanket and a moss drip.
local function mossRock(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("MossRock", parent)
	local s = rng:range(2.4, 3.2)
	local base = yawAt(p, rng)
	local h = s * 0.8
	bit(m, base * CFrame.new(0, h / 2, 0), Vector3.new(s * 1.25, h, s), W.Rock, rng)
	bit(
		m,
		base * CFrame.new(s * 0.62, h * 0.38, s * 0.15) * Geo.randomTilt(rng, 0.1),
		Vector3.new(s * 0.7, h * 0.76, s * 0.75),
		W.RockDark,
		rng
	)
	bit(
		m,
		base * CFrame.new(-s * 0.12, h + s * 0.16, -s * 0.05) * Geo.randomTilt(rng, 0.1),
		Vector3.new(s * 0.8, s * 0.4, s * 0.7),
		W.RockLight,
		rng
	)
	bit(m, base * CFrame.new(-s * 0.12, h + s * 0.37, -s * 0.05), Vector3.new(s * 0.84, 0.18, s * 0.74), W.Moss, rng)
	bit(m, base * CFrame.new(-s * 0.35, h * 0.62, -s * 0.5 - 0.06), Vector3.new(s * 0.45, h * 0.75, 0.16), W.MossDark, rng)
	return m
end

-- A tall standing stone with a light top chip, a moss streak and a small stone at its foot.
local function standingStone(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("StandingStone", parent)
	local h = rng:range(3.6, 5)
	local base = yawAt(p, rng) * Geo.randomTilt(rng, 0.08)
	bit(m, base * CFrame.new(0, h / 2, 0), Vector3.new(1.6, h, 1.25), W.Rock, rng)
	bit(m, base * CFrame.new(0.1, h + 0.28, 0), Vector3.new(1.2, 0.6, 0.95), W.RockLight, rng)
	bit(m, base * CFrame.new(-0.81, h * 0.4, 0), Vector3.new(0.16, h * 0.55, 0.8), W.MossDark, rng)
	bit(m, base * CFrame.new(1.35, 0.4, 0.3) * CFrame.Angles(0, 0, math.rad(-12)), Vector3.new(0.9, 0.8, 0.8), W.RockDark, rng)
	return m
end

---------------------------------------------------------------- grass

local GRASS = { C.GrassLight, C.LeafGreenLight, C.LeafGreen }

-- Tall grass: 5 pointed blades (wedges) leaning out from a small clump, with
-- white or yellow seed tips on two of them when `flowered`.
local function tallGrass(parent: Instance, p: Vector3, rng: Rng.Rng, flowered: boolean?): Model
	local m = Style.model(if flowered then "FlowerGrass" else "TallGrass", parent)
	local a0 = rng:range(0, math.pi * 2)
	local tip = if rng:chance(0.6) then C.FlowerWhite else C.FlowerYellow
	for i = 1, 5 do
		local h = if i == 1 then rng:range(2.2, 2.7) else rng:range(1.3, 2.1)
		local w = rng:range(0.85, 1.15)
		local a = a0 + i * (math.pi * 2 / 5) + rng:range(-0.25, 0.25)
		-- local +Z points out from the clump; the blade's point is on that side
		local frame = CFrame.new(p) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 0.25) * CFrame.Angles(math.rad(rng:range(10, 24)), 0, 0)
		local blade = frame * CFrame.new(0, h / 2, 0)
		Geo.wedge(m, blade, Vector3.new(0.16, h, w), Style.vary(GRASS[rng:int(1, #GRASS)], rng, 0.05), nil, Style.tiny())
		if flowered and i <= 2 then
			bit(m, blade * CFrame.new(0, h / 2 + 0.05, w / 2 - 0.1), Vector3.new(0.32, 0.32, 0.32), tip, rng)
		end
	end
	return m
end

---------------------------------------------------------------- flowers

-- One flower on a stem (with a leaf on `leaf`). kind: Tulip, Daisy, Bluebell,
-- Lavender, Poppy, Sunny. 3-5 parts.
local function flower(parent: Instance, p: Vector3, kind: string, rng: Rng.Rng, leaf: boolean?)
	local h = if kind == "Lavender" then rng:range(1.2, 1.6) else rng:range(1.1, 1.7)
	local yaw = CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi), 0)
	bit(parent, yaw * CFrame.new(0, h / 2, 0), Vector3.new(0.18, h, 0.18), W.Stem, rng)
	if leaf then
		bit(parent, yaw * CFrame.new(0.35, h * 0.32, 0) * CFrame.Angles(0, 0, math.rad(-25)), Vector3.new(0.8, 0.12, 0.38), W.Leaf, rng)
	end
	local top = yaw * CFrame.new(0, h, 0)
	if kind == "Tulip" then
		local color = if rng:chance(0.6) then C.FlowerRed elseif rng:chance(0.5) then C.FlowerPink else C.FlowerYellow
		bit(parent, top * CFrame.new(0, 0.3, 0), Vector3.new(0.7, 0.7, 0.7), color, rng)
		bit(
			parent,
			top * CFrame.new(0, 0.72, 0) * CFrame.Angles(0, math.pi / 4, 0),
			Vector3.new(0.5, 0.26, 0.5),
			color:Lerp(Color3.new(1, 1, 1), 0.2),
			rng
		)
	elseif kind == "Lavender" then
		bit(parent, top * CFrame.new(0, 0.2, 0), Vector3.new(0.46, 0.6, 0.46), C.CrystalViolet, rng)
		bit(parent, top * CFrame.new(0, 0.66, 0), Vector3.new(0.32, 0.4, 0.32), C.FlowerPurple, rng)
	else
		local petal = if kind == "Daisy"
			then C.FlowerWhite
			elseif kind == "Bluebell" then C.FlowerBlue
			elseif kind == "Poppy" then C.FlowerRed
			else C.FlowerYellow
		local s = rng:range(0.95, 1.2)
		bit(parent, top, Vector3.new(s, 0.18, s * 0.4), petal, rng)
		bit(parent, top * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(s, 0.18, s * 0.4), petal, rng)
		if kind == "Daisy" or kind == "Poppy" then
			bit(
				parent,
				top * CFrame.new(0, 0.1, 0),
				Vector3.new(0.38, 0.22, 0.38),
				if kind == "Daisy" then C.FlowerYellow else C.HazardDark,
				rng
			)
		end
	end
end

Wilds.FlowerKinds = { "Tulip", "Daisy", "Bluebell", "Lavender", "Poppy", "Sunny" }

-- A patch of 3 flowers of one kind ("Wildflowers": mixed) on a leafy mound.
local function flowerPatch(kind: string): Builder
	return function(parent: Instance, p: Vector3, rng: Rng.Rng): Model
		local m = Style.model(kind .. "Patch", parent)
		bit(m, yawAt(p + Vector3.new(0, 0.15, 0), rng), Vector3.new(rng:range(2.4, 3), 0.3, rng:range(1.8, 2.4)), C.LeafGreenDark, rng)
		for i = 1, 3 do
			local a = i * (math.pi * 2 / 3) + rng:range(-0.4, 0.4)
			local r = rng:range(0.6, 1)
			local k = if kind == "Wildflowers" then Wilds.FlowerKinds[rng:int(1, #Wilds.FlowerKinds)] else kind
			flower(m, p + Vector3.new(math.cos(a) * r, 0.25, math.sin(a) * r), k, rng, i == 1)
		end
		return m
	end
end

---------------------------------------------------------------- bushes

-- A lumpy voxel bush (a core, two side lumps and a light top, like the
-- trees' canopies) with dots: red berries ("Berry") or pink blossoms ("Blossom").
local function dottedBush(kind: string): Builder
	return function(parent: Instance, p: Vector3, rng: Rng.Rng): Model
		local m = Style.model(kind .. "Bush", parent)
		local s = rng:range(2, 2.6)
		local base = yawAt(p, rng)
		local dark, mid, light = C.LeafGreenDark, C.LeafGreen, C.LeafGreenLight
		if kind == "Blossom" then
			mid, light = C.LeafGreenDark:Lerp(C.LeafGreen, 0.6), C.LeafGreen
		end
		bit(m, base * CFrame.new(0, s * 0.35, 0), Vector3.new(s * 1.1, s * 0.7, s), mid, rng)
		bit(m, base * CFrame.new(s * 0.45, s * 0.52, s * 0.25), Vector3.new(s * 0.62, s * 0.56, s * 0.62), light, rng)
		bit(m, base * CFrame.new(-s * 0.5, s * 0.27, -s * 0.2), Vector3.new(s * 0.56, s * 0.52, s * 0.56), dark, rng)
		bit(m, base * CFrame.new(-s * 0.1, s * 0.8, -s * 0.05), Vector3.new(s * 0.6, s * 0.4, s * 0.6), light, rng)
		local dot = if kind == "Blossom" then W.Blossom else W.Berry
		local d = if kind == "Blossom" then 0.46 else 0.36
		for _, q in
			{
				Vector3.new(s * 0.5, s * 0.82, s * 0.3),
				Vector3.new(s * 0.05, s * 0.45, s * 0.52),
				Vector3.new(-s * 0.12, s * 1.02, -s * 0.1),
			}
		do
			bit(m, base * CFrame.new(q), Vector3.new(d, d, d), dot, rng)
		end
		return m
	end
end

-- A low fern: five fronds fanned out flat.
local function fern(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("Fern", parent)
	local a0 = rng:range(0, math.pi * 2)
	for i = 1, 5 do
		local a = a0 + i * (math.pi * 2 / 5)
		local len = rng:range(1.8, 2.4)
		local frame = CFrame.new(p) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(rng:range(22, 34)), 0, 0)
		bit(m, frame * CFrame.new(0, 0, -len / 2), Vector3.new(0.6, 0.14, len), if i % 2 == 0 then C.LeafGreenDark else W.Leaf, rng)
	end
	return m
end

---------------------------------------------------------------- wood and mushrooms

local function mushroom(parent: Instance, p: Vector3, red: boolean, size: number, rng: Rng.Rng)
	local h = 0.7 * size
	local yaw = CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi), 0)
	bit(parent, yaw * CFrame.new(0, h / 2, 0), Vector3.new(0.34, h, 0.34) * size, W.MushStem, rng)
	local capSize = Vector3.new(1, 0.42, 1) * size
	bit(parent, yaw * CFrame.new(0, h + capSize.Y / 2 - 0.05, 0), capSize, if red then W.CapRed else W.CapBrown, rng)
	if red then
		bit(parent, yaw * CFrame.new(0.2 * size, h + capSize.Y, -0.1 * size), Vector3.new(0.3, 0.08, 0.3) * size, W.CapSpot)
	else
		bit(
			parent,
			yaw * CFrame.new(0, h + capSize.Y + 0.05, 0),
			Vector3.new(0.6, 0.16, 0.6) * size,
			W.CapBrown:Lerp(C.DirtLight, 0.4),
			rng
		)
	end
end

-- 2 (sometimes 3) mushrooms of one kind.
local function mushrooms(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("Mushrooms", parent)
	local red = rng:chance(0.6)
	for i = 1, if rng:chance(0.3) then 3 else 2 do
		local off = if i == 1 then Vector3.new(0, 0, 0) else Vector3.new(rng:range(-0.9, 0.9), 0, rng:range(-0.9, 0.9))
		mushroom(m, p + off, red, if i == 1 then rng:range(1.1, 1.35) else rng:range(0.7, 0.9), rng)
	end
	return m
end

-- A tree stump with its rings, a root and moss on one side.
local function stump(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("Stump", parent)
	local base = yawAt(p, rng)
	local h = rng:range(1.1, 1.6)
	bit(m, base * CFrame.new(0, h / 2, 0), Vector3.new(1.8, h, 1.8), C.Trunk, rng)
	bit(m, base * CFrame.new(0, h + 0.03, 0), Vector3.new(1.5, 0.08, 1.5), C.WoodLight, rng)
	bit(m, base * CFrame.new(0, h + 0.06, 0), Vector3.new(0.8, 0.08, 0.8), C.Wood, rng)
	bit(m, base * CFrame.new(1.1, 0.25, 0) * CFrame.Angles(0, 0, math.rad(-20)), Vector3.new(1, 0.5, 0.6), C.TrunkDark, rng)
	bit(m, base * CFrame.new(0, h * 0.5, 0.91), Vector3.new(1.2, h * 0.7, 0.12), W.Moss, rng)
	if rng:chance(0.5) then
		mushroom(m, p - base.RightVector * 1.2 + base.LookVector * 0.6, rng:chance(0.5), 0.75, rng)
	end
	return m
end

-- A fallen log with light end faces, dark hollow cores and a moss patch.
local function log(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("Log", parent)
	local base = yawAt(p, rng)
	local len = rng:range(4.5, 6)
	local d = rng:range(1.3, 1.6)
	bit(m, base * CFrame.new(0, d / 2, 0), Vector3.new(d, d, len), C.Trunk, rng)
	for _, side in { -1, 1 } do
		bit(m, base * CFrame.new(0, d / 2, side * (len / 2 + 0.03)), Vector3.new(d * 0.8, d * 0.8, 0.08), C.WoodLight, rng)
		bit(m, base * CFrame.new(0, d / 2, side * (len / 2 + 0.06)), Vector3.new(d * 0.42, d * 0.42, 0.08), C.TrunkDark)
	end
	bit(m, base * CFrame.new(0.1, d + 0.06, rng:range(-0.8, 0.8)), Vector3.new(d * 0.8, 0.14, len * 0.4), W.Moss, rng)
	return m
end

---------------------------------------------------------------- the kit

Wilds.Pieces = {
	Pebbles = pebbles,
	MossRock = mossRock,
	StandingStone = standingStone,
	TallGrass = function(parent: Instance, p: Vector3, rng: Rng.Rng): Model
		return tallGrass(parent, p, rng, false)
	end,
	FlowerGrass = function(parent: Instance, p: Vector3, rng: Rng.Rng): Model
		return tallGrass(parent, p, rng, true)
	end,
	Tulips = flowerPatch("Tulip"),
	Daisies = flowerPatch("Daisy"),
	Bluebells = flowerPatch("Bluebell"),
	Lavender = flowerPatch("Lavender"),
	Wildflowers = flowerPatch("Wildflowers"),
	BerryBush = dottedBush("Berry"),
	BlossomBush = dottedBush("Blossom"),
	Fern = fern,
	Mushrooms = mushrooms,
	Stump = stump,
	Log = log,
} :: { [string]: Builder }

-- The scatter places small groups ("spots of nature") in one of four themes;
-- each piece of a group is a weighted pick from its theme (Rng.weighted).
Wilds.Themes = {
	Meadow = { TallGrass = 3, FlowerGrass = 2, Daisies = 1, Bluebells = 1, Tulips = 1, Lavender = 1, Wildflowers = 1.5, Pebbles = 0.5 },
	Rocky = { Pebbles = 2, MossRock = 1.5, StandingStone = 0.6, TallGrass = 2, Fern = 1 },
	Woodland = { Stump = 1, Log = 0.8, Mushrooms = 2, Fern = 1.5, BerryBush = 1, TallGrass = 1 },
	Bushy = { BerryBush = 1.5, BlossomBush = 1.5, Wildflowers = 1, TallGrass = 1.5, Pebbles = 0.5 },
} :: { [string]: { [string]: number } }
Wilds.ThemeWeights = { Meadow = 3, Rocky = 2, Woodland = 1.5, Bushy = 1.5 } :: { [string]: number }
-- the free radius each piece needs
Wilds.Radius = {
	Pebbles = 1.8,
	MossRock = 2.6,
	StandingStone = 2,
	TallGrass = 1.4,
	FlowerGrass = 1.4,
	Tulips = 1.7,
	Daisies = 1.7,
	Bluebells = 1.7,
	Lavender = 1.7,
	Wildflowers = 1.7,
	BerryBush = 2,
	BlossomBush = 2,
	Fern = 1.8,
	Mushrooms = 1.2,
	Stump = 1.6,
	Log = 3.2,
} :: { [string]: number }
-- How many pieces at most on the town's lawns and on the mountains' green
-- tops, how many make a group, and how far apart the groups' centers stay.
Wilds.MaxTown = 75
Wilds.MaxMountain = 60
Wilds.GroupSize = { Min = 3, Max = 5 }
Wilds.GroupSpacing = 14
Wilds.GroupReach = 5.5 -- the farthest a group's piece stands from its center
-- Bigger pieces (rocks, logs, stumps) keep out of the plaza views.
Wilds.Big = { MossRock = true, StandingStone = true, Stump = true, Log = true } :: { [string]: boolean }

---------------------------------------------------------------- secrets

-- A lost miner's camp: a canvas tent, a fire ring with glowing embers, a log
-- seat, a crate with a lantern and a pickaxe leaning on the tent.
local function lostCamp(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("LostCamp", parent)
	local base = yawAt(p, rng)
	bit(m, base * CFrame.new(0, 0.06, 0), Vector3.new(7.6, 0.12, 6), C.Dirt, rng)
	-- tent (ridge along X)
	local L, H, Wd = 3.8, 2.6, 3.4
	local tent = base * CFrame.new(-1.6, H / 2, -1.1)
	for _, side in { -1, 1 } do
		local cf = tent * CFrame.new(0, 0, side * Wd / 4) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new())
		Geo.wedge(m, cf, Vector3.new(L, H, Wd / 2), Style.vary(if side < 0 then W.Canvas else W.CanvasDark, rng, 0.04), nil, Style.tiny())
	end
	bit(m, tent * CFrame.new(L / 2 + 0.02, -H * 0.2, 0), Vector3.new(0.08, H * 0.6, Wd * 0.3), C.WoodDark)
	bit(m, tent * CFrame.new(0, H / 2 + 0.05, 0), Vector3.new(L + 0.4, 0.14, 0.14), C.WoodDark)
	-- fire ring
	local fire = base * CFrame.new(1.9, 0, 0.9)
	for i = 1, 6 do
		local a = i * (math.pi / 3)
		bit(
			m,
			fire * CFrame.new(math.cos(a) * 1.05, 0.25, math.sin(a) * 1.05) * CFrame.Angles(0, a, 0),
			Vector3.new(0.6, 0.5, 0.75),
			W.RockDark,
			rng
		)
	end
	for _, a in { 0.5, -0.5 } do
		bit(m, fire * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, a, 0), Vector3.new(0.35, 0.35, 1.6), C.TrunkDark)
	end
	bit(m, fire * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.7, 0.7, 0.7), C.Fire, nil, NEON)
	local core = bit(m, fire * CFrame.new(0, 1.05, 0), Vector3.new(0.4, 0.5, 0.4), C.FireCore, nil, NEON)
	core.Name = "CampFire"
	Style.emitter(core, "Embers", C.Ember, 3)
	-- log seat, crate with a lantern, pickaxe
	bit(m, base * CFrame.new(2, 0.42, 2.55) * CFrame.Angles(0, 0.2, 0), Vector3.new(2.6, 0.85, 0.85), C.Trunk, rng)
	local crate = base * CFrame.new(1.2, 0, -2.2)
	bit(m, crate * CFrame.new(0, 0.7, 0), Vector3.new(1.4, 1.4, 1.4), C.WoodLight, rng)
	bit(m, crate * CFrame.new(0, 0.7, 0), Vector3.new(1.48, 0.26, 1.48), C.WoodDark)
	local glass = bit(m, crate * CFrame.new(0, 1.8, 0), Vector3.new(0.6, 0.75, 0.6), C.LampAmber, nil, NEON)
	glass.Name = "LanternGlow"
	bit(m, crate * CFrame.new(0, 2.25, 0), Vector3.new(0.8, 0.16, 0.8), C.Iron)
	local pick = tent * CFrame.new(L / 2 - 0.6, -H / 2, Wd / 2 + 0.3) * CFrame.Angles(math.rad(-18), 0, 0)
	bit(m, pick * CFrame.new(0, 1.2, 0), Vector3.new(0.2, 2.4, 0.2), C.Wood)
	bit(m, pick * CFrame.new(0, 2.35, 0), Vector3.new(1.7, 0.26, 0.26), C.IronLight)
	return m
end

-- A treasure chest half sunk in a dirt mound, its lid ajar over gold, coins
-- spilled and a spade stuck in the dirt.
local function buriedChest(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("BuriedChest", parent)
	local base = yawAt(p, rng)
	bit(m, base * CFrame.new(0, 0.2, 0), Vector3.new(4.4, 0.4, 3.6), C.Dirt, rng)
	bit(m, base * CFrame.new(0.3, 0.42, 0.2), Vector3.new(3, 0.2, 2.4), C.DirtLight, rng)
	local chest = base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(10))
	bit(m, chest, Vector3.new(2.8, 1.3, 1.8), C.Wood, rng)
	for _, x in { -0.9, 0.9 } do
		bit(m, chest * CFrame.new(x, 0, 0), Vector3.new(0.24, 1.36, 1.86), C.Iron)
	end
	local gold = bit(m, chest * CFrame.new(0, 0.66, 0), Vector3.new(1.8, 0.1, 1), C.Gold, nil, NEON)
	gold.Name = "TreasureGlint"
	local hinge = chest * CFrame.new(0, 0.65, 0.9) * CFrame.Angles(math.rad(-55), 0, 0)
	bit(m, hinge * CFrame.new(0, 0.22, -0.9), Vector3.new(2.8, 0.44, 1.8), C.WoodLight, rng)
	bit(m, hinge * CFrame.new(0, 0.24, -1.78), Vector3.new(0.55, 0.32, 0.12), C.Brass)
	for i = 1, 4 do
		local q = base * CFrame.new(rng:range(-1.8, 1.8), 0.45, rng:range(1, 1.6) * (if i % 2 == 0 then 1 else -1))
		bit(m, q * CFrame.Angles(0, rng:range(0, math.pi), rng:range(-0.3, 0.3)), Vector3.new(0.5, 0.12, 0.5), C.Gold)
	end
	local spade = base * CFrame.new(-2.1, 0, -1.1) * CFrame.Angles(math.rad(12), 0, math.rad(-10))
	bit(m, spade * CFrame.new(0, 1.4, 0), Vector3.new(0.18, 2.4, 0.18), C.Wood)
	bit(m, spade * CFrame.new(0, 0.3, 0), Vector3.new(0.8, 0.9, 0.12), C.IronLight)
	pebbles(m, (base * CFrame.new(-0.6, 0, -2.6)).Position, rng)
	fern(m, (base * CFrame.new(2.6, 0, -1.4)).Position, rng)
	return m
end

-- A fairy ring: eight mushrooms around a little glowing crystal on a stone.
local function fairyRing(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("FairyRing", parent)
	bit(m, CFrame.new(p + Vector3.new(0, 0.05, 0)), Vector3.new(7.2, 0.1, 7.2), C.GrassLight, rng)
	bit(m, CFrame.new(p + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(7.2, 0.1, 7.2), C.GrassLight, rng)
	for i = 1, 8 do
		local a = i * (math.pi / 4) + rng:range(-0.12, 0.12)
		mushroom(m, p + Vector3.new(math.cos(a) * 3, 0.05, math.sin(a) * 3), i % 2 == 0, rng:range(0.9, 1.2), rng)
	end
	bit(m, CFrame.new(p + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0.4, 0), Vector3.new(1.4, 0.7, 1.2), W.RockDark, rng)
	local tip = Style.crystal(m, CFrame.new(p + Vector3.new(0, 0.7, 0)), 2, 0.7, C.CrystalPinkDeep, nil, 0.45)
	tip[1].Name = "FairyCrystal"
	Style.crystal(
		m,
		CFrame.new(p + Vector3.new(0.45, 0.6, 0.2)) * CFrame.Angles(0, 0, math.rad(-25)),
		1.1,
		0.42,
		C.CrystalBlueDeep,
		nil,
		0.45
	)
	return m
end

-- A fossil skeleton half in the dirt: spine, ribs, skull and tail, a brush
-- and a pick left beside it (a hint at the FOSSIL DIG).
local function fossil(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("Fossil", parent)
	local base = yawAt(p, rng)
	bit(m, base * CFrame.new(0, 0.06, 0), Vector3.new(9, 0.12, 4.6), C.DirtLight, rng)
	bit(m, base * CFrame.new(-0.4, 0.08, 0.2), Vector3.new(6.6, 0.12, 3.2), C.Dirt, rng)
	for i = 0, 6 do
		local x = -3 + i * 0.9
		local y = 0.32 + math.sin(i * 0.5) * 0.12
		bit(m, base * CFrame.new(x, y, math.sin(i * 0.7) * 0.25), Vector3.new(0.62, 0.5, 0.55), if i % 2 == 0 then W.Bone else W.BoneDark)
	end
	for i = 0, 2 do
		local x = -1.8 + i * 1.1
		for _, side in { -1, 1 } do
			local rib = base * CFrame.new(x, 0.3, side * 0.95) * CFrame.Angles(math.rad(side * 38), 0, 0)
			bit(m, rib * CFrame.new(0, 0.5, 0), Vector3.new(0.24, 1.35 - i * 0.12, 0.24), W.Bone)
		end
	end
	local skull = base * CFrame.new(3.4, 0.55, 0) * CFrame.Angles(0, 0, math.rad(8))
	bit(m, skull, Vector3.new(1.8, 1, 1.15), W.Bone)
	bit(m, skull * CFrame.new(0.55, -0.55, 0), Vector3.new(1.3, 0.28, 0.9), W.BoneDark)
	for _, side in { -1, 1 } do
		bit(m, skull * CFrame.new(0.1, 0.15, side * 0.58), Vector3.new(0.34, 0.3, 0.06), C.StoneDeep)
	end
	bit(m, skull * CFrame.new(-0.5, 0.65, 0) * CFrame.Angles(0, 0, math.rad(30)), Vector3.new(0.28, 0.7, 0.28), W.BoneDark)
	bit(m, base * CFrame.new(-3.8, 0.22, 0.3) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.2, 0.3, 0.3), W.BoneDark)
	local pick = base * CFrame.new(0.8, 0.15, 1.6) * CFrame.Angles(0, 0.6, 0)
	bit(m, pick, Vector3.new(0.18, 0.18, 2), C.Wood)
	bit(m, pick * CFrame.new(0, 0, -1), Vector3.new(1.2, 0.2, 0.2), C.IronLight)
	bit(m, base * CFrame.new(-1.4, 0.15, -1.7) * CFrame.Angles(0, -0.4, 0), Vector3.new(0.3, 0.16, 1), C.WoodLight)
	return m
end

-- A Kaldrum rune stone: a tall slab with glowing cyan runes, moss and a ring
-- of small stones with two crystal shards.
local function runeStone(parent: Instance, p: Vector3, rng: Rng.Rng): Model
	local m = Style.model("RuneStone", parent)
	local base = yawAt(p, rng)
	local h = 5.6
	local slab = base * CFrame.Angles(0, 0, math.rad(4))
	bit(m, slab * CFrame.new(0, h / 2, 0), Vector3.new(2.4, h, 1.2), W.Rock, rng)
	bit(m, slab * CFrame.new(0, h + 0.3, 0), Vector3.new(1.8, 0.6, 1), W.RockLight, rng)
	bit(m, slab * CFrame.new(0.9, h * 0.25, 0), Vector3.new(0.7, h * 0.5, 1.26), W.MossDark, rng)
	-- runes on both faces
	local runes = {
		{ 0, 4.3, 0.16, 1.1 },
		{ 0, 4.3, 0.9, 0.16 },
		{ -0.4, 3.0, 0.16, 1 },
		{ 0.05, 2.7, 0.95, 0.16 },
		{ 0, 1.75, 0.16, 1 },
		{ 0.3, 1.45, 0.6, 0.16 },
	}
	for _, side in { -1, 1 } do
		local face = slab * CFrame.new(0, 0, side * 0.64)
		for i, r in runes do
			local rune = bit(m, face * CFrame.new(r[1] * -side, r[2], 0), Vector3.new(r[3], r[4], 0.08), W.Rune, nil, NEON)
			if i == 1 and side < 0 then
				rune.Name = "RuneGlow"
			end
		end
	end
	for i = 1, 6 do
		local a = i * (math.pi / 3) + 0.3
		bit(
			m,
			base * CFrame.new(math.cos(a) * 2.8, 0.25, math.sin(a) * 2.8) * CFrame.Angles(0, a, 0),
			Vector3.new(0.8, 0.5, 0.6),
			W.Rock,
			rng
		)
	end
	Style.crystal(m, base * CFrame.new(-1.6, 0, -1.3) * CFrame.Angles(0, 0, math.rad(15)), 1.3, 0.45, C.CrystalBlueDeep, nil, 0.45)
	Style.crystal(m, base * CFrame.new(1.7, 0, -1.1) * CFrame.Angles(0, 0, math.rad(-20)), 0.9, 0.36, C.CrystalBlueDeep, nil, 0.45)
	return m
end

Wilds.Secrets = {
	LostCamp = lostCamp,
	BuriedChest = buriedChest,
	FairyRing = fairyRing,
	Fossil = fossil,
	RuneStone = runeStone,
} :: { [string]: Builder }
Wilds.SecretOrder = { "LostCamp", "BuriedChest", "FairyRing", "Fossil", "RuneStone" }
Wilds.SecretRadius = { LostCamp = 4.4, BuriedChest = 3.6, FairyRing = 4, Fossil = 4.8, RuneStone = 3.4 } :: { [string]: number }
-- Where each secret hides: on the town's lawns near the ground's edge, or on
-- a green mountain top (the lowest free one first).
Wilds.SecretWhere =
	{ LostCamp = "Town", BuriedChest = "Town", Fossil = "Town", FairyRing = "Mountain", RuneStone = "Mountain" } :: { [string]: string }
-- Town secrets sit within this many studs of the town ground's edge; all of them spread apart.
Wilds.SecretEdge = 40
Wilds.SecretSpacing = 60

---------------------------------------------------------------- scatter

local function inBox(p: Vector3, box: { Min: Vector3, Max: Vector3 }, margin: number): boolean
	return p.X > box.Min.X - margin and p.X < box.Max.X + margin and p.Z > box.Min.Z - margin and p.Z < box.Max.Z + margin
end

local function decorate(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end

-- How far `p` is from the town ground's edge.
local function edgeDistance(index: Meadow.Index, p: Vector3): number
	local g = index.Ground
	if not g then
		return math.huge
	end
	return math.min(p.X - g.Min.X, g.Max.X - p.X, p.Z - g.Min.Z, g.Max.Z - p.Z)
end

-- Does the part's flat footprint reach into the square of radius r around p?
local function overlaps(part: BasePart, p: Vector3, r: number): boolean
	local cf, size = part.CFrame, part.Size
	local rv, uv, lv = cf.RightVector, cf.UpVector, cf.LookVector
	local hx = (math.abs(rv.X) * size.X + math.abs(uv.X) * size.Y + math.abs(lv.X) * size.Z) / 2
	local hz = (math.abs(rv.Z) * size.X + math.abs(uv.Z) * size.Y + math.abs(lv.Z) * size.Z) / 2
	local c = cf.Position
	return math.abs(c.X - p.X) < hx + r and math.abs(c.Z - p.Z) < hz + r
end

-- Takes the meadow lawn's tufts, flower beds, bushes and rocks out where a
-- wilds piece now stands (a bush goes as a whole; the flat grass patches stay).
local function clearLawn(lawn: Instance?, p: Vector3, r: number)
	if not lawn then
		return
	end
	local doomed: { Instance } = {}
	for _, child in lawn:GetChildren() do
		if child:IsA("BasePart") then
			if child.Size.Y > 0.15 and overlaps(child, p, r) then
				table.insert(doomed, child)
			end
		else
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") and overlaps(d, p, r) then
					table.insert(doomed, child)
					break
				end
			end
		end
	end
	for _, d in doomed do
		d:Destroy()
	end
end

local function shuffle<T>(list: { T }, rng: Rng.Rng)
	for i = #list, 2, -1 do
		local j = rng:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function spaced(placed: { Vector3 }, p: Vector3, d: number): boolean
	for _, q in placed do
		if (p - q).Magnitude < d then
			return false
		end
	end
	return true
end

-- The green tops of the Land mountains outside the town (the Meadow's
-- mountain trees stand on the same caps).
local function mountainCaps(map: Instance): { BasePart }
	local caps: { BasePart } = {}
	local land = map:FindFirstChild("Land")
	local mountains = land and land:FindFirstChild("Mountains")
	if not mountains then
		return caps
	end
	for _, d in mountains:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			if d.Size.Y <= 1.2 and d.Size.X >= 8 and d.Size.Z >= 8 and c.G > c.R + 0.1 and c.G > c.B + 0.05 then
				local p = d.CFrame.Position
				if not inBox(p, Meadow.Area, 4) then
					table.insert(caps, d)
				end
			end
		end
	end
	table.sort(caps, function(a: BasePart, b: BasePart): boolean
		local pa, pb = a.CFrame.Position, b.CFrame.Position
		return if pa.X ~= pb.X then pa.X < pb.X elseif pa.Z ~= pb.Z then pa.Z < pb.Z else pa.Y < pb.Y
	end)
	return caps
end

local function capTop(cap: BasePart, ox: number, oz: number): Vector3
	return (cap.CFrame * CFrame.new(ox, cap.Size.Y / 2, oz)).Position
end

-- One group around `center`: 3-5 pieces of one theme, the first at the
-- center, the rest around it. `fits` checks a spot for a piece, `after` runs
-- on every piece placed. Returns how many it placed (at most `room`).
local function group(
	parent: Instance,
	center: Vector3,
	rng: Rng.Rng,
	room: number,
	fits: (Vector3, number, string) -> boolean,
	after: (Model, Vector3, number) -> ()
): number
	local theme = Wilds.Themes[rng:weighted(Wilds.ThemeWeights)]
	local want = math.min(room, rng:int(Wilds.GroupSize.Min, Wilds.GroupSize.Max))
	local placed = 0
	local tries = 0
	while placed < want and tries < want * 4 do
		tries += 1
		local name = rng:weighted(theme)
		local r = Wilds.Radius[name]
		local q = center
		if tries > 1 then
			local a = rng:range(0, math.pi * 2)
			local d = rng:range(2.4, Wilds.GroupReach)
			q = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		end
		if fits(q, r, name) then
			after(Wilds.Pieces[name](parent, q, rng), q, r)
			placed += 1
		elseif tries == 1 then
			return 0
		end
	end
	return placed
end

-- Builds the wilds into Emberfall.Lobby.Flora (or the map), after the Meadow.
-- Returns the model and where each secret went ({ [name]: Vector3 }).
function Wilds.build(map: Instance, rng: Rng.Rng): (Model, { [string]: Vector3 })
	local emberfall = map:FindFirstChild("Emberfall")
	local lobby = emberfall and emberfall:FindFirstChild("Lobby")
	local flora = lobby and lobby:FindFirstChild("Flora")
	local meadow = flora and flora:FindFirstChild("Meadow")
	local lawn = meadow and meadow:FindFirstChild("Lawn")
	local m = Style.model("Wilds", flora or map)
	local index = Meadow.index(map, lawn)

	-- every free lawn spot on the town ground, shuffled (the secrets may use the
	-- strip by the quarry beyond the meadow's area; the pieces keep to the area)
	local ground = index.Ground or Meadow.Area
	local spots: { Vector3 } = {}
	local x = ground.Min.X + 2
	while x < ground.Max.X - 2 do
		local z = ground.Min.Z + 2
		while z < ground.Max.Z - 2 do
			local p = Vector3.new(x + rng:range(-1.2, 1.2), 0, z + rng:range(-1.2, 1.2))
			if Meadow.allowed(p, 1.2, ground) and Meadow.free(index, p, 1.2, 3) then
				table.insert(spots, p)
			end
			z += 3
		end
		x += 3
	end
	shuffle(spots, rng)
	local caps = mountainCaps(map)
	shuffle(caps, rng)

	-- the secrets first
	local secrets = Style.model("Secrets", m)
	local found: { [string]: Vector3 } = {}
	local taken: { Vector3 } = {}
	local low = table.clone(caps)
	table.sort(low, function(a: BasePart, b: BasePart): boolean
		return a.CFrame.Position.Y < b.CFrame.Position.Y
	end)
	local function townSpot(r: number, spacing: number): Vector3?
		for _, p in spots do
			if
				spaced(taken, p, spacing)
				and edgeDistance(index, p) < Wilds.SecretEdge
				and not inBox(p, Meadow.Core, r + 6)
				and not inBox(p, Meadow.ForgeBack, r)
				and not inBox(p, Meadow.VaultZone, r)
				and Meadow.allowed(p, r, ground)
				and Meadow.free(index, p, r, 7)
			then
				return p
			end
		end
		return nil
	end
	local function mountainSpot(r: number, spacing: number): Vector3?
		for _, cap in low do
			if math.min(cap.Size.X, cap.Size.Z) / 2 >= r + 0.5 then
				local p = capTop(cap, 0, 0)
				if spaced(taken, p, spacing) and not WorldLayout.isKeepOut(p, r) and Meadow.freeBand(index, p, r, p.Y + 0.05, p.Y + 7) then
					return p
				end
			end
		end
		return nil
	end
	-- the biggest first; where the drawn place has no room left, closer to the
	-- others, then the other kind of place
	local order = table.clone(Wilds.SecretOrder)
	table.sort(order, function(a: string, b: string): boolean
		return Wilds.SecretRadius[a] > Wilds.SecretRadius[b]
	end)
	for _, name in order do
		local r = Wilds.SecretRadius[name]
		local town = Wilds.SecretWhere[name] == "Town"
		local at: Vector3? = nil
		for _, spacing in { Wilds.SecretSpacing, Wilds.SecretSpacing / 2 } do
			at = at or (if town then townSpot(r, spacing) else mountainSpot(r, spacing))
		end
		at = at or (if town then mountainSpot(r, Wilds.SecretSpacing / 2) else townSpot(r, Wilds.SecretSpacing / 2))
		if at then
			local s = Wilds.Secrets[name](secrets, at, Rng.new(`Wilds/{name}/{rng:nextU32()}`))
			Meadow.track(index, s)
			clearLawn(lawn, at, r)
			found[name] = at
			table.insert(taken, at)
		end
	end

	-- then groups of pieces on the town's lawns, more of them toward the edges
	local pieces = Style.model("Pieces", m)
	local centers: { Vector3 } = {}
	local count = 0
	for _, p in spots do
		if count >= Wilds.MaxTown then
			break
		end
		local edge = math.clamp(1 - edgeDistance(index, p) / 40, 0, 1)
		if rng:next() > 0.4 + 0.6 * edge or not spaced(centers, p, Wilds.GroupSpacing) then
			continue
		end
		local placed = group(pieces, p, rng, Wilds.MaxTown - count, function(q: Vector3, r: number, name: string): boolean
			return not (Wilds.Big[name] and inBox(q, Meadow.Core, r + 4)) and Meadow.allowed(q, r) and Meadow.free(index, q, r, 4)
		end, function(piece: Model, q: Vector3, r: number)
			Meadow.track(index, piece)
			clearLawn(lawn, q, r)
		end)
		if placed > 0 then
			table.insert(centers, p)
			count += placed
		end
	end

	-- and on the mountains' green tops: a group or two per cap
	local high = Style.model("Mountains", m)
	count = 0
	for _, cap in caps do
		if count >= Wilds.MaxMountain then
			break
		end
		local groups = if cap.Size.X * cap.Size.Z > 400 then 2 else 1
		for _ = 1, groups do
			local hx, hz = cap.Size.X / 2 - 2.5, cap.Size.Z / 2 - 2.5
			if hx <= 0 or hz <= 0 or count >= Wilds.MaxMountain then
				continue
			end
			local p = capTop(cap, rng:range(-hx, hx), rng:range(-hz, hz))
			if not spaced(centers, p, Wilds.GroupSpacing) then
				continue
			end
			local frame = cap.CFrame
			local placed = group(high, p, rng, Wilds.MaxMountain - count, function(q: Vector3, r: number, _name: string): boolean
				local l = frame:PointToObjectSpace(q)
				return math.abs(l.X) < cap.Size.X / 2 - r - 0.3
					and math.abs(l.Z) < cap.Size.Z / 2 - r - 0.3
					and not WorldLayout.isKeepOut(q, r)
					and Meadow.freeBand(index, q, r, q.Y + 0.05, q.Y + 4)
			end, function(piece: Model, _q: Vector3, _r: number)
				Meadow.track(index, piece)
			end)
			if placed > 0 then
				table.insert(centers, p)
				count += placed
			end
		end
	end
	decorate(m)
	return m, found
end

return Wilds
