--[[
	Horizon isles: a ring of far islands on the sea around the whole map, so
	no side of the town looks out on empty water (owner 2026-10-17), built
	from the Kenney kits the owner sent: Hexagon Kit tiles (Hex) with its
	castle, mill, port, house, wizard tower and mountains on top
	(Blocks + Kenney/Hex*), Survival Kit camp pieces (tent, campfire, anvil,
	autumn trees), Fantasy Town trees, lanterns and a stall; two lighthouses
	in the kits' colours with a turning beam; and in the north, behind the
	massif, three Candy pillar stacks in the mountains' Spectrum colours.

	Every isle sits 500+ studs out (past every Sky piece and the sun path),
	is unreachable decoration and carries no lights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)
local Spectrum = require(script.Parent.Parent.Spectrum)
local Place = require(script.Parent.Place)
local Hex = require(script.Parent.Hex)
local Blocks = require(script.Parent.Blocks)

local Models = script.Parent.Kenney
local C = Style.C
local SEA = Place.Sea
local NEON = Enum.Material.Neon

local Isles = {}

-- A tile of an island: axial (Q, R), top kind, height above the sea, and
-- what stands on it: a Kenney hexagon building / "Lighthouse" (Model) or props.
type Tile = { Q: number, R: number, Kind: string, Top: number, Model: string?, Props: { string }? }
type Island = { Name: string, Az: number, Dist: number, W: number, Tiles: { Tile } }

-- Props: Kenney model -> its longest side in tile widths.
local PROPS: { [string]: number } = {
	RoundTree = 0.5,
	AutumnTree = 0.55,
	Tent = 0.62,
	Campfire = 0.3,
	Anvil = 0.36,
	Lantern = 0.3,
	Stall = 0.4,
}

Isles.Islands = {
	{
		Name = "CastleIsle",
		Az = 205,
		Dist = 700,
		W = 44,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Grass", Top = 9, Model = "HexCastle" },
			{ Q = 1, R = 0, Kind = "Grass", Top = 6, Props = { "RoundTree", "AutumnTree" } },
			{ Q = -1, R = 0, Kind = "Grass", Top = 6, Props = { "RoundTree", "RoundTree" } },
			{ Q = 0, R = -1, Kind = "Grass", Top = 7, Model = "HexHouse" },
			{ Q = 0, R = 1, Kind = "Sand", Top = 4 },
			{ Q = 1, R = -1, Kind = "Sand", Top = 4 },
			{ Q = -1, R = 1, Kind = "Stone", Top = 5 },
		},
	},
	{
		Name = "MillIsle",
		Az = 95,
		Dist = 690,
		W = 42,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Grass", Top = 7, Model = "HexMill" },
			{ Q = 1, R = 0, Kind = "Grass", Top = 6, Model = "HexHouse" },
			{ Q = -1, R = 0, Kind = "Grass", Top = 6, Props = { "AutumnTree", "AutumnTree" } },
			{ Q = 1, R = -1, Kind = "Grass", Top = 6, Props = { "RoundTree", "AutumnTree" } },
			{ Q = 0, R = 1, Kind = "Sand", Top = 4 },
			{ Q = 0, R = -1, Kind = "Sand", Top = 4 },
		},
	},
	{
		Name = "PortIsle",
		Az = 140,
		Dist = 610,
		W = 40,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Grass", Top = 7, Model = "HexHouse" },
			{ Q = -1, R = 1, Kind = "Sand", Top = 4, Model = "HexPort" },
			{ Q = 0, R = 1, Kind = "Sand", Top = 4, Props = { "Stall", "Lantern" } },
			{ Q = 1, R = 0, Kind = "Grass", Top = 6, Props = { "RoundTree", "RoundTree" } },
			{ Q = 1, R = -1, Kind = "Stone", Top = 5 },
		},
	},
	{
		Name = "MountainIsle",
		Az = 165,
		Dist = 900,
		W = 52,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Stone", Top = 8, Model = "HexMountain" },
			{ Q = 1, R = -1, Kind = "Stone", Top = 7, Model = "HexMountain" },
			{ Q = 1, R = 0, Kind = "Grass", Top = 6, Props = { "RoundTree", "AutumnTree" } },
			{ Q = -1, R = 0, Kind = "Grass", Top = 6, Props = { "RoundTree", "AutumnTree" } },
			{ Q = 0, R = 1, Kind = "Sand", Top = 4 },
			{ Q = -1, R = 1, Kind = "Grass", Top = 5 },
			{ Q = 0, R = -1, Kind = "Stone", Top = 6 },
		},
	},
	{
		Name = "WizardIsle",
		Az = 58,
		Dist = 780,
		W = 44,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Grass", Top = 8, Model = "HexWizard" },
			{ Q = 1, R = 0, Kind = "Grass", Top = 6, Props = { "RoundTree", "AutumnTree" } },
			{ Q = -1, R = 0, Kind = "Stone", Top = 5 },
			{ Q = 0, R = 1, Kind = "Sand", Top = 4 },
			{ Q = 0, R = -1, Kind = "Grass", Top = 6, Props = { "RoundTree" } },
		},
	},
	{
		Name = "CampIsle",
		Az = 238,
		Dist = 600,
		W = 34,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Sand", Top = 5, Props = { "Tent" } },
			{ Q = 1, R = 0, Kind = "Grass", Top = 6, Props = { "AutumnTree", "AutumnTree" } },
			{ Q = -1, R = 0, Kind = "Sand", Top = 4, Props = { "Campfire", "Lantern" } },
			{ Q = 0, R = 1, Kind = "Sand", Top = 4, Props = { "Anvil" } },
			{ Q = 1, R = -1, Kind = "Grass", Top = 6, Props = { "AutumnTree" } },
		},
	},
	{
		Name = "LighthouseSouth",
		Az = 182,
		Dist = 540,
		W = 30,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Stone", Top = 8, Model = "Lighthouse" },
			{ Q = 1, R = 0, Kind = "Stone", Top = 5 },
			{ Q = 0, R = 1, Kind = "Sand", Top = 3, Props = { "Lantern" } },
			{ Q = -1, R = 0, Kind = "Stone", Top = 6 },
		},
	},
	{
		Name = "LighthouseWest",
		Az = 300,
		Dist = 780,
		W = 30,
		Tiles = {
			{ Q = 0, R = 0, Kind = "Stone", Top = 8, Model = "Lighthouse" },
			{ Q = 1, R = 0, Kind = "Grass", Top = 5, Props = { "RoundTree" } },
			{ Q = -1, R = 1, Kind = "Sand", Top = 3 },
			{ Q = 0, R = -1, Kind = "Stone", Top = 6 },
		},
	},
} :: { Island }

-- Candy pillar stacks in the north, behind the massif.
Isles.Stacks = {
	{ Az = 10, Dist = 1000, Height = 112 },
	{ Az = 24, Dist = 900, Height = 72 },
	{ Az = 340, Dist = 1040, Height = 90 },
}

local function model(name: string): Blocks.Data
	return require(Models:FindFirstChild(name) :: ModuleScript) :: any
end

---------------------------------------------------------------- pieces

-- White surf around an island: a translucent hexagon just over the sea.
local function surf(m: Model, center: Vector3, w: number)
	local size = Vector3.new(w + 8, 0.25, (w + 8) / math.sqrt(3))
	for i = 0, 2 do
		Style.block(
			m,
			CFrame.new(center.X, SEA + 0.12, center.Z) * CFrame.Angles(0, i * math.pi / 3, 0),
			size,
			C.Foam,
			nil,
			Kit.far({ Transparency = 0.5 })
		)
	end
end

-- A turning lighthouse beam: two long faint shafts around an invisible hub
-- (the pivot), tag Spin.
local function beam(m: Model, at: Vector3, length: number, rng: Rng.Rng)
	local b = Style.model("LightBeam", m)
	local hub = Style.block(b, CFrame.new(at), Vector3.new(1, 1, 1), C.Lamp, nil, Kit.far({ Transparency = 1 }))
	hub.Name = "Hub"
	for _, side in { -1, 1 } do
		Kit.glow(b, CFrame.new(at) * CFrame.new(0, 0, side * (length / 2 + 2)), Vector3.new(2.6, 2.6, length), C.Lamp, 0.8)
	end
	b.PrimaryPart = hub
	b:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:range(0, math.pi), 0))
	b:AddTag("Spin")
	b:SetAttribute("SpinSpeed", 0.6)
	b:SetAttribute("BobHeight", 0)
end

-- A lighthouse in the kits' colours: white tower with red bands (the
-- Watercraft liner's red), a dark gallery, the lamp room, the Hexagon
-- Kit's blue stepped roof, a turning beam. `base` = foot center. 15 parts.
local LIGHT_WHITE = Color3.fromHex("f3f3f7")
local LIGHT_RED = Color3.fromHex("d8574c")
local ROOF_BLUE = Color3.fromHex("7277f1")
local GALLERY = Color3.fromHex("4c4f5d")
local function lighthouse(m: Model, base: Vector3, s: number, rng: Rng.Rng)
	local x, z = base.X, base.Z
	local y = base.Y
	local seg = 7 * s
	for i = 1, 4 do
		local dia = (10 - i * 0.8) * s
		Geo.cylinder(m, Vector3.new(x, y + seg / 2, z), seg, dia, if i % 2 == 1 then LIGHT_WHITE else LIGHT_RED, nil, Kit.far())
		y += seg
	end
	Geo.cylinder(m, Vector3.new(x, y + 0.5 * s, z), 1 * s, 9.6 * s, GALLERY, nil, Kit.far())
	y += 1 * s
	Geo.cylinder(m, Vector3.new(x, y + 2.2 * s, z), 4.4 * s, 5.6 * s, C.Lamp, NEON, Kit.far())
	local lamp = Vector3.new(x, y + 2.2 * s, z)
	y += 4.4 * s
	for i, dia in { 7.2, 5, 2.8 } do
		local h = (1.7 - i * 0.2) * s
		local roof = if i == 2 then ROOF_BLUE:Lerp(Color3.new(0, 0, 0), 0.15) else ROOF_BLUE
		Geo.cylinder(m, Vector3.new(x, y + h / 2, z), h, dia * s, roof, nil, Kit.far())
		y += h
	end
	Geo.ball(m, Vector3.new(x, y + 0.6 * s, z), 1.4 * s, C.Gold, nil, Kit.far())
	beam(m, lamp, 90 * s, rng)
end

-- Candy sea stack: Spectrum pillars out of the surf, a grassy top with a
-- Fantasy Town tree on the tall ones. ~14-34 parts.
local function stack(m: Model, c: Vector3, height: number, rng: Rng.Rng)
	local lane = rng:range(-170, 170)
	local w = math.floor(height * rng:range(0.16, 0.2))
	local function pillar(x: number, z: number, size: number, top: number, grass: boolean?)
		local shade = 14 + (top - SEA) / height * 150
		local color = Spectrum.color(lane + rng:range(-20, 20), shade, rng)
		Style.block(m, CFrame.new(x, (SEA - 2 + top) / 2, z), Vector3.new(size, top - SEA + 2, size), color, nil, Kit.far())
		local cap = if grass then Hex.Colors.Grass else Spectrum.tint(color)
		Style.block(m, CFrame.new(x, top + 0.45, z), Vector3.new(size + 0.4, 0.9, size + 0.4), cap, nil, Kit.far())
	end
	local crowned = height >= 80
	pillar(c.X, c.Z, w, SEA + height, crowned)
	if crowned then
		Blocks.build(m, model("RoundTree"), CFrame.new(c.X, SEA + height + 0.9, c.Z), w * 1.1, { Name = "Tree" })
	end
	local step = w / 2
	for _ = 1, math.floor(rng:range(4, 6.99)) do
		local dx = math.floor(rng:range(-3.99, 4)) * step
		local dz = math.floor(rng:range(-3.99, 4)) * step
		if math.abs(dx) < step and math.abs(dz) < step then
			dx = step * 2
		end
		pillar(c.X + dx, c.Z + dz, w * rng:range(0.6, 1), SEA + height * rng:range(0.35, 0.8))
	end
end

---------------------------------------------------------------- islands

local function island(parent: Instance, spec: Island, rng: Rng.Rng): Model
	local m = Style.model(spec.Name, parent)
	local center = Place.at(spec.Az, spec.Dist, SEA)
	local w = spec.W
	-- the cluster faces the town: axial +R toward the plaza
	local toTown = Vector3.new(-center.X, 0, -center.Z).Unit
	local frame = CFrame.lookAt(center, center - toTown)
	-- one ring of surf around the whole cluster (centered on its tiles)
	local mid = Vector3.zero
	for _, tile in spec.Tiles do
		mid += Hex.offset(tile.Q, tile.R, w)
	end
	surf(m, frame:PointToWorldSpace(mid / #spec.Tiles), w * 2.6)
	for _, tile in spec.Tiles do
		local p = frame:PointToWorldSpace(Hex.offset(tile.Q, tile.R, w))
		local top = SEA + tile.Top
		Hex.tile(m, p, top, SEA - 3, w, tile.Kind)
		if tile.Model == "Lighthouse" then
			lighthouse(m, Vector3.new(p.X, top, p.Z), w / 30, rng)
		elseif tile.Model then
			-- a Kenney hexagon building: its own tile was clipped off, model
			-- height 0.2 (the tile top) lands on our tile's top
			local foot = Vector3.new(p.X, top - 0.2 * w, p.Z)
			local face = CFrame.lookAt(foot, foot + toTown) * CFrame.Angles(0, math.rad(60 * rng:int(-1, 1)), 0)
			Blocks.build(m, model(tile.Model), face, 0, { Name = tile.Model, Scale = w })
		end
		local props: { string } = tile.Props or {}
		for i, prop in props do
			local a = rng:range(0, math.pi * 2) + i * math.pi
			local r = if #props > 1 then w * 0.22 else w * rng:range(0, 0.12)
			local at = Vector3.new(p.X + math.cos(a) * r, top, p.Z + math.sin(a) * r)
			local cf = CFrame.lookAt(at, at + toTown) * CFrame.Angles(0, rng:range(-0.6, 0.6), 0)
			Blocks.build(m, model(prop), cf, w * PROPS[prop], { Name = prop })
		end
	end
	return m
end

function Isles.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Isles", parent)
	for i, spec in Isles.Islands do
		island(m, spec, Rng.new(`Horizon/Isles/{spec.Name}/{i}/{rng:nextU32()}`))
	end
	for i, s in Isles.Stacks do
		local sm = Style.model(`Stack{i}`, m)
		stack(sm, Place.at(s.Az, s.Dist, SEA), s.Height, Rng.new(`Horizon/Stacks/{i}/{rng:nextU32()}`))
	end
	return m
end

return Isles
