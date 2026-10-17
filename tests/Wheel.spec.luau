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
			local w: any = { replies = {}, rolls = {}, scheduled = {}, income = 0, restricted = false, now = NOW }
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
			WheelService._test.setSchedule(function(seconds, fn)
				table.insert(w.scheduled, { Seconds = seconds, Fn = fn })
			end)
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
		-- already full: nothing is added (capped), the card says so
		w.now += DAY
		w.data.Boosts.HexaLuckyUntil = w.now + BoostConfig.MaxStackSeconds
		local full = w.spin(rollFor(6)).A
		T.eq(full.Boost, "HexaLucky")
		T.eq(full.Seconds, 0)
		T.eq(w.data.Boosts.HexaLuckyUntil, w.now + BoostConfig.MaxStackSeconds)
		local prize, detail = WheelView.prizeText(full)
		T.eq(prize, "Hexa Lucky")
		T.truthy(detail:find("full"), "explains the cap")
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
		-- the CapsuleResult waits until the screen wheel stopped
		T.eq(#w.scheduled, 1)
		T.truthy(w.scheduled[1].Seconds >= WheelConfig.SpinSeconds, "after the spin")
		w.scheduled[1].Fn()
		local opening = w.replies[#w.replies]
		T.eq(opening.Event, "CapsuleResult")
		T.eq(opening.A.Free, true)
		T.eq(opening.A.Count, 1)
		T.eq(opening.A.Golems[1].Id, golem.Id)
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
		T.eq(#w.scheduled, 0, "no opening")
	end)

	withWheel("Wheel: the Ore Prize puts a dirty Rare+ ore into the pen and keeps it secret", function(w)
		local result = w.spin(rollFor(7), 0.01).A
		T.eq(result.Kind, "Ore")
		T.eq(result.DirtyOre, true)
		T.eq(result.Ore, nil, "which ore stays secret")
		T.eq(#w.data.Storage, 1)
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
		-- the ore prize lists its own odds (a day-1 player: Gold)
		local ore = rows[WheelConfig.ById.OrePrize.Index]
		for _, line in WheelConfig.oreOdds(info.Ore) do
			T.truthy(ore.Detail:find(WheelView.percent(line.Chance), 1, true), "ore odds in the row")
		end
		T.truthy(ore.Detail:find("Gold"), "Gold for a new player")
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
		end
	end)

	T.test("WheelView: the FREE SPIN! chip sits right of the teleport bar", function()
		for _, scale in { 0.62, 1, 1.25 } do
			local layout = TeleportView.layout(scale)
			local barHalf = (TeleportView.barWidth(layout, 3) + 44 + layout.Gap) / 2
			local offset = WheelView.chipOffset(scale)
			T.truthy(offset.X > barHalf, "clear of the bar at " .. scale)
			local chip = WheelView.buildChip(scale)
			local holder = chip.Button.Parent
			local width = holder.Size.X.Offset
			local screenHalf = 568 / 0.62 / 2
			if scale <= 0.62 then
				T.truthy(offset.X + width <= screenHalf, "on screen on a small phone")
				T.truthy(holder.Size.Y.Offset * scale >= 44, "44 pt to tap")
			end
		end
	end)
end
