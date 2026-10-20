--[[
	The "Forge Works" concept (scene "works_gallery", shots in
	tools/preview/works_shots.json): the Satisfactory x Hydroneer look
	(src/shared/Builders/WorksMachines.luau) in the front row, the same
	machines in today's Soft look (KitMachines, saved at the git tag
	machines-soft-2026-10-20) in the row behind, each with a name sign.
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3

Gallery.Gap = 5 -- studs between machines
Gallery.RowGap = 26 -- studs between the two rows

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

function Gallery.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Works = Loader.requirePath("ReplicatedStorage.Shared.Builders.WorksMachines")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local Old = require("./machines_gallery")
	local root = roblox.Instance.new("Model")
	root.Name = "WorksGallery"
	root.Parent = parent
	local CELL = GameConfig.CellSize

	Geo.block(root, CF.new(0, -1.06, 10), V3.new(260, 2, 160), C3.fromRGB(130, 186, 82))
	local widths = {}
	local total = 0
	for i, id in Works.Concept do
		local size = MachineData.ById[id].Size
		widths[i] = size[1] * CELL
		total += widths[i] + (if i > 1 then Gallery.Gap else 0)
	end
	for row, look in { "Works", "Soft" } do
		local z = (row - 1) * Gallery.RowGap
		Geo.block(root, CF.new(0, -0.55, z), V3.new(total + 10, 1.1, 20), C3.fromRGB(96, 100, 112))
		sign(root, CF.new(total / 2 + 3, 2.6, z - 8), if look == "Works" then "NEW: FORGE WORKS" else "NOW: SOFT (SAVED)", 9)
		local x = total / 2
		for i, id in Works.Concept do
			local cx = x - widths[i] / 2
			local model
			if look == "Works" then
				model = Works.build(id)
			else
				model = KitMachines.buildAny(id, 0)
			end
			model:PivotTo(CF.new(cx, 0, z))
			model.Parent = root
			Old.paintGuis(Loader, root, model)
			local top = model:FindFirstChild("ChimneyTop", true)
			if top then
				Old.smoke(Loader, root, top, 1.0)
			end
			local n = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			print(string.format("  %-6s %-16s x %6.1f  %3d parts", look, id, cx, n))
			if look == "Works" then
				local name = MachineData.ById[id].Name
				sign(root, CF.new(cx, 0.8, z - 7.5) * CF.Angles(0.3, 0, 0), string.upper(name), math.max(3.6, #name * 0.42))
			end
			x -= widths[i] + Gallery.Gap
		end
	end
	return root
end

return Gallery
