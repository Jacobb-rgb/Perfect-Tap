-- ElevatorService under Lune: the save field (and that old saves get it),
-- the prompt on every stop, buying (afford / can't afford / owned / too far /
-- double tap), Go validation (not owned, locked floors, bad floor values,
-- range, same floor, cooldown), where a ride puts you (the stop's plate in
-- front of the cage, facing out; the floor's Entrance when it has no stop)
-- and the void catcher. Stops are built by the real MineKit.elevator; save
-- data, players, characters and Net are small fakes; EconomyService runs
-- for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
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
	local PRICE = MineFloors.Elevator.Price

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
		local w: any = { notes = {}, changed = 0, pushes = 0, now = 1000 }
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
		patch(ElevatorService, "Fade", 0)
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

	T.test("elevator: the save field defaults to false and old saves get it", function()
		T.eq(DataTemplate.Upgrades.Elevator, false, "template default")
		-- a save from before the elevator: Upgrades without the field
		local old = ProfileStore.deepCopy(DataTemplate)
		old.Upgrades = { Bellows = 2, ExtraSlots = 1, PenLevel = 3, PenAutomation = 1 }
		ProfileStore.reconcile(old, DataTemplate)
		T.eq(old.Upgrades.Elevator, false, "reconciled into Upgrades")
		T.eq(old.Upgrades.Bellows, 2, "other levels kept")
		T.eq(old.Upgrades.PenLevel, 3, "pen level kept")
		Migrations.run(old)
		T.eq(old.Upgrades.Elevator, false, "migrations keep the default")
		-- a bought elevator survives reconcile and migrations
		local bought = ProfileStore.deepCopy(DataTemplate)
		bought.Upgrades.Elevator = true
		ProfileStore.reconcile(bought, DataTemplate)
		Migrations.run(bought)
		T.eq(bought.Upgrades.Elevator, true, "kept")
		-- a broken Upgrades value is rebuilt from the template (not owned)
		local broken = ProfileStore.deepCopy(DataTemplate)
		broken.Upgrades = "junk"
		Migrations.run(broken)
		T.eq(broken.Upgrades.Elevator, false, "rebuilt")
	end)

	T.test("elevator: owns / isUnlocked read the save safely", function()
		T.truthy(ElevatorService.owns({ Upgrades = { Elevator = true } }), "owned")
		T.falsy(ElevatorService.owns({ Upgrades = { Elevator = false } }), "not owned")
		T.falsy(ElevatorService.owns({ Upgrades = { Elevator = "yes" } }), "junk value")
		T.falsy(ElevatorService.owns({ Upgrades = 5 }), "junk upgrades")
		T.falsy(ElevatorService.owns({}), "no upgrades")
		for _, floor in MineFloors.List do
			T.truthy(ElevatorService.isUnlocked(floor.MinBlaster, floor.Index), floor.Name .. " at its level")
			if floor.MinBlaster > 1 then
				T.falsy(ElevatorService.isUnlocked(floor.MinBlaster - 1, floor.Index), floor.Name .. " one below")
			end
		end
		T.falsy(ElevatorService.isUnlocked(99, MineFloors.ComingSoon.Index), "coming soon is never open")
		T.eq(ElevatorService.blasterLevel({ BlasterLevel = 0 / 0 }), 1, "NaN level reads as 1")
		T.eq(ElevatorService.blasterLevel({ BlasterLevel = 7.9 }), 7, "fractions floor")
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
			T.eq(prompt.KeyboardKeyCode, roblox.Enum.KeyCode.F, "F")
			T.eq(prompt.GamepadKeyCode, roblox.Enum.KeyCode.ButtonY, "gamepad Y")
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
		T.eq(opened[1].B.Owned, false, "not owned")
		w.standAt(2, 40)
		elevator.open(w.player, w.stops[2])
		T.eq(#w.notesNamed("OpenUI"), 1, "too far: nothing")
	end)

	---------------------------------------------------------------- buying

	withWorld("elevator: buying with enough coins", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = PRICE + 250
		local ok, reason = w.act({ Action = "Buy" })
		T.truthy(ok, "bought")
		T.eq(reason, "Ok")
		T.eq(w.data.Coins, 250, "price taken")
		T.eq(w.data.Upgrades.Elevator, true, "saved flag")
		T.truthy(w.changed > 0, "DataService.changed")
		T.eq(w.lastNotify().Kind, "Reward", "toast")
	end)

	withWorld("elevator: buying without enough coins", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = PRICE - 1
		local ok, reason = w.act({ Action = "Buy" })
		T.falsy(ok, "refused")
		T.eq(reason, "NoCoins")
		T.eq(w.data.Coins, PRICE - 1, "coins kept")
		T.eq(w.data.Upgrades.Elevator, false, "not owned")
		local note = w.lastNotify()
		T.eq(note.Kind, "Deny", "deny toast")
		T.truthy(note.Text:find(Format.money(PRICE), 1, true), "says the price")
		T.truthy(note.Text:find(Format.money(1), 1, true), "says what is missing")
	end)

	withWorld("elevator: buying twice, or when owned, never charges again", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Coins = PRICE * 2
		local first = w.act({ Action = "Buy" })
		local second, reason = w.act({ Action = "Buy" })
		T.truthy(first, "first buys")
		T.falsy(second, "second refused")
		T.eq(reason, "Owned")
		T.eq(w.data.Coins, PRICE, "charged once")
	end)

	withWorld("elevator: buying works away from a stop (the side menu button)", function(w)
		w.hookAll()
		w.standAt(1, 400)
		w.data.Coins = PRICE
		local ok, reason = w.act({ Action = "Buy" })
		T.truthy(ok, "bought from anywhere")
		T.eq(reason, "Ok")
		T.eq(w.data.Coins, 0, "price taken")
		T.eq(w.data.Upgrades.Elevator, true, "owned")
	end)

	---------------------------------------------------------------- Go validation

	withWorld("elevator: Go needs the elevator", function(w)
		w.hookAll()
		w.standAt(1)
		local ok, reason = w.act({ Action = "Go", Floor = 2 })
		T.falsy(ok)
		T.eq(reason, "NotOwned")
		T.eq(#w.player.pivots, 0, "not moved")
		T.eq(w.lastNotify().Kind, "Deny", "told")
	end)

	withWorld("elevator: Go refuses floors the blaster hasn't unlocked", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Upgrades.Elevator = true
		w.data.BlasterLevel = 6
		local ok, reason = w.act({ Action = "Go", Floor = 4 })
		T.falsy(ok, "floor 4 needs 7")
		T.eq(reason, "Locked")
		T.truthy(w.lastNotify().Text:find("Blaster 7+", 1, true), "says the blaster")
		T.eq(#w.player.pivots, 0, "not moved")
		local ok3 = w.act({ Action = "Go", Floor = 3 })
		T.truthy(ok3, "floor 3 is open at 6")
	end)

	withWorld("elevator: Go ignores bad floor values and bad requests", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Upgrades.Elevator = true
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

	withWorld("elevator: Go works from anywhere (the side menu button)", function(w)
		w.hookAll()
		w.data.Upgrades.Elevator = true
		w.standAt(1, 500)
		local ok, reason = w.act({ Action = "Go", Floor = 2 })
		T.truthy(ok, "far from every stop")
		T.eq(reason, "Ok")
		T.eq(#w.player.pivots, 1, "moved")
		local target = ElevatorService.arrivalCFrame(w.stops[2])
		T.near((w.player.root.Position - target.Position).Magnitude, 0, 1e-4, "at floor 2's stop")
		-- away from a stop even the floor you are on is a ride (back to its stop)
		w.now += ElevatorService.Cooldown
		w.standAt(2, 300)
		T.truthy(w.act({ Action = "Go", Floor = 2 }), "back to floor 2's stop")
	end)

	withWorld("elevator: Go to the floor you are on is refused", function(w)
		w.hookAll()
		w.standAt(3)
		w.data.Upgrades.Elevator = true
		local ok, reason = w.act({ Action = "Go", Floor = 3 })
		T.falsy(ok)
		T.eq(reason, "Here")
	end)

	withWorld("elevator: rides have a cooldown", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Upgrades.Elevator = true
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
		w.data.Upgrades.Elevator = true
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
		-- the client's fade: Depart, then Arrive
		local rides = w.notesNamed("ElevatorRide")
		T.eq(#rides, 2, "two ride messages")
		T.eq(rides[1].A.Phase, "Depart")
		T.eq(rides[1].A.Floor, 5)
		T.eq(rides[1].A.Name, MineFloors.get(5).Name)
		T.eq(rides[2].A.Phase, "Arrive")
		T.eq(rides[2].A.Ok, true)
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
		w.data.Upgrades.Elevator = true
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
		w.data.Upgrades.Elevator = true
		local ok, reason = w.act({ Action = "Go", Floor = 4 })
		T.falsy(ok)
		T.eq(reason, "NoStop")
		T.eq(#w.player.pivots, 0, "not moved")
	end)

	withWorld("elevator: a dead or missing character is never moved", function(w)
		w.hookAll()
		w.standAt(1)
		w.data.Upgrades.Elevator = true
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
