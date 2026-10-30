--[[
	The Dragon King's royal cape (owner 2026-10-30: "premium Dragon King
	equip effect"): every player with the Dragon King golem equipped wears it
	on the back, an exclusive cosmetic for owning it. Built from parts on each
	client (RoyalCapeController) for every wearer near the camera: nothing is
	replicated, no uploads.

	Look: deep royal red velvet (Fabric) in three panels hung on hinges so it
	can flow, flaring out toward the hem, gold edges down both sides along
	the flare, a double gold hem, a velvet mantle with a gold lower edge
	across the top of the back whose ends go over the shoulders and a little
	way down the chest to two gold clasps set with rubies, joined by a
	sagging gold chain, and the Dragon King's crest on the back (a gold crown
	over a flame between two swept wings, an ember in the flame). Subtle gold
	sparkles drift off the middle panel.

	Contract: a Model "RoyalCape" whose PrimaryPart "Root" (invisible) sits at
	the wearer's top back edge (the middle of the torso's back face, at its
	top). +Z points away from the back, +Y up, X across. Panels:
	  CapeTop   from under the mantle down to the pin; welded still to Root. With a
	            backpack on it reaches just below the pack, which sits over it
	            (the pack's own things stick out above the shoulders, so the
	            cape goes under the pack, never over it)
	  CapeMid   hangs from CapeTop on its Weld "Hinge"; carries the crest and
	            the sparkles (ParticleEmitter "CapeSparkle", Enabled = false
	            until the controller turns it on)
	  CapeHem   hangs from CapeMid on its Weld "Hinge"; carries the hem
	A Hinge's C0 at rest is its attribute RestC0; RoyalCape.bend turns it
	(lift = the panel swinging back, roll = swaying to the side). Every other
	part hangs on a Weld (Part0 its panel, C1 = identity) in it, so the whole
	cape moves with the panels. Built in place round Root at the origin; every
	part unanchored, Massless, CanCollide / CanTouch / CanQuery off (the cape
	never changes the body's physics, the camera or any raycast), shadows only
	from the three panels. RoyalCape.attach pivots it onto a torso and welds
	Root there (a Weld to UpperTorso on R15, Torso on R6: never a Motor6D, so
	the Avatar Joint Upgrade's AnimationConstraints don't matter).

	Size: RoyalCape.fit measures the character (the torso's width sets the
	scale, the torso's top to the feet sets the length, the hem stays clear of
	the ground) and the worn backpack (the pin goes just below its bag).
	Budget: RoyalCape.MaxParts parts (tests/RoyalCape.spec.luau).
	Motion (RoyalCape.step / clearance / clear, below): the controller's
	math, pure so previews and tests run it too.

	Pure: only Instance creation (no services), so Lune tests and previews can
	build it.
]]

local BackpackData = require(script.Parent.Parent.Config.BackpackData)
local ItemBuilder = require(script.Parent.ItemBuilder)

local RoyalCape = {}

RoyalCape.Golem = "DragonKing" -- GolemConfig kind whose wearers get the cape
RoyalCape.MaxParts = 32
RoyalCape.SkipTag = "NoStuds" -- StudStyleConfig.SkipTag: the velvet keeps its look
RoyalCape.Sparkle = "rbxasset://textures/particles/sparkles_main.dds"
RoyalCape.SparkleRate = 3 -- particles per second (full mode)

-- Studs at the default 2-stud wide torso (RoyalCape.fit scales them).
RoyalCape.HemClearance = 0.35 -- the hem's bottom above the ground
RoyalCape.Pin = 0.5 -- CapeTop's length without a backpack
RoyalCape.PackMargin = 0.1 -- CapeTop reaches this far below a backpack's bag
RoyalCape.Crest = 0.5 -- the crest's middle below the first hinge (PackCrest under a backpack: clear of its shade)
RoyalCape.PackCrest = 0.62
RoyalCape.MinFlow = 0.9 -- CapeMid + CapeHem never shorter than this
RoyalCape.Width = { Top = 1.96, Hem = 2.7 } -- the flare (inside the torso's width at the top)

export type Fit = {
	Torso: BasePart,
	Scale: number,
	Length: number, -- studs: Root down to the hem's bottom
	Pin: number, -- studs: Root down to the first hinge
	Crest: number, -- studs: the first hinge down to the crest's middle
}

export type Options = {
	Scale: number?,
	Length: number?,
	Pin: number?,
	Crest: number?,
}

local rgb = Color3.fromRGB
local M = Enum.Material
local PI = math.pi

local VELVET = rgb(120, 14, 32)
local GOLD = rgb(255, 196, 56)
local RUBY = ItemBuilder.glowColor(rgb(235, 30, 60))
local EMBER = ItemBuilder.glowColor(rgb(255, 130, 30))
local SPARKLE = rgb(255, 214, 120)

local THICK = 0.09 -- CapeTop's thickness (the lower panels a hair thinner: no coplanar faces)
local GAP = 0.02 -- the back to the velvet's inner face
local OVERLAP = 0.05 -- a lower panel reaches this far above its hinge (no gap when it bends)
local EDGE = 0.09 -- the gold side edges' width

local function seq(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i, v in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(points)
end

-- One part of the cape: decor flags, unanchored and massless (welded later).
local function part(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	shadow: boolean?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = shadow == true
	p.Parent = parent
	return p
end

-- A one-wedge right triangle lying flat on the XY plane (facing +Z): the
-- right angle at `corner`, one leg `w` long toward +X turned by `angle`,
-- the other `h` long toward -Y turned the same way.
local function flatWedge(parent: Instance, name: string, corner: CFrame, w: number, h: number, depth: number, color: Color3): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	-- a WedgePart's right angle is at its bottom-back edge; turned a quarter
	-- about Y its triangle lies in XY with the right angle at (+w/2, -h/2):
	-- half a turn about Z puts it at the top-left, the legs going +X and -Y
	p.Size = Vector3.new(depth, h, w)
	p.CFrame = corner * CFrame.Angles(0, 0, PI) * CFrame.new(-w / 2, h / 2, 0) * CFrame.Angles(0, PI / 2, 0)
	p.Color = color
	p.Material = M.Foil
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Welds `p` to `panel` where it stands (Weld, C1 = identity).
local function stick(p: BasePart, panel: BasePart)
	local weld = Instance.new("Weld")
	weld.Name = "CapeWeld"
	weld.Part0 = panel
	weld.Part1 = p
	weld.C0 = panel.CFrame:ToObjectSpace(p.CFrame)
	weld.Parent = p
end

-- A lower panel's hinge: `child` hangs from `parent` at `at` (Root space).
local function hinge(parent: BasePart, child: BasePart, at: CFrame)
	local weld = Instance.new("Weld")
	weld.Name = "Hinge"
	weld.Part0 = parent
	weld.Part1 = child
	weld.C0 = parent.CFrame:ToObjectSpace(at)
	weld.C1 = child.CFrame:ToObjectSpace(at)
	weld:SetAttribute("RestC0", weld.C0)
	weld.Parent = child
end

-- A thin rod from `a` to `b` (a cylinder: Roblox cylinders run along X).
local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3): BasePart
	local dir = (b - a).Unit
	local up = Vector3.zAxis:Cross(dir).Unit
	local cf = CFrame.fromMatrix((a + b) / 2, dir, up)
	return part(parent, name, cf, Vector3.new((b - a).Magnitude, d, d), color, M.Foil, Enum.PartType.Cylinder)
end

--[[
	Builds the cape round Root at the origin. `options`: Scale (1 = a 2-stud
	wide torso), Length (studs from Root to the hem's bottom) and Pin (studs
	from Root to the first hinge); RoyalCape.fit gives all three.
]]
function RoyalCape.build(options: Options?): Model
	local o: Options = options or {}
	local s = math.clamp(o.Scale or 1, 0.4, 3)
	local length = math.max(o.Length or 3.65 * s, (RoyalCape.Pin + RoyalCape.MinFlow + 0.2) * s)
	local pin = math.clamp(o.Pin or RoyalCape.Pin * s, 0.35 * s, length - RoyalCape.MinFlow * s)
	local crest = o.Crest or RoyalCape.Crest * s
	-- the two flowing panels: CapeMid long enough for the crest
	local flow = length - pin
	local mid = math.max(flow * 0.5, math.min(crest + 0.3 * s, flow * 0.7))

	local model = Instance.new("Model")
	model.Name = "RoyalCape"
	model:SetAttribute(RoyalCape.SkipTag, true)
	local root = part(model, "Root", CFrame.identity, Vector3.new(0.2, 0.2, 0.2) * s, VELVET, M.SmoothPlastic)
	root.Transparency = 1
	model.PrimaryPart = root

	-- the flare: the cape's half width `d` studs below Root
	local function half(d: number): number
		local t = math.clamp(d / length, 0, 1)
		return s * (RoyalCape.Width.Top + (RoyalCape.Width.Hem - RoyalCape.Width.Top) * t) / 2
	end
	local zc = (GAP + THICK / 2) * s -- the panels' middle plane

	-- a velvet panel from `top` to `bottom` studs below Root, its two gold
	-- edges along the flare (each panel a hair thinner than the one above)
	local function panel(name: string, top: number, bottom: number, thin: number): BasePart
		local depth = (THICK - thin) * s
		local h = bottom - top
		-- the velvet as wide as the flare at the panel's top (no red past the gold
		-- there); a long panel flares more than an edge is wide: its edges widen
		local flare = half(bottom) - half(top)
		local edgeWidth = math.max(EDGE * s, flare + 0.01 * s)
		local p =
			part(model, name, CFrame.new(0, -(top + bottom) / 2, zc), Vector3.new(2 * half(top), h, depth), VELVET, M.Fabric, nil, true)
		for i, side in { -1, 1 } do
			local x0, x1 = half(top) - edgeWidth / 2, half(bottom) - edgeWidth / 2
			local tilt = math.atan((x1 - x0) / h)
			local edge = part(
				model,
				name .. "Edge" .. i,
				CFrame.new(side * (x0 + x1) / 2, -(top + bottom) / 2, zc) * CFrame.Angles(0, 0, side * tilt),
				Vector3.new(edgeWidth, h / math.cos(tilt) + 0.02 * s, depth + 0.03 * s),
				GOLD,
				M.Foil
			)
			stick(edge, p)
		end
		return p
	end

	---------------------------------------------------------------- the panels
	local topPanel = panel("CapeTop", 0.12 * s, pin, 0)
	local midPanel = panel("CapeMid", pin - OVERLAP * s, pin + mid, 0.01)
	local hemPanel = panel("CapeHem", pin + mid - OVERLAP * s, length - 0.05 * s, 0.02)
	stick(topPanel, root)
	hinge(topPanel, midPanel, CFrame.new(0, -pin, zc))
	hinge(midPanel, hemPanel, CFrame.new(0, -(pin + mid), zc))

	-- the double gold hem
	local hemDepth = (THICK + 0.05) * s
	stick(
		part(
			model,
			"Hem",
			CFrame.new(0, -length + 0.065 * s, zc),
			Vector3.new(2 * half(length) + 0.03 * s, 0.13 * s, hemDepth),
			GOLD,
			M.Foil
		),
		hemPanel
	)
	stick(
		part(
			model,
			"HemLine",
			CFrame.new(0, -length + 0.23 * s, zc),
			Vector3.new(2 * half(length - 0.23 * s) - 2 * EDGE * s, 0.045 * s, (THICK + 0.01) * s),
			GOLD,
			M.Foil
		),
		hemPanel
	)

	---------------------------------------------------------------- the mantle, clasps, chain
	-- a velvet mantle across the top of the back with a gold lower edge, the
	-- cape hanging from under it: behind the back of the head (a 1.25-stud
	-- head reaches 0.125 behind the torso) it rises level with the shoulders
	stick(part(model, "Mantle", CFrame.new(0, -0.105 * s, 0.205 * s), Vector3.new(2.04, 0.45, 0.15) * s, VELVET, M.Fabric), topPanel)
	stick(part(model, "MantleEdge", CFrame.new(0, -0.33 * s, 0.2 * s), Vector3.new(2.08, 0.07, 0.19) * s, GOLD, M.Foil), topPanel)
	for i, side in { -1, 1 } do
		-- its ends over the shoulders to the clasps (outside a backpack's straps, inside the arms)
		stick(
			part(
				model,
				"Shoulder" .. i,
				CFrame.new(side * 0.86 * s, 0.06 * s, -0.375 * s),
				Vector3.new(0.36, 0.12, 1.29) * s,
				VELVET,
				M.Fabric
			),
			topPanel
		)
		-- and a little way down the chest, the clasp on it: a gold disc, a ruby
		stick(
			part(
				model,
				"Front" .. i,
				CFrame.new(side * 0.85 * s, -0.12 * s, -1.035 * s),
				Vector3.new(0.3, 0.48, 0.07) * s,
				VELVET,
				M.Fabric
			),
			topPanel
		)
		local at = Vector3.new(side * 0.85 * s, -0.1 * s, -1.1 * s)
		stick(
			part(
				model,
				"Clasp" .. i,
				CFrame.new(at) * CFrame.Angles(0, PI / 2, 0),
				Vector3.new(0.06, 0.34, 0.34) * s,
				GOLD,
				M.Foil,
				Enum.PartType.Cylinder
			),
			topPanel
		)
		stick(
			part(
				model,
				"Ruby" .. i,
				CFrame.new(at + Vector3.new(0, 0, -0.04 * s)),
				Vector3.new(0.15, 0.15, 0.15) * s,
				RUBY,
				M.Neon,
				Enum.PartType.Ball
			),
			topPanel
		)
		-- the chain sags from the clasp to the middle of the chest (in front of a backpack's straps)
		stick(
			rod(model, "Chain" .. i, Vector3.new(side * 0.72, -0.18, -1.12) * s, Vector3.new(0, -0.42, -1.12) * s, 0.05 * s, GOLD),
			topPanel
		)
	end

	---------------------------------------------------------------- the crest
	-- on CapeMid's back, just below the hinge (below a backpack, between the shoulder blades without one)
	local back = zc + (THICK - 0.01) * s / 2
	local k = 1.2 * s -- (the crest's size)
	local function at(x: number, y: number, dz: number): CFrame
		return CFrame.new(x * k, -pin - crest + y * k, back + dz * s)
	end
	local diamond = CFrame.Angles(0, 0, PI / 4)
	-- the flame: a gold diamond with an ember inside
	stick(part(model, "CrestFlame", at(0, -0.07, 0.012) * diamond, Vector3.new(0.2 * k, 0.2 * k, 0.035 * s), GOLD, M.Foil), midPanel)
	stick(part(model, "CrestEmber", at(0, -0.07, 0.03) * diamond, Vector3.new(0.1 * k, 0.1 * k, 0.03 * s), EMBER, M.Neon), midPanel)
	-- two swept wings, rising outward from the flame
	for i, side in { -1, 1 } do
		local corner = at(side * 0.13, 0.03, 0.008) * CFrame.Angles(0, 0, side * 0.32)
		if side < 0 then
			-- the left one mirrored (half a turn about Y: the legs go -X and -Y)
			corner = corner * CFrame.Angles(0, PI, 0)
		end
		stick(flatWedge(model, "CrestWing" .. i, corner, 0.27 * k, 0.22 * k, 0.03 * s, GOLD), midPanel)
	end
	-- the crown above: a band and three points (diamonds half behind the band)
	stick(part(model, "CrestCrown", at(0, 0.15, 0.015), Vector3.new(0.34 * k, 0.07 * k, 0.035 * s), GOLD, M.Foil), midPanel)
	for i, x in { -0.13, 0, 0.13 } do
		local size = if x == 0 then 0.12 else 0.09
		stick(
			part(
				model,
				"CrestPoint" .. i,
				at(x, 0.2 + (if x == 0 then 0.02 else 0), 0.008) * diamond,
				Vector3.new(size * k, size * k, 0.03 * s),
				GOLD,
				M.Foil
			),
			midPanel
		)
	end

	---------------------------------------------------------------- the sparkles
	local e = Instance.new("ParticleEmitter")
	e.Name = "CapeSparkle"
	e.Texture = RoyalCape.Sparkle
	e.Color = ColorSequence.new(SPARKLE)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = seq(0.16, 0.12, 0)
	e.Transparency = seq(0.15, 0.35, 1)
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Speed = NumberRange.new(0.2, 0.5)
	e.SpreadAngle = Vector2.new(60, 60)
	e.EmissionDirection = Enum.NormalId.Back
	e.Acceleration = Vector3.new(0, 0.35, 0)
	e.Drag = 0.8
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Rate = RoyalCape.SparkleRate
	e.Enabled = false
	e.Parent = midPanel

	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	model:SetAttribute("Parts", count)
	-- (its shape for RoyalCape.clearance)
	model:SetAttribute("Pin", pin)
	model:SetAttribute("Mid", mid)
	model:SetAttribute("Length", length)
	model:SetAttribute("HalfTop", half(0))
	model:SetAttribute("HalfHem", half(length))
	return model
end

---------------------------------------------------------------- wearing it

-- Does an EquippedAttribute value ("PebbleGolem,DragonKing,...") hold the Dragon King?
function RoyalCape.wears(kinds: any): boolean
	if type(kinds) ~= "string" then
		return false
	end
	for kind in string.gmatch(kinds, "[^,]+") do
		if string.match(kind, "^%s*(.-)%s*$") == RoyalCape.Golem then
			return true
		end
	end
	return false
end

-- The torso the cape hangs on: UpperTorso (R15) or Torso (R6).
function RoyalCape.torsoOf(character: Model): BasePart?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

-- Root's place on the torso: the middle of its back face, at its top.
function RoyalCape.anchor(torso: BasePart): CFrame
	return CFrame.new(0, torso.Size.Y / 2, torso.Size.Z / 2)
end

--[[
	The cape's size for `character` wearing the backpack `packId` (nil: none),
	or nil while its torso or HumanoidRootPart isn't there (not streamed in
	yet, R15 parts still arriving).
]]
function RoyalCape.fit(character: Model, packId: string?): Fit?
	local torso = RoyalCape.torsoOf(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not torso or not root or not root:IsA("BasePart") then
		return nil
	end
	local scale = math.clamp(torso.Size.X / 2, 0.5, 2.5)
	-- the feet below the root: R15 stands on HipHeight, R6 on its legs (HipHeight 0)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid and humanoid.HipHeight > 0.05 then humanoid.HipHeight else 2
	local leg = character:FindFirstChild("Left Leg")
	if hip == 2 and leg and leg:IsA("BasePart") then
		hip = leg.Size.Y
	end
	-- (in the root's frame: an emote's bend doesn't change it much)
	local top = root.CFrame:PointToObjectSpace((torso.CFrame * RoyalCape.anchor(torso)).Position).Y
	local drop = top + root.Size.Y / 2 + hip
	local length = math.clamp(drop - RoyalCape.HemClearance * scale, 2 * scale, 7 * scale)
	local pin = RoyalCape.Pin * scale
	local pack = if packId then BackpackData.ById[packId] else nil
	if pack then
		-- (BackpackWearController scales the pack by the same torso width)
		pin = (pack.Size.Y + RoyalCape.PackMargin) * scale
	end
	pin = math.min(pin, length - RoyalCape.MinFlow * scale)
	local crest = (if pack then RoyalCape.PackCrest else RoyalCape.Crest) * scale
	return { Torso = torso, Scale = scale, Length = length, Pin = pin, Crest = crest }
end

-- Puts a built cape on `torso`: pivoted in place, Root welded to it. Returns the weld.
function RoyalCape.attach(model: Model, torso: BasePart): Weld
	local root = model.PrimaryPart :: BasePart
	local offset = RoyalCape.anchor(torso)
	model:PivotTo(torso.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Name = "CapeAttach"
	weld.Part0 = torso
	weld.Part1 = root
	weld.C0 = offset
	weld.Parent = root
	return weld
end

-- The two hinges, top to bottom (CapeMid's, CapeHem's).
function RoyalCape.hinges(model: Model): (Weld?, Weld?)
	local function find(name: string): Weld?
		local panel = model:FindFirstChild(name)
		local weld = if panel then panel:FindFirstChild("Hinge") else nil
		return if weld and weld:IsA("Weld") then weld else nil
	end
	return find("CapeMid"), find("CapeHem")
end

-- Turns a hinge from its rest: `lift` swings the panel back (radians), `roll` to the side.
function RoyalCape.bend(weld: Weld, lift: number, roll: number)
	local rest = weld:GetAttribute("RestC0")
	if typeof(rest) == "CFrame" then
		weld.C0 = rest * CFrame.Angles(-lift, 0, roll)
	end
end

---------------------------------------------------------------- the flow

--[[
	How the cape moves (RoyalCapeController steps it at most Flow.Rate times a
	second for every cape near the camera; previews and tests step it too).
	Walking or running lifts it back (CapeHem a little more than CapeMid: it
	curves), with a flutter that quickens with the speed; boards and speed
	boots lift it further. Falling fast billows it up, turning or strafing
	swings it out to the side, and standing still it waves gently in a breeze.
	Walking backwards barely lifts it. Calm (Reduce motion): only a smaller,
	smooth lift; no flutter, breeze, billow or swing.
]]
RoyalCape.Flow = {
	Rate = 30, -- updates per second at most
	RunSpeed = 20, -- studs/s: the full walking lift (walking is ~18)
	FastSpeed = 50, -- studs/s: the most lift (boards, speed boots)
	Rest = { 0.05, 0.04 }, -- radians off the back at rest (CapeMid's hinge, CapeHem's)
	Lift = { 0.36, 0.34 }, -- radians more at RunSpeed
	FastLift = { 0.4, 0.2 }, -- radians more at FastSpeed
	Fall = 0.5, -- radians more falling fast
	Flutter = 0.09, -- radians: the wave at RunSpeed
	Breeze = 0.035, -- radians: the idle wave
	TurnRoll = 0.05, -- radians of swing per radian/s of turning
	MaxRoll = 0.28,
	Ease = 7, -- 1/s: how fast the lift follows the speed
	CalmLift = 0.5, -- Reduce motion: this much of the lift
	Gap = 0.08, -- studs from a limb to the panels' middle (half their thickness and a little)
	PushIn = 30, -- 1/s: how fast a limb pushes the cape back
	PushOut = 5, -- 1/s: how fast it falls back after
	MaxPush = { 1.0, 1.45 }, -- radians: a heel kicked up to the hips passes (no cape flipping up)
}

export type FlowState = {
	Speed: number, -- smoothed studs/s
	Lift1: number,
	Lift2: number,
	Roll: number,
	Phase: number, -- the flutter's phase
	Time: number,
	Seed: number,
	Push1: number, -- CapeMid's least lift (eased), RoyalCape.clear
	Push2: number, -- CapeHem's least total lift (eased)
}

function RoyalCape.newFlow(seed: number?): FlowState
	local f = RoyalCape.Flow
	return { Speed = 0, Lift1 = f.Rest[1], Lift2 = f.Rest[2], Roll = 0, Phase = 0, Time = 0, Seed = seed or 0, Push1 = 0, Push2 = 0 }
end

--[[
	One step of `dt` seconds for a character moving `forward` / `side` studs/s
	(its own facing; side > 0 = to its right), `vertical` studs/s (up > 0) and
	turning `turn` radians/s (left > 0). Returns the hinges' angles: CapeMid's
	lift and roll, CapeHem's lift and roll (RoyalCape.bend).
]]
function RoyalCape.step(
	state: FlowState,
	dt: number,
	forward: number,
	side: number,
	vertical: number,
	turn: number,
	calm: boolean
): (number, number, number, number)
	local f = RoyalCape.Flow
	local moving = math.max(forward, 0) + 0.4 * math.abs(side) + 0.25 * math.max(-forward, 0)
	state.Speed += (moving - state.Speed) * (1 - math.exp(-dt * 6))
	local run = math.clamp(state.Speed / f.RunSpeed, 0, 1)
	local fast = math.clamp((state.Speed - f.RunSpeed) / (f.FastSpeed - f.RunSpeed), 0, 1)
	local lift1 = f.Lift[1] * run + f.FastLift[1] * fast
	local lift2 = f.Lift[2] * run + f.FastLift[2] * fast
	local roll = 0
	if calm then
		lift1 *= f.CalmLift
		lift2 *= f.CalmLift
	else
		local fall = math.clamp((-vertical - 10) / 40, 0, 1) * f.Fall
		lift1 += fall * 0.6
		lift2 += fall * 0.4
		roll = math.clamp(-turn * f.TurnRoll - side / f.RunSpeed * 0.12, -f.MaxRoll, f.MaxRoll)
	end
	local ease = 1 - math.exp(-dt * f.Ease)
	state.Lift1 += (f.Rest[1] + lift1 - state.Lift1) * ease
	state.Lift2 += (f.Rest[2] + lift2 - state.Lift2) * ease
	state.Roll += (roll - state.Roll) * ease
	state.Time += dt
	state.Phase = (state.Phase + dt * (6 + 6 * run)) % (4 * PI) -- (4 pi: the half-speed sways wrap smoothly)
	if calm then
		return state.Lift1, 0, state.Lift2, 0
	end
	-- the flutter while moving, the breeze standing still
	local flutter = f.Flutter * run * (1 + 0.5 * fast)
	local breeze = f.Breeze * (1 - run)
	local t, phase, seed = state.Time, state.Phase, state.Seed
	local wave1 = math.sin(phase) * flutter * 0.45 + math.sin(t * 1.3 + seed) * breeze
	local wave2 = math.sin(phase - 1.1) * flutter + math.sin(t * 1.3 + seed - 0.8) * breeze * 1.4
	local sway1 = math.sin(t * 0.9 + seed) * breeze * 0.6 + math.sin(phase * 0.5) * flutter * 0.25
	local sway2 = math.sin(t * 0.9 + seed - 0.6) * breeze * 0.8 + math.sin(phase * 0.5 - 0.8) * flutter * 0.35
	return state.Lift1 + wave1, state.Roll * 0.6 + sway1, state.Lift2 + wave2, state.Roll * 0.4 + sway2
end

---------------------------------------------------------------- staying behind the limbs

-- The parts a flowing panel keeps behind (R15 and R6): a running avatar
-- kicks its heels up behind it, arms swing back past the cape's edges, an
-- emote may kick back too.
RoyalCape.Limbs = {
	"LeftUpperLeg",
	"RightUpperLeg",
	"LeftLowerLeg",
	"RightLowerLeg",
	"LeftFoot",
	"RightFoot",
	"LeftLowerArm",
	"RightLowerArm",
	"LeftHand",
	"RightHand",
	"Left Leg",
	"Right Leg",
	"Left Arm",
	"Right Arm",
}

function RoyalCape.limbs(character: Model): { BasePart }
	local out = {}
	for _, name in RoyalCape.Limbs do
		local limb = character:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			table.insert(out, limb)
		end
	end
	return out
end

-- CapeMid's hinge in world space at rest (CapeTop's frame there: X across, Y up, Z back).
function RoyalCape.hingeFrame(model: Model): CFrame?
	local top = model:FindFirstChild("CapeTop")
	local mid = RoyalCape.hinges(model)
	local rest = if mid then mid:GetAttribute("RestC0") else nil
	if top and top:IsA("BasePart") and typeof(rest) == "CFrame" then
		return top.CFrame * rest
	end
	return nil
end

export type Shape = {
	Pin: number, -- studs: Root down to CapeMid's hinge
	Mid: number, -- CapeMid's length
	Length: number, -- Root down to the hem
	HalfTop: number, -- the half width at Root
	HalfHem: number, -- the half width at the hem
	Scale: number,
}

-- A built cape's shape (its attributes), for RoyalCape.clearance.
function RoyalCape.shape(model: Model): Shape?
	local function num(name: string): number?
		local v = model:GetAttribute(name)
		return if type(v) == "number" then v else nil
	end
	local pin, mid, length, top, hem = num("Pin"), num("Mid"), num("Length"), num("HalfTop"), num("HalfHem")
	if not (pin and mid and length and top and hem) then
		return nil
	end
	return { Pin = pin, Mid = mid, Length = length, HalfTop = top, HalfHem = hem, Scale = top / (RoyalCape.Width.Top / 2) }
end

local corners: { Vector3 } = {} -- (reused: the limbs' corners in the hinge's frame)
local SIGNS = { -1, 1 }

--[[
	The least lifts that keep the flowing panels behind `limbs`' corners:
	`hinge` = RoyalCape.hingeFrame, `shape` = RoyalCape.shape, `lift1` =
	CapeMid's lift about to be shown (it moves CapeHem's hinge). A corner
	counts where the cape is wider than it is far out to the side (by a
	margin: an elbow brushing the flared edge doesn't swing the cape), and
	only below the hinge; the gap kept grows from nothing at the hinge (a
	thigh right under it can't be helped) to Flow.Gap. Returns CapeMid's
	least lift and CapeHem's least total lift (CapeMid's plus its own),
	radians; 0 when nothing is behind the cape.
]]
function RoyalCape.clearance(hinge: CFrame, shape: Shape, limbs: { BasePart }, lift1: number): (number, number)
	local s = shape.Scale
	local gap = RoyalCape.Flow.Gap * s
	local n = 0
	for _, limb in limbs do
		local cf, size = limb.CFrame, limb.Size / 2
		for _, sx in SIGNS do
			for _, sy in SIGNS do
				for _, sz in SIGNS do
					local p = hinge:PointToObjectSpace(cf * Vector3.new(sx * size.X, sy * size.Y, sz * size.Z))
					local down = -p.Y
					local t = math.clamp((shape.Pin + down) / shape.Length, 0, 1)
					local half = shape.HalfTop + (shape.HalfHem - shape.HalfTop) * t
					if down > 0.15 * s and math.abs(p.X) < half - 0.12 * s then
						n += 1
						corners[n] = p
					end
				end
			end
		end
	end
	-- (the gap kept grows from nothing at the pinned hinge; past the bend it is
	-- whole: CapeMid lifts for it)
	local function clear(z: number, down: number, whole: boolean?): number
		return math.atan2(z + (if whole then gap else gap * math.clamp(down / (0.6 * s), 0, 1)), down)
	end
	-- CapeMid's lift `a`: the corners along it need it at least so far back;
	-- the ones past its bottom need CapeHem's total lift from there (a heel
	-- right behind the bend can only be cleared by lifting CapeMid further)
	local f = RoyalCape.Flow
	local mid = shape.Mid
	local function needs(a: number): (number, number)
		local cosA, sinA = math.cos(a), math.sin(a)
		local hy, hz = -mid * cosA, mid * sinA
		local alongMid, pastMid = 0, 0
		for i = 1, n do
			local p = corners[i]
			if -p.Y * cosA + p.Z * sinA <= mid then
				alongMid = math.max(alongMid, clear(p.Z, -p.Y))
			else
				local down, back = hy - p.Y, p.Z - hz
				if down > 0.02 * s then
					pastMid = math.max(pastMid, clear(back, down, true))
				elseif back + gap > 0 then
					pastMid = math.huge -- (above the bend and behind it)
				end
			end
		end
		return alongMid, pastMid
	end
	local a = lift1
	local need1, need2 = needs(a)
	for _ = 1, 10 do
		if need1 <= a + 1e-3 and need2 <= f.MaxPush[2] or a >= f.MaxPush[1] then
			break
		end
		a = math.min(f.MaxPush[1], math.max(need1, a + 0.1))
		local along, past = needs(a)
		need1, need2 = math.max(along, a), past
	end
	if need2 == math.huge then
		need2 = f.MaxPush[2]
	end
	table.clear(corners)
	return need1, need2
end

--[[
	Eases the limbs' push (quick in, slow out: the cape bounces off a heel and
	settles) and lifts the step's angles to it. Returns CapeMid's and
	CapeHem's lifts.
]]
function RoyalCape.clear(state: FlowState, dt: number, lift1: number, lift2: number, need1: number, need2: number): (number, number)
	local f = RoyalCape.Flow
	local function ease(current: number, target: number): number
		local rate = if target > current then f.PushIn else f.PushOut
		return current + (target - current) * (1 - math.exp(-dt * rate))
	end
	state.Push1 = ease(state.Push1, math.min(need1, f.MaxPush[1]))
	state.Push2 = ease(state.Push2, math.min(need2, f.MaxPush[2]))
	local a = math.max(lift1, state.Push1)
	return a, math.max(lift2, state.Push2 - a)
end

return RoyalCape
