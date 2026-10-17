--[[
	Railway preview (scene "railway" for tools/lune/export_scene.luau, shots in
	tools/preview/railway_shots.json): the whole world with the railway
	(src/server/World/Railway.luau) and, for the pictures only, parked ore
	trains (TrainBuilder locomotive + 2 loaded wagons, chained and steamed by
	train_gallery.consist; the game animates them on the client):
	  - at the Mine Station, its first wagon under the loading chute's spout
	    (TrainConfig.QuarryStop), heading for the west portal
	  - at plot 5's train stop on the east coast in plot 5's banner color
	    (the "Banner" part PlotBuilder builds), its wagons beside the stop
	The ore nodes are added by export_scene (as in the world scene).
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

-- Model-space CFrame of an attachment on a model still at the origin.
local function attachmentCFrame(model: any, name: string): any
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name == name then
			return d.Parent.CFrame * d.CFrame
		end
	end
	error("no " .. name .. " on " .. model.Name)
end

function Gallery.build(Loader: any, workspace: any)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Trains = require("./train_gallery")

	local map = WorldBuilder.build(workspace)
	local props = roblox.Instance.new("Folder")
	props.Name = "RailwayPreview"
	props.Parent = workspace

	local function colors(ids: { string }): { any }
		local list = {}
		for _, id in ids do
			table.insert(list, OreData.ById[id].Color)
		end
		return list
	end

	-- the distance from the locomotive's Root back to its first wagon's center
	local loco = TrainBuilder.locomotive(roblox.Color3.new(1, 1, 1))
	local wagon = TrainBuilder.wagon(roblox.Color3.new(1, 1, 1))
	local toWagon = attachmentCFrame(loco, "CouplerBack").Position.Z - attachmentCFrame(wagon, "CouplerFront").Position.Z
	loco:Destroy()
	wagon:Destroy()

	-- at the station: heading west, the first wagon under the spout
	local stop = TrainConfig.QuarryStop
	local west = V3.new(-1, 0, 0)
	local front = stop + west * toWagon + V3.new(0, TrainBuilder.RailTop, 0)
	Trains.consist(
		Loader,
		props,
		CF.lookAt(front, front + west),
		roblox.Color3.fromRGB(220, 70, 50),
		{ colors({ "Copper", "Iron", "Coal" }), colors({ "Silver", "Tin" }) }
	)

	-- at plot 5's stop on the east coast, heading north, in the plot's banner color
	local plot = WorldLayout.Plots[5]
	local banner = map.Plots:FindFirstChild("Plot_" .. plot.Id)
	local bannerPart = banner and banner:FindFirstChild("Banner", true)
	local color = if bannerPart then bannerPart.Color else roblox.Color3.fromRGB(160, 90, 220)
	local at = TrainConfig.stopFor(plot)
	local north = V3.new(0, 0, -1)
	local coastFront = at + north * 9 + V3.new(0, TrainBuilder.RailTop, 0)
	Trains.consist(
		Loader,
		props,
		CF.lookAt(coastFront, coastFront + north),
		color,
		{ colors({ "Gold", "Amethyst", "Iron" }), colors({ "Copper", "Quartz" }) }
	)
	return map
end

return Gallery
