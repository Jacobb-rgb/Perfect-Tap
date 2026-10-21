--[[
	A blocky R15 stand-in for the move previews (tools/lune/export_moves.luau).
	Same parts, sizes and Motor6D joints (C0 / C1 pivots) as Roblox's R15
	block rig (the game moves the player's own avatar; this is only for
	videos). solve() does what the engine does every frame:
	  Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
	so a MoveMath pose looks here as it will on a real R15 character.

	Each part comes with its decor (face, hair, belt, boots) as sub-parts in
	the part's own frame, ready for the preview's groups.
]]

local roblox = require("@lune/roblox") :: any
local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

local R15 = {}

export type SubPart = { Shape: number, Size: any, CFrame: any, Color: any, Material: string }

R15.Colors = {
	Skin = Color3.fromRGB(242, 196, 150),
	Shirt = Color3.fromRGB(226, 112, 46),
	ShirtDark = Color3.fromRGB(176, 78, 30),
	Pants = Color3.fromRGB(58, 74, 120),
	Boots = Color3.fromRGB(92, 60, 40),
	Hair = Color3.fromRGB(96, 58, 32),
	Eye = Color3.fromRGB(30, 26, 34),
	Belt = Color3.fromRGB(70, 46, 30),
	Buckle = Color3.fromRGB(240, 196, 70),
	Glove = Color3.fromRGB(150, 96, 56),
}

-- name -> { Size, Color } (HumanoidRootPart is invisible)
R15.Parts = {
	HumanoidRootPart = { Size = Vector3.new(2, 2, 1), Hidden = true },
	LowerTorso = { Size = Vector3.new(2, 0.4, 1), Color = R15.Colors.Pants },
	UpperTorso = { Size = Vector3.new(2, 1.6, 1), Color = R15.Colors.Shirt },
	Head = { Size = Vector3.new(1.25, 1.25, 1.25), Color = R15.Colors.Skin },
	LeftUpperArm = { Size = Vector3.new(1, 1.17, 1), Color = R15.Colors.Shirt },
	LeftLowerArm = { Size = Vector3.new(1, 1.05, 1), Color = R15.Colors.Skin },
	LeftHand = { Size = Vector3.new(1, 0.3, 1), Color = R15.Colors.Glove },
	RightUpperArm = { Size = Vector3.new(1, 1.17, 1), Color = R15.Colors.Shirt },
	RightLowerArm = { Size = Vector3.new(1, 1.05, 1), Color = R15.Colors.Skin },
	RightHand = { Size = Vector3.new(1, 0.3, 1), Color = R15.Colors.Glove },
	LeftUpperLeg = { Size = Vector3.new(1, 1.22, 1), Color = R15.Colors.Pants },
	LeftLowerLeg = { Size = Vector3.new(1, 1.19, 1), Color = R15.Colors.Pants },
	LeftFoot = { Size = Vector3.new(1, 0.3, 1), Color = R15.Colors.Boots },
	RightUpperLeg = { Size = Vector3.new(1, 1.22, 1), Color = R15.Colors.Pants },
	RightLowerLeg = { Size = Vector3.new(1, 1.19, 1), Color = R15.Colors.Pants },
	RightFoot = { Size = Vector3.new(1, 0.3, 1), Color = R15.Colors.Boots },
}
R15.Order = {
	"HumanoidRootPart",
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

-- Motor6Ds (R15 block rig pivots), parents before children
R15.Joints = {
	{ Name = "Root", Part0 = "HumanoidRootPart", Part1 = "LowerTorso", C0 = CFrame.new(0, -1, 0), C1 = CFrame.new(0, -0.2, 0) },
	{ Name = "Waist", Part0 = "LowerTorso", Part1 = "UpperTorso", C0 = CFrame.new(0, 0.2, 0), C1 = CFrame.new(0, -0.8, 0) },
	{ Name = "Neck", Part0 = "UpperTorso", Part1 = "Head", C0 = CFrame.new(0, 0.8, 0), C1 = CFrame.new(0, -0.62, 0) },
	{ Name = "LeftShoulder", Part0 = "UpperTorso", Part1 = "LeftUpperArm", C0 = CFrame.new(-1, 0.56, 0), C1 = CFrame.new(0.5, 0.42, 0) },
	{ Name = "LeftElbow", Part0 = "LeftUpperArm", Part1 = "LeftLowerArm", C0 = CFrame.new(0, -0.33, 0), C1 = CFrame.new(0, 0.26, 0) },
	{ Name = "LeftWrist", Part0 = "LeftLowerArm", Part1 = "LeftHand", C0 = CFrame.new(0, -0.5, 0), C1 = CFrame.new(0, 0.12, 0) },
	{ Name = "RightShoulder", Part0 = "UpperTorso", Part1 = "RightUpperArm", C0 = CFrame.new(1, 0.56, 0), C1 = CFrame.new(-0.5, 0.42, 0) },
	{ Name = "RightElbow", Part0 = "RightUpperArm", Part1 = "RightLowerArm", C0 = CFrame.new(0, -0.33, 0), C1 = CFrame.new(0, 0.26, 0) },
	{ Name = "RightWrist", Part0 = "RightLowerArm", Part1 = "RightHand", C0 = CFrame.new(0, -0.5, 0), C1 = CFrame.new(0, 0.12, 0) },
	{ Name = "LeftHip", Part0 = "LowerTorso", Part1 = "LeftUpperLeg", C0 = CFrame.new(-0.5, -0.2, 0), C1 = CFrame.new(0, 0.42, 0) },
	{ Name = "LeftKnee", Part0 = "LeftUpperLeg", Part1 = "LeftLowerLeg", C0 = CFrame.new(0, -0.41, 0), C1 = CFrame.new(0, 0.37, 0) },
	{ Name = "LeftAnkle", Part0 = "LeftLowerLeg", Part1 = "LeftFoot", C0 = CFrame.new(0, -0.55, 0), C1 = CFrame.new(0, 0.1, 0) },
	{ Name = "RightHip", Part0 = "LowerTorso", Part1 = "RightUpperLeg", C0 = CFrame.new(0.5, -0.2, 0), C1 = CFrame.new(0, 0.42, 0) },
	{ Name = "RightKnee", Part0 = "RightUpperLeg", Part1 = "RightLowerLeg", C0 = CFrame.new(0, -0.41, 0), C1 = CFrame.new(0, 0.37, 0) },
	{ Name = "RightAnkle", Part0 = "RightLowerLeg", Part1 = "RightFoot", C0 = CFrame.new(0, -0.55, 0), C1 = CFrame.new(0, 0.1, 0) },
}

R15.HipHeight = 2 -- ground to the bottom of the HumanoidRootPart
R15.RootHeight = 3 -- ground to the HumanoidRootPart's centre (HipHeight + half its height)

-- Every part's CFrame: rootCF = the HumanoidRootPart, transforms[joint] = Motor6D.Transform.
function R15.solve(rootCF: any, transforms: { [string]: any }): { [string]: any }
	local out = { HumanoidRootPart = rootCF }
	for _, joint in R15.Joints do
		local parent = out[joint.Part0]
		local transform = transforms[joint.Name] or CFrame.identity
		out[joint.Part1] = parent * joint.C0 * transform * joint.C1:Inverse()
	end
	return out
end

-- The world position of a joint's pivot (for clipping checks).
function R15.pivot(parts: { [string]: any }, jointName: string): any
	for _, joint in R15.Joints do
		if joint.Name == jointName then
			return (parts[joint.Part0] * joint.C0).Position
		end
	end
	return nil
end

local function sub(shape: number, size: any, cf: any, color: any, material: string?): SubPart
	return { Shape = shape, Size = size, CFrame = cf, Color = color, Material = material or "SmoothPlastic" }
end

-- The visible pieces of one body part, in the part's own frame.
function R15.pieces(partName: string): { SubPart }
	local info = R15.Parts[partName]
	if info.Hidden then
		return {}
	end
	local c = R15.Colors
	local list = { sub(0, info.Size, CFrame.identity, info.Color) }
	if partName == "Head" then
		-- eyes, cheeks, a smile, hair (the face looks along -Z)
		for _, x in { -0.26, 0.26 } do
			table.insert(list, sub(0, Vector3.new(0.16, 0.3, 0.04), CFrame.new(x, 0.08, -0.63), c.Eye))
			table.insert(list, sub(0, Vector3.new(0.07, 0.08, 0.02), CFrame.new(x + 0.03, 0.15, -0.655), Color3.new(1, 1, 1)))
		end
		table.insert(list, sub(0, Vector3.new(0.5, 0.08, 0.04), CFrame.new(0, -0.3, -0.63), c.Eye))
		table.insert(list, sub(0, Vector3.new(0.08, 0.1, 0.04), CFrame.new(-0.27, -0.24, -0.63), c.Eye))
		table.insert(list, sub(0, Vector3.new(0.08, 0.1, 0.04), CFrame.new(0.27, -0.24, -0.63), c.Eye))
		table.insert(list, sub(0, Vector3.new(1.33, 0.36, 1.33), CFrame.new(0, 0.58, 0.02), c.Hair))
		table.insert(list, sub(0, Vector3.new(1.33, 0.55, 0.3), CFrame.new(0, 0.3, 0.53), c.Hair))
		table.insert(list, sub(0, Vector3.new(1.0, 0.16, 0.12), CFrame.new(0, 0.45, -0.66), c.Hair))
	elseif partName == "UpperTorso" then
		-- a work apron with a pocket
		table.insert(list, sub(0, Vector3.new(1.3, 1.3, 0.06), CFrame.new(0, -0.12, -0.52), c.ShirtDark))
		table.insert(list, sub(0, Vector3.new(0.6, 0.34, 0.04), CFrame.new(0, -0.38, -0.56), c.Belt))
	elseif partName == "LowerTorso" then
		table.insert(list, sub(0, Vector3.new(2.04, 0.18, 1.04), CFrame.new(0, 0.1, 0), c.Belt))
		table.insert(list, sub(0, Vector3.new(0.36, 0.2, 0.06), CFrame.new(0, 0.1, -0.53), c.Buckle, "Metal"))
	elseif partName == "LeftUpperArm" or partName == "RightUpperArm" then
		-- a sleeve cuff
		table.insert(list, sub(0, Vector3.new(1.04, 0.18, 1.04), CFrame.new(0, -0.5, 0), c.ShirtDark))
	elseif partName == "LeftFoot" or partName == "RightFoot" then
		table.insert(list, sub(0, Vector3.new(1.02, 0.12, 1.12), CFrame.new(0, -0.09, -0.06), Color3.fromRGB(60, 40, 28)))
	end
	return list
end

return R15
