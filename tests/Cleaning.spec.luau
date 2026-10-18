-- Cleaning minigame: patterns are valid and deterministic; scoring rewards
-- accuracy, punishes chips, and rejects impossible (cheated) input.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Geometry2D = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.Geometry2D")
	local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
	local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningScoring")
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2

	-- Simulated player. offset = distance from the line in tolerance units (inward if negative).
	-- t0 = session clock when the cut starts (all steps share one clock).
	local function traceCut(cut, speed, offset, tol, jitter, t0)
		local samples = {}
		local t = t0 or 0
		local step = 1 / 60
		local s = 0
		while s <= cut.Length do
			local p, tangent = Geometry2D.pointAt(cut.Line, s)
			local normal = Vector2.new(-tangent.Y, tangent.X)
			-- make +offset point away from the core (outward), -offset into the core
			if normal:Dot(p) < 0 then
				normal = -normal
			end
			local wobble = if jitter then math.sin(s * 37) * jitter * tol else 0
			local q = p + normal * (offset * tol + wobble)
			table.insert(samples, q.X)
			table.insert(samples, q.Y)
			table.insert(samples, t)
			s += speed * step
			t += step
		end
		local last = cut.Line[#cut.Line]
		table.insert(samples, last.X)
		table.insert(samples, last.Y)
		table.insert(samples, t)
		return samples
	end

	-- Records brush positions like the client: feed every position to the
	-- shared tracker, keep only the ones that removed dirt or snapped a crystal.
	local function recordBrush(pattern, points)
		local tracker = Scoring.ScrapeTracker.new(pattern)
		local samples = {}
		for _, point in points do
			local removed, snapped = tracker:add(point.p, point.t)
			if #removed > 0 or #snapped > 0 then
				table.insert(samples, point.p.X)
				table.insert(samples, point.p.Y)
				table.insert(samples, point.t)
			end
		end
		return { Samples = samples }, tracker
	end

	-- Brush onto each dirt patch in turn (and onto the crystals if clumsy).
	local function scrapeAll(pattern, perSecond, hitFragile, t0)
		local points = {}
		local t = (t0 or 0) + 0.2
		for _, d in pattern.Dirt do
			if not d.Fragile or hitFragile then
				table.insert(points, { p = d.Center, t = t })
				t += 1 / perSecond
			end
		end
		local scrape = recordBrush(pattern, points)
		return scrape, t
	end

	-- Zig-zag scrubbing over the whole core at `speed` face units per second, 60 fps.
	local function scrub(pattern, speed, t0)
		local points = {}
		local t = t0 or 0
		local minU, maxU, minV, maxV = math.huge, -math.huge, math.huge, -math.huge
		for _, p in pattern.Core do
			minU, maxU = math.min(minU, p.X), math.max(maxU, p.X)
			minV, maxV = math.min(minV, p.Y), math.max(maxV, p.Y)
		end
		local rows = math.ceil((maxV - minV) / 0.2) + 1
		for row = 0, rows do
			local v = minV + row * (maxV - minV) / rows
			local fromU, toU = minU, maxU
			if row % 2 == 1 then
				fromU, toU = maxU, minU
			end
			local length = math.abs(toU - fromU)
			local steps = math.max(1, math.ceil(length / (speed / 60)))
			for i = 0, steps do
				table.insert(points, { p = Vector2.new(fromU + (toU - fromU) * i / steps, v), t = t })
				t += 1 / 60
			end
		end
		return recordBrush(pattern, points)
	end

	local function polishCircles(turns, radPerSecond, mode, t0)
		local samples = {}
		local t, angle = t0 or 0, 0
		local total = 0
		while total < turns * math.pi * 2 do
			local wrapped = math.atan2(math.sin(angle), math.cos(angle))
			table.insert(samples, t)
			table.insert(samples, wrapped)
			t += 1 / 30
			angle += radPerSecond / 30
			total += radPerSecond / 30
		end
		return { Samples = samples, Mode = mode or "Circle" }
	end

	-- A whole honest session on one clock: cuts one after another, then scrape, then polish.
	local function submission(pattern, speedFactor, offset, jitter, opts)
		opts = opts or {}
		local clock = opts.start or 1
		local cuts = {}
		for _, cut in pattern.Cuts do
			local samples = traceCut(cut, pattern.MaxCutSpeed * speedFactor, offset, pattern.Tolerance, jitter, clock)
			table.insert(cuts, { Samples = samples })
			clock = samples[#samples] + 1.2 -- the crack animation
		end
		local scrape, scrapeEnd = scrapeAll(pattern, opts.scrapeRate or 12, opts.hitFragile, clock)
		return {
			Cuts = cuts,
			Scrape = scrape,
			Polish = polishCircles(pattern.PolishTurns + 0.2, opts.polishSpeed or 4.5, opts.polishMode, scrapeEnd + 1),
			Input = opts.input or "Mouse",
		}
	end

	T.test("patterns: every ore and many seeds give valid, convex, solvable jobs", function()
		for _, ore in OreData.List do
			local rarity = Rarity.get(ore.Rarity)
			for seed = 1, 40 do
				local p = Patterns.generate(ore.Id, seed * 7919)
				T.truthy(#p.Cuts >= math.max(2, rarity.Cuts - 1), `{ore.Id} seed {seed}: cuts {#p.Cuts}`)
				T.truthy(math.abs(Geometry2D.area(p.Core)) > 0.45, `{ore.Id} seed {seed}: core too small`)
				T.truthy(Geometry2D.containsConvex(p.Core, Vector2.zero), `{ore.Id} seed {seed}: center not in core`)
				T.truthy(p.DirtCount >= 6, `{ore.Id} seed {seed}: dirt {p.DirtCount}`)
				for _, cut in p.Cuts do
					T.truthy(cut.Length > 0.3, "cut length")
					T.truthy(#cut.Caps >= 1, "cut removes crust")
				end
			end
		end
	end)

	T.test("patterns: same seed -> identical pattern (client == server)", function()
		local a = Patterns.generate("Gold", 123456)
		local b = Patterns.generate("Gold", 123456)
		T.eq(#a.Cuts, #b.Cuts)
		for i, cut in a.Cuts do
			for j, point in cut.Line do
				T.eq(point, b.Cuts[i].Line[j])
			end
		end
		T.eq(#a.Dirt, #b.Dirt)
	end)

	T.test("scoring: careful player gets Flawless on every rarity", function()
		for _, ore in OreData.List do
			local p = Patterns.generate(ore.Id, 2024)
			local r = Scoring.score(p, submission(p, 0.5, 0, 0.1))
			T.truthy(r.Valid, `{ore.Id}: {r.Reason}`)
			T.eq(r.Grade, "Flawless", `{ore.Id} grade (score {r.Score})`)
			T.eq(r.Chips, 0, ore.Id .. " chips")
		end
	end)

	T.test("scoring: sloppy lines give a lower grade, never a fail", function()
		local p = Patterns.generate("Silver", 77)
		local careful = Scoring.score(p, submission(p, 0.5, 0, 0.1))
		local sloppy = Scoring.score(p, submission(p, 0.5, 1.4, 0.8))
		T.truthy(sloppy.Valid, sloppy.Reason)
		T.lt(sloppy.Score, careful.Score, "sloppy < careful")
		T.truthy(sloppy.Grade ~= "Flawless", "sloppy is not flawless")
	end)

	T.test("scoring: cutting into the core chips the ore", function()
		local p = Patterns.generate("Emberite", 5)
		local r = Scoring.score(p, submission(p, 0.5, -2.2, 0))
		T.truthy(r.Valid, r.Reason)
		T.truthy(r.Chips >= 1, "chips counted")
	end)

	T.test("scoring: rushing the chisel and hitting fragile spots costs grade", function()
		local p = Patterns.generate("Gold", 99)
		local calm = Scoring.score(p, submission(p, 0.5, 0, 0.1))
		local rushed = Scoring.score(p, submission(p, 1.6, 0, 0.1))
		T.truthy(rushed.Valid, rushed.Reason)
		T.lt(rushed.Chisel, calm.Chisel, "too fast lowers chisel score")
		local clumsy = Scoring.score(p, submission(p, 0.5, 0, 0.1, { hitFragile = true }))
		T.truthy(clumsy.FragileHits >= 1, "fragile hits counted")
		T.lt(clumsy.Scrape, calm.Scrape, "fragile hits lower scrape score")
	end)

	T.test("scoring: rub mode (accessibility) works but caps polish", function()
		local p = Patterns.generate("Copper", 3)
		local r = Scoring.score(p, submission(p, 0.5, 0, 0.1, { polishMode = "Rub" }))
		T.truthy(r.Valid, r.Reason)
		T.le(r.Polish, 0.75, "rub polish capped")
	end)

	T.test("scoring: touch players get extra line tolerance", function()
		local p = Patterns.generate("DragonEgg", 11)
		local mouse = Scoring.score(p, submission(p, 0.5, 1.1, 0.2, { input = "Mouse" }))
		local touch = Scoring.score(p, submission(p, 0.5, 1.1, 0.2, { input = "Touch" }))
		T.lt(mouse.Chisel, touch.Chisel, "touch is more lenient")
	end)

	T.test("anti-cheat: impossible or broken input is rejected", function()
		local p = Patterns.generate("Heartstone", 42)
		-- teleport-speed cut
		local bot = submission(p, 0.5, 0, 0)
		for _, cut in bot.Cuts do
			for i = 3, #cut.Samples, 3 do
				cut.Samples[i] = 0
			end
		end
		T.falsy(Scoring.score(p, bot).Valid, "zero-time cuts rejected")
		-- NaN
		local nan = submission(p, 0.5, 0, 0)
		nan.Cuts[1].Samples[1] = 0 / 0
		T.falsy(Scoring.score(p, nan).Valid, "NaN rejected")
		-- skipped dirt (drop the last brush position)
		local lazy = submission(p, 0.5, 0, 0)
		for _ = 1, 3 do
			table.remove(lazy.Scrape.Samples)
		end
		T.falsy(Scoring.score(p, lazy).Valid, "dirt left rejected")
		-- brush positions far off the ore
		local far = submission(p, 0.5, 0, 0)
		far.Scrape.Samples[1] = 7
		T.falsy(Scoring.score(p, far).Valid, "far brush rejected")
		-- instant scraping
		local instant = submission(p, 0.5, 0, 0, { scrapeRate = 10000 })
		T.falsy(Scoring.score(p, instant).Valid, "instant scrape rejected")
		-- not enough polishing
		local dull = submission(p, 0.5, 0, 0)
		dull.Polish = polishCircles(1, 4)
		T.falsy(Scoring.score(p, dull).Valid, "unpolished rejected")
		-- wrong shape / garbage
		T.falsy(Scoring.score(p, { Cuts = {} }).Valid, "missing cuts rejected")
		T.falsy(Scoring.score(p, "hello").Valid, "garbage rejected")
		-- cut started in the middle (skipping half the line) never completes
		local skip = submission(p, 0.5, 0, 0)
		local samples = skip.Cuts[1].Samples
		local half = math.floor(#samples / 6) * 3
		local trimmed = {}
		for i = half + 1, #samples do
			table.insert(trimmed, samples[i])
		end
		skip.Cuts[1].Samples = trimmed
		T.falsy(Scoring.score(p, skip).Valid, "half cut rejected")
		-- timestamps after the session could have ended
		local late = submission(p, 0.5, 0, 0, { start = Scoring.MaxSampleTime })
		T.falsy(Scoring.score(p, late).Valid, "impossible timestamps rejected")
	end)

	T.test("scoring: slow players (several minutes) are still graded", function()
		for _, ore in OreData.List do
			local p = Patterns.generate(ore.Id, 314)
			local r = Scoring.score(p, submission(p, 0.5, 0, 0.1, { start = 240 }))
			T.truthy(r.Valid, `{ore.Id}: {r.Reason}`)
		end
	end)

	T.test("scoring: fast honest scrubbing is never rejected", function()
		local runs, covered = 0, 0
		for _, ore in OreData.List do
			for seed = 1, 25 do
				local p = Patterns.generate(ore.Id, seed * 104729)
				for _, speed in { 4, 8, 12 } do
					local sub = submission(p, 0.5, 0, 0.1)
					local scrape, tracker = scrub(p, speed, sub.Cuts[#sub.Cuts].Samples[#sub.Cuts[#sub.Cuts].Samples] + 1.3)
					runs += 1
					if tracker:complete() then
						covered += 1
						sub.Scrape = scrape
						sub.Polish = polishCircles(p.PolishTurns + 0.2, 4.5, nil, scrape.Samples[#scrape.Samples] + 1)
						local r = Scoring.score(p, sub)
						T.truthy(r.Valid, `{ore.Id} seed {seed} at {speed} u/s: {r.Reason}`)
					end
				end
			end
		end
		-- the zig-zag must actually clear the dirt in most runs for this test to mean anything
		T.truthy(covered >= runs * 0.8, `scrub covered {covered}/{runs}`)
	end)

	T.test("scoring: crystals are found from the brush path, not reported by the client", function()
		local p = Patterns.generate("Heartstone", 42)
		local careful = submission(p, 0.5, 0, 0.1)
		local clumsy = submission(p, 0.5, 0, 0.1, { hitFragile = true })
		local fragileCount = 0
		for _, d in p.Dirt do
			if d.Fragile then
				fragileCount += 1
			end
		end
		T.truthy(fragileCount > 0, "Heartstone has crystals")
		local a, b = Scoring.score(p, careful), Scoring.score(p, clumsy)
		T.truthy(a.Valid and b.Valid, tostring(a.Reason) .. " / " .. tostring(b.Reason))
		T.eq(a.FragileHits, 0, "careful brushing snaps nothing")
		T.eq(b.FragileHits, fragileCount, "every crystal brushed is counted")
		T.lt(b.Scrape, a.Scrape, "snapped crystals cost scrape score")
	end)

	T.test("scoring: polishing too fast scores low instead of failing", function()
		local p = Patterns.generate("Copper", 8)
		local frantic = Scoring.score(p, submission(p, 0.5, 0, 0.1, { polishSpeed = 28 }))
		T.truthy(frantic.Valid, frantic.Reason)
		T.lt(frantic.Polish, 0.5, "fast polish loses points")
		local bot = Scoring.score(p, submission(p, 0.5, 0, 0.1, { polishSpeed = 400 }))
		T.falsy(bot.Valid, "inhuman polish speed rejected")
	end)

	T.test("timeline: steps must be in order and the latest time is reported", function()
		local p = Patterns.generate("Silver", 21)
		local sub = submission(p, 0.5, 0, 0.1)
		local ordered, latest = Scoring.timeline(sub)
		T.truthy(ordered, "honest run is in order")
		T.eq(latest, sub.Polish.Samples[#sub.Polish.Samples - 1], "latest = last polish sample")
		-- polishing claimed before scraping
		local early = submission(p, 0.5, 0, 0.1)
		early.Polish = polishCircles(p.PolishTurns + 0.2, 4.5, nil, 0)
		local ok = Scoring.timeline(early)
		T.falsy(ok, "polish before scrape is out of order")
		-- each real client pause is required
		local gaps = Scoring.MinGaps
		T.falsy(Scoring.timeline(submission(p, 0.5, 0, 0.1, { start = gaps.FirstCut - 0.1 })), "first cut before the camera intro")
		local squeezed = submission(p, 0.5, 0, 0.1)
		local first, second = squeezed.Cuts[1].Samples, squeezed.Cuts[2].Samples
		local shift = second[3] - (first[#first] + gaps.BetweenCuts - 0.05)
		for i = 3, #second, 3 do
			second[i] -= shift
		end
		T.falsy(Scoring.timeline(squeezed), "next cut during the crack")
	end)

	T.test("timeline: the client's fixed pauses and the server's gaps agree", function()
		local P, G = Scoring.ClientPauses, Scoring.MinGaps
		T.lt(G.FirstCut, P.Intro, "intro")
		T.lt(G.BetweenCuts, P.HitStop + P.Crack, "crack")
		T.lt(G.ToScrape, P.HitStop + P.LastCrack + P.Crack + P.StepGap, "last crack + step gap")
		T.lt(G.ToPolish, P.ScrapeFinish + P.StepGap, "scrape finish + step gap")
		T.lt(G.ToSubmit, P.PolishFinish + P.StepGap, "polish finish + step gap")
		for name, gap in G do
			T.truthy(gap > 0.3, name .. " is a real pause")
		end
	end)

	-- A scripted run as short as the scoring physics allow (reviewer's bot): cuts right on the
	-- line just under MaxCutSpeed, scrape at the dirt centres in DirtCount/200 s, polish 60% in
	-- the band and the rest near MaxPolishSpeed. `gaps` = pauses between the steps.
	local function botRun(p, gaps)
		local t = gaps.Intro
		local cuts = {}
		for i, cut in p.Cuts do
			if i > 1 then
				t += gaps.Crack
			end
			local samples = traceCut(cut, p.MaxCutSpeed * 0.999, 0, p.Tolerance, nil, t)
			table.insert(cuts, { Samples = samples })
			t = samples[#samples]
		end
		t += gaps.ToScrape
		-- only the dirt centres that remove something, spread over the shortest allowed time
		local probe = Scoring.ScrapeTracker.new(p)
		local centres = {}
		for _, d in p.Dirt do
			if not d.Fragile and #probe:add(d.Center, 0) > 0 then
				table.insert(centres, d.Center)
			end
		end
		local window = p.DirtCount / 200 + 0.002
		local points = {}
		for i, c in centres do
			table.insert(points, { p = c, t = t + window * (i - 1) / math.max(1, #centres - 1) })
		end
		local scrape = recordBrush(p, points)
		t += window + gaps.ToPolish
		local samples = { t, 0 }
		local angle, done = 0, 0
		local need = p.PolishTurns * math.pi * 2
		for _, segment in { { 0.6, 8.4 }, { 0.4, 59 } } do
			local target = done + need * segment[1]
			while done < target do
				local d = math.min(segment[2] / 60, 2.2)
				t += d / segment[2]
				angle += d
				done += d
				table.insert(samples, t)
				table.insert(samples, math.atan2(math.sin(angle), math.cos(angle)))
			end
		end
		return { Cuts = cuts, Scrape = scrape, Polish = { Samples = samples, Mode = "Circle" }, Input = "Touch" }, t
	end

	T.test("anti-cheat: a compressed bot run is rejected, the real client's timing passes", function()
		local P = Scoring.ClientPauses
		local none = { Intro = 0, Crack = 0, ToScrape = 0, ToPolish = 0 }
		local real = {
			Intro = P.Intro,
			Crack = P.HitStop + P.Crack,
			ToScrape = P.HitStop + P.LastCrack + P.Crack + P.StepGap,
			ToPolish = P.ScrapeFinish + P.StepGap,
		}
		local atRule = {
			Intro = Scoring.MinGaps.FirstCut,
			Crack = Scoring.MinGaps.BetweenCuts,
			ToScrape = Scoring.MinGaps.ToScrape,
			ToPolish = Scoring.MinGaps.ToPolish,
		}
		for _, ore in OreData.List do
			for seed = 1, 5 do
				local p = Patterns.generate(ore.Id, seed * 7919)
				local label = `{ore.Id} seed {seed}`
				-- the compressed bot scores perfectly, but its timeline can't come from the client
				local bot, botLatest = botRun(p, none)
				local r = Scoring.score(p, bot)
				T.truthy(r.Valid, label .. ": bot input is physically possible: " .. tostring(r.Reason))
				T.falsy(Scoring.fitsSession(bot, botLatest + 0.6 + 1e-3), label .. ": compressed bot rejected")
				T.falsy(Scoring.fitsSession(bot, botLatest + 60), label .. ": waiting before sending doesn't help")
				-- the same moves at the real client's pace pass, even submitted at the earliest moment
				local honest, latest = botRun(p, real)
				T.truthy(Scoring.score(p, honest).Valid, label .. ": padded run valid")
				local fits, why = Scoring.fitsSession(honest, latest + P.PolishFinish + P.StepGap)
				T.truthy(fits, label .. ": real client timing accepted: " .. tostring(why))
				T.falsy(Scoring.fitsSession(honest, latest + 0.3), label .. ": sent before the polish finish")
				-- a bot padding to the exact rule saves only the frame slack
				local padded, paddedLatest = botRun(p, atRule)
				T.truthy(Scoring.fitsSession(padded, paddedLatest + Scoring.MinGaps.ToSubmit + 1e-6), label .. ": padded bot fits")
				local floor = paddedLatest + Scoring.MinGaps.ToSubmit
				local client = latest + P.PolishFinish + P.StepGap
				T.truthy(floor >= client - 0.05 * (#p.Cuts + 3) - 1e-6, `{label}: bot {floor}s vs real client {client}s`)
			end
		end
	end)

	T.test("anti-cheat: careful honest runs with the real pauses always fit", function()
		local P = Scoring.ClientPauses
		for _, ore in OreData.List do
			local p = Patterns.generate(ore.Id, 2718)
			local sub = submission(p, 0.5, 0, 0.1, { start = P.Intro })
			local _, latest = Scoring.timeline(sub)
			local fits, why = Scoring.fitsSession(sub, latest + P.PolishFinish + P.StepGap)
			T.truthy(fits, `{ore.Id}: {why}`)
		end
	end)
end
