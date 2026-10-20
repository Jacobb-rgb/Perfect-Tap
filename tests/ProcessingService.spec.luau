-- ProcessingService under Lune: furnaces, Crusher and Auto Cleaner on top
-- of the real MachineService. Roblox-only neighbours (save data, plots,
-- Net, item spawning, server time) are swapped for small fakes for each
-- test and put back afterwards. Job ticks get a fake clock.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local MachineLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineLogic")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local ProcessingService = Loader.requirePath("ServerScriptService.Server.Services.ProcessingService")
	local ShopService = Loader.requirePath("ServerScriptService.Server.Services.ShopService")
	local Workspace = Loader.game:GetService("Workspace")

	local PLOT = 3
	local USER, STRANGER = 301, 302
	local MAX_IN = GameConfig.MachineIntakeQueue
	local MAX_OUT = MachineData.MaxOutBuffer
	local internals = MachineService._test
	local processing = ProcessingService._test

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
		return { K = kind, O = ore or "Copper", G = grade }
	end

	local function setup(): any
		local w: any = { notes = {}, spawns = {}, loose = 0, changed = 0, serverNow = 5000 }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.player = {
			UserId = USER,
			Name = "Smith",
			Parent = true,
			GetAttribute = function()
				return nil
			end,
		}
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { ClayFurnace = 2, BlastFurnace = 1, Crusher = 2, AutoCleaner = 1 }
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
		-- power: full speed unless a test says otherwise (speed modifiers other
		-- services registered never leak into these job times)
		w.speed = 1
		patch(MachineService, "speedFactor", function()
			return w.speed
		end)
		internals.reset()
		processing.reset()
		processing.reseed(12345)
		ProcessingService.init()
		internals.spawnAll(w.player, PLOT)
		w.restore = function()
			internals.reset()
			processing.reset()
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
		assert(m, `place {id}: {code}`)
		return m
	end

	local tick = processing.behaviour.tick
	local MachineBillboard = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineBillboard")
	-- the old job attributes ride in the one packed Job attribute now
	-- (ProcessingService.jobText), read the way the client reads it
	local JOB_FIELDS = { Working = "Working", WorkStart = "Start", WorkTime = "Time", WorkOre = "Ore", Cycles = "Cycles" }
	local function attr(m: any, name: string): any
		local field = JOB_FIELDS[name]
		if field then
			return (MachineBillboard.decodeJob(m.Model:GetAttribute("Job")) :: any)[field]
		end
		return m.Model:GetAttribute(name)
	end
	local function count(list: any): number
		return if list then #list else 0
	end
	-- puts roster machines into the Build menu so the test can place them
	local ROSTER = { "BrickFurnace", "Polisher", "CrystalExtractor", "PlasmaFurnace", "AlloyFurnace" }
	local function stock(w: any, ids: { string })
		for _, id in ids do
			w.data.MachineInventory[id] = (w.data.MachineInventory[id] or 0) + 2
		end
	end

	withWorld("ProcessingService: processors spawn with their attributes and a Put In prompt", function(w)
		for i, id in { "ClayFurnace", "BlastFurnace", "Crusher", "AutoCleaner" } do
			local m = place(w, id, (i - 1) * 3, 0)
			T.eq(attr(m, "Queue"), 0, id .. " Queue")
			T.eq(attr(m, "QueueMax"), MAX_IN, id .. " QueueMax")
			T.eq(attr(m, "OutCount"), 0, id .. " OutCount")
			T.eq(attr(m, "Working"), false, id .. " Working")
			T.eq(attr(m, "Cycles"), 0, id .. " Cycles")
			T.eq(attr(m, "Status"), "", id .. " Status")
			T.truthy(MachineService.hasIntake(m), id .. " takes items")
			local prompt = m.Model.PrimaryPart.Prompt:FindFirstChild("LoadPrompt")
			T.truthy(prompt, id .. " LoadPrompt")
			T.eq(prompt.ActionText, MachineData.ById[id].LoadText, id .. " prompt text")
			T.eq(prompt.UIOffset.Y, 0, id .. " prompt order 0")
		end
		-- a saved queue shows up on spawn
		internals.reset()
		ProcessingService.init()
		w.data.PlacedMachines =
			{ { Id = "ClayFurnace", X = 4, Z = 4, R = 0, In = { item("Clean"), item("Crushed") }, Out = { item("Ingot") } } }
		internals.spawnAll(w.player, PLOT)
		local m = MachineService.ofPlot(PLOT)[1]
		T.eq(attr(m, "Queue"), 2, "saved queue")
		T.eq(attr(m, "OutCount"), 1, "saved output")
	end)

	withWorld("ProcessingService: hand-ins follow the machine rules", function(w)
		local furnace = place(w, "ClayFurnace", 0, 0)
		local cleaner = place(w, "AutoCleaner", 4, 0)
		local ok, reason = MachineService.insertDesc(furnace, item("Raw"), USER, "Drop")
		T.falsy(ok, "raw ore refused by a furnace")
		T.eq(reason, "Wrong", "raw reason")
		ok, reason = MachineService.insertDesc(furnace, item("Clean", "Copper", "Clean"), STRANGER, "Drop")
		T.eq(reason, "Foreign", "someone else's ore")
		T.truthy(MachineService.insertDesc(cleaner, item("Raw"), USER, "Belt"), "raw into the Auto Cleaner")
		local before = w.changed
		for i = 1, MAX_IN do
			T.truthy(
				MachineService.insertDesc(furnace, item(if i % 2 == 0 then "Crushed" else "Clean", "Iron", "Rough"), USER, "Hand"),
				"item " .. i
			)
			T.eq(attr(furnace, "Queue"), i, "Queue " .. i)
		end
		T.eq(w.changed, before + MAX_IN, "every insert marks the save changed")
		ok, reason = MachineService.insertDesc(furnace, item("Clean"), USER, "Drop")
		T.falsy(ok, "5th item")
		T.eq(reason, "Full", "it waits")
		T.eq(#furnace.Entry.In, MAX_IN, "queue capped")
	end)

	withWorld("ProcessingService: a furnace job, Bellows, stats and the first-ingot toast", function(w)
		local m = place(w, "ClayFurnace", 4, 4)
		local seen = {}
		ProcessingService.onProcessed(function(p, id, input, outputs)
			table.insert(seen, { p, id, input, outputs })
		end)
		MachineService.insertDesc(m, item("Clean", "Copper", "Clean"), USER, "Hand")
		MachineService.insertDesc(m, item("Crushed", "Iron", "Pristine"), USER, "Hand")
		tick(m, 100)
		T.eq(attr(m, "Working"), true, "working")
		T.eq(attr(m, "WorkTime"), 6, "Clay Furnace takes 6 s")
		T.eq(attr(m, "WorkOre"), "Copper", "WorkOre")
		T.eq(attr(m, "WorkStart"), 5000, "WorkStart is server time")
		tick(m, 105.9)
		T.eq(#m.Entry.In, 2, "not done yet")
		T.eq(m.Entry.Out, nil, "nothing out yet")
		w.serverNow = 5006.05
		tick(m, 106.05)
		T.eq(#m.Entry.In, 1, "In[1] consumed")
		T.eq(#m.Entry.Out, 1, "one ingot")
		local ingot = m.Entry.Out[1]
		T.truthy(ingot.K == "Ingot" and ingot.O == "Copper" and ingot.G == "Clean", "Copper ingot keeps the grade")
		T.eq(attr(m, "Cycles"), 1, "Cycles")
		T.eq(attr(m, "Queue"), 1, "Queue")
		T.eq(attr(m, "OutCount"), 1, "OutCount")
		T.eq(w.data.Stats.IngotsSmelted, 1, "IngotsSmelted")
		T.eq(#w.notes, 1, "first-ingot toast")
		T.eq(w.notes[1].Name, "Notify", "Notify")
		T.eq(w.notes[1].Payload.Kind, "Reward", "toast kind")
		T.truthy(w.notes[1].Payload.Text:find("first ingot"), "toast text")
		T.eq(#seen, 1, "onProcessed")
		T.truthy(seen[1][1] == w.player and seen[1][2] == "ClayFurnace", "listener args")
		T.eq(seen[1][3].O, "Copper", "listener input")
		T.eq(seen[1][4][1].K, "Ingot", "listener outputs")
		T.falsy(seen[1][4][1] == ingot, "listeners get copies")
		-- the next job is chained from the moment the first ended
		T.eq(attr(m, "Working"), true, "next job started")
		T.eq(attr(m, "WorkOre"), "Iron", "next ore")
		T.near(attr(m, "WorkStart"), 5006, 1e-6, "chained start")
		T.eq(m.State.Job.EndsAt, 112, "ends 6 s after the first ended")
		tick(m, 112)
		T.eq(w.data.Stats.IngotsSmelted, 2, "second ingot")
		T.eq(m.Entry.Out[2].G, "Pristine", "crushed ore keeps its grade too")
		T.eq(#w.notes, 1, "the toast only comes once")
		T.eq(attr(m, "Working"), false, "idle")
		T.eq(m.Entry.In, nil, "empty queue is nil")

		-- Bellows is read when each job starts
		w.data.Upgrades.Bellows = 5
		MachineService.insertDesc(m, item("Clean"), USER, "Hand")
		tick(m, 200)
		T.near(attr(m, "WorkTime"), 3, 1e-9, "Bellows 5 halves the time")
		w.data.Upgrades.Bellows = 0 / 0
		tick(m, 203)
		MachineService.insertDesc(m, item("Clean"), USER, "Hand")
		tick(m, 204)
		T.eq(attr(m, "WorkTime"), 6, "a broken Bellows value counts as 0")
		-- no upgrade makes a job faster than MinProcessTime
		w.patch(MachineData.ById.ClayFurnace, "Time", 0.1)
		tick(m, 210)
		MachineService.insertDesc(m, item("Clean"), USER, "Hand")
		tick(m, 211)
		T.eq(attr(m, "WorkTime"), GameConfig.MinProcessTime, "MinProcessTime")
	end)

	withWorld("ProcessingService: a sorter job (Iron Box) passes items on and counts toward nothing", function(w)
		-- the Iron Box may run on these jobs (WP-CleanerBox); this pins the contract
		MachineService.register("IronBox", processing.behaviour)
		w.data.MachineInventory.IronBox = 1
		local m = place(w, "IronBox", 0, 0)
		local seen = 0
		ProcessingService.onProcessed(function()
			seen += 1
		end)
		local ingot = item("Ingot", "Gold", "Pristine")
		MachineService.insertDesc(m, ingot, USER, "Hand")
		MachineService.insertDesc(m, item("Raw", "Silver"), USER, "Hand")
		tick(m, 10)
		T.eq(attr(m, "WorkTime"), MachineData.ById.IronBox.Time, "a timed job")
		tick(m, 10 + MachineData.ById.IronBox.Time)
		T.eq(#m.Entry.Out, 1, "the ingot waits in Out")
		local out = m.Entry.Out[1]
		T.truthy(out.K == "Ingot" and out.O == "Gold" and out.G == "Pristine", "unchanged")
		tick(m, 10 + 2 * MachineData.ById.IronBox.Time)
		T.eq(#m.Entry.Out, 2)
		T.eq(m.Entry.Out[2].K, "Raw", "dirty ore stays dirty")
		T.eq(m.Entry.In, nil)
		T.eq(attr(m, "Cycles"), 2, "the box still animates its cycles")
		T.eq(w.data.Stats.IngotsSmelted, 0, "passing an ingot on is not smelting")
		T.eq(#w.notes, 0, "no first-ingot toast")
		T.eq(seen, 0, "no onProcessed")
		T.eq((w.data.Discovered or {}).Silver, nil, "nothing discovered")
	end)

	withWorld("ProcessingService: the Crusher makes 2 piles and waits for room in Out", function(w)
		local m = place(w, "Crusher", 0, 0)
		m.Entry.Out = { item("Crushed"), item("Crushed"), item("Crushed") }
		MachineService.insertDesc(m, item("Clean", "Silver", "Flawless"), USER, "Drop")
		tick(m, 10)
		T.eq(attr(m, "WorkTime"), 3, "Crusher takes 3 s")
		tick(m, 13)
		T.eq(#m.Entry.Out, 3, "no room for 2 more")
		T.eq(#m.Entry.In, 1, "the ore stays in")
		T.eq(attr(m, "Status"), "OutputBlocked", "blocked")
		T.eq(attr(m, "Working"), false, "idle while waiting")
		T.eq(attr(m, "Cycles"), 0, "not finished")
		local rolled = m.State.Job.Outputs
		tick(m, 14)
		T.truthy(m.State.Job.Outputs == rolled, "the result is not re-rolled while waiting")
		MachineLogic.popOut(m.Entry)
		tick(m, 15)
		T.eq(#m.Entry.Out, MAX_OUT, "2 piles added")
		T.eq(m.Entry.In, nil, "ore used")
		for i = 3, 4 do
			local pile = m.Entry.Out[i]
			T.truthy(pile.K == "Crushed" and pile.O == "Silver" and pile.G == "Flawless", "pile " .. i)
		end
		T.eq(attr(m, "Cycles"), 1, "Cycles")
		T.eq(attr(m, "OutCount"), MAX_OUT, "OutCount")
		T.eq(w.data.Stats.IngotsSmelted, 0, "crushing is not smelting")

		-- a more specific reason from MachineService is kept
		MachineService.insertDesc(m, item("Clean"), USER, "Drop")
		MachineService.setAttrs(m, { Status = "TooManyItems" })
		tick(m, 20)
		tick(m, 30)
		T.eq(attr(m, "Status"), "TooManyItems", "status kept")
	end)

	withWorld("ProcessingService: the Auto Cleaner rolls Rough or Clean, about 60/40", function(w)
		local m = place(w, "AutoCleaner", 0, 0)
		local grades = {}
		local now = 0
		local jobs = 600
		for _ = 1, jobs do
			T.truthy(MachineService.insertDesc(m, item("Raw", "Gold"), USER, "Belt"), "raw in")
			tick(m, now)
			now += 8
			tick(m, now)
			local out = MachineLogic.popOut(m.Entry)
			T.truthy(out and out.K == "Clean" and out.O == "Gold", "clean gold out")
			grades[out.G] = (grades[out.G] or 0) + 1
		end
		T.eq((grades.Rough or 0) + (grades.Clean or 0), jobs, "only Rough or Clean")
		T.near(grades.Rough / jobs, 0.6, 0.07, "Rough share")
		T.eq(attr(m, "Cycles"), jobs, "Cycles")
		T.eq(w.data.Stats.IngotsSmelted, 0, "no ingots")
	end)

	withWorld("ProcessingService: the Cleaning Plant's Quality level sets its grade odds", function(w)
		local m = place(w, "AutoCleaner", 0, 0)
		local prompt = m.Model.PrimaryPart.Prompt:FindFirstChild("LoadPrompt")
		T.eq(attr(m, "Quality"), 0, "level 0 shown")
		T.eq(attr(m, "QualityOdds"), "60% Rough · 40% Clean", "level 0 odds")
		T.eq(prompt.ObjectText, "Cleaning Plant · Quality 0", "the level on the prompt (the odds are on the billboard)")
		-- the Tech shop writes the level; the plant shows it within a second
		w.data.MachineUpgrades = { AutoCleaner = { Quality = 5 } }
		tick(m, 0.5)
		T.eq(attr(m, "Quality"), 5, "level 5 shown")
		T.eq(attr(m, "QualityOdds"), "20% Clean · 50% Pristine · 30% Flawless", "level 5 odds")
		T.eq(prompt.ObjectText, "Cleaning Plant · Quality 5", "prompt names the level")
		T.truthy(#prompt.ObjectText <= 32, "short enough for a phone's prompt")
		local grades = {}
		local now = 10
		local jobs = 600
		for i = 1, jobs do
			MachineService.insertDesc(m, item("Raw", "Silver"), USER, "Belt")
			tick(m, now)
			if i == 1 then
				T.eq(attr(m, "WorkOre"), "", "dirty ore doesn't show its ore while it is cleaned")
			end
			now += 8
			tick(m, now)
			local out = MachineLogic.popOut(m.Entry)
			T.truthy(out and out.K == "Clean", "clean ore out")
			grades[out.G] = (grades[out.G] or 0) + 1
		end
		T.eq(grades.Rough, nil, "no Rough at level 5")
		T.near((grades.Flawless or 0) / jobs, 0.3, 0.07, "Flawless share")
		T.near((grades.Pristine or 0) / jobs, 0.5, 0.07, "Pristine share")
		-- a broken or too high level counts as the nearest real one
		w.data.MachineUpgrades = { AutoCleaner = { Quality = 99 } }
		tick(m, now + 2)
		T.eq(attr(m, "Quality"), 5, "clamped to what is sold")
		w.data.MachineUpgrades = { AutoCleaner = { Quality = 0 / 0 } }
		tick(m, now + 4)
		T.eq(attr(m, "Quality"), 0, "NaN counts as 0")
		-- the level is read when a job starts
		w.data.MachineUpgrades = { AutoCleaner = { Quality = 0 } }
		MachineService.insertDesc(m, item("Raw", "Silver"), USER, "Belt")
		tick(m, now + 10)
		w.data.MachineUpgrades = { AutoCleaner = { Quality = 5 } }
		T.truthy(m.State.Job.Odds == MachineData.gradeOdds(0), "the running job keeps its odds")
	end)

	withWorld("ProcessingService: Speed upgrades shorten jobs, per machine type", function(w)
		local furnace = place(w, "ClayFurnace", 0, 0)
		local crusher = place(w, "Crusher", 4, 0)
		w.data.MachineUpgrades = { ClayFurnace = { Speed = 2 } }
		MachineService.insertDesc(furnace, item("Clean"), USER, "Hand")
		MachineService.insertDesc(crusher, item("Clean"), USER, "Hand")
		tick(furnace, 1)
		tick(crusher, 1)
		T.near(attr(furnace, "WorkTime"), 6 * MachineData.speedMult(2), 1e-9, "Clay Furnace Speed 2")
		T.eq(attr(crusher, "WorkTime"), 3, "the Crusher has its own level")
		-- Speed and Bellows multiply
		w.data.Upgrades.Bellows = 5
		w.data.MachineUpgrades = { ClayFurnace = { Speed = 5 } }
		T.near(processing.jobTime(furnace), math.max(GameConfig.MinProcessTime, 6 * 0.5 * MachineData.speedMult(5)), 1e-9, "both")
		w.data.MachineUpgrades = { ClayFurnace = "broken" }
		T.near(processing.jobTime(furnace), 3, 1e-9, "a broken record counts as level 0")
	end)

	T.test("ProcessingService: grade odds as text", function()
		T.eq(ProcessingService.oddsText(MachineData.gradeOdds(0)), "60% Rough · 40% Clean")
		T.eq(ProcessingService.oddsText(MachineData.gradeOdds(3)), "15% Rough · 45% Clean · 35% Pristine · 5% Flawless")
		T.eq(ProcessingService.oddsText({ Flawless = 1, Bogus = 2, Rough = 0 / 0 }), "100% Flawless", "unknown and broken entries left out")
		T.eq(ProcessingService.oddsText({}), "")
	end)

	withWorld("ProcessingService: damaged saves don't jam a machine", function(w)
		local m = place(w, "ClayFurnace", 0, 0)
		m.Entry.In = { { K = "Bogus", O = "Copper" }, item("Raw", "Iron"), item("Clean", "Iron", "Rough") }
		tick(m, 0)
		T.eq(#m.Entry.In, 2, "junk dropped")
		T.eq(attr(m, "Queue"), 2, "Queue")
		tick(m, 1)
		T.eq(attr(m, "WorkOre"), "", "the stray raw ore is worked (dirty: no ore shown)")
		tick(m, 7)
		T.eq(#m.Entry.Out, 1, "it comes out")
		T.eq(m.Entry.Out[1].K, "Raw", "unchanged")
		T.eq(attr(m, "Cycles"), 0, "not counted as a job")
		T.eq(w.data.Stats.IngotsSmelted, 0, "no stats")
		tick(m, 13)
		T.eq(m.Entry.Out[2].K, "Ingot", "the real ore smelts")
		T.eq(attr(m, "Cycles"), 1, "Cycles")
		-- the queue changing under a running job restarts it on the new In[1]
		MachineService.insertDesc(m, item("Clean", "Silver"), USER, "Hand")
		tick(m, 20)
		m.Entry.In = { item("Clean", "Gold") }
		tick(m, 21)
		T.eq(attr(m, "WorkOre"), "Gold", "restarted")
		T.eq(m.State.Job.EndsAt, 27, "from scratch")
	end)

	withWorld("ProcessingService: outputs leave through MachineService, straight into the next machine", function(w)
		-- a Crusher whose output cell is the back row of a furnace
		local crusher = place(w, "Crusher", 4, 6)
		local ox, oz = Grid.outputCell("Crusher", 4, 6, 0)
		local furnace = place(w, "ClayFurnace", ox, oz - 1)
		T.eq(MachineService.atCell(PLOT, ox, oz), furnace, "furnace on the output cell")
		MachineService.insertDesc(crusher, item("Clean", "Copper", "Clean"), USER, "Hand")
		internals.tick()
		T.eq(attr(crusher, "Working"), true, "crushing")
		crusher.State.Job.EndsAt = 0
		internals.tick()
		internals.tick()
		T.eq(crusher.Entry.Out, nil, "both piles left")
		T.eq(#w.spawns, 0, "nothing on the floor")
		T.eq(count(furnace.Entry.In), 2, "handed to the furnace")
		T.eq(furnace.Entry.In[1].K, "Crushed", "crushed ore")

		-- the furnace's ingot pops out of its front as a loose item
		furnace.State.Job = nil
		internals.tick()
		furnace.State.Job.EndsAt = 0
		internals.tick()
		T.eq(#w.spawns, 1, "one ingot spawned")
		T.eq(w.spawns[1].Desc.K, "Ingot", "an ingot")
		T.eq(w.spawns[1].Owner, USER, "owned by the machine owner")
		T.eq(attr(furnace, "OutCount"), 0, "OutCount back to 0")
		T.eq(count(furnace.Entry.In), 1, "the second pile is next")
	end)

	withWorld("ProcessingService: items are conserved over random jobs", function(w)
		local rng = Rng.new(777)
		local machines = {
			place(w, "ClayFurnace", 0, 0),
			place(w, "Crusher", 3, 0),
			place(w, "AutoCleaner", 6, 0),
			place(w, "BlastFurnace", 0, 4),
		}
		local feed = {
			ClayFurnace = { "Clean", "Crushed" },
			BlastFurnace = { "Clean", "Crushed" },
			Crusher = { "Clean" },
			AutoCleaner = { "Raw" },
		}
		local ores = { "Copper", "Iron", "Silver", "Gold" }
		local grades = { "Rough", "Clean", "Pristine", "Flawless" }
		local pushed, popped = {}, {}
		local now = 0
		for step = 1, 4000 do
			local m = machines[rng:int(1, #machines)]
			local roll = rng:next()
			if roll < 0.45 then
				local kinds = feed[m.Id]
				local d = item(kinds[rng:int(1, #kinds)], ores[rng:int(1, #ores)], grades[rng:int(1, #grades)])
				if MachineService.insertDesc(m, d, USER, "Drop") then
					pushed[m] = (pushed[m] or 0) + 1
				end
			elseif roll < 0.7 then
				if MachineLogic.popOut(m.Entry) then
					popped[m] = (popped[m] or 0) + 1
				end
			else
				now += rng:range(0, 4)
				for _, x in machines do
					tick(x, now)
				end
			end
			for _, x in machines do
				T.le(count(x.Entry.In), MAX_IN, `In cap at step {step}`)
				T.le(count(x.Entry.Out), MAX_OUT, `Out cap at step {step}`)
			end
		end
		for _, m in machines do
			local done = attr(m, "Cycles")
			local per = MachineData.ById[m.Id].OutputCount
			T.eq(pushed[m] or 0, count(m.Entry.In) + done, m.Id .. ": every item in is queued or used")
			T.eq(done * per, count(m.Entry.Out) + (popped[m] or 0), m.Id .. ": every result is waiting or gone")
			T.eq(attr(m, "Queue"), count(m.Entry.In), m.Id .. " Queue attribute")
			T.truthy(done > 20, m.Id .. " did real work")
			for _, d in m.Entry.Out or {} do
				T.truthy(ItemData.Kinds[d.K] and MachineLogic.isValidDesc(d), m.Id .. " valid output")
			end
		end
	end)

	---------------------------------------------------------------- roster processors

	withWorld("ProcessingService: the roster processors spawn with their attributes and a Put In prompt", function(w)
		stock(w, ROSTER)
		local spots = { { 0, 0 }, { 3, 0 }, { 6, 0 }, { 9, 0 }, { 0, 4 } }
		for i, id in ROSTER do
			local m = place(w, id, spots[i][1], spots[i][2])
			T.eq(attr(m, "Queue"), 0, id .. " Queue")
			T.eq(attr(m, "QueueMax"), MAX_IN, id .. " QueueMax")
			T.eq(attr(m, "Working"), false, id .. " Working")
			T.eq(attr(m, "Status"), "", id .. " Status")
			T.truthy(MachineService.hasIntake(m), id .. " takes items")
			local prompt = m.Model.PrimaryPart.Prompt:FindFirstChild("LoadPrompt")
			T.truthy(prompt, id .. " LoadPrompt")
			T.eq(prompt.ActionText, MachineData.ById[id].LoadText, id .. " prompt text")
		end
	end)

	withWorld("ProcessingService: job time is divided by MachineService.speedFactor (power)", function(w)
		stock(w, { "BrickFurnace" })
		local brick = place(w, "BrickFurnace", 0, 0)
		local clay = place(w, "ClayFurnace", 4, 0)
		MachineService.insertDesc(brick, item("Clean", "Iron", "Pristine"), USER, "Hand")
		tick(brick, 10)
		T.eq(attr(brick, "WorkTime"), 4, "the Brick Furnace takes 4 s at full power")
		tick(brick, 14)
		local ingot = brick.Entry.Out[1]
		T.truthy(ingot.K == "Ingot" and ingot.O == "Iron" and ingot.G == "Pristine", "an iron ingot, same grade")
		-- too little power slows the next job down
		w.speed = 0.6
		MachineService.insertDesc(brick, item("Crushed", "Copper", "Rough"), USER, "Hand")
		tick(brick, 20)
		T.near(attr(brick, "WorkTime"), 4 / 0.6, 1e-9, "60% speed: the job takes longer")
		tick(brick, 24)
		T.eq(count(brick.Entry.Out), 1, "not done after the full-power time")
		tick(brick, 20 + 4 / 0.6 + 1e-6)
		T.eq(count(brick.Entry.Out), 2, "done after the slowed time")
		-- Bellows, Speed and power all multiply
		w.data.MachineUpgrades = { ClayFurnace = { Speed = 2 } }
		w.data.Upgrades.Bellows = 5
		local upgraded = 6 * 0.5 * MachineData.speedMult(2)
		w.speed = 0.5
		T.near(processing.jobTime(clay), upgraded / 0.5, 1e-9, "Bellows, Speed and power")
		w.speed = 20
		T.eq(processing.jobTime(clay), GameConfig.MinProcessTime, "never below MinProcessTime")
		for _, broken in { 0 / 0, 0, -1, math.huge, "fast" } do
			w.speed = broken
			T.near(processing.jobTime(clay), upgraded, 1e-9, `a broken factor ({broken}) counts as 1`)
		end
		w.speed = 1e-9
		T.truthy(processing.jobTime(clay) < math.huge, "a tiny factor never stops a machine")
	end)

	withWorld("ProcessingService: the Plasma Furnace smelts 2 queued items per job", function(w)
		stock(w, { "PlasmaFurnace" })
		local m = place(w, "PlasmaFurnace", 0, 0)
		local seen = {}
		ProcessingService.onProcessed(function(_, id, input, outputs)
			table.insert(seen, { Id = id, Input = input, Outputs = outputs })
		end)
		for _, ore in { "Copper", "Iron", "Gold" } do
			T.truthy(MachineService.insertDesc(m, item("Crushed", ore, "Clean"), USER, "Belt"), ore .. " in")
		end
		tick(m, 10)
		T.eq(attr(m, "WorkTime"), 2.5, "2.5 s")
		T.eq(#m.State.Job.Inputs, 2, "two items in one job")
		T.eq(attr(m, "WorkOre"), "Copper", "In[1] shows")
		tick(m, 12.5)
		T.eq(#m.Entry.Out, 2, "one ingot per item")
		T.eq(m.Entry.Out[1].O .. "," .. m.Entry.Out[2].O, "Copper,Iron", "in queue order")
		for _, out in m.Entry.Out do
			T.truthy(out.K == "Ingot" and out.G == "Clean", "ingots keep the grade")
		end
		T.eq(count(m.Entry.In), 1, "gold waits")
		T.eq(attr(m, "Cycles"), 1, "one job")
		T.eq(w.data.Stats.IngotsSmelted, 2, "both count as smelted")
		T.eq(#seen, 2, "listeners hear each item")
		T.eq(seen[2].Input.O, "Iron", "with its own input")
		T.eq(seen[2].Outputs[1].O, "Iron", "and its own output")
		-- the next job takes what is left, chained from the end of the first
		T.eq(#m.State.Job.Inputs, 1, "gold alone")
		T.eq(m.State.Job.EndsAt, 15, "chained")
		tick(m, 15)
		T.eq(#m.Entry.Out, 3, "gold ingot")
		-- never more results than fit in Out
		for _ = 1, 2 do
			MachineService.insertDesc(m, item("Clean", "Silver", "Rough"), USER, "Belt")
		end
		tick(m, 20)
		T.eq(#m.State.Job.Inputs, 1, "Out holds 3 of 4: only one result fits")
		tick(m, 22.5)
		T.eq(#m.Entry.Out, MAX_OUT, "Out full")
		for _ = 1, MAX_OUT do
			MachineLogic.popOut(m.Entry)
		end
		tick(m, 25)
		for _ = 1, 3 do
			MachineService.insertDesc(m, item("Clean", "Silver", "Rough"), USER, "Belt")
		end
		tick(m, 30)
		T.eq(#m.State.Job.Inputs, 2, "room again: Batch caps it at 2")
		T.eq(count(m.Entry.In), 3, "the items stay queued while worked")
		tick(m, 32.5)
		T.eq(count(m.Entry.In), 1, "both used")
		T.eq(attr(m, "Queue"), 1, "Queue attribute")
	end)

	withWorld("ProcessingService: the Polisher makes about half its ore one grade better", function(w)
		stock(w, { "Polisher" })
		local m = place(w, "Polisher", 0, 0)
		local ok, reason = MachineService.insertDesc(m, item("Raw", "Gold"), USER, "Hand")
		T.falsy(ok, "dirty ore")
		T.eq(reason, "Wrong", "refused")
		local ups, jobs, now = 0, 400, 0
		local better = { Rough = "Clean", Clean = "Pristine" }
		for i = 1, jobs do
			local grade = if i % 2 == 0 then "Rough" else "Clean"
			T.truthy(MachineService.insertDesc(m, item("Clean", "Gold", grade), USER, "Belt"), "clean in")
			tick(m, now)
			now += MachineData.ById.Polisher.Time
			tick(m, now)
			local out = MachineLogic.popOut(m.Entry)
			T.truthy(out and out.K == "Clean" and out.O == "Gold", "clean gold out")
			T.truthy(out.G == grade or out.G == better[grade], `{grade} -> {out.G}`)
			if out.G ~= grade then
				ups += 1
			end
		end
		T.near(ups / jobs, MachineData.ById.Polisher.GradeUpChance, 0.08, "share one grade better")
		for _ = 1, 20 do
			MachineService.insertDesc(m, item("Clean", "Gold", "Flawless"), USER, "Belt")
			tick(m, now)
			now += MachineData.ById.Polisher.Time
			tick(m, now)
			T.eq(MachineLogic.popOut(m.Entry).G, "Flawless", "Flawless stays Flawless")
		end
		-- the Polisher tops out at Pristine: a belt loop never makes Flawless (owner, 2026-10-20)
		for _ = 1, 20 do
			MachineService.insertDesc(m, item("Clean", "Gold", "Pristine"), USER, "Belt")
			tick(m, now)
			now += MachineData.ById.Polisher.Time
			tick(m, now)
			T.eq(MachineLogic.popOut(m.Entry).G, "Pristine", "Pristine stays Pristine")
		end
		T.eq(attr(m, "Cycles"), jobs + 40, "Cycles")
		T.eq(w.data.Stats.IngotsSmelted, 0, "polishing is not smelting")
	end)

	withWorld("ProcessingService: the Crystal Extractor passes crushed ore on and sometimes gives a shard", function(w)
		stock(w, { "CrystalExtractor" })
		local m = place(w, "CrystalExtractor", 0, 0)
		local info = MachineData.ById.CrystalExtractor
		local real = info.ShardChance
		-- every pile here counts as freshly crushed (one roll each; the loop test checks the budget)
		w.data.ShardRolls = ProcessingService.MaxShardRolls
		T.eq(select(2, MachineService.insertDesc(m, item("Clean"), USER, "Hand")), "Wrong", "only crushed ore")
		local now = 0
		-- one whole job; its item is taken out of Out, so Out never fills up
		local function job()
			T.truthy(MachineService.insertDesc(m, item("Crushed", "Iron", "Rough"), USER, "Belt"), "crushed in")
			tick(m, now)
			now += info.Time
			tick(m, now)
			local out = MachineLogic.popOut(m.Entry)
			T.truthy(out and out.K == "Crushed" and out.O == "Iron", "passed through")
		end
		local function toasts(): number
			local n = 0
			for _, note in w.notes do
				if note.Name == "Notify" and note.Payload.Text == "+1 Crystal Shard!" then
					n += 1
				end
			end
			return n
		end
		-- a sure shard: Shards + 1, a toast, the save marked changed
		w.patch(info, "ShardChance", 1)
		w.data.Shards = 0
		MachineService.insertDesc(m, item("Crushed", "Silver", "Pristine"), USER, "Belt")
		tick(m, now)
		T.eq(attr(m, "WorkTime"), info.Time, "a timed job")
		local before = w.changed
		now += info.Time
		tick(m, now)
		local out = MachineLogic.popOut(m.Entry)
		T.truthy(out and out.K == "Crushed" and out.O == "Silver" and out.G == "Pristine", "the same item comes out")
		T.eq(w.data.Shards, 1, "+1 shard")
		T.truthy(w.changed > before, "save marked changed")
		local toast = w.notes[#w.notes]
		T.eq(toast.Name, "Notify", "a toast")
		T.eq(toast.Player, w.player, "to the owner")
		T.eq(toast.Payload.Text, "+1 Crystal Shard!", "toast text")
		T.eq(toast.Payload.Kind, "Reward", "toast kind")
		-- a broken or negative count starts again from 0: never negative
		for _, broken in { -5, 0 / 0, "lots" } do
			w.data.Shards = broken
			job()
			T.eq(w.data.Shards, 1, `from {broken}`)
		end
		-- through Shards.add: never past Shards.Max (an endless count is clamped too)
		local Shards = Loader.requirePath("ServerScriptService.Server.Shards")
		for _, full in { Shards.Max, math.huge } do
			w.data.Shards = full
			job()
			T.eq(w.data.Shards, Shards.Max, `clamped at Shards.Max from {full}`)
		end
		w.data.Shards = 2.7
		job()
		T.eq(w.data.Shards, 3, "whole shards")
		-- no chance: never a shard
		w.patch(info, "ShardChance", 0)
		local shown = toasts()
		for _ = 1, 20 do
			job()
		end
		T.eq(w.data.Shards, 3, "no shards at 0%")
		T.eq(toasts(), shown, "no toasts")
		-- the real odds
		w.patch(info, "ShardChance", real)
		w.data.Shards = 0
		shown = toasts()
		local jobs = 1000
		for _ = 1, jobs do
			job()
		end
		T.near(w.data.Shards / jobs, real, 0.04, "share of jobs with a shard")
		T.eq(toasts() - shown, w.data.Shards, "one toast per shard")
		T.eq(w.data.Stats.IngotsSmelted, 0, "no ingots")
	end)

	withWorld("ProcessingService: each crushed pile is shaken for a shard once (no extractor loop)", function(w)
		stock(w, { "CrystalExtractor" })
		local crusher = place(w, "Crusher", 0, 0)
		local m = place(w, "CrystalExtractor", 4, 0)
		local info = MachineData.ById.CrystalExtractor
		w.patch(info, "ShardChance", 1) -- every allowed roll gives a shard
		w.data.Shards = 0
		T.eq(w.data.ShardRolls, 0, "a fresh save has no rolls")
		local now = 0
		local function shake(desc: any): any
			T.truthy(MachineService.insertDesc(m, desc, USER, "Belt"), "crushed in")
			tick(m, now)
			now += info.Time
			tick(m, now)
			local out = MachineLogic.popOut(m.Entry)
			T.truthy(out and out.K == "Crushed" and out.O == desc.O, "passed through")
			return out
		end
		-- a pile that no Crusher made for this save (or a looped one): no roll
		shake(item("Crushed", "Iron", "Rough"))
		T.eq(w.data.Shards, 0, "no roll without a crushed pile behind it")
		-- the Crusher makes 2 piles: 2 rolls
		MachineService.insertDesc(crusher, item("Clean", "Gold", "Clean"), USER, "Drop")
		tick(crusher, now)
		now += 10
		tick(crusher, now)
		T.eq(w.data.ShardRolls, 2, "one roll per pile crushed")
		local a = MachineLogic.popOut(crusher.Entry)
		local b = MachineLogic.popOut(crusher.Entry)
		local outA = shake(a)
		T.eq(w.data.Shards, 1, "first pile rolled")
		shake(b)
		T.eq(w.data.Shards, 2, "second pile rolled")
		T.eq(w.data.ShardRolls, 0, "both rolls spent")
		-- feeding the extractor its own output back finds nothing, however often
		local looped = outA
		for _ = 1, 20 do
			looped = shake(looped)
		end
		T.eq(w.data.Shards, 2, "a loop makes no shards")
		T.eq(w.data.ShardRolls, 0, "never negative")
		-- junk counts as none
		w.data.ShardRolls = 0 / 0
		shake(looped)
		T.eq(w.data.Shards, 2, "NaN rolls = none")
	end)

	withWorld("ProcessingService: the Alloy Furnace waits for a second ore, then makes one alloy", function(w)
		stock(w, { "AlloyFurnace" })
		local m = place(w, "AlloyFurnace", 0, 0)
		local seen = {}
		ProcessingService.onProcessed(function(_, id, input, outputs)
			table.insert(seen, { Id = id, Input = input, Outputs = outputs })
		end)
		T.eq(select(2, MachineService.insertDesc(m, item("Clean", "Gold"), USER, "Hand")), "Wrong", "ingots only")
		T.truthy(MachineService.insertDesc(m, item("Ingot", "Copper", "Flawless"), USER, "Belt"), "1st copper")
		tick(m, 0)
		T.eq(attr(m, "Working"), false, "one ore: no job")
		T.eq(attr(m, "Status"), "NeedsOtherOre", "says why")
		T.eq(m.State.Job, nil, "no job")
		T.truthy(MachineService.insertDesc(m, item("Ingot", "Copper", "Rough"), USER, "Belt"), "2nd copper")
		T.truthy(MachineService.insertDesc(m, item("Ingot", "Copper", "Clean"), USER, "Belt"), "3rd copper")
		tick(m, 1)
		T.eq(attr(m, "Status"), "NeedsOtherOre", "still one ore")
		local ok, reason = MachineService.insertDesc(m, item("Ingot", "Copper"), USER, "Belt")
		T.falsy(ok, "a 4th copper")
		T.eq(reason, "Full", "waits: the last place is kept for another ore")
		T.truthy(MachineService.insertDesc(m, item("Ingot", "Gold", "Pristine"), USER, "Belt"), "gold takes it")
		T.eq(attr(m, "Queue"), MAX_IN, "queue full")
		tick(m, 2)
		T.eq(attr(m, "Status"), "", "cleared once a job can start")
		T.eq(attr(m, "Working"), true, "working")
		T.eq(attr(m, "WorkTime"), MachineData.ById.AlloyFurnace.Time, "its job time")
		T.eq(attr(m, "WorkOre"), "Copper", "In[1] shows")
		tick(m, 2 + MachineData.ById.AlloyFurnace.Time)
		T.eq(#m.Entry.Out, 1, "ONE alloy for two ingots")
		local alloy = m.Entry.Out[1]
		T.eq(alloy.K, "Alloy", "an alloy")
		T.eq(alloy.O, "Gold", "of the more valuable ore")
		T.eq(alloy.G, "Pristine", "with the lower grade (Flawless + Pristine)")
		T.truthy(MachineLogic.isValidDesc(alloy), "a valid item")
		T.eq(count(m.Entry.In), 2, "two coppers wait")
		T.eq(m.Entry.In[1].G, "Rough", "the first copper and the gold went")
		T.eq(attr(m, "Queue"), 2, "Queue attribute")
		T.eq(attr(m, "Cycles"), 1, "one job")
		T.eq(w.data.Stats.IngotsSmelted, 0, "an alloy is no ingot")
		T.eq(#seen, 1, "listeners hear one job")
		T.truthy(seen[1].Id == "AlloyFurnace" and seen[1].Input.O == "Copper", "with its first ingot")
		T.eq(seen[1].Outputs[1].K, "Alloy", "and the alloy")
		T.eq(attr(m, "Status"), "NeedsOtherOre", "only copper left")
		T.eq(attr(m, "Working"), false, "idle")
		-- iron is worth more than copper; an ingot without a grade counts as Rough
		MachineService.insertDesc(m, item("Ingot", "Iron"), USER, "Hand")
		tick(m, 10)
		T.eq(attr(m, "Status"), "", "a pair again")
		tick(m, 10 + MachineData.ById.AlloyFurnace.Time)
		T.eq(m.Entry.Out[2].O, "Iron", "iron alloy")
		T.eq(m.Entry.Out[2].G, "Rough", "Rough")
		T.eq(m.Entry.In[1].G, "Clean", "the clean copper waits")
		-- a status MachineService shows is never replaced
		MachineService.setAttrs(m, { Status = "OutputBlocked" })
		tick(m, 20)
		T.eq(attr(m, "Status"), "OutputBlocked", "kept")
		MachineService.setAttrs(m, { Status = "" })
		tick(m, 21)
		T.eq(attr(m, "Status"), "NeedsOtherOre", "back once it is clear")
		-- an empty queue clears it
		m.Entry.In = nil
		tick(m, 22)
		T.eq(attr(m, "Status"), "", "nothing waits")
	end)

	withWorld("ProcessingService: a Speed buy rebuilds that machine type with its new look, queues kept", function(w)
		local hooked: any = nil
		w.patch(ShopService, "onBought", function(callback)
			hooked = callback
		end)
		ProcessingService.start()
		T.truthy(hooked == processing.onBought, "start() listens to Tech shop buys")
		local furnace = place(w, "ClayFurnace", 0, 0)
		local crusher = place(w, "Crusher", 4, 0)
		MachineService.insertDesc(furnace, item("Clean", "Iron", "Clean"), USER, "Hand")
		MachineService.insertDesc(furnace, item("Crushed", "Gold", "Rough"), USER, "Hand")
		furnace.Entry.Out = { item("Ingot", "Copper", "Rough") }
		tick(furnace, 10)
		T.eq(attr(furnace, "Working"), true, "a job is running")
		local entry = furnace.Entry
		T.eq(furnace.Model:GetAttribute("Level"), 0, "plain look")
		local function buy(machineId: any, upgrade: string, level: number?, kind: string?)
			hooked(w.player, {
				Item = `{machineId}:{upgrade}`,
				Kind = kind or "Upgrade",
				Machine = machineId,
				Upgrade = upgrade,
				Level = level,
				Count = 1,
				Price = 1000,
			})
		end
		w.data.MachineUpgrades = { ClayFurnace = { Speed = 1 } }
		buy("ClayFurnace", "Speed", 1)
		T.truthy(furnace.Removed, "the old model went")
		local new = MachineService.atCell(PLOT, 0, 0)
		T.truthy(new and new ~= furnace, "a new machine stands there")
		T.eq(new.Model:GetAttribute("Level"), MachineData.lookLevel(1), "with the level 1 look")
		T.truthy(new.Entry == entry, "on the same saved entry")
		T.eq(count(entry.In), 2, "the queue stays")
		T.eq(count(entry.Out), 1, "the finished item stays")
		T.eq(attr(new, "Queue"), 2, "Queue shown")
		T.eq(attr(new, "OutCount"), 1, "OutCount shown")
		T.eq(attr(new, "QueueMax"), MAX_IN, "spawned hook ran")
		T.truthy(new.Model.PrimaryPart.Prompt:FindFirstChild("LoadPrompt"), "Put In prompt")
		T.eq(new.State.Job, nil, "the job in progress...")
		tick(new, 11)
		T.eq(new.State.Job.Input, entry.In[1], "...starts over on In[1]")
		T.near(new.State.Job.EndsAt, 11 + 6 * MachineData.speedMult(1), 1e-9, "with the new speed")
		T.falsy(crusher.Removed, "other machine types stay")
		T.eq(MachineService.atCell(PLOT, 4, 0), crusher, "the crusher is untouched")
		-- buys that don't change the look rebuild nothing
		local function unchanged(label: string)
			T.eq(MachineService.atCell(PLOT, 0, 0), new, label)
			T.falsy(new.Removed, label)
		end
		buy("ClayFurnace", "Quality", 1)
		unchanged("a Quality buy")
		buy("ClayFurnace", "Speed", nil, "Machine")
		unchanged("a machine buy")
		buy("Nope", "Speed", 1)
		unchanged("an unknown machine")
		w.data.MachineUpgrades = { ClayFurnace = { Speed = 5 } }
		buy("ClayFurnace", "Speed", 5)
		unchanged("level 5 looks like level 4")
		hooked({ UserId = STRANGER, Name = "Nobody", Parent = true }, {
			Item = "x",
			Kind = "Upgrade",
			Machine = "ClayFurnace",
			Upgrade = "Speed",
			Level = 2,
			Count = 1,
			Price = 1,
		})
		unchanged("a player without a plot")
		-- the next look level does rebuild
		w.data.MachineUpgrades = { ClayFurnace = { Speed = 4 } }
		buy("ClayFurnace", "Speed", 4)
		local latest = MachineService.atCell(PLOT, 0, 0)
		T.truthy(latest ~= new and new.Removed, "rebuilt again")
		T.eq(latest.Model:GetAttribute("Level"), MachineData.lookLevel(4), "level 4 look")
		T.truthy(latest.Entry == entry, "same entry")
	end)

	withWorld("ProcessingService: roster processors conserve items over random jobs", function(w)
		stock(w, ROSTER)
		w.data.ShardRolls = ProcessingService.MaxShardRolls -- the fed piles count as freshly crushed
		local rng = Rng.new(4242)
		local machines = {
			place(w, "BrickFurnace", 0, 0),
			place(w, "Polisher", 3, 0),
			place(w, "CrystalExtractor", 6, 0),
			place(w, "PlasmaFurnace", 9, 0),
			place(w, "AlloyFurnace", 0, 4),
		}
		local feed = {
			BrickFurnace = { "Clean", "Crushed" },
			Polisher = { "Clean" },
			CrystalExtractor = { "Crushed" },
			PlasmaFurnace = { "Clean", "Crushed" },
			AlloyFurnace = { "Ingot" },
		}
		local ores = { "Copper", "Iron", "Silver", "Gold" }
		local grades = { "Rough", "Clean", "Pristine", "Flawless" }
		local pushed, popped = {}, {}
		local alloy = machines[5]
		local now = 0
		for step = 1, 4000 do
			local m = machines[rng:int(1, #machines)]
			local roll = rng:next()
			if roll < 0.45 then
				local kinds = feed[m.Id]
				local d = item(kinds[rng:int(1, #kinds)], ores[rng:int(1, #ores)], grades[rng:int(1, #grades)])
				if MachineService.insertDesc(m, d, USER, "Drop") then
					pushed[m] = (pushed[m] or 0) + 1
				end
			elseif roll < 0.7 then
				if MachineLogic.popOut(m.Entry) then
					popped[m] = (popped[m] or 0) + 1
				end
			else
				now += rng:range(0, 4)
				for _, x in machines do
					tick(x, now)
				end
			end
			for _, x in machines do
				T.le(count(x.Entry.In), MAX_IN, `In cap at step {step}`)
				T.le(count(x.Entry.Out), MAX_OUT, `Out cap at step {step}`)
			end
			if count(alloy.Entry.In) == MAX_IN then
				T.truthy(MachineLogic.alloyPair(alloy.Entry.In), `step {step}: a full alloy queue always holds a pair`)
			end
		end
		for _, m in machines do
			local consumed = (pushed[m] or 0) - count(m.Entry.In)
			local produced = count(m.Entry.Out) + (popped[m] or 0)
			local cycles = attr(m, "Cycles")
			if m == alloy then
				T.eq(consumed, 2 * produced, "two ingots per alloy")
				T.eq(produced, cycles, "one alloy per job")
			else
				T.eq(produced, consumed, m.Id .. ": one result per item")
			end
			T.eq(attr(m, "Queue"), count(m.Entry.In), m.Id .. " Queue attribute")
			T.truthy(cycles > 20, `{m.Id} did real work ({cycles})`)
			for _, d in m.Entry.Out or {} do
				T.truthy(MachineLogic.isValidDesc(d), m.Id .. " valid output")
				T.eq(d.K, MachineData.ById[m.Id].Output, m.Id .. " output kind")
			end
		end
		local shards = w.data.Shards
		T.truthy(shards > 0 and shards == math.floor(shards), `whole shards ({shards})`)
	end)
end
