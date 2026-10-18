--[[
	Pooled sounds with random pitch (client only).
	Sfx.play("BlastHit")              -- 2D (UI / own actions)
	Sfx.play("NodeShatter", position) -- 3D at a world position
]]

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("SoundConfig"))

local Sfx = {}

local POOL_2D = 8
local POOL_3D = 10

local pool2D: { Sound } = {}
local pool3D: { { part: Part, sound: Sound } } = {}
local next2D, next3D = 1, 1
local loops: { [string]: Sound } = {}
local ready = false

local function ensure()
	if ready then
		return
	end
	ready = true
	-- the group SettingsController made (its volume is the player's Sounds setting)
	local existing = SoundService:FindFirstChild("TerraForgeSfx")
	local group: SoundGroup
	if existing and existing:IsA("SoundGroup") then
		group = existing
	else
		group = Instance.new("SoundGroup")
		group.Name = "TerraForgeSfx"
		group.Volume = 1
		group.Parent = SoundService
	end
	for i = 1, POOL_2D do
		local s = Instance.new("Sound")
		s.Name = "Sfx2D_" .. i
		s.SoundGroup = group
		s.Parent = group
		table.insert(pool2D, s)
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientSfx"
	folder.Parent = Workspace
	for i = 1, POOL_3D do
		local part = Instance.new("Part")
		part.Name = "SfxEmitter" .. i
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = folder
		local s = Instance.new("Sound")
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 120
		s.SoundGroup = group
		s.Parent = part
		table.insert(pool3D, { part = part, sound = s })
	end
end

local function configure(sound: Sound, def: SoundConfig.SoundDef, pitchScale: number?)
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	local low, high = def.Pitch[1], def.Pitch[2]
	sound.PlaybackSpeed = (low + (high - low) * math.random()) * (pitchScale or 1)
	sound.Looped = def.Looped == true
end

function Sfx.play(name: string, position: Vector3?, pitchScale: number?)
	local def = SoundConfig[name]
	if not def then
		return
	end
	ensure()
	if position then
		local slot = pool3D[next3D]
		next3D = next3D % #pool3D + 1
		slot.part.CFrame = CFrame.new(position)
		configure(slot.sound, def, pitchScale)
		slot.sound.TimePosition = 0
		slot.sound:Play()
	else
		local sound = pool2D[next2D]
		next2D = next2D % #pool2D + 1
		configure(sound, def, pitchScale)
		sound.TimePosition = 0
		sound:Play()
	end
end

-- Looping sound on/off (e.g. scraping while dragging).
function Sfx.loop(name: string, on: boolean)
	local def = SoundConfig[name]
	if not def then
		return
	end
	ensure()
	local sound = loops[name]
	if on then
		if not sound then
			local s = Instance.new("Sound")
			s.Name = "Loop_" .. name
			s.Parent = SoundService
			loops[name] = s
			sound = s
		end
		local active = sound :: Sound
		if not active.IsPlaying then
			configure(active, def)
			active.Looped = true
			active:Play()
		end
	elseif sound then
		sound:Stop()
	end
end

return Sfx
