--[[
	Quiet lobby ambience (AmbienceConfig): water at the waterfalls and the
	stream, plops and crickets at the ponds, the hammer and the fire crackle
	at THE GREAT FORGE, the wind high on the mountains (and a plaza murmur
	once the owner picks one). The server marks the spots
	(World/Lobby/Ambience.luau: Attachments tagged AmbienceConfig.Tag); as a
	spot streams in this controller hangs one positional Sound per layer on
	it, and the Sounds go when the spot streams out. Every CheckEvery seconds
	it plays the loops in earshot of the camera (and stops the rest) and fires
	the one-shots on their own random timers. Every Sound plays through the
	SoundGroup AmbienceConfig.Group (a settings menu sets its Volume; this
	controller never does). While the cleaning minigame is open everything
	turns down to AmbienceConfig.CleaningDuck.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AmbienceConfig = require(Shared.Config.AmbienceConfig)
local SoundConfig = require(Shared.Config.SoundConfig)
local CleaningController = require(script.Parent.CleaningController)

local AmbienceController = {}

type Voice = {
	Layer: AmbienceConfig.Layer,
	Def: SoundConfig.SoundDef,
	Sound: Sound,
	NextAt: number,
}
type Spot = { Position: Vector3, Voices: { Voice } }

local group: SoundGroup? = nil
local spots: { [Attachment]: Spot } = {}
local wind: Sound? = nil
local rng = Random.new()

-- The ambience SoundGroup: found or created by its exact name (AmbienceConfig.Group).
function AmbienceController.group(): SoundGroup
	if group and group.Parent then
		return group
	end
	local found = SoundService:FindFirstChild(AmbienceConfig.Group)
	if found and found:IsA("SoundGroup") then
		group = found
		return found
	end
	local created = Instance.new("SoundGroup")
	created.Name = AmbienceConfig.Group
	created.Parent = SoundService
	group = created
	return created
end

local function pitch(def: SoundConfig.SoundDef): number
	return def.Pitch[1] + (def.Pitch[2] - def.Pitch[1]) * rng:NextNumber()
end

local function newSound(parent: Instance, def: SoundConfig.SoundDef, layer: AmbienceConfig.Layer?): Sound
	local s = Instance.new("Sound")
	s.Name = "Ambience"
	s.SoundId = def.Id
	s.Volume = 0
	s.Looped = def.Looped == true
	s.PlaybackSpeed = pitch(def)
	if layer then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = layer.MinDistance
		s.RollOffMaxDistance = layer.MaxDistance
	end
	s.SoundGroup = AmbienceController.group()
	s.Parent = parent
	return s
end

local function addSpot(instance: Instance)
	if not instance:IsA("Attachment") or spots[instance] then
		return
	end
	local kind = instance:GetAttribute(AmbienceConfig.Attribute)
	local layers = if type(kind) == "string" then AmbienceConfig.Kinds[kind] else nil
	if not layers then
		return
	end
	local voices: { Voice } = {}
	for _, layer in layers do
		local def = AmbienceConfig.def(layer)
		if def then
			table.insert(voices, {
				Layer = layer,
				Def = def,
				Sound = newSound(instance, def, layer),
				NextAt = os.clock() + AmbienceConfig.interval(layer, rng:NextNumber()),
			})
		end
	end
	spots[instance] = { Position = instance.WorldPosition, Voices = voices }
end

local function removeSpot(instance: Instance)
	local spot = if instance:IsA("Attachment") then spots[instance] else nil
	if not spot then
		return
	end
	spots[instance :: Attachment] = nil
	for _, voice in spot.Voices do
		voice.Sound:Destroy()
	end
end

local function gain(): number
	return if CleaningController.isActive() then AmbienceConfig.CleaningDuck else 1
end

local function playBurst(voice: Voice, level: number)
	local count = AmbienceConfig.burst(voice.Layer, rng:NextNumber())
	local gap = voice.Layer.Gap or 0.1
	for i = 1, count do
		task.delay((i - 1) * gap, function()
			local s = voice.Sound
			if s.Parent then
				s.Volume = voice.Def.Volume * level
				s.PlaybackSpeed = pitch(voice.Def)
				s.TimePosition = 0
				s:Play()
			end
		end)
	end
end

local function step(listener: Vector3, level: number, now: number)
	for _, spot in spots do
		local distance = (spot.Position - listener).Magnitude
		for _, voice in spot.Voices do
			local near = AmbienceConfig.inEarshot(voice.Layer, distance)
			if voice.Layer.Loop then
				local s = voice.Sound
				if near then
					s.Volume = voice.Def.Volume * level
					if not s.IsPlaying then
						s:Play()
					end
				elseif s.IsPlaying then
					s:Stop()
				end
			elseif now >= voice.NextAt then
				if near then
					playBurst(voice, level)
				end
				voice.NextAt = now + AmbienceConfig.interval(voice.Layer, rng:NextNumber())
			end
		end
	end
	local s = wind
	if s then
		local share = AmbienceConfig.windShare(listener)
		local def = SoundConfig[AmbienceConfig.Wind.Sound]
		if share > 0.01 and def then
			s.Volume = def.Volume * share * level
			if not s.IsPlaying then
				s:Play()
			end
		elseif s.IsPlaying then
			s:Stop()
		end
	end
end

function AmbienceController.init()
	AmbienceController.group()
	local def = SoundConfig[AmbienceConfig.Wind.Sound]
	if def then
		wind = newSound(SoundService, def, nil)
	end
end

function AmbienceController.start()
	CollectionService:GetInstanceAddedSignal(AmbienceConfig.Tag):Connect(addSpot)
	CollectionService:GetInstanceRemovedSignal(AmbienceConfig.Tag):Connect(removeSpot)
	for _, instance in CollectionService:GetTagged(AmbienceConfig.Tag) do
		addSpot(instance)
	end
	while true do
		local camera = Workspace.CurrentCamera
		if camera then
			step(camera.CFrame.Position, gain(), os.clock())
		end
		task.wait(AmbienceConfig.CheckEvery)
	end
end

return AmbienceController
