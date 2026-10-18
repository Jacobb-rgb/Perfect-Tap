--[[
	Background music (MusicConfig): one looping Sound per track, created on
	first use in SoundService (local to this client) and routed through the
	SoundGroup "TerraForgeMusic" (the settings menu sets its Volume; this
	controller never does). Every CheckEvery seconds it picks the track for
	the player's position (MusicConfig.trackFor); a change must hold for
	MusicConfig.Hold seconds (MusicConfig.settle), then the old track fades
	out and pauses (it resumes where it left off, so walking back and forth
	never restarts a song) and the new one fades in. A silent track (id 0)
	just fades the music out. While the cleaning minigame is open the music
	is turned down to MusicConfig.CleaningDuck.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MusicConfig = require(Shared.Config.MusicConfig)
local CleaningController = require(script.Parent.CleaningController)

local MusicController = {}

local player = Players.LocalPlayer
local group: SoundGroup? = nil
local sounds: { [string]: Sound } = {}
local tweens: { [Sound]: Tween } = {}
local current: string? = nil
local ducked = false

-- The music SoundGroup: found or created by its exact name (MusicConfig.Group).
function MusicController.group(): SoundGroup
	if group and group.Parent then
		return group
	end
	local found = SoundService:FindFirstChild(MusicConfig.Group)
	if found and found:IsA("SoundGroup") then
		group = found
		return found
	end
	local created = Instance.new("SoundGroup")
	created.Name = MusicConfig.Group
	created.Parent = SoundService
	group = created
	return created
end

local function targetVolume(name: string): number
	local track = MusicConfig.Tracks[name]
	local volume = if track then track.Volume else 0
	return if ducked then volume * MusicConfig.CleaningDuck else volume
end

local function sound(name: string): Sound?
	local existing = sounds[name]
	if existing then
		return existing
	end
	local id = MusicConfig.soundId(MusicConfig.Tracks[name])
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "Music" .. name
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = MusicController.group()
	s.Parent = SoundService
	sounds[name] = s
	return s
end

local function fade(s: Sound, volume: number, seconds: number, after: (() -> ())?)
	local running = tweens[s]
	if running then
		running:Cancel()
	end
	local tween = TweenService:Create(s, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = volume })
	tweens[s] = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and tweens[s] == tween then
			tweens[s] = nil
			if after then
				after()
			end
		end
	end)
	tween:Play()
end

-- Crossfade to `name` (nil = silence).
function MusicController.play(name: string?)
	if name == current then
		return
	end
	local old = if current then sounds[current] else nil
	current = name
	if old then
		local leaving = old
		fade(leaving, 0, MusicConfig.FadeOut, function()
			if sounds[current or ""] ~= leaving then
				leaving:Pause()
			end
		end)
	end
	local new = if name then sound(name) else nil
	if new and name then
		if new.IsPaused then
			new:Resume()
		elseif not new.IsPlaying then
			new:Play()
		end
		fade(new, targetVolume(name), MusicConfig.FadeIn)
	end
end

-- The track playing now (nil = silence).
function MusicController.current(): string?
	return current
end

-- Is the player inside the Blaster Vault's LightingZone?
local function inVault(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged("LightingZone") do
		if zone:IsA("BasePart") then
			local preset = zone:GetAttribute("Preset")
			if type(preset) == "string" and string.find(preset, "Vault", 1, true) then
				local p = zone.CFrame:PointToObjectSpace(position)
				local half = zone.Size / 2
				if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
					return true
				end
			end
		end
	end
	return false
end

local function isCleaning(): boolean
	return CleaningController.isActive()
end

function MusicController.init()
	MusicController.group()
end

function MusicController.start()
	local state: MusicConfig.Pick = { Playing = nil, Candidate = nil, Since = 0 }
	while true do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local want = MusicConfig.trackFor(root.Position, inVault(root.Position))
			local pick = MusicConfig.settle(state, want, os.clock())
			if pick then
				MusicController.play(pick)
			end
		end
		local duck = isCleaning()
		if duck ~= ducked then
			ducked = duck
			local s = if current then sounds[current] else nil
			if s and current then
				fade(s, targetVolume(current), 0.6)
			end
		end
		task.wait(MusicConfig.CheckEvery)
	end
end

return MusicController
