--[[
	MusicConfig: every zone maps to a track, the ids are whole numbers (0 =
	silent), the right track for the plaza, a base, the quarry, a cave and the
	Blaster Vault, and the settle rule (no flip-flopping on a border).
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local MusicConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MusicConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")

	T.test("music: tracks, zones and fades are sane", function()
		T.eq(MusicConfig.Group, "TerraForgeMusic", "the settings menu's SoundGroup name")
		for name, track in MusicConfig.Tracks do
			T.truthy(type(track.Id) == "number" and track.Id >= 0 and track.Id == math.floor(track.Id), name .. " id is a whole number")
			T.truthy(track.Volume > 0 and track.Volume <= 0.6, name .. " plays quietly")
		end
		for _, zone in WorldLayout.Zones do
			local name = MusicConfig.ZoneTrack[zone.Id] or "Lobby"
			T.truthy(MusicConfig.Tracks[name], `{zone.Id} plays a known track`)
		end
		T.truthy(MusicConfig.FadeIn > 0 and MusicConfig.FadeOut > 0 and MusicConfig.Hold > 0, "fades and hold")
		T.truthy(MusicConfig.CleaningDuck > 0 and MusicConfig.CleaningDuck < 1, "the minigame turns it down, not off")
		T.eq(MusicConfig.soundId({ Id = 0, Volume = 0.3 }), nil, "0 = silent")
		T.eq(MusicConfig.soundId({ Id = 1837849285, Volume = 0.3 }), "rbxassetid://1837849285", "content id")
		T.eq(MusicConfig.soundId(nil), nil, "missing track = silent")
	end)

	T.test("music: the right track in every part of the world", function()
		T.eq(MusicConfig.trackFor(WorldLayout.SpawnPoint + Vector3.new(0, 3, 0)), "Lobby", "spawn")
		T.eq(MusicConfig.trackFor(Vector3.new(0, 3, 0)), "Lobby", "plaza")
		local plot = WorldLayout.Plots[1]
		T.eq(MusicConfig.trackFor(plot.Center + Vector3.new(0, 3, 0)), "Base", "a base")
		local q = WorldLayout.Quarry
		T.eq(MusicConfig.trackFor((q.Min + q.Max) / 2), "Mine", "the quarry")
		for _, zone in WorldLayout.Zones do
			if zone.Id == "EmberCaves" then
				T.eq(MusicConfig.trackFor((zone.Min + zone.Max) / 2), "Mine", "the Ember Caves")
			end
		end
		local vault = LobbyLayout.ById.BlasterVault
		T.eq(MusicConfig.trackFor(vault.Center + Vector3.new(0, 3, 0)), "Vault", "the Blaster Vault")
		T.eq(MusicConfig.trackFor(Vector3.new(0, 3, 0), true), "Vault", "inside the vault's lighting zone")
	end)

	T.test("music: a change has to hold before the music switches", function()
		local state = { Playing = nil, Candidate = nil, Since = 0 }
		T.eq(MusicConfig.settle(state, "Lobby", 0), "Lobby", "the first track starts at once")
		T.eq(MusicConfig.settle(state, "Lobby", 1), nil, "same track: nothing")
		T.eq(MusicConfig.settle(state, "Base", 2), nil, "a new track has to wait")
		T.eq(MusicConfig.settle(state, "Lobby", 2.5), nil, "back over the border: nothing")
		T.eq(MusicConfig.settle(state, "Base", 3), nil, "the wait starts again")
		T.eq(MusicConfig.settle(state, "Base", 3 + MusicConfig.Hold * 0.5), nil, "still waiting")
		T.eq(MusicConfig.settle(state, "Base", 3 + MusicConfig.Hold), "Base", "held long enough: switch")
		T.eq(state.Playing, "Base", "now playing Base")
	end)
end
