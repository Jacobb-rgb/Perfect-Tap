--[[
	Blaster design proposals for the owner (2026-10): three clean styles for
	the laser blasters and three ways to display them, rendered with the
	preview pipeline. Prototype only: the game still uses BlasterBuilder.

	  A  Soft      rounded side profiles, ore color + bone white + graphite
	               (the clean toy look of current Roblox shooters);
	               floating guns on hero pedestals in a dark studio
	  B  Tactical  dark graphite with ore-colored armor shells and neon seams,
	               sharp chamfered low-poly profiles; an armory wall with lit niches
	  C  Core      pearl white with ore accents and a glass chamber holding the
	               glowing ore crystal; a white gallery with glass cases

	Each style shows levels 1, 5 and 10. Scene "blaster_concepts"
	(lune run tools/lune/export_scene.luau blaster_concepts), shots in
	tools/preview/blaster_concept_shots.json.

	Gun design frame (studs, held size): barrel along -Z, +Y up, +X is the
	gun's right side, the top of the grip at the origin.
]]

local roblox = require("@lune/roblox") :: any

local Concepts = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass

local CF: any -- Loader.CFrame (set in Concepts.build)
local Geo: any

---------------------------------------------------------------- part kit

local function kit(model: any)
	local K = {}
	local ALONG_Z = nil :: any

	local function part(className: string, cf: any, size: any, color: any, mat: any?, shape: any?)
		local p = roblox.Instance.new(className)
		p.Anchored = true
		p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = mat or SMOOTH
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Parent = model
		return p
	end
	K.part = part

	function K.boxCF(cf: any, size: any, color: any, mat: any?)
		return part("Part", cf, size, color, mat)
	end

	-- a box from side-profile ranges, width w, centered on x = dx
	function K.box(z0: number, z1: number, y0: number, y1: number, w: number, color: any, mat: any?, dx: number?)
		return part("Part", CF.new(dx or 0, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(w, y1 - y0, z1 - z0), color, mat)
	end

	-- a cylinder along the local X axis of cf
	function K.cylCF(cf: any, length: number, d: number, color: any, mat: any?)
		return part("Part", cf, V3.new(length, d, d), color, mat, Enum.PartType.Cylinder)
	end

	-- a cylinder along Z (barrels, scopes, rings)
	function K.tube(z0: number, z1: number, y: number, d: number, color: any, mat: any?, dx: number?)
		ALONG_Z = ALONG_Z or CF.Angles(0, math.pi / 2, 0)
		return K.cylCF(CF.new(dx or 0, y, (z0 + z1) / 2) * ALONG_Z, z1 - z0, d, color, mat)
	end

	-- a round light / bezel seen on both sides (axis along X)
	function K.dot(z: number, y: number, d: number, w: number, color: any, mat: any?)
		return K.cylCF(CF.new(0, y, z), w, d, color, mat)
	end

	-- a box whose side-profile corners are rounded (the edges along X), radius r
	function K.rboxCF(cf: any, size: any, r: number, color: any, mat: any?)
		local W, H, D = size.X, size.Y, size.Z
		r = math.min(r, H / 2, D / 2)
		if r < 0.01 then
			return K.boxCF(cf, size, color, mat)
		end
		local e = 0.002
		if H - 2 * r > e then
			K.boxCF(cf, V3.new(W, H - 2 * r, D), color, mat)
		end
		if D - 2 * r > e then
			K.boxCF(cf, V3.new(W, H, D - 2 * r), color, mat)
		end
		local ys = if H - 2 * r > e then { -1, 1 } else { 0 }
		local zs = if D - 2 * r > e then { -1, 1 } else { 0 }
		for _, sy in ys do
			for _, sz in zs do
				K.cylCF(cf * CF.new(0, sy * (H / 2 - r), sz * (D / 2 - r)), W, 2 * r, color, mat)
			end
		end
		return nil
	end

	function K.rbox(z0: number, z1: number, y0: number, y1: number, w: number, r: number, color: any, mat: any?, dx: number?)
		return K.rboxCF(CF.new(dx or 0, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(w, y1 - y0, z1 - z0), r, color, mat)
	end

	-- the frame of a grip / magazine: top center at (z, y), its axis `length` long and
	-- tilted by `tilt` (negative = the bottom leans back); returns the center CFrame
	function K.gripCF(z: number, y: number, length: number, tilt: number)
		return CF.new(0, y, z) * CF.Angles(tilt, 0, 0) * CF.new(0, -length / 2, 0)
	end

	-- a rounded grip / magazine
	function K.grip(z: number, y: number, length: number, depth: number, w: number, r: number, tilt: number, color: any, mat: any?)
		local cf = K.gripCF(z, y, length, tilt)
		K.rboxCF(cf, V3.new(w, length, depth), r, color, mat)
		return cf
	end

	-- a convex side-profile polygon { {z, y}, ... } extruded to width w (sharp low-poly facets)
	function K.prism(points: { { number } }, w: number, color: any, mat: any?, dx: number?)
		local x = dx or 0
		local p1 = V3.new(x, points[1][2], points[1][1])
		for i = 2, #points - 1 do
			local a = V3.new(x, points[i][2], points[i][1])
			local b = V3.new(x, points[i + 1][2], points[i + 1][1])
			Geo.triangle(model, p1, a, b, w, color, mat or SMOOTH, nil, { CanCollide = false })
		end
	end

	--[[
		A convex side-profile polygon { {z, y}, ... } with rounded corners (radius r),
		extruded to width w: the polygon shrunk by r (a prism), a slab along every
		edge and a cylinder on every corner (the Minkowski sum with a disc).
	]]
	function K.rpoly(points: { { number } }, w: number, r: number, color: any, mat: any?, dx: number?)
		local n = #points
		local area = 0
		for i = 1, n do
			local a, b = points[i], points[i % n + 1]
			area += a[1] * b[2] - b[1] * a[2]
		end
		local sign = if area > 0 then 1 else -1
		-- every edge moved inward by r: a point on it and its direction
		local lines = {}
		for i = 1, n do
			local a, b = points[i], points[i % n + 1]
			local du, dv = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(du * du + dv * dv)
			du, dv = du / len, dv / len
			local nu, nv = -dv * sign, du * sign -- inward normal
			lines[i] = { a[1] + nu * r, a[2] + nv * r, du, dv, -nu, -nv }
		end
		local inner = {}
		for i = 1, n do
			local l1, l2 = lines[(i - 2) % n + 1], lines[i]
			local cross = l1[3] * l2[4] - l1[4] * l2[3]
			local bu, bv = l2[1] - l1[1], l2[2] - l1[2]
			local t = (bu * l2[4] - bv * l2[3]) / cross
			inner[i] = { l1[1] + l1[3] * t, l1[2] + l1[4] * t }
		end
		local x = dx or 0
		K.prism(inner, w, color, mat, dx)
		for i = 1, n do
			local a, b = inner[i], inner[i % n + 1]
			local l = lines[i]
			local du, dv = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(du * du + dv * dv)
			local up = V3.new(0, l[6], l[5])
			local center = V3.new(x, (a[2] + b[2]) / 2 + l[6] * r / 2, (a[1] + b[1]) / 2 + l[5] * r / 2)
			if len > 0.004 then
				part("Part", CF.fromMatrix(center, V3.new(1, 0, 0), up), V3.new(w, r + 0.004, len + 0.004), color, mat)
			end
			K.cylCF(CF.new(x, a[2], a[1]), w, 2 * r, color, mat)
		end
	end

	-- a glowing ore crystal along Z: a diamond-section rod with pointed ends
	function K.crystal(z0: number, z1: number, y: number, d: number, color: any)
		local len = z1 - z0
		local mid = CF.new(0, y, (z0 + z1) / 2)
		local s = d / math.sqrt(2)
		part("Part", mid * CF.Angles(0, 0, math.pi / 4), V3.new(s, s, len * 0.62), color, NEON)
		for _, side in { -1, 1 } do
			-- the tips: a smaller rod, then a tiny one (a stepped point)
			part(
				"Part",
				mid * CF.new(0, 0, side * len * 0.36) * CF.Angles(0, 0, math.pi / 4),
				V3.new(s * 0.62, s * 0.62, len * 0.16),
				color,
				NEON
			)
			part(
				"Part",
				mid * CF.new(0, 0, side * len * 0.46) * CF.Angles(0, 0, math.pi / 4),
				V3.new(s * 0.3, s * 0.3, len * 0.08),
				color,
				NEON
			)
		end
	end

	return K
end

---------------------------------------------------------------- palettes

local BONE = C3.fromRGB(234, 231, 226)
local GRAPHITE = C3.fromRGB(44, 46, 54)
local GRAPHITE_SOFT = C3.fromRGB(66, 69, 80) -- grip panels
local GUNMETAL = C3.fromRGB(84, 88, 100)
local TAC_DARK = C3.fromRGB(46, 49, 58)
local TAC_MID = C3.fromRGB(70, 74, 86)
local PEARL = C3.fromRGB(240, 241, 245)
local PEARL_GREY = C3.fromRGB(196, 201, 212)
local CORE_DARK = C3.fromRGB(58, 62, 74)
local GOLD = C3.fromRGB(226, 182, 84)

type Colors = { main: any, light: any, dark: any, metal: any, glow: any, glowSoft: any, accent: any, trim: any, core: any? }

local function colorsFor(Loader: any, style: string, level: number, oreId: string): Colors
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local look = BlasterBuilder.look(level, oreId)
	local ore = look.Body
	if style == "A" then
		return {
			main = ore,
			light = BONE,
			dark = GRAPHITE,
			metal = GUNMETAL,
			glow = look.GlowCore,
			glowSoft = look.GlowSoft,
			accent = look.Accent,
			trim = GRAPHITE_SOFT,
		}
	elseif style == "B" then
		return {
			main = TAC_DARK,
			light = TAC_MID,
			dark = C3.fromRGB(30, 32, 38),
			metal = GUNMETAL,
			glow = look.GlowCore,
			glowSoft = look.GlowSoft,
			accent = ore,
			trim = TAC_MID,
		}
	end
	return {
		main = PEARL,
		light = PEARL_GREY,
		dark = CORE_DARK,
		metal = PEARL_GREY,
		glow = look.GlowCore,
		glowSoft = look.GlowSoft,
		accent = ore,
		trim = if level >= 10 then GOLD else ore,
		core = ore:Lerp(C3.new(0, 0, 0), 0.22), -- the crystal: saturated, so it glows in its color
	}
end

---------------------------------------------------------------- style A: Soft

local A = {}

function A.pistol(K: any, c: Colors)
	-- slide: a slightly raked front, rounded corners, serrations at the back
	K.rpoly({ { -1.30, 0.30 }, { 0.56, 0.30 }, { 0.52, 0.80 }, { -1.20, 0.80 } }, 0.40, 0.10, c.main)
	for i = 0, 3 do
		local z = 0.16 + i * 0.09
		K.box(z - 0.02, z + 0.02, 0.46, 0.74, 0.41, c.accent)
	end
	K.box(-1.02, -0.06, 0.52, 0.56, 0.41, c.glow, NEON) -- glow line
	-- frame with a raked dust cover
	K.rpoly({ { -1.08, 0.36 }, { 0.50, 0.36 }, { 0.50, 0.04 }, { -0.70, 0.02 }, { -1.08, 0.16 } }, 0.36, 0.06, c.light)
	K.tube(-1.40, -1.22, 0.55, 0.24, c.dark) -- muzzle
	K.tube(-1.41, -1.37, 0.55, 0.13, c.glow, NEON)
	K.rbox(0.34, 0.50, 0.76, 0.88, 0.20, 0.05, c.dark) -- sights
	K.box(-1.12, -1.04, 0.76, 0.86, 0.08, c.dark)
	-- grip with a textured panel
	K.rpoly({ { -0.02, 0.10 }, { 0.48, 0.10 }, { 0.74, -0.90 }, { 0.22, -0.94 } }, 0.36, 0.12, c.dark)
	K.rpoly({ { 0.08, -0.16 }, { 0.42, -0.16 }, { 0.62, -0.80 }, { 0.26, -0.82 } }, 0.38, 0.07, c.trim)
	-- trigger guard and trigger
	K.rbox(-0.56, 0.02, -0.30, -0.21, 0.12, 0.045, c.dark)
	K.rpoly({ { -0.60, 0.04 }, { -0.48, 0.04 }, { -0.46, -0.28 }, { -0.58, -0.28 } }, 0.12, 0.03, c.dark)
	K.boxCF(CF.new(0, -0.07, -0.22) * CF.Angles(-0.25, 0, 0), V3.new(0.06, 0.24, 0.06), c.light)
end

function A.carbine(K: any, c: Colors)
	-- upper receiver, lower receiver, a handguard tapering to the front
	K.rpoly({ { -1.50, 0.30 }, { 0.95, 0.30 }, { 0.95, 0.86 }, { -1.36, 0.86 }, { -1.50, 0.72 } }, 0.46, 0.10, c.main)
	K.rpoly({ { -0.95, 0.34 }, { 0.78, 0.34 }, { 0.78, 0.04 }, { -0.62, 0.00 }, { -0.95, 0.10 } }, 0.42, 0.07, c.light)
	K.rpoly({ { -1.36, 0.22 }, { -1.36, 0.80 }, { -2.42, 0.72 }, { -2.48, 0.30 } }, 0.42, 0.12, c.light)
	for i = 0, 2 do
		local z = -2.10 + i * 0.22
		K.rbox(z - 0.05, z + 0.05, 0.42, 0.60, 0.43, 0.04, c.glow, NEON)
	end
	-- barrel and a squared muzzle device
	K.tube(-2.85, -2.40, 0.50, 0.20, c.metal, METAL)
	K.rpoly({ { -3.10, 0.34 }, { -2.80, 0.30 }, { -2.80, 0.70 }, { -3.10, 0.66 } }, 0.32, 0.06, c.dark)
	K.tube(-3.11, -3.06, 0.50, 0.16, c.glow, NEON)
	-- top rail with notches and a reflex sight
	K.box(-1.30, 0.80, 0.86, 0.92, 0.22, c.dark)
	for i = 0, 8 do
		local z = -1.20 + i * 0.24
		K.box(z - 0.05, z + 0.05, 0.92, 0.96, 0.24, c.dark)
	end
	K.rpoly({ { -0.66, 0.94 }, { -0.12, 0.94 }, { -0.18, 1.30 }, { -0.66, 1.30 } }, 0.30, 0.08, c.dark)
	K.box(-0.69, -0.64, 1.02, 1.22, 0.20, c.glow, NEON)
	-- charging handle, power light, glow line
	K.box(0.66, 0.92, 0.70, 0.78, 0.52, c.dark)
	K.dot(0.42, 0.56, 0.26, 0.47, c.dark)
	K.dot(0.42, 0.56, 0.16, 0.48, c.glow, NEON)
	K.box(-1.30, 0.18, 0.68, 0.72, 0.47, c.glowSoft, NEON)
	-- grip, a magazine curving forward with a glow window, trigger guard
	K.rpoly({ { 0.18, 0.06 }, { 0.68, 0.06 }, { 0.92, -0.86 }, { 0.42, -0.90 } }, 0.36, 0.12, c.dark)
	K.rpoly({ { -0.80, 0.04 }, { -0.36, 0.04 }, { -0.50, -0.86 }, { -0.92, -0.80 } }, 0.32, 0.08, c.main)
	K.boxCF(CF.new(0, -0.40, -0.63) * CF.Angles(0.15, 0, 0), V3.new(0.33, 0.06, 0.30), c.glow, NEON)
	K.rbox(-0.30, 0.20, -0.30, -0.21, 0.12, 0.045, c.dark)
	-- stock: tapered, a cut-out, a dark pad
	K.rpoly({ { 0.90, 0.16 }, { 0.90, 0.84 }, { 1.88, 0.78 }, { 1.88, 0.06 } }, 0.40, 0.12, c.main)
	K.rpoly({ { 1.08, 0.34 }, { 1.08, 0.62 }, { 1.58, 0.60 }, { 1.58, 0.30 } }, 0.41, 0.10, c.dark)
	K.rbox(1.82, 1.98, 0.00, 0.86, 0.42, 0.07, c.dark)
end

function A.rifle(K: any, c: Colors)
	K.rpoly({ { -1.70, 0.28 }, { 1.05, 0.28 }, { 1.05, 0.92 }, { -1.52, 0.92 }, { -1.70, 0.76 } }, 0.50, 0.12, c.main)
	K.rpoly({ { -1.20, 0.32 }, { 0.85, 0.32 }, { 0.85, 0.02 }, { -0.90, -0.02 }, { -1.20, 0.10 } }, 0.44, 0.07, c.light)
	K.rpoly({ { -1.60, 0.20 }, { -1.60, 0.86 }, { -3.30, 0.78 }, { -3.36, 0.30 } }, 0.44, 0.14, c.light)
	for i = 0, 3 do
		local z = -2.95 + i * 0.24
		K.rbox(z - 0.05, z + 0.05, 0.42, 0.64, 0.45, 0.04, c.glow, NEON)
	end
	-- barrel, a ring, a big muzzle brake
	K.tube(-4.05, -3.20, 0.54, 0.22, c.metal, METAL)
	K.tube(-3.80, -3.66, 0.54, 0.30, c.main)
	K.rpoly({ { -4.45, 0.34 }, { -4.00, 0.30 }, { -4.00, 0.78 }, { -4.45, 0.74 } }, 0.38, 0.08, c.main)
	K.box(-4.36, -4.08, 0.50, 0.58, 0.39, c.dark)
	K.tube(-4.46, -4.40, 0.54, 0.16, c.glow, NEON)
	-- energy core on the side, glow lines
	K.dot(-0.40, 0.60, 0.52, 0.51, c.dark)
	K.dot(-0.40, 0.60, 0.42, 0.515, c.light)
	K.dot(-0.40, 0.60, 0.30, 0.52, c.glow, NEON)
	K.box(-1.50, -0.72, 0.74, 0.78, 0.505, c.glowSoft, NEON)
	K.box(-0.08, 0.85, 0.74, 0.78, 0.505, c.glowSoft, NEON)
	-- top rail with notches
	K.box(-1.50, 0.85, 0.92, 0.98, 0.22, c.dark)
	for i = 0, 9 do
		local z = -1.40 + i * 0.25
		K.box(z - 0.05, z + 0.05, 0.98, 1.02, 0.24, c.dark)
	end
	-- scope on two rounded mounts
	K.rpoly({ { -1.05, 0.98 }, { -0.75, 0.98 }, { -0.80, 1.14 }, { -1.00, 1.14 } }, 0.22, 0.04, c.dark)
	K.rpoly({ { -0.05, 0.98 }, { 0.25, 0.98 }, { 0.20, 1.14 }, { 0.00, 1.14 } }, 0.22, 0.04, c.dark)
	K.tube(-1.30, 0.40, 1.28, 0.36, c.dark)
	K.tube(-1.52, -1.25, 1.28, 0.48, c.dark)
	K.tube(-1.53, -1.49, 1.28, 0.36, c.glow, NEON)
	K.tube(0.35, 0.55, 1.28, 0.30, c.dark)
	K.tube(-0.55, -0.45, 1.28, 0.38, c.main)
	-- grip, foregrip, trigger guard
	K.rpoly({ { 0.26, 0.06 }, { 0.76, 0.06 }, { 1.00, -0.86 }, { 0.50, -0.90 } }, 0.36, 0.12, c.dark)
	K.rpoly({ { -2.50, 0.26 }, { -2.08, 0.26 }, { -2.14, -0.32 }, { -2.44, -0.32 } }, 0.28, 0.10, c.dark)
	K.rbox(-0.22, 0.28, -0.30, -0.21, 0.12, 0.045, c.dark)
	-- long stock: cheek riser, cut-out, dark pad
	K.rpoly({ { 1.00, 0.14 }, { 1.00, 0.90 }, { 2.36, 0.84 }, { 2.36, -0.02 } }, 0.42, 0.14, c.main)
	K.rpoly({ { 1.30, 0.86 }, { 2.10, 0.84 }, { 2.04, 1.02 }, { 1.40, 1.04 } }, 0.36, 0.06, c.main)
	K.rpoly({ { 1.25, 0.34 }, { 1.25, 0.62 }, { 1.95, 0.60 }, { 1.95, 0.30 } }, 0.43, 0.10, c.dark)
	K.rbox(2.30, 2.48, -0.06, 0.94, 0.44, 0.08, c.dark)
end

---------------------------------------------------------------- style B: Tactical

local B = {}

function B.pistol(K: any, c: Colors)
	-- slide: an ore-colored armor shell with sharp chamfers
	K.prism({ { -1.32, 0.32 }, { -1.32, 0.60 }, { -1.10, 0.82 }, { 0.40, 0.82 }, { 0.56, 0.64 }, { 0.56, 0.32 } }, 0.40, c.accent)
	-- frame: dark, a raked front
	K.prism({ { -1.12, 0.36 }, { 0.50, 0.36 }, { 0.50, 0.02 }, { -0.82, 0.02 }, { -1.12, 0.20 } }, 0.36, c.main)
	K.box(-1.18, 0.50, 0.33, 0.37, 0.41, c.glow, NEON) -- neon seam
	for i = 0, 2 do -- slide serrations
		local z = 0.12 + i * 0.12
		K.box(z - 0.025, z + 0.025, 0.48, 0.74, 0.41, c.main)
	end
	K.tube(-1.44, -1.30, 0.56, 0.22, c.main)
	K.tube(-1.45, -1.40, 0.56, 0.12, c.glow, NEON)
	K.box(-1.12, -1.02, 0.80, 0.90, 0.08, c.main) -- sights
	K.box(0.30, 0.46, 0.80, 0.90, 0.18, c.main)
	-- grip: a parallelogram, the bottom leans back, an ore-colored inlay
	K.prism({ { -0.06, 0.06 }, { 0.46, 0.06 }, { 0.72, -0.92 }, { 0.20, -0.92 } }, 0.36, c.main)
	K.prism({ { 0.04, -0.22 }, { 0.40, -0.22 }, { 0.58, -0.80 }, { 0.20, -0.80 } }, 0.38, c.light)
	-- trigger guard
	K.prism({ { -0.60, 0.04 }, { -0.48, 0.04 }, { -0.42, -0.28 }, { -0.56, -0.26 } }, 0.12, c.main)
	K.box(-0.50, 0.04, -0.30, -0.22, 0.12, c.main)
	K.box(-0.24, -0.17, -0.16, 0.04, 0.06, c.accent)
end

function B.carbine(K: any, c: Colors)
	-- upper armor shell
	K.prism({ { -1.50, 0.42 }, { -1.36, 0.86 }, { 0.75, 0.86 }, { 0.95, 0.66 }, { 0.95, 0.42 } }, 0.46, c.accent)
	-- lower receiver
	K.prism({ { -1.00, 0.44 }, { 0.92, 0.44 }, { 0.92, 0.02 }, { -0.75, 0.02 }, { -1.00, 0.20 } }, 0.42, c.main)
	K.box(-1.45, 0.90, 0.41, 0.45, 0.47, c.glow, NEON) -- neon seam
	-- handguard with a neon vent line
	K.prism({ { -2.45, 0.30 }, { -2.45, 0.62 }, { -2.30, 0.78 }, { -1.40, 0.78 }, { -1.40, 0.26 } }, 0.40, c.main)
	K.box(-2.30, -1.55, 0.50, 0.55, 0.41, c.glow, NEON)
	K.box(-2.30, -1.55, 0.36, 0.40, 0.41, c.light)
	K.tube(-2.85, -2.40, 0.52, 0.18, c.metal, METAL)
	K.prism({ { -3.12, 0.40 }, { -3.12, 0.62 }, { -3.00, 0.70 }, { -2.80, 0.70 }, { -2.80, 0.36 }, { -3.00, 0.36 } }, 0.32, c.accent)
	K.tube(-3.13, -3.08, 0.52, 0.12, c.glow, NEON)
	-- angular optic
	K.prism({ { -0.66, 0.86 }, { -0.56, 1.18 }, { 0.10, 1.18 }, { 0.18, 0.86 } }, 0.30, c.main)
	K.box(-0.63, -0.58, 0.92, 1.12, 0.22, c.glow, NEON)
	-- grip, magazine, trigger guard
	K.prism({ { 0.10, 0.04 }, { 0.58, 0.04 }, { 0.84, -0.88 }, { 0.36, -0.88 } }, 0.36, c.main)
	K.prism({ { 0.20, -0.22 }, { 0.52, -0.22 }, { 0.70, -0.78 }, { 0.36, -0.78 } }, 0.38, c.light)
	K.prism({ { -0.80, 0.04 }, { -0.36, 0.04 }, { -0.28, -0.82 }, { -0.70, -0.88 } }, 0.32, c.main)
	K.prism({ { -0.76, -0.50 }, { -0.33, -0.50 }, { -0.315, -0.60 }, { -0.74, -0.64 } }, 0.34, c.glow, NEON)
	K.box(-0.28, 0.12, -0.30, -0.22, 0.12, c.main)
	-- stock: angular, a dark frame with an ore-colored cheek panel
	K.prism({ { 0.90, 0.06 }, { 0.90, 0.84 }, { 1.85, 0.74 }, { 1.95, 0.58 }, { 1.95, -0.06 }, { 1.75, -0.12 } }, 0.40, c.main)
	K.prism({ { 1.05, 0.48 }, { 1.05, 0.76 }, { 1.70, 0.68 }, { 1.70, 0.48 } }, 0.42, c.accent)
end

function B.rifle(K: any, c: Colors)
	-- long upper armor shell
	K.prism({ { -1.85, 0.42 }, { -1.62, 0.94 }, { 1.00, 0.94 }, { 1.20, 0.72 }, { 1.20, 0.42 } }, 0.50, c.accent)
	K.prism({ { -1.40, 0.44 }, { 1.10, 0.44 }, { 1.10, 0.00 }, { -1.10, 0.00 }, { -1.40, 0.22 } }, 0.44, c.main)
	K.box(-1.80, 1.15, 0.41, 0.45, 0.51, c.glow, NEON) -- neon seam
	-- energy cell on the side
	K.box(-0.95, -0.05, 0.54, 0.82, 0.52, c.main)
	K.box(-0.85, -0.15, 0.60, 0.76, 0.53, c.glow, NEON)
	-- long handguard with two neon lines
	K.prism({ { -3.40, 0.28 }, { -3.40, 0.64 }, { -3.20, 0.84 }, { -1.70, 0.84 }, { -1.70, 0.24 } }, 0.42, c.main)
	K.box(-3.20, -1.85, 0.56, 0.60, 0.43, c.glow, NEON)
	K.box(-3.20, -1.85, 0.40, 0.44, 0.43, c.glow, NEON)
	K.tube(-4.10, -3.35, 0.54, 0.20, c.metal, METAL)
	K.prism({ { -4.50, 0.38 }, { -4.50, 0.68 }, { -4.34, 0.78 }, { -4.00, 0.78 }, { -4.00, 0.32 }, { -4.34, 0.32 } }, 0.36, c.accent)
	K.box(-4.40, -4.10, 0.50, 0.58, 0.37, c.dark)
	K.tube(-4.51, -4.46, 0.54, 0.14, c.glow, NEON)
	-- scope on two angular mounts
	K.prism({ { -1.10, 0.94 }, { -1.02, 1.10 }, { -0.78, 1.10 }, { -0.70, 0.94 } }, 0.20, c.main)
	K.prism({ { -0.10, 0.94 }, { -0.02, 1.10 }, { 0.22, 1.10 }, { 0.30, 0.94 } }, 0.20, c.main)
	K.tube(-1.40, 0.40, 1.26, 0.36, c.main)
	K.tube(-1.62, -1.32, 1.26, 0.48, c.main)
	K.tube(-1.63, -1.58, 1.26, 0.36, c.glow, NEON)
	K.tube(-0.50, -0.40, 1.26, 0.38, c.accent)
	-- grip, foregrip, trigger guard
	K.prism({ { 0.30, 0.02 }, { 0.78, 0.02 }, { 1.04, -0.88 }, { 0.56, -0.88 } }, 0.36, c.main)
	K.prism({ { 0.40, -0.22 }, { 0.72, -0.22 }, { 0.90, -0.78 }, { 0.56, -0.78 } }, 0.38, c.light)
	K.prism({ { -2.50, 0.26 }, { -2.10, 0.26 }, { -2.14, -0.30 }, { -2.42, -0.30 } }, 0.26, c.main)
	K.box(-0.10, 0.32, -0.30, -0.22, 0.12, c.main)
	-- stock: long, angular, an ore-colored cheek panel and a dark pad
	K.prism({ { 1.15, 0.04 }, { 1.15, 0.90 }, { 2.25, 0.82 }, { 2.40, 0.62 }, { 2.40, -0.10 }, { 2.10, -0.16 } }, 0.42, c.main)
	K.prism({ { 1.30, 0.52 }, { 1.30, 0.82 }, { 2.15, 0.74 }, { 2.15, 0.52 } }, 0.44, c.accent)
	K.box(2.40, 2.52, -0.12, 0.66, 0.44, c.dark)
end

---------------------------------------------------------------- style C: Core

local C = {}

-- the ore chamber: a glass tube along Z holding the glowing ore crystal, collars at both ends
local function chamber(K: any, c: Colors, z0: number, z1: number, y: number, d: number)
	K.tube(z0, z1, y, d, C3.fromRGB(220, 236, 248), GLASS).Transparency = 0.72
	K.crystal(z0 + 0.06, z1 - 0.06, y, d * 0.5, c.core)
	local mat = if c.trim == GOLD then METAL else SMOOTH
	K.tube(z0 - 0.04, z0 + 0.05, y, d + 0.08, c.trim, mat)
	K.tube(z1 - 0.05, z1 + 0.04, y, d + 0.08, c.trim, mat)
end

-- an emitter barrel: a pale tube with ore-colored rings, glow bands between them and a glowing tip
local function emitter(K: any, c: Colors, z0: number, z1: number, y: number, d: number, rings: number)
	K.tube(z0, z1, y, d, c.light)
	local step = (z1 - z0) / (rings + 1)
	for i = 1, rings do
		local z = z1 - i * step
		K.tube(z - 0.04, z + 0.04, y, d + 0.1, c.accent)
		if i < rings then
			K.tube(z - step * 0.62, z - step * 0.38, y, d + 0.02, c.glowSoft, NEON)
		end
	end
	K.tube(z0 - 0.22, z0 + 0.02, y, d + 0.14, c.main)
	K.tube(z0 - 0.06, z0 + 0.0, y, d + 0.18, c.trim, if c.trim == GOLD then METAL else SMOOTH)
	K.tube(z0 - 0.23, z0 - 0.19, y, d * 0.6, c.glow, NEON)
end

function C.pistol(K: any, c: Colors)
	-- rear body, the ore chamber, the nose
	K.rpoly({ { -0.22, 0.12 }, { 0.58, 0.12 }, { 0.58, 0.70 }, { 0.42, 0.84 }, { -0.22, 0.84 } }, 0.46, 0.14, c.main)
	chamber(K, c, -0.80, -0.22, 0.48, 0.60)
	K.rpoly({ { -1.18, 0.20 }, { -0.80, 0.14 }, { -0.80, 0.82 }, { -1.08, 0.78 }, { -1.18, 0.64 } }, 0.42, 0.12, c.main)
	emitter(K, c, -1.46, -1.16, 0.48, 0.28, 1)
	K.box(-0.90, -0.12, 0.80, 0.88, 0.16, c.dark) -- spine over the chamber
	K.box(-0.10, 0.50, 0.30, 0.35, 0.47, c.accent) -- color band
	K.rpoly({ { -1.02, 0.22 }, { 0.50, 0.22 }, { 0.50, 0.02 }, { -0.84, 0.00 } }, 0.40, 0.06, c.dark) -- lower frame
	K.rpoly({ { -0.02, 0.10 }, { 0.48, 0.10 }, { 0.74, -0.90 }, { 0.22, -0.94 } }, 0.38, 0.14, c.dark)
	K.rbox(-0.56, 0.02, -0.30, -0.21, 0.12, 0.045, c.dark)
	K.rpoly({ { -0.60, 0.04 }, { -0.48, 0.04 }, { -0.46, -0.28 }, { -0.58, -0.28 } }, 0.12, 0.03, c.dark)
	K.boxCF(CF.new(0, -0.07, -0.22) * CF.Angles(-0.25, 0, 0), V3.new(0.06, 0.24, 0.06), c.accent)
end

function C.carbine(K: any, c: Colors)
	K.rpoly({ { -0.30, 0.04 }, { 1.00, 0.04 }, { 1.00, 0.80 }, { 0.82, 0.92 }, { -0.30, 0.92 } }, 0.48, 0.16, c.main)
	chamber(K, c, -1.15, -0.30, 0.50, 0.74)
	K.rpoly({ { -1.95, 0.18 }, { -1.15, 0.10 }, { -1.15, 0.90 }, { -1.80, 0.82 }, { -1.95, 0.64 } }, 0.44, 0.14, c.main)
	emitter(K, c, -2.75, -1.95, 0.50, 0.32, 3)
	K.box(-1.40, 0.70, 0.90, 0.98, 0.20, c.dark) -- top rail
	K.box(-0.20, 0.90, 0.24, 0.30, 0.49, c.accent)
	K.box(-1.85, -1.25, 0.24, 0.30, 0.45, c.accent)
	K.rpoly({ { -1.20, 0.18 }, { 0.80, 0.18 }, { 0.80, 0.00 }, { -1.05, -0.02 } }, 0.42, 0.06, c.dark)
	K.rpoly({ { 0.18, 0.06 }, { 0.68, 0.06 }, { 0.92, -0.86 }, { 0.42, -0.90 } }, 0.38, 0.14, c.dark)
	K.rpoly({ { -1.80, 0.16 }, { -1.40, 0.16 }, { -1.46, -0.38 }, { -1.74, -0.38 } }, 0.28, 0.11, c.dark) -- foregrip
	K.rbox(-0.30, 0.20, -0.30, -0.21, 0.12, 0.045, c.dark)
	-- stock: tapered, a cut-out, a dark pad
	K.rpoly({ { 0.95, 0.14 }, { 0.95, 0.82 }, { 1.90, 0.76 }, { 1.90, 0.06 } }, 0.42, 0.16, c.main)
	K.rpoly({ { 1.15, 0.32 }, { 1.15, 0.60 }, { 1.62, 0.58 }, { 1.62, 0.30 } }, 0.43, 0.11, c.dark)
	K.rbox(1.84, 2.00, 0.00, 0.86, 0.44, 0.07, c.dark)
end

function C.rifle(K: any, c: Colors)
	K.rpoly({ { -0.40, 0.04 }, { 1.10, 0.04 }, { 1.10, 0.86 }, { 0.90, 0.98 }, { -0.40, 0.98 } }, 0.52, 0.18, c.main)
	chamber(K, c, -1.45, -0.40, 0.52, 0.84)
	K.rpoly({ { -2.40, 0.18 }, { -1.45, 0.08 }, { -1.45, 0.96 }, { -2.24, 0.88 }, { -2.40, 0.68 } }, 0.48, 0.16, c.main)
	emitter(K, c, -4.10, -2.40, 0.52, 0.34, 5)
	K.box(-1.70, 0.80, 0.96, 1.04, 0.22, c.dark) -- top rail
	K.box(-0.30, 1.00, 0.64, 0.69, 0.53, c.trim, METAL) -- gold trim line
	K.box(-2.30, -1.55, 0.64, 0.69, 0.49, c.trim, METAL)
	K.box(-0.30, 1.00, 0.24, 0.30, 0.53, c.accent)
	K.box(-2.30, -1.55, 0.24, 0.30, 0.49, c.accent)
	-- slim scope on the rail
	K.box(-1.20, -1.00, 1.04, 1.22, 0.14, c.dark)
	K.box(0.00, 0.20, 1.04, 1.22, 0.14, c.dark)
	K.tube(-1.40, 0.45, 1.32, 0.28, c.main)
	K.tube(-1.42, -1.34, 1.32, 0.34, c.trim, METAL)
	K.tube(-1.43, -1.40, 1.32, 0.22, c.glow, NEON)
	K.tube(-0.55, -0.47, 1.32, 0.32, c.accent)
	K.rpoly({ { -1.50, 0.16 }, { 0.90, 0.16 }, { 0.90, -0.02 }, { -1.35, -0.04 } }, 0.44, 0.06, c.dark)
	K.rpoly({ { 0.26, 0.06 }, { 0.76, 0.06 }, { 1.00, -0.86 }, { 0.50, -0.90 } }, 0.38, 0.14, c.dark)
	K.rpoly({ { -2.30, 0.16 }, { -1.86, 0.16 }, { -1.92, -0.40 }, { -2.24, -0.40 } }, 0.30, 0.12, c.dark)
	K.rbox(-0.22, 0.28, -0.30, -0.21, 0.12, 0.045, c.dark)
	-- long stock: cheek riser, cut-out, dark pad
	K.rpoly({ { 1.05, 0.12 }, { 1.05, 0.90 }, { 2.45, 0.84 }, { 2.45, -0.02 } }, 0.44, 0.18, c.main)
	K.rpoly({ { 1.35, 0.86 }, { 2.15, 0.84 }, { 2.08, 1.02 }, { 1.45, 1.04 } }, 0.38, 0.07, c.main)
	K.rpoly({ { 1.30, 0.32 }, { 1.30, 0.62 }, { 2.00, 0.60 }, { 2.00, 0.28 } }, 0.45, 0.11, c.dark)
	K.rbox(2.38, 2.56, -0.06, 0.94, 0.46, 0.08, c.dark)
end

local STYLES = { A = A, B = B, C = C }
local ARCHETYPE = { [1] = "pistol", [5] = "carbine", [10] = "rifle" }

-- Builds a concept gun into a new Model in its design frame.
function Concepts.gun(Loader: any, style: string, level: number, oreId: string): any
	local model = roblox.Instance.new("Model")
	model.Name = "Concept" .. style .. level
	local K = kit(model)
	local c = colorsFor(Loader, style, level, oreId)
	STYLES[style][ARCHETYPE[level]](K, c)
	return model
end

-- Extents of a model's parts in its own frame (rough: rotated boxes).
local function bounds(model: any)
	local lo = V3.new(math.huge, math.huge, math.huge)
	local hi = V3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local r = d.CFrame
			local s = d.Size / 2
			local p = r.Position
			local ext = V3.new(
				math.abs(r.RightVector.X) * s.X + math.abs(r.UpVector.X) * s.Y + math.abs(r.LookVector.X) * s.Z,
				math.abs(r.RightVector.Y) * s.X + math.abs(r.UpVector.Y) * s.Y + math.abs(r.LookVector.Y) * s.Z,
				math.abs(r.RightVector.Z) * s.X + math.abs(r.UpVector.Z) * s.Y + math.abs(r.LookVector.Z) * s.Z
			)
			lo = lo:Min(p - ext)
			hi = hi:Max(p + ext)
		end
	end
	return lo, hi
end

-- Scales a model about its design origin, centers it on its bounding box and moves it to `cf`.
local function present(model: any, cf: any, scale: number, parent: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size = d.Size * scale
			d.CFrame = CF.new(d.CFrame.Position * scale) * d.CFrame.Rotation
		end
	end
	local lo, hi = bounds(model)
	local center = (lo + hi) / 2
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * CF.new(-center) * d.CFrame
		end
	end
	model.Parent = parent
	return hi - lo
end

---------------------------------------------------------------- display rooms

-- The three guns every proposal shows.
Concepts.Lineup = {
	{ Level = 1, Ore = "", Scale = 2.0 },
	{ Level = 5, Ore = "Gold", Scale = 1.55 },
	{ Level = 10, Ore = "Heartstone", Scale = 1.3 },
}

function Concepts.build(Loader: any, parent: any)
	CF = Loader.CFrame
	Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterConcepts"
	root.Parent = parent
	local K = kit(root)
	local UPRIGHT = CF.Angles(0, 0, math.pi / 2) -- a cylinder standing up

	local function label(cf: any, size: any, text: string, plate: any, ink: any)
		local p = K.boxCF(cf, size, plate)
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.Parent = p
		local t = roblox.Instance.new("TextLabel")
		t.Text = text
		t.TextColor3 = ink
		t.FontFace = roblox.Font.fromEnum(Enum.Font.FredokaOne)
		t.Parent = gui
		return p
	end

	-- a level badge in the ore color (dark text on light colors)
	local function badge(cf: any, size: any, level: number, color: any)
		local luma = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
		local ink = if luma > 0.62 then C3.fromRGB(30, 30, 36) else C3.fromRGB(255, 255, 255)
		return label(cf, size, "LV " .. level, color, ink)
	end

	local function light(pos: any, color: any, range: number, brightness: number)
		local holder = K.part("Part", CF.new(pos), V3.new(0.1, 0.1, 0.1), color)
		holder.Transparency = 1
		local l = roblox.Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Parent = holder
	end

	local function room(x0: number, floor: any, wall: any)
		K.boxCF(CF.new(x0, -0.5, 0), V3.new(70, 1, 50), floor)
		K.boxCF(CF.new(x0, 14, -10.5), V3.new(70, 30, 1), wall)
	end

	------------------------------------------------ A: hero pedestals in a dark studio
	do
		local x0 = 0
		local WALL = C3.fromRGB(32, 36, 54)
		room(x0, C3.fromRGB(40, 44, 64), WALL)
		K.box(-10.05, -9.95, 0.0, 0.12, 70, C3.fromRGB(70, 96, 160), NEON, x0) -- light line along the floor
		label(CF.new(x0, 10.6, -9.95), V3.new(14, 1.4, 0.1), "LASER BLASTERS", WALL, C3.fromRGB(240, 242, 250))
		label(CF.new(x0, 9.45, -9.95), V3.new(8, 0.6, 0.1), "A  ·  SOFT", WALL, C3.fromRGB(140, 160, 210))
		for i, entry in Concepts.Lineup do
			local x = x0 + (i - 2) * 10.5
			local z = -2.5
			local look = BlasterBuilder.look(entry.Level, entry.Ore)
			-- pedestal: a dark drum, a light top, a glowing ore ring and a faint light disc
			K.cylCF(CF.new(x, 0.7, z) * UPRIGHT, 1.4, 4.6, C3.fromRGB(52, 56, 76))
			K.cylCF(CF.new(x, 1.46, z) * UPRIGHT, 0.12, 4.2, C3.fromRGB(214, 218, 228))
			K.cylCF(CF.new(x, 1.36, z) * UPRIGHT, 0.1, 4.72, look.GlowSoft, NEON)
			K.cylCF(CF.new(x, 1.53, z) * UPRIGHT, 0.03, 2.9, look.GlowSoft, NEON)
			K.cylCF(CF.new(x, 1.545, z) * UPRIGHT, 0.03, 2.62, C3.fromRGB(214, 218, 228))
			-- a tall rounded backdrop panel behind the gun, an ore-colored line at its foot
			K.rboxCF(CF.new(x, 4.6, -9.85) * CF.Angles(0, math.pi / 2, 0), V3.new(0.2, 9.0, 7.6), 1.2, C3.fromRGB(40, 45, 68))
			K.boxCF(CF.new(x, 0.6, -9.7), V3.new(5.0, 0.08, 0.1), look.GlowSoft, NEON)
			local gun = Concepts.gun(Loader, "A", entry.Level, entry.Ore)
			present(gun, CF.new(x, 3.9, z) * CF.Angles(0, -1.22, 0) * CF.Angles(0.1, 0, 0), entry.Scale, root)
			local name = BlasterData.displayName(entry.Level, entry.Ore)
			badge(CF.new(x, 1.0, z + 2.38), V3.new(1.3, 0.42, 0.06), entry.Level, look.Body)
			label(CF.new(x, 0.48, z + 2.4), V3.new(4.3, 0.5, 0.06), name, C3.fromRGB(22, 24, 36), C3.fromRGB(238, 240, 248))
		end
	end

	------------------------------------------------ B: armory wall with lit niches
	do
		local x0 = 80
		local WALL = C3.fromRGB(74, 78, 90)
		room(x0, C3.fromRGB(54, 56, 64), WALL)
		label(CF.new(x0, 11.0, -9.95), V3.new(14, 1.4, 0.1), "LASER BLASTERS", WALL, C3.fromRGB(240, 242, 250))
		label(CF.new(x0, 9.85, -9.95), V3.new(8, 0.6, 0.1), "B  ·  TACTICAL", WALL, C3.fromRGB(176, 182, 196))
		local widths = { 6.0, 8.4, 10.4 }
		local xs = { x0 - 10.4, x0 - 2.4, x0 + 7.6 }
		for i, entry in Concepts.Lineup do
			local look = BlasterBuilder.look(entry.Level, entry.Ore)
			local w, h = widths[i], 4.6
			local x, y = xs[i], 5.2
			-- the niche: a light panel with a faint grid, a dark frame, neon lines top and bottom
			K.boxCF(CF.new(x, y, -9.9), V3.new(w, h, 0.2), C3.fromRGB(168, 174, 188))
			for gx = 1, math.floor(w / 0.8) do
				K.boxCF(CF.new(x - w / 2 + gx * 0.8, y, -9.79), V3.new(0.03, h, 0.02), C3.fromRGB(150, 156, 170))
			end
			for gy = 1, 5 do
				K.boxCF(CF.new(x, y - h / 2 + gy * 0.8, -9.79), V3.new(w, 0.03, 0.02), C3.fromRGB(150, 156, 170))
			end
			for _, s in { -1, 1 } do
				K.boxCF(CF.new(x, y + s * (h / 2 + 0.15), -9.75), V3.new(w + 0.6, 0.3, 0.5), C3.fromRGB(40, 43, 50))
				K.boxCF(CF.new(x + s * (w / 2 + 0.15), y, -9.75), V3.new(0.3, h, 0.5), C3.fromRGB(40, 43, 50))
				K.boxCF(CF.new(x, y + s * (h / 2 - 0.06), -9.7), V3.new(w, 0.07, 0.3), look.GlowSoft, NEON)
			end
			local gun = Concepts.gun(Loader, "B", entry.Level, entry.Ore)
			present(gun, CF.new(x, y + 0.1, -9.0) * CF.Angles(0, -math.pi / 2, 0), entry.Scale, root)
			for _, s in { -1, 1 } do -- two pegs under the gun
				K.cylCF(CF.new(x + s * w * 0.18, y - 1.25, -9.4) * CF.Angles(0, math.pi / 2, 0), 1.0, 0.16, C3.fromRGB(40, 43, 50))
			end
			local name = BlasterData.displayName(entry.Level, entry.Ore)
			badge(CF.new(x - w / 2 + 0.65, y - h / 2 - 1.0, -9.9), V3.new(1.3, 0.5, 0.06), entry.Level, look.Body)
			label(
				CF.new(x + 0.65, y - h / 2 - 1.0, -9.9),
				V3.new(w - 1.3, 0.5, 0.06),
				name,
				C3.fromRGB(36, 38, 46),
				C3.fromRGB(236, 238, 244)
			)
		end
	end

	------------------------------------------------ C: white gallery with glass cases
	do
		local x0 = 160
		local WALL = C3.fromRGB(212, 215, 222)
		room(x0, C3.fromRGB(196, 200, 208), WALL)
		K.box(-10.0, -9.9, 0, 0.3, 70, C3.fromRGB(180, 184, 194), nil, x0) -- baseboard
		label(CF.new(x0, 10.6, -9.95), V3.new(14, 1.4, 0.1), "LASER BLASTERS", WALL, C3.fromRGB(46, 50, 62))
		label(CF.new(x0, 9.45, -9.95), V3.new(8, 0.6, 0.1), "C  ·  CORE", WALL, C3.fromRGB(120, 126, 142))
		for i, entry in Concepts.Lineup do
			local x = x0 + (i - 2) * 10.5
			local z = -2.5
			local look = BlasterBuilder.look(entry.Level, entry.Ore)
			-- a white rounded plinth with an ore-colored band, a glass case on top
			K.rboxCF(CF.new(x, 1.1, z), V3.new(6.4, 2.2, 3.2), 0.5, C3.fromRGB(232, 234, 240))
			K.boxCF(CF.new(x, 1.85, z), V3.new(6.42, 0.1, 3.22), look.Body)
			local case = K.boxCF(CF.new(x, 3.7, z), V3.new(6.2, 3.0, 3.0), C3.fromRGB(220, 236, 248), GLASS)
			case.Transparency = 0.9
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K.boxCF(CF.new(x + sx * 3.08, 3.7, z + sz * 1.48), V3.new(0.05, 3.0, 0.05), C3.fromRGB(226, 228, 234))
				end
			end
			for _, sz in { -1, 1 } do
				K.boxCF(CF.new(x, 5.2, z + sz * 1.48), V3.new(6.2, 0.05, 0.05), C3.fromRGB(226, 228, 234))
			end
			for _, sx in { -1, 1 } do
				K.boxCF(CF.new(x + sx * 3.08, 5.2, z), V3.new(0.05, 0.05, 3.0), C3.fromRGB(226, 228, 234))
			end
			local gun = Concepts.gun(Loader, "C", entry.Level, entry.Ore)
			present(gun, CF.new(x, 3.65, z) * CF.Angles(0, -1.28, 0) * CF.Angles(0.06, 0, 0), entry.Scale * 0.88, root)
			K.cylCF(CF.new(x, 2.5, z) * UPRIGHT, 0.9, 0.22, C3.fromRGB(232, 234, 240)) -- a small stand
			local name = BlasterData.displayName(entry.Level, entry.Ore)
			badge(CF.new(x - 2.3, 1.35, z + 1.62), V3.new(1.1, 0.4, 0.04), entry.Level, look.Body)
			label(CF.new(x + 0.6, 1.35, z + 1.62), V3.new(4.4, 0.4, 0.04), name, C3.fromRGB(232, 234, 240), C3.fromRGB(50, 54, 66))
		end
	end

	------------------------------------------------ compare wall: every style x level, side view
	do
		local x0 = 240
		local WALL = C3.fromRGB(184, 188, 198)
		room(x0, C3.fromRGB(160, 164, 174), WALL)
		local rows = { { "A", "A  SOFT" }, { "B", "B  TACTICAL" }, { "C", "C  CORE" } }
		local cols = { x0 - 7.5, x0 + 1.0, x0 + 11.5 }
		for r, row in rows do
			local y = 12.6 - r * 3.6
			label(CF.new(x0 - 14.5, y, -9.95), V3.new(4.6, 0.8, 0.1), row[2], C3.fromRGB(60, 64, 74), C3.fromRGB(240, 242, 248))
			for i, entry in Concepts.Lineup do
				local gun = Concepts.gun(Loader, row[1], entry.Level, entry.Ore)
				present(gun, CF.new(cols[i], y, -9.0) * CF.Angles(0, -math.pi / 2, 0), entry.Scale * 0.95, root)
			end
		end
		for i, entry in Concepts.Lineup do
			label(
				CF.new(cols[i], 12.9, -9.95),
				V3.new(6.0, 0.6, 0.1),
				"LV " .. entry.Level .. "  " .. BlasterData.get(entry.Level).Name,
				C3.fromRGB(60, 64, 74),
				C3.fromRGB(240, 242, 248)
			)
		end
	end
	return root
end

return Concepts
