--[[
	The elevator's travel cinematic, the shared timeline and the server's rules
	(owner 2026-11-15): 4-6 s from GO to the controls back on every pair of
	floors, the doors shut before the server moves the character, the counter
	reaches the target; the server keeps a rider riding for the whole cinematic
	(one ride at a time), never departs to a locked floor, never charges coins
	for a ride, sends the stops and the target with "Depart", and moves nobody
	who left, died or respawned behind the shut doors ("Cancel"). Every mine
	has its arrival look and a sound that plays. Stops are the real
	MineKit.elevator; save data, players, characters and Net are small fakes;
	EconomyService runs for real.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local Config = Loader.requirePath("ReplicatedStorage.Shared.Config.ElevatorTravelConfig")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local Players = Loader.game:GetService("Players")
	local elevator = ElevatorService._test
	local timing = Config.Timing

	---------------------------------------------------------------- the timeline

	T.test("travel: 4-6 s from GO until the controls are back, on every pair of floors", function()
		local count = #MineFloors.List
		for from = 1, count do
			for to = 1, count do
				if from ~= to then
					local plan = Config.plan(from, to)
					T.truthy(plan.EndAt >= 4 and plan.EndAt <= 6, `{from} -> {to}: {plan.EndAt} s`)
					T.eq(plan.Floors, math.abs(to - from), "floors travelled")
					T.eq(plan.Down, to > from, "deeper = down")
				end
			end
		end
		-- the owner's phases: preparation 0-0.7, doors 0.7-1.5, ride 1.5-~4, arrival ~4-6
		local plan = Config.plan(1, 6)
		T.eq(plan.Enter, 0.7, "the preparation lasts 0.7 s")
		T.eq(plan.DoorsShut, 1.5, "the doors meet at 1.5 s")
		T.truthy(plan.StopAt >= 3.8 and plan.StopAt <= 4.5, "the cabin stops about 4 s in: " .. plan.StopAt)
		-- junk from the network falls back to a sane ride
		local junk = Config.plan(0 / 0, "x")
		T.truthy(junk.EndAt >= 4 and junk.EndAt <= 6, "junk")
		local same = Config.plan(3, 3)
		T.truthy(same.Floors >= 1, "never zero floors")
	end)

	T.test("travel: the phases come in order and the counter reaches the target", function()
		for _, pair in { { 1, 2 }, { 1, 6 }, { 6, 1 }, { 3, 5 }, { 5, 4 } } do
			local plan = Config.plan(pair[1], pair[2])
			local order = {
				plan.Enter,
				plan.DipMid,
				plan.DoorsCloseAt,
				plan.DoorsShut,
				plan.BrakeAt,
				plan.StopAt,
				plan.DoorsOpenAt,
				plan.OpenedAt, -- (a moment with the doors open on the new mine ...)
				plan.ExitAt, -- (... before the camera goes back to the player)
				plan.EndAt,
			}
			for i = 2, #order do
				T.truthy(order[i] > order[i - 1], `{pair[1]} -> {pair[2]}: step {i} after step {i - 1}`)
			end
			T.eq(#plan.Ticks, plan.Floors, "one tick per floor")
			local last = plan.TravelStart
			for i, tick in plan.Ticks do
				T.truthy(tick.Time > last, "ticks in order")
				T.eq(tick.Floor, pair[1] + (if plan.Down then i else -i), "counting toward the target")
				last = tick.Time
			end
			T.truthy(last <= plan.StopAt, "the counter shows the target by the stop")
			T.eq(Config.floorAt(plan, 0), pair[1], "starts at the floor left")
			T.eq(Config.floorAt(plan, plan.StopAt), pair[2], "the target at the stop")
			-- flickers only in the smooth part of the ride, never more than a few
			for _, at in plan.Flickers do
				T.truthy(at > plan.TravelStart + timing.SpeedUp and at < plan.BrakeAt, "a flicker in the ride")
			end
			T.le(#plan.Flickers, 2, "two flickers at most")
		end
	end)

	T.test("travel: the server moves the character behind shut doors; it holds the rider to the end", function()
		local plan = Config.plan(2, 3)
		T.truthy(ElevatorService.DoorsClose > plan.DoorsShut, "the doors are shut when the character moves")
		T.truthy(ElevatorService.DoorsClose < plan.BrakeAt, "long before the brake")
		for from = 1, 5 do
			local to = from + 1
			local hold = Config.hold(from, to)
			local p = Config.plan(from, to)
			T.truthy(hold < p.EndAt, "the server lets go before the client ends (no refused tap after it)")
			T.truthy(hold > p.OpenedAt - 0.5, "but not before the doors are about open")
			T.near(ElevatorService.rideTime(from, to), p.BrakeAt - p.TravelStart, 1e-9, "Duration = the ride's length")
		end
		T.truthy(Config.arriveTail() > 1, "a late Arrive still holds the rider through the arrival")
	end)

	T.test("travel: warning flashes stay under 3 a second; the arrival light stays in range", function()
		local flashes = timing.Prepare
		for i = 2, #flashes do
			T.truthy(flashes[i] - flashes[i - 1] >= 1 / 3, "at most 3 flashes a second")
		end
		T.truthy(timing.FlashOn < flashes[2] - flashes[1], "dark between the flashes")
		for id, theme in Config.Themes do
			for _, reduced in { false, true } do
				local peak = 0
				for k = 0, 60 do
					local level = Config.arrivalLight(theme, k * 0.05, reduced)
					T.truthy(level >= 0 and level <= 1, `{id}: light in 0..1`)
					peak = math.max(peak, level)
				end
				T.truthy(peak > 0.5, id .. ": the arrival lights up")
				T.eq(Config.arrivalLight(theme, 2.9, reduced), 0, id .. ": dark again before the effects end")
			end
		end
		-- reduced motion: no beat on the pulsing core, only a smooth swell
		local core = Config.Themes.HeartstoneCore
		T.truthy(core.Pulse > 0, "the core pulses")
		local a, b = Config.arrivalLight(core, 0.5, true), Config.arrivalLight(core, 0.8, true)
		T.near(a, b, 1e-9, "no beat with reduced motion")
	end)

	T.test("travel: every mine has its own arrival look and a sound that plays", function()
		local wanted = {
			Quarry = "Pebbles",
			EmberCaves = "Sparks",
			DeepHollow = "Crystals",
			SunkenPalace = "Ring",
			StormglassRift = "Arcs",
			HeartstoneCore = "Core",
		}
		for _, floor in MineFloors.List do
			local theme = Config.Themes[floor.Id]
			T.truthy(theme, floor.Name .. " has a theme (by its floor Id)")
			T.truthy(theme[wanted[floor.Id]] ~= nil, floor.Name .. ": " .. wanted[floor.Id])
			local sound = SoundConfig[theme.Sound]
			T.truthy(sound, floor.Name .. ": its sound exists")
			local id = sound.Id
			T.truthy(
				string.sub(id, 1, 14) == "rbxassetid://1" or string.sub(id, 1, 18) == "rbxasset://sounds/",
				"a sound that plays: " .. id
			)
		end
		T.eq(Config.theme("NoSuchFloor"), Config.Themes[Config.DefaultTheme], "a new floor gets a look")
		-- the owner's colours: red for the caves, blue for the hollow, violet for the Rift, magenta for the core
		local function hue(c: any): number
			local h = c:ToHSV()
			return h * 360
		end
		local light = function(id: string): any
			return Config.Themes[id].Light
		end
		T.truthy(hue(light("EmberCaves")) < 25 or hue(light("EmberCaves")) > 340, "Ember Caves: red light")
		T.truthy(hue(light("DeepHollow")) > 190 and hue(light("DeepHollow")) < 225, "Deep Hollow: blue light")
		T.truthy(hue(light("StormglassRift")) > 250 and hue(light("StormglassRift")) < 290, "Stormglass Rift: violet light")
		T.truthy(hue(light("HeartstoneCore")) > 300 and hue(light("HeartstoneCore")) < 340, "Heartstone Core: magenta light")
		T.truthy(hue(light("SunkenPalace")) > 30 and hue(light("SunkenPalace")) < 50, "Sunken Palace: golden light")
		-- every sound the cinematic plays exists
		for _, key in
			{
				"ElevatorStart",
				"ElevatorWarn",
				"ElevatorDoorClose",
				"DoorThud",
				"ElevatorHum",
				"ElevatorTick",
				"ElevatorBrake",
				"ElevatorDing",
				"ElevatorDoorOpen",
				"ElevatorArrive",
			}
		do
			T.truthy(SoundConfig[key], key)
		end
		T.truthy(SoundConfig.ElevatorHum.Looped, "the hum loops")
	end)

	---------------------------------------------------------------- the server

	local function stopCFrame(floorIndex: number): any
		return CFrame.new(floorIndex * 200, -50 * floorIndex, 0) * CFrame.Angles(0, floorIndex * 0.9, 0)
	end

	local function fakeCharacter(p: any): any
		local character: any = {}
		local root: any = { Name = "HumanoidRootPart", Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		local humanoid: any = { Health = 100 }
		character.root = root
		character.humanoid = humanoid
		character.pivots = {}
		character.FindFirstChildOfClass = function(_, class: string)
			return if class == "Humanoid" then humanoid else nil
		end
		character.FindFirstChild = function(_, name: string)
			return if name == "HumanoidRootPart" then root else nil
		end
		character.PivotTo = function(_, cf: any)
			table.insert(character.pivots, cf)
			table.insert(p.pivots, cf)
			root.CFrame = cf
			root.Position = cf.Position
		end
		root.Parent = character
		return character
	end

	local function withWorld(name: string, body: (any) -> ())
		T.test(name, function()
			local w: any = { notes = {}, now = 1000, cleaning = false }
			local p: any = { UserId = 811, Name = "Traveller", Parent = true, pivots = {} }
			p.Character = fakeCharacter(p)
			-- the stream wait is where a rider can leave, die or respawn behind the shut doors
			p.RequestStreamAroundAsync = function()
				local hook = w.onStream
				if hook then
					hook()
				end
			end
			w.player = p
			w.data = ProfileStore.deepCopy(DataTemplate)
			w.data.BlasterLevel = 10
			w.data.Coins = 1e15
			-- whichever way this build sells the elevator (once, or floor by floor), this rider owns it
			w.data.Upgrades.Elevator = true
			local floors = {}
			for _, floor in MineFloors.List do
				floors[floor.Id] = true
			end
			w.data.Upgrades.Floors = floors
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			patch(DataService, "get", function(q)
				return if q == w.player then w.data else nil
			end)
			patch(DataService, "changed", function() end)
			patch(StateService, "push", function() end)
			patch(Net, "fire", function(event, q, a)
				table.insert(w.notes, { Name = event, Player = q, A = a })
			end)
			patch(Players, "GetPlayerFromCharacter", function(_, character)
				return if character == w.player.Character then w.player else nil
			end)
			patch(Players, "GetPlayers", function()
				return { w.player }
			end)
			patch(ElevatorService, "DoorsClose", 0)
			patch(ElevatorService, "isCleaning", function()
				return w.cleaning
			end)
			elevator.reset()
			elevator.setClock(function()
				return w.now
			end)
			local map = Instance.new("Folder")
			map.Name = "Map"
			w.stops = {}
			for _, floor in MineFloors.List do
				local model = Instance.new("Model")
				model.Name = "MineFloor" .. floor.Index
				model.Parent = map
				w.stops[floor.Index] = MineKit.elevator(model, stopCFrame(floor.Index), floor.Index)
				elevator.hookStop(w.stops[floor.Index])
			end
			w.standAt = function(floorIndex: number)
				local cf = stopCFrame(floorIndex) * CFrame.new(0, 3, -6)
				local root = w.player.Character.root
				root.CFrame = cf
				root.Position = cf.Position
			end
			w.go = function(floorIndex: number): (boolean, string)
				return elevator.action(w.player, { Action = "Go", Floor = floorIndex })
			end
			w.rides = function(): { any }
				local out = {}
				for _, note in w.notes do
					if note.Name == "ElevatorRide" then
						table.insert(out, note.A)
					end
				end
				return out
			end
			local ok, err = pcall(body, w)
			elevator.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	withWorld("travel: one ride at a time, held for the whole cinematic", function(w)
		w.standAt(1)
		T.truthy(w.go(2), "the first ride")
		T.truthy(ElevatorService.isRiding(w.player), "riding")
		local hold = Config.hold(1, 2)
		-- a second GO anywhere inside the cinematic is refused and plays nothing
		for _, later in { 0.5, 2, hold - 0.05 } do
			w.now = 1000 + later
			local ok, reason = w.go(3)
			T.falsy(ok, `refused {later} s in`)
			T.eq(reason, "Cooldown")
		end
		T.eq(#w.rides(), 2, "one Depart and one Arrive, nothing more")
		T.eq(#w.player.pivots, 1, "moved once")
		-- as the cinematic ends the rider is free again (from the stop it arrived at)
		w.now = 1000 + hold + 0.01
		T.falsy(ElevatorService.isRiding(w.player), "free at the end")
		T.truthy(w.go(3), "the next ride")
		T.eq(#w.player.pivots, 2, "moved again")
	end)

	withWorld("travel: a locked floor never departs (the blaster level decides)", function(w)
		w.standAt(1)
		w.data.BlasterLevel = 6 -- floor 4 needs blaster 7
		local ok, reason = w.go(4)
		T.falsy(ok)
		T.eq(reason, "Locked")
		T.eq(#w.rides(), 0, "no Depart: no cinematic")
		T.eq(#w.player.pivots, 0, "nobody moved")
		T.falsy(ElevatorService.isRiding(w.player), "not riding")
		-- junk floors are ignored
		for _, junk in { 0, 99, 2.5, "4", 0 / 0 } do
			local okJunk = elevator.action(w.player, { Action = "Go", Floor = junk })
			T.falsy(okJunk, "junk floor " .. tostring(junk))
		end
		T.eq(#w.rides(), 0, "still nothing")
		w.data.BlasterLevel = 7
		T.truthy(w.go(4), "open with blaster 7")
	end)

	withWorld("travel: riding to a floor already open never charges coins", function(w)
		w.standAt(1)
		local coins = w.data.Coins
		T.truthy(w.go(5), "a ride")
		T.eq(w.data.Coins, coins, "no coins for the ride")
		w.now += Config.hold(1, 5) + 0.1
		T.truthy(w.go(1), "and back")
		T.eq(w.data.Coins, coins, "no coins for the ride back")
		w.now += Config.hold(5, 1) + 0.1
		T.truthy(w.go(5), "and again")
		T.eq(w.data.Coins, coins, "never")
	end)

	withWorld("travel: Depart carries the stops and the target, Arrive follows the move", function(w)
		w.standAt(2)
		T.truthy(w.go(6), "a ride")
		local rides = w.rides()
		T.eq(#rides, 2)
		local depart = rides[1]
		T.eq(depart.Phase, "Depart")
		T.eq(depart.Floor, 6)
		T.eq(depart.From, 2)
		T.eq(depart.Name, MineFloors.get(6).Name)
		local fromAt = ElevatorService.stopCFrame(w.stops[2])
		local stopAt = ElevatorService.stopCFrame(w.stops[6])
		T.near((depart.FromAt.Position - fromAt.Position).Magnitude, 0, 1e-4, "the stop left")
		T.near((depart.StopAt.Position - stopAt.Position).Magnitude, 0, 1e-4, "the target stop")
		T.near(depart.FromAt.LookVector:Dot(fromAt.LookVector), 1, 1e-4, "facing its front")
		local target = ElevatorService.arrivalCFrame(w.stops[6])
		T.near((depart.Target.Position - target.Position).Magnitude, 0, 1e-4, "where the character will stand")
		T.near((w.player.pivots[1].Position - target.Position).Magnitude, 0, 1e-4, "and stands")
		T.eq(rides[2].Phase, "Arrive")
		T.eq(rides[2].Ok, true)
	end)

	withWorld("travel: a rider stays riding while the move is under way, however late it runs", function(w)
		w.standAt(1)
		local seen: boolean? = nil
		w.onStream = function()
			-- a long server hitch inside the stream wait: far past the ride's time bound
			w.now += 60
			seen = ElevatorService.isRiding(w.player)
		end
		T.truthy(w.go(2), "departed")
		T.eq(seen, true, "still riding while the move thread runs")
		T.eq(#w.player.pivots, 1, "moved")
		-- once moved, the arrival's tail still counts (a late move pushes the end back)
		T.truthy(ElevatorService.isRiding(w.player), "riding through the arrival")
		w.now += Config.arriveTail() + 0.01
		T.falsy(ElevatorService.isRiding(w.player), "free once the arrival is over")
	end)

	for _, case in { "respawned", "died", "left" } do
		withWorld(`travel: a rider who {case} behind the shut doors is never moved`, function(w)
			w.standAt(1)
			local first = w.player.Character
			w.onStream = function()
				if case == "respawned" then
					w.player.Character = fakeCharacter(w.player)
				elseif case == "died" then
					first.humanoid.Health = 0
				else
					w.player.Parent = nil
				end
			end
			T.truthy(w.go(3), "departed")
			T.eq(#w.player.pivots, 0, "nobody moved: " .. case)
			local rides = w.rides()
			T.eq(rides[1].Phase, "Depart")
			if case == "left" then
				T.eq(#rides, 1, "nothing more for a player who left")
			else
				T.eq(rides[2].Phase, "Cancel", "the client gives the game back")
				T.eq(rides[2].Floor, 3)
			end
			T.falsy(ElevatorService.isRiding(w.player), "free again")
			-- (a respawned rider can ride again from a stop at once: the cancelled ride counts for nothing)
			if case == "respawned" then
				w.onStream = nil
				w.standAt(1)
				T.truthy(w.go(3), "rides again")
				T.eq(#w.player.pivots, 1, "now it moves")
			end
		end)
	end
end
