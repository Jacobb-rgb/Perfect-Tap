--[[
	GearFxController: what the gear looks like on characters (client only,
	cheap on phones).

	Head lamps (Helmet Lamp gear, GearConfig.LampBudget)
	- Every player whose attribute GearConfig.LampAttribute ("LampLevel",
	  set by GearService) is above 0 wears a helmet lamp: a thin yellow
	  helmet band around the head with a dark housing and a Neon lens on
	  the forehead (three client-side parts welded to the Head: no
	  collision, no queries, massless, no shadows). The lens gets whiter
	  with the level.
	- Only the LOCAL player's lamp casts light: ONE SpotLight (Shadows off)
	  with the range and brightness from State.Bonuses (LampRange /
	  LampBrightness, the capped totals the server computed), aimed a little
	  down, and only where it is dark: the lighting zone you stand in
	  (LightingController.currentZone, the mine's caves and hollows) has a
	  LightingConfig preset Brightness under DarkBelow. In the sunny town
	  and the open quarry the light is off (Enabled), so it costs nothing.
	  Other players' lamps are Neon only (LampBudget.OthersNeon).
	- A sync every LAMP_TICK (at most 8 players) builds missing lamps
	  (respawns, characters streaming in), removes them when the level drops
	  to 0 and keeps the light in step with the snapshot and the zone; the
	  level attribute and CharacterAdded rebuild at once.

	Ore Magnet (the pull itself is server physics, ItemService.magnetStep)
	- The server tags a pulled item's model MAGNET_TAG (CollectionService,
	  ItemService.Magnet.Tag) while it slides; when its Owner attribute is
	  YOU it gets a soft glowing Beam to your character (at most MAX_BEAMS,
	  pooled; more wait for a free one). Event-driven: the tag's added /
	  removed signals, no polling of Workspace.Items. Other players' pulls
	  show nothing (no cost).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearConfig = require(Shared.Config.GearConfig)
local LightingConfig = require(Shared.Config.LightingConfig)
local StateController = require(script.Parent.StateController)

local GearFxController = {}

local LAMP_NAME = "TerraForgeLamp"
local MAGNET_TAG = "MagnetPulled" -- ItemService.Magnet.Tag (server)
local ANCHOR_NAME = "TerraForgeMagnetAnchor"
local BEAM_NAME = "TerraForgeMagnetBeam"
local MAX_BEAMS = 8
local LAMP_TICK = 0.5

local rgb = Color3.fromRGB
local HOUSING_COLOR = rgb(58, 60, 72)
local BAND_COLOR = rgb(255, 196, 18) -- the SHOP stall's yellow helmet (GearShopView)
local LIGHT_COLOR = rgb(255, 242, 214)
local BEAM_COLOR = ColorSequence.new(rgb(120, 200, 255), rgb(255, 255, 255))

GearFxController.LampName = LAMP_NAME
GearFxController.MagnetTag = MAGNET_TAG
GearFxController.LightAngle = 70 -- degrees of the SpotLight cone
GearFxController.LightTilt = 12 -- degrees the lamp looks down
-- the lamp's parts (cylinders along their X axis = forward)
GearFxController.HousingSize = Vector3.new(0.28, 0.44, 0.44)
GearFxController.LensSize = Vector3.new(0.08, 0.32, 0.32)
GearFxController.LensOffset = 0.16
GearFxController.BandHeight = 0.2
-- a lighting zone whose preset Brightness is below this is dark: the lamp lights
GearFxController.DarkBelow = 1.2

type Lamp = {
	Character: Model,
	Level: number,
	Model: Model,
	Housing: BasePart,
	Light: SpotLight?,
}

local localPlayer = Players.LocalPlayer
local lamps: { [Player]: Lamp } = {}
local beams: { [Model]: Beam } = {}
local waiting: { [Model]: boolean } = {} -- pulled toward you, no free beam yet
local pool: { Beam } = {}
local lighting: any = nil -- LightingController (required on first use)

---------------------------------------------------------------- pure helpers

-- The lens color of a lamp level: warm at level 1, cool white at the top.
function GearFxController.lensColor(level: number): Color3
	local t = math.clamp((level - 1) / math.max(1, GearConfig.MaxLevel - 1), 0, 1)
	return rgb(255, 222, 150):Lerp(rgb(236, 248, 255), t)
end

-- Where the lamp sits on a head of `size` (head space): on the forehead, facing forward.
function GearFxController.lampOffset(size: Vector3): CFrame
	return CFrame.new(0, size.Y * 0.36, -size.Z / 2 - 0.1)
		* CFrame.Angles(0, math.rad(90), 0)
		* CFrame.Angles(0, 0, math.rad(-GearFxController.LightTilt))
end

-- The helmet band around a head of `size` (head space; a thin block just
-- outside the head's box, so it shows on blocky and round heads alike) and
-- its size: at the lamp's height, the lamp sits on its front.
function GearFxController.band(size: Vector3): (CFrame, Vector3)
	local at = CFrame.new(0, size.Y * 0.36, 0)
	return at, Vector3.new(size.X + 0.1, GearFxController.BandHeight, size.Z + 0.1)
end

-- The size a head looks (an R6 head is a 2 x 1 x 1 part drawn by its mesh).
function GearFxController.headSize(head: BasePart): Vector3
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Head then
		local s = mesh.Scale
		return Vector3.new(math.min(head.Size.X, s.X), math.min(head.Size.Y, s.Y), math.min(head.Size.Z * 1.25, s.Z))
	end
	return head.Size
end

-- The local player's lamp light (range, brightness) from a State snapshot (0, 0 = none).
function GearFxController.lightOf(state: any, level: number): (number, number)
	local bonuses = if type(state) == "table" then state.Bonuses else nil
	local range = if type(bonuses) == "table" then tonumber(bonuses.LampRange) else nil
	local brightness = if type(bonuses) == "table" then tonumber(bonuses.LampBrightness) else nil
	if not range or range ~= range or range <= 0 then
		range = GearConfig.value("HelmetLamp", level)
	end
	if not brightness or brightness ~= brightness or brightness <= 0 then
		brightness = GearConfig.value("HelmetLamp", level, "LampBrightness")
	end
	return math.clamp(range :: number, 0, 60), math.clamp(brightness :: number, 0, 5)
end

-- Is a lighting preset (LightingConfig.Presets name) dark enough for the lamp to light?
function GearFxController.isDark(presetName: any): boolean
	local presets: any = LightingConfig.Presets
	local preset = if type(presetName) == "string" then presets[presetName] else nil
	local settings = if type(preset) == "table" then preset.Lighting else nil
	local brightness = if type(settings) == "table" then settings.Brightness else nil
	return type(brightness) == "number" and brightness < GearFxController.DarkBelow
end

---------------------------------------------------------------- head lamps

local function levelOf(player: Player): number
	return GearConfig.clampLevel(player:GetAttribute(GearConfig.LampAttribute))
end

-- The lighting zone the local player stands in (LightingController), "Surface" if unknown.
local function currentPreset(): string
	if lighting == nil then
		local module = script.Parent:FindFirstChild("LightingController")
		local ok, controller = false, nil
		if module and module:IsA("ModuleScript") then
			ok, controller = pcall(require, module :: any)
		end
		lighting = if ok and type(controller) == "table" then controller else false
	end
	local controller = lighting
	if type(controller) == "table" and type(controller.currentZone) == "function" then
		local ok, zone = pcall(controller.currentZone)
		if ok and type(zone) == "string" then
			return zone
		end
	end
	return "Surface"
end

local function removeLamp(player: Player)
	local lamp = lamps[player]
	lamps[player] = nil
	if lamp then
		lamp.Model:Destroy()
	end
end

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Cylinder
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	p.Parent = parent
	return p
end

local function updateLight(player: Player, lamp: Lamp)
	if player ~= localPlayer then
		return
	end
	local range, brightness = GearFxController.lightOf(StateController.get(), lamp.Level)
	local dark = GearFxController.isDark(currentPreset())
	local light = lamp.Light
	if not light then
		-- made the first time it is needed (never in the sunny town)
		if GearConfig.LampBudget.MaxLights < 1 or not dark then
			return
		end
		local made = Instance.new("SpotLight")
		made.Name = "LampLight"
		made.Face = Enum.NormalId.Right -- the housing's +X looks forward
		made.Angle = GearFxController.LightAngle
		made.Color = LIGHT_COLOR
		made.Shadows = GearConfig.LampBudget.Shadows
		made.Parent = lamp.Housing
		lamp.Light = made
		light = made
	end
	local current = light :: SpotLight
	if current.Enabled ~= dark then
		current.Enabled = dark
	end
	if current.Range ~= range then
		current.Range = range
	end
	if current.Brightness ~= brightness then
		current.Brightness = brightness
	end
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function buildLamp(player: Player, character: Model, level: number)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	removeLamp(player)
	local model = Instance.new("Model")
	model.Name = LAMP_NAME
	local size = GearFxController.headSize(head)
	local bandAt, bandSize = GearFxController.band(size)
	local band = part("Band", bandSize, BAND_COLOR, Enum.Material.SmoothPlastic, model, Enum.PartType.Block)
	band.CFrame = head.CFrame * bandAt
	local at = head.CFrame * GearFxController.lampOffset(size)
	local housing = part("Housing", GearFxController.HousingSize, HOUSING_COLOR, Enum.Material.SmoothPlastic, model)
	housing.CFrame = at
	local lens = part("Lens", GearFxController.LensSize, GearFxController.lensColor(level), Enum.Material.Neon, model)
	lens.CFrame = at * CFrame.new(GearFxController.LensOffset, 0, 0)
	weld(head, band)
	weld(head, housing)
	weld(housing, lens)
	model.Parent = character
	local lamp: Lamp = { Character = character, Level = level, Model = model, Housing = housing, Light = nil }
	lamps[player] = lamp
	updateLight(player, lamp)
end

-- Builds, rebuilds or removes one player's lamp to match their level and character.
local function syncLamp(player: Player)
	local level = levelOf(player)
	local character = player.Character
	local lamp = lamps[player]
	if level <= 0 or not character then
		removeLamp(player)
		return
	end
	if lamp and lamp.Character == character and lamp.Level == level and lamp.Model.Parent == character then
		updateLight(player, lamp)
		return
	end
	buildLamp(player, character, level)
end

local function hookPlayer(player: Player)
	player:GetAttributeChangedSignal(GearConfig.LampAttribute):Connect(function()
		syncLamp(player)
	end)
	player.CharacterAdded:Connect(function(character)
		removeLamp(player)
		task.spawn(function()
			character:WaitForChild("Head", 10)
			if player.Character == character then
				syncLamp(player)
			end
		end)
	end)
	player.CharacterRemoving:Connect(function()
		removeLamp(player)
	end)
	syncLamp(player)
end

---------------------------------------------------------------- magnet beams

local function anchor(): Attachment?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local existing = root:FindFirstChild(ANCHOR_NAME)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local made = Instance.new("Attachment")
	made.Name = ANCHOR_NAME
	made.Position = Vector3.new(0, -0.6, 0)
	made.Parent = root
	return made
end

local function newBeam(): Beam
	local beam = Instance.new("Beam")
	beam.Name = BEAM_NAME
	beam.Color = BEAM_COLOR
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.92),
	})
	beam.Width0 = 0.32
	beam.Width1 = 0.06
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 6
	return beam
end

-- Where the beams live: a folder in the camera (it outlives items and
-- respawns, so a pooled beam is never destroyed with what it pointed at).
local function beamFolder(): Instance?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local existing = camera:FindFirstChild(BEAM_NAME)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = BEAM_NAME
	folder.Parent = camera
	return folder
end

local function beamCount(): number
	local count = 0
	for _ in beams do
		count += 1
	end
	return count
end

-- Is this tagged model an item pulled toward the local player?
local function mine(model: Instance): boolean
	return model:IsA("Model") and model:GetAttribute("Owner") == localPlayer.UserId
end

local function attachBeam(model: Model): boolean
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local target = anchor()
	local folder = beamFolder()
	if not body or not target or not folder or beamCount() >= MAX_BEAMS then
		return false
	end
	local start = Instance.new("Attachment")
	start.Name = BEAM_NAME
	start.Parent = body
	local beam = table.remove(pool) or newBeam()
	beam.Attachment0 = start
	beam.Attachment1 = target
	beam.Parent = folder
	beams[model] = beam
	return true
end

-- A model waiting for a free beam gets one (beams are freed or the character came back).
local function fillWaiting()
	for model in waiting do
		if not model.Parent or not model:HasTag(MAGNET_TAG) then
			waiting[model] = nil
		elseif beamCount() >= MAX_BEAMS then
			return
		elseif attachBeam(model) then
			waiting[model] = nil
		end
	end
end

local function releaseBeam(model: Model)
	waiting[model] = nil
	local beam = beams[model]
	beams[model] = nil
	if not beam then
		return
	end
	local start = beam.Attachment0
	-- (a beam whose folder went away with an old camera is just dropped)
	local reusable = pcall(function()
		beam.Attachment0 = nil
		beam.Attachment1 = nil
		beam.Parent = nil
	end)
	if start then
		start:Destroy()
	end
	if reusable and #pool < MAX_BEAMS then
		table.insert(pool, beam)
	end
end

local function onPulled(instance: Instance)
	if not mine(instance) then
		return
	end
	local model = instance :: Model
	if beams[model] then
		return
	end
	if not attachBeam(model) then
		waiting[model] = true
	end
end

local function onReleased(instance: Instance)
	if instance:IsA("Model") then
		releaseBeam(instance)
		fillWaiting()
	end
end

-- A new character: the beams point at its root again.
local function retarget()
	local target = anchor()
	local lost: { Model } = {}
	for model, beam in beams do
		if target and model.Parent then
			beam.Attachment1 = target
		else
			table.insert(lost, model)
		end
	end
	for _, model in lost do
		releaseBeam(model)
		if model.Parent and model:HasTag(MAGNET_TAG) then
			waiting[model] = true
		end
	end
	fillWaiting()
end

---------------------------------------------------------------- lifecycle

function GearFxController.start()
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(removeLamp)
	StateController.onChanged(function()
		local lamp = lamps[localPlayer]
		if lamp then
			updateLight(localPlayer, lamp)
		end
	end)
	-- magnet beams: only the tag's signals (items streaming in arrive tagged)
	CollectionService:GetInstanceAddedSignal(MAGNET_TAG):Connect(onPulled)
	CollectionService:GetInstanceRemovedSignal(MAGNET_TAG):Connect(onReleased)
	for _, instance in CollectionService:GetTagged(MAGNET_TAG) do
		onPulled(instance)
	end
	localPlayer.CharacterAdded:Connect(function(character)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			retarget()
		end)
	end)
	while true do
		task.wait(LAMP_TICK)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(function()
				syncLamp(player)
			end)
			if not ok then
				warn("[GearFx] lamp: " .. tostring(err))
			end
		end
	end
end

return GearFxController
