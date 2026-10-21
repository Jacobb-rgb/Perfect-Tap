--[[
	The level-up burst at the character's feet (step 3 of the "juicy level
	up" reel): a light pillar shoots up and thins out, a shockwave ring
	runs out over the ground, a second slower ring, and sparks fly up and
	out. Parts only (neon, no collisions, no shadows), posed by time, so
	LevelController plays it and the Lune previews pose the same frames.

	  LevelBurst.build(parent, cf, milestone?) -> Burst (cf = the ground under the feet)
	  LevelBurst.pose(burst, t)   t seconds in (0..LevelBurst.Seconds; outside it every part is hidden)
	  LevelBurst.setOrigin(burst, cf, milestone?)  moves a pooled burst (LevelController keeps one)
]]

local LevelBurst = {}

LevelBurst.Seconds = 1.6
LevelBurst.Sparks = 12
LevelBurst.Color = Color3.fromRGB(255, 190, 60)
LevelBurst.Hot = Color3.fromRGB(255, 244, 200)
LevelBurst.MilestoneColor = Color3.fromRGB(255, 110, 200)

export type Burst = {
	Model: Model,
	Origin: CFrame,
	Pillar: Part,
	Core: Part,
	Ring: Part,
	Ring2: Part,
	Sparks: { Part },
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

function LevelBurst.build(parent: Instance, cf: CFrame, milestone: boolean?): Burst
	local model = Instance.new("Model")
	model.Name = "LevelBurst"
	local color = if milestone then LevelBurst.MilestoneColor else LevelBurst.Color
	local sparks = {}
	for i = 1, LevelBurst.Sparks do
		table.insert(sparks, part(model, "Spark" .. i, Enum.PartType.Block, if i % 3 == 0 then LevelBurst.Hot else color))
	end
	local burst = {
		Model = model,
		Origin = cf,
		Pillar = part(model, "Pillar", Enum.PartType.Cylinder, color),
		Core = part(model, "Core", Enum.PartType.Cylinder, LevelBurst.Hot),
		Ring = part(model, "Ring", Enum.PartType.Cylinder, color),
		Ring2 = part(model, "Ring2", Enum.PartType.Cylinder, LevelBurst.Hot),
		Sparks = sparks,
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
end

return LevelBurst
