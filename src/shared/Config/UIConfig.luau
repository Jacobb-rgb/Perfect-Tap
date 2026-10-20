--[[
	UI switches.

	LightUI: the owner's light "Bubble" look (style A, src/client/UI/Bubble*.luau).
	Default is what ships; while it is false every player sees exactly
	yesterday's dark UI. To try the light UI in Studio without changing code,
	set the Workspace attribute "LightUI" = true before pressing Play. To turn
	it back off fast: Default = false (docs/handoff/UI_LIGHT_SWITCH_ON.md).
]]

local UIConfig = {}

UIConfig.Default = false -- the switch (true once the owner's ANO lands)
UIConfig.LightUI = UIConfig.Default
UIConfig.Attribute = "LightUI" -- Workspace attribute that turns it on for testing

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
