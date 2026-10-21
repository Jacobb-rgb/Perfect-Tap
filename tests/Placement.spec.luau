-- Placement rules, slot limits, the inventory ledger and layout repair.
return function(T, Loader)
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")

	local CELLS = GameConfig.PlotCells

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function deepEqual(a: any, b: any): boolean
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	local function entry(id: string, x: number, z: number, r: number?): any
		return { Id = id, X = x, Z = z, R = r or 0 }
	end

	T.test("Placement: every reason code has a text", function()
		for _, code in
			{
				"NoPlot",
				"TooFar",
				"NotYours",
				"Invalid",
				"UnknownMachine",
				"BadInput",
				"OutOfBounds",
				"Chute",
				"Overlap",
				"NoMachineSlots",
				"NoConveyorSlots",
				"NoneOwned",
				"Busy",
			}
		do
			T.truthy(type(Placement.Reasons[code]) == "string" and #Placement.Reasons[code] > 0, code)
		end
	end)

	T.test("Placement: bounds at every edge for every footprint", function()
		for _, machine in MachineData.List do
			for r = 0, 3 do
				local w, d = Grid.footprint(machine.Id, r)
				for x = -1, CELLS do
					for z = -1, CELLS do
						local fits = x >= 0 and z >= 0 and x + w <= CELLS and z + d <= CELLS
						-- only belts may cover a chute cell (Step3Config.spec has the details)
						local chute = fits and not Placement.fitsUnderDeck(machine.Id) and Placement.chuteUnder(machine.Id, x, z, r) ~= nil
						-- a Belt Lift / Slide needs a platform at its top end (none on an empty plot)
						local edge = fits and not chute and machine.Slope ~= nil
						local ok, code = Placement.validate({}, machine.Id, x, z, r)
						T.eq(ok, fits and not chute and not edge, `{machine.Id} r{r} at {x},{z}`)
						if not fits then
							T.eq(code, "OutOfBounds", `{machine.Id} r{r} at {x},{z} code`)
						elseif chute then
							T.eq(code, "Chute", `{machine.Id} r{r} at {x},{z} code`)
						elseif edge then
							T.eq(code, "DeckEdge", `{machine.Id} r{r} at {x},{z} code`)
						end
						T.eq(Placement.inBounds(machine.Id, x, z, r), fits)
					end
				end
			end
		end
		T.eq(select(2, Placement.validate({}, "StorageCrate", CELLS - 1, 0, 0)), "OutOfBounds", "2x2 at the last X")
		T.eq(select(2, Placement.validate({}, "BlastFurnace", 0, CELLS - 2, 0)), "OutOfBounds", "3x3 two rows from the back")
		T.truthy(Placement.validate({}, "BlastFurnace", CELLS - 3, 0, 0), "3x3 in the far corner")
		local fx = BaseLayout.chuteCell("Foundry")
		T.eq(select(2, Placement.validate({}, "BlastFurnace", fx, CELLS - 3, 0)), "Chute", "3x3 over the Foundry chute")
	end)

	T.test("Placement: unknown machines and bad numbers are refused first", function()
		T.eq(select(2, Placement.validate({}, "Nope", 0, 0, 0)), "UnknownMachine")
		T.eq(select(2, Placement.validate({}, 5 :: any, 0, 0, 0)), "UnknownMachine")
		T.eq(select(2, Placement.validate({}, "Nope", 0 / 0, 0, 0)), "UnknownMachine", "unknown before bad input")
		for _, bad in { { 1.5, 0, 0 }, { 0, 0, 4 }, { 0, 0, -1 }, { 0 / 0, 0, 0 }, { 0, math.huge, 0 }, { 0, 0, 0.5 } } do
			T.eq(select(2, Placement.validate({}, "Conveyor", bad[1], bad[2], bad[3])), "BadInput", `{bad[1]},{bad[2]},{bad[3]}`)
		end
		T.eq(select(2, Placement.validate({}, "Conveyor", "3" :: any, 0, 0)), "BadInput", "string coordinate")
	end)

	T.test("Placement: overlap is detected; a move may overlap its own old cells", function()
		local furnace = entry("ClayFurnace", 4, 4)
		local entries = { furnace }
		T.eq(select(2, Placement.validate(entries, "StorageCrate", 5, 5, 0)), "Overlap")
		T.eq(select(2, Placement.validate(entries, "Conveyor", 4, 5, 0)), "Overlap")
		T.truthy(Placement.validate(entries, "Conveyor", 6, 5, 0), "next to it is free")
		T.truthy(Placement.validate(entries, "ClayFurnace", 5, 4, 1, nil, furnace), "move by one cell")
		T.truthy(Placement.validate(entries, "ClayFurnace", 4, 4, 2, nil, furnace), "turn in place")
		-- unknown ids neither block cells nor count
		local withUnknown = { entry("FutureMachine", 0, 0) }
		T.truthy(Placement.validate(withUnknown, "Conveyor", 0, 0, 0), "unknown entries don't occupy")
		local m, c = Placement.counts(withUnknown)
		T.eq(m, 0)
		T.eq(c, 0)
	end)

	T.test("Placement: slot limits 10/13/16/22 and 40/60", function()
		T.eq(Placement.limits(0, false).Machines, 10)
		T.eq(Placement.limits(1, false).Machines, 13)
		T.eq(Placement.limits(2, false).Machines, 16)
		T.eq(Placement.limits(2, true).Machines, 22)
		T.eq(Placement.limits(9, false).Machines, 16, "only 2 upgrades exist")
		T.eq(Placement.limits(-3, false).Machines, 10)
		T.eq(Placement.limits(0, false).Conveyors, 40)
		T.eq(Placement.limits(0, true).Conveyors, 60)
	end)

	T.test("Placement: belts never use machine slots, a move never fails on slots", function()
		local limits = Placement.limits(0, false)
		local entries = {}
		-- 10 machines (the Sell Chute is 1x1 and takes a machine slot)
		for i = 0, 9 do
			table.insert(entries, entry("SellChute", i, 0))
		end
		local m, c = Placement.counts(entries)
		T.eq(m, 10)
		T.eq(c, 0)
		T.eq(select(2, Placement.validate(entries, "SellChute", 0, 5, 0, limits)), "NoMachineSlots")
		T.eq(select(2, Placement.validate(entries, "CleaningStation", 0, 5, 0, limits)), "NoMachineSlots", "the station counts too")
		T.truthy(Placement.validate(entries, "Conveyor", 0, 5, 0, limits), "belts still fit")
		T.truthy(Placement.validate(entries, "SellChute", 0, 5, 0, nil), "no limits given")
		T.truthy(Placement.validate(entries, "SellChute", 0, 5, 0, limits, entries[1]), "moving ignores slots")
		local data = { PlacedMachines = entries, MachineInventory = {}, Storage = {} }
		T.truthy(Placement.commitMove(data, entries[1], 0, 6, 0), "commitMove at the limit")
		-- 40 belts
		local belts = {}
		for i = 0, 39 do
			table.insert(belts, entry("Conveyor", i % CELLS, 1 + i // CELLS))
		end
		T.eq(select(2, Placement.validate(belts, "Conveyor", 0, 8, 0, limits)), "NoConveyorSlots")
		T.truthy(Placement.validate(belts, "SellChute", 0, 8, 0, limits), "machines still fit")
	end)

	T.test("Placement: StarterKit and StudioDevKit layout fit together", function()
		local entries = {}
		local limits = Placement.limits(0, false)
		local all = {}
		for _, e in MachineData.StarterKit do
			table.insert(all, e)
		end
		local kit = GameConfig.StudioDevKit
		T.truthy(kit, "dev kit configured")
		for _, e in kit.Layout do
			table.insert(all, e)
		end
		for _, e in all do
			local ok, code = Placement.validate(entries, e.Id, e.X, e.Z, e.R, limits)
			T.truthy(ok, `{e.Id} at {e.X},{e.Z}: {code}`)
			table.insert(entries, entry(e.Id, e.X, e.Z, e.R))
		end
		for id, count in kit.Inventory do
			T.truthy(MachineData.ById[id], "dev kit inventory id " .. id)
			T.truthy(count >= 1 and count == math.floor(count), "dev kit count " .. id)
		end
		-- every output pops out onto a free cell on the plot
		local occupied = Placement.occupancy(entries)
		for _, e in entries do
			local ox, oz = Grid.outputCell(e.Id, e.X, e.Z, e.R)
			if ox then
				T.truthy(ox >= 0 and oz >= 0 and ox < CELLS and oz < CELLS, e.Id .. " output on the plot")
				T.eq(occupied[Grid.key(ox, oz)], nil, e.Id .. " output cell is free")
			end
		end
		local data = { PlacedMachines = entries, MachineInventory = {}, Storage = {} }
		T.eq(#Placement.sanitize(data), 0, "nothing displaced")
	end)

	T.test("Placement: clampOrigin keeps every footprint on the plot", function()
		for _, machine in MachineData.List do
			for r = 0, 3 do
				for cx = -2, CELLS + 1 do
					for cz = -2, CELLS + 1 do
						local x, z = Placement.clampOrigin(machine.Id, cx, cz, r)
						T.truthy(Placement.inBounds(machine.Id, x, z, r), `{machine.Id} r{r} cursor {cx},{cz}`)
					end
				end
			end
		end
		-- a 3x2 turned at the far edge is pushed back on
		local x, z = Placement.clampOrigin("CleaningStation", CELLS - 1, CELLS - 1, 1)
		T.eq(x, CELLS - 2)
		T.eq(z, CELLS - 3)
		-- in the open the cursor is the (lower) middle cell
		x, z = Placement.clampOrigin("BlastFurnace", 5, 5, 0)
		T.eq(x, 4)
		T.eq(z, 4)
		x, z = Placement.clampOrigin("Conveyor", 7, 3, 2)
		T.eq(x, 7)
		T.eq(z, 3)
	end)

	T.test("Placement: commits keep placed + inventory constant per id", function()
		local rng = Rng.new(4242)
		local ids = {}
		local data = { PlacedMachines = {}, MachineInventory = {}, Storage = {} }
		for _, machine in MachineData.List do
			table.insert(ids, machine.Id)
			data.MachineInventory[machine.Id] = 3
		end
		local limits = Placement.limits(0, false)
		local function totals(): { [string]: number }
			local t = {}
			for _, id in ids do
				t[id] = data.MachineInventory[id] or 0
			end
			for _, e in data.PlacedMachines do
				t[e.Id] += 1
			end
			return t
		end
		local function check(label: string)
			for _, id in ids do
				T.eq(totals()[id], 3, label .. " total " .. id)
			end
			for id, count in data.MachineInventory do
				T.truthy(count >= 1, label .. " no zero key " .. id)
			end
			-- the layout stays valid: on the plot and no overlaps
			local seen = {}
			for _, e in data.PlacedMachines do
				T.truthy(Placement.inBounds(e.Id, e.X, e.Z, e.R), label .. " in bounds")
				T.truthy(Placement.chuteAllows(e.Id, e.X, e.Z, e.R), label .. " only belts on chutes")
				for _, k in Placement.cells(e.Id, e.X, e.Z, e.R) do
					T.falsy(seen[k], label .. " overlap")
					seen[k] = true
				end
			end
			local m, c = Placement.counts(data.PlacedMachines)
			T.le(m, limits.Machines, label .. " machine slots")
			T.le(c, limits.Conveyors, label .. " belt slots")
		end
		local placedOk, movedOk, pickedOk = 0, 0, 0
		for step = 1, 4000 do
			local op = rng:int(1, 3)
			local before = deepCopy(data)
			local x, z, r = rng:int(-1, CELLS), rng:int(-1, CELLS), rng:int(0, 3)
			local changed = false
			if op == 1 then
				local id = rng:pick(ids)
				local e, code = Placement.commitPlace(data, id, x, z, r, limits)
				changed = e ~= nil
				if e then
					placedOk += 1
					T.eq(data.PlacedMachines[#data.PlacedMachines], e, "appended")
				else
					T.truthy(Placement.Reasons[code], "reason " .. tostring(code))
				end
			elseif op == 2 and #data.PlacedMachines > 0 then
				local e = rng:pick(data.PlacedMachines)
				local ok = Placement.commitMove(data, e, x, z, r)
				changed = ok
				if ok then
					movedOk += 1
				end
			elseif op == 3 and #data.PlacedMachines > 0 then
				local e = rng:pick(data.PlacedMachines)
				T.truthy(Placement.commitPickup(data, e), "pickup")
				T.falsy(Placement.commitPickup(data, e), "second pickup of the same entry")
				changed = true
				pickedOk += 1
			end
			if not changed then
				T.truthy(deepEqual(before, data), `step {step}: a failed commit changed nothing`)
			end
			check("step " .. step)
		end
		T.truthy(placedOk > 50 and movedOk > 50 and pickedOk > 50, `ops ran: {placedOk}/{movedOk}/{pickedOk}`)
		-- no inventory: NoneOwned, nothing changes
		local empty = { PlacedMachines = {}, MachineInventory = {}, Storage = {} }
		local e, code = Placement.commitPlace(empty, "Conveyor", 0, 0, 0, limits)
		T.eq(e, nil)
		T.eq(code, "NoneOwned")
		T.eq(next(empty.MachineInventory), nil)
		-- moving an entry that isn't in the layout
		T.eq(select(2, Placement.commitMove(empty, entry("Conveyor", 0, 0), 1, 1, 0)), "Invalid")
		-- placing the last one removes the key
		local one = { PlacedMachines = {}, MachineInventory = { Conveyor = 1 }, Storage = {} }
		T.truthy(Placement.commitPlace(one, "Conveyor", 0, 0, 0, limits))
		T.eq(one.MachineInventory.Conveyor, nil, "key removed at 0")
	end)

	T.test("Placement: sanitize repairs overlaps and long queues", function()
		local first = entry("ClayFurnace", 4, 4)
		local second = entry("StorageCrate", 5, 5)
		second.In = { { K = "Clean", O = "Copper", G = "Rough" } }
		second.Out = { { K = "Ingot", O = "Iron", G = "Clean" } }
		local unknown = entry("FutureMachine", 4, 4)
		unknown.In = { { K = "Raw", O = "Copper" } }
		local offPlot = entry("Crusher", CELLS - 1, 0)
		local queued = entry("Crusher", 0, 8)
		queued.In = {}
		for i = 1, 6 do
			table.insert(queued.In, { K = "Clean", O = "Copper", G = if i <= 4 then "Rough" else "Flawless" })
		end
		queued.Out = {}
		local data = {
			PlacedMachines = { first, second, unknown, offPlot, queued },
			MachineInventory = { Crusher = 2 },
			Storage = {},
			Coins = 0,
			TotalEarned = 0,
		}
		local list = data.PlacedMachines
		local displaced = Placement.sanitize(data)
		T.eq(#displaced, 2, "two machines displaced")
		T.eq(displaced[1], "StorageCrate")
		T.eq(displaced[2], "Crusher")
		T.eq(data.PlacedMachines, list, "same list table")
		T.eq(#data.PlacedMachines, 3)
		T.eq(data.PlacedMachines[1], first, "first kept")
		T.eq(data.PlacedMachines[2], unknown, "unknown id kept untouched")
		T.eq(#unknown.In, 1)
		T.eq(data.PlacedMachines[3], queued)
		T.eq(data.MachineInventory.StorageCrate, 1)
		T.eq(data.MachineInventory.Crusher, 3)
		T.eq(#queued.In, 4, "In trimmed to 4")
		T.eq(queued.In[4].G, "Rough", "the oldest 4 stay")
		T.eq(queued.Out, nil, "empty Out becomes nil")
		-- 2 from the displaced crate + 2 trimmed
		T.eq(#data.Storage, 4, "spilled to storage")
		T.eq(data.Storage[3].G, "Flawless")
		T.eq(data.Coins, 0)
		-- running it again changes nothing
		local copy = deepCopy(data)
		T.eq(#Placement.sanitize(data), 0)
		T.truthy(deepEqual(copy, data), "idempotent")
	end)

	T.test("Placement: sanitize pays for spills when storage is full", function()
		local storage = {}
		for _ = 1, GameConfig.MaxStoredItems do
			table.insert(storage, { K = "Raw", O = "Copper" })
		end
		local loser = entry("ClayFurnace", 0, 0)
		loser.In = { { K = "Clean", O = "Gold", G = "Pristine" } }
		local data = {
			PlacedMachines = { entry("Crusher", 0, 0), loser },
			MachineInventory = {},
			Storage = storage,
			Coins = 5,
			TotalEarned = 5,
		}
		Placement.sanitize(data)
		local value = ItemData.value("Clean", "Gold", "Pristine")
		T.eq(#data.Storage, GameConfig.MaxStoredItems, "storage stays at the cap")
		T.eq(data.Coins, 5 + value, "paid at full value")
		T.eq(data.TotalEarned, 5 + value)
		T.eq(data.MachineInventory.ClayFurnace, 1)
	end)
end
