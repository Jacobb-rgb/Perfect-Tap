-- BuildService under Lune: the build remotes' checks in contract order,
-- BuildResult replies, effects for other players, lifting players and
-- items out of a new machine, no crate rule (the Ore Pen holds stored items)
-- and the State provider.
-- MachineService runs for real; its Roblox-only neighbours are fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local BuildService = Loader.requirePath("ServerScriptService.Server.Services.BuildService")
	local Players = Loader.game:GetService("Players")
	local RunService = Loader.game:GetService("RunService")

	local PLOT = 3
	local USER, OTHER = 301, 302
	local CELL = GameConfig.CellSize
	local HALF = GameConfig.PlotCells * CELL / 2
	local build = BuildService._test

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

	-- World position above the middle of a plot cell.
	local function cellPosition(gx: number, gz: number, height: number): any
		local localPos = Vector3.new(-HALF + (gx + 0.5) * CELL, height, -HALF + (gz + 0.5) * CELL)
		return PlotService.plotCFrame(PLOT) * localPos
	end

	local function fakePlayer(w: any, userId: number, name: string): any
		local p: any = {
			UserId = userId,
			Name = name,
			Parent = true,
			GetAttribute = function()
				return nil
			end,
		}
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then { Health = 100 } else nil
			end,
			FindFirstChild = function(_, name2: string)
				return if name2 == "HumanoidRootPart" then p.root else nil
			end,
			PivotTo = function(_, cf)
				table.insert(w.pivots, { Player = p, CFrame = cf })
			end,
		}
		p.stand = function(position)
			p.root.Position = position
			p.root.CFrame = CFrame.new(position)
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, near = {}, pivots = {}, released = {}, loose = {}, placed = {} }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.folder = folder
		w.player = fakePlayer(w, USER, "Builder")
		w.other = fakePlayer(w, OTHER, "Neighbour")
		w.near[w.player] = true
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { ClayFurnace = 2, StorageCrate = 2, Conveyor = 5 }
		w.data = data
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data else nil
		end)
		patch(DataService, "changed", function() end)
		patch(DataService, "isInMemory", function()
			return false
		end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player then PLOT else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then plotModel else nil
		end)
		patch(PlotService, "isNear", function(p, id, range)
			T.eq(range, GameConfig.BuildRange, "build range")
			return id == PLOT and w.near[p] == true
		end)
		patch(Net, "fire", function(name, p, payload)
			table.insert(w.notes, { Name = name, Player = p, Payload = payload })
		end)
		patch(Net, "fireNear", function(name, position, radius, except, ...)
			table.insert(w.notes, { Name = name, Position = position, Radius = radius, Except = except, Args = { ... } })
		end)
		patch(ItemService, "looseCount", function()
			return 0
		end)
		patch(ItemService, "looseList", function()
			return table.clone(w.loose)
		end)
		patch(ItemService, "release", function(record, cf, velocity)
			table.insert(w.released, { Record = record, CFrame = cf, Velocity = velocity })
		end)
		patch(RunService, "IsStudio", function()
			return false
		end)
		patch(Players, "GetPlayers", function()
			return { w.player, w.other }
		end)
		MachineService._test.reset()
		build.reset()
		BuildService.onPlaced(function(p, id)
			table.insert(w.placed, { Player = p, Id = id })
		end)
		MachineService._test.spawnAll(w.player, PLOT)
		w.restore = function()
			MachineService._test.reset()
			build.reset()
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

	-- The last note of a kind.
	local function last(w: any, name: string): any
		for i = #w.notes, 1, -1 do
			if w.notes[i].Name == name then
				return w.notes[i]
			end
		end
		return nil
	end

	local function count(w: any, name: string): number
		local n = 0
		for _, note in w.notes do
			if note.Name == name then
				n += 1
			end
		end
		return n
	end

	-- The reply to the last request, checked for its seq and op.
	local function result(w: any, seq: number, op: string): any
		local note = last(w, "BuildResult")
		T.truthy(note, "a BuildResult was sent")
		T.truthy(note.Player == w.player, "to the builder")
		T.eq(note.Payload.Seq, seq, "Seq")
		T.eq(note.Payload.Op, op, "Op")
		return note.Payload
	end

	local function placedOne(w: any, id: string, x: number, z: number, r: number): any
		local before = #MachineService.ofPlot(PLOT)
		build.place(w.player, 77, id, x, z, r)
		local list = MachineService.ofPlot(PLOT)
		T.eq(#list, before + 1, "placed " .. id)
		for _, m in list do
			if m.Id == id and m.X == x and m.Z == z then
				return m
			end
		end
		error("placed machine not found")
	end

	withWorld("BuildService: bad input, no plot, too far and foreign models are refused", function(w)
		local data = w.data
		-- 1) types and ranges; an unusable seq is answered with -1
		build.place(w.player, nil, "ClayFurnace", 0, 0, 0)
		T.eq(result(w, -1, "Place").Reason, "BadInput", "missing seq")
		for _, seq in { 1.5, -1, 2 ^ 31, 0 / 0, "4" } do
			build.place(w.player, seq, "ClayFurnace", 0, 0, 0)
			local r = result(w, -1, "Place")
			T.eq(r.Reason, "BadInput", "bad seq " .. tostring(seq))
		end
		local cases = {
			{ "ClayFurnace", 12, 0, 0 },
			{ "ClayFurnace", 0, -1, 0 },
			{ "ClayFurnace", 0, 0, 4 },
			{ "ClayFurnace", 0 / 0, 0, 0 },
			{ "ClayFurnace", 1.5, 0, 0 },
			{ "ClayFurnace", "1", 0, 0 },
			{ string.rep("A", 33), 0, 0, 0 },
			{ 42, 0, 0, 0 },
		}
		for i, c in cases do
			build.place(w.player, i, c[1], c[2], c[3], c[4])
			local r = result(w, i, "Place")
			T.falsy(r.Ok, "case " .. i)
			T.eq(r.Reason, "BadInput", "case " .. i)
		end
		build.move(w.player, 20, nil, 99, 0, 0)
		T.eq(result(w, 20, "Move").Reason, "BadInput", "move range")
		-- 2) no data / no plot
		local stranger = fakePlayer(w, 999, "Stranger")
		build.place(stranger, 21, "ClayFurnace", 0, 0, 0)
		local noPlot = last(w, "BuildResult")
		T.eq(noPlot.Payload.Reason, "NoPlot", "no plot")
		-- 3) too far from the plot
		w.near[w.player] = false
		build.place(w.player, 22, "ClayFurnace", 0, 0, 0)
		T.eq(result(w, 22, "Place").Reason, "TooFar", "too far")
		w.near[w.player] = true
		-- 4) moves and pickups need one of your own machine models
		local m = placedOne(w, "ClayFurnace", 0, 0, 0)
		local foreign = Instance.new("Model")
		foreign.Parent = Instance.new("Folder")
		local values: { any } = { false, foreign, m.Model.PrimaryPart, "Model", w.folder }
		for _, value in values do
			build.move(w.player, 23, value, 4, 4, 0)
			T.eq(result(w, 23, "Move").Reason, "NotYours", "move " .. tostring(value))
			build.pickup(w.player, 24, value)
			T.eq(result(w, 24, "Pickup").Reason, "NotYours", "pickup " .. tostring(value))
		end
		build.pickup(w.player, 24, nil)
		T.eq(result(w, 24, "Pickup").Reason, "NotYours", "pickup nil")
		-- a machine in your folder that belongs to someone else is not yours either
		m.Owner = w.other
		build.pickup(w.player, 24, m.Model)
		T.eq(result(w, 24, "Pickup").Reason, "NotYours", "owner check")
		m.Owner = w.player
		-- the range check comes before the ownership check
		w.near[w.player] = false
		build.pickup(w.player, 25, foreign)
		T.eq(result(w, 25, "Pickup").Reason, "TooFar", "range first")
		w.near[w.player] = true
		-- MachineService's own codes come through unchanged
		build.place(w.player, 26, "Anvil", 6, 6, 0)
		T.eq(result(w, 26, "Place").Reason, "NoneOwned", "not owned")
		build.place(w.player, 27, "ClayFurnace", 1, 1, 0)
		T.eq(result(w, 27, "Place").Reason, "Overlap", "overlap")
		build.place(w.player, 28, "ClayFurnace", 11, 0, 0)
		T.eq(result(w, 28, "Place").Reason, "OutOfBounds", "out of bounds")
		T.eq(#data.PlacedMachines, 1, "nothing else placed")
		T.eq(data.MachineInventory.ClayFurnace, 1, "inventory only spent once")
		T.eq(count(w, "Fx"), 1, "only the one real placement puffed")
		T.eq(#w.placed, 1, "onPlaced once")
	end)

	withWorld("BuildService: place, move and pickup reply and puff for other players", function(w)
		local data = w.data
		build.place(w.player, 5, "ClayFurnace", 4, 4, 1)
		local r = result(w, 5, "Place")
		T.truthy(r.Ok, "placed")
		T.eq(r.Reason, nil, "no reason")
		T.eq(r.Id, "ClayFurnace", "Id")
		T.eq(r.X, 4, "X")
		T.eq(r.Z, 4, "Z")
		T.eq(r.R, 1, "R")
		T.eq(data.MachineInventory.ClayFurnace, 1, "inventory -1")
		T.eq(#w.placed, 1, "onPlaced")
		T.truthy(w.placed[1].Player == w.player and w.placed[1].Id == "ClayFurnace", "onPlaced args")
		local m = MachineService.ofPlot(PLOT)[1]
		local fx = last(w, "Fx")
		T.eq(fx.Args[1], "Placed", "Fx kind")
		T.eq(fx.Args[3], "ClayFurnace", "Fx machine")
		T.truthy(fx.Except == w.player, "not to the builder")
		T.eq(fx.Radius, 100, "near radius")
		T.near((fx.Position - m.Model:GetPivot().Position).Magnitude, 0, 1e-4, "at the machine")

		build.move(w.player, 6, m.Model, 7, 7, 2)
		r = result(w, 6, "Move")
		T.truthy(r.Ok, "moved")
		T.eq(r.X, 7, "new X")
		T.eq(r.R, 2, "new R")
		T.eq(m.Entry.X, 7, "saved")
		T.eq(last(w, "Fx").Args[1], "Placed", "puff where it landed")

		build.move(w.player, 7, m.Model, 11, 11, 0)
		r = result(w, 7, "Move")
		T.falsy(r.Ok, "refused")
		T.eq(r.Reason, "OutOfBounds", "reason")
		T.eq(r.Id, "ClayFurnace", "names the machine")
		T.eq(m.Entry.X, 7, "unchanged")

		m.Model:SetAttribute("Busy", true)
		build.move(w.player, 8, m.Model, 0, 0, 0)
		T.eq(result(w, 8, "Move").Reason, "Busy", "busy move")
		build.pickup(w.player, 9, m.Model)
		T.eq(result(w, 9, "Pickup").Reason, "Busy", "busy pickup")
		m.Model:SetAttribute("Busy", nil)

		local position = m.Model:GetPivot().Position
		local puffs = count(w, "Fx")
		build.pickup(w.player, 10, m.Model)
		r = result(w, 10, "Pickup")
		T.truthy(r.Ok, "packed up")
		T.eq(r.Id, "ClayFurnace", "Id")
		T.eq(r.X, 7, "old X")
		T.eq(data.MachineInventory.ClayFurnace, 2, "back in the inventory")
		T.eq(#data.PlacedMachines, 0, "entry gone")
		T.eq(count(w, "Fx"), puffs + 1, "one puff")
		fx = last(w, "Fx")
		T.eq(fx.Args[1], "PackedUp", "PackedUp")
		T.near((fx.Position - position).Magnitude, 0, 1e-4, "where it stood")
		T.eq(#MachineService.ofPlot(PLOT), 0, "model gone")
	end)

	withWorld("BuildService: a machine placed on players and items lifts them on top", function(w)
		-- the builder stands in cell 5,5; the neighbour next to the footprint
		w.player.stand(cellPosition(5, 5, 3))
		w.other.stand(cellPosition(6, 5, 3))
		local inside = { State = "Loose", Body = { CFrame = CFrame.new(cellPosition(4, 4, 0.5)) } }
		local outside = { State = "Loose", Body = { CFrame = CFrame.new(cellPosition(4, 6, 0.5)) } }
		local carried = { State = "Carried", Body = { CFrame = CFrame.new(cellPosition(5, 4, 0.5)) } }
		w.loose = { inside, outside, carried }
		-- belts never lift anything
		build.place(w.player, 1, "Conveyor", 5, 5, 0)
		T.truthy(result(w, 1, "Place").Ok, "belt placed")
		T.eq(#w.pivots, 0, "nobody lifted by a belt")
		T.eq(#w.released, 0, "no item lifted by a belt")
		build.pickup(w.player, 2, MachineService.ofPlot(PLOT)[1].Model)

		build.place(w.player, 3, "ClayFurnace", 4, 4, 0)
		T.truthy(result(w, 3, "Place").Ok, "furnace placed")
		local m = MachineService.ofPlot(PLOT)[1]
		local top = build.modelTop(m.Model)
		T.lt(m.Model:GetPivot().Position.Y + 2, top, "the top is above the base")
		T.eq(#w.pivots, 1, "one character lifted")
		local lifted = w.pivots[1]
		T.truthy(lifted.Player == w.player, "the one inside")
		T.near(lifted.CFrame.Position.Y, top + 3, 1e-4, "onto the roof")
		T.near(lifted.CFrame.Position.X, w.player.root.Position.X, 1e-4, "same X")
		T.near(lifted.CFrame.Position.Z, w.player.root.Position.Z, 1e-4, "same Z")
		T.eq(#w.released, 1, "one item lifted")
		T.truthy(w.released[1].Record == inside, "the loose one inside")
		T.near(w.released[1].CFrame.Position.Y, top + 2, 1e-4, "item onto the roof")

		-- moving it onto the neighbour lifts them too
		build.move(w.player, 4, m.Model, 6, 4, 0)
		T.truthy(result(w, 4, "Move").Ok, "moved")
		T.eq(#w.pivots, 2, "neighbour lifted")
		T.truthy(w.pivots[2].Player == w.other, "the neighbour")
	end)

	withWorld("BuildService: packing machines up never touches the Ore Pen or nags about crates", function(w)
		local data = w.data
		local a = placedOne(w, "StorageCrate", 0, 0, 0)
		local b = placedOne(w, "ClayFurnace", 4, 0, 0)
		data.Storage = { { K = "Raw", O = "Copper" } }
		local before = count(w, "Notify")
		build.pickup(w.player, 1, a.Model)
		T.truthy(result(w, 1, "Pickup").Ok, "a (retired) crate")
		build.pickup(w.player, 2, b.Model)
		T.truthy(result(w, 2, "Pickup").Ok, "the last machine")
		T.eq(count(w, "Notify"), before, "no crate toast: the pen is on the yard")
		T.eq(#data.Storage, 1, "Ore Pen untouched")
	end)

	withWorld("BuildService: the State provider sends the layout and slot usage", function(w)
		local m = placedOne(w, "ClayFurnace", 2, 3, 1)
		m.Entry.In = { { K = "Clean", O = "Copper", G = "Rough" } }
		placedOne(w, "Conveyor", 9, 9, 2)
		placedOne(w, "Conveyor", 9, 8, 2)
		table.insert(w.data.PlacedMachines, { Id = "FutureMachine", X = 0, Z = 11, R = 0 })
		local snapshot: any = {}
		build.provide(w.player, w.data, snapshot)
		T.eq(#snapshot.Placed, 4, "every saved entry")
		local first = snapshot.Placed[1]
		T.eq(first.Id, "ClayFurnace", "Id")
		T.eq(first.X, 2, "X")
		T.eq(first.Z, 3, "Z")
		T.eq(first.R, 1, "R")
		T.eq(first.In, nil, "contents stay on the server")
		T.truthy(first ~= m.Entry, "a copy, not the saved table")
		T.eq(snapshot.Build.MachineSlots, 10, "machine slots")
		T.eq(snapshot.Build.ConveyorSlots, 40, "belt slots")
		T.eq(snapshot.Build.MachinesUsed, 1, "machines used")
		T.eq(snapshot.Build.ConveyorsUsed, 2, "belts used")
		-- the output cell maths the client uses matches the server's
		local ox, oz = Grid.outputCell("ClayFurnace", 2, 3, 1)
		T.truthy(ox ~= nil and oz ~= nil, "furnace has an output cell")
	end)
end
