--[[
	Iron Box preview (scene "ironbox" for tools/lune/export_scene.luau, shots
	in tools/preview/ironbox_shots.json; WP-CleanerBox).

	A plot pad with a small sorting line, placed with the game's own grid
	maths (Grid.localCFrame): a Cleaning Plant whose output belt runs into
	the Iron Box's back, and two belts carrying the box's SEND output away.
	What the client draws is posed by hand, the way MachineFxController
	would show it:
	  - the screen's Item line ("PRISTINE GOLD" in Rare blue; the renderer
	    draws one text per SurfaceGui), the KEEP flap swung open (a Gold
	    just went to the pen), a scaled display Gold behind the bay's glass;
	  - dirty ore riding in, a sent Coal and a Copper on the out belts.
	UI overlays (build/preview/<name>.json):
	  ui_ironbox         HUD + the keep list in MY LIST (PC, 1.25 scale)
	  ui_ironbox_phone   the keep list on a 667 x 375 pt phone (compact)
	  ui_ironbox_narrow  the keep list on a 568 x 320 pt phone (3 columns)
	  ui_ironbox_rare    RARE+ mode (PC)
	buildBoard (scene "penboard": `lune run tools/lune/export_scene.luau
	world penboard`): the Pen Automation sorting board at plot 5's Ore Pen
	gate, placed and painted the way IronBoxService does it.
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3

-- grid cells (min corner, rotation 0 = front toward -Z)
Preview.Layout = {
	{ Id = "AutoCleaner", X = 4, Z = 7, R = 0 },
	{ Id = "Conveyor", X = 5, Z = 6, R = 0 },
	{ Id = "Conveyor", X = 5, Z = 5, R = 0 },
	{ Id = "IronBox", X = 4, Z = 3, R = 0 },
	{ Id = "Conveyor", X = 5, Z = 2, R = 0 },
	{ Id = "Conveyor", X = 5, Z = 1, R = 0 },
	{ Id = "Conveyor", X = 5, Z = 0, R = 0 },
}

-- what the player has discovered and chosen (the keep list overlays)
Preview.Discovered = {
	"Coal",
	"Copper",
	"Tin",
	"Iron",
	"Silver",
	"Quartz",
	"Gold",
	"Amethyst",
	"Ruby",
	"Sapphire",
	"Emerald",
	"Diamond",
	"Azurium",
	"Stormcore",
}
Preview.KeepList = { Coal = false, Copper = false, Tin = false, Iron = true, Silver = true, Gold = true, Ruby = true }

local function lowest(model: any): number
	local low = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
			local half = math.abs(r10) * d.Size.X / 2 + math.abs(r11) * d.Size.Y / 2 + math.abs(r12) * d.Size.Z / 2
			low = math.min(low, d.CFrame.Position.Y - half)
		end
	end
	return low
end

local function shift(model: any, offset: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + offset
		end
	end
end

-- Model:ScaleTo stand-in (Lune has none): every part's size and offset from `around`.
local function scale(model: any, factor: number, around: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size = d.Size * factor
			d.CFrame = cf - cf.Position + (around + (cf.Position - around) * factor)
		end
	end
end

local function extent(model: any): number
	local lo, hi = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local p, h = d.CFrame.Position, d.Size / 2
			lo = V3.new(math.min(lo.X, p.X - h.X), math.min(lo.Y, p.Y - h.Y), math.min(lo.Z, p.Z - h.Z))
			hi = V3.new(math.max(hi.X, p.X + h.X), math.max(hi.Y, p.Y + h.Y), math.max(hi.Z, p.Z + h.Z))
		end
	end
	local size = hi - lo
	return math.max(size.X, size.Y, size.Z)
end

function Preview.build(Loader: any, parent: any): { [string]: any }
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local IronBoxView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.IronBoxView")
	local Gallery = require("./machines_gallery")
	local UiExport = require("./uiexport")
	local Dummy = require("./dummy")

	local root = roblox.Instance.new("Model")
	root.Name = "IronBoxPreview"
	root.Parent = parent
	local CELL = GameConfig.CellSize
	local half = GameConfig.PlotCells * CELL / 2

	-- lawn, a gravel plot pad with faint cell lines and a low kerb (like the machine gallery)
	Geo.block(root, CF.new(0, -1.06, 0), V3.new(260, 2, 260), C3.fromRGB(150, 196, 92))
	Geo.block(root, CF.new(0, -0.5, 0), V3.new(half * 2, 1, half * 2), C3.fromRGB(214, 192, 150))
	for i = 1, GameConfig.PlotCells - 1 do
		local p = -half + i * CELL
		Geo.block(root, CF.new(p, 0.005, 0), V3.new(0.08, 0.01, half * 2), C3.fromRGB(196, 174, 134))
		Geo.block(root, CF.new(0, 0.005, p), V3.new(half * 2, 0.01, 0.08), C3.fromRGB(196, 174, 134))
	end

	local placed = {}
	local belts = {}
	for _, entry in Preview.Layout do
		local model = MachineBuilder.build(entry.Id)
		model:PivotTo(Grid.localCFrame(entry.Id, entry.X, entry.Z, entry.R))
		model.Parent = root
		Gallery.paintGuis(Loader, root, model)
		if entry.Id == "Conveyor" then
			table.insert(belts, model)
		else
			placed[entry.Id] = model
		end
	end
	local box = placed.IronBox
	local base = box.PrimaryPart

	-- the screen: the last item (one text per SurfaceGui in the renderer)
	local gold = OreData.ById.Gold
	local screen = box:FindFirstChild("Screen")
	local item = screen.ScreenGui.Item
	item.Text = "PRISTINE GOLD"
	item.TextColor3 = MachineBuilder.IronBox.ScreenText:Lerp(Rarity.get(gold.Rarity).Color, MachineBuilder.IronBox.RarityTint)
	screen.ScreenGui.Counter.Text = "KEPT 12 · SENT 31"

	-- the KEEP flap swung open on its top edge (a Gold just went to the pen)
	local flap = box:FindFirstChild("FlapKeep")
	local hinge = flap.CFrame * CF.new(0, flap.Size.Y / 2, 0)
	local angle = MachineBuilder.IronBox.FlapOpen * 0.8
	flap.CFrame = hinge * CF.Angles(angle, 0, 0) * hinge:Inverse() * flap.CFrame

	-- a display Gold behind the glass, scaled to the window, on ShowPoint
	local show = base.CFrame * base:FindFirstChild("ShowPoint").CFrame * CF.Angles(0, math.rad(25), 0)
	local shown = ItemBuilder.display({ K = "Clean", O = "Gold", G = "Pristine" }, CF.new(), "Clean|Gold|Pristine|")
	for _, d in shown:GetDescendants() do
		if d:IsA("PointLight") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	local size = extent(shown)
	if size > MachineBuilder.IronBox.Window then
		scale(shown, MachineBuilder.IronBox.Window / size, V3.new(0, 0, 0))
	end
	local offset = lowest(shown)
	for _, d in shown:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = show * (d.CFrame - V3.new(0, offset, 0))
		end
	end
	shown.Parent = root

	-- ore on the belts: dirty ore riding in, sent ore riding away
	local function ore(kind: string, oreId: string, belt: any, x: number, z: number, yaw: number, seed: number)
		local beltTop = belt:FindFirstChild("Belt").CFrame.Position.Y + 0.25
		local built = ItemBuilder.build(
			{ Kind = kind, OreId = oreId, Grade = "Rough" },
			belt:GetPivot() * CF.new(x, 1.5, z) * CF.Angles(0, yaw, 0),
			seed
		)
		shift(built, V3.new(0, beltTop - lowest(built), 0))
		built.Parent = root
	end
	ore("Raw", "Silver", belts[1], 0.1, 0.4, 0.6, 3)
	ore("Raw", "Gold", belts[2], -0.2, -0.6, 1.9, 8)
	ore("Clean", "Coal", belts[3], 0.15, 0.2, 0.9, 5)
	ore("Clean", "Copper", belts[5], -0.1, 0.5, 2.4, 6)

	-- a forgekeeper next to the box for scale
	Dummy.build(root, CF, base.CFrame * CF.new(-6.2, -0.15, -3.2) * CF.Angles(0, math.pi * 0.8, 0), "idle")
	Gallery.steam(Loader, root, placed.AutoCleaner:FindFirstChild("Vent"))

	-- the scene JSON needs at least one emitter: an invisible one far away
	local anchor = Geo.block(root, CF.new(0, -40, -3000), V3.new(1, 1, 1), C3.new(0, 0, 0))
	anchor.Transparency = 1
	local placeholder = roblox.Instance.new("ParticleEmitter")
	placeholder.Texture = "rbxasset://textures/particles/smoke_main.dds"
	placeholder.Parent = anchor

	---------------------------------------------------------------- UI
	local pcScale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = 0.62 * 900 / 375 -- a 667 x 375 pt phone at the 0.62 floor, scaled up to the render
	local discovered = {}
	for _, id in Preview.Discovered do
		discovered[id] = true
	end

	local function hud(uiScale: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(84210)
		refs.Income.Text = Format.perSecond(312)
		refs.Income.TextColor3 = C3.fromRGB(110, 214, 92)
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		return refs
	end

	local function view(mode: string, compact: boolean, uiScale: number, maxWidth: number, maxHeight: number): any
		local refs = IronBoxView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		IronBoxView.layout(refs, compact, maxWidth, maxHeight)
		local state = { Discovered = discovered, KeepMode = mode, KeepList = Preview.KeepList }
		IronBoxView.setEntries(refs, IronBoxView.entries(state))
		IronBoxView.setMode(refs, mode, IronBoxView.hasList(state))
		IronBoxView.setHint(
			refs,
			if compact then "Tap an ore to keep it or send it on" else "Click an ore to keep it or send it on  -  Backspace: close",
			nil,
			nil
		)
		return refs
	end

	local exports: { [string]: any } = {}
	exports.ui_ironbox = UiExport.export({ hud(pcScale).Gui, view("List", false, pcScale, 1600 / pcScale, (900 - 36) / pcScale).Gui })
	exports.ui_ironbox_rare =
		UiExport.export({ hud(pcScale).Gui, view("RarePlus", false, pcScale, 1600 / pcScale, (900 - 36) / pcScale).Gui })
	exports.ui_ironbox_phone =
		UiExport.export({ hud(phoneScale).Gui, view("List", true, phoneScale, 1600 / phoneScale, (900 - 58) / phoneScale).Gui })
	-- a 568 x 320 pt phone at the 0.62 floor (the render's 16:9 is about its shape)
	local narrowScale = 0.62 * 900 / 320
	exports.ui_ironbox_narrow =
		UiExport.export({ hud(narrowScale).Gui, view("List", true, narrowScale, 1600 / narrowScale, (900 - 58) / narrowScale).Gui })
	return exports
end

Preview.BoardPlot = 5 -- the yard preview's plot (an east plot: the sun lights its yard)

-- The sorting board at a plot's pen gate (scene "penboard", on the world).
function Preview.buildBoard(Loader: any, workspace: any): any
	local CF = Loader.CFrame
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local IronBoxService = Loader.requirePath("ServerScriptService.Server.Services.IronBoxService")
	local Dummy = require("./dummy")
	local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[Preview.BoardPlot])
	local board = MachineBuilder.sortingBoard()
	board.Name = IronBoxService.BoardName
	board:PivotTo(plotCF * IronBoxService.boardPoint())
	local discovered = {}
	for _, id in Preview.Discovered do
		discovered[id] = true
	end
	MachineBuilder.paintSortingBoard(
		board,
		IronBoxService.boardInfo({ KeepMode = "List", KeepList = Preview.KeepList, Discovered = discovered })
	)
	board.Parent = workspace
	-- the renderer paints top-level SurfaceGui frames only: lay the swatch
	-- grid out the way UIGridLayout does (cells of 1/Columns minus 6 px, 6 px
	-- apart, centred) as plain frames on a temporary gui, paint, drop it
	local display = board:FindFirstChild("Display")
	local gui = display.BoardGui
	local swatches = gui.Swatches
	local frames = {}
	for _, child in swatches:GetChildren() do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	table.sort(frames, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local temp = roblox.Instance.new("SurfaceGui")
	temp.Name = "PreviewSwatches"
	temp.Face = roblox.Enum.NormalId.Front
	temp.Parent = display
	local px, py = display.Size.X * gui.PixelsPerStud, display.Size.Y * gui.PixelsPerStud
	local fx, fy = swatches.Position.X.Scale * px, swatches.Position.Y.Scale * py
	local fw, fh = swatches.Size.X.Scale * px, swatches.Size.Y.Scale * py
	local cols = MachineBuilder.SortingBoard.Columns
	local cellW, cellH = fw / cols - 6, fh / 2 - 6
	local used = math.min(#frames, cols)
	local gridW = used * cellW + (used - 1) * 6
	for i, frame in frames do
		local col, row = (i - 1) % cols, (i - 1) // cols
		local plate = roblox.Instance.new("Frame")
		plate.BackgroundColor3 = frame.BackgroundColor3
		plate.Position = roblox.UDim2.fromScale((fx + (fw - gridW) / 2 + col * (cellW + 6)) / px, (fy + row * (cellH + 6)) / py)
		plate.Size = roblox.UDim2.fromScale(cellW / px, cellH / py)
		plate.Parent = temp
	end
	swatches.Parent = nil
	require("./machines_gallery").paintGuis(Loader, workspace, board)
	temp:Destroy()
	swatches.Parent = gui
	-- the renderer also centres a SurfaceGui's one text on the whole face:
	-- give the Mode line a thin band of its own over the display's top
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local mode = gui.Mode
	local bandH = display.Size.Y * mode.Size.Y.Scale
	local bandY = display.Size.Y / 2 - display.Size.Y * mode.Position.Y.Scale - bandH / 2
	local band = Geo.block(
		workspace,
		display.CFrame * CF.new(0, bandY, -display.Size.Z / 2 - 0.004),
		roblox.Vector3.new(display.Size.X * mode.Size.X.Scale, bandH, 0.006),
		display.Color,
		roblox.Enum.Material.Neon,
		{ CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	)
	local bandGui = roblox.Instance.new("SurfaceGui")
	bandGui.Face = roblox.Enum.NormalId.Front
	bandGui.Parent = band
	local text = mode:Clone()
	text.Parent = bandGui
	gui:Destroy()
	-- a forgekeeper on the gate side, turned toward it
	Dummy.build(workspace, CF, plotCF * IronBoxService.boardPoint() * CF.new(-3.0, 0, -3.9) * CF.Angles(0, math.rad(35), 0), "idle")
	local at = board:GetPivot().Position
	print(string.format("sorting board at %.1f, %.1f, %.1f", at.X, at.Y, at.Z))
	return board
end

return Preview
