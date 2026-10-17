--[[
	A working factory on a plot (scene "factory", shots in
	tools/preview/factory_shots.json): the real plot pad (PlotBuilder) at the
	origin facing -Z, the roster machines placed on the grid the way a player
	would (express belts from the yard -> Splitter -> Brick / Plasma Furnace
	-> Sell Box, a Robot Arm feeding an Alloy Furnace), ores and ingots on
	the belts, and power: a Solar Panel, a Wind Turbine and a Fusion Reactor on a network of
	Power Poles with cables to every machine they power (PowerLogic: the
	same networks and cables the game computes).
]]

local roblox = require("@lune/roblox") :: any

local Factory = {}

local V3 = roblox.Vector3

-- Cells: z 0 is the road side (-Z), z 11 the yard side; R 0 faces the road.
Factory.Machines = {
	{ Id = "ExpressConveyor", X = 5, Z = 11, R = 0 },
	{ Id = "ExpressConveyor", X = 5, Z = 10, R = 0 },
	{ Id = "ExpressConveyor", X = 5, Z = 9, R = 0 },
	{ Id = "Splitter", X = 5, Z = 8, R = 0 },
	{ Id = "Conveyor", X = 4, Z = 8, R = 3 },
	{ Id = "Conveyor", X = 3, Z = 8, R = 0 },
	{ Id = "Conveyor", X = 3, Z = 7, R = 0 },
	{ Id = "Conveyor", X = 6, Z = 8, R = 1 },
	{ Id = "Conveyor", X = 7, Z = 8, R = 0 },
	{ Id = "Conveyor", X = 7, Z = 7, R = 0 },
	{ Id = "BrickFurnace", X = 2, Z = 5, R = 0 },
	{ Id = "PlasmaFurnace", X = 7, Z = 5, R = 0 },
	{ Id = "Conveyor", X = 3, Z = 4, R = 1 },
	{ Id = "Conveyor", X = 4, Z = 4, R = 1 },
	{ Id = "Conveyor", X = 8, Z = 4, R = 3 },
	{ Id = "Conveyor", X = 7, Z = 4, R = 3 },
	{ Id = "SellBox", X = 5, Z = 3, R = 0 },
	{ Id = "RobotArm", X = 2, Z = 4, R = 0 },
	{ Id = "AlloyFurnace", X = 0, Z = 2, R = 0 },
	{ Id = "Conveyor", X = 1, Z = 1, R = 1 },
	{ Id = "Conveyor", X = 2, Z = 1, R = 1 },
	{ Id = "Conveyor", X = 3, Z = 1, R = 1 },
	{ Id = "Conveyor", X = 4, Z = 1, R = 1 },
	{ Id = "Conveyor", X = 5, Z = 1, R = 2 },
	{ Id = "Conveyor", X = 5, Z = 2, R = 2 },
	{ Id = "SolarPanel", X = 0, Z = 10, R = 0 },
	{ Id = "WindTurbine", X = 10, Z = 10, R = 0 },
	{ Id = "FusionReactor", X = 9, Z = 1, R = 0 },
	{ Id = "PowerPole", X = 2, Z = 9, R = 0 },
	{ Id = "PowerPole", X = 6, Z = 10, R = 0 },
	{ Id = "PowerPole", X = 9, Z = 9, R = 0 },
	{ Id = "PowerPole", X = 1, Z = 6, R = 0 },
	{ Id = "PowerPole", X = 9, Z = 5, R = 0 },
}

-- Items lying on belts: cell, item, offset along the belt (-0.5..0.5 of a cell).
Factory.Items = {
	{ X = 5, Z = 11, D = { K = "Clean", O = "Amethyst", G = "Pristine" }, T = 0.1 },
	{ X = 5, Z = 10, D = { K = "Clean", O = "Copper", G = "Clean" }, T = -0.2 },
	{ X = 5, Z = 9, D = { K = "Clean", O = "Gold", G = "Clean" }, T = 0.2 },
	{ X = 3, Z = 8, D = { K = "Clean", O = "Silver", G = "Rough" }, T = 0 },
	{ X = 7, Z = 7, D = { K = "Clean", O = "Ruby", G = "Clean" }, T = 0.1 },
	{ X = 4, Z = 4, D = { K = "Ingot", O = "Silver", G = "Rough" }, T = 0 },
	{ X = 7, Z = 4, D = { K = "Ingot", O = "Gold", G = "Clean" }, T = 0.1 },
	{ X = 3, Z = 1, D = { K = "Alloy", O = "Gold", G = "Clean" }, T = 0 },
	{ X = 5, Z = 2, D = { K = "Ingot", O = "Copper", G = "Clean" }, T = 0 },
}

local function cablePoint(pole: any, name: string): any
	local base = pole.PrimaryPart
	return base.CFrame:PointToWorldSpace(base:FindFirstChild(name).CFrame.Position)
end

function Factory.build(Loader: any, parent: any, level: number?)
	local CF = Loader.CFrame
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local Old = require("./machines_gallery")
	local CELL = GameConfig.CellSize

	local plot = { Id = 1, Center = V3.new(0, 0.3, 0), Facing = V3.new(0, 0, -1) }
	local plotCF = CF.lookAt(plot.Center, plot.Center + plot.Facing)
	local root = roblox.Instance.new("Model")
	root.Name = "Factory"
	root.Parent = parent
	-- grass round the plot
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	Geo.block(root, CF.new(0, -1.3, 20), V3.new(260, 2, 260), roblox.Color3.fromRGB(122, 178, 78))
	local plotModel = PlotBuilder.buildPlot(root, plot, Rng.new(1))
	Old.paintGuis(Loader, root, plotModel)

	local models = {}
	for i, entry in Factory.Machines do
		local info = MachineData.ById[entry.Id]
		local look = if info.Upgrades and level then level else 0
		local model = MachineBuilder.build(entry.Id, look)
		model:PivotTo(plotCF * Grid.localCFrame(entry.Id, entry.X, entry.Z, entry.R))
		model.Parent = root
		Old.paintGuis(Loader, root, model)
		local top = model:FindFirstChild("ChimneyTop", true)
		if top then
			Old.smoke(Loader, root, top, 1.0)
		end
		models[i] = model
	end
	for i, it in Factory.Items do
		local cf = plotCF * Grid.localCFrame("Conveyor", it.X, it.Z, 0) * CF.new(0, 1.05, it.T * CELL)
		local model = if it.D.K == "Clean"
			then ItemBuilder.display(it.D, cf * CF.Angles(0, 0.6 * i, 0), i)
			else ItemBuilder.build({ Kind = it.D.K, OreId = it.D.O, Grade = it.D.G }, cf * CF.Angles(0, 0.4 * i, 0), i)
		model.Parent = root
	end

	-- power cables exactly as the game draws them (PowerLogic networks, the
	-- PowerController geometry: one cable between the facing insulators of
	-- linked poles, one from the nearest insulator down to the top of each
	-- machine / generator a pole feeds; Beams in game, parts here)
	local PowerLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.PowerLogic")
	local result = PowerLogic.compute(Factory.Machines, {})
	local function insulator(pole: any, toward: any): any
		local l, r = cablePoint(pole, "CableL"), cablePoint(pole, "CableR")
		return if (l - toward).Magnitude <= (r - toward).Magnitude then l else r
	end
	local function sag(a: any, b: any): number
		return math.clamp((a - b).Magnitude * 0.045, 0.25, 1.6)
	end
	local links, feeds = 0, 0
	for i, pole in result.Poles do
		local model = models[i]
		local base = model.PrimaryPart
		for _, j in pole.Links do
			if j > i then
				local other = models[j].PrimaryPart
				local a = insulator(model, other.CFrame.Position)
				local b = insulator(models[j], base.CFrame.Position)
				KitMachines.cable(root, a, b, sag(a, b))
				links += 1
			end
		end
		for _, j in pole.Feeds do
			local target = models[j].PrimaryPart
			local a = insulator(model, target.CFrame.Position)
			local status = target:FindFirstChild("Status")
			local top = if status then status.CFrame.Position.Y - 1.5 else 3
			local y = math.min(top, a.Y - 0.4 - target.CFrame.Position.Y)
			local b = target.CFrame:PointToWorldSpace(V3.new(0, y, 0))
			KitMachines.cable(root, a, b, sag(a, b))
			feeds += 1
		end
	end
	for _, net in result.Networks do
		print(string.format("  network %s: supply %d, demand %d, speed %.2f", net.Id, net.Supply, net.Demand, net.Speed))
	end
	print(string.format("Factory: %d machines, %d pole links, %d feeds", #Factory.Machines, links, feeds))
	return root
end

return Factory
