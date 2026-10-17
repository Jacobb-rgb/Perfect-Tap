--[[
	Preview-only setup for the base yard (WP-Base). Puts sample ores on the
	podiums of plot 5 (an east plot: the sun lights its yard from the pad
	side) and a pile into its Ore Pen (the same builders and
	spots the game uses) and builds the UI overlays:
	  hud_base       the HUD: coins, "+$X/s" income, a "+$X" popup, carry slots
	  ui_pen         HUD + the Ore Pen panel (PC layout)
	  ui_pen_phone   HUD + the Ore Pen panel at the phone scale (compact)
	  ui_offline     HUD + the "While you were away" popup
	Called by tools/lune/export_scene.luau (`lune run tools/lune/export_scene.luau world yard`).
	Shots: tools/preview/yard_shots.json (scene "yard").
]]

local UiExport = require("./uiexport")

local YardPreview = {}

YardPreview.Plot = 5 -- an east plot: the sun lights the yard from the pad side
YardPreview.Podiums = {
	{ K = "Clean", O = "Emerald", G = "Flawless" },
	{ K = "Clean", O = "Stormcore", G = "Pristine" }, -- a wide Epic ore inside the holo-ring
}
YardPreview.Pen = {
	["Raw|Copper||"] = 9,
	["Raw|Gold||"] = 4,
	["Clean|Silver|Clean|"] = 3,
	["Clean|Amethyst|Pristine|"] = 2,
	["Clean|Copper|Rough|"] = 6,
	["Clean|Ruby|Rough|"] = 1,
	["Ingot|Iron|Clean|"] = 2,
}

-- A small factory on the preview plot's pad (the machines the game places, in the KitMachines look).
YardPreview.Machines = {
	{ Id = "CleaningStation", X = 1, Z = 8, R = 0 },
	{ Id = "AutoCleaner", X = 5, Z = 8, R = 0 },
	{ Id = "ClayFurnace", X = 8, Z = 8, R = 0 },
	{ Id = "Crusher", X = 8, Z = 4, R = 0 },
	{ Id = "BlastFurnace", X = 1, Z = 3, R = 0 },
	{ Id = "Conveyor", X = 6, Z = 7, R = 0 },
	{ Id = "Conveyor", X = 6, Z = 6, R = 0 },
	{ Id = "Conveyor", X = 6, Z = 5, R = 0 },
}

function YardPreview.build(Loader: any, workspace: any): { [string]: any }
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local PenView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.PenView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
	local CF = Loader.CFrame

	local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[YardPreview.Plot])
	do
		local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
		local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
		local Old = require("./machines_gallery")
		local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots", true)
		local parent = folder or workspace
		-- paint the metal floor's tile seams (SurfaceGui) on every plot plate for the renderer
		for _, plate in workspace:GetDescendants() do
			if plate:IsA("BasePart") and plate.Name == "Plate" and plate:FindFirstChild("Tiles") then
				Old.paintGuis(Loader, workspace, plate.Parent)
			end
		end
		for _, entry in YardPreview.Machines do
			local model = MachineBuilder.build(entry.Id)
			model:PivotTo(plotCF * Grid.localCFrame(entry.Id, entry.X, entry.Z, entry.R))
			model.Parent = parent
			Old.paintGuis(Loader, workspace, model)
			local top = model:FindFirstChild("ChimneyTop", true)
			if top then
				Old.smoke(Loader, workspace, top, 1.0)
			end
		end
	end
	local folder = Loader.roblox.Instance.new("Folder")
	folder.Name = "YardPreview"
	folder.Parent = workspace

	-- ores on the podiums (what PodiumService shows), pile in the pen (PenController)
	local income = 0
	for slot, desc in YardPreview.Podiums do
		local rect = BaseLayout.Podiums[slot]
		local model = ItemBuilder.display(
			desc,
			plotCF * CF.new(rect.Center.X, BaseLayout.PodiumOreHeight, rect.Center.Z) * CF.Angles(0, 0.5, 0),
			`{YardPreview.Plot}/{slot}/{desc.O}` -- the seed PodiumService uses
		)
		model.Parent = folder
		income += ItemData.income(desc)
	end
	local spots = PenView.pileSpots(plotCF, YardPreview.Plot)
	local used = 0
	local keys = {}
	for key, n in PenView.pileCounts(YardPreview.Pen, BaseLayout.Pen.ShowMax) do
		table.insert(keys, { key, n })
	end
	table.sort(keys, function(a, b)
		return a[1] < b[1]
	end)
	for _, pair in keys do
		local desc = ItemData.parseKey(pair[1])
		for _ = 1, pair[2] do
			used += 1
			local model = ItemBuilder.display(desc, spots[used], `pile/{used}`)
			model.Parent = folder
		end
	end
	local penCount = 0
	for _, n in YardPreview.Pen do
		penCount += n
	end

	-- HUD as a player with two podiums would see it
	local scale = 1.25 -- 900 px tall render / 720 design height
	local function hud(uiScale: number?): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = scale
		-- the quick-teleport bar (layout for the real uiScale: 0.62 on phones) and
		-- the right side menu with BUILD (the elevator button lives in its own left
		-- side menu: ElevatorController / ElevatorView.buildSideMenu)
		BuildView.menuButton(refs.Menu)
		local teleport = TeleportView.build(refs.TopBar, uiScale or 1)
		TeleportView.relayout(teleport, refs.TopBar, uiScale or 1)
		refs.Coins.Text = Format.money(12480)
		refs.Income.Text = Format.perSecond(income)
		refs.Income.TextColor3 = Loader.roblox.Color3.fromRGB(110, 214, 92)
		HudView.floater(refs.Floaters, "+" .. Format.money(income * 30))
		refs.CarryLabel.Text = "CARRYING 2/3"
		HudView.slot(refs.CarrySlots, nil, 1, true)
		HudView.slot(refs.CarrySlots, Rarity.get("Rare").Color, 2)
		HudView.slot(refs.CarrySlots, nil, 3)
		return refs
	end

	local function pen(compact: boolean, uiScale: number): any
		local refs = PenView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		PenView.setCompact(refs, compact)
		PenView.setMode(refs, "Pen", nil)
		PenView.setHeader(refs, penCount, 40)
		PenView.setEntries(refs, PenView.entries(YardPreview.Pen, "Pen"), true)
		PenView.setHint(
			refs,
			if compact
				then "TAKE: carry it  -  PODIUM: earn money every second"
				else "TAKE puts ore in your hands  -  PODIUM earns money every second  -  Backspace: close",
			nil,
			nil
		)
		return refs
	end

	local exports: { [string]: any } = {}
	exports.hud_base = UiExport.export({ hud().Gui })
	exports.ui_pen = UiExport.export({ hud().Gui, pen(false, scale).Gui })
	-- an iPhone SE-sized screen (375 pt tall) scaled up to the 900 px render, at the 0.62 phone floor
	local phoneScale = 0.62 * 900 / 375
	local phoneHud = hud(0.62)
	phoneHud.Gui.Scale.Scale = phoneScale
	exports.ui_pen_phone = UiExport.export({ phoneHud.Gui, pen(true, phoneScale).Gui })
	local phoneOnly = hud(0.62)
	phoneOnly.Gui.Scale.Scale = phoneScale
	exports.hud_phone = UiExport.export({ phoneOnly.Gui })
	local offline = HudView.buildOffline()
	offline.Gui.Scale.Scale = scale
	offline.Gui.Enabled = true
	offline.Amount.Text = "+" .. Format.money(income * 0.5 * 3 * 3600)
	offline.Detail.Text = "Away 3h 05m. Podiums pay 50% while you're offline, for up to 5 hours."
	exports.ui_offline = UiExport.export({ hud().Gui, offline.Gui })
	return exports
end

return YardPreview
