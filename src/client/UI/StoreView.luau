--[[
	The Robux Shop window (owner 2026-10-20 evening: "change the shop
	completely, like this", his egg-game photos): a bright green "Shop"
	header with a red X, a dark body that scrolls down through sections
	("-- MONEY --", "-- PASSES --"...), bright painted cards with light rays
	behind a big picture and a green Robux price button, and a column of
	section tabs right of the window (a tap scrolls to the section).
	Config/StoreConfig places the cards; the Pop kit (UI/Pop.luau) draws them.

	  build()              the window (hidden); Refs.Cards[id] per StoreConfig card
	  layout(refs, w, h, compact?) fits the window into w x h design units
	  setCard(refs, id, key, state) which product a card shows now and its
	                       state ("Buy" | "Owned" | "Pending" | "Locked" | "Hidden");
	                       hidden cards close their row up (relayout)
	  setCoins(refs, income) the money cards' amounts at this podium income
	  showDetail(refs, detail?) the odds panel shown before a paid random
	                       buy (nil hides it)
	  setStatus(refs, text?) a line at the bottom of the window
	  sectionTop(refs, id) where a section starts in the scrolled list (tabs)

	Pictures are live 3D models where the game has them (PictureModels:
	cash, capsules, golems, the train, hoverboards; the STAR blasters are
	filled by StoreController with RebirthView.fillPicture), else the icon
	sheets' pictures (IconAssets; nothing until uploaded, never an emoji).

	Pure builder + layout, no services: the Lune previews build it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopTheme = require(Shared.Config.PopTheme)
local StoreConfig = require(Shared.Config.StoreConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local IconAssets = require(Shared.Config.IconAssets)
local Format = require(Shared.Util.Format)
local PictureModels = require(Shared.Builders.PictureModels)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local StoreView = {}

export type CardRefs = {
	Spec: StoreConfig.CardSpec,
	Button: TextButton,
	Title: TextLabel?,
	Amount: TextLabel?, -- Coins: the coins it gives
	Description: TextLabel?,
	Price: TextButton,
	PriceAmount: TextLabel,
	Owned: Frame,
	Shade: Frame,
	Key: string, -- the product it shows now
	State: string,
}

export type Detail = {
	Title: string,
	Lines: { string },
	Robux: number,
	Paint: string?,
}

export type Refs = {
	Gui: ScreenGui,
	Group: Frame, -- the window and the tabs beside it
	Window: Pop.Window,
	Scroller: ScrollingFrame,
	Sections: { [string]: Frame },
	Tabs: { [string]: TextButton },
	Cards: { [string]: CardRefs },
	Order: { string }, -- card ids top to bottom, left to right (gamepad order)
	Status: TextLabel,
	Detail: Frame,
	DetailTitle: TextLabel,
	DetailLines: TextLabel,
	DetailBuy: TextButton,
	DetailBack: TextButton,
	Tops: { [string]: number }, -- section id -> its top in the scrolled list
}

StoreView.Header = 76
StoreView.Width = 960 -- the window
StoreView.CardsWidth = 918 -- the cards' row width inside the scroller
StoreView.Gap = 12
StoreView.HeadingHeight = 56
StoreView.MaxHeight = 640
StoreView.TabGap = 12
StoreView.TabSize = 84

-- The window's size and fit scale for a w x h design-unit screen: the
-- window keeps its width (the tabs sit beside it) and gets as tall as the
-- screen allows; a screen too narrow or too short shrinks it all (fit < 1).
function StoreView.windowSize(w: number, h: number, tab: number?): (Vector2, number)
	local group = StoreView.Width + StoreView.TabGap + (tab or StoreView.TabSize)
	local fit = math.min(1, (w - 24) / group, (h - 16) / 520)
	local height = math.min(StoreView.MaxHeight, (h - 24) / fit)
	return Vector2.new(StoreView.Width, math.floor(height)), fit
end

local function productOf(spec: StoreConfig.CardSpec): MonetizationConfig.Product
	return MonetizationConfig.Products[spec.Keys[1]]
end

-- A card's paint: a PopTheme paint, the rainbow, or a STAR blaster's light.
local function paintOf(spec: StoreConfig.CardSpec): Pop.Paint
	local glow = spec.GlowColor
	if glow then
		return { Top = glow:Lerp(Color3.new(1, 1, 1), 0.35), Bottom = glow:Lerp(Color3.new(0, 0, 0), 0.45), Edge = PopTheme.Outline }
	end
	return Pop.paint(if spec.Paint == "Rainbow" then "Purple" else spec.Paint)
end

-- A card's picture: the live model (PictureModels) or the icon.
local function picture(parent: Instance, spec: StoreConfig.CardSpec, size: number, props: { [string]: any }): GuiObject
	local name = spec.Model
	if name and string.sub(name, 1, 5) == "star_" then
		return Pop.model(parent, spec.Icon, size, nil, props) -- (StoreController fills the gun)
	end
	if name then
		local model, from = PictureModels.build(name)
		if model then
			return Pop.model(parent, spec.Icon, size, model, props, from)
		end
	end
	local icon = UIKit.new("ImageLabel", {
		Name = "Picture",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 4,
	}, parent)
	IconAssets.apply(icon, spec.Icon)
	icon:SetAttribute("Icon", spec.Icon)
	for key, value in props do
		(icon :: any)[key] = value
	end
	return icon
end

-- The OWNED tag that replaces a pass's price once it is bought (where the price was).
local function ownedTag(parent: Instance, height: number, right: boolean): Frame
	local tag = Pop.tag(parent, "OWNED", PopTheme.Gray, Vector2.new(170, height), {
		Name = "Owned",
		AnchorPoint = if right then Vector2.new(1, 1) else Vector2.new(0.5, 1),
		Position = if right then UDim2.new(1, -12, 1, -12) else UDim2.new(0.5, 0, 1, -10),
		Visible = false,
	})
	return tag
end

local function buildCard(parent: Instance, spec: StoreConfig.CardSpec, w: number, h: number): CardRefs
	local product = productOf(spec)
	local paint = paintOf(spec)
	local button = Pop.card(parent, paint, {
		Name = spec.Id,
		Size = UDim2.fromOffset(w, h),
	}, if spec.Look == "Item" then UDim2.new(0, math.floor(h * 0.42), 0.46, 0) else nil)
	if spec.Paint == "Rainbow" then
		Pop.rainbow(button)
	end
	local priceH = if spec.Look == "Bundle" then 62 else 50
	local priceW = if spec.Look == "Bundle" then 300 elseif spec.Look == "Item" then math.floor(w * 0.5) else w - 24
	local price = Pop.price(button, product.Robux, Vector2.new(priceW, priceH), {
		AnchorPoint = if spec.Look == "Bundle" or spec.Look == "Item" then Vector2.new(1, 1) else Vector2.new(0.5, 1),
		Position = if spec.Look == "Bundle" or spec.Look == "Item" then UDim2.new(1, -12, 1, -12) else UDim2.new(0.5, 0, 1, -10),
		Selectable = false, -- (one gamepad stop per card: the card buys)
		ZIndex = 6,
	})
	local priceAmount = (price:FindFirstChild("Row") :: Frame):FindFirstChild("Amount") :: TextLabel
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 9,
	}, button)
	UIKit.corner(shade, PopTheme.Corner)
	local refs: CardRefs = {
		Spec = spec,
		Button = button,
		Title = nil,
		Amount = nil,
		Description = nil,
		Price = price,
		PriceAmount = priceAmount,
		Owned = ownedTag(button, priceH - 6, spec.Look == "Bundle" or spec.Look == "Item"),
		Shade = shade,
		Key = spec.Keys[1],
		State = "Buy",
	}
	local title = spec.Title or product.Name
	local below = priceH + 14 -- the price's room at the bottom
	if spec.Look == "Bundle" then
		refs.Title = Pop.title(button, title, 46, "Gold", {
			AnchorPoint = Vector2.new(0, 0),
			FontFace = PopTheme.Heavy,
			Position = UDim2.fromOffset(22, 14),
			Size = UDim2.new(0.62, 0, 0, 52),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		})
		Pop.text(button, "Includes:", 24, {
			Name = "Includes",
			Position = UDim2.fromOffset(24, 72),
			Size = UDim2.new(0.5, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		})
		local lines: { string } = spec.Lines or {}
		for i, line in lines do
			Pop.text(button, "+ " .. line, 22, {
				Name = "Line" .. i,
				Position = UDim2.fromOffset(34, 72 + i * 32),
				Size = UDim2.new(0.5, 0, 0, 30),
				TextColor3 = Color3.fromRGB(255, 248, 200),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
			})
		end
		picture(button, spec, 210, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.76, 0, 0.4, 0),
			ZIndex = 5,
		})
	elseif spec.Look == "Coins" then
		local size = math.floor(math.min(w * 0.62, (h - below) * 0.86))
		picture(button, spec, size, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, math.floor((h - below) * 0.44) + 4),
			ZIndex = 5,
		})
		refs.Amount = Pop.text(button, "$0", 36, {
			Name = "Amount",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(below - 2)),
			Size = UDim2.new(1, -12, 0, 42),
			ZIndex = 7,
		})
	elseif spec.Look == "Capsule" then
		refs.Title = Pop.text(button, title, 20, {
			Name = "Title",
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.new(1, -12, 0, 26),
			TextScaled = true,
			ZIndex = 7,
		})
		local size = math.floor(math.min(w * 0.66, (h - below - 34) * 0.92))
		picture(button, spec, size, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 34 + math.floor((h - below - 34) / 2)),
			ZIndex = 5,
		})
		Pop.title(button, spec.Big or "", 44, "White", {
			Name = "Big",
			AnchorPoint = Vector2.new(1, 1),
			FontFace = PopTheme.Heavy,
			Position = UDim2.new(1, -10, 1, -(below - 4)),
			Size = UDim2.fromOffset(110, 48),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 7,
		})
	elseif spec.Look == "Boost" or spec.Look == "Star" then
		refs.Title = Pop.text(button, title, 24, {
			Name = "Title",
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.new(1, -12, 0, 30),
			TextScaled = true,
			ZIndex = 7,
		})
		local size = math.floor(math.min(w * 0.6, h - below - 100))
		picture(button, spec, size, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(math.floor(w / 2), 40),
			ZIndex = 5,
		})
		Pop.title(button, spec.Big or "", 30, "Gold", {
			Name = "Big",
			AnchorPoint = Vector2.new(0.5, 1),
			FontFace = PopTheme.Heavy,
			Position = UDim2.new(0.5, 0, 1, -(below + 24)),
			Size = UDim2.new(1, -10, 0, 36),
			ZIndex = 7,
		})
		local note = Pop.text(button, spec.Note or "", 17, {
			Name = "Note",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(below - 2)),
			Size = UDim2.new(1, -12, 0, 24),
			TextScaled = true,
			ZIndex = 7,
		})
		if spec.Look == "Star" then
			refs.Description = note
		end
	else -- "Item": the picture left, the title and text right, the price bottom right
		local size = math.floor(h - 56)
		picture(button, spec, size, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.46, 0),
			ZIndex = 5,
		})
		local left = size + 18
		refs.Title = Pop.text(button, title, 28, {
			Name = "Title",
			Position = UDim2.fromOffset(left, 10),
			Size = UDim2.new(1, -(left + 10), 0, 34),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		})
		refs.Description = Pop.text(button, spec.Short or product.Description, 17, {
			Name = "Description",
			Position = UDim2.fromOffset(left, 48),
			Size = UDim2.new(1, -(left + 10), 1, -(48 + below)),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 7,
		})
	end
	if spec.Ribbon then
		Pop.ribbon(button, spec.Ribbon, 136)
	end
	return refs
end

-- The heights of a section's rows (design units).
local function rowHeight(section: StoreConfig.Section, row: number): number
	return if row == 1 and section.BigRow then section.BigRow else section.RowHeight
end

--[[
	Places every section, row and card from the top of the scrolled list:
	hidden cards close their row up, empty rows and sections fold away (and
	their tabs hide). Returns the list's height.
]]
function StoreView.relayout(refs: Refs): number
	local gap = StoreView.Gap
	local y = 6
	for _, section in StoreConfig.Sections do
		local frame = refs.Sections[section.Id]
		local rows = StoreConfig.rows(section.Id)
		local inner = StoreView.HeadingHeight
		local any = false
		for r, row in rows do
			local shown: { CardRefs } = {}
			local spans = 0
			for _, spec in row do
				local card = refs.Cards[spec.Id]
				if card and card.State ~= "Hidden" then
					table.insert(shown, card)
					spans += spec.Span or 1
				end
			end
			if #shown > 0 then
				any = true
				local h = rowHeight(section, r)
				local unit = (StoreView.CardsWidth - (#shown - 1) * gap) / spans
				local x = 0
				for _, card in shown do
					local w = math.floor(unit * (card.Spec.Span or 1))
					card.Button.Position = UDim2.fromOffset(x, inner)
					card.Button.Size = UDim2.fromOffset(w, h)
					x += w + gap
				end
				inner += h + gap
			end
		end
		frame.Visible = any
		local tab = refs.Tabs[section.Id]
		if tab and tab.Parent then
			(tab.Parent :: GuiObject).Visible = any
		end
		if any then
			frame.Position = UDim2.fromOffset(0, y)
			frame.Size = UDim2.fromOffset(StoreView.CardsWidth, inner)
			refs.Tops[section.Id] = y
			y += inner + 6
		end
	end
	local total = y + 8
	refs.Scroller.CanvasSize = UDim2.fromOffset(StoreView.CardsWidth, total)
	return total
end

function StoreView.build(): Refs
	local gui = UIKit.screen("TerraForgeStore", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	-- a dim backdrop over the world
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	-- the window sits in a full-screen holder whose UIScale fits it to small screens
	local holder = UIKit.new("Frame", {
		Name = "Fit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	UIKit.new("UIScale", { Name = "FitScale", Scale = 1 }, holder)
	local size = StoreView.windowSize(1280, 720)
	local group = UIKit.new("Frame", {
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X + StoreView.TabGap + StoreView.TabSize, size.Y),
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, holder)
	local window = Pop.window(group, StoreConfig.Title, size, StoreView.Header, "Green")
	window.Root.AnchorPoint = Vector2.new(0, 0)
	window.Root.Position = UDim2.fromOffset(0, 0)

	local scroller = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -14, 1, -12),
		CanvasSize = UDim2.fromOffset(StoreView.CardsWidth, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 2,
	}, window.Body)

	local sections: { [string]: Frame } = {}
	local cards: { [string]: CardRefs } = {}
	local order: { string } = {}
	for _, section in StoreConfig.Sections do
		local frame = UIKit.new("Frame", {
			Name = section.Id,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(StoreView.CardsWidth, 100),
			ZIndex = 2,
		}, scroller)
		Pop.heading(frame, section.Title, section.Colors, 40)
		sections[section.Id] = frame
		for r, row in StoreConfig.rows(section.Id) do
			local h = rowHeight(section, r)
			local unit = (StoreView.CardsWidth - (#row - 1) * StoreView.Gap) / #row
			for _, spec in row do
				cards[spec.Id] = buildCard(frame, spec, math.floor(unit * (spec.Span or 1)), h)
				table.insert(order, spec.Id)
			end
		end
	end

	-- the section tabs right of the window
	local tabs: { [string]: TextButton } = {}
	local tabColumn = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(size.X + StoreView.TabGap, StoreView.Header),
		Size = UDim2.new(0, StoreView.TabSize, 1, -StoreView.Header),
	}, group)
	UIKit.list(tabColumn, Enum.FillDirection.Vertical, 10)
	for i, section in StoreConfig.Sections do
		local face = Pop.tile(tabColumn, {
			Name = section.Id,
			Label = section.Tab,
			Icon = section.TabIcon,
			Paint = section.TabPaint,
			Size = StoreView.TabSize,
			LayoutOrder = i,
		})
		tabs[section.Id] = face
	end

	local status = Pop.text(window.Body, "", 20, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.25,
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(560, 34),
		Visible = false,
		ZIndex = 12,
	})
	UIKit.corner(status, 8)

	-- the odds panel (paid random items show their odds before the buy); a
	-- dim blocker under it keeps taps and the D-pad off the cards behind
	local blocker = UIKit.new("TextButton", {
		Name = "Blocker",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Selectable = false,
		Visible = false,
		ZIndex = 19,
	}, window.Body)
	UIKit.corner(blocker, 4)
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 440),
		Visible = false,
		ZIndex = 20,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, window.Body)
	UIKit.corner(detail, 8)
	Pop.border(detail, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, detail)
	local band = UIKit.new("Frame", {
		Name = "Band",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 54),
		ZIndex = 21,
	}, detail)
	Pop.face(band, "Purple", 6)
	local detailTitle = Pop.text(band, "", 30, {
		Name = "Title",
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		ZIndex = 22,
	})
	-- the odds can run long (Triple Lucky: every capsule): they scroll
	local linesScroll = UIKit.new("ScrollingFrame", {
		Name = "LinesScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, 70),
		Size = UDim2.new(1, -34, 1, -150),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
		ZIndex = 21,
	}, detail)
	local detailLines = Pop.text(linesScroll, "", 18, {
		Name = "Lines",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -12, 0, 0),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 21,
	})
	local back = Pop.button(detail, "BACK", PopTheme.Gray, Vector2.new(200, 56), {
		Name = "Back",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.28, 0, 1, -14),
		ZIndex = 22,
	})
	local buy = Pop.price(detail, 0, Vector2.new(220, 56), {
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.72, 0, 1, -14),
		ZIndex = 22,
	})

	local refs: Refs = {
		Gui = gui,
		Group = group,
		Window = window,
		Scroller = scroller,
		Sections = sections,
		Tabs = tabs,
		Cards = cards,
		Order = order,
		Status = status,
		Detail = detail,
		DetailTitle = detailTitle,
		DetailLines = detailLines,
		DetailBuy = buy,
		DetailBack = back,
		Tops = {},
	}
	StoreView.relayout(refs)
	StoreView.layout(refs, 1280, 720)
	return refs
end

-- Sizes for the big screens and for phones / TVs (compact: TechShopView.compactFor):
-- on a phone the HUD scale is small, so the X, the tabs, the odds and their buttons grow.
StoreView.Metrics = {
	Normal = { Close = 62, Tab = 84, Lines = 18, Status = 20, Button = Vector2.new(200, 56), Detail = Vector2.new(600, 440) },
	Compact = { Close = 76, Tab = 92, Lines = 24, Status = 24, Button = Vector2.new(240, 72), Detail = Vector2.new(780, 480) },
}

-- Fits the window into a w x h design-unit screen (compact: the phone sizes).
function StoreView.layout(refs: Refs, w: number, h: number, compact: boolean?)
	local m = if compact then StoreView.Metrics.Compact else StoreView.Metrics.Normal
	local size, fit = StoreView.windowSize(w, h, m.Tab)
	refs.Window.Root.Size = UDim2.fromOffset(size.X, size.Y)
	refs.Group.Size = UDim2.fromOffset(size.X + StoreView.TabGap + m.Tab, size.Y)
	local holder = refs.Group.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
	-- (compact: the touch targets and texts keep their size through the fit shrink)
	local k = if compact then 1 / math.max(fit, 0.5) else 1
	local close = math.floor(m.Close * k)
	refs.Window.Close.Size = UDim2.fromOffset(close, close)
	local closeLabel = refs.Window.Close:FindFirstChild("Label") :: TextLabel?
	if closeLabel then
		closeLabel.TextSize = math.floor(close * 0.66)
	end
	-- the tabs: as big as they can be in the window's height
	local tabColumn = refs.Group:FindFirstChild("Tabs") :: Frame?
	if tabColumn then
		local count = 0
		for _, tab in refs.Tabs do
			if tab.Parent and (tab.Parent :: GuiObject).Visible then
				count += 1
			end
		end
		local room = size.Y - StoreView.Header - 8
		local tab = math.min(m.Tab, math.floor((room - 10 * math.max(0, count - 1)) / math.max(count, 1)))
		tabColumn.Position = UDim2.fromOffset(size.X + StoreView.TabGap, StoreView.Header)
		tabColumn.Size = UDim2.new(0, m.Tab, 1, -StoreView.Header)
		for _, face in refs.Tabs do
			local frame = face.Parent :: Frame
			frame.Size = UDim2.fromOffset(tab, tab)
		end
	end
	refs.Detail.Size = UDim2.fromOffset(math.min(m.Detail.X * k, size.X - 40), math.min(m.Detail.Y * k, size.Y - StoreView.Header - 30))
	refs.DetailLines.TextSize = math.floor(m.Lines * k)
	refs.Status.TextSize = math.floor(m.Status * k)
	refs.Status.Size = UDim2.fromOffset(math.min(760, size.X - 60), math.floor(m.Status * k) + 14)
	for _, button in { refs.DetailBuy, refs.DetailBack } do
		button.Size = UDim2.fromOffset(math.floor(m.Button.X * k), math.floor(m.Button.Y * k))
	end
end

-- Which product a card shows and how: "Buy" (price), "Owned" (a pass the
-- player has: the OWNED tag), "Pending" (a purchase on its way: shaded),
-- "Locked" (not yet: a STAR blaster before its rebirth; shaded, no price),
-- "Hidden" (nothing to sell: the blaster at the top level; its row closes up).
function StoreView.setCard(refs: Refs, id: string, key: string, state: string)
	local card = refs.Cards[id]
	local product = MonetizationConfig.Products[key]
	if not card or not product then
		return
	end
	local wasHidden = card.State == "Hidden"
	card.Key = key
	card.State = state
	Pop.setPrice(card.Price, product.Robux)
	if card.Description and card.Spec.Look == "Item" then
		card.Description.Text = card.Spec.Short or product.Description
	end
	card.Button.Visible = state ~= "Hidden"
	card.Price.Visible = state == "Buy" or state == "Pending"
	card.Owned.Visible = state == "Owned"
	card.Button.Active = state == "Buy"
	card.Shade.Visible = state == "Pending" or state == "Locked"
	if wasHidden ~= (state == "Hidden") then
		StoreView.relayout(refs)
	end
end

-- A card's note ("Opens at rebirth 3", the blaster's rebirth line).
function StoreView.setNote(refs: Refs, id: string, text: string)
	local card = refs.Cards[id]
	if not card then
		return
	end
	if card.Description and card.Spec.Look ~= "Item" then
		card.Description.Text = text
		return
	end
	local note = card.Button:FindFirstChild("Note")
	if note and note:IsA("TextLabel") then
		note.Text = text
	end
end

-- A card's big line ("LV 5" on the blaster card).
function StoreView.setBig(refs: Refs, id: string, text: string)
	local card = refs.Cards[id]
	local big = if card then card.Button:FindFirstChild("Big") else nil
	if big and big:IsA("TextLabel") then
		big.Text = text
	end
end

-- The money cards' amounts at a podium income of `income` coins per second.
function StoreView.setCoins(refs: Refs, income: number)
	for _, card in refs.Cards do
		local amount = card.Amount
		if amount then
			local coins = MonetizationConfig.coinPackAmount(card.Key, income) or 0
			amount.Text = "$" .. Format.big(coins)
		end
	end
end

-- Where section `id` starts in the scrolled list (design units; 0 unknown).
function StoreView.sectionTop(refs: Refs, id: string): number
	return refs.Tops[id] or 0
end

-- The odds panel before a paid random buy (nil hides it).
function StoreView.showDetail(refs: Refs, detail: Detail?)
	refs.Detail.Visible = detail ~= nil
	local blocker = refs.Window.Body:FindFirstChild("Blocker")
	if blocker and blocker:IsA("GuiObject") then
		blocker.Visible = detail ~= nil
	end
	if not detail then
		return
	end
	refs.DetailTitle.Text = detail.Title
	local band = refs.Detail:FindFirstChild("Band")
	if band and band:IsA("GuiObject") then
		local paint = detail.Paint or "Purple"
		Pop.repaint(band, if paint == "Rainbow" then "Purple" else paint)
	end
	refs.DetailLines.Text = table.concat(detail.Lines, "\n")
	-- (AutomaticSize grows it in the game; the height also from the lines for the previews)
	refs.DetailLines.Size = UDim2.new(1, -12, 0, #detail.Lines * math.ceil(refs.DetailLines.TextSize * 1.3) + 8)
	Pop.setPrice(refs.DetailBuy, detail.Robux)
end

-- The line at the bottom of the window (nil / "" hides it).
function StoreView.setStatus(refs: Refs, text: string?)
	refs.Status.Text = text or ""
	refs.Status.Visible = text ~= nil and text ~= ""
end

return StoreView
