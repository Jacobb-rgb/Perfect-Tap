--[[
	WorldService: makes sure the map exists and the lighting is set.

	- If Workspace.Map is missing (empty place synced with Rojo) or was baked
	  by an older WorldBuilder version, the map is (re)built. A map with the
	  attribute KeepMap = true is never touched (for hand-edited maps).
	- NodeSpawn markers are moved to ServerStorage so clients never stream them.
	- Lighting is set from LightingConfig.Surface (Technology must be set to
	  Future in Studio: Lighting > Technology; default.project.json does it).
	- The parts tagged Mine/Diorama.CameraTag (the quarry's mossy rock) go in the
	  camera-only collision group: Roblox's camera stops at them, nothing touches them.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.LightingConfig)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)
local Diorama = require(script.Parent.Parent.World.Mine.Diorama)

local WorldService = {}

WorldService.Map = nil :: Model?
WorldService.NodeSpawns = nil :: Folder?

local EFFECT_CLASSES = {
	Atmosphere = "Atmosphere",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}

local function ensureEffect(name: string): Instance
	local className = EFFECT_CLASSES[name]
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local effect = Instance.new(className)
	effect.Name = name
	effect.Parent = Lighting
	return effect
end

local function applyPreset(presetName: string)
	local preset = LightingConfig.Presets[presetName]
	if not preset then
		return
	end
	local lightingTarget: any = Lighting
	for key, value in preset.Lighting do
		lightingTarget[key] = value
	end
	local groups: { [string]: { [string]: any } } = {
		Atmosphere = preset.Atmosphere,
		ColorCorrection = preset.ColorCorrection,
		Bloom = preset.Bloom,
		SunRays = preset.SunRays,
	}
	for group, values in groups do
		local effect: any = ensureEffect(group)
		for key, value in values do
			effect[key] = value
		end
	end
	if not Lighting:FindFirstChildOfClass("DepthOfFieldEffect") then
		local dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "DepthOfField"
		dof.Enabled = false
		dof.Parent = Lighting
	end
end

local function ensureMap(): Model
	local map = Workspace:FindFirstChild("Map") :: Model?
	if map then
		local keep = map:GetAttribute("KeepMap") == true
		local version = map:GetAttribute("BuilderVersion")
		if keep or version == WorldBuilder.Version then
			return map
		end
		warn(`[WorldService] Map is version {version}, builder is {WorldBuilder.Version}: rebuilding`)
		map:Destroy()
	end
	local started = os.clock()
	local built = WorldBuilder.build(Workspace)
	print(string.format("[WorldService] built map in %.2fs", os.clock() - started))
	return built
end

--[[
	(owner 2026-11-17: "the walls are still invisible") The quarry's mossy rock (Mine/Diorama:
	every chunk tagged Diorama.CameraTag) is solid and queryable so that Roblox's camera, which
	stops only at such parts, halts at the rock's front instead of looking out from inside it; in
	the camera-only group it never touches a player, an ore or anything else (WorldService.start).
	The baked map leaves the parts in Default: the group is a runtime registration.
]]
local function cameraOnly()
	local group = Diorama.CameraGroup
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end)
	if not ok then
		warn("[WorldService] camera group: " .. tostring(err))
		return
	end
	local function join(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
	for _, part in CollectionService:GetTagged(Diorama.CameraTag) do
		join(part)
	end
	CollectionService:GetInstanceAddedSignal(Diorama.CameraTag):Connect(join)
end

function WorldService.init()
	applyPreset("Surface")
	local map = ensureMap()
	WorldService.Map = map

	-- Keep node spawn markers on the server only.
	local markers = map:FindFirstChild("NodeSpawns")
	if markers then
		markers.Parent = ServerStorage
		WorldService.NodeSpawns = markers :: Folder
	else
		warn("[WorldService] Map has no NodeSpawns folder; no ore will grow")
	end

	-- Runtime folders for dynamic things.
	for _, name in { "Nodes", "Items", "Debris" } do
		if not Workspace:FindFirstChild(name) then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = Workspace
		end
	end

	cameraOnly()
end

-- After every service's init registered its collision groups: the camera-only group collides with
-- none of them (Default, the characters, the ore, the belts, itself).
function WorldService.start()
	local group = Diorama.CameraGroup
	local ok, groups = pcall(function()
		return PhysicsService:GetRegisteredCollisionGroups()
	end)
	if not ok then
		warn("[WorldService] collision groups: " .. tostring(groups))
		return
	end
	for _, info in groups do
		local name = (info :: any).name
		if type(name) == "string" then
			local set, err = pcall(function()
				PhysicsService:CollisionGroupSetCollidable(group, name, false)
			end)
			if not set then
				warn("[WorldService] camera group vs " .. name .. ": " .. tostring(err))
			end
		end
	end
end

function WorldService.getPlotModel(plotId: number): Model?
	local map = WorldService.Map
	local plots = map and map:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot_" .. plotId) :: Model?
end

return WorldService
