-- StateService network diet (perf pass 1, docs/SERVER_PERF_AUDIT.md #1):
-- pushes carry only the sections that changed (Placed only after a layout
-- edit), a removed section is announced, the first push after a (re)join is
-- whole and goes out at once, later pushes are coalesced, the coin
-- attributes follow the balance, the client's StateController.merge turns
-- every partial push back into the whole snapshot (steps 6-7 Kept keys too),
-- and a busy player's State bytes per second drop a lot.
return function(T, Loader)
	local task = require("@lune/task")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local BuildService = Loader.requirePath("ServerScriptService.Server.Services.BuildService")
	local StateController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController")

	local NOW = 1_800_000_000

	local function fresh(): { [string]: any }
		return ProfileStore.deepCopy(DataTemplate)
	end

	local function fakePlayer(userId: number): any
		local p: any = { UserId = userId, Name = "P" .. userId, Parent = true, attrs = {}, writes = 0 }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.writes += 1
			p.attrs[key] = value
		end
		return p
	end

	-- a copy, like a RemoteEvent delivers it (the client never shares the server's tables)
	local function wire(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in value do
			out[k] = wire(v)
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

	-- the sections of a push, whole or patched (not Full / Kept / Removed)
	local function sections(push: { [string]: any }): { string }
		local list = {}
		for key in push do
			if not StateService.Reserved[key] then
				table.insert(list, key)
			end
		end
		for key in push.Patch or {} do
			table.insert(list, key)
		end
		table.sort(list)
		return list
	end

	--[[
		Rough size of a value in a RemoteEvent (Roblox's format: a type byte,
		doubles for numbers, length-prefixed strings, tables as key/value
		pairs). Good enough to compare two protocols.
	]]
	local function bytes(value: any): number
		local kind = type(value)
		if kind == "number" then
			return 9
		elseif kind == "string" then
			return 2 + #value
		elseif kind == "boolean" or kind == "nil" then
			return 2
		elseif kind == "table" then
			local total = 3
			local n = #value
			for k, v in value do
				if not (type(k) == "number" and k >= 1 and k <= n) then
					total += bytes(k)
				end
				total += bytes(v)
			end
			return total
		end
		return 9
	end

	-- A busy factory: ~70 placed entries (machines, belts, poles), a full
	-- pen, codex, keep list, upgrades and Foundry ingots.
	local function busyData(): { [string]: any }
		local data = fresh()
		local ids = { "Crusher", "ClayFurnace", "Anvil", "Polisher", "Sorter", "Splitter", "RobotArm", "PowerPole" }
		for i = 1, 70 do
			local id = if i % 3 == 0 then ids[(i // 3) % #ids + 1] else "Conveyor"
			table.insert(data.PlacedMachines, { Id = id, X = i % 12, Z = i // 12, R = i % 4 })
		end
		local ores = {}
		for i, ore in OreData.List do
			if i <= 24 then
				table.insert(ores, ore.Id)
				data.Discovered[ore.Id] = true
			end
		end
		local kinds = { "Raw", "Clean", "Crushed", "Ingot" }
		local grades = { "Rough", "Clean", "Pristine", "Flawless" }
		for i = 1, 160 do
			local kind = kinds[i % #kinds + 1]
			table.insert(data.Storage, {
				K = kind,
				O = ores[i % #ores + 1],
				G = if kind == "Raw" then nil else grades[(i // 4) % #grades + 1],
			})
		end
		for i = 1, 20 do
			table.insert(data.Foundry.Stock, { K = "Ingot", O = ores[i % 6 + 1], G = grades[i % 4 + 1] })
		end
		for i = 1, 12 do
			data.KeepList[ores[i]] = i % 2 == 0
		end
		data.MachineInventory = { Conveyor = 12, Crusher = 1, Sorter = 2, PowerPole = 3 }
		data.MachineUpgrades = { Crusher = { Speed = 3, Output = 2 }, ClayFurnace = { Speed = 2 }, Polisher = { Speed = 1 } }
		data.Coins = 12345.5
		return data
	end

	local function withState(name: string, fn: (any) -> ())
		T.test(name, function()
			local w: any = { byPlayer = {}, fired = {}, income = 4.5, extra = true }
			local savedGet = rawget(DataService, "get")
			local savedFire = rawget(Net, "fire")
			rawset(DataService, "get", function(p)
				return w.byPlayer[p]
			end)
			rawset(Net, "fire", function(name: string, p: any, payload: any)
				table.insert(w.fired, { Name = name, Player = p, Payload = payload })
			end)
			Bonuses._test.reset()
			Bonuses._test.setClock(function()
				return NOW
			end)
			StateService._test.reset()
			local providers = StateService._test.providerCount()
			-- the real Placed / Build provider and a podium income like PodiumService's
			StateService.addProvider(BuildService._test.provide)
			StateService.addProvider(function(_p, _data, snapshot)
				snapshot.Income = w.income
				if w.extra then
					snapshot.Extra = { Note = "only sometimes" }
				end
			end)
			local push, attr = StateService.PushSeconds, StateService.AttributeSeconds
			local ok, err = pcall(fn, w)
			StateService.PushSeconds, StateService.AttributeSeconds = push, attr
			StateService._test.trimProviders(providers)
			StateService._test.reset()
			rawset(DataService, "get", savedGet)
			rawset(Net, "fire", savedFire)
			Bonuses._test.reset()
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function waitUntil(check: () -> boolean, timeout: number?)
		local deadline = os.clock() + (timeout or 1)
		repeat
			task.wait()
		until check() or os.clock() > deadline
	end

	withState("StateService: a push carries only the sections that changed; Placed only after a layout edit", function(w)
		local data = busyData()
		local p = fakePlayer(41)
		w.byPlayer[p] = data
		local first = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(first.Full, true, "the first push is whole")
		T.eq(#first.Placed, 70, "every machine and belt")
		T.truthy(first.Coins and first.Storage and first.Discovered and first.Build, "whole")
		T.eq(first.Kept, nil)
		T.eq(first.Removed, nil)
		-- nothing changed: no section at all (the sticky ones listed in Kept, steps 6-7)
		local second = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(#sections(second), 0, "an empty push: " .. table.concat(sections(second), ","))
		T.eq(second.Full, nil, "not whole")
		for _, key in { "Gear", "Enchants", "Golems", "Artifacts", "Bonuses", "Discovered" } do
			T.truthy(table.find(second.Kept, key), key .. " listed as kept")
		end
		-- a sale and an ore into the pen: only those sections
		data.Coins += 40
		table.insert(data.Storage, { K = "Raw", O = data.Storage[1].O })
		local third = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(table.concat(sections(third), ","), "Coins,Storage,StorageCount", "only what changed")
		T.eq(third.Placed, nil, "no Placed without a layout edit")
		-- the pen summary as a patch: one count, not the whole pen
		T.eq(third.Storage, nil, "Storage patched, not whole")
		local storagePatch = third.Patch.Storage
		local setKeys = {}
		for key in storagePatch.Set do
			table.insert(setKeys, key)
		end
		T.eq(#setKeys, 1, "one count changed")
		T.eq(storagePatch.Clear, nil)
		-- a machine turned: Placed again (counts and slots stay: left out)
		data.PlacedMachines[3].R = (data.PlacedMachines[3].R + 1) % 4
		local fourth = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(table.concat(sections(fourth), ","), "Placed", "a turned machine")
		T.eq(#fourth.Placed, 70)
		-- a new belt: Placed, its count and the slots
		table.insert(data.PlacedMachines, { Id = "Conveyor", X = 11, Z = 11, R = 0 })
		local fifth = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(table.concat(sections(fifth), ","), "Build,Placed,PlacedCount", "a placed belt")
		T.truthy(fifth.Patch and fifth.Patch.Build and fifth.Patch.Build.Set.ConveyorsUsed, "Build: only the belt count")
		-- a new golem: the sticky record goes again, the others stay kept
		-- fingerprints: no text inside a string passes for a separator
		T.truthy(StateService.fingerprint({ "a,s1:b" }) ~= StateService.fingerprint({ "a", "b" }), "strings are length-prefixed")
		T.eq(StateService.fingerprint({ X = { 1, 2 }, Y = "z" }), StateService.fingerprint({ Y = "z", X = { 1, 2 } }))
		GolemConfig.add(data.Golems, "PebbleGolem")
		local sixth = StateService.trim(p, StateService.snapshot(p) :: any)
		T.truthy(sixth.Golems, "Golems sent again")
		T.falsy(table.find(sixth.Kept, "Golems"))
		T.truthy(table.find(sixth.Kept, "Gear"), "Gear still kept")
	end)

	withState("StateService: an emptied section goes out empty, a removed one is listed in Removed", function(w)
		local data = busyData()
		local p = fakePlayer(42)
		w.byPlayer[p] = data
		local client = StateController.merge(nil, wire(StateService.trim(p, StateService.snapshot(p) :: any)))
		T.truthy(client.Extra, "the provider's section")
		-- emptied: the empty table is a change like any other
		table.clear(data.KeepList)
		local push = StateService.trim(p, StateService.snapshot(p) :: any)
		T.truthy(push.KeepList and next(push.KeepList) == nil, "KeepList sent empty")
		client = StateController.merge(client, wire(push))
		T.truthy(client.KeepList and next(client.KeepList) == nil, "the client's KeepList is empty")
		-- removed: the provider leaves it out now
		w.extra = false
		push = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(push.Removed and table.concat(push.Removed, ","), "Extra", "listed as removed")
		T.eq(#sections(push), 0, "nothing else")
		client = StateController.merge(client, wire(push))
		T.eq(client.Extra, nil, "gone on the client")
		T.truthy(client.Placed and #client.Placed == 70, "the rest stays")
		-- back again: whole section, no Removed
		w.extra = true
		push = StateService.trim(p, StateService.snapshot(p) :: any)
		T.eq(table.concat(sections(push), ","), "Extra")
		T.eq(push.Removed, nil)
	end)

	withState("StateController: partial pushes merge into the whole snapshot (Kept, Removed, Full)", function(w)
		local data = busyData()
		local p = fakePlayer(43)
		w.byPlayer[p] = data
		local client: any = nil
		local function step(label: string)
			local push = wire(StateService.trim(p, StateService.snapshot(p) :: any))
			client = StateController.merge(client, push)
			local truth = StateService.snapshot(p) :: any
			T.truthy(deepEqual(client, truth), label .. ": the client has the whole snapshot")
			for key in StateService.Reserved do
				T.eq(client[key], nil, label .. ": no " .. key)
			end
		end
		step("first")
		step("nothing changed")
		data.Coins += 1
		step("coins")
		data.Gear.Boots = 2
		step("gear (sticky)")
		data.PlacedMachines[1].X = 9
		step("layout")
		w.extra = false
		step("removed")
		w.extra = true
		data.Stats.OresMined += 3
		step("back + stats (patch)")
		table.insert(data.Storage, { K = "Raw", O = data.Storage[1].O })
		table.remove(data.Storage, 2)
		step("storage (patch)")
		table.clear(data.Storage)
		step("storage emptied (whole)")
		table.insert(data.Storage, { K = "Raw", O = "Copper" })
		step("storage again")
		-- steps 6-7: Kept keys come from the previous snapshot
		local previous = { Coins = 1, Gear = { Boots = 1 }, Golems = { Owned = {} } }
		local merged = StateController.merge(previous, { Coins = 2, Kept = { "Gear", "Golems" } })
		T.eq(merged.Coins, 2)
		T.truthy(merged.Gear == previous.Gear and merged.Golems == previous.Golems, "kept records")
		T.eq(merged.Kept, nil)
		T.eq(previous.Coins, 1, "the previous snapshot is not changed")
		-- Full replaces: a section the server no longer has does not linger
		local whole = StateController.merge(previous, { Full = true, Coins = 3 })
		T.eq(whole.Gear, nil, "full push replaces")
		T.eq(whole.Full, nil)
		-- a patch changes and clears keys of a copy of the previous section
		local before = { Storage = { a = 1, b = 2, c = 3 }, Coins = 5 }
		local patchedSnap = StateController.merge(before, { Patch = { Storage = { Set = { a = 4, d = 1 }, Clear = { "b" } } } })
		T.truthy(deepEqual(patchedSnap.Storage, { a = 4, c = 3, d = 1 }), "patched")
		T.truthy(deepEqual(before.Storage, { a = 1, b = 2, c = 3 }), "the previous section is not changed")
		T.eq(patchedSnap.Coins, 5)
		T.eq(patchedSnap.Patch, nil)
		-- a first push without Full (an old server) is taken as it is
		local alone = StateController.merge(nil, { Coins = 4, Kept = { "Gear" } })
		T.eq(alone.Coins, 4)
		T.eq(alone.Gear, nil)
	end)

	withState("StateService: the first push after a (re)join is whole and at once, later ones are coalesced", function(w)
		T.eq(StateService.PushSeconds, 0.5, "default coalesce window")
		StateService.PushSeconds = 0.15
		local data = busyData()
		local p = fakePlayer(44)
		w.byPlayer[p] = data
		StateService.push(p)
		task.wait()
		waitUntil(function()
			return #w.fired >= 1
		end, 0.05)
		T.eq(#w.fired, 1, "the first push goes out at once")
		T.eq(w.fired[1].Payload.Full, true, "whole")
		T.eq(#w.fired[1].Payload.Placed, 70)
		-- a burst of changes: one push after the window
		for _ = 1, 10 do
			data.Coins += 1
			StateService.push(p)
		end
		task.wait(0.05)
		T.eq(#w.fired, 1, "held back")
		waitUntil(function()
			return #w.fired >= 2
		end, 1)
		T.eq(#w.fired, 2, "one push for the burst")
		T.eq(w.fired[2].Payload.Full, nil)
		T.eq(w.fired[2].Payload.Coins, data.Coins, "the newest coins")
		T.eq(w.fired[2].Payload.Placed, nil, "no Placed")
		task.wait(0.2)
		T.eq(#w.fired, 2, "no push without a change")
		-- left and came back (PlayerRemoving -> forget): whole again, at once
		StateService.forget(p)
		T.falsy(StateService.hasSent(p))
		StateService.push(p)
		waitUntil(function()
			return #w.fired >= 3
		end, 0.05)
		T.eq(#w.fired, 3, "at once after the rejoin")
		T.eq(w.fired[3].Payload.Full, true, "whole after the rejoin")
		T.eq(#w.fired[3].Payload.Placed, 70, "Placed again")
		-- a player who left before the push: nothing is sent
		local gone = fakePlayer(45)
		w.byPlayer[gone] = busyData()
		StateService.push(gone)
		gone.Parent = nil
		task.wait(0.05)
		for _, fire in w.fired do
			T.truthy(fire.Player ~= gone, "nothing for a player who left")
		end
	end)

	withState("StateService: the Coins / IncomePerSec attributes follow the balance, at most every AttributeSeconds", function(w)
		T.eq(StateService.AttributeSeconds, 0.25, "default attribute window")
		StateService.AttributeSeconds = 0.05
		local data = busyData()
		local p = fakePlayer(46)
		w.byPlayer[p] = data
		StateService.send(p)
		T.eq(p.attrs.Coins, data.Coins, "Coins with the snapshot")
		T.eq(p.attrs.IncomePerSec, 4.5, "IncomePerSec from the snapshot's Income")
		-- quiet podium payouts: many changes, one write per window
		local writes = p.writes
		for _ = 1, 20 do
			data.Coins += 0.25
			StateService.touchCoins(p)
		end
		T.eq(p.writes, writes, "not yet")
		waitUntil(function()
			return p.attrs.Coins == data.Coins
		end, 1)
		T.eq(p.attrs.Coins, data.Coins, "the newest balance")
		T.eq(p.writes, writes + 1, "one write for the burst")
		-- unchanged: no write
		StateService.touchCoins(p)
		task.wait(0.1)
		T.eq(p.writes, writes + 1, "same value: no write")
		-- income follows the next snapshot
		w.income = 9
		StateService.send(p)
		T.eq(p.attrs.IncomePerSec, 9)
	end)

	withState("StateService: a busy player's State bytes per second drop a lot", function(w)
		local data = busyData()
		local oldP, newP = fakePlayer(47), fakePlayer(48)
		w.byPlayer[oldP] = data
		w.byPlayer[newP] = data
		-- main 9be848a: a push every 0.2 s while changes come, the whole
		-- snapshot minus the unchanged sticky records (steps 6-7)
		local oldKnown: { [string]: string } = {}
		local function oldTrim(snapshot: { [string]: any }): { [string]: any }
			local kept = {}
			for _, key in StateService.Sticky do
				local value = snapshot[key]
				if value ~= nil then
					local mark = StateService.fingerprint(value)
					if oldKnown[key] == mark then
						snapshot[key] = nil
						table.insert(kept, key)
					else
						oldKnown[key] = mark
					end
				end
			end
			if #kept > 0 then
				snapshot.Kept = kept
			end
			return snapshot
		end
		-- a running factory: 15 data changes a second for 30 s (ores into the
		-- pen and out to the machines, sales, podium coins, stats), one layout
		-- edit, a golem; a moving train / pen counter that changes every push
		local SECONDS, RATE = 30, 15
		local events = SECONDS * RATE
		local oldBytes, newBytes, attrBytes = 0, 0, 0
		local oldPushes, newPushes, attrWrites = 0, 0, 0
		local nextOld, nextNew, nextAttr = 0, 0, 0
		local lastCoins: number? = nil
		local ore = data.Storage[1].O
		local function counters(snapshot: { [string]: any }, t: number)
			snapshot.PenSend = { Pen = #data.Storage % 7, Train = 0, PenWait = 0, TrainWait = 0 }
			snapshot.Train = { Cargo = math.floor(t) % 20, Capacity = 20, Moving = 0, AutoDepartIn = 30 - t % 30 }
		end
		for i = 1, events do
			local t = i / RATE
			local roll = i % 10
			if roll < 4 then
				table.insert(data.Storage, { K = "Raw", O = ore })
			elseif roll < 7 then
				table.remove(data.Storage)
			elseif roll < 8 then
				data.Coins += 25
				data.Stats.ItemsSold += 1
			else
				data.Stats.OresCleaned += 1
			end
			if i % RATE == 0 then
				data.Coins += 3.5 -- the quiet podium payout every second
			end
			if i == events // 2 then
				data.PlacedMachines[5].X = (data.PlacedMachines[5].X + 1) % 12
			end
			if i == events // 3 then
				GolemConfig.add(data.Golems, "PebbleGolem")
			end
			if t >= nextOld then
				nextOld = t + 0.2
				local snapshot = StateService.snapshot(oldP) :: any
				counters(snapshot, t)
				oldBytes += bytes(oldTrim(snapshot))
				oldPushes += 1
			end
			if t >= nextNew then
				nextNew = t + StateService.PushSeconds
				local snapshot = StateService.snapshot(newP) :: any
				counters(snapshot, t)
				newBytes += bytes(StateService.trim(newP, snapshot))
				newPushes += 1
			end
			if t >= nextAttr and data.Coins ~= lastCoins then
				nextAttr = t + StateService.AttributeSeconds
				lastCoins = data.Coins
				-- an attribute change replicates as its name and a double (to every client)
				attrBytes += 2 + #StateService.CoinsAttribute + 9 + 4
				attrWrites += 1
			end
		end
		-- per receiving client: its own State plus the coin attributes of
		-- every player on the server (attributes replicate to everyone)
		local before = oldBytes / SECONDS
		local after = (newBytes + attrBytes * GameConfig.MaxPlayers) / SECONDS
		print(
			string.format(
				"    [State bytes/s, busy player] before %.0f B/s (%d pushes, %.0f B each), after %.0f B/s (%d pushes %.0f B/s + %d coin attribute writes x 8 players %.0f B/s): %.1f%% of before",
				before,
				oldPushes,
				oldBytes / oldPushes,
				after,
				newPushes,
				newBytes / SECONDS,
				attrWrites,
				attrBytes * GameConfig.MaxPlayers / SECONDS,
				after / before * 100
			)
		)
		T.lt(after, before * 0.15, "at least 85% less")
		T.lt(after, 3000, "under 3 KB/s (SERVER_PERF_AUDIT fix 1)")
	end)
end
