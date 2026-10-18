--[[
	Build mode UI (pure builder; PlacementController wires it up).
	  top centre    slot chip 'MACHINES 3/10 - BELTS 0/40'
	  top right     DONE
	  bottom        tray of machine cards you own (MachineData order, 'x2')
	  above tray    reason / warning line, and a key hint line
	  bottom right  big touch buttons: Cancel, Rotate, Move, Pack Up, Place
	The Gui has the TerraForge attribute, so the HUD's UIScale applies.
	With UIConfig.lightUI() on (the light UI, ships off) build() makes the same
	refs in the light "Bubble" look: a white slot pill with the 3D build icon,
	a white tray, machine cards with their 3D pictures in the category colour,
	chunky light buttons. setInventory / setCounts keep the colours readable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local MachineData = require(Shared.Config.MachineData)
local UIConfig = require(Shared.Config.UIConfig)
local IconAssets = require(Shared.Config.IconAssets)
local BubbleTheme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)
local HudBubble = require(script.Parent.HudBubble)

local BuildView = {}

export type Mode = "Idle" | "Selected" | "Placing" | "Moving"

export type Card = {
	Button: TextButton,
	Count: TextLabel,
	Stroke: UIStroke,
	Bound: boolean,
}

export type Refs = {
	Gui: ScreenGui,
	Chip: TextLabel,
	Reason: TextLabel,
	Hint: TextLabel,
	Tray: ScrollingFrame,
	Empty: TextLabel,
	Cards: { [string]: Card },
	Actions: Frame,
	Cancel: TextButton,
	Rotate: TextButton,
	Move: TextButton,
	PackUp: TextButton,
	Place: TextButton,
	Done: TextButton,
	OnPick: ((string) -> ())?,
}

local rgb = Color3.fromRGB

BuildView.CategoryColors = {
	Processing = rgb(236, 128, 56),
	Storage = rgb(176, 124, 74),
	Logistics = rgb(90, 160, 230),
	Selling = rgb(110, 214, 92),
} :: { [string]: Color3 }

BuildView.ReasonColors = {
	Bad = Theme.Bad,
	Warn = rgb(255, 210, 80),
	Info = Theme.Text,
} :: { [string]: Color3 }

-- Design-unit sizes (the HUD's UIScale shrinks them on small screens).
BuildView.TouchButtonHeight = 76
BuildView.TrayHeight = 112
local CARD_WIDTH = 118
local CARD_HEIGHT = 96
local ACTION_GAP = 10
local EDGE = 16

-- Which touch buttons each mode shows.
local MODE_BUTTONS: { [string]: { [string]: boolean } } = {
	Idle = {},
	Placing = { Cancel = true, Rotate = true, Place = true },
	Selected = { Cancel = true, Move = true, PackUp = true },
	Moving = { Cancel = true, Rotate = true, PackUp = true, Place = true },
}

local function card(parent: Instance, machine: MachineData.Machine): Card
	local button = UIKit.new("TextButton", {
		Name = machine.Id,
		LayoutOrder = machine.Order,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, parent)
	UIKit.corner(button, 12)
	local stroke = UIKit.stroke(button, 3)
	UIKit.gradient(button, Color3.new(1, 1, 1), rgb(200, 200, 200))
	local color = BuildView.CategoryColors[machine.Category] or Theme.PanelLight
	local band = UIKit.new("Frame", {
		Name = "Band",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, button)
	UIKit.corner(band, 12)
	UIKit.label(band, string.upper(machine.Category), 12, {
		Name = "Category",
		Size = UDim2.fromScale(1, 1),
	})
	UIKit.label(button, machine.Name, 17, {
		Name = "MachineName",
		Position = UDim2.fromOffset(6, 24),
		Size = UDim2.new(1, -12, 0, 46),
	})
	UIKit.label(button, `{machine.Size[1]}x{machine.Size[2]}`, 13, {
		Name = "Footprint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -4),
		Size = UDim2.fromOffset(40, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
	})
	local count = UIKit.label(button, "x0", 18, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -3),
		Size = UDim2.fromOffset(56, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Accent,
	})
	return { Button = button, Count = count, Stroke = stroke, Bound = false }
end

local function actionButton(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	dark: Color3,
	width: number,
	order: number
): TextButton
	return UIKit.button(parent, text, color, dark, {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, BuildView.TouchButtonHeight),
		TextSize = 24,
		Visible = false,
	})
end

---------------------------------------------------------------- the light look (UIConfig.LightUI)

-- The 3D picture of a machine (its Soft model), or the build icon.
function BuildView.iconFor(id: string): string
	local name = "machine_" .. id
	return if IconAssets.has(name) then name else "build"
end

-- A machine card: a clickable transparent button (so hiding it hides the
-- whole card) holding a light body in the category colour.
local function lightCard(parent: Instance, machine: MachineData.Machine): Card
	local w, h = 104, BuildView.TrayHeight - 22
	local button = UIKit.new("TextButton", {
		Name = machine.Id,
		LayoutOrder = machine.Order,
		Size = UDim2.fromOffset(w, h + BubbleTheme.Lip),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, parent)
	local color = BuildView.CategoryColors[machine.Category] or BubbleTheme.Roles.Plain.Base
	local holder, face = Bubble.body(button, Bubble.roleFrom(color), Vector2.new(w, h), { Name = "Body", Corner = 16 })
	holder.Size = UDim2.fromScale(1, 1)
	Bubble.icon(face, BuildView.iconFor(machine.Id), 64, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -10),
	})
	Bubble.text(face, machine.Name, 15, {
		Name = "MachineName",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -8, 0, 18),
		TextScaled = true,
		ZIndex = 4,
	})
	local chip = Bubble.chip(face, "x0", Vector2.new(64, 22), 16, nil, {
		Name = "CountChip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
	})
	local stroke = face:FindFirstChildOfClass("UIStroke") :: UIStroke
	return { Button = button, Count = chip:FindFirstChild("Text") :: TextLabel, Stroke = stroke, Bound = false }
end

local function lightAction(parent: Instance, name: string, text: string, role: string, width: number, order: number): TextButton
	local face, holder = Bubble.button(parent, {
		Name = name,
		Text = text,
		Role = role,
		Size = Vector2.new(width, BuildView.TouchButtonHeight - BubbleTheme.Lip),
		TextSize = 24,
		LayoutOrder = order,
	})
	holder.Visible = false
	if role == "Plain" then
		local label = face:FindFirstChild("Label") :: TextLabel
		label.TextColor3 = BubbleTheme.Ink
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
			stroke.Transparency = 1
		end
	end
	return face :: TextButton
end

local function buildLight(): Refs
	local gui = UIKit.screen("TerraForgeBuild", 8)
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("Bubble", true)
	gui.Enabled = false

	-- the slot pill with the 3D build icon
	local chip = Bubble.ink(gui, "MACHINES 0/0 - BELTS 0/0", 20, {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = BubbleTheme.Panel,
		BackgroundTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(420, 44),
	})
	Bubble.corner(chip, 22)
	Bubble.stroke(chip, 3.5)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 40) }, chip)
	Bubble.icon(chip, "build", 62, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -32, 0.5, -2) })

	local done = Bubble.button(gui, { Name = "Done", Text = "DONE", Role = "Go", Size = Vector2.new(150, 58), Icon = "check", TextSize = 26 })
	local doneHolder = done.Parent :: Frame
	doneHolder.AnchorPoint = Vector2.new(1, 0)
	doneHolder.Position = UDim2.new(1, -EDGE, 0, EDGE + 4)

	-- the tray: a white rounded strip of cards
	local tray = UIKit.new("ScrollingFrame", {
		Name = "Tray",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -2 * EDGE, 0, BuildView.TrayHeight),
		BackgroundColor3 = BubbleTheme.Panel,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = BubbleTheme.InkSoft,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, gui)
	Bubble.corner(tray, 22)
	Bubble.stroke(tray, 3.5)
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(940, BuildView.TrayHeight) }, tray)
	local pad = UIKit.padding(tray, 10)
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 4)
	UIKit.list(tray, Enum.FillDirection.Horizontal, 10, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
	local cards: { [string]: Card } = {}
	for _, machine in MachineData.List do
		cards[machine.Id] = lightCard(tray, machine)
	end
	local empty = Bubble.text(gui, "Nothing left to place. Pack up a machine to place it again.", 20, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -50),
		Size = UDim2.fromOffset(620, 28),
		Visible = false,
	})

	-- reason and key hint above the tray
	local reason = Bubble.text(gui, "", 22, {
		Name = "Reason",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BuildView.TrayHeight + 22)),
		Size = UDim2.fromOffset(640, 30),
		Visible = false,
	})
	local hint = Bubble.text(gui, "", 18, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BuildView.TrayHeight + 54)),
		Size = UDim2.fromOffset(820, 24),
		Visible = false,
	})

	-- touch buttons, bottom right
	local actions = UIKit.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -EDGE, 1, -12),
		Size = UDim2.fromOffset(0, BuildView.TouchButtonHeight + 6),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	UIKit.list(actions, Enum.FillDirection.Horizontal, ACTION_GAP, {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})
	return {
		Gui = gui,
		Chip = chip,
		Reason = reason,
		Hint = hint,
		Tray = tray,
		Empty = empty,
		Cards = cards,
		Actions = actions,
		Cancel = lightAction(actions, "Cancel", "CANCEL", "Danger", 112, 1),
		Rotate = lightAction(actions, "Rotate", "ROTATE", "Plain", 112, 2),
		Move = lightAction(actions, "Move", "MOVE", "Plain", 104, 3),
		PackUp = lightAction(actions, "PackUp", "PACK UP", "Plain", 124, 4),
		Place = lightAction(actions, "Place", "PLACE", "Go", 140, 5),
		Done = done,
		OnPick = nil,
	}
end

function BuildView.build(): Refs
	if UIConfig.lightUI() then
		return buildLight()
	end
	local gui = UIKit.screen("TerraForgeBuild", 8)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false

	-- slot chip
	local chip = UIKit.label(gui, "MACHINES 0/0 - BELTS 0/0", 18, {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(380, 36),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0,
		TextWrapped = false,
	})
	UIKit.corner(chip, 18)
	UIKit.stroke(chip, 3)

	-- done
	local done = UIKit.button(gui, "DONE", Theme.Good, Theme.GoodDark, {
		Name = "Done",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, EDGE + 4),
		Size = UDim2.fromOffset(120, 64),
		TextSize = 26,
	})

	-- tray
	local tray = UIKit.new("ScrollingFrame", {
		Name = "Tray",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -2 * EDGE, 0, BuildView.TrayHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, gui)
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(940, BuildView.TrayHeight) }, tray)
	UIKit.list(tray, Enum.FillDirection.Horizontal, 10, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local cards: { [string]: Card } = {}
	for _, machine in MachineData.List do
		cards[machine.Id] = card(tray, machine)
	end
	local empty = UIKit.label(gui, "Nothing left to place. Pack up a machine to place it again.", 18, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -50),
		Size = UDim2.fromOffset(560, 28),
		TextColor3 = Theme.TextDim,
		Visible = false,
	})

	-- reason / warning and key hints, above the tray
	local reason = UIKit.label(gui, "", 22, {
		Name = "Reason",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BuildView.TrayHeight + 18)),
		Size = UDim2.fromOffset(640, 30),
		Visible = false,
	})
	local hint = UIKit.label(gui, "", 16, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BuildView.TrayHeight + 50)),
		Size = UDim2.fromOffset(820, 22),
		TextColor3 = Theme.TextDim,
		Visible = false,
	})

	-- touch buttons, bottom right
	local actions = UIKit.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -EDGE, 1, -12),
		Size = UDim2.fromOffset(0, BuildView.TouchButtonHeight + 6),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	UIKit.list(actions, Enum.FillDirection.Horizontal, ACTION_GAP, {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})
	local cancel = actionButton(actions, "Cancel", "Cancel", Theme.Bad, Theme.BadDark, 104, 1)
	local rotate = actionButton(actions, "Rotate", "Rotate", Theme.Info, rgb(60, 120, 190), 104, 2)
	local move = actionButton(actions, "Move", "Move", Theme.Accent, Theme.AccentDark, 104, 3)
	local packUp = actionButton(actions, "PackUp", "Pack Up", Theme.Accent, Theme.AccentDark, 120, 4)
	local place = actionButton(actions, "Place", "PLACE", Theme.Good, Theme.GoodDark, 136, 5)

	return {
		Gui = gui,
		Chip = chip,
		Reason = reason,
		Hint = hint,
		Tray = tray,
		Empty = empty,
		Cards = cards,
		Actions = actions,
		Cancel = cancel,
		Rotate = rotate,
		Move = move,
		PackUp = packUp,
		Place = place,
		Done = done,
		OnPick = nil,
	}
end

--[[
	Shows a card for every machine you have left to place (count > 0), in
	MachineData order, and marks the selected one. Clicking or tapping a
	card calls onPick(id) (the latest callback passed here).
]]
function BuildView.setInventory(refs: Refs, inventory: { [string]: number }, selected: string?, onPick: (id: string) -> ())
	refs.OnPick = onPick
	local any = false
	for id, entry in refs.Cards do
		local count = inventory[id]
		local n = if type(count) == "number" then math.max(0, math.floor(count)) else 0
		local show = n > 0
		entry.Button.Visible = show
		any = any or show
		entry.Count.Text = `x{n}`
		local isSelected = show and id == selected
		if refs.Gui:GetAttribute("Bubble") then
			entry.Stroke.Color = if isSelected then BubbleTheme.Gold else BubbleTheme.Outline
			entry.Stroke.Thickness = if isSelected then 5 else BubbleTheme.Stroke
		else
			entry.Stroke.Color = if isSelected then Theme.Accent else Theme.Outline
			entry.Stroke.Thickness = if isSelected then 4.5 else 3
			entry.Button.BackgroundColor3 = if isSelected then Theme.PanelLight else Theme.Panel
		end
		if not entry.Bound then
			entry.Bound = true
			entry.Button.Activated:Connect(function()
				local callback = refs.OnPick
				if callback then
					callback(id)
				end
			end)
		end
	end
	refs.Empty.Visible = not any
end

function BuildView.setCounts(refs: Refs, machinesUsed: number, machineSlots: number, conveyorsUsed: number, conveyorSlots: number)
	refs.Chip.Text = `MACHINES {machinesUsed}/{machineSlots} - BELTS {conveyorsUsed}/{conveyorSlots}`
	local full = machinesUsed >= machineSlots or conveyorsUsed >= conveyorSlots
	if refs.Gui:GetAttribute("Bubble") then
		refs.Chip.TextColor3 = if full then BubbleTheme.Bad else BubbleTheme.Ink -- dark text on the white pill
	else
		refs.Chip.TextColor3 = if full then Theme.Accent else Theme.Text
	end
end

-- kind: 'Bad' (red, can't place), 'Warn' (yellow), 'Info' (white); nil text hides it.
function BuildView.setReason(refs: Refs, text: string?, kind: string?)
	if not text or text == "" then
		refs.Reason.Visible = false
		return
	end
	refs.Reason.Text = text
	refs.Reason.TextColor3 = BuildView.ReasonColors[kind or "Info"] or Theme.Text
	refs.Reason.Visible = true
end

-- Key hints for the current device; nil hides the line.
function BuildView.setHint(refs: Refs, text: string?)
	refs.Hint.Text = text or ""
	refs.Hint.Visible = text ~= nil and text ~= ""
end

local function holderOf(button: TextButton): GuiObject?
	local parent = button.Parent
	return if parent and parent:IsA("GuiObject") then parent else nil
end

-- Shows the touch buttons that fit the mode (touch only) and makes room
-- for them next to the tray.
function BuildView.setMode(refs: Refs, mode: Mode, isTouch: boolean)
	local wanted = MODE_BUTTONS[mode] or {}
	local shown = 0
	local width = 0
	local buttons: { [string]: TextButton } = {
		Cancel = refs.Cancel,
		Rotate = refs.Rotate,
		Move = refs.Move,
		PackUp = refs.PackUp,
		Place = refs.Place,
	}
	for name, button in buttons do
		local visible = isTouch and wanted[name] == true
		local holder = holderOf(button)
		if holder then
			holder.Visible = visible
			if visible then
				shown += 1
				width += holder.Size.X.Offset
			end
		end
	end
	refs.Actions.Visible = shown > 0
	if shown > 0 then
		-- the tray takes the space left of the buttons
		local reserved = width + (shown - 1) * ACTION_GAP + 3 * EDGE
		refs.Tray.AnchorPoint = Vector2.new(0, 1)
		refs.Tray.Position = UDim2.new(0, EDGE, 1, -12)
		refs.Tray.Size = UDim2.new(1, -reserved, 0, BuildView.TrayHeight)
	else
		refs.Tray.AnchorPoint = Vector2.new(0.5, 1)
		refs.Tray.Position = UDim2.new(0.5, 0, 1, -12)
		refs.Tray.Size = UDim2.new(1, -2 * EDGE, 0, BuildView.TrayHeight)
	end
end

-- The BUILD button for the HUD's right-side menu (HudController.refs().Menu).
function BuildView.menuButton(menu: Instance): TextButton
	if menu:GetAttribute("Bubble") then
		return HudBubble.claimTile(menu, "Build") -- the light HUD's BUILD tile
	end
	return UIKit.button(menu, "BUILD", Theme.Accent, Theme.AccentDark, {
		Name = "Build",
		LayoutOrder = 10,
		Size = UDim2.fromOffset(84, 64),
		TextSize = 20,
	})
end

return BuildView
