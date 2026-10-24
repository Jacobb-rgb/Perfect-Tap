-- Real ore on the belts (owner 2026-10-24): the droppers' Drops, the Money Laser, the Sell Box, caps and saves.
return function(T, Loader)
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local MachineLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineLogic")

	local function drop(id: string, marked: boolean?): any
		return { K = "Drop", O = id, R = if marked then DropperConfig.LaserMark else nil }
	end

	T.test("drops: worth the dropper's Income x DropEvery, twice that after a laser; never a storage key", function()
		local SellService = Loader.requirePath("ServerScriptService.Server.Services.SellService")
		for _, dropper in DropperConfig.List do
			local value = dropper.Income * DropperConfig.DropEvery
			T.eq(DropperConfig.dropValue(dropper.Id), value, dropper.Id)
			T.eq(ItemData.value("Drop", dropper.Id, nil, nil), value)
			T.eq(ItemData.value("Drop", dropper.Id, nil, DropperConfig.LaserMark), value * DropperConfig.Laser.Mult)
			T.eq(SellService.boxPriceOf(drop(dropper.Id)), value, "the Sell Box price")
			T.eq(SellService.boxPriceOf(drop(dropper.Id, true)), value * DropperConfig.Laser.Mult)
			T.eq(SellService.priceOf(drop(dropper.Id)), 0, "Tobin never buys a Drop (counter, SellBin, sell all)")
			T.falsy(ItemData.parseKey(ItemData.storageKey(drop(dropper.Id))), "no pen / summary key")
			T.eq(ItemData.income(drop(dropper.Id)), 0, "nothing on a podium")
		end
		T.eq(SellService.boxPriceOf({ K = "Drop", O = "Diamond" }), 0, "an ore id is no dropper")
		T.eq(SellService.boxPriceOf({ K = "Drop", O = "BasicDropper", R = "X9" }), 0, "a forged mark sells for nothing")
		T.eq(SellService.boxPriceOf({ K = "Drop", O = "BasicDropper", G = "Flawless" }), 0, "no grades on a Drop")
		T.eq(
			SellService.boxPriceOf({ K = "Clean", O = "Diamond", G = "Rough" }),
			SellService.priceOf({ K = "Clean", O = "Diamond", G = "Rough" }),
			"ore: Tobin's price"
		)
	end)

	T.test("drops: a valid Drop is a known dropper with no grade and at most the laser's mark", function()
		T.truthy(MachineLogic.isValidDesc(drop("DarkMatterDropper")))
		T.truthy(MachineLogic.isValidDesc(drop("DarkMatterDropper", true)))
		T.falsy(MachineLogic.isValidDesc({ K = "Drop", O = "NoSuchDropper" }))
		T.falsy(MachineLogic.isValidDesc({ K = "Drop", O = "BasicDropper", G = "Rough" }))
		T.falsy(MachineLogic.isValidDesc({ K = "Drop", O = "BasicDropper", R = "Dagger" }))
		T.eq(ItemData.displayName("Drop", "GoldDropper", nil, nil), "Heaven Drop")
		T.eq(ItemData.displayName("Drop", "GoldDropper", nil, DropperConfig.LaserMark), "Heaven Drop 2X")
	end)

	T.test("drops: only the Money Laser, the Splitter and the owner's Sell Box take them", function()
		local entry = {}
		local laser = DropperConfig.Laser.Id
		T.truthy(MachineLogic.accepts(laser, drop("BasicDropper"), entry, true), "the laser")
		T.truthy(MachineLogic.accepts("SellBox", drop("BasicDropper"), entry, true), "the owner's Sell Box")
		T.truthy(MachineLogic.accepts("Splitter", drop("BasicDropper"), entry, true), "the Splitter")
		local ok, reason = MachineLogic.accepts("SellBox", drop("BasicDropper"), entry, false)
		T.falsy(ok, "another player's Sell Box pays nobody")
		T.eq(reason, "Foreign")
		for _, id in { "Polisher", "BrickFurnace", "Sorter", "IronBox", "CleaningPlant", "Crusher" } do
			local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
			if MachineData.ById[id] then
				T.falsy(MachineLogic.accepts(id, drop("BasicDropper"), {}, true), id .. " refuses a Drop")
			end
		end
		T.falsy(MachineLogic.accepts(laser, { K = "Clean", O = "Diamond", G = "Rough" }, entry, true), "the laser takes Drops only")
	end)

	T.test("drops: the Money Laser doubles a Drop once", function()
		local DropperService = Loader.requirePath("ServerScriptService.Server.Services.DropperService")
		local once = DropperService.lasered(drop("RedDropper"))
		local twice = DropperService.lasered(once)
		T.eq(once.R, DropperConfig.LaserMark)
		T.eq(ItemData.value(twice.K, twice.O, twice.G, twice.R), DropperConfig.dropValue("RedDropper", true), "a second laser adds nothing")
	end)

	T.test("drops: live caps per owner and per server keep the belts and the loose-item room light", function()
		local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
		local DropperService = Loader.requirePath("ServerScriptService.Server.Services.DropperService")
		T.truthy(DropperService.canDrop(0, 0))
		T.falsy(DropperService.canDrop(DropperConfig.MaxLiveDrops, 0), "the owner's cap")
		T.falsy(DropperService.canDrop(0, DropperConfig.MaxLiveDropsServer), "the server's cap")
		T.truthy(
			DropperConfig.MaxLiveDrops <= GameConfig.MaxLooseItemsPerPlayer / 2,
			"Drops never take more than half of a player's loose-item room (their ore factory keeps the rest)"
		)
		T.truthy(DropperConfig.MaxLiveDropsServer <= 8 * DropperConfig.MaxLiveDrops, "the server cap covers 8 plots")
		T.truthy(DropperConfig.DropLife > 0 and DropperConfig.DropEvery >= 2, "a sane pace")
	end)

	T.test("drops: a save never keeps one: a save with Drops in queues and the pen loads clean", function()
		local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
		local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
		local DropperService = Loader.requirePath("ServerScriptService.Server.Services.DropperService")
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
		local function save(): any
			local data = deepCopy(DataTemplate)
			data.Storage = { { K = "Clean", O = "Diamond", G = "Rough" }, drop("BasicDropper") }
			data.PlacedMachines = {
				{ Id = DropperConfig.Laser.Id, X = 2, Z = 2, R = 0, Out = { drop("BasicDropper", true), drop("BlueDropper") } },
				{ Id = "Splitter", X = 4, Z = 2, R = 0, In = { drop("RedDropper"), { K = "Clean", O = "Diamond", G = "Rough" } } },
			}
			return data
		end
		-- on load (any save an autosave caught)
		local data = save()
		local report = Migrations.run(data, 1e9)
		T.eq(#data.Storage, 1, "only the ore stays in the pen")
		T.eq(data.Storage[1].K, "Clean")
		local laserEntry, splitterEntry
		for _, entry in data.PlacedMachines do
			if entry.Id == DropperConfig.Laser.Id then
				laserEntry = entry
			elseif entry.Id == "Splitter" then
				splitterEntry = entry
			end
		end
		T.truthy(laserEntry and splitterEntry, "the machines stay")
		T.eq(laserEntry.Out, nil, "the laser's Drops are gone")
		T.eq(#splitterEntry.In, 1, "the Splitter keeps its ore")
		T.truthy(report.Dropped >= 4, "the Drops are dropped, not moved to the pen")
		-- before a leaving player's last save
		local leaving = save()
		T.eq(DropperService.stripSave(leaving), 4)
		T.eq(#leaving.Storage, 1)
		T.eq(leaving.PlacedMachines[1].Out, nil)
		T.eq(#leaving.PlacedMachines[2].In, 1)
	end)

	T.test("drops: never stored: storeDesc says Lost, the pen refuses it", function()
		local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
		local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
		local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
		local data = { Storage = {} }
		local player: any = { UserId = 7702, Name = "Drops", Parent = true }
		local oldGet = rawget(DataService, "get")
		rawset(DataService, "get", function(p)
			return if p == player then data else nil
		end)
		local ok, err = pcall(function()
			T.eq(ItemService.storeDesc(player, drop("GoldDropper")), "Lost")
			local stored = PenService.store(player, drop("GoldDropper"))
			T.falsy(stored, "the pen refuses a Drop")
			T.eq(#data.Storage, 0)
		end)
		rawset(DataService, "get", oldGet)
		assert(ok, err)
	end)
end
