--[[
	WorldService: makes sure the map exists and the lighting is set.

	- If Workspace.Map is missing (empty place synced with Rojo) or was baked
	  by an older WorldBuilder version, the map is (re)built. A map with the
	  attribute KeepMap = true is never touched (for hand-edited maps).
	- NodeSpawn markers are moved to ServerStorage so clients never stream them.
	- Lighting is set from LightingConfig.Surface (Technology must be set to
	  Future in Studio: Lighting > Technology; default.project.json does it).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.LightingConfig)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

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
end

function WorldService.getPlotModel(plotId: number): Model?
	local map = WorldService.Map
	local plots = map and map:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot_" .. plotId) :: Model?
end

return WorldService
