--!strict
--[[
	The VIP cave behind every yard (owner 2026-11-17, in place of the VIP mine at the quarry: "a
	little cave on every plot where the train unloaded ore ... it opens only with the pass", built
	"in the rainbow mountain style with waterfalls round it"; only the plot's owner with the
	Forgemaster's Pass goes in, 5 rocks of the Glimmer Grotto's ore). BaseLayout.VipCave holds its
	layout (plot-local); its door is part of the plot's back wall (PlotBuilder.fence, VipDoor).

	  PlotCave.build(parent, plot, rng) -> (Model, { Spawn })   one plot's cave and its rock spots

	  Mound   rainbow voxel columns round the room like the mountains round the island (Spectrum
	          colours, Kit.column's dirt band and grass top), a lintel over the door, a peak
	  Room    a dark cave inside (floor, walls, ceiling), cyan crystals, one light; a LightingZone
	          (Preset "Grotto": the grotto's cave light, no weather inside)
	  Falls   a waterfall either side of the door down the mound's front into a pool
	  Sign    GLIMMER GROTTO over the door
	It stands outside the plot's model (the plot's part and see-through rules), in Map.VipCaves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local BaseLayout = require(Shared:WaitForChild("Config"):WaitForChild("BaseLayout"))
local WorldLayout = require(Shared:WaitForChild("Config"):WaitForChild("WorldLayout"))
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local Style = require(script.Parent.Lobby.Style)
local Spectrum = require(script.Parent.Lobby.Backdrop.Spectrum)
local Kit = require(script.Parent.Lobby.Backdrop.Kit)

local PlotCave = {}

export type Spawn = { Position: Vector3, Zone: string, PlotId: number }

-- the room's dark rock (inside the rainbow, the cave's own colour) and its floor
PlotCave.RockColor = Color3.fromRGB(78, 56, 104)
PlotCave.FloorColor = Color3.fromRGB(60, 44, 82)
PlotCave.Zone = "Grotto"
PlotCave.MoundTop = 24 -- the mound's highest top: its colours run from the foot to here
PlotCave.RoomFront = 65.6 -- the room's inside runs from here back (the mound's front, the door's tunnel, before it)
-- phones (tests/VipCave.spec.luau): a cave's parts and see-through parts (the falls and their pools);
-- every plot has one, all inside the town's streaming radius (LobbyLayout.Budget)
PlotCave.Budget = { Parts = 80, SeeThrough = 10 }

--[[
	The mound: voxel columns like the mountains round the island (Lobby/Backdrop/Kit.column: a
	coloured block, a dirt band and a grass top), plot-local { x0, z0, x1, z1, bottom, top }: the
	front round the door (its tunnel x -4 .. 4: the columns' own faces), the waterfall wings, the
	roof over the room and the back up to a peak. None reaches into the room (BaseLayout.VipCave.Room,
	its shell a stud thick round it).
]]
PlotCave.Columns = {
	-- (the front's tops 10.6 and up: their dirt bands start at the room's ceiling, none shows inside)
	{ -12, 63.8, -4, 65.6, -2, 10.6 }, -- front, left of the door
	{ 4, 63.8, 12, 65.6, -2, 10.8 }, -- front, right of the door
	{ -4, 63.8, 4, 65.6, 7.6, 11.6 }, -- the lintel over the door
	{ -20, 66.6, -12, 71, -2, 12.4 }, -- the left wing (its fall down the front)
	{ 12, 66.6, 20, 71, -2, 13.2 }, -- the right wing
	{ -20, 71, -12, 77, -2, 15 },
	{ 12, 71, 20, 77, -2, 14.4 },
	{ -12, 65.6, 0, 71, 10, 13.6 }, -- the roof over the room
	{ 0, 65.6, 12, 71, 10, 12.8 },
	{ -12, 71, 0, 75.8, 10, 17.4 },
	{ 0, 71, 12, 75.8, 10, 16.2 },
	{ -20, 77, -12, 84, -2, 19.6 }, -- the back
	{ -12, 75.8, 6, 84, -2, 22.4 },
	{ 6, 75.8, 20, 84, -2, 18.6 },
	{ -4, 74, 3, 81, 17, PlotCave.MoundTop }, -- the peak
}
-- the falls: x along the back wall, the lip's height on the wing's front (z 66.6), width (their foot
-- and pool behind the yard's back wall: no foam)
PlotCave.Falls = { { -15.5, 12.2, 3.6 }, { 15.5, 13, 3.6 } }

local SOLID = Style.solid() -- (queryable: the camera stays inside the room)

local function partIn(
	parent: Instance,
	cf: CFrame,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	y0: number,
	y1: number,
	color: Color3,
	material: Enum.Material?,
	props: any
): Part
	return Style.block(
		parent,
		cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		color,
		material,
		props
	)
end

function PlotCave.build(parent: Instance, plot: WorldLayout.Plot, rng: Rng.Rng): (Model, { Spawn })
	local cave = BaseLayout.VipCave
	local cf = WorldLayout.plotCFrame(plot)
	local m = Instance.new("Model")
	m.Name = "VipCave_" .. plot.Id
	m:SetAttribute("PlotId", plot.Id)

	-- the mound: each column in its own rainbow colour for its height (lanes all over the island's
	-- range, so neighbours never match), a grass top like the island's mountains
	for _, c in PlotCave.Columns do
		local a = cf:PointToWorldSpace(Vector3.new(c[1], c[5], c[2]))
		local b = cf:PointToWorldSpace(Vector3.new(c[3], c[6], c[4]))
		local shade = 14 + c[6] / PlotCave.MoundTop * 150
		local color = Spectrum.color(rng:range(-170, 170), shade, rng)
		local main = Kit.column(m, a.X, a.Z, b.X, b.Z, a.Y, b.Y, rng, { Color = color, Cap = "Grass" })
		main.Color = color
		main.Name = "Mound"
	end

	-- the room: a dark floor, walls and ceiling (its front is the mound's front round the door)
	local room = cave.Room
	local rx0, rx1 = room.Min.X, room.Max.X
	local rz0, rz1 = PlotCave.RoomFront, room.Max.Z
	local ry1 = room.Max.Y
	local shell = Instance.new("Model")
	shell.Name = "Room"
	shell.Parent = m
	partIn(shell, cf, rx0, 63.8, rx1, rz1, -0.4, 0, PlotCave.FloorColor, Enum.Material.Slate, SOLID).Name = "Floor"
	partIn(shell, cf, rx0 - 1, 63.8, rx0, rz1 + 1, -0.4, ry1 + 1, PlotCave.RockColor, Enum.Material.Slate, SOLID).Name = "Wall"
	partIn(shell, cf, rx1, 63.8, rx1 + 1, rz1 + 1, -0.4, ry1 + 1, PlotCave.RockColor, Enum.Material.Slate, SOLID).Name = "Wall"
	partIn(shell, cf, rx0, rz1, rx1, rz1 + 1, -0.4, ry1, PlotCave.RockColor, Enum.Material.Slate, SOLID).Name = "Wall"
	partIn(shell, cf, rx0 - 1, rz0, rx1 + 1, rz1 + 1, ry1, ry1 + 1, PlotCave.RockColor, Enum.Material.Slate, SOLID).Name = "Ceiling"

	-- cyan crystals in the back corners, the left one lit
	for i, spot in { Vector3.new(rx0 + 1.6, 0, rz1 - 1.4), Vector3.new(rx1 - 1.6, 0, rz1 - 1.4) } do
		Style.crystalCluster(m, cf * CFrame.new(spot), 4.2, Palette.Vip, rng, { Count = 1, Light = i == 1, Range = 22, Brightness = 1.2 })
	end

	-- the grotto's cave light inside (LightingController: a LightingZone part's box)
	local zone = partIn(m, cf, rx0, 63.8, rx1, rz1, 0, ry1, PlotCave.RockColor, nil, Style.tiny({ Transparency = 1 }))
	zone.Name = "LightingZone"
	zone:SetAttribute("Preset", "Grotto")
	zone:AddTag("LightingZone")

	-- the falls down the wings' fronts into a pool behind the back wall
	for _, f in PlotCave.Falls do
		local x, lip, width = f[1], f[2], f[3]
		local at = Vector3.new(x, lip, 66.55)
		Style.waterfall(m, cf * CFrame.lookAt(at, at + Vector3.new(0, 0, -1)), lip - 0.2, width, rng, { Foam = false })
		local pool = Style.water(m, cf * CFrame.new(x, 0.1, 65.2), Vector3.new(width + 2.4, 0.4, 2.4))
		pool.Name = "Water"
	end

	-- the name over the door
	Props.sign(m, cf * CFrame.new(0, 9.4, 63.35), "GLIMMER GROTTO", 10, 1.7, Palette.HollowRockDark, Palette.Vip)

	m.Parent = parent
	local spawns: { Spawn } = {}
	for _, p in cave.Rocks do
		table.insert(spawns, { Position = cf:PointToWorldSpace(p), Zone = PlotCave.Zone, PlotId = plot.Id })
	end
	return m, spawns
end

-- Every plot's cave (Map.VipCaves) and all their rock spots.
function PlotCave.buildAll(map: Instance, rng: Rng.Rng): { Spawn }
	local folder = Instance.new("Folder")
	folder.Name = "VipCaves"
	folder.Parent = map
	local spawns: { Spawn } = {}
	for _, plot in WorldLayout.Plots do
		local _, list = PlotCave.build(folder, plot, rng)
		for _, s in list do
			table.insert(spawns, s)
		end
	end
	return spawns
end

-- Where someone who may not be in a plot's cave is put back: in the yard, in front of its door.
function PlotCave.outside(plot: WorldLayout.Plot): CFrame
	return WorldLayout.plotCFrame(plot) * CFrame.lookAt(Vector3.new(0, 3, 59), Vector3.new(0, 3, 50))
end

-- The world box of one plot's cave room (the door's tunnel included), for AccessService.
function PlotCave.roomBox(plot: WorldLayout.Plot): (CFrame, Vector3)
	local room = BaseLayout.VipCave.Room
	local cf = WorldLayout.plotCFrame(plot)
	local min, max = Vector3.new(room.Min.X - 1, room.Min.Y - 1, 63.4), Vector3.new(room.Max.X + 1, room.Max.Y + 1, room.Max.Z + 1)
	return cf * CFrame.new((min + max) / 2), max - min
end

return PlotCave
