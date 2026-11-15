--[[
	Every MeshKit template on a dark floor, in rows (ores, rocks per floor, props), for a quick
	look at the owner's models in the preview pipeline (MESHY=1 mounts stand-ins before the upload).

	  MESHY=1 lune run tools/lune/export_scene.luau meshy_gallery
	  SHOTS_EXTRA=tools/preview/meshy_shots.json node tools/preview/render.mjs meshy_gallery meshy_ores meshy_rocks meshy_props
]]

local roblox = require("@lune/roblox") :: any
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3

local Gallery = {}

function Gallery.build(Loader: any, workspace: any)
	local MeshKit = Loader.requirePath("ReplicatedStorage.Shared.Builders.MeshKit")
	local Catalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local model = roblox.Instance.new("Model")
	model.Name = "MeshyGallery"
	local floor = roblox.Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(220, 1, 200)
	floor.CFrame = CFrame.new(40, -0.5, 30)
	floor.Color = Color3.fromRGB(46, 50, 70)
	floor.Parent = model

	local function place(name: string, x: number, z: number, size: number)
		local own = MeshKit.box(name)
		if not own then
			return
		end
		local s = size / math.max(own.X, own.Y, own.Z)
		local box = own * s
		local p = MeshKit.part(name, box, CFrame.new(x, box.Y / 2, z), { CastShadow = true })
		if p then
			p.Parent = model
		end
	end

	-- row 0: ores (display), row 1: the same ores _Low
	local ores = {}
	for id in Catalog.Ores do
		table.insert(ores, id)
	end
	table.sort(ores)
	for i, id in ores do
		place("Ore_" .. id, -30 + (i - 1) * 4, -20, 3)
		place("Ore_" .. id .. "_Low", -30 + (i - 1) * 4, -15, 3)
	end
	-- rows 2-7: rocks per floor
	local floors = { "Quarry", "EmberCaves", "DeepHollow", "SunkenPalace", "StormglassRift", "HeartstoneCore" }
	local kinds = { "Small", "Big", "Crystal", "Golden", "Geode", "Artifact", "Giant" }
	for f, fid in floors do
		for k, kind in kinds do
			place("Rock_" .. fid .. "_" .. kind, -30 + (k - 1) * 9, -4 + (f - 1) * 9, if kind == "Giant" then 8 else 6)
		end
	end
	-- props on the right
	local props = {
		"PlotBase",
		"CleaningStation",
		"DisplayPedestal",
		"Museum",
		"TreeGreen",
		"TreeOrange",
		"TreeYellow",
		"MossyCliff",
		"MineElevator",
		"Meteor",
	}
	for i, name in props do
		local col = (i - 1) % 4
		local row = (i - 1) // 4
		place("Prop_" .. name, 50 + col * 16, -10 + row * 18, if name == "MineElevator" or name == "MossyCliff" then 14 else 11)
	end
	model.Parent = workspace
end

return Gallery
