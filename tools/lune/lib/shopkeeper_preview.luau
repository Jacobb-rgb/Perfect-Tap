--[[
	The shopkeepers' spots (scene "shopkeepers" for tools/lune/export_scene.luau:
	the world, shots in tools/preview/shopkeeper_shots.json). Lune can't fetch
	Roblox avatars, so a blocky stand-in (Kit.npc, dark like the owner's skin:
	black puffer jacket, black hair, white goggles) stands on every
	ShopkeeperSpot where ShopkeeperController puts the owner's avatar in the
	game. Prints each spot (shop, feet, facing) for the shot list.
]]

local Preview = {}

function Preview.build(Loader: any, map: any)
	local Kit = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Kit")
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local roblox = require("@lune/roblox") :: any
	local rgb = roblox.Color3.fromRGB
	local look = {
		Name = "ShopkeeperStandIn",
		Shirt = rgb(28, 28, 32),
		Pants = rgb(22, 22, 26),
		Boots = rgb(16, 16, 18),
		Skin = rgb(44, 44, 48),
		Hair = rgb(12, 12, 14),
		Goggles = rgb(238, 240, 244),
		Belt = rgb(40, 70, 170),
	}
	local spots = {}
	for _, d in map:GetDescendants() do
		if d:IsA("Attachment") and table.find(d:GetTags(), ShopkeeperConfig.Tag) then
			table.insert(spots, d)
		end
	end
	-- (collected first: the stand-ins go into the same models)
	for _, d in spots do
		local feet = d.Parent.CFrame * d.CFrame
		local p, f = feet.Position, feet.LookVector
		print(string.format("spot %-8s feet (%.1f, %.1f, %.1f) facing (%.2f, %.2f)", d:GetAttribute("Shop"), p.X, p.Y, p.Z, f.X, f.Z))
		-- Kit.npc is about as tall as an R15 avatar at scale 1: scaled like the keeper there
		local npc = Kit.npc(d.Parent.Parent, feet, look)
		local k = ShopkeeperConfig.scale(d:GetAttribute("Shop"))
		for _, part in npc:GetDescendants() do
			if part:IsA("BasePart") then
				local rel = feet:ToObjectSpace(part.CFrame)
				part.Size = part.Size * k
				part.CFrame = feet * roblox.CFrame.new(rel.Position * k) * (rel - rel.Position)
			end
		end
		-- ShopkeeperController's light in front of his chest (root ~3 studs up)
		local light = ShopkeeperConfig.FaceLight
		local lamp = roblox.Instance.new("Part")
		lamp.Name = "ShopkeeperFaceLight"
		lamp.Anchored = true
		lamp.Transparency = 1
		lamp.Size = roblox.Vector3.new(0.2, 0.2, 0.2)
		lamp.CFrame = feet * roblox.CFrame.new(light.Offset.X * k, (3 + light.Offset.Y) * k, light.Offset.Z * k)
		local point = roblox.Instance.new("PointLight")
		point.Range = light.Range
		point.Brightness = light.Brightness
		point.Color = light.Color
		point.Parent = lamp
		lamp.Parent = d.Parent.Parent
	end
end

return Preview
