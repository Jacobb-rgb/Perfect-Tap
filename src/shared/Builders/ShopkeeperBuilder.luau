--[[
	ShopkeeperBuilder: the owner's miner shopkeeper (2026-10-24: "upload exactly
	this", docs/art/shopkeeper/roblox_miner_shopkeeper.glb) built from Roblox
	parts, piece for piece (Builders/ShopkeeperModel, generated from the file):
	smooth plastic, the lamps neon, the model tagged NoStuds (no Roblox studs on
	him, Shared/StudStyle).

	An R6-style rig so Roblox's own R6 animations move him: invisible
	HumanoidRootPart (anchored), Torso, Head, Left / Right Arm, Left / Right
	Leg around the pieces of each, joined by Motor6Ds with the standard R6
	names and joint frames (RootJoint, Neck, Left / Right Shoulder, Left /
	Right Hip) at his own neck, shoulders and hips; every visible piece is
	welded to its rig part. An AnimationController with an Animator plays the
	tracks (ShopkeeperController).

	Pure: Instance creation only. `feet` = his feet on the floor, LookVector =
	the way he faces; `scale` = his size (1 = the file: 5.53 studs tall).
]]

local ShopkeeperModel = require(script.Parent.ShopkeeperModel)

local ShopkeeperBuilder = {}

ShopkeeperBuilder.SkipTag = "NoStuds" -- StudStyleConfig.SkipTag

ShopkeeperBuilder.RigParts = { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

-- the R6 joint frames (the rotation part of the stock R6 C0 / C1)
local ROOT = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local RIGHT = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LEFT = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)

-- The axis-aligned box round the pieces of rig part `rig` (model space, scale 1).
local function bounds(rig: string): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, piece in ShopkeeperModel.Pieces do
		if piece.Rig == rig then
			local half = piece.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local p = piece.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end
				end
			end
		end
	end
	return lo, hi
end

local function find(name: string): ShopkeeperModel.Piece
	for _, piece in ShopkeeperModel.Pieces do
		if piece.Name == name then
			return piece
		end
	end
	error("no shopkeeper piece " .. name)
end

-- The joints (model space, scale 1): where each rig part turns.
function ShopkeeperBuilder.pivots(): { [string]: Vector3 }
	local torso = find("torso")
	local top = torso.CFrame.Position.Y + torso.Size.Y / 2
	local shoulderL, shoulderR = find("L_shoulder"), find("R_shoulder")
	local thighL, thighR = find("L_thigh"), find("R_thigh")
	local function hip(thigh: ShopkeeperModel.Piece): Vector3
		local p = thigh.CFrame.Position
		return Vector3.new(p.X, p.Y + thigh.Size.Y / 2, p.Z)
	end
	return {
		Root = torso.CFrame.Position,
		Neck = Vector3.new(0, top, torso.CFrame.Position.Z),
		["Left Shoulder"] = shoulderL.CFrame.Position,
		["Right Shoulder"] = shoulderR.CFrame.Position,
		["Left Hip"] = hip(thighL),
		["Right Hip"] = hip(thighR),
	}
end

local function rigPart(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Anchored = false
	part.Parent = parent
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, pivot: CFrame, frame: CFrame): Motor6D
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:ToObjectSpace(pivot) * frame
	motor.C1 = part1.CFrame:ToObjectSpace(pivot) * frame
	motor.Parent = part0
	return motor
end

function ShopkeeperBuilder.build(feet: CFrame, scale: number?): Model
	local s = scale or 1
	local function place(cf: CFrame): CFrame
		return feet * CFrame.new(cf.Position * s) * cf.Rotation
	end
	local model = Instance.new("Model")
	model.Name = "Shopkeeper"
	model:AddTag(ShopkeeperBuilder.SkipTag)

	-- the rig: the root over the torso, a box round each limb's pieces
	local pivots = ShopkeeperBuilder.pivots()
	local root = rigPart("HumanoidRootPart", find("torso").Size * s, place(CFrame.new(pivots.Root)), model)
	root.Anchored = true
	local rig: { [string]: Part } = {}
	for _, name in ShopkeeperBuilder.RigParts do
		local lo, hi = bounds(name)
		rig[name] = rigPart(name, (hi - lo) * s, place(CFrame.new((lo + hi) / 2)), model)
	end
	local function at(name: string): CFrame
		return place(CFrame.new(pivots[name]))
	end
	joint("RootJoint", root, rig.Torso, at("Root"), ROOT)
	joint("Neck", rig.Torso, rig.Head, at("Neck"), ROOT)
	joint("Left Shoulder", rig.Torso, rig["Left Arm"], at("Left Shoulder"), LEFT)
	joint("Right Shoulder", rig.Torso, rig["Right Arm"], at("Right Shoulder"), RIGHT)
	joint("Left Hip", rig.Torso, rig["Left Leg"], at("Left Hip"), LEFT)
	joint("Right Hip", rig.Torso, rig["Right Leg"], at("Right Hip"), RIGHT)

	-- the pieces, each welded to its rig part
	for _, piece in ShopkeeperModel.Pieces do
		local part = Instance.new("Part")
		part.Name = piece.Name
		part.Shape = if piece.Shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
		part.Material = if piece.Material == "Neon" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = piece.Color
		part.Size = piece.Size * s
		part.CFrame = place(piece.CFrame)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Massless = true
		part.Anchored = false
		local holder = rig[piece.Rig] or rig.Torso
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = holder
		weld.Part1 = part
		weld.Parent = part
		part.Parent = holder
	end

	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller
	model.PrimaryPart = root
	return model
end

return ShopkeeperBuilder
