--[[
	A working factory on a plot (scene "factory", shots in
	tools/preview/factory_shots.json): the real plot pad (PlotBuilder) at the
	origin facing -Z, the roster machines placed on the grid the way a player
	would (express belts from the yard -> Splitter -> Brick / Plasma Furnace
	-> Sell Box, a Robot Arm feeding an Alloy Furnace), ores and ingots on
	the belts, and power: a Solar Panel and a Wind Turbine on a network of
	Power Poles with cables to every machine they power. The cables follow
	PowerLogic when it exists (the same networks the game computes),
	otherwise the nearest pole.
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
	{ Id = "PowerPole", X = 2, Z = 9, R = 0 },
	{ Id = "PowerPole", X = 6, Z = 10, R = 0 },
	{ Id = "PowerPole", X = 9, Z = 9, R = 0 },
	{ Id = "PowerPole", X = 1, Z = 6, R = 0 },
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

-- Highest point of a model near its middle (Lune has no GetBoundingBox).
local function topOf(model: any): any
	local pivot = model:GetPivot().Position
	local top = pivot.Y
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local p = part.CFrame.Position
			local dx, dz = p.X - pivot.X, p.Z - pivot.Z
			if dx * dx + dz * dz < 2.5 then
				top = math.max(top, p.Y + part.Size.Y / 2)
			end
		end
	end
	return V3.new(pivot.X, top, pivot.Z)
end

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

	-- power cables: pole <-> pole, pole -> each machine it powers
	local okLogic, PowerLogic = pcall(Loader.requirePath, "ReplicatedStorage.Shared.Machines.PowerLogic")
	local poles = {}
	for i, entry in Factory.Machines do
		if entry.Id == "PowerPole" then
			table.insert(poles, i)
		end
	end
	local links: { { number } } = {}
	local feeds: { { number } } = {}
	local fromLogic = false
	if okLogic and type(PowerLogic) == "table" and type(PowerLogic.cables) == "function" then
		-- PowerLogic.cables(entries, levels) -> links { {pole, pole} }, feeds { {pole, machine} } (entry indexes)
		local ok, l, f = pcall(PowerLogic.cables, Factory.Machines, {})
		if ok and l and f then
			links, feeds, fromLogic = l, f, true
		end
	end
	if not fromLogic then
		local rules = MachineData.PowerRules
		local function cheb(ax: number, az: number, bx: number, bz: number): number
			return math.max(math.abs(ax - bx), math.abs(az - bz))
		end
		for a = 1, #poles do
			for b = a + 1, #poles do
				local pa, pb = Factory.Machines[poles[a]], Factory.Machines[poles[b]]
				if cheb(pa.X, pa.Z, pb.X, pb.Z) <= rules.PoleLink then
					table.insert(links, { poles[a], poles[b] })
				end
			end
		end
		for i, entry in Factory.Machines do
			local info = MachineData.ById[entry.Id]
			if (info.Power or 0) > 0 or (info.PowerOut or 0) > 0 then
				local w, d = Grid.footprint(entry.Id, entry.R)
				local best, bestDist = nil, math.huge
				for _, p in poles do
					local pole = Factory.Machines[p]
					for cx = entry.X, entry.X + w - 1 do
						for cz = entry.Z, entry.Z + d - 1 do
							local dist = cheb(cx, cz, pole.X, pole.Z)
							if dist <= rules.PoleReach and dist < bestDist then
								best, bestDist = p, dist
							end
						end
					end
				end
				if best then
					table.insert(feeds, { best, i })
				end
			end
		end
	end
	for _, pair in links do
		local a, b = models[pair[1]], models[pair[2]]
		for _, name in { "CableL", "CableR" } do
			KitMachines.cable(root, cablePoint(a, name), cablePoint(b, name), 0.9)
		end
	end
	for _, pair in feeds do
		local pole, target = models[pair[1]], models[pair[2]]
		local to = topOf(target) - V3.new(0, 0.15, 0)
		local l, r = cablePoint(pole, "CableL"), cablePoint(pole, "CableR")
		local from = if (l - to).Magnitude < (r - to).Magnitude then l else r
		KitMachines.cable(root, from, to, 0.6)
	end
	print(
		string.format(
			"Factory: %d machines, %d pole links, %d feeds (%s)",
			#Factory.Machines,
			#links,
			#feeds,
			if fromLogic then "PowerLogic" else "nearest pole"
		)
	)
	return root
end

return Factory
