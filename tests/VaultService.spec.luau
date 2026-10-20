-- VaultService (the Blaster Vault shop) under Lune: the counter prompt,
-- prices and case looks from BlasterData, buying the next level only (in
-- order, coins only), every refusal with its VaultResult and no change, the
-- range, a double tap buys one level, broken payloads, and a fuzz run where
-- coins and levels always add up. Save data, players and Net are small
-- fakes; EconomyService runs for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local VaultService = Loader.requirePath("ServerScriptService.Server.Services.VaultService")

	local vault = VaultService._test

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

	local function fakePlayer(): any
		local p: any = { UserId = 777, Name = "Buyer", Parent = true, attrs = {} }
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.humanoid = { Health = 100 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name: string)
				return if name == "HumanoidRootPart" then p.root else nil
			end,
		}
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0 }
		w.player = fakePlayer()
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
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		vault.reset()
		-- the vault counter top, its customer side = +Z
		local counter = Instance.new("Part")
		counter.Size = Vector3.new(13, 0.24, 3.5)
		counter.CFrame = CFrame.new(0, 4.6, 104)
		counter.Parent = Instance.new("Model")
		vault.hookCounter(counter)
		w.counter = counter
		w.standAt = function(away: number)
			local p = (counter.CFrame * CFrame.new(0, 0, counter.Size.Z / 2 + away)).Position
			w.player.root.Position = p
			w.player.root.CFrame = CFrame.new(p)
		end
		w.standAt(3)
		w.restore = function()
			vault.reset()
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

	local function results(w: any): { any }
		local out = {}
		for _, note in w.notes do
			if note.Name == "VaultResult" then
				table.insert(out, note.A)
			end
		end
		return out
	end

	local function buy(w: any, payload: any): any
		local before = #results(w)
		vault.buy(w.player, payload)
		local list = results(w)
		T.eq(#list, before + 1, "exactly one VaultResult per request")
		return list[#list]
	end

	T.test("VaultService: prices and case looks come from BlasterData", function()
		T.eq(BlasterData.vaultPrice(1), nil, "level 1 is not sold")
		T.eq(BlasterData.vaultPrice(11), nil, "Coming soon is not sold")
		T.eq(BlasterData.vaultPrice(0.5), nil, "fractions are not levels")
		T.eq(BlasterData.vaultPrice(2.5), nil, "fractions are not levels")
		T.eq(BlasterData.vaultPrice(0 / 0), nil, "NaN is not a level")
		T.eq(BlasterData.vaultPrice("2"), nil, "strings are not levels")
		local last = 0
		for level = 2, BlasterData.MaxLevel do
			local price = BlasterData.vaultPrice(level)
			T.truthy(price, "level " .. level .. " has a price")
			T.eq(price, BlasterData.get(level).Recipe.Coins * BlasterData.Vault.PriceMultiplier, "level " .. level .. " price")
			T.truthy(price > last, "prices grow with the level")
			last = price
		end
		T.eq(#BlasterData.Vault.Ores, BlasterData.MaxLevel, "one case look per level")
		T.eq(BlasterData.vaultOre(1), "", "level 1 is the rusty starter")
		local lastOrder = 0
		for level = 2, BlasterData.MaxLevel do
			local ore = BlasterData.vaultOre(level)
			T.truthy(OreData.exists(ore), "level " .. level .. " case ore exists")
			-- the case colours follow the rarity (owner 2026-10-20): never a rarer ore below a commoner one
			local order = Rarity.ById[OreData.get(ore).Rarity].Order
			T.truthy(order >= lastOrder, `level {level}'s {ore} is at least as rare as the level below`)
			lastOrder = order
		end
		-- the ores the new 36-ore roster drops are never used
		local dropped = {
			"Ruby",
			"Azurium",
			"Emerald",
			"Verdantine",
			"Stormcore",
			"Bloodstone",
			"Solarite",
			"Voidstone",
			"Magmacore",
			"Skyglass",
			"Prismite",
			"Starmetal",
		}
		for _, id in BlasterData.Vault.Ores do
			T.falsy(table.find(dropped, id), id .. " stays in the new roster")
		end
	end)

	withWorld("VaultService: the counter gets one Blaster Vault prompt and opens the shop", function(w)
		local point = w.counter:FindFirstChild(VaultService.PointName)
		T.truthy(point, "prompt point")
		local prompt = point and point:FindFirstChild(VaultService.PromptName)
		T.truthy(prompt, "prompt")
		T.eq(prompt.KeyboardKeyCode, roblox.Enum.KeyCode.F, "F like the other counters (E grabs)")
		vault.hookCounter(w.counter)
		local count = 0
		for _, d in w.counter:GetDescendants() do
			if d.Name == VaultService.PromptName then
				count += 1
			end
		end
		T.eq(count, 1, "hooking twice keeps one prompt")
		vault.open(w.player, w.counter)
		T.eq(w.notes[#w.notes].Name, "OpenUI", "opens the shop")
		T.eq(w.notes[#w.notes].A, "Vault", "the Vault panel")
	end)

	withWorld("VaultService: buying the next level takes the coins and gives the blaster", function(w)
		-- enough for every level up to the top (4 x the forge curve)
		local start = 1e13
		w.data.Coins = start
		local r = buy(w, { Level = 2 })
		T.eq(r.Ok, true, "bought")
		T.eq(w.data.BlasterLevel, 2, "new level")
		T.eq(w.data.BlasterOre, BlasterData.vaultOre(2), "the case's ore look")
		T.eq(w.data.Coins, start - BlasterData.vaultPrice(2), "paid")
		T.eq(w.data.Stats.BlastersBought, 1, "counted")
		T.eq(r.Name, BlasterData.displayName(2, BlasterData.vaultOre(2)), "the name for the cinematic")
		T.truthy(w.changed > 0, "the save changed")
		-- all the way to the top, in order
		for level = 3, BlasterData.MaxLevel do
			T.eq(buy(w, { Level = level }).Ok, true, "level " .. level)
		end
		T.eq(w.data.BlasterLevel, BlasterData.MaxLevel, "top level")
		T.eq(buy(w, { Level = BlasterData.MaxLevel + 1 }).Reason, "Max", "nothing past the top")
	end)

	withWorld("VaultService: a Robux blaster gives the next level in its band, else only counts it (never refuses)", function(w)
		-- the STORE's bands (MonetizationConfig entries with Grant "BlasterLevel")
		local bandA = { Key = "BlasterNextA", Grant = "BlasterLevel", MinLevel = 2, MaxLevel = 4 }
		local bandD = { Key = "BlasterNextD", Grant = "BlasterLevel", MinLevel = 10, MaxLevel = 10 }
		w.data.BlasterLevel = 2
		w.data.Coins = 777
		T.eq(VaultService.paidStatus(w.data, bandA), "Prompt", "next level 3 is in band A")
		T.eq(VaultService.paidStatus(w.data, bandD), "Full", "band D is for LV 10 only")
		T.truthy(vault.grantPaid(w.player, w.data, bandA), "granted")
		T.eq(w.data.BlasterLevel, 3)
		T.eq(w.data.BlasterOre, BlasterData.vaultOre(3), "that level's case look")
		T.eq(w.data.Coins, 777, "no coins taken")
		T.eq(w.data.Stats.BlastersPaid, 1)
		T.eq(w.data.Stats.BlastersBought, 0, "a Vault (coins) buy counts elsewhere")
		T.eq(w.data.Stats.RunPaid, true, "this rebirth run is paid (no stars for it)")
		local r = results(w)[#results(w)]
		T.truthy(r.Ok and r.Paid and r.Level == 3, "the crate opening plays (Paid)")
		-- off band (a stale or client-made prompt): its Robux are banked, never a level from a cheaper band now
		-- (with no band entries in MonetizationConfig nothing converts: the credit just waits)
		w.data.BlasterLevel = 9
		bandA.Robux = 49
		T.eq(VaultService.paidStatus(w.data, bandA), "Full")
		T.truthy(vault.grantPaid(w.player, w.data, bandA), "the receipt is still taken (never a retry loop)")
		T.eq(w.data.BlasterLevel, 9, "band A never buys LV 10")
		T.eq(w.data.Stats.BlastersPaid, 1, "no lift without a band price to check")
		T.eq(w.data.Stats.BlasterCredit, 49, "banked")
		w.data.BlasterLevel = BlasterData.MaxLevel
		T.eq(VaultService.paidStatus(w.data, bandD), "Full", "the store hides it at the top")
		-- a save that isn't this player's live one is left to MonetizationService (not processed yet)
		T.falsy(vault.grantPaid(w.player, deepCopy(w.data), bandD))
		-- the coin Vault goes through the same setter
		w.data.BlasterLevel = 3
		w.data.Coins = 1e12
		w.data.Stats.RunPaid = false
		vault.buy(w.player, { Level = 4 })
		T.eq(w.data.BlasterLevel, 4)
		T.eq(w.data.Stats.BlastersBought, 1)
		T.eq(w.data.Stats.RunPaid, false, "coins don't mark the run paid")
	end)

	-- the STORE's four bands (they live in MonetizationConfig on ui/store), added for a test
	local function withBands(fn: () -> ())
		local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
		local bands = {
			{ Key = "TestBandA", Kind = "Product", Grant = "BlasterLevel", Id = 0, Robux = 49, MinLevel = 2, MaxLevel = 4 },
			{ Key = "TestBandB", Kind = "Product", Grant = "BlasterLevel", Id = 0, Robux = 99, MinLevel = 5, MaxLevel = 7 },
			{ Key = "TestBandC", Kind = "Product", Grant = "BlasterLevel", Id = 0, Robux = 199, MinLevel = 8, MaxLevel = 9 },
			{ Key = "TestBandD", Kind = "Product", Grant = "BlasterLevel", Id = 0, Robux = 399, MinLevel = 10, MaxLevel = 10 },
		}
		for _, band in bands do
			MonetizationConfig.Products[band.Key] = band :: any
		end
		local ok, err = pcall(fn, bands)
		for _, band in bands do
			MonetizationConfig.Products[band.Key] = nil
		end
		if not ok then
			error(err, 0)
		end
	end

	withWorld("VaultService: banked Robux buy start lifts only at the band price of the start they make", function(w)
		local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
		withBands(function(bands: any)
			local A, D = bands[1], bands[4]
			w.data.Rebirths = 1
			w.data.BlasterLevel = 9
			w.data.Stats.RunForged = 9
			-- a stale A (LV 2-4) at LV 9: 49 R$ make the start LV 2, priced like buying LV 2
			T.truthy(vault.grantPaid(w.player, w.data, A))
			T.eq(w.data.Stats.BlastersPaid, 1)
			T.eq(w.data.Stats.BlasterCredit, 0)
			T.eq(RebirthConfig.startFor(w.data), 2)
			-- a stale D (399 R$) at the top level: lifts at 49 + 49 + 99 + 99 + 99 (starts 3..7), 4 R$ left
			w.data.BlasterLevel = 10
			w.data.Stats.RunForged = 10
			T.truthy(vault.grantPaid(w.player, w.data, D))
			T.eq(w.data.BlasterLevel, 10)
			T.eq(w.data.Stats.BlastersPaid, 6)
			T.eq(w.data.Stats.BlasterCredit, 4)
			T.eq(RebirthConfig.startFor(w.data), 7)
			local note = w.notes[#w.notes]
			T.truthy(note.Name == "Notify" and string.find(note.A.Text, "LV 7", 1, true), "it says the new start")
			-- the cheapest band never buys a high start: start 8 costs a C (199)
			T.truthy(vault.grantPaid(w.player, w.data, A))
			T.eq(w.data.Stats.BlastersPaid, 6, "49 + 4 R$ don't make LV 8")
			T.eq(w.data.Stats.BlasterCredit, 53)
			-- past the cap (start LV 9) nothing more converts
			w.data.Stats.BlastersPaid = 8
			T.eq(VaultService.spendCredit(w.data), 0)
		end)
	end)

	withWorld("VaultService: the top level waits for the Foundry while a run has forged no rebirth level", function(w)
		local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
		withBands(function(bands: any)
			local D = bands[4]
			-- a lifted run: Robux levels start it at LV 9, nothing forged yet
			w.data.Rebirths = 3
			w.data.Stats.BlastersPaid = 8
			w.data.Stats.RunPaid = true
			w.data.Stats.RunForged = 0
			w.data.BlasterLevel = 9
			w.data.Coins = 1e13
			T.truthy(RebirthConfig.topBlocked(w.data))
			T.eq(VaultService.paidStatus(w.data, D), "Full", "the STORE doesn't sell LV 10")
			T.truthy(vault.grantPaid(w.player, w.data, D), "a stale receipt is still taken")
			T.eq(w.data.BlasterLevel, 9, "banked, not the top level")
			local r = buy(w, { Level = 10 })
			T.eq(r.Reason, "ForgeFirst", "the coin Vault waits too")
			T.eq(w.data.BlasterLevel, 9)
			-- forging LV 10 at the Foundry earns the rebirth
			w.data.BlasterLevel = 10
			w.data.Stats.RunForged = 10
			T.truthy(RebirthConfig.canRebirth(w.data))
			-- with a rebirth level forged, the top level is for sale
			w.data.BlasterLevel = 9
			w.data.Stats.RunForged = 7
			T.falsy(RebirthConfig.topBlocked(w.data))
			T.eq(VaultService.paidStatus(w.data, D), "Prompt")
		end)
	end)

	withWorld("VaultService: a Robux level on the first run keeps the levels the grace counted", function(w)
		local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
		withBands(function(bands: any)
			local C = bands[3]
			-- the first run: LV 7 from Vault cases, nothing forged; the grace counts LV 7
			w.data.BlasterLevel = 7
			T.eq(RebirthConfig.reachedOf(w.data), 7)
			T.truthy(vault.grantPaid(w.player, w.data, C))
			T.eq(w.data.BlasterLevel, 8)
			T.eq(RebirthConfig.reachedOf(w.data), 7, "the bought LV 8 pays nothing, LV 7 still counts")
			T.truthy(RebirthConfig.canRebirth(w.data), "the rebirth the player had stays")
			T.truthy(vault.grantPaid(w.player, w.data, C))
			T.eq(RebirthConfig.reachedOf(w.data), 7, "a second Robux level: still 7")
		end)
	end)

	withWorld("VaultService: refusals change nothing", function(w)
		w.data.Coins = 1e12
		w.data.BlasterLevel = 3
		local function refused(payload: any, reason: string)
			local coins, level, ore = w.data.Coins, w.data.BlasterLevel, w.data.BlasterOre
			local r = buy(w, payload)
			T.eq(r.Ok, false, reason .. " refused")
			T.eq(r.Reason, reason, "reason " .. reason)
			T.eq(w.data.Coins, coins, reason .. ": coins kept")
			T.eq(w.data.BlasterLevel, level, reason .. ": level kept")
			T.eq(w.data.BlasterOre, ore, reason .. ": look kept")
		end
		refused({ Level = 3 }, "Owned")
		refused({ Level = 2 }, "Owned")
		refused({ Level = 1 }, "Owned")
		refused({ Level = 5 }, "Locked")
		refused({ Level = 11 }, "BadLevel")
		refused({ Level = 4.5 }, "BadLevel")
		refused({ Level = 0 / 0 }, "BadLevel")
		refused({ Level = "4" }, "BadLevel")
		refused({}, "BadLevel")
		refused("nope", "BadLevel")
		w.data.Coins = BlasterData.vaultPrice(4) - 1
		refused({ Level = 4 }, "NoCoins")
		w.data.Coins = 1e12
		w.standAt(40)
		refused({ Level = 4 }, "TooFar")
		w.standAt(3)
		w.loaded = false
		local r = buy(w, { Level = 4 })
		T.eq(r.Reason, "NoData", "no save")
		w.loaded = true
		T.eq(buy(w, { Level = 4 }).Ok, true, "then it works")
	end)

	withWorld("VaultService: a double tap buys one level", function(w)
		w.data.Coins = BlasterData.vaultPrice(2) * 3
		T.eq(buy(w, { Level = 2 }).Ok, true, "first tap")
		local second = buy(w, { Level = 2 })
		T.eq(second.Ok, false, "second tap")
		T.eq(second.Reason, "Owned", "already owned")
		T.eq(w.data.Coins, BlasterData.vaultPrice(2) * 2, "paid once")
	end)

	withWorld("VaultService: refusal() matches what buy() does (the cards use it)", function(w)
		for current = 1, BlasterData.MaxLevel do
			for level = 1, BlasterData.MaxLevel + 1 do
				for _, coins in { 0, 1e15 } do
					w.data.BlasterLevel = current
					w.data.Coins = coins
					local expected = VaultService.refusal(level, current, coins)
					local r = buy(w, { Level = level })
					T.eq(r.Ok, expected == nil, string.format("%d -> %d with %d coins", current, level, coins))
					if expected then
						T.eq(r.Reason, expected, "same reason")
					end
				end
			end
		end
	end)

	withWorld("VaultService: fuzz: coins and levels always add up", function(w)
		local rng = Rng.new("vault-fuzz")
		w.data.Coins = 5e9
		local spent = 0
		for _ = 1, 400 do
			local level = rng:int(-2, 13)
			local before = w.data.BlasterLevel
			local coins = w.data.Coins
			local r = buy(w, { Level = level })
			if r.Ok then
				T.eq(w.data.BlasterLevel, before + 1, "one level up")
				spent += coins - w.data.Coins
			else
				T.eq(w.data.BlasterLevel, before, "no change")
				T.eq(w.data.Coins, coins, "no coins taken")
			end
			if rng:chance(0.05) then
				w.data.Coins += 1e9
			end
		end
		local expected = 0
		for level = 2, w.data.BlasterLevel do
			expected += BlasterData.vaultPrice(level)
		end
		T.eq(spent, expected, "paid exactly the prices of the levels bought")
	end)
end
