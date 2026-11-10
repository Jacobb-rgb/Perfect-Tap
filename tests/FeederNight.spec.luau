-- Night Shift's machines on the Ore Feeder's ore (owner 2026-11-07, machine step 4):
-- the line a base has, the feeders feeding one ore every FeederSeconds of the work,
-- what comes out going into the pen while it has room, what stays in the feeder
-- (no machine for it, no room, a SECRET), the report and why nothing was made, and
-- the Night Shift window's Machines tile.
return function(T, Loader)
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
	local FeederNight = Loader.requirePath("ReplicatedStorage.Shared.Machines.FeederNight")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local NightShiftService = Loader.requirePath("ServerScriptService.Server.Services.NightShiftService")
	local NightShiftView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.NightShiftView")

	local function ore(kind: string, oreId: string?): any
		return { K = kind, O = oreId or "Gold", G = if kind == "Raw" then nil else "Clean" }
	end

	local function base(machines: { string }, feeder: { any }?): any
		local placed = {}
		for k, id in machines do
			table.insert(placed, { Id = id, X = k * 2, Z = 0, R = 0 })
		end
		if feeder then
			table.insert(placed, { Id = "OreFeeder", X = 0, Z = 4, R = 0, In = feeder })
		end
		return { PlacedMachines = placed, Upgrades = {}, MachineUpgrades = {}, Storage = {} }
	end

	local function half(): number
		return 0.5
	end

	T.test("feeder night: the line is the placed machines, each kind's fastest", function()
		local line = FeederNight.line(base({ "AutoCleaner", "Crusher", "ClayFurnace" }))
		T.eq(line.Raw.Machine, "AutoCleaner")
		T.eq(line.Clean.Machine, "Crusher")
		T.eq(line.Crushed.Machine, "ClayFurnace")
		T.eq(next(FeederNight.line(base({}))), nil, "no machines: no line")
		local twoCrushers = FeederNight.line(base({ "Crusher", "Crusher" }))
		T.near(twoCrushers.Clean.PerSecond, 2 * twoCrushers.Clean.Best, 1e-9, "two machines: twice the jobs")
	end)

	T.test("feeder night: one ore a FeederSeconds of work, out into the pen while it has room", function()
		local feeder = {}
		for _ = 1, 10 do
			table.insert(feeder, ore("Raw"))
		end
		local data = base({ "AutoCleaner", "Crusher", "ClayFurnace" }, feeder)
		local line = FeederNight.line(data)
		-- room for 5: an ore ends as 2 ingots (crushed x2), so 2 fit and the third stays
		local report = FeederNight.run(FeederNight.queues(data), data.Storage, line, 8 * 3600 * 0.25, 5, function()
			return nil
		end, half)
		T.eq(report.Fed, 2, "two ores fed")
		T.eq(#feeder, 8, "the rest stays in the feeder")
		T.eq(#data.Storage, 4, "4 pieces into the pen")
		T.eq(report.Bars, 4)
		T.eq(data.Storage[1].K, "Ingot")
		T.truthy(report.Cleaned.Gold, "out of the dirt: the codex finds it")
		-- the work caps the feeding: 3 FeederSeconds feed 3 ores (six Crushers: jobs to spare)
		local more = {}
		for _ = 1, 10 do
			table.insert(more, ore("Clean", "Coal"))
		end
		local d2 = base({ "Crusher", "Crusher", "Crusher", "Crusher", "Crusher", "Crusher" }, more)
		local r2 = FeederNight.run(FeederNight.queues(d2), d2.Storage, FeederNight.line(d2), 3 * MachineData.FeederSeconds, 300, function()
			return nil
		end, half)
		T.eq(r2.Fed, 3, "work / FeederSeconds")
		T.eq(#more, 7)
		T.eq(#d2.Storage, 6, "crushed x2 each")
		T.eq(r2.Bars, 0)
		T.eq(r2.Total, 6)
	end)

	T.test("feeder night: no machine for it, a SECRET, a job cap: the ore stays as it was", function()
		local secret = SecretOreConfig.List[1].Ore
		local feeder = { ore("Raw", "Gold"), ore("Clean", secret), ore("Clean", "Silver") }
		local data = base({ "Crusher" }, feeder)
		local report = FeederNight.run(FeederNight.queues(data), data.Storage, FeederNight.line(data), 3600, 300, function()
			return nil
		end, half)
		T.eq(report.Fed, 1, "only the clean Silver: no cleaner for the dirty Gold, never the secret")
		T.eq(#feeder, 2)
		T.eq(feeder[1].K, "Raw", "the dirty Gold kept, in its place")
		T.eq(feeder[2].O, secret, "the secret kept")
		-- a stage does at most PerSecond x work jobs
		local lots = {}
		for _ = 1, 50 do
			table.insert(lots, ore("Clean", "Coal"))
		end
		local d2 = base({ "Crusher" }, lots)
		local line = FeederNight.line(d2)
		local work = 40
		local cap = math.floor(line.Clean.PerSecond * work)
		local r2 = FeederNight.run(FeederNight.queues(d2), d2.Storage, line, work, 300, function()
			return nil
		end, half)
		T.eq(r2.Fed, math.min(cap, math.floor(work / MachineData.FeederSeconds)), "the Crusher's jobs")
	end)

	T.test("feeder night: Night Shift's return runs it at the offline rate, says why when nothing was made", function()
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local ok, err = pcall(function()
			local changed = 0
			patch(DataService, "changed", function()
				changed += 1
			end)
			patch(NightShiftService, "random", half)
			patch(NightShiftService, "clock", function()
				return 2e9
			end)
			local player: any = { Name = "Mia", UserId = 7, Parent = true }
			local function data(machines: { string }, feeder: { any }?): any
				local d = base(machines, feeder)
				d.NightShift = { CrateAt = 0, Ready = false }
				d.Stats = {}
				d.Discovered = {}
				return d
			end
			T.eq(NightShiftService.onReturn(player, data({ "Crusher" }), 7200, false).Why, "NoFeeder")
			T.eq(NightShiftService.onReturn(player, data({ "Crusher" }, {}), 7200, false).Why, "Empty")
			T.eq(NightShiftService.onReturn(player, data({}, { ore("Clean") }), 7200, false).Why, "NoMachines")
			local feeder = {}
			for _ = 1, 400 do
				table.insert(feeder, ore("Raw", "Gold"))
			end
			local d = data({ "AutoCleaner", "Crusher", "ClayFurnace" }, feeder)
			local seconds = 600 -- (short: the machines' jobs, not the pen, decide)
			local answer = NightShiftService.onReturn(player, d, seconds, false)
			local made = answer.Made
			T.truthy(made, "the machines made something")
			local work = seconds * EconomyConfig.offlineRate(false)
			T.truthy(made.Fed <= math.floor(work / MachineData.FeederSeconds), "never more than the feeder feeds at 25%")
			T.eq(#feeder, 400 - made.Fed)
			T.eq(made.Total, #d.Storage)
			T.truthy(#made.List >= 1 and #made.List <= NightShiftService.ListMax)
			T.eq(made.List[1].K, "Ingot")
			T.truthy(changed > 0, "saved")
			-- the pass: 50% for 12 h, more work
			local feeder2 = {}
			for _ = 1, 400 do
				table.insert(feeder2, ore("Raw", "Gold"))
			end
			local d2 = data({ "AutoCleaner", "Crusher", "ClayFurnace" }, feeder2)
			local withPass = NightShiftService.onReturn(player, d2, seconds, true).Made
			T.truthy(withPass.Fed > made.Fed, "the pass's 50%")
			-- a full pen
			local d3 = data({ "Crusher" }, { ore("Clean") })
			for _ = 1, EconomyConfig.penCapacity(nil, 10000) do
				table.insert(d3.Storage, ore("Clean", "Coal"))
			end
			T.eq(NightShiftService.onReturn(player, d3, seconds, false).Why, "PenFull")
		end)
		for k = #saved, 1, -1 do
			rawset(saved[k][1], saved[k][2], saved[k][3])
		end
		if not ok then
			error(err, 0)
		end
	end)

	T.test("feeder night: the window's Machines tile shows what was made, or why not", function()
		T.eq(NightShiftView.machinesText({ Total = 12, Bars = 12 }), "+12 bars")
		T.eq(NightShiftView.machinesText({ Total = 5, Bars = 2 }), "+5 items")
		T.eq(NightShiftView.machinesText(nil), "+0 bars")
		T.eq(NightShiftView.whyText("NoFeeder"), NightShiftView.Why.NoFeeder)
		T.eq(NightShiftView.whyText("Weird"), NightShiftView.WhyDefault)
		local refs = NightShiftView.build()
		NightShiftView.fill(refs, {
			Amount = 1000,
			Seconds = 3600,
			Hours = 8,
			Rate = 0.25,
			Made = { Fed = 6, Total = 12, Bars = 12, List = { { K = "Ingot", O = "Gold", G = "Clean", N = 12 } } },
		})
		T.eq(refs.Machines.Text, "+12 bars")
		T.falsy(refs.Empty.Visible, "rows, not the hint")
		T.truthy(refs.Rows:FindFirstChild("Row1"), "one row")
		NightShiftView.fill(refs, { Amount = 1000, Seconds = 3600, Hours = 8, Rate = 0.25, Why = "Empty" })
		T.truthy(refs.Empty.Visible)
		T.eq(refs.Empty.Text, NightShiftView.Why.Empty)
		T.eq(refs.Rows:FindFirstChild("Row1"), nil, "old rows cleared")
		T.truthy(NightShiftView.Size.Y * 0.62 <= 390 - 24, "fits a phone held sideways")
		for _, d in refs.Gui:GetDescendants() do
			if d:IsA("TextLabel") and d.Text ~= "" then
				T.truthy(d.TextSize * 0.62 >= 10, d.Name .. " " .. d.TextSize)
			end
		end
	end)
end
