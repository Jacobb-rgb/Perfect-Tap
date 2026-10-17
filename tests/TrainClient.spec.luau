-- Ore trains on the client (TrainController + TrainView): the trip timeline
-- (legs, easing, the quarry portal per plot side, where a train is at a
-- time), tunnels hiding the cars, the wagons tipping toward the pen,
-- couplers, the waiting train at the Mine Station, trip payloads, the HUD
-- chip's state text from State snapshots, the upgrade rows, the view's
-- children and the phone layout (every touch target >= 44 pt).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")
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

	local function near(a: any, b: any, eps: number?, label: string?)
		T.near((a - b).Magnitude, 0, eps or 1e-4, label)
	end

	local function at(share: number): number
		return DEPART + TRIP * share
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

	-- places a consist at a pose (what the RenderStepped loop does with BulkMoveTo)
	local function place(consist: any, pose: any, parent: any)
		local parts, cframes = {}, {}
		TrainController.placeConsist(consist, pose, parent, parts, cframes)
		for i, part in parts do
			part.CFrame = cframes[i]
		end
		return #parts
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

	T.test("TrainClient: legs follow TrainConfig.Timeline", function()
		local tl = TrainConfig.Timeline
		local cases = {
			{ -0.1, "Waiting", 0 },
			{ 0, "Quarry", 0 },
			{ tl.QuarryLeg[2] / 2, "Quarry", 0.5 },
			{ tl.Underground[1], "Underground", 0 },
			{ (tl.Underground[1] + tl.Underground[2]) / 2, "Underground", 0.5 },
			{ tl.CoastLeg[1], "Coast", 0 },
			{ (tl.CoastLeg[1] + tl.CoastLeg[2]) / 2, "Coast", 0.5 },
			{ tl.Unload[1], "Unload", 0 },
			{ 0.999, "Unload", (0.999 - tl.Unload[1]) / (tl.Unload[2] - tl.Unload[1]) },
			{ 1.5, "Unload", 1 },
		}
		for _, case in cases do
			local leg, f = TrainController.legAt(case[1])
			T.eq(leg, case[2], "leg at " .. case[1])
			T.near(f, case[3], 1e-9, "fraction at " .. case[1])
		end
		-- the legs cover 0..1 without gaps
		T.eq(tl.QuarryLeg[2], tl.Underground[1])
		T.eq(tl.Underground[2], tl.CoastLeg[1])
		T.eq(tl.CoastLeg[2], tl.Unload[1])
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
			-- the quarry leg heads for it: west plots run west from the station
			local p = TrainController.poseAt(plot, DEPART, ARRIVE, at(0.05))
			T.eq(p.Leg, "Quarry")
			T.truthy((p.Facing.X < 0) == (plot.Center.X < 0), "plot " .. plot.Id .. " heads to its side")
			-- the coast leg runs on the plot's own line
			local coast = TrainController.poseAt(plot, DEPART, ARRIVE, at(0.85))
			T.near(coast.Position.X, TrainConfig.lineFor(plot)[1].X, 1e-6, "plot " .. plot.Id .. " coast x")
		end
	end)

	T.test("TrainClient: where a train is during a trip", function()
		local tl = TrainConfig.Timeline
		local stop = TrainConfig.QuarryStop
		local portal = TrainController.quarryPortal(WEST)
		local quarryLength = (portal - stop).Magnitude + TrainController.HideDepth

		-- leaving the station: at rest on QuarryStop, heading for the portal
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, DEPART)
		T.eq(p.Leg, "Quarry")
		near(p.Position, stop + RAIL, 1e-6, "starts on QuarryStop")
		T.near(p.Speed, 0, 1e-9, "starts from rest")
		near(p.Facing, Vector3.new(-1, 0, 0), 1e-6, "faces the west portal")
		-- halfway through the quarry leg: a quarter of the way (ease in)
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, at(tl.QuarryLeg[2] / 2))
		T.near((p.Position - (stop + RAIL)).Magnitude, quarryLength * 0.25, 1e-4, "eased in")
		-- underground: hidden
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, at(0.4))
		T.eq(p.Leg, "Underground")
		T.truthy(p.Hidden, "hidden underground")

		local line = TrainConfig.lineFor(WEST)
		local mouth = line[1]
		local trainStop = TrainConfig.stopFor(WEST)
		local start = mouth + Vector3.new(0, 0, TrainController.HideDepth) -- inside the south tunnel
		-- the coast leg: halfway in time is halfway along (ease in / out), facing north
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, at((tl.CoastLeg[1] + tl.CoastLeg[2]) / 2))
		T.eq(p.Leg, "Coast")
		near(p.Position, (start + trainStop) / 2 + RAIL, 1e-4, "halfway along the coast")
		near(p.Facing, Vector3.new(0, 0, -1), 1e-6, "runs north")
		T.lt(0, p.Speed, "moving")
		-- arriving: at the stop, the hopper tips during the unload
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, at(tl.Unload[1]))
		near(p.Position, trainStop + RAIL, 1e-6, "at the Train Stop")
		T.near(p.Tip, 0, 1e-9, "not tipped yet")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, at(tl.Unload[1] + (tl.Unload[2] - tl.Unload[1]) * 0.3))
		T.lt(0, p.Tip, "tipping")
		T.lt(p.Tip, 1, "still tipping")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, at(0.995))
		T.near(p.Tip, 1, 1e-9, "fully tipped")
		-- after arrival: holds, tips back, rolls back south into the tunnel
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + 0.1)
		T.eq(p.Leg, "Unload")
		T.near(p.Tip, 1, 1e-9, "still pouring")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + TrainController.UnloadHold + 0.01)
		T.eq(p.Leg, "Return")
		T.near(p.Tip, 0, 1e-9, "hopper back down")
		near(p.Facing, Vector3.new(0, 0, -1), 1e-6, "backs up (still faces north)")
		local mid = TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + TrainConfig.ReturnSeconds * 0.7)
		T.lt(trainStop.Z, mid.Position.Z, "rolls south")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + TrainConfig.ReturnSeconds - 0.001)
		near(p.Position, start + RAIL, 0.01, "back inside the tunnel")
		p = TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + TrainConfig.ReturnSeconds)
		T.eq(p.Leg, "Done")
		T.truthy(p.Hidden, "gone after the return")
		-- a broken trip (no duration) never errors: it is simply over
		T.eq(TrainController.poseAt(WEST, ARRIVE, ARRIVE, ARRIVE + 100).Leg, "Done")
	end)

	T.test("TrainClient: no jumps while a train is in sight; Speed matches the motion", function()
		for _, plot in { WEST, EAST_FAR } do
			local dt = 0.01
			local last = TrainController.poseAt(plot, DEPART, ARRIVE, DEPART)
			local t = DEPART + dt
			while t < ARRIVE + TrainConfig.ReturnSeconds do
				local p = TrainController.poseAt(plot, DEPART, ARRIVE, t)
				if p.Leg == last.Leg and not p.Hidden then
					local moved = (p.Position - last.Position).Magnitude
					-- average speed over the step, compared with the reported speed
					local expected = (p.Speed + last.Speed) / 2 * dt
					T.near(moved, expected, math.max(0.02, expected * 0.05), `plot {plot.Id} {p.Leg} at {t - DEPART}`)
					T.near(math.abs(p.Odometer - last.Odometer), moved, 1e-3, "odometer follows the rails")
				end
				last = p
				t += dt
			end
		end
	end)

	T.test("TrainClient: tunnels hide the cars", function()
		local tl = TrainConfig.Timeline
		-- coming out of the south tunnel: at the start nothing shows, then the locomotive first
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, at(tl.CoastLeg[1] + 1e-6))
		T.falsy(TrainController.visible(p, p.Position, 7.2), "locomotive still inside")
		local out = TrainController.poseAt(WEST, DEPART, ARRIVE, at(tl.CoastLeg[2] - 0.01))
		T.truthy(TrainController.visible(out, out.Position, 7.2), "locomotive out")
		T.truthy(TrainController.visible(out, out.Position - out.Facing * 25, 6), "last wagon out")
		-- the near plot (z 84) sees its train come out halfway through the leg
		local mid = TrainController.poseAt(WEST, DEPART, ARRIVE, at((tl.CoastLeg[1] + tl.CoastLeg[2]) / 2))
		T.truthy(TrainController.visible(mid, mid.Position, 7.2), "locomotive at the mouth")
		-- end of the quarry leg: the whole train is inside the quarry wall
		local inside = TrainController.poseAt(WEST, DEPART, ARRIVE, at(tl.QuarryLeg[2] - 1e-6))
		T.falsy(TrainController.visible(inside, inside.Position - inside.Facing * 25.15, 6), "last wagon inside")
		-- HideDepth fits a locomotive with two wagons (front coupler to back coupler)
		local consist = TrainController.buildConsist(RED, { ORE, ORE }, false)
		local last = consist.Vehicles[3]
		local span = consist.Vehicles[1].Half + last.Offset + last.Half
		T.le(span, TrainController.HideDepth, "a whole consist fits in a tunnel")
		TrainController.destroyConsist(consist)
	end)

	T.test("TrainClient: the waiting train backs into the Mine Station", function()
		local stop = TrainConfig.QuarryStop
		for _, plot in { WEST, EAST_FAR } do
			local portal = TrainController.quarryPortal(plot)
			local rest = TrainController.parkedPose(plot, nil)
			near(rest.Position, stop + RAIL, 1e-6, "waits on QuarryStop")
			T.eq(rest.Speed, 0)
			T.truthy(rest.Facing:Dot((portal - stop).Unit) > 0.999, "faces its portal")
			local first = TrainController.parkedPose(plot, 0)
			near(
				first.Position,
				stop + (portal - stop).Unit * ((portal - stop).Magnitude + TrainController.HideDepth) + RAIL,
				1e-4,
				"starts in the tunnel"
			)
			local half = TrainController.parkedPose(plot, TrainController.RollInSeconds / 2)
			T.lt((half.Position - rest.Position).Magnitude, (first.Position - rest.Position).Magnitude, "comes closer")
			T.lt(0, half.Speed, "rolling")
			local done = TrainController.parkedPose(plot, TrainController.RollInSeconds)
			near(done.Position, rest.Position, 1e-6, "parked")
			T.eq(TrainController.parkedPose(plot, 99).Speed, 0, "long after: standing")
		end
	end)

	---------------------------------------------------------------- consists

	T.test("TrainClient: couplers touch and the wheels roll", function()
		local folder = Instance.new("Folder")
		local consist = TrainController.buildConsist(RED, { ORE, {} }, false)
		T.eq(#consist.Vehicles, 3)
		T.eq(consist.Vehicles[1].Model:GetAttribute("Kind"), "Locomotive")
		T.truthy(consist.Vehicles[2].Loaded, "loaded wagon")
		T.falsy(consist.Vehicles[3].Loaded, "empty wagon")
		local p = TrainController.poseAt(WEST, DEPART, ARRIVE, at(0.94))
		local count = place(consist, p, folder)
		T.lt(90, count, "every part placed")
		for i = 1, 2 do
			local back = worldOf(find(consist.Vehicles[i].Model, "Attachment", "CouplerBack"))
			local front = worldOf(find(consist.Vehicles[i + 1].Model, "Attachment", "CouplerFront"))
			near(back, front, 1e-4, "coupler " .. i)
		end
		-- the locomotive's Root sits on the rails at the pose
		near(consist.Vehicles[1].Model.PrimaryPart.CFrame.Position, p.Position, 1e-4, "locomotive on the pose")
		near(consist.Vehicles[1].Model.PrimaryPart.CFrame.LookVector, p.Facing, 1e-6, "front ahead")
		-- wheels stay on their axles and turn by distance / radius
		local loco = consist.Vehicles[1]
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
		local tunnel = TrainController.poseAt(WEST, DEPART, ARRIVE, at(0.5))
		T.eq(place(consist, tunnel, folder), 0, "nothing placed underground")
		T.eq(consist.Vehicles[1].Model.Parent, nil, "hidden")
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
			local upright = TrainController.poseAt(plot, DEPART, ARRIVE, at(TrainConfig.Timeline.Unload[1]))
			local tipped = TrainController.poseAt(plot, DEPART, ARRIVE, at(0.999))
			place(consist, upright, nil)
			local before = oreCenter()
			local wheel = wagon.Parts[next(wagon.Wheels) :: number].CFrame.Position
			place(consist, tipped, nil)
			local after = oreCenter()
			local pen = TrainController.penCenter(plot)
			local toward = Vector3.new(pen.X - before.X, 0, pen.Z - before.Z).Unit
			T.lt(1, (after - before):Dot(toward), "plot " .. plot.Id .. " ore moves toward the pen")
			near(wagon.Parts[next(wagon.Wheels) :: number].CFrame.Position, wheel, 1e-4, "the bogies stay put")
			TrainController.destroyConsist(consist)
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
		local top = wagon.Offsets[index :: number].Position.Y
		TrainController.setFill(wagon, 0.25)
		T.lt(wagon.Offsets[index :: number].Position.Y, top, "a low load sits lower")
		TrainController.setFill(wagon, 1)
		T.near(wagon.Offsets[index :: number].Position.Y, top, 1e-9, "full again")
		TrainController.destroyConsist(consist)
	end)

	T.test("TrainClient: the load slides out while pouring and stays out", function()
		local tl = TrainConfig.Timeline
		T.eq(TrainController.pourFill(TrainController.poseAt(WEST, DEPART, ARRIVE, at(0.85))), nil, "full on the coast")
		T.eq(TrainController.pourFill(TrainController.poseAt(WEST, DEPART, ARRIVE, at(tl.Unload[1]))), nil, "not tipped yet")
		local consist = TrainController.buildConsist(RED, { ORE, ORE }, false)
		local fills = {}
		for _, share in { 0.955, 0.965, 0.975, 0.99 } do
			TrainController.applyPour(consist, TrainController.poseAt(WEST, DEPART, ARRIVE, at(share)))
			table.insert(fills, consist.Vehicles[2].Fill)
		end
		for i = 2, #fills do
			T.le(fills[i], fills[i - 1], "never fills back up")
		end
		T.lt(fills[#fills], 0.05, "empty at full tip")
		-- tipping back after arrival and the trip home keep it empty
		TrainController.applyPour(consist, TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + 0.8))
		T.lt(consist.Vehicles[2].Fill, 0.05, "stays empty while the hopper comes down")
		T.eq(TrainController.pourFill(TrainController.poseAt(WEST, DEPART, ARRIVE, ARRIVE + 3)), 0, "empty on the way back")
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
		T.truthy(loading.CanSend, "send early")
		T.near(loading.Fill, 0.75, 1e-9)
		T.eq(status({ Cargo = 6, Capacity = 8, AutoDepartIn = 18 }, 4.2).Line, "Leaves in 0:05", "counted down")
		T.eq(status({ Cargo = 2, Capacity = 8 }).Line, "Ready – Send!")

		local full = status({ Cargo = 8, Capacity = 8 })
		T.eq(full.Phase, "Full")
		T.eq(full.Line, "Full – Send!")
		T.truthy(full.CanSend)

		local moving = status({ Cargo = 0, Capacity = 8, Moving = 8, DepartAt = now - 18, ArriveAt = now + 11.2 })
		T.eq(moving.Phase, "Moving")
		T.eq(moving.Line, "On its way 0:12")
		T.falsy(moving.CanSend, "already away")
		T.near(moving.Progress, 18 / 29.2, 1e-9, "the chip's bar shows the trip")
		T.eq(loading.Progress, nil, "no trip bar at the station")
		local back = status({ Cargo = 3, Capacity = 8, DepartAt = now - 31, ArriveAt = now - 1 })
		T.eq(back.Phase, "Returning")
		T.eq(back.Line, "Returning")
		T.falsy(back.CanSend, "still away")
		local home = status({ Cargo = 3, Capacity = 8, DepartAt = now - 60, ArriveAt = now - 30 })
		T.eq(home.Phase, "Loading", "an old trip doesn't count")

		-- junk snapshots fall back to safe values
		local junk = TrainView.read({ Cargo = 0 / 0, Capacity = "8", CapacityLevel = -3, ArriveAt = math.huge, Express = "yes" })
		T.eq(junk.Cargo, 0)
		T.eq(junk.Capacity, TrainConfig.capacity(0, false))
		T.eq(junk.CapacityLevel, 0)
		T.eq(junk.ArriveAt, nil)
		T.eq(junk.Express, false)
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
		T.eq(refs.ChipSend.BackgroundColor3, Theme.Good, "SEND lights up")
		T.eq(refs.ChipFill.Size.X.Scale, 1)
		TrainView.setUpgrades(refs, train, 100)
		T.eq(refs.Rows.Capacity.Detail.Text, "Cargo 12 → 18")
		T.eq(refs.Rows.Capacity.Buy.BackgroundColor3, Theme.PanelLight, "can't afford: greyed")
		T.eq(refs.Rows.Speed.Price.Text, "$3K")
		TrainView.setStatus(refs, TrainView.status(TrainView.read({ Cargo = 0, Capacity = 8 }), 0, nil))
		T.eq(refs.ChipSend.BackgroundColor3, Theme.PanelLight, "empty: SEND greyed")
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

	T.test("TrainClient: phone layout keeps every touch target >= 44 pt", function()
		local scale = TrainView.PhoneScale
		-- an iPhone SE in landscape: 667 x 375 pt, 58 pt for the top bar
		local width, height = 667 / scale, (375 - 58) / scale
		local refs = TrainView.build(true)
		TrainView.layout(refs, true, width, height)
		T.truthy(refs.Compact, "compact")
		for _, target in TrainView.touchTargets(refs) do
			local w, h = absolute(target)
			T.le(TrainView.MinTouch, h * scale, target.Name .. " tall enough")
			T.le(TrainView.MinTouch, w * scale, target.Name .. " wide enough")
		end
		-- the panel fits the screen and the rows fit the panel
		local panel = refs.Panel.Size
		T.le(panel.X.Offset, width, "panel width")
		T.le(panel.Y.Offset, height, "panel height")
		local rows = refs.Rows.Capacity.Frame.Parent
		T.le(rows.Position.Y.Offset + rows.Size.Y.Offset, panel.Y.Offset, "rows inside")
		T.lt(0, refs.Trip.Size.Y.Offset, "room for the trip line")
		T.falsy(refs.Subtitle.Visible, "no subtitle on phones")
		-- the chip stays on the left third of the screen, under the coins
		T.le((refs.ChipFrame.Position.X.Offset + refs.ChipFrame.Size.X.Offset) * scale, 667 * 0.45, "chip width")
		-- desktop: still comfortable to click, and the panel fits a 720p screen
		TrainView.layout(refs, false, 1280, 720 - 36)
		for _, target in TrainView.touchTargets(refs) do
			local _, h = absolute(target)
			T.le(40, h, target.Name .. " on desktop")
		end
		T.le(refs.Panel.Size.Y.Offset, 720 - 36, "fits 720p")
	end)

	T.test("TrainClient: sounds exist for the chuff and the whistle", function()
		for _, name in { "TrainChuff", "TrainWhistle", "Drop", "Gulp", "UIClick" } do
			local def = SoundConfig[name]
			T.truthy(def, name)
			T.truthy(string.sub(def.Id, 1, 9) == "rbxasset:", name .. " is a built-in or uploaded sound")
		end
	end)

	local _ = CFrame
end
