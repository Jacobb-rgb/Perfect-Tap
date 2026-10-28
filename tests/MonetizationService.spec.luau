-- MonetizationService under Lune.
-- Game passes (the hoverboards): owned on load -> granted (idempotent, "unlocked" once),
-- "not owned" after a pass grant -> revoked and unequipped (a coin board survives), a check
-- that keeps failing changes nothing, a retry that succeeds, the purchase-finished signal
-- (true / false, unknown id, id 0), the session cache, and boards never going through
-- ProcessReceipt.
-- Developer products (a test-only entry): NotProcessedYet without the player or their save
-- on this server, idempotent by PurchaseId, the save goes through before PurchaseGranted,
-- unknown / id 0 products, a receipt decided twice at once.
-- Players, saves, Net and UserOwnsGamePassAsync are small fakes.
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
	local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")

	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local m = MonetizationService._test
	local COMET, PHOENIX, PRODUCT = 1001, 1002, 5001

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
		local w: any = { granted = 0, saves = 0, saveOk = true, changed = 0, notes = {}, pauses = {}, owned = {}, calls = 0 }
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
		-- real ids for both board passes, plus a test-only developer product
		w.oldIds = {}
		for key, entry in MonetizationConfig.Entries do
			w.oldIds[key] = entry.Id
		end
		MonetizationConfig.Entries.HoverboardCustom.Id = COMET
		-- the game sells one Robux board (owner 2026-10-25); a second, faster test-only board and
		-- its pass keep the two-pass cases (which one is equipped, revoking both, a retry)
		MonetizationConfig.Entries.HoverboardTestFast = {
			Key = "HoverboardTestFast",
			Kind = "GamePass",
			Id = PHOENIX,
			Robux = 49,
			Name = "Test fast board",
			Grant = "Hoverboard",
			BoardId = "TestFastBoard",
		}
		HoverboardData.ById.TestFastBoard = table.clone(HoverboardData.ById.TerraForgeCustom)
		HoverboardData.ById.TestFastBoard.Id = "TestFastBoard"
		HoverboardData.ById.TestFastBoard.PassKey = "HoverboardTestFast"
		HoverboardData.ById.TestFastBoard.Speed = HoverboardData.ById.TerraForgeCustom.Speed + 5 -- faster than the real one
		MonetizationConfig.Entries.TestCoinPouch =
			{ Key = "TestCoinPouch", Kind = "Product", Id = PRODUCT, Robux = 25, Name = "Test pouch", Grant = "TestPouch" }
		m.reset()
		m.setFindPlayer(function(userId)
			return if userId == w.player.UserId then w.player else nil
		end)
		-- Roblox's answers: w.owned[passId] = true / false, or a function (error / count)
		m.setOwnsGamePass(function(userId, passId)
			w.calls += 1
			local answer = w.owned[passId]
			if type(answer) == "function" then
				return answer()
			end
			if answer == nil then
				error("HTTP 500 (fake)")
			end
			return answer == true
		end)
		m.setPause(function(seconds)
			table.insert(w.pauses, seconds)
		end)
		w.oldProductGrant = m.grants.TestPouch
		w.oldHoverboardGrant = m.grants.Hoverboard
		w.oldPass = m.passHandlers.Hoverboard
		MonetizationService.register("TestPouch", function(player, data, entry)
			w.granted += 1
			w.lastEntry = entry
			return w.grantOk ~= false
		end)
		-- nothing about boards may go through ProcessReceipt
		MonetizationService.register("Hoverboard", function()
			w.boardReceipts = (w.boardReceipts or 0) + 1
			return true
		end)
		MonetizationService.registerPass("Hoverboard", { grant = HoverboardService._test.grant, revoke = HoverboardService._test.revoke })
		w.receipt = function(purchaseId: any, productId: any, userId: any?): any
			return { PlayerId = userId or w.player.UserId, PurchaseId = purchaseId, ProductId = productId, CurrencySpent = 25 }
		end
		w.boards = function(): any
			return w.data.Hoverboards
		end
		w.unlockedNotes = function(): number
			local n = 0
			for _, note in w.notes do
				if note.Name == "Notify" and type(note.A) == "table" and string.find(note.A.Text, "unlocked", 1, true) then
					n += 1
				end
			end
			return n
		end
		w.restore = function()
			m.grants.TestPouch = w.oldProductGrant
			m.grants.Hoverboard = w.oldHoverboardGrant
			m.passHandlers.Hoverboard = w.oldPass
			MonetizationConfig.Entries.TestCoinPouch = nil
			MonetizationConfig.Entries.HoverboardTestFast = nil
			HoverboardData.ById.TestFastBoard = nil
			for key, id in w.oldIds do
				MonetizationConfig.Entries[key].Id = id
			end
			HoverboardService._test.reset()
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

	---------------------------------------------------------------- game passes

	withWorld("passes: owned on load -> the board is granted and equipped, idempotent on every load", function(w)
		w.owned[COMET] = true
		w.owned[PHOENIX] = false
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, true, "owned")
		T.eq(w.boards().Passes.TerraForgeCustom, true, "marked as pass-given")
		T.eq(w.boards().Equipped, "TerraForgeCustom", "equipped")
		T.eq(w.boards().Owned.TestFastBoard, nil, "the other pass isn't owned")
		T.truthy(MonetizationService.owns(w.player, "HoverboardCustom"), "session cache: owned")
		T.falsy(MonetizationService.owns(w.player, "HoverboardTestFast"), "session cache: not owned")
		T.eq(w.unlockedNotes(), 1, "'unlocked' said once")
		local changes = w.changed
		m.checkAll(w.player)
		m.checkAll(w.player)
		T.eq(w.unlockedNotes(), 1, "no repeat on later loads")
		T.eq(w.changed, changes, "nothing changed on later loads")
		T.eq(w.boards().Owned.TerraForgeCustom, true, "still owned")
	end)

	withWorld("passes: not owned after a pass grant -> revoked, unequipped, off the board; coin boards survive", function(w)
		w.data.Hoverboards.Owned.TimberDrifter = true
		w.owned[COMET] = true
		w.owned[PHOENIX] = true
		m.checkAll(w.player)
		T.eq(w.boards().Equipped, "TestFastBoard", "the fastest pass board equipped")
		-- ride the Phoenix, then Roblox says both passes are gone (refunded)
		HoverboardService._test.riding(w.player, "TestFastBoard")
		w.owned[COMET] = false
		w.owned[PHOENIX] = false
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, nil, "Comet revoked")
		T.eq(w.boards().Owned.TestFastBoard, nil, "Phoenix revoked")
		T.eq(w.boards().Passes.TestFastBoard, nil, "pass marks cleared")
		T.eq(w.boards().Equipped, "", "unequipped")
		T.falsy(HoverboardService.isRiding(w.player), "got off the revoked board")
		T.eq(w.boards().Owned.TimberDrifter, true, "the coin board survives a revoke")
		T.falsy(MonetizationService.owns(w.player, "HoverboardTestFast"), "session cache: not owned")
	end)

	withWorld("passes: a revoke never takes a board the pass didn't give", function(w)
		-- an older grant without the pass mark (and a coin board) stay put
		w.data.Hoverboards.Owned.TerraForgeCustom = true
		w.data.Hoverboards.Owned.CartCruiser = true
		w.data.Hoverboards.Equipped = "TerraForgeCustom"
		w.owned[COMET] = false
		w.owned[PHOENIX] = false
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, true, "no pass mark: not taken")
		T.eq(w.boards().Owned.CartCruiser, true, "coin board untouched")
		T.eq(w.boards().Equipped, "TerraForgeCustom", "still equipped")
	end)

	withWorld("passes: a check that keeps failing changes nothing; a retry that succeeds counts", function(w)
		w.data.Hoverboards.Owned.TerraForgeCustom = true
		w.data.Hoverboards.Passes.TerraForgeCustom = true
		w.data.Hoverboards.Equipped = "TerraForgeCustom"
		-- Comet: every try errors; Phoenix: errors twice, then says owned
		local phoenixTries = 0
		w.owned[COMET] = function()
			error("HTTP 503 (fake)")
		end
		w.owned[PHOENIX] = function()
			phoenixTries += 1
			if phoenixTries < 3 then
				error("timeout (fake)")
			end
			return true
		end
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, true, "a failed check never revokes")
		T.eq(w.boards().Passes.TerraForgeCustom, true, "the pass mark stays")
		T.falsy(MonetizationService.owns(w.player, "HoverboardCustom"), "unknown, not owned, in the cache")
		T.eq(phoenixTries, 3, "the third try answered")
		T.eq(w.boards().Owned.TestFastBoard, true, "granted after the retry")
		T.eq(w.boards().Equipped, "TestFastBoard", "the faster board is equipped")
		T.eq(
			w.calls,
			MonetizationService.CheckTries * (1 + MonetizationService.Rechecks) + 3,
			"Comet tried CheckTries times in the load round and every later round, Phoenix 3 times"
		)
		T.eq(w.pauses[1], MonetizationService.RetryDelay, "first pause")
		T.eq(w.pauses[2], MonetizationService.RetryDelay * 2, "the pause doubles")
		T.eq(w.pauses[6], MonetizationService.RecheckDelay, "the failing pass is asked again later")
		T.truthy(MonetizationService.passesChecked(w.player), "the load's first round is done")
	end)

	withWorld("passes: a board bought while its check is in flight keeps the purchase (Roblox's stale 'not owned')", function(w)
		w.owned[PHOENIX] = false
		w.owned[COMET] = function()
			-- the player buys the pass while Roblox works on the check, which answers from before it
			m.purchaseFinished(w.player, COMET, true)
			return false
		end
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, true, "still owned")
		T.eq(w.boards().Passes.TerraForgeCustom, true, "the pass mark stays")
		T.eq(w.boards().Equipped, "TerraForgeCustom", "still equipped")
		T.truthy(MonetizationService.owns(w.player, "HoverboardCustom"), "session cache: owned")
		-- a later round in this session (a cached answer) never takes it either
		w.owned[COMET] = false
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, true, "kept for the session")
		-- the next session: a refund is seen
		m.forget(w.player)
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, nil, "refunded: revoked on the next load")
	end)

	withWorld("passes: a pass bought while the save was still loading is granted by the load's check", function(w)
		w.loaded = false
		m.purchaseFinished(w.player, COMET, true)
		T.eq(w.data.Hoverboards.Owned.TerraForgeCustom, nil, "no save yet: nothing to grant into")
		T.truthy(MonetizationService.owns(w.player, "HoverboardCustom"), "session cache: owned")
		w.loaded = true
		w.owned[COMET] = true
		w.owned[PHOENIX] = false
		m.checkAll(w.player)
		T.eq(w.boards().Owned.TerraForgeCustom, true, "granted once the save loaded")
	end)

	withWorld("passes: a player who leaves stops the checks quietly; no save = no change", function(w)
		w.owned[COMET] = function()
			w.player.Parent = nil
			error("left (fake)")
		end
		w.owned[PHOENIX] = true
		m.checkAll(w.player)
		T.eq(w.calls, 1, "no more tries once the player left")
		T.eq(w.boards().Owned.TestFastBoard, nil, "nothing granted after leaving")
		w.player.Parent = true
		w.loaded = false
		m.checkAll(w.player)
		T.eq(w.data.Hoverboards.Owned.TestFastBoard, nil, "no loaded save: nothing written")
	end)

	withWorld("passes: purchase finished grants only a live pass that was bought", function(w)
		m.purchaseFinished(w.player, COMET, false)
		T.eq(w.boards().Owned.TerraForgeCustom, nil, "not purchased: nothing")
		m.purchaseFinished(w.player, 777777, true)
		T.eq(next(w.boards().Owned), nil, "an unknown pass id: nothing")
		m.purchaseFinished(w.player, PRODUCT, true)
		T.eq(next(w.boards().Owned), nil, "a developer product id is no pass")
		local old = MonetizationConfig.Entries.HoverboardTestFast.Id
		MonetizationConfig.Entries.HoverboardTestFast.Id = 0
		m.purchaseFinished(w.player, 0, true)
		T.eq(w.boards().Owned.TestFastBoard, nil, "id 0 never matches")
		MonetizationConfig.Entries.HoverboardTestFast.Id = old
		m.purchaseFinished(w.player, COMET, true)
		T.eq(w.boards().Owned.TerraForgeCustom, true, "bought: granted")
		T.eq(w.boards().Equipped, "TerraForgeCustom", "equipped")
		T.truthy(MonetizationService.owns(w.player, "HoverboardCustom"), "session cache")
		T.truthy(w.changed > 0, "DataService.changed")
		m.purchaseFinished(w.player, COMET, true)
		T.eq(w.unlockedNotes(), 1, "a second signal changes nothing")
	end)

	withWorld("passes: id 0 passes are never checked, and boards never go through ProcessReceipt", function(w)
		MonetizationConfig.Entries.HoverboardCustom.Id = 0
		w.owned[PHOENIX] = true
		m.checkAll(w.player)
		T.eq(w.calls, 1, "only the live pass is checked")
		T.eq(w.boards().Owned.TerraForgeCustom, nil, "id 0: nothing")
		T.eq(MonetizationService.decide(w.receipt("b1", PHOENIX)), NOT_YET, "a pass id as a receipt")
		T.eq(w.boardReceipts, nil, "no board grant through ProcessReceipt")
		T.eq(w.data.Purchases.b1, nil, "nothing recorded")
	end)

	---------------------------------------------------------------- developer products

	withWorld("receipts: NotProcessedYet when the player or their save isn't on this server", function(w)
		T.eq(MonetizationService.decide(w.receipt("a1", PRODUCT, 999)), NOT_YET, "player not in this server")
		w.loaded = false
		T.eq(MonetizationService.decide(w.receipt("a1", PRODUCT)), NOT_YET, "save not loaded here (no session lock)")
		T.eq(w.granted, 0, "nothing granted")
		T.eq(w.data.Purchases.a1, nil, "nothing recorded")
		w.loaded = true
		T.eq(MonetizationService.decide(w.receipt("a1", PRODUCT)), GRANTED, "granted once the save is here")
		T.eq(w.granted, 1, "granted once")
	end)

	withWorld("receipts: granted once per PurchaseId, recorded and saved before PurchaseGranted", function(w)
		T.eq(MonetizationService.decide(w.receipt("p1", PRODUCT)), GRANTED, "first call")
		T.eq(w.granted, 1, "granted")
		T.eq(w.lastEntry.Key, "TestCoinPouch", "the entry of the receipt's id")
		T.truthy(w.data.Purchases.p1 ~= nil, "PurchaseId recorded")
		T.eq(w.data.PurchaseCount, 1, "PurchaseCount")
		T.eq(w.saves, 1, "saved before answering")
		T.truthy(w.changed >= 1, "DataService.changed")
		T.eq(MonetizationService.decide(w.receipt("p1", PRODUCT)), GRANTED, "the same receipt again")
		T.eq(w.granted, 1, "never granted twice")
		T.eq(w.data.PurchaseCount, 1, "counted once")
		T.eq(MonetizationService.decide(w.receipt(12345, PRODUCT)), GRANTED, "numeric purchase ids work")
		T.truthy(w.data.Purchases["12345"] ~= nil, "numeric id stored as text")
		T.eq(w.granted, 2, "two different purchases, two grants")
	end)

	withWorld("receipts: a failed save is retried, PurchaseGranted only after it went through", function(w)
		w.saveOk = false
		T.eq(MonetizationService.decide(w.receipt("s1", PRODUCT)), NOT_YET, "save failed")
		T.eq(w.granted, 1, "granted in memory")
		T.truthy(w.data.Purchases.s1 ~= nil, "id recorded with the grant")
		T.truthy(m.isUnsaved("s1"), "remembered as not saved")
		T.eq(MonetizationService.decide(w.receipt("s1", PRODUCT)), NOT_YET, "still failing")
		T.eq(w.granted, 1, "no second grant while retrying")
		w.saveOk = true
		T.eq(MonetizationService.decide(w.receipt("s1", PRODUCT)), GRANTED, "the save went through")
		T.eq(w.granted, 1, "still one grant")
		T.falsy(m.isUnsaved("s1"), "saved")
		T.eq(w.data.PurchaseCount, 1, "counted once")
	end)

	withWorld("receipts: unknown products, id 0, refusing handlers and junk are never granted", function(w)
		T.eq(MonetizationService.decide(w.receipt("u1", 5555)), NOT_YET, "unknown product id")
		T.eq(MonetizationService.decide(w.receipt("u2", 0)), NOT_YET, "id 0 never matches")
		T.eq(MonetizationService.decide(nil), NOT_YET, "nil receipt")
		T.eq(MonetizationService.decide({}), NOT_YET, "empty receipt")
		T.eq(MonetizationService.decide(w.receipt(nil, PRODUCT)), NOT_YET, "no purchase id")
		T.eq(MonetizationService.decide(w.receipt("u3", PRODUCT, "4242")), NOT_YET, "a string player id")
		T.eq(w.granted, 0, "nothing granted")
		w.grantOk = false
		T.eq(MonetizationService.decide(w.receipt("u4", PRODUCT)), NOT_YET, "the handler refused")
		T.eq(w.data.Purchases.u4, nil, "a refused grant is not recorded")
		T.eq(w.saves, 0, "nothing saved")
		MonetizationConfig.Entries.TestCoinPouch.Id = 0
		w.grantOk = true
		T.eq(MonetizationService.decide(w.receipt("u5", PRODUCT)), NOT_YET, "a product without an id")
	end)

	withWorld("receipts: a grant handler that yields is cancelled and refused, nothing recorded", function(w)
		local finished = false
		local yielded: thread? = nil
		MonetizationService.register("TestPouch", function()
			yielded = coroutine.running()
			coroutine.yield() -- what task.wait or a DataStore call would do
			finished = true
			return true
		end)
		T.eq(MonetizationService.decide(w.receipt("y1", PRODUCT)), NOT_YET, "a yielding handler is refused")
		T.eq(w.data.Purchases.y1, nil, "not recorded")
		T.eq(yielded and coroutine.status(yielded), "dead", "the handler's thread is closed")
		T.falsy(finished, "the cancelled handler never finishes later")
	end)

	withWorld("receipts: the same PurchaseId decided twice at once waits", function(w)
		m.setInFlight("f1", true)
		T.eq(MonetizationService.decide(w.receipt("f1", PRODUCT)), NOT_YET, "in flight")
		T.eq(w.granted, 0, "not granted while the first call runs")
		m.setInFlight("f1", false)
		T.eq(MonetizationService.decide(w.receipt("f1", PRODUCT)), GRANTED, "then granted")
	end)
end
