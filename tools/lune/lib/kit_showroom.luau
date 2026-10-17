--[[
	Machine showroom (scene "kit_showroom", shots in
	tools/preview/kit_showroom_shots.json): every machine of the roster
	(KitMachines.Catalog) at level 0 on a metal floor, one row per group
	(Cleaning, Furnaces, Special, Transport, Power) with a name sign in front
	of each machine. Belts are shown as short runs, the poles with cables.
]]

local roblox = require("@lune/roblox") :: any

local Showroom = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3

Showroom.Groups = { "Cleaning", "Furnaces", "Special", "Transport", "Power" }
Showroom.RowGap = 50 -- studs between rows (along Z)
Showroom.Gap = 6 -- studs between machines in a row

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
	label.Size = roblox.UDim2.fromScale(0.94, 0.8)
	label.Position = roblox.UDim2.fromScale(0.03, 0.1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = C3.fromRGB(255, 196, 72)
	label.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.LuckiestGuy)
	label.Parent = gui
end

-- Row layout: { id, x, width, depth } per machine, the row's total width.
function Showroom.layout(KitMachines: any, CELL: number): { [string]: { any } }
	local rows = {}
	for _, group in Showroom.Groups do
		rows[group] = {}
	end
	for _, entry in KitMachines.Catalog do
		local size = KitMachines.Sizes[entry.Id]
		local w, d
		if entry.Id == "Conveyor" or entry.Id == "ExpressConveyor" then
			w, d = CELL, CELL * 3
		elseif entry.Id == "BeltLift" or entry.Id == "Slide" then
			w, d = CELL * 3, CELL -- turned sideways so the slope shows
		elseif entry.Id == "PowerPole" then
			w, d = CELL * 4, CELL
		elseif size then
			w, d = size[1] * CELL, size[2] * CELL
		else
			w, d = nil, nil
		end
		table.insert(rows[entry.Group], { entry = entry, w = w, d = d })
	end
	return rows
end

function Showroom.build(Loader: any, parent: any, level: number?)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local Old = require("./machines_gallery")
	local root = roblox.Instance.new("Model")
	root.Name = "Showroom"
	root.Parent = parent
	local CELL = GameConfig.CellSize
	local NEON = roblox.Enum.Material.Neon
	local rows = Showroom.layout(KitMachines, CELL)

	Geo.block(root, CF.new(0, -1.06, 40), V3.new(420, 2, 320), C3.fromRGB(130, 186, 82))
	local counts = {}
	for r, group in Showroom.Groups do
		local items = rows[group]
		for _, it in items do
			if not it.w then
				local size = MachineData.ById[it.entry.Id].Size
				it.w, it.d = size[1] * CELL, size[2] * CELL
			end
		end
		local total = 0
		for i, it in items do
			total += it.w + (if i > 1 then Showroom.Gap else 0)
		end
		local z = (r - 1) * Showroom.RowGap
		-- the row's metal pad with a glowing edge
		local padW, padD = total + 10, 22
		Geo.block(root, CF.new(0, -0.6, z + 2), V3.new(padW + 2, 1.2, padD + 2), C3.fromRGB(46, 48, 58))
		Geo.block(root, CF.new(0, -0.5, z + 2), V3.new(padW, 1, padD), C3.fromRGB(104, 108, 120))
		for _, side in { -1, 1 } do
			Geo.block(
				root,
				CF.new(0, -0.4, z + 2 + side * (padD / 2 + 1.01)),
				V3.new(padW * 0.9, 0.22, 0.05),
				C3.fromRGB(255, 128, 20),
				NEON
			)
		end
		sign(root, CF.new(total / 2 + 4, 3.2, z - 6) * CF.Angles(0, 0, 0), string.upper(group), 7)
		-- machines from left to right on screen (+X shows on the left of a camera looking +Z)
		local x = total / 2
		for _, it in items do
			local id = it.entry.Id
			local cx = x - it.w / 2
			if id == "Conveyor" or id == "ExpressConveyor" then
				for k = 0, 2 do
					local caps = if k == 0 then { start = { arrow = "right" } } elseif k == 2 then { finish = {} } else nil
					local belt = KitMachines.conveyor(caps, id == "ExpressConveyor")
					belt:PivotTo(CF.new(cx, 0, z + CELL - k * CELL))
					belt.Parent = root
					Old.paintGuis(Loader, root, belt)
				end
			elseif id == "PowerPole" then
				local poles = {}
				for k = 0, 2 do
					local pole = KitMachines.buildAny(id, 0)
					pole:PivotTo(CF.new(cx + CELL * 1.5 - k * CELL * 1.5, 0, z + 2))
					pole.Parent = root
					table.insert(poles, pole)
				end
				for k = 1, 2 do
					local a = poles[k].PrimaryPart
					local b = poles[k + 1].PrimaryPart
					for _, name in { "CableL", "CableR" } do
						local pa = a.CFrame:PointToWorldSpace(a:FindFirstChild(name).CFrame.Position)
						local pb = b.CFrame:PointToWorldSpace(b:FindFirstChild(name).CFrame.Position)
						KitMachines.cable(root, pa, pb, 0.9)
					end
				end
				counts[id] = 0
			else
				local model = KitMachines.buildAny(id, if it.entry.Upgrades then level or 0 else 0)
				local turn = if id == "BeltLift" or id == "Slide" then CF.Angles(0, math.pi / 2, 0) else CF.new()
				model:PivotTo(CF.new(cx, 0, z + 2) * turn)
				model.Parent = root
				Old.paintGuis(Loader, root, model)
				local n = 0
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						n += 1
					end
				end
				counts[id] = n
				local top = model:FindFirstChild("ChimneyTop", true)
				if top then
					Old.smoke(Loader, root, top, 1.0)
				end
				if id == "AutoCleaner" or id == "CleaningStation" then
					Old.water(Loader, root, model, if id == "AutoCleaner" then 1 else 0.4, V3.new(1, 0, -1.2).Unit)
				end
			end
			local depth = it.d
			local signZ = z + 2 - depth / 2 - 2.2
			if id == "Conveyor" or id == "ExpressConveyor" then
				signZ = z + CELL - 2 * CELL - CELL / 2 - 2.2
			end
			sign(root, CF.new(cx, 0.8, signZ) * CF.Angles(0.3, 0, 0), string.upper(it.entry.Name), math.max(3.6, #it.entry.Name * 0.42))
			print(string.format("  %-18s x %6.1f z %5.1f", id, cx, z + 2))
			x -= it.w + Showroom.Gap
		end
	end
	local names = {}
	for id in counts do
		table.insert(names, id)
	end
	table.sort(names)
	for _, id in names do
		print(string.format("  %-18s %3d parts", id, counts[id]))
	end
	return root
end

return Showroom
