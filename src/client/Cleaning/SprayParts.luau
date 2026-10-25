--[[
	Pure builders for the default spray look (DefaultLook plays them, the
	preview scene `cleaning spray` draws the same parts frozen):
	  wand(parent)                 the spray wand, hidden until placed
	  wandFrame(workCF, hit, on)   where the wand stands for a nozzle point
	                               (from the lower right, toward the camera)
	  placeWand(wand, cf?)         puts it there (nil: hides it)
	  jet(parent)                  the water jet: a bright core in a soft glow
	  placeJet(jet, tip, hit)      the jet between the nozzle and the dirt
	  hideJet(jet)                 the spray is off
	  spot(parent)                 the splash ring on the dirt (how wide the spray washes)
	  placeSpot(spot, workCF, hit, radius)  the ring at the nozzle point, `radius` studs
	  thin(block, left)            a dirt block washed down to `left` (0..1)
	A chunky pressure-washer lance and a thick jet (owner 2026-10-25: the old
	wand and jet were too thin).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Geo = require(ReplicatedStorage:WaitForChild("Shared").Builders.Geo)

local SprayParts = {}

SprayParts.StandOff = 1.1 -- studs between the nozzle tip and the dirt while spraying
SprayParts.JetColor = Color3.fromRGB(80, 185, 255)
SprayParts.Hidden = CFrame.new(0, -1000, 0)

local function props(): { [string]: any }
	return { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
end

-- The spray wand, built pointing up (+Y) with the nozzle tip at the origin.
function SprayParts.wand(parent: Instance): Model
	local wand = Instance.new("Model")
	wand.Name = "SprayWand"
	local metal, gold, grip = Color3.fromRGB(60, 64, 72), Color3.fromRGB(214, 150, 40), Color3.fromRGB(40, 42, 48)
	-- nozzle, its glowing ring, the lance, a coupling, then the gun body with handle and trigger
	Geo.cylinder(wand, Vector3.new(0, 0.12, 0), 0.24, 0.28, metal, Enum.Material.Metal, props())
	Geo.cylinder(wand, Vector3.new(0, 0.27, 0), 0.07, 0.32, SprayParts.JetColor, Enum.Material.Neon, props())
	Geo.cylinder(wand, Vector3.new(0, 1.05, 0), 1.5, 0.17, gold, Enum.Material.Metal, props())
	Geo.cylinder(wand, Vector3.new(0, 1.82, 0), 0.12, 0.26, metal, Enum.Material.Metal, props())
	Geo.block(wand, CFrame.new(0, 2.1, 0), Vector3.new(0.36, 0.46, 0.36), grip, nil, props())
	Geo.block(wand, CFrame.new(0, 2.34, 0.26), Vector3.new(0.2, 0.62, 0.24), grip, nil, props())
	Geo.block(wand, CFrame.new(0, 2.14, 0.22), Vector3.new(0.08, 0.16, 0.12), Color3.fromRGB(255, 196, 40), nil, props())
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

SprayParts.JetCore = 0.16 -- studs across: the bright middle of the jet
SprayParts.JetGlow = 0.34 -- studs across: the soft water around it

-- The jet: a bright core with a soft glow around it (the glow is the core's child).
function SprayParts.jet(parent: Instance): Part
	local p = props()
	p.Name = "Jet"
	p.Transparency = 1
	local core = Geo.cylinder(parent, SprayParts.Hidden.Position, 1, SprayParts.JetCore, SprayParts.JetColor, Enum.Material.Neon, p)
	local g = props()
	g.Name = "JetGlow"
	g.Transparency = 1
	Geo.cylinder(core, SprayParts.Hidden.Position, 1, SprayParts.JetGlow, Color3.fromRGB(170, 225, 255), Enum.Material.Glass, g)
	return core
end

function SprayParts.placeJet(jet: BasePart, tip: Vector3, hit: Vector3)
	local length = math.max(0.05, (tip - hit).Magnitude)
	-- a cylinder's length runs along its X axis: turn it onto the line from the nozzle to the dirt
	local cf = CFrame.lookAt((tip + hit) / 2, hit) * CFrame.Angles(0, math.pi / 2, 0)
	jet.Size = Vector3.new(length, SprayParts.JetCore, SprayParts.JetCore)
	jet.CFrame = cf
	jet.Transparency = 0.3
	local glow = jet:FindFirstChild("JetGlow") :: BasePart?
	if glow then
		glow.Size = Vector3.new(length, SprayParts.JetGlow, SprayParts.JetGlow)
		glow.CFrame = cf
		glow.Transparency = 0.6
	end
end

function SprayParts.hideJet(jet: BasePart)
	jet.Transparency = 1
	local glow = jet:FindFirstChild("JetGlow") :: BasePart?
	if glow then
		glow.Transparency = 1
	end
end

-- The splash ring on the dirt: shows how wide the spray washes.
function SprayParts.spot(parent: Instance): Part
	local p = props()
	p.Name = "SpraySpot"
	p.Transparency = 1
	return Geo.cylinder(parent, SprayParts.Hidden.Position, 0.03, 1, Color3.fromRGB(190, 235, 255), Enum.Material.SmoothPlastic, p)
end

-- `radius` in studs; nil hides the ring. It lies on the dirt facing the camera.
function SprayParts.placeSpot(spot: BasePart, workCF: CFrame, hit: Vector3?, radius: number?)
	if not hit or not radius then
		spot.CFrame = SprayParts.Hidden
		spot.Transparency = 1
		return
	end
	-- the disc's flat faces look along its X axis: X onto the work face's normal
	local normal = -workCF.LookVector
	spot.Size = Vector3.new(0.03, radius * 2, radius * 2)
	spot.CFrame = CFrame.lookAt(hit + normal * 0.1, hit + normal) * CFrame.Angles(0, math.pi / 2, 0)
	spot.Transparency = 0.65
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
