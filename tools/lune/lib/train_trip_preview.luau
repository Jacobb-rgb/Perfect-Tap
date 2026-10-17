--[[
	Ore train trips in the world (scene "train_trip" for
	tools/lune/export_scene.luau, shots in tools/preview/train_trip_shots.json).
	Everything is placed with the game's own code: TrainController.poseAt /
	parkedPose / buildConsist / placeConsist / pourMouth / arc and TrainView.
	  - plot 2's train (west line) on its coast leg, passing behind plot 1
	  - plot 5's train (east line) unloading: the hoppers tipped toward its Ore
	    Pen, ore chunks in the air
	  - your train waiting at the Mine Station with a 6/8 load
	Steam shows as a few soft puffs (the renderer draws every smoke emitter as
	the same big cloud). When the map has no Railway yet (the world package
	builds it), straight TrainBuilder tracks are laid along TrainConfig's lines
	and the yards' placeholder track pieces are removed, so the picture shows
	the finished line.
	UI overlays (build/preview/<name>.json):
	  ui_train_hud     HUD + the train chip ("On its way")
	  ui_train_panel   HUD + chip + the Mine Station panel (PC)
	  ui_train_phone   the same at the phone scale (compact layout)
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

Preview.CoastPlot = 2 -- its train passes behind plot 1
Preview.CoastShare = 0.85 -- of the trip: on the coast leg, behind plot 1's yard
Preview.UnloadPlot = 5
Preview.UnloadShare = 0.9705 -- tipped 90 %: the load is sliding out
Preview.StationPlot = 6 -- an east plot: the waiting train faces the east portal
Preview.Coins = 12480

local function lookup(Loader: any, path: string): any
	return Loader.requirePath(path)
end

-- Soft steam puffs over a chimney top, drifting toward `back` (opaque balls:
-- see tools/lune/lib/train_gallery.luau).
local function steam(parent: any, top: any, back: any, drift: number)
	local white = roblox.Color3.fromRGB(242, 242, 248)
	local sky = roblox.Color3.fromRGB(236, 214, 230)
	local puffs = {
		{ Up = 0.7, Back = 0.1, Size = 1.4, Fade = 0 },
		{ Up = 2.0, Back = 0.9, Size = 2.2, Fade = 0.25 },
		{ Up = 3.6, Back = 2.3, Size = 3.0, Fade = 0.5 },
		{ Up = 5.3, Back = 4.3, Size = 3.8, Fade = 0.75 },
	}
	for _, puff in puffs do
		local p = roblox.Instance.new("Part")
		p.Name = "SteamPuff"
		p.Shape = roblox.Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Material = roblox.Enum.Material.SmoothPlastic
		p.Color = white:Lerp(sky, puff.Fade)
		p.Size = roblox.Vector3.new(puff.Size, puff.Size, puff.Size)
		p.CFrame = roblox.CFrame.new(top + roblox.Vector3.new(0, puff.Up, 0) + back * (puff.Back * drift))
		p.Parent = parent
	end
end

-- Builds a consist for a pose and places it (what the RenderStepped loop does).
local function train(Loader: any, parent: any, pose: any, color: any, loads: { any }, flip: boolean, fills: { number }?): any
	local TrainController = lookup(Loader, "StarterPlayer.StarterPlayerScripts.Client.Controllers.TrainController")
	local consist = TrainController.buildConsist(color, loads, flip)
	if fills then
		for i, fill in fills do
			local wagon = consist.Vehicles[i + 1]
			if wagon and wagon.Loaded then
				TrainController.setFill(wagon, fill)
			end
		end
	end
	TrainController.applyPour(consist, pose)
	local parts, cframes = {}, {}
	TrainController.placeConsist(consist, pose, parent, parts, cframes)
	for i, part in parts do
		part.CFrame = cframes[i]
	end
	local loco = consist.Vehicles[1]
	if loco.Shown and loco.Smoke then
		local smoke = loco.Smoke
		local top = (smoke.Parent.CFrame * smoke.CFrame).Position
		steam(parent, top, -pose.Facing, if pose.Speed > 1 then 1 else 0.25)
	end
	return consist
end

-- Straight preview tracks along TrainConfig's lines when the map has no Railway.
local function rails(Loader: any, workspace: any, parent: any)
	local map = workspace:FindFirstChild("Map")
	if map and map:FindFirstChild("Railway") then
		return
	end
	local TrainConfig = lookup(Loader, "ReplicatedStorage.Shared.Config.TrainConfig")
	local TrainBuilder = lookup(Loader, "ReplicatedStorage.Shared.Builders.TrainBuilder")
	local CF = Loader.CFrame
	local placeholders = {}
	for _, d in workspace:GetDescendants() do
		if d:GetAttribute("RailwayPlaceholder") then
			table.insert(placeholders, d)
		end
	end
	for _, d in placeholders do
		d:Destroy()
	end
	for _, line in { TrainConfig.QuarryLine, TrainConfig.CoastWest, TrainConfig.CoastEast } do
		for i = 1, #line - 1 do
			local a, b = line[i], line[i + 1]
			local track = TrainBuilder.track((b - a).Magnitude)
			track:PivotTo(CF.lookAt((a + b) / 2, b))
			track.Parent = parent
		end
	end
end

function Preview.build(Loader: any, workspace: any): { [string]: any }
	local WorldLayout = lookup(Loader, "ReplicatedStorage.Shared.Config.WorldLayout")
	local OreData = lookup(Loader, "ReplicatedStorage.Shared.Config.OreData")
	local Format = lookup(Loader, "ReplicatedStorage.Shared.Util.Format")
	local Rarity = lookup(Loader, "ReplicatedStorage.Shared.Config.Rarity")
	local TrainController = lookup(Loader, "StarterPlayer.StarterPlayerScripts.Client.Controllers.TrainController")
	local TrainView = lookup(Loader, "StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
	local HudView = lookup(Loader, "StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local C3 = roblox.Color3
	local V3 = roblox.Vector3
	local CF = Loader.CFrame

	local folder = roblox.Instance.new("Folder")
	folder.Name = "TrainTripPreview"
	folder.Parent = workspace
	rails(Loader, workspace, folder)

	local depart, trip = 1000, 30
	local arrive = depart + trip
	local function oreColors(ids: { string }): { any }
		local colors = {}
		for _, id in ids do
			table.insert(colors, OreData.ById[id].Color)
		end
		return colors
	end

	-- 1) plot 2's train on the coast leg, behind plot 1 (2 wagons: a 14-item trip)
	local coastPlot = WorldLayout.Plots[Preview.CoastPlot]
	local coastPose = TrainController.poseAt(coastPlot, depart, arrive, depart + trip * Preview.CoastShare)
	train(
		Loader,
		folder,
		coastPose,
		TrainController.BannerColors[Preview.CoastPlot],
		TrainController.splitLoad(oreColors({ "Copper", "Iron", "Coal", "Silver", "Tin", "Copper" }), 2),
		TrainController.wagonFlip(coastPlot)
	)

	-- 2) plot 5's train unloading into its pen, ore in the air
	local unloadPlot = WorldLayout.Plots[Preview.UnloadPlot]
	local unloadPose = TrainController.poseAt(unloadPlot, depart, arrive, depart + trip * Preview.UnloadShare)
	local load = oreColors({ "Gold", "Copper", "Amethyst", "Iron", "Silver", "Coal" })
	local consist = train(
		Loader,
		folder,
		unloadPose,
		TrainController.BannerColors[Preview.UnloadPlot],
		TrainController.splitLoad(load, 2),
		TrainController.wagonFlip(unloadPlot)
	)
	local Geo = lookup(Loader, "ReplicatedStorage.Shared.Builders.Geo")
	for w = 2, #consist.Vehicles do
		local mouth = TrainController.pourMouth(unloadPose, consist.Vehicles[w].Offset, unloadPlot)
		for i = 1, 5 do
			local t = 0.12 + (i - 1) * 0.17 + (w - 2) * 0.06
			local to = TrainController.penSpot(unloadPlot, ((i * 37 + w * 11) % 10) / 10, ((i * 53 + w * 7) % 10) / 10)
			local at = TrainController.arc(mouth, to, 8, t)
			local size = 0.9 + ((i + w) % 3) * 0.2
			local chunk = Geo.block(
				folder,
				CF.new(at) * CF.Angles(i * 1.3, i * 0.7 + w, i * 0.4),
				V3.new(size, size * 0.8, size),
				load[(i + w) % #load + 1]
			)
			chunk.Name = "OreChunk"
		end
		-- the dust puff over the tipped hopper (Vfx "Dust" in the game)
		local toward = (TrainController.penCenter(unloadPlot) - mouth)
		toward = V3.new(toward.X, 0, toward.Z).Unit
		for k = 0, 3 do
			local spot = mouth + toward * (1.5 + k * 0.8) + V3.new(0, 1.2 + (k % 2) * 0.9, 0) - unloadPose.Facing * ((k - 1.5) * 1.8)
			local puff = Geo.ball(folder, spot, 1.6 + (k % 3) * 0.5, C3.fromRGB(214, 196, 170))
			puff.CastShadow = false
		end
	end

	-- 3) your train waiting at the Mine Station, 6 of 8 loaded
	local stationPlot = WorldLayout.Plots[Preview.StationPlot]
	local parked = TrainController.parkedPose(stationPlot, nil)
	local fills = TrainController.wagonFills(6, 8, 1)
	train(Loader, folder, parked, TrainController.BannerColors[Preview.StationPlot], TrainController.splitLoad({}, 1), false, fills)

	-- the scene JSON needs at least one emitter: an invisible one far away (see train_gallery)
	local anchor = Geo.block(folder, CF.new(0, -40, -3000), V3.new(1, 1, 1), C3.new(0, 0, 0))
	anchor.Transparency = 1
	local placeholder = roblox.Instance.new("ParticleEmitter")
	placeholder.Texture = "rbxasset://textures/particles/smoke_main.dds"
	placeholder.Parent = anchor

	---------------------------------------------------------------- UI
	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = TrainView.PhoneScale * 900 / 375 -- an iPhone SE-sized screen scaled up to the render

	local function hud(uiScale: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(Preview.Coins)
		refs.Income.Text = Format.perSecond(42)
		refs.Income.TextColor3 = C3.fromRGB(110, 214, 92)
		refs.CarryLabel.Text = "CARRYING 1/3"
		HudView.slot(refs.CarrySlots, nil, 1, true)
		HudView.slot(refs.CarrySlots, nil, 2)
		HudView.slot(refs.CarrySlots, nil, 3)
		HudView.toast(refs.Toasts, "Your train is on its way home!", Rarity.get("Common").Color)
		return refs
	end

	local function view(
		snapshot: { [string]: any },
		now: number,
		uiScale: number,
		compact: boolean,
		maxWidth: number,
		maxHeight: number,
		open: boolean
	): any
		local refs = TrainView.build(compact)
		refs.Chip.Scale.Scale = uiScale
		refs.Gui.Scale.Scale = uiScale
		TrainView.layout(refs, compact, maxWidth, maxHeight)
		refs.ChipKey.Visible = not compact
		local train = TrainView.read(snapshot)
		TrainView.setStatus(refs, TrainView.status(train, now, nil))
		TrainView.setUpgrades(refs, train, Preview.Coins)
		TrainView.setColor(refs, TrainController.BannerColors[Preview.StationPlot])
		refs.Hint.Text = "T: open / close   •   Backspace: close"
		refs.Gui.Enabled = open
		return refs
	end

	local moving = { Cargo = 0, Capacity = 8, Moving = 8, DepartAt = 100, ArriveAt = 130, AutoDepartIn = nil }
	local waiting = { Cargo = 6, Capacity = 8, CapacityLevel = 0, SpeedLevel = 1, AutoDepartIn = 18, TripSeconds = 25 }
	local exports: { [string]: any } = {}
	local hudRefs = hud(scale)
	local chip = view(moving, 118, scale, false, 1600 / scale, (900 - 36) / scale, false)
	exports.ui_train_hud = UiExport.export({ hudRefs.Gui, chip.Chip })
	local panelHud = hud(scale)
	panelHud.Toasts:ClearAllChildren()
	local panel = view(waiting, 0, scale, false, 1600 / scale, (900 - 36) / scale, true)
	exports.ui_train_panel = UiExport.export({ panelHud.Gui, panel.Chip, panel.Gui })
	local phoneHud = hud(phoneScale)
	phoneHud.Toasts:ClearAllChildren()
	local phone = view(waiting, 0, phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, true)
	exports.ui_train_phone = UiExport.export({ phoneHud.Gui, phone.Chip, phone.Gui })
	local phoneChip = view(moving, 118, phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, false)
	local phoneHud2 = hud(phoneScale)
	exports.ui_train_hud_phone = UiExport.export({ phoneHud2.Gui, phoneChip.Chip })
	return exports
end

return Preview
