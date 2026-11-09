-- The Ore Feeder (owner 2026-11-07, machine step 3): its data and prices (his own,
-- never x2), what it takes (only ore you put in or drop in, never a dirty SECRET,
-- never from a belt or a machine), its capacity by level, one ore out per
-- FeederSeconds while the outlet is free, the Capacity row in the upgrade window,
-- the counter's text, and its model (steel + blue, the outlet, the funnel, the counter).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local fs = require("@lune/fs")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local FeederService = Loader.requirePath("ServerScriptService.Server.Services.FeederService")
	local View = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineUpgradeView")
	local FeederController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.FeederController")

	local USER = 4242

	T.test("Ore Feeder: his prices and sizes (never x2), one ore a second", function()
		local feeder = MachineData.ById.OreFeeder
		T.truthy(feeder, "in the roster")
		T.eq(feeder.Price, 50000000, "50M, as he said (PriceKept)")
		T.truthy(MachineData.PriceKept.OreFeeder)
		T.eq(feeder.Behaviour, "Feeder")
		T.eq(feeder.Size[1], 2)
		local capacity = feeder.Upgrades.Capacity
		T.eq(capacity[1], 500000000)
		T.eq(capacity[2], 5000000000)
		T.eq(capacity[3], 50000000000)
		T.eq(MachineData.feederCapacity(0), 200)
		T.eq(MachineData.feederCapacity(1), 500)
		T.eq(MachineData.feederCapacity(2), 700)
		T.eq(MachineData.feederCapacity(3), 1000)
		T.eq(MachineData.feederCapacity(9), 1000, "clamped")
		T.eq(MachineData.feederCapacity(0 / 0), 200, "broken: level 0")
		T.eq(MachineData.FeederSeconds, 1)
		T.eq(feeder.LoadMax, 1000, "one Put In takes a whole backpack")
		T.truthy(table.find(MachineData.UpgradeKinds, "Capacity"))
		T.eq(EconomyConfig.techItem("Upgrade:OreFeeder:Capacity").Prices, capacity, "sold at the machine")
		T.eq(EconomyConfig.techItem("OreFeeder").Kind, "Machine", "the machine itself in the shop")
		local intake = fs.readFile("src/server/Services/IntakeService.luau")
		T.truthy(intake:find("machine.Info.LoadMax or MAX_LOAD", 1, true), "Put In honours LoadMax")
	end)

	-- a placed feeder of a fake player with a real Model (attributes)
	local function world(level: number?): any
		local w: any = { pushed = {}, changed = 0 }
		w.player = { UserId = USER, Name = "Feeder" }
		w.data = { MachineUpgrades = { OreFeeder = { Capacity = level or 0 } } }
		local model = Instance.new("Model")
		w.machine = {
			Id = "OreFeeder",
			Info = MachineData.ById.OreFeeder,
			Owner = w.player,
			Entry = { Id = "OreFeeder", X = 0, Z = 0, R = 0, In = {} },
			State = {},
			Model = model,
			Removed = false,
		}
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(MachineService, "pushOut", function(machine, desc)
			local out = machine.Entry.Out or {}
			machine.Entry.Out = out
			table.insert(out, desc)
			table.insert(w.pushed, desc)
		end)
		w.restore = function()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	local function guarded(w: any, fn: () -> ())
		local ok, err = pcall(fn)
		w.restore()
		if not ok then
			error(err, 0)
		end
	end

	local function ore(kind: string, oreId: string?): any
		return { K = kind, O = oreId or "Gold", G = if kind == "Raw" then nil else "Clean" }
	end

	T.test("Ore Feeder: takes only ore you put in or drop in, never a dirty SECRET, up to its capacity", function()
		local w = world()
		guarded(w, function()
			local m = w.machine
			local behaviour = FeederService._test.behaviour
			for _, kind in { "Raw", "Clean", "Crushed" } do
				T.truthy(FeederService.accepts(m, ore(kind), USER, "Hand"), kind .. " from your hands")
			end
			T.truthy(FeederService.accepts(m, ore("Raw"), USER, "Drop"), "dropped into its funnel")
			for _, via in { "Belt", "Machine" } do
				local ok, why = FeederService.accepts(m, ore("Raw"), USER, via)
				T.falsy(ok, via .. ": only what you put in")
				T.eq(why, "Wrong")
			end
			T.eq(select(2, FeederService.accepts(m, ore("Raw"), 999, "Hand")), "Foreign")
			T.falsy(FeederService.accepts(m, { K = "Ingot", O = "Gold", G = "Clean" }, USER, "Hand"), "no ingots")
			local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
			local secret = SecretOreConfig.List[1].Ore
			T.falsy(FeederService.accepts(m, ore("Raw", secret), USER, "Hand"), "a dirty SECRET is cleaned by hand")
			-- fill it to 200 through the behaviour's insert
			for _ = 1, 200 do
				behaviour.insert(m, ore("Clean"), USER, "Hand")
			end
			T.eq(#m.Entry.In, 200)
			T.eq(m.Model:GetAttribute("Stored"), 200, "the counter")
			T.eq(m.Model:GetAttribute("Capacity"), 200)
			T.truthy(w.changed >= 200, "every ore saved")
			local ok, why = FeederService.accepts(m, ore("Clean"), USER, "Hand")
			T.falsy(ok, "full at 200")
			T.eq(why, "Full")
			w.data.MachineUpgrades.OreFeeder.Capacity = 1
			T.truthy(FeederService.accepts(m, ore("Clean"), USER, "Hand"), "Capacity 1: 500")
			T.eq(FeederService.capacityOf(w.player), 500)
		end)
	end)

	T.test("Ore Feeder: one ore to the outlet every FeederSeconds, only while the outlet is free", function()
		local w = world()
		guarded(w, function()
			local m = w.machine
			local tick = FeederService._test.tick
			local behaviour = FeederService._test.behaviour
			for _, oreId in { "Gold", "Silver", "Coal" } do
				behaviour.insert(m, ore("Clean", oreId), USER, "Hand")
			end
			T.truthy(behaviour.busy(m, 0), "busy with ore in it")
			tick(m, 10)
			T.eq(#w.pushed, 1, "the first one out")
			T.eq(w.pushed[1].O, "Gold", "in the order put in")
			tick(m, 20)
			T.eq(#w.pushed, 1, "the outlet still holds one: wait")
			m.Entry.Out = {}
			tick(m, 20)
			T.eq(#w.pushed, 2, "the outlet free: the next")
			m.Entry.Out = {}
			tick(m, 20.5)
			T.eq(#w.pushed, 2, "not before FeederSeconds")
			tick(m, 21)
			T.eq(#w.pushed, 3)
			T.eq(w.pushed[3].O, "Coal")
			T.falsy(behaviour.busy(m, 22), "empty: it rests")
			T.eq(m.Model:GetAttribute("Stored"), 1, "the one at the outlet still counts")
		end)
	end)

	T.test("Ore Feeder: the Capacity row at the machine, the counter's text", function()
		local rows = View.rows("OreFeeder", { MachineUpgrades = {}, Upgrades = {} }, 1e9)
		T.eq(#rows, 1, "Capacity only (no job time: no Bellows)")
		T.eq(rows[1].Title, "Capacity")
		T.eq(rows[1].Change, "200 → 500 ores")
		T.eq(rows[1].Price, 500000000)
		T.eq(rows[1].Next, 1)
		local top = View.rows("OreFeeder", { MachineUpgrades = { OreFeeder = { Capacity = 3 } } }, 0)[1]
		T.eq(top.Level, "MAX")
		T.eq(top.Change, "1000 ores")
		T.truthy(View.has("OreFeeder"), "its Upgrades prompt")
		T.eq(View.titleOf("OreFeeder"), "Ore Feeder Upgrades")
		T.eq(FeederController.text(142, 200), "142 / 200")
		T.eq(FeederController.text(nil, 500), "0 / 500")
		T.eq(FeederController.text(5, nil), "", "before the server says")
	end)

	T.test("Ore Feeder: its model in steel + blue, with the outlet, the funnel and the counter", function()
		local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
		local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
		T.truthy(KitMachines.SteelLook.OreFeeder, "steel + blue (his look B)")
		local model = MachineBuilder.build("OreFeeder", 0, nil)
		local base = model.PrimaryPart
		for _, name in { "Output", "Prompt", "Intake" } do
			T.truthy(base:FindFirstChild(name), name)
		end
		local parts, screens, frame = 0, 0, nil
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d:HasTag("FeederScreen") then
					screens += 1
				end
				if d.Name == "Rim" then
					frame = d.Color
				end
			end
		end
		T.eq(screens, 1, "one counter")
		T.eq(frame, KitMachines.Steel.Frame, "steel")
		T.truthy(parts <= 60, `{parts} parts`)
		T.eq(model:GetAttribute("MachineId"), "OreFeeder")
	end)
end
