-- MonetizationService (the one ProcessReceipt) under Lune: NotProcessedYet without the
-- player or their save on this server, idempotent by PurchaseId, the save goes through
-- before PurchaseGranted (a failed save is retried, never granted twice), unknown / id 0
-- products, a receipt decided twice at once, and the hoverboard grant handler.
-- Players, saves and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Enum = roblox.Enum
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local MonetizationService = Loader.requirePath("ServerScriptService.Server.Services.MonetizationService")
	local HoverboardService = Loader.requirePath("ServerScriptService.Server.Services.HoverboardService")

	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local m = MonetizationService._test

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

	local function setup(): any
		local w: any = { granted = 0, saves = 0, saveOk = true, changed = 0, notes = {} }
		w.player = { UserId = 4242, Name = "Payer", Parent = true, attrs = {} }
		w.player.GetAttribute = function(_, key)
			return w.player.attrs[key]
		end
		w.player.SetAttribute = function(_, key, value)
			w.player.attrs[key] = value
		end
		w.data = deepCopy(DataTemplate)
		w.loaded = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player and w.loaded then w.data else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(DataService, "saveNow", function()
			w.saves += 1
			return w.saveOk
		end)
		patch(Net, "fire", function(name, p, a)
			table.insert(w.notes, { Name = name, A = a })
		end)
		patch(StateService, "push", function() end)
		-- give both hoverboard products a real id for the test
		w.oldIds = {}
		for key, product in MonetizationConfig.Products do
			w.oldIds[key] = product.Id
		end
		MonetizationConfig.Products.HoverboardComet.Id = 1001
		MonetizationConfig.Products.HoverboardPhoenix.Id = 1002
		m.reset()
		m.setFindPlayer(function(userId)
			return if userId == w.player.UserId then w.player else nil
		end)
		w.oldGrant = m.grants.Hoverboard
		w.oldTest = m.grants.Test
		MonetizationService.register("Hoverboard", function(player, data, product)
			w.granted += 1
			w.lastProduct = product
			return w.grantOk ~= false
		end)
		w.receipt = function(purchaseId: any, productId: any, userId: any?): any
			return { PlayerId = userId or w.player.UserId, PurchaseId = purchaseId, ProductId = productId, CurrencySpent = 49 }
		end
		w.restore = function()
			m.grants.Hoverboard = w.oldGrant
			m.grants.Test = w.oldTest
			for key, id in w.oldIds do
				MonetizationConfig.Products[key].Id = id
			end
			m.reset()
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

	withWorld("receipts: NotProcessedYet when the player or their save isn't on this server", function(w)
		T.eq(MonetizationService.decide(w.receipt("a1", 1001, 999)), NOT_YET, "player not in this server")
		w.loaded = false
		T.eq(MonetizationService.decide(w.receipt("a1", 1001)), NOT_YET, "save not loaded here (no session lock)")
		T.eq(w.granted, 0, "nothing granted")
		T.eq(w.data.Purchases.a1, nil, "nothing recorded")
		w.loaded = true
		T.eq(MonetizationService.decide(w.receipt("a1", 1001)), GRANTED, "granted once the save is here")
		T.eq(w.granted, 1, "granted once")
	end)

	withWorld("receipts: granted once per PurchaseId, recorded and saved before PurchaseGranted", function(w)
		T.eq(MonetizationService.decide(w.receipt("p1", 1001)), GRANTED, "first call")
		T.eq(w.granted, 1, "granted")
		T.truthy(w.data.Purchases.p1 ~= nil, "PurchaseId recorded")
		T.eq(w.data.PurchaseCount, 1, "PurchaseCount")
		T.eq(w.saves, 1, "saved before answering")
		T.truthy(w.changed >= 1, "DataService.changed")
		T.eq(MonetizationService.decide(w.receipt("p1", 1001)), GRANTED, "the same receipt again")
		T.eq(w.granted, 1, "never granted twice")
		T.eq(w.data.PurchaseCount, 1, "counted once")
		T.eq(MonetizationService.decide(w.receipt(12345, 1002)), GRANTED, "numeric purchase ids work")
		T.eq(w.lastProduct.Key, "HoverboardPhoenix", "the product of the receipt's id")
		T.truthy(w.data.Purchases["12345"] ~= nil, "numeric id stored as text")
		T.eq(MonetizationService.decide(w.receipt(12345, 1002)), GRANTED, "again")
		T.eq(w.granted, 2, "two different purchases, two grants")
	end)

	withWorld("receipts: a failed save is retried, PurchaseGranted only after it went through", function(w)
		w.saveOk = false
		T.eq(MonetizationService.decide(w.receipt("s1", 1001)), NOT_YET, "save failed")
		T.eq(w.granted, 1, "granted in memory")
		T.truthy(w.data.Purchases.s1 ~= nil, "id recorded with the grant")
		T.truthy(m.isUnsaved("s1"), "remembered as not saved")
		T.eq(MonetizationService.decide(w.receipt("s1", 1001)), NOT_YET, "still failing")
		T.eq(w.granted, 1, "no second grant while retrying")
		w.saveOk = true
		T.eq(MonetizationService.decide(w.receipt("s1", 1001)), GRANTED, "the save went through")
		T.eq(w.granted, 1, "still one grant")
		T.falsy(m.isUnsaved("s1"), "saved")
		T.eq(w.data.PurchaseCount, 1, "counted once")
	end)

	withWorld("receipts: unknown products, id 0, refusing handlers and junk are never granted", function(w)
		T.eq(MonetizationService.decide(w.receipt("u1", 5555)), NOT_YET, "unknown product id")
		T.eq(MonetizationService.decide(w.receipt("u2", 0)), NOT_YET, "id 0 never matches")
		T.eq(MonetizationService.decide(nil), NOT_YET, "nil receipt")
		T.eq(MonetizationService.decide({}), NOT_YET, "empty receipt")
		T.eq(MonetizationService.decide(w.receipt(nil, 1001)), NOT_YET, "no purchase id")
		T.eq(MonetizationService.decide(w.receipt("u3", 1001, "4242")), NOT_YET, "a string player id")
		T.eq(w.granted, 0, "nothing granted")
		w.grantOk = false
		T.eq(MonetizationService.decide(w.receipt("u4", 1001)), NOT_YET, "the handler refused")
		T.eq(w.data.Purchases.u4, nil, "a refused grant is not recorded")
		T.eq(w.saves, 0, "nothing saved")
		-- with the real config ids back to 0, no hoverboard product can match
		MonetizationConfig.Products.HoverboardComet.Id = 0
		w.grantOk = true
		T.eq(MonetizationService.decide(w.receipt("u5", 1001)), NOT_YET, "a product without an id")
	end)

	withWorld("receipts: the same PurchaseId decided twice at once waits", function(w)
		m.setInFlight("f1", true)
		T.eq(MonetizationService.decide(w.receipt("f1", 1001)), NOT_YET, "in flight")
		T.eq(w.granted, 0, "not granted while the first call runs")
		m.setInFlight("f1", false)
		T.eq(MonetizationService.decide(w.receipt("f1", 1001)), GRANTED, "then granted")
	end)

	withWorld("receipts: the hoverboard handler owns and equips the board, once", function(w)
		MonetizationService.register("Hoverboard", HoverboardService._test.grant)
		T.eq(MonetizationService.decide(w.receipt("h1", 1001)), GRANTED, "Neon Comet")
		T.eq(w.data.Hoverboards.Owned.NeonComet, true, "owned")
		T.eq(w.data.Hoverboards.Equipped, "NeonComet", "equipped (faster than nothing)")
		w.data.Hoverboards.Owned.TimberDrifter = true
		T.eq(MonetizationService.decide(w.receipt("h2", 1002)), GRANTED, "Royal Phoenix")
		T.eq(w.data.Hoverboards.Equipped, "RoyalPhoenix", "the faster board is equipped")
		T.eq(MonetizationService.decide(w.receipt("h3", 1001)), GRANTED, "Neon Comet bought again")
		T.eq(w.data.Hoverboards.Equipped, "RoyalPhoenix", "an owned board changes nothing")
		T.eq(w.data.PurchaseCount, 3, "every purchase is recorded")
	end)
end
