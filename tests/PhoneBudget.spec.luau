--[[
	The phone target (integrator, 2026-10-18): at most LobbyLayout.Budget.
	PhoneParts parts stream in around a player standing in the lobby. Those
	are every part inside the lobby area plus every part of a Persistent
	model anywhere (ModelStreamingMode Persistent: always streamed,
	whatever the distance). Models in the "Lod" mode (LevelOfDetail =
	StreamingMesh) only send a proxy from afar and don't count.
	Steps 6-7: the artifact museum ArtifactService builds into every plot's
	yard at server start (MuseumBuilder, structure only: the relics are
	client-side) stands in the lobby area too, so it counts here.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local MuseumBuilder = Loader.requirePath("ServerScriptService.Server.World.MuseumBuilder")

	local function persistent(model: any): boolean
		local ok, mode = pcall(function()
			return model.ModelStreamingMode.Name
		end)
		return ok and mode == "Persistent"
	end

	T.test("phones: the lobby plus the always-streamed models stay under PhoneParts", function()
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		-- walk the map once: a part counts when it is in the lobby area, or under a Persistent model
		local lobby, outside = 0, 0
		local function walk(instance: any, always: boolean)
			for _, child in instance:GetChildren() do
				if child:IsA("BasePart") then
					if LobbyLayout.inArea(child.CFrame.Position) then
						lobby += 1
					elseif always then
						outside += 1
					end
				end
				walk(child, always or (child:IsA("Model") and persistent(child)))
			end
		end
		walk(map, false)
		-- the yard museums (ArtifactService, one per plot)
		local museums = 0
		for _, plot in WorldLayout.Plots do
			local museum = MuseumBuilder.build(WorldLayout.plotCFrame(plot))
			for _, d in museum:GetDescendants() do
				if d:IsA("BasePart") and LobbyLayout.inArea(d.CFrame.Position) then
					museums += 1
				end
			end
		end
		local total = lobby + outside + museums
		local budget = LobbyLayout.Budget.PhoneParts
		T.truthy(type(budget) == "number" and budget > 0, "LobbyLayout.Budget.PhoneParts")
		T.le(total, budget, `lobby {lobby} + always-streamed outside it {outside} + yard museums {museums} = {total} parts`)
	end)

	--[[
		Everything that streams in round a player at the spawn or on the plaza
		(integrator 2026-10-22, the SKY HAVEN review): every part within
		Workspace.StreamingTargetRadius (default.project.json) of the spot,
		Lod models included (inside the radius they stream in whole; Lod only
		helps farther away), plus every Persistent model's parts anywhere,
		plus the yard museums. The lobby budget above misses the sky islands,
		SKY HAVEN and the far shores that are outside the lobby area but well
		inside the radius.
	]]
	T.test("phones: what streams in round the spawn and the plaza stays under StreamParts", function()
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local radius = project.tree.Workspace["$properties"].StreamingTargetRadius
		T.truthy(type(radius) == "number" and radius > 0, "Workspace.StreamingTargetRadius")
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local museums = 0
		for _, plot in WorldLayout.Plots do
			for _, d in MuseumBuilder.build(WorldLayout.plotCFrame(plot)):GetDescendants() do
				if d:IsA("BasePart") then
					museums += 1
				end
			end
		end
		local budget = LobbyLayout.Budget.StreamParts
		T.truthy(type(budget) == "number" and budget > 0, "LobbyLayout.Budget.StreamParts")
		for name, spot in { Spawn = WorldLayout.SpawnPoint, Plaza = WorldLayout.Plaza.Center } do
			local near, always = 0, 0
			local function walk(instance: any, persists: boolean)
				for _, child in instance:GetChildren() do
					if child:IsA("BasePart") then
						if (child.CFrame.Position - spot).Magnitude <= radius then
							near += 1
						elseif persists then
							always += 1
						end
					end
					walk(child, persists or (child:IsA("Model") and persistent(child)))
				end
			end
			walk(map, false)
			local total = near + always + museums
			T.le(total, budget, `{name}: {near} parts within {radius} studs + {always} always-streamed beyond + {museums} museum = {total}`)
		end
	end)
end
