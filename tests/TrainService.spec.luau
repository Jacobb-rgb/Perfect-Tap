-- TrainService under Lune: hooks found under the railway, intake (owner only,
-- capacity, bounce when full / away), Load Train, Send, the auto-depart timer,
-- delivery into the pen (capacity, retry, one toast), the return trip, joining
-- (delivery and re-announcing), upgrades, Express, junk input and no
-- duplication. The railway hooks follow the WORLD contract; players, saves,
-- carrying, plots and Net are small fakes, items and coins are real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local Enum = roblox.Enum
	local CFrame = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local EconomyService = Loader.requirePath("ServerScriptService.Server.Services.EconomyService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
	local TrainService = Loader.requirePath("ServerScriptService.Server.Services.TrainService")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local PLOT, OTHER_PLOT = 3, 6
	local USER, OTHER, STRANGER = 701, 702, 703
	local NOW = 1.76e9 -- a plausible os.time()
	local OFFSET = 12.25 -- workspace:GetServerTimeNow() - os.time() in these tests
	local train = TrainService._test
	local CAP = TrainConfig.capacity(0, false)
	local TRIP = TrainConfig.tripSeconds(0, false)
	local COAL = { K = "Raw", O = "Coal" }
	local DIRTY_GOLD = { K = "Raw", O = "Gold" }
	local IRON = { K = "Ingot", O = "Iron", G = "Clean" }
	local GOLD = { K = "Clean", O = "Gold", G = "Pristine" }

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

	local plotModel: any = nil
	local function getPlotModel(): any
		if not plotModel then
			plotModel = PlotBuilder.buildPlot(Instance.new("Folder"), WorldLayout.Plots[PLOT], Rng.new(PLOT))
		end
		return plotModel
	end

	local function fakePlayer(userId: number, name: string): any
		local p: any = { UserId = userId, Name = name, Parent = true, attributes = {} }
		p.GetAttribute = function(self, key)
			return self.attributes[key]
		end
		p.root = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0) }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then { Health = 100 } else nil
			end,
			FindFirstChild = function(_, child: string)
				return if child == "HumanoidRootPart" then p.root else nil
			end,
		}
		p.stand = function(position: any)
			p.root.Position = position
			p.root.CFrame = CFrame.new(position)
		end
		return p
	end

	---------------------------------------------------------------- the railway hooks (WORLD contract)

	local function newPart(parent: any, name: string, cf: any, size: any): any
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = size
		part.CFrame = cf
		part.Parent = parent
		return part
	end

	local function newAttachment(parent: any, name: string, world: any): any
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = parent.CFrame:ToObjectSpace(CFrame.new(world))
		a.Parent = parent
		return a
	end

	local function hopper(parent: any, center: any, size: any): any
		local intake = newPart(parent, "Intake", CFrame.new(center + Vector3.new(0, size.Y / 2, 0)), size)
		intake.Transparency = 1
		intake.CanCollide = false
		intake.CanTouch = false
		intake.CanQuery = false
		intake:AddTag("TrainHopper")
		return intake
	end

	local function buildRailway(): any
		local railway = Instance.new("Folder")
		railway.Name = "Railway"
		local s = TrainConfig.Station
		local station = Instance.new("Model")
		station.Name = "MineStation"
		station:AddTag("TrainStation")
		station.Parent = railway
		local platform = newPart(station, "Platform", CFrame.new(s.Platform.Center), s.Platform.Size)
		newAttachment(platform, "PromptPoint", s.PromptPoint)
		newAttachment(platform, "TrainPoint", TrainConfig.QuarryStop)
		hopper(station, s.Hopper, s.HopperSize)
		-- an untagged box: not a hook
		newPart(station, "Chute", CFrame.new(s.Hopper + Vector3.new(0, 8, 0)), Vector3.new(4, 4, 4))
		for _, lift in TrainConfig.Lifts do
			local m = Instance.new("Model")
			m.Name = "Lift_" .. lift.Id
			m:SetAttribute("LiftId", lift.Id)
			m:AddTag("MineLift")
			m.Parent = railway
			local box = hopper(m, lift.Position, lift.Size)
			box:SetAttribute("LiftId", lift.Id)
			local cage = newPart(m, "Cage", CFrame.new(lift.Position + Vector3.new(0, 0.5, 0)), Vector3.new(8, 1, 8))
			newAttachment(cage, "PromptPoint", lift.Position + Vector3.new(0, 3, lift.Size.Z / 2 + 3))
		end
		return railway
	end

	---------------------------------------------------------------- world

	local function setup(): any
		local w: any = { notes = {}, all = {}, changed = {}, zones = {}, now = NOW }
		w.player = fakePlayer(USER, "Owner")
		w.other = fakePlayer(OTHER, "Neighbour")
		w.data = deepCopy(DataTemplate)
		w.otherData = deepCopy(DataTemplate)
		w.online = { [w.player] = true, [w.other] = true }
		w.plots = { [w.player] = PLOT, [w.other] = OTHER_PLOT }
		w.carried = { [w.player] = {}, [w.other] = {} }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			if not w.online[p] then
				return nil
			end
			return if p == w.player then w.data elseif p == w.other then w.otherData else nil
		end)
		patch(DataService, "changed", function(p)
			w.changed[p] = (w.changed[p] or 0) + 1
		end)
		patch(Net, "fire", function(name, p, a, b, c)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b, C = c })
		end)
		patch(Net, "fireAll", function(name, a, b, c)
			table.insert(w.all, { Name = name, A = a, B = b, C = c })
		end)
		patch(PlotService, "plotOf", function(p)
			return w.plots[p]
		end)
		patch(PlotService, "ownerOf", function(id)
			for p, plotId in w.plots do
				if plotId == id then
					return p
				end
			end
			return nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then getPlotModel() else nil
		end)
		patch(Players, "GetPlayers", function()
			return { w.player, w.other }
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == OTHER then w.other else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids = (w.ids or 0) + 1
			return "train-guid-" .. w.ids
		end)
		patch(IntakeService, "addZone", function(name, part, handler)
			table.insert(w.zones, { Name = name, Part = part, Handler = handler })
		end)
		patch(CarryService, "list", function(p)
			return w.carried[p] or {}
		end)
		patch(CarryService, "takeTop", function(p, predicate)
			local list = w.carried[p] or {}
			for i = #list, 1, -1 do
				local record = list[i]
				if not predicate or predicate(record) then
					table.remove(list, i)
					return record
				end
			end
			return nil
		end)
		ItemService._test.reset()
		EconomyService._test.reset()
		train.reset()
		train.setClock(function()
			return w.now
		end, function()
			return w.now + OFFSET
		end)
		w.railway = buildRailway()
		train.watch(w.railway)
		for _, zone in w.zones do
			w[zone.Name] = zone
		end
		w.station = w.TrainStation
		w.player.stand(TrainConfig.Station.PromptPoint)
		w.other.stand(TrainConfig.Station.PromptPoint + Vector3.new(2, 0, 0))
		w.restore = function()
			train.reset()
			ItemService._test.reset()
			EconomyService._test.reset()
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

	---------------------------------------------------------------- helpers

	local function inside(part: any, position: any): boolean
		local p = part.CFrame:PointToObjectSpace(position)
		local half = part.Size / 2
		return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
	end

	local function flat(v: any): any
		return Vector3.new(v.X, 0, v.Z)
	end

	-- A loose item of `owner` that lands in a hopper (the IntakeService scan calls the zone).
	local function drop(zone: any, owner: number, desc: any): any
		local record = ItemService.spawnDesc(desc, owner, CFrame.new(zone.Part.CFrame.Position), nil, true)
		zone.Handler(record)
		return record
	end

	local function dropMany(zone: any, owner: number, desc: any, n: number)
		for _ = 1, n do
			drop(zone, owner, desc)
		end
	end

	local function carry(w: any, p: any, desc: any): any
		local record = ItemService.spawnDesc(desc, p.UserId, CFrame.new(p.root.Position), nil, true)
		record.State = "Carried"
		table.insert(w.carried[p], record)
		return record
	end

	local function toasts(w: any, p: any, text: string): number
		local n = 0
		for _, note in w.notes do
			if note.Name == "Notify" and note.Player == p and note.A.Text == text then
				n += 1
			end
		end
		return n
	end

	local function lastToast(w: any, p: any): any
		for i = #w.notes, 1, -1 do
			local note = w.notes[i]
			if note.Name == "Notify" and note.Player == p then
				return note.A
			end
		end
		return nil
	end

	local function lastNote(w: any, name: string): any
		for i = #w.notes, 1, -1 do
			if w.notes[i].Name == name then
				return w.notes[i]
			end
		end
		return nil
	end

	-- Every "TrainTrip" sent to all players (one per departure / re-announce).
	local function trips(w: any, userId: number?): { any }
		local list = {}
		for _, note in w.all do
			if note.Name == "TrainTrip" and (userId == nil or note.A.UserId == userId) then
				table.insert(list, note.A)
			end
		end
		return list
	end

	local function unloads(w: any): { any }
		local list = {}
		for _, note in w.all do
			if note.Name == "Fx" and note.A == "TrainUnload" then
				table.insert(list, note)
			end
		end
		return list
	end

	local function snapshot(w: any, p: any): any
		local s = {}
		train.provide(p, if p == w.player then w.data else w.otherData, s)
		return s.Train
	end

	local function advance(w: any, seconds: number)
		w.now += seconds
		TrainService.tick()
	end

	local function fillPen(w: any, n: number)
		for _ = 1, n do
			table.insert(w.data.Storage, { K = "Raw", O = "Coal" })
		end
	end

	-- Items of a user in every place: the world (loose or carried), Cargo, TripCargo, the pen.
	local function census(w: any, userId: number, data: any): number
		local inWorld = #ItemService.ownedBy(userId)
		return inWorld + #data.Train.Cargo + #data.Train.TripCargo + #data.Storage
	end

	---------------------------------------------------------------- hooks

	withWorld("TrainService: every tagged hopper under the railway gets an intake zone and two prompts", function(w)
		T.eq(#w.zones, 1 + #TrainConfig.Lifts, "the station and each lift (the untagged box is no hook)")
		T.truthy(w.station and w.TrainEmberCaves and w.TrainDeepHollow, "zone names")
		T.eq(w.station.Part, w.railway.MineStation.Intake, "the station's Intake part")
		train.watch(w.railway)
		train.setupHook(w.station.Part)
		T.eq(#w.zones, 1 + #TrainConfig.Lifts, "a hook is set up only once")
		local point = w.railway.MineStation.Platform.PromptPoint
		local load = point:FindFirstChild("TrainLoadPrompt")
		local send = point:FindFirstChild("TrainSendPrompt")
		T.truthy(load and send, "both prompts on the PromptPoint")
		T.eq(load.ActionText, "Load Train", "load text")
		T.eq(send.ActionText, "Send Train", "send text")
		T.eq(load.ObjectText, "Mine Station", "object text")
		T.eq(load.KeyboardKeyCode, Enum.KeyCode.F, "F")
		T.eq(load.GamepadKeyCode, Enum.KeyCode.ButtonY, "gamepad Y")
		T.eq(send.KeyboardKeyCode, Enum.KeyCode.G, "G")
		T.eq(send.GamepadKeyCode, Enum.KeyCode.ButtonB, "gamepad B")
		T.falsy(load.RequiresLineOfSight, "no line of sight needed")
		T.truthy(load:HasTag(TrainService.PromptTag) and send:HasTag(TrainService.PromptTag), "tagged for the client")
		T.eq(load:GetAttribute("Action"), "Load", "load action")
		T.eq(send:GetAttribute("Action"), "Send", "send action")
		local liftPoint = w.railway.Lift_EmberCaves.Cage.PromptPoint
		T.eq(liftPoint.TrainLoadPrompt.ObjectText, "Mine Lift", "lift prompts")
		-- a hook without a PromptPoint keeps its prompts on itself and bounces along its LookVector
		local folder = Instance.new("Folder")
		local lone = hopper(folder, Vector3.new(0, 0, 500), Vector3.new(4, 4, 4))
		local hook = train.setupHook(lone)
		T.truthy(lone:FindFirstChild("TrainLoadPrompt") and lone:FindFirstChild("TrainSendPrompt"), "prompts on the part")
		T.near(hook.Out.Magnitude, 1, 1e-6, "unit out vector")
		T.near(hook.Out.Y, 0, 1e-6, "flat out vector")
	end)

	---------------------------------------------------------------- intake

	withWorld("TrainService: items in a hopper go into their owner's own train", function(w)
		local mine = drop(w.station, USER, COAL)
		T.eq(mine.State, "Consumed", "taken out of the world")
		T.eq(#w.data.Train.Cargo, 1, "in my cargo")
		T.eq(w.data.Train.Cargo[1].O, "Coal", "the right item")
		T.eq(#w.otherData.Train.Cargo, 0, "not in the neighbour's train")
		local fx = lastNote(w, "Fx")
		T.truthy(fx and fx.A == "TrainLoad" and fx.Player == w.player, "TrainLoad effect for the owner")
		T.eq(typeof(fx.B), "Vector3", "at a position")
		T.truthy((w.changed[w.player] or 0) > 0, "data changed")
		drop(w.station, OTHER, GOLD)
		T.eq(#w.otherData.Train.Cargo, 1, "the neighbour's item goes into the neighbour's train")
		T.eq(#w.data.Train.Cargo, 1, "mine unchanged")
		-- the lifts load the same trains
		drop(w.TrainEmberCaves, USER, IRON)
		drop(w.TrainDeepHollow, USER, DIRTY_GOLD)
		T.eq(#w.data.Train.Cargo, 3, "lifts load into the cargo too")
		T.eq(#trips(w), 0, "nobody's train has left")
		-- items in someone's hands are left alone
		local held = carry(w, w.player, COAL)
		w.station.Handler(held)
		T.eq(held.State, "Carried", "carried item untouched")
		T.eq(#w.data.Train.Cargo, 3, "not loaded")
	end)

	withWorld("TrainService: items nobody can take bounce out toward the prompts", function(w)
		local stray = drop(w.station, STRANGER, COAL) -- its owner left
		T.eq(stray.State, "Loose", "not taken")
		T.falsy(inside(w.station.Part, stray.Body.CFrame.Position), "out of the hopper box")
		local toward = flat(TrainConfig.Station.PromptPoint - w.station.Part.CFrame.Position)
		local moved = flat(stray.Body.CFrame.Position - w.station.Part.CFrame.Position)
		T.lt(0, toward.Unit:Dot(moved.Unit), "toward the prompt side")
		w.online[w.other] = false
		local unloaded = drop(w.station, OTHER, COAL)
		T.eq(unloaded.State, "Loose", "owner's data not loaded: not taken")
		w.online[w.other] = true
		w.plots[w.other] = nil
		local homeless = drop(w.station, OTHER, COAL)
		T.eq(homeless.State, "Loose", "owner without a plot: not taken")
		T.eq(#w.data.Train.Cargo + #w.otherData.Train.Cargo, 0, "nothing loaded anywhere")
		-- lifts bounce toward their own prompts
		local lift = drop(w.TrainEmberCaves, STRANGER, COAL)
		T.falsy(inside(w.TrainEmberCaves.Part, lift.Body.CFrame.Position), "out of the lift box")
	end)

	withWorld("TrainService: a full train leaves at once; while away, items bounce with a throttled toast", function(w)
		dropMany(w.station, USER, COAL, CAP - 1)
		T.eq(#w.data.Train.Cargo, CAP - 1, "loading")
		T.eq(#trips(w), 0, "not full yet")
		drop(w.station, USER, GOLD)
		local t = w.data.Train
		T.eq(#t.Cargo, 0, "the cargo left")
		T.eq(#t.TripCargo, CAP, "all of it is on the train")
		T.eq(t.TripDepartAt, w.now, "saved departure (os.time)")
		T.eq(t.TripArriveAt, w.now + TRIP, "saved arrival (os.time)")
		local list = trips(w)
		T.eq(#list, 1, "one TrainTrip to everyone")
		local trip = list[1]
		T.eq(trip.UserId, USER, "user")
		T.eq(trip.PlotId, PLOT, "plot")
		T.eq(trip.Count, CAP, "count")
		T.near(trip.DepartAt, w.now + OFFSET, 1e-6, "server-time departure")
		T.near(trip.ArriveAt, w.now + OFFSET + TRIP, 1e-6, "server-time arrival")
		T.eq(trip.Color, getPlotModel().Banner.Color, "the plot banner color")
		T.eq(#trip.Load, 2, "dirt and gold")
		T.eq(trip.Load[1], ItemBuilder.DirtyCrust, "dirty ore shows as dirt, most first")
		T.eq(trip.Load[2], OreData.ById.Gold.Color, "cleaned gold shows its color")
		-- the train is away: items bounce, the toast is throttled
		local bounced = drop(w.station, USER, COAL)
		T.eq(bounced.State, "Loose", "bounced")
		T.falsy(inside(w.station.Part, bounced.Body.CFrame.Position), "out of the box")
		T.eq(toasts(w, w.player, TrainService.AwayText), 1, "told once")
		T.eq(lastNote(w, "Fx").A, "Reject", "reject effect")
		drop(w.station, USER, COAL)
		T.eq(toasts(w, w.player, TrainService.AwayText), 1, "throttled")
		w.now += 6
		drop(w.station, USER, COAL)
		T.eq(toasts(w, w.player, TrainService.AwayText), 2, "told again later")
		T.eq(#t.TripCargo, CAP, "nothing joined the moving train")
		T.eq(#t.Cargo, 0, "nothing waits at the station")
		-- dirty ore never shows its ore color on the wagon
		T.eq(TrainService.loadColors({ DIRTY_GOLD, DIRTY_GOLD })[1], ItemBuilder.DirtyCrust, "dirty gold is dirt")
	end)

	withWorld("TrainService: a full cargo that could not leave yet bounces items with 'press Send'", function(w)
		-- loaded with Express, then the perk ended: 12 waiting, room for 8
		for _ = 1, TrainConfig.capacity(0, true) do
			table.insert(w.data.Train.Cargo, { K = "Raw", O = "Coal" })
		end
		local bounced = drop(w.station, USER, COAL)
		T.eq(bounced.State, "Loose", "bounced")
		T.eq(toasts(w, w.player, TrainService.FullText), 1, "full toast")
		drop(w.station, USER, COAL)
		T.eq(toasts(w, w.player, TrainService.FullText), 1, "throttled")
		advance(w, 1)
		T.eq(#w.data.Train.TripCargo, TrainConfig.capacity(0, true), "the loop sends a full train off")
		T.eq(#trips(w, USER), 1, "announced")
		-- the save cap always holds the biggest train
		T.le(TrainConfig.capacity(TrainConfig.maxLevel(TrainConfig.Capacity), true), TrainConfig.MaxCargoSaved, "save cap")
	end)

	withWorld("TrainService: Express carries 50 % more and makes the trip twice as fast", function(w)
		w.player.attributes.Perk_TrainExpress = true
		local cap = TrainConfig.capacity(0, true)
		local s = snapshot(w, w.player)
		T.truthy(s.Express, "Express")
		T.eq(s.Capacity, cap, "capacity")
		T.eq(s.TripSeconds, TrainConfig.tripSeconds(0, true), "trip seconds")
		dropMany(w.station, USER, COAL, cap - 1)
		T.eq(#trips(w), 0, "room for more than the normal train")
		drop(w.station, USER, COAL)
		local t = w.data.Train
		T.eq(#t.TripCargo, cap, "left when full")
		T.eq(t.TripArriveAt - t.TripDepartAt, TrainConfig.tripSeconds(0, true), "half the trip")
		T.lt(t.TripArriveAt - t.TripDepartAt, TRIP, "faster than without")
	end)

	---------------------------------------------------------------- departure

	withWorld("TrainService: a train with cargo leaves AutoDepartSeconds after the last load", function(w)
		dropMany(w.station, USER, COAL, 2)
		T.eq(snapshot(w, w.player).AutoDepartIn, TrainConfig.AutoDepartSeconds, "counting down")
		advance(w, 10)
		drop(w.station, USER, COAL) -- a new load starts the wait again
		advance(w, TrainConfig.AutoDepartSeconds - 1)
		T.eq(#trips(w), 0, "not yet")
		T.eq(snapshot(w, w.player).AutoDepartIn, 1, "one second left")
		advance(w, 1)
		local list = trips(w, USER)
		T.eq(#list, 1, "left by itself")
		T.eq(list[1].Count, 3, "with everything")
		T.eq(snapshot(w, w.player).AutoDepartIn, nil, "no countdown on the move")
		-- an empty train never leaves by itself
		advance(w, 100)
		T.eq(#trips(w, OTHER), 0, "the neighbour's empty train stays")
	end)

	withWorld("TrainService: Send leaves at once with what is loaded, from anywhere", function(w)
		train.action(w.player, "Send")
		T.eq(#trips(w), 0, "nothing to send")
		T.eq(toasts(w, w.player, TrainService.EmptyText), 1, "empty toast")
		dropMany(w.station, USER, COAL, 2)
		w.player.stand(Vector3.new(400, 3, 400))
		train.action(w.player, "Send")
		local list = trips(w, USER)
		T.eq(#list, 1, "sent from far away")
		T.eq(list[1].Count, 2, "with 2 items")
		T.eq(#w.data.Train.Cargo, 0, "cargo moved")
		train.action(w.player, "Send")
		T.eq(#trips(w, USER), 1, "can't send twice")
		T.eq(toasts(w, w.player, TrainService.AwayText), 1, "on its way")
		local s = snapshot(w, w.player)
		T.eq(s.Moving, 2, "moving")
		T.eq(s.Cargo, 0, "nothing waiting")
		T.near(s.DepartAt, list[1].DepartAt, 1e-6, "same departure as the clients got")
		T.near(s.ArriveAt, list[1].ArriveAt, 1e-6, "same arrival as the clients got")
	end)

	---------------------------------------------------------------- arrival

	withWorld("TrainService: on arrival the ore goes into the pen, then the train rolls back", function(w)
		drop(w.station, USER, COAL)
		drop(w.station, USER, GOLD)
		drop(w.TrainEmberCaves, USER, IRON)
		TrainService.send(w.player)
		advance(w, TRIP - 1)
		T.eq(#w.data.Train.TripCargo, 3, "still on the way")
		T.eq(#w.data.Storage, 0, "pen untouched")
		advance(w, 1)
		local t = w.data.Train
		T.eq(#w.data.Storage, 3, "unloaded into the pen")
		T.eq(#t.TripCargo, 0, "train empty")
		T.eq(t.TripDepartAt, 0, "trip cleared")
		T.eq(t.TripArriveAt, 0, "trip cleared")
		T.eq(w.data.Stats.TrainTrips, 1, "trip counted")
		local fx = unloads(w)
		T.eq(#fx, 1, "TrainUnload for everyone")
		T.eq(fx[1].B, PLOT, "at my plot")
		T.eq(fx[1].C, 3, "count")
		local s = snapshot(w, w.player)
		T.eq(s.Moving, 0, "nothing moving")
		T.eq(s.ArriveAt, nil, "no trip times")
		T.near(s.ReturnAt, w.now + OFFSET + TrainConfig.ReturnSeconds, 1e-6, "rolling back")
		-- rolling back: no loading yet
		local bounced = drop(w.station, USER, COAL)
		T.eq(bounced.State, "Loose", "still away")
		advance(w, TrainConfig.ReturnSeconds)
		T.eq(snapshot(w, w.player).ReturnAt, nil, "back at the station")
		drop(w.station, USER, COAL)
		T.eq(#w.data.Train.Cargo, 1, "loading again")
	end)

	withWorld("TrainService: a full pen keeps the rest on the train and retries with one toast", function(w)
		local capacity = ItemService.penCapacity(w.data)
		fillPen(w, capacity - 2)
		dropMany(w.station, USER, GOLD, 5)
		TrainService.send(w.player)
		advance(w, TRIP)
		local t = w.data.Train
		T.eq(#w.data.Storage, capacity, "pen filled up")
		T.eq(#t.TripCargo, 3, "the rest waits on the train")
		T.eq(toasts(w, w.player, TrainService.PenFullText), 1, "one toast")
		T.eq(#unloads(w), 0, "not unloaded yet")
		T.truthy(t.TripArriveAt > 0, "the trip is not over")
		TrainService.tick()
		advance(w, TrainConfig.DeliveryRetry)
		T.eq(#t.TripCargo, 3, "still full")
		T.eq(toasts(w, w.player, TrainService.PenFullText), 1, "still one toast")
		T.eq(drop(w.station, USER, COAL).State, "Loose", "the train is not back: no loading")
		for _ = 1, 3 do
			table.remove(w.data.Storage)
		end
		advance(w, TrainConfig.DeliveryRetry - 1)
		T.eq(#t.TripCargo, 3, "waits for the next try")
		advance(w, 1)
		T.eq(#t.TripCargo, 0, "delivered")
		T.eq(#w.data.Storage, capacity, "pen full again, nothing over")
		T.eq(w.data.Stats.TrainTrips, 1, "one trip")
		local fx = unloads(w)
		T.eq(#fx, 1, "unloaded once")
		T.eq(fx[1].C, 5, "the whole load counts")
		T.eq(toasts(w, w.player, TrainService.PenFullText), 1, "never repeated")
		-- the next trip may warn again
		advance(w, TrainConfig.ReturnSeconds)
		drop(w.station, USER, GOLD)
		TrainService.send(w.player)
		advance(w, TRIP)
		T.eq(toasts(w, w.player, TrainService.PenFullText), 2, "a new trip, a new toast")
	end)

	---------------------------------------------------------------- joining

	withWorld("TrainService: joining delivers a trip that arrived while you were away, without animation", function(w)
		local t = w.data.Train
		for _ = 1, 4 do
			table.insert(t.TripCargo, { K = "Raw", O = "Coal" })
		end
		t.TripDepartAt = NOW - 200
		t.TripArriveAt = NOW - 170
		table.insert(t.Cargo, { K = "Raw", O = "Iron" })
		table.insert(t.Cargo, { K = "Raw", O = "Iron" })
		train.loaded(w.player, w.data)
		T.eq(#w.data.Storage, 4, "delivered into the pen")
		T.eq(#t.TripCargo, 0, "train empty")
		T.eq(t.TripArriveAt, 0, "trip over")
		T.eq(w.data.Stats.TrainTrips, 1, "counted")
		T.eq(#unloads(w), 0, "no unload animation")
		T.eq(#trips(w), 0, "no trip to animate")
		T.truthy(lastToast(w, w.player).Text:find("while you were away", 1, true), "told")
		local list = lastNote(w, "TrainTrip")
		T.truthy(list and list.Player == w.player and #list.A == 0, "an (empty) list of trips for the joiner")
		local s = snapshot(w, w.player)
		T.eq(s.ReturnAt, nil, "no return trip after a delivery while away")
		T.eq(s.AutoDepartIn, TrainConfig.AutoDepartSeconds, "the waiting cargo counts down again")
		drop(w.station, USER, COAL)
		T.eq(#t.Cargo, 3, "loading right away")
	end)

	withWorld("TrainService: joining with a full pen keeps the rest on the train and retries", function(w)
		local t = w.data.Train
		fillPen(w, ItemService.penCapacity(w.data) - 1)
		for _ = 1, 3 do
			table.insert(t.TripCargo, { K = "Clean", O = "Gold", G = "Rough" })
		end
		t.TripDepartAt = NOW - 100
		t.TripArriveAt = NOW - 70
		train.loaded(w.player, w.data)
		T.eq(#t.TripCargo, 2, "two wait on the train")
		T.eq(toasts(w, w.player, TrainService.PenFullText), 1, "pen full toast")
		table.remove(w.data.Storage)
		table.remove(w.data.Storage)
		advance(w, TrainConfig.DeliveryRetry)
		T.eq(#t.TripCargo, 0, "delivered on the retry")
		T.eq(w.data.Stats.TrainTrips, 1, "counted once")
	end)

	withWorld("TrainService: joining mid-trip announces the trip again; the joiner gets everyone's trips", function(w)
		dropMany(w.station, OTHER, COAL, 2)
		TrainService.send(w.other)
		T.eq(#trips(w, OTHER), 1, "the neighbour's train is on its way")
		-- the owner joins with a trip that left 10 s ago (the plot comes after the data)
		local t = w.data.Train
		for _ = 1, 3 do
			table.insert(t.TripCargo, { K = "Raw", O = "Copper" })
		end
		t.TripDepartAt = w.now - 10
		t.TripArriveAt = w.now + TRIP - 10
		w.plots[w.player] = nil
		train.loaded(w.player, w.data)
		T.eq(#trips(w, USER), 0, "no plot yet: not announced")
		local list = lastNote(w, "TrainTrip")
		T.truthy(list and list.Player == w.player, "a list for the joiner")
		T.eq(#list.A, 1, "the neighbour's trip")
		T.eq(list.A[1].UserId, OTHER, "whose")
		T.eq(list.A[1].Count, 2, "count")
		w.plots[w.player] = PLOT
		train.announce(w.player) -- PlotService.onAssigned
		local mine = trips(w, USER)
		T.eq(#mine, 1, "announced to everyone")
		T.near(mine[1].DepartAt, w.now + OFFSET - 10, 1e-6, "departure in server time")
		T.near(mine[1].ArriveAt, w.now + OFFSET + TRIP - 10, 1e-6, "arrival in server time")
		T.eq(mine[1].Count, 3, "count")
		train.announce(w.player)
		T.eq(#trips(w, USER), 1, "only once")
		T.eq(drop(w.station, USER, COAL).State, "Loose", "the train is away")
		advance(w, TRIP - 10)
		T.eq(#w.data.Storage, 3, "arrives as usual")
		T.eq(#unloads(w), 1, "mine unloaded")
		advance(w, 10)
		T.eq(#w.otherData.Storage, 2, "the neighbour's too")
		T.eq(#unloads(w), 2, "both trains unloaded")
	end)

	withWorld("TrainService: a save from a skewed clock never makes a trip longer than a full trip", function(w)
		local t = w.data.Train
		table.insert(t.TripCargo, { K = "Raw", O = "Coal" })
		t.TripDepartAt = w.now + 4000
		t.TripArriveAt = w.now + 5000
		train.loaded(w.player, w.data)
		T.le(t.TripArriveAt, w.now + TRIP, "arrival clamped")
		T.le(t.TripDepartAt, t.TripArriveAt, "departs before it arrives")
		local trip = trips(w, USER)[1]
		T.truthy(trip, "announced")
		T.le(trip.ArriveAt, w.now + OFFSET + TRIP, "clients get the clamped time")
		advance(w, TRIP)
		T.eq(#w.data.Storage, 1, "delivered in time")
	end)

	---------------------------------------------------------------- Load Train

	withWorld("TrainService: Load Train loads what you carry while there is room", function(w)
		local hook = train.setupHook(w.station.Part)
		train.load(w.player, hook)
		T.truthy(lastToast(w, w.player).Text:find("Carry ore", 1, true), "empty hands hint")
		for _ = 1, 5 do
			carry(w, w.player, COAL)
		end
		train.load(w.player, hook)
		T.eq(#w.data.Train.Cargo, 5, "loaded")
		T.eq(#w.carried[w.player], 0, "hands empty")
		T.eq(lastNote(w, "Fx").A, "TrainLoad", "load effect")
		for _ = 1, 6 do
			carry(w, w.player, IRON)
		end
		train.load(w.player, hook)
		T.eq(#w.data.Train.TripCargo, CAP, "filled up and left")
		T.eq(#w.carried[w.player], 6 - (CAP - 5), "the rest stays in your hands")
		T.eq(lastToast(w, w.player).Text, TrainService.AwayText, "told the train left")
		train.load(w.player, hook)
		T.eq(#w.data.Train.Cargo, 0, "nothing loads while it is away")
		-- back again: too far away does nothing
		advance(w, TRIP)
		advance(w, TrainConfig.ReturnSeconds)
		w.player.stand(TrainConfig.Station.PromptPoint + Vector3.new(0, 0, 60))
		train.load(w.player, hook)
		T.eq(#w.data.Train.Cargo, 0, "too far")
		w.player.stand(TrainConfig.Station.PromptPoint)
		-- an item of someone else in your stack (never happens) is not loaded
		local foreign = ItemService.spawnDesc(COAL, OTHER, CFrame.new(0, 5, 0), nil, true)
		foreign.State = "Carried"
		table.insert(w.carried[w.player], 1, foreign)
		train.load(w.player, hook)
		T.eq(#w.data.Train.Cargo, 3, "only your own items")
		T.eq(#w.carried[w.player], 1, "one left in your hands")
		T.eq(w.carried[w.player][1], foreign, "the foreign one stays")
		-- a stranger without data or plot does nothing
		local stranger = fakePlayer(STRANGER, "Stranger")
		stranger.stand(TrainConfig.Station.PromptPoint)
		train.load(stranger, hook)
		T.eq(#w.data.Train.Cargo, 3, "unchanged")
	end)

	---------------------------------------------------------------- upgrades

	withWorld("TrainService: upgrades cost the next price, stop at the top and need the coins", function(w)
		local price = TrainConfig.nextPrice(TrainConfig.Capacity, 0)
		w.data.Coins = price - 1
		train.action(w.player, "Upgrade", { Kind = "Capacity" })
		T.eq(w.data.Train.CapacityLevel, 0, "too poor")
		T.eq(w.data.Coins, price - 1, "nothing paid")
		T.truthy(lastToast(w, w.player).Text:find("You need", 1, true), "told the price")
		w.data.Coins = price
		train.action(w.player, "Upgrade", { Kind = "Capacity" })
		T.eq(w.data.Train.CapacityLevel, 1, "level 1")
		T.eq(w.data.Coins, 0, "paid")
		T.eq(lastToast(w, w.player).Kind, "Reward", "celebrated")
		local s = snapshot(w, w.player)
		T.eq(s.Capacity, TrainConfig.Capacity[2].Value, "bigger cargo")
		T.eq(s.NextCapacityPrice, TrainConfig.Capacity[3].Price, "next price")
		-- speed to the top
		local total = 0
		for level = 1, TrainConfig.maxLevel(TrainConfig.Speed) do
			total += TrainConfig.Speed[level + 1].Price
		end
		w.data.Coins = total + 5
		for _ = 1, TrainConfig.maxLevel(TrainConfig.Speed) + 2 do
			train.action(w.player, "Upgrade", { Kind = "Speed" })
		end
		T.eq(w.data.Train.SpeedLevel, TrainConfig.maxLevel(TrainConfig.Speed), "top level")
		T.eq(w.data.Coins, 5, "paid every level once")
		T.truthy(lastToast(w, w.player).Text:find("top level", 1, true), "maxed toast")
		s = snapshot(w, w.player)
		T.eq(s.NextSpeedPrice, nil, "no next price")
		T.eq(s.TripSeconds, TrainConfig.Speed[#TrainConfig.Speed].Value, "fastest trip")
		-- the next trip is faster
		drop(w.station, USER, COAL)
		TrainService.send(w.player)
		local t = w.data.Train
		T.eq(t.TripArriveAt - t.TripDepartAt, TrainConfig.Speed[#TrainConfig.Speed].Value, "fast trip")
	end)

	withWorld("TrainService: junk TrainAction input changes nothing", function(w)
		dropMany(w.station, USER, COAL, 2)
		w.data.Coins = 1e9
		local junk: { any } = {
			{ nil, nil },
			{ 42, nil },
			{ "send", nil },
			{ "Sendd", nil },
			{ string.rep("S", 100), nil },
			{ {}, nil },
			{ "Upgrade", nil },
			{ "Upgrade", "Capacity" },
			{ "Upgrade", { Kind = "capacity" } },
			{ "Upgrade", { Kind = 5 } },
			{ "Upgrade", { Kind = "Express" } },
			{ "Upgrade", { Kind = "CapacityLevel" } },
			{ "Upgrade", setmetatable({ Kind = "Speed" }, {}) },
			{ "Upgrade", { Kind = "Speed", A = 1, B = 2, C = 3, D = 4 } },
			{ "Upgrade", { Kind = string.rep("x", 400) } },
			{ "Upgrade", { "Capacity" } },
			{ "Upgrade", { Kind = 0 / 0 } },
		}
		for _, case in junk do
			train.action(w.player, case[1], case[2])
		end
		T.eq(w.data.Coins, 1e9, "no coins spent")
		T.eq(w.data.Train.CapacityLevel, 0, "capacity level")
		T.eq(w.data.Train.SpeedLevel, 0, "speed level")
		T.eq(#w.data.Train.Cargo, 2, "cargo untouched")
		T.eq(#trips(w), 0, "nothing sent")
		-- no data, no plot, a stranger
		w.online[w.player] = false
		train.action(w.player, "Send")
		train.action(w.player, "Upgrade", { Kind = "Speed" })
		w.online[w.player] = true
		T.eq(#trips(w), 0, "no data: nothing")
		T.eq(w.data.Train.SpeedLevel, 0, "no data: no upgrade")
		w.plots[w.player] = nil
		train.action(w.player, "Send")
		T.eq(#trips(w), 0, "no plot: the train waits")
		T.eq(#w.data.Train.Cargo, 2, "cargo kept")
		train.action(fakePlayer(STRANGER, "Stranger"), "Send")
		T.eq(#trips(w), 0, "stranger: nothing")
	end)

	---------------------------------------------------------------- duplication

	withWorld("TrainService: no duplication: every item is in exactly one place at all times", function(w)
		local rng = Rng.new("train-dupes")
		local made = 0
		local hook = train.setupHook(w.station.Part)
		local zones = { w.station, w.TrainEmberCaves, w.TrainDeepHollow }
		local descs = { COAL, DIRTY_GOLD, IRON, GOLD }
		-- a nearly full pen, so deliveries run into it
		fillPen(w, ItemService.penCapacity(w.data) - 6)
		made += #w.data.Storage
		local function check(label: string)
			T.eq(census(w, USER, w.data), made, label)
			local t = w.data.Train
			T.le(#t.Cargo + #t.TripCargo, TrainConfig.MaxCargoSaved, label .. ": save cap")
			T.le(#t.Cargo, TrainConfig.capacity(t.CapacityLevel, true), label .. ": capacity")
			if #t.TripCargo > 0 then
				T.eq(#t.Cargo, 0, label .. ": nothing waits while the train is away")
			end
		end
		for step = 1, 400 do
			local roll = rng:next()
			local label = "step " .. step
			if roll < 0.35 then
				drop(rng:pick(zones), USER, rng:pick(descs))
				made += 1
				label ..= " drop"
			elseif roll < 0.5 then
				for _ = 1, math.min(rng:int(1, 4), 8 - #w.carried[w.player]) do
					carry(w, w.player, rng:pick(descs))
					made += 1
				end
				train.load(w.player, hook)
				label ..= " load"
			elseif roll < 0.58 then
				train.action(w.player, "Send")
				label ..= " send"
			elseif roll < 0.7 then
				for _ = 1, math.min(#w.data.Storage, rng:int(1, 12)) do
					table.remove(w.data.Storage, rng:int(1, #w.data.Storage))
					made -= 1 -- sold
				end
				label ..= " sell"
			elseif roll < 0.73 then
				train.forget(w.player) -- left and came back
				train.loaded(w.player, w.data)
				label ..= " rejoin"
			elseif roll < 0.76 then
				w.player.attributes.Perk_TrainExpress = if w.player.attributes.Perk_TrainExpress then nil else true
				label ..= " express"
			else
				advance(w, rng:int(1, 9))
				label ..= " time"
			end
			check(label)
		end
		T.truthy(w.data.Stats.TrainTrips > 3, "trains really ran")
	end)
end
