-- MachineInfo (pure): what build mode's info card says about every machine,
-- the tray's power chips, the BUILD tile's count and the power preview maths.
return function(T, Loader)
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local MachineInfo = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineInfo")

	local function has(text: string?, part: string): boolean
		return text ~= nil and string.find(text, part, 1, true) ~= nil
	end

	T.test("MachineInfo: every machine has a name, category, size and description", function()
		for _, machine in MachineData.List do
			local info = MachineInfo.describe(machine.Id)
			T.truthy(info, machine.Id)
			T.eq(info.Id, machine.Id, "id")
			T.eq(info.Name, machine.Name, machine.Id .. " name")
			T.eq(info.Category, machine.Category, machine.Id .. " category")
			T.eq(info.Size, `{machine.Size[1]}x{machine.Size[2]} cells`, machine.Id .. " size")
			T.eq(info.Description, machine.Description, machine.Id .. " description")
			T.eq(info.PowerNeed, machine.Power or 0, machine.Id .. " power need")
			T.eq(info.PowerMake, machine.PowerOut or 0, machine.Id .. " power made")
			if info.Flow then
				T.truthy(has(info.Flow, " -> "), machine.Id .. " flow reads TAKES -> GIVES")
			end
		end
		T.falsy(MachineInfo.describe("NoSuchMachine"), "unknown id")
		T.falsy(MachineInfo.describe(42), "not a string")
	end)

	T.test("MachineInfo: takes, gives and seconds come from the data", function()
		local crusher = MachineInfo.describe("Crusher")
		T.eq(crusher.Takes, "Clean ore", "Accepts")
		T.eq(crusher.Gives, "2 Crushed ore", "Output x OutputCount")
		T.eq(crusher.Seconds, 3, "Time")
		T.eq(crusher.Flow, "Clean ore -> 2 Crushed ore · 3 s", "the card's line")
		T.eq(crusher.PowerText, MachineInfo.NoPowerText, "needs no power")
		T.eq(crusher.OutputText, MachineInfo.FrontText, "results out of the front")

		local furnace = MachineInfo.describe("ClayFurnace")
		T.eq(furnace.Flow, "Clean ore, Crushed ore -> Ingot · 6 s", "kinds in processing order")

		local blast = MachineInfo.describe("BlastFurnace")
		T.eq(blast.Flow, "Clean ore, Crushed ore -> Ingot · 2.5 s", "half seconds")

		local plasma = MachineInfo.describe("PlasmaFurnace")
		T.truthy(has(plasma.Flow, "(2 at once)"), "Batch")

		local alloy = MachineInfo.describe("AlloyFurnace")
		T.eq(alloy.Takes, "2 Ingots", "Inputs")
		T.eq(alloy.Gives, "Alloy", "one alloy")

		T.eq(MachineInfo.describe("SellBox").Takes, MachineInfo.AnyText, "many kinds: any item")
		T.eq(MachineInfo.describe("SellBox").Gives, "Coins", "behaviour text")
		T.eq(MachineInfo.describe("RestorationTable").Takes, "Dusty relics", "relics")
		T.eq(MachineInfo.describe("RobotArm").Takes, MachineInfo.TakesText.RobotArm, "no Accepts: its own text")

		local belt = MachineInfo.describe("Conveyor")
		T.falsy(belt.Flow, "a belt has no job")
		T.falsy(belt.PowerText, "no power line")
		T.eq(belt.OutputText, MachineInfo.BeltText, "arrows")
	end)

	T.test("MachineInfo: the power line and where results come out", function()
		local rules = MachineData.PowerRules
		local brick = MachineInfo.describe("BrickFurnace")
		T.eq(brick.PowerText, `Needs 10 power: a pole within {rules.PoleReach} cells, else 60% speed`, "a consumer")
		local wind = MachineInfo.describe("WindTurbine")
		T.truthy(has(wind.PowerText, "Makes 40 power"), "a generator: " .. tostring(wind.PowerText))
		local pole = MachineInfo.describe("PowerPole")
		T.truthy(has(pole.PowerText, `within {rules.PoleLink} cells`), "a pole links")
		T.eq(MachineInfo.describe("Splitter").OutputText, MachineInfo.SidesText, "side outputs")
		T.eq(MachineInfo.describe("Sorter").OutputText, MachineInfo.SidesText, "side outputs")
		T.eq(MachineInfo.describe("CleaningStation").OutputText, MachineInfo.TrayText, "the tray")
		T.falsy(MachineInfo.describe("SolarPanel").OutputText, "a generator makes no items")
	end)

	T.test("MachineInfo: tray power chips", function()
		T.eq(MachineInfo.powerChip("BrickFurnace"), "⚡10", "needs")
		T.eq(MachineInfo.powerChip("WindTurbine"), "+40⚡", "makes")
		T.eq(MachineInfo.powerChip("PowerPole"), "⚡", "a pole")
		T.falsy(MachineInfo.powerChip("Crusher"), "no part in power")
		T.falsy(MachineInfo.powerChip("Nope"), "unknown")
	end)

	T.test("MachineInfo: the BUILD tile counts every machine waiting to be placed", function()
		T.eq(MachineInfo.unplaced({ Crusher = 2, Conveyor = 24, ClayFurnace = 0 }), 26, "all kinds, not only the Cleaning Station")
		T.eq(MachineInfo.unplaced({ CleaningStation = 1 }), 1, "the station too")
		T.eq(
			MachineInfo.unplaced({ Fake = 3, Crusher = -1, Polisher = "2", Splitter = 0 / 0, Sorter = 1.7 }),
			1,
			"junk counts 0, halves floor"
		)
		T.eq(MachineInfo.unplaced({ Conveyor = 1e9 }), MachineData.MaxInventory, "capped like the save")
		T.eq(MachineInfo.unplaced(nil), 0, "no inventory")
		T.eq(MachineInfo.unplaced("x"), 0, "broken inventory")
	end)

	T.test("MachineInfo: power preview of a machine (powered or how slow)", function()
		local ghost = { Id = "BrickFurnace", X = 5, Z = 5, R = 0 }
		local alone = MachineInfo.powerPreview({}, ghost)
		T.eq(alone.State, "NoPole", "no pole")
		T.eq(alone.Text, "No pole in reach: runs at 60%", "the reason line")
		T.falsy(alone.Good, "yellow")
		T.near(alone.Speed, 0.6, 1e-9, "60%")

		local pole = { Id = "PowerPole", X = 4, Z = 4, R = 0 }
		local dead = MachineInfo.powerPreview({ pole }, ghost)
		T.eq(dead.State, "NoSupply", "a pole without a generator")
		T.falsy(dead.Good, "yellow")
		T.eq(dead.Pole, pole, "hangs on that pole")

		local solar = { Id = "SolarPanel", X = 1, Z = 1, R = 0 } -- 15 power, its cell (2, 2) is 2 cells from the pole
		local powered = MachineInfo.powerPreview({ pole, solar }, ghost)
		T.eq(powered.State, "Powered", "15 power for 10")
		T.eq(powered.Text, "Powered", "the reason line")
		T.truthy(powered.Good, "green")
		T.eq(powered.Speed, 1, "full speed")

		local plasma = MachineInfo.powerPreview({ pole, solar }, { Id = "PlasmaFurnace", X = 5, Z = 5, R = 0 })
		T.eq(plasma.State, "Slow", "15 power for 60")
		T.near(plasma.Speed, MachineData.powerSpeed(15, 60), 1e-9, "the server's speed")
		T.truthy(has(plasma.Text, "runs at 70%"), tostring(plasma.Text))
		T.falsy(plasma.Good, "yellow")

		-- a Speed upgrade makes the generator stronger (data.MachineUpgrades)
		local upgraded = MachineInfo.powerPreview(
			{ pole, solar },
			{ Id = "PlasmaFurnace", X = 5, Z = 5, R = 0 },
			{ SolarPanel = { Speed = 4 } }
		)
		T.near(upgraded.Speed, MachineData.powerSpeed(30, 60), 1e-9, "upgraded solar")

		local far = MachineInfo.powerPreview({ pole, solar }, { Id = "BrickFurnace", X = 9, Z = 9, R = 0 })
		T.eq(far.State, "NoPole", "4 cells away is out of reach")

		local crusher = MachineInfo.powerPreview({ pole, solar }, { Id = "Crusher", X = 5, Z = 5, R = 0 })
		T.eq(crusher.State, "None", "needs no power")
		T.falsy(crusher.Text, "nothing to say")
	end)

	T.test("MachineInfo: power preview of a pole (links, feeds) and a generator", function()
		local a = { Id = "PowerPole", X = 2, Z = 2, R = 0 }
		local b = { Id = "PowerPole", X = 12, Z = 12, R = 0 }
		local furnace = { Id = "BrickFurnace", X = 7, Z = 7, R = 0 }
		local preview = MachineInfo.powerPreview({ a, b, furnace }, { Id = "PowerPole", X = 6, Z = 6, R = 0 })
		T.eq(preview.State, "Links", "links")
		T.eq(#preview.Links, 2, "both poles within 6 cells")
		T.truthy(table.find(preview.Links, a) and table.find(preview.Links, b), "the entries themselves")
		T.eq(#preview.Feeds, 1, "the furnace hangs on the nearest pole: the new one")
		T.eq(preview.Feeds[1], furnace, "the furnace")
		T.truthy(has(preview.Text, "links 2 poles") or has(preview.Text, "Links 2 poles"), tostring(preview.Text))
		T.truthy(has(preview.Text, "no generator yet"), "no supply yet")
		T.falsy(preview.Good, "yellow without a generator")

		local lonely = MachineInfo.powerPreview({ b }, { Id = "PowerPole", X = 0, Z = 0, R = 0 })
		T.eq(lonely.State, "Alone", "12 cells from the other pole")
		T.eq(#lonely.Links, 0, "no links")

		local solar = MachineInfo.powerPreview({ a }, { Id = "SolarPanel", X = 3, Z = 3, R = 0 })
		T.eq(solar.State, "Feeds", "a generator in reach")
		T.eq(solar.Pole, a, "its pole")
		T.truthy(solar.Good, "green")
		local stray = MachineInfo.powerPreview({ b }, { Id = "SolarPanel", X = 0, Z = 0, R = 0 })
		T.eq(stray.State, "NoPole", "a generator out of reach")
		T.falsy(stray.Good, "yellow")
	end)

	T.test("MachineInfo: reach squares and preview lines", function()
		local x0, z0, x1, z1 = MachineInfo.area(1, 1, 3, 13)
		T.eq(x0 + z0, 0, "clamped at the plot's corner")
		T.eq(x1, 4, "3 cells right")
		T.eq(z1, 4, "3 cells up")
		x0, z0, x1, z1 = MachineInfo.area(6, 6, 3, 13)
		T.truthy(x0 == 3 and z0 == 3 and x1 == 9 and z1 == 9, "7 x 7 in the middle")
		x0, z0, x1, z1 = MachineInfo.area(12, 0, 6, 13)
		T.truthy(x0 == 6 and z0 == 0 and x1 == 12 and z1 == 6, "clamped to the far edge")

		local mx, mz, length, yaw = MachineInfo.segment(0.5, 0.5, 3.5, 4.5)
		T.near(mx, 2, 1e-9, "middle x")
		T.near(mz, 2.5, 1e-9, "middle z")
		T.near(length, 5, 1e-9, "3-4-5")
		T.near(math.sin(yaw) * length, 3, 1e-9, "turned along x")
		T.near(math.cos(yaw) * length, 4, 1e-9, "and z")
		local _, _, zero = MachineInfo.segment(2, 2, 2, 2)
		T.eq(zero, 0, "a point")
	end)
end
