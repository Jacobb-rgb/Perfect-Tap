-- Save size guard (docs/SAVE_AUDIT.md #11): a save filled to every cap the
-- game enforces, written the way ProfileStore writes it (JSON with the lock),
-- stays far under Roblox's 4 MB per key. Measured on 2026-10-18: ~120 KB.
-- When a feature adds a record to the save, add its maxed form here.
return function(T, Loader)
	local serde = require("@lune/serde")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")

	T.Limit = 256 * 1024 -- 2x headroom over today's maxed save; Roblox's hard limit is 4 MB

	-- The longest strings a save can hold for an item (the longest ore id and grade, a recipe).
	local function longestOre(): string
		local best = ""
		for id in OreData.ById do
			if #id > #best then
				best = id
			end
		end
		return best
	end

	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")

	local function maxedSave(): { [string]: any }
		local d = ProfileStore.deepCopy(DataTemplate)
		local ore = longestOre()
		local function item(): { [string]: any }
			return { K = "Clean", O = ore, G = "Pristine", R = "RecipeNameLong" }
		end
		for _ = 1, GameConfig.MaxStoredItems do
			table.insert(d.Storage, item())
		end
		local side = GameConfig.PlotCells
		local cells = side * side
		for i = 1, cells do
			local queueIn, queueOut = {}, {}
			for _ = 1, 4 do
				table.insert(queueIn, item())
				table.insert(queueOut, item())
			end
			table.insert(
				d.PlacedMachines,
				{ Id = "CrystalExtractor", X = i % side, Z = i // side, R = 3, In = queueIn, Out = queueOut, C = "Legendary" }
			)
		end
		for id in MachineData.ById do
			d.MachineInventory[id] = MachineData.MaxInventory
			d.MachineUpgrades[id] = { Speed = 99, Quality = 99 }
		end
		for _ = 1, GameConfig.MaxFoundryStock do
			table.insert(d.Foundry.Stock, { K = "Ingot", O = ore, G = "Pristine" })
		end
		for _ = 1, TrainConfig.MaxCargoSaved do
			table.insert(d.Train.Cargo, item())
		end
		for id in OreData.ById do
			d.Discovered[id] = true
			d.KeepList[id] = true
		end
		-- the newest 100 receipt ids plus a busy month (younger ids are never trimmed)
		for i = 1, 200 do
			d.Purchases[`1234567890123_{i}_abcdefabcdefabcdefabcdef`] = 1760000000 + i
		end
		d.ForgeName = string.rep("W", 30)
		-- rebirth: every Star Shop perk at its top
		d.Rebirths, d.Stars = 999, 99999
		for _, perk in RebirthConfig.Perks do
			d.StarPerks[perk.Id] = #perk.Costs
		end
		return d
	end

	T.test("SaveSize: a save at every cap stays far under the DataStore limit", function()
		local data = maxedSave()
		T.truthy(ProfileStore.storable(data), "the maxed save is storable")
		local record = {
			Data = data,
			Lock = { JobId = string.rep("0", 36), SessionId = string.rep("0", 36) .. "#999#1760000000", Time = 1760000000 },
			Saved = 1760000000,
		}
		local bytes = #serde.encode("json", record)
		print(`  [SaveSize] maxed save: {math.floor(bytes / 1024)} KB of {math.floor(T.Limit / 1024)} KB allowed (Roblox: 4096 KB)`)
		T.le(bytes, T.Limit, "maxed save bytes")
	end)
end
