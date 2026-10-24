--[[
	The shopkeeper previews (tools/lune/export_scene.luau, shots in
	tools/preview/shopkeeper_shots.json):
	  "shopkeepers"     the world with the owner's miner (ShopkeeperBuilder,
	                    the same build as ShopkeeperController's) on every
	                    ShopkeeperSpot at his scale there, with his chest light;
	                    prints each spot (shop, feet, facing) for the shot list
	  "shopkeeper_solo" the miner alone on a plain floor (front and 3/4 shots)
]]

local Preview = {}

local function faceLight(Loader: any, roblox: any, parent: any, feet: any, scale: number)
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local light = ShopkeeperConfig.FaceLight
	local lamp = roblox.Instance.new("Part")
	lamp.Name = "ShopkeeperFaceLight"
	lamp.Anchored = true
	lamp.Transparency = 1
	lamp.Size = roblox.Vector3.new(0.2, 0.2, 0.2)
	lamp.CFrame = feet * roblox.CFrame.new(light.Offset * scale)
	local point = roblox.Instance.new("PointLight")
	point.Range = light.Range
	point.Brightness = light.Brightness
	point.Color = light.Color
	point.Parent = lamp
	lamp.Parent = parent
end

-- The rig's parts are see-through (Transparency 1): the exporter gets only what shows.
local function dropRig(model: any)
	local rig = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency >= 1 then
			table.insert(rig, d)
		end
	end
	for _, part in rig do
		for _, child in part:GetChildren() do
			if child:IsA("BasePart") then
				child.Anchored = true
				child.Parent = model
			end
		end
	end
	for _, part in rig do
		part:Destroy()
	end
end

function Preview.build(Loader: any, map: any)
	local ShopkeeperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ShopkeeperBuilder")
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local roblox = require("@lune/roblox") :: any
	local spots = {}
	for _, d in map:GetDescendants() do
		if d:IsA("Attachment") and table.find(d:GetTags(), ShopkeeperConfig.Tag) then
			table.insert(spots, d)
		end
	end
	-- (collected first: the keepers go into the same models)
	for _, d in spots do
		local feet = d.Parent.CFrame * d.CFrame
		local p, f = feet.Position, feet.LookVector
		local shop = d:GetAttribute("Shop")
		print(string.format("spot %-8s feet (%.1f, %.1f, %.1f) facing (%.2f, %.2f)", shop, p.X, p.Y, p.Z, f.X, f.Z))
		local scale = ShopkeeperConfig.scale(shop)
		local keeper = ShopkeeperBuilder.build(feet, scale)
		dropRig(keeper)
		keeper.Parent = d.Parent.Parent
		faceLight(Loader, roblox, d.Parent.Parent, feet, scale)
	end
end

function Preview.buildSolo(Loader: any, workspace: any)
	local ShopkeeperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ShopkeeperBuilder")
	local roblox = require("@lune/roblox") :: any
	local floor = roblox.Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = roblox.Vector3.new(40, 1, 40)
	floor.CFrame = roblox.CFrame.new(0, -0.5, 0)
	floor.Color = roblox.Color3.fromRGB(70, 74, 92)
	floor.Material = roblox.Enum.Material.SmoothPlastic
	floor.Parent = workspace
	local keeper = ShopkeeperBuilder.build(roblox.CFrame.new(), 1)
	dropRig(keeper)
	keeper.Parent = workspace
end

return Preview
