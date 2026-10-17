--[[
	GearFxController: what the gear looks like on characters (client only,
	cheap on phones).

	Head lamps (Helmet Lamp gear, GearConfig.LampBudget)
	- Every player whose attribute GearConfig.LampAttribute ("LampLevel",
	  set by GearService) is above 0 wears a small lamp on the forehead: a
	  dark housing and a Neon lens (two client-side parts welded to the
	  Head: no collision, no queries, massless, no shadows). The lens gets
	  whiter with the level.
	- Only the LOCAL player's lamp casts light: ONE SpotLight (Shadows off)
	  with the range and brightness from State.Bonuses (LampRange /
	  LampBrightness, the capped totals the server computed), aimed a little
	  down. Other players' lamps are Neon only (LampBudget.OthersNeon).
	- A 1 s sync (at most 8 players) builds missing lamps (respawns,
	  characters streaming in), removes them when the level drops to 0 and
	  keeps the light in step with the snapshot; the level attribute and
	  CharacterAdded rebuild at once.

	Ore Magnet (the pull itself is server physics, ItemService.magnetStep)
	- An item the server pulls toward YOU carries the model attribute
	  MAGNET_ATTRIBUTE (= your UserId): it gets a soft glowing Beam to your
	  character (at most MAX_BEAMS, pooled), checked 5 times a second and
	  only while you have a magnet (State.Bonuses.MagnetRadius) or beams are
	  still out. Other players' pulls show nothing (no cost).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearConfig = require(Shared.Config.GearConfig)
local StateController = require(script.Parent.StateController)

local GearFxController = {}

local LAMP_NAME = "TerraForgeLamp"
local MAGNET_ATTRIBUTE = "MagnetTo" -- ItemService.Magnet.Attribute (server)
local ANCHOR_NAME = "TerraForgeMagnetAnchor"
local BEAM_NAME = "TerraForgeMagnetBeam"
local MAX_BEAMS = 8
local BEAM_TICK = 0.2
local LAMP_TICK = 1

local rgb = Color3.fromRGB
local HOUSING_COLOR = rgb(58, 60, 72)
local LIGHT_COLOR = rgb(255, 242, 214)
local BEAM_COLOR = ColorSequence.new(rgb(120, 200, 255), rgb(255, 255, 255))

GearFxController.LampName = LAMP_NAME
GearFxController.LightAngle = 70 -- degrees of the SpotLight cone
GearFxController.LightTilt = 12 -- degrees the lamp looks down
-- the lamp's two parts (cylinders along their X axis = forward)
GearFxController.HousingSize = Vector3.new(0.28, 0.44, 0.44)
GearFxController.LensSize = Vector3.new(0.08, 0.32, 0.32)
GearFxController.LensOffset = 0.16

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
local pool: { Beam } = {}

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

---------------------------------------------------------------- head lamps

local function levelOf(player: Player): number
	return GearConfig.clampLevel(player:GetAttribute(GearConfig.LampAttribute))
end

local function removeLamp(player: Player)
	local lamp = lamps[player]
	lamps[player] = nil
	if lamp then
		lamp.Model:Destroy()
	end
end

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
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
	local light = lamp.Light
	if not light then
		if GearConfig.LampBudget.MaxLights < 1 then
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
	if current.Range ~= range then
		current.Range = range
	end
	if current.Brightness ~= brightness then
		current.Brightness = brightness
	end
end

local function buildLamp(player: Player, character: Model, level: number)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	removeLamp(player)
	local model = Instance.new("Model")
	model.Name = LAMP_NAME
	local at = head.CFrame * GearFxController.lampOffset(head.Size)
	local housing = part("Housing", GearFxController.HousingSize, HOUSING_COLOR, Enum.Material.SmoothPlastic, model)
	housing.CFrame = at
	local lens = part("Lens", GearFxController.LensSize, GearFxController.lensColor(level), Enum.Material.Neon, model)
	lens.CFrame = at * CFrame.new(GearFxController.LensOffset, 0, 0)
	local toHead = Instance.new("WeldConstraint")
	toHead.Part0 = head
	toHead.Part1 = housing
	toHead.Parent = housing
	local toHousing = Instance.new("WeldConstraint")
	toHousing.Part0 = housing
	toHousing.Part1 = lens
	toHousing.Parent = lens
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

local function releaseBeam(model: Model)
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

local function attachBeam(model: Model, body: BasePart, target: Attachment)
	local count = 0
	for _ in beams do
		count += 1
	end
	local folder = beamFolder()
	if count >= MAX_BEAMS or not folder then
		return
	end
	local start = Instance.new("Attachment")
	start.Name = BEAM_NAME
	start.Parent = body
	local beam = table.remove(pool) or newBeam()
	beam.Attachment0 = start
	beam.Attachment1 = target
	beam.Parent = folder
	beams[model] = beam
end

local function hasMagnet(): boolean
	local state = StateController.get()
	local bonuses = if state then state.Bonuses else nil
	local radius = if type(bonuses) == "table" then tonumber(bonuses.MagnetRadius) else nil
	return radius ~= nil and radius > 0
end

local function syncBeams()
	local items = Workspace:FindFirstChild("Items")
	if not items or (not hasMagnet() and next(beams) == nil) then
		return
	end
	local me = localPlayer.UserId
	local target = anchor()
	local seen: { [Model]: boolean } = {}
	if target then
		for _, child in items:GetChildren() do
			if child:IsA("Model") and child:GetAttribute(MAGNET_ATTRIBUTE) == me then
				local body = child.PrimaryPart
				if body then
					seen[child] = true
					local beam = beams[child]
					if beam and beam.Attachment1 ~= target then
						releaseBeam(child)
					end
					if not beams[child] then
						attachBeam(child, body, target)
					end
				end
			end
		end
	end
	for model in beams do
		if not seen[model] or not model.Parent then
			releaseBeam(model)
		end
	end
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
	task.spawn(function()
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
	end)
	while true do
		task.wait(BEAM_TICK)
		local ok, err = pcall(function()
			syncBeams()
		end)
		if not ok then
			warn("[GearFx] magnet: " .. tostring(err))
		end
	end
end

return GearFxController
