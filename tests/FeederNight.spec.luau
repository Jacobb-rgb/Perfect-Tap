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
		-- (review 11-10) a Polisher's or an Extractor's output is what it took: never a stage,
		-- whichever stands first
		local crusherAlone = FeederNight.line(base({ "Crusher" })).Clean.PerSecond
		for _, other in { "Polisher", "CrystalExtractor" } do
			for _, order in { { other, "Crusher" }, { "Crusher", other } } do
				local line = FeederNight.line(base(order))
				T.eq(line.Clean.Machine, "Crusher", `{order[1]} then {order[2]}`)
				T.near(line.Clean.PerSecond, crusherAlone, 1e-9, `{other} adds no jobs`)
			end
			T.eq(next(FeederNight.line(base({ other }))), nil, `{other} alone: no line`)
		end
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
		T.truthy(report.RoomStopped, "the pen's room stopped it")
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
		T.falsy(r2.RoomStopped, "the work, not the room")
		-- (review 11-10) every feeder feeds at its own pace, as online: two feeders, twice the ores
		local a, b = {}, {}
		for _ = 1, 10 do
			table.insert(a, ore("Clean", "Coal"))
			table.insert(b, ore("Clean", "Coal"))
		end
		local crushers = {}
		for _ = 1, 12 do
			table.insert(crushers, "Crusher") -- (jobs to spare: the feeders decide)
		end
		local d3 = base(crushers, a)
		table.insert(d3.PlacedMachines, { Id = "OreFeeder", X = 6, Z = 4, R = 0, In = b })
		local r3 = FeederNight.run(FeederNight.queues(d3), d3.Storage, FeederNight.line(d3), 3 * MachineData.FeederSeconds, 300, function()
			return nil
		end, half)
		T.eq(r3.Fed, 6, "3 from each feeder")
		T.eq(#a, 7)
		T.eq(#b, 7)
	end)

	T.test("feeder night: an Iron Box keeps what the player keeps, into the pen clean, never smelted (review 11-10)", function()
		T.eq(MachineData.Keep.Default, "RarePlus")
		local feeder = { ore("Raw", "RoyalAurum"), ore("Raw", "Coal"), ore("Clean", "RoyalAurum") }
		local data = base({ "AutoCleaner", "IronBox", "Crusher", "ClayFurnace" }, feeder)
		data.KeepMode = "RarePlus"
		local function keep(desc: any): boolean
			return MachineData.keeps(data.KeepMode, data.KeepList, desc)
		end
		local report = FeederNight.run(FeederNight.queues(data), data.Storage, FeederNight.line(data), 3600, 300, function()
			return nil
		end, half, keep)
		T.eq(report.Fed, 3)
		T.eq(#feeder, 0)
		local clean, bars = 0, 0
		for _, item in data.Storage do
			if item.K == "Clean" and item.O == "RoyalAurum" then
				clean += 1
			elseif item.K == "Ingot" and item.O == "Coal" then
				bars += 1
			end
		end
		T.eq(clean, 2, "both Royal Aurum kept clean (the dirty one cleaned first)")
		T.eq(bars, 2, "the Coal still smelted: crushed x2")
		T.eq(#data.Storage, 4, "nothing else")
		T.truthy(report.Cleaned.RoyalAurum, "the dirty one came out of the dirt")
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
			T.eq(NightShiftService.onReturn(player, data({ "Polisher" }, { ore("Clean") }), 7200, false).Why, "NoMachines")
			-- the Iron Box, through the real return: a dirty Royal Aurum ends clean in the pen
			local boxed = data({ "AutoCleaner", "IronBox", "Crusher", "ClayFurnace" }, { ore("Raw", "RoyalAurum") })
			T.truthy(NightShiftService.onReturn(player, boxed, 7200, false).Made, "made")
			T.eq(#boxed.Storage, 1)
			T.eq(boxed.Storage[1].K, "Clean", "kept, not smelted")
			local unboxed = data({ "AutoCleaner", "Crusher", "ClayFurnace" }, { ore("Raw", "RoyalAurum") })
			NightShiftService.onReturn(player, unboxed, 7200, false)
			T.eq(unboxed.Storage[1].K, "Ingot", "without a box the line smelts it")
			local feeder = {}
			for _ = 1, 400 do
				table.insert(feeder, ore("Raw", "Gold"))
			end
			local d = data({ "AutoCleaner", "Crusher", "ClayFurnace" }, feeder)
			-- (review 11-10) ore already in the pen is never taken: only the feeder's
			local before = { ore("Raw", "Gold"), ore("Raw", "Gold"), ore("Clean", "Coal") }
			for _, item in before do
				table.insert(d.Storage, item)
			end
			-- no crate today (one a day): the save mark comes from the machines' work
			d.NightShift.CrateAt = 2e9
			changed = 0
			local seconds = 600 -- (short: the machines' jobs, not the pen, decide)
			local answer = NightShiftService.onReturn(player, d, seconds, false)
			local made = answer.Made
			T.truthy(made, "the machines made something")
			T.falsy(answer.Crate, "no crate this time")
			T.truthy(changed > 0, "the machines' work saved")
			for k, item in before do
				T.eq(d.Storage[k], item, "the pen's own ore untouched")
				T.eq(item.K, if k == 3 then "Clean" else "Raw")
			end
			T.truthy(d.Discovered.Gold, "the codex finds the cleaned Gold")
			T.eq(made.Left, #feeder, "what's still in the feeder")
			local work = seconds * EconomyConfig.offlineRate(false)
			T.truthy(made.Fed <= math.floor(work / MachineData.FeederSeconds), "never more than the feeder feeds at 25%")
			T.eq(#feeder, 400 - made.Fed)
			T.eq(made.Total, #d.Storage - #before)
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
			-- (review 11-10) one place left and every ore needs two: the pen, not "nothing to do"
			local d4 = data({ "AutoCleaner", "Crusher", "ClayFurnace" }, { ore("Raw", "Gold") })
			for _ = 1, EconomyConfig.penCapacity(nil, 10000) - 1 do
				table.insert(d4.Storage, ore("Clean", "Coal"))
			end
			T.eq(NightShiftService.onReturn(player, d4, seconds, false).Why, "PenFull")
			-- the hours and the rate (owner: 25 % for 8 h, 50 % for 12 h with the pass)
			local works = {}
			patch(FeederNight, "run", function(_q, _s, _l, work: number)
				table.insert(works, work)
				return { Fed = 0, Total = 0, Bars = 0, Made = {}, Cleaned = {}, RoomStopped = false }
			end)
			for _, case in
				{ { 28800, false, 7200 }, { 28801, false, 7200 }, { 43200, true, 21600 }, { 43201, true, 21600 }, { 3600, true, 1800 } }
			do
				table.clear(works)
				NightShiftService.onReturn(player, data({ "Crusher" }, { ore("Clean") }), case[1], case[2])
				T.near(works[1], case[3], 1e-6, `{case[1]} s, pass {case[2]}`)
			end
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
		T.eq(refs.Rows.Row1.Count.Text, "x12", "its count")
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
