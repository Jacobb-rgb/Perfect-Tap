--[[
	Platforms in the game (docs/plans/PLATFORMS_PLAN.md, phases 1-2): scene
	"platforms_game" (shots in tools/preview/platforms_shots.json:
	platforms_game_overview / platforms_game_side / platforms_game_build).

	A small factory built from the game's own models and placed through the
	game's own rules (Placement.validate on the layout below, in order; the
	export stops if one is refused): a ground belt -> Belt Lift up -> a deck
	belt -> a Brick Furnace across two platforms -> a deck belt -> Slide down
	-> a belt -> Sell Box; a Solar Panel on a third platform, a ground belt
	running under the decks, a power pole.

	`build` = true adds a build-mode look the client draws (PlacementController
	/ GridOverlay): the grid lines, the deck cells' plates at deck height, a
	green belt ghost on a deck cell and a red Belt Lift ghost whose top end
	reaches no deck (Placement says "DeckEdge").
]]

local roblox = require("@lune/roblox") :: any

local Scene = {}

-- { Id, X, Z, R, L } in placement order (each one checked by Placement.validate)
Scene.Layout = {
	{ "Platform", 4, 6, 0, 0 },
	{ "Platform", 4, 4, 0, 0 },
	{ "Platform", 6, 5, 0, 0 },
	{ "Conveyor", 5, 11, 0, 0 },
	{ "BeltLift", 5, 8, 0, 0 }, -- cells z 8-10, its top end at the deck cell (5, 7)
	{ "Conveyor", 5, 7, 0, 1 },
	{ "BrickFurnace", 4, 5, 0, 1 }, -- across two decks, output cell (5, 4)
	{ "Conveyor", 5, 4, 0, 1 },
	{ "Slide", 5, 1, 0, 0 }, -- cells z 1-3, its top end at the deck cell (5, 4)
	{ "Conveyor", 5, 0, 1, 0 },
	{ "SellBox", 6, 0, 0, 0 },
	{ "SolarPanel", 6, 5, 0, 1 },
	{ "Conveyor", 2, 5, 1, 0 },
	{ "Conveyor", 3, 5, 1, 0 },
	{ "Conveyor", 4, 5, 1, 0 }, -- under the decks
	{ "Conveyor", 5, 5, 1, 0 },
	{ "Conveyor", 6, 5, 1, 0 },
	{ "Conveyor", 7, 5, 1, 0 },
	{ "Conveyor", 8, 5, 1, 0 },
	{ "PowerPole", 8, 7, 0, 0 },
}

function Scene.build(Loader: any, parent: any, build: boolean?)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Gallery = require("./machines_gallery")
	local CELL = GameConfig.CellSize
	local CELLS = GameConfig.PlotCells
	local HALF = CELLS * CELL / 2
	local DECK = MachineData.DeckHeight
	-- (bigger plots) the cells here are on a 12-cell grid: a bigger one moves
	-- them with it (BaseLayout.GridShift across, PlotCells - 12 back)
	local SX, SZ = (CELLS - 12) / 2, CELLS - 12

	local plot = { Id = 1, Center = V3.new(0, 0.3, 0), Facing = V3.new(0, 0, -1) }
	local plotCF = CF.lookAt(plot.Center, plot.Center + plot.Facing)
	local root = roblox.Instance.new("Model")
	root.Name = "PlatformsGame"
	root.Parent = parent
	Geo.block(root, CF.new(0, -1.3, 20), V3.new(260, 2, 260), C3.fromRGB(122, 178, 78))
	local plotModel = PlotBuilder.buildPlot(root, plot, Rng.new(1))
	Gallery.paintGuis(Loader, root, plotModel)

	local function cellCF(x: number, z: number, w: number, d: number, level: number?): any
		return plotCF * CF.new(-HALF + (x + w / 2) * CELL, Grid.levelY(level), -HALF + (z + d / 2) * CELL)
	end

	-- the layout, through the game's rules
	local entries = {}
	local partCounts: { [string]: number } = {}
	for _, row in Scene.Layout do
		local id, x, z, r, level = row[1], row[2] + SX, row[3] + SZ, row[4], row[5]
		local ok, why = Placement.validate(entries, id, x, z, r, nil, nil, level)
		assert(ok, `{id} at {x},{z} level {level}: {why}`)
		table.insert(entries, { Id = id, X = x, Z = z, R = r, L = if level == 1 then 1 else nil })
		local model = MachineBuilder.build(id, 0)
		model:PivotTo(plotCF * Grid.localCFrame(id, x, z, r, level))
		model.Parent = root
		Gallery.paintGuis(Loader, root, model)
		local top = model:FindFirstChild("ChimneyTop", true)
		if top then
			Gallery.smoke(Loader, root, top, 1.0)
		end
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		partCounts[id] = n
	end

	-- ore on its way: on the ground belt, half way up the lift, on the deck, on the slide, under the deck
	local function at(x: number, z: number, w: number, d: number, level: number?): any
		return cellCF(x + SX, z + SZ, w, d, level)
	end
	local items = {
		{ at(5, 11, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Clean", OreId = "Gold" } },
		{ at(5, 8, 1, 3) * CF.new(0, 1.05 + DECK * 0.55, -0.6), { Kind = "Clean", OreId = "Amethyst" } },
		{ at(5, 7, 1, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Clean", OreId = "Sapphire" } },
		{ at(5, 4, 1, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Ingot", OreId = "Gold", Grade = "Clean" } },
		{ at(5, 1, 1, 3) * CF.new(0, 1.05 + DECK * 0.4, -1), { Kind = "Ingot", OreId = "Bronze", Grade = "Clean" } },
		{ at(3, 5, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Clean", OreId = "Copper" } },
		{ at(7, 5, 1, 1) * CF.new(0, 1.05, 0), { Kind = "Clean", OreId = "Emberite" } },
	}
	for i, it in items do
		local model = ItemBuilder.build(it[2], it[1] * CF.Angles(0, 0.5 * i, 0), i)
		model.Parent = root
	end

	if build then
		-- the build-mode look (PlacementController / GridOverlay colours)
		local NEON = roblox.Enum.Material.Neon
		local LINE = C3.fromRGB(255, 236, 200)
		local DECK_COLOR = C3.fromRGB(120, 200, 255)
		local function plate(cf: any, w: number, d: number, color: any, transparency: number)
			local part = Geo.block(root, cf * CF.new(0, 0.11, 0), V3.new(w - 0.3, 0.06, d - 0.3), color, NEON)
			part.Transparency = transparency
			part.CastShadow = false
		end
		for i = 0, CELLS do
			local offset = -HALF + i * CELL
			local a = Geo.block(root, plotCF * CF.new(0, 0.04, offset), V3.new(CELLS * CELL, 0.05, 0.08), LINE, NEON)
			a.Transparency = 0.55
			local b = Geo.block(root, plotCF * CF.new(offset, 0.04, 0), V3.new(0.08, 0.05, CELLS * CELL), LINE, NEON)
			b.Transparency = 0.55
		end
		for k in Placement.decks(entries) do
			plate(cellCF(k % CELLS, k // CELLS, 1, 1, 1) * CF.new(0, 0.02, 0), CELL, CELL, DECK_COLOR, 0.55)
		end
		local function ghost(id: string, x: number, z: number, r: number, level: number, color: any)
			local model = MachineBuilder.build(id, 0)
			model:PivotTo(plotCF * Grid.localCFrame(id, x, z, r, level))
			local guis = {}
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					-- like the game's ghost with its Highlight: tinted, see-through
					d.Color = d.Color:Lerp(color, 0.8)
					d.Transparency = math.max(d.Transparency, 0.3)
					d.CastShadow = false
				elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
					table.insert(guis, d)
				end
			end
			for _, gui in guis do
				gui:Destroy()
			end
			model.Parent = root
			local w, dd = Grid.footprint(id, r)
			plate(cellCF(x, z, w, dd, level) * CF.new(0, 0.06, 0), w * CELL, dd * CELL, color, 0.35)
		end
		local OK, BAD = C3.fromRGB(80, 220, 120), C3.fromRGB(235, 80, 70)
		-- a belt ghost on a free deck cell (allowed), a Belt Lift ghost whose top end reaches no deck (refused)
		local okBelt = Placement.validate(entries, "Conveyor", 4 + SX, 4 + SZ, 1, nil, nil, 1)
		assert(okBelt, "the belt ghost's spot is free on the deck")
		ghost("Conveyor", 4 + SX, 4 + SZ, 1, 1, OK)
		local okLift, why = Placement.validate(entries, "BeltLift", 9 + SX, 8 + SZ, 0, nil, nil, 0)
		assert(not okLift and why == "DeckEdge", "the lift ghost is refused: " .. tostring(why))
		ghost("BeltLift", 9 + SX, 8 + SZ, 0, 0, BAD)
	end

	print(
		string.format(
			"Platforms (game): %d entries; parts: platform %d, lift %d, slide %d",
			#entries,
			partCounts.Platform or 0,
			partCounts.BeltLift or 0,
			partCounts.Slide or 0
		)
	)
	return root
end

return Scene
