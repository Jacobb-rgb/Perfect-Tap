--[[
	Flora scatter (LOBBY_PLAN 6.5 items 11-13): colorful voxel trees,
	bushes, flower patches and boulders placed with LobbyLayout.isFree (so
	never on roads, paths, plots, the bases' yards, outcrops or set pieces),
	plus the fences along the creek, ponds and side paths and the garden
	lanterns at the path junctions.

	Sight lines: no tree crown within 6 studs of the south road between
	z 36 and 100; nothing taller than 12 within 10 studs of the plaza curb.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Water = require(script.Parent.Water)
local Buildings = require(script.Parent.Buildings)

local C = Style.C

local Scatter = {}

-- (flowers, bushes and boulders were cut to pay for the town buildings' parts)
Scatter.Limits = { Trees = 45, Bushes = 20, Flowers = 8, Boulders = 3 }

-- No scattered trees here: they would hide the ponds, the creek and the
-- bridge, the corridor from the plaza to the bridge, or the LAB shopfront
-- and the ROCK SCANNER (hero camera views).
Scatter.TreeFreeBoxes = {
	{ Min = Vector2.new(-44, 52), Max = Vector2.new(44, 92) },
	{ Min = Vector2.new(-12, 28), Max = Vector2.new(32, 52) },
	{ Min = Vector2.new(26, 84), Max = Vector2.new(58, 100) },
}

local function treeFree(p: Vector3): boolean
	for _, box in Scatter.TreeFreeBoxes do
		if p.X >= box.Min.X and p.X <= box.Max.X and p.Z >= box.Min.Y and p.Z <= box.Max.Y then
			return false
		end
	end
	return true
end

type Zone = {
	Name: string,
	Min: Vector2, -- x, z
	Max: Vector2,
	Trees: number,
	Full: boolean?, -- full Style.tree (near the hero camera) instead of lean trees
}

-- Where trees go, in order (each zone gets up to `Trees`).
Scatter.Zones = {
	-- foreground and the strips along the plot roads (the hero view)
	{ Name = "Front", Min = Vector2.new(-66, 20), Max = Vector2.new(66, 82), Trees = 9, Full = true },
	{ Name = "Middle", Min = Vector2.new(-66, -60), Max = Vector2.new(66, 20), Trees = 6 },
	-- behind the forge and the stalls
	{ Name = "Back", Min = Vector2.new(-66, -112), Max = Vector2.new(66, -60), Trees = 12 },
	-- south foreground (lobby_south view)
	{ Name = "South", Min = Vector2.new(-66, 86), Max = Vector2.new(66, 146), Trees = 7 },
	-- the island's south corners beyond the bases
	{ Name = "Corners", Min = Vector2.new(-166, 112), Max = Vector2.new(166, 146), Trees = 5 },
} :: { Zone }

local KIND_WEIGHTS = { Green = 45, Pink = 15, Red = 12, Yellow = 14, Orange = 14 }

-- Tree kind with a regional tint: autumn colors in the south-west (toward
-- the mine and the autumn corner), pink near the cherry grove.
local function treeKind(rng: Rng.Rng, p: Vector3): string
	local w: { [string]: number } = table.clone(KIND_WEIGHTS)
	if p.X < -36 and p.Z > 36 then
		-- the concept's yellow/orange foreground corner (bottom left of the hero view)
		w.Yellow *= 2.5
		w.Orange *= 2.5
		w.Pink *= 0.3
		w.Red *= 0.5
	elseif p.X > 24 and p.Z < -40 then
		w.Pink *= 2
		w.Yellow *= 0.6
	end
	return rng:weighted(w)
end

local BUSH_COLORS = { C.LeafGreen, C.LeafGreenDark, C.LeafGreenLight, C.LeafGreen, C.FlowerPurple, C.LeafPink, C.LeafRed, C.LeafOrange }
local FLOWER_COLORS = { C.FlowerYellow, C.FlowerWhite, C.FlowerPurple, C.FlowerPink, C.FlowerRed, C.FlowerBlue }

local function randomIn(rng: Rng.Rng, zone: Zone): Vector3
	return Vector3.new(rng:range(zone.Min.X, zone.Max.X), 0, rng:range(zone.Min.Y, zone.Max.Y))
end

type Counts = { Trees: number, Bushes: number, Flowers: number, Boulders: number }

local function bush(m: Instance, placer: Kit.Placer, counts: Counts, p: Vector3, rng: Rng.Rng, color: Color3?): boolean
	if counts.Bushes >= Scatter.Limits.Bushes or not Kit.free(placer, p, 1.8) then
		return false
	end
	Kit.take(placer, p, 1.8)
	Style.bush(m, p, color or rng:pick(BUSH_COLORS), rng, rng:range(2, 3))
	counts.Bushes += 1
	return true
end

local function flowers(m: Instance, placer: Kit.Placer, counts: Counts, p: Vector3, rng: Rng.Rng): boolean
	if counts.Flowers >= Scatter.Limits.Flowers or not Kit.free(placer, p, 2) then
		return false
	end
	Kit.take(placer, p, 1.6)
	Kit.flowerPatch(m, p, rng:pick(FLOWER_COLORS), rng, rng:int(3, 4))
	counts.Flowers += 1
	return true
end

local function trees(m: Instance, placer: Kit.Placer, counts: Counts, rng: Rng.Rng)
	for _, zone in Scatter.Zones do
		local placed = 0
		local tries = 0
		while placed < zone.Trees and tries < 900 and counts.Trees < Scatter.Limits.Trees do
			tries += 1
			local p = randomIn(rng, zone)
			local scale = rng:range(0.85, 1.14)
			local reach = Kit.treeReach(scale)
			if not Kit.treeAllowed(p, reach, Kit.treeHeight(scale)) then
				-- near the plaza curb only small trees (<= 12 tall)
				scale = 0.8
				reach = Kit.treeReach(scale)
			end
			if treeFree(p) and Kit.treeAllowed(p, reach, Kit.treeHeight(scale)) and Kit.free(placer, p, 3.6 * scale, reach) then
				Kit.take(placer, p, reach * 0.8)
				local kind = treeKind(rng, p)
				local base = CFrame.new(p)
				if zone.Full then
					Style.tree(m, base, kind, rng, scale)
				else
					Kit.leanTree(m, base, kind, rng, scale)
				end
				placed += 1
				counts.Trees += 1
				-- a bush at its feet
				local a = rng:range(0, math.pi * 2)
				local d = reach + rng:range(0.5, 2.5)
				if rng:chance(0.45) then
					bush(m, placer, counts, p + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), rng)
				end
			end
		end
	end
end

-- Fill the hero foreground and the south meadow with flowers, bushes, boulders.
local function groundCover(m: Instance, placer: Kit.Placer, counts: Counts, rng: Rng.Rng)
	local banks = { Name = "Cover", Min = Vector2.new(-44, 66), Max = Vector2.new(44, 98), Trees = 0 }
	local front = { Name = "Cover", Min = Vector2.new(-64, 24), Max = Vector2.new(64, 82), Trees = 0 }
	local middle = { Name = "Cover", Min = Vector2.new(-64, -110), Max = Vector2.new(64, 24), Trees = 0 }
	local south = { Name = "Cover", Min = Vector2.new(-150, 84), Max = Vector2.new(150, 146), Trees = 0 }
	local plan = {
		{ zone = banks, flowers = 6, bushes = 4, boulders = 2 },
		{ zone = front, flowers = 2, bushes = 4, boulders = 1 },
		{ zone = middle, flowers = 0, bushes = 2, boulders = 0 },
		{ zone = south, flowers = 0, bushes = 6, boulders = 0 },
	}
	for _, step in plan do
		local zone = step.zone :: Zone
		local f, b, r = 0, 0, 0
		for _ = 1, 700 do
			if f >= step.flowers and b >= step.bushes and r >= step.boulders then
				break
			end
			local p = randomIn(rng, zone)
			local roll = rng:next()
			if roll < 0.55 and f < step.flowers then
				if flowers(m, placer, counts, p, rng) then
					f += 1
				end
			elseif roll < 0.85 and b < step.bushes then
				if bush(m, placer, counts, p, rng) then
					b += 1
				end
			elseif r < step.boulders and counts.Boulders < Scatter.Limits.Boulders then
				local size = rng:range(2.2, 3.6)
				if Kit.free(placer, p, size * 0.7 + 0.5) then
					Kit.take(placer, p, size * 0.7)
					Style.boulder(m, p, size, rng)
					counts.Boulders += 1
					r += 1
				end
			end
		end
	end
end

-- A capped fence; `lamps` puts lamp boxes on its first and/or last post.
local function fence(m: Instance, from: Vector3, to: Vector3, lampFrom: boolean?, lampTo: boolean?)
	Style.fence(m, from, to, { Caps = true, Height = 2.8, PostEvery = 4.5 })
	if lampFrom then
		Kit.lampBox(m, CFrame.new(from + Vector3.new(0, 3.1, 0)), 0.7, false)
	end
	if lampTo then
		Kit.lampBox(m, CFrame.new(to + Vector3.new(0, 3.1, 0)), 0.7, false)
	end
end

local function fences(m: Instance, placer: Kit.Placer)
	local lily = LobbyLayout.get("LilyPond")
	local koi = LobbyLayout.get("KoiPond")
	-- creek banks between the bridge and the ponds (gap at the bridge), lamps by the bridge
	local zs = { Water.CreekMinZ - 1.8, Water.CreekMaxZ + 1.8 }
	for _, z in zs do
		for _, side in { -1, 1 } do
			local inner = Vector3.new(side * 6.9, 0, z)
			local outer = Vector3.new(side * 13.2, 0, z)
			fence(m, inner, outer, true, false)
		end
	end
	-- the ponds' outer ends
	local lx = lily.Center.X - lily.Size.X / 2 - 1.8
	fence(m, Vector3.new(lx, 0, lily.Center.Z - 5.5), Vector3.new(lx, 0, lily.Center.Z + 5.5))
	local kx = koi.Center.X + koi.Size.X / 2 + 1.8
	fence(m, Vector3.new(kx, 0, koi.Center.Z - 4), Vector3.new(kx, 0, koi.Center.Z + 3.4)) -- ends before the LAB
	-- one side of ToScanner (north) and of ToMine (north)
	fence(m, Vector3.new(9.5, 0, 75.4), Vector3.new(38, 0, 75.4)) -- ends before the LAB shopfront
	fence(m, Vector3.new(-33, 0, 80.4), Vector3.new(-9.5, 0, 80.4))
	-- keep the scatter off the fence lines
	for x = 9.5, 38, 3 do
		Kit.take(placer, Vector3.new(x, 0, 75.4), 1)
	end
	for x = -33, -9.5, 3 do
		Kit.take(placer, Vector3.new(x, 0, 80.4), 1)
	end
	for z = lily.Center.Z - 6, lily.Center.Z + 6, 3 do
		Kit.take(placer, Vector3.new(lx, 0, z), 1)
		Kit.take(placer, Vector3.new(kx, 0, z), 1)
	end
end

-- Post lanterns at the path junctions (lights where people gather); a
-- deeper amber than C.Lamp so they glow warm and never blow out white.
Scatter.LanternColor = Color3.fromRGB(255, 165, 70)
Scatter.Lanterns = {
	{ At = Vector3.new(7.6, 0, 75.4), Yaw = math.pi / 2, Light = true }, -- ToScanner meets the south road
	{ At = Vector3.new(-7.6, 0, 80.4), Yaw = -math.pi / 2, Light = true }, -- ToMine meets the south road
	{ At = Vector3.new(78, 0, -120.2), Yaw = math.pi / 2, Light = false }, -- ToNextArea leaves the plot road
	{ At = Vector3.new(-35, 0, 111), Yaw = -math.pi / 2, Light = true }, -- by the autumn corner
}

--[[
	Post lantern (concept v1): a dark wooden post with a cap and an arm, a
	small deep-amber lamp in a dark metal cage hanging from the arm (no
	white blob up close), optionally a PointLight. 7 parts.
]]
local function postLantern(parent: Instance, base: CFrame, h: number, light: boolean)
	local m = Style.model("Lantern", parent)
	Style.block(m, base * CFrame.new(0, h / 2, 0), Vector3.new(0.7, h, 0.7), C.WoodDark)
	Style.block(m, base * CFrame.new(0, h + 0.15, 0), Vector3.new(1, 0.3, 1), C.Wood, nil, Style.tiny())
	Style.block(m, base * CFrame.new(0, h - 0.4, -0.9), Vector3.new(0.35, 0.35, 2.2), C.WoodDark, nil, Style.tiny())
	local glow = Buildings.cagedLamp(m, base * CFrame.new(0, h - 1.1, -1.7), 1.4)
	glow.Color = Scatter.LanternColor
	if light then
		Style.light(glow, Scatter.LanternColor, 16, 1.3)
	end
	m.PrimaryPart = glow
end

local function lanterns(m: Instance, placer: Kit.Placer)
	for _, l in Scatter.Lanterns do
		postLantern(m, CFrame.new(l.At) * CFrame.Angles(0, l.Yaw, 0), 7, l.Light)
		Kit.take(placer, l.At, 1.2)
	end
end

-- `keepOut`: rectangles (the town building sites) the scatter must stay clear of.
function Scatter.build(parent: Instance, rng: Rng.Rng, keepOut: { Kit.Box }?)
	local placer = Kit.newPlacer(keepOut)
	local fenceModel = Style.model("Fences", parent)
	fences(fenceModel, placer)
	local lanternModel = Style.model("GardenLanterns", parent)
	lanterns(lanternModel, placer)
	local m = Style.model("Scatter", parent)
	local counts: Counts = { Trees = 0, Bushes = 0, Flowers = 0, Boulders = 0 }
	trees(m, placer, counts, Kit.sub(rng))
	groundCover(m, placer, counts, Kit.sub(rng))
	m:SetAttribute("Trees", counts.Trees)
	m:SetAttribute("Bushes", counts.Bushes)
	m:SetAttribute("Flowers", counts.Flowers)
	m:SetAttribute("Boulders", counts.Boulders)
end

return Scatter
