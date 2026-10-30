--[[
	The Dragon King's royal cape (Builders/RoyalCape) on stand-in characters,
	for the preview pictures (tools/lune/export_cape.luau -> build/preview/cape.json,
	shots in tools/preview/cape_shots.json) and the tests.

	  Preview.r15(parent, rootCF, transforms, look)  a blocky R15 character
	      (lib/dummy_r15: Roblox's block rig sizes and joints), posed
	  Preview.r6(parent, rootCF, look)               a classic R6 character
	  Preview.wear(character, packId, flow)          builds the cape the way
	      RoyalCapeController does (RoyalCape.fit / build / attach), bends its
	      hinges by `flow` ({ lift1, roll1, lift2, roll2 }) and places every
	      part where the welds hold it (Preview.solve: Lune runs no physics)
	  Preview.solve(model)  moves every part welded below the model's Root the
	      way Roblox would: Part1 = Part0 * C0 * C1:Inverse()

	The scene: a gold-rimmed stone plaza on a lawn; left to right an R6 player,
	an R15 player standing, one walking (the cape lifted by RoyalCape.step at
	walking speed), one standing with the Rookie Pack, one running with the
	Miner's Pack, and one on a board's speed.
]]

local roblox = require("@lune/roblox") :: any
local Instance, Vector3, Color3 = roblox.Instance, roblox.Vector3, roblox.Color3
local R15 = require("./dummy_r15")

local Preview = {}

Preview.Spacing = 14

export type Look = { Shirt: any, ShirtDark: any, Pants: any }

local LOOKS: { Look } = {
	{ Shirt = Color3.fromRGB(70, 112, 196), ShirtDark = Color3.fromRGB(48, 80, 150), Pants = Color3.fromRGB(46, 50, 70) },
	{ Shirt = Color3.fromRGB(236, 236, 242), ShirtDark = Color3.fromRGB(190, 192, 206), Pants = Color3.fromRGB(58, 66, 104) },
	{ Shirt = Color3.fromRGB(64, 150, 92), ShirtDark = Color3.fromRGB(44, 110, 66), Pants = Color3.fromRGB(70, 56, 44) },
	{ Shirt = Color3.fromRGB(40, 40, 52), ShirtDark = Color3.fromRGB(26, 26, 34), Pants = Color3.fromRGB(80, 80, 96) },
}
Preview.Looks = LOOKS

local function block(parent: any, name: string, cf: any, size: any, color: any, material: any?, shape: any?): any
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or roblox.Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

--[[
	A posed R15 block character: the real body parts (named like Roblox's, the
	HumanoidRootPart invisible) with a Humanoid (HipHeight 2), their decor
	(face, hair, belt, boots) as separate anchored parts.
]]
function Preview.r15(parent: any, rootCF: any, transforms: { [string]: any }?, look: Look?): any
	local model = Instance.new("Model")
	model.Name = "R15Player"
	model.Parent = parent
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = R15.HipHeight
	humanoid.Parent = model
	local colors = look or LOOKS[1]
	local swap = {
		[R15.Colors.Shirt] = colors.Shirt,
		[R15.Colors.ShirtDark] = colors.ShirtDark,
		[R15.Colors.Pants] = colors.Pants,
	}
	local placed = R15.solve(rootCF, transforms or {})
	for _, name in R15.Order do
		local info = R15.Parts[name]
		local cf = placed[name]
		local body = block(model, name, cf, info.Size, swap[info.Color] or info.Color or Color3.new(1, 1, 1))
		if info.Hidden then
			body.Transparency = 1
		end
		for i, piece in R15.pieces(name) do
			if i > 1 then
				local shape = if piece.Shape == 1 then roblox.Enum.PartType.Ball else nil
				local material = roblox.Enum.Material[piece.Material]
				block(model, name .. "Decor", cf * piece.CFrame, piece.Size, swap[piece.Color] or piece.Color, material, shape)
			end
		end
	end
	return model
end

-- A classic R6 character standing (Torso 2 x 2 x 1, legs 2 tall, HipHeight 0).
function Preview.r6(parent: any, rootCF: any, look: Look?): any
	local model = Instance.new("Model")
	model.Name = "R6Player"
	model.Parent = parent
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 0
	humanoid.Parent = model
	local colors = look or LOOKS[2]
	local root = block(model, "HumanoidRootPart", rootCF, Vector3.new(2, 2, 1), Color3.new(1, 1, 1))
	root.Transparency = 1
	block(model, "Torso", rootCF, Vector3.new(2, 2, 1), colors.Shirt)
	block(model, "Head", rootCF * roblox.CFrame.new(0, 1.5, 0), Vector3.new(2, 1, 1), R15.Colors.Skin)
	block(model, "HeadDecor", rootCF * roblox.CFrame.new(0, 1.9, 0.05), Vector3.new(2.04, 0.3, 1.04), R15.Colors.Hair)
	for _, side in { -1, 1 } do
		block(
			model,
			if side < 0 then "Left Arm" else "Right Arm",
			rootCF * roblox.CFrame.new(side * 1.5, 0, 0),
			Vector3.new(1, 2, 1),
			colors.Shirt
		)
		block(
			model,
			if side < 0 then "Left Leg" else "Right Leg",
			rootCF * roblox.CFrame.new(side * 0.5, -2, 0),
			Vector3.new(1, 2, 1),
			colors.Pants
		)
		block(model, "Eye", rootCF * roblox.CFrame.new(side * 0.3, 1.55, -0.51), Vector3.new(0.16, 0.26, 0.04), R15.Colors.Eye)
	end
	return model
end

-- Moves every part welded (Weld) below the model's Root to where the welds hold it.
-- (Lune hands out a new userdata per Instance read, so parts can't key a table:
-- the solved ones are marked with an attribute while it runs)
function Preview.solve(model: any)
	local welds = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and d.Part0 and d.Part1 and d.Part0:IsDescendantOf(model) then
			table.insert(welds, d)
		end
	end
	model.PrimaryPart:SetAttribute("__Solved", true)
	local left = #welds
	while left > 0 do
		local before = left
		for _, weld in welds do
			if weld.Part0:GetAttribute("__Solved") and not weld.Part1:GetAttribute("__Solved") then
				weld.Part1.CFrame = weld.Part0.CFrame * weld.C0 * weld.C1:Inverse()
				weld.Part1:SetAttribute("__Solved", true)
				left -= 1
			end
		end
		assert(left < before, "a weld hangs on nothing below Root")
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("__Solved", nil)
		end
	end
end

--[[
	Puts the cape on `character` as the controller does (wearing the pack
	`packId`, nil = none), the hinges bent by `flow` = { lift1, roll1, lift2,
	roll2 } (nil = at rest). Returns the cape (parented to the character's
	parent) and the RoyalCape.fit.
]]
function Preview.wear(Loader: any, character: any, packId: string?, flow: { number }?): (any, any)
	local RoyalCape = Loader.requirePath("ReplicatedStorage.Shared.Builders.RoyalCape")
	local fit = RoyalCape.fit(character, packId)
	assert(fit, "no torso to wear the cape on")
	local cape = RoyalCape.build({ Scale = fit.Scale, Length = fit.Length, Pin = fit.Pin, Crest = fit.Crest })
	RoyalCape.attach(cape, fit.Torso)
	Preview.solve(cape)
	if flow then
		-- the flow, then kept behind the limbs as RoyalCapeController does (eased all the way)
		local lift1, lift2 = flow[1], flow[3]
		local hinge = RoyalCape.hingeFrame(cape)
		local need1, need2 = RoyalCape.clearance(hinge, RoyalCape.shape(cape), RoyalCape.limbs(character), lift1)
		lift1, lift2 = RoyalCape.clear(RoyalCape.newFlow(), 10, lift1, lift2, need1, need2)
		local mid, hem = RoyalCape.hinges(cape)
		RoyalCape.bend(mid, lift1, flow[2])
		RoyalCape.bend(hem, lift2, flow[4])
		Preview.solve(cape)
	end
	cape.Parent = character.Parent
	return cape, fit
end

-- RoyalCape.step at a steady speed until the lift settles: { lift1, roll1, lift2, roll2 } at a flutter peak.
function Preview.flowAt(Loader: any, forward: number, side: number?, turn: number?, phase: number?): { number }
	local RoyalCape = Loader.requirePath("ReplicatedStorage.Shared.Builders.RoyalCape")
	local state = RoyalCape.newFlow(0.7)
	local out = { 0, 0, 0, 0 }
	for _ = 1, 90 do
		out = { RoyalCape.step(state, 1 / 30, forward, side or 0, 0, turn or 0, false) }
	end
	-- a moment of the flutter (the same state, its phase set)
	if phase then
		state.Phase = phase
		out = { RoyalCape.step(state, 0, forward, side or 0, 0, turn or 0, false) }
	end
	return out
end

-- A walking / running R15 pose (`k` 0..1: how far the limbs swing).
function Preview.walkPose(k: number): { [string]: any }
	local A = roblox.CFrame.Angles
	return {
		Root = A(-0.08 * k, 0, 0),
		LeftHip = A(0.62 * k, 0, 0),
		RightHip = A(-0.55 * k, 0, 0),
		LeftKnee = A(-0.15 * k, 0, 0),
		RightKnee = A(-0.7 * k, 0, 0),
		LeftShoulder = A(-0.55 * k, 0, 0.06),
		RightShoulder = A(0.6 * k, 0, -0.06),
		LeftElbow = A(0.35 * k, 0, 0),
		RightElbow = A(0.45 * k, 0, 0),
	}
end

-- The preview scene (see the header).
function Preview.build(Loader: any, workspace: any)
	local CF = Loader.CFrame
	local M = roblox.Enum.Material
	local stage = Instance.new("Model")
	stage.Name = "CapeStage"
	stage.Parent = workspace
	block(stage, "Lawn", CF.new(12, -0.5, 0), Vector3.new(120, 1, 80), Color3.fromRGB(104, 170, 78), M.Grass)
	block(
		stage,
		"Plaza",
		CF.new(12, -0.45, 0) * CF.Angles(0, 0, math.pi / 2),
		Vector3.new(1, 44, 44),
		Color3.fromRGB(196, 186, 170),
		M.Slate,
		roblox.Enum.PartType.Cylinder
	)
	block(
		stage,
		"PlazaRim",
		CF.new(12, -0.47, 0) * CF.Angles(0, 0, math.pi / 2),
		Vector3.new(1, 45.2, 45.2),
		Color3.fromRGB(214, 160, 60),
		M.Foil,
		roblox.Enum.PartType.Cylinder
	)
	-- a hedge far behind the line (the backdrop of the front shots)
	for i = 1, 12 do
		local x = -18 + i * 5
		local bush = block(
			stage,
			"Bush",
			CF.new(x, 1.3, -18),
			Vector3.new(4.2, 3, 4.2),
			Color3.fromRGB(70, 140, 60),
			M.Grass,
			roblox.Enum.PartType.Ball
		)
		bush.CastShadow = false
	end
	local function at(i: number): any
		return CF.new((i - 1) * Preview.Spacing, 0, 0)
	end
	local rootY = R15.RootHeight
	-- 1: R6, standing
	local r6 = Preview.r6(stage, at(1) * CF.new(0, 3, 0), LOOKS[2])
	Preview.wear(Loader, r6, nil, nil)
	-- 2: R15 standing (a breeze moment)
	local idle = Preview.r15(stage, at(2) * CF.new(0, rootY, 0), nil, LOOKS[1])
	Preview.wear(Loader, idle, nil, Preview.flowAt(Loader, 0))
	-- 3: R15 walking
	local walk = Preview.r15(stage, at(3) * CF.new(0, rootY, 0), Preview.walkPose(1), LOOKS[3])
	Preview.wear(Loader, walk, nil, Preview.flowAt(Loader, 18, 0, 0, 1.4))
	-- 4: R15 standing with the Rookie Pack
	local packed = Preview.r15(stage, at(4) * CF.new(0, rootY, 0), nil, LOOKS[2])
	Preview.wear(Loader, packed, "RookiePack", Preview.flowAt(Loader, 0))
	Preview.pack(Loader, packed, "RookiePack")
	-- 5: R15 running with the Miner's Pack
	local runner = Preview.r15(stage, at(5) * CF.new(0, rootY, 0), Preview.walkPose(1), LOOKS[4])
	Preview.wear(Loader, runner, "MinersPack", Preview.flowAt(Loader, 22, 0, 0, 2.2))
	Preview.pack(Loader, runner, "MinersPack")
	-- 6: R15 at a board's speed
	local fast = Preview.r15(stage, at(6) * CF.new(0, rootY, 0), Preview.walkPose(0.4), LOOKS[1])
	Preview.wear(Loader, fast, nil, Preview.flowAt(Loader, 45, 0, 0, 0.6))
end

-- The worn backpack the way BackpackWearController puts it on (with its effects).
function Preview.pack(Loader: any, character: any, packId: string)
	local BackpackBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackBuilder")
	local BackpackFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.BackpackFx")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local model = BackpackBuilder.build(packId)
	local offset = Loader.CFrame.new(0, torso.Size.Y / 2 - BackpackBuilder.Top, torso.Size.Z / 2)
	model:PivotTo(torso.CFrame * offset)
	BackpackFx.apply(model, false)
	model.Parent = character.Parent
end

return Preview
