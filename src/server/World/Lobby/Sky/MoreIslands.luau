--[[
	More floating islands round the map (owner 2026-10-21: "more of those
	levitating islands, they're mega cool"). Six themes, all outside the lobby
	area (they float over the sea and behind the mountains), every one in the
	"Lod" streaming mode like the west and east islands (phones get a proxy
	from afar), no collisions, no lights (neon only).

	  CrystalIsle   north-west: giant glowing crystal clusters, hovering shards
	  BlossomIsle   south-west: pink blossom trees, a red shrine gate, a stone
	                lantern and a waterfall
	  WindmillIsle  south-east: a voxel windmill over striped flower fields
	  LavaIsle      high over the forge mountains: dark rock, a lava pool, a
	                lava fall, a glowing anvil and a smoking hut
	  TwinIslets    east: two islets joined by a plank rope bridge with lanterns
	  JungleIsle    north-east, the highest: a big jungle tree, vines, a waterfall

	Each island's frame looks at the plaza, so its front (and its waterfall)
	faces the town.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Meadow = require(script.Parent.Parent.Flora.Meadow)

local C = Style.C
local NEON = Enum.Material.Neon

local MoreIslands = {}

-- ground points (the top of each island's grass)
MoreIslands.Spots = {
	CrystalIsle = Vector3.new(-232, 92, -34),
	BlossomIsle = Vector3.new(-214, 74, 118),
	WindmillIsle = Vector3.new(224, 84, 120),
	LavaIsle = Vector3.new(-44, 182, -318),
	TwinIslets = Vector3.new(240, 60, 8),
	JungleIsle = Vector3.new(206, 150, -156),
}

local LAVA = Color3.fromRGB(255, 110, 30)
local LAVA_HOT = Color3.fromRGB(255, 200, 80)
local ROCK_DARK = Color3.fromRGB(52, 44, 52)

-- the island's frame: at its ground point, its front toward the plaza
local function frameAt(at: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(0, at.Y, 0))
end

local function far(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	Style.streaming(m, "Lod")
end

local function tree(m: Model, frame: CFrame, at: Vector3, kind: string, rng: Rng.Rng, scale: number)
	Style.tree(m, frame * CFrame.new(at), kind, rng, scale)
end

local function vines(m: Model, frame: CFrame, w: number, d: number, rng: Rng.Rng, count: number)
	for i = 1, count do
		local side = (i - 1) % 4
		local len = rng:range(3, 8)
		local at = if side == 0
			then Vector3.new(rng:range(-w * 0.4, w * 0.4), -1.5 - len / 2, -d / 2 - 0.3)
			elseif side == 1 then Vector3.new(w / 2 + 0.3, -1.5 - len / 2, rng:range(-d * 0.4, d * 0.4))
			elseif side == 2 then Vector3.new(-w / 2 - 0.3, -1.5 - len / 2, rng:range(-d * 0.4, d * 0.4))
			else Vector3.new(rng:range(-w * 0.4, w * 0.4), -1.5 - len / 2, d / 2 + 0.3)
		Kit.box(m, frame, at, Vector3.new(rng:range(0.8, 1.4), len, rng:range(0.8, 1.4)), Style.vary(C.LeafGreenDark, rng, 0.06))
	end
end

-- a stream across the island's top to its front edge and a fall off it
local function waterfall(m: Model, frame: CFrame, x: number, d: number, height: number, width: number, rng: Rng.Rng)
	Kit.box(m, frame, Vector3.new(x, 0.12, -d / 4), Vector3.new(width - 1.5, 0.3, d / 2), C.Water, nil, Kit.far({ Transparency = 0.15 }))
	Kit.skyFall(m, frame * CFrame.new(x, -0.4, -d / 2 - 0.5), height, width, rng)
end

---------------------------------------------------------------- the islands

local function crystalIsle(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("CrystalIsle", parent)
	local frame = frameAt(MoreIslands.Spots.CrystalIsle)
	local w, d = 24, 20
	Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 30, Tiers = 5 })
	Style.crystalCluster(m, frame * CFrame.new(-3, 0, 1), 11, C.CrystalPurple, rng, { Count = 4 })
	Style.crystalCluster(m, frame * CFrame.new(5, 0, -3), 8, C.CrystalCyan, rng, { Count = 3 })
	Style.crystalCluster(m, frame * CFrame.new(-7, 0, -6), 6, C.CrystalPink, rng, { Count = 3 })
	-- crystals growing out of the rock underneath, and shards hovering over the top
	Style.crystalCluster(m, frame * CFrame.new(2, -12, 0) * CFrame.Angles(math.pi, 0, 0), 6, C.CrystalCyan, rng, { Count = 2 })
	for i = 1, 4 do
		local a = i * math.pi / 2 + rng:range(-0.3, 0.3)
		local at = frame
			* CFrame.new(math.cos(a) * 8, rng:range(9, 14), math.sin(a) * 7)
			* CFrame.Angles(rng:range(-0.4, 0.4), a, rng:range(-0.4, 0.4))
		Style.crystal(m, at, rng:range(2.2, 3.4), 0.9, if i % 2 == 0 then C.CrystalPurple else C.CrystalCyan)
	end
	vines(m, frame, w, d, rng, 4)
	far(m)
	return m
end

local function blossomIsle(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("BlossomIsle", parent)
	local frame = frameAt(MoreIslands.Spots.BlossomIsle)
	local w, d = 26, 22
	Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 32, Tiers = 5 })
	tree(m, frame, Vector3.new(-7, 0, 4), "Pink", rng, 1.2)
	tree(m, frame, Vector3.new(7, 0, 5), "Pink", rng, 1)
	-- a red shrine gate over the path to the front edge
	local gate = frame * CFrame.new(-1, 0, -4)
	for _, sx in { -1, 1 } do
		Style.block(m, gate * CFrame.new(sx * 2.6, 3, 0), Vector3.new(0.7, 6, 0.7), C.AwningRed, nil, Kit.far())
	end
	Style.block(m, gate * CFrame.new(0, 6.3, 0), Vector3.new(7.4, 0.6, 0.9), C.AwningRed, nil, Kit.far())
	Style.block(m, gate * CFrame.new(0, 6.8, 0), Vector3.new(8.2, 0.4, 1.1), C.WoodDark, nil, Kit.far())
	Style.block(m, gate * CFrame.new(0, 5, 0), Vector3.new(6, 0.35, 0.5), C.AwningRed, nil, Kit.far())
	-- a stone lantern with a warm glow
	local lantern = frame * CFrame.new(4, 0, -6)
	Style.block(m, lantern * CFrame.new(0, 0.4, 0), Vector3.new(1.6, 0.8, 1.6), C.StoneDark, nil, Kit.far())
	Style.block(m, lantern * CFrame.new(0, 1.6, 0), Vector3.new(0.7, 1.6, 0.7), C.Stone, nil, Kit.far())
	Kit.glow(m, lantern * CFrame.new(0, 2.8, 0), Vector3.new(1, 0.8, 1), C.LampAmber)
	Style.block(m, lantern * CFrame.new(0, 3.45, 0), Vector3.new(1.8, 0.5, 1.8), C.StoneDark, nil, Kit.far())
	for _, f in { { At = Vector3.new(-3, 0, -7), Color = C.FlowerPink }, { At = Vector3.new(6, 0, 0), Color = C.FlowerWhite } } do
		Style.flowers(m, (frame * CFrame.new(f.At)).Position, f.Color, rng, 4, 1.4)
	end
	waterfall(m, frame, 4.5, d, 32, 4.5, rng)
	vines(m, frame, w, d, rng, 4)
	far(m)
	return m
end

local function windmillIsle(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("WindmillIsle", parent)
	local frame = frameAt(MoreIslands.Spots.WindmillIsle)
	local w, d = 26, 22
	Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 30, Tiers = 5 })
	-- striped flower fields
	local stripes = { C.FlowerYellow, C.FlowerPink, C.FlowerPurple, C.FlowerRed }
	for i, color in stripes do
		Kit.box(m, frame, Vector3.new(-6 + i * 3, 0.35, -2), Vector3.new(2.2, 0.5, 11), color)
	end
	-- the windmill: a tapering stone tower, a dark cap, four sails facing the town
	local base = frame * CFrame.new(-6, 0, 3)
	for i, s in { 6, 5, 4.2 } do
		Style.block(m, base * CFrame.new(0, (i - 0.5) * 4, 0), Vector3.new(s, 4, s), Style.vary(C.StoneLight, rng, 0.04), nil, Kit.far())
	end
	Kit.window(m, base * CFrame.new(0, 6, -2.55), 1.2, 1.4)
	Style.block(m, base * CFrame.new(0, 12.6, 0), Vector3.new(5.4, 1.2, 5.4), C.RoofTerracottaDark, nil, Kit.far())
	Style.block(m, base * CFrame.new(0, 13.8, 0), Vector3.new(3.6, 1.2, 3.6), C.RoofTerracotta, nil, Kit.far())
	Style.block(m, base * CFrame.new(0, 14.8, 0), Vector3.new(1.6, 0.9, 1.6), C.RoofTerracottaDark, nil, Kit.far())
	local hub = base * CFrame.new(0, 9.5, -2.8)
	Style.block(m, hub, Vector3.new(1.4, 1.4, 1.4), C.WoodDark, nil, Kit.far())
	for k = 0, 3 do
		local arm = hub * CFrame.Angles(0, 0, k * math.pi / 2 + 0.35)
		Style.block(m, arm * CFrame.new(0, 4.4, -0.3), Vector3.new(0.35, 8.2, 0.35), C.WoodDark, nil, Kit.far())
		Style.block(m, arm * CFrame.new(0.9, 5, -0.35), Vector3.new(1.5, 6.4, 0.12), C.FlowerWhite, nil, Kit.far())
	end
	tree(m, frame, Vector3.new(8, 0, 6), "Green", rng, 0.9)
	vines(m, frame, w, d, rng, 4)
	far(m)
	return m
end

local function lavaIsle(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("LavaIsle", parent)
	local frame = frameAt(MoreIslands.Spots.LavaIsle)
	local w, d = 24, 20
	local rock = Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 34, Tiers = 5 })
	-- scorched top: the grass turns to dark rock
	for _, p in rock:GetChildren() do
		if p:IsA("BasePart") and p.CFrame.Position.Y > frame.Position.Y - 4.9 then
			p.Color = ROCK_DARK:Lerp(p.Color, 0.15)
		end
	end
	-- a lava pool, a lava fall off the front, glowing cracks down the rock
	Kit.glow(m, frame * CFrame.new(3, 0.25, -3), Vector3.new(7, 0.4, 6), LAVA)
	Kit.glow(m, frame * CFrame.new(3, 0.35, -3), Vector3.new(4, 0.4, 3), LAVA_HOT)
	Kit.glow(m, frame * CFrame.new(3, 0.28, -8.5), Vector3.new(2.4, 0.3, 5), LAVA)
	local fall = Kit.skyFall(m, frame * CFrame.new(3, -0.4, -d / 2 - 0.5), 36, 3.6, rng)
	for _, p in fall:GetDescendants() do
		if p:IsA("BasePart") then
			p.Color = if p.Size.X < 1.2 then LAVA_HOT else LAVA
			p.Material = NEON
		end
	end
	for i = 1, 5 do
		local y = -6 - i * 4.4
		Kit.glow(m, frame * CFrame.new(rng:range(-6, 6), y, -d * 0.36 + i * 0.4), Vector3.new(rng:range(2, 4), 0.3, 0.3), LAVA)
	end
	-- the glowing anvil on a stump, a smoking stone hut
	local anvil = frame * CFrame.new(-4, 0, -4)
	Style.block(m, anvil * CFrame.new(0, 0.7, 0), Vector3.new(1.6, 1.4, 1.6), C.WoodDark, nil, Kit.far())
	Style.block(m, anvil * CFrame.new(0, 1.8, 0), Vector3.new(3, 0.8, 1.3), C.Iron, nil, Kit.far())
	Kit.glow(m, anvil * CFrame.new(0, 2.3, 0), Vector3.new(1.4, 0.3, 0.9), LAVA_HOT)
	local hut = frame * CFrame.new(-4, 0, 5)
	Style.block(m, hut * CFrame.new(0, 2.5, 0), Vector3.new(7, 5, 6), Style.vary(C.StoneDark, rng, 0.04), nil, Kit.far())
	Style.block(m, hut * CFrame.new(0, 5.4, 0), Vector3.new(8, 0.8, 7), ROCK_DARK, nil, Kit.far())
	Kit.glow(m, hut * CFrame.new(0, 2, -3.05), Vector3.new(2, 2.6, 0.2), LAVA)
	local chimney = Style.block(m, hut * CFrame.new(2.4, 7, 1.5), Vector3.new(1.4, 3.6, 1.4), ROCK_DARK, nil, Kit.far())
	local top = Kit.glow(m, hut * CFrame.new(2.4, 8.9, 1.5), Vector3.new(1, 0.3, 1), LAVA)
	Style.emitter(top, "Smoke", nil, 2)
	chimney.Name = "Chimney"
	far(m)
	return m
end

local function twinIslets(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("TwinIslets", parent)
	local a = frameAt(MoreIslands.Spots.TwinIslets)
	local bPos = (a * CFrame.new(-22, 8, 6)).Position
	local b = frameAt(bPos)
	Kit.floatingIsland(m, a, rng, { Width = 13, Depth = 11, Hang = 16, Tiers = 3 })
	Kit.floatingIsland(m, b, rng, { Width = 11, Depth = 9, Hang = 14, Tiers = 3 })
	tree(m, a, Vector3.new(2, 0, 1), "Orange", rng, 0.8)
	tree(m, b, Vector3.new(-1, 0, 1), "Green", rng, 0.75)
	-- the rope bridge: planks hung in a sag between the two edges, two rope lines, lantern posts
	local p0 = (a * CFrame.new(-6, 0, 0)).Position
	local p1 = (b * CFrame.new(5, 0, 0)).Position
	local n = 9
	local prev0, prev1 = nil :: Vector3?, nil :: Vector3?
	for i = 0, n do
		local t = i / n
		local p = p0:Lerp(p1, t) + Vector3.new(0, -math.sin(t * math.pi) * 2.2, 0)
		local dir = (p1 - p0).Unit
		local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
		Style.block(m, CFrame.lookAt(p, p + dir), Vector3.new(3, 0.25, 1.2), Style.vary(C.Plank, rng, 0.06), nil, Kit.far())
		local r0, r1 = p + right * 1.5 + Vector3.new(0, 1.3, 0), p - right * 1.5 + Vector3.new(0, 1.3, 0)
		if prev0 and prev1 then
			Kit.beam(m, prev0, r0, 0.18, C.WoodLight)
			Kit.beam(m, prev1, r1, 0.18, C.WoodLight)
		end
		prev0, prev1 = r0, r1
	end
	for _, at in { p0, p1 } do
		Style.block(m, CFrame.new(at + Vector3.new(0, 1.6, 0)), Vector3.new(0.4, 3.2, 0.4), C.WoodDark, nil, Kit.far())
		Kit.glow(m, CFrame.new(at + Vector3.new(0, 3.5, 0)), Vector3.new(0.8, 0.8, 0.8), C.LampAmber)
	end
	vines(m, a, 13, 11, rng, 3)
	vines(m, b, 11, 9, rng, 2)
	far(m)
	return m
end

local function jungleIsle(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("JungleIsle", parent)
	local frame = frameAt(MoreIslands.Spots.JungleIsle)
	local w, d = 26, 22
	Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 36, Tiers = 5 })
	Meadow.jungleTree(m, (frame * CFrame.new(-4, 0, 3)).Position, 16, 6, rng, nil)
	Meadow.jungleTree(m, (frame * CFrame.new(7, 0, 5)).Position, 11, 4, rng, Style.TreeKinds.Pink)
	for _, at in { Vector3.new(6, 0, -5), Vector3.new(-8, 0, -6) } do
		Style.bush(m, (frame * CFrame.new(at)).Position, C.LeafGreen, rng, 1.4)
	end
	waterfall(m, frame, 1, d, 40, 5, rng)
	vines(m, frame, w, d, rng, 8)
	far(m)
	return m
end

function MoreIslands.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("MoreIslands", parent)
	-- each island draws from its own stream
	crystalIsle(m, Rng.new(`MoreIslands/Crystal/{rng:nextU32()}`))
	blossomIsle(m, Rng.new(`MoreIslands/Blossom/{rng:nextU32()}`))
	windmillIsle(m, Rng.new(`MoreIslands/Windmill/{rng:nextU32()}`))
	lavaIsle(m, Rng.new(`MoreIslands/Lava/{rng:nextU32()}`))
	twinIslets(m, Rng.new(`MoreIslands/Twin/{rng:nextU32()}`))
	jungleIsle(m, Rng.new(`MoreIslands/Jungle/{rng:nextU32()}`))
	return m
end

return MoreIslands
