--[[
	Preview frames of the blaster shooting feel (Config/BlasterFeel,
	Effects/BlasterFx): a miner fires at a quarry rock; the beam, the muzzle
	flash, the sparks, the rock chips, the Lv7+ energy stream / swirl and
	the Lv10 shock ring are drawn from BlasterFeel's own numbers as parts
	(the renderer has no Beam or live particles). One scene per frame.

	  lune run tools/lune/export_blaster_feel.luau
	-> build/preview/blaster_feel_<n>.json + build/preview/blaster_feel_shots.json
	  SHOTS_EXTRA=build/preview/blaster_feel_shots.json node tools/preview/render.mjs blaster_feel_1 blaster_feel_1
	Frames: 1-4 one Lv10 shot (trigger down, first sparks, a chip pulse,
	steady fire), 5-7 steady fire at Lv3, Lv5, Lv8 (the tiers side by side).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local Gallery = require("./lib/blaster_gallery")

local root = process.cwd
Loader.init(root)

local CF = Loader.CFrame
local V3 = roblox.Vector3
local C3 = roblox.Color3
local Instance = roblox.Instance
local NEON = roblox.Enum.Material.Neon

local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local BlasterFeel = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterFeel")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")

local FX = { CanCollide = false, CastShadow = false }

local function presetsJson()
	local out = {}
	for name, preset in LightingConfig.Presets do
		local p = {}
		for group, values in preset do
			p[group] = {}
			for key, value in values do
				p[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
			end
		end
		out[name] = p
	end
	return out
end

local function rng(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

local function fade(props: any, t: number): any
	local p = table.clone(props)
	p.Transparency = t
	return p
end

--[[
	One frame. moment: "start" (trigger down: flash, kick x2), "first"
	(beam on, first sparks), "chips" (a chip pulse: chips, glints, swell,
	ring), "steady" (steady fire).
]]
local function frame(level: number, oreId: string, moment: string, seed: number): (any, any)
	local game = Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local feel = BlasterFeel.resolve(level, false)
	local tier = feel.Tier
	local look = BlasterBuilder.look(level, oreId)
	local glow = look.Glow
	local white = C3.new(1, 1, 1)
	local r = rng(seed)
	-- the quarry floor, a few rocks behind
	local m = Instance.new("Model")
	m.Name = "Shot"
	m.Parent = workspace
	Geo.block(m, CF.new(0, -0.5, 0), V3.new(120, 1, 120), C3.fromRGB(122, 104, 88))
	for i, p in { { -9, -14 }, { 7, -18 }, { -16, -4 }, { 15, -8 } } do
		local back = OreNodeBuilder.buildRock("Quarry", { "Copper" }, CF.new(p[1], 0, p[2]), 90 + i)
		back.Parent = m
	end
	local rock = OreNodeBuilder.buildRock("Quarry", { "Gold", "Copper" }, CF.new(0, 0, 0) * CF.Angles(0, 0.6, 0), 41)
	rock.Parent = m
	local feet = V3.new(13.5, 0, 10.5)
	local aim = Gallery.surface(rock, feet, 0.8)
	local tool, muzzle = Gallery.forgekeeper(Loader, m, CF.lookAt(feet, V3.new(0, 0, 0)), aim, level, oreId)
	-- the gun kick: the gun jumps back and the muzzle climbs (BlasterFx), x2 on the trigger
	local kick = if moment == "start" then 2 elseif moment == "chips" then 1 else 0
	if kick > 0 then
		local handle = tool:FindFirstChild("Handle")
		local pivot = handle.CFrame.Position
		local barrel = (muzzle - pivot).Unit
		local axis = barrel:Cross(V3.new(0, 1, 0)).Unit
		local lift = BlasterFeel.Recoil.GunLift * kick
		local move = CF.new(pivot) * CF.fromAxisAngle(axis, lift) * CF.new(-pivot) * CF.new(-barrel * BlasterFeel.Recoil.GunBack * kick)
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = move * d.CFrame
			end
		end
		muzzle = move * muzzle
	end
	local hit = aim
	local length = (hit - muzzle).Magnitude
	local dir = (hit - muzzle).Unit
	local back = -dir
	local swell = if moment == "chips" then 1.35 elseif moment == "first" then 1.15 else 1
	-- the beam: the glow (thicker at the muzzle), the white core, the Lv7+ energy motes
	local w = tier.BeamWidth * swell
	for i = 0, 3 do
		local a = muzzle + dir * (length * i / 4)
		local b = muzzle + dir * (length * (i + 1) / 4)
		local width = w * (1 - 0.28 * (i + 0.5) / 4)
		Geo.block(m, CF.lookAt((a + b) / 2, b), V3.new(width, width, (b - a).Magnitude), glow, NEON, fade(FX, 0.45 + 0.05 * i))
	end
	local core = tier.CoreWidth * swell * 0.7
	Geo.block(m, CF.lookAt((muzzle + hit) / 2, hit), V3.new(core, core, length), white:Lerp(glow, 0.15), NEON, FX)
	if tier.Energy then
		local step = 2.2
		local offset = (if moment == "steady" then 0.9 else 0.3)
		local d = offset
		while d < length - 0.4 do
			local p = muzzle + dir * d
			Geo.ball(m, p, w * 0.75, white:Lerp(glow, 0.35), NEON, fade(FX, 0.15))
			d += step
		end
		-- the swirl off the muzzle: sparkles drifting up and back
		for _ = 1, math.floor(feel.Swirl / 4) do
			local p = muzzle + V3.new((r() - 0.5) * 1.2, r() * 1.1, (r() - 0.5) * 1.2) + back * r() * 0.6
			Geo.ball(m, p, 0.12 + r() * 0.12, white:Lerp(glow, 0.5), NEON, FX)
		end
	end
	-- the muzzle flash (bigger on the trigger)
	-- (a soft glow sprite in the game; a see-through ball here)
	local flash = tier.Flash * (if moment == "start" then 1.0 else 0.55)
	Geo.ball(m, muzzle, flash, glow:Lerp(white, 0.45), NEON, fade(FX, 0.55))
	Geo.ball(m, muzzle, flash * 0.4, white, NEON, fade(FX, 0.1))
	-- the hit: the hot glow (the beam's light is there in the game too)
	if moment ~= "start" then
		Geo.ball(m, hit + back * 0.2, 1.1 * swell, glow, NEON, fade(FX, 0.35))
		Geo.ball(m, hit + back * 0.2, 0.5 * swell, white, NEON, FX)
		local holder = Geo.ball(m, hit + back * 0.8, 0.1, glow, nil, { CanCollide = false, Transparency = 1 })
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 9
		light.Brightness = tier.Light
		light.Parent = holder
		-- sparks bouncing back toward the shooter (Vfx.impact: a few per spark tick, two ticks shown)
		for _ = 1, feel.Sparks * 2 do
			local spread = V3.new((r() - 0.5) * 2, r() * 1.4, (r() - 0.5) * 2)
			local v = (back + spread * 0.75).Unit
			local d = 0.6 + r() * 2.4
			local p = hit + v * d + V3.new(0, -0.15 * d * d, 0)
			local len = 0.25 + r() * 0.35
			Geo.block(m, CF.lookAt(p, p + v), V3.new(0.07, 0.07, len), glow:Lerp(white, 0.5), NEON, FX)
		end
	end
	if moment == "chips" then
		-- rock chips in the crust colour and a few glints
		local crust = rock.PrimaryPart.Color
		for _ = 1, feel.Chips * 2 do
			local angle = r() * math.pi * 2
			local p = hit + back * 0.6 + V3.new(math.cos(angle) * (0.6 + r()), 0.8 + r() * 1.4, math.sin(angle) * (0.6 + r()))
			local s = 0.3 + r() * 0.3
			Geo.block(m, CF.new(p) * CF.Angles(r() * 6, r() * 6, 0), V3.new(s, s * 0.8, s), crust)
		end
		for _ = 1, math.max(1, feel.Sparks // 2) do
			local p = hit + back * 0.6 + V3.new((r() - 0.5) * 1.6, r() * 1.2, (r() - 0.5) * 1.6)
			Geo.ball(m, p, 0.22, white:Lerp(glow, 0.3), NEON, FX)
		end
		if feel.Rings > 0 then
			-- the Lv10 shock ring, facing the shooter
			local center = CF.lookAt(hit + back * 0.3, hit + back * 2)
			for i = 0, 23 do
				local a = i / 24 * math.pi * 2
				local p = center * CF.new(math.cos(a) * 1.7, math.sin(a) * 1.7, 0)
				Geo.block(
					m,
					CF.lookAt(p.Position, p.Position + center.LookVector) * CF.Angles(0, 0, a),
					V3.new(0.12, 0.5, 0.06),
					glow:Lerp(white, 0.3),
					NEON,
					fade(FX, 0.25)
				)
			end
		end
	end
	-- the camera: beside the shot, looking across the beam
	local mid = (muzzle + hit) / 2
	local side = dir:Cross(V3.new(0, 1, 0)).Unit
	local cam = mid + side * 13 + V3.new(0, 3.2, 0) - dir * 3.5
	local sun = ((cam - mid).Unit + V3.new(0, 0.9, 0)).Unit
	return workspace,
		{
			position = { cam.X, cam.Y, cam.Z },
			target = { mid.X - dir.X * 1.8, mid.Y - 0.3, mid.Z - dir.Z * 1.8 },
			fov = 50,
			sun = { sun.X, sun.Y, sun.Z },
		}
end

local frames = {
	{ 10, "start" },
	{ 10, "first" },
	{ 10, "chips" },
	{ 10, "steady" },
	{ 3, "steady" },
	{ 5, "chips" },
	{ 8, "steady" },
}

fs.writeDir(root .. "/build/preview")
local presets = presetsJson()
local shots = {}
for i, f in frames do
	local level, moment = f[1], f[2]
	local workspace, camera = frame(level, BlasterData.vaultOre(level), moment, 1000 + i * 17)
	local scene = Export.collect(workspace)
	scene.presets = presets
	local name = "blaster_feel_" .. i
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", scene))
	shots[name] = {
		scene = name,
		position = camera.position,
		target = camera.target,
		fov = camera.fov,
		preset = "Surface",
		sunDir = camera.sun,
		shadowExtent = 40,
		maxLights = 6,
	}
	print(string.format("Exported %s (Lv%d %s): %d parts, %d lights", name, level, moment, #scene.parts, #scene.lights))
end
fs.writeFile(root .. "/build/preview/blaster_feel_shots.json", serde.encode("json", shots, true))
