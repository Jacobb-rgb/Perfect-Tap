--[[
	Preview-only setup for step 3 WP-Belts (scene "belts" in
	tools/lune/export_scene.luau, shots in tools/preview/belts_shots.json).
	The world, then a small factory line on plot 5 built with the REAL
	services (MachineService places the machines, ConveyorService builds the
	chute plates and signs and opens the rails, PenService builds the
	sorting board), with fake save data for the owner:
	  PEN chute    belt -> belt -> Cleaning Plant -> belt -> belt -> Iron Box
	               -> belts -> Clay Furnace -> belts along the edge and up
	               the right side -> the back wall (the FOUNDRY chute's old
	               sink went with the Foundry, owner 2026-10-24)
	  TRAIN chute  belt -> belts that join the PEN line from the side (a T)
	  dirty ore on the PEN / TRAIN belts, clean ore after the plant, ingots
	  on the way to the wall; Pen Automation 1 (the sorting board)
	Also writes build/preview/belts_build.json: the same plus build mode's
	grid and chute plates (GridOverlay), and the UI overlays:
	  ui_belts_pen        HUD + the Ore Pen panel with the send toolbar (PC)
	  ui_belts_pen_phone  the same at the phone scale (compact layout)
	  ui_belts_train      HUD + the train chip while Direct Unload waits ("Belt full")
	  ui_belts_train_phone  the same on a phone
	The preview can't draw BillboardGuis (build mode's chute labels) or
	SurfaceGui frames (belt faces are painted with machines_gallery.paintGuis).
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")
local Export = require("./export")
local UiExport = require("./uiexport")
local Gallery = require("./machines_gallery")

local BeltsPreview = {}

BeltsPreview.Plot = 5
BeltsPreview.BuildPlot = 6 -- the empty east plot next to it: build mode's chute plates
BeltsPreview.UserId = 9001

-- machine, min cell, rotation (r0 faces the road, r2 the yard)
BeltsPreview.Layout = {
	{ Id = "Conveyor", X = 3, Z = 11, R = 0 }, -- PEN chute
	{ Id = "Conveyor", X = 3, Z = 10, R = 0 },
	{ Id = "Conveyor", X = 3, Z = 9, R = 0 },
	{ Id = "AutoCleaner", X = 2, Z = 7, R = 0 },
	{ Id = "Conveyor", X = 3, Z = 6, R = 0 },
	{ Id = "Conveyor", X = 3, Z = 5, R = 0 },
	{ Id = "IronBox", X = 2, Z = 3, R = 0 },
	{ Id = "Conveyor", X = 3, Z = 2, R = 1 },
	{ Id = "Conveyor", X = 4, Z = 2, R = 1 },
	{ Id = "Conveyor", X = 5, Z = 2, R = 1 },
	{ Id = "ClayFurnace", X = 6, Z = 1, R = 0 },
	{ Id = "Conveyor", X = 7, Z = 0, R = 1 },
	{ Id = "Conveyor", X = 8, Z = 0, R = 1 },
	{ Id = "Conveyor", X = 9, Z = 0, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 1, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 2, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 3, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 4, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 5, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 6, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 7, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 8, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 9, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 10, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 11, R = 2 }, -- (the old FOUNDRY chute's cell)
	{ Id = "Conveyor", X = 6, Z = 11, R = 0 }, -- TRAIN chute
	{ Id = "Conveyor", X = 6, Z = 10, R = 3 },
	{ Id = "Conveyor", X = 5, Z = 10, R = 3 },
	{ Id = "Conveyor", X = 4, Z = 10, R = 3 }, -- into the PEN line's side
}

BeltsPreview.Pen = {
	["Raw|Copper||"] = 7,
	["Raw|Gold||"] = 3,
	["Clean|Silver|Clean|"] = 2,
	["Clean|Amethyst|Pristine|"] = 2,
	["Clean|Copper|Rough|"] = 4,
	["Ingot|Iron|Clean|"] = 2,
}

function BeltsPreview.build(Loader: any, workspace: any): { [string]: any }
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local WorldService = Loader.requirePath("ServerScriptService.Server.Services.WorldService")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local ConveyorService = Loader.requirePath("ServerScriptService.Server.Services.ConveyorService")
	local PenService = Loader.requirePath("ServerScriptService.Server.Services.PenService")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local PenView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.PenView")
	local GridOverlay = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.GridOverlay")
	local Players = Loader.game:GetService("Players")

	local plotId = BeltsPreview.Plot
	local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[plotId])
	WorldService.Map = workspace:FindFirstChild("Map")

	-- the owner and their save (fakes; the services are the real ones)
	local player: any = { UserId = BeltsPreview.UserId, Name = "Preview", Parent = true }
	player.GetAttribute = function()
		return nil
	end
	local data = table.clone(DataTemplate)
	data.Upgrades = table.clone(DataTemplate.Upgrades)
	data.Upgrades.PenAutomation = 1
	data.StarterKitGiven = true
	data.PlacedMachines = {}
	data.MachineInventory = { Conveyor = 40, AutoCleaner = 1, IronBox = 1, ClayFurnace = 1 }
	data.Storage = {}
	for key, n in BeltsPreview.Pen do
		local desc = ItemData.parseKey(key)
		for _ = 1, n do
			table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
		end
	end
	rawset(DataService, "get", function(p)
		return if p == player then data else nil
	end)
	rawset(DataService, "changed", function() end)
	-- no clients here: toasts (the billboard's first-send one) go nowhere
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	rawset(Net, "fire", function() end)
	rawset(PlotService, "plotOf", function(p)
		return if p == player then plotId else nil
	end)
	rawset(PlotService, "ownerOf", function(id)
		return if id == plotId then player else nil
	end)
	rawset(Players, "GetPlayerByUserId", function(_, id)
		return if id == player.UserId then player else nil
	end)

	-- the machines and belts, through MachineService (as build mode places them)
	MachineService.register("Conveyor", ConveyorService._test.behaviour)
	MachineService._test.spawnAll(player, plotId)
	local byCell = {}
	for _, entry in BeltsPreview.Layout do
		local m, code = MachineService.place(player, entry.Id, entry.X, entry.Z, entry.R)
		assert(m, `preview layout: {entry.Id} at {entry.X},{entry.Z}: {code}`)
		byCell[`{entry.X},{entry.Z}`] = m
	end
	-- every plot gets its chute plates and signs (as ConveyorService.start does)
	for _, plot in WorldLayout.Plots do
		ConveyorService._test.buildMarkers(plot.Id)
	end
	ConveyorService._test.onLayout(player, plotId)
	-- the board says "Sending 9…": the billboard queued the dirty ore
	PenService.arrived(player, { { K = "Raw", O = "Copper" } }, "Pen")
	PenService._test.queue(player).Pen.Intents[1].Left = 9
	PenService._test.updateBoard(plotId)

	-- what the preview can't draw: the belts' painted faces
	local paint = roblox.Instance.new("Model")
	paint.Name = "BeltPaint"
	paint.Parent = workspace
	for _, m in MachineService.ofPlot(plotId) do
		if m.Info.IsConveyor then
			Gallery.paintGuis(Loader, paint, m.Model)
		end
	end

	-- items riding the line
	local items = roblox.Instance.new("Model")
	items.Name = "PreviewItems"
	items.Parent = workspace
	local function ride(cell: string, kind: string, oreId: string, grade: string?, z: number, seed: number)
		local m = byCell[cell]
		local belt = m.Model:FindFirstChild("Belt")
		local top = belt.CFrame.Position.Y + belt.Size.Y / 2
		local item = ItemBuilder.build(
			{ Kind = kind, OreId = oreId, Grade = grade },
			m.Model:GetPivot() * CF.new(0, 2, z) * CF.Angles(0, seed, 0),
			seed
		)
		local low = math.huge
		for _, d in item:GetDescendants() do
			if d:IsA("BasePart") then
				local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
				local half = math.abs(r10) * d.Size.X / 2 + math.abs(r11) * d.Size.Y / 2 + math.abs(r12) * d.Size.Z / 2
				low = math.min(low, d.CFrame.Position.Y - half)
			end
		end
		for _, d in item:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + V3.new(0, top - low, 0)
			end
			if d:IsA("ParticleEmitter") then
				d:Destroy()
			end
		end
		item.Parent = items
	end
	ride("3,11", "Raw", "Copper", nil, 0.4, 1)
	ride("3,10", "Raw", "Gold", nil, -1.2, 2)
	ride("3,9", "Raw", "Copper", nil, 0.8, 3)
	ride("6,11", "Raw", "Iron", nil, -0.6, 4)
	ride("5,10", "Raw", "Coal", nil, 0.2, 5)
	ride("3,6", "Clean", "Silver", "Clean", -0.4, 6)
	ride("4,2", "Clean", "Copper", "Rough", 0.3, 7)
	ride("9,3", "Ingot", "Copper", "Rough", 0.5, 8)
	ride("9,7", "Ingot", "Iron", "Clean", -0.8, 9)
	ride("9,10", "Ingot", "Silver", "Clean", 0.6, 10)

	-- points for the shots (world space)
	local function world(localPos: any): any
		return (plotCF * CF.new(localPos)).Position
	end
	for _, name in BaseLayout.ChuteNames do
		local p = world(BaseLayout.chuteLocal(name))
		print(string.format("  chute %-8s %7.1f %5.1f %7.1f", name, p.X, p.Y, p.Z))
	end
	local board = world(PenService.BoardCenter)
	print(string.format("  sort board    %7.1f %5.1f %7.1f", board.X, board.Y, board.Z))
	local center = world(V3.new(0, 0, 0))
	print(string.format("  plot centre   %7.1f %5.1f %7.1f  look %s", center.X, center.Y, center.Z, tostring(plotCF.LookVector)))

	-- UI: the pen panel with the send toolbar
	local function hud(scale: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = scale
		refs.Coins.Text = Format.money(84210)
		refs.Income.Text = Format.perSecond(312)
		refs.Income.TextColor3 = roblox.Color3.fromRGB(110, 214, 92)
		return refs
	end
	-- `inset`: the render's top bar (pixels), like the shot's uiInset
	local function pen(compact: boolean, scale: number, inset: number): any
		local refs = PenView.build()
		refs.Gui.Scale.Scale = scale
		refs.Gui.Enabled = true
		-- the screen in design units, as PenController measures it (1600 x 900 renders)
		PenView.setCompact(refs, compact, roblox.Vector2.new(1600 / scale, (900 - inset) / scale))
		PenView.setMode(refs, "Pen", nil)
		PenView.setAutoSort(refs, true, true)
		local total = 0
		for _, n in BeltsPreview.Pen do
			total += n
		end
		PenView.setHeader(refs, total, 60)
		local entries = PenView.entries(BeltsPreview.Pen, "Pen")
		PenView.setEntries(refs, entries, true)
		-- the State the server sends (the same count as the board)
		local snapshot: any = {}
		PenService._test.provide(player, data, snapshot)
		PenView.setSending(refs, snapshot.PenSend, true, 10)
		PenView.setHint(
			refs,
			if compact
				then "TAKE: carry it  -  SEND: onto your belts (twice: all)  -  PODIUM: money every second"
				else "TAKE: to your hands  -  SEND: to your belts (twice: all)  -  PODIUM: money/s  -  Backspace: close",
			nil,
			nil
		)
		-- a SEND just pressed on the amethyst row: a second press sends the whole stack
		local row = refs.Rows["Clean|Amethyst|Pristine|"]
		if row then
			row.Send.Text = PenView.sendButtonText(BeltsPreview.Pen["Clean|Amethyst|Pristine|"])
		end
		return refs
	end
	local scale = 1.25 -- 900 px tall render / 720 design height
	local exports: { [string]: any } = {}
	exports.ui_belts_pen = UiExport.export({ hud(scale).Gui, pen(false, scale, 0).Gui })
	local phoneScale = 0.62 * 900 / 375 -- an iPhone SE-sized screen at the 0.62 phone floor
	exports.ui_belts_pen_phone = UiExport.export({ hud(phoneScale).Gui, pen(true, phoneScale, 58).Gui })
	-- the train chip while Direct Unload waits for room on the TRAIN chute's belt
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
	local function trainChip(uiScale: number, compact: boolean, inset: number): any
		local refs = TrainView.build(compact)
		refs.Chip.Scale.Scale = uiScale
		refs.Gui.Scale.Scale = uiScale
		TrainView.layout(refs, compact, 1600 / uiScale, (900 - inset) / uiScale)
		refs.ChipKey.Visible = not compact
		local train = TrainView.read({
			Cargo = 0,
			Capacity = 8,
			Moving = 5,
			DepartAt = 100,
			ArriveAt = 130,
			Unloading = true,
			UnloadWait = "Jammed",
		})
		TrainView.setStatus(refs, TrainView.status(train, 140, nil))
		TrainView.setColor(refs, BaseLayout.Chutes.Train.Color)
		refs.Gui.Enabled = false
		refs.Chip.Enabled = TrainView.chipVisible(true, false)
		return refs
	end
	exports.ui_belts_train = UiExport.export({ hud(scale).Gui, trainChip(scale, false, 0).Chip })
	local trainPhone = TrainView.PhoneScale * 900 / 375
	exports.ui_belts_train_phone = UiExport.export({ hud(trainPhone).Gui, trainChip(trainPhone, true, 58).Chip })

	-- build mode on the empty plot next door (BuildPlot): the grid and the
	-- chute plates, written as belts_build.json right here (then taken away
	-- again for the normal scene). show() places the lines, then parents the
	-- folder to the game's Workspace, a stand-in under Lune: the folder goes
	-- into this scene instead.
	local buildCF = WorldLayout.plotCFrame(WorldLayout.Plots[BeltsPreview.BuildPlot])
	pcall(GridOverlay.show, buildCF)
	for _, name in BaseLayout.ChuteNames do
		local chute = BaseLayout.Chutes[name]
		local cell = BaseLayout.chuteLocal(name)
		GridOverlay.plate("Chute" .. name, buildCF * CF.new(cell.X, 0.05, cell.Z), 4, 4, chute.Color)
	end
	local overlay = GridOverlay.folder()
	overlay.Parent = workspace
	local buildScene = Export.collect(workspace)
	local presets = {}
	for name, preset in LightingConfig.Presets do
		local out = {}
		for group, values in preset do
			out[group] = {}
			for key, value in values do
				out[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
			end
		end
		presets[name] = out
	end
	buildScene.presets = presets
	fs.writeDir(Loader.root .. "/build/preview")
	fs.writeFile(Loader.root .. "/build/preview/belts_build.json", serde.encode("json", buildScene))
	print(string.format("Exported belts_build: %d parts", #buildScene.parts))
	overlay.Parent = nil
	return exports
end

return BeltsPreview
