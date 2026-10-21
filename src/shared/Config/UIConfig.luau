--[[
	UI switches.

	LightUI: the owner's light "Bubble" look (style A, src/client/UI/Bubble*.luau).
	Default is what ships (on since 2026-10-20). To turn it back off fast:
	Default = false, and every player sees the dark UI again
	(docs/handoff/UI_LIGHT_SWITCH_ON.md). With it off, the Workspace attribute
	"LightUI" = true still turns it on for a Studio test.
]]

local UIConfig = {}

UIConfig.Default = true -- the switch: the light UI is on (owner's go, 2026-10-20)
UIConfig.LightUI = UIConfig.Default
UIConfig.Attribute = "LightUI" -- Workspace attribute that turns it on for testing

-- Our own prompt pills (LightPrompt, LightWorldController) instead of the
-- stock Roblox prompt. Off (owner 2026-10-20): the stock prompt stacks
-- prompts by UIOffset and updates its text live; the pill does neither.
UIConfig.CustomPrompts = false

-- Is the light UI on (the flag, or the Studio test attribute)?
function UIConfig.lightUI(): boolean
	if UIConfig.LightUI then
		return true
	end
	local ok, on = pcall(function()
		return game:GetService("Workspace"):GetAttribute(UIConfig.Attribute) == true
	end)
	return ok and on == true
end

return UIConfig
