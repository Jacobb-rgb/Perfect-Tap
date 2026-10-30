-- SECRET ores (owner 2026-10-29): the config and its chance math, the looks and their
-- budgets, the moving parts (SecretOreFx), the jackpot screen (SecretReveal) and the
-- shared reveal kit's flash gap (RevealKit).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local BoostConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.BoostConfig")
	local StatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StatConfig")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local SecretOreShapes = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreShapes")
	local SecretOreFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreFx")

	local function parts(model)
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	T.test("secret ores: six, each an OreData entry of Rarity Secret with its own look and floor", function()
		T.eq(#SecretOreConfig.List, 6, "six secrets")
		T.eq(#OreData.Secrets, 6, "OreData.Secrets")
		local floors = {}
		for _, secret in SecretOreConfig.List do
			local ore = OreData.ById[secret.Ore]
			T.truthy(ore, secret.Ore .. " is an ore")
			T.eq(ore.Rarity, "Secret", secret.Ore .. " rarity")
			T.eq(ore.Shape, secret.Ore, secret.Ore .. " Shape = Id")
			T.truthy(ItemBuilder.Shapes[secret.Ore], secret.Ore .. " has a recipe")
			T.truthy(table.find(SecretOreShapes.Ores, secret.Ore), secret.Ore .. " listed in SecretOreShapes.Ores")
			T.truthy(OreData.exists(secret.Ore), secret.Ore .. " exists")
			T.truthy(secret.OneIn >= 1000, secret.Ore .. " is rare")
			T.truthy(secret.Stars >= 1 and secret.Stars <= 3, secret.Ore .. " stars")
			if secret.Floor then
				T.truthy(MineFloors.ById[secret.Floor], secret.Ore .. " floor exists")
				T.falsy(floors[secret.Floor], secret.Floor .. " has one secret")
				floors[secret.Floor] = true
			end
		end
		T.eq(SecretOreConfig.ByOre.RainbowNova.Floor, nil, "Rainbow Nova: every floor")
	end)

	T.test("secret ores: never in the lists everything iterates (36 ores, 6 rarities)", function()
		T.eq(#Rarity.List, 6, "six rarities in Rarity.List")
		T.eq(Rarity.get("Secret").Order, 7, "Rarity.get knows Secret")
		for _, ore in OreData.List do
			T.falsy(SecretOreConfig.isSecret(ore.Id), ore.Id .. " in OreData.List is not secret")
			T.truthy(ore.Rarity ~= "Secret", ore.Id .. " rarity")
		end
		for _, floor in MineFloors.List do
			for oreId in floor.Ores do
				T.falsy(SecretOreConfig.isSecret(oreId), floor.Id .. " rocks never hold a secret")
			end
			for oreId in floor.CrystalOres or {} do
				T.falsy(SecretOreConfig.isSecret(oreId), floor.Id .. " crystals never hold a secret")
			end
		end
		-- the luck tables (cards, zone effects) stay the six rarities
		for _, row in BoostConfig.luckTable(4) do
			T.truthy(row.Rarity ~= "Secret", "no Secret row in luckTable")
		end
	end)

	T.test("secret ores: luck raises the chance by its square root, at most x2.5", function()
		T.eq(SecretOreConfig.luckMult(1), 1, "no luck")
		T.eq(SecretOreConfig.luckMult(0.5), 1, "below x1")
		T.eq(SecretOreConfig.luckMult(0 / 0), 1, "NaN")
		T.eq(SecretOreConfig.luckMult(math.huge), 1, "inf")
		T.eq(SecretOreConfig.luckMult("x"), 1, "not a number")
		T.near(SecretOreConfig.luckMult(4), 2, 1e-9, "x4 luck -> x2")
		T.near(SecretOreConfig.luckMult(StatConfig.MaxOreLuck), 2.5, 1e-9, "the most luck there is -> x2.5")
		T.eq(SecretOreConfig.luckMult(100), 2.5, "capped")
		T.eq(BoostConfig.LuckPower.Secret, SecretOreConfig.LuckPower, "BoostConfig agrees")
		local eye = SecretOreConfig.ByOre.HollowEye
		T.near(SecretOreConfig.chance(eye, 1), 1 / 4000, 1e-12, "1 in 4,000")
		T.eq(SecretOreConfig.oddsText(eye, 1), "1 in 4,000", "odds text")
		T.eq(SecretOreConfig.oddsText(eye, 4), "1 in 2,000", "odds text with x4 luck")
		T.eq(SecretOreConfig.chanceText(1000000), "1 in 1,000,000", "commas")
	end)

	T.test("secret ores: the roll (own floor + Rainbow Nova, the rarest first, one draw each)", function()
		local function always(v)
			return function()
				return v
			end
		end
		T.eq(SecretOreConfig.roll("DeepHollow", 1, always(0)), "RainbowNova", "a draw of 0 hits the rarest first")
		T.eq(SecretOreConfig.roll("DeepHollow", 1, always(0.9)), nil, "nothing")
		local draws = { 0.5, 0 }
		local k = 0
		local function seq()
			k += 1
			return draws[k] or 1
		end
		T.eq(SecretOreConfig.roll("DeepHollow", 1, seq), "HollowEye", "Nova missed, the floor's own hit")
		T.eq(k, 2, "two draws on a floor with its own secret")
		k = 0
		draws = { 0.5 }
		T.eq(SecretOreConfig.roll(nil, 1, seq), nil, "no floor: only Rainbow Nova")
		T.eq(k, 1, "one draw")
		-- the chance a draw must beat: just under hits, just over misses
		local eye = SecretOreConfig.ByOre.HollowEye
		draws = { 1, SecretOreConfig.chance(eye, 1) * 0.999 }
		k = 0
		T.eq(SecretOreConfig.roll("DeepHollow", 1, seq), "HollowEye", "just under the chance")
		draws = { 1, SecretOreConfig.chance(eye, 1) * 1.001 }
		k = 0
		T.eq(SecretOreConfig.roll("DeepHollow", 1, seq), nil, "just over the chance")
	end)

	T.test("secret ores: budgets (clean, podium with its aura, dirty chunk like any other)", function()
		for _, secret in SecretOreConfig.List do
			for _, seed in { 1, 7, "x" } do
				local clean = ItemBuilder.build({ Kind = "Clean", OreId = secret.Ore, Grade = "Flawless" }, CF.new(0, 3, 0), seed)
				T.le(#parts(clean), ItemBuilder.Budget.Clean, secret.Ore .. " clean parts")
				local shown = ItemBuilder.display({ K = "Clean", O = secret.Ore, G = "Flawless" }, CF.new(0, 3, 0), seed)
				T.le(#parts(shown), ItemBuilder.Budget.SecretDisplay, secret.Ore .. " display parts")
				local lights = 0
				for _, d in shown:GetDescendants() do
					if d:IsA("PointLight") then
						lights += 1
					end
				end
				T.le(lights, 1, secret.Ore .. " one light")
				local raw = ItemBuilder.build({ Kind = "Raw", OreId = secret.Ore }, CF.new(0, 3, 0), seed)
				local normal = ItemBuilder.build({ Kind = "Raw", OreId = "Coal" }, CF.new(0, 3, 0), seed)
				T.eq(#parts(raw), #parts(normal), secret.Ore .. " dirty chunk has the same parts as any")
				T.truthy(raw:FindFirstChild("SecretShine", true), secret.Ore .. " dirty chunk sparkles")
			end
		end
	end)

	T.test("secret ores: the podium turns a display about its upright first part", function()
		for _, secret in SecretOreConfig.List do
			local shown = ItemBuilder.display({ K = "Clean", O = secret.Ore, G = "Flawless" }, CF.new(), 1)
			local up = shown.PrimaryPart.CFrame.UpVector
			T.truthy(up.Y > 0.999, secret.Ore .. " PrimaryPart stands upright")
			T.truthy(shown:GetAttribute("Center") ~= nil, secret.Ore .. " Center")
		end
	end)

	T.test("secret ores: moving parts (SecretOreFx) move, and come back", function()
		for _, secret in SecretOreConfig.List do
			local shown = ItemBuilder.display({ K = "Clean", O = secret.Ore, G = "Flawless" }, CF.new(), 1)
			local pivot = CF.new(shown:GetAttribute("Center"))
			local rig = SecretOreFx.rig(shown, pivot)
			T.truthy(#rig.Entries >= 8, secret.Ore .. " has moving parts")
			local before = {}
			for _, e in rig.Entries do
				before[e.Part] = e.Part.CFrame.Position
			end
			SecretOreFx.pose(rig, pivot, 0.7)
			local moved = 0
			for _, e in rig.Entries do
				if (e.Part.CFrame.Position - before[e.Part]).Magnitude > 1e-3 then
					moved += 1
				end
			end
			T.truthy(moved >= 4, secret.Ore .. " parts moved")
			-- reduce motion: everything where it was built
			SecretOreFx.pose(rig, pivot, 0.7, true)
			for _, e in rig.Entries do
				T.truthy((e.Part.CFrame.Position - before[e.Part]).Magnitude < 1e-3, secret.Ore .. " still with reduce motion")
			end
		end
	end)

	T.test("secret ores: every ore odds table shows ??? Secret with its chance, luck applied", function()
		local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
		for _, floor in MineFloors.List do
			local rows = BoostView.secretRows(floor.ZoneId, 1, 4)
			local own = SecretOreConfig.forFloor(floor.Id)
			table.sort(own, function(a, b)
				return a.OneIn > b.OneIn
			end)
			T.eq(#rows, #own, floor.Id .. ": one row per secret it can turn into, the rarest first")
			for k, row in rows do
				T.eq(row.Name, "??? Secret " .. string.rep("★", own[k].Stars), floor.Id .. ": the name hidden, its stars shown")
				T.eq(row.Before, SecretOreConfig.oddsText(own[k], 1), floor.Id .. ": the chance now")
				T.eq(row.After, SecretOreConfig.oddsText(own[k], 4), floor.Id .. ": the chance with the luck")
			end
		end
		T.eq(#BoostView.secretRows("NoSuchZone", 1, 1), 0, "no mine floor, no secret")
		local lines = BoostView.secretLines(1, 6.25)
		T.eq(#lines, #SecretOreConfig.List + 1, "a title and a line per secret")
		T.truthy(lines[#lines]:find("every floor:  1 in 1,000,000  →  1 in 400,000", 1, true), lines[#lines])
	end)

	T.test("secret ores: the codex shows them as ??? with their chance, never in the 36 count", function()
		local CodexView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CodexView")
		local found = { Coal = true, HollowEye = true }
		local secrets = CodexView.secretEntries(found, { HollowEye = true })
		T.eq(#secrets, 6, "six secret cards")
		local all = CodexView.entries(found)
		for _, e in secrets do
			table.insert(all, e)
		end
		local n, total = CodexView.count(all)
		T.eq(n, 1, "only Coal counts")
		T.eq(total, #OreData.List, "the 36")
		for _, e in secrets do
			local text = CodexView.detailText(e)
			if e.Ore.Id == "HollowEye" then
				T.truthy(e.Found and e.New, "found and NEW")
				T.eq(text.Name, "Hollow Eye")
				T.truthy(text.Where:find("1 in 4,000", 1, true), text.Where)
			else
				T.eq(text.Name, CodexView.HiddenName, e.Ore.Id .. " hidden")
				T.truthy(text.Income:find("1 in ", 1, true), e.Ore.Id .. ": the chance is never hidden")
				T.falsy(text.Income:find(e.Ore.Name, 1, true), e.Ore.Id .. ": the name is")
			end
		end
	end)

	T.test("secret ores: the jackpot screen fits a landscape phone, says the right skip, keeps its pulses apart", function()
		local roblox2 = require("@lune/roblox") :: any
		local SecretReveal = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.SecretReveal")
		local RevealKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealKit")
		local view = SecretReveal.build()
		SecretReveal.setOre(view, "RainbowNova", { New = true })
		local screen = roblox2.Vector2.new(812, 375)
		SecretReveal.pose(view, 1, { Screen = screen, Scale = 1, TopInset = 58, Input = "Gamepad" })
		local scale = view.Scale.Scale
		T.truthy(scale < 1, "smaller than the HUD's scale on a short screen")
		local midY = screen.Y * SecretReveal.Center.Y.Scale
		T.truthy(midY - SecretReveal.Reach.UpCosmos * scale >= 58 - 1e-6, "the ribbon clears the top bar")
		T.truthy(midY + SecretReveal.Reach.Down * scale <= screen.Y, "the hint stays on screen")
		T.eq(view.Hint.Text, "Press A to continue", "a gamepad's skip")
		SecretReveal.pose(view, 1, { Screen = roblox2.Vector2.new(1920, 1080), Scale = 1.25, Input = "Touch" })
		T.eq(view.Scale.Scale, 1.25, "a big screen keeps the HUD's scale")
		T.eq(view.Hint.Text, "Tap to continue")
		for stars, tier in SecretReveal.Tiers do
			for k = 2, #tier.Shocks do
				T.truthy(tier.Shocks[k] - tier.Shocks[k - 1] >= RevealKit.FlashGap - 1e-9, stars .. " stars: shockwaves FlashGap apart")
			end
		end
		RevealKit.resetFlash()
		T.truthy(RevealKit.takeFlash(10), "a flash")
		T.falsy(RevealKit.takeFlash(10.2), "not within FlashGap")
		T.truthy(RevealKit.takeFlash(10.45), "after it")
		RevealKit.resetFlash()
	end)

	T.test("secret ores: moving parts come back to rest exactly (a podium out of range), and stay in the dirt's ore", function()
		local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
		local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
		for _, secret in SecretOreConfig.List do
			local shown = ItemBuilder.display({ K = "Clean", O = secret.Ore, G = "Flawless" }, CF.new(), 1)
			local pivot = CF.new(shown:GetAttribute("Center"))
			local rig = SecretOreFx.rig(shown, pivot)
			local rest = {}
			for _, e in rig.Entries do
				rest[e.Part] = { e.Part.CFrame, e.Part.Size, e.Part.Transparency, e.Part.Color }
			end
			SecretOreFx.pose(rig, pivot * CF.Angles(0, 1.3, 0), 2.37)
			SecretOreFx.rest(rig, pivot)
			for part, r in rest do
				T.truthy((part.CFrame.Position - r[1].Position).Magnitude < 1e-4, secret.Ore .. " back in place")
				T.truthy((part.Size - r[2]).Magnitude < 1e-4, secret.Ore .. " back to size")
				T.eq(part.Transparency, r[3], secret.Ore .. " back to its transparency")
			end
			-- the same ore under the dirt (fitted smaller): its movers stay round it
			local shell = OreShellBuilder.build(Patterns.generate(secret.Ore, 7), CF.new(0, 5, 0), nil)
			local treasure = shell.Treasure
			local center = treasure:GetAttribute("Center")
			local reach = 0
			local list = {}
			for _, d in treasure:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.99 then
					table.insert(list, d)
				end
			end
			local mid = roblox.Vector3.zero
			for _, d in list do
				mid += d.CFrame.Position
			end
			mid /= #list
			for _, d in list do
				reach = math.max(reach, (d.CFrame.Position - mid).Magnitude)
			end
			local shellRig = SecretOreFx.rig(treasure, CF.new(center))
			for _, t in { 0.3, 0.9, 1.7, 2.6 } do
				SecretOreFx.pose(shellRig, CF.new(center), t)
				for _, e in shellRig.Entries do
					T.truthy(
						(e.Part.CFrame.Position - mid).Magnitude <= reach * 1.2 + 0.05,
						secret.Ore .. " mover stays near the ore under the dirt"
					)
				end
			end
		end
	end)

	T.test("secret ores: the Hollow Eye blinks (iris hidden, lid shown) only now and then", function()
		local shown = ItemBuilder.display({ K = "Clean", O = "HollowEye", G = "Flawless" }, CF.new(), 1)
		local pivot = CF.new(shown:GetAttribute("Center"))
		local rig = SecretOreFx.rig(shown, pivot)
		local function state(t)
			SecretOreFx.pose(rig, pivot, t)
			local lid, iris = nil, nil
			for _, e in rig.Entries do
				if e.Kind == "Lid" then
					lid = e.Part.Transparency
				elseif e.Kind == "Look" and e.Part.Material == roblox.Enum.Material.Neon then
					iris = e.Part.Transparency
				end
			end
			return lid, iris
		end
		local lid, iris = state(1)
		T.eq(lid, 1, "open: no lid")
		T.eq(iris, 0, "open: iris shown")
		lid, iris = state(SecretOreFx.BlinkEvery - SecretOreFx.BlinkTime / 2)
		T.eq(lid, 0, "blink: lid shown")
		T.eq(iris, 1, "blink: iris hidden")
	end)
end
