--[[
	CleanFlash: the cleaning's screen flashes (a crystal's crack, the reveal,
	a relic's or a Flawless card: CleaningController's ctx.flash) through
	RevealKit's one flash clock, so two flashes anywhere in the game are
	never closer than RevealKit.FlashGap. A flash too soon after another (a
	crack just before the reveal) waits its turn once, then plays if the
	cleaning is still on. Reduce motion (Motion.reduced()): no flash, and it
	takes no slot (the jackpot, the eggs and the weather do the same).

	  CleanFlash.play(show, live)   show() now, or once it may while live()
]]

local RevealKit = require(script.Parent.Parent.Effects.RevealKit)
local Motion = require(script.Parent.Parent.UI.Motion)

local CleanFlash = {}

-- (tests) the clock and the wait
CleanFlash.clock = os.clock
CleanFlash.delay = function(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end

function CleanFlash.play(show: () -> (), live: () -> boolean)
	if Motion.reduced() then
		return
	end
	local now = CleanFlash.clock()
	if RevealKit.takeFlash(now) then
		show()
		return
	end
	CleanFlash.delay(math.max(0, RevealKit.nextFlashAt() - now), function()
		if live() and not Motion.reduced() and RevealKit.takeFlash(CleanFlash.clock()) then
			show()
		end
	end)
end

return CleanFlash
