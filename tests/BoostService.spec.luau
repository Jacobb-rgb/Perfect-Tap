-- BoostService (luck boosts) and BoostView under Lune: coin top-ups at
-- the price BoostConfig quotes (CoinLimit, Full, NoCoins, NoEffect), Robux
-- packs answered with PurchasePrompt and never granted (Coming soon while
-- the id is 0, Restricted, Full, Prompted when live), the paid-random
-- policy read only when needed, the expiry push, add() capped / uncapped, a
-- fuzz run (one answer per request, coins never below 0, boosts never past
-- the cap), and that the view offers exactly what the server quotes and
-- shows the boosted odds in numbers (Hexa: every ore of a zone, Triple:
-- every golem of a capsule; rarest first), its layouts (phone buttons
-- >= 44 pt, no overlaps, the gamepad row on phones / TVs), the HUD chips
-- (under the train chip and the "+$X" popups) and "Coming soon" for a boost
-- whose package isn't in the game yet. Save data, players and Net are small
-- fakes; EconomyService runs for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local Receipts = Loader.requirePath("ServerScriptService.Server.Receipts")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local BoostService = Loader.requirePath("ServerScriptService.Server.Services.BoostService")
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")

	local NOW = 1_800_000_000
	local boost = BoostService._test

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
		local p: any = { UserId = userId, Name = "B" .. userId, Parent = true, attrs = {} }
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
		local w: any = { notes = {}, changed = 0, pushed = 0, delays = {}, prompts = {}, policyCalls = 0, restricted = false }
		w.player = fakePlayer(601)
		w.data = deepCopy(DataTemplate)
		w.data.BlasterLevel = 5
		w.data.Coins = 0
		w.now = NOW
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
		patch(StateService, "push", function()
			w.pushed += 1
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		Policy._test.reset()
		Policy._test.setFetcher(function()
			w.policyCalls += 1
			return { ArePaidRandomItemsRestricted = w.restricted, IsPaidItemTradingAllowed = false }
		end)
		boost.reset()
		Receipts._test.reset()
		Receipts._test.setPublisher(function(ready)
			w.receiptsPublished = ready
		end)
		boost.setClock(function()
			return w.now
		end)
		boost.setDelay(function(seconds, fn)
			table.insert(w.delays, { Seconds = seconds, Fn = fn })
		end)
		boost.setPrompter(function(p, product)
			table.insert(w.prompts, { Player = p, Product = product })
		end)
		-- every package that reads a boost is in the game (the coming-soon test turns one off)
		boost.setHasService(function()
			return true
		end)
		w.restore = function()
			boost.reset()
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

	-- Sends one BoostAction; returns the one answer it got ({ Name, A }).
	local function act(w: any, action: any, payload: any): any
		local before = #notes(w, "ActionResult") + #notes(w, "PurchasePrompt")
		boost.boostAction(w.player, action, payload)
		local answers = {}
		for _, note in w.notes do
			if note.Name == "ActionResult" or note.Name == "PurchasePrompt" then
				table.insert(answers, note)
			end
		end
		T.eq(#answers, before + 1, "exactly one answer per request")
		return answers[#answers]
	end

	local function result(w: any, action: string, id: any): any
		local answer = act(w, action, { Id = id })
		T.eq(answer.Name, "ActionResult", "an ActionResult")
		T.eq(answer.A.Action, "Boost")
		T.eq(answer.A.Op, action)
		return answer.A
	end

	local function refused(w: any, action: string, id: any, reason: string, label: string)
		local coins = w.data.Coins
		local boosts = deepCopy(w.data.Boosts)
		local r = result(w, action, id)
		T.eq(r.Ok, false, label .. ": refused")
		T.eq(r.Reason, reason, label .. ": reason")
		T.truthy(BoostConfig.Reasons[reason], label .. ": the reason has a text")
		T.eq(w.data.Coins, coins, label .. ": coins kept")
		for key, value in boosts do
			T.eq(w.data.Boosts[key], value, label .. ": boosts kept " .. key)
		end
	end

	---------------------------------------------------------------- coin top-ups

	withWorld("BoostService: a coin top-up pays the quoted price and adds the time", function(w)
		local price = BoostConfig.coinPrice("HexaLucky5", w.data.BlasterLevel)
		T.truthy(price and price > 0, "a price")
		w.data.Coins = price + 7
		local r = result(w, "BuyCoins", "HexaLucky5")
		T.eq(r.Ok, true, "bought")
		T.eq(r.Id, "HexaLucky5")
		T.eq(w.data.Coins, 7, "paid the quoted price")
		T.eq(w.data.Boosts.HexaLuckyUntil, NOW + 300, "5 minutes from now")
		T.truthy(w.changed > 0, "DataService.changed")
		local toast = notes(w, "Notify")
		T.eq(#toast, 1, "one toast")
		T.eq(toast[1].A.Kind, "Reward")
		T.eq(toast[1].A.Text, "Hexa Lucky: +5:00 (5:00 left)")
		-- coins can be bought with Robux (CoinPacksEnabled): a coin boost is a paid random item too
		T.eq(w.policyCalls, if MonetizationConfig.coinsBuyable() then 1 else 0, "the policy is read only while coins can be bought")
		-- a second top-up while less than 10 min is left adds to the end
		w.now = NOW + 100
		w.data.Coins = price
		T.eq(result(w, "BuyCoins", "HexaLucky5").Ok, true, "topped up")
		T.eq(w.data.Boosts.HexaLuckyUntil, NOW + 600, "added to the end")
		-- 500 s left now: still below CoinBuyBelow (600)
		w.data.Coins = price
		T.eq(result(w, "BuyCoins", "HexaLucky5").Ok, true, "topped up again")
		T.eq(w.data.Boosts.HexaLuckyUntil, NOW + 900)
		-- 800 s left: coins only top up below 10 minutes
		w.data.Coins = price
		refused(w, "BuyCoins", "HexaLucky5", "CoinLimit", "coin limit")
		-- the Triple Lucky offer prices 2 Crystal capsules at the blaster level
		local triple = BoostConfig.coinPrice("TripleLucky5", w.data.BlasterLevel)
		T.eq(triple, (CapsuleConfig.price("Crystal", 1, w.data.BlasterLevel) :: number) * 2, "2 Crystal capsules")
		w.data.Coins = triple
		T.eq(result(w, "BuyCoins", "TripleLucky5").Ok, true)
		T.eq(w.data.Boosts.TripleLuckyUntil, NOW + 100 + 300)
		T.eq(w.data.Coins, 0)
	end)

	withWorld("BoostService: coin top-ups are refused with a reason and change nothing", function(w)
		w.data.Coins = 1
		refused(w, "BuyCoins", "HexaLucky5", "NoCoins", "too poor")
		w.data.Coins = 1e15
		refused(w, "BuyCoins", "HexaLucky15", "BadOffer", "a Robux pack via BuyCoins")
		refused(w, "BuyCoins", "Nope", "BadOffer", "unknown offer")
		refused(w, "BuyCoins", 5, "BadOffer", "a number")
		refused(w, "BuyCoins", nil, "BadOffer", "no id")
		refused(w, "BuyCoins", string.rep("x", 200), "BadOffer", "a long id")
		-- Full: a running boost close to its cap (a Robux pack can pass the coin limit's 10 min)
		w.data.Boosts.HexaLuckyUntil = NOW + 300
		local saved = BoostConfig.CoinBuyBelow
		BoostConfig.CoinBuyBelow = BoostConfig.MaxStackSeconds + 1
		w.data.Boosts.HexaLuckyUntil = NOW + BoostConfig.MaxStackSeconds - 100
		local ok, err = pcall(refused, w, "BuyCoins", "HexaLucky5", "Full", "past 2 hours")
		BoostConfig.CoinBuyBelow = saved
		if not ok then
			error(err, 0)
		end
		-- NoEffect: no mine with a Rare+ ore (a test zone list)
		local zones = WorldLayout.Zones
		local plain = {}
		for _, zone in zones do
			local copy = table.clone(zone)
			copy.Ores = if zone.Id == "Outcrops" then zone.Ores else {}
			table.insert(plain, copy)
		end
		WorldLayout.Zones = plain
		-- (the mine floors' rock weights too: BoostConfig.zoneWeights)
		local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
		local byZone = MineFloors.ByZone
		MineFloors.ByZone = {}
		w.data.Boosts.HexaLuckyUntil = 0
		local ok2, err2 = pcall(function()
			refused(w, "BuyCoins", "HexaLucky5", "NoEffect", "no Rare ores anywhere")
			refused(w, "BuyRobux", "HexaLucky15", "NoEffect", "no Robux pack either")
			w.data.Coins = 0
			T.eq(result(w, "BuyCoins", "TripleLucky5").Reason, "NoCoins", "Triple Lucky always has an effect")
		end)
		WorldLayout.Zones = zones
		MineFloors.ByZone = byZone
		if not ok2 then
			error(err2, 0)
		end
		-- no save loaded
		w.loaded = false
		local r = result(w, "BuyCoins", "HexaLucky5")
		T.eq(r.Reason, "BadOffer", "no save: refused")
		-- unknown actions still get their answer
		w.loaded = true
		T.eq(act(w, "Steal", { Id = "HexaLucky5" }).A.Reason, "BadOffer")
		T.eq(act(w, { 1 }, nil).A.Op, "")
		T.eq(act(w, string.rep("A", 40), nil).A.Op, "", "a long action name is not echoed")
	end)

	withWorld("BoostService: with coin packs on, coin boosts are paid random items (Restricted where restricted)", function(w)
		MonetizationConfig.CoinPacksEnabled = true
		w.restricted = true
		w.data.Coins = 1e15
		refused(w, "BuyCoins", "HexaLucky5", "Restricted", "restricted player")
		T.eq(w.policyCalls, 1, "the policy was asked")
		T.eq(w.player.attrs.PaidRandomRestricted, true, "the client can read it")
		-- a player who may buy them
		Policy._test.reset()
		w.restricted = false
		T.eq(result(w, "BuyCoins", "HexaLucky5").Ok, true, "allowed")
	end)

	---------------------------------------------------------------- Robux packs

	withWorld("BoostService: Robux packs are answered with PurchasePrompt and never granted", function(w)
		w.data.Coins = 500
		local function prompt(id: string): string
			local answer = act(w, "BuyRobux", { Id = id })
			T.eq(answer.Name, "PurchasePrompt", id .. ": a PurchasePrompt")
			T.eq(answer.A.Product, BoostConfig.OfferById[id].Product)
			return answer.A.Status
		end
		-- placeholders: Coming soon, nothing prompted, nothing granted
		for _, offer in BoostConfig.RobuxOffers do
			T.eq(prompt(offer.Id), "ComingSoon", offer.Id)
		end
		T.eq(#w.prompts, 0, "no MarketplaceService prompt")
		T.eq(w.data.Boosts.HexaLuckyUntil, 0, "never granted")
		T.eq(w.data.Boosts.TripleLuckyUntil, 0)
		T.eq(w.data.Coins, 500, "no coins taken")
		T.eq(w.changed, 0, "no save change")
		-- a live product id but no receipt handler yet (step 8): Coming soon, never prompted
		MonetizationConfig.Products.HexaLucky15.Id = 4242
		T.eq(Receipts.ready(), false, "no receipt handler before step 8")
		T.eq(prompt("HexaLucky15"), "ComingSoon", "live id, receipts not ready")
		T.eq(#w.prompts, 0, "nobody pays Robux for nothing")
		-- step 8 turns the gate on: the prompt is shown
		Receipts.setReady(true)
		T.eq(w.receiptsPublished, true, "the clients learn it (ReplicatedStorage attribute)")
		T.eq(prompt("HexaLucky15"), "Prompted")
		T.eq(#w.prompts, 1, "prompted once")
		T.eq(w.prompts[1].Product.Id, 4242, "with the id from MonetizationConfig")
		T.eq(w.data.Boosts.HexaLuckyUntil, 0, "still not granted (step 8 does that)")
		-- restricted players: Restricted, no prompt
		Policy._test.reset()
		w.restricted = true
		T.eq(prompt("HexaLucky15"), "Restricted")
		T.eq(#w.prompts, 1, "no new prompt")
		-- a pack that would pass the cap: Full
		Policy._test.reset()
		w.restricted = false
		w.data.Boosts.HexaLuckyUntil = NOW + BoostConfig.MaxStackSeconds - 60
		T.eq(prompt("HexaLucky15"), "Full")
		T.eq(#w.prompts, 1)
		-- a prompt that fails is answered too
		boost.setPrompter(function()
			error("MarketplaceService down")
		end)
		w.data.Boosts.HexaLuckyUntil = 0
		T.eq(prompt("HexaLucky15"), "Unknown", "a failed prompt")
		-- bad ids
		T.eq(act(w, "BuyRobux", { Id = "HexaLucky5" }).A.Reason, "BadOffer", "a coin offer via BuyRobux")
		T.eq(act(w, "BuyRobux", { Id = "x" }).A.Reason, "BadOffer")
		T.eq(act(w, "BuyRobux", "HexaLucky15").A.Reason, "BadOffer", "a bare string")
	end)

	withWorld("BoostService: promptPurchase is the one prompt path (owned, full, coin packs off)", function(w)
		T.eq(BoostService.promptPurchase(w.player, "EnchantHeartfire", false, false), "ComingSoon")
		T.eq(w.policyCalls, 0, "not a paid random item: no policy call")
		T.eq(BoostService.promptPurchase(w.player, "EnchantStarbreaker", false, false), "ComingSoon")
		T.eq(w.policyCalls, 1, "Starbreaker's pass changes odds: policy asked")
		MonetizationConfig.Products.EnchantHeartfire.Id = 77
		-- a live pass before step 8 grants passes: Coming soon
		T.eq(BoostService.promptPurchase(w.player, "EnchantHeartfire", false, false), "ComingSoon", "no pass grant yet")
		T.eq(#w.prompts, 0, "not prompted")
		Receipts.setReady(true)
		T.eq(BoostService.promptPurchase(w.player, "EnchantHeartfire", true, false), "Owned")
		T.eq(BoostService.promptPurchase(w.player, "EnchantHeartfire", false, false), "Prompted")
		T.eq(w.prompts[1].Product.Kind, "GamePass", "a game pass")
		T.eq(BoostService.promptPurchase(w.player, "CoinsSmall", false, false), "Unknown", "coin packs are off")
		T.eq(BoostService.promptPurchase(w.player, "Nope", false, false), "Unknown")
		local sent = notes(w, "PurchasePrompt")
		T.eq(#sent, 7, "every call answered the client")
		-- a player who left gets no event
		w.player.Parent = nil
		BoostService.promptPurchase(w.player, "EnchantHeartfire", false, false)
		T.eq(#notes(w, "PurchasePrompt"), 7)
	end)

	---------------------------------------------------------------- expiry and add

	withWorld("BoostService: a boost that runs out pushes State and says so", function(w)
		w.data.Boosts.TripleLuckyUntil = NOW + 300
		w.data.Boosts.HexaLuckyUntil = NOW + 120
		BoostService.plan(w.player)
		T.eq(boost.planned(w.player), NOW + 120, "the soonest expiry")
		T.eq(#w.delays, 1, "one timer")
		T.truthy(w.delays[1].Seconds >= 120 and w.delays[1].Seconds <= 121, "just after it ends")
		-- planning again for the same expiry adds no timer
		BoostService.plan(w.player)
		T.eq(#w.delays, 1, "no second timer")
		w.now = NOW + 121
		w.delays[1].Fn()
		T.eq(w.pushed, 1, "State pushed")
		local toast = notes(w, "Notify")
		T.eq(toast[#toast].A.Text, "Hexa Lucky ran out.")
		T.eq(boost.planned(w.player), NOW + 300, "the next one is planned")
		-- a top-up moves the end: the old timer does nothing
		w.data.Boosts.TripleLuckyUntil = NOW + 900
		BoostService.plan(w.player)
		local stale = w.delays[2]
		local fresh = w.delays[3]
		T.truthy(stale and fresh, "a new timer")
		stale.Fn()
		T.eq(w.pushed, 1, "the stale timer does nothing")
		w.now = NOW + 901
		fresh.Fn()
		T.eq(w.pushed, 2)
		T.eq(boost.planned(w.player), nil, "nothing more to plan")
		-- both ending together: one toast with both names
		w.data.Boosts.TripleLuckyUntil = w.now + 50
		w.data.Boosts.HexaLuckyUntil = w.now + 50
		BoostService.plan(w.player)
		w.now += 51
		w.delays[#w.delays].Fn()
		toast = notes(w, "Notify")
		T.eq(toast[#toast].A.Text, "Triple Lucky and Hexa Lucky ran out.")
		-- a player who left: nothing
		w.data.Boosts.HexaLuckyUntil = w.now + 10
		BoostService.plan(w.player)
		w.player.Parent = nil
		w.now += 11
		local pushed = w.pushed
		w.delays[#w.delays].Fn()
		T.eq(w.pushed, pushed, "no push for a player who left")
		-- a save change after leaving (a beforeRelease callback) plans nothing and keeps no timer
		local timers = #w.delays
		w.data.Boosts.HexaLuckyUntil = w.now + 3600
		BoostService.plan(w.player)
		T.eq(boost.planned(w.player), nil, "nothing planned for a player who left")
		T.eq(#w.delays, timers, "no timer kept")
	end)

	---------------------------------------------------------------- coming soon

	withWorld("BoostService: a boost nothing reads yet is coming soon (shown, refused, nothing taken)", function(w)
		boost.setHasService(function(name: string): boolean
			return name ~= "CapsuleService"
		end)
		T.eq(BoostService.comingSoon("TripleLucky"), true, "no capsules: Triple Lucky has no effect yet")
		T.eq(BoostService.comingSoon("HexaLucky"), false, "mining reads Hexa Lucky")
		T.eq(BoostService.comingSoon(nil), false)
		T.eq(table.concat(BoostService.soonIds(), ","), "TripleLucky")
		for id, service in BoostService.Consumers do
			T.truthy(
				BoostConfig.Kinds[id] or Loader.requirePath("ReplicatedStorage.Shared.Config.EnchantConfig").ById[id],
				id .. " is a boost or an enchant"
			)
			T.truthy(service:match("Service$"), id .. ": a service module name")
		end
		w.data.Coins = 1e12
		local before = deepCopy(w.data.Boosts)
		local r = result(w, "BuyCoins", "TripleLucky5")
		T.eq(r.Ok, false)
		T.eq(r.Reason, "ComingSoon", "coins: coming soon")
		MonetizationConfig.Products.TripleLucky15.Id = 99
		local r2 = result(w, "BuyRobux", "TripleLucky15")
		T.eq(r2.Reason, "ComingSoon", "Robux: coming soon even with a live id")
		T.eq(#w.prompts, 0, "no prompt")
		T.eq(w.data.Coins, 1e12, "no coins taken")
		for key, value in before do
			T.eq(w.data.Boosts[key], value, "no time added " .. key)
		end
		T.eq(result(w, "BuyCoins", "HexaLucky5").Ok, true, "Hexa Lucky still sells")
		-- rewards and receipts are never held back
		T.truthy(BoostService.add(w.player, "TripleLucky", 60, true), "add() still works")
		-- the view: the attribute's ids, every Triple offer greyed with the reason
		local soon = BoostView.soonSet("TripleLucky, Prospector")
		T.truthy(soon.TripleLucky and soon.Prospector, "parsed")
		T.eq(next(BoostView.soonSet(nil)), nil, "no attribute: nothing")
		T.eq(next(BoostView.soonSet("")), nil)
		local cards = BoostView.cards({ BlasterLevel = 5, Boosts = {}, Bonuses = {} }, 1e12, NOW, false, soon)
		T.eq(cards[1].Kind, "TripleLucky")
		T.truthy(#cards[1].Offers > 0, "the offers stay in view")
		for _, offer in cards[1].Offers do
			T.falsy(offer.CanBuy, offer.Id)
			T.eq(offer.Reason, "ComingSoon")
			T.truthy(offer.Text:find("COMING SOON"), offer.Id .. ": says so")
		end
		T.eq(cards[1].KeyLine, BoostView.SoonText.TripleLucky)
		T.eq(BoostView.reasonText("ComingSoon"), MonetizationConfig.StatusText.ComingSoon)
		for _, offer in cards[2].Offers do
			T.falsy(offer.Reason == "ComingSoon" and not offer.Robux, "Hexa Lucky's coin offer sells")
		end
	end)

	withWorld("BoostService: add() caps coin / wheel time and never loses paid time", function(w)
		T.eq(BoostService.add(w.player, "HexaLucky", 600, true), NOW + 600)
		T.eq(BoostService.add(w.player, "HexaLucky", 3 * 3600, true), NOW + BoostConfig.MaxStackSeconds, "capped at 2 h")
		T.eq(BoostService.add(w.player, "HexaLucky", 3600, false), NOW + BoostConfig.MaxStackSeconds + 3600, "a receipt is never cut")
		T.eq(BoostService.add(w.player, "Nope", 60, true), nil, "unknown kind")
		T.truthy(w.changed >= 3, "every add saves")
		w.data.Boosts = "junk"
		T.eq(BoostService.add(w.player, "TripleLucky", 60, true), NOW + 60, "a broken record is rebuilt")
		w.loaded = false
		T.eq(BoostService.add(w.player, "TripleLucky", 60, true), nil, "no save")
	end)

	---------------------------------------------------------------- fuzz

	withWorld("BoostService: fuzz (junk requests, time passing): one answer each, nothing lost or duplicated", function(w)
		local rng = Rng.new(4242)
		local ids = { "HexaLucky5", "TripleLucky5", "HexaLucky15", "TripleLucky60", "Nope", "", 7, nil :: any }
		local actions = { "BuyCoins", "BuyRobux", "BuyCoins", "Junk" }
		local spent = 0
		for _ = 1, 400 do
			w.now += rng:int(0, 200)
			w.data.Coins = rng:int(0, 3) * 1e6
			local action = actions[rng:int(1, #actions)]
			local id = ids[rng:int(1, #ids)]
			local before = w.data.Coins
			local untilBefore = {
				Hexa = BoostConfig.untilOf(w.data.Boosts, "HexaLucky"),
				Triple = BoostConfig.untilOf(w.data.Boosts, "TripleLucky"),
			}
			local payload = if rng:int(1, 6) == 1 then id else { Id = id }
			local answer = act(w, action, payload)
			local paid = before - w.data.Coins
			T.truthy(w.data.Coins >= 0, "coins never below 0")
			if answer.Name == "ActionResult" and answer.A.Ok then
				local offer = BoostConfig.OfferById[id]
				T.eq(paid, BoostConfig.coinPrice(id, w.data.BlasterLevel), "paid exactly the quoted price")
				local key = if offer.Boost == "HexaLucky" then "Hexa" else "Triple"
				local after = BoostConfig.untilOf(w.data.Boosts, offer.Boost)
				T.eq(after, math.max(w.now, untilBefore[key]) + offer.Seconds, "exactly the offer's time")
				T.truthy(after - w.now <= BoostConfig.MaxStackSeconds, "never past the cap")
				spent += paid
			else
				T.eq(paid, 0, "nothing paid without a successful buy")
				T.eq(BoostConfig.untilOf(w.data.Boosts, "HexaLucky"), untilBefore.Hexa, "no time without a buy")
				T.eq(BoostConfig.untilOf(w.data.Boosts, "TripleLucky"), untilBefore.Triple)
			end
		end
		T.truthy(spent > 0, "some buys went through")
		T.eq(#w.prompts, 0, "placeholders never prompt")
	end)

	---------------------------------------------------------------- the view

	local function state(over: { [string]: any }?): { [string]: any }
		local s: { [string]: any } = {
			Coins = 2e6,
			BlasterLevel = 5,
			Boosts = { TripleLuckyUntil = 0, HexaLuckyUntil = 0 },
			Bonuses = { OreLuckPct = 0.15, OreLuckMult = 1, ArtifactPct = 0 },
			Perks = { ForgeVip = false },
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	T.test("BoostView: percents and times", function()
		T.eq(BoostView.pct(0.6123), "61.2%")
		T.eq(BoostView.pct(0.037), "3.7%")
		T.eq(BoostView.pct(0.0059), "0.59%")
		T.eq(BoostView.pct(0.00015), "0.015%")
		T.eq(BoostView.pct(0), "0%")
		T.eq(BoostView.pct(1), "100%")
		T.eq(BoostView.pct(0.99999), "99.9%", "never rounds up to 100% when it isn't")
		T.eq(BoostView.pct(1e-9), "<0.0001%", "tiny but not 0")
		T.eq(BoostView.pct(0 / 0), "0%")
		T.eq(BoostView.mult(2.5), "x2.5")
		T.eq(BoostView.mult(1), "x1")
		T.eq(BoostView.duration(300), "5 MIN")
		T.eq(BoostView.duration(900), "15 MIN")
		T.eq(BoostView.duration(3600), "1 HOUR")
		T.eq(BoostView.duration(7200), "2 HOURS")
		T.eq(BoostView.timer(299.2), "5:00", "rounds up: never shows 0:00 while running")
		T.eq(BoostView.timer(3900), "1h 05m")
		T.truthy(BoostView.restricted(nil), "unknown policy = restricted")
		T.truthy(BoostView.restricted(true))
		T.falsy(BoostView.restricted(false))
	end)

	T.test("BoostView: the cards offer exactly what the server quotes", function()
		for _, level in { 1, 3, 5, 8, 10 } do
			for _, left in { 0, 200, 700, BoostConfig.MaxStackSeconds - 100 } do
				for _, cash in { 0, 5e4, 1e12 } do
					local s = state({ BlasterLevel = level, Boosts = { TripleLuckyUntil = NOW + left, HexaLuckyUntil = NOW + left } })
					for _, card in BoostView.cards(s, cash, NOW, false) do
						T.eq(card.Remaining, left)
						T.eq(card.Active, left > 0)
						for _, offer in card.Offers do
							if offer.Robux then
								T.eq(
									offer.Reason,
									if offer.Kind == "HexaLucky" and not BoostConfig.hasEffect("HexaLucky", level)
										then "NoEffect" -- (floors 1's rocks: no Rare+ ores to luck into)
										elseif BoostConfig.canExtend(s.Boosts, offer.Kind, offer.Seconds, NOW) then "ComingSoon"
										else "Full",
									"Robux packs: Coming soon while the id is 0"
								)
								T.falsy(offer.CanBuy, "never buyable while the id is 0")
							else
								local price, reason = BoostConfig.coinQuote(s.Boosts, offer.Id, level, false, NOW)
								T.eq(offer.Price, BoostConfig.coinPrice(offer.Id, level), "the card's price")
								if reason then
									T.eq(offer.Reason, reason, "the same refusal")
								elseif cash < (price :: number) then
									T.eq(offer.Reason, "NoCoins")
								else
									T.truthy(offer.CanBuy, "buyable")
								end
							end
						end
					end
				end
			end
		end
		-- restricted players see no Robux packs (coin top-ups stay while coins can't be bought)
		MonetizationConfig.CoinPacksEnabled = false
		for _, card in BoostView.cards(state(), 1e9, NOW, true) do
			for _, offer in card.Offers do
				T.falsy(offer.Robux, "no Robux pack where restricted")
			end
			T.eq(#card.Offers, 1, "the coin top-up stays")
		end
		MonetizationConfig.CoinPacksEnabled = true
		for _, card in BoostView.cards(state(), 1e9, NOW, true) do
			T.eq(#card.Offers, 0, "coin packs on: coin boosts are paid random items too")
		end
		MonetizationConfig.CoinPacksEnabled = false
		-- a live product: its price in R$
		MonetizationConfig.Products.TripleLucky15.Id = 99
		local card = BoostView.cards(state(), 0, NOW, false)[1]
		MonetizationConfig.Products.TripleLucky15.Id = 0
		T.eq(card.Offers[2].Text, `+15 MIN{BoostView.Separator}39 R$`)
		T.truthy(card.Offers[2].CanBuy)
		-- ...but only once step 8's receipts gate is on (the controllers pass soonNow)
		MonetizationConfig.Products.TripleLucky15.Id = 99
		local waiting = BoostView.cards(state(), 0, NOW, false, BoostView.soonNow(nil, nil))[1]
		local ready = BoostView.cards(state(), 0, NOW, false, BoostView.soonNow(nil, true))[1]
		MonetizationConfig.Products.TripleLucky15.Id = 0
		T.eq(waiting.Offers[2].Text, `+15 MIN{BoostView.Separator}COMING SOON`, "live id, no receipt handler yet")
		T.falsy(waiting.Offers[2].CanBuy)
		T.eq(waiting.Offers[2].Reason, "ComingSoon")
		T.truthy(waiting.Offers[1].CanBuy == card.Offers[1].CanBuy, "the coin offer doesn't wait for receipts")
		T.eq(ready.Offers[2].Text, `+15 MIN{BoostView.Separator}39 R$`, "receipts ready: sold")
		T.truthy(ready.Offers[2].CanBuy)
		-- Hexa Lucky's key line: the luck without and with it
		local hexa = BoostView.cards(state(), 0, NOW, false)[2]
		local without, with = BoostConfig.hexaLuck(0.15)
		T.eq(hexa.KeyLine, `Your ore luck: {BoostView.mult(without)} → {BoostView.mult(with)}`)
	end)

	T.test("BoostView: the boosted odds are the real ones (every ore, every golem, sums of 100%)", function()
		local s = state({ Bonuses = { OreLuckPct = 0.3, OreLuckMult = 1, ArtifactPct = 0 } })
		local without, with = BoostConfig.hexaLuck(0.3)
		for _, zone in WorldLayout.Zones do
			local weights = BoostConfig.zoneWeights(zone)
			local crystal = BoostConfig.crystalWeights(zone)
			if next(weights) ~= nil then
				local t = BoostView.hexaOdds(s, zone.Id)
				local before = BoostConfig.oreOdds(weights, without)
				local after = BoostConfig.oreOdds(weights, with)
				local crystalRows = if crystal then #BoostConfig.oreOdds(crystal, without) else 0
				local secretRows = #BoostView.secretRows(zone.Id, without, with)
				T.eq(#t.Rows, #before + crystalRows + secretRows, zone.Id .. ": every ore (and every crystal rock ore, the secrets)")
				-- the SECRET ores first (the rarest): ??? names, "1 in N" chances (SecretOreConfig)
				for i = 1, secretRows do
					T.eq(t.Rows[i].Name:sub(1, 10), "??? Secret", zone.Id .. ": the secret's name stays hidden")
					T.truthy(t.Rows[i].Before:find("1 in ", 1, true), zone.Id .. ": its chance is shown")
				end
				for i = secretRows + #before + 1, #t.Rows do
					T.truthy(t.Rows[i].Name:find("(crystal rock)", 1, true), zone.Id .. ": crystal rock rows last")
				end
				t = table.clone(t)
				t.Rows = table.move(t.Rows, secretRows + 1, secretRows + #before, 1, {})
				local byName = {}
				local order = math.huge
				for _, row in t.Rows do
					byName[row.Name] = row
				end
				for _, line in before do
					local ore = OreData.ById[line.Ore]
					byName[ore.Name].Order = Rarity.get(ore.Rarity).Order
				end
				for _, row in t.Rows do
					T.truthy(row.Order <= order, zone.Id .. ": rarest first")
					order = row.Order
				end
				for i, line in before do
					local row = byName[OreData.ById[line.Ore].Name]
					T.truthy(row, zone.Id .. " " .. line.Ore .. " has a row")
					T.eq(row.Before, BoostView.pct(line.Chance), zone.Id .. " " .. line.Ore .. " before")
					T.eq(after[i].Ore, line.Ore)
					T.eq(row.After, BoostView.pct(after[i].Chance), zone.Id .. " " .. line.Ore .. " after")
				end
				local rare = BoostConfig.rareShare(weights, without)
				if rare > 0 then
					T.eq(t.Summary.Before, BoostView.pct(rare))
					T.eq(t.Summary.After, BoostView.pct(BoostConfig.rareShare(weights, with)))
					if rare < 1 - 1e-9 then
						T.truthy(t.Summary.Change > 0, zone.Id .. ": Rare+ grows")
					else
						T.eq(t.Summary.Change, 0, zone.Id .. ": every ore already Rare+")
					end
				elseif crystal and BoostConfig.rareShare(crystal, without) > 0 then
					T.eq(t.Summary, nil, zone.Id .. ": no Rare ores in plain rocks, no summary")
				else
					T.eq(t.Summary, nil, zone.Id .. ": no Rare ores, no summary")
					T.truthy(t.Note:find("changes nothing"), zone.Id .. ": says so")
				end
			end
		end
		T.eq(#BoostView.hexaOdds(s, "Nope").Rows, 0, "unknown zone")
		for _, capsule in CapsuleConfig.List do
			local t = BoostView.tripleOdds(capsule.Id)
			local before = CapsuleConfig.odds(capsule.Id, false)
			local after = CapsuleConfig.odds(capsule.Id, true)
			T.eq(#t.Rows, #before, capsule.Id .. ": every golem")
			local byName = {}
			for _, row in t.Rows do
				byName[row.Name] = row
			end
			local orders = {}
			for _, line in before do
				local golem = GolemConfig.ById[line.Golem]
				orders[golem.Name] = Rarity.get(golem.Rarity).Order
			end
			for i = 2, #t.Rows do
				T.truthy(orders[t.Rows[i].Name] <= orders[t.Rows[i - 1].Name], capsule.Id .. ": rarest first")
			end
			T.truthy(t.Rows[1].Change > 0, capsule.Id .. ": the top row is one Triple Lucky raises")
			local sumBefore, sumAfter = 0, 0
			for i, line in before do
				local row = byName[GolemConfig.ById[line.Golem].Name]
				T.eq(after[i].Golem, line.Golem)
				T.eq(row.Before, BoostView.pct(line.Chance))
				T.eq(row.After, BoostView.pct(after[i].Chance))
				sumBefore += line.Chance
				sumAfter += after[i].Chance
			end
			T.near(sumBefore, 1, 1e-9)
			T.near(sumAfter, 1, 1e-9)
			T.truthy(t.Summary.Change > 0, capsule.Id .. ": the lucky golems grow")
		end
		-- the capsules shown: the Royal one (Robux) is hidden where restricted; a
		-- limited edition's capsule only while it is on sale
		local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
		local during = LimitedGolems.Current.EndsAt - 3600
		T.eq(#BoostView.capsules(false, during), #CapsuleConfig.List)
		T.truthy(table.find(BoostView.capsules(false, during), "Dragonforge"), "the limited capsule while it runs")
		T.eq(#BoostView.capsules(false, LimitedGolems.Current.EndsAt + 1), #CapsuleConfig.List - 1, "not after its end")
		T.falsy(table.find(BoostView.capsules(true, during), "Royal"), "no Royal where restricted")
		T.falsy(table.find(BoostView.capsules(true, during), "Dragonforge"), "no limited capsule where restricted")
		-- the zone a table starts on
		T.eq(BoostView.defaultZone(s, "Quarry"), "Quarry", "where you stand")
		T.eq(BoostView.defaultZone(s, "Emberfall"), "DeepHollow", "in town: the hardest zone you can mine")
		T.truthy(BoostView.defaultZone(state({ BlasterLevel = 1 }), nil), "level 1: a zone (none has Rare+ ores yet)")
		T.eq(BoostView.cycle({ "A", "B", "C" }, "C", 1), "A", "wraps")
		T.eq(BoostView.cycle({ "A", "B", "C" }, "A", -1), "C")
		T.eq(BoostView.cycle({}, "A", 1), nil)
		-- Hexa Lucky's part of the luck only counts while it runs
		local running = state({ Bonuses = { OreLuckPct = 0, OreLuckMult = 2.5 }, Boosts = { HexaLuckyUntil = NOW + 5 } })
		T.eq(BoostView.context(running, NOW).OreLuckMult, 2.5)
		T.eq(BoostView.context(running, NOW + 6).OreLuckMult, 1, "ran out on the client's clock")
		T.truthy(StatConfig.oreLuck(0, 2.5) == 2.5)
	end)

	T.test("BoostView: the HUD chips show the running boosts", function()
		local s = state({ Boosts = { TripleLuckyUntil = NOW + 299, HexaLuckyUntil = NOW + 3900 } })
		local chips = BoostView.chips(s, NOW)
		T.eq(#chips, 2)
		T.eq(chips[1].Kind, "TripleLucky")
		T.eq(chips[1].Text, "4:59")
		T.eq(chips[1].Mult, "x3")
		T.eq(chips[2].Text, "1h 05m")
		T.eq(#BoostView.chips(s, NOW + 4000), 0, "none after they end")
		local refs = BoostView.buildChips()
		BoostView.setChips(refs, chips, true)
		T.truthy(refs.Chips.TripleLucky.Visible and refs.Chips.HexaLucky.Visible, "both shown")
		T.falsy(refs.Launcher.Visible, "no launcher while one runs")
		BoostView.setChips(refs, {}, true)
		T.falsy(refs.Chips.TripleLucky.Visible)
		T.truthy(refs.Launcher.Visible, "the BOOSTS launcher when none runs")
		BoostView.setChips(refs, {}, false)
		T.falsy(refs.Launcher.Visible, "the side menu can turn it off")
		-- the touch area is 72 units (44 pt on a phone)
		T.eq(refs.Launcher.Size.Y.Offset, BoostView.ChipHit)
		T.truthy(BoostView.ChipHit * 0.62 >= 44, "44 pt")
		T.eq(refs.Gui:GetAttribute("TerraForge"), true, "scaled with the HUD")
		-- in the left column under the train chip (PC and phone sizes), which sits
		-- under the coins (16..90) and their "+$X" popups (96..156)
		for _, compact in { false, true } do
			local train = TrainView.build(compact)
			TrainView.layout(train, compact, 1600, 800)
			local chip = train.ChipFrame
			local bottom = chip.Position.Y.Offset + chip.Size.Y.Offset
			T.eq(chip.Size.Y.Offset, BoostView.TrainChipHeight[if compact then "Compact" else "Normal"], "TrainView's chip height")
			local top = BoostView.chipsTop(chip, compact)
			T.eq(top, BoostView.chipsTop(nil, compact), "the fallback is where TrainView puts it")
			T.truthy(top >= bottom + BoostView.ChipGap, "under the train chip")
			T.truthy(top >= BoostView.FloatersBottom, "under the +$X popups")
			T.truthy(BoostView.ChipLeft == TrainView.ChipLeft, "lined up with the train chip")
		end
		BoostView.placeChips(refs, 240)
		T.eq(refs.Row.Position.Y.Offset, 240)
		-- the pill sits at the top of its touch area: the touch area only reaches down
		local pill = refs.Launcher:FindFirstChild("Pill") :: any
		T.eq(pill.Position.Y.Scale, 0)
		T.eq(pill.Position.Y.Offset, 0)
		T.eq(pill.AnchorPoint.Y, 0)
	end)

	T.test("BoostView: chips tell the boosts apart by picture and word, not colour alone", function()
		local s = state({ Boosts = { TripleLuckyUntil = NOW + 222, HexaLuckyUntil = NOW + 3900 } })
		local chips = BoostView.chips(s, NOW)
		T.eq(chips[1].Tag, "TRIPLE")
		T.eq(chips[2].Tag, "HEXA")
		local refs = BoostView.buildChips()
		BoostView.setChips(refs, chips, true)
		local widths = {}
		for _, kindId in BoostConfig.KindIds do
			local button = refs.Chips[kindId]
			local pill = button:FindFirstChild("Pill") :: any
			local dot = pill:FindFirstChild("Dot") :: any
			local art = dot:FindFirstChild("Art") :: any
			T.truthy(art ~= nil, kindId .. ": its picture in the chip")
			T.eq(art:FindFirstChild("Badge"), nil, kindId .. ": no unreadable badge in the chip")
			local text = pill:FindFirstChild("Text") :: any
			local chip = if kindId == "TripleLucky" then chips[1] else chips[2]
			T.eq(text.Text, `{BoostView.ChipTags[kindId]} {chip.Text}`, kindId .. ": the tag before the timer")
			-- the text fits its label, the label sits inside the pill after the picture, the touch area matches
			T.truthy(TechShopView.fits(text.Text, text.Size.X.Offset, text.Size.Y.Offset, text.TextSize, false), kindId .. ": fits")
			T.truthy(text.Position.X.Offset >= dot.Position.X.Offset + dot.Size.X.Offset, kindId .. ": after the picture")
			T.truthy(text.Position.X.Offset + text.Size.X.Offset <= pill.Size.X.Offset, kindId .. ": inside the pill")
			T.eq(button.Size.X.Offset, pill.Size.X.Offset)
			T.eq(button.Size.Y.Offset, BoostView.ChipHit)
			widths[kindId] = pill.Size.X.Offset
		end
		T.eq((refs.Chips.HexaLucky:FindFirstChild("Pill") :: any):FindFirstChild("Text").Text, "HEXA 1h 05m")
		-- the row holds both chips and the gamepad glyph
		T.truthy(widths.TripleLucky + widths.HexaLucky + 8 + 8 + 30 <= refs.Row.Size.X.Offset, "both chips fit the row")
		-- the launcher: "+" and BOOSTS, no tag
		local launcherPill = refs.Launcher:FindFirstChild("Pill") :: any
		T.eq(launcherPill:FindFirstChild("Text").Text, "BOOSTS")
	end)

	T.test("BoostView: opens on a boost that can be bought; a gamepad starts on the tab", function()
		local s = state()
		-- this build: Triple Lucky is coming soon (no capsules yet) -> Hexa Lucky
		local soon = BoostView.soonSet("TripleLucky,Prospector")
		T.eq(BoostView.openTab("TripleLucky", s, soon), "HexaLucky", "nothing to buy on Triple: Hexa")
		T.eq(BoostView.openTab("HexaLucky", s, soon), "HexaLucky")
		T.eq(BoostView.openTab("TripleLucky", s, {}), "TripleLucky", "the last tab while it can be bought")
		T.eq(BoostView.openTab("HexaLucky", s, nil), "HexaLucky")
		-- Hexa Lucky without an effect (no Rare ore in reach) isn't usable either
		local noEffect = false
		for level = 1, 10 do
			if not BoostConfig.hasEffect("HexaLucky", level, false) then
				noEffect = true
				local low = state({ BlasterLevel = level })
				T.eq(BoostView.openTab("HexaLucky", low, {}), "TripleLucky", `level {level}: Hexa does nothing yet`)
				T.eq(BoostView.openTab("TripleLucky", low, soon), "TripleLucky", "nothing usable: the last tab stays")
			end
		end
		T.truthy(noEffect or BoostConfig.hasEffect("HexaLucky", 1, false), "checked")
		-- the gamepad selection: the open tab, never an offer (A is also jump)
		for _, compact in { false, true } do
			local refs = BoostView.build(compact)
			BoostView.layout(refs, compact, 1280, 684)
			for _, kindId in BoostConfig.KindIds do
				BoostView.setTab(refs, kindId)
				local cards = BoostView.cards(s, 1e12, NOW, false)
				BoostView.setCard(refs, if kindId == "TripleLucky" then cards[1] else cards[2])
				local first = BoostView.firstButton(refs)
				T.eq(first, refs.Tabs[kindId], kindId .. ": starts on its tab")
				for _, button in refs.Card.Offers do
					T.truthy(first ~= button, "never on an offer")
				end
			end
		end
	end)

	-- the screens the layouts must fit (design units: the screen / the HUD scale)
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

	T.test("BoostView: layouts fit, phone buttons are at least 44 pt, nothing overlaps", function()
		for _, screen in SCREENS do
			local label = screen.Label
			for _, kindId in BoostConfig.KindIds do
				local refs = BoostView.build(screen.Compact)
				BoostView.layout(refs, screen.Compact, screen.Width, screen.Height)
				BoostView.setTab(refs, kindId)
				local cards = BoostView.cards(state(), 1e6, NOW, false)
				local card = if kindId == "TripleLucky" then cards[1] else cards[2]
				BoostView.setCard(refs, card)
				BoostView.setTable(refs.Odds, BoostView.hexaOdds(state(), "DeepHollow"), true)
				local panel = { 0, 0, refs.Panel.Size.X.Offset, refs.Panel.Size.Y.Offset }
				T.truthy(panel[3] <= math.max(640, screen.Width - 24), label .. " width fits")
				T.truthy(panel[4] <= math.max(BoostView.MinHeight, screen.Height - 16), label .. " height fits")
				local cardBox = boxIn(refs.Card.Frame, panel)
				local oddsBox = boxIn(refs.Odds.Frame, panel)
				T.falsy(overlaps(cardBox, oddsBox), label .. " card and odds side by side")
				T.truthy(oddsBox[1] + oddsBox[3] <= panel[3], label .. " odds inside the panel")
				T.truthy(cardBox[2] + cardBox[4] <= panel[4], label .. " card inside the panel")
				-- the offers sit inside the card, none overlapping, above the card's bottom
				local faces = {}
				for _, button in refs.Card.Offers do
					local holder = button.Parent
					if holder.Visible then
						local box = boxIn(holder, cardBox)
						T.truthy(box[2] + box[4] <= cardBox[2] + cardBox[4] + 0.5, `{label} {kindId}: offer inside the card`)
						T.truthy(box[1] + box[3] <= cardBox[1] + cardBox[3] + 0.5, `{label} {kindId}: offer inside the card (x)`)
						for _, other in faces do
							T.falsy(overlaps(box, other), `{label} {kindId}: offers overlap`)
						end
						table.insert(faces, box)
						if screen.Compact then
							T.truthy(box[4] * 0.62 >= 44 - 0.5 and box[3] * 0.62 >= 44, `{label}: offer 44 pt`)
						end
						-- the text fits its face (shrunk when needed)
						local wrapped = button.TextWrapped
						T.truthy(
							TechShopView.fits(button.Text, box[3] - 10, box[4] - 6, button.TextSize, wrapped),
							`{label}: "{button.Text}" fits its button`
						)
					end
				end
				T.truthy(#faces >= 1, label .. " offers shown")
				-- the key line and the note keep their room
				local key = boxIn(refs.Card.KeyLine, cardBox)
				T.truthy(key[2] + key[4] <= faces[1][2] + 0.5, label .. " key line above the offers")
				if screen.Compact then
					for _, target in BoostView.touchTargets(refs) do
						T.truthy(target.Size.Y.Offset * 0.62 >= 44 - 0.5, `{label}: {target.Name} tall enough`)
					end
				end
				-- the description stays (a short card next to the icon on a small phone) and fits its box
				local desc = refs.Card.Description
				T.truthy(desc.Visible, label .. " the description stays")
				local short = refs.Card.Frame:GetAttribute("Short") == true
				T.eq(desc.Text, if short then card.Short else card.Description)
				T.eq(refs.Card.Name.Visible, not short, label .. " the name only on a card that isn't short (the tab shows it)")
				local descBox = boxIn(desc, cardBox)
				T.truthy(
					TechShopView.fits(desc.Text, descBox[3], descBox[4], desc.TextSize, true),
					`{label} {kindId}: the description fits`
				)
				T.truthy(descBox[2] + descBox[4] <= key[2] + 0.5, label .. " description above the key line")
				if short then
					local icon = boxIn(refs.Card.Icon, cardBox)
					T.falsy(overlaps(descBox, icon), label .. " short description beside the icon")
					T.falsy(overlaps(descBox, boxIn(refs.Card.Status, cardBox)), label .. " under the status")
				end
				-- the odds list shows whole rows only (no half-cut row at the bottom)
				local m = BoostView.tableMetrics(screen.Compact)
				local listHeight = refs.Odds.List.Size.Y.Offset
				local rowsInView = listHeight / (m.Row + 2)
				T.truthy(math.abs(rowsInView - math.floor(rowsInView + 1e-6)) < 1e-6, label .. " whole rows in view")
				-- the summary row stays, with at least two rows under it (rarest first)
				local list = refs.Odds.List
				T.truthy(refs.Odds.ShowSummary and refs.Odds.Summary.Frame.Visible, label .. " the summary row stays")
				T.truthy(
					list.Size.Y.Offset >= 2 * (BoostView.tableMetrics(screen.Compact).Row + 2) - 0.5,
					label .. " two odds rows in view under the summary"
				)
				-- a gamepad: the glyph row shows, also on phones and TVs (bigger, in a footer of its own)
				BoostView.setHint(refs, "", { "a", "b", "c", "d", "e" })
				T.truthy(refs.PadHint.Visible, label .. " gamepad row shown")
				T.falsy(refs.Hint.Visible, label .. " no text hint with a gamepad")
				local pad = boxIn(refs.PadHint, panel)
				T.truthy(pad[3] <= panel[3] and pad[1] >= 0, label .. " gamepad row inside the panel")
				T.truthy(pad[2] + pad[4] <= panel[4], label .. " gamepad row inside the panel (y)")
				for _, frame in { refs.Card.Frame, refs.Odds.Frame } do
					T.falsy(overlaps(boxIn(frame, panel), pad), label .. " gamepad row under the body")
				end
				if screen.Compact then
					T.eq(refs.PadHint.Size.Y.Offset, 24 * BoostView.PadHintScale, label .. " bigger glyphs on phones / TVs")
				end
				BoostView.setHint(refs, "Click an offer", nil)
				T.falsy(refs.PadHint.Visible)
				T.eq(refs.Hint.Visible, not screen.Compact, label .. " text hint only on PC")
			end
		end
		-- the small phone gets the short card (both boosts)
		local small = SCREENS[5]
		local smallRefs = BoostView.build(true)
		BoostView.layout(smallRefs, true, small.Width, small.Height)
		T.eq(smallRefs.Card.Frame:GetAttribute("Short"), true, "short card on the small phone")
		local big = BoostView.build(false)
		BoostView.layout(big, false, SCREENS[3].Width, SCREENS[3].Height)
		T.eq(big.Card.Frame:GetAttribute("Short"), false, "the full card on a big PC")
		-- the subtitle fits its line
		local refs = BoostView.build(false)
		BoostView.layout(refs, false, 1280, 684)
		T.truthy(
			TechShopView.fits(refs.Subtitle.Text, refs.Panel.Size.X.Offset - 16 * 2 - 54, 22, refs.Subtitle.TextSize, false),
			"the subtitle fits"
		)
	end)
end
