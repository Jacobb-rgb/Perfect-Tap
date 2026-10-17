-- GearService (the Gear shop at the SHOP stall), the Ore Magnet in
-- ItemService and GearShopView under Lune: the counter prompt, buying the
-- five gear lines one level at a time (the Level the card shows, no double
-- buys, "Stale", "Max", newer saves never lowered), every refusal with its
-- one ActionResult and no change, the range, the effects at once (walk
-- speed on the humanoid, carry capacity, pickup range, throw power,
-- magnet radius, the LampLevel attribute), a fuzz run where coins and
-- levels always add up; the magnet (own items only, the nearest first, not
-- through walls, not hand-dropped items, not on bases, lets go at your feet
-- or when the magnet goes away); and that the view's cards offer exactly
-- what the server quotes, fit every screen, keep 44 pt touch targets and
-- never overlap. Save data, players and Net are small fakes;
-- EconomyService, Bonuses and CarryService run for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local GearConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GearConfig")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local GearService = Loader.requirePath("ServerScriptService.Server.Services.GearService")
	local GearShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GearShopView")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local USER = 601
	local OTHER = 602
	local STALL = Vector3.new(-44, 3, -20)
	local gear = GearService._test
	local Reasons = GearConfig.Reasons
	local LINES = GearConfig.LineIds

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
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0), AssemblyLinearVelocity = Vector3.zero }
		p.humanoid = { Health = 100, WalkSpeed = 16 }
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
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, bought = {}, ids = 0 }
		w.player = fakePlayer(USER, "Miner")
		w.other = fakePlayer(OTHER, "Neighbour")
		w.data = deepCopy(DataTemplate)
		w.otherData = deepCopy(DataTemplate)
		w.loaded = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			if p == w.player and w.loaded then
				return w.data
			elseif p == w.other then
				return w.otherData
			end
			return nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(Players, "GetPlayers", function()
			return { w.player, w.other }
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == OTHER then w.other else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids += 1
			return "gear-guid-" .. w.ids
		end)
		gear.reset()
		ItemService._test.reset()
		Bonuses.invalidate(w.player)
		Bonuses.invalidate(w.other)
		GearService.onBought(function(p, bought)
			table.insert(w.bought, { Player = p, Bought = bought })
		end)
		-- the SHOP counter top, like Stalls builds it (customer side = -Z)
		local stall = Instance.new("Model")
		local counter = Instance.new("Part")
		counter.Size = Vector3.new(6.9, 0.3, 1.9)
		counter.CFrame = CFrame.lookAt(STALL, STALL + Vector3.new(-1, 0, 0))
		counter.Parent = stall
		gear.hookCounter(counter)
		w.counter = counter
		-- puts the player `away` studs in front of the counter's customer side
		w.standAt = function(away: number)
			local front = counter.CFrame * CFrame.new(0, 0, -(counter.Size.Z / 2 + away))
			w.player.root.Position = front.Position
			w.player.root.CFrame = front
		end
		w.standAt(3)
		-- items live in a folder (unparented = destroyed, as in the game)
		w.world = Instance.new("Folder")
		w.restore = function()
			gear.reset()
			ItemService._test.reset()
			Bonuses.invalidate(w.player)
			Bonuses.invalidate(w.other)
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

	-- Sends one GearAction and returns the ActionResult it got (asserts exactly one).
	local function act(w: any, op: any, payload: any): any
		local before = #notes(w, "ActionResult")
		gear.gearAction(w.player, op, payload)
		local results = notes(w, "ActionResult")
		T.eq(#results, before + 1, "exactly one ActionResult per request")
		local result = results[#results].A
		T.eq(result.Action, "Gear", "Action")
		return result
	end

	local function buy(w: any, line: any, level: any): any
		return act(w, "Buy", { Line = line, Level = level })
	end

	local function refused(w: any, op: any, payload: any, reason: string, label: string): any
		local coins = w.data.Coins
		local levels = deepCopy(w.data.Gear)
		local result = act(w, op, payload)
		T.eq(result.Ok, false, label .. ": refused")
		T.eq(result.Reason, reason, label .. ": reason")
		T.truthy(Reasons[reason], label .. ": the reason has a text")
		T.eq(w.data.Coins, coins, label .. ": coins kept")
		if type(levels) == "table" then
			for key, n in levels do
				T.eq(w.data.Gear[key], n, label .. ": level " .. tostring(key))
			end
		end
		return result
	end

	---------------------------------------------------------------- the counter

	withWorld("GearService: the SHOP counter gets a Gear Shop prompt on its customer side", function(w)
		local point = w.counter:FindFirstChild(GearService.PointName)
		T.truthy(point and point:IsA("Attachment"), "prompt point")
		T.truthy(point.CFrame.Position.Z < 0, "on the customer side (-Z)")
		T.truthy(point.CFrame.Position.Y > 0, "above the counter top")
		local prompt = point:FindFirstChild(GearService.PromptName)
		T.truthy(prompt and prompt:IsA("ProximityPrompt"), "prompt")
		T.eq(prompt.ActionText, "Gear Shop")
		T.eq(prompt.KeyboardKeyCode, roblox.Enum.KeyCode.F)
		T.eq(prompt.GamepadKeyCode, roblox.Enum.KeyCode.ButtonY)
		T.eq(prompt.HoldDuration, 0)
		T.falsy(prompt.RequiresLineOfSight, "no line of sight needed")
		T.eq(GearService.Tag, "ShopCounter", "the lobby's SHOP hook")
		gear.hookCounter(w.counter)
		local n = 0
		for _, child in w.counter:GetChildren() do
			if child.Name == GearService.PointName then
				n += 1
			end
		end
		T.eq(n, 1, "hooked once")
		gear.open(w.player, w.counter)
		local opened = notes(w, "OpenUI")
		T.eq(#opened, 1, "opens")
		T.eq(opened[1].A, "Gear")
		T.truthy(opened[1].B.Counter == w.counter, "with the counter")
		w.standAt(GearService.Range + 5)
		gear.open(w.player, w.counter)
		T.eq(#notes(w, "OpenUI"), 1, "not from far away")
		-- the client closes the shop before the server would say "TooFar"
		T.truthy(prompt.MaxActivationDistance < GearShopView.CloseRange, "the prompt reaches less than the shop stays open")
		T.truthy(GearShopView.CloseRange + 4 <= GearService.Range, "the server is the lenient side")
		w.standAt(GearShopView.CloseRange)
		w.data.Coins = GearConfig.ById.Boots.Prices[1]
		T.eq(buy(w, "Boots", 1).Ok, true, "a BUY from where the shop is still open")
		-- a counter that leaves is forgotten, and hooked again with one prompt
		gear.unhookCounter(w.counter)
		T.eq(#gear.counters(), 0, "dropped")
		T.eq(w.counter:FindFirstChild(GearService.PointName), nil, "its prompt is gone")
		gear.hookCounter(w.counter)
		T.eq(#gear.counters(), 1, "hooked again")
	end)

	---------------------------------------------------------------- buying

	withWorld("GearService: each line buys its next level and works at once", function(w)
		w.data.Coins = 1e9
		local start = w.data.Coins
		local spent = 0
		for i, line in LINES do
			local price = GearConfig.ById[line].Prices[1]
			local result = buy(w, line, 1)
			T.eq(result.Ok, true, line .. " bought")
			T.eq(result.Op, "Buy")
			T.eq(result.Id, line, "Id = the line")
			T.eq(result.Level, 1, "the new level")
			T.eq(w.data.Gear[line], 1, line .. " saved")
			spent += price
			T.eq(w.data.Coins, start - spent, line .. " paid exactly")
			local bought = w.bought[i].Bought
			T.eq(bought.Line, line)
			T.eq(bought.Level, 1)
			T.eq(bought.Price, price)
			local toast = notes(w, "Notify")[i].A
			T.eq(toast.Kind, "Reward")
			T.eq(toast.Text, GearService.boughtText(line, 1, false), line .. " toast")
		end
		T.truthy(w.changed > 0, "DataService.changed")
		-- the effects, right away
		local stats = Bonuses.stats(w.player)
		T.eq(w.player.humanoid.WalkSpeed, GearConfig.value("Boots", 1), "Boots I on the humanoid")
		T.eq(CarryService.capacity(w.player), 2, "Backpack I: two items")
		T.eq(w.player.attrs.CarryCapacity, 2, "the client's attribute")
		T.eq(CarryService.pickupRange(w.player), 13, "Gloves I reach")
		T.eq(w.player.attrs.PickupRange, 13, "the client's PickupRange")
		T.near(Bonuses.throwMult(stats), 1.08, 1e-9, "Gloves I throw")
		T.eq(Bonuses.magnetRadius(stats), 8, "Magnet I")
		T.eq(w.player.attrs[GearConfig.LampAttribute], 1, "LampLevel for the head lamps")
		local range, brightness = Bonuses.lamp(stats)
		T.eq(range, 18)
		T.near(brightness, 1.2, 1e-9)
		-- texts
		T.eq(GearService.boughtText("Boots", 3, false), "Miner's Boots III: walk speed 22!")
		T.eq(GearService.boughtText("Backpack", 2, true), "Ore Backpack II: you can carry 6 items!")
		T.eq(GearService.boughtText("Gloves", 1, false), "Grip Gloves I: grab from 13 studs, throw x1.08!")
		T.eq(GearService.boughtText("HelmetLamp", 5, false), "Helmet Lamp V: your lamp lights 56 studs!")
		T.eq(GearService.boughtText("Magnet", 2, false), "Ore Magnet II: your ore flies to you from 12 studs!")
	end)

	withWorld("GearService: a buy is exactly the level the card shows (no double buys)", function(w)
		local prices = GearConfig.ById.Boots.Prices
		w.data.Coins = prices[1] + prices[2] + 7
		refused(w, "Buy", { Line = "Boots" }, "Stale", "no Level")
		refused(w, "Buy", { Line = "Boots", Level = 2 }, "Stale", "skipping a level")
		refused(w, "Buy", { Line = "Boots", Level = 0 }, "Stale", "the level you have")
		for _, bad in { "1", 1.5, 0 / 0, math.huge, -1, true, {} } do
			refused(w, "Buy", { Line = "Boots", Level = bad }, "Stale", "level " .. tostring(bad))
		end
		T.eq(buy(w, "Boots", 1).Ok, true, "level 1")
		-- a double tap sends the same Level twice: the second is Stale and costs nothing
		refused(w, "Buy", { Line = "Boots", Level = 1 }, "Stale", "double tap")
		T.eq(buy(w, "Boots", 2).Ok, true, "level 2")
		T.eq(w.data.Gear.Boots, 2)
		T.eq(w.data.Coins, 7, "paid levels 1 and 2 once")
		-- to the top
		w.data.Coins = 1e12
		for level = 3, GearConfig.MaxLevel do
			T.eq(buy(w, "Boots", level).Ok, true, "level " .. level)
		end
		refused(w, "Buy", { Line = "Boots", Level = GearConfig.MaxLevel + 1 }, "Max", "past the top")
		T.eq(w.data.Gear.Boots, GearConfig.MaxLevel)
		T.eq(w.player.humanoid.WalkSpeed, 26, "Boots V")
		-- the other lines are untouched
		for _, line in LINES do
			if line ~= "Boots" then
				T.eq(w.data.Gear[line], 0, line .. " untouched")
			end
		end
	end)

	withWorld("GearService: refusals answer with a reason and change nothing", function(w)
		w.data.Coins = GearConfig.ById.Magnet.Prices[1] - 1
		refused(w, "Buy", { Line = "Magnet", Level = 1 }, "NoCoins", "too poor")
		local function bad(op: any, payload: any, label: string)
			refused(w, op, payload, "BadItem", label)
		end
		bad("Buy", nil, "no payload")
		bad("Buy", "Boots", "a string payload")
		bad("Buy", { Line = "Cape", Level = 1 }, "unknown line")
		bad("Buy", { Line = 5, Level = 1 }, "a number line")
		bad("Buy", { Line = string.rep("B", 200), Level = 1 }, "too long")
		bad("Sell", { Line = "Boots", Level = 1 }, "another op")
		bad(nil, { Line = "Boots", Level = 1 }, "no op")
		bad({}, { Line = "Boots", Level = 1 }, "a table op")
		local big = { Line = "Boots", Level = 1 }
		for i = 1, 10 do
			big["k" .. i] = i
		end
		bad("Buy", big, "too many fields")
		T.eq(act(w, "Buy", { Line = "Cape", Level = 1 }).Id, "Cape", "the line is echoed")
		-- too far / no character
		w.data.Coins = 1e9
		w.standAt(GearService.Range + 4)
		refused(w, "Buy", { Line = "Boots", Level = 1 }, "TooFar", "far away")
		w.player.Character = nil
		refused(w, "Buy", { Line = "Boots", Level = 1 }, "TooFar", "no character")
		-- no save loaded (joining / leaving): still one answer, nothing bought
		w.loaded = false
		local result = act(w, "Buy", { Line = "Boots", Level = 1 })
		T.eq(result.Ok, false)
		T.eq(result.Reason, "BadItem", "no data: BadItem")
		T.eq(#w.bought, 0, "nothing bought")
		T.eq(#notes(w, "Notify"), 0, "no toasts for refusals")
	end)

	withWorld("GearService: broken or newer saves never lose levels or coins", function(w)
		w.data.Coins = 1e9
		-- no Gear record at all: made on the first buy (before the coins are taken)
		w.data.Gear = nil
		T.eq(buy(w, "Gloves", 1).Ok, true, "a missing record")
		T.eq(w.data.Gear.Gloves, 1)
		w.data.Gear = "junk"
		T.eq(buy(w, "Magnet", 1).Ok, true, "a junk record")
		T.eq(type(w.data.Gear), "table")
		T.eq(w.data.Gear.Magnet, 1)
		-- a newer server gave Boots 7: never lowered, "Max" here
		w.data.Gear = { Boots = 7, HelmetLamp = 2, Backpack = 0, Gloves = 0, Magnet = 0, Cape = 3 }
		Bonuses.invalidate(w.player)
		local coins = w.data.Coins
		refused(w, "Buy", { Line = "Boots", Level = 8 }, "Max", "a newer level")
		refused(w, "Buy", { Line = "Boots", Level = 6 }, "Max", "the level after our top")
		T.eq(w.data.Gear.Boots, 7, "kept")
		T.eq(w.data.Gear.Cape, 3, "an unknown line is kept")
		T.eq(buy(w, "HelmetLamp", 3).Ok, true, "the next lamp level")
		T.eq(w.data.Gear.Cape, 3, "still kept")
		T.eq(w.data.Coins, coins - GearConfig.ById.HelmetLamp.Prices[3])
		T.eq(w.player.attrs[GearConfig.LampAttribute], 3)
		-- a fractional / junk saved level counts as its clamp (GearConfig.level)
		w.data.Gear.Backpack = 2.7
		T.eq(buy(w, "Backpack", 3).Ok, true, "2.7 counts as 2")
		T.eq(w.data.Gear.Backpack, 3)
	end)

	withWorld("GearService: fuzz: coins and levels always add up", function(w)
		local rng = Rng.new(4242)
		w.data.Coins = 5e7
		local spent = 0
		local levels = 0
		for _ = 1, 600 do
			local line = LINES[rng:int(1, #LINES)]
			local roll = rng:int(1, 10)
			local level: any = GearConfig.level(w.data.Gear, line) + 1
			if roll == 1 then
				level = level + 1
			elseif roll == 2 then
				level = level - 1
			elseif roll == 3 then
				line = "Nope"
			end
			if rng:int(1, 8) == 1 then
				w.standAt(GearService.Range + 2)
			else
				w.standAt(2)
			end
			local coins = w.data.Coins
			local before = GearConfig.level(w.data.Gear, line)
			local result = act(w, "Buy", { Line = line, Level = level })
			if result.Ok then
				local price = GearConfig.ById[line].Prices[before + 1]
				T.eq(coins - w.data.Coins, price, "paid the price of the next level")
				T.eq(w.data.Gear[line], before + 1, "one level")
				T.eq(result.Level, before + 1)
				spent += price
				levels += 1
			else
				T.eq(w.data.Coins, coins, "refused: coins kept")
				T.truthy(Reasons[result.Reason], "a known reason: " .. tostring(result.Reason))
			end
			T.truthy(w.data.Coins >= 0, "never below zero")
		end
		local total = 0
		for _, line in LINES do
			local n = w.data.Gear[line]
			T.truthy(n >= 0 and n <= GearConfig.MaxLevel, "level in range " .. line)
			total += n
		end
		T.eq(total, levels, "every level paid for is saved")
		T.eq(5e7 - w.data.Coins, spent, "coins spent = coins gone")
		T.truthy(levels > 10, "the fuzz bought things")
	end)

	---------------------------------------------------------------- the Ore Magnet

	-- A clean copper chunk of `owner` at `position`, released long ago (no Delay), in the world.
	local function chunk(w: any, owner: number, position: any): any
		local record = ItemService.spawnDesc({ K = "Clean", O = "Copper", G = "Rough" }, owner, CFrame.new(position), nil, true)
		record.Model.Parent = w.world
		record.ReleasedAt = -100
		return record
	end

	local function magnetWorld(w: any, radius: number, clear: boolean?)
		w.radius = radius
		w.clear = if clear == nil then true else clear
		ItemService._test.setMagnet(function(p)
			return if p == w.player then w.radius else 0
		end, function()
			return w.clear
		end)
		-- out in the mine, far from every base
		w.player.root.Position = Vector3.new(0, 3, -200)
		w.player.root.CFrame = CFrame.new(0, 3, -200)
		w.other.root.Position = Vector3.new(0, 3, -200)
		w.other.root.CFrame = CFrame.new(0, 3, -200)
	end

	withWorld("Ore Magnet: bases are left alone (belts, chutes, the pen)", function(w)
		local plot = WorldLayout.Plots[1]
		local frame = WorldLayout.plotCFrame(plot)
		T.truthy(ItemService.onBase(plot.Center + Vector3.new(0, 1, 0)), "the plot's centre")
		T.truthy(ItemService.onBase((frame * CFrame.new(20, 1, -20)).Position), "a grid corner")
		T.truthy(ItemService.onBase((frame * CFrame.new(-10, 1, 50)).Position), "the yard (the Ore Pen)")
		T.truthy(ItemService.onBase((frame * CFrame.new(0, 1, -26)).Position), "the margin on the road side")
		T.falsy(ItemService.onBase(Vector3.new(0, 3, 0)), "the plaza")
		T.falsy(ItemService.onBase(Vector3.new(0, -10, -200)), "the mine")
		T.falsy(ItemService.onBase((frame * CFrame.new(0, 1, -45)).Position), "the plot road")
		for _, p in WorldLayout.Plots do
			T.truthy(ItemService.onBase(p.Center), "every plot " .. p.Id)
		end
	end)

	withWorld("Ore Magnet: magnetWants (own loose items in range, after the delay, not at your feet)", function(w)
		magnetWorld(w, 12)
		local root = w.player.root.Position
		local m = ItemService.Magnet
		local near = chunk(w, USER, root + Vector3.new(8, -2, 0))
		local wants, flat = ItemService.magnetWants(near, root, 12, 0)
		T.truthy(wants, "in range")
		T.near(flat, 8, 1e-3, "flat distance")
		T.falsy(ItemService.magnetWants(near, root, 7, 0), "out of range")
		T.falsy(ItemService.magnetWants(near, root, 0, 0), "no magnet")
		local feet = chunk(w, USER, root + Vector3.new(m.StopDistance - 0.5, -2, 0))
		T.falsy(ItemService.magnetWants(feet, root, 12, 0), "already at your feet")
		local high = chunk(w, USER, root + Vector3.new(6, m.MaxRise + 2, 0))
		T.falsy(ItemService.magnetWants(high, root, 12, 0), "far above")
		local fresh = chunk(w, USER, root + Vector3.new(0, -2, 8))
		fresh.ReleasedAt = 10
		T.falsy(ItemService.magnetWants(fresh, root, 12, 10 + m.Delay / 2), "just appeared")
		T.truthy(ItemService.magnetWants(fresh, root, 12, 10 + m.Delay), "after the delay")
		near.HandDropped = true
		T.falsy(ItemService.magnetWants(near, root, 12, 0), "dropped by hand")
		near.HandDropped = nil
		near.Model.Parent = nil
		T.falsy(ItemService.magnetWants(near, root, 12, 0), "gone")
		near.Model.Parent = w.world
		ItemService.setState(near, "Machine")
		T.falsy(ItemService.magnetWants(near, root, 12, 0), "not loose")
		-- pull speed: faster further away, within MinSpeed .. Speed
		T.eq(ItemService.pullSpeed(0), m.MinSpeed)
		T.eq(ItemService.pullSpeed(1000), m.Speed)
		T.truthy(ItemService.pullSpeed(8) > ItemService.pullSpeed(5), "faster further away")
	end)

	withWorld("Ore Magnet: own items in range slide to their owner, nobody else's", function(w)
		magnetWorld(w, 12)
		local root = w.player.root.Position
		local mine = chunk(w, USER, root + Vector3.new(8, -2, 0))
		local far = chunk(w, USER, root + Vector3.new(0, -2, 20))
		local theirs = chunk(w, OTHER, root + Vector3.new(-6, -2, 0))
		ItemService.magnetStep(0)
		local pull = mine.Pull
		T.truthy(pull and pull:IsA("LinearVelocity"), "pulled")
		T.truthy(pull.Parent == mine.Body, "in the item's body")
		T.truthy(pull.Attachment0 and pull.Attachment0.Parent == mine.Body, "with its attachment")
		T.eq(pull.VelocityConstraintMode, roblox.Enum.VelocityConstraintMode.Plane, "ground plane only: gravity and walls still act")
		T.eq(pull.RelativeTo, roblox.Enum.ActuatorRelativeTo.World)
		local v = pull.PlaneVelocity
		T.truthy(v.X < 0 and math.abs(v.Y) < 1e-6, "toward the owner (-X)")
		T.near(v.Magnitude, ItemService.pullSpeed(8), 1e-3, "pull speed")
		T.truthy(pull.MaxForce > 0, "a force")
		T.eq(mine.Model:GetAttribute(ItemService.Magnet.Attribute), USER, "the client's beam attribute")
		T.eq(mine.ClientOwnedUntil, nil, "server physics")
		T.eq(far.Pull, nil, "out of range")
		T.eq(theirs.Pull, nil, "never another player's item")
		T.eq(#ItemService._test.pulling(), 1, "one pull")
		-- it moved closer: steered, still one constraint
		mine.Body.CFrame = CFrame.new(root + Vector3.new(6, -2, 0))
		ItemService.magnetStep(0.25)
		T.truthy(mine.Pull == pull, "the same pull")
		T.near(pull.PlaneVelocity.Magnitude, ItemService.pullSpeed(6), 1e-3, "slower when close")
		-- at your feet: let go
		mine.Body.CFrame = CFrame.new(root + Vector3.new(ItemService.Magnet.StopDistance - 1, -2, 0))
		ItemService.magnetStep(0.5)
		T.eq(mine.Pull, nil, "let go")
		local alive = pcall(function()
			return pull.Parent
		end)
		T.falsy(alive, "the constraint is destroyed")
		T.eq(mine.Model:GetAttribute(ItemService.Magnet.Attribute), nil, "the attribute is gone")
		T.eq(mine.Body:FindFirstChild(ItemService.Magnet.PullName), nil, "no pull or attachment left in the body")
		T.eq(#ItemService._test.pulling(), 0)
	end)

	withWorld("Ore Magnet: never through walls (line of sight, checked again while pulling)", function(w)
		magnetWorld(w, 15, false)
		local root = w.player.root.Position
		local m = ItemService.Magnet
		local item = chunk(w, USER, root + Vector3.new(10, -2, 0))
		ItemService.magnetStep(0)
		T.eq(item.Pull, nil, "a wall in between: no pull")
		w.clear = true
		ItemService.magnetStep(1)
		T.truthy(item.Pull, "clear: pulled")
		w.clear = false
		ItemService.magnetStep(1 + m.CheckEvery / 2)
		T.truthy(item.Pull, "not checked again yet")
		ItemService.magnetStep(1 + m.CheckEvery + 0.01)
		T.eq(item.Pull, nil, "a wall now: let go")
	end)

	withWorld("Ore Magnet: the nearest MaxPulls items, and it lets go when the magnet goes away", function(w)
		magnetWorld(w, 30)
		local root = w.player.root.Position
		local m = ItemService.Magnet
		local items = {}
		for i = 1, m.MaxPulls + 4 do
			table.insert(items, chunk(w, USER, root + Vector3.new(0, -2, 5 + i)))
		end
		ItemService.magnetStep(0)
		for i, item in items do
			if i <= m.MaxPulls then
				T.truthy(item.Pull, "near item " .. i .. " pulled")
			else
				T.eq(item.Pull, nil, "far item " .. i .. " waits")
			end
		end
		-- picked up: let go, and a hand-dropped mark is cleared
		local first = items[1]
		first.HandDropped = true
		ItemService.setState(first, "Carried")
		T.eq(first.Pull, nil, "carried: no pull")
		T.eq(first.HandDropped, nil, "picked up again: the mark is gone")
		-- dead owner: every pull stops
		w.player.humanoid.Health = 0
		ItemService.magnetStep(0.25)
		T.eq(#ItemService._test.pulling(), 0, "dead: let go")
		w.player.humanoid.Health = 100
		ItemService.magnetStep(0.5)
		T.truthy(#ItemService._test.pulling() > 0, "alive again")
		-- no magnet any more
		w.radius = 0
		ItemService.magnetStep(0.75)
		T.eq(#ItemService._test.pulling(), 0, "no magnet: let go")
		for _, item in items do
			T.eq(item.Pull, nil, "no constraint left")
		end
		-- destroyed while pulled
		w.radius = 30
		ItemService.magnetStep(1)
		local pulled = ItemService._test.pulling()[1]
		ItemService.destroy(pulled)
		for _, record in ItemService._test.pulling() do
			T.truthy(record ~= pulled, "a destroyed item is forgotten")
		end
	end)

	withWorld("Ore Magnet: hand-dropped items and items on a base stay put", function(w)
		magnetWorld(w, 30)
		local root = w.player.root.Position
		local dropped = chunk(w, USER, root + Vector3.new(8, -2, 0))
		dropped.HandDropped = true
		ItemService.magnetStep(0)
		T.eq(dropped.Pull, nil, "dropped by hand")
		-- standing at your base's edge: the ore on the belts stays
		local plot = WorldLayout.Plots[2]
		local frame = WorldLayout.plotCFrame(plot)
		local stand = (frame * CFrame.new(0, 3, -40)).Position
		w.player.root.Position = stand
		w.player.root.CFrame = CFrame.new(stand)
		local onBelt = chunk(w, USER, (frame * CFrame.new(0, 1, -20)).Position)
		local onRoad = chunk(w, USER, (frame * CFrame.new(8, 1, -44)).Position)
		ItemService.magnetStep(0.25)
		T.eq(onBelt.Pull, nil, "on the base: left alone")
		T.truthy(onRoad.Pull, "on the road: pulled")
	end)

	withWorld("Ore Magnet: the radius comes from the Ore Magnet gear (Bonuses)", function(w)
		ItemService._test.setMagnet(nil, function()
			return true
		end)
		w.player.root.Position = Vector3.new(0, 3, -200)
		local root = w.player.root.Position
		local item = chunk(w, USER, root + Vector3.new(7, -2, 0))
		ItemService.magnetStep(0)
		T.eq(item.Pull, nil, "no Ore Magnet: no pull")
		w.data.Coins = 1e9
		w.standAt(2)
		T.eq(buy(w, "Magnet", 1).Ok, true)
		w.player.root.Position = root
		ItemService.magnetStep(0.25)
		T.truthy(item.Pull, "Ore Magnet I (8 studs) pulls an item 7 studs away")
	end)

	---------------------------------------------------------------- the view

	local function state(over: { [string]: any }?): { [string]: any }
		local s: { [string]: any } = {
			Coins = 0,
			Gear = { Boots = 0, HelmetLamp = 0, Backpack = 0, Gloves = 0, Magnet = 0 },
			Perks = { StrongBack = false },
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	local function cardOf(cards: { any }, line: string): any
		for _, card in cards do
			if card.Line == line then
				return card
			end
		end
		return nil
	end

	T.test("GearShopView: one card per gear line, what it gives now and next", function()
		local cards = GearShopView.cards(state(), 0)
		T.eq(#cards, #GearConfig.Lines, "five cards")
		for i, card in cards do
			T.eq(card.Line, LINES[i], "shop order")
			T.eq(card.Order, i)
			T.eq(card.Level, 0)
			T.eq(card.Chip, "LV 0/5")
			T.eq(card.Buy.Text, "BUY")
			T.eq(card.Buy.Level, 1, "asks for level 1")
			T.eq(card.Buy.Price, GearConfig.ById[card.Line].Prices[1])
			T.eq(card.PriceText, Format.money(card.Buy.Price))
			T.eq(card.Buy.CanBuy, false, "no coins")
			T.eq(card.Buy.Reason, "NoCoins")
			T.eq(card.PriceColor, Theme.Bad, "red price")
			T.falsy(card.Done)
		end
		local boots = cardOf(cards, "Boots")
		T.eq(boots.Effect, "16 → 18")
		T.eq(boots.Unit, "walk speed")
		T.eq(boots.Extra, "")
		local lamp = cardOf(cards, "HelmetLamp")
		T.eq(lamp.Effect, "Off → 18")
		T.eq(lamp.Extra, "Brightness 1.2")
		T.eq(cardOf(cards, "Magnet").Effect, "Off → 8")
		T.eq(cardOf(cards, "Gloves").Extra, "Throw x1 → x1.08")
		T.eq(cardOf(cards, "Backpack").Effect, "1 → 2")
		-- level 1 lamp, Strong Back, affordable
		local s = state()
		s.Gear.HelmetLamp = 1
		s.Gear.Gloves = 3
		s.Perks.StrongBack = true
		local rich = GearShopView.cards(s, 1e9)
		local lamp1 = cardOf(rich, "HelmetLamp")
		T.eq(lamp1.Effect, "18 → 26")
		T.eq(lamp1.Extra, "Brightness 1.2 → 1.5")
		T.eq(lamp1.Chip, "LV 1/5")
		T.eq(lamp1.Buy.Level, 2)
		T.eq(lamp1.Buy.CanBuy, true)
		T.eq(lamp1.PriceColor, Theme.Coin)
		T.eq(cardOf(rich, "Gloves").Extra, "Throw x1.24 → x1.32")
		local pack = cardOf(rich, "Backpack")
		T.eq(pack.Effect, "2 → 4", "Strong Back doubles")
		T.eq(pack.Unit, "items (Strong Back)")
		-- the top level
		local top = state()
		for _, line in LINES do
			top.Gear[line] = GearConfig.MaxLevel
		end
		for _, card in GearShopView.cards(top, 1e12) do
			T.truthy(card.Done, card.Line .. " done")
			T.eq(card.Chip, "MAX")
			T.eq(card.Buy.Text, "MAX")
			T.eq(card.Buy.CanBuy, false)
			T.eq(card.Buy.Reason, "Max")
			T.eq(card.PriceText, "TOP LEVEL")
			T.falsy(card.Effect:find("→", 1, true), card.Line .. ": no next value")
		end
		T.eq(cardOf(GearShopView.cards(top, 0), "Boots").Effect, "26")
		-- broken snapshots read as level 0
		for _, junk in { nil, 5, { Gear = "x" }, { Gear = { Boots = "3", Magnet = -2 } } } do
			local list = GearShopView.cards(junk, 0 / 0)
			T.eq(#list, 5)
			for _, card in list do
				T.eq(card.Level, 0, "junk -> level 0")
			end
		end
	end)

	T.test("GearShopView: every BUY a card offers is exactly what the server quotes", function()
		local rng = Rng.new(77)
		for _ = 1, 300 do
			local s = state()
			for _, line in LINES do
				s.Gear[line] = rng:int(0, GearConfig.MaxLevel)
			end
			local coins = rng:int(0, 3000000)
			for _, card in GearShopView.cards(s, coins) do
				local price, reason = GearConfig.quote(s.Gear, card.Line, card.Buy.Level)
				if card.Done then
					T.eq(card.Buy.Level, nil, "a done card sends no level")
					T.eq(price, nil, "nothing to buy")
					T.eq(reason, "Max", "the server says Max too")
				else
					T.eq(price, card.Buy.Price, card.Line .. " price = quote")
					T.eq(card.Buy.CanBuy, coins >= price, "affordable")
				end
			end
		end
	end)

	-- The screens the shop is laid out for (as GearShopController.fit).
	local SCREENS = {
		{ Label = "PC 1280x720", Compact = false, Width = 1280, Height = 720 - 36 },
		{ Label = "PC 1600x900", Compact = false, Width = 1600 / 1.25, Height = (900 - 36) / 1.25 },
		{ Label = "big PC", Compact = false, Width = 1536, Height = 835 },
		{ Label = "PC 4:3", Compact = false, Width = 1100, Height = 720 - 36 / 1.07 },
		{ Label = "phone", Compact = true, Width = 1600 / (0.62 * 900 / 375), Height = (900 - 58) / (0.62 * 900 / 375) },
		{ Label = "small phone", Compact = true, Width = 1600 / (0.62 * 900 / 320), Height = (900 - 163) / (0.62 * 900 / 320) },
		{ Label = "tablet", Compact = true, Width = 1024 / 0.62, Height = (768 - 36) / 0.62 },
		{ Label = "TV 1080p", Compact = true, Width = 1920 / 1.25, Height = (1080 - 36) / 1.25 },
	}

	local function boxIn(obj: any, parent: { number }): { number }
		local wd = obj.Size.X.Scale * parent[3] + obj.Size.X.Offset
		local ht = obj.Size.Y.Scale * parent[4] + obj.Size.Y.Offset
		local x = parent[1] + obj.Position.X.Scale * parent[3] + obj.Position.X.Offset - obj.AnchorPoint.X * wd
		local y = parent[2] + obj.Position.Y.Scale * parent[4] + obj.Position.Y.Offset - obj.AnchorPoint.Y * ht
		return { x, y, wd, ht }
	end

	local function faceIn(button: any, parent: { number }): { number }
		return boxIn(button, boxIn(button.Parent, parent))
	end

	local function overlaps(a: { number }, b: { number }): boolean
		return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
	end

	local function inside(a: { number }, b: { number }): boolean
		return a[1] >= b[1] - 0.01 and a[2] >= b[2] - 0.01 and a[1] + a[3] <= b[1] + b[3] + 0.01 and a[2] + a[4] <= b[2] + b[4] + 0.01
	end

	local function laidOut(screen: any): (any, { number })
		local refs = GearShopView.build(screen.Compact)
		GearShopView.layout(refs, screen.Compact, screen.Width, screen.Height)
		local size = refs.Panel.Size
		return refs, { 0, 0, size.X.Offset, size.Y.Offset }
	end

	T.test("GearShopView: layouts fit, cards stack cleanly, phone buttons are at least 44 pt", function()
		T.truthy(GearShopView.compactFor(true, false, 0.62, 375), "phones are compact")
		T.truthy(GearShopView.compactFor(false, true, 1.25, 1080), "TVs are compact")
		T.falsy(GearShopView.compactFor(false, false, 1, 720), "PC is not")
		for _, screen in SCREENS do
			local label = screen.Label
			local refs, panel = laidOut(screen)
			T.truthy(panel[3] <= math.max(560, screen.Width - 24), label .. " width fits")
			T.truthy(panel[4] <= math.max(GearShopView.MinHeight, screen.Height - 16), label .. " height fits")
			GearShopView.setCards(refs, GearShopView.cards(state(), 1e6))
			local list = boxIn(refs.List, panel)
			T.truthy(inside(list, panel), label .. " cards inside the panel")
			-- the X and the coins above the cards, apart
			local close = faceIn(refs.Close, panel)
			local balance = boxIn(refs.Balance, panel)
			T.truthy(inside(close, panel), label .. " X inside")
			T.falsy(overlaps(close, balance), label .. " X and coins")
			T.truthy(close[2] + close[4] <= list[2], label .. " X above the cards")
			local canvas = math.max(list[3], refs.List.CanvasSize.X.Offset)
			local cards = { 0, 0, canvas, list[4] }
			local faces = {}
			for _, slot in refs.SlotList do
				local card = boxIn(slot.Frame, cards)
				T.truthy(inside(card, cards), `{label} {slot.Line}: card inside the list`)
				local inner = { 0, 0, card[3], card[4] }
				-- top to bottom: showcase, title, pips, description, effect box, price, button
				local order: { any } = { slot.Showcase, slot.Title }
				if refs.ShowPips then
					table.insert(order, slot.PipBar)
				end
				if refs.ShowDescription then
					table.insert(order, slot.Description)
				end
				table.insert(order, slot.EffectBox)
				if not refs.PriceOnButton then
					table.insert(order, slot.Price)
				end
				local bottom = 0
				for _, obj in order do
					local box = boxIn(obj, inner)
					T.truthy(inside(box, inner), `{label} {slot.Line}: {obj.Name} inside the card`)
					T.truthy(box[2] >= bottom - 0.01, `{label} {slot.Line}: {obj.Name} below the one above`)
					bottom = box[2] + box[4]
				end
				local face = faceIn(slot.Button, inner)
				local lip = boxIn(slot.Button.Parent, inner)
				T.truthy(face[2] >= bottom - 0.01, `{label} {slot.Line}: BUY below the price`)
				T.truthy(inside(lip, inner), `{label} {slot.Line}: BUY inside the card`)
				local abs = { card[1] + face[1], card[2] + face[2], face[3], face[4] }
				for _, other in faces do
					T.falsy(overlaps(abs, other), `{label}: BUY buttons overlap`)
				end
				table.insert(faces, abs)
				local case = boxIn(slot.Showcase, inner)
				T.truthy(case[4] >= 40, `{label} {slot.Line}: a showcase to look at`)
				local caseBox = { 0, 0, case[3], case[4] }
				local art = boxIn(slot.Art, caseBox)
				T.truthy(inside(art, caseBox), `{label} {slot.Line}: the item inside its showcase`)
				T.falsy(overlaps(art, boxIn(slot.Chip, caseBox)), `{label} {slot.Line}: the level chip never covers the item`)
				T.truthy(art[3] >= 40, `{label} {slot.Line}: the item is big enough to see`)
			end
			if screen.Compact then
				for _, target in GearShopView.touchTargets(refs) do
					local box = boxIn(target, { 0, 0, 1000, 1000 })
					T.truthy(box[4] * GearShopView.PhoneScale >= GearShopView.MinTouch - 0.5, label .. " tall enough " .. target.Name)
					T.truthy(box[3] * GearShopView.PhoneScale >= GearShopView.MinTouch, label .. " wide enough " .. target.Name)
				end
			end
		end
		-- PC 1280 x 720: below the HUD coins, inside the screen, every row shown
		local pc = GearShopView.build(false)
		GearShopView.layout(pc, false, 1280, 720 - 36)
		local top = pc.Panel.Position.Y.Offset
		T.truthy(top >= GearShopView.CoinsBottom, "below the HUD coins")
		T.truthy(top + pc.Panel.Size.Y.Offset <= 720 - 36, "inside the screen")
		T.truthy(pc.ShowDescription and pc.ShowPips and pc.ShowExtra, "PC shows every row")
		T.eq(pc.List.ScrollingEnabled, false, "five cards side by side")
		-- the usual phone keeps the pips and the second stat
		local phone = GearShopView.build(true)
		GearShopView.layout(phone, true, SCREENS[5].Width, SCREENS[5].Height)
		T.truthy(phone.ShowExtra, "phone: second stat line")
		-- dropping rows: the description first, then the price row (onto the
		-- button), then the pips, then the second stat
		local tall = GearShopView.rows(true, 2000)
		T.truthy(tall.Description and tall.Pips and tall.Extra and not tall.PriceOnButton, "tall: everything")
		local last = tall
		for height = 600, 200, -5 do
			local r = GearShopView.rows(true, height)
			T.truthy(r.Icon >= 40, "a showcase still at " .. height)
			if r.Pips then
				T.truthy(r.Extra, "pips go before the second stat")
			end
			if not r.PriceOnButton then
				T.truthy(r.Pips and r.Extra, "the price moves before the pips go")
			end
			if r.Description then
				T.falsy(r.PriceOnButton, "the description goes first")
			end
			-- shorter never shows more
			T.truthy(not r.Description or last.Description, "monotonic description")
			T.truthy(not r.Pips or last.Pips, "monotonic pips")
			T.truthy(not r.Extra or last.Extra, "monotonic extra")
			last = r
		end
		local small = GearShopView.build(true)
		GearShopView.layout(small, true, SCREENS[6].Width, SCREENS[6].Height)
		T.truthy(small.PriceOnButton, "small phone: the price rides on the BUY button")
		T.truthy(small.ShowPips and small.ShowExtra, "small phone: pips and the second stat stay")
		GearShopView.setCards(small, GearShopView.cards(state(), 0))
		T.eq(small.Slots.Boots.Button.Text, "BUY " .. Format.money(GearConfig.ById.Boots.Prices[1]))
		T.falsy(small.Slots.Boots.Price.Visible, "no price row")
	end)

	T.test("GearShopView: every card's texts fit their boxes on every screen", function()
		local reasons = { "Already at the top level" }
		for _, text in GearShopView.StatusText do
			table.insert(reasons, text)
		end
		for _, text in Reasons do
			table.insert(reasons, text)
		end
		local states = { state() }
		local mid = state()
		mid.Gear = { Boots = 2, HelmetLamp = 3, Backpack = 4, Gloves = 4, Magnet = 4 }
		mid.Perks.StrongBack = true
		table.insert(states, mid)
		local top = state()
		for _, line in LINES do
			top.Gear[line] = GearConfig.MaxLevel
		end
		table.insert(states, top)
		for _, screen in SCREENS do
			local refs = laidOut(screen)
			for _, s in states do
				GearShopView.setCards(refs, GearShopView.cards(s, 123456789))
				for _, slot in refs.SlotList do
					local b = slot.Boxes
					local where = `{screen.Label} {slot.Line}`
					local inner = b.Width - 8
					T.truthy(TechShopView.fits(slot.Title.Text, b.Width, b.Title * 1.3, slot.Title.TextSize, false), where .. " title")
					T.truthy(TechShopView.fits(slot.Effect.Text, inner, b.Effect * 1.2, slot.Effect.TextSize, false), where .. " effect: " .. slot.Effect.Text)
					T.truthy(TechShopView.fits(slot.Unit.Text, inner, b.Unit * 1.25, slot.Unit.TextSize, false), where .. " unit: " .. slot.Unit.Text)
					T.truthy(TechShopView.fits(slot.Extra.Text, inner, b.Extra * 1.25, slot.Extra.TextSize, false), where .. " extra: " .. slot.Extra.Text)
					T.truthy(TechShopView.fits(slot.Price.Text, b.Width, b.Price * 1.25, slot.Price.TextSize, false), where .. " price")
					T.truthy(
						TechShopView.fits(slot.Button.Text, b.Width - 16, b.Button * 1.3, slot.Button.TextSize, false),
						where .. " button: " .. slot.Button.Text
					)
					if slot.Description.Visible then
						T.truthy(
							TechShopView.fits(slot.Description.Text, b.Width, b.DescriptionHeight, slot.Description.TextSize, true),
							where .. " description"
						)
					end
				end
			end
			for _, slot in refs.SlotList do
				for _, text in reasons do
					GearShopView.setStatus(refs, slot.Line, text, Theme.Bad)
					local b = slot.Boxes
					T.truthy(
						TechShopView.fits(text, b.Width - 8, b.StatusHeight, slot.Status.TextSize, true),
						`{screen.Label} {slot.Line} status: {text}`
					)
					T.falsy(slot.Effect.Visible, "the status covers the effect")
				end
				GearShopView.setStatus(refs, slot.Line, nil, nil)
				T.truthy(slot.Effect.Visible, "the effect is back")
			end
		end
	end)

	T.test("GearShopView: setCards, busy buttons, icons and the gamepad's first button", function()
		local refs = GearShopView.build(false)
		GearShopView.layout(refs, false, 1280, 684)
		local s = state()
		s.Gear.Boots = GearConfig.MaxLevel
		s.Gear.HelmetLamp = GearConfig.MaxLevel
		GearShopView.setCards(refs, GearShopView.cards(s, GearConfig.ById.Backpack.Prices[1]))
		local boots = refs.Slots.Boots
		T.eq(boots.Button.Text, "MAX")
		T.eq(boots.Title.Text, "MINER'S BOOTS")
		for _, pip in boots.Pips do
			T.eq(pip.BackgroundColor3, Theme.Good, "every pip lit at the top")
		end
		T.eq(refs.Slots.Magnet.Pips[1].BackgroundColor3, Theme.PanelDark, "level 0: no pip lit")
		-- the gamepad starts on the first card that can buy
		T.truthy(GearShopView.firstButton(refs) == refs.Slots.Backpack.Button, "the backpack is affordable")
		-- a busy button keeps its text
		local pack = refs.Slots.Backpack.Button
		pack:SetAttribute("Busy", true)
		pack.Text = "..."
		GearShopView.setCards(refs, GearShopView.cards(s, 0))
		T.eq(pack.Text, "...", "busy text kept")
		pack:SetAttribute("Busy", false)
		GearShopView.setCards(refs, GearShopView.cards(s, 0))
		T.eq(pack.Text, "BUY")
		T.truthy(GearShopView.firstButton(refs) == refs.SlotList[1].Button, "nothing affordable: the first card")
		-- coins and the header message
		GearShopView.setCoins(refs, 1234567)
		T.eq(refs.BalanceAmount.Text, Format.money(1234567))
		GearShopView.showReceipt(refs, "Miner's Boots I: walk speed 18!", Theme.Good)
		T.truthy(refs.Receipt.Visible and not refs.Subtitle.Visible, "the message replaces the subtitle")
		GearShopView.hideReceipt(refs)
		T.truthy(refs.Subtitle.Visible, "subtitle back")
		-- every line's icon is drawn
		local kinds = GearShopView.iconKinds()
		for _, line in GearConfig.Lines do
			T.truthy(table.find(kinds, line.Icon), "icon for " .. line.Id)
			T.truthy(#refs.Slots[line.Id].Art:GetChildren() >= 4, line.Id .. " drawn from frames")
		end
		-- the hint: glyphs on a gamepad
		GearShopView.setHint(refs, "", { "a", "b" })
		T.truthy(refs.PadHint.Visible and not refs.Hint.Visible, "pad hint")
		T.eq(refs.PadGlyphs[1].Image, "a")
		GearShopView.setHint(refs, "Click BUY", nil)
		T.truthy(refs.Hint.Visible and not refs.PadHint.Visible, "text hint")
	end)

	T.test("GearFx: lamp light from the snapshot, lens colors, the lamp on the forehead", function()
		-- a client module: it reads Players.LocalPlayer when it loads
		local hadLocal = rawget(Players, "LocalPlayer")
		rawset(Players, "LocalPlayer", { UserId = USER })
		local loaded, GearFxController = pcall(Loader.requirePath, "StarterPlayer.StarterPlayerScripts.Client.Controllers.GearFxController")
		rawset(Players, "LocalPlayer", hadLocal)
		T.truthy(loaded, "GearFxController loads: " .. tostring(GearFxController))
		local range, brightness = GearFxController.lightOf({ Bonuses = { LampRange = 34, LampBrightness = 1.8 } }, 3)
		T.eq(range, 34)
		T.near(brightness, 1.8, 1e-9)
		local r2, b2 = GearFxController.lightOf(nil, 2)
		T.eq(r2, GearConfig.value("HelmetLamp", 2), "no snapshot yet: the gear value")
		T.near(b2, GearConfig.value("HelmetLamp", 2, "LampBrightness"), 1e-9)
		local r3 = GearFxController.lightOf({ Bonuses = { LampRange = 500 } }, 5)
		T.eq(r3, 60, "Roblox's SpotLight range cap")
		T.truthy(GearFxController.lensColor(1) ~= GearFxController.lensColor(5), "lens changes with the level")
		local head = Vector3.new(1.2, 1.2, 1.2)
		local at = GearFxController.lampOffset(head)
		T.truthy(at.Position.Z < -0.6, "in front of the face")
		T.truthy(at.Position.Y > 0, "on the forehead")
		-- the housing's +X (the SpotLight's Face Right) looks forward and a little down
		local forward = at:VectorToWorldSpace(Vector3.new(1, 0, 0))
		T.truthy(forward.Z < -0.9, "looks forward")
		T.truthy(forward.Y < 0, "a little down")
		T.eq(GearConfig.LampBudget.MaxLights, 1, "one real light per client")
		T.falsy(GearConfig.LampBudget.Shadows, "no shadows")
	end)
end
