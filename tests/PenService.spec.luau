-- PenService under Lune: pen capacity, the intake box (owner only, full pen
-- bounces), Put In, Take limits, ToPodium, bad inputs, the send queue (step 3:
-- intents only, one item at a time onto the PEN / TRAIN chute belts, filters,
-- SEND then ALL = exactly the stack, Stop, leaving, junk, broken entries,
-- errors half way), the sorting billboard (on / off, arrivals only, full
-- queue, re-checked when an item leaves, the first-send toast), the TRAIN
-- lane's Direct Unload from a train's cargo (its own wait reason), and the
-- pure parts of PenView (rows, free podium slot, pile selection, the send
-- toolbar per lane, SEND / ALL, the AUTO-SORT switch, HUD room).
-- The plot is built by the real PlotBuilder, machines and belts are real;
-- players, saves, carrying and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Vector2 = roblox.Vector2
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
		-- every loose item here stands for one at the base (belts, chutes, the
		-- pen gate): the factory's loose cap counts only those (looseCount "Base")
		patch(ItemService, "onBase", function()
			return true
		end)
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

	withWorld("PenService: a pen over its capacity takes nothing new (PenOver); Take and Send still work", function(w)
		local capacity = PenService.capacity(w.player)
		-- a rescue move overfilled it (leaving, an item back from another plot...)
		fill(w, DIRTY, capacity + 4)
		T.truthy(PenService.isOver(w.data), "over its capacity")
		T.eq(PenService.OverReason, "PenOver", "one reason code")
		T.eq(PenService.refusal(w.data), "PenOver", "refusal")
		T.falsy(PenService.hasRoom(w.player), "no room (the Iron Box keep route)")
		local stored, why = PenService.store(w.player, { K = "Raw", O = "Coal" })
		T.falsy(stored, "the sinks can't store")
		T.eq(why, "PenOver", "and learn why")
		T.eq(#w.data.Storage, capacity + 4, "nothing went in")
		-- thrown in: bounced, with the over-capacity toast (throttled)
		local record = itemInPen(w, USER, { K = "Clean", O = "Gold", G = "Pristine" })
		w.zone.Handler(record)
		T.eq(record.State, "Loose", "not taken")
		T.falsy(insideIntake(w, record.Body.CFrame.Position), "bounced out of the gate")
		T.eq(lastNote(w, "Notify").A.Text, PenService.overText(w.data), "says it holds too much")
		local toasts = count(w, "Notify")
		w.zone.Handler(itemInPen(w, USER, { K = "Raw", O = "Coal" }))
		T.eq(count(w, "Notify"), toasts, "throttled")
		-- Put In: refused, the hands keep everything
		for i = 1, 2 do
			local carried = ItemService.spawnDesc({ K = "Raw", O = "Copper" }, USER, CFrame.new(i, 5, 0), nil, true)
			carried.State = "Carried"
			table.insert(w.carried, carried)
		end
		T.eq(pen.putIn(w.player, PLOT), "PenOver", "Put In refused")
		T.eq(#w.carried, 2, "nothing taken from the hands")
		T.eq(#w.data.Storage, capacity + 4, "nothing stored")
		T.eq(lastNote(w, "Notify").A.Text, PenService.overText(w.data), "told why")
		-- the State shows it (PenView turns red)
		local snapshot = {}
		pen.provide(w.player, w.data, snapshot)
		T.eq(snapshot.PenOver, true, "PenOver in the State")
		T.eq(snapshot.PenCapacity, capacity, "with the capacity")
		-- Take still works
		w.hands = 6
		pen.action(w.player, "Take", { Key = DIRTY, Count = 3 })
		T.eq(#w.data.Storage, capacity + 1, "Take works while over")
		-- Send still works
		pen.action(w.player, "Send", { Key = DIRTY, Count = 1 })
		local queue = pen.queue(w.player)
		T.truthy(queue and #queue.Pen.Intents == 1, "Send works while over")
		pen.action(w.player, "Take", { Key = DIRTY, Count = 1 })
		-- exactly full now: not over, just full
		T.falsy(PenService.isOver(w.data), "back at the capacity")
		T.eq(PenService.refusal(w.data), "PenFull", "full, not over")
		snapshot = {}
		pen.provide(w.player, w.data, snapshot)
		T.eq(snapshot.PenOver, false, "PenOver off")
		-- one below: Put In works again
		table.remove(w.data.Storage)
		T.eq(pen.putIn(w.player, PLOT), "PenFull", "one went in, the next one doesn't fit")
		T.eq(#w.data.Storage, capacity, "filled up to the capacity, never over")
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

	withWorld("PenService: Take never goes past the hard ceiling of loose items (items lying in the mine count)", function(w)
		fill(w, GOLD, 4)
		w.hands = 0
		-- this test's items lie away from bases (the harness counts them as base items)
		local onBase = rawget(ItemService, "onBase")
		rawset(ItemService, "onBase", function()
			return false
		end)
		local ok, err = pcall(function()
			for i = 1, GameConfig.MaxLooseItemsTotal do
				ItemService.spawnDesc({ K = "Raw", O = "Coal" }, USER, CFrame.new(i * 3, 5, 400), nil, true)
			end
			T.eq(ItemService.looseCount(USER, "Base"), 0, "none at the base")
			T.eq(ItemService.totalRoom(USER), 0, "at the hard ceiling")
			pen.action(w.player, "Take", { Key = GOLD, Count = 1 })
			T.eq(inPen(w, GOLD), 4, "nothing taken onto the ground")
		end)
		rawset(ItemService, "onBase", onBase)
		if not ok then
			error(err, 0)
		end
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

	-- the State's PenSend { Pen, Train, PenWait?, TrainWait? }
	local function sendState(w: any): any
		local snapshot: any = {}
		pen.provide(w.player, w.data, snapshot)
		return snapshot.PenSend
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
		T.truthy(sendState(w).PenWait:find("Put a conveyor", 1, true), "the State says why")
		-- a belt facing the yard is no good either
		local m = chuteBelt(w, "Pen", BaseLayout.SinkRotation)
		PenService.tickSend(2)
		T.eq(inPen(w, GOLD), 3, "facing the yard: nothing leaves")
		T.truthy(sendState(w).PenWait:find("away from the yard", 1, true), "turn the belt")
		MachineService.move(m, m.X, m.Z, 0)
		PenService.tickSend(3)
		T.eq(inPen(w, GOLD), 2, "one left the pen")
		local out = looseOn(m)
		T.eq(#out, 1, "it rides the PEN chute's belt")
		T.eq(out[1].Kind, "Clean", "the right item")
		T.eq(out[1].OreId, "Gold", "the right ore")
		T.eq(census(w), total, "moved, not copied")
		T.eq(sendState(w).Pen, 1, "one to go")
		T.eq(sendState(w).PenWait, nil, "not waiting")
		PenService.tickSend(3.1)
		T.eq(inPen(w, GOLD), 2, "one item every SendInterval")
		PenService.tickSend(3 + PenService.SendInterval)
		T.eq(inPen(w, GOLD), 2, "the first still lies on the chute: waits")
		T.truthy(sendState(w).PenWait:find("full", 1, true), "jammed")
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

	withWorld("PenService: a billboard intent only sends ore that is still unkept when it leaves", function(w)
		local copper = { K = "Clean", O = "Copper", G = "Rough" }
		w.data.Upgrades.PenAutomation = 1
		local m = chuteBelt(w, "Pen", 0)
		-- the belt is full for now: the queued copper waits in the pen
		local blocker = ItemService.spawnDesc({ K = "Raw", O = "Coal" }, USER, m.Model:GetPivot() * CFrame.new(0, 1.5, 0), nil, true)
		fill(w, COPPER_CLEAN, 1) -- an older copy the player keeps in the pen
		w.zone.Handler(itemInPen(w, USER, copper))
		T.eq(inPen(w, COPPER_CLEAN), 2, "both in the pen")
		T.eq(sendState(w).Pen, 1, "the new one is queued (Rare+: copper isn't kept)")
		local total = census(w)
		PenService.tickSend(1)
		T.eq(inPen(w, COPPER_CLEAN), 2, "the belt is full: it waits")
		-- meanwhile the player marks copper Keep in the Iron Box view
		w.data.KeepMode = "List"
		w.data.KeepList = { Copper = true }
		T.eq(sendState(w).Pen, 0, "nothing to send any more")
		blocker.Model:PivotTo(CFrame.new(0, 500, 0))
		for step = 2, 5 do
			PenService.tickSend(step)
		end
		T.eq(inPen(w, COPPER_CLEAN), 2, "kept now: neither copy leaves")
		T.eq(#looseOn(m), 0, "nothing on the belt")
		T.eq(pen.queue(w.player), nil, "the billboard's intent ended")
		T.eq(census(w), total, "nothing lost")
		-- unkept again: only what arrives from now on is sorted (the pen's copies stay)
		w.data.KeepList = { Copper = false }
		PenService.tickSend(6)
		T.eq(inPen(w, COPPER_CLEAN), 2, "an ended intent doesn't come back")
		-- the player's own SEND of a kept ore still works (only Auto intents re-check)
		w.data.KeepList = { Copper = true }
		pen.action(w.player, "Send", { Key = COPPER_CLEAN, Count = 1 })
		PenService.tickSend(7)
		T.eq(inPen(w, COPPER_CLEAN), 1, "sent on purpose")
	end)

	withWorld("PenService: SEND then ALL sends exactly the stack, nothing extra stays queued", function(w)
		fill(w, GOLD, 4)
		local m = chuteBelt(w, "Pen", 0)
		local blocker = ItemService.spawnDesc({ K = "Raw", O = "Coal" }, USER, m.Model:GetPivot() * CFrame.new(0, 1.5, 0), nil, true)
		-- SEND (one), then ALL x4? while the first one still waits in the pen
		pen.action(w.player, "Send", { Key = GOLD, Count = 1 })
		PenService.tickSend(1)
		T.eq(inPen(w, GOLD), 4, "the first one waits (belt full)")
		pen.action(w.player, "Send", { Key = GOLD, All = true })
		local queue = pen.queue(w.player)
		T.eq(#queue.Pen.Intents, 1, "one intent")
		T.eq(queue.Pen.Intents[1].Left, 4, "all four: the queued one is part of them, not on top")
		T.eq(sendState(w).Pen, 4, "the State agrees")
		blocker.Model:PivotTo(CFrame.new(0, 500, 0))
		for step = 1, 12 do
			rideAway(m)
			PenService.tickSend(10 + step)
		end
		T.eq(inPen(w, GOLD), 0, "the whole stack went")
		T.eq(pen.queue(w.player), nil, "and the queue is empty")
		-- a new gold arriving later stays in the pen
		fill(w, GOLD, 1)
		PenService.tickSend(30)
		T.eq(inPen(w, GOLD), 1, "not sent: no leftover intent")
		-- after the first one left: ALL is what is left (the stack the button shows then)
		fill(w, GOLD, 2)
		pen.action(w.player, "Send", { Key = GOLD, Count = 1 })
		PenService.tickSend(31)
		T.eq(inPen(w, GOLD), 2, "one out")
		pen.action(w.player, "Send", { Key = GOLD, All = true })
		T.eq(sendState(w).Pen, 2, "the two left")
		for step = 1, 8 do
			rideAway(m)
			PenService.tickSend(40 + step)
		end
		T.eq(inPen(w, GOLD), 0, "all out")
		-- counts add up ("one more"), but never past what is in the pen
		fill(w, DIRTY, 2)
		ItemService.spawnDesc({ K = "Raw", O = "Coal" }, USER, m.Model:GetPivot() * CFrame.new(0, 1.5, 0), nil, true)
		for _ = 1, 5 do
			pen.action(w.player, "Send", { Filter = "Dirty", Count = 1 })
		end
		T.eq(pen.queue(w.player).Pen.Intents[1].Left, 2, "five presses, two dirty ores: two")
		pen.action(w.player, "Send", { Filter = "Dirty" })
		T.eq(pen.queue(w.player).Pen.Intents[1].Left, 2, "all of them: still two")
		-- junk All requests change nothing
		PenService.stopSend(w.player)
		fill(w, GOLD, 2)
		for _, arg in
			{ { Key = GOLD, All = "yes" }, { Key = GOLD, All = true, Count = 2 }, { Filter = "Dirty", All = true }, { All = true } }
		do
			pen.action(w.player, "Send", arg)
		end
		T.eq(pen.queue(w.player), nil, "nothing queued")
	end)

	withWorld("PenService: the first time auto-sort sends ore away, a toast says so (once a session)", function(w)
		local copper = { K = "Clean", O = "Copper", G = "Rough" }
		w.data.Upgrades.PenAutomation = 1
		chuteBelt(w, "Pen", 0)
		local function told(): number
			local n = 0
			for _, note in w.notes do
				if note.Name == "Notify" and note.A.Text == PenService.AutoFirstText then
					n += 1
				end
			end
			return n
		end
		w.zone.Handler(itemInPen(w, USER, { K = "Clean", O = "Gold", G = "Pristine" }))
		T.eq(told(), 0, "kept ore: nothing to say")
		w.zone.Handler(itemInPen(w, USER, copper))
		T.eq(told(), 1, "the first ore sent on: told where to switch it off")
		T.truthy(PenService.AutoFirstText:find("switch it off", 1, true), "says how to stop it")
		w.zone.Handler(itemInPen(w, USER, copper))
		PenService.arrived(w.player, { { K = "Raw", O = "Coal" } }, "Train")
		T.eq(told(), 1, "only once")
	end)

	withWorld("PenService: the TRAIN lane pours a train's dirty ore straight from its cargo, never through the pen", function(w)
		-- a fake unloading train: TrainService registers the real one (TrainService spec)
		local cargo: { any } = {
			{ K = "Raw", O = "Gold" },
			{ K = "Clean", O = "Copper", G = "Rough" }, -- not for the chute: stays for the pen
			{ K = "Raw", O = "Coal" },
			{ K = "Raw", O = "Unobtainium" }, -- a broken entry: never taken
			{ K = "Raw", O = "Iron" },
		}
		local unloading = true
		local sent, failed = 0, 0
		PenService.setTrainCargo({
			list = function(p, data)
				T.truthy(p == w.player and data == w.data, "asked for the owner")
				return if unloading then cargo else nil
			end,
			sent = function(_, ok)
				if ok then
					sent += 1
				else
					failed += 1
				end
			end,
		})
		-- a full pen doesn't matter: nothing goes through it
		w.data.Upgrades.PenLevel = 0
		fill(w, GOLD, PenService.capacity(w.player))
		local penBefore = #w.data.Storage
		local function census2(): number
			return #w.data.Storage + #cargo + #ItemService.ownedBy(USER)
		end
		local total = census2()
		local trainBelt = chuteBelt(w, "Train", 0)
		T.truthy(PenService.unloadTrain(w.player), "Cargo intent added")
		T.falsy(PenService.unloadTrain(w.player), "only once")
		local queue = pen.queue(w.player)
		T.eq(#queue.Train.Intents, 1, "one Cargo intent")
		T.eq(#queue.Pen.Intents, 0, "nothing for the pen's lane")
		T.eq(select(2, PenService.sendCounts(w.player)), 3, "three spawnable dirty ores to go")
		PenService.tickSend(1)
		T.eq(#looseOn(trainBelt), 1, "one on the TRAIN chute's belt")
		T.eq(looseOn(trainBelt)[1].OreId, "Gold", "front to back")
		T.eq(#cargo, 4, "taken off the train")
		T.eq(#w.data.Storage, penBefore, "the pen never saw it")
		T.eq(sent, 1, "TrainService told")
		T.eq(census2(), total, "moved, not copied")
		-- 2 per second: not before SendInterval
		rideAway(trainBelt)
		PenService.tickSend(1 + PenService.SendInterval / 2)
		T.eq(#cargo, 4, "one item every SendInterval")
		-- the belt is jammed: the item stays on the train, same place
		local blocker =
			ItemService.spawnDesc({ K = "Raw", O = "Copper" }, USER, trainBelt.Model:GetPivot() * CFrame.new(0, 1.5, 0), nil, true)
		total += 1
		PenService.tickSend(2)
		T.eq(#cargo, 4, "jammed: nothing taken")
		T.truthy(sendState(w).TrainWait:find("TRAIN chute", 1, true), "the State says why, for the train's lane")
		T.eq(sendState(w).PenWait, nil, "the pen's lane isn't the one waiting")
		T.eq(PenService.laneWait(w.player, "Train"), "Jammed", "TrainService reads the reason (UnloadWait)")
		T.eq(PenService.laneWait(w.player, "Pen"), nil, "nothing for the pen")
		blocker.Model:PivotTo(CFrame.new(0, 500, 0))
		PenService.tickSend(3)
		T.eq(#cargo, 3, "the next one")
		T.eq(looseOn(trainBelt)[1].OreId, "Coal", "the coal")
		T.eq(cargo[1].K, "Clean", "the clean ore stays on board for the pen")
		T.eq(census2(), total, "still nothing lost")
		-- StopSend is the pen's: the train goes on
		pen.action(w.player, "StopSend", nil)
		T.truthy(pen.queue(w.player) and #pen.queue(w.player).Train.Intents == 1, "the train's unload goes on")
		rideAway(trainBelt)
		PenService.tickSend(4)
		T.eq(#cargo, 2, "the iron")
		T.eq(cargo[2].O, "Unobtainium", "the broken entry is never taken")
		rideAway(trainBelt)
		PenService.tickSend(5)
		T.eq(pen.queue(w.player), nil, "no dirty ore left that can spawn: done")
		T.eq(sent, 3, "three sent")
		T.eq(failed, 0, "no failure")
		T.eq(census2(), total, "every item in exactly one place")
		-- the train stops unloading that way (belt gone, trip over): the intent just ends
		table.insert(cargo, { K = "Raw", O = "Gold" })
		PenService.unloadTrain(w.player)
		unloading = false
		PenService.tickSend(6)
		T.eq(pen.queue(w.player), nil, "dropped")
		T.eq(#cargo, 3, "still on the train")
		-- spawning that fails for good: the item stays, TrainService hears it
		unloading = true
		PenService.unloadTrain(w.player)
		local original = ItemService.spawnDesc
		rawset(ItemService, "spawnDesc", function()
			error("broken")
		end)
		local ok, err = pcall(PenService.tickSend, 7)
		rawset(ItemService, "spawnDesc", original)
		assert(ok, err)
		T.eq(#cargo, 3, "kept on the train")
		T.eq(failed, 1, "TrainService told it failed")
		T.eq(pen.queue(w.player), nil, "and the lane is free")
	end)

	withWorld("PenService: broken pen entries never block a lane, and spawning that breaks keeps the count", function(w)
		local m = chuteBelt(w, "Pen", 0)
		fill(w, DIRTY, 2)
		-- the newest entries are junk an old save could hold: they would be picked first
		table.insert(w.data.Storage, { K = "Raw", O = "Unobtainium" })
		table.insert(w.data.Storage, { K = "Shiny", O = "Copper" })
		table.insert(w.data.Storage, { K = "Raw", O = "Copper", G = 5 })
		table.insert(w.data.Storage, { K = "Clean", O = "Gold", G = "Clean", R = {} })
		pen.action(w.player, "Send", { Filter = "All" })
		T.eq(sendState(w).Pen, 2, "only what can become an item counts")
		for step = 1, 6 do
			rideAway(m)
			PenService.tickSend(step)
		end
		T.eq(inPen(w, DIRTY), 0, "both dirty ores went out")
		T.eq(#w.data.Storage, 4, "the junk stays in the pen")
		T.eq(pen.queue(w.player), nil, "and the lane is done, not stuck")
		-- an error half way through spawning: one item stays in exactly one place
		rideAway(m)
		fill(w, GOLD, 2)
		local total = census(w)
		local original = ItemService.spawnDesc
		local ok, err = pcall(function()
			rawset(ItemService, "spawnDesc", function(...)
				local record = original(...)
				record.Model.Parent = nil
				error("SetAttribute broke")
			end)
			pen.action(w.player, "Send", { Key = GOLD, Count = 2 })
			PenService.tickSend(20)
		end)
		rawset(ItemService, "spawnDesc", original)
		assert(ok, err)
		T.eq(inPen(w, GOLD), 2, "back in the pen")
		T.eq(census(w), total, "no ghost item that would be stored again later")
		T.eq(pen.queue(w.player), nil, "the intent is dropped, nothing retries forever")
		-- an error after the item was made completely: unmade, so it is in the pen once
		ok, err = pcall(function()
			rawset(ItemService, "spawnDesc", function(...)
				original(...)
				error("broke after")
			end)
			pen.action(w.player, "Send", { Key = GOLD, Count = 1 })
			PenService.tickSend(30)
		end)
		rawset(ItemService, "spawnDesc", original)
		assert(ok, err)
		T.eq(inPen(w, GOLD), 2, "still in the pen")
		T.eq(census(w), total, "and nowhere else")
		-- once spawning works again it goes out normally
		pen.action(w.player, "Send", { Key = GOLD, Count = 1 })
		PenService.tickSend(40)
		T.eq(inPen(w, GOLD), 1, "one left the pen")
		T.eq(census(w), total, "and exists once, on the belt")
	end)

	withWorld("PenService: auto-sort can be switched off; only arrivals are sorted; a full queue says so", function(w)
		local copper = { K = "Clean", O = "Copper", G = "Rough" }
		w.data.Upgrades.PenAutomation = 1
		chuteBelt(w, "Pen", 0)
		T.truthy(PenService.autoSortOn(w.data), "on by default")
		local s = {}
		pen.provide(w.player, w.data, s)
		T.eq(s.AutoSort, true, "the State says so")
		w.zone.Handler(itemInPen(w, USER, copper))
		fill(w, DIRTY, 2)
		pen.action(w.player, "Send", { Key = DIRTY, Count = 2 })
		local queue = pen.queue(w.player)
		T.eq(#queue.Pen.Intents, 2, "the billboard's and the player's")
		-- switching off from anywhere drops what the billboard queued
		w.player.stand(w.gate.Position + Vector3.new(0, 0, 300))
		pen.action(w.player, "AutoSort", { On = false })
		T.eq(w.data.AutoSort, false, "saved")
		T.eq(lastNote(w, "Notify").A.Text, PenService.AutoOffText, "told")
		T.eq(#queue.Pen.Intents, 1, "the player's own SEND goes on")
		T.eq(queue.Pen.Intents[1].Key, DIRTY, "that one")
		pen.updateBoard(PLOT)
		T.eq(pen.board(PLOT).Title.Text, PenService.BoardTitleOff, "the board says OFF")
		T.truthy(pen.board(PLOT).Status.Text:find("stays", 1, true), "and what that means")
		w.zone.Handler(itemInPen(w, USER, copper))
		T.eq(#queue.Pen.Intents, 1, "off: arrivals stay in the pen")
		s = {}
		pen.provide(w.player, w.data, s)
		T.eq(s.AutoSort, false, "the State says off")
		pen.action(w.player, "AutoSort", { On = true })
		T.eq(w.data.AutoSort, true, "on again")
		T.eq(lastNote(w, "Notify").A.Text, PenService.AutoOnText, "told how keeping works")
		pen.updateBoard(PLOT)
		T.eq(pen.board(PLOT).Title.Text, PenService.BoardTitle, "the board says ON")
		local notes = #w.notes
		pen.action(w.player, "AutoSort", { On = true })
		T.eq(#w.notes, notes, "no change: quiet")
		for _, junk in { { On = "yes" }, { On = 1 }, {}, "On" } do
			pen.action(w.player, "AutoSort", junk)
		end
		T.eq(w.data.AutoSort, true, "junk changes nothing")
		-- without the billboard there is nothing to switch
		w.data.Upgrades.PenAutomation = 0
		pen.action(w.player, "AutoSort", { On = false })
		T.eq(w.data.AutoSort, true, "needs the upgrade")
		w.data.Upgrades.PenAutomation = 1
		-- only what a player brings: a sink or a machine must store, never arrive
		local before = #queue.Pen.Intents
		PenService.arrived(w.player, { { K = "Ingot", O = "Iron", G = "Clean" } }, "Factory" :: any)
		T.eq(#queue.Pen.Intents, before, "a 'Factory' arrival is ignored (no loop through the PEN chute)")
		-- a full queue: told, the rest stays in the pen
		PenService.stopSend(w.player)
		local descs = {}
		T.lt(PenService.MaxIntents, #OreData.List, "enough ores to fill the queue")
		for i = 1, math.min(#OreData.List, PenService.MaxIntents + 3) do
			local ore = OreData.List[i]
			table.insert(descs, { K = "Ingot", O = ore.Id, G = "Clean" })
		end
		PenService.arrived(w.player, descs, "Train")
		T.eq(#pen.queue(w.player).Pen.Intents, PenService.MaxIntents, "capped")
		T.eq(lastNote(w, "Notify").A.Text, PenService.QueueFullText, "told the queue is full")
	end)

	withWorld("PenService: the sorting board shows what is kept and what the PEN chute does", function(w)
		pen.updateBoard(PLOT)
		T.eq(pen.board(PLOT), nil, "no billboard bought: no board")
		w.data.Upgrades.PenAutomation = 1
		pen.updateBoard(PLOT)
		local board = pen.board(PLOT)
		T.truthy(board, "board built")
		T.eq(board.Model.Parent, PenService.yard(PLOT):FindFirstChild("Pen"), "at the pen")
		T.eq(
			board.Model:FindFirstChild("Title"):FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text").Text,
			PenService.BoardTitle,
			"AUTO-SORT ON"
		)
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

	T.test("PenView: +$X/s counts the income bonus like the podium tags (State Bonuses.IncomePct)", function()
		local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
		local base = ItemData.income(ItemData.parseKey(GOLD))
		T.truthy(base > 0, "gold earns on a podium")
		T.eq(PenView.incomeMult({ IncomePct = 0.25 }), 1.25, "1 + IncomePct")
		for _, junk in { nil, {}, { IncomePct = -1 }, { IncomePct = 0 / 0 }, { IncomePct = math.huge }, { IncomePct = "2" }, 5 } do
			T.eq(PenView.incomeMult(junk), 1, "junk bonus: none")
		end
		local plain = PenView.entries({ [GOLD] = 2, [DIRTY] = 1 }, "Pen")
		local boosted = PenView.entries({ [GOLD] = 2, [DIRTY] = 1 }, "Pen", PenView.incomeMult({ IncomePct = 0.5 }))
		local function gold(list: { any }): any
			for _, entry in list do
				if entry.Key == GOLD then
					return entry
				end
			end
			return nil
		end
		T.near(gold(plain).Income, base, 1e-9, "no bonus: the base income")
		T.near(gold(boosted).Income, base * 1.5, 1e-9, "with the bonus")
		T.near(
			gold(PenView.entries({ [GOLD] = 1 }, "Pick", PenView.incomeMult({ IncomePct = 0.5 }))).Income,
			base * 1.5,
			1e-9,
			"pick mode too"
		)
		T.near(gold(PenView.entries({ [GOLD] = 1 }, "Pen", 0 / 0)).Income, base, 1e-9, "a junk multiplier counts as 1")
		for _, entry in boosted do
			if entry.Kind == "Raw" then
				T.eq(entry.Income, 0, "dirty ore never earns")
			end
		end
		-- the row shows it
		local refs = PenView.build()
		PenView.setEntries(refs, boosted, true)
		T.eq(refs.Rows[GOLD].Income.Text, Format.perSecond(base * 1.5), "the row's +$X/s")
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
		-- over its capacity (State PenOver): red, and the idle status line says why
		T.falsy(PenView.isOver(40, 40), "full is not over")
		T.truthy(PenView.isOver(44, 40), "over")
		PenView.setSending(refs, nil, false, 0)
		PenView.setHeader(refs, 44, 40)
		T.eq(refs.Header.Text, "44 / 40", "over count")
		T.eq(refs.Status.Text, PenView.OverText, "the status line says why")
		PenView.setSending(refs, { Pen = 2, Train = 0 }, false, 0)
		PenView.setHeader(refs, 44, 40)
		T.truthy(refs.Status.Text:find("Sending", 1, true), "a running send keeps its line")
		PenView.setSending(refs, nil, false, 0)
		PenView.setHeader(refs, 37, 40)
		T.eq(refs.Status.Text, PenView.SendIdleText, "under the capacity again: the idle line")
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
		T.eq(text, "Sending 3…", "the pen's own sends")
		T.falsy(waiting, "not waiting")
		T.eq(total, 5, "total")
		text, waiting = PenView.sendText({ Pen = 2, Train = 0, PenWait = "Put a conveyor on your PEN chute" })
		T.eq(text, "2 waiting: Put a conveyor on your PEN chute", "why it waits")
		T.truthy(waiting, "waiting")
		-- the train's lane waiting never reads as the pen's sends being stuck
		text, waiting = PenView.sendText({ Pen = 3, Train = 4, TrainWait = "The belt at your TRAIN chute is full" })
		T.eq(text, "Sending 3…", "the pen sends fine")
		T.falsy(waiting, "not the pen waiting")
		text, waiting = PenView.sendText({ Pen = 0, Train = 4, TrainWait = "The belt at your TRAIN chute is full" })
		T.eq(text, "Train unloading 4…", "only the train: says so (its wait shows in the train panel)")
		T.falsy(waiting, "not the pen waiting")
		T.eq((PenView.sendText({ Pen = 0, Train = 0, PenWait = "x" })), idle, "nothing queued: no wait line")
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

	T.test("PenView: SEND sends one, ALL xN? the rest; STOP is the pen's; the AUTO-SORT switch", function()
		T.eq(PenView.sendButtonText(nil), "SEND", "plain")
		T.eq(PenView.sendButtonText(0), "SEND", "nothing left")
		T.eq(PenView.sendButtonText(4), "ALL x4?", "armed: the whole stack")
		T.eq(PenView.sendButtonText(1), "SEND", "a stack of one has nothing more to send")
		local refs = PenView.build()
		-- only the train unloads: nothing for STOP to stop
		PenView.setSending(refs, { Pen = 0, Train = 4 }, true, 0)
		T.falsy(refs.StopSend.Parent.Visible, "no STOP for the train's Direct Unload")
		T.eq(refs.Status.Text, "Train unloading 4…", "but it says what goes out")
		PenView.setSending(refs, { Pen = 2, Train = 4 }, true, 0)
		T.truthy(refs.StopSend.Parent.Visible, "STOP for the pen's sends")
		-- the switch: only with the billboard, in pen mode, never over the bar
		PenView.setAutoSort(refs, false, true)
		T.falsy(refs.AutoSort.Parent.Visible, "no billboard: no switch")
		for _, compact in { false, true } do
			PenView.setCompact(refs, compact)
			PenView.setAutoSort(refs, true, true)
			local holder = refs.AutoSort.Parent
			T.truthy(holder.Visible, "switch shown")
			T.eq(refs.AutoSort.Text, "AUTO-SORT ON", "on")
			local width = refs.Panel.Size.X.Offset
			local toggleLeft = width + holder.Position.X.Offset - holder.Size.X.Offset
			local barRight = refs.Bar.Position.X.Offset + width + refs.Bar.Size.X.Offset
			T.le(barRight + 8, toggleLeft, "the bar ends left of the switch")
			T.le(80, refs.Bar.Size.X.Offset + width, "the bar keeps some length")
			T.le(if compact then 72 else 50, holder.Size.Y.Offset, "a big enough touch target")
			local closeLeft = width + refs.Close.Parent.Position.X.Offset - refs.Close.Parent.Size.X.Offset
			T.le(width + holder.Position.X.Offset, closeLeft, "left of the X")
			PenView.setAutoSort(refs, true, false)
			T.eq(refs.AutoSort.Text, "AUTO-SORT OFF", "off")
		end
		PenView.setMode(refs, "Pick", 1)
		T.falsy(refs.AutoSort.Parent.Visible, "never in pick mode")
		PenView.setMode(refs, "Pen", nil)
		PenView.setAutoSort(refs, true, true)
		T.truthy(refs.AutoSort.Parent.Visible, "back in pen mode")
	end)

	T.test("PenView: the panel keeps clear of the coins and the HANDS box", function()
		local refs = PenView.build()
		local function box(room: any): (number, number, number, number)
			local size, pos, anchor = refs.Panel.Size, refs.Panel.Position, refs.Panel.AnchorPoint
			local w, h = size.X.Offset, size.Y.Offset
			local x = pos.X.Scale * room.X + pos.X.Offset - anchor.X * w
			local y = pos.Y.Scale * room.Y + pos.Y.Offset - anchor.Y * h
			return x, y, x + w, y + h
		end
		local function clear(room: any, what: string)
			local x0, y0, x1, y1 = box(room)
			T.le(0, x0, what .. ": on screen (left)")
			T.le(x1, room.X, what .. ": on screen (right)")
			T.le(0, y0, what .. ": on screen (top)")
			-- the coins box (top left) and the HANDS box (bottom centre, 260 wide)
			local coinsFree = x0 >= PenView.HudLeft or y0 >= PenView.HudTop
			T.truthy(coinsFree, what .. ": the coins stay visible")
			local handsLeft, handsRight = room.X / 2 - 130, room.X / 2 + 130
			local handsFree = y1 <= room.Y - PenView.HudBottom or x1 <= handsLeft or x0 >= handsRight
			T.truthy(handsFree, what .. ": the HANDS box stays visible")
		end
		-- a PC (1600 x 900 at UI scale 1.25), a tall tablet, a small phone at the 0.62 floor
		local pc = Vector2.new(1280, 720)
		PenView.setCompact(refs, false, pc)
		clear(pc, "PC")
		T.le(4, (refs.Panel.Size.Y.Offset - 188 + 8) / 72, "PC: four rows or more")
		T.eq(refs.Toolbar.Size.Y.Offset, 58, "50-unit toolbar buttons fit")
		T.le(50, refs.SendDirty.Parent.Size.Y.Offset, "toolbar buttons >= 44 pt down to a 0.88 scale")
		local tablet = Vector2.new(1100, 825)
		PenView.setCompact(refs, false, tablet)
		clear(tablet, "tablet")
		local phone = Vector2.new(1600 / (0.62 * 900 / 375), (900 - 58) / (0.62 * 900 / 375))
		PenView.setCompact(refs, true, phone)
		clear(phone, "phone")
		T.le(72, refs.SendDirty.Parent.Size.Y.Offset, "phone: touch-sized toolbar")
		local wide = Vector2.new(844 / 0.62, (390 - 47) / 0.62)
		PenView.setCompact(refs, true, wide)
		clear(wide, "wide phone")
		-- no room known (tests, previews of old): the full layout, centred
		PenView.setCompact(refs, true, nil)
		T.eq(refs.Panel.AnchorPoint, Vector2.new(0.5, 0.5), "centred")
	end)
end
