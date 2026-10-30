-- The SECRET ore cinematic (owner 2026-10-30): its timeline from the one Timing table, skip and
-- CONTINUE (the name is always shown), Reduce motion, the burst's one flash, the layout on phones and
-- big screens, and the player (Effects/SecretOreReveal) on fake instances: repeated reveals leave one
-- gui, no post effects, no connections or bindings, and run OnDone once each.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local V2 = roblox.Vector2
	local SecretCinematic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.SecretCinematic")
	local SecretOreReveal = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.SecretOreReveal")
	local RevealKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealKit")
	local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.SecretRevealController")
	local SoundConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SoundConfig")
	local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local tm = SecretCinematic.Timing
	local DESKTOP = V2.new(1600, 900)

	local function opts(extra)
		local o = { Screen = DESKTOP, TopInset = 36, Input = "Mouse" }
		for k, v in extra or {} do
			o[k] = v
		end
		return o
	end

	T.test("secret cinematic: the owner's phases (0 / 1.5 / 3.5 / 5 / ~8 s), all from Timing", function()
		T.eq(tm.Discovery, 0, "discovery at 0")
		T.eq(tm.Charge, 1.5, "charging at 1.5 s")
		T.eq(tm.Explosion, 3.5, "the burst at 3.5 s")
		T.eq(tm.Reveal, 5, "the reveal at 5 s")
		T.eq(tm.Settle, 8, "all in by 8 s")
		local order = { "Discovery", "Charge", "Explosion", "Reveal", "Pulse", "Settle" }
		for k = 2, #order do
			T.lt(tm[order[k - 1]], tm[order[k]], order[k] .. " after " .. order[k - 1])
		end
		T.eq(SecretCinematic.phase(1.49), "Discovery")
		T.eq(SecretCinematic.phase(1.5), "Charge")
		T.eq(SecretCinematic.phase(3.5), "Explosion")
		T.eq(SecretCinematic.phase(5), "Reveal")
		-- overrides move everything: the phases, the cues, the hum
		local slow = SecretCinematic.timing({ Charge = 2, Explosion = 4.5, Reveal = 6, Bogus = 3, Close = "x" })
		T.eq(slow.Charge, 2, "override")
		T.eq(slow.Close, tm.Close, "a broken override is ignored")
		T.eq(slow.Bogus, nil, "an unknown key is ignored")
		T.eq(SecretCinematic.phase(4.4, slow), "Charge", "the phase follows the table")
		for _, cues in { SecretCinematic.cues(tm, 3), SecretCinematic.cues(slow, 1) } do
			for k = 2, #cues do
				T.le(cues[k - 1].At, cues[k].At, "cues in order")
			end
		end
		local function boomAt(timing)
			for _, cue in SecretCinematic.cues(timing, 1) do
				if cue.Sound == "SecretBoom" then
					return cue.At
				end
			end
			return nil
		end
		T.eq(boomAt(tm), tm.Explosion, "the boom at the burst")
		T.eq(boomAt(slow), slow.Explosion, "and with the overrides")
		-- every cue in its own phase, every sound a real SoundConfig sound
		for stars = 1, 3 do
			for _, cue in SecretCinematic.cues(tm, stars) do
				T.truthy(SoundConfig[cue.Sound], cue.Sound .. " is a sound")
			end
		end
		T.truthy(#SecretCinematic.cues(tm, 3) > #SecretCinematic.cues(tm, 1), "more sparkles for more stars")
		T.truthy(SoundConfig.SecretHum.Looped, "the hum loops")
		local volume = SecretCinematic.hum(2.5)
		T.truthy(volume > 0, "it hums while charging")
		local early, speed1 = SecretCinematic.hum(1.6)
		local late, speed2 = SecretCinematic.hum(3.4)
		T.truthy(late > early and speed2 > speed1, "louder and higher as it charges")
		T.eq((SecretCinematic.hum(tm.Explosion)), 0, "silent from the burst")
	end)

	T.test("secret cinematic: a skip never passes the name, SECRET or the chance; CONTINUE only after them", function()
		for t = 0, tm.ContinueAt + 1, 0.05 do
			local to, continue = SecretCinematic.press(t)
			if t < tm.SkipFrom then
				T.eq(to, t, "too early (the cleaning's last tap): nothing")
				T.falsy(continue)
			elseif t < tm.SkipTo then
				T.eq(to, tm.SkipTo, "a skip lands on SkipTo")
				T.falsy(continue, "a skip never closes it")
			elseif t < tm.ContinueAt then
				T.eq(to, t, "between: nothing")
				T.falsy(continue, "no CONTINUE before ContinueAt")
			else
				T.truthy(continue, "CONTINUE from ContinueAt")
			end
		end
		T.lt(tm.SkipTo, tm.Reveal, "a skip lands before the words")
		T.truthy(tm.SkipTo - tm.Explosion >= RevealKit.Style.FlashTime, "a skip lands after the burst's flash")
		T.truthy(tm.SkipTo - tm.Explosion >= tm.FlashWindow, "so a flash that waited can never come after a skip")
		T.lt(tm.ContinueAt, tm.AutoContinue, "it can be continued before it goes on its own")
		-- the real pose at ContinueAt: SECRET, the name and the chance are all up
		local view = SecretCinematic.build()
		SecretCinematic.setOre(view, "HollowEye")
		SecretCinematic.setInfo(view, { Name = "Hollow Eye", Stars = 1, Chance = "1 in 4,000", Value = "$1.8M", New = true })
		SecretCinematic.pose(view, tm.ContinueAt, opts())
		T.truthy(view.ButtonHolder.Visible, "CONTINUE shown when it takes presses")
		SecretCinematic.pose(view, tm.ContinueAt + 0.2, opts())
		T.truthy(view.Title.Visible, "SECRET shown")
		for _, letter in view.Letters do
			T.truthy(letter.Label.TextTransparency < 0.01, "every letter in")
		end
		T.truthy(view.NameHolder.Visible and view.Name.TextTransparency < 0.01, "the name in")
		T.eq(view.Name.Text, "Hollow Eye")
		T.truthy(view.Row.Visible and view.Chance.TextTransparency < 0.01, "the chance in")
		T.eq(view.Chance.Text, "1 in 4,000")
		T.eq(view.PillText.Text, "SECRET ★", "the rarity: SECRET and its stars")
		T.truthy(view.ValueHolder.Visible and view.ValueAmount.Text == "$1.8M", "the value in")
		T.truthy(view.NewTag.Visible, "NEW! on a first find")
		T.truthy(view.ButtonHolder.Visible, "CONTINUE shown")
		-- and before the reveal, none of it
		SecretCinematic.pose(view, tm.SkipTo, opts())
		T.falsy(view.Title.Visible, "no words in the burst")
		T.falsy(view.ButtonHolder.Visible, "no CONTINUE yet")
	end)

	T.test("secret cinematic: Reduce motion is calm (no flash, shake, punch, spin, sparks)", function()
		local view = SecretCinematic.build()
		SecretCinematic.setOre(view, "RainbowNova")
		SecretCinematic.setInfo(view, { Name = "Rainbow Nova", Stars = 3, Chance = "1 in 1,000,000" })
		local layout = SecretCinematic.layout(DESKTOP, 36, true)
		local camAt, rings = nil, nil
		for _, t in { tm.Explosion, tm.Explosion + 0.05, tm.Explosion + 0.2, tm.Explosion + 0.4 } do
			SecretCinematic.pose(view, t, opts({ Reduced = true, FlashAt = tm.Explosion }))
			T.eq(view.Flash.BackgroundTransparency, 1, "no flash")
			T.near(view.Stage.Position.X.Offset, layout.Center.X, 1, "no shake (x)")
			T.near(view.Stage.Position.Y.Offset, layout.Center.Y, 1, "no shake (y)")
			T.near(view.StageScale.Scale, layout.Scale, 1e-5, "no punch")
			for _, spark in view.Sparks do
				T.falsy(spark.Frame.Visible, "no sparks")
			end
			for _, shock in view.Shocks do
				T.falsy(shock.Visible, "no shockwaves")
			end
		end
		for _, t in { 2, 2.7, 6, 7.5 } do
			SecretCinematic.pose(view, t, opts({ Reduced = true }))
			local cam = view.Camera.CFrame.Position
			if camAt then
				T.truthy((cam - camAt).Magnitude < 1e-3, "the ore does not spin")
			end
			camAt = cam
			local turns = {}
			for k, ring in view.Rings do
				turns[k] = ring.Frame.Rotation
			end
			if rings then
				for k, r in turns do
					T.eq(r, rings[k], "rings stand still")
				end
			end
			rings = turns
			for _, f in view.Fragments do
				for _, ghost in f.Ghosts do
					T.falsy(ghost.Visible, "no trails")
				end
			end
		end
		-- the rule: no flash, and no slot taken from anything else
		RevealKit.resetFlash()
		local at, retry = SecretCinematic.boomFlash(10, true)
		T.eq(at, math.huge, "Reduce motion: no flash")
		T.eq(retry, nil, "no retry")
		T.truthy(RevealKit.takeFlash(10), "no slot taken")
		RevealKit.resetFlash()
		-- with motion: there is one at the burst (softer than RevealKit's cap)
		SecretCinematic.pose(view, tm.Explosion, opts({ FlashAt = tm.Explosion }))
		T.near(
			view.Flash.BackgroundTransparency,
			1 - math.min(SecretCinematic.FlashPeak, RevealKit.Style.FlashPeak),
			1e-6,
			"one soft flash"
		)
		SecretCinematic.pose(view, tm.Explosion + RevealKit.Style.FlashTime, opts({ FlashAt = tm.Explosion }))
		T.eq(view.Flash.BackgroundTransparency, 1, "gone FlashTime later")
		local world = SecretCinematic.world(tm.Explosion + 0.25, opts({ Reduced = true }), 3)
		local loud = SecretCinematic.world(tm.Explosion + 0.25, opts(), 3)
		T.truthy(world.Blur < loud.Blur, "no blur spike with Reduce motion")
		T.truthy(loud.Blur <= SecretCinematic.Blur.Peak + 1e-6, "the blur never past its peak")
	end)

	T.test("secret cinematic: the shakes are smooth (owner 2026-10-30: no stutter): small steps at 60 fps", function()
		local view = SecretCinematic.build()
		local tm = SecretCinematic.Timing
		local last: any = nil
		local t = tm.Explosion - 1
		while t < tm.Explosion + 1 do
			SecretCinematic.pose(view, t, opts())
			local at = V2.new(view.Stage.Position.X.Offset, view.Stage.Position.Y.Offset)
			if last then
				T.truthy((at - last).Magnitude <= 5, `the stage moves at most 5 units a frame at {t}`)
			end
			last = at
			t += 1 / 60
		end
		for i = 0, 400 do
			T.truthy(math.abs(SecretCinematic.sway(i / 100, 4.6, 0.3)) <= 1 + 1e-9, "the sway in -1..1")
		end
	end)

	T.test("secret cinematic: the burst's one flash waits once for RevealKit's gap, never late", function()
		RevealKit.resetFlash()
		local at, retry = SecretCinematic.boomFlash(10, false)
		T.eq(at, 0, "free: at the burst")
		T.eq(retry, nil)
		at, retry = SecretCinematic.boomFlash(10.1, false)
		T.eq(at, math.huge, "too soon after another")
		T.truthy(retry and math.abs(retry - (10 + RevealKit.FlashGap)) < 1e-9, "it tries again when the gap is over")
		T.eq(SecretCinematic.retryBoomFlash(0.42, 10.42), 0.42, "then it flashes where the show is")
		RevealKit.resetFlash()
		T.eq(SecretCinematic.retryBoomFlash(tm.FlashWindow + 0.01, 20), nil, "too late: none")
		T.truthy(RevealKit.takeFlash(20), "and no slot taken")
		RevealKit.resetFlash()
		-- the controller's names are the same rule
		T.eq(Controller.flashPlan(30, false), 0, "Controller.flashPlan")
		T.eq(Controller.retryFlash(0.3, 30.1), nil, "Controller.retryFlash: the slot is taken")
		RevealKit.resetFlash()
	end)

	T.test("secret cinematic: the layout fits a landscape phone (Side), tablets and big screens (Stack)", function()
		local screens = {
			{ V2.new(812, 375), 58, true }, -- a landscape phone, the new top bar
			{ V2.new(926, 428), 58, true },
			{ V2.new(1024, 768), 36, true }, -- a tablet
			{ V2.new(1180, 820), 36, true },
			{ V2.new(1280, 720), 36, false },
			{ V2.new(1920, 1080), 36, false },
			{ V2.new(375, 812), 58, true }, -- a phone held upright
		}
		for _, s in screens do
			local screen, inset, touch = s[1], s[2], s[3]
			for _, cosmos in { false, true } do
				local layout = SecretCinematic.layout(screen, inset, cosmos)
				local mode = SecretCinematic.Layouts[layout.Mode]
				local label = `{screen.X}x{screen.Y} {layout.Mode}`
				local up = if cosmos then mode.UpCosmos else mode.Up
				T.truthy(layout.Center.Y - up * layout.Scale >= inset - 0.01, label .. ": clear of the top bar")
				T.truthy(layout.Center.Y + mode.Down * layout.Scale <= screen.Y + 0.01, label .. ": on screen at the bottom")
				T.truthy(mode.Half * layout.Scale * 2 <= screen.X + 0.01, label .. ": fits across")
				T.le(layout.Scale, SecretCinematic.MaxScale, label .. ": never past the HUD's biggest")
				local button = SecretCinematic.ButtonSize.Y * layout.Scale * mode.TextScale * SecretCinematic.buttonScale(layout, touch)
				if touch then
					T.truthy(button >= SecretCinematic.MinTouch - 1e-6, label .. ": CONTINUE >= 44 pt on touch")
				end
				-- the words stay readable: the name's letters and the chance
				T.truthy(52 * mode.TextScale * layout.Scale >= 24 or screen.X < screen.Y, label .. ": a readable name")
			end
		end
		T.eq(SecretCinematic.layout(V2.new(812, 375), 58).Mode, "Side", "a landscape phone: the ore left, the words right")
		T.eq(SecretCinematic.layout(V2.new(1920, 1080), 36).Mode, "Stack", "a big screen: one column")
		T.eq(SecretCinematic.layout(V2.new(1920, 1080), 36).Scale, SecretCinematic.MaxScale, "at the HUD's biggest")
		T.eq(SecretCinematic.layout(V2.new(1024, 768), 36).Mode, "Stack", "a tablet: one column")
	end)

	T.test("secret cinematic: every ore poses through the whole show, a phone gets fewer pieces, nothing is made per frame", function()
		local view = SecretCinematic.build()
		local function count()
			return #view.Gui:GetDescendants()
		end
		for _, secret in SecretOreConfig.List do
			SecretCinematic.setOre(view, secret.Ore)
			SecretCinematic.setInfo(view, SecretCinematic.infoOf(secret.Ore))
			local before = count()
			for t = 0, tm.Settle, 0.25 do
				T.falsy(SecretCinematic.pose(view, t, opts()), secret.Ore .. " still playing at " .. t)
			end
			T.eq(count(), before, secret.Ore .. ": nothing made while it plays")
			T.eq(#view.World:GetChildren(), 1, secret.Ore .. ": one model in the viewport")
			-- the phone at the burst
			SecretCinematic.pose(view, tm.Explosion + 0.2, opts({ Phone = true, Screen = V2.new(812, 375) }))
			local sparks, beams = 0, 0
			for _, s in view.Sparks do
				sparks += if s.Frame.Visible then 1 else 0
			end
			for _, b in view.Bars do
				beams += if b.Visible then 1 else 0
			end
			T.le(sparks, SecretCinematic.Phone.Sparks, secret.Ore .. ": phone sparks")
			T.le(beams, SecretCinematic.Phone.Bars, secret.Ore .. ": phone beams")
			-- CONTINUE, then the close: the ore flies into the bag and it ends
			local target = V2.new(800, 860)
			T.falsy(SecretCinematic.pose(view, 9, opts({ ContinuedAt = 9, Target = target })))
			T.truthy(SecretCinematic.pose(view, 9 + tm.Close, opts({ ContinuedAt = 9, Target = target })), secret.Ore .. " ends")
			T.falsy(view.Gui.Enabled, "hidden at the end")
		end
		T.eq(#view.World:GetChildren(), 1, "six ores shown, still one model in the viewport")
		-- 3 stars: the ribbon
		SecretCinematic.setInfo(view, SecretCinematic.infoOf("RainbowNova"))
		SecretCinematic.pose(view, tm.Settle, opts())
		T.truthy(view.Ribbon.Visible, "ONE IN A MILLION! for Rainbow Nova")
		SecretCinematic.setInfo(view, SecretCinematic.infoOf("HollowEye"))
		SecretCinematic.pose(view, tm.Settle, opts())
		T.falsy(view.Ribbon.Visible, "not for one star")
		T.eq(#SecretCinematic.Palettes, 3, "a look per star count")
		T.truthy(SecretCinematic.Palettes[3].Rainbow, "Rainbow Nova: the rainbow")
	end)

	---------------------------------------------------------------- the player on fakes

	local function fakeEnv()
		local env: any = {}
		local state = { Steps = {}, Bound = 0, Resets = {}, Sounds = {}, Shakes = 0, Clock = 100, Hum = 0 }
		local playerGui = roblox.Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local camera = roblox.Instance.new("Camera")
		state.PlayerGui = playerGui
		state.Camera = camera
		env.GuiParent = function()
			return playerGui
		end
		env.EffectParent = function()
			return camera
		end
		env.Step = function(callback)
			local c = { Callback = callback, On = true }
			table.insert(state.Steps, c)
			return {
				Disconnect = function()
					c.On = false
				end,
			}
		end
		env.BindInput = function(press)
			state.Bound += 1
			state.Press = press
		end
		env.UnbindInput = function()
			state.Bound = 0
			state.Press = nil
		end
		env.OnReset = function(callback)
			local c = { Callback = callback, On = true }
			table.insert(state.Resets, c)
			return {
				Disconnect = function()
					c.On = false
				end,
			}
		end
		env.Clock = function()
			return state.Clock
		end
		env.Screen = function()
			return DESKTOP
		end
		env.TopInset = function()
			return 36
		end
		env.Input = function()
			return "Gamepad"
		end
		env.Phone = function()
			return false
		end
		env.Touch = function()
			return false
		end
		env.Reduced = function()
			return state.Reduced == true
		end
		env.Sound = function(name)
			table.insert(state.Sounds, name)
		end
		env.Hum = function(volume)
			state.Hum = volume
		end
		env.Shake = function()
			state.Shakes += 1
		end
		local function live(list)
			local n = 0
			for _, c in list do
				n += if c.On then 1 else 0
			end
			return n
		end
		function state.tick(seconds, dt)
			local step = dt or 1 / 30
			local left = seconds
			while left > 1e-9 do
				local d = math.min(step, left)
				left -= d
				state.Clock += d
				for _, c in state.Steps do
					if c.On then
						c.Callback(d)
					end
				end
			end
		end
		function state.live()
			return live(state.Steps)
		end
		function state.liveResets()
			return live(state.Resets)
		end
		function state.reset()
			for _, c in state.Resets do
				if c.On then
					c.Callback()
				end
			end
		end
		function state.effects()
			local n = 0
			for _, child in camera:GetChildren() do
				if child.Name:find("TerraForgeSecret") then
					n += 1
				end
			end
			return n
		end
		function state.guis()
			local n = 0
			for _, child in playerGui:GetChildren() do
				if child.Name == "TerraForgeSecretCinematic" then
					n += 1
				end
			end
			return n
		end
		function state.count(name)
			local n = 0
			for _, s in state.Sounds do
				n += if s == name then 1 else 0
			end
			return n
		end
		return env, state
	end

	local function request(ore, name, stars, done)
		return { Ore = ore, Name = name, Stars = stars, Chance = "1 in 4,000", Value = "$1.8M", OnDone = done }
	end

	T.test("secret cinematic player: a whole show, CONTINUE, then everything cleaned up", function()
		RevealKit.resetFlash()
		local env, s = fakeEnv()
		local runner = SecretOreReveal.new(env)
		local done = 0
		runner.play(request("HollowEye", "Hollow Eye", 1, function()
			done += 1
		end))
		T.eq(s.guis(), 1, "one gui")
		T.eq(s.effects(), 2, "the blur and the grade, on the camera")
		T.eq(s.live(), 1, "one frame connection")
		T.eq(s.Bound, 1, "one input binding")
		s.tick(0.1)
		T.eq(s.count("SecretMystery"), 1, "the first cue at the start")
		s.tick(tm.Explosion)
		T.eq(s.Shakes, 1, "the camera kicked once at the burst")
		T.eq(s.count("SecretBoom"), 1, "boom")
		local v = runner.view()
		T.eq(v.Gui.Enabled, true, "showing")
		s.tick(tm.ContinueAt - tm.Explosion)
		s.Press()
		s.tick(tm.Close + 0.1)
		T.eq(done, 1, "OnDone once")
		T.falsy(runner.playing(), "over")
		T.eq(s.live(), 0, "no connection left")
		T.eq(s.liveResets(), 0, "no reset hook left")
		T.eq(s.Bound, 0, "the binding gone")
		T.eq(s.effects(), 0, "no post effects left")
		T.eq(s.Hum, 0, "the hum stopped")
		T.eq(s.guis(), 1, "the gui kept (hidden) for the next time")
		T.falsy(v.Gui.Enabled, "hidden")
		RevealKit.resetFlash()
	end)

	T.test("secret cinematic player: repeated and overlapping reveals of different models never pile up", function()
		RevealKit.resetFlash()
		local env, s = fakeEnv()
		local runner = SecretOreReveal.new(env)
		local done = {}
		local function finished(key)
			return function()
				done[key] = (done[key] or 0) + 1
			end
		end
		-- a passed model (cloned: the caller's stays as it was)
		local model = ItemBuilder.display({ K = "Clean", O = "CagedLightning", G = "Flawless" }, Loader.CFrame.new(), 1)
		local parts = #model:GetDescendants()
		runner.play(request(model, "Caged Lightning", 2, finished("a")))
		s.tick(1)
		T.eq(#model:GetDescendants(), parts, "the caller's model untouched")
		-- another while it plays: the first closes cleanly first
		runner.play(request("RainbowNova", "Rainbow Nova", 3, finished("b")))
		T.eq(done.a, 1, "the first's OnDone ran")
		T.eq(s.guis(), 1, "still one gui")
		T.eq(s.effects(), 2, "still one blur and one grade")
		T.eq(s.live(), 1, "one frame connection")
		local v = runner.view()
		T.eq(#v.World:GetChildren(), 1, "one model in the viewport")
		T.eq(v.Passed, nil, "the passed model's clone dropped")
		-- cancel it halfway
		s.tick(2)
		runner.cancel()
		T.eq(done.b, 1, "cancel runs OnDone")
		T.eq(s.effects(), 0, "cancel removes the post effects")
		T.eq(s.live(), 0, "and the connection")
		-- a third: reset (the character goes) mid-show
		runner.play(request("HeartOfTerra", "Heart of Terra", 2, finished("c")))
		s.tick(0.6)
		s.reset()
		T.eq(done.c, 1, "a reset closes it")
		T.eq(s.effects(), 0, "no post effects after a reset")
		T.eq(s.Bound, 0, "no binding after a reset")
		-- a fourth nobody presses anything on: it continues on its own
		runner.play(request("FrostflameCrystal", "Frostflame Crystal", 1, finished("d")))
		s.tick(tm.AutoContinue + tm.Close + 0.2, 1 / 10)
		T.eq(done.d, 1, "auto-continue: nobody gets stuck")
		T.eq(s.guis(), 1, "four reveals, one gui")
		T.eq(s.effects(), 0, "four reveals, no post effects left")
		T.eq(s.live(), 0, "four reveals, no connections left")
		for key, n in done do
			T.eq(n, 1, key .. ": OnDone exactly once")
		end
		-- a leftover effect (a crash) is reused, never doubled
		local stale = roblox.Instance.new("BlurEffect")
		stale.Name = SecretOreReveal.BlurName
		stale.Parent = s.Camera
		runner.play(request("HollowEye", "Hollow Eye", 1, nil))
		T.eq(s.effects(), 2, "the leftover reused")
		runner.cancel()
		T.eq(s.effects(), 0, "and removed")
		RevealKit.resetFlash()
	end)

	T.test("secret cinematic player: a skip lands before the name, with no flash, kick or late flash", function()
		RevealKit.resetFlash()
		local env, s = fakeEnv()
		local runner = SecretOreReveal.new(env)
		local done = 0
		runner.play(request("TidecrownPearl", "Tidecrown Pearl", 1, function()
			done += 1
		end))
		s.tick(0.2)
		s.Press()
		T.near(runner.time(), 0.2, 0.05, "too early: nothing")
		s.tick(0.8)
		s.Press()
		T.eq(runner.time(), tm.SkipTo, "skipped to SkipTo")
		T.eq(s.count("SecretBoom"), 1, "the boom plays once on the skip")
		T.eq(s.count("SecretRise"), 0, "the cues it jumped over stay quiet")
		s.tick(0.5)
		T.eq(s.Shakes, 0, "no kick for a burst it jumped over")
		T.eq(runner.view().Flash.BackgroundTransparency, 1, "no flash after a skip")
		T.truthy(RevealKit.takeFlash(s.Clock), "and no slot taken")
		s.Press()
		T.truthy(runner.playing(), "before ContinueAt a press does nothing")
		s.tick(tm.ContinueAt - runner.time() + 0.05)
		T.truthy(runner.view().NameHolder.Visible, "the name is up")
		s.Press()
		s.tick(tm.Close + 0.1)
		T.eq(done, 1, "closed by CONTINUE")
		-- a waiting flash that the skip cuts off never fires
		RevealKit.resetFlash()
		runner.play(request("HollowEye", "Hollow Eye", 1, nil))
		s.tick(tm.Explosion - 0.2)
		RevealKit.takeFlash(s.Clock + 0.15) -- another reveal flashed just before the burst
		s.tick(0.25)
		T.eq(runner.view().Flash.BackgroundTransparency, 1, "the burst's flash waits")
		s.Press()
		s.tick(1)
		T.eq(runner.view().Flash.BackgroundTransparency, 1, "and never fires after the skip")
		runner.cancel()
		RevealKit.resetFlash()
	end)

	T.test("secret cinematic: the controller's value (the server's, else Flawless) and where the ore flies", function()
		local flawless = ItemData.value("Clean", "HollowEye", SecretOreConfig.Grade)
		T.eq(Controller.valueOf("HollowEye", nil), flawless, "Flawless, as the cleaning grades a secret")
		T.eq(flawless, math.floor(OreData.get("HollowEye").Value * ItemData.gradeMult("Flawless") + 0.5), "its value")
		T.eq(Controller.valueOf("HollowEye", { Value = 1234 }), 1234, "the server's graded value")
		T.eq(Controller.valueOf("HollowEye", { Value = 0 / 0 }), flawless, "a broken value: Flawless")
		T.eq(Controller.valueOf("HollowEye", { Grade = "Rough" }), ItemData.value("Clean", "HollowEye", "Rough"), "a capped grade")
		local screen = V2.new(1280, 720)
		T.eq(Controller.flyTo("Pen", screen, nil), nil, "to the pen: it fades")
		T.eq(Controller.flyTo("Tray", screen, V2.new(1, 2)), nil, "to the tray: it fades")
		T.eq(Controller.flyTo("Backpack", screen, V2.new(640, 650)), V2.new(640, 650), "into the bag button")
		T.eq(Controller.flyTo(nil, screen, nil), V2.new(640, 656), "the bag's place when the HUD is hidden")
	end)
end
