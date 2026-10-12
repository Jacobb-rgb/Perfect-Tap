--[[
	2D geometry for the cleaning minigame (face coordinates: the ore face is
	roughly the unit disc, x = right, y = up). Pure math, shared by client
	(visuals, live feedback) and server (re-scoring the player's input).
]]

local Geometry2D = {}

export type Poly = { Vector2 }

local EPS = 1e-9

function Geometry2D.cross(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

function Geometry2D.perp(v: Vector2): Vector2
	return Vector2.new(-v.Y, v.X)
end

function Geometry2D.rotate(v: Vector2, angle: number): Vector2
	local c, s = math.cos(angle), math.sin(angle)
	return Vector2.new(v.X * c - v.Y * s, v.X * s + v.Y * c)
end

function Geometry2D.area(poly: Poly): number
	local sum = 0
	for i = 1, #poly do
		local a = poly[i]
		local b = poly[i % #poly + 1]
		sum += a.X * b.Y - b.X * a.Y
	end
	return sum / 2
end

function Geometry2D.centroid(poly: Poly): Vector2
	local sum = Vector2.zero
	for _, p in poly do
		sum += p
	end
	return if #poly > 0 then sum / #poly else Vector2.zero
end

--[[
	Keeps the part of a polygon where n·x <= c (keepInside = true) or
	n·x >= c (keepInside = false). Sutherland-Hodgman against one half-plane.
]]
function Geometry2D.clip(poly: Poly, n: Vector2, c: number, keepInside: boolean): Poly
	local out: Poly = {}
	local count = #poly
	if count == 0 then
		return out
	end
	local function value(p: Vector2): number
		local d = n:Dot(p) - c
		return if keepInside then d else -d
	end
	for i = 1, count do
		local current = poly[i]
		local nextPoint = poly[i % count + 1]
		local vc, vn = value(current), value(nextPoint)
		if vc <= 0 then
			table.insert(out, current)
		end
		if (vc < 0 and vn > 0) or (vc > 0 and vn < 0) then
			local t = vc / (vc - vn)
			table.insert(out, current + (nextPoint - current) * t)
		end
	end
	-- drop duplicate neighbours
	local cleaned: Poly = {}
	for i, p in out do
		local prev = out[(i - 2) % #out + 1]
		if #out < 2 or (p - prev).Magnitude > 1e-6 then
			table.insert(cleaned, p)
		end
	end
	return cleaned
end

function Geometry2D.containsConvex(poly: Poly, p: Vector2): boolean
	local sign = 0
	for i = 1, #poly do
		local a = poly[i]
		local b = poly[i % #poly + 1]
		local c = Geometry2D.cross(b - a, p - a)
		if math.abs(c) > EPS then
			local s = if c > 0 then 1 else -1
			if sign == 0 then
				sign = s
			elseif s ~= sign then
				return false
			end
		end
	end
	return true
end

--[[
	Intersection of the line point + t*dir with a convex polygon.
	Returns tMin, tMax (nil if the line misses).
]]
function Geometry2D.lineSpan(poly: Poly, point: Vector2, dir: Vector2): (number?, number?)
	local tMin, tMax = -math.huge, math.huge
	-- polygon is assumed counter-clockwise; edges have outward normals
	local ccw = Geometry2D.area(poly) > 0
	for i = 1, #poly do
		local a = poly[i]
		local b = poly[i % #poly + 1]
		local edge = b - a
		local outward = if ccw then Vector2.new(edge.Y, -edge.X) else Vector2.new(-edge.Y, edge.X)
		local denom = outward:Dot(dir)
		local num = outward:Dot(a - point)
		if math.abs(denom) < EPS then
			if num < 0 then
				return nil, nil
			end
		else
			local t = num / denom
			if denom > 0 then
				tMax = math.min(tMax, t)
			else
				tMin = math.max(tMin, t)
			end
		end
	end
	if tMin > tMax then
		return nil, nil
	end
	return tMin, tMax
end

function Geometry2D.polylineLength(line: { Vector2 }): number
	local length = 0
	for i = 2, #line do
		length += (line[i] - line[i - 1]).Magnitude
	end
	return length
end

--[[
	Closest point on a polyline.
	Returns distance, arc-length parameter s, the closest point, and the
	side (+1 left of travel direction, -1 right).
]]
function Geometry2D.closest(line: { Vector2 }, p: Vector2): (number, number, Vector2, number)
	local bestDistance, bestS, bestPoint, bestSide = math.huge, 0, line[1], 1
	local walked = 0
	for i = 2, #line do
		local a, b = line[i - 1], line[i]
		local ab = b - a
		local len = ab.Magnitude
		if len > EPS then
			local t = math.clamp((p - a):Dot(ab) / (len * len), 0, 1)
			local q = a + ab * t
			local d = (p - q).Magnitude
			if d < bestDistance then
				bestDistance = d
				bestS = walked + len * t
				bestPoint = q
				bestSide = if Geometry2D.cross(ab, p - a) >= 0 then 1 else -1
			end
		end
		walked += len
	end
	return bestDistance, bestS, bestPoint, bestSide
end

-- Point and unit tangent at arc length s along a polyline.
function Geometry2D.pointAt(line: { Vector2 }, s: number): (Vector2, Vector2)
	local walked = 0
	for i = 2, #line do
		local a, b = line[i - 1], line[i]
		local len = (b - a).Magnitude
		if walked + len >= s or i == #line then
			local t = if len > EPS then math.clamp((s - walked) / len, 0, 1) else 0
			local tangent = if len > EPS then (b - a) / len else Vector2.new(1, 0)
			return a + (b - a) * t, tangent
		end
		walked += len
	end
	return line[#line], Vector2.new(1, 0)
end

-- Fan triangulation of a convex polygon: list of {a, b, c}.
function Geometry2D.triangulateConvex(poly: Poly): { { Vector2 } }
	local tris = {}
	for i = 2, #poly - 1 do
		table.insert(tris, { poly[1], poly[i], poly[i + 1] })
	end
	return tris
end

return Geometry2D
