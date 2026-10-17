--[[
	Kit machines preview (scene "kit_machines" in tools/lune/export_scene.luau,
	shots in tools/preview/kit_machines_shots.json): the Kenney Factory Kit
	machines from src/shared/Builders/KitMachines.luau.
	  - a plot pad with every kit machine in iron (level 0), belts into and
	    out of the Cleaning Plant, ore on the way, water and smoke stand-ins;
	  - the upgrade ladder: the same machine at levels 0..4 (iron -> shards
	    -> crystal frames -> whole crystal), with level signs;
	  - the crystal themes: a level 4 machine in each theme.
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3

Gallery.Layout = {
	{ Id = "CleaningStation", X = 0, Z = 1, R = 0 },
	{ Id = "ClayFurnace", X = 4, Z = 1, R = 0 },
	{ Id = "Crusher", X = 7, Z = 1, R = 0 },
	{ Id = "AutoCleaner", X = 10, Z = 1, R = 0 },
	{ Id = "BlastFurnace", X = 0, Z = 5, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 4, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 3, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 0, R = 0 },
}

Gallery.LadderX = 70 -- centre of the ladder pad
Gallery.ThemeX = 136 -- centre of the theme pad
Gallery.MaxX = -70 -- centre of the max level plot (every machine at the last level)
Gallery.LadderMachine = "ClayFurnace"
Gallery.ThemeMachine = "Crusher"

local function count(model: any): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- A level sign: a dark board with light text, standing in front of a machine.
local function sign(parent: any, cf: any, text: string, width: number)
	local board = roblox.Instance.new("Part")
	board.Anchored = true
	board.Size = V3.new(width, 1.1, 0.2)
	board.CFrame = cf
	board.Color = C3.fromRGB(44, 46, 58)
	board.Material = roblox.Enum.Material.SmoothPlastic
	board.Parent = parent
	local gui = roblox.Instance.new("SurfaceGui")
	gui.Face = roblox.Enum.NormalId.Front
	gui.SizingMode = roblox.Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = board
	local label = roblox.Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = roblox.UDim2.fromScale(0.94, 0.8)
	label.Position = roblox.UDim2.fromScale(0.03, 0.1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = C3.fromRGB(255, 196, 72)
	label.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.LuckiestGuy)
	label.Parent = gui
end

function Gallery.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Old = require("./machines_gallery")
	local Dummy = require("./dummy")
	local root = roblox.Instance.new("Model")
	root.Name = "KitMachineGallery"
	root.Parent = parent
	local CELL = GameConfig.CellSize
	local half = GameConfig.PlotCells * CELL / 2

	-- lawn and plot pads (gravel with faint cell lines and a low kerb)
	Geo.block(root, CF.new(30, -1.06, 0), V3.new(320, 2, 260), C3.fromRGB(150, 196, 92))
	local function pad(cx: number, w: number, d: number, lines: boolean)
		Geo.block(root, CF.new(cx, -0.5, 0), V3.new(w, 1, d), C3.fromRGB(214, 192, 150))
		if lines then
			for i = 1, GameConfig.PlotCells - 1 do
				local p = -half + i * CELL
				Geo.block(root, CF.new(cx + p, 0.005, 0), V3.new(0.08, 0.01, d), C3.fromRGB(196, 174, 134))
				Geo.block(root, CF.new(cx, 0.005, p), V3.new(w, 0.01, 0.08), C3.fromRGB(196, 174, 134))
			end
		end
		for _, side in { -1, 1 } do
			Geo.block(root, CF.new(cx + side * (w / 2 + 0.4), 0.2, 0), V3.new(0.8, 0.8, d + 1.6), C3.fromRGB(120, 112, 108))
			Geo.block(root, CF.new(cx, 0.2, side * (d / 2 + 0.4)), V3.new(w + 1.6, 0.8, 0.8), C3.fromRGB(120, 112, 108))
		end
	end
	pad(0, half * 2, half * 2, true)
	pad(Gallery.LadderX, 64, half * 2, false)
	pad(Gallery.ThemeX, 50, half * 2, false)
	pad(Gallery.MaxX, half * 2, half * 2, true)

	local placed = {}
	local belts = {}
	local counts = {}
	for _, entry in Gallery.Layout do
		local model = if KitMachines.has(entry.Id) then KitMachines.build(entry.Id, 0) else MachineBuilder.build(entry.Id)
		model:PivotTo(Grid.localCFrame(entry.Id, entry.X, entry.Z, entry.R))
		model.Parent = root
		placed[entry.Id] = model
		counts[entry.Id] = count(model)
		Old.paintGuis(Loader, root, model)
		if entry.Id == "Conveyor" then
			table.insert(belts, model)
		end
	end

	-- ore on the way (dropped so its lowest point rests on `surface`)
	local function ore(kind: string, oreId: string, cf: any, surface: number, seed: number)
		local item = ItemBuilder.build({ Kind = kind, OreId = oreId, Grade = "Clean" }, cf, seed)
		local low = math.huge
		for _, d in item:GetDescendants() do
			if d:IsA("BasePart") then
				local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
				local h = math.abs(r10) * d.Size.X / 2 + math.abs(r11) * d.Size.Y / 2 + math.abs(r12) * d.Size.Z / 2
				low = math.min(low, d.CFrame.Position.Y - h)
			end
		end
		for _, d in item:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + V3.new(0, surface - low, 0)
			end
		end
		item.Parent = root
	end
	local cleaner = placed.AutoCleaner.PrimaryPart
	local shower = cleaner.CFrame:PointToWorldSpace(cleaner:FindFirstChild("WaterIn").CFrame.Position)
	local rollerTop = cleaner.CFrame.Position.Y + 0.15 + 1.35 + 0.31
	ore("Raw", "Copper", CF.new(shower.X, rollerTop + 1, shower.Z) * CF.Angles(0, 0.4, 0), rollerTop, 7)
	local view = V3.new(1, 0, -1.2).Unit
	Old.water(Loader, root, placed.CleaningStation, 0.4, view)
	Old.water(Loader, root, placed.AutoCleaner, 1, view, rollerTop + 1.05)
	Old.steam(Loader, root, placed.AutoCleaner:FindFirstChild("Vent", true))
	Old.smoke(Loader, root, placed.ClayFurnace:FindFirstChild("ChimneyTop", true), 0.8)
	Old.smoke(Loader, root, placed.BlastFurnace:FindFirstChild("ChimneyTop", true), 1)
	local function onBelt(belt: any, x: number, z: number): (any, number)
		local cf = belt:GetPivot() * CF.new(x, 1.5, z)
		return cf, belt:FindFirstChild("Belt").CFrame.Position.Y + 0.25
	end
	local cf1, top1 = onBelt(belts[1], 0.1, 0.6)
	ore("Raw", "Iron", cf1 * CF.Angles(0, 1.1, 0), top1, 11)
	local cf3, top3 = onBelt(belts[3], -0.1, -0.4)
	ore("Clean", "Copper", cf3 * CF.Angles(0, 0.7, 0), top3, 5)
	local station = placed.CleaningStation.PrimaryPart.CFrame
	Dummy.build(root, CF, station * CF.new(-5.2, 0, -4.6) * CF.Angles(0, math.pi * 0.85, 0), "idle")

	-- the same plot with every machine at the max level
	for _, entry in Gallery.Layout do
		local model = if KitMachines.has(entry.Id)
			then KitMachines.build(entry.Id, KitMachines.MaxLevel)
			else MachineBuilder.build(entry.Id)
		model:PivotTo(CF.new(Gallery.MaxX, 0, 0) * Grid.localCFrame(entry.Id, entry.X, entry.Z, entry.R))
		model.Parent = root
		Old.paintGuis(Loader, root, model)
	end

	-- the upgrade ladder: levels 0..4 left to right
	local lx = Gallery.LadderX
	for level = 0, KitMachines.MaxLevel do
		local x = lx + 24 - level * 12 -- +X shows on the left of a camera looking +Z
		local model = KitMachines.build(Gallery.LadderMachine, level)
		model:PivotTo(CF.new(x, 0, -8))
		model.Parent = root
		counts[Gallery.LadderMachine .. " L" .. level] = count(model)
		sign(root, CF.new(x, 0.75, -14.2) * CF.Angles(0.3, 0, 0), "LV " .. level, 3.2)
		if level == 0 then
			Old.smoke(Loader, root, model:FindFirstChild("ChimneyTop", true), 0.8)
		end
	end
	-- the crystal themes at the max level
	local themes = { "Aqua", "Amethyst", "Rose" }
	for i, theme in themes do
		local x = Gallery.ThemeX + 14 - (i - 1) * 14
		local model = KitMachines.build(Gallery.ThemeMachine, KitMachines.MaxLevel, theme)
		model:PivotTo(CF.new(x, 0, -8))
		model.Parent = root
		counts[Gallery.ThemeMachine .. " " .. theme] = count(model)
		sign(root, CF.new(x, 0.75, -14.2) * CF.Angles(0.3, 0, 0), string.upper(theme), 4.2)
	end

	local names = {}
	for id in counts do
		table.insert(names, id)
	end
	table.sort(names)
	for _, id in names do
		print(string.format("  %-22s %3d parts", id, counts[id]))
	end
	return root
end

return Gallery
