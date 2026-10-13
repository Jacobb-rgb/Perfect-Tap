-- Grid maths: rotations, footprints, cells, sides and output cells agree
-- with each other and with the built machine models.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")

	local CELLS = GameConfig.PlotCells

	T.test("Grid: dir and right match the LookVector and RightVector of localCFrame", function()
		for r = 0, 3 do
			local cf = Grid.localCFrame("Conveyor", 5, 5, r)
			local dx, dz = Grid.dir(r)
			T.near(cf.LookVector.X, dx, 1e-5, `r{r} look x`)
			T.near(cf.LookVector.Z, dz, 1e-5, `r{r} look z`)
			local rx, rz = Grid.right(r)
			T.near(cf.RightVector.X, rx, 1e-5, `r{r} right x`)
			T.near(cf.RightVector.Z, rz, 1e-5, `r{r} right z`)
		end
		local dx, dz = Grid.dir(0)
		T.eq(dx, 0, "r0 dx")
		T.eq(dz, -1, "r0 faces the road (-Z)")
	end)

	T.test("Grid: footprints swap at rotations 1 and 3", function()
		for _, machine in MachineData.List do
			for r = 0, 3 do
				local w, d = Grid.footprint(machine.Id, r)
				if r % 2 == 1 then
					T.eq(w, machine.Size[2], machine.Id .. " w")
					T.eq(d, machine.Size[1], machine.Id .. " d")
				else
					T.eq(w, machine.Size[1], machine.Id .. " w")
					T.eq(d, machine.Size[2], machine.Id .. " d")
				end
			end
		end
	end)

	T.test("Grid: key is unique per cell", function()
		local seen = {}
		for z = 0, CELLS - 1 do
			for x = 0, CELLS - 1 do
				local k = Grid.key(x, z)
				T.falsy(seen[k], `key {k} used twice`)
				seen[k] = true
			end
		end
	end)

	T.test("Grid: localCFrame and cellFromLocal round-trip for all 144 cells", function()
		for r = 0, 3 do
			for z = 0, CELLS - 1 do
				for x = 0, CELLS - 1 do
					local gx, gz = Grid.cellFromLocal(Grid.localCFrame("Conveyor", x, z, r).Position)
					T.eq(gx, x, `x at {x},{z} r{r}`)
					T.eq(gz, z, `z at {x},{z} r{r}`)
				end
			end
		end
		local half = CELLS * GameConfig.CellSize / 2
		T.eq(Grid.cellFromLocal(Vector3.new(-half - 0.1, 0, 0)), nil, "off the plot")
		T.eq(Grid.cellFromLocal(Vector3.new(0, 0, half + 0.1)), nil, "off the plot")
		T.eq(Grid.cellFromLocal(Vector3.new(0 / 0, 0, 0)), nil, "NaN")
	end)

	T.test("Grid: footprint centre sits in the middle of its cells", function()
		for _, machine in MachineData.List do
			for r = 0, 3 do
				local w, d = Grid.footprint(machine.Id, r)
				local p = Grid.localCFrame(machine.Id, 2, 3, r).Position
				local half = CELLS * GameConfig.CellSize / 2
				T.near(p.X, -half + (2 + w / 2) * GameConfig.CellSize, 1e-6, machine.Id .. " x")
				T.near(p.Z, -half + (3 + d / 2) * GameConfig.CellSize, 1e-6, machine.Id .. " z")
			end
		end
	end)

	T.test("Grid: sideOf names the faces from the machine's point of view", function()
		-- 2x2 at (4,4), facing the road (-Z): front row is z=3, right is +X
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 0, 4, 3), "Front")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 0, 5, 6), "Back")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 0, 6, 4), "Right")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 0, 3, 5), "Left")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 0, 3, 3), nil, "diagonal")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 0, 4, 4), nil, "inside")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 0, 4, 2), nil, "two cells away")
		-- turned to face +X: right is +Z
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 1, 6, 4), "Front")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 1, 3, 4), "Back")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 1, 4, 6), "Right")
		T.eq(Grid.sideOf("ClayFurnace", 4, 4, 1, 5, 3), "Left")
		-- 3x2 Cleaning Station turned: footprint 2 wide, 3 deep
		T.eq(Grid.sideOf("CleaningStation", 0, 0, 1, 1, 3), "Right")
		T.eq(Grid.sideOf("CleaningStation", 0, 0, 1, 2, 2), "Front")
	end)

	T.test("Grid: 2-wide machines output from the right front cell", function()
		local x, z = Grid.outputCell("ClayFurnace", 8, 4, 0)
		T.eq(x, 9, "right column")
		T.eq(z, 3, "front cell")
		x, z = Grid.outputCell("ClayFurnace", 8, 4, 2) -- facing +Z: right is -X
		T.eq(x, 8)
		T.eq(z, 6)
		x, z = Grid.outputCell("BlastFurnace", 0, 0, 0) -- 3-wide: middle column, off the plot
		T.eq(x, 1)
		T.eq(z, -1)
		T.eq(Grid.outputCell("SellChute", 3, 3, 0), nil, "chute has no output")
		T.eq(Grid.outputCell("Conveyor", 3, 3, 0), nil, "belt has no output")
		T.eq(Grid.outputCell("CleaningStation", 3, 3, 0), nil, "station uses its tray")
		T.eq(Grid.outputLocal("CleaningStation"), nil)
		local out = Grid.outputLocal("Crusher")
		T.near(out.X, 2, 1e-5, "2-wide output x")
		T.near(out.Z, -4.5, 1e-5, "2-wide output z")
		T.near(out.Y, 1.8, 1e-5, "output height")
		out = Grid.outputLocal("BlastFurnace")
		T.near(out.X, 0, 1e-5, "3-wide output x")
		T.near(out.Z, -6.5, 1e-5, "3-wide output z")
	end)

	T.test("Grid: output cell is in front of the footprint for every rotation", function()
		for _, machine in MachineData.List do
			if Grid.outputLocal(machine.Id) then
				for r = 0, 3 do
					local ox, oz = Grid.outputCell(machine.Id, 4, 4, r)
					T.eq(Grid.sideOf(machine.Id, 4, 4, r, ox, oz), "Front", `{machine.Id} r{r}`)
				end
			end
		end
	end)

	T.test("Grid: outputCell matches the built model's Output attachment", function()
		for _, machine in MachineData.List do
			local outputLocal = Grid.outputLocal(machine.Id)
			if outputLocal then
				for r = 0, 3 do
					local w, d = Grid.footprint(machine.Id, r)
					-- any in-bounds origin works; use two different ones
					for _, origin in { { 0, 0 }, { CELLS - w, CELLS - d } } do
						local model = MachineBuilder.build(machine.Id)
						model:PivotTo(Grid.localCFrame(machine.Id, origin[1], origin[2], r))
						local base = model.PrimaryPart
						local attachment = base:FindFirstChild("Output")
						T.truthy(attachment, machine.Id .. " has an Output")
						local world = (base.CFrame * attachment.CFrame).Position
						local ex, ez = Grid.outputCell(machine.Id, origin[1], origin[2], r)
						local half = CELLS * GameConfig.CellSize / 2
						local gx = math.floor((world.X + half) / GameConfig.CellSize)
						local gz = math.floor((world.Z + half) / GameConfig.CellSize)
						T.eq(gx, ex, `{machine.Id} r{r} at {origin[1]},{origin[2]}: output x`)
						T.eq(gz, ez, `{machine.Id} r{r} at {origin[1]},{origin[2]}: output z`)
					end
				end
			end
		end
	end)
end
