--[[
	The one Furnace at its four tiers (scene "furnace_tiers", shots in
	tools/preview/furnace_tiers_shots.json): Furnace (clay), Brick, Blast and
	Plasma side by side, as MachineBuilder builds them for a player's tier
	(owner 2026-10-24), each with a sign; behind the first one the starter
	Crusher that drops its piles into it.
]]

local roblox = require("@lune/roblox") :: any

local Tiers = {}

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

function Tiers.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Old = require("./machines_gallery")
	local root = roblox.Instance.new("Model")
	root.Name = "FurnaceTiers"
	root.Parent = parent
	Geo.block(root, CF.new(0, -1.06, 6), V3.new(140, 2, 90), C3.fromRGB(130, 186, 82))
	Geo.block(root, CF.new(0, -0.55, 3), V3.new(56, 1.1, 22), C3.fromRGB(96, 100, 112))
	local gap = 12
	for tier = 0, 3 do
		local x = (1.5 - tier) * gap -- tier 0 on the left of a camera looking +Z
		local model = MachineBuilder.build("ClayFurnace", 0, tier)
		model:PivotTo(CF.new(x, 0, 0))
		model.Parent = root
		Old.paintGuis(Loader, root, model)
		local top = model:FindFirstChild("ChimneyTop", true)
		if top then
			Old.smoke(Loader, root, top, 1.0)
		end
		local info = MachineData.info("ClayFurnace", tier)
		local label = string.upper(info.Name)
		sign(root, CF.new(x, 0.8, -6.5) * CF.Angles(0.3, 0, 0), label, math.max(3.6, #label * 0.42))
		if tier == 0 then
			-- the starter Crusher behind it (toward the back wall) feeds it
			local crusher = MachineBuilder.build("Crusher", 0)
			crusher:PivotTo(CF.new(x, 0, 8))
			crusher.Parent = root
			Old.paintGuis(Loader, root, crusher)
		end
	end
	return root
end

return Tiers
