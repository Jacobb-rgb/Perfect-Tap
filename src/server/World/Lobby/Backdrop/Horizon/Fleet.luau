--[[
	Ships on the far sea from the Kenney Watercraft Kit (owner 2026-10-17):
	the big ocean liner, a pirate galleon (the kit's ship-large with its
	sails dyed black and a white skull on the main sail), a container ship,
	a tug and a houseboat off the port isle, two little sailing boats.
	Rebuilt from boxes (Blocks + Kenney/*); each one bobs on the swell (tag
	Spin, SpinSpeed 0; client DecorController). Unreachable decoration. The
	liner is rebuilt by hand from the kit model's measurements (cleaner).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)
local Place = require(script.Parent.Place)
local Blocks = require(script.Parent.Blocks)

local Models = script.Parent.Kenney
local C = Style.C

local Fleet = {}

-- Model, bearing / studs from the plaza, the bearing the bow points to,
-- length in studs, how deep the hull sits (fraction of the model's height).
type Spot = { Model: string, Az: number, Dist: number, Heading: number, Length: number, Sink: number, Pirate: boolean? }

Fleet.Spots = {
	{ Model = "OceanLiner", Az = 170, Dist = 430, Heading = 285, Length = 150, Sink = 0.1 },
	{ Model = "Galleon", Az = 120, Dist = 470, Heading = 185, Length = 80, Sink = 0.08, Pirate = true },
	{ Model = "CargoShip", Az = 68, Dist = 520, Heading = 165, Length = 110, Sink = 0.12 },
	{ Model = "TugBoat", Az = 146, Dist = 548, Heading = 235, Length = 26, Sink = 0.1 },
	{ Model = "HouseBoat", Az = 133, Dist = 552, Heading = 40, Length = 22, Sink = 0.08 },
	{ Model = "SailBoatA", Az = 215, Dist = 470, Heading = 120, Length = 28, Sink = 0.08 },
	{ Model = "SailBoatB", Az = 104, Dist = 430, Heading = 20, Length = 26, Sink = 0.08 },
} :: { Spot }

local BLACK = Color3.fromHex("2e2e38")
local BONE = Color3.fromHex("ecebf2")

local function model(name: string): Blocks.Data
	return require(Models:FindFirstChild(name) :: ModuleScript) :: any
end

-- The near-white colours of a model (a galleon's sails, to dye black).
local function whites(data: Blocks.Data): { string }
	local out: { string } = {}
	for _, hex in data.Colors do
		local c = Color3.fromHex(hex)
		if math.min(c.R, c.G, c.B) > 0.72 then
			table.insert(out, hex)
		end
	end
	return out
end

-- A skull on both faces of the main sail: head, jaw, two eye holes.
local function skull(m: Model, face: CFrame, s: number)
	Style.block(m, face, Vector3.new(s, s * 0.9, 0.3), BONE, nil, Kit.far())
	Style.block(m, face * CFrame.new(0, -s * 0.58, 0), Vector3.new(s * 0.6, s * 0.3, 0.3), BONE, nil, Kit.far())
	for _, side in { -1, 1 } do
		Style.block(m, face * CFrame.new(side * s * 0.22, s * 0.05, 0), Vector3.new(s * 0.26, s * 0.26, 0.4), BLACK, nil, Kit.far())
	end
end

--[[
	The ocean liner, measured off the kit's ship-ocean-liner (Kenney units,
	21.3 long, bow toward -Z) and rebuilt as clean blocks: the voxel copy
	smeared its four funnels. Red bottom, black hull with a white rim, three
	white decks with lit windows, four yellow funnels with black tops, masts
	at both ends with flags and a string of lights between them. ~34 parts.
]]
local LINER = {
	Red = Color3.fromHex("d8574c"),
	Hull = Color3.fromHex("444754"),
	White = Color3.fromHex("efeff5"),
	Deck = Color3.fromHex("e6e6ef"),
	Rim = Color3.fromHex("f9f9fc"),
	Funnel = Color3.fromHex("ffab42"),
	Cap = Color3.fromHex("505362"),
	Window = Color3.fromHex("ffc070"),
}
Fleet.LinerLength = 21.3 -- Kenney units
Fleet.LinerWaterline = 1.3
local function liner(parent: Instance, frame: CFrame, length: number): Model
	local m = Style.model("OceanLiner", parent)
	local s = length / Fleet.LinerLength
	-- a block between two corners given in Kenney units
	local function box(
		x0: number,
		y0: number,
		z0: number,
		x1: number,
		y1: number,
		z1: number,
		color: Color3,
		material: Enum.Material?
	): Part
		local lo, hi = Vector3.new(x0, y0, z0) * s, Vector3.new(x1, y1, z1) * s
		return Style.block(m, frame * CFrame.new((lo + hi) / 2), hi - lo, color, material, Kit.far())
	end
	local keel = box(-2.15, 0, -7.4, 2.15, 1.5, 8.6, LINER.Red)
	keel.Name = "Keel"
	box(-1.5, 0.2, -9, 1.5, 1.5, -7.4, LINER.Red)
	box(-1.7, 0.2, 8.6, 1.7, 1.5, 9.8, LINER.Red)
	-- black hull, stepped to a point at the bow and rounded at the stern
	box(-2.3, 1.5, -7.2, 2.3, 3.1, 8.6, LINER.Hull)
	box(-1.75, 1.3, -8.8, 1.75, 3.2, -7.2, LINER.Hull)
	box(-0.95, 1.3, -9.75, 0.95, 3.3, -8.8, LINER.Hull)
	box(-1.95, 1.4, 8.6, 1.95, 3.1, 10, LINER.Hull)
	box(-1.2, 1.5, 10, 1.2, 3.1, 10.6, LINER.Hull)
	-- white rim along the deck edge and the forecastle deck
	box(-2.35, 3.1, -7.2, 2.35, 3.3, 8.6, LINER.Rim)
	box(-1.7, 3.2, -9.6, 1.7, 3.5, -6.1, LINER.White)
	-- three white decks
	box(-2.08, 3.3, -6.1, 2.08, 4.6, 6.1, LINER.White)
	box(-1.62, 4.6, -5.3, 1.62, 5.35, 5.2, LINER.Deck)
	box(-1.14, 5.35, -5.5, 1.14, 5.9, 4.6, LINER.White)
	-- lit windows along both sides of the two lower decks
	for _, side in { -1, 1 } do
		local x = side * 2.1
		box(x - 0.03, 3.85, -5.6, x + 0.03, 4.05, 5.6, LINER.Window, Enum.Material.Neon).Transparency = 0.35
		local x2 = side * 1.64
		box(x2 - 0.03, 4.9, -4.8, x2 + 0.03, 5.05, 4.7, LINER.Window, Enum.Material.Neon).Transparency = 0.35
	end
	-- four funnels with black tops
	for _, z in { -4.73, -1.69, 1.35, 4.39 } do
		local base = frame * CFrame.new(Vector3.new(0, 5.9, z) * s)
		Geo.cylinder(m, (base * CFrame.new(0, 0.7 * s, 0)).Position, 1.4 * s, 1.25 * s, LINER.Funnel, nil, Kit.far())
		Geo.cylinder(m, (base * CFrame.new(0, 1.7 * s, 0)).Position, 0.6 * s, 1.3 * s, LINER.Cap, nil, Kit.far())
	end
	-- masts with flags and the string of lights between their tops
	local tops: { Vector3 } = {}
	for _, z in { -8.3, 8.4 } do
		box(-0.09, 3.3, z - 0.09, 0.09, 8.9, z + 0.09, LINER.Cap)
		box(0, 8.1, z, 0.04, 8.8, z + (if z < 0 then 0.9 else -0.9), LINER.Red)
		table.insert(tops, (frame * CFrame.new(Vector3.new(0, 8.7, z) * s)).Position)
	end
	Kit.beam(m, tops[1], tops[2], math.max(0.15, 0.04 * s), LINER.Cap)
	for i = 1, 7 do
		local p = tops[1]:Lerp(tops[2], i / 8) - Vector3.new(0, 0.6 * s * math.sin(math.pi * i / 8), 0)
		Style.block(m, CFrame.new(p), Vector3.new(0.35, 0.35, 0.35) * s, C.Lamp, Enum.Material.Neon, Kit.far())
	end
	return m
end

local function ship(parent: Instance, spot: Spot, rng: Rng.Rng): Model
	if spot.Model == "OceanLiner" then
		local s = spot.Length / Fleet.LinerLength
		local p = Place.at(spot.Az, spot.Dist, Place.Sea - Fleet.LinerWaterline * s)
		local m = liner(parent, Place.heading(p, spot.Heading + rng:range(-3, 3)), spot.Length)
		m.PrimaryPart = m:FindFirstChild("Keel") :: BasePart
		m:AddTag("Spin")
		m:SetAttribute("SpinSpeed", 0)
		m:SetAttribute("BobHeight", 0.6)
		m:SetAttribute("BobSpeed", 0.4)
		return m
	end
	local data = model(spot.Model)
	local height = Blocks.height(data, spot.Length)
	local p = Place.at(spot.Az, spot.Dist, Place.Sea - height * spot.Sink)
	-- Kenney bows point along the model's +Z: turn half round so the bow
	-- follows the heading
	local frame = Place.heading(p, spot.Heading + rng:range(-4, 4))
	local recolor: { [string]: Color3 } = {}
	local sails = whites(data)
	if spot.Pirate then
		for _, hex in sails do
			recolor[hex] = BLACK
		end
	end
	local m = Blocks.build(parent, data, frame, spot.Length, { Name = spot.Model, Turn = math.pi, Recolor = recolor })
	if spot.Pirate then
		local center, size = Blocks.panel(data, sails, spot.Length)
		if center and size then
			local base = frame * CFrame.Angles(0, math.pi, 0)
			local s = math.min(size.X, size.Y) * 0.5
			for _, side in { -1, 1 } do
				local face = base * CFrame.new(center + Vector3.new(0, 0, side * (size.Z / 2 + 0.2)))
				skull(m, if side > 0 then face else face * CFrame.Angles(0, math.pi, 0), s)
			end
		end
	end
	-- bob around the biggest block (the hull)
	local hull: BasePart? = nil
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and (not hull or d.Size.Magnitude > (hull :: BasePart).Size.Magnitude) then
			hull = d
		end
	end
	m.PrimaryPart = hull
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", 0)
	m:SetAttribute("BobHeight", math.clamp(spot.Length * 0.008, 0.3, 1))
	m:SetAttribute("BobSpeed", 0.5 + rng:range(0, 0.3))
	return m
end

function Fleet.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Fleet", parent)
	for i, spot in Fleet.Spots do
		ship(m, spot, Rng.new(`Horizon/Fleet/{i}/{rng:nextU32()}`))
	end
	return m
end

return Fleet
