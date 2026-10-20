--[[
	Simulated players for spray-washing (Lune tests and calibration). Each
	one records like the real client: a sample at most every SampleStep (frame
	timing: 50-67 ms apart with tiny jitter) while the spray is on, fed to the
	shared SprayTracker on the way, and the recording stops once the job is
	done.

	  sweep(pattern, opts)    rows across the clump, the spray off between rows,
	                          then a pass over whatever is left
	  scribble(pattern, opts) the spray always on, wandering around
	opts: Speed (face units / s), Spacing (row gap in spray radii), Input,
	      Start (session clock of the first sample), Seed, Even (computed
	      timestamps: t += SampleStep, what a script does), Linger (seconds to
	      hold still on every crystal), Margin (face units past the clump's edge)
	Returns submission, tracker.
]]

local roblox = require("@lune/roblox") :: any
local Vector2 = roblox.Vector2

return function(Loader: any)
	local Geometry2D = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.Geometry2D")
	local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.SprayScoring")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")

	local Players = {}

	local function recorder(pattern: any, opts: any)
		local rec = {
			tracker = Scoring.SprayTracker.new(pattern, opts.Input or "Mouse"),
			strokes = {},
			stroke = nil :: any,
			t = opts.Start or 1,
			rng = Rng.new(opts.Seed or 7),
			even = opts.Even == true,
		}
		function rec.done(): boolean
			return rec.tracker:complete()
		end
		-- the time to the next recorded sample (frames at 60 fps: 3 or 4 frames, a little jitter)
		function rec.step(): number
			if rec.even then
				return Scoring.SampleStep
			end
			local frames = if rec.rng:next() < 0.6 then 3 else 4
			return frames / 60 + rec.rng:next() * 0.002
		end
		function rec.sample(p: Vector2)
			if rec.done() then
				return
			end
			if not rec.stroke then
				rec.stroke = {}
				table.insert(rec.strokes, rec.stroke)
			end
			table.insert(rec.stroke, p.X)
			table.insert(rec.stroke, p.Y)
			table.insert(rec.stroke, rec.t)
			rec.tracker:add(p.X, p.Y, rec.t)
		end
		function rec.lift(gap: number)
			rec.stroke = nil
			rec.tracker:lift()
			rec.t += gap
		end
		-- sprays along a straight line at `speed`, sampling like the client
		function rec.move(from: Vector2, to: Vector2, speed: number)
			local length = (to - from).Magnitude
			local travelled = 0
			rec.sample(from)
			while travelled < length and not rec.done() do
				local dt = rec.step()
				rec.t += dt
				-- a hand never keeps an exact pace (a script does)
				local pace = if rec.even then 1 else 0.85 + 0.3 * rec.rng:next()
				travelled = math.min(length, travelled + speed * pace * dt)
				rec.sample(from + (to - from) * (travelled / math.max(length, 1e-6)))
			end
		end
		-- holds the spray still at p for `seconds`
		function rec.hold(p: Vector2, seconds: number)
			local held = 0
			rec.sample(p)
			while held < seconds and not rec.done() do
				local dt = rec.step()
				rec.t += dt
				held += dt
				rec.sample(p)
			end
		end
		function rec.result()
			return { Strokes = rec.strokes, Input = opts.Input or "Mouse" }, rec.tracker
		end
		return rec
	end

	-- whatever is still dirty: hold the spray on it until it is clean
	local function mopUp(rec: any, pattern: any, speed: number)
		local guard = 0
		while not rec.done() and guard < 400 do
			guard += 1
			local target = nil
			for i, cell in pattern.Cells do
				if not rec.tracker.cleaned[i] then
					target = cell.Center
					break
				end
			end
			if not target then
				break
			end
			rec.lift(0.15)
			rec.hold(target, 0.1)
		end
		local _ = speed
	end

	function Players.sweep(pattern: any, opts: any?)
		local o = opts or {}
		local rec = recorder(pattern, o)
		local radius = rec.tracker.radius
		local speed = o.Speed or 2
		local spacing = (o.Spacing or 0.8) * radius
		local margin = o.Margin or 0.05
		local minV, maxV = math.huge, -math.huge
		for _, p in pattern.Outline do
			minV, maxV = math.min(minV, p.Y), math.max(maxV, p.Y)
		end
		local row = 0
		local v = minV + spacing * 0.5
		while v < maxV and not rec.done() do
			local tMin, tMax = Geometry2D.lineSpan(pattern.Outline, Vector2.new(0, v), Vector2.new(1, 0))
			if tMin and tMax then
				local fromU, toU = tMin - margin, tMax + margin
				if row % 2 == 1 then
					fromU, toU = toU, fromU
				end
				rec.move(Vector2.new(fromU, v), Vector2.new(toU, v), speed)
				rec.lift(0.12)
				row += 1
			end
			v += spacing
		end
		if o.Linger then
			for _, crystal in pattern.Crystals do
				rec.lift(0.1)
				rec.hold(crystal.Center, o.Linger)
			end
		end
		mopUp(rec, pattern, speed)
		return rec.result()
	end

	function Players.scribble(pattern: any, opts: any?)
		local o = opts or {}
		local rec = recorder(pattern, o)
		local speed = o.Speed or 3
		local p = Vector2.new(0, 0)
		local angle = 0
		local stop = rec.t + (o.MaxTime or 90)
		rec.sample(p)
		while not rec.done() and rec.t < stop do
			local dt = rec.step()
			rec.t += dt
			angle += (rec.rng:next() - 0.5) * 2.2
			p += Vector2.new(math.cos(angle), math.sin(angle)) * speed * dt
			if p.Magnitude > 1.15 then
				p = p.Unit * 1.15
				angle += math.pi * 0.8
			end
			rec.sample(p)
		end
		mopUp(rec, pattern, speed)
		return rec.result()
	end

	return Players
end
