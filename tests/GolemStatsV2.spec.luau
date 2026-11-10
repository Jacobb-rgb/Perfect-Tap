-- The golem stats of 2026-10-30 (the owner's list): every egg wakes its own
-- golems, one per rarity, with exactly his bonuses, so the eggs are tiers
-- apart; the Sky egg's two HUGE golems give two bonuses each; the caps fit
-- the best three golems of every stat; the odds (also with Triple Lucky)
-- stay exact and sum to 1, HUGE included.
return function(T, Loader)
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
	local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
	local HatchStage = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchStage")
	local GolemView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GolemView")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")

	local EPS = 1e-9

	-- the owner's list: egg -> { golem, rarity, bonus type, value }
	local EGGS = {
		Stone = {
			{ "PebbleGolem", "Common", "Income", 0.03 },
			{ "CopperTinker", "Uncommon", "MiningSpeed", 0.05 },
			{ "CobaltDiver", "Rare", "Luck", 0.07 },
			{ "CoalChomper", "Epic", "SellValue", 0.1 },
		},
		Crystal = {
			{ "JadeGardener", "Common", "Income", 0.1 },
			{ "AmethystAcolyte", "Uncommon", "MiningSpeed", 0.12 },
			{ "QuartzSprite", "Rare", "Luck", 0.15 },
			{ "SapphireSage", "Epic", "SellValue", 0.18 },
			{ "DiamondDuke", "Legendary", "Income", 0.2 },
		},
		Royal = {
			{ "SilverSquire", "Uncommon", "Income", 0.2 },
			{ "RoseKnight", "Rare", "MiningSpeed", 0.25 },
			{ "MoonstoneOracle", "Epic", "Luck", 0.3 },
			{ "StormTitan", "Legendary", "SellValue", 0.35 },
			{ "CelestialSovereign", "Mythic", "Income", 0.4 },
		},
		Sky = {
			{ "SkySprite", "Epic", "Luck", 0.5 },
			{ "StormSentinel", "Legendary", "MiningSpeed", 0.65 },
			{ "AetherKing", "Mythic", "Income", 1 },
			{ "SkyTitan", "Mythic", "MiningSpeed", 1.2 },
			{ "CloudColossus", "Mythic", "Income", 0.6 },
		},
		Dragonforge = {
			{ "CinderWhelp", "Rare", "MiningSpeed", 1 },
			{ "EmberHatchling", "Rare", "Luck", 1 },
			{ "ScaleKnight", "Epic", "SellValue", 1.5 },
			{ "Flamewing", "Epic", "WalkSpeed", 1 },
			{ "MagmaWyvern", "Legendary", "MiningSpeed", 2 },
			{ "DragonKing", "Mythic", "Income", 3.5 },
		},
	}

	local function count(t: { [any]: any }): number
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	T.test("Golem stats v2: every egg wakes exactly its own golems with the owner's bonuses", function()
		for eggId, rows in EGGS do
			local capsule = CapsuleConfig.ById[eggId]
			T.truthy(capsule, eggId)
			T.eq(count(capsule.Odds), #rows, `{eggId}: only its own golems`)
			for _, row in rows do
				local id, rarity, bonusType, value = row[1], row[2], row[3], row[4]
				local golem = GolemConfig.ById[id]
				T.truthy(golem and capsule.Odds[id], `{eggId} wakes {id}`)
				T.eq(golem.Rarity, rarity, `{id} rarity`)
				T.eq(golem.Bonus.Type, bonusType, `{id} bonus type`)
				T.near(golem.Bonus.Value, value, EPS, `{id} bonus value`)
			end
		end
		-- no golem sleeps in two eggs
		local home: { [string]: string } = {}
		for _, capsule in CapsuleConfig.List do
			for id in capsule.Odds do
				T.eq(home[id], nil, `{id} is in {home[id]} and {capsule.Id}`)
				home[id] = capsule.Id
			end
		end
		-- the egg golems wear their egg's costumes
		for _, eggId in { "Stone", "Crystal", "Royal" } do
			for id in CapsuleConfig.ById[eggId].Odds do
				T.eq(GolemConfig.ById[id].Family, eggId, `{id} Family`)
			end
		end
	end)

	T.test("Golem stats v2: the eggs are tiers apart and rarer golems are rarer", function()
		-- each egg's golems: the rarer, the stronger and the less likely
		for eggId, rows in EGGS do
			local odds = CapsuleConfig.ById[eggId].Odds
			for i = 2, #rows do
				local a, b = rows[i - 1][1], rows[i][1]
				T.truthy(odds[b] <= odds[a], `{eggId}: {b} is no likelier than {a}`)
				T.truthy(GolemConfig.order(b) >= GolemConfig.order(a), `{eggId}: {b} is no less rare than {a}`)
			end
		end
		-- the best of a lower egg is at most the common one of the next
		local function best(eggId: string): number
			local top = 0
			for _, row in EGGS[eggId] do
				top = math.max(top, GolemConfig.value(row[1]))
			end
			return top
		end
		local function first(eggId: string): number
			return GolemConfig.value(EGGS[eggId][1][1])
		end
		T.truthy(best("Stone") <= first("Crystal") + EPS, "Stone's best <= Crystal's first")
		T.truthy(best("Crystal") <= first("Royal") + EPS, "Crystal's best <= Royal's first")
		T.truthy(best("Royal") <= first("Sky") + EPS, "Royal's best <= Sky's first")
		-- nobody gets everything at once: each egg's top golem is 1 % or less
		for _, eggId in { "Stone", "Crystal", "Royal" } do
			local rows = EGGS[eggId]
			T.truthy(CapsuleConfig.ById[eggId].Odds[rows[#rows][1]] <= 0.01 + EPS, `{eggId}: its best is at most 1 %`)
		end
	end)

	T.test("Golem stats v2: the HUGE golems: two bonuses, 0.5 % and 0.3 % of a Sky egg", function()
		local titan, colossus = GolemConfig.ById.SkyTitan, GolemConfig.ById.CloudColossus
		T.truthy(titan.Huge and colossus.Huge, "both HUGE")
		T.eq(titan.Bonus2 and titan.Bonus2.Type, "Income")
		T.near(titan.Bonus2 and titan.Bonus2.Value or 0, 0.2, EPS)
		T.eq(colossus.Bonus2 and colossus.Bonus2.Type, "Luck")
		T.near(colossus.Bonus2 and colossus.Bonus2.Value or 0, 1, EPS)
		T.near(CapsuleConfig.ById.Sky.Odds.SkyTitan, 0.005, EPS, "Sky Titan 0.5 %")
		T.near(CapsuleConfig.ById.Sky.Odds.CloudColossus, 0.003, EPS, "Cloud Colossus 0.3 %")
		for _, golem in GolemConfig.List do
			T.truthy(golem.Bonus2 == nil or golem.Huge, `only HUGE golems have two bonuses ({golem.Id})`)
		end
		-- both bonuses count while equipped, raised by Golem Bond
		local golems = {
			Owned = { { Id = 1, Kind = "SkyTitan" }, { Id = 2, Kind = "CloudColossus" } },
			Equipped = { 1, 2 },
			NextId = 3,
		}
		local stats = GolemConfig.stats(golems, 0.5)
		T.near(stats.DamagePct, 1.2 * 1.5, EPS, "Sky Titan's mining")
		T.near(stats.IncomePct, (0.2 + 0.6) * 1.5, EPS, "both incomes")
		T.near(stats.OreLuckPct, 1 * 1.5, EPS, "Cloud Colossus' luck")
		T.eq(GolemConfig.describe("SkyTitan"), "+120% Mining speed, +20% Income")
		T.eq(GolemConfig.describe("CloudColossus", 0.1), "+66% Income, +110% Ore luck")
		T.eq(GolemConfig.describe("DragonKing"), "+350% Income")
	end)

	T.test("Golem stats v2: every egg's odds sum to 1, also with Triple Lucky (HUGE x3 too)", function()
		for _, capsule in CapsuleConfig.List do
			for _, lucky in { false, true } do
				local total = 0
				for _, line in CapsuleConfig.odds(capsule.Id, lucky) do
					T.truthy(line.Chance > 0, `{capsule.Id} {line.Golem} > 0`)
					total += line.Chance
				end
				T.near(total, 1, 1e-9, `{capsule.Id} sums to 1 (lucky {lucky})`)
			end
		end
		-- Triple Lucky makes every golem from LuckyFrom up exactly 3x as likely
		for _, eggId in { "Sky", "Royal" } do
			local from = Rarity.ById[CapsuleConfig.ById[eggId].LuckyFrom].Order
			local plain: { [string]: number } = {}
			for _, line in CapsuleConfig.odds(eggId, false) do
				plain[line.Golem] = line.Chance
			end
			for _, line in CapsuleConfig.odds(eggId, true) do
				if GolemConfig.order(line.Golem) >= from then
					T.near(line.Chance, plain[line.Golem] * 3, 1e-12, `{eggId} {line.Golem} x3`)
				else
					T.truthy(line.Chance < plain[line.Golem], `{eggId} {line.Golem} shares the rest`)
				end
			end
		end
		local lucky: { [string]: number } = {}
		for _, line in CapsuleConfig.odds("Sky", true) do
			lucky[line.Golem] = line.Chance
		end
		T.near(lucky.SkyTitan, 0.015, 1e-12, "Sky Titan 1.5 % with Triple Lucky")
		T.near(lucky.CloudColossus, 0.009, 1e-12, "Cloud Colossus 0.9 % with Triple Lucky")
	end)

	T.test("Golem stats v2: the retired golems stay (owned ones keep working), no egg wakes them", function()
		for _, id in { "TinTumbler", "EmberImp", "GildedPorter", "HeartstoneColossus" } do
			local golem = GolemConfig.ById[id]
			T.truthy(golem and golem.Family, `{id} still known, with a costume family`)
			for _, capsule in CapsuleConfig.List do
				T.eq(capsule.Odds[id], nil, `{capsule.Id} doesn't wake {id}`)
			end
			local golems = { Owned = { { Id = 1, Kind = id } }, Equipped = { 1 }, NextId = 2 }
			local stat = GolemConfig.BonusTypes[golem.Bonus.Type].Stat
			T.near(GolemConfig.stats(golems)[stat], golem.Bonus.Value, EPS, `{id} still gives its bonus`)
		end
	end)

	T.test("Golem stats v2: the caps fit the best three golems of every stat", function()
		local best: { [string]: { number } } = {}
		for _, golem in GolemConfig.List do
			for _, bonus in GolemConfig.bonuses(golem) do
				local stat = GolemConfig.BonusTypes[bonus.Type].Stat
				best[stat] = best[stat] or {}
				table.insert(best[stat], bonus.Value)
			end
		end
		-- (walk speed stops at +100 %, twice as fast, on purpose: Flamewing alone)
		best.WalkSpeedPct = { GolemConfig.ById.Flamewing.Bonus.Value }
		for stat, values in best do
			table.sort(values, function(a, b)
				return a > b
			end)
			local top = (values[1] or 0) + (values[2] or 0) + (values[3] or 0)
			local cap = StatConfig.ById[stat].Max :: number
			T.truthy(top <= cap + EPS, `{stat}: the best three ({top}) fit under the cap ({cap})`)
		end
		T.near(StatConfig.MaxOreLuck, 10, EPS, "ore luck at most x10")
	end)

	T.test("Golem stats v2: 'best' is the whole bonus, rarity breaks a tie", function()
		T.truthy(GolemConfig.score("CinderWhelp") > GolemConfig.score("CelestialSovereign"), "+100% Rare over +40% Mythic")
		T.truthy(GolemConfig.score("CoalChomper") > GolemConfig.score("JadeGardener"), "same +10%: the Epic first")
		T.truthy(GolemConfig.score("CloudColossus") > GolemConfig.score("SkyTitan"), "+160% over +140%")
		T.eq(GolemConfig.score("NoSuchGolem"), -1)
	end)

	T.test("Golem stats v2: a v11 save loads with every golem it owns, retired ones and paid ones too", function()
		T.eq(DataTemplate.Version, Migrations.Latest, "Version and Latest together")
		T.eq(Migrations.Latest, 16)
		local save: any = { Version = 11 }
		save.Golems = {
			Owned = {
				{ Id = 1, Kind = "HeartstoneColossus", Paid = true, Locked = true },
				{ Id = 2, Kind = "TinTumbler" },
				{ Id = 3, Kind = "GildedPorter", Paid = true },
				{ Id = 4, Kind = "EmberImp" },
				{ Id = 5, Kind = "SkyTitan" },
			},
			Equipped = { 1, 5 },
			NextId = 6,
		}
		Migrations.run(save)
		T.eq(save.Version, 16)
		T.eq(#save.Golems.Owned, 5, "none lost")
		T.eq(save.Golems.Owned[1].Kind, "HeartstoneColossus")
		T.truthy(save.Golems.Owned[1].Paid and save.Golems.Owned[1].Locked, "paid and locked stay")
		T.eq(#save.Golems.Equipped, 2, "still equipped")
		T.near(GolemConfig.stats(save.Golems).DamagePct, 0.4 + 1.2, EPS, "both give their bonus")
	end)

	T.test("Golem stats v2: the opening names both HUGE bonuses and shows a HUGE golem bigger, on the screen", function()
		T.eq(HatchStage.bonusLine(GolemConfig.ById.SkyTitan), "+120% Mining speed, +20% Income")
		T.eq(HatchStage.bonusLine(GolemConfig.ById.CloudColossus), "+60% Income, +100% Ore luck")
		T.eq(HatchStage.bonusLine(GolemConfig.ById.AetherKing), "+100% Income")
		-- (the rarest first, then the score: a HUGE golem is the show of any Sky egg batch it wakes in)
		T.eq(CapsuleView.best({ "SkySprite", "AetherKing", "SkyTitan" }), "SkyTitan")
		T.eq(CapsuleView.best({ "SkyTitan", "CloudColossus" }), "CloudColossus")
		local middle = { Golem = Vector2.new(0.5, 0.46), GolemH = 0.5 } :: any
		local plain = HatchStage.golemDepth("AetherKing", 10, middle)
		local huge = HatchStage.golemDepth("SkyTitan", 10, middle)
		T.near(plain, HatchFx.depthFor(10, 0.5), EPS, "the others fill their slot")
		T.near(huge, HatchFx.depthFor(10, 0.5 * HatchStage.HugeShare), EPS, "a HUGE one more")
		local top = { Golem = Vector2.new(0.5, 0.25), GolemH = 0.42 } :: any
		T.near(HatchStage.golemDepth("SkyTitan", 10, top), HatchFx.depthFor(10, 0.46), EPS, "its head stays on the screen")
		local tight = { Golem = Vector2.new(0.5, 0.2), GolemH = 0.42 } :: any
		T.near(HatchStage.golemDepth("SkyTitan", 10, tight), HatchFx.depthFor(10, 0.42), EPS, "never smaller than its slot")
	end)

	T.test("Golem stats v2: the opening never says a golem is sure: no 1 in 1 in any egg, also with Triple Lucky", function()
		for _, capsule in CapsuleConfig.List do
			for _, lucky in { false, true } do
				for _, line in CapsuleConfig.odds(capsule.Id, lucky) do
					local words = HatchStage.chanceWords(line.Chance)
					T.truthy(words ~= "1 in 1", `{capsule.Id} {line.Golem} at {line.Chance} says {words}`)
				end
			end
		end
		T.eq(HatchStage.chanceWords(0.7), "70%")
		T.eq(HatchStage.chanceWords(0.832), "83.2%")
		T.eq(HatchStage.chanceWords(0.3), "1 in 3")
		T.eq(HatchStage.chanceWords(0.005), "1 in 200")
	end)

	T.test("Golem stats v2: the equipped totals say what the game applies (the caps), like Bonuses.compute", function()
		local function totals(kinds: { string }): (string, any)
			local owned, equipped = {}, {}
			for i, kind in kinds do
				owned[i] = { Id = i, Kind = kind }
				equipped[i] = i
			end
			local golems = { Owned = owned, Equipped = equipped, NextId = #kinds + 1 }
			local data = ProfileStore.deepCopy(DataTemplate)
			data.Golems = golems
			return GolemView.totals({ Golems = golems, Bonuses = { GolemBond = 0 } }), Bonuses.compute(data, 1_800_000_000)
		end
		local text, stats = totals({ "DragonKing", "DragonKing", "Flamewing" })
		T.near(stats.IncomePct, 6, EPS, "the server's cap")
		T.truthy(text:find("+600% Income", 1, true), text)
		T.truthy(text:find("+100% Walk speed", 1, true), text)
		text, stats = totals({ "Flamewing", "Flamewing", "Flamewing" })
		T.near(stats.WalkSpeedPct, 1, EPS, "the server's cap")
		T.eq(text, "+100% Walk speed", "not +300%")
		text, stats = totals({ "MagmaWyvern", "MagmaWyvern", "MagmaWyvern" })
		T.near(stats.DamagePct, 5, EPS, "the server's cap")
		T.eq(text, "+500% Mining speed", "not +600%")
		T.eq((totals({ "PebbleGolem" })), "+3% Income", "under its cap: as it is")
	end)

	T.test("Golem stats v2: small cards keep the text floor (a HUGE golem's first bonus), the odds list shows both", function()
		T.eq(GolemView.shortBonus(GolemConfig.describe("SkyTitan")), "+120% MINING")
		T.eq(GolemView.shortBonus(GolemConfig.describe("CloudColossus")), "+60% INCOME")
		T.eq(GolemView.shortBonus(GolemConfig.describe("DragonKing")), "+350% INCOME")
		T.eq(GolemConfig.describe("SkyTitan"), "+120% Mining speed, +20% Income", "the detail panel names both")
		-- the PC stall window's odds rows: a HUGE golem's two bonuses wrap onto two lines, others stay one line
		local refs = CapsuleView.build(false)
		refs.Tab = "Sky"
		local state = { Golems = { Owned = {}, Equipped = {}, NextId = 1 }, AtPodium = "Sky" }
		CapsuleView.setCards(refs, CapsuleView.cards(state, 1e9, false, 1_800_000_000, nil, true))
		local wrapped, seen = 0, 0
		for _, row in refs.Rows do
			if row.Frame.Visible and row.Bonus.Text ~= "" then
				seen += 1
				local two = row.Bonus.Text:find(", ", 1, true) ~= nil
				T.eq(row.Bonus.TextWrapped, two, row.Name.Text .. ": two lines only for two bonuses")
				if two then
					wrapped += 1
					T.truthy(
						TechShopView.fits(row.Bonus.Text, row.Bonus.Size.X.Offset, row.Bonus.Size.Y.Offset, row.Bonus.TextSize, true),
						row.Name.Text .. ": both seen"
					)
					T.truthy(row.Bonus.TextSize >= 10, row.Name.Text .. ": at the text floor or above")
				end
			end
		end
		T.truthy(seen > 0, "the odds list shows")
		T.eq(refs.Tab, "Sky", "the Sky egg shown")
		T.eq(wrapped, 2, "the two HUGE golems")
	end)
end
