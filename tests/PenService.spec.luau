-- PenService under Lune: pen capacity, the intake box (owner only, full pen
-- bounces), Put In, Take limits, ToPodium, bad inputs, the send queue (step 3:
-- intents only, one item at a time onto the PEN / TRAIN chute belts, filters,
-- Stop, leaving, junk), the sorting billboard and Direct Unload, and the pure
-- parts of PenView (rows, free podium slot, pile selection, the send toolbar).
-- The plot is built by the real PlotBuilder, machines and belts are real;
-- players, saves, carrying and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
	local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local ConveyorService = Loader.requirePath("ServerScriptService.Server.Services.ConveyorService")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local PenView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.PenView")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local PLOT = 2
	local USER, OTHER = 501, 502
	local pen = PenService._test
	local GOLD = "Clean|Gold|Pristine|"
	local DIRTY = "Raw|Copper||"

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

	local function fakePlayer(userId: number, name: string): any
		local p: any = { UserId = userId, Name = name, Parent = true, attributes = {} }
		p.GetAttribute = function(self, key)
			return self.attributes[key]
		end
		p.root = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0) }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then { Health = 100 } else nil
			end,
			FindFirstChild = function(_, child: string)
				return if child == "HumanoidRootPart" then p.root else nil
			end,
		}
		p.stand = function(position: any)
			p.root.Position = position
			p.root.CFrame = CFrame.new(position)
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, carried = {}, pickups = {}, zones = {}, hands = 3 }
		w.plotModel = PlotBuilder.buildPlot(roblox.Instance.new("Folder"), WorldLayout.Plots[PLOT], Rng.new(PLOT))
		w.player = fakePlayer(USER, "Owner")
		w.other = fakePlayer(OTHER, "Neighbour")
		w.data = deepCopy(DataTemplate)
		w.otherData = deepCopy(DataTemplate)
		w.gate = PenService.gateCFrame(PLOT)
		w.player.stand(w.gate.Position + Vector3.new(0, 3, 0))
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data elseif p == w.other then w.otherData else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, a, b, c)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b, C = c })
		end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player then PLOT else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT and not w.free then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then w.plotModel else nil
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == OTHER then w.other else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids = (w.ids or 0) + 1
			return "pen-guid-" .. w.ids
		end)
		patch(IntakeService, "addZone", function(name, part, handler)
			table.insert(w.zones, { Name = name, Part = part, Handler = handler })
		end)
		patch(CarryService, "capacity", function()
			return w.hands
		end)
		patch(CarryService, "list", function()
			return w.carried
		end)
		patch(CarryService, "takeTop", function(_, predicate)
			for i = #w.carried, 1, -1 do
				local record = w.carried[i]
				if not predicate or predicate(record) then
					table.remove(w.carried, i)
					return record
				end
			end
			return nil
		end)
		patch(CarryService, "pickup", function(p, record)
			if #w.carried >= w.hands then
				return false
			end
			record.State = "Carried"
			table.insert(w.carried, record)
			table.insert(w.pickups, record)
			return true
		end)
		ItemService._test.reset()
		MachineService._test.reset()
		ConveyorService._test.reset()
		pen.reset()
		w.gap = ConveyorService.SourceGap
		ConveyorService.SourceGap = 0
		w.data.StarterKitGiven = true
		w.data.MachineInventory = { Conveyor = 10 }
		T.truthy(pen.setupPen(PLOT), "pen set up")
		w.zone = w.zones[1]
		w.restore = function()
			ItemService._test.reset()
			MachineService._test.reset()
			ConveyorService._test.reset()
			ConveyorService.SourceGap = w.gap
			pen.reset()
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

	local function count(w: any, name: string): number
		local n = 0
		for _, note in w.notes do
			if note.Name == name then
				n += 1
			end
		end
		return n
	end

	local function lastNote(w: any, name: string): any
		for i = #w.notes, 1, -1 do
			if w.notes[i].Name == name then
				return w.notes[i]
			end
		end
		return nil
	end

	local function fill(w: any, key: string, n: number)
		local desc = ItemData.parseKey(key)
		for _ = 1, n do
			table.insert(w.data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
		end
	end

	local function inPen(w: any, key: string): number
		local n = 0
		for _, entry in w.data.Storage do
			if ItemData.storageKey(entry) == key then
				n += 1
			end
		end
		return n
	end

	-- A loose item of `owner` lying inside the pen's intake box.
	local function itemInPen(w: any, owner: number, desc: any): any
		local center = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT])
			* CFrame.new(BaseLayout.Pen.Area.Center.X, 1, BaseLayout.Pen.Area.Center.Z)
		return ItemService.spawnDesc(desc, owner, center, nil, true)
	end

	local function insideIntake(w: any, position: any): boolean
		local part = w.zone.Part
		local p = part.CFrame:PointToObjectSpace(position)
		local half = part.Size / 2
		return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
	end

	---------------------------------------------------------------- capacity

	withWorld("PenService: capacity follows the pen level and never passes the DataStore cap", function(w)
		local base = EconomyConfig.Pen.BaseCapacity
		T.eq(PenService.capacity(w.player), base, "starting pen")
		for level = 1, #EconomyConfig.Pen.Prices do
			w.data.Upgrades.PenLevel = level
			T.eq(
				PenService.capacity(w.player),
				math.min(GameConfig.MaxStoredItems, base + level * EconomyConfig.Pen.PerLevel),
				"level " .. level
			)
		end
		for _, junk in { -3, 0 / 0, "7", math.huge, 999 } do
			w.data.Upgrades.PenLevel = junk
			T.le(PenService.capacity(w.player), GameConfig.MaxStoredItems, "junk level " .. tostring(junk))
			T.le(base, PenService.capacity(w.player), "never below the start")
		end
		w.data.Upgrades.PenLevel = 0
		T.eq(PenService.capacity(fakePlayer(9, "Nobody")), 0, "no data: no pen")
		fill(w, GOLD, base - 1)
		T.truthy(PenService.hasRoom(w.player), "one place left")
		T.falsy(PenService.hasRoom(w.player, 2), "not two")
		T.truthy(PenService.store(w.player, { K = "Raw", O = "Iron" }), "last place")
		T.falsy(PenService.store(w.player, { K = "Raw", O = "Iron" }), "full: refused (no sale here)")
		T.eq(#w.data.Storage, base, "exactly full")
		T.eq(w.data.Coins, 0, "nothing sold")
		-- takeOne takes the newest matching entry, or nothing
		local taken = PenService.takeOne(w.player, "Raw|Iron||")
		T.truthy(taken and taken.O == "Iron", "took the iron")
		T.eq(PenService.takeOne(w.player, "Raw|Iron||"), nil, "no more iron")
		T.eq(PenService.takeOne(w.player, "Clean|Nope||"), nil, "unknown key")
	end)

	---------------------------------------------------------------- intake

	withWorld("PenService: your own items dropped in the pen are stored", function(w)
		local record = itemInPen(w, USER, { K = "Clean", O = "Gold", G = "Pristine" })
		w.zone.Handler(record)
		T.eq(record.State, "Consumed", "taken out of the world")
		T.eq(inPen(w, GOLD), 1, "in the pen")
		T.truthy(w.changed > 0, "data changed")
		local fx = lastNote(w, "Fx")
		T.eq(fx and fx.A, "PenIn", "PenIn effect")
		T.eq(w.zone.Name, "Pen" .. PLOT, "zone name")
		T.truthy(
			insideIntake(w, WorldLayout.plotCFrame(WorldLayout.Plots[PLOT]) * BaseLayout.Pen.Area.Center + Vector3.new(0, 1, 0)),
			"box covers the pen"
		)
	end)

	withWorld("PenService: other players' items are never taken, they bounce out of the gate", function(w)
		local foreign = itemInPen(w, OTHER, { K = "Clean", O = "Gold", G = "Flawless" })
		w.zone.Handler(foreign)
		T.eq(foreign.State, "Loose", "still a loose item")
		T.eq(#w.data.Storage, 0, "not in the owner's pen")
		T.eq(#w.otherData.Storage, 0, "not teleported into the thrower's pen either")
		T.falsy(insideIntake(w, foreign.Body.CFrame.Position), "out of the box")
		local toast = lastNote(w, "Notify")
		T.truthy(toast and toast.Player == w.other, "the thrower is told")
		local before = count(w, "Notify")
		w.zone.Handler(itemInPen(w, OTHER, { K = "Raw", O = "Coal" }))
		T.eq(count(w, "Notify"), before, "the toast is throttled")
		-- a free plot's pen takes nothing at all
		w.free = true
		local mine = itemInPen(w, USER, { K = "Raw", O = "Coal" })
		w.zone.Handler(mine)
		T.eq(mine.State, "Loose", "free plot: bounced")
		T.eq(#w.data.Storage, 0, "free plot: not stored")
	end)

	withWorld("PenService: a full pen bounces items back out with a toast", function(w)
		fill(w, DIRTY, PenService.capacity(w.player))
		local record = itemInPen(w, USER, { K = "Clean", O = "Gold", G = "Pristine" })
		w.zone.Handler(record)
		T.eq(record.State, "Loose", "not taken")
		T.falsy(insideIntake(w, record.Body.CFrame.Position), "bounced out of the gate")
		local toast = lastNote(w, "Notify")
		T.truthy(toast and toast.Player == w.player, "owner told")
		T.truthy(toast.A.Text:find("full", 1, true), "full text")
		T.eq(#w.data.Storage, PenService.capacity(w.player), "still exactly full")
		local before = count(w, "Notify")
		w.zone.Handler(itemInPen(w, USER, { K = "Raw", O = "Coal" }))
		T.eq(count(w, "Notify"), before, "full toast is throttled")
	end)

	---------------------------------------------------------------- prompts

	withWorld("PenService: Put In stores what you carry while there is room", function(w)
		pen.putIn(w.player, PLOT)
		T.truthy(lastNote(w, "Notify").A.Text:find("Carry ore", 1, true), "empty hands hint")
		for i = 1, 3 do
			local record = ItemService.spawnDesc({ K = "Raw", O = "Copper" }, USER, CFrame.new(i, 5, 0), nil, true)
			record.State = "Carried"
			table.insert(w.carried, record)
		end
		fill(w, GOLD, PenService.capacity(w.player) - 2)
		pen.putIn(w.player, PLOT)
		T.eq(#w.data.Storage, PenService.capacity(w.player), "filled up")
		T.eq(#w.carried, 1, "one left in your hands")
		T.truthy(lastNote(w, "Notify").A.Text:find("full", 1, true), "full toast")
		-- someone else's pen
		local before = #w.data.Storage
		pen.putIn(w.other, PLOT)
		T.eq(lastNote(w, "Notify").Player, w.other, "stranger told")
		T.eq(#w.data.Storage, before, "nothing changed")
	end)

	withWorld("PenService: Open Pen only opens your own pen", function(w)
		pen.open(w.player, PLOT)
		local open = lastNote(w, "OpenUI")
		T.truthy(open and open.Player == w.player and open.A == "Pen", "OpenUI Pen")
		pen.open(w.other, PLOT)
		T.eq(count(w, "OpenUI"), 1, "not for strangers")
		T.eq(lastNote(w, "Notify").Player, w.other, "stranger told")
	end)

	---------------------------------------------------------------- PenAction

	withWorld("PenService: Take spawns at most StorageTakeMax items into your hands", function(w)
		fill(w, GOLD, 8)
		pen.action(w.player, "Take", { Key = GOLD, Count = 2 })
		T.eq(inPen(w, GOLD), 6, "two out")
		T.eq(#w.pickups, 2, "into the hands")
		T.eq(w.pickups[1].Grade, "Pristine", "the right item")
		local spot = w.pickups[1].ReleasePos
		T.lt((spot - w.gate.Position).Magnitude, 4, "at the pen gate")
		-- over the limit, zero, fractions, NaN and strings do nothing
		for _, bad in { GameConfig.StorageTakeMax + 1, 0, -1, 1.5, 0 / 0, math.huge, "2" } do
			pen.action(w.player, "Take", { Key = GOLD, Count = bad })
		end
		T.eq(inPen(w, GOLD), 6, "bad counts ignored")
		-- the full limit at once: hands take 1 more, the rest lies at the gate
		pen.action(w.player, "Take", { Key = GOLD, Count = GameConfig.StorageTakeMax })
		T.eq(inPen(w, GOLD), 6 - GameConfig.StorageTakeMax, "StorageTakeMax out")
		T.eq(#w.carried, w.hands, "hands full")
		-- asking for more than there is takes what is there
		pen.action(w.player, "Take", { Key = GOLD, Count = GameConfig.StorageTakeMax })
		T.eq(inPen(w, GOLD), 0, "pen empty")
		pen.action(w.player, "Take", { Key = GOLD, Count = 1 })
		T.eq(inPen(w, GOLD), 0, "nothing to take")
	end)

	withWorld("PenService: Take refuses with full hands and too many loose items, far away or without a plot", function(w)
		fill(w, GOLD, 4)
		w.hands = 0
		for i = 1, GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom do
			ItemService.spawnDesc({ K = "Raw", O = "Coal" }, USER, CFrame.new(i * 3, 5, 400), nil, true)
		end
		pen.action(w.player, "Take", { Key = GOLD, Count = 1 })
		T.eq(inPen(w, GOLD), 4, "nothing taken")
		T.truthy(lastNote(w, "Notify").A.Text:find("hands are full", 1, true), "hands full toast")
		w.hands = 3
		w.player.stand(w.gate.Position + Vector3.new(PenService.Range + 10, 0, 0))
		pen.action(w.player, "Take", { Key = GOLD, Count = 1 })
		T.eq(inPen(w, GOLD), 4, "too far")
		T.truthy(lastNote(w, "Notify").A.Text:find("Walk back", 1, true), "too far toast")
		w.player.stand(w.gate.Position)
		local stranger = fakePlayer(USER, "Copy")
		pen.action(stranger, "Take", { Key = GOLD, Count = 1 })
		T.eq(inPen(w, GOLD), 4, "no plot, no data: nothing")
		w.player.Character = nil
		pen.action(w.player, "Take", { Key = GOLD, Count = 1 })
		T.eq(inPen(w, GOLD), 4, "no character")
	end)

	withWorld("PenService: ToPodium hands a canonical key and a valid slot to PodiumService", function(w)
		local calls = {}
		PenService.setPodiumPlacer(function(p, slot, key)
			table.insert(calls, { Player = p, Slot = slot, Key = key })
			return true, nil
		end)
		pen.action(w.player, "ToPodium", { Key = GOLD, Slot = 2 })
		T.eq(#calls, 1, "placed")
		T.truthy(calls[1].Player == w.player and calls[1].Slot == 2 and calls[1].Key == GOLD, "args")
		for _, slot in { 0, EconomyConfig.Podiums.Max + 1, 1.5, 0 / 0, "1", nil } do
			pen.action(w.player, "ToPodium", { Key = GOLD, Slot = slot })
		end
		T.eq(#calls, 1, "bad slots ignored")
		w.player.stand(w.gate.Position + Vector3.new(0, 0, 80))
		pen.action(w.player, "ToPodium", { Key = GOLD, Slot = 1 })
		T.eq(#calls, 1, "too far from the pen")
	end)

	withWorld("PenService: junk PenAction input is ignored", function(w)
		fill(w, GOLD, 3)
		local calls = 0
		PenService.setPodiumPlacer(function()
			calls += 1
			return true, nil
		end)
		local junk: { any } = {
			{ nil, { Key = GOLD, Count = 1 } },
			{ 5, { Key = GOLD, Count = 1 } },
			{ "Take", nil },
			{ "Take", "Clean|Gold|Pristine|" },
			{ "Take", setmetatable({ Key = GOLD, Count = 1 }, {}) },
			{ "Take", { Key = GOLD, Count = 1, A = 1, B = 2, C = 3 } },
			{ "Take", { Key = string.rep("x", 500), Count = 1 } },
			{ "Take", { Key = "Clean|Gold|Shiny|", Count = 1 } },
			{ "Take", { Key = "Clean|Unobtainium||", Count = 1 } },
			{ "Take", { Key = 42, Count = 1 } },
			{ "Steal", { Key = GOLD, Count = 1 } },
			{ string.rep("T", 100), { Key = GOLD, Count = 1 } },
		}
		for _, case in junk do
			pen.action(w.player, case[1], case[2])
		end
		T.eq(inPen(w, GOLD), 3, "pen untouched")
		T.eq(calls, 0, "no podium call")
		T.eq(#w.pickups, 0, "nothing spawned")
	end)

	---------------------------------------------------------------- send queue (step 3, WP-Belts)

	local COPPER_CLEAN = "Clean|Copper|Rough|"

	-- A belt on a chute cell of the plot (MachineService places it like build mode).
	local function chuteBelt(w: any, chute: string, r: number): any
		MachineService._test.spawnAll(w.player, PLOT)
		local x, z = BaseLayout.chuteCell(chute)
		local m = MachineService.place(w.player, "Conveyor", x, z, r)
		assert(m, "belt on the " .. chute .. " chute")
		return m
	end

	local function looseOn(m: any): { any }
		local list = {}
		local pivot = m.Model:GetPivot()
		for _, record in ItemService.looseList() do
			local p = pivot:PointToObjectSpace(record.Body.CFrame.Position)
			if math.abs(p.X) <= 2 and math.abs(p.Z) <= 2.5 and p.Y > -1 and p.Y < 5 then
				table.insert(list, record)
			end
		end
		return list
	end

	-- Items that left a chute ride on: move them off its cell.
	local function rideAway(m: any)
		for i, record in looseOn(m) do
			record.Model:PivotTo(m.Model:GetPivot() * CFrame.new(0, 1.5, -6 - i * 2))
		end
	end

	local function sendState(w: any): any
		local snapshot = {}
		local pens, trains = PenService.sendCounts(w.player)
		snapshot.Pen, snapshot.Train = pens, trains
		snapshot.Wait = pen.waitLine(w.player)
		return snapshot
	end

	local function census(w: any): number
		return #w.data.Storage + #ItemService.ownedBy(USER)
	end

	withWorld("PenService: Send keeps items in the pen until each one rides out of the PEN chute", function(w)
		fill(w, GOLD, 3)
		fill(w, DIRTY, 2)
		local total = census(w)
		pen.action(w.player, "Send", { Key = GOLD, Count = 2 })
		local toast = lastNote(w, "Notify")
		T.truthy(toast and toast.A.Text:find("PEN chute", 1, true), "no belt yet: says where it goes")
		local queue = pen.queue(w.player)
		T.truthy(queue and #queue.Pen.Intents == 1 and queue.Pen.Intents[1].Left == 2, "one intent for two")
		T.eq(inPen(w, GOLD), 3, "nothing taken out yet")
		T.eq(sendState(w).Pen, 2, "the State says two to send")
		PenService.tickSend(1)
		T.eq(inPen(w, GOLD), 3, "no belt: nothing leaves")
		T.eq(census(w), total, "nothing lost")
		T.truthy(sendState(w).Wait:find("Put a conveyor", 1, true), "the State says why")
		-- a belt facing the yard is no good either
		local m = chuteBelt(w, "Pen", BaseLayout.SinkRotation)
		PenService.tickSend(2)
		T.eq(inPen(w, GOLD), 3, "facing the yard: nothing leaves")
		T.truthy(sendState(w).Wait:find("away from the yard", 1, true), "turn the belt")
		MachineService.move(m, m.X, m.Z, 0)
		PenService.tickSend(3)
		T.eq(inPen(w, GOLD), 2, "one left the pen")
		local out = looseOn(m)
		T.eq(#out, 1, "it rides the PEN chute's belt")
		T.eq(out[1].Kind, "Clean", "the right item")
		T.eq(out[1].OreId, "Gold", "the right ore")
		T.eq(census(w), total, "moved, not copied")
		T.eq(sendState(w).Pen, 1, "one to go")
		T.eq(sendState(w).Wait, nil, "not waiting")
		PenService.tickSend(3.1)
		T.eq(inPen(w, GOLD), 2, "one item every SendInterval")
		PenService.tickSend(3 + PenService.SendInterval)
		T.eq(inPen(w, GOLD), 2, "the first still lies on the chute: waits")
		T.truthy(sendState(w).Wait:find("full", 1, true), "jammed")
		rideAway(m)
		PenService.tickSend(4)
		T.eq(inPen(w, GOLD), 1, "the second one")
		T.eq(census(w), total, "still nothing lost")
		T.eq(pen.queue(w.player), nil, "done: the queue is gone")
		T.eq(inPen(w, DIRTY), 2, "other items stay")
		local changedBefore = w.changed
		PenService.tickSend(10)
		T.eq(w.changed, changedBefore, "an empty queue costs nothing")
	end)

	withWorld("PenService: Send filters: all dirty, unkept (with the billboard), everything", function(w)
		fill(w, GOLD, 2)
		fill(w, COPPER_CLEAN, 2)
		fill(w, DIRTY, 3)
		fill(w, "Ingot|Iron|Clean|", 1)
		local m = chuteBelt(w, "Pen", 0)
		local function drain()
			for step = 1, 40 do
				rideAway(m)
				PenService.tickSend(100 + step)
			end
		end
		pen.action(w.player, "Send", { Filter = "Dirty" })
		T.eq(sendState(w).Pen, 3, "three dirty")
		drain()
		T.eq(inPen(w, DIRTY), 0, "all dirty ore sent")
		T.eq(#w.data.Storage, 5, "the rest stays")
		-- unkept needs the sorting billboard
		pen.action(w.player, "Send", { Filter = "Unkept" })
		T.truthy(lastNote(w, "Notify").A.Text:find("Pen Automation", 1, true), "needs the upgrade")
		T.eq(pen.queue(w.player), nil, "nothing queued")
		w.data.Upgrades.PenAutomation = 1
		pen.action(w.player, "Send", { Filter = "Unkept" })
		local expected = 0
		for _, entry in w.data.Storage do
			if not MachineData.keeps(w.data.KeepMode, w.data.KeepList, entry) then
				expected += 1
			end
		end
		T.eq(expected, 3, "clean copper and the ingot are not kept (Rare+ default)")
		T.eq(sendState(w).Pen, expected, "unkept count")
		drain()
		T.eq(inPen(w, GOLD), 2, "the kept gold stays")
		T.eq(#w.data.Storage, 2, "only kept ore left")
		-- "All" with a Count sends that many
		pen.action(w.player, "Send", { Filter = "All", Count = 1 })
		T.eq(sendState(w).Pen, 1, "Count limits a filter")
		drain()
		T.eq(#w.data.Storage, 1, "one sent")
		-- nothing matching: a hint, no intent
		pen.action(w.player, "Send", { Filter = "Dirty" })
		T.truthy(lastNote(w, "Notify").A.Text:find("nothing like that", 1, true), "nothing to send")
		T.eq(pen.queue(w.player), nil, "no intent")
	end)

	withWorld("PenService: equal intents merge, overlapping ones count items once, the queue has a cap", function(w)
		fill(w, DIRTY, 4)
		pen.action(w.player, "Send", { Key = DIRTY, Count = 2 })
		pen.action(w.player, "Send", { Key = DIRTY, Count = 1 })
		local queue = pen.queue(w.player)
		T.eq(#queue.Pen.Intents, 1, "same key merged")
		T.eq(queue.Pen.Intents[1].Left, 3, "counts add up")
		pen.action(w.player, "Send", { Filter = "Dirty" })
		pen.action(w.player, "Send", { Filter = "Dirty" })
		T.eq(#queue.Pen.Intents, 2, "same filter merged")
		T.eq(sendState(w).Pen, 4, "every item counts once")
		-- many different kinds: the lane is capped
		local grades = { "Rough", "Clean", "Pristine" }
		local added = 0
		for i = 1, 10 do
			local ore = OreData.List[i].Id
			for _, grade in grades do
				local key = `Clean|{ore}|{grade}|`
				if ItemData.parseKey(key) then
					fill(w, key, 1)
					pen.action(w.player, "Send", { Key = key })
					added += 1
				end
			end
		end
		T.truthy(added + 2 > PenService.MaxIntents, "enough kinds to hit the cap")
		T.eq(#queue.Pen.Intents, PenService.MaxIntents, "capped")
		T.truthy(lastNote(w, "Notify").A.Text:find("queue is full", 1, true), "told so")
	end)

	withWorld("PenService: StopSend and leaving just drop the intents; every item stays in the pen", function(w)
		fill(w, DIRTY, 5)
		local total = census(w)
		pen.action(w.player, "Send", { Filter = "Dirty" })
		-- StopSend works from anywhere
		w.player.stand(w.gate.Position + Vector3.new(0, 0, 300))
		pen.action(w.player, "StopSend", nil)
		T.eq(pen.queue(w.player), nil, "stopped")
		T.truthy(lastNote(w, "Notify").A.Text:find("stopped", 1, true), "told")
		T.eq(inPen(w, DIRTY), 5, "all still in the pen")
		local notes = #w.notes
		pen.action(w.player, "StopSend", {})
		T.eq(#w.notes, notes, "nothing to stop: quiet")
		-- leaving mid-send
		w.player.stand(w.gate.Position)
		local m = chuteBelt(w, "Pen", 0)
		pen.action(w.player, "Send", { Filter = "Dirty" })
		PenService.tickSend(1)
		T.eq(inPen(w, DIRTY), 4, "one on its way")
		rideAway(m)
		w.player.Parent = nil
		PenService.tickSend(2)
		T.eq(pen.queue(w.player), nil, "the queue just stops")
		T.eq(inPen(w, DIRTY), 4, "the rest never left the pen")
		T.eq(census(w), total, "nothing lost, nothing copied")
		-- no plot any more (released): same
		w.player.Parent = true
		pen.action(w.player, "Send", { Filter = "Dirty" })
		T.truthy(pen.queue(w.player), "queued again")
		local plotOf = PlotService.plotOf
		rawset(PlotService, "plotOf", function()
			return nil
		end)
		PenService.tickSend(3)
		rawset(PlotService, "plotOf", plotOf)
		T.eq(pen.queue(w.player), nil, "no plot: dropped")
		T.eq(inPen(w, DIRTY), 4, "still in the pen")
	end)

	withWorld("PenService: junk Send input changes nothing", function(w)
		fill(w, GOLD, 3)
		local junk: { any } = {
			{ Key = GOLD, Filter = "Dirty" },
			{ Filter = "Shiny" },
			{ Filter = 5 },
			{ Filter = string.rep("D", 50) },
			{},
			{ Key = GOLD, Count = 0 },
			{ Key = GOLD, Count = 1.5 },
			{ Key = GOLD, Count = 0 / 0 },
			{ Key = GOLD, Count = math.huge },
			{ Key = GOLD, Count = GameConfig.MaxStoredItems + 1 },
			{ Key = GOLD, Count = "2" },
			{ Key = "Clean|Unobtainium||" },
			{ Key = string.rep("x", 500) },
			{ Key = 42 },
			setmetatable({ Key = GOLD }, {}),
			{ Key = GOLD, Count = 1, A = 1, B = 2, C = 3 },
		}
		for _, arg in junk do
			pen.action(w.player, "Send", arg)
		end
		pen.action(w.player, "Send", nil)
		pen.action(w.player, "Send", "Clean|Gold|Pristine|")
		T.eq(pen.queue(w.player), nil, "nothing queued")
		T.eq(inPen(w, GOLD), 3, "pen untouched")
		-- far from the pen
		w.player.stand(w.gate.Position + Vector3.new(0, 0, 80))
		pen.action(w.player, "Send", { Key = GOLD })
		T.eq(pen.queue(w.player), nil, "too far")
		T.truthy(lastNote(w, "Notify").A.Text:find("Walk back", 1, true), "told")
	end)

	withWorld("PenService: the sorting billboard sends on what you don't keep as it arrives", function(w)
		local copper = { K = "Clean", O = "Copper", G = "Rough" }
		local gold = { K = "Clean", O = "Gold", G = "Pristine" }
		-- without the upgrade nothing happens
		w.zone.Handler(itemInPen(w, USER, copper))
		T.eq(pen.queue(w.player), nil, "no billboard: stays")
		w.data.Upgrades.PenAutomation = 1
		-- no belt at the PEN chute: it simply stays in the pen
		w.zone.Handler(itemInPen(w, USER, copper))
		T.eq(pen.queue(w.player), nil, "no belt: stays")
		local m = chuteBelt(w, "Pen", 0)
		w.zone.Handler(itemInPen(w, USER, gold))
		T.eq(pen.queue(w.player), nil, "kept ore stays")
		w.zone.Handler(itemInPen(w, USER, copper))
		local queue = pen.queue(w.player)
		T.truthy(queue and #queue.Pen.Intents == 1, "unkept ore queued")
		T.eq(queue.Pen.Intents[1].Key, COPPER_CLEAN, "by key")
		T.eq(queue.Pen.Intents[1].Left, 1, "just that one")
		-- Put In counts as arriving too
		local carried = ItemService.spawnDesc({ K = "Raw", O = "Coal" }, USER, CFrame.new(0, 5, 0), nil, true)
		carried.State = "Carried"
		table.insert(w.carried, carried)
		pen.putIn(w.player, PLOT)
		T.eq(#queue.Pen.Intents, 2, "dirty ore from your hands queued")
		PenService.tickSend(1)
		T.eq(#looseOn(m), 1, "out it goes")
		-- a list player: their own choices count
		w.data.KeepMode = "List"
		w.data.KeepList = { Copper = true }
		w.zone.Handler(itemInPen(w, USER, copper))
		local copperIntents = 0
		for _, intent in queue.Pen.Intents do
			if intent.Key == COPPER_CLEAN then
				copperIntents += 1
			end
		end
		T.eq(copperIntents, 0, "copper is kept now: not added")
	end)

	withWorld("PenService: Direct Unload pours the train's dirty ore out of the TRAIN chute", function(w)
		local raw = { K = "Raw", O = "Gold" }
		local clean = { K = "Clean", O = "Copper", G = "Rough" }
		local function deliver(descs: { any })
			for _, d in descs do
				table.insert(w.data.Storage, d)
			end
			PenService.arrived(w.player, descs, "Train")
		end
		-- level 1: no Direct Unload, but the billboard sends unkept ore from the PEN chute
		w.data.Upgrades.PenAutomation = 1
		local penBelt = chuteBelt(w, "Pen", 0)
		deliver({ { K = raw.K, O = raw.O } })
		local queue = pen.queue(w.player)
		T.truthy(queue and #queue.Pen.Intents == 1 and #queue.Train.Intents == 0, "PEN chute lane")
		PenService.stopSend(w.player)
		-- level 2 with a belt on the TRAIN chute: the TRAIN lane
		w.data.Upgrades.PenAutomation = 2
		local trainBelt = chuteBelt(w, "Train", 0)
		deliver({ { K = raw.K, O = raw.O }, { K = raw.K, O = raw.O }, { K = clean.K, O = clean.O, G = clean.G } })
		queue = pen.queue(w.player)
		T.eq(queue.Train.Intents[1].Left, 2, "both dirty ores on the TRAIN lane")
		T.eq(#queue.Pen.Intents, 1, "the unkept clean ore on the PEN lane")
		local before = census(w)
		PenService.tickSend(1)
		T.eq(#looseOn(trainBelt), 1, "dirty ore on the TRAIN chute's belt")
		T.eq(looseOn(trainBelt)[1].Kind, "Raw", "dirty")
		T.eq(#looseOn(penBelt), 1, "and the clean one at the PEN chute, at the same time")
		T.eq(census(w), before, "moved, not copied")
		rideAway(trainBelt)
		PenService.tickSend(2)
		T.eq(#looseOn(trainBelt), 1, "the second one")
		T.eq(pen.queue(w.player), nil, "all out")
		-- no belt on the TRAIN chute: as without the upgrade (it stays, or the billboard takes it)
		MachineService.pickup(trainBelt)
		MachineService.pickup(penBelt)
		deliver({ { K = raw.K, O = raw.O } })
		T.eq(pen.queue(w.player), nil, "no belts: it stays in the pen")
	end)

	withWorld("PenService: the sorting board shows what is kept and what the PEN chute does", function(w)
		pen.updateBoard(PLOT)
		T.eq(pen.board(PLOT), nil, "no billboard bought: no board")
		w.data.Upgrades.PenAutomation = 1
		pen.updateBoard(PLOT)
		local board = pen.board(PLOT)
		T.truthy(board, "board built")
		T.eq(board.Model.Parent, PenService.yard(PLOT):FindFirstChild("Pen"), "at the pen")
		T.eq(board.Model:FindFirstChild("Title"):FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text").Text, PenService.BoardTitle, "AUTO-SORT ON")
		T.eq(board.Body.Text, PenService.keepSummary("RarePlus", {}), "what is kept")
		T.truthy(board.Status.Text:find("Put a conveyor", 1, true), "needs a belt")
		local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT])
		for _, d in board.Model:GetDescendants() do
			if d:IsA("BasePart") then
				T.falsy(d.CanCollide, d.Name .. " never blocks")
				local p = plotCF:PointToObjectSpace(d.CFrame.Position)
				T.lt(GameConfig.PlotCells * GameConfig.CellSize / 2 + 1, p.Z, d.Name .. " in the yard, off the grid and its wall")
			end
		end
		local look = plotCF:VectorToObjectSpace(board.Model:FindFirstChild("Board").CFrame.LookVector)
		T.lt(look.Z, -0.99, "faces the grid")
		chuteBelt(w, "Pen", 0)
		pen.updateBoard(PLOT)
		T.truthy(board.Status.Text:find("PEN chute", 1, true), "ready: says where it goes")
		fill(w, DIRTY, 3)
		pen.action(w.player, "Send", { Filter = "Dirty" })
		pen.updateBoard(PLOT)
		T.eq(board.Status.Text, "Sending 3…", "sending")
		w.data.KeepMode = "All"
		pen.updateBoard(PLOT)
		T.eq(board.Body.Text, "Keeps every clean ore", "follows the keep mode")
		w.data.Upgrades.PenAutomation = 0
		pen.updateBoard(PLOT)
		T.eq(pen.board(PLOT), nil, "gone without the upgrade")
		T.eq(PenService.yard(PLOT):FindFirstChild("Pen"):FindFirstChild("SortBoard"), nil, "model removed")
		-- a free plot has no board
		w.data.Upgrades.PenAutomation = 1
		w.free = true
		pen.updateBoard(PLOT)
		T.eq(pen.board(PLOT), nil, "free plot")
	end)

	T.test("PenService: the board's keep summary", function()
		T.eq(PenService.keepSummary("All", {}), "Keeps every clean ore", "all")
		local rare = PenService.keepSummary("RarePlus", {})
		T.eq(rare, "Keeps clean Rare+ ore", "rare and up")
		T.eq(PenService.keepSummary("List", {}), rare, "an empty list keeps like Rare+")
		T.eq(PenService.keepSummary("Bogus", nil), rare, "junk mode: the default")
		local list = PenService.keepSummary("List", { Copper = true, Gold = false })
		T.truthy(list:find("Copper", 1, true), "the kept ore: " .. list)
		T.falsy(list:find("Gold", 1, true), "not the one sent on")
		T.truthy(list:find("Rare+", 1, true), "unset rare ore still kept")
		local many = {}
		local n = 0
		for _, ore in OreData.List do
			many[ore.Id] = true
			n += 1
		end
		local all = PenService.keepSummary("List", many)
		T.truthy(all:find(`+{n - 6} more`, 1, true), "long lists are cut: " .. all)
		T.falsy(all:find("haven't set", 1, true), "everything set")
		local none = {}
		for _, ore in OreData.List do
			none[ore.Id] = false
		end
		T.eq(PenService.keepSummary("List", none), "Keeps no clean ore you set", "nothing kept")
	end)

	---------------------------------------------------------------- PenView (pure)

	T.test("PenView: rows sorted by income, dirty ore last and hidden", function()
		local summary = {
			["Raw|Diamond||"] = 3,
			["Clean|Copper|Rough|"] = 2,
			["Clean|Gold|Flawless|"] = 1,
			["Ingot|Iron|Clean|"] = 4,
			["Clean|Bogus||"] = 9,
			[42] = 1,
			["Clean|Iron|Clean|"] = 0,
		}
		local rows = PenView.entries(summary, "Pen")
		T.eq(#rows, 4, "junk and zero counts skipped")
		T.eq(rows[1].Key, "Clean|Gold|Flawless|", "best income first")
		T.eq(rows[2].Key, "Clean|Copper|Rough|", "then cheaper clean ore")
		T.eq(rows[3].Kind, "Ingot", "other kinds after podium ore")
		T.eq(rows[4].Key, PenView.DirtyKey, "dirty ore last, as one merged row")
		T.eq(rows[4].Name, ItemData.DirtyName, "shown as Dirty Ore")
		T.truthy(rows[4].Mystery, "question mark icon")
		T.eq(rows[4].Income, 0, "no income")
		T.eq(rows[4].Value, 0, "no value hint")
		T.eq(rows[4].Color, PenView.DirtyColor, "no rarity colour")
		T.eq(rows[4].Grade, nil, "no grade chip")
		T.near(rows[1].Income, ItemData.income(ItemData.parseKey("Clean|Gold|Flawless|")), 1e-9, "income per second")
		local pick = PenView.entries(summary, "Pick")
		T.eq(#pick, 2, "pick mode: podium ore only")
		T.eq(#PenView.entries(nil, "Pen"), 0, "no summary")
		T.eq(#PenView.entries("x", "Pen"), 0, "junk summary")
		-- different hidden ores never show as separate rows
		local mixed = PenView.entries({ ["Raw|Coal||"] = 4, ["Raw|Heartstone||"] = 1 }, "Pen")
		T.eq(#mixed, 1, "one Dirty Ore row")
		T.eq(mixed[1].Count, 5, "counts added up")
		T.eq(PenView.keyFor(mixed[1], 0), "Raw|Coal||", "a roll picks a real key")
		T.eq(PenView.keyFor(mixed[1], 0.95), "Raw|Heartstone||", "weighted by count")
		T.eq(PenView.keyFor(rows[1], 0.5), rows[1].Key, "normal rows keep their key")
	end)

	T.test("PenView: the first free unlocked podium slot", function()
		T.eq(PenView.freeSlot({ "", "", "", "" }, 2), 1, "slot 1")
		T.eq(PenView.freeSlot({ GOLD, "", "", "" }, 2), 2, "slot 2")
		T.eq(PenView.freeSlot({ GOLD, GOLD, "", "" }, 2), nil, "3 and 4 locked")
		T.eq(PenView.freeSlot({ GOLD, GOLD, "", "" }, 4), 3, "unlocked with the perk")
		T.eq(PenView.freeSlot(nil, 4), nil, "no data")
		T.eq(PenView.freeSlot({ GOLD, GOLD, "", "" }, 99), 3, "slots clamp to the max")
		T.eq(PenView.freeSlot({ "", "" }, nil), 1, "default = free slots")
	end)

	T.test("PenView: the pile shows at most ShowMax items, a bit of everything", function()
		local max = BaseLayout.Pen.ShowMax
		local counts = PenView.pileCounts({ [GOLD] = 100, [DIRTY] = 100, ["Clean|Copper|Rough|"] = 1 }, max)
		local total = 0
		for _, n in counts do
			total += n
		end
		T.eq(total, max, "capped")
		T.eq(counts["Clean|Copper|Rough|"], 1, "the single copper shows")
		T.truthy(counts[GOLD] >= 11 and counts[DIRTY] >= 11, "both big piles show")
		local small = PenView.pileCounts({ [GOLD] = 2 }, max)
		T.eq(small[GOLD], 2, "small pen shows all")
		T.eq(next(PenView.pileCounts({}, max)), nil, "empty pen")
	end)

	T.test("PenView: builds, switches modes and the phone layout", function()
		local refs = PenView.build()
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "HUD scale applies")
		T.falsy(refs.Gui.Enabled, "starts closed")
		PenView.setHeader(refs, 37, 40)
		T.eq(refs.Header.Text, "37 / 40", "count")
		local rows = PenView.entries({ [GOLD] = 3, [DIRTY] = 5 }, "Pen")
		local created = PenView.setEntries(refs, rows, true)
		T.eq(#created, 2, "two rows")
		local gold = refs.Rows[GOLD]
		T.truthy(gold.Podium.Parent.Visible, "podium button for clean ore")
		T.truthy(gold.Take.Parent.Visible, "take button")
		T.eq(gold.Count.Text, "x3", "count")
		T.truthy(gold.Grade.Visible, "grade chip")
		T.falsy(refs.Rows[PenView.DirtyKey].Podium.Parent.Visible, "no podium for dirty ore")
		T.truthy(refs.Rows[PenView.DirtyKey].Mystery.Visible, "question mark")
		PenView.setEntries(refs, rows, false)
		T.falsy(gold.Podium.Parent.Visible, "no free slot: no podium button")
		PenView.setMode(refs, "Pick", 3)
		T.truthy(refs.Title.Text:find("PODIUM 3", 1, true), "pick title")
		PenView.setEntries(refs, PenView.entries({ [GOLD] = 3, [DIRTY] = 5 }, "Pick"), false)
		T.eq(refs.Rows[PenView.DirtyKey], nil, "dirty row removed in pick mode")
		T.eq(gold.Podium.Text, "PLACE", "place button")
		T.falsy(gold.Take.Parent.Visible, "no take in pick mode")
		local normalHeight = refs.Panel.Size.Y.Offset
		PenView.setCompact(refs, true)
		T.le(72, gold.Podium.Parent.Size.Y.Offset, "touch buttons >= 44 pt at 0.62 scale")
		T.truthy(refs.Panel.Size.Y.Offset * 0.62 <= 375 - 36, "fits a small phone")
		T.truthy(normalHeight > 0, "layout height")
		PenView.setEntries(refs, {}, false)
		T.truthy(refs.Empty.Visible, "empty text")
		-- gamepad footer: the platform's glyphs instead of key names
		PenView.setHint(refs, "", "rbxasset://a.png", "rbxasset://b.png")
		T.truthy(refs.PadHint.Visible, "glyph hint")
		T.falsy(refs.Hint.Visible, "no text hint")
		T.eq(refs.PadA.Image, "rbxasset://a.png", "A glyph")
		T.eq(refs.PadAText.Text, "place", "pick mode says place")
		PenView.setMode(refs, "Pen", nil)
		PenView.setHint(refs, "Backspace: close", nil, nil)
		T.falsy(refs.PadHint.Visible, "mouse: text again")
		T.eq(refs.Hint.Text, "Backspace: close", "text hint")
	end)

	T.test("PenView: the send toolbar, SEND on every row, both layouts", function()
		local idle = PenView.SendIdleText
		T.eq((PenView.sendText(nil)), idle, "no State yet")
		local text, waiting, total = PenView.sendText({ Pen = 3, Train = 2 })
		T.eq(text, "Sending 5…", "both lanes")
		T.falsy(waiting, "not waiting")
		T.eq(total, 5, "total")
		text, waiting = PenView.sendText({ Pen = 2, Train = 0, Wait = "Put a conveyor on your PEN chute" })
		T.eq(text, "2 waiting: Put a conveyor on your PEN chute", "why it waits")
		T.truthy(waiting, "waiting")
		T.eq((PenView.sendText({ Pen = 0, Train = 0, Wait = "x" })), idle, "nothing queued: no wait line")
		T.eq((PenView.sendText({ Pen = "3", Train = 0 / 0 })), idle, "junk counts")
		T.eq(select(3, PenView.sendText({ Pen = math.huge })), 0, "no infinity")

		local refs = PenView.build()
		T.truthy(refs.Toolbar.Visible, "toolbar in pen mode")
		PenView.setSending(refs, { Pen = 2, Train = 0 }, false, 3)
		T.truthy(refs.StopSend.Parent.Visible, "STOP while sending")
		T.falsy(refs.SendUnkept.Parent.Visible, "no billboard: no SEND UNKEPT")
		T.eq(refs.Status.Text, "Sending 2…", "status")
		PenView.setSending(refs, nil, true, 0)
		T.falsy(refs.StopSend.Parent.Visible, "nothing to stop")
		T.truthy(refs.SendUnkept.Parent.Visible, "billboard: SEND UNKEPT")
		T.near(refs.SendDirty.TextTransparency, 0.4, 1e-4, "dimmed without dirty ore")
		local rows = PenView.entries({ [GOLD] = 3, [DIRTY] = 5 }, "Pen")
		PenView.setEntries(refs, rows, true)
		local gold = refs.Rows[GOLD]
		T.truthy(gold.Send.Parent.Visible, "SEND on a clean row")
		T.truthy(refs.Rows[PenView.DirtyKey].Send.Parent.Visible, "SEND on the dirty row")
		for _, compact in { false, true } do
			PenView.setCompact(refs, compact)
			local take, send, podium = gold.Take.Parent, gold.Send.Parent, gold.Podium.Parent
			local function right(f: any): number
				return f.Position.X.Offset + f.Size.X.Offset
			end
			T.le(right(gold.Count), take.Position.X.Offset, "count left of TAKE")
			T.le(right(take), send.Position.X.Offset, "TAKE left of SEND")
			T.le(right(send), podium.Position.X.Offset, "SEND left of PODIUM")
			T.le(right(podium), gold.Frame.Size.X.Offset, "inside the row")
			T.le(0, gold.Name.Size.X.Offset - 120, "room for the name")
			if compact then
				T.le(72, send.Size.Y.Offset, "touch-sized SEND")
				T.le(72, refs.SendDirty.Parent.Size.Y.Offset, "touch-sized toolbar")
				T.truthy(refs.Panel.Size.Y.Offset * 0.62 <= 375 - 36, "fits a small phone")
			end
			local used = 0
			for _, button in { refs.SendDirty, refs.SendUnkept, refs.StopSend } do
				used += button.Parent.Size.X.Offset + 8
			end
			T.le(used + refs.Status.Size.X.Offset, refs.Panel.Size.X.Offset - 32 + 1, "toolbar fits the panel")
			T.eq(refs.List.Position.Y.Offset, refs.Toolbar.Position.Y.Offset + refs.Toolbar.Size.Y.Offset, "list under the toolbar")
		end
		-- pick mode: no toolbar, no TAKE / SEND
		PenView.setMode(refs, "Pick", 1)
		PenView.setEntries(refs, PenView.entries({ [GOLD] = 3 }, "Pick"), false)
		T.falsy(refs.Toolbar.Visible, "no toolbar")
		T.falsy(gold.Send.Parent.Visible, "no SEND")
		T.eq(refs.List.Position.Y.Offset, refs.Toolbar.Position.Y.Offset, "list moves up")
	end)
end
