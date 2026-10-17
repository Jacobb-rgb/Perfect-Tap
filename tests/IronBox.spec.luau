-- The Iron Box under Lune (step 3, WP-CleanerBox): IronBoxService's sorter
-- on top of the real MachineService + ProcessingService jobs and the real
-- PenService store, the keep list (IronBoxAction), the Keep List prompt,
-- and the pure parts of IronBoxView (chips, predict = the server's rules,
-- layout sizes). Saves, plots, Net and item spawning are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local MachineLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineLogic")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
	local ProcessingService = Loader.requirePath("ServerScriptService.Server.Services.ProcessingService")
	local IronBoxService = Loader.requirePath("ServerScriptService.Server.Services.IronBoxService")
	local IronBoxView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.IronBoxView")
	local Workspace = Loader.game:GetService("Workspace")

	local PLOT = 4
	local USER, STRANGER = 401, 402
	local TIME = MachineData.ById.IronBox.Time
	local internals = MachineService._test
	local processing = ProcessingService._test
	local box = IronBoxService._test

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

	local function fakePlayer(userId: number, name: string): any
		return {
			UserId = userId,
			Name = name,
			Parent = true,
			GetAttribute = function()
				return nil
			end,
		}
	end

	local function setup(): any
		local w: any = { notes = {}, spawns = {}, changed = 0, serverNow = 9000 }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.player = fakePlayer(USER, "Sorter")
		w.stranger = fakePlayer(STRANGER, "Stranger")
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { IronBox = 3, AutoCleaner = 1 }
		data.Discovered = { Coal = true, Copper = true, Gold = true, Diamond = true }
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
		patch(Net, "fire", function(name, p, payload, extra)
			table.insert(w.notes, { Name = name, Player = p, Payload = payload, Extra = extra })
		end)
		patch(ItemService, "looseCount", function()
			return 0
		end)
		patch(ItemService, "spawnDesc", function(d, owner)
			local record = { Desc = d, Owner = owner }
			table.insert(w.spawns, record)
			return record
		end)
		patch(Workspace, "GetServerTimeNow", function()
			return w.serverNow
		end)
		internals.reset()
		processing.reset()
		box.reset()
		IntakeService._test.reset()
		processing.reseed(4242)
		ProcessingService.init()
		MachineService.register("IronBox", ProcessingService.sorterBehaviour(IronBoxService.sorter))
		internals.spawnAll(w.player, PLOT)
		w.restore = function()
			internals.reset()
			processing.reset()
			box.reset()
			IntakeService._test.reset()
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

	local function place(w: any, x: number?, z: number?): any
		local m, code = MachineService.place(w.player, "IronBox", x or 4, z or 4, 0)
		assert(m, `place IronBox: {code}`)
		return m
	end

	-- the sorter behaviour's tick for a placed box (a fake clock)
	local sorterTick = ProcessingService.sorterBehaviour(IronBoxService.sorter).tick
	local function tick(m: any, now: number)
		sorterTick(m, now)
	end
	local function attr(m: any, name: string): any
		return m.Model:GetAttribute(name)
	end
	local function count(list: any): number
		return if list then #list else 0
	end
	local function notesNamed(w: any, name: string): { any }
		local list = {}
		for _, note in w.notes do
			if note.Name == name then
				table.insert(list, note)
			end
		end
		return list
	end

	-- one item through a box: in, start, finish (returns the time after)
	local function sortOne(w: any, m: any, desc: any, now: number): number
		T.truthy(MachineService.insertDesc(m, desc, USER, "Belt"), `{desc.K} {desc.O} goes in`)
		tick(m, now)
		local ends = m.State.Job and m.State.Job.EndsAt or now
		tick(m, ends)
		return ends
	end

	---------------------------------------------------------------- the box

	withWorld("IronBox: spawns with its attributes, a Sort prompt and a Keep List prompt", function(w)
		local m = place(w)
		for name, value in { LastKind = "", LastOre = "", LastGrade = "", LastRoute = "", Kept = 0, Sent = 0, Queue = 0, Cycles = 0 } do
			T.eq(attr(m, name), value, name)
		end
		T.eq(attr(m, "QueueMax"), GameConfig.MachineIntakeQueue, "QueueMax")
		T.truthy(MachineService.hasIntake(m), "takes items")
		local anchor = m.Model.PrimaryPart.Prompt
		local load = anchor:FindFirstChild("LoadPrompt")
		T.truthy(load, "Put In prompt")
		T.eq(load.ActionText, "Sort", "its text")
		local keep = anchor:FindFirstChild(IronBoxService.PromptName)
		T.truthy(keep, "Keep List prompt")
		T.eq(keep.ActionText, "Keep List")
		T.truthy(keep.KeyboardKeyCode == roblox.Enum.KeyCode.G, "G on keyboards")
		T.truthy(keep.GamepadKeyCode == roblox.Enum.KeyCode.ButtonB, "B on gamepads")
		T.eq(keep.UIOffset.Y, 72, "under the Put In prompt")
		T.eq(keep.HoldDuration, 0)
	end)

	withWorld("IronBox: kept clean ore goes into the pen, everything else out of the front", function(w)
		local m = place(w)
		local now = 10
		local stored = #w.data.Storage
		-- Gold is Rare: the default Rare+ rule keeps it
		now = sortOne(w, m, item("Clean", "Gold", "Pristine"), now)
		T.eq(#w.data.Storage, stored + 1, "into the pen")
		local last = w.data.Storage[#w.data.Storage]
		T.truthy(last.K == "Clean" and last.O == "Gold" and last.G == "Pristine", "the same item")
		T.eq(m.Entry.In, nil, "out of the box")
		T.eq(m.Entry.Out, nil, "not out of the front too")
		T.eq(attr(m, "LastRoute"), "Keep")
		T.eq(attr(m, "LastOre"), "Gold")
		T.eq(attr(m, "LastGrade"), "Pristine")
		T.eq(attr(m, "LastKind"), "Clean")
		T.eq(attr(m, "Kept"), 1)
		T.eq(attr(m, "Sent"), 0)
		T.eq(attr(m, "Cycles"), 1, "the box still animates its cycles")
		-- Coal is Common: sent on
		now = sortOne(w, m, item("Clean", "Coal", "Rough"), now + 1)
		T.eq(#w.data.Storage, stored + 1, "not kept")
		T.eq(count(m.Entry.Out), 1, "waits to leave the front")
		T.eq(m.Entry.Out[1].O, "Coal")
		T.eq(attr(m, "LastRoute"), "Send")
		T.eq(attr(m, "Sent"), 1)
		-- dirty ore always passes on (and the box can't see through the dirt)
		now = sortOne(w, m, item("Raw", "Diamond"), now + 1)
		T.eq(m.Entry.Out[2].K, "Raw", "dirty Diamond passes on")
		T.eq(attr(m, "LastKind"), "Raw")
		T.eq(attr(m, "LastOre"), "", "the ore stays a secret")
		T.eq(attr(m, "LastGrade"), "")
		-- crushed ore and ingots pass on even when their ore is kept
		now = sortOne(w, m, item("Ingot", "Gold", "Clean"), now + 1)
		now = sortOne(w, m, item("Crushed", "Diamond", "Clean"), now + 1)
		T.eq(count(m.Entry.Out), 4, "ingot and crushed ore on their way")
		T.eq(#w.data.Storage, stored + 1, "nothing else kept")
		T.eq(attr(m, "Kept"), 1)
		T.eq(attr(m, "Sent"), 4)
		-- MachineService sends Out through the front as loose items
		internals.tick()
		T.eq(#w.spawns, 1, "one item out of the front per emit")
		T.eq(w.spawns[1].Desc.O, "Coal", "oldest first")
		T.eq(w.spawns[1].Owner, USER, "owned by the box's owner")
	end)

	withWorld("IronBox: KeepMode and KeepList decide what clean ore stays", function(w)
		local m = place(w)
		local now = 10
		w.data.KeepMode = "All"
		now = sortOne(w, m, item("Clean", "Coal"), now)
		T.eq(attr(m, "LastRoute"), "Keep", "All keeps Coal")
		w.data.KeepMode = "List"
		w.data.KeepList = { Coal = true, Gold = false }
		now = sortOne(w, m, item("Clean", "Coal"), now + 1)
		T.eq(attr(m, "LastRoute"), "Keep", "on the list")
		now = sortOne(w, m, item("Clean", "Gold", "Flawless"), now + 1)
		T.eq(attr(m, "LastRoute"), "Send", "taken off the list")
		now = sortOne(w, m, item("Clean", "Diamond"), now + 1)
		T.eq(attr(m, "LastRoute"), "Keep", "not on the list: Rare+ rule (Epic)")
		now = sortOne(w, m, item("Clean", "Copper"), now + 1)
		T.eq(attr(m, "LastRoute"), "Send", "not on the list: Rare+ rule (Common)")
		-- a broken setting counts as the default
		w.data.KeepMode = "Nonsense"
		w.data.KeepList = 5
		now = sortOne(w, m, item("Clean", "Gold"), now + 1)
		T.eq(attr(m, "LastRoute"), "Keep", "default Rare+")
		T.eq(attr(m, "Kept"), 4)
		T.eq(attr(m, "Sent"), 2)
	end)

	withWorld("IronBox: a full pen sends kept ore out of the front, with a hint", function(w)
		local m = place(w)
		local capacity = PenService.capacityOf(w.data)
		for i = 1, capacity do
			w.data.Storage[i] = item("Clean", "Coal", "Rough")
		end
		sortOne(w, m, item("Clean", "Gold", "Clean"), 10)
		T.eq(#w.data.Storage, capacity, "the pen did not grow past its capacity")
		T.eq(count(m.Entry.Out), 1, "out of the front instead")
		T.eq(m.Entry.Out[1].O, "Gold")
		T.eq(attr(m, "LastRoute"), "Send")
		local hints = notesNamed(w, "Notify")
		T.eq(#hints, 1, "one hint")
		T.eq(hints[1].Payload.Text, IronBoxService.PenFullText)
		sortOne(w, m, item("Clean", "Gold", "Clean"), 20)
		T.eq(#notesNamed(w, "Notify"), 1, "the hint is throttled")
	end)

	withWorld("IronBox: a blocked front waits, a kept item still goes into the pen", function(w)
		local m = place(w)
		m.Entry.Out = { item("Raw"), item("Raw"), item("Raw"), item("Raw") }
		MachineService.insertDesc(m, item("Clean", "Coal"), USER, "Belt")
		MachineService.insertDesc(m, item("Clean", "Gold"), USER, "Belt")
		tick(m, 10)
		tick(m, 10 + TIME)
		T.eq(count(m.Entry.In), 2, "the Coal waits for room in front")
		T.eq(attr(m, "Status"), "OutputBlocked")
		T.eq(attr(m, "Working"), false)
		local stored = #w.data.Storage
		-- room in front: the Coal leaves, then the Gold goes into the pen even with Out full again
		MachineLogic.popOut(m.Entry)
		tick(m, 11 + TIME)
		T.eq(count(m.Entry.Out), 4, "Coal in Out")
		tick(m, 12 + 2 * TIME)
		T.eq(m.Entry.In, nil, "the Gold is done")
		T.eq(#w.data.Storage, stored + 1, "kept with the front full")
		T.eq(count(m.Entry.Out), 4)
	end)

	withWorld("IronBox: sort time follows the box's Speed level and Bellows", function(w)
		local m = place(w)
		MachineService.insertDesc(m, item("Clean", "Coal"), USER, "Belt")
		tick(m, 1)
		T.eq(attr(m, "WorkTime"), TIME, "4 s without upgrades")
		m.State.Job = nil
		w.data.MachineUpgrades = { IronBox = { Speed = 2 } }
		tick(m, 2)
		T.near(attr(m, "WorkTime"), TIME * MachineData.speedMult(2), 1e-9, "Speed 2")
		-- every Speed level still counts with full Bellows
		w.data.Upgrades.Bellows = #MachineData.Bellows.Prices
		local last = math.huge
		for level = 0, MachineData.upgradeMax("IronBox", "Speed") do
			w.data.MachineUpgrades = { IronBox = { Speed = level } }
			m.State.Job = nil
			tick(m, 3 + level)
			local seconds = attr(m, "WorkTime")
			T.lt(seconds, last, `Speed {level} is faster`)
			T.truthy(seconds >= GameConfig.MinProcessTime, "never below MinProcessTime")
			last = seconds
		end
		-- another machine type's upgrade does nothing here
		w.data.MachineUpgrades = { AutoCleaner = { Speed = 5 } }
		w.data.Upgrades.Bellows = 0
		m.State.Job = nil
		tick(m, 20)
		T.eq(attr(m, "WorkTime"), TIME, "only the box's own Speed")
	end)

	withWorld("IronBox: sorting counts toward nothing (stats, discovery, listeners)", function(w)
		local m = place(w)
		local seen = 0
		ProcessingService.onProcessed(function()
			seen += 1
		end)
		w.data.Discovered = {}
		local now = sortOne(w, m, item("Clean", "Diamond", "Flawless"), 10)
		sortOne(w, m, item("Ingot", "Gold"), now + 1)
		T.eq(seen, 0, "no onProcessed")
		T.eq(w.data.Stats.IngotsSmelted, 0, "an ingot passing by is not smelted")
		T.eq(w.data.Discovered.Diamond, nil, "nothing discovered")
		T.eq(#notesNamed(w, "Notify"), 0, "no toasts")
	end)

	withWorld("IronBox: refuses other players' items and items it doesn't sort", function(w)
		local m = place(w)
		local ok, reason = MachineService.insertDesc(m, item("Clean", "Gold"), STRANGER, "Belt")
		T.falsy(ok)
		T.eq(reason, "Foreign")
		ok, reason = MachineService.insertDesc(m, { K = "Gear", O = "Gold", G = "Clean", R = "Dagger" }, USER, "Drop")
		T.falsy(ok)
		T.eq(reason, "Wrong", "gear is not sorted")
		for i = 1, GameConfig.MachineIntakeQueue do
			T.truthy(MachineService.insertDesc(m, item("Clean", "Coal"), USER, "Drop"), "item " .. i)
		end
		ok, reason = MachineService.insertDesc(m, item("Clean", "Coal"), USER, "Drop")
		T.eq(reason, "Full", "the queue waits")
	end)

	withWorld("IronBox: items are conserved over random sorting", function(w)
		local rng = Rng.new(31337)
		local m = place(w)
		local kinds = { "Raw", "Clean", "Clean", "Clean", "Crushed", "Ingot" }
		local ores = { "Coal", "Copper", "Gold", "Diamond", "Silver" }
		local modes = { "RarePlus", "List", "All" }
		local pushed, popped, removed = 0, 0, 0
		local storedBefore = #w.data.Storage
		local now = 0
		for step = 1, 3000 do
			local before = #w.data.Storage
			local roll = rng:next()
			if roll < 0.4 then
				local d = item(kinds[rng:int(1, #kinds)], ores[rng:int(1, #ores)], "Clean")
				if MachineService.insertDesc(m, d, USER, "Belt") then
					pushed += 1
				end
			elseif roll < 0.6 then
				if MachineLogic.popOut(m.Entry) then
					popped += 1
				end
			elseif roll < 0.65 then
				-- the player takes some ore out of the pen
				if #w.data.Storage > 0 then
					table.remove(w.data.Storage, rng:int(1, #w.data.Storage))
					removed += 1
				end
			elseif roll < 0.68 then
				w.data.KeepMode = modes[rng:int(1, #modes)]
				w.data.KeepList = { Gold = rng:next() < 0.5, Coal = rng:next() < 0.5 }
			elseif roll < 0.7 then
				-- the pen fills up now and then
				w.data.Upgrades.PenLevel = rng:int(0, 2)
			else
				now += rng:range(0, 3)
				tick(m, now)
			end
			T.le(count(m.Entry.In), GameConfig.MachineIntakeQueue, `In cap at step {step}`)
			T.le(count(m.Entry.Out), MachineData.MaxOutBuffer, `Out cap at step {step}`)
			-- the box never fills the pen past its capacity
			T.le(#w.data.Storage, math.max(before, PenService.capacityOf(w.data)), `pen cap at step {step}`)
		end
		local kept = attr(m, "Kept")
		local sent = attr(m, "Sent")
		T.eq(pushed, count(m.Entry.In) + kept + sent, "every item in is queued or sorted")
		T.eq(sent, count(m.Entry.Out) + popped, "every sent item is waiting or gone out of the front")
		T.eq(#w.data.Storage + removed - storedBefore, kept, "every kept item is in the pen")
		T.truthy(kept > 20 and sent > 20, "both ways were used")
		T.eq(attr(m, "Cycles"), kept + sent, "Cycles")
	end)

	---------------------------------------------------------------- the keep list

	withWorld("IronBox: the Keep List prompt opens the panel on your own box only", function(w)
		local m = place(w)
		box.open(w.player, m)
		local opens = notesNamed(w, "OpenUI")
		T.eq(#opens, 1, "opened")
		T.eq(opens[1].Payload, "IronBox", "the IronBox panel")
		T.truthy(opens[1].Extra.Box == m.Model, "for this box")
		box.open(w.stranger, m)
		T.eq(#notesNamed(w, "OpenUI"), 1, "not for a stranger")
		local denied = notesNamed(w, "Notify")
		T.eq(#denied, 1)
		T.eq(denied[1].Payload.Kind, "Deny")
		box.open(w.stranger, m)
		T.eq(#notesNamed(w, "Notify"), 1, "the deny toast is throttled")
	end)

	withWorld("IronBoxAction: modes, choices, presets and ClearList", function(w)
		local action = box.action
		local data = w.data
		local before = w.changed
		action(w.player, "SetMode", { Mode = "All" })
		T.eq(data.KeepMode, "All")
		T.eq(w.changed, before + 1, "changed once")
		action(w.player, "SetMode", { Mode = "All" })
		T.eq(w.changed, before + 1, "no change, no push")
		for _, bad in { "Everything", 5, "", string.rep("x", 100) } do
			action(w.player, "SetMode", { Mode = bad })
			T.eq(data.KeepMode, "All", "refused mode " .. tostring(bad))
		end
		-- a choice in "All": every discovered ore becomes the list as shown, then the one changes
		action(w.player, "SetKeep", { Ore = "Coal", Keep = false })
		T.eq(data.KeepMode, "List", "now your own list")
		T.eq(data.KeepList.Coal, false, "Coal sent on")
		for _, ore in { "Copper", "Gold", "Diamond" } do
			T.eq(data.KeepList[ore], true, ore .. " stays kept as shown")
		end
		T.eq(data.KeepList.Silver, nil, "undiscovered ores get no entry")
		-- only known, discovered ores
		local snapshot = deepCopy(data.KeepList)
		action(w.player, "SetKeep", { Ore = "Silver", Keep = true })
		action(w.player, "SetKeep", { Ore = "NotAnOre", Keep = true })
		action(w.player, "SetKeep", { Ore = "Gold", Keep = "yes" })
		action(w.player, "SetKeep", { Ore = 7, Keep = true })
		action(w.player, "SetKeep", "Gold")
		for ore, keep in snapshot do
			T.eq(data.KeepList[ore], keep, "unchanged " .. ore)
		end
		T.eq(data.KeepList.Silver, nil, "Silver refused (not discovered)")
		-- presets
		action(w.player, "SetKeepMany", { Ores = { "Coal", "Copper", "Gold", "Silver", "Coal" }, Keep = true })
		T.eq(data.KeepList.Coal, true)
		T.eq(data.KeepList.Copper, true)
		T.eq(data.KeepList.Silver, nil, "undiscovered skipped")
		local tooMany = {}
		for i = 1, #OreData.List + 1 do
			tooMany[i] = "Coal"
		end
		action(w.player, "SetKeepMany", { Ores = tooMany, Keep = false })
		T.eq(data.KeepList.Coal, true, "too long a list is refused")
		-- choices in Rare+ mode start from the Rare+ rule, not an old list
		action(w.player, "SetMode", { Mode = "RarePlus" })
		action(w.player, "SetKeep", { Ore = "Diamond", Keep = false })
		T.eq(data.KeepMode, "List")
		T.eq(data.KeepList.Coal, false, "Coal as Rare+ showed it")
		T.eq(data.KeepList.Gold, true, "Gold as Rare+ showed it")
		T.eq(data.KeepList.Diamond, false, "the tapped one")
		-- ClearList: everything follows Rare+ again (still in List mode)
		action(w.player, "ClearList")
		T.eq(next(data.KeepList), nil, "empty")
		T.eq(data.KeepMode, "List")
		local count = w.changed
		action(w.player, "ClearList")
		T.eq(w.changed, count, "already empty")
		-- junk
		action(w.player, "Explode", { Ore = "Gold", Keep = true })
		action(w.player, nil, nil)
		action(w.player, string.rep("S", 40), {})
		action(w.stranger, "SetMode", { Mode = "All" })
		T.eq(w.changed, count, "nothing changed")
		T.eq(data.KeepMode, "List")
	end)

	withWorld("IronBoxAction: the box follows the list at once", function(w)
		local m = place(w)
		box.action(w.player, "SetKeep", { Ore = "Coal", Keep = true })
		local now = sortOne(w, m, item("Clean", "Coal"), 10)
		T.eq(attr(m, "LastRoute"), "Keep", "Coal kept after SetKeep")
		box.action(w.player, "SetKeep", { Ore = "Gold", Keep = false })
		sortOne(w, m, item("Clean", "Gold", "Flawless"), now + 1)
		T.eq(attr(m, "LastRoute"), "Send", "Gold sent on after SetKeep false")
	end)

	---------------------------------------------------------------- the view (pure)

	T.test("IronBoxView: chips are the discovered ores, best income first", function()
		local state = {
			Discovered = { Coal = true, Gold = true, Diamond = true, Bogus = true, Copper = false },
			KeepMode = "RarePlus",
			KeepList = {},
		}
		local list = IronBoxView.entries(state)
		T.eq(#list, 3, "only known, discovered ores")
		T.eq(list[1].Ore, "Diamond", "best income first")
		T.eq(list[3].Ore, "Coal")
		for i = 2, #list do
			T.truthy(list[i - 1].Income >= list[i].Income, "sorted")
		end
		T.eq(list[1].Keep, true, "Epic kept by Rare+")
		T.eq(list[3].Keep, false, "Common sent on")
		T.truthy(list[2].Color == OreData.ById.Gold.Color, "the ore's colour")
		state.KeepMode = "List"
		state.KeepList = { Coal = true, Diamond = false }
		list = IronBoxView.entries(state)
		T.eq(list[1].Keep, false)
		T.eq(list[3].Keep, true)
		T.eq(#IronBoxView.entries(nil), 0)
		T.eq(#IronBoxView.entries({ Discovered = 5 }), 0)
		T.eq(IronBoxView.modeOf({ KeepMode = "Bad" }), MachineData.Keep.Default)
		for _, mode in MachineData.Keep.Modes do
			T.truthy(#IronBoxView.modeText(mode) > 10, mode .. " text")
			T.truthy(IronBoxView.ModeLabels[mode], mode .. " label")
		end
	end)

	T.test("IronBoxView: predict follows IronBoxService's rules", function()
		local rng = Rng.new(99)
		local ores = { "Coal", "Copper", "Gold", "Diamond", "Silver", "Bogus" }
		local actions = { "SetMode", "SetKeep", "SetKeepMany", "ClearList" }
		local modes = { "RarePlus", "List", "All", "Nope" }
		for trial = 1, 300 do
			local data: any = {
				Discovered = { Coal = true, Gold = true, Diamond = rng:next() < 0.5, Copper = rng:next() < 0.5 },
				KeepMode = modes[rng:int(1, 3)],
				KeepList = { Gold = rng:next() < 0.5, Silver = true },
			}
			local state = deepCopy(data)
			for _ = 1, 6 do
				local action = actions[rng:int(1, #actions)]
				local arg: any = nil
				if action == "SetMode" then
					arg = { Mode = modes[rng:int(1, #modes)] }
				elseif action == "SetKeep" then
					arg = { Ore = ores[rng:int(1, #ores)], Keep = rng:next() < 0.5 }
				elseif action == "SetKeepMany" then
					arg = { Ores = { ores[rng:int(1, #ores)], ores[rng:int(1, #ores)] }, Keep = rng:next() < 0.5 }
				end
				IronBoxService.apply(data, action, arg)
				state = IronBoxView.predict(state, action, arg)
				T.eq(state.KeepMode, data.KeepMode, `mode after {action} (trial {trial})`)
				for _, ore in OreData.List do
					local shown = MachineData.keepsOre(state.KeepMode, state.KeepList, ore.Id)
					local real = MachineData.keepsOre(data.KeepMode, data.KeepList, ore.Id)
					T.eq(shown, real, `{ore.Id} after {action} (trial {trial})`)
				end
			end
		end
	end)

	T.test("IronBoxView: builds, and chips stay big enough to tap on phones", function()
		local refs = IronBoxView.build()
		T.eq(refs.Gui.Enabled, false, "starts closed")
		T.truthy(refs.Modes.RarePlus and refs.Modes.List and refs.Modes.All, "three mode buttons")
		IronBoxView.setMode(refs, "List")
		T.truthy(refs.Presets.Visible, "presets")
		T.eq(refs.Modes.List:GetAttribute("Selected"), true)
		IronBoxView.setMode(refs, "All")
		T.eq(refs.Modes.List:GetAttribute("Selected"), false)
		T.eq(refs.Modes.All:GetAttribute("Selected"), true)
		local state = { Discovered = { Coal = true, Gold = true }, KeepMode = "RarePlus", KeepList = {} }
		local created = IronBoxView.setEntries(refs, IronBoxView.entries(state))
		T.eq(#created, 2, "two chips")
		T.eq(refs.Chips.Gold.Button:GetAttribute("Keep"), true)
		T.eq(refs.Chips.Coal.Button:GetAttribute("Keep"), false)
		T.truthy(refs.Chips.Gold.Button.BackgroundColor3 == OreData.ById.Gold.Color, "a kept chip is filled in its ore colour")
		T.falsy(refs.Empty.Visible)
		created = IronBoxView.setEntries(refs, IronBoxView.entries({ Discovered = { Gold = true }, KeepMode = "All" }))
		T.eq(#created, 0, "chips are reused")
		T.eq(refs.Chips.Coal, nil, "a chip that is gone is removed")
		IronBoxView.setEntries(refs, {})
		T.truthy(refs.Empty.Visible, "empty text")
		-- PC: the panel fits 720 design units with 4 rows
		IronBoxView.layout(refs, false, 1600, 720)
		T.eq(refs.Rows, 4)
		T.truthy(refs.Panel.Size.Y.Offset <= 700, "fits a 720 screen")
		-- phones: 0.62 scale, a 667 x 375 pt screen; chips and buttons >= 44 pt
		local phone = 0.62
		IronBoxView.layout(refs, true, 667 / phone, (375 - 36) / phone)
		T.truthy(refs.Rows >= 3, "three rows of chips")
		T.falsy(refs.Info.Visible, "no info line on phones")
		local modesRow = (refs.Modes.RarePlus.Parent :: any).Parent
		local closeHolder = refs.Close.Parent :: any
		local clear = modesRow.Position.Y.Offset >= 14 + closeHolder.Size.Y.Offset
			or modesRow.Position.X.Offset + modesRow.Size.X.Offset <= refs.Panel.Size.X.Offset - 16 - closeHolder.Size.X.Offset
		T.truthy(clear, "mode buttons clear of the close button")
		T.eq(refs.Panel.AnchorPoint.X, 1, "on the right, clear of the HUD coins")
		T.truthy(refs.Panel.Size.Y.Offset * phone <= 375 - 36, "fits the phone")
		T.truthy(refs.Panel.Size.X.Offset * phone <= 667, "fits the phone's width")
		T.truthy(refs.Grid.CellSize.Y.Offset * phone >= 44, "chips >= 44 pt")
		T.truthy((refs.Modes.List.Parent :: any).Size.Y.Offset * phone >= 40, "mode buttons")
		T.truthy((refs.AllKeep.Parent :: any).Size.Y.Offset * phone >= 40, "preset buttons")
		T.truthy((refs.Close.Parent :: any).Size.Y.Offset * phone >= 44, "close button")
		IronBoxView.setHint(refs, "", "rbxasset://a", "rbxasset://b")
		T.truthy(refs.PadHint.Visible and not refs.Hint.Visible, "gamepad glyphs")
	end)

	T.test("IronBox: Tech shop sells it and its Speed upgrade", function()
		T.truthy(EconomyConfig.techItem("IronBox"), "the machine")
		T.truthy(EconomyConfig.techItem("Upgrade:IronBox:Speed"), "its Speed upgrade")
		T.eq(EconomyConfig.techItem("Upgrade:IronBox:Quality"), nil, "no Quality upgrade")
	end)
end
