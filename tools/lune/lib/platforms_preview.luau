--[[
	Preview for the owner's decision (NOT in the game): buildable 2x2
	platforms on legs one level up (5 studs, the Belt Lift's rise), in the
	machines' style A. Scene "platforms" (shots in tools/preview/factory_shots.json:
	platforms_overview / platforms_side / platforms_deck).

	The line: a ground belt -> Belt Lift up -> belts and a Brick Furnace on the
	deck -> Slide down -> a belt -> Sell Box on the ground; a Solar Panel on a
	third platform, a ground belt running under the deck.
]]

local roblox = require("@lune/roblox") :: any

local Platforms = {}

Platforms.Level = 5 -- studs: the deck top (the Belt Lift rises this much)

-- Platforms (min cell x, z), each 2x2 cells.
Platforms.Decks = { { 4, 6 }, { 4, 4 }, { 6, 5 } }

-- Ground pieces { Id, X, Z, R }; deck pieces get Platforms.Level added.
Platforms.Ground = {
	{ "Conveyor", 5, 11, 0 },
	{ "Conveyor", 5, 0, 1 },
	{ "SellBox", 6, 0, 0 },
	{ "Conveyor", 2, 5, 1 },
	{ "Conveyor", 3, 5, 1 },
	{ "Conveyor", 4, 5, 1 },
	{ "Conveyor", 5, 5, 1 },
	{ "Conveyor", 6, 5, 1 },
	{ "Conveyor", 7, 5, 1 },
	{ "Conveyor", 8, 5, 1 },
	{ "PowerPole", 8, 7, 0 },
}
Platforms.Deck = {
	{ "Conveyor", 5, 7, 0 },
	{ "BrickFurnace", 4, 5, 0 },
	{ "Conveyor", 5, 4, 0 },
	{ "SolarPanel", 6, 5, 0 },
}

-- A style-A platform: 4 round slate legs on orange feet, a cream deck slab with
-- a light metal top, orange glow strips round the edge and cream rails on the
-- sides nothing else leans on. `cf` = the footprint centre on the ground.
function Platforms.platform(Loader: any, parent: any, cf: any, size: number, height: number, rails: { string }): any
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local NEON = roblox.Enum.Material.Neon
	local CREAM, SLATE, ORANGE, METAL =
		C3.fromRGB(232, 226, 214), C3.fromRGB(72, 84, 122), C3.fromRGB(255, 146, 52), C3.fromRGB(176, 182, 198)
	local model = roblox.Instance.new("Model")
	model.Name = "Platform"
	model.Parent = parent
	local half = size / 2 - 0.6
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local leg = Geo.make("Part", {
				Shape = roblox.Enum.PartType.Cylinder,
				CFrame = cf * CF.new(sx * half, (height - 0.6) / 2, sz * half) * CF.Angles(0, 0, math.pi / 2),
				Size = V3.new(height - 0.6, 0.7, 0.7),
				Color = SLATE,
			}, model)
			leg.Name = "Leg"
			local foot = Geo.make("Part", {
				Shape = roblox.Enum.PartType.Cylinder,
				CFrame = cf * CF.new(sx * half, 0.2, sz * half) * CF.Angles(0, 0, math.pi / 2),
				Size = V3.new(0.4, 1.2, 1.2),
				Color = ORANGE,
			}, model)
			foot.Name = "Foot"
		end
	end
	-- the deck: cream slab, metal top, glow strips on its four edges
	Geo.block(model, cf * CF.new(0, height - 0.45, 0), V3.new(size - 0.1, 0.7, size - 0.1), CREAM)
	local top = Geo.block(model, cf * CF.new(0, height - 0.05, 0), V3.new(size - 0.5, 0.1, size - 0.5), METAL)
	top.Name = "Deck"
	for _, side in { -1, 1 } do
		Geo.block(model, cf * CF.new(0, height - 0.55, side * (size / 2 - 0.02)), V3.new(size - 0.6, 0.14, 0.06), ORANGE, NEON)
		Geo.block(model, cf * CF.new(side * (size / 2 - 0.02), height - 0.55, 0), V3.new(0.06, 0.14, size - 0.6), ORANGE, NEON)
	end
	-- rails on the open sides ("N" / "S" / "E" / "W" in plot terms: -Z / +Z / +X / -X)
	for _, side in rails do
		local offset = if side == "N"
			then CF.new(0, 0, -size / 2 + 0.2)
			elseif side == "S" then CF.new(0, 0, size / 2 - 0.2)
			elseif side == "E" then CF.new(size / 2 - 0.2, 0, 0) * CF.Angles(0, math.pi / 2, 0)
			else CF.new(-size / 2 + 0.2, 0, 0) * CF.Angles(0, math.pi / 2, 0)
		local rail = Geo.make("Part", {
			Shape = roblox.Enum.PartType.Cylinder,
			CFrame = cf * offset * CF.new(0, height + 0.9, 0),
			Size = V3.new(size - 0.6, 0.32, 0.32),
			Color = CREAM,
		}, model)
		rail.Name = "Rail"
	end
	return model
end

function Platforms.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Old = require("./machines_gallery")
	local CELL = GameConfig.CellSize
	local HALF = GameConfig.PlotCells * CELL / 2
	local level = Platforms.Level

	local plot = { Id = 1, Center = V3.new(0, 0.3, 0), Facing = V3.new(0, 0, -1) }
	local plotCF = CF.lookAt(plot.Center, plot.Center + plot.Facing)
	local root = roblox.Instance.new("Model")
	root.Name = "PlatformsPreview"
	root.Parent = parent
	Geo.block(root, CF.new(0, -1.3, 20), V3.new(260, 2, 260), roblox.Color3.fromRGB(122, 178, 78))
	local plotModel = PlotBuilder.buildPlot(root, plot, Rng.new(1))
	Old.paintGuis(Loader, root, plotModel)

	local function cellCF(x: number, z: number, w: number, d: number): any
		return plotCF * CF.new(-HALF + (x + w / 2) * CELL, 0, -HALF + (z + d / 2) * CELL)
	end
	local before = #root:GetDescendants()
	local platformParts = 0
	for i, deck in Platforms.Decks do
		local rails = if i == 3 then { "E", "N", "S" } elseif i == 1 then { "W" } else { "W", "N" }
		local model = Platforms.platform(Loader, root, cellCF(deck[1], deck[2], 2, 2), 2 * CELL, level, rails)
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		platformParts = n
	end
	local function place(entry: any, y: number)
		local id, x, z, r = entry[1], entry[2], entry[3], entry[4]
		local model = MachineBuilder.build(id, 0)
		model:PivotTo(plotCF * CF.new(0, y, 0) * Grid.localCFrame(id, x, z, r))
		model.Parent = root
		Old.paintGuis(Loader, root, model)
		local top = model:FindFirstChild("ChimneyTop", true)
		if top then
			Old.smoke(Loader, root, top, 1.0)
		end
	end
	for _, entry in Platforms.Ground do
		place(entry, 0)
	end
	for _, entry in Platforms.Deck do
		place(entry, level)
	end
	-- the Belt Lift (cells x 5, z 8..10, high end at z 8) and the Slide (x 5, z 1..3, high end at z 3)
	local lift = KitMachines.slope(true, 3 * CELL, level)
	lift:PivotTo(cellCF(5, 8, 1, 3))
	lift.Parent = root
	Old.paintGuis(Loader, root, lift)
	local slide = KitMachines.slope(false, 3 * CELL, level)
	slide:PivotTo(cellCF(5, 1, 1, 3))
	slide.Parent = root
	Old.paintGuis(Loader, root, slide)
	-- ore on its way: on the ground belt, half way up the lift, ingots on the deck and the slide
	local items = {
		{ cellCF(5, 11, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Clean", OreId = "Gold" } },
		{ cellCF(5, 8, 1, 3) * CF.new(0, 1.05 + level * 0.55, -0.6), { Kind = "Clean", OreId = "Amethyst" } },
		{ cellCF(5, 7, 1, 1) * CF.new(0, level + 1.05, 0), { Kind = "Clean", OreId = "Sapphire" } },
		{ cellCF(5, 4, 1, 1) * CF.new(0, level + 1.05, 0), { Kind = "Ingot", OreId = "Gold", Grade = "Clean" } },
		{ cellCF(5, 1, 1, 3) * CF.new(0, 1.05 + level * 0.4, -1), { Kind = "Ingot", OreId = "Bronze", Grade = "Clean" } },
		{ cellCF(3, 5, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Clean", OreId = "Copper" } },
		{ cellCF(7, 5, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Clean", OreId = "Emberite" } },
	}
	for i, it in items do
		local model = ItemBuilder.build(it[2], it[1] * CF.Angles(0, 0.5 * i, 0), i)
		model.Parent = root
	end
	local added = #root:GetDescendants() - before
	print(string.format("Platforms preview: %d platforms, %d parts each; %d instances added", #Platforms.Decks, platformParts, added))
	return root
end

return Platforms
