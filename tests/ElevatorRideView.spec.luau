-- ElevatorRideView (the full-screen elevator ride) under Lune: the ride's
-- timing (doors shut before the server moves the character, one tick per
-- floor, the doors open only after "Arrive" and the least ride time, the
-- fail-safe, 2.5-3 s in all), the shaft in the windows (scrolling rock bands
-- tinted by the floor being passed, a lamp per floor), the indicator's pulse,
-- chevrons and dots, the speed lines, the overlay it builds and its pose
-- (doors, shake, banner) with and without reduced motion.
return function(T, Loader)
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local ElevatorView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ElevatorView")
	local RideView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ElevatorRideView")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")

	local timing = RideView.Timing

	local function ride(from: number, to: number, reduced: boolean?): any
		return RideView.newRide(
			from,
			to,
			MineFloors.get(to).Name,
			ElevatorService.rideTime(from, to),
			ElevatorService.DoorsClose,
			reduced == true
		)
	end

	T.test("ElevatorRide: the doors are shut before the server moves the character", function()
		local r = ride(1, 4)
		T.le(r.Close, ElevatorService.DoorsClose - 0.05 + 1e-9, "shut before DoorsClose")
		T.truthy(r.Close >= 0.15, "a real slam, not a pop")
		T.eq(RideView.closedness(r, 0), 0, "open at the start")
		T.near(RideView.closedness(r, r.Close), 1, 1e-9, "shut at Close")
		T.eq(RideView.closedness(r, 30), 1, "stay shut until the doors may open")
		-- junk from the network falls back to sane numbers
		local junk = RideView.newRide(nil, 3, "x", 0 / 0, "soon", false)
		T.eq(junk.From, 3, "unknown start = the target")
		T.eq(junk.Close, timing.Close, "default slam")
		T.truthy(junk.MinRide > junk.Close, "some ride")
		local fast = RideView.newRide(2, 3, "x", 0.1, 0.1, false)
		T.truthy(fast.Close >= 0.15 and fast.MinRide >= fast.Close + 0.6, "never too short")
	end)

	T.test("ElevatorRide: one tick per floor, counting toward the target", function()
		local down = ride(1, 4)
		T.eq(RideView.direction(1, 4), "Down", "deeper = down")
		T.eq(RideView.direction(4, 2), "Up", "back up")
		local ticks = RideView.ticks(down)
		T.eq(#ticks, 3, "three floors, three ticks")
		local last = -1
		for i, tick in ticks do
			T.eq(tick.Floor, 1 + i, "floor " .. (1 + i))
			T.truthy(tick.Time > last, "in order")
			T.truthy(tick.Time >= down.Close + timing.TickLead - 1e-9, "after the thud")
			T.truthy(tick.Time <= down.MinRide - timing.TickLead + 1e-9, "before the ding")
			last = tick.Time
		end
		T.near(ticks[2].Time - ticks[1].Time, ticks[3].Time - ticks[2].Time, 1e-9, "evenly spaced")
		T.eq(RideView.numberAt(down, 0), 1, "starts at the floor you left")
		T.eq(RideView.numberAt(down, down.MinRide), 4, "reaches the target")
		local up = ride(5, 2)
		local upTicks = RideView.ticks(up)
		T.eq(#upTicks, 3)
		T.eq(upTicks[1].Floor, 4, "counting down the numbers when going up")
		T.eq(upTicks[3].Floor, 2)
		T.eq(#RideView.ticks(RideView.newRide(3, 3, "x", 2, 0.5, false)), 0, "no floors, no ticks")
	end)

	T.test("ElevatorRide: the doors open only after Arrive and the least ride time, or by the fail-safe", function()
		local r = ride(2, 3)
		T.falsy(RideView.shouldOpen(r, r.MinRide - 0.01, true), "not before the least ride time")
		T.truthy(RideView.shouldOpen(r, r.MinRide, true), "at the least ride time once arrived")
		T.falsy(RideView.shouldOpen(r, r.MinRide + 2, false), "waits for Arrive (streaming)")
		T.truthy(RideView.shouldOpen(r, r.MinRide + timing.FailSafe, false), "the fail-safe always opens them")
		r.OpenAt = r.MinRide
		T.falsy(RideView.shouldOpen(r, r.MinRide + 1, true), "once only")
		T.near(RideView.closedness(r, r.OpenAt + timing.Open), 0, 1e-9, "open after Open seconds")
		T.near(RideView.openedAt(r), r.OpenAt + timing.Open, 1e-9, "controls come back then")
		T.truthy(RideView.doneAt(r) > RideView.openedAt(r), "the banner finishes after the doors")
	end)

	T.test("ElevatorRide: about 2.5-3 s from GO until the doors are open", function()
		for _, pair in { { 1, 2 }, { 1, 5 }, { 3, 4 }, { 5, 1 } } do
			local r = ride(pair[1], pair[2])
			r.OpenAt = r.MinRide
			local total = RideView.openedAt(r)
			T.truthy(total >= 2.4 and total <= 3.05, `{pair[1]} -> {pair[2]}: {total} s`)
		end
	end)

	T.test("ElevatorRide: the overlay covers the screen; the panels follow the HUD scale", function()
		local refs = RideView.build()
		T.falsy(refs.Gui.Enabled, "off until a ride")
		T.truthy(refs.Gui.IgnoreGuiInset, "over the top bar too")
		T.eq(refs.Gui:FindFirstChildOfClass("UIScale"), nil, "no UIScale on the gui (the doors fill the screen)")
		T.eq(refs.DoorLeft.Size.X.Scale, 0.5, "half the screen each")
		T.truthy(refs.DoorLeft.Size.X.Offset > 0, "overlapping at the seam")
		T.eq(refs.DoorLeft.Size.Y.Scale, 1, "full height")
		T.eq(#refs.Windows, 2, "a window per door")
		for _, win in refs.Windows do
			T.truthy(win.Frame.ClipsDescendants, "the shaft stays inside the window")
			T.eq(#win.Bands, 5, "rock bands")
		end
		T.eq(#refs.SpeedLines, 10, "speed lines on both edges")
		T.eq(#refs.Chevrons, 3, "three flowing chevrons")
		T.eq(#refs.Dots, #MineFloors.List, "a dot per floor")
		RideView.layout(refs, 0.62, 36)
		T.near(refs.IndicatorScale.Scale, 0.62, 1e-6, "indicator scaled")
		T.near(refs.BannerScale.Scale, 0.62, 1e-6, "banner scaled")
		local r = ride(1, 4)
		RideView.setRide(refs, r)
		T.eq(refs.BannerText.Text, "FLOOR 4 · SUNKEN PALACE", "banner text")
		T.eq(refs.BannerStroke.Color, ElevatorView.floorColor(4), "floor colour")
		T.eq(RideView.bannerText(5, "Heartstone Core"), "FLOOR 5 · HEARTSTONE CORE")
	end)

	T.test("ElevatorRide: the pose follows the timeline", function()
		local refs = RideView.build()
		RideView.layout(refs, 1, 36)
		local r = ride(1, 4)
		RideView.setRide(refs, r)
		local rest = refs.Root.Position
		RideView.pose(refs, r, 0)
		T.near(refs.DoorLeft.Position.X.Scale, -0.56, 1e-6, "doors open at the start")
		T.near(refs.DoorRight.Position.X.Scale, 1.56, 1e-6)
		T.falsy(refs.Banner.Visible, "no banner yet")
		RideView.pose(refs, r, r.Close)
		T.near(refs.DoorLeft.Position.X.Scale, 0, 1e-6, "left door shut")
		T.near(refs.DoorRight.Position.X.Scale, 1, 1e-6, "right door shut")
		T.truthy(refs.Seam.Visible, "the seam glows")
		RideView.pose(refs, r, r.Close + 0.05)
		T.truthy(refs.Root.Position ~= rest, "the thud shakes")
		T.truthy(refs.Windows[1].Lamp.Visible, "a lamp passes while riding")
		T.truthy(refs.SpeedLines[1].Visible, "speed lines while riding")
		T.truthy(refs.Indicator.Visible, "the indicator is in")
		T.eq(refs.Arrow.Rotation, 180, "down arrow")
		T.eq(refs.Number.Text, "1", "still floor 1")
		RideView.pose(refs, r, r.MinRide - 0.01)
		T.eq(refs.Number.Text, "4", "counted to 4")
		T.eq(refs.Number.TextColor3, ElevatorView.floorColor(4), "in the floor's colour")
		T.eq(refs.Dots[4].Size.X.Offset, 18, "its dot is big")
		r.OpenAt = r.MinRide
		RideView.pose(refs, r, r.OpenAt + timing.BannerDelay + timing.BannerIn + 0.2)
		T.truthy(refs.Banner.Visible, "the banner holds")
		T.near(refs.Banner.Position.X.Scale, 0.5, 1e-6, "in the middle")
		T.falsy(refs.Windows[1].Lamp.Visible, "no lamp after the ding")
		T.falsy(refs.SpeedLines[1].Visible, "no speed lines after the ding")
		T.falsy(refs.DoorLeft.Visible, "the doors are open")
		RideView.pose(refs, r, RideView.doneAt(r) + 0.01)
		T.falsy(refs.Banner.Visible, "the banner left")
		T.falsy(refs.Indicator.Visible, "the indicator left")
		-- going back up
		local up = ride(4, 2)
		RideView.pose(refs, up, up.Close + 0.5)
		T.eq(refs.Arrow.Rotation, 0, "up arrow")
	end)

	T.test("ElevatorRide: the shaft tint follows the floor being passed and cross-fades at each tick", function()
		local r = ride(1, 4)
		local a, b, k = RideView.tintAt(r, 0)
		T.truthy(a == 1 and b == 1 and k == 1, "floor 1 before the first tick")
		local ticks = RideView.ticks(r)
		a, b, k = RideView.tintAt(r, ticks[2].Time + 0.01)
		T.truthy(a == 2 and b == 3, "from floor 2 to floor 3")
		T.truthy(k > 0 and k < 0.2, "the cross-fade just started")
		a, b, k = RideView.tintAt(r, ticks[2].Time + RideView.Timing.TintFade)
		T.near(k, 1, 1e-9, "done after TintFade")
		local up = ride(5, 3)
		a, b = RideView.tintAt(up, RideView.ticks(up)[1].Time)
		T.truthy(a == 5 and b == 4, "going up: 5 -> 4")
		-- each floor's shaft is its own palette
		local seen = {}
		for floor = 1, #MineFloors.List do
			local colors = RideView.shaftColors(floor)
			T.eq(colors.Vein, MineFloors.get(floor).Palette.Accent, "veins in the floor's accent " .. floor)
			T.eq(colors.Glint, MineFloors.get(floor).Palette.Crystal, "glints in its crystal colour " .. floor)
			local mid = colors.Bands[1]
			local id = string.format("%.2f,%.2f,%.2f", mid.R, mid.G, mid.B)
			T.falsy(seen[id], "a different rock per floor")
			seen[id] = true
		end
		T.eq(RideView.shaftColors(99).Vein, RideView.shaftColors(#MineFloors.List).Vein, "past the list: the last floor")
	end)

	T.test("ElevatorRide: the wall speeds up after the thud, a lamp passes at each tick, the indicator pulses", function()
		local r = ride(1, 4)
		T.eq(RideView.travel(r, r.Close), 0, "still at the thud")
		local early = RideView.travel(r, r.Close + 0.1)
		local later = RideView.travel(r, r.Close + 0.6) - RideView.travel(r, r.Close + 0.5)
		T.truthy(early < 0.1 * RideView.ShaftSpeed, "slow at first")
		T.near(later, 0.1 * RideView.ShaftSpeed, 1e-6, "then full speed")
		r.OpenAt = r.MinRide
		T.eq(RideView.travel(r, r.MinRide + 1), RideView.travel(r, r.MinRide), "frozen once the doors open")
		r.OpenAt = nil
		local refs = RideView.build()
		RideView.layout(refs, 1, 36)
		RideView.setRide(refs, r)
		local ticks = RideView.ticks(r)
		RideView.pose(refs, r, ticks[1].Time)
		T.near(refs.Windows[1].Lamp.Position.Y.Scale, 0.5, 1e-6, "the lamp is in the middle at a tick")
		T.near(RideView.pulseAt(r, ticks[1].Time), 1, 1e-9, "full pulse at a tick")
		T.truthy(refs.IndicatorScale.Scale > 1.05, "the indicator pops")
		T.truthy(refs.IndicatorGlow.Transparency < 0.2, "and glows")
		RideView.pose(refs, r, ticks[1].Time + RideView.Timing.Pulse + 0.01)
		T.near(refs.IndicatorScale.Scale, 1, 1e-6, "back to size")
		-- the wall moves up when going down
		local band = refs.Windows[1].Bands[2].Frame
		RideView.pose(refs, r, 1.0)
		local y1 = band.Position.Y.Scale
		RideView.pose(refs, r, 1.02)
		local y2 = band.Position.Y.Scale
		T.truthy(y2 < y1 or y2 - y1 > 1, "the wall moves up going down")
		-- dots of the floors passed light up
		RideView.pose(refs, r, ticks[2].Time + 0.01)
		T.eq(refs.Dots[1].BackgroundTransparency, 0, "floor 1 passed")
		T.eq(refs.Dots[3].BackgroundTransparency, 0, "floor 3 current")
		T.eq(refs.Dots[3].Size.X.Offset, 18, "current is big")
		T.truthy(refs.Dots[5].BackgroundTransparency > 0.5, "floor 5 not yet")
		T.eq(refs.FloorStripes[1].BackgroundColor3, ElevatorView.floorColor(4), "the doors' stripe in the target colour")
	end)

	T.test("ElevatorRide: reduced motion keeps the doors and the numbers, drops shake and sweeps", function()
		local refs = RideView.build()
		RideView.layout(refs, 1, 36)
		local r = ride(1, 3, true)
		local rest = refs.Root.Position
		RideView.pose(refs, r, r.Close + 0.05)
		T.eq(refs.Root.Position, rest, "no shake")
		for _, line in refs.SpeedLines do
			T.falsy(line.Visible, "no speed lines")
		end
		T.falsy(refs.Windows[1].Lamp.Visible, "no passing lamp")
		local band = refs.Windows[1].Bands[1].Frame
		local before = band.Position
		local tintBefore = band.BackgroundColor3
		T.near(refs.IndicatorScale.Scale, 1, 1e-6, "no pop")
		T.near(refs.DoorLeft.Position.X.Scale, 0, 1e-6, "the doors still shut")
		RideView.pose(refs, r, r.MinRide - 0.01)
		T.eq(refs.Number.Text, "3", "the numbers still count")
		T.eq(band.Position, before, "the wall doesn't scroll")
		T.truthy(band.BackgroundColor3 ~= tintBefore, "but the tint follows the floors")
	end)
end
