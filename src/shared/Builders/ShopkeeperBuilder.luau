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

	The style pass (owner 2026-10-24: "a bit nicer, with effects"): metal
	shoulder pads, plates and tools, leather apron, straps, boots and pack,
	fabric trousers and shirt, a glossy helmet, neon orange trims and pickaxe
	tip, three glowing ore crystals in his pack, a shine in each eye and the
	shop's name on his apron badge (opts.Badge, in place of the file's four
	letter bars).
	Effects (opts.Effects, default on): a soft light cone from the helmet lamp
	(a Beam: no light), a SpotLight in the lamp and a PointLight in front of
	his chest (off unless opts.Lights: the game lights only the nearest
	keeper), sparkles rising from the crystals, a gold CoinBurst emitter
	(Rate 0: the controller emits it) and a warm outline (Highlight).

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

export type Options = {
	Badge: string?, -- the word on his apron badge (nil: the file's four letter bars)
	Effects: boolean?, -- the beam, lights, sparkles, coin burst and outline (default true)
	Lights: boolean?, -- the lamp's SpotLight and the chest light switched on (default false)
}

-- the style pass: a material (and gloss) per piece of the file
local function set(names: { string }): { [string]: boolean }
	local out = {}
	for _, name in names do
		out[name] = true
	end
	return out
end
local METAL = set({
	"L_shoulder",
	"R_shoulder",
	"L_shoulder_trim",
	"R_shoulder_trim",
	"L_knee_plate",
	"R_knee_plate",
	"chest_plate",
	"pickaxe_head",
	"lantern_frame",
	"lantern_handle",
	"lamp_mount",
	"side_lamp",
	"helmet_rim",
	"chest_device",
})
local LEATHER = set({
	"apron",
	"apron_top",
	"apron_strap",
	"apron_strap_1",
	"harness",
	"harness_1",
	"belt",
	"belt_pouch",
	"belt_pouch_1",
	"pouch_flap",
	"pouch_flap_1",
	"backpack",
	"backpack_panel",
	"L_boot",
	"R_boot",
	"L_bracer",
	"R_bracer",
	"pickaxe_handle",
})
local FABRIC = set({ "L_thigh", "R_thigh", "L_shin", "R_shin", "L_knee", "R_knee", "hips", "torso", "collar" })
local GLOSSY = set({ "helmet_top", "helmet_band", "helmet_top_stripe", "backpack_tube", "backpack_tube_1" })
local NEON = set({ "L_boot_trim", "R_boot_trim", "L_bracer_trim", "R_bracer_trim", "pickaxe_tip" })
local LETTERS = set({ "sign_letter_stem", "sign_letter_stem_1", "sign_letter_stem_2", "sign_letter_stem_3" })

ShopkeeperBuilder.Glow = Color3.fromRGB(255, 214, 140) -- the lamp's light, the beam, the outline
ShopkeeperBuilder.Sparkle = "rbxasset://textures/particles/sparkles_main.dds"

-- Pieces the style pass adds (model space, scale 1, like ShopkeeperModel):
-- a shine in each eye and three ore crystals in his pack.
local EXTRA: { ShopkeeperModel.Piece } = {
	{
		Name = "eye_shine",
		Rig = "Head",
		Shape = "Block",
		Material = "SmoothPlastic",
		Size = Vector3.new(0.035, 0.045, 0.01),
		CFrame = CFrame.new(-0.18, 4.625, -0.417),
		Color = Color3.fromRGB(255, 255, 255),
	},
	{
		Name = "eye_shine_1",
		Rig = "Head",
		Shape = "Block",
		Material = "SmoothPlastic",
		Size = Vector3.new(0.035, 0.045, 0.01),
		CFrame = CFrame.new(0.22, 4.625, -0.417),
		Color = Color3.fromRGB(255, 255, 255),
	},
	{
		Name = "crystal_cyan",
		Rig = "Torso",
		Shape = "Block",
		Material = "Neon",
		Size = Vector3.new(0.16, 0.5, 0.16),
		CFrame = CFrame.new(-0.19, 3.86, 0.5) * CFrame.Angles(0, math.pi / 4, 0.3),
		Color = Color3.fromRGB(0, 170, 255),
	},
	{
		Name = "crystal_purple",
		Rig = "Torso",
		Shape = "Block",
		Material = "Neon",
		Size = Vector3.new(0.2, 0.64, 0.2),
		CFrame = CFrame.new(0.01, 3.93, 0.47) * CFrame.Angles(0.15, math.pi / 4, -0.08),
		Color = Color3.fromRGB(150, 60, 255),
	},
	{
		Name = "crystal_gold",
		Rig = "Torso",
		Shape = "Block",
		Material = "Neon",
		Size = Vector3.new(0.14, 0.42, 0.14),
		CFrame = CFrame.new(0.2, 3.83, 0.53) * CFrame.Angles(0, math.pi / 4, -0.38),
		Color = Color3.fromRGB(255, 176, 30),
	},
}
ShopkeeperBuilder.Extra = EXTRA

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

-- The effects on a built keeper (see the header); `s` = his scale.
function ShopkeeperBuilder.effects(model: Model, built: { [string]: Part }, rig: { [string]: Part }, s: number, lights: boolean)
	-- the helmet lamp: a soft cone of light ahead and down (a Beam), the SpotLight in it
	local lamp = built.lamp_glow
	if lamp then
		-- (the lens is a disc: its X axis points the way he faces)
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamStart"
		a0.CFrame = CFrame.new(0.07 * s, 0, 0)
		a0.Parent = lamp
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamEnd"
		a1.CFrame = CFrame.new(6.5 * s, -2.4 * s, 0)
		a1.Parent = lamp
		local beam = Instance.new("Beam")
		beam.Name = "HelmetBeam"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(ShopkeeperBuilder.Glow)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Width0 = 0.25 * s
		beam.Width1 = 3.2 * s
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = lamp
		local spot = Instance.new("SpotLight")
		spot.Name = "HelmetSpot"
		spot.Face = Enum.NormalId.Right
		spot.Angle = 60
		spot.Range = 16
		spot.Brightness = 1.6
		spot.Color = ShopkeeperBuilder.Glow
		spot.Shadows = false
		spot.Enabled = lights
		spot.Parent = lamp
	end
	-- the soft light in front of his chest (the shops' insides are dark)
	local root = model.PrimaryPart or rig.Torso
	local front = Instance.new("Attachment")
	front.Name = "FaceLight"
	front.CFrame = CFrame.new(0, 0.3 * s, -3.4 * s)
	front.Parent = root
	local face = Instance.new("PointLight")
	face.Name = "FaceLight"
	face.Range = 9
	face.Brightness = 0.7
	face.Color = Color3.fromRGB(255, 236, 214)
	face.Shadows = false
	face.Enabled = lights
	face.Parent = front
	-- sparkles rising from the crystals in his pack
	local crystal = built.crystal_purple
	if crystal then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = ShopkeeperBuilder.Sparkle
		sparkles.Rate = 2.5
		sparkles.Lifetime = NumberRange.new(0.9, 1.5)
		sparkles.Speed = NumberRange.new(0.4, 0.9)
		sparkles.SpreadAngle = Vector2.new(35, 35)
		sparkles.EmissionDirection = Enum.NormalId.Top
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Color = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(200, 120, 255))
		sparkles.LightEmission = 1
		sparkles.LightInfluence = 0
		sparkles.Parent = crystal
	end
	-- the gold burst for a sale (Rate 0: ShopkeeperController emits it)
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "CoinBurst"
	burst.Texture = ShopkeeperBuilder.Sparkle
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.7, 1.1)
	burst.Speed = NumberRange.new(6 * s, 9 * s)
	burst.SpreadAngle = Vector2.new(50, 50)
	burst.Acceleration = Vector3.new(0, -14 * s, 0)
	burst.EmissionDirection = Enum.NormalId.Top
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42 * s),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 214, 70), Color3.fromRGB(255, 160, 30))
	burst.LightEmission = 0.8
	burst.LightInfluence = 0
	burst.Parent = rig.Head or root
	-- a warm outline round him (it reads against the dark shops)
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = ShopkeeperBuilder.Glow
	outline.OutlineTransparency = 0.55
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
end

function ShopkeeperBuilder.build(feet: CFrame, scale: number?, opts: Options?): Model
	local s = scale or 1
	local o: Options = opts or {}
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

	-- the pieces, each welded to its rig part (the file's, then the style pass's)
	local built: { [string]: Part } = {}
	local function add(piece: ShopkeeperModel.Piece)
		local part = Instance.new("Part")
		part.Name = piece.Name
		part.Shape = if piece.Shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
		local name = piece.Name
		part.Material = if piece.Material == "Neon" or NEON[name]
			then Enum.Material.Neon
			elseif METAL[name] then Enum.Material.Metal
			elseif LEATHER[name] then Enum.Material.Leather
			elseif FABRIC[name] then Enum.Material.Fabric
			else Enum.Material.SmoothPlastic
		part.Reflectance = if GLOSSY[name] then 0.12 elseif METAL[name] then 0.06 else 0
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
		built[name] = part
	end
	for _, piece in ShopkeeperModel.Pieces do
		if not (o.Badge and LETTERS[piece.Name]) then
			add(piece)
		end
	end
	for _, piece in EXTRA do
		add(piece)
	end

	-- the shop's name on his apron badge
	local sign = built.SHOP_sign
	if o.Badge and sign then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Badge"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 240
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.86, 0.8)
		label.Position = UDim2.fromScale(0.07, 0.1)
		label.Text = o.Badge
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 244, 218)
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.Parent = gui
		gui.Parent = sign
	end

	if o.Effects ~= false then
		ShopkeeperBuilder.effects(model, built, rig, s, o.Lights == true)
	end

	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller
	model.PrimaryPart = root
	return model
end

return ShopkeeperBuilder
