--[[
	WeatherLogic: the pure math of the weather (Config/WeatherConfig), shared
	by the client (Controllers/WeatherController, Effects/WeatherFx), the
	tests (tests/Weather.spec.luau) and the preview tools. No services, no
	Instances, no randomness: everything comes from a hash of the config's
	Seed, so every player computes the same weather from the server time.

	- The schedule: time is cut into slots (Schedule.Slot seconds); event(slot)
	  says whether the slot has weather, which kind (a weighted pick of the
	  kinds that are on), when it starts, how long it lasts, whether a
	  rainbow follows and where the wind blows. at(time) is the weather at a
	  moment: the kind, its strength with the fades (ramp), the rainbow's
	  strength. A forced kind (the WeatherForce attribute) shows at once at
	  full strength.
	- Lightning: one strike at most per Lightning.Window of a storm, at a
	  hashed moment, with a hashed thunder delay (nextStrike); flash(dt) is
	  the flash's brightness dt seconds after the strike.
	- Looks: tint (the WeatherTint colour correction blended from neutral),
	  rate (an emitter's rate after the phone / Reduce motion caps), the
	  rain's slant, the rainbow's bands and arc, a tree's sway.
	- Clear view (owner 2026-10-27): the hole in the sky field round the
	  camera (hole, strips) so nothing falls near the lens, the ground pads'
	  distance from the camera (padClear), at most one flash per
	  Lightning.MinFlashGap (flashAllowed).
	- isSurface(position): weather shows only on the surface (zones, sea).
]]

local WeatherConfig = require(script.Parent.Parent.Config.WeatherConfig)
local WorldLayout = require(script.Parent.Parent.Config.WorldLayout)

export type Kind = WeatherConfig.Kind
export type Config = WeatherConfig.Config
export type Tint = WeatherConfig.Tint

export type Event = {
	Kind: Kind,
	Slot: number, -- -1 for a forced event
	Start: number, -- server time it begins
	Length: number, -- seconds, fades included
	Rainbow: boolean, -- a rainbow follows it
	WindYaw: number, -- radians: where the wind blows to (0 = +X, pi/2 = +Z)
}

export type State = {
	Kind: Kind, -- the weather now ("Clear" between events, also while only a rainbow shows)
	Intensity: number, -- 0..1 with the fades
	Rainbow: number, -- 0..1
	Elapsed: number, -- seconds since the event began
	WindYaw: number,
	Event: Event?,
	Forced: boolean,
}

export type Strike = {
	At: number, -- seconds since the event began
	Delay: number, -- seconds from the flash to its thunder
	Window: number,
}

-- A strip of the sky field in the field's own frame (x downwind, z across, centred on the
-- camera's fall line): its centre, size, the inner ring or not, its share of the rates.
export type Strip = {
	X: number,
	Z: number,
	SizeX: number,
	SizeZ: number,
	Near: boolean,
	Share: number,
}

export type Band = {
	Radius: number, -- studs: the arc's radius at Rainbow.Distance
	Width: number, -- studs
	Color: Color3,
}

local WeatherLogic = {}

local TAU = math.pi * 2
local TWO32 = 4294967296
local WHITE = Color3.new(1, 1, 1)
-- a cubic Bezier's control distance for a quarter circle (radius 1)
WeatherLogic.Curve = 4 / 3 * (math.sqrt(2) - 1)

---------------------------------------------------------------- hash

-- (a * b) mod 2^32 without losing bits in a double
local function mul32(a: number, b: number): number
	local lo = a % 65536
	local hi = (a - lo) / 65536
	return (lo * b + ((hi * b) % 65536) * 65536) % TWO32
end

-- murmur3's finalizer: every input bit moves every output bit
local function fmix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

local function int32(x: number): number
	return math.floor(x) % TWO32
end

-- A number in [0, 1) from three whole numbers (the same everywhere, every time).
function WeatherLogic.hash(a: number, b: number, c: number): number
	local h = fmix(int32(a))
	h = fmix(bit32.bxor(h, int32(b)))
	h = fmix(bit32.bxor(h, mul32(int32(c) + 1, 0x9E3779B1)))
	return h / TWO32
end

---------------------------------------------------------------- the schedule

-- The kind for a roll in [0, 1): a weighted pick of the kinds that are on, in Order.
function WeatherLogic.pick(roll: number, cfg: Config?): Kind
	local c = cfg or WeatherConfig
	local total = 0
	for _, kind in c.Order do
		local look = c.Kinds[kind]
		if look and look.On and look.Weight > 0 then
			total += look.Weight
		end
	end
	if total <= 0 then
		return "Clear"
	end
	local at = math.clamp(roll, 0, 1) * total
	local last: Kind = "Clear"
	for _, kind in c.Order do
		local look = c.Kinds[kind]
		if look and look.On and look.Weight > 0 then
			last = kind
			at -= look.Weight
			if at < 0 then
				return kind
			end
		end
	end
	return last
end

-- 0..1: up over fadeIn, held, down over fadeOut, 0 outside [0, length] (smoothstep ends).
function WeatherLogic.ramp(t: number, length: number, fadeIn: number, fadeOut: number): number
	if t <= 0 or t >= length then
		return 0
	end
	local a = if fadeIn > 0 then math.min(1, t / fadeIn) else 1
	local b = if fadeOut > 0 then math.min(1, (length - t) / fadeOut) else 1
	local x = math.min(a, b)
	return x * x * (3 - 2 * x)
end

-- The weather event of a slot, or nil (a clear slot).
function WeatherLogic.event(slot: number, cfg: Config?): Event?
	local c = cfg or WeatherConfig
	local s = c.Schedule
	local seed = s.Seed
	if WeatherLogic.hash(seed, slot, 1) >= s.EventChance then
		return nil
	end
	local kind = WeatherLogic.pick(WeatherLogic.hash(seed, slot, 2), c)
	local look = c.Kinds[kind]
	if kind == "Clear" or not look then
		return nil
	end
	local d = look.Duration
	local minimum = s.FadeIn + s.FadeOut + 1
	local length = math.max(minimum, d[1] + (d[2] - d[1]) * WeatherLogic.hash(seed, slot, 3))
	local rainbow = c.Rainbow.On and (look.Rainbow or 0) > WeatherLogic.hash(seed, slot, 4)
	local tail = if rainbow then math.max(0, c.Rainbow.Seconds - c.Rainbow.Lead) else 0
	local room = s.Slot - 2 * s.Margin - length - tail
	if room < 0 then
		length = math.max(minimum, length + room)
		room = 0
	end
	return {
		Kind = kind,
		Slot = slot,
		Start = slot * s.Slot + s.Margin + room * WeatherLogic.hash(seed, slot, 5),
		Length = length,
		Rainbow = rainbow,
		WindYaw = WeatherLogic.hash(seed, slot, 6) * TAU,
	}
end

-- A WeatherForce attribute's value -> a kind, "Rainbow", or nil (no force / unknown).
function WeatherLogic.parseForce(value: any, cfg: Config?): string?
	if type(value) ~= "string" then
		return nil
	end
	local c = cfg or WeatherConfig
	local wanted = string.lower((string.gsub(value, "%s", "")))
	if wanted == "" then
		return nil
	end
	for _, kind in c.Order do
		if string.lower(kind) == wanted then
			return kind
		end
	end
	if wanted == "rainbow" then
		return "Rainbow"
	elseif wanted == "clear" then
		return "Clear"
	end
	return nil
end

local function clearState(time: number, c: Config): State
	local slot = math.floor(time / c.Schedule.Slot)
	return {
		Kind = "Clear",
		Intensity = 0,
		Rainbow = 0,
		Elapsed = 0,
		WindYaw = WeatherLogic.hash(c.Schedule.Seed, slot, 6) * TAU,
		Event = nil,
		Forced = false,
	}
end

-- The weather at server time `time`. `force` = the WeatherForce attribute's value (or nil).
function WeatherLogic.at(time: number, force: any?, cfg: Config?): State
	local c = cfg or WeatherConfig
	local forced = WeatherLogic.parseForce(force, c)
	if forced then
		local state = clearState(time, c)
		state.Forced = true
		if forced == "Rainbow" then
			state.Rainbow = 1
		elseif forced ~= "Clear" then
			-- a forced event restarts every hour (so its lightning windows stay small numbers)
			local start = math.floor(time / 3600) * 3600
			local kind = forced
			state.Kind = kind
			state.Intensity = 1
			state.Elapsed = time - start
			state.Event = {
				Kind = kind,
				Slot = -1,
				Start = start,
				Length = 3600,
				Rainbow = false,
				WindYaw = state.WindYaw,
			}
		end
		return state
	end
	if not c.Enabled then
		return clearState(time, c)
	end
	local slot = math.floor(time / c.Schedule.Slot)
	local event = WeatherLogic.event(slot, c)
	if not event then
		return clearState(time, c)
	end
	local s = c.Schedule
	local t = time - event.Start
	local inside = t > 0 and t < event.Length
	local rainbow = 0
	if event.Rainbow then
		local r = c.Rainbow
		rainbow = WeatherLogic.ramp(t - (event.Length - r.Lead), r.Seconds, r.FadeIn, r.FadeOut)
	end
	return {
		Kind = if inside then event.Kind else "Clear",
		Intensity = if inside then WeatherLogic.ramp(t, event.Length, s.FadeIn, s.FadeOut) else 0,
		Rainbow = rainbow,
		Elapsed = t,
		WindYaw = event.WindYaw,
		Event = event,
		Forced = false,
	}
end

---------------------------------------------------------------- lightning

-- The strike of a storm's lightning window (nil = no strike in it).
function WeatherLogic.strike(event: Event, window: number, cfg: Config?): Strike?
	local c = cfg or WeatherConfig
	local l = c.Lightning
	if window < 0 then
		return nil
	end
	local key = c.Schedule.Seed * 31 + event.Slot
	if WeatherLogic.hash(key, window, 7) >= l.Chance then
		return nil
	end
	local d = l.Delay
	return {
		At = l.First + window * l.Window + WeatherLogic.hash(key, window, 8) * (l.Window - l.MinGap),
		Delay = d[1] + (d[2] - d[1]) * WeatherLogic.hash(key, window, 9),
		Window = window,
	}
end

-- The first strike after `elapsed` seconds of the event (nil: no lightning in this kind).
function WeatherLogic.nextStrike(event: Event, elapsed: number, cfg: Config?): Strike?
	local c = cfg or WeatherConfig
	local look = c.Kinds[event.Kind]
	if not (look and look.Lightning) then
		return nil
	end
	local l = c.Lightning
	local first = math.max(0, math.floor((elapsed - l.First) / l.Window))
	for window = first, first + 8 do
		local s = WeatherLogic.strike(event, window, c)
		if s and s.At > elapsed then
			return s
		end
	end
	return nil
end

-- The flash's extra brightness `dt` seconds after a strike: a flash, a flicker, gone.
function WeatherLogic.flash(dt: number, cfg: Config?): number
	local c = cfg or WeatherConfig
	local l = c.Lightning
	if dt < 0 or dt >= l.Length then
		return 0
	end
	local v = l.Peak * math.exp(-dt / 0.06)
	if dt >= l.Flicker then
		v += l.Second * math.exp(-(dt - l.Flicker) / 0.1)
	end
	return v * math.min(1, (1 - dt / l.Length) * 4)
end

-- May a strike flash now? Not within Lightning.MinFlashGap of the last flash (`last`, nil = none):
-- with its flicker that is at most two flashes a second (photosensitivity).
function WeatherLogic.flashAllowed(last: number?, now: number, cfg: Config?): boolean
	local c = cfg or WeatherConfig
	return last == nil or now - last >= c.Lightning.MinFlashGap
end

-- A thunder's volume share: a close strike (short delay) is louder.
function WeatherLogic.thunderLevel(delay: number, cfg: Config?): number
	local c = cfg or WeatherConfig
	local d = c.Lightning.Delay
	local t = if d[2] > d[1] then math.clamp((delay - d[1]) / (d[2] - d[1]), 0, 1) else 0
	return 1 - 0.45 * t
end

---------------------------------------------------------------- looks

local function blend(a: Tint, b: Tint, t: number): Tint
	return {
		Color = a.Color:Lerp(b.Color, t),
		Brightness = a.Brightness + (b.Brightness - a.Brightness) * t,
		Contrast = a.Contrast + (b.Contrast - a.Contrast) * t,
		Saturation = a.Saturation + (b.Saturation - a.Saturation) * t,
	}
end

WeatherLogic.Neutral = { Color = WHITE, Brightness = 0, Contrast = 0, Saturation = 0 } :: Tint

-- The WeatherTint for a kind at a strength, with the rainbow's "sun is back" on top.
function WeatherLogic.tint(kind: Kind, intensity: number, rainbow: number, cfg: Config?): Tint
	local c = cfg or WeatherConfig
	local result = WeatherLogic.Neutral
	local look = c.Kinds[kind]
	if look and intensity > 0 then
		result = blend(result, look.Tint, math.clamp(intensity, 0, 1))
	end
	if rainbow > 0 then
		result = blend(result, c.Rainbow.Tint, math.clamp(rainbow, 0, 1))
	end
	return result
end

-- True when a tint is (about) neutral: the effect can be switched off.
function WeatherLogic.isNeutral(t: Tint): boolean
	return math.abs(t.Brightness) < 0.002
		and math.abs(t.Contrast) < 0.002
		and math.abs(t.Saturation) < 0.002
		and math.abs(t.Color.R - 1) + math.abs(t.Color.G - 1) + math.abs(t.Color.B - 1) < 0.006
end

-- An emitter's rate: its full-strength rate x strength, after the phone and Reduce motion caps.
function WeatherLogic.rate(base: number?, intensity: number, phone: boolean, reduced: boolean, cfg: Config?): number
	local c = cfg or WeatherConfig
	if not base or base <= 0 or intensity <= 0 then
		return 0
	end
	local r = base * math.min(intensity, 1)
	if phone then
		r *= c.Phone.Rate
	end
	if reduced then
		r *= c.Reduced.Rate
	end
	return r
end

-- The flat direction the wind blows to.
function WeatherLogic.windDirection(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, math.sin(yaw))
end

-- Radians the falling particles lean from straight down (the wind over their fall speed).
function WeatherLogic.slant(wind: number, fallSpeed: number): number
	if fallSpeed <= 0 then
		return 0
	end
	return math.atan(math.max(0, wind) / fallSpeed)
end

-- The lean of what falls in a kind (rain, else hail, else snow): its wind over the fall speed.
function WeatherLogic.lookSlant(look: WeatherConfig.Look?, cfg: Config?): number
	local c = cfg or WeatherConfig
	if not look then
		return 0
	end
	local p = c.Particles
	local fall = if look.Rain then p.Rain.Speed elseif look.Hail then p.Hail.Speed else p.Snow.Speed
	return WeatherLogic.slant(look.Wind, (fall[1] + fall[2]) / 2)
end

-- Half the width of the sky field's hole for a kind: its Clear studs plus how far its widest
-- spread can drift a particle sideways before it reaches the camera's height.
function WeatherLogic.hole(look: WeatherConfig.Look?, cfg: Config?): number
	local c = cfg or WeatherConfig
	local clear = if look and look.Clear then look.Clear else c.Box.Clear
	if not look then
		return clear
	end
	local p = c.Particles
	local spread = 0
	if (look.Rain or 0) > 0 then
		spread = math.max(spread, p.Rain.Spread or 0)
	end
	if (look.Hail or 0) > 0 then
		spread = math.max(spread, p.Hail.Spread or 0)
	end
	if (look.Snow or 0) > 0 then
		spread = math.max(spread, p.Snow.Spread or 0)
	end
	local path = c.Box.Height / math.cos(WeatherLogic.lookSlant(look, c))
	return clear + path * math.tan(math.rad(spread))
end

-- The sky field's 8 strips round a hole of half-width `hole`: the inner ring (Box.NearWidth wide,
-- smaller fainter particles) then the outer ring out to Box.Field / 2; each ring is a strip on
-- either side across the whole ring and one on either side between them. A strip of no area
-- has Share 0. The shares add up to 1 (the whole field minus the hole).
function WeatherLogic.strips(hole: number, cfg: Config?): { Strip }
	local c = cfg or WeatherConfig
	local half = c.Box.Field / 2
	local h1 = math.clamp(hole, 0, half)
	local h2 = math.clamp(hole + c.Box.NearWidth, h1, half)
	local total = (2 * half) ^ 2 - (2 * h1) ^ 2
	local out: { Strip } = {}
	local function add(x: number, z: number, sx: number, sz: number, near: boolean)
		local area = sx * sz
		table.insert(out, {
			X = x,
			Z = z,
			SizeX = sx,
			SizeZ = sz,
			Near = near,
			Share = if total > 0 then area / total else 0,
		})
	end
	local function ring(inner: number, outer: number, near: boolean)
		local w = outer - inner
		local mid = (inner + outer) / 2
		add(0, mid, 2 * outer, w, near)
		add(0, -mid, 2 * outer, w, near)
		add(mid, 0, w, 2 * inner, near)
		add(-mid, 0, w, 2 * inner, near)
	end
	ring(h1, h2, true)
	ring(h2, half, false)
	return out
end

-- May a ground pad go at `spot`? Only Ground.Clear studs or more from the camera.
function WeatherLogic.padClear(spot: Vector3, camera: Vector3, cfg: Config?): boolean
	local c = cfg or WeatherConfig
	return (spot - camera).Magnitude >= c.Ground.Clear
end

-- A spot in a disc of `radius` for two rolls in [0, 1) (even over the area), flat.
function WeatherLogic.scatter(u: number, v: number, radius: number): Vector3
	local r = math.sqrt(math.clamp(u, 0, 1)) * radius
	local a = v * TAU
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- A tree's lean (radians, downwind) at time `now`: a slow wave with a flutter, never upwind.
function WeatherLogic.sway(now: number, phase: number, amount: number, speed: number): number
	local wave = 0.55 + 0.45 * math.sin(now * speed + phase)
	local flutter = 0.12 * math.sin(now * speed * 2.7 + phase * 1.3)
	return amount * math.max(0, wave + flutter)
end

---------------------------------------------------------------- rainbow

-- The rainbow's colour bands, outside in: radius and width at Rainbow.Distance.
function WeatherLogic.rainbowBands(cfg: Config?): { Band }
	local c = cfg or WeatherConfig
	local r = c.Rainbow
	local bands: { Band } = {}
	for i, color in ipairs(r.Colors) do
		-- the band spans [angle - Band / 2, angle + Band / 2] seen from the camera; on the arc's
		-- plane that is a ring between the two tangents (a little overlap: no gaps)
		local angle = r.Angle - (i - 0.5) * r.Band
		local outer = math.tan(math.rad(angle + r.Band / 2))
		local inner = math.tan(math.rad(angle - r.Band / 2))
		table.insert(bands, {
			Radius = r.Distance * (outer + inner) / 2,
			Width = r.Distance * (outer - inner) * 1.15,
			Color = color,
		})
	end
	return bands
end

--[[
	The arc of a band in the rainbow's own frame (x right, y up, the arc in
	the xy plane): the left foot, the top and the right foot, and each
	point's direction of travel (left to right), for two Beams (left foot ->
	top, top -> right foot) whose CurveSize0 = CurveSize1 = Curve make a
	half circle: a Beam's first control point is Attachment0 + its Axis x
	CurveSize0, the second Attachment1 - its Axis x CurveSize1.
]]
function WeatherLogic.rainbowArc(radius: number): { Points: { Vector3 }, Axes: { Vector3 }, Curve: number }
	return {
		Points = { Vector3.new(-radius, 0, 0), Vector3.new(0, radius, 0), Vector3.new(radius, 0, 0) },
		Axes = { Vector3.new(0, 1, 0), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0) },
		Curve = radius * WeatherLogic.Curve,
	}
end

-- The rainbow's frame for a camera at `cameraPosition` with the sun toward `sunDirection`: its
-- centre Rainbow.Distance away at the anti-solar point (below the horizon while the sun is up),
-- facing the camera, up = world up as far as it goes.
function WeatherLogic.rainbowFrame(cameraPosition: Vector3, sunDirection: Vector3, cfg: Config?): CFrame
	local c = cfg or WeatherConfig
	local away = -sunDirection
	if away.Magnitude < 1e-6 then
		away = Vector3.new(1, 0, 0)
	end
	local center = cameraPosition + away.Unit * c.Rainbow.Distance
	return CFrame.lookAt(center, cameraPosition)
end

-- The rainbow's alpha for a band point: the feet fade out (0 = foot, 1 = top).
function WeatherLogic.rainbowTransparency(alpha: number, along: number, cfg: Config?): number
	local c = cfg or WeatherConfig
	local r = c.Rainbow
	local base = r.Transparency + (r.FootFade - r.Transparency) * (1 - math.clamp(along, 0, 1)) ^ 2
	return 1 - (1 - base) * math.clamp(alpha, 0, 1)
end

---------------------------------------------------------------- where

-- True where weather shows: the surface (WeatherConfig.Zones), the sea and the sky above it.
function WeatherLogic.isSurface(position: Vector3, cfg: Config?): boolean
	local c = cfg or WeatherConfig
	local zone = WorldLayout.zoneAt(position)
	if zone then
		return c.Zones[zone.Id] == true
	end
	return position.Y >= c.OutsideMinY
end

return WeatherLogic
