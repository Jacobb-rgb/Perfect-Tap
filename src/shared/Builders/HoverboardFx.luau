--[[
	Ride effects of every hoverboard (HoverboardData.Effect), for the client
	(HoverboardController). Built once per board and reused: no instances are
	created while riding, only Enabled / Rate change and bursts :Emit().

	Coin boards: small thruster effects, no trail (the trail stays a Robux perk).
	  Sparks   Timber Drifter: amber thruster puffs, a little dust under the
	           planks                                               8 particles/s
	  Vents    Cart Cruiser: blue flame jets from the twin exhausts, a warm
	           headlamp glint, grey dust                           12 particles/s
	  Lava     Emberglass Glider: a lava jet, lava drips falling from the
	           belly and embers rising around the rider            12 particles/s
	Robux boards: a light trail and big effects.
	  Comet    a cyan -> magenta light trail from the tail, cyan / white
	           star sparks from the thrusters, magenta glints on the fin tips,
	           a shimmer around the comet orb and star dust under it  36 particles/s
	  Phoenix  a gold -> flame -> violet trail, gold flames from the two
	           thrusters, wings of fire on the wing tips, rising embers and
	           falling gold feathers                               37 particles/s
	  None     no effect set
	Bursts (one :Emit each, HoverboardFx.burst): "Start" when you hop on (a
	dust / spark / star / fire splash under the board), "Boost" when you reach
	top speed (sparks from the thrusters; a sonic star cone on the Comet, a
	fire flare on the Phoenix).
	Lightning (HoverboardBolts, owner 2026-10-24): every board crackles with
	arcs in its glow colour (more and longer on the Robux boards, more with
	speed and while surging) and a strike from the sky hits it when you hop
	on: HoverboardFx.flicker / strike, called by HoverboardController.
	`lite` (low-end phones, many riders in view) halves every rate and burst,
	shortens the trail and drops the volume emitters (dust, embers, feathers).

	Use:
	  local set = HoverboardFx.acquire(boardId, lite)   -- nil for "None" boards
	  if set and HoverboardFx.mount(set, boardModel) then
	      HoverboardFx.setActive(set, true, speedAlpha) -- 0..1 scales the rates
	      HoverboardFx.burst(set, "Start")
	  end
	  HoverboardFx.release(set)  -- disables, unmounts, keeps it for the next rider
	Emitters sit on the board's Attachments (HoverboardBuilder contract; the
	emitter's attribute "Mount" names it), trails between TrailLeft and
	TrailRight. Every emitter / trail starts disabled; burst emitters stay
	disabled and only ever :Emit().

	Pure: only Instance creation (no services), so Lune tests and previews can
	build it.
]]

local HoverboardBolts = require(script.Parent.HoverboardBolts)
local HoverboardData = require(script.Parent.Parent.Config.HoverboardData)
local ItemBuilder = require(script.Parent.ItemBuilder)

local HoverboardFx = {}

HoverboardFx.PoolSize = 4 -- spare effect sets kept per board id
HoverboardFx.Sparkle = "rbxasset://textures/particles/sparkles_main.dds"
HoverboardFx.Fire = "rbxasset://textures/particles/fire_main.dds"
HoverboardFx.Smoke = "rbxasset://textures/particles/smoke_main.dds"
HoverboardFx.BoostAt = 0.92 -- speed / board speed: the Boost burst fires when you reach this
HoverboardFx.BoostReset = 0.6 -- ... and can fire again after slowing below this

export type Burst = "Start" | "Boost"

export type FxSet = {
	BoardId: string,
	Effect: HoverboardData.Effect,
	Lite: boolean,
	Emitters: { ParticleEmitter }, -- continuous (Rate follows the speed)
	Bursts: { ParticleEmitter }, -- one-shot (attribute "Burst" = Start / Boost, "Count")
	Trails: { Trail },
	Bolts: HoverboardBolts.BoltSet?, -- the lightning
	Model: Model?,
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

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
	Rate: number?, -- continuous emitters
	Burst: Burst?, -- burst emitters: fired by HoverboardFx.burst
	Count: number?, -- particles per burst
	Color: ColorSequence,
	Size: NumberSequence,
	Transparency: NumberSequence?,
	Lifetime: NumberRange,
	Speed: NumberRange,
	Spread: number,
	Acceleration: Vector3?,
	Drag: number?,
	Texture: string?,
	Dull: boolean?, -- dust: lit by the world, no glow
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
	e.Transparency = spec.Transparency or seq(0.05, 0.25, 1)
	e.Lifetime = spec.Lifetime
	e.Speed = spec.Speed
	e.SpreadAngle = Vector2.new(spec.Spread, spec.Spread)
	e.Acceleration = spec.Acceleration or Vector3.zero
	e.Drag = spec.Drag or 0
	e.LightEmission = if spec.Dull then 0 else 1
	e.LightInfluence = if spec.Dull then 1 else 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e:SetAttribute("Mount", spec.Mount)
	if spec.Burst then
		e.Rate = 0
		e:SetAttribute("Burst", spec.Burst)
		local count = spec.Count or 8
		e:SetAttribute("Count", math.max(1, math.floor(if set.Lite then count * 0.5 else count)))
		table.insert(set.Bursts, e)
		return
	end
	local base = spec.Rate or 0
	local rate = if set.Lite then base * 0.5 else base
	e.Rate = rate
	e:SetAttribute("BaseRate", rate)
	table.insert(set.Emitters, e)
end

local function trail(set: FxSet, name: string, color: ColorSequence, lifetime: number)
	local t = Instance.new("Trail")
	t.Name = name
	t.Enabled = false
	t.Color = color
	t.Transparency = seq(0.1, 0.5, 1)
	t.WidthScale = seq(1, 0.6, 0.15)
	t.Lifetime = if set.Lite then lifetime * 0.6 else lifetime
	t.MinLength = 0.15
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = true -- reads from every camera angle (side views, other players)
	t:SetAttribute("Mount0", "TrailLeft")
	t:SetAttribute("Mount1", "TrailRight")
	table.insert(set.Trails, t)
end

-- Dust kicked up under the board (Pad points down): a soft puff, lit by the world.
local function dust(set: FxSet, name: string, color: Color3, rate: number)
	emitter(set, {
		Name = name,
		Mount = "Pad",
		Rate = rate,
		Color = colors(color, color:Lerp(WHITE, 0.3)),
		Size = seq(0.4, 1.1, 1.6),
		Transparency = seq(0.55, 0.75, 1),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(1.5, 3),
		Spread = 70,
		Drag = 3,
		Texture = HoverboardFx.Smoke,
		Dull = true,
		Volume = true,
	})
end

-- The hop-on splash under the board: `count` particles flying out low and slowing down.
local function splash(set: FxSet, name: string, color: ColorSequence, count: number, texture: string?, dull: boolean?)
	emitter(set, {
		Name = name,
		Mount = "Pad",
		Burst = "Start",
		Count = count,
		Color = color,
		Size = if dull then seq(0.5, 1.4, 2) else seq(0.5, 0.35, 0),
		Transparency = if dull then seq(0.4, 0.65, 1) else nil,
		Lifetime = NumberRange.new(0.45, 0.8),
		Speed = NumberRange.new(7, 11),
		Spread = 85,
		Drag = 6,
		Acceleration = Vector3.new(0, 3, 0),
		Texture = texture,
		Dull = dull,
	})
end

-- Sparks shooting back out of every exhaust when you reach top speed.
local function boostSparks(set: FxSet, prefix: string, exhausts: number, color: ColorSequence, count: number)
	for i = 1, exhausts do
		emitter(set, {
			Name = prefix .. "Boost" .. i,
			Mount = "Exhaust" .. i,
			Burst = "Boost",
			Count = count,
			Color = color,
			Size = seq(0.45, 0.3, 0),
			Lifetime = NumberRange.new(0.25, 0.5),
			Speed = NumberRange.new(9, 14),
			Spread = 22,
			Drag = 3,
		})
	end
end

local function sparks(set: FxSet, c: HoverboardData.Colors)
	local amber, gold = glow(c.Glow), glow(c.Glow2)
	for i = 1, 2 do
		emitter(set, {
			Name = "TimberPuff" .. i,
			Mount = "Exhaust" .. i,
			Rate = 3,
			Color = colors(gold, amber, c.Trim),
			Size = seq(0.42, 0.28, 0),
			Lifetime = NumberRange.new(0.18, 0.35),
			Speed = NumberRange.new(3, 5),
			Spread = 10,
			Drag = 2,
			Texture = HoverboardFx.Fire,
		})
	end
	dust(set, "TimberDust", c.Main:Lerp(WHITE, 0.35), 2)
	splash(set, "TimberLift", colors(c.Main:Lerp(WHITE, 0.45)), 10, HoverboardFx.Smoke, true)
	boostSparks(set, "Timber", 2, colors(gold:Lerp(WHITE, 0.3), amber), 4)
end

local function vents(set: FxSet, c: HoverboardData.Colors)
	local blue, lamp = glow(c.Glow), glow(c.Glow2)
	for i = 1, 2 do
		emitter(set, {
			Name = "CartJet" .. i,
			Mount = "Exhaust" .. i,
			Rate = 4,
			Color = colors(blue:Lerp(WHITE, 0.45), blue, c.Main),
			Size = seq(0.4, 0.26, 0),
			Lifetime = NumberRange.new(0.2, 0.35),
			Speed = NumberRange.new(5, 8),
			Spread = 8,
			Drag = 2,
			Texture = HoverboardFx.Fire,
		})
	end
	emitter(set, {
		Name = "CartLamp",
		Mount = "Nose",
		Rate = 2,
		Color = colors(lamp:Lerp(WHITE, 0.4), lamp),
		Size = seq(0, 0.5, 0),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(0.2, 0.6),
		Spread = 180,
	})
	dust(set, "CartDust", c.Main:Lerp(WHITE, 0.2), 2)
	splash(set, "CartLift", colors(blue:Lerp(WHITE, 0.3), blue), 12)
	boostSparks(set, "Cart", 2, colors(blue:Lerp(WHITE, 0.5), blue), 5)
end

local function lava(set: FxSet, c: HoverboardData.Colors)
	local hot, ember = glow(c.Glow), glow(c.Glow2)
	emitter(set, {
		Name = "LavaJet",
		Mount = "Exhaust1",
		Rate = 5,
		Color = colors(ember:Lerp(WHITE, 0.3), hot, c.Main),
		Size = seq(0.6, 0.38, 0),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(4, 7),
		Spread = 12,
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 1.5,
		Texture = HoverboardFx.Fire,
	})
	emitter(set, {
		Name = "LavaDrips",
		Mount = "Pad",
		Rate = 3,
		Color = colors(ember, hot, hot:Lerp(BLACK, 0.5)),
		Size = seq(0.24, 0.2, 0.1),
		Transparency = seq(0, 0.1, 1),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(0.5, 1.5),
		Spread = 25,
		Acceleration = Vector3.new(0, -30, 0),
	})
	emitter(set, {
		Name = "LavaEmbers",
		Mount = "Aura",
		Rate = 4,
		Color = colors(ember, hot),
		Size = seq(0.22, 0.16, 0),
		Lifetime = NumberRange.new(0.8, 1.3),
		Speed = NumberRange.new(0.5, 1.5),
		Spread = 180,
		Acceleration = Vector3.new(0, 4, 0),
		Volume = true,
	})
	splash(set, "LavaSplash", colors(ember, hot), 14, HoverboardFx.Fire)
	boostSparks(set, "Lava", 1, colors(ember:Lerp(WHITE, 0.3), hot), 10)
end

local function comet(set: FxSet, c: HoverboardData.Colors)
	local cyan, magenta = glow(c.Glow), glow(c.Glow2)
	local star = c.Trim
	trail(set, "CometTrail", colors(cyan, cyan:Lerp(magenta, 0.5), magenta), 0.55)
	emitter(set, {
		Name = "CometStars",
		Mount = "Exhaust1",
		Rate = 16,
		Color = colors(star, cyan, magenta),
		Size = seq(0.5, 0.32, 0),
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
			Size = seq(0, 0.35, 0),
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
	emitter(set, {
		Name = "CometDust",
		Mount = "Pad",
		Rate = 6,
		Color = colors(WHITE, cyan, magenta),
		Size = seq(0, 0.3, 0),
		Lifetime = NumberRange.new(0.6, 1.0),
		Speed = NumberRange.new(1, 2.5),
		Spread = 60,
		Drag = 1.5,
	})
	splash(set, "CometNova", colors(WHITE, cyan, magenta), 18)
	-- the sonic boom at top speed: a cone of stars out of the tail and a white flash on the orb
	emitter(set, {
		Name = "CometBoom",
		Mount = "Exhaust1",
		Burst = "Boost",
		Count = 24,
		Color = colors(WHITE, cyan, magenta),
		Size = seq(0.55, 0.4, 0),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(10, 16),
		Spread = 55,
		Drag = 4,
	})
	emitter(set, {
		Name = "CometFlash",
		Mount = "Nose",
		Burst = "Boost",
		Count = 1,
		Color = colors(WHITE, cyan),
		Size = seq(0.5, 3.5, 4),
		Transparency = seq(0, 0.5, 1),
		Lifetime = NumberRange.new(0.25, 0.25),
		Speed = NumberRange.new(0, 0),
		Spread = 0,
	})
end

local function phoenix(set: FxSet, c: HoverboardData.Colors)
	local gold, violet, fire = glow(c.Glow2), glow(c.Glow), glow(c.Accent)
	trail(set, "PhoenixTrail", colors(gold, fire, violet), 0.65)
	for i = 1, 2 do
		emitter(set, {
			Name = "PhoenixFlame" .. i,
			Mount = "Exhaust" .. i,
			Rate = 10,
			Color = colors(gold, fire, violet),
			Size = seq(0.65, 0.38, 0),
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
		Rate = 4,
		Color = colors(gold, fire),
		Size = seq(0.3, 0.2, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.5, 1.5),
		Spread = 180,
		Acceleration = Vector3.new(0, 3, 0),
		Volume = true,
	})
	-- wings of fire: flames licking up off both wing tips
	for _, side in { "Left", "Right" } do
		emitter(set, {
			Name = "PhoenixWing" .. side,
			Mount = "Tip" .. side,
			Rate = 5,
			Color = colors(gold:Lerp(WHITE, 0.2), fire, violet),
			Size = seq(0.5, 0.32, 0),
			Lifetime = NumberRange.new(0.35, 0.65),
			Speed = NumberRange.new(0.5, 1.5),
			Spread = 60,
			Acceleration = Vector3.new(0, 6, 0),
			Texture = HoverboardFx.Fire,
		})
	end
	emitter(set, {
		Name = "PhoenixFeathers",
		Mount = "Aura",
		Rate = 3,
		Color = colors(gold, gold:Lerp(violet, 0.4)),
		Size = seq(0.32, 0.26, 0),
		Lifetime = NumberRange.new(1.0, 1.6),
		Speed = NumberRange.new(1, 2),
		Spread = 180,
		Acceleration = Vector3.new(0, -2.5, 0),
		Drag = 2,
		Volume = true,
	})
	splash(set, "PhoenixRise", colors(gold, fire, violet), 20, HoverboardFx.Fire)
	-- the flare at top speed: a burst of fire up through the rider plus gold sparks from the thrusters
	emitter(set, {
		Name = "PhoenixFlare",
		Mount = "Aura",
		Burst = "Boost",
		Count = 16,
		Color = colors(gold:Lerp(WHITE, 0.3), fire, violet),
		Size = seq(0.9, 0.6, 0),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(5, 9),
		Spread = 70,
		Acceleration = Vector3.new(0, 8, 0),
		Drag = 3,
		Texture = HoverboardFx.Fire,
	})
	boostSparks(set, "Phoenix", 2, colors(gold:Lerp(WHITE, 0.4), gold), 6)
end

-- A new (unmounted, disabled) effect set for a board, or nil when the board has no effect.
function HoverboardFx.create(boardId: string, lite: boolean?): FxSet?
	local board = HoverboardData.get(boardId)
	if not board or board.Effect == "None" then
		return nil
	end
	local set: FxSet = {
		BoardId = board.Id,
		Effect = board.Effect,
		Lite = lite == true,
		Emitters = {},
		Bursts = {},
		Trails = {},
		Bolts = HoverboardBolts.create(board.Effect, glow(board.Colors.Glow), lite),
		Model = nil,
	}
	local build: (FxSet, HoverboardData.Colors) -> () = if board.Effect == "Sparks"
		then sparks
		elseif board.Effect == "Vents" then vents
		elseif board.Effect == "Lava" then lava
		elseif board.Effect == "Comet" then comet
		else phoenix
	build(set, board.Colors)
	return set
end

-- Continuous particles per second of a set at full intensity (the mobile budget check).
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
	for _, list in { set.Emitters, set.Bursts } do
		for _, e in list do
			if not find(e:GetAttribute("Mount")) then
				return false
			end
		end
	end
	for _, t in set.Trails do
		if not find(t:GetAttribute("Mount0")) or not find(t:GetAttribute("Mount1")) then
			return false
		end
	end
	for _, list in { set.Emitters, set.Bursts } do
		for _, e in list do
			e.Parent = find(e:GetAttribute("Mount"))
		end
	end
	for _, t in set.Trails do
		t.Attachment0 = find(t:GetAttribute("Mount0"))
		t.Attachment1 = find(t:GetAttribute("Mount1"))
		t.Parent = root
	end
	local bolts = set.Bolts
	if bolts then
		HoverboardBolts.mount(bolts, root)
	end
	set.Model = model
	return true
end

-- Takes the set off its board (disabled first, so nothing lingers).
function HoverboardFx.unmount(set: FxSet)
	HoverboardFx.setActive(set, false)
	for _, list in { set.Emitters, set.Bursts } do
		for _, e in list do
			e.Parent = nil
		end
	end
	for _, t in set.Trails do
		t.Parent = nil
		-- drop the old board's attachments (pcall: the Lune test runtime can't set refs to nil)
		pcall(function()
			t.Attachment0 = nil
			t.Attachment1 = nil
		end)
	end
	local bolts = set.Bolts
	if bolts then
		HoverboardBolts.unmount(bolts)
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
	local bolts = set.Bolts
	if bolts and not active then
		HoverboardBolts.hide(bolts)
	end
end

-- One lightning flicker (every HoverboardBolts.FlickerEvery seconds while riding):
-- `speed` 0..1 = speed / top speed, `surge` 0..1 = the hop on, top speed or a landing.
-- Returns how many arcs show.
function HoverboardFx.flicker(set: FxSet, rand: () -> number, speed: number, surge: number): number
	local bolts = set.Bolts
	if not bolts or not set.Model then
		return 0
	end
	return HoverboardBolts.flicker(bolts, rand, speed, surge)
end

-- The strike from the sky (the hop on): alpha > 0 shows it with a new shape, 0 hides it.
function HoverboardFx.strike(set: FxSet, rand: () -> number, alpha: number)
	local bolts = set.Bolts
	if bolts and set.Model then
		HoverboardBolts.strike(bolts, rand, alpha, 1.5)
	end
end

-- Fires a set's one-shot bursts of that kind ("Start" when you hop on, "Boost" at top
-- speed). Only while mounted; a set without such a burst does nothing.
function HoverboardFx.burst(set: FxSet, kind: Burst)
	if not set.Model then
		return
	end
	for _, e in set.Bursts do
		local count = e:GetAttribute("Count")
		if e:GetAttribute("Burst") == kind and type(count) == "number" and e.Parent then
			e:Emit(count)
		end
	end
end

-- Particles one burst of that kind throws (the budget check).
function HoverboardFx.burstCount(set: FxSet, kind: Burst): number
	local total = 0
	for _, e in set.Bursts do
		local count = e:GetAttribute("Count")
		if e:GetAttribute("Burst") == kind and type(count) == "number" then
			total += count
		end
	end
	return total
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
	for _, list in { set.Emitters, set.Bursts } do
		for _, e in list do
			e:Destroy()
		end
	end
	for _, t in set.Trails do
		t:Destroy()
	end
	local bolts = set.Bolts
	if bolts then
		HoverboardBolts.destroy(bolts)
	end
end

-- Spare sets waiting in the pool for a board (tests).
function HoverboardFx.pooled(boardId: string): number
	local pool = pools[boardId]
	return if pool then #pool else 0
end

return HoverboardFx
