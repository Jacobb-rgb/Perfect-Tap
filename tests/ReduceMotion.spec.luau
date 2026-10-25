--[[
	Reduce motion works with UI motion on or off (review 2026-10-25: while
	Config/AnimConfig.UIMotion was off, nothing set UI/Motion's flag, so
	Motion.reduced() stayed false for the Level, HUD, Train, Wheel and
	Placement controllers). ReduceMotionController sets it from the SETTINGS
	toggle and Roblox's GuiService.ReducedMotionEnabled.
]]

return function(T, Loader)
	local fs = require("@lune/fs")
	local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")
	local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.ReduceMotionController")

	local function source(path: string): string
		return fs.readFile(Loader.root .. "/src/client/" .. path .. ".luau")
	end

	T.test("ReduceMotion: the flag follows the settings even with UI motion off", function()
		Motion.setEnabled(false)
		local ok, err = pcall(function()
			Motion.setReduced(false)
			Motion.setSystemReduced(false)
			T.falsy(Motion.reduced())
			Motion.setReduced(true)
			T.truthy(Motion.reduced(), "the SETTINGS toggle")
			Motion.setReduced(false)
			Motion.setSystemReduced(true)
			T.truthy(Motion.reduced(), "Roblox's own setting")
		end)
		Motion.setSystemReduced(false)
		Motion.setReduced(false)
		Motion.setEnabled(true)
		if not ok then
			error(err, 0)
		end
	end)

	T.test("ReduceMotion: the controller is in the ORDER and wires both sources", function()
		T.truthy(type(Controller.start) == "function" and type(Controller.init) == "function")
		local body = source("Controllers/ReduceMotionController")
		T.truthy(body:find("Motion.setReduced(current.ReduceMotion == true)", 1, true), "the SETTINGS toggle")
		T.truthy(body:find("Motion.setSystemReduced(systemReduced())", 1, true), "Roblox's own setting")
		T.truthy(body:find('GetPropertyChangedSignal("ReducedMotionEnabled")', 1, true), "and its changes")
		-- (the others read Motion.reduced() when they animate, not at start, so the
		-- place in the ORDER only has to exist; it sits right after SettingsController)
		local init = source("init.client")
		local at = init:find('"ReduceMotionController"', 1, true)
		local settings = init:find('"SettingsController"', 1, true)
		T.truthy(at and settings and settings < at, "in the client ORDER, after SettingsController")
	end)
end
