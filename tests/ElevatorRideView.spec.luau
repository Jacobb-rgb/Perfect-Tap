-- ElevatorRideView (the full-screen elevator ride) under Lune: the ride's
-- timing (doors shut before the server moves the character, one tick per
-- floor, the doors open only after "Arrive" and the least ride time, the
-- fail-safe, 2.5-3 s in all), the overlay it builds and its pose (doors,
-- shake, sweeps, indicator, banner) with and without reduced motion.
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
		T.eq(#refs.Strips, 6, "three light strips per window")
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
		T.truthy(refs.Strips[1].Visible, "lights sweep while riding")
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
		T.falsy(refs.Strips[1].Visible, "no sweeps after the ding")
		T.falsy(refs.DoorLeft.Visible, "the doors are open")
		RideView.pose(refs, r, RideView.doneAt(r) + 0.01)
		T.falsy(refs.Banner.Visible, "the banner left")
		T.falsy(refs.Indicator.Visible, "the indicator left")
		-- going back up
		local up = ride(4, 2)
		RideView.pose(refs, up, up.Close + 0.5)
		T.eq(refs.Arrow.Rotation, 0, "up arrow")
	end)

	T.test("ElevatorRide: reduced motion keeps the doors and the numbers, drops shake and sweeps", function()
		local refs = RideView.build()
		RideView.layout(refs, 1, 36)
		local r = ride(1, 3, true)
		local rest = refs.Root.Position
		RideView.pose(refs, r, r.Close + 0.05)
		T.eq(refs.Root.Position, rest, "no shake")
		for _, strip in refs.Strips do
			T.falsy(strip.Visible, "no sweeps")
		end
		T.near(refs.DoorLeft.Position.X.Scale, 0, 1e-6, "the doors still shut")
		RideView.pose(refs, r, r.MinRide - 0.01)
		T.eq(refs.Number.Text, "3", "the numbers still count")
	end)
end
