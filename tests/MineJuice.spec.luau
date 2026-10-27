-- The owner's two reels of 2026-10-27 (Config/JuiceConfig): growing rock cracks, chips, the ore
-- flying into the bag (no comic word at the break: the owner turned it down), and the level-up's
-- slow fill, WHOOSH!, ticks, ripples and rays.
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Color3 = roblox.Color3
	local Vector2 = roblox.Vector2
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance

	local JuiceConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.JuiceConfig")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local CrackLogic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.CrackLogic")
	local RockFxLogic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RockFxLogic")
	local LevelBurst = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.LevelBurst")
	local LevelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LevelView")
	local PopWord = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.PopWord")
	local BagFly = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BagFly")
	local Rules = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.MineJuiceRules")

	local function distance(a, b): number
		return math.sqrt(((a.R - b.R) * 255) ^ 2 + ((a.G - b.G) * 255) ^ 2 + ((a.B - b.B) * 255) ^ 2)
	end

	T.test("Juice: every switch is a boolean and on", function()
		for _, group in { JuiceConfig.Mining, JuiceConfig.LevelUp } do
			for name, on in group do
				T.eq(on, true, name .. " on")
			end
		end
		for _, name in { "Cracks", "Glints", "Chips", "Tok", "BagFly" } do
			T.eq(type(JuiceConfig.Mining[name]), "boolean", "Mining." .. name)
		end
		T.eq(JuiceConfig.Mining.Smash, nil, "no SMASH! switch: the word is gone (owner 2026-10-27)")
		for _, name in { "SlowFill", "Whoosh", "Chime", "Ripples", "Ticks" } do
			T.eq(type(JuiceConfig.LevelUp[name]), "boolean", "LevelUp." .. name)
		end
		T.le(JuiceConfig.CrackRocksPhone, JuiceConfig.CrackRocks, "phones crack fewer rocks")
	end)

	T.test("Juice: the glint and the dirty chunk never look like a rarity (dirty ore keeps its secret)", function()
		for _, info in Rarity.List do
			T.truthy(distance(JuiceConfig.GlintColor, info.Color) > 60, "glint unlike " .. info.Id)
			T.truthy(distance(JuiceConfig.DirtyChunk, info.Color) > 60, "dirty chunk unlike " .. info.Id)
		end
		-- the cracks and the flight take no ore colour: one constant for every rock
		local cracks = fs.readFile(Loader.root .. "/src/client/Effects/RockCracks.luau")
		T.falsy(string.find(cracks, "OreData", 1, true), "RockCracks never reads ore data")
		T.falsy(string.find(cracks, ".Glow,", 1, true) or string.find(cracks, ".Glow)", 1, true), "no ore glow colour")
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/MineJuiceController.luau")
		T.truthy(string.find(controller, "if ore then ore.Color else nil", 1, true), "only a cleaned ore (an id) gets its colour")
	end)

	T.test("Juice: a crack plan is seeded, stays in reach and grows main arm first", function()
		local a = CrackLogic.plan("10,4,-3", 2, CrackLogic.Detail)
		local b = CrackLogic.plan("10,4,-3", 2, CrackLogic.Detail)
		T.eq(#a.Points, #b.Points, "same seed, same points")
		for i, p in a.Points do
			T.near(p.X, b.Points[i].X, 1e-9, "same x " .. i)
			T.near(p.Y, b.Points[i].Y, 1e-9, "same y " .. i)
			T.le(p.Magnitude, 2 * 1.9, "point " .. i .. " within reach")
		end
		local darks, glints, flecks = CrackLogic.counts(CrackLogic.Detail)
		T.eq(#a.Segs, darks, "dark segments")
		local mains = 0
		for _, seg in a.Segs do
			if seg.Main then
				mains += 1
			end
			T.lt(seg.From, seg.To, "a segment draws in over a range")
			T.truthy(seg.From >= 0 and seg.To <= 1, "inside 0..1")
			T.truthy(seg.I >= 1 and seg.I <= #a.Points and seg.J >= 1 and seg.J <= #a.Points, "points exist")
			T.truthy(seg.Width > 0, "has a width")
		end
		T.eq(mains, glints, "a glint per main segment")
		T.eq(#a.Flecks, flecks, "flecks")
		local pd, pg, pf = CrackLogic.counts(CrackLogic.PhoneDetail)
		T.lt(pd + pg + pf, darks + glints + flecks, "phones use fewer parts")
		local phone = CrackLogic.plan(7, 2, CrackLogic.PhoneDetail)
		T.eq(#phone.Segs, pd, "phone plan size")
		-- the very first hit already shows the first main segment; branches come later
		local first = CrackLogic.growth(95, 100)
		local shown = 0
		for _, seg in a.Segs do
			if CrackLogic.fraction(seg, first) > 0 then
				shown += 1
				T.truthy(seg.Main, "only the main arms at the first hit")
			end
		end
		T.truthy(shown >= 1, "something shows after the first hit")
	end)

	T.test("Juice: the crack grows with every hit and is whole at the break", function()
		T.eq(CrackLogic.growth(100, 100), 0, "untouched")
		T.eq(CrackLogic.growth(nil, 100), 0, "no health")
		T.eq(CrackLogic.growth(50, 0), 0, "broken max")
		T.eq(CrackLogic.growth(0 / 0, 100), 0, "nan")
		local plan = CrackLogic.plan(3, 2.5)
		local last = -1
		local lastDrawn = -1
		for hp = 100, 0, -5 do
			local g = CrackLogic.growth(hp, 100)
			T.truthy(g >= last, "growth never shrinks (hp " .. hp .. ")")
			last = g
			local drawn = 0
			for _, seg in plan.Segs do
				drawn += CrackLogic.fraction(seg, g)
			end
			T.truthy(drawn >= lastDrawn, "the drawn length grows")
			lastDrawn = drawn
		end
		T.eq(CrackLogic.growth(0, 100), 1, "full at the break")
		for _, seg in plan.Segs do
			T.eq(CrackLogic.fraction(seg, 1), 1, "every segment drawn at the end")
		end
		T.truthy(CrackLogic.growth(66, 100) >= CrackLogic.GlintFrom, "the glint shows by the second crack stage")
		T.lt(CrackLogic.glint(0), CrackLogic.glint(CrackLogic.Heat), "the glint flares on a hit, then cools")
		T.eq(CrackLogic.glint(10), CrackLogic.glint(CrackLogic.Heat), "a steady glow after")
		for _, since in { 0, 0.1, 0.3, 10 } do
			T.eq(CrackLogic.glint(since, true), CrackLogic.Steady, "Reduce motion: steady, no flare (" .. since .. ")")
		end
	end)

	T.test("Juice: glints flare at most GlintFlaresPerSecond a second per rock, never with Reduce motion", function()
		local rate = JuiceConfig.GlintFlaresPerSecond
		T.truthy(rate >= 2 and rate <= 3, "2 to 3 flares a second")
		T.near(Rules.flareGap(), 1 / rate, 1e-9, "the gap")
		for _, every in { 0.05, 0.12, 0.2, 1 / 3, 0.5 } do
			local last: number? = nil
			local flares = {}
			local t = 0
			while t < 6 do
				if Rules.flare(t, last, false) then
					if last then
						T.truthy(t - last >= Rules.flareGap() - 1e-6, "never closer than the gap (hits every " .. every .. ")")
					end
					last = t
					table.insert(flares, t)
				end
				t += every
			end
			T.truthy(#flares >= 1, "the first hit flares")
			-- in any one second: no more than the rate allows
			for _, from in flares do
				local n = 0
				for _, at in flares do
					if at >= from and at < from + 1 then
						n += 1
					end
				end
				T.le(n, math.ceil(rate), "at most " .. math.ceil(rate) .. " flares in a second (hits every " .. every .. ")")
			end
			if #flares >= 3 then
				local span = flares[#flares] - flares[1]
				T.le((#flares - 1) / span, rate + 1e-6, "the long-run rate (hits every " .. every .. ")")
			end
		end
		T.truthy(Rules.flare(0, nil, false), "a fresh rock flares")
		T.falsy(Rules.flare(0, nil, true), "Reduce motion: never")
		T.falsy(Rules.flare(100, 0, true), "Reduce motion: never, however long after")
	end)

	T.test("Juice: Reduce motion stops the chips, the sparkle, the flight and the bump", function()
		T.eq(Rules.chips(false, 10, false), 3, "PC: three chips")
		T.eq(Rules.chips(false, 10, true), 2, "phone: two")
		T.eq(Rules.chips(false, JuiceConfig.ChipRange + 1, false), 0, "too far: none")
		T.eq(Rules.chips(true, 10, false), 0, "Reduce motion: none")
		T.eq(Rules.chips(false, 0 / 0, false), 0, "no distance: none")
		T.truthy(Rules.sparkle(false, 10), "the crack sparkle")
		T.falsy(Rules.sparkle(true, 10), "Reduce motion: no sparkle")
		T.falsy(Rules.sparkle(false, JuiceConfig.CrackRange + 1), "too far: no sparkle")
		T.eq(Rules.pickup(false, true, true), "Fly", "an icon free, the spot on screen: it flies")
		T.eq(Rules.pickup(false, false, true), "Bump", "every icon in the air: only the bump")
		T.eq(Rules.pickup(false, true, false), "Bump", "off screen: only the bump")
		for _, icon in { true, false } do
			for _, onScreen in { true, false } do
				T.eq(Rules.pickup(true, icon, onScreen), "Quiet", "Reduce motion: no flight, no bump")
			end
		end
		-- the controller asks these rules (and plays no bump under Reduce motion)
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/MineJuiceController.luau")
		T.truthy(string.find(controller, "MineJuiceRules.pickup(Motion.reduced()", 1, true), "the pickup asks the rule")
		T.truthy(string.find(controller, "MineJuiceRules.chips(reduced", 1, true), "the chips ask the rule")
		T.truthy(string.find(controller, "RockCracks.hit(rock, reduced)", 1, true), "the cracks get Reduce motion")
		T.truthy(
			string.find(controller, 'Sfx.play("BagPop")\n\tif Motion.reduced() then\n\t\treturn\n\tend', 1, true),
			"land: no bump under Reduce motion"
		)
	end)

	T.test("Juice: crack frames lie on the face, along the segment", function()
		for _, normal in { Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0.3, -0.9, 0.2).Unit } do
			local right, up = CrackLogic.basis(normal)
			T.near(right.Magnitude, 1, 1e-6, "right is unit")
			T.near(up.Magnitude, 1, 1e-6, "up is unit")
			T.near(right:Dot(normal), 0, 1e-6, "right in the face")
			T.near(up:Dot(normal), 0, 1e-6, "up in the face")
			T.near(right:Dot(up), 0, 1e-6, "right and up apart")
			local a = CrackLogic.flatPoint(Vector3.new(1, 2, 3), right, up, Vector2.new(0, 0))
			local b = CrackLogic.flatPoint(Vector3.new(1, 2, 3), right, up, Vector2.new(1.5, -0.5))
			local cf, length = CrackLogic.segmentFrame(a, b, normal, 0.03)
			T.near(length, (b - a).Magnitude, 1e-6, "length")
			T.near(cf.LookVector:Dot((b - a).Unit), 1, 1e-4, "runs along the segment")
			T.near(cf.UpVector:Dot(normal), 1, 1e-4, "thickness out of the surface")
			T.near((cf.Position - (a + b) / 2 - normal * 0.03).Magnitude, 0, 1e-6, "in the middle, lifted")
		end
		local _, zero = CrackLogic.segmentFrame(Vector3.zero, Vector3.zero, Vector3.new(0, 1, 0), 0)
		T.eq(zero, 0, "a zero segment has no length")
		T.near(CrackLogic.sizeFor(Vector3.new(5, 4, 6)), 5 * 0.42, 1e-6, "the middle size")
		T.eq(CrackLogic.sizeFor(Vector3.new(0.5, 0.5, 0.5)), 0.8, "small rocks clamp")
		T.eq(CrackLogic.sizeFor(Vector3.new(40, 40, 40)), 4.5, "a giant clamps")
	end)

	T.test("Juice: a hit's chips are few, in the crust colours only, out of the face and under the cap", function()
		local crust = Color3.fromRGB(150, 130, 110)
		local out = Vector3.new(0, 0, 1)
		local pieces = RockFxLogic.chipPlan({ Position = Vector3.new(0, 3, 0), Crust = crust, Out = out, Ground = 0, Seed = 4 })
		T.eq(#pieces, 3, "three by default")
		for _, p in pieces do
			T.falsy(p.Neon, "no glowing chips")
			T.truthy(distance(p.Color, crust) < 90, "a crust shade")
			T.truthy(p.Velocity:Dot(out) > 0, "out of the face")
			T.le(p.Life, RockFxLogic.MaxLife, "short-lived")
			local _, _, _, done = RockFxLogic.sample(p, p.Life + 0.01)
			T.truthy(done, "gone after its life")
		end
		T.eq(#RockFxLogic.chipPlan({ Position = Vector3.zero, Crust = crust, Alive = RockFxLogic.Cap }), 0, "none when full")
		T.eq(#RockFxLogic.chipPlan({ Position = Vector3.zero, Crust = crust, Alive = RockFxLogic.Cap - 1, Count = 3 }), 1, "only what fits")
		T.eq(#RockFxLogic.chipPlan({ Position = Vector3.zero, Crust = crust, Count = 2 }), 2, "phones ask for two")
	end)

	T.test("Juice: WHOOSH! and +1 pop, then hide; Reduce motion fades them straight", function()
		local gui = Instance.new("ScreenGui")
		local word = PopWord.build(gui, "+1", 34, { Tilt = -8 })
		T.falsy(word.Holder.Visible, "hidden until posed")
		local peak = 0
		for t = 0, word.Seconds + 0.1, 0.02 do
			local done = PopWord.pose(word, t)
			peak = math.max(peak, word.Scale.Scale)
			if t < word.Seconds then
				T.falsy(done, "still playing at " .. t)
				T.truthy(word.Holder.Visible, "shows at " .. t)
			end
		end
		T.truthy(peak > 1, "pops in with an overshoot")
		T.truthy(PopWord.pose(word, word.Seconds + 0.01), "done")
		T.falsy(word.Holder.Visible, "hidden after")
		PopWord.pose(word, 0.1, true)
		T.eq(word.Scale.Scale, 1, "reduced: full size")
		T.eq(word.Inner.Rotation, 0, "reduced: straight")
		local whoosh = PopWord.build(gui, "WHOOSH!", 34, { Lines = true })
		T.eq(#whoosh.Lines, 3, "three speed lines")
		PopWord.pose(whoosh, 0.2)
	end)

	T.test("Juice: the ore pops up at the pickup, then lands on the slot; the bump ends", function()
		local view = BagFly.build()
		T.eq(view.Gui.Name, "TerraForgeJuice", "its own overlay")
		T.eq(#view.Flyers, JuiceConfig.Flyers, "pooled icons")
		T.eq((view :: any).Smash, nil, "no SMASH! word on the overlay")
		for _, d in view.Gui:GetDescendants() do
			if d:IsA("TextLabel") then
				T.falsy(string.find(d.Text, "SMASH", 1, true), "no SMASH! text anywhere")
			end
		end
		local f = view.Flyers[1]
		local from, to = Vector2.new(400, 300), Vector2.new(640, 680)
		BagFly.poseFlyer(f, from, to, BagFly.Rise * 0.99, 1, 1.3)
		T.lt(f.Holder.Position.Y.Offset, from.Y - BagFly.RiseHeight * 0.8, "floats up first")
		BagFly.poseFlyer(f, from, to, BagFly.Rise + BagFly.Fly * 0.999, 1, 1.3)
		T.near(f.Holder.Position.X.Offset, to.X, 3, "lands on the slot (x)")
		T.near(f.Holder.Position.Y.Offset, to.Y, 3, "lands on the slot (y)")
		T.truthy(BagFly.poseFlyer(f, from, to, BagFly.Rise + BagFly.Fly + 0.01, 1, 1.3), "done")
		T.falsy(f.Holder.Visible, "hidden after")
		BagFly.setOre(f, nil)
		T.truthy(f.Dirty and f.Flecks[1].Visible, "dirty: stone with gold flecks")
		BagFly.setOre(f, OreData.ById[OreData.List[1].Id].Color)
		T.falsy(f.Dirty or f.Flecks[1].Visible, "a cleaned ore: its gem")
		local b = view.Bumps[1]
		local done = false
		for t = 0, 1.2, 0.05 do
			done = BagFly.poseBump(b, to, Vector2.new(70, 70), t, 1)
		end
		T.truthy(done, "the bump ends")
		T.falsy(b.Ring.Visible, "its ring hides")
	end)

	T.test("Juice: the level-up fill races, then creeps to full", function()
		for _, from in { 0, 0.3, 0.8 } do
			T.near(LevelView.fillCurve(from, 0), from, 1e-9, "starts where it was")
			T.near(LevelView.fillCurve(from, 1), 1, 1e-9, "ends full")
			local last = from
			for u = 0, 1, 0.02 do
				local v = LevelView.fillCurve(from, u)
				T.truthy(v >= last - 1e-9, "never goes back")
				last = v
			end
			local rest = 1 - from
			local atKnee = LevelView.fillCurve(from, LevelView.FillKnee) - from
			T.truthy(atKnee >= rest * 0.8, "most of the way in the first part (races)")
			local early = LevelView.fillCurve(from, 0.1) - LevelView.fillCurve(from, 0)
			local late = LevelView.fillCurve(from, 0.97) - LevelView.fillCurve(from, 0.87)
			T.lt(late, early * 0.5, "much slower right before full (hold your breath)")
		end
		T.lt(LevelView.fillSeconds(0.9), LevelView.fillSeconds(0), "a short way is quicker")
		T.le(LevelView.fillSeconds(0) + LevelView.FullHold, 1.8, "never drags")
	end)

	T.test("Juice: reward rows tick in one by one, the coins in clicks", function()
		local m = { Level = 12, Coins = 1350, Bonus = 0.12, Increase = 0.01, Milestone = true }
		T.eq(LevelView.ticks(0, m), 0, "nothing before the rows")
		local last = 0
		for t = 0, LevelView.MomentSeconds, 0.01 do
			local n = LevelView.ticks(t, m)
			T.truthy(n >= last, "ticks only add up")
			T.le(n - last, 1, "one click at a time (at 100 fps)")
			last = n
		end
		T.eq(last, 3 + LevelView.CoinTicks, "a click per row and per coins step")
		T.eq(LevelView.ticks(LevelView.MomentSeconds, m, true), 3, "reduced: one per row, no counting")
		T.lt(LevelView.rowAt(1), LevelView.rowAt(2), "coins first")
		T.lt(LevelView.rowAt(2), LevelView.rowAt(3), "then income, then the milestone")
		local step, since = LevelView.coinStep(LevelView.rowAt(1) + 5, LevelView.rowAt(1))
		T.eq(step, LevelView.CoinTicks, "every click at the end")
		T.truthy(since > 0, "the last click is behind")
		local view = LevelView.build()
		for t = 0, LevelView.MomentSeconds, 0.05 do
			LevelView.poseMoment(view, t, m)
		end
		LevelView.poseMoment(view, LevelView.rowAt(1) + 0.95 + 0.01, m)
		T.eq(view.Rows[1].Amount.Text, "+$1.35K", "the coins land on the exact amount")
		LevelView.poseMoment(view, 1.0, m, true)
		T.eq(view.Rows[1].Bump.Scale, 1, "reduced: no bump")
	end)

	T.test("Juice: the full bar flashes, WHOOSH! pops by the bar", function()
		local view = LevelView.build()
		LevelView.poseFull(view, 1)
		T.lt(view.Hot.BackgroundTransparency, 0.3, "white-hot when full")
		T.truthy(view.BarScale.Scale > 1, "the bar swells")
		LevelView.poseGlow(view, 0, 0)
		LevelView.poseFull(view, 0)
		T.eq(view.Hot.BackgroundTransparency, 1, "gone after")
		LevelView.poseGlow(view, 1, 0, true)
		LevelView.poseFull(view, 1, true)
		T.eq(view.BarScale.Scale, 1, "reduced: the bar never grows")
		T.eq(view.Hot.BackgroundTransparency, 1, "reduced: no white-hot flash")
		T.eq(view.Whoosh.Holder.Parent, view.Bar, "WHOOSH! sits on the bar")
		T.falsy(LevelView.poseWhoosh(view, 0.3), "playing")
		T.truthy(view.Whoosh.Holder.Visible, "shows while it fills")
		T.truthy(LevelView.poseWhoosh(view, LevelView.WhooshSeconds + 0.01), "done")
	end)

	T.test("Juice: rays shoot out of the character, three rings ripple out across the floor", function()
		local model = Instance.new("Model")
		local burst = LevelBurst.build(model, roblox.CFrame.new(0, 0, 0), false)
		T.eq(#burst.Rays, LevelBurst.Rays, "rays")
		T.eq(#burst.Ripples, LevelBurst.Ripples, "ripples")
		for _, bars in burst.Ripples do
			T.eq(#bars, LevelBurst.RippleBars, "bars per ring")
		end
		local plain = LevelBurst.build(Instance.new("Model"), roblox.CFrame.new(0, 0, 0), false, false)
		T.eq(#plain.Rays + #plain.Ripples, 0, "switched off: none built")
		LevelBurst.pose(plain, 0.5)
		-- each ring runs out wider and wider, one after another, low on the floor
		local function radius(r: number, t: number): number?
			LevelBurst.pose(burst, t)
			local bar = burst.Ripples[r][1]
			if bar.Transparency >= 1 then
				return nil
			end
			T.le(bar.CFrame.Position.Y, 0.3, "on the floor")
			local p = bar.CFrame.Position
			return math.sqrt(p.X * p.X + p.Z * p.Z)
		end
		T.eq(radius(3, 0.1), nil, "the third ring waits")
		local r1a, r1b = radius(1, 0.2), radius(1, 0.6)
		T.truthy(r1a and r1b and r1b > r1a, "ring 1 runs out")
		local r3 = radius(3, 0.8)
		T.truthy(r3 ~= nil and r3 < (radius(1, 0.8) or 0), "the later ring is behind")
		LevelBurst.pose(burst, 0.1)
		local ray = burst.Rays[1]
		T.lt(ray.Transparency, 1, "rays show at once")
		T.truthy(ray.CFrame.Position.Y > 2, "out of the chest")
		LevelBurst.pose(burst, LevelBurst.Seconds + 0.1)
		for _, r in burst.Rays do
			T.eq(r.Transparency, 1, "rays gone at the end")
		end
		for _, bars in burst.Ripples do
			T.eq(bars[1].Transparency, 1, "ripples gone at the end")
		end
		T.le(LevelBurst.Rays + LevelBurst.Ripples * LevelBurst.RippleBars, 60, "phone budget for the extras")
	end)

	T.test("Juice: the new sounds exist, play once and are Roblox-made ids or shipped files", function()
		T.eq(SoundConfig.RockSmash, nil, "no SMASH! boom")
		for _, name in { "RockTok", "RockCrunch", "BagRise", "BagPop", "LevelWhoosh", "LevelChime", "LevelTick" } do
			local def = SoundConfig[name]
			T.truthy(def, "sound " .. name)
			T.falsy(def.Looped, name .. " plays once")
			T.truthy(string.match(def.Id, "^rbxassetid://%d+$") or string.match(def.Id, "^rbxasset://sounds/"), name .. " id")
			T.truthy(def.Volume > 0 and def.Volume <= 0.6, name .. " volume")
		end
	end)

	T.test("Juice: the controller is in the client ORDER after the world motion", function()
		local init = fs.readFile(Loader.root .. "/src/client/init.client.luau")
		local at = string.find(init, '"MineJuiceController"', 1, true)
		local world = string.find(init, '"WorldMotionController"', 1, true)
		T.truthy(at and world and world < at, "in the ORDER after WorldMotionController")
	end)
end
