--[[
	The loading screen (scene "loading" for tools/lune/export_scene.luau,
	shots in tools/preview/loading_shots.json). Drawn with the game's own
	LoadingView / LoadingConfig; the embers the script animates stand still
	here. The screen is opaque, so the scene behind it is empty.

	UI overlays (build/preview/<name>.json), each rendered at 1600 x 900 px:
	  ui_loading_pc           PC 1600 x 900: 64 %, a tip, SKIP
	  ui_loading_start        PC at the start: 8 %, no SKIP yet
	  ui_loading_phone        667 x 375 pt phone: SKIP big enough to tap, larger tip
	  ui_loading_phone_small  568 x 320 pt phone
	  ui_loading_tv           a 1080p TV (console): the safe area, the gamepad key on SKIP
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

local Vector2 = roblox.Vector2

function Preview.build(Loader: any): { [string]: any }
	local LoadingConfig = Loader.requirePath("ReplicatedFirst.LoadingConfig")
	local LoadingView = Loader.requirePath("ReplicatedFirst.LoadingView")

	-- `pt` the screen, `px` render pixels per pt, `input` for SKIP
	local function screen(
		pt: any,
		px: number,
		touch: boolean,
		tenFoot: boolean,
		progress: number,
		tip: number,
		skip: boolean,
		input: string
	): any
		local refs = LoadingView.build()
		local layout = LoadingConfig.layout(pt, touch, tenFoot)
		LoadingView.apply(refs, layout)
		refs.Scale.Scale = layout.Scale * px
		LoadingView.setProgress(refs, progress, false)
		LoadingView.setTip(refs, LoadingConfig.Tips[tip])
		LoadingView.showSkip(refs, skip, input, "")
		-- a few embers where the script would have them mid-rise
		for i = 1, (if touch then 4 else 8) do
			local ember = roblox.Instance.new("Frame")
			ember.BorderSizePixel = 0
			ember.BackgroundColor3 = if i % 2 == 0 then roblox.Color3.fromRGB(255, 186, 70) else roblox.Color3.fromRGB(255, 120, 40)
			ember.BackgroundTransparency = 0.15 + (i % 4) * 0.2
			ember.Size = roblox.UDim2.fromOffset(6 + i % 3 * 2, 6 + i % 3 * 2)
			ember.Position = roblox.UDim2.fromScale(0.05 + ((i * 0.137) % 1) * 0.9, 0.95 - (i * 0.29 % 1) * 0.55)
			local round = roblox.Instance.new("UICorner")
			round.CornerRadius = roblox.UDim.new(0.5, 0)
			round.Parent = ember
			ember.Parent = refs.Embers
		end
		return UiExport.export({ refs.Gui })
	end

	return {
		ui_loading_pc = screen(Vector2.new(1600, 900), 1, false, false, 0.64, 2, true, "Mouse"),
		ui_loading_start = screen(Vector2.new(1600, 900), 1, false, false, 0.08, 1, false, "Mouse"),
		ui_loading_phone = screen(Vector2.new(667, 375), 900 / 375, true, false, 0.42, 3, true, "Touch"),
		ui_loading_phone_small = screen(Vector2.new(568, 320), 900 / 320, true, false, 0.81, 5, true, "Touch"),
		ui_loading_tv = screen(Vector2.new(1920, 1080), 900 / 1080, false, true, 0.55, 4, true, "Gamepad"),
	}
end

return Preview
