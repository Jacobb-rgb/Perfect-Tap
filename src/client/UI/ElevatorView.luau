--[[
	ElevatorView: what the elevator's screens share. (The floor picker is
	UI/ElevatorWindow since the owner's new ELEVATOR window, 2026-11-15.)

	  floors   FloorColors / floorColor: a floor's colour (the window's cards
	           and TRAVEL buttons, the ride's door stripes, counter and
	           banner); floorRarities: the rarities of its ores (the chips)
	  Pop      the round-look window pieces the backpack shop uses (paintFrom,
	           popWindow, fitWindow, popFooter, popButton, paintButton) and
	           measure: a word's width (TextService in the game,
	           ElevatorController sets Measure; tables in Lune)
	  fade     the void rescue's black screen (buildFade, setFadeText)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared.Config.MineFloors)
local OreData = require(Shared.Config.OreData)
local PopTheme = require(Shared.Config.PopTheme)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local ElevatorView = {}

-- a Pop button (Pop.price's face: the drawn icons, the robux mark and the word in a row) in a holder
export type ButtonRefs = {
	Holder: Frame,
	Edge: UIStroke,
	Button: TextButton,
	Gradient: UIGradient,
	Row: GuiObject,
	Icons: { [string]: Frame },
	Label: TextLabel,
	LabelStroke: UIStroke,
	Style: string,
}

export type Fade = {
	Gui: ScreenGui,
	Black: Frame,
	Title: TextLabel,
	Name: TextLabel,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT = rgb(255, 255, 255)
local NEON_BRIGHT = rgb(120, 210, 255)
local OUTLINE = PopTheme.Outline

-- each floor's colour (owner 2026-11-15: brown / stone, orange / red, cyan / blue, gold / yellow,
-- purple / violet, magenta / deep purple); grey = coming soon
ElevatorView.FloorColors = {
	Color3.fromHex("#c9955a"),
	Color3.fromHex("#ff6a2a"),
	Color3.fromHex("#2fb6ff"),
	Color3.fromHex("#ffc21a"),
	Color3.fromHex("#9a5cff"),
	Color3.fromHex("#e23fc8"),
} :: { Color3 }
ElevatorView.SoonColor = rgb(118, 124, 146)

---------------------------------------------------------------- measuring text

-- Glyph widths of FredokaOne and LuckiestGuy (1/100 em, ASCII 32..126), measured
-- from the fonts. In the game ElevatorController sets ElevatorView.Measure to
-- TextService, so these only matter for the tests and the preview.
local FREDOKA = {
	25,
	27,
	43,
	75,
	48,
	84,
	75,
	21,
	38,
	38,
	50,
	53,
	24,
	43,
	24,
	53,
	61,
	41,
	61,
	61,
	59,
	53,
	56,
	56,
	58,
	56,
	24,
	24,
	63,
	48,
	63,
	51,
	91,
	77,
	65,
	68,
	70,
	64,
	64,
	71,
	70,
	26,
	55,
	64,
	59,
	87,
	72,
	78,
	63,
	83,
	63,
	58,
	73,
	73,
	78,
	100,
	74,
	69,
	64,
	35,
	53,
	35,
	53,
	83,
	48,
	60,
	59,
	52,
	60,
	57,
	45,
	59,
	61,
	26,
	25,
	54,
	33,
	85,
	61,
	60,
	58,
	58,
	46,
	49,
	45,
	61,
	64,
	79,
	57,
	60,
	59,
	38,
	22,
	38,
	65,
}
local LUCKIEST = {
	20,
	28,
	48,
	61,
	44,
	72,
	63,
	23,
	39,
	38,
	54,
	46,
	22,
	38,
	22,
	50,
	63,
	39,
	51,
	53,
	54,
	53,
	57,
	51,
	57,
	56,
	25,
	25,
	46,
	39,
	46,
	55,
	66,
	63,
	59,
	51,
	58,
	48,
	49,
	63,
	63,
	30,
	51,
	61,
	45,
	79,
	70,
	64,
	60,
	69,
	61,
	53,
	54,
	62,
	61,
	91,
	59,
	61,
	49,
	37,
	51,
	37,
	49,
	30,
	28,
	63,
	59,
	51,
	58,
	58,
	49,
	63,
	63,
	29,
	51,
	60,
	45,
	90,
	65,
	64,
	60,
	69,
	61,
	53,
	54,
	61,
	61,
	91,
	59,
	61,
	50,
	41,
	29,
	40,
	58,
}

-- In the game: TextService (set by ElevatorController); nil = the tables above.
ElevatorView.Measure = nil :: ((text: string, size: number, title: boolean) -> number)?

-- Width of one line of `text` at `size` (FredokaOne, or LuckiestGuy when `title`).
function ElevatorView.measure(text: string, size: number, title: boolean?): number
	local custom = ElevatorView.Measure
	if custom then
		local ok, width = pcall(custom, text, size, title == true)
		if ok and type(width) == "number" and width == width then
			return width
		end
	end
	local widths = if title then LUCKIEST else FREDOKA
	local em = 0
	for _, code in utf8.codes(text) do
		em += if code >= 32 and code <= 126 then widths[code - 31] else 60
	end
	return em / 100 * size
end

---------------------------------------------------------------- floors

function ElevatorView.floorColor(index: number): Color3
	return ElevatorView.FloorColors[index] or ElevatorView.SoonColor
end

-- the rarities in their order (OreData), for the cards' chips
ElevatorView.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- The rarities of a floor's ores (its rocks and its crystal rocks), Common first; {} for no such floor.
function ElevatorView.floorRarities(index: number): { string }
	local floor = MineFloors.ByIndex[index]
	local found: { [string]: boolean } = {}
	if floor then
		for _, weights in { floor.Ores, floor.CrystalOres } do
			for id in weights do
				if OreData.exists(id) then
					found[OreData.get(id).Rarity] = true
				end
			end
		end
	end
	local list: { string } = {}
	for _, rarity in ElevatorView.RarityOrder do
		if found[rarity] then
			table.insert(list, rarity)
		end
	end
	return list
end

---------------------------------------------------------------- Pop pieces (the backpack shop's window uses them)

-- A Pop paint from one colour: a lighter top, a deeper bottom (a floor's card, a board's card).
function ElevatorView.paintFrom(color: Color3, light: number?, deep: number?): Pop.Paint
	return {
		Top = color:Lerp(WHITE, light or 0.1),
		Bottom = color:Lerp(BLACK, deep or 0.35),
		Edge = OUTLINE,
	}
end

export type Chrome = {
	Panel: Frame,
	Header: Frame,
	Body: Frame,
	Title: TextLabel,
	TitleShadow: TextLabel,
	CloseLook: ButtonRefs,
}

--[[
	A Pop window filling `root` (Pop.window: a black frame, the band in
	`paint` with shine stripes and studs, the white title with its 3D shadow,
	a dark studded body). The window clips (the elevator's doors stay inside);
	its red X (Pop.close) sits in a holder on `root` (a controller hangs the
	gamepad's B glyph on the holder). fitWindow sizes it for a band height.
]]
function ElevatorView.popWindow(root: Frame, title: string, paint: string, band: number): Chrome
	local window = Pop.window(root, title, Vector2.new(800, 500), band, paint)
	if window.Icon then
		window.Icon:Destroy() -- (the round look's band icon: this window brings its own, fitWindow)
	end
	local panel = window.Root
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.ClipsDescendants = true
	local holder: Frame = UIKit.new("Frame", {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, root)
	local close = window.Close
	close.AnchorPoint = Vector2.zero
	close.Position = UDim2.new()
	close.Size = UDim2.fromScale(1, 1)
	close.ZIndex = 2 -- (under a controller's glyph on the holder)
	close.Parent = holder
	local label = close:FindFirstChild("Label") :: TextLabel
	local look: ButtonRefs = {
		Holder = holder,
		Edge = close:FindFirstChild("Border") :: UIStroke,
		Button = close,
		Gradient = close:FindFirstChild("Paint") :: UIGradient,
		Row = close,
		Icons = {},
		Label = label,
		LabelStroke = label:FindFirstChild("Edge") :: UIStroke,
		Style = "Close",
	}
	return {
		Panel = panel,
		Header = window.Header,
		Body = window.Body,
		Title = window.Title,
		TitleShadow = window.Header:FindFirstChild("TitleShadow") :: TextLabel,
		CloseLook = look,
	}
end

-- Sizes a popWindow for a `band` tall header: the icon and the title in the band, the X on its right.
function ElevatorView.fitWindow(chrome: Chrome, icon: GuiObject, band: number, titleSize: number, iconSize: number, closeSize: number)
	chrome.Header.Size = UDim2.new(1, -8, 0, band - 8)
	chrome.Body.Position = UDim2.fromOffset(4, band)
	chrome.Body.Size = UDim2.new(1, -8, 1, -(band + 4))
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Size = UDim2.fromOffset(iconSize, iconSize)
	local left = 12 + iconSize + 12
	local title, shadow = chrome.Title, chrome.TitleShadow
	title.TextSize = titleSize
	title.Position = UDim2.new(0, left, 0.5, 0)
	title.Size = UDim2.new(1, -(left + closeSize + 24), 1, -4)
	local edge = title:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = Pop.edgeFor(titleSize)
	end
	shadow.TextSize = titleSize
	shadow.Position = title.Position + UDim2.fromOffset(0, 4)
	shadow.Size = title.Size
	local close = chrome.CloseLook
	close.Holder.Size = UDim2.fromOffset(closeSize, closeSize)
	close.Holder.Position = UDim2.new(1, -10, 0, math.floor(band / 2))
	close.Label.TextSize = math.floor(closeSize * 0.66)
	close.LabelStroke.Thickness = Pop.edgeFor(close.Label.TextSize)
end

-- The dark footer pill hanging on the panel's bottom edge; returns it and its row (icons + the hint).
function ElevatorView.popFooter(root: Frame): (Frame, Frame)
	local footer: Frame = UIKit.new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(380, 36),
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, footer)
	Pop.border(footer, 3)
	local row: Frame = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, footer)
	UIKit.list(row, Enum.FillDirection.Horizontal, 8, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	return footer, row
end

--[[
	A Pop button in a holder: Pop.price's face (green, studs, the light rim;
	its Row holds the robux "Mark" and the word "Amount") with the drawn icons
	`iconNames` (from `makers`, in white) in front of the word. paintButton
	repaints it per state.
]]
function ElevatorView.popButton(
	parent: Instance,
	name: string,
	iconNames: { string },
	makers: { [string]: (Instance, Color3) -> Frame }
): ButtonRefs
	local holder: Frame = UIKit.new("Frame", {
		Name = name .. "Holder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(160, 56),
	}, parent)
	local button = Pop.price(holder, nil, Vector2.new(160, 56), {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, "")
	local row = button:FindFirstChild("Row") :: Frame
	local list = row:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, 8)
	end
	local made: { [string]: Frame } = {}
	for _, kind in iconNames do
		local icon = makers[kind](row, WHITE)
		icon.LayoutOrder = 0
		icon.Visible = false
		made[kind] = icon
	end
	local label = row:FindFirstChild("Amount") :: TextLabel
	return {
		Holder = holder,
		Edge = button:FindFirstChild("Border") :: UIStroke,
		Button = button,
		Gradient = button:FindFirstChild("Paint") :: UIGradient,
		Row = row,
		Icons = made,
		Label = label,
		LabelStroke = label:FindFirstChild("Edge") :: UIStroke,
		Style = "",
	}
end

-- Paints a popButton: `paint`, the word (`heavy`: the LuckiestGuy font) and the drawn icon `icon` (nil: none).
function ElevatorView.paintButton(look: ButtonRefs, paint: Pop.Paint, text: string, textSize: number, icon: string?, heavy: boolean?)
	Pop.repaint(look.Button, paint)
	look.Label.Text = text
	look.Label.TextSize = textSize
	look.Label.FontFace = if heavy then PopTheme.Heavy else PopTheme.Font
	look.Label.TextColor3 = TEXT
	look.LabelStroke.Thickness = Pop.edgeFor(textSize)
	look.Label.Size = UDim2.fromOffset(math.ceil(ElevatorView.measure(text, textSize, heavy)) + 6, textSize + 8)
	local iconSize = math.floor(textSize * 0.95)
	for kind, frame in look.Icons do
		local shown = kind == icon
		frame.Visible = shown
		if shown then
			frame.Size = UDim2.fromOffset(iconSize, iconSize)
		end
	end
end

---------------------------------------------------------------- the ride fade

-- The black screen of a ride (no UIScale: the black layer always covers the whole screen).
function ElevatorView.buildFade(): Fade
	local gui = UIKit.new("ScreenGui", {
		Name = "TerraForgeElevatorFade",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 60,
		Enabled = false,
	})
	local black = UIKit.new("Frame", {
		Name = "Black",
		BackgroundColor3 = Color3.fromRGB(8, 10, 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = true,
	}, gui)
	local title = UIKit.label(black, "", 48, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.12, 0),
		FontFace = Theme.TitleFont,
		TextColor3 = TEXT,
		TextScaled = true,
		TextTransparency = 1,
	})
	local titleStroke = title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = rgb(20, 50, 150)
	end
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 72, MinTextSize = 24 }, title)
	local name = UIKit.label(black, "", 28, {
		Name = "FloorName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(0.9, 0, 0.07, 0),
		TextColor3 = NEON_BRIGHT,
		TextScaled = true,
		TextTransparency = 1,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 40, MinTextSize = 16 }, name)
	return { Gui = gui, Black = black, Title = title, Name = name }
end

function ElevatorView.setFadeText(fade: Fade, floorIndex: number, name: string)
	fade.Title.Text = `FLOOR {floorIndex}`
	fade.Name.Text = name
end

return ElevatorView
