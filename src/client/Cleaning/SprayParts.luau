--[[
	Pure builders for the default spray look (DefaultLook plays them, the
	preview scene `cleaning spray` draws the same parts frozen):
	  wand(parent)                 the spray wand, hidden until placed
	  wandFrame(workCF, hit, on)   where the wand stands for a nozzle point
	                               (from the lower right, toward the camera)
	  placeWand(wand, cf?)         puts it there (nil: hides it)
	  placeJet(jet, tip, hit)      the water jet between the nozzle and the dirt
	  thin(block, left)            a dirt block washed down to `left` (0..1)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Geo = require(ReplicatedStorage:WaitForChild("Shared").Builders.Geo)

local SprayParts = {}

SprayParts.StandOff = 1.1 -- studs between the nozzle tip and the dirt while spraying
SprayParts.JetColor = Color3.fromRGB(150, 220, 255)
SprayParts.Hidden = CFrame.new(0, -1000, 0)

local function props(): { [string]: any }
	return { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
end

-- The spray wand, built pointing up (+Y) with the nozzle tip at the origin.
function SprayParts.wand(parent: Instance): Model
	local wand = Instance.new("Model")
	wand.Name = "SprayWand"
	Geo.block(wand, CFrame.new(0, 0.08, 0), Vector3.new(0.12, 0.16, 0.12), Color3.fromRGB(60, 64, 72), Enum.Material.Metal, props())
	Geo.block(wand, CFrame.new(0, 0.75, 0), Vector3.new(0.09, 1.2, 0.09), Color3.fromRGB(214, 150, 40), Enum.Material.Metal, props())
	Geo.block(wand, CFrame.new(0, 1.45, 0), Vector3.new(0.2, 0.3, 0.2), Color3.fromRGB(40, 42, 48), nil, props())
	Geo.block(wand, CFrame.new(0, 1.62, 0.16), Vector3.new(0.12, 0.42, 0.14), Color3.fromRGB(40, 42, 48), nil, props())
	for _, d in wand:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseCF", d.CFrame)
			d.Transparency = 1
		end
	end
	wand.Parent = parent
	return wand
end

function SprayParts.wandFrame(workCF: CFrame, hit: Vector3, active: boolean): (CFrame, Vector3)
	local axis = workCF:VectorToWorldSpace(Vector3.new(0.45, -0.5, 0.75)).Unit
	local tip = hit + axis * (if active then SprayParts.StandOff else SprayParts.StandOff + 0.25)
	local right = axis:Cross(workCF.LookVector * -1)
	right = if right.Magnitude > 1e-3 then right.Unit else workCF.RightVector
	local back = right:Cross(axis).Unit
	return CFrame.fromMatrix(tip, right, axis, back), tip
end

function SprayParts.placeWand(wand: Model, cf: CFrame?)
	for _, d in wand:GetDescendants() do
		if d:IsA("BasePart") then
			if cf then
				d.CFrame = cf * (d:GetAttribute("BaseCF") :: CFrame)
				d.Transparency = 0
			else
				d.CFrame = SprayParts.Hidden
				d.Transparency = 1
			end
		end
	end
end

function SprayParts.jet(parent: Instance): Part
	local p = props()
	p.Name = "Jet"
	p.Transparency = 1
	return Geo.block(parent, SprayParts.Hidden, Vector3.new(0.07, 0.07, 1), SprayParts.JetColor, Enum.Material.Neon, p)
end

function SprayParts.placeJet(jet: BasePart, tip: Vector3, hit: Vector3)
	jet.Size = Vector3.new(0.07, 0.07, math.max(0.05, (tip - hit).Magnitude))
	jet.CFrame = CFrame.lookAt((tip + hit) / 2, hit)
	jet.Transparency = 0.35
end

-- A dirt block (OreShellBuilder: attributes FullSize, and FullCF set by the look) washed down
-- to `left` of its dirt: thinner, a little smaller and wetter (lighter), its back staying on
-- the ore face.
function SprayParts.thin(block: BasePart, left: number)
	local full = block:GetAttribute("FullSize") :: Vector3
	local fullCF = (block:GetAttribute("FullCF") :: CFrame?) or block.CFrame
	if not block:GetAttribute("FullCF") then
		block:SetAttribute("FullCF", fullCF)
	end
	local flat = 0.75 + 0.25 * left
	local depth = full.Z * math.max(0.25, left)
	block.Size = Vector3.new(full.X * flat, full.Y * flat, depth)
	block.CFrame = fullCF * CFrame.new(0, 0, -(full.Z - depth) / 2)
	local color = block:GetAttribute("FullColor") :: Color3?
	if not color then
		color = block.Color
		block:SetAttribute("FullColor", color)
	end
	block.Color = (color :: Color3):Lerp(Color3.fromRGB(150, 118, 84), 0.4 * (1 - left))
end

return SprayParts
