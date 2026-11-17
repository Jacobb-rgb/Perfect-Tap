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
	  Rocks   5 spots of the Glimmer Grotto's ore, each with the owner's Meshy rock model for it
	          (BaseLayout.VipCave.RockFloor / RockKinds: MiningService builds it with RockBuilder),
	          and 2 of the Sunken Palace's own rocks in the middle (FloorRocks); every cave rock's ore
	          may rarely be one of floors 5 and 6 (Rare)
	It stands outside the plot's model (the plot's part and see-through rules), in Map.VipCaves.
	(owner 2026-11-17 evening: "widen it a bit, it's terribly narrow in there") The room runs back
	past the island's edge: PlotCave.openEdge cuts a window into Land's boundary wall behind it and
	lowers the coastal rocks inside it; the room's own walls and the mound close it.
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

export type Spawn = {
	Position: Vector3,
	Zone: string,
	PlotId: number,
	RockFloor: string?, -- a zone rock in this floor's Meshy model of RockKind
	RockKind: string?,
	Floor: number?, -- a mine floor's own rock (its ores, health, blaster level) of Kind
	Kind: string?,
	RareFloors: string?, -- "StormglassRift,HeartstoneCore": a rare ore's floors, RareChance per ore
	RareChance: number?,
}

-- the room's violet rock (inside the rainbow, the cave's own colour) and its floor, light enough
-- to read under the grotto's teal cave light
PlotCave.RockColor = Color3.fromRGB(96, 74, 134)
PlotCave.FloorColor = Color3.fromRGB(74, 58, 104)
-- the mound's colours: the island's mountain range from one side to the other (Spectrum's lanes,
-- gold and orange through pink to purple; every other plot the other way round), bright: the
-- height (t) runs over this part of the lanes, foot to top
PlotCave.Hue = { Lane = 170, T0 = 0.45, T1 = 0.8 }
-- the cave's light: a pale cyan, so the rocks' crusts and ores keep their own colours under it
PlotCave.LightColor = Color3.fromRGB(200, 244, 255)
PlotCave.Zone = "Grotto"
PlotCave.MoundTop = 27 -- the mound's highest top: its colours run from the foot to here
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
	-- (the front's tops 13.6 and up: their dirt bands start at the room's ceiling, none shows inside)
	{ -21, 63.8, -5, 65.6, -2, 13.8 }, -- front, left of the door
	{ 5, 63.8, 21, 65.6, -2, 14 }, -- front, right of the door
	{ -5, 63.8, 5, 65.6, 8.6, 14.6 }, -- the lintel over the door
	-- (past the island's edge, z 76 on, the columns reach down into the coastal rocks)
	{ -27, 66.6, -21, 76, -6, 15 }, -- the left wing (its fall down the front)
	{ 21, 66.6, 27, 76, -6, 15.8 }, -- the right wing
	{ -27, 76, -21, 86, -6, 18.6 },
	{ 21, 76, 27, 86, -6, 17.8 },
	{ -21, 65.6, 0, 74, 13, 16.6 }, -- the roof over the room
	{ 0, 65.6, 21, 74, 13, 15.8 },
	{ -21, 74, 0, 85, 13, 20.4 },
	{ 0, 74, 21, 85, 13, 19.2 },
	{ -27, 85, -8, 90, -8, 21.6 }, -- the back, over the coast
	{ -8, 85, 10, 90, -8, 24.8 },
	{ 10, 85, 27, 90, -8, 20.6 },
	{ -5, 80, 4, 88, 19, PlotCave.MoundTop }, -- the peak
}
-- the falls: x along the back wall, the lip's height on the wing's front (z 66.6), width (their foot
-- and pool behind the yard's back wall: no foam)
PlotCave.Falls = { { -24, 14.6, 3.6 }, { 24, 15.4, 3.6 } }
-- The window cut into Land's boundary wall behind each cave (plot-local x across, up to y Top):
-- the room and its side walls; above it the wall stays
PlotCave.EdgeWindow = { X = 21, Top = 14 }

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

	-- the mound: a rainbow across it like the mountains round the island (each column the range's
	-- colour for its place and height, Spectrum jitters neighbours apart), a grass top on each
	local hue = PlotCave.Hue
	local flip = if plot.Id % 2 == 0 then -1 else 1
	for _, c in PlotCave.Columns do
		local a = cf:PointToWorldSpace(Vector3.new(c[1], c[5], c[2]))
		local b = cf:PointToWorldSpace(Vector3.new(c[3], c[6], c[4]))
		local across = math.clamp((c[1] + c[3]) / 2 / cave.Mound.Max.X, -1, 1)
		local t = hue.T0 + (hue.T1 - hue.T0) * c[6] / PlotCave.MoundTop
		local color = Spectrum.color(flip * across * hue.Lane, 14 + t * 150, rng)
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
	local ceiling = partIn(shell, cf, rx0 - 1, rz0, rx1 + 1, rz1 + 1, ry1, ry1 + 1, PlotCave.RockColor, Enum.Material.Slate, SOLID)
	ceiling.Name = "Ceiling"

	-- cyan crystals in the back corners; the cave's one light under the ceiling's middle (no
	-- shadows: it reaches the whole room, the rocks and the way in)
	for _, spot in { Vector3.new(rx0 + 1.6, 0, rz1 - 1.4), Vector3.new(rx1 - 1.6, 0, rz1 - 1.4) } do
		Style.crystalCluster(m, cf * CFrame.new(spot), 4.2, Palette.Vip, rng, { Count = 1 })
	end
	Style.light(ceiling, PlotCave.LightColor, 30, 1.8)

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
	Props.sign(m, cf * CFrame.new(0, 11.6, 63.35), "GLIMMER GROTTO", 10, 1.7, Palette.HollowRockDark, Palette.Vip)

	m.Parent = parent
	local spawns: { Spawn } = {}
	local rareFloors = table.concat(cave.Rare.Floors, ",")
	for i, p in cave.Rocks do
		table.insert(spawns, {
			Position = cf:PointToWorldSpace(p),
			Zone = PlotCave.Zone,
			PlotId = plot.Id,
			RockFloor = cave.RockFloor,
			RockKind = cave.RockKinds[i],
			RareFloors = rareFloors,
			RareChance = cave.Rare.Chance,
		})
	end
	for _, rock in cave.FloorRocks do
		table.insert(spawns, {
			Position = cf:PointToWorldSpace(rock.At),
			Zone = PlotCave.Zone,
			PlotId = plot.Id,
			Floor = rock.Floor,
			Kind = rock.Kind,
			RareFloors = rareFloors,
			RareChance = cave.Rare.Chance,
		})
	end
	return m, spawns
end

-- A world box (min, max) of a plot-local one (plots turn by quarter turns: it stays a box).
local function worldBox(cf: CFrame, lo: Vector3, hi: Vector3): (Vector3, Vector3)
	local a, b = cf:PointToWorldSpace(lo), cf:PointToWorldSpace(hi)
	return a:Min(b), a:Max(b)
end

local function partBox(part: BasePart): (Vector3, Vector3)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = part.CFrame:PointToWorldSpace(Vector3.new(sx, sy, sz) * part.Size / 2)
				lo, hi = lo:Min(p), hi:Max(p)
			end
		end
	end
	return lo, hi
end

local function overlaps(aLo: Vector3, aHi: Vector3, bLo: Vector3, bHi: Vector3): boolean
	return aLo.X < bHi.X and bLo.X < aHi.X and aLo.Y < bHi.Y and bLo.Y < aHi.Y and aLo.Z < bHi.Z and bLo.Z < aHi.Z
end

--[[
	The rooms run back past the island's edge (BaseLayout.VipCave.Room to z 84; the island ends at
	about 75 behind the yards): Land's boundary wall there (z 76 .. 78, Land.Bounds) gets a window
	the room's width up to EdgeWindow.Top (the wall is split into pieces round it, above it it stays),
	and the coastal rocks inside a room (Land.Cliffs: their tops at the ground, 0 .. 2) are lowered
	under its floor or, wholly above it, taken away. The room's walls, floor and ceiling and the
	mound round it close every window: nobody walks off the island through one.
]]
function PlotCave.openEdge(map: Instance)
	local land = map:FindFirstChild("Land")
	if not land then
		return
	end
	local room = BaseLayout.VipCave.Room
	local edge = PlotCave.EdgeWindow
	local windows: { { Lo: Vector3, Hi: Vector3 } } = {}
	local rooms: { { Cf: CFrame, Lo: Vector3, Hi: Vector3 } } = {}
	for _, plot in WorldLayout.Plots do
		local cf = WorldLayout.plotCFrame(plot)
		local lo, hi = worldBox(cf, Vector3.new(-edge.X, -1000, 70), Vector3.new(edge.X, edge.Top, room.Max.Z + 1))
		table.insert(windows, { Lo = lo, Hi = hi })
		local rlo, rhi = worldBox(cf, Vector3.new(room.Min.X, -0.45, 63.8), Vector3.new(room.Max.X, room.Max.Y, room.Max.Z))
		table.insert(rooms, { Cf = cf, Lo = rlo, Hi = rhi })
	end
	-- the boundary wall: each piece split along its long side round the windows it crosses
	local bounds = land:FindFirstChild("Bounds")
	if bounds then
		for _, wall in bounds:GetChildren() do
			if not wall:IsA("BasePart") then
				continue
			end
			local lo, hi = partBox(wall)
			local alongX = (hi.X - lo.X) >= (hi.Z - lo.Z)
			local cuts: { { A: number, B: number, Top: number } } = {}
			for _, w in windows do
				if overlaps(lo, hi, w.Lo, w.Hi) then
					local a = if alongX then math.max(lo.X, w.Lo.X) else math.max(lo.Z, w.Lo.Z)
					local b = if alongX then math.min(hi.X, w.Hi.X) else math.min(hi.Z, w.Hi.Z)
					table.insert(cuts, { A = a, B = b, Top = math.min(w.Hi.Y, hi.Y) })
				end
			end
			if #cuts == 0 then
				continue
			end
			table.sort(cuts, function(p, q)
				return p.A < q.A
			end)
			local function piece(a: number, b: number, y0: number, y1: number)
				if b - a < 0.01 or y1 - y0 < 0.01 then
					return
				end
				local copy = wall:Clone()
				local min = if alongX then Vector3.new(a, y0, lo.Z) else Vector3.new(lo.X, y0, a)
				local max = if alongX then Vector3.new(b, y1, hi.Z) else Vector3.new(hi.X, y1, b)
				copy.Size = max - min
				copy.CFrame = CFrame.new((min + max) / 2)
				copy.Parent = bounds
			end
			local from = if alongX then lo.X else lo.Z
			for _, c in cuts do
				piece(from, c.A, lo.Y, hi.Y)
				piece(c.A, c.B, c.Top, hi.Y)
				from = math.max(from, c.B)
			end
			piece(from, if alongX then hi.X else hi.Z, lo.Y, hi.Y)
			wall:Destroy()
		end
	end
	-- the coastal rocks inside a room: under its floor, or gone
	local cliffs = land:FindFirstChild("Cliffs")
	if cliffs then
		local doomed: { Instance } = {}
		for _, d in cliffs:GetDescendants() do
			if not d:IsA("BasePart") then
				continue
			end
			local lo, hi = partBox(d)
			for _, r in rooms do
				if overlaps(lo, hi, r.Lo, r.Hi) then
					local floor = r.Lo.Y
					local upright = d.CFrame.UpVector.Y > 0.999
					if lo.Y < floor - 0.05 and upright then
						local cut = hi.Y - floor
						d.Size -= Vector3.new(0, cut, 0)
						d.CFrame -= Vector3.new(0, cut / 2, 0)
					else
						table.insert(doomed, d)
					end
					break
				end
			end
		end
		for _, d in doomed do
			d:Destroy()
		end
	end
end

-- Every plot's cave (Map.VipCaves) and all their rock spots; the island's edge opened behind them.
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
	PlotCave.openEdge(map)
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
