--[[
	MECHA NEON (upcoming limited edition): the costumes of the set's 6 chrome
	robot golems and the set's shard (GolemGearLimited explains the contract
	and the tools).

	  NeonVisor   Bolt Bot (Rare): a big dark visor with oval neon eyes, ear
	              bolts with glowing caps, an antenna with a blinking ball, a
	              yellow lightning bolt on the shoulder, a red hero scarf
	              streaming in the wind, a tool belt with a chrome wrench and a
	              glowing battery and a little helper drone hovering over its
	              shoulder
	  Headset     Beat Bot (Rare): huge DJ headphones with neon rings, a boom
	              mic, a face screen with an equalizer mouth, shutter shades
	              pushed up on its forehead, a gold chain with a record
	              medallion, a speaker chest, a glow stick, light-up sneakers
	              and a vinyl record in its hand
	  MechaCrest  Laser Ranger (Epic): a hero helmet with a gold V-fin crest,
	              cheek guards, a scanner monocle, layered shoulder pads, a
	              red HERO CAPE with neon trim and gold clasps, a holo star
	              badge, neon gauntlets, a chest chevron and a laser rifle
	  Rockets     Rocket Rex (Epic): a robot dino: a snout with chrome teeth
	              and a glowing maw, aviator goggles pushed up on its head, a big firework rocket in its claw,
	              chrome back plates, shoulder rocket pods (four rockets), a
	              a gold CHAMPION belt, claws
	              and a mechanical tail
	  JetPack     Jet Striker (Legendary): a pilot dome helmet with a wrap
	              visor and a tail fin, a white aviator scarf streaming back
	              over the wings, gold squadron wings with a neon star on the
	              chest, a jet pack with two flaming thrusters, swept wing
	              blades with neon edges and missiles under them, arm blades,
	              boot jets, embers
	  OmegaMech   Omega Mech (Mythic): a heavy mech frame: a gold crown V-fin,
	              a closed face plate, huge layered shoulder armour, a royal
	              CYBER-CLOAK (black with neon trim, a high collar, gem clasps),
	              an arm cannon, a neon energy sword in its mech fist, a
	              glowing chest reactor, a giant neon reactor ring on its back,
	              boot jets, embers and its own light

	The shard: a MECHA EGG of glossy chrome hovering on a jet ring, neon
	circuit lines, a visor window with cute eyes, ear bolts, antennas, a
	little V-fin crown, a tilted neon orbit ring and twinkling stars.
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Shard = Types.Shard

local MechaNeon = {}

-- (every robot's face is a screen or a visor: no stone brow)
MechaNeon.Faces = {
	NeonVisor = "Visor",
	Headset = "Visor",
	MechaCrest = "Visor",
	Rockets = "Visor",
	JetPack = "Visor",
	OmegaFrame = "Visor",
} :: { [string]: string }

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local METAL = M.Metal
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local PI = math.pi

local CHROME = rgb(214, 222, 238)
local CHROME_DARK = rgb(132, 140, 162)
local GLASS = rgb(16, 18, 32)
local DARK = rgb(34, 34, 50)
local CYAN = rgb(0, 236, 255)
local MAGENTA = rgb(255, 46, 196)
local YELLOW = rgb(255, 222, 40)
local GOLD = rgb(255, 196, 56)
local FLAME = rgb(255, 130, 30)
local FLAME_HOT = rgb(255, 236, 120)
local WHITE = rgb(246, 248, 255)
local SCARF_RED = rgb(230, 40, 54)

-- (the shared tools, filled by accessories / shard)
local T: Tools = nil :: any
local K: Kit = nil :: any

---------------------------------------------------------------- small shapes

-- a box at a golem-local point (unscaled), turned by `rot`
local function box(c: Ctx, name: string, p: Vector3, size: Vector3, color: Color3, material: Enum.Material?, rot: CFrame?): Part
	return K.part(c.Model, name, c.At(p.X, p.Y, p.Z) * (rot or CFrame.identity), c.V(size.X, size.Y, size.Z), color, material)
end

local function ball(c: Ctx, name: string, p: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	return K.part(c.Model, name, c.At(p.X, p.Y, p.Z), c.V(d, d, d), color, material, BALL)
end

-- a disc / short cylinder `len` long along an axis ("X" sideways, "Y" up,
-- "Z" facing the front)
local function disc(c: Ctx, name: string, p: Vector3, len: number, d: number, axis: string, color: Color3, material: Enum.Material?): Part
	local rot = if axis == "Z" then CFrame.Angles(0, PI / 2, 0) elseif axis == "Y" then CFrame.Angles(0, 0, PI / 2) else CFrame.identity
	return K.part(c.Model, name, c.At(p.X, p.Y, p.Z) * rot, c.V(len, d, d), color, material, CYL)
end

-- a diamond (a square turned 45 degrees about its facing axis)
local function diamond(c: Ctx, name: string, cf: CFrame, w: number, thick: number, color: Color3, material: Enum.Material?): Part
	return K.part(c.Model, name, cf * CFrame.Angles(0, 0, PI / 4), c.V(w, w, thick), color, material)
end

-- a bar between two golem-local points (w x d thick, unscaled)
local function bar(c: Ctx, name: string, a: Vector3, b: Vector3, w: number, d: number, color: Color3, material: Enum.Material?): Part
	return T.seg(c.Model, name, T.P(c, a.X, a.Y, a.Z), T.P(c, b.X, b.Y, b.Z), w * c.S, d * c.S, color, material)
end

-- a flat triangle through three golem-local points (one or two wedges)
local function tri(c: Ctx, name: string, a: Vector3, b: Vector3, p: Vector3, thick: number, color: Color3, material: Enum.Material?)
	T.tri(
		c.Model,
		name,
		T.P(c, a.X, a.Y, a.Z),
		T.P(c, b.X, b.Y, b.Z),
		T.P(c, p.X, p.Y, p.Z),
		thick * c.S,
		color,
		material,
		math.min(2, c.Room())
	)
end

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- the body's own part `name` becomes an oval (a Sphere SpecialMesh: free)
local function oval(c: Ctx, name: string)
	local p = c.Model:FindFirstChild(name)
	if p and p:IsA("BasePart") and not p:FindFirstChildOfClass("SpecialMesh") then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
end

-- the body's own part `name` turns into a round disc facing the front
local function roundFront(c: Ctx, name: string, p: Vector3, d: number, color: Color3)
	local q = c.Model:FindFirstChild(name)
	if q and q:IsA("Part") then
		q.Shape = CYL
		q.CFrame = c.At(p.X, p.Y, p.Z) * CFrame.Angles(0, PI / 2, 0)
		q.Size = c.V(0.05, d, d)
		q.Color = color
		q.Material = NEON
	end
end

-- the eyes re-dressed (eyes = glow shapes, tilted `tilt` outward-down)
local function eyes(c: Ctx, y: number, size: Vector3, tilt: number, round: boolean, z: number?)
	for i, x in { -0.29, 0.29 } do
		local side = if i == 1 then -1 else 1
		T.redress(c, "Eye" .. i, c.At(x, y, z or -0.715) * CFrame.Angles(0, 0, side * tilt), c.V(size.X, size.Y, size.Z), c.Glow, NEON)
		if round then
			oval(c, "Eye" .. i)
		end
	end
end

-- every robot: chrome-trimmed shoulder pads (the boulder and the crystal
-- re-dressed) and metal legs and fists
local function mechaBody(c: Ctx, padColor: Color3, size: Vector3, x: number, y: number)
	for i, side in { -1, 1 } do
		T.redress(
			c,
			if i == 1 then "Boulder" else "Crystal",
			c.At(side * x, y, 0) * CFrame.Angles(0, 0, -side * 0.16),
			c.V(size.X, size.Y, size.Z),
			padColor,
			METAL
		)
	end
	for _, name in { "Leg1", "Leg2" } do
		T.recolor(c, name, c.Look.Trim, M.DiamondPlate)
	end
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, c.Look.Trim, METAL)
	end
end

-- an octagon ring of bars in the plane facing the front (golem-local),
-- `n` bars; returns the top
local function ring(c: Ctx, name: string, center: Vector3, r: number, w: number, color: Color3, material: Enum.Material?): number
	local n = 8
	for i = 1, n do
		if c.Room() < 1 then
			break
		end
		local a0, a1 = (i - 0.5) * 2 * PI / n, (i + 0.5) * 2 * PI / n
		local a = center + v3(math.sin(a0) * r, math.cos(a0) * r, 0)
		local b = center + v3(math.sin(a1) * r, math.cos(a1) * r, 0)
		local dir = (b - a).Unit
		bar(c, name .. i, a - dir * w * 0.5, b + dir * w * 0.5, w, w, color, material)
	end
	return center.Y + r
end

local function bodyPart(c: Ctx): BasePart?
	local body = c.Model:FindFirstChild("Body")
	return if body and body:IsA("BasePart") then body else nil
end

--[[
	A CAPE hanging from the shoulders behind the body (golem-local, unscaled):
	the cloth (a slab tilted back from z0 at the shoulders to z1 at the hem),
	two triangular flares widening it from w0 to w1 at the hem (swept `Sweep`
	sideways and lifted `Lift` up and back, as if the wind caught it), a neon
	hem and neon side edges, two clasps at the collarbones. In priority
	order, as far as the room allows: cloth, flares, hem, clasps, edges.
]]
type CapeSpec = {
	Y0: number,
	Y1: number,
	Z0: number,
	Z1: number,
	W0: number,
	W1: number,
	Cloth: Color3,
	Trim: Color3,
	Clasp: Color3,
	ClaspMaterial: Enum.Material,
	Sweep: number,
	Lift: number,
}
local function cape(c: Ctx, k: CapeSpec)
	local h = k.Y0 - k.Y1
	local dz = k.Z1 - k.Z0
	local tilt = -math.atan2(dz, h)
	local thick = 0.06
	box(
		c,
		"Cape",
		v3(0, (k.Y0 + k.Y1) / 2, (k.Z0 + k.Z1) / 2),
		v3(k.W0, math.sqrt(h * h + dz * dz), thick),
		k.Cloth,
		M.Fabric,
		CFrame.Angles(tilt, 0, 0)
	)
	-- the hem's outer corners
	local function corner(side: number): Vector3
		return v3(side * k.W1 / 2 + k.Sweep, k.Y1 + k.Lift, k.Z1 + k.Lift)
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			tri(
				c,
				"CapeFlare" .. i,
				v3(side * k.W0 / 2, k.Y0, k.Z0),
				v3(side * k.W0 / 2, k.Y1, k.Z1),
				corner(side),
				thick,
				k.Cloth,
				M.Fabric
			)
		end
	end
	if c.Room() >= 1 then
		-- (the hem follows the cloth's bottom edge and the lifted corners: one bar from corner to corner)
		bar(c, "CapeHem", corner(-1) + v3(0, 0.03, 0.02), corner(1) + v3(0, 0.03, 0.02), 0.08, 0.1, k.Trim, NEON)
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			diamond(c, "CapeClasp" .. i, c.At(side * 0.42, 1.36, -0.45), 0.2, 0.06, k.Clasp, k.ClaspMaterial)
		end
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			local a = v3(side * k.W0 / 2, k.Y0 - 0.06, k.Z0 + 0.01)
			bar(c, "CapeEdge" .. i, a, corner(side) + v3(0, 0.03, 0.02), 0.07, 0.07, k.Trim, NEON)
		end
	end
end

--[[
	A SCARF: a wrap round the neck, (with `knot`) a knot with a short end at
	the front, and one long tail streaming back and out to `side` in the
	wind, rising by `rise` (two waving segments and a forked tip), in
	priority order.
]]
local function scarf(c: Ctx, color: Color3, side: number, rise: number, knot: boolean)
	box(c, "ScarfWrap", v3(0, 1.43, 0), v3(1.32, 0.2, 1.0), color, M.Fabric)
	if knot and c.Room() >= 2 then
		box(c, "ScarfKnot", v3(-side * 0.3, 1.34, -0.5), v3(0.24, 0.22, 0.1), color, M.Fabric, CFrame.Angles(0, 0, 0.4))
		bar(c, "ScarfEnd", v3(-side * 0.3, 1.3, -0.52), v3(-side * 0.36, 0.95, -0.5), 0.2, 0.05, color, M.Fabric)
	end
	-- the long tail: back from the neck, out to the side, waving up
	local p0, p1, p2 = v3(side * 0.55, 1.46, 0.44), v3(side * 1.0, 1.34 + rise * 0.5, 0.84), v3(side * 1.5, 1.46 + rise, 1.12)
	if c.Room() >= 1 then
		bar(c, "ScarfTail1", p0, p1, 0.05, 0.3, color, M.Fabric)
	end
	if c.Room() >= 1 then
		bar(c, "ScarfTail2", p1, p2, 0.05, 0.26, color, M.Fabric)
	end
	if c.Room() >= 1 then
		local dir = (p2 - p1).Unit
		tri(c, "ScarfTip", p2 + v3(0, 0.13, 0), p2 - v3(0, 0.13, 0), p2 + dir * 0.36 - v3(0, 0.1, 0), 0.05, color, M.Fabric)
	end
end

---------------------------------------------------------------- the costumes

local function boltBot(c: Ctx): number
	local trim = c.Look.Trim
	mechaBody(c, trim, v3(0.5, 0.34, 0.64), 0.8, 1.52)
	-- the big visor and oval eyes
	box(c, "Visor", v3(0, 2.04, -0.675), v3(1.42, 0.58, 0.06), GLASS, M.SmoothPlastic)
	eyes(c, 2.04, v3(0.32, 0.3, 0.04), 0, true)
	box(c, "VisorLine", v3(0, 2.36, -0.68), v3(1.42, 0.05, 0.06), c.Glow, NEON)
	-- ear bolts with glowing caps
	for i, side in { -1, 1 } do
		disc(c, "Ear" .. i, v3(side * 0.8, 2.04, 0), 0.14, 0.58, "X", trim, METAL)
		disc(c, "EarLight" .. i, v3(side * 0.88, 2.04, 0), 0.04, 0.34, "X", c.Glow, NEON)
	end
	-- the antenna and its blinking ball
	local top = 2.7
	if c.Room() >= 3 then
		disc(c, "AntennaBase", v3(0.32, 2.74, 0.05), 0.1, 0.32, "Y", trim, METAL)
		box(c, "Antenna", v3(0.32, 3.02, 0.05), v3(0.07, 0.52, 0.07), CHROME, METAL)
		ball(c, "AntennaBall", v3(0.32, 3.34, 0.05), 0.28, MAGENTA, NEON)
		top = 3.48
	end
	-- the red hero scarf, its tail streaming out to the left (the picture's right)
	scarf(c, SCARF_RED, -1, -0.04, true)
	-- the lightning bolt on the right shoulder
	if c.Room() >= 3 then
		local p1, p2, p3, p4 = v3(1.3, 2.5, -0.12), v3(1.06, 2.08, -0.12), v3(1.34, 2.04, -0.12), v3(1.08, 1.58, -0.12)
		bar(c, "Bolt1", p1, p2, 0.2, 0.1, YELLOW, NEON)
		bar(c, "Bolt2", p2 + v3(-0.04, 0, 0), p3 + v3(0.04, 0, 0), 0.14, 0.1, YELLOW, NEON)
		bar(c, "Bolt3", p3, p4, 0.2, 0.1, YELLOW, NEON)
	end
	-- the helper drone hovering over the right shoulder: a chrome ball, a cyan eye, a rotor
	if c.Room() >= 3 then
		local d = v3(1.2, 3.08, -0.05)
		ball(c, "Drone", d, 0.5, CHROME, METAL)
		box(c, "DroneEye", d + v3(0, 0.02, -0.24), v3(0.26, 0.1, 0.04), CYAN, NEON)
		box(c, "DroneRotor", d + v3(0, 0.31, 0), v3(0.84, 0.04, 0.12), DARK, METAL, CFrame.Angles(0, 0.5, 0))
		top = math.max(top, 3.4)
	end
	-- the chest gauge and LED buttons
	if c.Room() >= 1 then
		box(c, "ChestPlate", v3(0, 1.04, -0.44), v3(0.86, 0.66, 0.04), trim, METAL)
	end
	roundFront(c, "Core", v3(0, 1.14, -0.475), 0.32, c.Glow)
	local leds: { Color3 } = { CYAN, MAGENTA, YELLOW }
	for i, color in leds do
		if c.Room() >= 1 then
			box(c, "Led" .. i, v3((i - 2) * 0.24, 0.85, -0.47), v3(0.12, 0.07, 0.03), color, NEON)
		end
	end
	-- the mouth light
	if c.Room() >= 1 then
		box(c, "Mouth", v3(0, 1.64, -0.665), v3(0.36, 0.06, 0.03), c.Glow, NEON)
	end
	-- the tool belt: a chrome wrench on the right hip, a glowing battery on the left
	if c.Room() >= 4 then
		box(c, "Belt", v3(0, 0.57, 0), v3(1.26, 0.13, 0.9), DARK, METAL)
		bar(c, "WrenchGrip", v3(0.44, 0.6, -0.48), v3(0.3, 0.2, -0.48), 0.11, 0.05, CHROME, METAL)
		box(c, "WrenchHead", v3(0.48, 0.7, -0.49), v3(0.3, 0.18, 0.05), CHROME, METAL, CFrame.Angles(0, 0, -0.3))
		box(c, "Battery", v3(-0.42, 0.42, -0.47), v3(0.18, 0.26, 0.06), YELLOW, NEON)
	end
	-- neon cuffs
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			box(c, "Cuff" .. i, v3(side * 0.81, 0.88, 0), v3(0.44, 0.08, 0.54), c.Glow, NEON, CFrame.Angles(0, 0, side * 0.1))
		end
	end
	return top
end

local function beatBot(c: Ctx): number
	local trim = c.Look.Trim
	mechaBody(c, trim, v3(0.46, 0.3, 0.6), 0.8, 1.5)
	-- the face screen, oval eyes and the equalizer mouth
	box(c, "Screen", v3(0, 2.0, -0.672), v3(1.24, 0.8, 0.05), GLASS, M.SmoothPlastic)
	eyes(c, 2.14, v3(0.24, 0.3, 0.04), 0, true, -0.705)
	for i, h in { 0.1, 0.2, 0.3, 0.18, 0.1 } do
		if c.Room() >= 1 then
			local x = (i - 3) * 0.15
			box(c, "Eq" .. i, v3(x, 1.7 + h / 2, -0.705), v3(0.1, h, 0.03), if i % 2 == 1 then CYAN else c.Glow, NEON)
		end
	end
	-- the DJ headphones: band, sides, cups with neon rings
	box(c, "Headband", v3(0, 2.88, 0), v3(1.66, 0.16, 0.32), trim, METAL)
	for i, side in { -1, 1 } do
		box(c, "BandSide" .. i, v3(side * 0.85, 2.64, 0), v3(0.14, 0.5, 0.28), trim, METAL)
		disc(c, "Cup" .. i, v3(side * 0.88, 2.08, 0), 0.3, 0.86, "X", trim, METAL)
		if c.Room() >= 2 then
			disc(c, "CupRing" .. i, v3(side * 1.04, 2.08, 0), 0.04, 0.68, "X", c.Glow, NEON)
			disc(c, "CupCenter" .. i, v3(side * 1.06, 2.08, 0), 0.04, 0.44, "X", CHROME, METAL)
		end
	end
	-- the shutter shades pushed up on the forehead
	if c.Room() >= 2 then
		local rot = CFrame.Angles(-0.25, 0, 0)
		box(c, "Shades", v3(0, 2.52, -0.7), v3(1.18, 0.2, 0.06), DARK, METAL, rot)
		box(c, "ShadeSlats", v3(0, 2.52, -0.735), v3(1.06, 0.05, 0.03), MAGENTA, NEON, rot)
	end
	-- the boom mic from the left cup
	if c.Room() >= 2 then
		bar(c, "MicArm", v3(-0.94, 1.94, -0.3), v3(-0.56, 1.66, -0.78), 0.06, 0.06, DARK, METAL)
		ball(c, "Mic", v3(-0.54, 1.66, -0.8), 0.18, DARK, M.Fabric)
	end
	-- the speaker chest
	if c.Room() >= 3 then
		box(c, "SpeakerBox", v3(0, 0.98, -0.44), v3(0.9, 0.76, 0.05), trim, METAL)
		disc(c, "SpeakerRing", v3(0, 0.94, -0.47), 0.03, 0.6, "Z", c.Glow, NEON)
		disc(c, "SpeakerCone", v3(0, 0.94, -0.49), 0.03, 0.48, "Z", DARK, M.SmoothPlastic)
	end
	roundFront(c, "Core", v3(0, 0.94, -0.51), 0.2, CYAN)
	-- the gold chain with a record medallion over the speaker
	if c.Room() >= 3 then
		for i, side in { -1, 1 } do
			bar(c, "Chain" .. i, v3(side * 0.42, 1.45, -0.47), v3(side * 0.04, 1.3, -0.5), 0.05, 0.05, GOLD, M.Foil)
		end
		disc(c, "Medallion", v3(0, 1.27, -0.51), 0.04, 0.2, "Z", GOLD, M.Foil)
	end
	for i, x in { -0.32, 0.32 } do
		if c.Room() >= 1 then
			disc(c, "Tweeter" .. i, v3(x, 0.66, -0.47), 0.03, 0.1, "Z", CYAN, NEON)
		end
	end
	-- the vinyl record in the right hand, a glow stick in the left
	if c.Room() >= 2 then
		disc(c, "Vinyl", v3(0.98, 0.98, -0.34), 0.04, 0.82, "Z", rgb(20, 20, 26), M.SmoothPlastic)
		disc(c, "Label", v3(0.98, 0.98, -0.365), 0.03, 0.3, "Z", c.Glow, NEON)
	end
	if c.Room() >= 1 then
		bar(c, "GlowStick", v3(-0.9, 0.5, -0.32), v3(-0.98, 1.16, -0.4), 0.09, 0.09, rgb(120, 255, 90), NEON)
	end
	-- light-up sneakers
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			box(c, "Sole" .. i, v3(x, 0.05, -0.04), v3(0.5, 0.1, 0.64), c.Glow, NEON)
		end
	end
	return 2.96
end

local function laserRanger(c: Ctx): number
	local trim = c.Look.Trim
	mechaBody(c, trim, v3(0.58, 0.3, 0.68), 0.82, 1.52)
	-- the helmet: a cap band, cheek guards, a dark visor and slit eyes
	box(c, "HelmCap", v3(0, 2.64, 0.02), v3(1.6, 0.2, 1.4), trim, METAL)
	for i, side in { -1, 1 } do
		box(c, "Cheek" .. i, v3(side * 0.78, 1.96, -0.2), v3(0.1, 0.74, 0.62), trim, METAL)
	end
	box(c, "Visor", v3(0, 2.06, -0.675), v3(1.36, 0.42, 0.05), GLASS, M.SmoothPlastic)
	eyes(c, 2.06, v3(0.36, 0.12, 0.04), 0.16, false)
	box(c, "Chin", v3(0, 1.62, -0.67), v3(0.72, 0.24, 0.08), trim, METAL)
	-- the gold V-fin crest and its gem
	local top = 2.74
	if c.Room() >= 4 then
		box(c, "Forehead", v3(0, 2.48, -0.68), v3(0.46, 0.22, 0.08), trim, METAL)
		for i, side in { -1, 1 } do
			bar(c, "Fin" .. i, v3(side * 0.08, 2.5, -0.74), v3(side * 0.66, 3.22, -0.74), 0.15, 0.06, GOLD, M.Foil)
		end
		diamond(c, "CrestGem", c.At(0, 2.5, -0.75), 0.26, 0.05, c.Glow, NEON)
		top = 3.28
	end
	-- the hero cape: red cloth, neon yellow trim, gold clasps, swept by the wind
	cape(c, {
		Y0 = 1.5,
		Y1 = 0.16,
		Z0 = 0.47,
		Z1 = 0.66,
		W0 = 1.3,
		W1 = 2.3,
		Cloth = rgb(210, 30, 52),
		Trim = YELLOW,
		Clasp = GOLD,
		ClaspMaterial = M.Foil,
		Sweep = -0.35,
		Lift = 0.16,
	})
	-- the scanner monocle over the right eye
	if c.Room() >= 3 then
		disc(c, "Scope", v3(0.29, 2.06, -0.75), 0.1, 0.4, "Z", CHROME, METAL)
		disc(c, "ScopeLens", v3(0.29, 2.06, -0.805), 0.03, 0.28, "Z", c.Glow, NEON)
		box(c, "ScopeArm", v3(0.62, 2.06, -0.5), v3(0.14, 0.08, 0.5), CHROME, METAL)
	end
	-- layered shoulder pads with neon stripes
	for i, side in { -1, 1 } do
		if c.Room() >= 2 then
			local rot = CFrame.Angles(0, 0, -side * 0.16)
			box(c, "PadTop" .. i, v3(side * 0.84, 1.7, 0), v3(0.5, 0.12, 0.6), CHROME, METAL, rot)
			box(c, "PadStripe" .. i, v3(side * 0.82, 1.52, -0.35), v3(0.4, 0.06, 0.03), c.Glow, NEON, rot)
		end
	end
	-- the laser rifle in the right hand
	if c.Room() >= 6 then
		box(c, "RifleBody", v3(0.92, 0.82, -0.42), v3(0.2, 0.28, 0.82), DARK, METAL)
		disc(c, "Barrel", v3(0.92, 0.86, -1.04), 0.46, 0.13, "Z", CHROME, METAL)
		disc(c, "Muzzle", v3(0.92, 0.86, -1.28), 0.06, 0.22, "Z", c.Glow, NEON)
		box(c, "Cell", v3(1.03, 0.82, -0.42), v3(0.02, 0.1, 0.6), c.Glow, NEON)
		disc(c, "RifleScope", v3(0.92, 1.04, -0.4), 0.42, 0.13, "Z", trim, METAL)
		box(c, "Stock", v3(0.92, 0.74, 0.06), v3(0.16, 0.22, 0.32), trim, METAL)
	end
	-- the chest armour, its chevron and a holo star badge
	if c.Room() >= 3 then
		box(c, "ChestPlate", v3(0, 1.1, -0.44), v3(0.9, 0.6, 0.04), trim, METAL)
		for i, side in { -1, 1 } do
			box(c, "Chevron" .. i, v3(side * 0.13, 0.84, -0.465), v3(0.3, 0.07, 0.03), c.Glow, NEON, CFrame.Angles(0, 0, side * 0.55))
		end
	end
	roundFront(c, "Core", v3(0, 1.14, -0.47), 0.26, c.Glow)
	if c.Room() >= 1 then
		diamond(c, "Badge", c.At(-0.3, 1.26, -0.47), 0.16, 0.03, YELLOW, NEON)
	end
	-- the belt and buckle, neon gauntlets
	if c.Room() >= 2 then
		box(c, "Belt", v3(0, 0.56, 0), v3(1.24, 0.12, 0.89), DARK, METAL)
		box(c, "Buckle", v3(0, 0.56, -0.45), v3(0.22, 0.14, 0.03), c.Glow, NEON)
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			box(c, "Gauntlet" .. i, v3(side * 0.82, 0.9, -0.02), v3(0.44, 0.07, 0.54), c.Glow, NEON, CFrame.Angles(0, 0, side * 0.1))
		end
	end
	return top
end

local function rocketRex(c: Ctx): number
	local trim = c.Look.Trim
	-- the rocket pods (the shoulder parts)
	for i, side in { -1, 1 } do
		T.redress(c, if i == 1 then "Boulder" else "Crystal", c.At(side * 0.88, 1.8, 0.05), c.V(0.5, 0.58, 0.8), trim, METAL)
	end
	for _, name in { "Leg1", "Leg2", "Fist1", "Fist2" } do
		T.recolor(c, name, trim, METAL)
	end
	-- the dino head: angry eyes over a snout, an open jaw, a glowing maw, teeth
	eyes(c, 2.32, v3(0.28, 0.14, 0.04), 0.22, false)
	box(c, "Snout", v3(0, 1.98, -0.88), v3(1.1, 0.36, 0.5), c.Look.Body, METAL)
	box(c, "BrowRidge", v3(0, 2.44, -0.68), v3(1.3, 0.1, 0.1), CHROME, METAL)
	box(c, "Jaw", v3(0, 1.56, -0.84), v3(1.0, 0.18, 0.48), trim, METAL, CFrame.Angles(0.18, 0, 0))
	box(c, "Maw", v3(0, 1.72, -0.82), v3(0.9, 0.24, 0.36), c.Glow, NEON)
	for i, x in { -0.36, -0.12, 0.12, 0.36 } do
		if c.Room() >= 1 then
			diamond(c, "Tooth" .. i, c.At(x, 1.8, -1.06) * CFrame.Angles(0, 0, 0), 0.13, 0.06, WHITE, METAL)
		end
	end
	-- aviator goggles pushed up on the head: a strap round it, two amber lenses
	if c.Room() >= 3 then
		box(c, "GoggleStrap", v3(0, 2.58, 0), v3(1.56, 0.12, 1.36), rgb(70, 44, 30), M.Fabric)
		for i, x in { -0.3, 0.3 } do
			-- (tilted up: they sit on the forehead)
			K.part(
				c.Model,
				"Goggle" .. i,
				c.At(x, 2.66, -0.6) * CFrame.Angles(0.7, 0, 0) * CFrame.Angles(0, PI / 2, 0),
				c.V(0.12, 0.32, 0.32),
				rgb(90, 200, 255),
				M.Glass,
				CYL
			)
		end
	end
	-- four rockets in the pods: white bodies, glowing noses
	for i, side in { -1, 1 } do
		for j, y in { 1.94, 1.66 } do
			if c.Room() >= 2 then
				disc(c, `Rocket{i}_{j}`, v3(side * 0.88, y, -0.46), 0.3, 0.2, "Z", WHITE, METAL)
				ball(c, `Nose{i}_{j}`, v3(side * 0.88, y, -0.61), 0.2, c.Glow, NEON)
			end
		end
	end
	-- chrome back plates over the head and down the back
	local top = 2.79
	for i, k in { { 2.86, -0.2, 0.36 }, { 2.9, 0.18, 0.44 }, { 2.7, 0.56, 0.34 }, { 1.62, 0.5, 0.3 } } do
		if c.Room() < 1 then
			break
		end
		diamond(c, "Plate" .. i, c.At(0, k[1], k[2]) * CFrame.Angles(0, PI / 2, 0), k[3], 0.08, CHROME, METAL)
		top = math.max(top, k[1] + k[3] * 0.71)
	end
	-- the chest plate and hazard stripes
	if c.Room() >= 3 then
		box(c, "ChestPlate", v3(0, 1.04, -0.44), v3(0.86, 0.6, 0.04), trim, METAL)
		for i, x in { -0.24, 0.24 } do
			box(c, "Stripe" .. i, v3(x, 1.04, -0.465), v3(0.1, 0.44, 0.03), c.Glow, NEON, CFrame.Angles(0, 0, 0.5))
		end
	end
	roundFront(c, "Core", v3(0, 1.04, -0.475), 0.24, rgb(255, 80, 60))
	-- the gold champion belt: a strap, a big plate, a glowing gem
	if c.Room() >= 3 then
		box(c, "ChampBelt", v3(0, 0.6, 0), v3(1.26, 0.16, 0.9), rgb(40, 34, 50), M.Fabric)
		box(c, "ChampPlate", v3(0, 0.6, -0.46), v3(0.52, 0.3, 0.04), GOLD, M.Foil)
		diamond(c, "ChampGem", c.At(0, 0.6, -0.49), 0.14, 0.03, c.Glow, NEON)
	end
	-- a big firework rocket in the left claw: a white body, a glowing nose, a flame
	if c.Room() >= 3 then
		disc(c, "Firework", v3(-0.9, 0.98, -0.34), 0.7, 0.2, "Y", WHITE, METAL)
		ball(c, "FireworkNose", v3(-0.9, 1.38, -0.34), 0.22, MAGENTA, NEON)
		T.ellipsoid(c.Model, "FireworkFlame", c.At(-0.9, 0.5, -0.34), c.V(0.18, 0.3, 0.18), FLAME, NEON)
	end
	-- claws on the fists
	for i, side in { -1, 1 } do
		for j, dx in { -0.12, 0.12 } do
			if c.Room() >= 1 then
				box(c, `Claw{i}_{j}`, v3(side * 0.86 + dx, 0.56, -0.32), v3(0.1, 0.1, 0.26), WHITE, METAL, CFrame.Angles(0.5, 0, 0))
			end
		end
	end
	-- the mechanical tail, curling out to the right, a glowing tip
	local tail = { v3(0.2, 0.5, 0.4), v3(0.62, 0.36, 0.72), v3(1.08, 0.28, 0.56), v3(1.34, 0.36, 0.14) }
	for i = 1, 3 do
		if c.Room() < 1 then
			break
		end
		local w = 0.26 * (1 - 0.2 * (i - 1))
		local a, b = tail[i], tail[i + 1]
		local dir = (b - a).Unit
		bar(c, "Tail" .. i, a - dir * w * 0.35, b + dir * w * 0.2, w, w, if i == 2 then CHROME else trim, METAL)
	end
	if c.Room() >= 1 then
		diamond(c, "TailTip", c.At(1.38, 0.5, 0.1), 0.3, 0.08, c.Glow, NEON)
	end
	return top
end

local function jetStriker(c: Ctx): number
	local trim = c.Look.Trim
	local hull = c.Look.Body
	mechaBody(c, CHROME_DARK, v3(0.52, 0.3, 0.66), 0.8, 1.52)
	-- the pilot dome, the wrap visor, the tail fin
	T.ellipsoid(c.Model, "Dome", c.At(0, 2.45, 0.04), c.V(1.74, 1.2, 1.5), hull, METAL)
	box(c, "Visor", v3(0, 2.02, -0.675), v3(1.46, 0.5, 0.06), rgb(14, 40, 64), M.SmoothPlastic)
	eyes(c, 2.02, v3(0.32, 0.22, 0.04), 0.1, true)
	box(c, "VisorTrim", v3(0, 2.29, -0.69), v3(1.46, 0.05, 0.05), c.Glow, NEON)
	local top = 2.98
	if c.Room() >= 2 then
		T.tri(c.Model, "Fin", T.P(c, 0, 2.98, -0.3), T.P(c, 0, 3.5, 0.5), T.P(c, 0, 2.98, 0.62), 0.08 * c.S, CHROME, METAL, 2)
		top = 3.5
	end
	-- the jet pack: two thrusters, nozzles, flames
	if c.Room() >= 5 then
		box(c, "Pack", v3(0, 1.1, 0.56), v3(0.9, 0.8, 0.3), trim, METAL)
		for i, side in { -1, 1 } do
			disc(c, "Thruster" .. i, v3(side * 0.5, 0.98, 0.7), 0.84, 0.44, "Y", CHROME, METAL)
			disc(c, "Nozzle" .. i, v3(side * 0.5, 0.5, 0.7), 0.16, 0.52, "Y", DARK, METAL)
		end
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 2 then
			T.ellipsoid(c.Model, "Flame" .. i, c.At(side * 0.5, 0.14, 0.7), c.V(0.46, 0.66, 0.46), FLAME, NEON)
			T.ellipsoid(c.Model, "FlameCore" .. i, c.At(side * 0.5, -0.16, 0.7), c.V(0.24, 0.44, 0.24), FLAME_HOT, NEON)
		end
	end
	-- swept wing blades with neon leading edges and tip lights
	for i, side in { -1, 1 } do
		if c.Room() >= 4 then
			local root, tip, low = v3(side * 0.6, 1.5, 0.66), v3(side * 2.1, 1.75, 0.96), v3(side * 0.62, 0.84, 0.74)
			tri(c, "Wing" .. i, root, tip, low, 0.06, CHROME_DARK, METAL)
			bar(c, "WingEdge" .. i, root, tip, 0.06, 0.08, c.Glow, NEON)
			ball(c, "WingLight" .. i, tip, 0.16, if side < 0 then MAGENTA else CYAN, NEON)
		end
	end
	-- the orange flight scarf: the tail streams back and up over the left wing
	scarf(c, rgb(255, 140, 30), -1, 0.8, false)
	-- a missile under each wing: a white body, a glowing tip
	for i, side in { -1, 1 } do
		if c.Room() >= 2 then
			disc(c, "Missile" .. i, v3(side * 1.25, 1.1, 0.72), 0.62, 0.14, "Z", WHITE, METAL)
			ball(c, "MissileTip" .. i, v3(side * 1.25, 1.1, 0.38), 0.14, MAGENTA, NEON)
		end
	end
	-- boot jets in the hover gap
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			T.ellipsoid(c.Model, "BootFlame" .. i, c.At(x, -0.1, 0.02), c.V(0.3, 0.26, 0.3), c.Glow, NEON)
		end
	end
	-- the chest: an X harness, the round core, gold squadron wings with a neon star
	if c.Room() >= 2 then
		for i, side in { -1, 1 } do
			box(c, "Strap" .. i, v3(0, 1.0, -0.445), v3(0.14, 1.0, 0.03), CHROME_DARK, METAL, CFrame.Angles(0, 0, side * 0.62))
		end
	end
	roundFront(c, "Core", v3(0, 1.0, -0.47), 0.3, c.Glow)
	if c.Room() >= 3 then
		for i, side in { -1, 1 } do
			bar(c, "Squadron" .. i, v3(side * 0.08, 1.3, -0.47), v3(side * 0.4, 1.36, -0.47), 0.03, 0.08, GOLD, M.Foil)
		end
		diamond(c, "SquadStar", c.At(0, 1.3, -0.49), 0.13, 0.03, YELLOW, NEON)
	end
	-- arm blades
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			box(c, "Blade" .. i, v3(side * 1.01, 1.12, 0.02), v3(0.06, 0.62, 0.3), c.Glow, NEON, CFrame.Angles(0.35, 0, side * 0.1))
		end
	end
	-- side intakes and thruster rings
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			disc(c, "Intake" .. i, v3(side * 0.8, 2.0, 0.08), 0.12, 0.42, "X", CHROME, METAL)
		end
	end
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			disc(c, "ThrusterRing" .. i, v3(side * 0.5, 1.22, 0.7), 0.06, 0.48, "Y", c.Glow, NEON)
		end
	end
	local body = bodyPart(c)
	if body then
		T.embers(body, FLAME, 4)
	end
	return top
end

local function omegaMech(c: Ctx): number
	local trim = c.Look.Trim
	local glow = c.Glow
	-- huge layered shoulder armour (the shoulder parts re-dressed)
	for i, side in { -1, 1 } do
		T.redress(
			c,
			if i == 1 then "Boulder" else "Crystal",
			c.At(side * 0.94, 1.6, 0) * CFrame.Angles(0, 0, -side * 0.14),
			c.V(0.72, 0.42, 0.88),
			trim,
			METAL
		)
	end
	for _, name in { "Leg1", "Leg2" } do
		T.recolor(c, name, trim, M.DiamondPlate)
	end
	-- the left mech fist, the right forearm turned into the cannon housing
	T.redress(c, "Fist1", c.At(-0.9, 0.68, -0.05) * CFrame.Angles(0.2, -0.3, 0), c.V(0.62, 0.54, 0.58), trim, METAL)
	T.redress(c, "Fist2", c.At(0.9, 0.82, -0.18), c.V(0.52, 0.5, 0.66), trim, METAL)
	-- the closed face: visor, slit eyes, a chin plate, cheek guards
	box(c, "Visor", v3(0, 2.02, -0.675), v3(1.36, 0.42, 0.05), GLASS, M.SmoothPlastic)
	eyes(c, 2.02, v3(0.34, 0.12, 0.04), 0.2, false)
	box(c, "Chin", v3(0, 1.64, -0.68), v3(0.8, 0.3, 0.08), trim, METAL)
	-- the crown: a gold V-fin, a centre blade, a gem on the forehead plate
	box(c, "Forehead", v3(0, 2.46, -0.69), v3(0.52, 0.26, 0.1), trim, METAL)
	diamond(c, "CrownGem", c.At(0, 2.46, -0.755), 0.24, 0.05, glow, NEON)
	local top = 2.7
	if c.Room() >= 3 then
		for i, side in { -1, 1 } do
			bar(c, "Fin" .. i, v3(side * 0.1, 2.5, -0.74), v3(side * 0.88, 3.42, -0.72), 0.18, 0.07, GOLD, M.Foil)
		end
		bar(c, "FinMid", v3(0, 2.56, -0.74), v3(0, 3.16, -0.72), 0.12, 0.07, GOLD, M.Foil)
		top = 3.5
	end
	-- the royal cyber-cloak: black cloth, a magenta neon hem and edges, gem clasps
	cape(c, {
		Y0 = 1.52,
		Y1 = 0.1,
		Z0 = 0.47,
		Z1 = 0.68,
		W0 = 1.36,
		W1 = 2.8,
		Cloth = rgb(26, 20, 40),
		Trim = glow,
		Clasp = CYAN,
		ClaspMaterial = NEON,
		Sweep = -0.55,
		Lift = 0.12,
	})
	-- its high collar: two gold-edged plates standing behind the head
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			-- (one wedge: its slope runs from the outer top corner down to the neck)
			local frame = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -side), Vector3.yAxis, Vector3.new(side, 0, 0))
			K.wedge(c.Model, "Collar" .. i, c.At(side * 0.68, 2.28, 0.7) * frame, c.V(0.06, 1.5, 0.76), rgb(60, 36, 92), METAL)
		end
	end
	-- the giant reactor ring on the back, a hub and four cyan nodes
	local ringC = v3(0, 1.85, 0.9)
	if c.Room() >= 9 then
		top = math.max(top, ring(c, "ReactorRing", ringC, 1.5, 0.14, glow, NEON) + 0.1)
		disc(c, "ReactorHub", v3(0, 1.85, 0.86), 0.2, 0.6, "Z", CHROME, METAL)
	end
	for i, a in { 0, PI / 2, PI, 3 * PI / 2 } do
		if c.Room() < 1 then
			break
		end
		ball(c, "RingNode" .. i, ringC + v3(math.sin(a) * 1.5, math.cos(a) * 1.5, 0), 0.28, CYAN, NEON)
	end
	-- the arm cannon
	if c.Room() >= 4 then
		disc(c, "Cannon", v3(0.9, 0.82, -0.66), 0.6, 0.44, "Z", CHROME, METAL)
		disc(c, "CannonRing", v3(0.9, 0.82, -0.84), 0.1, 0.52, "Z", trim, METAL)
		disc(c, "Muzzle", v3(0.9, 0.82, -0.97), 0.06, 0.3, "Z", glow, NEON)
		box(c, "CannonCell", v3(0.9, 1.08, -0.3), v3(0.12, 0.04, 0.52), CYAN, NEON)
	end
	-- the energy sword in the mech fist: a hilt, a gold guard, a long neon blade
	if c.Room() >= 3 then
		local hand = v3(-0.92, 0.66, -0.36)
		bar(c, "SwordHilt", hand + v3(0, -0.24, 0.1), hand + v3(0, 0.12, -0.06), 0.1, 0.1, DARK, METAL)
		bar(c, "SwordGuard", hand + v3(-0.2, 0.14, -0.08), hand + v3(0.2, 0.14, -0.08), 0.1, 0.1, GOLD, M.Foil)
		bar(c, "SwordBlade", hand + v3(0, 0.18, -0.09), hand + v3(-0.02, 1.95, -0.84), 0.2, 0.06, CYAN, NEON)
	end
	-- layered shoulder plates with neon stripes and gold fins
	for i, side in { -1, 1 } do
		if c.Room() >= 3 then
			local rot = CFrame.Angles(0, 0, -side * 0.14)
			box(c, "PadTop" .. i, v3(side * 0.98, 1.85, 0), v3(0.62, 0.14, 0.78), CHROME, METAL, rot)
			box(c, "PadStripe" .. i, v3(side * 0.94, 1.6, -0.45), v3(0.54, 0.08, 0.03), glow, NEON, rot)
			box(c, "PadFin" .. i, v3(side * 1.12, 2.06, 0.05), v3(0.08, 0.34, 0.56), GOLD, M.Foil, rot)
		end
	end
	-- the chest reactor
	if c.Room() >= 2 then
		box(c, "ChestPlate", v3(0, 1.08, -0.44), v3(0.94, 0.7, 0.04), trim, METAL)
		disc(c, "ReactorHousing", v3(0, 1.1, -0.47), 0.04, 0.5, "Z", GOLD, M.Foil)
	end
	roundFront(c, "Core", v3(0, 1.1, -0.5), 0.34, glow)
	-- cheek guards
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			box(c, "Cheek" .. i, v3(side * 0.78, 1.96, -0.16), v3(0.1, 0.8, 0.8), trim, METAL)
		end
	end
	-- the waist armour, knees, heavy feet and boot jets
	if c.Room() >= 3 then
		box(c, "Belt", v3(0, 0.56, 0), v3(1.26, 0.14, 0.9), trim, METAL)
		for i, x in { -0.32, 0.32 } do
			box(c, "Tasset" .. i, v3(x, 0.4, -0.46), v3(0.34, 0.3, 0.05), CHROME, METAL)
		end
	end
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 2 then
			box(c, "Foot" .. i, v3(x, 0.08, -0.1), v3(0.5, 0.16, 0.72), trim, METAL)
			T.ellipsoid(c.Model, "BootFlame" .. i, c.At(x, -0.12, -0.05), c.V(0.3, 0.26, 0.3), CYAN, NEON)
		end
	end
	-- the collar's neon edges
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			bar(c, "CollarEdge" .. i, v3(side * 0.3, 1.53, 0.66), v3(side * 1.06, 3.03, 0.66), 0.08, 0.08, glow, NEON)
		end
	end
	local body = bodyPart(c)
	if body then
		T.embers(body, glow, 5)
		T.light(body, glow, 8, 1.2)
	end
	return top
end

function MechaNeon.accessories(kit: Kit, tools: Tools): { [string]: (Ctx) -> number }
	K, T = kit, tools
	return {
		NeonVisor = boltBot,
		Headset = beatBot,
		MechaCrest = laserRanger,
		Rockets = rocketRex,
		JetPack = jetStriker,
		OmegaFrame = omegaMech,
	}
end

---------------------------------------------------------------- the shard

--[[
	The MECHA EGG shard (units: studs, the shard's center at s.Center, the
	front -Z): a sphere below the waist and a tall ellipsoid above it (the
	halves of the opening) in glossy chrome; a neon band at the waist, neon
	circuit lines with glowing nodes, a visor window with cute eyes, ear
	bolts, antennas, a little V-fin crown, and a jet ring it hovers on.
]]
function MechaNeon.shard(kit: Kit, tools: Tools, s: Shard)
	K, T = kit, tools
	local C = s.Center
	local r = 1.25
	local topCenter = 0.4 * r
	local cyan = s.Glow
	local function at(x: number, y: number, z: number): CFrame
		return C * CFrame.new(x, y, z)
	end
	local function P(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	-- the shell's radius at height y (lower sphere / upper ellipsoid)
	local function radiusAt(y: number): number
		if y <= 0 then
			return math.sqrt(math.max(r * r - y * y, 0))
		end
		local yy = (y - topCenter) / (1.4 * r)
		return r * math.sqrt(math.max(1 - yy * yy, 0))
	end
	-- a frame on the shell at height y, angle a round it (0 = front), facing out
	local function onShell(y: number, a: number, out: number?): CFrame
		local rr = radiusAt(y) + (out or 0)
		return at(math.sin(a) * rr, y, -math.cos(a) * rr) * CFrame.Angles(0, -a, 0)
	end
	local chrome = rgb(200, 206, 226)
	local chromeLow = rgb(150, 160, 190)
	local purple = rgb(168, 40, 200)

	-- Bottom: the round lower shell, the neon band, the cracks
	T.ellipsoid(s.Bottom, "Shell", at(0, 0, 0), Vector3.new(2 * r, 2 * r, 2 * r), purple, METAL)
	K.upright(s.Bottom, "Band", at(0, 0.02, 0), 0.16, 2 * r + 0.06, cyan, NEON)
	for i, k in { { -0.55, -0.35, 0.5 }, { 0.42, -0.62, -0.6 }, { 0.06, -0.9, 0.35 } } do
		local a = math.asin(math.clamp(k[1] / r, -1, 1))
		K.part(s.Bottom, "Crack" .. i, onShell(k[2], a, 0.02) * CFrame.Angles(0, 0, k[3]), Vector3.new(0.09, 0.62, 0.04), WHITE, NEON)
	end
	-- the hover jet ring under the egg: a dark disc, a magenta glow ring, three struts
	K.upright(s.Bottom, "JetRing", at(0, -r - 0.05, 0), 0.18, 1.7, DARK, METAL)
	K.upright(s.Bottom, "JetGlow", at(0, -r - 0.05, 0), 0.08, 1.86, MAGENTA, NEON)
	K.upright(s.Bottom, "JetCore", at(0, -r - 0.22, 0), 0.08, 0.7, FLAME_HOT, NEON)
	-- a row of chrome bolts under the band
	for i = 1, 4 do
		if s.Room() < 1 then
			break
		end
		local a = (i - 2.5) * 0.55
		K.part(s.Bottom, "Bolt" .. i, onShell(-0.28, a, -0.02), Vector3.new(0.16, 0.16, 0.16), chrome, METAL, BALL)
	end
	-- magenta circuit lines on the lower shell
	for i, k in { { -0.9, -0.55, 0.25 }, { 0.9, -0.55, -0.25 } } do
		if s.Room() < 1 then
			break
		end
		K.part(s.Bottom, "LowCircuit" .. i, onShell(k[2], k[1], 0.0) * CFrame.Angles(0, 0, k[3]), Vector3.new(0.07, 0.5, 0.05), cyan, NEON)
	end

	-- Top: the tall glossy upper shell
	T.ellipsoid(s.Top, "Shell", at(0, topCenter, 0), Vector3.new(2 * r, 2.8 * r, 2 * r), chrome, METAL)
	-- the visor window: a dark screen with a cyan frame and two cute eyes
	local vy = 0.72
	local vz = -radiusAt(vy)
	T.ellipsoid(s.Top, "VisorFrame", at(0, vy, vz + 0.12), Vector3.new(1.62, 0.9, 0.3), cyan, NEON)
	T.ellipsoid(s.Top, "Visor", at(0, vy, vz + 0.08), Vector3.new(1.48, 0.76, 0.3), GLASS, M.SmoothPlastic)
	for i, x in { -0.32, 0.32 } do
		T.ellipsoid(s.Top, "Eye" .. i, at(x, vy + 0.02, vz - 0.07), Vector3.new(0.24, 0.32, 0.06), cyan, NEON)
		if s.Room() >= 1 then
			K.part(s.Top, "Shine" .. i, at(x - 0.05, vy + 0.1, vz - 0.1), Vector3.new(0.07, 0.07, 0.04), WHITE, NEON)
		end
	end
	if s.Room() >= 1 then
		K.part(s.Top, "Smile", at(0, vy - 0.2, vz - 0.06), Vector3.new(0.22, 0.05, 0.04), MAGENTA, NEON)
	end
	-- ear bolts with neon rings
	for i, side in { -1, 1 } do
		if s.Room() >= 2 then
			local y = 0.55
			local x = side * radiusAt(y)
			K.part(s.Top, "Ear" .. i, at(x, y, 0), Vector3.new(0.24, 0.62, 0.62), DARK, METAL, CYL)
			K.part(s.Top, "EarLight" .. i, at(x + side * 0.12, y, 0), Vector3.new(0.06, 0.4, 0.4), MAGENTA, NEON, CYL)
		end
	end
	-- neon circuit lines climbing the shell, a glowing node at each end
	for i, k in { { -0.62, 1.15, 1.8 }, { 0.62, 1.15, 1.8 }, { -1.5, 0.35, 1.4 }, { 1.5, 0.35, 1.4 } } do
		if s.Room() < 2 then
			break
		end
		local a, y0, y1 = k[1], k[2], k[3]
		local p0 = onShell(y0, a, -0.01).Position
		local p1 = onShell(y1, a * 0.7, -0.01).Position
		T.seg(s.Top, "Circuit" .. i, p0, p1, 0.07, 0.07, if i <= 2 then cyan else MAGENTA, NEON)
		K.part(s.Top, "Node" .. i, onShell(y1, a * 0.7, -0.02), Vector3.new(0.16, 0.16, 0.16), if i <= 2 then MAGENTA else cyan, NEON, BALL)
	end
	-- the little V-fin crown and its gem
	local tipY = topCenter + 1.4 * r
	if s.Room() >= 3 then
		for i, side in { -1, 1 } do
			T.seg(s.Top, "Fin" .. i, P(side * 0.08, tipY - 0.32, -0.46), P(side * 0.62, tipY + 0.22, -0.5), 0.2, 0.08, GOLD, M.Foil)
		end
		K.part(s.Top, "Gem", at(0, tipY - 0.3, -0.52) * CFrame.Angles(0, 0, PI / 4), Vector3.new(0.24, 0.24, 0.08), MAGENTA, NEON)
	end
	-- two antennas with blinking balls
	for i, side in { -1, 1 } do
		if s.Room() >= 2 then
			local base = P(side * 0.45, tipY - 0.3, 0.2)
			local tip = P(side * 0.75, tipY + 0.45, 0.35)
			T.seg(s.Top, "Antenna" .. i, base, tip, 0.07, 0.07, chromeLow, METAL)
			K.part(s.Top, "AntennaBall" .. i, CFrame.new(tip), Vector3.new(0.24, 0.24, 0.24), if i == 1 then cyan else MAGENTA, NEON, BALL)
		end
	end
	-- the tilted neon orbit ring round the egg (dipping in front), two cyan
	-- satellites riding it
	local orbit = C * CFrame.new(0, -0.15, 0) * CFrame.Angles(0.5, 0, 0)
	local rr = 1.78
	local n = 8
	local function onOrbit(a: number): Vector3
		return (orbit * CFrame.new(math.sin(a) * rr, 0, -math.cos(a) * rr)).Position
	end
	for i = 1, n do
		if s.Room() < 1 then
			break
		end
		local a0, a1 = (i - 1) * 2 * PI / n, i * 2 * PI / n
		local a, b = onOrbit(a0), onOrbit(a1)
		local dir = (b - a).Unit
		T.seg(s.Bottom, "Orbit" .. i, a - dir * 0.05, b + dir * 0.05, 0.1, 0.1, MAGENTA, NEON)
	end
	for i, a in { -0.9, 2.3 } do
		if s.Room() >= 1 then
			K.part(s.Bottom, "Satellite" .. i, CFrame.new(onOrbit(a)), Vector3.new(0.26, 0.26, 0.26), cyan, NEON, BALL)
		end
	end
	-- twinkling stars floating round the egg (four-point: two thin diamonds)
	for i, k in { { -1.55, 1.55, -0.3, 0.36 }, { 1.6, 0.9, -0.4, 0.26 } } do
		if s.Room() >= 1 then
			K.part(s.Top, "Star" .. i, at(k[1], k[2], k[3]) * CFrame.Angles(0, 0, PI / 4), Vector3.new(k[4], k[4], 0.05), WHITE, NEON)
		end
	end
	local band = s.Bottom:FindFirstChild("Band")
	if band and band:IsA("BasePart") then
		T.embers(band, cyan, 5, 0.22)
	end
end

return MechaNeon
