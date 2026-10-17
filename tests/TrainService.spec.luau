-- TrainService under Lune: hooks found under the railway (also added later,
-- from the station / lift root), intake (owner only, capacity, bounce when
-- full / away with the right toast, Reject throttle), Load Train, Send, the
-- auto-depart timer, the arrival timer, delivery into the pen (capacity,
-- retry, one toast, Waiting), the return trip as the client reads it,
-- joining (quiet delivery and retries, re-announcing, the Express grace),
-- banner colors, upgrades, Express, junk input, one broken train and no
-- duplication. The railway hooks follow the WORLD contract; players, saves,
-- carrying, plots and Net are small fakes, items and coins are real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local task = require("@lune/task") :: any
	local Vector3 = roblox.Vector3
	local Vector2 = roblox.Vector2
	local Color3 = roblox.Color3
	local Instance = roblox.Instance
	local Enum = roblox.Enum
	local CFrame = Loader.CFrame
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
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
		local w: any = { notes = {}, all = {}, near = {}, wakes = {}, changed = {}, zones = {}, now = NOW }
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
		patch(Net, "fireNear", function(name, position, radius, except, a, b)
			table.insert(w.near, { Name = name, Position = position, Radius = radius, Except = except, A = a, B = b })
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
		-- os.time(), the server clock and the arrival timer (kept until a test runs it)
		train.setClock(function()
			return w.now
		end, function()
			return w.now + OFFSET
		end, function(seconds, fn)
			table.insert(w.wakes, { At = w.now + OFFSET + seconds, Fn = fn })
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

	local function serverTime(w: any): number
		return w.now + OFFSET
	end

	-- Runs the arrival timers that are due (or the next one, moving the clock to it).
	local function runWakes(w: any, jump: boolean?)
		if jump and w.wakes[1] then
			w.now = math.max(w.now, w.wakes[1].At - OFFSET)
		end
		local i = 1
		while i <= #w.wakes do
			local wake = w.wakes[i]
			if wake.At <= serverTime(w) + 1e-9 then
				table.remove(w.wakes, i)
				wake.Fn()
			else
				i += 1
			end
		end
	end

	local function count(list: { any }, name: string, a: any): number
		local n = 0
		for _, note in list do
			if note.Name == name and note.A == a then
				n += 1
			end
		end
		return n
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
		-- the prompt rules: Load slot 0, Send slot 1, slot 2 (0, 144) for the client's "Train" panel prompt
		T.eq(load.UIOffset, Vector2.new(0, 0), "load in slot 0")
		T.eq(send.UIOffset, Vector2.new(0, TrainService.PromptSlotHeight), "send in slot 1")
		T.eq(load:GetAttribute("Slot"), 0, "load slot attribute")
		T.eq(send:GetAttribute("Slot"), 1, "send slot attribute")
		T.eq(TrainService.PromptSlotHeight, 72, "the machine prompts' step")
		T.eq(TrainService.PromptSlots.Panel * TrainService.PromptSlotHeight, 144, "slot 2 for the client")
		for _, prompt in point:GetChildren() do
			if prompt:IsA("ProximityPrompt") then
				T.truthy(prompt.Name ~= "TrainPrompt", "no server prompt takes the client's prompt name")
			end
		end
		T.truthy(load.Enabled and send.Enabled, "enabled (the client hides Load with empty hands)")
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

	withWorld("TrainService: the prompt point comes from the station or lift, also for a hopper in its own model", function(w)
		local s = TrainConfig.Station
		local map = Instance.new("Model")
		map.Name = "Map"
		local railway = Instance.new("Folder")
		railway.Name = "Railway"
		railway.Parent = map
		-- a PromptPoint somewhere else in the map is never used
		local elsewhere = newPart(map, "Elsewhere", CFrame.new(0, 0, 900), Vector3.new(2, 2, 2))
		newAttachment(elsewhere, "PromptPoint", Vector3.new(0, 3, 900))
		local station = Instance.new("Model")
		station.Name = "MineStation"
		station:AddTag("TrainStation")
		station.Parent = railway
		local platform = newPart(station, "Platform", CFrame.new(s.Platform.Center), s.Platform.Size)
		newAttachment(platform, "PromptPoint", s.PromptPoint)
		local hopperModel = Instance.new("Model") -- a Kenney-style hopper built as its own model
		hopperModel.Name = "Hopper"
		hopperModel.Parent = station
		local intake = hopper(hopperModel, s.Hopper, s.HopperSize)
		local hook = train.setupHook(intake)
		T.eq(hook.Name, "Mine Station", "station")
		T.lt((hook.Point - s.PromptPoint).Magnitude, 1e-4, "the station's prompt point")
		T.truthy(platform.PromptPoint:FindFirstChild("TrainLoadPrompt"), "prompts at the station's PromptPoint")
		T.falsy(intake:FindFirstChild("TrainLoadPrompt"), "not on the invisible intake")
		local toward = flat(s.PromptPoint - intake.CFrame.Position).Unit
		T.lt(0.99, hook.Out:Dot(toward), "bounces toward the prompts")
		-- a lift whose LiftId is only on its model, the intake in a sub-model
		local lift = Instance.new("Model")
		lift.Name = "Lift_Annex"
		lift:SetAttribute("LiftId", "Annex")
		lift:AddTag("MineLift")
		lift.Parent = railway
		local box = Instance.new("Model")
		box.Name = "Box"
		box.Parent = lift
		local liftIntake = hopper(box, Vector3.new(60, -12, -300), Vector3.new(6, 5, 6))
		local cage = newPart(lift, "Cage", CFrame.new(60, -11.5, -300), Vector3.new(8, 1, 8))
		newAttachment(cage, "PromptPoint", Vector3.new(60, -9, -294))
		local liftHook = train.setupHook(liftIntake)
		T.eq(liftHook.LiftId, "Annex", "lift id from the model")
		T.eq(liftHook.Name, "Mine Lift", "lift")
		T.eq(cage.PromptPoint.TrainSendPrompt.ObjectText, "Mine Lift", "prompts at the lift's PromptPoint")
		T.eq(#w.zones, 1 + #TrainConfig.Lifts + 2, "zones for both")
		T.eq(w.zones[#w.zones].Name, "TrainAnnex", "lift zone name")
		-- a hopper straight in the railway: no search above the railway (the map model)
		local bare = hopper(railway, Vector3.new(0, 0, 700), Vector3.new(4, 4, 4))
		train.setupHook(bare)
		T.truthy(bare:FindFirstChild("TrainLoadPrompt"), "prompts on the part")
		T.falsy(elsewhere.PromptPoint:FindFirstChild("TrainLoadPrompt"), "never the map's other PromptPoint")
	end)

	withWorld("TrainService: hoppers added to the railway later get their zone and prompts", function(w)
		-- the railway's DescendantAdded (the loader's instances have no live signals)
		local handlers = {}
		local added = {
			Connect = function(_, fn)
				table.insert(handlers, fn)
				return { Disconnect = function() end, Connected = true }
			end,
		}
		train.watch(w.railway, added)
		local before = #w.zones
		T.eq(before, 1 + #TrainConfig.Lifts, "the hooks are set up once")
		local lift = Instance.new("Model")
		lift.Name = "Lift_Third"
		lift:SetAttribute("LiftId", "Third")
		lift:AddTag("MineLift")
		local box = hopper(lift, Vector3.new(30, -40, -500), Vector3.new(6, 5, 6))
		box:SetAttribute("LiftId", "Third")
		local cage = newPart(lift, "Cage", CFrame.new(30, -39.5, -500), Vector3.new(8, 1, 8))
		newAttachment(cage, "PromptPoint", Vector3.new(30, -37, -494))
		lift.Parent = w.railway
		local parts = { lift :: any }
		for _, d in lift:GetDescendants() do
			table.insert(parts, d)
		end
		T.eq(#handlers, 1, "listening")
		for _, d in parts do
			handlers[1](d)
		end
		T.eq(#w.zones, before, "deferred: the model finishes building first")
		task.wait()
		T.eq(#w.zones, before + 1, "the new lift's zone")
		T.eq(w.zones[#w.zones].Name, "TrainThird", "zone name")
		T.eq(w.zones[#w.zones].Part, box, "its intake")
		T.truthy(cage.PromptPoint:FindFirstChild("TrainLoadPrompt"), "load prompt at its PromptPoint")
		T.truthy(cage.PromptPoint:FindFirstChild("TrainSendPrompt"), "send prompt")
		-- items go into the train through it
		drop(w.zones[#w.zones], USER, COAL)
		T.eq(#w.data.Train.Cargo, 1, "loads")
		-- a part tagged later (CollectionService): only under the railway
		local late = newPart(w.railway.MineStation, "Annex", CFrame.new(40, -10, -147), Vector3.new(3, 3, 3))
		late:SetAttribute("LiftId", "Late")
		late:AddTag("TrainHopper")
		train.tagged(late)
		local outside = hopper(Instance.new("Folder"), Vector3.new(0, 0, 800), Vector3.new(3, 3, 3))
		train.tagged(outside)
		task.wait()
		T.eq(#w.zones, before + 2, "the tagged part under the railway, not the one outside")
		T.eq(w.zones[#w.zones].Part, late, "the late hopper")
		train.tagged(late)
		task.wait()
		T.eq(#w.zones, before + 2, "never twice")
	end)

	---------------------------------------------------------------- intake

	withWorld("TrainService: items in a hopper go into their owner's own train", function(w)
		local mine = drop(w.station, USER, COAL)
		T.eq(mine.State, "Consumed", "taken out of the world")
		T.eq(#w.data.Train.Cargo, 1, "in my cargo")
		T.eq(w.data.Train.Cargo[1].O, "Coal", "the right item")
		T.eq(#w.otherData.Train.Cargo, 0, "not in the neighbour's train")
		-- the station is shared: everyone close by sees the load puff
		local fx = w.near[#w.near]
		T.truthy(fx and fx.Name == "Fx" and fx.A == "TrainLoad", "TrainLoad effect")
		T.eq(typeof(fx.B), "Vector3", "at a position")
		T.eq(fx.Position, fx.B, "around the hopper")
		T.le(80, fx.Radius, "for everyone near the station")
		T.eq(fx.Except, nil, "the owner too")
		T.eq(count(w.notes, "Fx", "TrainLoad"), 0, "not only for the owner")
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
		T.eq(trip.Waiting, nil, "on its way: not waiting")
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
		-- dirty ore never shows its ore color on the wagon; all dirty: {} (the client's shaded dirt)
		T.eq(#TrainService.loadColors({ DIRTY_GOLD, DIRTY_GOLD, COAL }), 0, "all dirty: no colors")
		T.eq(#TrainService.loadColors({}), 0, "nothing: no colors")
		local mixed = TrainService.loadColors({ DIRTY_GOLD, GOLD, IRON, IRON })
		T.eq(mixed[1], OreData.ById.Iron.Color, "most common first")
		T.eq(#mixed, 3, "iron, then dirt and gold")
		T.truthy(table.find(mixed, ItemBuilder.DirtyCrust) ~= nil, "dirty gold is dirt")
		T.truthy(table.find(mixed, OreData.ById.Gold.Color) ~= nil, "clean gold shows")
	end)

	withWorld("TrainService: an item that rolls back into the hopper gets the Reject effect once per cooldown", function(w)
		dropMany(w.station, USER, COAL, 2)
		TrainService.send(w.player)
		local item = drop(w.station, USER, COAL)
		T.eq(count(w.notes, "Fx", "Reject"), 1, "rejected")
		for _ = 1, 4 do
			w.now += 0.2
			w.station.Handler(item) -- it rolled back in
			T.eq(item.State, "Loose", "still refused")
			T.falsy(inside(w.station.Part, item.Body.CFrame.Position), "popped out again")
		end
		T.eq(count(w.notes, "Fx", "Reject"), 1, "no effect spam for the same item")
		w.now += GameConfig.RejectCooldown
		w.station.Handler(item)
		T.eq(count(w.notes, "Fx", "Reject"), 2, "again after the cooldown")
		drop(w.station, USER, COAL)
		T.eq(count(w.notes, "Fx", "Reject"), 3, "another item has its own effect")
		T.eq(toasts(w, w.player, TrainService.AwayText), 1, "one toast for all of it")
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
		T.eq(#list[1].Load, 0, "all dirty ore: no colors, the client shows its dirt")
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
		local trip = trips(w, USER)[1]
		advance(w, TRIP - 1)
		T.eq(#w.data.Train.TripCargo, 3, "still on the way")
		T.eq(#w.data.Storage, 0, "pen untouched")
		T.eq(snapshot(w, w.player).Waiting, false, "not waiting on the way")
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
		-- rolling back, as the client reads it: the trip times stay, back at ArriveAt + ReturnSeconds
		local s = snapshot(w, w.player)
		T.eq(s.Moving, 0, "nothing moving")
		T.eq(s.Waiting, false, "not waiting")
		T.near(s.DepartAt, trip.DepartAt, 1e-6, "the trip's departure")
		T.near(s.ArriveAt, trip.ArriveAt, 1e-6, "unloaded on time: the arrival clients animate")
		T.eq(s.ReturnAt, nil, "no field outside the contract")
		T.eq(s.AutoDepartIn, nil, "no countdown")
		local bounced = drop(w.station, USER, COAL)
		T.eq(bounced.State, "Loose", "still away")
		T.eq(lastToast(w, w.player).Text, TrainService.ReturnText, "coming back")
		train.action(w.player, "Send")
		T.eq(lastToast(w, w.player).Text, TrainService.ReturnText, "Send says the same")
		T.eq(toasts(w, w.player, TrainService.AwayText), 0, "never 'on its way' while it comes back")
		w.now = s.ArriveAt + TrainConfig.ReturnSeconds - 0.25 - OFFSET
		T.eq(drop(w.station, USER, COAL).State, "Loose", "a moment before it is back")
		w.now += 0.25
		drop(w.station, USER, COAL)
		T.eq(#t.Cargo, 1, "loading again exactly when the client shows it back")
		TrainService.tick()
		s = snapshot(w, w.player)
		T.eq(s.ArriveAt, nil, "back at the station: no trip times")
		T.eq(s.DepartAt, nil, "no trip times")
		T.eq(s.Cargo, 1, "the new load")
	end)

	withWorld("TrainService: a timer unloads the train right at its arrival (server time)", function(w)
		w.player.attributes.Perk_TrainExpress = true
		drop(w.station, USER, GOLD)
		w.now += 0.4 -- between two whole seconds
		TrainService.send(w.player)
		local trip = trips(w, USER)[1]
		T.near(trip.ArriveAt - trip.DepartAt, TrainConfig.tripSeconds(0, true), 1e-6, "an Express trip")
		T.eq(#w.wakes, 1, "one arrival timer")
		T.lt(trip.ArriveAt, w.wakes[1].At, "never before the arrival")
		T.lt(w.wakes[1].At, trip.ArriveAt + 0.1, "within a tenth of a second")
		w.now = trip.ArriveAt - 0.3 - OFFSET
		TrainService.tick()
		T.eq(#w.data.Storage, 0, "not before the arrival")
		runWakes(w, true)
		T.eq(#w.data.Storage, 1, "unloaded by the timer")
		T.eq(#unloads(w), 1, "the unload effect at the arrival")
		T.lt(serverTime(w) - trip.ArriveAt, 0.1, "right on time")
		T.near(snapshot(w, w.player).ArriveAt, trip.ArriveAt, 1e-6, "on time: the arrival clients animate")
		advance(w, 0.5)
		T.eq(#unloads(w), 1, "the loop never unloads it again")
		-- a running trip found on joining gets its timer too
		local o = w.otherData.Train
		table.insert(o.TripCargo, { K = "Raw", O = "Coal" })
		o.TripDepartAt = w.now - 5
		o.TripArriveAt = w.now + 7
		train.loaded(w.other, w.otherData)
		T.eq(#w.wakes, 1, "the joiner's arrival timer")
		runWakes(w, true)
		T.eq(#w.otherData.Storage, 1, "unloaded at its arrival")
	end)

	withWorld("TrainService: a full pen keeps the rest on the train (Waiting) and retries with one toast", function(w)
		local capacity = ItemService.penCapacity(w.data)
		fillPen(w, capacity - 2)
		dropMany(w.station, USER, GOLD, 5)
		TrainService.send(w.player)
		local trip = trips(w, USER)[1]
		advance(w, TRIP)
		local t = w.data.Train
		T.eq(#w.data.Storage, capacity, "pen filled up")
		T.eq(#t.TripCargo, 3, "the rest waits on the train")
		T.eq(toasts(w, w.player, TrainService.PenFullText), 1, "one toast")
		T.eq(#unloads(w), 0, "not unloaded yet")
		T.truthy(t.TripArriveAt > 0, "the trip is not over")
		-- everyone learns it stands at the stop: the same trip again, Waiting = true
		local list = trips(w, USER)
		T.eq(#list, 2, "TrainTrip again")
		T.eq(list[2].Waiting, true, "waiting")
		T.eq(list[2].DepartAt, trip.DepartAt, "same departure (the client keeps its train)")
		T.eq(list[2].ArriveAt, trip.ArriveAt, "same arrival")
		T.eq(list[2].Count, trip.Count, "the count it left with")
		T.eq(list[2].Load, trip.Load, "the load it left with")
		-- the snapshot as the client reads it: waiting at the stop
		local s = snapshot(w, w.player)
		T.eq(s.Waiting, true, "waiting")
		T.eq(s.Moving, 3, "on the train")
		T.near(s.ArriveAt, trip.ArriveAt, 1e-6, "it did arrive")
		-- a joiner sees it waiting too
		train.loaded(w.other, w.otherData)
		local joinList = lastNote(w, "TrainTrip")
		T.eq(joinList.Player, w.other, "the joiner's list")
		T.eq(#joinList.A, 1, "my waiting train")
		T.eq(joinList.A[1].Waiting, true, "marked waiting")
		T.eq(joinList.A[1].ArriveAt, trip.ArriveAt, "same times")
		-- every refusal says why
		T.eq(drop(w.station, USER, COAL).State, "Loose", "the train is not back: no loading")
		T.eq(toasts(w, w.player, TrainService.AwayText), 0, "not 'on its way'")
		T.eq(toasts(w, w.player, TrainService.PenFullText), 1, "shares the throttle with the arrival toast")
		w.now += 2
		train.action(w.player, "Send")
		T.eq(lastToast(w, w.player).Text, TrainService.PenFullText, "Send: make room")
		local said = toasts(w, w.player, TrainService.PenFullText)
		TrainService.tick()
		advance(w, TrainConfig.DeliveryRetry)
		T.eq(#t.TripCargo, 3, "still full")
		T.eq(snapshot(w, w.player).Waiting, true, "still waiting")
		T.eq(toasts(w, w.player, TrainService.PenFullText), said, "the retries don't repeat it")
		T.eq(#trips(w, USER), 2, "nor the TrainTrip")
		for _ = 1, 3 do
			table.remove(w.data.Storage)
		end
		advance(w, TrainConfig.DeliveryRetry - 1)
		T.eq(#t.TripCargo, 3, "waits for the next try")
		advance(w, 1)
		local unloadAt = serverTime(w)
		T.eq(#t.TripCargo, 0, "delivered")
		T.eq(#w.data.Storage, capacity, "pen full again, nothing over")
		T.eq(w.data.Stats.TrainTrips, 1, "one trip")
		local fx = unloads(w)
		T.eq(#fx, 1, "unloaded once")
		T.eq(fx[1].C, 5, "the whole load counts")
		T.eq(toasts(w, w.player, TrainService.PenFullText), said, "never repeated")
		-- unloaded late: everyone gets the unload time first (the train is at the stop for the effect)
		list = trips(w, USER)
		T.eq(#list, 3, "TrainTrip with the unload")
		local late = list[3]
		T.eq(late.Waiting, nil, "not waiting any more")
		T.eq(late.DepartAt, trip.DepartAt, "same departure")
		T.near(late.ArriveAt, unloadAt, 1e-6, "arrives (unloads) now")
		T.eq(late.Count, trip.Count, "count")
		local lateAt, fxAt = 0, 0
		for i, note in w.all do
			if note.Name == "TrainTrip" and note.A == late then
				lateAt = i
			elseif note.Name == "Fx" and note.A == "TrainUnload" then
				fxAt = i
			end
		end
		T.lt(lateAt, fxAt, "the trip before the unload effect")
		-- ArriveAt moves to the unload, ArriveAt + ReturnSeconds is when it is back
		s = snapshot(w, w.player)
		T.eq(s.Waiting, false, "not waiting any more")
		T.near(s.DepartAt, trip.DepartAt, 1e-6, "same departure")
		T.near(s.ArriveAt, unloadAt, 1e-6, "the late unload")
		T.near(s.ArriveAt, late.ArriveAt, 1e-6, "as the clients got it")
		advance(w, TrainConfig.ReturnSeconds - 1)
		T.eq(drop(w.station, USER, COAL).State, "Loose", "rolling back")
		T.eq(lastToast(w, w.player).Text, TrainService.ReturnText, "coming back")
		-- the next trip may warn again; nothing fits at all: the HUD still learns it waits
		advance(w, 1)
		drop(w.station, USER, GOLD)
		T.eq(#t.Cargo, 1, "loading again")
		TrainService.send(w.player)
		local before = w.changed[w.player]
		advance(w, TRIP)
		T.eq(#t.TripCargo, 1, "nothing fit")
		T.eq(toasts(w, w.player, TrainService.PenFullText), said + 1, "a new trip, a new toast")
		T.lt(before, w.changed[w.player], "snapshot pushed")
		T.eq(snapshot(w, w.player).Waiting, true, "waiting")
		T.eq(trips(w, USER)[#trips(w, USER)].Waiting, true, "announced as waiting")
	end)

	withWorld("TrainService: a long wait at a full pen still unloads as a trip clients accept", function(w)
		fillPen(w, ItemService.penCapacity(w.data))
		drop(w.station, USER, GOLD)
		TrainService.send(w.player)
		local trip = trips(w, USER)[1]
		advance(w, TRIP)
		T.eq(snapshot(w, w.player).Waiting, true, "waiting")
		-- hours later the player makes room
		advance(w, 3 * 3600)
		table.remove(w.data.Storage)
		advance(w, TrainConfig.DeliveryRetry)
		T.eq(#w.data.Train.TripCargo, 0, "delivered")
		local list = trips(w, USER)
		local late = list[#list]
		T.near(late.ArriveAt, serverTime(w), 1e-6, "unloads now")
		T.le(late.ArriveAt - late.DepartAt, TrainService.MaxTripSpan, "never longer than clients accept")
		T.near(late.ArriveAt - late.DepartAt, trip.ArriveAt - trip.DepartAt, 1e-6, "as long as the real trip")
		local s = snapshot(w, w.player)
		T.near(s.DepartAt, late.DepartAt, 1e-6, "the snapshot agrees")
		T.near(s.ArriveAt, late.ArriveAt, 1e-6, "the snapshot agrees")
		T.eq(#unloads(w), 1, "the unload effect")
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
		T.eq(#w.wakes, 0, "no arrival timer")
		T.eq(lastToast(w, w.player).Text, "Your train brought 4 ore to your Ore Pen while you were away.", "told")
		local list = lastNote(w, "TrainTrip")
		T.truthy(list and list.Player == w.player and #list.A == 0, "an (empty) list of trips for the joiner")
		local s = snapshot(w, w.player)
		T.eq(s.ArriveAt, nil, "no return trip after a delivery while away")
		T.eq(s.Waiting, false, "not waiting")
		T.eq(s.AutoDepartIn, TrainConfig.AutoDepartSeconds, "the waiting cargo counts down again")
		drop(w.station, USER, COAL)
		T.eq(#t.Cargo, 3, "loading right away")
	end)

	withWorld("TrainService: joining with a full pen: the rest waits at the stop where everyone sees it", function(w)
		local t = w.data.Train
		fillPen(w, ItemService.penCapacity(w.data) - 1)
		for _ = 1, 3 do
			table.insert(t.TripCargo, { K = "Clean", O = "Gold", G = "Rough" })
		end
		t.TripDepartAt = NOW - 100
		t.TripArriveAt = NOW - 70
		train.loaded(w.player, w.data)
		T.eq(#t.TripCargo, 2, "two wait on the train")
		T.eq(toasts(w, w.player, "Your train brought 1 ore to your Ore Pen while you were away."), 1, "what fit")
		T.eq(toasts(w, w.player, TrainService.PenFullText), 1, "pen full toast")
		T.eq(#unloads(w), 0, "nothing unloaded for anyone to see")
		-- the waiting train is announced: every client can draw it standing at the stop
		local list = trips(w, USER)
		T.eq(#list, 1, "announced once")
		local trip = list[1]
		T.eq(trip.Waiting, true, "waiting")
		T.eq(trip.Count, 2, "what is on the train")
		T.eq(trip.PlotId, PLOT, "at my plot")
		T.eq(#trip.Load, 1, "clean gold")
		T.near(trip.ArriveAt, serverTime(w) - 70, 1e-6, "it arrived long ago")
		T.near(trip.ArriveAt - trip.DepartAt, 30, 1e-6, "the trip as it was")
		train.announce(w.player) -- PlotService.onAssigned
		T.eq(#trips(w, USER), 1, "only once")
		local s = snapshot(w, w.player)
		T.eq(s.Waiting, true, "waiting at the stop")
		T.eq(s.Moving, 2, "two on the train")
		T.near(s.ArriveAt, trip.ArriveAt, 1e-6, "the times everyone got")
		T.eq(drop(w.station, USER, COAL).State, "Loose", "no loading while it waits")
		T.eq(toasts(w, w.player, TrainService.AwayText), 0, "not 'on its way'")
		table.remove(w.data.Storage)
		table.remove(w.data.Storage)
		advance(w, TrainConfig.DeliveryRetry)
		T.eq(#t.TripCargo, 0, "delivered on the retry")
		T.eq(w.data.Stats.TrainTrips, 1, "counted once")
		-- a train everyone saw waiting unloads for everyone, then rolls back
		local fx = unloads(w)
		T.eq(#fx, 1, "the unload effect")
		T.eq(fx[1].C, 3, "the whole load")
		list = trips(w, USER)
		T.eq(#list, 2, "the unload time to everyone")
		T.eq(list[2].Waiting, nil, "not waiting")
		T.near(list[2].ArriveAt, serverTime(w), 1e-6, "unloads now")
		T.le(list[2].ArriveAt - list[2].DepartAt, TrainService.MaxTripSpan, "a trip clients accept")
		s = snapshot(w, w.player)
		T.eq(s.Waiting, false, "done")
		T.near(s.ArriveAt, serverTime(w), 1e-6, "rolling back from now")
		T.eq(drop(w.station, USER, COAL).State, "Loose", "rolling back: no loading")
		advance(w, TrainConfig.ReturnSeconds)
		drop(w.station, USER, COAL)
		T.eq(#t.Cargo, 1, "back: loading")
	end)

	withWorld("TrainService: rejoining this server mid-trip announces the very same times", function(w)
		drop(w.station, USER, GOLD)
		w.now += 0.437 -- between two whole seconds
		TrainService.send(w.player)
		local first = trips(w, USER)[1]
		T.eq(w.data.Train.TripDepartAt, w.now, "saved with the fraction (milliseconds)")
		advance(w, 3)
		train.forget(w.player) -- left and came back (same server)
		w.now += 0.25
		train.loaded(w.player, w.data)
		local list = trips(w, USER)
		T.eq(#list, 2, "announced again")
		T.eq(list[2].DepartAt, first.DepartAt, "exactly the same departure (no rebuilt train on other screens)")
		T.eq(list[2].ArriveAt, first.ArriveAt, "exactly the same arrival")
		T.eq(#list[2].Load, #first.Load, "same load colors")
		T.eq(list[2].Load[1], first.Load[1], "same load colors")
		-- a joiner gets the same times too
		train.loaded(w.other, w.otherData)
		local join = lastNote(w, "TrainTrip")
		T.eq(join.A[1].DepartAt, first.DepartAt, "the joiner's list")
		-- another server (no session times): worked out from the saved wall-clock times
		train.reset()
		train.setClock(function()
			return w.now
		end, function()
			return w.now + OFFSET + 40 -- a different server clock
		end, function() end)
		train.loaded(w.player, w.data)
		list = trips(w, USER)
		T.near(list[#list].DepartAt, first.DepartAt + 40, 1e-6, "same trip in that server's time")
	end)

	withWorld("TrainService: right after joining a full cargo waits a moment for perks such as Express", function(w)
		local t, o = w.data.Train, w.otherData.Train
		for _ = 1, CAP + 2 do
			table.insert(t.Cargo, { K = "Raw", O = "Coal" })
			table.insert(o.Cargo, { K = "Raw", O = "Coal" })
		end
		train.loaded(w.player, w.data)
		train.loaded(w.other, w.otherData)
		advance(w, 1)
		T.eq(#t.TripCargo + #o.TripCargo, 0, "nobody's train leaves in the first tick")
		w.player.attributes.Perk_TrainExpress = true -- the game pass check came back
		advance(w, TrainService.JoinGrace)
		T.eq(#t.TripCargo, 0, "Express: room for more, still loading")
		T.eq(#t.Cargo, CAP + 2, "kept")
		T.truthy(snapshot(w, w.player).AutoDepartIn, "counting down")
		T.eq(#o.TripCargo, CAP + 2, "without the perk the full train leaves after the grace")
		T.eq(#trips(w, OTHER), 1, "announced")
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
		T.eq(list.A[1].Color, TrainService.BannerColors[OTHER_PLOT], "no plot model here: PlotBuilder's banner color")
		T.eq(#w.wakes, 2, "arrival timers for both trains")
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

	withWorld("TrainService: the train color is the plot banner, found anywhere in the plot", function(w)
		local plot = Instance.new("Model")
		local decor = Instance.new("Folder")
		decor.Name = "Decor"
		decor.Parent = plot
		local banner = Instance.new("Part")
		banner.Name = "Banner"
		banner.Color = Color3.fromRGB(12, 34, 56)
		banner.Parent = decor
		PlotService.model = function(id)
			return if id == PLOT then plot else nil
		end
		T.eq(TrainService.bannerColor(PLOT), banner.Color, "a banner in a sub-folder")
		T.eq(TrainService.bannerColor(OTHER_PLOT), TrainService.BannerColors[OTHER_PLOT], "no plot model: the plot's color")
		T.eq(TrainService.bannerColor(#TrainService.BannerColors + 1), TrainService.BannerColors[1], "the colors repeat")
		T.eq(getPlotModel().Banner.Color, TrainService.BannerColors[PLOT], "the same list as PlotBuilder")
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
		T.eq(w.near[#w.near].A, "TrainLoad", "load effect")
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

	withWorld("TrainService: prompt and Send hints fit every hook and can't be spammed", function(w)
		local lift = train.setupHook(w.TrainEmberCaves.Part)
		w.player.stand(lift.Point)
		-- Send Train at a Mine Lift with an empty train: no talk of the Mine Station
		T.falsy(TrainService.EmptyText:find("Mine Station", 1, true), "fits a lift too")
		for _ = 1, 50 do
			train.action(w.player, "Send")
			train.load(w.player, lift) -- empty hands
		end
		T.eq(toasts(w, w.player, TrainService.EmptyText), 1, "one empty-train hint")
		T.eq(toasts(w, w.player, TrainService.HandsText), 1, "one empty-hands hint")
		w.now += 2
		train.action(w.player, "Send")
		train.load(w.player, lift)
		T.eq(toasts(w, w.player, TrainService.EmptyText), 2, "a real press later gets it again")
		T.eq(toasts(w, w.player, TrainService.HandsText), 2, "the hands hint too")
		-- while the train is away: Load and Send with something in hand
		drop(w.station, USER, COAL)
		TrainService.send(w.player)
		local before = #w.notes
		for _ = 1, 30 do
			carry(w, w.player, COAL)
			train.load(w.player, lift)
			train.action(w.player, "Send")
		end
		local said = 0
		for i = before + 1, #w.notes do
			if w.notes[i].Name == "Notify" then
				said += 1
			end
		end
		T.eq(said, 1, "one 'on its way' for all of it")
		T.eq(#w.data.Train.Cargo, 0, "nothing loaded")
		T.eq(#w.carried[w.player], 30, "still in your hands")
	end)

	withWorld("TrainService: without a plot the train never leaves by itself", function(w)
		w.plots[w.player] = nil
		local t = w.data.Train
		for _ = 1, CAP do
			table.insert(t.Cargo, { K = "Raw", O = "Coal" })
		end
		train.loaded(w.player, w.data)
		advance(w, TrainService.JoinGrace + TrainConfig.AutoDepartSeconds + 5)
		T.eq(#t.TripCargo, 0, "a full cargo waits")
		T.eq(#t.Cargo, CAP, "kept")
		T.eq(snapshot(w, w.player).AutoDepartIn, nil, "no countdown that never ends")
		TrainService.send(w.player)
		T.eq(lastToast(w, w.player).Text, TrainService.NoPlotText, "Send says why")
		-- the plot comes: it leaves as usual
		w.plots[w.player] = PLOT
		advance(w, 1)
		T.eq(#t.TripCargo, CAP, "full: it leaves")
		T.eq(#trips(w, USER), 1, "announced")
	end)

	withWorld("TrainService: the map's railway is watched, also when it comes later or is built again", function(w)
		local before = #w.zones
		local mapHandlers = {}
		local listening = 0
		local mapAdded = {
			Connect = function(_, fn)
				table.insert(mapHandlers, 1, fn)
				listening += 1
				return {
					Disconnect = function()
						listening -= 1
					end,
					Connected = true,
				}
			end,
		}
		-- a map without a railway yet
		local map = Instance.new("Model")
		map.Name = "Map"
		train.watchMap(map, mapAdded)
		T.eq(listening, 1, "listening for the railway")
		T.eq(#w.zones, before, "nothing yet")
		local first = buildRailway()
		first.Parent = map
		mapHandlers[1](first)
		T.eq(#w.zones, before + 1 + #TrainConfig.Lifts, "the railway's hooks")
		-- built again: the old railway goes (Destroy: every part's Parent is nil), a new one comes
		local gone = first:GetDescendants()
		for i = #gone, 1, -1 do
			gone[i].Parent = nil
		end
		first.Parent = nil
		local second = buildRailway()
		second.Parent = map
		mapHandlers[1](second)
		T.eq(#w.zones, before + 2 * (1 + #TrainConfig.Lifts), "the new railway's hooks")
		T.eq(train.hooks(), 1 + #TrainConfig.Lifts + 1 + #TrainConfig.Lifts, "hooks of the first test railway and the new one")
		local zone = w.zones[#w.zones - #TrainConfig.Lifts]
		T.eq(zone.Part, second.MineStation.Intake, "the new station hopper")
		drop(zone, USER, COAL)
		T.eq(#w.data.Train.Cargo, 1, "loads through the new railway")
		-- a part tagged later under the new railway is a hook; the old railway is forgotten
		local late = newPart(second.MineStation, "Annex", CFrame.new(40, -10, -147), Vector3.new(3, 3, 3))
		late:SetAttribute("LiftId", "Late")
		late:AddTag("TrainHopper")
		train.tagged(late)
		task.wait()
		T.eq(w.zones[#w.zones].Part, late, "tagged under the new railway")
		-- other children of the map are no railway
		local count = #w.zones
		local decor = Instance.new("Folder")
		decor.Name = "Decor"
		mapHandlers[1](decor)
		mapHandlers[1](second) -- the same railway again
		T.eq(#w.zones, count, "nothing new")
		-- a map that has its railway right away
		local other = Instance.new("Model")
		other.Name = "Map"
		local third = buildRailway()
		third.Parent = other
		train.watchMap(other, mapAdded)
		T.eq(#w.zones, count + 1 + #TrainConfig.Lifts, "its hooks at once")
		T.eq(#mapHandlers, 2, "a new listener")
		T.eq(listening, 1, "the old map's listener is gone")
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
		T.eq(lastToast(w, w.player).Text, TrainService.NoPlotText, "told why")
		train.action(fakePlayer(STRANGER, "Stranger"), "Send")
		T.eq(#trips(w), 0, "stranger: nothing")
	end)

	withWorld("TrainService: one broken train never stops the others", function(w)
		dropMany(w.station, OTHER, COAL, 2)
		TrainService.send(w.other)
		-- the owner's save is broken: reading the train throws (the owner comes first in the loop)
		w.data.Train = setmetatable({}, {
			__index = function()
				error("corrupt save")
			end,
		})
		advance(w, TRIP)
		T.eq(#w.otherData.Storage, 2, "the neighbour's train still arrives")
		T.eq(#unloads(w), 1, "and unloads")
		runWakes(w)
		T.eq(#unloads(w), 1, "its timer is harmless afterwards")
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
				runWakes(w)
				label ..= " time"
			end
			check(label)
		end
		T.truthy(w.data.Stats.TrainTrips > 3, "trains really ran")
	end)
end
