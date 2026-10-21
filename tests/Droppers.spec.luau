-- Droppers and the Money Laser (owner 2026-10-21): config, income, machines, models.
return function(T, Loader)
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")

	T.test("droppers: seven, dearer and richer up the list, real ores, resale under the price", function()
		T.eq(#DropperConfig.List, 7)
		local last
		for _, dropper in DropperConfig.List do
			T.truthy(dropper.Resale < dropper.Price, dropper.Id .. " resale")
			if last then
				T.truthy(dropper.Price > last.Price and dropper.Income > last.Income, dropper.Id .. " climbs")
			end
			for _, oreId in dropper.Ores do
				T.truthy(OreData.exists(oreId), dropper.Id .. " ore " .. oreId)
			end
			local hours = DropperConfig.payback(dropper) / 3600
			T.truthy(hours > 0.5 and hours < 6, dropper.Id .. " pays back in 0.5-6 h")
			last = dropper
		end
	end)

	T.test("droppers: income on the plot, every Money Laser doubles one dropper (the best first)", function()
		local basic, gold = DropperConfig.ById.BasicDropper, DropperConfig.ById.GoldDropper
		T.eq(DropperConfig.placedIncome(nil), 0)
		T.eq(DropperConfig.placedIncome({ { Id = "Conveyor" } }), 0)
		T.eq(DropperConfig.placedIncome({ { Id = "BasicDropper" }, { Id = "GoldDropper" } }), basic.Income + gold.Income)
		local laser = DropperConfig.Laser.Id
		T.eq(
			DropperConfig.placedIncome({ { Id = "BasicDropper" }, { Id = "GoldDropper" }, { Id = laser } }),
			basic.Income + gold.Income * 2
		)
		T.eq(
			DropperConfig.placedIncome({ { Id = "BasicDropper" }, { Id = laser }, { Id = laser }, { Id = laser } }),
			basic.Income * 2,
			"spare lasers do nothing"
		)
		T.eq(DropperConfig.placedIncome({ "junk", { Id = 5 } }), 0)
	end)

	T.test("droppers: 2 x 2 machines in the Tech shop with a model, no intake", function()
		for _, id in { "BasicDropper", "DarkMatterDropper", DropperConfig.Laser.Id } do
			local info = MachineData.ById[id]
			T.truthy(info, id .. " is a machine")
			T.eq(info.Size[1], 2)
			T.eq(info.Size[2], 2)
			T.truthy(info.NoIntake)
			T.truthy(EconomyConfig.TechShop.ById[id], id .. " in the Tech shop")
			local model = MachineBuilder.build(id)
			T.truthy(model.PrimaryPart, id .. " base")
			local count = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
				end
			end
			T.truthy(count <= 140, id .. " part budget (" .. count .. ")")
		end
	end)

	T.test("droppers: the State snapshot's income is incomeOf (podiums + droppers), so the HUD chip matches", function()
		local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
		local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
		local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
		local function deepCopy(t: any): any
			if type(t) ~= "table" then
				return t
			end
			local out = {}
			for k, v in t do
				out[k] = deepCopy(v)
			end
			return out
		end
		local data = deepCopy(DataTemplate)
		data.PlacedMachines = { { Id = "BasicDropper", X = 1, Z = 1, R = 0 }, { Id = DropperConfig.Laser.Id, X = 4, Z = 1, R = 0 } }
		local player: any = { UserId = 7701, Name = "Dropper", Parent = true, attributes = {} }
		player.GetAttribute = function(self, key)
			return self.attributes[key]
		end
		local oldGet = rawget(DataService, "get")
		rawset(DataService, "get", function(p)
			return if p == player then data else nil
		end)
		local ok, err = pcall(function()
			local snapshot: any = {}
			PodiumService._test.provide(player, data, snapshot)
			local expected = PodiumService.incomeOf(player, data)
			T.truthy(expected >= DropperConfig.ById.BasicDropper.Income * 2, "the laser doubles the Basic Dropper")
			T.eq(snapshot.Income, expected)
		end)
		rawset(DataService, "get", oldGet)
		assert(ok, err)
	end)

	T.test("droppers: a rebirth takes the placed droppers and lasers away (owner decision pending), other machines stay", function()
		local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
		local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
		local function deepCopy(t: any): any
			if type(t) ~= "table" then
				return t
			end
			local out = {}
			for k, v in t do
				out[k] = deepCopy(v)
			end
			return out
		end
		local data = deepCopy(DataTemplate)
		data.BlasterLevel = 10
		data.PlacedMachines = {
			{ Id = "BasicDropper", X = 1, Z = 1, R = 0 },
			{ Id = "Conveyor", X = 4, Z = 1, R = 0 },
			{ Id = DropperConfig.Laser.Id, X = 6, Z = 1, R = 0 },
			{ Id = "GoldDropper", X = 8, Z = 1, R = 0 },
		}
		RebirthConfig.reset(data)
		T.eq(#data.PlacedMachines, 1)
		T.eq(data.PlacedMachines[1].Id, "Conveyor")
		T.eq(DropperConfig.placedIncome(data.PlacedMachines), 0, "no dropper income left for the new run")
	end)

	T.test("droppers: a plot full of droppers (22 machine slots) stays inside a phone budget", function()
		local most = 0
		for _, id in
			{
				"BasicDropper",
				"BlueDropper",
				"RedDropper",
				"PurpleDropper",
				"GoldDropper",
				"RainbowDropper",
				"DarkMatterDropper",
				DropperConfig.Laser.Id,
			}
		do
			local count = 0
			for _, d in MachineBuilder.build(id):GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
				end
			end
			most = math.max(most, count)
		end
		T.truthy(most * 22 <= 2500, `22 of the biggest ({most} parts) stay under 2500 parts`)
	end)

	T.test("droppers: Grid's outputCell is nil exactly when outputLocal is nil, for every machine", function()
		local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
		for _, machine in MachineData.List do
			local cx = Grid.outputCell(machine.Id, 4, 4, 0)
			T.eq(cx == nil, Grid.outputLocal(machine.Id) == nil, machine.Id)
		end
	end)
end
