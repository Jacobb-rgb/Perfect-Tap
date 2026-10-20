--[[
	Quiet lobby ambience (watcher's night task 2026-10-18). What plays where:

	  Waterfall  a soft water rush at every waterfall (the stream's fall off
	             the south rim, the mountain falls, the quarry falls)
	  Brook      a gentle trickle at the stream's humped bridge
	  Pond       a plop now and then and crickets at every pond (frogs once
	             the owner picks a croak: Id 0 = silent)
	  Forge      hammer blows on the anvil and a fire crackle at THE GREAT
	             FORGE's furnace
	  Plaza      a low crowd murmur on the plaza (Id 0 until the owner picks
	             one: no shipped Roblox sound sounds like people talking)
	  Wind       a 2D wind that fades in as the camera climbs the mountains

	The server marks the spots (World/Lobby/Ambience.luau: Attachments tagged
	AmbienceConfig.Tag with an "Ambience" attribute = the kind); the client's
	AmbienceController hangs one positional Sound per layer on each spot.
	Layers use SoundConfig keys (ids that play in today's clients, checked by
	tests/BlasterFeel.spec.luau) or a Creator Store id the owner pastes in.

	Volume: every ambience Sound plays through the SoundGroup named
	AmbienceConfig.Group, which sits inside the sound effects group
	(AmbienceConfig.ParentGroup = SettingsConfig.SfxGroup) once that exists,
	so the SETTINGS panel's sound slider turns the ambience down too (nested
	SoundGroups multiply). The controller never sets a group's Volume.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local SoundConfig = require(Shared.Config.SoundConfig)
local MineAmbience = require(Shared.Config.MineAmbience)

export type Layer = {
	Sound: string?, -- a SoundConfig key
	Id: number?, -- or a Creator Store audio id the owner picks (0 = silent: the layer is skipped)
	Volume: number?, -- for an Id layer
	Pitch: { number }?, -- for an Id layer
	Loop: boolean?, -- loops while the camera is in earshot; otherwise one-shots
	Every: { number }?, -- seconds between one-shots (random in the range)
	Burst: { number }?, -- plays per one-shot (random count in the range: a chirp, a double blow)
	Gap: number?, -- seconds between the plays of a burst
	MinDistance: number, -- full volume inside this (Sound.RollOffMinDistance)
	MaxDistance: number, -- silent past this (Sound.RollOffMaxDistance)
}

local AmbienceConfig = {}

AmbienceConfig.Group = "TerraForgeAmbience"
AmbienceConfig.ParentGroup = "TerraForgeSfx" -- SettingsConfig.SfxGroup (tests/Ambience.spec.luau)
AmbienceConfig.Tag = "AmbienceSpot"
AmbienceConfig.Attribute = "Ambience"

-- Nothing is heard further than this: under Workspace.StreamingMinRadius (96,
-- default.project.json), so a spot's part is always streamed in while it is audible.
AmbienceConfig.MaxEarshot = 90
-- a loop starts this far before its MaxDistance (it fades in from silence anyway)
AmbienceConfig.Margin = 4
AmbienceConfig.CheckEvery = 0.1 -- seconds between the controller's steps
-- Everything is turned down to this share while the cleaning minigame is open.
AmbienceConfig.CleaningDuck = 0.25
-- the server marks at most this many waterfalls and ponds (the nearest to the plaza first)
AmbienceConfig.MaxWaterfalls = 8
AmbienceConfig.MaxPonds = 8

AmbienceConfig.Kinds = {
	Waterfall = {
		{ Sound = "AmbWaterfall", Loop = true, MinDistance = 12, MaxDistance = 80 },
	},
	Brook = {
		{ Sound = "AmbBrook", Loop = true, MinDistance = 6, MaxDistance = 40 },
	},
	Pond = {
		{ Sound = "AmbPlop", Every = { 6, 15 }, MinDistance = 5, MaxDistance = 40 },
		{ Sound = "AmbCricket", Every = { 1.5, 4.5 }, Burst = { 3, 5 }, Gap = 0.07, MinDistance = 4, MaxDistance = 32 },
		-- TODO(owner): a frog croak from the Creator Store (Audio, "frog"), Volume ~0.15
		{ Id = 0, Volume = 0.15, Pitch = { 0.9, 1.1 }, Every = { 7, 16 }, MinDistance = 5, MaxDistance = 36 },
	},
	Forge = {
		{ Sound = "AmbHammer", Every = { 1.8, 3.4 }, Burst = { 1, 3 }, Gap = 0.45, MinDistance = 10, MaxDistance = 75 },
		{ Sound = "AmbCrackle", Every = { 0.15, 0.7 }, MinDistance = 6, MaxDistance = 35 },
	},
	Plaza = {
		-- TODO(owner): a quiet crowd murmur loop from the Creator Store (Audio, "crowd murmur"), Volume ~0.2
		{ Id = 0, Volume = 0.2, Pitch = { 1, 1 }, Loop = true, MinDistance = 25, MaxDistance = 85 },
	},
} :: { [string]: { Layer } }

-- The lobby's own kinds (tests/Ambience.spec scopes its lobby checks to these).
AmbienceConfig.LobbyKinds = { "Waterfall", "Brook", "Pond", "Forge", "Plaza" }

-- The mine floors' kinds (MineAmbience: the floors place their own spots), so def(),
-- the controller and the spec's layer checks see them too.
for kind, layers in MineAmbience.Kinds do
	AmbienceConfig.Kinds[kind] = layers :: any
end

-- The 2D wind: silent below Low, full at High (camera height, inside the lobby only).
AmbienceConfig.Wind = { Sound = "AmbWind", Low = 45, High = 120 }

-- The sound a layer plays, or nil when it is silent (an owner slot still at 0).
function AmbienceConfig.def(layer: Layer): SoundConfig.SoundDef?
	if layer.Sound then
		return SoundConfig[layer.Sound]
	end
	local id = layer.Id
	if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
		return nil
	end
	return {
		Id = "rbxassetid://" .. string.format("%d", id),
		Volume = layer.Volume or 0.2,
		Pitch = layer.Pitch or { 1, 1 },
		Looped = layer.Loop == true,
	}
end

local function lerp(range: { number }?, u: number, default: number): number
	if not range then
		return default
	end
	return range[1] + (range[2] - range[1]) * math.clamp(u, 0, 1)
end

-- Seconds until a one-shot plays again (u = a random number 0..1).
function AmbienceConfig.interval(layer: Layer, u: number): number
	return lerp(layer.Every, u, 5)
end

-- How many plays a one-shot makes (u = a random number 0..1).
function AmbienceConfig.burst(layer: Layer, u: number): number
	if not layer.Burst then
		return 1
	end
	return math.clamp(math.floor(lerp(layer.Burst, u, 1) + 0.5), 1, 8)
end

-- Is a listener `distance` studs away close enough to bother playing the layer?
function AmbienceConfig.inEarshot(layer: Layer, distance: number): boolean
	return distance <= layer.MaxDistance + AmbienceConfig.Margin
end

-- The wind's share (0..1) for a camera at `position`.
function AmbienceConfig.windShare(position: Vector3): number
	if not LobbyLayout.inArea(position) then
		return 0
	end
	local w = AmbienceConfig.Wind
	return math.clamp((position.Y - w.Low) / (w.High - w.Low), 0, 1)
end

return AmbienceConfig
