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

	T.test("Machines: water pours from WaterOut down to WaterIn on the station and the Auto Cleaner", function()
		for _, id in { "CleaningStation", "AutoCleaner" } do
			local model = MachineBuilder.build(id)
			local out, into = attachment(model, "WaterOut"), attachment(model, "WaterIn")
			T.truthy(out and into, id .. " has WaterOut and WaterIn")
			local a, b = out.CFrame.Position, into.CFrame.Position
			T.truthy(a.Y > b.Y + 1.5, id .. " the water falls")
			T.eq(type(out:GetAttribute("Curve")), "number", id .. " WaterOut Curve")
			T.eq(type(into:GetAttribute("Curve")), "number", id .. " WaterIn Curve")
			-- the Beam's control points stay between the two ends (no loops)
			local p1 = a + out.CFrame.RightVector * out:GetAttribute("Curve")
			local p2 = b - into.CFrame.RightVector * into:GetAttribute("Curve")
			T.truthy(p1.Y <= a.Y + 1e-3 and p2.Y >= b.Y - 1e-3, id .. " curve goes down")
			local w, d = MachineData.ById[id].Size[1] * CELL / 2, MachineData.ById[id].Size[2] * CELL / 2
			T.truthy(math.abs(b.X) < w and math.abs(b.Z) < d, id .. " water lands on the machine")
		end
		-- the station's stream lands in its basin, the cleaner's is a shower over the rollers
		local station = MachineBuilder.build("CleaningStation")
		local pool = station:FindFirstChild("WaterPool")
		T.truthy(pool, "station has a WaterPool")
		local landing = attachment(station, "WaterIn").CFrame.Position
		local poolTop = pool.CFrame.Position.Y + pool.Size.Y / 2 - station.PrimaryPart.CFrame.Position.Y
		T.near(landing.Y, poolTop, 0.05, "lands on the water surface")
		T.truthy(math.abs(landing.X - pool.CFrame.Position.X) < pool.Size.X / 2, "inside the basin (x)")
		T.truthy(math.abs(landing.Z - pool.CFrame.Position.Z) < pool.Size.Z / 2, "inside the basin (z)")
		T.falsy(pool.CanCollide, "water does not collide")
		local cleaner = MachineBuilder.build("AutoCleaner")
		T.eq(attachment(cleaner, "WaterOut"):GetAttribute("Spray"), true, "cleaner sprays")
		T.eq(attachment(station, "WaterOut"):GetAttribute("Spray"), nil, "station pours")
		-- the close-up camera keeps a clear view: the stream is off to the side of the ore
		local ore = attachment(station, "OrePoint").CFrame.Position
		T.truthy(math.abs(landing.X - ore.X) > 3, "stream beside the vise")
	end)

	T.test("Machines: the Cleaning Station's stream stays out of the close-up view", function()
		local model = MachineBuilder.build("CleaningStation")
		local cam = attachment(model, "CamPoint").CFrame
		local a, b = pos(model, "WaterOut"), pos(model, "WaterIn")
		-- CameraFit.BaseFov (40 degrees) on a 16:9 screen
		local tanHalfWidth = math.tan(math.rad(20)) * 16 / 9
		for _, t in { 0, 0.5, 1 } do
			local rel = cam:PointToObjectSpace(a:Lerp(b, t))
			T.truthy(rel.Z < 0 and math.abs(rel.X) / -rel.Z > tanHalfWidth, `stream point {t} outside the close-up`)
		end
	end)

	T.test("Machines: pipe bends are pipe pieces, not ball elbows", function()
		-- every machine with pipes: no ball-shaped elbow parts bigger than a bolt
		for _, id in { "CleaningStation", "ClayFurnace", "BlastFurnace", "AutoCleaner" } do
			for _, part in parts(MachineBuilder.build(id)) do
				if part:IsA("Part") and part.Shape == roblox.Enum.PartType.Ball then
					T.truthy(part.Size.X <= 0.4, `{id} has a ball bigger than a bolt ({part.Size.X})`)
				end
			end
		end
	end)

	T.test("Machines: moving parts and glows the client animates are named", function()
		local function count(model: any, name: string): number
			local n = 0
			for _, part in parts(model) do
				if part.Name == name then
					n += 1
				end
			end
			return n
		end
		local crusher = MachineBuilder.build("Crusher")
		for i = 1, 2 do
			T.eq(count(crusher, "Roller" .. i), 1, "Roller" .. i)
			-- tooth bars turn with each roller
			T.truthy(count(crusher, "Roller" .. i .. "Tooth") >= 3, "Roller" .. i .. " teeth")
		end
		-- a big and a small cog on each side, each pair on one shared axis line
		-- (the client spins every part of a name around the first one's X axis)
		for _, name in { "Cog1", "Cog2" } do
			T.truthy(count(crusher, name) >= 8, name .. " parts on both sides")
			local axis = crusher:FindFirstChild(name)
			for _, part in parts(crusher) do
				if part.Name == name then
					local p = part.CFrame.Position
					T.near(p.Y, axis.CFrame.Position.Y, 1e-3, name .. " on the axis (y)")
					T.near(p.Z, axis.CFrame.Position.Z, 1e-3, name .. " on the axis (z)")
				end
			end
		end
		T.eq(typeof(MachineBuilder.CogRatio), "number", "cog ratio for the client")
		local cleaner = MachineBuilder.build("AutoCleaner")
		T.eq(count(cleaner, "Drum"), 1, "Drum")
		T.truthy(count(cleaner, "DrumRib") >= 2, "DrumRib")
		T.truthy(count(cleaner, "BedRoller") >= 3, "BedRoller")
		T.truthy(cleaner:FindFirstChild("Vent"):FindFirstChild("Smoke"), "Vent smoke")
		-- stack light: one lamp lit (Neon) in the built look, the rest dim plastic
		local lit = 0
		for _, name in { "StackRed", "StackAmber", "StackGreen" } do
			T.eq(count(cleaner, name), 1, name)
			T.truthy(MachineBuilder.Stack.Lamps[name], name .. " colour for the client")
			if cleaner:FindFirstChild(name).Material == roblox.Enum.Material.Neon then
				lit += 1
				T.eq(name, MachineBuilder.Stack.Lit, "the built look lights Stack.Lit")
			end
		end
		T.eq(lit, 1, "one stack lamp lit")
		for _, id in { "ClayFurnace", "BlastFurnace" } do
			local furnace = MachineBuilder.build(id)
			local glow = furnace:FindFirstChild("Glow")
			T.truthy(glow and glow:FindFirstChildOfClass("PointLight") and glow:FindFirstChild("Embers"), id .. " Glow")
			T.truthy(furnace:FindFirstChild("ChimneyTop"):FindFirstChild("Smoke"), id .. " chimney smoke")
			local lights = 0
			for _, d in furnace:GetDescendants() do
				if d:IsA("PointLight") then
					lights += 1
				end
			end
			T.eq(lights, 1, id .. " one light")
		end
		T.truthy(count(MachineBuilder.build("BlastFurnace"), "Molten") >= 1, "molten glass tap")
		T.truthy(MachineBuilder.build("SellChute"):FindFirstChild("Coins"):FindFirstChildOfClass("PointLight"), "coin light")
		T.truthy(MachineBuilder.build("StorageCrate"):FindFirstChild("CountSign"), "crate count sign")
	end)

	T.test("Machines: the belt paints its rollers on one SurfaceGui", function()
		local belt = MachineBuilder.build("Conveyor"):FindFirstChild("Belt")
		local guis = 0
		for _, d in belt:GetChildren() do
			if d:IsA("SurfaceGui") then
				guis += 1
				T.truthy(d.Face == roblox.Enum.NormalId.Top, "on the top face")
				T.truthy(d.MaxDistance > 0, "fades out with distance")
			end
		end
		T.eq(guis, 1, "one SurfaceGui")
	end)

	T.test("Machines: part budget and footprint", function()
		for _, machine in MachineData.List do
			local model = MachineBuilder.build(machine.Id)
			if not machine.IsConveyor then
				T.le(#parts(model), 70, machine.Id .. " part count")
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
