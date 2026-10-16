--[[
	Sky package kit: small builders shared by the Sky set pieces (floating
	islands, ship hulls, timber, mist). Pure: Instance creation only.

	Everything in the sky and on the far sea is decoration nobody can reach:
	no collision, no raycasts, no shadows (`Kit.far()`), Style.C colors only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)

local C = Style.C
local NEON = Enum.Material.Neon

local Kit = {}

type Opts = { [string]: any }

-- Unreachable decoration: no collision, no query, no shadow.
function Kit.far(extra: Opts?): Opts
	return Style.tiny(extra)
end

-- A block in a frame: `at` is the block's center in frame space.
function Kit.box(parent: Instance, frame: CFrame, at: Vector3, size: Vector3, color: Color3, material: Enum.Material?, props: Opts?): Part
	return Style.block(parent, frame * CFrame.new(at), size, color, material, props or Kit.far())
end

-- Neon block (never casts a shadow).
function Kit.glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3, transparency: number?): Part
	return Style.block(parent, cf, size, color, NEON, Kit.far({ Transparency = transparency or 0 }))
end

-- A beam between two points (square section, `thickness` wide).
function Kit.beam(parent: Instance, a: Vector3, b: Vector3, thickness: number, color: Color3, props: Opts?): Part
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	return Style.block(parent, cf, Vector3.new(thickness, thickness, length), color, nil, props or Kit.far())
end

-- A small lit window: dark frame + Lamp neon pane, 2 parts. `cf` = pane
-- center, LookVector = outward.
function Kit.window(parent: Instance, cf: CFrame, width: number, height: number, frameColor: Color3?): Part
	Style.block(parent, cf * CFrame.new(0, 0, 0.12), Vector3.new(width + 0.5, height + 0.5, 0.3), frameColor or C.WoodDark, nil, Kit.far())
	local pane = Kit.glow(parent, cf * CFrame.new(0, 0, -0.06), Vector3.new(width, height, 0.2), C.Lamp)
	pane.Name = "WindowGlow"
	return pane
end

--[[
	Floating voxel island. `frame` = center of the grass top surface (the
	island's ground point), LookVector = the island's front. Builds a grass
	slab with a lighter cap and edge lumps, a dirt band, `Tiers` inverted
	stone tiers (StoneDark -> StoneDeep) narrowing to a point `Hang` studs
	below, and a few hanging chunks. opts: Width, Depth, Hang, Tiers (4-5).
	About 20-26 parts.
]]
function Kit.floatingIsland(parent: Instance, frame: CFrame, rng: Rng.Rng, opts: Opts): Model
	local m = Style.model("Rock", parent)
	local w: number = opts.Width
	local d: number = opts.Depth
	local hang: number = opts.Hang or 34
	local tiers: number = opts.Tiers or 5
	-- grass slab, lighter cap, edge lumps that break the rectangle
	Kit.box(m, frame, Vector3.new(0, -1, 0), Vector3.new(w, 2, d), Style.vary(C.Grass, rng, 0.03))
	Kit.box(m, frame, Vector3.new(rng:range(-1, 1), 0.15, rng:range(-1, 1)), Vector3.new(w * 0.62, 0.4, d * 0.6), C.GrassLight)
	for i = 1, 4 do
		local side = if i % 2 == 0 then 1 else -1
		local alongX = i <= 2
		local s = Vector3.new(rng:range(5, 9), 2, rng:range(4, 7))
		-- each lump pokes out of the edge by at most a quarter of its size
		local at = if alongX
			then Vector3.new(rng:range(-w * 0.3, w * 0.3), -1.2, side * (d / 2 - s.Z * 0.25))
			else Vector3.new(side * (w / 2 - s.X * 0.25), -1.2, rng:range(-d * 0.3, d * 0.3))
		Kit.box(m, frame, at, s, Style.vary(C.GrassDark, rng, 0.04))
	end
	-- dirt band under the grass
	Kit.box(m, frame, Vector3.new(0, -3.4, 0), Vector3.new(w * 0.97, 2.8, d * 0.97), Style.vary(C.DirtDark, rng, 0.04))
	-- inverted stone tiers narrowing to a point
	local top = -4.8
	local tierH = (hang - 4.8) / (tiers + 0.6)
	local cx, cz = 0, 0
	for i = 1, tiers do
		local k = 1 - (i - 0.4) / (tiers + 0.4)
		local tw = math.max(3, w * 0.94 * k)
		local td = math.max(3, d * 0.94 * k)
		cx += rng:range(-1.2, 1.2)
		cz += rng:range(-1.2, 1.2)
		local h = tierH * rng:range(0.95, 1.15)
		-- lighter stone under the grass, darker toward the point
		local t = (i - 1) / math.max(1, tiers - 1)
		local color = if t < 0.5 then C.Stone:Lerp(C.StoneDark, t * 2) else C.StoneDark:Lerp(C.StoneDeep, t * 2 - 1)
		Kit.box(m, frame, Vector3.new(cx, top - h / 2, cz), Vector3.new(tw, h, td), Style.vary(color, rng, 0.05))
		-- a protruding block on a random side (voxel silhouette)
		local sx = if rng:chance(0.5) then 1 else -1
		local s = Vector3.new(tw * 0.32, h * rng:range(0.6, 0.9), td * 0.4)
		Kit.box(
			m,
			frame,
			Vector3.new(cx + sx * (tw / 2), top - h * 0.55, cz + rng:range(-td * 0.25, td * 0.25)),
			s,
			Style.vary(if rng:chance(0.4) then C.StoneLight else C.Stone, rng, 0.05)
		)
		-- hanging chunk under the tier's edge
		if i < tiers then
			local hs = rng:range(2, 3.4)
			Kit.box(
				m,
				frame,
				Vector3.new(cx + rng:range(-tw * 0.42, tw * 0.42), top - h - hs * 0.4, cz + rng:range(-td * 0.42, td * 0.42)),
				Vector3.new(hs, hs * 1.3, hs),
				Style.vary(C.StoneDeep, rng, 0.05)
			)
		end
		top -= h
	end
	-- the point
	Kit.box(m, frame, Vector3.new(cx, math.max(-hang + 2, top - 2), cz), Vector3.new(2.4, 4, 2.4), C.StoneDeep)
	return m
end

--[[
	A waterfall pouring off an island edge into thin air: water lip, a sheet
	that fades out in three steps (more transparent each), three neon foam
	streaks (one CrystalCyan) and a cloud of mist at the bottom. `top` = center of the lip,
	LookVector = the side the water faces. 10 parts.
]]
function Kit.skyFall(parent: Instance, top: CFrame, height: number, width: number, rng: Rng.Rng): Model
	local m = Style.model("Waterfall", parent)
	Style.block(m, top * CFrame.new(0, 0.1, 0.4), Vector3.new(width + 0.8, 1, 1.6), C.Water, nil, Kit.far())
	local y = 0
	local steps = { { 0.5, 0.1 }, { 0.3, 0.3 }, { 0.2, 0.55 } }
	for i, step in steps do
		local h = height * step[1]
		local w = width * (1 - (i - 1) * 0.12)
		local sheet = Style.block(
			m,
			top * CFrame.new(0, y - h / 2, 0),
			Vector3.new(w, h, 0.6),
			C.Falls,
			nil,
			Kit.far({ Transparency = step[2], Reflectance = 0.08 })
		)
		sheet.Name = "Water"
		y -= h
	end
	for i = 1, 3 do
		local x = (i - 2) * width * 0.28 + rng:range(-0.4, 0.4)
		local h = height * rng:range(0.4, 0.75)
		local color = if i == 2 then C.CrystalCyan else C.Foam
		Kit.glow(m, top * CFrame.new(x, -h / 2 - 0.3, -0.4), Vector3.new(math.max(0.4, width * 0.1), h, 0.2), color, 0.3)
	end
	-- mist where the water breaks up
	local mist: Part? = nil
	for i = 1, 3 do
		local s = width * rng:range(0.5, 0.8)
		local p = Style.block(
			m,
			top * CFrame.new(rng:range(-width * 0.35, width * 0.35), -height + i * 1.2, rng:range(-1, 1)),
			Vector3.new(s, s * 0.6, s * 0.7),
			C.Foam,
			nil,
			Kit.far({ Transparency = 0.55 + i * 0.1 })
		)
		mist = mist or p
	end
	if mist then
		Style.emitter(mist, "Mist", C.Foam, 3)
	end
	return m
end

--[[
	Stepped voxel ship hull. `frame` = bottom center at the keel, LookVector =
	the bow. opts: Length, Beam, Height (hull side height). Keel WoodDark,
	sides Wood, a RoofTrim stripe, a Plank deck, a stepped bow and a raised
	stern castle. Returns the model, the deck height and the keel part.
	About 14 parts.
]]
function Kit.hull(parent: Instance, frame: CFrame, rng: Rng.Rng, opts: Opts): (Model, number, Part)
	local m = Style.model("Hull", parent)
	local len: number = opts.Length
	local beam: number = opts.Beam
	local hh: number = opts.Height or 4
	local keel = Kit.box(m, frame, Vector3.new(0, 0.6, 0), Vector3.new(beam * 0.34, 1.2, len * 0.72), C.WoodDark)
	keel.Name = "Keel"
	Kit.box(m, frame, Vector3.new(0, 1.2 + hh * 0.2, 0.02 * len), Vector3.new(beam * 0.7, hh * 0.4, len * 0.8), Style.vary(C.WoodDark, rng, 0.04))
	Kit.box(m, frame, Vector3.new(0, 1.2 + hh * 0.7, 0.04 * len), Vector3.new(beam, hh * 0.6, len * 0.78), Style.vary(C.Wood, rng, 0.04))
	-- stripe and gunwale
	Kit.box(m, frame, Vector3.new(0, 1.2 + hh * 0.62, 0.04 * len), Vector3.new(beam + 0.25, hh * 0.14, len * 0.79), C.RoofTrim)
	Kit.box(m, frame, Vector3.new(0, 1.2 + hh + 0.25, 0.04 * len), Vector3.new(beam + 0.2, 0.5, len * 0.8), C.WoodDark)
	local deckY = 1.2 + hh
	Kit.box(m, frame, Vector3.new(0, deckY + 0.1, 0.04 * len), Vector3.new(beam - 1, 0.3, len * 0.76), C.Plank)
	-- stepped bow (toward -Z = LookVector)
	Kit.box(m, frame, Vector3.new(0, 1.2 + hh * 0.62, -len * 0.42), Vector3.new(beam * 0.66, hh * 0.9, len * 0.12), Style.vary(C.Wood, rng, 0.04))
	Kit.box(m, frame, Vector3.new(0, 1.2 + hh * 0.72, -len * 0.5), Vector3.new(beam * 0.34, hh * 0.8, len * 0.06), C.WoodDark)
	Kit.beam(m, (frame * CFrame.new(0, deckY + 0.4, -len * 0.48)).Position, (frame * CFrame.new(0, deckY + 2.2, -len * 0.64)).Position, 0.5, C.WoodDark)
	-- stern castle (toward +Z)
	local castleLen = len * 0.24
	local castleZ = len * 0.4 - castleLen / 2 + 0.04 * len
	Kit.box(m, frame, Vector3.new(0, deckY + 1.2, castleZ), Vector3.new(beam * 0.96, 2.4, castleLen), Style.vary(C.Wood, rng, 0.04))
	Kit.box(m, frame, Vector3.new(0, deckY + 2.55, castleZ), Vector3.new(beam, 0.5, castleLen + 0.3), C.WoodDark)
	Kit.box(m, frame, Vector3.new(0, deckY + 1.0, castleZ + castleLen / 2 + 0.05), Vector3.new(beam * 0.9, 0.5, 0.3), C.RoofTrim)
	return m, deckY, keel
end

--[[
	Mast with square sails: `base` = foot of the mast on the deck (LookVector
	= the ship's bow). Each sail is 2 blocks (a flat sheet and a bowed belly
	pushed forward) under a WoodDark yard; a red pennant at the top.
	sails = { { width, height } } bottom to top. 3 + 3 per sail parts.
]]
function Kit.mast(parent: Instance, base: CFrame, height: number, sails: { { number } }, rng: Rng.Rng): Model
	local m = Style.model("Mast", parent)
	Style.block(m, base * CFrame.new(0, height / 2, 0), Vector3.new(0.8, height, 0.8), C.WoodDark, nil, Kit.far())
	local y = height * 0.2
	for i, sail in sails do
		local sw, sh = sail[1], sail[2]
		local color = if i % 2 == 1 then C.AwningWhite else C.FlagLight
		local cy = y + sh / 2
		Style.block(m, base * CFrame.new(0, cy, -0.5), Vector3.new(sw, sh, 0.3), Style.vary(color, rng, 0.02), nil, Kit.far())
		Style.block(m, base * CFrame.new(0, cy - sh * 0.05, -0.95), Vector3.new(sw * 0.76, sh * 0.72, 0.4), Style.vary(color, rng, 0.03), nil, Kit.far())
		Style.block(m, base * CFrame.new(0, y + sh + 0.25, -0.4), Vector3.new(sw + 1.2, 0.5, 0.5), C.WoodDark, nil, Kit.far())
		y += sh + 0.9
	end
	-- pennant streaming backward (+Z)
	Style.block(m, base * CFrame.new(0, height - 0.6, 1.5), Vector3.new(0.2, 1, 2.6), C.AwningRed, nil, Kit.far())
	return m
end

return Kit
