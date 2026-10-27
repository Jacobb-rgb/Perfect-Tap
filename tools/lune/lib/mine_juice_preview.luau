--[[
	Helpers for the mining reel preview (tools/lune/export_mine_juice.luau):
	the game's growing cracks (Effects/CrackLogic, laid out the way
	Effects/RockCracks does it) on a rock without Roblox physics, and
	stand-ins for the particle bursts.

	  cast(model, origin, dir, maxT)  -> (position?, normal?): a ray against a
	        model's visible parts (blocks, wedges, balls; cylinders as boxes),
	        what Workspace:Raycast with an Include filter gives in the game
	  crack(Loader, parent, rock, plan, frame, growth, since, glints)
	        lays out the dark segments, gold glints and flecks of `plan` on the
	        rock (frame = { Origin, Normal, Right, Up } from the first hit),
	        projecting every plan point onto the surface like RockCracks.project
	  particles(...) / flashBall(...)  stand-ins of Vfx bursts (as in rock_fx_preview)
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}

local V3 = roblox.Vector3
local Enum = roblox.Enum

-- A ray against one part (convex: a box, a wedge = a box cut by its slope, a ball): t and the local normal.
local function rayPart(part, origin, dir, maxT): (number?, any?)
	local cf = part.CFrame
	local h = part.Size / 2
	if part.ClassName == "Part" and part.Shape == Enum.PartType.Ball then
		local r = math.min(h.X, h.Y, h.Z)
		local oc = origin - cf.Position
		local b = oc:Dot(dir)
		local c = oc:Dot(oc) - r * r
		local disc = b * b - c
		if disc < 0 then
			return nil, nil
		end
		local t = -b - math.sqrt(disc)
		if t < 0 or t > maxT then
			return nil, nil
		end
		return t, ((origin + dir * t) - cf.Position).Unit
	end
	local lo = cf:PointToObjectSpace(origin)
	local ld = cf:VectorToObjectSpace(dir)
	local planes = {
		{ V3.new(1, 0, 0), h.X },
		{ V3.new(-1, 0, 0), h.X },
		{ V3.new(0, 1, 0), h.Y },
		{ V3.new(0, -1, 0), h.Y },
		{ V3.new(0, 0, 1), h.Z },
		{ V3.new(0, 0, -1), h.Z },
	}
	if part.ClassName == "WedgePart" then
		-- the slope: low at the front (-Z), tall at the back (+Z): y / h.Y <= z / h.Z
		table.insert(planes, { V3.new(0, h.Z, -h.Y).Unit, 0 })
	end
	local enter, exit = 0, maxT
	local normal = nil
	for _, plane in planes do
		local n, d = plane[1], plane[2]
		local denom = n:Dot(ld)
		local num = d - n:Dot(lo)
		if math.abs(denom) < 1e-9 then
			if num < 0 then
				return nil, nil
			end
		else
			local t = num / denom
			if denom < 0 then
				if t > enter then
					enter, normal = t, n
				end
			elseif t < exit then
				exit = t
			end
			if enter > exit then
				return nil, nil
			end
		end
	end
	if not normal then
		return nil, nil -- (starts inside)
	end
	return enter, cf:VectorToWorldSpace(normal)
end

-- The nearest hit of a ray on a model's visible parts: (position, normal) or nil.
function Preview.cast(model, origin, dir, maxT: number): (any?, any?)
	local unit = dir.Unit
	local best, bestNormal = math.huge, nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local t, n = rayPart(d, origin, unit, maxT)
			if t and t < best then
				best, bestNormal = t, n
			end
		end
	end
	if bestNormal then
		return origin + unit * best, bestNormal
	end
	return nil, nil
end

-- The middle of a model's visible parts and its size (a bounding box).
function Preview.bounds(model): (any, any)
	local lo = V3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local r = d.CFrame
			local s = d.Size / 2
			local e = V3.new(
				math.abs(r.RightVector.X) * s.X + math.abs(r.UpVector.X) * s.Y + math.abs(r.LookVector.X) * s.Z,
				math.abs(r.RightVector.Y) * s.X + math.abs(r.UpVector.Y) * s.Y + math.abs(r.LookVector.Y) * s.Z,
				math.abs(r.RightVector.Z) * s.X + math.abs(r.UpVector.Z) * s.Y + math.abs(r.LookVector.Z) * s.Z
			)
			local p = r.Position
			lo = V3.new(math.min(lo.X, p.X - e.X), math.min(lo.Y, p.Y - e.Y), math.min(lo.Z, p.Z - e.Z))
			hi = V3.new(math.max(hi.X, p.X + e.X), math.max(hi.Y, p.Y + e.Y), math.max(hi.Z, p.Z + e.Z))
		end
	end
	return (lo + hi) / 2, hi - lo
end

--[[
	The crack of `plan` on `rock` at `growth`, `since` seconds after the last
	hit (the glints flare), the way Effects/RockCracks lays it out: every plan
	point projected onto the surface along the face normal, thin parts
	between them. Parts go into `parent`.
]]
function Preview.crack(Loader, parent, rock, plan, frame, growth: number, since: number, glints: boolean)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local CrackLogic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.CrackLogic")
	local JuiceConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.JuiceConfig")
	local reach = plan.Size * 1.5 + 2
	local points, normals, onRock = {}, {}, {}
	for i, p in plan.Points do
		local flat = CrackLogic.flatPoint(frame.Origin, frame.Right, frame.Up, p)
		local hit, normal = Preview.cast(rock, flat + frame.Normal * (reach * 0.5), frame.Normal * -1, reach)
		local ok = hit ~= nil and (hit - flat):Dot(frame.Normal) > -plan.Size * 0.8
		points[i] = if ok then hit else flat
		normals[i] = if ok then normal else frame.Normal
		onRock[i] = ok
	end
	local glow = CrackLogic.glint(since)
	local showGlint = glints and growth >= CrackLogic.GlintFrom
	local props = { CanCollide = false, CastShadow = false }
	for _, seg in plan.Segs do
		local f = CrackLogic.fraction(seg, growth)
		if f > 0 and onRock[seg.I] and onRock[seg.J] then
			local a = points[seg.I]
			local tip = a:Lerp(points[seg.J], f)
			local n = normals[seg.I] + normals[seg.J]
			n = if n.Magnitude > 1e-3 then n.Unit else frame.Normal
			local cf, length = CrackLogic.segmentFrame(a, tip, n, CrackLogic.Lift)
			Geo.block(
				parent,
				cf,
				V3.new(seg.Width, CrackLogic.Thickness, length + seg.Width * 0.6),
				JuiceConfig.CrackColor,
				Enum.Material.SmoothPlastic,
				props
			)
			if seg.Main and showGlint and length > seg.Width * 0.4 then
				Geo.block(
					parent,
					cf * Loader.CFrame.new(0, CrackLogic.Thickness * 0.3, 0),
					V3.new(seg.Width * CrackLogic.GlintWidth, CrackLogic.Thickness * 1.3, length - seg.Width * 0.2),
					JuiceConfig.GlintColor,
					Enum.Material.Neon,
					{ CanCollide = false, CastShadow = false, Transparency = glow }
				)
			end
		end
	end
	if glints then
		for i, index in plan.Flecks do
			if growth >= plan.FleckFrom[i] and onRock[index] then
				local s = CrackLogic.FleckSize * math.clamp(plan.Size / 2, 0.7, 1.6)
				local cf = Loader.CFrame.new(points[index] + normals[index] * 0.04) * Loader.CFrame.Angles(0.6, 0.785, 0.4)
				Geo.block(
					parent,
					cf,
					V3.new(s, s, s),
					JuiceConfig.GlintColor,
					Enum.Material.Neon,
					{ CanCollide = false, CastShadow = false, Transparency = glow * 0.6 }
				)
			end
		end
	end
	return points[1]
end

-- stand-in particles of one Vfx burst frozen at time t (dust puffs, sparkles, glints; as rock_fx_preview)
function Preview.particles(Geo, parent, rng, kind: string, center, count: number, color, t: number, scale: number?)
	local k = scale or 1
	for _ = 1, count do
		local dir = V3.new(rng:range(-1, 1), rng:range(-1, 1), rng:range(-1, 1))
		dir = if dir.Magnitude > 0.05 then dir.Unit else V3.new(0, 1, 0)
		if kind == "Dust" then
			local life = rng:range(0.6, 1.1)
			if t >= 0 and t < life then
				local speed = rng:range(3, 8) * k
				local p = center + dir * (speed / 4 * (1 - math.exp(-4 * t)))
				local f = t / life
				Geo.ball(
					parent,
					p,
					(1 + 2.2 * f) * k * 0.9,
					color,
					nil,
					{ CastShadow = false, CanCollide = false, Transparency = 0.5 + 0.45 * f }
				)
			end
		elseif kind == "Burst" then
			local life = rng:range(0.5, 1.1)
			if t >= 0 and t < life then
				local speed = rng:range(10, 24) * k
				local p = center + dir * (speed / 2.5 * (1 - math.exp(-2.5 * t)))
				Geo.ball(
					parent,
					p,
					math.max(0.08, 0.5 * (1 - t / life)) * k,
					color,
					Enum.Material.Neon,
					{ CastShadow = false, CanCollide = false }
				)
			end
		elseif kind == "Glint" then
			local life = rng:range(0.4, 0.9)
			if t >= 0 and t < life then
				local speed = rng:range(2, 7) * k
				local p = center + dir * (speed / 2 * (1 - math.exp(-2 * t)))
				local f = t / life
				local size = if f < 0.4 then 0.7 * f / 0.4 else 0.7 * (1 - (f - 0.4) / 0.6)
				Geo.ball(parent, p, math.max(0.06, size * 0.6) * k, color, Enum.Material.Neon, { CastShadow = false, CanCollide = false })
			end
		end
	end
end

-- a stand-in of Vfx.flash (a big soft glow) at time t
function Preview.flashBall(Geo, parent, position, color, size: number, t: number)
	local life = 0.17
	if t >= 0 and t < life then
		local f = t / life
		Geo.ball(
			parent,
			position,
			size * (0.7 + 0.3 * f) * 0.55,
			color,
			Enum.Material.Neon,
			{ CastShadow = false, CanCollide = false, Transparency = 0.35 + 0.6 * f }
		)
	end
end

-- RockFx debris pieces (RockFxLogic plans) at time t
function Preview.debris(Geo, parent, pieces, t: number, Logic)
	if t < 0 then
		return
	end
	for _, piece in pieces do
		local cf, scale, transparency, done = Logic.sample(piece, t)
		if not done and transparency < 0.98 then
			local material = if piece.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local props = { CastShadow = true, CanCollide = false, Transparency = transparency }
			if piece.Wedge then
				Geo.wedge(parent, cf, piece.Size * scale, piece.Color, material, props)
			else
				Geo.block(parent, cf, piece.Size * scale, piece.Color, material, props)
			end
		end
	end
end

return Preview
