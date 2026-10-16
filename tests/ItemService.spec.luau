-- ItemService under Lune: descriptors, the per-owner index, the Ore Pen
-- with its capacity, the loose cap, the trust check, hidden dirty-ore values
-- and the snap-back of items a client moved too far. Save data, players and
-- Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local USER = 301

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
		local w: any = { notes = {}, ids = 0 }
		w.data = deepCopy(DataTemplate)
		w.root = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0) }
		local character = {
			FindFirstChild = function(_, name: string)
				return if name == "HumanoidRootPart" then w.root else nil
			end,
		}
		w.player = { UserId = USER, Name = "Owner", Parent = true, Character = character }
		w.online = true
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player and w.online then w.data else nil
		end)
		patch(DataService, "changed", function() end)
		patch(Net, "fire", function(name, p, payload)
			table.insert(w.notes, { Name = name, Player = p, Payload = payload })
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER and w.online then w.player else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids += 1
			return "guid-" .. w.ids
		end)
		ItemService._test.reset()
		w.restore = function()
			ItemService._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		-- moves the owner's character
		w.moveOwner = function(position: any)
			w.root.Position = position
			w.root.CFrame = CFrame.new(position)
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

	local function clean(grade: string?): any
		return { K = "Clean", O = "Copper", G = grade or "Rough" }
	end

	withWorld("ItemService: spawnDesc, descOf and the per-owner index", function(w)
		local record = ItemService.spawnDesc(clean("Pristine"), USER, CFrame.new(0, 5, 0))
		T.truthy(record, "spawned")
		T.eq(record.Kind, "Clean", "kind")
		T.eq(record.Grade, "Pristine", "grade")
		T.eq(record.State, "Loose", "loose")
		T.eq(record.Model:GetAttribute("Owner"), USER, "Owner attribute")
		T.eq(record.Model:GetAttribute("Value"), ItemData.value("Clean", "Copper", "Pristine"), "Value attribute")
		T.near((record.ReleasePos - Vector3.new(0, 5, 0)).Magnitude, 0, 1e-4, "release point")
		T.truthy(record.ClientOwnedUntil, "the nearby owner's client simulates it")
		T.eq(ItemService.looseCount(USER), 1, "looseCount")
		T.eq(#ItemService.ownedBy(USER), 1, "ownedBy")
		T.eq(#ItemService.looseList(), 1, "looseList")
		T.truthy(ItemService.getById(record.Id) == record, "getById")
		local d = ItemService.descOf(record)
		T.truthy(d.K == "Clean" and d.O == "Copper" and d.G == "Pristine" and d.R == nil, "descOf")
		T.truthy(ItemService.descOf(record) ~= d, "a fresh table each time")

		local served = ItemService.spawnDesc(clean(), USER, CFrame.new(2, 5, 0), nil, true)
		T.eq(served.ClientOwnedUntil, nil, "serverOwned keeps server physics")
		w.moveOwner(Vector3.new(GameConfig.ClientPhysicsRange + 10, 3, 0))
		local far = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		T.eq(far.ClientOwnedUntil, nil, "a far-away owner's client never simulates it")
		T.eq(ItemService.spawnDesc({ K = "Clean" } :: any, USER, CFrame.new()), nil, "junk descriptor")
		T.eq(ItemService.looseCount(USER), 3, "three loose")
		T.eq(ItemService.looseCount(USER + 1), 0, "nobody else's")
	end)

	withWorld("ItemService: absorb takes an item out of the world once", function(w)
		local record = ItemService.spawnDesc(clean("Clean"), USER, CFrame.new(0, 5, 0))
		record.Model:SetAttribute("CarriedBy", USER)
		local d = ItemService.absorb(record)
		T.truthy(d.K == "Clean" and d.G == "Clean", "descriptor")
		T.eq(record.State, "Consumed", "consumed")
		T.eq(ItemService.looseCount(USER), 0, "not loose")
		T.eq(#ItemService.ownedBy(USER), 0, "not owned")
		T.eq(ItemService.getById(record.Id), nil, "forgotten")
		T.falsy(pcall(ItemService.absorb, record), "a consumed item can't be absorbed again")
	end)

	withWorld("ItemService: storeDesc fills the Ore Pen up to its capacity and pays beyond it", function(w)
		local d = clean("Flawless")
		T.eq(ItemService.storeDesc(w.player, d), "Stored", "stored")
		T.eq(#w.data.Storage, 1, "in the pen")
		T.truthy(w.data.Storage[1] ~= d, "a copy is stored")
		T.eq(w.data.Storage[1].G, "Flawless", "grade kept")
		T.eq(#w.notes, 0, "no toast without a reason")
		ItemService.storeDesc(w.player, d, "Packed up")
		T.eq(w.notes[1].Payload.Text, "Packed up (moved to your Ore Pen)", "stored toast")
		-- the starting pen holds EconomyConfig.Pen.BaseCapacity items
		local capacity = ItemService.penCapacity(w.data)
		T.eq(capacity, EconomyConfig.Pen.BaseCapacity, "starting pen")
		for _ = #w.data.Storage + 1, capacity do
			table.insert(w.data.Storage, clean())
		end
		local coins = w.data.Coins
		T.eq(ItemService.storeDesc(w.player, d, "Too many loose items"), "Sold", "sold when full")
		local value = ItemData.value("Clean", "Copper", "Flawless")
		T.eq(w.data.Coins, coins + value, "paid the full value")
		T.eq(w.data.TotalEarned, value, "counted as earned")
		T.eq(#w.data.Storage, capacity, "never over the capacity")
		T.eq(w.notes[2].Payload.Text, `Too many loose items (Ore Pen full: sold it for {Format.money(value)})`, "sold toast")
		-- a pen upgrade makes room; the DataStore cap always wins
		w.data.Upgrades.PenLevel = 2
		T.eq(ItemService.penCapacity(w.data), capacity + 2 * EconomyConfig.Pen.PerLevel, "upgraded pen")
		T.eq(ItemService.storeDesc(w.player, d), "Stored", "room again")
		w.data.Upgrades.PenLevel = 999
		T.le(ItemService.penCapacity(w.data), GameConfig.MaxStoredItems, "never above the DataStore cap")
		w.data.Upgrades.PenLevel = 0 / 0
		T.eq(ItemService.penCapacity(w.data), capacity, "junk level = starting pen")
		w.data.Upgrades = nil
		T.eq(ItemService.penCapacity(w.data), capacity, "no upgrades table")
		T.eq(ItemService.storeDesc(w.player, { K = 5 } :: any), "Lost", "junk")
		w.online = false
		T.eq(ItemService.storeDesc(w.player, d), "Lost", "no data loaded")
	end)

	withWorld("ItemService: dirty ore replicates no value (rarity stays hidden)", function(w)
		local raw = ItemService.spawnDesc({ K = "Raw", O = "Diamond" }, USER, CFrame.new(0, 5, 0))
		T.eq(raw.Model:GetAttribute("Value"), 0, "raw Value attribute")
		T.eq(raw.Model:GetAttribute("Kind"), "Raw", "kind")
		local cleaned = ItemService.spawnDesc(clean("Clean"), USER, CFrame.new(2, 5, 0))
		T.eq(cleaned.Model:GetAttribute("Value"), ItemData.value("Clean", "Copper", "Clean"), "clean ore shows its value")
		-- the pen still pays the real raw price when it is full
		for _ = 1, ItemService.penCapacity(w.data) do
			table.insert(w.data.Storage, clean())
		end
		local coins = w.data.Coins
		T.eq(ItemService.stash(raw, nil), false, "sold, not kept")
		T.eq(w.data.Coins, coins + ItemData.value("Raw", "Diamond"), "raw price")
	end)

	withWorld("ItemService: stash and the loose cap keep every item", function(w)
		local record = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		T.truthy(ItemService.stash(record, "Your item landed on another forge"), "stashed")
		T.eq(record.State, "Consumed", "gone from the world")
		T.eq(#w.data.Storage, 1, "in storage")
		T.eq(w.notes[1].Payload.Text, "Your item landed on another forge (moved to your Ore Pen)", "toast")

		local cap = GameConfig.MaxLooseItemsPerPlayer
		for i = 1, cap + 2 do
			ItemService.spawnDesc(clean(), USER, CFrame.new(i, 5, 0))
		end
		T.eq(ItemService.looseCount(USER), cap, "at most the cap stays loose")
		T.eq(#w.data.Storage, 3, "the oldest two went to storage")
		local toasts = 0
		for _, note in w.notes do
			if note.Payload.Text == "Too many loose items (moved to your Ore Pen)" then
				toasts += 1
			end
		end
		T.eq(toasts, 1, "one toast")

		w.online = false
		local orphan = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		T.falsy(ItemService.stash(orphan, nil), "owner gone: nothing to keep it in")
		T.eq(orphan.State, "Consumed", "destroyed anyway")
	end)

	withWorld("ItemService: isTrusted checks the owner's distance and plausible travel", function(w)
		local record = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		local t0 = record.ReleasedAt
		T.truthy(record.ClientOwnedUntil, "client-owned")
		record.Body.CFrame = CFrame.new(10, 1, 0)
		T.truthy(ItemService.isTrusted(record, t0 + 1), "thrown 10 studs in a second")
		record.Body.CFrame = CFrame.new(30, 1, 0)
		T.falsy(ItemService.isTrusted(record, t0 + 0.2), "30 studs in 0.2 s")
		T.truthy(ItemService.isTrusted(record, t0 + 1), "30 studs in a second")
		w.moveOwner(Vector3.new(30 + GameConfig.AntiTeleportRange + 5, 3, 0))
		T.falsy(ItemService.isTrusted(record, t0 + 5), "owner too far away")
		w.online = false
		T.falsy(ItemService.isTrusted(record, t0 + 5), "owner gone")
		record.ClientOwnedUntil = nil
		T.truthy(ItemService.isTrusted(record, t0 + 5), "the server simulates it: always trusted")
	end)

	withWorld("ItemService: items a client moved too far snap back", function(w)
		-- (in the game items live in Workspace.Items; unparented means destroyed)
		local world = roblox.Instance.new("Folder")
		local function spawnIn(cf: any, serverOwned: boolean?): any
			local r = ItemService.spawnDesc(clean(), USER, cf, nil, serverOwned)
			r.Model.Parent = world
			return r
		end
		local record = spawnIn(CFrame.new(0, 5, 0))
		local maintain = ItemService._test.maintain
		-- moved within reason: it stays
		record.Body.CFrame = CFrame.new(GameConfig.MaxItemTravel - 5, 1, 0)
		record.ClientOwnedUntil = os.clock() - 1
		maintain(record, os.clock())
		T.eq(record.ClientOwnedUntil, nil, "server took it back")
		T.near(record.Body.CFrame.Position.X, GameConfig.MaxItemTravel - 5, 1e-4, "left where it is")
		-- teleported: back next to the owner
		local other = spawnIn(CFrame.new(0, 5, 0))
		other.Body.CFrame = CFrame.new(GameConfig.MaxItemTravel + 30, 1, 0)
		other.ClientOwnedUntil = os.clock() - 1
		maintain(other, os.clock())
		local rescue = (w.root.CFrame * CFrame.new(0, 2, -4)).Position
		T.near((other.Body.CFrame.Position - rescue).Magnitude, 0, 1e-3, "back at the owner")
		T.eq(other.State, "Loose", "still loose")
		-- fell out of the world: rescued too
		local fallen = spawnIn(CFrame.new(0, 5, 0), true)
		fallen.Body.CFrame = CFrame.new(0, GameConfig.ItemFallKillY - 1, 0)
		maintain(fallen, os.clock())
		T.near((fallen.Body.CFrame.Position - rescue).Magnitude, 0, 1e-3, "fallen item rescued")
		-- destroyed by the engine: kept as storage
		local stored = #w.data.Storage
		local lost = spawnIn(CFrame.new(0, 5, 0), true)
		lost.Model.Parent = nil
		maintain(lost, os.clock())
		T.eq(lost.State, "Consumed", "forgotten")
		T.eq(#w.data.Storage, stored + 1, "kept in storage")
		T.eq(ItemService.getById(lost.Id), nil, "out of the index")
	end)

	withWorld("ItemService: eject pops an item out where it is", function(w)
		local record = ItemService.spawnDesc(clean(), USER, CFrame.new(4, 5, 4), nil, true)
		record.Body.Anchored = true
		ItemService.setState(record, "Machine")
		local before = record.Model:GetPivot().Position
		ItemService.eject(record, Vector3.new(0, 10, 8))
		T.eq(record.State, "Loose", "loose again")
		T.falsy(record.Body.Anchored, "unanchored")
		local after = record.Model:GetPivot().Position
		T.near((after - (before + Vector3.new(0, 1.5, 0))).Magnitude, 0, 1e-4, "lifted 1.5 studs")
		T.near((record.ReleasePos - after).Magnitude, 0, 1e-4, "new release point")
	end)
end
