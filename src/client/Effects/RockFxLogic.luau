--[[
	RockFxLogic: the pure math of the rock breaking animation, shared by the
	client (Effects/RockFx.luau) and the preview tools: which debris pieces a
	crack or a shatter throws, in which colors, and where each piece is at time
	t (a ballistic arc that bounces on the ground, spins, then shrinks and
	fades). Also the envelopes of the flash light, the ground ring and the
	small shake of a rock that is being blasted, and the few chips every hit
	knocks off (chipPlan). No services, no Instances.

	Caps (phones): at most Cap = 30 debris pieces alive at once and every piece
	is gone after MaxLife = 1.5 s; a burst that would go over the cap throws
	fewer pieces (budget), keeping the mix of rock chunks and crystal shards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))

local RockFxLogic = {}

export type Piece = {
	Kind: string, -- "Chunk" (rock) | "Shard" (crystal)
	Wedge: boolean, -- WedgePart instead of a block
	Size: Vector3,
	Color: Color3,
	Neon: boolean,
	Origin: Vector3,
	Velocity: Vector3,
	Spin: Vector3, -- radians per second around X, Y, Z
	Turn: Vector3, -- start angles
	Life: number, -- seconds (<= MaxLife)
	Ground: number, -- Y of the ground it bounces on
}

export type Colors = {
	Rock: { Color3 }, -- chunks
	Crystal: { Color3 }, -- shards
	Glow: Color3, -- sparks, flash, ring
	Neon: boolean, -- crystal shards glow (deeper floors)
}

export type ShatterOpts = {
	Position: Vector3, -- the rock's center
	Crust: Color3, -- rock color from the server (used when Floor is unknown)
	Glow: Color3,
	Floor: number?,
	Kind: string?,
	Radius: number?,
	Ground: number?,
	Alive: number?, -- pieces already flying
	Seed: (number | string)?,
}

export type CrackOpts = {
	Position: Vector3, -- the hit point
	Crust: Color3,
	Glow: Color3,
	Stage: number,
	Stages: number?,
	Out: Vector3?, -- the direction pieces spray to (toward the shooter / camera)
	Ground: number?,
	Alive: number?,
	Seed: (number | string)?,
}

RockFxLogic.Cap = 30
RockFxLogic.ChipCap = 8 -- hit chips (chipPlan) alive at once: a cap of their own, outside Cap
RockFxLogic.MaxLife = 1.5
RockFxLogic.Gravity = 80
RockFxLogic.Bounce = 0.35 -- vertical speed kept at a bounce
RockFxLogic.Friction = 0.55 -- horizontal speed kept at a bounce

-- Pieces a shatter throws per rock kind (before the cap).
RockFxLogic.Counts = {
	Small = { Chunks = 10, Shards = 6 },
	Big = { Chunks = 13, Shards = 6 },
	Crystal = { Chunks = 7, Shards = 12 },
	Golden = { Chunks = 12, Shards = 8 },
	Geode = { Chunks = 10, Shards = 10 },
	Artifact = { Chunks = 10, Shards = 8 },
	Giant = { Chunks = 14, Shards = 16 },
} :: { [string]: { Chunks: number, Shards: number } }

-- Colors every floor shares for the special rocks (the same as RockBuilder.Special).
RockFxLogic.Special = {
	Gold = Color3.fromRGB(255, 196, 52),
	GoldDeep = Color3.fromRGB(196, 132, 30),
	Geode = Color3.fromRGB(176, 104, 255),
	GeodeShell = Color3.fromRGB(74, 62, 84),
	Rune = Color3.fromRGB(90, 255, 214),
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2

---------------------------------------------------------------- colors and budget

-- The colors of a rock's debris: its floor's palette, or shades of the crust / glow colors (old events).
function RockFxLogic.colors(floor: number?, kind: string?, crust: Color3, glow: Color3): Colors
	local def = if floor then MineFloors.ByIndex[floor] else nil
	local rock: { Color3 }
	local crystal: { Color3 }
	local neon: boolean
	if def then
		local pal = def.Palette
		rock = { pal.Mid, pal.Light, pal.Dark }
		crystal = { pal.Crystal, pal.Crystal2 }
		neon = def.Index >= 2
	else
		rock = { crust, crust:Lerp(WHITE, 0.3), crust:Lerp(BLACK, 0.35) }
		crystal = { glow, glow:Lerp(WHITE, 0.45) }
		neon = true
	end
	local s = RockFxLogic.Special
	if kind == "Golden" then
		rock = { s.Gold, s.GoldDeep, s.Gold:Lerp(WHITE, 0.35) }
		crystal = { s.Gold:Lerp(WHITE, 0.3), glow }
		neon = true
	elseif kind == "Geode" then
		rock = { s.GeodeShell, s.GeodeShell:Lerp(WHITE, 0.2), s.GeodeShell:Lerp(BLACK, 0.3) }
		crystal = { s.Geode, s.Geode:Lerp(WHITE, 0.4) }
		neon = true
	elseif kind == "Artifact" then
		crystal = { s.Rune, crystal[1] }
		neon = true
	end
	return { Rock = rock, Crystal = crystal, Glow = glow, Neon = neon }
end

--[[
	How many chunks and shards fit under the cap when `alive` pieces already
	fly: all of them when they fit, else fewer of both in the same mix
	(at least one of each when two or more still fit).
]]
function RockFxLogic.budget(wantChunks: number, wantShards: number, alive: number, cap: number?): (number, number)
	local free = math.max(0, (cap or RockFxLogic.Cap) - alive)
	local want = wantChunks + wantShards
	if want <= free then
		return wantChunks, wantShards
	end
	if free <= 0 then
		return 0, 0
	end
	local chunks = math.floor(free * wantChunks / want + 0.5)
	local least = if wantChunks > 0 and wantShards > 0 and free >= 2 then 1 else 0
	chunks = math.clamp(chunks, least, free - least)
	return chunks, math.min(wantShards, free - chunks)
end

---------------------------------------------------------------- plans

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, 1)
end

-- Every piece of a shatter: rock chunks fly out in a ring, crystal shards higher and faster.
function RockFxLogic.shatterPlan(opts: ShatterOpts): { Piece }
	local kind = opts.Kind or "Small"
	local giant = kind == "Giant"
	local counts = RockFxLogic.Counts[kind] or RockFxLogic.Counts.Small
	local radius = opts.Radius or (if giant then 7 else 2.5)
	local colors = RockFxLogic.colors(opts.Floor, kind, opts.Crust, opts.Glow)
	local chunks, shards = RockFxLogic.budget(counts.Chunks, counts.Shards, opts.Alive or 0)
	local rng = Rng.new(opts.Seed or "shatter")
	local pos = opts.Position
	local ground = opts.Ground or (pos.Y - radius * 0.6)
	local size = math.clamp(radius / 2.5, 0.8, 2.2)
	local power = if giant then 1.35 else 1
	local start = rng:range(0, TAU)
	local pieces: { Piece } = {}
	for i = 1, chunks do
		local yaw = start + (i / math.max(1, chunks)) * TAU + rng:range(-0.4, 0.4)
		local out = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local s = rng:range(0.35, 0.8) * size
		table.insert(pieces, {
			Kind = "Chunk",
			Wedge = i % 2 == 0,
			Size = Vector3.new(s, s * rng:range(0.6, 1.1), s * rng:range(0.7, 1.2)),
			Color = colors.Rock[(i - 1) % #colors.Rock + 1],
			Neon = false,
			Origin = pos + out * (rng:range(0.2, 0.7) * radius) + Vector3.new(0, rng:range(-0.3, 0.5) * radius, 0),
			Velocity = out * (rng:range(9, 17) * power) + Vector3.new(0, rng:range(14, 26) * math.sqrt(power), 0),
			Spin = Vector3.new(rng:range(-9, 9), rng:range(-9, 9), rng:range(-9, 9)),
			Turn = Vector3.new(rng:range(0, TAU), rng:range(0, TAU), rng:range(0, TAU)),
			Life = rng:range(0.95, 1.35),
			Ground = ground,
		})
	end
	for i = 1, shards do
		local yaw = start + 0.5 + (i / math.max(1, shards)) * TAU + rng:range(-0.5, 0.5)
		local out = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local w = rng:range(0.16, 0.28) * size
		local first = (i - 1) % #colors.Crystal == 0
		table.insert(pieces, {
			Kind = "Shard",
			Wedge = false,
			Size = Vector3.new(w, rng:range(0.5, 0.95) * math.min(size, 1.5), w),
			Color = colors.Crystal[(i - 1) % #colors.Crystal + 1],
			-- deep floors glow; matte floors only light up their main crystal color (white neon looks like a lamp)
			Neon = colors.Neon or (first and i % 2 == 1),
			Origin = pos + out * (0.3 * radius) + Vector3.new(0, rng:range(0.2, 0.8) * radius, 0),
			Velocity = out * (rng:range(10, 20) * power) + Vector3.new(0, rng:range(18, 30) * math.sqrt(power), 0),
			Spin = Vector3.new(rng:range(-14, 14), rng:range(-6, 6), rng:range(-14, 14)),
			Turn = Vector3.new(rng:range(-0.6, 0.6), rng:range(0, TAU), rng:range(-0.6, 0.6)),
			Life = rng:range(0.85, 1.25),
			Ground = ground,
		})
	end
	return pieces
end

-- The pop of a crack stage: a few glowing shards in the stage's ore glow and rock chips, sprayed toward `Out`.
function RockFxLogic.crackPlan(opts: CrackOpts): { Piece }
	local total = opts.Stages or 3
	local last = opts.Stage >= total - 1
	local wantShards = if last then 5 else 4
	local chips, shards = RockFxLogic.budget(3, wantShards, opts.Alive or 0)
	local rng = Rng.new(opts.Seed or "crack")
	local pos = opts.Position
	local out = flat(opts.Out or Vector3.new(0, 0, 1))
	local side = Vector3.new(-out.Z, 0, out.X)
	local ground = opts.Ground or (pos.Y - 2)
	local rockColors = { opts.Crust, opts.Crust:Lerp(WHITE, 0.25), opts.Crust:Lerp(BLACK, 0.3) }
	local pieces: { Piece } = {}
	local function spray(spread: number): Vector3
		local s = rng:range(-spread, spread)
		return (out + side * s).Unit
	end
	for i = 1, shards do
		local w = rng:range(0.12, 0.22)
		table.insert(pieces, {
			Kind = "Shard",
			Wedge = false,
			Size = Vector3.new(w, rng:range(0.4, 0.75), w),
			Color = if i % 2 == 0 then opts.Glow:Lerp(WHITE, 0.35) else opts.Glow,
			Neon = true,
			Origin = pos + out * 0.2,
			Velocity = spray(1.1) * rng:range(7, 13) + Vector3.new(0, rng:range(12, 20), 0),
			Spin = Vector3.new(rng:range(-16, 16), rng:range(-8, 8), rng:range(-16, 16)),
			Turn = Vector3.new(rng:range(0, TAU), rng:range(0, TAU), rng:range(0, TAU)),
			Life = rng:range(0.6, 0.85),
			Ground = ground,
		})
	end
	for i = 1, chips do
		local s = rng:range(0.3, 0.5)
		table.insert(pieces, {
			Kind = "Chunk",
			Wedge = i == 2,
			Size = Vector3.new(s, s * 0.8, s),
			Color = rockColors[(i - 1) % #rockColors + 1],
			Neon = false,
			Origin = pos + out * 0.2,
			Velocity = spray(0.9) * rng:range(5, 10) + Vector3.new(0, rng:range(10, 16), 0),
			Spin = Vector3.new(rng:range(-10, 10), rng:range(-10, 10), rng:range(-10, 10)),
			Turn = Vector3.new(rng:range(0, TAU), rng:range(0, TAU), rng:range(0, TAU)),
			Life = rng:range(0.7, 0.95),
			Ground = ground,
		})
	end
	return pieces
end

export type ChipOpts = {
	Position: Vector3, -- where the hit cracks the rock (the crack's centre)
	Crust: Color3,
	Out: Vector3?, -- the face's outward normal (chips spray off it, toward the viewer)
	Count: number?, -- chips wanted (default 3)
	Ground: number?,
	Alive: number?,
	Seed: (number | string)?,
}

--[[
	The chips of one hit (the owner's mining reel 2026-10-27: "little chips fly
	off every hit"): a few small rock chips in the crust colours only (never a
	glow: the ore stays secret), sprayed out of the face, short-lived. Under
	their own ChipCap (`Alive` = chips already flying), so they never take the
	room of a crack or a break.
]]
function RockFxLogic.chipPlan(opts: ChipOpts): { Piece }
	local want = math.max(0, opts.Count or 3)
	local count = math.min(want, math.max(0, RockFxLogic.ChipCap - (opts.Alive or 0)))
	local rng = Rng.new(opts.Seed or "chip")
	local pos = opts.Position
	local outward = opts.Out or Vector3.new(0, 0, 1)
	local out = if outward.Magnitude > 0.01 then outward.Unit else Vector3.new(0, 0, 1)
	local across = flat(out)
	local side = Vector3.new(-across.Z, 0, across.X)
	local ground = opts.Ground or (pos.Y - 2)
	local rockColors = { opts.Crust, opts.Crust:Lerp(WHITE, 0.3), opts.Crust:Lerp(BLACK, 0.35) }
	local pieces: { Piece } = {}
	for i = 1, count do
		local s = rng:range(0.14, 0.3)
		local spray = (out + side * rng:range(-0.9, 0.9) + Vector3.new(0, rng:range(-0.1, 0.5), 0)).Unit
		table.insert(pieces, {
			Kind = "Chunk",
			Wedge = i % 2 == 0,
			Size = Vector3.new(s, s * rng:range(0.6, 0.9), s * rng:range(0.8, 1.2)),
			Color = rockColors[(i - 1) % #rockColors + 1],
			Neon = false,
			Origin = pos + out * 0.15,
			Velocity = spray * rng:range(6, 11) + Vector3.new(0, rng:range(7, 13), 0),
			Spin = Vector3.new(rng:range(-14, 14), rng:range(-14, 14), rng:range(-14, 14)),
			Turn = Vector3.new(rng:range(0, TAU), rng:range(0, TAU), rng:range(0, TAU)),
			Life = rng:range(0.5, 0.75),
			Ground = ground,
		})
	end
	return pieces
end

---------------------------------------------------------------- motion

--[[
	Where a piece is `t` seconds after it was thrown: (CFrame, size scale,
	transparency, done). Flies on a ballistic arc, bounces twice on its Ground
	(losing speed and spin), pops in over the first 0.06 s, shrinks after 60 %
	of its life and fades after 72 %.
]]
function RockFxLogic.sample(piece: Piece, t: number): (CFrame, number, number, boolean)
	local g = RockFxLogic.Gravity
	local life = piece.Life
	local remaining = math.clamp(t, 0, life)
	local p = piece.Origin
	local v = piece.Velocity
	local floorY = piece.Ground + math.min(piece.Size.X, piece.Size.Y, piece.Size.Z) * 0.5
	local angle = Vector3.zero
	local spin = piece.Spin
	for bounce = 0, 2 do
		local height = math.max(0, p.Y - floorY)
		local hit = (v.Y + math.sqrt(math.max(0, v.Y * v.Y + 2 * g * height))) / g
		if remaining <= hit then
			p = p + Vector3.new(v.X * remaining, v.Y * remaining - 0.5 * g * remaining * remaining, v.Z * remaining)
			angle += spin * remaining
			remaining = 0
			break
		end
		p = Vector3.new(p.X + v.X * hit, floorY, p.Z + v.Z * hit)
		angle += spin * hit
		remaining -= hit
		local up = -(v.Y - g * hit) * RockFxLogic.Bounce
		v = Vector3.new(v.X * RockFxLogic.Friction, up, v.Z * RockFxLogic.Friction)
		spin *= 0.5
		if bounce == 2 or up < 2 then
			-- resting: a short slide, then it lies still
			local slide = math.min(remaining, 0.12)
			p += Vector3.new(v.X * slide, 0, v.Z * slide)
			angle += spin * slide
			break
		end
	end
	if p.Y < floorY then
		p = Vector3.new(p.X, floorY, p.Z)
	end
	local turn = piece.Turn + angle
	local cf = CFrame.new(p) * CFrame.Angles(turn.X, turn.Y, turn.Z)
	local k = math.clamp(t / life, 0, 1)
	local scale = if k < 0.6 then 1 else 1 - 0.8 * ((k - 0.6) / 0.4) ^ 1.5
	if t < 0.06 then
		scale *= 0.5 + 0.5 * math.max(0, t) / 0.06
	end
	local base = if piece.Neon then 0.05 else 0
	local transparency = if k < 0.72 then base else base + (1 - base) * ((k - 0.72) / 0.28)
	return cf, scale, math.clamp(transparency, 0, 1), t >= life
end

-- Brightness (0..1) of a flash `t` seconds in: a fast rise, then it fades out by `duration`.
function RockFxLogic.flash(t: number, duration: number): number
	if t <= 0 or t >= duration then
		return 0
	end
	local rise = math.min(0.035, duration * 0.3)
	if t < rise then
		return t / rise
	end
	local k = (t - rise) / (duration - rise)
	return (1 - k) * (1 - k)
end

-- The ground ring of a shatter: (diameter, transparency) growing from r0 to r1 over `duration`.
function RockFxLogic.ring(t: number, duration: number, r0: number, r1: number): (number, number)
	local k = math.clamp(t / duration, 0, 1)
	local ease = 1 - (1 - k) ^ 3
	return 2 * (r0 + (r1 - r0) * ease), 0.15 + 0.85 * k
end

--[[
	The ground ring of a shatter as `count` thin bars around a circle (a
	Cylinder part would be a solid disc): the frame of each bar (length along
	its Z) and the bar length, for a ring `diameter` studs across at `center`.
]]
function RockFxLogic.ringSegments(center: Vector3, diameter: number, count: number): ({ CFrame }, number)
	local r = diameter / 2
	local length = 2 * r * math.tan(math.pi / count) + 0.05
	local frames: { CFrame } = {}
	for i = 1, count do
		local a = (i - 1) / count * TAU
		local position = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		table.insert(frames, CFrame.new(position) * CFrame.Angles(0, -a, 0))
	end
	return frames, length
end

-- The tremble of a rock being blasted: a small offset (studs / radians) around its pivot, gone at `duration`.
function RockFxLogic.shakeOffset(t: number, duration: number, strength: number, seed: number): CFrame
	if t >= duration or t < 0 then
		return CFrame.identity
	end
	local a = strength * (1 - t / duration)
	local x = math.sin(t * 95 + seed) * a
	local z = math.cos(t * 83 + seed * 1.7) * a
	local roll = math.sin(t * 70 + seed * 0.6) * a * 0.05
	return CFrame.new(x, 0, z) * CFrame.Angles(roll, 0, -roll)
end

return RockFxLogic
