--[[
	Spectrum: the colour theme of the mountain range behind the town and the
	voxel spires above it (owner's reference 2026-10-17: a skyline of square
	pillars, red / orange / gold low down, pink, lavender and white up high,
	warm yellow in the west, purple and crimson in the east).

	Spectrum.Theme picks the look:
	  "Classic"  the old blue-grey forge stone, no spires
	  "Sunset"   coloured stone, grassy ledges kept, spires
	  "Candy"    coloured stone with light tinted tops (no grass), spires
	  "Forge"    the old blue-grey stone with the coloured spires behind it
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)

local Spectrum = {}

Spectrum.Theme = "Candy"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- West to east lanes; each runs low -> mid -> high -> peak.
type Lane = { X: number, Stops: { Color3 } }
local LANES: { Lane } = {
	{ X = -170, Stops = { rgb(186, 48, 30), rgb(234, 124, 36), rgb(246, 186, 52), rgb(252, 214, 96) } },
	{ X = -60, Stops = { rgb(196, 56, 36), rgb(240, 132, 56), rgb(244, 150, 84), rgb(250, 186, 130) } },
	{ X = 10, Stops = { rgb(190, 40, 56), rgb(226, 84, 126), rgb(238, 118, 176), rgb(246, 172, 214) } },
	{ X = 70, Stops = { rgb(172, 36, 72), rgb(206, 92, 168), rgb(214, 140, 232), rgb(236, 200, 250) } },
	{ X = 125, Stops = { rgb(140, 40, 88), rgb(142, 90, 206), rgb(166, 128, 240), rgb(204, 182, 252) } },
	{ X = 170, Stops = { rgb(116, 30, 54), rgb(170, 48, 82), rgb(204, 72, 116), rgb(232, 128, 162) } },
}

local function along(stops: { Color3 }, t: number): Color3
	local f = math.clamp(t, 0, 1) * (#stops - 1)
	local i = math.min(math.floor(f) + 1, #stops - 1)
	return stops[i]:Lerp(stops[i + 1], f - (i - 1))
end

-- Colour of a voxel column at x whose top is `top` studs high.
function Spectrum.color(x: number, top: number, rng: Rng.Rng): Color3
	-- neighbours never match: jitter the height and the lane a little, and
	-- some low blocks turn orange / gold like the reference's foreground
	local t = math.clamp((top - 14) / 150 + rng:range(-0.1, 0.1), 0, 1)
	x += rng:range(-30, 30)
	if t < 0.4 and rng:chance(0.3) then
		t = math.clamp(t + rng:range(0.12, 0.25), 0, 1)
		x -= 60
	end
	local lane = LANES[#LANES]
	local color = along(lane.Stops, t)
	for i = 1, #LANES - 1 do
		local a, b = LANES[i], LANES[i + 1]
		if x <= b.X then
			local u = math.clamp((x - a.X) / (b.X - a.X), 0, 1)
			color = along(a.Stops, t):Lerp(along(b.Stops, t), u)
			break
		end
	end
	return Geo.vary(color, rng, 0.04)
end

-- Height strata: a column is cut into stacked blocks near these heights
-- (jittered per column), each coloured for its own height, so the range
-- shades from red at the foot to pale at the top like the reference.
local LEVELS = { 30, 52, 74, 96, 118, 140 }

-- A coloured voxel column filling min..max, cut at the strata. Returns the
-- top block.
function Spectrum.stack(parent: Instance, min: Vector3, max: Vector3, rng: Rng.Rng, props: { [string]: any }?): Part
	local x = (min.X + max.X) / 2
	local cuts: { number } = {}
	for _, level in LEVELS do
		local y = level + math.floor(rng:range(-5, 5))
		if y > min.Y + 4 and y < max.Y - 4 then
			table.insert(cuts, y)
		end
	end
	table.insert(cuts, max.Y)
	local y0 = min.Y
	local last: Part? = nil
	for _, y1 in cuts do
		last = Geo.block(
			parent,
			CFrame.new(x, (y0 + y1) / 2, (min.Z + max.Z) / 2),
			Vector3.new(max.X - min.X, y1 - y0, max.Z - min.Z),
			Spectrum.color(x, y1, rng),
			nil,
			props
		)
		y0 = y1
	end
	return last :: Part
end

-- The lit top face of a column: a paler version of its colour.
function Spectrum.tint(color: Color3): Color3
	return color:Lerp(Color3.new(1, 1, 1), 0.32)
end

function Spectrum.colored(): boolean
	return Spectrum.Theme == "Sunset" or Spectrum.Theme == "Candy"
end

function Spectrum.spires(): boolean
	return Spectrum.Theme ~= "Classic"
end

return Spectrum
