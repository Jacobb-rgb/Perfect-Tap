-- CleaningService's vise scan (SERVER_PERF_AUDIT #10): it keeps its own set
-- of Cleaning Stations from the spawned / removed hooks, looks only into
-- empty stations, and sets its overlap filter only when the Items folder
-- changes. Real MachineService; save data, plots, Net and the Workspace
-- queries are small fakes per test.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local CleaningService = Loader.requirePath("ServerScriptService.Server.Services.CleaningService")
	local Workspace = Loader.game:GetService("Workspace")

	local PLOT = 5
	local internals = MachineService._test
	local cleaning = CleaningService._test

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

	T.test("CleaningService: the vise scan walks its own station list, not every machine", function()
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local player = {
			UserId = 501,
			Name = "Scrubber",
			Parent = true,
			Character = nil,
			GetAttribute = function()
				return nil
			end,
		}
		local data = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = { CleaningStation = 3, ClayFurnace = 2, Conveyor = 30 }
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		local items = Instance.new("Folder")
		local queries = 0
		local ok, err = pcall(function()
			patch(DataService, "get", function(p)
				return if p == player then data else nil
			end)
			patch(DataService, "isInMemory", function()
				return false
			end)
			patch(DataService, "changed", function() end)
			patch(PlotService, "plotOf", function(p)
				return if p == player then PLOT else nil
			end)
			patch(PlotService, "ownerOf", function(id)
				return if id == PLOT then player else nil
			end)
			patch(PlotService, "model", function(id)
				return if id == PLOT then plotModel else nil
			end)
			patch(Net, "fire", function() end)
			patch(Workspace, "FindFirstChild", function(_, name: string)
				return if name == "Items" then items else nil
			end)
			patch(Workspace, "GetPartBoundsInBox", function()
				queries += 1
				return {}
			end)
			internals.reset()
			cleaning.reset()
			MachineService.register("CleaningStation", cleaning.behaviour)
			internals.spawnAll(player, PLOT)
			local a = MachineService.place(player, "CleaningStation", 0, 0, 0)
			local b = MachineService.place(player, "CleaningStation", 4, 0, 0)
			T.truthy(a and b, "two stations placed")
			MachineService.place(player, "ClayFurnace", 8, 0, 0)
			for x = 0, 9 do
				MachineService.place(player, "Conveyor", x, 8, 0)
			end
			T.eq(#cleaning.stations(), 2, "the hooks keep exactly the stations")
			T.truthy(CleaningService.stationOf(player) == a.Model or CleaningService.stationOf(player) == b.Model, "stationOf")

			-- a scan with a counting filter
			local filterSets = 0
			local store = {}
			local params = setmetatable({}, {
				__index = store,
				__newindex = function(_, key, value)
					if key == "FilterDescendantsInstances" then
						filterSets += 1
					end
					store[key] = value
				end,
			})
			local scan = { Params = params, Folder = nil }
			T.eq(cleaning.intakePass(scan), 2, "both empty stations looked into")
			T.eq(queries, 2, "one box query per empty station, none for the other machines")
			T.eq(filterSets, 1, "the filter is set once")
			T.eq(cleaning.intakePass(scan), 2, "again")
			T.eq(filterSets, 1, "not set again while the Items folder stays")
			-- a station someone cleans at is skipped
			a.State.Session = {}
			T.eq(cleaning.intakePass(scan), 1, "busy station skipped")
			a.State.Session = nil
			-- a new Items folder: the filter follows
			items = Instance.new("Folder")
			cleaning.intakePass(scan)
			T.eq(filterSets, 2, "set again for the new folder")
			-- packed up: out of the list
			T.truthy(MachineService.pickup(b), "picked up")
			T.eq(#cleaning.stations(), 1, "the removed hook took it out")
			queries = 0
			T.eq(cleaning.intakePass(scan), 1, "one station left")
			T.eq(queries, 1, "one query")
		end)
		internals.reset()
		cleaning.reset()
		for i = #saved, 1, -1 do
			rawset(saved[i][1], saved[i][2], saved[i][3])
		end
		if not ok then
			error(err, 0)
		end
	end)
	T.test("CleaningService: only a chunk really in the hands goes into the vise (security #11)", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/server/Services/CleaningService.luau")
		T.truthy(source:find("return cleanable(r) and r.State == \"Carried\"", 1, true), "takeTop asks for a carried chunk or relic")
		T.truthy(source:find("if not mount(machine, record) then", 1, true), "a refused mount starts no session")
		T.truthy(source:find("if mount(machine, record) then", 1, true), "nor does the auto-start from the intake")
		local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
		local consumed: any = { State = "Consumed", Model = Instance.new("Model") }
		T.eq(ItemService.mount(consumed, roblox.CFrame.new()), false, "ItemService refuses a consumed record")
	end)

end
