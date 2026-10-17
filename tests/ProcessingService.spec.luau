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
	local function attr(m: any, name: string): any
		return m.Model:GetAttribute(name)
	end
	local function count(list: any): number
		return if list then #list else 0
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
		T.truthy(prompt.ObjectText:find("60% Rough", 1, true), "odds on the prompt")
		-- the Tech shop writes the level; the plant shows it within a second
		w.data.MachineUpgrades = { AutoCleaner = { Quality = 5 } }
		tick(m, 0.5)
		T.eq(attr(m, "Quality"), 5, "level 5 shown")
		T.eq(attr(m, "QualityOdds"), "20% Clean · 50% Pristine · 30% Flawless", "level 5 odds")
		T.truthy(prompt.ObjectText:find("Quality 5", 1, true), "prompt names the level")
		local grades = {}
		local now = 10
		local jobs = 600
		for _ = 1, jobs do
			MachineService.insertDesc(m, item("Raw", "Silver"), USER, "Belt")
			tick(m, now)
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
		T.eq(attr(m, "WorkOre"), "Iron", "the stray raw ore is worked")
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
end
