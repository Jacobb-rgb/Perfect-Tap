--[[
	Is a gui put away at scale 0? Roblox never keeps a UIScale at 0: Scale = 0
	reads back as 1e-07 (the owner's Studio trace 2026-11-07, Studio 0.746). So a
	test for "hidden" never compares a UIScale with 0: with "~= 0" the egg
	opening's return took that 1e-07 for a real scale and put it back, and the
	whole HUD stayed invisible after the opening (CapsuleController.hideHud).
	No real scale gets this small (HudController.uiScale is 0.62 at the least).
]]

local HiddenScale = {}

HiddenScale.Below = 0.001

function HiddenScale.is(scale: number): boolean
	return scale >= 0 and scale < HiddenScale.Below
end

return HiddenScale
