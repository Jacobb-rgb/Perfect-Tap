-- DropperService under Lune with the REAL ItemService.spawnDesc and MachineService (review 2026-10-24):
-- a dropper's tick pushes a real loose Drop onto a belt or an empty cell, through a Money Laser too;
-- Tobin never takes a Drop; a laser holding Drops packs up with a full pen.
-- Save data, plots, Net and the loose-item count are small fakes per test.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local CFrame = roblox.CFrame
	local Players = Loader.game:GetService("Players")
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local DropperService = Loader.requirePath("ServerScriptService.Server.Services.DropperService")

	local PLOT = 6
	local USER = 611
	local LASER = DropperConfig.Laser.Id
	local internals = MachineService._test

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
		local w: any = { notes = {}, loose = 0 }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		w.player = {
			UserId = USER,
			Name = "Dropper",
			Parent = true,
			GetAttribute = function()
				return nil
			end,
		}
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { BasicDropper = 2, [LASER] = 2, Conveyor = 4 }
		w.data = data
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then data else nil
		end)
		patch(DataService, "isInMemory", function()
			return false
		end)
		patch(DataService, "changed", function() end)
		patch(DataService, "beforeRelease", function() end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player then PLOT else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then plotModel else nil
		end)
		patch(Net, "fire", function(name, p, payload)
			table.insert(w.notes, { Name = name, Player = p, Payload = payload })
		end)
		patch(ItemService, "looseCount", function()
			return w.loose
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player else nil
		end)
		ItemService._test.reset()
		internals.reset()
		DropperService._test.reset()
		DropperService.init()
		internals.spawnAll(w.player, PLOT)
		w.restore = function()
			internals.reset()
			DropperService._test.reset()
			ItemService._test.reset()
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

	local function place(w: any, id: string, x: number, z: number): any
		local m, code = MachineService.place(w.player, id, x, z, 0)
		assert(m, `place {id}: {code}`)
		return m
	end

	-- the owner's live Drop records
	local function drops(): { any }
		local list = {}
		for _, record in ItemService.ownedBy(USER) do
			if record.Kind == "Drop" and record.State ~= "Consumed" then
				table.insert(list, record)
			end
		end
		return list
	end

	-- runs the dropper's next Drop now (its timer set to now) and one machine tick
	local function dropNow(m: any)
		m.State.NextDrop = 0
		MachineService.wake(m)
		internals.tick()
	end

	withWorld("dropper service: the real spawnDesc makes a loose Drop with its dropper's value", function(_w)
		local record = ItemService.spawnDesc({ K = "Drop", O = "GoldDropper" }, USER, CFrame.new(0, 5, 0), nil, true)
		T.truthy(record, "a Drop can be a loose item")
		T.eq(record.Kind, "Drop")
		T.eq(record.Model:GetAttribute("Value"), DropperConfig.dropValue("GoldDropper"))
		T.eq(ItemService.spawnDesc({ K = "Drop", O = "NoSuchDropper" } :: any, USER, CFrame.new()), nil, "an unknown dropper makes nothing")
		local marked =
			ItemService.spawnDesc({ K = "Drop", O = "GoldDropper", R = DropperConfig.LaserMark }, USER, CFrame.new(2, 5, 0), nil, true)
		T.eq(marked.Model:GetAttribute("Value"), DropperConfig.dropValue("GoldDropper", true))
	end)

	withWorld("dropper service: a dropper's tick pushes a real Drop onto the belt in front (and onto an empty cell)", function(w)
		local dropper = place(w, "BasicDropper", 2, 2)
		local ox, oz = Grid.outputCell("BasicDropper", 2, 2, 0)
		T.truthy(ox and oz, "the dropper has a front output cell")
		place(w, "Conveyor", ox :: number, oz :: number)
		dropNow(dropper)
		local list = drops()
		T.eq(#list, 1, "one loose Drop on the belt")
		T.eq(list[1].OreId, "BasicDropper")
		T.eq(list[1].State, "Loose")
		T.eq(DropperService.liveOf(USER), 1, "counted for the cap")
		-- a second dropper with nothing in front: the Drop pops onto the empty cell
		local other = place(w, "BasicDropper", 8, 8)
		dropNow(other)
		T.eq(#drops(), 2)
	end)

	withWorld("dropper service: dropper -> Money Laser -> the laser's front: one marked Drop", function(w)
		local dropper = place(w, "BasicDropper", 2, 2)
		local ox, oz = Grid.outputCell("BasicDropper", 2, 2, 0)
		local laser = place(w, LASER, ox :: number, oz :: number)
		dropNow(dropper)
		local out = laser.Entry.Out
		T.truthy(out == nil or #out <= 1, "the laser took it")
		-- the laser's tick pushes it out of its front as a real loose item
		laser.State.NextEmit = 0
		MachineService.wake(laser)
		internals.tick()
		local list = drops()
		T.eq(#list, 1, "one Drop left the laser")
		T.eq(list[1].Recipe, DropperConfig.LaserMark, "doubled once")
		T.eq(laser.Entry.Out, nil, "nothing waits in the laser")
		T.eq(laser.Model:GetAttribute("Cycles"), 1)
	end)

	withWorld("dropper service: at the owner's cap a dropper waits and shows why", function(w)
		local dropper = place(w, "BasicDropper", 2, 2)
		for _ = 1, DropperConfig.MaxLiveDrops do
			ItemService.spawnDesc({ K = "Drop", O = "BasicDropper" }, USER, CFrame.new(0, 5, 0), nil, true)
		end
		DropperService.sweep(os.clock())
		T.eq(DropperService.liveOf(USER), DropperConfig.MaxLiveDrops)
		dropNow(dropper)
		T.eq(#drops(), DropperConfig.MaxLiveDrops, "no Drop over the cap")
		T.eq(dropper.Model:GetAttribute("Status"), "TooManyItems")
	end)

	withWorld("dropper service: a loose Drop older than DropLife goes in the sweep", function(_w)
		local record = ItemService.spawnDesc({ K = "Drop", O = "BasicDropper" }, USER, CFrame.new(0, 5, 0), nil, true)
		DropperService._test.reset()
		DropperService.sweep(os.clock())
		T.eq(DropperService.liveOf(USER), 0, "nobody watched yet")
		-- (an owner with Drops out is watched once a dropper or a laser spawned for them)
		local data = DataService.get(_w.player)
		T.truthy(data)
		local dropper = place(_w, "BasicDropper", 2, 2)
		T.truthy(dropper)
		record.CreatedAt = os.clock() - DropperConfig.DropLife - 1
		DropperService.sweep(os.clock())
		T.eq(record.State, "Consumed", "the old loose Drop is gone")
	end)

	withWorld("dropper service: Tobin never buys a Drop", function(w)
		local SellService = Loader.requirePath("ServerScriptService.Server.Services.SellService")
		local three = ItemService.spawnDesc({ K = "Drop", O = "BasicDropper" }, USER, CFrame.new(0, 5, 0), nil, true)
		T.eq(SellService.sellRecord(three), 0, "Tobin's SellBin pays nothing for a Drop")
		T.eq(SellService.priceOf({ K = "Drop", O = "BasicDropper" }), 0)
	end)

	withWorld("dropper service: a laser holding Drops packs up even with a full pen (they never go there)", function(w)
		local laser = place(w, LASER, 4, 4)
		laser.Entry.Out = { { K = "Drop", O = "BasicDropper", R = DropperConfig.LaserMark } }
		local capacity = ItemService.penCapacity(w.data)
		w.data.Storage = {}
		for _ = 1, capacity do
			table.insert(w.data.Storage, { K = "Clean", O = "Copper", G = "Rough" })
		end
		local ok, why = MachineService.pickup(laser)
		T.truthy(ok, `the laser packs up ({why})`)
		T.eq(#w.data.Storage, capacity, "the Drop did not go to the pen")
	end)
end
