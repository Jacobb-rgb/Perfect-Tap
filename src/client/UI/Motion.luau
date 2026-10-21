--[[
	Motion: the UI's tween kit (owner 2026-10-21: "perfect animations").
	Windows pop and slide, buttons squash and bounce, the shop's cards
	breathe and shine, money rolls up and cash flies into the counter,
	rewards pop in. UIMotionController attaches most of it by itself.

	  pop(window, dim?)        scale 0.85 -> 1 (Back out, 0.22 s); the dim
	                           backdrop fades in with it
	  close(window, done?, dim?) scale to 0.9, then done() (or Visible = false)
	  slide(gui, from, distance?) in from "Left" | "Right" | "Up" | "Down"
	                           (it moves the AnchorPoint, never the Position
	                           a layout owns)
	  press(button)            a squash to 0.92 on press, a bounce back
	  hover(button)            a 1.04 grow under the mouse (PC only) and while
	                           a gamepad selects it (select)
	  breathe(gui)             a slow 1 <-> 1.03 pulse (BEST VALUE, FEATURED)
	  shine(button, phase?)    a light streak across the button every few seconds
	  countUp(label, from, to, format) the money rolling up
	  flyTo(from, to, icon?)   cash bits flying into the money counter (from a
	                           gui, a point in AbsolutePosition space, or nil:
	                           the screen centre); at most one burst a second
	  popIn(gui)               a bounce in for toasts and reward cards

	How it stays cheap and clean:
	- Everything is a TweenService tween (no per-frame Lua, no per-frame
	  allocations); the loops (breathe, shine) are endless tweens that run
	  only while their gui shows and isn't scrolled away (refreshLoops:
	  UIMotionController calls it when a gui opens or closes and once a
	  second while loops exist).
	- A newer animation on the same thing cancels the older one (a token per
	  thing); settle(root) snaps everything inside a hidden gui to its end.
	- One UIScale per thing. A button gets its own "MotionScale", unless it has
	  a UIScale already: then that one is tweened from its value and given
	  back. Windows and reward cards use "MotionPop". Roblox scales a UIScale
	  about the AnchorPoint, so centred things pop from their middle; a scale
	  changes the hit area only while its tween runs.
	- Reduce motion (the game's setting SettingsConfig.ReduceMotion, or
	  Roblox's own GuiService.ReducedMotionEnabled): every call jumps to its
	  end, nothing loops, no cash flies, buttons don't squash.

	The pure parts (the easing curves, count-up steps, the shine's offset,
	press targets) have Lune tests (tests/UIMotion.spec.luau). No emoji.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopTheme = require(Shared.Config.PopTheme)

local Motion = {}

export type Side = "Left" | "Right" | "Up" | "Down"
export type Profile = { Down: number, Hover: number }
export type Pointer = "Mouse" | "Touch" | "Gamepad"

---------------------------------------------------------------- tuning

Motion.Pop = { From = 0.85, Near = 0.95, Time = 0.22, DimTime = 0.18 }
Motion.Close = { To = 0.9, Time = 0.12 }
Motion.Slide = { Distance = 48, Time = 0.3 }
Motion.Press = { DownTime = 0.07, UpTime = 0.26, HoverTime = 0.12, BigSize = 220 }
Motion.Profiles = {
	Normal = { Down = 0.92, Hover = 1.04 } :: Profile,
	-- the shop's big cards: a gentler squash, the neighbours stay clear
	Big = { Down = 0.97, Hover = 1.02 } :: Profile,
}
Motion.Breathe = { Peak = 1.03, Time = 1.2 }
-- the streak crosses the button in Sweep seconds once every Period (one
-- endless linear tween of the gradient's offset: most of it is off the button)
Motion.Shine = { Period = 3.6, Sweep = 0.6, Width = 0.14, Core = 0.04, Transparency = 0.3, Tilt = 25, From = -1.2, To = 1.2, Inset = 6 }
Motion.Count = { Min = 0.45, Max = 0.9 }
Motion.Fly = { Bits = 7, Burst = 0.16, Travel = 0.42, Gap = 0.045, Every = 1, Spread = 70, Size = Vector2.new(38, 22) }
Motion.PopIn = { From = 0.5, Time = 0.32 }
Motion.Bump = { Peak = 1.15, Time = 0.09 }
Motion.SweepEvery = 1 -- seconds between the loops' visibility checks

---------------------------------------------------------------- easing (pure)

local BACK = 1.70158

local function bounceOut(t: number): number
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		local u = t - 1.5 / 2.75
		return 7.5625 * u * u + 0.75
	elseif t < 2.5 / 2.75 then
		local u = t - 2.25 / 2.75
		return 7.5625 * u * u + 0.9375
	end
	local u = t - 2.625 / 2.75
	return 7.5625 * u * u + 0.984375
end

-- The "In" curves of Roblox's EasingStyles (t and the result 0..1).
Motion.Easing = {
	Linear = function(t: number): number
		return t
	end,
	Sine = function(t: number): number
		return 1 - math.cos(t * math.pi / 2)
	end,
	Quad = function(t: number): number
		return t * t
	end,
	Cubic = function(t: number): number
		return t * t * t
	end,
	Quart = function(t: number): number
		return t * t * t * t
	end,
	Quint = function(t: number): number
		return t * t * t * t * t
	end,
	Exponential = function(t: number): number
		return if t <= 0 then 0 else 2 ^ (10 * (t - 1))
	end,
	Circular = function(t: number): number
		return 1 - math.sqrt(math.max(0, 1 - t * t))
	end,
	Back = function(t: number): number
		return t * t * ((BACK + 1) * t - BACK)
	end,
	Bounce = function(t: number): number
		return 1 - bounceOut(1 - t)
	end,
	Elastic = function(t: number): number
		if t <= 0 or t >= 1 then
			return t
		end
		return -(2 ^ (10 * (t - 1))) * math.sin((t - 1.075) * 2 * math.pi / 0.3)
	end,
} :: { [string]: (number) -> number }

-- An eased 0..1 for `t` (0..1), like TweenService: style "Back", direction
-- "In" | "Out" | "InOut".
function Motion.ease(style: string, direction: string, t: number): number
	local curve = Motion.Easing[style] or Motion.Easing.Linear
	local x = math.clamp(t, 0, 1)
	if direction == "In" then
		return curve(x)
	elseif direction == "InOut" then
		return if x < 0.5 then curve(x * 2) / 2 else 1 - curve((1 - x) * 2) / 2
	end
	return 1 - curve(1 - x)
end

-- A window's scale `t` seconds into its pop (`from` 0.85: Back out to 1).
function Motion.popScale(t: number, from: number?): number
	local start = from or Motion.Pop.From
	return start + (1 - start) * Motion.ease("Back", "Out", t / Motion.Pop.Time)
end

-- How long a count-up runs: bigger jumps a little longer (0.45 .. 0.9 s).
function Motion.countTime(from: number, to: number): number
	local jump = math.abs(to - from)
	local digits = if jump >= 1 then math.log10(jump) else 0
	return math.clamp(Motion.Count.Min + digits * 0.06, Motion.Count.Min, Motion.Count.Max)
end

-- The counted value at `alpha` (0..1 of the count's time): Quad out.
function Motion.countValue(from: number, to: number, alpha: number): number
	return from + (to - from) * Motion.ease("Quad", "Out", alpha)
end

-- The label's texts at `steps` + 1 evenly spaced moments of a count-up
-- (the first is from's text, the last to's).
function Motion.countSteps(from: number, to: number, format: (number) -> string, steps: number): { string }
	local out: { string } = {}
	local n = math.max(1, math.floor(steps))
	for i = 0, n do
		table.insert(out, format(if i == n then to else Motion.countValue(from, to, i / n)))
	end
	return out
end

-- The shine gradient's offset `t` seconds into its loop (`phase` shifts it).
function Motion.shineOffset(t: number, phase: number?): number
	local s = Motion.Shine
	local travel = (s.To - s.From) * s.Period / s.Sweep
	local cycle = ((t + (phase or 0)) % s.Period) / s.Period
	return s.From + travel * cycle
end

-- The end offset of the shine's loop tween.
function Motion.shineEnd(): number
	local s = Motion.Shine
	return s.From + (s.To - s.From) * s.Period / s.Sweep
end

-- The streak's transparency along the gradient: clear, a soft white band, clear.
function Motion.shineKeys(): { { number } }
	local s = Motion.Shine
	return {
		{ 0, 1 },
		{ 0.5 - s.Width, 1 },
		{ 0.5 - s.Core, s.Transparency },
		{ 0.5 + s.Core, s.Transparency },
		{ 0.5 + s.Width, 1 },
		{ 1, 1 },
	}
end

-- The breathing scale `t` seconds into its loop (Sine in-out, there and back).
function Motion.breatheScale(t: number, base: number?): number
	local b = Motion.Breathe
	local cycle = (t % (b.Time * 2)) / b.Time
	local alpha = if cycle <= 1 then cycle else 2 - cycle
	local start = base or 1
	return start + (start * b.Peak - start) * Motion.ease("Sine", "InOut", alpha)
end

-- Where a button's scale goes: squashed while pressed, grown under the
-- mouse or the gamepad's selection, else its base.
function Motion.pressTarget(base: number, pressed: boolean, raised: boolean, profile: Profile?): number
	local p = profile or Motion.Profiles.Normal
	if pressed then
		return base * p.Down
	elseif raised then
		return base * p.Hover
	end
	return base
end

-- Is an AnchorPoint the middle (a UIScale then pops it from its centre)?
function Motion.centred(anchor: Vector2): boolean
	return math.abs(anchor.X - 0.5) < 0.01 and math.abs(anchor.Y - 0.5) < 0.01
end

-- The AnchorPoint a slide starts from: `distance` design units toward `from`
-- for a thing `size` big (moving the anchor down moves the thing the other way).
function Motion.slideAnchor(base: Vector2, from: Side, distance: number, size: Vector2): Vector2
	local w = math.max(1, size.X)
	local h = math.max(1, size.Y)
	if from == "Left" then
		return Vector2.new(base.X + distance / w, base.Y)
	elseif from == "Right" then
		return Vector2.new(base.X - distance / w, base.Y)
	elseif from == "Up" then
		return Vector2.new(base.X, base.Y + distance / h)
	end
	return Vector2.new(base.X, base.Y - distance / h)
end

---------------------------------------------------------------- reduce motion

local settingReduced = false
local systemReduced = false
local pointer: Pointer = "Mouse"

-- The game's own setting (SettingsConfig.ReduceMotion; UIMotionController).
function Motion.setReduced(on: boolean)
	local was = Motion.reduced()
	settingReduced = on == true
	if was ~= Motion.reduced() then
		Motion.refreshLoops()
	end
end

-- Roblox's setting (GuiService.ReducedMotionEnabled; UIMotionController).
function Motion.setSystemReduced(on: boolean)
	local was = Motion.reduced()
	systemReduced = on == true
	if was ~= Motion.reduced() then
		Motion.refreshLoops()
	end
end

function Motion.reduced(): boolean
	return settingReduced or systemReduced
end

-- The input the player uses now: hover grows only for the mouse.
function Motion.setPointer(kind: Pointer)
	if pointer == kind then
		return
	end
	pointer = kind
	if kind ~= "Mouse" then
		Motion.clearHover()
	end
end

function Motion.pointer(): Pointer
	return pointer
end

---------------------------------------------------------------- shared helpers

local infos: { [string]: TweenInfo } = {}

-- A cached TweenInfo (TweenInfo isn't made per animation).
local function info(
	key: string,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	repeats: number?,
	reverses: boolean?
): TweenInfo
	local made = infos[key]
	if made then
		return made
	end
	local fresh = TweenInfo.new(time, style, direction, repeats or 0, reverses == true)
	infos[key] = fresh
	return fresh
end

-- Does `gui` show: every GuiObject up to its ScreenGui Visible, that gui
-- Enabled and in a PlayerGui.
function Motion.shown(gui: Instance): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("LayerCollector") then
			local holder = node.Parent
			return (node :: LayerCollector).Enabled and holder ~= nil and holder:IsA("PlayerGui")
		elseif node:IsA("GuiObject") then
			if not (node :: GuiObject).Visible then
				return false
			end
		else
			return false
		end
		node = node.Parent
	end
	return false
end

-- The design scale of the ScreenGui around `gui` (its "Scale" UIScale: HudController.uiScale).
local function guiScale(gui: Instance): number
	local screen = gui:FindFirstAncestorWhichIsA("LayerCollector")
	local scale = if screen then screen:FindFirstChild("Scale") else nil
	if scale and scale:IsA("UIScale") and scale.Scale > 0 then
		return scale.Scale
	end
	return 1
end

-- A gui's size in pixels (zero where nothing lays it out: the Lune previews).
local function pixels(gui: GuiObject): Vector2
	local ok, size = pcall(function(): Vector2
		return gui.AbsoluteSize
	end)
	return if ok then size else Vector2.zero
end

-- A gui's size in design units (its offsets, or its pixels over the gui scale).
function Motion.designSize(gui: GuiObject): Vector2
	local size = gui.Size
	if size.X.Scale == 0 and size.Y.Scale == 0 then
		return Vector2.new(size.X.Offset, size.Y.Offset)
	end
	local k = guiScale(gui)
	local abs = pixels(gui)
	local w = if size.X.Scale == 0 then size.X.Offset else abs.X / k
	local h = if size.Y.Scale == 0 then size.Y.Offset else abs.Y / k
	return Vector2.new(w, h)
end

-- every thing Motion scales: its UIScale and what runs on it
type Scaled = {
	Gui: GuiObject,
	Scale: UIScale,
	Base: number,
	Own: boolean,
	Token: number,
	Tween: Tween?,
	-- buttons
	Profile: Profile,
	Press: boolean,
	Hover: boolean,
	Pressed: boolean,
	Hovered: boolean,
	Selected: boolean,
	Release: RBXScriptConnection?,
	Breathing: boolean,
	Loop: Tween?,
}

-- weak keys: a destroyed gui drops out by itself
local scaled: { [GuiObject]: Scaled } = setmetatable({}, { __mode = "k" }) :: any

-- The scale state of `gui`: its UIScale (an existing one, else a new one named `name`).
local function scaleOf(gui: GuiObject, name: string): Scaled
	local s = scaled[gui]
	if s and s.Scale.Parent == gui then
		return s
	end
	local existing = gui:FindFirstChildOfClass("UIScale")
	local scale: UIScale
	local own = false
	if existing then
		scale = existing
		-- (one of Motion's own from before: it rests at 1)
		own = existing.Name == "MotionScale" or existing.Name == "MotionPop"
	else
		scale = Instance.new("UIScale")
		scale.Name = name
		scale.Scale = 1
		scale.Parent = gui
		own = true
	end
	local fresh: Scaled = {
		Gui = gui,
		Scale = scale,
		Base = if own then 1 else scale.Scale,
		Own = own,
		Token = 0,
		Tween = nil,
		Profile = Motion.Profiles.Normal,
		Press = false,
		Hover = false,
		Pressed = false,
		Hovered = false,
		Selected = false,
		Release = nil,
		Breathing = false,
		Loop = nil,
	}
	scaled[gui] = fresh
	return fresh
end

-- (tests) the scale state's UIScale, nil when Motion never touched `gui`.
function Motion.scaleOf(gui: GuiObject): UIScale?
	local s = scaled[gui]
	return if s then s.Scale else nil
end

local function stopTween(s: Scaled)
	local tween = s.Tween
	s.Tween = nil
	if tween then
		tween:Cancel()
	end
end

local function stopLoop(s: Scaled)
	local loop = s.Loop
	s.Loop = nil
	if loop then
		loop:Cancel()
	end
end

local function atRest(s: Scaled): boolean
	return not s.Pressed and not s.Hovered and not s.Selected and s.Tween == nil
end

-- A scale at rest takes its UIScale's value as its base again (an existing
-- UIScale that other code sets: Motion gives back what it found).
local function rebase(s: Scaled)
	if not s.Own and atRest(s) and s.Loop == nil then
		s.Base = s.Scale.Scale
	end
end

-- Plays `tween` as the thing's current one; `after` runs when it ends untouched.
local function run(s: Scaled, tween: Tween, after: (() -> ())?)
	s.Tween = tween
	local token = s.Token
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if s.Token ~= token then
			return
		end
		s.Tween = nil
		if after and state == Enum.PlaybackState.Completed then
			after()
		end
	end)
	tween:Play()
end

---------------------------------------------------------------- loops

type Loop = {
	Kind: "Breathe" | "Shine",
	Running: boolean,
	Phase: number,
	Token: number,
	Gradient: UIGradient?,
	Tween: Tween?,
	Screen: LayerCollector?, -- (its gui: while that is closed the check stops there)
}

local loops: { [GuiObject]: Loop } = {}
local loopCount = 0

local startBreathe: (s: Scaled) -> ()

function Motion.hasLoops(): boolean
	return loopCount > 0
end

local function startLoop(gui: GuiObject, loop: Loop)
	loop.Running = true
	loop.Token += 1
	if loop.Kind == "Breathe" then
		local s = scaleOf(gui, "MotionScale")
		if atRest(s) then
			startBreathe(s)
		end
		return
	end
	local gradient = loop.Gradient
	if not gradient then
		return
	end
	local token = loop.Token
	local function play()
		if loop.Token ~= token or not loop.Running or not gradient.Parent then
			return
		end
		local s = Motion.Shine
		gradient.Offset = Vector2.new(s.From, 0)
		local tween = TweenService:Create(
			gradient,
			info("Shine", s.Period, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false),
			{ Offset = Vector2.new(Motion.shineEnd(), 0) }
		)
		loop.Tween = tween
		tween:Play()
	end
	if loop.Phase > 0 then
		task.delay(loop.Phase, play)
	else
		play()
	end
end

local function stopLoopOf(gui: GuiObject, loop: Loop)
	loop.Running = false
	loop.Token += 1
	if loop.Kind == "Breathe" then
		local s = scaled[gui]
		if s then
			stopLoop(s)
			if atRest(s) then
				s.Scale.Scale = s.Base
			end
		end
		return
	end
	local tween = loop.Tween
	loop.Tween = nil
	if tween then
		tween:Cancel()
	end
	local gradient = loop.Gradient
	if gradient then
		gradient.Offset = Vector2.new(Motion.Shine.From, 0)
	end
end

-- Is `gui` inside the scrolling frame that holds it (a card scrolled away
-- doesn't shine)? True while it isn't laid out yet.
function Motion.inView(gui: GuiObject): boolean
	local size = pixels(gui)
	if size.X <= 0 or size.Y <= 0 then
		return true
	end
	local scroller = gui:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not scroller then
		return true
	end
	local at = gui.AbsolutePosition
	local from = scroller.AbsolutePosition
	local room = scroller.AbsoluteSize
	return at.X < from.X + room.X and at.Y < from.Y + room.Y and at.X + size.X > from.X and at.Y + size.Y > from.Y
end

-- Starts the loops that show and stops the others (and forgets removed ones).
function Motion.refreshLoops()
	local calm = Motion.reduced()
	for gui, loop in loops do
		if gui.Parent == nil then
			stopLoopOf(gui, loop)
			loops[gui] = nil
			loopCount -= 1
		else
			local screen = loop.Screen
			if screen == nil or screen.Parent == nil then
				screen = gui:FindFirstAncestorWhichIsA("LayerCollector")
				loop.Screen = screen
			end
			-- (a closed gui: no walk up its tree)
			local open = screen ~= nil and screen.Enabled
			local want = open and not calm and Motion.shown(gui) and Motion.inView(gui)
			if want ~= loop.Running then
				if want then
					startLoop(gui, loop)
				else
					stopLoopOf(gui, loop)
				end
			end
		end
	end
end

local function addLoop(gui: GuiObject, loop: Loop)
	if loops[gui] then
		return
	end
	loops[gui] = loop
	loopCount += 1
	if not Motion.reduced() and Motion.shown(gui) and Motion.inView(gui) then
		startLoop(gui, loop)
	end
end

-- (tests) the kinds of loop on `gui` and whether it runs.
function Motion.loopOf(gui: GuiObject): (string?, boolean)
	local loop = loops[gui]
	if not loop then
		return nil, false
	end
	return loop.Kind, loop.Running
end

---------------------------------------------------------------- buttons

startBreathe = function(s: Scaled)
	local loop = loops[s.Gui]
	if not s.Breathing or not loop or not loop.Running or s.Loop ~= nil or Motion.reduced() then
		return
	end
	s.Scale.Scale = s.Base
	local b = Motion.Breathe
	local tween = TweenService:Create(
		s.Scale,
		info("Breathe", b.Time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = s.Base * b.Peak }
	)
	s.Loop = tween
	tween:Play()
end

-- Tweens a button toward where its state says (`kind`: how it moves there).
local function retarget(s: Scaled, kind: "Down" | "Up" | "Hover")
	s.Token += 1
	stopLoop(s)
	stopTween(s)
	if Motion.reduced() then
		s.Scale.Scale = s.Base
		return
	end
	local goal = Motion.pressTarget(s.Base, s.Pressed, s.Hovered or s.Selected, s.Profile)
	local p = Motion.Press
	local tweenInfo = if kind == "Down"
		then info("Down", p.DownTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		elseif kind == "Up" then info("Up", p.UpTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		else info("Hover", p.HoverTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	run(s, TweenService:Create(s.Scale, tweenInfo, { Scale = goal }), function()
		if atRest(s) and s.Breathing then
			startBreathe(s)
		end
	end)
end

local function buttonState(button: GuiObject): Scaled
	local s = scaleOf(button, "MotionScale")
	if not s.Press and not s.Hover then
		local size = Motion.designSize(button)
		s.Profile = if math.max(size.X, size.Y) >= Motion.Press.BigSize then Motion.Profiles.Big else Motion.Profiles.Normal
	end
	return s
end

-- The squash on press and the bounce back (mouse and touch here; a
-- gamepad's A through pressDown). Attaching twice changes nothing.
function Motion.press(button: GuiButton): UIScale
	local s = buttonState(button)
	if not s.Press then
		s.Press = true
		button.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				Motion.pressDown(button, input)
			end
		end)
	end
	return s.Scale
end

-- The grow under the mouse (PC only: never on touch or a gamepad).
function Motion.hover(button: GuiButton): UIScale
	local s = buttonState(button)
	if not s.Hover then
		s.Hover = true
		button.MouseEnter:Connect(function()
			if pointer ~= "Mouse" or s.Hovered then
				return
			end
			rebase(s)
			s.Hovered = true
			retarget(s, "Hover")
		end)
		button.MouseLeave:Connect(function()
			if not s.Hovered and not s.Pressed then
				return
			end
			-- (dragged off while held: it springs back, like the press won't count)
			s.Hovered = false
			local was = s.Pressed
			s.Pressed = false
			retarget(s, if was then "Up" else "Hover")
		end)
	end
	return s.Scale
end

-- A press begins (`input` followed to its end: then the bounce back).
function Motion.pressDown(button: GuiObject, input: InputObject?)
	local s = scaled[button]
	if not s or not s.Press then
		return
	end
	local old = s.Release
	s.Release = nil
	if old then
		old:Disconnect()
	end
	if not s.Pressed then
		rebase(s)
		s.Pressed = true
		retarget(s, "Down")
	end
	if input then
		local follow = input
		s.Release = follow:GetPropertyChangedSignal("UserInputState"):Connect(function()
			local state = follow.UserInputState
			if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				Motion.pressUp(button)
			end
		end)
	else
		local token = s.Token
		task.delay(Motion.Press.DownTime + 0.05, function()
			if s.Token == token then
				Motion.pressUp(button)
			end
		end)
	end
end

function Motion.pressUp(button: GuiObject)
	local s = scaled[button]
	if not s then
		return
	end
	local old = s.Release
	s.Release = nil
	if old then
		old:Disconnect()
	end
	if s.Pressed then
		s.Pressed = false
		retarget(s, "Up")
	end
end

-- The gamepad's selection grows a button like the mouse does.
function Motion.select(button: GuiObject?, on: boolean)
	local s = if button then scaled[button] else nil
	if not s or not s.Hover or s.Selected == on then
		return
	end
	if on then
		rebase(s)
	end
	s.Selected = on
	retarget(s, "Hover")
end

-- Every hover grow goes (the player switched to touch or a gamepad).
function Motion.clearHover()
	for _, s in scaled do
		if s.Hovered then
			s.Hovered = false
			retarget(s, "Hover")
		end
	end
end

-- (tests) a button's state.
function Motion.stateOf(gui: GuiObject): { Pressed: boolean, Hovered: boolean, Selected: boolean, Profile: Profile }?
	local s = scaled[gui]
	if not s then
		return nil
	end
	return { Pressed = s.Pressed, Hovered = s.Hovered, Selected = s.Selected, Profile = s.Profile }
end

---------------------------------------------------------------- breathe / shine

-- A slow 1 <-> 1.03 pulse while it shows (a button keeps its press feel:
-- the pulse pauses while it is pressed, hovered or selected).
function Motion.breathe(gui: GuiObject)
	local s = scaleOf(gui, "MotionScale")
	s.Breathing = true
	addLoop(gui, { Kind = "Breathe", Running = false, Phase = 0, Token = 0, Gradient = nil, Tween = nil, Screen = nil })
end

-- A diagonal light streak sweeping across `button` every Shine.Period
-- seconds (`phase` seconds late: neighbours don't flash together). A
-- white gradient band in a clipping frame inset from the rounded corners.
function Motion.shine(button: GuiObject, phase: number?)
	if loops[button] then
		return
	end
	local s = Motion.Shine
	local row = button:FindFirstChild("Row")
	local z = if row and row:IsA("GuiObject") then math.max(1, row.ZIndex - 1) else button.ZIndex
	local clip = Instance.new("Frame")
	clip.Name = "MotionShine"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromOffset(s.Inset, 2)
	clip.Size = UDim2.new(1, -s.Inset * 2, 1, -4)
	clip.ZIndex = z
	local streak = Instance.new("Frame")
	streak.Name = "Streak"
	streak.BackgroundColor3 = Color3.new(1, 1, 1)
	streak.BackgroundTransparency = 0
	streak.BorderSizePixel = 0
	streak.Size = UDim2.fromScale(1, 1)
	streak.ZIndex = z
	streak.Parent = clip
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Sweep"
	gradient.Rotation = s.Tilt
	local keys = {}
	for _, key in Motion.shineKeys() do
		table.insert(keys, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	gradient.Transparency = NumberSequence.new(keys)
	gradient.Offset = Vector2.new(s.From, 0)
	gradient.Parent = streak
	clip.Parent = button
	addLoop(button, { Kind = "Shine", Running = false, Phase = phase or 0, Token = 0, Gradient = gradient, Tween = nil, Screen = nil })
end

---------------------------------------------------------------- windows

-- the dim backdrops' own transparency (taken once, before any fade)
local dims: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
local dimTweens: { [GuiObject]: Tween } = setmetatable({}, { __mode = "k" }) :: any
local poppedAt: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any

local function dimBase(dim: GuiObject): number
	local base = dims[dim]
	if base == nil then
		base = dim.BackgroundTransparency
		dims[dim] = base
	end
	return base
end

local function fadeDim(dim: GuiObject, goal: number, time: number)
	local old = dimTweens[dim]
	dimTweens[dim] = nil
	if old then
		old:Cancel()
	end
	if Motion.reduced() then
		dim.BackgroundTransparency = goal
		return
	end
	local tween = TweenService:Create(
		dim,
		info("Dim" .. time, time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = goal }
	)
	dimTweens[dim] = tween
	tween:Play()
end

-- Was `window` popped in the last `seconds` (a controller's own pop: the watcher leaves it)?
function Motion.poppedRecently(window: GuiObject, seconds: number?): boolean
	local at = poppedAt[window]
	return at ~= nil and os.clock() - at <= (seconds or 0.25)
end

-- A window opens: scale 0.85 -> 1 (0.95 when it isn't centred: Roblox
-- scales about the AnchorPoint), the dim backdrop fading in.
function Motion.pop(window: GuiObject, dim: GuiObject?)
	poppedAt[window] = os.clock()
	local s = scaleOf(window, "MotionPop")
	s.Token += 1
	stopTween(s)
	rebase(s)
	if dim then
		local base = dimBase(dim)
		if base < 0.98 and not Motion.reduced() then
			dim.BackgroundTransparency = 1
		end
		fadeDim(dim, base, Motion.Pop.DimTime)
	end
	if Motion.reduced() then
		s.Scale.Scale = s.Base
		return
	end
	local p = Motion.Pop
	s.Scale.Scale = s.Base * (if Motion.centred(window.AnchorPoint) then p.From else p.Near)
	run(s, TweenService:Create(s.Scale, info("Pop", p.Time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = s.Base }))
end

-- A window closes: scale to 0.9 (and the dim fading), then `done` (else Visible = false).
function Motion.close(window: GuiObject, done: (() -> ())?, dim: GuiObject?)
	local s = scaleOf(window, "MotionPop")
	s.Token += 1
	stopTween(s)
	rebase(s)
	local base = s.Base
	local function finish()
		if done then
			done()
		else
			window.Visible = false
		end
		s.Scale.Scale = base
		if dim then
			fadeDim(dim, dimBase(dim), 0)
		end
	end
	if Motion.reduced() or not Motion.shown(window) then
		finish()
		return
	end
	if dim then
		dimBase(dim)
		fadeDim(dim, 1, Motion.Close.Time)
	end
	run(
		s,
		TweenService:Create(
			s.Scale,
			info("Close", Motion.Close.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = base * Motion.Close.To }
		),
		finish
	)
end

-- the slides' resting AnchorPoint (taken once) and running tween
local anchors: { [GuiObject]: Vector2 } = setmetatable({}, { __mode = "k" }) :: any
local slides: { [GuiObject]: Tween } = setmetatable({}, { __mode = "k" }) :: any

-- Slides `gui` in from a side, `distance` design units (Motion.Slide.Distance).
function Motion.slide(gui: GuiObject, from: Side, distance: number?)
	local stored: Vector2? = anchors[gui]
	local rest: Vector2
	if stored then
		rest = stored
	else
		rest = gui.AnchorPoint
		anchors[gui] = rest
	end
	local old = slides[gui]
	slides[gui] = nil
	if old then
		old:Cancel()
	end
	if Motion.reduced() or not Motion.shown(gui) then
		gui.AnchorPoint = rest
		return
	end
	gui.AnchorPoint = Motion.slideAnchor(rest, from, distance or Motion.Slide.Distance, Motion.designSize(gui))
	local tween =
		TweenService:Create(gui, info("Slide", Motion.Slide.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { AnchorPoint = rest })
	slides[gui] = tween
	tween:Play()
end

-- A toast or a reward card appears: a bounce in. Returns its UIScale.
function Motion.popIn(gui: GuiObject): UIScale
	local s = scaleOf(gui, "MotionPop")
	s.Token += 1
	stopTween(s)
	rebase(s)
	if Motion.reduced() or not Motion.shown(gui) then
		s.Scale.Scale = s.Base
		return s.Scale
	end
	s.Scale.Scale = s.Base * Motion.PopIn.From
	run(
		s,
		TweenService:Create(s.Scale, info("PopIn", Motion.PopIn.Time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = s.Base })
	)
	return s.Scale
end

-- A quick bump (the cash pile when the money lands).
function Motion.bump(gui: GuiObject)
	if Motion.reduced() or not Motion.shown(gui) then
		return
	end
	local s = scaleOf(gui, "MotionPop")
	if s.Tween then
		return -- (still bumping)
	end
	s.Token += 1
	rebase(s)
	local b = Motion.Bump
	run(
		s,
		TweenService:Create(
			s.Scale,
			info("Bump", b.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
			{ Scale = s.Base * b.Peak }
		)
	)
end

---------------------------------------------------------------- count-up

type Counter = {
	Value: NumberValue,
	Format: (number) -> string,
	To: number,
	Tween: Tween?,
	Token: number,
}

local counters: { [TextLabel]: Counter } = setmetatable({}, { __mode = "k" }) :: any

function Motion.isCounting(label: TextLabel): boolean
	local c = counters[label]
	return c ~= nil and c.Tween ~= nil
end

local function stopCount(label: TextLabel, c: Counter)
	c.Token += 1
	local tween = c.Tween
	c.Tween = nil
	if tween then
		tween:Cancel()
	end
	label.Text = c.Format(c.To)
end

-- Rolls `label` up from `from` to `to` (texts through `format`); a count
-- already running goes on from where it is to the new `to`.
function Motion.countUp(label: TextLabel, from: number, to: number, format: (number) -> string, time: number?)
	local c = counters[label]
	if Motion.reduced() or not Motion.shown(label) then
		if c then
			c.Format = format
			c.To = to
			stopCount(label, c)
		else
			label.Text = format(to)
		end
		return
	end
	if not c then
		local value = Instance.new("NumberValue")
		value.Name = "MotionCount"
		local made: Counter = { Value = value, Format = format, To = to, Tween = nil, Token = 0 }
		value.Changed:Connect(function(now: number)
			if made.Tween then
				label.Text = made.Format(now)
			end
		end)
		value.Parent = label
		counters[label] = made
		c = made
	end
	local counter = c :: Counter
	local start = if counter.Tween then counter.Value.Value else from
	counter.Token += 1
	local old = counter.Tween
	counter.Tween = nil
	if old then
		old:Cancel()
	end
	counter.Format = format
	counter.To = to
	counter.Value.Value = start
	local seconds = time or Motion.countTime(start, to)
	local tween =
		TweenService:Create(counter.Value, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = to })
	counter.Tween = tween
	local token = counter.Token
	tween.Completed:Once(function()
		if counter.Token ~= token then
			return
		end
		counter.Tween = nil
		label.Text = counter.Format(counter.To)
	end)
	label.Text = format(start)
	tween:Play()
end

---------------------------------------------------------------- cash flying in

local flyAt: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
local seed = 20261021

-- 0..1 (a small LCG: the same flight every time, no allocation)
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local MONEY_GREEN = Color3.fromRGB(96, 206, 72)
local MONEY_LIGHT = Color3.fromRGB(176, 246, 128)
local COIN_GOLD = Color3.fromRGB(255, 200, 40)
local COIN_LIGHT = Color3.fromRGB(255, 236, 140)

-- One cash bit: a green banknote (or a gold coin) drawn from frames (no
-- uploaded picture needed, no emoji).
local function newBit(layer: Frame): Frame
	local size = Motion.Fly.Size
	local bit = Instance.new("Frame")
	bit.Name = "Cash"
	bit.AnchorPoint = Vector2.new(0.5, 0.5)
	bit.BackgroundColor3 = MONEY_GREEN
	bit.BorderSizePixel = 0
	bit.Size = UDim2.fromOffset(size.X, size.Y)
	bit.Visible = false
	bit.ZIndex = 61
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = bit
	local border = Instance.new("UIStroke")
	border.Name = "Border"
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = PopTheme.Outline
	border.Thickness = 2
	border.Parent = bit
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.BackgroundColor3 = MONEY_LIGHT
	band.BorderSizePixel = 0
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.fromScale(0.5, 0.62)
	band.ZIndex = 62
	local bandCorner = Instance.new("UICorner")
	bandCorner.CornerRadius = UDim.new(1, 0)
	bandCorner.Parent = band
	band.Parent = bit
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.FontFace = PopTheme.Heavy
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "$"
	mark.TextColor3 = Color3.fromRGB(30, 110, 30)
	mark.TextScaled = true
	mark.ZIndex = 63
	mark.Parent = band
	bit.Parent = layer
	return bit
end

local function look(bit: Frame, icon: string?)
	local coin = icon == "coin" or icon == "coins"
	local size = Motion.Fly.Size
	bit.BackgroundColor3 = if coin then COIN_GOLD else MONEY_GREEN
	bit.Size = if coin then UDim2.fromOffset(size.Y + 4, size.Y + 4) else UDim2.fromOffset(size.X, size.Y)
	local corner = bit:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = if coin then UDim.new(1, 0) else UDim.new(0, 4)
	end
	local band = bit:FindFirstChild("Band") :: Frame?
	if band then
		band.BackgroundColor3 = if coin then COIN_LIGHT else MONEY_LIGHT
		local mark = band:FindFirstChild("Mark") :: TextLabel?
		if mark then
			mark.TextColor3 = if coin then Color3.fromRGB(150, 96, 0) else Color3.fromRGB(30, 110, 30)
		end
	end
end

-- A cash bit as flyTo draws it (the previews show the same one).
function Motion.makeBit(layer: Frame, icon: string?): Frame
	local bit = newBit(layer)
	look(bit, icon)
	return bit
end

--[[
	Where a bit is `t` seconds into its flight (the curves of flyTo's two
	tweens): out of `start` to `burst` (Quad out, Fly.Burst s), then into
	`goal` shrinking (Quad in, Fly.Travel s). Returns the point and its size
	factor; nil once it has landed.
]]
function Motion.flyAt(start: Vector2, burst: Vector2, goal: Vector2, t: number): (Vector2?, number)
	local f = Motion.Fly
	if t < 0 then
		return start, 1
	elseif t < f.Burst then
		return start + (burst - start) * Motion.ease("Quad", "Out", t / f.Burst), 1
	elseif t < f.Burst + f.Travel then
		local a = Motion.ease("Quad", "In", (t - f.Burst) / f.Travel)
		return burst + (goal - burst) * a, 1 - 0.45 * a
	end
	return nil, 0.55
end

-- The full-screen layer the bits fly in (one per ScreenGui, above the rest).
local function layerOf(screen: LayerCollector): Frame
	local existing = screen:FindFirstChild("MotionFly")
	if existing and existing:IsA("Frame") then
		return existing
	end
	local layer = Instance.new("Frame")
	layer.Name = "MotionFly"
	layer.Active = false
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 60
	layer.Parent = screen
	return layer
end

local function takeBit(layer: Frame): Frame
	for _, child in layer:GetChildren() do
		if child:IsA("Frame") and child.Name == "Cash" and not child.Visible then
			return child
		end
	end
	return newBit(layer)
end

local function centreOf(gui: GuiObject): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize * 0.5
end

-- Small cash bits burst out of `from` (a gui, a point in AbsolutePosition
-- space, or nil: the screen centre) and fly into `to`, which bumps when they
-- land. At most one burst a second per target. False when nothing flew.
function Motion.flyTo(from: (GuiObject | Vector2)?, to: GuiObject, icon: string?, count: number?): boolean
	if Motion.reduced() or not Motion.shown(to) then
		return false
	end
	local now = os.clock()
	local last = flyAt[to]
	if last and now - last < Motion.Fly.Every then
		return false
	end
	local screen = to:FindFirstAncestorWhichIsA("LayerCollector")
	if not screen then
		return false
	end
	flyAt[to] = now
	local layer = layerOf(screen)
	local k = guiScale(to)
	local origin = layer.AbsolutePosition
	local function design(point: Vector2): UDim2
		local p = (point - origin) / k
		return UDim2.fromOffset(p.X, p.Y)
	end
	local startPoint: Vector2
	if typeof(from) == "Vector2" then
		startPoint = from :: Vector2
	elseif from ~= nil then
		startPoint = centreOf(from :: GuiObject)
	else
		startPoint = origin + layer.AbsoluteSize * 0.5
	end
	local start = design(startPoint)
	local goal = design(centreOf(to))
	local f = Motion.Fly
	local n = math.clamp(count or f.Bits, 1, 12)
	local burstInfo = info("FlyBurst", f.Burst, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local travelInfo = info("FlyTravel", f.Travel, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local landed = false
	for i = 1, n do
		local bit = takeBit(layer)
		look(bit, icon)
		local angle = (i / n) * math.pi * 2 + rand() * 0.8
		local reach = f.Spread * (0.55 + rand() * 0.45)
		bit.Position = start
		bit.Rotation = (rand() - 0.5) * 50
		bit.Visible = true
		local burstTo = start + UDim2.fromOffset(math.cos(angle) * reach, math.sin(angle) * reach)
		local full = bit.Size
		task.delay((i - 1) * f.Gap, function()
			if not bit.Parent then
				return
			end
			local burst = TweenService:Create(bit, burstInfo, { Position = burstTo, Rotation = bit.Rotation + (rand() - 0.5) * 60 })
			burst.Completed:Once(function()
				if not bit.Parent then
					return
				end
				local travel = TweenService:Create(bit, travelInfo, {
					Position = goal,
					Rotation = (rand() - 0.5) * 20,
					Size = UDim2.fromOffset(full.X.Offset * 0.55, full.Y.Offset * 0.55),
				})
				travel.Completed:Once(function()
					bit.Visible = false
					bit.Size = full
					if not landed then
						landed = true
						Motion.bump(to)
					end
				end)
				travel:Play()
			end)
			burst:Play()
		end)
	end
	return true
end

---------------------------------------------------------------- hidden guis

-- Everything inside `root` (a gui that just hid) jumps to its end: no tween
-- keeps running for a gui nobody sees. Loops stop through refreshLoops.
function Motion.settle(root: Instance)
	for gui, s in scaled do
		if (s.Tween or s.Pressed or s.Hovered or s.Selected) and gui:IsDescendantOf(root) then
			s.Token += 1
			stopTween(s)
			local release = s.Release
			s.Release = nil
			if release then
				release:Disconnect()
			end
			s.Pressed = false
			s.Hovered = false
			s.Selected = false
			s.Scale.Scale = s.Base
		end
	end
	for label, c in counters do
		if c.Tween and label:IsDescendantOf(root) then
			stopCount(label, c)
		end
	end
	for gui, tween in slides do
		if gui:IsDescendantOf(root) then
			tween:Cancel()
			slides[gui] = nil
			local rest = anchors[gui]
			if rest then
				gui.AnchorPoint = rest
			end
		end
	end
	local layer = root:FindFirstChild("MotionFly")
	if layer then
		for _, bit in layer:GetChildren() do
			if bit:IsA("Frame") then
				bit.Visible = false
				bit.Size = UDim2.fromOffset(Motion.Fly.Size.X, Motion.Fly.Size.Y)
			end
		end
	end
	Motion.refreshLoops()
end

return Motion
