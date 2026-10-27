-- MachineService, the step d runtime core, under Lune. Its Roblox-only
-- neighbours (save data, plot lookups, Net, item spawning) are swapped for
-- small fakes for each test and put back afterwards.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local task = require("@lune/task")
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local RunService = Loader.game:GetService("RunService")

	local PLOT = 2
	local USER = 101
	local internals = MachineService._test

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

	local function newData(): any
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		return data
	end

	local function desc(kind: string, grade: string?): any
		return { K = kind, O = "Copper", G = grade or "Rough" }
	end

	-- A fake world around MachineService; restore() puts everything back.
	local function setup(): any
		local w: any = {
			data = {},
			notes = {},
			spawns = {},
			loose = 0,
			studio = false,
			inMemory = false,
			changed = 0,
		}
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.folder = folder
		w.root = { Position = Vector3.zero }
		local character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then { Health = 100 } else nil
			end,
			FindFirstChild = function(_, name: string)
				return if name == "HumanoidRootPart" then w.root else nil
			end,
		}
		w.player = {
			UserId = USER,
			Name = "Tester",
			Parent = true,
			Character = character,
			GetAttribute = function()
				return nil
			end,
		}
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return w.data[p]
		end)
		patch(DataService, "isInMemory", function()
			return w.inMemory
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player then PLOT else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then plotModel else nil
		end)
		patch(Net, "fire", function(name, p, payload)
			table.insert(w.notes, { Name = name, Player = p, Payload = payload })
		end)
		patch(ItemService, "looseCount", function()
			return w.loose
		end)
		patch(ItemService, "spawnDesc", function(d, owner, cf, velocity, serverOwned)
			local record = { Desc = d, Owner = owner, CFrame = cf, Velocity = velocity, ServerOwned = serverOwned }
			table.insert(w.spawns, record)
			return record
		end)
		patch(RunService, "IsStudio", function()
			return w.studio
		end)
		internals.reset()
		w.restore = function()
			internals.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	local function withWorld(name: string, fn: (any) -> ())
		T.test(name, function()
			local w = setup()
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	-- A behaviour that logs every hook; `accept` decides canAccept.
	local function recorder(log: { any }, accept: ((any, any, number, string) -> (boolean, string?))?): any
		return {
			spawned = function(m)
				table.insert(log, { "spawned", m })
			end,
			removed = function(m, reason)
				table.insert(log, { "removed", m, reason })
			end,
			moved = function(m)
				table.insert(log, { "moved", m })
			end,
			canAccept = function(m, d, owner, via)
				if accept then
					return accept(m, d, owner, via)
				end
				return true, nil
			end,
			insert = function(m, d, owner, via)
				table.insert(log, { "insert", m, d, owner, via })
			end,
		}
	end

	-- Lets deferred work (the layout listeners) run. Lune's task.wait() can (rarely)
	-- resume before a deferred thread ran: wait until `check` holds (at most 5 s),
	-- then a few more steps before counting.
	local function settle(check: () -> boolean)
		local since = os.clock()
		repeat
			task.wait()
		until check() or os.clock() - since > 5
		for _ = 1, 3 do
			task.wait()
		end
	end

	-- Waits for the delayed toasts (MachineService TOAST_DELAY 3 s): until 3.1 s
	-- have passed since `since` AND `want` Notify notes arrived, at most 10 s.
	-- (A fixed 3.1 s wait raced the 3 s delay's timer on a loaded machine.)
	local function waitForToasts(w: any, since: number, want: number)
		local function toasts(): number
			local n = 0
			for _, note in w.notes do
				if note.Name == "Notify" then
					n += 1
				end
			end
			return n
		end
		repeat
			task.wait(0.05)
		until (os.clock() - since >= 3.1 and toasts() >= want) or os.clock() - since > 10
	end

	local function count(log: { any }, kind: string): number
		local n = 0
		for _, e in log do
			if e[1] == kind then
				n += 1
			end
		end
		return n
	end

	local function sameCFrame(a: any, b: any, label: string)
		local ac, bc = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do
			T.near(ac[i], bc[i], 1e-4, label .. " component " .. i)
		end
	end

	local function covers(m: any)
		local fw, fd = Grid.footprint(m.Id, m.R)
		for z = m.Z, m.Z + fd - 1 do
			for x = m.X, m.X + fw - 1 do
				T.truthy(MachineService.atCell(PLOT, x, z) == m, `{m.Id} covers {x},{z}`)
			end
		end
	end

	withWorld("MachineService: spawnAll gives the StarterKit once, linked to the save", function(w)
		local data = newData()
		data.StarterKitGiven = false
		w.data[w.player] = data
		local layouts = {}
		MachineService.onLayoutChanged(function(_, plotId)
			table.insert(layouts, plotId)
		end)
		internals.spawnAll(w.player, PLOT)
		T.truthy(data.StarterKitGiven, "kit flag")
		T.eq(#data.PlacedMachines, #MachineData.StarterKit, "kit entries")
		local list = MachineService.ofPlot(PLOT)
		T.eq(#list, #MachineData.StarterKit, "machines")
		for i, m in list do
			T.truthy(m.Entry == data.PlacedMachines[i], "entry is the saved table, in saved order")
			T.eq(m.Model.Parent, w.folder, "parented to the plot")
			T.eq(m.Model:GetAttribute("Owner"), USER, "Owner")
			T.eq(m.Model:GetAttribute("GridX"), m.Entry.X, "GridX")
			T.eq(m.Model:GetAttribute("Status"), "", "Status")
			T.truthy(m.Info == MachineData.ById[m.Id], "Info")
			T.falsy(m.Removed, "Removed")
			sameCFrame(m.Model:GetPivot(), PlotService.footprintCFrame(PLOT, m.Id, m.X, m.Z, m.R), m.Id)
			covers(m)
		end
		T.eq(MachineService.atCell(PLOT, 14, 14), nil, "empty cell")
		T.eq(MachineService.atCell(PLOT, -1, 4), nil, "off the plot")
		T.eq(#MachineService.ofPlot(PLOT + 1), 0, "other plot")
		T.eq(next(data.MachineInventory), nil, "no dev kit outside Studio")
		-- already spawned: nothing happens
		internals.spawnAll(w.player, PLOT)
		T.eq(#MachineService.ofPlot(PLOT), #MachineData.StarterKit, "spawned once")
		settle(function()
			return #layouts >= 1
		end)
		T.eq(#layouts, 1, "layout listeners ran once")
		T.eq(layouts[1], PLOT, "for the plot")
	end)

	withWorld("MachineService: the Studio dev kit only comes with in-memory saves", function(w)
		local kit = GameConfig.StudioDevKit
		T.truthy(kit, "dev kit configured")
		local data = newData()
		data.StarterKitGiven = false
		w.data[w.player] = data
		w.studio, w.inMemory = true, true
		internals.spawnAll(w.player, PLOT)
		local total = #MachineData.StarterKit + #kit.Layout
		T.eq(#data.PlacedMachines, total, "kit + dev layout")
		T.eq(#MachineService.ofPlot(PLOT), total, "all spawned")
		for id, n in kit.Inventory do
			T.eq(data.MachineInventory[id], n, "inventory " .. id)
		end
		-- next session: the kit flag is set, nothing is added again
		internals.reset()
		internals.spawnAll(w.player, PLOT)
		T.eq(#data.PlacedMachines, total, "not added twice")
		-- Studio saving to real DataStores: no dev kit
		internals.reset()
		local live = newData()
		live.StarterKitGiven = false
		w.data[w.player] = live
		w.inMemory = false
		internals.spawnAll(w.player, PLOT)
		T.eq(#live.PlacedMachines, #MachineData.StarterKit, "no dev kit with DataStores")
	end)

	withWorld("MachineService: a broken saved layout is repaired, unknown machines kept", function(w)
		local data = newData()
		data.PlacedMachines = {
			{ Id = "ClayFurnace", X = 0, Z = 0, R = 0, In = { desc("Clean") } },
			{ Id = "Crusher", X = 1, Z = 1, R = 0, Out = { desc("Crushed") } }, -- overlaps the furnace
			{ Id = "FutureMachine", X = 6, Z = 6, R = 0 },
			{ Id = "Anvil", X = GameConfig.PlotCells - 1, Z = 0, R = 0 }, -- sticks out of the plot
		}
		w.data[w.player] = data
		local since = os.clock()
		internals.spawnAll(w.player, PLOT)
		local list = MachineService.ofPlot(PLOT)
		T.eq(#list, 1, "only the furnace spawns")
		T.eq(list[1].Id, "ClayFurnace", "furnace")
		T.eq(#list[1].Entry.In, 1, "its queue is kept")
		T.eq(#data.PlacedMachines, 2, "furnace + the unknown machine stay in the save")
		T.eq(data.PlacedMachines[2].Id, "FutureMachine", "unknown kept")
		T.eq(data.MachineInventory.Crusher, 1, "crusher back in the inventory")
		T.eq(data.MachineInventory.Anvil, 1, "anvil back in the inventory")
		T.eq(#data.Storage, 1, "the crusher's output went to Storage")
		-- one toast, a moment later (the client HUD may still be starting)
		waitForToasts(w, since, 1)
		local toasts = 0
		for _, note in w.notes do
			if note.Name == "Notify" then
				toasts += 1
				T.eq(note.Payload.Text, "2 machines didn't fit and are waiting in your Build menu.", "toast text")
			end
		end
		T.eq(toasts, 1, "one toast")
	end)

	withWorld("MachineService: machines on the new chutes get their own toast", function(w)
		local data = newData()
		local px, pz = BaseLayout.chuteCell("Pen")
		local tx, tz = BaseLayout.chuteCell("Train")
		data.PlacedMachines = {
			{ Id = "Crusher", X = px - 1, Z = pz - 1, R = 0 }, -- covers the PEN chute
			{ Id = "Conveyor", X = tx, Z = tz, R = 0 }, -- belts may stand on a chute
			{ Id = "ClayFurnace", X = GameConfig.PlotCells - 1, Z = 0, R = 0 }, -- sticks out of the plot
		}
		w.data[w.player] = data
		local since = os.clock()
		internals.spawnAll(w.player, PLOT)
		local list = MachineService.ofPlot(PLOT)
		T.eq(#list, 1, "only the belt spawns")
		T.eq(list[1].Id, "Conveyor")
		T.eq(data.MachineInventory.Crusher, 1, "crusher back in the inventory")
		T.eq(data.MachineInventory.ClayFurnace, 1, "furnace back in the inventory")
		waitForToasts(w, since, 2)
		local texts = {}
		for _, note in w.notes do
			if note.Name == "Notify" then
				texts[note.Payload.Text] = true
			end
		end
		T.truthy(texts["Furnace didn't fit and is waiting in your Build menu."], "the usual toast")
		T.truthy(
			texts["A chute now sits where your Crusher stood (only belts can go on it). It is waiting in your Build menu."],
			"the chute toast"
		)
	end)

	withWorld("MachineService: packing up past the inventory cap refunds the machine", function(w)
		local data = newData()
		data.MachineInventory = { Conveyor = 1 }
		data.Coins = 0
		w.data[w.player] = data
		internals.spawnAll(w.player, PLOT)
		local m = MachineService.place(w.player, "Conveyor", 0, 0, 0)
		T.truthy(m, "placed")
		data.MachineInventory.Conveyor = MachineData.MaxInventory -- bought a full stack since
		T.truthy(MachineService.pickup(m), "picked up")
		T.eq(data.MachineInventory.Conveyor, MachineData.MaxInventory, "the stack stays at the cap")
		T.eq(data.Coins, MachineData.ById.Conveyor.Price, "refunded")
		local note = w.notes[#w.notes]
		T.eq(note.Name, "Notify")
		T.truthy(string.find(note.Payload.Text, "refunded", 1, true), "refund toast")
	end)

	withWorld("MachineService: place, move and pickup keep the ledger", function(w)
		local data = newData()
		data.MachineInventory = { ClayFurnace = 2, StorageCrate = 1 }
		w.data[w.player] = data
		internals.spawnAll(w.player, PLOT)
		local log = {}
		MachineService.register("ClayFurnace", recorder(log))
		local m, code = MachineService.place(w.player, "ClayFurnace", 0, 0, 0)
		T.truthy(m, "placed")
		T.eq(code, nil, "no code")
		T.eq(data.MachineInventory.ClayFurnace, 1, "inventory -1")
		T.truthy(data.PlacedMachines[1] == m.Entry, "entry saved")
		T.eq(count(log, "spawned"), 1, "spawned hook")
		sameCFrame(m.Model:GetPivot(), PlotService.footprintCFrame(PLOT, "ClayFurnace", 0, 0, 0), "placed pivot")
		covers(m)
		local _, overlap = MachineService.place(w.player, "ClayFurnace", 1, 1, 0)
		T.eq(overlap, "Overlap", "overlap")
		local _, none = MachineService.place(w.player, "Anvil", 6, 6, 0)
		T.eq(none, "NoneOwned", "not owned")
		local _, outside = MachineService.place(w.player, "ClayFurnace", GameConfig.PlotCells - 1, 0, 0)
		T.eq(outside, "OutOfBounds", "out of bounds")
		T.eq(data.MachineInventory.ClayFurnace, 1, "failed places change nothing")
		T.eq(#data.PlacedMachines, 1, "still one placed")

		-- move: the same entry table changes in place
		local entry = m.Entry
		local ok = MachineService.move(m, 6, 6, 1)
		T.truthy(ok, "moved")
		T.truthy(m.Entry == entry, "same entry")
		T.eq(entry.X, 6, "entry X")
		T.eq(entry.R, 1, "entry R")
		T.eq(m.X, 6, "m.X")
		T.eq(m.Model:GetAttribute("Rotation"), 1, "Rotation attribute")
		T.eq(MachineService.atCell(PLOT, 0, 0), nil, "old cell free")
		covers(m)
		sameCFrame(m.Model:GetPivot(), PlotService.footprintCFrame(PLOT, "ClayFurnace", 6, 6, 1), "moved pivot")
		T.eq(count(log, "moved"), 1, "moved hook")
		local _, blocked = MachineService.move(m, GameConfig.PlotCells - 1, GameConfig.PlotCells - 1, 0)
		T.eq(blocked, "OutOfBounds", "bad move")
		T.eq(entry.X, 6, "a failed move changes nothing")

		-- busy machines can't be moved or packed up
		m.Model:SetAttribute("Busy", true)
		local _, busyMove = MachineService.move(m, 0, 0, 0)
		local _, busyPick = MachineService.pickup(m)
		T.eq(busyMove, "Busy", "busy move")
		T.eq(busyPick, "Busy", "busy pickup")
		m.Model:SetAttribute("Busy", nil)

		-- pickup: contents go to Storage, the machine back to the inventory
		entry.In = { desc("Clean", "Clean") }
		entry.Out = { desc("Ingot") }
		T.truthy(MachineService.pickup(m), "picked up")
		T.truthy(m.Removed, "removed")
		T.eq(#data.Storage, 2, "contents stored")
		T.eq(data.Storage[1].K, "Clean", "In first")
		T.eq(data.MachineInventory.ClayFurnace, 2, "inventory +1")
		T.eq(#data.PlacedMachines, 0, "entry gone")
		T.eq(entry.In, nil, "drained")
		T.eq(MachineService.atCell(PLOT, 6, 6), nil, "cell free")
		local removed = log[#log]
		T.eq(removed[1], "removed", "removed hook")
		T.eq(removed[3], "Pickup", "reason")
		local note = w.notes[#w.notes]
		T.eq(note.Name, "Notify", "toast")
		T.eq(note.Payload.Text, "2 items from your Furnace went to your Ore Pen.", "toast text")
		local _, again = MachineService.pickup(m)
		T.eq(again, "Invalid", "can't pick up twice")

		-- a full Ore Pen: packing a machine up is no way past its capacity
		local m2 = MachineService.place(w.player, "ClayFurnace", 0, 0, 0)
		m2.Entry.In = { desc("Clean") }
		local capacity = ItemService.penCapacity(data)
		for _ = #data.Storage + 1, capacity do
			table.insert(data.Storage, desc("Raw"))
		end
		local coins = data.Coins
		local ok, why = MachineService.pickup(m2)
		T.falsy(ok, "refused while its contents don't fit")
		T.eq(why, "PenFull")
		T.falsy(m2.Removed, "still placed")
		T.eq(#m2.Entry.In, 1, "contents kept")
		T.eq(#data.Storage, capacity, "the pen not over its capacity")
		T.eq(data.Coins, coins, "nothing sold behind the player's back")
		-- room again: it packs up
		table.remove(data.Storage)
		T.truthy(MachineService.pickup(m2), "picked up once its contents fit")
		T.eq(#data.Storage, capacity, "contents stored")
		-- an empty machine always packs up, pen full or not
		local m3 = MachineService.place(w.player, "ClayFurnace", 0, 0, 0)
		T.truthy(MachineService.pickup(m3), "an empty machine packs up with a full pen")
	end)

	withWorld("MachineService: random place/move/pickup keep placed + inventory constant", function(w)
		local data = newData()
		local ids = { "ClayFurnace", "Crusher", "StorageCrate", "Conveyor", "BlastFurnace", "SellChute" }
		for _, id in ids do
			data.MachineInventory[id] = 6
		end
		w.data[w.player] = data
		internals.spawnAll(w.player, PLOT)
		local rng = Rng.new(4242)
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
		local start = totals()
		for step = 1, 600 do
			local list = MachineService.ofPlot(PLOT)
			local roll = rng:next()
			if roll < 0.5 or #list == 0 then
				MachineService.place(w.player, rng:pick(ids), rng:int(-1, 12), rng:int(-1, 12), rng:int(0, 3))
			elseif roll < 0.8 then
				local m = rng:pick(list)
				if rng:chance(0.1) then
					m.Model:SetAttribute("Busy", true)
				end
				MachineService.move(m, rng:int(-1, 12), rng:int(-1, 12), rng:int(0, 3))
				m.Model:SetAttribute("Busy", nil)
			else
				MachineService.pickup(rng:pick(list))
			end
			local now = totals()
			for _, id in ids do
				T.eq(now[id], start[id], `step {step}: {id} total`)
				T.truthy(data.MachineInventory[id] ~= 0, "no zero keys")
			end
			-- the runtime index matches the save exactly
			list = MachineService.ofPlot(PLOT)
			T.eq(#list, #data.PlacedMachines, "machines = entries")
			local occupied = Placement.occupancy(data.PlacedMachines)
			for i, m in list do
				T.truthy(m.Entry == data.PlacedMachines[i], "saved order")
				T.eq(m.X, m.Entry.X, "X in sync")
				T.eq(m.R, m.Entry.R, "R in sync")
			end
			for z = 0, GameConfig.PlotCells - 1 do
				for x = 0, GameConfig.PlotCells - 1 do
					local m = MachineService.atCell(PLOT, x, z)
					local e = occupied[Grid.key(x, z)]
					T.truthy((m and m.Entry) == e, `cell {x},{z}`)
				end
			end
		end
	end)

	withWorld("MachineService: outputs go straight into the machine in front", function(w)
		local data = newData()
		data.MachineInventory = { ClayFurnace = 3, StorageCrate = 1 }
		w.data[w.player] = data
		internals.spawnAll(w.player, PLOT)
		local furnaceLog, crateLog = {}, {}
		local crateAnswer: any = { true, nil }
		MachineService.register("ClayFurnace", recorder(furnaceLog))
		MachineService.register(
			"StorageCrate",
			recorder(crateLog, function()
				return crateAnswer[1], crateAnswer[2]
			end)
		)
		local a = MachineService.place(w.player, "ClayFurnace", 4, 4, 0)
		local ox, oz = Grid.outputCell("ClayFurnace", 4, 4, 0)
		T.eq(ox, 5, "right front cell x")
		T.eq(oz, 3, "right front cell z")

		-- a crate in the output cell takes it (crates take every side)
		local crate = MachineService.place(w.player, "StorageCrate", 5, 2, 0)
		T.truthy(crate, "crate placed")
		local ingot = desc("Ingot")
		local result = MachineService.emit(a, ingot)
		T.eq(result, "Handed", "handed to the crate")
		local last = crateLog[#crateLog]
		T.truthy(last[1] == "insert" and last[3] == ingot and last[4] == USER and last[5] == "Machine", "crate insert")
		crateAnswer = { false, "Full" }
		T.eq(MachineService.emit(a, ingot), "Blocked", "crate full")
		T.eq(a.Model:GetAttribute("Status"), "OutputBlocked", "status")
		T.eq(#w.spawns, 0, "nothing spawned")
		MachineService.pickup(crate)

		-- a furnace facing back at it (front to front) doesn't take it: it pops out
		local b = MachineService.place(w.player, "ClayFurnace", 5, 2, 2)
		T.truthy(b, "facing furnace placed")
		T.eq(MachineService.emit(a, ingot), "Spawned", "spawned instead")
		local spawned = w.spawns[#w.spawns]
		T.truthy(spawned.Desc == ingot, "same item")
		T.eq(spawned.Owner, USER, "owned by the machine owner")
		T.truthy(spawned.ServerOwned, "server keeps output physics")
		local look = a.Model:GetPivot().LookVector
		T.near(
			(spawned.Velocity - (look * GameConfig.OutputPop.Forward + Vector3.new(0, GameConfig.OutputPop.Up, 0))).Magnitude,
			0,
			1e-4,
			"pop velocity"
		)
		local plotId, localPos = PlotService.plotAt(spawned.CFrame.Position)
		T.eq(plotId, PLOT, "spawned on the plot")
		local sx, sz = Grid.cellFromLocal(localPos)
		T.eq(sx, ox, "spawned over the output cell x")
		T.eq(sz, oz, "spawned over the output cell z")

		-- turned around, its back faces the output: handed over
		T.truthy(MachineService.move(b, 5, 2, 0), "turn it")
		local before = count(furnaceLog, "insert")
		T.eq(MachineService.emit(a, ingot), "Handed", "into its back")
		local handed = furnaceLog[#furnaceLog]
		T.eq(count(furnaceLog, "insert"), before + 1, "inserted once")
		T.truthy(handed[2] == b, "into the other furnace")

		-- nothing in front: too many loose items pauses output
		MachineService.pickup(b)
		w.loose = GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom
		local spawns = #w.spawns
		T.eq(MachineService.emit(a, ingot), "Blocked", "loose cap")
		T.eq(a.Model:GetAttribute("Status"), "TooManyItems", "status")
		T.eq(#w.spawns, spawns, "nothing spawned")
		w.loose -= 1
		T.eq(MachineService.emit(a, ingot), "Spawned", "under the cap")
	end)

	withWorld("MachineService: the tick sends outputs one per tick and backs off when blocked", function(w)
		local data = newData()
		data.MachineInventory = { ClayFurnace = 1 }
		w.data[w.player] = data
		internals.spawnAll(w.player, PLOT)
		local ticks = 0
		MachineService.register("ClayFurnace", {
			tick = function(_, now)
				ticks += 1
				T.truthy(type(now) == "number", "tick gets the time")
			end,
		})
		MachineService.register("ClayFurnace", {
			tick = function()
				error("broken behaviour")
			end,
		})
		local m = MachineService.place(w.player, "ClayFurnace", 4, 4, 0)
		m.Entry.Out = { desc("Ingot"), desc("Ingot", "Clean") }
		internals.tick()
		T.eq(ticks, 1, "behaviour tick ran")
		T.eq(#w.spawns, 1, "one item out")
		T.eq(#m.Entry.Out, 1, "one left")
		T.eq(m.Model:GetAttribute("OutCount"), 1, "OutCount")
		internals.tick()
		T.eq(#w.spawns, 2, "the next one a tick later")
		T.eq(w.spawns[2].Desc.G, "Clean", "in order")
		T.eq(m.Entry.Out, nil, "empty Out is nil")
		T.eq(m.Model:GetAttribute("OutCount"), 0, "OutCount 0")

		-- blocked: wait OutputRetry before trying again
		m.Entry.Out = { desc("Ingot") }
		w.loose = GameConfig.MaxLooseItemsPerPlayer
		internals.tick()
		T.eq(m.Model:GetAttribute("Status"), "TooManyItems", "blocked")
		w.loose = 0
		internals.tick()
		T.eq(#w.spawns, 2, "waits before retrying")
		m.State.NextEmit = 0
		internals.tick()
		T.eq(#w.spawns, 3, "retried")
		T.eq(m.Model:GetAttribute("Status"), "", "status cleared")

		-- junk from a damaged save is dropped instead of jamming the machine
		m.Entry.Out = { { K = "Bogus", O = "Copper" }, desc("Ingot") }
		internals.tick()
		T.eq(#w.spawns, 3, "junk not spawned")
		T.eq(#m.Entry.Out, 1, "junk dropped")
		internals.tick()
		T.eq(#w.spawns, 4, "the good item follows")
	end)

	withWorld("MachineService: items go in through canAccept and insert", function(w)
		local data = newData()
		data.MachineInventory = { ClayFurnace = 1, Crusher = 1, StorageCrate = 1, Conveyor = 1 }
		w.data[w.player] = data
		internals.spawnAll(w.player, PLOT)
		local log = {}
		local asked = 0
		local answer: any = { true, nil }
		MachineService.register(
			"ClayFurnace",
			recorder(log, function()
				asked += 1
				return answer[1], answer[2]
			end)
		)
		MachineService.register("Crusher", {
			canAccept = function()
				error("broken canAccept")
			end,
			insert = function() end,
		})
		MachineService.register("StorageCrate", {
			canAccept = function()
				return true, nil
			end,
			insert = function()
				error("broken insert")
			end,
		})
		local furnace = MachineService.place(w.player, "ClayFurnace", 0, 0, 0)
		local crusher = MachineService.place(w.player, "Crusher", 4, 0, 0)
		local crate = MachineService.place(w.player, "StorageCrate", 8, 0, 0)
		local belt = MachineService.place(w.player, "Conveyor", 0, 6, 0)
		T.truthy(furnace and crusher and crate and belt, "all placed")
		T.truthy(MachineService.hasIntake(furnace), "furnace takes items")
		T.falsy(MachineService.hasIntake(belt), "belts don't")

		local ok, reason = MachineService.canAccept(belt, desc("Clean"), USER, "Drop")
		T.falsy(ok, "no intake")
		T.eq(reason, "Wrong", "no intake reason")
		ok, reason = MachineService.canAccept(furnace, { K = "Bogus", O = "Copper" }, USER, "Drop")
		T.eq(reason, "Wrong", "junk item")
		T.eq(asked, 0, "junk never reaches the behaviour")
		answer = { false, nil }
		ok, reason = MachineService.canAccept(furnace, desc("Clean"), USER, "Drop")
		T.eq(reason, "Wrong", "refusal without a reason")
		answer = { false, "Full" }
		ok, reason = MachineService.canAccept(furnace, desc("Clean"), USER, "Drop")
		T.eq(reason, "Full", "reason passed on")
		ok, reason = MachineService.canAccept(crusher, desc("Clean"), USER, "Drop")
		T.falsy(ok, "broken canAccept refuses")
		T.eq(reason, "Busy", "and the item waits")

		-- descriptors
		answer = { true, nil }
		local d = desc("Clean", "Pristine")
		T.truthy(MachineService.insertDesc(furnace, d, USER, "Machine"), "insertDesc")
		local last = log[#log]
		T.truthy(last[1] == "insert" and last[3] == d and last[4] == USER and last[5] == "Machine", "insert hook args")
		local spawns = #w.spawns
		T.truthy(MachineService.insertDesc(crate, d, USER, "Belt"), "taken even though insert broke")
		T.eq(#w.spawns, spawns + 1, "the item came back out instead of vanishing")
		T.truthy(w.spawns[#w.spawns].Desc == d, "same item")

		-- physical items: absorbed only when accepted
		local function record(kind: string): any
			local model = Instance.new("Model")
			local body = Instance.new("Part")
			body.Name = "Body"
			body.Parent = model
			model.PrimaryPart = body
			return {
				Id = "item-" .. kind,
				Model = model,
				Body = body,
				Kind = kind,
				OreId = "Copper",
				Grade = "Clean",
				Owner = USER,
				State = "Loose",
			}
		end
		local item = record("Clean")
		T.truthy(MachineService.insertRecord(furnace, item, "Drop"), "insertRecord")
		T.eq(item.State, "Consumed", "absorbed")
		last = log[#log]
		T.truthy(last[3].K == "Clean" and last[3].G == "Clean" and last[5] == "Drop", "inserted as a descriptor")
		local _, consumed = MachineService.insertRecord(furnace, item, "Drop")
		T.eq(consumed, "Busy", "a consumed item can't go in twice")
		answer = { false, "Wrong" }
		local raw = record("Raw")
		local refused, why = MachineService.insertRecord(furnace, raw, "Drop")
		T.falsy(refused, "refused")
		T.eq(why, "Wrong", "why")
		T.eq(raw.State, "Loose", "a refused item stays in the world")

		-- finished items queue in Out
		MachineService.pushOut(crusher, desc("Crushed"))
		T.eq(#crusher.Entry.Out, 1, "pushOut")
		T.eq(crusher.Model:GetAttribute("OutCount"), 1, "OutCount")
		MachineService.pickup(crusher)
		local stored = #data.Storage
		MachineService.pushOut(crusher, desc("Crushed"))
		T.eq(#data.Storage, stored + 1, "pushOut after pickup goes to Storage")

		-- packed-up machines take nothing
		MachineService.pickup(furnace)
		answer = { true, nil }
		local _, gone = MachineService.canAccept(furnace, desc("Clean"), USER, "Drop")
		T.eq(gone, "Busy", "removed machine")
	end)

	withWorld("MachineService: register catches up with machines already placed", function(w)
		w.data[w.player] = (function()
			local data = newData()
			data.StarterKitGiven = false
			return data
		end)()
		local layouts = 0
		MachineService.onLayoutChanged(function()
			layouts += 1
		end)
		internals.spawnAll(w.player, PLOT)
		settle(function()
			return layouts >= 1
		end)
		T.eq(layouts, 1, "spawn layout")
		local seen = {}
		MachineService.register("Crusher", {
			spawned = function(m)
				table.insert(seen, m)
			end,
		})
		T.eq(#seen, 1, "the StarterKit Crusher got the spawned hook")
		T.eq(seen[1].Id, "Crusher", "crusher")
		settle(function()
			return layouts >= 2
		end)
		T.eq(layouts, 2, "the plot's layout listeners ran again")
	end)

	withWorld("MachineService: MachineAction only reaches your own machine, up close", function(w)
		local data = newData()
		data.MachineInventory = { ClayFurnace = 1 }
		w.data[w.player] = data
		internals.spawnAll(w.player, PLOT)
		local calls = {}
		MachineService.onAction("Poke", function(p, m, arg)
			table.insert(calls, { p, m, arg })
		end)
		local m = MachineService.place(w.player, "ClayFurnace", 4, 4, 0)
		local pivot = m.Model:GetPivot().Position
		w.root.Position = pivot + Vector3.new(0, 0, GameConfig.MachineUseRange - 1)
		internals.action(w.player, m.Model, "Poke", { 1 })
		T.eq(#calls, 1, "handled")
		T.truthy(calls[1][1] == w.player and calls[1][2] == m and calls[1][3][1] == 1, "handler args")
		internals.action(w.player, m.Model, "Unknown", nil)
		internals.action(w.player, m.Model, string.rep("x", 25), nil)
		internals.action(w.player, m.Model.PrimaryPart, "Poke", nil)
		internals.action(w.player, "not a model", "Poke", nil)
		local stranger = { UserId = 7, Name = "Stranger", Parent = true, Character = w.player.Character }
		internals.action(stranger, m.Model, "Poke", nil)
		w.root.Position = pivot + Vector3.new(0, 0, GameConfig.MachineUseRange + 1)
		internals.action(w.player, m.Model, "Poke", nil)
		T.eq(#calls, 1, "everything else is ignored")
	end)
end
