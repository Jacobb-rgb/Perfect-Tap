--[[
	CleanFlash: the cleaning's flashes share RevealKit's one clock, a flash
	too soon after another waits its turn once, and Reduce motion has none
	(and takes no slot).
]]

return function(T, Loader)
	local CleanFlash = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CleanFlash")
	local RevealKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealKit")
	local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")

	T.test("cleaning flash: one clock with every reveal, a too-early one waits once, none in Reduce motion", function()
		local now = 100
		local waits: { { At: number, Fn: () -> () } } = {}
		local clock, delay = CleanFlash.clock, CleanFlash.delay
		CleanFlash.clock = function()
			return now
		end
		CleanFlash.delay = function(seconds: number, fn: () -> ())
			table.insert(waits, { At = now + seconds, Fn = fn })
		end
		local shown = 0
		local live = true
		local function show()
			shown += 1
		end
		local function isLive()
			return live
		end
		local ok, err = pcall(function()
			RevealKit.resetFlash()
			CleanFlash.play(show, isLive)
			T.eq(shown, 1, "a free clock: now")
			now = 100.1
			CleanFlash.play(show, isLive)
			T.eq(shown, 1, "too soon (a crack just before): not now")
			T.eq(#waits, 1, "it waits")
			T.truthy(math.abs(waits[1].At - (100 + RevealKit.FlashGap)) < 1e-9, "until the gap is over")
			now = waits[1].At + 1e-6
			waits[1].Fn()
			T.eq(shown, 2, "then it plays")
			table.clear(waits)
			now = 100.5
			CleanFlash.play(show, isLive)
			live = false
			now = waits[1].At + 1e-6
			waits[1].Fn()
			T.eq(shown, 2, "not once the cleaning is over")
			live = true
			table.clear(waits)
			RevealKit.resetFlash()
			Motion.setReduced(true)
			CleanFlash.play(show, isLive)
			T.eq(shown, 2, "Reduce motion: no flash")
			T.eq(#waits, 0, "and no wait")
			T.truthy(RevealKit.takeFlash(now), "and no slot taken")
			Motion.setReduced(false)
			CleanFlash.play(show, isLive)
			Motion.setReduced(true)
			now = waits[1].At + 1e-6
			waits[1].Fn()
			T.eq(shown, 2, "Reduce motion switched on while it waited: none")
		end)
		Motion.setReduced(false)
		RevealKit.resetFlash()
		CleanFlash.clock, CleanFlash.delay = clock, delay
		if not ok then
			error(err, 0)
		end
	end)
end
