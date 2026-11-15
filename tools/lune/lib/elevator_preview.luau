--[[
	The mine elevator's UI over the Stormglass Rift (scene "elevator_ui" for
	tools/lune/export_scene.luau, shots in tools/preview/mine_floor5_shots.json):
	the ELEVATOR window (owner 2026-11-15, UI/ElevatorWindow) and the ride to
	floor 5, drawn with the game's own ElevatorWindow / ElevatorRideView. The
	floor area behind is the mine_floor scene of floor 5 (MineFloorScene).

	UI overlays (build/preview/<name>.json), each rendered at 1600 x 900 px:
	  ui_elevator_pc        PC (1280 x 720 design units), like the owner's picture: blaster 8 at
	                        floor 1, floors 2-3 to walk or ride, floor 4 bought, floor 5 to buy
	                        (enough coins), floor 6 locked (blaster 9)
	  ui_elevator_pc_poor   the same short of floor 5's price: NOT ENOUGH COINS
	  ui_elevator_pc_new    a new player (blaster 1, a few coins): floors 2-6 locked
	  ui_elevator_pc_bare   the PC window before the owner uploads the pictures (painted backdrops)
	  ui_elevator_phone     a 667 x 375 pt phone (uiScale 0.62): 2 columns, the top of the list
	  ui_elevator_phone_end the phone scrolled to the end (floors 5-6 and COMING SOON)
	  ui_elevator_ride_pc   the ride from floor 1 down to floor 5, passing floor 5's shaft
	  ui_elevator_banner_pc the arrival: "FLOOR 5 · STORMGLASS RIFT"
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any, workspace: any): { [string]: any }
	require("./mine_floor_scene").build(Loader, workspace, 5)
	local UI = "StarterPlayer.StarterPlayerScripts.Client.UI."
	local ElevatorWindow = Loader.requirePath(UI .. "ElevatorWindow")
	local RideView = Loader.requirePath(UI .. "ElevatorRideView")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")

	local PC = 1.25 -- 900 px tall render / 720 design height
	local PHONE = 0.62 * 900 / 375 -- a 667 x 375 pt phone at uiScale 0.62, scaled up to the render
	local riftPrice = MineFloors.priceOf(5)

	-- the owner's picture: the Sunken Palace bought, the Rift to buy
	local palace = { [MineFloors.get(4).Id] = true }

	local function window(compact: boolean, level: number, here: number, bought: any, coins: number, scrolled: boolean?): any
		local refs = ElevatorWindow.build(compact)
		refs.Gui.Enabled = true
		refs.Gui.Scale.Scale = if compact then PHONE else PC
		if compact then
			ElevatorWindow.layout(refs, 667 / 0.62, (375 - 36) / 0.62)
			ElevatorWindow.setHint(refs, "")
		else
			ElevatorWindow.layout(refs, 1280, (900 - 36) / PC)
			ElevatorWindow.setHint(refs, "Click a floor  ·  Backspace: close")
		end
		ElevatorWindow.setFloors(refs, ElevatorWindow.entries(level, here, bought, coins))
		ElevatorWindow.setStatus(refs, level, coins)
		if scrolled then
			local grid = refs.Grid
			grid.CanvasPosition = roblox.Vector2.new(0, math.max(0, grid.CanvasSize.Y.Offset - grid.Size.Y.Offset))
		end
		return UiExport.export({ refs.Gui })
	end

	local function ride(arrived: boolean): any
		local refs = RideView.build()
		refs.Gui.Enabled = true
		RideView.layout(refs, PC, 36)
		local name = MineFloors.get(5).Name
		local r = RideView.newRide(1, 5, name, ElevatorService.rideTime(1, 5), ElevatorService.DoorsClose, false)
		RideView.setRide(refs, r)
		if arrived then
			r.OpenAt = r.MinRide
			RideView.pose(refs, r, r.OpenAt + RideView.Timing.BannerDelay + RideView.Timing.BannerIn + 0.2)
		else
			RideView.pose(refs, r, r.MinRide - 0.05)
		end
		return UiExport.export({ refs.Gui })
	end

	local exports = {
		ui_elevator_pc = window(false, 8, 1, palace, riftPrice + 1.25e6),
		ui_elevator_pc_poor = window(false, 8, 1, palace, math.floor(riftPrice * 0.6)),
		ui_elevator_pc_new = window(false, 1, 1, {}, 250),
		ui_elevator_phone = window(true, 8, 1, palace, riftPrice + 1.25e6),
		ui_elevator_phone_end = window(true, 8, 1, palace, riftPrice + 1.25e6, true),
		ui_elevator_ride_pc = ride(false),
		ui_elevator_banner_pc = ride(true),
	}
	-- before the owner's upload of the pictures: the painted backdrops
	local preview = IconAssets.ElevatorArt.Preview
	IconAssets.ElevatorArt.Preview = false
	exports.ui_elevator_pc_bare = window(false, 8, 1, palace, riftPrice + 1.25e6)
	IconAssets.ElevatorArt.Preview = preview
	return exports
end

return Preview
