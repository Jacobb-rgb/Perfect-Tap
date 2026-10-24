--[[
	Backpack preview pictures (art/backpacks, the owner's reference picture
	of a blue rune backpack, 2026-10-24):
	  scene "backpacks"       the ten packs (BackpackBuilder) worst to best on
	                          rising pedestals in a shop, a rarity glow ring on
	                          each, a plate in front (number, name, ore, price)
	  scene "backpacks_worn"  stand-in miners on a meadow path seen from
	                          behind (the player's own camera), each wearing a
	                          pack, like the owner's reference shots
	Shots: tools/preview/backpack_shots.json.
]]

local Preview = {}

Preview.Spacing = 3.4
Preview.WornSpacing = 4.2

local function setup(Loader: any)
	local roblox = Loader.roblox
	return {
		roblox = roblox,
		CFrame = Loader.CFrame,
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo"),
		Builder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackBuilder"),
		Data = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData"),
		Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity"),
		Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format"),
		Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng"),
	}
end

local function blockMaker(k: any, parent: any)
	return function(name: string, cf: any, size: any, color: any, material: any?, shape: string?): any
		local p = k.Geo.make("Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = color,
			Material = material or k.Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
		}, parent)
		if shape == "Cylinder" then
			p.Shape = k.Enum.PartType.Cylinder
		end
		return p
	end
end

-- A plate whose +Z face shows `lines` (one TextLabel per line, own colours).
local function plate(k: any, block: any, cf: any, size: any, lines: { { any } })
	local p = block("Plate", cf, size, k.Color3.fromRGB(38, 30, 26))
	local gui = k.roblox.Instance.new("SurfaceGui")
	gui.Face = k.Enum.NormalId.Back
	gui.SizingMode = k.Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = p
	local n = #lines
	for i, line in lines do
		local t = k.roblox.Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = k.roblox.UDim2.fromScale(0.94, 0.86 / n)
		t.Position = k.roblox.UDim2.fromScale(0.03, 0.07 + (i - 1) * 0.86 / n)
		t.Text = line[1]
		t.TextScaled = true
		t.TextColor3 = line[2]
		t.TextStrokeColor3 = k.Color3.fromRGB(10, 8, 6)
		t.TextStrokeTransparency = 0.25
		t.FontFace = k.roblox.Font.fromEnum(k.Enum.Font.LuckiestGuy)
		t.Parent = gui
	end
end

-- Puts a built pack so its bag stands centered on (x, floorY, z), facing +Z.
local function placePack(k: any, parent: any, packId: string, x: number, floorY: number, z: number): any
	local model = k.Builder.build(packId)
	local pack = k.Data.ById[packId]
	local bottom = model:GetAttribute("BottomY")
	model:PivotTo(k.CFrame.new(x, floorY - bottom, z - k.Builder.Gap - pack.Size.Z / 2))
	model.Parent = parent
	return model
end

local function priceText(k: any, price: number): string
	if price <= 0 then
		return "FREE"
	end
	return k.Format.short(price) .. " COINS"
end

--[[
	Scene "backpacks": the ten packs left (worst) to right (best) on rising
	stone pedestals in a warm shop with a plank floor and a back wall.
]]
function Preview.build(Loader: any, workspace: any)
	local k = setup(Loader)
	local rgb = k.Color3.fromRGB
	local stage = k.roblox.Instance.new("Model")
	stage.Name = "BackpackShowroom"
	stage.Parent = workspace
	local block = blockMaker(k, stage)
	local CF, V3 = k.CFrame, k.Vector3
	local NEON = k.Enum.Material.Neon

	-- the shop: planks, a wall with a wainscot, a sign strip
	block("Floor", CF.new(0, -0.5, 4), V3.new(60, 1, 34), rgb(104, 74, 54), k.Enum.Material.WoodPlanks)
	block("Wall", CF.new(0, 10, -6), V3.new(60, 22, 1), rgb(92, 128, 140))
	block("Wainscot", CF.new(0, 1.6, -5.4), V3.new(60, 3.2, 0.4), rgb(120, 80, 50), k.Enum.Material.Wood)
	block("Rail", CF.new(0, 3.25, -5.3), V3.new(60, 0.2, 0.6), rgb(96, 62, 38), k.Enum.Material.Wood)
	plate(k, block, CF.new(0, 9.2, -5.4), V3.new(14, 2.2, 0.2), { { "BACKPACKS", rgb(255, 214, 90) } })

	for i, pack in k.Data.List do
		local x = (i - 5.5) * Preview.Spacing
		local height = 0.6 + (i - 1) * 0.2
		local rarity = k.Rarity.ById[pack.Rarity]
		-- the pedestal: stone, a glowing rarity ring under a stone top
		block(
			"Pedestal",
			CF.new(x, height / 2, 0) * CF.Angles(0, 0, math.pi / 2),
			V3.new(height, 2.5, 2.5),
			rgb(120, 116, 128),
			nil,
			"Cylinder"
		)
		block(
			"PedestalRing",
			CF.new(x, height - 0.12, 0) * CF.Angles(0, 0, math.pi / 2),
			V3.new(0.1, 2.7, 2.7),
			rarity.Color,
			NEON,
			"Cylinder"
		)
		block(
			"PedestalTop",
			CF.new(x, height - 0.02, 0) * CF.Angles(0, 0, math.pi / 2),
			V3.new(0.12, 2.5, 2.5),
			rgb(150, 146, 158),
			nil,
			"Cylinder"
		)
		placePack(k, stage, pack.Id, x, height + 0.04, 0)
		-- the plate in front, tilted back
		plate(k, block, CF.new(x, 0.86, 2.1) * CF.Angles(-0.35, 0, 0), V3.new(3.1, 0.5, 0.14), {
			{ `{i}. {string.upper(pack.Name)}`, rarity.Color },
		})
		plate(k, block, CF.new(x, 0.38, 2.27) * CF.Angles(-0.35, 0, 0), V3.new(3.1, 0.46, 0.14), {
			{ `{k.Format.commas(pack.Capacity)} ORE · {priceText(k, pack.Price)}`, rgb(255, 236, 170) },
		})
	end
end

--[[
	Scene "backpacks_worn": miners seen from behind on a meadow path, each
	wearing a pack (Root on the back of the dummy's torso), like the owner's
	reference shots. Row 1 (z = 0): packs 1-5; row 2 (z = -14): packs 6-10.
]]
function Preview.buildWorn(Loader: any, workspace: any)
	local k = setup(Loader)
	local rgb = k.Color3.fromRGB
	local CF, V3 = k.CFrame, k.Vector3
	local Dummy = require("./dummy")
	local stage = k.roblox.Instance.new("Model")
	stage.Name = "BackpackMeadow"
	stage.Parent = workspace
	local block = blockMaker(k, stage)
	local rng = k.Rng.new(2410)

	block("Grass", CF.new(0, -0.5, -8), V3.new(80, 1, 60), rgb(98, 168, 72), k.Enum.Material.Grass)
	-- two stone paths of flat slate stones
	for _, rowZ in { 0, -14 } do
		for _ = 1, 70 do
			local x = rng:range(-13, 13)
			local z = rowZ + rng:range(-2.6, 2.6)
			local s = rng:range(0.7, 1.4)
			block("Stone", CF.new(x, 0.02, z) * CF.Angles(0, rng:range(0, math.pi), 0), V3.new(s, 0.12, s * 0.7), rgb(112, 118, 150))
		end
	end
	-- leafy bushes with purple fruit along the far edge
	for i = 1, 16 do
		local x = (i - 8.5) * 3.4 + rng:range(-0.6, 0.6)
		local z = -22 + rng:range(-1, 1)
		local leaf = block(
			"Bush",
			CF.new(x, 1.1, z) * CF.Angles(0, rng:range(0, 1.5), 0),
			V3.new(2.6, 2.2, 2.6),
			rgb(86, 170, 60),
			k.Enum.Material.Grass
		)
		leaf.Shape = k.Enum.PartType.Ball
		for _ = 1, 3 do
			local berry = block(
				"Fruit",
				CF.new(x + rng:range(-1, 1), rng:range(1.2, 2.2), z + rng:range(0.6, 1.2)),
				V3.new(0.5, 0.7, 0.5),
				rgb(98, 50, 200)
			)
			berry.Shape = k.Enum.PartType.Ball
		end
	end

	local shirts = {
		{ shirt = rgb(120, 120, 140), pants = rgb(70, 60, 50) },
		{ shirt = rgb(186, 98, 48), pants = rgb(60, 54, 70) },
		{ shirt = rgb(70, 120, 186), pants = rgb(52, 52, 64) },
		{ shirt = rgb(220, 220, 228), pants = rgb(60, 70, 110) },
		{ shirt = rgb(120, 62, 48), pants = rgb(46, 44, 56) },
	}
	for i, pack in k.Data.List do
		local row = if i <= 5 then 0 else 1
		local col = if i <= 5 then i else i - 5
		local x = (col - 3) * Preview.WornSpacing
		local z = -row * 14
		-- facing away from the camera (-Z): the back and the pack face +Z
		local root = CF.new(x, 0, z)
		local look = shirts[(i - 1) % #shirts + 1]
		Dummy.build(stage, CF, root, "idle", { shirt = look.shirt, pants = look.pants })
		local model = k.Builder.build(pack.Id)
		model:PivotTo(root * CF.new(0, 3.2, 0.5))
		model.Parent = stage
	end
end

return Preview
