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

	withWorld("ItemService: storeDesc may overfill the pen up to the DataStore cap and pays beyond it", function(w)
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
		-- system moves (leaving, the loose cap) still keep the item past the capacity
		T.eq(ItemService.storeDesc(w.player, d, "Too many loose items"), "Stored", "kept past the pen capacity")
		T.eq(#w.data.Storage, capacity + 1, "pen overfilled by one")
		for _ = #w.data.Storage + 1, GameConfig.MaxStoredItems do
			table.insert(w.data.Storage, clean())
		end
		local coins = w.data.Coins
		T.eq(ItemService.storeDesc(w.player, d, "Too many loose items"), "Sold", "sold at the DataStore cap")
		local value = ItemData.value("Clean", "Copper", "Flawless")
		T.eq(w.data.Coins, coins + value, "paid the full value")
		T.eq(w.data.TotalEarned, value, "counted as earned")
		T.eq(#w.data.Storage, GameConfig.MaxStoredItems, "never over the DataStore cap")
		T.eq(w.notes[3].Payload.Text, `Too many loose items (no room left anywhere: sold it for {Format.money(value)})`, "sold toast")
		-- the sell bonus counts here too (the same as Tobin's counter)
		local Bonuses = Loader.requirePath("ServerScriptService.Server.Bonuses")
		Bonuses.register("ItemSpecSell", function()
			return { SellPct = 0.35 }
		end)
		local before = w.data.Coins
		local okSell, why = pcall(function()
			T.eq(ItemService.storeDesc(w.player, d), "Sold", "sold again")
			T.eq(w.data.Coins, before + math.floor(value * 1.35 + 0.5), "pen-full sale pays the sell bonus")
		end)
		Bonuses.unregister("ItemSpecSell")
		if not okSell then
			error(why, 0)
		end
		-- a pen upgrade raises the capacity; the DataStore cap always wins
		w.data.Upgrades.PenLevel = 2
		T.eq(ItemService.penCapacity(w.data), capacity + 2 * EconomyConfig.Pen.PerLevel, "upgraded pen")
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

	withWorld("ItemService: dirty ore replicates no value, no ore id and a neutral name (rarity stays hidden)", function(w)
		local raw = ItemService.spawnDesc({ K = "Raw", O = "Diamond" }, USER, CFrame.new(0, 5, 0))
		T.eq(raw.Model:GetAttribute("Value"), nil, "no raw Value attribute (clients read nil as 0)")
		T.eq(raw.Model:GetAttribute("OreId"), nil, "no OreId attribute on dirty ore")
		T.eq(raw.Model.Name, "Raw", "a neutral model name (not Raw_Diamond)")
		T.eq(raw.Model:GetAttribute("Kind"), "Raw", "kind")
		T.eq(raw.OreId, "Diamond", "the server still knows the ore")
		T.eq(ItemService.descOf(raw).O, "Diamond", "and stores / sells / cleans it as that ore")
		for _, belt in { true, false } do
			local other = ItemService.spawnDesc({ K = "Raw", O = "Coal" }, USER, CFrame.new(4, 5, 0), nil, belt)
			T.eq(other.Model.Name, raw.Model.Name, "every dirty ore has the same name")
			T.eq(other.Model:GetAttribute("OreId"), nil, "no ore id on belts either")
		end
		local cleaned = ItemService.spawnDesc(clean("Clean"), USER, CFrame.new(2, 5, 0))
		T.eq(cleaned.Model:GetAttribute("Value"), ItemData.value("Clean", "Copper", "Clean"), "clean ore shows its value")
		T.eq(cleaned.Model:GetAttribute("OreId"), "Copper", "clean ore shows its ore")
		T.eq(cleaned.Model:GetAttribute("ItemId"), nil, "no id attribute (only the server uses ids)")
		-- a full pen keeps dirty ore (never sold behind the player's back) ...
		for _ = 1, ItemService.penCapacity(w.data) do
			table.insert(w.data.Storage, clean())
		end
		T.eq(ItemService.stash(raw, nil), true, "kept past the pen capacity")
		-- ... and only the DataStore cap pays the real raw price
		for _ = #w.data.Storage + 1, GameConfig.MaxStoredItems do
			table.insert(w.data.Storage, clean())
		end
		local raw2 = ItemService.spawnDesc({ K = "Raw", O = "Diamond" }, USER, CFrame.new(0, 5, 0))
		local coins = w.data.Coins
		T.eq(ItemService.stash(raw2, nil), false, "sold, not kept")
		T.eq(w.data.Coins, coins + ItemData.value("Raw", "Diamond"), "raw price")
	end)

	withWorld("ItemService: items at home and items in the mine have their own loose caps (compat #4)", function(w)
		local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
		local home = WorldLayout.plotCFrame(WorldLayout.Plots[1])
		T.truthy(ItemService.onBase(home.Position + Vector3.new(0, 3, 0)), "a plot's middle is a base")
		local cap = GameConfig.MaxLooseItemsPerPlayer
		-- a busy factory: belt items at home
		for i = 1, cap + 4 do
			ItemService.spawnDesc(clean(), USER, home * CFrame.new((i % 10) - 5, 3, math.floor(i / 10)), nil, true)
		end
		T.eq(ItemService.looseCount(USER, "Base"), cap + 4, "all at home")
		T.eq(ItemService.looseCount(USER, "Away"), 0, "none in the mine")
		T.falsy(ItemService.atLooseCap(USER), "a busy factory never stops your mining")
		-- ore left lying in the mine (far from every base)
		local far = Vector3.new(0, 5, 0)
		T.falsy(ItemService.onBase(far), "the test spot is away from bases")
		for i = 1, cap do
			ItemService.spawnDesc(clean(), USER, CFrame.new(far + Vector3.new(i, 0, 0)))
		end
		T.truthy(ItemService.atLooseCap(USER), "the mine's cap: rocks stop giving ore")
		T.eq(ItemService.looseCount(USER, "Base"), cap + 4, "and the factory's count didn't grow")
		T.eq(ItemService.looseCount(USER), 2 * cap + 4, "all of them")
	end)

	withWorld("ItemService: stash and the loose cap keep every item", function(w)
		local record = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		T.truthy(ItemService.stash(record, "Your item landed on another forge"), "stashed")
		T.eq(record.State, "Consumed", "gone from the world")
		T.eq(#w.data.Storage, 1, "in storage")
		T.eq(w.notes[1].Payload.Text, "Your item landed on another forge (moved to your Ore Pen)", "toast")

		-- the loose cap: nothing is moved into the pen behind your back any
		-- more (the sources stop instead: atLooseCap, MiningService)
		local cap = GameConfig.MaxLooseItemsPerPlayer
		for i = 1, cap - 1 do
			ItemService.spawnDesc(clean(), USER, CFrame.new(i, 5, 0))
		end
		T.falsy(ItemService.atLooseCap(USER), "one below the cap")
		ItemService.spawnDesc(clean(), USER, CFrame.new(cap, 5, 0))
		T.truthy(ItemService.atLooseCap(USER), "at the cap")
		for i = 1, 2 do
			ItemService.spawnDesc(clean(), USER, CFrame.new(cap + i, 5, 0))
		end
		T.eq(ItemService.looseCount(USER), cap + 2, "every item stays where it is")
		T.eq(#w.data.Storage, 1, "nothing went into the pen")
		for _, note in w.notes do
			T.falsy(tostring(note.Payload and note.Payload.Text):find("Too many loose", 1, true), "no loose-cap toast")
		end
		T.falsy(ItemService.atLooseCap(USER + 1), "nobody else is at the cap")

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
	---------------------------------------------------------------- ids, looks, the pool (perf audit #3/#4)

	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")

	local function partsOf(model: any): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- destroyed (Lune errors where Roblox reads a destroyed Parent as nil)
	local function gone(instance: any): boolean
		local ok, parent = pcall(function()
			return instance.Parent
		end)
		return not ok or parent == nil
	end

	local function weldsOf(model: any): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("WeldConstraint") then
				n += 1
			end
		end
		return n
	end

	T.test("ItemBuilder.buildLight: every ore and kind fits 3 parts with the full look's Body", function()
		local ItemBuilderL = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
		local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
		local cf = CFrame.new(3, 4, 5)
		local function count(model: any): (number, number)
			local parts, extras = 0, 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
					extras += 1
				end
			end
			return parts, extras
		end
		local recipes = {}
		for _, recipe in ItemData.Recipes do
			table.insert(recipes, recipe.Id)
		end
		for _, ore in OreData.List do
			local infos: { any } = {
				{ Kind = "Raw", OreId = ore.Id },
				{ Kind = "Clean", OreId = ore.Id, Grade = "Flawless" },
				{ Kind = "Clean", OreId = ore.Id, Grade = "Rough" },
				{ Kind = "Crushed", OreId = ore.Id },
				{ Kind = "Ingot", OreId = ore.Id, Grade = "Flawless" },
				{ Kind = "Alloy", OreId = ore.Id },
			}
			for _, recipe in recipes do
				table.insert(infos, { Kind = "Gear", OreId = ore.Id, Recipe = recipe })
			end
			for _, info in infos do
				local label = `{info.Kind} {ore.Id} {info.Grade or info.Recipe or ""}`
				local light = ItemBuilderL.buildLight(info, cf, 7)
				local full = ItemBuilderL.build(info, cf, 7)
				local parts, extras = count(light)
				T.le(parts, ItemBuilderL.LightBudget, label .. ": light parts")
				T.eq(extras, 0, label .. ": no sparkles or lights on belts")
				local a, b = light.PrimaryPart, full.PrimaryPart
				T.eq(a.Name, "Body", label .. ": a Body")
				T.near((a.Size - b.Size).Magnitude, 0, 1e-4, label .. ": the same Body size")
				T.near((a.CFrame.Position - b.CFrame.Position).Magnitude, 0, 1e-4, label .. ": at the same spot")
				T.truthy(a.CanCollide, label .. ": the Body collides")
				for _, d in light:GetDescendants() do
					if d:IsA("BasePart") and d ~= a then
						T.falsy(d.CanCollide, label .. ": decor never collides")
						T.truthy(d.Massless, label .. ": decor is massless")
					end
				end
			end
		end
		-- dirty ore on a belt looks the same for every ore but its glint
		local gold = ItemBuilderL.buildLight({ Kind = "Raw", OreId = "Gold" }, cf, 3)
		local coal = ItemBuilderL.buildLight({ Kind = "Raw", OreId = "Coal" }, cf, 3)
		T.eq(gold.PrimaryPart.Color, coal.PrimaryPart.Color, "the same crust")
		T.eq(gold.PrimaryPart.Size, coal.PrimaryPart.Size, "the same size")
	end)

	withWorld("ItemService: short numeric ids, only used on the server", function(w)
		local a = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		local b = ItemService.spawnDesc(clean(), USER, CFrame.new(2, 5, 0))
		T.eq(type(a.Id), "number", "a number, not a GUID")
		T.truthy(a.Id ~= b.Id, "unique")
		T.truthy(ItemService.getById(b.Id) == b, "getById")
		T.eq(w.ids, 0, "no GUID generated")
		for _, name in { "ItemId", "Grade", "Recipe" } do
			T.eq(a.Model:GetAttribute(name), if name == "Grade" then "Rough" else nil, name)
		end
		local count = 0
		for _ in a.Model:GetAttributes() do
			count += 1
		end
		T.le(count, 6, "at most Kind, OreId, Grade, Owner, State, Value")
	end)

	withWorld("ItemService: belt items wear the light look (<= 3 parts); dress switches it in place", function(w)
		local kinds: { any } = {
			{ K = "Raw", O = "Gold" },
			{ K = "Clean", O = "Diamond", G = "Flawless" },
			{ K = "Crushed", O = "Iron" },
			{ K = "Ingot", O = "Copper", G = "Flawless" },
			{ K = "Alloy", O = "Copper" },
			{ K = "Gear", O = "Iron", R = "Helm" },
			{ K = "Gear", O = "Iron", R = "Greatsword" },
			{ K = "Gear", O = "Iron", R = "ToolHead" },
		}
		for _, desc in kinds do
			local label = `{desc.K} {desc.O} {desc.R or ""}`
			local belt = ItemService.spawnDesc(desc, USER, CFrame.new(0, 5, 0), nil, true)
			T.truthy(belt.Light, label .. ": machine / chute spawns are light")
			T.le(#partsOf(belt.Model), ItemBuilder.LightBudget, label .. ": at most 3 parts on belts")
			T.le(weldsOf(belt.Model), ItemBuilder.LightBudget - 1, label .. ": at most 2 welds")
			local body = belt.Body
			local size = body.Size
			-- picked up: the full look on the same model and body
			T.truthy(ItemService.dress(belt, false), label .. ": dressed")
			T.falsy(belt.Light, label .. ": full now")
			T.truthy(belt.Body == body and belt.Model.PrimaryPart == body, label .. ": the same Body")
			T.near((belt.Body.Size - size).Magnitude, 0, 1e-4, label .. ": the same physics box")
			local full = ItemBuilder.build({ Kind = desc.K, OreId = desc.O, Grade = desc.G, Recipe = desc.R }, CFrame.new(), belt.Id)
			T.eq(#partsOf(belt.Model), #partsOf(full), label .. ": every part of the full look")
			T.eq(weldsOf(belt.Model), #partsOf(full) - 1, label .. ": every decor part welded")
			for _, part in partsOf(belt.Model) do
				T.eq(part.CollisionGroup, ItemService.ItemGroup, label .. ": items group")
			end
			T.falsy(ItemService.dress(belt, false), label .. ": already full")
			-- hand-spawned items are full from the start
			local hand = ItemService.spawnDesc(desc, USER, CFrame.new(0, 5, 0))
			T.falsy(hand.Light, label .. ": hand spawns are full")
		end
		local gone = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0), nil, true)
		ItemService.destroy(gone)
		T.falsy(ItemService.dress(gone, false), "a consumed item is never dressed")
	end)

	withWorld("ItemService: a machine taking a belt item parks its model; the next belt spawn nearby wears it", function(w)
		local world = roblox.Instance.new("Folder")
		ItemService._test.setFolder(world)
		local pool = ItemService.Pool
		local raw = ItemService.spawnDesc({ K = "Raw", O = "Gold" }, USER, CFrame.new(0, 5, 0), nil, true)
		local model, body = raw.Model, raw.Body
		T.truthy(model.Parent == world, "in the items folder")
		T.truthy(model:HasTag("Item"), "tagged for clients")
		local desc = ItemService.absorb(raw)
		T.eq(desc.O, "Gold", "absorbed as gold")
		T.eq(raw.State, "Consumed", "the record is gone")
		T.eq(ItemService.looseCount(USER), 0, "nothing loose")
		T.truthy(model.Parent == world, "the model stays (parked)")
		T.falsy(model:HasTag("Item"), "clients ignore a parked model")
		for _, part in partsOf(model) do
			T.eq(part.Transparency, 1, "hidden")
			T.truthy(part.Anchored, "anchored")
			T.falsy(part.CanCollide or part.CanQuery or part.CanTouch, "no collision, query or touch")
		end
		T.eq(ItemService._test.parked(USER), 1, "one parked model")
		-- the machine's output: the same model, re-dressed as the new item
		local crushed = ItemService.spawnDesc({ K = "Crushed", O = "Gold" }, USER, CFrame.new(4, 5, 0), nil, true)
		T.truthy(crushed.Model == model and crushed.Body == body, "the parked model is worn again")
		T.eq(ItemService._test.parked(USER), 0, "out of the pool")
		T.truthy(model:HasTag("Item"), "tagged again")
		T.eq(model:GetAttribute("Kind"), "Crushed", "new kind")
		T.eq(model:GetAttribute("OreId"), "Gold", "crushed ore shows its ore")
		T.eq(model.Name, "Crushed_Gold", "named for its look")
		T.le(#partsOf(model), ItemBuilder.LightBudget, "light look")
		T.near((body.CFrame.Position - Vector3.new(4, 5, 0)).Magnitude, 0, 1e-3, "moved to the output")
		for _, part in partsOf(model) do
			T.falsy(part.Anchored, "unanchored")
			T.eq(part.CanCollide, part == body, "only the Body collides")
			T.truthy(part.CanQuery, "clickable")
			T.truthy(part.Transparency < 1 or part == body and body.Transparency == 1, "visible again")
		end
		T.eq(crushed.State, "Loose", "loose")
		T.truthy(crushed.Id ~= raw.Id, "a new id")
		T.truthy(ItemService.get(model) == crushed, "the model maps to the new record")
		-- the same look: shown again exactly as it was (no rebuild)
		-- (Lune hands out a new wrapper per lookup: compare in order, by look)
		local before = {}
		for _, part in partsOf(model) do
			table.insert(before, { Color = part.Color, Size = part.Size, Transparency = part.Transparency })
		end
		ItemService.absorb(crushed)
		local again = ItemService.spawnDesc({ K = "Crushed", O = "Gold" }, USER, CFrame.new(2, 5, 0), nil, true)
		T.truthy(again.Model == model, "worn again")
		local after = partsOf(model)
		T.eq(#after, #before, "the same parts")
		for i, part in after do
			T.truthy(part.Color == before[i].Color and part.Size == before[i].Size, "the very same look " .. i)
			T.eq(part.Transparency, before[i].Transparency, "transparency restored " .. i)
		end
		-- dirty ore re-used from a clean model loses the clean ore's attributes
		ItemService.absorb(again)
		local dirty = ItemService.spawnDesc({ K = "Raw", O = "Diamond" }, USER, CFrame.new(1, 5, 0), nil, true)
		T.truthy(dirty.Model == model, "worn again")
		T.eq(model:GetAttribute("OreId"), nil, "no ore id left over")
		T.eq(model:GetAttribute("Value"), nil, "no value left over")
		T.eq(model.Name, "Raw", "neutral name")
		-- too far away, someone else's, or a hand spawn: a new model
		ItemService.absorb(dirty)
		local far = ItemService.spawnDesc(clean(), USER, CFrame.new(pool.Reach + 10, 5, 0), nil, true)
		T.truthy(far.Model ~= model, "beyond Reach: a new model")
		local hand = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		T.truthy(hand.Model ~= model, "a hand spawn never wears a parked belt model")
		local theirs = ItemService.spawnDesc(clean(), USER + 1, CFrame.new(0, 5, 0), nil, true)
		T.truthy(theirs.Model ~= model, "never another player's model")
		T.eq(ItemService._test.parked(USER), 1, "still parked")
		-- a full (hand) item taken by a machine is destroyed, not parked
		ItemService.absorb(hand)
		T.truthy(gone(hand.Model), "full items go")
		-- parked models expire after Pool.Keep
		ItemService.maintainAll(os.clock() + pool.Keep + 1)
		T.eq(ItemService._test.parked(USER), 0, "expired")
		T.truthy(gone(model), "destroyed")
		-- at most Pool.Max per owner
		for i = 1, pool.Max + 3 do
			local r = ItemService.spawnDesc(clean(), USER, CFrame.new(i * 100, 5, 0), nil, true)
			ItemService.absorb(r)
		end
		T.eq(ItemService._test.parked(USER), pool.Max, "the pool holds at most Max")
	end)

	withWorld("ItemService: consumed records can't be mounted, released or re-stated; CarryService hears consumed carried ones", function(w)
		local heard = {}
		ItemService.onCarriedConsumed(function(record)
			table.insert(heard, record)
		end)
		local world = roblox.Instance.new("Folder")
		local carried = ItemService.spawnDesc({ K = "Raw", O = "Gold" }, USER, CFrame.new(0, 5, 0))
		carried.Model.Parent = world
		T.truthy(ItemService.setState(carried, "Carried"), "carried")
		-- the engine destroys it (the owner fell into the void with it)
		carried.Model.Parent = nil
		ItemService._test.maintain(carried, os.clock())
		T.eq(carried.State, "Consumed", "consumed")
		T.eq(#heard, 1, "CarryService heard it")
		T.truthy(heard[1] == carried, "about that record")
		T.eq(#w.data.Storage, 1, "kept in the pen once")
		T.falsy(ItemService.setState(carried, "Machine"), "no new state")
		T.eq(carried.State, "Consumed", "still consumed")
		T.falsy(ItemService.mount(carried, CFrame.new()), "no mount")
		T.falsy(ItemService.release(carried, CFrame.new()), "no release")
		T.falsy(ItemService.eject(carried, Vector3.zero), "no eject")
		T.eq(ItemService.looseCount(USER), 0, "never loose again")
		-- consuming a loose item doesn't bother CarryService
		local loose = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		ItemService.absorb(loose)
		T.eq(#heard, 1, "only carried ones")
		-- a broken listener never breaks the caller
		ItemService.onCarriedConsumed(function()
			error("boom")
		end)
		local other = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		ItemService.setState(other, "Carried")
		T.truthy(pcall(ItemService.absorb, other), "absorb still works")
		T.eq(other.State, "Consumed", "consumed")
	end)

	withWorld("ItemService: hand-back caps the client's speed and checks the height (Security #8)", function(w)
		local world = roblox.Instance.new("Folder")
		local function thrown(at: any): any
			local r = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
			r.Model.Parent = world
			r.Body.CFrame = CFrame.new(at)
			r.ClientOwnedUntil = os.clock() - 1
			return r
		end
		-- a client flung it: the server keeps at most HandBackSpeed / HandBackSpin
		local flung = thrown(Vector3.new(10, 1, 0))
		flung.Body.AssemblyLinearVelocity = Vector3.new(900, 50, 0)
		flung.Body.AssemblyAngularVelocity = Vector3.new(0, 300, 0)
		ItemService._test.maintain(flung, os.clock())
		T.eq(flung.ClientOwnedUntil, nil, "the server has it")
		T.le(flung.Body.AssemblyLinearVelocity.Magnitude, ItemService.HandBackSpeed + 1e-4, "speed capped")
		T.le(flung.Body.AssemblyAngularVelocity.Magnitude, ItemService.HandBackSpin + 1e-4, "spin capped")
		local slow = thrown(Vector3.new(10, 1, 0))
		slow.Body.AssemblyLinearVelocity = Vector3.new(3, 0, 0)
		ItemService._test.maintain(slow, os.clock())
		T.near(slow.Body.AssemblyLinearVelocity.X, 3, 1e-4, "a slow roll is kept")
		local broken = thrown(Vector3.new(10, 1, 0))
		broken.Body.AssemblyLinearVelocity = Vector3.new(0 / 0, 0, 0)
		ItemService._test.maintain(broken, os.clock())
		T.eq(broken.Body.AssemblyLinearVelocity.Magnitude, 0, "a broken speed is zeroed")
		-- carried onto a roof: higher than any throw reaches -> back to the owner
		local rise = ItemService.riseLimit(slow)
		T.truthy(rise > 10 and rise < 40, "a throw's height (" .. rise .. ")")
		local roof = thrown(Vector3.new(5, 5 + rise + 4, 0))
		ItemService._test.maintain(roof, os.clock())
		local rescue = (w.root.CFrame * CFrame.new(0, 2, -4)).Position
		T.near((roof.Body.CFrame.Position - rescue).Magnitude, 0, 1e-3, "too high: back at the owner")
		local ledge = thrown(Vector3.new(5, 5 + rise - 2, 0))
		ItemService._test.maintain(ledge, os.clock())
		T.near(ledge.Body.CFrame.Position.Y, 5 + rise - 2, 1e-3, "a plausible height stays")
		-- isTrusted checks the height too
		local high = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		high.Body.CFrame = CFrame.new(1, 5 + rise + 2, 0)
		T.falsy(ItemService.isTrusted(high, high.ReleasedAt + 2), "too high to trust")
		high.Body.CFrame = CFrame.new(1, 4, 0)
		T.truthy(ItemService.isTrusted(high, high.ReleasedAt + 2), "on the ground: trusted")
	end)

	withWorld("ItemService: queued items sleep (anchored) and wake when the queue moves", function(w)
		local world = roblox.Instance.new("Folder")
		ItemService._test.setFolder(world)
		local front = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0), nil, true)
		local behind = ItemService.spawnDesc(clean(), USER, CFrame.new(2, 5, 0), nil, true)
		local farAway = ItemService.spawnDesc(clean(), USER, CFrame.new(60, 5, 0), nil, true)
		for _, r in { front, behind, farAway } do
			T.truthy(ItemService.sleep(r), "asleep")
			for _, part in partsOf(r.Model) do
				T.truthy(part.Anchored, "anchored")
			end
		end
		T.truthy(ItemService.sleep(behind), "sleeping twice is fine")
		local client = ItemService.spawnDesc(clean(), USER, CFrame.new(0, 5, 0))
		T.falsy(ItemService.sleep(client), "never while a client simulates it")
		-- the machine takes the front one: the queue behind it wakes
		ItemService.absorb(front)
		T.eq(behind.Asleep, nil, "the next in line wakes")
		T.falsy(behind.Body.Anchored, "and can move")
		T.truthy(farAway.Asleep, "far away: still asleep")
		-- nothing sleeps for ever (a belt taken away under it)
		ItemService._test.maintain(farAway, (farAway.Asleep :: number) + ItemService.SleepMax + 0.1)
		T.eq(farAway.Asleep, nil, "woken after SleepMax")
		T.falsy(farAway.Body.Anchored, "unanchored")
		-- picked up, released or carried: awake
		ItemService.sleep(behind)
		ItemService.release(behind, CFrame.new(0, 5, 0))
		T.eq(behind.Asleep, nil, "released: awake")
		T.falsy(behind.Body.Anchored, "unanchored")
		T.eq(ItemService.wakeNear(USER, Vector3.zero, 100), 0, "nobody left asleep")
	end)

	withWorld("ItemService: ore left far behind or stuck in the mine goes into the pen at the cap (review)", function(w)
		local world = roblox.Instance.new("Folder")
		local cap = GameConfig.MaxLooseItemsPerPlayer
		local t0 = os.clock()
		local function spawnAt(position: any): any
			local r = ItemService.spawnDesc(clean(), USER, CFrame.new(position))
			r.Model.Parent = world
			return r
		end
		-- the owner stands at the origin; 25 chunks lie far away in the mine, 5 wedged 20 studs off,
		-- 1 right at the owner's feet: 31 away from bases, one over the cap
		w.moveOwner(Vector3.new(0, 3, 0))
		local farOnes, nearOnes = {}, {}
		for i = 1, 25 do
			table.insert(farOnes, spawnAt(Vector3.new(400 + i * 2, 5, 0)))
		end
		for i = 1, 5 do
			table.insert(nearOnes, spawnAt(Vector3.new(20, 5, i * 2)))
		end
		local feet = spawnAt(Vector3.new(1, 3, 0))
		T.truthy(ItemService.atLooseCap(USER), "at the mine's cap: rocks hold")
		-- not long enough yet: nothing moves
		ItemService.maintainAll(t0 + 30)
		T.eq(ItemService.looseCount(USER, "Away"), cap + 1, "nothing rescued after 30 s")
		-- 90 s later the far ones count as left behind: the oldest 2 go, back under the cap
		ItemService.maintainAll(t0 + ItemService.StaleAwaySeconds + 5)
		T.eq(ItemService.looseCount(USER, "Away"), cap - 1, "back under the cap")
		T.falsy(ItemService.atLooseCap(USER), "rocks give ore again")
		T.eq(farOnes[1].State, "Consumed", "the oldest went")
		T.eq(farOnes[2].State, "Consumed")
		T.eq(farOnes[3].State, "Loose", "only as many as needed")
		T.eq(#w.data.Storage, 2, "into the pen, nothing lost")
		local last = w.notes[#w.notes]
		T.truthy(last.Payload.Text:find("2 ore you left lying in the mine", 1, true), "one toast says so")
		-- the player walks over to the far ones: only the stuck rule is left
		w.moveOwner(Vector3.new(420, 3, 0))
		for i = 1, 2 do
			table.insert(farOnes, spawnAt(Vector3.new(440 + i, 5, 0)))
		end
		T.truthy(ItemService.atLooseCap(USER), "at the cap again")
		ItemService.maintainAll(t0 + ItemService.StaleAwaySeconds + 10)
		T.truthy(ItemService.atLooseCap(USER), "everything is near the owner now: nothing rescued")
		-- 3 minutes after they were dropped, chunks still out of grab reach count as stuck;
		-- the very oldest one lies at the owner's feet: never taken
		local atFeet = spawnAt(Vector3.new(421, 3, 0))
		atFeet.CreatedAt = t0 - 1000
		ItemService.maintainAll(t0 + ItemService.StuckSeconds + 10)
		T.falsy(ItemService.atLooseCap(USER), "stuck ones rescued")
		T.eq(atFeet.State, "Loose", "nothing within grab reach is ever taken")
		T.eq(feet.State, "Loose", "the next oldest out-of-reach ones went first")
	end)

	withWorld("ItemService: one maintenance pass looks each owner up once (perf audit #10)", function(w)
		local world = roblox.Instance.new("Folder")
		for i = 1, 12 do
			local r = ItemService.spawnDesc(clean(), USER, CFrame.new(i, 5, 0), nil, true)
			r.Model.Parent = world
		end
		local lookups = 0
		local get = Players.GetPlayerByUserId
		rawset(Players, "GetPlayerByUserId", function(self, id)
			lookups += 1
			return get(self, id)
		end)
		local ok, err = pcall(ItemService.maintainAll, os.clock())
		rawset(Players, "GetPlayerByUserId", get)
		if not ok then
			error(err, 0)
		end
		T.eq(lookups, 1, "one lookup for 12 items of one owner")
		for _, r in ItemService.ownedBy(USER) do
			T.near(r.LastNearOwner, os.clock(), 1, "near-owner time kept up to date")
		end
	end)
end
