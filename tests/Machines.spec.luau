-- Machine models: attachments the services and controllers rely on, outputs
-- on the shared grid positions, and part budgets for phones.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")

	local CELL = GameConfig.CellSize

	local function parts(model: any): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function attachment(model: any, name: string): any
		local a = model.PrimaryPart:FindFirstChild(name)
		return if a and a:IsA("Attachment") then a else nil
	end

	-- position relative to the Base (= the model pivot), like Grid.outputLocal
	local function pos(model: any, name: string): any
		return attachment(model, name).CFrame.Position
	end

	local function near(a: any, b: any, eps: number?): boolean
		return (a - b).Magnitude <= (eps or 1e-4)
	end

	T.test("Machines: every machine builds with Base, Prompt, Status and Intake", function()
		for _, machine in MachineData.List do
			local model = MachineBuilder.build(machine.Id)
			T.truthy(model.PrimaryPart, machine.Id .. " PrimaryPart")
			T.eq(model.PrimaryPart.Name, "Base", machine.Id .. " PrimaryPart name")
			T.eq(model:GetAttribute("MachineId"), machine.Id)
			T.truthy(attachment(model, "Prompt"), machine.Id .. " Prompt")
			T.truthy(attachment(model, "Status"), machine.Id .. " Status")
			if machine.IsConveyor then
				T.eq(attachment(model, "Intake"), nil, "belts have no hopper")
			else
				local intake = attachment(model, "Intake")
				T.truthy(intake, machine.Id .. " Intake")
				T.eq(typeof(intake:GetAttribute("IntakeSize")), "Vector3", machine.Id .. " IntakeSize")
			end
			for _, part in parts(model) do
				T.truthy(part.Anchored, machine.Id .. " " .. part.Name .. " anchored")
			end
		end
	end)

	T.test("Machines: Status sits 1.5 studs above the highest part", function()
		for _, machine in MachineData.List do
			local model = MachineBuilder.build(machine.Id)
			local baseY = model.PrimaryPart.CFrame.Position.Y
			local top = -math.huge
			for _, part in parts(model) do
				-- at least 1.5 studs above every part's centre
				top = math.max(top, part.CFrame.Position.Y)
			end
			local status = pos(model, "Status")
			T.truthy(status.Y + baseY >= top + 1.5 - 1e-3, machine.Id .. " Status above the model")
			T.near(status.X, 0, 1e-4)
			T.near(status.Z, 0, 1e-4)
		end
	end)

	T.test("Machines: outputs are on the grid, in front, outside the intake", function()
		for _, machine in MachineData.List do
			local model = MachineBuilder.build(machine.Id)
			local expected = Grid.outputLocal(machine.Id)
			if expected then
				local out = pos(model, "Output")
				T.truthy(near(out, expected), `{machine.Id} Output at Grid.outputLocal ({out} vs {expected})`)
				local w, d = machine.Size[1], machine.Size[2]
				-- 0.5 studs in front of the footprint
				T.near(out.Z, -(d * CELL / 2) - 0.5, 1e-4, machine.Id .. " 0.5 studs out front")
				-- on a cell centre column
				local column = (out.X + w * CELL / 2) / CELL - 0.5
				T.near(column, math.floor(column + 0.5), 1e-4, machine.Id .. " on a cell centre")
				T.truthy(math.abs(out.X) < w * CELL / 2, machine.Id .. " inside the width")
				-- outside its own intake box
				local intake = attachment(model, "Intake")
				local size = intake:GetAttribute("IntakeSize")
				local localOut = intake.CFrame:PointToObjectSpace(out)
				local inside = math.abs(localOut.X) <= size.X / 2 and math.abs(localOut.Y) <= size.Y / 2 and math.abs(localOut.Z) <= size.Z / 2
				T.falsy(inside, machine.Id .. " Output inside its own Intake")
			elseif machine.Id == "CleaningStation" then
				T.truthy(attachment(model, "Output"), "station keeps its tray Output")
			else
				T.eq(attachment(model, "Output"), nil, machine.Id .. " has no Output")
			end
		end
	end)

	T.test("Machines: the Cleaning Station close-up points did not move", function()
		local model = MachineBuilder.build("CleaningStation")
		local top = 3.4
		local orePoint = Vector3.new(0, top + 1.95, 0.3)
		T.truthy(near(pos(model, "OrePoint"), orePoint), "OrePoint")
		T.truthy(near(pos(model, "CamPoint"), Vector3.new(0, top + 5.4, -4.6)), "CamPoint position")
		local look = attachment(model, "CamPoint").CFrame.LookVector
		local want = (orePoint + Vector3.new(0, 0.1, 0) - Vector3.new(0, top + 5.4, -4.6)).Unit
		T.truthy(near(look, want, 1e-3), "CamPoint looks at the ore")
		T.truthy(near(pos(model, "Output"), Vector3.new(3.6, top + 1.4, -0.4)), "tray Output")
	end)

	T.test("Machines: the Anvil has its close-up points and ingot slots", function()
		local model = MachineBuilder.build("Anvil")
		local anvilPoint = pos(model, "AnvilPoint")
		T.truthy(near(anvilPoint, Vector3.new(0, 4.95, 0.3)), "AnvilPoint")
		local cam = attachment(model, "CamPoint")
		T.truthy(cam, "CamPoint")
		T.truthy(near(cam.CFrame.Position, Vector3.new(0, 8.5, -5.5)), "CamPoint position")
		local want = (anvilPoint + Vector3.new(0, 0.2, 0) - Vector3.new(0, 8.5, -5.5)).Unit
		T.truthy(near(cam.CFrame.LookVector, want, 1e-3), "CamPoint looks at the anvil")
		local face = model:FindFirstChild("AnvilFace")
		local faceTop = face.CFrame.Position.Y + face.Size.Y / 2 - model.PrimaryPart.CFrame.Position.Y
		for i = 1, 4 do
			local slot = attachment(model, "IngotSlot" .. i)
			T.truthy(slot, "IngotSlot" .. i)
			local p = slot.CFrame.Position
			T.truthy(p.Y >= faceTop, "slot " .. i .. " on top of the face")
			T.truthy(math.abs(p.X) <= face.Size.X / 2, "slot " .. i .. " over the face")
		end
	end)

	T.test("Machines: the conveyor is 6 parts with named rails", function()
		local model = MachineBuilder.build("Conveyor")
		local list = parts(model)
		T.le(#list, 6, "conveyor parts")
		local belt = model:FindFirstChild("Belt")
		T.truthy(belt, "Belt")
		T.truthy(belt:HasTag("ConveyorBelt"), "Belt tagged ConveyorBelt")
		local props = belt.CustomPhysicalProperties
		T.truthy(props, "Belt has custom physics")
		T.near(props.Elasticity, 0, 1e-6, "no bounce")
		local railL, railR = model:FindFirstChild("RailL"), model:FindFirstChild("RailR")
		T.truthy(railL and railR, "rails")
		T.truthy(railL.CFrame.Position.X < 0, "RailL at -X")
		T.truthy(railR.CFrame.Position.X > 0, "RailR at +X (Grid.right)")
		local arrows = 0
		for _, part in list do
			if part.Name == "Arrow" then
				arrows += 1
			end
			T.falsy(part.CastShadow, part.Name .. " casts no shadow")
		end
		T.eq(arrows, 2, "one chevron of two wedges")
		T.truthy(model.PrimaryPart.CanQuery, "Base can be queried")
		T.falsy(model.PrimaryPart.CanCollide, "Base doesn't collide")
	end)

	T.test("Machines: part budget and footprint", function()
		for _, machine in MachineData.List do
			local model = MachineBuilder.build(machine.Id)
			if not machine.IsConveyor then
				T.le(#parts(model), 40, machine.Id .. " part count")
			end
			-- nothing pokes more than half a stud into the neighbouring cells
			local hw, hd = machine.Size[1] * CELL / 2, machine.Size[2] * CELL / 2
			for _, part in parts(model) do
				local p = part.CFrame.Position
				T.truthy(math.abs(p.X) <= hw + 0.5 and math.abs(p.Z) <= hd + 0.5, `{machine.Id} {part.Name} centre outside the footprint`)
			end
		end
	end)
end
