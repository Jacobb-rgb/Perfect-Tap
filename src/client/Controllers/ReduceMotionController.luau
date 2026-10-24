--[[
	ReduceMotionController: keeps UI/Motion's reduce-motion flag in step with
	the SETTINGS toggle (ReduceMotion) and Roblox's own
	GuiService.ReducedMotionEnabled, whether UI motion (Config/AnimConfig.UIMotion)
	is on or off.

	Motion.reduced() is read by the Level, HUD, Train, Wheel and Placement
	controllers (and the shopkeepers). UIMotionController used to be the only
	one that set the flag, and it returns at once while UI motion is off, so
	Motion.reduced() stayed false and Reduce motion did nothing there (review
	2026-10-25). UIMotionController still sets the same flags when it runs;
	setting them twice is harmless.
]]

local GuiService = game:GetService("GuiService")

local Motion = require(script.Parent.Parent.UI.Motion)

local ReduceMotionController = {}

-- Roblox's own setting (pcall: older clients don't have the property).
local function systemReduced(): boolean
	local ok, on = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and on == true
end

function ReduceMotionController.init() end

function ReduceMotionController.start()
	-- (required here: SettingsController needs the player)
	local SettingsController = require(script.Parent.SettingsController)
	Motion.setSystemReduced(systemReduced())
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			Motion.setSystemReduced(systemReduced())
		end)
	end)
	SettingsController.onChanged(function(current)
		Motion.setReduced(current.ReduceMotion == true)
	end)
end

return ReduceMotionController
