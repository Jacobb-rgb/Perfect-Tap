-- Kit machines (KitMachines.luau): the MachineBuilder contract at every
-- upgrade level, footprints, named moving parts and part budgets.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")

	local CELL = GameConfig.CellSize
	local IDS = { "CleaningStation", "ClayFurnace", "Crusher", "AutoCleaner", "BlastFurnace" }

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

	local function find(model: any, name: string): any
		return model:FindFirstChild(name, true)
	end

	T.test("KitMachines: every level builds with Base, Prompt, Status, Intake and Output", function()
		for _, id in IDS do
			T.truthy(KitMachines.has(id), id)
			for level = 0, KitMachines.MaxLevel do
				local model = KitMachines.build(id, level)
				local tag = id .. " L" .. level
				T.eq(model.PrimaryPart.Name, "Base", tag)
				T.eq(model:GetAttribute("MachineId"), id, tag)
				T.eq(model:GetAttribute("Level"), level, tag)
				for _, name in { "Prompt", "Status", "Intake", "Output" } do
					T.truthy(attachment(model, name), tag .. " " .. name)
				end
				T.eq(typeof(attachment(model, "Intake"):GetAttribute("IntakeSize")), "Vector3", tag)
				for _, part in parts(model) do
					T.truthy(part.Anchored, tag .. " " .. part.Name .. " anchored")
					T.truthy(part:GetAttribute("Kit") ~= nil, tag .. " " .. part.Name .. " has a Kit role")
				end
			end
		end
	end)

	T.test("KitMachines: outputs sit on the shared grid positions (the station uses its tray)", function()
		for _, id in IDS do
			if id ~= "CleaningStation" then
				local model = KitMachines.build(id, 0)
				local expected = Grid.outputLocal(id)
				T.truthy((attachment(model, "Output").CFrame.Position - expected).Magnitude < 1e-4, id)
			end
		end
	end)

	T.test("KitMachines: machine parts stay inside the footprint (chutes may reach the output)", function()
		for _, id in IDS do
			local info = MachineData.ById[id]
			local hw, hd = info.Size[1] * CELL / 2, info.Size[2] * CELL / 2
			local model = KitMachines.build(id, 0)
			for _, part in parts(model) do
				if part.Name ~= "Chute" and part.Name ~= "ChuteLip" and part.Name ~= "Molten" then
					local cf, size = part.CFrame, part.Size
					local r = { cf:GetComponents() }
					local ex = math.abs(r[4]) * size.X / 2 + math.abs(r[5]) * size.Y / 2 + math.abs(r[6]) * size.Z / 2
					local ez = math.abs(r[10]) * size.X / 2 + math.abs(r[11]) * size.Y / 2 + math.abs(r[12]) * size.Z / 2
					local p = cf.Position
					T.truthy(math.abs(p.X) + ex <= hw + 0.35, id .. " " .. part.Name .. " x " .. (math.abs(p.X) + ex))
					T.truthy(math.abs(p.Z) + ez <= hd + 0.35, id .. " " .. part.Name .. " z " .. (math.abs(p.Z) + ez))
				end
			end
		end
	end)

	T.test("KitMachines: named parts for the client effects", function()
		local furnace = KitMachines.build("ClayFurnace", 0)
		T.truthy(find(furnace, "Glow"), "ClayFurnace Glow")
		T.truthy(find(furnace, "ChimneyTop"), "ClayFurnace ChimneyTop")
		local blast = KitMachines.build("BlastFurnace", 0)
		T.truthy(find(blast, "Glow"), "BlastFurnace Glow")
		T.truthy(find(blast, "Molten"), "BlastFurnace Molten")
		local crusher = KitMachines.build("Crusher", 0)
		for _, name in { "Cog1", "Cog2", "Roller1", "Roller2", "Roller1Tooth", "StackGreen" } do
			T.truthy(find(crusher, name), "Crusher " .. name)
		end
		local cleaner = KitMachines.build("AutoCleaner", 0)
		for _, name in { "Drum", "DrumRib", "BedRoller", "WaterPool", "Vent", "StackRed", "StackAmber", "StackGreen" } do
			T.truthy(find(cleaner, name), "AutoCleaner " .. name)
		end
		for _, id in { "AutoCleaner", "CleaningStation" } do
			local model = KitMachines.build(id, 0)
			T.truthy(attachment(model, "WaterOut"), id .. " WaterOut")
			T.truthy(attachment(model, "WaterIn"), id .. " WaterIn")
			T.eq(typeof(attachment(model, "WaterOut"):GetAttribute("Curve")), "number", id .. " Curve")
		end
		local station = KitMachines.build("CleaningStation", 0)
		T.truthy(attachment(station, "OrePoint"), "OrePoint")
		T.truthy(attachment(station, "CamPoint"), "CamPoint")
		T.truthy(find(station, "WaterPool"), "station WaterPool")
	end)

	T.test("KitMachines: crystals grow with the level and the max level turns the body to crystal", function()
		for _, id in IDS do
			local previous = -1
			for level = 0, KitMachines.MaxLevel do
				local model = KitMachines.build(id, level)
				local crystals = 0
				for _, part in parts(model) do
					if part:GetAttribute("Kit") == "Crystal" then
						crystals += 1
					end
				end
				if level == 0 then
					T.eq(crystals, 0, id .. " L0 is plain iron")
				else
					T.truthy(crystals > previous, id .. " L" .. level .. " has more crystals")
				end
				previous = crystals
			end
			local top = KitMachines.build(id, KitMachines.MaxLevel)
			local body = top:FindFirstChild("Body", true)
			if body then
				T.truthy(body.Color ~= KitMachines.Palette.Body, id .. " max level body is crystal coloured")
				T.eq(body.Transparency, 0, id .. " max level body stays opaque (no balls showing through)")
			end
		end
	end)

	T.test("KitMachines: part budgets for phones", function()
		for _, id in IDS do
			local size = MachineData.ById[id].Size
			local big = size[1] * size[2] >= 9 -- the 3x3 Blast Furnace gets more
			local iron = #parts(KitMachines.build(id, 0))
			local crystal = #parts(KitMachines.build(id, KitMachines.MaxLevel))
			T.truthy(iron <= 140, id .. " level 0: " .. iron .. " parts")
			T.truthy(crystal <= (if big then 280 else 240), id .. " max level: " .. crystal .. " parts")
		end
	end)

	T.test("KitMachines: belts keep the game's belt parts and stay light", function()
		local belt = KitMachines.conveyor()
		T.eq(belt.PrimaryPart.Name, "Base")
		for _, name in { "Belt", "RailL", "RailR" } do
			T.truthy(belt:FindFirstChild(name), "belt " .. name)
		end
		T.truthy(belt:FindFirstChild("Belt"):HasTag("ConveyorBelt"), "belt tag")
		local arrows = 0
		for _, part in parts(belt) do
			if part.Name == "Arrow" then
				arrows += 1
			end
		end
		T.eq(arrows, 2, "two arrow wedges")
		-- (15: the owner's detailed belts 2026-10-24, phone lag accepted; was 12)
		T.truthy(#parts(belt) <= 15, "belt parts: " .. #parts(belt))
		T.truthy(attachment(belt, "Prompt"), "belt Prompt")
		local capped = KitMachines.conveyor({ start = { arrow = "right" }, finish = {} })
		T.truthy(capped:FindFirstChild("Beacon", true), "start cap beacon")
		for _, up in { true, false } do
			local slope = KitMachines.slope(up)
			T.truthy(slope:FindFirstChild("Belt"), "slope belt")
			T.truthy(#parts(slope) <= 80, "slope parts: " .. #parts(slope))
		end
	end)

	T.test("KitMachines: every roster machine builds, stays in its footprint and within budget", function()
		T.eq(#KitMachines.Catalog, 24, "the roster has 24 machines")
		local skip = { Chute = true, ChuteLip = true, Molten = true, Blade = true, Cable = true }
		for _, entry in KitMachines.Catalog do
			local id = entry.Id
			local levels = if entry.Upgrades then { 0, KitMachines.MaxLevel } else { 0 }
			for _, level in levels do
				local model = KitMachines.buildAny(id, level)
				local tag = id .. " L" .. level
				T.eq(model.PrimaryPart.Name, "Base", tag)
				T.truthy(attachment(model, "Prompt"), tag .. " Prompt")
				local crystals = 0
				for _, part in parts(model) do
					T.truthy(part:GetAttribute("Kit") ~= nil, tag .. " " .. part.Name .. " has a Kit role")
					if part:GetAttribute("Kit") == "Crystal" then
						crystals += 1
					end
				end
				if level == 0 then
					T.eq(crystals, 0, tag .. " plain")
				else
					T.truthy(crystals > 0, tag .. " grows crystals")
				end
			end
			local size = KitMachines.Sizes[id] or MachineData.ById[id].Size
			local model = KitMachines.buildAny(id, 0)
			local list = parts(model)
			local cells = size[1] * size[2]
			T.truthy(#list <= (if cells >= 6 then 200 else 150), id .. " level 0: " .. #list .. " parts")
			if id ~= "BeltLift" and id ~= "Slide" then
				local hw, hd = size[1] * CELL / 2, size[2] * CELL / 2
				for _, part in list do
					if not skip[part.Name] then
						local cf, sz = part.CFrame, part.Size
						local r = { cf:GetComponents() }
						local ex = math.abs(r[4]) * sz.X / 2 + math.abs(r[5]) * sz.Y / 2 + math.abs(r[6]) * sz.Z / 2
						local ez = math.abs(r[10]) * sz.X / 2 + math.abs(r[11]) * sz.Y / 2 + math.abs(r[12]) * sz.Z / 2
						local p = cf.Position
						T.truthy(math.abs(p.X) + ex <= hw + 0.4, id .. " " .. part.Name .. " x " .. (math.abs(p.X) + ex))
						T.truthy(math.abs(p.Z) + ez <= hd + 0.4, id .. " " .. part.Name .. " z " .. (math.abs(p.Z) + ez))
					end
				end
			end
		end
	end)

	T.test("KitMachines: item machines have an intake, outputs follow the grid rule", function()
		for _, id in { "IronBox", "Polisher", "BrickFurnace", "PlasmaFurnace", "AlloyFurnace", "CrystalExtractor", "SellBox" } do
			local model = KitMachines.build(id, 0)
			T.truthy(attachment(model, "Intake"), id .. " Intake")
			local out = KitMachines.outputFor(id)
			if out then
				T.truthy((attachment(model, "Output").CFrame.Position - out).Magnitude < 1e-4, id .. " Output")
			else
				T.eq(attachment(model, "Output"), nil, id .. " has no output")
			end
		end
	end)
end
