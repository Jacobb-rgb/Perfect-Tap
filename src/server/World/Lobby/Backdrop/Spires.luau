--[[
	Spires: the voxel pillar peaks of the owner's reference (2026-10-17)
	rising behind and on top of the ForgeMountain massif. Each peak is a
	cluster of square pillars, the tallest in the middle and shorter ones
	leaning on it, coloured by height (Spectrum: red / orange low, pink,
	lavender and white up high) with a paler lit top on every pillar.

	  Ridge     three rows of side-by-side pillars behind the massif
	  Summit    peaks on the massif's back fill, clear of the Beacon
	  Flanks    lower peaks on the Land flanks west and east of the massif

	Pure decoration: no collision, all at y >= 24 (above the cave roofs).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Spectrum = require(script.Parent.Spectrum)

local Spires = {}

local BASE = 24
local EDGE = 169 -- island half width (WorldLayout.Island) minus a stud

-- One square pillar from `bottom` to `top` with its lit top.
local function pillar(parent: Instance, x: number, z: number, size: number, bottom: number, top: number, rng: Rng.Rng)
	local color = Spectrum.color(x, top, rng)
	local h = size / 2
	if x - h < -EDGE or x + h > EDGE then
		return -- keep on the island
	end
	-- (no shadows: the spires stand behind the massif, their shadows never reach the town)
	Kit.box(parent, Vector3.new(x - h, bottom, z - h), Vector3.new(x + h, top, z + h), color, nil, Style.ghost({ CastShadow = false }))
	Kit.box(
		parent,
		Vector3.new(x - h - 0.2, top, z - h - 0.2),
		Vector3.new(x + h + 0.2, top + 0.9, z + h + 0.2),
		Spectrum.tint(color),
		nil,
		Style.tiny()
	)
end

-- A peak: the tallest pillar at (cx, cz), `count` shorter ones around it on
-- a voxel grid of `w`/2.
local function peak(parent: Instance, cx: number, cz: number, bottom: number, top: number, w: number, count: number, rng: Rng.Rng)
	pillar(parent, cx, cz, w, bottom, top, rng)
	local step = w / 2
	for _ = 1, count do
		local dx = math.floor(rng:range(-2.99, 3)) * step
		local dz = math.floor(rng:range(-2.99, 1)) * step
		if dx == 0 and dz == 0 then
			dx = if rng:chance(0.5) then step * 2 else -step * 2
		end
		local size = w * rng:range(0.6, 1.0)
		local t = top - (top - bottom) * rng:range(0.18, 0.5)
		pillar(parent, cx + dx, cz + dz, size, bottom, math.floor(t), rng)
	end
end

function Spires.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Spires", parent)

	-- Ridge: three rows of side-by-side pillars behind the massif, stepping
	-- up toward the back. Their tops follow the massif's skyline plus a few
	-- broad humps and noise, so they read as mountains made of pillars.
	local function skyline(x: number): number
		if x < -80 then
			return 62 - (-80 - x) * 0.36
		elseif x < -50 then
			return 72
		elseif x < 20 then
			return 92
		elseif x < 96 then
			return 112
		elseif x < 140 then
			return 85
		elseif x < 162 then
			return 74
		end
		return 62 - (x - 162) * 0.36
	end
	local humps: { { number } } = { { -132, 30, 36 }, { -62, 34, 30 }, { 8, 30, 32 }, { 62, 40, 40 }, { 124, 30, 34 }, { 164, 22, 28 } }
	local function envelope(x: number): number
		local h = 6
		for _, hump in humps do
			h = math.max(h, hump[3] * math.exp(-((x - hump[1]) / hump[2]) ^ 2))
		end
		return h
	end
	local rows: { { number } } = { { -350, 0.55 }, { -364, 0.8 }, { -380, 1.0 } }
	for _, row in rows do
		local x = -168 + rng:range(0, 6)
		while x < 168 do
			local w = math.floor(rng:range(7, 10.99))
			local cx = x + w / 2
			local top = math.floor(skyline(cx) + 8 + envelope(cx) * row[2] + rng:range(-6, 8))
			pillar(m, cx, row[1] + math.floor(rng:range(-2, 2.99)), w, BASE, top, rng)
			x += w
		end
	end

	-- Summit: on the back fill of the massif (tops 68..117), clear of the
	-- Beacon (x 52..68) and of the crane's swing (x 96..118)
	local summit: { { number } } = {
		{ -70, -330, 72, 122 },
		{ -44, -326, 92, 134 },
		{ -14, -332, 92, 140 },
		{ 28, -334, 110, 150 },
		{ 84, -336, 110, 146 },
		{ 128, -328, 84, 128 },
		{ 152, -322, 72, 118 },
	}
	for _, s in summit do
		peak(m, s[1], s[2], s[3] - 14, s[4] + math.floor(rng:range(-6, 6)), rng:range(5, 7), math.floor(rng:range(2, 4)), rng)
	end

	-- Flanks: lower peaks on the Land cliffs beside the massif (clear of
	-- FloatingIslandWest's footprint and fall at x -170..-130, z > -270)
	local flanks: { { number } } = {
		{ -150, -304, 96 },
		{ -118, -292, 84 },
		{ -100, -322, 104 },
		{ 166, -300, 96 },
		{ 164, -262, 80 },
	}
	for _, f in flanks do
		peak(m, f[1], f[2], BASE + 10, f[3] + math.floor(rng:range(-6, 6)), rng:range(5, 7), math.floor(rng:range(2, 4)), rng)
	end

	return m
end

return Spires
