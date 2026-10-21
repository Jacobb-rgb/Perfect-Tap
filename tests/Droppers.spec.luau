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
			T.truthy(count <= 240, id .. " part budget (" .. count .. ")")
		end
	end)
end
