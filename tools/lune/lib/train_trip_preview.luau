--[[
	Ore train trips in the world (scene "train_trip" for
	tools/lune/export_scene.luau, shots in tools/preview/train_trip_shots.json).
	Everything is placed with the game's own code: TrainController.poseAt /
	stopAt / parkedPose / buildConsist / placeConsist / pourMouth / penSpot /
	arcHeight / arc and TrainView.
	  - plot 3's train (west line) on its coast leg, passing behind plot 1
	  - plot 2's train (west line) unloading: its wagons alongside its Ore Pen,
	    the hoppers tipped toward it, ore chunks in the air
	  - plot 5's train (east line) unloading the same way
	  - your train (plot 6) waiting at the Mine Station with a 6/8 load, its
	    first wagon under the loading chute
	Steam shows as one or two small soft puffs over a standing chimney and a
	short trail behind a moving one, dust as a few small puffs over the hopper
	lips (the renderer draws every smoke emitter as the same big cloud). When
	the map has no Railway yet (the world package builds it), straight
	TrainBuilder tracks are laid along TrainConfig's lines and the yards'
	placeholder track pieces are removed, so the picture shows the finished
	line.
	UI overlays (build/preview/<name>.json):
	  ui_train_hud         HUD + the train chip ("On its way", the ore on board)
	  ui_train_panel       HUD + chip + the Mine Station panel (PC)
	  ui_train_phone       the panel on a 667 x 375 pt phone (compact layout)
	  ui_train_phone_small the panel on a 568 x 320 pt phone (narrow rows)
	  ui_train_hud_phone   the chip on a phone, the train waiting at a full pen
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

Preview.CoastPlot = 3 -- its train passes behind plot 1...
Preview.CoastZ = 78 -- ...with its locomotive here
Preview.UnloadPlot = 2 -- a west plot: the yard is mirrored, the pen lies north of the plot centre
Preview.UnloadEastPlot = 5
Preview.UnloadSeconds = 0.62 -- after the unload began: tipped, the load sliding out
Preview.StationPlot = 6 -- an east plot: the waiting train faces the east portal
Preview.Coins = 12480

local function lookup(Loader: any, path: string): any
	return Loader.requirePath(path)
end

local function puff(parent: any, at: any, size: number, color: any, transparency: number)
	local p = roblox.Instance.new("Part")
	p.Name = "Puff"
	p.Shape = roblox.Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Material = roblox.Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = transparency
	p.Size = roblox.Vector3.new(size, size, size)
	p.CFrame = roblox.CFrame.new(at)
	p.Parent = parent
	return p
end

-- Steam over a chimney top: two small puffs when standing, a short trail drifting `back` when moving.
local function steam(parent: any, top: any, back: any, moving: boolean)
	local white = roblox.Color3.fromRGB(246, 246, 250)
	local V3 = roblox.Vector3
	if not moving then
		puff(parent, top + V3.new(0, 0.6, 0), 0.9, white, 0.25)
		puff(parent, top + V3.new(0.25, 1.6, 0.1), 1.3, white, 0.45)
		return
	end
	local trail = {
		{ Up = 0.6, Back = 0.2, Size = 1.0, Fade = 0.2 },
		{ Up = 1.5, Back = 1.3, Size = 1.5, Fade = 0.4 },
		{ Up = 2.4, Back = 2.9, Size = 2.0, Fade = 0.6 },
	}
	for _, s in trail do
		puff(parent, top + V3.new(0, s.Up, 0) + back * s.Back, s.Size, white, s.Fade)
	end
end

-- Builds a consist for a pose and places it (what the PreRender loop does).
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
		steam(parent, top, -pose.Facing, pose.Speed > 1)
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

-- The server time on a plot's coast leg when its locomotive passes world z `z`.
local function coastTimeAt(TrainController: any, plot: any, depart: number, arrive: number, wagons: number, z: number): number
	local s = TrainController.legSpans(arrive - depart)
	local lo, hi = depart + s.Underground, depart + s.Coast
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		local p = TrainController.poseAt(plot, depart, arrive, mid, wagons)
		if p.Position.Z > z then
			lo = mid
		else
			hi = mid
		end
	end
	return (lo + hi) / 2
end

function Preview.build(Loader: any, workspace: any): { [string]: any }
	local WorldLayout = lookup(Loader, "ReplicatedStorage.Shared.Config.WorldLayout")
	local OreData = lookup(Loader, "ReplicatedStorage.Shared.Config.OreData")
	local Format = lookup(Loader, "ReplicatedStorage.Shared.Util.Format")
	local Rarity = lookup(Loader, "ReplicatedStorage.Shared.Config.Rarity")
	local ItemBuilder = lookup(Loader, "ReplicatedStorage.Shared.Builders.ItemBuilder")
	local Geo = lookup(Loader, "ReplicatedStorage.Shared.Builders.Geo")
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

	-- 1) plot 3's train on the coast leg, behind plot 1 (2 wagons: a 14-item trip of dirty and clean ore)
	local coastPlot = WorldLayout.Plots[Preview.CoastPlot]
	local coastAt = coastTimeAt(TrainController, coastPlot, depart, arrive, 2, Preview.CoastZ)
	local coastPose = TrainController.poseAt(coastPlot, depart, arrive, coastAt, 2)
	local coastLoad = { ItemBuilder.DirtyCrust, OreData.ById.Copper.Color, OreData.ById.Silver.Color }
	train(
		Loader,
		folder,
		coastPose,
		TrainController.BannerColors[Preview.CoastPlot],
		TrainController.splitLoad(coastLoad, 2),
		TrainController.wagonFlip(coastPlot)
	)

	-- 2) unloading trains (west plot 2, east plot 5): tipped, ore in the air
	local function unload(plotId: number, ids: { string })
		local plot = WorldLayout.Plots[plotId]
		local unloadAt = arrive + 0.3
		local pose = TrainController.poseAt(plot, depart, arrive, unloadAt + Preview.UnloadSeconds, 2, unloadAt)
		local load = oreColors(ids)
		local consist = train(
			Loader,
			folder,
			pose,
			TrainController.BannerColors[plotId],
			TrainController.splitLoad(load, 2),
			TrainController.wagonFlip(plot)
		)
		local side = TrainController.penSide(plot)
		for w = 2, #consist.Vehicles do
			local mouth = TrainController.pourMouth(pose, consist.Vehicles[w].Offset, plot)
			for i = 1, 4 do
				local t = 0.14 + (i - 1) * 0.2 + (w - 2) * 0.07
				local from = mouth + pose.Facing * (((i * 7 + w) % 5) / 5 - 0.5) * 3
				local to = TrainController.penSpot(plot, ((i * 37 + w * 11) % 10) / 10, ((i * 53 + w * 7) % 10) / 10, mouth)
				local height = TrainController.arcHeight(plot, from, to, 5 + (i % 3))
				local at = TrainController.arc(from, to, height, t)
				local size = 0.9 + ((i + w) % 3) * 0.2
				local chunk = Geo.block(
					folder,
					CF.new(at) * CF.Angles(i * 1.3, i * 0.7 + w, i * 0.4),
					V3.new(size, size * 0.8, size),
					load[(i + w) % #load + 1]
				)
				chunk.Name = "OreChunk"
			end
			-- the dust puff over the tipped hopper's lip (Vfx "Dust" in the game)
			local dust = C3.fromRGB(222, 204, 178)
			for k = 0, 2 do
				local spot = mouth + side * (0.6 + k * 0.7) + V3.new(0, 0.3 + (k % 2) * 0.5, 0) - pose.Facing * ((k - 1) * 2.2)
				puff(folder, spot, 0.9 + (k % 2) * 0.35, dust, 0.35)
			end
		end
	end
	unload(Preview.UnloadPlot, { "Gold", "Copper", "Amethyst", "Iron", "Silver", "Coal" })
	unload(Preview.UnloadEastPlot, { "Copper", "Iron", "Silver", "Coal", "Gold", "Copper" })

	-- 3) your train waiting at the Mine Station, 6 of 8 loaded (dirty ore: the warm clay load)
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
	local phoneScale = TrainView.PhoneScale * 900 / 375 -- a 667 x 375 pt phone scaled up to the render
	local smallScale = TrainView.PhoneScale * 900 / 320 -- a 568 x 320 pt phone
	local smallInset = math.floor(58 * 900 / 320) -- its 58 pt top bar, in render pixels

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
		refs.Chip.Enabled = TrainView.chipVisible(true, open, compact)
		return refs
	end

	local moving = { Cargo = 0, Capacity = 8, Moving = 8, DepartAt = 100, ArriveAt = 130, AutoDepartIn = nil }
	local penFull = { Cargo = 0, Capacity = 8, Moving = 8, DepartAt = 100, ArriveAt = 130, Waiting = true }
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
	local smallHud = hud(smallScale)
	smallHud.Toasts:ClearAllChildren()
	local small = view(waiting, 0, smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale, true)
	exports.ui_train_phone_small = UiExport.export({ smallHud.Gui, small.Chip, small.Gui })
	local phoneChip = view(penFull, 160, phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, false)
	local phoneHud2 = hud(phoneScale)
	phoneHud2.Toasts:ClearAllChildren()
	HudView.toast(phoneHud2.Toasts, "Your Ore Pen is full – make room", C3.fromRGB(236, 84, 70))
	exports.ui_train_hud_phone = UiExport.export({ phoneHud2.Gui, phoneChip.Chip })
	return exports
end

return Preview
