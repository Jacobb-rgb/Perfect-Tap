--[[
	Kit machines preview (scene "kit_machines" in tools/lune/export_scene.luau,
	shots in tools/preview/kit_machines_shots.json): the machines and belts
	from src/shared/Builders/KitMachines.luau.
	  - a plot with every machine at level 0, belts with end caps into and
	    out of the Cleaning Plant, ore on the way, water and smoke stand-ins
	    (the pads are metal plates with glowing edges like the owner's
	    reference, docs/art/machines_reference.webp);
	  - the same plot with every machine at the max level;
	  - the upgrade ladder: one machine at levels 0..4, with level signs;
	  - the crystal themes: a max level machine in each theme;
	  - the belts: a long straight run with end caps, a Belt Lift and a Slide.
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3

-- Caps: "start" / "finish" add an end cap on that end of the belt cell.
Gallery.Layout = {
	{ Id = "CleaningStation", X = 0, Z = 1, R = 0 },
	{ Id = "ClayFurnace", X = 4, Z = 1, R = 0 },
	{ Id = "Crusher", X = 7, Z = 1, R = 0 },
	{ Id = "AutoCleaner", X = 10, Z = 1, R = 0 },
	{ Id = "BlastFurnace", X = 0, Z = 5, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 4, R = 0, Caps = "start" },
	{ Id = "Conveyor", X = 11, Z = 3, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 0, R = 0, Caps = "finish" },
}

Gallery.LadderX = 70 -- centre of the ladder pad
Gallery.ThemeX = 136 -- centre of the theme pad
Gallery.BeltX = 204 -- centre of the belt pad
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

-- A sign: a dark board with gold text, standing in front of a machine.
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
	local NEON = roblox.Enum.Material.Neon
	-- (bigger plots) the layout is on a 12-cell grid: keep it at the pads' centres
	local gridShift = (GameConfig.PlotCells - 12) / 2

	-- lawn and metal pads: dark plates, lighter tile seams, a glowing orange edge
	Geo.block(root, CF.new(60, -1.06, 0), V3.new(480, 2, 260), C3.fromRGB(130, 186, 82))
	local function pad(cx: number, w: number, d: number)
		Geo.block(root, CF.new(cx, -0.6, 0), V3.new(w + 2.4, 1.2, d + 2.4), C3.fromRGB(46, 48, 58))
		Geo.block(root, CF.new(cx, -0.5, 0), V3.new(w, 1, d), C3.fromRGB(104, 108, 120))
		for i = 1, math.floor(w / CELL) - 1 do
			local x = cx - w / 2 + i * CELL
			Geo.block(root, CF.new(x, 0.005, 0), V3.new(0.1, 0.01, d), C3.fromRGB(82, 86, 98))
		end
		for i = 1, math.floor(d / CELL) - 1 do
			local z = -d / 2 + i * CELL
			Geo.block(root, CF.new(cx, 0.005, z), V3.new(w, 0.01, 0.1), C3.fromRGB(82, 86, 98))
		end
		for _, side in { -1, 1 } do
			for k = 0, 2 do
				local glowZ = -d / 2 + d * (k + 0.5) / 3
				Geo.block(
					root,
					CF.new(cx + side * (w / 2 + 1.21), -0.4, glowZ),
					V3.new(0.05, 0.25, d / 3 * 0.55),
					C3.fromRGB(255, 128, 20),
					NEON
				)
				local glowX = cx - w / 2 + w * (k + 0.5) / 3
				Geo.block(
					root,
					CF.new(glowX, -0.4, side * (d / 2 + 1.21)),
					V3.new(w / 3 * 0.55, 0.25, 0.05),
					C3.fromRGB(255, 128, 20),
					NEON
				)
			end
		end
	end
	pad(0, half * 2, half * 2)
	pad(Gallery.MaxX, half * 2, half * 2)
	pad(Gallery.LadderX, 64, half * 2)
	pad(Gallery.ThemeX, 52, half * 2)
	pad(Gallery.BeltX, 64, half * 2)

	local function capsFor(entry: any): any
		if entry.Caps == "start" then
			return { start = { arrow = "right" } }
		elseif entry.Caps == "finish" then
			return { finish = {} }
		end
		return nil
	end

	local function placePlot(offset: any, level: number): { [string]: any }
		local placed = {}
		for _, entry in Gallery.Layout do
			local model = if entry.Id == "Conveyor" then KitMachines.conveyor(capsFor(entry)) else KitMachines.build(entry.Id, level)
			model:PivotTo(offset * Grid.localCFrame(entry.Id, entry.X + gridShift, entry.Z + gridShift, entry.R))
			model.Parent = root
			Old.paintGuis(Loader, root, model)
			if entry.Id ~= "Conveyor" then
				placed[entry.Id] = model
			end
		end
		return placed
	end

	local counts = {}
	local placed = placePlot(CF.new(0, 0, 0), 0)
	for id, model in placed do
		counts[id] = count(model)
	end
	counts.Conveyor = count(KitMachines.conveyor())
	counts["Conveyor + caps"] = count(KitMachines.conveyor({ start = { arrow = "right" }, finish = {} }))
	placePlot(CF.new(Gallery.MaxX, 0, 0), KitMachines.MaxLevel)

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
	local rollerTop = cleaner.CFrame.Position.Y + 0.15 + 1.35 + 0.33
	ore("Raw", "Copper", CF.new(shower.X, rollerTop + 1, shower.Z) * CF.Angles(0, 0.4, 0), rollerTop, 7)
	local view = V3.new(1, 0, -1.2).Unit
	Old.water(Loader, root, placed.CleaningStation, 0.4, view)
	Old.water(Loader, root, placed.AutoCleaner, 1, view, rollerTop + 1.05)
	Old.steam(Loader, root, placed.AutoCleaner:FindFirstChild("Vent", true))
	Old.smoke(Loader, root, placed.ClayFurnace:FindFirstChild("ChimneyTop", true), 1.1)
	Old.smoke(Loader, root, placed.BlastFurnace:FindFirstChild("ChimneyTop", true), 1.4)
	local beltTop = 0.8
	local function cell(x: number, z: number): any
		return Grid.localCFrame("Conveyor", x + gridShift, z + gridShift, 0)
	end
	ore("Raw", "Iron", cell(11, 4) * CF.new(0.1, 1.5, 0.6) * CF.Angles(0, 1.1, 0), beltTop, 11)
	ore("Clean", "Copper", cell(11, 0) * CF.new(-0.1, 1.5, -0.4) * CF.Angles(0, 0.7, 0), beltTop, 5)
	local station = placed.CleaningStation.PrimaryPart.CFrame
	Dummy.build(root, CF, station * CF.new(-5.2, 0, -4.6) * CF.Angles(0, math.pi * 0.85, 0), "idle")

	-- the upgrade ladder: levels 0..4 left to right (+X shows on the left of a camera looking +Z)
	local lx = Gallery.LadderX
	for level = 0, KitMachines.MaxLevel do
		local x = lx + 24 - level * 12
		local model = KitMachines.build(Gallery.LadderMachine, level)
		model:PivotTo(CF.new(x, 0, -8))
		model.Parent = root
		Old.paintGuis(Loader, root, model)
		counts[Gallery.LadderMachine .. " L" .. level] = count(model)
		sign(root, CF.new(x, 0.75, -14.2) * CF.Angles(0.3, 0, 0), "LV " .. level, 3.2)
		if level == 0 then
			Old.smoke(Loader, root, model:FindFirstChild("ChimneyTop", true), 1.1)
		end
	end
	-- the crystal themes at the max level
	for i, theme in { "Aqua", "Amethyst", "Rose" } do
		local x = Gallery.ThemeX + 14 - (i - 1) * 14
		local model = KitMachines.build(Gallery.ThemeMachine, KitMachines.MaxLevel, theme)
		model:PivotTo(CF.new(x, 0, -8))
		model.Parent = root
		Old.paintGuis(Loader, root, model)
		counts[Gallery.ThemeMachine .. " " .. theme] = count(model)
		sign(root, CF.new(x, 0.75, -14.2) * CF.Angles(0.3, 0, 0), string.upper(theme), 4.2)
	end

	-- the belts: a straight run of six cells along X (items move toward -X), a lift and a slide
	local bx = Gallery.BeltX
	for i = 0, 5 do
		-- items move toward +X here, so the run starts at the last cell (i = 5)
		local caps = if i == 5 then { start = { arrow = "right" } } elseif i == 0 then { finish = {} } else nil
		local model = KitMachines.conveyor(caps)
		model:PivotTo(CF.new(bx + 10 - i * 4, 0, -14) * CF.Angles(0, -math.pi / 2, 0))
		model.Parent = root
		Old.paintGuis(Loader, root, model)
		if i % 2 == 1 then
			ore("Clean", if i == 1 then "Gold" else "Copper", CF.new(bx + 10 - i * 4, 1.5, -14) * CF.Angles(0, 0.5 * i, 0), beltTop, 20 + i)
		end
	end
	local lift = KitMachines.slope(true)
	lift:PivotTo(CF.new(bx + 12, 0, 6) * CF.Angles(0, math.pi / 2, 0)) -- rises toward -X (the right of the camera)
	lift.Parent = root
	Old.paintGuis(Loader, root, lift)
	local slide = KitMachines.slope(false)
	slide:PivotTo(CF.new(bx - 12, 0, 6) * CF.Angles(0, math.pi / 2, 0))
	slide.Parent = root
	Old.paintGuis(Loader, root, slide)
	counts.BeltLift = count(lift)
	sign(root, CF.new(bx + 12, 0.75, 1.0) * CF.Angles(0.3, 0, 0), "BELT LIFT", 4.4)
	sign(root, CF.new(bx - 12, 0.75, 1.0) * CF.Angles(0.3, 0, 0), "SLIDE", 3.4)

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
