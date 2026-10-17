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
			if machine.IsConveyor or machine.NoIntake then
				T.eq(attachment(model, "Intake"), nil, machine.Id .. " has no hopper")
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
				local inside = math.abs(localOut.X) <= size.X / 2
					and math.abs(localOut.Y) <= size.Y / 2
					and math.abs(localOut.Z) <= size.Z / 2
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

	-- extent of a part along world Y / X / Z (balls are round whatever their rotation)
	local function extents(part: any): (number, number, number)
		local cf, size = part.CFrame, part.Size
		if part:IsA("Part") and part.Shape == roblox.Enum.PartType.Ball then
			return size.X / 2, size.X / 2, size.X / 2
		end
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local ey = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
		local ex = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
		local ez = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		return ex, ey, ez
	end

	T.test("Machines: the conveyor keeps the parts the game uses and stays light", function()
		local model = MachineBuilder.build("Conveyor")
		local list = parts(model)
		T.le(#list, 12, "conveyor parts")
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
		local ex, ey, ez = extents(pool)
		local poolTop = pool.CFrame.Position.Y + ey - station.PrimaryPart.CFrame.Position.Y
		T.near(landing.Y, poolTop, 0.05, "lands on the water surface")
		T.truthy(math.abs(landing.X - pool.CFrame.Position.X) < ex, "inside the basin (x)")
		T.truthy(math.abs(landing.Z - pool.CFrame.Position.Z) < ez, "inside the basin (z)")
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

	T.test("Machines: pipe bend joints sit where two bend pieces meet", function()
		for _, id in { "CleaningStation", "ClayFurnace", "BlastFurnace", "AutoCleaner" } do
			local model = MachineBuilder.build(id)
			local list = parts(model)
			for _, part in list do
				if part.Name == "PipeJoint" then
					local centre = part.CFrame.Position
					local ends = 0
					for _, other in list do
						if other.Name == "PipeBend" then
							local tip = other.CFrame.RightVector * (other.Size.X / 2)
							local p = other.CFrame.Position
							if (p + tip - centre).Magnitude < 0.02 or (p - tip - centre).Magnitude < 0.02 then
								ends += 1
							end
						end
					end
					T.eq(ends, 2, `{id} PipeJoint between two bend pieces`)
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
			T.truthy(count(crusher, "Roller" .. i .. "Tooth") >= 2, "Roller" .. i .. " teeth")
		end
		-- the client spins every part of a name around the first one's X axis
		for _, name in { "Cog1", "Cog2" } do
			T.truthy(count(crusher, name) >= 5, name .. " parts")
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
		T.truthy(count(MachineBuilder.build("BlastFurnace"), "Molten") >= 1, "molten metal")
		T.truthy(MachineBuilder.build("SellChute"):FindFirstChild("Coins"):FindFirstChildOfClass("PointLight"), "coin light")
		T.truthy(MachineBuilder.build("StorageCrate"):FindFirstChild("CountSign"), "crate count sign")
	end)

	T.test("Machines: the belt paints its segments on one SurfaceGui", function()
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
				T.le(#parts(model), 140, machine.Id .. " part count")
			end
			-- every part stays inside its footprint (whole extents, 0.12 studs of
			-- slack); only the output chute may reach out toward the Output
			local hw, hd = machine.Size[1] * CELL / 2, machine.Size[2] * CELL / 2
			for _, part in parts(model) do
				local ex, _, ez = extents(part)
				local p = part.CFrame.Position
				local chute = part.Name == "Chute" or part.Name == "ChuteLip" or part.Name == "Molten"
				local front = if chute then hd + 0.8 else hd + 0.12
				-- side outputs (Splitter, Sorter): their chutes reach into the side cells
				local side = if chute and machine.SideOutputs then hw + 0.8 else hw + 0.12
				T.truthy(
					math.abs(p.X) + ex <= side and p.Z + ez <= hd + 0.12 and -(p.Z - ez) <= front,
					`{machine.Id} {part.Name} reaches out of the footprint ({p.X}, {p.Z} +- {ex}, {ez})`
				)
			end
		end
	end)

	T.test("Machines: the Blast Furnace has a molten throat inside its intake", function()
		local furnace = MachineBuilder.build("BlastFurnace")
		local intake = attachment(furnace, "Intake")
		local size = intake:GetAttribute("IntakeSize")
		local throat = false
		for _, part in parts(furnace) do
			if part.Name == "Molten" and part.Material == roblox.Enum.Material.Neon and part.CFrame.Position.Y > 7 then
				local rel = intake.CFrame:PointToObjectSpace(part.CFrame.Position)
				if math.abs(rel.X) <= size.X / 2 and math.abs(rel.Y) <= size.Y / 2 and math.abs(rel.Z) <= size.Z / 2 then
					throat = true
				end
			end
		end
		T.truthy(throat, "molten throat on the lid")
	end)

	T.test("Machines: the Auto Cleaner's water lands in a tray under its rollers", function()
		local cleaner = MachineBuilder.build("AutoCleaner")
		local pool = cleaner:FindFirstChild("WaterPool")
		T.truthy(pool, "tray WaterPool")
		T.falsy(pool.CanCollide, "water does not collide")
		local landing = attachment(cleaner, "WaterIn").CFrame.Position
		local local_ = cleaner.PrimaryPart.CFrame:PointToObjectSpace(pool.CFrame.Position)
		T.truthy(local_.Y + pool.Size.Y / 2 < landing.Y, "tray below the landing point")
		T.truthy(
			math.abs(landing.X - local_.X) < pool.Size.X / 2 and math.abs(landing.Z - local_.Z) < pool.Size.Z / 2,
			"tray under the shower"
		)
		-- the brush rests just on top of ore (ore about 1 stud tall)
		local drum = cleaner:FindFirstChild("Drum")
		local drumLocal = cleaner.PrimaryPart.CFrame:PointToObjectSpace(drum.CFrame.Position)
		local bottom = drumLocal.Y - drum.Size.Y / 2
		T.truthy(bottom > landing.Y + 0.6 and bottom < landing.Y + 1.4, "brush at ore height")
	end)

	T.test("Machines: the Iron Box has its window, screen, two flaps and hopper", function()
		-- (the owner's "Soft" style: KitMachines builds it with the same parts)
		local model = MachineBuilder.build("IronBox")
		local base = model.PrimaryPart
		local CELLS = MachineData.ById.IronBox.Size
		local front = -(CELLS[2] * CELL / 2)
		local function part(name: string): any
			local found = model:FindFirstChild(name)
			T.truthy(found and found:IsA("BasePart"), "part " .. name)
			return found
		end
		local function localPos(p: any): any
			return base.CFrame:PointToObjectSpace(p.CFrame.Position)
		end
		-- the screen with the two labels the client fills in
		local screen = part("Screen")
		T.truthy(screen.Material == roblox.Enum.Material.Neon, "lit screen")
		local gui = screen:FindFirstChild("ScreenGui")
		T.truthy(gui and gui:FindFirstChild("Item") and gui:FindFirstChild("Counter"), "Item and Counter labels")
		T.eq(gui.Item.Text, MachineBuilder.IronBox.ScreenIdle)
		-- the glass inspection bay and the spot for the shown item inside it
		local glass = part("BayGlass")
		T.truthy(glass.Material == roblox.Enum.Material.Glass and glass.Transparency > 0.3, "see-through glass")
		local show = attachment(model, "ShowPoint")
		T.truthy(show, "ShowPoint")
		local floor = localPos(part("BayFloor"))
		local glassAt = localPos(glass)
		local spot = show.CFrame.Position
		local backAt = localPos(part("BayBack"))
		T.truthy(spot.Z > glassAt.Z and spot.Z < backAt.Z, "between the glass and the dark back of the bay")
		T.truthy(math.abs(spot.X - glassAt.X) < 0.2, "in the middle of the window")
		T.near(spot.Y, floor.Y + part("BayFloor").Size.Y / 2, 0.05, "on the bay floor")
		local window = glass.Size
		T.truthy(window.X > MachineBuilder.IronBox.Window and window.Y > MachineBuilder.IronBox.Window, "the shown item fits the window")
		-- two flaps on the front, SEND at the output column, both under the screen / window
		local keep, send = part("FlapKeep"), part("FlapSend")
		local out = attachment(model, "Output").CFrame.Position
		-- SEND over the chute to the output column (the Soft box keeps it on its flat front)
		T.truthy(math.abs(localPos(send).X - out.X) <= 1, "SEND near the output column")
		T.truthy(localPos(keep).X < 0 and localPos(send).X > 0, "KEEP left, SEND right")
		for _, flap in { keep, send } do
			local p = localPos(flap)
			T.truthy(p.Z < front + 2, flap.Name .. " on the front")
			T.truthy(p.Y + flap.Size.Y / 2 < localPos(screen).Y - screen.Size.Y / 2, flap.Name .. " under the screen")
			T.falsy(flap.CanCollide, flap.Name .. " swings freely")
			T.truthy(flap:FindFirstChild("FlapText"), flap.Name .. " label")
		end
		T.truthy(keep.Color ~= send.Color, "the two ways look different")
		-- both flap labels read from the usual eye and camera heights in front
		-- of the box: the inspection bay's floor never hides their top edge
		local bayFloor = part("BayFloor")
		local floorAt = localPos(bayFloor)
		local lo, hi = floorAt - bayFloor.Size / 2, floorAt + bayFloor.Size / 2
		-- does the segment a -> b pass through the floor's box (slab test)?
		local function hits(a: any, b: any): boolean
			local t0, t1 = 0, 1
			for _, axis in { "X", "Y", "Z" } do
				local from, delta = a[axis], b[axis] - a[axis]
				if math.abs(delta) < 1e-9 then
					if from < lo[axis] or from > hi[axis] then
						return false
					end
				else
					local ta, tb = (lo[axis] - from) / delta, (hi[axis] - from) / delta
					t0 = math.max(t0, math.min(ta, tb))
					t1 = math.min(t1, math.max(ta, tb))
					if t0 > t1 then
						return false
					end
				end
			end
			return true
		end
		for _, flap in { keep, send } do
			local p = localPos(flap)
			local label = flap.FlapText:FindFirstChild("Text")
			-- the label's top edge on the flap's front face
			local top = roblox.Vector3.new(p.X, p.Y + flap.Size.Y / 2 - label.Position.Y.Scale * flap.Size.Y, p.Z - flap.Size.Z / 2 - 0.01)
			-- standing in front, stepped back, and the camera up behind you
			for _, eye in { { 6, 4.5 }, { 12, 6 }, { 9, 10 }, { 16, 12 } } do
				local from = roblox.Vector3.new(p.X, eye[2], front - eye[1])
				T.falsy(hits(from, top), `{flap.Name} label seen from {eye[1]} studs out, {eye[2]} up`)
			end
		end
		-- the floor port the kept ore drops into stays inside the footprint
		T.truthy(model:FindFirstChild("PenPort"), "pen port")
		-- the hopper intake covers the roof cup, not the front
		local intake = attachment(model, "Intake")
		T.truthy(intake.CFrame.Position.Y > localPos(screen).Y, "intake on the roof")
		-- the old strongbox pieces are gone
		T.eq(model:FindFirstChild("Strap"), nil)
		T.eq(model:FindFirstChild("Flap"), nil)
		T.le(#parts(model), 70, "part budget")
	end)

	T.test("Machines: the pen's sorting board (Pen Automation) is a small lit board on two posts", function()
		local board = MachineBuilder.sortingBoard()
		local base = board.PrimaryPart
		T.truthy(base and base.Name == "Base", "Base is the PrimaryPart")
		T.eq(base.Transparency, 1, "an invisible anchor")
		T.falsy(base.CanCollide, "nothing to trip over")
		T.eq(board:GetAttribute("MachineId"), nil, "not a machine")
		T.truthy(attachment(board, "Prompt"), "Prompt attachment")
		T.truthy(attachment(board, "Prompt").CFrame.Position.Z < 0, "the prompt in front of the board")
		T.le(#parts(board), 15, "decor prop budget")
		local display = board:FindFirstChild("Display")
		T.truthy(display and display.Material == roblox.Enum.Material.Neon, "a lit display")
		local gui = display:FindFirstChild("BoardGui")
		T.truthy(gui and gui.Face == roblox.Enum.NormalId.Front, "drawn on its front (-Z)")
		T.truthy(gui:FindFirstChild("Mode") and gui:FindFirstChild("Swatches") and gui:FindFirstChild("Empty"), "its labels")
		for _, d in board:GetDescendants() do
			if d:IsA("BasePart") then
				T.truthy(d.Anchored, d.Name .. " anchored")
				T.falsy(d.CanTouch, d.Name .. " no touch events")
			end
		end
		-- no wider than the space between the pen gate's post and the pen's corner
		local lo, hi = math.huge, -math.huge
		local top = 0
		for _, p in parts(board) do
			if p.Transparency < 1 then
				local at = p.CFrame.Position
				lo = math.min(lo, at.X - p.Size.X / 2)
				hi = math.max(hi, at.X + p.Size.X / 2)
				top = math.max(top, at.Y + p.Size.Y / 2)
			end
		end
		T.truthy(hi - lo <= 4.5, "about 4.4 studs wide (footings)")
		T.truthy(top > 4 and top < 6, "taller than a player's waist, under the gate sign")
		-- painting: one swatch per kept ore, "+N" past the limit, the empty text
		local red, blue = roblox.Color3.fromRGB(220, 40, 40), roblox.Color3.fromRGB(40, 80, 220)
		MachineBuilder.paintSortingBoard(board, { Mode = "KEEPS MY LIST", Colors = { red, blue }, Empty = "NOTHING" })
		T.eq(gui.Mode.Text, "KEEPS MY LIST")
		T.truthy(gui.Swatches.Swatch1.BackgroundColor3 == red and gui.Swatches.Swatch2.BackgroundColor3 == blue, "in order")
		T.falsy(gui.Empty.Visible, "no empty text")
		local many = {}
		for i = 1, MachineBuilder.SortingBoard.MaxSwatches + 3 do
			many[i] = if i % 2 == 0 then red else blue
		end
		MachineBuilder.paintSortingBoard(board, { Mode = "KEEPS EVERYTHING", Colors = many, Empty = "" })
		local max = MachineBuilder.SortingBoard.MaxSwatches
		T.truthy(gui.Swatches:FindFirstChild("Swatch" .. max), "full board")
		T.eq(gui.Swatches:FindFirstChild("Swatch" .. (max + 1)), nil, "never more than MaxSwatches")
		T.eq(gui.Swatches["Swatch" .. max].More.Text, "+4", "the last one counts itself and the rest")
		MachineBuilder.paintSortingBoard(board, { Mode = "KEEPS MY LIST", Colors = { red }, Empty = "" })
		T.eq(gui.Swatches:FindFirstChild("Swatch2"), nil, "extra swatches removed")
		MachineBuilder.paintSortingBoard(board, { Mode = "KEEPS MY LIST", Colors = {}, Empty = "SENDS EVERYTHING ON" })
		T.eq(gui.Swatches:FindFirstChild("Swatch1"), nil)
		T.truthy(gui.Empty.Visible and gui.Empty.Text == "SENDS EVERYTHING ON", "empty text")
	end)

	T.test("Machines: stack light colours for the client", function()
		-- unlit stack lamps keep their hue, the lit one is toned down
		T.truthy(MachineBuilder.Stack.Dim <= 0.35, "unlit lamps keep their colour")
		T.truthy(MachineBuilder.Stack.Glow > 0 and MachineBuilder.Stack.Glow < 0.5, "lit lamp does not bloom white")
	end)

	T.test("Machines: the roster machines come from KitMachines with an upgrade look", function()
		for _, id in { "CleaningStation", "ClayFurnace", "Crusher", "AutoCleaner", "BlastFurnace" } do
			local plain = MachineBuilder.build(id)
			T.eq(plain:GetAttribute("Level"), 0, id .. " level 0 by default")
			local top = MachineBuilder.build(id, 4)
			T.eq(top:GetAttribute("Level"), 4, id .. " upgrade look")
			T.truthy(top:FindFirstChild("Crystals"), id .. " grows crystals")
		end
	end)
end
