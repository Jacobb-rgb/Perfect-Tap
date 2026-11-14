--!strict
--[[
	Mine floors from the owner's dioramas (made with Meshy, 2026-11-13; docs/plans/MESHY_MODELS_PLAN.md).
	The owner: "I made the six places much prettier, just scale them up and put them in the game".

	  Diorama.has(index)                        the floor is its diorama (MineFloors.usesDiorama)
	  Diorama.build(index, parent, origin, opts?) -> Model "MineFloor<N>" with MineKit's floor contract

	The diorama's tiles (Floor_<Id>_<NN>, looks only) are scaled evenly into the floor's footprint
	with its usual ground at local y = 0 and its centre at x = z = 0 (DioramaData, made by
	tools/meshy/floor_heights.py + floor_layout.py from the processed tiles). Players walk on
	invisible collision boxes made from the diorama's walk heights; the RockSpawns, the GiantSpawn,
	the Entrance, the elevator stop, the ore lift spot (a steel deck where the lift stands higher
	than the ground) and the blaster gate sit on flat ground found in the diorama. A few soft lights,
	the floor's ambience spots and, for the cave floors, a closed room of rock walls round the diorama
	under one ceiling height for every cave floor (MineFloors.CeilingHeight).
	The floor module adds its own extras (floor 6: the void enclosure and the VoidCatcher).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local MeshKit = require(Shared:WaitForChild("Builders"):WaitForChild("MeshKit"))
local MeshCatalog = require(Shared:WaitForChild("Config"):WaitForChild("MeshCatalog"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local MineAmbience = require(Shared:WaitForChild("Config"):WaitForChild("MineAmbience"))
local Mine = ServerScriptService:WaitForChild("Server"):WaitForChild("World"):WaitForChild("Mine")
local MineKit = require(Mine:WaitForChild("MineKit"))
local DioramaData = require(Mine:WaitForChild("DioramaData"))

local Diorama = {}

-- A way through a floor's room wall that Land keeps open: on side Side ("N" = local -Z, "S" = +Z,
-- "E" = +X, "W" = -X), From..To along the wall (local X for N/S, Z for E/W), up to Top (local Y;
-- nil = the ceiling).
export type Opening = { Side: string, From: number, To: number, Top: number? }
export type Look = {
	Walls: { string }?,
	Thin: { string }?,
	Openings: { Opening }?,
	ElevatorWidth: number?,
	Flatten: { number }?,
	Light: Color3,
	Brightness: number,
}

--[[
	Per floor: the cave floors' closed room (MineFloors.CeilingFloors: rock walls on the Walls sides,
	tight round the diorama, and one dark ceiling at MineFloors.CeilingHeight; owner 2026-11-14: "no
	void behind the walls, all ceilings the same"), the elevator tower's width (its spot's size less
	a margin),
	the light colour and strength. The quarry is open sky; the Heartstone Core has its own void
	enclosure (Floor6Core). The Ember Caves' south side meets the quarry's back 1.7 studs away: a
	thin wall there round the DEPTHS portal's 18 x 16 way in (Lobby/Backdrop, its frame hides the
	wall's edges); its north wall keeps Land's tunnel down to the Deep Hollow open, and the
	Hollow's south wall the tunnel's other end (both openings a little wider than the tunnel's
	x -12..12 and its roof at world 4: no faces shared with Land's, nothing flickers).
	(the dioramas' painted colours need near-white light to read; their caves are dark otherwise)
]]
Diorama.Floors = {
	Quarry = {
		ElevatorWidth = 8,
		-- the blue sign gate in the middle of the quarry (owner 2026-11-14: in the way), squashed in
		-- the sharper tiles: tools/meshy/jobs_2026-11-14.json "flatten" x -9..9, z 7..17
		Flatten = { -9, 7, 9, 17 },
		Light = Color3.fromRGB(255, 236, 214),
		Brightness = 0.8,
	},
	EmberCaves = {
		Walls = { "N", "E", "W" },
		Thin = { "S" },
		Openings = { { Side = "N", From = -12.3, To = 12.3, Top = 16.3 }, { Side = "S", From = -10, To = 10, Top = 17 } },
		Light = Color3.fromRGB(255, 222, 196),
		Brightness = 1.4,
	},
	DeepHollow = {
		Walls = { "N", "E", "W", "S" },
		Openings = { { Side = "S", From = -12.3, To = 12.3 } },
		Light = Color3.fromRGB(220, 240, 255),
		Brightness = 1.8,
	},
	SunkenPalace = { Walls = { "N", "E", "W", "S" }, Light = Color3.fromRGB(255, 232, 210), Brightness = 1.6 },
	StormglassRift = { Walls = { "N", "E", "W", "S" }, Light = Color3.fromRGB(230, 236, 255), Brightness = 2.4 },
	HeartstoneCore = { Light = Color3.fromRGB(255, 226, 246), Brightness = 2.4 },
} :: { [string]: Look }

Diorama.ElevatorWidth = 12 -- the tower's width on a 16-stud elevator spot (tools/meshy/floors/config.json)
Diorama.WallGap = 0.6 -- the room's walls stand this far outside the diorama's own outline
Diorama.WallDepth = 4 -- rock shards' depth
Diorama.ThinWall = 0.12 -- a thin wall's slab (look.Thin) ...
Diorama.ThinGap = -0.1 -- ... its line this far out of the diorama's outline (just inside: the portal's back is 0.3 behind)
Diorama.CeilingThickness = 0.5 -- its top at local 34: world 22 on the Ember Caves, the massif's foot
Diorama.WallBottom = -6 -- the walls reach this far under the usual ground
Diorama.OpeningPad = 2.5 -- rock shards keep this far off an opening (theirs overhang a piece's ends)
Diorama.FlattenTop = 0.1 -- the walk height of a squashed thing's patch (the flatten box's floor)

Diorama.LightHeight = 14
Diorama.LightRange = 48
Diorama.BoxDepth = 6 -- collision boxes reach this far under their top (and below the lowest ground)

local GROUND = { CanTouch = false, CanQuery = true, CanCollide = true, CastShadow = false, Transparency = 1 }
-- a path ramp's turn by its DioramaData dir (rising toward +X, -X, +Z, -Z; a wedge rises toward +Z)
local RAMP_TURN = { math.pi / 2, -math.pi / 2, 0, math.pi }
local GLOW = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local STEEL = Color3.fromRGB(70, 74, 88)

-- Whether floor `index` is built from its diorama (MineFloors.usesDiorama, and its layout exists).
function Diorama.has(index: number): boolean
	local floor = MineFloors.ByIndex[index]
	return floor ~= nil and DioramaData[floor.Id] ~= nil and MineFloors.usesDiorama(index)
end

-- The world CFrame of a local point (x, y, z) of the floor.
local function at(origin: CFrame, p: Vector3): CFrame
	return origin * CFrame.new(p)
end

-- The diorama's outline on the ground (floor-local X and Z), from its tiles' boxes.
function Diorama.footprint(index: number): (Vector2, Vector2)
	local floor = MineFloors.ByIndex[index]
	local data = DioramaData[floor.Id]
	local s = data.Scale
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, name in MineFloors.floorTiles(index) or MeshCatalog.Floors[floor.Id] do
		local entry = MeshCatalog.Assets[name]
		local c, half = entry.Center, entry.Box / 2
		x0 = math.min(x0, (c.X - half.X - data.CenterN.X) * s)
		x1 = math.max(x1, (c.X + half.X - data.CenterN.X) * s)
		z0 = math.min(z0, (c.Z - half.Z - data.CenterN.Y) * s)
		z1 = math.max(z1, (c.Z + half.Z - data.CenterN.Y) * s)
	end
	return Vector2.new(x0, z0), Vector2.new(x1, z1)
end

--[[
	The closed room of a cave floor: on each side of look.Walls a jagged rock wall (MineKit.wall)
	in the floor's palette with a dark slab right behind it from under the ground up into the
	ceiling, on each side of look.Thin only a thin dark slab (where the room meets the quarry: the
	town never sees it), both split round look.Openings (a lintel over an opening with a Top); one
	ceiling slab over the whole room at MineFloors.CeilingHeight, out over the walls (never past a
	side without one). Solid: nobody walks off the diorama's open front. Cutaway (the preview
	pictures) leaves out the ceiling and the front (+Z) wall.
]]
local function room(model: Model, index: number, origin: CFrame, look: Look, cutaway: boolean)
	local floor = MineFloors.ByIndex[index]
	local pal = floor.Palette
	local colors = { pal.Mid, pal.Light, pal.Dark }
	local rng = Rng.new("DioramaRoom" .. floor.Id)
	local folder = Instance.new("Model")
	folder.Name = "Room"
	folder.Parent = model
	local ceilingY = MineFloors.CeilingHeight
	local bottom = Diorama.WallBottom
	local depth = Diorama.WallDepth
	local reach = depth + 2 -- a rock wall's slab ends this far behind its line
	local slabTop = ceilingY + Diorama.CeilingThickness
	local slabProps = { CanTouch = false, CanQuery = false, CanCollide = true, CastShadow = false }
	local walls: { string } = look.Walls or {}
	local thin: { string } = look.Thin or {}
	local openings: { Opening } = look.Openings or {}
	local kind: { [string]: string } = {}
	for _, side in walls do
		kind[side] = "rock"
	end
	for _, side in thin do
		kind[side] = "thin"
	end
	-- how far behind a side's line its wall reaches (the walls along it run on that far: the
	-- corners close; the ceiling covers it)
	local function behind(side: string): number
		return if kind[side] == "rock" then reach elseif kind[side] == "thin" then Diorama.ThinWall else 0
	end
	-- each side's line: WallGap out of the diorama's outline, a thin wall's ThinGap (in front of
	-- whatever stands right behind it: the DEPTHS portal's back)
	local fpLo, fpHi = Diorama.footprint(index)
	local function gapOf(side: string): number
		return if kind[side] == "thin" then Diorama.ThinGap else Diorama.WallGap
	end
	local lo = Vector2.new(fpLo.X - gapOf("W"), fpLo.Y - gapOf("N"))
	local hi = Vector2.new(fpHi.X + gapOf("E"), fpHi.Y + gapOf("S"))

	-- one wall piece from a to b along the side's line, from y0 up to y1
	-- (padA / padB: the shards keep this far off a piece's end at an opening; theirs overhang it)
	local function piece(side: string, a: number, b: number, y0: number, y1: number, padA: number?, padB: number?)
		if b - a < 0.5 then
			return
		end
		local function point(t: number, y: number): Vector3
			return if side == "N"
				then Vector3.new(t, y, lo.Y)
				elseif side == "S" then Vector3.new(t, y, hi.Y)
				elseif side == "W" then Vector3.new(lo.X, y, t)
				else Vector3.new(hi.X, y, t)
		end
		-- (toward the room)
		local face = if side == "N"
			then Vector3.new(0, 0, 1)
			elseif side == "S" then Vector3.new(0, 0, -1)
			elseif side == "W" then Vector3.new(1, 0, 0)
			else Vector3.new(-1, 0, 0)
		local from, to = point(a, y0), point(b, y0)
		local rock = kind[side] == "rock"
		local sa, sb = a + (padA or 0), b - (padB or 0)
		if rock and y0 <= bottom and sb - sa > 2 then
			-- the shards from under the ground up to the ceiling (no solid facets in front of
			-- them: the diorama's walkable edge and its path ramps stay clear)
			MineKit.wall(
				folder,
				origin:PointToWorldSpace(point(sa, y0)),
				origin:PointToWorldSpace(point(sb, y0)),
				ceilingY + Diorama.CeilingThickness * 0.8 - y0,
				origin:VectorToWorldSpace(face),
				colors,
				rng,
				{
					Depth = depth,
					Step = 9,
					Glow = pal.Crystal,
					Facets = false,
				}
			)
		end
		-- the slab right behind the shards' faces (whatever stands beyond the wall, Land's
		-- mountains between the caves, stays hidden where the shards are low), a thin wall's slab,
		-- a lintel over an opening
		local gap = if rock then 0.3 else 0
		local thick = behind(side) - gap
		local mid = (from + to) / 2 - face * (gap + thick / 2)
		local along = (to - from).Magnitude
		local size = if side == "N" or side == "S" then Vector3.new(along, y1 - y0, thick) else Vector3.new(thick, y1 - y0, along)
		local slab = Geo.block(folder, at(origin, Vector3.new(mid.X, (y0 + y1) / 2, mid.Z)), size, pal.Dark, Enum.Material.Slate, slabProps)
		slab.Name = if y0 <= bottom then "WallSlab" else "Lintel"
	end

	for _, side in { "N", "E", "S", "W" } do
		-- (Cutaway, the preview pictures: no front wall, as MineKit's floor contract has it)
		if not kind[side] or (cutaway and side == "S") then
			continue
		end
		local alongX = side == "N" or side == "S"
		local a0 = if alongX then lo.X - behind("W") else lo.Y - behind("N")
		local a1 = if alongX then hi.X + behind("E") else hi.Y + behind("S")
		local cuts: { Opening } = {}
		for _, o in openings do
			if o.Side == side then
				table.insert(cuts, o)
			end
		end
		table.sort(cuts, function(p, q)
			return p.From < q.From
		end)
		local t, pad = a0, 0
		for _, o in cuts do
			piece(side, t, o.From, bottom, slabTop, pad, Diorama.OpeningPad)
			if o.Top and o.Top < ceilingY then
				piece(side, o.From, o.To, o.Top, slabTop)
			end
			t, pad = o.To, Diorama.OpeningPad
		end
		piece(side, t, a1, bottom, slabTop, pad, 0)
	end

	if cutaway then
		return
	end
	-- the ceiling over the whole room and its walls
	local x0, x1 = lo.X - behind("W"), hi.X + behind("E")
	local z0, z1 = lo.Y - behind("N"), hi.Y + behind("S")
	local ceiling = Geo.block(
		folder,
		at(origin, Vector3.new((x0 + x1) / 2, ceilingY + Diorama.CeilingThickness / 2, (z0 + z1) / 2)),
		Vector3.new(x1 - x0, Diorama.CeilingThickness, z1 - z0),
		pal.Dark,
		Enum.Material.Slate,
		slabProps
	)
	ceiling.Name = "Ceiling"
end

function Diorama.build(index: number, parent: Instance, origin: CFrame, opts: { Cutaway: boolean? }?): Model
	local floor = MineFloors.ByIndex[index]
	local data = DioramaData[floor.Id]
	local look: Look = Diorama.Floors[floor.Id] or { Light = Color3.new(1, 1, 1), Brightness = 0.8 }
	local closed = MineFloors.CeilingFloors[index] == true
	local model = Instance.new("Model")
	model.Name = "MineFloor" .. index
	model:SetAttribute("Floor", index)
	model:SetAttribute("FloorId", floor.Id)
	model:SetAttribute("Diorama", true)
	model.Parent = parent

	-- the tiles: looks only (players stand on the boxes below)
	local tilesFolder = Instance.new("Folder")
	tilesFolder.Name = "Diorama"
	tilesFolder.Parent = model
	local s = data.Scale
	for _, name in MineFloors.floorTiles(index) or MeshCatalog.Floors[floor.Id] do
		local entry = MeshCatalog.Assets[name]
		local c = entry.Center
		local pos = Vector3.new((c.X - data.CenterN.X) * s, (c.Y - data.GroundN) * s, (c.Z - data.CenterN.Y) * s)
		local tile = MeshKit.part(name, entry.Box * s, at(origin, pos), { CastShadow = true })
		if tile then
			tile.Parent = tilesFolder
		end
	end

	-- the ground: invisible boxes from the walk heights
	local groundFolder = Instance.new("Folder")
	groundFolder.Name = "Ground"
	groundFolder.Parent = model
	-- (the sharper tiles squash what stood in look.Flatten flat: its walk heights, measured on the
	-- first tiles, go down to the patch it left, and no path ramp leads up onto it)
	local flat = if look.Flatten and MineFloors.floorTiles(index) == MeshCatalog.FloorsHD[floor.Id] then look.Flatten else nil
	local function flattened(x: number, z: number): boolean
		return flat ~= nil and x > flat[1] and x < flat[3] and z > flat[2] and z < flat[4]
	end
	local boxes = data.Boxes
	for i = 1, #boxes, 5 do
		local x0, z0, x1, z1, top = boxes[i], boxes[i + 1], boxes[i + 2], boxes[i + 3], boxes[i + 4]
		if flattened((x0 + x1) / 2, (z0 + z1) / 2) then
			top = math.min(top, Diorama.FlattenTop)
		end
		local bottom = math.min(top - Diorama.BoxDepth, data.Bottom - Diorama.BoxDepth)
		local box = Geo.block(
			groundFolder,
			at(origin, Vector3.new((x0 + x1) / 2, (top + bottom) / 2, (z0 + z1) / 2)),
			Vector3.new(x1 - x0, top - bottom, z1 - z0),
			floor.Palette.Ground,
			nil,
			GROUND
		)
		box.Name = "Ground"
	end
	-- the path ramps: invisible wedges where a terrace's edge would need a jump from the
	-- elevator's level (DioramaData.Ramps); a WedgePart's high side is its +Z, turned the way it rises
	local ramps = data.Ramps
	for i = 1, #ramps, 7 do
		local x0, z0, x1, z1, y, rise, dir = ramps[i], ramps[i + 1], ramps[i + 2], ramps[i + 3], ramps[i + 4], ramps[i + 5], ramps[i + 6]
		if flattened((x0 + x1) / 2, (z0 + z1) / 2) then
			continue
		end
		local alongX = dir <= 2
		local across = if alongX then z1 - z0 else x1 - x0
		local along = if alongX then x1 - x0 else z1 - z0
		local cf = at(origin, Vector3.new((x0 + x1) / 2, y + rise / 2, (z0 + z1) / 2)) * CFrame.Angles(0, RAMP_TURN[dir], 0)
		local ramp = Geo.wedge(groundFolder, cf, Vector3.new(across, rise, along), floor.Palette.Ground, nil, GROUND)
		ramp.Name = "Ramp"
	end

	-- the rock spawns and the Giant Crystal's spot
	local spawns = MineKit.spawns(model)
	for _, spawn in data.Spawns do
		spawns.add(at(origin, Vector3.new(spawn[1], spawn[2], spawn[3])), spawn[4] == true)
	end
	MineKit.marker(model, "GiantSpawn", at(origin, data.Giant))

	-- arrival: the entrance, the elevator stop facing the main path, the blaster gate over it
	local anchors = data.Anchors
	MineKit.marker(model, "Entrance", at(origin, anchors.Entrance))
	-- (owner 2026-11-14: "taller, always from the ground to the ceiling, lit and big": the tower
	-- reaches the room's ceiling, in the open quarry the top of its cliffs, in the void up as high)
	local e = anchors.Elevator
	local top = if closed then MineFloors.CeilingHeight else math.min(MineFloors.CeilingHeight, data.Top)
	MineKit.elevator(model, origin * CFrame.lookAt(e, Vector3.new(0, e.Y, e.Z)), index, {
		Height = top - e.Y - 0.6,
		Width = look.ElevatorWidth or Diorama.ElevatorWidth,
	})
	local pal = floor.Palette
	-- (no gate where every blaster may go: floor 1's "BLASTER LV 1+" only stood in the way)
	if floor.MinBlaster > 1 and anchors.Gate then
		MineKit.gate(model, at(origin, anchors.Gate), 12, floor.MinBlaster, { pal.Mid, pal.Light, pal.Dark })
	end

	-- the ore lift (Railway builds it from TrainConfig at MineFloors.liftSpot): a steel deck under it
	-- where it stands higher than the diorama's ground
	local liftSpot = MineFloors.liftSpot(index)
	if liftSpot then
		local groundY = anchors.Lift and anchors.Lift.Y or 0
		if liftSpot.Y - groundY > 0.3 then
			local h = liftSpot.Y - groundY + 1
			local deck = Geo.block(
				model,
				at(origin, Vector3.new(liftSpot.X, liftSpot.Y - h / 2, liftSpot.Z)),
				Vector3.new(9, h, 9),
				STEEL,
				Enum.Material.DiamondPlate,
				SOLID
			)
			deck.Name = "LiftDeck"
		end
		MineKit.oreLift(model, origin:PointToWorldSpace(liftSpot), floor.Id)
	end

	-- soft lights over the walkable ground
	local lightFolder = Instance.new("Folder")
	lightFolder.Name = "Lights"
	lightFolder.Parent = model
	for _, p in data.Lights do
		local holder = Geo.block(
			lightFolder,
			at(origin, p + Vector3.new(0, Diorama.LightHeight, 0)),
			Vector3.new(0.4, 0.4, 0.4),
			look.Light,
			nil,
			GLOW
		)
		holder.Name = "Light"
		local light = Instance.new("PointLight")
		light.Color = look.Light
		light.Range = Diorama.LightRange
		light.Brightness = look.Brightness
		light.Shadows = false
		light.Parent = holder
	end

	-- the cave floors' closed room up to the one ceiling height (the sky never shows in the caves)
	if closed then
		room(model, index, origin, look, opts ~= nil and opts.Cutaway == true)
	end

	-- ambience: the floor's kinds on ground boxes spread over the floor
	local kinds = MineAmbience.Floors[floor.Id] or {}
	if #kinds > 0 then
		for i = 1, math.min(6, #data.Lights) do
			MineKit.ambienceNear(groundFolder, kinds[(i - 1) % #kinds + 1], origin:PointToWorldSpace(data.Lights[i] + Vector3.new(0, 1, 0)))
		end
	end

	return model
end

return Diorama
