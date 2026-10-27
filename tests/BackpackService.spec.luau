-- BackpackService (the packs you own and wear, the BACKPACKS shop counter) under Lune:
-- the prompt on the counter, buying any pack you can afford (a bigger one is worn at
-- once), equipping one you own, every refusal with its BackpackResult and no change,
-- the counter's range, broken payloads, the worn pack's player attribute and the
-- capacity that follows it. Save data, players and Net are small fakes;
-- EconomyService, Bonuses and CarryService run for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local BackpackData = Loader.requirePath("ReplicatedStorage.Shared.Config.BackpackData")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local BackpackService = Loader.requirePath("ServerScriptService.Server.Services.BackpackService")

	local shop = BackpackService._test

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

	local function fakePlayer(): any
		local p: any = { UserId = 778, Name = "Packer", Parent = true, attrs = {} }
		p.root = { Position = Vector3.new(0, 0, 0), CFrame = CFrame.new(0, 0, 0) }
		p.humanoid = { Health = 100, WalkSpeed = 16 }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name: string)
				return if name == "HumanoidRootPart" then p.root else nil
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
		local w: any = { notes = {}, changed = 0 }
		w.player = fakePlayer()
		w.data = deepCopy(DataTemplate)
		w.loaded = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player and w.loaded then w.data else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
			Bonuses.invalidate(w.player)
		end)
		patch(Net, "fire", function(name, p, a, b)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b })
		end)
		shop.reset()
		Bonuses.invalidate(w.player)
		-- the shop's counter top, its customer side = +Z
		local counter = Instance.new("Part")
		counter.Size = Vector3.new(8, 0.3, 3)
		counter.CFrame = CFrame.new(46, 4, 74)
		counter.Parent = Instance.new("Model")
		shop.hookCounter(counter)
		w.counter = counter
		w.standAt = function(away: number)
			local p = (counter.CFrame * CFrame.new(0, 0, counter.Size.Z / 2 + away)).Position
			w.player.root.Position = p
			w.player.root.CFrame = CFrame.new(p)
		end
		w.standAt(3)
		w.restore = function()
			shop.reset()
			Bonuses.invalidate(w.player)
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

	local function act(w: any, op: any, payload: any): any
		local before = 0
		for _, note in w.notes do
			if note.Name == "BackpackResult" then
				before += 1
			end
		end
		shop.action(w.player, op, payload)
		local list = {}
		for _, note in w.notes do
			if note.Name == "BackpackResult" then
				table.insert(list, note.A)
			end
		end
		T.eq(#list, before + 1, "exactly one BackpackResult per request")
		return list[#list]
	end

	T.test("BackpackData: ten packs worst to best, 5 to 1000, the starter free", function()
		T.eq(#BackpackData.List, 10)
		T.eq(BackpackData.StarterId, BackpackData.List[1].Id)
		T.eq(BackpackData.List[1].Capacity, 5, "start at 5 (owner)")
		T.eq(BackpackData.List[#BackpackData.List].Capacity, 1000, "the biggest holds 1000 (owner)")
		T.eq(BackpackData.List[1].Price, 0, "the starter is free")
		for i = 2, #BackpackData.List do
			T.lt(BackpackData.List[i - 1].Capacity, BackpackData.List[i].Capacity, "bigger " .. i)
			T.lt(BackpackData.List[i - 1].Price, BackpackData.List[i].Price, "pricier " .. i)
		end
		T.eq(BackpackData.capacity("Nope"), 5, "an unknown pack reads as the starter")
		T.eq(BackpackData.capacity(nil), 5)
		T.eq(DataTemplate.Backpacks.Equipped, BackpackData.StarterId, "everyone starts with the starter")
		T.eq(DataTemplate.Backpacks.Owned[BackpackData.StarterId], true)
	end)

	withWorld("BackpackService: the counter's prompt opens the shop window", function(w)
		local point = w.counter:FindFirstChild(BackpackService.PointName)
		T.truthy(point and point:IsA("Attachment"), "a prompt point (made when the building has none)")
		local prompt = point:FindFirstChild(BackpackService.PromptName)
		T.truthy(prompt and prompt:IsA("ProximityPrompt"), "the Backpacks prompt")
		shop.open(w.player, w.counter)
		local note = w.notes[#w.notes]
		T.eq(note.Name, "OpenUI")
		T.eq(note.A, "Backpacks", "the style chat's shop window")
		T.eq(note.B.Counter, w.counter, "with the counter (its range)")
		w.standAt(40)
		local count = #w.notes
		shop.open(w.player, w.counter)
		T.eq(#w.notes, count, "too far: nothing opens")
		-- hooked twice: one prompt
		shop.hookCounter(w.counter)
		local prompts = 0
		for _, d in point:GetChildren() do
			if d.Name == BackpackService.PromptName then
				prompts += 1
			end
		end
		T.eq(prompts, 1, "one prompt per counter")
	end)

	withWorld("BackpackService: buy any pack you can afford; a bigger one is worn at once", function(w)
		local miners = BackpackData.ById.MinersPack
		local trail = BackpackData.ById.TrailPack
		w.data.Coins = miners.Price + trail.Price
		local r = act(w, "Buy", { Id = miners.Id })
		T.truthy(r.Ok, "bought out of order (owner: any pack you can afford)")
		T.eq(w.data.Coins, trail.Price, "paid")
		T.eq(w.data.Backpacks.Owned[miners.Id], true, "owned")
		T.eq(w.data.Backpacks.Equipped, miners.Id, "a bigger pack is worn at once")
		T.eq(w.player.attrs[BackpackService.Attribute], miners.Id, "the worn pack shows (attribute)")
		T.eq(CarryService.capacity(w.player), miners.Capacity, "the backpack holds the pack's capacity")
		T.eq(w.player.attrs.CarryCapacity, miners.Capacity, "the attribute follows")
		-- a smaller pack: owned, not worn
		r = act(w, "Buy", { Id = trail.Id })
		T.truthy(r.Ok, "bought")
		T.eq(w.data.Coins, 0)
		T.eq(w.data.Backpacks.Equipped, miners.Id, "the bigger one stays on")
		-- equip the smaller one, anywhere
		w.standAt(500)
		r = act(w, "Equip", { Id = trail.Id })
		T.truthy(r.Ok, "equipped away from the shop")
		T.eq(w.data.Backpacks.Equipped, trail.Id)
		T.eq(CarryService.capacity(w.player), trail.Capacity)
		r = act(w, "Equip", { Id = BackpackData.StarterId })
		T.truthy(r.Ok, "the starter is always yours")
	end)

	withWorld("BackpackService: refusals change nothing", function(w)
		local miners = BackpackData.ById.MinersPack
		w.data.Coins = miners.Price - 1
		local before = deepCopy(w.data.Backpacks)
		local function refused(op: any, payload: any, reason: string)
			local r = act(w, op, payload)
			T.falsy(r.Ok, reason)
			T.eq(r.Reason, reason, "reason " .. reason)
			T.eq(w.data.Coins, miners.Price - 1, reason .. ": coins kept")
			T.eq(w.data.Backpacks.Equipped, before.Equipped, reason .. ": still worn")
		end
		refused("Buy", { Id = miners.Id }, "NoCoins")
		refused("Buy", { Id = BackpackData.StarterId }, "Owned")
		refused("Buy", { Id = "Jetpack" }, "BadId")
		refused("Equip", { Id = miners.Id }, "NotOwned")
		refused("Equip", { Id = "Jetpack" }, "BadId")
		refused("Steal", { Id = miners.Id }, "BadId")
		refused("Buy", "MinersPack", "BadId")
		refused("Buy", { Id = string.rep("x", 200) }, "BadId")
		refused("Buy", nil, "BadId")
		w.data.Coins = miners.Price * 2
		w.standAt(40)
		local r = act(w, "Buy", { Id = miners.Id })
		T.eq(r.Reason, "TooFar", "only at the counter")
		T.eq(w.data.Backpacks.Owned[miners.Id], nil, "nothing bought")
		w.standAt(3)
		T.truthy(act(w, "Buy", { Id = miners.Id }).Ok, "then it works")
		r = act(w, "Buy", { Id = miners.Id })
		T.eq(r.Reason, "Owned", "a double tap buys one pack")
		T.eq(w.data.Coins, miners.Price, "paid once")
	end)

	withWorld("BackpackService: the Strong Back perk and Deep Pockets on top of the worn pack", function(w)
		local trail = BackpackData.ById.TrailPack
		w.data.Backpacks.Owned[trail.Id] = true
		w.data.Backpacks.Equipped = trail.Id
		Bonuses.invalidate(w.player)
		T.eq(CarryService.capacity(w.player), trail.Capacity)
		w.data.StarPerks = { DeepPockets = 3 }
		Bonuses.invalidate(w.player)
		T.eq(CarryService.capacity(w.player), math.ceil(trail.Capacity * 1.3), "+10 % a level, rounded up")
		w.player.attrs.Perk_StrongBack = true
		Bonuses.invalidate(w.player)
		T.eq(CarryService.capacity(w.player), math.ceil(trail.Capacity * 1.3) * 2, "doubled by Strong Back")
		-- the Rookie pack's 5: Deep Pockets I still adds one
		w.player.attrs.Perk_StrongBack = nil
		w.data.Backpacks.Equipped = BackpackData.StarterId
		w.data.StarPerks = { DeepPockets = 1 }
		Bonuses.invalidate(w.player)
		T.eq(CarryService.capacity(w.player), 6, "5 + 10 % rounded up")
	end)
end
