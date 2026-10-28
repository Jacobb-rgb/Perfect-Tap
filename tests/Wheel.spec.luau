-- The Spin & Win wheel (step 7; bought spins and the Pop look, owner
-- 2026-10-20): WheelService (the free spin: cooldown saved before the
-- prize, every prize kind and its fallbacks, the paid-random substitutes,
-- junk input, the EmberChest prompt; bought spins: the receipt banks them,
-- the free spin goes first, bought ones ignore the cooldown and use the same
-- table, restricted players can't buy or spin them, "Buy" only prompts)
-- and WheelView (exact odds rows, percent / countdown texts, the disc angles
-- that put a segment under the pointer, the pie bars, SPIN (n), Fast Spin,
-- the buy step's odds, the jackpot tiles, every screen's layout and touch
-- sizes, no emoji, the chip).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local fs = require("@lune/fs") :: any
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local Receipts = Loader.requirePath("ServerScriptService.Server.Receipts")
	local BoostService = Loader.requirePath("ServerScriptService.Server.Services.BoostService")
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local WheelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WheelConfig")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local EnchantConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EnchantConfig")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local WheelService = Loader.requirePath("ServerScriptService.Server.Services.WheelService")
	local WheelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")

	local NOW = 1_800_000_000
	local DAY = WheelConfig.CooldownSeconds

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
		local p: any = { UserId = userId, Name = "Spinner" .. userId, Parent = true, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	-- A roll in the middle of segment `index` of a wheel.
	local function rollFor(index: number, noCapsules: boolean?): number
		local acc = 0
		for i, segment in WheelConfig.segments(noCapsules) do
			if i == index then
				return acc + segment.Odds / 2
			end
			acc += segment.Odds
		end
		error("no segment " .. index)
	end

	-- A world: one loaded player, every reply logged, rolls taken in order.
	local function withWheel(name: string, body: (any) -> ())
		T.test(name, function()
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			local w: any = { replies = {}, rolls = {}, income = 0, restricted = false, now = NOW, clock = 100 }
			w.player = fakePlayer(901)
			w.data = deepCopy(DataTemplate)
			patch(DataService, "get", function(p)
				return if p == w.player then w.data else nil
			end)
			patch(DataService, "changed", function()
				w.changed = (w.changed or 0) + 1
			end)
			patch(Net, "fire", function(event: string, p: any, a: any, b: any)
				table.insert(w.replies, { Event = event, Player = p, A = a, B = b })
			end)
			w.policyCalls = 0
			patch(Policy, "paidRandomRestricted", function()
				w.policyCalls += 1
				return w.restricted
			end)
			patch(PodiumService, "incomeOf", function()
				return w.income
			end)
			WheelService._test.reset()
			WheelService._test.setClock(function()
				return w.now
			end)
			WheelService._test.setRandom(function()
				return if #w.rolls > 0 then table.remove(w.rolls, 1) else 0.5
			end)
			WheelService._test.setTimer(function()
				return w.clock
			end)
			WheelService._test.setCapsules(nil) -- no capsule package: the wheel opens it itself
			Bonuses._test.reset()
			Bonuses._test.setClock(function()
				return w.now
			end)
			w.spin = function(...: number): any
				w.rolls = { ... }
				local before = #w.replies
				WheelService._test.action(w.player, "Spin")
				local reply = w.replies[#w.replies]
				return if #w.replies > before then reply else nil
			end
			-- the client's "Reveal" (the screen showed a capsule prize): the reply, if any
			w.reveal = function(): any
				local before = #w.replies
				WheelService._test.action(w.player, "Reveal")
				return if #w.replies > before then w.replies[#w.replies] else nil
			end
			local ok, err = pcall(body, w)
			WheelService._test.reset()
			Bonuses._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	---------------------------------------------------------------- the free spin

	withWheel("Wheel: a spin that isn't ready never asks PolicyService (audit S1)", function(w)
		T.truthy(w.spin(rollFor(4)), "the first spin works")
		T.eq(w.policyCalls, 1)
		for _ = 1, 5 do
			w.spin(rollFor(4))
		end
		T.eq(w.policyCalls, 1, "not-ready spins stop before the policy call")
		w.now += DAY
		T.truthy(w.spin(rollFor(4)))
		T.eq(w.policyCalls, 2, "the next day's spin asks again")
	end)

	withWheel("Wheel: a ready spin saves the cooldown and answers with WheelResult", function(w)
		local reply = w.spin(rollFor(4))
		T.eq(reply.Event, "WheelResult")
		local result = reply.A
		T.eq(result.Id, "Shards")
		T.eq(result.Segment, 4)
		T.eq(result.Kind, "Shards")
		T.eq(result.NextSpinAt, NOW + DAY, "next spin in 24 h")
		T.eq(w.data.Wheel.NextSpinAt, NOW + DAY, "saved")
		T.eq(w.data.Stats.WheelSpins, 1)
		T.truthy((w.changed or 0) >= 1, "DataService.changed")
	end)

	withWheel("Wheel: a second spin the same day is refused and changes nothing", function(w)
		w.spin(rollFor(4))
		local shards = w.data.Shards
		w.now = NOW + DAY - 1
		local reply = w.spin(rollFor(4))
		T.eq(reply.Event, "ActionResult")
		T.eq(reply.A.Action, "Wheel")
		T.eq(reply.A.Op, "Spin")
		T.eq(reply.A.Ok, false)
		T.eq(reply.A.Reason, "NotReady")
		T.truthy(WheelConfig.Reasons[reply.A.Reason], "a Reasons code")
		T.eq(w.data.Shards, shards, "no second prize")
		T.eq(w.data.Stats.WheelSpins, 1)
		-- the timer ran out (also while offline): ready again
		w.now = NOW + DAY
		T.eq(w.spin(rollFor(4)).Event, "WheelResult")
		T.eq(w.data.Wheel.NextSpinAt, NOW + 2 * DAY)
	end)

	withWheel("Wheel: a broken saved timer counts as ready", function(w)
		w.data.Wheel.NextSpinAt = 0 / 0
		T.eq(w.spin(rollFor(1)).Event, "WheelResult")
		w.data.Wheel = "junk"
		w.now = NOW + 3 * DAY
		T.eq(w.spin(rollFor(1)).Event, "WheelResult", "a junk record is replaced")
		T.eq(type(w.data.Wheel), "table")
	end)

	withWheel("Wheel: junk actions get no answer; no save answers NotReady", function(w)
		local before = #w.replies
		WheelService._test.action(w.player, "Buy")
		WheelService._test.action(w.player, "Buy", { Count = 3 })
		WheelService._test.action(w.player, "Buy", { Count = 0 / 0 })
		WheelService._test.action(w.player, "Buy", { Count = "5" })
		WheelService._test.action(w.player, "Buy", { Count = 5, A = 1, B = 2 })
		WheelService._test.action(w.player, nil)
		WheelService._test.action(w.player, { "Spin" })
		T.eq(#w.replies, before, "dropped")
		T.eq(w.data.Stats.WheelSpins, 0)
		local stranger = fakePlayer(902)
		WheelService._test.action(stranger, "Spin")
		local reply = w.replies[#w.replies]
		T.eq(reply.Player, stranger)
		T.eq(reply.A.Reason, "NotReady")
	end)

	---------------------------------------------------------------- prizes

	withWheel("Wheel: Coins pay seconds of podium income, at least Min", function(w)
		w.income = 0
		local result = w.spin(rollFor(1)).A
		local coins = WheelConfig.ById.Coins
		T.eq(result.Amount, coins.Min, "a new player gets the minimum")
		T.eq(w.data.Coins, coins.Min)
		w.now += DAY
		w.income = 640
		local big = w.spin(rollFor(5)).A
		T.eq(big.Id, "BigCoins")
		T.eq(big.Amount, 640 * (WheelConfig.ById.BigCoins.Seconds :: number))
		T.eq(w.data.Coins, coins.Min + big.Amount)
		T.eq(w.data.TotalEarned, w.data.Coins)
	end)

	withWheel("Wheel: a Boost adds its seconds, capped at the stack limit", function(w)
		local result = w.spin(rollFor(2)).A
		T.eq(result.Kind, "Boost")
		T.eq(result.Boost, "TripleLucky")
		T.eq(result.Seconds, 600)
		T.eq(w.data.Boosts.TripleLuckyUntil, NOW + 600)
		T.eq(result.Coins, nil, "all of it fit: no coins")
		-- already full: nothing is added (capped), the Coins segment's prize instead
		w.now += DAY
		w.data.Boosts.HexaLuckyUntil = w.now + BoostConfig.MaxStackSeconds
		local coinsBefore = w.data.Coins
		local full = w.spin(rollFor(6)).A
		T.eq(full.Boost, "HexaLucky")
		T.eq(full.Seconds, 0)
		T.eq(w.data.Boosts.HexaLuckyUntil, w.now + BoostConfig.MaxStackSeconds)
		local whole = WheelConfig.coins(WheelConfig.ById.Coins, w.income)
		T.eq(full.Coins, whole, "never an empty prize")
		T.eq(w.data.Coins, coinsBefore + whole)
		local prize, detail = WheelView.prizeText(full)
		T.truthy(prize:find("coins"), "the coins")
		T.truthy(detail:find("full"), "explains the cap")
		-- partly full: the seconds that fit, coins for the rest
		w.now += DAY
		w.data.Boosts.TripleLuckyUntil = w.now + BoostConfig.MaxStackSeconds - 240
		local part = w.spin(rollFor(2)).A
		T.eq(part.Seconds, 240)
		T.eq(part.Coins, math.floor(whole * (600 - 240) / 600))
		local prize2, detail2 = WheelView.prizeText(part)
		T.truthy(prize2:find("4 min", 1, true), "the seconds added")
		T.truthy(detail2:find("coins", 1, true), "and the coins")
		T.eq(WheelService.boostFallbackCoins(WheelConfig.ById.TripleLucky, 600, 1000), 0)
		T.eq(WheelService.boostFallbackCoins(WheelConfig.ById.TripleLucky, -5, 0), WheelConfig.ById.Coins.Min)
	end)

	withWheel("Wheel: a Capsule opens for free (Triple Lucky counts) and the opening follows", function(w)
		local result = w.spin(rollFor(3), 0.0).A
		T.eq(result.Kind, "Capsule")
		T.eq(result.Capsule, "Stone")
		local golem = result.Golem
		T.truthy(golem, "a golem")
		T.eq(golem.Kind, CapsuleConfig.roll("Stone", false, 0.0))
		T.eq(#w.data.Golems.Owned, 1)
		T.eq(w.data.Golems.Owned[1].Id, golem.Id)
		T.falsy(w.data.Golems.Owned[1].Paid, "a wheel prize is not paid")
		T.eq(w.data.Stats.CapsulesOpened, 1)
		T.eq(result.Lucky, false)
		-- the opening waits for the open screen's "Reveal", and comes once
		local opening = w.reveal()
		T.eq(opening.Event, "CapsuleResult")
		T.eq(opening.A.Free, true)
		T.eq(opening.A.Count, 1)
		T.eq(opening.A.Golems[1].Id, golem.Id)
		T.eq(w.reveal(), nil, "only once")
		T.eq(#w.data.Golems.Owned, 1, "Reveal grants nothing")
		-- with Triple Lucky on, the lucky odds are used
		w.now += DAY
		w.data.Boosts.TripleLuckyUntil = w.now + 300
		local lucky = w.spin(rollFor(8), 0.999).A
		T.eq(lucky.Capsule, "Crystal")
		T.eq(lucky.Lucky, true)
		T.eq(lucky.Golem.Kind, CapsuleConfig.roll("Crystal", true, 0.999))
	end)

	withWheel("Wheel: a full golem inventory pays a share of the capsule instead", function(w)
		for _ = 1, GolemConfig.InventoryCap do
			GolemConfig.add(w.data.Golems, GolemConfig.List[1].Id)
		end
		local result = w.spin(rollFor(3)).A
		T.eq(result.Kind, "Capsule")
		T.falsy(result.Golem)
		local share = WheelConfig.capsuleFallbackCoins("Stone", w.data.BlasterLevel)
		T.truthy(share > 0)
		T.eq(result.Coins, share)
		T.eq(w.data.Coins, share)
		T.eq(#w.data.Golems.Owned, GolemConfig.InventoryCap, "no golem past the cap")
		T.eq(w.reveal(), nil, "no opening")
	end)

	withWheel("Wheel: a capsule's opening is dropped for a closed screen (no Reveal in time)", function(w)
		w.spin(rollFor(3), 0.0)
		w.clock += WheelService.RevealSeconds + 1
		T.eq(w.reveal(), nil, "too late: the golem is in the inventory, the toast told the player")
		T.eq(#w.data.Golems.Owned, 1)
		-- junk Reveals before any prize change nothing
		w.now += DAY
		w.spin(rollFor(4))
		T.eq(w.reveal(), nil)
	end)

	-- A capsule package like the real one (Capsules, step 7): grantFree(player,
	-- capsuleId, count?, quiet?) -> (CapsuleResult?, reason?); it adds the golems,
	-- calls DataService.changed and sends the CapsuleResult itself unless it
	-- declares QuietFree and is asked to be quiet.
	local function fakeCapsules(w: any, quietFree: boolean): any
		local fake: any = { QuietFree = if quietFree then true else nil, calls = {} }
		fake.grantFree = function(p: any, capsuleId: string, count: number?, quiet: boolean?): (any, string?)
			table.insert(fake.calls, { Player = p, Capsule = capsuleId, Count = count, Quiet = quiet })
			local n = count or 1
			if GolemConfig.room(w.data.Golems) < n then
				return nil, "InventoryFull"
			end
			local entry = GolemConfig.add(w.data.Golems, GolemConfig.List[2].Id)
			w.data.Stats.CapsulesOpened = (w.data.Stats.CapsulesOpened or 0) + 1
			DataService.changed(p)
			local result = { Capsule = capsuleId, Count = n, Golems = { { Id = entry.Id, Kind = entry.Kind } }, Lucky = true, Free = true }
			if not (fake.QuietFree and quiet) then
				Net.fire("CapsuleResult", p, result)
			end
			return result, nil
		end
		return fake
	end

	local function count(w: any, event: string): number
		local n = 0
		for _, reply in w.replies do
			if reply.Event == event then
				n += 1
			end
		end
		return n
	end

	withWheel("Wheel: the capsule package's grantFree (quiet) opens it, the wheel's Reveal plays it once", function(w)
		local fake = fakeCapsules(w, true)
		WheelService._test.setCapsules(fake)
		local result = w.spin(rollFor(8), 0.25).A
		T.eq(#fake.calls, 1)
		T.eq(fake.calls[1].Player, w.player)
		T.eq(fake.calls[1].Capsule, "Crystal")
		T.eq(fake.calls[1].Count, 1, "one capsule")
		T.eq(fake.calls[1].Quiet, true, "asked to stay quiet")
		T.eq(result.Golem.Id, w.data.Golems.Owned[1].Id)
		T.eq(result.Golem.Kind, GolemConfig.List[2].Id)
		T.eq(result.Lucky, true, "the service's Triple Lucky answer")
		T.eq(#w.data.Golems.Owned, 1, "one golem, added by the service only")
		T.eq(w.data.Stats.CapsulesOpened, 1)
		T.eq(count(w, "CapsuleResult"), 0, "nothing spoils the turning disc")
		local opening = w.reveal()
		T.eq(opening.Event, "CapsuleResult")
		T.eq(opening.A.Golems[1].Id, result.Golem.Id)
		T.eq(opening.A.Free, true)
		T.eq(w.reveal(), nil, "once")
	end)

	withWheel("Wheel + the real CapsuleService: a quiet free capsule, its opening once on Reveal", function(w)
		local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
		T.eq(CapsuleService.QuietFree, true, "the capsule package honors quiet")
		WheelService._test.setCapsules(CapsuleService :: any)
		local result = w.spin(rollFor(8)).A
		T.eq(result.Capsule, "Crystal")
		T.truthy(result.Golem, "a golem woke")
		T.eq(#w.data.Golems.Owned, 1, "added once, by the capsule package")
		T.eq(w.data.Golems.Owned[1].Kind, result.Golem.Kind)
		T.truthy(CapsuleConfig.ById.Crystal.Odds[result.Golem.Kind], "rolled from the Crystal capsule's odds")
		T.eq(w.data.Stats.CapsulesOpened, 1)
		T.eq(count(w, "CapsuleResult"), 0, "nothing spoils the turning disc")
		local opening = w.reveal()
		T.eq(opening.Event, "CapsuleResult")
		T.eq(opening.A.Free, true)
		T.eq(opening.A.Golems[1].Id, result.Golem.Id)
		T.eq(w.reveal(), nil, "once")
	end)

	withWheel("Wheel: an older capsule package sends the opening itself: the wheel never sends it again", function(w)
		local fake = fakeCapsules(w, false)
		WheelService._test.setCapsules(fake)
		local result = w.spin(rollFor(3), 0.25).A
		T.truthy(result.Golem, "the golem")
		T.eq(count(w, "CapsuleResult"), 1, "the service's own CapsuleResult")
		T.eq(w.reveal(), nil, "no second opening")
		T.eq(count(w, "CapsuleResult"), 1)
		T.eq(#w.data.Golems.Owned, 1)
	end)

	withWheel("Wheel: grantFree refusals and errors pay the coin share and never roll again", function(w)
		local fake = fakeCapsules(w, true)
		WheelService._test.setCapsules(fake)
		-- the inventory is full: the coins share, Full = true (the card says why)
		for _ = 1, GolemConfig.InventoryCap do
			GolemConfig.add(w.data.Golems, GolemConfig.List[1].Id)
		end
		local full = w.spin(rollFor(3)).A
		T.falsy(full.Golem)
		local share = WheelConfig.capsuleFallbackCoins("Stone", w.data.BlasterLevel)
		T.eq(full.Coins, share)
		T.eq(full.Full, true)
		local _, fullText = WheelView.prizeText(full)
		T.truthy(fullText:find("inventory is full", 1, true))
		T.eq(#w.data.Golems.Owned, GolemConfig.InventoryCap, "no golem past the cap")
		T.eq(w.reveal(), nil, "no opening")
		-- any other refusal: the same coins, no false "full" message, no roll here
		table.clear(w.data.Golems.Owned)
		w.now += DAY
		fake.grantFree = function(): (any, string?)
			return nil, "BadCapsule"
		end
		local coinsBefore = w.data.Coins
		local refused = w.spin(rollFor(3)).A
		T.falsy(refused.Golem)
		T.eq(refused.Coins, share)
		T.eq(refused.Full, nil)
		local _, refusedText = WheelView.prizeText(refused)
		T.falsy(refusedText:find("full", 1, true), "never claims a full inventory")
		T.eq(w.data.Coins, coinsBefore + share)
		T.eq(#w.data.Golems.Owned, 0, "the wheel didn't open one itself")
		-- the service fails half-way (a golem may already be in): coins, never a second golem
		w.now += DAY
		fake.grantFree = function(p: any): (any, string?)
			GolemConfig.add(w.data.Golems, GolemConfig.List[1].Id)
			error("capsule package down")
		end
		local failed = w.spin(rollFor(3), 0.0).A
		T.falsy(failed.Golem)
		T.eq(failed.Coins, share)
		T.eq(#w.data.Golems.Owned, 1, "only the service's half-done golem, no second roll")
		T.eq(w.reveal(), nil)
		T.eq(w.data.Wheel.NextSpinAt, w.now + DAY, "the cooldown holds all the same")
	end)

	withWheel("Wheel: the Ore Prize puts a dirty Rare+ ore into the pen and keeps it secret", function(w)
		local result = w.spin(rollFor(7), 0.01).A
		T.eq(result.Kind, "Ore")
		T.eq(result.DirtyOre, true)
		T.eq(result.Ore, nil, "which ore stays secret")
		T.eq(#w.data.Storage, 1)
		T.eq(w.data.Stats.WheelOres, 1, "counted as the wheel's (the tutorial leaves it out)")
		T.eq(TutorialConfig.advance(1, w.data), 1, "a new player's tutorial stays on step 1 (no mine, hopper or train skipped)")
		local entry = w.data.Storage[1]
		T.eq(entry.K, "Raw", "dirty")
		local context = WheelService.oreContext(w.player, w.data)
		T.eq(entry.O, WheelConfig.pickOre(0.01, context))
		T.truthy(BoostConfig.isLuckyOre(entry.O), "Rare or rarer")
		for key in result do
			T.truthy(key ~= "O" and key ~= "OreId", "no ore id in the result")
		end
	end)

	withWheel("Wheel: a full pen pays the ore prize's expected raw value", function(w)
		for _ = 1, 2000 do
			if #w.data.Storage >= GameConfig.MaxStoredItems then
				break
			end
			table.insert(w.data.Storage, { K = "Raw", O = "Coal" })
		end
		local before = #w.data.Storage
		local result = w.spin(rollFor(7)).A
		T.falsy(result.DirtyOre)
		T.eq(#w.data.Storage, before, "nothing stored")
		T.eq(w.data.Stats.WheelOres, 0, "no wheel ore in the pen")
		local expected = WheelConfig.oreFallbackCoins(WheelService.oreContext(w.player, w.data))
		T.truthy(expected > 0)
		T.eq(result.Coins, expected)
		T.eq(w.data.Coins, expected)
	end)

	withWheel("Wheel: the full-pen ore coins include the player's sell bonus (Midas)", function(w)
		for _ = 1, 2000 do
			if #w.data.Storage >= GameConfig.MaxStoredItems then
				break
			end
			table.insert(w.data.Storage, { K = "Raw", O = "Coal" })
		end
		w.data.Enchants = { Owned = { Midas = 3 }, Slots = { "Midas", "", "", "" } }
		Bonuses.invalidate(w.player)
		local mult = 1 + EnchantConfig.value("Midas", "SellPct", 3)
		local base = WheelConfig.oreFallbackCoins(WheelService.oreContext(w.player, w.data))
		local result = w.spin(rollFor(7)).A
		T.eq(result.Coins, math.floor(base * mult + 0.5), "what Tobin would pay with Midas III")
	end)

	withWheel("Wheel: Shards go into data.Shards", function(w)
		w.data.Shards = 7
		local result = w.spin(rollFor(4)).A
		T.eq(result.Amount, WheelConfig.ById.Shards.Amount)
		T.eq(w.data.Shards, 7 + (WheelConfig.ById.Shards.Amount :: number))
	end)

	withWheel("Wheel: players who can't buy any capsule spin the substitutes", function(w)
		w.restricted = true
		local saved = rawget(CapsuleConfig, "allRestricted")
		rawset(CapsuleConfig, "allRestricted", function(restricted)
			return restricted == true
		end)
		local ok, err = pcall(function()
			local result = w.spin(rollFor(2, true)).A
			T.eq(result.Id, "TripleLuckyCoins")
			T.eq(result.Segment, 2)
			T.eq(result.Kind, "Coins")
			T.eq(w.data.Boosts.TripleLuckyUntil, 0, "no Triple Lucky for them")
			T.truthy(w.data.Coins >= (WheelConfig.Substitutes.TripleLucky.Min :: number))
		end)
		rawset(CapsuleConfig, "allRestricted", saved)
		if not ok then
			error(err, 0)
		end
	end)

	withWheel("Wheel: every segment pays out over many days (no prize kind crashes)", function(w)
		w.income = 25
		for index = 1, #WheelConfig.Segments do
			w.now += DAY
			local reply = w.spin(rollFor(index), 0.5)
			T.eq(reply.Event, "WheelResult", "segment " .. index)
			T.eq(reply.A.Segment, index)
		end
		T.eq(w.data.Stats.WheelSpins, #WheelConfig.Segments)
	end)

	---------------------------------------------------------------- bought spins (Robux)

	T.test("Wheel: the BUY SPINS rows are three paid random products (25 / 99 / 179)", function()
		local prices = { [1] = 25, [5] = 99, [10] = 179 }
		T.eq(#WheelConfig.Packs, 3)
		for _, pack in WheelConfig.Packs do
			local product = MonetizationConfig.get(pack.Product)
			T.truthy(product, pack.Product)
			T.eq(product.Kind, "Product", pack.Product .. ": bought again and again")
			T.eq(product.Grant, "WheelSpins")
			T.eq(product.Spins, pack.Count)
			T.eq(product.Robux, prices[pack.Count], pack.Product .. " price")
			T.truthy(product.PaidRandom, pack.Product .. ": a paid random item")
			T.eq(product.Id, 0, "the owner pastes the id later")
			T.eq(MonetizationConfig.promptStatus(pack.Product, true), "Restricted", "never sold where restricted")
			T.eq(MonetizationConfig.promptStatus(pack.Product, false), "ComingSoon", "id 0: coming soon")
			T.eq(WheelConfig.packFor(pack.Count), pack)
		end
		T.eq(WheelConfig.packFor(3), nil)
		T.eq(WheelConfig.packFor("5"), nil)
		-- the spins a save holds, and SPIN (n)
		T.eq(WheelConfig.heldSpins({ Spins = 3 }), 3)
		T.eq(WheelConfig.heldSpins({ Spins = 2.6 }), 2)
		T.eq(WheelConfig.heldSpins({ Spins = -1 }), 0)
		T.eq(WheelConfig.heldSpins({ Spins = 0 / 0 }), 0)
		T.eq(WheelConfig.heldSpins(nil), 0)
		T.eq(WheelConfig.spinsNow({ NextSpinAt = 0, Spins = 2 }, NOW, false), 3, "free + bought")
		T.eq(WheelConfig.spinsNow({ NextSpinAt = 0, Spins = 2 }, NOW, true), 1, "restricted: the free one only")
		T.eq(WheelConfig.spinsNow({ NextSpinAt = NOW + 60, Spins = 2 }, NOW, false), 2)
		T.eq(WheelConfig.spinsNow({ NextSpinAt = NOW + 60, Spins = 0 }, NOW, false), 0)
		T.truthy(WheelConfig.MaxSpins >= 100 and WheelConfig.MaxSavedSpins > WheelConfig.MaxSpins, "caps")
		T.truthy(WheelConfig.Reasons.Restricted and WheelConfig.Reasons.NotReady, "reason texts")
		local limit = Net.Events.WheelAction
		T.truthy(limit.Rate > 0 and limit.Rate <= 4 and limit.Burst >= 2, "WheelAction (Spin / Reveal / Buy) is rate limited")
		T.eq(DataTemplate.Wheel.Spins, 0, "a new save holds no bought spins")
	end)

	withWheel("Wheel: the receipt handler banks bought spins (nothing spins)", function(w)
		local grant = WheelService._test.grantSpins
		T.truthy(grant(w.player, w.data, MonetizationConfig.get("WheelSpins5")), "5 spins")
		T.eq(w.data.Wheel.Spins, 5)
		T.truthy(grant(w.player, w.data, MonetizationConfig.get("WheelSpins1")), "1 more")
		T.eq(w.data.Wheel.Spins, 6)
		local notify = w.replies[#w.replies]
		T.eq(notify.Event, "Notify")
		T.truthy(string.find(notify.A.Text, "you have 6", 1, true), "says how many")
		-- junk entries and another save are refused (MonetizationService keeps the receipt pending)
		T.falsy(grant(w.player, w.data, { Key = "X", Kind = "Product", Id = 0, Robux = 1, Name = "x", Description = "", Spins = 0 }))
		T.falsy(grant(w.player, w.data, { Key = "X", Kind = "Product", Id = 0, Robux = 1, Name = "x", Description = "", Spins = 2.5 }))
		T.falsy(grant(w.player, w.data, { Key = "X", Kind = "Product", Id = 0, Robux = 1, Name = "x", Description = "" }))
		T.falsy(grant(w.player, deepCopy(w.data), MonetizationConfig.get("WheelSpins1")), "not the loaded save")
		T.eq(w.data.Wheel.Spins, 6)
		-- past MaxSpins all of them still count (a receipt is never cut)
		w.data.Wheel.Spins = WheelConfig.MaxSpins
		T.truthy(grant(w.player, w.data, MonetizationConfig.get("WheelSpins10")))
		T.eq(w.data.Wheel.Spins, WheelConfig.MaxSpins + 10)
		T.eq(w.data.Stats.WheelSpins, 0, "nothing was spun")
		T.eq(w.data.Wheel.NextSpinAt, 0, "the free spin untouched")
	end)

	withWheel("Wheel: the free spin goes first, then bought spins (they ignore the cooldown)", function(w)
		w.data.Wheel.Spins = 2
		local first = w.spin(rollFor(4)).A
		T.eq(first.Paid, false, "the free spin first")
		T.eq(first.Spins, 2)
		T.eq(w.data.Wheel.NextSpinAt, NOW + DAY)
		T.eq(w.data.Wheel.Spins, 2, "no bought spin used")
		local second = w.spin(rollFor(1))
		T.eq(second.Event, "WheelResult", "a bought spin while the free one waits")
		T.eq(second.A.Paid, true)
		T.eq(second.A.Spins, 1)
		T.eq(w.data.Wheel.Spins, 1)
		T.eq(w.data.Wheel.NextSpinAt, NOW + DAY, "the cooldown stays as it was")
		T.eq(second.A.NextSpinAt, NOW + DAY)
		T.eq(w.spin(rollFor(1)).A.Spins, 0)
		local none = w.spin(rollFor(1))
		T.eq(none.Event, "ActionResult")
		T.eq(none.A.Reason, "NotReady", "nothing left")
		T.eq(w.data.Stats.WheelSpins, 3)
		-- the next day the free one goes first again
		w.data.Wheel.Spins = 1
		w.now += DAY
		local free = w.spin(rollFor(1)).A
		T.eq(free.Paid, false)
		T.eq(w.data.Wheel.Spins, 1)
	end)

	withWheel("Wheel: a bought spin draws from the same table as the free one", function(w)
		w.data.Wheel.NextSpinAt = NOW + DAY
		w.data.Wheel.Spins = #WheelConfig.Segments
		for index = 1, #WheelConfig.Segments do
			local result = w.spin(rollFor(index), 0.5).A
			T.eq(result.Paid, true)
			T.eq(result.Segment, index, "segment " .. index)
			T.eq(result.Id, WheelConfig.pick(rollFor(index), false).Id, "WheelConfig.pick, the free spin's table")
		end
		T.eq(w.data.Wheel.Spins, 0)
	end)

	withWheel("Wheel: where paid random items are restricted the free spin works, bought spins wait", function(w)
		w.restricted = true
		w.data.Wheel.Spins = 3
		local free = w.spin(rollFor(1))
		T.eq(free.Event, "WheelResult", "the free daily spin works for everyone")
		T.eq(free.A.Paid, false)
		local refused = w.spin(rollFor(1))
		T.eq(refused.Event, "ActionResult")
		T.eq(refused.A.Reason, "Restricted", "bought spins are never spun where restricted")
		T.eq(w.data.Wheel.Spins, 3, "kept in the save")
		T.eq(w.data.Stats.WheelSpins, 1)
		-- the policy allows them again (another region): they spin
		w.restricted = false
		T.eq(w.spin(rollFor(1)).A.Paid, true)
		T.eq(w.data.Wheel.Spins, 2)
		-- nothing to spin never asks PolicyService
		w.data.Wheel.Spins = 0
		local calls = w.policyCalls
		w.spin(rollFor(1))
		T.eq(w.policyCalls, calls, "no policy call without a spin to use")
	end)

	withWheel("Wheel: Buy only prompts the row's product; restricted players can't buy", function(w)
		local prompted: { string } = {}
		BoostService._test.setPrompter(function(_p: any, product: any)
			table.insert(prompted, product.Key)
		end)
		Receipts._test.setPublisher(function() end)
		local buy = function(count: any): any
			local before = #w.replies
			WheelService._test.action(w.player, "Buy", { Count = count })
			return if #w.replies > before then w.replies[#w.replies] else nil
		end
		local ok, err = pcall(function()
			w.restricted = true
			local refused = buy(5)
			T.eq(refused.Event, "PurchasePrompt")
			T.eq(refused.A.Product, "WheelSpins5")
			T.eq(refused.A.Status, "Restricted", "never sold where restricted")
			T.eq(#prompted, 0, "no prompt")
			w.restricted = false
			T.eq(buy(1).A.Status, "ComingSoon", "id 0: never prompted")
			MonetizationConfig.Products.WheelSpins10.Id = 4242
			T.eq(buy(10).A.Status, "ComingSoon", "the receipts gate is shut")
			Receipts.setReady(true)
			local live = buy(10)
			T.eq(live.A.Product, "WheelSpins10")
			T.eq(live.A.Status, "Prompted")
			T.eq(prompted[1], "WheelSpins10", "MarketplaceService's prompt")
			w.data.Wheel.Spins = WheelConfig.MaxSpins - 5
			T.eq(buy(10).A.Status, "Full", "past MaxSpins held: not offered")
			T.eq(#prompted, 1)
			T.eq(w.data.Wheel.Spins, WheelConfig.MaxSpins - 5, "a Buy never grants")
			T.eq(w.data.Stats.WheelSpins, 0)
		end)
		MonetizationConfig.Products.WheelSpins10.Id = 0
		Receipts._test.reset()
		BoostService._test.reset()
		if not ok then
			error(err, 0)
		end
	end)

	-- (review 269fd39 #1) a bought spin never swaps a golem for coins; the rows say what a full pen pays
	local function fillGolems(w: any)
		for _ = 1, GolemConfig.InventoryCap do
			GolemConfig.add(w.data.Golems, GolemConfig.List[1].Id)
		end
		T.eq(GolemConfig.room(w.data.Golems), 0, "the golem inventory is full")
	end

	local function fillPen(w: any)
		for _ = 1, 5000 do
			if PenService.refusal(w.data) then
				break
			end
			table.insert(w.data.Storage, { K = "Raw", O = "Coal" })
		end
		T.truthy(PenService.refusal(w.data) ~= nil, "the Ore Pen is full")
	end

	-- The State the client would get for this save (the fields WheelView.info reads).
	local function stateOf(w: any): any
		return {
			Golems = w.data.Golems,
			BlasterLevel = w.data.BlasterLevel,
			Stats = w.data.Stats,
			Discovered = w.data.Discovered,
			StorageCount = #w.data.Storage,
			PenCapacity = PenService.capacityOf(w.data),
			PenOver = PenService.isOver(w.data),
			Bonuses = { SellMult = 1, TripleLucky = false },
		}
	end

	withWheel("Wheel: a bought spin with a full golem inventory is refused and stays saved", function(w)
		w.data.Wheel.NextSpinAt = NOW + DAY -- only bought spins
		w.data.Wheel.Spins = 3
		fillGolems(w)
		local coins = w.data.Coins
		local refused = w.spin(rollFor(3))
		T.eq(refused.Event, "ActionResult")
		T.eq(refused.A.Reason, "InventoryFull")
		T.truthy(WheelConfig.Reasons.InventoryFull, "a reason text")
		T.eq(w.data.Wheel.Spins, 3, "the bought spin stays saved")
		T.eq(w.data.Stats.WheelSpins, 0, "nothing spun")
		T.eq(w.data.Coins, coins, "no coins instead of the prize")
		T.eq(w.data.Wheel.NextSpinAt, NOW + DAY)
		-- room again: the bought spin goes, its golem is a paid one
		table.remove(w.data.Golems.Owned)
		local result = w.spin(rollFor(3), 0.0).A
		T.eq(result.Paid, true)
		T.eq(result.Capsule, "Stone")
		T.truthy(result.Golem, "the golem, not coins")
		T.eq(w.data.Wheel.Spins, 2)
	end)

	withWheel("Wheel: a free spin with a full golem inventory still pays coins (bought spins untouched)", function(w)
		w.data.Wheel.Spins = 2
		fillGolems(w)
		local result = w.spin(rollFor(3)).A
		T.eq(result.Paid, false, "the free spin")
		T.eq(result.Kind, "Capsule")
		T.falsy(result.Golem)
		T.eq(result.Full, true)
		local share = WheelConfig.capsuleFallbackCoins("Stone", BlasterData.priceLevel(w.data))
		T.eq(result.Coins, share, "the coin share as before")
		T.eq(w.data.Wheel.Spins, 2, "no bought spin used")
		-- the row said so before the spin, with the same amount
		local info = WheelView.info(stateOf(w), false)
		T.eq(info.GolemRoom, 0)
		T.eq(WheelView.capsuleFallback(info, "Stone"), share, "the row's amount is what the server pays")
		T.truthy(
			string.find(WheelView.detail(WheelConfig.ById.StoneCapsule, info), `pays {Format.money(share)} coins instead`, 1, true),
			"the capsule row says it"
		)
	end)

	withWheel("Wheel: a full Ore Pen is disclosed in the rows with the coins the server pays", function(w)
		fillPen(w)
		local info = WheelView.info(stateOf(w), false)
		T.eq(info.PenFull, true, "the client sees the full pen")
		local detail = WheelView.detail(WheelConfig.ById.OrePrize, info)
		local note = `Ore Pen full: pays {Format.money(WheelView.oreFallback(info))} coins instead`
		T.eq(detail:sub(1, #note), note, "the ore row starts with the note (a cut row never hides it)")
		local result = w.spin(rollFor(7)).A
		T.falsy(result.DirtyOre)
		T.eq(result.Coins, WheelView.oreFallback(info), "the server pays what the row said")
		-- a free pen, room for golems, or nothing known: no note
		local clear = WheelView.info({ Golems = { Owned = {} }, StorageCount = 0, PenCapacity = 30 }, false)
		T.eq(clear.PenFull, false)
		T.eq(clear.GolemRoom, GolemConfig.InventoryCap)
		for _, segment in WheelConfig.Segments do
			T.falsy(string.find(WheelView.detail(segment, clear), "full: pays", 1, true), segment.Id .. ": no note")
			T.falsy(
				string.find(WheelView.detail(segment, WheelView.info(nil, false)), "full: pays", 1, true),
				segment.Id .. ": unknown, no note"
			)
		end
	end)

	withWheel("Wheel: Buy answers Full when the golem inventory has no room", function(w)
		fillGolems(w)
		local before = #w.replies
		WheelService._test.action(w.player, "Buy", { Count = 5 })
		local reply = w.replies[#w.replies]
		T.truthy(#w.replies > before)
		T.eq(reply.Event, "PurchasePrompt")
		T.eq(reply.A.Status, "Full", "a bought spin couldn't be used")
		T.truthy(WheelService.inventoryBlocks(w.data))
		table.remove(w.data.Golems.Owned)
		T.falsy(WheelService.inventoryBlocks(w.data), "room again")
		WheelService._test.action(w.player, "Buy", { Count = 5 })
		T.eq(w.replies[#w.replies].A.Status, "ComingSoon", "id 0: offered again")
		-- the client says which Full it is
		local source = fs.readFile("src/client/Controllers/WheelController.luau")
		T.truthy(source:find("then WheelConfig.Reasons.InventoryFull else WheelConfig.Reasons.MaxSpins", 1, true), "the Full text")
	end)

	-- (review 269fd39 #2) golems from bought spins are Robux golems
	withWheel("Wheel: a bought spin's golem is saved Paid and Locked (the free spin's isn't)", function(w)
		-- the wheel's own opening (no capsule package)
		w.data.Wheel.Spins = 1
		local free = w.spin(rollFor(3), 0.0).A
		T.eq(free.Paid, false)
		local freeGolem = GolemConfig.find(w.data.Golems, free.Golem.Id)
		T.falsy(freeGolem.Paid, "a free spin's golem is not paid")
		T.falsy(freeGolem.Locked)
		local bought = w.spin(rollFor(3), 0.0).A
		T.eq(bought.Paid, true)
		local paidGolem = GolemConfig.find(w.data.Golems, bought.Golem.Id)
		T.eq(paidGolem.Paid, true, "Paid")
		T.eq(paidGolem.Locked, true, "Locked")
		-- through the real capsule package: the same, and its opening says PaidSpin
		local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
		WheelService._test.setCapsules(CapsuleService :: any)
		local sources: { string } = {}
		CapsuleService.onOpened(function(_p: any, info: any)
			table.insert(sources, info.Source)
		end)
		local ok, err = pcall(function()
			w.data.Wheel.Spins = 1
			w.data.Wheel.NextSpinAt = NOW + DAY
			local result = w.spin(rollFor(8)).A
			T.eq(result.Paid, true)
			local golem = GolemConfig.find(w.data.Golems, result.Golem.Id)
			T.eq(golem.Paid, true, "Paid (CapsuleService)")
			T.eq(golem.Locked, true, "Locked (CapsuleService)")
			T.eq(sources[#sources], "PaidSpin", "analytics: from a paid spin")
			w.now += DAY
			local again = w.spin(rollFor(3)).A
			T.eq(again.Paid, false)
			T.falsy(GolemConfig.find(w.data.Golems, again.Golem.Id).Paid, "the free spin's golem")
			T.eq(sources[#sources], "Free")
		end)
		CapsuleService._test.reset()
		if not ok then
			error(err, 0)
		end
	end)

	T.test("Wheel: Migrations keep bought spins whole and sane (idempotent)", function()
		local cases: { { any } } = {
			{ "none", 0 },
			{ -3, 0 },
			{ 0 / 0, 0 },
			{ "x", 0 },
			{ 2.7, 2 },
			{ 12, 12 },
			{ 1e12, WheelConfig.MaxSavedSpins },
		}
		for _, case in cases do
			local data = deepCopy(DataTemplate)
			data.Wheel.Spins = if case[1] == "none" then nil else case[1]
			Migrations.run(data, NOW)
			T.eq(data.Wheel.Spins, case[2], `Spins {tostring(case[1])}`)
			local again = deepCopy(data)
			local report = Migrations.run(again, NOW)
			T.eq(again.Wheel.Spins, data.Wheel.Spins, "idempotent")
			T.eq(report.Dropped, 0, "nothing more to repair")
		end
	end)

	T.test("Wheel: Fast Spin is a saved setting (off by default)", function()
		T.eq(SettingsConfig.Defaults.FastSpin, false)
		T.eq(DataTemplate.Settings.FastSpin, false)
		T.eq(SettingsConfig.sanitize(nil).FastSpin, false)
		T.eq(SettingsConfig.sanitize({ FastSpin = true }).FastSpin, true)
		T.eq(SettingsConfig.sanitize({ FastSpin = "yes" }).FastSpin, false, "junk: the default")
		T.falsy(SettingsConfig.equal(SettingsConfig.sanitize({ FastSpin = true }), SettingsConfig.sanitize(nil)), "a change is sent")
		T.eq(SettingsConfig.merge({ Music = 0.2 }, { FastSpin = true }).Music, 0.2, "the other settings stay")
	end)

	---------------------------------------------------------------- the EmberChest prompt

	withWheel("Wheel: the EmberChest gets one Spin & Win prompt that opens the wheel screen", function(w)
		local model = Instance.new("Model")
		model.Name = "EmberChest"
		local chest = Instance.new("Part")
		chest.Name = "Chest"
		chest.Size = Vector3.new(4.6, 2.6, 3)
		chest.CFrame = CFrame.new(0, 2, 0)
		chest.Parent = model
		model.PrimaryPart = chest
		WheelService._test.hookChest(model)
		WheelService._test.hookChest(model)
		local points = 0
		for _, child in chest:GetChildren() do
			if child.Name == WheelService.PointName then
				points += 1
				local prompt = child:FindFirstChild(WheelService.PromptName)
				T.truthy(prompt, "prompt")
				T.eq(prompt.ActionText, "Spin & Win")
				T.eq(prompt.HoldDuration, 0)
			end
		end
		T.eq(points, 1, "hooked once")
		WheelService._test.open(w.player, chest)
		local reply = w.replies[#w.replies]
		T.eq(reply.Event, "OpenUI")
		T.eq(reply.A, "Wheel")
		T.eq(reply.B.Chest, chest)
	end)

	---------------------------------------------------------------- WheelView (pure)

	T.test("WheelView: percent and countdown texts", function()
		T.eq(WheelView.percent(0.3), "30%")
		T.eq(WheelView.percent(0.12), "12%")
		T.eq(WheelView.percent(1 / 3), "33.3%")
		T.eq(WheelView.percent(0.005), "0.5%")
		T.eq(WheelView.percent(0.0012), "0.12%")
		T.eq(WheelView.percent(0.165), "16.5%")
		T.eq(WheelView.percent(0 / 0), "0%")
		T.eq(WheelView.countdown(13 * 3600 + 42 * 60 + 10), "13:42:10")
		T.eq(WheelView.countdown(0), "00:00:00")
		T.eq(WheelView.countdown(-5), "00:00:00")
		T.eq(WheelView.countdown(59.2), "00:01:00", "rounds up: never 0 while waiting")
		T.eq(WheelView.duration(600), "10 min")
		T.eq(WheelView.duration(7200), "2 h")
	end)

	T.test("WheelView: the disc stops with the won segment under the pointer", function()
		local count = #WheelConfig.Segments
		for index = 1, count do
			T.eq(WheelView.segmentAt(WheelView.restAngle(index, count), count), index, "rest " .. index)
			for _, from in { 0, 37, 359.9, 1234.5 } do
				for _, jitter in { -0.5, 0, 0.5 } do
					local target = WheelView.spinTarget(from, index, count, WheelView.Turns, jitter)
					T.eq(WheelView.segmentAt(target, count), index, `segment {index} from {from}`)
					T.truthy(target - from >= WheelView.Turns * 360, "at least the full turns")
					T.truthy(target - from < (WheelView.Turns + 1) * 360 + 1e-6, "not more than one extra turn")
				end
			end
		end
		T.near(WheelView.ease(0), 0)
		T.near(WheelView.ease(1), 1)
		T.truthy(WheelView.ease(0.5) > 0.5, "fast start, slow stop")
	end)

	T.test("WheelView: the odds rows are exact and say what each segment pays", function()
		local info = {
			NoCapsules = false,
			Income = 640,
			Ore = { BlasterLevel = 1, BestIncome = 0, Vip = false },
			TripleLucky = false,
		}
		local rows = WheelView.rows(info)
		T.eq(#rows, #WheelConfig.Segments)
		local total = 0
		for i, row in rows do
			local segment = WheelConfig.Segments[i]
			T.eq(row.Id, segment.Id)
			T.eq(row.Chance, WheelView.percent(segment.Odds))
			T.truthy(#row.Detail > 0, "detail " .. row.Id)
			total += segment.Odds
		end
		T.near(total, 1, 1e-9)
		-- the ore prize lists its own odds (a day-1 player: Bronze, the Quarry's Rare ore)
		local ore = rows[WheelConfig.ById.OrePrize.Index]
		for _, line in WheelConfig.oreOdds(info.Ore) do
			T.truthy(ore.Detail:find(WheelView.percent(line.Chance), 1, true), "ore odds in the row")
		end
		T.truthy(ore.Detail:find("Bronze"), "Bronze for a new player")
		-- coins at this player's income
		T.truthy(rows[1].Detail:find("76.8K", 1, true), "2 min x $640/s")
		-- capsules with their rarity odds, Triple Lucky changes them
		local lucky = table.clone(info)
		lucky.TripleLucky = true
		local plain = rows[WheelConfig.ById.StoneCapsule.Index].Detail
		local boosted = WheelView.rows(lucky)[WheelConfig.ById.StoneCapsule.Index].Detail
		T.truthy(plain ~= boosted, "the boosted odds show")
		T.truthy(boosted:find("Triple Lucky on"), "says so")
		-- the substitutes' wheel
		local restricted = table.clone(info)
		restricted.NoCapsules = true
		local subRows = WheelView.rows(restricted)
		T.eq(subRows[2].Id, "TripleLuckyCoins")
		T.eq(subRows[2].Label, "More Coins", "its own name next to Coins")
		T.truthy(subRows[1].Label ~= subRows[2].Label)
		-- a capsule lists the exact chance of EVERY golem in it (Triple Lucky as the player has it)
		for _, segment in WheelConfig.Segments do
			local row = rows[segment.Index]
			if segment.Kind == "Capsule" then
				local odds = CapsuleConfig.odds(segment.Capsule, false)
				T.eq(#row.Lines, #odds, "every golem of " .. segment.Id)
				for i, line in odds do
					T.eq(row.Lines[i].Name, GolemConfig.ById[line.Golem].Name)
					T.eq(row.Lines[i].Chance, WheelView.percent(line.Chance))
				end
			else
				T.eq(row.Lines, nil)
			end
		end
		local luckyLines = WheelView.rows(lucky)[WheelConfig.ById.CrystalCapsule.Index].Lines
		local luckyOdds = CapsuleConfig.odds("Crystal", true)
		T.eq(luckyLines[#luckyLines].Chance, WheelView.percent(luckyOdds[#luckyOdds].Chance), "Triple Lucky's odds")
	end)

	T.test("WheelView: one-line details are cut to fit, the card has the whole text", function()
		local long = "A free Stone Capsule: Common 80% · Uncommon 16.5% · Rare 2.9% · Epic 0.5% · Legendary 0.05%"
		local cut = WheelView.truncate(long, 14, 200)
		T.truthy(#cut < #long and cut:sub(-3) == "...", "cut")
		T.truthy(#cut * 14 * 0.56 <= 200 + 1e-6, "fits")
		T.eq(WheelView.truncate("Short", 14, 200), "Short")
		local refs = WheelView.build(false)
		WheelView.layout(refs, 1280, 684)
		local info = {
			NoCapsules = false,
			Income = 640,
			Ore = { BlasterLevel = 4, BestIncome = 900, Vip = false },
			TripleLucky = false,
		}
		WheelView.setRows(refs, WheelView.rows(info))
		WheelView.showInfo(refs, "StoneCapsule")
		T.truthy(refs.Info.Visible)
		T.eq(refs.InfoId, "StoneCapsule")
		T.eq(refs.InfoText.Text, refs.RowData.StoneCapsule.Detail, "the whole text")
		local labels = 0
		for _, child in refs.InfoLines:GetChildren() do
			if child:IsA("TextLabel") then
				labels += 1
			end
		end
		T.eq(labels, #CapsuleConfig.odds("Stone", false))
		WheelView.hideInfo(refs)
		T.falsy(refs.Info.Visible)
		T.eq(refs.InfoId, nil)
	end)

	T.test("WheelView: the prize card's text for every kind", function()
		local cases = {
			{ Kind = "Coins", Amount = 2500 },
			{ Kind = "Boost", Boost = "TripleLucky", Seconds = 600 },
			{ Kind = "Capsule", Capsule = "Stone", Golem = { Id = 1, Kind = GolemConfig.List[1].Id } },
			{ Kind = "Capsule", Capsule = "Crystal", Coins = 900 },
			{ Kind = "Ore", DirtyOre = true },
			{ Kind = "Ore", Coins = 300 },
			{ Kind = "Shards", Amount = 25 },
		}
		for _, result in cases do
			local prize, detail = WheelView.prizeText(result)
			T.truthy(#prize > 0 and #detail > 0, "texts for " .. result.Kind)
		end
		local prize = WheelView.prizeText({ Kind = "Capsule", Capsule = "Stone", Golem = { Id = 1, Kind = GolemConfig.List[1].Id } })
		T.truthy(prize:find(GolemConfig.List[1].Name, 1, true), "the golem's name")
	end)

	T.test("WheelView: the pie's edge bars never spill over a segment edge", function()
		local refs = WheelView.build(false)
		local count = #refs.SegmentIds
		T.eq(count, #WheelConfig.Segments)
		local step = 360 / count
		local spilled = 0
		local bars = 0
		for _, child in refs.Disc:GetChildren() do
			if child:IsA("Frame") and child.ZIndex == 3 then
				bars += 1
				-- the outer side of an edge bar lies on an edge ray: its centre is half a
				-- bar width from the nearest edge ray (disc scale)
				local cx, cy = child.Position.X.Scale - 0.5, child.Position.Y.Scale - 0.5
				local angle = math.deg(math.atan2(cx, -cy)) % 360
				local width = child.Size.X.Scale
				local best = math.huge
				for i = 0, count - 1 do
					local edge = math.rad(i * step - step / 2)
					local ex, ey = math.sin(edge), -math.cos(edge)
					-- distance of the bar centre from the edge line (through the centre)
					local d = math.abs(cx * ey - cy * ex)
					if (cx * ex + cy * ey) > 0 then
						best = math.min(best, d)
					end
				end
				if math.abs(best - width / 2) > 1e-6 then
					spilled += 1
				end
				T.truthy(angle == angle, "angle")
			end
		end
		T.eq(bars, 2 * count, "two edge bars per segment")
		T.eq(spilled, 0)
		T.eq(#refs.Labels, count)
	end)

	local function midInfo(): any
		return {
			NoCapsules = false,
			Income = 640,
			Ore = { BlasterLevel = 4, BestIncome = 900, Vip = false },
			TripleLucky = false,
		}
	end

	-- A gui's box in its parent's offsets (offset positions and sizes only).
	local function box(gui: any): { X: number, Y: number, W: number, H: number }
		local s = gui.Size
		return {
			X = gui.Position.X.Offset - gui.AnchorPoint.X * s.X.Offset,
			Y = gui.Position.Y.Offset - gui.AnchorPoint.Y * s.Y.Offset,
			W = s.X.Offset,
			H = s.Y.Offset,
		}
	end
	local function overlap(a: any, b: any): boolean
		return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
	end

	T.test("WheelView: every screen fits, nothing overlaps, touch targets are 44 pt", function()
		-- (uiScale, maxW, maxH) in design units: a 568 x 320 pt and a 667 x 375 pt phone, PCs, a TV
		local screens = {
			{ Name = "phone 568x320", Compact = true, Scale = 0.62, W = 568 / 0.62, H = (320 - 58) / 0.62 },
			{ Name = "phone 667x375", Compact = true, Scale = 0.62, W = 667 / 0.62, H = (375 - 58) / 0.62 },
			{ Name = "PC 1280x720", Compact = false, Scale = 1, W = 1280, H = 720 - 36 },
			{ Name = "PC 1920x1080", Compact = false, Scale = 1.25, W = 1920 / 1.25, H = (1080 - 36) / 1.25 },
			{ Name = "TV", Compact = true, Scale = 1.25, W = 1920 / 1.25, H = (1080 - 36) / 1.25 },
		}
		for _, screen in screens do
			local name = screen.Name
			local refs = WheelView.build(screen.Compact)
			WheelView.setRows(refs, WheelView.rows(midInfo()))
			WheelView.layout(refs, screen.W, screen.H)
			local size = refs.Panel.Size
			T.truthy(size.X.Offset <= screen.W and size.Y.Offset <= screen.H, `{name}: everything fits`)
			local wheel = refs.WheelBox.Size.X.Offset
			T.truthy(wheel >= 200, `{name}: a readable wheel ({wheel})`)
			T.truthy(refs.WheelBox.Position.Y.Offset + wheel + 72 <= size.Y.Offset, `{name}: the SPIN banner under the wheel fits`)
			-- the cards beside the wheel, inside the box, clear of the wheel and of each other
			local wheelBox = box(refs.WheelBox)
			local buy = box(refs.Buy)
			T.truthy(refs.JackpotShown, `{name}: room for the jackpot card`)
			local jackpot = box(refs.Jackpot)
			for cardName, card in { Buy = buy, Jackpot = jackpot } do
				T.truthy(card.X >= 0 and card.Y >= 0, `{name}: {cardName} inside (top left)`)
				T.truthy(card.X + card.W <= size.X.Offset and card.Y + card.H <= size.Y.Offset, `{name}: {cardName} inside`)
				T.falsy(overlap(card, wheelBox), `{name}: {cardName} clear of the wheel`)
			end
			T.falsy(overlap(buy, jackpot), `{name}: the cards apart`)
			-- the BUY SPINS card holds its rows, Details and Fast Spin
			local fast = box(refs.FastSpin)
			local details = box(refs.Details)
			T.truthy(fast.Y + fast.H <= buy.H and details.Y + details.H <= buy.H, `{name}: Details and Fast Spin in the card`)
			for _, row in refs.BuyRows do
				local r = box(row.Frame)
				T.truthy(r.Y + r.H <= details.Y, `{name}: x{row.Count} above Details`)
				T.truthy(row.Button.Size.X.Offset <= r.W, `{name}: x{row.Count}'s price in its row`)
			end
			-- the jackpot tiles fit their card
			local grid = refs.JackpotTiles:FindFirstChildOfClass("UIGridLayout")
			local count = 0
			for _, child in refs.JackpotTiles:GetChildren() do
				if child:IsA("Frame") then
					count += 1
				end
			end
			local columns = grid.FillDirectionMaxCells
			local rowsN = math.ceil(count / columns)
			local tile = grid.CellSize.Y.Offset
			local gap = grid.CellPadding.Y.Offset
			T.truthy(rowsN * tile + (rowsN - 1) * gap <= refs.JackpotTiles.Size.Y.Offset, `{name}: every golem tile in the card`)
			T.truthy(
				columns * grid.CellSize.X.Offset + (columns - 1) * grid.CellPadding.X.Offset <= refs.JackpotTiles.Size.X.Offset,
				`{name}: tiles wide`
			)
			-- the X: at the wheel's top right, its red square off the painted faces, clear of the cards
			local close = box(refs.Close)
			local face = refs.Close:FindFirstChild("Face")
			local extra = (close.W - face.Size.X.Offset) / 2
			local cx, cy = wheelBox.X + wheel / 2, wheelBox.Y + wheel / 2
			local left, bottom = close.X + extra, close.Y + extra + face.Size.Y.Offset
			T.truthy(left > cx and bottom < cy, `{name}: the X at the top right`)
			local dx, dy = left - cx, cy - bottom
			T.truthy(math.sqrt(dx * dx + dy * dy) >= wheel / 2 * WheelView.DiscShare, `{name}: the X off the faces`)
			T.falsy(overlap(close, jackpot), `{name}: the X clear of the jackpot card`)
			T.truthy(close.Y >= -8, `{name}: the X on screen`)
			if screen.Compact and screen.Scale <= 0.62 then
				local s = screen.Scale
				T.truthy((refs.Spin.Parent :: any).Size.Y.Offset * s >= 44 and refs.Spin.Size.Y.Offset * s >= 44, `{name}: SPIN is 44 pt`)
				T.truthy(close.H * s >= 44 and close.W * s >= 44, `{name}: X is 44 pt`)
				for count2, button in refs.BuyButtons do
					T.truthy(button.Size.Y.Offset * s >= 44, `{name}: x{count2}'s price button is 44 pt`)
				end
				T.truthy(details.H * s >= 44, `{name}: Details is 44 pt`)
				T.truthy(fast.H * s >= 44 and fast.W * s >= 44, `{name}: Fast Spin is 44 pt`)
				T.truthy(refs.OddsBuy.Size.Y.Offset * s >= 44, `{name}: the buy step's price button is 44 pt`)
				T.truthy(refs.OddsClose.Size.Y.Offset * s >= 44, `{name}: the odds window's X is 44 pt`)
				T.truthy(refs.InfoClose.Size.Y.Offset * s >= 44, `{name}: the card's X is 44 pt`)
				T.truthy(refs.ResultOk.Size.Y.Offset * s >= 44, `{name}: OK is 44 pt`)
			end
			-- the odds window: on screen, all 8 rows in view, no scrolling (phones: a 2 x 4 grid of 44 pt tiles)
			local card = refs.OddsCard.Size
			T.truthy(card.X.Offset <= screen.W and card.Y.Offset <= screen.H, `{name}: the odds window fits`)
			local odds = refs.Odds
			T.truthy(odds.CanvasSize.Y.Offset <= odds.Size.Y.Offset, `{name}: every row in view`)
			T.falsy(refs.More.Visible, `{name}: nothing hidden below`)
			if screen.Compact and screen.Scale <= 0.62 then
				local cell = odds:FindFirstChildOfClass("UIGridLayout").CellSize
				T.truthy(cell.Y.Offset * screen.Scale >= 44, `{name}: a row is 44 pt to tap`)
			end
			-- the prize card over the wheel's lower half, inside
			local result = box(refs.Result)
			T.truthy(result.Y >= 0 and result.Y + result.H <= size.Y.Offset, `{name}: the prize card fits`)
			T.truthy(result.Y >= wheelBox.Y + wheel * 0.3, `{name}: the won segment stays in view under the pointer`)
			T.truthy(refs.ResultOk.Size.Y.Offset + 60 <= result.H, `{name}: OK in the card`)
			-- the biggest details card (a capsule's 14 golems) fits its card
			WheelView.showOdds(refs)
			WheelView.showInfo(refs, "StoneCapsule")
			local lines = refs.InfoLines
			T.truthy(
				lines.Position.Y.Offset + 7 * lines:FindFirstChildOfClass("UIGridLayout").CellSize.Y.Offset <= refs.Info.Size.Y.Offset,
				`{name}: the golem odds fit the card`
			)
			refs.Gui:Destroy()
		end
		-- a screen too narrow for both cards: the jackpot hides (Details lists it)
		local narrow = WheelView.build(true)
		WheelView.layout(narrow, 600, 600)
		T.falsy(narrow.JackpotShown, "a narrow screen: no jackpot card")
		T.falsy(narrow.Jackpot.Visible)
		T.truthy(narrow.Panel.Size.X.Offset <= 600, "the rest fits")
		T.truthy(narrow.WheelBox.Size.X.Offset >= 220, "the wheel keeps its size")
		-- a list longer than its box says so
		local short = WheelView.build(false)
		WheelView.layout(short, 1280, 420)
		WheelView.setRows(
			short,
			WheelView.rows({
				NoCapsules = false,
				Income = 0,
				Ore = { BlasterLevel = 1, BestIncome = 0, Vip = false },
				TripleLucky = false,
			})
		)
		T.truthy(short.More.Visible, "more below")
	end)

	T.test("WheelView: SPIN (n), the free spin line and Fast Spin", function()
		T.eq(WheelView.spinCount(true, 0), 1)
		T.eq(WheelView.spinCount(true, 2), 3)
		T.eq(WheelView.spinCount(false, 0), 0)
		T.eq(WheelView.spinCount(false, 5), 5)
		T.eq(WheelView.spinCount(false, 0 / 0), 0, "junk")
		local refs = WheelView.build(false)
		local label = refs.Spin:FindFirstChild("Label")
		WheelView.setReady(refs, true, 0, false, 2)
		T.eq(label.Text, "SPIN (3)", "the free one + 2 bought")
		T.eq(refs.SpinCount, 3)
		T.eq(refs.Status.Text, "FREE SPIN READY!")
		T.truthy(refs.Spin:GetAttribute("Ready"))
		WheelView.setReady(refs, false, 14 * 60 + 44, false, 0)
		T.eq(label.Text, "SPIN (0)")
		T.eq(refs.Status.Text, "FREE SPIN IN 00:14:44")
		T.falsy(refs.Spin:GetAttribute("Ready"), "grey: nothing to spin")
		WheelView.setReady(refs, false, 3600, false, 4)
		T.eq(label.Text, "SPIN (4)", "bought spins while the free one waits")
		T.truthy(refs.Spin:GetAttribute("Ready"))
		T.eq(refs.Status.Text, "FREE SPIN IN 01:00:00")
		WheelView.setReady(refs, false, 0, true)
		T.eq(label.Text, "SPINNING...")
		T.falsy(refs.Spin:GetAttribute("Ready"))
		-- Fast Spin: ~1.2 s instead of 5 s, fewer turns, the same landing
		T.eq(WheelView.spinSeconds(false), WheelConfig.SpinSeconds)
		T.eq(WheelConfig.SpinSeconds, 5)
		T.near(WheelView.spinSeconds(true), 1.2, 1e-9)
		T.truthy(WheelView.spinTurns(true) >= 1 and WheelView.spinTurns(true) < WheelView.spinTurns(false))
		local count = #WheelConfig.Segments
		for index = 1, count do
			local target = WheelView.spinTarget(123, index, count, WheelView.spinTurns(true), 0.3)
			T.eq(WheelView.segmentAt(target, count), index, "a fast spin lands on " .. index)
		end
		T.falsy(refs.Fast)
		WheelView.setFast(refs, true)
		T.truthy(refs.Fast)
		T.eq(refs.FastCheck:GetAttribute("On"), true, "the box is ticked")
		T.eq(refs.FastSpin:GetAttribute("On"), true)
		WheelView.setFast(refs, false)
		T.eq(refs.FastCheck:GetAttribute("On"), false)
		-- the controller: the screen disc and the lobby wheel use the same time and turns; the box is saved
		local source = fs.readFile("src/client/Controllers/WheelController.luau")
		T.truthy(source:find("local seconds = WheelView.spinSeconds(fast)", 1, true), "Fast Spin's time")
		T.truthy(source:find("landLobby(segment.Index, jitter, seconds, turns)", 1, true), "the lobby wheel lands the same way")
		T.truthy(source:find('SettingsController.set("FastSpin", fast)', 1, true), "saved with the settings")
		T.truthy(
			source:find("WheelView.setReady(view, isReady(), secondsLeft(), busy, usableSpins())", 1, true),
			"SPIN (n) counts the bought spins"
		)
		refs.Gui:Destroy()
	end)

	T.test("WheelView: the buy step shows every segment's odds and pay before the price", function()
		for _, compact in { true, false } do
			local refs = WheelView.build(compact)
			WheelView.setRows(refs, WheelView.rows(midInfo()))
			if compact then
				WheelView.layout(refs, 568 / 0.62, (320 - 58) / 0.62)
			else
				WheelView.layout(refs, 1280, 684)
			end
			T.falsy(refs.OddsCard.Visible, "closed at first")
			WheelView.showBuy(refs, 5)
			T.truthy(refs.OddsCard.Visible and refs.OddsDim.Visible, "the buy step is open")
			T.eq(refs.BuyPack, 5)
			T.truthy(refs.OddsBuy.Visible, "its price button")
			T.eq(refs.OddsBuy:GetAttribute("Product"), "WheelSpins5")
			local amount = refs.OddsBuy:FindFirstChild("Amount", true)
			local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
			T.eq(amount.Text, Pop.priceWords(99), "the price") -- (the round look: "R$99")
			T.truthy(string.find(refs.OddsTitle.Text, "5 SPINS", 1, true), "the pack in the title")
			-- all 8 segments: the exact chance and what each pays this player, in view
			local shown = 0
			for _, segment in WheelConfig.segments(false) do
				local row = refs.Rows[segment.Id]
				T.truthy(row and row.Visible ~= false, segment.Id .. " listed")
				T.eq(row:FindFirstChild("Chance").Text, WheelView.percent(segment.Odds), segment.Id .. " chance")
				local detail = row:FindFirstChild("Detail")
				local full = WheelView.detail(segment, midInfo())
				T.truthy(#detail.Text >= 20, segment.Id .. ": what it pays")
				T.eq(full:sub(1, 12), detail.Text:sub(1, 12), segment.Id .. ": this player's pay")
				shown += 1
			end
			T.eq(shown, 8)
			T.truthy(refs.Odds.CanvasSize.Y.Offset <= refs.Odds.Size.Y.Offset, "no scrolling to see them")
			-- the coins at this player's income show on a PC row (and on a phone tile, two lines)
			T.truthy(string.find(refs.Rows.Coins:FindFirstChild("Detail").Text, "76.8K", 1, true), "the coins row says $76.8K now")
			-- Details is the same list without a price
			WheelView.showOdds(refs)
			T.falsy(refs.OddsBuy.Visible)
			T.eq(refs.BuyPack, nil)
			T.eq(refs.OddsTitle.Text, "ALL ODDS")
			WheelView.hideOdds(refs)
			T.falsy(refs.OddsCard.Visible)
			refs.Gui:Destroy()
		end
		-- the controller sends "Buy" only from the buy step's own button (after the odds)
		local source = fs.readFile("src/client/Controllers/WheelController.luau")
		local _, sends = string.gsub(source, 'Net.send%("WheelAction", "Buy"', "")
		T.eq(sends, 1, "one place sends Buy")
		local confirmAt = source:find("confirmBuy = function()", 1, true)
		local sendAt = source:find('Net.send("WheelAction", "Buy"', 1, true)
		local openAt = source:find("openBuy = function(count: number)", 1, true)
		T.truthy(confirmAt and sendAt and openAt and sendAt > confirmAt, "Buy is sent from confirmBuy")
		T.truthy(source:find("WheelView.showBuy(view, count)", 1, true), "a price button opens the buy step")
		T.truthy(source:find("view.OddsBuy.Activated:Connect(function()\n\t\tconfirmBuy()", 1, true), "the buy step's button buys")
		T.truthy(source:find("if restricted() then", openAt, true), "restricted: no buy step")
	end)

	T.test("WheelView: restricted players see no BUY SPINS rows", function()
		local refs = WheelView.build(true)
		WheelView.layout(refs, 667 / 0.62, (375 - 58) / 0.62)
		WheelView.setBuy(refs, false)
		for _, row in refs.BuyRows do
			T.truthy(row.Frame.Visible, "x" .. row.Count .. " offered")
		end
		T.falsy(refs.BuyNote.Visible)
		WheelView.setBuy(refs, true)
		for _, row in refs.BuyRows do
			T.falsy(row.Frame.Visible, "x" .. row.Count .. " hidden")
		end
		T.truthy(refs.BuyNote.Visible, "a note says why")
		-- the controller: unknown policy counts as restricted
		local source = fs.readFile("src/client/Controllers/WheelController.luau")
		T.truthy(source:find("return player:GetAttribute(RESTRICTED_ATTRIBUTE) ~= false", 1, true), "unknown = restricted")
		T.truthy(source:find("WheelView.setBuy(view, restricted())", 1, true), "the rows follow the policy")
		refs.Gui:Destroy()
	end)

	T.test("WheelView: the jackpot card shows the Crystal Capsule's golem odds", function()
		local segment, lines = WheelView.jackpot(false)
		T.eq(segment.Id, WheelConfig.JackpotId)
		T.eq(segment.Capsule, "Crystal")
		local odds = CapsuleConfig.odds("Crystal", false)
		T.eq(#lines, #odds)
		local refs = WheelView.build(false)
		local tiles = {}
		for _, child in refs.JackpotTiles:GetChildren() do
			if child:IsA("Frame") then
				tiles[child.LayoutOrder] = child
			end
		end
		for i, line in odds do
			local tile = tiles[i]
			T.truthy(tile, "a tile for golem " .. i)
			T.eq(tile:FindFirstChild("Chance").Text, WheelView.percent(line.Chance), line.Golem .. " chance")
			T.eq(tile:FindFirstChild("Icon"):GetAttribute("Icon"), WheelView.golemIcon(line.Golem), line.Golem .. " picture")
			-- no uploaded picture yet: the name instead (never an emoji)
			T.truthy(tile:FindFirstChild("Name"), line.Golem .. ": its name stands in")
		end
		T.truthy(string.find(refs.JackpotFooter.Text, WheelView.percent(segment.Odds), 1, true), "its chance on the wheel")
		T.eq(WheelView.golemIcon("PebbleGolem"), "golem_PebbleGolem")
		T.eq(WheelView.golemIcon("RoseKnight"), "golem_RoseKnight", "the sheet lists the renamed golems by their new ids")
		-- Triple Lucky changes the tiles
		local _, lucky = WheelView.jackpot(true)
		T.truthy(lucky[#lucky].Chance ~= lines[#lines].Chance, "the boosted odds")
		refs.Gui:Destroy()
	end)

	T.test("WheelView: text only, no emoji anywhere (owner)", function()
		local function isEmoji(cp: number): boolean
			return cp >= 0x1F000
				or (cp >= 0x2600 and cp <= 0x27BF)
				or (cp >= 0x2B00 and cp <= 0x2BFF)
				or cp == 0xFE0F
				or (cp >= 0x2190 and cp <= 0x21FF)
		end
		local function scan(root: any, label: string)
			for _, d in root:GetDescendants() do
				if d:IsA("TextLabel") or d:IsA("TextButton") then
					for _, cp in utf8.codes(d.Text) do
						T.falsy(isEmoji(cp), `{label}: "{d.Text}" ({d.Name})`)
					end
				end
			end
		end
		for _, compact in { false, true } do
			local refs = WheelView.build(compact)
			WheelView.setRows(refs, WheelView.rows(midInfo()))
			WheelView.layout(refs, 1280, 684)
			WheelView.showBuy(refs, 10)
			WheelView.showInfo(refs, "CrystalCapsule")
			WheelView.showResult(refs, "Big prize", "detail", WheelView.faceColor(1))
			WheelView.setBuy(refs, true)
			scan(refs.Gui, if compact then "phone wheel" else "PC wheel")
			refs.Gui:Destroy()
		end
		for _, scale in { 0.62, 1.25 } do
			local chip = WheelView.buildChip(scale)
			scan(chip.Gui, "chip")
			T.eq(chip.Button:FindFirstChild("Label").Text, "FREE SPIN!")
			T.truthy(chip.Icon:IsA("Frame"), "the drawn wheel mark, not a picture or an emoji")
			chip.Gui:Destroy()
		end
	end)

	T.test("WheelView: the FREE SPIN! chip sits right of the teleport bar", function()
		for _, scale in { 0.62, 1, 1.25 } do
			local layout = TeleportView.layout(scale)
			local barHalf = (TeleportView.barWidth(layout, 3) + 44 + layout.Gap) / 2
			local offset = WheelView.chipOffset(scale)
			T.truthy(offset.X > barHalf, "clear of the bar at " .. scale)
			local chip = WheelView.buildChip(scale)
			T.falsy(chip.Gui.Enabled, "hidden until the controller shows it")
			T.eq(chip.Button:FindFirstChild("Glyph"), nil, "no gamepad shortcut of its own (the D-pad is the side menu's)")
			local holder = chip.Button.Parent
			local width = holder.Size.X.Offset
			local screenHalf = 568 / 0.62 / 2
			if scale <= 0.62 then
				T.truthy(offset.X + width <= screenHalf, "on screen on a small phone")
				T.truthy(holder.Size.Y.Offset * scale >= 44, "44 pt to tap")
			end
		end
	end)

	T.test("WheelView: the chip only shows over the HUD", function()
		T.truthy(WheelView.chipVisible(true, false, false, false), "ready, nothing else on screen")
		T.truthy(WheelView.chipVisible(true, false, false, false, false), "the tutorial bubble elsewhere (PC, TV)")
		T.falsy(WheelView.chipVisible(true, false, false, true), "not over the minigame / a close-up / build mode")
		T.falsy(WheelView.chipVisible(true, true, false, false), "not while the wheel is open")
		T.falsy(WheelView.chipVisible(true, false, true, false), "not while a spin is in flight")
		T.falsy(WheelView.chipVisible(false, false, false, false), "not before the spin is ready")
		T.falsy(WheelView.chipVisible(true, false, false, false, true), "not while the touch tutorial bubble has its spot")
	end)

	T.test("WheelView: the chip follows the bar on every screen width (icon-only bar under 600 pt)", function()
		local Vector2 = (require("@lune/roblox") :: any).Vector2
		for _, screen in
			{
				{ Name = "phone 568x320", Size = Vector2.new(568, 320) },
				{ Name = "phone 667x375", Size = Vector2.new(667, 375) },
				{ Name = "phone 844x390", Size = Vector2.new(844, 390) },
				{ Name = "tablet 1024x768", Size = Vector2.new(1024, 768) },
				{ Name = "PC 1280x720", Size = Vector2.new(1280, 720) },
				{ Name = "PC 1920x1080", Size = Vector2.new(1920, 1080) },
			}
		do
			local scale = math.clamp(math.min(screen.Size.Y / 720, screen.Size.X / 1100), 0.62, 1.25)
			local w = screen.Size.X / scale
			-- the bar as TeleportController lays it out (screen width in pt)
			local bar = TeleportView.layout(scale, screen.Size.X)
			local barRight = w / 2 + (TeleportView.barWidth(bar, 3) + 44 + bar.Gap) / 2
			local at, size = WheelView.chipRect(scale, screen.Size)
			T.truthy(at.X >= barRight, `{screen.Name}: right of the bar`)
			T.le(at.X - barRight, 16, `{screen.Name}: right after the bar's end, not floating`)
			T.le(at.X + size.X, w, `{screen.Name}: on screen`)
			T.eq(at.Y, 10, `{screen.Name}: in the top row`)
			-- buildChip / placeChip put it there
			local chip = WheelView.buildChip(scale, screen.Size.X)
			local holder = chip.Button.Parent
			T.near(holder.Position.X.Offset, at.X - w / 2, 1e-3, `{screen.Name}: built where chipRect says`)
			WheelView.placeChip(chip, 1, nil)
			WheelView.placeChip(chip, scale, screen.Size.X)
			T.near(holder.Position.X.Offset, at.X - w / 2, 1e-3, `{screen.Name}: placed again for the screen`)
			T.eq(holder.Size.X.Offset, size.X)
			chip.Gui:Destroy()
		end
		-- 568 pt: the icon-only bar is 114 units shorter than the compact one, so the chip moves in by half of that
		local small = WheelView.chipOffset(0.62, 568)
		local wide = WheelView.chipOffset(0.62, 667)
		T.eq(wide.X - small.X, 57, "the chip sits at the icon-only bar's end")
		-- the controller passes the screen width and the tutorial flag
		local fs = require("@lune/fs")
		local source = fs.readFile("src/client/Controllers/WheelController.luau")
		T.truthy(source:find("WheelView.buildChip(HudController.uiScale(), screenWidth())", 1, true), "built for the screen width")
		T.truthy(
			source:find("WheelView.placeChip(c, HudController.uiScale(), screenWidth())", 1, true),
			"placed again on a new screen size"
		)
		T.truthy(source:find("WheelView.chipVisible(ready, open, busy, busyScreen, tutorial)", 1, true), "reads the tutorial bubble")
		T.truthy(source:find("tutorial.onTopRowChanged(updateChip)", 1, true), "steps aside the moment the bubble comes")
	end)
end
