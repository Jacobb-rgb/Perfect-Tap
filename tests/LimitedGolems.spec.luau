-- LIMITED EDITION golems (Config/LimitedGolems, a prototype): four themed
-- sets of 6 (Rare, Rare, Epic, Epic, Legendary, Mythic) with banner odds
-- that sum to 1, not wired into the game's golem list; every one builds
-- with its themed gear within LimitedMaxParts (the GolemConfig hard cap),
-- in Mini Characters proportions, standing on its base with a measured
-- Height, decoration only, welds for followers, and Legendary+ hover on
-- their aura. The capsule golems keep their own 20-part budget.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CFrame = Loader.CFrame
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")

	local function parts(model: any): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function yExtent(part: any): (number, number)
		local cf = part.CFrame
		local h = part.Size / 2
		local up = math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z
		return cf.Position.Y - up, cf.Position.Y + up
	end

	local function each(fn: (any, any) -> ())
		for _, id in LimitedGolems.Order do
			local theme = LimitedGolems.Themes[id]
			for _, golem in theme.Golems do
				fn(theme, golem)
			end
		end
	end

	T.test("LimitedGolems: four sets of 6 by rarity, banner odds sum to 1, not in the game list", function()
		T.eq(#LimitedGolems.Order, 4, "four proposals")
		local seen = {}
		for _, id in LimitedGolems.Order do
			local theme = LimitedGolems.Themes[id]
			T.truthy(theme and theme.Id == id, id)
			T.truthy(#theme.Title > 0 and #theme.Tagline > 0, id .. " banner text")
			T.eq(#theme.Golems, 6, id .. " has 6 golems")
			local total, last = 0, math.huge
			for i, golem in theme.Golems do
				T.eq(golem.Rarity, LimitedGolems.SetRarities[i], golem.Id .. " rarity")
				T.falsy(seen[golem.Id], golem.Id .. " unique")
				seen[golem.Id] = true
				T.falsy(GolemConfig.ById[golem.Id], golem.Id .. " is not wired into GolemConfig yet")
				T.eq(LimitedGolems.ById[golem.Id], golem)
				T.eq(LimitedGolems.ThemeOf[golem.Id], id)
				T.truthy(GolemConfig.Accessories[golem.Accessory], golem.Id .. " gear is known")
				T.truthy(GolemConfig.BonusTypes[golem.Bonus.Type] and golem.Bonus.Value > 0, golem.Id .. " bonus")
				local odds = theme.Odds[golem.Id]
				T.truthy(type(odds) == "number" and odds > 0 and odds <= last, golem.Id .. " odds fall with rarity")
				last = odds
				total += odds
			end
			T.near(total, 1, 1e-9, id .. " odds sum to 1")
			T.near(theme.Odds[theme.Golems[6].Id], 0.01, 1e-9, id .. " Mythic 1%")
		end
		for _, golem in GolemConfig.List do
			T.falsy(LimitedGolems.ById[golem.Id], golem.Id .. " is no limited golem")
		end
	end)

	T.test("LimitedGolems: every golem builds within the limited budget", function()
		T.le(GolemBuilder.LimitedMaxParts, GolemConfig.MaxParts, "the per-model hard cap")
		T.eq(GolemBuilder.MaxParts, 20, "capsule golems keep their budget")
		each(function(_, golem)
			T.eq(GolemBuilder.budget(golem.Id), GolemBuilder.LimitedMaxParts, golem.Id .. " budget")
			local model = GolemBuilder.build(golem.Id)
			local n = GolemBuilder.partCount(model)
			T.le(n, GolemBuilder.LimitedMaxParts, golem.Id .. " parts")
			T.truthy(n >= 16, golem.Id .. " wears its gear (" .. n .. " parts)")
			T.eq(model:GetAttribute("Golem"), golem.Id)
			T.truthy(model.PrimaryPart and model.PrimaryPart.Name == "Body", golem.Id .. " PrimaryPart = Body")
			local head, body = model:FindFirstChild("Head"), model:FindFirstChild("Body")
			T.truthy(head.Size.X > body.Size.X and head.Size.Y > body.Size.Y, golem.Id .. " big head")
			local eye = model:FindFirstChild("Eye1")
			T.truthy(eye and eye.Material == roblox.Enum.Material.Neon, golem.Id .. " glowing eyes")
			T.truthy(eye.CFrame.Position.Z < head.CFrame.Position.Z - head.Size.Z / 2 + 0.05, golem.Id .. " eyes on the front")
			T.eq(body.Color, golem.Body, golem.Id .. " body colour")
		end)
		for _, golem in GolemConfig.List do
			T.eq(GolemBuilder.budget(golem.Id), GolemBuilder.MaxParts, golem.Id .. " capsule budget")
		end
	end)

	T.test("LimitedGolems: stand on their base, Height covers the gear, decoration only", function()
		for _, size in { 1, 0.85, 2.2 } do
			each(function(_, golem)
				local base = CFrame.new(-8, 3, 12) * CFrame.Angles(0, -0.7, 0)
				local model = GolemBuilder.build(golem.Id, base, { Size = size })
				local lowest, highest, neon = math.huge, -math.huge, 0
				for _, part in parts(model) do
					local lo, hi = yExtent(part)
					lowest = math.min(lowest, lo)
					highest = math.max(highest, hi)
					T.falsy(part.CanCollide or part.CanTouch or part.CanQuery, golem.Id .. " " .. part.Name .. " decoration")
					T.truthy(part.Anchored, golem.Id .. " anchored when not welded")
					if part.Material == roblox.Enum.Material.Neon then
						neon += 1
					end
					if part.CastShadow then
						T.truthy(part.Name == "Body" or part.Name == "Head", "only Body and Head cast shadows")
					end
				end
				T.near(lowest, 3, 0.02, `{golem.Id} x{size}: on the base (feet, or the aura under floating feet)`)
				local height = model:GetAttribute("Height")
				T.near(highest, 3 + height, 0.05, `{golem.Id} x{size}: Height is the measured top`)
				local local_ = base:PointToObjectSpace(model.PrimaryPart.CFrame.Position)
				T.near(local_.Y, model:GetAttribute("RootHeight"), 1e-3, golem.Id .. " RootHeight")
				local eye = base:PointToObjectSpace(model:FindFirstChild("Eye1").CFrame.Position)
				T.truthy(eye.Z < -0.5 * size, golem.Id .. " faces -Z")
				T.truthy(neon >= 3 and neon <= 16, `{golem.Id}: {neon} glowing parts`)
			end)
		end
	end)

	T.test("LimitedGolems: Legendary and Mythic hover on their aura", function()
		each(function(_, golem)
			local model = GolemBuilder.build(golem.Id)
			local premium = Rarity.ById[golem.Rarity].Order >= Rarity.ById[GolemBuilder.PremiumFrom].Order
			T.eq(GolemBuilder.premium(golem.Id), premium, golem.Id .. " premium")
			local aura = model:FindFirstChild("Aura")
			if premium then
				T.truthy(aura and aura.Material == roblox.Enum.Material.Neon, golem.Id .. " aura")
				T.near(model:GetAttribute("Hover"), GolemBuilder.Hover * golem.Scale, 1e-6, golem.Id .. " hovers")
			else
				T.falsy(aura, golem.Id .. " no aura")
				T.eq(model:GetAttribute("Hover"), 0)
			end
		end)
	end)

	T.test("LimitedGolems: welded followers move with their Body", function()
		for _, kind in { "DragonKing", "NebulaTitan", "OmegaMech", "AuroraColossus" } do
			local model = GolemBuilder.build(kind, CFrame.new(20, 1, -4), { Welded = true, Size = 0.85 })
			local body = model.PrimaryPart
			T.truthy(body.Anchored, kind .. " Body anchored")
			for _, part in parts(model) do
				if part ~= body then
					T.falsy(part.Anchored, kind .. " " .. part.Name .. " unanchored")
					local weld = part:FindFirstChildOfClass("WeldConstraint")
					T.truthy(weld and weld.Part0 == body and weld.Part1 == part, kind .. " " .. part.Name .. " welded")
				end
			end
		end
	end)

	T.test("LimitedGolems: the themed gear fits a capsule golem's 20 parts too", function()
		local seen = {}
		each(function(_, golem)
			seen[golem.Accessory] = true
		end)
		for accessory in seen do
			for _, base in { "PebbleGolem", "StormTitan" } do
				local fake = table.clone(GolemConfig.ById[base])
				fake.Id = "TestLimited" .. accessory
				fake.Accessory = accessory
				GolemConfig.ById[fake.Id] = fake
				local ok, model = pcall(GolemBuilder.build, fake.Id)
				GolemConfig.ById[fake.Id] = nil
				T.truthy(ok, accessory .. " builds on " .. base)
				T.le(GolemBuilder.partCount(model), GolemBuilder.MaxParts, accessory .. " on " .. base .. " in budget")
				if base == "StormTitan" then
					T.truthy(model:FindFirstChild("Aura"), accessory .. ": the aura always fits")
				end
			end
		end
	end)
end
