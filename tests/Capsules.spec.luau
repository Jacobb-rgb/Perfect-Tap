-- Golem capsules and golem pets (step 7) under Lune: CapsuleService (coin
-- opens: one atomic quote / roll / spend / grant, every refusal answered and
-- harmless, Triple Lucky with its grace, the Royal capsule's PurchasePrompt
-- and stored prompt state, paid-random-items policy, free wheel capsules,
-- step 8 grants past the cap, the stall prompt, a fuzz run where coins and
-- golems always add up), GolemService (equip / unequip / best / lock /
-- delete, the followers attribute, junk input), and the views (exact odds
-- on cards and on the stall's board, prices = the server's, Royal hidden
-- where restricted / "Coming soon" while not live, phone touch targets,
-- buttons inside their panels, the portraits). Save data, players, Net and
-- PolicyService are small fakes; EconomyService and Bonuses run for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local Policy = Loader.requirePath("ServerScriptService.Server.Policy")
	local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
	local GolemService = Loader.requirePath("ServerScriptService.Server.Services.GolemService")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
	local GolemView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GolemView")

	local NOW = 1_800_000_000
	local caps = CapsuleService._test
	local Reasons = CapsuleConfig.Reasons

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
		local p: any = { UserId = userId, Name = "Waker" .. userId, DisplayName = "Waker" .. userId, Parent = true, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	-- A fake Random whose NextNumber() comes from a list, then from a seeded Rng.
	local function fakeRandom(values: { number }?, seed: number?): any
		local rng = Rng.new(seed or 7)
		local i = 0
		return {
			NextNumber = function(_self: any): number
				i += 1
				if values and values[i] then
					return values[i]
				end
				return rng:next()
			end,
		}
	end

	local function setup(opts: any?): any
		local w: any = { notes = {}, changed = 0, opened = {}, prompted = {} }
		w.player = fakePlayer(701)
		w.other = fakePlayer(702)
		w.data = deepCopy(DataTemplate)
		w.data.Coins = 1e9
		w.loaded = true
		w.restricted = if opts and opts.Restricted ~= nil then opts.Restricted else false
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
		patch(DataService, "changed", function(p)
			w.changed += 1
			Bonuses.invalidate(p)
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		caps.reset()
		caps.setClock(function()
			return NOW
		end)
		w.values = nil
		caps.setRandom(function(_p)
			return fakeRandom(w.values, 11)
		end)
		caps.setPrompter(function(p, id)
			table.insert(w.prompted, { Player = p, Id = id })
		end)
		caps.setPlayers(function()
			return { w.player, w.other }
		end)
		CapsuleService.onOpened(function(p, info)
			table.insert(w.opened, { Player = p, Info = info })
		end)
		Policy._test.reset()
		Policy._test.setFetcher(function()
			return { ArePaidRandomItemsRestricted = w.restricted, IsPaidItemTradingAllowed = false }
		end)
		Bonuses._test.setClock(function()
			return NOW
		end)
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

	local function withWorld(name: string, fn: (any) -> (), opts: any?)
		T.test(name, function()
			local w = setup(opts)
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function notes(w: any, name: string, player: any?): { any }
		local out = {}
		for _, note in w.notes do
			if note.Name == name and (player == nil or note.Player == player) then
				table.insert(out, note)
			end
		end
		return out
	end

	-- Sends one CapsuleAction and returns the one answer it got (name, payload).
	local function act(w: any, action: any, arg: any): (string, any)
		local before = #w.notes
		caps.action(w.player, action, arg)
		local answers = {}
		for i = before + 1, #w.notes do
			local note = w.notes[i]
			if
				note.Player == w.player and (note.Name == "CapsuleResult" or note.Name == "ActionResult" or note.Name == "PurchasePrompt")
			then
				table.insert(answers, note)
			end
		end
		T.eq(#answers, 1, "exactly one answer per request")
		return answers[1].Name, answers[1].A
	end

	local function refused(w: any, arg: any, reason: string, label: string, action: any?)
		local coins = w.data.Coins
		local count = GolemConfig.count(w.data.Golems)
		local nextId = w.data.Golems.NextId
		local name, answer = act(w, action or "Open", arg)
		T.eq(name, "ActionResult", label .. ": an ActionResult")
		T.eq(answer.Action, "Capsule", label)
		T.eq(answer.Ok, false, label .. ": refused")
		T.eq(answer.Reason, reason, label .. ": reason")
		T.truthy(Reasons[reason], label .. ": the reason has a text")
		T.eq(w.data.Coins, coins, label .. ": coins kept")
		T.eq(GolemConfig.count(w.data.Golems), count, label .. ": no golem added")
		T.eq(w.data.Golems.NextId, nextId, label .. ": no id used")
	end

	local function fill(data: any, n: number, kind: string?, overCap: boolean?)
		for _ = 1, n do
			GolemConfig.add(data.Golems, kind or "PebbleGolem", overCap)
		end
	end

	---------------------------------------------------------------- pure helpers

	T.test("Capsules: the odds lines are CapsuleConfig's exact odds and sum to 1", function()
		for _, capsule in CapsuleConfig.List do
			for _, lucky in { false, true } do
				local lines = CapsuleView.oddsLines(capsule.Id, lucky)
				local config = CapsuleConfig.odds(capsule.Id, lucky)
				T.eq(#lines, #config, capsule.Id .. " one line per golem")
				local sum = 0
				local from = Rarity.ById[capsule.LuckyFrom].Order
				for i, line in lines do
					T.eq(line.Golem, config[i].Golem)
					T.eq(line.Chance, config[i].Chance, "exact chance")
					T.eq(line.Text, CapsuleView.percent(line.Chance))
					T.eq(line.Lucky, lucky and GolemConfig.order(line.Golem) >= from, "x3 only on lucky golems while lucky")
					T.eq(line.Bonus, GolemConfig.describe(line.Golem))
					sum += line.Chance
				end
				T.near(sum, 1, 1e-9, capsule.Id .. " sums to 1")
			end
		end
	end)

	T.test("Capsules: chances are shown exactly (three significant digits)", function()
		T.eq(CapsuleView.percent(0.25), "25%")
		T.eq(CapsuleView.percent(0.231865), "23.19%")
		T.eq(CapsuleView.percent(0.0007), "0.07%")
		T.eq(CapsuleView.percent(0.000465), "0.0465%")
		T.eq(CapsuleView.percent(0.012), "1.2%")
		T.eq(CapsuleView.percent(1), "100%")
		T.eq(CapsuleView.percent(0), "0%")
		T.eq(CapsuleView.percent(0 / 0), "0%")
		-- every shown chance is within 0.5 % (relative) of the real one
		for _, capsule in CapsuleConfig.List do
			for _, line in CapsuleView.oddsLines(capsule.Id, true) do
				local shown = tonumber(line.Text:sub(1, -2)) / 100
				T.truthy(math.abs(shown - line.Chance) <= line.Chance * 0.005, line.Golem .. " " .. line.Text)
			end
		end
	end)

	---------------------------------------------------------------- coin capsules

	withWorld("Capsules: a coin open spends once and grants every golem in the same step", function(w)
		w.data.BlasterLevel = 5
		w.data.Coins = 100000
		local price = CapsuleConfig.price("Stone", 3, 5)
		T.eq(price, 2500 * 5 * 3, "x3 at blaster level 5")
		w.values = { 0.1, 0.5, 0.999 }
		local name, result = act(w, "Open", { Capsule = "Stone", Count = 3 })
		T.eq(name, "CapsuleResult")
		T.eq(result.Capsule, "Stone")
		T.eq(result.Count, 3)
		T.eq(result.Lucky, false)
		T.eq(#result.Golems, 3)
		T.eq(w.data.Coins, 100000 - price, "paid once")
		T.eq(GolemConfig.count(w.data.Golems), 3)
		for i, g in result.Golems do
			T.eq(g.Id, i, "ids in order")
			T.eq(g.Kind, CapsuleConfig.roll("Stone", false, w.values[i]), "the roll's golem")
			T.eq(w.data.Golems.Owned[i].Kind, g.Kind, "saved")
			T.falsy(w.data.Golems.Owned[i].Paid, "coin golems are not Paid")
		end
		T.eq(w.data.Golems.NextId, 4)
		T.eq(w.data.Stats.CapsulesOpened, 3)
		T.truthy(w.changed >= 2, "DataService.changed after the spend and the grant")
		T.eq(#w.opened, 1, "onOpened")
		T.eq(w.opened[1].Info.Source, "Coins")
		T.eq(w.opened[1].Info.Price, price)
		-- x10 pays 9 capsules
		local before = w.data.Coins
		w.data.Coins = 1e9
		before = w.data.Coins
		local _, ten = act(w, "Open", { Capsule = "Crystal", Count = 10 })
		T.eq(#ten.Golems, 10)
		T.eq(before - w.data.Coins, CapsuleConfig.price("Crystal", 10, 5))
		T.eq(CapsuleConfig.price("Crystal", 10, 5), 750000 * 5 * 9, "x10 = 9 capsules' price")
		T.eq(w.data.Stats.CapsulesOpened, 13)
	end)

	withWorld("Capsules: every refusal answers once and changes nothing", function(w)
		refused(w, { Capsule = "Gravel", Count = 1 }, "BadCapsule", "unknown capsule")
		refused(w, { Capsule = 5, Count = 1 }, "BadCapsule", "not a string")
		refused(w, { Capsule = string.rep("S", 100), Count = 1 }, "BadCapsule", "long string")
		refused(w, "Stone", "BadCapsule", "not a table")
		refused(w, nil, "BadCapsule", "nothing")
		refused(w, { Capsule = "Stone", Count = 2 }, "BadCount", "count 2")
		refused(w, { Capsule = "Stone", Count = 0 / 0 }, "BadCount", "NaN")
		refused(w, { Capsule = "Stone", Count = 3.5 }, "BadCount", "fraction")
		refused(w, { Capsule = "Stone", Count = math.huge }, "BadCount", "inf")
		refused(w, { Capsule = "Stone", Count = "10" }, "BadCount", "string count")
		local big = {}
		for i = 1, 50 do
			big[i] = i
		end
		big.Capsule = "Stone"
		big.Count = 1
		refused(w, big, "BadCapsule", "huge table")
		refused(w, { Capsule = "Stone", Count = 1 }, "BadCapsule", "other action", "Spin")
		w.data.Coins = CapsuleConfig.price("Stone", 3, w.data.BlasterLevel) - 1
		refused(w, { Capsule = "Stone", Count = 3 }, "NoCoins", "one coin short")
		w.data.Coins = 1e9
		fill(w.data, GolemConfig.InventoryCap - 2)
		refused(w, { Capsule = "Stone", Count = 3 }, "InventoryFull", "only 2 places")
		local _, ok = act(w, "Open", { Capsule = "Stone", Count = 1 })
		T.eq(#ok.Golems, 1, "one still fits")
		w.loaded = false
		refused(w, { Capsule = "Stone", Count = 1 }, "BadCapsule", "save not loaded")
	end)

	withWorld("Capsules: Triple Lucky rolls the boosted odds (with a short grace after it ends)", function(w)
		-- a roll that gives a Rare+ golem only with Triple Lucky
		local roll: number? = nil
		for r = 0, 0.9999, 0.0005 do
			local plain = CapsuleConfig.roll("Stone", false, r)
			local lucky = CapsuleConfig.roll("Stone", true, r)
			if plain ~= lucky and GolemConfig.order(lucky) >= 3 then
				roll = r
				break
			end
		end
		T.truthy(roll, "found a deciding roll")
		local r = roll :: number
		local function openOne(): any
			w.values = { r }
			Bonuses.invalidate(w.player)
			local _, result = act(w, "Open", { Capsule = "Stone", Count = 1 })
			return result
		end
		w.data.Boosts.TripleLuckyUntil = NOW + 100
		local on = openOne()
		T.eq(on.Lucky, true)
		T.eq(on.Golems[1].Kind, CapsuleConfig.roll("Stone", true, r), "boosted roll")
		w.data.Boosts.TripleLuckyUntil = NOW - (CapsuleService.LuckyGrace - 1)
		T.eq(openOne().Lucky, true, "within the grace")
		w.data.Boosts.TripleLuckyUntil = NOW - (CapsuleService.LuckyGrace + 1)
		local off = openOne()
		T.eq(off.Lucky, false, "after the grace")
		T.eq(off.Golems[1].Kind, CapsuleConfig.roll("Stone", false, r), "plain roll")
		T.truthy(BoostConfig.Kinds.TripleLucky ~= nil)
	end)

	withWorld("Capsules: Legendary and Mythic golems are announced to the other players", function(w)
		local text = caps.announce(w.player, { "PebbleGolem", "StormcoreTitan", "EmberImp" })
		T.eq(text, "Waker701 woke a Legendary Stormcore Titan!")
		local told = notes(w, "Notify", w.other)
		T.eq(#told, 1, "the other player")
		T.eq(told[1].A.Kind, "Discovery")
		T.eq(told[1].A.Rarity, "Legendary")
		T.eq(#notes(w, "Notify", w.player), 0, "not the opener")
		T.eq(caps.announce(w.player, { "PebbleGolem", "RubyKnight" }), nil, "Epic: no announcement")
	end)

	---------------------------------------------------------------- paid random items

	withWorld("Capsules: the Royal capsule (Robux) is never granted here: PurchasePrompt", function(w)
		for _, count in CapsuleConfig.Counts do
			local coins = w.data.Coins
			local name, answer = act(w, "Open", { Capsule = "Royal", Count = count })
			T.eq(name, "PurchasePrompt")
			T.eq(answer.Product, CapsuleConfig.product("Royal", count))
			T.eq(answer.Status, "ComingSoon", "placeholder ids: Coming soon")
			T.eq(w.data.Coins, coins)
			T.eq(GolemConfig.count(w.data.Golems), 0, "nothing granted")
		end
		T.eq(#w.prompted, 0, "no MarketplaceService prompt for a placeholder")
		-- a live product prompts and remembers the Triple Lucky state the player saw
		local product = MonetizationConfig.Products.RoyalCapsule3
		local oldId = product.Id
		product.Id = 123456
		local ok, err = pcall(function()
			w.data.Boosts.TripleLuckyUntil = NOW + 60
			Bonuses.invalidate(w.player)
			local name, answer = act(w, "Open", { Capsule = "Royal", Count = 3 })
			T.eq(name, "PurchasePrompt")
			T.eq(answer.Status, "Prompted")
			T.eq(#w.prompted, 1)
			T.eq(w.prompted[1].Id, 123456)
			T.eq(CapsuleService.promptedLucky(w.player, "RoyalCapsule3"), true, "stored lucky")
			T.eq(GolemConfig.count(w.data.Golems), 0, "still nothing granted before the receipt")
			-- full inventory: "Full", no prompt
			fill(w.data, GolemConfig.InventoryCap - 2)
			local _, full = act(w, "Open", { Capsule = "Royal", Count = 3 })
			T.eq(full.Status, "Full")
			T.eq(#w.prompted, 1, "no second prompt")
		end)
		product.Id = oldId
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("Capsules: where paid random items are restricted, Royal answers Restricted", function(w)
		local name, answer = act(w, "Open", { Capsule = "Royal", Count = 1 })
		T.eq(name, "PurchasePrompt")
		T.eq(answer.Status, "Restricted")
		-- coin capsules are no paid random items while coins can't be bought with Robux
		T.falsy(MonetizationConfig.coinsBuyable(), "coin packs off")
		local _, result = act(w, "Open", { Capsule = "Stone", Count = 1 })
		T.eq(#result.Golems, 1, "a coin capsule opens")
		-- turning coin packs on makes coin capsules paid random items: refused
		MonetizationConfig.CoinPacksEnabled = true
		local ok, err = pcall(function()
			refused(w, { Capsule = "Stone", Count = 1 }, "Restricted", "coins buyable + restricted")
		end)
		MonetizationConfig.CoinPacksEnabled = false
		if not ok then
			error(err, 0)
		end
	end, { Restricted = true })

	withWorld("Capsules: a failing PolicyService counts as restricted (strict)", function(w)
		Policy._test.setFetcher(function()
			error("PolicyService down")
		end)
		local _, answer = act(w, "Open", { Capsule = "Royal", Count = 1 })
		T.eq(answer.Status, "Restricted")
	end)

	---------------------------------------------------------------- free and paid grants (other packages)

	withWorld("Capsules: grantFree (the wheel's prize) is free, marked Free and refused when full", function(w)
		local coins = w.data.Coins
		local result = CapsuleService.grantFree(w.player, "Crystal")
		T.truthy(result, "granted")
		T.eq(result.Free, true)
		T.eq(#result.Golems, 1)
		T.eq(w.data.Coins, coins, "free")
		T.eq(#notes(w, "CapsuleResult"), 1, "the client plays it")
		T.eq(w.opened[1].Info.Source, "Free")
		fill(w.data, GolemConfig.InventoryCap - 1)
		local none, reason = CapsuleService.grantFree(w.player, "Crystal")
		T.eq(none, nil)
		T.eq(reason, "InventoryFull")
		T.eq(GolemConfig.count(w.data.Golems), GolemConfig.InventoryCap)
	end)

	withWorld("Capsules: grantProduct (step 8 receipts) uses the prompted odds and may pass the cap", function(w)
		local product = MonetizationConfig.Products.RoyalCapsule10
		local oldId = product.Id
		product.Id = 777
		local ok, err = pcall(function()
			act(w, "Open", { Capsule = "Royal", Count = 10 }) -- prompted without Triple Lucky
			T.eq(CapsuleService.promptedLucky(w.player, "RoyalCapsule10"), false)
			-- the boost starts before the receipt: the receipt still uses the prompt's odds
			w.data.Boosts.TripleLuckyUntil = NOW + 600
			Bonuses.invalidate(w.player)
			fill(w.data, GolemConfig.MaxSaved - 4, nil, true)
			local result, missing = CapsuleService.grantProduct(w.player, "RoyalCapsule10")
			T.truthy(result)
			T.eq(result.Lucky, false, "the odds the player saw")
			T.eq(#result.Golems, 4, "up to MaxSaved")
			T.eq(missing, 6, "the rest is reported for compensation")
			T.eq(GolemConfig.count(w.data.Golems), GolemConfig.MaxSaved)
			for i = GolemConfig.MaxSaved - 3, GolemConfig.MaxSaved do
				T.eq(w.data.Golems.Owned[i].Paid, true, "paid golems are marked")
			end
			T.eq(CapsuleService.promptedLucky(w.player, "RoyalCapsule10"), nil, "the prompt is used up")
			-- old prompts are forgotten
			act(w, "Open", { Capsule = "Royal", Count = 10 })
			T.eq(CapsuleService.promptedLucky(w.player, "RoyalCapsule10", NOW + MonetizationConfig.PromptMemorySeconds + 1), nil)
		end)
		product.Id = oldId
		if not ok then
			error(err, 0)
		end
	end)

	---------------------------------------------------------------- fuzz

	withWorld("Capsules: fuzz: random requests never lose or duplicate coins or golems", function(w)
		local rng = Rng.new(4242)
		local spent = 0
		local woken = 0
		local ids: { [number]: boolean } = {}
		w.data.Coins = 5e7
		w.data.BlasterLevel = 3
		local capsules = { "Stone", "Crystal", "Royal", "Gravel", 7 }
		local counts = { 1, 3, 10, 2, 0 / 0, -1, 11 }
		for step = 1, 400 do
			local capsule = rng:pick(capsules)
			local count = rng:pick(counts)
			local coins = w.data.Coins
			local name, answer = act(w, if step % 37 == 0 then "Drop" else "Open", { Capsule = capsule, Count = count })
			if name == "CapsuleResult" then
				spent += coins - w.data.Coins
				T.eq(coins - w.data.Coins, CapsuleConfig.price(answer.Capsule, answer.Count, 3), "paid the quote")
				for _, g in answer.Golems do
					T.falsy(ids[g.Id], "unique id")
					ids[g.Id] = true
					woken += 1
				end
			else
				T.eq(w.data.Coins, coins, "a refusal costs nothing")
			end
			-- delete some now and then so the inventory doesn't stay full
			if step % 25 == 0 then
				local all = {}
				for _, entry in w.data.Golems.Owned do
					table.insert(all, entry.Id)
				end
				local n = math.min(#all, 40)
				if n > 0 then
					GolemConfig.delete(w.data.Golems, table.move(all, 1, n, 1, {}))
					woken -= n
				end
			end
			T.eq(GolemConfig.count(w.data.Golems), woken, "golems add up")
			T.le(GolemConfig.count(w.data.Golems), GolemConfig.InventoryCap, "never past the cap")
		end
		T.eq(5e7 - w.data.Coins, spent, "coins add up")
		T.truthy(spent > 0, "some opens went through")
	end)

	---------------------------------------------------------------- the stall

	withWorld("Capsules: the CapsuleStall gets one Capsules prompt in front of its capsule", function(w)
		local stall = Instance.new("Model")
		local base = Instance.new("Part")
		base.Name = "CapsuleMachine"
		base.Size = Vector3.new(0.5, 6.2, 6.2)
		base.CFrame = CFrame.new(-42, 1, 12) * CFrame.Angles(0, 0, math.pi / 2)
		base.Parent = stall
		stall.PrimaryPart = base
		local board = Instance.new("Part")
		board.Name = "OddsBoard"
		board.Size = Vector3.new(1.9, 3.9, 0.1)
		-- the stall's front faces +X here
		board.CFrame = CFrame.lookAt(Vector3.new(-37, 4, 18), Vector3.new(-30, 4, 18))
		board.Parent = stall
		caps.hookStall(stall)
		caps.hookStall(stall)
		local points = 0
		for _, child in base:GetChildren() do
			if child.Name == CapsuleService.PointName then
				points += 1
			end
		end
		T.eq(points, 1, "hooked once")
		local point = base:FindFirstChild(CapsuleService.PointName)
		local world = base.CFrame * point.CFrame
		T.truthy(world.Position.X > -42 + 3, "in front of the pedestal")
		T.near(world.Position.Y, 4, 0.01, "chest height")
		local prompt = point:FindFirstChild(CapsuleService.PromptName)
		T.truthy(prompt and prompt:IsA("ProximityPrompt"))
		T.eq(prompt.ActionText, "Capsules")
		T.eq(prompt.KeyboardKeyCode, roblox.Enum.KeyCode.F)
		T.eq(prompt.GamepadKeyCode, roblox.Enum.KeyCode.ButtonY)
		T.falsy(prompt.RequiresLineOfSight)
		caps.open(w.player, stall)
		local opened = notes(w, "OpenUI")
		T.eq(#opened, 1)
		T.eq(opened[1].A, "Capsules")
		T.truthy(opened[1].B.Stall == stall)
		w.loaded = false
		caps.open(w.player, stall)
		T.eq(#notes(w, "OpenUI"), 1, "not before the save is loaded")
	end)

	---------------------------------------------------------------- golem actions

	withWorld("Golems: equip, unequip, equip best, lock and delete through GolemAction", function(w)
		local g = w.data.Golems
		GolemConfig.add(g, "PebbleGolem") -- 1
		GolemConfig.add(g, "RubyKnight") -- 2
		GolemConfig.add(g, "EmberImp") -- 3
		GolemConfig.add(g, "HeartstoneColossus") -- 4
		GolemConfig.add(g, "CopperTinker") -- 5
		local function golem(action: any, arg: any): any
			local before = #w.notes
			GolemService._test.action(w.player, action, arg)
			local answers = {}
			for i = before + 1, #w.notes do
				if w.notes[i].Name == "ActionResult" then
					table.insert(answers, w.notes[i].A)
				end
			end
			T.eq(#answers, 1, "one ActionResult")
			T.eq(answers[1].Action, "Golem")
			return answers[1]
		end
		local attr = GolemConfig.EquippedAttribute
		T.eq(golem("Equip", { Id = 2 }).Ok, true)
		T.eq(w.player.attrs[attr], "RubyKnight", "followers attribute")
		golem("Equip", { Id = 1 })
		golem("Equip", { Id = 3 })
		local full = golem("Equip", { Id = 4 })
		T.eq(full.Ok, false)
		T.eq(full.Reason, "SlotsFull")
		T.eq(golem("Unequip", { Id = 1 }).Ok, true)
		T.eq(w.player.attrs[attr], "RubyKnight,EmberImp")
		T.eq(golem("Unequip", { Id = 1 }).Reason, "NotEquipped")
		T.eq(golem("EquipBest").Ok, true)
		T.eq(w.player.attrs[attr], "HeartstoneColossus,RubyKnight,EmberImp", "the 3 best")
		-- lock: locked golems are never deleted
		T.eq(golem("Lock", { Id = 4, Locked = true }).Ok, true)
		T.eq(g.Owned[4].Locked, true)
		T.eq(golem("Lock", { Id = 4, Locked = "yes" }).Reason, "BadLock")
		local deleted = golem("Delete", { Ids = { 4, 5 } })
		T.eq(deleted.Ok, true)
		T.eq(deleted.Count, 1, "only the unlocked one")
		T.truthy(GolemConfig.find(g, 4), "the locked one stays")
		T.falsy(GolemConfig.find(g, 5))
		T.eq(golem("Delete", { Ids = { 4 } }).Reason, "BadIds", "only locked golems named")
		T.eq(golem("Lock", { Id = 4, Locked = false }).Ok, true)
		T.eq(golem("Delete", { Ids = { 4 } }).Count, 1)
		T.eq(w.player.attrs[attr], "RubyKnight,EmberImp", "a deleted golem leaves its slot")
		-- junk
		T.eq(golem("Equip", { Id = "2" }).Reason, "BadGolem")
		T.eq(golem("Equip", { Id = 0 / 0 }).Reason, "BadGolem")
		T.eq(golem("Equip", { Id = 99 }).Reason, "BadGolem")
		T.eq(golem("Equip", "2").Reason, "BadGolem")
		T.eq(golem("Dance", {}).Reason, "BadGolem")
		T.eq(golem(42, nil).Ok, false)
		T.eq(golem("Delete", { Ids = "all" }).Reason, "BadIds")
		local many = {}
		for i = 1, GolemConfig.MaxDelete + 1 do
			many[i] = i
		end
		T.eq(golem("Delete", { Ids = many }).Reason, "BadIds", "too many ids")
		T.eq(golem("Delete", { Ids = { 1.5 } }).Reason, "BadIds")
		T.eq(GolemConfig.count(g), 3, "junk changed nothing")
		w.loaded = false
		T.eq(golem("Equip", { Id = 1 }).Ok, false, "no save: refused")
	end)

	---------------------------------------------------------------- views

	local function state(overrides: any?): any
		local s: any = {
			Coins = 50000,
			BlasterLevel = 2,
			Golems = { Owned = {}, Equipped = {}, NextId = 1 },
			Boosts = { TripleLuckyUntil = 0, HexaLuckyUntil = 0 },
			Bonuses = { GolemBond = 0 },
		}
		if overrides then
			for k, v in overrides do
				s[k] = v
			end
		end
		return s
	end

	local function cardOf(cards: { any }, id: string): any
		for _, card in cards do
			if card.Id == id then
				return card
			end
		end
		return nil
	end

	T.test("Capsules view: the cards quote what the server quotes", function()
		local s = state()
		local cards = CapsuleView.cards(s, 9000, false, NOW)
		local stone = cardOf(cards, "Stone")
		T.truthy(stone.Visible)
		for i, count in CapsuleConfig.Counts do
			local buy = stone.Buys[i]
			T.eq(buy.Count, count)
			T.eq(buy.Price, CapsuleConfig.price("Stone", count, 2), "price at the blaster level")
			T.eq(buy.PriceText, Format.money(buy.Price))
			T.eq(buy.CanBuy, 9000 >= buy.Price, "affordable " .. count)
			T.eq(buy.Reason, if 9000 >= buy.Price then nil else "NoCoins")
		end
		-- no room: InventoryFull, before the coins
		local full = state()
		fill(full, GolemConfig.InventoryCap - 1)
		local crowded = cardOf(CapsuleView.cards(full, 1e12, false, NOW), "Stone")
		T.eq(crowded.Buys[1].CanBuy, true, "one fits")
		T.eq(crowded.Buys[2].Reason, "InventoryFull")
		T.eq(crowded.Room, 1)
	end)

	T.test("Capsules view: Royal is hidden where restricted, 'Coming soon' while not live", function()
		local s = state()
		local open = CapsuleView.cards(s, 1e9, false, NOW)
		local royal = cardOf(open, "Royal")
		T.truthy(royal.Visible, "shown where allowed")
		T.eq(royal.Live, false, "placeholder ids")
		T.eq(royal.Note, MonetizationConfig.StatusText.ComingSoon, "Coming soon instead of buttons")
		for _, buy in royal.Buys do
			T.falsy(buy.CanBuy, "no Robux button works while not live")
		end
		T.truthy(#royal.Odds > 0, "its odds are shown anyway")
		local restricted = CapsuleView.cards(s, 1e9, true, NOW)
		T.falsy(cardOf(restricted, "Royal").Visible, "hidden where restricted")
		T.truthy(cardOf(restricted, "Stone").Visible, "coin capsules stay (coins can't be bought with Robux)")
		MonetizationConfig.CoinPacksEnabled = true
		local packs = CapsuleView.cards(s, 1e9, true, NOW)
		MonetizationConfig.CoinPacksEnabled = false
		T.falsy(cardOf(packs, "Stone").Visible, "coin capsules hidden too once coins can be bought")
		T.eq(#CapsuleView.visibleTabs(packs), 0)
	end)

	T.test("Capsules view: with Triple Lucky on, the cards show the boosted odds", function()
		local s = state({ Boosts = { TripleLuckyUntil = NOW + 125, HexaLuckyUntil = 0 } })
		local card = cardOf(CapsuleView.cards(s, 1e9, false, NOW), "Crystal")
		T.eq(card.Lucky, true)
		T.eq(card.LuckySeconds, 125)
		local boosted = CapsuleConfig.odds("Crystal", true)
		for i, line in card.Odds do
			T.eq(line.Chance, boosted[i].Chance)
		end
		T.truthy(CapsuleView.luckyText(card):find("2:05"), "time left")
		local off = cardOf(CapsuleView.cards(s, 1e9, false, NOW + 200), "Crystal")
		T.eq(off.Lucky, false, "ran out")
	end)

	T.test("Capsules view: the shop panel fills, switches tabs and fits phones (44 pt buttons)", function()
		for _, compact in { false, true } do
			local refs = CapsuleView.build(compact)
			local sizes = if compact then { { 1076, 547 }, { 916, 423 } } else { { 1280, 684 }, { 1100, 620 } }
			for _, size in sizes do
				CapsuleView.layout(refs, compact, size[1], size[2])
				local shown = CapsuleView.setCards(refs, CapsuleView.cards(state(), 1e9, true, NOW))
				T.eq(shown, "Stone", "the first visible tab")
				T.falsy(refs.Tabs.Royal.Parent.Visible, "Royal tab hidden (restricted)")
				local panel = refs.Panel.Size
				T.le(panel.X.Offset, size[1], "panel width fits")
				T.le(panel.Y.Offset, size[2], "panel height fits")
				for i, button in refs.Buttons do
					local holder = button.Parent
					T.truthy(holder.Visible, "OPEN button " .. i)
					local p = holder.Position
					T.truthy(
						p.X.Offset >= 0 and p.X.Offset + holder.Size.X.Offset <= refs.Left.Size.X.Offset + 0.5,
						"inside the left column"
					)
					T.le(p.Y.Offset + holder.Size.Y.Offset, refs.Left.Size.Y.Offset + 0.5, "above the column's end")
					T.truthy(button.Text:find("OPEN") and button.Text:find("%$"), "count and price")
				end
				local rows = 0
				for _, row in refs.Rows do
					if row.Frame.Visible then
						rows += 1
					end
				end
				T.eq(rows, #CapsuleConfig.odds("Stone", false), "one odds row per golem")
			end
			if compact then
				for _, target in CapsuleView.touchTargets(refs) do
					T.truthy(target.Size.Y.Offset * CapsuleView.PhoneScale >= CapsuleView.MinTouch - 0.5, target.Name .. " 44 pt tall")
					T.truthy(target.Size.X.Offset * CapsuleView.PhoneScale >= CapsuleView.MinTouch - 0.5, target.Name .. " 44 pt wide")
				end
			end
			-- Royal (allowed, not live): the note instead of the buttons
			refs.Tab = "Royal"
			CapsuleView.setCards(refs, CapsuleView.cards(state(), 1e9, false, NOW))
			T.truthy(refs.Note.Visible, "Coming soon")
			for _, button in refs.Buttons do
				T.falsy(button.Parent.Visible, "no Robux buttons")
			end
			-- nothing allowed: the empty text
			MonetizationConfig.CoinPacksEnabled = true
			local none = CapsuleView.setCards(refs, CapsuleView.cards(state(), 1e9, true, NOW))
			MonetizationConfig.CoinPacksEnabled = false
			T.eq(none, "")
			T.truthy(refs.Empty.Visible)
		end
	end)

	T.test("Capsules view: the opening overlay lays out on PC and phones", function()
		for _, compact in { false, true } do
			local o = CapsuleView.buildOpening(compact)
			local w, h = if compact then 916 else 1280, if compact then 423 else 684
			CapsuleView.layoutOpening(o, compact, w, h)
			CapsuleView.setPlate(o, "StarmetalSovereign", true)
			T.truthy(o.Plate.Visible)
			T.eq(o.PlateRarity.Text, "MYTHIC")
			T.truthy(o.PlateNew.Visible)
			local kinds = {
				"PebbleGolem",
				"RubyKnight",
				"EmberImp",
				"TinTumbler",
				"QuartzSprite",
				"CoalChomper",
				"GildedPorter",
				"SilverSquire",
				"JadeGardener",
				"MoonstoneOracle",
			}
			CapsuleView.setGrid(o, kinds, { [2] = true }, 10)
			T.eq(#o.Cells, 10)
			local cell = o.GridLayout.CellSize
			local perRow = math.floor((o.Grid.Size.X.Offset + 12) / (cell.X.Offset + 12))
			T.truthy(perRow >= 5, "5 per row")
			local rowsH = 2 * cell.Y.Offset + 12
			T.le(rowsH, o.Grid.Size.Y.Offset, "two rows fit")
			T.eq(CapsuleView.best(kinds), "MoonstoneOracle", "the rarest")
			if compact then
				for _, target in CapsuleView.openTargets(o) do
					T.truthy(target.Size.Y.Offset * CapsuleView.PhoneScale >= CapsuleView.MinTouch - 0.5, target.Name .. " 44 pt")
				end
			end
			for _, target in CapsuleView.openTargets(o) do
				T.le(target.Position.Y.Offset, h, target.Name .. " on screen")
			end
		end
	end)

	T.test("Capsules view: the stall's odds board shows the capsule's real odds per rarity", function()
		local gui = Instance.new("SurfaceGui")
		local old = Instance.new("TextLabel")
		old.Name = "Title"
		old.Text = "RARITIES"
		old.Parent = gui
		for _, capsule in CapsuleConfig.List do
			for _, lucky in { false, true } do
				CapsuleView.fillBoard(gui, capsule.Id, lucky)
				local title = gui:FindFirstChild("Title")
				T.eq(title.Text, string.upper(capsule.Name), "the old labels are gone")
				local odds = CapsuleConfig.rarityOdds(capsule.Id, lucky)
				for i, info in Rarity.List do
					local total = gui:FindFirstChild("Total" .. i)
					T.truthy(total, "row " .. i)
					if odds[info.Id] then
						T.eq(total.Text, CapsuleView.percent(odds[info.Id]), capsule.Id .. " " .. info.Id)
						local golems = gui:FindFirstChild("Golems" .. i)
						T.truthy(golems, "the golems of the rarity")
						for _, line in CapsuleView.oddsLines(capsule.Id, lucky) do
							if line.Rarity == info.Id then
								T.truthy(golems.Text:find(line.Text, 1, true), line.Golem .. " chance on the board")
							end
						end
					else
						T.eq(total.Text, "-", "a rarity the capsule doesn't hold")
					end
				end
				T.eq(gui:FindFirstChild("Subtitle").Text, if lucky then "TRIPLE LUCKY ODDS" else "ODDS PER CAPSULE")
			end
		end
	end)

	T.test("Golems view: cards sort equipped first, then the best; unknown kinds show ???", function()
		local s = state()
		local g = s.Golems
		GolemConfig.add(g, "PebbleGolem") -- 1
		GolemConfig.add(g, "DiamondDuke") -- 2
		GolemConfig.add(g, "EmberImp") -- 3
		table.insert(g.Owned, { Id = 4, Kind = "FutureGolem" })
		g.NextId = 5
		GolemConfig.add(g, "CopperTinker") -- 5
		g.Equipped = { 5 }
		g.Owned[1].Locked = true
		s.Bonuses.GolemBond = 0.1
		local cards = GolemView.cards(s)
		T.eq(#cards, 5)
		T.eq(cards[1].Id, 5, "equipped first")
		T.eq(cards[2].Kind, "DiamondDuke", "then the best")
		T.eq(cards[#cards].Kind, "FutureGolem", "unknown last")
		T.eq(cards[#cards].Name, "???")
		T.falsy(cards[#cards].Known)
		local pebble = nil
		for _, card in cards do
			if card.Id == 1 then
				pebble = card
			end
		end
		T.truthy(pebble.Locked)
		T.eq(cards[1].Bonus, GolemConfig.describe("CopperTinker", 0.1), "Golem Bond in the bonus")
		T.eq(GolemView.countText(s), `5 / {GolemConfig.InventoryCap}`)
		T.eq(#GolemView.equipped(s), 1)
		T.truthy(GolemView.totals(s):find("Mining speed"), "totals")
		local ids = GolemView.pickRarity(cards, "Common")
		T.eq(#ids, 0, "locked and equipped Commons are never picked")
		T.truthy(GolemView.confirmText(cards, { [5] = true, [3] = true }):find("1 of them is equipped"))
	end)

	T.test("Golems view: the inventory fills and fits phones (44 pt buttons)", function()
		local s = state()
		for i = 1, 12 do
			GolemConfig.add(s.Golems, GolemConfig.List[(i - 1) % #GolemConfig.List + 1].Id)
		end
		s.Golems.Equipped = { 1, 2 }
		for _, compact in { false, true } do
			local refs = GolemView.build(compact)
			local sizes = if compact then { { 1076, 547 }, { 916, 423 } } else { { 1280, 684 } }
			for _, size in sizes do
				GolemView.layout(refs, compact, size[1], size[2])
				local cards = GolemView.cards(s)
				GolemView.setCards(refs, cards, cards[3].Id, nil)
				GolemView.setEquipped(refs, GolemView.equipped(s), GolemView.totals(s))
				GolemView.setDetail(refs, cards[3])
				local n = 0
				for _ in refs.Cards do
					n += 1
				end
				T.eq(n, 12, "one card per golem")
				T.le(refs.Panel.Size.X.Offset, size[1])
				T.le(refs.Panel.Size.Y.Offset, size[2] + 1)
				-- detail buttons inside the detail column
				for _, b in { refs.Equip, refs.Lock, refs.Delete } do
					local holder = b.Parent
					T.le(holder.Position.X.Offset + holder.Size.X.Offset, refs.Detail.Size.X.Offset, b.Name .. " inside")
					T.le(holder.Position.Y.Offset + holder.Size.Y.Offset, refs.Detail.Size.Y.Offset, b.Name .. " above the end")
					T.truthy(holder.Position.Y.Offset >= refs.DetailBonus.Position.Y.Offset + 20, b.Name .. " under the texts")
				end
			end
			if compact then
				for _, target in GolemView.touchTargets(refs) do
					T.truthy(target.Size.Y.Offset * GolemView.PhoneScale >= GolemView.MinTouch - 0.5, target.Name .. " 44 pt tall")
				end
			end
			-- delete mode and removed golems
			GolemView.setDeleteMode(refs, true, 2)
			T.truthy(refs.DeleteBar.Visible)
			T.falsy(refs.Detail.Visible)
			T.eq(refs.DeleteConfirm.Text, "DELETE 2")
			GolemView.setCards(refs, {}, nil, {})
			T.truthy(refs.Empty.Visible)
			T.eq(next(refs.Cards), nil, "cards of deleted golems are gone")
		end
	end)

	T.test("Golems view: every golem has a portrait (and an unknown one too)", function()
		local holder = Instance.new("Frame")
		for _, golem in GolemConfig.List do
			local p = GolemView.portrait(holder, golem.Id, 100)
			T.truthy(p:FindFirstChild("Head") and p:FindFirstChild("Body") and p:FindFirstChild("Eye1"), golem.Id)
			T.truthy(#p:GetChildren() >= 14, golem.Id .. " has its gear")
		end
		local unknown = GolemView.portrait(holder, "FutureGolem", 100)
		T.truthy(unknown:FindFirstChild("Unknown"), "a ? face")
	end)
end
