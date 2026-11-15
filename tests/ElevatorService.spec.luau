-- ElevatorService under Lune: the save's floors bought (old saves get an
-- empty set, Version 17 turns a bought one-time elevator into every floor with
-- a price, a broken set is repaired), the prompt on every stop, buying a floor
-- (afford / can't afford / free floor / owned / locked / too far / double tap /
-- bad floor values, never a ride), the State's floors, Go validation (a free
-- floor without a ticket, an elevator-only floor not bought, locked floors, bad
-- floor values, range, same floor, cleaning, dead, cooldown), the ride's messages (Depart
-- with From / Duration / DoorsClose, then Arrive), where a ride puts you (the
-- stop's plate in front of the cage, facing out; the floor's Entrance when
-- it has no stop) and the void catcher. Stops are built by the real MineKit.elevator; save
-- data, players, characters and Net are small fakes; EconomyService runs
-- for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local PromptConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.PromptConfig")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local Players = Loader.game:GetService("Players")

	local elevator = ElevatorService._test
	-- floor 4's ticket (Sunken Palace, blaster 7): the first floor with a price
	local PRICE = MineFloors.priceOf(4)

	local function deepEqual(a: any, b: any): boolean
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	-- stop n stands at (n * 200, -50 n, 0), turned a different way on every floor
	local function stopCFrame(floorIndex: number): any
		return CFrame.new(floorIndex * 200, -50 * floorIndex, 0) * CFrame.Angles(0, floorIndex * 0.9, 0)
	end

	local function fakePlayer(userId: number, name: string): any
		local p: any = { UserId = userId, Name = name, Parent = true, pivots = {} }
		p.root = { Name = "HumanoidRootPart", Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.humanoid = { Health = 100 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, childName: string)
				return if childName == "HumanoidRootPart" then p.root else nil
			end,
			PivotTo = function(_, cf: any)
				table.insert(p.pivots, cf)
				p.root.CFrame = cf
				p.root.Position = cf.Position
			end,
		}
		p.root.Parent = p.Character
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, pushes = 0, now = 1000, cleaning = false }
		w.player = fakePlayer(501, "Rider")
		w.data = ProfileStore.deepCopy(DataTemplate)
		w.data.BlasterLevel = 10
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
		patch(StateService, "push", function()
			w.pushes += 1
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(Players, "GetPlayerFromCharacter", function(_, character)
			return if character == w.player.Character then w.player else nil
		end)
		patch(Players, "GetPlayers", function()
			return { w.player }
		end)
		patch(ElevatorService, "DoorsClose", 0)
		patch(ElevatorService, "isCleaning", function(p)
			return p == w.player and w.cleaning
		end)
		elevator.reset()
		elevator.setClock(function()
			return w.now
		end)
		-- one stop per floor, built like the floor areas do
		w.map = Instance.new("Folder")
		w.map.Name = "Map"
		w.stops = {}
		for _, floor in MineFloors.List do
			local floorModel = Instance.new("Model")
			floorModel.Name = "MineFloor" .. floor.Index
			floorModel.Parent = w.map
			w.stops[floor.Index] = MineKit.elevator(floorModel, stopCFrame(floor.Index), floor.Index)
		end
		w.hookAll = function()
			for _, model in w.stops do
				elevator.hookStop(model)
			end
		end
		-- puts the player `away` studs in front of a stop's plate
		w.standAt = function(floorIndex: number, away: number?)
			local cf = stopCFrame(floorIndex) * CFrame.new(0, 3, -(5 + (away or 1)))
			w.player.root.CFrame = cf
			w.player.root.Position = cf.Position
		end
		w.act = function(arg: any): (boolean, string)
			return elevator.action(w.player, arg)
		end
		-- every floor with a ticket bought (what the old one-time elevator gave)
		w.buyAll = function()
			for _, floor in MineFloors.List do
				if MineFloors.priceOf(floor.Index) > 0 then
					w.data.Upgrades.Floors[floor.Id] = true
				end
			end
		end
		w.notesNamed = function(name: string): { any }
			local out = {}
			for _, note in w.notes do
				if note.Name == name then
					table.insert(out, note)
				end
			end
			return out
		end
		w.lastNotify = function(): any
			local list = w.notesNamed("Notify")
			return list[#list] and list[#list].A
		end
		w.restore = function()
			elevator.reset()
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

	---------------------------------------------------------------- save

	T.test("elevator: the save keeps the floors bought; old saves get an empty set", function()
		T.eq(type(DataTemplate.Upgrades.Floors), "table", "template: a set")
		T.eq(next(DataTemplate.Upgrades.Floors), nil, "template: nothing bought")
		T.eq(DataTemplate.Upgrades.Elevator, nil, "the one-time elevator flag is gone")
		T.eq(DataTemplate.Version, 17, "floors bought one by one: save Version 17")
		T.eq(Migrations.Latest, DataTemplate.Version, "bumped together")
		-- a save from before the elevator: Upgrades without the field
		local old = ProfileStore.deepCopy(DataTemplate)
		old.Upgrades = { Bellows = 2, ExtraSlots = 1, PenLevel = 3, PenAutomation = 1 }
		ProfileStore.reconcile(old, DataTemplate)
		T.eq(type(old.Upgrades.Floors), "table", "reconciled into Upgrades")
		T.truthy(old.Upgrades.Floors ~= DataTemplate.Upgrades.Floors, "a copy, never the template's own set")
		T.eq(old.Upgrades.Bellows, 2, "other levels kept")
		T.eq(old.Upgrades.PenLevel, 3, "pen level kept")
		Migrations.run(old)
		T.eq(next(old.Upgrades.Floors), nil, "migrations: nothing bought")
		-- floors bought survive reconcile and migrations
		local bought = ProfileStore.deepCopy(DataTemplate)
		bought.Upgrades.Floors.SunkenPalace = true
		ProfileStore.reconcile(bought, DataTemplate)
		Migrations.run(bought)
		T.eq(bought.Upgrades.Floors.SunkenPalace, true, "kept")
		T.eq(bought.Upgrades.Floors.StormglassRift, nil, "only what was bought")
		-- a broken Upgrades value is rebuilt from the template (nothing bought), with a set of its own
		local broken = ProfileStore.deepCopy(DataTemplate)
		broken.Upgrades = "junk"
		Migrations.run(broken)
		T.eq(type(broken.Upgrades.Floors), "table", "rebuilt")
		T.eq(next(broken.Upgrades.Floors), nil, "nothing bought")
		T.truthy(broken.Upgrades.Floors ~= DataTemplate.Upgrades.Floors, "never the template's own set")
	end)

	T.test("elevator: Version 17: a save that bought the one-time elevator owns every floor with a price", function()
		-- a v16 save as a v16 server left it: Upgrades.Elevator, no Floors
		local v16 = ProfileStore.deepCopy(DataTemplate)
		Migrations.run(v16)
		v16.Version = 16
		v16.Upgrades.Floors = nil
		v16.Upgrades.Elevator = true
		v16.BlasterLevel = 7 -- floors 5 and 6 open later, with the blaster
		local before = ProfileStore.deepCopy(v16)
		-- the load: the template reconciled in, then the chain
		ProfileStore.reconcile(v16, DataTemplate)
		local report = Migrations.run(v16)
		T.eq(v16.Version, Migrations.Latest)
		T.eq(v16.Upgrades.Elevator, nil, "the old flag goes")
		local priced = 0
		for _, floor in MineFloors.List do
			local paid = MineFloors.priceOf(floor.Index) > 0
			T.eq(v16.Upgrades.Floors[floor.Id], if paid then true else nil, floor.Id)
			priced += if paid then 1 else 0
		end
		T.eq(priced, 3, "floors 4-6")
		T.eq(report.Moved + report.Dropped, 0, "not a repair")
		-- the elevator rides where the blaster allows: floor 4 now, 5 and 6 bought for later
		T.truthy(ElevatorService.ridable(v16, 4), "floor 4 at blaster 7")
		T.falsy(ElevatorService.ridable(v16, 5), "floor 5 waits for blaster 8")
		v16.BlasterLevel = 9
		T.truthy(ElevatorService.ridable(v16, 6), "floor 6 at blaster 9, no second payment")
		v16.BlasterLevel = 7
		-- once: the next load changes nothing
		local copy = ProfileStore.deepCopy(v16)
		local again = Migrations.run(v16)
		T.truthy(deepEqual(copy, v16), "idempotent")
		T.eq(again.Moved + again.Dropped, 0)
		-- nothing else in the save moved
		v16.Upgrades.Floors = nil
		v16.Upgrades.Elevator = true
		v16.Version = 16
		T.truthy(deepEqual(before, v16), "everything else unchanged")

		-- an older save goes through the step too (any version: the old flag is the trigger)
		for _, version in { 3, 9, 15 } do
			local older = ProfileStore.deepCopy(before)
			older.Version = version
			ProfileStore.reconcile(older, DataTemplate)
			Migrations.run(older)
			T.eq(older.Upgrades.Elevator, nil, `v{version}: the old flag goes`)
			T.eq(older.Upgrades.Floors.HeartstoneCore, true, `v{version}: floor 6 bought`)
		end
		-- not bought (false) or junk: nothing bought, the field goes
		for _, flag in { false, "yes", 1 } :: { any } do
			local notBought = ProfileStore.deepCopy(before)
			notBought.Upgrades.Elevator = flag
			ProfileStore.reconcile(notBought, DataTemplate)
			Migrations.run(notBought)
			T.eq(notBought.Upgrades.Elevator, nil, `{tostring(flag)}: the field goes`)
			T.eq(next(notBought.Upgrades.Floors), nil, `{tostring(flag)}: nothing bought`)
		end
		-- a broken Floors next to the bought elevator: a set again, every priced floor in it
		local brokenSet = ProfileStore.deepCopy(before)
		brokenSet.Upgrades.Floors = "junk"
		Migrations.run(brokenSet)
		T.eq(brokenSet.Upgrades.Floors.SunkenPalace, true, "rebuilt and filled")
		T.eq(brokenSet.Upgrades.Floors.StormglassRift, true)
		T.eq(brokenSet.Upgrades.Floors.HeartstoneCore, true)
		-- floors bought already stay (a newer build's too)
		local mixed = ProfileStore.deepCopy(before)
		mixed.Upgrades.Floors = { SunkenPalace = true, AbyssGate = true }
		Migrations.run(mixed)
		T.eq(mixed.Upgrades.Floors.AbyssGate, true, "a newer build's floor stays")
		T.eq(mixed.Upgrades.Floors.HeartstoneCore, true, "the rest added")
	end)

	T.test("elevator: a broken Floors set is repaired, a newer build's floors stay", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		Migrations.run(data)
		data.Upgrades.Floors = "junk"
		local report = Migrations.run(data)
		T.eq(type(data.Upgrades.Floors), "table", "a set again")
		T.eq(next(data.Upgrades.Floors), nil, "nothing bought")
		T.eq(report.Dropped, 1, "the junk set")
		data.Upgrades.Floors = nil
		Migrations.run(data)
		T.eq(type(data.Upgrades.Floors), "table", "a missing set comes back")
		data.Upgrades.Floors = {
			SunkenPalace = true,
			AbyssGate = true, -- a newer build's floor
			HeartstoneCore = false,
			Bad = "yes",
			[4] = true,
			[""] = true,
			[string.rep("x", 100)] = true,
		}
		report = Migrations.run(data)
		T.eq(data.Upgrades.Floors.SunkenPalace, true, "bought: kept")
		T.eq(data.Upgrades.Floors.AbyssGate, true, "a newer build's floor: kept")
		T.eq(data.Upgrades.Floors.HeartstoneCore, nil, "false is no purchase")
		T.eq(data.Upgrades.Floors.Bad, nil, "junk value")
		T.eq(data.Upgrades.Floors[4], nil, "not an id")
		T.eq(data.Upgrades.Floors[""], nil, "empty id")
		T.eq(data.Upgrades.Floors[string.rep("x", 100)], nil, "too long for an id")
		T.eq(report.Dropped, 5, "five junk entries")
		local copy = ProfileStore.deepCopy(data)
		report = Migrations.run(data)
		T.truthy(deepEqual(copy, data), "idempotent")
		T.eq(report.Moved + report.Dropped, 0)
	end)

	T.test("elevator: bought / ridable / isUnlocked read the save safely", function()
		local function save(level: any, floors: any): any
			return { BlasterLevel = level, Upgrades = { Floors = floors } }
		end
		T.truthy(ElevatorService.bought(save(10, { SunkenPalace = true }), 4), "bought")
		T.falsy(ElevatorService.bought(save(10, { SunkenPalace = true }), 5), "another floor")
		T.falsy(ElevatorService.bought(save(10, { SunkenPalace = "yes" }), 4), "junk value")
		T.falsy(ElevatorService.bought(save(10, "junk"), 4), "junk set")
		T.falsy(ElevatorService.bought({ Upgrades = 5 }, 4), "junk upgrades")
		T.falsy(ElevatorService.bought({}, 4), "no upgrades")
		T.falsy(ElevatorService.bought(save(10, { SunkenPalace = true }), 99), "no such floor")
		T.falsy(ElevatorService.bought(save(10, { SunkenPalace = true }), 0 / 0), "NaN floor")
		-- floors you can walk to ride with the blaster alone; elevator-only floors need their ticket too
		for _, floor in MineFloors.List do
			local free = MineFloors.priceOf(floor.Index) == 0
			T.eq(ElevatorService.ridable(save(floor.MinBlaster, {}), floor.Index), free, floor.Name .. " without a ticket")
			T.truthy(ElevatorService.ridable(save(floor.MinBlaster, { [floor.Id] = true }), floor.Index), floor.Name .. " with a ticket")
			T.eq(ElevatorService.ridable(save(10, nil), floor.Index), free, floor.Name .. " with no set")
			if floor.MinBlaster > 1 then
				T.falsy(ElevatorService.isUnlocked(floor.MinBlaster - 1, floor.Index), floor.Name .. " one below")
				T.falsy(
					ElevatorService.ridable(save(floor.MinBlaster - 1, { [floor.Id] = true }), floor.Index),
					floor.Name .. " bought, blaster too weak"
				)
			end
			T.truthy(ElevatorService.isUnlocked(floor.MinBlaster, floor.Index), floor.Name .. " at its level")
		end
		T.falsy(ElevatorService.isUnlocked(99, MineFloors.ComingSoon.Index), "coming soon is never open")
		T.falsy(ElevatorService.ridable(save(99, {}), MineFloors.ComingSoon.Index), "coming soon is never ridable")
		T.eq(ElevatorService.blasterLevel({ BlasterLevel = 0 / 0 }), 1, "NaN level reads as 1")
		T.eq(ElevatorService.blasterLevel({ BlasterLevel = 7.9 }), 7, "fractions floor")
		-- the State's copy: known floors bought only
		T.truthy(
			deepEqual(
				ElevatorService.boughtFloors(save(10, { SunkenPalace = true, AbyssGate = true, HeartstoneCore = "x" })),
				{ SunkenPalace = true }
			),
			"known floors bought only"
		)
		T.truthy(deepEqual(ElevatorService.boughtFloors({ Upgrades = "junk" }), {}), "junk: none")
	end)

	---------------------------------------------------------------- prompts

	withWorld("elevator: every stop gets one prompt on its call panel", function(w)
		w.hookAll()
		w.hookAll() -- hooking twice changes nothing
		for index, model in w.stops do
			local point = model.CallPanel.PromptPoint
			local found = {}
			for _, child in point:GetChildren() do
				if child:IsA("ProximityPrompt") then
					table.insert(found, child)
				end
			end
			T.eq(#found, 1, "one prompt on floor " .. index)
			local prompt = found[1]
			T.eq(prompt.Name, ElevatorService.PromptName, "name")
			T.eq(prompt.ObjectText, "Elevator", "object text")
			T.eq(prompt.ActionText, "Use", "action text")
			T.eq(prompt.KeyboardKeyCode, PromptConfig.Keys.Main.Keyboard, "E")
			T.eq(prompt.GamepadKeyCode, PromptConfig.Keys.Main.Gamepad, "gamepad Y")
			T.eq(prompt.HoldDuration, 0, "tap")
			T.falsy(prompt.RequiresLineOfSight, "no line of sight needed")
			T.eq(ElevatorService.floorOf(model), index, "floor attribute")
		end
	end)

	withWorld("elevator: the prompt opens the view only near the stop", function(w)
		w.hookAll()
		w.standAt(2)
		elevator.open(w.player, w.stops[2])
		local opened = w.notesNamed("OpenUI")
		T.eq(#opened, 1, "opened")
		T.eq(opened[1].A, "Elevator", "kind")
		T.eq(opened[1].B.Floor, 2, "floor of the stop")
		T.eq(opened[1].B.Stop, w.stops[2], "the stop")
		T.eq(opened[1].B.Owned, nil, "(the floors bought are in State)")
		w.standAt(2, 40)
		elevator.open(w.player, w.stops[2])
		T.eq(#w.notesNamed("OpenUI"), 1, "too far: nothing")
	end)

	---------------------------------------------------------------- buying

	withWorld("elevator: buying a floor's ticket with enough coins, never a ride", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = PRICE + 250
		local ok, reason = w.act({ Action = "Buy", Floor = 4 })
		T.truthy(ok, "bought")
		T.eq(reason, "Ok")
		T.eq(w.data.Coins, 250, "the ticket's price taken")
		T.eq(w.data.Upgrades.Floors.SunkenPalace, true, "saved")
		T.eq(w.data.Upgrades.Floors.StormglassRift, nil, "only that floor")
		T.truthy(w.changed > 0, "DataService.changed")
		local note = w.lastNotify()
		T.eq(note.Kind, "Reward", "toast")
		T.eq(note.Text, "Sunken Palace unlocked!")
		T.eq(#w.player.pivots, 0, "never moved: no ride after buying")
		T.eq(#w.notesNamed("ElevatorRide"), 0, "no ride")
		T.truthy(ElevatorService.ridable(w.data, 4), "the elevator goes there now")
	end)

	withWorld("elevator: every elevator-only floor is bought on its own, at its own price", function(w)
		w.hookAll()
		w.standAt(2)
		local total = 0
		for _, floor in MineFloors.List do
			total += MineFloors.priceOf(floor.Index)
		end
		w.data.Coins = total
		for _, index in { 6, 4, 5 } do
			local floor = MineFloors.ByIndex[index]
			local before = w.data.Coins
			local ok, reason = w.act({ Action = "Buy", Floor = index })
			T.truthy(ok, floor.Name)
			T.eq(reason, "Ok")
			T.eq(before - w.data.Coins, MineFloors.priceOf(index), floor.Name .. ": its own price")
			T.eq(w.data.Upgrades.Floors[floor.Id], true, floor.Name .. " saved")
		end
		T.eq(w.data.Coins, 0, "all three paid")
		T.eq(#w.player.pivots, 0, "never moved")
	end)

	withWorld("elevator: buying without enough coins", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = PRICE - 1
		local ok, reason = w.act({ Action = "Buy", Floor = 4 })
		T.falsy(ok, "refused")
		T.eq(reason, "NoCoins")
		T.eq(w.data.Coins, PRICE - 1, "coins kept")
		T.eq(w.data.Upgrades.Floors.SunkenPalace, nil, "not bought")
		local note = w.lastNotify()
		T.eq(note.Kind, "Deny", "deny toast")
		T.truthy(note.Text:find("Sunken Palace", 1, true), "names the floor")
		T.truthy(note.Text:find(Format.money(PRICE), 1, true), "says the price")
		T.truthy(note.Text:find(Format.money(1), 1, true), "says what is missing")
	end)

	withWorld("elevator: buying twice, or when bought, never charges again", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = PRICE * 2
		local first = w.act({ Action = "Buy", Floor = 4 })
		local second, reason = w.act({ Action = "Buy", Floor = 4 })
		T.truthy(first, "first buys")
		T.falsy(second, "second refused")
		T.eq(reason, "Owned")
		T.eq(w.data.Coins, PRICE, "charged once")
		local note = w.lastNotify()
		T.eq(note.Kind, "Deny", "told")
		T.truthy(note.Text:find("Sunken Palace", 1, true), "names the floor")
	end)

	withWorld("elevator: a floor you can walk to needs no ticket", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = 1e15
		for index = 1, 3 do
			local ok, reason = w.act({ Action = "Buy", Floor = index })
			T.falsy(ok, "floor " .. index)
			T.eq(reason, "Free", "floor " .. index)
			local note = w.lastNotify()
			T.eq(note.Kind, "Deny", "told")
			T.eq(note.Text, MineFloors.ByIndex[index].Name .. " needs no ticket.")
		end
		T.eq(w.data.Coins, 1e15, "nothing spent")
		T.eq(next(w.data.Upgrades.Floors), nil, "nothing saved")
	end)

	withWorld("elevator: a floor the blaster hasn't unlocked can't be bought", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.BlasterLevel = 7
		w.data.Coins = 1e15
		local ok, reason = w.act({ Action = "Buy", Floor = 5 })
		T.falsy(ok, "floor 5 needs blaster 8")
		T.eq(reason, "Locked")
		local note = w.lastNotify()
		T.eq(note.Kind, "Deny", "told")
		T.eq(note.Text, "Stormglass Rift needs Blaster 8+.")
		T.eq(w.data.Coins, 1e15, "nothing spent")
		T.eq(w.data.Upgrades.Floors.StormglassRift, nil, "not bought")
		T.truthy(w.act({ Action = "Buy", Floor = 4 }), "floor 4 is open at blaster 7")
	end)

	withWorld("elevator: buying needs a stop nearby", function(w)
		w.hookAll()
		w.standAt(1, 40)
		w.data.Coins = PRICE
		local ok, reason = w.act({ Action = "Buy", Floor = 4 })
		T.falsy(ok)
		T.eq(reason, "TooFar")
		T.eq(w.data.Coins, PRICE, "coins kept")
		T.eq(w.data.Upgrades.Floors.SunkenPalace, nil, "not bought")
		w.standAt(1)
		T.truthy(w.act({ Action = "Buy", Floor = 4 }), "at the stop it works")
	end)

	withWorld("elevator: Buy ignores bad floor values (and the old one-time Buy)", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = 1e15
		local bad: { any } =
			{ 0, -1, 99, #MineFloors.List + 1, MineFloors.ComingSoon.Index, 4.5, "4", "x", 0 / 0, math.huge, -math.huge, true, {} }
		for _, value in bad do
			local ok, reason = w.act({ Action = "Buy", Floor = value })
			T.falsy(ok, "refused " .. tostring(value))
			T.eq(reason, "BadFloor", tostring(value))
		end
		local okNil, reasonNil = w.act({ Action = "Buy" })
		T.falsy(okNil, "no floor")
		T.eq(reasonNil, "BadFloor", "no floor")
		T.eq(w.data.Coins, 1e15, "nothing spent")
		T.eq(next(w.data.Upgrades.Floors), nil, "nothing bought")
		T.eq(#w.notesNamed("Notify"), 0, "ignored silently")
	end)

	---------------------------------------------------------------- State

	withWorld("elevator: the State carries the floors bought", function(w)
		local snapshot: any = {}
		elevator.provide(w.player, w.data, snapshot)
		T.truthy(deepEqual(snapshot.ElevatorFloors, {}), "nothing bought")
		w.hookAll()
		w.standAt(1)
		w.data.Coins = PRICE
		T.truthy(w.act({ Action = "Buy", Floor = 4 }), "bought")
		w.data.Upgrades.Floors.AbyssGate = true -- a newer build's floor stays out of this build's State
		elevator.provide(w.player, w.data, snapshot)
		T.truthy(deepEqual(snapshot.ElevatorFloors, { SunkenPalace = true }), "the floor bought")
		T.truthy(snapshot.ElevatorFloors ~= w.data.Upgrades.Floors, "a copy, not the save's own set")
	end)

	---------------------------------------------------------------- Go validation

	withWorld("elevator: Go to a floor you can walk to needs no ticket", function(w)
		w.hookAll()
		w.standAt(1)
		T.eq(next(w.data.Upgrades.Floors), nil, "nothing bought")
		local ok, reason = w.act({ Action = "Go", Floor = 3 })
		T.truthy(ok, "floor 3 without a ticket")
		T.eq(reason, "Ok")
		T.eq(#w.player.pivots, 1, "moved")
	end)

	withWorld("elevator: Go to an elevator-only floor needs its ticket", function(w)
		w.hookAll()
		w.standAt(1)
		local ok, reason = w.act({ Action = "Go", Floor = 4 })
		T.falsy(ok)
		T.eq(reason, "NotBought")
		local note = w.lastNotify()
		T.eq(note.Kind, "Deny", "told")
		T.eq(note.Text, `Buy Sunken Palace first ({Format.money(PRICE)}).`)
		T.eq(#w.player.pivots, 0, "not moved")
		-- another floor's ticket doesn't open it
		w.data.Upgrades.Floors.StormglassRift = true
		local okOther, reasonOther = w.act({ Action = "Go", Floor = 4 })
		T.falsy(okOther, "floor 5's ticket")
		T.eq(reasonOther, "NotBought")
		-- bought: the next GO rides
		w.data.Coins = PRICE
		T.truthy(w.act({ Action = "Buy", Floor = 4 }), "bought")
		T.eq(#w.player.pivots, 0, "buying never moves")
		T.truthy(w.act({ Action = "Go", Floor = 4 }), "rides")
		T.eq(#w.player.pivots, 1, "moved")
	end)

	withWorld("elevator: Go refuses floors the blaster hasn't unlocked, bought or not", function(w)
		w.hookAll()
		w.standAt(1)
		w.buyAll()
		w.data.BlasterLevel = 6
		local ok, reason = w.act({ Action = "Go", Floor = 4 })
		T.falsy(ok, "floor 4 needs 7")
		T.eq(reason, "Locked")
		T.truthy(w.lastNotify().Text:find("Blaster 7+", 1, true), "says the blaster")
		T.eq(#w.player.pivots, 0, "not moved")
		-- neither open nor bought: the blaster is what it needs first
		w.data.Upgrades.Floors = {}
		local _, first = w.act({ Action = "Go", Floor = 5 })
		T.eq(first, "Locked", "the blaster before the ticket")
		local ok3 = w.act({ Action = "Go", Floor = 3 })
		T.truthy(ok3, "floor 3 is open at 6")
	end)

	withWorld("elevator: Go ignores bad floor values and bad requests", function(w)
		w.hookAll()
		w.standAt(1)
		w.buyAll()
		local bad: { any } =
			{ 0, -1, 99, #MineFloors.List + 1, MineFloors.ComingSoon.Index, 2.5, "x", "2", 0 / 0, math.huge, -math.huge, true, {} }
		for _, value in bad do
			local ok, reason = w.act({ Action = "Go", Floor = value })
			T.falsy(ok, "refused " .. tostring(value))
			T.eq(reason, "BadFloor", tostring(value))
		end
		local okNil, reasonNil = w.act({ Action = "Go" })
		T.falsy(okNil, "nil floor")
		T.eq(reasonNil, "BadFloor", "nil floor")
		local okNone, reasonNone = w.act(nil)
		T.falsy(okNone, "no request")
		T.eq(reasonNone, "BadAction", "no request")
		for _, arg in { "Go", 5, { Action = "Fly", Floor = 2 }, { Action = 1 }, { Floor = 2 } } :: { any } do
			local ok, reason = w.act(arg)
			T.falsy(ok, "bad request")
			T.eq(reason, "BadAction", "bad request " .. tostring(arg))
		end
		local big = { Action = "Go", Floor = 2, A = 1, B = 2, C = 3 }
		local okBig, reasonBig = w.act(big)
		T.falsy(okBig, "oversized table")
		T.eq(reasonBig, "BadAction")
		T.eq(#w.player.pivots, 0, "never moved")
		T.eq(#w.notesNamed("ElevatorRide"), 0, "no ride")
	end)

	withWorld("elevator: Go needs a stop within range", function(w)
		w.hookAll()
		w.buyAll()
		w.standAt(1, ElevatorService.Range + 2)
		local ok, reason = w.act({ Action = "Go", Floor = 2 })
		T.falsy(ok, "too far")
		T.eq(reason, "TooFar")
		T.eq(#w.player.pivots, 0, "not moved")
		w.standAt(1, ElevatorService.Range - 2)
		T.truthy(w.act({ Action = "Go", Floor = 2 }), "close enough")
	end)

	withWorld("elevator: no ride during a cleaning session", function(w)
		w.hookAll()
		w.standAt(1)
		w.buyAll()
		w.cleaning = true
		local ok, reason = w.act({ Action = "Go", Floor = 2 })
		T.falsy(ok)
		T.eq(reason, "Cleaning")
		T.eq(w.lastNotify().Kind, "Deny", "told")
		T.eq(#w.player.pivots, 0, "not moved")
		w.cleaning = false
		T.truthy(w.act({ Action = "Go", Floor = 2 }), "after cleaning")
	end)

	withWorld("elevator: Go to the floor you are on is refused", function(w)
		w.hookAll()
		w.standAt(3)
		w.buyAll()
		local ok, reason = w.act({ Action = "Go", Floor = 3 })
		T.falsy(ok)
		T.eq(reason, "Here")
	end)

	withWorld("elevator: rides have a cooldown", function(w)
		w.hookAll()
		w.standAt(1)
		w.buyAll()
		T.truthy(w.act({ Action = "Go", Floor = 2 }), "first ride")
		-- now at floor 2's stop
		w.now += 1
		local ok, reason = w.act({ Action = "Go", Floor = 1 })
		T.falsy(ok, "too soon")
		T.eq(reason, "Cooldown")
		T.eq(#w.player.pivots, 1, "moved once")
		w.now += ElevatorService.Cooldown
		T.truthy(w.act({ Action = "Go", Floor = 1 }), "after the cooldown")
		T.eq(#w.player.pivots, 2, "moved again")
	end)

	---------------------------------------------------------------- targets

	withWorld("elevator: a ride ends on the target stop's plate, in front of the cage, facing out", function(w)
		w.hookAll()
		w.standAt(1)
		w.buyAll()
		local ok = w.act({ Action = "Go", Floor = 5 })
		T.truthy(ok, "ride")
		T.eq(#w.player.pivots, 1, "moved")
		local cf = w.player.pivots[1]
		local stop = w.stops[5]
		local expected = ElevatorService.arrivalCFrame(stop)
		T.near((cf.Position - expected.Position).Magnitude, 0, 1e-4, "at the arrival point")
		-- in the stop's own space: on the plate, in front of the cage (z < -2.8), root height
		local base = stop.Base
		local localPos = stopCFrame(5):PointToObjectSpace(cf.Position)
		T.lt(math.abs(localPos.X), base.Size.X / 2, "inside the plate (x)")
		T.lt(math.abs(localPos.Z), base.Size.Z / 2, "inside the plate (z)")
		T.lt(localPos.Z, -2.8, "in front of the cage")
		T.near(localPos.Y, 3.6, 1e-3, "root height above the stop floor")
		-- facing out: the stop's front, level
		local look = cf.LookVector
		T.near(look.Y, 0, 1e-4, "level")
		T.near(look:Dot(stopCFrame(5).LookVector), 1, 1e-4, "faces the stop's front")
		-- the client's ride: Depart (from, to, how long, when the doors are shut), then Arrive
		local rides = w.notesNamed("ElevatorRide")
		T.eq(#rides, 2, "two ride messages")
		local depart = rides[1].A
		T.eq(depart.Phase, "Depart")
		T.eq(depart.Floor, 5)
		T.eq(depart.From, 1, "from the stop the rider stood at")
		T.eq(depart.Name, MineFloors.get(5).Name)
		T.eq(depart.Duration, ElevatorService.rideTime(1, 5), "ride time")
		T.eq(depart.DoorsClose, ElevatorService.DoorsClose, "doors-shut time")
		T.eq(rides[2].A.Phase, "Arrive")
		T.eq(rides[2].A.Ok, true)
	end)

	T.test("elevator: ride times grow with the floors travelled, within about 2-2.5 s", function()
		local one = ElevatorService.rideTime(1, 2)
		local four = ElevatorService.rideTime(1, 5)
		T.lt(one, four, "longer for more floors")
		T.eq(ElevatorService.rideTime(5, 1), four, "the same up and down")
		T.le(four, ElevatorService.RideMax, "capped")
		T.truthy(one >= 1.8 and four <= 2.6, "about 2-2.5 s of ride (+ the doors: 2.5-3 s)")
		T.eq(ElevatorService.rideTime(nil, 3), ElevatorService.rideTime(2, 3), "unknown start = one floor")
		T.truthy(ElevatorService.DoorsClose > 0.3 and ElevatorService.DoorsClose < 1, "moves behind shut doors, soon")
	end)

	withWorld("elevator: targetFor picks the floor's stop, else its Entrance", function(w)
		w.hookAll()
		for _, floor in MineFloors.List do
			local target = ElevatorService.targetFor(floor.Index)
			T.truthy(target, "target for floor " .. floor.Index)
			local localPos = stopCFrame(floor.Index):PointToObjectSpace(target.Position)
			T.lt(localPos.Magnitude, 6, "near its own stop " .. floor.Index)
		end
		-- floor 4 without a stop: its Entrance marker in Map.MineFloor4
		elevator.reset()
		elevator.setClock(function()
			return w.now
		end)
		for index, model in w.stops do
			if index ~= 4 then
				elevator.hookStop(model)
			end
		end
		T.eq(ElevatorService.targetFor(4), nil, "no stop, no map yet")
		elevator.setMap(w.map)
		T.eq(ElevatorService.targetFor(4), nil, "no Entrance yet")
		local entrance = MineKit.marker(w.map.MineFloor4, "Entrance", CFrame.lookAt(Vector3.new(10, -170, 40), Vector3.new(10, -170, 0)))
		local target = ElevatorService.targetFor(4)
		T.truthy(target, "Entrance target")
		local above = entrance.CFrame.Position + Vector3.new(0, ElevatorService.EntranceLift, 0)
		T.near((target.Position - above).Magnitude, 0, 1e-4, "above the marker")
		T.near(target.LookVector:Dot(Vector3.new(0, 0, -1)), 1, 1e-4, "faces like the marker")
		-- and a ride there
		w.standAt(1)
		w.buyAll()
		T.truthy(w.act({ Action = "Go", Floor = 4 }), "ride to the Entrance")
		T.near((w.player.root.Position - target.Position).Magnitude, 0, 1e-4, "moved there")
	end)

	withWorld("elevator: a floor with no stop and no Entrance is refused", function(w)
		for index, model in w.stops do
			if index ~= 4 then
				elevator.hookStop(model)
			end
		end
		w.standAt(1)
		w.buyAll()
		local ok, reason = w.act({ Action = "Go", Floor = 4 })
		T.falsy(ok)
		T.eq(reason, "NoStop")
		T.eq(#w.player.pivots, 0, "not moved")
	end)

	withWorld("elevator: a dead or missing character is never moved", function(w)
		w.hookAll()
		w.standAt(1)
		w.buyAll()
		w.player.humanoid.Health = 0
		local ok, reason = w.act({ Action = "Go", Floor = 2 })
		T.falsy(ok, "a dead character doesn't ride")
		T.eq(reason, "NoCharacter")
		T.eq(#w.player.pivots, 0, "not moved")
	end)

	---------------------------------------------------------------- void catcher

	withWorld("elevator: a VoidCatcher puts a falling player back at the floor's stop", function(w)
		w.hookAll()
		local catcher = Instance.new("Part")
		catcher.Name = "VoidCatcher"
		catcher.Size = Vector3.new(300, 4, 300)
		catcher.CFrame = CFrame.new(stopCFrame(5).Position + Vector3.new(0, -60, 0))
		catcher:SetAttribute("Floor", 5)
		catcher.CanTouch = false
		elevator.hookCatcher(catcher)
		T.truthy(catcher.CanTouch, "touchable")
		-- a foot touching does nothing; the root does
		elevator.touched(catcher, { Name = "LeftFoot", Parent = w.player.Character })
		T.eq(#w.player.pivots, 0, "a foot is not the root")
		elevator.touched(catcher, w.player.root)
		T.eq(#w.player.pivots, 1, "rescued")
		local target = ElevatorService.arrivalCFrame(w.stops[5])
		T.near((w.player.root.Position - target.Position).Magnitude, 0, 1e-4, "at floor 5's stop")
		local rides = w.notesNamed("ElevatorRide")
		T.eq(rides[#rides].A.Rescue, true, "the client is told")
		-- debounced
		elevator.touched(catcher, w.player.root)
		T.eq(#w.player.pivots, 1, "debounced")
		w.now += ElevatorService.CatchDebounce
		elevator.touched(catcher, w.player.root)
		T.eq(#w.player.pivots, 2, "again after the debounce")
		-- a stranger's root is ignored
		local stranger = fakePlayer(777, "Stranger")
		elevator.touched(catcher, stranger.root)
		T.eq(#stranger.pivots, 0, "not a player here")
	end)

	withWorld("elevator: the catcher check finds roots inside or below a catcher", function(w)
		w.hookAll()
		local catcher = Instance.new("Part")
		catcher.Size = Vector3.new(100, 4, 100)
		catcher.CFrame = CFrame.new(0, -400, 0)
		catcher:SetAttribute("Floor", 5)
		catcher.Parent = w.map
		elevator.hookCatcher(catcher)
		T.truthy(ElevatorService.isCaught(catcher, Vector3.new(10, -399, 10)), "inside")
		T.truthy(ElevatorService.isCaught(catcher, Vector3.new(10, -450, -40)), "below")
		T.falsy(ElevatorService.isCaught(catcher, Vector3.new(10, -380, 10)), "above")
		T.falsy(ElevatorService.isCaught(catcher, Vector3.new(80, -410, 10)), "beside")
		T.falsy(ElevatorService.isCaught(catcher, Vector3.new(0, -402 - ElevatorService.CatchDepth - 5, 0)), "far below")
		-- the 0.5 s check over players
		w.player.root.Position = Vector3.new(0, -300, 0)
		elevator.checkCatchers()
		T.eq(#w.player.pivots, 0, "standing above: nothing")
		w.player.root.Position = Vector3.new(5, -430, 5)
		elevator.checkCatchers()
		T.eq(#w.player.pivots, 1, "fallen below: rescued")
		-- without a Floor attribute the nearest stop's floor is used
		local loose = Instance.new("Part")
		loose.Size = Vector3.new(20, 2, 20)
		loose.CFrame = CFrame.new(stopCFrame(3).Position + Vector3.new(0, -40, 0))
		elevator.hookCatcher(loose)
		w.now += ElevatorService.CatchDebounce
		elevator.touched(loose, w.player.root)
		local target = ElevatorService.arrivalCFrame(w.stops[3])
		T.near((w.player.root.Position - target.Position).Magnitude, 0, 1e-4, "nearest stop's floor")
	end)
end
