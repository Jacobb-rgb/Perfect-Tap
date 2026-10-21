-- SellService under Lune: Tobin's prices, selling from the Ore Pen and from
-- the hands, podium ore that is never sold, bad requests, the range to the
-- stall, the Sell-all filters (and that SellView plans the same), the
-- SellBin paying the item's owner and no double sales. Save data, players,
-- carrying and Net are small fakes; EconomyService runs for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local PromptConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.PromptConfig")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local SellService = Loader.requirePath("ServerScriptService.Server.Services.SellService")
	local SellView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SellView")
	local Players = Loader.game:GetService("Players")

	local USER, STRANGER = 401, 402
	local STALL = Vector3.new(38, 0, -4)
	local sell = SellService._test
	local MAX = EconomyConfig.Sell.MaxPerRequest

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

	local function price(kind: string, oreId: string, grade: string?, recipe: string?): number
		return ItemData.value(kind, oreId, grade, recipe)
	end

	local function fakePlayer(userId: number, name: string): any
		local p: any = { UserId = userId, Name = name, Parent = true }
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.humanoid = { Health = 100 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name2: string)
				return if name2 == "HumanoidRootPart" then p.root else nil
			end,
		}
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, pushes = 0, carried = {}, absorbed = {}, stashed = {}, ids = 0 }
		w.player = fakePlayer(USER, "Seller")
		w.stranger = fakePlayer(STRANGER, "Stranger")
		w.data = deepCopy(DataTemplate)
		w.strangerData = deepCopy(DataTemplate)
		w.strangerOnline = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			if p == w.player then
				return w.data
			elseif p == w.stranger and w.strangerOnline then
				return w.strangerData
			end
			return nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(StateService, "push", function()
			w.pushes += 1
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			if id == USER then
				return w.player
			elseif id == STRANGER and w.strangerOnline then
				return w.stranger
			end
			return nil
		end)
		patch(CarryService, "list", function(p)
			return if p == w.player then w.carried else {}
		end)
		patch(CarryService, "takeTop", function(p, predicate)
			if p ~= w.player then
				return nil
			end
			for i = #w.carried, 1, -1 do
				local record = w.carried[i]
				if not predicate or predicate(record) then
					table.remove(w.carried, i)
					return record
				end
			end
			return nil
		end)
		patch(ItemService, "absorb", function(record)
			assert(record.State ~= "Consumed", "an item was absorbed twice")
			record.State = "Consumed"
			table.insert(w.absorbed, record)
			return ItemService.descOf(record)
		end)
		patch(ItemService, "stash", function(record, reason)
			record.State = "Consumed"
			table.insert(w.stashed, { Record = record, Reason = reason })
			return true
		end)
		sell.reset()
		-- Tobin's counter, like TownLegacy builds it (facing -X)
		local stall = Instance.new("Model")
		local counter = Instance.new("Part")
		counter.Size = Vector3.new(14, 3.6, 2.6)
		counter.CFrame = CFrame.lookAt(STALL, STALL + Vector3.new(-1, 0, 0)) * CFrame.new(0, 2.8, -3)
		counter.Parent = stall
		sell.hookCounter(counter)
		w.counter = counter
		w.stall = stall
		-- puts a player `away` studs in front of the counter's customer side
		w.standAt = function(p: any, away: number)
			local front = counter.CFrame * CFrame.new(0, 0, -(counter.Size.Z / 2 + away))
			p.root.Position = front.Position
			p.root.CFrame = front
		end
		w.standAt(w.player, 3)
		w.standAt(w.stranger, 3)
		w.restore = function()
			sell.reset()
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

	local function pen(w: any, list: { { any } })
		for _, item in list do
			for _ = 1, item[4] or 1 do
				table.insert(w.data.Storage, { K = item[1], O = item[2], G = item[3] })
			end
		end
	end

	local function carry(w: any, kind: string, oreId: string, grade: string?, owner: number?): any
		w.ids += 1
		local record = {
			Id = "carried-" .. w.ids,
			Kind = kind,
			OreId = oreId,
			Grade = grade,
			Recipe = nil,
			Owner = owner or USER,
			State = "Carried",
			Body = { CFrame = CFrame.new(0, 3, 0), Position = Vector3.new(0, 3, 0) },
			Model = {},
		}
		table.insert(w.carried, record)
		return record
	end

	local function loose(w: any, kind: string, oreId: string, grade: string?, owner: number): any
		w.ids += 1
		return {
			Id = "loose-" .. w.ids,
			Kind = kind,
			OreId = oreId,
			Grade = grade,
			Recipe = nil,
			Owner = owner,
			State = "Loose",
			Body = { CFrame = CFrame.new(STALL), Position = STALL },
			Model = {},
		}
	end

	local function notes(w: any, name: string, player: any?): { any }
		local out = {}
		for _, note in w.notes do
			if note.Name == name and (player == nil or note.Player == player) then
				table.insert(out, note)
			end
		end
		return out
	end

	local function count(list: { any }, key: string): number
		local n = 0
		for _, entry in list do
			if ItemData.storageKey(entry) == key then
				n += 1
			end
		end
		return n
	end

	local function act(w: any, action: any, arg: any)
		sell.action(w.player, action, arg)
	end

	---------------------------------------------------------------- prices

	T.test("SellService: Tobin pays ItemData.value; junk is worth nothing", function()
		local gold = OreData.ById.Gold
		T.eq(gold.Value, gold.Income * OreData.SellSeconds, "Value = Income x SellSeconds")
		T.eq(SellService.priceOf({ K = "Clean", O = "Gold", G = "Pristine" }), math.floor(gold.Value * 1.7 + 0.5), "clean pristine gold")
		T.eq(SellService.priceOf({ K = "Clean", O = "Gold" }), gold.Value, "clean rough gold")
		T.eq(SellService.priceOf({ K = "Raw", O = "Gold" }), math.floor(gold.Value * 0.4 + 0.5), "dirty ore pays the raw price")
		T.eq(SellService.priceOf({ K = "Gear", O = "Gold", G = "Clean", R = "Dagger" }), price("Gear", "Gold", "Clean", "Dagger"), "gear")
		T.eq(SellService.priceOf({ K = "Clean", O = "Nope" }), 0, "unknown ore")
		T.eq(SellService.priceOf({ K = "Shiny", O = "Gold" }), 0, "unknown kind")
		T.eq(SellService.priceOf({ K = "Gear", O = "Gold", G = "Clean" }), 0, "gear without a recipe")
		T.eq(SellService.priceOf({ K = "Raw", O = "Gold", R = "Dagger" }), 0, "recipe on raw ore")
		T.eq(SellService.priceOf({ K = "Clean", O = "Gold", G = "Shiny" }), 0, "unknown grade")
		T.eq(SellService.priceOf(nil :: any), 0, "nil")
		T.eq(SellService.priceOf("Clean|Gold||" :: any), 0, "a string")
		T.eq(SellService.paidText(1234, 3), "Tobin paid $1.23K for 3 items.", "toast text")
		T.eq(SellService.paidText(5, 1), "Tobin paid $5 for 1 item.", "one item")
		T.eq(SellService.revealText({ { K = "Raw", O = "Gold" } }), " It was Gold!", "one dirty ore")
		T.eq(SellService.revealText({ { K = "Clean", O = "Gold" } }), "", "nothing dirty")
		local many, rarity = SellService.revealText({
			{ K = "Raw", O = "Coal" },
			{ K = "Raw", O = "Diamond" },
			{ K = "Raw", O = "Coal" },
			{ K = "Clean", O = "Heartstone" },
		})
		T.eq(many, " The Dirty Ore was: Diamond, 2x Coal.", "rarest first, clean ore not listed")
		T.eq(rarity, "Epic", "rarest revealed")
	end)

	---------------------------------------------------------------- the pen

	withWorld("SellService: sells from the Ore Pen", function(w)
		pen(w, { { "Clean", "Copper", "Rough", 3 }, { "Raw", "Gold", nil, 2 }, { "Ingot", "Iron", "Clean", 1 } })
		local each = price("Clean", "Copper", "Rough")
		act(w, "Sell", { Key = "Clean|Copper|Rough|", Count = 2, From = "Pen" })
		T.eq(#w.data.Storage, 4, "two left the pen")
		T.eq(count(w.data.Storage, "Clean|Copper|Rough|"), 1, "one copper left")
		T.eq(count(w.data.Storage, "Raw|Gold||"), 2, "dirty ore untouched")
		T.near(w.data.Coins, each * 2, 1e-9, "coins")
		T.near(w.data.TotalEarned, each * 2, 1e-9, "total earned")
		T.eq(w.data.Stats.ItemsSold, 2, "stats")
		T.truthy(w.changed > 0, "DataService.changed")
		local earned = notes(w, "Earned", w.player)
		T.eq(#earned, 1, "one Earned popup")
		T.eq(earned[1].A.Amount, each * 2, "popup amount")
		T.eq(earned[1].A.Source, "Sell", "popup source")
		T.eq(earned[1].A.Count, 2, "popup count")
		T.eq(typeof(earned[1].A.Position), "Vector3", "popup position")
		T.truthy((earned[1].A.Position - w.counter.CFrame.Position).Magnitude < 6, "popup at the counter")
		local toast = notes(w, "Notify", w.player)
		T.eq(#toast, 1, "one toast")
		T.eq(toast[1].A.Text, `Tobin paid {Format.money(each * 2)} for 2 items.`, "toast text")
		T.eq(toast[1].A.Kind, "Reward", "toast kind")
		-- asking for more than there is sells what is there
		act(w, "Sell", { Key = "Clean|Copper|Rough|", Count = 5, From = "Pen" })
		T.eq(count(w.data.Storage, "Clean|Copper|Rough|"), 0, "last copper sold")
		T.eq(w.data.Stats.ItemsSold, 3, "stats")
		T.near(w.data.Coins, each * 3, 1e-9, "coins")
	end)

	withWorld("SellService: Dirty Ore pays the raw price and shows what it was", function(w)
		pen(w, { { "Raw", "Gold" }, { "Raw", "Coal" } })
		act(w, "Sell", { Key = "Raw|Gold||", Count = 1, From = "Pen" })
		T.eq(w.data.Coins, price("Raw", "Gold"), "raw gold price")
		T.eq(#w.data.Storage, 1, "coal left")
		local toast = notes(w, "Notify", w.player)
		T.eq(toast[1].A.Text, `Tobin paid {Format.money(price("Raw", "Gold"))} for 1 item. It was Gold!`, "reveal")
		T.eq(toast[1].A.Rarity, "Rare", "rare reveal colours the toast")
	end)

	withWorld("SellService: the sell bonus (Midas, SellValue golems) raises every payout", function(w)
		local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
		w.data.Enchants.Owned.Midas = 3 -- +35 %
		w.data.Enchants.Slots[1] = "Midas"
		Bonuses.invalidate(w.player)
		pen(w, { { "Clean", "Copper", "Rough", 2 } })
		local each = price("Clean", "Copper", "Rough")
		act(w, "Sell", { Key = "Clean|Copper|Rough|", Count = 2, From = "Pen" })
		local paid = math.floor(each * 2 * 1.35 + 0.5)
		T.truthy(paid > each * 2)
		T.eq(w.data.Coins, paid, "coins with the bonus")
		T.eq(notes(w, "Earned", w.player)[1].A.Amount, paid, "popup amount")
		T.eq(notes(w, "Notify", w.player)[1].A.Text, `Tobin paid {Format.money(paid)} for 2 items.`, "toast amount")
		-- the SellBin pays the owner's bonus too
		local item = loose(w, "Clean", "Copper", "Rough", USER)
		T.eq(SellService.sellRecord(item, STALL), math.floor(each * 1.35 + 0.5))
		T.eq(w.data.Coins, paid + math.floor(each * 1.35 + 0.5))
		Bonuses.invalidate(w.player)
	end)

	---------------------------------------------------------------- hands

	withWorld("SellService: sells what you carry", function(w)
		pen(w, { { "Clean", "Silver", "Rough" } })
		local coal = carry(w, "Raw", "Coal")
		local silverA = carry(w, "Clean", "Silver", "Rough")
		local silverB = carry(w, "Clean", "Silver", "Rough")
		act(w, "Sell", { Key = "Clean|Silver|Rough|", Count = 2, From = "Hands" })
		T.eq(#w.absorbed, 2, "two items left the world")
		T.eq(silverA.State, "Consumed", "silver A sold")
		T.eq(silverB.State, "Consumed", "silver B sold")
		T.eq(coal.State, "Carried", "coal still carried")
		T.eq(#w.carried, 1, "one left in the hands")
		T.eq(count(w.data.Storage, "Clean|Silver|Rough|"), 1, "the pen's silver is untouched")
		T.eq(w.data.Coins, price("Clean", "Silver", "Rough") * 2, "coins")
		T.eq(w.data.Stats.ItemsSold, 2, "stats")
		-- the pen's silver can't be sold "from the hands"
		w.notes = {}
		act(w, "Sell", { Key = "Clean|Silver|Rough|", Count = 1, From = "Hands" })
		T.eq(count(w.data.Storage, "Clean|Silver|Rough|"), 1, "pen still has it")
		T.eq(w.data.Coins, price("Clean", "Silver", "Rough") * 2, "nothing paid")
		local denied = notes(w, "Notify", w.player)
		T.eq(denied[1].A.Kind, "Deny", "told why")
		T.truthy(w.pushes > 0, "view refreshed")
		-- someone else's item in your stack (never happens, but never sell it)
		carry(w, "Clean", "Gold", "Rough", STRANGER)
		act(w, "Sell", { Key = "Clean|Gold|Rough|", Count = 1, From = "Hands" })
		T.eq(#w.carried, 2, "foreign item kept")
		T.eq(w.data.Coins, price("Clean", "Silver", "Rough") * 2, "nothing paid")
	end)

	withWorld("SellService: the hands summary for the Sell view", function(w)
		carry(w, "Clean", "Silver", "Rough")
		carry(w, "Raw", "Coal")
		carry(w, "Clean", "Silver", "Rough")
		carry(w, "Clean", "Gold", "Rough", STRANGER)
		local summary = SellService.handsSummary(w.player)
		T.eq(summary["Clean|Silver|Rough|"], 2, "silver")
		T.eq(summary["Raw|Coal||"], 1, "coal")
		T.eq(summary["Clean|Gold|Rough|"], nil, "not your item")
		T.eq(next(SellService.handsSummary(w.stranger)), nil, "empty hands")
	end)

	---------------------------------------------------------------- podiums

	withWorld("SellService: podium ore is never sold", function(w)
		w.data.Podiums = { "Clean|Gold|Flawless|", "Clean|Silver|Rough|", "", "" }
		pen(w, { { "Clean", "Silver", "Rough" }, { "Clean", "Coal", "Rough", 5 } })
		act(w, "Sell", { Key = "Clean|Gold|Flawless|", Count = 1, From = "Pen" })
		T.eq(w.data.Coins, 0, "nothing paid for podium ore")
		act(w, "Sell", { Key = "Clean|Silver|Rough|", Count = 2, From = "Pen" })
		T.eq(w.data.Coins, price("Clean", "Silver", "Rough"), "only the pen's silver")
		act(w, "SellAll", { Filter = "AllButBest" })
		act(w, "SellAll", { Filter = "Dirty" })
		T.eq(w.data.Podiums[1], "Clean|Gold|Flawless|", "podium 1 untouched")
		T.eq(w.data.Podiums[2], "Clean|Silver|Rough|", "podium 2 untouched")
		T.eq(#w.data.Podiums, 4, "four slots")
		-- the best 4 coal stay; one is sold
		T.eq(count(w.data.Storage, "Clean|Coal|Rough|"), 4, "best four kept")
	end)

	---------------------------------------------------------------- bad input

	withWorld("SellService: refuses bad keys, counts and types", function(w)
		pen(w, { { "Clean", "Copper", "Rough", 3 }, { "Raw", "Gold" } })
		carry(w, "Clean", "Copper", "Rough")
		local key = "Clean|Copper|Rough|"
		local tooMany = {}
		for i = 1, 20 do
			tooMany["k" .. i] = i
		end
		tooMany.Key, tooMany.Count, tooMany.From = key, 1, "Pen"
		local bad: { { any } } = {
			{ "Sell", nil },
			{ "Sell", key },
			{ "Sell", 5 },
			{ "Sell", { Key = "Clean|Nope|Rough|", Count = 1, From = "Pen" } },
			{ "Sell", { Key = 123, Count = 1, From = "Pen" } },
			{ "Sell", { Key = string.rep("a", 500), Count = 1, From = "Pen" } },
			{ "Sell", { Key = "Clean|Copper|Rough", Count = 1, From = "Pen" } },
			{ "Sell", { Key = "Gear|Copper|Rough|", Count = 1, From = "Pen" } },
			{ "Sell", { Key = "Clean|Copper|Rough|Dagger", Count = 1, From = "Pen" } },
			{ "Sell", { Key = key, Count = 0, From = "Pen" } },
			{ "Sell", { Key = key, Count = -1, From = "Pen" } },
			{ "Sell", { Key = key, Count = 1.5, From = "Pen" } },
			{ "Sell", { Key = key, Count = 0 / 0, From = "Pen" } },
			{ "Sell", { Key = key, Count = math.huge, From = "Pen" } },
			{ "Sell", { Key = key, Count = -math.huge, From = "Pen" } },
			{ "Sell", { Key = key, Count = MAX + 1, From = "Pen" } },
			{ "Sell", { Key = key, Count = 1e300, From = "Pen" } },
			{ "Sell", { Key = key, Count = "1", From = "Pen" } },
			{ "Sell", { Key = key, Count = nil, From = "Pen" } },
			{ "Sell", { Key = key, Count = 1, From = "Podium" } },
			{ "Sell", { Key = key, Count = 1, From = nil } },
			{ "Sell", { Key = key, Count = 1, From = 1 } },
			{ "Sell", setmetatable({ Key = key, Count = 1, From = "Pen" }, {}) },
			{ "Sell", tooMany },
			{ "SellAll", { Filter = "Everything" } },
			{ "SellAll", { Filter = nil } },
			{ "SellAll", { Filter = "Dirty", From = "Podium" } },
			{ "SellAll", "Dirty" },
			{ "Steal", { Key = key, Count = 1, From = "Pen" } },
			{ nil, { Key = key, Count = 1, From = "Pen" } },
			{ 7, { Key = key, Count = 1, From = "Pen" } },
		}
		for i, case in bad do
			act(w, case[1], case[2])
			T.eq(w.data.Coins, 0, `case {i}: no coins`)
			T.eq(#w.data.Storage, 4, `case {i}: pen untouched`)
			T.eq(#w.carried, 1, `case {i}: hands untouched`)
		end
		T.eq(#notes(w, "Earned"), 0, "no popups")
		T.eq(w.data.Stats.ItemsSold, 0, "no stats")
		-- the exact limit works
		pen(w, { { "Raw", "Coal", nil, MAX } })
		act(w, "Sell", { Key = "Raw|Coal||", Count = MAX, From = "Pen" })
		T.eq(w.data.Stats.ItemsSold, MAX, "MaxPerRequest items")
	end)

	withWorld("SellService: only at Tobin's stall, alive, with data", function(w)
		pen(w, { { "Clean", "Copper", "Rough", 3 } })
		local arg = { Key = "Clean|Copper|Rough|", Count = 1, From = "Pen" }
		w.standAt(w.player, SellService.Range + 2)
		act(w, "Sell", arg)
		T.eq(w.data.Coins, 0, "too far")
		local denied = notes(w, "Notify", w.player)
		T.eq(#denied, 1, "told to walk up")
		T.truthy(string.find(denied[1].A.Text, "Tobin's stall", 1, true) ~= nil, "deny text")
		-- just inside the range (measured from the counter's surface)
		w.standAt(w.player, SellService.Range - 1)
		act(w, "Sell", arg)
		T.eq(w.data.Coins, price("Clean", "Copper", "Rough"), "in range")
		-- dead, no character, no data, the counter gone
		w.standAt(w.player, 2)
		w.player.humanoid.Health = 0
		act(w, "Sell", arg)
		w.player.humanoid.Health = 100
		local character = w.player.Character
		w.player.Character = nil
		act(w, "Sell", arg)
		w.player.Character = character
		local data = w.data
		w.data = nil
		act(w, "Sell", arg)
		w.data = data
		w.counter.Parent = nil
		act(w, "Sell", arg)
		w.counter.Parent = w.stall
		T.eq(w.data.Coins, price("Clean", "Copper", "Rough"), "none of those sold")
		T.eq(#w.data.Storage, 2, "pen")
		-- a teleport to the stall only counts from where the server sees you
		w.standAt(w.player, 2)
		act(w, "Sell", arg)
		T.eq(#w.data.Storage, 1, "sold again at the stall")
	end)

	---------------------------------------------------------------- Sell all

	withWorld("SellService: Sell all Dirty Ore (pen and hands)", function(w)
		pen(w, { { "Raw", "Gold", nil, 2 }, { "Raw", "Coal" }, { "Clean", "Copper", "Rough" } })
		carry(w, "Raw", "Silver")
		carry(w, "Clean", "Tin", "Rough")
		local summaryPen = { ["Raw|Gold||"] = 2, ["Raw|Coal||"] = 1, ["Clean|Copper|Rough|"] = 1 }
		local summaryHands = { ["Raw|Silver||"] = 1, ["Clean|Tin|Rough|"] = 1 }
		local plan = SellView.plan(summaryPen, summaryHands, "Dirty", nil)
		T.eq(plan.Count, 4, "the view plans 4")
		T.eq(plan.Dirty, 4, "all dirty")
		act(w, "SellAll", { Filter = "Dirty" })
		local expected = price("Raw", "Gold") * 2 + price("Raw", "Coal") + price("Raw", "Silver")
		T.eq(w.data.Coins, expected, "raw prices")
		T.eq(w.data.Stats.ItemsSold, plan.Count, "same count as the view's plan")
		T.eq(#w.data.Storage, 1, "copper kept")
		T.eq(#w.carried, 1, "tin kept")
		T.eq(w.carried[1].OreId, "Tin", "tin")
		local toast = notes(w, "Notify", w.player)
		T.eq(
			toast[1].A.Text,
			`Tobin paid {Format.money(expected)} for 4 items. The Dirty Ore was: 2x Gold, Silver, Coal.`,
			"reveal, rarest first"
		)
		-- nothing left: a friendly refusal
		w.notes = {}
		act(w, "SellAll", { Filter = "Dirty" })
		T.eq(notes(w, "Notify", w.player)[1].A.Kind, "Deny", "nothing to sell")
	end)

	withWorld("SellService: Sell all Dirty Ore from one section", function(w)
		pen(w, { { "Raw", "Gold" } })
		local raw = carry(w, "Raw", "Silver")
		act(w, "SellAll", { Filter = "Dirty", From = "Pen" })
		T.eq(#w.data.Storage, 0, "pen sold")
		T.eq(raw.State, "Carried", "hands kept")
		act(w, "SellAll", { Filter = "Dirty", From = "Hands" })
		T.eq(raw.State, "Consumed", "hands sold")
		T.eq(w.data.Coins, price("Raw", "Gold") + price("Raw", "Silver"), "coins")
	end)

	withWorld("SellService: Sell all but the best 4 keeps the best clean ores", function(w)
		pen(w, {
			{ "Clean", "Coal", "Rough", 3 },
			{ "Clean", "Gold", "Flawless" },
			{ "Clean", "Silver", "Clean", 2 },
			{ "Ingot", "Iron", "Clean" },
			{ "Raw", "Diamond" },
		})
		local amethyst = carry(w, "Clean", "Amethyst", "Pristine")
		local crushed = carry(w, "Crushed", "Tin", "Rough")
		local plan = SellView.plan({
			["Clean|Coal|Rough|"] = 3,
			["Clean|Gold|Flawless|"] = 1,
			["Clean|Silver|Clean|"] = 2,
			["Ingot|Iron|Clean|"] = 1,
			["Raw|Diamond||"] = 1,
		}, { ["Clean|Amethyst|Pristine|"] = 1, ["Crushed|Tin|Rough|"] = 1 }, "AllButBest", nil)
		act(w, "SellAll", { Filter = "AllButBest" })
		local expected = price("Clean", "Coal", "Rough") * 3 + price("Ingot", "Iron", "Clean") + price("Crushed", "Tin", "Rough")
		T.eq(w.data.Coins, expected, "coal, ingot and crushed tin sold")
		T.eq(plan.Count, 5, "the view plans 5")
		T.eq(plan.Total, expected, "the view knows the total")
		T.eq(plan.Kept, 4, "four kept")
		T.eq(plan.Dirty, 0, "dirty ore not in it")
		T.eq(w.data.Stats.ItemsSold, 5, "stats")
		T.eq(count(w.data.Storage, "Clean|Gold|Flawless|"), 1, "gold kept")
		T.eq(count(w.data.Storage, "Clean|Silver|Clean|"), 2, "silver kept")
		T.eq(count(w.data.Storage, "Raw|Diamond||"), 1, "dirty ore kept")
		T.eq(count(w.data.Storage, "Clean|Coal|Rough|"), 0, "coal sold")
		T.eq(amethyst.State, "Carried", "amethyst kept")
		T.eq(crushed.State, "Consumed", "crushed tin sold")
		-- now only the best four (and dirty ore) are left: nothing to sell
		w.notes = {}
		act(w, "SellAll", { Filter = "AllButBest" })
		T.eq(w.data.Coins, expected, "nothing more")
		T.eq(notes(w, "Notify", w.player)[1].A.Kind, "Deny", "told why")
	end)

	withWorld("SellService: at most MaxPerRequest items per request", function(w)
		pen(w, { { "Raw", "Coal", nil, MAX + 10 } })
		act(w, "SellAll", { Filter = "Dirty" })
		T.eq(#w.data.Storage, 10, "ten left")
		T.eq(w.data.Stats.ItemsSold, MAX, "MaxPerRequest sold")
		local info = notes(w, "Notify", w.player)
		T.eq(#info, 2, "paid toast and a 'more left' note")
		T.truthy(string.find(info[2].A.Text, "10 more", 1, true) ~= nil, "more left")
		local plan = SellView.plan({ ["Raw|Coal||"] = MAX + 10 }, {}, "Dirty", nil)
		T.eq(plan.Count, MAX, "view: capped")
		T.eq(plan.Eligible, MAX + 10, "view: eligible")
	end)

	withWorld("SellService: no double sale when two requests race", function(w)
		pen(w, { { "Clean", "Copper", "Rough", 3 } })
		carry(w, "Clean", "Silver", "Rough")
		carry(w, "Clean", "Silver", "Rough")
		local penArg = { Key = "Clean|Copper|Rough|", Count = 3, From = "Pen" }
		local handArg = { Key = "Clean|Silver|Rough|", Count = 2, From = "Hands" }
		-- both requests arrive in the same frame (each handler runs to the end without yielding)
		local threads = {
			coroutine.create(act),
			coroutine.create(act),
			coroutine.create(act),
			coroutine.create(act),
		}
		local args = { { "Sell", penArg }, { "Sell", penArg }, { "Sell", handArg }, { "SellAll", { Filter = "AllButBest" } } }
		for i, thread in threads do
			local ok, err = coroutine.resume(thread, w, args[i][1], args[i][2])
			T.truthy(ok, `request {i} ran: {err}`)
			T.eq(coroutine.status(thread), "dead", `request {i} finished without yielding`)
		end
		local expected = price("Clean", "Copper", "Rough") * 3 + price("Clean", "Silver", "Rough") * 2
		T.eq(w.data.Coins, expected, "each item paid once")
		T.eq(w.data.Stats.ItemsSold, 5, "five items")
		T.eq(#w.absorbed, 2, "each carried item absorbed once")
		T.eq(#w.data.Storage, 0, "pen empty")
	end)

	---------------------------------------------------------------- the bin

	withWorld("SellService: the SellBin pays the item's owner", function(w)
		local bin = Instance.new("Part")
		bin.Size = Vector3.new(8, 5, 6)
		bin.CFrame = CFrame.new(STALL + Vector3.new(-12, 2.6, 0))
		local handler = sell.binHandler(bin)
		-- the stranger's gold, thrown in by anyone
		local foreign = loose(w, "Clean", "Gold", "Rough", STRANGER)
		handler(foreign)
		T.eq(foreign.State, "Consumed", "sold")
		T.eq(w.strangerData.Coins, price("Clean", "Gold", "Rough"), "the owner is paid")
		T.eq(w.data.Coins, 0, "the thrower is not")
		T.eq(w.strangerData.Stats.ItemsSold, 1, "owner's stats")
		-- three of your own land together: one popup, one toast
		for _, oreId in { "Coal", "Coal", "Silver" } do
			handler(loose(w, "Raw", oreId, nil, USER))
		end
		local mine = price("Raw", "Coal") * 2 + price("Raw", "Silver")
		T.eq(w.data.Coins, mine, "paid at once")
		T.eq(#notes(w, "Earned", w.player), 0, "popup waits for the batch")
		sell.flushBins()
		local earned = notes(w, "Earned", w.player)
		T.eq(#earned, 1, "one popup")
		T.eq(earned[1].A.Amount, mine, "batch amount")
		T.eq(earned[1].A.Count, 3, "batch count")
		T.eq(earned[1].A.Source, "Sell", "source")
		local toast = notes(w, "Notify", w.player)
		T.eq(#toast, 1, "one toast")
		T.truthy(string.find(toast[1].A.Text, "for 3 items", 1, true) ~= nil, "toast count")
		T.truthy(string.find(toast[1].A.Text, "Silver, 2x Coal", 1, true) ~= nil, "toast reveal")
		local strangerEarned = notes(w, "Earned", w.stranger)
		T.eq(#strangerEarned, 1, "the owner sees their popup")
		-- owner not in the game: the item is left alone
		w.strangerOnline = false
		local orphan = loose(w, "Clean", "Gold", "Rough", STRANGER)
		handler(orphan)
		T.eq(orphan.State, "Loose", "not sold")
		-- carried or consumed items are not the bin's business
		local held = loose(w, "Clean", "Gold", "Rough", USER)
		held.State = "Carried"
		handler(held)
		T.eq(held.State, "Carried", "carried item untouched")
		-- junk data: kept for its owner instead of bouncing in the bin
		local junk = loose(w, "Clean", "Nope", "Rough", USER)
		handler(junk)
		T.eq(#w.stashed, 1, "stashed")
		T.eq(w.stashed[1].Reason, "Tobin can't buy that", "reason")
		T.eq(w.data.Coins, mine, "junk pays nothing")
	end)

	---------------------------------------------------------------- the prompt

	withWorld("SellService: the Sell Ore prompt opens the view", function(w)
		local point = w.counter:FindFirstChild("SellPromptPoint")
		T.truthy(point, "prompt point")
		local prompt = point:FindFirstChild("SellOrePrompt")
		T.truthy(prompt, "prompt")
		T.eq(prompt.ActionText, "Sell Ore", "action text")
		T.eq(prompt.ObjectText, "Tobin the Miner", "object text")
		T.eq(prompt.GamepadKeyCode, PromptConfig.Keys.Main.Gamepad, "gamepad key")
		T.eq(prompt.KeyboardKeyCode, PromptConfig.Keys.Main.Keyboard, "E")
		sell.hookCounter(w.counter)
		T.eq(#point:GetChildren(), 1, "hooked once")
		carry(w, "Raw", "Coal")
		sell.open(w.player, w.counter)
		local open = notes(w, "OpenUI", w.player)
		T.eq(#open, 1, "opened")
		T.eq(open[1].A, "Sell", "kind")
		T.eq(open[1].B.Hands["Raw|Coal||"], 1, "hands sent along")
		T.truthy(open[1].B.Counter == w.counter, "counter sent along")
		w.standAt(w.player, 60)
		sell.open(w.player, w.counter)
		T.eq(#notes(w, "OpenUI", w.player), 1, "not from far away")
	end)

	---------------------------------------------------------------- the view

	T.test("SellView: rows merge Dirty Ore, sort by price and hide its price", function()
		local list = SellView.entries({
			["Raw|Gold||"] = 2,
			["Raw|Coal||"] = 3,
			["Clean|Copper|Rough|"] = 4,
			["Clean|Gold|Pristine|"] = 1,
			["Clean|Nope|Rough|"] = 9,
			["Clean|Silver|Rough|"] = 0,
			[5] = 1,
		}, "Pen")
		T.eq(#list, 3, "dirty row + two clean rows")
		T.eq(list[1].Name, "Dirty Ore", "dirty first")
		T.eq(list[1].Count, 5, "dirty merged")
		T.eq(list[1].Price, nil, "price unknown")
		T.eq(list[1].RarityOrder, 0, "rarity hidden")
		T.eq(list[1].Id, "Pen/Dirty", "id")
		T.eq(SellView.priceText(list[1].Price), "?", "shows ?")
		T.eq(list[2].Name, "Pristine Gold", "most valuable next")
		T.eq(list[2].ChipText, "Pristine", "grade chip")
		T.eq(list[3].Name, "Rough Copper", "then copper")
		T.eq(SellView.priceText(list[3].Price), Format.money(price("Clean", "Copper", "Rough")), "money format")
		T.eq(#SellView.entries(nil, "Hands"), 0, "no summary")
		-- Sell 1 on the dirty row picks one of its keys, weighted by count
		T.eq(SellView.pickKey(list[1], 0), "Raw|Coal||", "low roll")
		T.eq(SellView.pickKey(list[1], 0.99), "Raw|Gold||", "high roll")
	end)

	T.test("SellView: confirm rules never leak a Dirty Ore's rarity", function()
		T.falsy(SellView.needsConfirm(10, 3), "10 rare items")
		T.truthy(SellView.needsConfirm(11, 1), "11 items")
		T.truthy(SellView.needsConfirm(1, 4), "one epic")
		local dirty = SellView.entries({ ["Raw|Heartstone||"] = 1 }, "Hands")[1]
		T.falsy(SellView.needsConfirm(1, dirty.RarityOrder), "a hidden mythic sells without asking")
		local mythic = SellView.entries({ ["Clean|Heartstone|Flawless|"] = 1 }, "Pen")[1]
		T.truthy(SellView.needsConfirm(1, mythic.RarityOrder), "a clean mythic asks")
		T.truthy(string.find(SellView.confirmRowText(mythic, 1), "(Mythic)", 1, true) ~= nil, "names the rarity")
		T.truthy(string.find(SellView.confirmRowText(dirty, 1), "Heartstone", 1, true) == nil, "dirty text hides the ore")
		local plan = SellView.plan({ ["Clean|Coal|Rough|"] = 20 }, {}, "AllButBest", nil)
		T.eq(plan.Count, 16, "keeps 4")
		T.truthy(string.find(SellView.confirmPlanText(plan, "AllButBest"), Format.money(plan.Total), 1, true) ~= nil, "total shown")
	end)

	T.test("SellView: builds, fills and fits phones", function()
		local refs = SellView.build(false)
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "UI scale applies")
		local rows = SellView.setEntries(refs, "Pen", SellView.entries({ ["Raw|Coal||"] = 2, ["Clean|Gold|Rough|"] = 1 }, "Pen"))
		T.eq(#rows, 2, "two rows made")
		T.falsy(refs.Empty.Pen.Visible, "pen not empty")
		T.eq(#SellView.setEntries(refs, "Hands", {}), 0, "no hand rows")
		T.truthy(refs.Empty.Hands.Visible, "hands empty")
		local gold = refs.Rows["Pen/Clean|Gold|Rough|"]
		T.falsy(gold.SellAll.Parent.Visible, "no Sell all for a single item")
		T.eq(refs.Rows["Pen/Dirty"].Price.Text, "?", "dirty price")
		T.eq(refs.Rows["Pen/Dirty"].IconText.Text, "?", "dirty icon")
		-- refresh: rows are reused, gone rows removed
		local again = SellView.setEntries(refs, "Pen", SellView.entries({ ["Raw|Coal||"] = 1 }, "Pen"))
		T.eq(#again, 0, "reused")
		T.eq(refs.Rows["Pen/Clean|Gold|Rough|"], nil, "gold row gone")
		-- phone: compact rows, buttons about 44 pt at the smallest UI scale
		SellView.layout(refs, true, 390 / 0.62, 844 / 0.62)
		T.truthy(refs.Compact, "compact")
		local holder = refs.Rows["Pen/Dirty"].SellOne.Parent
		T.truthy(holder.Size.Y.Offset * 0.62 >= 44, "touch target")
		T.truthy(refs.Panel.Size.X.Offset <= 390 / 0.62 - 24 or refs.Panel.Size.X.Offset == 560, "fits a narrow screen")
		SellView.setFooter(refs, SellView.plan({}, {}, "Dirty", nil), SellView.plan({}, {}, "AllButBest", nil))
		T.eq(refs.SellDirty.Text, "Sell all Dirty Ore", "footer label")
		SellView.showConfirm(refs, "Sell?")
		T.truthy(refs.Confirm.Visible, "confirm shown")
		SellView.hideConfirm(refs)
		T.falsy(refs.Confirm.Visible, "confirm hidden")
		-- the last sale shows in the header (toasts are behind the panel)
		SellView.layout(refs, false, 1280, 690)
		SellView.showReceipt(refs, "Tobin paid $5 for 1 item.", Theme.Good)
		T.truthy(refs.Receipt.Visible, "receipt shown")
		T.falsy(refs.Subtitle.Visible, "instead of the subtitle")
		SellView.hideReceipt(refs)
		T.falsy(refs.Receipt.Visible, "receipt hidden")
		T.truthy(refs.Subtitle.Visible, "subtitle back")
	end)
end
