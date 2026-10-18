-- The daily wheel (step 7): WheelService (the free spin: cooldown saved
-- before the prize, every prize kind and its fallbacks, the paid-random
-- substitutes, junk input, the EmberChest prompt) and WheelView's pure
-- parts (exact odds rows, percent / countdown texts, the disc angles that
-- put a segment under the pointer, the pie bars, phone layouts, the chip).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local WheelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WheelConfig")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PodiumService = Loader.requirePath("ServerScriptService.Server.Services.PodiumService")
	local WheelService = Loader.requirePath("ServerScriptService.Server.Services.WheelService")
	local WheelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")

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
			patch(Policy, "paidRandomRestricted", function()
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

	T.test("WheelView: phone layouts fit, touch targets are 44 pt", function()
		-- (uiScale, maxW, maxH) in design units: a 568 x 320 pt and a 667 x 375 pt phone, a PC, a TV
		local screens = {
			{ Compact = true, Scale = 0.62, W = 568 / 0.62, H = (320 - 58) / 0.62 },
			{ Compact = true, Scale = 0.62, W = 667 / 0.62, H = (375 - 58) / 0.62 },
			{ Compact = false, Scale = 1.25, W = 1920 / 1.25, H = (1080 - 36) / 1.25 },
			{ Compact = true, Scale = 1.25, W = 1920 / 1.25, H = (1080 - 36) / 1.25 },
		}
		for _, screen in screens do
			local refs = WheelView.build(screen.Compact)
			WheelView.layout(refs, screen.W, screen.H)
			local size = refs.Panel.Size
			T.truthy(size.X.Offset <= screen.W and size.Y.Offset <= screen.H, "the panel fits")
			local wheel = refs.WheelBox.Size.X.Offset
			T.truthy(wheel >= 200, "a readable wheel")
			T.truthy(refs.WheelBox.Position.Y.Offset + wheel + 72 <= size.Y.Offset, "the button under the wheel fits")
			if screen.Compact and screen.Scale <= 0.62 then
				local button = (refs.Spin.Parent :: any).Size.Y.Offset
				T.truthy(button * screen.Scale >= 44, "SPIN! is 44 pt")
				T.truthy(refs.Close.Parent.Size.Y.Offset * screen.Scale >= 44, "X is 44 pt")
			end
			local odds = refs.Odds
			T.truthy(odds.Position.X.Offset + odds.Size.X.Offset <= size.X.Offset, "the odds fit")
			-- all 8 rows in view, no scrolling (phones: a 2 x 4 grid of 44 pt tiles)
			local info = {
				NoCapsules = false,
				Income = 640,
				Ore = { BlasterLevel = 4, BestIncome = 900, Vip = false },
				TripleLucky = false,
			}
			WheelView.setRows(refs, WheelView.rows(info))
			T.truthy(odds.CanvasSize.Y.Offset <= odds.Size.Y.Offset, "every row in view")
			T.falsy(refs.More.Visible, "nothing hidden below")
			if screen.Compact and screen.Scale <= 0.62 then
				local cell = odds:FindFirstChildOfClass("UIGridLayout").CellSize
				T.truthy(cell.Y.Offset * screen.Scale >= 44, "a row is 44 pt to tap")
				T.truthy(refs.InfoClose.Parent.Size.Y.Offset * screen.Scale >= 44, "the card's X is 44 pt")
			end
			-- the biggest details card (a capsule's 14 golems) fits its card
			WheelView.showInfo(refs, "StoneCapsule")
			local lines = refs.InfoLines
			T.truthy(
				lines.Position.Y.Offset + 7 * lines:FindFirstChildOfClass("UIGridLayout").CellSize.Y.Offset <= refs.Info.Size.Y.Offset,
				"the golem odds fit the card"
			)
		end
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
		T.falsy(WheelView.chipVisible(true, false, false, true), "not over the minigame / Foundry moment / build mode")
		T.falsy(WheelView.chipVisible(true, true, false, false), "not while the wheel is open")
		T.falsy(WheelView.chipVisible(true, false, true, false), "not while a spin is in flight")
		T.falsy(WheelView.chipVisible(false, false, false, false), "not before the spin is ready")
		T.falsy(WheelView.chipVisible(true, false, false, false, true), "not while the touch tutorial bubble has its spot")
	end)

	T.test("WheelView: the chip follows the bar on every screen width (icon-only bar under 600 pt)", function()
		local Vector2 = (require("@lune/roblox") :: any).Vector2
		for _, screen in {
			{ Name = "phone 568x320", Size = Vector2.new(568, 320) },
			{ Name = "phone 667x375", Size = Vector2.new(667, 375) },
			{ Name = "phone 844x390", Size = Vector2.new(844, 390) },
			{ Name = "tablet 1024x768", Size = Vector2.new(1024, 768) },
			{ Name = "PC 1280x720", Size = Vector2.new(1280, 720) },
			{ Name = "PC 1920x1080", Size = Vector2.new(1920, 1080) },
		} do
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
		T.truthy(source:find("WheelView.placeChip(c, HudController.uiScale(), screenWidth())", 1, true), "placed again on a new screen size")
		T.truthy(source:find("WheelView.chipVisible(ready, open, busy, busyScreen, tutorial)", 1, true), "reads the tutorial bubble")
		T.truthy(source:find("tutorial.onTopRowChanged(updateChip)", 1, true), "steps aside the moment the bubble comes")
	end)
end
