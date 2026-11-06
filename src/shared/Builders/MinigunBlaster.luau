--[[
	The round blasters (owner 2026-11-06, his "ALL BLASTERS" picture and script,
	after his "Mining Blasters" minigun picture of 2026-10-31: "celé kulaté",
	"extrémně cool, ale hodně clean"): every level and STAR blaster has the same
	body, its own colours, and more crystals with the level. From the muzzle back:

	  muzzle    a glowing hexagonal crystal (three crossed bars) on a dark neck
	            (the Singularity Rail: a glowing ring round a dark bore)
	  flange    a thick dark round flange, glowing dots round its rim
	  bands     the wide glowing bands on a dark round section
	  drum      the big dark drum with metal edges and small glowing lights;
	            the crystals grow out of it, top, bottom and sides
	  cage      six thin barrels round a glowing core (rainbow bands from level
	            RainbowCoreFrom) between dark clamps, with two glowing hoops
	  back      a dark round back with a band of six rainbow rings
	  grip      a round grip under the cage, a ball at its end, at the hand

	A lightning bolt glows on each side of the drum (the owner: "přidej duhové
	čáry ... nějaké blesky", kept 2026-11-06). Everything is round but the
	crystals, the hexagon and the bolts, which are cut like his picture's. The colours are Palettes (his, by level and STAR blaster) for a gun
	in its case's ore; an older save's gun in another ore keeps that ore's colours
	(the skin, KenneyBlaster.skin, made vivid).

	The spin ("když minigun střílí, ať se točí ten kotouč"): the barrels, the rim
	dots and the drum's lights are listed in the anchors (Spin) with their axis
	(SpinAxis): BlasterBuilder hangs them on a Motor6D the client turns while the
	gun fires (Effects/BarrelSpin).

	Every level has the same shape, longer with the level (StartLength to
	EndLength studs). Frame: the barrel along -Z, +Y up, the hand at the origin
	(on top of the grip). Parts through `part` (BlasterBuilder welds them), at
	most MaxParts; no lights. Pure: Instance creation only.
]]

local BlasterData = require(script.Parent.Parent.Config.BlasterData)
local KenneyBlaster = require(script.Parent.KenneyBlaster)

local MinigunBlaster = {}

MinigunBlaster.MaxParts = 96 -- per gun (phones: every player holds one)
MinigunBlaster.StartLength = 2.6 -- level 1's length (studs): a small one, it grows with the level
MinigunBlaster.EndLength = 5.6 -- level 10's length (the STAR blasters too)
MinigunBlaster.RainbowCoreFrom = 5 -- the core glows in rainbow bands from this level (the STAR blasters too)

local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local MID = Color3.fromRGB(62, 67, 76)
local DARK = Color3.fromRGB(24, 27, 34)
local DARKER = Color3.fromRGB(10, 12, 17)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- the rainbow (red .. violet), a little deep so Neon shows each colour
local RAINBOW = {
	rgb(225, 28, 58),
	rgb(235, 105, 10),
	rgb(225, 190, 0),
	rgb(25, 190, 75),
	rgb(25, 115, 235),
	rgb(125, 45, 225),
}

export type Palette = {
	Color: Color3, -- the wide bands, the hoops
	Accent: Color3, -- the rim dots, the drum's lights, the core
	Crystal: Color3,
}

-- the owner's colours: levels 1-10, then the STAR blasters (KenneyBlaster's models 11-15)
MinigunBlaster.Palettes = {
	{ Color = rgb(255, 85, 10), Accent = rgb(255, 130, 30), Crystal = rgb(255, 95, 20) }, -- Rusty
	{ Color = rgb(255, 105, 20), Accent = rgb(255, 160, 50), Crystal = rgb(255, 125, 35) }, -- Copper Scrap
	{ Color = rgb(175, 70, 255), Accent = rgb(220, 100, 255), Crystal = rgb(180, 80, 255) }, -- Cobalt Spark
	{ Color = rgb(255, 214, 150), Accent = rgb(255, 165, 60), Crystal = rgb(255, 240, 190) }, -- Emberite Ember
	{ Color = rgb(255, 210, 50), Accent = rgb(255, 240, 100), Crystal = rgb(255, 220, 70) }, -- Gold Forgefire
	{ Color = rgb(70, 160, 255), Accent = rgb(100, 190, 255), Crystal = rgb(130, 210, 255) }, -- Sapphire Sunlance
	{ Color = rgb(235, 80, 255), Accent = rgb(220, 80, 255), Crystal = rgb(255, 100, 255) }, -- Amethyst Stormlance
	{ Color = rgb(140, 75, 255), Accent = rgb(150, 80, 255), Crystal = rgb(200, 100, 255) }, -- Obsidian Starlance
	{ Color = rgb(255, 150, 20), Accent = rgb(255, 215, 80), Crystal = rgb(255, 200, 70) }, -- Royal Aurum Sunlance
	{ Color = rgb(255, 80, 170), Accent = rgb(255, 150, 220), Crystal = rgb(255, 110, 180) }, -- Heartstone Heartlance
	{ Color = rgb(70, 160, 255), Accent = rgb(235, 240, 255), Crystal = rgb(170, 220, 255) }, -- Comet Launcher
	{ Color = rgb(255, 90, 210), Accent = rgb(175, 70, 255), Crystal = rgb(255, 120, 255) }, -- Nebula Twin
	{ Color = rgb(60, 240, 255), Accent = rgb(235, 240, 255), Crystal = rgb(100, 255, 255) }, -- Pulsar Rifle
	{ Color = rgb(255, 210, 50), Accent = rgb(255, 125, 25), Crystal = rgb(255, 230, 100) }, -- Supernova Gatling
	{ Color = rgb(175, 70, 255), Accent = rgb(255, 90, 190), Crystal = rgb(190, 100, 255) }, -- Singularity Rail
} :: { Palette }
MinigunBlaster.RingMuzzle = 15 -- this model's muzzle is a glowing ring round a dark bore (the Singularity Rail)

-- the design: a gun 10 units long (z: the back at +4, the muzzle at -6), the hand on the grip
local DESIGN_LENGTH = 10
local HAND_Z, HAND_Y = 2.3, -0.15
local AXIS_Y = 0.9 -- the gun's axis
local BARREL_R = 0.62 -- the six barrels' circle
local FRONT = -6.05

-- where the crystals grow (design units): on the drum, each a base and the way it points
local CLUSTERS = {
	{ 0, AXIS_Y + 1.15, -1.75, 0, 1, -0.2 }, -- on top, the front of the drum
	{ 0, AXIS_Y - 1.15, -1.5, 0, -1, 0.15 }, -- underneath
	{ 0, AXIS_Y + 1.15, -0.95, 0, 1, 0.5 }, -- on top, the back of the drum
	{ 1.05, AXIS_Y + 0.65, -1.35, 1, 0.6, -0.1 }, -- the right side, high (the bolt is below it)
	{ -1.05, AXIS_Y + 0.65, -1.35, -1, 0.6, -0.1 }, -- the left side
}
-- the crystals in the order they appear with the level: { cluster, its n-th crystal (1 the biggest,
-- 2 and 3 fanned out along the gun and shorter) }
local CRYSTAL_ORDER = {
	{ 1, 1 },
	{ 2, 1 },
	{ 3, 1 },
	{ 1, 2 },
	{ 2, 2 },
	{ 4, 1 },
	{ 5, 1 },
	{ 1, 3 },
	{ 3, 2 },
	{ 2, 3 },
	{ 4, 2 },
	{ 5, 2 },
}

-- A glow: very bright colours are pulled down so Neon shows its colour, not white.
local function tame(c: Color3): Color3
	local luma = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return c:Lerp(BLACK, math.max(0, luma - 0.55) * 0.9)
end

-- A glow at one even brightness, so every gun glows alike (bright colours bloom into white, dark ones
-- hardly glow), more saturated (pale ones stay pale: the Emberite's cream).
local GLOW_LUMA = 0.56
local function deep(c: Color3): Color3
	local h, sat = c:ToHSV()
	local full = Color3.fromHSV(h, if sat < 0.5 then sat else sat + (1 - sat) * 0.5, 1)
	local luma = 0.299 * full.R + 0.587 * full.G + 0.114 * full.B
	return Color3.fromHSV(h, if sat < 0.5 then sat else sat + (1 - sat) * 0.5, math.min(1, GLOW_LUMA / luma))
end

-- A vivid glow in the skin's own hue (an older save's gun in another ore); near-greys stay as they are.
local function vivid(c: Color3, saturation: number): Color3
	local h, sat, v = c:ToHSV()
	if sat < 0.08 then
		return c
	end
	return tame(Color3.fromHSV(h, math.max(sat, saturation), math.clamp(v, 0.78, 0.9)))
end

-- A level's scale: studs per design unit (the gun is StartLength .. EndLength long).
function MinigunBlaster.scale(level: number): number
	local t = (math.clamp(level, 1, 10) - 1) / 9
	return (MinigunBlaster.StartLength + (MinigunBlaster.EndLength - MinigunBlaster.StartLength) * t) / DESIGN_LENGTH
end

-- How many crystals a level grows (2 at level 1 ... 12 at level 10; the STAR blasters all 12).
function MinigunBlaster.crystals(level: number): number
	local lv = math.clamp(math.floor(level), 1, 10)
	return if lv >= 10 then 12 else lv + 1
end

-- A gun's colours: the owner's for a level in its case's ore and for a STAR blaster, else the ore's.
function MinigunBlaster.palette(level: number, oreId: string, skin: KenneyBlaster.Skin): Palette
	local own = MinigunBlaster.Palettes[level]
	if own and (level > BlasterData.MaxLevel or oreId == BlasterData.vaultOre(level)) then
		return { Color = deep(own.Color), Accent = deep(own.Accent), Crystal = deep(own.Crystal) }
	end
	return { Color = vivid(skin.Rim:Lerp(skin.Glow, 0.25), 0.8), Accent = vivid(skin.Glow, 0.7), Crystal = vivid(skin.Shard, 0.75) }
end

--[[
	Builds a level's gun with `part` (level 11-15: a STAR blaster) and returns the
	anchors (KenneyBlaster.Anchors: the hand, the muzzle, the top over the body,
	the barrel's line, and what spins about which axis).
]]
function MinigunBlaster.parts(level: number, oreId: string, skin: KenneyBlaster.Skin, part: KenneyBlaster.PartFn): KenneyBlaster.Anchors
	local S = MinigunBlaster.scale(level)
	local made = 0
	local spin: { BasePart } = {} -- the barrels, the rim dots and the drum's lights
	local colors = MinigunBlaster.palette(level, oreId, skin)
	local function at(x: number, y: number, z: number): Vector3
		return Vector3.new(x * S, (y - HAND_Y) * S, (z - HAND_Z) * S)
	end
	local function piece(
		name: string,
		cf: CFrame,
		size: Vector3,
		color: Color3,
		material: Enum.Material?,
		shape: Enum.PartType?,
		className: string?
	): BasePart?
		if made >= MinigunBlaster.MaxParts then
			return nil
		end
		made += 1
		local p = part(name, cf, size, color, material or PLASTIC, className)
		if shape and typeof(p) == "Instance" and p:IsA("Part") then
			p.Shape = shape
		end
		return p
	end
	-- a cylinder along `axis` (a Part's cylinder runs along its X axis)
	local function cylinder(
		name: string,
		center: Vector3,
		axis: Vector3,
		length: number,
		d: number,
		color: Color3,
		material: Enum.Material?
	)
		local hint = if math.abs(axis.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
		local up = (hint - axis * hint:Dot(axis)).Unit
		return piece(
			name,
			CFrame.fromMatrix(center, axis, up),
			Vector3.new(length * S, d * S, d * S),
			color,
			material,
			Enum.PartType.Cylinder
		)
	end
	-- along the gun, on its axis, from z0 to z1
	local function round(name: string, z0: number, z1: number, d: number, color: Color3, material: Enum.Material?)
		return cylinder(name, at(0, AXIS_Y, (z0 + z1) / 2), Vector3.zAxis, math.abs(z1 - z0), d, color, material)
	end
	local function ball(name: string, x: number, y: number, z: number, d: number, color: Color3, material: Enum.Material?)
		return piece(name, CFrame.new(at(x, y, z)), Vector3.new(d, d, d) * S, color, material, Enum.PartType.Ball)
	end
	local function spinning(p: BasePart?)
		if p then
			table.insert(spin, p)
		end
	end

	-- the muzzle
	if level == MinigunBlaster.RingMuzzle then
		round("MuzzleGlow", FRONT, FRONT + 0.85, 1.2, colors.Color, NEON)
		round("Bore", FRONT - 0.01, FRONT + 0.6, 0.72, DARKER)
	else
		-- a hexagonal crystal: three crossed bars
		local glow = colors.Color:Lerp(WHITE, 0.2)
		for i = 0, 2 do
			piece(
				"MuzzleGlow",
				CFrame.new(at(0, AXIS_Y, FRONT + 0.55)) * CFrame.Angles(0, 0, i * math.pi / 3),
				Vector3.new(1.2, 0.69, 1.1) * S,
				glow,
				NEON
			)
		end
	end
	round("Body", -5.3, -4.9, 1.2, DARKER)
	-- the flange and its rim dots
	round("Body", -4.95, -4.4, 2.55, DARK)
	round("Body", -4.4, -4.2, 2.15, DARKER)
	for i = 0, 5 do
		local t = i / 6 * math.pi * 2
		spinning(ball("Dot", math.cos(t) * 1.22, AXIS_Y + math.sin(t) * 1.22, -4.67, 0.24, colors.Accent, NEON))
	end
	-- the wide glowing bands
	round("Body", -4.25, -2.3, 2.2, DARK)
	round("Rim", -4.15, -3.62, 2.3, colors.Color, NEON)
	round("Rim", -3.52, -3.0, 2.3, colors.Color, NEON)
	round("Rim", -2.9, -2.42, 2.3, colors.Color, NEON)
	-- the big drum, its metal edges and lights
	round("Body", -2.35, -0.55, 2.5, DARK)
	round("Trim", -2.35, -2.2, 2.6, MID)
	round("Trim", -0.7, -0.55, 2.6, MID)
	for i = 0, 3 do
		local t = i / 4 * math.pi * 2 + math.pi / 4
		spinning(ball("Light", math.cos(t) * 1.24, AXIS_Y + math.sin(t) * 1.24, -1.45, 0.2, colors.Accent, NEON))
	end
	-- a lightning bolt on each side of the drum: a zigzag of thin bars
	local boltColor = colors.Color:Lerp(WHITE, 0.45)
	for side = -1, 1, 2 do
		local x = side * 1.27
		local points = {
			at(x, AXIS_Y + 0.5, -0.85),
			at(x, AXIS_Y + 0.02, -1.62),
			at(x, AXIS_Y + 0.08, -1.3),
			at(x, AXIS_Y - 0.5, -2.08),
		}
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local along = (b - a).Unit
			local across = Vector3.xAxis:Cross(along).Unit
			piece(
				"Bolt",
				CFrame.fromMatrix((a + b) / 2, Vector3.xAxis, across),
				Vector3.new(0.05 * S, 0.15 * S, (b - a).Magnitude + 0.09 * S),
				boltColor,
				NEON
			)
		end
	end
	-- the cage: the glowing core, six barrels, the hoops and clamps, the round back
	if level >= MinigunBlaster.RainbowCoreFrom then
		for i, color in RAINBOW do
			local z0 = -0.6 + (i - 1) * (3.55 / #RAINBOW)
			round("Core", z0, z0 + 3.55 / #RAINBOW, 0.5, color, NEON)
		end
	else
		round("Core", -0.6, 2.95, 0.5, colors.Accent, NEON)
	end
	for i = 0, 5 do
		local t = i / 6 * math.pi * 2 + math.pi / 6
		spinning(cylinder("Barrel", at(math.cos(t) * BARREL_R, AXIS_Y + math.sin(t) * BARREL_R, 1.2), Vector3.zAxis, 3.6, 0.3, MID))
	end
	round("Rim", 0.25, 0.5, 1.75, colors.Color, NEON)
	round("Body", 0.95, 1.3, 1.95, DARK)
	round("Rim", 1.65, 1.9, 1.75, colors.Color, NEON)
	round("Body", 2.1, 2.5, 1.95, DARK)
	round("Body", 2.7, 3.72, 2.1, DARK)
	for i, color in RAINBOW do
		local z = 2.78 + (i - 1) * 0.15
		round("Rainbow", z, z + 0.11, 2.17, color, NEON)
	end
	ball("Body", 0, AXIS_Y, 3.6, 1.3, DARKER)
	-- the round grip under the hand, leaning back a little, a ball at its end
	local gripTop, gripEnd = at(0, -0.05, HAND_Z), at(0, -1.55, HAND_Z + 0.35)
	cylinder("Grip", (gripTop + gripEnd) / 2, (gripTop - gripEnd).Unit, (gripTop - gripEnd).Magnitude / S, 0.6, DARKER)
	piece("Grip", CFrame.new(gripEnd), Vector3.new(0.68, 0.68, 0.68) * S, DARKER, PLASTIC, Enum.PartType.Ball)

	-- the crystals, cut like the picture's: a square column on its corner and a pointed tip
	local tip = colors.Crystal:Lerp(WHITE, 0.18)
	local n = MinigunBlaster.crystals(level)
	local size = 1.0 + 0.13 * (math.clamp(level, 1, 10) - 1)
	for i = 1, math.min(n, #CRYSTAL_ORDER) do
		local cluster = CLUSTERS[CRYSTAL_ORDER[i][1]]
		local k = CRYSTAL_ORDER[i][2]
		local dir = Vector3.new(cluster[4], cluster[5], cluster[6]).Unit
		-- (the 2nd and 3rd of a cluster lean along the gun, either way, and are shorter)
		local lean = (Vector3.zAxis - dir * Vector3.zAxis:Dot(dir)).Unit
		local up = if k == 1 then dir elseif k == 2 then (dir + lean * 0.6).Unit else (dir - lean * 0.6).Unit
		local length = size * (if k == 1 then 1 elseif k == 2 then 0.72 else 0.6) * S
		local width = length * 0.26
		local base = at(cluster[1], cluster[2], cluster[3]) - up * 0.15 * S
		local hint = if math.abs(up.X) > 0.9 then Vector3.zAxis else Vector3.xAxis
		local right = (hint - up * hint:Dot(up)).Unit
		local cf = CFrame.fromMatrix(base, right, up) * CFrame.Angles(0, math.pi / 4, 0)
		local column = length * 0.62
		local top = cf * CFrame.new(0, column + (length - column) / 2, 0)
		local tipSize = Vector3.new(width, length - column, width / 2)
		piece("Crystal", cf * CFrame.new(0, column / 2, 0), Vector3.new(width, column, width), colors.Crystal, NEON)
		piece("CrystalTip", top * CFrame.new(0, 0, -width / 4), tipSize, tip, NEON, nil, "WedgePart")
		piece("CrystalTip", top * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0), tipSize, tip, NEON, nil, "WedgePart")
	end

	local muzzle = at(0, AXIS_Y, FRONT)
	return {
		Hand = Vector3.zero,
		Muzzle = muzzle,
		Top = at(0, AXIS_Y + 1.25, -1.45),
		Side = at(1.25, AXIS_Y, -1.45),
		BarrelY = muzzle.Y,
		BarrelZ = muzzle.Z,
		BarrelR = 1.2 * S,
		Spin = spin,
		SpinAxis = CFrame.new(at(0, AXIS_Y, -1)),
	}
end

return MinigunBlaster
