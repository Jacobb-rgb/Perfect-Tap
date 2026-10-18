--[[
	Ride effects of the Robux hoverboards (HoverboardData.Effect), for the
	client (HoverboardController). Built once per board and reused:
	no instances are created while riding, only Enabled / Rate change.

	  Comet    a cyan -> magenta light trail from the tail, cyan / white
	           star sparks from the thrusters, magenta glints on the fin tips
	           and a shimmer around the comet orb                   30 particles/s
	  Phoenix  a gold -> flame -> violet trail, gold flames from the two
	           thrusters, rising embers around the board and gold / violet
	           sparkles on the wing tips                            38 particles/s
	  None     (coin boards) no effect set
	`lite` (low-end phones, many riders in view) halves every rate, shortens
	the trail and drops the volume emitter (Aura).

	Use:
	  local set = HoverboardFx.acquire(boardId, lite)   -- nil for "None" boards
	  if set and HoverboardFx.mount(set, boardModel) then
	      HoverboardFx.setActive(set, true, speedAlpha) -- 0..1 scales the rates
	  end
	  HoverboardFx.release(set)  -- disables, unmounts, keeps it for the next rider
	Emitters sit on the board's Attachments (HoverboardBuilder contract; the
	emitter's attribute "Mount" names it), trails between TrailLeft and
	TrailRight. Every emitter / trail starts disabled.

	Pure: only Instance creation (no services), so Lune tests and previews can
	build it.
]]

local HoverboardData = require(script.Parent.Parent.Config.HoverboardData)
local ItemBuilder = require(script.Parent.ItemBuilder)

local HoverboardFx = {}

HoverboardFx.PoolSize = 4 -- spare effect sets kept per board id
HoverboardFx.Sparkle = "rbxasset://textures/particles/sparkles_main.dds"
HoverboardFx.Fire = "rbxasset://textures/particles/fire_main.dds"

export type FxSet = {
	BoardId: string,
	Effect: HoverboardData.Effect,
	Lite: boolean,
	Emitters: { ParticleEmitter },
	Trails: { Trail },
	Model: Model?,
}

local WHITE = Color3.new(1, 1, 1)

local pools: { [string]: { FxSet } } = {}

local function glow(color: Color3): Color3
	return ItemBuilder.glowColor(color)
end

local function seq(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i, v in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(points)
end

local function colors(...: Color3): ColorSequence
	local values = { ... }
	if #values == 1 then
		return ColorSequence.new(values[1])
	end
	local points = {}
	for i, v in values do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return ColorSequence.new(points)
end

type EmitterSpec = {
	Name: string,
	Mount: string,
	Rate: number,
	Color: ColorSequence,
	Size: NumberSequence,
	Lifetime: NumberRange,
	Speed: NumberRange,
	Spread: number,
	Acceleration: Vector3?,
	Drag: number?,
	Texture: string?,
	Volume: boolean?, -- dropped in lite mode
}

local function emitter(set: FxSet, spec: EmitterSpec)
	if set.Lite and spec.Volume then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = spec.Name
	e.Enabled = false
	e.Texture = spec.Texture or HoverboardFx.Sparkle
	e.Color = spec.Color
	e.Size = spec.Size
	e.Transparency = seq(0.05, 0.25, 1)
	e.Lifetime = spec.Lifetime
	e.Speed = spec.Speed
	e.SpreadAngle = Vector2.new(spec.Spread, spec.Spread)
	e.Acceleration = spec.Acceleration or Vector3.zero
	e.Drag = spec.Drag or 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	local rate = if set.Lite then spec.Rate * 0.5 else spec.Rate
	e.Rate = rate
	e:SetAttribute("BaseRate", rate)
	e:SetAttribute("Mount", spec.Mount)
	table.insert(set.Emitters, e)
end

local function trail(set: FxSet, name: string, color: ColorSequence, lifetime: number)
	local t = Instance.new("Trail")
	t.Name = name
	t.Enabled = false
	t.Color = color
	t.Transparency = seq(0.15, 0.55, 1)
	t.WidthScale = seq(1, 0.55, 0.15)
	t.Lifetime = if set.Lite then lifetime * 0.6 else lifetime
	t.MinLength = 0.15
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = true -- reads from every camera angle (side views, other players)
	t:SetAttribute("Mount0", "TrailLeft")
	t:SetAttribute("Mount1", "TrailRight")
	table.insert(set.Trails, t)
end

local function comet(set: FxSet, c: HoverboardData.Colors)
	local cyan, magenta = glow(c.Glow), glow(c.Glow2)
	local star = c.Trim
	trail(set, "CometTrail", colors(cyan, cyan:Lerp(magenta, 0.5), magenta), 0.45)
	emitter(set, {
		Name = "CometStars",
		Mount = "Exhaust1",
		Rate = 16,
		Color = colors(star, cyan, magenta),
		Size = seq(0.45, 0.3, 0),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(3, 6),
		Spread = 18,
		Drag = 2,
	})
	for _, side in { "Left", "Right" } do
		emitter(set, {
			Name = "CometGlint" .. side,
			Mount = "Tip" .. side,
			Rate = 5,
			Color = colors(magenta:Lerp(WHITE, 0.3), magenta),
			Size = seq(0, 0.3, 0),
			Lifetime = NumberRange.new(0.3, 0.6),
			Speed = NumberRange.new(0.5, 1.5),
			Spread = 180,
		})
	end
	emitter(set, {
		Name = "CometShimmer",
		Mount = "Nose",
		Rate = 4,
		Color = colors(star, cyan),
		Size = seq(0, 0.35, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(0.3, 1),
		Spread = 180,
		Volume = true,
	})
end

local function phoenix(set: FxSet, c: HoverboardData.Colors)
	local gold, violet, fire = glow(c.Glow2), glow(c.Glow), glow(c.Accent)
	trail(set, "PhoenixTrail", colors(gold, fire, violet), 0.55)
	for i = 1, 2 do
		emitter(set, {
			Name = "PhoenixFlame" .. i,
			Mount = "Exhaust" .. i,
			Rate = 10,
			Color = colors(gold, fire, violet),
			Size = seq(0.6, 0.35, 0),
			Lifetime = NumberRange.new(0.3, 0.6),
			Speed = NumberRange.new(4, 7),
			Spread = 14,
			Acceleration = Vector3.new(0, 4, 0),
			Drag = 1.5,
			Texture = HoverboardFx.Fire,
		})
	end
	emitter(set, {
		Name = "PhoenixEmbers",
		Mount = "Aura",
		Rate = 6,
		Color = colors(gold, fire),
		Size = seq(0.3, 0.2, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.5, 1.5),
		Spread = 180,
		Acceleration = Vector3.new(0, 3, 0),
		Volume = true,
	})
	for _, side in { "Left", "Right" } do
		emitter(set, {
			Name = "PhoenixWing" .. side,
			Mount = "Tip" .. side,
			Rate = 6,
			Color = colors(gold, violet),
			Size = seq(0, 0.35, 0),
			Lifetime = NumberRange.new(0.35, 0.7),
			Speed = NumberRange.new(0.5, 2),
			Spread = 180,
		})
	end
end

-- A new (unmounted, disabled) effect set for a board, or nil when the board has no effect.
function HoverboardFx.create(boardId: string, lite: boolean?): FxSet?
	local board = HoverboardData.get(boardId)
	if not board or board.Effect == "None" then
		return nil
	end
	local set: FxSet = { BoardId = board.Id, Effect = board.Effect, Lite = lite == true, Emitters = {}, Trails = {}, Model = nil }
	if board.Effect == "Comet" then
		comet(set, board.Colors)
	elseif board.Effect == "Phoenix" then
		phoenix(set, board.Colors)
	end
	return set
end

-- Particles per second of a set at full intensity (the mobile budget check).
function HoverboardFx.rate(set: FxSet): number
	local total = 0
	for _, e in set.Emitters do
		total += e.Rate
	end
	return total
end

-- Puts the set on a built board: emitters into their Attachments, trails between
-- TrailLeft and TrailRight. false when an attachment is missing (nothing is moved).
function HoverboardFx.mount(set: FxSet, model: Model): boolean
	local root = model.PrimaryPart
	if not root then
		return false
	end
	local function find(name: any): Attachment?
		local a = if type(name) == "string" then root:FindFirstChild(name) else nil
		return if a and a:IsA("Attachment") then a else nil
	end
	for _, e in set.Emitters do
		if not find(e:GetAttribute("Mount")) then
			return false
		end
	end
	for _, t in set.Trails do
		if not find(t:GetAttribute("Mount0")) or not find(t:GetAttribute("Mount1")) then
			return false
		end
	end
	for _, e in set.Emitters do
		e.Parent = find(e:GetAttribute("Mount"))
	end
	for _, t in set.Trails do
		t.Attachment0 = find(t:GetAttribute("Mount0"))
		t.Attachment1 = find(t:GetAttribute("Mount1"))
		t.Parent = root
	end
	set.Model = model
	return true
end

-- Takes the set off its board (disabled first, so nothing lingers).
function HoverboardFx.unmount(set: FxSet)
	HoverboardFx.setActive(set, false)
	for _, e in set.Emitters do
		e.Parent = nil
	end
	for _, t in set.Trails do
		t.Parent = nil
		-- drop the old board's attachments (pcall: the Lune test runtime can't set refs to nil)
		pcall(function()
			t.Attachment0 = nil
			t.Attachment1 = nil
		end)
	end
	set.Model = nil
end

-- Turns the effects on or off; `intensity` 0..1 (board speed / top speed) scales the rates.
function HoverboardFx.setActive(set: FxSet, active: boolean, intensity: number?)
	local k = math.clamp(if intensity == nil then 1 else intensity, 0, 1)
	for _, e in set.Emitters do
		local base = e:GetAttribute("BaseRate")
		e.Rate = (if type(base) == "number" then base else 0) * k
		e.Enabled = active and k > 0
	end
	for _, t in set.Trails do
		t.Enabled = active and k > 0.15
	end
end

-- A set for a board from the pool (or a new one); nil for boards without effects.
function HoverboardFx.acquire(boardId: string, lite: boolean?): FxSet?
	local pool = pools[boardId]
	if pool then
		for i = #pool, 1, -1 do
			local set = pool[i]
			if set.Lite == (lite == true) then
				table.remove(pool, i)
				return set
			end
		end
	end
	return HoverboardFx.create(boardId, lite)
end

-- Gives a set back: unmounted and kept for the next rider (destroyed when the pool is full).
function HoverboardFx.release(set: FxSet)
	HoverboardFx.unmount(set)
	local pool = pools[set.BoardId]
	if not pool then
		pool = {}
		pools[set.BoardId] = pool
	end
	if table.find(pool, set) then
		return -- released twice
	end
	if #pool < HoverboardFx.PoolSize then
		table.insert(pool, set)
		return
	end
	for _, e in set.Emitters do
		e:Destroy()
	end
	for _, t in set.Trails do
		t:Destroy()
	end
end

-- Spare sets waiting in the pool for a board (tests).
function HoverboardFx.pooled(boardId: string): number
	local pool = pools[boardId]
	return if pool then #pool else 0
end

return HoverboardFx
