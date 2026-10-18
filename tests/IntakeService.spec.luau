-- IntakeService under Lune: the per-plot zone index (hoppers and belt
-- ends), what the scan does with each loose item, refusals, foreign-item
-- return, town zones and the Put In prompt's loading loop. Roblox-only
-- neighbours are swapped for small fakes and put back afterwards.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local Instance = roblox.Instance
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
	local Players = Loader.game:GetService("Players")

	local PLOT = 5
	local USER, STRANGER = 201, 202
	local CELL = GameConfig.CellSize
	local HALF = GameConfig.PlotCells * CELL / 2
	local intake = IntakeService._test

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

	local function setup(): any
		local w: any = { notes = {}, ejects = {}, stashes = {}, inserts = {}, carried = {}, full = false }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.player = {
			UserId = USER,
			Name = "Owner",
			Parent = true,
			GetAttribute = function()
				return nil
			end,
		}
		w.stranger = {
			UserId = STRANGER,
			Name = "Stranger",
			Parent = true,
			GetAttribute = function()
				return nil
			end,
		}
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { ClayFurnace = 1, Conveyor = 3, StorageCrate = 1 }
		w.data = data
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then data else nil
		end)
		patch(DataService, "changed", function() end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player then PLOT else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then plotModel else nil
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(ItemService, "isTrusted", function(record)
			return record.Trusted ~= false
		end)
		patch(ItemService, "absorb", function(record)
			record.State = "Consumed"
			return ItemService.descOf(record)
		end)
		patch(ItemService, "eject", function(record, velocity)
			record.State = "Loose"
			table.insert(w.ejects, { Record = record, Velocity = velocity })
		end)
		patch(ItemService, "stash", function(record, reason)
			record.State = "Consumed"
			table.insert(w.stashes, { Record = record, Reason = reason })
			return true
		end)
		patch(CarryService, "takeTop", function(_, predicate)
			for i = #w.carried, 1, -1 do
				local record = w.carried[i]
				if not predicate or predicate(record) then
					table.remove(w.carried, i)
					return record
				end
			end
			return nil
		end)
		patch(CarryService, "list", function()
			return w.carried
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == STRANGER then w.stranger else nil
		end)
		MachineService._test.reset()
		intake.reset()
		-- the furnace takes clean ore from its owner, refuses raw ore
		MachineService.register("ClayFurnace", {
			canAccept = function(m, d, owner)
				if owner ~= m.Owner.UserId then
					return false, "Foreign"
				elseif d.K == "Raw" then
					return false, "Wrong"
				elseif w.full then
					return false, "Full"
				end
				return true, nil
			end,
			insert = function(m, d, owner, via)
				table.insert(w.inserts, { Machine = m, Desc = d, Owner = owner, Via = via })
			end,
		})
		MachineService._test.spawnAll(w.player, PLOT)
		-- furnace at 4,4 facing the road; a belt into its left side; a belt
		-- into its front; a lone belt; a crate nobody registered
		w.furnace = MachineService.place(w.player, "ClayFurnace", 4, 4, 0)
		w.sideBelt = MachineService.place(w.player, "Conveyor", 3, 4, 1)
		w.frontBelt = MachineService.place(w.player, "Conveyor", 4, 3, 2)
		w.loneBelt = MachineService.place(w.player, "Conveyor", 9, 9, 0)
		w.crate = MachineService.place(w.player, "StorageCrate", 0, 10, 0)
		assert(w.furnace and w.sideBelt and w.frontBelt and w.loneBelt and w.crate, "layout placed")
		intake.rebuild(PLOT)
		w.restore = function()
			MachineService._test.reset()
			intake.reset()
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

	-- A loose item at a plot-local position.
	local function item(kind: string, localPos: any, owner: number?): any
		local world = PlotService.plotCFrame(PLOT):PointToWorldSpace(localPos)
		return {
			Id = "item",
			Kind = kind,
			OreId = "Copper",
			Grade = if kind == "Raw" then nil else "Rough",
			Owner = owner or USER,
			State = "Loose",
			Body = { Position = world },
			ClientOwnedUntil = nil,
		}
	end

	-- plot-local centre of a cell, `up` studs above the pad
	local function cellCentre(x: number, z: number, up: number): any
		return Vector3.new(-HALF + (x + 0.5) * CELL, up, -HALF + (z + 0.5) * CELL)
	end

	local function kinds(list: { any }): string
		local out = {}
		for _, zone in list do
			table.insert(out, zone.Kind)
		end
		return table.concat(out, ",")
	end

	withWorld("IntakeService: hoppers and belt ends are indexed on the right cells", function(w)
		T.eq(kinds(intake.zonesAt(PLOT, 3, 4)), "Feeder", "belt cell")
		local onFurnace = intake.zonesAt(PLOT, 4, 4)
		T.eq(kinds(onFurnace), "Hopper,Feeder", "target cell: hopper first")
		T.truthy(onFurnace[1].Machine == w.furnace, "hopper of the furnace")
		T.truthy(onFurnace[2].Machine == w.furnace and onFurnace[2].Belt == w.sideBelt, "feeder into the furnace")
		T.eq(kinds(intake.zonesAt(PLOT, 5, 5)), "Hopper", "other furnace cell")
		T.eq(kinds(intake.zonesAt(PLOT, 4, 3)), "", "a belt into the output front feeds nothing")
		T.eq(kinds(intake.zonesAt(PLOT, 9, 9)), "", "lone belt")
		T.eq(kinds(intake.zonesAt(PLOT, 0, 10)), "", "unregistered crate has no hopper")
		-- the index follows the layout
		MachineService.move(w.sideBelt, 3, 5, 1)
		intake.rebuild(PLOT)
		T.eq(kinds(intake.zonesAt(PLOT, 3, 4)), "", "old belt cell")
		T.eq(kinds(intake.zonesAt(PLOT, 3, 5)), "Feeder", "new belt cell")
		MachineService.pickup(w.furnace)
		intake.rebuild(PLOT)
		T.eq(kinds(intake.zonesAt(PLOT, 4, 4)), "", "packed-up furnace")
	end)

	withWorld("IntakeService: belt ends and hoppers put items in", function(w)
		-- on the belt, just before the furnace's side
		local onBelt = item("Clean", Vector3.new(-HALF + 4 * CELL - 0.3, 1, -HALF + 4.5 * CELL))
		intake.scanOne(onBelt, 10)
		T.eq(#w.inserts, 1, "fed from the belt")
		T.eq(w.inserts[1].Via, "Belt", "via Belt")
		T.eq(onBelt.State, "Consumed", "absorbed")
		-- pressed into the furnace's own cell
		local pressed = item("Clean", Vector3.new(-HALF + 4 * CELL + 0.05, 1, -HALF + 4.5 * CELL))
		intake.scanOne(pressed, 10)
		T.eq(#w.inserts, 2, "fed from inside the target cell")
		T.eq(w.inserts[2].Via, "Belt", "via Belt")
		-- dropped into the hopper
		local base = w.furnace.Model.PrimaryPart
		local hopper = base.CFrame * base:FindFirstChild("Intake").CFrame
		local dropped = item("Clean", PlotService.plotCFrame(PLOT):PointToObjectSpace(hopper.Position))
		intake.scanOne(dropped, 10)
		T.eq(#w.inserts, 3, "hopper")
		T.eq(w.inserts[3].Via, "Drop", "via Drop")
		T.eq(w.inserts[3].Owner, USER, "owner passed on")
		-- untrusted items wait
		local sketchy = item("Clean", Vector3.new(-HALF + 4 * CELL - 0.3, 1, -HALF + 4.5 * CELL))
		sketchy.Trusted = false
		intake.scanOne(sketchy, 10)
		T.eq(#w.inserts, 3, "untrusted item skipped")
		T.eq(sketchy.State, "Loose", "still loose")
		-- a full machine: the item just waits
		w.full = true
		local waiting = item("Clean", Vector3.new(-HALF + 4 * CELL - 0.3, 1, -HALF + 4.5 * CELL))
		intake.scanOne(waiting, 10)
		T.eq(waiting.State, "Loose", "waits")
		T.eq(#w.ejects, 0, "not pushed away")
	end)

	withWorld("IntakeService: refused items bounce out with a hint", function(w)
		local beltPos = Vector3.new(-HALF + 4 * CELL - 0.3, 1, -HALF + 4.5 * CELL)
		local raw = item("Raw", beltPos)
		intake.scanOne(raw, 10)
		T.eq(#w.inserts, 0, "refused")
		T.eq(#w.ejects, 1, "pushed off")
		local right = w.sideBelt.Model:GetPivot().RightVector
		local expected = right * GameConfig.BeltRejectPop.Side + Vector3.new(0, GameConfig.BeltRejectPop.Up, 0)
		T.near((w.ejects[1].Velocity - expected).Magnitude, 0, 1e-4, "off the belt's side")
		local fx, hints = 0, 0
		for _, note in w.notes do
			if note.Name == "Fx" and note.A == "Reject" then
				fx += 1
			elseif note.Name == "Notify" then
				hints += 1
				T.eq(note.A.Text, MachineData.ById.ClayFurnace.WrongHint, "hint text")
			end
		end
		T.eq(fx, 1, "reject effect")
		T.eq(hints, 1, "hint")
		-- the same item again right away: no second bounce
		intake.scanOne(raw, 10)
		T.eq(#w.ejects, 1, "per-item cooldown")
		-- another raw item: bounces, but the hint is throttled
		intake.scanOne(item("Raw", beltPos), 10)
		T.eq(#w.ejects, 2, "second item bounces")
		local hintsAfter = 0
		for _, note in w.notes do
			if note.Name == "Notify" then
				hintsAfter += 1
			end
		end
		T.eq(hintsAfter, 1, "hint throttled")
		-- someone else's ore thrown into the hopper: bounces out the front, no hint
		local base = w.furnace.Model.PrimaryPart
		local hopper = base.CFrame * base:FindFirstChild("Intake").CFrame
		local foreign = item("Clean", PlotService.plotCFrame(PLOT):PointToObjectSpace(hopper.Position), STRANGER)
		intake.scanOne(foreign, 10)
		T.eq(#w.ejects, 3, "foreign item bounces")
		local look = w.furnace.Model:GetPivot().LookVector
		local out = look * GameConfig.RejectPop.Out + Vector3.new(0, GameConfig.RejectPop.Up, 0)
		T.near((w.ejects[3].Velocity - out).Magnitude, 0, 1e-4, "out of the front")
		local last = w.notes[#w.notes]
		T.eq(last.Name, "Fx", "only the effect")
		T.truthy(last.Player == w.stranger, "to the item's owner")
	end)

	withWorld("IntakeService: belts, other forges and town zones", function(w)
		-- an item riding a belt that feeds nothing goes to the belt handler
		local calls = {}
		IntakeService.setBeltHandler(function(belt, record, localPos, now)
			table.insert(calls, { belt, record, localPos, now })
		end)
		local riding = item("Clean", cellCentre(4, 3, 1))
		intake.scanOne(riding, 12)
		T.eq(#calls, 1, "belt handler")
		T.truthy(calls[1][1] == w.frontBelt, "the belt under it")
		T.near((calls[1][3] - Vector3.new(0, 1, 0)).Magnitude, 0, 1e-3, "belt-local position")
		T.eq(calls[1][4], 12, "time")
		T.eq(#w.inserts, 0, "a belt into the front feeds nothing")

		-- someone else's item lying on this forge goes home after a while
		local visitor = item("Clean", cellCentre(10, 10, 0.5), STRANGER)
		intake.scanOne(visitor, 100)
		intake.scanOne(visitor, 100 + GameConfig.ForeignItemReturn - 0.1)
		T.eq(#w.stashes, 0, "not yet")
		intake.scanOne(visitor, 100 + GameConfig.ForeignItemReturn)
		T.eq(#w.stashes, 1, "returned")
		T.eq(w.stashes[1].Reason, "Your item landed on another forge", "toast")
		local mine = item("Clean", cellCentre(10, 10, 0.5))
		intake.scanOne(mine, 100)
		intake.scanOne(mine, 200)
		T.eq(#w.stashes, 1, "your own items stay")

		-- town zones take trusted items
		local part = Instance.new("Part")
		part.CFrame = CFrame.new(0, 3, 60)
		part.Size = Vector3.new(8, 5, 6)
		part.Parent = Instance.new("Folder")
		local sold = {}
		IntakeService.addZone("SellBin", part, function(record)
			table.insert(sold, record)
		end)
		local function at(position: any, trusted: boolean): any
			return { Kind = "Clean", OreId = "Copper", Owner = USER, State = "Loose", Body = { Position = position }, Trusted = trusted }
		end
		intake.scanOne(at(Vector3.new(1, 2, 61), false), 5)
		T.eq(#sold, 0, "untrusted item ignored")
		intake.scanOne(at(Vector3.new(1, 2, 61), true), 5)
		T.eq(#sold, 1, "sold")
		intake.scanOne(at(Vector3.new(10, 2, 61), true), 5)
		T.eq(#sold, 1, "outside the box")
	end)

	withWorld("IntakeService: Put In loads what fits from your hands", function(w)
		local function carried(kind: string): any
			return {
				Id = kind,
				Kind = kind,
				OreId = "Copper",
				Grade = if kind == "Raw" then nil else "Rough",
				Owner = USER,
				State = "Carried",
			}
		end
		w.carried = { carried("Clean"), carried("Raw"), carried("Clean") }
		intake.load(w.player, w.furnace)
		T.eq(#w.inserts, 2, "both clean ores")
		T.eq(w.inserts[1].Via, "Hand", "via Hand")
		T.eq(#w.carried, 1, "raw ore stays in your hands")
		T.eq(w.carried[1].Kind, "Raw", "raw")
		local notes = #w.notes
		intake.load(w.player, w.furnace)
		T.eq(w.notes[notes + 1].A.Text, MachineData.ById.ClayFurnace.WrongHint, "why nothing went in")
		w.carried = { carried("Clean") }
		w.full = true
		intake.load(w.player, w.furnace)
		T.eq(w.notes[#w.notes].A.Text, "Your Clay Furnace is full.", "full")
		T.eq(#w.carried, 1, "kept")
		intake.load(w.stranger, w.furnace)
		T.eq(w.notes[#w.notes].A.Text, "That's not your machine.", "not yours")
		w.carried = {}
		intake.load(w.player, w.furnace)
		T.eq(w.notes[#w.notes].A.Text, "Carry items here to put them in the Clay Furnace.", "empty hands")
	end)
	---------------------------------------------------------------- town zone index (perf pass 1)

	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")

	-- A zone part at a world CFrame.
	local function zonePart(cf: any, size: any): any
		local part = Instance.new("Part")
		part.CFrame = cf
		part.Size = size
		part.Parent = Instance.new("Folder")
		return part
	end

	local function looseAt(position: any): any
		return { Kind = "Clean", OreId = "Copper", Owner = USER, State = "Loose", Body = { Position = position }, Trusted = true }
	end

	local function plotPoint(plotId: number, x: number, y: number, z: number): any
		return WorldLayout.plotCFrame(WorldLayout.Plots[plotId]):PointToWorldSpace(Vector3.new(x, y, z))
	end

	-- Every plot gets a zone on its pad and one in its yard (like the pens and
	-- the foundry hoppers), the town a SellBin, a turned box, two overlapping
	-- boxes and one across a plot's edge.
	local function townZones(taken: { string }): { any }
		local zones = {}
		local function add(name: string, cf: any, size: any)
			local part = zonePart(cf, size)
			IntakeService.addZone(name, part, function(record)
				record.State = "Consumed"
				table.insert(taken, name)
			end)
			table.insert(zones, { Name = name, Part = part })
		end
		for _, plot in WorldLayout.Plots do
			local cf = WorldLayout.plotCFrame(plot)
			add("Pad" .. plot.Id, cf * CFrame.new(14, 2, -6), Vector3.new(6, 4, 6))
			add("Yard" .. plot.Id, cf * CFrame.new(0, 2, 40), Vector3.new(10, 4, 8))
		end
		add("SellBin", CFrame.new(0, 3, 60), Vector3.new(8, 5, 6))
		add("Turned", CFrame.new(30, 2, -40) * CFrame.Angles(0, math.rad(35), math.rad(10)), Vector3.new(12, 4, 3))
		add("First", CFrame.new(-20, 2, 10), Vector3.new(8, 4, 8))
		add("Second", CFrame.new(-17, 2, 13), Vector3.new(8, 4, 8))
		local plot1 = WorldLayout.plotCFrame(WorldLayout.Plots[1])
		add("Edge", plot1 * CFrame.new(-26, 2, 0), Vector3.new(6, 4, 10))
		return zones
	end

	withWorld("IntakeService: an item is tested only against the town zones of its plot or its town square", function(_w)
		local taken = {}
		townZones(taken)
		-- on plot 5's pad: only the zones over plot 5
		local onPad = intake.candidates(plotPoint(PLOT, 14, 2, -6))
		T.eq(table.concat(onPad, ","), "Pad5", "plot 5's own zones")
		local elsewhere = intake.candidates(plotPoint(PLOT, -10, 1, 10))
		T.eq(table.concat(elsewhere, ","), "Pad5", "the same few anywhere on the plot")
		-- the town: only the zones in the item's square
		T.eq(table.concat(intake.candidates(Vector3.new(1, 2, 61)), ","), "SellBin", "next to the SellBin")
		T.eq(#intake.candidates(Vector3.new(0, 2, -100)), 0, "an empty field: no box test at all")
		local overlap = intake.candidates(Vector3.new(-18, 2, 12))
		T.eq(table.concat(overlap, ","), "First,Second", "overlapping boxes in the order they were added")
		-- the same zone still takes the item, the first added wins
		intake.scanOne(looseAt(Vector3.new(-18, 2, 12)), 5)
		T.eq(table.concat(taken, ","), "First", "first added wins")
		intake.scanOne(looseAt(plotPoint(PLOT, 14, 2, -6)), 5)
		T.eq(taken[2], "Pad5", "a zone on the plot comes before the plot's machines")
		local sketchy = looseAt(Vector3.new(1, 2, 61))
		sketchy.Trusted = false
		intake.scanOne(sketchy, 5)
		T.eq(#taken, 2, "untrusted: ignored")
		T.eq(sketchy.State, "Loose")
	end)

	withWorld("IntakeService: the zone index takes an item exactly where testing every zone would", function(_w)
		local taken = {}
		local zones = townZones(taken)
		local function reference(position: any): string?
			for _, zone in zones do
				local part = zone.Part
				if part.Parent then
					local q = part.CFrame:PointToObjectSpace(position)
					local h = part.Size / 2
					if math.abs(q.X) <= h.X and math.abs(q.Y) <= h.Y and math.abs(q.Z) <= h.Z then
						return zone.Name
					end
				end
			end
			return nil
		end
		-- a small seeded generator (Lune has no Random)
		local seed = 7
		local rng = {}
		function rng.NextNumber(_, lo: number, hi: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return lo + (hi - lo) * seed / 2147483648
		end
		local points = {}
		for _ = 1, 2500 do
			table.insert(points, Vector3.new(rng:NextNumber(-150, 150), rng:NextNumber(-1, 7), rng:NextNumber(-130, 130)))
		end
		for _, zone in zones do
			local c = zone.Part.CFrame.Position
			for _ = 1, 60 do
				table.insert(points, c + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-3, 3), rng:NextNumber(-6, 6)))
			end
		end
		local hits = 0
		for i, position in points do
			local expected = reference(position)
			local before = #taken
			intake.scanOne(looseAt(position), 5)
			local got = if #taken > before then taken[#taken] else nil
			if expected then
				hits += 1
			end
			T.eq(got, expected, `point {i} at {position}`)
		end
		T.truthy(hits > 250, "enough points inside the zones: " .. hits)
	end)

	withWorld("IntakeService: the cached zone boxes follow a moved, resized or removed zone part", function(_w)
		local taken = {}
		local part = zonePart(CFrame.new(0, 3, 60), Vector3.new(8, 5, 6))
		IntakeService.addZone("SellBin", part, function(record)
			record.State = "Consumed"
			table.insert(taken, "SellBin")
		end)
		intake.scanOne(looseAt(Vector3.new(1, 2, 61)), 5)
		T.eq(#taken, 1, "taken where it stands")
		-- moved (its CFrame signal marks the index)
		part.CFrame = CFrame.new(40, 3, 60)
		intake.invalidate()
		intake.scanOne(looseAt(Vector3.new(1, 2, 61)), 5)
		T.eq(#taken, 1, "not at the old place")
		intake.scanOne(looseAt(Vector3.new(41, 2, 61)), 5)
		T.eq(#taken, 2, "at the new place")
		-- resized
		part.Size = Vector3.new(30, 5, 6)
		intake.invalidate()
		intake.scanOne(looseAt(Vector3.new(53, 2, 61)), 5)
		T.eq(#taken, 3, "the bigger box")
		-- removed: skipped at once, even before the index is rebuilt
		local parent = part.Parent
		part.Parent = nil
		intake.scanOne(looseAt(Vector3.new(41, 2, 61)), 5)
		T.eq(#taken, 3, "a removed zone takes nothing")
		intake.invalidate()
		T.eq(#intake.candidates(Vector3.new(41, 2, 61)), 0, "and leaves the index")
		-- back again
		part.Parent = parent
		intake.invalidate()
		intake.scanOne(looseAt(Vector3.new(41, 2, 61)), 5)
		T.eq(#taken, 4, "back in the index")
		-- a zone added later joins the index
		local later = zonePart(CFrame.new(-60, 3, 60), Vector3.new(4, 4, 4))
		IntakeService.addZone("Later", later, function(record)
			record.State = "Consumed"
			table.insert(taken, "Later")
		end)
		intake.scanOne(looseAt(Vector3.new(-60, 3, 60)), 5)
		T.eq(taken[#taken], "Later", "a new zone")
	end)
end
