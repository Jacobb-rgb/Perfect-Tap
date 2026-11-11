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
		for _, key in
			{
				"CoinsSmall",
				"CoinsMedium",
				"CoinsLarge",
				"CoinsHuge",
				"CoinsMega",
				"RoyalCapsule5",
				"ServerLuck15",
				"BlasterNextA",
				"BlasterNextD",
			}
		do
			T.truthy(StoreConfig.sells(key), key .. " is sold")
		end
		T.falsy(StoreConfig.sells("Nope"), "unknown key")
		-- (review #12) the pass opens the Glimmer Grotto: its odds show before the buy
		T.truthy(StoreConfig.ById.BigPass.Odds, "the Forgemaster's Pass card shows the Grotto odds first")
		T.truthy(StoreConfig.ById.BigPassWide.Odds, "and its wide card on PASSES")
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
		-- (shop v3, owner 2026-11-11) six tabs, every card on a known one, every tab has cards,
		-- a tab's rows fill 1..n with 1 to 5 cards
		local ids = {}
		for _, section in StoreConfig.Sections do
			table.insert(ids, section.Id)
		end
		T.eq(table.concat(ids, ","), "Featured,Golems,Blasters,Passes,Boosts,Cash", "the six tabs in the concept's order")
		local seen: { [string]: number } = {}
		for _, card in StoreConfig.Cards do
			T.truthy(StoreConfig.SectionById[card.Section], card.Id .. " in a known tab")
			seen[card.Section] = (seen[card.Section] or 0) + 1
		end
		for _, section in StoreConfig.Sections do
			T.truthy((seen[section.Id] or 0) > 0, section.Id .. " has cards")
			for r, row in StoreConfig.rows(section.Id) do
				T.truthy(#row >= 1 and #row <= 5, section.Id .. ": 1 to 5 cards a row")
				T.truthy(section.RowHeights[r] ~= nil, section.Id .. " row " .. r .. " has a height")
			end
		end
	end)

	-- (owner rule 2026-11-11) everything the shop sold before is still on a tab, plus the wheel's spins
	T.test("Store: every product the shop sells stays reachable on a tab", function()
		local reachable: { [string]: boolean } = {}
		for _, spec in StoreConfig.Cards do
			for _, key in StoreConfig.keysOf(spec) do
				reachable[key] = true
			end
		end
		local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
		local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
		if edition then
			for _, key in edition.Products do
				reachable[key] = true -- (the FEATURED banner's four buttons)
			end
		end
		for _, key in
			{
				"BigPass",
				"StarterPack",
				"Podiums",
				"OfflineExtension",
				"DoubleMoney",
				"TrainExpress",
				"HoverboardCustom",
				"CoinsSmall",
				"CoinsMedium",
				"CoinsLarge",
				"CoinsHuge",
				"CoinsMega",
				"TripleLucky15",
				"TripleLucky60",
				"HexaLucky15",
				"HexaLucky60",
				"ServerLuck15",
				"WheelSpins1",
				"WheelSpins5",
				"WheelSpins10",
				"EnchantHeartfire",
				"EnchantStarbreaker",
				"BlasterNextA",
				"BlasterNextB",
				"BlasterNextC",
				"BlasterNextD",
				"RoyalCapsule1",
				"RoyalCapsule3",
				"RoyalCapsule5",
				"RoyalCapsule10",
				"StarComet",
				"StarNebula",
				"StarPulsar",
				"StarSupernova",
				"StarSingularity",
				"DragonforgeCapsule1",
				"DragonforgeCapsule3",
				"DragonforgeCapsule10",
				"DragonforgeCapsule50",
			}
		do
			T.truthy(reachable[key], key .. " is on a tab")
			T.truthy(MonetizationConfig.Products[key] ~= nil, key .. " exists")
		end
		-- every product it shows has a Grant (a handler gives it: MonetizationService)
		for key in reachable do
			local product = MonetizationConfig.Products[key]
			T.truthy(product and product.Grant ~= nil, key .. " has a Grant")
		end
	end)

	-- (owner rule 2026-11-11) paid random products and the pass that opens odds always show the odds first
	T.test("Store: every paid random buy button shows the odds before the buy", function()
		local StoreView = ui("StoreView")
		local refs = StoreView.build()
		local buttons = 0
		for _, card in refs.Cards do
			for key, face in card.Buys do
				buttons += 1
				local product = MonetizationConfig.Products[key]
				T.eq(face:GetAttribute("Key"), key, card.Spec.Id .. ": the button knows its product")
				if product.PaidRandom then
					T.truthy(face:GetAttribute("Odds"), `{card.Spec.Id} {key}: the odds first`)
					T.truthy(StoreView.needsOdds(card.Spec, key), key)
				end
			end
		end
		T.truthy(buttons >= #StoreConfig.Cards, "a price button on every card")
		T.truthy(StoreView.needsOdds(StoreConfig.ById.BigPass, "BigPass"), "the pass: the Grotto odds first")
		T.falsy(StoreView.needsOdds(StoreConfig.ById.Podiums, "Podiums"), "a plain pass: no odds panel")
		for _, key in { "WheelSpins1", "WheelSpins5", "WheelSpins10", "TripleLucky60", "HexaLucky60", "ServerLuck15", "EnchantStarbreaker" } do
			T.truthy(MonetizationConfig.Products[key].PaidRandom, key .. " is a paid random item")
		end
		-- the limited banner's buttons too
		local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
		local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
		if edition then
			local banner = StoreView.setEdition(refs, edition) :: any
			for count, face in banner.Buys do
				T.truthy(face:GetAttribute("Odds"), `x{count}: the odds first`)
				T.eq(face:GetAttribute("Key"), edition.Products[count])
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
		T.truthy(refs.Cards.Podiums.Owned.Visible, "OWNED")
		T.falsy((refs.Cards.Podiums.Price.Parent :: any).Visible, "no price on an owned pass")
		StoreView.setCard(refs, "Blaster", "BlasterNextB", "Buy")
		T.eq(refs.Cards.Blaster.Key, "BlasterNextB", "the band")
		T.eq(refs.Cards.Blaster.PriceAmount.Text, "99", "its price")
		T.eq(refs.Cards.Blaster.Price:GetAttribute("Key"), "BlasterNextB", "its button buys the band")
		StoreView.setCard(refs, "Blaster", "BlasterNextD", "Hidden")
		T.falsy(refs.Cards.Blaster.Holder.Visible, "hidden at the top")
		StoreView.setCard(refs, "Royal5", "RoyalCapsule5", "Pending")
		T.falsy(refs.Cards.Royal5.Price.Active, "greyed while a buy is on its way")
		T.truthy(refs.Cards.Royal5.Shade.Visible)
		StoreView.setCoins(refs, 0)
		T.eq((refs.Cards.CoinsSmall.Amount :: any).Text, "$2.5K", "no income: the minimum")
		StoreView.setCoins(refs, 1000)
		T.eq((refs.Cards.CoinsMega.Amount :: any).Text, "$18M", "5 hours of 1,000/s")
		T.eq((refs.Cards.StarterPack.Amount :: any).Text, "$1.2M", "the Starter Pack: 20 min of 1,000/s")
		StoreView.showDetail(refs, { Title = "Royal Egg x5", Lines = { "a", "b" }, Robux = 229, Paint = "Pink" })
		T.truthy(refs.Detail.Visible, "the odds panel")
		T.eq(refs.DetailLines.Text, "a\nb")
		StoreView.showDetail(refs, nil)
		T.falsy(refs.Detail.Visible)
		-- a short phone screen shrinks the whole window instead of cutting the cards
		local _, fitTall = StoreView.windowSize(1280, 720)
		local _, fitPhone = StoreView.windowSize(600, 300)
		T.eq(fitTall, 1, "a PC screen: full size")
		T.lt(fitPhone, 1, "a short screen: fitted")
		-- a hidden card closes its row up; a tab with nothing to show hides (the open one moves)
		T.eq(refs.Cards.StarComet.Holder.Position.X.Offset, 0, "the next card moves to the row's start")
		StoreView.selectTab(refs, "Golems")
		for _, id in { "Royal1", "Royal3", "Royal5", "Royal10" } do
			StoreView.setCard(refs, id, refs.Cards[id].Key, "Hidden")
		end
		StoreView.setRoyalShown(refs, false)
		T.falsy(StoreView.tabShown(refs, "Golems"), "no eggs: the tab hides")
		T.truthy(refs.Current ~= "Golems", "the open tab moved to one that shows")
		T.falsy(table.find(StoreView.visibleTabs(refs), "Golems"), "not in the LB / RB order")
	end)

	-- (shop v3) a tab shows its own page in its own colours; nothing else shows
	T.test("Store: a tab shows its page, its colour world and the first thing a gamepad lands on", function()
		local StoreView = ui("StoreView")
		local ShopFx = ui("ShopFx")
		local refs = StoreView.build()
		for _, section in StoreConfig.Sections do
			T.truthy(StoreView.selectTab(refs, section.Id) or refs.Current == section.Id, section.Id)
			for id, page in refs.Pages do
				T.eq(page.Visible, id == section.Id, section.Id .. ": only its page shows (" .. id .. ")")
			end
			local paint = refs.Window.Header:FindFirstChild("Paint") :: any
			T.eq(paint.Color.Keypoints[1].Value, ShopFx.Themes[section.Id].Head[1], section.Id .. ": its header colour")
			local first = StoreView.firstSelectable(refs) :: any
			T.truthy(first and first:IsDescendantOf(refs.Pages[section.Id]), section.Id .. ": the gamepad lands on its page")
			T.truthy(first.Selectable, "a selectable stop")
			local tab = refs.TabRefs[section.Id]
			T.truthy(tab.Ring.Visible, "the open tab's white rim")
			T.truthy(tab.Scale.Scale > 1, "the open tab is bigger")
		end
		-- a multi-option card: no face stop, every option is one; a one-price card: the face
		T.falsy(refs.Cards.WheelSpins.Button.Selectable, "the wheel card's face is no stop")
		for _, key in StoreConfig.ById.WheelSpins.Options :: { string } do
			T.truthy(refs.Cards.WheelSpins.Buys[key].Selectable, key .. " is a stop")
		end
		T.truthy(refs.Cards.Podiums.Button.Selectable, "a pass card is one stop")
		T.falsy(refs.Cards.Podiums.Price.Selectable, "its price is not a second one")
	end)

	-- (review #5) on phones the tabs, the buy buttons and the odds panel's BUY stay >= 44 pt
	T.test("Store: phone tabs and buy buttons are at least 44 pt", function()
		local StoreView = ui("StoreView")
		local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
		local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - 86400)
		T.truthy(edition, "the edition runs a day before its end")
		for _, screen in { { 667, 375 }, { 844, 390 }, { 568, 320 }, { 740, 360 } } do
			local scale = 0.62 -- HudController.uiScale on phones
			local w, h = screen[1] / scale, (screen[2] - 58) / scale
			local _, fit = StoreView.windowSize(w, h)
			local refs = StoreView.build(StoreView.metricsFor(true, fit))
			StoreView.setEdition(refs, edition)
			StoreView.layout(refs, w, h, true)
			T.falsy(StoreView.needsRebuild(refs, w, h, true), "built for this screen")
			local pt = refs.Fit * scale
			local where = `{screen[1]}x{screen[2]}`
			for id, face in refs.Tabs do
				local size = (face.Parent :: any).Parent.Size
				local k = refs.TabRefs[id].Scale.Scale
				T.truthy(size.Y.Offset * k * pt >= 44 - 1e-6, `tab {id} >= 44 pt at {where} ({size.Y.Offset * k * pt})`)
			end
			for id, card in refs.Cards do
				for key, face in card.Buys do
					local size = StoreView.buttonSize(face)
					T.truthy(size.Y * pt >= 44 - 1e-6, `{id} {key} >= 44 pt at {where} ({size.Y * pt})`)
				end
			end
			for count, face in (refs.Banner :: any).Buys do
				T.truthy(StoreView.buttonSize(face).Y * pt >= 44 - 1e-6, `banner x{count} >= 44 pt at {where}`)
			end
			T.truthy(StoreView.buttonSize(refs.DetailBuy).Y * pt >= 44 - 1e-6, "the odds panel's BUY")
			T.truthy(refs.Window.Close.Parent and (refs.Window.Close.Parent :: any).Size.Y.Offset * pt >= 44 - 1e-6, "the X")
			-- the six tabs fit between the basket and the X
			local m = refs.Metrics
			local right = 0
			for _, tab in refs.TabRefs do
				right = math.max(right, tab.Holder.Position.X.Offset + tab.Width / 2)
			end
			T.truthy(right <= StoreView.Width - (m.Close + 14), `{where}: the tabs end before the X ({right})`)
		end
		-- a PC is not rebuilt for a phone's sizes until it is one
		local pc = StoreView.build()
		T.falsy(StoreView.needsRebuild(pc, 1280, 684, false))
		T.truthy(StoreView.needsRebuild(pc, 1076, 511, true))
	end)

	-- (review #6) with the icon sheets not uploaded, every card still shows a picture (a live model, a drawn one)
	T.test("Store: no blank picture areas before the icon sheets are uploaded", function()
		local StoreView = ui("StoreView")
		local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
		local before, beforeId = IconAssets.Previewing, IconAssets.Shop.Id
		IconAssets.Previewing = false
		IconAssets.Shop.Id = 0 -- (as before the owner's upload, or if it ever fails to load)
		local ok, err = pcall(function()
			for _, spec in StoreConfig.Cards do
				T.truthy(StoreView.hasPicture(spec), spec.Id .. " shows a picture in the game")
			end
			-- no empty sheet pictures in the built window either (the 3D models stand in)
			local refs = StoreView.build()
			for _, d in refs.Gui:GetDescendants() do
				if d:IsA("ImageLabel") then
					local icon = d:GetAttribute("Icon")
					T.falsy(
						type(icon) == "string" and string.sub(icon, 1, 5) == "shop_",
						"no sheet picture before the upload: " .. d:GetFullName()
					)
				end
			end
		end)
		IconAssets.Previewing = before
		IconAssets.Shop.Id = beforeId
		if not ok then
			error(err, 0)
		end
	end)

	-- (owner 2026-11-11) his upload of the shop icon sheet is in: every tab and card picture shows from it
	T.test("Store: the uploaded shop icon sheet shows its pictures", function()
		local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
		T.truthy(IconAssets.Shop.Id > 0, "the owner's upload is set")
		T.truthy(IconAssets.shopShows("clover"), "the clover (Lucky) shows from the sheet")
	end)

	-- (owner rule 2026-11-11) the stickers only say what the prices back up
	T.test("Store: BEST VALUE only where the price per item is the lowest", function()
		local StoreView = ui("StoreView")
		T.eq(StoreView.bestValue({ "RoyalCapsule1", "RoyalCapsule3", "RoyalCapsule5", "RoyalCapsule10" }), "RoyalCapsule10")
		T.eq(StoreView.bestValue({ "WheelSpins1", "WheelSpins5", "WheelSpins10" }), "WheelSpins10")
		T.eq(StoreView.bestValue({ "TripleLucky15", "TripleLucky60" }), "TripleLucky60")
		T.eq(
			StoreView.bestValue({ "DragonforgeCapsule1", "DragonforgeCapsule3", "DragonforgeCapsule10", "DragonforgeCapsule50" }),
			"DragonforgeCapsule50"
		)
		local packs = { "CoinsSmall", "CoinsMedium", "CoinsLarge", "CoinsHuge", "CoinsMega" }
		T.eq(StoreView.bestValue(packs, 0), "CoinsMega", "at no income (the minimums)")
		T.eq(StoreView.bestValue(packs, 1840), "CoinsMega", "at $1.84K/s")
		T.eq(StoreView.bestValue({ "BigPass" }), nil, "one option: nothing to compare")
		T.eq(StoreView.bestValue({ "WheelSpins1", "WheelSpins1" }), nil, "a tie: no claim")
		-- the built shop: one sticker on the eggs, the best coin pack only
		local refs = StoreView.build()
		StoreView.setCoins(refs, 1840)
		for _, card in refs.Cards do
			if card.Spec.Look == "Coins" or card.Spec.Look == "Egg" then
				local best = card.Spec.Id == "CoinsMega" or card.Spec.Id == "Royal10"
				T.eq((card.Sticker :: any).Visible, best, card.Spec.Id .. " sticker")
			end
		end
		-- no made-up words anywhere in the window (the concept's placeholders)
		for _, d in refs.Gui:GetDescendants() do
			if d:IsA("TextLabel") then
				for _, banned in { "POPULAR", "FREE!", "Yours forever", "FOR EVERYONE", "250K", "15 min luck" } do
					T.falsy(string.find(d.Text, banned, 1, true), `"{banned}" in {d:GetFullName()}`)
				end
			end
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
		StoreView.setTimer(refs, 86400 + 3600)
		T.eq(banner.Timer.Text, StoreView.endsOn(edition.EndsAt) .. " · 1d 1h left", "the real end and the time left")
		local odds = {}
		for _, line in CapsuleConfig.odds(edition.CapsuleId, true) do
			odds[line.Golem] = line.Chance
		end
		StoreView.setBannerOdds(refs, odds, true)
		local mythic = edition.Golems[#edition.Golems]
		T.eq(banner.Chances[mythic.Id].Text, StoreView.percent(odds[mythic.Id]), "the Mythic tile shows the lucky chance")
		T.eq(banner.Hero.Text, `{mythic.Name} {StoreView.percent(odds[mythic.Id])}`, "and the big one's chip")
		T.truthy(odds[mythic.Id] > edition.Odds[mythic.Id], "Triple Lucky raises it")
		T.truthy(banner.Lucky.Parent.Visible, "the WITH TRIPLE LUCKY tag")
		-- the Royal Egg's tiles the same way
		local royal = {}
		for _, line in CapsuleConfig.odds("Royal", false) do
			royal[line.Golem] = line.Chance
		end
		StoreView.setRoyalOdds(refs, royal, false)
		T.eq((refs.Royal :: any).Chances.CelestialSovereign.Text, "1%")
		T.eq((refs.Royal :: any).Chances.SilverSquire.Text, "48%")
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
		StoreService.buy(w.player, "WheelSpins10")
		T.eq(w.answers[#w.answers].Status, "Unknown", "spins go through WheelAction (its Full rules)")
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
