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

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Buildings = require(script.Parent.Buildings)

local C = Style.C

local Scatter = {}

-- (plain bushes and boulders were cut: they read as loose cubes; the lawn
-- gaps get garden beds, short fence runs and crates instead, see gardens)
-- (round 2: 38 trees: the town-edge belts got an inner row, the budget went there)
Scatter.Limits = { Trees = 34, Bushes = 8, Flowers = 8, Boulders = 0 }

-- No scattered trees here: they would hide the ponds, the creek and the
-- bridge, the corridor from the plaza to the bridge, the CAPSULES module
-- (the ground between it and the lily pond, so it shows from lobby_hero
-- like in concept v2), or the LAB shopfront and the ROCK SCANNER (hero
-- camera views).
Scatter.TreeFreeBoxes = {
	{ Min = Vector2.new(-44, 52), Max = Vector2.new(44, 92) },
	{ Min = Vector2.new(-26, 28), Max = Vector2.new(26, 52) }, -- the koi pond and the bridge
	{ Min = Vector2.new(-58, 4), Max = Vector2.new(-12, 52) }, -- CAPSULES, its front and the lily pond
	{ Min = Vector2.new(28, 60), Max = Vector2.new(58, 86) },
	-- the FOSSIL DIG's keep-out strip: between the pit and the hero camera
	-- (and the HALL OF FAME beside it)
	{ Min = Vector2.new(20, 18), Max = Vector2.new(66, 64) },
	-- the SPIN & WIN wheel's silhouette (behind the ring and beside its sign)
	-- and its stair base (the Smithy's old spot behind the SHOP stays open)
	{ Min = Vector2.new(-72, -112), Max = Vector2.new(-24, -38) },
	-- the MINE's portal, its yard and lane in the south-west corner (seen
	-- from the hero camera over the Blaster Vault)
	{ Min = Vector2.new(-92, 116), Max = Vector2.new(-58, 149) },
	-- the MINE hill itself (x -110..-88, z 121..151) and a crown's reach +
	-- 2 studs to the west: its voxel rock top must not sink into autumn
	-- crowns; the autumn woods frame it from the west and the south
	{ Min = Vector2.new(-118, 117), Max = Vector2.new(-88, 151) },
	-- the MAP tower's and the WORKS' fronts in the south-east hamlet and the
	-- hamlet lane (the hero camera sees them from the south-west); trees
	-- along the island's south edge behind it stay under the sight lines
	{ Min = Vector2.new(76, 113), Max = Vector2.new(112, 138) },
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

-- Where trees go, in order (each zone gets up to `Trees`). The wide
-- concept v2 stalls leave little free ground in the Front and Middle
-- zones, so the Back, South and Corners zones carry more of the trees.
Scatter.Zones = {
	-- foreground and the strips along the plot roads (the hero view)
	{ Name = "Front", Min = Vector2.new(-66, 20), Max = Vector2.new(66, 82), Trees = 9, Full = true },
	{ Name = "Middle", Min = Vector2.new(-66, -60), Max = Vector2.new(66, 20), Trees = 6 },
	-- behind the forge and the stalls
	{ Name = "Back", Min = Vector2.new(-66, -112), Max = Vector2.new(66, -60), Trees = 15 },
	-- south foreground (lobby_south view; the Blaster Vault and its jungle
	-- trees fill most of it now)
	{ Name = "South", Min = Vector2.new(-66, 86), Max = Vector2.new(66, 146), Trees = 4 },
	-- the island's south corners beyond the bases: the autumn woods round the
	-- MINE in the west, the MAP hamlet in the east (off the coastal railway's
	-- portal hills at |x| 160+)
	{ Name = "SouthWest", Min = Vector2.new(-150, 112), Max = Vector2.new(-60, 146), Trees = 12 },
	{ Name = "SouthEast", Min = Vector2.new(60, 112), Max = Vector2.new(150, 146), Trees = 10 },
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
	if counts.Bushes >= Scatter.Limits.Bushes or not Kit.free(placer, p, 2.3) then
		return false
	end
	Kit.take(placer, p, 1.8)
	Style.bush(m, p, color or rng:pick(BUSH_COLORS), rng, rng:range(2, 3))
	counts.Bushes += 1
	return true
end

local function flowers(m: Instance, placer: Kit.Placer, counts: Counts, p: Vector3, rng: Rng.Rng): boolean
	if counts.Flowers >= Scatter.Limits.Flowers or not Kit.free(placer, p, 2.5) then
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
				local kind = treeKind(rng, p)
				local base = CFrame.new(p)
				local tree = if zone.Full then Style.tree(m, base, kind, rng, scale) else Kit.leanTree(m, base, kind, rng, scale)
				-- the whole tree keeps off the stalls (fences, walls, signs) and their clear aprons
				if not Kit.clearOfStalls(tree) then
					tree:Destroy()
					continue
				end
				Kit.take(placer, p, reach * 0.8)
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
		{ zone = banks, flowers = 6, bushes = 2, boulders = 0 },
		{ zone = front, flowers = 2, bushes = 1, boulders = 0 },
		{ zone = middle, flowers = 0, bushes = 1, boulders = 0 },
		{ zone = south, flowers = 0, bushes = 3, boulders = 0 },
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

-- The fence runs: the koi pond's bank east of the bridge (the run along the
-- old ToMine path went with the MINE; the Blaster Vault stands there). Every
-- run marks its line taken, so the scatter keeps half a stud off it.
Scatter.FenceRuns = {
	{ From = Vector3.new(7.8, 0, 63.6), To = Vector3.new(18.5, 0, 63.6), LampFrom = true },
} :: { { From: Vector3, To: Vector3, LampFrom: boolean?, LampTo: boolean? } }

local function fences(m: Instance, placer: Kit.Placer)
	for _, run in Scatter.FenceRuns do
		fence(m, run.From, run.To, run.LampFrom, run.LampTo)
		local length = (run.To - run.From).Magnitude
		for t = 0, length, 2 do
			Kit.take(placer, run.From:Lerp(run.To, t / length), 1.3)
		end
		Kit.take(placer, run.To, 1.3)
	end
end

--[[
	Garden corners for the bare lawn gaps (concept v1: the town is full of
	little gardens): south of the HALL OF FAME, between CAPSULES and the
	plaza, and on the lawns either side of the koi pond: flower beds (a
	leafy box with three flower cubes), short capped fence runs, crates and
	dark bushes. Each item only where the ground is free (Kit.free).
]]
export type GardenItem = { Kind: string, At: Vector3, Color: Color3?, To: Vector3? }
Scatter.Gardens = {
	-- the lawn between the lily pond and the west statue of the Blaster Vault
	{ Kind = "Bed", At = Vector3.new(-31, 0, 56), Color = C.FlowerYellow },
	{ Kind = "Bed", At = Vector3.new(-36, 0, 62), Color = C.FlowerWhite },
	{ Kind = "Bush", At = Vector3.new(-28, 0, 63), Color = C.LeafGreenDark },
	{ Kind = "Fence", At = Vector3.new(-46, 0, 53.5), To = Vector3.new(-33, 0, 53.5) },
	-- the lawn south of the koi pond, east of the bridge
	{ Kind = "Bed", At = Vector3.new(13, 0, 67.5), Color = C.FlowerPink },
	{ Kind = "Crate", At = Vector3.new(19.5, 0, 68.5) },
	-- beside the HALL OF FAME
	{ Kind = "Bed", At = Vector3.new(36.5, 0, 63), Color = C.FlowerYellow },
	{ Kind = "Bush", At = Vector3.new(19.5, 0, 38), Color = C.LeafGreenDark },
} :: { GardenItem }

local function gardens(m: Instance, placer: Kit.Placer, rng: Rng.Rng)
	for _, item in Scatter.Gardens do
		local p = item.At
		if item.Kind == "Fence" then
			local to = item.To or p
			local length = (to - p).Magnitude
			local free = true
			for t = 0, length, 1.5 do
				free = free and Kit.free(placer, p:Lerp(to, t / length), 0.9)
			end
			if free and Kit.free(placer, to, 0.9) then
				Style.fence(m, p, to, { Caps = true, Height = 2.4, PostEvery = 4, Rails = 2 })
				for t = 0, length, 2 do
					Kit.take(placer, p:Lerp(to, t / length), 1.3)
				end
			end
		elseif item.Kind == "Bed" then
			if Kit.free(placer, p, 2) then
				Kit.take(placer, p, 2)
				local at = CFrame.new(p) * CFrame.Angles(0, rng:range(-0.2, 0.2), 0)
				Style.block(
					m,
					at * CFrame.new(0, 0.25, 0),
					Vector3.new(3.0, 0.5, 1.4),
					Style.vary(C.LeafGreenDark, rng, 0.04),
					nil,
					Style.tiny()
				)
				Style.block(m, at * CFrame.new(0, 0.12, 0), Vector3.new(3.3, 0.24, 1.7), C.WoodDark, nil, Style.tiny())
				for i = -1, 1 do
					local k = rng:range(0.55, 0.7)
					Style.block(
						m,
						at * CFrame.new(i * 0.95, 0.5 + k / 2, rng:range(-0.2, 0.2)),
						Vector3.new(k, k, k),
						Style.vary(item.Color or C.FlowerYellow, rng, 0.05),
						nil,
						Style.tiny()
					)
				end
			end
		elseif item.Kind == "Bush" then
			if Kit.free(placer, p, 2) then
				Kit.take(placer, p, 2)
				Style.bush(m, p, item.Color or C.LeafGreenDark, rng, 2.2)
			end
		elseif item.Kind == "Crate" then
			if Kit.free(placer, p, 1.6) then
				Kit.take(placer, p, 1.6)
				Style.crate(m, CFrame.new(p), rng, 1.6)
			end
		end
	end
end

-- Post lanterns at the path junctions (lights where people gather); a
-- deeper amber than C.Lamp so they glow warm and never blow out white.
Scatter.LanternColor = C.LampAmber
Scatter.Lanterns = {
	-- (the Blaster Vault: a pair at the end of the south road, either side of
	-- the vault's steps, the east one where ToScanner leaves the road)
	{ At = Vector3.new(7.4, 0, 77.0), Yaw = math.pi / 2, Light = true },
	{ At = Vector3.new(-7.4, 0, 77.0), Yaw = -math.pi / 2, Light = true },
	{ At = Vector3.new(78, 0, -120.2), Yaw = math.pi / 2, Light = false }, -- ToNextArea leaves the plot road
	-- (the Plaza lights the MINE lane where it leaves the west plot road)
	-- the hamlet lane (LobbyLayout HamletLane) where it leaves the east plot
	-- road's end for the MAP hamlet, its arm over the lane
	{ At = Vector3.new(72.5, 0, 127.5), Yaw = -0.705, Light = false },
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
	gardens(Style.model("Gardens", parent), placer, Kit.sub(rng))
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
