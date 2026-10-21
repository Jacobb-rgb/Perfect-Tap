--[[
	Build mode UI (pure builder; PlacementController wires it up).
	  top centre    slot chip 'MACHINES 3/10 - BELTS 0/40'
	  top right     DONE, and SHOP under it (the Tech shop's machines)
	  bottom        tray of machine cards you own (MachineData order, 'x2'):
	                a live 3D picture of the machine, its category band
	                and a power chip ("PWR 10" needs, "+40 PWR" makes); empty,
	                it says "Buy machines with SHOP" next to a SHOP button
	                (not while the touch buttons show: they sit there)
	  above tray    reason / warning line, and the controls: a row of
	                keycap chips for the mode and device (keys / setKeys:
	                [LMB] Place [R] Rotate ...; the platform's own glyphs
	                on a gamepad; what to tap on touch)
	  left          the machine info card (setInfo, MachineInfo.describe):
	                live picture, name, category, size, TAKES -> GIVES,
	                its power, where the results come out, the description;
	                it takes clicks and taps (Active), so they never reach
	                the plot under it
	  bottom right  big touch buttons: Deck / Ground (while the plot has
	                platforms), Cancel, Rotate, Move, Pack Up, Place
	The Gui has the TerraForge attribute, so the HUD's UIScale applies.
	With UIConfig.lightUI() on (the light UI) build() makes the same refs in
	the light "Bubble" look: a slot pill with the 3D build icon, a tray
	panel, machine cards in the category colour, chunky buttons.
	setInventory / setCounts keep the colours readable.
	setCompact (phones: touch, or the HUD's UIScale at about its floor):
	every text at least BuildView.MinText design units, the tray cards
	without their category band, a wider, shorter info card (a smaller
	picture, no description, the size in the category chip) that never
	grows past the room between the controls and the slot pill.
	Machine pictures are live ViewportFrames of MachineBuilder.build(id)
	(no uploads: the icon sheets have no ids yet; picture()), built once
	per tray card when it first shows and once per machine for the info
	card, then reused; never animated.
	menuButton / setMenuKey / setMenuBadge: the HUD's BUILD tile with its
	key hint (B, the gamepad glyph) and the count of machines to place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local MachineData = require(Shared.Config.MachineData)
local UIConfig = require(Shared.Config.UIConfig)
local IconAssets = require(Shared.Config.IconAssets)
local BubbleTheme = require(Shared.Config.BubbleTheme)
local MachineBuilder = require(Shared.Builders.MachineBuilder)
local MachineInfo = require(Shared.Machines.MachineInfo)
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
	Picture: ViewportFrame?, -- the live 3D machine (filled once when the card first shows)
	Power: TextLabel?, -- the power chip's text (nil: no part in power)
}

-- One chip of the controls row: keycaps (or gamepad buttons) and what they do.
export type Key = {
	Caps: { string }, -- keycap texts ("LMB", "R"); a gamepad's fallback names ("A")
	Pads: { Enum.KeyCode }?, -- gamepad buttons (glyph images), one per cap
	Text: string,
}

export type KeyOptions = {
	Belt: boolean?, -- placing a belt (click or drag lays a line)
	Decks: boolean?, -- the plot has platforms (the Deck / Ground key)
}

-- The machine info card.
export type InfoCard = {
	Frame: Frame,
	View: ViewportFrame, -- the live 3D machine
	Name: TextLabel,
	Category: TextLabel,
	Footprint: TextLabel, -- "2x2 cells"
	Flow: TextLabel, -- "Clean ore -> 2 Crushed ore · 3 s"
	Power: TextLabel,
	Output: TextLabel,
	Note: TextLabel, -- the selected machine's state right now
	Description: TextLabel,
	Room: UISizeConstraint, -- its height cap (setCompact)
	Id: string?, -- the machine shown now
	Shown: MachineInfo.Info?, -- what it shows now, and the note (setCompact redraws them)
	ShownNote: string?,
	Models: { [string]: Model }, -- pictures built so far (one per machine)
	Cameras: { [string]: CFrame },
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
	Layer: TextButton, -- the Deck / Ground toggle (platforms)
	Done: TextButton,
	Shop: TextButton, -- the Tech shop's machines (top right, under DONE)
	EmptyShop: TextButton, -- the empty tray's SHOP
	Keys: Frame, -- the controls row (setKeys)
	Info: InfoCard,
	OnPick: ((string) -> ())?,
	OnHover: ((string, boolean) -> ())?, -- a tray card is hovered / selected (true) or left
	Compact: boolean, -- the phone sizes (setCompact)
}

local rgb = Color3.fromRGB

BuildView.CategoryColors = {
	Processing = rgb(236, 128, 56),
	Storage = rgb(176, 124, 74),
	Logistics = rgb(90, 160, 230),
	Selling = rgb(110, 214, 92),
	Power = rgb(250, 204, 70),
} :: { [string]: Color3 }

-- The Deck / Ground toggle's text for each layer (BuildView.setLayer).
BuildView.LayerText = { Deck = "DECK", Ground = "GROUND" }

BuildView.ReasonColors = {
	Bad = Theme.Bad,
	Warn = rgb(255, 210, 80),
	Good = rgb(110, 230, 120),
	Info = Theme.Text,
} :: { [string]: Color3 }

BuildView.EmptyText = "Buy machines with SHOP"
BuildView.OutputColor = rgb(255, 160, 40) -- the amber plate of the output cell

-- Design-unit sizes (the HUD's UIScale shrinks them on small screens).
BuildView.TouchButtonHeight = 76
BuildView.TrayHeight = 112
local CARD_WIDTH = 118
local CARD_HEIGHT = 96
local ACTION_GAP = 10
local EDGE = 16
local KEY_HEIGHT = 36 -- a controls chip
local CAP_SIZE = 28 -- a keycap / gamepad glyph in it
local KEYS_ABOVE = 58 -- the controls row's bottom over the tray
local INFO_ABOVE = 104 -- the info card's bottom over the tray (above the reason and controls rows)
local INFO_WIDTH = 330
local INFO_PICTURE = 76
local INFO_PAD = 10
local PICTURE_FOV = 30
-- phones (setCompact)
local INFO_WIDTH_COMPACT = 400 -- wider, so its lines wrap less
local INFO_PICTURE_COMPACT = 48
BuildView.CompactScale = 0.7 -- the HUD's UIScale at or under which build mode uses the phone sizes
BuildView.MinText = 16 -- design units: no text smaller on a phone (about 10 px at the 0.62 floor)
BuildView.InfoBottom = BuildView.TrayHeight + INFO_ABOVE -- the info card's bottom edge over the screen's
BuildView.PillRoom = 70 -- design units the slot pill (and its build icon) takes at the top, with a gap

-- Which touch buttons each mode shows.
local MODE_BUTTONS: { [string]: { [string]: boolean } } = {
	Idle = {},
	Placing = { Cancel = true, Rotate = true, Place = true },
	Selected = { Cancel = true, Move = true, PackUp = true },
	Moving = { Cancel = true, Rotate = true, PackUp = true, Place = true },
}

---------------------------------------------------------------- controls (keycap chips)

local function key(caps: { string }, text: string): Key
	return { Caps = caps, Pads = nil, Text = text }
end

local function pad(pads: { Enum.KeyCode }, caps: { string }, text: string): Key
	return { Caps = caps, Pads = pads, Text = text }
end

local K = Enum.KeyCode

-- The controls row per device and mode (keys() adds the belt and deck variants).
BuildView.Keys = {
	Mouse = {
		Idle = { key({ "LMB" }, "Select"), key({ "WASD" }, "Pan"), key({ "WHEEL" }, "Zoom"), key({ "B" }, "Done") },
		Placing = { key({ "LMB" }, "Place"), key({ "R" }, "Rotate"), key({ "RMB" }, "Cancel"), key({ "B" }, "Done") },
		PlacingBelt = { key({ "LMB" }, "Place, drag a line"), key({ "R" }, "Rotate"), key({ "RMB" }, "Cancel"), key({ "B" }, "Done") },
		Selected = { key({ "LMB", "M" }, "Move"), key({ "X" }, "Pack up"), key({ "RMB" }, "Back"), key({ "B" }, "Done") },
		Moving = { key({ "LMB" }, "Put here"), key({ "R" }, "Rotate"), key({ "X" }, "Pack up"), key({ "RMB" }, "Cancel") },
	},
	Gamepad = {
		Idle = {
			pad({ K.ButtonL1, K.ButtonR1 }, { "LB", "RB" }, "Pick"),
			pad({ K.Thumbstick1 }, { "LS" }, "Cursor"),
			pad({ K.DPadLeft }, { "LEFT" }, "Shop"),
			pad({ K.ButtonB }, { "B" }, "Done"),
		},
		Placing = {
			pad({ K.ButtonA }, { "A" }, "Place"),
			pad({ K.ButtonX }, { "X" }, "Rotate"),
			pad({ K.ButtonL1, K.ButtonR1 }, { "LB", "RB" }, "Change"),
			pad({ K.ButtonB }, { "B" }, "Cancel"),
		},
		Selected = {
			pad({ K.ButtonA }, { "A" }, "Move"),
			pad({ K.ButtonY }, { "Y" }, "Hold: pack up"),
			pad({ K.ButtonL1, K.ButtonR1 }, { "LB", "RB" }, "Pick"),
			pad({ K.ButtonB }, { "B" }, "Back"),
		},
		Moving = {
			pad({ K.ButtonA }, { "A" }, "Put here"),
			pad({ K.ButtonX }, { "X" }, "Rotate"),
			pad({ K.ButtonY }, { "Y" }, "Hold: pack up"),
			pad({ K.ButtonB }, { "B" }, "Cancel"),
		},
	},
	Touch = {
		Idle = { key({ "TAP" }, "A machine below, or one of yours"), key({ "DRAG" }, "Pan"), key({ "PINCH" }, "Zoom") },
		Placing = { key({ "TAP" }, "Where it goes"), key({ "PLACE" }, "Put it there") },
		Selected = { key({ "MOVE" }, "Pick it up"), key({ "PACK UP" }, "Back to the tray"), key({ "TAP" }, "Another machine") },
		Moving = { key({ "TAP" }, "Where it goes"), key({ "PLACE" }, "Put it there") },
	},
} :: { [string]: { [string]: { Key } } }

-- The Deck / Ground key (while the plot has platforms; not in Idle: that row is long already).
BuildView.DeckKeys = {
	Mouse = key({ "V" }, "Deck / ground"),
	Gamepad = pad({ K.DPadUp }, { "UP" }, "Deck / ground"),
} :: { [string]: Key }

--[[
	The controls row for a device ("Mouse" | "Gamepad" | "Touch") and a
	build mode: a fresh list (callers may change it). Unknown devices or
	modes get an empty row.
]]
function BuildView.keys(kind: string, mode: string, opts: KeyOptions?): { Key }
	local rows = BuildView.Keys[kind]
	if not rows then
		return {}
	end
	local o: KeyOptions = opts or {}
	local row = rows[mode]
	if mode == "Placing" and o.Belt and rows.PlacingBelt then
		row = rows.PlacingBelt
	end
	local list: { Key } = if row then table.clone(row) else {}
	local deck = BuildView.DeckKeys[kind]
	if o.Decks and deck and mode ~= "Idle" and #list > 0 then
		table.insert(list, deck)
	end
	return list
end

---------------------------------------------------------------- the look (light or dark)

type Palette = {
	Panel: Color3,
	Outline: Color3,
	Text: Color3,
	Dim: Color3,
	Well: Color3, -- the picture's background
	Power: Color3,
	Cap: Color3, -- keycap face
	CapInk: Color3,
	Font: Font,
}

local function paletteOf(light: boolean): Palette
	if light then
		return {
			Panel = BubbleTheme.Panel,
			Outline = BubbleTheme.Outline,
			Text = BubbleTheme.Ink,
			Dim = BubbleTheme.InkSoft,
			Well = BubbleTheme.PanelTint,
			Power = BubbleTheme.Gold,
			Cap = BubbleTheme.White,
			CapInk = BubbleTheme.DarkInk,
			Font = BubbleTheme.Font,
		}
	end
	return {
		Panel = Theme.Panel,
		Outline = Theme.Outline,
		Text = Theme.Text,
		Dim = Theme.TextDim,
		Well = Theme.PanelDark,
		Power = Theme.Coin,
		Cap = Theme.Text,
		CapInk = Theme.Outline,
		Font = Theme.Font,
	}
end

local function isLight(refs: Refs): boolean
	return refs.Gui:GetAttribute("Bubble") == true
end

-- A plain text line (no outline: it sits on a solid panel).
local function line(parent: Instance, text: string, size: number, color: Color3, font: Font, props: UIKit.Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color,
		FontFace = font,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	if props then
		for k, value in props do
			(label :: any)[k] = value
		end
	end
	return label
end

---------------------------------------------------------------- machine pictures

--[[
	A machine model for a picture (MachineBuilder.build, so it looks exactly
	like the placed one) with nothing live left in it: no tags (client
	effects must not mistake it for a real belt or machine), no MachineId,
	no lights, particles or GUIs; anchored. Also the camera CFrame that
	frames it from the front right, a little from above (the front, -Z, is
	where the results come out).
]]
function BuildView.picture(id: string): (Model, CFrame)
	local model = MachineBuilder.build(id)
	model.Name = "Picture"
	model:SetAttribute("MachineId", nil)
	for _, tag in model:GetTags() do
		model:RemoveTag(tag)
	end
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in model:GetDescendants() do
		for _, tag in d:GetTags() do
			d:RemoveTag(tag)
		end
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			-- the part's world-aligned box
			local cf, half = d.CFrame, d.Size / 2
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local extent = Vector3.new(
				math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
				math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
				math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
			)
			lo = lo:Min(cf.Position - extent)
			hi = hi:Max(cf.Position + extent)
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") then
			local effect: any = d
			effect.Enabled = false
		elseif d:IsA("LayerCollector") then
			d.Enabled = false
		end
	end
	if lo.X > hi.X then
		lo, hi = -Vector3.one, Vector3.one
	end
	local center = (lo + hi) / 2
	local radius = math.max(0.5, (hi - lo).Magnitude / 2)
	local from = Vector3.new(0.8, 0.7, -1).Unit * (radius / math.sin(math.rad(PICTURE_FOV / 2)) * 0.92)
	return model, CFrame.lookAt(center + from, center)
end

local function newViewport(parent: Instance, props: UIKit.Props): ViewportFrame
	local view = UIKit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Ambient = rgb(170, 166, 160),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.5, -1, 0.4),
	}, parent)
	for k, value in props do
		(view :: any)[k] = value
	end
	return view
end

-- Shows `model` in a ViewportFrame through its own camera.
local function showPicture(view: ViewportFrame, model: Model, cf: CFrame)
	local camera = view:FindFirstChildOfClass("Camera")
	if not camera then
		local created = Instance.new("Camera")
		created.FieldOfView = PICTURE_FOV
		created.Parent = view
		camera = created
	end
	local cam = camera :: Camera
	cam.CFrame = cf
	view.CurrentCamera = cam
	model.Parent = view
end

-- Builds a tray card's picture (once: a card that has one keeps it).
function BuildView.fillPicture(entry: Card, id: string)
	local view = entry.Picture
	if not view or view:FindFirstChild("Picture") or not MachineData.ById[id] then
		return
	end
	local model, cf = BuildView.picture(id)
	showPicture(view, model, cf)
end

-- Does this machine have an uploaded icon (else the card shows the live picture)?
function BuildView.hasIcon(id: string): boolean
	local image = IconAssets.find("machine_" .. id)
	return image ~= ""
end

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
	local chipText = MachineInfo.powerChip(machine.Id)
	UIKit.label(band, string.upper(machine.Category), 12, {
		Name = "Category",
		Position = UDim2.fromOffset(if chipText then 8 else 0, 0),
		Size = if chipText then UDim2.new(1, -60, 1, 0) else UDim2.fromScale(1, 1),
		TextXAlignment = if chipText then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
	})
	local power: TextLabel? = nil
	if chipText then
		power = UIKit.chip(band, chipText, if machine.Power then Theme.Accent else Theme.Good, {
			Name = "PowerChip",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -3, 0.5, 0),
			Size = UDim2.fromOffset(50, 18),
			TextSize = 13,
		})
	end
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
	return { Button = button, Count = count, Stroke = stroke, Bound = false, Picture = nil, Power = power }
end

--[[
	The machine info card, bottom left over the tray (hidden until setInfo):
	  [picture]  NAME
	             CATEGORY  2x2 cells
	  Clean ore -> 2 Crushed ore · 3 s
	  Needs 10 power: a pole within 3 cells, else 60% speed
	  Results come out the FRONT (amber square)
	  (the selected machine's state now)
	  Description
	It grows with its text (AutomaticSize).
]]
local function infoCard(gui: ScreenGui, light: boolean): InfoCard
	local p = paletteOf(light)
	-- Active: a click or tap on the card stays on it (never places or
	-- moves the ghost under it); ClipsDescendants: capped by Room
	local frame = UIKit.new("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -BuildView.InfoBottom),
		Size = UDim2.fromOffset(INFO_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = p.Panel,
		BorderSizePixel = 0,
		Active = true,
		ClipsDescendants = true,
		Visible = false,
	}, gui)
	UIKit.corner(frame, 16)
	UIKit.stroke(frame, 3, p.Outline)
	UIKit.padding(frame, INFO_PAD)
	UIKit.list(frame, Enum.FillDirection.Vertical, 4)
	local room = UIKit.new("UISizeConstraint", { Name = "Room" }, frame)

	local header = UIKit.new("Frame", {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, INFO_PICTURE),
		BackgroundTransparency = 1,
	}, frame)
	local view = newViewport(header, {
		Name = "View",
		Size = UDim2.fromOffset(INFO_PICTURE, INFO_PICTURE),
		BackgroundColor3 = p.Well,
		BackgroundTransparency = 0,
	})
	UIKit.corner(view, 12)
	local left = INFO_PICTURE + 10
	local name = line(header, "", 22, p.Text, p.Font, {
		Name = "MachineName",
		Position = UDim2.fromOffset(left, 0),
		Size = UDim2.new(1, -left, 0, 28),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local category = line(header, "", 13, Color3.new(1, 1, 1), p.Font, {
		Name = "Category",
		Position = UDim2.fromOffset(left, 31),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Accent,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.corner(category, 11)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, category)
	UIKit.textStroke(category, 1.5, p.Outline)
	local footprint = line(header, "", 15, p.Dim, p.Font, {
		Name = "Footprint",
		Position = UDim2.fromOffset(left, 56),
		Size = UDim2.new(1, -left, 0, 18),
		TextWrapped = false,
	})

	local function row(name: string, order: number, size: number, color: Color3): TextLabel
		return line(frame, "", size, color, p.Font, {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
	end
	return {
		Frame = frame,
		View = view,
		Name = name,
		Category = category,
		Footprint = footprint,
		Flow = row("Flow", 2, 18, p.Text),
		Power = row("Power", 3, 16, p.Power),
		Output = row("Output", 4, 16, BuildView.OutputColor),
		Note = row("Note", 5, 16, BuildView.ReasonColors.Warn),
		Description = row("Description", 6, 15, p.Dim),
		Room = room,
		Id = nil,
		Shown = nil,
		ShownNote = nil,
		Models = {},
		Cameras = {},
	}
end

-- The controls row (setKeys fills it with chips), above the reason line.
local function keysRow(gui: ScreenGui): Frame
	local row = UIKit.new("Frame", {
		Name = "Keys",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BuildView.TrayHeight + KEYS_ABOVE)),
		Size = UDim2.fromOffset(0, KEY_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	return row
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
-- whole card) holding a light body in the category colour: the category
-- band, the live 3D picture (or the uploaded icon), the power chip on the
-- top right corner, the name and the count chip on the bottom edge.
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
	local role = Bubble.roleFrom(color)
	local holder, face = Bubble.body(button, role, Vector2.new(w, h), { Name = "Body", Corner = 16 })
	holder.Size = UDim2.fromScale(1, 1)
	local band = UIKit.new("Frame", {
		Name = "Band",
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 15),
		BackgroundColor3 = role.Lip,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, face)
	Bubble.corner(band, 7)
	Bubble.text(band, string.upper(machine.Category), 11, {
		Name = "Category",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	})
	local picture: ViewportFrame? = nil
	if BuildView.hasIcon(machine.Id) then
		Bubble.icon(face, BuildView.iconFor(machine.Id), 46, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18),
		})
	else
		picture = newViewport(face, {
			Name = "Picture",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 19),
			Size = UDim2.new(1, -8, 0, 42),
			ZIndex = 3,
		})
	end
	Bubble.text(face, machine.Name, 15, {
		Name = "MachineName",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -8, 0, 17),
		TextScaled = true,
		ZIndex = 4,
	})
	local chip = Bubble.chip(face, "x0", Vector2.new(64, 22), 16, nil, {
		Name = "CountChip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
	})
	local power: TextLabel? = nil
	local chipText = MachineInfo.powerChip(machine.Id)
	if chipText then
		local powerChip = Bubble.chip(face, chipText, Vector2.new(48, 20), 13, if machine.Power then "Build" else "Go", {
			Name = "PowerChip",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 6, 0, 2),
			ZIndex = 6,
		})
		local text = powerChip:FindFirstChild("Text") :: TextLabel
		text.ZIndex = 7
		power = text
	end
	local stroke = face:FindFirstChildOfClass("UIStroke") :: UIStroke
	return {
		Button = button,
		Count = chip:FindFirstChild("Text") :: TextLabel,
		Stroke = stroke,
		Bound = false,
		Picture = picture,
		Power = power,
	}
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

	local done =
		Bubble.button(gui, { Name = "Done", Text = "DONE", Role = "Go", Size = Vector2.new(150, 58), Icon = "check", TextSize = 26 })
	local doneHolder = done.Parent :: Frame
	doneHolder.AnchorPoint = Vector2.new(1, 0)
	doneHolder.Position = UDim2.new(1, -EDGE, 0, EDGE + 4)
	-- SHOP under DONE: the Tech shop's machines (not next to it: the slot pill is there on narrow screens)
	local shop =
		Bubble.button(gui, { Name = "Shop", Text = "SHOP", Role = "Shop", Size = Vector2.new(150, 66), Icon = "shop", TextSize = 26 })
	local shopHolder = shop.Parent :: Frame
	shopHolder.AnchorPoint = Vector2.new(1, 0)
	shopHolder.Position = UDim2.new(1, -EDGE, 0, EDGE + 4 + 58 + BubbleTheme.Lip + 12)

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
	-- the empty tray: "Buy machines with SHOP" [SHOP], in the middle of the tray
	local middle = -(12 + BuildView.TrayHeight / 2)
	local empty = Bubble.text(gui, BuildView.EmptyText, 22, {
		Name = "Empty",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -10, 1, middle),
		Size = UDim2.fromOffset(360, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
		Visible = false,
	})
	local emptyShop =
		Bubble.button(gui, { Name = "EmptyShop", Text = "SHOP", Role = "Shop", Size = Vector2.new(150, 66), Icon = "shop", TextSize = 26 })
	local emptyHolder = emptyShop.Parent :: Frame
	emptyHolder.AnchorPoint = Vector2.new(0, 0.5)
	emptyHolder.Position = UDim2.new(0.5, 10, 1, middle)
	emptyHolder.ZIndex = 3
	emptyHolder.Visible = false

	-- reason and the controls above the tray, the info card left of them
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
		Layer = lightAction(actions, "Layer", BuildView.LayerText.Deck, "Lobby", 124, 0),
		Done = done,
		Shop = shop,
		EmptyShop = emptyShop,
		Keys = keysRow(gui),
		Info = infoCard(gui, true),
		OnPick = nil,
		OnHover = nil,
		Compact = false,
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
	-- SHOP under it: the Tech shop's machines
	local shop = UIKit.button(gui, "SHOP", Theme.Info, rgb(60, 120, 190), {
		Name = "Shop",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, EDGE + 4 + 64 + 14),
		Size = UDim2.fromOffset(120, 64),
		TextSize = 24,
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
	local middle = -(12 + BuildView.TrayHeight / 2)
	local empty = UIKit.label(gui, BuildView.EmptyText, 22, {
		Name = "Empty",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -10, 1, middle),
		Size = UDim2.fromOffset(360, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	})
	local emptyShop = UIKit.button(gui, "SHOP", Theme.Info, rgb(60, 120, 190), {
		Name = "EmptyShop",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 10, 1, middle),
		Size = UDim2.fromOffset(130, 64),
		TextSize = 24,
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
	local layer = actionButton(actions, "Layer", BuildView.LayerText.Deck, rgb(90, 160, 230), rgb(50, 104, 170), 120, 0)
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
		Layer = layer,
		Done = done,
		Shop = shop,
		EmptyShop = emptyShop,
		Keys = keysRow(gui),
		Info = infoCard(gui, false),
		OnPick = nil,
		OnHover = nil,
		Compact = false,
	}
end

--[[
	The empty tray's text and SHOP button: shown while the tray is empty
	(setInventory) and no touch buttons show (setMode: in Placing, Selected
	and Moving they sit right where SHOP would be, and a tap meant for
	CANCEL would open the shop). SHOP under DONE is always there.
]]
local function showEmpty(refs: Refs)
	local show = refs.Gui:GetAttribute("TrayEmpty") == true and refs.Gui:GetAttribute("ActionsShown") ~= true
	refs.Empty.Visible = show
	local shopHolder = refs.EmptyShop.Parent
	if shopHolder and shopHolder:IsA("GuiObject") then
		shopHolder.Visible = show
	end
end

--[[
	Shows a card for every machine you have left to place (count > 0), in
	MachineData order, and marks the selected one. Clicking or tapping a
	card calls onPick(id); hovering it with the mouse or selecting it with
	a gamepad calls onHover(id, true), leaving it onHover(id, false) (the
	latest callbacks passed here). A card's picture is built the first time
	it shows. An empty tray says "Buy machines with SHOP" with a SHOP button
	(showEmpty).
]]
function BuildView.setInventory(
	refs: Refs,
	inventory: { [string]: number },
	selected: string?,
	onPick: (id: string) -> (),
	onHover: ((id: string, on: boolean) -> ())?
)
	refs.OnPick = onPick
	refs.OnHover = onHover
	local any = false
	for id, entry in refs.Cards do
		local count = inventory[id]
		local n = if type(count) == "number" then math.max(0, math.floor(count)) else 0
		local show = n > 0
		entry.Button.Visible = show
		any = any or show
		entry.Count.Text = `x{n}`
		if show then
			BuildView.fillPicture(entry, id)
		end
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
			local button = entry.Button
			button.Activated:Connect(function()
				local callback = refs.OnPick
				if callback then
					callback(id)
				end
			end)
			local function hover(on: boolean)
				local callback = refs.OnHover
				if callback then
					callback(id, on)
				end
			end
			button.MouseEnter:Connect(function()
				hover(true)
			end)
			button.MouseLeave:Connect(function()
				hover(false)
			end)
			pcall(function() -- (Lune's instances have no selection events)
				button.SelectionGained:Connect(function()
					hover(true)
				end)
				button.SelectionLost:Connect(function()
					hover(false)
				end)
			end)
		end
	end
	refs.Gui:SetAttribute("TrayEmpty", not any)
	showEmpty(refs)
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

-- kind: 'Bad' (red, can't place), 'Warn' (yellow), 'Good' (green), 'Info' (white); nil text hides it.
function BuildView.setReason(refs: Refs, text: string?, kind: string?)
	if not text or text == "" then
		refs.Reason.Visible = false
		return
	end
	refs.Reason.Text = text
	refs.Reason.TextColor3 = BuildView.ReasonColors[kind or "Info"] or Theme.Text
	refs.Reason.Visible = true
end

-- A one-line text hint (the controls row, setKeys, replaced it in the game); nil hides it.
function BuildView.setHint(refs: Refs, text: string?)
	refs.Hint.Text = text or ""
	refs.Hint.Visible = text ~= nil and text ~= ""
end

-- One chip of the controls row: its keycaps (or gamepad glyph images) and its text.
local function keyChip(row: Frame, k: Key, images: { string }, order: number, p: Palette): Frame
	local chip = UIKit.new("Frame", {
		Name = "Key",
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, KEY_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = p.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Active = true, -- a tap on "[PLACE] Put it there" is not a tap on the plot
	}, row)
	UIKit.corner(chip, KEY_HEIGHT // 2)
	UIKit.stroke(chip, 2.5, p.Outline)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 12) }, chip)
	UIKit.list(chip, Enum.FillDirection.Horizontal, 5, { VerticalAlignment = Enum.VerticalAlignment.Center })
	for i, cap in k.Caps do
		local image = images[i]
		if image and image ~= "" then
			UIKit.new("ImageLabel", {
				Name = "Glyph",
				LayoutOrder = i,
				BackgroundTransparency = 1,
				Image = image,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(CAP_SIZE, CAP_SIZE),
			}, chip)
		else
			local label = line(chip, cap, 16, p.CapInk, p.Font, {
				Name = "Cap",
				LayoutOrder = i,
				Size = UDim2.fromOffset(CAP_SIZE, CAP_SIZE),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 0,
				BackgroundColor3 = p.Cap,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			UIKit.corner(label, 7)
			UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, label)
		end
	end
	line(chip, k.Text, 19, p.Text, p.Font, {
		Name = "Text",
		LayoutOrder = 100,
		Size = UDim2.fromOffset(0, KEY_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
	})
	return chip
end

--[[
	Fills the controls row with one chip per key (BuildView.keys). With
	`glyph` (a gamepad: UserInputService:GetImageForKeyCode, via
	MenuPanels.glyph) a key's Pads show as the platform's own button
	images; a button without an image shows its cap text. An empty list
	hides the row. The same row again rebuilds nothing.
]]
function BuildView.setKeys(refs: Refs, keys: { Key }, glyph: ((Enum.KeyCode) -> string)?)
	local row = refs.Keys
	local images: { { string } } = {}
	local parts: { string } = {}
	for i, k in keys do
		local list: { string } = {}
		local pads = k.Pads
		if glyph and pads then
			for j, keyCode in pads do
				list[j] = glyph(keyCode)
			end
		end
		images[i] = list
		table.insert(parts, `{table.concat(k.Caps, "+")}|{table.concat(list, "+")}|{k.Text}`)
	end
	local signature = table.concat(parts, ";")
	refs.Hint.Visible = false
	row.Visible = #keys > 0
	if row:GetAttribute("Keys") == signature then
		return
	end
	row:SetAttribute("Keys", signature)
	for _, child in row:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local p = paletteOf(isLight(refs))
	for i, k in keys do
		keyChip(row, k, images[i], i, p)
	end
end

-- The chips of the controls row in order (tests).
function BuildView.keyChips(refs: Refs): { Frame }
	local list: { Frame } = {}
	for _, child in refs.Keys:GetChildren() do
		if child:IsA("Frame") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return list
end

local function setLine(label: TextLabel, text: string?)
	label.Text = text or ""
	label.Visible = text ~= nil and text ~= ""
end

--[[
	The machine info card: `info` (MachineInfo.describe) with its live 3D
	picture (built once per machine, then reused), or nil to hide it.
	`note` is an extra line in yellow (the selected machine's state now).
	Compact (setCompact): the size rides in the category chip and the
	description is left out.
]]
function BuildView.setInfo(refs: Refs, info: MachineInfo.Info?, note: string?)
	local card = refs.Info
	card.Shown, card.ShownNote = info, note
	if not info then
		card.Frame.Visible = false
		return
	end
	if card.Id ~= info.Id then
		card.Id = info.Id
		local p = paletteOf(isLight(refs))
		local category = string.upper(info.Category)
		card.Name.Text = info.Name
		card.Category.Text = if refs.Compact then `{category}  {info.Size}` else category
		card.Category.BackgroundColor3 = BuildView.CategoryColors[info.Category] or Theme.Accent
		card.Footprint.Text = info.Size
		setLine(card.Flow, info.Flow)
		setLine(card.Power, info.PowerText)
		card.Power.TextColor3 = if info.PowerText == MachineInfo.NoPowerText then p.Dim else p.Power
		setLine(card.Output, info.OutputText)
		setLine(card.Description, if refs.Compact then nil else info.Description)
		-- the picture: one model per machine, built the first time it shows
		for _, child in card.View:GetChildren() do
			if child:IsA("Model") then
				child.Parent = nil
			end
		end
		local model, cf = card.Models[info.Id], card.Cameras[info.Id]
		if not model or not cf then
			local built, fit = BuildView.picture(info.Id)
			card.Models[info.Id], card.Cameras[info.Id] = built, fit
			model, cf = built, fit
		end
		showPicture(card.View, model, cf)
	end
	setLine(card.Note, note)
	card.Frame.Visible = true
end

local function holderOf(button: TextButton): GuiObject?
	local parent = button.Parent
	return if parent and parent:IsA("GuiObject") then parent else nil
end

-- The room the info card has on a ScreenGui `height` design units tall:
-- from its bottom (over the controls row) up to the slot pill.
function BuildView.infoRoom(height: number): number
	return math.max(INFO_PICTURE_COMPACT + 2 * INFO_PAD, height - BuildView.InfoBottom - BuildView.PillRoom)
end

local function findGui(parent: Instance, name: string): GuiObject?
	local found = parent:FindFirstChild(name, true)
	return if found and found:IsA("GuiObject") then found else nil
end

-- A tray card in the phone sizes or back: no category band (its text
-- would be under MinText; the light card's body and the dark band keep
-- the category colour), a bigger picture, power chip and size text.
local function compactCard(entry: Card, light: boolean, compact: boolean)
	local button = entry.Button
	local power = entry.Power
	local chip = if power then power.Parent else nil
	if light then
		local band = findGui(button, "Band")
		if band then
			band.Visible = not compact
		end
		local picture = entry.Picture
		if picture then
			picture.Position = UDim2.new(0.5, 0, 0, if compact then 4 else 19)
			picture.Size = UDim2.new(1, -8, 0, if compact then 52 else 42)
		end
		local name = findGui(button, "MachineName")
		if name then
			name.Size = UDim2.new(1, -8, 0, if compact then 20 else 17)
		end
		if power and chip and chip:IsA("Frame") then
			chip.Size = if compact then UDim2.fromOffset(58, 24) else UDim2.fromOffset(48, 20)
			power.TextSize = if compact then BuildView.MinText else 13
			local corner = chip:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(0, if compact then 12 else 10)
			end
		end
		return
	end
	local category = findGui(button, "Category")
	if category then
		category.Visible = not compact
	end
	if power then
		power.Size = if compact then UDim2.fromOffset(58, 22) else UDim2.fromOffset(50, 18)
		power.TextSize = if compact then BuildView.MinText else 13
	end
	local footprint = findGui(button, "Footprint")
	if footprint and footprint:IsA("TextLabel") then
		footprint.Size = if compact then UDim2.fromOffset(48, 20) else UDim2.fromOffset(40, 18)
		footprint.TextSize = if compact then BuildView.MinText else 13
	end
end

--[[
	Phone sizes on or off (PlacementController: touch, or the HUD's UIScale
	at or under CompactScale), and the info card's height cap `room` in
	design units (BuildView.infoRoom; nil: none). Tray cards: compactCard.
	The info card gets wider and shorter: a 48 picture, the size in the
	category chip (MinText), no description. What it shows is redrawn.
]]
function BuildView.setCompact(refs: Refs, compact: boolean, room: number?)
	local card = refs.Info
	card.Room.MaxSize = Vector2.new(math.huge, if room then math.max(room, 0) else math.huge)
	if refs.Compact == compact then
		return
	end
	refs.Compact = compact
	local light = isLight(refs)
	for _, entry in refs.Cards do
		compactCard(entry, light, compact)
	end
	local picture = if compact then INFO_PICTURE_COMPACT else INFO_PICTURE
	local left = picture + 10
	card.Frame.Size = UDim2.fromOffset(if compact then INFO_WIDTH_COMPACT else INFO_WIDTH, 0)
	local header = card.View.Parent
	if header and header:IsA("Frame") then
		header.Size = UDim2.new(1, 0, 0, picture)
	end
	card.View.Size = UDim2.fromOffset(picture, picture)
	card.Name.Position = UDim2.fromOffset(left, 0)
	card.Name.Size = UDim2.new(1, -left, 0, if compact then 24 else 28)
	card.Category.Position = UDim2.fromOffset(left, if compact then 26 else 31)
	card.Category.TextSize = if compact then BuildView.MinText else 13
	card.Footprint.Position = UDim2.fromOffset(left, 56)
	card.Footprint.Size = UDim2.new(1, -left, 0, 18)
	card.Footprint.Visible = not compact
	-- redraw what it shows in the new sizes
	card.Id = nil
	local shown = card.Shown
	if shown then
		BuildView.setInfo(refs, shown, card.ShownNote)
	end
end

-- Shows the touch buttons that fit the mode (touch only) and makes room
-- for them next to the tray. `layers`: the plot has platforms, so the
-- Deck / Ground toggle shows too (in every mode: it also picks what a tap
-- selects on a deck).
function BuildView.setMode(refs: Refs, mode: Mode, isTouch: boolean, layers: boolean?)
	local wanted = MODE_BUTTONS[mode] or {}
	local shown = 0
	local width = 0
	local buttons: { [string]: TextButton } = {
		Cancel = refs.Cancel,
		Rotate = refs.Rotate,
		Move = refs.Move,
		PackUp = refs.PackUp,
		Place = refs.Place,
		Layer = refs.Layer,
	}
	for name, button in buttons do
		local visible = isTouch and (wanted[name] == true or (name == "Layer" and layers == true))
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
	refs.Gui:SetAttribute("ActionsShown", shown > 0)
	showEmpty(refs)
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

-- The Deck / Ground toggle shows the layer it works on now.
function BuildView.setLayer(refs: Refs, ground: boolean)
	local text = if ground then BuildView.LayerText.Ground else BuildView.LayerText.Deck
	local label = refs.Layer:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text -- the light button's text sits on its Label
	else
		refs.Layer.Text = text
	end
end

-- The BUILD tile's key hint: a keycap on its top left corner (hidden until setMenuKey).
local function menuKeyCap(button: GuiObject): Frame
	local existing = button:FindFirstChild("KeyCap")
	if existing and existing:IsA("Frame") then
		return existing
	end
	local cap = UIKit.new("Frame", {
		Name = "KeyCap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = BubbleTheme.White,
		BorderSizePixel = 0,
		ZIndex = 5,
		Visible = false,
	}, button)
	Bubble.corner(cap, 8)
	Bubble.stroke(cap, 2.5)
	Bubble.ink(cap, "", 19, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = BubbleTheme.DarkInk,
		ZIndex = 6,
	})
	UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Visible = false,
	}, cap)
	return cap
end

-- The BUILD button for the HUD's right-side menu (HudController.refs().Menu).
function BuildView.menuButton(menu: Instance): TextButton
	local button: TextButton
	if menu:GetAttribute("Bubble") then
		button = HudBubble.claimTile(menu, "Build") -- the light HUD's BUILD tile
	else
		button = UIKit.button(menu, "BUILD", Theme.Accent, Theme.AccentDark, {
			Name = "Build",
			LayoutOrder = 10,
			Size = UDim2.fromOffset(84, 64),
			TextSize = 20,
		})
	end
	menuKeyCap(button)
	return button
end

-- The BUILD tile's key: `cap` on a keycap ("B"), or the gamepad's own
-- glyph `image` (D-pad Up); neither hides it (touch: the tile is the way).
function BuildView.setMenuKey(button: TextButton, cap: string?, image: string?)
	local frame = menuKeyCap(button)
	local text = frame:FindFirstChild("Text") :: TextLabel
	local glyph = frame:FindFirstChild("Glyph") :: ImageLabel
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local hasImage = image ~= nil and image ~= ""
	glyph.Image = image or ""
	glyph.Visible = hasImage
	text.Text = if hasImage then "" else cap or ""
	text.Visible = not hasImage
	frame.BackgroundTransparency = if hasImage then 1 else 0
	if stroke then
		stroke.Enabled = not hasImage
	end
	frame.Visible = hasImage or (cap ~= nil and cap ~= "")
end

-- The BUILD tile's badge: how many machines wait to be placed (0 hides it).
function BuildView.setMenuBadge(button: TextButton, count: number)
	HudBubble.setTileBadge(button, math.max(0, math.floor(count)))
end

return BuildView
