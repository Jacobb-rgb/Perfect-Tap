--[[
	Ore train preview (scene "trains" for tools/lune/export_scene.luau, shots in
	tools/preview/train_shots.json): three trains (locomotive + 2 loaded ore
	wagons) in plot banner colors on straight tracks, laid out like the Kenney
	Train Kit preview, plus forgekeepers for scale (kept clear of the drive
	wheels), sidings with an empty wagon (amber) and white / purple trains, and a
	"studio" corner on a dark floor framed like the Kenney reference sheet with a
	lineup of all eight plot banner colors.
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

-- all eight plot banner colors (PlotBuilder BANNER_COLORS)
Gallery.Banners = {
	{ 220, 70, 50 },
	{ 240, 170, 40 },
	{ 80, 180, 90 },
	{ 60, 140, 220 },
	{ 160, 90, 220 },
	{ 230, 110, 170 },
	{ 60, 190, 190 },
	{ 240, 230, 210 },
}

-- the three main trains in the yard
Gallery.Trains = {
	{ Color = { 220, 70, 50 }, Loads = { { "Copper", "Iron", "Coal" }, { "Copper", "Silver" } } },
	{ Color = { 60, 140, 220 }, Loads = { { "Gold", "Silver" }, { "Azurium", "Iron", "Gold" } } },
	{ Color = { 80, 180, 90 }, Loads = { { "Emerald", "Ruby", "Gold" }, { "Coal", "Copper" } } },
}

-- Model-space CFrame of a coupler attachment (the model is still at the origin).
local function coupler(model: any, name: string): any
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name == name then
			return d.Parent.CFrame * d.CFrame
		end
	end
	error("no " .. name .. " on " .. model.Name)
end

--[[
	A locomotive and its wagons chained by their couplers; `front` is the
	CFrame of the locomotive's Root (on the rails). Returns the models.
]]
function Gallery.consist(Loader: any, parent: any, front: any, color: any, loads: { { any } }): { any }
	local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")
	local list = {}
	local loco = TrainBuilder.locomotive(color)
	local back = coupler(loco, "CouplerBack")
	loco:PivotTo(front)
	loco.Parent = parent
	-- what the client adds: steam at the Smoke attachment, a warm lamp light
	for _, d in loco:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "Smoke" then
			local steam = roblox.Instance.new("ParticleEmitter")
			steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
			steam.Color = roblox.ColorSequence.new(roblox.Color3.fromRGB(205, 205, 212))
			steam.Parent = d.Parent
		elseif d:IsA("BasePart") and d.Name == "LampGlass" then
			local light = roblox.Instance.new("PointLight")
			light.Color = d.Color
			light.Range = 8
			light.Brightness = 0.8
			light.Parent = d
		end
	end
	table.insert(list, loco)
	local cf = front
	for _, load in loads do
		local wagon = TrainBuilder.wagon(color, load)
		local wagonCf = cf * back * coupler(wagon, "CouplerFront"):Inverse()
		back = coupler(wagon, "CouplerBack")
		wagon:PivotTo(wagonCf)
		wagon.Parent = parent
		table.insert(list, wagon)
		cf = wagonCf
	end
	return list
end

function Gallery.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Dummy = require("./dummy")
	local root = roblox.Instance.new("Model")
	root.Name = "TrainGallery"
	root.Parent = parent

	-- a neutral grey-brown gravel yard (no orange cast on the colors)
	Geo.block(root, CF.new(0, -0.5, 0), V3.new(700, 1, 700), C3.fromRGB(118, 112, 106), roblox.Enum.Material.Slate)

	local function oreColors(ids: { string }): { any }
		local colors = {}
		for _, id in ids do
			table.insert(colors, OreData.ById[id].Color)
		end
		return colors
	end

	local spacing = 13
	for i, info in Gallery.Trains do
		local x = (i - 2) * spacing
		local track = TrainBuilder.track(72)
		track:PivotTo(CF.new(x, 0, 2))
		track.Parent = root
		local loads = {}
		for _, ids in info.Loads do
			table.insert(loads, oreColors(ids))
		end
		local color = C3.fromRGB(info.Color[1], info.Color[2], info.Color[3])
		Gallery.consist(Loader, root, CF.new(x, TrainBuilder.RailTop, -12), color, loads)
	end

	-- a short siding: an empty wagon behind a locomotive in amber (another plot)
	local sidingX = 2 * spacing
	local siding = TrainBuilder.track(36)
	siding:PivotTo(CF.new(sidingX, 0, -6))
	siding.Parent = root
	Gallery.consist(Loader, root, CF.new(sidingX, TrainBuilder.RailTop, -16), C3.fromRGB(240, 170, 40), { {} })
	-- two more sidings: a white and a purple train (the colors most likely to wash out / go dark)
	local sidings = {
		{ X = 3 * spacing, Color = C3.fromRGB(240, 230, 210), Load = { "Coal", "Copper", "Iron" } },
		{ X = 4 * spacing, Color = C3.fromRGB(160, 90, 220), Load = { "Amethyst", "Silver", "Gold" } },
	}
	for _, info in sidings do
		local track = TrainBuilder.track(36)
		track:PivotTo(CF.new(info.X, 0, -6))
		track.Parent = root
		Gallery.consist(Loader, root, CF.new(info.X, TrainBuilder.RailTop, -16), info.Color, { oreColors(info.Load) })
	end

	-- a station sign at the back of the yard
	for _, side in { -1, 1 } do
		Geo.block(root, CF.new(side * 7, 3, 44), V3.new(0.6, 6, 0.6), C3.fromRGB(96, 70, 48), roblox.Enum.Material.Wood)
	end
	local sign = Geo.block(root, CF.new(0, 6.2, 44), V3.new(16, 2.6, 0.4), C3.fromRGB(56, 40, 30), roblox.Enum.Material.Wood)
	local gui = roblox.Instance.new("SurfaceGui")
	gui.Face = roblox.Enum.NormalId.Front
	gui.Parent = sign
	local label = roblox.Instance.new("TextLabel")
	label.Text = "ORE TRAINS"
	label.TextColor3 = C3.fromRGB(255, 214, 120)
	label.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
	label.Parent = gui

	-- forgekeepers for scale: behind the red cab beside the first wagon (clear of
	-- the drive wheels) and between the blue and green trains
	Dummy.build(root, CF, CF.lookAt(V3.new(-spacing - 5.8, 0, 1.2), V3.new(-spacing - 30, 0, 4)), "idle")
	Dummy.build(
		root,
		CF,
		CF.lookAt(V3.new(spacing - 6.4, 0, 4), V3.new(spacing - 6.4, 0, -10)),
		"idle",
		{ shirt = C3.fromRGB(70, 120, 170), pants = C3.fromRGB(50, 50, 60) }
	)

	-- a "studio" corner far away on a dark floor, framed like the Kenney reference
	-- sheet (docs/art/kenney_refs/train_kit.jpg): green locomotive, copper wagon, track
	local studio = V3.new(300, 0, 0)
	Geo.block(root, CF.new(studio + V3.new(0, -0.45, 0)), V3.new(200, 1, 200), C3.fromRGB(42, 42, 51))
	local loco = TrainBuilder.locomotive(C3.fromRGB(80, 180, 90))
	loco:PivotTo(CF.new(studio + V3.new(-20, 0, 0)))
	loco.Parent = root
	local wagon = TrainBuilder.wagon(C3.fromRGB(80, 180, 90), { OreData.ById.Copper.Color })
	wagon:PivotTo(CF.new(studio))
	wagon.Parent = root
	local empty = TrainBuilder.wagon(C3.fromRGB(60, 140, 220))
	empty:PivotTo(CF.new(studio + V3.new(20, 0, 0)))
	empty.Parent = root
	local piece = TrainBuilder.track(12)
	piece:PivotTo(CF.new(studio + V3.new(40, 0, 0)))
	piece.Parent = root

	-- all eight banner colors in a row (an echelon so a 3/4 camera sees every cab)
	for i, c in Gallery.Banners do
		local color = C3.fromRGB(c[1], c[2], c[3])
		local at = studio + V3.new((i - 4.5) * 12, 0, 71 + (i - 4.5) * 6)
		local loco = TrainBuilder.locomotive(color)
		loco:PivotTo(CF.new(at))
		loco.Parent = root
	end
	return root
end

return Gallery
