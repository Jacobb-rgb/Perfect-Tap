-- Spray-washing: the dirt patterns are valid and deterministic; the shared
-- tracker scores speed, aim and cracked crystals; broken or impossible input
-- is rejected; the FLAWLESS guard caps computed timestamps.
return function(T, Loader)
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Geometry2D = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.Geometry2D")
	local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
	local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.SprayScoring")
	local Players = require("../tools/lune/lib/spray_players")(Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2

	local P = Scoring.ClientPauses

	-- one ore of every rarity
	local byRarity = {}
	for _, ore in OreData.List do
		byRarity[ore.Rarity] = byRarity[ore.Rarity] or ore.Id
	end

	-- a good player: steady rows at par pace (slower on thicker dirt), from the end of the intro
	local function goodSweep(pattern, opts)
		local o = opts or {}
		local thick = Rarity.get(pattern.Rarity).DirtThickness
		o.Speed = o.Speed or 1.9 / thick
		o.Start = o.Start or P.Intro
		return Players.sweep(pattern, o)
	end

	-- the latest timestamp of a submission
	local function latest(sub): number
		local last = 0
		for _, stroke in sub.Strokes do
			if #stroke > 0 then
				last = math.max(last, stroke[#stroke])
			end
		end
		return last
	end

	T.test("spray patterns: every ore and many seeds give valid, washable jobs", function()
		for _, ore in OreData.List do
			local rarity = Rarity.get(ore.Rarity)
			for seed = 1, 6 do
				local p = Patterns.generate(ore.Id, seed * 7907)
				local label = `{ore.Id} seed {seed}`
				T.truthy(#p.Cells >= 100, label .. ": a clump full of dirt")
				T.truthy(p.Required <= #p.Cells and p.Required >= #p.Cells - 3, label .. ": only a few specks wash off by themselves")
				local total = 0
				for i, cell in p.Cells do
					T.eq(cell.Index, i)
					T.truthy(cell.Amount > 0, label .. ": every cell has dirt")
					T.truthy(Geometry2D.containsConvex(p.Outline, cell.Center), label .. ": cells sit on the clump")
					T.eq(p.CellAt[Patterns.key(p.Grid, cell.Gx, cell.Gy)], i, label .. ": the grid finds the cell")
					total += cell.Amount
				end
				T.truthy(math.abs(total - p.TotalAmount) < 1e-9, label .. ": total dirt adds up")
				T.truthy(#p.Crystals <= rarity.FragileSpots, label .. ": no more crystals than the rarity has")
				if rarity.FragileSpots > 0 then
					T.truthy(#p.Crystals >= 1, label .. ": the rarity's crystals are there")
				end
				for i, crystal in p.Crystals do
					T.truthy(crystal.Center.Magnitude < Patterns.CrystalZone, label .. ": crystals near the middle")
					for _, cell in p.Cells do
						T.truthy((cell.Center - crystal.Center).Magnitude > 1e-6, label .. ": a crystal's cell holds no dirt")
					end
					for j = i + 1, #p.Crystals do
						T.truthy((p.Crystals[j].Center - crystal.Center).Magnitude >= Patterns.CrystalGap, label .. ": crystals apart")
					end
				end
			end
		end
	end)

	T.test("spray patterns: the same seed gives the same dirt (client == server)", function()
		local a = Patterns.generate("Gold", 4242)
		local b = Patterns.generate("Gold", 4242)
		T.eq(#a.Cells, #b.Cells)
		for i, cell in a.Cells do
			T.eq(cell.Amount, b.Cells[i].Amount)
			T.eq(cell.Center, b.Cells[i].Center)
		end
		T.eq(#a.Crystals, #b.Crystals)
		local c = Patterns.generate("Gold", 4243)
		T.truthy(c.TotalAmount ~= a.TotalAmount, "another seed, other dirt")
	end)

	T.test("spray scoring: a steady sweep at par pace is Flawless on every rarity", function()
		for _, info in Rarity.List do
			for seed = 1, 3 do
				local p = Patterns.generate(byRarity[info.Id], seed * 977)
				local sub, tracker = goodSweep(p, { Seed = seed })
				local r = Scoring.score(p, sub)
				T.truthy(r.Valid, `{info.Id}: {r.Reason}`)
				T.eq(r.Grade, "Flawless", `{info.Id} seed {seed}: score {r.Score}, {r.Time}s`)
				T.eq(r.Cracks, 0, info.Id .. ": a quick pass never cracks a crystal")
				-- the client's live tracker and the server's replay agree exactly
				T.eq(tracker:parts().Score, r.Score, info.Id .. ": client == server")
				T.truthy(r.Time > 5 and r.Time < 20, `{info.Id}: a clean takes {r.Time}s`)
			end
		end
	end)

	T.test("spray scoring: slow careful washing is Pristine, scribbling Clean or lower, never a fail", function()
		for _, info in Rarity.List do
			local p = Patterns.generate(byRarity[info.Id], 31337)
			local slow = Scoring.score(p, goodSweep(p, { Speed = 1.2 / info.DirtThickness }))
			T.truthy(slow.Valid, info.Id)
			T.eq(slow.Grade, "Pristine", `{info.Id}: slow sweep {slow.Score}`)
			local scribble = Scoring.score(p, (Players.scribble(p, { Speed = 3, Start = P.Intro, Seed = 3 })))
			T.truthy(scribble.Valid, info.Id .. ": " .. tostring(scribble.Reason))
			T.truthy(scribble.Score < slow.Score, info.Id .. ": scribbling scores lower")
			T.truthy(scribble.Grade == "Clean" or scribble.Grade == "Rough", `{info.Id}: scribble {scribble.Grade}`)
			T.truthy(scribble.Aim < 0.7, info.Id .. ": scribbling wastes water")
		end
		-- several minutes of slow washing are still graded
		local p = Patterns.generate("Coal", 5)
		local crawl = Scoring.score(p, goodSweep(p, { Speed = 0.2 }))
		T.truthy(crawl.Valid, tostring(crawl.Reason))
		T.truthy(crawl.Time > 40, "it really took long")
		T.truthy(crawl.Grade == "Clean" or crawl.Grade == "Rough", crawl.Grade)
	end)

	T.test("spray scoring: spraying past the clump wastes water and costs grade", function()
		local p = Patterns.generate("Gold", 99)
		local tidy = Scoring.score(p, goodSweep(p))
		local wide = Scoring.score(p, goodSweep(p, { Margin = 1.2 }))
		T.truthy(wide.Valid)
		T.truthy(wide.Aim < tidy.Aim - 0.2, `aim {wide.Aim} vs {tidy.Aim}`)
		T.truthy(wide.Score < tidy.Score, "and the grade drops")
	end)

	T.test("spray scoring: a crystal cracks only when sprayed point-blank too long", function()
		local p
		for seed = 1, 50 do
			p = Patterns.generate(byRarity.Mythic, seed)
			if #p.Crystals >= 2 then
				break
			end
		end
		local crystal = p.Crystals[1].Center
		-- a quick pass right over it: fine
		local tracker = Scoring.SprayTracker.new(p, "Mouse")
		local t = 1
		local u = crystal.X - 0.4
		while u < crystal.X + 0.4 do
			tracker:add(u, crystal.Y, t)
			u += 0.1
			t += 0.05
		end
		T.eq(tracker.cracks, 0, "a pass at 2 face units per second")
		-- holding still on it: cracks once, the crystal's crack is reported once
		tracker:lift()
		local cracked = {}
		for _ = 1, 20 do
			t += 0.05
			local _, now = tracker:add(crystal.X, crystal.Y, t)
			for _, index in now do
				table.insert(cracked, index)
			end
		end
		T.eq(tracker.cracks, 1, "a second point-blank cracks it")
		T.eq(#cracked, 1)
		T.eq(cracked[1], 1)
		-- short bursts with cooling in between never add up
		local again = Scoring.SprayTracker.new(p, "Mouse")
		local c2 = p.Crystals[2].Center
		t = 1
		for _ = 1, 10 do
			again:add(c2.X, c2.Y, t)
			again:add(c2.X, c2.Y, t + 0.15)
			again:lift()
			t += 1
		end
		T.eq(again.cracks, 0, "taps with pauses cool off")
		-- a cracked crystal costs grade
		local clean = Scoring.score(p, goodSweep(p, { Start = 2 }))
		local sub = goodSweep(p, { Start = 2 })
		local hold = {}
		local t0 = 1
		for i = 0, 10 do
			table.insert(hold, crystal.X)
			table.insert(hold, crystal.Y)
			table.insert(hold, t0 + i * 0.05 + 0.001 * (i % 3))
		end
		table.insert(sub.Strokes, 1, hold)
		local hurt = Scoring.score(p, sub)
		T.truthy(hurt.Valid, tostring(hurt.Reason))
		T.eq(hurt.Cracks, 1)
		T.truthy(hurt.Score <= clean.Score - Scoring.Weights.Crack + 0.05, `{hurt.Score} vs {clean.Score}`)
	end)

	T.test("spray scoring: a touch player's wider spray helps aim, not the score", function()
		local p = Patterns.generate("Gold", 2024)
		local mouse = Scoring.score(p, goodSweep(p))
		local touch = Scoring.score(p, goodSweep(p, { Input = "Touch" }))
		T.truthy(touch.Valid)
		T.eq(touch.Grade, "Flawless")
		T.truthy(math.abs(touch.Score - mouse.Score) < 0.06, `{touch.Score} vs {mouse.Score}`)
		T.truthy(Scoring.par(p, "Touch") < Scoring.par(p, "Mouse"), "the wider spray is expected to be quicker")
	end)

	T.test("spray anti-cheat: broken or impossible input is rejected", function()
		local p = Patterns.generate("Gold", 7)
		local good = goodSweep(p)
		T.truthy(Scoring.score(p, good).Valid)
		local function with(edit)
			local copy = { Input = good.Input, Strokes = {} }
			for i, stroke in good.Strokes do
				copy.Strokes[i] = table.clone(stroke)
			end
			edit(copy)
			return Scoring.score(p, copy)
		end
		T.falsy(Scoring.score(p, nil).Valid, "nil")
		T.falsy(Scoring.score(p, { Strokes = "x" }).Valid, "no strokes")
		T.falsy(
			with(function(s)
				table.insert(s.Strokes[1], 0.5)
			end).Valid,
			"a stroke that isn't u, v, t triples"
		)
		T.falsy(
			with(function(s)
				s.Strokes[1][1] = 0 / 0
			end).Valid,
			"NaN"
		)
		T.falsy(
			with(function(s)
				s.Strokes[1][1] = math.huge
			end).Valid,
			"inf"
		)
		T.falsy(
			with(function(s)
				s.Strokes[1][2] = 9
			end).Valid,
			"far off the clump"
		)
		T.falsy(
			with(function(s)
				local last = s.Strokes[#s.Strokes]
				last[#last] = 0.1
			end).Valid,
			"time going backwards"
		)
		T.falsy(
			with(function(s)
				s.Strokes[1][3] = -1
			end).Valid,
			"negative time"
		)
		T.falsy(
			with(function(s)
				s.Strokes[#s.Strokes + 1] = { 0, 0, Scoring.MaxSampleTime + 1 }
			end).Valid,
			"after any session could end"
		)
		T.falsy(
			with(function(s)
				for _ = 1, Scoring.MaxStrokes + 1 do
					table.insert(s.Strokes, {})
				end
			end).Valid,
			"too many strokes"
		)
		T.falsy(
			with(function(s)
				local big = {}
				local t = 200
				for _ = 1, Scoring.MaxSamples + 1 do
					table.insert(big, 3)
					table.insert(big, 3)
					table.insert(big, t)
				end
				table.insert(s.Strokes, big)
			end).Valid,
			"too many samples"
		)
		local half = with(function(s)
			for i = #s.Strokes, math.floor(#s.Strokes / 2), -1 do
				table.remove(s.Strokes, i)
			end
		end)
		T.falsy(half.Valid, "dirt left")
		T.eq(half.Reason, "dirt left")
	end)

	T.test("spray anti-cheat: a frame hitch sprays only MaxStep, compressed time is refused", function()
		local p = Patterns.generate("Gold", 11)
		-- one sample, then the next 5 s later at the same spot: only MaxStep of spray
		local tracker = Scoring.SprayTracker.new(p, "Mouse")
		local cell = p.Cells[math.floor(#p.Cells / 2)]
		tracker:add(cell.Center.X, cell.Center.Y, 1)
		tracker:add(cell.Center.X, cell.Center.Y, 6)
		T.truthy(math.abs(tracker.sprayTime - Scoring.MaxStep) < 1e-9, "a hitch sprays MaxStep")
		-- squeezing a whole sweep into a tenth of the time leaves the dirt on
		local sub = goodSweep(p)
		for _, stroke in sub.Strokes do
			for i = 3, #stroke, 3 do
				stroke[i] = P.Intro + (stroke[i] - P.Intro) * 0.1
			end
		end
		local fast = Scoring.score(p, sub)
		T.falsy(fast.Valid, "compressed time can't come from the client")
		T.eq(fast.Reason, "samples too close")
	end)

	T.test("spray anti-cheat: forged heavy payloads are rejected cheaply, honest runs unchanged", function()
		local p = Patterns.generate(byRarity.Mythic, 12345)
		local function zigzag(count: number, gap: number, input: string)
			local stroke = {}
			local t = 1
			for i = 1, count do
				local side = if i % 2 == 0 then 1.2 else -1.2
				table.insert(stroke, side)
				table.insert(stroke, side)
				table.insert(stroke, t)
				t += gap
			end
			return { Strokes = { stroke }, Input = input }, t
		end
		local function timed(fn): (number, any)
			local started = os.clock()
			local result = fn()
			return (os.clock() - started) * 1000, result
		end
		-- 1. samples packed 1e-7 s apart: the real client never records closer than SampleStep
		local dense = zigzag(Scoring.MaxSamples, 1e-7, "Touch")
		local ms, r = timed(function()
			return Scoring.score(p, dense)
		end)
		T.falsy(r.Valid)
		T.eq(r.Reason, "samples too close")
		T.truthy(ms < 20, `dense payload rejected in {ms} ms`)
		-- 2. client-like spacing that never finishes: the cheap check wants the matching real time ...
		local slow, last = zigzag(Scoring.MaxSamples, Scoring.SampleStep, "Touch")
		T.falsy(Scoring.fitsSession(slow, 3.1), "200 s of samples in a 3 s session")
		local cheap
		cheap, r = timed(function()
			return { Scoring.fitsSession(slow, 3.1) }
		end)
		T.truthy(cheap < 20, `the pre-check is cheap ({cheap} ms)`)
		-- ... and even after waiting it out, the replay stops at its work budget
		T.truthy(Scoring.fitsSession(slow, last + 1))
		ms, r = timed(function()
			return Scoring.score(p, slow)
		end)
		T.falsy(r.Valid)
		T.eq(r.Reason, "too much spray")
		T.truthy(ms < 30, `budget-limited replay in {ms} ms`)
		-- 3. a string-keyed stroke list can't skip the stroke cap: nothing in it counts
		T.falsy(Scoring.score(p, { Strokes = { a = dense.Strokes[1] } }).Valid)
		T.falsy(Scoring.fitsSession({ Strokes = { a = dense.Strokes[1] } }, 300))
		T.falsy(Scoring.fitsSession({ Strokes = { { 0, 0, "x" } } }, 300), "junk timestamps never error")
		T.falsy(Scoring.fitsSession({ Strokes = { 5 } }, 300))
		T.falsy(Scoring.fitsSession(nil, 300))
		-- 4. an honest sweep is unchanged and cheap
		local honest, tracker = goodSweep(p)
		ms, r = timed(function()
			return Scoring.score(p, honest)
		end)
		T.truthy(r.Valid)
		T.eq(r.Grade, "Flawless")
		local samples = 0
		for _, stroke in honest.Strokes do
			samples += #stroke // 3
		end
		T.truthy(tracker.substeps <= 2 * samples, `about one spray per sample ({tracker.substeps} for {samples})`)
		T.truthy(ms < 50, `honest replay in {ms} ms`)
	end)

	T.test("spray timeline: the client's pauses and the server's gaps agree", function()
		for _, info in Rarity.List do
			local p = Patterns.generate(byRarity[info.Id], 2718)
			local sub = goodSweep(p)
			local last = latest(sub)
			local fits, why = Scoring.fitsSession(sub, last + P.Finish)
			T.truthy(fits, `{info.Id}: {why}`)
			T.falsy(Scoring.fitsSession(sub, last + P.Finish - 0.1), info.Id .. ": sent before the finish pause")
			-- spraying before the camera intro can't come from the client
			local early = goodSweep(p, { Start = 0.2 })
			T.falsy(Scoring.fitsSession(early, latest(early) + 10), info.Id .. ": sprayed during the intro")
		end
		T.falsy(Scoring.fitsSession({ Strokes = {} }, 100), "no spray at all")
		T.truthy(
			Scoring.MinGaps.FirstSpray < P.Intro and Scoring.MinGaps.ToSubmit < P.Finish,
			"frame slack, never stricter than the client"
		)
	end)

	T.test("FLAWLESS guard: computed timestamps keep Pristine, real frame times keep Flawless", function()
		local Guard = Loader.requirePath("ServerScriptService.Server.CleaningGuard")
		local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
		local logged = {}
		Guard._test.reset()
		Guard._test.setLog(function(line)
			table.insert(logged, line)
		end)
		local ok, err = pcall(function()
			for seed = 1, 4 do
				local p = Patterns.generate("Gold", seed * 104729)
				-- a script: the same moves with t += SampleStep
				local bot = goodSweep(p, { Even = true, Seed = seed })
				local result = Scoring.score(p, bot)
				T.truthy(result.Valid, "the bot run is valid")
				T.eq(result.Grade, "Flawless", "it scores Flawless")
				local verdict = Guard.check(bot)
				T.truthy(verdict.Synthetic, "computed timestamps: synthetic")
				T.eq(Guard.gradeFor(result.Grade, verdict), Guard.Config.CapGrade, "keeps Pristine")
				Guard.note("bot", verdict, result.Grade)
				-- a real player: frame times
				local human = goodSweep(p, { Seed = seed })
				local hv = Guard.check(human)
				T.falsy(hv.Synthetic, "real frame times are never synthetic")
				T.eq(#hv.Soft, 0, "nor inhumanly even")
				T.eq(Guard.gradeFor("Flawless", hv), "Flawless", "a real Flawless stays Flawless")
				-- a gamepad's even stick never counts as a soft signal
				local pad = table.clone(human)
				pad.Input = "Gamepad"
				T.eq(#Guard.check(pad).Soft, 0)
			end
			-- many short strokes with computed timestamps: no long run, but most intervals equal
			local short = { Strokes = {}, Input = "Mouse" }
			local t = 1
			for s = 1, 40 do
				local stroke = {}
				for i = 0, 5 do
					table.insert(stroke, -0.5 + i * 0.1)
					table.insert(stroke, -0.5 + s * 0.02)
					table.insert(stroke, t)
					t += 0.05
				end
				table.insert(short.Strokes, stroke)
				t += 0.05
			end
			T.truthy(Guard.check(short).Synthetic, "short strokes don't hide computed timestamps")
			-- a nozzle moving at an exactly even speed (positions computed from frame times): noted
			local even = { Strokes = { {} }, Input = "Mouse" }
			local tt = 1
			for i = 0, 60 do
				table.insert(even.Strokes[1], -0.9 + 1.5 * (tt - 1))
				table.insert(even.Strokes[1], 0)
				table.insert(even.Strokes[1], tt)
				tt += 0.05 + (i * 7 % 5) * 0.003
			end
			local soft = Guard.check(even)
			T.falsy(soft.Synthetic, "frame-like intervals")
			T.truthy(table.find(soft.Soft, "Speed") ~= nil, "the even speed is noted")
			even.Input = "Gamepad"
			T.eq(#Guard.check(even).Soft, 0, "never for a gamepad")
			-- grades below Flawless never change; soft signals only log while SoftEnforce is off
			T.eq(Guard.gradeFor("Pristine", { Synthetic = true, Soft = {} }), "Pristine")
			T.eq(Guard.gradeFor("Flawless", { Synthetic = false, Soft = { "Speed" } }), "Flawless", "soft: logged only")
			T.eq(#logged, 1, "one log line per player per LogEvery")
			T.truthy(logged[1]:find("synthetic", 1, true), "the line says what fired")
			T.eq(Guard._test.counts("bot").Runs, 4, "every run counted")
			T.truthy(ItemData.GradeById[Guard.Config.CapGrade], "the cap is a real grade")
			-- junk never errors
			T.falsy(Guard.check(nil).Synthetic)
			T.falsy(Guard.check({ Strokes = { { 0 / 0, 1, "x" } } }).Synthetic)
			T.falsy(Guard.check({ Strokes = "x" }).Synthetic)
		end)
		Guard._test.reset()
		if not ok then
			error(err, 0)
		end
	end)

	T.test("spray look: crystals glow and stick out of the dirt, one dirt block per cell", function()
		local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
		local CF = Loader.CFrame
		for seed = 1, 3 do
			local p = Patterns.generate(byRarity.Mythic, seed * 13)
			local work = CF.new(0, 5, 0)
			local shell = OreShellBuilder.build(p, work)
			local count = 0
			for _ in shell.Dirt do
				count += 1
			end
			T.eq(count, #p.Cells, "every cell has a block")
			for _, block in shell.Dirt do
				local back = work:PointToObjectSpace(block.CFrame.Position).Z - block.Size.Z / 2
				T.truthy(math.abs(back - (OreShellBuilder.CoreFront - 0.01)) < 1e-3, "dirt sits on the ore face")
				T.truthy(block:GetAttribute("FullSize") == block.Size, "the look knows its full size")
			end
			for index, crystal in p.Crystals do
				local shard = shell.Fragile[index]
				T.truthy(shard ~= nil, "every crystal is built")
				T.eq(shard.Material, roblox.Enum.Material.Neon, "it glows")
				local at = work:PointToObjectSpace(shard.CFrame.Position)
				T.truthy(at.Z > OreShellBuilder.CoreFront + OreShellBuilder.DirtDepth.Max * 0.5, "it sticks out of the dirt")
				local uv = Vector2.new(at.X, at.Y) / OreShellBuilder.Scale
				T.truthy((uv - crystal.Center).Magnitude < 0.25, "drawn where it cracks")
			end
		end
	end)
end
