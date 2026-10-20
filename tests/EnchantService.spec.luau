-- EnchantService (the Enchant shop at the rune table) and EnchantView
-- under Lune: the counter prompt, buying tiers for coins and shards with
-- the Tier the card shows (no double buys: "Stale"; "Max"), a new enchant
-- going into the first free slot, the Mythics' 20 R$ passes answered with
-- PurchasePrompt and never granted, the paid-random policy for odds
-- boosters, the range, slots (Locked, NotOwned, BadSlot, moving, emptying),
-- the bonuses the slotted enchants give, a fuzz run, and that the view
-- offers exactly what the server quotes, shows the new odds in numbers
-- before any buy of an odds booster (the lasting odds: Hexa Lucky left
-- out; "IN A SLOT" when the buy doesn't slot it, with every slot full the
-- odds with it in place of the least lucky slotted enchant; no artifact
-- rows while artifacts are coming soon), "Coming soon" for an enchant
-- whose package isn't in the game yet, the effect on every catalog row,
-- a gamepad that starts on the picked row (never a buy button), and fits
-- phones (44 pt targets, the gamepad row on phones / TVs, slot texts that
-- fit after a new layout).
-- Save data, players and Net are small fakes; EconomyService runs for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local EnchantConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EnchantConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local Receipts = Loader.requirePath("ServerScriptService.Server.Receipts")
	local Shards = Loader.requirePath("ServerScriptService.Server.Shards")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local BoostService = Loader.requirePath("ServerScriptService.Server.Services.BoostService")
	local EnchantService = Loader.requirePath("ServerScriptService.Server.Services.EnchantService")
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local EnchantView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EnchantView")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")

	local TABLE = Vector3.new(-30, 3, 40)
	local shop = EnchantService._test
	local Reasons = EnchantConfig.Reasons

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

	local function fakePlayer(userId: number): any
		local p: any = { UserId = userId, Name = "E" .. userId, Parent = true, attrs = {} }
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.humanoid = { Health = 100 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name: string)
				return if name == "HumanoidRootPart" then p.root else nil
			end,
		}
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, bought = {}, prompts = {}, policyCalls = 0, restricted = false }
		w.player = fakePlayer(701)
		w.data = deepCopy(DataTemplate)
		w.data.BlasterLevel = 1
		w.data.Coins = 0
		w.loaded = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			if p == w.player and w.loaded then
				return w.data
			end
			return nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		Policy._test.reset()
		Policy._test.setFetcher(function()
			w.policyCalls += 1
			return { ArePaidRandomItemsRestricted = w.restricted, IsPaidItemTradingAllowed = false }
		end)
		BoostService._test.reset()
		Receipts._test.reset()
		Receipts._test.setPublisher(function() end)
		BoostService._test.setPrompter(function(p, product)
			table.insert(w.prompts, { Player = p, Product = product })
		end)
		-- every package that reads an enchant is in the game (the coming-soon test turns one off)
		BoostService._test.setHasService(function()
			return true
		end)
		shop.reset()
		EnchantService.onBought(function(p, id, tier, currency)
			table.insert(w.bought, { Player = p, Id = id, Tier = tier, Currency = currency })
		end)
		-- the rune table top, like the Enchant district builds it (customer side = -Z)
		local hut = Instance.new("Model")
		local counter = Instance.new("Part")
		counter.Size = Vector3.new(3.6, 0.2, 1.9)
		counter.CFrame = CFrame.lookAt(TABLE, TABLE + Vector3.new(0, 0, 1))
		counter.Parent = hut
		shop.hookCounter(counter)
		w.counter = counter
		w.standAt = function(away: number)
			local front = counter.CFrame * CFrame.new(0, 0, -(counter.Size.Z / 2 + away))
			w.player.root.Position = front.Position
			w.player.root.CFrame = front
		end
		w.standAt(3)
		w.restore = function()
			shop.reset()
			BoostService._test.reset()
			Receipts._test.reset()
			Policy._test.reset()
			MonetizationConfig.CoinPacksEnabled = false
			for _, product in MonetizationConfig.List do
				product.Id = 0
			end
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

	local function notes(w: any, name: string): { any }
		local out = {}
		for _, note in w.notes do
			if note.Name == name then
				table.insert(out, note)
			end
		end
		return out
	end

	-- One EnchantAction; returns its one answer ({ Name, A }).
	local function act(w: any, action: any, payload: any): any
		local count = function(): number
			return #notes(w, "ActionResult") + #notes(w, "PurchasePrompt")
		end
		local before = count()
		shop.enchantAction(w.player, action, payload)
		T.eq(count(), before + 1, "exactly one answer per request")
		local last
		for _, note in w.notes do
			if note.Name == "ActionResult" or note.Name == "PurchasePrompt" then
				last = note
			end
		end
		return last
	end

	local function buy(w: any, id: any, currency: any, tier: any): any
		local answer = act(w, "Buy", { Id = id, Currency = currency, Tier = tier })
		T.eq(answer.Name, "ActionResult")
		T.eq(answer.A.Action, "Enchant")
		T.eq(answer.A.Op, "Buy")
		return answer.A
	end

	local function slot(w: any, index: any, id: any): any
		local answer = act(w, "Slot", { Slot = index, Id = id })
		T.eq(answer.Name, "ActionResult")
		T.eq(answer.A.Op, "Slot")
		return answer.A
	end

	local function refused(w: any, id: any, currency: any, tier: any, reason: string, label: string)
		local coins = w.data.Coins
		local shards = Shards.get(w.data)
		local enchants = deepCopy(w.data.Enchants)
		local r = buy(w, id, currency, tier)
		T.eq(r.Ok, false, label .. ": refused")
		T.eq(r.Reason, reason, label .. ": reason")
		T.truthy(Reasons[reason], label .. ": the reason has a text")
		T.eq(w.data.Coins, coins, label .. ": coins kept")
		T.eq(Shards.get(w.data), shards, label .. ": shards kept")
		for key, value in enchants.Owned do
			T.eq(w.data.Enchants.Owned[key], value, label .. ": owned kept " .. key)
		end
		for key in w.data.Enchants.Owned do
			T.truthy(enchants.Owned[key] ~= nil, label .. ": nothing new " .. key)
		end
		for i = 1, EnchantConfig.MaxSlots do
			T.eq(w.data.Enchants.Slots[i], enchants.Slots[i], label .. ": slot kept " .. i)
		end
	end

	---------------------------------------------------------------- the counter

	withWorld("EnchantService: the rune table gets an Enchant prompt and opens the view near it", function(w)
		local point = w.counter:FindFirstChild(EnchantService.PointName)
		T.truthy(point and point:IsA("Attachment"), "prompt point")
		T.truthy(point.CFrame.Position.Z < 0, "on the customer side (-Z)")
		local prompt = point:FindFirstChild(EnchantService.PromptName)
		T.truthy(prompt and prompt:IsA("ProximityPrompt"), "prompt")
		T.eq(prompt.ActionText, "Enchant")
		T.eq(prompt.KeyboardKeyCode, roblox.Enum.KeyCode.F)
		T.eq(prompt.GamepadKeyCode, roblox.Enum.KeyCode.ButtonY)
		T.falsy(prompt.RequiresLineOfSight)
		shop.hookCounter(w.counter)
		local n = 0
		for _, child in w.counter:GetChildren() do
			if child.Name == EnchantService.PointName then
				n += 1
			end
		end
		T.eq(n, 1, "hooked once")
		shop.open(w.player, w.counter)
		local opened = notes(w, "OpenUI")
		T.eq(#opened, 1)
		T.eq(opened[1].A, "Enchant")
		T.truthy(opened[1].B.Counter == w.counter)
		w.standAt(EnchantService.Range + 5)
		shop.open(w.player, w.counter)
		T.eq(#notes(w, "OpenUI"), 1, "not from far away")
		T.truthy(prompt.MaxActivationDistance < EnchantView.CloseRange, "the prompt reaches less than the view stays open")
		T.truthy(EnchantView.CloseRange + 4 <= EnchantService.Range, "the server is the lenient side")
		w.standAt(EnchantView.CloseRange)
		w.data.Coins = 2000
		T.eq(buy(w, "Power", "Coins", 1).Ok, true, "a buy from where the view is still open")
		-- a counter that leaves is dropped, with its prompt
		shop.unhookCounter(w.counter)
		T.eq(#shop.counters(), 0)
		T.eq(w.counter:FindFirstChild(EnchantService.PointName), nil)
		T.eq(buy(w, "Swift", "Coins", 1).Reason, "TooFar", "no table: too far")
	end)

	---------------------------------------------------------------- buying

	withWorld("EnchantService: buying tiers for coins (the Tier the card shows, never twice)", function(w)
		local power = EnchantConfig.ById.Power
		w.data.Coins = power.Coins[1] + 5
		local r = buy(w, "Power", "Coins", 1)
		T.eq(r.Ok, true, "bought")
		T.eq(r.Id, "Power")
		T.eq(r.Level, 1, "the new tier")
		T.eq(w.data.Coins, 5, "paid the price")
		T.eq(w.data.Enchants.Owned.Power, 1)
		T.eq(w.data.Enchants.Slots[1], "Power", "a new enchant goes into the first free slot")
		T.truthy(w.changed > 0, "DataService.changed")
		local toast = notes(w, "Notify")
		T.eq(toast[1].A.Kind, "Reward")
		T.eq(toast[1].A.Text, "Power I is in slot 1 of your blaster!")
		T.eq(#w.bought, 1, "onBought")
		T.eq(w.bought[1].Tier, 1)
		T.eq(w.bought[1].Currency, "Coins")
		-- a double tap (the same Tier again) never buys a second tier
		w.data.Coins = 1e9
		refused(w, "Power", "Coins", 1, "Stale", "double tap")
		refused(w, "Power", "Coins", 3, "Stale", "skipping a tier")
		T.eq(buy(w, "Power", "Coins", 2).Ok, true, "tier II")
		T.eq(w.data.Coins, 1e9 - power.Coins[2])
		T.eq(notes(w, "Notify")[2].A.Text, "Power II: your enchant got stronger!")
		T.eq(buy(w, "Power", "Coins", 3).Ok, true, "tier III")
		refused(w, "Power", "Coins", 4, "Max", "past the top tier")
		T.eq(w.data.Enchants.Owned.Power, 3)
		T.eq(w.data.Enchants.Slots[1], "Power", "still in its slot")
		-- the slotted enchant's bonus reaches the game
		local stats = Bonuses.compute(w.data, os.time(), nil)
		T.near(stats.DamagePct, 0.35, 1e-9, "Power III: +35% damage")
		-- all open slots full (level 1: one slot): a new enchant isn't slotted
		w.data.Coins = EnchantConfig.ById.Swift.Coins[1]
		T.eq(buy(w, "Swift", "Coins", 1).Ok, true)
		T.eq(w.data.Enchants.Slots[1], "Power", "the slot keeps Power")
		T.eq(w.data.Enchants.Owned.Swift, 1, "owned")
		local last = notes(w, "Notify")
		T.eq(last[#last].A.Text, "Swift I bought! Put it in a slot to use it.")
	end)

	withWorld("EnchantService: shards pay for Epic and Legendary enchants", function(w)
		local twin = EnchantConfig.ById.TwinDrop
		w.data.Shards = (twin.Shards :: { number })[1] + 3
		w.data.Coins = 0
		local r = buy(w, "TwinDrop", "Shards", 1)
		T.eq(r.Ok, true, "bought with shards")
		T.eq(Shards.get(w.data), 3, "shards spent")
		T.eq(w.data.Coins, 0, "no coins")
		T.eq(w.data.Enchants.Owned.TwinDrop, 1)
		refused(w, "TwinDrop", "Shards", 2, "NoShards", "too few shards")
		refused(w, "Power", "Shards", 1, "BadCurrency", "a Common enchant isn't sold for shards")
		refused(w, "Power", "Gems", 1, "BadCurrency", "an unknown currency")
		refused(w, "Power", 5, 1, "BadCurrency", "a number as currency")
		-- a broken shard balance counts as 0
		w.data.Shards = 0 / 0
		refused(w, "TwinDrop", "Shards", 2, "NoShards", "NaN shards")
		w.data.Shards = "lots"
		refused(w, "TwinDrop", "Shards", 2, "NoShards", "a string")
	end)

	withWorld("EnchantService: the Mythics' 20 R$ passes are prompted, never granted", function(w)
		w.data.Coins = 50
		local answer = act(w, "Buy", { Id = "Heartfire", Currency = "Robux", Tier = 1 })
		T.eq(answer.Name, "PurchasePrompt", "a PurchasePrompt")
		T.eq(answer.A.Product, "EnchantHeartfire")
		T.eq(answer.A.Status, "ComingSoon", "the pass id is 0")
		T.eq(#w.prompts, 0, "no prompt")
		T.eq(EnchantConfig.tierOf(w.data.Enchants, "Heartfire"), 0, "never granted")
		T.eq(w.data.Coins, 50)
		-- a live pass id before step 8 grants passes: still Coming soon
		MonetizationConfig.Products.EnchantHeartfire.Id = 123
		answer = act(w, "Buy", { Id = "Heartfire", Currency = "Robux", Tier = 1 })
		T.eq(answer.A.Status, "ComingSoon", "receipts gate off")
		T.eq(#w.prompts, 0, "no prompt")
		-- live and step 8 ready: the game pass prompt
		Receipts.setReady(true)
		answer = act(w, "Buy", { Id = "Heartfire", Currency = "Robux", Tier = 1 })
		T.eq(answer.A.Status, "Prompted")
		T.eq(w.prompts[1].Product.Kind, "GamePass")
		T.eq(EnchantConfig.tierOf(w.data.Enchants, "Heartfire"), 0, "still not granted (step 8)")
		-- Starbreaker changes odds: a paid random item with Robux; restricted players get Restricted
		w.restricted = true
		refused(w, "Starbreaker", "Robux", 1, "Restricted", "restricted")
		T.eq(w.policyCalls, 1, "the policy was asked")
		T.eq(w.player.attrs.PaidRandomRestricted, true)
		-- its coin price is not a paid random item while coins can't be bought
		w.data.Coins = 1e12
		T.eq(buy(w, "Starbreaker", "Coins", 1).Ok, true, "1T coins")
		T.eq(w.policyCalls, 1, "no policy call for a coin buy")
		refused(w, "Starbreaker", "Robux", 2, "Max", "owned: no Robux option")
		-- Robux for an enchant without a pass
		refused(w, "Power", "Robux", 1, "BadCurrency", "no pass for Power")
	end)

	withWorld("EnchantService: with coin packs on, coin and shard buys of odds boosters are paid random items", function(w)
		MonetizationConfig.CoinPacksEnabled = true
		w.restricted = true
		w.data.Coins = 1e12
		w.data.Shards = 1e6
		refused(w, "Lucky", "Coins", 1, "Restricted", "Lucky for coins")
		refused(w, "Prospector", "Shards", 1, "Restricted", "Prospector for shards")
		T.eq(buy(w, "Power", "Coins", 1).Ok, true, "other enchants stay for sale")
		Policy._test.reset()
		w.restricted = false
		T.eq(buy(w, "Lucky", "Coins", 1).Ok, true, "allowed elsewhere")
	end)

	withWorld("EnchantService: bad requests are refused with a reason and change nothing", function(w)
		w.data.Coins = 1e12
		refused(w, "Nope", "Coins", 1, "BadItem", "unknown enchant")
		refused(w, nil, "Coins", 1, "BadItem", "no id")
		refused(w, 7, "Coins", 1, "BadItem", "a number id")
		refused(w, string.rep("x", 100), "Coins", 1, "BadItem", "a long id")
		refused(w, "Power", "Coins", 0, "Stale", "tier 0")
		refused(w, "Power", "Coins", 1.5, "Stale", "a fraction")
		refused(w, "Power", "Coins", 0 / 0, "Stale", "NaN")
		refused(w, "Power", "Coins", "1", "Stale", "a string tier")
		w.data.Coins = 10
		refused(w, "Power", "Coins", 1, "NoCoins", "too poor")
		w.standAt(EnchantService.Range + 2)
		w.data.Coins = 1e12
		refused(w, "Power", "Coins", 1, "TooFar", "away from the table")
		w.standAt(2)
		-- junk payloads
		T.eq(act(w, "Buy", nil).A.Reason, "BadItem")
		T.eq(act(w, "Buy", "Power").A.Reason, "BadItem")
		T.eq(act(w, "Buy", setmetatable({ Id = "Power" }, {})).A.Reason, "BadItem", "a table with a metatable")
		T.eq(act(w, "Dance", { Id = "Power" }).A.Op, "Dance")
		T.eq(act(w, 5, nil).A.Op, "")
		-- no save loaded
		w.loaded = false
		T.eq(act(w, "Buy", { Id = "Power", Currency = "Coins", Tier = 1 }).A.Reason, "BadItem")
		T.eq(act(w, "Slot", { Slot = 1, Id = "" }).A.Reason, "BadItem")
		T.eq(w.changed, 0, "nothing saved")
	end)

	---------------------------------------------------------------- slots

	withWorld("EnchantService: slots (open by blaster level, owned enchants only, free and anywhere)", function(w)
		w.data.Enchants.Owned = { Power = 2, Lucky = 1, Swift = 1 }
		w.data.BlasterLevel = 4 -- two open slots
		w.standAt(500) -- slot changes work anywhere
		T.eq(slot(w, 1, "Power").Ok, true)
		T.eq(slot(w, 2, "Lucky").Ok, true)
		T.eq(w.data.Enchants.Slots[1], "Power")
		T.eq(w.data.Enchants.Slots[2], "Lucky")
		local r = slot(w, 3, "Swift")
		T.eq(r.Reason, "Locked", "slot 3 opens at level 7")
		T.eq(slot(w, 5, "Swift").Reason, "BadSlot")
		T.eq(slot(w, 0, "Swift").Reason, "BadSlot")
		T.eq(slot(w, 1.5, "Swift").Reason, "BadSlot")
		T.eq(slot(w, nil, "Swift").Reason, "BadSlot")
		T.eq(slot(w, 1, "Midas").Reason, "NotOwned")
		T.eq(slot(w, 1, "Nope").Reason, "BadItem")
		T.eq(slot(w, 1, 5).Reason, "BadItem", "a number id")
		-- moving: an enchant sits in one slot at most
		T.eq(slot(w, 2, "Power").Ok, true, "Power moves to slot 2")
		T.eq(w.data.Enchants.Slots[1], "", "slot 1 emptied")
		T.eq(w.data.Enchants.Slots[2], "Power")
		-- emptying
		T.eq(slot(w, 2, "").Ok, true)
		T.eq(w.data.Enchants.Slots[2], "")
		T.eq(slot(w, 1, nil).Ok, true, "nil empties too")
		-- the bonuses follow the open slots only
		T.eq(slot(w, 1, "Lucky").Ok, true)
		local stats = Bonuses.compute(w.data, os.time(), nil)
		T.near(stats.OreLuckPct, 0.15, 1e-9, "Lucky I in slot 1")
		-- a broken record is rebuilt for a real change, never for a refused one
		w.data.Enchants = "junk"
		T.eq(slot(w, 1, "Lucky").Reason, "NotOwned", "nothing owned in a broken record")
		T.eq(w.data.Enchants, "junk", "a refused request writes nothing")
		T.eq(slot(w, 1, "").Ok, true, "emptying works")
		T.eq(type(w.data.Enchants), "table", "rebuilt")
		T.eq(#w.data.Enchants.Slots, EnchantConfig.MaxSlots)
	end)

	---------------------------------------------------------------- fuzz

	withWorld("EnchantService: fuzz (random buys and slots): one answer each, prices exact, nothing lost", function(w)
		local rng = Rng.new(777)
		local ids = { "Power", "Swift", "Lucky", "TwinDrop", "Prospector", "Heartfire", "Starbreaker", "Nope", nil :: any }
		local currencies = { "Coins", "Shards", "Robux", "Coins", 3 }
		w.data.BlasterLevel = 7
		for _ = 1, 500 do
			w.data.Coins = rng:int(0, 4) * 10 ^ rng:int(3, 12)
			w.data.Shards = rng:int(0, 2000)
			local id = ids[rng:int(1, #ids)]
			if rng:int(1, 3) == 1 then
				local before = deepCopy(w.data.Enchants)
				local index = rng:int(0, 5)
				local target = if rng:int(1, 4) == 1 then "" else id
				local r = slot(w, index, target)
				if r.Ok then
					local count = 0
					for i = 1, EnchantConfig.MaxSlots do
						local s = w.data.Enchants.Slots[i]
						T.truthy(s == "" or EnchantConfig.tierOf(w.data.Enchants, s) > 0, "only owned enchants in slots")
						if s ~= "" and s == target then
							count += 1
						end
					end
					T.truthy(count <= 1, "in one slot at most")
				else
					for i = 1, EnchantConfig.MaxSlots do
						T.eq(w.data.Enchants.Slots[i], before.Slots[i], "a refused slot change writes nothing")
					end
				end
			else
				local currency = currencies[rng:int(1, #currencies)]
				local owned = if type(id) == "string" then EnchantConfig.tierOf(w.data.Enchants, id) else 0
				local tier = owned + (if rng:int(1, 5) == 1 then rng:int(-1, 2) else 1)
				local coins, shards = w.data.Coins, Shards.get(w.data)
				local answer = act(w, "Buy", { Id = id, Currency = currency, Tier = tier })
				if answer.Name == "PurchasePrompt" then
					T.eq(answer.A.Status, "ComingSoon", "placeholders only")
					T.eq(w.data.Coins, coins)
					T.eq(EnchantConfig.tierOf(w.data.Enchants, id), owned, "Robux never grants here")
				elseif answer.A.Ok then
					local coinPrice, shardPrice = EnchantConfig.nextPrice(id, owned)
					T.eq(EnchantConfig.tierOf(w.data.Enchants, id), owned + 1, "exactly one tier")
					if currency == "Coins" then
						T.eq(coins - w.data.Coins, coinPrice, "paid the coin price")
						T.eq(Shards.get(w.data), shards)
					else
						T.eq(shards - Shards.get(w.data), shardPrice, "paid the shard price")
						T.eq(w.data.Coins, coins)
					end
				else
					T.eq(w.data.Coins, coins, "refused: no coins taken")
					T.eq(Shards.get(w.data), shards, "refused: no shards taken")
					if type(id) == "string" then
						T.eq(EnchantConfig.tierOf(w.data.Enchants, id), owned, "refused: no tier")
					end
				end
				T.truthy(w.data.Coins >= 0 and Shards.get(w.data) >= 0, "never below 0")
			end
		end
		T.eq(#w.prompts, 0)
	end)

	withWorld("EnchantService: an enchant nothing reads yet is coming soon (shown, refused, nothing taken)", function(w)
		BoostService._test.setHasService(function(name: string): boolean
			return name ~= "ArtifactService"
		end)
		w.data.Coins = 1e12
		Shards.add(w.data, 10000)
		local r = buy(w, "Prospector", "Coins", 1)
		T.eq(r.Ok, false)
		T.eq(r.Reason, "ComingSoon", "no artifacts yet: Prospector is coming soon")
		T.eq(w.data.Coins, 1e12, "no coins taken")
		T.eq(EnchantConfig.tierOf(w.data.Enchants, "Prospector"), 0, "not granted")
		T.eq(buy(w, "Prospector", "Shards", 1).Reason, "ComingSoon", "shards too")
		T.eq(buy(w, "Power", "Coins", 1).Ok, true, "the others still sell")
		local s = {
			BlasterLevel = 5,
			Shards = 500,
			Enchants = { Owned = {}, Slots = { "", "", "", "" } },
			Bonuses = {},
			Boosts = {},
		}
		local soon = BoostView.soonSet("Prospector")
		for _, card in EnchantView.cards(s, 1e12, false, soon) do
			if card.Id == "Prospector" then
				T.eq(#card.Buys, 1, "one button")
				T.eq(card.Buys[1].Text, "COMING SOON")
				T.falsy(card.Buys[1].CanBuy)
				T.eq(card.Buys[1].Reason, "ComingSoon")
				T.eq(card.ListLine, EnchantView.SoonText.Prospector)
			else
				for _, option in card.Buys do
					T.truthy(option.Reason ~= "ComingSoon" or option.Currency == "Robux", card.Id .. " sells")
				end
			end
		end
		T.eq(EnchantView.reasonText("ComingSoon"), MonetizationConfig.StatusText.ComingSoon)
	end)

	---------------------------------------------------------------- the view

	local NOW = 1_800_000_000

	local function state(over: { [string]: any }?): { [string]: any }
		local s: { [string]: any } = {
			Coins = 5e6,
			BlasterLevel = 5,
			Shards = 120,
			Enchants = { Owned = { Power = 2, Lucky = 1, TwinDrop = 1 }, Slots = { "Power", "Lucky", "", "" } },
			Boosts = { TripleLuckyUntil = 0, HexaLuckyUntil = 0 },
			Bonuses = { OreLuckPct = 0.15, OreLuckMult = 1, ArtifactPct = 0 },
			Perks = { ForgeVip = false },
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	T.test("EnchantView: the cards offer exactly what the server quotes", function()
		for _, coins in { 0, 1e5, 1e13 } do
			for _, shards in { 0, 200, 5000 } do
				local s = state({ Shards = shards })
				local cards = EnchantView.cards(s, coins, false)
				T.eq(#cards, #EnchantConfig.List, "every enchant")
				for _, card in cards do
					local owned = EnchantConfig.tierOf(s.Enchants, card.Id)
					T.eq(card.Tier, owned)
					for _, option in card.Buys do
						if option.Currency == "Max" then
							T.truthy(card.Done)
						else
							T.eq(option.Tier, owned + 1, "the Tier the server wants")
							local price, reason = EnchantConfig.quote(s.Enchants, card.Id, option.Currency, option.Tier, false)
							if option.Currency == "Robux" then
								T.eq(reason, "Robux", "a Robux option exists only where the server prompts")
								T.eq(option.Reason, "ComingSoon")
								T.falsy(option.CanBuy)
							else
								T.eq(option.Price, price, "the quoted price")
								local balance = if option.Currency == "Coins" then coins else shards
								T.eq(option.CanBuy, balance >= (price :: number), "affordable exactly when the server sells")
							end
						end
					end
				end
			end
		end
		local cards = EnchantView.cards(state(), 5e6, false)
		local byId = {}
		for _, card in cards do
			byId[card.Id] = card
		end
		T.eq(byId.Power.TierText, "II / III")
		T.eq(byId.Power.Slot, 1)
		T.eq(byId.Power.Now, "Now: +20% blaster damage")
		T.eq(byId.Power.Next, "Next: +35% blaster damage")
		T.eq(byId.Swift.TierText, "NEW")
		T.eq(byId.Swift.Next, "Buy: +1 walk speed")
		T.eq(byId.TwinDrop.ListLine, `Owned: not in a slot{EnchantView.Separator}next $300M`)
		T.eq(byId.Heartfire.ListLine, "$1T or 20 R$ (soon)", "the pass isn't on sale yet")
		T.eq(byId.Heartfire.Buys[2].Text, "20 R$ • SOON", "the button shows the price too, greyed")
		T.falsy(byId.Heartfire.Buys[2].CanBuy)
		-- every catalog row says what the enchant does (the owned tier, else tier I)
		T.eq(byId.Power.Effect, "+20% blaster damage", "Power II owned")
		T.eq(byId.Swift.Effect, "+1 walk speed", "not owned: tier I")
		T.eq(byId.Starbreaker.Effect, table.concat(EnchantConfig.describe("Starbreaker", 1), ", "), "both effects")
		for _, card in cards do
			T.truthy(#card.Effect > 0, card.Id .. ": an effect line")
		end
		T.truthy(byId.Lucky.Odds and byId.Prospector.Odds and byId.Starbreaker.Odds, "odds boosters marked")
		T.falsy(byId.Power.Odds)
		-- where paid random items are restricted: Starbreaker's pass goes, Heartfire's stays
		local restricted = {}
		for _, card in EnchantView.cards(state(), 5e6, true) do
			restricted[card.Id] = card
		end
		local function has(card: any, currency: string): boolean
			for _, option in card.Buys do
				if option.Currency == currency then
					return true
				end
			end
			return false
		end
		T.falsy(has(restricted.Starbreaker, "Robux"), "no Starbreaker pass where restricted")
		T.truthy(has(restricted.Starbreaker, "Coins"), "its coin price stays")
		T.truthy(has(restricted.Heartfire, "Robux"), "Heartfire's pass changes no odds")
		T.falsy(restricted.Starbreaker.ListLine:find("R%$"), "the list line drops the R$ too")
		-- a live pass shows its price
		MonetizationConfig.Products.EnchantHeartfire.Id = 5
		local live = EnchantView.cards(state(), 0, false)
		-- a live pass waits for step 8's receipts gate (the controllers pass soonNow)
		local gated = EnchantView.cards(state(), 0, false, BoostView.soonNow(nil, false))
		local opened = EnchantView.cards(state(), 0, false, BoostView.soonNow(nil, true))
		MonetizationConfig.Products.EnchantHeartfire.Id = 0
		for _, card in gated do
			if card.Id == "Heartfire" then
				T.eq(card.Buys[2].Text, "20 R$ • SOON", "receipts not ready: greyed")
				T.falsy(card.Buys[2].CanBuy)
				T.eq(card.Buys[2].Reason, "ComingSoon")
			end
		end
		for _, card in opened do
			if card.Id == "Heartfire" then
				T.truthy(card.Buys[2].CanBuy, "receipts ready: sold")
			end
		end
		for _, card in live do
			if card.Id == "Heartfire" then
				T.eq(card.Buys[2].Text, "20 R$")
				T.truthy(card.Buys[2].CanBuy)
				T.eq(card.ListLine, "$1T or 20 R$", "a live pass: its price")
			end
		end
		-- the slots
		local slots = EnchantView.slotCards(state())
		T.eq(#slots, EnchantConfig.MaxSlots)
		T.eq(slots[1].Name, "POWER II")
		T.eq(slots[1].Sub, "+20% damage", "a slot shows its main effect in short")
		T.eq(slots[2].Sub, "+15% ore luck")
		T.eq(EnchantView.shortEffect("Reach", 2), "+4 studs range")
		T.eq(EnchantView.shortEffect("Heartfire", 1), "+75% damage", "the main effect of two")
		T.eq(EnchantView.shortEffect("Starbreaker", 1), "+75% ore luck")
		T.eq(EnchantView.shortEffect("Overcharge", 1), "+25% surge")
		for _, enchant in EnchantConfig.List do
			T.truthy(#EnchantView.shortEffect(enchant.Id, 1) > 0, enchant.Id .. ": a short effect")
		end
		T.eq(slots[3].Open, false)
		T.eq(slots[3].Sub, "Blaster level 7")
		T.eq(EnchantView.slotCards(state({ BlasterLevel = 10 }))[4].Name, "EMPTY")
	end)

	T.test("EnchantView: odds boosters show the new odds in numbers (BoostConfig.preview)", function()
		local s = state()
		for _, zone in BoostView.zones(s) do
			local t, canSwitch = EnchantView.odds(s, "Lucky", zone.Id, NOW)
			T.truthy(t and canSwitch, zone.Id .. ": a table with zones to switch")
			local tbl = t :: any
			local ctx = BoostView.context(s, NOW)
			local preview = BoostConfig.preview(ctx, EnchantConfig.nextDelta(s.Enchants, 5, "Lucky"))
			for _, effect in preview.Zones do
				if effect.Zone == zone.Id then
					T.eq(#tbl.Rows, #effect.Rarities, zone.Id .. ": one row per lucky rarity")
					for i, line in effect.Rarities do
						T.eq(tbl.Rows[i].Before, BoostView.pct(line.Before))
						T.eq(tbl.Rows[i].After, BoostView.pct(line.After))
					end
					if effect.NoEffect then
						T.eq(tbl.Summary, nil)
						T.truthy(tbl.Note:find("changes nothing"), "says so")
					else
						T.eq(tbl.Summary.Before, BoostView.pct(effect.Before))
						T.eq(tbl.Summary.After, BoostView.pct(effect.After))
						T.truthy(effect.After > effect.Before, "Rare+ grows")
					end
				end
			end
			T.eq(tbl.Title, zone.Name)
		end
		-- Starbreaker: luck rows plus the artifact chance per rock
		local star = EnchantView.odds(s, "Starbreaker", "DeepHollow", NOW) :: any
		local last = star.Rows[#star.Rows]
		T.eq(last.Name, "Artifact", "the artifact chance per rock")
		T.truthy(last.Change > 0)
		-- Prospector: artifacts only, one row per zone, nothing to switch
		local pro, switch = EnchantView.odds(s, "Prospector", nil, NOW)
		T.falsy(switch)
		T.eq(#(pro :: any).Rows, #BoostView.zones(s), "every zone")
		-- no odds for other enchants or at the top tier
		T.eq(EnchantView.odds(s, "Power", "DeepHollow", NOW), nil)
		local top = state({ Enchants = { Owned = { Lucky = 3 }, Slots = { "Lucky", "", "", "" } } })
		T.eq(EnchantView.odds(top, "Lucky", "DeepHollow", NOW), nil, "top tier: nothing to buy")
		-- ore luck at its cap: the card says the buy changes nothing
		local capped = state({ Bonuses = { OreLuckPct = 1.5, OreLuckMult = 2.5, ArtifactPct = 0 }, Boosts = { HexaLuckyUntil = NOW + 60 } })
		local c = EnchantView.odds(capped, "Lucky", "DeepHollow", NOW) :: any
		T.truthy(c.Note:find("cap"), "at the cap")
		T.eq(c.Summary.Before, c.Summary.After, "no change")
		T.near(StatConfig.MaxOreLuck, 6.25, 1e-9)
		-- the lasting odds: a running Hexa Lucky is left out (Lucky I + Hexa: Starbreaker
		-- shows x1.15 -> x1.9, not the temporary x2.88 -> x4)
		local hexa = state({ Bonuses = { OreLuckPct = 0.15, OreLuckMult = 2.5, ArtifactPct = 0 }, Boosts = { HexaLuckyUntil = NOW + 600 } })
		local withHexa = EnchantView.odds(hexa, "Starbreaker", "DeepHollow", NOW) :: any
		local without = EnchantView.odds(state(), "Starbreaker", "DeepHollow", NOW) :: any
		T.eq(withHexa.Summary.Before, without.Summary.Before, "NOW without Hexa Lucky")
		T.eq(withHexa.Summary.After, without.Summary.After, "AFTER without Hexa Lucky")
		T.truthy(withHexa.Note:find("Hexa Lucky isn't counted"), "says so")
		T.falsy(without.Note:find("Hexa"), "no note without it")
		-- where the buy's luck lands: AFTER BUY in a slot, else IN A SLOT
		T.eq((EnchantView.odds(state(), "Lucky", "DeepHollow", NOW) :: any).AfterHeader, "AFTER BUY", "slotted")
		local full = EnchantView.odds(state(), "Starbreaker", "DeepHollow", NOW) :: any
		T.eq(full.AfterHeader, "IN A SLOT", "both open slots full: the buy doesn't slot it")
		T.truthy(full.Note:find("open slot is full"), "says so")
		T.truthy(full.Note:find("in place of Power"), "AFTER with it in place of the slotted enchant that changes no odds")
		T.truthy(full.Note:find("chance of each rarity"), "the rows are per rarity, the note says so")
		T.falsy(full.Note:find("chance per ore"), "not per ore")
		-- every slot holds an odds booster: AFTER is with it in place of the least lucky one,
		-- its luck taken out (the numbers can really be reached)
		local lucky = state({
			BlasterLevel = 5,
			Enchants = { Owned = { Lucky = 1, Prospector = 1 }, Slots = { "Lucky", "Prospector", "", "" } },
			Bonuses = { OreLuckPct = 0.15, OreLuckMult = 1, ArtifactPct = 0.25 },
		})
		T.eq(EnchantView.replaceTarget(lucky.Enchants, 5, "Starbreaker"), "Lucky", "the least luck")
		T.eq(EnchantView.replaceTarget(lucky.Enchants, 5, "Lucky"), nil, "slotted: nothing replaced")
		T.eq(EnchantView.replaceTarget(lucky.Enchants, 7, "Starbreaker"), nil, "a free slot: nothing replaced")
		local swap = EnchantView.odds(lucky, "Starbreaker", "DeepHollow", NOW) :: any
		T.truthy(swap.Note:find("in place of Lucky"), "names it")
		local luckNow = StatConfig.oreLuck(0.15, 1)
		local luckAfter = StatConfig.oreLuck(0.75, 1) -- Lucky's 0.15 out, Starbreaker's 0.75 in
		T.truthy(swap.Note:find(BoostView.mult(luckAfter), 1, true), "the luck it really reaches")
		T.truthy(BoostView.zones(lucky)[1] ~= nil and table.find(EnchantView.zoneIds(lucky), "DeepHollow"), "Deep Hollow in reach")
		for _, effect in BoostConfig.zoneEffects(5, false, luckNow, luckAfter) do
			if effect.Zone == "DeepHollow" then
				T.eq(swap.Summary.Before, BoostView.pct(effect.Before))
				T.eq(swap.Summary.After, BoostView.pct(effect.After))
			end
		end
		local art = swap.Rows[#swap.Rows]
		T.eq(art.Name, "Artifact")
		local chance = BoostConfig.preview(BoostView.context(lucky, NOW), {}).Artifacts :: any
		for _, line in chance do
			if line.Zone == "DeepHollow" then
				T.eq(art.Before, BoostView.pct(line.Before), "artifact chance now")
			end
		end
		-- while artifacts aren't in the game: no artifact rows; Prospector's table stays as information
		local soon = BoostView.soonSet("Prospector")
		local starSoon = EnchantView.odds(state(), "Starbreaker", "DeepHollow", NOW, soon) :: any
		for _, row in starSoon.Rows do
			T.truthy(row.Name ~= "Artifact", "no artifact row while artifacts are coming soon")
		end
		T.truthy(starSoon.Note:find("Artifacts: coming soon"), "says so")
		T.eq(#starSoon.Rows, #(EnchantView.odds(state(), "Starbreaker", "DeepHollow", NOW) :: any).Rows - 1)
		local proSoon = EnchantView.odds(state(), "Prospector", nil, NOW, soon) :: any
		T.truthy(proSoon ~= nil and #proSoon.Rows == #BoostView.zones(state()), "Prospector's table as information")
		T.truthy(proSoon.Note:find("coming soon"), "says they are coming")
		T.falsy((EnchantView.odds(state(), "Lucky", "DeepHollow", NOW, soon) :: any).Note:find("Artifacts"), "Lucky: no artifact note")
		local free = state({ Enchants = { Owned = { Power = 2 }, Slots = { "Power", "", "", "" } } })
		T.eq((EnchantView.odds(free, "Prospector", nil, NOW) :: any).AfterHeader, "AFTER BUY", "a free slot: it goes in")
		local unslotted = state({ Enchants = { Owned = { Lucky = 1 }, Slots = { "", "", "", "" } } })
		local u = EnchantView.odds(unslotted, "Lucky", "DeepHollow", NOW) :: any
		T.eq(u.AfterHeader, "IN A SLOT", "owned but not equipped: an upgrade counts once equipped")
		T.truthy(u.Note:find("equip it"), "says so")
		-- the zone list follows the blaster level (VIP zones with the pass)
		T.eq(#EnchantView.zoneIds(state({ BlasterLevel = 1 })), 2, "Outcrops and the Quarry at level 1")
		local vip = state({ BlasterLevel = 5, Perks = { ForgeVip = true } })
		T.truthy(table.find(EnchantView.zoneIds(vip), "Grotto"), "the Grotto with the VIP pass")
		T.truthy(WorldLayout.ZoneById.Grotto.VipOnly)
	end)

	local SCREENS = {
		{ Label = "PC 1280x720", Compact = false, Width = 1280, Height = 720 - 36 },
		{ Label = "PC 1600x900", Compact = false, Width = 1600 / 1.25, Height = (900 - 36) / 1.25 },
		{ Label = "big PC", Compact = false, Width = 1536, Height = 835 },
		{ Label = "phone", Compact = true, Width = 1600 / (0.62 * 900 / 375), Height = (900 - 58) / (0.62 * 900 / 375) },
		{ Label = "small phone", Compact = true, Width = 1600 / (0.62 * 900 / 320), Height = (900 - 163) / (0.62 * 900 / 320) },
		{ Label = "tablet", Compact = true, Width = 1024 / 0.62, Height = (768 - 36) / 0.62 },
		{ Label = "TV 1080p", Compact = true, Width = 1920 / 1.25, Height = (1080 - 36) / 1.25 },
	}

	local function boxIn(obj: any, parent: { number }): { number }
		local w = obj.Size.X.Scale * parent[3] + obj.Size.X.Offset
		local h = obj.Size.Y.Scale * parent[4] + obj.Size.Y.Offset
		local x = parent[1] + obj.Position.X.Scale * parent[3] + obj.Position.X.Offset - obj.AnchorPoint.X * w
		local y = parent[2] + obj.Position.Y.Scale * parent[4] + obj.Position.Y.Offset - obj.AnchorPoint.Y * h
		return { x, y, w, h }
	end

	local function overlaps(a: { number }, b: { number }): boolean
		return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
	end

	T.test("EnchantView: a gamepad starts on the picked row, never on a buy button", function()
		local s = state()
		for _, compact in { false, true } do
			local refs = EnchantView.build(compact)
			EnchantView.layout(refs, compact, 1280, 684)
			local cards = EnchantView.cards(s, 1e13, false)
			for _, card in cards do
				EnchantView.setRows(refs, cards, card.Id)
				local odds, canSwitch = EnchantView.odds(s, card.Id, "DeepHollow", NOW)
				EnchantView.setDetail(refs, card, odds, canSwitch)
				local first = EnchantView.firstButton(refs)
				T.eq(first, refs.Rows[card.Id].Button, card.Id .. ": its row")
				for _, button in refs.Detail.Buttons do
					T.truthy(first ~= button, card.Id .. ": never a buy button")
				end
				T.truthy(first ~= refs.Detail.Equip)
			end
		end
	end)

	T.test("EnchantView: layouts fit, phone targets are at least 44 pt, nothing overlaps", function()
		local s = state()
		for _, screen in SCREENS do
			local label = screen.Label
			for _, id in { "Power", "TwinDrop", "Starbreaker", "Lucky" } do
				local refs = EnchantView.build(screen.Compact)
				EnchantView.layout(refs, screen.Compact, screen.Width, screen.Height)
				local cards = EnchantView.cards(s, 5e6, false)
				local card
				for _, c in cards do
					if c.Id == id then
						card = c
					end
				end
				EnchantView.setSlots(refs, EnchantView.slotCards(s), 5, nil)
				EnchantView.setRows(refs, cards, id)
				local odds, canSwitch = EnchantView.odds(s, id, "DeepHollow", NOW)
				EnchantView.setDetail(refs, card, odds, canSwitch)
				EnchantView.setStatus(refs, EnchantView.StatusText.PickSlot, nil)
				local panel = { 0, 0, refs.Panel.Size.X.Offset, refs.Panel.Size.Y.Offset }
				T.truthy(panel[3] <= math.max(720, screen.Width - 24), label .. " width fits")
				T.truthy(panel[4] <= math.max(EnchantView.MinHeight, screen.Height - 16), label .. " height fits")
				local list = boxIn(refs.List, panel)
				local detail = boxIn(refs.Detail.Frame, panel)
				T.falsy(overlaps(list, detail), label .. " list and detail side by side")
				T.truthy(detail[1] + detail[3] <= panel[3] and detail[2] + detail[4] <= panel[4], label .. " detail inside the panel")
				T.truthy(list[2] + list[4] <= panel[4], label .. " list inside the panel")
				-- the slots: above the list, side by side, none overlapping
				local slotBoxes = {}
				for _, slot in refs.Slots do
					local box = boxIn(slot.Button.Parent, panel)
					T.truthy(box[2] + box[4] <= list[2], label .. " slots above the list")
					T.truthy(box[1] + box[3] <= detail[1], label .. " slots left of the detail")
					for _, other in slotBoxes do
						T.falsy(overlaps(box, other), label .. " slots overlap")
					end
					table.insert(slotBoxes, box)
				end
				-- the slot texts fit (short labels: "+20% damage") and the rows' effect lines too
				for _, slot in refs.Slots do
					local room = slot.Button.Parent.Size.X.Offset - slot.Name.Position.X.Offset - 6
					for _, text in { slot.Name, slot.Sub } do
						T.truthy(
							TechShopView.fits(text.Text, room, text.Size.Y.Offset, text.TextSize, false),
							`{label}: "{text.Text}" fits its slot`
						)
					end
					if screen.Compact then
						T.truthy(slot.Sub.TextSize >= 13, `{label}: "{slot.Sub.Text}" readable`)
					end
				end
				for _, row in refs.RowList do
					T.truthy(row.Effect.Text ~= "", label .. " " .. row.Id .. ": an effect line")
					T.truthy(
						row.Button.Size.Y.Offset >= row.Line.Position.Y.Offset + row.Line.Size.Y.Offset,
						label .. " three lines in a row"
					)
				end
				-- the buttons: inside the detail, under its scrolling body, none overlapping
				local body = boxIn(refs.Detail.Body, detail)
				local faces = {}
				for _, button in { refs.Detail.Buttons[1], refs.Detail.Buttons[2], refs.Detail.Buttons[3], refs.Detail.Equip } do
					local holder = button.Parent
					if holder.Visible then
						local box = boxIn(holder, detail)
						T.truthy(
							box[1] >= detail[1] and box[1] + box[3] <= detail[1] + detail[3] + 0.5,
							`{label} {id}: {holder.Name} inside`
						)
						T.truthy(box[2] + box[4] <= detail[2] + detail[4], `{label} {id}: {holder.Name} inside (y)`)
						T.truthy(box[2] >= body[2] + body[4], `{label} {id}: {holder.Name} under the body`)
						for _, other in faces do
							T.falsy(overlaps(box, other), `{label} {id}: buttons overlap`)
						end
						table.insert(faces, box)
						T.truthy(
							TechShopView.fits(button.Text, box[3] - 12, box[4] - 8, button.TextSize, false),
							`{label}: "{button.Text}" fits its button`
						)
					end
				end
				local statusBox = boxIn(refs.Detail.Status, detail)
				T.truthy(statusBox[2] >= body[2] + body[4] - 0.5, label .. " status under the body")
				T.truthy(
					TechShopView.fits(refs.Detail.Status.Text, statusBox[3], statusBox[4], refs.Detail.Status.TextSize, false),
					label .. " the status text fits"
				)
				if screen.Compact then
					for _, target in EnchantView.touchTargets(refs) do
						T.truthy(target.Size.Y.Offset * 0.62 >= 44 - 0.5, `{label}: {target.Name} tall enough`)
						if target.Size.X.Scale == 0 then
							T.truthy(target.Size.X.Offset * 0.62 >= 44, `{label}: {target.Name} wide enough`)
						end
					end
				end
				-- the odds table fits its box in the scrolling body (no inner scrolling)
				if odds then
					local t = refs.Detail.Odds
					local rowsShown = 0
					for _, row in t.Rows do
						if row.Frame.Visible then
							rowsShown += 1
						end
					end
					T.eq(rowsShown, #(odds :: any).Rows, label .. " every odds row")
					T.truthy(
						t.List.Size.Y.Offset >= rowsShown * (BoostView.tableMetrics(screen.Compact).Row + 2) - 0.5,
						label .. " all rows in view"
					)
				end
			end
		end
		-- a gamepad: the glyph row shows on every screen (phones / TVs: bigger, in a footer of its own)
		for _, screen in SCREENS do
			local refs = EnchantView.build(screen.Compact)
			EnchantView.layout(refs, screen.Compact, screen.Width, screen.Height)
			EnchantView.setSlots(refs, EnchantView.slotCards(state()), 5, nil)
			EnchantView.setHint(refs, "", { "a", "b", "c" })
			-- the new layout (phones / TVs: a footer of its own) fits the slot texts again
			for _, slot in refs.Slots do
				local room = slot.Button.Parent.Size.X.Offset - slot.Name.Position.X.Offset - 6
				T.truthy(
					TechShopView.fits(slot.Sub.Text, room, slot.Sub.Size.Y.Offset, slot.Sub.TextSize, false),
					`{screen.Label}: "{slot.Sub.Text}" still fits after the gamepad row came`
				)
			end
			local panel = { 0, 0, refs.Panel.Size.X.Offset, refs.Panel.Size.Y.Offset }
			local pad = boxIn(refs.PadHint, panel)
			T.truthy(refs.PadHint.Visible, screen.Label .. " gamepad row")
			T.truthy(pad[2] + pad[4] <= panel[4] and pad[1] >= 0 and pad[1] + pad[3] <= panel[3], screen.Label .. " inside")
			T.falsy(overlaps(boxIn(refs.Detail.Frame, panel), pad), screen.Label .. " under the detail")
			T.falsy(overlaps(boxIn(refs.List, panel), pad), screen.Label .. " under the list")
			EnchantView.setHint(refs, "Tap an enchant", nil)
			T.falsy(refs.PadHint.Visible)
		end
		-- every status text fits the status line on the smallest layout
		local refs = EnchantView.build(true)
		EnchantView.layout(refs, true, SCREENS[5].Width, SCREENS[5].Height)
		for key, text in EnchantView.StatusText do
			EnchantView.setStatus(refs, text, nil)
			T.truthy(
				TechShopView.fits(text, refs.BodyWidth, refs.Detail.Status.Size.Y.Offset, refs.Detail.Status.TextSize, false),
				"status " .. key .. " fits"
			)
		end
		for key, text in Reasons do
			EnchantView.setStatus(refs, text, nil)
			T.truthy(
				TechShopView.fits(text, refs.BodyWidth, refs.Detail.Status.Size.Y.Offset, refs.Detail.Status.TextSize, false),
				"reason " .. key .. " fits"
			)
		end
	end)
end
