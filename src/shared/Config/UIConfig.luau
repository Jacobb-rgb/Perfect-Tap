--[[
	UI switches.

	LightUI: the owner's light "Bubble" look (style A, src/client/UI/Bubble*.luau).
	OFF until the owner says yes: while it is off every player sees exactly
	today's UI. To try it in Studio without changing code, set the Workspace
	attribute "LightUI" = true before pressing Play.
]]

local UIConfig = {}

UIConfig.LightUI = false
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
