-- CarryService = the backpack (owner 2026-10-24: "everything into the backpack",
-- picked up "by itself when you walk near") under Lune: picking up your own loose
-- items into data.BackpackItems (never someone else's, never a dropper's Drop, never
-- out of reach), the auto-pickup pass (only your items in reach, while there is
-- room, one throttled "full" toast), the contents API (stacks, has, take, add,
-- force), a smaller pack holding more than it takes, the attributes, and no carry
-- slowdown on the walk speed. Save data, players and Net are small fakes;
-- ItemService, Bonuses and CarryService run for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BackpackData = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData")
	local GearConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GearConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local USER = 611
	local OTHER = 612
	local RAW = { K = "Raw", O = "Copper" }
	local CLEAN = { K = "Clean", O = "Gold", G = "Pristine" }

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
		local p: any = { UserId = userId, Name = name, Parent = true, attrs = {} }
		p.root = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0), AssemblyLinearVelocity = Vector3.zero }
		p.humanoid = { Health = 100, WalkSpeed = 16 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name2: string)
				return if name2 == "HumanoidRootPart" then p.root else nil
			end,
			GetAttribute = function()
				return nil
			end,
		}
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, ids = 0 }
		w.player = fakePlayer(USER, "Packer")
		w.other = fakePlayer(OTHER, "Neighbour")
		w.data = deepCopy(DataTemplate)
		w.otherData = deepCopy(DataTemplate)
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			if p == w.player then
				return w.data
			elseif p == w.other then
				return w.otherData
			end
			return nil
		end)
		patch(DataService, "changed", function(p)
			w.changed += 1
			Bonuses.invalidate(p)
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		patch(Players, "GetPlayers", function()
			return { w.player, w.other }
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == OTHER then w.other else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids += 1
			return "carry-guid-" .. w.ids
		end)
		ItemService._test.reset()
		CarryService._test.reset()
		-- (no walls in the tests' world: every long grab has a clear line)
		CarryService._test.setReach(function()
			return true
		end)
		Bonuses.invalidate(w.player)
		Bonuses.invalidate(w.other)
		-- a loose item `away` studs in front of the player
		w.item = function(desc: any, away: number, owner: number?): any
			local at = w.player.root.Position + Vector3.new(0, 0, -away)
			local record = ItemService.spawnDesc(desc, owner or USER, CFrame.new(at), nil, true)
			assert(record, "item")
			return record
		end
		w.restore = function()
			ItemService._test.reset()
			CarryService._test.reset()
			CarryService._test.setReach(nil)
			Bonuses.invalidate(w.player)
			Bonuses.invalidate(w.other)
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

	local function toasts(w: any, text: string): number
		local n = 0
		for _, note in w.notes do
			if note.Name == "Notify" and note.Player == w.player and note.A.Text == text then
				n += 1
			end
		end
		return n
	end

	withWorld("CarryService: picking up puts your own loose item into the backpack", function(w)
		local chunk = w.item(RAW, 2)
		T.truthy(CarryService.pickup(w.player, chunk), "picked up")
		T.eq(chunk.State, "Consumed", "out of the world (absorbed)")
		T.eq(w.data.BackpackItems[ItemData.storageKey(RAW)], 1, "in the backpack, by storage key")
		T.eq(CarryService.count(w.player), 1)
		T.eq(w.player.attrs.CarryCount, 1, "the attribute follows the backpack")
		T.eq(CarryService.capacity(w.player), BackpackData.capacity(BackpackData.StarterId), "the starter pack's 5")
		local fx = w.notes[#w.notes]
		T.truthy(fx.Name == "Fx" and fx.A == "Pickup" and fx.B ~= nil, "the pickup effect")
		-- someone else's, a Drop, too far
		local theirs = w.item(RAW, 2, OTHER)
		T.falsy(CarryService.pickup(w.player, theirs), "never someone else's item")
		T.eq(theirs.State, "Loose")
		local drop = w.item({ K = "Drop", O = "BasicDropper" }, 2)
		T.falsy(CarryService.pickup(w.player, drop), "a dropper's Drop rides the belts only")
		local far = w.item(RAW, CarryService.pickupRange(w.player) + 5)
		T.falsy(CarryService.pickup(w.player, far), "out of reach")
		T.eq(CarryService.count(w.player), 1, "nothing else went in")
		-- the request from the client (F / tap)
		local near = w.item(CLEAN, 3)
		CarryService._test.pickupRequest(w.player, near.Model)
		T.eq(near.State, "Consumed", "CarryPickup puts it in")
		T.eq(w.data.BackpackItems[ItemData.storageKey(CLEAN)], 1)
		CarryService._test.pickupRequest(w.player, "junk")
		CarryService._test.pickupRequest(w.player, nil)
		T.eq(CarryService.count(w.player), 2, "junk requests change nothing")
	end)

	withWorld("CarryService: the auto-pickup takes your items in reach while there is room", function(w)
		local capacity = CarryService.capacity(w.player)
		T.eq(capacity, 5, "the starter pack")
		local near = {}
		for i = 1, capacity + 2 do
			table.insert(near, w.item(RAW, 1 + i * 0.5))
		end
		local theirs = w.item(RAW, 2, OTHER)
		local far = w.item(RAW, CarryService.pickupRange(w.player) + 8)
		CarryService._test.autoPickup(w.player, os.clock())
		T.eq(CarryService.count(w.player), capacity, "filled to the capacity")
		T.eq(CarryService.room(w.player), 0, "full")
		T.eq(theirs.State, "Loose", "never someone else's")
		T.eq(far.State, "Loose", "nothing out of reach")
		local left = 0
		for _, record in near do
			if record.State == "Loose" then
				left += 1
			end
		end
		T.eq(left, 2, "the rest waits on the ground")
		T.eq(toasts(w, CarryService.FullText), 1, "one 'backpack full' toast")
		CarryService._test.autoPickup(w.player, os.clock())
		T.eq(toasts(w, CarryService.FullText), 1, "throttled")
		-- a bigger pack: the rest comes in on the next pass
		w.data.Backpacks.Owned.TrailPack = true
		w.data.Backpacks.Equipped = "TrailPack"
		Bonuses.invalidate(w.player)
		CarryService._test.autoPickup(w.player, os.clock())
		T.eq(CarryService.count(w.player), capacity + 2, "picked up the rest")
	end)

	withWorld("CarryService: stacks, has, take and add", function(w)
		w.data.Backpacks.Owned.MinersPack = true
		w.data.Backpacks.Equipped = "MinersPack"
		Bonuses.invalidate(w.player)
		T.eq(CarryService.add(w.player, RAW, 3), 3, "three dirty ores")
		T.eq(CarryService.add(w.player, CLEAN), 1, "one clean gold")
		T.eq(CarryService.add(w.player, { K = "Relic", O = "CrownCoin" }), 1)
		local stacks = CarryService.stacks(w.player)
		T.eq(#stacks, 3)
		for i = 2, #stacks do
			T.truthy(stacks[i - 1].Key < stacks[i].Key, "sorted by key")
		end
		T.truthy(
			CarryService.has(w.player, function(d)
				return d.K == "Clean"
			end),
			"has a clean ore"
		)
		T.falsy(
			CarryService.has(w.player, function(d)
				return d.K == "Ingot"
			end),
			"no ingot"
		)
		local taken = CarryService.take(w.player, function(d)
			return d.K == "Raw"
		end, 2)
		T.eq(#taken, 2, "at most max")
		T.eq(taken[1].K, "Raw")
		T.eq(taken[1].O, "Copper")
		T.eq(w.data.BackpackItems[ItemData.storageKey(RAW)], 1, "one left")
		local all = CarryService.take(w.player, function(d)
			return d.K ~= "Relic"
		end)
		T.eq(#all, 2, "every match without max (the last raw + the gold)")
		T.eq(w.data.BackpackItems[ItemData.storageKey(RAW)], nil, "an empty stack goes")
		T.eq(CarryService.count(w.player), 1, "the relic stays")
		-- a full backpack takes nothing more unless forced (things that must never be lost)
		local capacity = CarryService.capacity(w.player)
		T.eq(CarryService.add(w.player, RAW, capacity + 10), capacity - 1, "fills up to the capacity")
		T.eq(CarryService.add(w.player, RAW), 0, "full")
		T.eq(CarryService.add(w.player, RAW, 1, true), 1, "forced past it")
		T.eq(CarryService.room(w.player), 0)
		-- a key this build can't read stays in the save, unseen
		w.data.BackpackItems["Gem|Zzzium||"] = 2
		for _, stack in CarryService.stacks(w.player) do
			T.falsy(stack.Key == "Gem|Zzzium||", "an unreadable key is no stack")
		end
		T.eq(w.data.BackpackItems["Gem|Zzzium||"], 2, "kept")
	end)

	withWorld("CarryService: a smaller pack holds more than it takes; no carry slowdown", function(w)
		w.data.Backpacks.Owned.TrailPack = true
		w.data.Backpacks.Equipped = "TrailPack"
		Bonuses.invalidate(w.player)
		T.eq(CarryService.add(w.player, RAW, 12), 12)
		w.data.Backpacks.Equipped = BackpackData.StarterId
		Bonuses.invalidate(w.player)
		T.eq(CarryService.count(w.player), 12, "the contents stay")
		T.eq(CarryService.room(w.player), 0, "nothing new goes in")
		T.falsy(CarryService.pickup(w.player, w.item(RAW, 2)), "a pickup waits")
		T.eq(toasts(w, CarryService.FullText), 1, "says the backpack is full")
		-- walking: the backpack never slows anyone down
		CarryService.refreshWalkSpeed(w.player)
		T.eq(w.player.humanoid.WalkSpeed, GearConfig.value("Boots", 0), "Boots 0's speed with 12 items")
	end)
end
