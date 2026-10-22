--[[
	The regular capsules as EGGS (owner 2026-10-21: "an egg instead of the
	capsules", in the style of the limited editions' shards and the eggs of
	pet games). GolemBuilder.capsule builds the frame (the halves "Top" and
	"Bottom", their pivots, the hidden "Crack1..3") and calls the capsule's
	egg here with the same contract as a limited shard (GolemGearLimited:
	s.Top / s.Bottom / s.Center / s.Color / s.Glow / s.Room; one Neon "Band"
	and "Crack1".."Crack3" in s.Bottom). Units are studs, the egg's center at
	s.Center, the front -Z: a sphere (radius R) below the waist and an
	ellipsoid 2.8 R tall centered 0.4 R up above it (an egg's shape).

	  every one is THE PREMIUM EGG (premium below: the dragon egg's recipe,
	  owner: "clean like the dragon egg") in its theme (Themes):
	  Stone     an ancient rune stone, amber glowing in its veins
	  Crystal   a sapphire egg grown from living crystal
	  Royal     divine: pearl and gold, angel wings, a halo, clouds
	  (and the upcoming limited sets' shards: Galaxy, MechaNeon, FrostTitans)
]]

local Types = require(script.Parent.LimitedGearTypes)

type Kit = Types.Kit
type Tools = Types.Tools
type Shard = Types.Shard

local CapsuleEggs = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local NEON = M.Neon
local BALL = Enum.PartType.Ball
local PI = math.pi

CapsuleEggs.Radius = 1.25

--[[
	THE PREMIUM EGG (owner 2026-10-21: "take the dragon egg as the example,
	it is so clean; build each egg from what it is for, and it must look
	divine"): the dragon egg's recipe with a theme. Lower half: a sphere,
	the glowing waist band, a neat row of scales, a claw holding the egg
	(a ring, four talons with tips), rocks heaped round it on a glowing
	pool. Upper half: the tall shell, glowing seams, crystals and spikes
	breaking out, an emblem in a frame on the front, three streams of light
	running down from a crown on the tip, embers. Extras(s, h) adds the
	theme's own touches (a ring of stars, a halo, wings, a snow cap).
]]
export type Theme = {
	Shell: Color3,
	ShellLow: Color3,
	Scale: Color3,
	ScaleMaterial: Enum.Material?,
	Glow: Color3, -- the band, cracks, seams, streams, pool
	Hot: Color3, -- the streams' hot tops, the hot crystal
	Claw: Color3,
	ClawMaterial: Enum.Material,
	ClawTip: Color3,
	ClawTipMaterial: Enum.Material,
	Rock: Color3,
	RockMaterial: Enum.Material,
	RockShape: string?, -- "Block" (default) or "Ball" (clouds, snow)
	Crystal: Color3,
	Spike: Color3?, -- nil: no spikes
	SpikeTip: Color3?,
	SpikeMaterial: Enum.Material?,
	Horn: Color3?, -- nil: no horns
	Frame: Color3,
	FrameMaterial: Enum.Material,
	Iris: Color3,
	Mark: Color3,
	MarkShape: string, -- "Slit", "Sparkle", "Star", "Flake"
	Crown: { { any } }, -- { x, height, color, tilt }
	CrownCore: Color3,
	Embers: Color3,
	Extras: ((s: Shard, h: Helpers) -> ())?,
}

export type Helpers = {
	at: (x: number, y: number, z: number) -> CFrame,
	P: (x: number, y: number, z: number) -> Vector3,
	onTop: (az: number, y: number, out: number) -> Vector3,
	diamond: (parent: Instance, name: string, cf: CFrame, w: number, thick: number, color: Color3, material: Enum.Material?) -> Part,
	orbit: (name: string, y: number, radius: number, tilt: number, n: number, width: number, color: Color3) -> (),
	feathers: (side: number, color: Color3, tip: Color3, material: Enum.Material, y: number) -> (),
	ball: (name: string, cf: CFrame, size: number, color: Color3, material: Enum.Material?) -> Part,
	seg: (name: string, a: Vector3, b: Vector3, w: number, color: Color3, material: Enum.Material?) -> Part,
	puff: (name: string, cf: CFrame, size: Vector3, color: Color3) -> Part,
	TipY: number,
	R: number,
}

function CapsuleEggs.premium(kit: Kit, tools: Tools, s: Shard, th: Theme)
	local K, T = kit, tools
	local C = s.Center
	local r = CapsuleEggs.Radius
	-- (calm: the egg on its podium in the lobby glows only at its band, emblem and crown core)
	local GLOW = if s.Calm then M.SmoothPlastic else NEON
	local topCenter = 0.4 * r
	local tipY = topCenter + 1.4 * r
	local function at(x: number, y: number, z: number): CFrame
		return C * CFrame.new(x, y, z)
	end
	local function P(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	local function diamond(
		parent: Instance,
		name: string,
		cf: CFrame,
		w: number,
		thick: number,
		color: Color3,
		material: Enum.Material?
	): Part
		return K.part(parent, name, cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(w, w, thick), color, material)
	end
	local function onTop(az: number, y: number, out: number): Vector3
		local yy = (y - topCenter) / (1.4 * r)
		local rr = r * math.sqrt(math.max(1 - yy * yy, 0)) + out
		return P(math.sin(az) * rr, y, -math.cos(az) * rr)
	end

	-- Bottom: the lower shell, the glowing band, the hidden cracks
	T.ellipsoid(s.Bottom, "Shell", at(0, 0, 0), Vector3.new(2 * r, 2 * r, 2 * r), th.ShellLow, M.SmoothPlastic)
	K.upright(s.Bottom, "Band", at(0, 0.02, 0), 0.16, 2 * r + 0.06, th.Glow, NEON)
	for i, k in { { -0.55, -0.35, 0.5 }, { 0.42, -0.62, -0.6 }, { 0.06, -0.9, 0.35 } } do
		local a = math.asin(math.clamp(k[1] / r, -1, 1))
		local y = k[2]
		local rr = math.sqrt(math.max(r * r - y * y, 0))
		K.part(
			s.Bottom,
			"Crack" .. i,
			at(math.sin(a) * (rr + 0.02), y, -math.cos(a) * (rr + 0.02)) * CFrame.Angles(0, -a, k[3]),
			Vector3.new(0.09, 0.62, 0.04),
			K.lighter(th.Glow, 0.3),
			NEON
		)
	end
	-- the claw: a ring under the egg and four talons up its sides
	K.upright(s.Bottom, "ClawRing", at(0, -r + 0.12, 0), 0.24, 1.5, th.Claw, th.ClawMaterial)
	for i = 1, 4 do
		local a = (i - 0.5) * PI / 2
		local dx, dz = math.sin(a), -math.cos(a)
		local base = P(dx * 0.62, -r + 0.18, dz * 0.62)
		local knuckle = P(dx * 1.12, -0.62, dz * 1.12)
		local tip = P(dx * 1.24, -0.05, dz * 1.24)
		T.seg(s.Bottom, "Talon" .. i, base, knuckle, 0.22, 0.22, th.Claw, th.ClawMaterial)
		if s.Room() >= 1 then
			T.seg(s.Bottom, "TalonTip" .. i, knuckle, tip, 0.16, 0.16, th.ClawTip, th.ClawTipMaterial)
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
		K.part(
			s.Bottom,
			"Scale" .. i,
			cf * CFrame.Angles(0, 0, PI / 4),
			Vector3.new(0.36, 0.36, 0.1),
			th.Scale,
			th.ScaleMaterial or M.SmoothPlastic
		)
	end

	-- Top: the tall upper shell
	T.ellipsoid(s.Top, "Shell", at(0, topCenter, 0), Vector3.new(2 * r, 2.8 * r, 2 * r), th.Shell, M.SmoothPlastic)
	-- glowing seams running up the shell
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
			th.Glow,
			GLOW
		)
	end
	-- crystals breaking out of the shell
	local crystals: { { number } } = {
		{ 1.05, 0.5, -0.3, 0.46, 1.3, -0.75, 0.35 },
		{ 1.18, 0.1, 0.25, 0.32, 0.9, -1.1, -0.2 },
		{ -1.1, 0.35, -0.2, 0.42, 1.15, 0.8, 0.25 },
		{ -0.8, 1.35, 0.2, 0.3, 0.8, 0.6, -0.2 },
	}
	for i, k in crystals do
		if s.Room() < 1 then
			break
		end
		local cf = at(k[1], k[2], k[3]) * CFrame.Angles(k[7], 0, k[6]) * CFrame.Angles(0, PI / 4, 0)
		K.part(s.Top, "Crystal" .. i, cf, Vector3.new(k[4], k[5], k[4]), if i == 2 then th.Hot else th.Crystal, GLOW)
	end
	-- the emblem on the front: a frame, the glowing iris, its mark
	if s.Room() >= 4 then
		local y = 0.95
		local yy = (y - topCenter) / (1.4 * r)
		local z = -r * math.sqrt(math.max(1 - yy * yy, 0))
		local front = CFrame.lookAt(P(0, y, z), P(0, y + 0.25, z * 2))
		K.part(s.Top, "EmblemFrame", front * CFrame.Angles(0, 0, PI / 4), Vector3.new(0.78, 0.78, 0.1), th.Frame, th.FrameMaterial)
		K.part(s.Top, "Emblem", front * CFrame.new(0, 0, -0.04) * CFrame.Angles(0, 0, PI / 4), Vector3.new(0.6, 0.6, 0.1), th.Iris, NEON)
		local mark = front * CFrame.new(0, 0, -0.08)
		if th.MarkShape == "Slit" then
			K.part(s.Top, "Mark", mark, Vector3.new(0.12, 0.66, 0.08), th.Mark)
		elseif th.MarkShape == "Star" then
			K.part(s.Top, "Mark1", mark, Vector3.new(0.08, 0.5, 0.06), th.Mark, NEON)
			K.part(s.Top, "Mark2", mark * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.08, 0.5, 0.06), th.Mark, NEON)
		elseif th.MarkShape == "Flake" then
			for i = 1, 3 do
				K.part(s.Top, "Mark" .. i, mark * CFrame.Angles(0, 0, (i - 1) * PI / 3), Vector3.new(0.07, 0.5, 0.06), th.Mark, NEON)
			end
		else
			K.part(s.Top, "Mark", mark * CFrame.new(-0.1, 0.1, 0), Vector3.new(0.11, 0.11, 0.05), th.Mark, NEON)
		end
	end
	-- the crown on the tip and its white-hot core
	if s.Room() >= #th.Crown then
		for i, k in th.Crown do
			local h = k[2] :: number
			local cf = at(k[1] :: number, tipY - 0.1 + h * 0.35, 0) * CFrame.Angles(0, 0, k[4] :: number)
			diamond(s.Top, "CrownPiece" .. i, cf, h, 0.14, k[3] :: Color3, GLOW)
		end
	end
	if s.Room() >= 1 then
		diamond(s.Top, "CrownCore", at(0, tipY + 0.2, -0.1), 0.5, 0.1, th.CrownCore, NEON)
	end
	if th.Horn then
		for i, side in { -1, 1 } do
			if s.Room() < 1 then
				break
			end
			T.seg(s.Top, "EggHorn" .. i, P(side * 0.7, 1.5, 0.1), P(side * 1.0, 2.2, 0.35), 0.18, 0.18, th.Horn, M.Slate)
		end
	end
	-- the theme's own touches
	if th.Extras then
		th.Extras(s, {
			at = at,
			P = P,
			onTop = onTop,
			diamond = diamond,
			orbit = function(name: string, y: number, radius: number, tilt: number, n: number, width: number, color: Color3)
				local frame = at(0, y, 0) * CFrame.Angles(tilt, 0, tilt * 0.4)
				for i = 1, n do
					if s.Room() < 1 then
						return
					end
					local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
					local p0 = (frame * CFrame.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)).Position
					local p1 = (frame * CFrame.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)).Position
					T.seg(s.Top, name .. i, p0, p1, width, width, color, NEON)
				end
			end,
			feathers = function(side: number, color: Color3, tip: Color3, material: Enum.Material, y: number)
				for i = 1, 3 do
					if s.Room() < 1 then
						return
					end
					local length = 1.75 - (i - 1) * 0.3
					local cf = at(side * (1.05 + length * 0.42), y + (i - 1) * 0.14, 0.25)
						* CFrame.Angles(0, -side * 0.35, 0)
						* CFrame.Angles(0, 0, side * (0.35 + (i - 1) * 0.42) - side * PI / 2 + side * 0.9)
					T.ellipsoid(
						s.Top,
						`Feather{if side > 0 then 2 else 1}_{i}`,
						cf,
						Vector3.new(length, 0.5, 0.12),
						if i == 1 then tip else color,
						material
					)
				end
			end,
			ball = function(name: string, cf: CFrame, size: number, color: Color3, material: Enum.Material?): Part
				return K.part(s.Top, name, cf, Vector3.new(size, size, size), color, material, BALL)
			end,
			seg = function(name: string, a: Vector3, b: Vector3, w: number, color: Color3, material: Enum.Material?): Part
				return T.seg(s.Top, name, a, b, w, w, color, material)
			end,
			puff = function(name: string, cf: CFrame, size: Vector3, color: Color3): Part
				return T.ellipsoid(s.Top, name, cf, size, color, M.SmoothPlastic)
			end,
			TipY = tipY,
			R = r,
		})
	end
	-- three streams of light running down from the crown
	for i, k in { { -0.55, 0.26 }, { 0.35, 0.22 }, { 1.25, 0.24 } } do
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
				`Stream{i}_{j}`,
				a0 - dir * 0.08,
				a1 + dir * 0.06,
				w * (1 + 0.15 * j),
				0.08,
				if j == 1 then th.Hot else th.Glow,
				GLOW
			)
		end
		if s.Room() >= 2 then
			K.part(
				s.Top,
				"Drip" .. i,
				CFrame.new(onTop(az + 0.2, heights[#heights] - 0.1, 0.06)),
				Vector3.new(0.3, 0.3, 0.3),
				th.Glow,
				GLOW,
				BALL
			)
		end
	end
	-- spikes breaking out of the shell
	if th.Spike then
		for i, k in { { -1.55, 0.9, 1.3 }, { 1.7, 1.15, 1.2 }, { 2.6, 0.45, 1.0 } } do
			if s.Room() < 3 then
				break
			end
			local az, y, len = k[1], k[2], k[3]
			local base = onTop(az, y, -0.1)
			local dir = ((onTop(az, y, 1) - base).Unit + Vector3.new(0, 0.55, 0)).Unit
			local mid = base + dir * (len * 0.55)
			T.seg(s.Top, "Spike" .. i, base, mid, 0.44, 0.44, th.Spike, th.SpikeMaterial or M.SmoothPlastic)
			T.seg(s.Top, "SpikeTip" .. i, mid, base + dir * len, 0.22, 0.22, th.SpikeTip or th.Spike, th.SpikeMaterial or M.SmoothPlastic)
		end
	end
	-- rocks heaped round the claw on a glowing pool
	for i, k in { { -0.95, -1.0, -0.4, 0.6 }, { 0.9, -1.02, -0.5, 0.52 }, { -0.35, -1.1, -0.85, 0.44 }, { 0.5, -1.12, -0.8, 0.36 } } do
		if s.Room() < 1 then
			break
		end
		local size = Vector3.new(k[4], k[4] * 0.8, k[4] * 0.9)
		if th.RockShape == "Ball" then
			T.ellipsoid(s.Bottom, "Rock" .. i, at(k[1], k[2], k[3]), size * 1.2, th.Rock, th.RockMaterial)
		else
			K.part(s.Bottom, "Rock" .. i, at(k[1], k[2], k[3]) * CFrame.Angles(0.4 * i, 0.9 * i, 0.3), size, th.Rock, th.RockMaterial)
		end
	end
	if s.Room() >= 1 then
		K.upright(s.Bottom, "Pool", at(0, -r + 0.02, -0.2), 0.06, 2.6, th.Glow, GLOW)
	end
	local band = s.Bottom:FindFirstChild("Band")
	if band and band:IsA("BasePart") then
		T.embers(band, th.Embers, if s.Calm then 2 else 6, 0.25)
	end
end

CapsuleEggs.Themes = {} :: { [string]: Theme }
local Themes = CapsuleEggs.Themes
local WHITE = Color3.new(1, 1, 1)

-- STONE: an ancient rune stone, amber glowing in its veins
Themes.Stone = {
	Shell = rgb(84, 80, 80),
	ShellLow = rgb(56, 54, 56),
	Scale = rgb(120, 114, 108),
	Glow = rgb(255, 160, 50),
	Hot = rgb(255, 220, 120),
	Claw = rgb(176, 120, 60),
	ClawMaterial = M.Foil,
	ClawTip = rgb(110, 190, 70),
	ClawTipMaterial = M.Grass,
	Rock = rgb(104, 98, 94),
	RockMaterial = M.Slate,
	Crystal = rgb(255, 150, 40),
	Spike = rgb(110, 104, 100),
	SpikeTip = rgb(140, 134, 128),
	SpikeMaterial = M.Slate,
	Frame = rgb(176, 120, 60),
	FrameMaterial = M.Foil,
	Iris = rgb(90, 240, 200),
	Mark = rgb(30, 60, 50),
	MarkShape = "Slit",
	Crown = { { -0.4, 0.66, rgb(255, 150, 40), -0.4 }, { 0.4, 0.66, rgb(255, 150, 40), 0.4 }, { 0, 1.05, rgb(255, 214, 90), 0 } },
	CrownCore = rgb(255, 244, 200),
	Embers = rgb(255, 190, 80),
}

-- CRYSTAL: a sapphire egg grown from living crystal
Themes.Crystal = {
	Shell = rgb(34, 50, 130),
	ShellLow = rgb(60, 30, 120),
	Scale = rgb(150, 110, 240),
	Glow = rgb(90, 230, 255),
	Hot = rgb(220, 250, 255),
	Claw = rgb(214, 222, 236),
	ClawMaterial = M.Metal,
	ClawTip = rgb(90, 230, 255),
	ClawTipMaterial = NEON,
	Rock = rgb(120, 80, 210),
	RockMaterial = M.SmoothPlastic,
	Crystal = rgb(220, 120, 255),
	Spike = rgb(160, 120, 255),
	SpikeTip = rgb(220, 200, 255),
	SpikeMaterial = M.SmoothPlastic,
	Frame = rgb(214, 222, 236),
	FrameMaterial = M.Metal,
	Iris = rgb(220, 120, 255),
	Mark = WHITE,
	MarkShape = "Sparkle",
	Crown = { { -0.4, 0.7, rgb(220, 120, 255), -0.35 }, { 0.4, 0.7, rgb(220, 120, 255), 0.35 }, { 0, 1.15, rgb(90, 230, 255), 0 } },
	CrownCore = rgb(240, 252, 255),
	Embers = rgb(160, 240, 255),
}

-- ROYAL (divine): pearl and gold, a golden halo, angel wings, clouds
Themes.Royal = {
	Shell = rgb(252, 248, 238),
	ShellLow = rgb(255, 196, 56),
	Scale = rgb(255, 226, 140),
	ScaleMaterial = M.Foil,
	Glow = rgb(255, 210, 80),
	Hot = rgb(255, 250, 220),
	Claw = rgb(255, 196, 56),
	ClawMaterial = M.Foil,
	ClawTip = rgb(250, 244, 236),
	ClawTipMaterial = M.SmoothPlastic,
	Rock = rgb(255, 255, 255),
	RockMaterial = M.SmoothPlastic,
	RockShape = "Ball",
	Crystal = rgb(255, 210, 80),
	Frame = rgb(255, 196, 56),
	FrameMaterial = M.Foil,
	Iris = rgb(255, 40, 80),
	Mark = WHITE,
	MarkShape = "Sparkle",
	Crown = { { -0.42, 0.6, rgb(255, 210, 80), -0.45 }, { 0.42, 0.6, rgb(255, 210, 80), 0.45 }, { 0, 0.95, rgb(255, 236, 160), 0 } },
	CrownCore = WHITE,
	Embers = rgb(255, 236, 160),
	Extras = function(_s: Shard, h: Helpers)
		-- angel wings and a golden halo floating over the crown
		h.feathers(-1, rgb(255, 250, 240), rgb(255, 214, 90), M.SmoothPlastic, 1.0)
		h.feathers(1, rgb(255, 250, 240), rgb(255, 214, 90), M.SmoothPlastic, 1.0)
		h.orbit("Halo", h.TipY + 0.95, 0.62, 0.12, 8, 0.15, rgb(255, 220, 90))
	end,
}

-- SKY (the SKY EGG on SKY HAVEN, owner 2026-10-22: "cooler still than the
-- eggs below"): pearl over sky blue, gold claw and scales, cloud rocks,
-- SKY (the SKY EGG on Sky Haven): a STORM KNIGHT's egg like its golems
-- (owner: "black like the Storm Warden, mega cool"): black armour plates,
-- sky-blue light running in its seams, a crown of lightning, black and gold
-- wings, a golden halo, storm clouds round its foot and lightning bolts
-- striking beside it
Themes.Sky = {
	Shell = rgb(44, 48, 66),
	ShellLow = rgb(26, 28, 40),
	Scale = rgb(255, 210, 80),
	ScaleMaterial = M.Foil,
	Glow = rgb(110, 210, 255),
	Hot = rgb(230, 250, 255),
	Claw = rgb(255, 196, 56),
	ClawMaterial = M.Foil,
	ClawTip = rgb(110, 210, 255),
	ClawTipMaterial = NEON,
	Rock = rgb(150, 162, 196),
	RockMaterial = M.SmoothPlastic,
	RockShape = "Ball",
	Crystal = rgb(110, 210, 255),
	Spike = rgb(30, 32, 46),
	SpikeTip = rgb(255, 228, 90),
	SpikeMaterial = M.Metal,
	Frame = rgb(255, 196, 56),
	FrameMaterial = M.Foil,
	Iris = rgb(20, 24, 36),
	Mark = rgb(110, 210, 255),
	MarkShape = "Star",
	Crown = { { -0.42, 0.7, rgb(255, 228, 90), -0.5 }, { 0.42, 0.7, rgb(255, 228, 90), 0.5 }, { 0, 1.15, rgb(110, 210, 255), 0 } },
	CrownCore = WHITE,
	Embers = rgb(255, 230, 120),
	Extras = function(s: Shard, h: Helpers)
		-- black and gold wings, a golden halo over the lightning crown
		h.feathers(-1, rgb(40, 44, 60), rgb(255, 210, 80), M.Metal, 1.0)
		h.feathers(1, rgb(40, 44, 60), rgb(255, 210, 80), M.Metal, 1.0)
		h.orbit("Halo", h.TipY + 1.05, 0.62, 0.12, 8, 0.15, rgb(255, 220, 90))
		-- two lightning bolts striking down beside the egg
		for i, side in { -1, 1 } do
			local zig = {
				h.P(side * 1.9, 3.0, -0.2),
				h.P(side * 1.55, 2.2, -0.3),
				h.P(side * 1.95, 1.6, -0.3),
				h.P(side * 1.6, 0.7, -0.35),
			}
			for j = 1, #zig - 1 do
				if s.Room() < 1 then
					break
				end
				h.seg(`Bolt{i}_{j}`, zig[j], zig[j + 1], 0.13, rgb(255, 232, 100), NEON)
			end
		end
		-- a ring of storm clouds round the egg's waist
		for i = 1, 4 do
			if s.Room() < 1 then
				break
			end
			local a = (i - 0.5) / 4 * 2 * math.pi + 0.4
			h.puff("StormCloud" .. i, h.at(math.cos(a) * 1.45, 0.05, math.sin(a) * 1.1), Vector3.new(1.0, 0.55, 0.8), rgb(170, 182, 214))
		end
	end,
}

-- GALAXY: deep space, a ring of stars, little planets
Themes.Galaxy = {
	Shell = rgb(30, 22, 80),
	ShellLow = rgb(16, 12, 46),
	Scale = rgb(250, 250, 255),
	ScaleMaterial = NEON,
	Glow = rgb(150, 120, 255),
	Hot = rgb(240, 240, 255),
	Claw = rgb(214, 222, 236),
	ClawMaterial = M.Metal,
	ClawTip = rgb(90, 230, 255),
	ClawTipMaterial = NEON,
	Rock = rgb(70, 50, 110),
	RockMaterial = M.Slate,
	Crystal = rgb(90, 230, 255),
	Spike = nil,
	Frame = rgb(255, 196, 56),
	FrameMaterial = M.Foil,
	Iris = rgb(60, 40, 160),
	Mark = WHITE,
	MarkShape = "Star",
	Crown = { { -0.38, 0.6, rgb(150, 120, 255), -0.5 }, { 0.38, 0.6, rgb(255, 110, 230), 0.5 }, { 0, 1.1, rgb(240, 240, 255), 0 } },
	CrownCore = rgb(255, 250, 200),
	Embers = rgb(220, 220, 255),
	Extras = function(s: Shard, h: Helpers)
		-- a Saturn ring of starlight round the egg, two little planets riding it
		h.orbit("StarRing", 0.6, 1.95, 0.32, 12, 0.14, rgb(255, 214, 120))
		local planets: { { any } } = { { 1.9, 0.95, -0.4, 0.42, rgb(255, 130, 90) }, { -1.95, 0.35, 0.3, 0.32, rgb(90, 200, 255) } }
		for i, k in planets do
			if s.Room() < 1 then
				break
			end
			h.ball("Planet" .. i, h.at(k[1] :: number, k[2] :: number, k[3] :: number), k[4] :: number, k[5] :: Color3, M.SmoothPlastic)
		end
	end,
}

-- MECHA NEON: gunmetal and chrome, circuits of neon
Themes.MechaNeon = {
	Shell = rgb(58, 62, 80),
	ShellLow = rgb(34, 36, 48),
	Scale = rgb(200, 206, 222),
	ScaleMaterial = M.Metal,
	Glow = rgb(0, 230, 255),
	Hot = rgb(220, 255, 255),
	Claw = rgb(200, 206, 222),
	ClawMaterial = M.Metal,
	ClawTip = rgb(255, 60, 200),
	ClawTipMaterial = NEON,
	Rock = rgb(70, 74, 92),
	RockMaterial = M.DiamondPlate,
	Crystal = rgb(255, 60, 200),
	Spike = rgb(200, 206, 222),
	SpikeTip = rgb(255, 60, 200),
	SpikeMaterial = M.Metal,
	Frame = rgb(200, 206, 222),
	FrameMaterial = M.Metal,
	Iris = rgb(0, 230, 255),
	Mark = rgb(20, 24, 36),
	MarkShape = "Slit",
	Crown = { { -0.4, 0.62, rgb(255, 60, 200), -0.4 }, { 0.4, 0.62, rgb(255, 60, 200), 0.4 }, { 0, 1.05, rgb(0, 230, 255), 0 } },
	CrownCore = rgb(230, 255, 255),
	Embers = rgb(120, 240, 255),
}

-- FROST TITANS: deep glacier ice, a snow cap, icicles
Themes.FrostTitans = {
	Shell = rgb(46, 100, 170),
	ShellLow = rgb(26, 56, 110),
	Scale = rgb(230, 246, 255),
	Glow = rgb(120, 230, 255),
	Hot = rgb(240, 255, 255),
	Claw = rgb(214, 228, 244),
	ClawMaterial = M.Metal,
	ClawTip = rgb(170, 230, 255),
	ClawTipMaterial = M.Ice,
	Rock = rgb(248, 252, 255),
	RockMaterial = M.Snow,
	RockShape = "Ball",
	Crystal = rgb(150, 235, 255),
	Spike = rgb(200, 240, 255),
	SpikeTip = rgb(240, 252, 255),
	SpikeMaterial = M.Ice,
	Frame = rgb(214, 228, 244),
	FrameMaterial = M.Metal,
	Iris = rgb(30, 70, 150),
	Mark = rgb(200, 250, 255),
	MarkShape = "Flake",
	Crown = { { -0.4, 0.66, rgb(150, 235, 255), -0.4 }, { 0.4, 0.66, rgb(150, 235, 255), 0.4 }, { 0, 1.1, rgb(110, 255, 200), 0 } },
	CrownCore = rgb(240, 255, 255),
	Embers = rgb(220, 250, 255),
}

-- capsule id -> its egg (GolemBuilder.capsule): every regular capsule is a
-- premium egg in its theme
function CapsuleEggs.eggs(kit: Kit, tools: Tools): { [string]: (Shard) -> () }
	local E: { [string]: (Shard) -> () } = {}
	for _, id in { "Stone", "Crystal", "Royal" } do
		local theme = CapsuleEggs.Themes[id]
		E[id] = function(s: Shard)
			CapsuleEggs.premium(kit, tools, s, theme)
		end
	end
	return E
end

return CapsuleEggs
