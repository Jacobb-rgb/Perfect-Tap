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
