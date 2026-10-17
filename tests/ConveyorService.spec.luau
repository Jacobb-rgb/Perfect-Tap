-- ConveyorService under Lune: belt velocity and the walk-through collision
-- group, rails that open at corners, jam nudges (a queue waits, head-on belts
-- get pushed off), the Source chutes (no belt / facing the yard / jammed /
-- loose-item cap / spawning), the Sink hook (belt end and belt-less cell,
-- owner only, waiting, errors) and the chute plates and signs in the world.
-- MachineService and items are real; players, saves, plots and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
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
		w.data.MachineInventory = { Conveyor = 20, ClayFurnace = 1 }
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
		MachineService.register("Conveyor", conv.behaviour)
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
		-- the owner's loose-item cap
		for i = 1, GameConfig.MaxLooseItemsPerPlayer do
			ItemService.spawnDesc(COPPER, USER, CFrame.new(i * 3, 5, 900), nil, true)
		end
		T.eq(select(2, ConveyorService.sourceReady(PLOT, "Pen", USER)), "TooMany", "too many loose items")
		T.truthy(ConveyorService.sourceReady(PLOT, "Pen", STRANGER), "the cap is per owner")
		-- every wait has a line for the player
		for _, why in { "NoBelt", "Yard", "Jammed", "TooMany", "NoPlot" } do
			local text = ConveyorService.waitText("Pen", why)
			T.truthy(type(text) == "string" and #text > 5, "text for " .. why)
		end
		T.truthy(ConveyorService.waitText("Pen", "NoBelt"):find("PEN chute", 1, true), "names the chute")
		T.eq(ConveyorService.waitText("Pen", nil), nil, "no wait, no text")
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
		T.falsy(pcall(ConveyorService.setSink, "Pen", function()
			return true
		end), "the PEN chute is a source")
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
		-- with a belt on the cell the belt decides (it is no sink while it faces elsewhere)
		local fx, fz = BaseLayout.chuteCell("Foundry")
		belt(w, fx, fz, 0)
		local onBeltCell = chuteItem("Foundry")
		conv.scanSinks(2)
		T.eq(#calls, 1, "belt on the cell: no scan")
		T.eq(onBeltCell.State, "Loose", "left to the belt")
		-- a free plot takes nothing
		w.free = true
		MachineService._test.reset()
		local lone = chuteItem("Foundry")
		conv.scanSinks(3)
		T.eq(#calls, 1, "no owner, no sink")
		T.eq(lone.State, "Loose", "still there")
	end)

	---------------------------------------------------------------- chutes in the world

	withWorld("ConveyorService: every chute gets a plate on its cell and a sign behind it", function(w)
		conv.buildMarkers(PLOT)
		local folder = w.plotModel:FindFirstChild("Chutes")
		T.truthy(folder, "Chutes model on the plot")
		local plotCF = PlotService.plotCFrame(PLOT)
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
			local sign = model:FindFirstChild("Sign")
			local s = plotCF:PointToObjectSpace(sign.CFrame.Position)
			T.lt(GameConfig.PlotCells * CELL / 2, s.Z, name .. " sign off the grid")
			T.lt(3.5, s.Y - sign.Size.Y / 2, name .. " sign above the wall and the Foundry hood")
			local face = sign:FindFirstChild("FaceFront")
			T.eq(face:FindFirstChild("Title").Text, chute.Label, name .. " label")
			-- the front faces the grid (-Z plot-local)
			local look = plotCF:VectorToObjectSpace(sign.CFrame.LookVector)
			T.lt(look.Z, -0.99, name .. " faces the grid")
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					T.falsy(d.CanCollide, name .. " " .. d.Name .. " never blocks")
				end
			end
		end
		-- nothing pokes into the room kept for the Foundry's receiver hood
		local zone = BaseLayout.FoundryIntake.Zone
		for _, d in folder:FindFirstChild("Foundry"):GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Plate" then
				local p = plotCF:PointToObjectSpace(d.CFrame.Position)
				local half = d.Size / 2
				local apart = math.abs(p.X - zone.Center.X) >= half.X + zone.Size.X / 2
					or math.abs(p.Z - zone.Center.Z) >= half.Z + zone.Size.Z / 2
					or p.Y - half.Y >= zone.Size.Y
				T.truthy(apart, "Foundry sign " .. d.Name .. " clear of the receiver zone")
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
		local line = conv.markers(PLOT).Pen.Line
		T.eq(line.Text, ConveyorService.YardText, "turn the belt")
		MachineService.move(m, px, pz, 3)
		conv.onLayout(w.player, PLOT)
		T.eq(line.Text, ConveyorService.SignLines.Pen, "back to normal")
		-- the FOUNDRY sink belt faces the yard on purpose: no warning there
		local fx, fz = BaseLayout.chuteCell("Foundry")
		belt(w, fx, fz, BaseLayout.SinkRotation)
		conv.onLayout(w.player, PLOT)
		T.eq(conv.markers(PLOT).Foundry.Line.Text, ConveyorService.SignLines.Foundry, "sink belt is fine")
	end)
end
