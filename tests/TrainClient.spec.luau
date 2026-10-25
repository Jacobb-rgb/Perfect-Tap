-- Ore trains on the client (TrainController + TrainView): the trip timeline
-- (legs with minimum visible seconds, easing, the quarry portal per plot side,
-- where a train is at a time), the stop that lines the wagons up with the Ore
-- Pen, the hold at a full pen and the unload, the way back at a sane speed,
-- tunnels hiding the cars, one track per line (no train runs through
-- another), the wagons tipping toward the pen, emptying and the ore clearing
-- the museum, couplers, the waiting train under the station chute (parked
-- before loading opens), trip payloads (Waiting, late unloads) and snapshots
-- (also in the order the server really sends them), the HUD chip's state
-- text, the upgrade rows, presses ahead of the server (SEND "Leaving…" and
-- no unlock from a stale snapshot, the TrainTrip filling the trip bar,
-- clicked levels and a double click that buys two, the click budget), the
-- view's children, the prompt slots against
-- TrainService's real prompts and the phone layouts (every touch target
-- >= 44 pt, names readable on narrow phones, the coins and the backpack
-- button never cut by the panel).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local Instance = roblox.Instance
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local TrainController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.TrainController")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")

	local RAIL = Vector3.new(0, TrainBuilder.RailTop, 0)
	-- (positions at 12 cells; WorldLayout.PlotGrid moves them on a bigger grid)
	local WEST = WorldLayout.Plots[1] -- the south-most west plot: x -104, z 84
	local EAST_FAR = WorldLayout.Plots[8] -- the north-most east plot: x 104, z -84
	local DEPART, TRIP = 1000, 30
	local ARRIVE = DEPART + TRIP
	local RED = Color3.fromRGB(220, 70, 50)
	local ORE = { Color3.fromRGB(222, 120, 60), Color3.fromRGB(150, 156, 170), Color3.fromRGB(58, 54, 60) }
	local FIRST_WAGON = TrainController.LocoBack + TrainController.WagonLength / 2 -- 13.15

	local function near(a: any, b: any, eps: number?, label: string?)
		T.near((a - b).Magnitude, 0, eps or 1e-4, label)
	end

	local function find(model: any, className: string, name: string): any
		for _, d in model:GetDescendants() do
			if d:IsA(className) and d.Name == name then
				return d
			end
		end
		return nil
	end

	local function worldOf(attachment: any): any
		return (attachment.Parent.CFrame * attachment.CFrame).Position
	end

	-- places a consist at a pose (what the PreRender loop does with BulkMoveTo)
	local function place(consist: any, pose: any, parent: any)
		local parts, cframes = {}, {}
		TrainController.placeConsist(consist, pose, parent, parts, cframes)
		for i, part in parts do
			part.CFrame = cframes[i]
		end
		return #parts
	end

	local function spans(): any
		return TrainController.legSpans(TRIP)
	end

	---------------------------------------------------------------- timeline

	T.test("TrainClient: easing starts and stops smoothly", function()
		for _, kind in { "In", "Out", "InOut" } do
			local v0 = TrainController.ease(kind, 0)
			local v1 = TrainController.ease(kind, 1)
			T.near(v0, 0, 1e-9, kind .. " starts at 0")
			T.near(v1, 1, 1e-9, kind .. " ends at 1")
			local below = TrainController.ease(kind, -2)
			local above = TrainController.ease(kind, 5)
			T.near(below, 0, 1e-9, kind .. " clamps below")
			T.near(above, 1, 1e-9, kind .. " clamps above")
			-- the slope matches the curve (numeric derivative)
			for _, f in { 0.2, 0.5, 0.8 } do
				local a = TrainController.ease(kind, f - 1e-4)
				local b = TrainController.ease(kind, f + 1e-4)
				local _, slope = TrainController.ease(kind, f)
				T.near((b - a) / 2e-4, slope, 1e-3, kind .. " slope at " .. f)
			end
		end
		local _, startIn = TrainController.ease("In", 0)
		local _, endOut = TrainController.ease("Out", 1)
		local _, startInOut = TrainController.ease("InOut", 0)
		local _, endInOut = TrainController.ease("InOut", 1)
		T.eq(startIn, 0, "leaves the station from rest")
		T.eq(endOut, 0, "rolls in to a stop")
		T.eq(startInOut, 0, "coast leg starts at rest")
		T.eq(endInOut, 0, "...and stops at the Train Stop")
		T.near(TrainController.ease("InOut", 0.5), 0.5, 1e-9, "symmetric")
	end)

	T.test("TrainClient: legs follow TrainConfig.Timeline on a normal trip", function()
		local tl = TrainConfig.Timeline
		local s = spans()
		T.near(s.Quarry, TRIP * tl.QuarryLeg[2], 1e-9, "quarry leg share")
		T.near(s.Underground, TRIP * tl.Underground[2], 1e-9, "underground share")
		T.near(s.Coast, TRIP * tl.CoastLeg[2], 1e-9, "coast share")
		T.eq(s.Trip, TRIP)
		local cases = {
			{ -0.1, "Station", 0 },
			{ 0, "Quarry", 0 },
			{ s.Quarry / 2, "Quarry", 0.5 },
			{ s.Quarry, "Underground", 0 },
			{ (s.Quarry + s.Underground) / 2, "Underground", 0.5 },
			{ s.Underground, "Coast", 0 },
			{ (s.Underground + s.Coast) / 2, "Coast", 0.5 },
			{ s.Coast, "Stopped", 0 },
			{ TRIP + 50, "Stopped", 1 },
		}
		for _, case in cases do
			local leg, f = TrainController.legAt(case[1], TRIP)
			T.eq(leg, case[2], "leg at " .. case[1])
			T.near(f, case[3], 1e-9, "fraction at " .. case[1])
		end
		-- the shares cover 0..1 without gaps
		T.eq(tl.QuarryLeg[2], tl.Underground[1])
		T.eq(tl.Underground[2], tl.CoastLeg[1])
		T.eq(tl.CoastLeg[2], tl.Unload[1])
	end)

	T.test("TrainClient: fast trips keep the visible legs watchable", function()
		local durations = {}
		for level = 0, TrainConfig.maxLevel(TrainConfig.Speed) do
			table.insert(durations, TrainConfig.tripSeconds(level, false))
			table.insert(durations, TrainConfig.tripSeconds(level, true))
		end
		table.insert(durations, TrainConfig.MinTripSeconds)
		for _, d in durations do
			local s = TrainController.legSpans(d)
			T.near(s.Trip, d, 1e-9, `{d} s: ends at the arrival`)
			T.lt(0, s.Quarry, `{d} s quarry`)
			T.lt(s.Quarry, s.Underground, `{d} s underground`)
			T.lt(s.Underground, s.Coast, `{d} s coast`)
			T.lt(s.Coast, s.Trip, `{d} s arrival`)
			T.le(d * TrainController.MinUndergroundShare - 1e-9, s.Underground - s.Quarry, `{d} s: some of it stays hidden`)
			local fits = TrainController.MinQuarrySeconds + TrainController.MinCoastSeconds + TrainController.MinArriveSeconds
				<= d * (1 - TrainController.MinUndergroundShare)
			if fits then
				T.le(TrainController.MinCoastSeconds - 1e-9, s.Coast - s.Underground, `{d} s: the coast leg is never rushed`)
				T.le(TrainController.MinQuarrySeconds - 1e-9, s.Quarry, `{d} s: nor the quarry leg`)
			end
		end
		-- the top speed level (12 s): the coast leg gets its 6 s, the underground leg pays for it
		local s = TrainController.legSpans(12)
		T.near(s.Coast - s.Underground, TrainController.MinCoastSeconds, 1e-9, "6 s on the coast")
	end)

	T.test("TrainClient: each plot side uses its own quarry portal", function()
		-- the tunnel mouths and the buffer stops are where Railway builds them (one number in TrainConfig)
		T.eq(TrainController.PortalInset, TrainConfig.PortalInset, "PortalInset from TrainConfig")
		T.eq(TrainController.BufferGap, TrainConfig.BufferGap, "BufferGap from TrainConfig")
		local west, east = math.huge, -math.huge
		for _, point in TrainConfig.QuarryLine do
			west = math.min(west, point.X)
			east = math.max(east, point.X)
		end
		for _, plot in WorldLayout.Plots do
			local portal = TrainController.quarryPortal(plot)
			T.eq(portal.X, if plot.Center.X < 0 then west else east, "plot " .. plot.Id)
			-- the visible mouth stands PortalInset in front of the line's end (as Railway builds it)
			local mouth = TrainController.quarryMouth(plot)
			local inset = if plot.Center.X < 0 then TrainController.PortalInset else -TrainController.PortalInset
			near(mouth, portal + Vector3.new(inset, 0, 0), 1e-6, "plot " .. plot.Id .. " mouth")
			-- the quarry leg heads for it: west plots run west from the station
			local p = TrainController.poseAt(plot, DEPART, ARRIVE, DEPART + 1.5)
			T.eq(p.Leg, "Quarry")
			T.truthy((p.Facing.X < 0) == (plot.Center.X < 0), "plot " .. plot.Id .. " heads to its side")
			near(p.Portal, mouth + RAIL, 1e-6, "plot " .. plot.Id .. " hides behind the visible mouth")
			-- the coast leg runs on the plot's own line
			local coast = TrainController.poseAt(plot, DEPART, ARRIVE, DEPART + TRIP * 0.85)
			T.eq(coast.Leg, "Coast")
			T.near(coast.Position.X, TrainConfig.lineFor(plot)[1].X, 1e-6, "plot " .. plot.Id .. " coast x")
		end
	end)

	T.test("TrainClient: where a train is during a trip", function()
		local s = spans()
		local stop = TrainConfig.QuarryStop
		local mouth = TrainController.quarryMouth(WEST)
		local dir = Vector3.new(-1, 0, 0)
		local start = stop + dir * FIRST_WAGON -- the first wagon under the station chute
		local quarryLength = (mouth - start):Dot(dir) + TrainController.HideDepth

		-- leaving the station: at rest, heading for the portal
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART)
		T.eq(p.Leg, "Quarry")
		near(p.Position, start + RAIL, 1e-6, "starts with its first wagon on QuarryStop")
		T.near(p.Speed, 0, 1e-9, "starts from rest")
		near(p.Facing, dir, 1e-6, "faces the west portal")
		-- halfway through the quarry leg: it pulled away within DepartRamp and runs steady since,
		-- so it is past halfway (pullAway: steady speed = length / (seconds - ramp / 3))
		local ramp = math.min(TrainController.DepartRamp, s.Quarry / 2)
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Quarry / 2)
		local expected = quarryLength * (s.Quarry / 2 - ramp / 3) / (s.Quarry - ramp / 3)
		T.near((p.Position - (start + RAIL)).Magnitude, expected, 1e-4, "pulled away, then steady")
		T.near(p.Speed, quarryLength / (s.Quarry - ramp / 3), 1e-4, "at its steady speed")
		-- underground: hidden
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + (s.Quarry + s.Underground) / 2)
		T.eq(p.Leg, "Underground")
		T.truthy(p.Hidden, "hidden underground")

		local line = TrainConfig.lineFor(WEST)
		local trainStop = TrainController.stopAt(WEST, 1)
		local inside = line[1] + Vector3.new(0, 0, TrainController.HideDepth) -- inside the south tunnel
		-- the coast leg: halfway in time is halfway along (ease in / out), facing north
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + (s.Underground + s.Coast) / 2, 1)
		T.eq(p.Leg, "Coast")
		near(p.Position, (inside + trainStop) / 2 + RAIL, 1e-4, "halfway along the coast")
		near(p.Facing, Vector3.new(0, 0, -1), 1e-6, "runs north")
		T.lt(0, p.Speed, "moving")
		-- at the stop before the arrival: standing, loaded
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Coast + 0.01, 1)
		T.eq(p.Leg, "Stopped")
		near(p.Position, trainStop + RAIL, 1e-6, "at the Train Stop")
		T.eq(p.Tip, 0, "not tipped yet")
		-- the arrival passed but nobody unloaded it (a full pen): it keeps standing there loaded
		for _, late in { 0, 5, 120 } do
			p = TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + late, 1, nil)
			T.eq(p.Leg, "Stopped", `held {late} s after the arrival`)
			T.eq(p.Tip, 0)
			T.eq(p.Speed, 0)
			T.eq(TrainController.pourFill(p), nil, "the load stays on board")
		end
		-- the unload (here 40 s late): tip up, pour, tip down, then back south into the tunnel
		local unloadAt = ARRIVE + 40
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt - 0.01, 1, unloadAt)
		T.eq(p.Leg, "Stopped", "until the unload begins")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + TrainController.TipUp / 2, 1, unloadAt)
		T.eq(p.Leg, "Unload")
		T.lt(0, p.Tip, "tipping")
		T.lt(p.Tip, 1, "still tipping")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + TrainController.TipUp + TrainController.TipHold / 2, 1, unloadAt)
		T.near(p.Tip, 1, 1e-9, "fully tipped")
		near(p.Position, trainStop + RAIL, 1e-6, "on the stop while it pours")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + TrainController.unloadSeconds() + 0.01, 1, unloadAt)
		T.eq(p.Leg, "Return")
		T.near(p.Tip, 0, 1e-9, "hopper back down")
		near(p.Facing, Vector3.new(0, 0, -1), 1e-6, "backs up (still faces north)")
		local back = TrainController.returnSeconds(WEST, 1)
		T.le(TrainConfig.ReturnSeconds, back, "never back sooner than the server's ReturnSeconds")
		local mid = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + back * 0.7, 1, unloadAt)
		T.lt(trainStop.Z, mid.Position.Z, "rolls south")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + back - 0.001, 1, unloadAt)
		near(p.Position, inside + RAIL, 0.01, "back inside the tunnel")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + back, 1, unloadAt)
		T.eq(p.Leg, "Done")
		T.truthy(p.Hidden, "gone after the return")
		T.le(TrainController.TipUp + TrainController.TipHold + TrainController.TipDown, TrainController.unloadSeconds() + 1e-9)
		T.le(1.2, TrainController.unloadSeconds(), "the unload is never a blink")
		-- a broken trip (no duration) never errors: it is simply over
		T.eq(TrainController.poseAt(WEST, ARRIVE, ARRIVE, ARRIVE + 100).Leg, "Done")
	end)

	T.test("TrainClient: no jumps while a train is in sight; Speed matches the motion", function()
		for _, case in { { WEST, 30, 1 }, { EAST_FAR, 30, 2 }, { EAST_FAR, 12, 1 }, { WEST, 6, 2 } } do
			local plot, trip, wagons = case[1], case[2], case[3]
			local arrive = DEPART + trip
			local unloadAt = arrive + 0.35 -- the unload Fx comes a moment after the arrival
			local dt = 0.005
			local last = TrainController.poseAt(plot, DEPART, arrive, DEPART, wagons, unloadAt)
			local t = DEPART + dt
			while t < unloadAt + TrainController.returnSeconds(plot, wagons) do
				local p = TrainController.poseAt(plot, DEPART, arrive, t, wagons, unloadAt)
				local label = `plot {plot.Id} {trip} s {p.Leg} at {t - DEPART}`
				if not p.Hidden and not last.Hidden then
					local moved = (p.Position - last.Position).Magnitude
					-- average speed over the step, compared with the reported speed
					local expected = (p.Speed + last.Speed) / 2 * dt
					T.near(moved, expected, math.max(0.02, expected * 0.05), label)
					if p.Leg == last.Leg then
						T.near(math.abs(p.Odometer - last.Odometer), moved, 1e-3, "odometer follows the rails")
					end
					T.le(math.abs(p.Tip - last.Tip), 0.1, label .. " tip")
				end
				last = p
				t += dt
			end
		end
	end)

	T.test("TrainClient: a leaving train pulls away at once and still reaches the tunnel on time", function()
		-- pullAway: from rest to a steady speed within the ramp, the whole length at the end
		local seconds, length, ramp = 4.5, 70, TrainController.DepartRamp
		local d0, v0 = TrainController.pullAway(0, seconds, length, ramp)
		T.eq(d0, 0, "starts where it stood")
		T.eq(v0, 0, "from rest")
		local cruise = length / (seconds - ramp / 3)
		local _, atRamp = TrainController.pullAway(ramp, seconds, length, ramp)
		T.near(atRamp, cruise, 1e-9, "steady once the ramp is over")
		local _, later = TrainController.pullAway(seconds * 0.8, seconds, length, ramp)
		T.near(later, cruise, 1e-9, "and stays steady")
		T.near(TrainController.pullAway(seconds, seconds, length, ramp), length, 1e-9, "the whole run at the end")
		T.near(TrainController.pullAway(seconds + 3, seconds, length, ramp), length, 1e-9, "clamped after it")
		T.eq(TrainController.pullAway(-1, seconds, length, ramp), 0, "clamped before it")
		-- the speed is the slope of the distance (and never jumps at the end of the ramp)
		for _, t in { 0.1, 0.3, ramp - 1e-3, ramp + 1e-3, 2, 4 } do
			local a = TrainController.pullAway(t - 1e-5, seconds, length, ramp)
			local b = TrainController.pullAway(t + 1e-5, seconds, length, ramp)
			local _, speed = TrainController.pullAway(t, seconds, length, ramp)
			T.near((b - a) / 2e-5, speed, 1e-3, `slope at {t}`)
		end
		-- a run shorter than two ramps ramps over half of it; no ramp is a steady run
		local _, half = TrainController.pullAway(0.5, 1, 10, ramp)
		T.near(half, 10 / (1 - 0.5 / 3), 1e-9, "a short run is steady after half of it")
		T.near(TrainController.pullAway(0.25, 1, 10, 0), 2.5, 1e-9, "no ramp: steady from the start")
		-- on every plot and every trip: clearly off within half a second (x^2 managed under 1.6
		-- studs), at the tunnel when the quarry leg ends, the leg's end time kept
		local durations = {}
		for level = 0, TrainConfig.maxLevel(TrainConfig.Speed) do
			table.insert(durations, TrainConfig.tripSeconds(level, false))
			table.insert(durations, TrainConfig.tripSeconds(level, true))
		end
		table.insert(durations, TrainConfig.MinTripSeconds)
		for _, plot in WorldLayout.Plots do
			local start = TrainController.poseAt(plot, DEPART, DEPART + 30, DEPART).Position
			for _, d in durations do
				local s = TrainController.legSpans(d)
				local label = `plot {plot.Id} {d} s`
				local half = TrainController.poseAt(plot, DEPART, DEPART + d, DEPART + 0.5)
				T.eq(half.Leg, "Quarry", label)
				T.le(4.9, (half.Position - start).Magnitude, label .. ": ~5 studs in the first 0.5 s")
				local second = TrainController.poseAt(plot, DEPART, DEPART + d, DEPART + 1)
				T.le(12, (second.Position - start).Magnitude, label .. ": well off after 1 s")
				local edge = TrainController.poseAt(plot, DEPART, DEPART + d, DEPART + s.Quarry - 1e-4)
				local inside = TrainController.poseAt(plot, DEPART, DEPART + d, DEPART + s.Quarry + 1e-4)
				T.eq(edge.Leg, "Quarry", label)
				T.eq(inside.Leg, "Underground", label)
				near(edge.Position, inside.Position, 0.02, label .. ": in the tunnel when the leg ends")
			end
		end
	end)

	T.test("TrainClient: tunnels hide the cars", function()
		local s = spans()
		-- coming out of the south tunnel: at the start nothing shows, then the locomotive first
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Underground + 1e-6)
		T.falsy(TrainController.visible(p, p.Position, 7.2), "locomotive still inside")
		local out = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Coast - 0.01, 2)
		T.truthy(TrainController.visible(out, out.Position, 7.2), "locomotive out")
		T.truthy(TrainController.visible(out, out.Position - out.Facing * 25.15, 6), "last wagon out")
		-- the near plot (42 studs north of the portal) sees its train come out halfway through the leg
		local mid = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + (s.Underground + s.Coast) / 2)
		T.truthy(TrainController.visible(mid, mid.Position, 7.2), "locomotive at the mouth")
		-- end of the quarry leg: the whole train is behind the visible mouth
		local inside = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Quarry - 1e-6)
		T.falsy(TrainController.visible(inside, inside.Position - inside.Facing * 25.15, 6), "last wagon inside")
		-- HideDepth fits a locomotive with two wagons (front coupler to back coupler)
		local consist = TrainController.buildConsist(RED, { ORE, ORE }, false)
		local last = consist.Vehicles[3]
		local span = consist.Vehicles[1].Half + last.Offset + last.Half
		T.le(span, TrainController.HideDepth, "a whole consist fits in a tunnel")
		TrainController.destroyConsist(consist)
	end)

	-- no two shown cars of different trains on one track overlap
	local function apart(bodies: { any }, label: string)
		for i = 1, #bodies do
			for j = i + 1, #bodies do
				local a, b = bodies[i], bodies[j]
				if a.Track and a.Track == b.Track then
					for v, ca in a.Centers do
						for w, cb in b.Centers do
							if a.Shown[v] and b.Shown[w] then
								local gap = math.abs(ca - cb) - (a.Halves[v] + b.Halves[w])
								T.le(-TrainController.OcclusionSlack - 1e-6, gap, label)
							end
						end
					end
				end
			end
		end
	end

	T.test("TrainClient: two plots on one coast line never show overlapping trains", function()
		-- plot 1 (the south-most) is the first stop north of the south portal: every other west train passes it
		local south, north = WorldLayout.Plots[1], WorldLayout.Plots[4]
		for _, mineIsThrough in { false, true } do
			local standing = TrainController.nominalBody(2)
			local through = TrainController.nominalBody(2)
			local hid, cameOut, passedBack = false, false, false
			local unloadAt = ARRIVE + 4
			local t = DEPART
			while t < unloadAt + TrainController.returnSeconds(north, 2) do
				-- plot 1's train waits at its full pen (arrived long ago, no unload)
				local ps = TrainController.poseAt(south, DEPART - 400, DEPART - 370, t, 2, nil)
				local pt = TrainController.poseAt(north, DEPART, ARRIVE, t, 2, unloadAt)
				TrainController.fillBody(standing, ps, TrainController.tierOf(ps, false), DEPART - 400, 11)
				TrainController.fillBody(through, pt, TrainController.tierOf(pt, mineIsThrough), DEPART, 12)
				local list = { through, standing }
				TrainController.occlude(list)
				local label = `{if mineIsThrough then "yours" else "theirs"} at {math.floor((t - DEPART) * 100) / 100} s ({pt.Leg})`
				apart(list, label)
				T.eq(standing.Track, "West")
				if mineIsThrough then
					-- your own train always shows (where no tunnel hides it); the other one makes way
					for v = 1, 3 do
						T.eq(through.Shown[v], through.Open[v], label .. ": yours never hides")
					end
				else
					for v = 1, 3 do
						T.truthy(standing.Shown[v], label .. ": the standing train never blinks")
					end
					if through.Open[1] and not through.Shown[1] then
						hid = true
					elseif hid and through.Shown[1] and pt.Leg == "Coast" then
						cameOut = true
					end
					if pt.Leg == "Return" and through.Open[1] and not through.Shown[1] then
						passedBack = true
					end
				end
				t += 0.02
			end
			if not mineIsThrough then
				T.truthy(hid, "the through train hides where it meets the standing one")
				T.truthy(cameOut, "...and comes out at its far end")
				T.truthy(passedBack, "on the way back too")
			end
		end
		-- every pair of west plots, trips overlapping in time (one faster): never a ghost
		for a = 1, 4 do
			for b = 1, 4 do
				if a ~= b then
					local pa, pb = WorldLayout.Plots[a], WorldLayout.Plots[b]
					local ba, bb = TrainController.nominalBody(2), TrainController.nominalBody(1)
					local t = DEPART
					while t < DEPART + 60 do
						local p1 = TrainController.poseAt(pa, DEPART, DEPART + 30, t, 2, DEPART + 33)
						local p2 = TrainController.poseAt(pb, DEPART + 4, DEPART + 16, t, 1, DEPART + 17)
						TrainController.fillBody(ba, p1, TrainController.tierOf(p1, false), DEPART, 1)
						TrainController.fillBody(bb, p2, TrainController.tierOf(p2, false), DEPART + 4, 2)
						local list = { bb, ba }
						TrainController.occlude(list)
						apart(list, `plots {a} and {b} at {t - DEPART}`)
						t += 0.1
					end
				end
			end
		end
	end)

	T.test("TrainClient: other trains leave the station from behind your waiting train", function()
		local mineBody = TrainController.nominalBody(1)
		local yours = TrainController.parkedPose(WorldLayout.Plots[6], nil) -- an east plot: it faces the east portal
		local s = spans()
		for _, otherId in { 2, 7 } do -- a west and an east plot
			local other = WorldLayout.Plots[otherId]
			local body = TrainController.nominalBody(1)
			local startHidden, laterShown = false, false
			local t = DEPART
			while t < DEPART + s.Quarry do
				local p = TrainController.poseAt(other, DEPART, ARRIVE, t, 1)
				TrainController.fillBody(mineBody, yours, 0, -math.huge, 1)
				TrainController.fillBody(body, p, TrainController.tierOf(p, false), DEPART, 2)
				local list = { body, mineBody }
				TrainController.occlude(list)
				apart(list, `plot {otherId} at {t - DEPART}`)
				T.truthy(mineBody.Shown[1] and mineBody.Shown[2], "your waiting train never blinks")
				T.eq(body.Track, "Quarry")
				if t == DEPART then
					startHidden = not body.Shown[2]
				end
				if body.Shown[1] and body.Shown[2] then
					laterShown = true
				end
				t += 0.05
			end
			T.truthy(startHidden, `plot {otherId}: its wagon starts inside yours, so it hides`)
			T.truthy(laterShown, `plot {otherId}: the whole train shows once clear`)
		end
		-- underground or gone: no track, nothing to hide behind
		local below = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + (s.Quarry + s.Underground) / 2)
		T.eq(TrainController.trackOf(below), nil)
		T.eq(TrainController.tierOf(below, true), 0, "yours ranks first")
		T.eq(TrainController.tierOf(TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + 5, 1, nil), false), 1, "standing")
		T.eq(TrainController.tierOf(TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + TRIP * 0.85), false), 2, "moving")
	end)

	T.test("TrainClient: the empty train backs home at a sane speed", function()
		for _, plot in WorldLayout.Plots do
			for _, trip in { 30, 12 } do
				local arrive = DEPART + trip
				local unloadAt = arrive + 0.5
				local peakIn, peakBack = 0, 0
				local back = TrainController.returnSeconds(plot, 2)
				T.le(TrainConfig.ReturnSeconds, back, `plot {plot.Id}: at least ReturnSeconds`)
				local t = DEPART
				while t < unloadAt + back do
					local p = TrainController.poseAt(plot, DEPART, arrive, t, 2, unloadAt)
					if p.Leg == "Coast" then
						peakIn = math.max(peakIn, p.Speed)
					elseif p.Leg == "Return" then
						peakBack = math.max(peakBack, p.Speed)
					end
					t += 0.01
				end
				-- (ease in / out peaks at 1.5x the average)
				T.le(peakBack, TrainController.ReturnSpeed * 1.5 + 0.5, `plot {plot.Id} {trip} s: no zipping away`)
				T.lt(0, peakIn)
				-- gone at the end, still visible just before
				local gone = TrainController.poseAt(plot, DEPART, arrive, unloadAt + back + 1e-6, 2, unloadAt)
				T.eq(gone.Leg, "Done")
			end
		end
		-- the far stops take longer than ReturnSeconds (the old 92 studs/s), the near one doesn't
		T.lt(TrainConfig.ReturnSeconds + 2, TrainController.returnSeconds(WorldLayout.Plots[4], 2), "plot 4 rolls back longer")
		T.near(TrainController.returnSeconds(WEST, 1), TrainConfig.ReturnSeconds, 1e-9, "plot 1 as before")
	end)

	T.test("TrainClient: your train is parked again when loading opens", function()
		local unloadAt = ARRIVE + 2
		local from = TrainController.rollInAt(unloadAt)
		T.near(from + TrainController.RollInSeconds, unloadAt + TrainConfig.ReturnSeconds, 1e-9, "done at unload + ReturnSeconds")
		local plot = WorldLayout.Plots[6]
		local rest = TrainController.parkedPose(plot, nil)
		local open = TrainController.parkedPose(plot, unloadAt + TrainConfig.ReturnSeconds - from)
		near(open.Position, rest.Position, 1e-6, "standing under the chute when the server accepts loads")
		T.eq(open.Speed, 0)
		local rolling = TrainController.parkedPose(plot, 0.5)
		T.lt(0, rolling.Speed, "still backing in before that")
	end)

	T.test("TrainClient: the waiting train stands under the station chute", function()
		local stop = TrainConfig.QuarryStop
		for _, plot in { WEST, EAST_FAR } do
			local mouth = TrainController.quarryMouth(plot)
			local rest = TrainController.parkedPose(plot, nil)
			-- the first wagon's center (where the loading chute pours) is on QuarryStop / TrainPoint
			near(rest.Position - rest.Facing * FIRST_WAGON, stop + RAIL, 1e-4, "first wagon on QuarryStop")
			T.eq(rest.Speed, 0)
			T.truthy(rest.Facing:Dot((mouth - stop).Unit) > 0.999, "faces its portal")
			-- the trip leaves from exactly there: no jump at departure
			local leaving = TrainController.poseAt(plot, DEPART, ARRIVE, DEPART)
			near(leaving.Position, rest.Position, 1e-6, "the trip starts where it waited")
			near(leaving.Facing, rest.Facing, 1e-6)
			local first = TrainController.parkedPose(plot, 0)
			local tunnel = mouth + rest.Facing * TrainController.HideDepth + RAIL
			T.near((first.Position - tunnel):Dot(rest.Facing), 0, 1e-4, "starts in the tunnel")
			local half = TrainController.parkedPose(plot, TrainController.RollInSeconds / 2)
			T.lt((half.Position - rest.Position).Magnitude, (first.Position - rest.Position).Magnitude, "comes closer")
			T.lt(0, half.Speed, "rolling")
			local done = TrainController.parkedPose(plot, TrainController.RollInSeconds)
			near(done.Position, rest.Position, 1e-6, "parked")
			T.eq(TrainController.parkedPose(plot, 99).Speed, 0, "long after: standing")
		end
	end)

	T.test("TrainClient: the wagons stop at the plot's Ore Pen", function()
		local slack = 0.3
		for _, plot in WorldLayout.Plots do
			local line = TrainConfig.lineFor(plot)
			local north = (line[#line] - line[1]).Unit
			local pen = TrainController.penCenter(plot)
			-- the pen's extent along the line (its plot-local X runs along the rails)
			local penAlong = (pen - line[1]):Dot(north)
			local penHalf = BaseLayout.Pen.Area.Size.X / 2
			local farthest = (line[#line] - line[1]).Magnitude + TrainController.BufferGap - TrainController.LocoFront
			for wagons = 1, 2 do
				local stop = TrainController.stopAt(plot, wagons)
				local along = (stop - line[1]):Dot(north)
				T.near(stop.X, line[1].X, 1e-6, "on the line")
				T.le(along, farthest - slack + 1e-3, `plot {plot.Id}: the front buffers stay clear of the buffer stop`)
				local first = along - FIRST_WAGON
				local label = `plot {plot.Id} with {wagons} wagon(s)`
				if along < farthest - slack - 1e-3 then
					T.le(math.abs(first - penAlong), penHalf, label .. ": first wagon alongside the pen")
					local lastWagon = along - FIRST_WAGON - (wagons - 1) * TrainController.WagonLength
					T.le(math.abs(lastWagon - penAlong), penHalf, label .. ": last wagon alongside the pen")
				else
					-- (only the far west plot: the buffer stop at BufferZ keeps the train short of its pen centre)
					T.le(math.abs(first - penAlong), penHalf + TrainController.WagonLength / 2, label .. ": the hopper reaches the pen")
				end
			end
		end
		-- the west plots' wagons unload at the pen (the reviewer's plot 1)
		local first = TrainController.stopAt(WEST, 1) - Vector3.new(0, 0, -FIRST_WAGON)
		local pen = TrainController.penCenter(WEST)
		T.le(math.abs(first.Z - pen.Z), BaseLayout.Pen.Area.Size.X / 2, "plot 1: first wagon at the pen")
		-- the pour mouths open toward the pen
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE, 1, ARRIVE)
		local mouth = TrainController.pourMouth(p, FIRST_WAGON, WEST)
		T.lt((Vector3.new(mouth.X, 0, mouth.Z) - Vector3.new(pen.X, 0, pen.Z)).Magnitude, 30, "a short throw")
	end)

	---------------------------------------------------------------- consists

	T.test("TrainClient: couplers touch and the wheels roll", function()
		local folder = Instance.new("Folder")
		local consist = TrainController.buildConsist(RED, { ORE, {} }, false)
		T.eq(#consist.Vehicles, 3)
		T.eq(consist.Vehicles[1].Model:GetAttribute("Kind"), "Locomotive")
		T.truthy(consist.Vehicles[2].Loaded, "loaded wagon")
		T.falsy(consist.Vehicles[3].Loaded, "empty wagon")
		-- the controller's numbers match the builder
		local offsets = TrainController.wagonOffsets(2)
		T.near(consist.Vehicles[2].Offset, offsets[1], 1e-3, "first wagon offset")
		T.near(consist.Vehicles[3].Offset, offsets[2], 1e-3, "second wagon offset")
		local loco = consist.Vehicles[1]
		local frontCoupler = -worldOf(find(loco.Model, "Attachment", "CouplerFront")).Z
		T.le(frontCoupler, TrainController.LocoFront, "LocoFront covers the front buffers")
		T.lt(TrainController.LocoFront - 0.5, frontCoupler, "...and not much more")
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + TRIP * 0.94)
		local count = place(consist, p, folder)
		T.lt(90, count, "every part placed")
		for i = 1, 2 do
			local back = worldOf(find(consist.Vehicles[i].Model, "Attachment", "CouplerBack"))
			local front = worldOf(find(consist.Vehicles[i + 1].Model, "Attachment", "CouplerFront"))
			near(back, front, 1e-4, "coupler " .. i)
		end
		-- the locomotive's Root sits on the rails at the pose
		near(loco.Model.PrimaryPart.CFrame.Position, p.Position, 1e-4, "locomotive on the pose")
		near(loco.Model.PrimaryPart.CFrame.LookVector, p.Facing, 1e-6, "front ahead")
		-- wheels stay on their axles and turn by distance / radius
		for i, radius in loco.Wheels do
			local part = loco.Parts[i]
			local root = loco.Model.PrimaryPart.CFrame
			near(part.CFrame.Position, (root * loco.Base[i]).Position, 1e-4, "wheel stays on its axle")
			local turned = (root * loco.Base[i]):ToObjectSpace(part.CFrame)
			local _, _, _, _, _, _, _, _, _, _, r21, r22 = turned:GetComponents()
			local angle = math.atan2(r21, r22)
			local want = (-p.Odometer / radius + math.pi) % (2 * math.pi) - math.pi
			T.near((angle - want + math.pi) % (2 * math.pi) - math.pi, 0, 1e-3, "spin")
			break
		end
		-- shown cars are parented, cars in a tunnel are not
		for _, vehicle in consist.Vehicles do
			T.eq(vehicle.Model.Parent, folder, "shown")
		end
		local tunnel = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + TRIP * 0.5)
		T.eq(place(consist, tunnel, folder), 0, "nothing placed underground")
		T.eq(consist.Vehicles[1].Model.Parent, nil, "hidden")
		-- spare trains are found again by what they were built from
		local key = TrainController.consistKey(RED, { ORE, {} }, false)
		T.eq(consist.Key, key)
		T.eq(TrainController.consistKey(RED, { ORE, {} }, false), key, "the same train, the same key")
		T.truthy(TrainController.consistKey(RED, { ORE, {} }, true) ~= key, "turned wagons differ")
		T.truthy(TrainController.consistKey(RED, { ORE }, false) ~= key, "fewer wagons differ")
		TrainController.destroyConsist(consist)
	end)

	T.test("TrainClient: the wagons tip toward the plot's Ore Pen", function()
		for _, plot in WorldLayout.Plots do
			local flip = TrainController.wagonFlip(plot)
			T.eq(flip, plot.Center.X > 0, "plot " .. plot.Id .. " turns its wagons on the east side")
			local consist = TrainController.buildConsist(RED, { ORE }, flip)
			local wagon = consist.Vehicles[2]
			local function oreCenter(): any
				local sum, n = Vector3.new(), 0
				for _, part in wagon.Model:GetDescendants() do
					if part:IsA("BasePart") and part.Name == "Ore" then
						sum += part.CFrame.Position
						n += 1
					end
				end
				return sum / n
			end
			local upright = TrainController.poseAt(plot, DEPART, ARRIVE, ARRIVE + 1, 1, nil)
			local tipped = TrainController.poseAt(plot, DEPART, ARRIVE, ARRIVE + 1 + TrainController.TipUp, 1, ARRIVE + 1)
			T.near(tipped.Tip, 1, 1e-9)
			place(consist, upright, nil)
			local before = oreCenter()
			local wheel = wagon.Parts[next(wagon.Wheels) :: number].CFrame.Position
			place(consist, tipped, nil)
			local after = oreCenter()
			local toward = TrainController.penSide(plot)
			T.lt(1, (after - before):Dot(toward), "plot " .. plot.Id .. " ore moves toward the pen")
			near(wagon.Parts[next(wagon.Wheels) :: number].CFrame.Position, wheel, 1e-4, "the bogies stay put")
			TrainController.destroyConsist(consist)
		end
	end)

	T.test("TrainClient: the ore flies into the pen and over the museum", function()
		local foundry = BaseLayout.Museum
		for _, plot in WorldLayout.Plots do
			local cf = WorldLayout.plotCFrame(plot)
			local top = cf.Position.Y + foundry.Size.Y
			for wagons = 1, 2 do
				local p = TrainController.poseAt(plot, DEPART, ARRIVE, ARRIVE + 1, wagons, ARRIVE)
				for _, offset in TrainController.wagonOffsets(wagons) do
					local mouth = TrainController.pourMouth(p, offset, plot)
					for _, rolls in { { 0, 0 }, { 0.5, 0.5 }, { 1, 1 }, { 0.2, 0.9 }, { 0.9, 0.1 } } do
						local to = TrainController.penSpot(plot, rolls[1], rolls[2], mouth)
						-- lands inside the pen
						local l = cf:PointToObjectSpace(to) - BaseLayout.Pen.Area.Center
						T.le(math.abs(l.X), BaseLayout.Pen.Area.Size.X / 2 - 2.9, `plot {plot.Id} lands in the pen (x)`)
						T.le(math.abs(l.Z), BaseLayout.Pen.Area.Size.Z / 2 - 2.9, `plot {plot.Id} lands in the pen (z)`)
						local height = TrainController.arcHeight(plot, mouth, to, 5)
						T.le(5, height)
						for i = 1, 99 do
							local at = TrainController.arc(mouth, to, height, i / 100)
							local f = cf:PointToObjectSpace(at) - foundry.Center
							if math.abs(f.X) <= foundry.Size.X / 2 and math.abs(f.Z) <= foundry.Size.Z / 2 then
								T.lt(top, at.Y, `plot {plot.Id} wagon at {offset}: the chunk clears the museum`)
							end
						end
					end
				end
			end
		end
	end)

	T.test("TrainClient: wagons, loads and the cargo heap", function()
		T.eq(TrainController.wagonCount(1), 1)
		T.eq(TrainController.wagonCount(TrainController.WagonSlots), 1)
		T.eq(TrainController.wagonCount(TrainController.WagonSlots + 1), 2)
		T.eq(TrainController.wagonCount(80), 2, "never more than two")
		local a, b, c, d = ORE[1], ORE[2], ORE[3], RED
		local split = TrainController.splitLoad({ a, b, c, d }, 2)
		T.eq(#split[1], 2)
		T.eq(split[1][1], a)
		T.eq(split[1][2], c)
		T.eq(split[2][1], b)
		T.eq(split[2][2], d)
		local one = TrainController.splitLoad({ a }, 2)
		T.eq(#one[1], 1)
		T.eq(#one[2], 1, "a single color fills both wagons")
		T.eq(TrainController.splitLoad({}, 1)[1][1], TrainController.DirtyLoad[1], "Dirty Ore look when unknown")
		-- the server's dirt color becomes the warm clay shades (the waiting train shows the same)
		local dirt = TrainController.displayLoad({ ItemBuilder.DirtyCrust })
		T.eq(#dirt, #TrainController.DirtyLoad)
		T.eq(dirt[1], TrainController.DirtyLoad[1])
		local mixed = TrainController.displayLoad({ ItemBuilder.DirtyCrust, a, ItemBuilder.DirtyCrust })
		T.eq(mixed[1], TrainController.DirtyLoad[1], "most common first stays first")
		T.eq(mixed[#TrainController.DirtyLoad + 1], a)
		T.eq(#mixed, #TrainController.DirtyLoad + 1, "dirt only once")
		T.eq(#TrainController.displayLoad({ a, b, c, d, a, b, ItemBuilder.DirtyCrust }), 6, "at most 6 colors")
		local clay = TrainController.DirtyLoad[1]
		T.lt(0.6, clay.R, "a light, warm load")
		T.lt(clay.B, clay.R)
		local fills = TrainController.wagonFills(6, 8, 1)
		T.near(fills[1], 0.75, 1e-9)
		fills = TrainController.wagonFills(5, 18, 2)
		T.near(fills[1], 5 / 9, 1e-9, "the front wagon fills first")
		T.eq(fills[2], 0)
		fills = TrainController.wagonFills(40, 18, 2)
		T.eq(fills[1], 1)
		T.eq(fills[2], 1, "never over full")
		T.eq(TrainController.wagonFills(3, 0, 1)[1], 0, "no capacity")
		-- the heap sinks into the hopper (and comes back up)
		local consist = TrainController.buildConsist(RED, { ORE }, false)
		local wagon = consist.Vehicles[2]
		local index = nil
		for i in wagon.Heap do
			index = i
			break
		end
		T.truthy(index, "the ore parts are the heap")
		local topY = wagon.Offsets[index :: number].Position.Y
		TrainController.setFill(wagon, 0.25)
		T.lt(wagon.Offsets[index :: number].Position.Y, topY, "a low load sits lower")
		TrainController.setFill(wagon, 1)
		T.near(wagon.Offsets[index :: number].Position.Y, topY, 1e-9, "full again")
		TrainController.destroyConsist(consist)
	end)

	T.test("TrainClient: the load only slides out once the server unloads", function()
		T.eq(TrainController.pourFill(TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + TRIP * 0.85)), nil, "full on the coast")
		T.eq(TrainController.pourFill(TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + 30, 1, nil)), nil, "full while held")
		local unloadAt = ARRIVE + 0.2
		local consist = TrainController.buildConsist(RED, { ORE, ORE }, false)
		local fills = {}
		local holdEnd = TrainController.TipUp + TrainController.TipHold
		for _, after in { 0, 0.2, 0.35, 0.5, 0.8, holdEnd } do
			TrainController.applyPour(consist, TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + after, 2, unloadAt))
			table.insert(fills, consist.Vehicles[2].Fill)
		end
		T.eq(fills[1], 1, "not before the tip")
		T.lt(fills[4], 1, "pouring once the tip passes PourThreshold")
		T.lt(0.05, fills[5], "still pouring during the hold (the rocks slide out, not blink out)")
		for i = 2, #fills do
			T.le(fills[i], fills[i - 1], "never fills back up")
		end
		T.eq(fills[#fills], 0, "empty at the end of the hold")
		-- it starts pouring when the hopper passes PourThreshold
		local start = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + 0.25, 2, unloadAt)
		T.lt(start.Tip, TrainController.PourThreshold, "0.25 s: not tipped far enough")
		T.eq(start.Pour, 0, "...so nothing pours yet")
		-- tipping back and the trip home keep it empty
		local down = unloadAt + TrainController.TipUp + TrainController.TipHold + TrainController.TipDown / 2
		TrainController.applyPour(consist, TrainController.poseAt(WEST, DEPART, ARRIVE, down, 2, unloadAt))
		T.lt(consist.Vehicles[2].Fill, 0.05, "stays empty while the hopper comes down")
		T.eq(TrainController.pourFill(TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + 3, 2, unloadAt)), 0, "empty on the way back")
		T.eq(consist.Vehicles[3].Fill, consist.Vehicles[2].Fill, "both wagons pour")
		TrainController.destroyConsist(consist)
	end)

	-- the top of a part in its wagon's model space (TrainBuilder's frame: the rim top is at TOP 6.4)
	local function topOf(cf: any, size: any): number
		local h = size / 2
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		return cf.Position.Y + math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
	end
	local RIM_TOP = 6.4

	T.test("TrainClient: a poured wagon is empty (no rock above the rim)", function()
		for _, plot in { WEST, EAST_FAR } do
			local consist = TrainController.buildConsist(RED, { ORE, ORE }, TrainController.wagonFlip(plot))
			local unloadAt = ARRIVE + 0.3
			-- the moment the pour is done (pourFill 0), and on the way back
			local holdEnd = TrainController.TipUp + TrainController.TipHold
			for _, after in { holdEnd - 0.02, holdEnd + 0.01, TrainController.unloadSeconds() + 1 } do
				local p = TrainController.poseAt(plot, DEPART, ARRIVE, unloadAt + after, 2, unloadAt)
				TrainController.applyPour(consist, p)
				place(consist, p, nil)
			end
			for w = 2, 3 do
				local wagon = consist.Vehicles[w]
				T.eq(wagon.Fill, 0, `plot {plot.Id} wagon {w - 1} poured out`)
				T.truthy(wagon.Empty, "flagged empty")
				local rocks, bed = 0, 0
				for i, part in wagon.Parts do
					local offset = wagon.Offsets[i]
					if part.Name == "Ore" then
						rocks += 1
						local hidden = part.Transparency >= 1
						T.truthy(hidden or topOf(offset, part.Size) <= RIM_TOP, `plot {plot.Id}: no rock sticks out of the empty hopper`)
						T.truthy(hidden, "the rocks are gone")
					elseif part.Name == "OreBed" then
						bed += 1
						T.le(topOf(offset, part.Size), RIM_TOP - 1.2, "the bed sinks to the empty hopper's floor")
						T.lt(part.Transparency, 1, "...and stays as its dark floor")
					end
				end
				T.lt(0, rocks, "a loaded wagon has rocks")
				T.eq(bed, 1)
			end
			-- a spare train reused for a new trip is full again (setFill above 0 brings the rocks back)
			local wagon = consist.Vehicles[2]
			TrainController.setFill(wagon, 1)
			T.falsy(wagon.Empty)
			for i, part in wagon.Parts do
				if part.Name == "Ore" then
					T.eq(part.Transparency, wagon.Rocks[i], "rock shown again")
					near(wagon.Offsets[i].Position, wagon.Base[i].Position, 1e-9, "rock back on the heap")
				end
			end
			TrainController.destroyConsist(consist)
		end
	end)

	T.test("TrainClient: the rocks slide over the lip while they pour", function()
		local consist = TrainController.buildConsist(RED, { ORE }, false)
		local wagon = consist.Vehicles[2]
		local index: number? = nil
		for i in wagon.Rocks do
			index = i
			break
		end
		local i = index :: number
		local base = wagon.Base[i].Position
		TrainController.setFill(wagon, 0.5, true)
		local half = wagon.Offsets[i].Position - base
		T.near(half.X, TrainController.PourSlide * 0.5, 1e-9, "toward the tipping side (+X)")
		T.lt(half.Y, 0, "and down")
		-- the waiting train's heap only sinks (no sideways slide)
		TrainController.setFill(wagon, 0.5)
		T.near((wagon.Offsets[i].Position - base).X, 0, 1e-9, "parked: straight down")
		TrainController.destroyConsist(consist)
	end)

	T.test("TrainClient: the waiting train's heap grows from a small mound", function()
		local consist = TrainController.buildConsist(RED, { ORE }, false)
		local wagon = consist.Vehicles[2]
		local function peak(): number
			local best = -math.huge
			for i, part in wagon.Parts do
				if part.Name == "Ore" then
					best = math.max(best, topOf(wagon.Offsets[i], part.Size))
				end
			end
			return best
		end
		local full = peak()
		TrainController.setFill(wagon, 1 / 8)
		local low = peak()
		T.le(low, RIM_TOP + 0.05, "1 of 8: a small mound inside the hopper")
		T.lt(RIM_TOP - 1.2, low, "...that still shows")
		T.lt(1.2, full - low, "a clear difference to a full wagon")
		T.lt(RIM_TOP + 1, full, "full: a dome over the rim")
		TrainController.destroyConsist(consist)
	end)

	T.test("TrainClient: TrainTrip payloads are checked", function()
		local good = { UserId = 7, PlotId = 3, DepartAt = 10, ArriveAt = 40, Count = 6.7, Color = RED, Load = { ORE[1], "junk", ORE[2] } }
		local trip = TrainController.parseTrip(good)
		T.truthy(trip, "valid")
		T.eq(trip.Count, 6, "whole items")
		T.eq(#trip.Load, 2, "junk colors dropped")
		T.eq(trip.Color, RED)
		T.eq(trip.UnloadAt, nil, "not unloaded yet")
		local function bad(change: { [string]: any }, label: string)
			local copy = table.clone(good)
			for k, v in change do
				copy[k] = v
			end
			T.eq(TrainController.parseTrip(copy), nil, label)
		end
		bad({ PlotId = 99 }, "unknown plot")
		bad({ PlotId = 1.5 }, "fractional plot")
		bad({ ArriveAt = 10 }, "no duration")
		bad({ DepartAt = 0 / 0 }, "NaN")
		bad({ ArriveAt = math.huge }, "infinite")
		bad({ UserId = "7" }, "user id")
		T.eq(TrainController.parseTrip("trip"), nil, "not a table")
		local noColor = table.clone(good)
		noColor.Color = nil
		noColor.Load = nil
		noColor.Count = nil
		local fixed = TrainController.parseTrip(noColor)
		T.eq(fixed.Color, TrainController.BannerColors[3], "banner color of plot 3")
		T.eq(#fixed.Load, 0)
		T.eq(fixed.Count, 1)
	end)

	T.test("TrainClient: Waiting trains and late unloads keep their train", function()
		local base = { UserId = 7, PlotId = 3, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 8, Color = RED, Load = { ORE[1] } }
		local function parse(change: { [string]: any }): any
			local copy = table.clone(base)
			for k, v in change do
				copy[k] = v
			end
			return TrainController.parseTrip(copy)
		end
		local trip = parse({})
		T.eq(trip.Waiting, nil, "not waiting")
		T.eq(parse({ Waiting = true }).Waiting, true, "the server's Waiting")
		T.eq(parse({ Waiting = "yes" }).Waiting, nil, "junk is not waiting")
		-- a new trip
		local first, rebuildFirst = TrainController.mergeTrip(nil, trip, DEPART)
		T.eq(first, trip)
		T.falsy(rebuildFirst)
		-- the pen is full: the same trip again, now waiting (the train is kept)
		local waiting, rebuild = TrainController.mergeTrip(trip, parse({ Waiting = true }), ARRIVE + 3)
		T.eq(waiting.Waiting, true)
		T.falsy(rebuild, "no rebuild for the Waiting announcement")
		-- the late unload: same DepartAt, ArriveAt = the unload, no Waiting (cleared)
		local late, rebuildLate = TrainController.mergeTrip(waiting, parse({ ArriveAt = ARRIVE + 200 }), ARRIVE + 200)
		T.eq(late.Waiting, nil, "a TrainTrip without Waiting clears it")
		T.eq(late.ArriveAt, ARRIVE + 200)
		T.falsy(rebuildLate, "the standing train stays")
		T.eq(late.UnloadAt, ARRIVE + 200, "the late TrainTrip starts the tip")
		T.eq(waiting.UnloadAt, nil, "(the merge never changes the trip it got)")
		-- after a very long wait the server moves DepartAt (MaxTripSpan): still the same standing train
		local now = ARRIVE + 650
		local shifted, rebuildShifted = TrainController.mergeTrip(waiting, parse({ DepartAt = now - 30, ArriveAt = now }), now)
		T.eq(shifted.DepartAt, now - 30, "the new times")
		T.eq(shifted.ArriveAt, now)
		T.eq(shifted.Waiting, nil)
		T.falsy(rebuildShifted, "no blink")
		T.eq(shifted.UnloadAt, now, "and it tips now")
		local plot = WorldLayout.Plots[3]
		local before = TrainController.poseAt(plot, waiting.DepartAt, waiting.ArriveAt, now, 1)
		local after = TrainController.poseAt(plot, shifted.DepartAt, shifted.ArriveAt, now, 1)
		T.eq(after.Leg, "Stopped")
		near(after.Position, before.Position, 1e-6, "it doesn't move")
		-- what this screen knows survives the merge
		local quiet = table.clone(waiting)
		quiet.UnloadAt = ARRIVE + 300
		quiet.Quiet = true
		local kept = TrainController.mergeTrip(quiet, parse({ Waiting = true }), ARRIVE + 310)
		T.eq(kept.UnloadAt, ARRIVE + 300)
		T.eq(kept.Quiet, true)
		-- a moved DepartAt for a train still on its way, or a new departure, is a new trip
		local _, onTheWay = TrainController.mergeTrip(trip, parse({ DepartAt = DEPART + 5, ArriveAt = ARRIVE + 5 }), DEPART + 10)
		T.truthy(onTheWay, "on its way: a new trip")
		local nextTrip, rebuildNext =
			TrainController.mergeTrip(late, parse({ DepartAt = ARRIVE + 700, ArriveAt = ARRIVE + 730 }), ARRIVE + 700)
		T.truthy(rebuildNext, "the next departure")
		T.eq(nextTrip.UnloadAt, nil)
		-- a payload without load colors never replaces one with them
		local bare = table.clone(base)
		bare.Load = nil
		local richer, rebuildBare = TrainController.mergeTrip(trip, TrainController.parseTrip(bare), DEPART + 5)
		T.eq(#richer.Load, 1, "keeps the colors")
		T.falsy(rebuildBare)
		-- and the other way round: the colors arrive after a bare trip (the snapshot's): rebuilt with them
		local colored, rebuildColored = TrainController.mergeTrip(TrainController.parseTrip(bare), trip, DEPART + 5)
		T.eq(#colored.Load, 1)
		T.truthy(rebuildColored)
	end)

	T.test("TrainClient: your trip follows the State snapshot (full pen, late unload)", function()
		local trip = TrainController.parseTrip({ UserId = 7, PlotId = 5, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 8, Color = RED })
		local function news(fields: { [string]: any }, now: number): any
			return TrainController.snapshotNews(trip, TrainView.read(fields), now)
		end
		-- on its way
		T.eq(news({ Moving = 8, DepartAt = DEPART, ArriveAt = ARRIVE }, ARRIVE - 5), nil)
		-- arrived, the pen is full: it waits (TrainService keeps the original ArriveAt)
		T.eq(news({ Moving = 8, DepartAt = DEPART, ArriveAt = ARRIVE, Waiting = true }, ARRIVE + 4), "Waiting")
		-- still loaded right at the arrival (the next snapshot hasn't come yet): nothing new
		T.eq(news({ Moving = 8, DepartAt = DEPART, ArriveAt = ARRIVE }, ARRIVE + 0.1), nil)
		-- still loaded UnloadGrace after the arrival without the Waiting field: waiting too
		T.eq(news({ Moving = 8, DepartAt = DEPART, ArriveAt = ARRIVE }, ARRIVE + TrainView.UnloadGrace + 0.1), "Waiting")
		-- unloaded on time, or 40 s later after the pen was emptied (ArriveAt moves to the unload)
		T.eq(news({ Moving = 0, DepartAt = DEPART, ArriveAt = ARRIVE }, ARRIVE + 0.2), "Unloaded")
		T.eq(news({ Moving = 0, DepartAt = DEPART, ArriveAt = ARRIVE + 40 }, ARRIVE + 40.2), "Unloaded")
		-- the late ArriveAt is the same trip, never a new one
		T.eq(news({ Moving = 0, DepartAt = DEPART + 100, ArriveAt = ARRIVE + 140 }, ARRIVE + 140), nil, "another trip")
		-- the server has no trip any more (delivered while it couldn't be shown)
		T.eq(news({ Moving = 0 }, ARRIVE + 5), "Gone")
		T.eq(news({ Moving = 0 }, DEPART + 3), nil, "a stale snapshot during the trip")
		-- once unloaded, nothing changes it again
		trip.UnloadAt = ARRIVE + 40
		T.eq(news({ Moving = 0, DepartAt = DEPART, ArriveAt = ARRIVE + 40 }, ARRIVE + 41), nil)
		-- and the pose holds the train at the stop until then, then unloads once
		local held = TrainController.poseAt(WorldLayout.Plots[5], DEPART, ARRIVE, ARRIVE + 39, 1, trip.UnloadAt)
		T.eq(held.Leg, "Stopped", "waiting at a full pen")
		local pouring = TrainController.poseAt(WorldLayout.Plots[5], DEPART, ARRIVE, ARRIVE + 40.5, 1, trip.UnloadAt)
		T.eq(pouring.Leg, "Unload")
	end)

	T.test("TrainClient: a Waiting train stands at its stop until the late TrainTrip or the unload Fx", function()
		local plot = WorldLayout.Plots[3]
		local base = { UserId = 7, PlotId = 3, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 8, Color = RED, Load = { ORE[1] } }
		local function parse(change: { [string]: any }): any
			local copy = table.clone(base)
			for k, v in change do
				copy[k] = v
			end
			return TrainController.parseTrip(copy)
		end
		-- a joiner learns about it from its Waiting TrainTrip alone
		local trip = TrainController.mergeTrip(nil, parse({ Waiting = true }), ARRIVE + 40)
		T.eq(trip.Waiting, true)
		T.eq(trip.UnloadAt, nil)
		-- it stands loaded at its stop: no tip, no way back, however long the pen stays full
		local stop = TrainController.stopAt(plot, 1) + RAIL
		for _, later in { 1, 30, TrainController.HoldLimit + 50, 3000 } do
			local p = TrainController.poseAt(plot, trip.DepartAt, trip.ArriveAt, ARRIVE + later, 1, trip.UnloadAt)
			T.eq(p.Leg, "Stopped", `standing {later} s after the arrival`)
			T.eq(p.Tip, 0, "no tip")
			T.eq(p.Speed, 0)
			near(p.Position, stop, 1e-6, "at its stop")
			T.eq(TrainController.pourFill(p), nil, "still loaded")
			T.falsy(TrainController.holdExpired(trip, false, ARRIVE + later), "never sent away while Waiting")
		end
		-- (a train the server never said anything about leaves quietly after HoldLimit; yours never)
		local silent = parse({})
		T.falsy(TrainController.holdExpired(silent, false, ARRIVE + TrainController.HoldLimit - 1))
		T.truthy(TrainController.holdExpired(silent, false, ARRIVE + TrainController.HoldLimit + 1))
		T.falsy(TrainController.holdExpired(silent, true, ARRIVE + 3000), "your own train waits for the server")
		-- repeats change nothing: the Waiting announcement again, the join list's copy without Waiting
		local again = TrainController.mergeTrip(trip, parse({ Waiting = true }), ARRIVE + 60)
		T.eq(again.UnloadAt, nil, "the announcement again")
		local copy = TrainController.mergeTrip(parse({}), parse({}), ARRIVE + 60)
		T.eq(copy.UnloadAt, nil, "the same times again never unload")
		-- the pen has room: TrainTrip once more, ArriveAt = the unload, no Waiting -> the tip starts now
		local unloadAt = ARRIVE + 90
		local late, rebuild = TrainController.mergeTrip(again, parse({ ArriveAt = unloadAt }), unloadAt + 0.2)
		T.falsy(rebuild, "the same train")
		T.eq(late.Waiting, nil)
		T.near(late.UnloadAt, unloadAt + 0.2, 1e-9, "tips when it comes")
		local tipping = TrainController.poseAt(plot, late.DepartAt, late.ArriveAt, unloadAt + 0.6, 1, late.UnloadAt)
		T.eq(tipping.Leg, "Unload")
		T.lt(0, tipping.Tip, "the hoppers tip")
		near(tipping.Position, stop, 1e-6, "where it stood")
		local back = TrainController.poseAt(plot, late.DepartAt, late.ArriveAt, unloadAt + 4, 1, late.UnloadAt)
		T.eq(back.Leg, "Return", "then it rolls back")
		-- the Fx that follows finds it started (its train pours, no stand-in dust) and changes nothing
		T.truthy(TrainController.takeUnload(late, 3, unloadAt + 0.3), "the Fx belongs to it")
		T.near(late.UnloadAt, unloadAt + 0.2, 1e-9, "not restarted")
		T.falsy(TrainController.takeUnload(late, 3, unloadAt + 30), "a later Fx is another unload")
		-- the Fx alone (no late TrainTrip came): the tip starts at the Fx
		local alone = TrainController.mergeTrip(nil, parse({ Waiting = true }), ARRIVE + 40)
		T.falsy(TrainController.takeUnload(alone, 4, ARRIVE + 70), "another plot's Fx")
		T.eq(alone.UnloadAt, nil)
		T.truthy(TrainController.takeUnload(alone, 3, ARRIVE + 70))
		T.eq(alone.UnloadAt, ARRIVE + 70)
		T.eq(alone.Waiting, nil, "not waiting any more")
		-- an Fx for a train still on its way, or a quiet leave, is not its unload
		local onTheWay = parse({})
		T.falsy(TrainController.takeUnload(onTheWay, 3, DEPART + 5))
		T.eq(onTheWay.UnloadAt, nil)
		T.truthy(TrainController.takeUnload(parse({}), 3, ARRIVE - 1), "just reaching the stop")
		local quiet = parse({})
		quiet.UnloadAt = ARRIVE + 300
		quiet.Quiet = true
		T.falsy(TrainController.takeUnload(quiet, 3, ARRIVE + 301), "it left quietly")
	end)

	-- What TrainService sends for your own train that waits at a full pen, in the order it sends it:
	-- TrainTrip, the Waiting TrainTrip, the late TrainTrip (ArriveAt = the unload U, DepartAt kept or
	-- shifted under MaxTripSpan), Fx "TrainUnload", then the State snapshot (Moving 0, ArriveAt U).
	T.test("TrainClient: your waiting train in the server's real message order tips once and comes home", function()
		local plot = WorldLayout.Plots[3]
		local base = { UserId = 7, PlotId = 3, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 8, Color = RED, Load = { ORE[1] } }
		local function payload(change: { [string]: any }): any
			local copy = table.clone(base)
			for k, v in change do
				copy[k] = v
			end
			return copy
		end
		local function colorOf(_: number): any
			return RED
		end
		local cases = {
			{ Name = "DepartAt kept", Unload = ARRIVE + 90, FxFirst = false },
			{ Name = "DepartAt shifted", Unload = ARRIVE + 650, FxFirst = false },
			-- (reliable remotes keep the order; even if the Fx came first it stays one tip)
			{ Name = "shifted, Fx first", Unload = ARRIVE + 650, FxFirst = true },
		}
		for _, case in cases do
			local name = case.Name
			local unloadAt = case.Unload
			-- TrainService.deliver: DepartAt kept unless the trip would get longer than MaxTripSpan
			local departAt = DEPART
			if unloadAt - departAt > TrainConfig.MaxTripSpan then
				departAt = unloadAt - (ARRIVE - DEPART)
			end
			T.eq(departAt ~= DEPART, unloadAt == ARRIVE + 650, name .. ": the case")
			local trip: any = nil
			local function receive(raw: any, now: number)
				local incoming = TrainController.parseTrip(raw)
				T.truthy(incoming, name .. ": a TrainTrip clients accept")
				local merged, rebuild = TrainController.mergeTrip(trip, incoming, now)
				if trip then
					T.falsy(rebuild, name .. ": the same train, never rebuilt")
				end
				trip = merged
			end
			-- what syncSnapshotTrip does with a snapshot
			local function state(fields: { [string]: any }, now: number): any
				local train = TrainView.read(fields)
				local news = TrainController.applySnapshot(trip, train, now)
				T.eq(TrainController.snapshotTrip(trip, train, 7, plot, colorOf, now), nil, name .. ": no second trip from the snapshot")
				return news
			end
			-- it leaves and arrives at a full pen
			receive(payload({}), DEPART + 0.05)
			T.eq(state({ Moving = 8, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE }, DEPART + 0.1), nil, name .. ": on its way")
			receive(payload({ Waiting = true }), ARRIVE + 0.1)
			T.eq(trip.Waiting, true, name .. ": waiting")
			T.eq(trip.UnloadAt, nil, name .. ": no tip at the full pen")
			local waiting = { Moving = 8, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE, Waiting = true }
			T.eq(state(waiting, ARRIVE + 0.3), "Waiting")
			T.eq(trip.UnloadAt, nil)
			for _, t in { ARRIVE + 1, ARRIVE + 30, unloadAt - 0.5 } do
				local p = TrainController.poseAt(plot, trip.DepartAt, trip.ArriveAt, t, 1, trip.UnloadAt)
				T.eq(p.Leg, "Stopped", `{name}: standing at {t}`)
				T.eq(p.Tip, 0)
				T.eq(TrainController.parkedState(TrainView.read(waiting), trip, t), "Away", name .. ": no train at the station")
				T.eq(TrainView.status(TrainView.read(waiting), t).Phase, "Waiting", name .. ": the chip says so")
				T.eq(state(waiting, t), "Waiting", name .. ": the next snapshots")
			end
			-- the pen has room: the late TrainTrip, the Fx right after it (or, at worst, right before)
			local lateAt = unloadAt + 0.05
			local fxAt = unloadAt + 0.06
			local startedAt = lateAt
			if case.FxFirst then
				fxAt, lateAt = unloadAt + 0.05, unloadAt + 0.06
				startedAt = fxAt
				T.truthy(TrainController.takeUnload(trip, 3, fxAt), name .. ": the Fx starts the tip")
				T.eq(trip.UnloadAt, startedAt)
			end
			receive(payload({ DepartAt = departAt, ArriveAt = unloadAt }), lateAt)
			T.eq(trip.DepartAt, departAt, name .. ": the new times")
			T.eq(trip.ArriveAt, unloadAt)
			T.eq(trip.Waiting, nil, name .. ": not waiting any more")
			T.eq(trip.UnloadAt, startedAt, name .. ": the tip starts once, at whichever came first")
			if not case.FxFirst then
				T.truthy(TrainController.takeUnload(trip, 3, fxAt), name .. ": the Fx is this unload (its train pours)")
				T.eq(trip.UnloadAt, startedAt, name .. ": the Fx doesn't restart it")
			end
			-- the snapshot 0.2 s later and the ones after it change nothing
			local home = { Moving = 0, Capacity = 8, DepartAt = departAt, ArriveAt = unloadAt }
			for _, t in { unloadAt + 0.25, unloadAt + 1, unloadAt + 4 } do
				T.eq(state(home, t), nil, `{name}: the snapshot at {t} adds nothing`)
				T.eq(trip.UnloadAt, startedAt, name .. ": still one tip")
			end
			-- the tip where it stood, the way back, then your train backs into the station
			local tipping = TrainController.poseAt(plot, trip.DepartAt, trip.ArriveAt, startedAt + 0.6, 1, trip.UnloadAt)
			T.eq(tipping.Leg, "Unload", name .. ": it tips")
			near(tipping.Position, TrainController.stopAt(plot, 1) + RAIL, 1e-6, name .. ": where it stood")
			local from = TrainController.rollInAt(startedAt)
			local snap = TrainView.read(home)
			for _, t in { unloadAt + 0.25, unloadAt + 2, from - 0.05 } do
				T.eq(TrainController.parkedState(snap, trip, t), "Away", `{name}: away at {t}`)
			end
			local parked, roll = TrainController.parkedState(snap, trip, from + 0.05)
			T.eq(parked, "Parked", name .. ": back at the station")
			T.eq(roll, from, name .. ": backing in from rollInAt")
			T.eq(TrainController.parkedState(snap, trip, unloadAt + TrainConfig.ReturnSeconds + 5), "Parked", name .. ": and stays")
		end
	end)

	T.test("TrainClient: your trip from the snapshot alone (no TrainTrip came)", function()
		local plot = WorldLayout.Plots[2]
		local function colorOf(id: number): any
			return TrainController.BannerColors[id]
		end
		local function make(known: any, fields: { [string]: any }, now: number): any
			return TrainController.snapshotTrip(known, TrainView.read(fields), 7, plot, colorOf, now)
		end
		local moving = { Moving = 5, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE }
		local grace = TrainController.SnapshotTripGrace
		T.eq(make(nil, moving, DEPART + grace), nil, "its TrainTrip may still come")
		local trip = make(nil, moving, DEPART + grace + 0.01)
		T.truthy(trip, "then it is made from the snapshot")
		T.eq(trip.DepartAt, DEPART)
		T.eq(trip.ArriveAt, ARRIVE)
		T.eq(trip.Count, 5, "the ore on board")
		T.eq(trip.PlotId, 2)
		T.eq(trip.Color, TrainController.BannerColors[2])
		T.eq(#trip.Load, 0, "dirt colors")
		T.eq(trip.Waiting, nil)
		T.eq(trip.UnloadAt, nil)
		T.eq(make(nil, { Moving = 0, Capacity = 8 }, ARRIVE), nil, "no trip")
		-- waiting at a full pen (a joiner without the list yet)
		local waiting = make(nil, { Moving = 5, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE, Waiting = true }, ARRIVE + 50)
		T.eq(waiting.Waiting, true)
		T.eq(waiting.UnloadAt, nil, "no tip")
		-- already unloaded: only the way back is left, then nothing
		local back = make(nil, { Moving = 0, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE }, ARRIVE + 1)
		T.eq(back.UnloadAt, ARRIVE, "it unloaded at ArriveAt")
		T.eq(make(nil, { Moving = 0, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE }, ARRIVE + 10000), nil, "long home")
		-- a known trip is kept until it unloaded and a newer departure comes
		local known = TrainController.parseTrip({ UserId = 7, PlotId = 2, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 5 })
		T.eq(make(known, moving, DEPART + 10), nil, "the known trip")
		local nextTrip = { Moving = 8, Capacity = 8, DepartAt = ARRIVE + 100, ArriveAt = ARRIVE + 130 }
		T.eq(make(known, nextTrip, ARRIVE + 105), nil, "not unloaded on this screen yet")
		known.UnloadAt = ARRIVE
		T.eq(make(known, { Moving = 0, Capacity = 8, DepartAt = DEPART + 0.3, ArriveAt = ARRIVE }, ARRIVE + 3), nil, "the same trip")
		local newer = make(known, nextTrip, ARRIVE + 105)
		T.truthy(newer, "the next departure")
		T.eq(newer.DepartAt, ARRIVE + 100)
		-- applySnapshot: the news lands on the trip
		local mine = TrainController.parseTrip({ UserId = 7, PlotId = 2, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 5 })
		T.eq(TrainController.applySnapshot(mine, TrainView.read(moving), ARRIVE - 5), nil)
		T.eq(TrainController.applySnapshot(mine, TrainView.read(moving), ARRIVE + TrainView.UnloadGrace), "Waiting")
		T.eq(mine.Waiting, true)
		T.eq(mine.UnloadAt, nil)
		local unloaded = { Moving = 0, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE + 40 }
		T.eq(TrainController.applySnapshot(mine, TrainView.read(unloaded), ARRIVE + 40.2), "Unloaded")
		T.eq(mine.UnloadAt, ARRIVE + 40.2, "the tip starts now")
		T.eq(mine.Waiting, nil)
		T.eq(TrainController.applySnapshot(mine, TrainView.read(unloaded), ARRIVE + 41), nil, "once")
		T.eq(mine.UnloadAt, ARRIVE + 40.2)
		local gone = TrainController.parseTrip({ UserId = 7, PlotId = 2, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 5 })
		T.eq(TrainController.applySnapshot(gone, TrainView.read({ Moving = 0, Capacity = 8 }), ARRIVE + 5), "Gone")
		T.eq(gone.UnloadAt, nil, "the caller drops it")
	end)

	T.test("TrainClient: no train at your station while it has ore on board", function()
		local function snap(fields: { [string]: any }): any
			return TrainView.read(fields)
		end
		local function mine(change: { [string]: any }?): any
			local trip = TrainController.parseTrip({ UserId = 7, PlotId = 2, DepartAt = DEPART, ArriveAt = ARRIVE, Count = 8 })
			for k, v in change or {} do
				trip[k] = v
			end
			return trip
		end
		T.eq(TrainController.parkedState(nil, nil, DEPART), "Away", "no snapshot yet")
		-- loading at the station
		local state, roll = TrainController.parkedState(snap({ Cargo = 3, Capacity = 8 }), nil, DEPART)
		T.eq(state, "Parked")
		T.eq(roll, nil, "simply standing there")
		-- on a trip or waiting at a full pen: never at the station (with or without its TrainTrip)
		local trips = {
			snap({ Moving = 8, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE }),
			snap({ Moving = 8, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE, Waiting = true }),
			snap({ Moving = 8, Capacity = 8 }),
			snap({ Moving = 0, Capacity = 8, Waiting = true }),
		}
		for i, train in trips do
			local t = DEPART - 5
			while t < ARRIVE + 400 do
				local known = TrainController.parkedState(train, mine(), t)
				T.eq(known, "Away", `snapshot {i} with its trip at {t}`)
				local unknown = TrainController.parkedState(train, nil, t)
				T.truthy(unknown ~= "Parked", `snapshot {i} without its trip at {t}`)
				t += 0.5
			end
		end
		-- the only exception: it just left and its TrainTrip hasn't come yet (the train standing there leaves)
		local leaving = trips[1]
		T.eq(TrainController.parkedState(leaving, nil, DEPART + 1), "Hold")
		T.eq(TrainController.parkedState(leaving, nil, DEPART + TrainController.HoldSeconds + 0.1), "Away", "not for long")
		T.eq(TrainController.parkedState(trips[2], nil, ARRIVE + 10), "Away", "a waiting train never holds")
		T.eq(TrainController.parkedState(trips[3], nil, DEPART + 1), "Away", "no times: away")
		-- a trip still rolling home from before is not the new departure
		local old = mine({ DepartAt = DEPART - 100, ArriveAt = DEPART - 70, UnloadAt = DEPART - 70 })
		T.eq(TrainController.parkedState(leaving, old, DEPART + 1), "Hold")
		-- unloaded: it backs into the station from rollInAt, parked when loading opens
		local returning = snap({ Moving = 0, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE })
		local from = TrainController.rollInAt(ARRIVE)
		T.eq(TrainController.parkedState(returning, nil, from - 0.1), "Away", "still on its way back")
		local back, rollFrom = TrainController.parkedState(returning, nil, from + 0.1)
		T.eq(back, "Parked")
		T.eq(rollFrom, from, "backing in")
		-- after a late unload this screen saw, the way back counts from that unload
		local unloaded = mine({ UnloadAt = ARRIVE + 50 })
		local late = snap({ Moving = 0, Capacity = 8, DepartAt = DEPART, ArriveAt = ARRIVE + 50 })
		T.eq(TrainController.parkedState(late, unloaded, TrainController.rollInAt(ARRIVE + 50) - 0.1), "Away")
		local home, lateRoll = TrainController.parkedState(late, unloaded, TrainController.rollInAt(ARRIVE + 50) + 0.1)
		T.eq(home, "Parked")
		T.eq(lateRoll, TrainController.rollInAt(ARRIVE + 50))
	end)

	---------------------------------------------------------------- HUD and panel

	T.test("TrainClient: HUD state text from snapshots", function()
		local now = 5000
		local function status(fields: { [string]: any }, autoLeft: number?): any
			return TrainView.status(TrainView.read(fields), now, autoLeft)
		end
		local empty = status({ Cargo = 0, Capacity = 8 })
		T.eq(empty.Phase, "Empty")
		T.eq(empty.Title, "TRAIN 0/8")
		T.eq(empty.Line, "Load ore at the Mine")
		T.falsy(empty.CanSend, "nothing to send")

		local loading = status({ Cargo = 6, Capacity = 8, AutoDepartIn = 18 })
		T.eq(loading.Title, "TRAIN 6/8")
		T.eq(loading.Phase, "Loading")
		T.eq(loading.Line, "Leaves in 0:18")
		T.eq(loading.Unit, "ore on board")
		T.truthy(loading.CanSend, "send early")
		T.near(loading.Fill, 0.75, 1e-9)
		T.eq(status({ Cargo = 6, Capacity = 8, AutoDepartIn = 18 }, 4.2).Line, "Leaves in 0:05", "counted down")
		T.eq(status({ Cargo = 2, Capacity = 8 }).Line, "Ready – Send!")

		local full = status({ Cargo = 8, Capacity = 8 })
		T.eq(full.Phase, "Full")
		T.eq(full.Line, "Full – Send!")
		T.truthy(full.CanSend)

		-- on its way: the count is the ore on board, not the (empty) station cargo
		local moving = status({ Cargo = 0, Capacity = 8, Moving = 8, DepartAt = now - 18, ArriveAt = now + 11.2 })
		T.eq(moving.Phase, "Moving")
		T.eq(moving.Title, "TRAIN 8/8")
		T.eq(moving.Unit, "ore on the way")
		T.eq(moving.Line, "On its way 0:12")
		T.falsy(moving.CanSend, "already away")
		T.near(moving.Progress, 18 / 29.2, 1e-9, "the chip's bar shows the trip")
		T.eq(loading.Progress, nil, "no trip bar at the station")
		-- just arrived, still loaded: unloading
		local unloading = status({ Moving = 8, Capacity = 8, DepartAt = now - 30, ArriveAt = now - 0.5 })
		T.eq(unloading.Phase, "Unloading")
		T.falsy(unloading.CanSend)
		-- the pen is full: the train waits at the stop
		local waiting = status({ Cargo = 0, Capacity = 8, Moving = 8, DepartAt = now - 60, ArriveAt = now - 30, Waiting = true })
		T.eq(waiting.Phase, "Waiting")
		T.eq(waiting.Line, "Pen full – make room")
		T.eq(waiting.Title, "TRAIN 8/8")
		T.eq(waiting.Unit, "ore waiting at your pen")
		T.eq(waiting.Color, Theme.Bad)
		T.falsy(waiting.CanSend, "can't send a train that is away")
		T.eq(waiting.Progress, nil, "no trip bar while it waits")
		-- the pen holds more than its capacity: the chip says why (the server's WaitReason)
		local over = status({
			Cargo = 0,
			Capacity = 8,
			Moving = 8,
			DepartAt = now - 60,
			ArriveAt = now - 30,
			Waiting = true,
			WaitReason = "PenOver",
		})
		T.eq(over.Phase, "Waiting")
		T.eq(over.Line, TrainView.PenOverLine, "over its limit")
		T.eq(over.Color, Theme.Bad)
		local full = status({
			Cargo = 0,
			Capacity = 8,
			Moving = 8,
			DepartAt = now - 60,
			ArriveAt = now - 30,
			Waiting = true,
			WaitReason = "PenFull",
		})
		T.eq(full.Line, TrainView.PenFullLine, "just full")
		T.eq(TrainView.read({ WaitReason = "Junk" }).WaitReason, nil, "junk reasons are ignored")
		T.eq(status({ Moving = 5, Capacity = 8, DepartAt = now - 60, ArriveAt = now - 5 }).Phase, "Waiting", "still loaded long after")
		T.eq(status({ Moving = 3, Capacity = 8, Waiting = true }).Phase, "Waiting", "Waiting alone")
		-- the boundary: just before ArriveAt + UnloadGrace it is still unloading, at it it waits
		local arrived = { Moving = 8, Capacity = 8, DepartAt = now - 60, ArriveAt = now - TrainView.UnloadGrace }
		local function at(t: number, fields: { [string]: any }?): (boolean, string)
			local snap = TrainView.read(fields or arrived)
			return TrainView.waiting(snap, t), TrainView.status(snap, t).Phase
		end
		local before, beforePhase = at(now - 0.01)
		T.falsy(before, "UnloadGrace - 0.01 s after the arrival: not waiting yet")
		T.eq(beforePhase, "Unloading")
		local exact, exactPhase = at(now)
		T.truthy(exact, "exactly UnloadGrace after the arrival: waiting")
		T.eq(exactPhase, "Waiting")
		local flagged, flaggedPhase = at(now - 1000, { Moving = 3, Capacity = 8, Waiting = true })
		T.truthy(flagged, "the server's Waiting without ArriveAt")
		T.eq(flaggedPhase, "Waiting")
		T.falsy(TrainView.waiting(TrainView.read({ Moving = 3, Capacity = 8 }), now + 1000), "no ArriveAt, no Waiting: on its way")
		T.falsy(TrainView.waiting(TrainView.read({ Moving = 0, Capacity = 8, ArriveAt = now - 100 }), now), "nothing on board")
		T.truthy(TrainView.waiting(TrainView.read({ Moving = 0, Capacity = 8, Waiting = true }), now), "the server's word")
		-- (a snapshot that also shows station cargo) nothing can be sent while it waits
		local stocked = status({ Cargo = 8, Capacity = 8, Moving = 4, DepartAt = now - 60, ArriveAt = now - 30, Waiting = true })
		T.eq(stocked.Phase, "Waiting")
		T.eq(stocked.Title, "TRAIN 4/8", "counts the ore on board")
		T.falsy(stocked.CanSend)
		-- rolling back empty, then home
		local back = status({ Cargo = 0, Capacity = 8, DepartAt = now - 31, ArriveAt = now - 1 })
		T.eq(back.Phase, "Returning")
		T.eq(back.Line, "Returning")
		T.eq(back.Title, "TRAIN 0/8")
		T.falsy(back.CanSend, "still away")
		local late = status({ Cargo = 0, Capacity = 8, DepartAt = now - 90, ArriveAt = now - 2 })
		T.eq(late.Phase, "Returning", "after a late unload ArriveAt is the unload")
		local home = status({ Cargo = 3, Capacity = 8, DepartAt = now - 60, ArriveAt = now - 30 })
		T.eq(home.Phase, "Loading", "an old trip doesn't count")

		-- junk snapshots fall back to safe values
		local junk =
			TrainView.read({ Cargo = 0 / 0, Capacity = "8", CapacityLevel = -3, ArriveAt = math.huge, Express = "yes", Waiting = 1 })
		T.eq(junk.Cargo, 0)
		T.eq(junk.Capacity, TrainConfig.capacity(0, false))
		T.eq(junk.CapacityLevel, 0)
		T.eq(junk.ArriveAt, nil)
		T.eq(junk.Express, false)
		T.eq(junk.Waiting, false)
		T.eq(TrainView.read(nil).TripSeconds, TrainConfig.tripSeconds(0, false))
	end)

	T.test("TrainClient: upgrade rows show the next level and its price", function()
		local train = TrainView.read({ Cargo = 0, Capacity = 8, CapacityLevel = 0, SpeedLevel = 0 })
		local capacity = TrainView.upgrade(train, "Capacity", 2000)
		T.eq(capacity.Detail, "Cargo 8 → 15")
		T.eq(capacity.LevelText, "LV 1/10")
		T.eq(capacity.PriceText, "$2K")
		T.truthy(capacity.CanBuy, "affordable")
		T.falsy(TrainView.upgrade(train, "Capacity", 1999).CanBuy, "too expensive")
		local speed = TrainView.upgrade(train, "Speed", 0)
		T.eq(speed.Detail, "Trip 30 s → 25 s")
		T.eq(speed.PriceText, "$3K")
		-- the snapshot's price wins (the server knows best)
		local priced = TrainView.read({ CapacityLevel = 1, NextCapacityPrice = 12345 })
		T.eq(TrainView.upgrade(priced, "Capacity", 0).Price, 12345)
		-- maxed
		local top = TrainView.read({ CapacityLevel = 9, SpeedLevel = 5 })
		local maxed = TrainView.upgrade(top, "Capacity", 1e12)
		T.truthy(maxed.Maxed)
		T.eq(maxed.PriceText, "MAX")
		T.falsy(maxed.CanBuy)
		T.eq(maxed.Detail, "Cargo 1000 (max)")
		-- Express: +50 % cargo and half the trip
		local express = TrainView.read({ CapacityLevel = 0, SpeedLevel = 0, Express = true })
		T.eq(TrainView.upgrade(express, "Capacity", 0).Detail, "Cargo 12 → 22")
		T.eq(TrainView.upgrade(express, "Speed", 0).Detail, "Trip 15 s → 12.5 s")
	end)

	---------------------------------------------------------------- presses ahead of the server

	T.test("TrainClient: SEND says Leaving… at once; a stale snapshot never unlocks it", function()
		local now, clock = 5000, 100
		-- the cargo at the station (the last trip long done)
		local parked = TrainView.read({ Cargo = 6, Capacity = 8, AutoDepartIn = 18, DepartAt = now - 90, ArriveAt = now - 60 })
		local before, none = TrainController.sendStatus(parked, nil, clock, now, nil)
		T.eq(before.Phase, "Loading")
		T.truthy(before.CanSend)
		T.eq(none, nil)
		local press = { At = clock, Server = now, Count = 6 }
		-- right after the press: the snapshot still has the cargo at the station (it left the
		-- server before the press got there), the chip already says Leaving…
		local leaving, kept = TrainController.sendStatus(parked, press, clock + 0.1, now + 0.1, nil)
		T.eq(kept, press, "the press still counts")
		T.eq(leaving.Line, TrainController.LeavingLine)
		T.eq(leaving.Phase, "Moving", "SEND again says it is on its way")
		T.eq(leaving.Title, "TRAIN 6/8")
		T.eq(leaving.Unit, "ore on the way")
		T.eq(leaving.Progress, 0, "the trip bar at its start")
		T.near(leaving.Fill, 0.75, 1e-9)
		T.falsy(leaving.CanSend, "no second SEND")
		-- that stale snapshot neither unlocks SEND nor ends Leaving…
		T.falsy(TrainController.sendShown(parked, press), "stale: the cargo is still at the station")
		T.falsy(TrainController.sendShown(parked, nil))
		T.falsy(
			TrainController.sendShown(TrainView.read({ Cargo = 2, Capacity = 8, DepartAt = now - 40, ArriveAt = now - 10 }), press),
			"an old trip"
		)
		-- snapshots that show the send
		local away = TrainView.read({ Cargo = 0, Capacity = 8, Moving = 6, DepartAt = now + 0.05, ArriveAt = now + 30.05 })
		T.truthy(TrainController.sendShown(away, press), "on its way")
		local after, gone = TrainController.sendStatus(away, press, clock + 0.2, now + 0.2, nil)
		T.eq(gone, nil, "the press is over")
		T.eq(after.Phase, "Moving")
		T.eq(after.Line, "On its way 0:30")
		T.truthy(TrainController.sendShown(TrainView.read({ Cargo = 0, Capacity = 8 }), press), "the cargo left")
		T.truthy(TrainController.sendShown(TrainView.read({ Cargo = 3, Capacity = 8, Moving = 3, Waiting = true }), press), "waiting")
		local departed = TrainView.read({ Cargo = 2, Capacity = 8, DepartAt = now + 0.1, ArriveAt = now + 30 })
		T.truthy(TrainController.sendShown(departed, press), "departed at or after the press")
		T.falsy(TrainController.sendShown(departed, nil), "(that one needs the press)")
		-- no snapshot ever shows it (refused, dropped): back to the snapshot after SendPendingSeconds
		local still = TrainController.sendStatus(parked, press, clock + TrainController.SendPendingSeconds - 0.01, now + 1.99, nil)
		T.eq(still.Line, TrainController.LeavingLine, "still leaving")
		local back, over = TrainController.sendStatus(parked, press, clock + TrainController.SendPendingSeconds, now + 2, nil)
		T.eq(over, nil, "given up")
		T.eq(back.Phase, "Loading", "the snapshot again")
		T.truthy(back.CanSend)
		-- a clock that went back (a junk press) is dropped too
		T.eq(select(2, TrainController.sendStatus(parked, press, clock - 1, now, nil)), nil)
	end)

	T.test("TrainClient: your TrainTrip fills in the trip bar before the State push", function()
		local now = 5000
		local parked =
			TrainView.read({ Cargo = 6, Capacity = 8, AutoDepartIn = 10, DepartAt = now - 90, ArriveAt = now - 60, CapacityLevel = 1 })
		local trip = TrainController.parseTrip({
			UserId = 1,
			PlotId = 3,
			DepartAt = now - 0.1,
			ArriveAt = now + 29.9,
			Count = 6,
			Color = RED,
			Load = {},
		})
		local filled = TrainController.tripSnapshot(parked, trip, now)
		T.truthy(filled, "a new departure")
		T.eq(filled.Moving, 6, "the ore on board")
		T.eq(filled.Cargo, 0, "the station cargo left with it")
		T.eq(filled.DepartAt, trip.DepartAt)
		T.eq(filled.ArriveAt, trip.ArriveAt)
		T.eq(filled.AutoDepartIn, nil)
		T.eq(filled.CapacityLevel, 1, "the rest stays")
		T.eq(parked.Cargo, 6, "a copy: the snapshot is not changed")
		local chip = TrainView.status(filled, now, nil)
		T.eq(chip.Phase, "Moving")
		T.eq(chip.Title, "TRAIN 6/8")
		T.near(chip.Progress, 0.1 / 30, 1e-9, "the trip bar runs from the departure")
		T.truthy(TrainController.sendShown(filled, { At = 0, Server = now - 0.2, Count = 6 }), "it ends Leaving…")
		-- nothing to fill in
		T.eq(TrainController.tripSnapshot(filled, trip, now), nil, "the snapshot has it")
		local waiting = table.clone(trip)
		waiting.Waiting = true
		T.eq(TrainController.tripSnapshot(parked, waiting, now), nil, "a Waiting announcement")
		local old = TrainController.parseTrip({ UserId = 1, PlotId = 3, DepartAt = now - 90, ArriveAt = now - 60, Count = 6 })
		T.eq(TrainController.tripSnapshot(parked, old, now), nil, "the trip the snapshot knows")
		T.eq(TrainController.tripSnapshot(parked, trip, trip.ArriveAt), nil, "already arrived")
		local standing = TrainView.read({ Cargo = 0, Capacity = 8, Moving = 6, DepartAt = now - 90, ArriveAt = now - 60, Waiting = true })
		T.eq(TrainController.tripSnapshot(standing, trip, now), nil, "the ore is still on board (a late unload)")
		-- the first trip of a session (no DepartAt yet)
		T.truthy(TrainController.tripSnapshot(TrainView.read({ Cargo = 6, Capacity = 8 }), trip, now), "the first trip")
	end)

	T.test("TrainClient: BUY shows its level at once and a double click buys one level", function()
		local train = TrainView.read({ Capacity = 8, CapacityLevel = 0, SpeedLevel = 0 })
		local buys: any = { Capacity = {}, Speed = {} }
		local p1 = TrainConfig.nextPrice(TrainConfig.Capacity, 0)
		local p2 = TrainConfig.nextPrice(TrainConfig.Capacity, 1)
		local coins = p1 + p2 + 5
		local clock = 100
		T.truthy(TrainController.buyOpen(buys, "Capacity", nil, clock), "the first click goes")
		local info, level = TrainController.buyPlan(train, buys, "Capacity", coins)
		T.eq(level, 1, "the card's level")
		T.truthy(info.CanBuy)
		table.insert(buys.Capacity, { Level = level, Price = info.Price, At = clock })
		-- the panel at once: the next level, its price and the coins less the first price
		local shown, spend = TrainController.pendingView(train, buys)
		T.eq(shown.CapacityLevel, 1)
		T.eq(spend, p1)
		T.eq(shown.NextCapacityPrice, p2)
		T.eq(shown.Capacity, TrainConfig.capacity(1, false))
		T.eq(TrainView.upgrade(shown, "Capacity", coins - spend).LevelText, "LV 2/10")
		T.eq(train.CapacityLevel, 0, "the snapshot itself is not changed")
		T.eq(shown.SpeedLevel, 0, "speed on its own")
		-- the second click 0.2 s later (a double click, a gamepad bounce): nothing more is bought
		T.falsy(TrainController.buyOpen(buys, "Capacity", clock, clock + 0.2), "a double click buys one level (SECURITY_AUDIT #7)")
		T.truthy(TrainController.buyOpen(buys, "Speed", nil, clock + 0.2), "speed counts on its own")
		local speedInfo, speedLevel = TrainController.buyPlan(train, buys, "Speed", p1)
		T.eq(speedLevel, 1)
		T.falsy(speedInfo.CanBuy, "with the coins the capacity click left")
		-- the snapshot shows the first buy: "BOUGHT!" over, the next click buys level 2
		local after1 = TrainView.read({ Capacity = 12, CapacityLevel = 1, NextCapacityPrice = p2 })
		TrainController.pruneBuys(buys, after1, clock + 0.3)
		T.eq(#buys.Capacity, 0)
		T.falsy(TrainController.buyOpen(buys, "Capacity", clock, clock + 0.3), "still BOUGHT!")
		T.truthy(TrainController.buyOpen(buys, "Capacity", clock, clock + TrainController.BoughtSeconds + 0.01), "then a deliberate click")
		local info2, level2 = TrainController.buyPlan(after1, buys, "Capacity", coins - p1)
		T.eq(level2, 2, "the level after the first")
		T.truthy(info2.CanBuy)
		T.eq(info2.Price, p2)
		table.insert(buys.Capacity, { Level = level2, Price = info2.Price, At = clock + 1 })
		-- the second level waits for its own snapshot
		TrainController.pruneBuys(buys, after1, clock + 1.1)
		T.eq(#buys.Capacity, 1)
		shown, spend = TrainController.pendingView(after1, buys)
		T.eq(shown.CapacityLevel, 2)
		T.eq(spend, p2)
		-- after the second: nothing clicked ahead, the snapshot speaks
		local after2 = TrainView.read({ CapacityLevel = 2 })
		TrainController.pruneBuys(buys, after2, clock + 1.2)
		T.eq(#buys.Capacity, 0)
		shown, spend = TrainController.pendingView(after2, buys)
		T.eq(shown, after2, "no copy without clicked levels")
		T.eq(spend, 0)
		-- no snapshot ever has it: gone after BuyPendingSeconds, with every level clicked after it
		buys.Speed = { { Level = 1, Price = 3000, At = clock }, { Level = 2, Price = 6000, At = clock + 1.5 } }
		TrainController.pruneBuys(buys, train, clock + TrainController.BuyPendingSeconds - 0.01)
		T.eq(#buys.Speed, 2, "still shown")
		TrainController.pruneBuys(buys, train, clock + TrainController.BuyPendingSeconds)
		T.eq(#buys.Speed, 0, "the first ran out, the second counted on it")
		-- refused (TrainResult): that level and the ones clicked after it go
		buys.Capacity = { { Level = 1, Price = p1, At = clock }, { Level = 2, Price = p2, At = clock } }
		TrainController.dropBuys(buys.Capacity, 2)
		T.eq(#buys.Capacity, 1)
		T.eq(buys.Capacity[1].Level, 1, "the level before it stays")
		TrainController.dropBuys(buys.Capacity, 1)
		T.eq(#buys.Capacity, 0)
		-- the clicked top level: the card says MAX at once
		local top = TrainConfig.maxLevel(TrainConfig.Capacity)
		buys.Capacity = { { Level = top, Price = 1, At = clock } }
		T.truthy(TrainController.buyPlan(TrainView.read({ CapacityLevel = top - 1 }), buys, "Capacity", 1e12).Maxed, "maxed")
	end)

	T.test("TrainClient: clicks over TrainAction's rate limit are caught here, never dropped by the server", function()
		local limit = Net.Events.TrainAction
		T.eq(TrainController.ClickRate, limit.Rate, "the server's rate")
		T.lt(TrainController.ClickBurst, limit.Burst, "a little under the server's burst")
		local budget = { Tokens = TrainController.ClickBurst, Last = 0 }
		local passed = 0
		for _ = 1, 10 do
			if TrainController.takeClick(budget, 0) then
				passed += 1
			end
		end
		T.eq(passed, TrainController.ClickBurst, "a burst, then no more")
		T.falsy(TrainController.takeClick(budget, 0.1), "too soon")
		T.truthy(TrainController.takeClick(budget, 0.1 + 1 / limit.Rate), "one more a moment later")
		-- whatever the pace (a mashing player), the server's bucket takes every click this one lets
		-- through, even when they reach it a little bunched up
		local client = { Tokens = TrainController.ClickBurst, Last = 0 }
		local server = { Tokens = limit.Burst, Last = 0 }
		local t, sent, dropped = 0, 0, 0
		for i = 1, 400 do
			t += ((i * 7919) % 13) / 40 -- 0 .. 0.3 s apart
			if TrainController.takeClick(client, t) then
				sent += 1
				local arrive = t + ((i * 31) % 5) / 100 -- 0 .. 40 ms of jitter on the way
				server.Tokens = math.min(limit.Burst, server.Tokens + math.max(0, arrive - server.Last) * limit.Rate)
				server.Last = math.max(server.Last, arrive)
				if server.Tokens >= 1 then
					server.Tokens -= 1
				else
					dropped += 1
				end
			end
		end
		T.lt(100, sent, "most clicks go")
		T.eq(dropped, 0, "the server drops none of them")
	end)

	T.test("TrainClient: TrainView builds with the right children", function()
		local refs = TrainView.build()
		T.eq(refs.Chip.Name, "TerraForgeTrain")
		T.eq(refs.Gui.Name, "TerraForgeTrainPanel")
		for _, gui in { refs.Chip, refs.Gui } do
			T.eq(gui:GetAttribute("TerraForge"), true, gui.Name .. " is scaled by HudController")
			T.truthy(gui:FindFirstChild("Scale"), gui.Name .. " has a UIScale")
		end
		T.eq(refs.Gui.Enabled, false, "the panel starts closed")
		local chip = refs.Chip:FindFirstChild("TrainChip")
		T.truthy(chip, "chip")
		for _, name in { "Open", "TrainIcon", "Title", "Line", "Bar", "SendHolder", "Key", "Glyph" } do
			T.truthy(chip:FindFirstChild(name), "chip has " .. name)
		end
		T.truthy(refs.ChipOpen:IsA("TextButton"), "the chip opens the panel")
		T.eq(refs.ChipSend.Text, "SEND")
		local panel = refs.Gui:FindFirstChild("Panel")
		for _, name in { "Title", "Subtitle", "CloseHolder", "Card", "Rows", "Hint" } do
			T.truthy(panel:FindFirstChild(name), "panel has " .. name)
		end
		for _, name in { "Label", "TrainIcon", "Cargo", "Unit", "Bar", "State", "Trip", "SendHolder" } do
			T.truthy(refs.Card:FindFirstChild(name), "cargo card has " .. name)
		end
		local rows = panel:FindFirstChild("Rows")
		for _, name in { "CAPACITY", "SPEED", "EXPRESS TRAIN" } do
			local row = rows:FindFirstChild(name)
			T.truthy(row, "row " .. name)
			for _, child in { "ItemName", "Level", "Detail", "Price", "BuyHolder" } do
				T.truthy(row:FindFirstChild(child), name .. " has " .. child)
			end
		end
		T.eq(refs.Express.Buy.Text, "SOON", "Express is a placeholder")
		T.eq(refs.Express.Price.Text, `{TrainView.ExpressPrice} R$`)
		-- the chip sits under the coins panel, clear of its "+$X" popups
		T.le(16 + 74 + 40, refs.ChipFrame.Position.Y.Offset, "under the coins")
		T.eq(refs.ChipFrame.Position.X.Offset, 16, "lined up with the coins")

		-- filling in
		local train = TrainView.read({ Cargo = 8, Capacity = 8, CapacityLevel = 1, SpeedLevel = 0 })
		TrainView.setStatus(refs, TrainView.status(train, 0, nil))
		T.eq(refs.ChipTitle.Text, "TRAIN 8/8")
		T.eq(refs.ChipLine.Text, "Full – Send!")
		T.eq(refs.Cargo.Text, "8 / 8")
		T.eq(refs.CargoUnit.Text, "ore on board")
		T.eq(refs.ChipSend.BackgroundColor3, Theme.Good, "SEND lights up")
		T.eq(refs.ChipFill.Size.X.Scale, 1)
		TrainView.setUpgrades(refs, train, 100)
		T.eq(refs.Rows.Capacity.Detail.Text, "Cargo 15 → 30")
		T.eq(refs.Rows.Capacity.Buy.BackgroundColor3, Theme.PanelLight, "can't afford: greyed")
		T.eq(refs.Rows.Speed.Price.Text, "$3K")
		TrainView.setStatus(refs, TrainView.status(TrainView.read({ Cargo = 0, Capacity = 8 }), 0, nil))
		T.eq(refs.ChipSend.BackgroundColor3, Theme.PanelLight, "empty: SEND greyed")
		local penFull = TrainView.status(TrainView.read({ Moving = 6, Capacity = 8, Waiting = true }), 0, nil)
		TrainView.setStatus(refs, penFull)
		T.eq(refs.ChipLine.Text, "Pen full – make room")
		T.eq(refs.Cargo.Text, "6 / 8", "the ore still on the train")
		T.eq(refs.CargoUnit.Text, "ore waiting at your pen")
		T.eq(refs.ChipFill.BackgroundColor3, Theme.Bad)
		local blue = Color3.fromRGB(60, 140, 220)
		TrainView.setColor(refs, blue)
		local bodies = 0
		for _, child in refs.ChipIcon:GetChildren() do
			if child.Name == "Body" then
				T.eq(child.BackgroundColor3, blue, "banner color")
				bodies += 1
			end
		end
		T.eq(bodies, 2, "boiler and cab")
	end)

	-- a gui object's size in design units (scale sizes resolved against the parents)
	local function absolute(gui: any): (number, number)
		local size = gui.Size
		local w, h = size.X.Offset, size.Y.Offset
		if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
			local pw, ph = absolute(gui.Parent)
			w += pw * size.X.Scale
			h += ph * size.Y.Scale
		end
		return w, h
	end

	-- a phone screen in points (landscape) -> the compact layout fitted to it
	local function phone(widthPt: number, heightPt: number): (any, number, number)
		local scale = TrainView.PhoneScale
		local width, height = widthPt / scale, (heightPt - 58) / scale
		local refs = TrainView.build(true)
		TrainView.layout(refs, true, width, height)
		return refs, width, height
	end

	T.test("TrainClient: phone layout keeps every touch target >= 44 pt", function()
		local scale = TrainView.PhoneScale
		-- an iPhone SE (2nd gen) and the small 568 x 320 phones
		for _, screen in { { 667, 375 }, { 568, 320 } } do
			local label = `{screen[1]}x{screen[2]}`
			local refs, width, height = phone(screen[1], screen[2])
			T.truthy(refs.Compact, "compact")
			for _, target in TrainView.touchTargets(refs) do
				local w, h = absolute(target)
				T.le(TrainView.MinTouch, h * scale, label .. " " .. target.Name .. " tall enough")
				T.le(TrainView.MinTouch, w * scale, label .. " " .. target.Name .. " wide enough")
			end
			-- the panel fits the screen and the rows fit the panel
			local panel = refs.Panel.Size
			T.le(panel.X.Offset, width, label .. " panel width")
			T.le(panel.Y.Offset, height, label .. " panel height")
			local rows = refs.Rows.Capacity.Frame.Parent
			T.le(rows.Position.Y.Offset + rows.Size.Y.Offset, panel.Y.Offset, label .. " rows inside (the Express row too)")
			for _, row in { refs.Rows.Capacity, refs.Rows.Speed, refs.Express } do
				local rowHeight = row.Frame.Size.Y.Offset
				local buy = row.Buy.Parent
				T.le(buy.Position.Y.Offset + buy.Size.Y.Offset, rowHeight + 3.01, label .. " BUY inside its row")
				-- the name fits next to its level chip ("CAPACITY" in the title font ~ 0.62 x size per letter)
				local nameW = absolute(row.Name)
				T.le(#row.Name.Text * row.Name.TextSize * 0.62, nameW, label .. " " .. row.Name.Text .. " has room")
				local chipLeft = 0
				if row.Level.Visible then
					local rowW = absolute(row.Frame)
					chipLeft = rowW + row.Level.Position.X.Offset - row.Level.Size.X.Offset
					T.le(row.Name.Position.X.Offset + nameW, chipLeft + 0.01, label .. " name clear of the level chip")
				end
			end
			T.falsy(refs.Subtitle.Visible, "no subtitle on phones")
			-- the chip stays on the left of the screen, under the coins (and hides behind the open panel)
			T.le((refs.ChipFrame.Position.X.Offset + refs.ChipFrame.Size.X.Offset) * scale, screen[1] * 0.7, label .. " chip width")
		end
		local roomy = phone(844, 390)
		T.truthy(roomy.Trip.Visible, "a roomier phone has a line for the trip time")
		T.le((roomy.Trip.TextSize + 4), roomy.Trip.Size.Y.Offset, "...that fits")
		TrainView.setUpgrades(roomy, TrainView.read({ TripSeconds = 25 }), 0)
		T.eq(roomy.Trip.Text, "Trip 25 s to your base.", "one short line on phones")
		T.falsy(TrainView.chipVisible(true, true), "the chip hides behind the open panel (PC and phones)")
		T.truthy(TrainView.chipVisible(true, false), "shown with the HUD")
		T.falsy(TrainView.chipVisible(false, false), "hidden with the HUD")
		-- desktop: still comfortable to click, and the panel fits a 720p screen
		local refs = TrainView.build(false)
		TrainView.layout(refs, false, 1280, 720 - 36)
		for _, target in TrainView.touchTargets(refs) do
			local _, h = absolute(target)
			T.le(40, h, target.Name .. " on desktop")
		end
		T.le(refs.Panel.Size.Y.Offset, 720 - 36, "fits 720p")
		T.eq(refs.Rows.Capacity.Frame.Size.Y.Offset, 100, "full rows on desktop")
		T.falsy(refs.CoversCoins, "the PC panel stays clear of the HUD coins")
	end)

	T.test("TrainClient: the phone panel never cuts the coins or the backpack button", function()
		local scale = TrainView.PhoneScale
		local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
		-- the HUD's backpack button (bottom, right of the blaster's hotbar slot; the phone size)
		local pack = HudBubble.BackpackSizePhone
		local packRight = HudBubble.backpackX(scale) + pack.X
		for _, screen in { { 667, 375 }, { 812, 375 }, { 844, 390 }, { 800, 360 }, { 568, 320 } } do
			local label = `{screen[1]}x{screen[2]}`
			local refs, width, height = phone(screen[1], screen[2])
			local panel = refs.Panel
			T.eq(panel.AnchorPoint, roblox.Vector2.new(0.5, 1), label .. " at the bottom of the screen")
			local bottom = height + panel.Position.Y.Offset
			local top = bottom - panel.Size.Y.Offset
			T.le(0, top, label .. " inside the screen")
			-- the backpack button lies under the panel
			T.le(height - HudBubble.BackpackBottom, bottom, label .. " covers the backpack button's bottom")
			T.le(top, height - HudBubble.BackpackBottom - pack.Y, label .. " ...and its top")
			T.le(2 * packRight, panel.Size.X.Offset, label .. " ...and its right end")
			-- the HUD coins (16..90): either fully clear, or the panel says it covers them (they hide)
			if refs.CoversCoins then
				T.lt(top, 90, label .. " covers the coins")
			else
				T.le(TrainView.CoinsBottom, top, label .. " clear of the coins")
			end
			-- your coins are in the header either way, clear of the title
			local balance = refs.Balance
			T.truthy(balance.Visible, label .. " coins in the header")
			local titleRight = refs.Title.Position.X.Offset + panel.Size.X.Offset + refs.Title.Size.X.Offset
			local balanceLeft = panel.Size.X.Offset + balance.Position.X.Offset - balance.Size.X.Offset
			T.le(titleRight, balanceLeft, label .. " title clear of the coins")
			T.le(TrainView.MinTouch, absolute(refs.Close.Parent) * scale, label .. " close stays big")
		end
		-- the common phones keep the HUD coins in sight; only the smallest (320 pt) covers them
		T.falsy((phone(667, 375)).CoversCoins, "667x375: coins stay visible")
		T.truthy((phone(568, 320)).CoversCoins, "568x320: covered, so they hide while it is open")
	end)

	T.test("TrainClient: the panel keeps a gamepad selection and shows your coins", function()
		local refs = TrainView.build(false)
		T.eq(refs.Panel.SelectionGroup, true, "a selection group")
		for _, side in { "Up", "Down", "Left", "Right" } do
			T.eq(refs.Panel["SelectionBehavior" .. side], roblox.Enum.SelectionBehavior.Stop, "stops at the " .. side .. " edge")
		end
		TrainView.setCoins(refs, 12480)
		T.eq(refs.BalanceAmount.Text, "$12.5K")
		TrainView.setCoins(refs, -5)
		T.eq(refs.BalanceAmount.Text, "$0", "never negative")
		T.truthy(refs.Panel:FindFirstChild("Balance"), "the header's coins")
		T.truthy(refs.Balance:FindFirstChild("CoinIcon"), "with the HUD's coin icon")
	end)

	T.test("TrainClient: train sounds and the panel prompt", function()
		-- the sounds ship with every Roblox client (content/sounds) or are uploaded ids
		local shipped = {
			["rbxasset://sounds/action_falling.ogg"] = true,
			["rbxasset://sounds/action_footsteps_plastic.mp3"] = true,
			["rbxasset://sounds/action_get_up.mp3"] = true,
			["rbxasset://sounds/action_jump.mp3"] = true,
			["rbxasset://sounds/action_jump_land.mp3"] = true,
			["rbxasset://sounds/action_swim.mp3"] = true,
			["rbxasset://sounds/impact_explosion_03.mp3"] = true,
			["rbxasset://sounds/impact_water.mp3"] = true,
			["rbxasset://sounds/volume_slider.ogg"] = true,
		}
		for _, name in { "TrainChuff", "TrainWhistle" } do
			local def = SoundConfig[name]
			T.truthy(def, name)
			T.truthy(shipped[def.Id] or string.sub(def.Id, 1, 13) == "rbxassetid://", name .. " plays in today's clients")
			T.le(def.Pitch[1], def.Pitch[#def.Pitch], name .. " pitch range")
		end
		-- the "Train" prompt sits in TrainService's slot 2, under Load (0) and Send (1), at the same range
		T.eq(TrainController.PromptSlot * TrainController.PromptSlotHeight, 144)
		T.eq(TrainController.PromptDistance, 10)
	end)

	T.test("TrainClient: the prompt numbers are TrainService's (one TrainConfig for both sides)", function()
		local TrainService = Loader.requirePath("ServerScriptService.Server.Services.TrainService")
		T.eq(TrainController.PromptTag, TrainConfig.PromptTag, "the tag")
		T.eq(TrainService.PromptTag, TrainConfig.PromptTag)
		T.eq(TrainController.PromptSlotHeight, TrainService.PromptSlotHeight, "the slot step")
		T.eq(TrainController.PromptSlot, TrainService.PromptSlots.Panel, "the panel's slot")
		T.eq(TrainController.MaxTripSpan, TrainService.MaxTripSpan, "the longest trip clients accept")
		T.eq(TrainService.MaxTripSpan, TrainConfig.MaxTripSpan)
		-- every slot its own offset
		local seen = {}
		for name, slot in TrainConfig.PromptSlots do
			T.truthy(seen[slot] == nil, name .. " has a slot of its own")
			seen[slot] = name
		end
		-- your snapshot trip comes before the departing train's hold ends (the 4 Hz sync has time)
		T.lt(TrainController.SnapshotTripGrace, TrainController.HoldSeconds - 0.25)
		T.lt(0, TrainController.SnapshotTripGrace)
	end)

	T.test("TrainClient: the panel prompt keeps slot 2 and Load shows only with full hands (TrainService's real prompts)", function()
		local Vector2 = roblox.Vector2
		local Enum = roblox.Enum
		local CFrame = Loader.CFrame
		local TrainService = Loader.requirePath("ServerScriptService.Server.Services.TrainService")
		local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
		-- a Mine Station as Railway builds it (the WORLD contract), set up by the real TrainService
		local s = TrainConfig.Station
		local station = Instance.new("Model")
		station.Name = "MineStation"
		station:AddTag("TrainStation")
		local platform = Instance.new("Part")
		platform.Name = "Platform"
		platform.Anchored = true
		platform.Size = s.Platform.Size
		platform.CFrame = CFrame.new(s.Platform.Center)
		platform.Parent = station
		local point = Instance.new("Attachment")
		point.Name = "PromptPoint"
		point.CFrame = platform.CFrame:ToObjectSpace(CFrame.new(s.PromptPoint))
		point.Parent = platform
		local intake = Instance.new("Part")
		intake.Name = "Intake"
		intake.Anchored = true
		intake.Size = s.HopperSize
		intake.CFrame = CFrame.new(s.Hopper + Vector3.new(0, s.HopperSize.Y / 2, 0))
		intake:AddTag("TrainHopper")
		intake.Parent = station
		-- (no intake zone or hook is left behind for the other specs)
		local addZone = rawget(IntakeService, "addZone")
		rawset(IntakeService, "addZone", function() end)
		TrainService._test.reset()
		local ok, err = pcall(TrainService._test.setupHook, intake)
		rawset(IntakeService, "addZone", addZone)
		TrainService._test.reset()
		if not ok then
			error(err, 0)
		end
		local load = point:FindFirstChild("TrainLoadPrompt")
		local send = point:FindFirstChild("TrainSendPrompt")
		T.truthy(load and send, "the server's two prompts")
		local panel = TrainController.makePanelPrompt("Mine Station")
		panel.Parent = point
		T.eq(panel.Name, "TrainPanelPrompt", "its own name")
		T.truthy(panel.Name ~= load.Name and panel.Name ~= send.Name, "never one of the server's names")
		T.eq(panel.UIOffset, Vector2.new(0, 144), "slot 2")
		local prompts = 0
		for _, other in point:GetChildren() do
			if other:IsA("ProximityPrompt") and other ~= panel then
				prompts += 1
				T.truthy(other:HasTag(TrainController.PromptTag), other.Name .. " carries the client's tag")
				T.truthy(other.UIOffset ~= panel.UIOffset, other.Name .. " never at the panel's offset")
				T.truthy(math.abs(panel.UIOffset.Y - other.UIOffset.Y) >= 72, "a full slot away from " .. other.Name)
				T.truthy(other.KeyboardKeyCode ~= panel.KeyboardKeyCode, other.Name .. " has another key")
				T.truthy(other.GamepadKeyCode ~= panel.GamepadKeyCode, other.Name .. " has another button")
			end
		end
		T.eq(prompts, 2, "only Load and Send are the server's")
		T.eq(load:GetAttribute("Action"), "Load")
		T.eq(send:GetAttribute("Action"), "Send")
		T.falsy(panel:HasTag(TrainController.PromptTag), "not one of the server's tagged prompts")
		T.eq(panel:GetAttribute("Action"), nil)
		local PromptConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.PromptConfig")
		T.eq(panel.KeyboardKeyCode, Enum.KeyCode.T, "T opens the panel (E / G are Load / Send)")
		T.eq(panel.GamepadKeyCode, Enum.KeyCode.ButtonL3, "L3 (Y / B are Load / Send)")
		T.eq(panel.KeyboardKeyCode, PromptConfig.Keys.Panel.Keyboard, "PromptConfig's Panel role")
		T.eq(panel.GamepadKeyCode, PromptConfig.Keys.Panel.Gamepad)
		T.eq(load.KeyboardKeyCode, PromptConfig.Keys.Main.Keyboard, "Load is the Main role (E)")
		T.eq(send.KeyboardKeyCode, PromptConfig.Keys.Second.Keyboard, "Send is the Second role (G)")
		T.eq(panel.UIOffset, Vector2.new(0, 2 * PromptConfig.SlotHeight), "slot 2 in PromptConfig's step")
		T.eq(panel.Style, Enum.ProximityPromptStyle.Default, "the stock Roblox prompt")
		T.eq(panel.ObjectText, "Mine Station")
		T.eq(panel.MaxActivationDistance, TrainController.PromptDistance)
		T.eq(panel.MaxActivationDistance, load.MaxActivationDistance, "the same range as the server's")
		-- Load: only while the backpack holds something the train takes (TrainController.canLoad:
		-- anything but a dusty relic; tests/BackpackClient.spec checks the rule)
		T.truthy(load.Enabled, "the server leaves it on")
		T.truthy(TrainController.applyLoadPrompt(load, false), "a Load prompt")
		T.falsy(load.Enabled, "an empty backpack")
		TrainController.applyLoadPrompt(load, true)
		T.truthy(load.Enabled, "ore in the backpack")
		TrainController.applyLoadPrompt(load, false)
		T.falsy(load.Enabled, "loaded")
		TrainController.applyLoadPrompt(load, nil)
		T.falsy(load.Enabled, "nothing known yet")
		TrainController.applyLoadPrompt(load, "3")
		T.falsy(load.Enabled, "junk is nothing to load")
		-- everything else is left alone, whatever the backpack holds
		for _, loadable in { false, true } do
			for _, other in { send, panel } do
				T.falsy(TrainController.applyLoadPrompt(other, loadable), other.Name .. " is not a Load prompt")
				T.truthy(other.Enabled, other.Name .. " still shows")
			end
		end
		local machine = Instance.new("ProximityPrompt")
		machine.Name = "LoadPrompt"
		machine:SetAttribute("Action", "Load")
		T.falsy(TrainController.applyLoadPrompt(machine, false), "an untagged prompt (PromptController's)")
		T.truthy(machine.Enabled)
		T.falsy(TrainController.applyLoadPrompt(Instance.new("Part"), false), "not a prompt")
	end)
end
