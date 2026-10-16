--[[
	Builds the laser Blaster tool (design v2, replaces the pickaxe): a chunky,
	toy-like gun in the feel of the Kenney Blaster Kit, rebuilt from parts.

	Design frame (studs): the barrel points along -Z, +Y is up, the hand holds
	the grip at HAND. The Handle is the pistol grip, tilted back like a real
	grip; Tool.Grip is set so the barrel still points straight along the arm
	(in the R15 tool pose the grip attachment's -Z points forward).

	  Handle (grip) + Pommel, Body + Dome (rounded top), CoreHousing + Core
	  (glowing disc on both sides), Nose, Barrel(s), rings, MuzzleRing,
	  MuzzleGlow, Guard. Muzzle = Attachment on the Handle at the barrel tip
	  (the client beam starts there).

	Levels add detail: L1 rust patches, L2 stripe + second ring, L3 sight,
	L4 fins, L5 glowing coils, L6 crystal, L7 scope, L8 twin barrels,
	L9 energy tank + dorsal fin, L10 halo ring. Budget: <= 25 parts at every
	level. Colors follow the ore the blaster was forged from (BlasterData.skin);
	level 1 (or no ore) is the rusty starter.

	Pure: only Instance creation, so Lune tests and previews can build it.
]]

local Geo = require(script.Parent.Geo)
local BlasterData = require(script.Parent.Parent.Config.BlasterData)

local BlasterBuilder = {}

BlasterBuilder.ToolName = "Blaster"
BlasterBuilder.MaxParts = 25
BlasterBuilder.Scale = 0.8 -- the design below is ~3.6 studs long; held it is ~2.9 (level 1)

local IRON = Color3.fromRGB(58, 60, 68)
local IRON_LIGHT = Color3.fromRGB(96, 100, 110)
local WOOD = Color3.fromRGB(110, 70, 42)
local RUST = Color3.fromRGB(168, 84, 40)
local RUST_DARK = Color3.fromRGB(104, 58, 36)

-- Design frame: where the grip (Handle) sits and where the hand holds it.
local HANDLE_CF = CFrame.new(0, 0.12, 0.42) * CFrame.Angles(-0.3, 0, 0)
local HAND = Vector3.new(0, 0.3, 0.36)
-- Cylinder whose axis runs along Z (Roblox cylinders run along X).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

export type Look = {
	Level: number,
	Rusty: boolean,
	Body: Color3,
	Accent: Color3,
	Glow: Color3,
	Dark: Color3,
	Grip: Color3,
	BodyMaterial: Enum.Material,
}

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

-- The colors of a blaster (also used for the beam color: Look.Glow).
function BlasterBuilder.look(level: any, oreId: string?): Look
	local info = BlasterData.get(level)
	local rusty = info.Level <= 1 or not oreId or oreId == ""
	local body, glow = BlasterData.skin(if rusty then "" else oreId)
	if rusty then
		return {
			Level = info.Level,
			Rusty = true,
			Body = body,
			Accent = Color3.fromRGB(186, 140, 92),
			Glow = glow,
			Dark = darker(IRON, 0.1),
			Grip = WOOD,
			BodyMaterial = Enum.Material.CorrodedMetal,
		}
	end
	-- very dark ores (coal) keep a readable body; very light ones keep contrast
	local _, _, v = body:ToHSV()
	if v < 0.32 then
		body = lighter(body, 0.18)
	end
	return {
		Level = info.Level,
		Rusty = false,
		Body = body,
		Accent = if v > 0.85 then darker(body, 0.28) else lighter(body, 0.35),
		Glow = glow,
		Dark = if v < 0.32 then IRON_LIGHT else IRON,
		Grip = darker(body, 0.55),
		BodyMaterial = Enum.Material.SmoothPlastic,
	}
end

function BlasterBuilder.build(level: any, oreId: string?): Tool
	local info = BlasterData.get(level)
	local look = BlasterBuilder.look(info.Level, oreId)
	local lv = info.Level
	local s = BlasterBuilder.Scale * (1 + (lv - 1) * 0.025) -- higher levels are a little bigger
	local function scaled(cf: CFrame): CFrame
		return CFrame.new(cf.Position * s) * cf.Rotation
	end
	local handleCf = scaled(HANDLE_CF)

	local tool = Instance.new("Tool")
	tool.Name = BlasterBuilder.ToolName
	tool.ToolTip = BlasterData.displayName(lv, oreId)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	-- the hand at the top of the grip, the barrel straight along the arm
	tool.Grip = handleCf:Inverse() * CFrame.new(HAND * s)
	tool:SetAttribute("Level", lv)
	tool:SetAttribute("OreId", if oreId then oreId else "")
	tool:SetAttribute("Range", info.Range)
	tool:SetAttribute("Glow", look.Glow)

	local handle = Geo.make("Part", {
		Name = "Handle",
		Size = Vector3.new(0.42, 0.9, 0.56) * s,
		Color = look.Grip,
		Material = if look.Rusty then Enum.Material.Wood else Enum.Material.SmoothPlastic,
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Massless = true,
		CastShadow = false,
		CFrame = handleCf,
	})
	handle.Parent = tool

	local function part(
		name: string,
		cf: CFrame,
		size: Vector3,
		color: Color3,
		material: Enum.Material?,
		shape: Enum.PartType?,
		className: string?
	): BasePart
		local p = Geo.make(className or "Part", {
			Name = name,
			CFrame = scaled(cf),
			Size = size * s,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Massless = true,
			CastShadow = false,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local CYL = Enum.PartType.Cylinder
	local NEON = Enum.Material.Neon
	local METAL = if look.Rusty then Enum.Material.CorrodedMetal else Enum.Material.Metal

	-- grip and body
	part("Pommel", HANDLE_CF * CFrame.new(0, -0.48, 0.02), Vector3.new(0.48, 0.14, 0.64), look.Dark, METAL)
	part("Body", CFrame.new(0, 0.85, -0.5), Vector3.new(0.82, 0.6, 2.5), look.Body, look.BodyMaterial)
	part("Dome", CFrame.new(0, 1.0, -0.55) * ALONG_Z, Vector3.new(2.3, 0.82, 0.82), look.Body, look.BodyMaterial, CYL)
	-- the glowing core: a dark ring with a glowing disc, seen from both sides
	part("CoreHousing", CFrame.new(0, 0.92, -0.2), Vector3.new(0.88, 0.62, 0.62), look.Dark, METAL, CYL)
	local coreSize = if look.Rusty then 0.32 else 0.36
	part("Core", CFrame.new(0, 0.92, -0.2), Vector3.new(0.92, coreSize, coreSize), look.Glow, NEON, CYL)
	part("Nose", CFrame.new(0, 0.9, -1.86), Vector3.new(0.7, 0.52, 0.32), look.Dark, METAL)
	part("Guard", CFrame.new(0, 0.3, -0.32), Vector3.new(0.14, 0.1, 0.62), look.Dark, METAL)

	-- barrel(s): one up to level 7, twin barrels from level 8
	local twin = lv >= 8
	local barrelX: { number } = if twin then { -0.19, 0.19 } else { 0 }
	local barrelD = if twin then 0.32 else 0.46
	local barrelY = 0.9
	local tipZ = -3.35
	for i, x in barrelX do
		part(
			if i == 1 then "Barrel" else "Barrel2",
			CFrame.new(x, barrelY, -2.6) * ALONG_Z,
			Vector3.new(1.5, barrelD, barrelD),
			look.Dark,
			METAL,
			CYL
		)
		part(
			if i == 1 then "MuzzleGlow" else "MuzzleGlow2",
			CFrame.new(x, barrelY, tipZ - 0.03) * ALONG_Z,
			Vector3.new(0.06, barrelD * 0.62, barrelD * 0.62),
			look.Glow,
			NEON,
			CYL
		)
	end
	-- rings around the barrel(s): round for one barrel, a flat band for two
	local function ring(name: string, z: number, color: Color3, material: Enum.Material?, thick: number?, wide: number?)
		local t = thick or 0.14
		local d = wide or 0.6
		if twin then
			part(name, CFrame.new(0, barrelY, z), Vector3.new(d + 0.24, d - 0.14, t), color, material)
		else
			part(name, CFrame.new(0, barrelY, z) * ALONG_Z, Vector3.new(t, d, d), color, material, CYL)
		end
	end
	ring("Ring1", -2.2, look.Accent, METAL)
	ring("MuzzleRing", tipZ + 0.07, look.Accent, METAL, 0.14, 0.66)
	if lv >= 2 and lv < 5 then
		ring("Ring2", -2.65, look.Accent, METAL)
	elseif lv >= 5 then
		-- glowing coils
		ring("CoilA", -2.5, look.Glow, NEON, 0.07, 0.56)
		ring("CoilB", -2.8, look.Glow, NEON, 0.07, 0.56)
	end

	if look.Rusty and lv <= 3 then
		-- rust patches: the old starter blaster (later levels use the parts for detail)
		part("Rust", CFrame.new(0.4, 0.75, -1.05), Vector3.new(0.06, 0.3, 0.5), RUST, Enum.Material.CorrodedMetal)
		part(
			"Rust",
			CFrame.new(-0.3, 1.25, 0.2) * CFrame.Angles(0, 0, 0.6),
			Vector3.new(0.14, 0.24, 0.44),
			RUST_DARK,
			Enum.Material.CorrodedMetal
		)
	end
	if lv >= 2 then
		-- a stripe along both sides
		part("Stripe", CFrame.new(0, 0.68, -0.6), Vector3.new(0.86, 0.12, 1.6), look.Accent, METAL)
	end
	if lv >= 3 and lv < 7 then
		part("Sight", CFrame.new(0, 1.46, -1.4), Vector3.new(0.14, 0.2, 0.3), look.Dark, METAL)
	end
	if lv >= 4 then
		-- swept fins at the back
		for _, side in { -1, 1 } do
			local fin = CFrame.new(side * 0.47, 0.95, 0.45) * CFrame.Angles(0, 0, side * -0.25)
			part("Fin", fin, Vector3.new(0.08, 0.5, 0.7), look.Accent, METAL, nil, "WedgePart")
		end
	end
	if lv >= 6 then
		-- a crystal set into the top of the body
		part(
			"Crystal",
			CFrame.new(0, 1.42, -0.15) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
			Vector3.new(0.3, 0.3, 0.3),
			look.Glow,
			NEON
		)
	end
	if lv >= 7 then
		part("Scope", CFrame.new(0, 1.58, -0.95) * ALONG_Z, Vector3.new(0.8, 0.26, 0.26), look.Dark, METAL, CYL)
		part("Lens", CFrame.new(0, 1.58, -1.37) * ALONG_Z, Vector3.new(0.04, 0.18, 0.18), look.Glow, NEON, CYL)
	end
	if lv >= 9 then
		part("Tank", CFrame.new(0, 0.42, -1.3) * ALONG_Z, Vector3.new(0.7, 0.3, 0.3), look.Glow, NEON, CYL)
		part("DorsalFin", CFrame.new(0, 1.48, 0.45), Vector3.new(0.08, 0.36, 0.55), look.Accent, METAL, nil, "WedgePart")
	end
	if lv >= 10 then
		part("Halo", CFrame.new(0, barrelY, tipZ + 0.3) * ALONG_Z, Vector3.new(0.05, 1.0, 1.0), look.Glow, NEON, CYL)
	end

	-- where the beam leaves the barrel (between the twin barrels from level 8)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = handleCf:PointToObjectSpace(Vector3.new(0, barrelY, tipZ - 0.12) * s)
	muzzle.Parent = handle
	return tool
end

return BlasterBuilder
