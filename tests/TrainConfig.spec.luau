-- Ore train config (step 2): levels, prices, trip times, the lines and stops.
return function(T, Loader)
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local CFrame = Loader.CFrame
	local Vector3 = (require("@lune/roblox") :: any).Vector3

	T.test("Train: the top train with Express fits the biggest Ore Pen (it never waits for room a pen can't have)", function()
		local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
		local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
		local pen = EconomyConfig.Pen
		local biggest = pen.BaseCapacity + #pen.Prices * pen.PerLevel
		local top = TrainConfig.capacity(TrainConfig.maxLevel(TrainConfig.Capacity), true)
		T.le(top, biggest, "the top train with Express")
		T.le(biggest, GameConfig.MaxStoredItems, "the pen within the save cap")
		T.le(top, TrainConfig.MaxCargoSaved, "the cargo within the save cap")
		-- the old train's levels stay as they were (saves don't jump)
		for i, value in { 8, 12, 18, 26, 36, 50 } do
			T.eq(TrainConfig.Capacity[i].Value, value, "old level " .. (i - 1))
		end
	end)

	T.test("Train: upgrades get better and pricier", function()
		for _, list in { TrainConfig.Capacity, TrainConfig.Speed } do
			T.eq(list[1].Price, 0, "level 0 is free")
			for i = 2, #list do
				T.lt(list[i - 1].Price, list[i].Price, "price " .. i)
			end
		end
		for i = 2, #TrainConfig.Capacity do
			T.lt(TrainConfig.Capacity[i - 1].Value, TrainConfig.Capacity[i].Value, "capacity " .. i)
		end
		for i = 2, #TrainConfig.Speed do
			T.lt(TrainConfig.Speed[i].Value, TrainConfig.Speed[i - 1].Value, "faster " .. i)
		end
	end)

	T.test("Train: capacity, trip time and next price helpers", function()
		T.eq(TrainConfig.capacity(0, false), 8)
		T.eq(TrainConfig.capacity(99, false), 120, "clamped high")
		T.eq(TrainConfig.capacity(0 / 0, false), 8, "NaN")
		T.eq(TrainConfig.capacity(0, true), 12, "Express +50 %")
		T.eq(TrainConfig.tripSeconds(0, false), 30)
		T.eq(TrainConfig.tripSeconds(0, true), 15, "Express halves the trip")
		T.eq(TrainConfig.tripSeconds(5, true), TrainConfig.MinTripSeconds + 1, "12 / 2 = 6")
		T.le(TrainConfig.MinTripSeconds, TrainConfig.tripSeconds(5, true))
		T.eq(TrainConfig.nextPrice(TrainConfig.Capacity, 0), 2000)
		T.eq(TrainConfig.nextPrice(TrainConfig.Capacity, TrainConfig.maxLevel(TrainConfig.Capacity)), nil, "maxed")
		T.eq(TrainConfig.nextPrice(TrainConfig.Speed, -5), 3000, "junk level counts as 0")
	end)

	T.test("Train: every plot's stop is on its coastal line, behind its yard", function()
		for _, plot in WorldLayout.Plots do
			local stop = TrainConfig.stopFor(plot)
			local line = TrainConfig.lineFor(plot)
			T.eq(stop.X, line[1].X, "on the line x")
			T.lt(TrainConfig.BufferZ, stop.Z, "south of the buffer stop")
			T.lt(stop.Z, TrainConfig.SouthPortalZ, "north of the south portal")
			-- the stop is the plot's rail point (BaseLayout.RailZ, local x 0)
			local rail = (WorldLayout.plotCFrame(plot) * CFrame.new(0, 0, BaseLayout.RailZ)).Position
			T.near(rail.X, stop.X, 1e-6, "plot " .. plot.Id .. " rail x")
			T.near(rail.Z, stop.Z, 1e-6, "plot " .. plot.Id .. " rail z")
		end
	end)

	T.test("Train: the coastal lines follow the plot grid", function()
		local grid = WorldLayout.PlotGrid
		local railX = grid.CenterX + BaseLayout.RailZ -- 166 at 12 cells
		local southmost = -math.huge
		for _, plot in WorldLayout.Plots do
			southmost = math.max(southmost, plot.Center.Z)
		end
		-- the south portal stays 42 studs past the south-most plot (126 at 12 cells): the
		-- trains' coming out and passing are timed for that leg; the buffer stop never moves
		T.eq(TrainConfig.SouthPortalZ, southmost + 42, "south portal")
		T.eq(TrainConfig.BufferZ, -100, "buffer stop")
		for _, pair in { { TrainConfig.CoastWest, -1 }, { TrainConfig.CoastEast, 1 } } do
			local line, side = pair[1], pair[2]
			T.eq(#line, 2, "a straight line")
			T.eq(line[1], Vector3.new(side * railX, 0, TrainConfig.SouthPortalZ), "starts at the south portal")
			T.eq(line[2], Vector3.new(side * railX, 0, TrainConfig.BufferZ), "ends at the buffer stop")
		end
		-- the rail and the portals stay on the island
		T.lt(railX, WorldLayout.Island.Max.X, "rail inside the island")
		T.lt(TrainConfig.SouthPortalZ, WorldLayout.Island.Max.Z, "portal inside the island")
	end)

	T.test("Train: the station, track and lifts are kept free of rocks", function()
		T.truthy(WorldLayout.isKeepOut(TrainConfig.Station.Hopper), "station")
		T.truthy(WorldLayout.isKeepOut(TrainConfig.QuarryStop), "quarry track")
		for _, lift in TrainConfig.Lifts do
			T.truthy(WorldLayout.isKeepOut(lift.Position), lift.Id .. " lift")
		end
		-- the station hopper sits on the quarry floor, off the ramp (x -8..8)
		T.eq(TrainConfig.Station.Hopper.Y, WorldLayout.Quarry.Min.Y)
		T.lt(8, TrainConfig.Station.Platform.Center.X - TrainConfig.Station.Platform.Size.X / 2)
		local t = TrainConfig.Timeline
		T.eq(t.QuarryLeg[1], 0)
		T.eq(t.Unload[2], 1)
		T.le(t.QuarryLeg[2], t.CoastLeg[1])
	end)
end
