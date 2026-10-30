--[[
	HatchFx: the egg opening in the flow of the owner's clicker-sim video
	(2026-10-29: "open them exactly like there, this clean, glowing by
	rarity"; docs/plans/CLICKER_VIDEO_2026-10-29.md, section 1). Our eggs
	(their skins unchanged) and our golems; CapsuleController plays it in
	the full-screen viewport of CapsuleView's opening, the previews pose the
	same functions frame by frame.

	V2 (owner 2026-10-30, "ULTIMATE EGG OPENING V2": an entrance, a float,
	an energy charge, a rarity cinematic) keeps that flow and adds to it:

	  entrance   the eggs rise into their places from below, growing (0.3 of
	             their size, past it, back: Back), one after another, a
	             quick half turn settling; a glowing platform grows under
	             each (one in the middle at 60 % of the screen's height; 3
	             side by side and overlapping, the middle one bigger; 10 in
	             two rows of 5)
	  float      they float: a slow bob and a slow turn, a few motes rising
	  charge     white shockwave rings and a puff: the energy starts; two
	             energy rings orbit each egg (opposite ways, faster and
	             faster), motes stream into it, its glow grows, it pulses
	             and shakes harder; the cracks glow in the rarity colour of
	             the golem inside THAT egg (BrightTheme.crackColour; Mythic
	             a moving rainbow), growing in three steps, the egg pulsing
	             a little bigger at each; soft blobs of the best colour
	             drift behind
	  suspense   Legendary / Mythic: brighter cracks, a harder shake
	  silhouette each egg turns into a solid glowing silhouette of its colour
	  burst      it bursts: ONE flash in the best colour (RevealKit's one
	             flash gap: never sooner than FlashGap after the last; a
	             refused flash waits for its slot; stronger for the rarer,
	             Tiers), shell pieces, a puff, the rings fly apart, the
	             platforms flare and go
	  reveal     the golems stand where their eggs were, HUGE and SOLID, on a
	             soft sunburst with a little confetti and a soft aura each,
	             each with its name and "1 in N" (a Legendary / Mythic in a
	             batch centred, bigger, in front); up to 5: a pill over each
	             head with its rarity and its bonus ("RARE", "+10% Income")
	  rarity     the batch's best rarity sets the show (Tiers): Common a soft
	             white glow; Uncommon a green energy pulse; Rare blue energy
	             rings, more confetti; Epic a purple aura, a stronger flash;
	             Legendary golden rays, a slow-motion reveal, gold confetti,
	             LEGENDARY!; Mythic rainbow rays and energy, a brighter
	             stage, rainbow confetti, MYTHIC! (the server tells the
	             others: CapsuleService.announce)
	  hold       a gentle bob
	  fly        they spin and fly toward the player, shrinking; the HUD
	             comes back

	Everything here is pure (the Lune specs and the previews run it): the
	timeline (timeline: Auto's fast one, Reduce motion's calm one), the
	layout (layout: where each egg and golem stands, as shares of the
	screen), the camera maths of the stage viewport (at, project, depthFor:
	its camera at the origin looking along -Z, FieldOfView Fov), the poses
	(eggPose, golemPose) and the crack network (Cracks, addCracks: thin Neon
	parts on the egg's front, built once on the opening's pooled eggs, never
	on the eggs in the world). Reduce motion: no rise, float, orbit, motes,
	rings, shake, flash or spin; the eggs fade in, crack, fade out, the
	golems fade in and out (the platforms, auras, pills and the banner fade
	with them, still).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BrightTheme = require(Shared.Config.BrightTheme)

local HatchFx = {}

HatchFx.FlashTime = 0.3 -- the flash fades in this long (RevealKit.poseFlash)
HatchFx.FlashPeak = 0.85 -- its strongest (1 - BackgroundTransparency; RevealKit caps it at its FlashPeak)
HatchFx.MinShow = 0.3 -- every golem shows at least this long, named, whatever is skipped (paid random items)
HatchFx.Fov = 40 -- the stage viewport's camera
HatchFx.Turn = 0.22 -- radians a golem turns from facing the camera (a 3/4 look)
HatchFx.RingCount = 3 -- shockwave rings per egg
HatchFx.OrbitCount = 2 -- energy rings orbiting each egg while it charges (a phone opening many: 1)

export type Times = {
	Pop: number, -- an egg's entrance (it rises into its place, growing)
	Stagger: number, -- between two eggs coming in (x3: 3, x10: 10)
	Float: number, -- the eggs float this long before the charge
	Rings: number, -- the white rings and the puff, from the charge's start
	Steps: { number }, -- the cracks' three steps, from the charge's start
	Glow: number, -- the last step to the silhouette
	Silhouette: number, -- the silhouette to the burst
	GolemPop: number, -- a golem's pop (a Legendary / Mythic: its Tier's, slower)
	Hold: number, -- the golems stay (after their pop)
	Fly: number, -- they fly to the player
}

HatchFx.Times = {
	-- (Open 3 of Commons about 4.6 s; a Legendary about 6.2 s, a Mythic about 6.8 s: Tiers)
	Normal = {
		Pop = 0.5,
		Stagger = 0.09,
		Float = 0.55,
		Rings = 0,
		Steps = { 0.3, 0.7, 1.1 },
		Glow = 0.35,
		Silhouette = 0.12,
		GolemPop = 0.3,
		Hold = 1.05,
		Fly = 0.45,
	},
	-- Auto (about 2 s an opening, every golem still shown, named)
	Fast = {
		Pop = 0.2,
		Stagger = 0.03,
		Float = 0.1,
		Rings = 0,
		Steps = { 0.12, 0.27, 0.42 },
		Glow = 0.14,
		Silhouette = 0.06,
		GolemPop = 0.2,
		Hold = 0.62,
		Fly = 0.3,
	},
	-- Reduce motion: the eggs fade in, crack, fade out; the golems fade in and out
	Calm = {
		Pop = 0.2,
		Stagger = 0,
		Float = 0.2,
		Rings = math.huge,
		Steps = { 0.15, 0.4, 0.65 },
		Glow = 0.2,
		Silhouette = 0.25, -- (the eggs' fade out)
		GolemPop = 0.25, -- (the golems' fade in)
		Hold = 1.0,
		Fly = 0.3, -- (their fade out)
	},
} :: { [string]: Times }

--[[
	The rarity cinematic: the batch's BEST rarity (its Order, 1 Common ..
	6 Mythic) sets it. The same flow for every rarity, more of it for the
	rarer: never slower for a Common than its timings.
]]
export type Tier = {
	Suspense: number, -- seconds more build-up before the silhouette (Auto: SuspenseFast; Reduce motion: none)
	SuspenseFast: number,
	GolemPop: number?, -- a slow-motion reveal: the golems' pop this long (nil: the timings')
	Hold: number, -- seconds more they stand (Auto: HoldFast): the banner is read
	HoldFast: number,
	Flash: number, -- the burst's flash at its strongest (<= FlashPeak)
	Pulses: number, -- energy rings out of the best golem at the reveal, in its colour
	Confetti: number, -- confetti pieces at the reveal (of CapsuleView.ConfettiCount)
	Aura: number, -- the golems' aura (0..1)
	Rays: boolean, -- the sunburst's rays in the rarity's colour (Mythic: a rainbow); else soft white
	Banner: string?, -- a big word over the golems
	Light: number, -- the stage's light lifts (Mythic's stronger light: 0..1)
}

HatchFx.Tiers = {
	-- Common: a soft white glow, a few bits
	{ Suspense = 0, SuspenseFast = 0, Hold = 0, HoldFast = 0, Flash = 0.55, Pulses = 0, Confetti = 8, Aura = 0.4, Rays = false, Light = 0 },
	-- Uncommon: green, a small energy pulse
	{ Suspense = 0, SuspenseFast = 0, Hold = 0, HoldFast = 0, Flash = 0.6, Pulses = 1, Confetti = 12, Aura = 0.5, Rays = false, Light = 0 },
	-- Rare: blue energy rings, more bits
	{
		Suspense = 0,
		SuspenseFast = 0,
		Hold = 0.1,
		HoldFast = 0,
		Flash = 0.65,
		Pulses = 2,
		Confetti = 18,
		Aura = 0.6,
		Rays = false,
		Light = 0,
	},
	-- Epic: a purple aura, a stronger flash
	{
		Suspense = 0,
		SuspenseFast = 0,
		Hold = 0.2,
		HoldFast = 0,
		Flash = 0.8,
		Pulses = 2,
		Confetti = 18,
		Aura = 0.9,
		Rays = false,
		Light = 0,
	},
	-- Legendary: golden rays, a slow-motion reveal, gold confetti, LEGENDARY!
	{
		Suspense = 0.8,
		SuspenseFast = 0.4,
		GolemPop = 0.55,
		Hold = 0.5,
		HoldFast = 0.35,
		Flash = 0.85,
		Pulses = 3,
		Confetti = 18,
		Aura = 1,
		Rays = true,
		Banner = "LEGENDARY!",
		Light = 0,
	},
	-- Mythic: rainbow rays and energy, a brighter stage, rainbow confetti, MYTHIC!
	{
		Suspense = 1.0,
		SuspenseFast = 0.4,
		GolemPop = 0.65,
		Hold = 0.8,
		HoldFast = 0.35,
		Flash = 0.85,
		Pulses = 3,
		Confetti = 18,
		Aura = 1,
		Rays = true,
		Banner = "MYTHIC!",
		Light = 0.35,
	},
} :: { Tier }

-- The Tier of a batch whose best golem has Rarity `order` (1..6).
function HatchFx.tierOf(order: number): Tier
	return HatchFx.Tiers[math.clamp(math.floor(if order == order then order else 1), 1, #HatchFx.Tiers)]
end

export type Timeline = {
	Count: number,
	Order: number, -- the rarest golem's Rarity Order
	Fast: boolean,
	Reduced: boolean,
	Times: Times,
	Tier: Tier, -- the best rarity's cinematic
	Stagger: number,
	Float: number, -- the last egg is in: the float
	Charge: number, -- the energy charge starts (the orbits, the motes, the glow)
	Rings: number, -- the rings and the puff (math.huge: none)
	Steps: { number }, -- each crack step
	Suspense: number, -- seconds of it (0: none), from the last step
	Silhouette: number, -- the eggs turn into their colour
	Burst: number, -- they burst: the flash
	Reveal: number, -- the golems pop
	GolemPop: number, -- their pop (the Tier's slow motion)
	Banner: number, -- the big word slams in (math.huge: none)
	Fly: number, -- they fly to the player
	Total: number, -- the opening ends: the HUD comes back
}

--[[
	The timings of an opening of `count` eggs whose rarest golem has Rarity
	`order`: `fast` (Auto), `reduced` (Reduce motion). Open 3 of Commons
	takes about 4.6 s, Auto's about 2 s; a rarer best golem adds its Tier
	(the suspense, a slower pop, a longer hold; Reduce motion: no suspense,
	no slow motion, the hold for the banner).
]]
function HatchFx.timeline(order: number, count: number, fast: boolean, reduced: boolean): Timeline
	local n = math.clamp(math.floor(if count == count then count else 1), 1, 10)
	local o = math.clamp(math.floor(if order == order then order else 1), 1, 6)
	local times = if reduced then HatchFx.Times.Calm elseif fast then HatchFx.Times.Fast else HatchFx.Times.Normal
	local tier = HatchFx.tierOf(o)
	local stagger = if n > 3 then times.Stagger * 0.6 else times.Stagger
	local suspense = if reduced then 0 elseif fast then tier.SuspenseFast else tier.Suspense
	local spread = stagger * (n - 1) -- (the last egg comes in this much later: everything waits for it)
	local float = times.Pop + spread
	local charge = float + times.Float
	local steps = table.clone(times.Steps)
	for i, s in steps do
		steps[i] = s + charge
	end
	local silhouette = steps[#steps] + suspense + times.Glow
	local burst = silhouette + times.Silhouette
	local reveal = burst + (if reduced then times.Silhouette * 0.4 else 0.04)
	local pop = if fast or reduced then times.GolemPop else (tier.GolemPop or times.GolemPop)
	local hold = times.Hold + (if fast then tier.HoldFast else tier.Hold)
	local fly = reveal + pop + hold
	return {
		Count = n,
		Order = o,
		Fast = fast,
		Reduced = reduced,
		Times = times,
		Tier = tier,
		Stagger = stagger,
		Float = float,
		Charge = charge,
		Rings = if reduced then math.huge else charge + times.Rings,
		Steps = steps,
		Suspense = suspense,
		Silhouette = silhouette,
		Burst = burst,
		Reveal = reveal,
		GolemPop = pop,
		Banner = if tier.Banner then reveal + pop * 0.5 else math.huge,
		Fly = fly,
		Total = fly + times.Fly,
	}
end

--[[
	Where a tap at `t` goes: before the burst straight to it (the flash and
	the golems); while the golems stand on to their flight, but only once
	they have been out `shown` seconds (real time: their pop and MinShow):
	nil means "not yet" (the controller waits and goes then). Skip-all is a
	tap that also asks for the flight. Never back: every golem is seen,
	named (paid random items).
]]
function HatchFx.skipTo(t: number, tl: Timeline, shown: number): number?
	if t < tl.Burst then
		return tl.Burst
	elseif t < tl.Fly then
		if shown >= HatchFx.namedAt(tl) + HatchFx.MinShow then
			return tl.Fly
		end
		return nil
	end
	return t
end

HatchFx.GolemRipple = 0.03 -- seconds between two golems popping out (a batch)
HatchFx.NameIn = 0.16 -- a golem's name is fully shown this long after its pop

-- Seconds from the reveal until the LAST golem's name is fully shown (MinShow counts from there: every one named).
function HatchFx.namedAt(tl: Timeline): number
	local ripple = if tl.Reduced then 0 else HatchFx.GolemRipple
	return (tl.Count - 1) * ripple + (if tl.Reduced then tl.Times.GolemPop else HatchFx.NameIn)
end

---------------------------------------------------------------- the stage's camera

local function tanHalf(): number
	return math.tan(math.rad(HatchFx.Fov / 2))
end

-- The stage camera's point on the ray through the screen share (u right, v down) at depth z.
function HatchFx.at(u: number, v: number, z: number, aspect: number): Vector3
	local t = tanHalf()
	return Vector3.new((2 * u - 1) * t * aspect * z, (1 - 2 * v) * t * z, -z)
end

-- A stage point's screen share (u right, v down) and its depth.
function HatchFx.project(p: Vector3, aspect: number): (Vector2, number)
	local z = math.max(1e-3, -p.Z)
	local t = tanHalf()
	return Vector2.new(0.5 + p.X / (2 * z * t * aspect), 0.5 - p.Y / (2 * z * t)), z
end

-- How far a thing `height` studs tall stands to fill `share` of the screen's height.
function HatchFx.depthFor(height: number, share: number): number
	return height / (math.max(0.01, share) * 2 * tanHalf())
end

---------------------------------------------------------------- the layout

export type Slot = {
	Egg: Vector2, -- the egg's middle (screen shares: x right, y down)
	EggH: number, -- its height (a share of the screen's height)
	Golem: Vector2, -- its golem's middle
	GolemH: number,
	Text: number, -- the name's text size (design units; the chance's is ChanceShare of it)
	Front: boolean, -- drawn in front (the middle egg of a row, the special golem)
}

export type Layout = {
	Count: number,
	Special: number?,
	Slots: { Slot },
	Spacing: number, -- between two neighbours' middles (a share of the screen's width): a name fits in it
	Overrun: boolean?, -- the second row's marks still pass `Floor` at the smallest golems (HatchStage reports it)
}

HatchFx.ChanceShare = 0.74 -- the "1 in N" under a name, against the name's size

-- The slot in the middle of `count` eggs (where a Legendary / Mythic of the batch goes).
function HatchFx.centreSlot(count: number): number
	local n = math.clamp(math.floor(count), 1, 10)
	if n <= 5 then
		return math.ceil(n / 2)
	end
	return 3 -- (the top row's middle)
end

--[[
	Where `count` eggs and their golems stand on a screen `aspect` wide
	(width / height): one in the middle at 60 % of the height; up to 3 side
	by side, overlapping, the middle one bigger (about 70 % of the height
	together, the video); 4-5 in a row; more in two rows of 5. `special`: the
	slot of a Legendary / Mythic, whose golem stands centred, bigger, in
	front. The top centre stays free (nothing above 16 % of the height
	there: room for a quest card).
]]
--[[
	Two rows whose tags carry marks under their names (DELETED pills,
	waiting notes) part downward only (the top row and the top centre stay):
	`Top` the top row's tallest tag under its golem's feet, `Low` the second
	row's, `Floor` how far down the second row's tags may reach (the safe
	bottom, above a phone's home indicator); shares of the screen's height.
	Where the screen is short the golems get a little smaller.
]]
export type Marks = { Top: number, Low: number, Floor: number }

-- Two rows of 5 (`count` 6-10): where golem `i` stands across a screen `aspect` wide (a share of its
-- width) and the pitch between two of a row.
function HatchFx.rowX(i: number, count: number, aspect: number): (number, number)
	local a = math.max(0.8, if aspect == aspect then aspect else 16 / 9)
	local dx = math.min(0.17, 0.33 / a)
	local row = if i <= 5 then 1 else 2
	local inRow = if row == 1 then 5 else math.clamp(math.floor(count), 6, 10) - 5
	local col = if row == 1 then i else i - 5
	return 0.5 + (col - (inRow + 1) / 2) * dx, dx
end

function HatchFx.layout(count: number, aspect: number, special: number?, marks: Marks?): Layout
	local n = math.clamp(math.floor(if count == count then count else 1), 1, 10)
	local a = math.max(0.8, if aspect == aspect then aspect else 16 / 9)
	local slots: { Slot } = {}
	local spacing = 0.9
	local overrun = false
	if n == 1 then
		local big = special == 1
		table.insert(slots, {
			Egg = Vector2.new(0.5, 0.5),
			EggH = 0.6,
			Golem = Vector2.new(0.5, if big then 0.46 else 0.47),
			GolemH = if big then 0.56 else 0.5,
			Text = 44,
			Front = true,
		})
	elseif n <= 3 then
		-- (side by side and overlapping: the middles a third of the height apart, the middle one bigger, in front;
		-- the golems a little further apart: their names fit between)
		local dx = math.min(0.26, 0.33 / a)
		local gdx = math.min(0.28, 0.37 / a)
		spacing = gdx * (if n == 2 then 1.15 else 1)
		local mid = (n + 1) / 2
		for i = 1, n do
			local off = i - mid
			local centre = math.abs(off) < 0.01
			local isSpecial = special == i
			table.insert(slots, {
				Egg = Vector2.new(0.5 + off * dx * (if n == 2 then 0.9 else 1), if centre then 0.52 else 0.555),
				EggH = if centre then 0.64 else 0.52,
				Golem = Vector2.new(0.5 + off * spacing, if isSpecial then 0.455 elseif centre then 0.465 else 0.49),
				GolemH = if isSpecial then 0.56 elseif centre then 0.48 else 0.42,
				Text = if isSpecial then 38 else 34,
				Front = centre or isSpecial,
			})
		end
	elseif n <= 5 then
		local dx = math.min(0.19, 0.31 / a)
		spacing = dx
		local mid = (n + 1) / 2
		for i = 1, n do
			local isSpecial = special == i
			table.insert(slots, {
				Egg = Vector2.new(0.5 + (i - mid) * dx, 0.52),
				EggH = 0.42,
				Golem = Vector2.new(0.5 + (i - mid) * dx, if isSpecial then 0.47 else 0.49),
				GolemH = if isSpecial then 0.44 else 0.34,
				Text = if isSpecial then 32 else 28,
				Front = isSpecial,
			})
		end
	else
		-- two rows of 5 (the second may be shorter); a special one makes room: the rows part a little;
		-- `marks` (tags carry DELETED pills or waiting notes): the second row moves down until no top-row
		-- mark covers a second-row golem's head, its own tags above `Floor` (smaller golems where that
		-- needs it); the top row and the top centre never move
		local _, dx = HatchFx.rowX(1, n, a)
		spacing = dx
		local rowY = if special then { 0.33, 0.71 } else { 0.33, 0.69 }
		local golemH, specialH, eggH = 0.25, 0.33, 0.29
		if marks then
			local h = 0.25
			while true do
				local hs = h * 1.32
				local feet = math.max(rowY[1] - 0.01 + h / 2, if special then rowY[1] + 0.005 + hs / 2 else 0)
				-- (the second row's golem heads under the top row's tags, a little gap)
				local y2 = math.max(rowY[2], feet + marks.Top + 0.02 + 0.01 + h / 2)
				local fits = y2 - 0.01 + h / 2 + marks.Low <= marks.Floor
				if fits or h <= 0.17 then
					rowY = { rowY[1], y2 }
					golemH, specialH, eggH = h, hs, 0.29 * h / 0.25
					overrun = not fits -- (the smallest golems and still past it: a screen too short)
					break
				end
				h -= 0.01
			end
		end
		for i = 1, n do
			local row = if i <= 5 then 1 else 2
			local x = HatchFx.rowX(i, n, a)
			local isSpecial = special == i
			table.insert(slots, {
				Egg = Vector2.new(x, rowY[row]),
				EggH = eggH,
				Golem = Vector2.new(x, if isSpecial then rowY[row] + 0.005 else rowY[row] - 0.01),
				GolemH = if isSpecial then specialH else golemH,
				Text = if isSpecial then 26 else 22,
				Front = isSpecial,
			})
		end
	end
	return { Count = n, Special = special, Slots = slots, Spacing = spacing, Overrun = if overrun then true else nil }
end

--[[
	The order the results stand in: a Legendary / Mythic (`best`, the
	batch's rarest, when its Rarity order is 5 or more) goes to the middle
	slot, the others keep their order round it. Returns the result index for
	each slot and the special slot (nil: none).
]]
function HatchFx.arrange(count: number, best: number, bestOrder: number): ({ number }, number?)
	local n = math.clamp(math.floor(count), 1, 10)
	local out: { number } = {}
	for i = 1, n do
		out[i] = i
	end
	if bestOrder < 5 or best < 1 or best > n then
		return out, nil
	end
	local centre = HatchFx.centreSlot(n)
	if n > 1 then
		table.remove(out, best)
		table.insert(out, centre, best)
	end
	return out, centre
end

---------------------------------------------------------------- the poses (pure)

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- Back easing (overshoots, then settles): 0 -> 1.
function HatchFx.back(x: number): number
	x = clamp01(x)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- How many crack steps have come by `t` (0..3).
function HatchFx.levelAt(t: number, tl: Timeline): number
	local level = 0
	for i, s in tl.Steps do
		if t >= s then
			level = i
		end
	end
	return level
end

-- The little swell of a crack step (0 .. 1 .. 0 in 0.16 s after each step).
local PULSE = 0.16
function HatchFx.pulseAt(t: number, tl: Timeline): number
	if tl.Reduced then
		return 0
	end
	local best = 0
	for _, s in tl.Steps do
		local u = t - s
		if u >= 0 and u < PULSE then
			best = math.max(best, math.sin(u / PULSE * math.pi))
		end
	end
	return best
end

-- How far into the suspense `t` is (0..1; 0 without one).
function HatchFx.suspenseAt(t: number, tl: Timeline): number
	if tl.Suspense <= 0 then
		return 0
	end
	local from = tl.Steps[#tl.Steps]
	return clamp01((t - from) / tl.Suspense)
end

export type EggPose = {
	Shown: boolean, -- false: popped (the burst) or not in yet
	Scale: number, -- its size against its place's (the entrance, the pulses, the swell)
	Roll: number, -- its rock (radians, about its foot)
	Yaw: number, -- its turn round its upright (radians: the entrance's half turn, the float's slow turn)
	Drop: number, -- how far under its place it is (a share of the screen's height: the rise, the bob)
	Fade: number, -- 0 seen .. 1 gone (Reduce motion's fades)
	Level: number, -- cracks lit (0..3)
	Bright: number, -- 0..1: the cracks whiten (the suspense)
	Silhouette: number, -- 0..1: the egg turns into its colour
	Charge: number, -- 0..1: the energy charge (its orbits, motes and glow)
}

HatchFx.Rise = 0.42 -- an egg rises this far into its place (a share of the screen's height)
HatchFx.Bob = 0.012 -- the float's bob (a share of the screen's height)
HatchFx.FloatTurn = 0.28 -- the float's slow turn (radians each way)

-- Ease out (cubic): fast, then settling.
local function easeOut(x: number): number
	local k = 1 - clamp01(x)
	return 1 - k * k * k
end

-- How far into the energy charge `t` is (0..1): from the charge's start to the silhouette.
function HatchFx.chargeAt(t: number, tl: Timeline): number
	return clamp01((t - tl.Charge) / math.max(0.01, tl.Silhouette - tl.Charge))
end

--[[
	Egg `i` (of the timeline `tl`) at `t`: its entrance (it rises into its
	place from below, from 0.3 of its size, past it, back: Back, a half turn
	settling), the float (a slow bob and a slow turn, calming as the charge
	grows), the charge (it pulses twice a second, a shake growing with it),
	a tremble growing with the cracks, the pulse of each crack step, the
	suspense (a harder, faster shake and a swell for the `special` egg; the
	cracks whiten on every egg), the silhouette (swelling a little), the
	burst (gone). Reduce motion: still; it fades in and out.
]]
function HatchFx.eggPose(t: number, tl: Timeline, i: number, special: boolean): EggPose
	local times = tl.Times
	local start = (i - 1) * tl.Stagger
	local level = HatchFx.levelAt(t, tl)
	local charge = HatchFx.chargeAt(t, tl)
	if t < start or t >= tl.Burst then
		return {
			Shown = false,
			Scale = 1,
			Roll = 0,
			Yaw = 0,
			Drop = 0,
			Fade = 1,
			Level = level,
			Bright = 0,
			Silhouette = 0,
			Charge = charge,
		}
	end
	if tl.Reduced then
		local fadeIn = 1 - clamp01((t - start) / times.Pop)
		local fadeOut = clamp01((t - tl.Silhouette) / times.Silhouette)
		return {
			Shown = true,
			Scale = 1,
			Roll = 0,
			Yaw = 0,
			Drop = 0,
			Fade = math.max(fadeIn, fadeOut),
			Level = level,
			Bright = 0,
			Silhouette = 0,
			Charge = charge,
		}
	end
	local u = t - start
	local side = if i % 2 == 0 then -1 else 1
	-- the entrance: up from below, growing (Back), a half turn settling
	local e = u / times.Pop
	local scale = if e < 1 then 0.3 + 0.7 * HatchFx.back(e) else 1
	local drop = HatchFx.Rise * (1 - easeOut(e))
	local yaw = side * math.pi * 0.6 * (1 - easeOut(e))
	-- the float: a slow bob and a slow turn (they calm while the energy grows)
	local floating = clamp01((t - tl.Float) / 0.25) * (1 - 0.7 * charge)
	drop += HatchFx.Bob * math.sin((t - start) * 2 * math.pi * 0.7 + i * 0.9) * floating
	yaw += HatchFx.FloatTurn * math.sin((t - start) * 2 * math.pi * 0.22 + i * 1.1) * floating
	-- the charge: a pulse twice a second (its size only: never a flicker) and a shake growing with it
	local roll = 0
	if charge > 0 and t < tl.Silhouette then
		scale *= 1 + 0.035 * charge * (0.5 + 0.5 * math.sin((t - tl.Charge) * 2 * math.pi * 2))
		roll += 0.05 * charge * charge * math.sin(t * 2 * math.pi * 13 + i * 2.1)
	end
	-- the tremble of the cracks (grows with each step)
	if level > 0 then
		roll += (0.025 + 0.018 * level) * math.sin(t * 2 * math.pi * 9 + i * 1.3)
	end
	local suspense = HatchFx.suspenseAt(t, tl)
	if suspense > 0 and t < tl.Silhouette then
		local hard = if special then 1 else 0.45
		roll += hard * (0.05 + 0.06 * suspense) * math.sin(t * 2 * math.pi * 16 + i)
		if special then
			scale *= 1 + 0.08 * suspense
		end
	end
	scale *= 1 + 0.06 * HatchFx.pulseAt(t, tl)
	local silhouette = clamp01((t - tl.Silhouette) / math.max(0.01, times.Silhouette * 0.6))
	if t >= tl.Silhouette then
		scale *= 1 + 0.12 * clamp01((t - tl.Silhouette) / math.max(0.01, times.Silhouette))
		roll *= 0.3
	end
	local bright = if suspense > 0 then suspense else 0
	return {
		Shown = true,
		Scale = scale,
		Roll = roll,
		Yaw = yaw,
		Drop = drop,
		Fade = 0,
		Level = level,
		Bright = bright,
		Silhouette = silhouette,
		Charge = charge,
	}
end

--[[
	The glowing platform under egg `i` at `t`: its strength (0 none .. 1)
	and its size against its place's: it grows in with its egg, glows
	brighter with the charge, flares at the burst and goes (Reduce motion:
	it fades in and out, still).
]]
function HatchFx.platformAt(t: number, tl: Timeline, i: number): (number, number)
	local start = (i - 1) * tl.Stagger
	if t < start then
		return 0, 1
	end
	local inK = clamp01((t - start) / tl.Times.Pop)
	local strength = 0.55 + 0.45 * HatchFx.chargeAt(t, tl)
	local size = if tl.Reduced then 1 else 0.4 + 0.6 * easeOut(inK)
	if t >= tl.Burst then
		local k = clamp01((t - tl.Burst) / 0.35)
		return (1 - k) * strength, size * (1 + (if tl.Reduced then 0 else 0.45 * easeOut(k)))
	end
	return inK * strength, size
end

--[[
	Energy ring `j` (1, 2) orbiting egg `i` at `t`: its strength (0..1), its
	turn (degrees: the rings go opposite ways, faster and faster) and its
	size against the egg's height. In with the charge, brighter toward the
	burst; at the burst it flies apart and fades. Reduce motion: none.
]]
function HatchFx.orbitAt(t: number, tl: Timeline, i: number, j: number): (number, number, number)
	if tl.Reduced or t < tl.Charge then
		return 0, 0, 1
	end
	local u = t - tl.Charge
	local dir = if j % 2 == 1 then 1 else -1
	local turn = dir * (110 * u + 150 * u * u) + i * 47 + j * 90
	local size = if j % 2 == 1 then 0.98 else 1.16 -- (egg heights: close round it, the eggs of an Open 3 overlap)
	if t >= tl.Burst then
		local k = clamp01((t - tl.Burst) / 0.3)
		return 1 - k, turn, size * (1 + 1.1 * easeOut(k))
	end
	local charge = HatchFx.chargeAt(t, tl)
	return clamp01(u / 0.3) * (0.45 + 0.55 * charge), turn, size * (1 - 0.08 * charge)
end

--[[
	Mote `k` of `count` round egg `i` at `t`: shown, where (x, y: egg heights
	from its middle, y down), its size against the egg's height and its
	strength. Floating: a few rise slowly round the egg; charging: they
	stream into it (each comes back out at its edge and in again), brighter
	and quicker as the charge grows; gone at the burst. Reduce motion: none.
]]
function HatchFx.moteAt(t: number, tl: Timeline, i: number, k: number, count: number): (boolean, number, number, number, number)
	if tl.Reduced or t < tl.Float or t >= tl.Burst then
		return false, 0, 0, 0, 0
	end
	local seed = i * 7.31 + k * 2.399
	local angle = seed % (2 * math.pi)
	if t < tl.Charge then
		-- (rising slowly round the egg, a little to and fro)
		local p = ((t - tl.Float) * 0.45 + k / math.max(1, count)) % 1
		local x = math.cos(angle) * 0.62 + 0.05 * math.sin((t + seed) * 3)
		local y = 0.45 - p * 0.95
		return true, x, y, 0.035, math.sin(p * math.pi) * 0.5
	end
	local charge = HatchFx.chargeAt(t, tl)
	local p = ((t - tl.Charge) * (0.9 + 1.4 * charge) + k / math.max(1, count)) % 1
	local reach = 0.95 * (1 - p ^ 1.5) + 0.08
	local a = angle + p * 0.9
	return true, math.cos(a) * reach, math.sin(a) * reach * 0.9, 0.03 + 0.02 * charge, math.sin(p * math.pi) * (0.45 + 0.55 * charge)
end

-- How far a white shockwave ring `j` of an egg is through its flight at `t` (0..1; outside it: none).
-- RevealKit.poseRing draws it (Rings: from RingFrom of the egg's height, growing RingGrow more).
HatchFx.RingFrom = 0.45
HatchFx.RingGrow = 1.25
function HatchFx.ringU(t: number, tl: Timeline, j: number): number
	local u = t - tl.Rings - (j - 1) * 0.08
	local d = if tl.Fast then 0.3 else 0.45
	return u / d
end

-- The puff at the rings (and at the burst): a soft white glow's size (egg heights) and transparency.
function HatchFx.puffAt(u: number): (number, number)
	if u < 0 or u >= 0.35 then
		return 0, 1
	end
	local k = u / 0.35
	return 0.4 + 0.6 * (1 - (1 - k) ^ 2), 0.62 + 0.38 * k
end

export type GolemPose = {
	Shown: boolean,
	Scale: number, -- against its place's (the pop: Back)
	Lift: number, -- the bob (a share of its height)
	Spin: number, -- radians round its upright (the flight)
	Fly: number, -- 0..1 of the flight (toward the player, shrinking)
	Fade: number, -- 0 seen .. 1 gone (Reduce motion's fades)
	Name: number, -- the name's transparency (1: hidden)
}

--[[
	Golem `i` at `t`: it pops where its egg was (a quick ripple across the
	batch), bobs gently, then spins and flies to the player (Fly 0..1, the
	controller moves it there and shrinks it). Reduce motion: it fades in,
	stays still, fades out.
]]
function HatchFx.golemPose(t: number, tl: Timeline, i: number): GolemPose
	local times = tl.Times
	local at = tl.Reveal + (if tl.Reduced then 0 else (i - 1) * HatchFx.GolemRipple)
	if t < at or t >= tl.Total then
		return { Shown = false, Scale = 1, Lift = 0, Spin = 0, Fly = 0, Fade = 1, Name = 1 }
	end
	local u = t - at
	if tl.Reduced then
		local fade = math.max(1 - clamp01(u / tl.GolemPop), clamp01((t - tl.Fly) / times.Fly))
		return { Shown = true, Scale = 1, Lift = 0, Spin = 0, Fly = 0, Fade = fade, Name = fade }
	end
	-- (0.3 of its size, past it, back: Back; a Legendary / Mythic's slower: the slow motion)
	local scale = if u < tl.GolemPop then 0.3 + 0.7 * HatchFx.back(u / tl.GolemPop) else 1
	local lift = 0.025 * math.sin(math.max(0, u - tl.GolemPop) * 2 * math.pi * 0.9)
	local fly = clamp01((t - tl.Fly) / times.Fly)
	local spin = 0
	if fly > 0 then
		spin = fly * fly * math.pi * 4 -- (two turns, speeding up)
		lift = 0
	end
	local name = if fly > 0 then clamp01(fly * 4) else clamp01(1 - (u - (HatchFx.NameIn - 0.1)) / 0.1)
	return { Shown = true, Scale = scale, Lift = lift, Spin = spin, Fly = fly, Fade = 0, Name = name }
end

--[[
	A golem on its flight (`k` 0..1) from its place (screen share `from`,
	depth `z`) to the player (`to`, a screen share): its screen point and
	depth (further: smaller; four times as far at the end), speeding up.
]]
function HatchFx.flyTo(from: Vector2, z: number, to: Vector2, k: number): (Vector2, number)
	local e = k * k
	return from:Lerp(to, e), z * (1 + 3 * e)
end

---------------------------------------------------------------- the light behind

-- The sunburst's strength (0..1) at `t`: in at the reveal, settling to a soft glow, out with the flight.
function HatchFx.sunburstAt(t: number, tl: Timeline): number
	if t < tl.Reveal then
		return 0
	end
	local inK = clamp01((t - tl.Reveal) / 0.12)
	local settle = 1 - 0.35 * clamp01((t - tl.Reveal - 0.2) / 0.6)
	local out = 1 - clamp01((t - tl.Fly) / (tl.Times.Fly * 0.7))
	return inK * settle * out
end

-- The soft blobs behind the eggs (0..1): from the first crack to the reveal.
function HatchFx.blobsAt(t: number, tl: Timeline): number
	local from = tl.Steps[1]
	if t < from then
		return 0
	end
	local inK = clamp01((t - from) / 0.4)
	local out = 1 - clamp01((t - tl.Reveal) / 0.4)
	return inK * out * (0.75 + 0.25 * HatchFx.suspenseAt(t, tl))
end

-- How far the flash is through its fade `u` seconds after the burst (RevealKit.poseFlash's f: 0..1; outside: none).
function HatchFx.flashU(u: number): number
	return u / HatchFx.FlashTime
end

-- The burst's flash at its strongest for the batch's best rarity (its Tier's; never over FlashPeak).
function HatchFx.flashPeakOf(tl: Timeline): number
	return math.min(HatchFx.FlashPeak, tl.Tier.Flash)
end

--[[
	The glow of slot `i` at `t` (0..1): behind its egg while it charges
	(growing with it), then the aura behind its golem (the Tier's, breathing
	gently: slower than once a second), gone with the flight. Reduce motion:
	it fades with the stage, still.
]]
function HatchFx.auraAt(t: number, tl: Timeline, i: number): number
	if t < tl.Charge then
		return 0
	end
	if t < tl.Reveal then
		local glow = 0.25 + 0.6 * HatchFx.chargeAt(t, tl)
		return if t >= tl.Burst then glow * (1 - clamp01((t - tl.Burst) / 0.1)) else glow
	end
	local at = tl.Reveal + (if tl.Reduced then 0 else (i - 1) * HatchFx.GolemRipple)
	local inK = clamp01((t - at) / 0.25)
	local out = 1 - clamp01((t - tl.Fly) / (tl.Times.Fly * 0.6))
	local breathe = if tl.Reduced then 1 else 0.86 + 0.14 * math.sin((t - at) * 2 * math.pi * 0.6)
	return tl.Tier.Aura * inK * out * breathe
end

--[[
	The rarity's energy pulses at the reveal (Tier.Pulses rings out of the
	best golem): how far ring `j` is through its flight at `t` (0..1;
	outside: none). Reduce motion: none.
]]
function HatchFx.pulseU(t: number, tl: Timeline, j: number): number
	if tl.Reduced or j > tl.Tier.Pulses then
		return -1
	end
	return (t - tl.Reveal - (j - 1) * 0.14) / (if tl.Fast then 0.4 else 0.6)
end

--[[
	The big word of a Legendary / Mythic (Tier.Banner) at `t`: its scale (it
	slams in from big: Back) and its transparency (1: hidden); out with the
	flight. Reduce motion: it fades in at its size.
]]
function HatchFx.bannerAt(t: number, tl: Timeline): (number, number)
	if t < tl.Banner or t >= tl.Total then
		return 1, 1
	end
	local u = t - tl.Banner
	local out = clamp01((t - tl.Fly) / (tl.Times.Fly * 0.6))
	if tl.Reduced then
		return 1, math.max(1 - clamp01(u / 0.25), out)
	end
	local slam = 0.32
	local scale = if u < slam then 2.1 - 1.1 * HatchFx.back(u / slam) else 1
	return scale, math.max(1 - clamp01(u / 0.12), out)
end

-- The stage's light lift (0..1) of a Mythic (Tier.Light) at `t`: up at the burst, down with the flight.
function HatchFx.lightAt(t: number, tl: Timeline): number
	if tl.Tier.Light <= 0 or t < tl.Burst then
		return 0
	end
	return tl.Tier.Light * clamp01((t - tl.Burst) / 0.3) * (1 - clamp01((t - tl.Fly) / tl.Times.Fly))
end

--[[
	A golem's rarity pill ("RARE") and its bonus ("+10% Income") over its
	head: the bonus's words (`labels`: GolemConfig.BonusTypes; nil: none).
]]
function HatchFx.bonusText(bonusType: string, value: number, labels: { [string]: { Stat: string, Label: string } }): string?
	local kind = labels[bonusType]
	if not kind or type(value) ~= "number" or value ~= value or value <= 0 then
		return nil
	end
	local pct = value * 100
	local whole = math.floor(pct + 0.5)
	local text = if math.abs(pct - whole) < 0.05 then tostring(whole) else string.format("%.1f", pct)
	return `+{text}% {kind.Label}`
end

---------------------------------------------------------------- colours

--[[
	A crack's colour for a golem of `rarity` (BrightTheme.crackColour: white
	for Common, the rarity's colour above it) at `t`; Mythic a rainbow that
	moves along the cracks (`along`: the segment's place, 0..1). `bright`
	whitens it (the suspense).
]]
function HatchFx.crackColor(rarity: string, t: number, along: number, bright: number): Color3
	local color
	if rarity == "Mythic" then
		color = Color3.fromHSV((t * 0.55 + along * 0.6) % 1, 0.72, 1)
	else
		color = BrightTheme.crackColour(rarity)
	end
	if bright > 0 then
		-- (a steady whitening over the suspense: no pulse, never a flicker)
		color = color:Lerp(Color3.new(1, 1, 1), (if rarity == "Mythic" then 0.2 else 0.4) * bright)
	end
	return color
end

---------------------------------------------------------------- the egg

--[[
	The crack network on an egg's front (studs, the egg's own frame: the
	premium egg's shape, CapsuleEggs: a sphere of radius R round the
	middle, an ellipsoid 2.8 R tall above it 0.4 R up; its front -Z): each
	crack a zig-zag line, Level 1 the first two, 2 two more, 3 the
	branches. Every point is on the front, round the emblem.
]]
HatchFx.Cracks = {
	{ Level = 1, Points = { { 0.02, 2.05 }, { -0.16, 1.78 }, { 0.08, 1.56 }, { -0.42, 1.36 }, { -0.62, 1.0 }, { -0.5, 0.62 } } },
	{ Level = 1, Points = { { 0.12, 0.34 }, { -0.18, 0.12 }, { 0.1, -0.2 }, { -0.16, -0.5 }, { 0.04, -0.82 } } },
	{ Level = 2, Points = { { 0.08, 1.56 }, { 0.46, 1.42 }, { 0.6, 1.08 }, { 0.84, 0.86 } } },
	{ Level = 2, Points = { { -0.5, 0.62 }, { -0.2, 0.42 }, { 0.12, 0.34 }, { 0.5, 0.42 }, { 0.78, 0.2 } } },
	{ Level = 3, Points = { { -0.18, 0.12 }, { -0.56, 0.0 }, { -0.82, -0.3 } } },
	{ Level = 3, Points = { { 0.1, -0.2 }, { 0.46, -0.36 }, { 0.62, -0.68 } } },
	{ Level = 3, Points = { { -0.16, 1.78 }, { -0.46, 1.86 }, { -0.62, 1.64 } } },
	{ Level = 3, Points = { { 0.6, 1.08 }, { 0.42, 0.76 } } },
} :: { { Level: number, Points: { { number } } } }

HatchFx.CrackWidth = { 0.07, 0.1, 0.14 } -- studs, at each step (every lit crack thickens)
HatchFx.CrackDepth = 0.035 -- studs (flat on the shell)
HatchFx.CrackLift = 0.05 -- studs over the shell (over the band and the scales)

local EGG_R = 1.25 -- CapsuleEggs.Radius

-- The front surface of the premium egg at (x, y): its point and its outward normal.
function HatchFx.eggFront(x: number, y: number): (Vector3, Vector3)
	local r = EGG_R
	local zs = r * r - x * x - y * y
	local cy = 0.4 * r
	local ry = 1.4 * r
	local ye = (y - cy) / ry
	local ze = r * r * (1 - ye * ye) - x * x
	local sphere = if zs > 0 then math.sqrt(zs) else -1
	local ellipsoid = if ze > 0 then math.sqrt(ze) else -1
	if sphere >= ellipsoid and sphere > 0 then
		local p = Vector3.new(x, y, -sphere)
		return p, p.Unit
	elseif ellipsoid > 0 then
		local p = Vector3.new(x, y, -ellipsoid)
		return p, Vector3.new(x / (r * r), (y - cy) / (ry * ry), -ellipsoid / (r * r)).Unit
	end
	return Vector3.new(x, y, 0), Vector3.new(0, 0, -1)
end

export type CrackPart = { Part: BasePart, Level: number, Length: number, Along: number }

export type Record = {
	Model: Model,
	Parts: { BasePart },
	Colors: { Color3 },
	Materials: { Enum.Material },
	Trans: { number },
	Cracks: { CrackPart },
	Mid: number, -- its visual middle over its pivot (studs)
	Height: number, -- top to bottom (studs)
	Foot: number, -- its lowest point under the pivot (studs, negative)
	Lit: number, -- the crack level shown now
	Tint: Color3?, -- the silhouette's colour now (nil: as built)
	Faded: number, -- the transparency added now (Reduce motion's fades)
}

--[[
	Adds the crack network (Cracks) to an egg built round the origin
	(GolemBuilder.capsule with no base), hidden: thin Neon parts on its
	front shell, `maxLevel` the last step built (phones with many eggs: 2).
]]
function HatchFx.addCracks(model: Model, maxLevel: number?)
	local folder = Instance.new("Model")
	folder.Name = "HatchCracks"
	local top = maxLevel or 3
	local total = 0
	for _, crack in HatchFx.Cracks do
		total += #crack.Points - 1
	end
	local index = 0
	for c, crack in HatchFx.Cracks do
		if crack.Level > top then
			continue
		end
		for j = 1, #crack.Points - 1 do
			index += 1
			local a, na = HatchFx.eggFront(crack.Points[j][1], crack.Points[j][2])
			local b, nb = HatchFx.eggFront(crack.Points[j + 1][1], crack.Points[j + 1][2])
			local normal = (na + nb).Unit
			local mid = (a + b) / 2 + normal * HatchFx.CrackLift
			local along = b - a
			local length = along.Magnitude + 0.06
			local yAxis = (along - normal * along:Dot(normal)).Unit
			local xAxis = yAxis:Cross(normal).Unit
			local part = Instance.new("Part")
			part.Name = `Crack{c}_{j}`
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			part.Color = Color3.new(1, 1, 1)
			part.Transparency = 1
			part.Size = Vector3.new(HatchFx.CrackWidth[1], length, HatchFx.CrackDepth)
			part.CFrame = CFrame.fromMatrix(mid, xAxis, yAxis, normal)
			part:SetAttribute("CrackLevel", crack.Level)
			part:SetAttribute("CrackAlong", index / math.max(1, total))
			part.Parent = folder
		end
	end
	folder.Parent = model
end

--[[
	Records an egg as built (its parts' colours, materials and transparency
	to put back, its cracks, its size round its pivot). The model's pivot is
	its middle (GolemBuilder.capsule's Root).
]]
function HatchFx.record(model: Model): Record
	local pivot = model:GetPivot()
	local rec: Record = {
		Model = model,
		Parts = {},
		Colors = {},
		Materials = {},
		Trans = {},
		Cracks = {},
		Mid = 0.8,
		Height = 4.4,
		Foot = -1.3,
		Lit = 0,
		Tint = nil,
		Faded = 0,
	}
	local low, high = math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(rec.Parts, d)
			table.insert(rec.Colors, d.Color)
			table.insert(rec.Materials, d.Material)
			table.insert(rec.Trans, d.Transparency)
			local level = d:GetAttribute("CrackLevel")
			if type(level) == "number" then
				local along = d:GetAttribute("CrackAlong")
				table.insert(rec.Cracks, {
					Part = d,
					Level = level,
					Length = d.Size.Y,
					Along = if type(along) == "number" then along else 0,
				})
			elseif d.Transparency < 1 then
				local y = pivot:PointToObjectSpace(d.CFrame.Position).Y
				local half = math.max(d.Size.X, d.Size.Y, d.Size.Z) / 2
				low = math.min(low, y - half * 0.7)
				high = math.max(high, y + half * 0.7)
			end
		end
	end
	if low < high then
		rec.Foot = low
		rec.Height = high - low
		rec.Mid = (high + low) / 2
	end
	return rec
end

-- Puts a pooled egg back as it was built (colours, materials, see-through; the cracks hidden).
function HatchFx.reset(rec: Record)
	for i, part in rec.Parts do
		part.Color = rec.Colors[i]
		part.Material = rec.Materials[i]
		part.Transparency = rec.Trans[i]
	end
	for _, crack in rec.Cracks do
		crack.Part.Transparency = 1
	end
	rec.Lit = 0
	rec.Tint = nil
	rec.Faded = 0
end

--[[
	Paints an egg's cracks for `pose` (its lit level, each a step thicker,
	in `rarity`'s colour at `t`) and its silhouette (the whole egg one solid
	glowing colour, Neon: no light on it) and its fade (Reduce motion).
	Writes only what changed.
]]
function HatchFx.paintEgg(rec: Record, pose: EggPose, rarity: string, t: number)
	local level = math.clamp(pose.Level, 0, 3)
	local fadeChanged = pose.Fade ~= rec.Faded
	if fadeChanged then
		for i, part in rec.Parts do
			if rec.Trans[i] < 1 then
				part.Transparency = rec.Trans[i] + (1 - rec.Trans[i]) * pose.Fade
			end
		end
		rec.Faded = pose.Fade
	end
	if level ~= rec.Lit or fadeChanged or rarity == "Mythic" or pose.Bright > 0 then
		local width = HatchFx.CrackWidth[math.max(1, level)]
		for _, crack in rec.Cracks do
			local on = crack.Level <= level
			crack.Part.Transparency = if on then pose.Fade else 1
			if on then
				crack.Part.Color = HatchFx.crackColor(rarity, t, crack.Along, pose.Bright)
			end
			if level ~= rec.Lit then
				crack.Part.Size = Vector3.new(width, crack.Length, HatchFx.CrackDepth)
			end
		end
		rec.Lit = level
	end
	if pose.Silhouette > 0 then
		-- (the whole egg one flat glowing colour: Neon takes no light in a viewport)
		local tint = HatchFx.crackColor(rarity, t, 0.5, 0)
		if rec.Tint ~= tint then
			for i, part in rec.Parts do
				if rec.Trans[i] < 1 then
					part.Color = tint
					part.Material = Enum.Material.Neon
				end
			end
			rec.Tint = tint
		end
	end
end

return HatchFx
