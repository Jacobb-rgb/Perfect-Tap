-- Ore trains on the client (TrainController + TrainView): the trip timeline
-- (legs with minimum visible seconds, easing, the quarry portal per plot side,
-- where a train is at a time), the stop that lines the wagons up with the Ore
-- Pen, the hold at a full pen and the unload, tunnels hiding the cars, the
-- wagons tipping toward the pen and the ore clearing the Foundry, couplers,
-- the waiting train under the station chute, trip payloads and snapshots, the
-- HUD chip's state text, the upgrade rows, the view's children and the phone
-- layouts (every touch target >= 44 pt, names readable on narrow phones).
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
	local TrainController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.TrainController")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")

	local RAIL = Vector3.new(0, TrainBuilder.RailTop, 0)
	local WEST = WorldLayout.Plots[1] -- x -104, z 84
	local EAST_FAR = WorldLayout.Plots[8] -- x 104, z -84
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
		-- halfway through the quarry leg: a quarter of the way (ease in)
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Quarry / 2)
		T.near((p.Position - (start + RAIL)).Magnitude, quarryLength * 0.25, 1e-4, "eased in")
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
		local mid = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + TrainConfig.ReturnSeconds * 0.7, 1, unloadAt)
		T.lt(trainStop.Z, mid.Position.Z, "rolls south")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + TrainConfig.ReturnSeconds - 0.001, 1, unloadAt)
		near(p.Position, inside + RAIL, 0.01, "back inside the tunnel")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + TrainConfig.ReturnSeconds, 1, unloadAt)
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
			while t < unloadAt + TrainConfig.ReturnSeconds do
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

	T.test("TrainClient: tunnels hide the cars", function()
		local s = spans()
		-- coming out of the south tunnel: at the start nothing shows, then the locomotive first
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Underground + 1e-6)
		T.falsy(TrainController.visible(p, p.Position, 7.2), "locomotive still inside")
		local out = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART + s.Coast - 0.01, 2)
		T.truthy(TrainController.visible(out, out.Position, 7.2), "locomotive out")
		T.truthy(TrainController.visible(out, out.Position - out.Facing * 25.15, 6), "last wagon out")
		-- the near plot (z 84) sees its train come out halfway through the leg
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
		-- the west plots' wagons no longer unload beside the Foundry (the reviewer's plot 1)
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

	T.test("TrainClient: the ore flies into the pen and over the Foundry", function()
		local foundry = BaseLayout.Foundry
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
								T.lt(top, at.Y, `plot {plot.Id} wagon at {offset}: the chunk clears the Foundry`)
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
		for _, after in { 0, 0.2, 0.35, 0.5, 0.8 } do
			TrainController.applyPour(consist, TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + after, 2, unloadAt))
			table.insert(fills, consist.Vehicles[2].Fill)
		end
		T.eq(fills[1], 1, "not before the tip")
		for i = 2, #fills do
			T.le(fills[i], fills[i - 1], "never fills back up")
		end
		T.lt(fills[#fills], 0.05, "empty at full tip")
		-- tipping back and the trip home keep it empty
		local down = unloadAt + TrainController.TipUp + TrainController.TipHold + TrainController.TipDown / 2
		TrainController.applyPour(consist, TrainController.poseAt(WEST, DEPART, ARRIVE, down, 2, unloadAt))
		T.lt(consist.Vehicles[2].Fill, 0.05, "stays empty while the hopper comes down")
		T.eq(TrainController.pourFill(TrainController.poseAt(WEST, DEPART, ARRIVE, unloadAt + 3, 2, unloadAt)), 0, "empty on the way back")
		T.eq(consist.Vehicles[3].Fill, consist.Vehicles[2].Fill, "both wagons pour")
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
		T.eq(waiting.Phase, "PenFull")
		T.eq(waiting.Line, "Pen full – make room")
		T.eq(waiting.Title, "TRAIN 8/8")
		T.eq(waiting.Color, Theme.Bad)
		T.falsy(waiting.CanSend, "can't send a train that is away")
		T.eq(status({ Moving = 5, Capacity = 8, DepartAt = now - 60, ArriveAt = now - 5 }).Phase, "PenFull", "still loaded long after")
		T.eq(status({ Moving = 3, Capacity = 8, Waiting = true }).Phase, "PenFull", "Waiting alone")
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
		T.eq(capacity.Detail, "Cargo 8 → 12")
		T.eq(capacity.LevelText, "LV 1/6")
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
		local top = TrainView.read({ CapacityLevel = 5, SpeedLevel = 5 })
		local maxed = TrainView.upgrade(top, "Capacity", 1e12)
		T.truthy(maxed.Maxed)
		T.eq(maxed.PriceText, "MAX")
		T.falsy(maxed.CanBuy)
		T.eq(maxed.Detail, "Cargo 50 (max)")
		-- Express: +50 % cargo and half the trip
		local express = TrainView.read({ CapacityLevel = 0, SpeedLevel = 0, Express = true })
		T.eq(TrainView.upgrade(express, "Capacity", 0).Detail, "Cargo 12 → 18")
		T.eq(TrainView.upgrade(express, "Speed", 0).Detail, "Trip 15 s → 12.5 s")
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
		T.eq(refs.Rows.Capacity.Detail.Text, "Cargo 12 → 18")
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
		local roomy = phone(667, 375)
		T.lt(0, roomy.Trip.Size.Y.Offset, "room for the trip line")
		T.falsy(TrainView.chipVisible(true, true, true), "phones: the chip hides behind the open panel")
		T.truthy(TrainView.chipVisible(true, true, false), "PC: the chip stays")
		T.falsy(TrainView.chipVisible(false, false, false), "hidden with the HUD")
		-- desktop: still comfortable to click, and the panel fits a 720p screen
		local refs = TrainView.build(false)
		TrainView.layout(refs, false, 1280, 720 - 36)
		for _, target in TrainView.touchTargets(refs) do
			local _, h = absolute(target)
			T.le(40, h, target.Name .. " on desktop")
		end
		T.le(refs.Panel.Size.Y.Offset, 720 - 36, "fits 720p")
		T.eq(refs.Rows.Capacity.Frame.Size.Y.Offset, 100, "full rows on desktop")
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
end
