--[[
	ENCHANTS and LUCK BOOSTS in the light "Bubble" look (pure builders,
	preview first; steps 6-7's EnchantView / BoostView move onto them).

	  enchants  your blaster's slots on top (2 of 4 open, the rest LOCKED with
	            the blaster level that opens them), every enchant as a row by
	            rarity (rune, name, effect, price, level, NEW), the selected
	            enchant: rarity, level, now / next, all tiers, BUY (coins),
	            SHARDS, EQUIP
	  boosts    TRIPLE LUCKY / HEXA LUCKY tabs, the boost with its time left and
	            the coin offers, and the exact odds without / with the boost
	            (Roblox rule: new odds before buying)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local EnchantBubble = {}

local function headerChip(window: Bubble.Window, icon: string, text: string, rightOffset: number, width: number)
	local chip = Bubble.chip(window.Header, text, Vector2.new(width, 44), 24, nil, {
		Name = icon,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -rightOffset, 0.5, 0),
		ZIndex = 5,
	})
	local label = chip:FindFirstChild("Text") :: TextLabel
	label.Position = UDim2.fromOffset(30, 0)
	label.Size = UDim2.new(1, -36, 1, 0)
	Bubble.icon(chip, icon, 52, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = 6 })
end

local function plainLabel(face: GuiObject)
	local label = face:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextColor3 = Theme.InkSoft
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
			stroke.Transparency = 1
		end
	end
end

local function stretch(holder: Frame, face: GuiObject, height: number)
	holder.Size = UDim2.new(1, 0, 0, height + Theme.Lip)
	for _, part in { "Shadow", "Lip" } do
		local piece = holder:FindFirstChild(part) :: Frame
		piece.Size = UDim2.new(1, 0, 0, height)
	end
	face.Size = UDim2.new(1, 0, 0, height)
end

export type Slot = { Id: string, Name: string?, Effect: string?, Locked: string? }
export type Enchant = { Id: string, Name: string, Rarity: string, Color: Color3, Effect: string, Price: string, Level: string?, New: boolean? }
export type EnchantData = {
	Header: string,
	Slots: { Slot },
	Enchants: { Enchant },
	Selected: string,
	Description: string,
	Now: string,
	Next: string,
	Tiers: { string },
	Buy: string,
	Shards: string,
	Coins: string,
	ShardCount: string,
}
export type EnchantRefs = { Window: Bubble.Window, Rows: { [string]: TextButton }, Buy: TextButton, ShardsBuy: TextButton, Equip: TextButton }

function EnchantBubble.enchants(parent: Instance, uiScale: number, data: EnchantData): EnchantRefs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "Enchants",
		Title = "ENCHANTS",
		Icon = "enchant",
		Role = "Enchant",
		Size = size,
		HeaderHeight = header,
	})
	headerChip(window, "coin", data.Coins, 54, 180)
	headerChip(window, "shard", data.ShardCount, 54 + 180 + 40, 120)
	local body = window.Body
	local leftW = if compact then 640 else 480
	local textSize = if compact then 19 else 15

	-- slots
	Bubble.ink(body, data.Header, textSize, {
		Name = "Blaster",
		Size = UDim2.new(0, leftW, 0, 22),
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local slotH = if compact then 72 else 56
	local slots = UIKit.new("Frame", { Name = "Slots", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(0, leftW, 0, slotH + Theme.Lip) }, body)
	UIKit.list(slots, Enum.FillDirection.Horizontal, 8)
	local slotW = math.floor((leftW - 24) / 4)
	for i, s in data.Slots do
		local holder, face = Bubble.body(slots, if s.Locked then Bubble.role("Plain") else Bubble.role("Enchant"), Vector2.new(slotW, slotH), {
			Name = s.Id,
			Corner = 14,
			Clickable = true,
		})
		holder.LayoutOrder = i
		if s.Locked then
			Bubble.icon(face, "lock", slotH - 8, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) })
			Bubble.ink(face, s.Locked, textSize - 2, {
				Name = "Locked",
				Position = UDim2.fromOffset(slotH - 10, 0),
				Size = UDim2.new(1, -slotH + 6, 1, 0),
				TextColor3 = Theme.InkSoft,
				TextWrapped = true,
				ZIndex = 4,
			})
		else
			Bubble.icon(face, "enchant_" .. s.Id, slotH, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -4, 0.5, -2) })
			Bubble.text(face, s.Name or "", textSize, {
				Name = "SlotName",
				Position = UDim2.fromOffset(slotH - 8, 4),
				Size = UDim2.new(1, -slotH + 4, 0.5, -2),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 4,
			})
			Bubble.text(face, s.Effect or "", textSize - 3, {
				Name = "SlotEffect",
				Position = UDim2.new(0, slotH - 8, 0.5, 0),
				Size = UDim2.new(1, -slotH + 4, 0.5, -6),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 4,
			})
		end
	end

	-- the enchant list
	local top = 28 + slotH + Theme.Lip + 12
	local listPanel = Bubble.inset(body, "List", UDim2.fromOffset(0, top), UDim2.new(0, leftW, 1, -top))
	local scroll = UIKit.new("ScrollingFrame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.InkSoft,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		ZIndex = 3,
	}, listPanel)
	UIKit.list(scroll, Enum.FillDirection.Vertical, 6)
	local rowH = if compact then 72 else 54
	local rows = {}
	for i, e in data.Enchants do
		local holder, face = Bubble.body(scroll, Bubble.role("Plain"), Vector2.new(0, rowH), { Name = e.Id, Corner = 14, Clickable = true, Gloss = false })
		holder.LayoutOrder = i
		stretch(holder, face, rowH)
		if e.Id == data.Selected then
			Bubble.select(face, true)
		end
		Bubble.icon(face, "enchant_" .. e.Id, rowH, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, -1) })
		Bubble.ink(face, string.upper(e.Name), textSize + 2, {
			Name = "EnchantName",
			Position = UDim2.fromOffset(rowH + 4, if compact then 8 else 4),
			Size = UDim2.new(0.6, -rowH, 0, textSize + 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Bubble.ink(face, e.Effect, textSize - 2, {
			Name = "Effect",
			Position = UDim2.fromOffset(rowH + 4, if compact then 36 else 27),
			Size = UDim2.new(0.6, -rowH, 0, textSize + 2),
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Bubble.chip(face, string.upper(e.Rarity), Vector2.new(if compact then 130 else 100, 24), if compact then 15 else 13, Bubble.roleFrom(e.Color), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 6),
		})
		Bubble.ink(face, (if e.Level then e.Level .. "  ·  " else "") .. e.Price, textSize - 1, {
			Name = "Price",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -4),
			Size = UDim2.fromOffset(180, textSize + 4),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 4,
		})
		if e.New then
			Bubble.chip(face, "NEW", Vector2.new(52, 22), 14, "Vault", {
				Name = "New",
				Position = UDim2.fromOffset(rowH + 4 + Bubble.textWidth(e.Name, textSize + 2) + 6, if compact then 10 else 5),
			})
		end
		rows[e.Id] = face :: TextButton
	end

	-- the selected enchant
	local selected: Enchant = data.Enchants[1]
	for _, e in data.Enchants do
		if e.Id == data.Selected then
			selected = e
		end
	end
	local right = Bubble.inset(body, "Detail", UDim2.fromOffset(leftW + 16, 0), UDim2.new(1, -leftW - 16, 1, 0))
	Bubble.glowIcon(right, "enchant_" .. selected.Id, selected.Color, if compact then 90 else 96, { Position = UDim2.fromOffset(12, 12) })
	local x = if compact then 112 else 120
	Bubble.ink(right, string.upper(selected.Name), if compact then 30 else 30, {
		Name = "EnchantName",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(x, 18),
		Size = UDim2.new(1, -x - 12, 0, 34),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local chips = UIKit.new("Frame", { Name = "Chips", BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 58), Size = UDim2.new(1, -x - 12, 0, 28), ZIndex = 4 }, right)
	UIKit.list(chips, Enum.FillDirection.Horizontal, 8)
	Bubble.chip(chips, string.upper(selected.Rarity), Vector2.new(100, 28), 16, Bubble.roleFrom(selected.Color), { LayoutOrder = 1 })
	if selected.Level then
		Bubble.chip(chips, selected.Level, Vector2.new(70, 28), 16, "Build", { LayoutOrder = 2 })
	end
	local y = if compact then 112 else 122
	Bubble.ink(right, data.Description, textSize, {
		Name = "Description",
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, textSize + 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	y += textSize + 10
	Bubble.text(right, "NOW: " .. data.Now, textSize, {
		Name = "Now",
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, textSize + 4),
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	y += textSize + 8
	Bubble.ink(right, "NEXT: " .. data.Next, textSize, {
		Name = "Next",
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, textSize + 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	y += textSize + 14
	local tiers = UIKit.new("Frame", {
		Name = "Tiers",
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.new(1, -24, 0, (textSize + 6) * (#data.Tiers + 1) + 8),
		ZIndex = 3,
	}, right)
	Bubble.corner(tiers, 12)
	Bubble.stroke(tiers, 2.5)
	Bubble.ink(tiers, "ALL TIERS", textSize - 1, { Name = "Title", Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, textSize + 4), TextColor3 = Theme.InkSoft, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	for i, t in data.Tiers do
		Bubble.ink(tiers, t, textSize - 1, {
			Name = "Tier" .. i,
			Position = UDim2.fromOffset(10, 4 + i * (textSize + 6)),
			Size = UDim2.new(1, -20, 0, textSize + 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
	end
	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(1, -20, 0, (if compact then 72 else 56) + Theme.Lip),
		ZIndex = 4,
	}, right)
	UIKit.list(buttons, Enum.FillDirection.Horizontal, 8)
	local bw = math.floor((size.X - 32 - leftW - 16 - 20 - 16) / 3)
	local bh = if compact then 72 else 56
	local buy = Bubble.button(buttons, { Name = "Buy", Text = "BUY", Role = "Go", Size = Vector2.new(bw, bh), Price = data.Buy, PriceIcon = "coin", TextSize = textSize + 2, LayoutOrder = 1 })
	local shards = Bubble.button(buttons, { Name = "Shards", Text = "SHARDS", Role = "Gear", Size = Vector2.new(bw, bh), Price = data.Shards, PriceIcon = "shard", TextSize = textSize + 2, LayoutOrder = 2 })
	local equip = Bubble.button(buttons, { Name = "Equip", Text = "EQUIP", Role = "Enchant", Size = Vector2.new(bw, bh), TextSize = textSize + 6, LayoutOrder = 3 })
	return { Window = window, Rows = rows, Buy = buy, ShardsBuy = shards, Equip = equip }
end

export type OddsRow = { Name: string, Icon: string?, Color: Color3, Without: string, With: string }
export type BoostData = {
	Tab: string,
	Name: string,
	Icon: string,
	Active: string?,
	Text: string,
	Offers: { { Text: string, Price: string?, Soon: boolean? } },
	Note: string,
	Capsule: string,
	Odds: { OddsRow },
	Coins: string,
}
export type BoostRefs = { Window: Bubble.Window, Tabs: { [string]: TextButton }, Offers: { TextButton } }

EnchantBubble.BoostTabs = {
	{ Id = "TripleLucky", Label = "TRIPLE LUCKY", Icon = "clover", Role = "Boosts" },
	{ Id = "HexaLucky", Label = "HEXA LUCKY", Icon = "rainbow", Role = "Boosts" },
}

function EnchantBubble.boosts(parent: Instance, uiScale: number, data: BoostData): BoostRefs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "Boosts",
		Title = "LUCK BOOSTS",
		Icon = "clover",
		Role = "Boosts",
		Size = size,
		HeaderHeight = header,
	})
	headerChip(window, "coin", data.Coins, 54, 190)
	local body = window.Body
	local textSize = if compact then 19 else 15
	local tabs = Bubble.tabs(body, EnchantBubble.BoostTabs, data.Tab, if compact then Vector2.new(280, 72) else Vector2.new(220, 54), if compact then 22 else 19)
	local top = (if compact then 72 else 54) + Theme.Lip + 12
	local leftW = if compact then 470 else 380

	-- the boost and its offers
	local left = Bubble.inset(body, "Boost", UDim2.fromOffset(0, top), UDim2.new(0, leftW, 1, -top))
	Bubble.glowIcon(left, data.Icon, Color3.fromRGB(61, 220, 132), if compact then 76 else 80, { Position = UDim2.fromOffset(10, 10) })
	Bubble.ink(left, string.upper(data.Name), 28, {
		Name = "BoostName",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(102, 14),
		Size = UDim2.new(1, -112, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	if data.Active then
		Bubble.chip(left, "ACTIVE: " .. data.Active, Vector2.new(200, 30), 17, "Go", { Position = UDim2.fromOffset(102, 52) })
	end
	Bubble.ink(left, data.Text, textSize, {
		Name = "Text",
		Position = UDim2.fromOffset(14, if compact then 94 else 100),
		Size = UDim2.new(1, -28, 0, textSize * 2 + 8),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})
	local offers = UIKit.new("Frame", {
		Name = "Offers",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, if compact then 150 else 148),
		Size = UDim2.new(1, -20, 1, if compact then -170 else -190),
		ZIndex = 3,
	}, left)
	-- PC: one wide row per offer; phones: the offers side by side (72-unit buttons)
	UIKit.list(offers, if compact then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, 8)
	local offerRefs = {}
	for i, o in data.Offers do
		local face
		if compact then
			face = Bubble.button(offers, {
				Name = "Offer" .. i,
				Text = o.Text,
				Role = if o.Soon then "Plain" else "Go",
				Size = Vector2.new(math.floor((leftW - 20 - 16) / 3), 76),
				Price = if o.Soon then "SOON" else o.Price,
				PriceIcon = if o.Soon then "lock" else "coin",
				TextSize = 22,
				LayoutOrder = i,
			})
		else
			face = Bubble.button(offers, {
				Name = "Offer" .. i,
				Text = o.Text .. (if o.Soon then "  ·  COMING SOON" elseif o.Price then "  ·  " .. o.Price else ""),
				Role = if o.Soon then "Plain" else "Go",
				Size = Vector2.new(leftW - 20, 46),
				TextSize = textSize + 3,
				LayoutOrder = i,
			})
		end
		if o.Soon then
			plainLabel(face)
		end
		table.insert(offerRefs, face)
	end
	if not compact then
		Bubble.ink(left, data.Note, 13, {
			Name = "Note",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -8),
			Size = UDim2.new(1, -28, 0, 32),
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
	end

	-- the odds without / with the boost
	local right = Bubble.inset(body, "Odds", UDim2.fromOffset(leftW + 16, top), UDim2.new(1, -leftW - 16, 1, -top))
	local arrow = if compact then 60 else 44
	local _, prevHolder = Bubble.button(right, { Name = "PrevCapsule", Text = "<", Role = "Plain", Size = Vector2.new(arrow, arrow), TextSize = 26 })
	prevHolder.Position = UDim2.fromOffset(10, 8)
	local _, nextHolder = Bubble.button(right, { Name = "NextCapsule", Text = ">", Role = "Plain", Size = Vector2.new(arrow, arrow), TextSize = 26 })
	nextHolder.AnchorPoint = Vector2.new(1, 0)
	nextHolder.Position = UDim2.new(1, -10, 0, 8)
	for _, h in { prevHolder, nextHolder } do
		local face = h:FindFirstChild("Face") :: GuiObject
		local label = face:FindFirstChild("Label") :: TextLabel
		label.TextColor3 = Theme.Ink
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
			stroke.Transparency = 1
		end
	end
	Bubble.ink(right, string.upper(data.Capsule), if compact then 24 else 22, {
		Name = "Capsule",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(arrow + 20, 8),
		Size = UDim2.new(1, -arrow * 2 - 40, 0, arrow),
		ZIndex = 4,
	})
	local headY = arrow + 18
	type Column = { Text: string, X: number, Align: Enum.TextXAlignment }
	local cols: { Column } = {
		{ Text = "GOLEM", X = 0, Align = Enum.TextXAlignment.Left },
		{ Text = "WITHOUT", X = 0.6, Align = Enum.TextXAlignment.Right },
		{ Text = "WITH", X = 0.82, Align = Enum.TextXAlignment.Right },
	}
	for _, c in cols do
		Bubble.ink(right, c.Text, textSize - 2, {
			Name = "Head" .. c.Text,
			Position = UDim2.new(c.X, 14, 0, headY),
			Size = if c.X == 0 then UDim2.new(0.3, 0, 0, textSize + 2) else UDim2.new(0.18, -34, 0, textSize + 2),
			TextColor3 = Theme.InkSoft,
			TextXAlignment = c.Align,
			ZIndex = 4,
		})
	end
	local list = UIKit.new("ScrollingFrame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.InkSoft,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		Position = UDim2.fromOffset(10, headY + textSize + 8),
		Size = UDim2.new(1, -20, 1, -headY - textSize - 16),
		ZIndex = 3,
	}, right)
	UIKit.list(list, Enum.FillDirection.Vertical, 4)
	local rh = if compact then 30 else 30
	for i, r in data.Odds do
		local rowFrame = UIKit.new("Frame", {
			Name = "Row" .. i,
			BackgroundColor3 = if i % 2 == 0 then Theme.PanelTint else Theme.White,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, rh),
			ZIndex = 3,
		}, list)
		Bubble.corner(rowFrame, 8)
		if r.Icon then
			Bubble.icon(rowFrame, r.Icon, rh + 6, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -2, 0.5, 0) })
		end
		Bubble.ink(rowFrame, r.Name, textSize, {
			Name = "Name",
			Position = UDim2.fromOffset(rh + 6, 0),
			Size = UDim2.new(0.6, -rh - 6, 1, 0),
			TextColor3 = r.Color,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Bubble.ink(rowFrame, r.Without, textSize, {
			Name = "Without",
			Position = UDim2.new(0.6, 4, 0, 0),
			Size = UDim2.new(0.2, -10, 1, 0),
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 4,
		})
		Bubble.ink(rowFrame, r.With, textSize + 1, {
			Name = "With",
			Position = UDim2.new(0.82, 4, 0, 0),
			Size = UDim2.new(0.18, -12, 1, 0),
			TextColor3 = Color3.fromRGB(30, 160, 70),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 4,
		})
	end
	return { Window = window, Tabs = tabs, Offers = offerRefs }
end

return EnchantBubble
