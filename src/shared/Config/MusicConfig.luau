--[[
	Background music (V2_PLAN step 8): one quiet looping track per part of
	the world, crossfaded by the client's MusicController.

	  Lobby  the town, the plaza, the outcrops (Emberfall)
	  Base   standing on your (or anyone's) base
	  Mine   the quarry and the caves
	  Vault  inside the Blaster Vault (its LightingZone) and on its podium

	Track ids are Creator Store audio asset ids (numbers): 0 = silent, the
	controller then just fades the music out. How to pick free music and paste
	the ids: docs/handoff/HUDBA_NAVOD.md (Czech, for the owner).

	Volume: every music Sound plays through the SoundGroup named
	MusicConfig.Group in SoundService. The settings menu (SettingsController)
	sets that group's Volume; MusicController finds the group or creates it by
	that exact name and never sets its Volume itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local WorldLayout = require(Shared.Config.WorldLayout)

export type Track = {
	Id: number, -- Creator Store audio asset id, 0 = silent
	Volume: number, -- the Sound's own volume (quiet: music sits under the game sounds)
}

local MusicConfig = {}

MusicConfig.Group = "TerraForgeMusic"

-- TODO(owner): paste the Creator Store audio ids here (docs/handoff/HUDBA_NAVOD.md)
MusicConfig.Tracks = {
	Lobby = { Id = 0, Volume = 0.35 },
	Base = { Id = 0, Volume = 0.3 },
	Mine = { Id = 0, Volume = 0.3 },
	Vault = { Id = 0, Volume = 0.35 },
} :: { [string]: Track }

-- World zone id (WorldLayout.Zones) -> track. A zone not listed plays Lobby.
MusicConfig.ZoneTrack = {
	Emberfall = "Lobby",
	Outcrops = "Lobby",
	Quarry = "Mine",
	EmberCaves = "Mine",
	DeepHollow = "Mine",
	Grotto = "Mine",
} :: { [string]: string }

MusicConfig.FadeIn = 2.5 -- seconds
MusicConfig.FadeOut = 2
MusicConfig.CheckEvery = 0.5 -- seconds between position checks
-- A new track must win this long before the music changes: walking along a
-- border never flips the music back and forth.
MusicConfig.Hold = 1.5
-- The music is turned down to this share while the cleaning minigame is open.
MusicConfig.CleaningDuck = 0.4
-- How far past the Blaster Vault's footprint its music still plays (studs).
MusicConfig.VaultMargin = 2

-- The content id of a track, or nil when it is silent.
function MusicConfig.soundId(track: Track?): string?
	if not track or type(track.Id) ~= "number" or track.Id <= 0 or track.Id ~= math.floor(track.Id) then
		return nil
	end
	return "rbxassetid://" .. string.format("%d", track.Id)
end

-- The track that belongs at `position`. `vaultInside` = the player stands in
-- the vault's LightingZone (the client checks that part, see MusicController).
function MusicConfig.trackFor(position: Vector3, vaultInside: boolean?): string
	if vaultInside then
		return "Vault"
	end
	local vault = LobbyLayout.ById.BlasterVault
	if vault and LobbyLayout.distanceTo(vault, position) <= MusicConfig.VaultMargin and position.Y < 30 then
		return "Vault"
	end
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, position, 0) and math.abs(position.Y - plot.Center.Y) < 40 then
			return "Base"
		end
	end
	local zone = WorldLayout.zoneAt(position)
	return (zone and MusicConfig.ZoneTrack[zone.Id]) or "Lobby"
end

export type Pick = { Playing: string?, Candidate: string?, Since: number }

--[[
	The settle rule (pure, tested): `state` is what plays now and which
	candidate has been seen since when; `want` the track for this check at
	time `now`. Returns the track to play (or nil to keep the current one).
	The first track starts at once; later changes wait MusicConfig.Hold.
]]
function MusicConfig.settle(state: Pick, want: string, now: number): string?
	if state.Playing == nil then
		state.Playing = want
		state.Candidate = nil
		return want
	end
	if want == state.Playing then
		state.Candidate = nil
		return nil
	end
	if want ~= state.Candidate then
		state.Candidate = want
		state.Since = now
		return nil
	end
	if now - state.Since >= MusicConfig.Hold then
		state.Playing = want
		state.Candidate = nil
		return want
	end
	return nil
end

return MusicConfig
