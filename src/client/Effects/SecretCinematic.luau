--[[
	SecretCinematic: the SECRET ore's cinematic reveal (owner 2026-10-30: a premium ~8 s
	"SECRET ORE DISCOVERY": discovery, energy charging, a massive explosion, the reveal),
	the pure part: the timeline (one table: Timing, Sounds, Hum), the layout for any
	screen (layout), the look by the secret's Stars 1..3 (Palettes, Tiers: the same
	structure for all, Rainbow Nova in the whole rainbow), build() and pose(). Nothing
	runs on its own: Effects/SecretOreReveal plays it (one RenderStepped, skip, CONTINUE,
	the sounds, the client-only blur), the Lune previews and specs pose the same frames.

	The show (seconds, Timing; the cleaning's own build-up comes before it,
	Cleaning/SecretCleanFx: light leaking through the dirt, the shaking, three heartbeats):
	  0    Discovery   the world darkens (Dim) and blurs (world(): the runtime's BlurEffect
	                   and ColorCorrection on the camera), a vignette closes in, slow motes
	                   drift up; the ore is a dark silhouette in the middle (its viewport
	                   light low: only its glowing parts shine), a faint glow behind it; the
	                   viewport camera cranes up and pushes in slowly
	  1.5  Charge      3-4 energy rings come in one by one and turn opposite ways, faster and
	                   faster; crystal fragments with glowing trails orbit it, drawn in;
	                   thin radial beams grow behind it; its light grows; the ore turns
	                   faster and trembles at the end
	  3.5  Explosion   the burst: ONE soft flash (RevealKit's gap), shockwave rings (1-3 by
	                   stars), sparks, the beams shoot out, the fragments blow away, the
	                   screen punches in and shakes, the ore fully lit and whirled round
	  5    Reveal      S E C R E T drops in letter by letter (the palette's gradient), its
	                   energy line, the name (gold), the SECRET ★ pill and the chance, the
	                   value, NEW! on a first find, 3 stars: ONE IN A MILLION!; the ore goes
	                   to its place (a short wide screen: left of the words, Side) and keeps
	                   turning; an animated gradient drifts over the dark
	  6.2  ContinueAt  CONTINUE pops in (its bar fills until AutoContinue)
	  6.6  Pulse       a last energy pulse behind the ore (a ring, no flash)
	  8    Settle      everything is in; it idles until CONTINUE or AutoContinue
	  + Close          the ore flies into the bag (Target) or fades, everything fades
	press(): a tap / click / A / Enter between SkipFrom and SkipTo jumps to SkipTo (the
	burst's tail: no flash after it, the name always comes); before ContinueAt nothing
	else; from ContinueAt it continues.
	Reduce motion (opts.Reduced): no flash, shake, punch, spin, sparks, trails or flying
	fragments; words fade in at full size; the ore stays still and fades where it is.
	Phones (opts.Phone): fewer beams, motes, fragments, sparks, shorter trails, less blur.
	Perf: build() makes every piece once (pooled); pose() only sets properties (hidden
	groups are skipped); an ore id's model is built once (setOre keeps the six), a passed
	model is cloned once per show (setModel) and dropped by clear().

	  build() -> View   (Gui = ScreenGui "TerraForgeSecretCinematic", DisplayOrder 46,
	                     IgnoreGuiInset, ResetOnSpawn off, hidden)
	  setOre(view, oreId) / setModel(view, model)   the ore in the middle
	  setInfo(view, info)                            its words (Info) and look (Stars)
	  pose(view, t, opts) -> done                    one frame t seconds in (Opts)
	  clear(view)                                    after a show: the passed model goes
	  world(t, opts) -> World                        the blur / colour grade behind it
	  layout(screen, topInset, cosmos) -> Layout     where and how big (Stack or Side)
	  press(t, timing) -> (t, continue)              what a press does
	  timing(overrides) / cues(timing, stars) / hum(t, timing)
	  boomFlash(now, reduced) / retryBoomFlash(since, now, timing)   the burst's one flash
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local OreData = require(Config:WaitForChild("OreData"))
local PopTheme = require(Config:WaitForChild("PopTheme"))
local SecretOreConfig = require(Config:WaitForChild("SecretOreConfig"))
local Builders = Shared:WaitForChild("Builders")
local ItemBuilder = require(Builders:WaitForChild("ItemBuilder"))
local SecretOreFx = require(Builders:WaitForChild("SecretOreFx"))
local UIKit = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIKit"))
local RevealKit = require(script.Parent:WaitForChild("RevealKit"))

local SecretCinematic = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------- the timeline (one table)

export type Timing = {
	Discovery: number,
	Charge: number,
	Explosion: number,
	Reveal: number,
	Pulse: number,
	Settle: number,
	SkipFrom: number,
	SkipTo: number,
	ContinueAt: number,
	AutoContinue: number,
	Close: number,
	FlashWindow: number,
}

SecretCinematic.Timing = {
	Discovery = 0, -- phase 1: the dark, the blur, the silhouette, the motes, the camera's push in
	Charge = 1.5, -- phase 2: rings, beams, fragments, the light growing
	Explosion = 3.5, -- phase 3: the burst
	Reveal = 5.0, -- phase 4: SECRET, the name, rarity, chance, value
	Pulse = 6.6, -- the last energy pulse behind the ore
	Settle = 8.0, -- every entrance done: it idles until CONTINUE
	SkipFrom = 0.5, -- a press skips ahead from here (the cleaning's last tap never does)
	SkipTo = 4.4, -- where a skip lands: the burst's tail (past its flash), the reveal right after
	ContinueAt = 6.2, -- CONTINUE shows and takes presses from here
	AutoContinue = 14, -- it continues on its own here: nobody gets stuck
	Close = 0.75, -- seconds from CONTINUE: the ore into the bag, everything fades, the world back
	FlashWindow = 0.8, -- a flash refused at the burst may still come this long after it, never later
} :: Timing

-- Its phases in order (the Timing keys a cue can start from).
SecretCinematic.Phases = { "Discovery", "Charge", "Explosion", "Reveal" }

-- A copy of Timing with `overrides` (numbers >= 0 for known keys only) applied.
function SecretCinematic.timing(overrides: { [string]: any }?): Timing
	local out = table.clone(SecretCinematic.Timing)
	if overrides then
		local loose: any = out
		for key, value in overrides do
			if type(key) == "string" and loose[key] ~= nil and type(value) == "number" and value == value and value < math.huge then
				loose[key] = math.max(0, value)
			end
		end
	end
	return out
end

-- The phase `t` seconds in ("Discovery" | "Charge" | "Explosion" | "Reveal").
function SecretCinematic.phase(t: number, timing: Timing?): string
	local tm = timing or SecretCinematic.Timing
	if t < tm.Charge then
		return "Discovery"
	elseif t < tm.Explosion then
		return "Charge"
	elseif t < tm.Reveal then
		return "Explosion"
	end
	return "Reveal"
end

-- What a press does `t` seconds in: a skip (the new t), CONTINUE (true), or nothing (t, false).
function SecretCinematic.press(t: number, timing: Timing?): (number, boolean)
	local tm = timing or SecretCinematic.Timing
	if t >= tm.SkipFrom and t < tm.SkipTo then
		return tm.SkipTo, false
	end
	if t >= tm.ContinueAt then
		return t, true
	end
	return t, false
end

---------------------------------------------------------------- sounds (SoundConfig names, Sfx)

export type Cue = { At: number, Sound: string, OnSkip: boolean }

-- Each starts `After` seconds into its phase (Timing key; clamped inside it), Stars = from how many
-- stars. OnSkip: a skip that jumps over it still plays it once (the burst's boom: the jump lands).
SecretCinematic.Sounds = {
	{ Phase = "Discovery", After = 0.05, Sound = "SecretMystery" },
	{ Phase = "Charge", After = 0, Sound = "SecretRise" },
	{ Phase = "Charge", After = 0.6, Sound = "SecretSparkle" },
	{ Phase = "Charge", After = 1.1, Sound = "SecretSparkle" },
	{ Phase = "Charge", After = 1.45, Sound = "SecretSparkle" },
	{ Phase = "Charge", After = 1.7, Sound = "SecretThump" },
	{ Phase = "Explosion", After = 0, Sound = "SecretBoom", OnSkip = true },
	{ Phase = "Explosion", After = 0, Sound = "SecretChime" },
	{ Phase = "Explosion", After = 0.2, Sound = "SecretSparkle" },
	{ Phase = "Explosion", After = 0.4, Sound = "SecretSparkle", Stars = 2 },
	{ Phase = "Explosion", After = 0.8, Sound = "SecretSparkle", Stars = 3 },
	{ Phase = "Reveal", After = 0, Sound = "SecretFanfare" },
	{ Phase = "Reveal", After = 0.12, Sound = "SecretThump" },
	{ Phase = "Pulse", After = 0, Sound = "SecretChime" },
} :: { { Phase: string, After: number, Sound: string, OnSkip: boolean?, Stars: number? } }

-- The charging hum (SoundConfig SecretHum, one looping voice): from From until the burst, louder
-- and higher the more it charges.
SecretCinematic.Hum = { From = 0.2, Volume = { 0.12, 0.4 }, Speed = { 0.5, 1.45 } }

local function phaseEnd(tm: Timing, phase: string): number
	if phase == "Discovery" then
		return tm.Charge
	elseif phase == "Charge" then
		return tm.Explosion
	elseif phase == "Explosion" then
		return tm.Reveal
	end
	return math.huge
end

-- The show's sounds for a `stars` secret, in order of At (seconds into the show).
function SecretCinematic.cues(timing: Timing?, stars: number?): { Cue }
	local tm = timing or SecretCinematic.Timing
	local out: { Cue } = {}
	for _, cue in SecretCinematic.Sounds do
		local start = (tm :: any)[cue.Phase]
		if type(start) == "number" and (stars or 1) >= (cue.Stars or 1) then
			local at = math.min(start + cue.After, phaseEnd(tm, cue.Phase) - 0.01)
			table.insert(out, { At = math.max(at, start), Sound = cue.Sound, OnSkip = cue.OnSkip == true })
		end
	end
	table.sort(out, function(a, b)
		return a.At < b.At
	end)
	return out
end

local function span(t: number, a: number, b: number): number
	if b <= a then
		return if t >= b then 1 else 0
	end
	return math.clamp((t - a) / (b - a), 0, 1)
end

-- The hum `t` seconds in: (volume, playback speed); volume 0 = off.
function SecretCinematic.hum(t: number, timing: Timing?): (number, number)
	local tm = timing or SecretCinematic.Timing
	local hum = SecretCinematic.Hum
	if t < hum.From or t >= tm.Explosion then
		return 0, hum.Speed[1]
	end
	local u = span(t, tm.Charge, tm.Explosion) ^ 1.6
	local into = span(t, hum.From, tm.Charge)
	local volume = hum.Volume[1] * into + (hum.Volume[2] - hum.Volume[1]) * u
	return volume, hum.Speed[1] + (hum.Speed[2] - hum.Speed[1]) * u
end

---------------------------------------------------------------- the burst's one flash (RevealKit's gap)

-- The burst's flash at clock `now`: 0 (at the burst) if it may flash now; else math.huge and the
-- clock to try once more (a flash too soon after another: it plays then, where the show is).
-- Reduce motion: none, no slot taken.
function SecretCinematic.boomFlash(now: number, reduced: boolean): (number, number?)
	if reduced then
		return math.huge, nil
	end
	if RevealKit.takeFlash(now) then
		return 0, nil
	end
	return math.huge, RevealKit.nextFlashAt()
end

-- The flash that waited, `since` seconds after the burst, at clock `now`: `since` if it may flash
-- now; nil when the slot is taken again or it is FlashWindow late (a hitch, a skip), and then it
-- takes no slot.
function SecretCinematic.retryBoomFlash(since: number, now: number, timing: Timing?): number?
	local tm = timing or SecretCinematic.Timing
	if since < tm.FlashWindow and RevealKit.takeFlash(now) then
		return since
	end
	return nil
end

---------------------------------------------------------------- the look by stars

export type Palette = { Deep: Color3, A: Color3, B: Color3, Light: Color3, Rainbow: boolean }

SecretCinematic.Palettes = {
	-- 1 star: violet and ice
	{ Deep = rgb(10, 8, 26), A = rgb(168, 96, 255), B = rgb(72, 200, 255), Light = rgb(222, 198, 255), Rainbow = false },
	-- 2 stars: magenta and gold
	{ Deep = rgb(22, 8, 22), A = rgb(255, 84, 196), B = rgb(255, 204, 72), Light = rgb(255, 204, 236), Rainbow = false },
	-- 3 stars (Rainbow Nova): the whole rainbow, gold words
	{ Deep = rgb(8, 6, 20), A = rgb(255, 110, 226), B = rgb(80, 220, 255), Light = rgb(255, 234, 160), Rainbow = true },
} :: { Palette }

export type Tier = {
	Rings: number, -- energy rings
	Shocks: { number }, -- seconds after the burst each shockwave starts
	Sparks: number,
	Fragments: number,
	Motes: number,
	Shake: number, -- the world camera's kick at the burst (CameraShake, 0..1)
	Cosmos: boolean, -- the ONE IN A MILLION! ribbon
}

SecretCinematic.Tiers = {
	{ Rings = 3, Shocks = { 0 }, Sparks = 24, Fragments = 8, Motes = 22, Shake = 0.5, Cosmos = false },
	{ Rings = 4, Shocks = { 0, 0.4 }, Sparks = 30, Fragments = 10, Motes = 28, Shake = 0.7, Cosmos = false },
	{ Rings = 4, Shocks = { 0, 0.4, 0.8 }, Sparks = 36, Fragments = 12, Motes = 34, Shake = 0.9, Cosmos = true },
} :: { Tier }

-- A phone: fewer pieces (Bars: radial beams through the middle, two rays each; Trail: ghosts a fragment).
SecretCinematic.Phone = { Bars = 8, Fans = 4, Sparks = 16, Fragments = 6, Motes = 14, Trail = 2, Blur = 0.6 }
SecretCinematic.Full = { Bars = 12, Fans = 6, Trail = 3 }

SecretCinematic.FlashPeak = 0.72 -- softer than RevealKit's (and never past it)
SecretCinematic.GlowDiscs = 7 -- the soft glow's discs (a phone: GlowPhone)
SecretCinematic.GlowPhone = 5
SecretCinematic.GlowSize = 620 -- design units: the glow's widest
SecretCinematic.Blur = { Discovery = 12, Charge = 16, Peak = 23, Reveal = 10 } -- BlurEffect.Size
SecretCinematic.RayLength = 900 -- design units, end to end through the middle
SecretCinematic.OreSize = 300 -- design units: the ore's viewport
SecretCinematic.Fov = 30
SecretCinematic.Hints = { Touch = "Tap to skip", Gamepad = "Press A to skip", Mouse = "Click to skip" }
SecretCinematic.Gold = { rgb(255, 246, 196), rgb(255, 204, 72), rgb(255, 160, 40) }

function SecretCinematic.tierOf(stars: number?): Tier
	return SecretCinematic.Tiers[math.clamp(math.floor(stars or 1), 1, #SecretCinematic.Tiers)]
end

function SecretCinematic.paletteOf(stars: number?): Palette
	return SecretCinematic.Palettes[math.clamp(math.floor(stars or 1), 1, #SecretCinematic.Palettes)]
end

---------------------------------------------------------------- layout (any screen)

export type Mode = {
	Up: number, -- design units the show reaches above its middle (3 stars: UpCosmos, the ribbon)
	UpCosmos: number,
	Down: number, -- and below it (CONTINUE)
	Half: number, -- and to each side
	OreAt: Vector2, -- the ore's place in the reveal (before it: the middle)
	TextScale: number, -- the words' size
	Ribbon: Vector2,
	Title: Vector2,
	Name: Vector2,
	Row: Vector2,
	Value: Vector2,
	Button: Vector2,
	New: Vector2, -- NEW! (next to the ore)
}

SecretCinematic.Layouts = {
	-- everything in one column: the title over the ore, the words and CONTINUE under it
	Stack = {
		Up = 300,
		UpCosmos = 344,
		Down = 390,
		Half = 330,
		OreAt = Vector2.zero,
		TextScale = 1,
		Ribbon = Vector2.new(0, -322),
		Title = Vector2.new(0, -238),
		Name = Vector2.new(0, 184),
		Row = Vector2.new(0, 236),
		Value = Vector2.new(0, 282),
		Button = Vector2.new(0, 354),
		New = Vector2.new(128, -112),
	},
	-- a short wide screen (a landscape phone): the ore on the left, the words on the right
	Side = {
		Up = 176,
		UpCosmos = 198,
		Down = 162,
		Half = 380,
		OreAt = Vector2.new(-190, 0),
		TextScale = 0.78,
		Ribbon = Vector2.new(175, -178),
		Title = Vector2.new(175, -124),
		Name = Vector2.new(175, -56),
		Row = Vector2.new(175, -6),
		Value = Vector2.new(175, 38),
		Button = Vector2.new(175, 116),
		New = Vector2.new(-82, -112),
	},
} :: { [string]: Mode }

SecretCinematic.MaxScale = 1.25 -- the HUD's biggest
SecretCinematic.StackMin = 0.8 -- the column below this on a wide screen: Side
SecretCinematic.Margin = 10 -- px kept free at the bottom
SecretCinematic.Gutter = 12 -- px kept free at each side
SecretCinematic.ButtonSize = Vector2.new(280, 66) -- design units
SecretCinematic.MinTouch = 44 -- pt: CONTINUE's height on a touch screen, at least

export type Layout = { Mode: string, Scale: number, Center: Vector2 }

-- Where the show's middle goes (px from the screen's top left; the gui ignores the inset) and its
-- scale: one column (Stack) when it is big enough or the screen is not wide, else Side.
function SecretCinematic.layout(screen: Vector2, topInset: number?, cosmos: boolean?): Layout
	local top = math.max(topInset or 36, 0)
	local free = math.max(screen.Y - top - SecretCinematic.Margin, 1)
	local function fit(mode: Mode): (number, Vector2)
		local up = if cosmos then mode.UpCosmos else mode.Up
		local scale = math.min(free / (up + mode.Down), (screen.X - 2 * SecretCinematic.Gutter) / (2 * mode.Half), SecretCinematic.MaxScale)
		scale = math.max(scale, 0.2)
		local y = top + (free - (up + mode.Down) * scale) / 2 + up * scale
		return scale, Vector2.new(screen.X / 2, y)
	end
	local stackScale, stackAt = fit(SecretCinematic.Layouts.Stack)
	if stackScale >= SecretCinematic.StackMin or screen.X < screen.Y * 1.3 then
		return { Mode = "Stack", Scale = stackScale, Center = stackAt }
	end
	local sideScale, sideAt = fit(SecretCinematic.Layouts.Side)
	if sideScale > stackScale then
		return { Mode = "Side", Scale = sideScale, Center = sideAt }
	end
	return { Mode = "Stack", Scale = stackScale, Center = stackAt }
end

-- CONTINUE's own extra scale: on a touch screen never under MinTouch pt tall.
function SecretCinematic.buttonScale(layout: Layout, touch: boolean?): number
	if not touch then
		return 1
	end
	local mode = SecretCinematic.Layouts[layout.Mode]
	local tall = SecretCinematic.ButtonSize.Y * layout.Scale * mode.TextScale
	return math.max(1, SecretCinematic.MinTouch / math.max(tall, 1e-3))
end

---------------------------------------------------------------- the world behind it (client-only post effects)

export type World = { Blur: number, Brightness: number, Contrast: number, Saturation: number, Tint: Color3 }

export type Opts = {
	Screen: Vector2,
	TopInset: number?, -- px the top bar covers (default 36)
	Reduced: boolean?,
	Phone: boolean?, -- fewer pieces
	Touch: boolean?, -- CONTINUE at least MinTouch tall
	Input: string?, -- "Touch" | "Gamepad" | "Mouse": the skip hint, CONTINUE's key chip
	FlashAt: number?, -- the show's second its flash starts (default Explosion; math.huge: none)
	ContinuedAt: number?, -- the second CONTINUE was pressed (nil: not yet)
	Target: Vector2?, -- px: where the ore flies at the close (nil: it fades where it is)
	Timing: Timing?,
}

local function easeOut(x: number): number
	return 1 - (1 - x) ^ 3
end

local function easeInOut(x: number): number
	return if x < 0.5 then 4 * x * x * x else 1 - (-2 * x + 2) ^ 3 / 2
end

local function easeOutBack(x: number): number
	local c1, c3 = 1.9, 2.9
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function bump(x: number): number
	return if x > 0 and x < 1 then math.sin(x * math.pi) else 0
end

-- How far into the close (0..1; 0 before CONTINUE).
local function closing(t: number, opts: Opts, tm: Timing): number
	local at = opts.ContinuedAt
	return if at then span(t, at, at + tm.Close) else 0
end

-- The blur and colour grade of the world `t` seconds in (all back to nothing at the close's end).
function SecretCinematic.world(t: number, opts: Opts, stars: number?): World
	local tm = opts.Timing or SecretCinematic.Timing
	local b = SecretCinematic.Blur
	local blur: number
	if t < tm.Charge then
		blur = b.Discovery * easeOut(span(t, tm.Discovery, tm.Discovery + 1.0))
	elseif t < tm.Explosion then
		blur = b.Discovery + (b.Charge - b.Discovery) * span(t, tm.Charge, tm.Explosion)
	else
		blur = b.Charge + (b.Reveal - b.Charge) * easeInOut(span(t, tm.Explosion + 0.3, tm.Reveal + 0.6))
		if not opts.Reduced then
			blur += (b.Peak - b.Charge) * bump(span(t, tm.Explosion, tm.Explosion + 0.5))
		end
	end
	local into = easeOut(span(t, tm.Discovery, tm.Discovery + 1.0))
	local stay = 1 - closing(t, opts, tm)
	if t < 0 then
		stay = 0
	end
	local light = SecretCinematic.paletteOf(stars).Light
	return {
		Blur = blur * stay * (if opts.Phone then SecretCinematic.Phone.Blur else 1),
		Brightness = -0.08 * into * stay,
		Contrast = 0.1 * into * stay,
		Saturation = -0.45 * into * stay,
		Tint = WHITE:Lerp(light, 0.22 * into * stay),
	}
end

---------------------------------------------------------------- the view

type Mote = { Frame: Frame, At: Vector2, Speed: number, Phase: number }
type Ring = { Frame: Frame, Stroke: UIStroke, Gradient: UIGradient, Scale: UIScale, Dir: number, Speed: number, Thickness: number }
type Fragment = { Frame: Frame, Ghosts: { Frame }, Radius: number, Speed: number, Phase: number, Bob: number }
type Spark = { Frame: Frame, Dir: Vector2, Speed: number, Delay: number }
type Letter = { Holder: Frame, Scale: UIScale, Label: TextLabel, Glow: TextLabel, Gradient: UIGradient, X: number }

export type Info = {
	Name: string,
	Stars: number?, -- 1..3 (the look and the size; default 1)
	Rarity: string?, -- the pill (default "SECRET" + its stars)
	Chance: string?, -- "1 in 4,000"
	Value: string?, -- "$1.8M" (nil: no value line)
	New: boolean?, -- NEW! on a first find
}

export type View = {
	Gui: ScreenGui,
	Dim: Frame,
	Aurora: Frame,
	AuroraGradient: UIGradient,
	VignetteX: Frame,
	VignetteY: Frame,
	Motes: { Mote },
	Stage: Frame,
	StageScale: UIScale,
	Rig: Frame,
	Glows: { Frame }, -- the soft glow behind the ore: discs stacked from wide and faint to small
	Core: Frame,
	Bars: { Frame },
	Fans: { Frame },
	Rings: { Ring },
	Shocks: { Frame },
	Fragments: { Fragment },
	Sparks: { Spark },
	OreHolder: Frame,
	OreScale: UIScale,
	Port: ViewportFrame,
	World: WorldModel,
	Camera: Camera,
	Models: { [string]: Model },
	Rigs: { [Model]: SecretOreFx.Rig },
	Radius: { [Model]: number },
	Current: Model?,
	Passed: Model?, -- a clone of a model the caller passed (dropped by clear)
	NewTag: Frame,
	NewScale: UIScale,
	Ribbon: Frame,
	RibbonScale: UIScale,
	Title: Frame,
	TitleScale: UIScale,
	Letters: { Letter },
	Line: Frame,
	LineGradient: UIGradient,
	NameHolder: Frame,
	NameScale: UIScale,
	Name: TextLabel,
	NameGradient: UIGradient,
	Row: Frame,
	RowScale: UIScale,
	Pill: Frame,
	PillGradient: UIGradient,
	PillText: TextLabel,
	Chance: TextLabel,
	ValueHolder: Frame,
	ValueScale: UIScale,
	ValueChip: Frame,
	ValueStroke: UIStroke,
	ValueLabel: TextLabel,
	ValueAmount: TextLabel,
	ButtonHolder: Frame,
	ButtonScale: UIScale,
	Button: TextButton,
	ButtonFill: Frame,
	ButtonKey: Frame,
	Hint: TextLabel,
	Flash: Frame,
	Stars: number,
	New: boolean,
	HasValue: boolean,
	Shift: number, -- the rainbow's last step (its sequences change only when it moves on)
}

local VIEW_FROM_LOW = Vector3.new(-0.5, 0.08, -1)
local VIEW_FROM = Vector3.new(-0.5, 0.32, -1)
local LIGHT = Vector3.new(-0.16, -0.74, 0.65).Unit
local DARK_AMBIENT, LIT_AMBIENT = rgb(24, 20, 40), rgb(160, 154, 170)
local DARK_LIGHT, LIT_LIGHT = rgb(56, 50, 84), rgb(255, 248, 236)
local TITLE = "SECRET"
local TITLE_SIZE = 96 -- design units: a letter
local TRACKING = 12 -- design units between two letters
-- Montserrat Black capitals' widths (em), for the letter spacing
local ADVANCE = { S = 0.68, E = 0.62, C = 0.74, R = 0.72, T = 0.64 }
local CORNERS = {
	Vector3.new(1, 1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, -1, -1),
}

local function round(frame: Frame)
	UIKit.corner(frame, 999)
end

local function frame(parent: Instance, name: string, size: Vector2, z: number): Frame
	return UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = z,
	}, parent)
end

local function disc(parent: Instance, name: string, size: number, z: number): Frame
	local f = frame(parent, name, Vector2.new(size, size), z)
	round(f)
	return f
end

local function fadeSequence(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function threeTone(a: Color3, b: Color3, c: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, a),
		ColorSequenceKeypoint.new(0.5, b),
		ColorSequenceKeypoint.new(1, c),
	})
end

--[[
	A model made still for the viewport: its visible parts and its moving parts
	(SecretOreFx: a blinking lid is see-through until it blinks), no welds,
	sparkles, lights or floor disc, anchored, its middle at the origin. Returns
	how far its farthest corner reaches from the middle (the same as SecretReveal's).
]]
function SecretCinematic.still(model: Model): number
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Parent = model
			table.insert(parts, d)
		end
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			for _, extra in d:GetChildren() do
				extra:Destroy()
			end
		else
			d:Destroy()
		end
	end
	local kept: { BasePart } = {}
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in parts do
		local moving = part:GetAttribute("Move") ~= nil
		if part.Name == "Floor" or (part.Transparency >= 0.99 and not moving) then
			part:Destroy()
			continue
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		table.insert(kept, part)
		if part.Transparency >= 0.99 then
			continue
		end
		local half = part.Size / 2
		for _, corner in CORNERS do
			local at = part.CFrame * (corner * half)
			lo = Vector3.new(math.min(lo.X, at.X), math.min(lo.Y, at.Y), math.min(lo.Z, at.Z))
			hi = Vector3.new(math.max(hi.X, at.X), math.max(hi.Y, at.Y), math.max(hi.Z, at.Z))
		end
	end
	if #kept == 0 then
		return 1
	end
	local middle = CFrame.new(-(lo + hi) / 2)
	local reach = 0.5
	for _, part in kept do
		part.CFrame = middle * part.CFrame
		local half = part.Size / 2
		for _, corner in CORNERS do
			reach = math.max(reach, (part.CFrame * (corner * half)).Magnitude)
		end
	end
	return reach
end

local function word(parent: Instance, name: string, text: string, size: number, heavy: boolean, z: number): TextLabel
	return RevealKit.word(parent, name, text, size, heavy, z)
end

function SecretCinematic.build(): View
	local full = SecretCinematic.Tiers[#SecretCinematic.Tiers]
	local gui = UIKit.new("ScreenGui", {
		Name = "TerraForgeSecretCinematic",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 46, -- (the old jackpot screen's place: never both)
		Enabled = false,
	})
	local function screenFrame(name: string, z: number): Frame
		return UIKit.new("Frame", {
			Name = name,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
		}, gui)
	end
	local dim = screenFrame("Dim", 1)
	-- the animated gradient over the dark (soft at the middle, its colours drifting)
	local aurora = screenFrame("Aurora", 2)
	local auroraGradient = UIKit.new("UIGradient", {
		Rotation = 30,
		Transparency = fadeSequence({ { 0, 0.15 }, { 0.5, 0.75 }, { 1, 0.15 } }),
	}, aurora)
	-- the vignette: dark edges both ways
	local vignette = fadeSequence({ { 0, 0 }, { 0.2, 0.7 }, { 0.5, 1 }, { 0.8, 0.7 }, { 1, 0 } })
	local vignetteX = screenFrame("VignetteX", 3)
	vignetteX.BackgroundColor3 = Color3.new(0, 0, 0)
	UIKit.new("UIGradient", { Rotation = 0, Transparency = vignette }, vignetteX)
	local vignetteY = screenFrame("VignetteY", 3)
	vignetteY.BackgroundColor3 = Color3.new(0, 0, 0)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = vignette }, vignetteY)
	-- slow motes all over the screen (a fixed spread: the same every time)
	local motes: { Mote } = {}
	for k = 1, full.Motes do
		local size = 3 + (k * 5) % 5
		local mote = UIKit.new("Frame", {
			Name = "Mote" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(size, size),
			Visible = false,
			ZIndex = 4,
		}, gui)
		round(mote)
		table.insert(motes, {
			Frame = mote,
			At = Vector2.new((k * 0.618034) % 1, (k * 0.381966 + 0.21) % 1),
			Speed = 0.02 + (k * 0.0137) % 0.035,
			Phase = (k * 1.7) % (math.pi * 2),
		})
	end

	-- the stage: its middle is the show's middle, UIScale = the layout's scale
	local stage = UIKit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 5,
	}, gui)
	local stageScale = UIKit.new("UIScale", { Scale = 1 }, stage)
	-- the ore and everything round it
	local rig = frame(stage, "Rig", Vector2.zero, 1)
	-- the soft glow: discs from wide (the palette's A) to small (white), each faint: stacked they fall
	-- off smoothly from the middle (no picture needed)
	local glows: { Frame } = {}
	for k = 1, SecretCinematic.GlowDiscs do
		table.insert(glows, disc(rig, "Glow" .. k, 100, 1))
	end
	local fans: { Frame } = {}
	for k = 1, SecretCinematic.Full.Fans do
		local fan = frame(rig, "Fan" .. k, Vector2.new(150, SecretCinematic.RayLength), 2)
		fan.Visible = false
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = fadeSequence({ { 0, 1 }, { 0.25, 0.6 }, { 0.5, 0.2 }, { 0.75, 0.6 }, { 1, 1 } }),
		}, fan)
		table.insert(fans, fan)
	end
	local bars: { Frame } = {}
	for k = 1, SecretCinematic.Full.Bars do
		local b = frame(rig, "Beam" .. k, Vector2.new(12, SecretCinematic.RayLength), 3)
		b.Visible = false
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = fadeSequence({ { 0, 1 }, { 0.2, 0.55 }, { 0.5, 0 }, { 0.8, 0.55 }, { 1, 1 } }),
		}, b)
		table.insert(bars, b)
	end
	local core = disc(rig, "Core", 220, 5)
	local shocks = RevealKit.rings(rig, 4, 6)
	-- energy rings: a bright arc fading round each, turning opposite ways (5 + k seconds a turn)
	local rings: { Ring } = {}
	for k = 1, 4 do
		local size = 236 + 52 * k
		local ring = frame(rig, "Ring" .. k, Vector2.new(size, size), 7)
		ring.Visible = false
		round(ring)
		local stroke = UIKit.new("UIStroke", {
			Color = WHITE,
			Thickness = ({ 4, 3, 5, 2.5 })[k],
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, ring)
		local gradient = UIKit.new("UIGradient", {
			Rotation = 0,
			Transparency = fadeSequence({ { 0, 0 }, { 0.32, 0.1 }, { 0.5, 0.75 }, { 0.62, 1 }, { 1, 1 } }),
		}, stroke)
		table.insert(rings, {
			Frame = ring,
			Stroke = stroke,
			Gradient = gradient,
			Scale = UIKit.new("UIScale", { Scale = 1 }, ring),
			Dir = if k % 2 == 1 then 1 else -1,
			Speed = 360 / (5 + k),
			Thickness = ({ 4, 3, 5, 2.5 })[k],
		})
	end
	-- crystal fragments (diamonds) with a trail of fading ghosts; z 8 behind the ore, 10 in front
	local fragments: { Fragment } = {}
	for k = 1, full.Fragments do
		local size = 12 + (k * 7) % 9
		local ghosts: { Frame } = {}
		for j = 1, SecretCinematic.Full.Trail do
			local ghostSize = size * (1 - 0.2 * j)
			local ghost = frame(rig, "Trail" .. k .. "_" .. j, Vector2.new(ghostSize, ghostSize), 8)
			ghost.Visible = false
			ghost.Rotation = 45
			table.insert(ghosts, ghost)
		end
		local piece = frame(rig, "Fragment" .. k, Vector2.new(size, size), 8)
		piece.Visible = false
		piece.Rotation = 45
		UIKit.new("UIGradient", { Rotation = 45, Color = ColorSequence.new(WHITE, rgb(200, 200, 220)) }, piece)
		UIKit.new("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, piece)
		table.insert(fragments, {
			Frame = piece,
			Ghosts = ghosts,
			Radius = 168 + (k * 37) % 70,
			Speed = 0.9 + (k * 0.23) % 0.6,
			Phase = k * 2.399963, -- the golden angle: spread round the ore
			Bob = (k * 0.71) % (math.pi * 2),
		})
	end
	-- the ore: a viewport with a WorldModel, the camera turns round it
	local oreHolder = frame(rig, "Ore", Vector2.new(SecretCinematic.OreSize, SecretCinematic.OreSize), 9)
	local oreScale = UIKit.new("UIScale", { Scale = 1 }, oreHolder)
	local port = UIKit.new("ViewportFrame", {
		Name = "View",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Ambient = DARK_AMBIENT,
		LightColor = DARK_LIGHT,
		LightDirection = LIGHT,
		ZIndex = 9,
	}, oreHolder)
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = port
	local camera = Instance.new("Camera")
	camera.FieldOfView = SecretCinematic.Fov
	camera.Parent = port
	port.CurrentCamera = camera
	-- sparks of the burst: streaks with a bright head
	local sparks: { Spark } = {}
	for k = 1, full.Sparks do
		local a = (k * 137.508) % 360
		local s = frame(rig, "Spark" .. k, Vector2.new(if k % 3 == 0 then 22 else 34, if k % 3 == 0 then 4 else 5), 11)
		s.Visible = false
		s.Rotation = a
		UIKit.new("UIGradient", { Transparency = fadeSequence({ { 0, 1 }, { 0.6, 0.3 }, { 1, 0 } }) }, s)
		round(s)
		table.insert(sparks, {
			Frame = s,
			Dir = Vector2.new(math.cos(math.rad(a)), math.sin(math.rad(a))),
			Speed = 640 + (k * 53) % 420,
			Delay = (k % 4) * 0.025,
		})
	end
	-- NEW! on a first find: a tilted gold sticker by the ore
	local newTag = frame(rig, "New", Vector2.new(92, 40), 12)
	newTag.BackgroundColor3 = rgb(255, 214, 64)
	newTag.Rotation = 12
	newTag.Visible = false
	UIKit.corner(newTag, 10)
	UIKit.stroke(newTag, 3, PopTheme.Outline)
	local newScale = UIKit.new("UIScale", { Scale = 1 }, newTag)
	local newWord = word(newTag, "Text", "NEW!", 24, true, 13)
	newWord.Position = UDim2.fromScale(0.5, 0.5)
	newWord.Size = UDim2.fromScale(1, 1)
	UIKit.textStroke(newWord, 2, PopTheme.Outline)

	-- the words (each holder: a UIScale = the layout's TextScale x its entrance)
	local function holder(name: string, size: Vector2): (Frame, UIScale)
		local h = frame(stage, name, size, 5)
		h.Visible = false
		return h, UIKit.new("UIScale", { Scale = 1 }, h)
	end
	-- 3 stars: ONE IN A MILLION!
	local ribbon, ribbonScale = holder("Ribbon", Vector2.new(340, 40))
	ribbon.BackgroundColor3 = SecretCinematic.Gold[2]
	UIKit.corner(ribbon, 12)
	UIKit.stroke(ribbon, 3, PopTheme.Outline)
	UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(SecretCinematic.Gold[1], SecretCinematic.Gold[3]) }, ribbon)
	local ribbonWord = word(ribbon, "Text", "ONE IN A MILLION!", 24, true, 6)
	ribbonWord.Position = UDim2.fromScale(0.5, 0.5)
	ribbonWord.Size = UDim2.fromScale(1, 1)
	UIKit.textStroke(ribbonWord, 3, PopTheme.Outline)
	-- S E C R E T: a letter each (they drop in one after another), a glow copy behind each
	local title, titleScale = holder("Title", Vector2.new(560, 130))
	local letters: { Letter } = {}
	local width = 0
	for k = 1, #TITLE do
		width += (ADVANCE[TITLE:sub(k, k)] or 0.7) * TITLE_SIZE + (if k > 1 then TRACKING else 0)
	end
	local x = -width / 2
	for k = 1, #TITLE do
		local ch = TITLE:sub(k, k)
		local advance = (ADVANCE[ch] or 0.7) * TITLE_SIZE
		local slot = UIKit.new("Frame", {
			Name = "Letter" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, x + advance / 2, 0.5, 0),
			Size = UDim2.fromOffset(advance + 20, TITLE_SIZE * 1.25),
			ZIndex = 6,
		}, title)
		local scale = UIKit.new("UIScale", { Scale = 1 }, slot)
		local glowWord = word(slot, "Glow", ch, TITLE_SIZE, true, 6)
		glowWord.Position = UDim2.fromScale(0.5, 0.5)
		glowWord.Size = UDim2.fromScale(1, 1)
		glowWord.TextTransparency = 1
		UIKit.textStroke(glowWord, 9, WHITE)
		local label = word(slot, "Text", ch, TITLE_SIZE, true, 7)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(1, 1)
		label.TextTransparency = 1
		UIKit.textStroke(label, 5, PopTheme.Outline)
		local gradient = UIKit.new("UIGradient", { Rotation = 90 }, label)
		table.insert(letters, { Holder = slot, Scale = scale, Label = label, Glow = glowWord, Gradient = gradient, X = x + advance / 2 })
		x += advance + TRACKING
	end
	-- the energy line under the title
	local line = UIKit.new("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0.5, 64),
		Size = UDim2.fromOffset(0, 5),
		ZIndex = 6,
	}, title)
	round(line)
	local lineGradient = UIKit.new("UIGradient", {
		Transparency = fadeSequence({ { 0, 1 }, { 0.2, 0.3 }, { 0.5, 0 }, { 0.8, 0.3 }, { 1, 1 } }),
	}, line)
	-- the name (gold), scaled to fit its box
	local nameHolder, nameScale = holder("NameHolder", Vector2.new(560, 64))
	local name = word(nameHolder, "Name", "", 52, true, 6)
	name.Position = UDim2.fromScale(0.5, 0.5)
	name.Size = UDim2.fromScale(1, 1)
	name.TextScaled = true
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 52, MinTextSize = 14 }, name)
	UIKit.textStroke(name, 4, PopTheme.Outline)
	local nameGradient = UIKit.new("UIGradient", {
		Rotation = 90,
		Color = threeTone(SecretCinematic.Gold[1], SecretCinematic.Gold[2], SecretCinematic.Gold[3]),
	}, name)
	-- SECRET ★ and the chance, side by side
	local row, rowScale = holder("Row", Vector2.new(560, 44))
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(200, 42),
		ZIndex = 6,
	}, row)
	round(pill)
	UIKit.stroke(pill, 3, PopTheme.Outline)
	local pillGradient = UIKit.new("UIGradient", { Rotation = 0 }, pill)
	local pillText = word(pill, "Text", "SECRET", 24, true, 7)
	pillText.Position = UDim2.fromScale(0.5, 0.5)
	pillText.Size = UDim2.fromScale(1, 1)
	UIKit.textStroke(pillText, 3, PopTheme.Outline)
	local chance = UIKit.new("TextLabel", {
		Name = "Chance",
		BackgroundTransparency = 1,
		FontFace = Font.new(RevealKit.Style.Font, Enum.FontWeight.Heavy),
		LayoutOrder = 2,
		Size = UDim2.fromOffset(170, 42),
		Text = "",
		TextColor3 = WHITE,
		TextSize = 26,
		ZIndex = 6,
	}, row)
	UIKit.textStroke(chance, 3, PopTheme.Outline)
	-- VALUE $1.8M on a dark chip
	local valueHolder, valueScale = holder("ValueHolder", Vector2.new(420, 40))
	local valueChip = UIKit.new("Frame", {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rgb(16, 12, 30),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(240, 40),
		ZIndex = 6,
	}, valueHolder)
	round(valueChip)
	local valueStroke = UIKit.stroke(valueChip, 2, WHITE, 0.4)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, valueChip)
	local valueLabel = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		FontFace = Font.new(RevealKit.Style.Font, Enum.FontWeight.Bold),
		LayoutOrder = 1,
		Size = UDim2.fromOffset(78, 40),
		Text = "VALUE",
		TextColor3 = WHITE,
		TextSize = 20,
		ZIndex = 7,
	}, valueChip)
	local valueAmount = UIKit.new("TextLabel", {
		Name = "Amount",
		BackgroundTransparency = 1,
		FontFace = Font.new(RevealKit.Style.Font, Enum.FontWeight.Heavy),
		LayoutOrder = 2,
		Size = UDim2.fromOffset(120, 40),
		Text = "",
		TextColor3 = WHITE,
		TextSize = 30,
		ZIndex = 7,
	}, valueChip)
	UIKit.textStroke(valueAmount, 3, PopTheme.Outline)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Color = threeTone(SecretCinematic.Gold[1], SecretCinematic.Gold[2], SecretCinematic.Gold[3]),
	}, valueAmount)
	-- CONTINUE: big, green (the game's Pop button paint), its bar fills until it goes on its own
	local size = SecretCinematic.ButtonSize
	local buttonHolder, buttonScale = holder("ContinueHolder", size)
	local green = PopTheme.Paints.Green
	local button = UIKit.new("TextButton", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 6,
		Selectable = true,
	}, buttonHolder)
	UIKit.corner(button, 20)
	UIKit.stroke(button, 4, green.Edge)
	UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(green.Top, green.Bottom) }, button)
	local fillTrack = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -44, 0, 6),
		ZIndex = 7,
	}, button)
	round(fillTrack)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 8,
	}, fillTrack)
	round(fill)
	local buttonWord = word(button, "Text", "CONTINUE", 30, true, 8)
	buttonWord.Position = UDim2.new(0.5, 0, 0.5, -3)
	buttonWord.Size = UDim2.new(1, 0, 1, -10)
	UIKit.textStroke(buttonWord, 3, PopTheme.Outline)
	-- a gamepad's A on the left of it
	local key = UIKit.new("Frame", {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 34, 0.5, -3),
		Size = UDim2.fromOffset(36, 36),
		Visible = false,
		ZIndex = 9,
	}, button)
	round(key)
	UIKit.stroke(key, 3, PopTheme.Outline)
	local keyWord = word(key, "Text", "A", 22, true, 10)
	keyWord.Position = UDim2.fromScale(0.5, 0.5)
	keyWord.Size = UDim2.fromScale(1, 1)
	keyWord.TextColor3 = PopTheme.Outline
	-- the skip hint at the screen's bottom (before the reveal)
	local hint = UIKit.new("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		FontFace = Font.new(RevealKit.Style.Font, Enum.FontWeight.Bold),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(360, 28),
		Text = SecretCinematic.Hints.Mouse,
		TextColor3 = WHITE,
		TextSize = 20,
		TextTransparency = 1,
		ZIndex = 9,
	}, gui)
	UIKit.textStroke(hint, 2, PopTheme.Outline)

	return {
		Gui = gui,
		Dim = dim,
		Aurora = aurora,
		AuroraGradient = auroraGradient,
		VignetteX = vignetteX,
		VignetteY = vignetteY,
		Motes = motes,
		Stage = stage,
		StageScale = stageScale,
		Rig = rig,
		Glows = glows,
		Core = core,
		Bars = bars,
		Fans = fans,
		Rings = rings,
		Shocks = shocks,
		Fragments = fragments,
		Sparks = sparks,
		OreHolder = oreHolder,
		OreScale = oreScale,
		Port = port,
		World = worldModel,
		Camera = camera,
		Models = {},
		Rigs = {},
		Radius = {},
		Current = nil,
		Passed = nil,
		NewTag = newTag,
		NewScale = newScale,
		Ribbon = ribbon,
		RibbonScale = ribbonScale,
		Title = title,
		TitleScale = titleScale,
		Letters = letters,
		Line = line,
		LineGradient = lineGradient,
		NameHolder = nameHolder,
		NameScale = nameScale,
		Name = name,
		NameGradient = nameGradient,
		Row = row,
		RowScale = rowScale,
		Pill = pill,
		PillGradient = pillGradient,
		PillText = pillText,
		Chance = chance,
		ValueHolder = valueHolder,
		ValueScale = valueScale,
		ValueChip = valueChip,
		ValueStroke = valueStroke,
		ValueLabel = valueLabel,
		ValueAmount = valueAmount,
		ButtonHolder = buttonHolder,
		ButtonScale = buttonScale,
		Button = button,
		ButtonFill = fill,
		ButtonKey = key,
		Hint = hint,
		Flash = RevealKit.flash(gui, 10),
		Stars = 1,
		New = false,
		HasValue = false,
		Shift = -1,
	}
end

---------------------------------------------------------------- the ore and its words

local function show(view: View, model: Model)
	for _, child in view.World:GetChildren() do
		if child:IsA("Model") and child ~= model then
			child.Parent = nil
		end
	end
	model.Parent = view.World
	view.Current = model
end

-- A secret ore by its OreData id: its model is built the first time, then kept.
function SecretCinematic.setOre(view: View, oreId: string)
	SecretCinematic.clear(view)
	local model = view.Models[oreId]
	if not model then
		local built = ItemBuilder.display({ K = "Clean", O = oreId, G = SecretOreConfig.Grade }, CFrame.new(), oreId)
		view.Radius[built] = SecretCinematic.still(built)
		view.Rigs[built] = SecretOreFx.rig(built, CFrame.identity)
		view.Models[oreId] = built
		model = built
	end
	show(view, model)
end

-- Any model (the caller's stays untouched: a still clone is shown, clear() drops it).
function SecretCinematic.setModel(view: View, source: Model)
	SecretCinematic.clear(view)
	local model = source:Clone()
	view.Radius[model] = SecretCinematic.still(model)
	view.Rigs[model] = SecretOreFx.rig(model, CFrame.identity)
	view.Passed = model
	show(view, model)
end

-- After a show: a passed model's clone goes (an ore id's model is kept for the next time).
function SecretCinematic.clear(view: View)
	local passed = view.Passed
	if passed then
		view.Rigs[passed] = nil
		view.Radius[passed] = nil
		passed:Destroy()
		view.Passed = nil
		if view.Current == passed then
			view.Current = nil
		end
	end
end

-- The words and the look (its stars: the palette, the tier).
function SecretCinematic.setInfo(view: View, info: Info)
	local stars = math.clamp(math.floor(info.Stars or 1), 1, #SecretCinematic.Tiers)
	view.Stars = stars
	view.New = info.New == true
	view.Shift = -1
	local palette = SecretCinematic.paletteOf(stars)
	view.Name.Text = info.Name
	local rarity = info.Rarity or ("SECRET " .. string.rep("★", stars))
	view.PillText.Text = rarity
	view.Pill.Size = UDim2.fromOffset(math.max(150, 46 + 17 * utf8.len(rarity) :: number), 42)
	local chance = info.Chance or ""
	view.Chance.Text = chance
	view.Chance.TextColor3 = palette.Light
	view.Chance.Size = UDim2.fromOffset(math.max(40, 16 * #chance + 20), 42)
	view.Chance.Visible = chance ~= ""
	local value = info.Value
	view.HasValue = value ~= nil and value ~= ""
	view.ValueAmount.Text = value or ""
	view.ValueAmount.Size = UDim2.fromOffset(math.max(40, 20 * #(value or "") + 14), 40)
	view.ValueChip.Size = UDim2.fromOffset(78 + 10 + view.ValueAmount.Size.X.Offset + 34, 40)
	view.ValueLabel.TextColor3 = palette.Light
	view.ValueStroke.Color = palette.A
	view.Dim.BackgroundColor3 = palette.Deep
	view.Flash.BackgroundColor3 = palette.Light:Lerp(WHITE, 0.6)
	if not palette.Rainbow then
		local tones = threeTone(palette.A, palette.Light, palette.B)
		view.AuroraGradient.Color = threeTone(palette.A, palette.Deep, palette.B)
		view.PillGradient.Color = ColorSequence.new(palette.A, palette.B)
		view.LineGradient.Color = tones
		for _, letter in view.Letters do
			letter.Gradient.Color = threeTone(WHITE, palette.Light, palette.A)
			letter.Glow.TextColor3 = palette.A
			local edge = letter.Glow:FindFirstChildOfClass("UIStroke")
			if edge then
				edge.Color = palette.A
			end
		end
		for _, ring in view.Rings do
			ring.Gradient.Color = ColorSequence.new(palette.Light, palette.A)
		end
	end
end

-- (an ore's name, for callers that only have its id)
function SecretCinematic.infoOf(oreId: string): Info
	local ore = OreData.get(oreId)
	local secret = SecretOreConfig.ByOre[oreId]
	return {
		Name = ore.Name,
		Stars = if secret then secret.Stars else 1,
		Chance = if secret then SecretOreConfig.chanceText(secret.OneIn) else nil,
	}
end

---------------------------------------------------------------- the pose

local function textFade(label: TextLabel, alpha: number)
	label.TextTransparency = alpha
	local edge = label:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Transparency = alpha
	end
end

-- A colour along the palette (`x` 0 = A .. 1 = B; the rainbow drifts with t).
local function tone(palette: Palette, x: number, t: number): Color3
	if palette.Rainbow then
		return RevealKit.hue(x + t * 0.12)
	end
	return palette.A:Lerp(palette.B, math.clamp(x, 0, 1))
end

-- Piece k of n: A and B in turn (the rainbow: spread round it, drifting).
local function alternate(palette: Palette, k: number, n: number, t: number): Color3
	if palette.Rainbow then
		return RevealKit.hue((k - 1) / math.max(n, 1) + t * 0.12)
	end
	return if k % 2 == 1 then palette.A else palette.B
end

-- CONTINUE's words, edges, key and bar fade (its bar keeps its own see-through track).
local function fadeButton(view: View, alpha: number)
	for _, d in view.ButtonHolder:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextTransparency = alpha
		elseif d:IsA("UIStroke") then
			d.Transparency = alpha
		elseif d:IsA("Frame") then
			d.BackgroundTransparency = if d.Name == "Track"
				then 1 - 0.4 * (1 - alpha)
				elseif d.Name == "Fill" then 1 - 0.85 * (1 - alpha)
				else alpha
		end
	end
	view.Button.BackgroundTransparency = alpha
end

-- Where crystal fragment k is at `time`: (position, in front of the ore, alpha). It orbits on an
-- ellipse (behind the ore on its far side), drawn in as it charges, blown away at the burst; a
-- calm orbit again in the reveal.
local function orbit(f: Fragment, k: number, time: number, tm: Timing, reduced: boolean): (Vector2, boolean, number)
	local C, E, R = tm.Charge, tm.Explosion, tm.Reveal
	local c = span(time, C, E)
	if time < E + 0.9 then
		local a = f.Phase + (if reduced then 0 else f.Speed * (time + 2.4 * (E - C) * c ^ 2))
		local r = f.Radius * (1 - 0.32 * c ^ 2)
		local p = Vector2.new(math.cos(a) * r, math.sin(a) * r * 0.42 + (if reduced then 0 else 10 * math.sin(time * 1.3 + f.Bob)))
		local alpha = span(time, C + 0.25 + 0.05 * k, C + 0.6 + 0.05 * k)
		if time >= E then
			if not reduced then
				p += p.Unit * 900 * easeOut(span(time, E, E + 0.8))
			end
			alpha *= 1 - span(time, E + (if reduced then 0 else 0.25), E + 0.85)
		end
		return p, math.sin(a) > 0, alpha
	end
	local a = f.Phase + (if reduced then 0 else 0.5 * f.Speed * time)
	local r = f.Radius * 1.08
	local p = Vector2.new(math.cos(a) * r, math.sin(a) * r * 0.42 + (if reduced then 0 else 8 * math.sin(time * 1.1 + f.Bob)))
	return p, math.sin(a) > 0, 0.85 * span(time, R + 0.8 + 0.06 * k, R + 1.5 + 0.06 * k)
end

-- A line of words sliding up into its place from `from` (gap seconds); its alpha (0 = hidden).
local function rise(
	holder: Frame,
	scale: UIScale,
	place: Vector2,
	t: number,
	from: number,
	gap: number,
	textScale: number,
	stay: number,
	reduced: boolean
): number
	local u = span(t, from, from + gap)
	holder.Visible = u > 0 and stay > 0
	if holder.Visible then
		local lift = if reduced then 0 else 22 * (1 - easeOut(u))
		holder.Position = UDim2.fromOffset(place.X, place.Y + lift)
		scale.Scale = textScale
	end
	return u * stay
end

-- One frame `t` seconds into the show. Returns true when it is over (the gui is then disabled).
function SecretCinematic.pose(view: View, t: number, opts: Opts): boolean
	local tm = opts.Timing or SecretCinematic.Timing
	local reduced = opts.Reduced == true
	local phone = opts.Phone == true
	local tier = SecretCinematic.tierOf(view.Stars)
	local palette = SecretCinematic.paletteOf(view.Stars)
	local C, E, R, P = tm.Charge, tm.Explosion, tm.Reveal, tm.Pulse
	local continued = opts.ContinuedAt
	if t < 0 or (continued and t >= continued + tm.Close) then
		view.Gui.Enabled = false
		return t >= 0
	end
	view.Gui.Enabled = true
	local close = closing(t, opts, tm)
	local leave = span(close, 0, 0.55) -- everything but the ore fades in the close's first half
	local stay = 1 - leave

	-- the rainbow's colour sequences move on in steps (3 stars)
	if palette.Rainbow then
		local shift = math.floor(t * 2)
		if shift ~= view.Shift then
			view.Shift = shift
			local seq = RevealKit.rainbow(shift)
			view.AuroraGradient.Color = seq
			view.PillGradient.Color = seq
			view.LineGradient.Color = seq
			for _, letter in view.Letters do
				letter.Gradient.Color = RevealKit.rainbow(shift + 1)
			end
			for _, ring in view.Rings do
				ring.Gradient.Color = seq
			end
		end
	end

	-- the layout (any screen, live)
	local layout = SecretCinematic.layout(opts.Screen, opts.TopInset, tier.Cosmos)
	local mode = SecretCinematic.Layouts[layout.Mode]
	local textScale = mode.TextScale

	-- the screen: dark, the vignette, the drifting gradient
	local dark = (0.68 * easeOut(span(t, 0, 1.2)) + 0.16 * span(t, C, E) + 0.12 * easeOut(span(t, E, E + 0.3))) * stay
	view.Dim.BackgroundTransparency = 1 - dark
	view.VignetteX.BackgroundTransparency = 1 - 0.7 * dark
	view.VignetteY.BackgroundTransparency = 1 - 0.55 * dark
	local aurora = (0.12 * span(t, C, E) + 0.24 * easeOut(span(t, E, R + 0.5))) * stay
	view.Aurora.Visible = aurora > 0.001
	if view.Aurora.Visible then
		view.Aurora.BackgroundTransparency = 1 - aurora
		view.AuroraGradient.Rotation = if reduced then 30 else (30 + t * 9) % 360
		view.AuroraGradient.Offset = if reduced then Vector2.zero else Vector2.new(0.25 * math.sin(t * 0.37), 0)
	end
	local moteCount = if phone then SecretCinematic.Phone.Motes else tier.Motes
	local moteAlpha = span(t, 0.2, 1.4) * stay
	local drift = t + (if reduced then 0 else 3 * easeOut(span(t, E, E + 1.2)))
	for k, mote in view.Motes do
		local on = k <= moteCount and moteAlpha > 0
		mote.Frame.Visible = on
		if on then
			local x, y = mote.At.X, mote.At.Y
			if not reduced then
				x = (x + 0.012 * math.sin(t * 0.6 + mote.Phase)) % 1
				y = (y - drift * mote.Speed) % 1.1 - 0.05
			end
			mote.Frame.Position = UDim2.fromScale(x, y)
			local twinkle = if reduced then 0.6 else 0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * 2.1 + mote.Phase))
			mote.Frame.BackgroundColor3 = if k % 4 == 0 then WHITE else alternate(palette, k, 7, t)
			mote.Frame.BackgroundTransparency = 1 - 0.8 * twinkle * moteAlpha
		end
	end

	-- the stage: where the layout puts it, a punch and a shake at the burst
	local punch = if reduced then 0 else 0.07 * bump(span(t, E, E + 0.45))
	view.StageScale.Scale = layout.Scale * (1 + punch)
	local shake = Vector2.zero
	if not reduced then
		local tremble = if t < E then 3 * span(t, E - 0.9, E) ^ 2 else 0
		local kick = if t >= E then 16 * (1 - span(t, E, E + 0.7)) ^ 2 else 0
		local amount = math.max(tremble, kick)
		if amount > 0 then
			shake = Vector2.new(math.sin(t * 67.3) + 0.5 * math.sin(t * 41.1), math.cos(t * 59.7) + 0.5 * math.sin(t * 37.9)) * amount / 1.5
		end
	end
	view.Stage.Position = UDim2.fromOffset(layout.Center.X + shake.X, layout.Center.Y + shake.Y)
	-- the ore's place: the middle, in the reveal its layout's place
	local slide = easeInOut(span(t, R, R + 0.6))
	local at = mode.OreAt * slide
	view.Rig.Position = UDim2.fromOffset(at.X, at.Y)

	-- the glow behind it: mysterious, growing with the charge, a swell at the burst and the pulse
	local charge = span(t, C, E)
	local burst = if t >= E then math.exp(-(t - E) * 3.2) else 0
	local pulse = bump(span(t, P, P + 0.7))
	local rest = easeOut(span(t, E + 0.6, R + 0.4))
	local breathe = if reduced then 0 else 0.04 * math.sin(t * 2.2)
	local glow = (0.4 + 0.4 * charge ^ 1.3 + 0.5 * burst + 0.25 * pulse) * (1 - 0.3 * rest * (1 - pulse))
	local glowSize = SecretCinematic.GlowSize * (0.62 + 0.25 * charge + 0.25 * burst + 0.06 * pulse + breathe)
	local discs = if phone then SecretCinematic.GlowPhone else #view.Glows
	for k, d in view.Glows do
		local on = k <= discs and glow * stay > 0.005
		d.Visible = on
		if on then
			local inner = (k - 1) / math.max(discs - 1, 1) -- 0 the widest .. 1 the smallest
			local size = glowSize * (1 - 0.78 * inner)
			d.Size = UDim2.fromOffset(size, size)
			d.BackgroundColor3 = if palette.Rainbow
				then RevealKit.hue(inner * 0.6 + t * 0.12):Lerp(WHITE, inner ^ 2)
				elseif inner < 0.5 then palette.A:Lerp(palette.B, inner * 2)
				else palette.B:Lerp(WHITE, (inner - 0.5) * 2)
			d.BackgroundTransparency = 1 - math.min(1, glow * (0.09 + 0.07 * inner)) * stay
		end
	end
	view.Core.BackgroundTransparency = 1 - (0.04 + 0.3 * charge ^ 2 + 0.55 * burst + 0.1 * pulse) * (1 - 0.6 * rest) * stay
	local coreSize = 220 * (0.7 + 0.35 * charge + 0.3 * burst + breathe)
	view.Core.Size = UDim2.fromOffset(coreSize, coreSize)

	-- radial beams (two rays a bar) and wide soft fans: they grow with the charge, shoot out at the burst
	local length: number
	local beamAlpha: number
	local beamWidth: number
	if t < E then
		length = 0.5 * easeInOut(span(t, C + 0.2, E))
		beamAlpha = (0.15 + 0.4 * charge) * span(t, C, C + 0.4)
		beamWidth = 8 + 4 * charge
	else
		local out = easeOut(span(t, E, E + 0.25))
		length = 0.5 + 0.8 * out - 0.35 * easeInOut(span(t, E + 0.3, R))
		beamAlpha = 0.95 - 0.45 * easeInOut(span(t, E + 0.3, R)) + 0.25 * pulse
		beamWidth = 12 + 10 * out * (1 - span(t, E + 0.3, R))
		if not reduced then
			length += 0.03 * math.sin(t * 2.6)
		end
	end
	if reduced then
		beamAlpha *= 0.6
	end
	beamAlpha *= stay
	local spin = if reduced then 0 else 10 * t + 45 * easeOut(span(t, E, E + 0.8))
	local bars = if phone then SecretCinematic.Phone.Bars else #view.Bars
	for k, b in view.Bars do
		local on = k <= bars and length > 0.01 and beamAlpha > 0.005
		b.Visible = on
		if on then
			b.Rotation = (k - 1) * 180 / bars + spin
			b.Size = UDim2.fromOffset(beamWidth * (if k % 2 == 0 then 0.7 else 1), SecretCinematic.RayLength * length)
			b.BackgroundColor3 = alternate(palette, k, bars, t)
			b.BackgroundTransparency = 1 - beamAlpha * (if k % 2 == 0 then 0.75 else 1)
		end
	end
	local fans = if phone then SecretCinematic.Phone.Fans else #view.Fans
	local fanAlpha = (0.08 * charge + 0.12 * easeOut(span(t, E, E + 0.3))) * stay * (if reduced then 0.6 else 1)
	for k, fan in view.Fans do
		local on = k <= fans and fanAlpha > 0.005
		fan.Visible = on
		if on then
			fan.Rotation = (k - 0.5) * 180 / fans - (if reduced then 0 else 6 * t)
			fan.Size = UDim2.fromOffset(150, SecretCinematic.RayLength * (0.55 + 0.35 * math.max(charge, span(t, E, E + 0.3))))
			fan.BackgroundColor3 = alternate(palette, k + 1, fans, t + 4)
			fan.BackgroundTransparency = 1 - fanAlpha
		end
	end

	-- energy rings: in one by one, faster and faster, blown out at the burst, back calm in the reveal
	local run = t + 1.6 * (E - C) * charge ^ 2
	for k, ring in view.Rings do
		local inAt = C + 0.12 * (k - 1)
		local u = span(t, inAt, inAt + 0.45)
		local back = span(t, R + 0.3 + 0.1 * k, R + 0.8 + 0.1 * k)
		local alpha: number
		local scale: number
		if t < E then
			alpha = u
			scale = if reduced then 1 else 0.55 + 0.45 * easeOutBack(u)
		elseif t < R + 0.3 then
			local blown = span(t, E, E + 0.45)
			alpha = 1 - blown
			scale = 1 + (if reduced then 0 else 0.9 * easeOut(blown))
		else
			alpha = 0.7 * back
			scale = if reduced then 1 else 0.8 + 0.2 * easeOutBack(back)
		end
		scale += if reduced then 0 else 0.06 * pulse
		alpha *= stay
		local on = k <= tier.Rings and alpha > 0.005
		ring.Frame.Visible = on
		if on then
			ring.Scale.Scale = scale
			ring.Frame.Rotation = if reduced then k * 40 else (ring.Dir * ring.Speed * run + k * 40) % 360
			ring.Stroke.Transparency = 1 - alpha
			ring.Stroke.Thickness = ring.Thickness * (1 + 0.6 * burst)
		end
	end

	-- crystal fragments: orbiting with trails (ghosts where it was a moment ago), see orbit()
	local pieces = if phone then SecretCinematic.Phone.Fragments else tier.Fragments
	local trail = if reduced then 0 elseif phone then SecretCinematic.Phone.Trail else SecretCinematic.Full.Trail
	for k, f in view.Fragments do
		local p, front, alpha = orbit(f, k, t, tm, reduced)
		alpha *= stay
		local on = k <= pieces and alpha > 0.01
		f.Frame.Visible = on
		local color = if k % 3 == 0 then WHITE else alternate(palette, k, 5, t)
		if on then
			f.Frame.Position = UDim2.fromOffset(p.X, p.Y)
			f.Frame.ZIndex = if front then 10 else 8
			f.Frame.Rotation = 45 + (if reduced then 0 else t * 90 * (if k % 2 == 0 then 1 else -1))
			f.Frame.BackgroundColor3 = color
			f.Frame.BackgroundTransparency = 1 - alpha
		end
		for j, ghost in f.Ghosts do
			local showGhost = on and j <= trail
			ghost.Visible = showGhost
			if showGhost then
				local gp, gFront, gAlpha = orbit(f, k, t - 0.045 * j, tm, reduced)
				ghost.Position = UDim2.fromOffset(gp.X, gp.Y)
				ghost.ZIndex = if gFront then 10 else 8
				ghost.BackgroundColor3 = color
				ghost.BackgroundTransparency = 1 - gAlpha * stay * (0.55 - 0.15 * j)
			end
		end
	end

	-- shockwaves at the burst (one per star step, FlashGap apart), and the last pulse's soft ring
	for k, ring in view.Shocks do
		local u = -1
		local color = palette.Light
		if k <= #tier.Shocks and not reduced then
			u = (t - E - tier.Shocks[k]) / 0.62
			color = if k == 1 then palette.Light:Lerp(tone(palette, 0, t), math.clamp(u, 0, 1)) else alternate(palette, k, 3, t)
		elseif k == #view.Shocks then
			u = (t - P) / 0.9
		end
		RevealKit.poseRing(ring, if stay < 1 then -1 else u, color)
		if ring.Visible then
			-- (thinner than the shared look: a clean line, not a band over the whole screen)
			local edge = ring:FindFirstChildOfClass("UIStroke")
			if edge then
				edge.Thickness *= if k == #view.Shocks then 0.3 else 0.28
			end
		end
	end

	-- sparks of the burst
	local sparks = if phone then SecretCinematic.Phone.Sparks else tier.Sparks
	for k, s in view.Sparks do
		local dt = t - E - s.Delay
		local on = not reduced and k <= sparks and dt > 0 and dt < 0.9
		s.Frame.Visible = on
		if on then
			local travel = s.Speed * dt * (1 - 0.45 * dt)
			local p = s.Dir * (60 + travel)
			s.Frame.Position = UDim2.fromOffset(p.X, p.Y)
			s.Frame.BackgroundColor3 = if k % 3 == 0
				then SecretCinematic.Gold[2]
				elseif k % 3 == 1 then WHITE
				else alternate(palette, k, 9, t)
			s.Frame.BackgroundTransparency = span(dt, 0.45, 0.9)
		end
	end

	-- the flash (once at the burst, or a moment after it: the runtime took its slot, RevealKit.takeFlash)
	local flashAt = opts.FlashAt or E
	local f = if reduced then -1 else (t - flashAt) / RevealKit.Style.FlashTime
	local peak = math.min(SecretCinematic.FlashPeak, RevealKit.Style.FlashPeak)
	view.Flash.BackgroundTransparency = if f >= 0 and f < 1 then 1 - peak * (1 - f) ^ 3 else 1

	-- the ore: dark at first, lit up by the charge, fully at the burst; floating, turning
	local model = view.Current
	local reach = if model then view.Radius[model] or 1 else 1
	local oreRig = if model then view.Rigs[model] else nil
	if oreRig then
		SecretOreFx.pose(oreRig, CFrame.identity, t, reduced)
	end
	local size: number
	if t < E then
		size = 0.78 + 0.1 * easeOut(span(t, 0, C)) + 0.12 * easeInOut(charge)
	else
		size = 1 + (if reduced then 0 else 0.2 * bump(span(t, E, E + 0.6)))
	end
	if not reduced then
		size += 0.02 * math.sin(t * 2.4)
	end
	local float = if reduced then 0 else 7 * math.sin(t * 1.7)
	local tremble = if reduced or t >= E then Vector2.zero else Vector2.new(math.sin(t * 83), math.cos(t * 71)) * 3 * span(t, E - 0.8, E)
	local away = Vector2.new(tremble.X, float + tremble.Y)
	local gone = 0
	if continued then
		local u = close
		local target = opts.Target
		if target and not reduced then
			-- an arc into the bag, shrinking (the stage's scale turns px into design units)
			local scale = math.max(layout.Scale, 0.01)
			local from = layout.Center + (at + Vector2.new(0, float)) * scale
			local to = (target - from) / scale
			local e = easeInOut(u)
			away += to * e + Vector2.new(0, -110 * math.sin(u * math.pi))
			size *= 1 - 0.86 * e
			gone = span(u, 0.85, 1)
		else
			gone = u
		end
	end
	view.OreHolder.Position = UDim2.fromOffset(away.X, away.Y)
	view.OreScale.Scale = size
	view.Port.ImageTransparency = gone
	local light = 0.08 + 0.55 * charge ^ 1.5 + 0.37 * easeOut(span(t, E, E + 0.15))
	if t >= E then
		light = 1
	end
	view.Port.Ambient = DARK_AMBIENT:Lerp(LIT_AMBIENT, light)
	view.Port.LightColor = DARK_LIGHT:Lerp(LIT_LIGHT, light)
	-- the viewport camera: cranes up and pushes in, turns faster as it charges, whirls at the burst
	local turn = 0.6
	local pull = 1
	local from = VIEW_FROM
	if not reduced then
		turn = 0.35 * t + 0.7 * (E - C) * charge ^ 2 + math.pi * 2 * easeOut(span(t, E, E + 1.0)) + 0.45 * math.max(0, t - E - 1.0)
		if t < C then
			pull = 1.55 - 0.43 * easeInOut(span(t, 0, C))
			from = VIEW_FROM_LOW:Lerp(VIEW_FROM, easeInOut(span(t, 0, C)))
		elseif t < E then
			pull = 1.12 - 0.12 * easeInOut(charge)
		else
			pull = 0.86 + 0.14 * easeOut(span(t, E, E + 0.8))
		end
	end
	local look = CFrame.Angles(0, turn, 0):VectorToWorldSpace(from.Unit)
	local distance = reach / math.tan(math.rad(SecretCinematic.Fov) / 2) * 1.08 * pull
	view.Camera.CFrame = CFrame.lookAt(look * distance, Vector3.zero)

	-- the words
	local wordsIn = t >= R
	-- S E C R E T: one letter after another drops in (a squash as it lands), its gradient shining
	view.Title.Visible = wordsIn and stay > 0
	if view.Title.Visible then
		view.Title.Position = UDim2.fromOffset(mode.Title.X, mode.Title.Y)
		view.TitleScale.Scale = textScale
		for k, letter in view.Letters do
			local start = R + 0.05 * (k - 1)
			local u = span(t, start, start + 0.3)
			local s: number
			local drop = 0
			if reduced then
				s = 1
			elseif u < 1 then
				s = 2 - u * u
				drop = -40 * (1 - u)
			else
				local after = t - start - 0.3
				s = 1 + 0.1 * math.exp(-after * 9) * math.cos(after * 30)
			end
			letter.Scale.Scale = s
			letter.Holder.Position = UDim2.new(0.5, letter.X, 0.5, drop)
			local alpha = math.min(1, u * 2.5) * stay
			textFade(letter.Label, 1 - alpha)
			local shine = alpha * (0.3 + 0.25 * pulse + (if reduced then 0 else 0.1 * math.sin(t * 3 + k)))
			letter.Glow.TextTransparency = 1 - shine * 0.6
			local glowEdge = letter.Glow:FindFirstChildOfClass("UIStroke")
			if glowEdge then
				glowEdge.Transparency = 1 - shine
			end
			letter.Gradient.Offset = if reduced then Vector2.zero else Vector2.new(0, 0.25 * math.sin(t * 1.4 + k * 0.5))
		end
		local lineIn = easeOut(span(t, R + 0.35, R + 0.8))
		view.Line.Size = UDim2.fromOffset(470 * lineIn, 5)
		view.Line.BackgroundTransparency = 1 - lineIn * stay
		view.LineGradient.Offset = if reduced then Vector2.zero else Vector2.new(0.3 * math.sin(t * 1.8), 0)
	end
	-- 3 stars: ONE IN A MILLION!
	local ribbonIn = span(t, R + 0.45, R + 0.75)
	view.Ribbon.Visible = tier.Cosmos and ribbonIn > 0 and stay > 0
	if view.Ribbon.Visible then
		view.Ribbon.Position = UDim2.fromOffset(mode.Ribbon.X, mode.Ribbon.Y)
		view.RibbonScale.Scale = textScale * (if reduced then 1 else easeOutBack(ribbonIn) * (1 + 0.03 * math.sin(t * 5)))
		RevealKit.fade(view.Ribbon, 1 - ribbonIn * stay)
		view.Ribbon.BackgroundTransparency = 1 - ribbonIn * stay
	end
	-- the name, the rarity row and the value slide up after it
	local nameIn = rise(view.NameHolder, view.NameScale, mode.Name, t, R + 0.35, 0.4, textScale, stay, reduced)
	if view.NameHolder.Visible then
		textFade(view.Name, 1 - nameIn)
		view.NameGradient.Offset = if reduced then Vector2.zero else Vector2.new(0, 0.2 * math.sin(t * 1.6))
	end
	local rowIn = rise(view.Row, view.RowScale, mode.Row, t, R + 0.55, 0.4, textScale, stay, reduced)
	if view.Row.Visible then
		RevealKit.fade(view.Row, 1 - rowIn)
		view.Pill.BackgroundTransparency = 1 - rowIn
		view.PillGradient.Rotation = if reduced then 0 else (t * 40) % 360
	end
	local valueIn = rise(view.ValueHolder, view.ValueScale, mode.Value, t, R + 0.75, 0.4, textScale, stay, reduced)
	view.ValueHolder.Visible = view.ValueHolder.Visible and view.HasValue
	if view.ValueHolder.Visible then
		RevealKit.fade(view.ValueChip, 1 - valueIn)
		view.ValueChip.BackgroundTransparency = 1 - 0.75 * valueIn
		view.ValueStroke.Transparency = 1 - 0.6 * valueIn
	end
	-- NEW! (a first find), by the ore
	local newIn = span(t, R + 0.95, R + 1.25)
	view.NewTag.Visible = view.New and newIn > 0 and stay > 0
	if view.NewTag.Visible then
		local place = mode.New - mode.OreAt -- (in the rig: it moves with the ore)
		view.NewTag.Position = UDim2.fromOffset(place.X, place.Y)
		view.NewScale.Scale = textScale * (if reduced then 1 else easeOutBack(newIn))
		RevealKit.fade(view.NewTag, 1 - newIn * stay)
	end
	-- CONTINUE: pops in (mostly in when it starts taking presses), breathes, its bar fills until it
	-- goes on its own
	local buttonIn = span(t, tm.ContinueAt - 0.25, tm.ContinueAt + 0.1)
	view.ButtonHolder.Visible = buttonIn > 0 and stay > 0
	if view.ButtonHolder.Visible then
		view.ButtonHolder.Position = UDim2.fromOffset(mode.Button.X, mode.Button.Y)
		local pop = if reduced then 1 else easeOutBack(buttonIn) * (1 + 0.025 * math.sin(t * 4))
		view.ButtonScale.Scale = textScale * SecretCinematic.buttonScale(layout, opts.Touch) * pop
		local alpha = 1 - (if reduced then buttonIn else math.min(1, buttonIn * 2)) * stay
		fadeButton(view, alpha)
		view.ButtonFill.Size = UDim2.fromScale(span(t, tm.ContinueAt, tm.AutoContinue), 1)
		view.ButtonKey.Visible = opts.Input == "Gamepad"
	end
	-- the skip hint (before the burst's tail)
	local hintAlpha = span(t, tm.SkipFrom + 0.4, tm.SkipFrom + 0.9) * (1 - span(t, tm.SkipTo - 0.3, tm.SkipTo)) * stay
	view.Hint.Text = SecretCinematic.Hints[opts.Input or "Mouse"] or SecretCinematic.Hints.Mouse
	view.Hint.TextSize = math.max(14, 20 * layout.Scale)
	textFade(view.Hint, 1 - 0.65 * hintAlpha)
	return false
end

return SecretCinematic
