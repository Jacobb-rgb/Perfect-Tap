--[[
	WorldMotionLogic: the pure math of the world animations, shared by the
	client (Controllers/WorldMotionController) and the preview tools (the
	showreel runs this same code). No services, no Instances.

	- Golem followers: golemPose -> the extra (lift, pitch, yaw, roll) on top
	  of GolemController's own walk: a rounder hop with a wiggle and a nod
	  while walking, a sway and now and then a little hop in place while
	  standing ("waving"), the happy jump + spin on equip. Premium (hovering)
	  golems never hop: they rise and spin, and sway on their aura.
	- Ore popping out of a rock: popPose -> the visual arc, the extra spin,
	  the pop-in scale and the squash on landing of a fresh chunk's look.
	- Bits: small pooled parts (the white hit flash and its spikes, ore
	  cubes, dust cubes, banknotes, coins), planned by hitPlan / dustPlan /
	  cashPlan and moved by sample(bit, t).
	- Caps for phones and Reduce motion (caps, budget, *Counts).
	- A tiny part pool (newPool / take / give).
	- Machines (for MachineFxController, the integrator's file: not wired
	  here): machineShake / machinePop / machineGlow, the rumble of a working
	  machine, the hop when a job is done and the glow flash with it.
]]

local WorldMotionLogic = {}

local TAU = math.pi * 2
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

export type Bit = {
	Kind: string, -- "Flash" | "Spike" | "Cube" | "Dust" | "Note" | "Coin"
	Shape: string, -- the pooled part: "Block" | "Ball" | "Cylinder"
	Born: number, -- set by whoever spawns it
	Life: number,
	Origin: Vector3,
	Velocity: Vector3,
	Spin: Vector3, -- radians per second around X, Y, Z
	Turn: Vector3, -- start angles
	Size: Vector3,
	Color: Color3,
	Neon: boolean,
	Ground: number, -- Y of the ground it lands on
	Seed: number,
	-- Spike: the star of the hit flash, drawn in the plane facing the camera
	Right: Vector3,
	Up: Vector3,
	Angle: number,
	-- Coin: flies into Home (moved along by the controller) after HomeAt of its life
	Home: Vector3?,
	HomeAt: number,
}

export type Caps = { Bits: number, Pops: number, Flashes: number, Spikes: boolean, Spin: boolean }

export type HitOpts = {
	Position: Vector3,
	Back: Vector3?, -- toward the shooter (the cubes spray that way)
	Color: Color3, -- the ore colour the rock shows
	Right: Vector3, -- the camera's right / up: the flash star faces the viewer
	Up: Vector3,
	Ground: number,
	Seed: number,
	Small: boolean?, -- another player's hit: a smaller burst
	Phone: boolean?,
	Reduce: boolean?,
	Room: number?, -- bits that still fit (nil = no limit)
}

export type DustOpts = {
	Position: Vector3,
	Color: Color3,
	Ground: number,
	Seed: number,
	Landing: boolean, -- a flat ring along the ground (else a puff up and out)
	Count: number,
	Room: number?,
}

export type CashOpts = {
	Position: Vector3, -- the sell spot
	Ground: number,
	Home: Vector3?, -- the coins fly into the player there (nil = they just fall)
	Seed: number,
	Items: number,
	Phone: boolean?,
	Reduce: boolean?,
	Room: number?,
}

export type Pool = { Idle: { any }, Made: number, Cap: number, Make: () -> any }

WorldMotionLogic.Gravity = 70 -- bits fall a little floaty (Roblox's 196 reads too fast for tiny pieces)
WorldMotionLogic.Bounce = 0.35 -- vertical speed kept at a bounce
WorldMotionLogic.Friction = 0.6 -- horizontal speed kept at a bounce

WorldMotionLogic.Golem = {
	JumpTime = 0.95, -- the happy jump on equip: crouch, jump + one spin, a little rebound
	Crouch = 0.1, -- seconds of the crouch
	JumpEnd = 0.62, -- the jump lands here; the rebound fills the rest
	JumpHeight = 2.1,
	CrouchDepth = 0.16,
	Rebound = 0.32,
	FloatRise = 1.1, -- a Premium golem rises instead (it keeps its hover)
	Hang = 0.18, -- walking: extra hang time at the top of each hop (studs)
	Wiggle = 0.14, -- walking: the body turns left / right with each hop (radians)
	Nod = 0.09, -- walking: a forward nod on each landing
	Sway = 0.07, -- standing: the side sway (radians)
	IdleHop = 0.42, -- standing: a little double hop in place now and then
	IdleHopTime = 0.5,
	IdleHopEvery = { 5, 9 }, -- seconds between two idle hops (each golem its own)
	IdleWave = 0.3, -- the turn left and right during the idle hop ("waving")
}

WorldMotionLogic.Pop = {
	Lift = 2.2, -- the visual arc on top of the real flight (studs at its top)
	Start = 0.35, -- pop-in scale at the start
	PopIn = 0.24, -- seconds to grow (overshooting) to the full size
	SpinTime = 0.6, -- one extra turn, done by then (or by the landing)
	Squash = 0.34, -- how flat it gets on landing (0..1)
	SquashTime = 0.34,
	Blend = 0.06, -- an early landing blends the arc out this fast
	MaxTime = 1.8, -- a pop always ends by then
	LandSpeed = 5, -- falling faster than this, then slowing sharply = landed
	MinFlight = 0.2,
	MaxFlight = 1.2,
}

WorldMotionLogic.Hit = {
	FlashTime = 0.12,
	FlashSize = 2.1,
	SpikeTime = 0.16,
	SpikeLength = 1.5,
	SpikeReach = 1.9,
	SpikeWidth = 0.16,
	CubeLife = { 0.45, 0.7 },
	Gap = 0.18, -- seconds between two flashes on one rock
}

WorldMotionLogic.Cash = {
	Notes = { 3, 12 }, -- banknotes per sale (min, max)
	Coins = { 3, 9 },
	NoteSize = Vector3.new(1.2, 0.05, 0.6), -- cartoon big, so a phone still reads them as banknotes
	CoinSize = Vector3.new(0.14, 0.75, 0.75), -- a Cylinder: its axis is X
	NoteLife = { 1.25, 1.6 },
	CoinLife = { 0.95, 1.2 },
	HomeAt = 0.5, -- coins fly into the player for the last half of their life
	HomeRange = 45, -- studs: farther, coins just fall
	Note = Color3.fromRGB(98, 196, 74), -- CashBuilder.Note
	NoteLight = Color3.fromRGB(160, 232, 120), -- CashBuilder.NoteLight
	Coin = Color3.fromRGB(255, 206, 72), -- UITheme.Coin
}

WorldMotionLogic.Machine = {
	Shake = 0.035, -- studs of rumble at full heat
	Tilt = 0.012, -- radians of rock at full heat
	PopTime = 0.3, -- the hop when a job is done
	PopLift = 0.18,
	PopTilt = 0.05,
	GlowTime = 0.45, -- the glow flash with it
	Range = 40, -- studs from the camera
	MaxShaking = 4, -- nearest working machines that rumble at once
}

WorldMotionLogic.Caps = {
	PC = { Bits = 64, Pops = 6, Flashes = 3 },
	Phone = { Bits = 32, Pops = 3, Flashes = 2 },
}

---------------------------------------------------------------- helpers

local function frac(x: number): number
	return x - math.floor(x)
end

local function easeInOut(x: number): number
	return if x < 0.5 then 4 * x * x * x else 1 - ((-2 * x + 2) ^ 3) / 2
end

local function easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

-- A tiny deterministic random in [0, 1) from a seed and an index (no tables).
local function rand(seed: number, i: number): number
	return frac(math.sin(seed * 12.9898 + i * 78.233) * 43758.5453)
end

local function range(seed: number, i: number, a: number, b: number): number
	return a + (b - a) * rand(seed, i)
end

local function blank(kind: string, shape: string): Bit
	return {
		Kind = kind,
		Shape = shape,
		Born = 0,
		Life = 1,
		Origin = Vector3.zero,
		Velocity = Vector3.zero,
		Spin = Vector3.zero,
		Turn = Vector3.zero,
		Size = Vector3.one,
		Color = WHITE,
		Neon = false,
		Ground = 0,
		Seed = 0,
		Right = Vector3.xAxis,
		Up = Vector3.yAxis,
		Angle = 0,
		Home = nil,
		HomeAt = 1,
	}
end

---------------------------------------------------------------- caps and counts

-- The caps for this device: half on phones; Reduce motion halves the bits again, no pop look-alikes, no spikes, no spins.
function WorldMotionLogic.caps(phone: boolean, reduce: boolean): Caps
	local base = if phone then WorldMotionLogic.Caps.Phone else WorldMotionLogic.Caps.PC
	return {
		Bits = if reduce then math.floor(base.Bits / 2) else base.Bits,
		Pops = if reduce then 0 else base.Pops,
		Flashes = base.Flashes,
		Spikes = not reduce,
		Spin = not reduce,
	}
end

-- How many of `want` fit when `alive` of `cap` are in use.
function WorldMotionLogic.budget(want: number, alive: number, cap: number): number
	return math.max(0, math.min(want, cap - alive))
end

-- A hit: (spikes, cubes) besides its one flash.
function WorldMotionLogic.hitCounts(phone: boolean, reduce: boolean, small: boolean): (number, number)
	if reduce then
		return 0, 2
	end
	local spikes = if phone then 4 else 6
	local cubes = if phone then 3 else 5
	if small then
		spikes, cubes = math.max(3, spikes - 2), math.max(2, cubes - 2)
	end
	return spikes, cubes
end

-- Dust cubes of a chunk's pop (landing = the puff when it lands).
function WorldMotionLogic.dustCount(phone: boolean, reduce: boolean, landing: boolean): number
	if reduce then
		return 3
	end
	if phone then
		return if landing then 4 else 3
	end
	return if landing then 7 else 6
end

-- A sale of `items` items: (banknotes, coins); half on phones, a third with Reduce motion.
function WorldMotionLogic.cashCounts(items: number, phone: boolean, reduce: boolean): (number, number)
	local c = WorldMotionLogic.Cash
	local n = math.max(1, math.floor(if items == items then items else 1))
	local notes = math.clamp(3 + math.ceil(n * 0.75), c.Notes[1], c.Notes[2])
	local coins = math.clamp(3 + math.ceil(n * 0.5), c.Coins[1], c.Coins[2])
	local k = if reduce then 0.34 elseif phone then 0.5 else 1
	return math.max(1, math.ceil(notes * k)), math.max(1, math.ceil(coins * k))
end

---------------------------------------------------------------- golems

-- The happy jump on equip, `u` seconds in: (lift, pitch, yaw, roll).
local function celebration(u: number, floats: boolean, reduce: boolean): (number, number, number, number)
	local G = WorldMotionLogic.Golem
	local s = math.clamp(u / G.JumpTime, 0, 1)
	if reduce then
		-- Reduce motion: one small hop, no spin
		return 0.5 * 4 * s * (1 - s) * (if floats then 0.6 else 1), 0, 0, 0
	end
	if floats then
		-- a Premium golem keeps its hover: it rises, spins once and settles back
		return G.FloatRise * math.sin(math.pi * s), 0, TAU * easeInOut(s), 0.1 * math.sin(TAU * s)
	end
	if u < G.Crouch then
		local k = u / G.Crouch
		return -G.CrouchDepth * math.sin(math.pi * k), -0.12 * math.sin(math.pi * k), 0, 0
	elseif u < G.JumpEnd then
		local k = (u - G.Crouch) / (G.JumpEnd - G.Crouch)
		return G.JumpHeight * 4 * k * (1 - k), 0.14 * math.sin(math.pi * k), TAU * easeInOut(k), 0
	end
	local k = math.clamp((u - G.JumpEnd) / (G.JumpTime - G.JumpEnd), 0, 1)
	return G.Rebound * math.sin(math.pi * k), 0, 0, 0.1 * math.sin(3 * math.pi * k) * (1 - k)
end

--[[
	The extra pose of a follower golem on top of GolemController's own walk:
	(lift studs, pitch, yaw, roll radians). `phase` is its hop phase (one hop
	per pi), `celebrate` the seconds since its happy jump began (nil = none).
	Far golems (not `near`) and Reduce motion get nothing but the jump.
]]
function WorldMotionLogic.golemPose(
	now: number,
	phase: number,
	seed: number,
	walking: boolean,
	near: boolean,
	floats: boolean,
	celebrate: number?,
	reduce: boolean
): (number, number, number, number)
	local G = WorldMotionLogic.Golem
	local lift, pitch, yaw, roll = 0, 0, 0, 0
	if celebrate and celebrate >= 0 and celebrate < G.JumpTime then
		lift, pitch, yaw, roll = celebration(celebrate, floats, reduce)
	end
	if not near or reduce then
		return lift, pitch, yaw, roll
	end
	if floats then
		-- gliding on its aura: a soft sway, a slow look around
		roll += G.Sway * 0.6 * math.sin(now * 1.3 + seed)
		if not walking then
			yaw += 0.08 * math.sin(now * 0.7 + seed * 2)
		end
	elseif walking then
		local hop = math.abs(math.sin(phase))
		lift += G.Hang * (hop ^ 0.55 - hop) -- rounder hops: a little longer in the air
		yaw += G.Wiggle * math.sin(phase) -- turns left, right, left with the hops
		pitch -= G.Nod * (1 - hop) ^ 6 -- a nod on each landing
	else
		roll += G.Sway * math.sin(now * 1.7 + seed)
		-- now and then a little double hop in place, turning left and right
		local every = G.IdleHopEvery[1] + (G.IdleHopEvery[2] - G.IdleHopEvery[1]) * frac(seed * 0.618)
		local w = (now + seed * 2.3) % every
		if w < G.IdleHopTime then
			local s = w / G.IdleHopTime
			lift += G.IdleHop * math.abs(math.sin(TAU * s)) * (1 - 0.45 * s)
			yaw += G.IdleWave * math.sin(TAU * s)
		end
	end
	return lift, pitch, yaw, roll
end

---------------------------------------------------------------- ore pop

-- Seconds until something `height` studs above the ground, going up at `vy`, lands (gravity `g`).
function WorldMotionLogic.landTime(vy: number, height: number, g: number): number
	local h = math.max(0, height)
	local gravity = math.max(1, g)
	return (vy + math.sqrt(math.max(0, vy * vy + 2 * gravity * h))) / gravity
end

-- The pop-in scale `t` seconds after the chunk appears: Start -> overshoot ~1.16 -> 1.
function WorldMotionLogic.popScale(t: number): number
	local P = WorldMotionLogic.Pop
	if t >= P.PopIn then
		return 1
	end
	local x = math.max(0, t) / P.PopIn - 1
	local c1 = 3
	local back = 1 + (c1 + 1) * x * x * x + c1 * x * x
	return P.Start + (1 - P.Start) * back
end

-- The squash `u` seconds after landing: (wide, tall), about the same volume, back to (1, 1) by SquashTime.
function WorldMotionLogic.squash(u: number): (number, number)
	local P = WorldMotionLogic.Pop
	if u < 0 or u >= P.SquashTime then
		return 1, 1
	end
	local window = 1 - (u / P.SquashTime) ^ 3
	local tall = 1 - P.Squash * math.exp(-7 * u) * math.cos(18 * u) * window
	return 1 / math.sqrt(tall), tall
end

-- The visual arc `x` seconds into a flight of `T` seconds: 0 at both ends, Pop.Lift at the top.
local function arc(x: number, T: number): number
	local k = math.clamp(x / T, 0, 1)
	return WorldMotionLogic.Pop.Lift * 4 * k * (1 - k)
end

--[[
	A fresh chunk's look `t` seconds after it appeared: (lift, spin, wide,
	tall, done). `flight` = the predicted seconds to its landing, `landed` =
	the seconds at which it really landed (nil = still flying). The lift is
	0 at the start and at the landing, the spin is a whole turn, so the look
	always ends exactly on the real chunk.
]]
function WorldMotionLogic.popPose(t: number, flight: number, landed: number?): (number, number, number, number, boolean)
	local P = WorldMotionLogic.Pop
	local T = math.clamp(flight, P.MinFlight, P.MaxFlight)
	local lift: number
	if landed then
		lift = arc(landed, T) * math.max(0, 1 - (t - landed) / P.Blend)
	else
		lift = arc(t, T)
	end
	local spinEnd = math.min(P.SpinTime, T)
	if landed then
		spinEnd = math.min(spinEnd, math.max(landed, 0.05))
	end
	local k = math.clamp(t / spinEnd, 0, 1)
	local spin = if k >= 1 then 0 else TAU * easeOutCubic(k)
	local s = WorldMotionLogic.popScale(t)
	local wide, tall = s, s
	if landed then
		local w, h = WorldMotionLogic.squash(t - landed)
		wide, tall = wide * w, tall * h
	end
	local done = (landed ~= nil and t - landed >= P.SquashTime and t >= P.PopIn) or t >= P.MaxTime
	if done then
		return 0, 0, 1, 1, true
	end
	return lift, spin, wide, tall, false
end

-- The scale of the body's own axes for a squash: `tall` along the body axis nearest to world up, `wide` on the others.
function WorldMotionLogic.squashAxes(body: CFrame, wide: number, tall: number): Vector3
	local up = body:VectorToObjectSpace(Vector3.yAxis)
	local ax, ay, az = math.abs(up.X), math.abs(up.Y), math.abs(up.Z)
	if ay >= ax and ay >= az then
		return Vector3.new(wide, tall, wide)
	elseif ax >= az then
		return Vector3.new(tall, wide, wide)
	end
	return Vector3.new(wide, wide, tall)
end

-- The look-alike's frame: the real body's spot lifted (minus `drop`, the squash keeping its bottom down), turned `spin` around world up.
function WorldMotionLogic.popRoot(body: CFrame, lift: number, spin: number, drop: number): CFrame
	return CFrame.new(body.Position + Vector3.new(0, lift - drop, 0)) * CFrame.Angles(0, spin, 0) * body.Rotation
end

-- One part of the look-alike: its frame and size, `offset` / `size` = where it sits on the real body and how big it is.
function WorldMotionLogic.popPart(root: CFrame, scale: Vector3, offset: CFrame, size: Vector3): (CFrame, Vector3)
	local r = offset.Rotation
	local x, y, z = r.RightVector, r.UpVector, r.LookVector
	-- each of the part's axes stretches like that axis does under the body's scale
	-- (a turned part keeps its size at scale 1: only the squash changes it)
	local s = Vector3.new((x * scale).Magnitude, (y * scale).Magnitude, (z * scale).Magnitude)
	return root * CFrame.new(offset.Position * scale) * r, size * s
end

-- Did the chunk just land? (its vertical speed last frame and now; seconds since it appeared, its predicted flight)
function WorldMotionLogic.landed(lastVy: number, vy: number, t: number, flight: number): boolean
	local P = WorldMotionLogic.Pop
	if lastVy < -P.LandSpeed and vy > lastVy * 0.4 then
		return true
	end
	-- no fall seen (a client that doesn't run its physics): it has landed by now
	return t > flight + 0.25 and math.abs(vy) < 1
end

---------------------------------------------------------------- bit plans

-- The white impact flash, its spikes and the ore cubes of one blaster hit.
function WorldMotionLogic.hitPlan(o: HitOpts): { Bit }
	local H = WorldMotionLogic.Hit
	local out: { Bit } = {}
	local room = if o.Room then o.Room else math.huge
	if room < 1 then
		return out
	end
	local spikes, cubes = WorldMotionLogic.hitCounts(o.Phone == true, o.Reduce == true, o.Small == true)
	local k = if o.Small then 0.75 else 1
	local seed = o.Seed
	local back = if o.Back and o.Back.Magnitude > 0.01 then o.Back.Unit else Vector3.zero
	-- just in front of the surface, so the rock doesn't hide half of it
	local center = o.Position + back * 0.3
	-- the flash: a white ball that pops and fades
	local flash = blank("Flash", "Ball")
	flash.Life = H.FlashTime
	flash.Origin = center
	flash.Size = Vector3.one * H.FlashSize * k
	flash.Neon = true
	flash.Seed = seed
	table.insert(out, flash)
	room -= 1
	-- the star: white spikes shooting out in the plane facing the camera
	local n = math.min(spikes, room)
	local offset = rand(seed, 1) * TAU
	for i = 1, n do
		local spike = blank("Spike", "Block")
		spike.Life = H.SpikeTime * range(seed, 10 + i, 0.85, 1.15)
		spike.Origin = center
		spike.Size = Vector3.new(H.SpikeLength * k, H.SpikeWidth * k, H.SpikeWidth * k)
		spike.Neon = true
		spike.Right = o.Right
		spike.Up = o.Up
		spike.Angle = offset + (i - 1) / n * TAU + range(seed, 20 + i, -0.18, 0.18)
		spike.Seed = seed + i
		table.insert(out, spike)
	end
	room -= n
	-- small cubes in the ore's colour, spraying back toward the shooter
	local flatBack = Vector3.new(back.X, 0, back.Z)
	local side = if flatBack.Magnitude > 0.01 then Vector3.new(-flatBack.Z, 0, flatBack.X).Unit else Vector3.xAxis
	local m = math.min(cubes, room)
	for i = 1, m do
		local cube = blank("Cube", "Block")
		local s = range(seed, 30 + i, 0.26, 0.42) * k
		cube.Life = range(seed, 40 + i, WorldMotionLogic.Hit.CubeLife[1], WorldMotionLogic.Hit.CubeLife[2])
		cube.Origin = center + back * 0.1
		cube.Velocity = back * range(seed, 50 + i, 5, 10)
			+ side * range(seed, 60 + i, -7, 7)
			+ Vector3.new(0, range(seed, 70 + i, 9, 15), 0)
		cube.Spin = Vector3.new(range(seed, 80 + i, -14, 14), range(seed, 90 + i, -10, 10), range(seed, 100 + i, -14, 14))
		cube.Turn = Vector3.new(rand(seed, 110 + i) * TAU, rand(seed, 120 + i) * TAU, 0)
		cube.Size = Vector3.new(s, s, s)
		-- every third one glows (darker, so the bloom keeps its hue), every other one lighter
		cube.Neon = i % 3 == 0
		cube.Color = if cube.Neon then o.Color:Lerp(BLACK, 0.15) elseif i % 2 == 0 then o.Color:Lerp(WHITE, 0.3) else o.Color
		cube.Ground = o.Ground
		cube.Seed = seed + i
		table.insert(out, cube)
	end
	return out
end

-- Dust cubes: a puff up and out where a chunk pops, or a flat ring where it lands.
function WorldMotionLogic.dustPlan(o: DustOpts): { Bit }
	local out: { Bit } = {}
	local n = math.min(o.Count, if o.Room then o.Room else math.huge)
	local seed = o.Seed
	for i = 1, n do
		local dust = blank("Dust", "Block")
		local a = (i - 1) / math.max(1, n) * TAU + range(seed, i, -0.3, 0.3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local s = range(seed, 10 + i, 0.3, 0.55)
		dust.Life = range(seed, 20 + i, 0.4, 0.58)
		if o.Landing then
			dust.Origin = Vector3.new(o.Position.X, o.Ground + 0.2, o.Position.Z) + dir * 0.4
			dust.Velocity = dir * range(seed, 30 + i, 7, 10) + Vector3.new(0, range(seed, 40 + i, 0.5, 2), 0)
		else
			dust.Origin = o.Position + dir * 0.3
			dust.Velocity = dir * range(seed, 30 + i, 4, 8) + Vector3.new(0, range(seed, 40 + i, 3, 7), 0)
		end
		dust.Spin = Vector3.new(range(seed, 50 + i, -4, 4), range(seed, 60 + i, -4, 4), range(seed, 70 + i, -4, 4))
		dust.Turn = Vector3.new(rand(seed, 80 + i) * TAU, rand(seed, 90 + i) * TAU, 0)
		dust.Size = Vector3.new(s, s, s)
		dust.Color = o.Color:Lerp(WHITE, if i % 2 == 0 then 0.65 else 0.45)
		dust.Ground = o.Ground
		dust.Seed = seed + i
		table.insert(out, dust)
	end
	return out
end

-- The cash burst of a sale: banknotes fluttering out and coins bursting up (into Home when given).
function WorldMotionLogic.cashPlan(o: CashOpts): { Bit }
	local c = WorldMotionLogic.Cash
	local out: { Bit } = {}
	local notes, coins = WorldMotionLogic.cashCounts(o.Items, o.Phone == true, o.Reduce == true)
	local room = if o.Room then o.Room else math.huge
	if notes + coins > room then
		-- fewer of both, at least one of each while two fit
		local k = room / (notes + coins)
		notes = math.floor(notes * k + 0.5)
		coins = math.max(0, math.floor(room) - notes)
		if room >= 2 and coins == 0 then
			coins, notes = 1, notes - 1
		end
		if room >= 2 and notes == 0 then
			notes, coins = 1, coins - 1
		end
	end
	local seed = o.Seed
	local spin = o.Reduce ~= true
	for i = 1, notes do
		local note = blank("Note", "Block")
		local a = rand(seed, i) * TAU
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		note.Life = range(seed, 10 + i, c.NoteLife[1], c.NoteLife[2])
		note.Origin = o.Position + Vector3.new(0, 0.8, 0) + dir * 0.3
		note.Velocity = dir * range(seed, 20 + i, 4, 8) + Vector3.new(0, range(seed, 30 + i, 13, 19), 0)
		note.Spin = if spin then Vector3.new(0, range(seed, 40 + i, -6, 6), 0) else Vector3.zero
		note.Turn = Vector3.new(rand(seed, 50 + i) * 0.8, rand(seed, 60 + i) * TAU, rand(seed, 70 + i) * 0.8)
		note.Size = c.NoteSize
		note.Color = if i % 3 == 0 then c.NoteLight else c.Note
		note.Ground = o.Ground
		note.Seed = seed + i * 7
		table.insert(out, note)
	end
	for i = 1, coins do
		local coin = blank("Coin", "Cylinder")
		local a = rand(seed, 100 + i) * TAU
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		coin.Life = range(seed, 110 + i, c.CoinLife[1], c.CoinLife[2])
		coin.Origin = o.Position + Vector3.new(0, 0.6, 0) + dir * 0.25
		coin.Velocity = dir * range(seed, 120 + i, 5, 9) + Vector3.new(0, range(seed, 130 + i, 15, 21), 0)
		coin.Spin = if spin then Vector3.new(0, range(seed, 140 + i, 12, 20), 0) else Vector3.zero
		coin.Turn = Vector3.new(0, rand(seed, 150 + i) * TAU, 0)
		coin.Size = c.CoinSize
		coin.Color = c.Coin
		coin.Ground = o.Ground
		coin.Home = o.Home
		coin.HomeAt = c.HomeAt
		coin.Seed = seed + i * 11
		table.insert(out, coin)
	end
	return out
end

---------------------------------------------------------------- motion

-- A ballistic flight from `origin` that bounces twice on `floorY`: (position, angle offset).
local function ballistic(origin: Vector3, velocity: Vector3, spin: Vector3, floorY: number, t: number): (Vector3, Vector3)
	local g = WorldMotionLogic.Gravity
	local remaining = math.max(0, t)
	local p = origin
	local v = velocity
	local s = spin
	local angle = Vector3.zero
	for bounce = 0, 2 do
		local height = math.max(0, p.Y - floorY)
		local hit = (v.Y + math.sqrt(math.max(0, v.Y * v.Y + 2 * g * height))) / g
		if remaining <= hit then
			p = p + Vector3.new(v.X * remaining, v.Y * remaining - 0.5 * g * remaining * remaining, v.Z * remaining)
			angle += s * remaining
			remaining = 0
			break
		end
		p = Vector3.new(p.X + v.X * hit, floorY, p.Z + v.Z * hit)
		angle += s * hit
		remaining -= hit
		local up = -(v.Y - g * hit) * WorldMotionLogic.Bounce
		v = Vector3.new(v.X * WorldMotionLogic.Friction, up, v.Z * WorldMotionLogic.Friction)
		s *= 0.5
		if bounce == 2 or up < 2 then
			local slide = math.min(remaining, 0.12)
			p += Vector3.new(v.X * slide, 0, v.Z * slide)
			angle += s * slide
			break
		end
	end
	if p.Y < floorY then
		p = Vector3.new(p.X, floorY, p.Z)
	end
	return p, angle
end

--[[
	Where a bit is `t` seconds after it was born: (CFrame, size, transparency,
	done). Flash: pops and fades. Spike: shoots out from the centre and thins.
	Cube: flies, bounces, shrinks. Dust: puffs out with drag, grows, fades.
	Note: rises, then flutters down swaying and lies flat. Coin: bursts up
	spinning, then flies into Home.
]]
function WorldMotionLogic.sample(bit: Bit, t: number): (CFrame, Vector3, number, boolean)
	local life = bit.Life
	local k = math.clamp(t / life, 0, 1)
	local done = t >= life
	local kind = bit.Kind
	if kind == "Flash" then
		local rise = 0.22
		local size = if k < rise then 0.45 + 0.55 * (k / rise) else 1 - 0.55 * ((k - rise) / (1 - rise))
		local transparency = if k < rise then 0 else ((k - rise) / (1 - rise)) ^ 1.2
		return CFrame.new(bit.Origin), bit.Size * size, math.clamp(transparency, 0, 1), done
	elseif kind == "Spike" then
		local H = WorldMotionLogic.Hit
		local dir = bit.Right * math.cos(bit.Angle) + bit.Up * math.sin(bit.Angle)
		local reach = 0.3 + H.SpikeReach * easeOutCubic(k)
		local length = math.max(0.05, bit.Size.X * (1 - k) ^ 0.6 * math.min(1, 0.3 + k / 0.2))
		local width = math.max(0.03, bit.Size.Y * (1 - 0.6 * k))
		local position = bit.Origin + dir * (reach + length / 2)
		local normal = bit.Right:Cross(bit.Up)
		local cf = CFrame.fromMatrix(position, dir, normal:Cross(dir))
		return cf, Vector3.new(length, width, width), math.clamp(0.05 + 0.95 * k ^ 1.6, 0, 1), done
	elseif kind == "Dust" then
		local tau = 0.16
		local e = 1 - math.exp(-math.max(0, t) / tau)
		local v = bit.Velocity
		local position = bit.Origin + Vector3.new(v.X * tau * e, v.Y * tau * e + 1.2 * t, v.Z * tau * e)
		if position.Y < bit.Ground + 0.1 then
			position = Vector3.new(position.X, bit.Ground + 0.1, position.Z)
		end
		local turn = bit.Turn + bit.Spin * t
		-- a puff: grows quickly, then shrinks away while it clears
		local scale = if k < 0.3 then 0.6 + 0.9 * (k / 0.3) else 1.5 - 1.35 * ((k - 0.3) / 0.7)
		local cf = CFrame.new(position) * CFrame.Angles(turn.X, turn.Y, turn.Z)
		return cf, bit.Size * math.max(0.05, scale), math.clamp(0.25 + 0.65 * k ^ 1.5, 0, 1), done
	elseif kind == "Note" then
		local tau = 0.32
		local fall = -5.5 -- the paper's fall speed
		local e = 1 - math.exp(-math.max(0, t) / tau)
		local v = bit.Velocity
		local y = bit.Origin.Y + fall * t + (v.Y - fall) * tau * e
		local he = 1 - math.exp(-math.max(0, t) / 0.45)
		local flat = Vector3.new(v.X, 0, v.Z)
		local side = if flat.Magnitude > 0.01 then Vector3.new(-v.Z, 0, v.X).Unit else Vector3.xAxis
		local sway = math.sin(t * 6.5 + bit.Seed) * 0.55 * math.min(1, t / 0.35)
		local position = Vector3.new(bit.Origin.X + v.X * 0.45 * he, y, bit.Origin.Z + v.Z * 0.45 * he) + side * sway
		local floor = bit.Ground + bit.Size.Y / 2 + 0.02
		local yaw = bit.Turn.Y + bit.Spin.Y * t
		local cf: CFrame
		if position.Y <= floor then
			-- landed: it lies flat on the ground
			cf = CFrame.new(position.X, floor, position.Z) * CFrame.Angles(0, yaw, 0)
		else
			local pitch = bit.Turn.X + math.sin(t * 7.3 + bit.Seed) * 0.9
			local roll = bit.Turn.Z + math.cos(t * 5.1 + bit.Seed * 1.3) * 0.6
			cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
		end
		local scale = if k < 0.8 then 1 else 1 - (k - 0.8) / 0.2
		if t < 0.08 then
			scale *= 0.4 + 0.6 * math.max(0, t) / 0.08
		end
		return cf, bit.Size * math.max(0.05, scale), 0, done
	elseif kind == "Coin" then
		local half = bit.Size.Y / 2
		local home = bit.Home
		local homeStart = bit.HomeAt * life
		local position: Vector3
		local angle: Vector3
		local scale = 1
		if home and t > homeStart then
			local p0, a0 = ballistic(bit.Origin, bit.Velocity, bit.Spin, bit.Ground + half, homeStart)
			local u = math.clamp((t - homeStart) / (life - homeStart), 0, 1)
			local ease = u * u
			position = p0:Lerp(home, ease) + Vector3.new(0, 1.5 * math.sin(math.pi * u), 0)
			angle = a0 + bit.Spin * 2 * (t - homeStart)
			scale = 1 - 0.65 * u
		else
			position, angle = ballistic(bit.Origin, bit.Velocity, bit.Spin, bit.Ground + half, t)
			if not home and k > 0.75 then
				scale = 1 - (k - 0.75) / 0.25
			end
		end
		if t < 0.06 then
			scale *= 0.4 + 0.6 * math.max(0, t) / 0.06
		end
		local turn = bit.Turn + angle
		-- the coin stands on its edge (Cylinder axis X, flat) and spins around up
		local cf = CFrame.new(position) * CFrame.Angles(0, turn.Y, 0) * CFrame.Angles(0, 0, 0.35)
		return cf, bit.Size * math.max(0.05, scale), 0, done
	end
	-- Cube: flies, bounces twice, shrinks after 55 % of its life, fades after 78 %
	local half = math.min(bit.Size.X, bit.Size.Y, bit.Size.Z) / 2
	local position, angle = ballistic(bit.Origin, bit.Velocity, bit.Spin, bit.Ground + half, t)
	local turn = bit.Turn + angle
	local cf = CFrame.new(position) * CFrame.Angles(turn.X, turn.Y, turn.Z)
	local scale = if k < 0.55 then 1 else 1 - 0.85 * ((k - 0.55) / 0.45) ^ 1.4
	if t < 0.05 then
		scale *= 0.5 + 0.5 * math.max(0, t) / 0.05
	end
	local transparency = if k < 0.78 then 0 else (k - 0.78) / 0.22
	return cf, bit.Size * math.max(0.05, scale), math.clamp(transparency, 0, 1), done
end

---------------------------------------------------------------- machines

-- The rumble of a working machine `t` seconds into its work (heat 0..1 eases it in and out): an offset around its base.
function WorldMotionLogic.machineShake(t: number, heat: number, seed: number): CFrame
	local M = WorldMotionLogic.Machine
	local h = math.clamp(heat, 0, 1)
	if h <= 0 then
		return CFrame.identity
	end
	local a = M.Shake * h
	local x = (math.sin(t * 71 + seed) + 0.5 * math.sin(t * 113 + seed * 2.1)) / 1.5 * a
	local z = (math.cos(t * 67 + seed * 1.3) + 0.5 * math.sin(t * 97 + seed)) / 1.5 * a
	local roll = math.sin(t * 53 + seed * 0.7) * M.Tilt * h
	return CFrame.new(x, 0, z) * CFrame.Angles(roll * 0.6, 0, roll)
end

-- The hop of a machine `u` seconds after a job was done: up, a little tilt back, down with a tiny bounce.
function WorldMotionLogic.machinePop(u: number): CFrame
	local M = WorldMotionLogic.Machine
	if u < 0 or u >= M.PopTime then
		return CFrame.identity
	end
	local k = u / M.PopTime
	local lift = M.PopLift * math.sin(math.pi * math.min(1, k / 0.7)) * (if k < 0.7 then 1 else 0)
	local bounce = if k >= 0.7 then M.PopLift * 0.25 * math.sin(math.pi * (k - 0.7) / 0.3) else 0
	return CFrame.new(0, lift + bounce, 0) * CFrame.Angles(-M.PopTilt * math.sin(math.pi * k), 0, 0)
end

-- How far (0..1) a machine's glow flashes toward its hot colour `u` seconds after a job was done.
function WorldMotionLogic.machineGlow(u: number): number
	local M = WorldMotionLogic.Machine
	if u < 0 or u >= M.GlowTime then
		return 0
	end
	local k = u / M.GlowTime
	return if k < 0.15 then k / 0.15 else (1 - (k - 0.15) / 0.85) ^ 2
end

---------------------------------------------------------------- pool

-- A pool that makes at most `cap` items with `make` and hands idle ones out again.
function WorldMotionLogic.newPool(make: () -> any, cap: number): Pool
	return { Idle = {}, Made = 0, Cap = cap, Make = make }
end

-- An idle item, or a new one while fewer than Cap were made; nil when all are in use.
function WorldMotionLogic.take(pool: Pool): any?
	local item = table.remove(pool.Idle)
	if item ~= nil then
		return item
	end
	if pool.Made >= pool.Cap then
		return nil
	end
	pool.Made += 1
	return pool.Make()
end

function WorldMotionLogic.give(pool: Pool, item: any)
	table.insert(pool.Idle, item)
end

return WorldMotionLogic
