--[[
	Quest giver NPC prototypes (src/shared/Builders/NpcBuilder.luau) for the
	owner's pictures; nothing here touches the map code. The renders are a
	three.js approximation of Roblox lighting (say so to the owner).

	  scene "npc_lineup" (lineup): every quest giver on a "character select"
	    stage: a round stone stage with a glowing rim, a back panel in each
	    NPC's Pop paint, the area name on a plate in front, each NPC on its
	    own quest pad (NpcBuilder.dress), the nameplate (name + title) and
	    the gold "!" quest marker stand-ins on the builder's NameplatePoint /
	    QuestMarkerPoint. A back row shows the gear from behind.
	  scene "npc_world" (world): the world (WorldBuilder + the rocks) with
	    all 8 NPCs placed into it at Preview.Spots (the one set of spots:
	    WP-Q2 moves this table verbatim into src/shared/Config/NpcSpots.luau),
	    each with a stand-in player (tools/lune/lib/dummy.luau) beside it for
	    scale, standing on the ground found under its spot (a downward ray
	    against the map's colliding parts), facing its Face point; the
	    nameplate and marker turn to the spot's shot camera.
	  scene "npc_spawn" (world): the same, with every nameplate and marker
	    turned to Preview.SpawnCamera (the view a player has at the town
	    spawn: both lobby NPCs and their markers).
	Shots: tools/preview/npc_shots.json
	  lune run tools/lune/export_scene.luau npc_lineup   (also npc_world, npc_spawn)
	  SHOTS_EXTRA=tools/preview/npc_shots.json node tools/preview/render.mjs npc_lineup
	  SHOTS_EXTRA=tools/preview/npc_shots.json node tools/preview/render.mjs npc_world
	  SHOTS_EXTRA=tools/preview/npc_shots.json node tools/preview/render.mjs npc_spawn

	In the game the nameplate and the marker are BillboardGuis on those
	points (always facing the camera, AlwaysOnTop off); here they are plates
	with a text face turned to the shot's camera, in the Pop look
	(PopTheme.Body plate with a black edge, white name, the title in the
	NPC's paint; a gold "!" with a black outline).
]]

local roblox = require("@lune/roblox") :: any

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local Enum = roblox.Enum
local rgb = Color3.fromRGB

local Preview = {}

Preview.Spacing = 6.6
Preview.StageTop = 1.2
Preview.BackZ = 80 -- the back row (rear view)
Preview.GOLD = rgb(255, 198, 36)
Preview.SpawnCamera = Vector3.new(0, 6, 32) -- the town spawn view (WorldLayout.SpawnPoint, behind the player)

-- In-world spots: the NPC's feet (x, z; y from the ground), the point it
-- faces (where players arrive from), and the camera the nameplate /
-- marker turn to (= the shot in npc_shots.json). Search = the height the
-- ground ray starts from (under the floor's ceiling); Side = which side of
-- the NPC the stand-in player stands on (1 = the picture's right).
-- Checked (2026-10-21, map v44, a scratch Lune run; tests/QuestNpcs.spec in
-- WP-Q2 keeps it): ground under the Root box flat within 0.45, the right
-- WorldLayout zone, the Root box + 2 studs outside every KeepOut box, the
-- Root box + 1 stud free of colliding map parts, the PromptPoint at least 14
-- studs from Main prompts with Distance 10 (hopper, lifts, elevator call
-- panels, counters) and 16 from the Distance 12 ones (Guild Board, Fossil
-- Dig, capsule stall, codex), at least 7 studs from rock spawns.
Preview.Spots = {
	{
		Id = "Scholar",
		X = -20,
		Z = -14,
		Search = 30,
		Face = Vector3.new(0, 0, 20),
		Camera = Vector3.new(-12, 5.4, -5.4),
		Side = 1,
	},
	{
		Id = "GemPolisher",
		X = 16,
		Z = 11,
		Search = 30,
		Face = Vector3.new(0, 0, 22),
		Camera = Vector3.new(7.9, 5.4, 19.6),
		Side = 1,
	},
	{
		Id = "Explorer",
		X = 23,
		Z = -128,
		Search = -4,
		Face = Vector3.new(6, 0, -134),
		Camera = Vector3.new(11.3, -7.0, -129.5),
		Side = 1,
	},
	{
		Id = "LavaSmith",
		X = 2,
		Z = -278,
		Search = -2,
		Face = Vector3.new(-2, 0, -263),
		Camera = Vector3.new(1.4, -7.0, -266.2),
		Side = 1,
	},
	{
		Id = "CrystalMiner",
		X = -14,
		Z = -414,
		Search = -30,
		Face = Vector3.new(-4, 0, -400),
		Camera = Vector3.new(-5.3, -35.0, -406.1),
		Side = 1,
	},
	{
		Id = "PalaceGuard",
		X = -6,
		Z = -756,
		Search = -205,
		Face = Vector3.new(-24, 0, -755),
		Camera = Vector3.new(-17.3, -212.6, -752.9),
		Side = 1,
	},
	{
		Id = "StormEngineer",
		X = -26,
		Z = -768,
		Search = -285,
		Face = Vector3.new(-8, 0, -764),
		Camera = Vector3.new(-14.2, -295.0, -767.9),
		Side = 1,
	},
	{
		Id = "CoreShaman",
		X = 0,
		Z = -760,
		Search = -385,
		Face = Vector3.new(-13, 0, -741),
		Camera = Vector3.new(-4.4, -393.7, -749.1),
		Side = 1,
	},
}

---------------------------------------------------------------- parts

local function part(parent: any, cf: any, size: any, color: any, material: any?, shape: any?): any
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function cylinder(parent: any, CF: any, center: any, height: number, diameter: number, color: any, material: any?): any
	return part(
		parent,
		CF.new(center) * CF.Angles(0, 0, math.pi / 2),
		Vector3.new(height, diameter, diameter),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A plate with text on its Front face (self-lit, like a BillboardGui).
local function textPlate(parent: any, cf: any, size: any, color: any, text: string, textColor: any, font: any?): any
	local p = part(parent, cf, size, color)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Text = text
	label.TextColor3 = textColor
	label.FontFace = roblox.Font.fromEnum(font or Enum.Font.FredokaOne)
	label.Parent = gui
	gui.Parent = p
	return p
end

-- The frame at `position` whose front (LookVector) turns to `camera` (level).
local function facingCamera(CF: any, position: any, camera: any): any
	local flat = Vector3.new(camera.X, position.Y, camera.Z)
	if (flat - position).Magnitude < 0.01 then
		return CF.new(position)
	end
	return CF.lookAt(position, flat)
end

local function pointOf(model: any, name: string): any
	local root = model.PrimaryPart
	local a = root:FindFirstChild(name)
	return (root.CFrame * a.CFrame).Position
end

-- The nameplate (name + title) and the gold "!" marker over an NPC, turned to `camera`.
function Preview.overhead(Loader: any, parent: any, model: any, camera: any, showMarker: boolean?)
	local CF = Loader.CFrame
	local NpcBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.NpcBuilder")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local outfit = NpcBuilder.ById[model:GetAttribute("Npc")]
	local accent = if outfit then outfit.Accent else Color3.new(1, 1, 1)
	local name = model:GetAttribute("DisplayName")
	local title = string.upper(model:GetAttribute("Title"))
	local plate = facingCamera(CF, pointOf(model, "NameplatePoint"), camera)
	local width = math.max(3.0, #name * 0.3 + 0.8)
	-- the black edge behind, the Body plate, the Well strip under the title
	part(parent, plate * CF.new(0, 0.1, 0.05), Vector3.new(width + 0.22, 1.22, 0.08), PopTheme.Outline)
	textPlate(parent, plate * CF.new(0, 0.28, 0), Vector3.new(width, 0.58, 0.1), PopTheme.Body, name, PopTheme.Ink)
	textPlate(parent, plate * CF.new(0, -0.2, 0), Vector3.new(width, 0.4, 0.1), PopTheme.Well, title, accent)
	if showMarker ~= false then
		local marker = facingCamera(CF, pointOf(model, "QuestMarkerPoint"), camera)
		-- black outline behind, the gold bar and dot in front (in the game: a BillboardGui, bobbing)
		part(parent, marker * CF.new(0, 0.34, 0.08), Vector3.new(1.0, 1.6, 0.12), PopTheme.Outline)
		part(parent, marker * CF.new(0, -0.86, 0.08), Vector3.new(1.0, 0.76, 0.12), PopTheme.Outline)
		part(parent, marker * CF.new(0, 0.34, 0), Vector3.new(0.64, 1.24, 0.2), Preview.GOLD, Enum.Material.Neon)
		part(parent, marker * CF.new(0, -0.86, 0), Vector3.new(0.64, 0.42, 0.2), Preview.GOLD, Enum.Material.Neon)
	end
end

---------------------------------------------------------------- lineup

function Preview.lineup(Loader: any, workspace: any)
	local CF = Loader.CFrame
	local NpcBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.NpcBuilder")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local folder = Instance.new("Model")
	folder.Name = "NpcLineup"
	folder.Parent = workspace
	local camera = Vector3.new(0, 6, -40)

	-- the ground, the stage and its glowing rim
	part(folder, CF.new(0, -0.5, 10), Vector3.new(220, 1, 160), rgb(72, 86, 70))
	local step = cylinder(folder, CF, Vector3.new(0, 0.3, 4), 0.6, 60, rgb(96, 92, 112))
	step.CastShadow = true
	local stage = cylinder(folder, CF, Vector3.new(0, 0.6 + 0.3, 4), 0.6, 56, rgb(150, 140, 166))
	stage.CastShadow = true
	cylinder(folder, CF, Vector3.new(0, 1.0, 4), 0.2, 56.5, rgb(236, 150, 80))
	-- a dark slate wall behind the panels, the title on top
	local wall = part(folder, CF.new(0, 7.5, 8.6), Vector3.new(60, 13, 1.2), rgb(52, 50, 72))
	wall.CastShadow = true
	part(folder, CF.new(0, 14.1, 8.6), Vector3.new(60.4, 0.4, 1.5), rgb(236, 150, 80))
	textPlate(
		folder,
		CF.new(0, 15.6, 8.3),
		Vector3.new(22, 2.6, 0.4),
		PopTheme.Outline,
		"QUEST GIVERS",
		Preview.GOLD,
		Enum.Font.LuckiestGuy
	)

	local count = #NpcBuilder.Outfits
	for i, outfit in NpcBuilder.Outfits do
		-- the camera looks along +Z, so +X is the picture's left: list order left to right
		local x = ((count + 1) / 2 - i) * Preview.Spacing
		local paint = NpcBuilder.paintOf(outfit.Id)
		part(folder, CF.new(x, 5.0, 5.2), Vector3.new(Preview.Spacing - 0.6, 7.2, 0.4), paint.Bottom:Lerp(rgb(20, 18, 34), 0.6)).CastShadow =
			true
		part(folder, CF.new(x, 1.5, 4.95), Vector3.new(Preview.Spacing - 0.6, 0.3, 0.2), paint.Top, Enum.Material.Neon)
		local area = if outfit.Area == "Lobby"
			then "LOBBY"
			elseif outfit.Area == "Quarry" then "MINE STATION"
			else string.upper((string.gsub(outfit.Area, "(%l)(%u)", "%1 %2")))
		-- the area name on a plate lying tilted on the stage in front of the pad
		textPlate(folder, CF.new(x, 1.46, -3.0) * CF.Angles(0.8, 0, 0), Vector3.new(4.4, 0.7, 0.1), PopTheme.Outline, area, outfit.Accent)
		-- each NPC stands on its own quest pad (NpcBuilder.dress)
		local model = NpcBuilder.build(outfit.Id, CF.new(x, Preview.StageTop, 0))
		model.Parent = folder
		Preview.overhead(Loader, folder, model, camera)
	end

	-- the back row (Preview.BackZ, hidden behind the wall from the front
	-- shots): the same NPCs turned away, for the rear view of their gear
	part(folder, CF.new(0, 0.3, Preview.BackZ), Vector3.new(60, 0.6, 10), rgb(150, 140, 166)).CastShadow = true
	for i, outfit in NpcBuilder.Outfits do
		local x = ((count + 1) / 2 - i) * Preview.Spacing
		local model = NpcBuilder.build(outfit.Id, CF.lookAt(Vector3.new(x, 0.6, Preview.BackZ), Vector3.new(x, 0.6, Preview.BackZ + 10)))
		model.Parent = folder
	end

	-- warm stage lights
	for _, x in { -18, 0, 18 } do
		local holder = part(folder, CF.new(x, 10, -8), Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1))
		holder.Transparency = 1
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 226, 190)
		light.Range = 24
		light.Brightness = 0.8
		light.Parent = holder
	end
end

---------------------------------------------------------------- in the world

-- The highest colliding surface under (x, top, z) among `root`'s parts
-- (a vertical ray against each part's box), or nil.
function Preview.groundAt(root: any, x: number, top: number, z: number): number?
	local origin = Vector3.new(x, top, z)
	local down = Vector3.new(0, -1, 0)
	local best: number? = nil
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d.Transparency < 0.95 then
			local cf = d.CFrame
			local o = cf:PointToObjectSpace(origin)
			local dir = cf:VectorToObjectSpace(down)
			local h = d.Size / 2
			local tmin, tmax = -math.huge, math.huge
			local hit = true
			for _, axis in { "X", "Y", "Z" } do
				local oa, da, ha = o[axis], dir[axis], h[axis]
				if math.abs(da) < 1e-9 then
					if oa < -ha or oa > ha then
						hit = false
						break
					end
				else
					local t1, t2 = (-ha - oa) / da, (ha - oa) / da
					tmin = math.max(tmin, math.min(t1, t2))
					tmax = math.min(tmax, math.max(t1, t2))
				end
			end
			if hit and tmax >= tmin and tmin >= 0 and (best == nil or tmin < (best :: number)) then
				best = tmin
			end
		end
	end
	return if best then top - (best :: number) else nil
end

-- Every spot's NPC (dressed, on its pad) with a stand-in player; the
-- nameplates and markers turn to each spot's Camera, or to `camera` when given.
function Preview.world(Loader: any, workspace: any, camera: any?)
	local CF = Loader.CFrame
	local NpcBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.NpcBuilder")
	local Dummy = require("./dummy")
	local map = workspace:FindFirstChild("Map") or workspace
	local folder = Instance.new("Model")
	folder.Name = "NpcPrototypes"
	folder.Parent = workspace
	for _, spot in Preview.Spots do
		local y = Preview.groundAt(map, spot.X, spot.Search, spot.Z) or 0
		local feet = Vector3.new(spot.X, y, spot.Z)
		local face = Vector3.new(spot.Face.X, y, spot.Face.Z)
		local model = NpcBuilder.build(spot.Id, CF.lookAt(feet, face))
		model.Parent = folder
		Preview.overhead(Loader, folder, model, camera or spot.Camera)
		-- a stand-in player (5 studs tall, like an R15 avatar) at the NPC, for scale
		local toward = (face - feet).Unit
		local side = toward:Cross(Vector3.new(0, 1, 0))
		local stand = feet + toward * 2.2 - side * 4.6 * (spot.Side or 1)
		local standGround = Preview.groundAt(map, stand.X, spot.Search, stand.Z) or y
		local at = Vector3.new(stand.X, standGround, stand.Z)
		Dummy.build(folder, CF, CF.lookAt(at, Vector3.new(feet.X, standGround, feet.Z)), "idle", {
			shirt = rgb(70, 120, 200),
			pants = rgb(46, 48, 64),
		})
		print(string.format("NPC %s at (%.1f, %.2f, %.1f), height %.2f", spot.Id, spot.X, y, spot.Z, model:GetAttribute("Height")))
	end
end

return Preview
