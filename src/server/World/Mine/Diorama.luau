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
	the Entrance, the elevator stop and the blaster gate sit on flat ground found in the diorama (no
	ore lift: the owner took them out 2026-11-14; the layout still keeps its square beside the
	elevator clear, so the rock spawns stay where they were). A few soft lights,
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
local WorldLayout = require(Shared:WaitForChild("Config"):WaitForChild("WorldLayout"))
local MineAmbience = require(Shared:WaitForChild("Config"):WaitForChild("MineAmbience"))
local Mine = ServerScriptService:WaitForChild("Server"):WaitForChild("World"):WaitForChild("Mine")
local MineKit = require(Mine:WaitForChild("MineKit"))
local DioramaData = require(Mine:WaitForChild("DioramaData"))

local Diorama = {}

-- A way through a floor's room wall that Land keeps open: on side Side ("N" = local -Z, "S" = +Z,
-- "E" = +X, "W" = -X), From..To along the wall (local X for N/S, Z for E/W), up to Top (local Y;
-- nil = the ceiling). Veil: a glowing curtain of that colour fills it, walked through but never
-- seen through (a cave's way out, where its dark lighting turned the sky beyond black).
export type Opening = { Side: string, From: number, To: number, Top: number?, Veil: Color3? }
export type Look = {
	Walls: { string }?,
	Thin: { string }?,
	Openings: { Opening }?,
	ElevatorWidth: number?,
	-- [x0, y0, z0, x1, y1, z1] floor-local, an optional 7th 1: the squashed thing keeps its own
	-- look in the sharper tiles (tools/meshy/process_glb.py flatten_boxes) rather than the ground's
	Flatten: { { number } }?,
	WallTops: { [string]: number }?,
	WallGaps: { [string]: number }?,
	-- a side's wall keeps in front of this floor-local coordinate (Z for N / S, X for E / W):
	-- a neighbouring floor's wall stands there (Diorama.lines)
	WallLimits: { [string]: number }?,
	WallDepths: { [string]: number }?,
	WallGlow: boolean?,
	WallColors: { Color3 }?,
	WallCap: Color3?,
	-- the rock walls on these sides faced with this uploaded model (MeshKit) instead of part shards
	WallMesh: string?,
	WallMeshSides: { string }?,
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
	Owner 2026-11-15 evening (floor 3 nearly white in his Studio test: "from Location 3 to the
	last, slightly reduce the brightness ... keep Locations 1 and 2 unchanged"): floors 3-6 got
	1.25-1.8x the light of floor 2 on their pale painted tiles (light x its exposure x the tiles'
	mean albedo, tools/meshy/albedo.json: 0.91 / 0.71 / 0.79 / 1.03 against floor 2's 0.57); their
	Brightness is cut so, with LightingConfig's exposure step, each lands at about 0.63-0.68, a
	little over floor 2 (they stay the brighter, colourful deep floors). These lights are the
	floors' own: MineKit.dimLights (the part-built floors' 60 %) never ran on a diorama.
]]
Diorama.Floors = {
	Quarry = {
		-- (owner 2026-11-14: "extend the walls and add them on top so it lines up: you must not see
		-- behind them at all") rock walls round the open pit over its own cliffs and the part-built
		-- rim behind them: the sides up to the diorama's tallest rocks, the town side just over the
		-- rim (the town still looks in), the back is the DEPTHS portal and the massif. Openings: the
		-- ramp down from the town and the DEPTHS portal's block (the train band's two went with the
		-- train, owner 2026-11-17: "remove all departures, rails and holes in the wall", and the VIP
		-- grotto's door with the VIP mine: the side walls run on over them). (owner 2026-11-16, his shot down the side wall: "the gap's still there: board
		-- it up, an earth hill round it, a wall in front and nobody sees it") the back too: the side
		-- walls ended on the back line and the corners between them and the diorama's back cliff
		-- showed the massif's waterfall and the rim; a back wall as tall as the sides, with the same
		-- grass top, closes both corners and stops either side of the DEPTHS portal (Lobby/Backdrop
		-- DepthsPortal: x -22..22, its own 40 tall block, the walkway x -9..9 through it).
		Walls = { "N", "E", "W", "S" },
		WallTops = { N = 28, E = 28, W = 28, S = 14 },
		-- the town side stands in front of the town ground's edge at local z 58 (its flat face
		-- showed once Land's cliff went) and stays thin, clear of the rim road
		WallGaps = { S = -1.4 },
		-- (2026-11-17, the Meshy chat's review: the back wall's slab, grass top and mossy chunks, the
		-- side walls' back ends and the corner hills stood up to 6 studs inside the Ember Caves, by
		-- its way out) the Ember Caves' thin south wall faces the quarry at local z -59.97: the back
		-- wall moves in until all of it stays in front (it lines up with the DEPTHS portal's front)
		WallLimits = { N = -59.9 },
		-- (owner 2026-11-14, his mossy cliff picture: "board it up with walls like these, so it
		-- looks the same, only you can't see behind it") the side walls are faced with his mossy
		-- cliff model (WallMesh, Diorama.MeshDepth deep chunks); the town side stays thin
		WallDepths = { S = 2 },
		WallMesh = "Prop_MossyCliff",
		WallMeshSides = { "N", "E", "W" },
		WallGlow = false,
		-- the diorama's lavender stone and its moss
		WallColors = { Color3.fromRGB(150, 146, 184), Color3.fromRGB(184, 178, 214), Color3.fromRGB(128, 124, 160) },
		WallCap = Color3.fromRGB(110, 170, 70),
		Openings = {
			{ Side = "S", From = -11, To = 11 },
			-- (the DEPTHS portal's block, a little wider)
			{ Side = "N", From = -22.4, To = 22.4 },
		},
		ElevatorWidth = 8,
		-- (owner 2026-11-14: "the bridges and things in the passages: to the sides, or just remove
		-- them") squashed in the sharper tiles, tools/meshy/jobs_2026-11-14.json "flatten": the blue
		-- sign gate (out to z 19.5: its two path ramps go too), the thin rock sheet in the VIP grotto
		-- door, the rail spur in the DEPTHS tunnel, the railing and lamp post across the elevator's
		-- way north, and two walk-only fixes (the door approach, a ramp onto the railing)
		Flatten = {
			{ 42.7, 0.1, -9.7, 47, 24, 4.4 },
			{ -3, 0.1, -45, 1.8, 3, -23 },
			{ -18.3, 0.1, 39, -5.9, 13, 44 },
			{ -9, 0.1, 7, 9, 40, 19.5 },
			{ 37.5, 0.1, 1.45, 43.14, 4, 7.1 },
			{ -15, 0.1, 44, -9, 0.5, 47 },
		},
		Light = Color3.fromRGB(255, 236, 214),
		Brightness = 0.8,
	},
	-- (owner 2026-11-17, his model of the quarry: "finish it and smooth it exactly like on this
	-- model") the quarry's newest tiles (MeshCatalog.FloorsNext) are his whole model with its own
	-- cliffs all round, grass on top: no rock walls of ours round it (the mossy cliff he called
	-- cubes); Floor1Quarry holds its edges with invisible bodies and lays smooth grass round it
	QuarryNext = {
		ElevatorWidth = 8,
		Light = Color3.fromRGB(255, 236, 214),
		Brightness = 0.8,
	},
	EmberCaves = {
		Walls = { "N", "E", "W" },
		Thin = { "S" },
		-- (owner 2026-11-14: "when I go through to the next location I see through the walls": from
		-- inside, under the caves' dark lighting, the town and the sky out through the DEPTHS
		-- portal showed as black holes) a glowing ember curtain fills the way in from the quarry
		Openings = {
			{ Side = "N", From = -12.3, To = 12.3, Top = 16.3 },
			{ Side = "S", From = -10, To = 10, Top = 17, Veil = Color3.fromRGB(80, 22, 10) },
		},
		-- (owner 2026-11-14: "the bridges and things in the passages: to the sides, or just remove
		-- them") squashed in the sharper tiles, tools/meshy/jobs_2026-11-14.json "flatten": the
		-- central wooden bridge over the lava (four boxes: a flat path across it stays; their 7th value 1
		-- keeps the deck's own wood, not the ground's colour), the wooden beam gate at z 26 and the
		-- sign gate at z 40 on the main path
		Flatten = {
			{ -9.5, 0.1, -10, 8.5, 20, 13, 1 },
			{ -7.5, 0.1, -20.5, 5.7, 12, -10, 1 },
			{ -6, 0.1, -21.9, 5.1, 12, -20.5, 1 },
			{ -5.9, 0.8, -26.5, 4.9, 12, -21.9, 1 },
			{ -9.5, 0.1, 23.5, 8.5, 15, 29 },
			{ -11, 0.1, 37, 10, 16, 44 },
		},
		Light = Color3.fromRGB(255, 222, 196),
		Brightness = 1.4,
	},
	DeepHollow = {
		Walls = { "N", "E", "W", "S" },
		Openings = { { Side = "S", From = -12.3, To = 12.3 } },
		-- (owner 2026-11-14: "the bridges and things in the passages: to the sides, or just remove
		-- them") squashed in the sharper tiles, tools/meshy/jobs_2026-11-14.json "flatten": the stone
		-- gate with the blue sign over the path from the tunnel (five boxes: the plaza and the raised
		-- path lie at two heights), the lantern posts' walk boxes on the path, a ramp onto the east
		-- lantern, the sliver by the east pillar
		Flatten = {
			{ -8.9, 0.7, 36.6, -1.6, 9, 39 },
			{ -8.9, 2.1, 39, -5.4, 9, 39.95 },
			{ -5.4, 0.7, 39, -1.6, 9, 39.95 },
			{ -1.6, 2.1, 36.6, 5, 9, 40.5 },
			{ 5, 0.7, 36.6, 12.8, 9, 40.5 },
			{ -1.9, 2.3, 23.4, 4.9, 9, 29.05 },
			{ 5, 2.3, 16.9, 8.1, 9, 23.5 },
			{ 12.8, 4.9, 37, 13.2, 9, 40 },
		},
		Light = Color3.fromRGB(220, 240, 255),
		Brightness = 1.4, -- (2026-11-15: was 1.8)
	},
	SunkenPalace = {
		Walls = { "N", "E", "W", "S" },
		-- (owner 2026-11-14: "the bridges and things in the passages: to the sides, or just remove
		-- them") squashed in the sharper tiles, tools/meshy/jobs_2026-11-14.json "flatten": the velvet
		-- rope across the hall's only doorway and two path ramps that stood as walls in front of it
		Flatten = {
			{ -4.3, 1, 40, 4.3, 5, 44.4 },
			{ -14, 1, 35, -8, 1.5, 40 },
			{ 9, 1, 35, 13, 1.5, 40 },
		},
		Light = Color3.fromRGB(255, 232, 210),
		Brightness = 1.5, -- (2026-11-15: was 1.6)
	},
	StormglassRift = {
		Walls = { "N", "E", "W", "S" },
		-- (owner 2026-11-14: "the bridges and things in the passages: to the sides, or just remove
		-- them") squashed in the sharper tiles, tools/meshy/jobs_2026-11-14.json "flatten": walk-only
		-- lanes through the two Tesla-coil gates on the central path (the gates stay) and two ramps in
		-- the gate passage
		Flatten = {
			{ -2.6, 1, 18.76, 2.5, 6.5, 20.63 },
			{ -3.4, 1, 33.76, 3.9, 5.8, 37.51 },
			{ 5.5, 1, 44, 6.5, 1.2, 45 },
			{ 10.5, 1, 44, 11.5, 1.2, 45 },
		},
		Light = Color3.fromRGB(230, 236, 255),
		Brightness = 2.0, -- (2026-11-15: was 2.4)
	},
	HeartstoneCore = {
		-- (owner 2026-11-14: "the bridges and things in the passages: to the sides, or just remove
		-- them") squashed in the sharper tiles, tools/meshy/jobs_2026-11-14.json "flatten": the stone
		-- gate over the south bridge (beam and inner pillars) and the pink rim rail across the ends of the
		-- two glass bridges
		Flatten = {
			{ -4.3, 0, 41, 7.3, 6, 44.22 },
			{ -28.7, 4.2, -39.1, -25, 9, -35.2 },
			{ 27.6, 4.2, -39.1, 31.2, 9, -35.1 },
		},
		Light = Color3.fromRGB(255, 226, 246),
		Brightness = 1.7, -- (2026-11-15: was 2.4)
	},
} :: { [string]: Look }

-- The look floor `index` is built with: its newest tile set's (Floors.<FloorId>Next) while the
-- floor is built from that set (MineFloors.usesNextSet), else its own.
function Diorama.look(index: number): Look
	local floor = MineFloors.ByIndex[index]
	local plain: Look = { Light = Color3.new(1, 1, 1), Brightness = 0.8 }
	if not floor then
		return plain
	end
	local nextLook = Diorama.Floors[floor.Id .. "Next"]
	if nextLook and MineFloors.usesNextSet(index) then
		return nextLook
	end
	return Diorama.Floors[floor.Id] or plain
end

Diorama.ElevatorWidth = 12 -- the tower's width on a 16-stud elevator spot (tools/meshy/floors/config.json)
Diorama.WallGap = 0.6 -- the room's walls stand this far outside the diorama's own outline
Diorama.WallDepth = 4 -- rock shards' depth
Diorama.ThinWall = 0.12 -- a thin wall's slab (look.Thin) ...
Diorama.ThinGap = -0.1 -- ... its line this far out of the diorama's outline (just inside: the portal's back is 0.3 behind)
Diorama.CeilingThickness = 0.5 -- its top at local 34: world 22 on the Ember Caves, the massif's foot
Diorama.WallBottom = -6 -- the walls reach this far under the usual ground
Diorama.CapHeight = 1.4 -- an open-air wall's grassy top
Diorama.CapReach = 0.25 -- ... it overhangs its slab's back by this much
Diorama.OpeningPad = 2.5 -- rock shards keep this far off an opening (theirs overhang a piece's ends)
-- a mesh-faced wall (look.WallMesh): its chunks' size and depth (back past its slab, into the
-- rim), how far their fronts stand out of the wall's line, how far they keep off an opening, and
-- where its slab starts behind the line (in the chunks' hollows the slab would show as flat patches)
Diorama.MeshChunk = Vector2.new(30, 17)
Diorama.MeshDepth = 7
Diorama.MeshOut = 0.8
Diorama.MeshPad = 0.4
Diorama.MeshSlabGap = 4
-- each chunk turns up to this much (radians) about its upright, and every other one sits
-- MeshStagger deeper or shallower: no two read as copies (their boxes' back corners move with it)
Diorama.MeshYaw = 0.04
Diorama.MeshStagger = 0.08
Diorama.VeilThickness = 0.3
--[[
	(owner 2026-11-16, three Studio shots of the quarry: "you can see there's no wall there, you can see
	behind the 3D object: put a wall there") Roblox's camera (Poppercam) stops only at parts that are
	CanCollide, CanQuery and nearly opaque. The rooms' slabs, lintels and ceilings were CanQuery false
	and the mossy cliff chunks (walls, the VIP door's slot) neither, so a camera swung toward a wall
	(it zooms out to 70) went through it and showed the rim, the void and the backs of the models
	behind. The slabs, lintels and ceilings are camera stops now (queryable). Made solid (2026-11-16)
	the mossy cliff chunks' collision boxes stood where the rock's ragged top and sides are not, and
	the owner met "a wall that's there but invisible".

	(owner 2026-11-17, after his test: "the walls are still invisible ... make sure they are actually
	visible") With the chunks looks only, the slab 4.8 behind their fronts was the only stop: a player
	walked into the rock, and off a high terrace (its walk boxes end 1-3 studs short of the rock) fell
	into the hollow inside the wall; the camera stopped at the slab, inside the rock, whose faces
	(seen from behind) are not drawn, so the near wall vanished. Now, on a mesh-faced wall:
	- its body: an invisible solid box from MeshBodyIn in front of the wall's line (at the chunks'
	  fronts, the rock's front-most bumps; its usual face lies 0.7-1.6 behind them low down) back to
	  its slab, from under the ground to the wall's top (WallBody). Nothing stands inside a chunk's
	  box: the camera never looks out of one, and no line of sight that respects CanCollide (the
	  pickup's, the beam's) ever meets one between two things in the room;
	- the walk boxes that end within LedgeReach of a body run on to it (Diorama.ledges);
	- every mossy chunk stops the camera and nothing else: solid and queryable, tagged CameraTag,
	  which WorldService puts in the CameraGroup collision group (it collides with no group), so the
	  camera halts at the rock's front while players and ore pass on to the body behind.
]]
Diorama.CameraStops = { "WallSlab", "Lintel", "Ceiling" }
Diorama.MeshBodyIn = Diorama.MeshOut
Diorama.LedgeReach = 5
Diorama.CameraGroup = "CameraOnly"
Diorama.CameraTag = "CameraOnly"
-- a veil's lighting portal: its tag (LightingController.PortalTag) and how far either side of it
-- the zones are probed for its two presets
Diorama.PortalTag = "LightingPortal"
Diorama.PortalProbe = 2

Diorama.LightHeight = 14
Diorama.LightRange = 48
Diorama.BoxDepth = 6 -- collision boxes reach this far under their top (and below the lowest ground)

local GROUND = { CanTouch = false, CanQuery = true, CanCollide = true, CastShadow = false, Transparency = 1 }
-- a mesh-faced wall's body (Diorama.MeshBodyIn): solid, never seen, never clicked or shot
local BODY = { CanTouch = false, CanQuery = false, CanCollide = true, CastShadow = false, Transparency = 1 }
-- a floor-level mesh-faced wall piece's body for Diorama.ledges: its side, its span along the wall,
-- its front (local X on E / W, Z on N / S) and the piece's bottom
export type Body = { Side: string, From: number, To: number, Front: number, Y0: number }
-- a path ramp's turn by its DioramaData dir (rising toward +X, -X, +Z, -Z; a wedge rises toward +Z)
local RAMP_TURN = { math.pi / 2, -math.pi / 2, 0, math.pi }
local GLOW = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }

--[[
	Floor `index`'s walk data (DioramaData): its newest tile set's (MeshCatalog.FloorsNext, measured
	on those tiles themselves: DioramaData.<FloorId>Next) while the floor is built from that set, else
	the floor's own (measured on its first set; the sharper set squashes its look.Flatten boxes into it).
]]
function Diorama.data(index: number): any
	local floor = MineFloors.ByIndex[index]
	if not floor then
		return nil
	end
	local nextData = (DioramaData :: any)[floor.Id .. "Next"]
	if nextData and MineFloors.usesNextSet(index) then
		return nextData
	end
	return DioramaData[floor.Id]
end

-- Whether floor `index` is built from its diorama (MineFloors.usesDiorama, and its layout exists).
function Diorama.has(index: number): boolean
	local floor = MineFloors.ByIndex[index]
	return floor ~= nil and Diorama.data(index) ~= nil and MineFloors.usesDiorama(index)
end

-- The world CFrame of a local point (x, y, z) of the floor.
local function at(origin: CFrame, p: Vector3): CFrame
	return origin * CFrame.new(p)
end

--[[
	The walk boxes (quintuples x0, z0, x1, z1, top) with every flatten box [x0, y0, z0, x1, y1, z1]
	(floor-local) applied: where a walk box overlaps one higher than its floor, the overlap's top is
	cut down to that floor and the rest of the box stays as it was (split round the overlap).
]]
function Diorama.flattenBoxes(boxes: { number }, flats: { { number } }): { number }
	local list: { { number } } = {}
	for i = 1, #boxes, 5 do
		table.insert(list, { boxes[i], boxes[i + 1], boxes[i + 2], boxes[i + 3], boxes[i + 4] })
	end
	for _, f in flats do
		local nextList: { { number } } = {}
		for _, r in list do
			local ix0, ix1 = math.max(r[1], f[1]), math.min(r[3], f[4])
			local iz0, iz1 = math.max(r[2], f[3]), math.min(r[4], f[6])
			if ix0 >= ix1 or iz0 >= iz1 or r[5] <= f[2] then
				table.insert(nextList, r)
			else
				table.insert(nextList, { ix0, iz0, ix1, iz1, f[2] })
				if r[1] < ix0 then
					table.insert(nextList, { r[1], r[2], ix0, r[4], r[5] })
				end
				if ix1 < r[3] then
					table.insert(nextList, { ix1, r[2], r[3], r[4], r[5] })
				end
				if r[2] < iz0 then
					table.insert(nextList, { ix0, r[2], ix1, iz0, r[5] })
				end
				if iz1 < r[4] then
					table.insert(nextList, { ix0, iz1, ix1, r[4], r[5] })
				end
			end
		end
		list = nextList
	end
	local out: { number } = {}
	for _, r in list do
		for _, v in r do
			table.insert(out, v)
		end
	end
	return out
end

-- The diorama's outline on the ground (floor-local X and Z), from its tiles' boxes.
function Diorama.footprint(index: number): (Vector2, Vector2)
	local floor = MineFloors.ByIndex[index]
	local data = Diorama.data(index)
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

-- Whether look's rock walls (on side `side`, else on any) are faced with its uploaded model
-- (look.WallMesh on look.WallMeshSides).
function Diorama.meshWalls(look: Look, side: string?): boolean
	if look.WallMesh == nil or not MeshKit.has(look.WallMesh) then
		return false
	end
	return side == nil or table.find(look.WallMeshSides or {}, side) ~= nil
end

--[[
	A box of wall faced with chunks of an uploaded model (the owner's mossy cliff): `front` = the
	bottom centre of the box's front face, its LookVector out of the wall; size = (width, height,
	depth), the box running `depth` back from the front. The chunks (opts.Chunk, about
	Diorama.MeshChunk) stand side by side and in rows, overlapping a little to fill it, never
	past its sides or top (a box a little taller than a chunk takes one stretched row); a narrow
	box takes narrower chunks (at most 2.2 times as tall as wide). Each chunk is turned a hair and set a hair forward or back from its neighbours, so
	the same model never repeats as one flat sheet. Returns the chunks (none without the template).
]]
function Diorama.meshFill(
	parent: Instance,
	asset: string,
	front: CFrame,
	size: Vector3,
	rng: Rng.Rng,
	opts: { Chunk: Vector2?, Name: string? }?
): { MeshPart }
	local out: { MeshPart } = {}
	if not MeshKit.has(asset) or size.X < 0.5 or size.Y < 0.5 then
		return out
	end
	local chunk = if opts and opts.Chunk then opts.Chunk else Diorama.MeshChunk
	local w = math.min(chunk.X, size.X)
	local h = math.min(size.Y, w * 2.2)
	if h > chunk.Y * 1.1 then
		h = chunk.Y
	end
	local cols = if size.X <= w + 0.01 then 1 else math.ceil((size.X - w) / (w * 0.75)) + 1
	local rows = if size.Y <= h + 0.01 then 1 else math.ceil((size.Y - h) / (h * 0.8)) + 1
	local colStep = if cols > 1 then (size.X - w) / (cols - 1) else 0
	local rowStep = if rows > 1 then (size.Y - h) / (rows - 1) else 0
	-- (the model's front with the vines is its +Z side: turned round, out of the wall)
	local turned = front * CFrame.Angles(0, math.pi, 0)
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local k = (row + col) % 2
			local x = -size.X / 2 + w / 2 + col * colStep
			local cf = turned
				* CFrame.new(x, h / 2 + row * rowStep, -size.Z / 2 + (if k == 0 then Diorama.MeshStagger else -Diorama.MeshStagger))
				* CFrame.Angles(0, rng:range(-Diorama.MeshYaw, Diorama.MeshYaw), 0)
			-- (solid and queryable for the camera only, Diorama.CameraTag: its box stands where the rock's
			-- ragged top and sides are not, so nobody else ever touches it)
			local p = MeshKit.part(
				asset,
				Vector3.new(w, h, size.Z),
				cf,
				{ Name = if opts and opts.Name then opts.Name else "MeshWall", CanCollide = true, CanQuery = true }
			)
			if p then
				p:AddTag(Diorama.CameraTag)
				p.Parent = parent
				table.insert(out, p)
			end
		end
	end
	return out
end

--[[
	The room's lines (floor-local): lo = (the W side's x, the N side's z), hi = (E's x, S's z). Each
	stands WallGap out of the diorama's outline (look.WallGaps; a thin wall's ThinGap, in front of
	whatever stands right behind it: the DEPTHS portal's back), moved in where look.WallLimits keeps
	all a side builds behind its line (its slab and grass top, its chunks, the walls running on along
	it to close the corners) in front of a neighbouring floor's wall.
]]
function Diorama.lines(index: number): (Vector2, Vector2)
	local look: Look = Diorama.look(index)
	local kind: { [string]: string } = {}
	local walls: { string } = look.Walls or {}
	local thin: { string } = look.Thin or {}
	for _, side in walls do
		kind[side] = "rock"
	end
	for _, side in thin do
		kind[side] = "thin"
	end
	local function gapOf(side: string): number
		local gaps = look.WallGaps
		if gaps and gaps[side] then
			return gaps[side]
		end
		return if kind[side] == "thin" then Diorama.ThinGap else Diorama.WallGap
	end
	-- how far behind its line a side builds (room(): behind(), plus the grass top's overhang; a
	-- mesh-faced side's chunks)
	local function reach(side: string): number
		local depths = look.WallDepths
		local r = if kind[side] == "rock"
			then (if depths and depths[side] then depths[side] else Diorama.WallDepth) + 2
			elseif kind[side] == "thin" then Diorama.ThinWall
			else 0
		r += Diorama.CapReach
		if Diorama.meshWalls(look, side) then
			-- (a chunk's box back to MeshDepth, its back corners turned out by up to MeshYaw)
			local turn = Diorama.MeshChunk.X / 2 * math.sin(Diorama.MeshYaw) + Diorama.MeshStagger
			r = math.max(r, Diorama.MeshDepth - Diorama.MeshOut + turn)
		end
		return r
	end
	local fpLo, fpHi = Diorama.footprint(index)
	local w, n = fpLo.X - gapOf("W"), fpLo.Y - gapOf("N")
	local e, s = fpHi.X + gapOf("E"), fpHi.Y + gapOf("S")
	local limits: { [string]: number } = look.WallLimits or {}
	if limits.W then
		w = math.max(w, limits.W + reach("W"))
	end
	if limits.N then
		n = math.max(n, limits.N + reach("N"))
	end
	if limits.E then
		e = math.min(e, limits.E - reach("E"))
	end
	if limits.S then
		s = math.min(s, limits.S - reach("S"))
	end
	return Vector2.new(w, n), Vector2.new(e, s)
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
local function room(model: Model, index: number, origin: CFrame, look: Look, cutaway: boolean): { Body }
	local floor = MineFloors.ByIndex[index]
	local pal = floor.Palette
	-- (rock shards in these: Mid, Light, Dark; the slab behind in the last)
	local colors: { Color3 } = look.WallColors or { pal.Mid, pal.Light, pal.Dark }
	local slabColor = colors[3]
	local rng = Rng.new("DioramaRoom" .. floor.Id)
	local folder = Instance.new("Model")
	folder.Name = "Room"
	folder.Parent = model
	local closed = MineFloors.CeilingFloors[index] == true
	local ceilingY = MineFloors.CeilingHeight
	local bottom = Diorama.WallBottom
	-- a side's rock shards' depth (look.WallDepths: a thin town-side wall) and how far its slab
	-- ends behind its line
	local function depthOf(side: string): number
		local depths = look.WallDepths
		return if depths and depths[side] then depths[side] else Diorama.WallDepth
	end
	local function reachOf(side: string): number
		return depthOf(side) + 2
	end
	-- each side's wall top: up into the ceiling in a closed room, else look.WallTops (an open-air
	-- floor's walls end in one straight line)
	local function wallTop(side: string): number
		local tops = look.WallTops
		local top = if tops and tops[side] then tops[side] else ceilingY
		return if closed then top + Diorama.CeilingThickness else top
	end
	-- (queryable: Diorama.CameraStops)
	local slabProps = { CanTouch = false, CanQuery = true, CanCollide = true, CastShadow = false }
	-- the mesh-faced pieces' bodies (Diorama.ledges runs the walk boxes on to them)
	local bodies: { Body } = {}
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
		return if kind[side] == "rock" then reachOf(side) elseif kind[side] == "thin" then Diorama.ThinWall else 0
	end
	-- each side's line (Diorama.lines)
	local lo, hi = Diorama.lines(index)

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
		-- (look.WallMesh uploaded: this side's rock wall is its chunks, the slab further back)
		local meshWall = rock and Diorama.meshWalls(look, side)
		local sa, sb = a + (padA or 0), b - (padB or 0)
		if meshWall then
			-- the owner's model over the whole piece, a lintel too (from just under the ground: no
			-- seam at its foot), a hair off an opening; a lintel's chunks reach over its jambs
			local lintel = y0 > bottom
			local ma = a + (if lintel then -2 elseif (padA or 0) > 0 then Diorama.MeshPad else 0)
			local mb = b - (if lintel then -2 elseif (padB or 0) > 0 then Diorama.MeshPad else 0)
			local yb = if lintel then y0 else -1
			if mb - ma > 1 then
				local mid = (point(ma, yb) + point(mb, yb)) / 2 + face * Diorama.MeshOut
				Diorama.meshFill(
					folder,
					look.WallMesh :: string,
					origin * CFrame.lookAt(mid, mid + face),
					Vector3.new(mb - ma, y1 - yb, Diorama.MeshDepth),
					rng
				)
			end
		elseif rock and y0 <= bottom and sb - sa > 2 then
			-- the shards from under the ground up to the ceiling (no solid facets in front of
			-- them: the diorama's walkable edge and its path ramps stay clear)
			MineKit.wall(
				folder,
				origin:PointToWorldSpace(point(sa, y0)),
				origin:PointToWorldSpace(point(sb, y0)),
				wallTop(side) - (if closed then Diorama.CeilingThickness * 0.2 else 0) - y0,
				origin:VectorToWorldSpace(face),
				colors,
				rng,
				{
					Depth = depthOf(side),
					Step = 9,
					Glow = if look.WallGlow == false then nil else pal.Crystal,
					Facets = false,
				}
			)
		end
		-- the slab right behind the shards' faces (whatever stands beyond the wall, Land's
		-- mountains between the caves, stays hidden where the shards are low), a thin wall's slab,
		-- a lintel over an opening
		local gap = if meshWall then Diorama.MeshSlabGap elseif rock then 0.3 else 0
		local thick = behind(side) - gap
		local mid = (from + to) / 2 - face * (gap + thick / 2)
		local along = (to - from).Magnitude
		local size = if side == "N" or side == "S" then Vector3.new(along, y1 - y0, thick) else Vector3.new(thick, y1 - y0, along)
		local slab =
			Geo.block(folder, at(origin, Vector3.new(mid.X, (y0 + y1) / 2, mid.Z)), size, slabColor, Enum.Material.Slate, slabProps)
		slab.Name = if y0 <= bottom then "WallSlab" else "Lintel"
		-- a mesh-faced piece's body (Diorama.MeshBodyIn): where its rock shows, nobody walks into it
		if meshWall then
			local depth = Diorama.MeshSlabGap + Diorama.MeshBodyIn
			local bodyMid = (from + to) / 2 + face * (Diorama.MeshBodyIn - depth / 2)
			local bodySize = if side == "N" or side == "S" then Vector3.new(along, y1 - y0, depth) else Vector3.new(depth, y1 - y0, along)
			local body = Geo.block(folder, at(origin, Vector3.new(bodyMid.X, (y0 + y1) / 2, bodyMid.Z)), bodySize, slabColor, nil, BODY)
			body.Name = "WallBody"
			local front = from + face * Diorama.MeshBodyIn
			table.insert(bodies, {
				Side = side,
				From = a,
				To = b,
				Front = if side == "N" or side == "S" then front.Z else front.X,
				Y0 = y0,
			})
		end
		-- an open-air wall's grassy top (the diorama's own cliffs end in grass)
		if look.WallCap and not closed then
			local capSize = if side == "N" or side == "S"
				then Vector3.new(along + 0.4, Diorama.CapHeight, thick + 1)
				else Vector3.new(thick + 1, Diorama.CapHeight, along + 0.4)
			local cap = Geo.block(
				folder,
				at(origin, Vector3.new(mid.X + face.X * 0.25, y1 - Diorama.CapHeight / 2 + 0.2, mid.Z + face.Z * 0.25)),
				capSize,
				look.WallCap,
				Enum.Material.Grass,
				{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
			)
			cap.Name = "WallCap"
		end
	end

	for _, side in { "N", "E", "S", "W" } do
		-- (Cutaway, the preview pictures: no front wall, as MineKit's floor contract has it)
		if not kind[side] or (cutaway and side == "S") then
			continue
		end
		local alongX = side == "N" or side == "S"
		local top = wallTop(side)
		-- (a wall meeting a lower one at a corner ends on that one's line, its shards held back: no
		-- tall corner stands over the lower wall, into the town)
		local startSide = if alongX then "W" else "N"
		local endSide = if alongX then "E" else "S"
		local startLow = kind[startSide] ~= nil and wallTop(startSide) < top
		local endLow = kind[endSide] ~= nil and wallTop(endSide) < top
		local a0 = if alongX then lo.X - (if startLow then 0 else behind("W")) else lo.Y - (if startLow then 0 else behind("N"))
		local a1 = if alongX then hi.X + (if endLow then 0 else behind("E")) else hi.Y + (if endLow then 0 else behind("S"))
		local cuts: { Opening } = {}
		for _, o in openings do
			if o.Side == side then
				table.insert(cuts, o)
			end
		end
		table.sort(cuts, function(p, q)
			return p.From < q.From
		end)
		local t, pad = a0, if startLow then Diorama.OpeningPad else 0
		for _, o in cuts do
			piece(side, t, o.From, bottom, top, pad, Diorama.OpeningPad)
			if o.Top and o.Top < top then
				piece(side, o.From, o.To, o.Top, top)
			end
			t, pad = o.To, Diorama.OpeningPad
		end
		piece(side, t, a1, bottom, top, pad, if endLow then Diorama.OpeningPad else 0)
	end

	-- the veils: a glowing curtain in an opening (look.Openings[*].Veil), just behind the wall's
	-- line, tucked a little behind its edges and lintel; walked through, never seen through. Each is
	-- a lighting portal (LightingController: tag Diorama.PortalTag, its LookVector into the room,
	-- attributes Inside / Outside = the presets of the zones either side): the light follows the
	-- camera's side and changes the frame the camera passes through; its sides part at the middle of
	-- a thin wall round it (attribute PlaneZ, along its own Z: a camera stopped on either face of
	-- that wall then lies on its own side)
	for _, o in openings do
		local color = o.Veil
		if not color or not kind[o.Side] or (cutaway and o.Side == "S") then
			continue
		end
		local alongX = o.Side == "N" or o.Side == "S"
		local line = if o.Side == "N" then lo.Y elseif o.Side == "S" then hi.Y elseif o.Side == "W" then lo.X else hi.X
		local outward = if o.Side == "N" or o.Side == "W" then -1 else 1
		local c = line + outward * (Diorama.ThinWall + 0.01 + Diorama.VeilThickness / 2)
		local vy0, vy1 = -0.5, (o.Top or wallTop(o.Side)) + 0.2
		local width = o.To - o.From + 0.4
		local mid = (o.From + o.To) / 2
		local pos = if alongX then Vector3.new(mid, (vy0 + vy1) / 2, c) else Vector3.new(c, (vy0 + vy1) / 2, mid)
		local inward = if alongX then Vector3.new(0, 0, -outward) else Vector3.new(-outward, 0, 0)
		local veil = Geo.block(
			folder,
			origin * CFrame.lookAt(pos, pos + inward),
			Vector3.new(width, vy1 - vy0, Diorama.VeilThickness),
			color,
			Enum.Material.Neon,
			{ CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
		)
		veil.Name = "Veil"
		local function presetAt(p: Vector3): string
			local zone = WorldLayout.zoneAt(origin:PointToWorldSpace(p))
			return if zone then zone.Lighting else "Surface"
		end
		veil:SetAttribute("Inside", presetAt(pos + inward * Diorama.PortalProbe))
		veil:SetAttribute("Outside", presetAt(pos - inward * Diorama.PortalProbe))
		-- (the wall's middle, from where its slab stands, along the veil's own Z = outward)
		local wallMid = if kind[o.Side] == "thin"
			then Diorama.ThinWall / 2
			else (behind(o.Side) + (if Diorama.meshWalls(look, o.Side) then Diorama.MeshSlabGap else 0.3)) / 2
		veil:SetAttribute("PlaneZ", (line + outward * wallMid - c) * outward)
		-- and the whole wall round it, its face for the portal (a camera seen through the wall beside
		-- the opening is out there too)
		local a0 = if alongX then lo.X - behind("W") else lo.Y - behind("N")
		local a1 = if alongX then hi.X + behind("E") else hi.Y + behind("S")
		local cy = (vy0 + vy1) / 2
		veil:SetAttribute("FaceX", math.max(math.abs(a0 - mid), math.abs(a1 - mid)))
		veil:SetAttribute("FaceY", math.max(cy - Diorama.WallBottom, wallTop(o.Side) - cy))
		veil:AddTag(Diorama.PortalTag)
	end

	if cutaway or not closed then
		return bodies
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
	return bodies
end

--[[
	(owner 2026-11-17: "the walls are still invisible") The diorama's terraces reach its mossy walls'
	rock, but the walk boxes measured from it end 1-3 studs short: a player stepped off into the gap
	and fell into the wall. Every walk box (quintuples x0, z0, x1, z1, top) whose edge toward a
	floor-level mesh-faced piece ends within LedgeReach in front of the piece's body runs on to it,
	alongside the piece only (never into an opening): one more box per such pair, from that edge to
	the body's front at the walk box's top. Returns the new boxes as quintuples.
]]
function Diorama.ledges(walk: { number }, bodies: { Body }): { number }
	local out: { number } = {}
	for _, body in bodies do
		if body.Y0 > Diorama.WallBottom then
			continue
		end
		local alongX = body.Side == "N" or body.Side == "S"
		for i = 1, #walk, 5 do
			local x0, z0, x1, z1, top = walk[i], walk[i + 1], walk[i + 2], walk[i + 3], walk[i + 4]
			local a0 = math.max(if alongX then x0 else z0, body.From)
			local a1 = math.min(if alongX then x1 else z1, body.To)
			if a1 - a0 <= 0.05 then
				continue
			end
			-- (the box's edge toward the wall, and how far short of the body it ends)
			local edge, gap
			if body.Side == "E" then
				edge, gap = x1, body.Front - x1
			elseif body.Side == "W" then
				edge, gap = x0, x0 - body.Front
			elseif body.Side == "S" then
				edge, gap = z1, body.Front - z1
			else
				edge, gap = z0, z0 - body.Front
			end
			if gap <= 0.01 or gap > Diorama.LedgeReach then
				continue
			end
			local e0, e1 = math.min(edge, body.Front), math.max(edge, body.Front)
			if alongX then
				table.insert(out, a0)
				table.insert(out, e0)
				table.insert(out, a1)
				table.insert(out, e1)
			else
				table.insert(out, e0)
				table.insert(out, a0)
				table.insert(out, e1)
				table.insert(out, a1)
			end
			table.insert(out, top)
		end
	end
	return out
end

function Diorama.build(index: number, parent: Instance, origin: CFrame, opts: { Cutaway: boolean? }?): Model
	local floor = MineFloors.ByIndex[index]
	local data = Diorama.data(index)
	local look: Look = Diorama.look(index)
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
	-- (the sharper tiles squash what stood in each look.Flatten box down to the box's floor: the walk
	-- heights, measured on the first tiles, are cut to it inside the box, the boxes split round it,
	-- and no path ramp reaching into one is built)
	local flats: { { number } } = if look.Flatten and MineFloors.floorTiles(index) == MeshCatalog.FloorsHD[floor.Id]
		then look.Flatten
		else {}
	-- (a path ramp reaching into a flatten box led up onto the squashed thing: skipped)
	local function overlapsFlat(x0: number, z0: number, x1: number, z1: number): boolean
		for _, f in flats do
			if math.min(x1, f[4]) - math.max(x0, f[1]) > 0.05 and math.min(z1, f[6]) - math.max(z0, f[3]) > 0.05 then
				return true
			end
		end
		return false
	end
	local walk = Diorama.flattenBoxes(data.Boxes, flats)
	for i = 1, #walk, 5 do
		local x0, z0, x1, z1, top = walk[i], walk[i + 1], walk[i + 2], walk[i + 3], walk[i + 4]
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
		if overlapsFlat(x0, z0, x1, z1) then
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
	if closed or look.Walls then
		local bodies = room(model, index, origin, look, opts ~= nil and opts.Cutaway == true)
		-- the walk boxes that end just short of a mesh-faced wall run on to its body
		local ledges = Diorama.ledges(walk, bodies)
		for i = 1, #ledges, 5 do
			local x0, z0, x1, z1, ledgeTop = ledges[i], ledges[i + 1], ledges[i + 2], ledges[i + 3], ledges[i + 4]
			local bottom = math.min(ledgeTop - Diorama.BoxDepth, data.Bottom - Diorama.BoxDepth)
			local box = Geo.block(
				groundFolder,
				at(origin, Vector3.new((x0 + x1) / 2, (ledgeTop + bottom) / 2, (z0 + z1) / 2)),
				Vector3.new(x1 - x0, ledgeTop - bottom, z1 - z0),
				floor.Palette.Ground,
				nil,
				GROUND
			)
			box.Name = "Ledge"
		end
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
