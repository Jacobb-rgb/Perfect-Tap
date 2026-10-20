-- Platforms, the Belt Lift and the Slide (docs/plans/PLATFORMS_PLAN.md):
-- the level rules in Placement (deck cells, belts under a deck, the Lift /
-- Slide edges, DeckInUse, sanitize), the belt rules by level
-- (ConveyorLogic), Migrations of Entry.L, the models and a full plot of
-- platforms inside the budget, and the runtime: MachineService's index by
-- level, deck spawning, emits on a deck, the Lift's and Slide's belt
-- velocity along their slopes, jam nudges along a slope and the Lift's
-- feeder box at deck height. MachineService, ConveyorService and items are
-- real; players, saves, plots and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Placement = Loader.requirePath("ReplicatedStorage.Shared.Machines.Placement")
	local ConveyorLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.ConveyorLogic")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
	local ConveyorService = Loader.requirePath("ServerScriptService.Server.Services.ConveyorService")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local CELLS = GameConfig.PlotCells
	local CELL = GameConfig.CellSize
	local DECK = MachineData.DeckHeight

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

	local function deepEqual(a: any, b: any): boolean
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	local function e(id: string, x: number, z: number, r: number?, level: number?): any
		return { Id = id, X = x, Z = z, R = r or 0, L = level }
	end

	local function code(entries: { any }, id: string, x: number, z: number, r: number, level: number?, ignore: any?): string?
		local ok, why = Placement.validate(entries, id, x, z, r, nil, ignore, level)
		return if ok then "ok" else why
	end

	local function parts(model: any): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	---------------------------------------------------------------- data

	T.test("Platforms: MachineData entries (Platform, Belt Lift, Slide) and the reason texts", function()
		local platform = MachineData.ById.Platform
		T.truthy(platform, "Platform")
		T.eq(platform.Size[1], 2)
		T.eq(platform.Size[2], 2)
		T.eq(platform.Category, "Logistics")
		T.eq(platform.Behaviour, "Platform")
		T.truthy(platform.NoIntake, "no hopper")
		T.falsy(platform.IsConveyor or platform.SlotFree, "a machine slot")
		T.truthy(platform.Price >= 1000 and platform.Price <= 5000, "an early price")
		for _, id in { "BeltLift", "Slide" } do
			local info = MachineData.ById[id]
			T.truthy(info and info.IsConveyor, id .. " is a belt")
			T.eq(info.Size[1], 1, id)
			T.eq(info.Size[2], 3, id)
			T.eq(info.Price, MachineData.ById.ExpressConveyor.Price, id .. " priced like the Express Conveyor")
			T.truthy(table.find(MachineData.Buildable, info), id .. " is sold")
		end
		T.eq(MachineData.ById.BeltLift.Slope, "Up")
		T.eq(MachineData.ById.Slide.Slope, "Down")
		T.eq(DECK, 5, "the deck top at the Belt Lift's rise")
		for _, reason in { "NoDeck", "UnderDeck", "DeckEdge", "DeckInUse" } do
			T.truthy(type(Placement.Reasons[reason]) == "string" and #Placement.Reasons[reason] > 0, reason)
		end
		-- slots: a platform takes a machine slot, the slopes belt slots
		local machines, conveyors = Placement.counts({ e("Platform", 0, 0), e("BeltLift", 3, 0), e("Slide", 5, 0) })
		T.eq(machines, 1, "platform: machine slot")
		T.eq(conveyors, 2, "lift + slide: belt slots")
	end)

	---------------------------------------------------------------- Placement

	T.test("Platforms: deck cells take level 1 entries, side by side platforms make one deck", function()
		local layout = { e("Platform", 4, 4) }
		T.eq(code(layout, "Conveyor", 4, 4, 0, 1), "ok", "belt on the deck")
		T.eq(code(layout, "ClayFurnace", 4, 4, 0, 1), "ok", "2x2 machine on the whole deck")
		T.eq(code(layout, "Conveyor", 6, 4, 0, 1), "NoDeck", "no deck there")
		T.eq(code(layout, "ClayFurnace", 5, 5, 0, 1), "NoDeck", "half on the deck")
		T.eq(code(layout, "CleaningStation", 4, 4, 0, 1), "NoDeck", "3x2 on one deck")
		table.insert(layout, e("Platform", 6, 4))
		T.eq(code(layout, "ClayFurnace", 5, 4, 0, 1), "ok", "across two decks")
		T.eq(code(layout, "CleaningStation", 4, 4, 0, 1), "ok", "3x2 across two decks")
		-- occupancy is keyed by cell and level
		table.insert(layout, e("Conveyor", 4, 4, 0, 1))
		T.eq(code(layout, "Conveyor", 4, 4, 1, 1), "Overlap", "deck cell taken")
		T.eq(code(layout, "Conveyor", 4, 4, 1, 0), "ok", "the ground under it is free for a belt")
		local occupied = Placement.occupancy(layout)
		T.truthy(occupied[Placement.key(4, 4, 1)] == layout[3], "deck key")
		T.truthy(occupied[Placement.key(4, 4, 0)] == layout[1], "ground key: the platform's legs")
		T.eq(Placement.key(4, 4, 0), Grid.key(4, 4), "ground keys are Grid keys")
		T.truthy(Placement.key(4, 4, 1) >= CELLS * CELLS, "deck keys after every ground key")
		-- platforms and slopes never go on a deck; junk levels are refused
		T.eq(code(layout, "Platform", 4, 4, 0, 1), "BadInput", "platform on a deck")
		T.eq(code(layout, "BeltLift", 4, 4, 0, 1), "BadInput", "lift on a deck")
		T.eq(code(layout, "Conveyor", 5, 5, 0, 2), "BadInput", "level 2")
		T.eq(code(layout, "Conveyor", 5, 5, 0, 0.5), "BadInput", "level 0.5")
	end)

	T.test("Platforms: flat belts run under a deck, other ground machines don't", function()
		local layout = { e("Platform", 4, 4) }
		T.eq(code(layout, "Conveyor", 4, 4, 1), "ok", "belt under")
		T.eq(code(layout, "ExpressConveyor", 5, 5, 2), "ok", "express under")
		T.eq(code(layout, "ClayFurnace", 4, 4, 0), "UnderDeck", "furnace under")
		T.eq(code(layout, "RobotArm", 5, 4, 0), "UnderDeck", "arm under")
		T.eq(code(layout, "PowerPole", 4, 5, 0), "UnderDeck", "pole under")
		T.eq(code(layout, "Platform", 5, 5, 0), "Overlap", "platforms don't overlap")
		-- a platform goes over belts, not over machines
		local belts = { e("Conveyor", 4, 4, 1), e("Conveyor", 5, 4, 1) }
		T.eq(code(belts, "Platform", 4, 4, 0), "ok", "over belts")
		local furnace = { e("ClayFurnace", 5, 5) }
		T.eq(code(furnace, "Platform", 4, 4, 0), "Overlap", "over a furnace")
		local lift = { e("Platform", 0, 0), e("BeltLift", 0, 2) }
		T.eq(code(lift, "Platform", 0, 2, 0), "Overlap", "over a lift (no belt under a deck)")
		-- a belt under the deck keeps its ground cell in the occupancy map
		local under = { e("Platform", 4, 4), e("Conveyor", 4, 4, 1) }
		T.truthy(Placement.occupancy(under)[Grid.key(4, 4)] == under[2], "the belt, not the legs")
		T.truthy(Placement.decks(under)[Grid.key(4, 4)] == under[1], "decks() has the platform")
		-- chutes: only flat belts (no platform, no lift on a chute cell)
		local cx, cz = 3, CELLS - 1
		T.eq(code({}, "Platform", cx - 1, cz - 1, 0), "Chute", "platform over a chute")
		T.eq(code({}, "Conveyor", cx, cz, 0), "ok", "belt on a chute")
	end)

	T.test("Platforms: the Belt Lift's top end (front) and the Slide's (back) must touch a deck", function()
		local layout = { e("Platform", 4, 4) } -- deck cells x 4-5, z 4-5
		-- r0: front toward -Z, footprint x, z..z+2
		T.eq(code(layout, "BeltLift", 4, 6, 0), "ok", "lift with its front cell (4,5) on the deck")
		T.eq(code(layout, "BeltLift", 4, 7, 0), "DeckEdge", "one cell short")
		T.eq(code(layout, "BeltLift", 4, 5, 0), "UnderDeck", "a lift stands outside every deck")
		T.eq(code(layout, "BeltLift", 4, 1, 2), "ok", "r2: front toward +Z onto (4,4)")
		T.eq(code(layout, "BeltLift", 1, 4, 1), "ok", "r1: front toward +X onto (4,4)")
		T.eq(code(layout, "BeltLift", 6, 5, 3), "ok", "r3: front toward -X onto (5,5)")
		T.eq(code(layout, "BeltLift", 4, 1, 0), "DeckEdge", "facing away from the deck")
		T.eq(code(layout, "Slide", 4, 1, 0), "ok", "slide with its back cell (4,4) on the deck")
		T.eq(code(layout, "Slide", 4, 0, 0), "DeckEdge", "slide one short")
		T.eq(code(layout, "Slide", 4, 6, 2), "ok", "r2: back toward -Z onto (4,5)")
		T.eq(code(layout, "Slide", 4, 6, 0), "DeckEdge", "slide facing the wrong way")
		local ex, ez = Placement.deckEdgeCell("BeltLift", 4, 6, 0)
		T.truthy(ex == 4 and ez == 5, "lift edge cell")
		ex, ez = Placement.deckEdgeCell("Slide", 4, 1, 0)
		T.truthy(ex == 4 and ez == 4, "slide edge cell")
		T.eq(Placement.deckEdgeCell("Conveyor", 4, 1, 0), nil, "a flat belt has none")
		-- no deck at all
		T.eq(code({}, "BeltLift", 4, 6, 0), "DeckEdge", "no platform")
	end)

	T.test("Platforms: a used deck can't be packed up or moved away (DeckInUse)", function()
		local platform = e("Platform", 4, 4)
		local onDeck = e("Conveyor", 5, 5, 0, 1)
		local layout = { platform, onDeck }
		T.truthy(Placement.deckInUse(layout, platform), "a belt on it")
		T.eq(select(2, Placement.canPickup(layout, platform)), "DeckInUse", "pickup refused")
		T.truthy(Placement.canPickup(layout, onDeck), "the belt itself can go")
		T.eq(code(layout, "Platform", 6, 6, 0, 0, platform), "DeckInUse", "moving it away")
		T.eq(code(layout, "Platform", 4, 4, 1, 0, platform), "ok", "turning it in place")
		local data = { PlacedMachines = layout, MachineInventory = {} }
		local packed = Placement.commitPickup(data, platform)
		T.falsy(packed, "commitPickup refuses too")
		T.eq(#data.PlacedMachines, 2, "nothing changed")
		-- a Lift reaching the deck uses it as well
		local lifted = { platform, e("BeltLift", 4, 6, 0) }
		T.truthy(Placement.deckInUse(lifted, platform), "a lift's top end")
		local slid = { platform, e("Slide", 4, 1, 0) }
		T.truthy(Placement.deckInUse(slid, platform), "a slide's top end")
		-- belts under it don't
		local under = { platform, e("Conveyor", 4, 4, 1) }
		T.falsy(Placement.deckInUse(under, platform), "a belt under it")
		T.eq(code(under, "Platform", 8, 8, 0, 0, platform), "ok", "moves off its belts")
		T.falsy(Placement.deckInUse(layout, onDeck), "not a platform")
	end)

	T.test("Platforms: commits carry L only on a deck and keep the ledger", function()
		local data = { PlacedMachines = {}, MachineInventory = { Platform = 1, Conveyor = 3, ClayFurnace = 1 } }
		local limits = Placement.limits(0, false)
		local platform = Placement.commitPlace(data, "Platform", 4, 4, 0, limits)
		T.truthy(platform, "platform placed")
		T.eq(platform.L, nil, "ground: no L")
		local belt = Placement.commitPlace(data, "Conveyor", 4, 4, 0, limits, 1)
		T.truthy(belt and belt.L == 1, "deck belt: L = 1")
		local _, why = Placement.commitPlace(data, "ClayFurnace", 4, 4, 0, limits, 1)
		T.eq(why, "Overlap", "deck cell taken")
		T.eq(data.MachineInventory.ClayFurnace, 1, "a refused place costs nothing")
		local under = Placement.commitPlace(data, "Conveyor", 4, 4, 0, limits, 0)
		T.truthy(under and under.L == nil, "belt under the deck: no L")
		-- down to the ground and up again
		T.truthy(Placement.commitMove(data, belt, 8, 8, 0), "moved down")
		T.eq(belt.L, nil, "ground again")
		T.truthy(Placement.commitMove(data, belt, 5, 5, 0, 1), "moved up")
		T.eq(belt.L, 1, "deck again")
		local _, moveWhy = Placement.commitMove(data, belt, 9, 9, 0, 1)
		T.eq(moveWhy, "NoDeck", "no deck there")
		T.truthy(belt.X == 5 and belt.L == 1, "a refused move changes nothing")
		T.truthy(Placement.commitPickup(data, belt), "deck belt packed up")
		T.truthy(Placement.commitPickup(data, platform), "then the platform")
		T.eq(data.MachineInventory.Platform, 1, "ledger: platform back")
		T.eq(data.MachineInventory.Conveyor, 2, "ledger: belt back (one still placed)")
	end)

	T.test("Platforms: sanitize drops junk levels and sends lost deck entries back", function()
		local data = {
			PlacedMachines = {
				e("Conveyor", 0, 0, 0, "deck" :: any), -- junk: on the ground
				e("Conveyor", 1, 0, 0, 1.5),
				e("Conveyor", 2, 0, 0, -1),
				e("Conveyor", 3, 0, 0, 0),
				e("Conveyor", 4, 0, 0, 2), -- a level this server doesn't know
				e("ClayFurnace", 8, 8, 0, 1), -- its platform is gone
				e("Conveyor", 6, 7, 0, 1), -- deck entry before its platform in the list: fine
				e("Platform", 6, 6),
				e("Conveyor", 6, 7, 1, 1), -- the same deck cell twice
				e("BeltLift", 0, 4, 0), -- its top end reaches nothing
				e("Slide", 7, 3, 0), -- its back cell (7,6) is on the deck
				e("ClayFurnace", 2, 2), -- the first one wins the ground...
				e("Platform", 2, 2), -- ... so this platform is displaced
				e("Conveyor", 2, 2, 0, 1), -- and so is the belt on it
			},
			MachineInventory = {},
			Storage = {},
		}
		local list = data.PlacedMachines
		local keep = { list[1], list[2], list[3], list[4], list[7], list[8], list[11], list[12] }
		local displaced, reasons = Placement.sanitize(data)
		T.eq(#data.PlacedMachines, #keep, "kept count")
		for i, entry in keep do
			T.truthy(data.PlacedMachines[i] == entry, "kept in saved order " .. i)
		end
		for i = 1, 4 do
			T.eq(data.PlacedMachines[i].L, nil, "junk level dropped " .. i)
		end
		T.eq(data.PlacedMachines[5].L, 1, "a real deck belt keeps L")
		local why: { [string]: number } = {}
		for i, id in displaced do
			local key = id .. ":" .. reasons[i]
			why[key] = (why[key] or 0) + 1
		end
		T.eq(why["Conveyor:BadInput"], 1, "unknown level")
		T.eq(why["ClayFurnace:NoDeck"], 1, "no platform under it")
		T.eq(why["Conveyor:Overlap"], 1, "deck cell twice")
		T.eq(why["BeltLift:DeckEdge"], 1, "lift without a deck")
		T.eq(why["Platform:Overlap"], 1, "platform over a furnace")
		T.eq(why["Conveyor:NoDeck"], 1, "its deck went with it")
		T.eq(data.MachineInventory.ClayFurnace, 1, "back in the inventory")
		T.eq(data.MachineInventory.Platform, 1)
		T.eq(data.MachineInventory.BeltLift, 1)
		T.eq(data.MachineInventory.Conveyor, 3)
		-- running it again changes nothing
		local again = deepCopy(data)
		Placement.sanitize(again)
		T.truthy(deepEqual(again, data), "idempotent")
	end)

	T.test("Platforms: saves without L load unchanged", function()
		local data = {
			PlacedMachines = {
				e("CleaningStation", 4, 4),
				e("ClayFurnace", 8, 4),
				e("Conveyor", 0, 0, 1),
				e("ExpressConveyor", 1, 0, 1),
				{ Id = "FutureMachine", X = 0, Z = 11, R = 0 },
			},
			MachineInventory = { Crusher = 2 },
			Storage = {},
			Coins = 10,
		}
		data.PlacedMachines[2].In = { { K = "Clean", O = "Copper", G = "Rough" } }
		local before = deepCopy(data)
		Placement.sanitize(data)
		T.truthy(deepEqual(data, before), "sanitize: unchanged")
		local save = deepCopy(DataTemplate)
		save.PlacedMachines = deepCopy(before.PlacedMachines)
		Migrations.run(save, 1000)
		for _, entry in save.PlacedMachines do
			T.eq(entry.L, nil, entry.Id .. " gets no L")
		end
		T.truthy(deepEqual(save.PlacedMachines, before.PlacedMachines), "migrations: unchanged")
		-- Migrations keeps whole levels, drops junk and 0
		local levels = deepCopy(DataTemplate)
		levels.PlacedMachines = {
			e("Conveyor", 0, 0, 0, 1),
			e("Conveyor", 1, 0, 0, 0),
			e("Conveyor", 2, 0, 0, "x" :: any),
			e("Conveyor", 3, 0, 0, 1.5),
			e("Conveyor", 4, 0, 0, 3), -- a newer build's level is kept (sanitize decides)
			e("Conveyor", 5, 0, 0, 0 / 0),
		}
		Migrations.run(levels, 1000)
		local got = {}
		for _, entry in levels.PlacedMachines do
			got[entry.X] = entry.L
		end
		T.eq(got[0], 1)
		T.eq(got[1], nil)
		T.eq(got[2], nil)
		T.eq(got[3], nil)
		T.eq(got[4], 3)
		T.eq(got[5], nil)
		local copy = deepCopy(levels)
		Migrations.run(copy, 1000)
		T.truthy(deepEqual(copy.PlacedMachines, levels.PlacedMachines), "idempotent")
	end)

	---------------------------------------------------------------- belts by level

	T.test("Platforms: belts deliver on their own level; the Lift up onto the deck", function()
		T.truthy(select(3, ConveyorLogic.frontOf(e("BeltLift", 4, 6, 0))) == 1, "lift front: deck")
		T.truthy(select(3, ConveyorLogic.frontOf(e("Slide", 4, 1, 0))) == 0, "slide front: ground")
		T.truthy(select(3, ConveyorLogic.frontOf(e("Conveyor", 4, 4, 0, 1))) == 1, "deck belt: deck")
		local fx, fz = ConveyorLogic.frontOf(e("BeltLift", 4, 6, 0))
		T.truthy(fx == 4 and fz == 5, "lift front cell")
		local layout = {
			e("Platform", 4, 4),
			e("Platform", 6, 4),
			e("ClayFurnace", 6, 4, 0, 1), -- deck furnace over x 6-7, z 4-5
			e("Conveyor", 5, 4, 1, 1), -- deck belt into the deck furnace's side
			e("Conveyor", 5, 5, 1, 0), -- ground belt under the deck, toward (6,5): legs only there
			e("BeltLift", 4, 6, 0), -- up onto (4,5)
			e("Conveyor", 4, 5, 1, 1), -- deck belt the lift feeds from its side
		}
		local feeders = ConveyorLogic.feeders(layout)
		T.eq(#feeders, 1, "one feeder")
		T.truthy(feeders[1].Conveyor == layout[4] and feeders[1].Target == layout[3], "deck belt -> deck furnace")
		local sides = ConveyorLogic.openSides(layout)
		local s = sides[layout[7]]
		T.truthy(s, "the deck belt has sides")
		-- the belt at (4,5) runs +X (r1): its right is +Z, where the lift comes from
		T.truthy(s.Right and not s.Left, "the lift opens the side it arrives at")
		T.eq(sides[layout[6]], nil, "slopes have no side rails")
		T.falsy(sides[layout[5]].Left or sides[layout[5]].Right, "the ground belt sees nothing on the deck")
		-- a deck machine fed straight by the lift
		local direct = { e("Platform", 4, 4), e("SellBox", 4, 4, 0, 1), e("BeltLift", 4, 6, 0) }
		local f2 = ConveyorLogic.feeders(direct)
		T.truthy(#f2 == 1 and f2[1].Target == direct[2], "the lift feeds the deck Sell Box")
		-- belts on different levels never face each other
		T.eq(#ConveyorLogic.headOn({ e("Platform", 4, 4), e("Conveyor", 4, 4, 1, 1), e("Conveyor", 5, 4, 3, 0) }), 0, "no head-on")
	end)

	---------------------------------------------------------------- models

	T.test("Platforms: the platform model (style A, 17 parts) and the in-game slopes stay in their cells", function()
		local model = MachineBuilder.build("Platform")
		local list = parts(model)
		T.le(#list, 17, "platform parts")
		local deck = model:FindFirstChild("Deck")
		T.truthy(deck, "Deck top")
		T.near(deck.CFrame.Position.Y + deck.Size.Y / 2, DECK, 1e-4, "deck top at DeckHeight")
		T.eq(model:GetAttribute("MachineId"), "Platform")
		local legs = 0
		for _, part in list do
			T.truthy(part.Anchored, part.Name .. " anchored")
			local s = part.Size
			if s.X * s.Y * s.Z < 1 and part.Transparency < 1 then
				T.falsy(part.CastShadow, part.Name .. ": small parts cast no shadow")
			end
			if part.Name == "Leg" or part.Name == "Foot" then
				-- in the footprint's corners: only over a belt's outer rail (its last half
				-- stud), never over the belt surface items ride on
				local half = MachineData.ById.Platform.Size[1] * CELL / 2
				local p = part.CFrame.Position
				local radius = math.min(s.Y, s.Z) / 2
				T.truthy(math.abs(p.X) + radius <= half + 0.12 and math.abs(p.Z) + radius <= half + 0.12, part.Name .. " in the footprint")
				if part.Name == "Foot" then
					T.truthy(p.Y + s.X / 2 <= 0.31, "feet under a belt's surface")
				else
					T.truthy(math.abs(p.X) - radius >= half - 0.5 - 1e-3, "leg clear of the belts (x)")
					T.truthy(math.abs(p.Z) - radius >= half - 0.5 - 1e-3, "leg clear of the belts (z)")
					legs += 1
				end
			end
			-- nothing between the legs below the deck where belts and items pass
			local top = part.CFrame.Position.Y + s.Y / 2
			if part.Name ~= "Leg" and part.Name ~= "Foot" and part.Name ~= "Base" then
				T.truthy(part.CFrame.Position.Y - 0.5 > 3, part.Name .. " stays up under the deck (" .. top .. ")")
			end
		end
		T.eq(legs, 4, "four legs")
		for _, id in { "BeltLift", "Slide" } do
			local slope = MachineBuilder.build(id)
			local belt = slope:FindFirstChild("Belt")
			T.truthy(belt and belt:HasTag("ConveyorBelt"), id .. " Belt tagged")
			T.truthy(belt.CustomPhysicalProperties and belt.CustomPhysicalProperties.Friction >= 1, id .. " grippy belt")
			local look = belt.CFrame.LookVector
			T.truthy(look.Z < -0.8, id .. " runs toward the front")
			if id == "BeltLift" then
				T.truthy(look.Y > 0.3, "the lift rises")
			else
				T.truthy(look.Y < -0.3, "the slide falls")
			end
			T.le(#parts(slope), 60, id .. " parts")
			-- the high end's belt meets a deck belt's surface
			local top = -math.huge
			for _, part in parts(slope) do
				if part.Name == "Belt" then
					top = part.CFrame.Position.Y
				end
			end
			T.truthy(top > 2 and top < DECK, id .. " belt between the levels")
		end
	end)

	T.test("Platforms: a full plot of platforms (36) stays inside the budget", function()
		local placed = {}
		local refused = 0
		for z = 0, CELLS - 2, 2 do
			for x = 0, CELLS - 2, 2 do
				local ok, why = Placement.validate(placed, "Platform", x, z, 0)
				if ok then
					table.insert(placed, e("Platform", x, z))
				else
					T.eq(why, "Chute", `only chute cells refuse a platform ({x},{z})`)
					refused += 1
				end
			end
		end
		T.eq(#placed + refused, 36, "36 spots")
		T.eq(refused, 3, "the three chute cells")
		-- the parts of 36 platform models together
		local root = Instance.new("Model")
		local total, shadows = 0, 0
		for z = 0, CELLS - 2, 2 do
			for x = 0, CELLS - 2, 2 do
				local model = MachineBuilder.build("Platform")
				model:PivotTo(Grid.localCFrame("Platform", x, z, 0))
				model.Parent = root
				for _, part in parts(model) do
					total += 1
					if part.CastShadow then
						shadows += 1
					end
				end
			end
		end
		T.le(total, 36 * 17, "36 platforms: " .. total .. " parts")
		-- a plot's whole machine budget on a phone (22 machines x 70 parts) holds them easily
		T.le(total, 22 * 70, "inside the plot machine budget")
		T.le(shadows, 36 * 9, "only the big parts cast shadows")
	end)

	---------------------------------------------------------------- runtime

	local PLOT = 5
	local USER = 401

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
		local w: any = { notes = {}, ejects = {}, inserts = {} }
		w.plotModel = Instance.new("Model")
		local folder = Instance.new("Folder")
		folder.Name = "Machines"
		folder.Parent = w.plotModel
		w.player = fakePlayer(USER, "Builder")
		w.data = deepCopy(DataTemplate)
		w.data.StarterKitGiven = true
		w.data.MachineInventory = { Platform = 6, Conveyor = 10, BeltLift = 2, Slide = 2, ClayFurnace = 2, SellBox = 1, Splitter = 1 }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(ItemService, "onBase", function()
			return true
		end)
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
			return if id == PLOT then w.plotModel else nil
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids = (w.ids or 0) + 1
			return "platform-guid-" .. w.ids
		end)
		patch(ItemService, "eject", function(record, velocity)
			table.insert(w.ejects, { Record = record, Velocity = velocity })
		end)
		MachineService._test.reset()
		IntakeService._test.reset()
		ItemService._test.reset()
		ConveyorService._test.reset()
		for _, id in ConveyorService.beltIds() do
			MachineService.register(id, ConveyorService._test.behaviour)
		end
		-- stand-ins with an intake: every item is taken and logged
		for _, id in { "SellBox", "ClayFurnace" } do
			MachineService.register(id, {
				canAccept = function()
					return true, nil
				end,
				insert = function(m, d)
					table.insert(w.inserts, { Machine = m, Desc = d })
				end,
			})
		end
		MachineService._test.spawnAll(w.player, PLOT)
		w.restore = function()
			MachineService._test.reset()
			IntakeService._test.reset()
			ItemService._test.reset()
			ConveyorService._test.reset()
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

	local function place(w: any, id: string, x: number, z: number, r: number?, level: number?): any
		local m, why = MachineService.place(w.player, id, x, z, r or 0, level)
		assert(m, `place {id} at {x},{z} L{level or 0}: {why}`)
		return m
	end

	local function sameCFrame(a: any, b: any, label: string)
		local ac, bc = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do
			T.near(ac[i], bc[i], 1e-4, label .. " component " .. i)
		end
	end

	withWorld("Platforms: MachineService indexes by cell and level, deck machines spawn on the deck", function(w)
		local platform = place(w, "Platform", 4, 4)
		local under = place(w, "Conveyor", 4, 4, 1)
		local deckBelt = place(w, "Conveyor", 5, 5, 0, 1)
		local furnace = place(w, "ClayFurnace", 6, 4)
		T.eq(platform.L, 0)
		T.eq(deckBelt.L, 1, "machine level")
		T.eq(deckBelt.Model:GetAttribute("GridL"), 1, "GridL attribute")
		T.eq(under.Model:GetAttribute("GridL"), 0)
		sameCFrame(deckBelt.Model:GetPivot(), PlotService.footprintCFrame(PLOT, "Conveyor", 5, 5, 0, 1), "deck pivot")
		local ground = PlotService.footprintCFrame(PLOT, "Conveyor", 5, 5, 0)
		T.near(deckBelt.Model:GetPivot().Position.Y - ground.Position.Y, DECK, 1e-4, "DeckHeight up")
		-- atCell by level
		T.truthy(MachineService.atCell(PLOT, 4, 4) == under, "ground: the belt under the deck")
		T.truthy(MachineService.atCell(PLOT, 5, 4) == platform, "ground: the legs where no belt is")
		T.truthy(MachineService.atCell(PLOT, 5, 5, 1) == deckBelt, "deck: the deck belt")
		T.eq(MachineService.atCell(PLOT, 4, 4, 1), nil, "deck: a bare cell")
		T.eq(MachineService.atCell(PLOT, 6, 4, 1), nil, "no deck over the furnace")
		T.truthy(MachineService.atCell(PLOT, 6, 4, 0) == furnace, "furnace on the ground")
		T.truthy(MachineService.deckAt(PLOT, 5, 4) == platform, "deckAt")
		T.eq(MachineService.deckAt(PLOT, 6, 4), nil, "no deck")
		-- atHeight: what an item at some height is on
		T.truthy(MachineService.atHeight(PLOT, 5, 5, DECK + 1) == deckBelt, "up on the deck belt")
		T.eq(MachineService.atHeight(PLOT, 4, 4, DECK + 1), nil, "lying on a bare deck, not on the belt under it")
		T.truthy(MachineService.atHeight(PLOT, 4, 4, 1) == under, "down on the belt under the deck")
		-- an item high up a Belt Lift is still on the lift (no deck over its cells)
		local lift = place(w, "BeltLift", 4, 6, 0)
		T.truthy(MachineService.atHeight(PLOT, 4, 6, DECK) == lift, "the lift's top end")
		T.truthy(MachineService.atHeight(PLOT, 4, 8, 1) == lift, "the lift's low end")
	end)

	withWorld("Platforms: the Lift's Belt runs up its slope, the Slide's down, and jams nudge along them", function(w)
		place(w, "Platform", 4, 4)
		local lift = place(w, "BeltLift", 4, 6, 0)
		local slide = place(w, "Slide", 4, 1, 0)
		T.eq(MachineService.atCell(PLOT, 4, 7), lift, "the lift covers its cells")
		local plotCF = PlotService.plotCFrame(PLOT)
		local forward = plotCF:VectorToWorldSpace(Vector3.new(0, 0, -1)) -- r0's front
		for _, m in { lift, slide } do
			local belt = m.Model:FindFirstChild("Belt")
			local v = belt.AssemblyLinearVelocity
			T.near(v.Magnitude, GameConfig.ConveyorSpeed, 1e-3, m.Id .. " belt speed")
			T.truthy(v:Dot(forward) > 0, m.Id .. " carries toward its front")
			if m.Id == "BeltLift" then
				T.truthy(v.Y > 1, "the lift carries up its slope")
			else
				T.truthy(v.Y < -1, "the slide carries down its slope")
			end
			T.near((v.Unit - belt.CFrame.LookVector).Magnitude, 0, 1e-4, m.Id .. " along its tilted LookVector")
			for _, d in m.Model:GetDescendants() do
				if d:IsA("BasePart") then
					T.eq(d.CollisionGroup, ConveyorService.CollisionGroup, m.Id .. " " .. d.Name .. " walk-through")
				end
			end
		end
		-- a stuck item half way up the lift gets nudged up the slope
		local pivot = lift.Model:GetPivot()
		local record = ItemService.spawnDesc({ K = "Raw", O = "Copper" }, USER, pivot * CFrame.new(0, 3.5, 0), Vector3.zero, true)
		assert(record, "item")
		local now = 1000
		local function feed(t: number)
			ConveyorService._test.onBelt(lift, record, pivot:PointToObjectSpace(record.Body.CFrame.Position), t)
		end
		feed(now)
		feed(now + GameConfig.ConveyorStuckSeconds + 0.01)
		local v = record.Body.AssemblyLinearVelocity
		T.truthy(v.Y > 1, "nudged up the slope (" .. tostring(v) .. ")")
		T.truthy(v:Dot(forward) > 0, "toward the top end")
	end)

	withWorld("Platforms: a deck machine emits on its own level; the Lift feeds a deck machine at deck height", function(w)
		place(w, "Platform", 4, 4)
		place(w, "Platform", 4, 2)
		-- a deck furnace (x 4-5, z 4-5) whose output cell (5,3) holds a deck Sell Box (x 4-5, z 2-3)
		local furnace = place(w, "ClayFurnace", 4, 4, 0, 1)
		local box = place(w, "SellBox", 4, 2, 0, 1)
		local ox, oz = Grid.outputCell("ClayFurnace", 4, 4, 0)
		T.truthy(ox == 5 and oz == 3, "output cell on the other deck")
		local result = MachineService.emit(furnace, { K = "Ingot", O = "Copper", G = "Clean" })
		T.eq(result, "Handed", "into the deck Sell Box")
		T.truthy(#w.inserts == 1 and w.inserts[1].Machine == box, "the box took it")
		-- a ground furnace beside the deck: its output cell (7... ) is no deck machine
		local ground = place(w, "ClayFurnace", 6, 4, 1) -- r1: front toward +X, output cell (8, 4)
		local gx, gz = Grid.outputCell("ClayFurnace", 6, 4, 1)
		T.truthy(gx == 8, "ground output cell " .. tostring(gx) .. "," .. tostring(gz))
		local popped = MachineService.emit(ground, { K = "Ingot", O = "Iron", G = "Clean" })
		T.eq(popped, "Spawned", "nothing there: it pops out")
		-- a deck emit pops out at deck height when nothing takes it
		MachineService.pickup(box)
		local result2, record = MachineService.emit(furnace, { K = "Ingot", O = "Gold", G = "Clean" })
		T.eq(result2, "Spawned", "loose on the deck")
		local y = PlotService.plotCFrame(PLOT):PointToObjectSpace(record.Body.CFrame.Position).Y
		T.truthy(y > DECK, "popped out up on the deck (" .. y .. ")")
		-- the Lift's feeder box sits at its top end, up at the deck
		local deckBox = place(w, "SellBox", 4, 2, 0, 1)
		local lift = place(w, "BeltLift", 1, 2, 1) -- r1: x 1-3, front toward +X onto (4,2)
		IntakeService._test.rebuild(PLOT)
		-- an item (a plain record, like IntakeService.spec's) at the lift's top end
		local function itemAt(cf: any): any
			return {
				Id = "lifted",
				Kind = "Ingot",
				OreId = "Silver",
				Grade = "Clean",
				Owner = USER,
				State = "Loose",
				Body = { Position = cf.Position },
			}
		end
		local trusted, absorb = rawget(ItemService, "isTrusted"), rawget(ItemService, "absorb")
		rawset(ItemService, "isTrusted", function()
			return true
		end)
		rawset(ItemService, "absorb", function(record)
			record.State = "Consumed"
		end)
		local ok, err = pcall(function()
			local before = #w.inserts
			-- low on the lift (ground height, half way): nothing takes it
			IntakeService._test.scanOne(itemAt(lift.Model:GetPivot() * CFrame.new(0, 2, 0)), 10)
			T.eq(#w.inserts, before, "half way up: still riding")
			local top = itemAt(lift.Model:GetPivot() * CFrame.new(0, DECK + 1.2, -6 + 0.3))
			IntakeService._test.scanOne(top, 10)
			T.eq(#w.inserts, before + 1, "the top end of the lift fed the deck box")
			T.truthy(w.inserts[#w.inserts].Machine == deckBox, "the deck box")
			T.eq(top.State, "Consumed", "taken")
		end)
		rawset(ItemService, "isTrusted", trusted)
		rawset(ItemService, "absorb", absorb)
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("Platforms: a platform with things on it can't be packed up; empty, it can", function(w)
		local platform = place(w, "Platform", 4, 4)
		local belt = place(w, "Conveyor", 4, 4, 0, 1)
		local ok, why = MachineService.pickup(platform)
		T.falsy(ok, "refused")
		T.eq(why, "DeckInUse", "reason")
		T.falsy(platform.Removed, "still there")
		local _, moveWhy = MachineService.move(platform, 8, 8, 0)
		T.eq(moveWhy, "DeckInUse", "can't move away either")
		T.truthy(MachineService.move(belt, 8, 8, 0), "the belt comes down to the ground")
		T.eq(belt.L, 0, "belt on the ground")
		T.eq(belt.Model:GetAttribute("GridL"), 0, "GridL follows")
		T.near(
			belt.Model:GetPivot().Position.Y,
			PlotService.footprintCFrame(PLOT, "Conveyor", 8, 8, 0).Position.Y,
			1e-4,
			"at ground height"
		)
		T.truthy(MachineService.pickup(platform), "empty: packed up")
		T.eq(w.data.MachineInventory.Platform, 6, "back in the build menu")
	end)
	T.test("Platforms: the Tech shop lists the platform, the Belt Lift and the Slide right after the belts", function()
		local MD = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
		local express = MD.ById.ExpressConveyor.Order
		T.eq(MD.ById.Platform.Order, express + 1, "Platform after the Express Conveyor")
		T.eq(MD.ById.BeltLift.Order, express + 2, "then the Belt Lift")
		T.eq(MD.ById.Slide.Order, express + 3, "then the Slide")
	end)

	T.test("Platforms: the tutorial's GOT IT hint passes once a Platform stands on the plot", function()
		local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")
		local step = TutorialConfig.ById.Platforms
		T.truthy(step and step.Optional, "an info hint")
		T.truthy(step.Hint and step.Hint.Mouse and step.Hint.Touch and step.Hint.Gamepad, "a line for every input")
		T.falsy(step.done({ PlacedMachines = { { Id = "Conveyor", X = 0, Z = 0, R = 0 } } }, {}), "not yet")
		T.truthy(step.done({ PlacedMachines = { { Id = "Platform", X = 2, Z = 2, R = 0 } } }, {}), "done")
		T.falsy(step.done({}, {}), "no layout")
	end)

end
