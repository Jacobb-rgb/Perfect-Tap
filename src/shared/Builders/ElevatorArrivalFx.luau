--[[
	A mine's arrival in front of the elevator doors (owner 2026-11-15: "unique
	arrival effects for every mine"; the looks are ElevatorTravelConfig.Themes,
	keyed by the floor's Id):

	  Greystone Quarry   brown dust rolls in, small rocks tumble down, warm light
	  Ember Caves        glowing embers rise, a burst of sparks, red light
	  Deep Hollow        blue crystal shards grow out of the ground, cool motes, blue light
	  Sunken Palace      golden glitter falls, a gold ring runs over the ground, golden light
	  Stormglass Rift    violet energy motes, electric sparks and arcs, violet light
	  Heartstone Core    magenta motes rise round a glowing core, the light pulses

	Built once on the client and kept (pooled): one light, three emitters on two
	holders (the doors' feet and over the doorway), 8 pebbles, 6 crystal shards,
	a ring, 3 two-piece arcs and a core ball. setTheme() places and colours it
	for a stop; pose(fx, since) shows the parts for `since` seconds after the
	cabin stopped (pure: the Lune previews pose it too); burst() and rates() are
	the client's particles (random by nature, never in the pure pose). Reduce
	motion: no arcs, a slower swell, fewer particles.
]]

local ElevatorTravelConfig = require(script.Parent.Parent.Config.ElevatorTravelConfig)
local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)

type Theme = ElevatorTravelConfig.Theme

local Fx = {}

export type Pebble = { Part: BasePart, X: number, Z: number, Height: number, Delay: number, Spin: Vector3 }
export type Crystal = { Part: BasePart, Rest: CFrame, Size: Vector3, Delay: number }
export type Arc = { Parts: { BasePart }, Rest: { CFrame }, At: number }

export type Fx = {
	Folder: Folder,
	Ground: BasePart,
	Top: BasePart,
	LightPart: BasePart,
	Light: PointLight,
	Dust: ParticleEmitter,
	Motes: ParticleEmitter,
	Sparks: ParticleEmitter,
	Pebbles: { Pebble },
	Crystals: { Crystal },
	Ring: BasePart,
	Arcs: { Arc },
	Core: BasePart,
	Theme: Theme?,
	At: CFrame?,
}

local WHITE = Color3.new(1, 1, 1)
local DECOR: { [string]: any } = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 }
local GRAVITY = 60
local PLATE_TOP = 0.62 -- the stop's plate (MineKit.elevator: 0.6 tall)
-- where the effects stand (stop frame): in front of the doors, on the plate
Fx.Spot = CFrame.new(0, 0, -4.4)

local function part(folder: Folder, name: string, size: Vector3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {}
	for key, value in DECOR do
		props[key] = value
	end
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	local p = Geo.block(folder, CFrame.new(0, -500, 0), size, WHITE, material, props)
	p.Name = name
	return p
end

local function emitter(parent: BasePart, name: string, texture: string, settings: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Rate = 0
	e.LockedToPart = false
	local target: any = e
	for key, value in settings do
		target[key] = value
	end
	e.Parent = parent
	return e
end

function Fx.build(): Fx
	local folder = Instance.new("Folder")
	folder.Name = "ElevatorArrival"
	local ground = part(folder, "Ground", Vector3.new(6, 0.2, 2.6), Enum.Material.SmoothPlastic)
	local top = part(folder, "Top", Vector3.new(6, 0.2, 2.6), Enum.Material.SmoothPlastic)
	local lightPart = part(folder, "Light", Vector3.new(0.2, 0.2, 0.2), Enum.Material.SmoothPlastic)
	local l = Instance.new("PointLight")
	l.Range = 24
	l.Brightness = 0
	l.Shadows = false
	l.Parent = lightPart
	local sparkle = "rbxasset://textures/particles/sparkles_main.dds"
	local fx: Fx = {
		Folder = folder,
		Ground = ground,
		Top = top,
		LightPart = lightPart,
		Light = l,
		Dust = emitter(ground, "Dust", "rbxasset://textures/particles/smoke_main.dds", {
			Size = NumberSequence.new(2, 4.5),
			Transparency = NumberSequence.new(0.62, 1),
			Lifetime = NumberRange.new(1.4, 2.2),
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(45, 45),
			Acceleration = Vector3.new(0, 0.8, 0),
			LightEmission = 0,
		}),
		Motes = emitter(ground, "Motes", sparkle, {
			Size = NumberSequence.new(0.22, 0.05),
			Transparency = NumberSequence.new(0.1, 1),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(25, 25),
			LightEmission = 0.9,
		}),
		Sparks = emitter(ground, "Sparks", sparkle, {
			Size = NumberSequence.new(0.16, 0),
			Transparency = NumberSequence.new(0, 1),
			Lifetime = NumberRange.new(0.35, 0.6),
			Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(65, 65),
			Acceleration = Vector3.new(0, -28, 0),
			LightEmission = 1,
		}),
		Pebbles = {},
		Crystals = {},
		Ring = part(folder, "Ring", Vector3.new(0.08, 2, 2), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder }),
		Arcs = {},
		Core = part(folder, "Core", Vector3.new(1.8, 1.8, 1.8), Enum.Material.Neon, { Shape = Enum.PartType.Ball }),
		Theme = nil,
		At = nil,
	}
	local rng = Rng.new(4417)
	for i = 1, 8 do
		local size = rng:range(0.35, 0.65)
		table.insert(fx.Pebbles, {
			Part = part(folder, "Pebble", Vector3.new(size, size * rng:range(0.7, 1), size * rng:range(0.8, 1.1)), Enum.Material.Slate),
			X = (i - 4.5) * 0.7 + rng:range(-0.25, 0.25),
			Z = rng:range(-1.6, 0.6),
			Height = rng:range(8.5, 11),
			Delay = (i - 1) * 0.05 + rng:range(0, 0.05),
			Spin = Vector3.new(rng:range(-9, 9), rng:range(-9, 9), rng:range(-9, 9)),
		})
	end
	-- crystal shards in a half ring round the doors (frame of Fx.Spot), leaning out
	for i = 1, 6 do
		local side = if i % 2 == 0 then 1 else -1
		local k = math.ceil(i / 2)
		local x = side * (2.3 + k * 0.7)
		local z = -0.4 - k * 0.55
		local height = rng:range(1.2, 2.2)
		local rest = CFrame.new(x, PLATE_TOP, z) * CFrame.Angles(rng:range(-0.25, 0.1), 0, -side * rng:range(0.15, 0.4))
		table.insert(fx.Crystals, {
			Part = part(folder, "Crystal", Vector3.new(0.5, height, 0.5), Enum.Material.Neon),
			Rest = rest,
			Size = Vector3.new(rng:range(0.4, 0.6), height, rng:range(0.4, 0.6)),
			Delay = (i - 1) * 0.05,
		})
	end
	-- electric arcs: two thin pieces each, a zig-zag near the door frame
	local arcSpots: { { Points: { Vector3 }, At: number } } = {
		{ Points = { Vector3.new(-2.3, 5.2, 0.6), Vector3.new(-1.6, 4.1, 0.2), Vector3.new(-2.1, 3.0, 0.5) }, At = 0.3 },
		{ Points = { Vector3.new(2.2, 6.0, 0.4), Vector3.new(1.5, 5.0, 0.0), Vector3.new(2.3, 4.0, 0.3) }, At = 0.65 },
		{ Points = { Vector3.new(-0.8, 7.2, 0.5), Vector3.new(0.1, 6.6, 0.1), Vector3.new(0.9, 7.3, 0.4) }, At = 1.0 },
	}
	for _, spot in arcSpots do
		local pieces: { BasePart } = {}
		local rests: { CFrame } = {}
		for s = 1, 2 do
			local a = spot.Points[s]
			local b = spot.Points[s + 1]
			local len = (b - a).Magnitude
			table.insert(pieces, part(folder, "Arc", Vector3.new(0.07, 0.07, len), Enum.Material.Neon))
			table.insert(rests, CFrame.lookAt((a + b) / 2, b))
		end
		table.insert(fx.Arcs, { Parts = pieces, Rest = rests, At = spot.At })
	end
	return fx
end

-- Colours and places the effects for a mine at a stop (`at` = the stop's floor center).
function Fx.setTheme(fx: Fx, theme: Theme, at: CFrame)
	fx.Theme = theme
	fx.At = at
	local spot = at * Fx.Spot
	fx.Ground.CFrame = spot * CFrame.new(0, PLATE_TOP + 0.2, -0.2)
	fx.Top.CFrame = spot * CFrame.new(0, 7.2, 0.2)
	fx.LightPart.CFrame = spot * CFrame.new(0, 4, 1.4)
	fx.Light.Color = theme.Light
	fx.Light.Brightness = 0
	-- the emitters this mine uses sit on their holders, the others wait off the world
	fx.Dust.Parent = if theme.Dust then fx.Ground else nil
	fx.Sparks.Parent = if theme.Sparks then fx.Ground else nil
	fx.Motes.Parent = if theme.Motes then (if theme.MotesRise < 0 then fx.Top else fx.Ground) else nil
	if theme.Dust then
		fx.Dust.Color = ColorSequence.new(theme.Dust)
	end
	if theme.Sparks then
		fx.Sparks.Color = ColorSequence.new(theme.Sparks)
	end
	if theme.Motes then
		fx.Motes.Color = ColorSequence.new(theme.Motes)
		local rise = theme.MotesRise
		fx.Motes.EmissionDirection = if rise < 0 then Enum.NormalId.Bottom else Enum.NormalId.Top
		fx.Motes.Speed = if rise < 0 then NumberRange.new(0.8, 2) else NumberRange.new(rise * 0.6, rise * 1.2)
		fx.Motes.Acceleration = Vector3.new(0, if rise < 0 then -1.5 else rise * 0.5, 0)
	end
	for _, e in { fx.Dust, fx.Motes, fx.Sparks } do
		e.Rate = 0
	end
	local pebbleColor = theme.Pebbles or WHITE
	for i, pebble in fx.Pebbles do
		pebble.Part.Color = if i % 3 == 0 then pebbleColor:Lerp(Color3.new(0, 0, 0), 0.2) else pebbleColor
	end
	for i, crystal in fx.Crystals do
		local color = theme.Crystals or WHITE
		crystal.Part.Color = if i % 3 == 0 then color:Lerp(WHITE, 0.45) else color
	end
	fx.Ring.Color = theme.Ring or WHITE
	for _, arc in fx.Arcs do
		for _, piece in arc.Parts do
			piece.Color = theme.Arcs or WHITE
		end
	end
	fx.Core.Color = theme.Core or WHITE
	Fx.hide(fx)
end

-- Every part out of sight and the light off (the emitters stop).
function Fx.hide(fx: Fx)
	for _, pebble in fx.Pebbles do
		pebble.Part.Transparency = 1
	end
	for _, crystal in fx.Crystals do
		crystal.Part.Transparency = 1
	end
	fx.Ring.Transparency = 1
	for _, arc in fx.Arcs do
		for _, piece in arc.Parts do
			piece.Transparency = 1
		end
	end
	fx.Core.Transparency = 1
	fx.Light.Brightness = 0
	for _, e in { fx.Dust, fx.Motes, fx.Sparks } do
		e.Rate = 0
	end
end

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Where a pebble is `tau` seconds after it starts to fall: its height over the plate and whether it rests.
function Fx.pebbleHeight(height: number, size: number, tau: number): number
	local ground = PLATE_TOP + size / 2
	local drop = math.max(0, height - ground)
	local hit = math.sqrt(2 * drop / GRAVITY)
	if tau < hit then
		return height - 0.5 * GRAVITY * tau * tau
	end
	-- one small bounce, then it lies still
	local up = 0.3 * GRAVITY * hit
	local u = tau - hit
	return math.max(ground, ground + up * u - 0.5 * GRAVITY * u * u)
end

--[[
	The effects `since` seconds after the cabin stopped (they start as the
	doors open, OpenDelay later): the light, the pebbles, the crystals, the
	ring, the arcs, the core. Pure.
]]
function Fx.pose(fx: Fx, since: number, reduced: boolean)
	local theme = fx.Theme
	local at = fx.At
	if not theme or not at then
		return
	end
	local spot = at * Fx.Spot
	local level = ElevatorTravelConfig.arrivalLight(theme, since, reduced)
	-- (a PointLight without shadows shines into the cabin too: never so bright the doorway washes out)
	fx.Light.Brightness = 3 * level
	local fadeAll = 1 - smooth((since - 1.9) / 0.5)
	-- small rocks tumble down in front of the doors and come to rest
	if theme.Pebbles then
		for _, pebble in fx.Pebbles do
			local tau = since - 0.3 - pebble.Delay
			if tau < 0 or fadeAll <= 0 then
				pebble.Part.Transparency = 1
			else
				local y = Fx.pebbleHeight(pebble.Height, pebble.Part.Size.Y, tau)
				local spin = pebble.Spin * math.min(tau, 0.6)
				pebble.Part.CFrame = spot * CFrame.new(pebble.X, y, pebble.Z) * CFrame.Angles(spin.X, spin.Y, spin.Z)
				pebble.Part.Transparency = 1 - fadeAll
			end
		end
	end
	-- crystal shards grow out of the ground, glint and sink back
	if theme.Crystals then
		for _, crystal in fx.Crystals do
			local grow = smooth((since - 0.35 - crystal.Delay) / 0.35) * (1 - smooth((since - 2.0) / 0.4))
			if grow <= 0.01 then
				crystal.Part.Transparency = 1
			else
				local size = crystal.Size * grow
				crystal.Part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
				crystal.Part.CFrame = spot * crystal.Rest * CFrame.new(0, size.Y / 2, 0)
				local glint = if reduced then 0 else 0.15 * math.max(0, math.sin(since * 9 + crystal.Delay * 40))
				crystal.Part.Transparency = 0.12 - glint * 0.1
			end
		end
	end
	-- a glowing ring runs out over the ground
	if theme.Ring then
		local u = (since - 0.3) / (if reduced then 1.4 else 0.9)
		if u < 0 or u > 1 then
			fx.Ring.Transparency = 1
		else
			local d = 2 + 9 * smooth(u)
			fx.Ring.Size = Vector3.new(0.08, d, d)
			fx.Ring.CFrame = spot * CFrame.new(0, PLATE_TOP + 0.05, -0.6) * CFrame.Angles(0, 0, math.pi / 2)
			fx.Ring.Transparency = 0.15 + 0.85 * u
		end
	end
	-- short electric arcs, one at a time, about three a second at most (never with reduced motion)
	for _, arc in fx.Arcs do
		local lit = theme.Arcs ~= nil and not reduced and since >= arc.At and since < arc.At + 0.07
		for i, piece in arc.Parts do
			if lit then
				piece.CFrame = spot * arc.Rest[i]
				piece.Transparency = 0
			else
				piece.Transparency = 1
			end
		end
	end
	-- a glowing core over the doorway that beats with the light
	if theme.Core then
		local shown = smooth((since - 0.15) / 0.3) * fadeAll
		if shown <= 0.01 then
			fx.Core.Transparency = 1
		else
			local beat = if reduced or theme.Pulse <= 0 then 0 else math.cos(since * theme.Pulse * 2 * math.pi)
			local d = 1.6 * (1 + 0.12 * beat) * (0.6 + 0.4 * shown)
			fx.Core.Size = Vector3.new(d, d, d)
			fx.Core.CFrame = spot * CFrame.new(0, 5.4, -1.6)
			fx.Core.Transparency = 0.2 + 0.6 * (1 - shown) + 0.1 * (1 - beat) * 0.5
		end
	end
end

-- The one-off particle bursts as the doors open (the client; fewer with reduced motion).
function Fx.burst(fx: Fx, reduced: boolean)
	local theme = fx.Theme
	if not theme then
		return
	end
	local scale = if reduced then 0.4 else 1
	if theme.Dust then
		fx.Dust:Emit(math.floor(10 * scale + 0.5))
	end
	if theme.Motes then
		fx.Motes:Emit(math.floor(14 * scale + 0.5))
	end
	if theme.Sparks then
		fx.Sparks:Emit(math.floor(26 * scale + 0.5))
	end
end

-- The steady particle rates `since` seconds after the stop: they run while the doors open, then stop.
function Fx.rates(fx: Fx, since: number, reduced: boolean)
	local theme = fx.Theme
	if not theme then
		return
	end
	local on = since >= ElevatorTravelConfig.Timing.OpenDelay and since < 1.8
	local scale = if reduced then 0.4 else 1
	local dust = if on and theme.Dust then 5 * scale else 0
	local motes = if on and theme.Motes then 16 * scale else 0
	if fx.Dust.Rate ~= dust then
		fx.Dust.Rate = dust
	end
	if fx.Motes.Rate ~= motes then
		fx.Motes.Rate = motes
	end
	fx.Sparks.Rate = 0
end

return Fx
