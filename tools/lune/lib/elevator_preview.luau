--[[
	The mine elevator's UI over the Stormglass Rift (scene "elevator_ui" for
	tools/lune/export_scene.luau, shots in tools/preview/mine_floor5_shots.json):
	the floor list with its 7 cards and the ride to floor 5, drawn with the
	game's own ElevatorView / ElevatorRideView. The floor area behind is the
	mine_floor scene of floor 5 (MineFloorScene).

	UI overlays (build/preview/<name>.json), each rendered at 1600 x 900 px:
	  ui_elevator_floors_pc     PC (1280 x 720 design units): 4 + 3 cards, blaster 8, at floor 5
	  ui_elevator_floors_phone  667 x 375 pt phone (uiScale 0.62): 3 a row, the last row scrolls
	  ui_elevator_ride_pc       the ride from floor 1 down to floor 5, passing floor 5's shaft
	  ui_elevator_banner_pc     the arrival: "FLOOR 5 · STORMGLASS RIFT"
]]

local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any, workspace: any): { [string]: any }
	require("./mine_floor_scene").build(Loader, workspace, 5)
	local UI = "StarterPlayer.StarterPlayerScripts.Client.UI."
	local ElevatorView = Loader.requirePath(UI .. "ElevatorView")
	local RideView = Loader.requirePath(UI .. "ElevatorRideView")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")

	local PC = 1.25 -- 900 px tall render / 720 design height
	local PHONE = 0.62 * 900 / 375 -- a 667 x 375 pt phone at uiScale 0.62, scaled up to the render

	local function floors(compact: boolean): any
		local refs = ElevatorView.build(compact)
		refs.Gui.Enabled = true
		refs.Gui.Scale.Scale = if compact then PHONE else PC
		ElevatorView.setMode(refs, "Floors")
		if compact then
			ElevatorView.layout(refs, true, 667 / 0.62, (375 - 36) / 0.62)
			ElevatorView.setHint(refs, "Touch", "Tap GO to ride")
		else
			ElevatorView.layout(refs, false, 1280, (900 - 36) / PC)
		end
		ElevatorView.setFloors(refs, ElevatorView.entries(8, 5), 8)
		ElevatorView.pose(refs, ElevatorView.OpenTime)
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

	return {
		ui_elevator_floors_pc = floors(false),
		ui_elevator_floors_phone = floors(true),
		ui_elevator_ride_pc = ride(false),
		ui_elevator_banner_pc = ride(true),
	}
end

return Preview
