--[[
	The void crate opening (owner 2026-11-06: his storyboard and timeline): a
	dark purple void with floating rocks and chains, a round platform that lights
	up, a neon portal that opens above it, the crate (CaseBuilder) that shoots down
	out of the portal and slams onto the platform, hovers while the camera orbits,
	charges (it shakes, energy pours in, small portals open) and blows open (the
	lid halves fly up, the walls fold out, a huge beam, a flash); the new blaster
	flies out, circled by energy, over a platform of light, the camera zooms in on
	it for the reveal, it turns once more and is collected.

	  0.0-0.3  the scene: the platform starts to glow, the first particles
	  0.3-1.0  the portal opens and spins, the crate shoots out (T_LAND)
	  1.0-1.4  the impact: shake, a quick zoom, the energy wave, the shockwaves
	  1.4-2.0  the camera orbits, the crate hovers, two neon rings turn under it
	  2.0-2.8  charging: it shakes, rays pour in, small portals, the light grows
	  2.8-3.3  the explosive opening (T_BURST)
	  3.3-4.0  the blaster flies in (T_RISE_END)
	  4.0-4.8  the reveal: the zoom, the glow (T_HOLD: waits for AWESOME!)
	  4.8-5.3  collected: one more turn, the camera pulls out, the effects fade

	Pure and deterministic: build() creates every part once, update(t, idle) poses
	everything for time t and camera(t, idle) gives the camera frame and field of
	view; idle = the seconds waited at T_HOLD (what loops keeps moving meanwhile).
	The client runs them every frame (VaultController); the Lune preview exports
	frames with the same code. stage.bulk (optional, set by the client) moves the
	parts in one call; parts that stay put or hidden are not touched.

	Roblox has no motion blur: the falling crate draws see-through copies behind
	it and speed lines, and blur(t) gives the client a short BlurEffect.

	Stage frame: `origin` = the platform's top center; the crate's long side along
	Z, its front (+X) and the camera on the +X side.
]]

local Geo = require(script.Parent.Geo)
local CaseBuilder = require(script.Parent.CaseBuilder)
local BlasterBuilder = require(script.Parent.BlasterBuilder)

local Stage = {}

export type Stage = {
	Root: Model,
	Duration: number,
	Burst: number, -- the moment the crate bursts open
	Reveal: number, -- the blaster is out: the title comes in
	Hold: number, -- the reveal is done: time stops here until AWESOME!
	SkipTo: number, -- a skip before the burst jumps here (the burst still plays)
	Glow: Color3,
	update: (t: number, idle: number?) -> (),
	camera: (t: number, idle: number?) -> (CFrame, number),
	shake: (t: number) -> Vector3,
	blur: (t: number) -> number,
	bulk: (({ BasePart }, { CFrame }) -> ())?,
	burstParts: { BasePart }, -- emit particle bursts from these at Burst (client)
}

Stage.Duration = 5.3
Stage.T_PREP = 0.3
Stage.T_LAND = 1.0
Stage.T_IMPACT = 1.4
Stage.T_ORBIT = 2.0
Stage.T_BURST = 2.8
Stage.T_OPEN = 3.3
Stage.T_RISE_END = 4.0
Stage.T_HOLD = 4.8
Stage.SkipTo = Stage.T_BURST - 0.2
Stage.GunRest = 7.4 -- how high the blaster floats
Stage.PortalHeight = 14

local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

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

-- Hides a part far below (cheaper than toggling Parent every frame).
local HIDDEN = CFrame.new(0, -5000, 0)

-- studs: every level is shown at about the same hero size, inside this box
Stage.BlasterLength = 7
Stage.BlasterHeight = 3

--[[
	The new blaster as a loose Model for the stage: BlasterBuilder's held tool
	(the same parts the player gets), unwelded, centered on its bounding box
	and scaled to fit Stage.BlasterLength along the barrel (-Z) and
	Stage.BlasterHeight up.
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
	local height = math.max(hi[2] - lo[2], 0.2)
	local k = math.min(Stage.BlasterLength / length, Stage.BlasterHeight / height)
	for _, p in parts do
		for _, c in p:GetChildren() do
			if c:IsA("WeldConstraint") or c:IsA("Weld") or c:IsA("Motor6D") then
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

-- A flat ring of neon segments, posed by poseRing below (it writes only what changed).
type Ring = { Parts: { Part }, R: number, Th: number, A: number, Hidden: boolean, Tail: boolean }

local function newRing(parent: Instance, n: number, color: Color3, tail: boolean?): Ring
	local list = {}
	for _ = 1, n do
		table.insert(list, part(parent, Vector3.new(0.2, 0.08, 0.4), color, NEON))
	end
	return { Parts = list, R = -1, Th = -1, A = -1, Hidden = false, Tail = tail == true }
end

--[[
	Builds the stage into `parent` at `origin`. `blaster` (optional) is a Model
	of the new blaster in its own frame (barrel along -Z, centered); it is moved
	and turned by update. level / oreId pick the crate. calm = Reduce motion: no
	shake, no blur, no zoom kick.
]]
function Stage.build(parent: Instance, origin: CFrame, level: number, oreId: string, blaster: Model?, calm: boolean?): Stage
	local root = Instance.new("Model")
	root.Name = "CrateOpening"
	root.Parent = parent
	local caseModel = Instance.new("Model")
	caseModel.Name = "Case"
	caseModel.Parent = root
	local case = CaseBuilder.build(caseModel, CFrame.identity, level, oreId, 1)
	local glowColor = case.Glow
	local hot = WHITE:Lerp(glowColor, 0.55)
	local deep = glowColor:Lerp(BLACK, 0.6)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	---------------------------------------------------------------- the void (never moves)

	local room = Instance.new("Model")
	room.Name = "Room"
	room.Parent = root
	-- the void's colour: the crate's glow leaning to violet, brightest round the platform and low on the wall
	local void = glowColor:Lerp(Color3.fromRGB(96, 40, 210), 0.55)
	local night = Color3.fromRGB(10, 8, 18)
	local floor = part(room, Vector3.new(140, 1, 140), night)
	floor.CFrame = at(0, -1.1, 0)
	floor.Reflectance = 0.2
	for i, band in { { 66, 0.04 }, { 50, 0.07 }, { 38, 0.1 }, { 29, 0.14 }, { 22, 0.19 }, { 17, 0.25 }, { 13, 0.32 } } do
		local d = band[1] * 2
		local glowFloor = part(room, Vector3.new(0.1, d, d), night:Lerp(void, band[2]), NEON, Enum.PartType.Cylinder)
		glowFloor.CFrame = at(0, -0.6 + i * 0.002, 0) * CFrame.Angles(0, 0, math.pi / 2)
	end
	-- the round wall in rows: a soft glow along the horizon, dark overhead
	local wallN = 14
	local rows = 9
	for r = 1, rows do
		-- (y, height, how much it glows: the lowest row most, each one less)
		local h = 64 / rows
		local row = { (r - 0.5) * h, h + 0.1, 0.46 * (1 - (r - 1) / rows) ^ 2.2 + 0.02 }
		local color = night:Lerp(void, row[3])
		for i = 0, wallN - 1 do
			local a = i / wallN * math.pi * 2
			-- (Neon in these dim colours: an even glow, whatever the lights do)
			local w = part(room, Vector3.new(2, row[2], 2 * math.pi * 60 / wallN + 1), color, NEON)
			w.CFrame = at(0, row[1], 0) * CFrame.Angles(0, a, 0) * CFrame.new(60, 0, 0)
		end
	end
	local ceiling = part(room, Vector3.new(140, 1, 140), night)
	ceiling.CFrame = at(0, 64, 0)
	local stars = rng(7)
	for _ = 1, 20 do
		local a, h = stars() * math.pi * 2, 8 + stars() * 50
		local d = 0.2 + stars() * 0.35
		local s = part(room, Vector3.new(d, d, d), hot, NEON)
		s.CFrame = at(math.cos(a) * 58.5, h, math.sin(a) * 58.5)
	end
	-- jagged dark rocks along the edge of the floor
	local rockColor = Color3.fromRGB(44, 34, 62):Lerp(void, 0.12)
	local edge = rng(53)
	for _ = 1, 22 do
		local a, r = edge() * math.pi * 2, 20 + edge() * 22
		local h = 2 + edge() * 8
		local w = 2 + edge() * 4
		local rock = part(room, Vector3.new(w, h, w * (0.7 + edge() * 0.6)), rockColor)
		rock.CFrame = at(math.cos(a) * r, h * 0.3 - 1, math.sin(a) * r) * CFrame.Angles(edge() * 0.5, edge() * 6, edge() * 0.5)
	end
	-- the chains from above down to the platform's edge
	local chainColor = Color3.fromRGB(58, 50, 78)
	for _, c in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local from = Vector3.new(c[1] * 24, 34, c[2] * 26)
		local to = Vector3.new(c[1] * 9.5, -0.3, c[2] * 10.5)
		local n = 14
		for i = 1, n do
			local p = from:Lerp(to, (i - 0.5) / n)
			local link = part(room, Vector3.new(0.6, 0.3, 3.1), chainColor, METAL)
			link.CFrame = origin * CFrame.lookAt(p, to) * CFrame.Angles(0, 0, if i % 2 == 0 then math.pi / 4 else -math.pi / 4)
		end
	end
	-- glowing cracks in the floor, out from the platform
	local cracks = rng(77)
	local crackColor = glowColor:Lerp(BLACK, 0.25)
	for _ = 1, 14 do
		local a = cracks() * math.pi * 2
		local x, z = math.cos(a) * 8.8, math.sin(a) * 8.8
		for _ = 1, 3 do
			a += (cracks() - 0.5) * 1.1
			local len = 3 + cracks() * 6
			local nx, nz = x + math.cos(a) * len, z + math.sin(a) * len
			local c = part(room, Vector3.new(0.14, 0.05, len), crackColor, NEON)
			c.CFrame = origin * CFrame.lookAt(Vector3.new((x + nx) / 2, -0.58, (z + nz) / 2), Vector3.new(nx, -0.58, nz))
			x, z = nx, nz
		end
	end

	---------------------------------------------------------------- the platform

	local disc = part(root, Vector3.new(0.6, 17, 17), Color3.fromRGB(46, 42, 62), SMOOTH, Enum.PartType.Cylinder)
	disc.CFrame = at(0, -0.3, 0) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Name = "Platform"
	local outerRing = part(root, Vector3.new(0.5, 17.3, 17.3), glowColor, NEON, Enum.PartType.Cylinder)
	outerRing.CFrame = at(0, -0.33, 0) * CFrame.Angles(0, 0, math.pi / 2)
	outerRing.Name = "PlatformRim"
	-- his 12 glowing platform segments light up one after the other, the seams between the stones
	local plateGlow: { Part } = {}
	for i = 1, 12 do
		local a = math.rad(i * 30)
		local seg = part(root, Vector3.new(0.18, 0.1, 2.5), glowColor, NEON)
		seg.CFrame = at(math.cos(a) * 7.1, 0.02, math.sin(a) * 7.1) * CFrame.Angles(0, -a, 0)
		seg.Name = "PlatformGlow"
		table.insert(plateGlow, seg)
	end
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2 + 0.2
		local seam = part(root, Vector3.new(4.6, 0.04, 0.08), deep, NEON)
		seam.CFrame = at(math.cos(a) * 4.2, 0.01, math.sin(a) * 4.2) * CFrame.Angles(0, -a, 0)
	end
	local innerRing = newRing(root, 32, glowColor)

	---------------------------------------------------------------- the effects (all hidden when not in use)

	-- the portal: two rings, three spiral arms, a glowing heart; the shaft of light under it
	local portalOuter = newRing(root, 40, hot)
	local portalInner = newRing(root, 28, glowColor)
	local portalArms: { Part } = {}
	for _ = 1, 24 do
		table.insert(portalArms, part(root, Vector3.new(0.3, 0.1, 1), glowColor, NEON))
	end
	local portalHeart = part(root, Vector3.new(0.2, 1, 1), hot, NEON, Enum.PartType.Cylinder)
	local shaft = part(root, Vector3.new(1, 1, 1), glowColor, NEON, Enum.PartType.Cylinder)
	-- the crate's fall: see-through copies behind it, speed lines
	local ghosts: { Part } = {}
	for _ = 1, 4 do
		table.insert(ghosts, part(root, Vector3.new(case.Width, case.Height, case.Length), glowColor, NEON))
	end
	local speedRand = rng(91)
	local speedLines: { { p: Part, x: number, z: number, len: number } } = {}
	for _ = 1, 14 do
		local a, r = speedRand() * math.pi * 2, 3 + speedRand() * 5
		table.insert(speedLines, {
			p = part(root, Vector3.new(0.1, 1, 0.1), hot, NEON),
			x = math.cos(a) * r,
			z = math.sin(a) * r,
			len = 5 + speedRand() * 7,
		})
	end
	-- the energy wave: a ball that grows out of the crate; the shockwaves on the floor
	local wave = part(root, Vector3.new(1, 1, 1), hot, NEON, Enum.PartType.Ball)
	local waves = { newRing(root, 32, hot), newRing(root, 28, glowColor), newRing(root, 32, hot), newRing(root, 28, glowColor) }
	local burstRing = newRing(root, 28, hot)
	-- two neon rings turning under the hovering crate
	local underA, underB = newRing(root, 26, glowColor), newRing(root, 26, hot)
	-- the swirling comet arcs round the crate and later round the blaster
	local arcA, arcB = newRing(root, 34, hot, true), newRing(root, 34, glowColor, true)
	-- small portals round the crate while it charges, each with a ray into the crate
	local mini: { { ring: Ring, heart: Part, ray: Part, at: Vector3, t0: number } } = {}
	for i, spot in { Vector3.new(4, 6.5, -8), Vector3.new(4, 7, 8), Vector3.new(-6, 5, -6.5), Vector3.new(-6, 6, 6.5) } do
		table.insert(mini, {
			ring = newRing(root, 14, hot),
			heart = part(root, Vector3.new(0.15, 1, 1), glowColor, NEON, Enum.PartType.Cylinder),
			ray = part(root, Vector3.new(1, 0.2, 0.2), hot, NEON, Enum.PartType.Cylinder),
			at = spot,
			t0 = Stage.T_ORBIT + 0.08 * i,
		})
	end
	-- the light pillar out of the open crate, the god rays behind the blaster
	local pillarCore = part(root, Vector3.new(1, 1, 1), hot, NEON, Enum.PartType.Cylinder)
	local pillarWide = part(root, Vector3.new(1, 1, 1), glowColor, NEON, Enum.PartType.Cylinder)
	local rays: { Part } = {}
	for _ = 1, 10 do
		table.insert(rays, part(root, Vector3.new(0.6, 1, 0.1), glowColor, NEON))
	end
	-- the platform of light under the blaster
	local lightRing, lightInner = newRing(root, 30, hot), newRing(root, 22, glowColor)
	-- energy particles circling the blaster
	local orbitRand = rng(61)
	local orbiters: { { p: Part, r: number, speed: number, phase: number, tilt: number, size: number } } = {}
	for i = 1, 20 do
		table.insert(orbiters, {
			p = part(root, Vector3.new(0.2, 0.2, 0.2), if i % 3 == 0 then WHITE else hot, NEON, Enum.PartType.Ball),
			r = 3.4 + orbitRand() * 2.4,
			speed = (2 + orbitRand() * 2) * (if i % 2 == 0 then 1 else -1),
			phase = orbitRand() * math.pi * 2,
			tilt = (i % 3 - 1) * 0.55,
			size = 0.07 + orbitRand() * 0.13,
		})
	end
	-- pieces of the crate and sparks
	local shardRand = rng(11)
	type Flyer = { p: Part, dir: Vector3, speed: number, spin: Vector3, size: number, delay: number }
	local shards: { Flyer } = {}
	for i = 1, 16 do
		local a, up = shardRand() * math.pi * 2, 0.3 + shardRand() * 0.9
		table.insert(shards, {
			p = part(
				root,
				Vector3.new(0.5, 0.5, 0.5),
				if i % 2 == 0 then Color3.fromRGB(46, 43, 58) else glowColor,
				if i % 2 == 0 then METAL else NEON
			),
			dir = Vector3.new(math.cos(a), up, math.sin(a)).Unit,
			speed = 10 + shardRand() * 12,
			spin = Vector3.new(shardRand() * 10, shardRand() * 10, shardRand() * 10),
			size = 0.25 + shardRand() * 0.6,
			delay = shardRand() * 0.06,
		})
	end
	type Spark = { p: Part, dir: Vector3, speed: number, life: number, delay: number, t0: number, y: number }
	local sparkRand = rng(44)
	local sparks: { Spark } = {}
	for i = 1, 52 do
		-- the first ones fly out flat at the impact, the others at the burst
		local flat = i <= 16
		local a, up = sparkRand() * math.pi * 2, if flat then 0.1 + sparkRand() * 0.2 else sparkRand() * 1.3 + 0.15
		table.insert(sparks, {
			p = part(root, Vector3.new(0.1, 0.1, 1), if i % 4 == 0 then WHITE else hot, NEON),
			dir = Vector3.new(math.cos(a), up, math.sin(a)).Unit,
			speed = 8 + sparkRand() * 18,
			life = 0.5 + sparkRand() * 0.8,
			delay = sparkRand() * 0.08,
			t0 = if flat then Stage.T_LAND else Stage.T_BURST,
			y = if flat then 0.4 else 2.5,
		})
	end
	-- the first particles at the start, energy pouring into the crate while it charges
	type Streak = { p: Part, t0: number, dur: number, th: number, ph: number, r: number }
	local streakRand = rng(33)
	local streaks: { Streak } = {}
	for i = 1, 32 do
		local early = i <= 6
		table.insert(streaks, {
			p = part(root, Vector3.new(0.09, 0.09, 1), if i % 3 == 0 then WHITE else hot, NEON),
			t0 = if early then 0.05 + streakRand() * 0.3 else Stage.T_ORBIT + streakRand() * (Stage.T_BURST - Stage.T_ORBIT - 0.3),
			dur = 0.4 + streakRand() * 0.3,
			th = streakRand() * math.pi * 2,
			ph = math.acos(streakRand() * 1.6 - 0.6),
			r = 8 + streakRand() * 6,
		})
	end
	-- the floating rocks: they drift round the platform and are thrown back by the impact and the burst
	local floatRand = rng(29)
	type Rock = { p: Part, a: number, r: number, y: number, speed: number, spin: Vector3 }
	local rocks: { Rock } = {}
	for _ = 1, 16 do
		local d = 0.9 + floatRand() * 1.6
		table.insert(rocks, {
			p = part(root, Vector3.new(d, d * (0.7 + floatRand() * 0.5), d * (0.7 + floatRand() * 0.5)), rockColor),
			-- (behind and beside the crate, never in front of the camera)
			a = math.rad(100 + floatRand() * 160),
			r = 11 + floatRand() * 11,
			y = 1 + floatRand() * 11,
			speed = 0.03 + floatRand() * 0.05,
			spin = Vector3.new(floatRand(), floatRand(), floatRand()) * 0.5,
		})
	end

	-- the lights: a soft key light from the camera side, a violet fill, one in the crate, one on the blaster
	local keyHolder = part(room, Vector3.new(0.2, 0.2, 0.2), glowColor)
	keyHolder.Transparency = 1
	keyHolder.CFrame = at(13, 10, 6)
	local keyLight = Instance.new("PointLight")
	keyLight.Color = WHITE:Lerp(glowColor, 0.35)
	keyLight.Range = 40
	keyLight.Brightness = 3.2
	keyLight.Shadows = false
	keyLight.Parent = keyHolder
	local fillHolder = part(room, Vector3.new(0.2, 0.2, 0.2), glowColor)
	fillHolder.Transparency = 1
	fillHolder.CFrame = at(-3, 8, 9)
	local fillLight = Instance.new("PointLight")
	fillLight.Color = void
	fillLight.Range = 34
	fillLight.Brightness = 2.2
	fillLight.Shadows = false
	fillLight.Parent = fillHolder
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
	gunLight.Range = 14
	gunLight.Brightness = 0
	gunLight.Shadows = false
	gunLight.Parent = gunHolder

	-- the crate's parts in the crate's frame (the walls by their hinges, the lid by its halves)
	type Rel = { p: BasePart, rel: CFrame }
	local function relsOf(model: Instance, inv: CFrame?): { Rel }
		local out: { Rel } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, { p = d, rel = if inv then inv * d.CFrame else d.CFrame })
			end
		end
		return out
	end
	local baseParts = relsOf(case.Base)
	local lidParts = { relsOf(case.LidA), relsOf(case.LidB) }
	local panelParts: { { parts: { Rel }, hinge: CFrame, fold: Vector3 } } = {}
	for _, panel in case.Panels do
		table.insert(panelParts, { parts = relsOf(panel.Model), hinge = panel.Hinge, fold = panel.Fold })
	end
	local lightColors: { { p: BasePart, color: Color3 } } = {}
	for _, p in case.Lights do
		table.insert(lightColors, { p = p, color = p.Color })
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
	local gunBase: { [BasePart]: Vector3 } = {}
	for _, r in gunParts do
		gunBase[r.p] = r.p.Size
	end

	local T_LAND, T_IMPACT, T_ORBIT = Stage.T_LAND, Stage.T_IMPACT, Stage.T_ORBIT
	local T_BURST, T_OPEN, T_RISE, T_HOLD = Stage.T_BURST, Stage.T_OPEN, Stage.T_RISE_END, Stage.T_HOLD
	local T_FALL = 0.62 -- the crate comes out of the portal
	local PORTAL_Y = Stage.PortalHeight
	local caseTop = case.Height
	local gunRest = Stage.GunRest

	local self = {
		Root = root,
		Duration = Stage.Duration,
		Burst = T_BURST,
		Reveal = T_RISE,
		Hold = T_HOLD,
		SkipTo = Stage.SkipTo,
		Glow = glowColor,
		burstParts = { coreHolder },
	} :: any

	---------------------------------------------------------------- moving parts

	local moveParts: { BasePart } = {}
	local moveFrames: { CFrame } = {}
	local hiddenNow: { [BasePart]: boolean } = {}
	local function place(p: BasePart, cf: CFrame)
		hiddenNow[p] = nil
		table.insert(moveParts, p)
		table.insert(moveFrames, cf)
	end
	local function hide(p: BasePart)
		if not hiddenNow[p] then
			place(p, HIDDEN)
			hiddenNow[p] = true
		end
	end
	local function poseRing(rg: Ring, center: CFrame, radius: number, thick: number, alpha: number, angle: number)
		local n = #rg.Parts
		local resized = rg.R ~= radius or rg.Th ~= thick
		local size = if resized then Vector3.new(thick, thick * 0.5, 2 * math.pi * radius / n * 1.05) else nil
		local shade = math.abs(rg.A - alpha) > 0.01
		for i, p in rg.Parts do
			if size then
				p.Size = size
			end
			if shade then
				-- (a comet: the last segments fade away)
				p.Transparency = if rg.Tail then lerp(alpha, 1, (i - 1) / n) else alpha
			end
			local a = (i - 1) / n * math.pi * 2 + angle
			place(p, center * CFrame.Angles(0, a, 0) * CFrame.new(radius, 0, 0))
		end
		rg.R, rg.Th, rg.Hidden = radius, thick, false
		if shade then
			rg.A = alpha
		end
	end
	local function hideRing(rg: Ring)
		if not rg.Hidden then
			rg.Hidden = true
			for _, p in rg.Parts do
				hide(p)
			end
		end
	end
	-- A cylinder standing up, from y0 to y0 + height.
	local function poseColumn(p: BasePart, x: number, y0: number, z: number, height: number, d: number, alpha: number)
		p.Size = Vector3.new(height, d, d)
		p.Transparency = alpha
		place(p, at(x, y0 + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2))
	end

	---------------------------------------------------------------- the camera

	local noise = if calm then 0 else 1
	function self.shake(t: number): Vector3
		local a = 0
		for _, k in { { T_LAND, 0.65, 8 }, { T_BURST, 0.8, 6 }, { T_BURST - 0.2, 0.12, 12 } } do
			if t >= k[1] then
				a += k[2] * math.exp(-(t - k[1]) * k[3])
			end
		end
		if t > T_ORBIT and t < T_BURST then
			a += 0.1 * prog(t, T_ORBIT, T_BURST)
		end
		local v = Vector3.new(math.sin(t * 71.3) + math.sin(t * 43.1), math.sin(t * 57.9) + math.cos(t * 31.7), math.cos(t * 63.2))
		return v * (a * 0.5 * noise)
	end

	-- The size of a short BlurEffect: the crate's fall and the burst (Roblox has no motion blur).
	function self.blur(t: number): number
		if calm then
			return 0
		end
		local fall = if t > T_FALL and t < T_LAND + 0.08 then 7 * math.sin(prog(t, T_FALL, T_LAND + 0.08) * math.pi) else 0
		local burst = if t >= T_BURST then 9 * math.exp(-(t - T_BURST) * 9) else 0
		return fall + burst
	end

	-- the camera path round the stage: radius, angle from the crate's front (degrees), height, what it looks at, zoom
	type Key = { t: number, r: number, a: number, h: number, look: number, fov: number }
	local keys: { Key } = {
		{ t = 0, r = 22, a = 10, h = 5.5, look = 4.5, fov = 50 },
		{ t = Stage.T_PREP, r = 21, a = 10, h = 2.6, look = 8, fov = 58 },
		{ t = 0.9, r = 20, a = 12, h = 3, look = 7, fov = 58 },
		{ t = T_LAND + 0.04, r = 18.5, a = 12, h = 3.6, look = 2.2, fov = 54 },
		{ t = T_LAND + 0.15, r = 17, a = 13, h = 4.2, look = 2, fov = if calm then 50 else 42 },
		{ t = T_IMPACT, r = 16, a = 16, h = 4.4, look = 2.4, fov = 44 },
		{ t = T_ORBIT, r = 14.5, a = -8, h = 4, look = 2.7, fov = 42 },
		{ t = T_BURST, r = 12.5, a = -16, h = 3.6, look = 2.9, fov = 40 },
		{ t = T_BURST + 0.2, r = 17, a = -8, h = 4.6, look = 4.6, fov = 52 },
		{ t = T_OPEN, r = 18, a = 2, h = 5, look = 6.2, fov = 52 },
		{ t = T_RISE, r = 14, a = 12, h = 8, look = 7.2, fov = 46 },
		{ t = T_RISE + 0.18, r = 11.4, a = 15, h = 8.6, look = 7.2, fov = if calm then 46 else 38 },
		{ t = T_HOLD, r = 11, a = 18, h = 8.8, look = 7.1, fov = 38 },
		{ t = Stage.Duration, r = 20, a = 14, h = 7, look = 6, fov = 48 },
	}
	function self.camera(t: number, idle: number?): (CFrame, number)
		local i = 1
		while i < #keys - 1 and t > keys[i + 1].t do
			i += 1
		end
		local k0, k1 = keys[i], keys[i + 1]
		local u = easeInOut(prog(t, k0.t, k1.t))
		local a = math.rad(lerp(k0.a, k1.a, u) + 1.2 * math.sin((idle or 0) * 0.8))
		local r = lerp(k0.r, k1.r, u)
		local pos = Vector3.new(math.cos(a) * r, lerp(k0.h, k1.h, u), math.sin(a) * r)
		local look = Vector3.new(0, lerp(k0.look, k1.look, u), 0)
		local shake = self.shake(t)
		return origin * CFrame.lookAt(pos + shake, look + shake * 0.4), lerp(k0.fov, k1.fov, u)
	end

	---------------------------------------------------------------- every frame

	function self.update(t: number, idle: number?)
		local clock = t + (idle or 0) -- what keeps moving while the reveal waits
		local fadeOut = prog(t, T_HOLD + 0.05, Stage.Duration) -- the effects fade at the end
		local camCf = self.camera(t, idle)
		local charge = prog(t, T_ORBIT, T_BURST)

		-- the platform lights up in the first moments, its segments one by one; flares at the impact
		local lit = prog(t, 0, Stage.T_PREP + 0.2)
		local flareLand = if t >= T_LAND then math.exp(-(t - T_LAND) * 7) else 0
		local flareBurst = if t >= T_BURST then math.exp(-(t - T_BURST) * 3) else 0
		if lit < 1 or t < T_RISE then
			for i, seg in plateGlow do
				seg.Transparency = 1 - prog(t, (i - 1) * 0.03, (i - 1) * 0.03 + 0.15) * (0.7 + 0.3 * charge)
			end
		end
		outerRing.Color = deep:Lerp(glowColor, lit):Lerp(WHITE, clamp01(0.5 * flareLand + 0.6 * flareBurst + charge * 0.2))
		poseRing(innerRing, at(0, 0.03, 0), 5.2, 0.14, lerp(0.75, 0.15, math.max(lit * 0.5, charge)), 0)

		-- the portal: opens fast, spins fast, closes after the crate has landed
		local opening = prog(t, Stage.T_PREP, Stage.T_PREP + 0.3)
		local closing = prog(t, T_IMPACT, T_ORBIT)
		local scale = (if opening > 0 then easeOutBack(opening) else 0) * (1 - closing)
		if scale > 0.01 then
			-- (leaning to the camera: you look into it)
			local center = at(0, PORTAL_Y, 0) * CFrame.Angles(0, 0, 0.42)
			local spin = t * 9
			poseRing(portalOuter, center, 5.6 * scale, 0.42, 0, spin)
			poseRing(portalInner, center, 4 * scale, 0.24, 0.1, -spin * 1.4)
			for i, p in portalArms do
				local arm = (i - 1) % 3
				local step = (i - 1 - arm) / 3 + 1 -- 1..8 from the rim to the middle
				local a = arm / 3 * math.pi * 2 + spin * 1.8 + step * 0.42
				local r = 5.4 * scale * (1 - step / 9)
				p.Size = Vector3.new(0.3, 0.1, math.max(0.2, 1.5 * scale))
				place(p, center * CFrame.Angles(0, a, 0) * CFrame.new(r, 0, 0))
			end
			local d = 10.6 * scale
			portalHeart.Size = Vector3.new(0.16, d, d)
			portalHeart.Transparency = 0.72 - 0.3 * math.sin(clamp01(opening) * math.pi)
			place(portalHeart, center * CFrame.Angles(0, 0, math.pi / 2))
			poseColumn(shaft, 0, 0, 0, PORTAL_Y, 1.6 + 2.4 * scale, 0.88 + 0.1 * closing)
		else
			hideRing(portalOuter)
			hideRing(portalInner)
			for _, p in portalArms do
				hide(p)
			end
			hide(portalHeart)
			-- (at the end the shaft comes back: the column of light under the blaster)
			local column = prog(t, T_RISE, T_RISE + 0.4) * (1 - prog(t, T_HOLD + 0.2, Stage.Duration))
			if column > 0.01 then
				poseColumn(shaft, 0, 0, 0, gunRest - 2.4, 1.6, 1 - column * 0.1)
			else
				hide(shaft)
			end
		end

		-- the crate: shoots out of the portal, slams down, squashes, hovers, shakes, drops back open
		local shown = t >= T_FALL and t < T_RISE
		local fall = prog(t, T_FALL, T_LAND)
		local y = lerp(PORTAL_Y - caseTop / 2, 0, easeInCubic(fall))
		local squash = 1
		if t > T_LAND then
			local u = t - T_LAND
			y = if u < 0.26 then math.sin(u / 0.26 * math.pi) * 0.5 else 0
			squash = 1 - 0.18 * math.exp(-u * 10) * math.cos(u * 30)
		end
		local hover = easeInOut(prog(t, T_IMPACT, T_ORBIT)) * (1 - easeOutCubic(prog(t, T_BURST, T_BURST + 0.2)))
		y += hover * (0.7 + 0.12 * math.sin(t * 5))
		y -= easeInCubic(prog(t, T_RISE - 0.45, T_RISE)) * (caseTop + 1) -- at the end it sinks into the platform
		local rumble = if t > T_ORBIT and t < T_BURST then charge ^ 1.5 else 0
		local caseCf = origin
			* CFrame.new(math.sin(t * 61) * 0.06 * rumble, y, math.cos(t * 67) * 0.06 * rumble)
			* CFrame.Angles(math.sin(t * 47) * 0.05 * rumble + 0.04 * hover * math.sin(t * 3), 0, math.sin(t * 53 + 1) * 0.06 * rumble)
		local sq = Vector3.new(2 - squash, squash, 2 - squash)
		local function scaled(rel: CFrame): CFrame
			return CFrame.new(rel.Position * sq) * rel.Rotation
		end
		if shown then
			for _, r in baseParts do
				place(r.p, caseCf * scaled(r.rel))
			end
			-- the walls fold out at the burst, with an overshoot
			local open = prog(t, T_BURST, T_BURST + 0.3)
			local fold = (if open > 0 then easeOutBack(open) else 0) * 1.75
			for _, panel in panelParts do
				local hingeCf = caseCf * scaled(panel.hinge) * CFrame.Angles(panel.fold.X * fold, 0, panel.fold.Z * fold)
				local inv = panel.hinge:Inverse()
				for _, r in panel.parts do
					place(r.p, hingeCf * inv * scaled(r.rel))
				end
			end
			-- the lid: two halves fly up and apart, turning
			local lift = t - T_BURST
			for i, half in lidParts do
				local sz = if i == 1 then -1 else 1
				if lift > 1.0 then
					for _, r in half do
						hide(r.p)
					end
				else
					local off, turn = Vector3.zero, CFrame.identity
					if lift > 0 then
						local e = 1 - math.exp(-lift * 6)
						off = Vector3.new(0, 9 * e + 3 * lift, sz * 7.5 * e)
						turn = CFrame.Angles(sz * lift * 2.4, 0, lift * 1.2)
					end
					local pivot = CFrame.new(0, case.Height - 0.5, sz * case.Length / 4)
					local frame = caseCf * CFrame.new(off) * pivot * turn * pivot:Inverse()
					for _, r in half do
						place(r.p, frame * scaled(r.rel))
					end
				end
			end
		else
			for _, r in baseParts do
				hide(r.p)
			end
			for _, panel in panelParts do
				for _, r in panel.parts do
					hide(r.p)
				end
			end
			for _, half in lidParts do
				for _, r in half do
					hide(r.p)
				end
			end
		end
		-- its lights: pulse from the hover on, brighter and whiter with the charge
		local pulsing = t >= T_IMPACT and t < T_BURST
		if pulsing or (t >= T_BURST and t < T_BURST + 0.1) then
			local pulse = 0.5 + 0.5 * math.sin(t * (6 + 10 * charge)) -- (under 3 a second)
			for _, l in lightColors do
				l.p.Color = l.color:Lerp(WHITE, charge * 0.6)
				l.p.Transparency = if pulsing then 0.35 * (1 - charge) * pulse else 0
			end
		end
		case.Seam.Transparency = if t < T_BURST then 1 - (0.1 + 0.9 * charge) else 1
		case.Inside.Transparency = if t >= T_BURST then 0.1 + prog(t, T_BURST + 0.5, T_RISE) * 0.6 else 1
		coreLight.Brightness = if t < T_BURST then 0.6 * lit + charge * 5 else (9 * math.exp(-(t - T_BURST) * 3) + 1.5) * (1 - fadeOut)
		coreHolder.CFrame = at(0, 2.2 + hover * 0.7, 0)

		-- the fall's motion blur: see-through copies behind the crate, speed lines
		local falling = t >= T_FALL and t < T_LAND + 0.06
		for i, g in ghosts do
			if falling then
				local back = i * 1.5 * (0.4 + fall)
				g.Transparency = 0.72 + i * 0.06
				place(g, origin * CFrame.new(0, y + caseTop / 2 + back, 0))
			else
				hide(g)
			end
		end
		for i, line in speedLines do
			if falling then
				local run = ((t * 60 + i * 3.7) % 18)
				line.p.Size = Vector3.new(0.1, line.len, 0.1)
				line.p.Transparency = 0.2
				place(line.p, at(line.x, PORTAL_Y - run, line.z))
			else
				hide(line.p)
			end
		end

		-- the impact: the energy wave, the shockwaves on the floor
		local waveT = prog(t, T_LAND, T_LAND + 0.24)
		if t >= T_LAND and waveT < 1 then
			local d = lerp(5, 21, easeOutCubic(waveT))
			wave.Size = Vector3.new(d, d, d)
			wave.Transparency = lerp(0.93, 1, waveT)
			place(wave, at(0, 1.5, 0))
		else
			hide(wave)
		end
		for i, w in waves do
			local t0 = if i == 1 then T_LAND elseif i == 2 then T_LAND + 0.08 elseif i == 3 then T_BURST else T_BURST + 0.1
			local dur = if i <= 2 then 0.55 else 0.9
			local size = if i <= 2 then 9 + i * 2 else 15
			local u = prog(t, t0, t0 + dur)
			if t >= t0 and u < 1 then
				poseRing(w, at(0, 0.08, 0), lerp(0.75, size, easeOutCubic(u)), lerp(0.7, 0.18, u), u, 0)
			else
				hideRing(w)
			end
		end
		do
			local u = prog(t, T_BURST, T_BURST + 0.5)
			if t >= T_BURST and u < 1 then
				local center = CFrame.lookAt((origin * CFrame.new(0, caseTop + 0.5, 0)).Position, camCf.Position)
					* CFrame.Angles(math.pi / 2, 0, 0)
				poseRing(burstRing, center, lerp(0.5, 13, easeOutCubic(u)), lerp(0.6, 0.15, u), u, 0)
			else
				hideRing(burstRing)
			end
		end

		-- the hover: two neon rings turning under the crate
		local under = easeOutCubic(prog(t, T_IMPACT, T_IMPACT + 0.35)) * (1 - prog(t, T_BURST, T_BURST + 0.25))
		if under > 0.01 then
			poseRing(underA, at(0, 0.16, 0), 4.7 * under, 0.2, 0.1, t * 3)
			poseRing(underB, at(0, 0.3, 0), 5.9 * under, 0.13, 0.15, -t * 4.5)
		else
			hideRing(underA)
			hideRing(underB)
		end

		-- the blaster: flies out of the light, turning slowly, then floats at its hero angle
		local rise = prog(t, T_BURST + 0.08, T_RISE)
		local out = t > T_BURST + 0.06
		local bob = math.sin(clock * 2.1) * 0.14 * prog(t, T_RISE - 0.3, T_RISE + 0.3)
		local turning = (1 - easeOutCubic(rise)) * math.pi * 2 * 1.4
		-- "se ještě jednou otočí": one more turn when it is collected
		local last = easeInOut(prog(t, T_HOLD, Stage.Duration)) * math.pi * 2
		local gunScale = lerp(0.35, 1, easeOutCubic(prog(t, T_BURST, T_BURST + 0.7)))
		local gunCf = origin
			* CFrame.new(0, lerp(caseTop - 1.2, gunRest, easeOutCubic(rise)) + bob, 0)
			* CFrame.Angles(0, -0.2 + turning + last + 0.09 * math.sin(clock * 0.9), 0)
			* CFrame.Angles(0.22 + 0.04 * math.sin(clock * 1.3), 0, 0.04 * math.sin(clock * 1.7))
		for _, r in gunParts do
			if out then
				place(r.p, gunCf * CFrame.new(r.rel.Position * gunScale) * r.rel.Rotation)
				if gunScale < 1 or r.p.Size ~= gunBase[r.p] then
					r.p.Size = gunBase[r.p] * gunScale
				end
			else
				hide(r.p)
			end
		end
		-- its glow: white-hot out of the crate, a strong pulse at the reveal
		local gunGlow = if t > T_BURST then 0.7 * math.exp(-math.max(0, t - T_BURST - 0.25) * 2.2) else 0
		gunGlow += if t >= T_RISE then 0.45 * math.exp(-(t - T_RISE) * 3.5) else 0
		for _, n in gunNeon do
			n.p.Color = n.color:Lerp(WHITE, gunGlow * 0.45)
		end
		gunHolder.CFrame = gunCf * CFrame.new(3.5, 2.5, 3)
		gunLight.Brightness = if out then (1.2 + 0.3 * math.sin(clock * 4) + 2 * gunGlow) * (1 - fadeOut * 0.6) else 0

		-- behind the blaster, facing the camera: the god rays
		local toCam = (camCf.Position - gunCf.Position).Unit
		local behind = gunCf.Position - toCam * 4
		local raysIn = easeOutCubic(prog(t, T_BURST, T_BURST + 0.35))
		if raysIn > 0.01 and t < T_RISE + 0.05 then
			local frame = CFrame.lookAt(behind - toCam * 2, behind - toCam * 3) * CFrame.Angles(0, 0, clock * 0.35)
			local len = lerp(2, 15, raysIn)
			-- (for the burst and the flight: at the reveal only the blaster counts)
			local alpha = raysIn * 0.16 * (1 - prog(t, T_RISE - 0.3, T_RISE + 0.05))
			for i, p in rays do
				local a = (i - 1) / #rays * math.pi * 2
				local w = 0.16 + (i % 3) * 0.16
				p.Size = Vector3.new(w, len, 0.05)
				p.Transparency = 1 - alpha
				place(p, frame * CFrame.Angles(0, 0, a) * CFrame.new(0, len / 2 + 1.2, 0))
			end
		else
			for _, p in rays do
				hide(p)
			end
		end

		-- the comet arcs: round the crate from the hover on, round the blaster after the burst
		local arcsIn = (
			if t < T_BURST then easeOutCubic(prog(t, T_IMPACT, T_IMPACT + 0.3)) else easeOutCubic(prog(t, T_OPEN - 0.1, T_OPEN + 0.25))
		) * (1 - fadeOut)
		if arcsIn > 0.01 then
			local center = CFrame.new(if t < T_BURST then at(0, 2.2 + hover, 0).Position else gunCf.Position)
			local r0 = if t < T_BURST then 6.6 else 4.8
			poseRing(arcA, center * CFrame.Angles(0.5, 0, 0.42), r0 * arcsIn, 0.16, 0.08, clock * 3.4)
			poseRing(arcB, center * CFrame.Angles(-0.42, 0, -0.5), (r0 + 1.1) * arcsIn, 0.12, 0.15, -clock * 2.6)
		else
			hideRing(arcA)
			hideRing(arcB)
		end

		-- charging: rays pour in, small portals open round the crate
		for _, m in mini do
			local u = easeOutBack(prog(t, m.t0, m.t0 + 0.2))
			if t >= m.t0 and t < T_BURST then
				local p = at(m.at.X, m.at.Y, m.at.Z)
				local target = (origin * CFrame.new(0, 2.2 + hover, 0)).Position
				local face = CFrame.lookAt(p.Position, target) * CFrame.Angles(math.pi / 2, 0, 0)
				poseRing(m.ring, face, 1.3 * u, 0.2, 0, clock * 7)
				m.heart.Size = Vector3.new(0.1, 2.4 * u, 2.4 * u)
				m.heart.Transparency = 0.45
				place(m.heart, CFrame.lookAt(p.Position, target) * CFrame.Angles(0, math.pi / 2, 0))
				local line = target - p.Position
				local len = line.Magnitude * prog(t, m.t0 + 0.1, m.t0 + 0.3)
				if len > 0.05 then
					local d = 0.1 + 0.14 * charge
					m.ray.Size = Vector3.new(len, d, d)
					m.ray.Transparency = 0.35 - 0.25 * charge
					place(m.ray, CFrame.lookAt(p.Position + line.Unit * (len / 2), target) * CFrame.Angles(0, math.pi / 2, 0))
				else
					hide(m.ray)
				end
			else
				hideRing(m.ring)
				hide(m.heart)
				hide(m.ray)
			end
		end

		-- the light pillar out of the open crate
		local pIn = easeOutCubic(prog(t, T_BURST, T_BURST + 0.14))
		local pOut = 1 - prog(t, T_BURST + 0.3, T_RISE - 0.1)
		local swell = 1 + 0.7 * math.exp(-(t - T_BURST) * 5)
		if t >= T_BURST and pIn * pOut > 0.01 then
			local h = 40 * pIn
			poseColumn(pillarCore, 0, caseTop - 1, 0, h, 1.5 * swell, 1 - pIn * pOut * 0.8)
			poseColumn(pillarWide, 0, caseTop - 1, 0, h, 4.4 * swell, 1 - pIn * pOut * 0.3)
		else
			hide(pillarCore)
			hide(pillarWide)
		end

		-- the platform of light under the blaster
		local floorIn = easeOutBack(prog(t, T_OPEN + 0.05, T_OPEN + 0.4))
		local floorOut = 1 - prog(t, T_HOLD + 0.1, Stage.Duration)
		if t >= T_OPEN + 0.05 and floorOut > 0.01 then
			local y0 = gunRest - 2.5
			poseRing(lightRing, at(0, y0, 0), 3.8 * floorIn, 0.16, 1 - floorOut, clock)
			poseRing(lightInner, at(0, y0, 0), 2.6 * floorIn, 0.1, 1 - floorOut * 0.8, -clock * 1.6)
		else
			hideRing(lightRing)
			hideRing(lightInner)
		end

		-- the energy particles circling the blaster
		local orbitIn = prog(t, T_OPEN - 0.05, T_OPEN + 0.25) * (1 - fadeOut)
		for _, o in orbiters do
			if orbitIn > 0.01 then
				local a = o.phase + clock * o.speed
				local d = o.size * orbitIn
				o.p.Size = Vector3.new(d, d, d)
				local pos = gunCf.Position + (CFrame.Angles(o.tilt, 0, o.tilt * 0.5) * Vector3.new(math.cos(a) * o.r, 0, math.sin(a) * o.r))
				place(o.p, CFrame.new(pos))
			else
				hide(o.p)
			end
		end

		-- pieces of the crate fly out
		for _, sh in shards do
			local a = t - T_BURST - sh.delay
			if a > 0 and a < 1.1 then
				local pos = Vector3.new(0, caseTop * 0.7, 0) + sh.dir * sh.speed * a + Vector3.new(0, -9 * a * a, 0)
				local s = sh.size * (1 - prog(a, 0.7, 1.1))
				sh.p.Size = Vector3.new(s, s * 0.8, s * 1.2)
				place(sh.p, origin * CFrame.new(pos) * CFrame.Angles(sh.spin.X * a, sh.spin.Y * a, sh.spin.Z * a))
			else
				hide(sh.p)
			end
		end
		-- sparks with gravity and a trail
		for _, sp in sparks do
			local a = t - sp.t0 - sp.delay
			local u = a / sp.life
			if u > 0 and u < 1 then
				local function where(x: number): Vector3
					local drag = (1 - math.exp(-x * 2.2)) / 2.2
					return Vector3.new(
						sp.dir.X * sp.speed * drag,
						sp.y + sp.dir.Y * sp.speed * drag - 4.5 * x * x,
						sp.dir.Z * sp.speed * drag
					)
				end
				local head, tail = where(a), where(math.max(0, a - 0.05))
				local len = math.max(0.1, (head - tail).Magnitude)
				sp.p.Size = Vector3.new(0.12, 0.12, len)
				sp.p.Transparency = u * 0.8
				place(sp.p, origin * CFrame.lookAt((head + tail) / 2, head))
			else
				hide(sp.p)
			end
		end
		-- energy pulled toward the crate (at the very start toward the platform)
		for _, st in streaks do
			local u = (t - st.t0) / st.dur
			if u > 0 and u < 1 and t < T_BURST then
				local function where(v: number): Vector3
					local k = (1 - v) ^ 1.7
					local th = st.th + v * 2.4
					return Vector3.new(
						math.sin(st.ph) * math.cos(th) * st.r * k,
						1.8 + hover + math.cos(st.ph) * st.r * k * 0.8,
						math.sin(st.ph) * math.sin(th) * st.r * k
					)
				end
				local head, tail = where(u), where(math.max(0, u - 0.06))
				local len = math.max(0.1, (head - tail).Magnitude)
				st.p.Size = Vector3.new(0.1, 0.1, len)
				st.p.Transparency = 1 - math.sin(u * math.pi)
				place(st.p, origin * CFrame.lookAt((head + tail) / 2, head))
			else
				hide(st.p)
			end
		end
		-- the floating rocks: drift round, thrown back by the impact and the burst
		local push = 3 * flareLand
			+ 11 * (if t >= T_BURST then easeOutCubic(prog(t, T_BURST, T_BURST + 0.5)) * math.exp(-(t - T_BURST) * 0.5) else 0)
		for _, rock in rocks do
			local a = rock.a + clock * rock.speed
			local r = rock.r + push
			place(
				rock.p,
				at(math.cos(a) * r, rock.y + 0.5 * math.sin(clock * 0.9 + rock.a) + push * 0.25, math.sin(a) * r)
					* CFrame.Angles(rock.spin.X * clock + rock.a, rock.spin.Y * clock, rock.spin.Z * clock)
			)
		end

		local bulk = self.bulk
		if bulk then
			bulk(moveParts, moveFrames)
		else
			for i, p in moveParts do
				p.CFrame = moveFrames[i]
			end
		end
		table.clear(moveParts)
		table.clear(moveFrames)
	end

	self.update(0)
	return self :: Stage
end

return Stage
