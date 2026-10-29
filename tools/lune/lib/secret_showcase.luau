--[[
	The SECRET ores in one picture (scene "secret_showcase", shots in
	tools/preview/secret_shots.json): a dark vault, one tall pedestal per
	secret ore (SecretOreConfig order, each a step higher, Rainbow Nova on the
	highest), the ore in its podium look (ItemBuilder.display, Flawless) on
	top, its name plate and a plate with its floor and "1 in N" in front, a
	glowing rim in the Secret colour and a rainbow strip along the floor.
	Scene "secret_hidden" is the same vault with every ore still hidden: a
	black silhouette and "???" (how the ore index shows a secret nobody found).
]]

local roblox = require("@lune/roblox") :: any

local Showcase = {}

Showcase.Gap = 4.6 -- studs between two pedestals (the halos need room)
Showcase.Pedestal = roblox.Vector3.new(2.5, 1.2, 2.5)
Showcase.Rise = 0.45 -- each pedestal is this much taller than the one before

-- Where the i-th of `count` ores stands (the bottom middle of its display).
function Showcase.itemFrame(Loader: any, i: number, count: number): any
	local x = (i - (count + 1) / 2) * Showcase.Gap
	local h = Showcase.Pedestal.Y + (i - 1) * Showcase.Rise
	return Loader.CFrame.new(x, h + 0.06, 0) * Loader.CFrame.Angles(0, 0.3, 0)
end

-- `t`: the moment the moving parts are posed at (SecretOreFx; default 1.3 s);
-- `bare`: no ores (a video poses them every frame: tools/lune/export_secret_spin.luau)
function Showcase.build(Loader: any, parent: any, hidden: boolean?, t: number?, bare: boolean?)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local SecretOreShapes = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreShapes")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
	local SecretOreFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreFx")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local NEON = roblox.Enum.Material.Neon
	local root = roblox.Instance.new("Model")
	root.Name = "SecretShowcase"
	root.Parent = parent
	local secretColor = Rarity.get("Secret").Color
	local BOX = C3.fromRGB(30, 24, 42)
	local PLATE = C3.fromRGB(14, 10, 22)
	local TEXT = C3.fromRGB(246, 244, 255)
	local GOLD = C3.fromRGB(255, 214, 110)

	local function label(cf: any, width: number, height: number, text: string, frame: any, textColor: any)
		-- a thin frame in the rim colour, not glowing (neon frames bloom over the ores)
		Geo.block(root, cf * CF.new(0, 0, -0.03), V3.new(width + 0.08, height + 0.08, 0.05), frame:Lerp(C3.new(0, 0, 0), 0.35))
		local board = Geo.block(root, cf, V3.new(width, height, 0.08), PLATE)
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Back
		gui.Parent = board
		local textLabel = roblox.Instance.new("TextLabel")
		textLabel.Text = text
		textLabel.TextColor3 = textColor
		textLabel.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
		textLabel.Parent = gui
		return board
	end

	-- the vault: black floor, back wall, a rainbow strip along the front
	Geo.block(root, CF.new(0, -0.5, -4), V3.new(120, 1, 80), C3.fromRGB(10, 8, 16))
	Geo.block(root, CF.new(0, 14, -6.5), V3.new(120, 30, 1), C3.fromRGB(12, 9, 20))
	local count = #SecretOreConfig.List
	local width = (count - 1) * Showcase.Gap + 4
	for k, color in SecretOreShapes.Rainbow do
		local w = width / #SecretOreShapes.Rainbow
		Geo.block(root, CF.new(-width / 2 + (k - 0.5) * w, 0.03, 2.2), V3.new(w, 0.06, 0.14), color, NEON)
	end

	local silhouette = C3.fromRGB(26, 20, 36)
	local ped = Showcase.Pedestal
	for i, secret in SecretOreConfig.List do
		local ore = OreData.get(secret.Ore)
		local x = (i - (count + 1) / 2) * Showcase.Gap
		local h = ped.Y + (i - 1) * Showcase.Rise
		Geo.block(root, CF.new(x, h / 2, 0), V3.new(ped.X, h, ped.Z), BOX)
		-- glowing rim on top (Rainbow Nova: gold)
		local rim = if secret.Floor == nil then GOLD else secretColor
		Geo.block(root, CF.new(x, h + 0.03, 0), V3.new(ped.X + 0.12, 0.06, ped.Z + 0.12), BOX)
		Geo.block(root, CF.new(x, h + 0.02, ped.Z / 2 + 0.07), V3.new(ped.X + 0.12, 0.05, 0.05), rim, NEON)
		local item =
			ItemBuilder.display({ K = "Clean", O = ore.Id, G = SecretOreConfig.Grade }, Showcase.itemFrame(Loader, i, count), ore.Id)
		local pivot = CF.new(item:GetAttribute("Center"))
		SecretOreFx.pose(SecretOreFx.rig(item, pivot), pivot, t or 1.3)
		if hidden then
			-- a black cut-out of the ore: nothing glows, nothing sparkles, no aura
			for _, d in item:GetChildren() do
				if d:IsA("BasePart") and (d.Name == "Halo" or d.Name == "Floor") then
					d:Destroy()
				end
			end
			for _, d in item:GetDescendants() do
				if d:IsA("BasePart") then
					d.Color = silhouette
					d.Material = roblox.Enum.Material.SmoothPlastic
					d.Reflectance = 0
					d.Transparency = if d.Transparency > 0.5 then 1 else 0
				elseif d:IsA("ParticleEmitter") or d:IsA("PointLight") then
					d:Destroy()
				end
			end
		end
		item.Parent = if bare then nil else root
		local floorName = if secret.Floor then MineFloors.ById[secret.Floor].Name else "Every floor"
		local name = if hidden then "???" else ore.Name
		label(CF.new(x, h - 0.32, ped.Z / 2 + 0.05), ped.X - 0.15, 0.5, name, rim, TEXT)
		label(
			CF.new(x, h - 0.86, ped.Z / 2 + 0.05),
			ped.X - 0.15,
			0.42,
			floorName .. "  " .. SecretOreConfig.chanceText(secret.OneIn),
			rim,
			GOLD
		)
	end
	print(string.format("Secret showcase: %d secret ores%s", count, if hidden then " (hidden)" else ""))
	return root
end

return Showcase
