--[[
	DRAGONFORGE (limited edition, October / November 2026): the costumes of
	the set's 6 golems and the set's shard (GolemGearLimited explains the
	contract and the tools).

	  DragonHorns   Cinder Whelp (Rare): a soot-black baby dragon: curled
	                ivory horns, a muzzle with glowing nostrils, slit pupils,
	                little boned bat wings, a tail with a glowing spade
	  DragonEgg     Ember Hatchling (Rare): still half in its egg: the top of
	                the shell as a cap with a broken zigzag rim and spots, the
	                bottom of the shell round its hips, big sparkly eyes,
	                stubby wings, a little tail
	  DragonHelm    Dragonscale Knight (Epic): a closed helm shaped like a
	                dragon's skull (jaw, fangs, swept horns, a glowing crest),
	                scale pauldrons, a breastplate with the dragon's eye, a
	                cape, a kite shield and a flaming sword
	  DragonWings   Flamewing (Epic): wings made of fire (three layers from
	                ember red to white hot), a flame mohawk, a fire-tipped
	                tail, burning fists
	                Magma Wyvern (Legendary): obsidian with lava running in
	                its cracks, a roaring maw, long swept horns, huge torn
	                boned wings, a spiked tail, lava fists, embers
	  DragonCrown   Dragon King (Mythic): a gold crown of five points and
	                gems with a living flame, gold horns, a royal cape with an
	                ermine collar, gold armour, a sceptre with a fire orb,
	                huge three-panel gold-boned wings, embers and its own light

	The shard: a DRAGON EGG of black obsidian scales held in a gold dragon
	claw, lava glowing through its cracks, fire crystals breaking out of the
	shell and a crown of flame on top.
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools
type Shard = Types.Shard

local Dragonforge = {}

Dragonforge.Faces = {
	DragonHelm = "Closed",
} :: { [string]: string }

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

local GOLD = rgb(255, 196, 56)
local GOLD_DARK = rgb(196, 128, 30)
local IVORY = rgb(244, 230, 200)
local IVORY_DARK = rgb(196, 170, 130)
local SHELL = rgb(252, 240, 214)
local SPOT = rgb(240, 120, 40)
local FLAME_WHITE = rgb(255, 246, 200)
local FLAME_HOT = rgb(255, 214, 70)
local FLAME = rgb(255, 128, 24)
local EMBER = rgb(210, 40, 24)
local PUPIL = rgb(30, 14, 10)
local OBSIDIAN = rgb(28, 22, 30)
local CAPE = rgb(150, 18, 34)
local ERMINE = rgb(250, 246, 240)
local BLUSH = rgb(255, 140, 150)

-- (the shared tools, filled by accessories / shard)
local T: Tools = nil :: any
local K: Kit = nil :: any

---------------------------------------------------------------- small shapes

-- a diamond (a square turned 45 degrees about its facing axis)
local function diamond(
	parent: Instance,
	name: string,
	cf: CFrame,
	w: number,
	h: number,
	thick: number,
	color: Color3,
	material: Enum.Material?
): Part
	return K.part(parent, name, cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(w, h, thick), color, material)
end

-- a golem-local point, mirrored to `side` (x * side)
local function pt(c: Ctx, side: number, p: Vector3): Vector3
	return T.P(c, p.X * side, p.Y, p.Z)
end

-- a chain of segments through golem-local points (mirrored to `side`),
-- each `widths[i]` thick; stops when the budget runs out. Returns the
-- highest point (unscaled).
local function chain(
	c: Ctx,
	name: string,
	side: number,
	points: { Vector3 },
	widths: { number },
	colors: { Color3 },
	materials: { Enum.Material }
): number
	local top = 0
	for i = 1, #points - 1 do
		if c.Room() < 1 then
			break
		end
		local w = widths[i] * c.S
		-- (each segment reaches a little past its joints: no gaps at the bends)
		local a, b = pt(c, side, points[i]), pt(c, side, points[i + 1])
		local dir = (b - a).Unit
		T.seg(
			c.Model,
			name .. i,
			a - dir * (w * 0.35),
			b + dir * (w * 0.2),
			w,
			w,
			colors[math.min(i, #colors)],
			materials[math.min(i, #materials)]
		)
		top = math.max(top, points[i + 1].Y + widths[i] / 2)
	end
	return top
end

-- a pair of horns (chain on both sides)
local function horns(c: Ctx, points: { Vector3 }, widths: { number }, colors: { Color3 }, materials: { Enum.Material }): number
	local top = 0
	for i, side in { -1, 1 } do
		top = math.max(top, chain(c, "Horn" .. i .. "_", side, points, widths, colors, materials))
	end
	return top
end

--[[
	A boned wing on `side` from named golem-local points (side +1; mirrored),
	scaled by `k` about the shoulder R: bones = point-name pairs, panels =
	point-name triples with a color and a material each. Bones first (the
	frame reads even when the budget cuts a panel). Returns the top (unscaled).
]]
type WingSpec = {
	Points: { [string]: Vector3 },
	K: number,
	Bones: { { string } },
	BoneWidth: number,
	BoneColor: Color3,
	BoneMaterial: Enum.Material,
	Panels: { { any } }, -- { a, b, p, color, material }
}

local function wing(c: Ctx, i: number, side: number, spec: WingSpec): number
	local R = spec.Points.R
	local function at(name: string): Vector3
		local p = spec.Points[name]
		local q = R + (p - R) * spec.K
		return pt(c, side, q)
	end
	local top = 0
	for b, pair in spec.Bones do
		if c.Room() < 1 then
			break
		end
		local w = spec.BoneWidth * c.S
		T.seg(c.Model, `WingBone{i}_{b}`, at(pair[1]), at(pair[2]), w, w, spec.BoneColor, spec.BoneMaterial)
	end
	for n, panel in spec.Panels do
		local room = c.Room()
		if room < 1 then
			break
		end
		T.tri(c.Model, `Wing{i}_{n}`, at(panel[1]), at(panel[2]), at(panel[3]), 0.05 * c.S, panel[4], panel[5], math.min(room, 2))
	end
	for _, p in spec.Points do
		local q = R + (p - R) * spec.K
		top = math.max(top, q.Y)
	end
	return top
end

local function wings(c: Ctx, spec: WingSpec): number
	local top = 0
	for i, side in { -1, 1 } do
		top = math.max(top, wing(c, i, side, spec))
	end
	return top
end

-- the bat-wing frame every dragon shares (side +1, unscaled; the panels
-- name these): shoulder R, wrist W, the two finger tips T1 (outer, high) and
-- T2 (lower), and L low on the back
local WING_POINTS = {
	R = Vector3.new(0.38, 1.42, 0.46),
	W = Vector3.new(1.15, 2.3, 0.66),
	T1 = Vector3.new(1.95, 1.95, 0.8),
	T2 = Vector3.new(1.62, 1.12, 0.74),
	L = Vector3.new(0.62, 0.86, 0.56),
}

---------------------------------------------------------------- body pieces

-- every dragon: shoulder spikes (the boulder and the crystal re-dressed)
-- and the big lava core on the chest
local function dragonBody(c: Ctx, spikeColor: Color3?, spikeMaterial: Enum.Material?)
	for i, side in { -1, 1 } do
		T.redress(
			c,
			if i == 1 then "Boulder" else "Crystal",
			c.At(side * 0.66, 1.62, 0.06) * CFrame.Angles(0, 0, -side * 0.6) * CFrame.Angles(0, PI / 4, 0),
			c.V(0.3, 0.66, 0.3),
			spikeColor or c.Look.Trim,
			spikeMaterial or M.Slate
		)
	end
	T.redress(c, "Core", c.At(0, 1.14, -0.445) * CFrame.Angles(0, 0, PI / 4), c.V(0.32, 0.32, 0.06), c.Glow, NEON)
	-- a slim scaly brow ridge instead of the heavy stone brow
	T.redress(c, "Brow", c.At(0, 2.3, -0.645) * CFrame.Angles(-0.2, 0, 0), c.V(1.3, 0.1, 0.18), K.darker(c.Look.Trim, 0.1), M.Slate)
end

--[[
	The PREMIUM touches every Robux dragon gets (owner: "it's for Robux"):
	big shiny eyes (slit pupils and a white sparkle each), a dragon's belly
	scales under the core, claws on both fists and a little crest of spines
	on the head. `face` = false for a closed helm (the eyes stay in its slit).
]]
type Premium = {
	Face: boolean?,
	Belly: Color3?,
	Claws: Color3?,
	Crest: Color3?,
	CrestMaterial: Enum.Material?,
}
local function premium(c: Ctx, spec: Premium)
	if spec.Face ~= false then
		for i, x in { -0.29, 0.29 } do
			T.redress(c, "Eye" .. i, c.At(x, 2.0, -0.68), c.V(0.32, 0.3, 0.06), c.Glow, NEON)
		end
		for i, x in { -0.29, 0.29 } do
			if c.Room() < 2 then
				break
			end
			K.part(c.Model, "Pupil" .. i, c.At(x, 1.99, -0.715), c.V(0.07, 0.24, 0.02), PUPIL)
			K.part(c.Model, "Sparkle" .. i, c.At(x - 0.07, 2.07, -0.722), c.V(0.07, 0.07, 0.02), Color3.new(1, 1, 1), NEON)
		end
	end
	if spec.Belly then
		for i, k in { { 0.84, 0.66 }, { 0.66, 0.52 } } do
			if c.Room() < 1 then
				break
			end
			K.part(c.Model, "BellyScale" .. i, c.At(0, k[1], -0.44), c.V(k[2], 0.13, 0.04), spec.Belly, M.SmoothPlastic)
		end
	end
	if spec.Claws then
		for i, side in { -1, 1 } do
			for j, dx in { -0.14, 0.14 } do
				if c.Room() < 1 then
					break
				end
				local cf = c.At(side * 0.86 + dx, 0.5, -0.28) * CFrame.Angles(0.5, 0, 0)
				diamond(c.Model, `Claw{i}_{j}`, cf, 0.13 * c.S, 0.13 * c.S, 0.08 * c.S, spec.Claws, M.SmoothPlastic)
			end
		end
	end
	if spec.Crest then
		for i, z in { -0.32, 0, 0.32 } do
			if c.Room() < 1 then
				break
			end
			local h = if i == 2 then 0.36 else 0.28
			local cf = c.At(0, 2.72 + h * 0.2, z) * CFrame.Angles(0, PI / 2, 0)
			diamond(c.Model, "HeadSpine" .. i, cf, h * c.S, h * c.S, 0.07 * c.S, spec.Crest, spec.CrestMaterial or M.SmoothPlastic)
		end
	end
end

-- no brow at all (a cute face): the brow shrinks into the head
local function noBrow(c: Ctx)
	T.redress(c, "Brow", c.At(0, 2.1, 0), c.V(0.1, 0.1, 0.1), c.Look.Body, M.Slate)
end

-- a muzzle with glowing nostrils (and diamond fangs hanging under it)
local function muzzle(c: Ctx, fangs: boolean)
	if c.Room() < 1 then
		return
	end
	K.part(c.Model, "Snout", c.At(0, 1.74, -0.8), c.V(0.86, 0.42, 0.36), K.lighter(c.Look.Body, 0.1), M.Slate)
	if c.Room() >= 2 then
		for i, x in { -0.18, 0.18 } do
			K.part(c.Model, "Nostril" .. i, c.At(x, 1.86, -0.985), c.V(0.12, 0.07, 0.02), c.Glow, NEON)
		end
	end
	if fangs and c.Room() >= 2 then
		for i, x in { -0.26, 0.26 } do
			diamond(c.Model, "Fang" .. i, c.At(x, 1.53, -0.9), 0.13 * c.S, 0.13 * c.S, 0.06 * c.S, IVORY)
		end
	end
end

-- a tail curling from behind the hip out to the golem's right and forward,
-- tapering, with a tip (`tip` adds it). Returns nothing.
local TAIL = {
	Vector3.new(0.18, 0.62, 0.4),
	Vector3.new(0.62, 0.42, 0.72),
	Vector3.new(1.08, 0.3, 0.56),
	Vector3.new(1.34, 0.36, 0.14),
}
local function tail(c: Ctx, segments: number, width: number, color: Color3, tip: ((c: Ctx, at: CFrame) -> ())?)
	local points = {}
	for i = 1, segments + 1 do
		points[i] = TAIL[i]
	end
	local widths = {}
	for i = 1, segments do
		widths[i] = width * (1 - 0.22 * (i - 1))
	end
	chain(c, "Tail", 1, points, widths, { color }, { M.Slate })
	if tip and c.Room() >= 1 then
		local last = points[#points]
		tip(c, c.At(last.X + 0.06, last.Y + 0.12, last.Z - 0.04))
	end
end

-- a spade: a glowing diamond facing the front
local function spade(color: Color3, size: number): (c: Ctx, at: CFrame) -> ()
	return function(c, at)
		diamond(c.Model, "TailTip", at * CFrame.new(0, size * 0.25 * c.S, 0), size * c.S, size * c.S, 0.08 * c.S, color, NEON)
	end
end

-- dorsal spines down the back of the head and the body
local function spines(c: Ctx, color: Color3, material: Enum.Material, list: { { number } })
	for i, k in list do
		if c.Room() < 1 then
			return
		end
		local cf = c.At(0, k[1], k[2]) * CFrame.Angles(0, PI / 2, 0)
		diamond(c.Model, "Spine" .. i, cf, k[3] * c.S, k[3] * c.S, 0.08 * c.S, color, material)
	end
end

--[[
	A cape hanging from the shoulders and blowing back: the main panel, two
	flared side wedges (so it shows past the body from the front), a hem,
	and clasps with straps over the shoulders on the chest (they read from
	the front). Parts in priority order while the budget allows.
]]
type CapeSpec = {
	Color: Color3,
	Trim: Color3,
	TrimMaterial: Enum.Material?,
	Width: number?, -- at the shoulders (unscaled; default 1.3)
	Bottom: number?, -- the hem's height (default 0.14)
	Flare: number?, -- how far each side flares at the hem (default 0.32)
	Back: number?, -- how far the hem blows back (default 0.3)
	Clasp: Color3?, -- the clasps' color (nil: no clasps)
	ClaspMaterial: Enum.Material?,
	Material: Enum.Material?,
	Mantle: boolean?, -- a shoulder mantle over the arms (reads from the front)
	Collar: number?, -- a stand-up collar behind the head this tall (reads from the front)
}
local function cape(c: Ctx, spec: CapeSpec)
	local w = spec.Width or 1.3
	local yt, yb = 1.42, spec.Bottom or 0.14
	local zt = 0.47
	local zb = zt + (spec.Back or 0.3)
	local flare = spec.Flare or 0.32
	local material = spec.Material or M.Fabric
	if c.Room() < 1 then
		return
	end
	local tilt = math.atan((zb - zt) / (yt - yb))
	local mid = c.At(0, (yt + yb) / 2, (zt + zb) / 2) * CFrame.Angles(tilt, 0, 0)
	local length = math.sqrt((yt - yb) ^ 2 + (zb - zt) ^ 2)
	K.part(c.Model, "Cape", mid, c.V(w, length, 0.06), spec.Color, material)
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			break
		end
		T.tri(
			c.Model,
			"CapeFlare" .. i,
			T.P(c, side * (w / 2 - 0.02), yt - 0.05, zt + 0.01),
			T.P(c, side * (w / 2 - 0.02), yb, zb),
			T.P(c, side * (w / 2 + flare), yb, zb + 0.04),
			0.06 * c.S,
			K.darker(spec.Color, 0.12),
			material,
			1
		)
	end
	if c.Room() >= 1 then
		K.part(
			c.Model,
			"CapeHem",
			c.At(0, yb + 0.05, zb + 0.01) * CFrame.Angles(tilt, 0, 0),
			c.V(w + 2 * flare, 0.12, 0.09),
			spec.Trim,
			spec.TrimMaterial or M.Foil
		)
	end
	if spec.Collar then
		-- two halves standing up behind the head and fanning out (a vampire
		-- king's collar): taller and wider than the head, so it frames it
		local h = spec.Collar
		for i, side in { -1, 1 } do
			if c.Room() < 1 then
				break
			end
			local cf = c.At(side * 0.62, 1.46 + h / 2, 0.66) * CFrame.Angles(-0.25, side * 0.35, -side * 0.32)
			K.part(c.Model, "CapeCollar" .. i, cf, c.V(0.9, h, 0.07), spec.Color, material)
			if c.Room() >= 1 then
				-- a trim along the outer edge
				local rim = cf * CFrame.new(side * 0.43 * c.S, 0, -0.03 * c.S)
				K.part(c.Model, "CapeCollarRim" .. i, rim, c.V(0.1, h + 0.04, 0.05), spec.Trim, spec.TrimMaterial or M.Foil)
			end
		end
	end
	if spec.Mantle and c.Room() >= 1 then
		K.part(c.Model, "CapeMantle", c.At(0, 1.4, 0.06), c.V(2.02, 0.18, 1.04), spec.Color, material)
	end
	if spec.Clasp then
		for i, side in { -1, 1 } do
			if c.Room() < 2 then
				break
			end
			-- the strap over the shoulder, the clasp on the chest
			T.seg(
				c.Model,
				"CapeStrap" .. i,
				T.P(c, side * 0.42, 1.4, -0.44),
				T.P(c, side * 0.5, 1.5, 0.46),
				0.14 * c.S,
				0.05 * c.S,
				spec.Trim,
				spec.TrimMaterial or M.Foil
			)
			diamond(
				c.Model,
				"CapeClasp" .. i,
				c.At(side * 0.42, 1.34, -0.455),
				0.2 * c.S,
				0.2 * c.S,
				0.06 * c.S,
				spec.Clasp,
				spec.ClaspMaterial or NEON
			)
		end
	end
end

-- flying goggles pushed up on the forehead: a strap round the head, two round lenses
local function goggles(c: Ctx, y: number, frame: Color3, lens: Color3)
	if c.Room() < 3 then
		return
	end
	K.part(c.Model, "GoggleStrap", c.At(0, y, 0.02), c.V(1.56, 0.14, 1.36), rgb(70, 44, 30), M.Fabric)
	for i, x in { -0.3, 0.3 } do
		K.facing(c.Model, "Goggle" .. i, c.At(x, y + 0.02, -0.7), 0.12 * c.S, 0.42 * c.S, frame, M.Metal)
		if c.Room() >= 1 then
			K.facing(c.Model, "Lens" .. i, c.At(x, y + 0.02, -0.77), 0.03 * c.S, 0.3 * c.S, lens, NEON)
		end
	end
end

-- a scarf knotted round the neck, its two ends streaming back and out
local function scarf(c: Ctx, color: Color3, stripe: Color3)
	if c.Room() < 1 then
		return
	end
	K.part(c.Model, "Scarf", c.At(0, 1.36, 0), c.V(1.3, 0.2, 0.92), color, M.Fabric)
	for i, k in { { 0.3, 1.38, 0.5, 0.75, 1.0, 1.05 }, { -0.1, 1.34, 0.5, -0.45, 0.9, 1.2 } } do
		if c.Room() < 1 then
			break
		end
		T.seg(
			c.Model,
			"ScarfEnd" .. i,
			T.P(c, k[1], k[2], k[3]),
			T.P(c, k[4], k[5], k[6]),
			0.24 * c.S,
			0.05 * c.S,
			if i == 1 then color else stripe,
			M.Fabric
		)
	end
end

-- gauntlets / bracers on both forearms
local function bracers(c: Ctx, color: Color3, material: Enum.Material, gem: Color3?)
	for i, side in { -1, 1 } do
		if c.Room() < 1 then
			return
		end
		K.part(c.Model, "Bracer" .. i, c.At(side * 0.82, 0.98, 0) * CFrame.Angles(0, 0, side * 0.1), c.V(0.44, 0.16, 0.54), color, material)
		if gem and c.Room() >= 1 then
			diamond(c.Model, "BracerGem" .. i, c.At(side * 0.84, 0.98, -0.28), 0.12 * c.S, 0.12 * c.S, 0.04 * c.S, gem, NEON)
		end
	end
end

---------------------------------------------------------------- the costumes

local function cinderWhelp(c: Ctx): number
	dragonBody(c)
	-- curled ivory horns: up, out, then back
	local top = horns(
		c,
		{ Vector3.new(0.5, 2.6, 0.1), Vector3.new(0.74, 2.96, 0.16), Vector3.new(0.9, 3.22, 0.36), Vector3.new(0.86, 3.4, 0.62) },
		{ 0.26, 0.19, 0.13 },
		{ IVORY_DARK, IVORY, IVORY },
		{ M.Slate }
	)
	muzzle(c, false)
	local membrane = c.Look.Trim:Lerp(c.Look.Glow, 0.42)
	top = math.max(
		top,
		wings(c, {
			Points = WING_POINTS,
			K = 0.98,
			Bones = { { "R", "W" }, { "W", "T1" } },
			BoneWidth = 0.1,
			BoneColor = c.Look.Trim,
			BoneMaterial = M.Slate,
			Panels = {
				{ "R", "W", "T2", membrane, M.SmoothPlastic },
				{ "W", "T1", "T2", K.darker(membrane, 0.18), M.SmoothPlastic },
			},
		})
	)
	tail(c, 2, 0.24, c.Look.Trim, spade(c.Glow, 0.34))
	premium(c, { Belly = rgb(176, 130, 104), Claws = IVORY, Crest = c.Glow, CrestMaterial = NEON })
	-- a little adventurer: flying goggles on the forehead, a red scarf
	goggles(c, 2.42, rgb(196, 140, 60), rgb(255, 170, 60))
	scarf(c, rgb(210, 40, 40), rgb(255, 214, 90))
	return top
end

local function emberHatchling(c: Ctx): number
	dragonBody(c, c.Look.Trim)
	noBrow(c)
	-- the top of the egg: a smooth dome over the head, its broken zigzag rim
	T.ellipsoid(c.Model, "Shell", c.At(0, 2.66, 0.02), c.V(1.7, 1.42, 1.56), SHELL, M.SmoothPlastic)
	for i, x in { -0.5, -0.17, 0.17, 0.5 } do
		if c.Room() >= 1 then
			diamond(c.Model, "ShellPoint" .. i, c.At(x, 2.5, -0.7), 0.28 * c.S, 0.28 * c.S, 0.06 * c.S, SHELL, M.SmoothPlastic)
		end
	end
	-- the bottom of the egg round its hips, its points up
	if c.Room() >= 1 then
		T.ellipsoid(c.Model, "ShellLow", c.At(0, 0.56, 0), c.V(1.46, 0.92, 1.12), SHELL, M.SmoothPlastic)
	end
	for i, x in { -0.36, 0, 0.36 } do
		if c.Room() >= 1 then
			diamond(c.Model, "LowPoint" .. i, c.At(x, 0.98, -0.5), 0.3 * c.S, 0.3 * c.S, 0.06 * c.S, SHELL, M.SmoothPlastic)
		end
	end
	-- big sparkly eyes
	for i, x in { -0.28, 0.28 } do
		T.redress(c, "Eye" .. i, c.At(x, 1.98, -0.68), c.V(0.34, 0.3, 0.06), c.Glow, NEON)
	end
	if c.Room() >= 2 then
		for i, x in { -0.34, 0.22 } do
			K.part(c.Model, "Sparkle" .. i, c.At(x, 2.06, -0.715), c.V(0.09, 0.09, 0.02), Color3.new(1, 1, 1), NEON)
		end
	end
	-- stubby wings and a little tail
	local membrane = c.Look.Glow:Lerp(c.Look.Trim, 0.4)
	wings(c, {
		Points = WING_POINTS,
		K = 0.56,
		Bones = {},
		BoneWidth = 0.1,
		BoneColor = c.Look.Trim,
		BoneMaterial = M.Slate,
		Panels = { { "R", "W", "T2", membrane, M.SmoothPlastic } },
	})
	tail(c, 2, 0.22, c.Look.Trim, spade(c.Glow, 0.28))
	-- a tiny hero's cape and a gold bell on a collar
	cape(c, {
		Color = rgb(255, 196, 60),
		Trim = rgb(255, 120, 30),
		TrimMaterial = M.SmoothPlastic,
		Width = 1.2,
		Flare = 0.45,
		Back = 0.36,
		Bottom = 0.3,
	})
	if c.Room() >= 2 then
		K.part(c.Model, "Collar", c.At(0, 1.47, 0), c.V(1.28, 0.12, 0.96), rgb(200, 40, 50), M.Fabric)
		K.part(c.Model, "Bell", c.At(0, 1.32, -0.5), c.V(0.24, 0.24, 0.24), GOLD, M.Foil, BALL)
	end
	premium(c, { Face = false, Claws = IVORY })
	-- orange spots on the shell
	for i, k in { { -0.36, 3.02, -0.5, 0.3 }, { 0.38, 3.2, -0.3, 0.24 }, { 0.05, 3.32, -0.38, 0.18 } } do
		if c.Room() >= 1 then
			K.part(c.Model, "Spot" .. i, c.At(k[1], k[2], k[3]), c.V(k[4], k[4], k[4]), SPOT, M.SmoothPlastic, BALL)
		end
	end
	for i, x in { -0.5, 0.5 } do
		if c.Room() >= 1 then
			K.part(c.Model, "Blush" .. i, c.At(x, 1.8, -0.665), c.V(0.2, 0.1, 0.02), BLUSH, M.SmoothPlastic)
		end
	end
	return 2.66 + 0.71
end

local function scaleKnight(c: Ctx): number
	local trim = c.Look.Trim
	local metal = K.darker(trim, 0.08)
	dragonBody(c, metal, M.Metal)
	-- the dragon-skull helm
	K.part(c.Model, "Helm", c.At(0, 2.1, 0.02), c.V(1.62, 1.36, 1.42), trim, M.Metal)
	K.part(c.Model, "Slit", c.At(0, 2.02, -0.715), c.V(1.12, 0.22, 0.03), rgb(20, 14, 18))
	-- the dragon's brow ridge over the slit, its snout under it, fangs
	K.part(c.Model, "HelmBrow", c.At(0, 2.3, -0.76) * CFrame.Angles(-0.3, 0, 0), c.V(1.5, 0.2, 0.28), K.darker(trim, 0.25), M.Metal)
	K.part(c.Model, "Jaw", c.At(0, 1.7, -0.86), c.V(0.96, 0.4, 0.46), K.darker(trim, 0.12), M.Metal)
	for i, x in { -0.18, 0.18 } do
		if c.Room() >= 1 then
			K.part(c.Model, "HelmNostril" .. i, c.At(x, 1.82, -1.095), c.V(0.12, 0.07, 0.02), c.Glow, NEON)
		end
	end
	for i, x in { -0.3, 0.3 } do
		diamond(c.Model, "HelmFang" .. i, c.At(x, 1.48, -0.98), 0.14 * c.S, 0.14 * c.S, 0.05 * c.S, IVORY)
	end
	-- swept-back horns, gold into ivory
	local top = horns(
		c,
		{ Vector3.new(0.6, 2.56, 0.1), Vector3.new(0.86, 2.86, 0.34), Vector3.new(0.98, 3.0, 0.8) },
		{ 0.24, 0.16 },
		{ GOLD, IVORY },
		{ M.Foil, M.Slate }
	)
	-- a glowing crest of three fins over the top
	for i, z in { -0.36, 0, 0.36 } do
		if c.Room() >= 1 then
			local h = if i == 2 then 0.46 else 0.36
			local cf = c.At(0, 2.82, z) * CFrame.Angles(0, PI / 2, 0)
			diamond(c.Model, "Crest" .. i, cf, h * c.S, h * c.S, 0.08 * c.S, c.Glow, NEON)
			top = math.max(top, 2.82 + h * 0.71)
		end
	end
	-- the flaming sword in the right fist
	if c.Room() >= 3 then
		local hilt = Vector3.new(0.9, 0.7, -0.12)
		-- a steel blade with fire running up its middle
		local from, to = T.P(c, 0.92, 0.9, -0.22), T.P(c, 1.1, 2.6, -0.8)
		T.seg(c.Model, "Blade", from, to, 0.24 * c.S, 0.05 * c.S, rgb(214, 220, 232), M.Metal)
		if c.Room() >= 4 then
			local dir = (to - from).Unit
			local out = dir:Cross(Vector3.yAxis).Unit * (0.03 * c.S)
			T.seg(c.Model, "BladeFire", from + dir * (0.15 * c.S) - out, to - dir * (0.1 * c.S) - out, 0.1 * c.S, 0.07 * c.S, FLAME, NEON)
		end
		T.seg(c.Model, "Guard", T.P(c, 0.62, 0.8, -0.16), T.P(c, 1.22, 0.86, -0.2), 0.1 * c.S, 0.1 * c.S, GOLD, M.Foil)
		K.part(c.Model, "Pommel", c.At(hilt.X, 0.42, -0.04), c.V(0.16, 0.16, 0.16), GOLD, M.Foil, BALL)
	end
	-- the kite shield on the left arm with the dragon's eye
	if c.Room() >= 3 then
		local shield = c.At(-1.05, 1.0, -0.3) * CFrame.Angles(0, PI / 5, 0)
		K.part(c.Model, "Shield", shield, c.V(0.84, 0.62, 0.12), trim, M.Metal)
		diamond(c.Model, "ShieldPoint", shield * CFrame.new(0, -0.3 * c.S, 0), 0.6 * c.S, 0.6 * c.S, 0.11 * c.S, trim, M.Metal)
		local eye = shield * CFrame.new(0, -0.06 * c.S, -0.075 * c.S)
		K.part(c.Model, "ShieldEye", eye, c.V(0.12, 0.3, 0.03), c.Glow, NEON)
	end
	-- a knight's red cape on gold clasps
	cape(c, { Color = CAPE, Trim = GOLD, Clasp = c.Glow, Width = 1.3, Flare = 0.5, Back = 0.34, Mantle = true })
	-- a tabard with the dragon's eye over the breastplate
	if c.Room() >= 1 then
		K.part(c.Model, "Tabard", c.At(0, 0.74, -0.44), c.V(0.62, 0.5, 0.03), CAPE, M.Fabric)
	end
	-- a plume of flame on the helm's crown
	if c.Room() >= 2 then
		diamond(
			c.Model,
			"Plume",
			c.At(0, 3.18, 0.32) * CFrame.Angles(0, PI / 2, 0) * CFrame.Angles(0, 0, -0.5),
			0.5 * c.S,
			0.5 * c.S,
			0.1 * c.S,
			FLAME,
			NEON
		)
		diamond(
			c.Model,
			"PlumeCore",
			c.At(0, 3.12, 0.2) * CFrame.Angles(0, PI / 2, 0) * CFrame.Angles(0, 0, -0.4),
			0.3 * c.S,
			0.3 * c.S,
			0.08 * c.S,
			FLAME_HOT,
			NEON
		)
		top = math.max(top, 3.5)
	end
	-- gold gauntlets, dragon claws
	bracers(c, GOLD, M.Foil, nil)
	premium(c, { Face = false, Claws = IVORY })
	-- the breastplate and belt
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.08, -0.435), c.V(0.92, 0.6, 0.04), metal, M.Metal)
	end
	if c.Room() >= 1 then
		K.part(c.Model, "Belt", c.At(0, 0.62, 0), c.V(1.24, 0.12, 0.89), GOLD, M.Foil)
	end
	-- scale pauldrons: a second plate on each shoulder
	for i, side in { -1, 1 } do
		if c.Room() >= 1 then
			K.part(
				c.Model,
				"Pauldron" .. i,
				c.At(side * 0.78, 1.46, 0) * CFrame.Angles(0, 0, side * -0.35),
				c.V(0.56, 0.18, 0.62),
				trim,
				M.Metal
			)
		end
	end
	-- the dragon's eye on the breastplate (the core moves in front of it)
	T.redress(c, "Core", c.At(0, 1.1, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.3, 0.3, 0.04), c.Glow, NEON)
	return top
end

local function fireWings(c: Ctx): WingSpec
	return {
		Points = WING_POINTS,
		K = 0.95,
		Bones = { { "R", "W" } },
		BoneWidth = 0.1,
		BoneColor = FLAME_HOT,
		BoneMaterial = NEON,
		Panels = {
			{ "R", "W", "T1", EMBER, M.SmoothPlastic },
			{ "R", "T1", "T2", FLAME, M.SmoothPlastic },
			{ "R", "T2", "L", FLAME_HOT, NEON },
		},
	}
end

local function flamewing(c: Ctx): number
	dragonBody(c, FLAME, M.SmoothPlastic)
	local top = wings(c, fireWings(c))
	-- a flame mohawk: hot in the middle
	local mohawk: { { any } } = { { -0.3, 0.34, FLAME }, { 0, 0.52, FLAME_HOT }, { 0.3, 0.34, FLAME } }
	for i, k in mohawk do
		if c.Room() >= 1 then
			local h = k[2] :: number
			diamond(
				c.Model,
				"Flame" .. i,
				c.At(0, 2.76 + h * 0.2, k[1] :: number) * CFrame.Angles(0, PI / 2, 0),
				h * c.S,
				h * c.S,
				0.1 * c.S,
				k[3] :: Color3,
				NEON
			)
			top = math.max(top, 2.76 + h * 0.91)
		end
	end
	muzzle(c, false)
	-- short horns
	top = math.max(top, horns(c, { Vector3.new(0.58, 2.6, 0.14), Vector3.new(0.78, 3.0, 0.3) }, { 0.2 }, { IVORY }, { M.Slate }))
	-- a tail ending in fire
	tail(c, 2, 0.24, c.Look.Trim, function(cc, at)
		diamond(cc.Model, "TailFlame", at * CFrame.new(0, 0.12 * cc.S, 0), 0.4 * cc.S, 0.4 * cc.S, 0.08 * cc.S, FLAME, NEON)
		if cc.Room() >= 1 then
			diamond(
				cc.Model,
				"TailFlameCore",
				at * CFrame.new(0, 0.1 * cc.S, -0.05 * cc.S),
				0.22 * cc.S,
				0.22 * cc.S,
				0.06 * cc.S,
				FLAME_WHITE,
				NEON
			)
		end
	end)
	-- burning fists
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, FLAME, NEON)
	end
	premium(c, { Belly = rgb(255, 214, 160), Claws = IVORY })
	-- a fire pilot: aviator goggles, a long scarf streaming in the wind, a flame belt
	goggles(c, 2.44, GOLD, rgb(120, 220, 255))
	scarf(c, rgb(255, 240, 220), rgb(255, 160, 40))
	if c.Room() >= 2 then
		K.part(c.Model, "Belt", c.At(0, 0.62, 0), c.V(1.24, 0.12, 0.89), rgb(70, 30, 26), M.Fabric)
		diamond(c.Model, "Buckle", c.At(0, 0.62, -0.46), 0.22 * c.S, 0.22 * c.S, 0.05 * c.S, FLAME_HOT, NEON)
	end
	bracers(c, rgb(70, 30, 26), M.Fabric, nil)
	return top
end

local function magmaWyvern(c: Ctx): number
	dragonBody(c, OBSIDIAN, M.Basalt)
	-- huge torn wings on obsidian bones, lava glowing in the inner panel
	local top = wings(c, {
		Points = WING_POINTS,
		K = 1.22,
		Bones = { { "R", "W" }, { "W", "T1" }, { "W", "T2" } },
		BoneWidth = 0.12,
		BoneColor = OBSIDIAN,
		BoneMaterial = M.Basalt,
		Panels = {
			{ "W", "T1", "T2", rgb(64, 20, 24), M.SmoothPlastic },
			{ "R", "W", "T2", rgb(230, 80, 20), NEON },
		},
	})
	-- long horns swept back
	top = math.max(
		top,
		horns(
			c,
			{ Vector3.new(0.52, 2.62, 0.18), Vector3.new(0.7, 3.0, 0.4), Vector3.new(0.78, 3.18, 0.86), Vector3.new(0.74, 3.12, 1.3) },
			{ 0.28, 0.2, 0.13 },
			{ IVORY_DARK, IVORY, IVORY },
			{ M.Basalt, M.Slate, M.Slate }
		)
	)
	-- the roaring maw: upper and lower jaw, lava inside, fangs
	if c.Room() >= 3 then
		K.part(c.Model, "Snout", c.At(0, 1.86, -0.82), c.V(0.9, 0.3, 0.42), OBSIDIAN, M.Basalt)
		K.part(c.Model, "LowerJaw", c.At(0, 1.52, -0.78) * CFrame.Angles(0.22, 0, 0), c.V(0.82, 0.16, 0.38), OBSIDIAN, M.Basalt)
		K.part(c.Model, "Maw", c.At(0, 1.68, -0.8), c.V(0.7, 0.2, 0.3), c.Glow, NEON)
	end
	if c.Room() >= 2 then
		for i, x in { -0.28, 0.28 } do
			diamond(c.Model, "Fang" .. i, c.At(x, 1.68, -1.02), 0.13 * c.S, 0.13 * c.S, 0.05 * c.S, IVORY)
		end
	end
	tail(c, 3, 0.28, OBSIDIAN, function(cc, at)
		diamond(cc.Model, "TailSpike", at * CFrame.new(0.04 * cc.S, 0.06 * cc.S, 0), 0.36 * cc.S, 0.36 * cc.S, 0.1 * cc.S, c.Glow, NEON)
	end)
	-- lava running in its cracks (head, chest, arms, legs)
	local cracks = {
		{ -0.42, 2.38, -0.655, 0.5, 0.35 },
		{ 0.46, 1.66, -0.655, -0.6, 0.3 },
		{ 0.3, 1.25, -0.43, 0.7, 0.32 },
		{ -0.84, 1.2, -0.245, 0.3, 0.3 },
		{ 0.84, 1.06, -0.245, -0.4, 0.26 },
		{ -0.3, 0.3, -0.265, 0.2, 0.28 },
		{ 0.3, 0.2, -0.265, -0.3, 0.22 },
	}
	for i, k in cracks do
		if c.Room() < 1 then
			break
		end
		K.part(c.Model, "Lava" .. i, c.At(k[1], k[2], k[3]) * CFrame.Angles(0, 0, k[4]), c.V(0.06, k[5], 0.03), c.Glow, NEON)
	end
	-- a tattered smoke-black cape with a lava hem, obsidian war armour
	cape(
		c,
		{ Color = rgb(40, 26, 34), Trim = c.Glow, TrimMaterial = NEON, Width = 1.3, Flare = 0.55, Back = 0.4, Bottom = 0.1, Collar = 1.2 }
	)
	if c.Room() >= 2 then
		K.part(c.Model, "Breastplate", c.At(0, 1.08, -0.44), c.V(0.96, 0.62, 0.05), rgb(46, 36, 46), M.Metal)
		diamond(c.Model, "Rune", c.At(0, 1.08, -0.475), 0.3 * c.S, 0.3 * c.S, 0.03 * c.S, c.Glow, NEON)
	end
	for i, side in { -1, 1 } do
		if c.Room() < 2 then
			break
		end
		K.part(
			c.Model,
			"Pauldron" .. i,
			c.At(side * 0.8, 1.48, 0) * CFrame.Angles(0, 0, side * -0.35),
			c.V(0.6, 0.2, 0.66),
			rgb(46, 36, 46),
			M.Metal
		)
		T.seg(
			c.Model,
			"PauldronSpike" .. i,
			T.P(c, side * 0.86, 1.56, 0),
			T.P(c, side * 1.2, 2.0, 0.05),
			0.14 * c.S,
			0.14 * c.S,
			IVORY,
			M.Slate
		)
	end
	premium(c, { Claws = IVORY, Crest = c.Glow, CrestMaterial = NEON })
	spines(c, OBSIDIAN, M.Basalt, { { 2.6, 0.66, 0.4 }, { 1.3, 0.44, 0.36 } })
	-- lava fists
	for _, name in { "Fist1", "Fist2" } do
		T.recolor(c, name, c.Look.Glow, NEON)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, c.Glow, 4)
	end
	return top
end

local function dragonKing(c: Ctx): number
	dragonBody(c, GOLD, M.Foil)
	-- huge gold-boned wings in three crimson panels
	local top = wings(c, {
		Points = WING_POINTS,
		K = 1.32,
		Bones = { { "R", "W" }, { "W", "T1" }, { "W", "T2" } },
		BoneWidth = 0.13,
		BoneColor = GOLD,
		BoneMaterial = M.Foil,
		Panels = {
			{ "W", "T1", "T2", rgb(180, 26, 40), M.SmoothPlastic },
			{ "R", "W", "T2", rgb(140, 18, 34), M.SmoothPlastic },
			{ "R", "T2", "L", rgb(104, 12, 28), M.SmoothPlastic },
		},
	})
	-- the crown: a gold band, five points, three gems and a living flame
	K.upright(c.Model, "CrownBand", c.At(0, 2.86, 0), 0.32 * c.S, 1.3 * c.S, GOLD, M.Foil)
	for i = 1, 5 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 3) * 0.62 -- across the front and sides
		local x, z = math.sin(a) * 0.62, -math.cos(a) * 0.62
		local h = if i == 3 then 0.5 else 0.38
		local cf = c.At(x, 3.06, z) * CFrame.Angles(0, -a, 0)
		diamond(c.Model, "CrownPoint" .. i, cf, h * c.S, h * c.S, 0.08 * c.S, GOLD, M.Foil)
	end
	for i, a in { -0.62, 0, 0.62 } do
		if c.Room() < 1 then
			break
		end
		local x, z = math.sin(a) * 0.66, -math.cos(a) * 0.66
		local cf = c.At(x, 2.86, z) * CFrame.Angles(0, -a, 0)
		diamond(c.Model, "CrownGem" .. i, cf, 0.16 * c.S, 0.16 * c.S, 0.05 * c.S, if i == 2 then c.Glow else rgb(220, 30, 60), NEON)
	end
	if c.Room() >= 2 then
		diamond(c.Model, "CrownFlame", c.At(0, 3.36, 0.02), 0.62 * c.S, 0.62 * c.S, 0.12 * c.S, FLAME, NEON)
		diamond(c.Model, "CrownFlameCore", c.At(0, 3.3, -0.06), 0.34 * c.S, 0.34 * c.S, 0.08 * c.S, FLAME_WHITE, NEON)
		top = math.max(top, 3.36 + 0.44)
	end
	-- gold horns
	top = math.max(
		top,
		horns(
			c,
			{ Vector3.new(0.62, 2.5, 0.12), Vector3.new(0.92, 2.78, 0.22), Vector3.new(1.0, 3.18, 0.32) },
			{ 0.22, 0.15 },
			{ GOLD, IVORY },
			{ M.Foil, M.Slate }
		)
	)
	-- the royal cape: crimson, flared to the ground, a gold hem, gem clasps, an ermine collar
	cape(c, { Color = CAPE, Trim = GOLD, Clasp = c.Glow, Width = 1.36, Flare = 0.6, Back = 0.42, Bottom = 0.06, Collar = 1.4 })
	if c.Room() >= 1 then
		K.part(c.Model, "Collar", c.At(0, 1.5, 0.08), c.V(1.4, 0.24, 1.04), ERMINE, M.Fabric)
	end
	-- gold armour: breastplate, belt, bracers
	if c.Room() >= 1 then
		K.part(c.Model, "Breastplate", c.At(0, 1.06, -0.435), c.V(0.96, 0.66, 0.04), GOLD, M.Foil)
	end
	T.redress(c, "Core", c.At(0, 1.08, -0.47) * CFrame.Angles(0, 0, PI / 4), c.V(0.34, 0.34, 0.04), c.Glow, NEON)
	if c.Room() >= 1 then
		K.part(c.Model, "Belt", c.At(0, 0.6, 0), c.V(1.24, 0.12, 0.89), GOLD_DARK, M.Foil)
	end
	-- the sceptre in the right fist: a gold staff, a dragon-claw head, a fire orb
	if c.Room() >= 3 then
		T.seg(c.Model, "Staff", T.P(c, 1.08, 0.05, -0.42), T.P(c, 1.08, 2.3, -0.42), 0.1 * c.S, 0.1 * c.S, GOLD, M.Foil)
		diamond(c.Model, "StaffHead", c.At(1.08, 2.4, -0.42), 0.4 * c.S, 0.4 * c.S, 0.12 * c.S, GOLD, M.Foil)
		K.part(c.Model, "Orb", c.At(1.08, 2.66, -0.42), c.V(0.38, 0.38, 0.38), FLAME_HOT, NEON, BALL)
		top = math.max(top, 2.85)
	end
	bracers(c, GOLD, M.Foil, rgb(220, 30, 60))
	-- a gold dragon mask over the snout: the King's royal face
	if c.Room() >= 3 then
		K.part(c.Model, "Snout", c.At(0, 1.74, -0.8), c.V(0.9, 0.42, 0.36), GOLD, M.Foil)
		for i, x in { -0.18, 0.18 } do
			K.part(c.Model, "Nostril" .. i, c.At(x, 1.86, -0.985), c.V(0.12, 0.07, 0.02), c.Glow, NEON)
		end
	end
	premium(c, { Claws = GOLD })
	-- three fire gems orbiting the King, and a ring of flames round his aura
	for i = 1, 3 do
		if c.Room() < 1 then
			break
		end
		local a = ({ 0.15, PI - 0.15, PI / 2 })[i] -- the sides and behind (never over the face)
		local cf = c.At(math.cos(a) * 1.55, 2.0 + 0.35 * math.sin(a * 2), math.sin(a) * 1.0 - 0.2) * CFrame.Angles(0, -a, 0)
		diamond(c.Model, "OrbitGem" .. i, cf, 0.3 * c.S, 0.3 * c.S, 0.12 * c.S, if i == 2 then FLAME_HOT else rgb(255, 60, 90), NEON)
	end
	for i = 1, 6 do
		if c.Room() < 1 then
			break
		end
		local a = (i - 0.5) * 2 * PI / 6 -- (around the aura's rim)
		local cf = c.At(math.cos(a) * 1.1, 0.0, math.sin(a) * 1.1) * CFrame.Angles(0, -a + PI / 2, 0)
		diamond(c.Model, "RingFlame" .. i, cf, 0.34 * c.S, 0.34 * c.S, 0.06 * c.S, if i % 2 == 0 then FLAME_HOT else FLAME, NEON)
	end
	local body = c.Model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		T.embers(body, c.Glow, 5)
		T.light(body, c.Glow, 8, 1.2)
	end
	return top
end

function Dragonforge.accessories(kit: Kit, tools: Tools): { [string]: (Ctx) -> number }
	K, T = kit, tools
	return {
		DragonHorns = cinderWhelp,
		DragonEgg = emberHatchling,
		DragonHelm = scaleKnight,
		DragonWings = function(c: Ctx): number
			if c.Look.Rarity == "Legendary" or c.Look.Rarity == "Mythic" then
				return magmaWyvern(c)
			end
			return flamewing(c)
		end,
		DragonCrown = dragonKing,
	}
end

---------------------------------------------------------------- the shard

--[[
	The DRAGON EGG shard (units: studs, the shard's center at s.Center, the
	front -Z): the egg is a sphere below the waist and a tall ellipsoid
	above it (an egg's shape, the halves of the opening); black obsidian
	scales, lava in the seams, fire crystals breaking out, a crown of flame
	on top, a gold dragon claw holding it from below.
]]
function Dragonforge.shard(kit: Kit, tools: Tools, s: Shard)
	K, T = kit, tools
	local C = s.Center
	local r = 1.25
	local function at(x: number, y: number, z: number): CFrame
		return C * CFrame.new(x, y, z)
	end
	local function P(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	-- dark volcanic glass, so the lava glows against it
	local shell = rgb(92, 22, 28)
	local shellLow = rgb(56, 18, 26)
	local scale = rgb(140, 30, 30)
	local lava = s.Glow

	-- Bottom: the round lower shell, the band of lava at the waist, the cracks
	T.ellipsoid(s.Bottom, "Shell", at(0, 0, 0), Vector3.new(2 * r, 2 * r, 2 * r), shellLow, M.SmoothPlastic)
	K.upright(s.Bottom, "Band", at(0, 0.02, 0), 0.16, 2 * r + 0.06, lava, NEON)
	for i, k in { { -0.55, -0.35, 0.5 }, { 0.42, -0.62, -0.6 }, { 0.06, -0.9, 0.35 } } do
		local a = math.asin(math.clamp(k[1] / r, -1, 1))
		local y = k[2]
		local rr = math.sqrt(math.max(r * r - y * y, 0))
		K.part(
			s.Bottom,
			"Crack" .. i,
			at(math.sin(a) * (rr + 0.02), y, -math.cos(a) * (rr + 0.02)) * CFrame.Angles(0, -a, k[3]),
			Vector3.new(0.09, 0.62, 0.04),
			K.lighter(lava, 0.3),
			NEON
		)
	end
	-- the gold dragon claw: a ring under the egg and four talons up its sides
	K.upright(s.Bottom, "ClawRing", at(0, -r + 0.12, 0), 0.24, 1.5, GOLD, M.Foil)
	for i = 1, 4 do
		local a = (i - 0.5) * PI / 2 -- front-left, front-right, back-right, back-left
		local dx, dz = math.sin(a), -math.cos(a)
		local base = P(dx * 0.62, -r + 0.18, dz * 0.62)
		local knuckle = P(dx * 1.12, -0.62, dz * 1.12)
		local tip = P(dx * 1.24, -0.05, dz * 1.24)
		T.seg(s.Bottom, "Talon" .. i, base, knuckle, 0.22, 0.22, GOLD, M.Foil)
		if s.Room() >= 1 then
			T.seg(s.Bottom, "TalonTip" .. i, knuckle, tip, 0.16, 0.16, IVORY, M.Slate)
		end
	end
	-- a neat row of scales under the band
	for i = 1, 5 do
		if s.Room() < 1 then
			break
		end
		local a = (i - 3) * 0.42
		local y = -0.3
		local rr = math.sqrt(r * r - y * y)
		local cf = at(math.sin(a) * (rr - 0.02), y, -math.cos(a) * (rr - 0.02)) * CFrame.Angles(0, -a, 0)
		K.part(s.Bottom, "Scale" .. i, cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(0.36, 0.36, 0.1), scale, M.SmoothPlastic)
	end

	-- Top: the tall upper shell (an egg narrowing to its tip)
	local topCenter = 0.4 * r
	T.ellipsoid(s.Top, "Shell", at(0, topCenter, 0), Vector3.new(2 * r, 2.8 * r, 2 * r), shell, M.SmoothPlastic)
	-- lava seams running up the shell
	for i, k in { { -0.35, 0.65, 0.4 }, { 0.42, 1.0, -0.35 }, { -0.1, 1.45, 0.15 } } do
		if s.Room() < 1 then
			break
		end
		local x, y = k[1], k[2]
		local yy = (y - topCenter) / (1.4 * r)
		local rr = r * math.sqrt(math.max(1 - yy * yy, 0))
		local z = -math.sqrt(math.max(rr * rr - x * x, 0)) - 0.02
		K.part(
			s.Top,
			"Seam" .. i,
			at(x, y, z) * CFrame.Angles(0, math.asin(math.clamp(x / math.max(rr, 0.01), -1, 1)), k[3]),
			Vector3.new(0.08, 0.6, 0.04),
			lava,
			NEON
		)
	end
	-- fire crystals breaking out of the shell
	for i, k in
		{
			{ 1.05, 0.5, -0.3, 0.46, 1.3, -0.75, 0.35 },
			{ 1.18, 0.1, 0.25, 0.32, 0.9, -1.1, -0.2 },
			{ -1.1, 0.35, -0.2, 0.42, 1.15, 0.8, 0.25 },
			{ -0.8, 1.35, 0.2, 0.3, 0.8, 0.6, -0.2 },
		}
	do
		if s.Room() < 1 then
			break
		end
		local cf = at(k[1], k[2], k[3]) * CFrame.Angles(k[7], 0, k[6]) * CFrame.Angles(0, PI / 4, 0)
		K.part(s.Top, "Crystal" .. i, cf, Vector3.new(k[4], k[5], k[4]), if i == 2 then FLAME_HOT else FLAME, NEON)
	end
	-- the dragon's eye on the front: a gold frame, the glowing iris, a slit pupil
	if s.Room() >= 3 then
		local y = 0.95
		local yy = (y - topCenter) / (1.4 * r)
		local z = -r * math.sqrt(math.max(1 - yy * yy, 0))
		local eye = CFrame.lookAt(P(0, y, z), P(0, y + 0.25, z * 2))
		K.part(s.Top, "EyeFrame", eye * CFrame.Angles(0, 0, PI / 4), Vector3.new(0.78, 0.78, 0.1), GOLD, M.Foil)
		K.part(s.Top, "Eye", eye * CFrame.new(0, 0, -0.04) * CFrame.Angles(0, 0, PI / 4), Vector3.new(0.6, 0.6, 0.1), FLAME_HOT, NEON)
		K.part(s.Top, "EyePupil", eye * CFrame.new(0, 0, -0.08), Vector3.new(0.12, 0.66, 0.08), PUPIL)
	end
	-- the crown of flame on the tip
	local tipY = topCenter + 1.4 * r
	if s.Room() >= 3 then
		local flames: { { any } } = { { -0.4, 0.66, FLAME, -0.4 }, { 0.4, 0.66, FLAME, 0.4 }, { 0, 1.05, FLAME_HOT, 0 } }
		for i, k in flames do
			local h = k[2] :: number
			local cf = at(k[1] :: number, tipY - 0.1 + h * 0.35, 0) * CFrame.Angles(0, 0, k[4] :: number)
			diamond(s.Top, "Flame" .. i, cf, h, h, 0.14, k[3] :: Color3, NEON)
		end
	end
	if s.Room() >= 1 then
		diamond(s.Top, "FlameCore", at(0, tipY + 0.2, -0.1), 0.5, 0.5, 0.1, FLAME_WHITE, NEON)
	end
	-- small horns on the egg (it is a dragon's)
	for i, side in { -1, 1 } do
		if s.Room() < 1 then
			break
		end
		T.seg(s.Top, "EggHorn" .. i, P(side * 0.7, 1.5, 0.1), P(side * 1.0, 2.2, 0.35), 0.18, 0.18, IVORY, M.Slate)
	end
	-- LAVA FLOWING down the upper shell from the crown of flame: three
	-- streams hugging the egg's curve, each ending in a glowing drip
	local function onTop(az: number, y: number, out: number): Vector3
		local yy = (y - topCenter) / (1.4 * r)
		local rr = r * math.sqrt(math.max(1 - yy * yy, 0)) + out
		return P(math.sin(az) * rr, y, -math.cos(az) * rr)
	end
	local streams = { { -0.55, 0.26 }, { 0.35, 0.22 }, { 1.25, 0.24 } }
	for i, k in streams do
		local az, w = k[1], k[2]
		local heights = { 2.15, 1.75, 1.2, 0.55 }
		for j = 1, #heights - 1 do
			if s.Room() < 2 then
				break
			end
			local a0 = onTop(az + (j - 1) * 0.06, heights[j], 0.02)
			local a1 = onTop(az + j * 0.06, heights[j + 1], 0.02)
			local dir = (a1 - a0).Unit
			T.seg(
				s.Top,
				`LavaFlow{i}_{j}`,
				a0 - dir * 0.08,
				a1 + dir * 0.06,
				w * (1 + 0.15 * j),
				0.08,
				if j == 1 then FLAME_HOT else lava,
				NEON
			)
		end
		if s.Room() >= 2 then
			local drip = onTop(az + 0.2, heights[#heights] - 0.1, 0.06)
			K.part(s.Top, "LavaDrip" .. i, CFrame.new(drip), Vector3.new(0.3, 0.3, 0.3), FLAME, NEON, BALL)
		end
	end
	-- obsidian spikes breaking out of the shell
	for i, k in { { -1.55, 0.9, 1.3 }, { 1.7, 1.15, 1.2 }, { 2.6, 0.45, 1.0 } } do
		if s.Room() < 3 then
			break
		end
		local az, y, len = k[1], k[2], k[3]
		local base = onTop(az, y, -0.1)
		local dir = (onTop(az, y, 1) - base).Unit + Vector3.new(0, 0.55, 0)
		dir = dir.Unit
		local mid = base + dir * (len * 0.55)
		T.seg(s.Top, "Spike" .. i, base, mid, 0.44, 0.44, OBSIDIAN, M.Basalt)
		T.seg(s.Top, "SpikeTip" .. i, mid, base + dir * len, 0.22, 0.22, rgb(60, 40, 52), M.Basalt)
	end
	-- volcanic rocks heaped round the claw, lava glowing between them
	for i, k in { { -0.95, -1.0, -0.4, 0.6 }, { 0.9, -1.02, -0.5, 0.52 }, { -0.35, -1.1, -0.85, 0.44 }, { 0.5, -1.12, -0.8, 0.36 } } do
		if s.Room() < 1 then
			break
		end
		K.part(
			s.Bottom,
			"Rock" .. i,
			at(k[1], k[2], k[3]) * CFrame.Angles(0.4 * i, 0.9 * i, 0.3),
			Vector3.new(k[4], k[4] * 0.8, k[4] * 0.9),
			rgb(44, 32, 40),
			M.Basalt
		)
	end
	if s.Room() >= 1 then
		K.upright(s.Bottom, "LavaPool", at(0, -r + 0.02, -0.2), 0.06, 2.6, lava, NEON)
	end
	local core = s.Bottom:FindFirstChild("Band")
	if core and core:IsA("BasePart") then
		T.embers(core, lava, 6, 0.25)
	end
end

return Dragonforge
