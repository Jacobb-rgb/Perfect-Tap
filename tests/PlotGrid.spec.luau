--[[
	The plot grid block (WorldLayout.PlotGrid, bigger plots): the derived numbers match
	the plan's golden values for 12 and 16 cells, the plots and the island follow it,
	and the town core (plaza, quarry, rim road) never moves.
]]
return function(T, Loader)
	local Vector3 = (require("@lune/roblox") :: any).Vector3
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")

	-- the plan's numbers (build/reviews/bigger_plots_plan.md, option B)
	local GOLDEN = {
		[12] = { Half = 24, CenterX = 104, Pitch = 56, SouthZ = 112, CoastShift = 0, SouthShift = 0, Zs = { 84, 28, -28, -84 } },
		[16] = { Half = 32, CenterX = 112, Pitch = 72, SouthZ = 176, CoastShift = 16, SouthShift = 64, Zs = { 140, 68, -4, -76 } },
	}

	T.test("plot grid: the derived numbers match the plan for this PlotCells", function()
		local g = WorldLayout.PlotGrid
		local want = GOLDEN[GameConfig.PlotCells]
		T.truthy(want, `a golden row for PlotCells {GameConfig.PlotCells}`)
		T.eq(GameConfig.PlotCells % 2, 0, "an even grid (the save shift is half the growth)")
		for _, key in { "Half", "CenterX", "Pitch", "SouthZ", "CoastShift", "SouthShift" } do
			T.eq(g[key], want[key], key)
		end
		T.eq(g.FrontX, 79, "the pad front never moves")
		T.eq(g.NorthZ, -112, "the column north end never moves")
		-- plots: 4 per side, south -> north, ids 1-4 west then 5-8 east
		T.eq(#WorldLayout.Plots, 8)
		for id, plot in WorldLayout.Plots do
			local side = if id <= 4 then -1 else 1
			local i = (id - 1) % 4 + 1
			T.eq(plot.Id, id)
			T.eq(plot.Center.X, side * want.CenterX, `plot {id} x`)
			T.eq(plot.Center.Z, want.Zs[i], `plot {id} z`)
			T.eq(plot.Facing, Vector3.new(-side, 0, 0), `plot {id} faces the road`)
			-- the pad's road-side edge stays at |x| 79 (+1 for the pad lip)
			T.eq(math.abs(plot.Center.X) - g.Half - 1, g.FrontX, `plot {id} front`)
		end
		-- the island grows with the coast and the south band only
		T.eq(WorldLayout.Island.Max.X, 170 + want.CoastShift)
		T.eq(WorldLayout.Island.Min.X, -170 - want.CoastShift)
		T.eq(WorldLayout.Island.Max.Z, 150 + want.SouthShift)
		T.eq(WorldLayout.Island.Min.Z, -500, "the north (mountains, mine) never moves")
		-- the town core is untouched
		T.eq(WorldLayout.Plaza.Center, Vector3.new(0, 0, 0))
		T.eq(WorldLayout.Quarry.RampFrom, Vector3.new(0, 0, -112))
	end)
end
