-- ConveyorService under Lune: belt velocity and the walk-through collision
-- group, rails that open at corners, jam nudges (a queue waits, also across a
-- cell edge; head-on belts get pushed off), the Source chutes (no belt /
-- facing the yard / jammed / the loose-item ceiling under the machines' limit,
-- so a full line keeps draining / spawning), the Sink hook (belt end and
-- belt-less cell, owner only, not in mid-air, waiting, errors, a handler that
-- says it took an item but leaves it), descs that can't spawn ('Bad'), errors
-- half way through spawning, the server cost (one walk over the loose items
-- per pass, none for chutes) and the chute plates and plaques in the world.
-- MachineService and items are real; players, saves, plots and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
	local ConveyorService = Loader.requirePath("ServerScriptService.Server.Services.ConveyorService")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local PLOT = 4
	local USER, STRANGER = 301, 302
	local CELL = GameConfig.CellSize
	local conv = ConveyorService._test
	local COPPER = { K = "Raw", O = "Copper" }
	local INGOT = { K = "Ingot", O = "Iron", G = "Clean" }

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
		local p: any = { UserId = userId, Name = name, Parent = true }
		p.GetAttribute = function()
			return nil
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
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, ejects = {}, reacts = {} }
		w.plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = w.plotModel
		w.player = fakePlayer(USER, "Owner")
		w.stranger = fakePlayer(STRANGER, "Stranger")
		w.data = deepCopy(DataTemplate)
		w.data.StarterKitGiven = true
		w.data.MachineInventory = { Conveyor = 20, ExpressConveyor = 4, ClayFurnace = 1 }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data else nil
		end)
		patch(DataService, "changed", function() end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player then PLOT else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT and not w.free then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then w.plotModel else nil
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == STRANGER then w.stranger else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids = (w.ids or 0) + 1
			return "conveyor-guid-" .. w.ids
		end)
		patch(ItemService, "eject", function(record, velocity)
			table.insert(w.ejects, { Record = record, Velocity = velocity })
		end)
		patch(IntakeService, "react", function(machine, record, reason, via, belt)
			table.insert(w.reacts, { Machine = machine, Record = record, Reason = reason, Via = via, Belt = belt })
		end)
		w.gap = ConveyorService.SourceGap
		MachineService._test.reset()
		IntakeService._test.reset()
		ItemService._test.reset()
		conv.reset()
		for _, id in ConveyorService.beltIds() do
			MachineService.register(id, conv.behaviour)
		end
		MachineService._test.spawnAll(w.player, PLOT)
		w.restore = function()
			MachineService._test.reset()
			IntakeService._test.reset()
			ItemService._test.reset()
			conv.reset()
			ConveyorService.SourceGap = w.gap
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

	local function belt(w: any, x: number, z: number, r: number): any
		local m = MachineService.place(w.player, "Conveyor", x, z, r)
		assert(m, `belt at {x},{z}`)
		return m
	end

	-- A server-simulated item at a point in a belt's own space (front = -Z).
	local function onBeltItem(m: any, localPos: any, desc: any?, owner: number?): any
		local record = ItemService.spawnDesc(desc or COPPER, owner or USER, m.Model:GetPivot() * CFrame.new(localPos), Vector3.zero, true)
		assert(record, "item")
		return record
	end

	local function feed(m: any, record: any, now: number)
		conv.onBelt(m, record, m.Model:GetPivot():PointToObjectSpace(record.Body.CFrame.Position), now)
	end

	local function chuteItem(name: string, desc: any?, owner: number?): any
		local at = BaseLayout.chuteLocal(name) + Vector3.new(0, 1, 0)
		return ItemService.spawnDesc(desc or INGOT, owner or USER, PlotService.plotCFrame(PLOT) * CFrame.new(at), nil, true)
	end

	---------------------------------------------------------------- belts

	withWorld("ConveyorService: belts move items toward their front, players walk through", function(w)
		for r = 0, 3 do
			local m = belt(w, 2 + r * 2, 3, r)
			local part = m.Model:FindFirstChild("Belt")
			local dx, dz = Grid.dir(r)
			local plotCF = PlotService.plotCFrame(PLOT)
			local expected = plotCF:VectorToWorldSpace(Vector3.new(dx, 0, dz)) * GameConfig.ConveyorSpeed
			T.near((part.AssemblyLinearVelocity - expected).Magnitude, 0, 1e-4, "belt velocity r" .. r)
			for _, d in m.Model:GetDescendants() do
				if d:IsA("BasePart") then
					T.eq(d.CollisionGroup, ConveyorService.CollisionGroup, d.Name .. " walk-through group")
				end
			end
		end
		-- a turned belt runs the new way
		local m = belt(w, 9, 6, 0)
		T.truthy(MachineService.move(m, 9, 6, 1), "turned")
		local part = m.Model:FindFirstChild("Belt")
		T.near((part.AssemblyLinearVelocity - part.CFrame.LookVector * GameConfig.ConveyorSpeed).Magnitude, 0, 1e-4, "follows the move")
	end)

	withWorld("ConveyorService: the Express Conveyor is a belt twice as fast, in every belt rule", function(w)
		local ids = ConveyorService.beltIds()
		T.truthy(table.find(ids, "Conveyor") and table.find(ids, "ExpressConveyor"), "both belt types are belts")
		for _, id in ids do
			T.truthy(MachineData.ById[id].IsConveyor, id .. " is a conveyor")
		end
		local speed = GameConfig.ConveyorSpeed
		T.near(ConveyorService.speedOf(MachineData.ById.Conveyor), speed, 1e-9, "normal belt")
		T.near(
			ConveyorService.speedOf(MachineData.ById.ExpressConveyor),
			speed * MachineData.ById.ExpressConveyor.SpeedMult,
			1e-9,
			"express"
		)
		T.near(MachineData.ById.ExpressConveyor.SpeedMult, 2, 1e-9, "twice as fast")
		T.near(ConveyorService.speedOf({ SpeedMult = 0 / 0 } :: any), speed, 1e-9, "a broken multiplier counts as 1")
		T.near(ConveyorService.speedOf({ SpeedMult = -3 } :: any), speed, 1e-9, "a negative one too")
		-- the belt surface
		local express = MachineService.place(w.player, "ExpressConveyor", 5, 5, 1)
		T.truthy(express, "express belt placed")
		local part = express.Model:FindFirstChild("Belt")
		local dir = express.Model:GetPivot().LookVector
		T.near((part.AssemblyLinearVelocity - dir * speed * 2).Magnitude, 0, 1e-4, "surface at 2x")
		for _, d in express.Model:GetDescendants() do
			if d:IsA("BasePart") then
				T.eq(d.CollisionGroup, ConveyorService.CollisionGroup, d.Name .. " walk-through group")
			end
		end
		T.truthy(MachineService.move(express, 5, 5, 2), "turned")
		T.near((part.AssemblyLinearVelocity - part.CFrame.LookVector * speed * 2).Magnitude, 0, 1e-4, "follows the move at 2x")
		-- a stuck item on it is nudged at the express speed, then pushed off as before
		local record = onBeltItem(express, Vector3.new(0, 1.4, 0))
		dir = express.Model:GetPivot().LookVector
		local now = 100
		feed(express, record, now)
		now += GameConfig.ConveyorStuckSeconds + 0.01
		feed(express, record, now)
		T.near((record.Body.AssemblyLinearVelocity - (dir * speed * 2 + Vector3.new(0, 1, 0))).Magnitude, 0, 1e-4, "express nudge")
		for _ = 2, GameConfig.ConveyorMaxNudges do
			now += GameConfig.ConveyorStuckSeconds + 0.01
			record.Body.AssemblyLinearVelocity = Vector3.zero
			feed(express, record, now)
		end
		T.eq(#w.ejects, 1, "pushed off after the last nudge")
		-- side rails open for an express belt feeding a normal one (and back)
		local target = belt(w, 8, 8, 0)
		local side = MachineService.place(w.player, "ExpressConveyor", 7, 8, 1)
		conv.onLayout(w.player, PLOT)
		local rx = Grid.right(0)
		local openName = if rx > 0 then "RailL" else "RailR"
		T.falsy(target.Model:FindFirstChild(openName).CanCollide, "an express belt opens a normal belt's rail")
		T.truthy(side, "side belt")
		-- a Source chute starts items at the belt's own speed
		ConveyorService.SourceGap = 0
		local px, pz = BaseLayout.chuteCell("Pen")
		local source = MachineService.place(w.player, "ExpressConveyor", px, pz, 0)
		T.truthy(source, "express belt on the PEN chute")
		T.truthy(ConveyorService.beltOn(PLOT, "Pen") == source, "an express belt counts as the chute's belt")
		local item = ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
		T.truthy(item, "spawned on the express belt")
		T.near((item.Body.AssemblyLinearVelocity - source.Model:GetPivot().LookVector * speed * 2).Magnitude, 0, 1e-4, "riding at 2x")
		-- ConveyorService.init gives every belt type the belt behaviour
		MachineService._test.reset()
		IntakeService._test.reset()
		ConveyorService.init()
		MachineService._test.spawnAll(w.player, PLOT)
		local belts = 0
		for _, m in MachineService.ofPlot(PLOT) do
			if m.Info.IsConveyor then
				belts += 1
				local surface = m.Model:FindFirstChild("Belt")
				local want = surface.CFrame.LookVector * ConveyorService.beltSpeed(m)
				T.near((surface.AssemblyLinearVelocity - want).Magnitude, 0, 1e-4, m.Id .. " runs after init")
			end
		end
		T.eq(belts, 4, "every belt respawned (3 express, 1 normal)")
	end)

	withWorld("ConveyorService: a belt feeding in from the side opens that rail, and only that one", function(w)
		local target = belt(w, 6, 5, 0) -- toward the road
		local side = belt(w, 5, 5, 1) -- runs +X into the target's side
		conv.onLayout(w.player, PLOT)
		local function rail(m: any, name: string): any
			return m.Model:FindFirstChild(name)
		end
		-- the side belt sits at -X of the target, whose right hand (model +X, RailR) is Grid.right(0)
		local rx = Grid.right(0)
		local openName = if rx > 0 then "RailL" else "RailR"
		local closedName = if openName == "RailL" then "RailR" else "RailL"
		local open = rail(target, openName)
		T.falsy(open.CanCollide, "open rail lets items in")
		T.eq(open.Transparency, 1, "open rail hidden")
		for _, gui in open:GetChildren() do
			if gui:IsA("SurfaceGui") then
				T.falsy(gui.Enabled, "its painted face too")
			end
		end
		T.truthy(rail(target, closedName).CanCollide, "the other rail stays")
		T.truthy(rail(side, "RailL").CanCollide and rail(side, "RailR").CanCollide, "the feeding belt keeps both")
		-- the corner goes away: the rail closes again
		MachineService.pickup(side)
		conv.onLayout(w.player, PLOT)
		T.truthy(open.CanCollide, "closed again")
		T.eq(open.Transparency, 0, "visible again")
	end)

	---------------------------------------------------------------- jams

	withWorld("ConveyorService: a stuck item gets nudged along the belt, then pushed off the side", function(w)
		local m = belt(w, 5, 5, 1)
		local record = onBeltItem(m, Vector3.new(0, 1.4, 0))
		local dir = m.Model:GetPivot().LookVector
		local now = 100
		feed(m, record, now)
		T.truthy(conv.jam(record), "slow: watched")
		now += GameConfig.ConveyorStuckSeconds - 0.1
		feed(m, record, now)
		T.near(record.Body.AssemblyLinearVelocity.Magnitude, 0, 1e-6, "not yet")
		for i = 1, GameConfig.ConveyorMaxNudges - 1 do
			now += GameConfig.ConveyorStuckSeconds + 0.01
			record.Body.AssemblyLinearVelocity = Vector3.zero
			feed(m, record, now)
			local v = record.Body.AssemblyLinearVelocity
			T.near((v - (dir * GameConfig.ConveyorSpeed + Vector3.new(0, 1, 0))).Magnitude, 0, 1e-4, "nudge " .. i)
			T.eq(#w.ejects, 0, "still on the belt after nudge " .. i)
		end
		now += GameConfig.ConveyorStuckSeconds + 0.01
		record.Body.AssemblyLinearVelocity = Vector3.zero
		feed(m, record, now)
		T.eq(#w.ejects, 1, "pushed off after the last nudge")
		local pop = GameConfig.BeltRejectPop
		local expected = m.Model:GetPivot().RightVector * pop.Side + Vector3.new(0, pop.Up, 0)
		T.near((w.ejects[1].Velocity - expected).Magnitude, 0, 1e-4, "off the side")
		local fx = w.notes[#w.notes]
		T.truthy(fx and fx.Name == "Fx" and fx.A == "Reject" and fx.Player == w.player, "the owner sees why")
		-- a moving item is never touched
		local moving = onBeltItem(m, Vector3.new(0, 1.4, 1.5))
		moving.Body.AssemblyLinearVelocity = dir * GameConfig.ConveyorSpeed
		for _ = 1, 10 do
			now += 2
			feed(m, moving, now)
		end
		T.eq(#w.ejects, 1, "a riding item is left alone")
	end)

	withWorld("ConveyorService: items queued behind another one wait; head-on belts get cleared", function(w)
		local m = belt(w, 5, 5, 1)
		local front = onBeltItem(m, Vector3.new(0, 1.4, -1.6))
		local rear = onBeltItem(m, Vector3.new(0, 1.4, 0.2))
		local now = 50
		for _ = 1, 12 do
			now += 1.6
			rear.Body.AssemblyLinearVelocity = Vector3.zero
			front.Body.AssemblyLinearVelocity = Vector3.zero
			feed(m, rear, now)
		end
		T.eq(#w.ejects, 0, "the queued item waits (a full machine ahead, for example)")
		local jam = conv.jam(rear)
		T.truthy(jam == nil or jam.SlowSince == nil, "never counted as stuck")
		-- two belts facing each other: the items in the middle are no queue
		local a = belt(w, 2, 2, 1) -- +X
		local b = belt(w, 3, 2, 3) -- -X, into a
		local ia = onBeltItem(a, Vector3.new(0, 1.4, -1.7))
		local ib = onBeltItem(b, Vector3.new(0, 1.4, -1.7))
		for _ = 1, GameConfig.ConveyorMaxNudges + 1 do
			now += GameConfig.ConveyorStuckSeconds + 0.01
			ia.Body.AssemblyLinearVelocity = Vector3.zero
			ib.Body.AssemblyLinearVelocity = Vector3.zero
			feed(a, ia, now)
			feed(b, ib, now)
		end
		T.eq(#w.ejects, 2, "both pushed off: the jam clears")
	end)

	withWorld("ConveyorService: items the owner's client still moves are not judged", function(w)
		local m = belt(w, 5, 5, 1)
		local record = onBeltItem(m, Vector3.new(0, 1.4, 0))
		record.ClientOwnedUntil = os.clock() + 100
		local now = 0
		for _ = 1, 20 do
			now += 2
			feed(m, record, now)
		end
		T.eq(#w.ejects, 0, "never pushed")
		T.near(record.Body.AssemblyLinearVelocity.Magnitude, 0, 1e-6, "never nudged")
	end)

	---------------------------------------------------------------- sources

	withWorld("ConveyorService: a Source chute needs a belt that doesn't face the yard, with room", function(w)
		ConveyorService.SourceGap = 0
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "NoBelt", "no belt")
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Foundry", USER)), "NoBelt", "a Sink is never a source")
		local px, pz = BaseLayout.chuteCell("Pen")
		local m = belt(w, px, pz, BaseLayout.SinkRotation)
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "Yard", "runs off the grid")
		T.eq(ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER), nil, "nothing spawned toward the yard")
		T.eq(#ItemService.looseList(), 0, "no loose item")
		T.truthy(MachineService.move(m, px, pz, 0), "turned toward the road")
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", USER), "ready")
		local record = ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
		T.truthy(record, "spawned")
		T.eq(record.Owner, USER, "owner")
		T.eq(record.ClientOwnedUntil, nil, "server physics")
		local localPos = m.Model:GetPivot():PointToObjectSpace(record.Body.CFrame.Position)
		T.truthy(math.abs(localPos.X) < 0.01 and math.abs(localPos.Z) <= CELL / 2, "on the chute's belt")
		T.lt(0.8, localPos.Y, "above the belt")
		local v = record.Body.AssemblyLinearVelocity
		T.near((v - m.Model:GetPivot().LookVector * GameConfig.ConveyorSpeed).Magnitude, 0, 1e-4, "already riding")
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "Jammed", "the item still lies there")
		-- it rides away: room again
		record.Model:PivotTo(m.Model:GetPivot() * CFrame.new(0, 1.4, -CELL * 1.5))
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", USER), "room again")
		-- a just-spawned item counts as there for SourceGap seconds
		local second = ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
		T.truthy(second, "second item")
		second.Model:PivotTo(CFrame.new(0, 500, 0))
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", USER), "gap 0: ready")
		ConveyorService.SourceGap = 100
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "Jammed", "gap")
		ConveyorService.SourceGap = 0
		-- the owner's loose-item ceiling: SourceReserve under the machines' limit
		local machinesStop = GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom
		T.eq(ConveyorService.sourceCeiling(), machinesStop - ConveyorService.SourceReserve, "the ceiling")
		T.le(2 * MachineData.MaxOutBuffer, ConveyorService.SourceReserve, "room for two machines' finished items")
		T.lt(0, ConveyorService.sourceCeiling(), "Sources still work")
		for i = 1, ConveyorService.sourceCeiling() - ItemService.looseCount(USER) - 1 do
			ItemService.spawnDesc(COPPER, USER, CFrame.new(i * 3, 5, 900), nil, true)
		end
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", USER), "one under the ceiling: ready")
		ItemService.spawnDesc(COPPER, USER, CFrame.new(0, 5, 900), nil, true)
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "TooMany", "at the ceiling: waits")
		T.eq(ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER), nil, "nothing spawned")
		T.le(ItemService.looseCount(USER) + ConveyorService.SourceReserve, machinesStop, "the machines' room is left free")
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", STRANGER), "the ceiling is per owner")
		-- every wait has a line for the player
		for _, why in { "NoBelt", "Yard", "Jammed", "TooMany", "NoPlot" } do
			local text = ConveyorService.waitText("Pen", why)
			T.truthy(type(text) == "string" and #text > 5, "text for " .. why)
		end
		T.truthy(ConveyorService.waitText("Pen", "NoBelt"):find("PEN chute", 1, true), "names the chute")
		T.eq(ConveyorService.waitText("Pen", nil), nil, "no wait, no text")
	end)

	withWorld("ConveyorService: only descs that can become items spawn; the rest are 'Bad', never a wait", function(w)
		ConveyorService.SourceGap = 0
		local good: { any } = {
			COPPER,
			INGOT,
			{ K = "Clean", O = "Gold", G = "Pristine" },
			{ K = "Gear", O = "Iron", G = "Clean", R = "Dagger" },
		}
		for _, desc in good do
			T.truthy(ConveyorService.spawnable(desc), `{desc.K} {desc.O} can spawn`)
		end
		local bad: { any } = {
			nil,
			"Raw|Copper||",
			{ K = "Raw" },
			{ K = "Raw", O = "Unobtainium" },
			{ K = "Shiny", O = "Copper" },
			{ K = 5, O = "Copper" },
			{ K = "Clean", O = "Gold", G = 5 },
			{ K = "Clean", O = "Gold", G = "Shiny" },
			{ K = "Clean", O = "Gold", G = "Clean", R = {} },
			{ K = "Gear", O = "Iron", R = "Spoon" },
		}
		for i, desc in bad do
			T.falsy(ConveyorService.spawnable(desc), "junk desc " .. i)
		end
		local px, pz = BaseLayout.chuteCell("Pen")
		belt(w, px, pz, 0)
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", USER), "a ready PEN chute")
		for i, desc in bad do
			if type(desc) == "table" then
				local record, why = ConveyorService.spawnAtSource(PLOT, "Pen", desc, USER)
				T.eq(record, nil, "nothing spawned " .. i)
				T.eq(why, "Bad", "says Bad " .. i)
			end
		end
		T.eq(#ItemService.ownedBy(USER), 0, "no item made")
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", USER), "the chute is still free (no gap started)")
	end)

	withWorld("ConveyorService: an error half way through spawning never leaves a half-made item", function(w)
		ConveyorService.SourceGap = 0
		local px, pz = BaseLayout.chuteCell("Pen")
		local m = belt(w, px, pz, 0)
		local original = ItemService.spawnDesc
		local ok, err = pcall(function()
			-- made and indexed, but it never reached the world (like a SetAttribute error before Parent)
			rawset(ItemService, "spawnDesc", function(...)
				local record = original(...)
				record.Model.Parent = nil
				error("broken half way")
			end)
			local record, why = ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
			T.eq(record, nil, "no item")
			T.eq(why, "Bad", "Bad: the caller keeps its desc and moves on")
			T.eq(#ItemService.ownedBy(USER), 0, "the half-made item is gone again (nothing to store into the pen later)")
			-- made completely, then an error: unmade too (the caller keeps its desc)
			rawset(ItemService, "spawnDesc", function(...)
				original(...)
				error("broken after")
			end)
			local again, whyAgain = ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
			T.eq(again, nil, "no item")
			T.eq(whyAgain, "Bad", "Bad")
			T.eq(#ItemService.ownedBy(USER), 0, "nothing left over")
			T.eq(#ItemService.looseList(), 0, "nothing loose on the belt")
			-- other items of the owner are never touched
			rawset(ItemService, "spawnDesc", original)
			local old = ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
			T.truthy(old, "a normal spawn")
			old.Model:PivotTo(m.Model:GetPivot() * CFrame.new(0, 1.4, -CELL * 3))
			rawset(ItemService, "spawnDesc", function(...)
				original(...)
				error("broken after")
			end)
			ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
			T.eq(#ItemService.ownedBy(USER), 1, "the earlier item stays")
			T.eq(ItemService.ownedBy(USER)[1], old, "that one")
		end)
		rawset(ItemService, "spawnDesc", original)
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("ConveyorService: a long line never locks: machines keep emitting while the Sources wait", function(w)
		ConveyorService.SourceGap = 0
		local px, pz = BaseLayout.chuteCell("Pen")
		belt(w, px, pz, 0)
		local furnace = MachineService.place(w.player, "ClayFurnace", 4, 4, 0)
		T.truthy(furnace, "a machine on the line")
		-- a busy line: the Sources fill the owner's loose items up to their ceiling
		for _ = 1, GameConfig.MaxLooseItemsPerPlayer + 5 do
			if not ConveyorService.sourceReady(PLOT, "Pen", USER) then
				break
			end
			local record = ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER)
			assert(record, "spawned")
			-- it rides on down the line (somewhere off the chute's cell)
			record.Model:PivotTo(CFrame.new(ItemService.looseCount(USER) * 3, 5, 700))
		end
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "TooMany", "the Sources wait")
		T.eq(ItemService.looseCount(USER), ConveyorService.sourceCeiling(), "exactly at their ceiling")
		-- the machines' finished items still come out, one after another, so the
		-- line drains instead of filling their Out buffers and stopping
		for i = 1, MachineData.MaxOutBuffer do
			local result = MachineService.emit(furnace, INGOT)
			T.eq(result, "Spawned", "finished item " .. i .. " comes out")
		end
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "TooMany", "still nothing from the Sources")
	end)

	withWorld("ConveyorService: cheap on the server: one walk over the loose items per pass, none for chutes", function(w)
		ConveyorService.SourceGap = 0
		local m = belt(w, 5, 5, 1)
		local ahead = belt(w, 6, 5, 1)
		ConveyorService.setSink("Foundry", function()
			return false
		end)
		local px, pz = BaseLayout.chuteCell("Pen")
		belt(w, px, pz, 0)
		local slow: { any } = {}
		for i = 1, 6 do
			table.insert(slow, onBeltItem(m, Vector3.new(0, 1.4, 1.8 - i * 0.6)))
		end
		-- a far-away crowd of other loose items
		for i = 1, 40 do
			ItemService.spawnDesc(COPPER, STRANGER, CFrame.new(i * 3, 5, 800), nil, true)
		end
		local walks = 0
		local looseList = ItemService.looseList
		rawset(ItemService, "looseList", function()
			walks += 1
			return looseList()
		end)
		local ok, err = pcall(function()
			for _, record in slow do
				feed(m, record, 20)
			end
			T.eq(walks, 1, "every slow item of one pass shares one index")
			feed(m, slow[1], 20.2)
			T.eq(walks, 2, "a new pass builds it again")
			conv.scanSinks(21)
			T.truthy(ConveyorService.sourceReady(PLOT, "Pen", USER), "a ready chute")
			T.truthy(ConveyorService.spawnAtSource(PLOT, "Pen", COPPER, USER), "spawned")
			T.eq(walks, 2, "the sink scan and the Sources never walk every item")
		end)
		rawset(ItemService, "looseList", looseList)
		if not ok then
			error(err, 0)
		end
		-- the cell index still finds the line across a cell edge: an item waiting
		-- at the start of the next belt holds the one behind it
		for _, record in slow do
			ItemService.destroy(record)
		end
		local front = onBeltItem(ahead, Vector3.new(0, 1.4, 1.6))
		local rear = onBeltItem(m, Vector3.new(0, 1.4, -1.0))
		local now = 40
		for _ = 1, 12 do
			now += 1.6
			front.Body.AssemblyLinearVelocity = Vector3.zero
			rear.Body.AssemblyLinearVelocity = Vector3.zero
			feed(m, rear, now)
		end
		T.eq(#w.ejects, 0, "it waits behind the next belt's item")
		-- without it in front the same item is stuck: nudged, then pushed off
		front.Model:PivotTo(CFrame.new(0, 5, 600))
		for _ = 1, GameConfig.ConveyorMaxNudges + 2 do
			now += GameConfig.ConveyorStuckSeconds + 0.01
			rear.Body.AssemblyLinearVelocity = Vector3.zero
			feed(m, rear, now)
		end
		T.eq(#w.ejects, 1, "nothing ahead: cleared")
	end)

	---------------------------------------------------------------- sinks

	withWorld("ConveyorService: a belt into the FOUNDRY chute hands the owner's items to the sink", function(w)
		local fx, fz = BaseLayout.chuteCell("Foundry")
		local m = belt(w, fx, fz, BaseLayout.SinkRotation)
		local atEnd = Vector3.new(0, 1.4, -CELL / 2 + 0.5)
		-- no handler yet: the item waits at the end (never nudged off)
		local waiting = onBeltItem(m, atEnd, INGOT)
		local now = 10
		for _ = 1, 10 do
			now += 2
			feed(m, waiting, now)
		end
		T.eq(waiting.State, "Loose", "waits at the edge")
		T.eq(#w.ejects, 0, "not pushed off")
		local calls = {}
		local answer = true
		ConveyorService.setSink("Foundry", function(player, record)
			table.insert(calls, { Player = player, Record = record })
			if answer then
				ItemService.absorb(record)
				return true
			end
			return false
		end)
		feed(m, waiting, now)
		T.eq(#calls, 1, "offered")
		T.truthy(calls[1].Player == w.player, "with the owner")
		T.eq(waiting.State, "Consumed", "taken in")
		-- not at the end yet: just a belt
		local early = onBeltItem(m, Vector3.new(0, 1.4, 1.2), INGOT)
		feed(m, early, now)
		T.eq(#calls, 1, "only at the end")
		-- the sink can say no: the item waits there, again and again
		answer = false
		local refused = onBeltItem(m, atEnd, INGOT)
		for _ = 1, 8 do
			now += 2
			feed(m, refused, now)
		end
		T.eq(refused.State, "Loose", "still there")
		T.eq(#calls, 9, "offered every scan")
		T.eq(#w.ejects, 0, "never pushed off")
		-- another player's item: refused as Foreign, the sink never sees it
		answer = true
		local foreign = onBeltItem(m, atEnd, INGOT, STRANGER)
		feed(m, foreign, now)
		T.eq(#calls, 9, "not offered")
		T.eq(#w.reacts, 1, "pushed off like at a machine")
		T.eq(w.reacts[1].Reason, "Foreign", "Foreign")
		T.eq(w.reacts[1].Via, "Belt", "via Belt")
		-- a sink that breaks leaves the item where it is
		ConveyorService.setSink("Foundry", nil)
		ConveyorService.setSink("Foundry", function()
			error("broken sink")
		end)
		local survivor = onBeltItem(m, atEnd, INGOT)
		feed(m, survivor, now)
		T.eq(survivor.State, "Loose", "an error takes nothing")
		-- a handler that says it took an item but leaves it in the world: the
		-- item is taken out right there, so it is never offered (and stored) again
		ConveyorService.setSink("Foundry", nil)
		local stored: { any } = {}
		ConveyorService.setSink("Foundry", function(_, record)
			table.insert(stored, ItemService.descOf(record)) -- forgot ItemService.absorb
			return true
		end)
		local sloppy = onBeltItem(m, atEnd, INGOT)
		feed(m, sloppy, now)
		T.eq(#stored, 1, "stored")
		T.eq(sloppy.State, "Consumed", "out of the world: no copy left behind")
		for _ = 1, 10 do
			-- (IntakeService only scans loose items; even a stale call takes nothing)
			now += 0.2
			conv.onBelt(m, sloppy, atEnd, now)
		end
		T.eq(#stored, 1, "never offered (and stored) again")
		T.eq(#w.ejects, 0, "not pushed anywhere")
		-- a belt on the sink cell that faces elsewhere just carries items
		ConveyorService.setSink("Foundry", nil)
		local seen = 0
		ConveyorService.setSink("Foundry", function()
			seen += 1
			return false
		end)
		T.truthy(MachineService.move(m, fx, fz, 1), "turned along the back row")
		feed(m, onBeltItem(m, atEnd, INGOT), now)
		T.eq(seen, 0, "not a sink belt now")
		-- only sinks take a handler
		T.falsy(
			pcall(ConveyorService.setSink, "Pen", function()
				return true
			end),
			"the PEN chute is a source"
		)
	end)

	withWorld("ConveyorService: with no belt on the FOUNDRY chute, items lying on its cell go in", function(w)
		local calls = {}
		ConveyorService.setSink("Foundry", function(player, record)
			table.insert(calls, { Player = player, Record = record })
			ItemService.absorb(record)
			return true
		end)
		local mine = chuteItem("Foundry")
		local theirs = chuteItem("Foundry", nil, STRANGER)
		local elsewhere = chuteItem("Pen")
		conv.scanSinks(1)
		T.eq(#calls, 1, "one item taken")
		T.truthy(calls[1].Record == mine and calls[1].Player == w.player, "the owner's, with the owner")
		T.eq(theirs.State, "Loose", "another player's item stays (IntakeService sends it home)")
		T.eq(elsewhere.State, "Loose", "other cells are not the chute")
		-- ore flying over the cell is not on it (the plot reaches 24 studs up)
		local high = ItemService.spawnDesc(
			INGOT,
			USER,
			PlotService.plotCFrame(PLOT) * CFrame.new(BaseLayout.chuteLocal("Foundry") + Vector3.new(0, ConveyorService.SinkScanUp + 2, 0)),
			nil,
			true
		)
		conv.scanSinks(1.5)
		T.eq(#calls, 1, "not taken in mid-air")
		T.eq(high.State, "Loose", "it flies on")
		high.Model:PivotTo(PlotService.plotCFrame(PLOT) * CFrame.new(BaseLayout.chuteLocal("Foundry") + Vector3.new(0, 0.8, 0)))
		conv.scanSinks(1.6)
		T.eq(#calls, 2, "once it lands on the cell it goes in")
		-- with a belt on the cell the belt decides (it is no sink while it faces elsewhere)
		local fx, fz = BaseLayout.chuteCell("Foundry")
		belt(w, fx, fz, 0)
		local onBeltCell = chuteItem("Foundry")
		conv.scanSinks(2)
		T.eq(#calls, 2, "belt on the cell: no scan")
		T.eq(onBeltCell.State, "Loose", "left to the belt")
		-- a free plot takes nothing
		w.free = true
		MachineService._test.reset()
		local lone = chuteItem("Foundry")
		conv.scanSinks(3)
		T.eq(#calls, 2, "no owner, no sink")
		T.eq(lone.State, "Loose", "still there")
	end)

	---------------------------------------------------------------- chutes in the world

	withWorld("ConveyorService: every chute gets a plate on its cell and a plaque up on the back wall", function(w)
		conv.buildMarkers(PLOT)
		local folder = w.plotModel:FindFirstChild("Chutes")
		T.truthy(folder, "Chutes model on the plot")
		local plotCF = PlotService.plotCFrame(PLOT)
		local gate = BaseLayout.YardGate
		local grid = GameConfig.PlotCells * CELL / 2
		local wallLine = grid + 1 -- PlotBuilder.WallLine
		for _, name in BaseLayout.ChuteNames do
			local chute = BaseLayout.Chutes[name]
			local model = folder:FindFirstChild(name)
			T.truthy(model, name .. " marker")
			local plate = model:FindFirstChild("Plate")
			local cell = BaseLayout.chuteLocal(name)
			local p = plotCF:PointToObjectSpace(plate.CFrame.Position)
			T.near(p.X, cell.X, 1e-3, name .. " plate on the cell (x)")
			T.near(p.Z, cell.Z, 1e-3, name .. " plate on the cell (z)")
			T.lt(0.048, p.Y + plate.Size.Y / 2, name .. " plate over the lawn")
			T.eq(plate.Color, chute.Color, name .. " plate colour")
			local board = model:FindFirstChild("Board")
			local title = model:FindFirstChild("Title"):FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text")
			T.eq(title.Text, chute.Label, name .. " label")
			T.eq(model:FindFirstChild("Edge").Color, chute.Color, name .. " frame in the chute's colour")
			-- the front faces the grid (-Z plot-local)
			local look = plotCF:VectorToObjectSpace(board.CFrame.LookVector)
			T.lt(look.Z, -0.99, name .. " faces the grid")
			local b = plotCF:PointToObjectSpace(board.CFrame.Position)
			T.le(math.abs(b.X - cell.X), 6, name .. " plaque near its cell")
			-- the podiums' price tags (2.2 wide, low behind the wall) stay in view straight on
			for i, podium in BaseLayout.Podiums do
				local apart = math.abs(b.X - podium.Center.X)
				T.le(ConveyorService.PlaqueSize.X / 2 + 1.1, apart, `{name} plaque not in front of podium {i}'s tag`)
			end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					T.falsy(d.CanCollide, name .. " " .. d.Name .. " never blocks")
					if d.Name ~= "Plate" then
						local q = plotCF:PointToObjectSpace(d.CFrame.Position)
						local half = d.Size / 2
						T.lt(grid, q.Z - half.Z, name .. " " .. d.Name .. " off the grid")
						T.le(q.Z + half.Z, wallLine - 0.5 + 1e-6, name .. " " .. d.Name .. " on the wall's grid face, not in it")
						-- the wall's cap is at 2.25: above it, over the rails (1.1) of a belt on the
						-- chute and the items riding it; under the gate posts' caps (3.7) and the
						-- ORE PEN sign (3.75)
						T.le(2.25 - 1e-4, q.Y - half.Y, name .. " " .. d.Name .. " up on the wall's cap, over the belt and its items")
						T.le(q.Y + half.Y, 3.7, name .. " " .. d.Name .. " under the gate posts' caps and the ORE PEN sign")
						if name == "Pen" then
							-- the gate post (2.1 cap) stands out in front of the wall: a stud clear of it
							T.le(
								gate.Width / 2 + 2.1 + 1 - 1e-4,
								math.abs(q.X - gate.CenterX) - half.X,
								"Pen " .. d.Name .. " clear of the gate post"
							)
						end
						T.le(
							gate.Width / 2,
							math.abs(q.X - gate.CenterX) - half.X + 1e-6,
							name .. " " .. d.Name .. " out of the gate walkway"
						)
					end
				end
			end
		end
		-- the PEN plaque is right behind its cell; the TRAIN one (on the gate post)
		-- points at its cell, which is on the right as seen from the grid (+X is left)
		local markers = conv.markers(PLOT)
		T.eq(markers.Pen.Line.Text, ConveyorService.SignLines.Pen, "PEN: no arrow")
		T.eq(markers.Train.Line.Text, ConveyorService.SignLines.Train .. " >", "TRAIN: arrow toward its cell")
		T.truthy(markers.Foundry.Line.Text:find("BELT IN", 1, true), "FOUNDRY: belt in")
		-- nothing pokes into the room kept for the Foundry's receiver hood
		local zone = BaseLayout.FoundryIntake.Zone
		for _, d in folder:FindFirstChild("Foundry"):GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Plate" then
				local p = plotCF:PointToObjectSpace(d.CFrame.Position)
				local half = d.Size / 2
				local apart = math.abs(p.X - zone.Center.X) >= half.X + zone.Size.X / 2
					or math.abs(p.Z - zone.Center.Z) >= half.Z + zone.Size.Z / 2
					or p.Y - half.Y >= zone.Size.Y
				T.truthy(apart, "Foundry plaque " .. d.Name .. " clear of the receiver zone")
			end
		end
		-- built once per plot
		conv.buildMarkers(PLOT)
		local count = 0
		for _, child in w.plotModel:GetChildren() do
			if child.Name == "Chutes" then
				count += 1
			end
		end
		T.eq(count, 1, "only one set")
		-- a Source whose belt runs into the yard says so
		local px, pz = BaseLayout.chuteCell("Pen")
		local m = belt(w, px, pz, BaseLayout.SinkRotation)
		conv.onLayout(w.player, PLOT)
		local line = markers.Pen.Line
		T.eq(line.Text, ConveyorService.YardSign, "turn the belt")
		T.le(#line.Text, 12, "a short word, readable from the grid")
		MachineService.move(m, px, pz, 3)
		conv.onLayout(w.player, PLOT)
		T.eq(line.Text, ConveyorService.SignLines.Pen, "back to normal")
		local tx, tz = BaseLayout.chuteCell("Train")
		belt(w, tx, tz, BaseLayout.SinkRotation)
		conv.onLayout(w.player, PLOT)
		T.eq(markers.Train.Line.Text, ConveyorService.YardSign .. " >", "the TRAIN plaque warns too, still pointing")
		-- the FOUNDRY sink belt faces the yard on purpose: no warning there
		local fx, fz = BaseLayout.chuteCell("Foundry")
		belt(w, fx, fz, BaseLayout.SinkRotation)
		conv.onLayout(w.player, PLOT)
		T.falsy(markers.Foundry.Line.Text:find(ConveyorService.YardSign, 1, true), "sink belt is fine")
	end)
end
