--[[
	Every weather gives ore something (owner 2026-11-07, his pick): the list, the
	moments, each bonus where it works, the odds a paid boost shows.
]]

return function(T, Loader)
	local WeatherBonus = Loader.requirePath("ReplicatedStorage.Shared.Weather.WeatherBonus")
	local WeatherLogic = Loader.requirePath("ReplicatedStorage.Shared.Weather.WeatherLogic")
	local WeatherConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WeatherConfig")
	local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
	local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")
	local CleaningPatterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
	local SprayScoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.SprayScoring")
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.WeatherBonusController")

	local List = WeatherBonus.List

	local function withWeather(entry: any, fn: () -> ())
		local saved = rawget(Bonuses, "weatherNow")
		Bonuses.weatherNow = function()
			return entry
		end
		Bonuses.forgetWeather()
		local ok, err = pcall(fn)
		Bonuses.weatherNow = saved
		Bonuses.forgetWeather()
		if not ok then
			error(err, 0)
		end
	end

	T.test("weather bonus: the owner's list, one bonus for every weather", function()
		T.eq(List.Rain.Twin, 0.2)
		T.eq(List.Storm.Luck, 1.5)
		T.eq(List.Hail.Damage, 1.25)
		T.eq(List.Snow.Clean, 1.3)
		T.eq(List.Wind.Reach, 2)
		T.eq(List.Heatwave.Machine, 1.25)
		T.eq(List.Rainbow.Secret, 2)
		for kind in WeatherConfig.Kinds do
			T.truthy(List[kind], kind .. " gives something")
		end
		for kind, entry in List do
			T.eq(entry.Kind, kind)
			T.truthy(#entry.Tag > 0 and #entry.Text > 0, kind .. " says so")
			local effects = 0
			for _, key in { "Twin", "Luck", "Damage", "Clean", "Reach", "Machine", "Secret" } do
				if entry[key] then
					effects += 1
				end
			end
			T.eq(effects, 1, kind .. ": one bonus")
		end
	end)

	T.test("weather bonus: it runs from the weather's first second to its last", function()
		T.eq(WeatherBonus.at(1000, "Storm").Kind, "Storm", "forced")
		T.eq(WeatherBonus.at(1000, "Clear"), nil)
		T.eq(WeatherBonus.at(1000, "Rainbow").Kind, "Rainbow")
		local found: any = nil
		local slot = 3_000_000
		while not found do
			found = WeatherLogic.event(slot)
			slot += 1
		end
		T.eq(WeatherBonus.at(found.Start + 1).Kind, found.Kind, "just started")
		T.eq(WeatherBonus.at(found.Start + found.Length - 1).Kind, found.Kind, "about to end")
		local before = WeatherBonus.at(found.Start - 1)
		T.eq(before, nil, "not before it")
		T.near(WeatherBonus.left(found.Start + 10), found.Length - 10, 1e-6, "seconds left")
		local rainbow: any = nil
		slot = 3_000_000
		while not rainbow do
			local event = WeatherLogic.event(slot)
			if event and event.Rainbow then
				rainbow = event
			end
			slot += 1
		end
		local after = rainbow.Start + rainbow.Length + 1
		T.eq(WeatherBonus.at(after).Kind, "Rainbow", "a rainbow after the shower")
		T.truthy(WeatherBonus.left(after) > 0)
		T.eq(WeatherLogic.rainbowEnd(rainbow), rainbow.Start + rainbow.Length - WeatherConfig.Rainbow.Lead + WeatherConfig.Rainbow.Seconds)
	end)

	T.test("weather bonus: each works on the server, none in clear weather", function()
		local stats = { OreLuckPct = 0, OreLuckMult = 1, DamagePct = 0, TwinDropChance = 0.1, MagnetRadius = 0, PickupRange = 8 }
		withWeather(nil, function()
			T.eq(Bonuses.oreLuck(stats), StatConfig.oreLuck(0, 1))
			T.eq(Bonuses.damageMult(stats, false), 1)
			T.eq(Bonuses.twinDrop(stats), 0.1)
			T.eq(Bonuses.magnetRadius(stats), 0, "no magnet, no wind: nothing flies")
			T.eq(Bonuses.secretMult(), 1)
			T.eq(Bonuses.cleanMult(), 1)
			T.eq(Bonuses.machineMult(), 1)
		end)
		withWeather(List.Storm, function()
			T.eq(Bonuses.oreLuck(stats), StatConfig.oreLuck(0, 1.5))
			local max = StatConfig.ById.OreLuckMult.Max
			T.eq(Bonuses.oreLuck({ OreLuckPct = 0, OreLuckMult = max }), StatConfig.oreLuck(0, max), "the cap holds")
		end)
		withWeather(List.Hail, function()
			T.eq(Bonuses.damageMult(stats, false), 1.25)
		end)
		withWeather(List.Rain, function()
			T.near(Bonuses.twinDrop(stats), 0.3, 1e-9)
			T.near(Bonuses.twinDrop({ TwinDropChance = 2 }), 0.7, 1e-9, "on top of the enchant's cap")
		end)
		withWeather(List.Wind, function()
			-- (review 11-07: "magnet reach x2", magnet owners only, within the cap)
			T.eq(Bonuses.magnetRadius(stats), 0, "no magnet: nothing flies, wind or not")
			T.eq(Bonuses.magnetRadius({ MagnetRadius = 20 }), 40, "a magnet pulls from twice as far")
			T.eq(Bonuses.magnetRadius({ MagnetRadius = 20, MagnetBonus = 5 }), 50, "Magnetism counts, then doubled")
			local max = StatConfig.ById.MagnetRadius.Max
			T.eq(Bonuses.magnetRadius({ MagnetRadius = max - 2 }), max, "never past the cap")
			T.eq(Bonuses.magnetRadius({ MagnetRadius = 20 }, false), 20, "the magnet's own radius: the shop, the buy toast")
		end)
		withWeather(List.Rainbow, function()
			T.eq(Bonuses.secretMult(), 2)
		end)
		withWeather(List.Snow, function()
			T.eq(Bonuses.cleanMult(), 1.3)
		end)
		withWeather(List.Heatwave, function()
			T.eq(Bonuses.machineMult(), 1.25)
		end)
	end)

	T.test("weather bonus: a rainbow doubles the secret chance, in the roll and the text", function()
		local secret = SecretOreConfig.ByOre.HollowEye
		T.near(SecretOreConfig.chance(secret, 1, 2), 2 * SecretOreConfig.chance(secret, 1), 1e-12)
		T.eq(SecretOreConfig.oddsText(secret, 1, 2), "1 in 2,000")
		T.eq(SecretOreConfig.oddsText(secret, 1), "1 in 4,000", "without it")
		local roll = 1.5 / 4000
		T.eq(
			SecretOreConfig.roll("DeepHollow", 1, function()
				return roll
			end),
			nil,
			"not at 1 in 4,000"
		)
		T.truthy(SecretOreConfig.roll("DeepHollow", 1, function()
			return roll
		end, 2) ~= nil, "at 1 in 2,000")
	end)

	T.test("weather bonus: snow thins the dirt the same on both sides, nothing else does", function()
		local plain = CleaningPatterns.generate("Gold", 7)
		local total = plain.TotalAmount
		local thin = CleaningPatterns.thin(CleaningPatterns.generate("Gold", 7), 1.3)
		T.near(thin.TotalAmount, total / 1.3, 1e-6)
		T.near(thin.Cells[1].Amount, plain.Cells[1].Amount / 1.3, 1e-9)
		-- par stays the clump's: thinner dirt never makes the score harder (review 11-07)
		T.near(thin.ParAmount :: number, total, 1e-9)
		T.near(SprayScoring.par(thin, "Mouse"), SprayScoring.par(plain, "Mouse"), 1e-9, "the same par")
		T.eq(CleaningPatterns.thin(thin, 1.3).ParAmount, thin.ParAmount, "a second thinning keeps the first par")
		for _, bad in { 1, 0.5, 3, 0 / 0, "x", nil } do
			local same = CleaningPatterns.thin(CleaningPatterns.generate("Gold", 7), bad :: any)
			T.near(same.TotalAmount, total, 1e-9, "a broken factor changes nothing")
		end
	end)

	T.test("weather bonus: the odds a paid boost shows hold the storm and the rainbow, the chip runs with it", function()
		local saved = BoostView.weather
		local entry: any = List.Storm
		BoostView.weather = function()
			return entry
		end
		local ok, err = pcall(function()
			local state = { BlasterLevel = 5, Bonuses = { OreLuckPct = 0, OreLuckMult = 1 } }
			T.eq(BoostView.context(state, nil).OreLuckMult, 1.5, "in the context of every card")
			local storm = BoostView.hexaOdds(state, "DeepHollow")
			T.truthy(storm.Note:find("Storm now", 1, true) ~= nil, storm.Note)
			-- the numbers: the storm's luck without Hexa, the cap with it (review 11-07)
			local without, with = BoostConfig.hexaLuck(0, 1.5)
			T.truthy(storm.Note:find(`Ore luck {BoostView.mult(without)} without, {BoostView.mult(with)} with`, 1, true) ~= nil, storm.Note)
			T.truthy(math.abs(without - StatConfig.oreLuck(0, 1.5)) < 1e-9, "x1.5 without")
			-- the Hexa Lucky card's key line (a Robux card): the storm in its "now"
			for _, card in BoostView.cards(state, 0, 1000, false, {}) do
				if card.Kind == "HexaLucky" then
					T.eq(card.KeyLine, `Your ore luck: {BoostView.mult(without)} → {BoostView.mult(with)}`)
				end
			end
			T.truthy(BoostView.weatherNote():find("luck cap", 1, true) ~= nil, "a storm adds nothing on top of Hexa: said")
			local rows = BoostView.secretRows("DeepHollow", 1, 1)
			entry = List.Rainbow
			local doubled = BoostView.secretRows("DeepHollow", 1, 1)
			T.eq(rows[#rows].Before, "1 in 4,000", "Deep Hollow's own, in a storm's luck of 1")
			T.eq(doubled[#doubled].Before, "1 in 2,000", "doubled by the rainbow")
			-- the Store's luck card lines too (StoreController.luckLines: BoostView.secretLines)
			local function hollowLine(lines: { string }): string
				for _, line in lines do
					if line:find("Deep Hollow", 1, true) == 1 then
						return line
					end
				end
				return ""
			end
			T.truthy(hollowLine(BoostView.secretLines(1, 1)):find("1 in 2,000", 1, true) ~= nil, "the Store: x2 in a rainbow")
			T.truthy(BoostView.hexaOdds(state, "DeepHollow").Note:find("Rainbow now", 1, true) ~= nil)
			local chips = BoostView.chips(state, 1000)
			T.eq(chips[#chips].Kind, BoostView.WeatherChip)
			T.eq(chips[#chips].Tag, "RAINBOW")
			entry = nil
			T.truthy(hollowLine(BoostView.secretLines(1, 1)):find("1 in 4,000", 1, true) ~= nil, "the Store: clear")
			T.eq(BoostView.weatherNote(), "", "no note in clear weather")
			T.eq(#BoostView.chips(state, 1000), 0, "clear weather: no chip")
			T.eq(BoostView.context(state, nil).OreLuckMult, 1)
			local refs = BoostView.buildChips()
			T.truthy(refs.Chips[BoostView.WeatherChip], "its chip exists")
		end)
		BoostView.weather = saved
		if not ok then
			error(err, 0)
		end
	end)

	T.test("weather bonus: one word when a weather starts, not while it runs or ends", function()
		T.eq(Controller.word(nil, List.Storm), List.Storm.Text)
		T.eq(Controller.word(List.Rain, List.Rainbow), List.Rainbow.Text, "the rainbow after the rain")
		T.eq(Controller.word(List.Storm, List.Storm), nil)
		T.eq(Controller.word(List.Storm, nil), nil)
		T.eq(Controller.word(nil, nil), nil)
	end)
end
