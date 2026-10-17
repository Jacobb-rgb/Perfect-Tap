-- Cleaning minigame from the player's side: the client's chisel recording rules
-- (CutRecorder) with lifts and restarts, phone-sized line tolerance, the polish
-- speed gauge and the crystal visuals. Every recorded run must replay the same on
-- the server.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector2 = roblox.Vector2
	local Vector3 = roblox.Vector3
	local CF = Loader.CFrame
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Geometry2D = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.Geometry2D")
	local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
	local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningScoring")
	local CutRecorder = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CutRecorder")
	local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")

	local FPS = 60

	-- Pointer events along a cut from fraction a to b of its length (either way), 60 fps.
	-- offset: distance from the line in face units (sideways).
	local function stroke(events, cut, a, b, speed, t, offset)
		local length = cut.Length
		local s, finish = a * length, b * length
		local dir = if finish >= s then 1 else -1
		while (dir == 1 and s <= finish) or (dir == -1 and s >= finish) do
			local p, tangent = Geometry2D.pointAt(cut.Line, s)
			local normal = Vector2.new(-tangent.Y, tangent.X)
			table.insert(events, { down = true, p = p + normal * (offset or 0), t = t })
			s += dir * speed / FPS
			t += 1 / FPS
		end
		return t
	end
	local function lift(events, t, frames)
		for _ = 1, frames do
			table.insert(events, { down = false, t = t })
			t += 1 / FPS
		end
		return t
	end
	local function hold(events, p, t, frames)
		for _ = 1, frames do
			table.insert(events, { down = true, p = p, t = t })
			t += 1 / FPS
		end
		return t
	end

	-- Plays events like ChiselStep.update; stops at the crack (the client stops feeding then).
	local function play(recorder, events)
		local wasDown = false
		local restarts = 0
		for _, e in events do
			if e.down then
				wasDown = true
				local feed = recorder:feed(e.p, e.t)
				if feed.Restarted then
					restarts += 1
				end
				if feed.State and feed.State.Complete then
					return true, restarts
				end
			else
				if wasDown then
					recorder:release()
				end
				wasDown = false
			end
		end
		return recorder.tracker.complete, restarts
	end

	-- What the server does with one recorded cut (CleaningScoring.score -> scoreCut).
	local function replay(cut, tol, maxSpeed, samples)
		local tracker = Scoring.CutTracker.new(cut, tol, maxSpeed)
		for i = 1, #samples, 3 do
			tracker:add(Vector2.new(samples[i], samples[i + 1]), samples[i + 2])
		end
		return tracker
	end

	local function sameAsServer(recorder, pattern, tol, label)
		local server = replay(recorder.cut, tol, pattern.MaxCutSpeed, recorder.samples)
		T.truthy(server.complete, label .. ": server sees a finished cut")
		T.near(server:score(), recorder.tracker:score(), 1e-9, label .. ": score")
		T.eq(server.chips, recorder.tracker.chips, label .. ": chips")
	end

	-- every ore (30): each one has its own pattern difficulty and close-up colors
	local ORES = {}
	local WITH_CRYSTALS = {} -- ores whose rarity puts fragile crystals in the dirt
	for _, ore in OreData.List do
		table.insert(ORES, ore.Id)
		if Rarity.get(ore.Rarity).FragileSpots > 0 then
			table.insert(WITH_CRYSTALS, ore.Id)
		end
	end

	T.test("chisel: lifting at 25% and going on from the groove tip finishes the cut", function()
		for _, input in { "Touch", "Gamepad", "Mouse" } do
			for _, oreId in ORES do
				for seed = 1, 20 do
					local pattern = Patterns.generate(oreId, seed * 7919)
					local cut = pattern.Cuts[1]
					local tol = pattern.Tolerance * Scoring.InputLeniency[input]
					local recorder = CutRecorder.new(cut, tol, pattern.MaxCutSpeed)
					local events = {}
					local t = stroke(events, cut, 0, 0.25, 1.0, 1)
					t = lift(events, t, 10)
					t = stroke(events, cut, 0.25, 1.0, 1.0, t)
					local label = `{input} {oreId} seed {seed}`
					local done, restarts = play(recorder, events)
					T.truthy(done, label .. ": cut finished")
					T.eq(restarts, 0, label .. ": the groove was kept")
					sameAsServer(recorder, pattern, tol, label)
				end
			end
		end
	end)

	T.test("chisel: controller lets go of A and presses again where the cursor stayed", function()
		for _, oreId in ORES do
			for seed = 1, 20 do
				local pattern = Patterns.generate(oreId, seed * 104729)
				local cut = pattern.Cuts[1]
				local tol = pattern.Tolerance * Scoring.InputLeniency.Gamepad
				local recorder = CutRecorder.new(cut, tol, pattern.MaxCutSpeed)
				local events = {}
				local t = stroke(events, cut, 0, 0.2, 0.9, 1)
				local last = events[#events].p
				t = lift(events, t, 12)
				t = hold(events, last, t, 15)
				t = stroke(events, cut, 0.2, 1.0, 0.9, t)
				local done, restarts = play(recorder, events)
				T.truthy(done, `{oreId} seed {seed}: cut finished`)
				T.eq(restarts, 0, `{oreId} seed {seed}: no restart`)
				sameAsServer(recorder, pattern, tol, `{oreId} seed {seed}`)
			end
		end
	end)

	T.test("chisel: a touch at the wrong end is forgotten, the line works from the other end", function()
		for _, oreId in ORES do
			for seed = 1, 20 do
				local pattern = Patterns.generate(oreId, seed * 7919)
				local cut = pattern.Cuts[1]
				local tol = pattern.Tolerance * Scoring.InputLeniency.Touch
				local recorder = CutRecorder.new(cut, tol, pattern.MaxCutSpeed)
				local events = {}
				local t = stroke(events, cut, 0, 0.08, 1.0, 1)
				t = lift(events, t, 6)
				t = stroke(events, cut, 1.0, 0, 1.0, t)
				local done, restarts = play(recorder, events)
				T.truthy(done, `{oreId} seed {seed}: cut finished`)
				T.eq(restarts, 1, `{oreId} seed {seed}: the false start was dropped`)
				T.eq(recorder.tracker.direction, -1, `{oreId} seed {seed}: cut from the other end`)
				sameAsServer(recorder, pattern, tol, `{oreId} seed {seed}`)
			end
		end
	end)

	T.test("chisel: after an early lift, pressing away from the tip starts over", function()
		local pattern = Patterns.generate("Gold", 99)
		local cut = pattern.Cuts[1]
		local tol = pattern.Tolerance * Scoring.InputLeniency.Mouse
		local recorder = CutRecorder.new(cut, tol, pattern.MaxCutSpeed)
		local events = {}
		local t = stroke(events, cut, 0, 0.2, 1.0, 1)
		lift(events, t, 5)
		play(recorder, events)
		T.truthy(recorder.tracker.progress > 0, "groove kept while lifted")
		T.truthy(recorder:tip() ~= nil, "the tip marker has a place")
		local feed = recorder:feed(Vector2.new(0, 0), t + 0.2) -- the middle of the ore, off the line
		T.truthy(feed.Restarted, "press away from the tip restarts")
		T.eq(#recorder.samples, 0, "nothing of the dropped attempt is sent")
	end)

	T.test("chisel: past 30% the cut keeps its direction; the far end only shows the hint", function()
		local checked = 0
		for seed = 1, 20 do
			local pattern = Patterns.generate("Gold", seed * 7919)
			local cut = pattern.Cuts[1]
			local tol = pattern.Tolerance * Scoring.InputLeniency.Mouse
			local recorder = CutRecorder.new(cut, tol, pattern.MaxCutSpeed)
			local events = {}
			local t = stroke(events, cut, 0, 0.5, 1.0, 1)
			t = lift(events, t, 8)
			play(recorder, events)
			local progress = recorder.tracker.progress
			-- trace from the far end toward the groove (outside the tracker's tol*4 jump range)
			local stopAt = (progress + tol * 4.5) / cut.Length
			if stopAt < 0.95 then
				checked += 1
				local label = `Gold seed {seed}`
				local back = {}
				t = stroke(back, cut, 1.0, stopAt, 1.0, t)
				local _, restarts = play(recorder, back)
				T.eq(restarts, 0, label .. ": no restart after 30%")
				T.near(recorder.tracker.progress, progress, 1e-9, label .. ": far-end trace adds nothing")
				for _, e in back do
					T.falsy(recorder:nearTip(e.p), label .. ": far from the tip, the client hints instead of scratching")
				end
				-- going on from the tip finishes it
				local rest = {}
				t = lift(rest, t, 3)
				stroke(rest, cut, 0.5, 1.0, 1.0, t)
				T.truthy(play(recorder, rest), label .. ": finished from the tip")
				sameAsServer(recorder, pattern, tol, label)
			end
		end
		T.truthy(checked >= 10, `enough long lines checked ({checked})`)
	end)

	T.test("chisel: messy multi-stroke runs score the same on the server", function()
		for _, oreId in ORES do
			for seed = 1, 10 do
				local pattern = Patterns.generate(oreId, seed * 104729)
				local tol = pattern.Tolerance * Scoring.InputLeniency.Touch
				local cuts = {}
				local chips, weighted, length = 0, 0, 0
				local t = 1
				for i, cut in pattern.Cuts do
					local recorder = CutRecorder.new(cut, tol, pattern.MaxCutSpeed)
					local events = {}
					-- wander next to the ore first (before the cut starts: nothing is sent), then a
					-- false start, then most of the line from the other end with a wobble, lift, finish
					for k = 1, 30 do
						table.insert(events, { down = true, p = Vector2.new(math.sin(k) * 2, math.cos(k) * 2), t = t })
						t += 1 / FPS
					end
					t = lift(events, t, 3)
					t = stroke(events, cut, 0, 0.2, 0.8, t, -0.15 * tol)
					t = lift(events, t, 4)
					t = stroke(events, cut, 1.0, 0.45, 0.9, t, -2 * tol * (i % 2))
					t = lift(events, t, 4)
					t = stroke(events, cut, 0.45, 0.0, 0.9, t, 0.05 * tol)
					local done = play(recorder, events)
					T.truthy(done, `{oreId} seed {seed} cut {i}: finished`)
					sameAsServer(recorder, pattern, tol, `{oreId} seed {seed} cut {i}`)
					cuts[i] = { Samples = recorder.samples }
					chips += recorder.tracker.chips
					weighted += recorder.tracker:score() * cut.Length
					length += cut.Length
					t = recorder.samples[#recorder.samples] + Scoring.ClientPauses.HitStop + Scoring.ClientPauses.Crack
				end
				-- scrape at the dirt centres, then honest polishing, on the real client's pauses
				local scrapeTracker = Scoring.ScrapeTracker.new(pattern)
				local scrape = {}
				t += Scoring.ClientPauses.LastCrack + Scoring.ClientPauses.StepGap
				for _, d in pattern.Dirt do
					if not d.Fragile then
						local removed = scrapeTracker:add(d.Center, t)
						if #removed > 0 then
							table.insert(scrape, d.Center.X)
							table.insert(scrape, d.Center.Y)
							table.insert(scrape, t)
						end
						t += 0.08
					end
				end
				t += Scoring.ClientPauses.ScrapeFinish + Scoring.ClientPauses.StepGap
				local polish = {}
				local angle = 0
				while angle < (pattern.PolishTurns + 0.2) * math.pi * 2 do
					table.insert(polish, t)
					table.insert(polish, math.atan2(math.sin(angle), math.cos(angle)))
					angle += 4 / 30
					t += 1 / 30
				end
				local submission =
					{ Cuts = cuts, Scrape = { Samples = scrape }, Polish = { Samples = polish, Mode = "Circle" }, Input = "Touch" }
				local r = Scoring.score(pattern, submission)
				T.truthy(r.Valid, `{oreId} seed {seed}: {r.Reason}`)
				T.eq(r.Chips, chips, `{oreId} seed {seed}: chips match the meter`)
				T.near(r.Chisel, weighted / length, 1e-9, `{oreId} seed {seed}: chisel matches the meter`)
				local fits, why = Scoring.fitsSession(submission, polish[#polish - 1] + 0.65)
				T.truthy(fits, `{oreId} seed {seed}: {why}`)
			end
		end
	end)

	---------------------------------------------------------------- phones

	local function gaussian(rng)
		local u1 = math.max(rng:next(), 1e-9)
		local u2 = rng:next()
		return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	end

	-- A finger tracing a line with a smooth sideways wobble (AR(1), RMS sigma face units),
	-- sampled at 30 fps, at `speed` face units per second (overshoots go back and retrace).
	local function wobblyCut(cut, tol, maxSpeed, sigma, speed, rng)
		local recorder = CutRecorder.new(cut, tol, maxSpeed)
		local rho = 0.9 -- wobble correlated over ~0.3 s
		local t, s, e = 1, 0, gaussian(rng) * sigma
		for _ = 1, 2000 do
			local p, tangent = Geometry2D.pointAt(cut.Line, math.min(s, cut.Length))
			local normal = Vector2.new(-tangent.Y, tangent.X)
			e = rho * e + math.sqrt(1 - rho * rho) * gaussian(rng) * sigma
			recorder:feed(p + normal * e, t)
			if recorder.tracker.complete then
				break
			end
			t += 1 / 30
			s += speed / 30
			if s > cut.Length + 0.3 then
				s = cut.Length * 0.9
			end
		end
		return recorder
	end

	-- Share of seeds reaching Clean or better (scrape and polish assumed 0.85 each).
	local function cleanShare(oreId, input, unitSize, wobble)
		local rng = Rng.new(`wobble {oreId} {input} {unitSize} {wobble}`)
		local weights = Scoring.Weights
		local good = 0
		for seed = 1, 60 do
			local pattern = Patterns.generate(oreId, seed * 7919 + 8)
			local tol = pattern.Tolerance * Scoring.InputLeniency[input]
			local weighted, length, chips = 0, 0, 0
			for _, cut in pattern.Cuts do
				local recorder = wobblyCut(cut, tol, pattern.MaxCutSpeed, wobble / unitSize, 1.2, rng)
				weighted += recorder.tracker:score() * cut.Length
				length += cut.Length
				chips += recorder.tracker.chips
			end
			local penalty = math.min(Scoring.MaxChipPenalty, chips * Scoring.ChipPenalty)
			local total = weights.Chisel * weighted / length + weights.Scrape * 0.85 + weights.Polish * 0.85 - penalty
			if ItemData.gradeFromScore(total) ~= "Rough" then
				good += 1
			end
		end
		return good / 60
	end

	local function oreOf(rarityId)
		for _, ore in OreData.List do
			if ore.Rarity == rarityId then
				return ore.Id
			end
		end
		error("no ore of rarity " .. rarityId)
	end

	T.test("touch: Mythic on a phone (105 pt per face unit, 8 pt wobble) reaches Clean in >= 80% of runs", function()
		local mythic = oreOf("Mythic")
		T.truthy(Rarity.get("Mythic").Tolerance <= 0.06, "Mythic has the thinnest line")
		local share = cleanShare(mythic, "Touch", 105, 8)
		T.truthy(share >= 0.8, `{mythic} on a phone: Clean or better in {math.floor(share * 100)}% of 60 runs`)
		-- the same hand on a 1080p PC (315 px per face unit) is still at least as good
		local pc = cleanShare(mythic, "Mouse", 315, 8)
		T.truthy(pc >= 0.8, `{mythic} with a mouse: {math.floor(pc * 100)}%`)
	end)

	---------------------------------------------------------------- polish gauge

	-- Circling at a constant speed like PolishStep: still moves under 0.04 rad are only
	-- recorded every 0.5 s; returns every needle reading after the first second.
	local function needles(speed, fps)
		local gauge = Scoring.PolishGauge.new()
		local angle, lastAngle, lastT = 0, nil, -1
		local readings = {}
		local t = 0
		for _ = 1, fps * 4 do
			t += 1 / fps
			angle += speed / fps
			if lastAngle == nil then
				lastAngle, lastT = angle, t
			else
				local delta = angle - lastAngle
				if not (delta < 0.04 and t - lastT < 0.5) then
					gauge:add(lastT, t, delta)
					lastAngle, lastT = angle, t
				end
			end
			if t > 1 then
				table.insert(readings, Scoring.needleFor(gauge:speed(t)))
			end
		end
		return readings
	end

	T.test("polish gauge: the needle is green exactly when the speed counts", function()
		local band = Scoring.PolishBand
		local green = Scoring.GaugeGreen
		local checked = 0
		for _, speed in { 0.5, 0.9, 1.3, 1.6, 2.5, 4, 6, 8, 9.5, 10, 11.2, 13, 18 } do
			local nearEdge = math.abs(speed / band.Min - 1) <= 0.05 or math.abs(speed / band.Max - 1) <= 0.05
			if not nearEdge then
				local inBand = speed >= band.Min and speed <= band.Max
				for _, fps in { 60, 30 } do
					for _, needle in needles(speed, fps) do
						local isGreen = needle >= green.From and needle <= green.To
						T.eq(isGreen, inBand, `{speed} rad/s at {fps} fps: needle {needle}`)
						checked += 1
					end
				end
			end
		end
		T.truthy(checked > 500, "enough readings")
		-- the ring's demo dot runs in the middle of the green
		local demo = Scoring.needleFor(band.Demo)
		T.near(demo, (green.From + green.To) / 2, 0.03, "demo speed sits mid-green")
		-- following the demo dot exactly gives a full polish score
		local samples, t, angle = {}, 0, 0
		while angle < 5 * math.pi * 2 do
			table.insert(samples, t)
			table.insert(samples, math.atan2(math.sin(angle), math.cos(angle)))
			t += 1 / 60
			angle += band.Demo / 60
		end
		local total, inBand, net = Scoring.polishProgress(samples)
		T.near(Scoring.polishScore(total, inBand, net, "Circle"), 1, 1e-6, "demo speed polish")
	end)

	T.test("polish gauge: the needle drops when the rubbing stops", function()
		local gauge = Scoring.PolishGauge.new()
		local t = 0
		for _ = 1, 60 do
			gauge:add(t, t + 1 / 60, 5 / 60)
			t += 1 / 60
		end
		T.near(gauge:speed(t), 5, 0.05, "steady 5 rad/s")
		T.near(gauge:speed(t + 1), 0, 1e-9, "a second later the needle is at zero")
	end)

	---------------------------------------------------------------- crystals

	T.test("crystals: glowing, sticking out of the face, on a base smaller than the snap zone", function()
		T.lt(OreShellBuilder.CrystalBaseSize, Scoring.FragileRadius * 2, "pale base smaller than the snap zone")
		for _, oreId in WITH_CRYSTALS do
			local pattern = Patterns.generate(oreId, 42)
			local workCF = CF.new(0, 5, 0)
			local shell = OreShellBuilder.build(pattern, workCF)
			local fragileCount = 0
			for _, d in pattern.Dirt do
				if d.Fragile then
					fragileCount += 1
				end
			end
			T.truthy(fragileCount > 0, oreId .. " has crystals")
			local bases = 0
			for _, child in shell.Model:GetChildren() do
				T.truthy(child.Name ~= "FragileDirt", oreId .. ": no dirt look-alike under crystals")
				if child.Name == "CrystalBase" then
					bases += 1
				end
			end
			T.eq(bases, fragileCount, oreId .. ": one pale base per crystal")
			for _, shard in shell.Fragile do
				T.eq(shard.Material, roblox.Enum.Material.Neon, oreId .. ": crystal glows")
				-- the front-most corner of the shard, in face space
				local front = -math.huge
				local half = shard.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner = shard.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
							front = math.max(front, workCF:PointToObjectSpace(corner).Z)
						end
					end
				end
				T.truthy(front > OreShellBuilder.DirtFront + 0.08, `{oreId}: crystal sticks out in front of the dirt ({front})`)
			end
		end
	end)
end
