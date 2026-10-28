--[[
	The weather reel's data (preview only): every weather kind over the lobby
	plaza, one after the other, from the game's own weather code
	(Config/WeatherConfig, Weather/WeatherLogic):

	  per frame   the kind and its strength, the rainbow's strength, the
	              emitter rates (WeatherLogic.rate), the WeatherTint
	              (WeatherLogic.tint), the lightning flash (WeatherLogic.flash),
	              the wind and the rain's lean (WeatherLogic.slant)
	  once        the particle looks, the boxes and pads (WeatherConfig), the
	              rainbow's bands as world-space polylines from the same
	              Bezier arcs the Beams draw (WeatherLogic.rainbowBands /
	              rainbowArc / rainbowFrame for this camera and the lobby sun)

	The reel is compressed: each kind fades in and out in about half a second
	(the game takes 20-25 s) and the storm strikes twice in ~3 s (the game
	once per 12 s window at most). tools/preview/weather_overlay.js draws the
	particles as 2D stand-ins over one three.js render of the lobby (Roblox's
	ParticleEmitters and Beams cannot be rendered outside Roblox), so this
	is an approximation: no trees swaying, no occlusion of the particles.
]]

local roblox = require("@lune/roblox") :: any

local WeatherPreview = {}

-- the lobby plaza from the west, looking east over the pond: the rainbow's side of the sky
WeatherPreview.Shot = {
	scene = "world",
	position = { -52, 14, 44 },
	target = { 40, 8, 18 },
	fov = 70,
	preset = "Surface",
	sunDir = { -0.965, 0.225, 0.136 },
	shadowExtent = 160,
	maxLights = 24,
}

-- the reel, in order (seconds); Czech titles for the owner
WeatherPreview.Segments = {
	{ kind = "Clear", length = 0.8, title = "JASNO", sub = "bez počasí" },
	{ kind = "Rain", length = 2.4, title = "1 · DÉŠŤ", sub = "šikmé kapky, cákance a kroužky na zemi i v jezírku" },
	{
		kind = "Storm",
		length = 2.8,
		title = "2 · BOUŘKA",
		sub = "hustší déšť, blesk rozsvítí celé nebe, hrom o chvilku později",
	},
	{ kind = "Hail", length = 2.2, title = "3 · KRUPOBITÍ", sub = "kuličky ledu odskakují od země a ťukají" },
	{ kind = "Snow", length = 2.4, title = "4 · SNÍH", sub = "vločky pomalu padají, u kamery nic: vždycky čistý výhled" },
	{ kind = "Wind", length = 2.2, title = "5 · VÍTR", sub = "listí letí přes obraz, stromy se ve hře ohýbají" },
	{ kind = "Heatwave", length = 2.0, title = "6 · VEDRO", sub = "teplé barvy, slunce naplno, horko stoupá od země" },
	{ kind = "Rainbow", length = 2.6, title = "BONUS · DUHA", sub = "po krátké přeháňce se vrátí slunce a objeví se duha" },
}

-- the close still: snow seen from a player's camera on the plaza (the clear view round the lens)
WeatherPreview.CloseShot = {
	scene = "world",
	position = { -14, 7, 46 },
	target = { 20, 2, 34 },
	fov = 70,
	preset = "Surface",
	sunDir = { -0.965, 0.225, 0.136 },
	shadowExtent = 120,
	maxLights = 24,
}
WeatherPreview.CloseSegments = {
	{
		kind = "Snow",
		length = 2.4,
		title = "SNÍH ZBLÍZKA",
		sub = "kolem kamery nepadá nic, vločky dál jsou menší: vždycky čistý výhled",
	},
}

local FADE_IN, FADE_OUT = 0.55, 0.45
local STRIKES = { 0.85, 2.0 } -- seconds into the storm segment (the reel's strikes)
local WIND_YAW = math.pi / 2 -- toward +Z: across the view from left to right

local function hex(c: any): string
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function vec(v: any): { number }
	return { v.X, v.Y, v.Z }
end

local TEXTURE_KIND = {
	["rbxasset://textures/particles/SquareParticle.png"] = "square",
	["rbxasset://textures/particles/smoke_main.dds"] = "smoke",
	["rbxasset://textures/particles/explosion01_shockwave_main.dds"] = "ring",
	["rbxasset://textures/particles/sparkles_main.dds"] = "sparkle",
}

local function particles(WeatherConfig: any): { [string]: any }
	local out = {}
	for key, p in WeatherConfig.Particles do
		out[key] = {
			texture = TEXTURE_KIND[p.Texture] or "smoke",
			color = hex(p.Color),
			color2 = if p.Color2 then hex(p.Color2) else nil,
			size = p.Size,
			grow = p.Grow or 1,
			speed = p.Speed,
			lifetime = p.Lifetime,
			transparency = p.Transparency,
			lightEmission = p.LightEmission,
			squash = p.Squash or 0,
			spread = p.Spread or 0,
			gravity = p.Gravity or 0,
			drag = p.Drag or 0,
			rotSpeed = p.RotSpeed or 0,
			orientation = p.Orientation or "FacingCamera",
		}
	end
	return out
end

-- The rainbow's bands as world polylines for a camera at `camera` (the Beams' Bezier arcs).
local function rainbow(WeatherLogic: any, WeatherConfig: any, LobbyLayout: any, camera: any): { any }
	local Vector3 = roblox.Vector3
	local frame = WeatherLogic.rainbowFrame(camera, LobbyLayout.SunDirection)
	local bands = {}
	for _, band in WeatherLogic.rainbowBands() do
		local arc = WeatherLogic.rainbowArc(band.Radius)
		local points = {}
		for seg = 1, 2 do
			local p0, p3 = arc.Points[seg], arc.Points[seg + 1]
			local p1 = p0 + arc.Axes[seg] * arc.Curve
			local p2 = p3 - arc.Axes[seg + 1] * arc.Curve
			for i = (if seg == 1 then 0 else 1), 32 do
				local t = i / 32
				local u = 1 - t
				local p: any = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
				local along = if seg == 1 then t else 1 - t -- 0 at a foot, 1 at the top
				local world = frame:PointToWorldSpace(Vector3.new(p.X, p.Y, p.Z))
				table.insert(points, { world.X, world.Y, world.Z, WeatherLogic.rainbowTransparency(1, along) })
			end
		end
		table.insert(bands, { color = hex(band.Color), width = band.Width, points = points })
	end
	return bands
end

local function ramp(t: number, length: number): number
	if t <= 0 or t >= length then
		return 0
	end
	local x = math.min(1, t / FADE_IN, (length - t) / FADE_OUT)
	return x * x * (3 - 2 * x)
end

function WeatherPreview.build(Loader: any, opts: { fps: number?, width: number?, height: number?, close: boolean? }): any
	local Vector3 = roblox.Vector3
	local WeatherConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WeatherConfig")
	local WeatherLogic = Loader.requirePath("ReplicatedStorage.Shared.Weather.WeatherLogic")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local fps = opts.fps or 24
	local shot = if opts.close then WeatherPreview.CloseShot else WeatherPreview.Shot
	local reel = if opts.close then WeatherPreview.CloseSegments else WeatherPreview.Segments
	local camera = Vector3.new(shot.position[1], shot.position[2], shot.position[3])

	-- the sky field per kind: its clear hole and strips (WeatherLogic.hole / strips)
	local sky = {}
	for _, kind in WeatherConfig.Order do
		local look = WeatherConfig.Kinds[kind]
		local hole = WeatherLogic.hole(look)
		local strips = {}
		for _, strip in WeatherLogic.strips(hole) do
			table.insert(strips, { strip.X, strip.Z, strip.SizeX, strip.SizeZ, strip.Near, strip.Share })
		end
		sky[kind] = { hole = hole, strips = strips, height = WeatherLogic.fieldHeight(look) }
	end

	local segments = {}
	local frames = {}
	local picks = {}
	local start = 0
	local L = WeatherConfig.Lightning
	for index, seg in reel do
		table.insert(segments, { title = seg.title, sub = seg.sub, kind = seg.kind, start = start, length = seg.length })
		local count = math.floor(seg.length * fps + 0.5)
		table.insert(picks, #frames + math.floor(count * (if seg.kind == "Storm" then 0.33 else 0.72)))
		for f = 0, count - 1 do
			local t = f / fps
			local kind = seg.kind
			local strength = ramp(t, seg.length)
			local bow = 0
			if seg.kind == "Rainbow" then
				-- a quick shower that clears while the rainbow fades in (Rainbow.Lead in the game)
				kind = "Rain"
				strength = 0.7 * math.clamp(1 - t / 1.1, 0, 1)
				bow = math.clamp((t - 0.5) / 0.9, 0, 1) * math.clamp((seg.length - t) / 0.3, 0, 1)
			elseif seg.kind == "Clear" then
				kind = "Clear"
				strength = 0
			end
			local look = WeatherConfig.Kinds[kind]
			local rates = {}
			if look and strength > 0 then
				local function rate(base: number?): number
					return WeatherLogic.rate(base, strength, false, false)
				end
				rates.Rain = rate(look.Rain)
				rates.Hail = rate(look.Hail)
				rates.Snow = rate(look.Snow)
				rates.Leaves = rate(look.Leaves) / 2
				rates.Leaves2 = rate(look.Leaves) / 2
				rates.Heat = rate(look.Heat)
				rates.Ripple = rate(look.Splash)
				rates.Drop = rate(look.Splash) * 0.6
				rates.Bounce = rate(look.Bounce)
				rates.Settle = rate(look.Settle)
			end
			local flash = 0
			if seg.kind == "Storm" then
				for _, at in STRIKES do
					flash = math.max(flash, WeatherLogic.flash(t - at))
				end
			end
			local tint = WeatherLogic.tint(kind, strength, bow)
			table.insert(frames, {
				seg = index - 1,
				kind = kind,
				i = strength,
				rb = bow,
				wind = WIND_YAW,
				slant = WeatherLogic.lookSlant(look),
				windSpeed = if look then look.Wind else 0,
				tint = {
					tint.Color.R,
					tint.Color.G,
					tint.Color.B,
					tint.Brightness + flash,
					tint.Contrast,
					tint.Saturation,
				},
				flash = flash,
				rates = rates,
			})
		end
		start += count / fps
	end

	return {
		fps = fps,
		width = opts.width or 1280,
		height = opts.height or 720,
		shot = shot,
		groundY = 0.2,
		seaY = -2,
		box = {
			field = WeatherConfig.Box.Field,
			height = WeatherConfig.Box.Height,
			nearSize = WeatherConfig.Box.NearSize,
			nearAlpha = WeatherConfig.Box.NearAlpha,
			ahead = WeatherConfig.Box.Ahead,
			air = vec(WeatherConfig.Box.Air),
			upwind = WeatherConfig.Box.Upwind,
		},
		ground = {
			points = WeatherConfig.Ground.Points,
			pad = WeatherConfig.Ground.Pad,
			ahead = WeatherConfig.Ground.Ahead,
			radius = WeatherConfig.Ground.Radius,
			perTick = WeatherConfig.Ground.PerTick,
			clear = WeatherConfig.Ground.Clear,
			tries = WeatherConfig.Ground.Tries,
			every = WeatherConfig.CheckEvery,
		},
		particles = particles(WeatherConfig),
		sky = sky,
		rainbow = rainbow(WeatherLogic, WeatherConfig, LobbyLayout, camera),
		lightning = { length = L.Length },
		segments = segments,
		frames = frames,
		picks = picks,
		duration = #frames / fps,
	}
end

return WeatherPreview
