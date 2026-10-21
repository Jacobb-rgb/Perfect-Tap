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

	---------------------------------------------------------------- Stone

	E.Stone = function(s: Shard)
		local granite, graniteLow = rgb(152, 146, 136), rgb(118, 110, 102)
		local moss, mossDark = rgb(110, 180, 70), rgb(70, 130, 50)
		body(s, granite, graniteLow, M.SmoothPlastic, s.Glow)
		-- amber ore veins running up the shell
		for i, k in { { -0.5, 0.35, 1.1 }, { 0.6, 0.4, 1.25 }, { 1.7, 0.3, 1.0 } } do
			local a0, a1 = onTop(s, k[1], k[2], 0.02), onTop(s, k[1] + 0.25, k[3], 0.02)
			T.seg(s.Top, "Vein" .. i, a0, a1, 0.1, 0.06, s.Glow, NEON)
		end
		-- copper and gold nuggets set in the stone
		for i, k in { { -0.2, 0.75, rgb(214, 120, 60) }, { 0.95, 1.0, GOLD }, { -1.0, 0.55, GOLD }, { 0.35, 1.45, rgb(214, 120, 60) } } do
			if s.Room() < 1 then
				break
			end
			local p = onTop(s, k[1] :: number, k[2] :: number, 0.02)
			diamond(s.Top, "Nugget" .. i, onShell(s, p), 0.26, 0.12, k[3] :: Color3, M.Foil)
		end
		-- the moss cap over the tip, moss dripping down, two red mushrooms
		T.ellipsoid(s.Top, "Moss", at(s, 0, tipY - 0.36, 0), Vector3.new(1.7, 0.9, 1.6), moss, M.Grass)
		for i, k in { { -0.75, tipY - 0.75, -0.55 }, { 0.8, tipY - 0.85, 0.3 } } do
			if s.Room() < 1 then
				break
			end
			T.ellipsoid(s.Top, "MossDrip" .. i, at(s, k[1], k[2], k[3]), Vector3.new(0.7, 0.5, 0.7), mossDark, M.Grass)
		end
		for i, k in { { 0.42, tipY - 0.3, -0.25, 1 }, { -0.36, tipY - 0.24, 0.12, 0.8 } } do
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
		-- glowing amber crystals breaking out of the stone
		local ambers = { { 1.5, 0.45, 0.7, 0.3, -0.9 }, { -1.4, 0.8, 0.6, 0.26, 0.85 }, { 2.4, 0.2, 0.5, 0.22, -1.0 } }
		for i, k in ambers do
			if s.Room() < 1 then
				break
			end
			local p = onTop(s, k[1], k[2], -0.05)
			local cf = CFrame.new(p) * CFrame.Angles(0, -k[1], 0) * CFrame.Angles(0, 0, k[5]) * CFrame.Angles(0, PI / 4, 0)
			K.part(s.Top, "Amber" .. i, cf, Vector3.new(k[4], k[3], k[4]), s.Glow, NEON)
		end
		-- a little sprout on the moss
		if s.Room() >= 2 then
			T.seg(
				s.Top,
				"Sprout",
				at(s, 0.05, tipY, 0.3).Position,
				at(s, 0.1, tipY + 0.35, 0.35).Position,
				0.06,
				0.06,
				rgb(70, 150, 60),
				M.Grass
			)
			K.part(s.Top, "Leaf", at(s, 0.22, tipY + 0.4, 0.35) * CFrame.Angles(0, 0, 0.5), Vector3.new(0.34, 0.06, 0.2), moss, M.Grass)
		end
		-- a stone slab, pebbles round the egg's foot
		K.upright(s.Bottom, "Slab", at(s, 0, -r + 0.05, 0), 0.24, 2.6, rgb(100, 94, 88), M.Slate)
		for i = 1, 6 do
			if s.Room() < 1 then
				break
			end
			local a = (i - 0.5) * 2 * PI / 6 + 0.3
			local size = 0.32 + (i % 3) * 0.08
			K.part(
				s.Bottom,
				"Pebble" .. i,
				at(s, math.sin(a) * 1.15, -r + 0.25, -math.cos(a) * 1.15) * CFrame.Angles(0.5 * i, 0.9 * i, 0.3),
				Vector3.new(size, size * 0.75, size * 0.9),
				if i % 2 == 0 then rgb(128, 120, 112) else rgb(96, 90, 86),
				M.Slate
			)
		end
	end

	---------------------------------------------------------------- Crystal

	E.Crystal = function(s: Shard)
		local ice, violet = rgb(176, 226, 255), rgb(120, 86, 220)
		local cyan, pink = rgb(90, 230, 255), rgb(200, 120, 255)
		body(s, ice, violet, M.SmoothPlastic, s.Glow)
		-- silver rings round the upper shell
		ring(s, "Ring1", 0.95, 0.1, SILVER, M.Metal)
		ring(s, "Ring2", 1.65, 0.08, SILVER, M.Metal)
		-- a crown of glowing crystals on the tip, the tallest in the middle
		for i, k in
			{
				{ 0, 0, 1.3, 0.42, 0, cyan },
				{ -0.36, 0.05, 0.9, 0.32, 0.4, pink },
				{ 0.36, 0, 0.95, 0.32, -0.4, pink },
				{ 0.05, 0.35, 0.8, 0.28, -0.1, cyan },
				{ -0.1, -0.35, 0.75, 0.26, 0.15, cyan },
			}
		do
			if s.Room() < 1 then
				break
			end
			local h, w = k[3] :: number, k[4] :: number
			local cf = at(s, k[1] :: number, tipY - 0.42 + h * 0.4, k[2] :: number)
				* CFrame.Angles(0, 0, k[5] :: number)
				* CFrame.Angles(0, PI / 4, 0)
			K.part(s.Top, "CrownCrystal" .. i, cf, Vector3.new(w, h, w), k[6] :: Color3, NEON)
		end
		-- crystals breaking out of both sides
		for i, k in
			{
				{ 1.25, 0.55, 1.15, 0.42, -0.9 },
				{ 1.75, 0.2, 0.75, 0.32, -1.2 },
				{ -1.3, 0.6, 1.1, 0.4, 0.9 },
				{ -1.8, 0.25, 0.7, 0.3, 1.2 },
				{ 0.75, 1.5, 0.6, 0.26, -0.6 },
			}
		do
			if s.Room() < 1 then
				break
			end
			local p = onTop(s, k[1], k[2], -0.05)
			local cf = CFrame.new(p) * CFrame.Angles(0, -k[1], 0) * CFrame.Angles(0, 0, k[5]) * CFrame.Angles(0, PI / 4, 0)
			K.part(s.Top, "SideCrystal" .. i, cf, Vector3.new(k[4], k[3], k[4]), if i % 2 == 0 then pink else cyan, NEON)
		end
		-- a violet gem in a silver setting on the front
		local gem = onShell(s, onTop(s, 0, 1.3, 0.02))
		diamond(s.Top, "GemSetting", gem, 0.6, 0.1, SILVER, M.Metal)
		diamond(s.Top, "Gem", gem * CFrame.new(0, 0, -0.05), 0.42, 0.1, pink, NEON)
		-- shards floating round the egg
		for i, k in { { 1.75, 1.6, -0.3 }, { -1.7, 1.9, 0.1 }, { 1.2, 2.4, 0.5 } } do
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
		-- the silver claw stand: a ring and three crystal legs
		K.upright(s.Bottom, "StandRing", at(s, 0, -r + 0.12, 0), 0.22, 1.6, SILVER, M.Metal)
		for i = 1, 3 do
			if s.Room() < 1 then
				break
			end
			local a = (i - 1) * 2 * PI / 3 + PI / 6
			local from = at(s, math.sin(a) * 0.7, -r + 0.12, -math.cos(a) * 0.7).Position
			local to = onLow(s, a, -0.55, 0.06)
			T.seg(s.Bottom, "StandLeg" .. i, from, to, 0.18, 0.18, SILVER, M.Metal)
		end
	end

	---------------------------------------------------------------- Royal

	E.Royal = function(s: Shard)
		local crimson = rgb(170, 26, 64)
		local ruby, sapphire, emerald = rgb(255, 40, 80), rgb(60, 140, 255), rgb(40, 220, 120)
		body(s, crimson, GOLD, M.SmoothPlastic, s.Glow, M.Foil)
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
		-- three jewels on the front
		for i, k in { { 0, 1.28, ruby, 0.44 }, { -0.62, 0.85, sapphire, 0.3 }, { 0.62, 0.85, emerald, 0.3 } } do
			if s.Room() < 2 then
				break
			end
			local cf = onShell(s, onTop(s, k[1] :: number, k[2] :: number, 0.02))
			local w = k[4] :: number
			diamond(s.Top, "JewelSet" .. i, cf, w + 0.14, 0.08, GOLD, M.Foil)
			diamond(s.Top, "Jewel" .. i, cf * CFrame.new(0, 0, -0.05), w, 0.08, k[3] :: Color3, NEON)
		end
		-- the jewelled crown on the tip
		local crownY = tipY - 0.2
		K.upright(s.Top, "CrownBand", at(s, 0, crownY, 0), 0.26, 1.1, GOLD, M.Foil)
		for i = 1, 5 do
			if s.Room() < 1 then
				break
			end
			local a = (i - 3) * 0.7
			local h = if i == 3 then 0.44 else 0.34
			local cf = at(s, math.sin(a) * 0.52, crownY + 0.2 + h * 0.2, -math.cos(a) * 0.52) * CFrame.Angles(0, -a, 0)
			diamond(s.Top, "CrownPoint" .. i, cf, h, 0.08, GOLD, M.Foil)
		end
		for i, a in { -0.7, 0, 0.7 } do
			if s.Room() < 1 then
				break
			end
			local cf = at(s, math.sin(a) * 0.57, crownY, -math.cos(a) * 0.57) * CFrame.Angles(0, -a, 0)
			diamond(s.Top, "CrownGem" .. i, cf, 0.14, 0.05, if i == 2 then ruby else sapphire, NEON)
		end
		if s.Room() >= 1 then
			K.part(s.Top, "CrownOrb", at(s, 0, crownY + 0.48, 0), Vector3.new(0.24, 0.24, 0.24), GOLD, M.Foil, BALL)
		end
		-- the red velvet cushion with gold tassels at its corners
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
	end

	return E
end

return CapsuleEggs
