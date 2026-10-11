--[[
	Builds the pickaxe Tool. The shaft is the Handle (long axis = Z, the hand
	holds the -Z end), the head sits at the +Z end.
]]

local Geo = require(script.Parent.Geo)
local ToolData = require(script.Parent.Parent.Config.ToolData)

local PickaxeBuilder = {}

local WOOD = Color3.fromRGB(122, 80, 48)
local WRAP = Color3.fromRGB(70, 44, 30)

function PickaxeBuilder.build(pickaxeId: string): Tool
	local info = ToolData.PickaxeById[pickaxeId] or ToolData.PickaxeById[ToolData.DefaultPickaxe]
	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.ToolTip = info.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, 0, -1.6)
	tool:SetAttribute("PickaxeId", info.Id)
	tool:SetAttribute("Tier", info.Tier)
	tool:SetAttribute("Cooldown", info.Cooldown)

	local handle = Geo.make("Part", {
		Name = "Handle",
		Size = Vector3.new(0.38, 0.38, 4.4),
		Color = WOOD,
		Anchored = false,
		CanCollide = false,
		Massless = true,
		CFrame = CFrame.new(),
	})
	handle.Parent = tool

	local function part(className: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material)
		local p = Geo.make(className, {
			CFrame = cf,
			Size = size,
			Color = color,
			Material = material,
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Massless = true,
		})
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	-- grip wrap
	part("Part", CFrame.new(0, 0, -1.5), Vector3.new(0.44, 0.44, 1.1), WRAP, Enum.Material.SmoothPlastic)
	-- head: crossbar along Y with pointed ends
	local headZ = 1.95
	local material = if info.Glow then Enum.Material.Metal else info.HeadMaterial
	part("Part", CFrame.new(0, 0, headZ), Vector3.new(0.5, 2.6, 0.62), info.HeadColor, material)
	part("WedgePart", CFrame.new(0, 1.65, headZ) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(0.48, 0.6, 0.7), info.HeadColor, material)
	part("WedgePart", CFrame.new(0, -1.65, headZ) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.48, 0.6, 0.7), info.HeadColor, material)
	-- collar
	part("Part", CFrame.new(0, 0, headZ - 0.45), Vector3.new(0.55, 0.55, 0.3), WRAP, Enum.Material.SmoothPlastic)
	if info.Glow then
		local glow = part("Part", CFrame.new(0, 0, headZ), Vector3.new(0.54, 1.6, 0.2), info.HeadColor:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = info.HeadColor
		light.Range = 6
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = glow
	end
	return tool
end

return PickaxeBuilder
