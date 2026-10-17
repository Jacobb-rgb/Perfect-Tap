-- ShopService (the Tech shop at the UPGRADES stall) and TechShopView under
-- Lune: the counter prompt, buying machines (BUY 1 / BUY 5, the 999 cap),
-- levelled items with the Level the card shows (no double buys, "Stale",
-- "Max"), Bellows / Slots / pen automation, every refusal with its
-- ShopResult and no change, the range, broken saves, a fuzz run that checks
-- coins and items always add up, and that the view's cards offer exactly
-- what the server quotes (plus its tabs, layout and touch sizes). Save
-- data, players and Net are small fakes; EconomyService runs for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
	local ShopService = Loader.requirePath("ServerScriptService.Server.Services.ShopService")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")

	local USER = 501
	local STALL = Vector3.new(44, 3, -20)
	local shop = ShopService._test
	local Reasons = EconomyConfig.TechShop.Reasons

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function fakePlayer(userId: number, name: string): any
		local p: any = { UserId = userId, Name = name, Parent = true, attrs = {} }
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.humanoid = { Health = 100 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name2: string)
				return if name2 == "HumanoidRootPart" then p.root else nil
			end,
		}
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, bought = {} }
		w.player = fakePlayer(USER, "Builder")
		w.data = deepCopy(DataTemplate)
		w.loaded = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			if p == w.player and w.loaded then
				return w.data
			end
			return nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		shop.reset()
		ShopService.onBought(function(p, bought)
			table.insert(w.bought, { Player = p, Bought = bought })
		end)
		-- the UPGRADES counter top, like Stalls builds it (customer side = -Z)
		local stall = Instance.new("Model")
		local counter = Instance.new("Part")
		counter.Size = Vector3.new(6.9, 0.3, 1.9)
		counter.CFrame = CFrame.lookAt(STALL, STALL + Vector3.new(1, 0, 0))
		counter.Parent = stall
		shop.hookCounter(counter)
		w.counter = counter
		-- puts the player `away` studs in front of the counter's customer side
		w.standAt = function(away: number)
			local front = counter.CFrame * CFrame.new(0, 0, -(counter.Size.Z / 2 + away))
			w.player.root.Position = front.Position
			w.player.root.CFrame = front
		end
		w.standAt(3)
		w.restore = function()
			shop.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	local function withWorld(name: string, fn: (any) -> ())
		T.test(name, function()
			local w = setup()
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function notes(w: any, name: string): { any }
		local out = {}
		for _, note in w.notes do
			if note.Name == name then
				table.insert(out, note)
			end
		end
		return out
	end

	-- Sends one ShopBuy and returns the ShopResult it got (asserts exactly one).
	local function buy(w: any, payload: any): any
		local before = #notes(w, "ShopResult")
		shop.shopBuy(w.player, payload)
		local results = notes(w, "ShopResult")
		T.eq(#results, before + 1, "exactly one ShopResult per request")
		return results[#results].A
	end

	local function req(item: string, count: number?, level: number?): any
		return { Shop = "Tech", Item = item, Count = count, Level = level }
	end

	local function refused(w: any, payload: any, reason: string, label: string)
		local coins = w.data.Coins
		local inventory = deepCopy(w.data.MachineInventory)
		local upgrades = deepCopy(w.data.Upgrades)
		local machine = deepCopy(w.data.MachineUpgrades)
		local result = buy(w, payload)
		T.eq(result.Ok, false, label .. ": refused")
		T.eq(result.Reason, reason, label .. ": reason")
		T.truthy(Reasons[reason], label .. ": the reason has a text")
		T.eq(w.data.Coins, coins, label .. ": coins kept")
		for id, n in inventory do
			T.eq(w.data.MachineInventory[id], n, label .. ": inventory " .. id)
		end
		for id, n in w.data.MachineInventory do
			T.eq(inventory[id], n, label .. ": nothing added " .. id)
		end
		for key, n in upgrades do
			T.eq(w.data.Upgrades[key], n, label .. ": upgrade " .. key)
		end
		for id, record in w.data.MachineUpgrades do
			for kind, n in record do
				T.eq((machine[id] or {})[kind], n, label .. ": machine upgrade " .. id .. kind)
			end
		end
		return result
	end

	---------------------------------------------------------------- the counter

	withWorld("ShopService: the UPGRADES counter gets a Tech Shop prompt on its customer side", function(w)
		local point = w.counter:FindFirstChild(ShopService.PointName)
		T.truthy(point and point:IsA("Attachment"), "prompt point")
		T.truthy(point.CFrame.Position.Z < 0, "on the customer side (-Z)")
		T.truthy(point.CFrame.Position.Y > 0, "above the counter top")
		local prompt = point:FindFirstChild(ShopService.PromptName)
		T.truthy(prompt and prompt:IsA("ProximityPrompt"), "prompt")
		T.eq(prompt.ActionText, "Tech Shop")
		T.eq(prompt.KeyboardKeyCode, roblox.Enum.KeyCode.F)
		T.eq(prompt.GamepadKeyCode, roblox.Enum.KeyCode.ButtonY)
		T.eq(prompt.HoldDuration, 0)
		T.falsy(prompt.RequiresLineOfSight, "no line of sight needed")
		shop.hookCounter(w.counter)
		local n = 0
		for _, child in w.counter:GetChildren() do
			if child.Name == ShopService.PointName then
				n += 1
			end
		end
		T.eq(n, 1, "hooked once")
		-- open: only near the counter
		shop.open(w.player, w.counter)
		local opened = notes(w, "OpenUI")
		T.eq(#opened, 1, "opens")
		T.eq(opened[1].A, "Tech")
		T.truthy(opened[1].B.Counter == w.counter, "with the counter")
		w.standAt(ShopService.Range + 5)
		shop.open(w.player, w.counter)
		T.eq(#notes(w, "OpenUI"), 1, "not from far away")
	end)

	---------------------------------------------------------------- machines

	withWorld("ShopService: buying machines puts them in the Build menu", function(w)
		local cleaner = MachineData.ById.AutoCleaner
		w.data.Coins = cleaner.Price + 10
		local result = buy(w, req("AutoCleaner"))
		T.eq(result.Ok, true, "bought")
		T.eq(result.Item, "AutoCleaner")
		T.eq(result.Count, 1, "Count echoed")
		T.eq(result.Level, nil, "no level for machines")
		T.eq(w.data.Coins, 10, "paid the price")
		T.eq(w.data.MachineInventory.AutoCleaner, 1, "in the inventory")
		T.truthy(w.changed > 0, "DataService.changed")
		local toast = notes(w, "Notify")
		T.eq(#toast, 1, "one toast")
		T.eq(toast[1].A.Kind, "Reward")
		T.eq(toast[1].A.Text, "Bought a Cleaning Plant! Place it in Build mode.")
		T.eq(#w.bought, 1, "onBought")
		local bought = w.bought[1].Bought
		T.eq(bought.Item, "AutoCleaner")
		T.eq(bought.Kind, "Machine")
		T.eq(bought.Machine, "AutoCleaner")
		T.eq(bought.Count, 1)
		T.eq(bought.Price, cleaner.Price)

		-- BUY 5 conveyors in one request
		local belt = MachineData.ById.Conveyor
		w.data.Coins = belt.Price * 5
		local five = buy(w, req("Conveyor", 5))
		T.eq(five.Ok, true, "five belts")
		T.eq(five.Count, 5)
		T.eq(w.data.Coins, 0, "paid 5x")
		T.eq(w.data.MachineInventory.Conveyor, 5)
		T.eq(notes(w, "Notify")[2].A.Text, "Bought 5 Conveyors! Place them in Build mode.")
		-- an Iron Box: "an", plural "Iron Boxes"
		T.eq(ShopService.plural("Iron Box"), "Iron Boxes")
		T.eq(ShopService.plural("Blast Furnace"), "Blast Furnaces")
		w.data.Coins = MachineData.ById.IronBox.Price * 2
		T.eq(buy(w, req("IronBox", 2)).Ok, true)
		T.eq(notes(w, "Notify")[3].A.Text, "Bought 2 Iron Boxes! Place them in Build mode.")
		w.data.Coins = MachineData.ById.IronBox.Price
		T.eq(buy(w, req("IronBox")).Ok, true)
		T.eq(notes(w, "Notify")[4].A.Text, "Bought an Iron Box! Place it in Build mode.")
		T.eq(w.data.MachineInventory.IronBox, 3)
	end)

	withWorld("ShopService: machine counts are checked (1..MaxCount, at most 999 of a type)", function(w)
		w.data.Coins = 1e12
		for _, bad in { 0, -1, EconomyConfig.TechShop.MaxCount + 1, 1.5, 0 / 0, math.huge, "5", true, {} } do
			refused(w, req("Conveyor", bad :: any), "BadCount", "count " .. tostring(bad))
		end
		T.eq(buy(w, req("Conveyor", EconomyConfig.TechShop.MaxCount)).Ok, true, "MaxCount at once")
		w.data.MachineInventory.Conveyor = EconomyConfig.TechShop.MaxOwned - 1
		refused(w, req("Conveyor", 2), "MaxOwned", "past 999")
		T.eq(buy(w, req("Conveyor", 1)).Ok, true, "up to 999")
		T.eq(w.data.MachineInventory.Conveyor, EconomyConfig.TechShop.MaxOwned)
		refused(w, req("Conveyor", 1), "MaxOwned", "at 999")
		-- placed machines don't count toward the cap
		table.insert(w.data.PlacedMachines, { Id = "Crusher", X = 1, Z = 1, R = 0 })
		T.eq(buy(w, req("Crusher")).Ok, true, "placed ones don't count")
		-- retired machines are not sold
		for _, id in { "StorageCrate", "Anvil", "SellChute" } do
			refused(w, req(id), "BadItem", "retired " .. id)
		end
	end)

	withWorld("ShopService: refusals answer with a reason and change nothing", function(w)
		w.data.Coins = 100
		refused(w, req("Crusher"), "NoCoins", "too poor")
		refused(w, req("Upgrade:Crusher:Speed", nil, 1), "NoCoins", "too poor for a level")
		-- bad payloads
		local function bad(payload: any, item: string, label: string)
			local result = refused(w, payload, "BadItem", label)
			T.eq(result.Item, item, label .. ": Item echoed")
		end
		bad(nil, "", "nil")
		bad("Conveyor", "", "a string")
		bad({ Shop = "Gear", Item = "Conveyor" }, "Conveyor", "another shop")
		bad({ Item = "Conveyor" }, "Conveyor", "no shop")
		bad(req("Pickaxe"), "Pickaxe", "unknown item")
		bad(req("Upgrade:Conveyor:Speed"), "Upgrade:Conveyor:Speed", "belts have no upgrades")
		bad(req("Upgrade:Crusher:Quality"), "Upgrade:Crusher:Quality", "only the Cleaning Plant has Quality")
		bad(req(string.rep("A", 200)), "", "too long")
		bad({ Shop = "Tech", Item = 5 }, "", "a number item")
		local big = req("Conveyor")
		for i = 1, 20 do
			big["k" .. i] = i
		end
		bad(big, "", "too many fields")
		-- too far
		w.data.Coins = 1e9
		w.standAt(ShopService.Range + 4)
		refused(w, req("Conveyor"), "TooFar", "far away")
		w.player.Character = nil
		refused(w, req("Conveyor"), "TooFar", "no character")
		-- no save loaded: no answer at all
		w.loaded = false
		local before = #notes(w, "ShopResult")
		shop.shopBuy(w.player, req("Conveyor"))
		T.eq(#notes(w, "ShopResult"), before, "no data, no answer")
		T.eq(#w.bought, 0, "nothing bought")
		T.eq(#notes(w, "Notify"), 0, "no toasts for refusals")
	end)

	---------------------------------------------------------------- levelled items

	withWorld("ShopService: an upgrade buys exactly the level the card shows", function(w)
		local entry = EconomyConfig.techItem("Upgrade:AutoCleaner:Quality")
		local prices = entry.Prices
		w.data.Coins = prices[1] + prices[2] + 5
		refused(w, req(entry.Item), "Stale", "no Level")
		refused(w, req(entry.Item, nil, 2), "Stale", "skipping a level")
		refused(w, req(entry.Item, nil, 0), "Stale", "the level you have")
		local result = buy(w, req(entry.Item, nil, 1))
		T.eq(result.Ok, true, "level 1")
		T.eq(result.Level, 1, "Level echoed")
		T.eq(result.Count, nil, "no Count for levels")
		T.eq(w.data.MachineUpgrades.AutoCleaner.Quality, 1, "saved")
		T.eq(w.data.Coins, prices[2] + 5, "paid level 1")
		-- a double tap sends the same Level twice: the second is Stale and costs nothing
		refused(w, req(entry.Item, nil, 1), "Stale", "double tap")
		T.eq(buy(w, req(entry.Item, nil, 2)).Ok, true, "level 2")
		T.eq(w.data.MachineUpgrades.AutoCleaner.Quality, 2)
		T.eq(w.data.Coins, 5)
		T.eq(w.data.MachineUpgrades.AutoCleaner.Speed, nil, "Speed untouched")
		T.eq(notes(w, "Notify")[2].A.Text, "Cleaning Plant Quality level 2: better grades on every Cleaning Plant!")
		local bought = w.bought[2].Bought
		T.eq(bought.Kind, "Upgrade")
		T.eq(bought.Upgrade, "Quality")
		T.eq(bought.Level, 2)
		T.eq(bought.Price, prices[2])
		-- the top level
		w.data.Coins = 1e12
		for level = 3, #prices do
			T.eq(buy(w, req(entry.Item, nil, level)).Ok, true, "level " .. level)
		end
		refused(w, req(entry.Item, nil, #prices + 1), "Max", "past the top")
		T.eq(w.data.MachineUpgrades.AutoCleaner.Quality, #prices)
	end)

	withWorld("ShopService: Speed upgrades for every machine type that has them", function(w)
		w.data.Coins = 1e12
		local n = 0
		for _, entry in EconomyConfig.TechShop.Items do
			if entry.Kind == "Upgrade" and entry.Upgrade == "Speed" then
				n += 1
				local before = w.data.Coins
				T.eq(buy(w, req(entry.Item, nil, 1)).Ok, true, entry.Item)
				T.eq(w.data.MachineUpgrades[entry.Machine].Speed, 1, entry.Item .. " saved")
				T.eq(before - w.data.Coins, entry.Prices[1], entry.Item .. " price")
				T.truthy(notes(w, "Notify")[n].A.Text:find("Speed level 1", 1, true), "toast " .. entry.Item)
			end
		end
		T.eq(n, 5, "furnaces, crusher, cleaning plant, iron box")
	end)

	withWorld("ShopService: Bellows, machine Slots and pen automation", function(w)
		w.data.Coins = 1e12
		-- Bellows
		T.eq(buy(w, req("Bellows", nil, 1)).Ok, true)
		T.eq(w.data.Upgrades.Bellows, 1)
		T.eq(notes(w, "Notify")[1].A.Text, "Bellows level 1: all your machines work faster!")
		-- Slots: 10 -> 13 -> 16 (19 / 22 with the Workshop pass)
		T.eq(buy(w, req("Slots", nil, 1)).Ok, true)
		T.eq(w.data.Upgrades.ExtraSlots, 1)
		T.eq(notes(w, "Notify")[2].A.Text, "More room: 13 machine slots on your plot!")
		w.player.attrs.Perk_Workshop = true
		T.eq(buy(w, req("Slots", nil, 2)).Ok, true)
		T.eq(notes(w, "Notify")[3].A.Text, "More room: 22 machine slots on your plot!")
		refused(w, req("Slots", nil, 3), "Max", "two slot upgrades")
		-- pen automation: level 2 needs level 1 first
		refused(w, req("PenAutomation", nil, 2), "Stale", "Direct Unload before the billboard")
		local paid = w.data.Coins
		T.eq(buy(w, req("PenAutomation", nil, 1)).Ok, true, "billboard")
		T.eq(paid - w.data.Coins, EconomyConfig.PenAutomation.Prices[1])
		T.eq(w.data.Upgrades.PenAutomation, 1)
		T.eq(notes(w, "Notify")[4].A.Text, "Auto-Sort Billboard unlocked at your Ore Pen!")
		T.eq(buy(w, req("PenAutomation", nil, 2)).Ok, true, "Direct Unload")
		T.eq(w.data.Upgrades.PenAutomation, 2)
		T.truthy(notes(w, "Notify")[5].A.Text:find("Train Direct Unload unlocked", 1, true), "toast")
		refused(w, req("PenAutomation", nil, 3), "Max", "top")
		-- other Upgrades fields untouched
		T.eq(w.data.Upgrades.PenLevel, 0)
	end)

	withWorld("ShopService: broken or newer saves never lose levels or coins", function(w)
		w.data.Coins = 1e12
		-- a newer server sold more levels: read as the top level, never written down
		w.data.Upgrades.PenAutomation = 7
		refused(w, req("PenAutomation", nil, 3), "Max", "newer save")
		refused(w, req("PenAutomation", nil, 8), "Max", "newer save, its own number")
		T.eq(w.data.Upgrades.PenAutomation, 7, "kept")
		w.data.MachineUpgrades.Crusher = { Speed = 12 }
		refused(w, req("Upgrade:Crusher:Speed", nil, 6), "Max", "machine level above the top")
		T.eq(w.data.MachineUpgrades.Crusher.Speed, 12, "kept")
		-- missing / broken tables are made before paying
		w.data.MachineUpgrades = nil
		T.eq(buy(w, req("Upgrade:ClayFurnace:Speed", nil, 1)).Ok, true, "no MachineUpgrades table")
		T.eq(w.data.MachineUpgrades.ClayFurnace.Speed, 1)
		w.data.MachineUpgrades.BlastFurnace = 5
		T.eq(buy(w, req("Upgrade:BlastFurnace:Speed", nil, 1)).Ok, true, "a number instead of a record")
		T.eq(w.data.MachineUpgrades.BlastFurnace.Speed, 1)
		w.data.MachineUpgrades.IronBox = { Speed = 2.7 }
		T.eq(buy(w, req("Upgrade:IronBox:Speed", nil, 3)).Ok, true, "a broken level counts as its whole part")
		T.eq(w.data.MachineUpgrades.IronBox.Speed, 3)
		w.data.Upgrades = "junk"
		T.eq(buy(w, req("Bellows", nil, 1)).Ok, true, "no Upgrades record")
		T.eq(w.data.Upgrades.Bellows, 1)
		w.data.MachineInventory = nil
		T.eq(buy(w, req("Conveyor", 3)).Ok, true, "no inventory table")
		T.eq(w.data.MachineInventory.Conveyor, 3)
		w.data.MachineInventory.Crusher = 0 / 0
		T.eq(buy(w, req("Crusher")).Ok, true, "a NaN count")
		T.eq(w.data.MachineInventory.Crusher, 1)
		-- broken coins: nothing can be bought
		w.data.Coins = 0 / 0
		local inventory = w.data.MachineInventory.Conveyor
		local nan = buy(w, req("Conveyor"))
		T.eq(nan.Reason, "NoCoins", "NaN coins")
		T.eq(w.data.MachineInventory.Conveyor, inventory, "NaN coins: nothing added")
	end)

	withWorld("ShopService: fuzz: coins and items always add up", function(w)
		local rng = Rng.new(31337)
		local items = {}
		for _, entry in EconomyConfig.TechShop.Items do
			table.insert(items, entry.Item)
		end
		table.insert(items, "Nope")
		w.data.Coins = 5e7
		local spent = 0
		local machines = 0
		local levels = 0
		for _ = 1, 600 do
			local item = items[rng:int(1, #items)]
			local entry = EconomyConfig.techItem(item)
			local level: any = nil
			if entry and entry.Prices then
				local current = EconomyConfig.techLevel(entry, w.data)
				level = current + rng:int(0, 2)
			end
			local count: any = if rng:next() < 0.8 then rng:int(0, 22) else nil
			if rng:next() < 0.05 then
				w.standAt(ShopService.Range + 2)
			else
				w.standAt(2)
			end
			local coins = w.data.Coins
			local result = buy(w, req(item, count, level))
			if result.Ok then
				local paid = coins - w.data.Coins
				T.truthy(paid > 0, "paid something")
				spent += paid
				if entry.Kind == "Machine" then
					machines += result.Count
					T.eq(paid, MachineData.ById[item].Price * result.Count, "machine price")
				else
					levels += 1
					T.eq(result.Level, level, "the level asked for")
					T.eq(paid, entry.Prices[level], "level price")
				end
			else
				T.eq(w.data.Coins, coins, "refused: coins kept")
				T.truthy(Reasons[result.Reason], "a known reason: " .. tostring(result.Reason))
			end
			T.truthy(w.data.Coins >= 0, "never below zero")
		end
		local owned = 0
		for id, n in w.data.MachineInventory do
			T.truthy(n >= 1 and n <= EconomyConfig.TechShop.MaxOwned, "count in range " .. id)
			owned += n
		end
		T.eq(owned, machines, "every machine paid for is in the inventory")
		local bought = 0
		for _, record in w.data.MachineUpgrades do
			for _, n in record do
				bought += n
			end
		end
		for _, key in { "Bellows", "ExtraSlots", "PenAutomation" } do
			bought += w.data.Upgrades[key]
		end
		T.eq(bought, levels, "every level paid for is saved")
		T.eq(5e7 - w.data.Coins, spent, "coins spent = coins gone")
		T.truthy(levels > 5 and machines > 5, "the fuzz bought things")
	end)

	---------------------------------------------------------------- the view

	local function state(over: { [string]: any }?): { [string]: any }
		local s: { [string]: any } = {
			Coins = 0,
			MachineInventory = {},
			MachineUpgrades = {},
			Upgrades = { Bellows = 0, ExtraSlots = 0, PenLevel = 0, PenAutomation = 0 },
			Placed = {},
			Perks = { Workshop = false },
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	local function cardById(cards: { any }, id: string): any
		for _, card in cards do
			if card.Id == id then
				return card
			end
		end
		return nil
	end

	T.test("TechShopView: one row per thing sold, in three tabs", function()
		local refs = TechShopView.build(false)
		T.falsy(refs.Gui.Enabled, "starts closed")
		T.truthy(refs.Gui:GetAttribute("TerraForge"), "HUD scale applies")
		local tabs = {}
		for _, row in refs.RowList do
			tabs[row.Tab] = (tabs[row.Tab] or 0) + 1
		end
		T.eq(tabs.Machines, #MachineData.Buildable, "every buildable machine")
		local upgrades = 2 -- Bellows, Slots
		for _, entry in EconomyConfig.TechShop.Items do
			if entry.Kind == "Upgrade" then
				upgrades += 1
			end
		end
		T.eq(tabs.Upgrades, upgrades, "every upgrade + Bellows + Slots")
		T.eq(tabs.Automation, #EconomyConfig.PenAutomation.Prices, "one row per pen automation level")
		T.eq(refs.Rows.Conveyor and #refs.Rows.Conveyor.Buttons, 2, "BUY 1 / BUY 5 on belts")
		T.eq(#refs.Rows.Crusher.Buttons, 1, "one BUY on other machines")
		for _, machine in MachineData.Buildable do
			T.truthy(refs.Rows[machine.Id], "row " .. machine.Id)
		end
		for id in MachineData.Retired do
			T.eq(refs.Rows[id], nil, "retired " .. id .. " not sold")
		end
		-- tabs
		T.eq(refs.Tab, "Machines")
		T.truthy(refs.Lists.Machines.Visible and not refs.Lists.Upgrades.Visible, "machines first")
		TechShopView.setTab(refs, "Automation")
		T.truthy(refs.Lists.Automation.Visible and not refs.Lists.Machines.Visible, "switched")
		T.eq(TechShopView.nextTab("Machines", 1), "Upgrades")
		T.eq(TechShopView.nextTab("Automation", 1), "Machines", "wraps forward")
		T.eq(TechShopView.nextTab("Machines", -1), "Automation", "wraps back")
		T.eq(TechShopView.toTab("Upgrades"), "Upgrades")
		T.eq(TechShopView.toTab("Gear"), nil)
		-- Bellows and Slots sit under the "FOR ALL MACHINES" header
		T.truthy(refs.Rows.Bellows.Frame.LayoutOrder > TechShopView.AllMachinesOrder, "Bellows after the header")
		T.truthy(refs.Rows["Upgrade:AutoCleaner:Speed"].Frame.LayoutOrder < TechShopView.AllMachinesOrder, "machine upgrades first")
	end)

	T.test("TechShopView: cards show owned / placed counts and what you can afford", function()
		local belt = MachineData.ById.Conveyor
		local s = state({
			MachineInventory = { Conveyor = 3, AutoCleaner = EconomyConfig.TechShop.MaxOwned },
			Placed = { { Id = "Conveyor" }, { Id = "Conveyor" }, { Id = "ClayFurnace" } },
		})
		local cards = TechShopView.cards(s, belt.Price * 2)
		local conveyor = cardById(cards, "Conveyor")
		T.eq(conveyor.Tab, "Machines")
		T.eq(conveyor.Detail, "In your Build menu: 3   •   Placed: 2")
		T.eq(conveyor.PriceSub, "each")
		T.eq(#conveyor.Buys, 2)
		T.eq(conveyor.Buys[1].Text, "BUY 1")
		T.eq(conveyor.Buys[1].Count, 1)
		T.truthy(conveyor.Buys[1].CanBuy, "one belt affordable")
		T.eq(conveyor.Buys[2].Text, "BUY 5")
		T.eq(conveyor.Buys[2].Count, 5)
		T.falsy(conveyor.Buys[2].CanBuy, "five not")
		T.eq(conveyor.Buys[2].Reason, "NoCoins")
		local furnace = cardById(cards, "ClayFurnace")
		T.eq(furnace.Detail, "In your Build menu: 0   •   Placed: 1")
		T.eq(furnace.Buys[1].Text, "BUY")
		T.eq(cardById(cards, "Crusher").Detail, "You don't have one yet")
		local cleaner = cardById(cards, "AutoCleaner")
		T.eq(cleaner.Title, "Cleaning Plant", "the UI name")
		T.eq(cleaner.Buys[1].Reason, "MaxOwned", "999 in the Build menu")
		T.eq(cleaner.Detail, Reasons.MaxOwned)
		T.eq(TechShopView.placedCount(s, "Conveyor"), 2)
		T.eq(TechShopView.placedCount(nil, "Conveyor"), 0, "no state")
		-- a broken snapshot still gives every card
		T.eq(#TechShopView.cards(nil, 0 / 0), #TechShopView.cards(s, 0), "nil state")
	end)

	T.test("TechShopView: levelled cards ask for the next level and say what it gives", function()
		local s = state({
			MachineUpgrades = { AutoCleaner = { Speed = 2, Quality = 5 } },
			Upgrades = { Bellows = 1, ExtraSlots = 2, PenLevel = 0, PenAutomation = 0 },
		})
		local cards = TechShopView.cards(s, 1e12)
		local speed = cardById(cards, "Upgrade:AutoCleaner:Speed")
		T.eq(speed.Tab, "Upgrades")
		T.eq(speed.Title, "Cleaning Plant Speed")
		T.eq(speed.Chip, "LV 2/5")
		T.eq(speed.Buys[1].Level, 3, "buys level 3")
		T.eq(speed.Buys[1].Price, EconomyConfig.techItem("Upgrade:AutoCleaner:Speed").Prices[3])
		local plant = MachineData.ById.AutoCleaner
		local now = TechShopView.seconds(MachineData.processTime(plant, 1, 2))
		local after = TechShopView.seconds(MachineData.processTime(plant, 1, 3))
		T.eq(speed.Detail, `Per item: {now} → {after}`)
		T.eq(speed.Badge, "Speed")
		local quality = cardById(cards, "Upgrade:AutoCleaner:Quality")
		T.truthy(quality.Done, "Quality at the top")
		T.eq(quality.Buys[1].Text, "MAX")
		T.falsy(quality.Buys[1].CanBuy)
		T.eq(quality.Buys[1].Reason, "Max")
		T.eq(quality.Detail, "Pristine 50%   •   Flawless 30%   (top level)")
		local q0 = cardById(TechShopView.cards(state(), 1e12), "Upgrade:AutoCleaner:Quality")
		T.eq(q0.Detail, "Pristine 0% → 5%   •   Flawless 0% → 0%")
		local bellows = cardById(cards, "Bellows")
		T.eq(bellows.Detail, "Job time 90% → 80%")
		T.eq(bellows.Buys[1].Level, 2)
		local slots = cardById(cards, "Slots")
		T.truthy(slots.Done, "both slot upgrades bought")
		T.eq(slots.Detail, "Machine slots: 16 (top level)")
		local withPass = cardById(TechShopView.cards(state({ Perks = { Workshop = true } }), 0), "Slots")
		T.eq(withPass.Detail, "Machine slots: 16 → 19", "the Workshop pass counts")
		T.eq(TechShopView.seconds(8), "8 s")
		T.eq(TechShopView.seconds(6.4), "6.4 s")
	end)

	T.test("TechShopView: pen automation steps unlock in order", function()
		local function steps(level: number, coins: number): (any, any)
			local cards = TechShopView.cards(state({ Upgrades = { Bellows = 0, ExtraSlots = 0, PenAutomation = level } }), coins)
			return cardById(cards, "PenAutomation:1"), cardById(cards, "PenAutomation:2")
		end
		local prices = EconomyConfig.PenAutomation.Prices
		local one, two = steps(0, 1e12)
		T.eq(one.Tab, "Automation")
		T.eq(one.Title, "Auto-Sort Billboard")
		T.eq(two.Title, "Train Direct Unload")
		T.eq(one.Item, "PenAutomation")
		T.eq(one.Buys[1].Level, 1)
		T.truthy(one.Buys[1].CanBuy)
		T.eq(two.Buys[1].Text, "LOCKED")
		T.eq(two.Buys[1].Reason, "Locked")
		T.eq(two.Note, "Needs the Auto-Sort Billboard first")
		T.eq(two.PriceText, Format.money(prices[2]), "the price shows while locked")
		one, two = steps(1, prices[2] - 1)
		T.truthy(one.Done, "billboard owned")
		T.eq(one.Buys[1].Text, "OWNED")
		T.eq(one.Chip, "ACTIVE")
		T.eq(two.Buys[1].Level, 2)
		T.falsy(two.Buys[1].CanBuy, "not enough coins")
		T.eq(two.Buys[1].Reason, "NoCoins")
		one, two = steps(2, 0)
		T.truthy(one.Done and two.Done, "both owned")
		one, two = steps(9, 0)
		T.truthy(one.Done and two.Done, "a newer save's level")
	end)

	T.test("TechShopView: every BUY a card offers is exactly what the server quotes", function()
		local rng = Rng.new(77)
		for _ = 1, 60 do
			local s = state({
				MachineInventory = {
					Conveyor = rng:int(0, 999),
					Crusher = rng:int(0, 3),
					AutoCleaner = if rng:next() < 0.2 then 999 else rng:int(0, 2),
				},
				MachineUpgrades = {
					AutoCleaner = { Speed = rng:int(0, 5), Quality = rng:int(0, 5) },
					BlastFurnace = { Speed = rng:int(0, 6) },
				},
				Upgrades = { Bellows = rng:int(0, 5), ExtraSlots = rng:int(0, 2), PenLevel = 0, PenAutomation = rng:int(0, 2) },
			})
			local coins = rng:int(0, 3e6)
			for _, card in TechShopView.cards(s, coins) do
				local entry = EconomyConfig.techItem(card.Item)
				T.truthy(entry, "sold: " .. card.Item)
				for _, offer in card.Buys do
					local price, reason = EconomyConfig.techQuote(entry, s, offer.Count, offer.Level)
					if offer.CanBuy then
						T.eq(price, offer.Price, card.Id .. " price")
						T.truthy(coins >= price, card.Id .. " affordable")
					elseif offer.Reason == "NoCoins" then
						T.eq(price, offer.Price, card.Id .. " quoted but too dear")
						T.truthy(coins < price, card.Id .. " too dear")
					elseif offer.Reason ~= "Locked" then
						T.eq(price, nil, card.Id .. " refused")
						-- "OWNED" on step 1 when step 2 is for sale: the server sells step 2 then
						if not (card.Done and entry.Kind == "PenAutomation") then
							T.eq(reason, offer.Reason, card.Id .. " same reason")
						end
					end
				end
			end
		end
	end)

	T.test("TechShopView: layouts fit and phone buttons are at least 44 pt", function()
		local function check(compact: boolean, width: number, height: number, label: string)
			local refs = TechShopView.build(compact)
			TechShopView.layout(refs, compact, width, height)
			local panel = refs.Panel.Size
			T.truthy(panel.X.Offset <= math.max(560, width - 24), label .. " width fits")
			T.truthy(panel.Y.Offset <= math.max(380, height - 16), label .. " height fits")
			TechShopView.setCards(refs, TechShopView.cards(state(), 1e6))
			for _, row in refs.RowList do
				-- the title column keeps some room next to the price and buttons
				local title = row.Title.Size
				local rowWidth = panel.X.Offset - 16 - 10
				T.truthy(rowWidth + title.X.Offset > 120, label .. " title room " .. row.Id)
			end
			if compact then
				for _, target in TechShopView.touchTargets(refs) do
					local size = target.Size
					local w = size.X.Offset + size.X.Scale * (panel.X.Offset - 32) / 3
					T.truthy(size.Y.Offset * TechShopView.PhoneScale >= TechShopView.MinTouch - 0.5, label .. " tall enough " .. target.Name)
					T.truthy(w * TechShopView.PhoneScale >= TechShopView.MinTouch, label .. " wide enough " .. target.Name)
				end
			end
		end
		check(false, 1280, 720, "PC")
		-- on a 1280 x 720 screen the panel sits below the HUD coins (16..90), inside the screen
		local pc = TechShopView.build(false)
		TechShopView.layout(pc, false, 1280, (720 - 36) / 1)
		local top = pc.Panel.Position.Y.Offset
		T.truthy(top >= TechShopView.CoinsBottom, "below the HUD coins")
		T.truthy(top + pc.Panel.Size.Y.Offset <= 720 - 36, "inside the screen")
		-- a big screen: centred, clear of the coins anyway
		local big = TechShopView.build(false)
		TechShopView.layout(big, false, 1536, 835)
		T.truthy(big.Panel.Position.Y.Offset >= TechShopView.CoinsBottom, "big screen")
		T.eq(big.Panel.Size.Y.Offset, 600, "full height")
		check(true, 1600 / (0.62 * 900 / 375), (900 - 58) / (0.62 * 900 / 375), "phone")
		check(true, 1600 / (0.62 * 900 / 320), (900 - 163) / (0.62 * 900 / 320), "small phone")
	end)

	T.test("TechShopView: setCards fills rows; status lines and busy buttons", function()
		local refs = TechShopView.build(false)
		local s = state({ MachineUpgrades = { Crusher = { Speed = 5 } } })
		TechShopView.setCards(refs, TechShopView.cards(s, 100))
		local crusherSpeed = refs.Rows["Upgrade:Crusher:Speed"]
		T.eq(crusherSpeed.Buttons[1].Text, "MAX")
		T.eq(crusherSpeed.Price.Text, "", "no price at the top")
		local belt = refs.Rows.Conveyor
		T.eq(belt.Buttons[1].Text, "BUY 1")
		T.eq(belt.Buttons[2].Text, "BUY 5")
		T.eq(belt.Price.Text, "$25")
		T.truthy(belt.Buttons[1].Parent.Visible, "buttons shown")
		-- a busy button keeps its text over a refresh
		belt.Buttons[1]:SetAttribute("Busy", true)
		belt.Buttons[1].Text = "..."
		TechShopView.setCards(refs, TechShopView.cards(s, 100))
		T.eq(belt.Buttons[1].Text, "...", "busy text kept")
		-- the status line replaces the detail line
		TechShopView.setStatus(refs, "Conveyor", "Not enough coins", nil)
		T.truthy(belt.Status.Visible and not belt.Detail.Visible, "status shown")
		TechShopView.setStatus(refs, "Conveyor", nil, nil)
		T.truthy(belt.Detail.Visible and not belt.Status.Visible, "detail back")
		-- gamepad start: the first affordable BUY in the tab
		T.truthy(TechShopView.firstButton(refs, "Machines") == belt.Buttons[1], "first affordable")
		TechShopView.setCards(refs, TechShopView.cards(s, 0))
		T.truthy(TechShopView.firstButton(refs, "Machines") == belt.Buttons[1], "else the first button")
		TechShopView.setCoins(refs, 12480)
		T.eq(refs.BalanceAmount.Text, "$12.5K")
		TechShopView.showReceipt(refs, "Bought a Crusher!", refs.Title.TextColor3)
		T.truthy(refs.Receipt.Visible and not refs.Subtitle.Visible, "receipt")
		TechShopView.hideReceipt(refs)
		T.truthy(refs.Subtitle.Visible and not refs.Receipt.Visible, "subtitle back")
		-- every icon kind draws something
		for _, row in refs.RowList do
			local art = row.Icon:FindFirstChild("Art")
			T.truthy(art and #art:GetChildren() >= 3, "icon " .. row.Id)
		end
	end)
end
