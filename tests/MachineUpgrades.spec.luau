-- A machine's upgrades at the machine (owner 2026-11-07): the doubled prices
-- (MachineData.PriceMult: machines you can buy and their Speed / Quality / tier
-- lists; not the belts and line pieces, the droppers or retired machines), the
-- window's rows (MachineUpgradeView.rows: level, now > next, why, the next price
-- and level, MAX), which machines get the "Upgrades" prompt, where it goes next
-- to "Put In" (MachineUpgradeView.placement, PromptConfig.setRole), the
-- window's phone sizes and that every text fits its box. ShopService's side
-- (sold only at one of your own machines) is in ShopService.spec.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Enum = roblox.Enum
	local Vector2 = roblox.Vector2
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local PromptConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.PromptConfig")
	local View = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineUpgradeView")
	local Pop = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Pop")
	local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")
	local fs = require("@lune/fs")

	local PHONE = 0.62 -- HudController.uiScale's floor

	local function state(over: { [string]: any }?): { [string]: any }
		local s: { [string]: any } = {
			Coins = 0,
			MachineUpgrades = {},
			Upgrades = { Bellows = 0, ExtraSlots = 0, PenLevel = 0, PenAutomation = 0 },
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	local function rowOf(rows: { any }, item: string): any
		for _, r in rows do
			if r.Item == item then
				return r
			end
		end
		return nil
	end

	T.test("Machine upgrades: machines and their upgrades cost twice as much (owner 2026-11-07)", function()
		T.eq(MachineData.PriceMult, 2)
		-- the base curves stay (a retired look's refund), a machine you can buy pays them x2
		local speed, quality = MachineData.UpgradeCurves.Speed, MachineData.UpgradeCurves.Quality
		T.eq(speed[1], 20000)
		T.eq(quality[1], 50000)
		local was = { Crusher = 1500, ClayFurnace = 500, AutoCleaner = 25000, SolarPanel = 4000, Splitter = 3000, FusionReactor = 10000000 }
		for id, price in was do
			T.eq(MachineData.ById[id].Price, price * 2, id .. " x2")
		end
		T.eq(MachineData.ById.Crusher.Upgrades.Speed[1], speed[1] * 2, "Crusher Speed 1")
		T.eq(MachineData.ById.AutoCleaner.Upgrades.Quality[5], quality[5] * 2, "Cleaning Plant Quality 5")
		local tier = MachineData.ById.ClayFurnace.Upgrades.Tier
		T.eq(tier[1], 12000)
		T.eq(tier[2], 60000)
		T.eq(tier[3], 10000000)
		T.eq(MachineData.Bellows.Prices[1], 1000)
		T.eq(MachineData.Bellows.Prices[5], 50000)
		-- kept: the line's pieces, the droppers, retired machines
		local kept = { Conveyor = 25, ExpressConveyor = 150, BeltLift = 150, Slide = 150, Platform = 2500, PowerPole = 500 }
		for id, price in kept do
			T.eq(MachineData.ById[id].Price, price, id .. " kept")
			T.truthy(MachineData.PriceKept[id], id .. " listed")
		end
		T.eq(MachineData.ById.BasicDropper.Price, 5e9, "droppers keep their prices")
		T.eq(MachineData.ById.BlastFurnace.Upgrades.Speed[1], speed[1] * 4, "a retired look keeps its old list")
		-- the shop's quotes are the same lists
		T.eq(EconomyConfig.techItem("Upgrade:Crusher:Speed").Prices, MachineData.ById.Crusher.Upgrades.Speed)
		T.eq(EconomyConfig.techItem("Bellows").Prices, MachineData.Bellows.Prices)
	end)

	T.test("Machine upgrades: which machines get the Upgrades prompt", function()
		for _, id in
			{ "ClayFurnace", "Crusher", "AutoCleaner", "IronBox", "Polisher", "SolarPanel", "Splitter", "RobotArm", "RestorationTable" }
		do
			T.truthy(View.has(id), id)
		end
		-- every belt holds the one belt's levels (owner 2026-11-07)
		for _, id in { "Conveyor", "ExpressConveyor", "BeltLift", "Slide" } do
			T.truthy(View.has(id), id .. ": a belt")
			T.eq(MachineData.upgradeHolder(id), "Conveyor")
			local rows = View.rows(id, state(), 150000)
			T.eq(#rows, 1, id .. ": one row")
			T.eq(rows[1].Item, "Upgrade:Conveyor:Speed")
			T.eq(rows[1].Title, "Belt Speed")
			T.eq(rows[1].Change, "x1 → x1.5")
			T.eq(rows[1].Price, 100000)
			T.truthy(rows[1].Affordable)
			T.eq(View.titleOf(id), "Belt Upgrades")
			T.eq(View.noteOf(id), "All your belts get it")
		end
		local top = View.rows("Slide", state({ MachineUpgrades = { Conveyor = { Speed = 2 } } }), 0)[1]
		T.eq(top.Level, "MAX")
		T.eq(top.Change, "x2")
		T.eq(View.titleOf("ClayFurnace", 2), "Blast Furnace Upgrades")
		for _, id in { "CleaningStation", "SellBox", "PowerPole", "Platform", "BasicDropper", "Nope" } do
			T.falsy(View.has(id), id)
		end
		-- every machine with a Speed / Quality / tier upgrade or a job time has rows
		for _, machine in MachineData.Buildable do
			T.eq(#View.rows(machine.Id, state(), 0) > 0, View.has(machine.Id), machine.Id .. ": rows when it has a prompt")
		end
	end)

	T.test("Machine upgrades: a row says the level, now > next, why, and the next price", function()
		local s = state({
			MachineUpgrades = { ClayFurnace = { Speed = 2, Tier = 1 }, AutoCleaner = { Quality = 5 } },
			Upgrades = { Bellows = 3 },
		})
		local furnace = View.rows("ClayFurnace", s, 1e6)
		T.eq(#furnace, 3, "Speed, the tier, Bellows")
		local speed = rowOf(furnace, "Upgrade:ClayFurnace:Speed")
		local brick = MachineData.info("ClayFurnace", 1)
		T.eq(speed.Title, "Speed")
		T.eq(speed.Level, "LV 2 / 5")
		T.eq(speed.Change, string.format("%.1f s → %.1f s", MachineData.processTime(brick, 3, 2), MachineData.processTime(brick, 3, 3)))
		T.eq(speed.Why, View.Why.ClayFurnace)
		T.eq(speed.Next, 3)
		T.eq(speed.Price, MachineData.ById.ClayFurnace.Upgrades.Speed[3])
		T.eq(speed.Affordable, 1e6 >= speed.Price)
		local tier = rowOf(furnace, "Upgrade:ClayFurnace:Tier")
		T.eq(tier.Title, "Blast Furnace", "the furnace it turns into")
		T.eq(tier.Level, "LV 1 / 3")
		T.eq(tier.Why, "Much faster, needs power")
		T.eq(tier.Price, 60000)
		T.truthy(tier.Affordable)
		local bellows = rowOf(furnace, "Bellows")
		T.eq(bellows.Change, "-30% → -40%")
		T.eq(bellows.Why, View.Why.Bellows)
		T.eq(bellows.Next, 4)
		-- the top: MAX, no price, just the value
		local plant = View.rows("AutoCleaner", s, 1e12)
		local quality = rowOf(plant, "Upgrade:AutoCleaner:Quality")
		T.eq(quality.Level, "MAX")
		T.eq(quality.Price, nil)
		T.eq(quality.Next, nil)
		T.falsy(quality.Affordable)
		T.eq(quality.Change, "Flawless 30%")
		local q0 = rowOf(View.rows("AutoCleaner", state(), 0), "Upgrade:AutoCleaner:Quality")
		T.eq(q0.Change, "Clean 40% → Pristine 5%", "the best grade it makes now and next")
		T.falsy(q0.Affordable, "no coins")
		local plasma =
			rowOf(View.rows("ClayFurnace", state({ MachineUpgrades = { ClayFurnace = { Tier = 2 } } }), 0), "Upgrade:ClayFurnace:Tier")
		T.eq(plasma.Title, "Plasma Furnace")
		T.eq(plasma.Why, "2 at once, needs power")
		local top =
			rowOf(View.rows("ClayFurnace", state({ MachineUpgrades = { ClayFurnace = { Tier = 3 } } }), 0), "Upgrade:ClayFurnace:Tier")
		T.eq(top.Level, "MAX")
		T.eq(top.Why, "The best furnace there is")
		-- generators: power; belt helpers: x speed; no Bellows on either
		local solar = View.rows("SolarPanel", state(), 0)
		T.eq(#solar, 1)
		T.eq(solar[1].Title, "Power")
		T.eq(solar[1].Change, "15 → 19 power")
		local splitter = View.rows("Splitter", state(), 0)
		T.eq(#splitter, 1)
		T.eq(splitter[1].Change, "x1.00 → x1.14")
		-- broken saves read as level 0, never an error
		for _, junk in { nil, 5, "x", { MachineUpgrades = "x", Upgrades = 7 }, { MachineUpgrades = { Crusher = { Speed = 0 / 0 } } } } do
			local rows = View.rows("Crusher", junk, 0 / 0)
			T.eq(rows[1].Level, "LV 0 / 5")
			T.falsy(rows[1].Affordable)
		end
		T.eq(#View.rows("Nope", state(), 0), 0)
	end)

	T.test("Machine upgrades: every row's price and level are the server's (EconomyConfig)", function()
		for _, machine in MachineData.Buildable do
			for level = 0, 5 do
				local s = state({
					MachineUpgrades = { [machine.Id] = { Speed = level, Quality = level, Tier = math.min(level, 3) } },
					Upgrades = { Bellows = level },
				})
				for _, r in View.rows(machine.Id, s, 1e15) do
					local entry = EconomyConfig.techItem(r.Item)
					T.truthy(entry, r.Item)
					local now, max = EconomyConfig.techLevel(entry, s)
					if now < max then
						T.eq(r.Next, now + 1, r.Item .. " next")
						T.eq(r.Price, entry.Prices[now + 1], r.Item .. " price")
						T.truthy(r.Affordable)
					else
						T.eq(r.Level, "MAX", r.Item .. " max")
					end
				end
			end
		end
	end)

	T.test("Machine upgrades: Upgrades steps aside for Put In (PromptConfig roles)", function()
		T.eq(select(1, View.placement(false, false)), "Main", "E while Put In is hidden")
		T.eq(select(2, View.placement(false, true)), 0)
		local role, slot = View.placement(true, false)
		T.eq(role, "Panel", "T / L3 while Put In has E")
		T.eq(slot, 1)
		T.eq(select(2, View.placement(true, true)), 2, "under a Keep List / Change Sort")
		-- a rebuilt machine (a Speed level, a tier) is found again by its spot
		T.eq(View.spotKey(501, "Crusher", 3, 4, nil), View.spotKey(501, "Crusher", 3, 4, 0), "the ground is level 0")
		T.truthy(View.spotKey(501, "Crusher", 3, 4, 0) ~= View.spotKey(501, "Crusher", 3, 4, 1), "a deck above is another spot")
		T.truthy(View.spotKey(501, "Crusher", 3, 4, 0) ~= View.spotKey(502, "Crusher", 3, 4, 0), "another player's")
		T.truthy(View.spotKey(501, "Crusher", 3, 4, 0) ~= View.spotKey(501, "Polisher", 3, 4, 0), "another machine")
		T.eq(View.spotKey(nil, {}, nil, nil, nil), "?|?|?|?|0")
		local prompt = PromptConfig.make({ Name = "UpgradePrompt" })
		T.eq(prompt.KeyboardKeyCode, Enum.KeyCode.E)
		PromptConfig.setRole(prompt, "Panel", 2)
		T.eq(prompt.KeyboardKeyCode, Enum.KeyCode.T)
		T.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonL3)
		T.eq(prompt.UIOffset, Vector2.new(0, 2 * PromptConfig.SlotHeight))
		PromptConfig.setRole(prompt, "Main", 0)
		T.eq(prompt.KeyboardKeyCode, Enum.KeyCode.E)
		T.eq(prompt.UIOffset, Vector2.new(0, 0))
		T.truthy(
			View.CloseRange + 2 <= Loader.requirePath("ServerScriptService.Server.Services.ShopService").MachineRange,
			"the server is the lenient side"
		)
		T.truthy(table.find(MenuPanels.Names, "MachineUpgradeController"), "a MenuPanels panel")
		local init = fs.readFile("src/client/init.client.luau")
		T.truthy(string.find(init, '"MachineUpgradeController"', 1, true), "in the client ORDER")
	end)

	T.test("Machine upgrades: the window on a phone (44 pt buttons, 10 pt texts, everything fits)", function()
		local refs = View.build()
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.eq(refs.Close.Size.X.Offset * PHONE >= 44, true, "the X's hit area")
		local s = state({ MachineUpgrades = { ClayFurnace = { Speed = 1 } }, Upgrades = { Bellows = 1 } })
		View.fill(refs, "Furnace Upgrades", View.rows("ClayFurnace", s, 1e9))
		T.eq(#refs.Rows, 3)
		T.truthy(View.height(3) * PHONE <= 390 - 24, "three rows fit a phone held sideways")
		for _, r in refs.Rows do
			T.truthy(r.Frame.Visible)
			T.truthy(r.Buy.Visible and r.Buy.Active, "affordable")
			T.truthy(r.Buy.Size.Y.Offset * PHONE >= 44, "BUY 44 pt")
		end
		for _, d in refs.Gui:GetDescendants() do
			if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
				T.truthy(d.TextSize * PHONE >= 10, d.Name .. " " .. d.TextSize)
			end
		end
		-- a MAX row hides its BUY; fewer rows hide the rest
		View.fill(refs, "Solar Panel Upgrades", View.rows("SolarPanel", state({ MachineUpgrades = { SolarPanel = { Speed = 5 } } }), 0))
		T.falsy(refs.Rows[1].Buy.Visible, "MAX: no BUY")
		T.falsy(refs.Rows[2].Frame.Visible or refs.Rows[3].Frame.Visible, "one row only")
		T.eq(refs.Panel.Size.Y.Offset, View.height(1))
		-- every text of every machine at every level fits its box at full size
		local width = View.Width - 28
		local boxes = {}
		for key, share in View.Boxes do
			boxes[key] = width * share
		end
		local sizes = View.Sizes
		for _, machine in MachineData.Buildable do
			for level = 0, 5 do
				local st = state({
					MachineUpgrades = { [machine.Id] = { Speed = level, Quality = level, Tier = math.min(level, 3) } },
					Upgrades = { Bellows = level },
				})
				for _, r in View.rows(machine.Id, st, 0) do
					for key, box in boxes do
						local text = r[key]
						T.truthy(Pop.textWidth(text, sizes[key]) <= box, `{machine.Id} {key} "{text}" fits`)
					end
				end
			end
		end
		for key, text in View.Reasons do
			T.truthy(Pop.textWidth(text, sizes.Why) <= boxes.Why, `reason {key} "{text}" fits`)
		end
		T.eq(View.reasonText("NoCoins"), "Not enough coins")
		T.eq(View.reasonText("Weird"), View.Reasons.Retry)
		T.eq(View.reasonText(nil), View.Reasons.Retry)
		-- every reason the server can answer with has a short text here
		for key in EconomyConfig.TechShop.Reasons do
			T.truthy(View.Reasons[key] or key == "BadItem" or key == "MaxOwned" or key == "BadCount", "a short text for " .. key)
		end
		local _ = Instance
	end)
	T.test("Machine step 2: steel + blue only for the Solar Panel and the belt (owner 2026-11-07)", function()
		local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
		local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
		local P = KitMachines.Palette
		local before = table.clone(P)
		local looks = {}
		for id in KitMachines.SteelLook do
			table.insert(looks, id)
		end
		table.sort(looks)
		T.eq(table.concat(looks, ","), "Conveyor,SolarPanel", "his words: the machines, fences, pen and podiums keep their colours")
		local function colorOf(model: any, role: string, name: string?): any
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Kit") == role and (name == nil or d.Name == name) then
					return d.Color
				end
			end
			return nil
		end
		local solar = MachineBuilder.build("SolarPanel", 0, nil)
		T.eq(colorOf(solar, "Frame"), KitMachines.Steel.Frame, "the Solar Panel's frame: steel")
		T.eq(colorOf(solar, "Trim"), KitMachines.Steel.Trim, "its trim: blue")
		local crusher = MachineBuilder.build("Crusher", 0, nil)
		T.eq(colorOf(crusher, "Frame"), before.Frame, "the Crusher keeps today's colours")
		T.truthy(colorOf(crusher, "Frame") ~= KitMachines.Steel.Frame)
		local belt = MachineBuilder.build("Conveyor", 0, nil)
		T.eq(colorOf(belt, "Trim", "RailCap"), KitMachines.Steel.Trim, "the one belt: blue rail tops")
		T.eq(colorOf(belt, "Frame", "RailL"), KitMachines.Steel.Frame, "steel rails")
		local express = MachineBuilder.build("ExpressConveyor", 0, nil)
		T.truthy(colorOf(express, "Frame", "RailL") == before.Frame, "an old Express belt keeps its look")
		for role, color in before do
			T.eq(P[role], color, "the palette is back after every build: " .. role)
		end
	end)
end
