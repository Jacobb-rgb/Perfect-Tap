-- PenService under Lune: pen capacity, the intake box (owner only, full pen
-- bounces), Put In, Take limits, ToPodium, bad inputs, and the pure parts of
-- PenView (rows, free podium slot, pile selection). The plot is built by the
-- real PlotBuilder; players, saves, carrying and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
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
		pen.reset()
		T.truthy(pen.setupPen(PLOT), "pen set up")
		w.zone = w.zones[1]
		w.restore = function()
			ItemService._test.reset()
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
end
