--[[
	The level-up burst at the character's feet (step 3 of the "juicy level
	up" reel): a light pillar shoots up and thins out, a shockwave ring
	runs out over the ground, a second slower ring, and sparks fly up and
	out. Parts only (neon, no collisions, no shadows), posed by time, so
	LevelController plays it and the Lune previews pose the same frames.
	The owner's level-up reel of 2026-10-27 (Config/JuiceConfig.LevelUp
	Ripples) adds two things: light rays shooting out of the character for
	a moment (step 2, "a white flash with sunburst rays") and three thin
	rings rippling out across the floor one after another (step 3, "rings
	ripple out across the floor"; each ring is RippleBars thin bars round
	a circle: a Cylinder part would be a filled disc, not a ring).

	  LevelBurst.build(parent, cf, milestone?, extras?) -> Burst (cf = the ground under the feet;
	                              extras = false: no rays, no ripples, as before)
	  LevelBurst.pose(burst, t)   t seconds in (0..LevelBurst.Seconds; outside it every part is hidden)
	  LevelBurst.setOrigin(burst, cf, milestone?)  moves a pooled burst (LevelController keeps one)
]]

local LevelBurst = {}

LevelBurst.Seconds = 1.6
LevelBurst.Sparks = 12
LevelBurst.Color = Color3.fromRGB(255, 190, 60)
LevelBurst.Hot = Color3.fromRGB(255, 244, 200)
LevelBurst.MilestoneColor = Color3.fromRGB(255, 110, 200)
LevelBurst.Rays = 10 -- light rays out of the character
LevelBurst.Ripples = 3 -- rings rippling across the floor
LevelBurst.RippleBars = 16 -- bars per ring

export type Burst = {
	Model: Model,
	Origin: CFrame,
	Pillar: Part,
	Core: Part,
	Ring: Part,
	Ring2: Part,
	Sparks: { Part },
	Rays: { Part }, -- empty without the extras
	Ripples: { { Part } }, -- RippleBars bars per ring; empty without the extras
}

local function part(parent: Instance, name: string, shape: Enum.PartType, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 1
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Parent = parent
	return p
end

function LevelBurst.build(parent: Instance, cf: CFrame, milestone: boolean?, extras: boolean?): Burst
	local model = Instance.new("Model")
	model.Name = "LevelBurst"
	local color = if milestone then LevelBurst.MilestoneColor else LevelBurst.Color
	local sparks = {}
	for i = 1, LevelBurst.Sparks do
		table.insert(sparks, part(model, "Spark" .. i, Enum.PartType.Block, if i % 3 == 0 then LevelBurst.Hot else color))
	end
	local rays: { Part } = {}
	local ripples: { { Part } } = {}
	if extras ~= false then
		for i = 1, LevelBurst.Rays do
			table.insert(rays, part(model, "Ray" .. i, Enum.PartType.Block, LevelBurst.Hot))
		end
		for r = 1, LevelBurst.Ripples do
			local bars: { Part } = {}
			for i = 1, LevelBurst.RippleBars do
				table.insert(bars, part(model, "Ripple" .. r .. "_" .. i, Enum.PartType.Block, if r == 1 then LevelBurst.Hot else color))
			end
			table.insert(ripples, bars)
		end
	end
	local burst = {
		Model = model,
		Origin = cf,
		Pillar = part(model, "Pillar", Enum.PartType.Cylinder, color),
		Core = part(model, "Core", Enum.PartType.Cylinder, LevelBurst.Hot),
		Ring = part(model, "Ring", Enum.PartType.Cylinder, color),
		Ring2 = part(model, "Ring2", Enum.PartType.Cylinder, LevelBurst.Hot),
		Sparks = sparks,
		Rays = rays,
		Ripples = ripples,
	}
	model.Parent = parent
	return burst
end

-- Moves the (pooled) burst to a new spot and colour.
function LevelBurst.setOrigin(burst: Burst, cf: CFrame, milestone: boolean?)
	burst.Origin = cf
	local color = if milestone then LevelBurst.MilestoneColor else LevelBurst.Color
	burst.Pillar.Color = color
	burst.Ring.Color = color
	for i, spark in burst.Sparks do
		spark.Color = if i % 3 == 0 then LevelBurst.Hot else color
	end
	for r, bars in burst.Ripples do
		for _, bar in bars do
			bar.Color = if r == 1 then LevelBurst.Hot else color
		end
	end
end

local function span(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function easeOut(x: number): number
	return 1 - (1 - x) ^ 3
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis (X) turned up

function LevelBurst.pose(burst: Burst, t: number)
	local o = burst.Origin
	-- the pillar: shoots up fast, then thins and fades
	local rise = easeOut(span(t, 0, 0.25))
	local thin = span(t, 0.25, 1.1)
	local height = 2 + 26 * rise
	local width = 5.2 * (1 - 0.8 * thin) * (0.6 + 0.4 * rise)
	burst.Pillar.Size = Vector3.new(height, width, width)
	burst.Pillar.CFrame = o * CFrame.new(0, height / 2, 0) * UP
	burst.Pillar.Transparency = if t <= 0 or t >= 1.1 then 1 else 0.35 + 0.65 * thin
	burst.Core.Size = Vector3.new(height, width * 0.45, width * 0.45)
	burst.Core.CFrame = burst.Pillar.CFrame
	burst.Core.Transparency = if t <= 0 or t >= 1.0 then 1 else 0.1 + 0.9 * span(t, 0.2, 1.0)
	-- the shockwave: a thin disc running out over the ground
	local run = easeOut(span(t, 0.02, 0.6))
	local d = 2 + 22 * run
	burst.Ring.Size = Vector3.new(0.12, d, d)
	burst.Ring.CFrame = o * CFrame.new(0, 0.15, 0) * UP
	burst.Ring.Transparency = if t <= 0.02 or t >= 0.6 then 1 else 0.25 + 0.75 * run
	local run2 = easeOut(span(t, 0.12, 0.95))
	local d2 = 1 + 14 * run2
	burst.Ring2.Size = Vector3.new(0.1, d2, d2)
	burst.Ring2.CFrame = o * CFrame.new(0, 0.2, 0) * UP
	burst.Ring2.Transparency = if t <= 0.12 or t >= 0.95 then 1 else 0.3 + 0.7 * run2
	-- the sparks: out and up, falling a little, spinning, shrinking
	for i, spark in burst.Sparks do
		local angle = (i / #burst.Sparks) * math.pi * 2 + (i % 2) * 0.3
		local u = span(t, 0.05, 1.3)
		local out = 3 + 10 * easeOut(u) * (0.7 + 0.3 * ((i * 7) % 5) / 4)
		local up = 1.5 + (8 + (i % 4)) * u - 7 * u * u
		local s = 0.9 * (1 - u)
		spark.Size = Vector3.new(s, s, s)
		spark.CFrame = o * CFrame.new(math.cos(angle) * out, up, math.sin(angle) * out) * CFrame.Angles(u * 6 + i, u * 4, 0)
		spark.Transparency = if u <= 0 or u >= 1 then 1 else 0.1 + 0.6 * u
	end
	-- the rays: shoot out of the chest in a star, then thin out and fade
	local chest = o * CFrame.new(0, 3.2, 0)
	local shoot = easeOut(span(t, 0, 0.18))
	local fade = span(t, 0.16, 0.6)
	for i, ray in burst.Rays do
		if t <= 0 or t >= 0.6 then
			ray.Transparency = 1
			continue
		end
		local yaw = (i / #burst.Rays) * math.pi * 2 + 0.3
		local pitch = if i % 2 == 0 then 0.12 else 0.62
		local dir = chest:VectorToWorldSpace(Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), math.sin(yaw) * math.cos(pitch)))
		local length = (if i % 2 == 0 then 11 else 8) * shoot
		local thick = 0.5 * (1 - 0.75 * fade)
		local center = chest.Position + dir * (0.9 + length / 2)
		ray.Size = Vector3.new(thick, thick, math.max(length, 0.05))
		ray.CFrame = CFrame.lookAt(center, center + dir)
		ray.Transparency = 0.15 + 0.85 * fade
	end
	-- the ripples: thin rings running out across the floor one after another (the same
	-- speed, staggered, so they stay apart like ripples on water)
	for r, bars in burst.Ripples do
		local u = span(t, 0.08 + 0.2 * (r - 1), 1.03 + 0.2 * (r - 1))
		local hidden = u <= 0 or u >= 1
		local radius = 1.2 + 10.5 * (1 - (1 - u) * (1 - u))
		local length = 2 * radius * math.tan(math.pi / #bars) + 0.06
		local band = 0.75 * (1 - 0.5 * u)
		for i, bar in bars do
			if hidden then
				bar.Transparency = 1
				continue
			end
			local a = (i - 1) / #bars * math.pi * 2
			bar.Size = Vector3.new(band, 0.12, length)
			bar.CFrame = o * CFrame.new(math.cos(a) * radius, 0.22 + 0.02 * r, math.sin(a) * radius) * CFrame.Angles(0, -a, 0)
			bar.Transparency = 0.05 + 0.95 * u ^ 1.5
		end
	end
end

return LevelBurst
