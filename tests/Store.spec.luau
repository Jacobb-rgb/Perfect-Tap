-- The Robux STORE (owner 2026-10-20) under Lune: StoreConfig places a card for every
-- store product and picks the blaster band of the next level; StoreView builds every card
-- and shows their states; StoreService only prompts (by Grant: capsules and boosts go
-- through their own services, the blaster band and Server Luck answer "Full" when they
-- can't be given, passes "Owned"); Server Luck stacks, caps, feeds ore luck and ends.
-- Saves, Net and Roblox prompts are fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local StoreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoreConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local BoostService = Loader.requirePath("ServerScriptService.Server.Services.BoostService")
	local MonetizationService = Loader.requirePath("ServerScriptService.Server.Services.MonetizationService")
	local StoreService = Loader.requirePath("ServerScriptService.Server.Services.StoreService")
	local ServerBoostService = Loader.requirePath("ServerScriptService.Server.Services.ServerBoostService")
	local function ui(name: string)
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
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

	T.test("Store: a card for every store product, the blaster band of the next level", function()
		for _, key in { "CoinsSmall", "CoinsMedium", "CoinsLarge", "CoinsHuge", "CoinsMega", "RoyalCapsule5", "ServerLuck15", "BlasterNextA", "BlasterNextD" } do
			T.truthy(StoreConfig.sells(key), key .. " is sold")
		end
		T.falsy(StoreConfig.sells("Nope"), "unknown key")
		-- (review #12) the pass opens the Glimmer Grotto: its odds show before the buy
		T.truthy(StoreConfig.ById.BigPass.Odds, "the Forgemaster's Pass card shows the Grotto odds first")
		-- (review #4/#11) the blaster texts say what a rebirth really does
		for _, key in { "BlasterNextA", "BlasterNextB", "BlasterNextC", "BlasterNextD" } do
			T.truthy(string.find(MonetizationConfig.get(key).Description, "1 level higher", 1, true) ~= nil, key .. " text")
		end
		T.eq(StoreConfig.ById.Blaster.Note, "+1 rebirth start LV (max 9)")
		T.falsy(StoreConfig.sells(42), "junk")
		T.truthy(MonetizationConfig.CoinPacksDefault, "coin packs ship on (owner)")
		local spec = StoreConfig.ById.Blaster
		T.eq(StoreConfig.blasterKey(spec, 1), "BlasterNextA", "LV 1 -> next 2")
		T.eq(StoreConfig.blasterKey(spec, 3), "BlasterNextA", "LV 3 -> next 4")
		T.eq(StoreConfig.blasterKey(spec, 4), "BlasterNextB", "LV 4 -> next 5")
		T.eq(StoreConfig.blasterKey(spec, 7), "BlasterNextC", "LV 7 -> next 8")
		T.eq(StoreConfig.blasterKey(spec, 9), "BlasterNextD", "LV 9 -> the top")
		T.eq(StoreConfig.blasterKey(spec, 10), nil, "nothing at the top")
		T.eq(StoreConfig.blasterKey(spec, nil), "BlasterNextA", "no level: LV 1")
		-- (owner 2026-10-20 evening: sections one under the other) every card sits in a known
		-- section, every section has cards, and a section's rows fill 1..n
		local seen: { [string]: number } = {}
		for _, card in StoreConfig.Cards do
			T.truthy(StoreConfig.SectionById[card.Section], card.Id .. " in a known section")
			seen[card.Section] = (seen[card.Section] or 0) + 1
		end
		for _, section in StoreConfig.Sections do
			T.truthy((seen[section.Id] or 0) > 0, section.Id .. " has cards")
			for _, row in StoreConfig.rows(section.Id) do
				T.truthy(#row >= 1 and #row <= 4, section.Id .. ": 1 to 4 cards a row")
			end
		end
	end)

	T.test("Store: the Starbreaker odds show the change in every zone with Rare ores (review: never only Starter)", function()
		local CardOdds = ui("CardOdds")
		for level = 3, 10 do
			local state = { BlasterLevel = level, Enchants = { Owned = {}, Slots = {} }, Bonuses = {} }
			local text = table.concat(CardOdds.enchantLines(state, "Starbreaker", 1.7e9, {}), "\n")
			T.truthy(string.find(text, "Rare or better", 1, true) ~= nil, `LV {level}: the Rare or better line`)
			T.falsy(string.find(text, "No Rare ores", 1, true), `LV {level}: never "No Rare ores"`)
		end
	end)

	T.test("Store: the window builds every card and shows their states", function()
		local StoreView = ui("StoreView")
		local refs = StoreView.build()
		T.falsy(refs.Gui.Enabled, "hidden until opened")
		for _, card in StoreConfig.Cards do
			T.truthy(refs.Cards[card.Id], "card " .. card.Id)
		end
		T.eq(#refs.Order, #StoreConfig.Cards, "gamepad order")
		StoreView.setCard(refs, "Podiums", "Podiums", "Owned")
		T.truthy(refs.Cards.Podiums.Owned.Visible, "OWNED chip")
		T.falsy(refs.Cards.Podiums.Price.Visible, "no price on an owned pass")
		StoreView.setCard(refs, "Blaster", "BlasterNextB", "Buy")
		T.eq(refs.Cards.Blaster.Key, "BlasterNextB", "the band")
		T.eq(refs.Cards.Blaster.PriceAmount.Text, "99", "its price")
		StoreView.setCard(refs, "Blaster", "BlasterNextD", "Hidden")
		T.falsy(refs.Cards.Blaster.Button.Visible, "hidden at the top")
		StoreView.setCard(refs, "Royal5", "RoyalCapsule5", "Pending")
		T.falsy(refs.Cards.Royal5.Button.Active, "greyed while a buy is on its way")
		StoreView.setCoins(refs, 0)
		T.eq((refs.Cards.CoinsSmall.Amount :: any).Text, "$2.5K", "no income: the minimum")
		StoreView.setCoins(refs, 1000)
		T.eq((refs.Cards.CoinsMega.Amount :: any).Text, "$18M", "5 hours of 1,000/s")
		StoreView.showDetail(refs, { Title = "Royal Capsule x5", Lines = { "a", "b" }, Robux = 229, Paint = "Pink" })
		T.truthy(refs.Detail.Visible, "the odds panel")
		T.eq(refs.DetailLines.Text, "a\nb")
		StoreView.showDetail(refs, nil)
		T.falsy(refs.Detail.Visible)
		-- a short phone screen shrinks the whole window instead of cutting the cards
		local _, fitTall = StoreView.windowSize(1280, 720)
		local _, fitPhone = StoreView.windowSize(600, 300)
		T.eq(fitTall, 1, "a PC screen: full size")
		T.lt(fitPhone, 1, "a short screen: fitted")
		-- a hidden card closes its row up; a section with nothing to show folds away with its tab
		local before = refs.Cards.Blaster.Button.Position
		StoreView.setCard(refs, "Blaster", "BlasterNextD", "Hidden")
		T.eq(refs.Cards.StarComet.Button.Position.X.Offset, 0, "the next card moves to the row's start")
		T.eq(before.X.Offset, 0, "the blaster card was first")
		for _, id in { "Royal1", "Royal3", "Royal5", "Royal10" } do
			StoreView.setCard(refs, id, refs.Cards[id].Key, "Hidden")
		end
		T.falsy(refs.Sections.Eggs.Visible, "no capsules: the section folds")
		T.falsy((refs.Tabs.Eggs.Parent :: any).Visible, "and its tab hides")
		T.truthy(StoreView.sectionTop(refs, "Blasters") > StoreView.sectionTop(refs, "Luck"), "sections run top to bottom")
	end)

	-- (review #5) on phones the section tabs and the limited banner's buy buttons stay >= 44 pt
	T.test("Store: phone tabs and banner buttons are at least 44 pt", function()
		local StoreView = ui("StoreView")
		local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
		local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
		T.truthy(edition, "the edition runs a day before its end")
		for _, screen in { { 667, 375 }, { 844, 390 }, { 568, 320 }, { 740, 360 } } do
			local scale = 0.62 -- HudController.uiScale on phones
			local w, h = screen[1] / scale, (screen[2] - 58) / scale
			local refs = StoreView.build()
			StoreView.setEdition(refs, edition)
			StoreView.layout(refs, w, h, true)
			local pt = refs.Fit * scale
			for id, face in refs.Tabs do
				local frame = face.Parent :: any
				T.truthy(frame.Size.Y.Offset * pt >= 44, `tab {id} >= 44 pt at {screen[1]}x{screen[2]} ({frame.Size.Y.Offset * pt})`)
			end
			for count, button in (refs.Banner :: any).Buys do
				T.truthy(button.Size.Y.Offset * pt >= 44, `banner x{count} >= 44 pt at {screen[1]}x{screen[2]}`)
			end
			T.truthy(refs.DetailBuy.Size.Y.Offset * pt >= 44, "the odds panel's BUY")
		end
	end)

	-- (review #6) with the icon sheets not uploaded, every card still shows a picture (a live model) or lays out without one
	T.test("Store: no blank picture areas before the icon sheets are uploaded", function()
		local StoreView = ui("StoreView")
		local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
		local before = IconAssets.Previewing
		IconAssets.Previewing = false
		local ok, err = pcall(function()
			for _, spec in StoreConfig.Cards do
				T.truthy(StoreView.hasPicture(spec), spec.Id .. " shows a picture in the game")
			end
		end)
		IconAssets.Previewing = before
		if not ok then
			error(err, 0)
		end
	end)

	-- (review #3/#4/#9) the banner: the real end date, a quiet time left, the odds a buy rolls now
	T.test("Store: the limited banner shows the end date and the odds with Triple Lucky", function()
		local StoreView = ui("StoreView")
		local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
		local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
		T.eq(StoreView.endsOn(1796083199), "ENDS NOV 30")
		T.eq(StoreView.countdown(29 * 86400 + 21 * 3600 + 59), "29d 21h left")
		T.eq(StoreView.countdown(3 * 3600 + 15 * 60 + 40), "3h 15m left", "no ticking seconds")
		local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
		local refs = StoreView.build()
		local banner = StoreView.setEdition(refs, edition) :: any
		T.falsy(string.find(banner.Frame.Tagline.Text, "Limited time", 1, true), "no rush line")
		local odds = {}
		for _, line in CapsuleConfig.odds(edition.CapsuleId, true) do
			odds[line.Golem] = line.Chance
		end
		StoreView.setBannerOdds(refs, odds, true)
		local mythic = edition.Golems[#edition.Golems]
		T.eq(banner.Chances[mythic.Id].Text, StoreView.percent(odds[mythic.Id]), "the Mythic tile shows the lucky chance")
		T.truthy(odds[mythic.Id] > edition.Odds[mythic.Id], "Triple Lucky raises it")
		T.truthy(banner.Lucky.Parent.Visible, "the WITH TRIPLE LUCKY tag")
	end)

	-- StoreService with fakes: the save, Net answers and the prompts it asks for
	local function withStore(name: string, fn: (w: any) -> ())
		T.test(name, function()
			local w: any = { answers = {}, prompts = {} }
			w.player = { UserId = 7, Name = "Buyer", DisplayName = "Buyer", Parent = true }
			w.data = deepCopy(DataTemplate)
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			patch(DataService, "get", function(p)
				return if p == w.player then w.data else nil
			end)
			patch(Net, "fire", function(event, _, payload)
				if event == "PurchasePrompt" then
					table.insert(w.answers, payload)
				end
			end)
			patch(BoostService, "promptPurchase", function(_, key, owned, full)
				table.insert(w.prompts, { Key = key, Owned = owned, Full = full })
				return "Prompted"
			end)
			patch(MonetizationService, "owns", function(_, key)
				return w.owned ~= nil and w.owned[key] == true
			end)
			local ok, err = pcall(fn, w)
			for i = #saved, 1, -1 do
				local entry = saved[i]
				rawset(entry[1], entry[2], entry[3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	withStore("Store: StoreService only prompts, by Grant", function(w)
		StoreService.buy(w.player, "Nope")
		T.eq(w.answers[#w.answers].Status, "Unknown", "an unknown key")
		StoreService.buy(w.player, "RoyalCapsule5")
		T.eq(w.answers[#w.answers].Status, "Unknown", "capsules go through CapsuleAction")
		StoreService.buy(w.player, "HexaLucky15")
		T.eq(w.answers[#w.answers].Status, "Unknown", "boosts go through BoostAction")
		T.eq(#w.prompts, 0, "nothing prompted for those")
		w.data.BlasterLevel = 1
		StoreService.buy(w.player, "BlasterNextA")
		T.eq(w.prompts[#w.prompts].Key, "BlasterNextA")
		T.falsy(w.prompts[#w.prompts].Full, "LV 2 is in band A")
		StoreService.buy(w.player, "BlasterNextB")
		T.truthy(w.prompts[#w.prompts].Full, "band B doesn't hold LV 2: Full")
		w.data.BlasterLevel = 10
		StoreService.buy(w.player, "BlasterNextD")
		T.truthy(w.prompts[#w.prompts].Full, "the top level: Full")
		StoreService.buy(w.player, "CoinsMega")
		T.eq(w.prompts[#w.prompts].Key, "CoinsMega", "a coin pack is prompted")
		w.owned = { BigPass = true }
		StoreService.buy(w.player, "BigPass")
		T.truthy(w.prompts[#w.prompts].Owned, "an owned pass: Owned")
		StoreService.buy(w.player, "Podiums")
		T.falsy(w.prompts[#w.prompts].Owned, "not owned")
		StoreService.buy(w.player, "ServerLuck15")
		T.falsy(w.prompts[#w.prompts].Full, "Server Luck has room")
	end)

	T.test("Store: Server Luck stacks, caps, feeds ore luck and ends", function()
		local now = 1000
		local timers: { { At: number, Fn: () -> () } } = {}
		ServerBoostService._test.reset()
		ServerBoostService._test.setClock(function()
			return now
		end)
		ServerBoostService._test.setAfter(function(seconds, fn)
			table.insert(timers, { At = now + seconds, Fn = fn })
		end)
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local notes = {}
		patch(Net, "fireAll", function(_, payload)
			table.insert(notes, payload)
		end)
		patch(StateService, "push", function() end)
		ServerBoostService._test.setPlayers(function()
			return {}
		end)
		ServerBoostService.init() -- the "ServerBoost" handler and the "ServerLuck" Bonuses provider
		local ok, err = pcall(function()
			local entry = MonetizationConfig.get("ServerLuck15")
			local buyer = { DisplayName = "Kuba" }
			T.truthy(ServerBoostService._test.grant(buyer, {}, entry), "granted")
			T.eq(ServerBoostService.left(), 900, "15 minutes")
			T.truthy(string.find(notes[#notes].Text, "Kuba", 1, true) ~= nil, "everyone hears who bought it")
			ServerBoostService._test.grant(buyer, {}, entry)
			T.eq(ServerBoostService.left(), 1800, "stacks")
			T.truthy(ServerBoostService.full(ServerBoostService.MaxSeconds), "a buy past the cap is Full")
			for _ = 1, 40 do
				ServerBoostService.extend(900, nil)
			end
			T.eq(ServerBoostService.left(), ServerBoostService.MaxSeconds, "capped")
			-- (review #13) a receipt that lands at the cap still gets its full 15 minutes
			ServerBoostService._test.grant(buyer, {}, entry)
			T.eq(ServerBoostService.left(), ServerBoostService.MaxSeconds + 900, "a paid receipt is never cut")
			local stats = Bonuses.compute(deepCopy(DataTemplate), now, nil)
			T.eq(stats.OreLuckMult, ServerBoostService.Mult, "x2 ore luck while it runs")
			-- the clock runs past the end: the last timer ends it
			now += ServerBoostService.MaxSeconds + 901
			for _, timer in timers do
				timer.Fn()
			end
			T.falsy(ServerBoostService.active(), "ended")
			T.eq(notes[#notes].Text, "Server Luck ran out.")
			local after = Bonuses.compute(deepCopy(DataTemplate), now, nil)
			T.eq(after.OreLuckMult or 1, 1, "no luck after")
			T.falsy(entry.Id > 0, "a placeholder id")
			T.truthy(entry.PaidRandom, "changes odds: a paid random item")
		end)
		for i = #saved, 1, -1 do
			local s = saved[i]
			rawset(s[1], s[2], s[3])
		end
		ServerBoostService._test.reset()
		ServerBoostService._test.setClock(os.time)
		Bonuses.unregister("ServerLuck")
		local _ = roblox
		if not ok then
			error(err, 0)
		end
	end)
end
