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

	  Stone     a mossy granite egg: amber ore veins, copper and gold nuggets,
	            a moss cap with two red mushrooms, pebbles round a stone slab
	  Crystal   a glossy ice-blue egg on a violet base: a crown of glowing
	            crystals, crystals breaking out of its sides, silver rings,
	            a violet gem, floating shards, a silver claw stand
	  Royal     a crimson egg on a gold base: gold filigree rings and straps,
	            ruby, sapphire and emerald, a jewelled gold crown, a red
	            velvet cushion with gold tassels
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

local GOLD = rgb(255, 196, 56)
local SILVER = rgb(214, 222, 236)

function CapsuleEggs.eggs(kit: Kit, tools: Tools): { [string]: (Shard) -> () }
	local K, T = kit, tools
	local r = CapsuleEggs.Radius
	local topCenter = 0.4 * r
	local tipY = topCenter + 1.4 * r

	-- a diamond (a square turned 45 degrees about its facing axis)
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

	-- a point on the upper shell (azimuth from the front, height, pushed out)
	local function onTop(s: Shard, az: number, y: number, out: number): Vector3
		local yy = (y - topCenter) / (1.4 * r)
		local rr = r * math.sqrt(math.max(1 - yy * yy, 0)) + out
		return (s.Center * CFrame.new(math.sin(az) * rr, y, -math.cos(az) * rr)).Position
	end
	-- a point on the lower shell
	local function onLow(s: Shard, az: number, y: number, out: number): Vector3
		local rr = math.sqrt(math.max(r * r - y * y, 0)) + out
		return (s.Center * CFrame.new(math.sin(az) * rr, y, -math.cos(az) * rr)).Position
	end
	-- a part lying on the shell at `p`, facing out from the egg's axis
	local function onShell(s: Shard, p: Vector3): CFrame
		local axis = (s.Center * CFrame.new(0, (s.Center:PointToObjectSpace(p)).Y, 0)).Position
		return CFrame.lookAt(p, p + (p - axis).Unit)
	end
	local function at(s: Shard, x: number, y: number, z: number): CFrame
		return s.Center * CFrame.new(x, y, z)
	end

	-- the shells, the glowing waist band, the hidden cracks
	local function body(s: Shard, top: Color3, low: Color3, material: Enum.Material, band: Color3, lowMaterial: Enum.Material?)
		T.ellipsoid(s.Bottom, "Shell", at(s, 0, 0, 0), Vector3.new(2 * r, 2 * r, 2 * r), low, lowMaterial or material)
		T.ellipsoid(s.Top, "Shell", at(s, 0, topCenter, 0), Vector3.new(2 * r, 2.8 * r, 2 * r), top, material)
		K.upright(s.Bottom, "Band", at(s, 0, 0.02, 0), 0.16, 2 * r + 0.06, band, NEON)
		for i, k in { { -0.55, -0.35, 0.5 }, { 0.42, -0.62, -0.6 }, { 0.06, -0.9, 0.35 } } do
			local az = math.asin(math.clamp(k[1] / r, -1, 1))
			local p = onLow(s, az, k[2], 0.02)
			K.part(
				s.Bottom,
				"Crack" .. i,
				onShell(s, p) * CFrame.Angles(0, 0, k[3]),
				Vector3.new(0.09, 0.62, 0.04),
				K.lighter(band, 0.3),
				NEON
			)
		end
	end

	-- a ring hugging the upper shell at height y
	local function ring(s: Shard, name: string, y: number, width: number, color: Color3, material: Enum.Material)
		local yy = (y - topCenter) / (1.4 * r)
		local rr = r * math.sqrt(math.max(1 - yy * yy, 0))
		K.upright(s.Top, name, at(s, 0, y, 0), width, 2 * rr + 0.05, color, material)
	end

	local E: { [string]: (Shard) -> () } = {}

	-- a wing of three smooth feathers on `side`, fanning up and out from the
	-- upper shell (flat ellipsoids: no upload)
	local function wing(s: Shard, side: number, color: Color3, tip: Color3, material: Enum.Material)
		for i = 1, 3 do
			if s.Room() < 1 then
				return
			end
			local length = 1.75 - (i - 1) * 0.3
			local angle = side * (0.35 + (i - 1) * 0.42)
			local cf = at(s, side * (1.05 + length * 0.42), 1.1 + (i - 1) * 0.14, 0.25)
				* CFrame.Angles(0, -side * 0.35, 0)
				* CFrame.Angles(0, 0, angle - side * PI / 2 + side * 0.9)
			T.ellipsoid(
				s.Top,
				`Feather{side > 0 and 2 or 1}_{i}`,
				cf,
				Vector3.new(length, 0.5, 0.12),
				if i == 1 then tip else color,
				material
			)
		end
	end

	-- a ring of `n` segments circling the egg, tilted (an orbit)
	local function orbit(s: Shard, name: string, y: number, radius: number, tilt: number, n: number, width: number, color: Color3)
		local frame = at(s, 0, y, 0) * CFrame.Angles(tilt, 0, tilt * 0.4)
		for i = 1, n do
			if s.Room() < 1 then
				return
			end
			local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
			local p0 = (frame * CFrame.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)).Position
			local p1 = (frame * CFrame.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)).Position
			T.seg(s.Top, name .. i, p0, p1, width, width, color, NEON)
		end
	end

	-- small glowing motes floating round the egg
	local function motes(s: Shard, list: { { number } }, color: Color3)
		for i, k in list do
			if s.Room() < 1 then
				return
			end
			K.part(s.Top, "Mote" .. i, at(s, k[1], k[2], k[3]), Vector3.new(k[4], k[4], k[4]), color, NEON, BALL)
		end
	end

	---------------------------------------------------------------- Stone

	E.Stone = function(s: Shard)
		local slate, slateLow = rgb(122, 118, 112), rgb(86, 82, 80)
		local moss, mossDark = rgb(110, 190, 70), rgb(66, 130, 48)
		local rune = rgb(90, 240, 200)
		local bark = rgb(110, 72, 44)
		body(s, slate, slateLow, M.SmoothPlastic, s.Glow)
		-- the RUNE STONE: a glowing rune circle carved on the front, its glyph
		local front = onShell(s, onTop(s, 0, 1.05, 0.0))
		K.facing(s.Top, "RuneRing", front * CFrame.new(0, 0, -0.02), 0.06, 0.92, rune, NEON)
		K.facing(s.Top, "RuneDisc", front * CFrame.new(0, 0, -0.05), 0.06, 0.74, rgb(70, 68, 66), M.Slate)
		K.part(s.Top, "Glyph1", front * CFrame.new(0, 0, -0.09), Vector3.new(0.08, 0.5, 0.04), rune, NEON)
		K.part(s.Top, "Glyph2", front * CFrame.new(0, 0.08, -0.09) * CFrame.Angles(0, 0, 1.0), Vector3.new(0.08, 0.36, 0.04), rune, NEON)
		-- rune lines running round the sides
		for i, k in { { -1.0, 0.3, 1.2 }, { 1.05, 0.4, 1.35 }, { 2.6, 0.3, 1.1 } } do
			if s.Room() < 1 then
				break
			end
			T.seg(s.Top, "RuneLine" .. i, onTop(s, k[1], k[2], 0.02), onTop(s, k[1] + 0.3, k[3], 0.02), 0.08, 0.05, rune, NEON)
		end
		-- big amber crystals breaking out of both sides
		local ambers: { { number } } = {
			{ 1.45, 0.55, 1.0, 0.34, -0.85 },
			{ 1.75, 0.25, 0.7, 0.26, -1.15 },
			{ 1.2, 0.95, 0.55, 0.22, -0.6 },
			{ -1.45, 0.6, 0.95, 0.32, 0.85 },
			{ -1.8, 0.3, 0.65, 0.24, 1.15 },
			{ -1.15, 1.05, 0.5, 0.2, 0.6 },
		}
		for i, k in ambers do
			if s.Room() < 1 then
				break
			end
			local p = onTop(s, k[1], k[2], -0.05)
			local cf = CFrame.new(p) * CFrame.Angles(0, -k[1], 0) * CFrame.Angles(0, 0, k[5]) * CFrame.Angles(0, PI / 4, 0)
			K.part(s.Top, "Amber" .. i, cf, Vector3.new(k[4], k[3], k[4]), if i % 3 == 0 then rgb(255, 230, 120) else s.Glow, NEON)
		end
		-- the moss cap, its drips, two red mushrooms and a sprout
		T.ellipsoid(s.Top, "Moss", at(s, 0, tipY - 0.36, 0), Vector3.new(1.7, 0.9, 1.6), moss, M.Grass)
		for i, k in { { -0.75, tipY - 0.75, -0.55 }, { 0.8, tipY - 0.85, 0.3 } } do
			if s.Room() < 1 then
				break
			end
			T.ellipsoid(s.Top, "MossDrip" .. i, at(s, k[1], k[2], k[3]), Vector3.new(0.7, 0.5, 0.7), mossDark, M.Grass)
		end
		for i, k in { { 0.42, tipY - 0.3, -0.25, 1.15 }, { -0.36, tipY - 0.24, 0.12, 0.9 } } do
			if s.Room() < 3 then
				break
			end
			local size = k[4]
			K.upright(s.Top, "MushStem" .. i, at(s, k[1], k[2] + 0.12 * size, k[3]), 0.3 * size, 0.16 * size, rgb(246, 236, 214))
			T.ellipsoid(
				s.Top,
				"MushCap" .. i,
				at(s, k[1], k[2] + 0.3 * size, k[3]),
				Vector3.new(0.5, 0.26, 0.5) * size,
				rgb(220, 50, 50),
				M.SmoothPlastic
			)
			K.part(
				s.Top,
				"MushSpot" .. i,
				at(s, k[1] - 0.08 * size, k[2] + 0.4 * size, k[3] - 0.12 * size),
				Vector3.new(0.1, 0.1, 0.1) * size,
				Color3.new(1, 1, 1),
				M.SmoothPlastic,
				BALL
			)
		end
		if s.Room() >= 2 then
			T.seg(
				s.Top,
				"Sprout",
				at(s, 0.05, tipY, 0.3).Position,
				at(s, 0.1, tipY + 0.4, 0.35).Position,
				0.06,
				0.06,
				rgb(70, 150, 60),
				M.Grass
			)
			T.ellipsoid(
				s.Top,
				"Leaf",
				at(s, 0.24, tipY + 0.44, 0.35) * CFrame.Angles(0, 0, 0.5),
				Vector3.new(0.4, 0.08, 0.24),
				moss,
				M.Grass
			)
		end
		-- old roots gripping the egg's foot
		for i = 1, 3 do
			local a = (i - 1) * 2 * PI / 3 + 0.4
			local p0 = onLow(s, a, -0.25, 0.04)
			local p1 = onLow(s, a + 0.25, -0.85, 0.1)
			local p2 = (s.Center * CFrame.new(math.sin(a + 0.4) * 1.55, -r + 0.12, -math.cos(a + 0.4) * 1.55)).Position
			if s.Room() < 2 then
				break
			end
			T.seg(s.Bottom, `Root{i}_1`, p0, p1, 0.2, 0.2, bark, M.Wood)
			T.seg(s.Bottom, `Root{i}_2`, p1, p2, 0.16, 0.16, bark, M.Wood)
		end
		-- a boulder base split by glowing cracks
		K.upright(s.Bottom, "Slab", at(s, 0, -r + 0.05, 0), 0.26, 2.7, rgb(96, 90, 86), M.Slate)
		for i, k in { { 0.9, 0.6 }, { -1.0, 0.5 }, { 0.2, 0.55 } } do
			if s.Room() < 1 then
				break
			end
			local a = k[1] * 2.2
			K.part(
				s.Bottom,
				"Boulder" .. i,
				at(s, math.sin(a) * 1.25, -r + 0.3, -math.cos(a) * 1.25) * CFrame.Angles(0.4 * i, 0.9 * i, 0.3),
				Vector3.new(k[2], k[2] * 0.8, k[2] * 0.9),
				rgb(110, 104, 98),
				M.Slate
			)
		end
		for i, a in { 0.5, 2.6 } do
			if s.Room() < 1 then
				break
			end
			K.part(
				s.Bottom,
				"SlabCrack" .. i,
				at(s, math.sin(a) * 1.0, -r + 0.19, -math.cos(a) * 1.0) * CFrame.Angles(0, a, 0),
				Vector3.new(0.08, 0.04, 0.7),
				s.Glow,
				NEON
			)
		end
		-- fireflies
		motes(s, { { 1.7, 1.9, -0.4, 0.12 }, { -1.6, 2.3, 0.2, 0.1 }, { 1.2, 2.7, 0.6, 0.09 } }, rgb(220, 255, 140))
	end

	---------------------------------------------------------------- Crystal

	E.Crystal = function(s: Shard)
		local sapphire, violet = rgb(40, 60, 150), rgb(96, 50, 170)
		local cyan, pink, white = rgb(90, 235, 255), rgb(220, 120, 255), rgb(235, 250, 255)
		body(s, sapphire, violet, M.SmoothPlastic, cyan)
		-- glowing crystal seams across the dark shell
		for i, k in { { -0.55, 0.2, 0.9 }, { 0.4, 0.9, 1.6 }, { 1.4, 0.25, 1.05 }, { -1.5, 0.8, 1.55 } } do
			if s.Room() < 1 then
				break
			end
			T.seg(s.Top, "Seam" .. i, onTop(s, k[1], k[2], 0.02), onTop(s, k[1] + 0.35, k[3], 0.02), 0.08, 0.05, cyan, NEON)
		end
		-- the crown of crystals on the tip, a white-hot core crystal inside
		local crown: { { any } } = {
			{ 0, 0, 1.5, 0.46, 0, cyan },
			{ -0.4, 0.05, 1.0, 0.34, 0.45, pink },
			{ 0.4, 0, 1.05, 0.34, -0.45, pink },
			{ 0.05, 0.38, 0.9, 0.3, -0.1, cyan },
			{ -0.1, -0.38, 0.85, 0.28, 0.15, cyan },
			{ 0, 0, 0.95, 0.22, 0, white },
		}
		for i, k in crown do
			if s.Room() < 1 then
				break
			end
			local h, w = k[3] :: number, k[4] :: number
			local cf = at(s, k[1] :: number, tipY - 0.42 + h * 0.4, k[2] :: number)
				* CFrame.Angles(0, 0, k[5] :: number)
				* CFrame.Angles(0, PI / 4, 0)
			K.part(s.Top, "CrownCrystal" .. i, cf, Vector3.new(w, h, w), k[6] :: Color3, NEON)
		end
		-- crystal wings: three long shards fanning from each side
		for _, side in { -1, 1 } do
			for i = 1, 3 do
				if s.Room() < 1 then
					break
				end
				local length = 1.4 - (i - 1) * 0.25
				local cf = at(s, side * (1.0 + length * 0.35), 0.8 + (i - 1) * 0.28, 0.3)
					* CFrame.Angles(0, -side * 0.3, -side * (0.55 + (i - 1) * 0.35))
					* CFrame.Angles(0, PI / 4, 0)
				K.part(
					s.Top,
					`WingShard{side > 0 and 2 or 1}_{i}`,
					cf,
					Vector3.new(0.26, length, 0.26),
					if i == 2 then pink else cyan,
					NEON
				)
			end
		end
		-- the big gem on the front: a silver setting, the gem, a sparkle
		local gem = onShell(s, onTop(s, 0, 1.05, 0.02))
		diamond(s.Top, "GemSetting", gem, 0.78, 0.1, SILVER, M.Metal)
		diamond(s.Top, "Gem", gem * CFrame.new(0, 0, -0.05), 0.56, 0.1, pink, NEON)
		K.part(s.Top, "GemSparkle", gem * CFrame.new(-0.1, 0.1, -0.1), Vector3.new(0.1, 0.1, 0.04), white, NEON)
		-- a glowing orbit ring circling the egg
		orbit(s, "Orbit", 0.35, 1.8, 0.22, 10, 0.07, pink)
		-- floating shards
		for i, k in { { 1.85, 1.9, -0.3 }, { -1.8, 2.2, 0.1 }, { 1.0, 2.75, 0.5 } } do
			if s.Room() < 1 then
				break
			end
			K.part(
				s.Top,
				"Floater" .. i,
				at(s, k[1], k[2], k[3]) * CFrame.Angles(0.4, 0.8 * i, 0.3) * CFrame.Angles(0, PI / 4, 0),
				Vector3.new(0.18, 0.42, 0.18),
				cyan,
				NEON
			)
		end
		-- a crystal cluster base round a silver ring
		K.upright(s.Bottom, "StandRing", at(s, 0, -r + 0.1, 0), 0.2, 1.7, SILVER, M.Metal)
		for i = 1, 5 do
			if s.Room() < 1 then
				break
			end
			local a = (i - 1) * 2 * PI / 5 + 0.3
			local h = 0.55 + (i % 2) * 0.25
			local cf = at(s, math.sin(a) * 1.15, -r + h * 0.35, -math.cos(a) * 1.15)
				* CFrame.Angles(0, -a, (if i % 2 == 0 then 0.35 else -0.35))
				* CFrame.Angles(0, PI / 4, 0)
			K.part(s.Bottom, "BaseCrystal" .. i, cf, Vector3.new(0.28, h, 0.28), if i % 2 == 0 then pink else cyan, NEON)
		end
	end

	---------------------------------------------------------------- Royal

	E.Royal = function(s: Shard)
		local crimson = rgb(150, 16, 58)
		local ruby, sapphire, emerald = rgb(255, 40, 80), rgb(60, 140, 255), rgb(40, 220, 120)
		local pearl = rgb(250, 244, 236)
		body(s, crimson, GOLD, M.SmoothPlastic, s.Glow, M.Foil)
		-- golden wings of three smooth feathers each
		wing(s, -1, GOLD, rgb(255, 236, 160), M.Foil)
		wing(s, 1, GOLD, rgb(255, 236, 160), M.Foil)
		-- gold filigree: two rings and four straps from the waist to the crown
		ring(s, "Ring1", 0.85, 0.12, GOLD, M.Foil)
		ring(s, "Ring2", 1.7, 0.1, GOLD, M.Foil)
		for i = 1, 4 do
			local az = (i - 1) * PI / 2 + PI / 4
			local heights = { 0.12, 0.85, 1.7 }
			for j = 1, #heights - 1 do
				if s.Room() < 1 then
					break
				end
				local a0, a1 = onTop(s, az, heights[j], 0.02), onTop(s, az, heights[j + 1], 0.02)
				T.seg(s.Top, `Strap{i}_{j}`, a0, a1, 0.1, 0.06, GOLD, M.Foil)
			end
		end
		-- a string of pearls draped across the front
		for i = 1, 7 do
			if s.Room() < 1 then
				break
			end
			local az = (i - 4) * 0.22
			local y = 0.5 - 0.12 * math.cos((i - 4) / 3 * PI / 2)
			K.part(s.Top, "Pearl" .. i, CFrame.new(onTop(s, az, y, 0.06)), Vector3.new(0.16, 0.16, 0.16), pearl, M.SmoothPlastic, BALL)
		end
		-- the big ruby in the middle, a sapphire and an emerald beside it
		local jewels: { { any } } = { { 0, 1.25, ruby, 0.5 }, { -0.68, 1.15, sapphire, 0.3 }, { 0.68, 1.15, emerald, 0.3 } }
		for i, k in jewels do
			if s.Room() < 2 then
				break
			end
			local cf = onShell(s, onTop(s, k[1] :: number, k[2] :: number, 0.02))
			local w = k[4] :: number
			diamond(s.Top, "JewelSet" .. i, cf, w + 0.16, 0.08, GOLD, M.Foil)
			diamond(s.Top, "Jewel" .. i, cf * CFrame.new(0, 0, -0.05), w, 0.08, k[3] :: Color3, NEON)
			if i == 1 and s.Room() >= 1 then
				K.part(s.Top, "JewelSparkle", cf * CFrame.new(-0.1, 0.1, -0.1), Vector3.new(0.1, 0.1, 0.04), Color3.new(1, 1, 1), NEON)
			end
		end
		-- the crown: a gold band round a red velvet cap, five points, gems, an orb
		local crownY = tipY - 0.25
		T.ellipsoid(s.Top, "CrownCap", at(s, 0, crownY + 0.18, 0), Vector3.new(1.0, 0.7, 1.0), rgb(190, 20, 46), M.Fabric)
		K.upright(s.Top, "CrownBand", at(s, 0, crownY, 0), 0.3, 1.2, GOLD, M.Foil)
		for i = 1, 5 do
			if s.Room() < 1 then
				break
			end
			local a = (i - 3) * 0.7
			local h = if i == 3 then 0.5 else 0.38
			local cf = at(s, math.sin(a) * 0.57, crownY + 0.22 + h * 0.2, -math.cos(a) * 0.57) * CFrame.Angles(0, -a, 0)
			diamond(s.Top, "CrownPoint" .. i, cf, h, 0.08, GOLD, M.Foil)
		end
		for i, a in { -0.7, 0, 0.7 } do
			if s.Room() < 1 then
				break
			end
			local cf = at(s, math.sin(a) * 0.62, crownY, -math.cos(a) * 0.62) * CFrame.Angles(0, -a, 0)
			diamond(s.Top, "CrownGem" .. i, cf, 0.16, 0.05, if i == 2 then ruby else sapphire, NEON)
		end
		if s.Room() >= 1 then
			K.part(s.Top, "CrownOrb", at(s, 0, crownY + 0.6, 0), Vector3.new(0.26, 0.26, 0.26), GOLD, M.Foil, BALL)
		end
		-- the red velvet cushion with gold tassels
		T.ellipsoid(s.Bottom, "Cushion", at(s, 0, -r + 0.12, 0), Vector3.new(3.0, 0.62, 3.0), rgb(190, 20, 46), M.Fabric)
		for i = 1, 4 do
			if s.Room() < 1 then
				break
			end
			local a = (i - 0.5) * PI / 2
			K.part(
				s.Bottom,
				"Tassel" .. i,
				at(s, math.sin(a) * 1.35, -r + 0.05, -math.cos(a) * 1.35),
				Vector3.new(0.24, 0.24, 0.24),
				GOLD,
				M.Foil,
				BALL
			)
		end
		motes(s, { { 1.9, 1.9, -0.3, 0.1 }, { -1.9, 2.1, 0.1, 0.1 } }, rgb(255, 236, 160))
	end

	return E
end

return CapsuleEggs
