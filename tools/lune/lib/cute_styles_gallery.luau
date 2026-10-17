--[[
	Style exploration preview (scene "cute_styles", shots in
	tools/preview/cute_styles_shots.json): the Clay Furnace from
	src/shared/Builders/CuteMachines.luau in styles A (Soft), B (Bot) and C
	(Cool), side by side on a metal pad, with signs and a forgekeeper for scale.
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3

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
	local CuteMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.CuteMachines")
	local Old = require("./machines_gallery")
	local Dummy = require("./dummy")
	local root = roblox.Instance.new("Model")
	root.Name = "CuteStyles"
	root.Parent = parent
	Geo.block(root, CF.new(0, -1.06, 0), V3.new(300, 2, 300), C3.fromRGB(130, 186, 82))
	Geo.block(root, CF.new(0, -0.6, 0), V3.new(46, 1.2, 26), C3.fromRGB(46, 48, 58))
	Geo.block(root, CF.new(0, -0.5, 0), V3.new(44, 1, 24), C3.fromRGB(112, 116, 130))
	for i = 1, 10 do
		Geo.block(root, CF.new(-22 + i * 4, 0.005, 0), V3.new(0.1, 0.01, 24), C3.fromRGB(90, 94, 108))
	end
	for i = 1, 5 do
		Geo.block(root, CF.new(0, 0.005, -12 + i * 4), V3.new(44, 0.01, 0.1), C3.fromRGB(90, 94, 108))
	end
	for i, key in { "A", "B", "C" } do
		local x = 14 - (i - 1) * 14 -- +X shows on the left of a camera looking +Z
		local model = CuteMachines.furnace(key)
		model:PivotTo(CF.new(x, 0, 2))
		model.Parent = root
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		print(string.format("  style %s (%s): %d parts", key, CuteMachines.Styles[key].name, n))
		Old.smoke(Loader, root, model:FindFirstChild("ChimneyTop", true), 1.1)
		sign(root, CF.new(x, 0.75, -5.6) * CF.Angles(0.3, 0, 0), key .. " - " .. string.upper(CuteMachines.Styles[key].name), 5)
	end
	Dummy.build(root, CF, CF.new(-6.5, 0, -3.5) * CF.Angles(0, math.pi * 0.9, 0), "idle")
	return root
end

return Gallery
