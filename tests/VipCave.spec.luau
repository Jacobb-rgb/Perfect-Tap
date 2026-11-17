--[[
	The VIP cave behind every yard (owner 2026-11-17: in place of the VIP mine at the quarry, "a
	little cave on every plot where the train unloaded ore ... it opens only with the pass", in the
	rainbow mountain style with waterfalls round it; only the plot's owner with the Forgemaster's
	Pass goes in, 5 rocks of the Glimmer Grotto's ore, the door locked without the pass).
	World/PlotCave builds it, PlotBuilder its door in the back wall, AccessService and
	AccessController keep it the owner's, MiningService's gates grow and guard its rocks.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance
	local Enum = roblox.Enum
	local CFrame = Loader.CFrame
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local PlotCave = Loader.requirePath("ServerScriptService.Server.World.PlotCave")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local WorldService = Loader.requirePath("ServerScriptService.Server.Services.WorldService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local MiningService = Loader.requirePath("ServerScriptService.Server.Services.MiningService")
	local AccessService = Loader.requirePath("ServerScriptService.Server.Services.AccessService")

	local cave = BaseLayout.VipCave
	local room = cave.Room
	local ROOM_FRONT = PlotCave.RoomFront -- the room's inside from here back (the mound's front before it)

	local function tagged(instance: any, tag: string): boolean
		return table.find(instance:GetTags(), tag) ~= nil
	end

	-- the world box (axis-aligned: plots turn by quarter turns) of a plot-local box
	local function worldBox(plot: any, lo: any, hi: any): (any, any)
		local cf = WorldLayout.plotCFrame(plot)
		local a, b = cf:PointToWorldSpace(lo), cf:PointToWorldSpace(hi)
		return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)),
			Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	end

	-- a part's world box (its turn included)
	local function partBox(part: any): (any, any)
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
		local s = part.Size / 2
		local e = Vector3.new(
			math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z,
			math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z,
			math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z
		)
		local p = part.CFrame.Position
		return p - e, p + e
	end

	local function overlaps(aLo: any, aHi: any, bLo: any, bHi: any): boolean
		return aLo.X < bHi.X and bLo.X < aHi.X and aLo.Y < bHi.Y and bLo.Y < aHi.Y and aLo.Z < bHi.Z and bLo.Z < aHi.Z
	end

	T.test("VIP cave: a cave behind every yard, its 5 rock spots in its room", function()
		local map = Instance.new("Folder")
		local spawns = PlotCave.buildAll(map, Rng.new(1))
		local folder = map:FindFirstChild("VipCaves")
		T.truthy(folder, "Map.VipCaves")
		T.eq(#folder:GetChildren(), #WorldLayout.Plots, "a cave per plot")
		T.eq(#cave.Rocks, 5, "5 rocks (owner: 5, phones)")
		T.eq(#spawns, #WorldLayout.Plots * #cave.Rocks, "every cave's rock spots")
		for _, plot in WorldLayout.Plots do
			local model = folder:FindFirstChild("VipCave_" .. plot.Id)
			T.truthy(model, `plot {plot.Id}'s cave`)
			T.eq(model:GetAttribute("PlotId"), plot.Id, "the cave knows its plot")
			-- phones: its parts, one light, a few see-through ones (the falls and their pools)
			local parts, lights, seeThrough, zone, sign = 0, 0, 0, nil, false
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					if d.Transparency > 0 and d.Transparency < 1 then
						seeThrough += 1
					end
					if d.Name == "LightingZone" then
						zone = d
					end
				elseif d:IsA("Light") then
					lights += 1
				elseif d:IsA("TextLabel") and d.Text == "GLIMMER GROTTO" then
					sign = true
				end
			end
			T.le(parts, PlotCave.Budget.Parts, `plot {plot.Id}'s cave parts`)
			T.le(lights, 1, `plot {plot.Id}'s cave lights`)
			T.le(seeThrough, PlotCave.Budget.SeeThrough, `plot {plot.Id}'s cave see-through parts`)
			T.truthy(sign, "GLIMMER GROTTO over the door")
			-- the grotto's cave light inside (LightingController reads the tagged box)
			T.truthy(zone, "a LightingZone")
			T.eq(zone:GetAttribute("Preset"), "Grotto", "the grotto's light")
			T.truthy(tagged(zone, "LightingZone"), "tagged LightingZone")
			T.falsy(zone.CanCollide or zone.CanQuery, "the zone box neither collides nor is raycast")
			T.eq(zone.Transparency, 1, "the zone box is invisible")
		end
		local cf: any = nil
		local mine: { any } = {}
		for _, plot in WorldLayout.Plots do
			cf = WorldLayout.plotCFrame(plot)
			table.clear(mine)
			for _, s in spawns do
				if s.PlotId == plot.Id then
					T.eq(s.Zone, "Grotto", "the Glimmer Grotto's ore, blaster and VIP rule")
					table.insert(mine, cf:PointToObjectSpace(s.Position))
					T.eq(AccessService.caveAt(s.Position + Vector3.new(0, 2, 0)), plot.Id, "the spot is in its own cave")
					-- the magnet pulls the chunks off the rocks (the yard's margin ends before them)
					T.falsy(ItemService.onBase(s.Position + Vector3.new(0, 1, 0)), "a rock spot past the yard's pickup margin")
				end
			end
			T.eq(#mine, #cave.Rocks, `plot {plot.Id}'s 5 rock spots`)
			for i, p in mine do
				T.near(p.Y, 0, 0.01, "on the room's floor")
				T.le(room.Min.X + 2.5, p.X, "clear of the left wall")
				T.le(p.X, room.Max.X - 2.5, "clear of the right wall")
				T.le(ROOM_FRONT + 2.5, p.Z, "clear of the front wall")
				T.le(p.Z, room.Max.Z - 2, "clear of the back wall")
				-- (a U round the middle: the way in from the door stays clear)
				T.truthy(math.abs(p.X) >= 5 or p.Z >= ROOM_FRONT + 6, "the way in from the door stays clear")
				for j = i + 1, #mine do
					local q = mine[j]
					T.le(6.5, Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude, "rock spots 6.5 studs apart (a rock is 6-7 across)")
				end
			end
		end
	end)

	T.test("VIP cave: its door in the back wall is its plot's: solid, glowing, between two tall posts", function()
		local door = cave.Door
		for _, plot in { WorldLayout.Plots[1], WorldLayout.Plots[#WorldLayout.Plots] } do
			local model = PlotBuilder.buildPlot(Instance.new("Folder"), plot, Rng.new(plot.Id))
			local fence = model.Yard.Fence
			local part = fence:FindFirstChild("VipDoor")
			T.truthy(part, "the door in the yard's fence")
			T.truthy(tagged(part, "VipDoor"), "tagged VipDoor (AccessController)")
			T.eq(part:GetAttribute("PlotId"), plot.Id, "the door knows its plot")
			T.truthy(part.CanCollide, "solid for everyone on the server")
			T.eq(part.Transparency, 0, "opaque (the plot's no-see-through rule)")
			T.eq(part.Material, Enum.Material.Neon, "a glowing curtain")
			T.falsy(part.CanQuery, "no beam or camera stop")
			local cf = WorldLayout.plotCFrame(plot)
			local at = cf:PointToObjectSpace(part.CFrame.Position)
			T.near(at.X, door.CenterX, 0.01, "in the middle of the back wall")
			T.near(at.Z, PlotBuilder.BackWallZ, 0.01, "in the back wall")
			T.near(at.Y, door.Height / 2, 0.01, "on the yard's floor")
			T.near(part.Size.X, door.Width, 0.01, "as wide as the door")
			T.near(part.Size.Y, door.Height, 0.01, "as tall as the door")
			-- a post either side, a little taller than the door
			local posts = 0
			for _, d in fence:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Pillar" then
					local p = cf:PointToObjectSpace(d.CFrame.Position)
					local side = math.abs(math.abs(p.X - door.CenterX) - (door.Width / 2 + PlotBuilder.DoorPost / 2))
					if side < 0.05 and math.abs(p.Z - PlotBuilder.BackWallZ) < 0.05 then
						posts += 1
						T.le(door.Height, p.Y + d.Size.X / 2, "the post stands as tall as the door") -- (cylUp: X up)
					end
				end
			end
			T.eq(posts, 2, "a post either side of the door")
		end
	end)

	T.test("VIP cave: nothing else stands in a cave's room, its way in or the yard in front of its door", function()
		local game = Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local caves = map:FindFirstChild("VipCaves")
		T.truthy(caves, "Map.VipCaves")
		local markers = map:FindFirstChild("NodeSpawns")
		local half = cave.Door.Width / 2
		local boxes = {}
		for _, plot in WorldLayout.Plots do
			-- the room inside its shell, the tunnel from the door and the yard in front of the door
			local rLo, rHi = worldBox(
				plot,
				Vector3.new(room.Min.X + 0.05, 0.2, ROOM_FRONT),
				Vector3.new(room.Max.X - 0.05, room.Max.Y - 0.05, room.Max.Z - 0.05)
			)
			local tLo, tHi = worldBox(
				plot,
				Vector3.new(-half + 0.05, 0.2, PlotBuilder.BackWallZ + 0.3),
				Vector3.new(half - 0.05, cave.Door.Height - 0.05, ROOM_FRONT)
			)
			local yLo, yHi = worldBox(
				plot,
				Vector3.new(-half + 0.5, 0.6, PlotBuilder.BackWallZ - 6),
				Vector3.new(half - 0.5, 6, PlotBuilder.BackWallZ - 0.4)
			)
			table.insert(boxes, { Plot = plot.Id, Name = "room", Lo = rLo, Hi = rHi, Any = true })
			table.insert(boxes, { Plot = plot.Id, Name = "way in", Lo = tLo, Hi = tHi, Any = true })
			-- (the yard: only what blocks the way to the door)
			table.insert(boxes, { Plot = plot.Id, Name = "yard in front of the door", Lo = yLo, Hi = yHi, Any = false })
		end
		local checked = 0
		for _, d in map:GetDescendants() do
			if not d:IsA("BasePart") or d:IsDescendantOf(caves) or (markers and d:IsDescendantOf(markers)) then
				continue
			end
			if d.Transparency >= 1 and not d.CanCollide then
				continue -- invisible and walked through: zones, markers
			end
			checked += 1
			local lo, hi = partBox(d)
			for _, box in boxes do
				if (box.Any or d.CanCollide) and overlaps(lo, hi, box.Lo, box.Hi) then
					error(`{d:GetFullName()} stands in plot {box.Plot}'s cave ({box.Name})`, 0)
				end
			end
		end
		T.lt(1000, checked, "the map's parts checked")
		-- each cave's own parts keep its room and way in free too (crystals in the corners, rocks
		-- grow on their spots): only the zone box, the crystals and the floor's top touch them
		for _, plot in WorldLayout.Plots do
			local model = caves:FindFirstChild("VipCave_" .. plot.Id)
			for _, box in boxes do
				if box.Plot == plot.Id and box.Any then
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") and d.Name ~= "LightingZone" and not d:FindFirstAncestor("CrystalCluster") then
							local lo, hi = partBox(d)
							T.falsy(overlaps(lo, hi, box.Lo, box.Hi), `{d:GetFullName()} stands in its own {box.Name}`)
						end
					end
				end
			end
		end
		-- the rock spots are markers like every other (their plot on them)
		local own = 0
		for _, m in markers:GetChildren() do
			local id = m:GetAttribute("PlotId")
			if id ~= nil then
				own += 1
				T.eq(m:GetAttribute("Zone"), "Grotto", "a cave marker grows the grotto's rocks")
				T.eq(AccessService.caveAt(m.CFrame.Position), id, "a cave marker in its own cave")
			end
		end
		T.eq(own, #WorldLayout.Plots * #cave.Rocks, "the caves' markers")
	end)

	T.test("VIP cave: the walls round the room close it but for the door", function()
		local folder = Instance.new("Folder")
		local plot = WorldLayout.Plots[3]
		local model = PlotCave.build(folder, plot, Rng.new(3))
		local yard = PlotBuilder.buildPlot(Instance.new("Folder"), plot, Rng.new(3))
		local cf = WorldLayout.plotCFrame(plot)
		local solids = {}
		for _, root in { model, yard } do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then
					table.insert(solids, d)
				end
			end
		end
		local function blocked(x: number, y: number, z: number): boolean
			local world = cf:PointToWorldSpace(Vector3.new(x, y, z))
			for _, part in solids do
				local q = part.CFrame:PointToObjectSpace(world)
				local h = part.Size / 2
				if math.abs(q.X) <= h.X + 0.01 and math.abs(q.Y) <= h.Y + 0.01 and math.abs(q.Z) <= h.Z + 0.01 then
					return true
				end
			end
			return false
		end
		for _, y in { 1, 4, room.Max.Y - 1 } do
			for z = ROOM_FRONT, room.Max.Z, 1 do
				T.truthy(blocked(room.Min.X - 0.5, y, z), `the left wall at y {y}, z {z}`)
				T.truthy(blocked(room.Max.X + 0.5, y, z), `the right wall at y {y}, z {z}`)
			end
			for x = room.Min.X, room.Max.X, 1 do
				T.truthy(blocked(x, y, room.Max.Z + 0.5), `the back wall at x {x}, y {y}`)
				-- the front: the mound round the door, the door itself on the server
				T.truthy(blocked(x, y, ROOM_FRONT - 0.9) or blocked(x, y, PlotBuilder.BackWallZ), `the front at x {x}, y {y}`)
			end
		end
		for x = room.Min.X, room.Max.X, 2 do
			for z = ROOM_FRONT, room.Max.Z, 2 do
				T.truthy(blocked(x, room.Max.Y + 0.5, z), `the ceiling at x {x}, z {z}`)
				T.truthy(blocked(x, -0.2, z), `the floor at x {x}, z {z}`)
			end
		end
	end)

	T.test("VIP cave: AccessController opens only the player's own door, with the pass", function()
		-- (a client module: it reads Players.LocalPlayer when it loads)
		local Players = Loader.game:GetService("Players")
		local hadLocal = rawget(Players, "LocalPlayer")
		rawset(Players, "LocalPlayer", { Name = "Me", UserId = 1 })
		local ok, loaded = pcall(Loader.requirePath, "StarterPlayer.StarterPlayerScripts.Client.Controllers.AccessController")
		rawset(Players, "LocalPlayer", hadLocal)
		if not ok then
			error(loaded, 0)
		end
		local AccessController = loaded
		T.truthy(AccessController.opens(true, 3, 3), "the owner with the pass")
		T.falsy(AccessController.opens(false, 3, 3), "the owner without the pass")
		T.falsy(AccessController.opens(true, 3, 4), "another plot's door")
		T.falsy(AccessController.opens(true, nil, nil), "no plot yet")
		T.falsy(AccessController.opens(true, 3, nil), "a door without its plot")
		T.falsy(AccessController.opens(true, "3", 3), "a plot id that is no number")
	end)

	T.test("VIP cave: caveAt finds the cave that holds a point; the spot in front of the door is in none", function()
		for _, plot in WorldLayout.Plots do
			local cf = WorldLayout.plotCFrame(plot)
			T.eq(AccessService.caveAt(cf:PointToWorldSpace(Vector3.new(0, 3, 70))), plot.Id, "the room's middle")
			T.eq(
				AccessService.caveAt(cf:PointToWorldSpace(Vector3.new(0, 3, PlotBuilder.BackWallZ + 1))),
				plot.Id,
				"the way in behind the door"
			)
			T.eq(AccessService.caveAt(cf:PointToWorldSpace(Vector3.new(0, 3, 50))), nil, "the yard")
			T.eq(AccessService.caveAt(cf:PointToWorldSpace(Vector3.new(0, 30, 70))), nil, "the mound's top")
			T.eq(AccessService.caveAt(PlotCave.outside(plot).Position), nil, "the spot an intruder is put on")
			-- that spot is in the yard in front of the door, looking away from it
			local at = cf:PointToObjectSpace(PlotCave.outside(plot).Position)
			T.lt(at.Z, PlotBuilder.BackWallZ - 2, "in front of the door")
			T.lt(math.abs(at.X), cave.Door.Width / 2, "lined up with the door")
		end
	end)

	-- a player stand-in: Perks read its attributes
	local function fakePlayer(name: string): any
		local p: any = { Name = name, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		return p
	end

	local function withOwners(fn: ({ [number]: any }) -> ())
		local owners: { [number]: any } = {}
		local realOwnerOf = PlotService.ownerOf
		rawset(PlotService, "ownerOf", function(plotId: number)
			return owners[plotId]
		end)
		local ok, err = pcall(fn, owners)
		rawset(PlotService, "ownerOf", realOwnerOf)
		if not ok then
			error(err, 0)
		end
	end

	T.test("VIP cave: only the plot's owner with the pass may be in its cave and mine it", function()
		withOwners(function(owners)
			local owner, guest = fakePlayer("Owner"), fakePlayer("Guest")
			local marker = Instance.new("Part")
			marker:SetAttribute("Zone", "Grotto")
			marker:SetAttribute("PlotId", 2)
			local plain = Instance.new("Part")
			plain:SetAttribute("Zone", "Quarry")
			-- nobody owns plot 2: its cave grows nothing
			T.falsy(AccessService.spawnAllowed(marker), "no owner, no rocks")
			T.truthy(AccessService.spawnAllowed(plain), "other rocks grow as before")
			owners[2] = owner
			T.falsy(AccessService.mayEnter(owner, 2), "the owner without the pass")
			T.falsy(AccessService.spawnAllowed(marker), "no pass, no rocks")
			owner.attrs.Perk_ForgeVip = true
			T.truthy(AccessService.mayEnter(owner, 2), "the owner with the pass")
			T.truthy(AccessService.spawnAllowed(marker), "the pass grows the rocks")
			guest.attrs.Perk_ForgeVip = true
			T.falsy(AccessService.mayEnter(guest, 2), "a guest with the pass: not their cave")
			T.falsy(AccessService.mayEnter(owner, 3), "the owner in another plot's cave")
			-- mining: the plot's owner only (the VIP rule asks for the pass before this)
			T.eq(AccessService.mineRefusal(owner, marker), nil, "the owner mines")
			T.eq(AccessService.mineRefusal(guest, marker), AccessService.MineDeny, "a guest is refused")
			T.eq(AccessService.mineRefusal(guest, plain), nil, "other rocks as before")
		end)
	end)

	-- A rock model like OreNodeBuilder.buildRock makes (one 4x3x4 block).
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

	T.test("VIP cave: its rocks grow while the owner has the pass and go when the pass or the plot goes", function()
		local mining = MiningService._test
		local rocksFolder = Instance.new("Folder")
		local markers = Instance.new("Folder")
		local realBuild = OreNodeBuilder.buildRock
		local realMarkers = WorldService.NodeSpawns
		rawset(OreNodeBuilder, "buildRock", fakeRock)
		mining.reset(rocksFolder)
		WorldService.NodeSpawns = markers
		local ok, err = pcall(function()
			withOwners(function(owners)
				AccessService.init() -- the gates
				for plotId = 2, 3 do
					for i, p in cave.Rocks do
						local m = Instance.new("Part")
						m.Size = Vector3.new(2, 2, 2)
						m.CFrame = CFrame.new(p + Vector3.new(plotId * 100, 1, 0))
						m.Name = `Spot{plotId}_{i}`
						m:SetAttribute("Zone", "Grotto")
						m:SetAttribute("PlotId", plotId)
						m.Parent = markers
					end
				end
				local function count(plotId: number): number
					local n = 0
					for _, rock in rocksFolder:GetChildren() do
						local x = rock.PrimaryPart.CFrame.Position.X
						if math.abs(x - plotId * 100) < 20 then
							n += 1
						end
					end
					return n
				end
				local function refresh(plotId: number)
					MiningService.refreshMarkers(function(marker: any): boolean
						return marker:GetAttribute("PlotId") == plotId
					end)
				end
				-- the server starts: no owners, no cave rocks
				for _, m in markers:GetChildren() do
					T.eq(mining.spawnRock(m), nil, "no owner: " .. m.Name .. " stays empty")
				end
				T.eq(#rocksFolder:GetChildren(), 0, "no cave rocks at the start")
				local owner = fakePlayer("Owner")
				owners[2] = owner
				refresh(2)
				T.eq(count(2), 0, "an owner without the pass: still none")
				owner.attrs.Perk_ForgeVip = true
				refresh(2)
				T.eq(count(2), 5, "the pass grows the 5 rocks")
				T.eq(count(3), 0, "the next plot's cave stays empty")
				refresh(2)
				T.eq(count(2), 5, "a second refresh adds none")
				-- a mined rock waits for its regrowth (the respawn queue), refresh adds none meanwhile
				-- (as MiningService breaks one: its model goes, its regrowth is queued)
				local first = rocksFolder:GetChildren()[1]
				local rock = mining.rock(first)
				T.truthy(rock, "the rock's record")
				rock.Alive = false
				rock.Model:Destroy()
				table.insert(mining.respawns(), { At = math.huge, Marker = rock.Marker })
				refresh(2)
				T.eq(#mining.respawns(), 1, "its regrowth still waits")
				T.eq(count(2), 4, "no second rock on a spot that regrows")
				-- the pass goes (or the plot is let go): the rocks and their regrowth go
				owner.attrs.Perk_ForgeVip = nil
				refresh(2)
				T.eq(count(2), 0, "no pass: the rocks go")
				T.eq(#mining.respawns(), 0, "and their regrowth")
				owner.attrs.Perk_ForgeVip = true
				refresh(2)
				T.eq(count(2), 5, "the pass back: the rocks back")
				owners[2] = nil
				refresh(2)
				T.eq(count(2), 0, "the plot let go: the rocks go")
			end)
		end)
		mining.reset(nil)
		WorldService.NodeSpawns = realMarkers
		rawset(OreNodeBuilder, "buildRock", realBuild)
		if not ok then
			error(err, 0)
		end
	end)
end
