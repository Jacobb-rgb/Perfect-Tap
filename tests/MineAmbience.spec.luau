--[[
	Mine ambience (Config/MineAmbience, MineKit.ambience, World/Mine/Floor*.luau):
	every layer keeps the lobby ambience rules (quiet, an id that plays today,
	heard only inside the streaming radius, loops exactly when its sound loops),
	every floor of the game build carries 4-8 spots of its kinds on parts that
	are already there inside its box, no point on a floor hears more than 3
	loops, the spots add no parts, and the elevator has its arrival sting.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local MineAmbience = Loader.requirePath("ReplicatedStorage.Shared.Config.MineAmbience")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local MODULES = { "Floor1Quarry", "Floor2Ember", "Floor3Lagoon", "Floor4Palace", "Floor5Storm", "Floor6Core" }
	local KINDS = { "MineDrip", "MineRumble", "LagoonLap", "PalaceEcho", "CrystalHum", "LavaBubble", "StormCrackle" }
	-- AmbienceConfig's own kinds (review/hory-noc): the mine kinds are merged into the same table
	local LOBBY_KINDS = { "Waterfall", "Brook", "Pond", "Forge", "Plaza" }

	-- ids that play in today's clients (the rule of tests/BlasterFeel.spec.luau): a file still
	-- shipped in content/sounds, or one of Roblox's own uploads already verified in SoundConfig
	local SHIPPED = {
		["rbxasset://sounds/action_falling.ogg"] = true,
		["rbxasset://sounds/action_footsteps_plastic.mp3"] = true,
		["rbxasset://sounds/action_get_up.mp3"] = true,
		["rbxasset://sounds/action_jump.mp3"] = true,
		["rbxasset://sounds/action_jump_land.mp3"] = true,
		["rbxasset://sounds/action_swim.mp3"] = true,
		["rbxasset://sounds/impact_explosion_03.mp3"] = true,
		["rbxasset://sounds/impact_water.mp3"] = true,
		["rbxasset://sounds/oof.ogg"] = true,
		["rbxasset://sounds/ouch.ogg"] = true,
		["rbxasset://sounds/volume_slider.ogg"] = true,
	}
	local VERIFIED = {
		["12221967"] = true, -- button.wav
		["12221976"] = true, -- clickfast.wav
		["12221984"] = true, -- collide.wav
		["12221990"] = true, -- electronicpingshort.wav
		["12221996"] = true, -- flashbulb.wav
		["12222005"] = true, -- glassbreak.wav
		["12222046"] = true, -- hit.wav
		["12222140"] = true, -- snap.wav
		["12222200"] = true, -- swoosh.wav
		["12222225"] = true, -- unsheath.wav
		["12222253"] = true, -- victory.wav
		["162670130"] = true, -- UFO Beam
		["16480570986"] = true, -- Roblox Pinball low bells
	}
	local function plays(id: string): boolean
		if SHIPPED[id] then
			return true
		end
		local digits = string.match(id, "^rbxassetid://(%d+)$")
		return digits ~= nil and VERIFIED[digits] == true
	end

	local function count(model, className: string): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	local function spotsOf(model): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d.ClassName == "Attachment" and d:HasTag(MineAmbience.Tag) then
				table.insert(list, d)
			end
		end
		return list
	end

	local function worldOf(spot): any
		return (spot.Parent.CFrame * spot.CFrame).Position
	end

	-- how far `p` is from a part's box (0 inside it)
	local function boxDistance(part, p): number
		local q = part.CFrame:PointToObjectSpace(p)
		local h = part.Size / 2
		local dx = math.max(math.abs(q.X) - h.X, 0)
		local dy = math.max(math.abs(q.Y) - h.Y, 0)
		local dz = math.max(math.abs(q.Z) - h.Z, 0)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	-- a floor's box: its footprint (Floor.Size X, Z around the origin), from half its height
	-- below the ground up to its height (floor 6's void islands reach below the origin)
	local function inBox(Floor, origin, p): boolean
		local q = origin:PointToObjectSpace(p)
		local s = Floor.Size
		return math.abs(q.X) <= s.X / 2 and math.abs(q.Z) <= s.Z / 2 and q.Y >= -s.Y / 2 and q.Y <= s.Y
	end

	-- the game build of all the floors (WorldBuilder removes the rock spawns and markers)
	local built: any = nil
	local function mine(): any
		if not built then
			built = roblox.Instance.new("Model")
			WorldBuilder.buildMine(built)
		end
		return built
	end

	T.test("mine ambience: every layer is quiet, known and in streaming range", function()
		T.eq(MineAmbience.Tag, "AmbienceSpot", "AmbienceConfig.Tag")
		T.eq(MineAmbience.Attribute, "Ambience", "AmbienceConfig.Attribute")
		T.eq(MineAmbience.MaxEarshot, 90, "AmbienceConfig.MaxEarshot")
		T.truthy(MineAmbience.MaxEarshot < 96, "heard only inside Workspace.StreamingMinRadius (96)")
		local seen = 0
		for kind, layers in MineAmbience.Kinds do
			seen += 1
			T.truthy(table.find(KINDS, kind), "planned kind " .. kind)
			T.falsy(table.find(LOBBY_KINDS, kind), kind .. " keeps clear of the lobby's kind names")
			T.truthy(#layers >= 1, kind .. " has a layer")
			for i, layer in layers do
				local label = `{kind} layer {i}`
				T.truthy(layer.MinDistance > 0 and layer.MinDistance < layer.MaxDistance, label .. " roll-off")
				T.le(layer.MaxDistance, MineAmbience.MaxEarshot, label .. " earshot")
				if layer.Sound then
					local def = SoundConfig[layer.Sound]
					T.truthy(def, label .. " sound " .. layer.Sound)
					T.truthy(plays(def.Id), label .. " plays in today's clients (" .. def.Id .. ")")
					T.le(def.Volume, 0.45, label .. " plays quietly")
					T.eq(def.Looped == true, layer.Loop == true, label .. " loops exactly when the layer loops")
				else
					T.truthy(type(layer.Id) == "number" and layer.Id >= 0 and layer.Id == math.floor(layer.Id), label .. " owner id")
				end
				if not layer.Loop then
					local every = layer.Every
					T.truthy(every and every[1] > 0 and every[1] <= every[2], label .. " one-shot timer")
				end
				local burst = layer.Burst
				if burst then
					T.truthy(burst[1] >= 1 and burst[1] <= burst[2] and burst[2] <= 8, label .. " burst")
					T.truthy(layer.Gap and layer.Gap > 0, label .. " burst gap")
				end
			end
		end
		T.eq(seen, #KINDS, "seven mine kinds")
		local used: { [string]: boolean } = {}
		-- keyed by floor Id (a new floor can go in between): every floor in MineFloors has a list
		local lists = 0
		for id, kinds in MineAmbience.Floors do
			lists += 1
			T.truthy(MineFloors.ById[id] ~= nil, `kind list for a known floor ({id})`)
			for _, kind in kinds do
				T.truthy(MineAmbience.Kinds[kind], `floor {id} kind {kind}`)
				used[kind] = true
			end
		end
		for _, floor in MineFloors.List do
			T.truthy(MineAmbience.Floors[floor.Id], floor.Id .. " has a kind list")
		end
		T.eq(lists, #MineFloors.List, "a kind list per floor, no strays")
		for _, kind in KINDS do
			T.truthy(used[kind], kind .. " is on a floor")
		end
	end)

	T.test("mine ambience: every floor carries 4-8 spots of its kinds on parts already there", function()
		local map = mine()
		local floors = map:FindFirstChild("MineFloors")
		T.truthy(floors ~= nil, "map.MineFloors")
		local total = 0
		local lo, hi = MineAmbience.SpotsPerFloor[1], MineAmbience.SpotsPerFloor[2]
		T.eq(lo, 4, "at least 4 spots per floor")
		T.eq(hi, 8, "at most 8 spots per floor")
		for i, name in MODULES do
			local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. name)
			local origin = MineFloors.Placement[i]
			local model = floors:FindFirstChild("MineFloor" .. i)
			T.truthy(model ~= nil, name .. " is built")
			local spots = spotsOf(model)
			total += #spots
			T.truthy(#spots >= lo and #spots <= hi, `{name} has 4-8 spots ({#spots})`)
			local kinds: { [string]: number } = {}
			for _, spot in spots do
				local kind = spot:GetAttribute(MineAmbience.Attribute)
				local label = `{name} {spot.Name}`
				T.truthy(type(kind) == "string" and MineAmbience.Kinds[kind], label .. " has a known kind")
				T.truthy(table.find(MineAmbience.Floors[MineFloors.get(i).Id], kind), `{label}: {kind} belongs on floor {i}`)
				kinds[kind] = (kinds[kind] or 0) + 1
				T.eq(spot.Name, "Ambience" .. kind, label .. " name")
				T.truthy(spot:HasTag(MineAmbience.Tag), label .. " tagged")
				T.eq(#spot:GetDescendants(), 0, label .. " carries nothing")
				local host = spot.Parent
				T.truthy(host and host:IsA("BasePart"), label .. " rides on a part")
				T.truthy(host:IsDescendantOf(model), label .. " rides on a part of its floor")
				T.truthy(host.Name ~= "RockSpawn" and host.Name ~= "GiantSpawn", label .. " not on a marker WorldBuilder removes")
				local at = worldOf(spot)
				T.le(boxDistance(host, at), MineKit.AmbienceReach + 0.01, label .. " sits on its host part")
				T.le((at - host.CFrame.Position).Magnitude, host.Size.Magnitude / 2 + 8, label .. " near its host's middle")
				T.truthy(inBox(Floor, origin, at), label .. " inside the floor's box")
			end
			for _, kind in MineAmbience.Floors[MineFloors.get(i).Id] do
				T.truthy(kinds[kind], `{name} plays {kind}`)
			end
		end
		T.eq(#spotsOf(map), total, "every mine spot belongs to a floor")
	end)

	T.test("mine ambience: no point on a floor hears more than 3 loops", function()
		local map = mine()
		local loops = {}
		for _, spot in spotsOf(map) do
			for _, layer in MineAmbience.Kinds[spot:GetAttribute(MineAmbience.Attribute)] do
				if layer.Loop then
					table.insert(loops, { At = worldOf(spot), Reach = layer.MaxDistance })
				end
			end
		end
		T.truthy(#loops > 0, "some loops")
		T.eq(MineAmbience.MaxLoops, 3, "MaxLoops")
		local step = 3
		for i, name in MODULES do
			local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. name)
			local origin = MineFloors.Placement[i]
			local s = Floor.Size
			local worst, where = 0, nil
			for x = -s.X / 2, s.X / 2, step do
				for z = -s.Z / 2, s.Z / 2, step do
					for y = -s.Y / 2, s.Y, step do
						local p = origin:PointToWorldSpace(Vector3.new(x, y, z))
						local heard = 0
						for _, loop in loops do
							if (loop.At - p).Magnitude < loop.Reach then
								heard += 1
							end
						end
						if heard > worst then
							worst, where = heard, Vector3.new(x, y, z)
						end
					end
				end
			end
			T.le(worst, MineAmbience.MaxLoops, `{name}: loops heard at {where}`)
		end
	end)

	T.test("mine ambience: the spots add no parts", function()
		local real = MineKit.ambience
		for _, name in MODULES do
			local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. name)
			local with = Floor.build(roblox.Instance.new("Folder"), MineFloors.Placement[1], { Cutaway = false })
			local spots = #spotsOf(with)
			MineKit.ambience = function(_host, _kind, _at)
				return roblox.Instance.new("Attachment")
			end
			local ok, without = pcall(Floor.build, roblox.Instance.new("Folder"), MineFloors.Placement[1], { Cutaway = false })
			MineKit.ambience = real
			T.truthy(ok, name .. " builds without spots: " .. tostring(without))
			T.truthy(spots > 0, name .. " has spots")
			T.eq(#spotsOf(without), 0, name .. " no spots when MineKit.ambience makes none")
			T.eq(count(with, "BasePart"), count(without, "BasePart"), name .. " part count unchanged by the spots")
		end
	end)

	T.test("elevator: the arrival sting", function()
		local def = SoundConfig.ElevatorArrive
		T.truthy(def, "SoundConfig.ElevatorArrive")
		T.truthy(plays(def.Id), "the sting plays in today's clients (" .. def.Id .. ")")
		T.falsy(def.Looped, "the sting plays once")
		T.truthy(SoundConfig.ElevatorDing, "the ding before it")
	end)
end
