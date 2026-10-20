-- Step 8 monetization under Lune: every MonetizationConfig entry has its Grant and a
-- registered handler (the receipts gate opens only then), and every grant kind with the
-- real handlers: Royal capsules (paid, locked, the stored Triple Lucky prompt state, past
-- MaxSaved a pending-golem credit that wakes when there is room, never coins), Triple /
-- Hexa Lucky (uncapped paid time), coin packs (only while CoinPacksEnabled), the Perks
-- and Mythic enchant passes (on join and on PromptGamePassPurchaseFinished, idempotent,
-- never consumed, a refund takes back only what a pass gave). For each product: the
-- first grant, the same PurchaseId again, a failed save (NotProcessedYet, then one grant
-- on the retry), the player not in this server; PurchaseLog next to Purchases; off-policy
-- receipts (restricted player, id 0, unknown id) granted or kept pending and logged; the
-- Migrations sanitizing of the new fields. Pass checks: a pass bought while its check is in
-- flight keeps the purchase, the offline perk passes go first, a check that kept failing is
-- asked again and tops up the offline payout (never for a pass bought this session).
-- Players, saves, Net and Roblox are fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs") :: any
	local Enum = roblox.Enum
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local Receipts = Loader.requirePath("ServerScriptService.Server.Receipts")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local MonetizationService = Loader.requirePath("ServerScriptService.Server.Services.MonetizationService")
	local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
	local BoostService = Loader.requirePath("ServerScriptService.Server.Services.BoostService")
	local EnchantService = Loader.requirePath("ServerScriptService.Server.Services.EnchantService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local HoverboardService = Loader.requirePath("ServerScriptService.Server.Services.HoverboardService")
	local RebirthService = Loader.requirePath("ServerScriptService.Server.Services.RebirthService")
	local ServerBoostService = Loader.requirePath("ServerScriptService.Server.Services.ServerBoostService")
	local VaultService = Loader.requirePath("ServerScriptService.Server.Services.VaultService")
	local WheelService = Loader.requirePath("ServerScriptService.Server.Services.WheelService")
	local WheelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WheelConfig")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")

	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local NOW = 1_800_000_000
	local m = MonetizationService._test
	local caps = CapsuleService._test

	local EXPECTED_GRANTS = {
		BigPass = "Perks",
		Podiums = "Perks",
		OfflineExtension = "Perks",
		TrainExpress = "Perks",
		HoverboardComet = "Hoverboard",
		HoverboardPhoenix = "Hoverboard",
		StarComet = "RebirthWeapon",
		StarNebula = "RebirthWeapon",
		StarPulsar = "RebirthWeapon",
		StarSupernova = "RebirthWeapon",
		StarSingularity = "RebirthWeapon",
		EnchantHeartfire = "Enchant",
		EnchantStarbreaker = "Enchant",
		RoyalCapsule1 = "Capsule",
		RoyalCapsule3 = "Capsule",
		RoyalCapsule10 = "Capsule",
		TripleLucky15 = "Boost",
		TripleLucky60 = "Boost",
		HexaLucky15 = "Boost",
		HexaLucky60 = "Boost",
		CoinsSmall = "CoinPack",
		CoinsMedium = "CoinPack",
		CoinsLarge = "CoinPack",
		-- the Robux STORE (owner 2026-10-20)
		RoyalCapsule5 = "Capsule",
		CoinsHuge = "CoinPack",
		CoinsMega = "CoinPack",
		BlasterNextA = "BlasterLevel",
		BlasterNextB = "BlasterLevel",
		BlasterNextC = "BlasterLevel",
		BlasterNextD = "BlasterLevel",
		ServerLuck15 = "ServerBoost",
		-- the Spin & Win wheel's bought spins (owner 2026-10-20)
		WheelSpins1 = "WheelSpins",
		WheelSpins5 = "WheelSpins",
		WheelSpins10 = "WheelSpins",
	}

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

	-- every handler the game registers in the owners' init()
	local function registerAll()
		MonetizationService.registerPerks()
		CapsuleService.registerGrants()
		BoostService.registerGrants()
		EnchantService.registerGrants()
		PodiumService.registerGrants()
		MonetizationService.registerPass("Hoverboard", { grant = HoverboardService._test.grant, revoke = HoverboardService._test.revoke })
		MonetizationService.registerPass(
			"RebirthWeapon",
			{ grant = RebirthService._test.grantWeapon, revoke = RebirthService._test.revokeWeapon }
		)
		ServerBoostService.registerGrants()
		VaultService.registerGrants()
		WheelService.registerGrants()
	end

	local function setup(): any
		local w: any = { saves = 0, saveOk = true, changed = 0, notes = {}, logs = {}, owned = {}, published = {}, prompted = {} }
		w.player = { UserId = 5150, Name = "Buyer", DisplayName = "Buyer", Parent = true, attrs = {} }
		w.player.GetAttribute = function(_, key)
			return w.player.attrs[key]
		end
		w.player.SetAttribute = function(_, key, value)
			w.player.attrs[key] = value
		end
		w.data = deepCopy(DataTemplate)
		w.loaded = true
		w.restricted = false
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player and w.loaded then w.data else nil
		end)
		patch(DataService, "changed", function(p)
			w.changed += 1
			Bonuses.invalidate(p)
		end)
		patch(DataService, "saveNow", function()
			w.saves += 1
			return w.saveOk
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(StateService, "push", function() end)
		-- every entry live, each with its own id
		w.oldIds = {}
		w.ids = {}
		local keys = {}
		for key, entry in MonetizationConfig.Entries do
			w.oldIds[key] = entry.Id
			table.insert(keys, key)
		end
		table.sort(keys)
		for i, key in keys do
			MonetizationConfig.Entries[key].Id = 90000 + i
			w.ids[key] = 90000 + i
			w.owned[90000 + i] = false
		end
		w.oldCoinPacks = MonetizationConfig.CoinPacksEnabled
		-- the handlers: exactly what the owners register
		w.oldGrants = table.clone(m.grants)
		w.oldPasses = table.clone(m.passHandlers)
		table.clear(m.grants)
		table.clear(m.passHandlers)
		registerAll()
		m.reset()
		m.setFindPlayer(function(userId)
			return if userId == w.player.UserId then w.player else nil
		end)
		-- Roblox's answers: w.owned[passId] = true / false, nil (error) or a function
		m.setOwnsGamePass(function(_userId, passId)
			local answer = w.owned[passId]
			if type(answer) == "function" then
				return answer()
			end
			if answer == nil then
				error("HTTP 500 (fake)")
			end
			return answer == true
		end)
		m.setPause(function() end)
		m.setLog(function(text)
			table.insert(w.logs, text)
		end)
		caps.reset()
		caps.setClock(function()
			return NOW
		end)
		caps.setRandom(function()
			return {
				NextNumber = function()
					return 0.5
				end,
			}
		end)
		caps.setPlayers(function()
			return { w.player }
		end)
		caps.setPushState(function() end)
		caps.setPrompter(function(p, id)
			table.insert(w.prompted, { Player = p, Id = id })
		end)
		Receipts._test.setPublisher(function(ready)
			table.insert(w.published, ready)
		end)
		BoostService._test.setClock(function()
			return NOW
		end)
		Bonuses._test.setClock(function()
			return NOW
		end)
		Policy._test.reset()
		Policy._test.setFetcher(function()
			return { ArePaidRandomItemsRestricted = w.restricted, IsPaidItemTradingAllowed = false }
		end)
		Policy.fetch(w.player)
		w.receipt = function(purchaseId: any, key: string?, userId: any?): any
			local productId = if key then w.ids[key] else 0
			return { PlayerId = userId or w.player.UserId, PurchaseId = purchaseId, ProductId = productId, CurrencySpent = 1 }
		end
		w.decide = function(purchaseId: any, key: string?, userId: any?): any
			return MonetizationService.decide(w.receipt(purchaseId, key, userId))
		end
		w.notesOf = function(name: string): { any }
			local out = {}
			for _, note in w.notes do
				if note.Name == name then
					table.insert(out, note)
				end
			end
			return out
		end
		w.loggedWith = function(text: string): number
			local n = 0
			for _, line in w.logs do
				if string.find(line, text, 1, true) then
					n += 1
				end
			end
			return n
		end
		w.restore = function()
			MonetizationConfig.CoinPacksEnabled = w.oldCoinPacks
			for key, id in w.oldIds do
				MonetizationConfig.Entries[key].Id = id
			end
			table.clear(m.grants)
			table.clear(m.passHandlers)
			for k, v in w.oldGrants do
				m.grants[k] = v
			end
			for k, v in w.oldPasses do
				m.passHandlers[k] = v
			end
			m.reset()
			caps.reset()
			Receipts._test.reset()
			BoostService._test.reset()
			HoverboardService._test.reset()
			Policy._test.reset()
			Bonuses._test.reset()
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

	--[[
		The receipt rules for one product (docs/SAVE_AUDIT.md #8): not in this
		server -> NotProcessedYet and nothing; a failed save -> NotProcessedYet
		(granted in memory, recorded); the retry -> PurchaseGranted with no
		second grant; the same PurchaseId again -> PurchaseGranted, no grant.
		`grants()` counts what the product gave so far.
	]]
	local function receiptRules(w: any, key: string, grants: () -> number, label: string)
		T.eq(w.decide(`{key}-x`, key, 999), NOT_YET, `{label}: player not in this server`)
		w.loaded = false
		T.eq(w.decide(`{key}-x`, key), NOT_YET, `{label}: save not loaded here`)
		w.loaded = true
		T.eq(grants(), 0, `{label}: nothing granted without the player's save`)
		w.saveOk = false
		T.eq(w.decide(`{key}-1`, key), NOT_YET, `{label}: the save failed`)
		T.eq(grants(), 1, `{label}: granted in memory once`)
		T.truthy(w.data.Purchases[`{key}-1`] ~= nil, `{label}: recorded with the grant`)
		T.eq(w.decide(`{key}-1`, key), NOT_YET, `{label}: still failing`)
		w.saveOk = true
		T.eq(w.decide(`{key}-1`, key), GRANTED, `{label}: the retry's save went through`)
		T.eq(grants(), 1, `{label}: the retry grants nothing more`)
		T.eq(w.decide(`{key}-1`, key), GRANTED, `{label}: the same receipt again`)
		T.eq(grants(), 1, `{label}: never granted twice`)
		local log = w.data.PurchaseLog[`{key}-1`]
		T.truthy(log ~= nil, `{label}: PurchaseLog entry`)
		T.eq(log.Product, key, `{label}: the product key is logged`)
		T.truthy(type(log.At) == "number" and log.At > 0, `{label}: and the time`)
		T.eq(w.data.PurchaseCount, 1, `{label}: counted once`)
		T.eq(w.decide(`{key}-2`, key), GRANTED, `{label}: a second purchase`)
		T.eq(grants(), 2, `{label}: a second grant`)
	end

	---------------------------------------------------------------- config and the gate

	T.test("Step 8: every entry has its Grant, and every id is still a placeholder 0", function()
		local n = 0
		for _, entry in MonetizationConfig.List do
			n += 1
			T.eq(entry.Grant, EXPECTED_GRANTS[entry.Key], `{entry.Key} Grant`)
			T.eq(entry.Id, 0, `{entry.Key}: the owner pastes the id later`)
			if entry.Grant == "Perks" then
				T.truthy(entry.Kind == "GamePass" and entry.Perks and #entry.Perks > 0, `{entry.Key}: a pass with perks`)
			elseif entry.Grant == "Enchant" then
				T.truthy(entry.Kind == "GamePass" and entry.Enchant, `{entry.Key}: a pass with an enchant`)
			elseif entry.Grant == "Hoverboard" then
				T.truthy(entry.Kind == "GamePass" and entry.BoardId, `{entry.Key}: a pass with a board`)
			elseif entry.Grant == "RebirthWeapon" then
				T.truthy(entry.Kind == "GamePass" and entry.WeaponId, `{entry.Key}: a pass with a star blaster`)
			elseif entry.Grant == "Capsule" then
				T.truthy(entry.Kind == "Product" and entry.Capsule and entry.Count, `{entry.Key}: capsules`)
			elseif entry.Grant == "Boost" then
				T.truthy(entry.Kind == "Product" and BoostConfig.Kinds[entry.Boost] and entry.Seconds, `{entry.Key}: a boost`)
			elseif entry.Grant == "CoinPack" then
				T.truthy(entry.Kind == "Product" and entry.CoinPack and entry.CoinSeconds, `{entry.Key}: a coin pack`)
			elseif entry.Grant == "BlasterLevel" then
				T.truthy(entry.Kind == "Product" and entry.MinLevel and entry.MaxLevel and entry.MinLevel <= entry.MaxLevel, `{entry.Key}: a level band`)
			elseif entry.Grant == "ServerBoost" then
				T.truthy(entry.Kind == "Product" and entry.ServerBoost and entry.Seconds and entry.PaidRandom, `{entry.Key}: a paid random server boost`)
			elseif entry.Grant == "WheelSpins" then
				T.truthy(
					entry.Kind == "Product" and entry.Spins and entry.Spins >= 1 and entry.PaidRandom,
					`{entry.Key}: paid random wheel spins`
				)
				T.truthy(string.find(entry.Description, "odds shown before buying", 1, true) ~= nil, `{entry.Key} promises the odds`)
			end
		end
		local expected = 0
		for _ in EXPECTED_GRANTS do
			expected += 1
		end
		T.eq(n, expected, "every entry checked")
	end)

	T.test("Step 8: the owners register their handlers in init()", function()
		local function initCalls(path: string, service: string, call: string)
			local source = fs.readFile(path)
			local at = string.find(source, `function {service}.init()`, 1, true)
			T.truthy(at ~= nil, `{service}.init exists`)
			local callAt = string.find(source, `\n\t{call}\n`, at, true)
			T.truthy(callAt ~= nil, `{service}.init calls {call}`)
		end
		initCalls("src/server/Services/MonetizationService.luau", "MonetizationService", "MonetizationService.registerPerks()")
		initCalls("src/server/Services/CapsuleService.luau", "CapsuleService", "CapsuleService.registerGrants()")
		initCalls("src/server/Services/BoostService.luau", "BoostService", "BoostService.registerGrants()")
		initCalls("src/server/Services/EnchantService.luau", "EnchantService", "EnchantService.registerGrants()")
		initCalls("src/server/Services/PodiumService.luau", "PodiumService", "PodiumService.registerGrants()")
		initCalls("src/server/Services/ServerBoostService.luau", "ServerBoostService", "ServerBoostService.registerGrants()")
		initCalls("src/server/Services/VaultService.luau", "VaultService", "VaultService.registerGrants()")
		initCalls("src/server/Services/WheelService.luau", "WheelService", "WheelService.registerGrants()")
		local hover = fs.readFile("src/server/Services/HoverboardService.luau")
		T.truthy(string.find(hover, 'MonetizationService.registerPass("Hoverboard"', 1, true) ~= nil, "HoverboardService registers")
		local rebirth = fs.readFile("src/server/Services/RebirthService.luau")
		T.truthy(string.find(rebirth, 'MonetizationService.registerPass("RebirthWeapon"', 1, true) ~= nil, "RebirthService registers")
	end)

	withWorld("Step 8: the receipts gate stays closed while a live id has no handler", function(w)
		T.eq(#MonetizationService.unhandled(), 0, "every live id handled after the owners registered")
		T.truthy(MonetizationService.openGate(), "the gate opens")
		T.truthy(Receipts.ready(), "Receipts.ready")
		T.eq(w.published[#w.published], true, "the clients are told")
		-- one handler missing: closed again, and that key is named
		local boost = m.grants.Boost
		m.grants.Boost = nil
		local missing = MonetizationService.unhandled()
		T.truthy(table.find(missing, "TripleLucky15") ~= nil and table.find(missing, "HexaLucky60") ~= nil, "the boosts are missing")
		T.eq(#missing, 4, "only the boosts")
		T.falsy(MonetizationService.openGate(), "closed")
		T.falsy(Receipts.ready(), "Receipts not ready")
		T.eq(w.published[#w.published], false, "the clients are told")
		T.eq(w.loggedWith("receipts stay closed"), 1, "logged")
		m.grants.Boost = boost
		-- a pass handler missing
		local perks = m.passHandlers.Perks
		m.passHandlers.Perks = nil
		T.eq(#MonetizationService.unhandled(), 4, "the four perk passes")
		T.falsy(MonetizationService.openGate(), "closed")
		m.passHandlers.Perks = perks
		-- nothing registered at all: every live id is listed
		table.clear(m.grants)
		table.clear(m.passHandlers)
		T.eq(#MonetizationService.unhandled(), #MonetizationConfig.List, "every entry listed")
		T.falsy(MonetizationService.openGate(), "closed")
		registerAll()
		T.truthy(MonetizationService.openGate(), "open again")
		-- a live coin pack while coin packs are off is reported (set here: the
		-- world restores the shipped value afterwards)
		MonetizationConfig.CoinPacksEnabled = false
		MonetizationService.openGate()
		T.truthy(w.loggedWith("CoinPacksEnabled is false") >= 3, "the coin packs are reported")
	end)

	---------------------------------------------------------------- Royal capsules

	withWorld("Step 8: Royal capsule receipts follow the receipt rules; golems paid and locked", function(w)
		receiptRules(w, "RoyalCapsule3", function()
			return GolemConfig.count(w.data.Golems) // 3
		end, "RoyalCapsule3")
		for _, golem in w.data.Golems.Owned do
			T.eq(golem.Paid, true, "paid")
			T.eq(golem.Locked, true, "locked")
		end
		T.eq(#w.notesOf("CapsuleResult"), 2, "a CapsuleResult per grant")
		T.eq(w.data.Coins, DataTemplate.Coins, "no coins")
		T.eq(w.loggedWith("off policy"), 0, "nothing off policy")
	end)

	withWorld("Step 8: a Royal capsule uses the Triple Lucky state stored at 'Prompted'", function(w)
		Receipts.setReady(true)
		-- prompted while Triple Lucky runs; the boost ends before the receipt
		w.data.Boosts.TripleLuckyUntil = NOW + 60
		Bonuses.invalidate(w.player)
		caps.action(w.player, "Open", { Capsule = "Royal", Count = 1 })
		T.eq(#w.prompted, 1, "prompted")
		T.eq(w.prompted[1].Id, w.ids.RoyalCapsule1, "the live product id")
		T.eq(CapsuleService.promptedLucky(w.player, "RoyalCapsule1"), true, "stored with Triple Lucky")
		w.data.Boosts.TripleLuckyUntil = NOW - 100
		Bonuses.invalidate(w.player)
		T.eq(w.decide("r1", "RoyalCapsule1"), GRANTED, "granted")
		local results = w.notesOf("CapsuleResult")
		T.eq(results[#results].A.Lucky, true, "the stored Triple Lucky odds, although the boost ended")
		T.eq(CapsuleService.promptedLucky(w.player, "RoyalCapsule1"), nil, "the prompt is used up")
		-- no stored prompt (the Store tab, another server): the state at the receipt
		T.eq(w.decide("r2", "RoyalCapsule1"), GRANTED, "granted")
		results = w.notesOf("CapsuleResult")
		T.eq(results[#results].A.Lucky, false, "no prompt, no boost: normal odds")
		w.data.Boosts.TripleLuckyUntil = NOW + 600
		Bonuses.invalidate(w.player)
		T.eq(w.decide("r3", "RoyalCapsule1"), GRANTED, "granted")
		results = w.notesOf("CapsuleResult")
		T.eq(results[#results].A.Lucky, true, "no prompt, the boost runs: Triple Lucky")
		-- a client that prompted the product itself (no server prompt) changes nothing
		T.eq(GolemConfig.count(w.data.Golems), 3, "three golems")
	end)

	withWorld("Step 8: golems past MaxSaved wait as a pending credit (never coins) and wake when there is room", function(w)
		for i = 1, GolemConfig.MaxSaved - 1 do
			GolemConfig.add(w.data.Golems, "PebbleGolem", true)
		end
		local coins = w.data.Coins
		T.eq(w.decide("c1", "RoyalCapsule10"), GRANTED, "granted")
		T.eq(GolemConfig.count(w.data.Golems), GolemConfig.MaxSaved, "filled up to MaxSaved")
		T.eq(#w.data.Golems.Pending, 9, "nine golems wait")
		for _, entry in w.data.Golems.Pending do
			T.truthy(GolemConfig.ById[entry.Kind] ~= nil, "a rolled kind")
			T.eq(entry.Paid, true, "paid")
		end
		T.eq(w.data.Coins, coins, "never paid out as coins")
		T.eq(w.data.PurchaseLog.c1.Product, "RoyalCapsule10", "logged")
		-- room appears: the oldest pending golems wake, paid and locked
		for i = 1, 4 do
			table.remove(w.data.Golems.Owned, 1)
		end
		T.eq(CapsuleService.wakePending(w.player), 4, "four woke")
		T.eq(#w.data.Golems.Pending, 5, "five still wait")
		T.eq(GolemConfig.count(w.data.Golems), GolemConfig.MaxSaved, "full again")
		local last = w.data.Golems.Owned[#w.data.Golems.Owned]
		T.eq(last.Paid, true, "woken golems are paid")
		T.eq(last.Locked, true, "and locked")
		T.eq(CapsuleService.wakePending(w.player), 0, "no room: nothing")
		table.clear(w.data.Golems.Owned)
		T.eq(CapsuleService.wakePending(w.player), 5, "the rest woke")
		T.eq(#w.data.Golems.Pending, 0, "the credit is used up")
		-- an unknown kind (a newer build's) keeps waiting
		table.insert(w.data.Golems.Pending, { Kind = "VoidGolem", Paid = true })
		T.eq(CapsuleService.wakePending(w.player), 0, "unknown kind: waits")
		T.eq(#w.data.Golems.Pending, 1, "still there")
	end)

	withWorld("Step 8: a Royal receipt waits (nothing written) when even the pending credit is full", function(w)
		for i = 1, GolemConfig.MaxSaved do
			GolemConfig.add(w.data.Golems, "PebbleGolem", true)
		end
		w.data.Golems.Pending = {}
		for i = 1, GolemConfig.MaxPending - 2 do
			table.insert(w.data.Golems.Pending, { Kind = "PebbleGolem", Paid = true })
		end
		T.eq(w.decide("f1", "RoyalCapsule3"), NOT_YET, "no room for 3: the receipt waits")
		T.eq(#w.data.Golems.Pending, GolemConfig.MaxPending - 2, "nothing written")
		T.eq(w.data.Purchases.f1, nil, "not recorded")
		T.eq(w.loggedWith("can't take RoyalCapsule3"), 1, "logged")
		T.eq(w.decide("f2", "RoyalCapsule1"), GRANTED, "one still fits")
		T.eq(#w.data.Golems.Pending, GolemConfig.MaxPending - 1, "into the credit")
	end)

	withWorld("Step 8: a paid random product for a restricted player is granted and logged", function(w)
		Policy._test.reset()
		w.restricted = true
		Policy._test.setFetcher(function()
			return { ArePaidRandomItemsRestricted = true, IsPaidItemTradingAllowed = false }
		end)
		Policy.fetch(w.player)
		T.eq(w.decide("p1", "RoyalCapsule1"), GRANTED, "granted all the same")
		T.eq(GolemConfig.count(w.data.Golems), 1, "the golem")
		T.eq(w.decide("p2", "HexaLucky15"), GRANTED, "a luck boost too")
		T.eq(w.loggedWith("paid random item"), 2, "both logged")
		T.eq(
			w.loggedWith(`player {w.player.UserId}, product {w.ids.RoyalCapsule1}, purchase p1`),
			1,
			"with player, product and purchase id"
		)
		T.eq(w.decide("p1", "RoyalCapsule1"), GRANTED, "the same receipt again")
		T.eq(w.loggedWith("paid random item"), 2, "logged once")
	end)

	---------------------------------------------------------------- luck boosts

	withWorld("Step 8: Triple / Hexa Lucky receipts follow the receipt rules and add uncapped time", function(w)
		receiptRules(w, "TripleLucky15", function()
			return math.max(0, BoostConfig.untilOf(w.data.Boosts, "TripleLucky") - NOW) // 900
		end, "TripleLucky15")
		-- far past MaxStackSeconds: paid time is never cut
		w.data.Boosts.HexaLuckyUntil = NOW + BoostConfig.MaxStackSeconds
		T.eq(w.decide("h1", "HexaLucky60"), GRANTED, "granted at the cap")
		T.eq(BoostConfig.untilOf(w.data.Boosts, "HexaLucky"), NOW + BoostConfig.MaxStackSeconds + 3600, "uncapped")
		T.eq(w.decide("h2", "HexaLucky60"), GRANTED, "again")
		T.eq(BoostConfig.untilOf(w.data.Boosts, "HexaLucky"), NOW + BoostConfig.MaxStackSeconds + 7200, "still uncapped")
		T.eq(BoostConfig.untilOf(w.data.Boosts, "TripleLucky"), NOW + 2 * 900, "the other boost untouched")
		-- the time survives a load (Migrations clips only past MaxSavedSeconds)
		Migrations.run(w.data, NOW)
		T.eq(BoostConfig.untilOf(w.data.Boosts, "HexaLucky"), NOW + BoostConfig.MaxStackSeconds + 7200, "kept on load")
	end)

	---------------------------------------------------------------- Spin & Win spins

	withWorld("Step 8: wheel spin receipts bank the spins once (never a spin inside the receipt)", function(w)
		receiptRules(w, "WheelSpins5", function()
			return WheelConfig.heldSpins(w.data.Wheel) // 5
		end, "WheelSpins5")
		T.eq(w.data.Wheel.Spins, 10, "two receipts: 10 spins banked")
		T.eq(#w.notesOf("Notify"), 2, "a thank-you per grant")
		T.eq(#w.notesOf("WheelResult"), 0, "nothing spun inside ProcessReceipt")
		T.eq(w.data.Stats.WheelSpins, 0, "no spin counted")
		T.eq(w.data.Wheel.NextSpinAt, DataTemplate.Wheel.NextSpinAt, "the free spin untouched")
		-- the same PurchaseId again: never doubled
		T.eq(w.decide("WheelSpins5-1", "WheelSpins5"), GRANTED, "a duplicate receipt")
		T.eq(w.data.Wheel.Spins, 10, "not doubled")
		-- past MaxSpins a receipt still credits all of them (only the prompt says Full)
		w.data.Wheel.Spins = WheelConfig.MaxSpins
		T.eq(w.decide("big-1", "WheelSpins10"), GRANTED, "never refused")
		T.eq(w.data.Wheel.Spins, WheelConfig.MaxSpins + 10, "never cut")
		-- bought spins survive a rejoin: the saved record loads with them (Migrations + reconcile)
		local saved = ProfileStore.deepCopy(w.data)
		Migrations.run(saved, NOW + 86400)
		ProfileStore.reconcile(saved, DataTemplate)
		T.eq(saved.Wheel.Spins, WheelConfig.MaxSpins + 10, "kept on the next load")
		T.eq(w.loggedWith("off policy"), 0, "nothing off policy")
	end)

	withWorld("Step 8: a wheel spin receipt for a restricted player is credited and logged", function(w)
		Policy._test.reset()
		w.restricted = true
		Policy._test.setFetcher(function()
			return { ArePaidRandomItemsRestricted = true, IsPaidItemTradingAllowed = false }
		end)
		Policy.fetch(w.player)
		T.eq(w.decide("s1", "WheelSpins1"), GRANTED, "granted all the same")
		T.eq(w.data.Wheel.Spins, 1, "banked (they can't spin it there: WheelService)")
		T.eq(w.loggedWith("paid random item"), 1, "logged")
	end)

	---------------------------------------------------------------- coin packs

	withWorld("Step 8: coin packs wait while CoinPacksEnabled is false, then follow the receipt rules", function(w)
		MonetizationConfig.CoinPacksEnabled = false
		w.data.Coins += 777 -- earned coins: never counted as bought
		local coins = w.data.Coins
		T.eq(w.decide("k1", "CoinsSmall"), NOT_YET, "coin packs off: the receipt waits (never dropped)")
		T.eq(w.data.Coins, coins, "no coins")
		T.eq(w.data.Purchases.k1, nil, "not recorded")
		T.eq(w.loggedWith("can't take CoinsSmall"), 1, "logged")
		T.eq(w.decide("k1", "CoinsSmall"), NOT_YET, "again")
		T.eq(w.loggedWith("can't take CoinsSmall"), 1, "logged once")
		MonetizationConfig.CoinPacksEnabled = true
		local each = MonetizationConfig.coinPackAmount("CoinsMedium", 0)
		T.eq(each, 10000, "no income: the minimum")
		receiptRules(w, "CoinsMedium", function()
			return math.floor((w.data.Coins - coins) / each + 0.5)
		end, "CoinsMedium")
		T.eq(w.decide("k1", "CoinsSmall"), GRANTED, "the waiting receipt is granted once coin packs are on")
		T.eq(w.data.Coins - coins, 2 * each + 2500, "its coins")
		-- bought coins are counted in PaidCoins (kept through a rebirth while unspent)
		T.eq(w.data.PaidCoins, 2 * each + 2500, "only the bought coins are counted")
	end)

	---------------------------------------------------------------- off policy: ids

	withWorld("Step 8: receipts no live entry matches are kept pending and logged once", function(w)
		T.eq(w.decide("z1", nil), NOT_YET, "product id 0")
		T.eq(MonetizationService.decide({ PlayerId = w.player.UserId, PurchaseId = "z2", ProductId = 424242 }), NOT_YET, "unknown id")
		T.eq(w.loggedWith("purchase z1"), 1, "id 0 logged")
		T.eq(w.loggedWith("product 424242, purchase z2"), 1, "unknown id logged with the product id")
		T.eq(w.loggedWith(`player {w.player.UserId}`), 2, "with the player id")
		T.eq(w.decide("z1", nil), NOT_YET, "delivered again")
		T.eq(w.loggedWith("purchase z1"), 1, "logged once per purchase")
		T.eq(w.data.Purchases.z1, nil, "never acknowledged without the item")
		-- the owner pastes the id: the next delivery is granted
		T.eq(
			MonetizationService.decide({ PlayerId = w.player.UserId, PurchaseId = "z2", ProductId = w.ids.TripleLucky60 }),
			GRANTED,
			"granted"
		)
		-- a pass id sent as a receipt is no product
		T.eq(w.decide("z3", "BigPass"), NOT_YET, "a game pass id")
		T.eq(w.player.attrs.Perk_Podiums, nil, "no perk from a receipt")
	end)

	---------------------------------------------------------------- the Perks passes

	withWorld("Step 8: Perks passes grant on join and on purchase, idempotent, never consumed", function(w)
		w.owned[w.ids.BigPass] = true
		m.checkAll(w.player)
		for _, perk in MonetizationConfig.Entries.BigPass.Perks do
			T.eq(w.player.attrs["Perk_" .. perk], true, `{perk} from the big pass`)
		end
		T.eq(w.player.attrs.Perk_TrainExpress, nil, "not the train")
		T.truthy(MonetizationService.passesChecked(w.player), "the load's checks are done")
		local changes = w.changed
		m.checkAll(w.player)
		T.eq(w.changed, changes, "the next load changes nothing")
		-- bought in game
		m.purchaseFinished(w.player, w.ids.TrainExpress, false)
		T.eq(w.player.attrs.Perk_TrainExpress, nil, "not bought: nothing")
		m.purchaseFinished(w.player, w.ids.TrainExpress, true)
		T.eq(w.player.attrs.Perk_TrainExpress, true, "bought: the perk")
		changes = w.changed
		m.purchaseFinished(w.player, w.ids.TrainExpress, true)
		T.eq(w.changed, changes, "a second signal changes nothing")
		-- never consumed: still there after many loads and receipts
		w.owned[w.ids.TrainExpress] = true
		m.checkAll(w.player)
		T.eq(w.player.attrs.Perk_TrainExpress, true, "kept")
		T.eq(w.player.attrs.Perk_Podiums, true, "kept")
	end)

	withWorld("Step 8: a refunded Perks pass takes back only the perks no other owned pass gives", function(w)
		w.owned[w.ids.BigPass] = true
		w.owned[w.ids.Podiums] = true
		m.checkAll(w.player)
		T.eq(w.player.attrs.Perk_Podiums, true, "both give Podiums")
		w.owned[w.ids.Podiums] = false
		m.checkAll(w.player)
		T.eq(w.player.attrs.Perk_Podiums, true, "the big pass still gives it")
		w.owned[w.ids.BigPass] = false
		m.checkAll(w.player)
		T.eq(w.player.attrs.Perk_Podiums, nil, "gone with both passes")
		T.eq(w.player.attrs.Perk_StrongBack, nil, "the big pass's perks are gone")
		-- a check that keeps failing changes nothing
		m.purchaseFinished(w.player, w.ids.OfflineExtension, true)
		w.owned[w.ids.OfflineExtension] = nil
		m.checkAll(w.player)
		T.eq(w.player.attrs.Perk_OfflineExtension, true, "a failed check never revokes")
	end)

	withWorld("Step 8: the offline payout waits for the pass checks (Night Shift)", function(w)
		local podium = PodiumService._test
		local known: boolean? = nil
		local oldWait = PodiumService.PassWait
		PodiumService.PassWait = 0 -- (the fallback runs at once, after the test)
		podium.setPerkAtJoin(function()
			return known
		end)
		podium.setClock(function()
			return NOW
		end)
		local ok, err = pcall(function()
			w.data.LastSeen = NOW - 20 * 3600
			podium.loaded(w.player, w.data)
			T.truthy(podium.pending(w.player) ~= nil, "offline time waits")
			podium.offlineDue(w.player)
			T.truthy(podium.waiting(w.player), "the checks aren't done: it waits")
			T.truthy(podium.pending(w.player) ~= nil, "not paid yet")
			-- the checks finish (Night Shift owned): paid now, with the perk
			w.player.attrs.Perk_OfflineExtension = true
			known = true
			podium.passesChecked(w.player)
			T.falsy(podium.waiting(w.player), "done waiting")
			T.eq(podium.pending(w.player), nil, "paid")
			T.falsy(podium.hasTopUp(w.player), "every answer was in: nothing to top up")
			podium.passesChecked(w.player)
			T.eq(podium.pending(w.player), nil, "a second signal pays nothing")
			-- checks already done at OfflineDelay: paid at once
			known = true
			w.data.LastSeen = NOW - 3600
			podium.loaded(w.player, w.data)
			podium.offlineDue(w.player)
			T.falsy(podium.waiting(w.player), "no wait")
			T.eq(podium.pending(w.player), nil, "paid at once")
		end)
		podium.reset()
		PodiumService.PassWait = oldWait
		if not ok then
			error(err, 0)
		end
	end)

	---------------------------------------------------------------- the Mythic enchant passes

	withWorld("Step 8: Enchant passes grant the Mythic forever, idempotent; a refund takes back only the pass's", function(w)
		w.owned[w.ids.EnchantHeartfire] = true
		m.checkAll(w.player)
		T.eq(w.data.Enchants.Owned.Heartfire, 1, "owned")
		T.eq(w.data.Enchants.Passes.Heartfire, true, "marked as the pass's")
		T.eq(w.data.Enchants.Slots[1], "Heartfire", "slotted")
		local changes = w.changed
		m.checkAll(w.player)
		m.purchaseFinished(w.player, w.ids.EnchantHeartfire, true)
		T.eq(w.changed, changes, "idempotent on every load and signal")
		T.eq(w.data.Enchants.Owned.Heartfire, 1, "still tier 1")
		-- Starbreaker bought with coins before: the pass never marks (nor takes) it
		w.data.Enchants.Owned.Starbreaker = 1
		m.purchaseFinished(w.player, w.ids.EnchantStarbreaker, true)
		T.eq(w.data.Enchants.Passes.Starbreaker, nil, "not the pass's")
		w.owned[w.ids.EnchantStarbreaker] = false
		w.owned[w.ids.EnchantHeartfire] = false
		m.checkAll(w.player)
		T.eq(w.data.Enchants.Owned.Starbreaker, 1, "the coin-bought one stays")
		T.eq(w.data.Enchants.Owned.Heartfire, 1, "bought this session: a 'not owned' answer can't take it")
		-- the next session (PlayerRemoving dropped the session's answers): the refund shows
		m.forget(w.player)
		m.checkAll(w.player)
		T.eq(w.data.Enchants.Owned.Starbreaker, 1, "the coin-bought one still stays")
		T.eq(w.data.Enchants.Owned.Heartfire, nil, "the refunded pass's enchant is taken back")
		T.eq(w.data.Enchants.Slots[1], "", "and its slot emptied")
		T.eq(w.data.Enchants.Passes.Heartfire, nil, "mark cleared")
		-- bought in game
		m.purchaseFinished(w.player, w.ids.EnchantHeartfire, true)
		T.eq(w.data.Enchants.Owned.Heartfire, 1, "bought: owned again")
		T.eq(#w.notesOf("Notify") > 0, true, "the player is thanked")
		-- the save keeps it all through Migrations
		local before = deepCopy(w.data.Enchants)
		Migrations.run(w.data, NOW)
		T.eq(w.data.Enchants.Passes.Heartfire, before.Passes.Heartfire, "the mark survives a load")
	end)

	---------------------------------------------------------------- pass check timing

	withWorld("Step 8: a pass bought while its check is in flight keeps the purchase (Roblox's stale 'not owned')", function(w)
		for _, key in { "EnchantHeartfire", "TrainExpress" } do
			local id = w.ids[key]
			w.owned[id] = function()
				-- bought while Roblox works on the check, which answers from before the purchase
				m.purchaseFinished(w.player, id, true)
				return false
			end
		end
		m.checkAll(w.player)
		T.eq(w.data.Enchants.Owned.Heartfire, 1, "the Mythic stays")
		T.eq(w.data.Enchants.Passes.Heartfire, true, "marked as the pass's")
		T.eq(w.data.Enchants.Slots[1], "Heartfire", "still slotted")
		T.truthy(MonetizationService.owns(w.player, "EnchantHeartfire"), "owned this session")
		T.eq(w.player.attrs.Perk_TrainExpress, true, "the perk stays")
		T.truthy(MonetizationService.owns(w.player, "TrainExpress"), "owned this session")
		T.eq(MonetizationService.perkAtJoin(w.player, "TrainExpress"), false, "bought now: not owned at join")
		-- a later check in this session (a cached answer) takes nothing either
		w.owned[w.ids.EnchantHeartfire] = false
		w.owned[w.ids.TrainExpress] = false
		m.checkAll(w.player)
		T.eq(w.data.Enchants.Owned.Heartfire, 1, "kept for the session")
		T.eq(w.player.attrs.Perk_TrainExpress, true, "kept for the session")
		-- the next session: Roblox's "not owned" is a refund
		m.forget(w.player)
		m.checkAll(w.player)
		T.eq(w.data.Enchants.Owned.Heartfire, nil, "refunded: taken back on the next load")
		T.eq(w.player.attrs.Perk_TrainExpress, nil, "refunded: the perk is gone")
	end)

	withWorld("Step 8: the passes giving the offline perks are checked first", function(w)
		local keyOf = {}
		for key, id in w.ids do
			keyOf[id] = key
		end
		local order = {}
		m.setOwnsGamePass(function(_userId, passId)
			table.insert(order, keyOf[passId])
			return false
		end)
		m.checkAll(w.player)
		T.eq(#order, #MonetizationConfig.list("GamePass"), "every live pass once")
		T.eq(order[1], "BigPass", "the big pass first")
		T.eq(order[2], "OfflineExtension", "then Night Shift")
		T.eq(order[3], "Podiums", "then the Podiums pass")
		T.eq(order[4], "EnchantHeartfire", "then the rest by key")
		T.eq(MonetizationService.perkAtJoin(w.player, "OfflineExtension"), false, "known: not owned")
	end)

	-- One join with podium income, 20 h away, Night Shift's (and the Podiums pass's) check failing in the
	-- load round. `inRound` runs after the load round (base paid); then the re-check answers `owned`.
	local function lateNightShift(w: any, owned: boolean, inRound: (() -> ())?): any
		local podium = PodiumService._test
		local r: any = {}
		podium.setClock(function()
			return NOW
		end)
		w.data.Podiums = { "Clean|Gold|Pristine|", "", "Clean|Gold|Pristine|", "" }
		r.income = PodiumService.incomeOf(w.player, w.data)
		w.player.attrs.Perk_Podiums = true
		r.incomeAll = PodiumService.incomeOf(w.player, w.data)
		w.player.attrs.Perk_Podiums = nil
		T.truthy(r.income > 0 and r.incomeAll > r.income, "podium 3 counts only with the Podiums perk")
		r.coins = w.data.Coins
		w.data.LastSeen = NOW - 20 * 3600
		podium.loaded(w.player, w.data)
		podium.offlineDue(w.player)
		T.truthy(podium.waiting(w.player), "no answers yet: the payout waits")
		local outage = true
		for _, key in { "OfflineExtension", "Podiums" } do
			w.owned[w.ids[key]] = function()
				if outage then
					error("HTTP 503 (fake)")
				end
				return owned
			end
		end
		m.setPause(function(seconds)
			if seconds == MonetizationService.RecheckDelay and outage then
				-- the load round is done (its onPassesChecked): the base payout goes now
				T.eq(MonetizationService.perkAtJoin(w.player, "OfflineExtension"), nil, "Night Shift not known")
				podium.passesChecked(w.player)
				T.falsy(podium.waiting(w.player), "paid after the load round")
				T.eq(podium.pending(w.player), nil, "paid")
				r.base = w.data.Coins - r.coins
				T.truthy(podium.hasTopUp(w.player), "the rest waits for a later answer")
				if inRound then
					inRound()
				end
				outage = false
			end
		end)
		m.checkAll(w.player)
		-- the re-check answered (its onPassesChecked)
		podium.passesChecked(w.player)
		r.total = w.data.Coins - r.coins
		return r
	end

	withWorld("Step 8: Night Shift's check failing at join: the base payout now, the difference once a re-check says owned", function(w)
		local podium = PodiumService._test
		local ok, err = pcall(function()
			local o = EconomyConfig.Offline
			local r = lateNightShift(w, true)
			local base = r.income * o.Rate * o.BaseHours * 3600
			local full = r.incomeAll * o.Rate * o.ExtendedHours * 3600
			T.near(r.base, base, base * 1e-9, "the base: 5 h, podiums 1-2")
			T.eq(w.player.attrs.Perk_OfflineExtension, true, "the re-check granted Night Shift")
			T.eq(MonetizationService.perkAtJoin(w.player, "OfflineExtension"), true, "owned at join")
			T.near(r.total, full, full * 1e-9, "the absence counted with 12 h and podiums 3-4")
			T.falsy(podium.hasTopUp(w.player), "done")
			T.near(w.data.Stats.PodiumEarned, full, full * 1e-9, "counted as podium money")
			local toasts = 0
			for _, note in w.notesOf("Notify") do
				if string.find(note.A.Text, "time away", 1, true) then
					toasts += 1
				end
			end
			T.eq(toasts, 1, "the player is told once")
			podium.passesChecked(w.player)
			T.eq(podium.topUp(w.player), 0, "never twice")
			T.near(w.data.Coins - r.coins, full, full * 1e-9, "nothing more")
		end)
		podium.reset()
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("Step 8: no top-up when the late answer is 'not owned', or for Night Shift bought this session", function(w)
		local podium = PodiumService._test
		local ok, err = pcall(function()
			local r = lateNightShift(w, false)
			T.near(r.total, r.base, 1e-6, "not owned: the base stays")
			T.falsy(podium.hasTopUp(w.player), "settled")
			podium.reset()
			m.forget(w.player)
			w.player.attrs = {}
			-- bought in game after the base payout: Roblox now says owned, but it wasn't at join
			local id = w.ids.OfflineExtension
			r = lateNightShift(w, true, function()
				m.purchaseFinished(w.player, id, true)
			end)
			T.eq(w.player.attrs.Perk_OfflineExtension, true, "the bought perk")
			T.eq(MonetizationService.perkAtJoin(w.player, "OfflineExtension"), false, "not owned at join")
			T.eq(w.player.attrs.Perk_Podiums, true, "the Podiums pass the re-check found")
			local o = EconomyConfig.Offline
			local expected = r.incomeAll * o.Rate * o.BaseHours * 3600
			T.near(r.total, expected, expected * 1e-9, "podiums 3-4 count, the bought Night Shift doesn't")
			T.falsy(podium.hasTopUp(w.player), "settled")
		end)
		podium.reset()
		if not ok then
			error(err, 0)
		end
	end)

	---------------------------------------------------------------- Migrations

	T.test("Step 8: Migrations sanitize PurchaseLog, Golems.Pending and Enchants.Passes (idempotent)", function()
		local data = deepCopy(DataTemplate)
		data.Purchases = { a = NOW, b = NOW, ["7"] = NOW }
		data.PurchaseLog = {
			a = { Product = "RoyalCapsule3", At = NOW, Note = "kept" },
			b = { Product = 5, At = NOW },
			c = { Product = "TripleLucky15", At = NOW }, -- trimmed from Purchases
			["7"] = { Product = "HexaLucky60", At = -1 },
			d = "junk",
		}
		data.Golems.Pending = {
			{ Kind = "PebbleGolem", Paid = true },
			{ Kind = "VoidGolem" },
			{ Kind = "", Paid = true },
			{ Kind = "PebbleGolem", Paid = "yes" },
			"junk",
		}
		data.Enchants =
			{ Owned = { Heartfire = 1 }, Slots = { "", "", "", "" }, Passes = { Heartfire = true, Starbreaker = true, [3] = true } }
		Migrations.run(data, NOW)
		T.eq(data.PurchaseLog.a.Product, "RoyalCapsule3", "well-formed kept")
		T.eq(data.PurchaseLog.a.Note, "kept", "a newer build's field stays")
		T.eq(data.PurchaseLog.b, nil, "junk product")
		T.eq(data.PurchaseLog.c, nil, "not in Purchases any more")
		T.eq(data.PurchaseLog["7"], nil, "negative time")
		T.eq(data.PurchaseLog.d, nil, "junk entry")
		T.eq(#data.Golems.Pending, 2, "two well-formed pending golems")
		T.eq(data.Golems.Pending[2].Kind, "VoidGolem", "unknown kinds kept")
		T.eq(data.Enchants.Passes.Heartfire, true, "owned and marked")
		T.eq(data.Enchants.Passes.Starbreaker, nil, "not owned: dropped")
		T.eq(data.Enchants.Passes[3], nil, "junk key dropped")
		local before = deepCopy(data)
		local report = Migrations.run(data, NOW)
		T.eq(report.Dropped + report.Moved, 0, "idempotent")
		T.eq(#data.Golems.Pending, #before.Golems.Pending, "unchanged")
		-- junk records
		data.PurchaseLog = 5
		data.Golems.Pending = "x"
		data.Enchants.Passes = 7
		Migrations.run(data, NOW)
		T.eq(type(data.PurchaseLog), "table", "PurchaseLog repaired")
		T.eq(type(data.Golems.Pending), "table", "Pending repaired")
		T.eq(type(data.Enchants.Passes), "table", "Passes repaired")
		-- a save without the new fields gets none added by Migrations
		local old = deepCopy(DataTemplate)
		old.Golems = { Owned = {}, Equipped = {}, NextId = 1 }
		old.Enchants = { Owned = {}, Slots = { "", "", "", "" } }
		Migrations.run(old, NOW)
		T.eq(old.Golems.Pending, nil, "no Pending added")
		T.eq(old.Enchants.Passes, nil, "no Passes added")
	end)
end
