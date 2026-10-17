--[[
	The crate-opening cinematic's 3D stage (the owner-approved animation,
	tools/preview/anim.js, ported to parts): a dark round room far above the
	map, a stage disc with a glowing ring, the weapon case (CaseBuilder) that
	drops in, rattles while energy streams into it, bursts open (the lid flies
	up, a light pillar, shockwaves, a ring, crystal shards, sparks), and the
	new blaster rising out of the light, spinning to its hero pose in front of
	god rays.

	Pure and deterministic: build() creates every part once, update(t) poses
	everything for time t (seconds) and camera(t) gives the camera frame and
	field of view. The client runs update/camera every frame
	(VaultController); the Lune preview exports frames at chosen times.

	Stage frame: `origin` = the disc's top center; the case's long side along
	Z, its front (+X) and the camera in the +X +Z quarter.
]]

local Geo = require(script.Parent.Geo)
local CaseBuilder = require(script.Parent.CaseBuilder)
local BlasterBuilder = require(script.Parent.BlasterBuilder)

local Stage = {}

export type Stage = {
	Root: Model,
	Duration: number,
	Burst: number, -- the moment the case bursts open
	Reveal: number, -- the blaster has risen; the title comes in
	SkipTo: number, -- a skip before the burst jumps here (the burst still plays)
	Glow: Color3,
	update: (t: number) -> (),
	camera: (t: number) -> (CFrame, number),
	shake: (t: number) -> Vector3,
	burstParts: { BasePart }, -- emit particle bursts from these at Burst (client)
}

Stage.Duration = 10
Stage.T_LAND = 0.55
Stage.T_BURST = 2.85
Stage.T_RISE_END = 4.7
Stage.SkipTo = Stage.T_BURST - 0.2

local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local TINY = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function prog(t: number, a: number, b: number): number
	return clamp01((t - a) / (b - a))
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

local function easeInCubic(x: number): number
	return x * x * x
end

local function easeInOut(x: number): number
	return if x < 0.5 then 4 * x * x * x else 1 - (-2 * x + 2) ^ 3 / 2
end

local function easeOutBack(x: number): number
	local c1 = 1.9
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- A seeded random generator (the same sparks every time).
local function rng(seed: number): () -> number
	local state = seed % 2147483647
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

local function part(parent: Instance, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local props = table.clone(TINY)
	if shape then
		props.Shape = shape
	end
	return Geo.block(parent, CFrame.identity, size, color, material or SMOOTH, props)
end

-- A flat ring of `n` neon segments (radius 1 at size 1; scaled in update).
local function ring(parent: Instance, n: number, color: Color3): { Part }
	local segs = {}
	for _ = 1, n do
		table.insert(segs, part(parent, Vector3.new(0.2, 0.08, 0.4), color, NEON))
	end
	return segs
end

local function poseRing(segs: { Part }, center: CFrame, radius: number, thick: number, transparency: number)
	local n = #segs
	for i, p in segs do
		local a = (i - 1) / n * math.pi * 2
		p.Size = Vector3.new(thick, thick * 0.5, 2 * math.pi * radius / n * 1.05)
		p.CFrame = center * CFrame.Angles(0, a, 0) * CFrame.new(radius, 0, 0)
		p.Transparency = transparency
	end
end

-- Hides a part far below (cheaper than toggling Parent every frame).
local HIDDEN = CFrame.new(0, -5000, 0)

Stage.BlasterLength = 7 -- studs: every level is shown at about the same hero size

--[[
	The new blaster as a loose Model for the stage: BlasterBuilder's held tool
	(the same parts the player gets), unwelded, centered on its bounding box
	and scaled to Stage.BlasterLength along the barrel (-Z).
]]
function Stage.blasterModel(level: number, oreId: string?): Model
	local tool = BlasterBuilder.build(level, oreId)
	local model = Instance.new("Model")
	model.Name = "Blaster"
	local parts: { BasePart } = {}
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local half = d.Size / 2
			for corner = 0, 7 do
				local sx = if corner % 2 == 0 then -1 else 1
				local sy = if corner % 4 < 2 then -1 else 1
				local sz = if corner < 4 then -1 else 1
				local w = d.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
				for i, v in { w.X, w.Y, w.Z } do
					lo[i] = math.min(lo[i], v)
					hi[i] = math.max(hi[i], v)
				end
			end
		end
	end
	local center = Vector3.new((lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2)
	local length = math.max(hi[3] - lo[3], 0.5)
	local k = Stage.BlasterLength / length
	for _, p in parts do
		for _, c in p:GetChildren() do
			if c:IsA("WeldConstraint") or c:IsA("Weld") then
				c:Destroy()
			end
		end
		local cf = p.CFrame
		p.Anchored = true
		p.Size *= k
		p.CFrame = CFrame.new((cf.Position - center) * k) * cf.Rotation
		p.Parent = model
	end
	tool:Destroy()
	return model
end

--[[
	Builds the stage into `parent` at `origin`. `blaster` (optional) is a
	Model of the new blaster in its own frame (barrel along -Z, centered);
	it is moved and turned by update. level / oreId pick the case look.
]]
function Stage.build(parent: Instance, origin: CFrame, level: number, oreId: string, blaster: Model?): Stage
	local root = Instance.new("Model")
	root.Name = "CrateOpening"
	root.Parent = parent
	local caseModel = Instance.new("Model")
	caseModel.Name = "Case"
	caseModel.Parent = root
	local case = CaseBuilder.build(caseModel, CFrame.identity, level, oreId, 1)
	local glowColor = case.Glow
	local hot = Color3.new(1, 1, 1):Lerp(glowColor, 0.55)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	-- the room: a dark floor, a round wall of panels with a glowing horizon band, a dome of stars
	local room = Instance.new("Model")
	room.Name = "Room"
	room.Parent = root
	local floor = part(room, Vector3.new(140, 1, 140), Color3.fromRGB(10, 10, 16))
	floor.CFrame = at(0, -1.1, 0)
	floor.Reflectance = 0.15
	local wallN = 18
	for i = 0, wallN - 1 do
		local a = i / wallN * math.pi * 2
		local w = part(room, Vector3.new(2, 70, 2 * math.pi * 60 / wallN + 1), Color3.fromRGB(12, 11, 20))
		w.CFrame = at(0, 30, 0) * CFrame.Angles(0, a, 0) * CFrame.new(60, 0, 0)
		local band = part(room, Vector3.new(0.4, 3, 2 * math.pi * 59 / wallN + 1), glowColor:Lerp(Color3.new(0, 0, 0), 0.55), NEON)
		band.CFrame = at(0, 2.5, 0) * CFrame.Angles(0, a, 0) * CFrame.new(58.9, 0, 0)
		band.Transparency = 0.25
	end
	local ceiling = part(room, Vector3.new(140, 1, 140), Color3.fromRGB(8, 8, 14))
	ceiling.CFrame = at(0, 64, 0)
	local stars = rng(7)
	for _ = 1, 46 do
		local a, h = stars() * math.pi * 2, 8 + stars() * 52
		local d = 0.2 + stars() * 0.35
		local s = part(room, Vector3.new(d, d, d), Color3.fromRGB(150, 160, 210), NEON)
		s.CFrame = at(math.cos(a) * 58.5, h, math.sin(a) * 58.5)
	end

	-- the stage disc, its glowing rings
	local disc = part(root, Vector3.new(0.6, 15, 15), Color3.fromRGB(26, 26, 36), SMOOTH, Enum.PartType.Cylinder)
	disc.CFrame = at(0, -0.3, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local outerRing = part(root, Vector3.new(0.5, 15.2, 15.2), glowColor, NEON, Enum.PartType.Cylinder)
	outerRing.CFrame = at(0, -0.33, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local innerRing = ring(root, 32, glowColor)
	poseRing(innerRing, at(0, 0.02, 0), 5.2, 0.12, 0)

	-- the light pillar, the inside glow cone, an aura and god rays behind the blaster
	local pillarCore = part(root, Vector3.new(1, 1, 1), hot, NEON, Enum.PartType.Cylinder)
	local pillarWide = part(root, Vector3.new(1, 1, 1), glowColor, NEON, Enum.PartType.Cylinder)
	local aura = part(root, Vector3.new(1, 1, 1), glowColor, NEON, Enum.PartType.Ball)
	local rays: { Part } = {}
	for _ = 1, 14 do
		table.insert(rays, part(root, Vector3.new(0.6, 1, 0.1), glowColor, NEON))
	end
	-- shockwaves on the floor, a vertical burst ring
	local waves = { ring(root, 28, hot), ring(root, 28, glowColor), ring(root, 24, hot) }
	local burstRing = ring(root, 28, hot)
	-- crystal shards, sparks (head + tail), energy streaks pulled in while charging
	local shardRand = rng(11)
	type Flyer = { p: Part, dir: Vector3, speed: number, spin: Vector3, size: number, delay: number }
	local shards: { Flyer } = {}
	for _ = 1, 22 do
		local a, up = shardRand() * math.pi * 2, 0.5 + shardRand() * 0.9
		table.insert(shards, {
			p = part(root, Vector3.new(0.5, 1.4, 0.5), glowColor, NEON),
			dir = Vector3.new(math.cos(a), up, math.sin(a)).Unit,
			speed = 9 + shardRand() * 10,
			spin = Vector3.new(shardRand() * 12, shardRand() * 12, shardRand() * 12),
			size = 0.12 + shardRand() * 0.18,
			delay = shardRand() * 0.08,
		})
	end
	type Spark = { p: Part, dir: Vector3, speed: number, life: number, delay: number }
	local sparkRand = rng(44)
	local sparks: { Spark } = {}
	for i = 1, 46 do
		local a, up = sparkRand() * math.pi * 2, sparkRand() * 1.3 + 0.15
		table.insert(sparks, {
			p = part(root, Vector3.new(0.1, 0.1, 1), if i % 4 == 0 then Color3.new(1, 1, 1) else hot, NEON),
			dir = Vector3.new(math.cos(a), up, math.sin(a)).Unit,
			speed = 7 + sparkRand() * 16,
			life = 0.6 + sparkRand() * 1.1,
			delay = sparkRand() * 0.12,
		})
	end
	type Streak = { p: Part, t0: number, dur: number, th: number, ph: number, r: number }
	local streakRand = rng(33)
	local streaks: { Streak } = {}
	for i = 1, 36 do
		table.insert(streaks, {
			p = part(root, Vector3.new(0.09, 0.09, 1), if i % 3 == 0 then Color3.new(1, 1, 1) else hot, NEON),
			t0 = 0.9 + streakRand() * (Stage.T_BURST - 1.05),
			dur = 0.55 + streakRand() * 0.4,
			th = streakRand() * math.pi * 2,
			ph = math.acos(streakRand() * 1.6 - 0.6),
			r = 7 + streakRand() * 5,
		})
	end

	-- the lights: a soft key light from the camera side, one in the case, one on the blaster
	local keyHolder = part(root, Vector3.new(0.2, 0.2, 0.2), glowColor)
	keyHolder.Transparency = 1
	keyHolder.CFrame = at(9, 11, 8)
	local keyLight = Instance.new("PointLight")
	keyLight.Color = Color3.new(1, 1, 1):Lerp(glowColor, 0.25)
	keyLight.Range = 30
	keyLight.Brightness = 2.4
	keyLight.Shadows = false
	keyLight.Parent = keyHolder
	local coreHolder = part(root, Vector3.new(0.2, 0.2, 0.2), glowColor)
	coreHolder.Transparency = 1
	coreHolder.CFrame = at(0, 2.2, 0)
	local coreLight = Instance.new("PointLight")
	coreLight.Color = glowColor
	coreLight.Range = 26
	coreLight.Brightness = 0
	coreLight.Shadows = false
	coreLight.Parent = coreHolder
	local gunHolder = part(root, Vector3.new(0.2, 0.2, 0.2), glowColor)
	gunHolder.Transparency = 1
	local gunLight = Instance.new("PointLight")
	gunLight.Color = glowColor
	gunLight.Range = 20
	gunLight.Brightness = 0
	gunLight.Shadows = false
	gunLight.Parent = gunHolder

	-- the case's parts relative to the case frame (they move with the drop, the lid with its hinge)
	type Rel = { p: BasePart, rel: CFrame }
	local baseParts: { Rel } = {}
	for _, d in case.Base:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(baseParts, { p = d, rel = d.CFrame })
		end
	end
	local lidParts: { Rel } = {}
	local hingeInv = case.HingeOffset:Inverse()
	for _, d in case.Lid:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(lidParts, { p = d, rel = hingeInv * d.CFrame })
		end
	end
	local gunParts: { Rel } = {}
	if blaster then
		blaster.Parent = root
		for _, d in blaster:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(gunParts, { p = d, rel = d.CFrame })
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
	end
	local gunNeon: { { p: BasePart, color: Color3 } } = {}
	for _, r in gunParts do
		if r.p.Material == NEON then
			table.insert(gunNeon, { p = r.p, color = r.p.Color })
		end
	end
	local seamColor = case.Seam.Color
	local insideColor = case.Inside.Color

	local T_LAND, T_BURST, T_RISE = Stage.T_LAND, Stage.T_BURST, Stage.T_RISE_END
	local caseTop = case.Height
	local gunRest = caseTop + 3.6

	local self = {
		Root = root,
		Duration = Stage.Duration,
		Burst = T_BURST,
		Reveal = T_RISE + 0.25,
		SkipTo = Stage.SkipTo,
		Glow = glowColor,
		burstParts = { coreHolder },
	} :: any

	function self.shake(t: number): Vector3
		local a = 0
		for _, k in { { T_LAND, 0.35, 9 }, { T_BURST, 0.6, 6 }, { T_BURST - 0.25, 0.12, 12 } } do
			if t >= k[1] then
				a += k[2] * math.exp(-(t - k[1]) * k[3])
			end
		end
		if t < T_BURST then
			a += 0.05 * prog(t, 1.0, T_BURST)
		end
		local v = Vector3.new(math.sin(t * 71.3) + math.sin(t * 43.1), math.sin(t * 57.9) + math.cos(t * 31.7), math.cos(t * 63.2))
		return v * (a * 0.5)
	end

	-- the camera path (position, look-at, field of view) in stage coordinates
	type Key = { t: number, pos: Vector3, look: Vector3, fov: number }
	local keys: { Key } = {
		{ t = 0.0, pos = Vector3.new(17, 8.5, 12), look = Vector3.new(0, 4.2, 0), fov = 44 },
		{ t = T_LAND, pos = Vector3.new(15.5, 7.2, 10.5), look = Vector3.new(0, 1.6, 0), fov = 42 },
		{ t = T_BURST - 0.05, pos = Vector3.new(11.2, 5.2, 7.4), look = Vector3.new(0, 1.9, 0), fov = 40 },
		{ t = T_BURST + 0.6, pos = Vector3.new(13.6, 6.8, 9.2), look = Vector3.new(0, 3.6, 0), fov = 44 },
		{ t = T_RISE, pos = Vector3.new(10.2, gunRest + 1.6, 6.3), look = Vector3.new(0, gunRest - 0.5, 0), fov = 42 },
		{ t = Stage.Duration, pos = Vector3.new(8.3, gunRest + 1.2, 4.9), look = Vector3.new(0, gunRest - 0.2, 0), fov = 40 },
	}
	function self.camera(t: number): (CFrame, number)
		local i = 1
		while i < #keys - 1 and t > keys[i + 1].t do
			i += 1
		end
		local k0, k1 = keys[i], keys[i + 1]
		local u = easeInOut(prog(t, k0.t, k1.t))
		local pos = k0.pos:Lerp(k1.pos, u)
		local look = k0.look:Lerp(k1.look, u)
		local shake = self.shake(t)
		local world = origin * CFrame.lookAt(pos + shake, look + shake * 0.4)
		return world, lerp(k0.fov, k1.fov, u)
	end

	function self.update(t: number)
		-- the case: drop, squash, rattle while charging, a hop before the burst
		local drop = prog(t, 0, T_LAND)
		local y = lerp(8, 0, easeInCubic(drop))
		local squash = 1
		if t > T_LAND then
			local u = t - T_LAND
			y = if u < 0.32 then math.sin(u / 0.32 * math.pi) * 0.55 else 0
			squash = 1 - 0.14 * math.exp(-u * 10) * math.cos(u * 30)
		end
		local hop = prog(t, T_BURST - 0.3, T_BURST)
		if hop > 0 and hop < 1 then
			y += math.sin(hop * math.pi) * 0.7
		end
		local rumble = if t > 1.0 and t < T_BURST then prog(t, 1.0, T_BURST) ^ 2 else 0
		local tilt = if t < T_LAND then (1 - drop) * 0.25 else 0
		local caseCf = origin
			* CFrame.new(0, y, 0)
			* CFrame.Angles(math.sin(t * 47) * 0.05 * rumble, 0, math.sin(t * 53 + 1) * 0.06 * rumble + tilt)
		local sq = Vector3.new(2 - squash, squash, 2 - squash)
		local function scaled(rel: CFrame): CFrame
			return CFrame.new(rel.Position * sq) * rel.Rotation
		end
		for _, r in baseParts do
			r.p.CFrame = caseCf * scaled(r.rel)
		end
		-- the lid: rattles while charging, snaps open at the burst with an overshoot, settles
		local open = prog(t, T_BURST, T_BURST + 0.32)
		local lidAngle = if open > 0 then easeOutBack(open) * 1.95 else 0
		lidAngle -= prog(t, T_BURST + 0.32, T_BURST + 1.2) * 0.12
		if t < T_BURST then
			lidAngle = math.max(0, math.sin(t * 38) * 0.04 * rumble)
		end
		local hinge = caseCf * scaled(case.HingeOffset) * CFrame.Angles(0, 0, lidAngle)
		for _, r in lidParts do
			r.p.CFrame = hinge * r.rel
		end
		-- the seam glows up while charging, the inside glows once open
		local charge = prog(t, 1.0, T_BURST)
		case.Seam.Transparency = if t < T_BURST then 1 - (0.15 + 0.85 * charge * (0.75 + 0.25 * math.sin(t * 40))) else 1
		case.Seam.Color = seamColor
		case.Inside.Transparency = if t >= T_BURST then 0.25 + prog(t, T_BURST + 1.5, T_BURST + 3) * 0.4 else 1
		case.Inside.Color = insideColor
		coreLight.Brightness = if t < T_BURST then charge * 4 else 9 * math.exp(-(t - T_BURST) * 3) + 1.5
		outerRing.Color = glowColor:Lerp(
			Color3.new(1, 1, 1),
			clamp01(
				0.5 * math.exp(-math.abs(t - T_LAND) * 8) + (if t > T_BURST then 0.6 * math.exp(-(t - T_BURST) * 3) else 0) + charge * 0.15
			)
		)

		-- the blaster: rises out of the light, spins, floats at its hero angle
		local caseTopWorld = caseTop
		local rise = prog(t, T_BURST + 0.05, T_RISE)
		local shown = t > T_BURST + 0.02
		local bob = math.sin((t - T_RISE) * 2.1) * 0.16 * prog(t, T_RISE - 0.5, T_RISE + 0.5)
		local spin = (1 - easeOutCubic(rise)) * math.pi * 2 * 2.5
		local gunScale = lerp(0.35, 1, easeOutCubic(prog(t, T_BURST, T_BURST + 1.0)))
		local gunCf = origin
			* CFrame.new(0, lerp(caseTopWorld - 1.2, gunRest, easeOutCubic(rise)) + bob, 0)
			* CFrame.Angles(0.06 * math.sin(t * 1.3), -0.32 + spin + 0.1 * math.sin(t * 0.9), 0.05 * math.sin(t * 1.7))
		for _, r in gunParts do
			if shown then
				r.p.CFrame = gunCf * CFrame.new(r.rel.Position * gunScale) * r.rel.Rotation
				local base = r.p:GetAttribute("BaseSize")
				r.p.Size = (if typeof(base) == "Vector3" then base else r.p.Size) * gunScale
			else
				r.p.CFrame = HIDDEN
			end
		end
		local gunGlow = 0.7 * math.exp(-math.max(0, t - T_BURST - 0.3) * 2.2)
		for _, n in gunNeon do
			n.p.Color = n.color:Lerp(Color3.new(1, 1, 1), gunGlow * 0.5)
		end
		gunHolder.CFrame = gunCf * CFrame.new(2.5, 1.2, 1.5)
		gunLight.Brightness = if shown then 2.4 + 0.6 * math.sin(t * 4) else 0

		-- the camera side for camera-facing effects
		local camCf = self.camera(t)
		local toCam = (camCf.Position - gunCf.Position).Unit
		local behind = gunCf.Position - toCam * 4

		-- aura and god rays behind the blaster
		local auraIn = prog(t, T_BURST, T_BURST + 0.4)
		aura.CFrame = CFrame.new(gunCf.Position - toCam * 6)
		local auraSize = 9 + math.sin(t * 3)
		aura.Size = Vector3.new(auraSize, auraSize, auraSize)
		aura.Transparency = 1 - auraIn * (0.07 + 0.02 * math.sin(t * 5))
		local raysIn = easeOutCubic(prog(t, T_BURST, T_BURST + 0.35))
		local rayFrame = CFrame.lookAt(behind - toCam * 2, behind - toCam * 3) * CFrame.Angles(0, 0, t * 0.35)
		local rayLen = lerp(2, 13, raysIn)
		local rayAlpha = raysIn * (0.24 - 0.12 * prog(t, T_BURST + 0.5, T_BURST + 2)) * (0.9 + 0.1 * math.sin(t * 7))
		for i, p in rays do
			local a = (i - 1) / #rays * math.pi * 2
			local w = 0.35 + (i % 3) * 0.25
			p.Size = Vector3.new(w, rayLen, 0.05)
			p.CFrame = rayFrame * CFrame.Angles(0, 0, a) * CFrame.new(0, rayLen / 2 + 1.2, 0)
			p.Transparency = if rayAlpha > 0.01 then 1 - rayAlpha else 1
		end

		-- the light pillar
		local pIn = easeOutCubic(prog(t, T_BURST, T_BURST + 0.18))
		local pOut = 1 - prog(t, T_BURST + 0.35, T_BURST + 1.5)
		local swell = 1 + 0.6 * math.exp(-(t - T_BURST) * 5)
		local pillarH = 34 * pIn
		for i, p in { pillarCore, pillarWide } do
			local d = (if i == 1 then 1.6 else 4.4) * swell
			if t >= T_BURST and pIn * pOut > 0.01 then
				p.Size = Vector3.new(pillarH, d, d)
				p.CFrame = origin * CFrame.new(0, caseTop - 0.6 + pillarH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
				p.Transparency = 1 - pIn * pOut * (if i == 1 then 0.75 else 0.35) * (0.85 + 0.15 * math.sin(t * 30))
			else
				p.CFrame = HIDDEN
			end
		end

		-- shockwaves: the landing, the burst, an echo; the vertical burst ring
		for i, w in waves do
			local t0 = if i == 1 then T_LAND elseif i == 2 then T_BURST else T_BURST + 0.12
			local dur = if i == 1 then 0.7 elseif i == 2 then 0.9 else 1.1
			local size = if i == 1 then 7 elseif i == 2 then 13 else 9
			local u = prog(t, t0, t0 + dur)
			if t >= t0 and u < 1 then
				poseRing(w, origin * CFrame.new(0, 0.06, 0), lerp(0.75, size, easeOutCubic(u)), lerp(0.7, 0.18, u), u)
			else
				for _, p in w do
					p.CFrame = HIDDEN
				end
			end
		end
		do
			local u = prog(t, T_BURST, T_BURST + 0.55)
			if t >= T_BURST and u < 1 then
				local center = CFrame.lookAt((origin * CFrame.new(0, caseTop + 0.5, 0)).Position, camCf.Position)
					* CFrame.Angles(math.pi / 2, 0, 0)
				poseRing(burstRing, center, lerp(0.5, 11, easeOutCubic(u)), lerp(0.6, 0.15, u), u)
			else
				for _, p in burstRing do
					p.CFrame = HIDDEN
				end
			end
		end

		-- shards fly out of the case
		for _, sh in shards do
			local a = t - T_BURST - sh.delay
			if a > 0 and a < 1.6 then
				local pos = Vector3.new(0, caseTop, 0) + sh.dir * sh.speed * a + Vector3.new(0, -9 * a * a, 0)
				local s = sh.size * (1 - prog(a, 1.0, 1.6)) * 2.2
				sh.p.Size = Vector3.new(0.55 * s * 2, 1.4 * s * 2, 0.55 * s * 2)
				sh.p.CFrame = origin * CFrame.new(pos) * CFrame.Angles(sh.spin.X * a, sh.spin.Y * a, sh.spin.Z * a)
			else
				sh.p.CFrame = HIDDEN
			end
		end
		-- sparks with gravity and a trail
		for _, sp in sparks do
			local a = t - T_BURST - sp.delay
			local u = a / sp.life
			if u > 0 and u < 1 then
				local function at(x: number): Vector3
					local drag = (1 - math.exp(-x * 2.2)) / 2.2
					return Vector3.new(
						sp.dir.X * sp.speed * drag,
						caseTop + sp.dir.Y * sp.speed * drag - 4.5 * x * x,
						sp.dir.Z * sp.speed * drag
					)
				end
				local head, tail = at(a), at(math.max(0, a - 0.05))
				local len = math.max(0.1, (head - tail).Magnitude)
				sp.p.Size = Vector3.new(0.12, 0.12, len)
				sp.p.CFrame = origin * CFrame.lookAt((head + tail) / 2, head)
				sp.p.Transparency = u * 0.8
			else
				sp.p.CFrame = HIDDEN
			end
		end
		-- energy pulled into the case while it charges
		for _, st in streaks do
			local u = (t - st.t0) / st.dur
			if u > 0 and u < 1 and t < T_BURST then
				local function at(v: number): Vector3
					local k = (1 - v) ^ 1.7
					local th = st.th + v * 2.4
					return Vector3.new(
						math.sin(st.ph) * math.cos(th) * st.r * k,
						1.8 + math.cos(st.ph) * st.r * k * 0.8,
						math.sin(st.ph) * math.sin(th) * st.r * k
					)
				end
				local head, tail = at(u), at(math.max(0, u - 0.06))
				local len = math.max(0.1, (head - tail).Magnitude)
				st.p.Size = Vector3.new(0.1, 0.1, len)
				st.p.CFrame = origin * CFrame.lookAt((head + tail) / 2, head)
				st.p.Transparency = 1 - math.sin(u * math.pi)
			else
				st.p.CFrame = HIDDEN
			end
		end
		-- the inner ring pulses with the charge
		for _, p in innerRing do
			p.Transparency = 0.2 - 0.2 * charge
		end
	end

	-- remember the blaster's part sizes (update scales from them)
	for _, r in gunParts do
		r.p:SetAttribute("BaseSize", r.p.Size)
	end
	self.update(0)
	return self :: Stage
end

return Stage
