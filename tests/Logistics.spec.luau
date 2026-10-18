-- LogisticsService under Lune (WP-Logi, docs/plans/MACHINES_GAME_PLAN.md):
-- MachineService.emitSide, the Splitter (in turn, the blocked-side
-- fallback), the Sorter (rarity routing, SorterCycle saving entry.C, a
-- blocked side waits), the Robot Arm (one item per interval, never two
-- places or none, nothing when the front refuses, the held output) and the
-- Sell Box (Tobin's price, owner only, popup and toast). MachineService is
-- real; save data, plots, Net and item spawning are small fakes per test.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local SellService = Loader.requirePath("ServerScriptService.Server.Services.SellService")
	local LogisticsService = Loader.requirePath("ServerScriptService.Server.Services.LogisticsService")

	local PLOT = 6
	local USER, STRANGER = 601, 602
	local MAX_IN = GameConfig.MachineIntakeQueue
	local internals = MachineService._test
	local logi = LogisticsService._test

	-- a speed modifier that only works while a test turns it on (added after
	-- every MachineService reset, which clears the modifiers)
	local boost: { [string]: number } = {}
	local function addBoost()
		MachineService.addSpeedModifier(function(m: any): number
			return boost[m.Id] or 1
		end)
	end

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
		local w: any = { notes = {}, spawns = {}, loose = 0, changed = 0, answers = {}, logs = {} }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.root = { Position = Vector3.zero }
		w.player = {
			UserId = USER,
			Name = "Hauler",
			Parent = true,
			GetAttribute = function()
				return nil
			end,
			Character = {
				FindFirstChildOfClass = function(_, class: string)
					return if class == "Humanoid" then { Health = 100 } else nil
				end,
				FindFirstChild = function(_, name: string)
					return if name == "HumanoidRootPart" then w.root else nil
				end,
			},
		}
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { Splitter = 4, Sorter = 2, RobotArm = 2, SellBox = 1, Crusher = 2, ClayFurnace = 2 }
		w.data = data
		w.hasData = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player and w.hasData then data else nil
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
		internals.reset()
		addBoost()
		LogisticsService.init()
		-- stand-ins with an intake: the answer per type decides canAccept, inserts are logged
		for _, id in { "Crusher", "ClayFurnace" } do
			w.answers[id] = { true, nil }
			w.logs[id] = {}
			MachineService.register(id, {
				canAccept = function()
					return w.answers[id][1], w.answers[id][2]
				end,
				insert = function(m, d, owner, via)
					table.insert(w.logs[id], { Machine = m, Desc = d, Owner = owner, Via = via })
				end,
			})
		end
		internals.spawnAll(w.player, PLOT)
		w.restore = function()
			table.clear(boost)
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

	local function place(w: any, id: string, x: number, z: number, r: number?): any
		local m, code = MachineService.place(w.player, id, x, z, r or 0)
		assert(m, `place {id}: {code}`)
		return m
	end

	local function attr(m: any, name: string): any
		return m.Model:GetAttribute(name)
	end

	local function count(list: any): number
		return if list then #list else 0
	end

	-- The plot cell a spawned item appeared over.
	local function cellOf(record: any): (number?, number?)
		return PlotService.cellAt(PLOT, record.CFrame.Position)
	end

	-- Which side of the machine (-1 left, 1 right) a spawned item was sent to.
	local function sideOf(m: any, record: any): number
		local sx, sz = cellOf(record)
		for _, side in { -1, 1 } do
			local cx, cz = Grid.sideOutputCell(m.Id, m.X, m.Z, m.R, side)
			if sx == cx and sz == cz then
				return side
			end
		end
		return 0
	end

	---------------------------------------------------------------- emitSide

	withWorld("Logistics: emitSide pops items out of OutputL / OutputR sideways onto the side cell", function(w)
		for r = 0, 3 do
			local m = place(w, "Splitter", 2 + r * 2, 2, r)
			local plotCF = PlotService.plotCFrame(PLOT)
			for _, side in { -1, 1 } do
				local d = item("Clean", "Iron", "Clean")
				local result, record = MachineService.emitSide(m, d, side)
				T.eq(result, "Spawned", `r{r} side {side}`)
				T.truthy(record and record.Desc == d and record.Owner == USER and record.ServerOwned, "the same item, server physics")
				local point = MachineService.point(m, if side < 0 then "OutputL" else "OutputR")
				T.truthy(point, "attachment " .. side)
				T.near((record.CFrame.Position - point.Position).Magnitude, 0, 1e-4, "at the attachment")
				local cx, cz = Grid.sideOutputCell(m.Id, m.X, m.Z, m.R, side)
				local sx, sz = cellOf(record)
				T.eq(sx, cx, `r{r} side {side} cell x`)
				T.eq(sz, cz, `r{r} side {side} cell z`)
				local rx, rz = Grid.right(r)
				local outward = plotCF:VectorToWorldSpace(Vector3.new(rx, 0, rz)) * side
				local flat = Vector3.new(record.Velocity.X, 0, record.Velocity.Z)
				T.near((flat - outward * MachineService.SidePop.Out).Magnitude, 0, 1e-4, "sideways")
				T.near(record.Velocity.Y, MachineService.SidePop.Up, 1e-4, "a little up")
			end
		end
		-- too many loose items: blocked, nothing spawned
		local m = MachineService.ofPlot(PLOT)[1]
		w.loose = GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom
		local spawns = #w.spawns
		T.eq(MachineService.emitSide(m, item("Clean"), 1), "Blocked", "loose cap")
		T.eq(attr(m, "Status"), "TooManyItems", "status")
		T.eq(#w.spawns, spawns, "nothing spawned")
		MachineService.pickup(m)
		T.eq(MachineService.emitSide(m, item("Clean"), 1), "Blocked", "a packed-up machine sends nothing")
	end)

	withWorld("Logistics: emitSide hands to a machine in the side cell only from a face that takes items", function(w)
		local m = place(w, "Splitter", 5, 5, 0)
		local lx, lz = Grid.sideOutputCell("Splitter", 5, 5, 0, -1)
		T.eq(lx, 4, "left cell x")
		T.eq(lz, 5, "left cell z")
		-- a Crusher whose right side touches the splitter's cell (NoFront: it takes)
		local crusher = place(w, "Crusher", 3, 4, 0)
		local d = item("Clean", "Gold", "Pristine")
		T.eq(MachineService.emitSide(m, d, -1), "Handed", "into the crusher")
		local last = w.logs.Crusher[#w.logs.Crusher]
		T.truthy(last.Machine == crusher and last.Desc == d and last.Owner == USER and last.Via == "Machine", "insert args")
		w.answers.Crusher = { false, "Full" }
		T.eq(MachineService.emitSide(m, d, -1), "Blocked", "crusher full")
		T.eq(attr(m, "Status"), "OutputBlocked", "status")
		T.eq(#w.spawns, 0, "nothing spawned")
		-- turned so that its front (the output) faces the splitter: it doesn't take, the item pops out
		T.truthy(MachineService.move(crusher, 3, 4, 1), "crusher turned toward the splitter")
		w.answers.Crusher = { true, nil }
		local inserts = #w.logs.Crusher
		T.eq(MachineService.emitSide(m, d, -1), "Spawned", "pops out instead")
		T.eq(#w.logs.Crusher, inserts, "not inserted")
	end)

	---------------------------------------------------------------- Splitter

	withWorld("Logistics: the Splitter takes items like a processor and sends them left and right in turn", function(w)
		local m = place(w, "Splitter", 5, 5, 0)
		T.eq(attr(m, "Queue"), 0, "Queue")
		T.eq(attr(m, "QueueMax"), MAX_IN, "QueueMax")
		T.eq(attr(m, "Status"), "", "Status")
		T.truthy(MachineService.hasIntake(m), "takes items")
		local prompt = m.Model.PrimaryPart.Prompt:FindFirstChild("LoadPrompt")
		T.truthy(prompt and prompt.ActionText == MachineData.ById.Splitter.LoadText, "Put In prompt")
		local _, why = MachineService.insertDesc(m, item("Clean"), STRANGER, "Belt")
		T.eq(why, "Foreign", "someone else's item")
		_, why = MachineService.insertDesc(m, { K = "Bogus", O = "Copper" }, USER, "Belt")
		T.eq(why, "Wrong", "junk")
		local sent = {}
		local before = w.changed
		for i = 1, MAX_IN do
			local d = item(if i == 1 then "Raw" else "Ingot", "Iron", "Clean")
			table.insert(sent, d)
			T.truthy(MachineService.insertDesc(m, d, USER, if i % 2 == 0 then "Belt" else "Hand"), "item " .. i)
			T.eq(attr(m, "Queue"), i, "Queue " .. i)
		end
		T.eq(w.changed, before + MAX_IN, "every insert marks the save changed")
		_, why = MachineService.insertDesc(m, item("Clean"), USER, "Belt")
		T.eq(why, "Full", "a 5th item waits")
		-- one item per interval, left first, then in turn
		local tick = logi.splitter.tick
		local interval = LogisticsService.interval(m, LogisticsService.SplitInterval)
		T.near(interval, LogisticsService.SplitInterval, 1e-9, "Speed 0, full power")
		local now = 100
		tick(m, now)
		T.eq(#w.spawns, 1, "the first leaves at once")
		tick(m, now + interval * 0.5)
		T.eq(#w.spawns, 1, "nothing more within the interval")
		for _ = 2, MAX_IN do
			now += interval
			tick(m, now)
		end
		T.eq(#w.spawns, MAX_IN, "all out")
		for i, record in w.spawns do
			T.truthy(record.Desc == sent[i], "in order " .. i)
			T.eq(sideOf(m, record), if i % 2 == 1 then -1 else 1, "side of item " .. i)
		end
		T.eq(m.Entry.In, nil, "empty queue is nil")
		T.eq(attr(m, "Queue"), 0, "Queue 0")
		T.eq(attr(m, "Cycles"), MAX_IN, "Cycles")
		T.eq(attr(m, "LastSide"), 1, "LastSide")
		now += interval
		tick(m, now)
		T.eq(attr(m, "Working"), false, "idle")
		-- the Speed level and power change the interval
		w.data.MachineUpgrades.Splitter = { Speed = 5 }
		T.near(LogisticsService.interval(m, LogisticsService.SplitInterval), 0.6 * MachineData.speedMult(5), 1e-9, "Speed 5")
		boost.Splitter = 0.6
		T.near(
			LogisticsService.interval(m, LogisticsService.SplitInterval),
			0.6 * MachineData.speedMult(5) / 0.6,
			1e-9,
			"slower on too little power"
		)
		boost.Splitter = 1000
		T.eq(LogisticsService.interval(m, LogisticsService.SplitInterval), LogisticsService.MinInterval, "never below MinInterval")
	end)

	withWorld("Logistics: a blocked Splitter side gives its turn to the other side", function(w)
		local m = place(w, "Splitter", 5, 5, 0)
		place(w, "Crusher", 3, 4, 0) -- on the left side cell, takes from the splitter's side
		w.answers.Crusher = { false, "Full" }
		for i = 1, 3 do
			MachineService.insertDesc(m, item("Clean", "Iron", "Clean"), USER, "Belt")
			T.eq(attr(m, "Queue"), i, "queued " .. i)
		end
		local tick = logi.splitter.tick
		local interval = LogisticsService.interval(m, LogisticsService.SplitInterval)
		local now = 50
		tick(m, now)
		T.eq(#w.spawns, 1, "left blocked: out on the right")
		T.eq(sideOf(m, w.spawns[1]), 1, "right")
		T.eq(attr(m, "Status"), "", "status cleared once it left")
		now += interval
		tick(m, now)
		T.eq(#w.spawns, 2, "left still blocked: right again")
		T.eq(sideOf(m, w.spawns[2]), 1, "right again")
		-- the left takes again: the next item goes left (into the crusher)
		w.answers.Crusher = { true, nil }
		now += interval
		tick(m, now)
		T.eq(#w.logs.Crusher, 1, "handed left")
		T.eq(#w.spawns, 2, "not spawned")
		T.eq(m.Entry.In, nil, "all three left")
		-- both sides blocked: the item stays first in line and the splitter waits OutputRetry
		local d = item("Ingot", "Gold", "Clean")
		MachineService.insertDesc(m, d, USER, "Belt")
		w.answers.Crusher = { false, "Full" }
		w.loose = GameConfig.MaxLooseItemsPerPlayer
		now += interval
		tick(m, now)
		T.eq(count(m.Entry.In), 1, "kept")
		T.truthy(m.Entry.In[1] == d, "the same item")
		T.eq(#w.spawns, 2, "nothing spawned")
		T.eq(#w.logs.Crusher, 1, "nothing handed")
		T.truthy(attr(m, "Status") ~= "", "a blocked status shows")
		w.loose = 0
		tick(m, now + GameConfig.OutputRetry * 0.5)
		T.eq(count(m.Entry.In), 1, "waits before trying again")
		tick(m, now + GameConfig.OutputRetry)
		T.eq(m.Entry.In, nil, "then it leaves")
		T.eq(#w.spawns, 3, "on the free side")
		T.eq(sideOf(m, w.spawns[3]), 1, "the right (the left is still full)")
	end)

	---------------------------------------------------------------- Sorter

	withWorld("Logistics: the Sorter sends its threshold rarity and better right, the rest left", function(w)
		local m = place(w, "Sorter", 5, 5, 0)
		T.eq(LogisticsService.DefaultThreshold, Rarity.get("Rare").Order, "default Rare")
		T.eq(attr(m, "Threshold"), 3, "Threshold")
		T.eq(attr(m, "Detail"), "Rare+ ▶ right", "Detail")
		local _, why = MachineService.insertDesc(m, item("Raw", "Gold"), USER, "Belt")
		T.eq(why, "Wrong", "dirty ore hides its rarity")
		local list = {
			{ item("Clean", "Copper", "Clean"), -1 }, -- Common
			{ item("Clean", "Gold", "Rough"), 1 }, -- Rare
			{ item("Ingot", "Diamond", "Clean"), 1 }, -- Epic
			{ item("Crushed", "Silver", "Clean"), -1 }, -- Uncommon
		}
		for _, pair in list do
			T.truthy(MachineService.insertDesc(m, pair[1], USER, "Belt"), "in: " .. pair[1].O)
		end
		local tick = logi.sorter.tick
		local interval = LogisticsService.interval(m, LogisticsService.SortInterval)
		local now = 10
		for _ = 1, #list do
			tick(m, now)
			now += interval
		end
		T.eq(#w.spawns, #list, "all sorted")
		for i, pair in list do
			T.truthy(w.spawns[i].Desc == pair[1], "in order " .. i)
			T.eq(sideOf(m, w.spawns[i]), pair[2], pair[1].O .. " side")
		end
	end)

	withWorld("Logistics: SorterCycle steps the threshold through the rarities and saves it in C", function(w)
		local m = place(w, "Sorter", 5, 5, 0)
		w.root.Position = m.Model:GetPivot().Position
		local before = w.changed
		internals.action(w.player, m.Model, "SorterCycle", nil)
		T.eq(m.Entry.C, 4, "one step on: Epic")
		T.eq(attr(m, "Detail"), "Epic+ ▶ right", "Detail follows")
		T.eq(attr(m, "Threshold"), 4, "Threshold follows")
		T.eq(w.changed, before + 1, "saved")
		-- Gold (Rare) now goes left
		MachineService.insertDesc(m, item("Clean", "Gold", "Clean"), USER, "Belt")
		logi.sorter.tick(m, 10)
		T.eq(sideOf(m, w.spawns[1]), -1, "Rare below Epic: left")
		internals.action(w.player, m.Model, "SorterCycle", -1)
		T.eq(m.Entry.C, 3, "-1 steps back")
		-- it wraps around both ways
		m.Entry.C = #Rarity.List
		internals.action(w.player, m.Model, "SorterCycle", { "junk" })
		T.eq(m.Entry.C, 1, "Mythic -> Common (junk args step on)")
		T.eq(attr(m, "Detail"), "Common+ ▶ right", "Common")
		internals.action(w.player, m.Model, "SorterCycle", -1)
		T.eq(m.Entry.C, #Rarity.List, "Common -> Mythic")
		-- a broken saved setting counts as the default
		for _, bad in { 0, 7, 9, 0 / 0, "Rare" } do
			m.Entry.C = bad
			T.eq(LogisticsService.threshold(m), LogisticsService.DefaultThreshold, "bad C " .. tostring(bad))
		end
		T.eq(LogisticsService.nextThreshold(6, 1), 1, "next of 6")
		T.eq(LogisticsService.nextThreshold(1, -1), 6, "back of 1")
		-- not a Sorter, not yours, too far: nothing
		local splitter = place(w, "Splitter", 8, 5, 0)
		internals.action(w.player, splitter.Model, "SorterCycle", nil)
		T.eq(splitter.Entry.C, nil, "a Splitter has no threshold")
		m.Entry.C = 3
		local stranger = { UserId = STRANGER, Name = "Stranger", Parent = true, Character = w.player.Character }
		internals.action(stranger, m.Model, "SorterCycle", nil)
		w.root.Position = m.Model:GetPivot().Position + Vector3.new(0, 0, GameConfig.MachineUseRange + 1)
		internals.action(w.player, m.Model, "SorterCycle", nil)
		T.eq(m.Entry.C, 3, "unchanged")
		-- the saved setting shows again after a respawn
		m.Entry.C = 5
		internals.reset()
		LogisticsService.init()
		internals.spawnAll(w.player, PLOT)
		local again = MachineService.atCell(PLOT, 5, 5)
		T.eq(attr(again, "Detail"), "Legendary+ ▶ right", "the saved threshold shows")
	end)

	withWorld("Logistics: a Sorter waits while its chosen side is blocked (never the wrong side)", function(w)
		local m = place(w, "Sorter", 5, 5, 0)
		place(w, "Crusher", 6, 4, 0) -- on the right side cell, takes from the sorter's side
		w.answers.Crusher = { false, "Full" }
		local gold = item("Clean", "Gold", "Clean")
		MachineService.insertDesc(m, gold, USER, "Belt")
		MachineService.insertDesc(m, item("Clean", "Copper", "Clean"), USER, "Belt")
		logi.sorter.tick(m, 10)
		T.eq(#w.spawns, 0, "nothing went left")
		T.eq(count(m.Entry.In), 2, "both wait")
		T.truthy(m.Entry.In[1] == gold, "gold still first")
		T.eq(attr(m, "Status"), "OutputBlocked", "status")
		w.answers.Crusher = { true, nil }
		logi.sorter.tick(m, 10 + GameConfig.OutputRetry)
		T.eq(#w.logs.Crusher, 1, "gold went right into the crusher")
		T.truthy(w.logs.Crusher[1].Desc == gold, "that gold")
		logi.sorter.tick(m, 10 + GameConfig.OutputRetry + LogisticsService.SortInterval)
		T.eq(#w.spawns, 1, "copper left")
		T.eq(sideOf(m, w.spawns[1]), -1, "on the left")
	end)

	---------------------------------------------------------------- Robot Arm

	-- A furnace whose front faces the arm, the arm, and a crusher in front of it.
	local function armLine(w: any): (any, any, any)
		local furnace = place(w, "ClayFurnace", 4, 6, 0) -- covers 4-5 x 6-7, output cell (5, 5)
		local ox, oz = Grid.outputCell("ClayFurnace", 4, 6, 0)
		assert(ox == 5 and oz == 5, "furnace output cell")
		local arm = place(w, "RobotArm", 5, 5, 0) -- faces -Z: back (5, 6), front (5, 4)
		local crusher = place(w, "Crusher", 4, 3, 0) -- covers 4-5 x 3-4, its back touches the arm
		return furnace, arm, crusher
	end

	withWorld("Logistics: the Robot Arm moves exactly one finished item per interval, none lost or doubled", function(w)
		local furnace, arm, crusher = armLine(w)
		T.falsy(MachineService.hasIntake(arm), "the arm takes nothing itself")
		T.eq(attr(arm, "Holding"), "", "Holding")
		T.eq(attr(arm, "Working"), false, "Working")
		local a, b, c = item("Ingot", "Copper", "Clean"), item("Ingot", "Iron", "Rough"), item("Ingot", "Gold", "Pristine")
		furnace.Entry.Out = { a, b, c }
		local tick = logi.arm.tick
		local interval = LogisticsService.interval(arm, LogisticsService.ArmInterval)
		T.near(interval, LogisticsService.ArmInterval, 1e-9, "1.5 s at Speed 0")
		local before = w.changed
		local now = 200
		tick(arm, now)
		local log = w.logs.Crusher
		T.eq(#log, 1, "one item moved")
		T.truthy(log[1].Desc == a and log[1].Via == "Machine" and log[1].Owner == USER, "the first one, as a machine hand-over")
		T.truthy(log[1].Machine == crusher, "into the crusher")
		T.eq(#furnace.Entry.Out, 2, "gone from the furnace")
		T.eq(attr(furnace, "OutCount"), 2, "furnace OutCount")
		T.eq(attr(arm, "Holding"), "Copper", "Holding the ore it moved")
		T.eq(attr(arm, "Working"), true, "Working")
		T.eq(attr(arm, "Cycles"), 1, "Cycles")
		T.lt(before, w.changed, "saved")
		for i = 1, 9 do
			tick(arm, now + interval * i / 10)
		end
		T.eq(#log, 1, "nothing more within the interval")
		T.eq(attr(arm, "Holding"), "", "the hand-over show ended")
		T.eq(attr(arm, "Working"), false, "idle again")
		now += interval
		tick(arm, now)
		T.eq(#log, 2, "the next interval: the next item")
		T.truthy(log[2].Desc == b, "in order")
		now += interval
		tick(arm, now)
		now += interval
		tick(arm, now)
		T.eq(#log, 3, "no more than there was")
		T.truthy(log[3].Desc == c, "the last one")
		T.eq(furnace.Entry.Out, nil, "the furnace is empty")
		-- every item is in exactly one place
		local seen = {}
		for _, entry in log do
			T.falsy(seen[entry.Desc], "never moved twice")
			seen[entry.Desc] = true
		end
		T.truthy(seen[a] and seen[b] and seen[c], "never lost")
		-- faster with Speed
		w.data.MachineUpgrades.RobotArm = { Speed = 3 }
		T.near(LogisticsService.interval(arm, LogisticsService.ArmInterval), 1.5 * MachineData.speedMult(3), 1e-9, "Speed 3")
	end)

	withWorld("Logistics: the Robot Arm does nothing when the front refuses or can't take from its side", function(w)
		local furnace, arm, crusher = armLine(w)
		local a = item("Ingot", "Copper", "Clean")
		furnace.Entry.Out = { a }
		w.answers.Crusher = { false, "Full" }
		local tick = logi.arm.tick
		tick(arm, 10)
		T.eq(#w.logs.Crusher, 0, "nothing handed")
		T.truthy(furnace.Entry.Out and furnace.Entry.Out[1] == a, "the item stays in the furnace")
		T.eq(attr(arm, "Status"), "OutputBlocked", "the arm shows it waits")
		T.eq(attr(arm, "Holding"), "", "holding nothing")
		local result = LogisticsService.armMove(arm)
		T.eq(result, "Refused", "armMove says why")
		-- the crusher's front (its output) toward the arm: it never takes from there
		w.answers.Crusher = { true, nil }
		T.truthy(MachineService.move(crusher, 4, 3, 2), "crusher turned around")
		tick(arm, 20)
		T.eq(#w.logs.Crusher, 0, "not into its front")
		T.eq(#furnace.Entry.Out, 1, "still there")
		-- nothing in front at all
		MachineService.pickup(crusher)
		tick(arm, 30)
		T.eq(attr(arm, "Status"), "", "no machine in front: idle")
		T.eq(select(1, LogisticsService.armMove(arm)), "Idle", "Idle")
		T.eq(#furnace.Entry.Out, 1, "still there")
		-- junk in Out is left for the MachineService tick to drop
		furnace.Entry.Out = { { K = "Bogus", O = "Copper" } }
		place(w, "Crusher", 4, 3, 0)
		T.eq(select(1, LogisticsService.armMove(arm)), "Idle", "junk is not moved")
	end)

	withWorld("Logistics: the Robot Arm keeps the back machine's output in instead of letting it pop out", function(w)
		local furnace, arm, crusher = armLine(w)
		furnace.Entry.Out = { item("Ingot", "Copper", "Clean"), item("Ingot", "Iron", "Clean") }
		w.answers.Crusher = { false, "Full" }
		-- the arm looks first (MachineService ticks in no fixed order), then the whole tick runs
		logi.arm.tick(arm, os.clock())
		T.lt(os.clock(), furnace.State.NextEmit, "the furnace's output is held")
		internals.tick()
		T.eq(#w.spawns, 0, "nothing popped out onto the arm")
		T.eq(#furnace.Entry.Out, 2, "both wait in the furnace")
		-- the front takes again: the arm moves them, still nothing loose
		w.answers.Crusher = { true, nil }
		logi.arm.tick(arm, os.clock() + 100)
		T.eq(#w.logs.Crusher, 1, "moved by the arm")
		T.eq(#w.spawns, 0, "none spawned")
		-- without a machine in front the arm holds nothing: the furnace works as before
		MachineService.pickup(crusher)
		furnace.State.NextEmit = 0
		logi.arm.tick(arm, os.clock())
		T.eq(furnace.State.NextEmit, 0, "not held")
		internals.tick()
		T.eq(#w.spawns, 1, "it pops out as usual")
		T.eq(furnace.Entry.Out, nil, "gone from the furnace")
	end)

	---------------------------------------------------------------- Sell Box

	withWorld("Logistics: the Sell Box sells the owner's items at once at Tobin's price", function(w)
		local m = place(w, "SellBox", 5, 5, 0)
		T.truthy(MachineService.hasIntake(m), "takes items")
		local prompt = m.Model.PrimaryPart.Prompt:FindFirstChild("LoadPrompt")
		T.truthy(prompt and prompt.ActionText == MachineData.ById.SellBox.LoadText, "Put In prompt")
		local items = { item("Clean", "Gold", "Pristine"), item("Ingot", "Iron", "Clean"), item("Raw", "Diamond") }
		local total = 0
		local coins = w.data.Coins
		local sold = w.data.Stats.ItemsSold
		for i, d in items do
			local price = SellService.priceOf(d)
			T.lt(0, price, "worth something " .. i)
			local before = w.changed
			T.truthy(MachineService.insertDesc(m, d, USER, if i == 1 then "Belt" else "Drop"), "sold " .. i)
			total += price
			T.near(w.data.Coins, coins + total, 1e-6, "paid " .. i)
			T.eq(w.data.Stats.ItemsSold, sold + i, "ItemsSold " .. i)
			T.lt(before, w.changed, "saved " .. i)
		end
		T.eq(m.Entry.In, nil, "it never holds an item")
		T.eq(m.Entry.Out, nil, "nothing comes out")
		T.eq(attr(m, "Cycles"), #items, "Cycles")
		-- refusals: someone else's item, kinds it can't sell, junk, no save
		local _, why = MachineService.insertDesc(m, item("Clean", "Gold", "Clean"), STRANGER, "Belt")
		T.eq(why, "Foreign", "someone else's item")
		_, why = MachineService.insertDesc(m, { K = "Gear", O = "Iron", G = "Clean", R = "Pickaxe" }, USER, "Belt")
		T.eq(why, "Wrong", "not a kind it sells")
		_, why = MachineService.insertDesc(m, { K = "Bogus", O = "Copper" }, USER, "Belt")
		T.eq(why, "Wrong", "junk")
		w.hasData = false
		_, why = MachineService.insertDesc(m, item("Clean", "Gold", "Clean"), USER, "Belt")
		T.eq(why, "Busy", "no save loaded: the item waits")
		w.hasData = true
		T.near(w.data.Coins, coins + total, 1e-6, "no coins for refused items")
		-- one coin popup and one toast for sales close together
		T.eq(#w.notes, 0, "nothing yet")
		local tick = logi.sellBox.tick
		tick(m, os.clock() + LogisticsService.SellPopup + 0.01)
		local earned = w.notes[1]
		T.truthy(earned and earned.Name == "Earned" and earned.Player == w.player, "a coin popup")
		T.near(earned.Payload.Amount, total, 1e-6, "for all of them")
		T.eq(earned.Payload.Count, #items, "count")
		T.eq(earned.Payload.Source, "Sell", "Tobin's popup")
		T.eq(typeof(earned.Payload.Position), "Vector3", "at the box")
		T.eq(#w.notes, 1, "the toast comes later")
		tick(m, os.clock() + LogisticsService.SellToast + 0.01)
		local toast = w.notes[2]
		T.truthy(toast and toast.Name == "Notify", "a toast")
		T.truthy(string.find(toast.Payload.Text, SellService.paidText(total, #items), 1, true), "Tobin paid ... for 3 items")
		T.truthy(string.find(toast.Payload.Text, "Diamond", 1, true), "the dirty ore is revealed")
		T.eq(toast.Payload.Rarity, "Epic", "coloured by the rarest revealed ore")
		tick(m, os.clock() + 100)
		T.eq(#w.notes, 2, "once")
		-- packing the box up says what it sold right away
		MachineService.insertDesc(m, item("Ingot", "Copper", "Clean"), USER, "Belt")
		MachineService.pickup(m)
		T.eq(#w.notes, 4, "popup and toast on pickup")
		T.eq(w.notes[4].Name, "Notify", "toast")
	end)

	withWorld("Logistics: the Sell Box pays the owner's sell bonus, listeners get the base price", function(w)
		local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
		local SELL_PCT = 0.63
		Bonuses.register("LogisticsSpecSell", function()
			return { SellPct = SELL_PCT }
		end)
		local heard = {}
		local listening = true
		SellService.onSold(function(_p, d, value)
			if listening then
				table.insert(heard, { Desc = d, Value = value })
			end
		end)
		local ok, err = pcall(function()
			local m = place(w, "SellBox", 5, 5, 0)
			local d = item("Clean", "Gold", "Pristine")
			local base = SellService.priceOf(d)
			local coins = w.data.Coins
			T.truthy(MachineService.insertDesc(m, d, USER, "Belt"), "sold")
			local paid = math.floor(base * (1 + SELL_PCT) + 0.5)
			T.eq(w.data.Coins, coins + paid, "base x sellMult, like Tobin's counter")
			T.eq(paid, Bonuses.sellAmount(Bonuses.stats(w.player), base), "the same number as Bonuses.sellAmount")
			T.eq(#heard, 1, "onSold heard the sale")
			T.eq(heard[1].Value, base, "onSold gets the base price")
			logi.sellBox.tick(m, os.clock() + LogisticsService.SellPopup + 0.01)
			local earned = w.notes[1]
			T.truthy(earned and earned.Name == "Earned", "a coin popup")
			T.eq(earned.Payload.Amount, paid, "the popup shows what was paid")
		end)
		listening = false
		Bonuses.unregister("LogisticsSpecSell")
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("Logistics: LogisticsService registers every roster logistics machine", function(w)
		local m = place(w, "Splitter", 1, 1, 0)
		local s = place(w, "Sorter", 3, 1, 0)
		local box = place(w, "SellBox", 5, 1, 0)
		local arm = place(w, "RobotArm", 8, 1, 0)
		T.truthy(MachineService.hasIntake(m) and MachineService.hasIntake(s) and MachineService.hasIntake(box), "intakes")
		T.falsy(MachineService.hasIntake(arm), "the arm has none")
		T.eq(attr(arm, "Status"), "", "arm spawned")
		for _, info in MachineData.List do
			if info.Behaviour == "Splitter" or info.Behaviour == "Sorter" or info.Behaviour == "SellBox" then
				T.truthy(info.Accepts, info.Id .. " accepts something")
			end
		end
	end)
end
