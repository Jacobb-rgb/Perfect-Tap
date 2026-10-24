-- The MachineService tick's active list (SERVER_PERF_AUDIT #6), the packed
-- Job attribute (#7), the Status debounce (#7) and the loose count per pass
-- (#4), counted with MachineService._test.stats(). Real MachineService,
-- ProcessingService and LogisticsService; save data, plots, Net and item
-- spawning are small fakes per test.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local ProcessingService = Loader.requirePath("ServerScriptService.Server.Services.ProcessingService")
	local LogisticsService = Loader.requirePath("ServerScriptService.Server.Services.LogisticsService")
	local MachineBillboard = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineBillboard")
	local Workspace = Loader.game:GetService("Workspace")

	local PLOT = 4
	local USER = 401
	local CAP = GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom
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

	local function item(kind: string, ore: string?, grade: string?): any
		return { K = kind, O = ore or "Copper", G = grade or "Rough" }
	end

	local function setup(): any
		local w: any = { notes = {}, spawns = {}, loose = 0, looseCalls = 0, changed = 0, serverNow = 1000 }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.player = {
			UserId = USER,
			Name = "Ticker",
			Parent = true,
			GetAttribute = function()
				return nil
			end,
		}
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { Conveyor = 60, ClayFurnace = 6, Crusher = 2, AutoCleaner = 2, RobotArm = 2, SellBox = 2 }
		w.data = data
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		w.patch = patch
		patch(DataService, "get", function(p)
			return if p == w.player then data else nil
		end)
		patch(DataService, "isInMemory", function()
			return false
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
			w.looseCalls += 1
			return w.loose
		end)
		patch(ItemService, "spawnDesc", function(d, owner, cf, velocity, serverOwned)
			local record = { Desc = d, Owner = owner, CFrame = cf, Velocity = velocity, ServerOwned = serverOwned }
			table.insert(w.spawns, record)
			return record
		end)
		patch(Workspace, "GetServerTimeNow", function()
			return w.serverNow
		end)
		patch(MachineService, "speedFactor", function()
			return 1
		end)
		internals.reset()
		ProcessingService._test.reset()
		ProcessingService.init()
		LogisticsService.init()
		-- belts as ConveyorService registers them: no tick hook, no intake
		w.beltHooks = 0
		MachineService.register("Conveyor", {
			spawned = function()
				w.beltHooks += 1
			end,
		})
		internals.spawnAll(w.player, PLOT)
		w.restore = function()
			internals.reset()
			ProcessingService._test.reset()
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

	local function place(w: any, id: string, x: number, z: number, r: number?): any
		local m, code = MachineService.place(w.player, id, x, z, r or 0)
		assert(m, `place {id} at {x},{z}: {code}`)
		return m
	end

	local function job(m: any): any
		return MachineBillboard.decodeJob(m.Model:GetAttribute("Job"))
	end

	---------------------------------------------------------------- active list

	withWorld("MachineTick: 40 idle belts and idle processors are never visited, 4 busy furnaces every tick", function(w)
		local belts = 0
		for z = 0, 3 do
			for x = 0, 9 do
				place(w, "Conveyor", x, z, 0)
				belts += 1
			end
		end
		T.eq(belts, 40, "40 belts")
		local busy = {}
		for i = 0, 3 do
			table.insert(busy, place(w, "ClayFurnace", i * 3, 5))
		end
		local idle = { place(w, "Crusher", 0, 9), place(w, "AutoCleaner", 3, 9), place(w, "ClayFurnace", 6, 9) }
		-- the first pass visits every machine that just spawned once, then the idle ones leave
		internals.tick()
		T.eq(internals.activeCount(), 0, "nothing to do: nothing on the list")
		for _, m in busy do
			T.truthy(MachineService.insertDesc(m, item("Crushed"), USER, "Belt"), "fed")
		end
		T.eq(internals.activeCount(), #busy, "an item wakes its furnace")
		local before = internals.stats()
		local ticks = 25
		for _ = 1, ticks do
			internals.tick()
		end
		local after = internals.stats()
		T.eq(after.Visits - before.Visits, #busy * ticks, "only the busy furnaces are visited")
		T.eq(after.Hooks - before.Hooks, #busy * ticks, "only their tick hooks run")
		for _, m in busy do
			T.truthy(job(m).Working, "working")
		end
		for _, m in idle do
			T.falsy(MachineService.isActive(m), m.Id .. " idle: off the list")
			T.eq(job(m).Working, false, m.Id .. " shows idle")
		end
		T.eq(w.beltHooks, 40, "belt behaviours only ran their spawned hook")
	end)

	withWorld("MachineTick: an idle furnace wakes on an insert, works, sends its ingot and sleeps again", function(w)
		local m = place(w, "ClayFurnace", 4, 4)
		internals.tick()
		T.falsy(MachineService.isActive(m), "asleep")
		MachineService.insertDesc(m, item("Crushed", "Iron"), USER, "Hand")
		T.truthy(MachineService.isActive(m), "awake")
		internals.tick()
		T.truthy(m.State.Job, "the job started")
		m.State.Job.EndsAt = 0
		internals.tick()
		T.eq(#w.spawns, 1, "the ingot popped out in the same tick")
		T.eq(m.Entry.Out, nil, "Out empty")
		T.falsy(MachineService.isActive(m), "nothing left to do: asleep")
		local before = internals.stats().Visits
		internals.tick()
		internals.tick()
		T.eq(internals.stats().Visits, before, "not visited while asleep")
		-- pushOut wakes it too
		MachineService.pushOut(m, item("Ingot"))
		T.truthy(MachineService.isActive(m), "pushOut wakes it")
		internals.tick()
		T.eq(#w.spawns, 2, "sent")
	end)

	withWorld("MachineTick: a saved Out on a machine without a tick hook still gets out", function(w)
		internals.reset()
		-- an intake but no tick hook (a stand-in like the Logistics spec's)
		MachineService.register("ClayFurnace", {
			canAccept = function()
				return true, nil
			end,
			insert = function() end,
		})
		w.data.PlacedMachines = { { Id = "ClayFurnace", X = 4, Z = 4, R = 0, Out = { item("Ingot") } } }
		internals.spawnAll(w.player, PLOT)
		internals.tick()
		T.eq(#w.spawns, 1, "the saved ingot left")
		T.eq(internals.activeCount(), 0, "then it sleeps")
	end)

	withWorld("MachineTick: the Robot Arm sleeps with its idle furnace and wakes with it", function(w)
		local furnace = place(w, "ClayFurnace", 4, 6) -- output cell (5, 5)
		local arm = place(w, "RobotArm", 5, 5) -- back (5, 6), front (5, 4)
		local box = place(w, "SellBox", 4, 3) -- covers (5, 4)
		T.eq(MachineService.atCell(PLOT, 5, 4), box, "the Sell Box in front of the arm")
		internals.tick()
		T.eq(internals.activeCount(), 0, "idle line: nothing ticks")
		local coins = w.data.Coins
		MachineService.insertDesc(furnace, item("Crushed", "Copper", "Clean"), USER, "Hand")
		T.truthy(MachineService.isActive(arm), "the arm follows its back machine")
		internals.tick()
		T.truthy(furnace.State.Job, "smelting")
		T.lt(os.clock(), furnace.State.NextEmit, "the arm holds the furnace's output in")
		furnace.State.Job.EndsAt = 0
		internals.tick()
		internals.tick()
		T.eq(#w.spawns, 0, "nothing popped out onto the arm")
		T.lt(coins, w.data.Coins, "the arm handed the ingot to the Sell Box")
		T.eq(arm.Model:GetAttribute("Holding"), "Copper", "the arm shows it")
		-- the show and the sale batches end: everything sleeps
		arm.State.ShowUntil = 0
		box.State.SalePopup.FlushAt = 0
		box.State.SaleToast.FlushAt = 0
		internals.tick()
		internals.tick()
		T.eq(arm.Model:GetAttribute("Holding"), "", "show over")
		T.eq(internals.activeCount(), 0, "all asleep again")
		-- a layout change: the arm looks again (a new version of the plot)
		local version = MachineService.layoutVersion(PLOT)
		MachineService.pickup(box)
		T.lt(version, MachineService.layoutVersion(PLOT), "the layout version went up")
		LogisticsService._test.wakeArms(w.player, PLOT)
		T.truthy(MachineService.isActive(arm), "a layout change wakes the plot's arms")
		internals.tick()
		furnace.State.NextEmit = 0
		MachineService.pushOut(furnace, item("Ingot"))
		internals.tick()
		T.eq(#w.spawns, 1, "no front machine: the arm holds nothing, the ingot pops out")
	end)

	---------------------------------------------------------------- Status debounce

	withWorld("MachineTick: a blocked status stays while every other retry fails, clears once it flows", function(w)
		local m = place(w, "ClayFurnace", 4, 4)
		local writes = 0
		local shown = m.Model:GetAttribute("Status")
		local function watch()
			local s = m.Model:GetAttribute("Status")
			if s ~= shown then
				writes += 1
				shown = s
			end
		end
		m.Entry.Out = { item("Ingot"), item("Ingot"), item("Ingot"), item("Ingot") }
		MachineService.wake(m)
		w.loose = CAP
		internals.tick()
		watch()
		T.eq(shown, "TooManyItems", "blocked: shows at once")
		for _ = 1, 2 do
			-- room for one, then blocked again on the very next try
			w.loose = 0
			m.State.NextEmit = 0
			internals.tick()
			watch()
			T.eq(shown, "TooManyItems", "one got out, more wait: still shown")
			w.loose = CAP
			internals.tick()
			watch()
			T.eq(shown, "TooManyItems", "blocked again")
		end
		T.eq(writes, 1, "one Status write for the whole stutter")
		T.eq(#m.Entry.Out, 2, "two left")
		-- two in a row get out: it flows, the status clears
		w.loose = 0
		m.State.NextEmit = 0
		internals.tick()
		T.eq(m.Model:GetAttribute("Status"), "TooManyItems", "first one out")
		internals.tick()
		T.eq(m.Model:GetAttribute("Status"), "", "the next one too: cleared")
		-- and with nothing left it clears at once
		m.Entry.Out = { item("Ingot") }
		MachineService.wake(m) -- Out set by hand: pushOut would wake it
		w.loose = CAP
		m.State.NextEmit = 0
		internals.tick()
		T.eq(m.Model:GetAttribute("Status"), "TooManyItems", "blocked")
		w.loose = 0
		m.State.NextEmit = 0
		internals.tick()
		T.eq(m.Model:GetAttribute("Status"), "", "drained: cleared at once")
	end)

	---------------------------------------------------------------- loose count per pass

	withWorld("MachineTick: the loose cap is counted once per owner per pass, with what the pass spawned", function(w)
		local furnaces = {}
		for i = 0, 2 do
			local m = place(w, "ClayFurnace", i * 3, 4)
			m.Entry.Out = { item("Ingot") }
			MachineService.wake(m)
			table.insert(furnaces, m)
		end
		w.loose = CAP - 2
		w.looseCalls = 0
		internals.tick()
		T.eq(w.looseCalls, 1, "one count for three emits")
		T.eq(#w.spawns, 2, "two fit under the cap")
		local blocked = 0
		for _, m in furnaces do
			if m.Model:GetAttribute("Status") == "TooManyItems" then
				blocked += 1
			end
		end
		T.eq(blocked, 1, "the third waits: the pass counted its own spawns")
		-- outside a pass (a direct emit) it counts every time
		w.looseCalls = 0
		w.loose = 0
		MachineService.emit(furnaces[1], item("Ingot"))
		MachineService.emit(furnaces[1], item("Ingot"))
		T.eq(w.looseCalls, 2, "direct emits count fresh")
	end)

	---------------------------------------------------------------- the Job attribute

	T.test("MachineTick: the packed Job attribute round-trips through the client's reader", function()
		local idle = MachineBillboard.decodeJob(ProcessingService.jobText(7))
		T.eq(idle.Cycles, 7, "idle cycles")
		T.eq(idle.Working, false, "idle")
		T.eq(idle.Time, 0, "no time")
		local start = 1729250000.1234567
		local seconds = 4 / 0.6
		local running = MachineBillboard.decodeJob(ProcessingService.jobText(12, start, seconds, "Copper"))
		T.eq(running.Cycles, 12, "cycles")
		T.truthy(running.Working, "working")
		T.eq(running.Start, start, "start keeps full precision")
		T.eq(running.Time, seconds, "time keeps full precision")
		T.eq(running.Ore, "Copper", "ore")
		local dirty = MachineBillboard.decodeJob(ProcessingService.jobText(0, 5, 3, ""))
		T.truthy(dirty.Working and dirty.Ore == "", "dirty ore shows no ore")
		for _, junk in { 5, "", "x|y", "1|2|nope|Gold", "3|inf|2|Gold", true } do
			local j = MachineBillboard.decodeJob(junk)
			T.eq(j.Working, false, "junk reads idle: " .. tostring(junk))
			T.truthy(j.Cycles == j.Cycles and j.Time == 0 and j.Ore == "", "junk fields: " .. tostring(junk))
		end
		T.eq(MachineBillboard.decodeJob(nil).Working, false, "no attribute: idle")
		local broken = MachineBillboard.decodeJob("nan|1|1|Gold")
		T.eq(broken.Cycles, 0, "a broken count reads 0")
		T.truthy(broken.Working and broken.Ore == "Gold", "the job itself still reads")
	end)

	withWorld("MachineTick: a chained job writes the Job attribute once; Cycles rides along", function(w)
		local m = place(w, "ClayFurnace", 4, 4)
		for _ = 1, 3 do
			MachineService.insertDesc(m, item("Crushed", "Gold"), USER, "Belt")
		end
		local tick = ProcessingService._test.behaviour.tick
		tick(m, 10)
		local first = m.Model:GetAttribute("Job")
		T.eq(job(m).Cycles, 0, "nothing finished yet")
		T.eq(job(m).Ore, "Gold", "Gold shows")
		tick(m, 12)
		T.eq(m.Model:GetAttribute("Job"), first, "no write while it works")
		tick(m, 16)
		local second = job(m)
		T.eq(second.Cycles, 1, "one finished")
		T.truthy(second.Working, "the next one runs")
		T.eq(second.Start, 1000, "chained from the end of the first (server time)")
		for _, name in { "Working", "WorkStart", "WorkTime", "WorkOre", "Cycles" } do
			T.eq(m.Model:GetAttribute(name), nil, name .. " is no attribute any more")
		end
	end)
end
