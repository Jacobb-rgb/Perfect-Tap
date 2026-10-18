-- PodiumService under Lune: slots and the Podiums perk, Place / Remove /
-- Put On Podium, no duplication, the income tick, offline earnings (cap,
-- extension, clock skew), the lock visuals and bad input. The plot is built
-- by the real PlotBuilder and the ores by ItemBuilder.display; players,
-- saves, carrying and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local PLOT = 4
	local USER, OTHER = 601, 602
	local NOW = 1.76e9 -- a plausible os.time()
	local podium = PodiumService._test
	local GOLD = "Clean|Gold|Pristine|"
	local COPPER = "Clean|Copper|Rough|"
	local DIRTY = "Raw|Gold||"
	local INGOT = "Ingot|Gold|Clean|"

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

	local function income(key: string): number
		return ItemData.income(ItemData.parseKey(key))
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
		local w: any = { notes = {}, changed = {}, carried = {}, now = NOW }
		w.plotModel = PlotBuilder.buildPlot(roblox.Instance.new("Folder"), WorldLayout.Plots[PLOT], Rng.new(PLOT))
		w.player = fakePlayer(USER, "Owner")
		w.other = fakePlayer(OTHER, "Neighbour")
		w.data = deepCopy(DataTemplate)
		w.otherData = deepCopy(DataTemplate)
		w.online = { [w.player] = true, [w.other] = true }
		-- stand in front of the podiums
		local front = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT]) * CFrame.new(12, 3, 27)
		w.player.stand(front.Position)
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			if not w.online[p] then
				return nil
			end
			return if p == w.player then w.data elseif p == w.other then w.otherData else nil
		end)
		patch(DataService, "changed", function(p)
			w.changed[p] = (w.changed[p] or 0) + 1
		end)
		patch(Net, "fire", function(name, p, a, b, c)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b, C = c })
		end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player then PLOT else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then w.plotModel else nil
		end)
		patch(Players, "GetPlayers", function()
			return { w.player, w.other }
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == OTHER then w.other else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids = (w.ids or 0) + 1
			return "podium-guid-" .. w.ids
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
		ItemService._test.reset()
		EconomyService._test.reset()
		PenService._test.reset()
		podium.reset()
		podium.setClock(function()
			return w.now
		end)
		w.restore = function()
			podium.reset()
			ItemService._test.reset()
			EconomyService._test.reset()
			PenService._test.reset()
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

	local function onPodiums(w: any, key: string): number
		local n = 0
		for _, k in w.data.Podiums do
			if k == key then
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

	local function carry(w: any, desc: any): any
		local record = ItemService.spawnDesc(desc, USER, CFrame.new(0, 5, 0), nil, true)
		record.State = "Carried"
		table.insert(w.carried, record)
		return record
	end

	---------------------------------------------------------------- slots

	withWorld("PodiumService: 2 podiums for everyone, 4 with the Podiums perk", function(w)
		T.eq(PodiumService.slotsFor(w.player), EconomyConfig.Podiums.Free, "free slots")
		T.truthy(PodiumService.isUnlocked(w.player, 2), "slot 2")
		T.falsy(PodiumService.isUnlocked(w.player, 3), "slot 3 locked")
		T.falsy(PodiumService.isUnlocked(w.player, 0), "slot 0")
		w.player.attributes.Perk_Podiums = true
		T.eq(PodiumService.slotsFor(w.player), EconomyConfig.Podiums.Max, "perk slots")
		T.truthy(PodiumService.isUnlocked(w.player, 4), "slot 4")
		T.falsy(PodiumService.isUnlocked(w.player, 5), "slot 5")
	end)

	---------------------------------------------------------------- place / remove

	withWorld("PodiumService: Place moves one cleaned ore from the pen onto the podium and shows it", function(w)
		fill(w, GOLD, 2)
		local ok = PodiumService.place(w.player, 1, GOLD)
		T.truthy(ok, "placed")
		T.eq(w.data.Podiums[1], GOLD, "saved")
		T.eq(inPen(w, GOLD), 1, "one left in the pen")
		T.truthy((w.changed[w.player] or 0) > 0, "data changed")
		local shown = podium.shown(PLOT, 1)
		T.truthy(shown and shown.Model, "display built")
		T.eq(shown.Model.Parent, w.plotModel.Yard.Podium1, "on podium 1")
		T.eq(shown.Model.Name, "Display", "named for PodiumController")
		for _, d in shown.Model:GetDescendants() do
			if d:IsA("BasePart") then
				T.truthy(d.Anchored, "anchored")
				T.falsy(d.CanQuery, "no query")
				T.falsy(d.CanCollide, "no collision")
			end
		end
		local point = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT])
			* Vector3.new(BaseLayout.Podiums[1].Center.X, BaseLayout.PodiumOreHeight, BaseLayout.Podiums[1].Center.Z)
		T.lt((shown.Model:GetPivot().Position - point).Magnitude, 3, "at the ore point")
		T.eq(shown.Tag.Amount.Text, Format.perSecond(income(GOLD)), "+$X/s tag")
		T.eq(lastNote(w, "Fx").A, "PodiumPlaced", "effect")
		-- a canonical key is stored even for an equal but odd key
		T.truthy(PodiumService.place(w.player, 2, GOLD), "second podium")
		T.eq(inPen(w, GOLD), 0, "pen empty")
	end)

	withWorld("PodiumService: Place refuses locked slots, dirty ore, ingots, taken slots and missing ore", function(w)
		fill(w, GOLD, 2)
		fill(w, DIRTY, 1)
		fill(w, INGOT, 1)
		local cases = {
			{ 3, GOLD, "Locked" },
			{ 4, GOLD, "Locked" },
			{ 1, DIRTY, "NotClean" },
			{ 1, INGOT, "NotClean" },
			{ 1, "Clean|Gold|Shiny|", "NotClean" },
			{ 1, "", "NotClean" },
			{ 1, COPPER, "NotInPen" },
			{ 0, GOLD, "BadSlot" },
			{ 5, GOLD, "BadSlot" },
			{ 1.5, GOLD, "BadSlot" },
			{ 0 / 0, GOLD, "BadSlot" },
		}
		for _, c in cases do
			local ok, why = PodiumService.place(w.player, c[1], c[2])
			T.falsy(ok, `slot {c[1]} {c[2]}`)
			T.eq(why, c[3], `reason for slot {c[1]} {c[2]}`)
		end
		T.eq(#w.data.Storage, 4, "pen untouched")
		T.eq(onPodiums(w, ""), EconomyConfig.Podiums.Max, "podiums empty")
		T.truthy(PodiumService.place(w.player, 1, GOLD), "slot 1")
		local ok, why = PodiumService.place(w.player, 1, GOLD)
		T.falsy(ok, "taken")
		T.eq(why, "Taken", "taken reason")
		T.eq(inPen(w, GOLD), 1, "the second gold stays in the pen")
		-- the perk opens slots 3 and 4
		w.player.attributes.Perk_Podiums = true
		T.truthy(PodiumService.place(w.player, 3, GOLD), "slot 3 with the perk")
		w.online[w.player] = nil
		local _, noData = PodiumService.place(w.player, 2, GOLD)
		T.eq(noData, "NoData", "no data")
	end)

	withWorld("PodiumService: Remove puts the ore back into the pen, but not into a full pen", function(w)
		fill(w, GOLD, 1)
		PodiumService.place(w.player, 2, GOLD)
		T.eq(inPen(w, GOLD), 0, "on the podium")
		fill(w, DIRTY, PenService.capacity(w.player))
		local ok, why = PodiumService.remove(w.player, 2)
		T.falsy(ok, "pen full")
		T.eq(why, "PenFull", "reason")
		T.eq(w.data.Podiums[2], GOLD, "still on the podium")
		T.truthy(lastNote(w, "Notify").A.Text:find("full", 1, true), "full toast")
		table.remove(w.data.Storage)
		T.truthy(PodiumService.remove(w.player, 2), "room again")
		T.eq(w.data.Podiums[2], "", "podium empty")
		T.eq(inPen(w, GOLD), 1, "back in the pen")
		local shown = podium.shown(PLOT, 2)
		T.eq(shown.Model, nil, "display gone")
		T.eq(shown.Tag, nil, "tag gone")
		local again, empty = PodiumService.remove(w.player, 2)
		T.falsy(again, "nothing to remove")
		T.eq(empty, "Empty", "empty reason")
		-- an ore left on a slot that is locked now can still be taken back
		w.data.Podiums[4] = COPPER
		table.remove(w.data.Storage)
		T.truthy(PodiumService.remove(w.player, 4), "locked slot removable")
		T.eq(inPen(w, COPPER), 1, "copper back")
		-- junk on a slot is cleared, never turned into an item
		w.data.Podiums[1] = "Raw|Gold||"
		local before = #w.data.Storage
		T.falsy(PodiumService.remove(w.player, 1), "junk")
		T.eq(w.data.Podiums[1], "", "junk cleared")
		T.eq(#w.data.Storage, before, "no item made from junk")
		-- an ore a newer build knows (a key this server can't read) is never cleared
		w.data.Podiums[1] = "Clean|Zzzium|Pristine|"
		T.falsy(PodiumService.remove(w.player, 1), "can't be taken off here")
		T.eq(w.data.Podiums[1], "Clean|Zzzium|Pristine|", "kept for the newer build (docs/SAVE_AUDIT.md #1(b))")
		T.eq(#w.data.Storage, before, "no item made from it")
		w.data.Podiums[1] = ""
	end)

	withWorld("PodiumService: racing Place and Remove never duplicates an ore", function(w)
		fill(w, GOLD, 1)
		fill(w, COPPER, 1)
		local function total(): number
			return #w.data.Storage + EconomyConfig.Podiums.Max - onPodiums(w, "")
		end
		local start = total()
		for _ = 1, 25 do
			PodiumService.place(w.player, 1, GOLD)
			PodiumService.place(w.player, 2, GOLD)
			PodiumService.remove(w.player, 1)
			PodiumService.remove(w.player, 1)
			podium.action(w.player, 2, "Place", { Key = GOLD })
			podium.action(w.player, 1, "Place", { Key = COPPER })
			podium.action(w.player, 2, "Remove")
			podium.action(w.player, 1, "Remove")
			T.eq(total(), start, "items are conserved")
		end
		T.eq(inPen(w, GOLD) + onPodiums(w, GOLD), 1, "still exactly one gold")
		T.eq(inPen(w, COPPER) + onPodiums(w, COPPER), 1, "still exactly one copper")
	end)

	withWorld("PodiumService: Put On Podium takes the best cleaned ore from your hands", function(w)
		carry(w, { K = "Raw", O = "Diamond" })
		local copper = carry(w, { K = "Clean", O = "Copper", G = "Rough" })
		local gold = carry(w, { K = "Clean", O = "Gold", G = "Pristine" })
		carry(w, { K = "Clean", O = "Copper", G = "Clean" })
		T.truthy(PodiumService.placeFromHands(w.player, 1), "placed")
		T.eq(w.data.Podiums[1], GOLD, "the gold, not the top of the stack")
		T.eq(gold.State, "Consumed", "out of the world")
		T.eq(#w.carried, 3, "the rest stays carried")
		T.truthy(PodiumService.placeFromHands(w.player, 2), "second")
		T.eq(w.data.Podiums[2], "Clean|Copper|Clean|", "next best")
		local ok, why = PodiumService.placeFromHands(w.player, 3)
		T.falsy(ok, "locked")
		T.eq(why, "Locked", "locked reason")
		T.eq(copper.State, "Carried", "still in hand")
		-- only dirty ore left: the prompt falls back to the pen picker
		table.remove(w.carried, 2)
		w.data.Podiums[1] = ""
		podium.prompt(w.player, PLOT, 1, "Put")
		local open = lastNote(w, "OpenUI")
		T.truthy(open and open.A == "Pen" and open.B.Slot == 1, "pen opens in pick mode")
		T.eq(#w.carried, 1, "dirty ore stays in hand")
	end)

	withWorld("PodiumService: prompts and PodiumAction check owner, range and input", function(w)
		fill(w, GOLD, 3)
		podium.prompt(w.other, PLOT, 1, "Place")
		T.eq(lastNote(w, "Notify").Player, w.other, "stranger told")
		T.eq(lastNote(w, "OpenUI"), nil, "no picker for strangers")
		podium.prompt(w.player, PLOT, 1, "Place")
		T.eq(lastNote(w, "OpenUI").B.Slot, 1, "picker for slot 1")
		podium.prompt(w.player, PLOT, 3, "Place")
		T.truthy(lastNote(w, "Notify").A.Text:find("100 R$", 1, true), "locked slot names the price")
		local junk: { any } = {
			{ 0, "Place", { Key = GOLD } },
			{ 5, "Place", { Key = GOLD } },
			{ 1.5, "Place", { Key = GOLD } },
			{ 0 / 0, "Place", { Key = GOLD } },
			{ math.huge, "Place", { Key = GOLD } },
			{ "1", "Place", { Key = GOLD } },
			{ 1, nil, { Key = GOLD } },
			{ 1, "Steal", { Key = GOLD } },
			{ 1, "Place", nil },
			{ 1, "Place", GOLD },
			{ 1, "Place", { Key = string.rep("x", 300) } },
			{ 1, "Place", { Key = 5 } },
			{ 1, "Place", setmetatable({ Key = GOLD }, {}) },
		}
		for _, c in junk do
			podium.action(w.player, c[1], c[2], c[3])
		end
		T.eq(inPen(w, GOLD), 3, "nothing placed")
		w.player.stand(w.player.root.Position + Vector3.new(0, 0, 200))
		podium.action(w.player, 1, "Place", { Key = GOLD })
		T.eq(inPen(w, GOLD), 3, "too far")
		local stranger = fakePlayer(OTHER, "Neighbour")
		podium.action(stranger, 1, "Place", { Key = GOLD })
		T.eq(inPen(w, GOLD), 3, "no plot")
	end)

	---------------------------------------------------------------- income

	withWorld("PodiumService: every tick pays the podium income quietly, once per player", function(w)
		w.data.Podiums = { GOLD, COPPER, GOLD, "" }
		local perSecond = income(GOLD) + income(COPPER)
		T.near(PodiumService.incomeOf(w.player, w.data), perSecond, 1e-9, "slot 3 is locked: not counted")
		w.data.LastSeen = 0
		PodiumService.tick()
		local paid = perSecond * EconomyConfig.IncomeTick
		T.near(w.data.Coins, paid, 1e-9, "coins")
		T.near(w.data.TotalEarned, paid, 1e-9, "total earned")
		T.near(w.data.Stats.PodiumEarned, paid, 1e-9, "stats")
		T.eq(w.data.LastSeen, NOW, "LastSeen")
		T.eq(w.changed[w.player], 1, "one push per tick")
		T.eq(w.changed[w.other], nil, "no podium income: no push")
		T.eq(w.otherData.LastSeen, NOW, "LastSeen for everyone loaded")
		-- the perk opens slot 3, a bonus multiplies everything
		w.player.attributes.Perk_Podiums = true
		EconomyService.addIncomeBonus(function()
			return 0.5
		end)
		EconomyService.addIncomeBonus(function()
			return 0 / 0
		end)
		EconomyService.addIncomeBonus(function()
			error("broken bonus")
		end)
		local boosted = (perSecond + income(GOLD)) * 1.5
		T.near(PodiumService.incomeOf(w.player), boosted, 1e-9, "x1.5, junk bonuses ignored")
		PodiumService.tick()
		T.near(w.data.Coins, paid + boosted * EconomyConfig.IncomeTick, 1e-6, "second tick")
		-- the State provider fields
		local per = {}
		for slot = 1, EconomyConfig.Podiums.Max do
			per[slot] = PodiumService.slotIncome(w.player, w.data, slot)
		end
		T.near(per[3], income(GOLD) * 1.5, 1e-9, "slot 3 income")
		T.eq(per[4], 0, "empty slot")
		-- junk podium entries earn nothing
		w.data.Podiums = { "Raw|Gold||", 42, "Clean|Nope||", INGOT }
		T.eq(PodiumService.incomeOf(w.player), 0, "junk earns nothing")
		w.online[w.player] = nil
		local coins = w.data.Coins
		PodiumService.tick()
		T.eq(w.data.Coins, coins, "not loaded: skipped")
	end)

	---------------------------------------------------------------- offline

	withWorld("PodiumService: offline earnings at 50 % up to the cap, popup after loading", function(w)
		w.data.Podiums = { GOLD, COPPER, "", "" }
		local perSecond = income(GOLD) + income(COPPER)
		w.data.LastSeen = NOW - 3600
		podium.loaded(w.player, w.data)
		T.eq(w.data.LastSeen, NOW, "LastSeen = now on load")
		T.eq(podium.pending(w.player), 3600, "one hour waiting")
		local amount = podium.payOffline(w.player, true)
		T.near(amount, perSecond * EconomyConfig.Offline.Rate * 3600, 1e-6, "50 % of an hour")
		T.near(w.data.Coins, amount, 1e-6, "paid")
		T.near(w.data.Stats.PodiumEarned, amount, 1e-6, "counted as podium money")
		local popup = lastNote(w, "OpenUI")
		T.truthy(popup and popup.A == "Offline", "popup")
		T.near(popup.B.Amount, amount, 1e-6, "popup amount")
		T.eq(popup.B.Seconds, 3600, "popup seconds")
		T.eq(popup.B.Hours, EconomyConfig.Offline.BaseHours, "popup hours")
		T.eq(podium.pending(w.player), nil, "paid once")
		T.eq(podium.payOffline(w.player, true), 0, "never twice")
	end)

	withWorld("PodiumService: the offline cap, the extension and broken clocks", function(w)
		w.data.Podiums = { GOLD, "", "", "" }
		local perSecond = income(GOLD)
		local base = EconomyConfig.Offline.BaseHours * 3600
		local extended = EconomyConfig.Offline.ExtendedHours * 3600
		-- 10 hours away: capped at 5 h, or 10 h with the extension
		w.data.LastSeen = NOW - 36000
		podium.loaded(w.player, w.data)
		T.near(podium.payOffline(w.player, true), perSecond * 0.5 * base, 1e-6, "base cap")
		w.player.attributes.Perk_OfflineExtension = true
		w.data.LastSeen = NOW - 36000
		podium.loaded(w.player, w.data)
		T.near(podium.payOffline(w.player, true), perSecond * 0.5 * 36000, 1e-6, "extension: all 10 h")
		w.data.LastSeen = NOW - 3 * 24 * 3600
		podium.loaded(w.player, w.data)
		T.near(podium.payOffline(w.player, true), perSecond * 0.5 * extended, 1e-6, "extension cap")
		T.eq(lastNote(w, "OpenUI").B.Hours, EconomyConfig.Offline.ExtendedHours, "popup says 12 h")
		-- nothing for: short breaks, a clock in the future, broken or ancient values
		local coins = w.data.Coins
		for _, last in { NOW - 30, NOW + 600, 0, -5, 0 / 0, math.huge, "1700000000", 1000, NOW - 10 * 365 * 24 * 3600 } do
			w.data.LastSeen = last
			podium.loaded(w.player, w.data)
			T.eq(podium.pending(w.player), nil, "no offline pay for " .. tostring(last))
			T.eq(w.data.LastSeen, NOW, "LastSeen repaired for " .. tostring(last))
		end
		T.eq(w.data.Coins, coins, "nothing paid")
		T.eq(PodiumService.offlineSeconds(NOW - 100, NOW), 100, "plain case")
		T.eq(PodiumService.offlineSeconds(NOW + 1, NOW), 0, "skew")
		-- no podium income: nothing
		w.data.Podiums = { "", "", "", "" }
		w.data.LastSeen = NOW - 3600
		podium.loaded(w.player, w.data)
		T.eq(podium.payOffline(w.player, true), 0, "empty podiums pay nothing")
	end)

	withWorld("PodiumService: leaving before the welcome-back payout still pays it, and saves LastSeen", function(w)
		w.data.Podiums = { GOLD, "", "", "" }
		w.data.LastSeen = NOW - 7200
		podium.loaded(w.player, w.data)
		w.now = NOW + 2
		podium.release(w.player, w.data)
		T.near(w.data.Coins, income(GOLD) * 0.5 * 7200, 1e-6, "paid on leave")
		T.eq(lastNote(w, "OpenUI"), nil, "no popup for a player who left")
		T.eq(w.data.LastSeen, NOW + 2, "LastSeen at leave")
		T.eq(podium.pending(w.player), nil, "nothing pending")
	end)

	---------------------------------------------------------------- looks

	withWorld("PodiumService: locked podiums show a lock until the owner has the perk", function(w)
		local yard = w.plotModel.Yard
		local function lockShown(slot: number): boolean
			local lock = yard["Podium" .. slot]:FindFirstChild("Lock")
			for _, d in lock:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					return true
				end
			end
			return false
		end
		PodiumService.refreshPlot(PLOT)
		T.truthy(lockShown(3) and lockShown(4), "locked")
		w.player.attributes.Perk_Podiums = true
		PodiumService.refreshPlot(PLOT)
		T.falsy(lockShown(3) or lockShown(4), "unlocked")
		T.eq(yard.Podium3.Rim.Material, roblox.Enum.Material.Neon, "rim glows")
		T.falsy(yard.Podium3.PricePlate:FindFirstChildWhichIsA("SurfaceGui").Enabled, "price hidden")
		-- an ore left on a slot that lost the perk shows "Locked"
		w.data.Podiums[3] = GOLD
		PodiumService.refreshPlot(PLOT)
		w.player.attributes.Perk_Podiums = nil
		PodiumService.refreshPlot(PLOT)
		T.eq(podium.shown(PLOT, 3).Tag.Amount.Text, "Locked", "locked tag")
		T.truthy(lockShown(3), "locked again")
		-- the plot's owner leaves: empty podiums
		w.online[w.player] = nil
		PodiumService.refreshPlot(PLOT)
		T.eq(podium.shown(PLOT, 3).Model, nil, "no owner, no ore")
	end)
end
