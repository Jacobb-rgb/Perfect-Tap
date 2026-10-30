--[[
	SecretOreReveal: plays the SECRET ore cinematic (Effects/SecretCinematic) on this
	client (owner 2026-10-30, his sketch's API). The server stays authoritative: this only
	shows what it already decided (SecretRevealController calls it when the cleaning's
	dirt bursts).

	  SecretOreReveal.Play(ore, oreName, rarity, value, opts?)
	      ore     an OreData id (its model is built once and kept) or any Model (cloned,
	              made still; the caller's model is never touched)
	      rarity  a number = the secret's Stars 1..3 (the look and the size; the pill says
	              "SECRET ★★"), or a string = the pill's own text (Stars from opts, else 1)
	      value   a number = coins (Format.money), or a string shown as it is ("" = none)
	      opts    { Chance = "1 in 4,000", New = true, Stars, OnDone, Target, Timing }
	              Target: () -> Vector2? (px) where the ore flies at the close (nil: it
	              fades), Timing: overrides of SecretCinematic.Timing
	  SecretOreReveal.Cancel()       closes it now (OnDone still runs once)
	  SecretOreReveal.isPlaying()
	  SecretOreReveal.new(env)       a player on its own environment (the specs' fakes)

	One show at a time: a Play while one is up closes that one cleanly first (its OnDone
	runs). Everything is built once and kept (the gui, its pieces, the six ores' models);
	while it plays there is ONE frame connection, one input binding (a press: skip /
	CONTINUE, every press sunk so gamepad A never reaches the cleaning behind it), one
	reset hook; the blur and colour grade are two post effects with unique names on the
	camera (this player only; never in Lighting, where LightingController tweens the
	first ColorCorrectionEffect and the cleaning the first DepthOfFieldEffect), found or
	made by name so a leftover is reused, never doubled; on close, cancel or the
	character's reset they are destroyed, the binding and connections go, the hum stops,
	the gui hides, OnDone runs once.
	The burst's flash: one at most (SecretCinematic.boomFlash: RevealKit's gap); one
	refused waits once (retryBoomFlash) and never fires past FlashWindow or after a skip.
	Sounds: the timeline's cues (SecretCinematic.cues) fire as the clock passes them (no
	task.delay chains: a skip or a close simply stops them); a skip plays only the cues
	marked OnSkip it jumps over (the burst's boom).
	Reduce motion (Motion.reduced()): the calm pose, no flash, no camera kick.
]]

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Format"))
local SecretCinematic = require(script.Parent:WaitForChild("SecretCinematic"))

local SecretOreReveal = {}

SecretOreReveal.Action = "TerraForgeSecretCinematic" -- the input binding
SecretOreReveal.BlurName = "TerraForgeSecretBlur" -- (the egg opening's is TerraForgeOpeningBlur)
SecretOreReveal.GradeName = "TerraForgeSecretGrade"

export type Connection = { Disconnect: (any) -> () }

-- What a player needs from the outside world (robloxEnv: the real one; the specs pass fakes).
export type Env = {
	GuiParent: () -> Instance?, -- the PlayerGui
	EffectParent: () -> Instance?, -- where the post effects go (the camera)
	Step: (callback: (dt: number) -> ()) -> Connection, -- every frame
	BindInput: (press: () -> ()) -> (), -- tap / click / A / Enter / Space, sunk
	UnbindInput: () -> (),
	OnReset: (callback: () -> ()) -> Connection?, -- the character goes (a reset, a death)
	Clock: () -> number,
	Screen: () -> Vector2,
	TopInset: () -> number,
	Input: () -> string, -- "Touch" | "Gamepad" | "Mouse"
	Phone: () -> boolean,
	Touch: () -> boolean,
	Reduced: () -> boolean,
	Sound: (name: string) -> (),
	Hum: (volume: number, speed: number) -> (), -- the charging hum's voice (volume 0: stopped)
	Shake: (amount: number) -> (),
}

export type Request = {
	Ore: any, -- an OreData id (string) or a Model
	Name: string,
	Stars: number?,
	Rarity: string?,
	Chance: string?,
	Value: string?,
	New: boolean?,
	OnDone: (() -> ())?,
	Target: (() -> Vector2?)?,
	Timing: { [string]: any }?,
}

export type Opts = {
	Chance: string?,
	New: boolean?,
	Stars: number?,
	OnDone: (() -> ())?,
	Target: (() -> Vector2?)?,
	Timing: { [string]: any }?,
}

export type Runner = {
	play: (request: Request) -> (),
	cancel: () -> (),
	playing: () -> boolean,
	view: () -> SecretCinematic.View?,
	press: () -> (), -- (the specs: as if the player pressed)
	time: () -> number, -- seconds into the show (-1: none)
}

type Show = {
	T: number,
	Timing: SecretCinematic.Timing,
	Cues: { SecretCinematic.Cue },
	Opts: SecretCinematic.Opts,
	Stars: number,
	Reduced: boolean,
	Boomed: boolean,
	Retry: number?,
	Effects: { Instance },
	Blur: BlurEffect?,
	Grade: ColorCorrectionEffect?,
	Step: Connection?,
	Reset: Connection?,
	Target: (() -> Vector2?)?,
	OnDone: (() -> ())?,
	Finished: boolean,
}

-- The post effect `name` of `className` under `parent`: the one already there (a leftover) or a new one.
local function effect(parent: Instance, className: string, name: string): Instance
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == className then
		return found
	end
	if found then
		found:Destroy()
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

function SecretOreReveal.new(env: Env): Runner
	local view: SecretCinematic.View? = nil
	local current: Show? = nil

	local function finish(show: Show)
		if show.Finished then
			return
		end
		show.Finished = true
		if show.Step then
			show.Step:Disconnect()
		end
		if show.Reset then
			show.Reset:Disconnect()
		end
		env.UnbindInput()
		env.Hum(0, 1)
		for _, made in show.Effects do
			made:Destroy()
		end
		table.clear(show.Effects)
		local v = view
		if v then
			v.Gui.Enabled = false
			SecretCinematic.clear(v)
		end
		if current == show then
			current = nil
		end
		local done = show.OnDone
		show.OnDone = nil
		if done then
			local ok, err = pcall(done :: () -> any)
			if not ok then
				warn(`[SecretOreReveal] OnDone error: {err}`)
			end
		end
	end

	local function frame(show: Show, dt: number)
		local v = view
		if show.Finished or current ~= show or not v then
			return
		end
		local tm = show.Timing
		local before = show.T
		show.T += dt
		local t = show.T
		if not show.Opts.ContinuedAt and t >= tm.AutoContinue then
			show.Opts.ContinuedAt = t -- nobody gets stuck
		end
		-- the burst: its one flash (RevealKit's gap) and the world camera's kick
		if not show.Boomed and t >= tm.Explosion then
			show.Boomed = true
			local at, retry = SecretCinematic.boomFlash(env.Clock(), show.Reduced)
			show.Opts.FlashAt = if at < math.huge then tm.Explosion + at else math.huge
			show.Retry = retry
			if not show.Reduced then
				env.Shake(SecretCinematic.tierOf(show.Stars).Shake)
			end
		end
		local retry = show.Retry
		if retry and env.Clock() >= retry then
			show.Retry = nil
			local since = SecretCinematic.retryBoomFlash(t - tm.Explosion, env.Clock(), tm)
			if since then
				show.Opts.FlashAt = tm.Explosion + since
			end
		end
		-- the sounds the clock passed
		for _, cue in show.Cues do
			if cue.At > before and cue.At <= t then
				env.Sound(cue.Sound)
			end
		end
		env.Hum(SecretCinematic.hum(t, tm))
		-- the world behind it
		local opts = show.Opts
		opts.Screen = env.Screen()
		opts.TopInset = env.TopInset()
		opts.Input = env.Input()
		local target = show.Target
		if opts.ContinuedAt and not opts.Target and target then
			opts.Target = target()
		end
		local world = SecretCinematic.world(t, opts, show.Stars)
		local blur, grade = show.Blur, show.Grade
		if blur then
			blur.Size = world.Blur
		end
		if grade then
			grade.Brightness = world.Brightness
			grade.Contrast = world.Contrast
			grade.Saturation = world.Saturation
			grade.TintColor = world.Tint
		end
		if SecretCinematic.pose(v, t, opts) then
			finish(show)
		end
	end

	local function press()
		local show = current
		if not show or show.Finished then
			return
		end
		local t = show.T
		local skipTo, continue = SecretCinematic.press(t, show.Timing)
		if continue then
			if not show.Opts.ContinuedAt then
				show.Opts.ContinuedAt = t
				env.Sound("UIClick")
			end
		elseif skipTo > t then
			-- a skip: the cues it jumps over stay quiet (but the burst's boom: the jump lands), no
			-- flash or kick for a burst it jumped over, none late for one that waited
			for _, cue in show.Cues do
				if cue.OnSkip and cue.At > t and cue.At <= skipTo then
					env.Sound(cue.Sound)
				end
			end
			show.Boomed = true
			show.Retry = nil
			show.T = skipTo
			env.Hum(0, 1)
		end
	end

	-- The gui, built the first time (then kept).
	local function ensureView(): SecretCinematic.View
		local v = view
		if v then
			return v
		end
		local built = SecretCinematic.build()
		-- CONTINUE by a click or a tap on the button itself (the binding takes the rest)
		built.Button.Activated:Connect(press)
		view = built
		return built
	end

	local function play(request: Request)
		local old = current
		if old then
			finish(old) -- one show at a time: the one still up closes cleanly first
		end
		local v = ensureView()
		local parent = env.GuiParent()
		if parent and v.Gui.Parent ~= parent then
			v.Gui.Parent = parent
		end
		if type(request.Ore) == "string" then
			SecretCinematic.setOre(v, request.Ore)
		elseif typeof(request.Ore) == "Instance" and request.Ore:IsA("Model") then
			SecretCinematic.setModel(v, request.Ore)
		else
			SecretCinematic.clear(v)
			v.Current = nil
		end
		local stars = math.clamp(math.floor(request.Stars or 1), 1, #SecretCinematic.Tiers)
		SecretCinematic.setInfo(v, {
			Name = request.Name,
			Stars = stars,
			Rarity = request.Rarity,
			Chance = request.Chance,
			Value = request.Value,
			New = request.New,
		})
		local tm = SecretCinematic.timing(request.Timing)
		local reduced = env.Reduced()
		local show: Show = {
			T = 0,
			Timing = tm,
			Cues = SecretCinematic.cues(tm, stars),
			Opts = {
				Screen = env.Screen(),
				TopInset = env.TopInset(),
				Reduced = reduced,
				Phone = env.Phone(),
				Touch = env.Touch(),
				Input = env.Input(),
				FlashAt = math.huge, -- (set at the burst: RevealKit's gap)
				ContinuedAt = nil,
				Target = nil,
				Timing = tm,
			},
			Stars = stars,
			Reduced = reduced,
			Boomed = false,
			Retry = nil,
			Effects = {},
			Blur = nil,
			Grade = nil,
			Step = nil,
			Reset = nil,
			Target = request.Target,
			OnDone = request.OnDone,
			Finished = false,
		}
		local holder = env.EffectParent()
		if holder then
			local blur = effect(holder, "BlurEffect", SecretOreReveal.BlurName) :: BlurEffect
			blur.Size = 0
			blur.Enabled = true
			local grade = effect(holder, "ColorCorrectionEffect", SecretOreReveal.GradeName) :: ColorCorrectionEffect
			grade.Enabled = true
			show.Blur = blur
			show.Grade = grade
			table.insert(show.Effects, blur)
			table.insert(show.Effects, grade)
		end
		current = show
		env.BindInput(press)
		show.Reset = env.OnReset(function()
			finish(show)
		end)
		show.Step = env.Step(function(dt)
			frame(show, dt)
		end)
		-- its first frame now (the cue at 0 included)
		show.T = -1e-6
		frame(show, 1e-6)
	end

	return {
		play = play,
		cancel = function()
			local show = current
			if show then
				finish(show)
			end
		end,
		playing = function()
			return current ~= nil
		end,
		view = function()
			return view
		end,
		press = press,
		time = function()
			local show = current
			return if show then show.T else -1
		end,
	}
end

---------------------------------------------------------------- the real client

local function robloxEnv(): Env
	local Sfx = require(script.Parent:WaitForChild("Sfx"))
	local CameraShake = require(script.Parent:WaitForChild("CameraShake"))
	local Motion = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Motion"))
	local player = Players.LocalPlayer
	local hum: Sound? = nil
	local function screen(): Vector2
		local camera = Workspace.CurrentCamera
		return if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	return {
		GuiParent = function()
			return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
		end,
		EffectParent = function()
			return Workspace.CurrentCamera or Lighting
		end,
		Step = function(callback)
			return RunService.RenderStepped:Connect(callback)
		end,
		BindInput = function(onPress)
			ContextActionService:BindAction(
				SecretOreReveal.Action,
				function(_, state)
					if state == Enum.UserInputState.Begin then
						onPress()
					end
					-- (always sunk: gamepad A never reaches the cleaning's Collect behind it)
					return Enum.ContextActionResult.Sink
				end,
				false,
				Enum.UserInputType.MouseButton1,
				Enum.UserInputType.Touch,
				Enum.KeyCode.ButtonA,
				Enum.KeyCode.Return,
				Enum.KeyCode.Space
			)
		end,
		UnbindInput = function()
			ContextActionService:UnbindAction(SecretOreReveal.Action)
		end,
		OnReset = function(callback)
			return player.CharacterRemoving:Connect(function()
				callback()
			end)
		end,
		Clock = os.clock,
		Screen = screen,
		TopInset = function()
			local ok, inset = pcall(function()
				return GuiService:GetGuiInset()
			end)
			return if ok then math.max(inset.Y, 36) else 58
		end,
		Input = function()
			local last = UserInputService:GetLastInputType()
			if last == Enum.UserInputType.Touch then
				return "Touch"
			elseif last.Name:find("Gamepad") then
				return "Gamepad"
			end
			return "Mouse"
		end,
		Phone = function()
			local size = screen()
			return UserInputService.TouchEnabled and math.min(size.X, size.Y) < 600
		end,
		Touch = function()
			return UserInputService.TouchEnabled
		end,
		Reduced = Motion.reduced,
		Sound = function(name)
			Sfx.play(name)
		end,
		Hum = function(volume, speed)
			if volume <= 0 then
				if hum and hum.IsPlaying then
					hum:Stop()
				end
				return
			end
			if not hum then
				hum = Sfx.voice("SecretHum")
			end
			local voice = hum
			if voice then
				voice.Volume = volume
				voice.PlaybackSpeed = speed
				if not voice.IsPlaying then
					voice:Play()
				end
			end
		end,
		Shake = function(amount)
			CameraShake.add(amount)
		end,
	}
end

local runner: Runner? = nil

local function default(): Runner
	local r = runner
	if not r then
		local made = SecretOreReveal.new(robloxEnv())
		runner = made
		return made
	end
	return r
end

-- Plays the cinematic (see the top). `rarity`: Stars (number) or the pill's text; `value`: coins or text.
function SecretOreReveal.Play(ore: Model | string, oreName: string, rarity: number | string, value: number | string, opts: Opts?)
	local o: Opts = opts or {}
	local stars = if type(rarity) == "number" then rarity else o.Stars or 1
	default().play({
		Ore = ore,
		Name = oreName,
		Stars = stars,
		Rarity = if type(rarity) == "string" then rarity else nil,
		Chance = o.Chance,
		Value = if type(value) == "number" then Format.money(value) elseif value ~= "" then value else nil,
		New = o.New,
		OnDone = o.OnDone,
		Target = o.Target,
		Timing = o.Timing,
	})
end

function SecretOreReveal.Cancel()
	local r = runner
	if r then
		r.cancel()
	end
end

function SecretOreReveal.isPlaying(): boolean
	local r = runner
	return r ~= nil and r.playing()
end

return SecretOreReveal
