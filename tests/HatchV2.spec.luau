-- Hatch v2 (owner 2026-10-29: "much, much better, like Pet Simulator"; docs/plans/HATCH_V2.md):
-- the timings (normal, Auto's fast, Reduce motion's short), every result shown at least MinShow,
-- the rarity tiers and their looks (RevealFx, shared with the secret ores), the flash cap, the
-- stage for one egg, Open 3 and Open 10 (a row, two rows of five, every egg and golem on it), the
-- eggs' flight and the rare egg's suspense staying in bounds, and the reveal built, posed and
-- pooled without the game's services (Manual).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector2 = roblox.Vector2
	local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
	local RevealFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealFx")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")

	T.test("HatchV2: the timings (fly, wobble, suspense, ripple, pops, hold, jackpot) normal, fast and reduced", function()
		for order = 1, 6 do
			for _, count in { 1, 3, 10 } do
				local normal = HatchFx.timeline(order, count, false, false)
				local fast = HatchFx.timeline(order, count, true, false)
				local reduced = HatchFx.timeline(order, count, false, true)
				local where = `order {order}, {count} eggs`
				T.eq(#normal.Burst, count, where .. ": a burst per egg")
				T.eq(#normal.Pop, count, where .. ": a golem per egg")
				-- in order: fly, wobble, (suspense), bursts in a ripple, each golem right after its egg
				T.near(normal.Burst[1], normal.Fly + normal.Shake + normal.Suspense, 1e-9, where)
				for i = 1, count do
					T.truthy(normal.Pop[i] > normal.Burst[i], where .. ": the golem after its egg bursts")
					if i > 1 then
						T.near(normal.Burst[i] - normal.Burst[i - 1], HatchFx.Ripple, 1e-9, where .. ": a quick ripple")
					end
				end
				T.truthy(normal.Total >= normal.Pop[count] + HatchFx.MinShow - 1e-9, where .. ": every golem shows MinShow at least")
				-- PS99's rhythm: short; the batch's ripple well under a second
				T.truthy(normal.Fly <= 0.4 and normal.Burst[count] - normal.Burst[1] < 1, where)
				T.truthy(normal.Total < 9, where .. ": a hatch never drags")
				-- Auto: faster, every golem still shown
				T.truthy(fast.Total < normal.Total, where .. ": fast is faster")
				T.truthy(fast.Total >= fast.Pop[count] + HatchFx.MinShow - 1e-9, where .. ": fast still shows every result")
				-- Reduce motion: no flight to speak of, no suspense, no ripple, still every result
				T.eq(reduced.Suspense, 0, where .. ": no suspense")
				T.eq(reduced.Ripple, 0, where .. ": no ripple")
				T.truthy(reduced.Shake <= 0.4 + 1e-9, where .. ": a short wobble")
				T.truthy(reduced.Total >= reduced.Pop[count] + HatchFx.MinShow - 1e-9, where .. ": reduced shows every result")
				-- the rare moments: Legendary and Mythic gather light and get their jackpot
				if order >= 5 then
					T.truthy(normal.Suspense > 0.8, where .. ": suspense")
					T.truthy(normal.Jackpot >= 2, where .. ": a jackpot moment")
					if count > 1 then
						T.truthy(normal.JackpotAt >= normal.Pop[count] + normal.Hold - 1e-9, where .. ": after the batch shows")
						T.near(normal.Total, normal.JackpotAt + normal.Jackpot, 1e-9)
					end
				else
					T.eq(normal.Suspense, 0, where)
					T.eq(normal.Jackpot, 0, where)
					T.eq(normal.JackpotAt, math.huge, where)
				end
			end
		end
		-- a rarer golem: a longer wobble (the build-up tells it)
		T.truthy(HatchFx.timeline(4, 1, false, false).Shake > HatchFx.timeline(1, 1, false, false).Shake)
		-- junk in: the nearest sane timeline
		T.eq(HatchFx.timeline(0 / 0, 0 / 0, false, false).Count, 1)
		T.eq(HatchFx.timeline(3, 99, false, false).Count, 10)
	end)

	T.test("HatchV2: the stage for one egg, Open 3 and Open 10 (a row, two rows of five, all in view)", function()
		local tan15 = math.tan(math.rad(15))
		for _, case in { { 1, 1 }, { 3, 2.4 }, { 10, 2.4 }, { 10, 1.6 }, { 3, 1.3 } } do
			local n, aspect = case[1], case[2]
			local stage = HatchFx.stage(n, aspect)
			T.eq(#stage.Spots, n)
			T.eq(#stage.Cells, n)
			for i, spot in stage.Spots do
				-- every egg (and golem, about 4.6 studs) inside the camera's view with a margin
				local halfH = stage.Distance * tan15
				local halfW = halfH * aspect
				T.truthy(math.abs(spot.Y) + 2.3 <= halfH + 1e-6, `{n} eggs: egg {i} inside top / bottom`)
				T.truthy(math.abs(spot.X) + 2 <= halfW + 1e-6, `{n} eggs: egg {i} inside left / right`)
				local cell = stage.Cells[i]
				T.truthy(cell.X > 0 and cell.X < 1 and cell.Y > 0 and cell.Y < 1, "its cell on the viewport")
			end
			if n == 3 then
				-- a row, in reading order (the stage's +X shows on the left)
				T.eq(stage.Spots[1].Y, stage.Spots[3].Y)
				T.truthy(stage.Cells[1].X < stage.Cells[2].X and stage.Cells[2].X < stage.Cells[3].X, "left to right")
			elseif n == 10 then
				-- two rows of five, the first row on top
				for i = 1, 5 do
					T.truthy(stage.Cells[i].Y < stage.Cells[i + 5].Y, "row 1 over row 2")
					T.near(stage.Cells[i].X, stage.Cells[i + 5].X, 1e-6, "in columns")
				end
				T.truthy(stage.Cells[1].X < stage.Cells[5].X, "left to right")
				-- the tags (the golems' names) fit their cells side by side
				T.truthy(stage.Cell.X * 5 <= 1 + 1e-6)
			end
		end
		-- one egg: big in the middle of the hero
		local one = HatchFx.stage(1, 1)
		T.near(one.Cells[1].X, 0.5, 1e-9)
		T.truthy(GolemBuilder.CapsuleHeight / (2 * one.Distance * tan15) > 0.75, "one egg fills most of the hero")
	end)

	T.test("HatchV2: the eggs fly in and the rare egg gathers light, in bounds", function()
		local k0, s0, spin0 = HatchFx.flyAt(0, HatchFx.FlyTime)
		T.near(k0, 0, 1e-9, "from below")
		T.truthy(s0 < 0.5 and spin0 > 4, "small and spinning")
		local k1, s1, spin1 = HatchFx.flyAt(HatchFx.FlyTime, HatchFx.FlyTime)
		T.eq(k1, 1)
		T.eq(s1, 1)
		T.eq(spin1, 0, "in its place, still")
		local over = 0
		for i = 1, 40 do
			over = math.max(over, (HatchFx.flyAt(i / 40 * HatchFx.FlyTime, HatchFx.FlyTime)))
		end
		T.truthy(over > 1.02 and over < 1.2, "a bounce past its place")
		T.eq(select(1, HatchFx.flyAt(1, 0)), 1, "no flight (Reduce motion's 0): in place")
		for i = 0, 20 do
			local lift, swell, tremble, glow = HatchFx.suspenseAt(i / 20 * HatchFx.Suspense, HatchFx.Suspense)
			T.truthy(lift >= 0 and lift <= 0.4 + 1e-9, "a small rise (the hero clips)")
			T.truthy(swell >= 1 and swell <= 1.1 + 1e-9, "a small swell")
			T.truthy(math.abs(tremble) <= 0.05 + 1e-9, "a fine tremble")
			T.truthy(glow >= 0 and glow <= 1)
		end
		-- a pooled egg posed through the whole v2 hatch and back whole
		local CFrame = Loader.CFrame
		local Color3 = roblox.Color3
		local tl = HatchFx.timeline(5, 3, false, false)
		local plan = HatchFx.plan(5)
		local rec = HatchFx.record(GolemBuilder.capsule("Crystal"))
		local steps = 0
		local t = 0
		while t < tl.Burst[2] + HatchFx.BurstTime + 0.1 do
			local glow = HatchFx.poseV2(rec, CFrame.new(), t, tl, 2, plan, Color3.new(1, 0.8, 0.2), false, true)
			T.truthy(glow >= 0 and glow <= 1, "its light")
			for _, part in rec.Parts do
				T.truthy(part.CFrame.Position.Magnitude < 40, "never flung away")
			end
			t += 0.05
			steps += 1
		end
		T.truthy(steps > 40)
		T.truthy(rec.Faded, "gone after its break")
		HatchFx.reset(rec)
		T.falsy(rec.Faded, "back whole")
	end)

	T.test("HatchV2: RevealFx tiers, palettes and the shared flash cap", function()
		T.eq(RevealFx.tierOf("Common"), "Normal")
		T.eq(RevealFx.tierOf("Uncommon"), "Normal")
		T.eq(RevealFx.tierOf("Rare"), "Rare")
		T.eq(RevealFx.tierOf("Epic"), "Rare")
		T.eq(RevealFx.tierOf("Legendary"), "Jackpot")
		T.eq(RevealFx.tierOf("Mythic"), "Jackpot")
		T.eq(RevealFx.tierOf("Secret"), "Secret", "the secret ores' tier")
		T.eq(RevealFx.tierOf("NoSuch"), "Normal")
		-- bigger moments for rarer things
		local tiers = RevealFx.Tiers
		T.truthy(tiers.Rare.Rays > tiers.Normal.Rays and tiers.Jackpot.Rays > tiers.Rare.Rays)
		T.truthy(tiers.Jackpot.Back ~= 0 and tiers.Secret.Back ~= 0, "two ray layers for the jackpots")
		T.truthy(tiers.Jackpot.Confetti > 0 and tiers.Jackpot.Shake > 0 and tiers.Jackpot.Headline)
		T.falsy(tiers.Normal.Headline)
		T.truthy(RevealFx.PhoneRays <= 12 and RevealFx.PhoneConfetti <= 24, "phones: capped")
		-- headlines
		T.eq(RevealFx.headlineFor("Jackpot", "Legendary"), "LEGENDARY!")
		T.eq(RevealFx.headlineFor("Jackpot", "Mythic"), "MYTHIC!")
		T.eq(RevealFx.headlineFor("Secret", "Secret"), "SECRET!")
		T.eq(RevealFx.headlineFor("Rare", "Epic"), "EPIC!")
		T.eq(RevealFx.headlineFor("Normal", "Common"), nil)
		-- colours: Legendary gold, Mythic a drifting rainbow, Secret black and rainbow
		local gold = RevealFx.palette("Legendary")
		T.truthy(gold.Light.R > 0.9 and gold.Light.G > 0.75 and gold.Light.B < 0.4, "gold")
		local a = RevealFx.rayColor("Mythic", 1, 10, 0)
		local b = RevealFx.rayColor("Mythic", 1, 10, 1)
		T.truthy(a ~= b, "Mythic's rainbow drifts")
		T.eq(RevealFx.rayColor("Secret", 2, 10, 0), RevealFx.palette("Secret").Dark, "every other Secret ray near-black")
		T.truthy(RevealFx.palette("Secret").Black)
		for _, info in Rarity.List do
			local p = RevealFx.palette(info.Id)
			T.truthy(p.Light and p.Dark and p.Glow and p.Flash, info.Id .. ": a full palette")
		end
		-- the flash cap: 2.5 a second at most, one clock for every reveal
		T.truthy(1 / RevealFx.FlashGap <= 2.5 + 1e-9, "at most 2.5 flashes a second")
		T.falsy(RevealFx.flashOk(10, 10 + RevealFx.FlashGap - 0.01))
		T.truthy(RevealFx.flashOk(10, 10 + RevealFx.FlashGap))
		T.truthy(RevealFx.FlashPeak < 1, "never fully opaque")
		local source = require("@lune/fs").readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		T.truthy(string.find(source, "RevealFx.flash(", 1, true), "the egg's break flash goes through the same clock")
		T.falsy(string.find(source, "TweenService:Create(o.Flash", 1, true), "no flash of its own")
		-- the pose curves stay in bounds
		for i = 0, 40 do
			local t = i / 40
			T.truthy(RevealFx.swellAt(t) > 0.3 and RevealFx.swellAt(t) < 1.2)
			T.truthy(RevealFx.headlineAt(t) >= 0.3 and RevealFx.headlineAt(t) <= 1.15 + 1e-9)
		end
		T.near(RevealFx.swellAt(1), 1, 1e-9)
		T.eq(RevealFx.inAt(0, 0), 0, "the banner comes in after")
		T.eq(RevealFx.inAt(1, 0.2), 1)
	end)

	T.test("HatchV2: RevealFx shows into a caller's frame, posed by hand (Manual), and pools on close", function()
		local parent = Instance.new("Frame")
		local reduced = RevealFx.show("Golem", "HeartstoneColossus", "Mythic", {
			Parent = parent,
			Chance = "0.03%",
			New = true,
			Manual = true,
			Flash = false,
			Sound = false,
			Shake = false,
			Reduced = true,
			Phone = true,
		})
		T.eq(reduced.Tier, "Jackpot")
		T.eq(reduced.Root.Parent, parent, "in the caller's frame")
		T.eq(reduced.NameLabel.Text, "Heartstone Colossus", "the golem's name")
		T.eq(reduced.PillLabel.Text, "MYTHIC")
		T.eq(reduced.ChanceLabel.Text, "0.03%", "its chance")
		T.truthy(reduced.NewLabel.Visible)
		T.eq(reduced.Headline.Text, "MYTHIC!")
		T.eq(#reduced.Sparkles + #reduced.Confetti, 0, "Reduce motion: no pieces")
		local bars = 0
		for _, list in reduced.RayFrames do
			bars += #list
		end
		T.truthy(bars * 2 <= RevealFx.PhoneRays, "phones: 12 rays at most")
		reduced:pose(2)
		T.eq(reduced.Layers[1].Rotation, 0, "Reduce motion: the rays stand still")
		T.eq(reduced.NameLabel.TextTransparency, 0, "and the banner just shows")
		reduced:close()
		T.eq(reduced.Root.Parent, nil, "closed: let go")
		-- the pool hands the same frames back, filled anew (a secret ore, no banner)
		local secret = RevealFx.show("Ore", "NoSuchOre", "Secret", {
			Parent = parent,
			Chance = "1 in 25,000",
			Banner = false,
			Manual = true,
			Flash = false,
			Sound = false,
			Shake = false,
			Reduced = false,
			Phone = false,
		})
		T.eq(secret.Root, reduced.Root, "pooled")
		T.eq(secret.Tier, "Secret")
		T.eq(secret.Headline.Text, "SECRET!")
		-- rainbow LETTERS on a plain dark edge (a gradient on the stroke smudges inside the letters)
		local edge = secret.Headline:FindFirstChildOfClass("UIStroke")
		T.truthy(edge and edge:FindFirstChildOfClass("UIGradient") == nil, "the edge stays plain")
		T.truthy(#secret.HeadlineGradient.Color.Keypoints >= 6, "the letters a rainbow")
		T.falsy(secret.Banner.Visible, "no banner when asked")
		T.truthy(#secret.Confetti > 0, "a jackpot's confetti")
		secret:pose(0.5)
		T.truthy(secret.Layers[1].Rotation > 0 and #secret.Layers == 2, "two layers turning")
		secret:close()
		-- text sizes: 18 px at 1080p (the HUD's 1.25), 8 pt on a phone (0.62)
		T.truthy(secret.ChanceLabel.TextSize * 0.62 >= 8 and secret.ChanceLabel.TextSize * 1.25 >= 18)
		T.truthy(secret.PillLabel.TextSize * 1.25 >= 18)
		local _ = Vector2
	end)
end
