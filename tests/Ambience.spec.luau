--[[
	Lobby ambience (AmbienceConfig, World/Lobby/Ambience.luau): every layer
	plays a known sound (or is an owner slot at 0 = silent), nothing is heard
	past the streaming radius, the wind only blows high up in the lobby, and
	the built map carries the spots (tagged Attachments on parts that are
	already there: no new parts) at the waterfalls, the ponds, the stream,
	the forge and the plaza.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local AmbienceConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AmbienceConfig")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	T.test("ambience: every layer is quiet, known and in streaming range", function()
		T.eq(AmbienceConfig.Group, "TerraForgeAmbience", "the ambience SoundGroup's name")
		local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
		T.eq(AmbienceConfig.ParentGroup, SettingsConfig.SfxGroup, "nested in the SETTINGS sound effects group")
		T.truthy(AmbienceConfig.MaxEarshot <= 96, "heard well inside Workspace.StreamingMinRadius (112)")
		T.truthy(AmbienceConfig.CleaningDuck > 0 and AmbienceConfig.CleaningDuck < 1, "the minigame turns it down")
		local kinds = 0
		for kind, layers in AmbienceConfig.Kinds do
			kinds += 1
			for i, layer in layers do
				local label = `{kind} layer {i}`
				T.truthy(layer.MinDistance > 0 and layer.MinDistance < layer.MaxDistance, label .. " roll-off")
				T.le(layer.MaxDistance + AmbienceConfig.Margin, AmbienceConfig.MaxEarshot + AmbienceConfig.Margin, label .. " earshot")
				if layer.Sound then
					local def = SoundConfig[layer.Sound]
					T.truthy(def, label .. " sound " .. layer.Sound)
					T.eq(def.Looped == true, layer.Loop == true, label .. " loops exactly when the layer loops")
					T.truthy(def.Volume <= 0.45, label .. " plays quietly")
				else
					T.truthy(type(layer.Id) == "number" and layer.Id >= 0 and layer.Id == math.floor(layer.Id), label .. " owner id")
				end
				if not layer.Loop then
					local every = layer.Every
					T.truthy(every and every[1] > 0 and every[1] <= every[2], label .. " one-shot timer")
				end
			end
		end
		local MineAmbience = Loader.requirePath("ReplicatedStorage.Shared.Config.MineAmbience")
		local mineKinds = 0
		for _ in MineAmbience.Kinds do
			mineKinds += 1
		end
		T.eq(kinds, #AmbienceConfig.LobbyKinds + mineKinds, "the lobby's 5 kinds + the mine floors' (MineAmbience)")
		for _, kind in AmbienceConfig.LobbyKinds do
			T.truthy(AmbienceConfig.Kinds[kind], kind .. " is a lobby kind")
		end
		local wind = SoundConfig[AmbienceConfig.Wind.Sound]
		T.truthy(wind and wind.Looped, "the wind loops")
	end)

	T.test("ambience: owner slots stay silent until an id is pasted", function()
		T.eq(AmbienceConfig.def({ Id = 0, MinDistance = 5, MaxDistance = 30 }), nil, "0 = silent")
		T.eq(AmbienceConfig.def({ Id = 1.5, MinDistance = 5, MaxDistance = 30 }), nil, "not a whole number")
		local def = AmbienceConfig.def({ Id = 9000000001, Volume = 0.2, Loop = true, MinDistance = 5, MaxDistance = 30 })
		T.eq(def and def.Id, "rbxassetid://9000000001", "content id")
		T.truthy(def and def.Looped, "a looping slot loops")
		T.eq(AmbienceConfig.def({ Sound = "AmbPlop", MinDistance = 5, MaxDistance = 30 }), SoundConfig.AmbPlop, "a SoundConfig key")
	end)

	T.test("ambience: timers, bursts and the wind", function()
		local layer = { Sound = "AmbCricket", Every = { 2, 4 }, Burst = { 3, 5 }, MinDistance = 4, MaxDistance = 30 }
		T.near(AmbienceConfig.interval(layer, 0), 2, 1e-6, "shortest wait")
		T.near(AmbienceConfig.interval(layer, 1), 4, 1e-6, "longest wait")
		T.eq(AmbienceConfig.burst(layer, 0), 3, "fewest chirps")
		T.eq(AmbienceConfig.burst(layer, 1), 5, "most chirps")
		T.eq(AmbienceConfig.burst({ Sound = "AmbPlop", MinDistance = 4, MaxDistance = 30 }, 0.5), 1, "no burst = one play")
		T.truthy(AmbienceConfig.inEarshot(layer, 30), "at the edge")
		T.falsy(AmbienceConfig.inEarshot(layer, 60), "far away")
		T.eq(AmbienceConfig.windShare(Vector3.new(0, 15, 0)), 0, "no wind on the plaza")
		T.eq(AmbienceConfig.windShare(Vector3.new(150, 140, 100)), 1, "full wind high on the mountains")
		local mid = AmbienceConfig.windShare(Vector3.new(150, (AmbienceConfig.Wind.Low + AmbienceConfig.Wind.High) / 2, 100))
		T.truthy(mid > 0.4 and mid < 0.6, "it fades in on the way up")
		T.eq(AmbienceConfig.windShare(Vector3.new(0, 140, LobbyLayout.Area.Max.Z + 400)), 0, "only over the lobby")
	end)

	T.test("ambience: the map carries the spots on parts that are already there", function()
		local map = WorldBuilder.build(roblox.Instance.new("DataModel"):GetService("Workspace"))
		local count: { [string]: number } = {}
		local total = 0
		for _, d in map:GetDescendants() do
			local lobbyKind = d.ClassName == "Attachment" and table.find(AmbienceConfig.LobbyKinds, d:GetAttribute(AmbienceConfig.Attribute))
			-- (the mine floors' spots: tests/MineAmbience.spec.luau)
			if lobbyKind and table.find(d:GetTags(), AmbienceConfig.Tag) then
				total += 1
				local kind = d:GetAttribute(AmbienceConfig.Attribute)
				T.truthy(type(kind) == "string" and AmbienceConfig.Kinds[kind], `{d.Name} has a known kind`)
				count[kind] = (count[kind] or 0) + 1
				local host = d.Parent
				T.truthy(host and host:IsA("BasePart"), d.Name .. " rides on a part")
				local at = (host.CFrame * d.CFrame).Position
				local reach = host.Size.Magnitude / 2 + 8
				T.le((at - host.CFrame.Position).Magnitude, reach, d.Name .. " sits on its host part")
				T.eq(#d:GetChildren(), 0, d.Name .. " carries no parts")
				if kind ~= "Waterfall" then
					T.truthy(LobbyLayout.inArea(at), d.Name .. " is in the lobby")
				end
				if kind == "Forge" then
					local forge = LobbyLayout.ById.GreatForge
					T.le(LobbyLayout.distanceTo(forge, at), 0.01, "the forge spot is inside THE GREAT FORGE")
				end
			end
		end
		T.truthy((count.Waterfall or 0) >= 2, `waterfalls ({count.Waterfall or 0})`)
		T.le(count.Waterfall or 0, AmbienceConfig.MaxWaterfalls, "waterfall cap")
		T.truthy((count.Pond or 0) >= 3, `ponds ({count.Pond or 0})`)
		T.le(count.Pond or 0, AmbienceConfig.MaxPonds, "pond cap")
		T.eq(count.Brook, 1, "the stream")
		T.eq(count.Forge, 1, "THE GREAT FORGE")
		T.eq(count.Plaza, 1, "the plaza")
		T.le(total, 20, "few emitters")
	end)
end
