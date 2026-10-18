-- The mining beam's line of sight and range origin (docs/plans/MOVEMENT_CHECK_PLAN.md):
-- a wall between the head and the rock zeroes the damage tick (no toast), the
-- result is cached per (player, rock) for BeamLosCache, BeamIgnore parts (tag
-- or attribute) never block, a rock flush against the quarry wall or up on a
-- ledge stays mineable, the BeamLos switch, and the range measured from
-- MovementService.trustedPosition only with Enforce on. Workspace:Raycast is
-- replaced by a small box world (BeamSight._test.setRaycast); the rest of
-- the harness is the one from tests/Mining.spec.luau, cut down.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local CFrame = Loader.CFrame
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local MovementConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MovementConfig")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local MiningService = Loader.requirePath("ServerScriptService.Server.Services.MiningService")
	local MovementService = Loader.requirePath("ServerScriptService.Server.Services.MovementService")
	local MovementLogic = Loader.requirePath("ServerScriptService.Server.MovementLogic")
	local BeamSight = Loader.requirePath("ServerScriptService.Server.BeamSight")

	local mining = MiningService._test
	local TICK = BlasterData.Beam.ServerTick

	local function deepCopy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, x in value do
			out[k] = deepCopy(x)
		end
		return out
	end

	-- One 4x3x4 block like OreNodeBuilder.buildRock (box (-2, 0, -2)..(2, 3, 2) at the origin).
	local function fakeRock(zoneId: string, oreIds: { string }, base: any, _seed: any): any
		local model = Instance.new("Model")
		model.Name = "Rock"
		local body = Instance.new("Part")
		body.Name = "Rock1"
		body.Size = Vector3.new(4, 3, 4)
		body.CFrame = base * CFrame.new(0, 1.5, 0)
		body.Parent = model
		model.PrimaryPart = body
		model:SetAttribute("Zone", zoneId)
		model:SetAttribute("OreCount", #oreIds)
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
		p.Character = {
			FindFirstChildOfClass = function(_, className: string)
				return if className == "Humanoid" then p.humanoid else nil
			end,
			FindFirstChild = function(_, name: string)
				if name == "HumanoidRootPart" then
					return p.root
				elseif name == "Blaster" then
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
		local w: any = { notes = {}, now = 100, byPlayer = {}, walls = {}, casts = 0 }
		w.folder = Instance.new("Folder")
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return w.byPlayer[p]
		end)
		patch(DataService, "changed", function() end)
		patch(Net, "fire", function(name, p, ...)
			table.insert(w.notes, { Name = name, Player = p, Args = { ... } })
		end)
		patch(Net, "fireNear", function(name, _position, _radius, _except, ...)
			table.insert(w.notes, { Name = name, Args = { ... } })
		end)
		patch(ItemService, "spawn", function()
			return nil
		end)
		patch(OreNodeBuilder, "buildRock", fakeRock)
		patch(OreNodeBuilder, "applyStage", function()
			return {}
		end)
		local switches = { BeamLos = MovementConfig.BeamLos, Enforce = MovementConfig.Enforce }
		mining.reset(w.folder)
		mining.setClock(function()
			return w.now
		end)
		mining.setRandom(function()
			return 0.5
		end)
		-- the box world: the nearest wall the segment enters (like Roblox, a ray starting inside a part misses it)
		BeamSight._test.setRaycast(function(origin, direction)
			w.casts += 1
			local best, bestDistance = nil, math.huge
			for _, wall in w.walls do
				local entry = MovementLogic.entryPoint(origin, origin + direction, wall.Min, wall.Max)
				if entry and (entry - origin).Magnitude > 1e-6 then
					local distance = (entry - origin).Magnitude
					if distance < bestDistance then
						best, bestDistance = { Instance = wall.Part, Position = entry }, distance
					end
				end
			end
			return best
		end)
		w.player = fakePlayer(w, 601)
		w.restore = function()
			mining.reset(nil)
			MovementConfig.BeamLos = switches.BeamLos
			MovementConfig.Enforce = switches.Enforce
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		-- a wall from min to max (a real Part, so tags and attributes work)
		w.wall = function(min: any, max: any): any
			local part = Instance.new("Part")
			part.Name = "Wall"
			local wall = { Part = part, Min = min, Max = max }
			table.insert(w.walls, wall)
			return part
		end
		-- a Coal rock with lots of HP whose ground is at `position`
		w.rock = function(position: any?): any
			local marker = Instance.new("Part")
			marker.Size = Vector3.new(2, 2, 2)
			marker.CFrame = CFrame.new((position or Vector3.new(0, 0, 0)) + Vector3.new(0, 1, 0))
			marker:SetAttribute("Zone", "Quarry")
			local rock = mining.spawnRock(marker)
			T.truthy(rock, "spawned a rock")
			rock.Ores = { "Coal" }
			rock.Health = 1e6
			rock.MaxHealth = 1e6
			return rock
		end
		w.step = function(seconds: number?)
			w.now += seconds or TICK
			mining.tick(w.now)
		end
		-- fire at `rock` for one tick: did it lose health?
		w.hits = function(rock: any): boolean
			mining.blast(w.player, rock.Model)
			local before = rock.Health
			w.step()
			return rock.Health < before
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

	local function toasts(w: any): number
		local n = 0
		for _, note in w.notes do
			if note.Name == "Notify" then
				n += 1
			end
		end
		return n
	end

	withWorld("Beam LOS: a wall between the head and the rock zeroes the damage tick, with one throttled toast", function(w)
		local rock = w.rock()
		T.truthy(w.hits(rock), "open ground: damage")
		w.wall(Vector3.new(3.6, -1, -10), Vector3.new(4.4, 20, 10)) -- between the player (x 6) and the rock (x <= 2)
		w.now += MovementConfig.BeamLosCache
		local health = rock.Health
		for _ = 1, 8 do
			w.step()
		end
		T.eq(rock.Health, health, "blocked: no damage")
		T.eq(toasts(w), 1, "one toast says why (throttled per rock)")
		local last: any = nil
		for _, note in w.notes do
			if note.Name == "Notify" then
				last = note
			end
		end
		T.eq(last and last.Args[1].Text, MiningService.NoSightText, "the no-sight text")
		T.truthy(mining.target(w.player) == rock.Model, "the beam keeps its target (the client still draws it)")
		-- the wall goes away: damage again once the cached result runs out
		table.clear(w.walls)
		w.now += MovementConfig.BeamLosCache
		T.truthy(w.hits(rock), "clear again")
		-- a wall far behind the player or beside the line never matters
		w.wall(Vector3.new(10, -1, -10), Vector3.new(12, 20, 10))
		w.wall(Vector3.new(-10, -1, 6), Vector3.new(10, 20, 8))
		w.now += MovementConfig.BeamLosCache
		T.truthy(w.hits(rock), "walls off the line")
	end)

	withWorld("Beam LOS: one result per (player, rock) for BeamLosCache seconds", function(w)
		local rock = w.rock()
		mining.blast(w.player, rock.Model)
		w.step()
		T.eq(w.casts, 1, "one raycast")
		local ticks = math.floor(MovementConfig.BeamLosCache / TICK + 1e-6) - 2
		for _ = 1, ticks do
			w.step()
		end
		T.eq(w.casts, 1, "cached within " .. MovementConfig.BeamLosCache .. " s")
		-- a wall appearing inside the cached window only counts after it
		w.wall(Vector3.new(3.6, -1, -10), Vector3.new(4.4, 20, 10))
		local before = rock.Health
		w.step()
		T.lt(rock.Health, before, "still the cached clear result")
		w.step(MovementConfig.BeamLosCache)
		T.lt(1, w.casts, "cast again after the cache expired")
		before = rock.Health
		w.step()
		T.eq(rock.Health, before, "now blocked")
		-- another rock is its own entry
		local other = w.rock(Vector3.new(0, 0, -12))
		local casts = w.casts
		mining.blast(w.player, other.Model)
		w.step()
		T.lt(casts, w.casts, "a new rock casts at once")
		-- leaving forgets the cache
		mining.forget(w.player)
		casts = w.casts
		mining.blast(w.player, other.Model)
		w.step()
		T.lt(casts, w.casts, "forgotten on leave")
	end)

	withWorld("Beam LOS: BeamIgnore parts (tag, attribute, or their model's) never block", function(w)
		local rock = w.rock()
		local part = w.wall(Vector3.new(3.6, -1, -10), Vector3.new(4.4, 20, 10))
		part:AddTag(MovementConfig.BeamIgnoreTag)
		T.truthy(w.hits(rock), "tagged")
		part:RemoveTag(MovementConfig.BeamIgnoreTag)
		part:SetAttribute(MovementConfig.BeamIgnoreAttribute, true)
		w.now += MovementConfig.BeamLosCache
		T.truthy(w.hits(rock), "attributed")
		part:SetAttribute(MovementConfig.BeamIgnoreAttribute, nil)
		local decoration = Instance.new("Model")
		decoration:SetAttribute(MovementConfig.BeamIgnoreAttribute, true)
		part.Parent = decoration
		w.now += MovementConfig.BeamLosCache
		T.truthy(w.hits(rock), "inside an ignored model")
		-- an ignored part in front of a real wall: the wall still blocks
		table.clear(w.walls)
		local lamp = w.wall(Vector3.new(4.8, -1, -10), Vector3.new(5.2, 20, 10))
		lamp:SetAttribute(MovementConfig.BeamIgnoreAttribute, true)
		w.wall(Vector3.new(3.6, -1, -10), Vector3.new(4.4, 20, 10))
		w.now += MovementConfig.BeamLosCache
		T.falsy(w.hits(rock), "the real wall behind the decoration")
		-- a wall within BeamStopShort of the rock's face never counts (the quarry wall case)
		table.clear(w.walls)
		w.wall(Vector3.new(2.2, -1, -10), Vector3.new(2.4, 20, 10))
		w.now += MovementConfig.BeamLosCache
		T.truthy(w.hits(rock), "a slab right at the rock's face")
		-- a plain wall blocks
		table.clear(w.walls)
		w.wall(Vector3.new(3.6, -1, -10), Vector3.new(4.4, 20, 10))
		w.now += MovementConfig.BeamLosCache
		T.falsy(w.hits(rock), "untagged blocks")
	end)

	withWorld("Beam LOS: a rock flush against the quarry wall stays mineable from every side", function(w)
		local rock = w.rock()
		-- the quarry wall touches the rock's back (x = -2); one embedded half a stud into it, another one behind
		w.wall(Vector3.new(-14, -1, -30), Vector3.new(-2, 40, 30))
		w.wall(Vector3.new(-30, -1, -30), Vector3.new(-1.5, 2, 30)) -- the wall's foot reaches under the rock
		for _, spot in
			{
				Vector3.new(6, 3, 0), -- in front
				Vector3.new(4, 3, 5), -- at an angle
				Vector3.new(0, 3, 7), -- along the wall
				Vector3.new(-0.5, 3, -6), -- along the wall, close to it
				Vector3.new(3, 8, 0), -- above, on a ledge
				Vector3.new(2.5, 3, 0), -- right at the rock
			}
		do
			w.player.root.Position = spot
			w.now += MovementConfig.BeamLosCache
			T.truthy(w.hits(rock), "mineable from " .. tostring(spot))
		end
		-- the same wall between: blocked (behind the wall, inside range)
		w.player.root.Position = Vector3.new(-16, 3, 0)
		w.now += MovementConfig.BeamLosCache
		T.falsy(w.hits(rock), "through the wall from behind")
	end)

	withWorld("Beam LOS: a rock up on a ledge is reached by its top line when the ledge lip hides the closest point", function(w)
		local rock = w.rock(Vector3.new(0, 6, 0)) -- box (-2, 6, -2)..(2, 9, 2)
		w.wall(Vector3.new(-10, -1, -10), Vector3.new(4, 6, 10)) -- the ledge, its lip 2 studs in front of the rock
		w.player.root.Position = Vector3.new(8, 3, 0)
		local min, max = Vector3.new(-2, 6, -2), Vector3.new(2, 9, 2)
		local lines = MovementLogic.beamLines(Vector3.new(8, 4.5, 0), min, max, MovementConfig.BeamStopShort)
		T.eq(#lines, 2, "closest point + top line")
		T.truthy(w.hits(rock), "mineable from below the ledge")
		T.eq(w.casts, 2, "the closest line hit the lip, the top line was clear")
	end)

	withWorld("Beam LOS: switched off, walls don't matter", function(w)
		local rock = w.rock()
		w.wall(Vector3.new(3.6, -1, -10), Vector3.new(4.4, 20, 10))
		T.falsy(w.hits(rock), "on: blocked")
		MovementConfig.BeamLos = false
		w.now += MovementConfig.BeamLosCache
		local casts = w.casts
		T.truthy(w.hits(rock), "off: damage")
		T.eq(w.casts, casts, "no raycast when off")
	end)

	withWorld("Beam range: measured from MovementService.trustedPosition only with Enforce on", function(w)
		local rock = w.rock()
		local saved = rawget(MovementService, "trustedPosition")
		local asked = 0
		rawset(MovementService, "trustedPosition", function(_player)
			asked += 1
			return Vector3.new(500, 3, 0) -- the last good sample, far away
		end)
		local ok, err = pcall(function()
			MovementConfig.Enforce = false
			T.truthy(w.hits(rock), "Enforce off: the live position (no change today)")
			T.eq(asked, 0, "not even asked")
			MovementConfig.Enforce = true
			T.falsy(w.hits(rock), "Enforce on: out of range from the trusted position")
			T.lt(0, asked, "asked")
			rawset(MovementService, "trustedPosition", function(_player)
				return nil -- no character known: the live position
			end)
			T.truthy(w.hits(rock), "nil falls back to the live position")
		end)
		rawset(MovementService, "trustedPosition", saved)
		if not ok then
			error(err, 0)
		end
	end)

	T.test("Beam LOS: the Blaster Vault's interior decorations carry the BeamIgnore tag (build time)", function()
		local Vault = Loader.requirePath("ServerScriptService.Server.World.Lobby.Vault")
		local holder = Instance.new("Model")
		local vault = Vault.buildVault(holder)
		local zone = vault:FindFirstChild("VaultInterior")
		T.truthy(zone, "the interior zone")
		local tagged, counter = 0, false
		local inverse = zone.CFrame:Inverse()
		for _, d in vault:GetDescendants() do
			if d:IsA("BasePart") and d:HasTag(MovementConfig.BeamIgnoreTag) then
				tagged += 1
				T.truthy(d.CanQuery, d.Name .. ": only parts a raycast can hit need the tag")
				local p = inverse * d.CFrame.Position
				local half = zone.Size / 2 + Vector3.new(1, 1, 1)
				T.truthy(math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z, d.Name .. " is inside")
				counter = counter or d:HasTag("VaultCounter")
			end
		end
		T.lt(0, tagged, "interior parts tagged")
		T.truthy(counter, "the counter (its VaultCounter tag stays)")
		local floor = vault:FindFirstChild("Floor")
		T.truthy(floor and not floor:HasTag(MovementConfig.BeamIgnoreTag), "the floor is not a decoration")
	end)

	T.test("Beam LOS: geometry helpers (box of a turned part, closest point, entry point)", function()
		local lo, hi = MovementLogic.partBounds(CFrame.new(0, 1.5, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(4, 3, 4))
		local half = math.sqrt(8)
		T.near(hi.X, half, 1e-6, "turned 45 degrees: wider")
		T.near(lo.Z, -half, 1e-6)
		T.near(hi.Y, 3, 1e-6)
		local min, max = Vector3.new(-2, 0, -2), Vector3.new(2, 3, 2)
		T.eq(MovementLogic.closestPoint(Vector3.new(6, 4.5, 0), min, max), Vector3.new(2, 3, 0), "closest")
		T.eq(MovementLogic.closestPoint(Vector3.new(1, 1, 1), min, max), Vector3.new(1, 1, 1), "inside")
		T.eq(MovementLogic.entryPoint(Vector3.new(6, 1, 0), Vector3.new(0, 1, 0), min, max), Vector3.new(2, 1, 0), "entry")
		T.eq(MovementLogic.entryPoint(Vector3.new(6, 10, 0), Vector3.new(0, 10, 0), min, max), nil, "miss")
		T.eq(MovementLogic.entryPoint(Vector3.new(6, 1, 0), Vector3.new(3, 1, 0), min, max), nil, "stops short")
		T.eq(MovementLogic.beamLines(Vector3.new(2.5, 2, 0), min, max, 1.5), nil, "within stop-short: nothing between")
	end)
end
