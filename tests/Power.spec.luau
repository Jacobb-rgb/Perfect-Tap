-- Power (WP-Power): PowerLogic's networks (pole links in and out of
-- range, reach, separate networks, the nearest pole, tidy cable links,
-- deterministic results), supply / demand -> machine speed (full, partial,
-- none), generator Speed levels, the attribute encoding; PowerService's
-- attributes, speed modifier, rebuilt models and Tech shop upgrades through
-- a small harness (and once on the real MachineService); PowerController's
-- cables on real kit models.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local task = require("@lune/task")
	local Instance = roblox.Instance
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local PowerLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.PowerLogic")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local ShopService = Loader.requirePath("ServerScriptService.Server.Services.ShopService")
	local PowerService = Loader.requirePath("ServerScriptService.Server.Services.PowerService")
	local PowerController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.PowerController")
	local RunService = Loader.game:GetService("RunService")

	local RULES = MachineData.PowerRules
	local UNPOWERED = RULES.UnpoweredSpeed

	local function e(id: string, x: number, z: number, r: number?): any
		return { Id = id, X = x, Z = z, R = r or 0 }
	end

	-- Waits until check() holds, at most `timeout` seconds: deferred computes can take
	-- more than one frame when many test runs share the machine.
	local function waitUntil(check: () -> boolean, timeout: number?)
		local deadline = os.clock() + (timeout or 5) -- generous: returns as soon as the check holds
		repeat
			task.wait()
		until check() or os.clock() > deadline
	end

	local function speedOn(supply: number, demand: number): number
		return UNPOWERED + (1 - UNPOWERED) * math.min(1, supply / demand)
	end

	---------------------------------------------------------------- PowerLogic

	T.test("PowerLogic: kinds and the encoding helpers", function()
		T.eq(PowerLogic.kindOf(MachineData.ById.PowerPole), "Pole")
		T.eq(PowerLogic.kindOf(MachineData.ById.SolarPanel), "Generator")
		T.eq(PowerLogic.kindOf(MachineData.ById.WindTurbine), "Generator")
		T.eq(PowerLogic.kindOf(MachineData.ById.FusionReactor), "Generator")
		T.eq(PowerLogic.kindOf(MachineData.ById.BrickFurnace), "Machine")
		T.eq(PowerLogic.kindOf(MachineData.ById.Sorter), "Machine")
		-- the starter tier needs no power (a new player is never slowed)
		for _, id in { "ClayFurnace", "Crusher", "AutoCleaner", "IronBox", "Splitter" } do
			T.eq(PowerLogic.kindOf(MachineData.ById[id]), "Other", id .. " needs no power")
		end
		T.eq(PowerLogic.kindOf(MachineData.ById.SellBox), "Other")
		T.eq(PowerLogic.kindOf(MachineData.ById.Conveyor), "Other")
		T.eq(PowerLogic.kindOf(nil), "Other")
		T.eq(PowerLogic.reach(5, 5, 8, 5, 2, 2), 3, "3 cells to the left edge")
		T.eq(PowerLogic.reach(5, 5, 4, 4, 2, 2), 0, "inside the footprint")
		T.eq(PowerLogic.reach(0, 0, 3, 4, 1, 1), 4, "Chebyshev: the larger axis")
		local text = PowerLogic.encodeCells({ { X = 1, Z = 2 }, { X = 10, Z = 0 } })
		T.eq(text, "1,2;10,0")
		local cells = PowerLogic.decodeCells(text)
		T.eq(#cells, 2)
		T.eq(cells[2].X, 10)
		T.eq(cells[2].Z, 0)
		T.eq(PowerLogic.encodeCells({}), "")
		T.eq(#PowerLogic.decodeCells(""), 0)
		T.eq(#PowerLogic.decodeCells(nil), 0, "not a string")
		T.eq(#PowerLogic.decodeCells("x;3,4;5;;6,7,8"), 2, "junk skipped")
		T.eq(#PowerLogic.decodeCells(string.rep("1,1;", 500)), PowerLogic.MaxCells, "capped")
		T.eq(PowerLogic.round2(0.8999999), 0.9)
		T.eq(PowerLogic.round2(18.75), 18.75)
		local levels = PowerLogic.speedLevels({ WindTurbine = { Speed = 2 }, Crusher = { Quality = 1 }, Bad = 5, [3] = {} })
		T.eq(levels.WindTurbine, 2)
		T.eq(levels.Crusher, nil)
		T.eq(levels.Bad, nil)
		T.eq(next(PowerLogic.speedLevels(nil)), nil)
	end)

	T.test("PowerLogic: poles link within PoleLink cells, not beyond", function()
		T.eq(RULES.PoleLink, 6, "the rule this test was written for")
		-- in range (6 cells, also diagonally: Chebyshev)
		for _, other in { { 6, 0 }, { 0, 6 }, { 6, 6 }, { 3, 5 } } do
			local result = PowerLogic.compute({ e("PowerPole", 0, 0), e("PowerPole", other[1], other[2]) })
			T.eq(#result.Networks, 1, `{other[1]},{other[2]} one network`)
			T.eq(result.Poles[1].Network, result.Poles[2].Network, "same id")
			T.eq(result.Poles[1].Links[1], 2, "1 links to 2")
			T.eq(result.Poles[2].Links[1], 1, "2 links to 1")
		end
		-- out of range
		for _, other in { { 7, 0 }, { 0, 7 }, { 7, 2 } } do
			local result = PowerLogic.compute({ e("PowerPole", 0, 0), e("PowerPole", other[1], other[2]) })
			T.eq(#result.Networks, 2, `{other[1]},{other[2]} two networks`)
			T.truthy(result.Poles[1].Network ~= result.Poles[2].Network, "different ids")
			T.eq(#result.Poles[1].Links, 0, "no link")
			T.eq(#result.Poles[2].Links, 0, "no link")
		end
		-- a chain carries further than one link
		local chain = PowerLogic.compute({ e("PowerPole", 0, 0), e("PowerPole", 5, 0), e("PowerPole", 10, 0) })
		T.eq(#chain.Networks, 1, "chain of three")
		T.eq(chain.Networks[1].Id, "0,0", "named after its first pole")
	end)

	T.test("PowerLogic: cable links are the shortest that join the network (no web)", function()
		-- every pair is in range, but the cables run 0 -> 3 -> 6
		local result = PowerLogic.compute({ e("PowerPole", 6, 0), e("PowerPole", 0, 0), e("PowerPole", 3, 0) })
		T.eq(#result.Networks, 1)
		T.eq(#result.Poles[2].Links, 1, "end pole: one cable")
		T.eq(result.Poles[2].Links[1], 3, "0,0 -> 3,0")
		T.eq(#result.Poles[3].Links, 2, "middle pole: two cables")
		T.eq(result.Poles[3].Links[1], 2, "cell order: 0,0 first")
		T.eq(result.Poles[3].Links[2], 1, "then 6,0")
		T.eq(#result.Poles[1].Links, 1, "other end: one cable")
		-- a square of four: 3 cables, not 6
		local square = PowerLogic.compute({ e("PowerPole", 0, 0), e("PowerPole", 4, 0), e("PowerPole", 0, 4), e("PowerPole", 4, 4) })
		local cables = 0
		for _, pole in square.Poles do
			cables += #pole.Links
		end
		T.eq(cables / 2, 3, "a spanning tree of 4 poles")
	end)

	T.test("PowerLogic: machines and generators in PoleReach join, beyond it they don't", function()
		T.eq(RULES.PoleReach, 3, "the rule this test was written for")
		-- a 2x2 furnace 3 cells right of the pole (its left column at x 8)
		local near = PowerLogic.compute({ e("PowerPole", 5, 5), e("BrickFurnace", 8, 5), e("SolarPanel", 2, 2) })
		T.eq(near.Machines[2].Network, "5,5", "furnace in reach")
		T.eq(near.Machines[2].Pole, 1, "fed by the pole")
		T.eq(near.Machines[3].Network, "5,5", "solar panel in reach (its corner cell 3,3)")
		T.eq(near.Poles[1].Feeds[1], 3, "feeds in cell order: the panel (z 2) first")
		T.eq(near.Poles[1].Feeds[2], 2, "then the furnace")
		T.truthy(near.Machines[2].Powered, "powered")
		-- one cell further: out of reach
		local far = PowerLogic.compute({ e("PowerPole", 5, 5), e("BrickFurnace", 9, 5), e("SolarPanel", 0, 0) })
		T.eq(far.Machines[2].Network, nil, "furnace out of reach")
		T.eq(far.Machines[3].Network, nil, "panel out of reach (its corner cell 1,1 is 4 away)")
		T.falsy(far.Machines[2].Powered, "not powered")
		T.eq(far.Machines[2].Speed, UNPOWERED, "unpowered speed")
		T.eq(#far.Poles[1].Feeds, 0, "feeds nothing")
		-- a rotated machine reaches with its turned footprint (3x2 Alloy Furnace turned: 2 wide, 3 deep)
		local turned = PowerLogic.compute({ e("PowerPole", 0, 0), e("AlloyFurnace", 2, 3, 1) })
		T.eq(turned.Machines[2].Network, "0,0", "rotated footprint 2..3 x 3..5 is 3 cells away")
	end)

	T.test("PowerLogic: two separate networks keep their power apart", function()
		local result = PowerLogic.compute({
			e("PowerPole", 0, 0),
			e("WindTurbine", 1, 1), -- 40 power on the left network
			e("PowerPole", 10, 0),
			e("Polisher", 9, 1), -- 12 needed on the right network, no generator there
			e("BrickFurnace", 1, 3), -- 10 needed on the left network
		})
		T.eq(#result.Networks, 2)
		local left, right = result.ByNetwork["0,0"], result.ByNetwork["10,0"]
		T.truthy(left and right, "both networks by id")
		T.eq(left.Supply, 40)
		T.eq(left.Demand, 10)
		T.eq(right.Supply, 0)
		T.eq(right.Demand, 12)
		T.eq(result.Machines[5].Speed, 1, "left furnace at full speed")
		T.truthy(result.Machines[5].Powered, "left furnace powered")
		T.eq(result.Machines[4].Network, "10,0", "the polisher is on a network...")
		T.falsy(result.Machines[4].Powered, "...without power")
		T.eq(result.Machines[4].Speed, UNPOWERED, "so it is slow")
		T.eq(result.Networks[1].Id, "0,0", "networks in the order of their first poles")
	end)

	T.test("PowerLogic: a machine in reach of two networks joins the nearest pole's", function()
		-- poles 8 cells apart (not linked); a 1x1 Sorter 3 cells from the left
		-- pole and 5 from the right one
		local result = PowerLogic.compute({ e("PowerPole", 8, 0), e("PowerPole", 0, 0), e("Sorter", 3, 0) })
		T.eq(#result.Networks, 2)
		T.eq(result.Machines[3].Network, "0,0", "nearest pole")
		T.eq(result.Machines[3].Pole, 2)
		T.eq(#result.Poles[1].Feeds, 0, "the far pole feeds nothing")
		-- equal cells (3 from both): the shorter straight line wins (a 2x2
		-- furnace at 3..4 x 2..3: centre 4,3; poles at 0,0 and 7,1 are 7 apart)
		local line = PowerLogic.compute({ e("PowerPole", 0, 0), e("PowerPole", 7, 1), e("BrickFurnace", 3, 2) })
		T.eq(#line.Networks, 2, "not linked")
		T.eq(line.Machines[3].Network, "7,1", "closer in a straight line")
		-- a perfect tie: the first pole in cell order, whatever the entry order
		local tie = PowerLogic.compute({ e("PowerPole", 7, 0), e("PowerPole", 0, 0), e("BrickFurnace", 3, 0) })
		T.eq(tie.Machines[3].Network, "0,0", "first pole in cell order")
		T.eq(tie.Machines[3].Pole, 2)
	end)

	T.test("PowerLogic: supply / demand -> speed (full, partial, none)", function()
		-- full: 40 for 12
		local full = PowerLogic.compute({ e("PowerPole", 4, 4), e("WindTurbine", 1, 4), e("Polisher", 6, 4) })
		T.eq(full.Machines[3].Speed, 1, "full")
		T.truthy(full.Machines[3].Powered)
		-- partial: 15 for 20 -> 0.6 + 0.4 * 0.75
		local partial = PowerLogic.compute({ e("PowerPole", 4, 4), e("SolarPanel", 1, 4), e("BlastFurnace", 6, 4) })
		T.near(partial.Machines[3].Speed, 0.9, 1e-9, "partial")
		T.near(partial.Machines[3].Speed, speedOn(15, 20), 1e-9, "the rule")
		T.truthy(partial.Machines[3].Powered, "slowed but powered")
		T.near(partial.Networks[1].Speed, 0.9, 1e-9, "network speed")
		-- none: a pole and machines but no generator
		local none = PowerLogic.compute({ e("PowerPole", 4, 4), e("Polisher", 6, 4), e("BrickFurnace", 1, 4) })
		T.eq(none.Machines[2].Speed, UNPOWERED, "none")
		T.falsy(none.Machines[2].Powered)
		T.eq(none.Networks[1].Demand, 22, "12 + 10")
		-- no pole at all: everything slow, generators make nothing for anyone
		local alone = PowerLogic.compute({ e("WindTurbine", 0, 0), e("Polisher", 2, 0) })
		T.eq(alone.Machines[2].Speed, UNPOWERED, "a generator without a pole powers nothing")
		T.eq(alone.Machines[1].PowerOut, 40, "it still makes its power")
		T.eq(#alone.Networks, 0)
		-- machines without Power always run at 1, and get no network
		local other = PowerLogic.compute({ e("PowerPole", 4, 4), e("SellBox", 5, 4), e("Conveyor", 3, 4) })
		T.eq(other.Machines[2].Speed, 1, "Sell Box")
		T.eq(other.Machines[3].Speed, 1, "belt")
		T.eq(other.Machines[2].Network, nil, "not fed")
		T.eq(#other.Poles[1].Feeds, 0, "no cables to machines without Power")
		-- many machines share one network's power
		local shared = PowerLogic.compute({
			e("PowerPole", 5, 5),
			e("SolarPanel", 2, 5), -- 15
			e("Polisher", 6, 5), -- 12
			e("BrickFurnace", 5, 7), -- 10
			e("RobotArm", 4, 4), -- 4
			e("Sorter", 3, 3), -- 2
		})
		local network = shared.Networks[1]
		T.eq(network.Supply, 15)
		T.eq(network.Demand, 28)
		for i = 3, 6 do
			T.near(shared.Machines[i].Speed, speedOn(15, 28), 1e-9, `machine {i} shares the speed`)
		end
	end)

	T.test("PowerLogic: generator Speed levels make more power", function()
		local entries = { e("PowerPole", 5, 5), e("WindTurbine", 2, 5), e("AlloyFurnace", 6, 5), e("PlasmaFurnace", 6, 7) }
		local base = PowerLogic.compute(entries)
		T.eq(base.Networks[1].Supply, 40, "level 0")
		T.eq(base.Networks[1].Demand, 90, "30 + 60")
		T.near(base.Machines[3].Speed, speedOn(40, 90), 1e-9)
		for level = 1, 5 do
			local result = PowerLogic.compute(entries, { WindTurbine = level })
			local supply = 40 * (1 + RULES.PowerPerLevel * level)
			T.near(result.Networks[1].Supply, supply, 1e-9, `level {level} supply`)
			T.near(result.Machines[2].PowerOut, supply, 1e-9, `level {level} PowerOut`)
			T.near(result.Machines[3].Speed, speedOn(supply, 90), 1e-9, `level {level} speed`)
		end
		-- levels of other types change nothing; broken levels count as 0, big ones as 5
		T.eq(PowerLogic.compute(entries, { AlloyFurnace = 5 }).Networks[1].Supply, 40)
		T.eq(PowerLogic.compute(entries, { WindTurbine = 0 / 0 }).Networks[1].Supply, 40)
		T.eq(PowerLogic.compute(entries, { WindTurbine = 99 }).Networks[1].Supply, 40 * (1 + RULES.PowerPerLevel * 5))
		-- two generators add up
		local two = PowerLogic.compute({ e("PowerPole", 5, 5), e("WindTurbine", 2, 5), e("SolarPanel", 6, 5) }, { SolarPanel = 2 })
		T.eq(two.Networks[1].Supply, 40 + 15 * 1.5)
	end)

	T.test("PowerLogic: deterministic whatever the entry order, broken entries skipped", function()
		local list = {
			e("PowerPole", 6, 0),
			e("Polisher", 7, 2),
			e("PowerPole", 0, 0),
			e("WindTurbine", 1, 2),
			e("PowerPole", 3, 0),
			e("BrickFurnace", 4, 2),
			{ Id = "Nope", X = 1, Z = 1, R = 0 },
			{ Id = "Polisher", X = 0 / 0, Z = 1, R = 0 },
			{ Id = "Polisher", X = 1.5, Z = 1, R = 0 },
		}
		local function snapshot(entries: { any }): { [string]: string }
			local result = PowerLogic.compute(entries)
			local out = {}
			for i, entry in entries do
				local res = result.Machines[i]
				if res then
					local key = `{entry.Id}@{entry.X},{entry.Z}`
					local text = `{res.Kind} {res.Speed} {tostring(res.Network)} {tostring(res.Powered)}`
					local pole = result.Poles[i]
					if pole then
						local links, feeds = {}, {}
						for _, j in pole.Links do
							table.insert(links, `{entries[j].X},{entries[j].Z}`)
						end
						for _, j in pole.Feeds do
							table.insert(feeds, `{entries[j].X},{entries[j].Z}`)
						end
						text ..= ` L{table.concat(links, ";")} F{table.concat(feeds, ";")}`
					end
					out[key] = text
				end
			end
			return out
		end
		local first = snapshot(list)
		local count = 0
		for _ in first do
			count += 1
		end
		T.eq(count, 6, "the 3 broken entries get no result")
		local reversed = {}
		for i = #list, 1, -1 do
			table.insert(reversed, list[i])
		end
		local second = snapshot(reversed)
		for key, text in first do
			T.eq(second[key], text, key)
		end
		local result = PowerLogic.compute(list)
		T.eq(result.Networks[1].Id, "0,0", "the first pole in cell order names it")
		T.eq(result.Poles[3].Feeds[1], 4, "the pole at 0,0 feeds the turbine")
	end)

	---------------------------------------------------------------- PowerService (harness)

	local function fakePlayer(userId: number): any
		return { UserId = userId, Name = "P" .. userId, Parent = true }
	end

	-- A fake world: MachineService.ofPlayer returns w.machines, DataService.get w.data.
	local function setup(): any
		local w: any = { machines = {}, data = { MachineUpgrades = {} }, player = fakePlayer(301), changed = 0 }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(MachineService, "ofPlayer", function(p)
			return if p == w.player then table.clone(w.machines) else {}
		end)
		patch(DataService, "get", function(p)
			return if p == w.player then w.data else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		w.patch = patch
		w.add = function(id: string, x: number, z: number, r: number?): any
			local model = Instance.new("Model")
			model.Name = id
			local entry = { Id = id, X = x, Z = z, R = r or 0 }
			local machine = {
				Model = model,
				Id = id,
				Owner = w.player,
				PlotId = 1,
				X = x,
				Z = z,
				R = r or 0,
				State = {},
				Entry = entry,
				Info = MachineData.ById[id],
				Removed = false,
			}
			table.insert(w.machines, machine)
			return machine
		end
		PowerService._test.reset()
		w.restore = function()
			PowerService._test.reset()
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

	withWorld("PowerService: attributes on machines, generators and poles", function(w)
		local pole = w.add("PowerPole", 5, 5)
		local pole2 = w.add("PowerPole", 9, 5)
		local panel = w.add("SolarPanel", 2, 5) -- 15
		local blast = w.add("BlastFurnace", 6, 7) -- 20
		local sell = w.add("SellBox", 10, 9) -- no power
		local lonely = w.add("WindTurbine", 0, 10) -- no pole near
		PowerService._test.recompute(w.player)
		local m = blast.Model
		T.eq(m:GetAttribute("PowerSpeed"), 0.9, "15 for 20")
		T.eq(m:GetAttribute("Powered"), true)
		T.eq(m:GetAttribute("Network"), "5,5")
		T.eq(panel.Model:GetAttribute("PowerOut"), 15)
		T.eq(panel.Model:GetAttribute("Network"), "5,5")
		T.eq(lonely.Model:GetAttribute("PowerOut"), 40, "makes power...")
		T.eq(lonely.Model:GetAttribute("Network"), "", "...for no network")
		T.eq(sell.Model:GetAttribute("PowerSpeed"), nil, "no power attributes on a Sell Box")
		T.eq(sell.Model:GetAttribute("Network"), nil)
		for _, p in { pole, pole2 } do
			T.eq(p.Model:GetAttribute("Network"), "5,5", "pole network")
			T.eq(p.Model:GetAttribute("PowerSupply"), 15, "pole supply")
			T.eq(p.Model:GetAttribute("PowerDemand"), 20, "pole demand")
		end
		T.eq(pole.Model:GetAttribute("Links"), "9,5", "linked pole's cell")
		T.eq(pole2.Model:GetAttribute("Links"), "5,5", "listed on both poles")
		local feeds = PowerLogic.decodeCells(pole.Model:GetAttribute("Feeds"))
		T.eq(#feeds + #PowerLogic.decodeCells(pole2.Model:GetAttribute("Feeds")), 2, "panel and furnace fed once")
		T.eq(pole.Model:GetAttribute("Feeds"), "2,5;6,7", "the first pole feeds both (nearest)")
		T.eq(pole2.Model:GetAttribute("Feeds"), "", "nothing left for the second")
		-- speeds through the modifier
		T.near(PowerService.speedOf(blast), 0.9, 1e-9, "speedOf")
		T.eq(PowerService.speedOf(sell), 1, "no power needed")
		T.eq(PowerService.speedOf(panel), 1, "generators are not slowed")
		-- the layout changes: a turbine joins, the furnace goes to full speed
		w.add("WindTurbine", 2, 2)
		PowerService._test.recompute(w.player)
		T.eq(m:GetAttribute("PowerSpeed"), 1, "55 for 20")
		T.eq(pole.Model:GetAttribute("PowerSupply"), 55)
		T.eq(PowerService.speedOf(blast), 1)
		-- the poles go: no network, slow
		table.remove(w.machines, table.find(w.machines, pole))
		table.remove(w.machines, table.find(w.machines, pole2))
		PowerService._test.recompute(w.player)
		T.eq(m:GetAttribute("PowerSpeed"), UNPOWERED)
		T.eq(m:GetAttribute("Powered"), false)
		T.eq(m:GetAttribute("Network"), "")
		T.eq(PowerService.speedOf(blast), UNPOWERED)
		T.eq(w.changed, 0, "attributes are not save data")
	end)

	withWorld("PowerService: a machine placed this frame computes at once", function(w)
		w.add("PowerPole", 5, 5)
		w.add("WindTurbine", 2, 5)
		PowerService._test.recompute(w.player)
		local crusher = w.add("Polisher", 6, 5)
		T.eq(PowerService.resultOf(crusher), nil, "not computed yet")
		T.eq(PowerService.speedOf(crusher), 1, "computed on the spot: 40 for 12")
		T.eq(crusher.Model:GetAttribute("PowerSpeed"), 1)
		local far = w.add("Polisher", 0, 11)
		T.eq(PowerService.speedOf(far), UNPOWERED, "no pole near")
		far.Removed = true
		local ghost = w.add("BrickFurnace", 10, 10)
		ghost.Removed = true
		T.eq(PowerService.speedOf(ghost), UNPOWERED, "a removed machine never computes")
	end)

	withWorld("PowerService: a rebuilt model gets its attributes back at once", function(w)
		local pole = w.add("PowerPole", 5, 5)
		local turbine = w.add("WindTurbine", 2, 5)
		PowerService._test.recompute(w.player)
		-- MachineService.refreshType: same entry, new model
		local old = turbine.Model
		turbine.Model = Instance.new("Model")
		PowerService._test.spawned(turbine)
		T.eq(turbine.Model:GetAttribute("PowerOut"), 40, "cached attributes on the new model")
		T.eq(turbine.Model:GetAttribute("Network"), "5,5")
		T.truthy(old ~= turbine.Model)
		-- the Speed level went up meanwhile: next frame's compute has it
		w.data.MachineUpgrades.WindTurbine = { Speed = 1 }
		waitUntil(function()
			return turbine.Model:GetAttribute("PowerOut") == 50
		end)
		T.eq(turbine.Model:GetAttribute("PowerOut"), 50, "fresh compute next frame")
		T.eq(pole.Model:GetAttribute("PowerSupply"), 50)
	end)

	withWorld("PowerService: generator upgrades in the Tech shop recompute", function(w)
		local pole = w.add("PowerPole", 5, 5)
		local turbine = w.add("WindTurbine", 2, 5)
		w.add("AlloyFurnace", 6, 5)
		PowerService._test.recompute(w.player)
		T.eq(pole.Model:GetAttribute("PowerSupply"), 40)
		w.data.MachineUpgrades.WindTurbine = { Speed = 2 }
		PowerService._test.bought(w.player, {
			Item = "Upgrade:WindTurbine:Speed",
			Kind = "Upgrade",
			Machine = "WindTurbine",
			Upgrade = "Speed",
			Level = 2,
			Count = 1,
			Price = 1,
		})
		T.eq(turbine.Model:GetAttribute("PowerOut"), 40, "not in the same step")
		waitUntil(function()
			return turbine.Model:GetAttribute("PowerOut") == 60
		end)
		T.eq(turbine.Model:GetAttribute("PowerOut"), 60, "40 x 1.5")
		T.eq(pole.Model:GetAttribute("PowerSupply"), 60)
		-- buys that don't touch power don't compute
		w.data.MachineUpgrades.WindTurbine = { Speed = 3 }
		PowerService._test.bought(
			w.player,
			{ Item = "Upgrade:Crusher:Speed", Kind = "Upgrade", Machine = "Crusher", Upgrade = "Speed", Level = 1, Count = 1, Price = 1 }
		)
		PowerService._test.bought(w.player, { Item = "WindTurbine", Kind = "Machine", Machine = "WindTurbine", Count = 1, Price = 1 })
		PowerService._test.bought(w.player, { Item = "Bellows", Kind = "Bellows", Level = 1, Count = 1, Price = 1 })
		task.wait()
		T.eq(turbine.Model:GetAttribute("PowerOut"), 60, "unchanged")
		-- many asks in one frame compute once
		PowerService._test.schedule(w.player)
		PowerService._test.schedule(w.player)
		waitUntil(function()
			return turbine.Model:GetAttribute("PowerOut") == 70
		end)
		T.eq(turbine.Model:GetAttribute("PowerOut"), 70, "scheduled compute ran")
	end)

	withWorld("PowerService: init wires the layout, the shop, the speed modifier and the power models", function(w)
		local registered, modifiers, layouts, boughts = {}, {}, {}, {}
		w.patch(MachineService, "register", function(id, behaviour)
			registered[id] = behaviour
		end)
		w.patch(MachineService, "addSpeedModifier", function(fn)
			table.insert(modifiers, fn)
		end)
		w.patch(MachineService, "onLayoutChanged", function(fn)
			table.insert(layouts, fn)
		end)
		w.patch(ShopService, "onBought", function(fn)
			table.insert(boughts, fn)
		end)
		PowerService.init()
		for _, info in MachineData.List do
			local kind = PowerLogic.kindOf(info)
			if info.Retired or kind == "Other" then
				T.eq(registered[info.Id], nil, info.Id .. " not registered")
			else
				T.truthy(registered[info.Id] and registered[info.Id].spawned, info.Id .. " spawned hook")
				T.eq(registered[info.Id].canAccept, nil, info.Id .. " takes no items through power")
			end
		end
		T.eq(#modifiers, 1, "one speed modifier")
		T.eq(#layouts, 1, "one layout listener")
		T.eq(#boughts, 1, "one shop listener")
		local crusher = w.add("Polisher", 6, 5)
		w.add("PowerPole", 5, 5)
		w.add("SolarPanel", 2, 5)
		layouts[1](w.player, 1)
		T.near(crusher.Model:GetAttribute("PowerSpeed"), 1, 1e-9, "layout listener computes")
		T.eq(modifiers[1](crusher), 1, "the modifier is speedOf")
	end)

	---------------------------------------------------------------- PowerService on the real MachineService

	T.test("PowerService: real MachineService spawn -> attributes and speedFactor", function()
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = plotModel
		local player = fakePlayer(302)
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
		local data: any = deepCopy(DataTemplate)
		data.StarterKitGiven = true
		data.MachineInventory = {}
		data.MachineUpgrades = { SolarPanel = { Speed = 1 } }
		data.PlacedMachines = {
			{ Id = "PowerPole", X = 5, Z = 5, R = 0 },
			{ Id = "SolarPanel", X = 2, Z = 5, R = 0 }, -- 18.75
			{ Id = "BrickFurnace", X = 6, Z = 6, R = 0 }, -- 10
			{ Id = "RobotArm", X = 9, Z = 9, R = 0 }, -- 4, out of reach (4 cells)
		}
		local modifiers = {}
		patch(DataService, "get", function(p)
			return if p == player then data else nil
		end)
		patch(DataService, "changed", function() end)
		patch(DataService, "isInMemory", function()
			return false
		end)
		patch(PlotService, "plotOf", function(p)
			return if p == player then 3 else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == 3 then player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == 3 then plotModel else nil
		end)
		patch(Net, "fire", function() end)
		patch(ItemService, "looseCount", function()
			return 0
		end)
		patch(RunService, "IsStudio", function()
			return false
		end)
		patch(MachineService, "addSpeedModifier", function(fn)
			table.insert(modifiers, fn)
		end)
		patch(ShopService, "onBought", function() end)
		MachineService._test.reset()
		PowerService._test.reset()
		local ok, err = pcall(function()
			PowerService.init()
			MachineService._test.spawnAll(player, 3)
			local byId = {}
			waitUntil(function()
				for _, machine in MachineService.ofPlot(3) do
					byId[machine.Id] = machine
				end
				local furnace = byId.BrickFurnace
				return furnace ~= nil and furnace.Model:GetAttribute("PowerSpeed") ~= nil
			end)
			local furnace, crusher = byId.BrickFurnace, byId.RobotArm
			T.eq(furnace.Model:GetAttribute("PowerSpeed"), 1, "18.75 for 10")
			T.eq(furnace.Model:GetAttribute("Powered"), true)
			T.eq(crusher.Model:GetAttribute("PowerSpeed"), UNPOWERED, "out of reach")
			T.eq(byId.SolarPanel.Model:GetAttribute("PowerOut"), 18.75, "Speed 1 panel")
			T.eq(byId.PowerPole.Model:GetAttribute("Feeds"), "2,5;6,6")
			T.eq(byId.PowerPole.Model:GetAttribute("PowerDemand"), 10)
			-- MachineService.speedFactor runs the modifier (captured here so it doesn't outlive the test)
			T.eq(#modifiers, 1)
			T.eq(modifiers[1](crusher), UNPOWERED)
			-- move the crusher into reach: the layout listener recomputes
			T.truthy(MachineService.move(crusher, 7, 3, 0), "moved")
			waitUntil(function()
				return crusher.Model:GetAttribute("PowerSpeed") == 1
			end)
			T.eq(crusher.Model:GetAttribute("PowerSpeed"), 1, "now sharing 18.75 for 14")
			T.eq(byId.PowerPole.Model:GetAttribute("PowerDemand"), 14)
			T.eq(modifiers[1](crusher), 1)
			-- the panel goes back into the Build menu: 0 for 18
			T.truthy(MachineService.pickup(byId.SolarPanel), "picked up")
			waitUntil(function()
				return crusher.Model:GetAttribute("PowerSpeed") == UNPOWERED
			end)
			T.eq(crusher.Model:GetAttribute("PowerSpeed"), UNPOWERED, "no generator left")
			T.eq(crusher.Model:GetAttribute("Powered"), false)
			T.eq(modifiers[1](crusher), UNPOWERED)
			-- a model rebuilt for an upgrade look keeps its attributes
			MachineService.refreshType(player, "BrickFurnace")
			local rebuilt
			for _, machine in MachineService.ofPlot(3) do
				if machine.Id == "BrickFurnace" then
					rebuilt = machine
				end
			end
			T.truthy(rebuilt and rebuilt.Model ~= furnace.Model, "new model")
			T.eq(rebuilt.Model:GetAttribute("PowerSpeed"), UNPOWERED, "attributes at once")
			T.eq(rebuilt.Model:GetAttribute("Network"), "5,5")
			task.wait()
		end)
		MachineService._test.reset()
		PowerService._test.reset()
		for i = #saved, 1, -1 do
			rawset(saved[i][1], saved[i][2], saved[i][3])
		end
		if not ok then
			error(err, 0)
		end
	end)

	---------------------------------------------------------------- PowerController cables

	local function placeModel(id: string, x: number, z: number, r: number?): any
		local model = MachineBuilder.build(id)
		model:PivotTo(Grid.localCFrame(id, x, z, r or 0))
		model:SetAttribute("GridX", x)
		model:SetAttribute("GridZ", z)
		model:SetAttribute("Rotation", r or 0)
		return model
	end

	local function count(list: { any }, class: string): number
		local n = 0
		for _, instance in list do
			if instance:IsA(class) then
				n += 1
			end
		end
		return n
	end

	local function worldOf(attachment: any): any
		return (attachment.Parent.CFrame * attachment.CFrame).Position
	end

	T.test("PowerController: cables between linked poles and to the machines they feed", function()
		local poleA = placeModel("PowerPole", 2, 2)
		local poleB = placeModel("PowerPole", 6, 2)
		local furnace = placeModel("ClayFurnace", 3, 4)
		local turbine = placeModel("WindTurbine", 7, 3)
		poleA:SetAttribute("Links", "6,2")
		poleB:SetAttribute("Links", "2,2") -- the same link: drawn once
		poleA:SetAttribute("Feeds", "3,4;9,9") -- 9,9: not streamed in, skipped
		poleB:SetAttribute("Feeds", "7,3")
		local made = PowerController.drawCables({ poleA, poleB, furnace, turbine })
		T.eq(count(made, "Beam"), 3, "1 link + 2 feeds")
		for _, instance in made do
			if instance:IsA("Beam") then
				local a0, a1 = instance.Attachment0, instance.Attachment1
				T.truthy(a0 and a1, "both ends")
				T.eq(instance.Name, PowerController.CableName)
				T.truthy(instance.CurveSize0 > 0 and instance.CurveSize1 > 0, "sags")
				T.near(instance.Width0, PowerController.CableWidth, 1e-6)
				T.truthy(instance.FaceCamera, "a round-looking ribbon")
				-- the curve axes: down at the pole, up at the far end (the middle hangs low)
				T.near(a0.CFrame.XVector.Y, -1, 1e-6, "pole end axis down")
				T.near(a1.CFrame.XVector.Y, 1, 1e-6, "far end axis up")
				T.truthy(a0.Parent == poleA.PrimaryPart or a0.Parent == poleB.PrimaryPart, "starts on a pole")
				T.truthy(instance.Parent == a0.Parent, "lives on the pole's Base")
				local length = (worldOf(a0) - worldOf(a1)).Magnitude
				T.near(instance.CurveSize0 * 0.75, PowerController.sagOf(length), 1e-6, "sag from the length")
			end
		end
		-- the link runs between the facing insulators of the two poles
		local link
		for _, instance in made do
			if instance:IsA("Beam") and instance.Attachment1.Parent == poleB.PrimaryPart then
				link = instance
			end
		end
		T.truthy(link, "pole A -> pole B")
		local fromX, toX = worldOf(link.Attachment0).X, worldOf(link.Attachment1).X
		T.truthy(fromX > poleA.PrimaryPart.CFrame.Position.X, "A's insulator on B's side")
		T.truthy(toX < poleB.PrimaryPart.CFrame.Position.X, "B's insulator on A's side")
		-- feeds end on the machine's top, never above the insulator
		for _, instance in made do
			if instance:IsA("Beam") and instance.Attachment1.Parent == furnace.PrimaryPart then
				local top = worldOf(instance.Attachment1).Y
				local status = furnace.PrimaryPart:FindFirstChild("Status")
				local modelTop = (furnace.PrimaryPart.CFrame * status.CFrame).Position.Y - 1.5
				local limit = worldOf(instance.Attachment0).Y - 0.4
				T.near(top, math.min(modelTop, limit), 1e-4, "on the furnace's top (or below the insulator)")
				T.near(worldOf(instance.Attachment1).X, furnace.PrimaryPart.CFrame.Position.X, 1e-4, "over its middle")
			end
			if instance:IsA("Beam") and instance.Attachment1.Parent == turbine.PrimaryPart then
				-- (Lune keeps CFrames in 32-bit floats)
				T.truthy(worldOf(instance.Attachment1).Y <= worldOf(instance.Attachment0).Y - 0.4 + 1e-4, "tall turbine: in its side")
			end
		end
		T.truthy(count(made, "Attachment") <= 5, "attachments shared per insulator")
		PowerController.clearCables(made)
		T.eq(#made, 0, "cleared")
		for _, model in { poleA, poleB, furnace, turbine } do
			for _, d in model:GetDescendants() do
				T.falsy(d:IsA("Beam"), "no beams left")
				T.falsy(d:IsA("Attachment") and d.Name:match("^Power"), "no cable attachments left")
			end
		end
		-- no attributes yet, or a rotated machine: nothing breaks
		local bare = placeModel("PowerPole", 0, 0)
		local turned = placeModel("AlloyFurnace", 1, 1, 1)
		bare:SetAttribute("Feeds", "1,1")
		local again = PowerController.drawCables({ bare, turned, placeModel("PowerPole", 11, 11) })
		T.eq(count(again, "Beam"), 1, "the turned furnace is fed")
		PowerController.clearCables(again)
		T.eq(#PowerController.drawCables({ furnace }), 0, "no poles, no cables")
	end)
end
