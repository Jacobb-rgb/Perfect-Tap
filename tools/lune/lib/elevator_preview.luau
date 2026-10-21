--[[
	The mine elevator's UI over the Stormglass Rift (scene "elevator_ui" for
	tools/lune/export_scene.luau, shots in tools/preview/mine_floor5_shots.json):
	the floor list with its 7 cards and the ride to floor 5, drawn with the
	game's own ElevatorView / ElevatorRideView. The floor area behind is the
	mine_floor scene of floor 5 (MineFloorScene).

	UI overlays (build/preview/<name>.json), each rendered at 1600 x 900 px:
	  ui_elevator_floors_pc     PC (1280 x 720 design units): 4 + 3 cards, blaster 8, at floor 5
	  ui_elevator_floors_phone  667 x 375 pt phone (uiScale 0.62): 3 a row, the last row scrolls
	  ui_elevator_floors_phone_small  a 568 x 320 pt phone
	  ui_elevator_buy_pc        PC: the Buy page (enough coins: a green BUY)
	  ui_elevator_buy_phone     the phone's Buy page (a third of the price: BUY greyed out with a lock)
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

	-- a small 568 x 320 pt phone (the cards shrink: no mode line, a locked card's chips make room for its pill)
	local function floorsSmall(): any
		local refs = ElevatorView.build(true)
		refs.Gui.Enabled = true
		refs.Gui.Scale.Scale = 0.62 * 900 / 320
		ElevatorView.setMode(refs, "Floors")
		ElevatorView.layout(refs, true, 568 / 0.62, (320 - 36) / 0.62)
		ElevatorView.setHint(refs, "Touch", "Tap GO to ride")
		ElevatorView.setFloors(refs, ElevatorView.entries(8, 5), 8)
		ElevatorView.pose(refs, ElevatorView.OpenTime)
		return UiExport.export({ refs.Gui })
	end

	-- the Buy page (not owned yet): `coins` short of the price greys BUY out
	local function buy(compact: boolean, coins: number): any
		local refs = ElevatorView.build(compact)
		refs.Gui.Enabled = true
		refs.Gui.Scale.Scale = if compact then PHONE else PC
		ElevatorView.setMode(refs, "Buy")
		if compact then
			ElevatorView.layout(refs, true, 667 / 0.62, (375 - 36) / 0.62)
			ElevatorView.setHint(refs, "Touch", "Buy once, ride forever")
		else
			ElevatorView.layout(refs, false, 1280, (900 - 36) / PC)
			ElevatorView.setHint(refs, "Mouse", "Buy once, ride forever · Backspace: close")
		end
		ElevatorView.setPurchase(refs, coins, MineFloors.Elevator.Price)
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
		ui_elevator_floors_phone_small = floorsSmall(),
		ui_elevator_buy_pc = buy(false, MineFloors.Elevator.Price * 2),
		ui_elevator_buy_phone = buy(true, MineFloors.Elevator.Price / 3),
		ui_elevator_ride_pc = ride(false),
		ui_elevator_banner_pc = ride(true),
	}
end

return Preview
