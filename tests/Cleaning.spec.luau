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
	local function traceCut(cut, speed, offset, tol, jitter)
		local samples = {}
		local t = 0
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

	local function scrapeAll(pattern, perSecond, hitFragile)
		local removed, fragile = {}, {}
		local t = 0.2
		for _, d in pattern.Dirt do
			if d.Fragile then
				if hitFragile then
					table.insert(fragile, d.Index)
					table.insert(fragile, t)
				end
			else
				table.insert(removed, d.Index)
				table.insert(removed, t)
				t += 1 / perSecond
			end
		end
		return { Removed = removed, Fragile = fragile }
	end

	local function polishCircles(turns, radPerSecond, mode)
		local samples = {}
		local t, angle = 0, 0
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

	local function submission(pattern, speedFactor, offset, jitter, opts)
		opts = opts or {}
		local cuts = {}
		for _, cut in pattern.Cuts do
			table.insert(cuts, { Samples = traceCut(cut, pattern.MaxCutSpeed * speedFactor, offset, pattern.Tolerance, jitter) })
		end
		return {
			Cuts = cuts,
			Scrape = scrapeAll(pattern, opts.scrapeRate or 12, opts.hitFragile),
			Polish = polishCircles(pattern.PolishTurns + 0.2, opts.polishSpeed or 4.5, opts.polishMode),
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
		local p = Patterns.generate("Azurium", 11)
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
		-- skipped dirt
		local lazy = submission(p, 0.5, 0, 0)
		table.remove(lazy.Scrape.Removed)
		table.remove(lazy.Scrape.Removed)
		T.falsy(Scoring.score(p, lazy).Valid, "dirt left rejected")
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
	end)
end
