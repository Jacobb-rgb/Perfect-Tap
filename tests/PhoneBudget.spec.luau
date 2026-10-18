--[[
	The phone target (integrator, 2026-10-18): at most LobbyLayout.Budget.
	PhoneParts parts stream in around a player standing in the lobby. Those
	are every part inside the lobby area plus every part of a Persistent
	model anywhere (ModelStreamingMode Persistent: always streamed,
	whatever the distance). Models in the "Lod" mode (LevelOfDetail =
	StreamingMesh) only send a proxy from afar and don't count.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

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
		local total = lobby + outside
		local budget = LobbyLayout.Budget.PhoneParts
		T.truthy(type(budget) == "number" and budget > 0, "LobbyLayout.Budget.PhoneParts")
		T.le(total, budget, `lobby {lobby} + always-streamed outside it {outside} = {total} parts`)
	end)
end
