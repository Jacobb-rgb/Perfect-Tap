--[[
	Build mode UI (pure builder; PlacementController wires it up).
	  top centre    slot chip 'MACHINES 3/10 - BELTS 0/40'
	  top right     DONE
	  bottom        tray of machine cards you own (MachineData order, 'x2')
	  above tray    reason / warning line, and a key hint line
	  bottom right  big touch buttons: Cancel, Rotate, Move, Pack Up, Place
	The Gui has the TerraForge attribute, so the HUD's UIScale applies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local MachineData = require(Shared.Config.MachineData)
local UIKit = require(script.Parent.UIKit)

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

function BuildView.build(): Refs
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
		entry.Stroke.Color = if isSelected then Theme.Accent else Theme.Outline
		entry.Stroke.Thickness = if isSelected then 4.5 else 3
		entry.Button.BackgroundColor3 = if isSelected then Theme.PanelLight else Theme.Panel
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
	refs.Chip.TextColor3 = if full then Theme.Accent else Theme.Text
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
	return UIKit.button(menu, "BUILD", Theme.Accent, Theme.AccentDark, {
		Name = "Build",
		LayoutOrder = 10,
		Size = UDim2.fromOffset(84, 64),
		TextSize = 20,
	})
end

return BuildView
