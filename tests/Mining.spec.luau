-- MiningService under Lune: rocks with 1-3 server-side ores, beam damage per
-- server tick (dt capped at MaxTickGap), range / equip / blaster gate / VIP
-- refusals with throttled toasts, stage drops and chunk owners, bad MineBlast
-- input, respawns. Players, save data, ItemService and Net are small fakes;
-- the rock model is a simple fake so the ore package can restyle buildRock.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local MiningService = Loader.requirePath("ServerScriptService.Server.Services.MiningService")

	local mining = MiningService._test
	local realBuildRock, realApplyStage = OreNodeBuilder.buildRock, OreNodeBuilder.applyStage
	local Beam = BlasterData.Beam
	local TICK = Beam.ServerTick

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

	-- A rock model like OreNodeBuilder.buildRock makes (one 4x3x4 block).
	local function fakeRock(zoneId: string, oreIds: { string }, base: any, _seed: any): any
		local model = Instance.new("Model")
		model.Name = "Rock"
		local body = Instance.new("Part")
		body.Name = "Rock1"
		body.Size = Vector3.new(4, 3, 4)
		body.CFrame = base * CFrame.new(0, 1.5, 0)
		body.CanCollide = true
		body.Parent = model
		model.PrimaryPart = body
		model:SetAttribute("Zone", zoneId)
		model:SetAttribute("OreCount", #oreIds)
		model:SetAttribute("Stage", 0)
		return model
	end

	local function fakePlayer(w: any, userId: number): any
		local p: any = { UserId = userId, Name = "Miner" .. userId, Parent = true, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.root = { Position = Vector3.new(6, 3, 0) }
		p.humanoid = { Health = 100 }
		p.tool = {
			Name = "Blaster",
			IsA = function(_, className: string)
				return className == "Tool"
			end,
		}
		p.equipped = true
		p.Character = {
			FindFirstChildOfClass = function(_, className: string)
				return if className == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name: string)
				if name == "HumanoidRootPart" then
					return p.root
				elseif name == "Blaster" and p.equipped then
					return p.tool
				end
				return nil
			end,
		}
		p.data = deepCopy(DataTemplate)
		w.byPlayer[p] = p.data
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, spawned = {}, changed = 0, mined = {}, stages = {}, now = 100, rolls = {}, byPlayer = {} }
		w.folder = Instance.new("Folder")
		w.markers = Instance.new("Folder")
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return w.byPlayer[p]
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, ...)
			table.insert(w.notes, { Name = name, Player = p, Args = { ... } })
		end)
		patch(Net, "fireNear", function(name, position, radius, except, ...)
			table.insert(w.notes, { Name = name, Position = position, Radius = radius, Except = except, Args = { ... } })
		end)
		patch(ItemService, "spawn", function(info, owner, cf, velocity)
			table.insert(w.spawned, { Info = info, Owner = owner, CFrame = cf, Velocity = velocity })
			return nil
		end)
		patch(OreNodeBuilder, "buildRock", fakeRock)
		patch(OreNodeBuilder, "applyStage", function(model, stage, _seed)
			table.insert(w.stages, { Model = model, Stage = stage })
			return {}
		end)
		mining.reset(w.folder)
		mining.setClock(function()
			return w.now
		end)
		-- rolls are used in order; 0.5 when the list runs out
		mining.setRandom(function()
			return if #w.rolls > 0 then table.remove(w.rolls, 1) else 0.5
		end)
		MiningService.onChunkMined(function(p, oreId, count)
			table.insert(w.mined, { Player = p, OreId = oreId, Count = count })
		end)
		w.player = fakePlayer(w, 501)
		w.other = fakePlayer(w, 502)
		w.restore = function()
			mining.reset(nil)
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		-- a rock of `zoneId` at the origin (center at y = 1.5); `ores` replaces the roll
		w.rock = function(zoneId: string, ores: { string }?, health: number?, position: any?): any
			local marker = Instance.new("Part")
			marker.Size = Vector3.new(2, 2, 2)
			marker.CFrame = CFrame.new((position or Vector3.new(0, 0, 0)) + Vector3.new(0, 1, 0))
			marker:SetAttribute("Zone", zoneId)
			marker.Parent = w.markers
			local rock = mining.spawnRock(marker)
			T.truthy(rock, "spawned a rock in " .. zoneId)
			if ores then
				rock.Ores = ores
			end
			if health then
				rock.Health = health
				rock.MaxHealth = health
			end
			return rock
		end
		-- one server tick `seconds` later
		w.step = function(seconds: number?)
			w.now += seconds or TICK
			mining.tick(w.now)
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

	local function count(w: any, name: string, kind: string?): number
		local n = 0
		for _, note in w.notes do
			if note.Name == name and (not kind or note.Args[1] == kind) then
				n += 1
			end
		end
		return n
	end

	local function last(w: any, name: string, kind: string?): any
		for i = #w.notes, 1, -1 do
			local note = w.notes[i]
			if note.Name == name and (not kind or note.Args[1] == kind) then
				return note
			end
		end
		return nil
	end

	-- Lune errors on a destroyed instance where Roblox shows Parent = nil.
	local function destroyed(instance: any): boolean
		local ok, parent = pcall(function()
			return instance.Parent
		end)
		return not ok or parent == nil
	end

	-- No payload sent to clients names an ore (dirty ore is unknown until cleaned).
	local function noOreLeaks(w: any)
		local function check(value: any, depth: number)
			if type(value) == "string" then
				T.falsy(OreData.ById[value], "an ore id was sent to a client: " .. value)
			elseif type(value) == "table" and depth < 3 and value.UserId == nil then -- (fake players hold their save)
				for k, v in value do
					check(k, depth + 1)
					check(v, depth + 1)
				end
			end
		end
		for _, note in w.notes do
			check(note.Args, 0)
		end
	end

	withWorld("Mining: rocks roll 1-3 ores by zone weights and keep them on the server", function(w)
		local seen = {}
		local zone = WorldLayout.ZoneById.Quarry
		for i = 1, 120 do
			w.rolls = { (i % 20) / 20 } -- the ore count roll, the rest are 0.5
			local rock = w.rock("Quarry")
			local ores = rock.Ores
			T.truthy(#ores >= 1 and #ores <= 3, "1-3 ores")
			T.eq(#ores, BlasterData.oreCount((i % 20) / 20), "oreCount decides")
			seen[#ores] = true
			for _, oreId in ores do
				T.truthy(zone.Ores[oreId], oreId .. " is a quarry ore")
			end
			local model = rock.Model
			T.eq(rock.MaxHealth, BlasterData.rockHealth(zone.RockHealth, ores), "rock HP")
			T.eq(model:GetAttribute("Health"), rock.MaxHealth)
			T.eq(model:GetAttribute("MaxHealth"), rock.MaxHealth)
			T.eq(model:GetAttribute("OreCount"), #ores)
			T.eq(model:GetAttribute("MinBlaster"), zone.MinBlaster)
			T.eq(model:GetAttribute("Zone"), "Quarry")
			T.eq(model:GetAttribute("OreId"), nil, "no ore id on the model")
			for _, attribute in model:GetAttributes() do
				T.falsy(type(attribute) == "string" and OreData.ById[attribute], "no ore id in any attribute")
			end
			T.truthy(model:HasTag(MiningService.RockTag), "tagged")
			T.truthy(model.Parent == w.folder, "in the rocks folder")
			T.truthy(model.PrimaryPart.Anchored, "anchored")
		end
		T.truthy(seen[1] and seen[2] and seen[3], "every ore count happens")
		-- ore rolls walk the zone's weights in name order: roll 0 is the first ore
		w.rolls = { 0, 0 }
		local low = w.rock("Quarry")
		T.eq(low.Ores[1], "Bronze", "lowest roll = first ore by name")
		-- zones without ores grow nothing
		local marker = Instance.new("Part")
		marker:SetAttribute("Zone", "Emberfall")
		T.eq(mining.spawnRock(marker), nil, "no ores, no rock")
		marker:SetAttribute("Zone", "Nowhere")
		T.eq(mining.spawnRock(marker), nil, "unknown zone")
	end)

	withWorld("Mining: damage per tick is the blaster damage x dt, lag is capped at MaxTickGap", function(w)
		local rock = w.rock("Quarry", { "Coal" }, 10000)
		local p = w.player
		mining.blast(p, rock.Model)
		T.truthy(mining.target(p) == rock.Model, "target set")
		local dps = BlasterData.damage(1, "")
		w.step()
		T.near(rock.Health, 10000 - dps * TICK, 1e-6, "one tick")
		w.step()
		T.near(rock.Health, 10000 - dps * TICK * 2, 1e-6, "two ticks")
		w.step(5) -- a 5 s hitch only counts as MaxTickGap
		local expected = 10000 - dps * (TICK * 2 + Beam.MaxTickGap)
		T.near(rock.Health, expected, 1e-6, "capped")
		T.near(rock.Model:GetAttribute("Health"), expected, 1e-6, "Health attribute")
		mining.tick(w.now) -- the same moment again: dt = 0
		T.near(rock.Health, expected, 1e-6, "no damage at dt 0")
		-- a better blaster forged from gold
		p.data.BlasterLevel = 3
		p.data.BlasterOre = "Gold"
		w.step()
		expected -= BlasterData.damage(3, "Gold") * TICK
		T.near(rock.Health, expected, 1e-6, "level 3 gold")
		-- aiming at the same rock again keeps the clock; a new rock starts fresh
		w.now += 0.05
		mining.blast(p, rock.Model)
		w.step(0.05)
		expected -= BlasterData.damage(3, "Gold") * TICK
		T.near(rock.Health, expected, 1e-6, "same target keeps its tick clock")
		local second = w.rock("Quarry", { "Coal" }, 10000)
		w.now += 0.3
		mining.blast(p, second.Model)
		w.step()
		T.near(second.Health, 10000 - BlasterData.damage(3, "Gold") * TICK, 1e-6, "new target: dt from the switch")
		T.near(rock.Health, expected, 1e-6, "the old rock is left alone")
		-- stopping
		mining.blast(p, nil)
		T.eq(mining.target(p), nil, "stopped")
		w.step()
		T.near(second.Health, 10000 - BlasterData.damage(3, "Gold") * TICK, 1e-6, "no damage after stopping")
		-- hit effects for others: at most ~4 a second per rock, never to the shooter
		w.notes = {}
		mining.blast(p, rock.Model)
		for _ = 1, 20 do
			w.step()
		end
		local hits = count(w, "Fx", "BlastHit")
		T.truthy(hits >= 6 and hits <= 9, "BlastHit throttled over 2 s: " .. hits)
		local hit = last(w, "Fx", "BlastHit")
		T.truthy(hit.Except == p, "the shooter draws their own beam")
		T.eq(typeof(hit.Args[2]), "Vector3", "hit position")
		T.eq(typeof(hit.Args[3]), "Color3", "beam color")
		T.eq(hit.Args[3], OreData.ById.Gold.Glow, "gold beam")
		T.truthy(hit.Args[5] == p, "who is firing")
		noOreLeaks(w)
	end)

	withWorld("Mining: no damage out of range, unequipped, dead or without data", function(w)
		local rock = w.rock("Quarry", { "Coal" }, 1000)
		local p = w.player
		local reach = BlasterData.get(1).Range + Beam.RangeSlack + rock.Radius
		local function standAt(surface: number)
			-- root is 1.5 studs above the rock center: horizontal distance for a 3D distance
			local d = math.sqrt(math.max(surface, 0) ^ 2 - 1.5 ^ 2)
			p.root.Position = Vector3.new(d, 3, 0)
		end
		mining.blast(p, rock.Model)
		standAt(reach + 0.5)
		w.step()
		T.eq(rock.Health, 1000, "too far")
		standAt(reach - 0.5)
		w.step()
		T.near(rock.Health, 1000 - BlasterData.damage(1, "") * TICK, 1e-6, "just in range")
		local health = rock.Health
		p.equipped = false
		for _ = 1, 30 do
			w.step()
		end
		T.eq(rock.Health, health, "the blaster must be in hand")
		p.equipped = true
		w.step()
		T.near(rock.Health, health - BlasterData.damage(1, "") * TICK, 1e-6, "no burst after equipping again")
		health = rock.Health
		p.humanoid.Health = 0
		w.step()
		T.eq(rock.Health, health, "dead players don't blast")
		p.humanoid.Health = 100
		w.byPlayer[p] = nil
		w.step()
		T.eq(rock.Health, health, "no data, no damage")
		w.byPlayer[p] = p.data
		p.Character = nil
		w.step()
		T.eq(rock.Health, health, "no character")
		T.eq(count(w, "Notify"), 0, "no toasts for these")
	end)

	withWorld("Mining: the zone's MinBlaster gate refuses with one toast per rock per 3 s", function(w)
		local zone = WorldLayout.ZoneById.EmberCaves
		local rock = w.rock("EmberCaves", { "Bronze" }, 1000)
		local p = w.player
		mining.blast(p, rock.Model)
		w.step()
		T.eq(rock.Health, 1000, "level 1 can't hurt a cave rock")
		T.eq(count(w, "Notify"), 1, "one toast")
		local toast = last(w, "Notify")
		T.truthy(toast.Player == p, "to the shooter")
		T.eq(toast.Args[1].Text, "Needs a Level " .. zone.MinBlaster .. " blaster")
		T.eq(toast.Args[1].Kind, "Deny")
		T.eq(count(w, "Fx", "MineBounce"), 1, "bounce effect")
		T.eq(typeof(last(w, "Fx", "MineBounce").Args[2]), "Vector3")
		for _ = 1, 25 do
			w.step() -- 2.5 s more
		end
		T.eq(count(w, "Notify"), 1, "still one toast within 3 s")
		for _ = 1, 6 do
			w.step()
		end
		T.eq(count(w, "Notify"), 2, "the next toast after 3 s")
		-- another gated rock gets its own toast right away
		local other = w.rock("EmberCaves", { "Iron" }, 1000)
		mining.blast(p, other.Model)
		w.step()
		T.eq(count(w, "Notify"), 3, "a toast for the other rock")
		mining.blast(p, rock.Model)
		w.step()
		T.eq(count(w, "Notify"), 3, "back on the first rock: still throttled")
		-- a level-3 blaster can mine it
		p.data.BlasterLevel = zone.MinBlaster
		w.step()
		T.near(rock.Health, 1000 - BlasterData.damage(zone.MinBlaster, "") * TICK, 1e-6, "level 3 mines")
		noOreLeaks(w)
	end)

	withWorld("Mining: VIP zones need the ForgeVip perk", function(w)
		local zone = WorldLayout.ZoneById.Grotto
		T.truthy(zone.VipOnly, "the grotto is VIP")
		local rock = w.rock("Grotto", { "Silver" }, 1000)
		local p = w.player
		p.data.BlasterLevel = 10
		mining.blast(p, rock.Model)
		w.step()
		T.eq(rock.Health, 1000, "no perk, no damage")
		T.truthy(last(w, "Notify").Args[1].Text:find("VIP"), "VIP toast")
		p.attrs.Perk_ForgeVip = true
		w.step()
		T.near(rock.Health, 1000 - BlasterData.damage(10, "") * TICK, 1e-6, "VIPs mine")
	end)

	withWorld("Mining: stages drop the rolled ores (1, 2 or 3) to whoever crossed them", function(w)
		local dps = BlasterData.damage(10, "")
		local perTick = dps * TICK -- 99 HP
		local hp = perTick * 3 - 27 -- stages at 90, 180 and 270 HP lost: one stage per tick
		local all = { "Coal", "Copper", "Tin" }
		local a, b = w.player, w.other
		a.data.BlasterLevel = 10
		b.data.BlasterLevel = 10
		b.root.Position = Vector3.new(0, 3, 6)
		for n = 1, 3 do
			w.spawned, w.notes, w.mined, w.stages = {}, {}, {}, {}
			local ores = table.move(all, 1, n, 1, {})
			local rock = w.rock("Outcrops", ores, hp)
			local model = rock.Model
			local function blastOnce(p: any)
				mining.blast(p, model)
				w.step()
				mining.blast(p, nil)
			end
			blastOnce(a) -- stage 1
			T.eq(rock.Stage, 1, n .. " ores: stage 1")
			blastOnce(b) -- stage 2
			T.eq(rock.Stage, 2, n .. " ores: stage 2")
			local beforeA = a.data.Stats.RocksBroken
			blastOnce(a) -- stage 3 = shatter
			T.eq(#w.spawned, n, n .. " ores: one chunk per ore")
			-- expected owners: the drops happen at the last n stages
			local stageOwner = { a, b, a }
			for i, drop in w.spawned do
				local stage = 3 - n + i
				T.eq(drop.Info.Kind, "Raw", "dirty ore")
				T.eq(drop.Info.OreId, ores[i], n .. " ores: drop " .. i .. " is the next rolled ore")
				T.eq(drop.Owner, stageOwner[stage].UserId, n .. " ores: drop " .. i .. " belongs to who crossed stage " .. stage)
				T.truthy(drop.Velocity.Y > 0, "chunks pop up")
			end
			T.eq(#w.mined, n, "onChunkMined per chunk")
			T.eq(w.mined[#w.mined].Count, 1)
			T.eq(a.data.Stats.RocksBroken, beforeA + 1, "the finisher broke the rock")
			T.eq(count(w, "Fx", "NodeCrack"), 2, "two cracks")
			T.eq(count(w, "Fx", "NodeShatter"), 1, "one shatter")
			T.eq(#w.stages, 2, "crack visuals for stages 1 and 2")
			T.eq(mining.rock(model), nil, "the rock is gone")
			T.truthy(destroyed(model), "model destroyed")
			T.eq(mining.target(a), nil, "nobody targets it any more")
			noOreLeaks(w)
		end
		T.eq(a.data.Stats.OresMined + b.data.Stats.OresMined, 1 + 2 + 3, "OresMined counts every chunk")
		T.eq(b.data.Stats.OresMined, 2, "b crossed stage 2 for the 2- and 3-ore rocks")
		T.eq(b.data.Stats.RocksBroken, 0)
		T.eq(next(a.data.Discovered), nil, "dirty ore is not discovered by mining")
		T.eq(count(w, "Notify"), 0, "no new-ore toasts")
		T.truthy(w.changed > 0, "DataService.changed")
	end)

	withWorld("Mining: one big hit crosses several stages and still drops every ore", function(w)
		local rock = w.rock("Outcrops", { "Coal", "Copper", "Tin" }, 10)
		local p = w.player
		p.data.BlasterLevel = 10
		mining.blast(p, rock.Model)
		w.step()
		T.eq(#w.spawned, 3, "three chunks")
		for _, drop in w.spawned do
			T.eq(drop.Owner, p.UserId)
		end
		T.eq(mining.rock(rock.Model), nil, "shattered")
		T.falsy(rock.Alive, "dead")
		T.truthy(destroyed(rock.Model), "model destroyed")
		T.eq(mining.target(p), nil, "the beam stopped")
	end)

	withWorld("Mining: bad MineBlast input is refused and clears the target", function(w)
		local rock = w.rock("Quarry", { "Coal" }, 1000)
		local p = w.player
		local strangers = Instance.new("Folder")
		local foreignModel = Instance.new("Model")
		foreignModel.Parent = strangers
		local foreignPart = Instance.new("Part")
		foreignPart.Parent = strangers
		-- a rock that already shattered: the record is dead (Lune can't touch a destroyed
		-- model, so the dead record keeps its model; in Roblox Guard also refuses the
		-- destroyed model because it is no longer in the folder)
		local shattered = w.rock("Quarry", { "Coal" }, 1000)
		shattered.Alive = false
		local junk: { any } = {
			0 / 0,
			math.huge,
			"Rock",
			42,
			true,
			{},
			{ Model = rock.Model },
			Vector3.new(0, 0, 0),
			foreignModel,
			foreignPart,
			w.folder,
			rock.Model.PrimaryPart,
			shattered.Model,
		}
		for i, value in junk do
			mining.blast(p, rock.Model)
			T.truthy(mining.target(p) == rock.Model, "valid target first " .. i)
			mining.blast(p, value)
			T.eq(mining.target(p), nil, "junk #" .. i .. " (" .. tostring(value) .. ") clears the target")
		end
		local health = rock.Health
		w.step()
		T.eq(rock.Health, health, "no damage after junk")
		-- a rock the player can't see because it was removed from the folder
		rock.Model.Parent = strangers
		mining.blast(p, rock.Model)
		T.eq(mining.target(p), nil, "outside the rocks folder")
	end)

	withWorld("Mining: rocks grow back after the rarest ore's respawn time", function(w)
		local rock = w.rock("Outcrops", { "Coal", "Gold" }, 1)
		local p = w.player
		p.data.BlasterLevel = 10
		mining.blast(p, rock.Model)
		w.step()
		T.eq(mining.rock(rock.Model), nil, "shattered")
		local queue = mining.respawns()
		T.eq(#queue, 1, "queued")
		local wait = Rarity.get(OreData.ById.Gold.Rarity).RespawnTime -- random 0.5 -> x1.0
		T.near(queue[1].At, w.now + wait, 1e-6, "rarest ore (Gold) decides")
		local before = #w.folder:GetChildren()
		w.step(wait - 2)
		T.eq(#w.folder:GetChildren(), before, "not yet")
		w.step(3)
		T.eq(#w.folder:GetChildren(), before + 1, "grown back")
		T.eq(#mining.respawns(), 0, "queue empty")
	end)

	withWorld("Mining: nearestNode, onChunkMined and leaving players", function(w)
		local near = w.rock("Quarry", { "Coal" }, 1000, Vector3.new(10, 0, 0))
		local far = w.rock("Quarry", { "Gold", "Coal" }, 1000, Vector3.new(60, 0, 0))
		T.truthy(MiningService.nearestNode(Vector3.new(0, 0, 0)) == near.Model, "nearest")
		T.truthy(MiningService.nearestNode(Vector3.new(0, 0, 0), "Gold") == far.Model, "nearest with that ore")
		T.eq(MiningService.nearestNode(Vector3.new(0, 0, 0), "Heartstone"), nil, "none")
		local p = w.player
		p.root.Position = Vector3.new(14, 3, 0)
		mining.blast(p, near.Model)
		w.step()
		T.truthy(near.HitFx[p], "remembers hit effects per player")
		mining.forget(p)
		T.eq(mining.target(p), nil, "forgotten")
		T.eq(near.HitFx[p], nil, "per-rock state cleaned")
		local health = near.Health
		w.step()
		T.eq(near.Health, health, "a leaving player stops blasting")
	end)

	withWorld("Mining: works with the real OreNodeBuilder rock", function(w)
		rawset(OreNodeBuilder, "buildRock", realBuildRock)
		rawset(OreNodeBuilder, "applyStage", realApplyStage)
		local rock = w.rock("Quarry", nil, nil)
		local model = rock.Model
		local ores = table.clone(rock.Ores)
		T.truthy(model.PrimaryPart, "PrimaryPart")
		T.eq(model:GetAttribute("OreId"), nil, "no ore id")
		T.eq(model:GetAttribute("OreCount"), #ores)
		T.truthy(rock.Radius >= 1.5 and rock.Radius <= 9, "radius " .. rock.Radius)
		local p = w.player
		p.root.Position = rock.Center + Vector3.new(rock.Radius + 3, 1.5, 0)
		mining.blast(p, model)
		local ticks = 0
		while mining.rock(model) and ticks < 400 do
			w.step()
			ticks += 1
		end
		T.eq(mining.rock(model), nil, "broken by the rusty blaster in " .. ticks .. " ticks")
		T.eq(#w.spawned, #ores, "one chunk per ore")
		for i, drop in w.spawned do
			T.eq(drop.Info.OreId, ores[i])
		end
		noOreLeaks(w)
	end)
end
