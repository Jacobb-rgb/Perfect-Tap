-- Belt layout: rails, feeders into machine faces, head-on warnings.
return function(T, Loader)
	local ConveyorLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.ConveyorLogic")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")

	local function belt(x: number, z: number, r: number): any
		return { Id = "Conveyor", X = x, Z = z, R = r }
	end
	local function machine(id: string, x: number, z: number, r: number?): any
		return { Id = id, X = x, Z = z, R = r or 0 }
	end
	local function feedsFrom(list: { any }, conveyor: any): any
		for _, f in list do
			if f.Conveyor == conveyor then
				return f.Target
			end
		end
		return nil
	end

	T.test("ConveyorLogic: a straight line keeps both rails closed", function()
		-- r0 moves toward -Z, so each belt feeds the one at z-1
		local a, b, c = belt(5, 6, 0), belt(5, 5, 0), belt(5, 4, 0)
		local sides = ConveyorLogic.openSides({ a, b, c })
		for _, e in { a, b, c } do
			T.falsy(sides[e].Left, "left closed")
			T.falsy(sides[e].Right, "right closed")
		end
	end)

	T.test("ConveyorLogic: a corner opens the receiving belt's side", function()
		-- A at (4,5) moves +X into B at (5,5), which moves -Z (right is +X)
		local a, b = belt(4, 5, 1), belt(5, 5, 0)
		local sides = ConveyorLogic.openSides({ a, b })
		T.truthy(sides[b].Left, "B opens its left (where A comes in)")
		T.falsy(sides[b].Right, "B keeps its right")
		T.falsy(sides[a].Left)
		T.falsy(sides[a].Right)
		-- same corner from the other side
		local c = belt(6, 5, 3)
		sides = ConveyorLogic.openSides({ c, b })
		T.truthy(sides[b].Right, "B opens its right")
		T.falsy(sides[b].Left)
		-- a belt turned 90 degrees, facing up the receiving belt's side, opens it in every rotation
		for r = 0, 3 do
			local dx, dz = Grid.dir(r)
			local rx, rz = Grid.right(r)
			local target = belt(6, 6, r)
			local fromRight = belt(6 + rx, 6 + rz, (r + 3) % 4)
			local s = ConveyorLogic.openSides({ target, fromRight })
			T.truthy(s[target].Right, `r{r} right side opens`)
			T.falsy(s[target].Left, `r{r} left stays`)
			-- a side neighbour running alongside (same direction) does not open anything
			local alongside = belt(6 - rx, 6 - rz, r)
			s = ConveyorLogic.openSides({ target, alongside })
			T.falsy(s[target].Left, `r{r} parallel belt`)
			local _ = dx + dz
		end
	end)

	T.test("ConveyorLogic: a T-join opens both sides", function()
		local left, right, stem = belt(4, 5, 1), belt(6, 5, 3), belt(5, 5, 0)
		local sides = ConveyorLogic.openSides({ left, right, stem })
		T.truthy(sides[stem].Left)
		T.truthy(sides[stem].Right)
	end)

	T.test("ConveyorLogic: belts feed a furnace's sides and back, never its front", function()
		local furnace = machine("ClayFurnace", 4, 4, 0) -- cells x4-5, z4-5, front row z=3
		local back = belt(4, 6, 0) -- moves -Z into (4,5)
		local side = belt(6, 4, 3) -- moves -X into (5,4)
		local otherSide = belt(3, 5, 1) -- moves +X into (4,5)
		local front = belt(4, 3, 2) -- moves +Z into (4,4): the output face
		local away = belt(4, 7, 2) -- behind but moving away
		local feeders = ConveyorLogic.feeders({ furnace, back, side, otherSide, front, away })
		T.eq(feedsFrom(feeders, back), furnace, "back")
		T.eq(feedsFrom(feeders, side), furnace, "right side")
		T.eq(feedsFrom(feeders, otherSide), furnace, "left side")
		T.eq(feedsFrom(feeders, front), nil, "front never")
		T.eq(feedsFrom(feeders, away), nil, "belt moving away")
		T.eq(#feeders, 3)
		T.truthy(ConveyorLogic.faceAllowed(furnace, 4, 6), "faceAllowed back")
		T.falsy(ConveyorLogic.faceAllowed(furnace, 4, 3), "faceAllowed front")
		T.falsy(ConveyorLogic.faceAllowed(furnace, 7, 7), "not adjacent")
		T.falsy(ConveyorLogic.faceAllowed(furnace, 3, 3), "diagonal")
		-- turned furnace: its front is now +X
		local turned = machine("Crusher", 4, 4, 1)
		T.falsy(ConveyorLogic.faceAllowed(turned, 6, 5), "turned front")
		T.truthy(ConveyorLogic.faceAllowed(turned, 4, 3), "turned side")
	end)

	T.test("ConveyorLogic: crates and Sell Chutes take every face", function()
		local crate = machine("StorageCrate", 4, 4, 0)
		local front = belt(4, 3, 2)
		local feeders = ConveyorLogic.feeders({ crate, front })
		T.eq(feedsFrom(feeders, front), crate, "crate front")
		local chute = machine("SellChute", 8, 8, 0)
		local belts = { belt(8, 7, 2), belt(8, 9, 0), belt(7, 8, 1), belt(9, 8, 3) }
		local entries = { chute }
		for _, b in belts do
			table.insert(entries, b)
		end
		feeders = ConveyorLogic.feeders(entries)
		T.eq(#feeders, 4, "chute fed from all 4 sides")
		for _, b in belts do
			T.eq(feedsFrom(feeders, b), chute)
		end
	end)

	T.test("ConveyorLogic: the Cleaning Station and belts never get feeders", function()
		local station = machine("CleaningStation", 4, 4, 0) -- x4-6, z4-5
		local entries = { station, belt(4, 3, 2), belt(5, 6, 0), belt(3, 4, 1), belt(7, 5, 3) }
		T.eq(#ConveyorLogic.feeders(entries), 0)
		T.eq(MachineData.ById.CleaningStation.ConveyorFaces, nil)
		-- a belt pointing into another belt is not a feeder
		T.eq(#ConveyorLogic.feeders({ belt(1, 1, 1), belt(2, 1, 1) }), 0)
		-- a belt off the plot edge feeds nothing
		T.eq(#ConveyorLogic.feeders({ belt(0, 0, 3), belt(11, 11, 2) }), 0)
	end)

	T.test("ConveyorLogic: headOn lists belts facing each other once", function()
		local a, b = belt(2, 2, 1), belt(3, 2, 3)
		local pairsFound = ConveyorLogic.headOn({ a, b, belt(5, 5, 0), belt(5, 4, 0) })
		T.eq(#pairsFound, 1)
		local pair = pairsFound[1]
		T.truthy((pair[1] == a and pair[2] == b) or (pair[1] == b and pair[2] == a), "the right pair")
		T.eq(#ConveyorLogic.headOn({ belt(5, 5, 0), belt(5, 4, 0) }), 0, "a line is fine")
		T.eq(#ConveyorLogic.headOn({ belt(5, 5, 2), belt(5, 4, 0) }), 0, "back to back is fine")
		T.eq(#ConveyorLogic.headOn({ belt(5, 5, 0), belt(5, 4, 2) }), 1, "vertical pair")
	end)

	T.test("ConveyorLogic: unknown and overlapping entries are ignored", function()
		local good = belt(4, 5, 1)
		local target = belt(5, 5, 0)
		local ghost = { Id = "FutureMachine", X = 5, Z = 5, R = 0 }
		local sides = ConveyorLogic.openSides({ good, target, ghost })
		T.truthy(sides[target].Left)
		T.eq(sides[ghost], nil)
		-- a second belt on the same cell (bad save) gets no entry
		local dup = belt(5, 5, 2)
		sides = ConveyorLogic.openSides({ good, target, dup })
		T.eq(sides[dup], nil)
	end)
end
