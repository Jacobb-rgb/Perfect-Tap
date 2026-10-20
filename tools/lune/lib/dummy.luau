--[[
	Blocky stand-in character for preview renders only (the real game uses
	the player's Roblox avatar).
]]

local roblox = require("@lune/roblox") :: any
local Instance, Vector3, Color3 = roblox.Instance, roblox.Vector3, roblox.Color3

local Dummy = {}

local function block(parent, cf, size, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or roblox.Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- root: CFrame at the feet, facing LookVector. pose: "swing" | "carry" | "idle" | "hold"
-- ("hold": the right arm forward like Roblox's tool hold, `pickaxeTool` = a Tool whose
-- parts are in its grip frame (the hand at the origin, barrel -Z) placed in that hand)
function Dummy.build(parent, CFrame, root, pose, colors, pickaxeTool)
	local m = Instance.new("Model")
	m.Name = "Dummy"
	m.Parent = parent
	local shirt = colors and colors.shirt or Color3.fromRGB(186, 98, 48)
	local pants = colors and colors.pants or Color3.fromRGB(60, 54, 70)
	local skin = colors and colors.skin or Color3.fromRGB(236, 190, 150)
	local hair = colors and colors.hair or Color3.fromRGB(80, 50, 30)
	block(m, root * CFrame.new(-0.5, 1, 0), Vector3.new(0.95, 2, 0.95), pants)
	block(m, root * CFrame.new(0.5, 1, 0), Vector3.new(0.95, 2, 0.95), pants)
	block(m, root * CFrame.new(0, 3, 0), Vector3.new(2, 2, 1), shirt)
	-- apron
	block(m, root * CFrame.new(0, 2.7, -0.53), Vector3.new(1.6, 2.3, 0.08), Color3.fromRGB(110, 70, 40))
	block(m, root * CFrame.new(0, 4.65, 0), Vector3.new(1.2, 1.2, 1.2), skin)
	block(m, root * CFrame.new(0, 5.3, 0.1), Vector3.new(1.28, 0.32, 1.28), hair)
	block(m, root * CFrame.new(-0.27, 4.75, -0.61), Vector3.new(0.16, 0.26, 0.04), Color3.fromRGB(40, 30, 30))
	block(m, root * CFrame.new(0.27, 4.75, -0.61), Vector3.new(0.16, 0.26, 0.04), Color3.fromRGB(40, 30, 30))
	local function arm(side, angle, roll)
		-- pivot at the shoulder; angle swings the arm forward (radians)
		local shoulder = root * CFrame.new(side * 1.5, 3.9, 0)
		local cf = shoulder * CFrame.Angles(angle, 0, roll or 0) * CFrame.new(0, -0.9, 0)
		block(m, cf, Vector3.new(0.95, 2, 0.95), shirt)
		return shoulder * CFrame.Angles(angle, 0, roll or 0) * CFrame.new(0, -1.9, 0)
	end
	if pose == "swing" then
		arm(-1, 1.1, 0.2)
		local hand = arm(1, 1.9, -0.25)
		if pickaxeTool then
			-- shaft continues from the hand, angled down into the swing
			local dir = (hand.UpVector * -1):Lerp(root.LookVector * 1 + Vector3.new(0, -0.9, 0), 0.55).Unit
			local center = hand.Position + dir * 1.6
			local handleCf = CFrame.lookAt(center, center - dir)
			for _, d in pickaxeTool:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = handleCf * d.CFrame
					d.Anchored = true
				end
			end
			pickaxeTool.Parent = m
		end
	elseif pose == "hold" then
		arm(-1, 0.1, 0.05)
		local hand = arm(1, math.pi / 2, 0)
		if pickaxeTool then
			local grip = CFrame.new(hand.Position) * root.Rotation
			for _, d in pickaxeTool:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = grip * d.CFrame
					d.Anchored = true
				end
			end
			pickaxeTool.Parent = m
		end
	elseif pose == "carry" then
		arm(-1, 1.45, 0)
		arm(1, 1.45, 0)
	else
		arm(-1, 0.1, 0.05)
		arm(1, -0.1, -0.05)
	end
	return m
end

-- Same stack layout as CarryService.stackOffset (three columns in front of
-- the chest from the middle out, then a bundle on the back).
local COLUMN_ORDER = { 0, -1, 1 }
function Dummy.stackOffset(CFrame, index)
	local i = math.max(0, index - 1)
	if i < 9 then
		return CFrame.new(COLUMN_ORDER[i % 3 + 1] * 1.3, 0.2 + math.floor(i / 3) * 1.12, -2.1)
	end
	local j = i - 9
	local layer = math.floor(j / 6)
	local k = j % 6
	return CFrame.new(COLUMN_ORDER[k % 3 + 1] * 1.2, -0.3 + math.floor(k / 3) * 1.05, 1.6 + (layer % 3) * 0.3)
		* CFrame.Angles(0, layer * 0.6, 0)
end

return Dummy
