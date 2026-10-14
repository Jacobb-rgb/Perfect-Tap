-- PlotService grid helpers: footprint CFrames match the old maths, cells
-- round-trip, and plotAt / isNear find the right plot.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")

	local CELL = GameConfig.CellSize
	local CELLS = GameConfig.PlotCells
	local HALF = CELLS * CELL / 2

	local function sameCFrame(a: any, b: any, label: string)
		local ac, bc = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do
			T.near(ac[i], bc[i], 1e-4, label .. " component " .. i)
		end
	end

	T.test("PlotService: footprintCFrame matches the step c formula", function()
		for _, plot in WorldLayout.Plots do
			for _, machine in MachineData.List do
				for r = 0, 3 do
					local gx, gz = 2, 3
					local w, d = MachineData.footprint(machine, r)
					local old = PlotService.plotCFrame(plot.Id)
						* CFrame.new(-HALF + (gx + w / 2) * CELL, 0, -HALF + (gz + d / 2) * CELL)
						* CFrame.Angles(0, -r * math.pi / 2, 0)
					sameCFrame(PlotService.footprintCFrame(plot.Id, machine.Id, gx, gz, r), old, `{machine.Id} r{r}`)
				end
			end
		end
	end)

	T.test("PlotService: cellAt round-trips every cell centre", function()
		for _, plot in WorldLayout.Plots do
			local cf = PlotService.plotCFrame(plot.Id)
			for z = 0, CELLS - 1 do
				for x = 0, CELLS - 1 do
					local world = cf:PointToWorldSpace(Vector3.new(-HALF + (x + 0.5) * CELL, 1, -HALF + (z + 0.5) * CELL))
					local cx, cz = PlotService.cellAt(plot.Id, world)
					T.eq(cx, x, "cell x")
					T.eq(cz, z, "cell z")
				end
			end
			local outside = cf:PointToWorldSpace(Vector3.new(HALF + 0.5, 1, 0))
			T.eq(PlotService.cellAt(plot.Id, outside), nil, "border is not a cell")
		end
	end)

	T.test("PlotService: plotAt finds the plot and its local position", function()
		for _, plot in WorldLayout.Plots do
			local cf = PlotService.plotCFrame(plot.Id)
			for _, p in { Vector3.new(0, 1, 0), Vector3.new(HALF - 0.1, 0.5, -HALF + 0.1), Vector3.new(-HALF + 0.1, 20, HALF - 0.1) } do
				local id, localPos = PlotService.plotAt(cf:PointToWorldSpace(p))
				T.eq(id, plot.Id, "plot id")
				T.near((localPos - p).Magnitude, 0, 1e-3, "local position")
			end
			-- too high, too low, or beyond the pad
			T.eq(PlotService.plotAt(cf:PointToWorldSpace(Vector3.new(0, 30, 0))), nil, "far above")
			T.eq(PlotService.plotAt(cf:PointToWorldSpace(Vector3.new(0, -5, 0))), nil, "below")
			T.eq(PlotService.plotAt(cf:PointToWorldSpace(Vector3.new(HALF + 3, 1, 0))), nil, "beside the pad")
		end
		T.eq(PlotService.plotAt(Vector3.new(0, 1, 0)), nil, "town square")
	end)

	T.test("PlotService: plot grids line up with Grid.localCFrame", function()
		-- a machine's footprint centre is over its own min cell's plot
		for _, plot in WorldLayout.Plots do
			local world = PlotService.footprintCFrame(plot.Id, "ClayFurnace", 0, 0, 0).Position
			local id, localPos = PlotService.plotAt(world + Vector3.new(0, 1, 0))
			T.eq(id, plot.Id, "plot")
			local x, z = Grid.cellFromLocal(localPos - Vector3.new(CELL / 2, 0, CELL / 2))
			T.eq(x, 0, "min cell x")
			T.eq(z, 0, "min cell z")
		end
	end)

	T.test("PlotService: isNear measures from the plot centre, flat", function()
		local plot = WorldLayout.Plots[3]
		local function playerAt(position: any): any
			local root = { Position = position }
			return {
				Character = {
					FindFirstChild = function(_, name: string)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
			}
		end
		T.truthy(PlotService.isNear(playerAt(plot.Center + Vector3.new(30, 50, 40)), plot.Id, 70), "50 studs flat, high up")
		T.falsy(PlotService.isNear(playerAt(plot.Center + Vector3.new(60, 0, 40)), plot.Id, 70), "72 studs away")
		T.falsy(PlotService.isNear({ Character = nil }, plot.Id, 70), "no character")
	end)
end
