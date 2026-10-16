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

	---------------------------------------------------------------- base yard (WP-Base)

	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	local function buildPlot(plot: any): any
		local folder = roblox.Instance.new("Folder")
		return PlotBuilder.buildPlot(folder, plot, Rng.new(plot.Id))
	end

	local function localPoint(plot: any, part: any, attachment: any): any
		local world = part.CFrame * attachment.CFrame
		return WorldLayout.plotCFrame(plot):PointToObjectSpace(world.Position)
	end

	T.test("Yard: every plot has the pen, 4 podiums, foundry and train stop, named for the services", function()
		for _, plot in WorldLayout.Plots do
			local model = buildPlot(plot)
			local yard = model:FindFirstChild("Yard")
			T.truthy(yard, "Yard")
			for _, name in { "Ground", "Fence", "Pen", "Foundry", "TrainStop" } do
				T.truthy(yard:FindFirstChild(name), `plot {plot.Id} {name}`)
			end
			local intake = yard.Pen:FindFirstChild("Intake")
			T.truthy(intake and intake:IsA("BasePart"), "Pen.Intake part")
			T.eq(intake.Transparency, 1, "intake invisible")
			T.falsy(intake.CanCollide, "intake doesn't collide")
			T.falsy(intake.CanQuery, "intake not queryable")
			local box = BaseLayout.Pen.Intake
			local center = WorldLayout.plotCFrame(plot):PointToObjectSpace(intake.CFrame.Position)
			T.near(center.X, box.Center.X, 1e-3, "intake x")
			T.near(center.Z, box.Center.Z, 1e-3, "intake z")
			T.near(intake.Size.X, box.Size.X, 1e-3, "intake width")
			T.near(intake.Size.Z, box.Size.Z, 1e-3, "intake depth")
			T.le(center.Y - intake.Size.Y / 2, 0, "intake reaches the ground")
			T.le(box.Size.Y, center.Y + intake.Size.Y / 2, "intake is tall enough")
			local prompt = intake:FindFirstChild("Prompt")
			T.truthy(prompt and prompt:IsA("Attachment"), "pen Prompt attachment")
			local p = localPoint(plot, intake, prompt)
			T.near((p - BaseLayout.Pen.PromptPoint).Magnitude, 0, 1e-3, "prompt at Pen.PromptPoint")
			for slot, rect in BaseLayout.Podiums do
				local podium = yard:FindFirstChild("Podium" .. slot)
				T.truthy(podium, "Podium" .. slot)
				local top = podium:FindFirstChild("Top")
				T.truthy(top and top:IsA("BasePart"), "Top part")
				local orePoint = top:FindFirstChild("OrePoint")
				T.truthy(orePoint and orePoint:IsA("Attachment"), "OrePoint")
				local op = localPoint(plot, top, orePoint)
				T.near(op.X, rect.Center.X, 1e-3, "ore point x")
				T.near(op.Z, rect.Center.Z, 1e-3, "ore point z")
				T.near(op.Y, BaseLayout.PodiumOreHeight, 1e-3, "ore point height")
				T.truthy(top:FindFirstChild("Prompt"), "podium Prompt attachment")
				local locked = slot > EconomyConfig.Podiums.Free
				T.eq(podium:FindFirstChild("Lock") ~= nil, locked, "lock on slot " .. slot)
				T.eq(podium:FindFirstChild("PricePlate") ~= nil, locked, "price plate on slot " .. slot)
				if locked then
					local label = podium.PricePlate:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
					T.eq(label.Text, "100 R$", "price text")
				end
			end
		end
	end)

	T.test("Yard: part budget, shadows and the gate in the back rail", function()
		local plot = WorldLayout.Plots[1]
		local model = buildPlot(plot)
		local parts, collide = 0, 0
		for _, d in model.Yard:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d.CanCollide then
					collide += 1
				end
				local s = d.Size
				if s.X * s.Y * s.Z < 1 and d.Transparency < 1 then
					T.falsy(d.CastShadow, `small part {d:GetFullName()} casts a shadow`)
				end
			end
		end
		T.le(parts, 180, "yard parts")
		T.lt(collide, parts, "decoration doesn't collide")
		-- nothing of the back rail blocks the YardGate opening
		local gate = BaseLayout.YardGate
		local edge = GameConfig.PlotCells * GameConfig.CellSize / 2 + 0.5
		local plotCF = WorldLayout.plotCFrame(plot)
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") and d.CanCollide then
				local p = plotCF:PointToObjectSpace(d.CFrame.Position)
				if math.abs(p.Z - edge) < 0.6 and d.Size.Y < 3 then
					local minX = p.X - d.Size.X / 2
					local maxX = p.X + d.Size.X / 2
					local blocks = minX < gate.CenterX + gate.Width / 2 - 0.01 and maxX > gate.CenterX - gate.Width / 2 + 0.01
					T.falsy(blocks, "rail across the yard gate")
				end
			end
		end
	end)

	T.test("Yard: rocks, trees, grass patches and ore nodes stay out of every yard", function()
		for _, s in WorldBuilder.generateNodeSpawns() do
			T.falsy(PlotBuilder.isInYard(s.Position), "node spawn in a yard")
		end
		for _, plot in WorldLayout.Plots do
			local cf = WorldLayout.plotCFrame(plot)
			T.truthy(PlotBuilder.isInYard(cf:PointToWorldSpace(BaseLayout.Pen.Area.Center)), "pen is in the yard")
			T.truthy(PlotBuilder.isInYard(cf:PointToWorldSpace(Vector3.new(0, 0, BaseLayout.RailZ))), "the rail behind it too")
			T.falsy(PlotBuilder.isInYard(plot.Center), "the machine grid is not the yard")
		end
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local checked = 0
		for _, folderName in { "Land", "Emberfall" } do
			for _, d in map:FindFirstChild(folderName):GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					-- flat decoration near the ground: grass patches, trees, rocks, bushes, flowers
					if p.Y > -2 and p.Y < 20 and d.Size.X < 40 and d.Size.Z < 40 then
						checked += 1
						T.falsy(PlotBuilder.isInYard(p), `{d:GetFullName()} lies in a yard`)
					end
				end
			end
		end
		T.lt(100, checked, "decoration was checked")
	end)
end
