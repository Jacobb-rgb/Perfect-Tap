--[[
	MECHA NEON (upcoming limited edition): the costumes of the set's 6 chrome
	robot golems and the set's shard (GolemGearLimited explains the contract
	and the tools).

	  NeonVisor   Bolt Bot (Rare): a big dark visor with oval neon eyes, ear
	              bolts with glowing caps, an antenna with a blinking ball, a
	              yellow lightning bolt on the shoulder, a chest gauge with LED
	              buttons, neon cuffs and a wind-up key on its back
	  Headset     Beat Bot (Rare): huge DJ headphones with neon rings, a boom
	              mic, a face screen with an equalizer mouth, a speaker chest,
	              light-up sneakers and a vinyl record in its hand
	  MechaCrest  Laser Ranger (Epic): a hero helmet with a gold V-fin crest,
	              cheek guards, a scanner monocle, layered shoulder pads, a
	              chest chevron and a laser rifle
	  Rockets     Rocket Rex (Epic): a robot dino: a snout with chrome teeth
	              and a glowing maw, chrome back plates, shoulder rocket pods
	              (four rockets), claws and a mechanical tail
	  JetPack     Jet Striker (Legendary): a pilot dome helmet with a wrap
	              visor and a tail fin, a jet pack with two flaming thrusters,
	              swept wing blades with neon edges, arm blades, boot jets,
	              embers
	  OmegaFrame  Omega Mech (Mythic): a heavy mech frame: a gold crown V-fin,
	              a closed face plate, huge layered shoulder armour, an arm
	              cannon, a mech fist, a glowing chest reactor, a giant neon
	              reactor ring on its back, boot jets, embers and its own light

	The shard: a MECHA EGG of glossy chrome hovering on a jet ring, neon
	circuit lines, a visor window with cute eyes, ear bolts, antennas and a
	little V-fin crown.
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
	-- the lightning bolt on the right shoulder
	if c.Room() >= 3 then
		local p1, p2, p3, p4 = v3(1.3, 2.5, -0.12), v3(1.06, 2.08, -0.12), v3(1.34, 2.04, -0.12), v3(1.08, 1.58, -0.12)
		bar(c, "Bolt1", p1, p2, 0.2, 0.1, YELLOW, NEON)
		bar(c, "Bolt2", p2 + v3(-0.04, 0, 0), p3 + v3(0.04, 0, 0), 0.14, 0.1, YELLOW, NEON)
		bar(c, "Bolt3", p3, p4, 0.2, 0.1, YELLOW, NEON)
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
	-- chrome bolts on the left pad
	for i, x in { -0.66, -0.94 } do
		if c.Room() >= 1 then
			ball(c, "PadBolt" .. i, v3(x, 1.52, -0.32), 0.12, CHROME, METAL)
		end
	end
	-- neon cuffs
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			box(c, "Cuff" .. i, v3(side * 0.81, 0.88, 0), v3(0.44, 0.08, 0.54), c.Glow, NEON, CFrame.Angles(0, 0, side * 0.1))
		end
	end
	-- the wind-up key on the back
	if c.Room() >= 3 then
		disc(c, "KeyShaft", v3(0, 1.04, 0.54), 0.24, 0.1, "Z", CHROME, METAL)
		for i, x in { -0.17, 0.17 } do
			ball(c, "KeyLobe" .. i, v3(x, 1.04, 0.7), 0.3, YELLOW, METAL)
		end
	end
	-- chrome boot toes
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			box(c, "Toe" .. i, v3(x, 0.1, -0.3), v3(0.46, 0.2, 0.2), CHROME, METAL)
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
	-- the boom mic from the left cup
	if c.Room() >= 2 then
		bar(c, "MicArm", v3(-0.94, 1.94, -0.3), v3(-0.56, 1.66, -0.78), 0.06, 0.06, DARK, METAL)
		ball(c, "Mic", v3(-0.54, 1.66, -0.8), 0.18, DARK, M.Fabric)
	end
	-- the speaker chest
	if c.Room() >= 3 then
		box(c, "SpeakerBox", v3(0, 1.0, -0.44), v3(0.9, 0.8, 0.05), trim, METAL)
		disc(c, "SpeakerRing", v3(0, 0.98, -0.47), 0.03, 0.64, "Z", c.Glow, NEON)
		disc(c, "SpeakerCone", v3(0, 0.98, -0.49), 0.03, 0.52, "Z", DARK, M.SmoothPlastic)
	end
	roundFront(c, "Core", v3(0, 0.98, -0.51), 0.2, CYAN)
	for i, x in { -0.32, 0.32 } do
		if c.Room() >= 1 then
			disc(c, "Tweeter" .. i, v3(x, 1.3, -0.47), 0.03, 0.1, "Z", CYAN, NEON)
		end
	end
	-- the vinyl record in the right hand
	if c.Room() >= 2 then
		disc(c, "Vinyl", v3(0.98, 0.98, -0.34), 0.04, 0.82, "Z", rgb(20, 20, 26), M.SmoothPlastic)
		disc(c, "Label", v3(0.98, 0.98, -0.365), 0.03, 0.3, "Z", c.Glow, NEON)
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
	-- the chest armour and its chevron
	if c.Room() >= 3 then
		box(c, "ChestPlate", v3(0, 1.1, -0.44), v3(0.9, 0.6, 0.04), trim, METAL)
		for i, side in { -1, 1 } do
			box(c, "Chevron" .. i, v3(side * 0.13, 0.84, -0.465), v3(0.3, 0.07, 0.03), c.Glow, NEON, CFrame.Angles(0, 0, side * 0.55))
		end
	end
	roundFront(c, "Core", v3(0, 1.14, -0.47), 0.26, c.Glow)
	-- the belt and buckle, knee pads
	if c.Room() >= 2 then
		box(c, "Belt", v3(0, 0.56, 0), v3(1.24, 0.12, 0.89), DARK, METAL)
		box(c, "Buckle", v3(0, 0.56, -0.45), v3(0.22, 0.14, 0.03), c.Glow, NEON)
	end
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			box(c, "Knee" .. i, v3(x, 0.3, -0.27), v3(0.36, 0.2, 0.06), CHROME, METAL)
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
	local top = 2.7
	for i, k in { { 2.82, -0.2, 0.36 }, { 2.86, 0.18, 0.44 }, { 2.66, 0.56, 0.34 }, { 1.62, 0.5, 0.3 } } do
		if c.Room() < 1 then
			break
		end
		diamond(c, "Plate" .. i, c.At(0, k[1], k[2]) * CFrame.Angles(0, PI / 2, 0), k[3], 0.08, CHROME, METAL)
		top = math.max(top, k[1] + k[3] * 0.71)
	end
	-- the chest plate and hazard stripes
	if c.Room() >= 3 then
		box(c, "ChestPlate", v3(0, 1.0, -0.44), v3(0.86, 0.66, 0.04), trim, METAL)
		for i, x in { -0.24, 0.24 } do
			box(c, "Stripe" .. i, v3(x, 0.96, -0.465), v3(0.1, 0.5, 0.03), c.Glow, NEON, CFrame.Angles(0, 0, 0.5))
		end
	end
	roundFront(c, "Core", v3(0, 1.0, -0.475), 0.24, rgb(255, 80, 60))
	-- claws on the fists
	for i, side in { -1, 1 } do
		for j, dx in { -0.12, 0.12 } do
			if c.Room() >= 1 then
				box(c, `Claw{i}_{j}`, v3(side * 0.86 + dx, 0.56, -0.32), v3(0.1, 0.1, 0.26), WHITE, METAL, CFrame.Angles(0.5, 0, 0))
			end
		end
	end
	-- the mechanical tail, curling out to the right, a glowing tip
	local tail = { v3(0.2, 0.62, 0.4), v3(0.62, 0.42, 0.72), v3(1.08, 0.3, 0.56), v3(1.34, 0.36, 0.14) }
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
			disc(c, "Thruster" .. i, v3(side * 0.5, 1.06, 0.7), 1.0, 0.44, "Y", CHROME, METAL)
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
			T.tri(
				c.Model,
				"Wing" .. i,
				T.P(c, root.X, root.Y, root.Z),
				T.P(c, tip.X, tip.Y, tip.Z),
				T.P(c, low.X, low.Y, low.Z),
				0.06 * c.S,
				CHROME_DARK,
				METAL,
				2
			)
			bar(c, "WingEdge" .. i, root, tip, 0.06, 0.08, c.Glow, NEON)
			ball(c, "WingLight" .. i, tip, 0.16, if side < 0 then MAGENTA else CYAN, NEON)
		end
	end
	-- boot jets in the hover gap
	for i, x in { -0.3, 0.3 } do
		if c.Room() >= 1 then
			T.ellipsoid(c.Model, "BootFlame" .. i, c.At(x, -0.1, 0.02), c.V(0.3, 0.26, 0.3), c.Glow, NEON)
		end
	end
	-- the chest: an X harness, the round core, a collar
	if c.Room() >= 3 then
		for i, side in { -1, 1 } do
			box(c, "Strap" .. i, v3(0, 1.0, -0.445), v3(0.14, 1.0, 0.03), CHROME_DARK, METAL, CFrame.Angles(0, 0, side * 0.62))
		end
		box(c, "Collar", v3(0, 1.48, 0), v3(1.0, 0.12, 0.8), CHROME, METAL)
	end
	roundFront(c, "Core", v3(0, 1.0, -0.47), 0.3, c.Glow)
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
			disc(c, "ThrusterRing" .. i, v3(side * 0.5, 1.3, 0.7), 0.06, 0.48, "Y", c.Glow, NEON)
		end
	end
	if c.Room() >= 1 then
		box(c, "Grille", v3(0, 1.64, -0.665), v3(0.5, 0.12, 0.03), DARK, METAL)
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
	-- the giant reactor ring on the back, a hub and four cyan nodes
	local ringC = v3(0, 1.85, 0.78)
	if c.Room() >= 9 then
		top = math.max(top, ring(c, "ReactorRing", ringC, 1.5, 0.14, glow, NEON) + 0.1)
		disc(c, "ReactorHub", v3(0, 1.85, 0.62), 0.24, 0.6, "Z", CHROME, METAL)
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
	-- mech knuckles, cheek guards
	if c.Room() >= 1 then
		box(c, "Knuckles", v3(-0.94, 0.8, -0.36), v3(0.5, 0.08, 0.04), glow, NEON, CFrame.Angles(0.2, -0.3, 0))
	end
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
	-- swept-back horn antennae
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			bar(c, "Horn" .. i, v3(side * 0.62, 2.56, 0.2), v3(side * 0.9, 3.0, 0.72), 0.1, 0.1, CHROME, METAL)
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
	local chrome = rgb(226, 232, 246)
	local chromeLow = rgb(150, 160, 190)
	local purple = rgb(124, 58, 220)

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
	local band = s.Bottom:FindFirstChild("Band")
	if band and band:IsA("BasePart") then
		T.embers(band, cyan, 5, 0.22)
	end
end

return MechaNeon
