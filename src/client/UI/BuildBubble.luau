--[[
	Build mode in the light "Bubble" look (pure builder, preview first; the
	PlacementController moves from BuildView onto it after the owner's OK).
	The same parts as BuildView, restyled:

	  top centre    slot chip "MACHINES 3/10 · BELTS 12/40" with the build icon
	  top right     DONE
	  bottom        the tray: category tabs and the machines you own as cards
	                (3D machine picture, name, "x2"; selected = gold outline)
	  above tray    the reason line (warning pill) and the key hint
	  right (touch) PLACE, ROTATE, MOVE, PACK UP, CANCEL

	On phones the tray leaves the thumbstick corner free and the touch buttons
	sit above the jump button.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local BuildBubble = {}

local rgb = Color3.fromRGB

-- KitMachines.Catalog groups -> card colour
BuildBubble.GroupColors = {
	Cleaning = rgb(61, 165, 255),
	Furnaces = rgb(255, 138, 31),
	Special = rgb(180, 92, 255),
	Transport = rgb(34, 199, 169),
	Power = rgb(255, 196, 40),
} :: { [string]: Color3 }

BuildBubble.Groups = {
	{ Id = "All", Label = "ALL" },
	{ Id = "Cleaning", Label = "CLEANING" },
	{ Id = "Furnaces", Label = "FURNACES" },
	{ Id = "Special", Label = "SPECIAL" },
	{ Id = "Transport", Label = "TRANSPORT" },
	{ Id = "Power", Label = "POWER" },
}

export type Machine = { Id: string, Name: string, Group: string, Count: number }
export type Data = {
	Machines: { Machine },
	Selected: string?,
	Group: string,
	Slots: string, -- "MACHINES 3/10 · BELTS 12/40"
	Reason: string?,
	Hint: string?,
	Touch: boolean,
}

export type Layout = {
	Compact: boolean,
	TrayWidth: number,
	TrayX: number, -- centre offset from the screen centre
	Card: Vector2,
	Group: Vector2,
	GroupText: number,
	NameSize: number,
	ChipSize: number,
	Touch: Vector2,
}

function BuildBubble.layout(uiScale: number): Layout
	if uiScale <= 0.75 then
		return {
			Compact = true,
			TrayWidth = 760,
			TrayX = -40,
			Card = Vector2.new(112, 124),
			Group = Vector2.new(124, 72),
			GroupText = 20,
			NameSize = 19,
			ChipSize = 21,
			Touch = Vector2.new(96, 72),
		}
	end
	return {
		Compact = false,
		TrayWidth = 1080,
		TrayX = 0,
		Card = Vector2.new(104, 112),
		Group = Vector2.new(140, 40),
		GroupText = 17,
		NameSize = 15,
		ChipSize = 17,
		Touch = Vector2.new(96, 64),
	}
end

export type Refs = {
	Gui: ScreenGui,
	Chip: Frame,
	Done: TextButton,
	Groups: { [string]: TextButton },
	Cards: { [string]: TextButton },
	Reason: Frame?,
	Hint: TextLabel?,
	Place: TextButton?,
	Rotate: TextButton?,
	Move: TextButton?,
	PackUp: TextButton?,
	Cancel: TextButton?,
}

function BuildBubble.build(uiScale: number, data: Data): Refs
	local layout = BuildBubble.layout(uiScale)
	local gui = UIKit.screen("TerraForgeBuild", 6)
	gui:SetAttribute("TerraForge", true)
	local scale = gui:FindFirstChild("Scale") :: UIScale
	scale.Scale = uiScale

	-- slot chip + DONE
	local chip = Bubble.chip(gui, "", Vector2.new(if layout.Compact then 470 else 420, 48), if layout.Compact then 22 else 20, nil, {
		Name = "Slots",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
	})
	local chipText = chip:FindFirstChild("Text") :: TextLabel
	chipText.Text = data.Slots
	chipText.Position = UDim2.fromOffset(40, 0)
	chipText.Size = UDim2.new(1, -48, 1, 0)
	Bubble.icon(chip, "build", 64, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8, 0.5, -2), ZIndex = 6 })
	local done, doneHolder = Bubble.button(gui, {
		Name = "Done",
		Text = "DONE",
		Role = "Go",
		Size = Vector2.new(150, if layout.Compact then 72 else 56),
		Icon = "check",
		TextSize = 26,
	})
	doneHolder.AnchorPoint = Vector2.new(1, 0)
	doneHolder.Position = UDim2.new(1, -20, 0, 12)

	-- the tray
	local trayHeight = 16 + layout.Group.Y + Theme.Lip + 10 + 16 + layout.Card.Y + 26
	local trayHolder, tray = Bubble.body(gui, Bubble.role("Plain"), Vector2.new(layout.TrayWidth, trayHeight), {
		Name = "Tray",
		Corner = 24,
		Gloss = false,
	})
	trayHolder.AnchorPoint = Vector2.new(0.5, 1)
	trayHolder.Position = UDim2.new(0.5, layout.TrayX, 1, -12)
	local groupRow = UIKit.new("Frame", {
		Name = "Groups",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -32, 0, layout.Group.Y + Theme.Lip),
		ZIndex = 3,
	}, tray)
	UIKit.list(groupRow, Enum.FillDirection.Horizontal, 8)
	local groups = {}
	local shown = BuildBubble.Groups
	if layout.Compact then
		shown = { BuildBubble.Groups[1], BuildBubble.Groups[2], BuildBubble.Groups[3], BuildBubble.Groups[5], BuildBubble.Groups[6] }
	end
	for i, g in shown do
		local on = g.Id == data.Group
		local color = BuildBubble.GroupColors[g.Id]
		local face = Bubble.button(groupRow, {
			Name = g.Id,
			Text = g.Label,
			Role = if on then (if color then Bubble.roleFrom(color) else "Backpack") else "Plain",
			Size = layout.Group,
			TextSize = layout.GroupText,
			Corner = layout.Group.Y // 2,
			LayoutOrder = i,
		})
		if not on then
			local label = face:FindFirstChild("Label") :: TextLabel
			label.TextColor3 = if color then color else Theme.InkSoft
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = false
				stroke.Transparency = 1
			end
		else
			Bubble.select(face, true)
		end
		groups[g.Id] = face
	end

	local list = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.InkSoft,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		Position = UDim2.fromOffset(10, 14 + layout.Group.Y + Theme.Lip + 4),
		Size = UDim2.new(1, -20, 0, layout.Card.Y + 16 + 22),
		ZIndex = 3,
	}, tray)
	local pad = UIKit.padding(list, 6)
	pad.PaddingTop = UDim.new(0, 16)
	UIKit.list(list, Enum.FillDirection.Horizontal, 10)
	local cards = {}
	for i, machine in data.Machines do
		cards[machine.Id] = Bubble.card(list, {
			Name = machine.Id,
			Label = machine.Name,
			Icon = "machine_" .. machine.Id,
			Color = BuildBubble.GroupColors[machine.Group] or Theme.Roles.Plain.Base,
			Chip = "x" .. machine.Count,
			Size = layout.Card,
			NameSize = layout.NameSize,
			ChipSize = layout.ChipSize,
			Selected = machine.Id == data.Selected,
			LayoutOrder = i,
		})
	end

	-- reason + hint above the tray
	local refs: Refs = { Gui = gui, Chip = chip, Done = done, Groups = groups, Cards = cards }
	local above = 12 + trayHeight + Theme.Lip + 12
	if data.Reason then
		local reason = Bubble.chip(gui, data.Reason, Vector2.new(Bubble.textWidth(data.Reason, 20) + 40, 40), if layout.Compact then 22 else 20, "Build", {
			Name = "Reason",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, layout.TrayX, 1, -above),
		})
		refs.Reason = reason
		above += 48
	end
	if data.Hint and not data.Touch then
		refs.Hint = Bubble.text(gui, data.Hint, 20, {
			Name = "Hint",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -above),
			Size = UDim2.fromOffset(700, 26),
		})
	end

	-- touch buttons (right side, above the jump button on phones)
	if data.Touch then
		local t = layout.Touch
		local cluster = UIKit.new("Frame", {
			Name = "Actions",
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -20, 1, -(if layout.Compact then 160 else 230)),
			Size = UDim2.fromOffset(t.X * 2 + 10, (t.Y + Theme.Lip) * 3 + 20),
		}, gui)
		local function action(name: string, text: string, role: string, x: number, y: number, w: number): TextButton
			local face, holder = Bubble.button(cluster, { Name = name, Text = text, Role = role, Size = Vector2.new(w, t.Y), TextSize = 22 })
			holder.Position = UDim2.fromOffset(x, y)
			return face
		end
		local rowH = t.Y + Theme.Lip + 10
		refs.Rotate = action("Rotate", "ROTATE", "Plain", 0, 0, t.X)
		refs.Move = action("Move", "MOVE", "Plain", t.X + 10, 0, t.X)
		refs.PackUp = action("PackUp", "PACK UP", "Plain", 0, rowH, t.X)
		refs.Cancel = action("Cancel", "CANCEL", "Danger", t.X + 10, rowH, t.X)
		refs.Place = action("Place", "PLACE", "Go", 0, rowH * 2, t.X * 2 + 10)
		for _, b in { refs.Rotate, refs.Move, refs.PackUp } do
			if b then
				local label = b:FindFirstChild("Label") :: TextLabel
				label.TextColor3 = Theme.Ink
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Enabled = false
					stroke.Transparency = 1
				end
			end
		end
	end
	return refs
end

return BuildBubble
