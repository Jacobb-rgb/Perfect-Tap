-- LIMITED EDITION golems (Config/LimitedGolems, the Dragonforge set): the
-- set's 6 golems (Rare, Rare, Epic, Epic, Legendary, Mythic) are real golem
-- kinds with balanced bonuses; its Robux capsule (packs of 1 / 3 / 10 / 50)
-- is shop-only and its odds sum to 1 (Triple Lucky too); current(now) is
-- the banner's Edition until EndsAt and nil after; the server prompts the
-- capsule only while the edition runs ("Ended" after) but a receipt is
-- always granted (also the x50: paid golems past the cap, the rest in the
-- pending credit); the opening shows a big pack as a card per kind.
return function(T, Loader)
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")

	local caps = CapsuleService._test
	local ENDS = LimitedGolems.Current.EndsAt
	local DURING = ENDS - 86400
	local AFTER = ENDS + 1

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

	---------------------------------------------------------------- the set

	T.test("LimitedGolems: Dragonforge's 6 golems are real kinds by rarity with balanced bonuses", function()
		local set = LimitedGolems.Sets.Dragonforge
		T.truthy(set and set.Id == "Dragonforge" and #set.Title > 0 and #set.Tagline > 0, "the set")
		local golems = LimitedGolems.golems("Dragonforge")
		T.eq(#golems, 6)
		local names = {}
		for i, golem in golems do
			T.eq(golem.Rarity, LimitedGolems.SetRarities[i], golem.Id .. " rarity")
			T.eq(golem.Edition, "Dragonforge")
			T.eq(GolemConfig.ById[golem.Id], golem, golem.Id .. " is a real golem kind")
			T.truthy(golem.Accessory:sub(1, 6) == "Dragon", golem.Id .. " wears dragon gear")
			table.insert(names, golem.Name)
		end
		T.eq(table.concat(names, ", "), "Cinder Whelp, Ember Hatchling, Dragonscale Knight, Flamewing, Magma Wyvern, Dragon King")
		-- the Legendary and the Mythic are the best of their rarity in their bonus type
		for _, golem in golems do
			if Rarity.ById[golem.Rarity].Order >= 5 then
				for _, other in GolemConfig.List do
					if other ~= golem and other.Rarity == golem.Rarity and other.Bonus.Type == golem.Bonus.Type then
						T.truthy(golem.Bonus.Value > other.Bonus.Value, `{golem.Id} beats {other.Id}`)
					end
				end
			end
		end
		T.eq(GolemConfig.ById.DragonKing.Bonus.Type, "Income")
		T.truthy(GolemConfig.ById.DragonKing.Bonus.Value >= GolemConfig.ById.CelestialSovereign.Bonus.Value, "the best Income golem")
	end)

	T.test("LimitedGolems: the capsule is shop-only, its packs are 1 / 3 / 10 / 50 and its odds sum to 1", function()
		local capsule = CapsuleConfig.ById.Dragonforge
		T.eq(capsule.Currency, "Robux")
		T.eq(capsule.Limited, "Dragonforge")
		T.eq(capsule.LuckyFrom, "Legendary")
		T.falsy(table.find(CapsuleConfig.Stall, capsule), "never at the stall or in the capsule panel")
		local robux = { [1] = 99, [3] = 249, [10] = 799, [50] = 3499 }
		for count, price in robux do
			local key = CapsuleConfig.product("Dragonforge", count)
			local product = key and MonetizationConfig.get(key)
			T.truthy(product, `x{count} product`)
			T.eq(product.Key, `DragonforgeCapsule{count}`)
			T.eq(product.Robux, price, `x{count} price`)
			T.eq(product.Count, count)
			T.eq(product.Capsule, "Dragonforge")
			T.eq(product.Grant, "Capsule")
			T.eq(product.PaidRandom, true, "a paid random item (PolicyService)")
			T.eq(product.Id, 0, "the owner pastes the id")
			T.truthy(product.Description:find("odds shown before buying", 1, true), "honest text")
		end
		T.truthy(CapsuleConfig.isPaidRandom("Dragonforge"))
		T.truthy(CapsuleConfig.MaxCount >= 50)
		for _, lucky in { false, true } do
			local total = 0
			for _, line in CapsuleConfig.odds("Dragonforge", lucky) do
				T.eq(GolemConfig.ById[line.Golem].Edition, "Dragonforge", line.Golem)
				total += line.Chance
			end
			T.near(total, 1, 1e-9, `odds sum to 1 (Triple Lucky {lucky})`)
		end
		local lucky = CapsuleConfig.odds("Dragonforge", true)
		T.near(lucky[#lucky].Chance, 0.03, 1e-9, "Triple Lucky: the Dragon King x3")
	end)

	---------------------------------------------------------------- the edition window

	T.test("LimitedGolems: current() is the banner's edition until EndsAt, nil after", function()
		T.truthy(type(ENDS) == "number" and ENDS == math.floor(ENDS) and ENDS > 1_700_000_000, "a real unix time")
		local edition = LimitedGolems.current(DURING)
		T.truthy(edition, "on sale")
		T.eq(edition.Id, "Dragonforge")
		T.eq(edition.Title, "DRAGONFORGE")
		T.eq(edition.CapsuleId, "Dragonforge")
		T.eq(edition.EndsAt, ENDS)
		T.eq(#edition.Golems, 6)
		T.eq(edition.Golems[6].Id, "DragonKing", "set order: the Mythic last")
		local total = 0
		for _, golem in edition.Golems do
			total += edition.Odds[golem.Id]
		end
		T.near(total, 1, 1e-9, "the banner's odds sum to 1")
		T.eq(edition.Products[50], "DragonforgeCapsule50")
		T.eq(edition.Products[1], "DragonforgeCapsule1")
		T.truthy(LimitedGolems.current(ENDS), "the last second still counts")
		T.eq(LimitedGolems.current(AFTER), nil, "nil after EndsAt")
		T.eq(LimitedGolems.current(0 / 0 :: any), nil, "a broken clock")
		T.truthy(LimitedGolems.onSale("Dragonforge", DURING))
		T.falsy(LimitedGolems.onSale("Dragonforge", AFTER))
		T.truthy(LimitedGolems.onSale("Royal", AFTER), "other capsules don't end")
		-- a Current pointing at a set that doesn't exist: nothing on sale
		local old = LimitedGolems.Current
		LimitedGolems.Current = { Id = "Nope", EndsAt = ENDS }
		local ok = pcall(function()
			T.eq(LimitedGolems.current(DURING), nil)
			T.falsy(LimitedGolems.onSale("Dragonforge", DURING))
		end)
		LimitedGolems.Current = old
		T.truthy(ok)
		-- the end text exists
		T.truthy(CapsuleConfig.Reasons.Ended, "the Ended reason has a text")
	end)

	---------------------------------------------------------------- the server

	local function world(now: number): any
		local w: any = { notes = {}, prompted = {}, now = now }
		w.player = { UserId = 811, Name = "Dragon", DisplayName = "Dragon", Parent = true, attrs = {} }
		w.player.GetAttribute = function(_, key)
			return w.player.attrs[key]
		end
		w.player.SetAttribute = function(_, key, value)
			w.player.attrs[key] = value
		end
		w.data = deepCopy(DataTemplate)
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data else nil
		end)
		patch(DataService, "changed", function(p)
			Bonuses.invalidate(p)
		end)
		patch(Net, "fire", function(name, p, a)
			table.insert(w.notes, { Name = name, Player = p, A = a })
		end)
		caps.reset()
		caps.setClock(function()
			return w.now
		end)
		caps.setRandom(function()
			local i = 0
			return {
				NextNumber = function()
					i += 1
					return (i * 0.137) % 1
				end,
			}
		end)
		caps.setPrompter(function(p, id)
			table.insert(w.prompted, { Player = p, Id = id })
		end)
		caps.setPlayers(function()
			return { w.player }
		end)
		caps.setPushState(function() end)
		caps.setPublish(function() end)
		Policy._test.reset()
		Policy._test.setFetcher(function()
			return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = false }
		end)
		Bonuses._test.setClock(function()
			return w.now
		end)
		w.act = function(arg: any): (string?, any)
			local before = #w.notes
			caps.action(w.player, "Open", arg)
			for i = before + 1, #w.notes do
				local note = w.notes[i]
				if note.Name == "ActionResult" or note.Name == "PurchasePrompt" or note.Name == "CapsuleResult" then
					return note.Name, note.A
				end
			end
			return nil, nil
		end
		w.restore = function()
			caps.reset()
			Policy._test.reset()
			Bonuses._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	local function withWorld(name: string, now: number, fn: (any) -> ())
		T.test(name, function()
			local w = world(now)
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	withWorld("LimitedGolems: the server prompts the capsule while the edition runs, never after", DURING, function(w)
		local product = MonetizationConfig.Products.DragonforgeCapsule10
		local oldId = product.Id
		product.Id = 777010
		local ok, err = pcall(function()
			CapsuleService.setReceiptsReady(true)
			for _, count in { 1, 3, 10, 50 } do
				local name, answer = w.act({ Capsule = "Dragonforge", Count = count })
				T.eq(name, "PurchasePrompt", `x{count} while it runs`)
				T.eq(answer.Product, `DragonforgeCapsule{count}`)
			end
			T.eq(#w.prompted, 1, "the live x10 was prompted (the others are placeholders)")
			T.eq(w.prompted[1].Id, 777010)
			-- a x50 needs room for PromptRoom golems, not 50
			for _ = 1, GolemConfig.InventoryCap - CapsuleConfig.PromptRoom do
				GolemConfig.add(w.data.Golems, "PebbleGolem")
			end
			local _, roomy = w.act({ Capsule = "Dragonforge", Count = 10 })
			T.eq(roomy.Status, "Prompted", "room for 10")
			GolemConfig.add(w.data.Golems, "PebbleGolem")
			local _, full = w.act({ Capsule = "Dragonforge", Count = 10 })
			T.eq(full.Status, "Full", "no room for 10")
			-- after the end: refused, no prompt
			w.now = AFTER
			local before = #w.prompted
			for _, count in { 1, 3, 10, 50 } do
				local name, answer = w.act({ Capsule = "Dragonforge", Count = count })
				T.eq(name, "ActionResult", `x{count} after the end`)
				T.eq(answer.Ok, false)
				T.eq(answer.Reason, "Ended")
				T.eq(answer.Id, "Dragonforge")
			end
			T.eq(#w.prompted, before, "never prompted after the end")
			-- a count it doesn't sell: BadCount
			w.now = DURING
			local _, bad = w.act({ Capsule = "Dragonforge", Count = 5 })
			T.eq(bad.Reason, "BadCount")
			local _, junk = w.act({ Capsule = "Dragonforge", Count = 51 })
			T.eq(junk.Reason, "BadCount")
		end)
		product.Id = oldId
		CapsuleService.setReceiptsReady(false)
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("LimitedGolems: a receipt after the end is still granted, a x50 too", AFTER, function(w)
		local result, missing = CapsuleService.grantProduct(w.player, "DragonforgeCapsule3")
		T.truthy(result, "granted after the end")
		T.eq(result.Capsule, "Dragonforge")
		T.eq(#result.Golems, 3)
		T.eq(missing, 0)
		for _, golem in result.Golems do
			T.eq(GolemConfig.ById[golem.Kind].Edition, "Dragonforge", golem.Kind)
			local entry = GolemConfig.find(w.data.Golems, golem.Id)
			T.truthy(entry and entry.Paid and entry.Locked, "paid and locked")
		end
		-- x50 with 40 golems: up to MaxSaved now, the rest as the pending credit
		for _ = 1, 37 do
			GolemConfig.add(w.data.Golems, "PebbleGolem")
		end
		local big, left = CapsuleService.grantProduct(w.player, "DragonforgeCapsule50")
		T.truthy(big)
		T.eq(big.Count, 50, "all 50 rolled")
		T.eq(GolemConfig.count(w.data.Golems), GolemConfig.MaxSaved, "the inventory takes up to MaxSaved")
		T.eq(left, 50 - (GolemConfig.MaxSaved - 40), "the rest don't fit")
		-- the opening shows a card per kind
		local kinds = {}
		for _, golem in big.Golems do
			table.insert(kinds, golem.Kind)
		end
		local new = {}
		local cards, fresh, counts = CapsuleView.summary(kinds, new)
		T.truthy(#cards <= 6, "at most the six kinds")
		local total = 0
		for i, kind in cards do
			total += counts[i]
			T.falsy(fresh[i])
			if i > 1 then
				T.truthy(GolemConfig.score(cards[i - 1]) >= GolemConfig.score(kind), "rarest first")
			end
		end
		T.eq(total, #kinds, "every golem counted")
	end)
end
