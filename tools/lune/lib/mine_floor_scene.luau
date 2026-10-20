--[[
	Preview of one mine floor area (src/server/World/Mine/Floor<N>*.luau) with
	rocks on its spawn points (RockBuilder) and a stand-in player at the
	entrance. Scene "mine_floor" (lune run tools/lune/export_scene.luau mine_floor <N>)
	-> build/preview/mine_floor_<N>.json; shots in tools/preview/mine_floor<N>_shots.json
	(scene "mine_floor_<N>").

	Rock kinds on the spawns (fixed seed per spawn): the back ("Deep") spawns get
	more crystals; every floor shows one golden rock, one geode, one artifact rock,
	and the Giant Crystal on GiantSpawn.
]]

local roblox = require("@lune/roblox") :: any

local MineFloorScene = {}

MineFloorScene.Modules = { "Floor1Quarry", "Floor2Ember", "Floor3Lagoon", "Floor4Palace", "Floor5Core" }

-- index 0: the shared MineKit pieces side by side (elevator, gate, ore lift, wall, crystals)
local function buildKit(Loader, workspace)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local m = roblox.Instance.new("Model")
	m.Name = "MineKitGallery"
	m.Parent = workspace
	Geo.block(m, CF.new(0, -0.5, 0), V3.new(140, 1, 80), C3.fromRGB(70, 66, 74))
	local pal = MineFloors.get(2).Palette
	local colors = { pal.Mid, pal.Light, pal.Dark }
	MineKit.elevator(m, CF.lookAt(V3.new(-30, 0, 0), V3.new(-30, 0, 10)), 4)
	MineKit.gate(m, CF.lookAt(V3.new(0, 0, 0), V3.new(0, 0, 10)), 12, 5, colors)
	MineKit.oreLift(m, V3.new(30, 0, 0), "KitPreview")
	MineKit.wall(m, V3.new(-60, 0, -25), V3.new(60, 0, -25), 18, V3.new(0, 0, 1), colors, Rng.new(4), { Glow = C3.fromRGB(255, 140, 50) })
	MineKit.crystals(m, CF.new(14, 0, -14), 7, 6, "Tipped", { pal.Crystal, pal.Crystal2 }, 3)
	MineKit.crystals(m, CF.new(-14, 0, -14), 9, 8, "Shell", { MineFloors.get(3).Palette.Crystal, MineFloors.get(3).Palette.Crystal2 }, 5)
	local lamp = Geo.block(m, CF.new(0, 14, 16), V3.new(0.2, 0.2, 0.2), C3.new(1, 1, 1), nil, { Transparency = 1 })
	local l = roblox.Instance.new("PointLight")
	l.Range = 60
	l.Brightness = 1.2
	l.Color = C3.fromRGB(255, 240, 220)
	l.Parent = lamp
	return m
end

function MineFloorScene.build(Loader, workspace, index: number)
	if index == 0 then
		return buildKit(Loader, workspace)
	end
	local CF = Loader.CFrame
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. MineFloorScene.Modules[index])
	-- the preview shows the floor's own Mine Lift (in the game Railway builds it from TrainConfig)
	Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit").PreviewLifts = true
	local floor = MineFloors.get(index)
	local model = Floor.build(workspace, CF.new(0, 0, 0), { Cutaway = true })

	local spawns = model:FindFirstChild("RockSpawns")
	local list = {}
	if spawns then
		for _, p in spawns:GetChildren() do
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a.CFrame.Position, b.CFrame.Position
		if math.abs(pa.Z - pb.Z) > 0.01 then
			return pa.Z > pb.Z
		end
		return pa.X < pb.X
	end)
	local specials = { "Golden", "Geode", "Artifact" }
	local rocks = roblox.Instance.new("Folder")
	rocks.Name = "Rocks"
	rocks.Parent = model
	for i, p in list do
		local rng = Rng.new(index * 1000 + i)
		local deep = p:GetAttribute("Deep") == true
		local kind
		if i % 6 == 0 and #specials > 0 then
			kind = table.remove(specials, 1)
		else
			local roll = rng:next()
			if roll < (if deep then 0.3 else 0.12) then
				kind = "Crystal"
			elseif roll < 0.45 then
				kind = "Big"
			else
				kind = "Small"
			end
		end
		local weights = if kind == "Crystal" or kind == "Golden" then floor.CrystalOres else floor.Ores
		local ores = {}
		for _ = 1, MineFloors.OreCount[kind] do
			table.insert(ores, rng:weighted(weights))
		end
		local pos = p.CFrame.Position
		local rock = RockBuilder.build(index, kind, ores, CF.new(pos.X, pos.Y, pos.Z), index * 77 + i)
		rock.Parent = rocks
	end
	local giant = model:FindFirstChild("GiantSpawn")
	if giant then
		local pos = giant.CFrame.Position
		RockBuilder.build(index, "Giant", {}, CF.new(pos.X, pos.Y, pos.Z), index * 13).Parent = rocks
	end
	local entrance = model:FindFirstChild("Entrance")
	if entrance then
		local pos = entrance.CFrame.Position
		require("./dummy").build(model, CF, CF.lookAt(pos, pos + roblox.Vector3.new(0, 0, -10)), "idle")
	end
	return model
end

return MineFloorScene
