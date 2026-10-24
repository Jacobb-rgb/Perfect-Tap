--[[
	The shopkeeper previews (tools/lune/export_scene.luau, shots in
	tools/preview/shopkeeper_shots.json):
	  "shopkeepers"     the world with the owner's miner (ShopkeeperBuilder,
	                    the same build as ShopkeeperController's) on every
	                    ShopkeeperSpot at his scale there, his badge, effects and
	                    lights on (in the game only the nearest keeper's lights
	                    are on); prints each spot (shop, feet, facing)
	  "shopkeeper_solo" the miner alone on a plain floor (front and 3/4 shots)
]]

local Preview = {}

-- The exporter skips see-through parts (the rig) and takes PointLights on
-- parts only: the keeper's chest light (on an attachment) and his helmet
-- lamp's SpotLight show as PointLights on little hidden parts.
local function previewLights(keeper: any)
	local roblox = require("@lune/roblox") :: any
	local function lightAt(cf: any, range: number, brightness: number, color: any)
		local holder = roblox.Instance.new("Part")
		holder.Name = "PreviewLight"
		holder.Anchored = true
		holder.Transparency = 1
		holder.Size = roblox.Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = cf
		local point = roblox.Instance.new("PointLight")
		point.Range = range
		point.Brightness = brightness
		point.Color = color
		point.Parent = holder
		holder.Parent = keeper
	end
	for _, d in keeper:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "CoinBurst" then
			d:Destroy() -- (it only fires on a sale; the renderer would draw it always)
		elseif d:IsA("PointLight") and d.Parent:IsA("Attachment") then
			lightAt(d.Parent.Parent.CFrame * d.Parent.CFrame, d.Range, d.Brightness, d.Color)
		elseif d:IsA("SpotLight") then
			-- (the lens faces its part's X axis: a point light ahead and down, where its cone lands)
			lightAt(d.Parent.CFrame * roblox.CFrame.new(4, -2, 0), d.Range * 0.5, d.Brightness * 0.5, d.Color)
		end
	end
end

function Preview.build(Loader: any, map: any)
	local ShopkeeperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ShopkeeperBuilder")
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
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
		local keeper = ShopkeeperBuilder.build(feet, scale, { Badge = ShopkeeperConfig.badge(shop), Lights = true })
		previewLights(keeper)
		keeper.Parent = d.Parent.Parent
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
	local keeper = ShopkeeperBuilder.build(roblox.CFrame.new(), 1, { Badge = "SHOP", Lights = true })
	previewLights(keeper)
	keeper.Parent = workspace
end

return Preview
