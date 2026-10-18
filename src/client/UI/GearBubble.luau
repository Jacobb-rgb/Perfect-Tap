--[[
	GEAR SHOP in the light "Bubble" look (pure builder, preview first; steps
	6-7's GearShopView moves onto it): one tall card per gear piece with its
	level (pips), what it does, the next step ("20 -> 22 walk speed"), the
	price and BUY / BOUGHT! / MAX.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local GearBubble = {}

export type Gear = {
	Id: string,
	Name: string,
	Icon: string,
	Level: number,
	MaxLevel: number,
	Text: string,
	From: string,
	To: string,
	Unit: string,
	Price: string,
	State: string, -- "Buy" | "Bought" | "Max"
	Color: Color3,
}
export type Data = { Gear: { Gear }, Coins: string, Note: string? }
export type Refs = { Window: Bubble.Window, Buy: { [string]: TextButton } }

function GearBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "GearShop",
		Title = "GEAR SHOP",
		Icon = "helmet",
		Role = "Gear",
		Size = size,
		HeaderHeight = header,
	})
	local coins = Bubble.chip(window.Header, data.Coins, Vector2.new(190, 44), 24, nil, {
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -54, 0.5, 0),
		ZIndex = 5,
	})
	local coinsText = coins:FindFirstChild("Text") :: TextLabel
	coinsText.Position = UDim2.fromOffset(30, 0)
	coinsText.Size = UDim2.new(1, -36, 1, 0)
	Bubble.icon(coins, "coin", 52, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = 6 })
	local body = window.Body
	local top = 0
	if data.Note then
		Bubble.text(body, data.Note, if compact then 21 else 18, {
			Name = "Note",
			Size = UDim2.new(1, 0, 0, 26),
			TextColor3 = Theme.Good,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		top = 36
	end
	local row = UIKit.new("Frame", { Name = "Cards", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, top + 14), Size = UDim2.new(1, 0, 1, -top - 14) }, body)
	UIKit.list(row, Enum.FillDirection.Horizontal, 12, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local count = #data.Gear
	local cardW = math.floor((size.X - 32 - (count - 1) * 12) / count)
	local cardH = size.Y - header - 3 - 32 - top - 14 - Theme.Lip
	local textSize = if compact then 19 else 15
	local buy = {}
	for i, g in data.Gear do
		local holder, face = Bubble.body(row, Bubble.roleFrom(g.Color), Vector2.new(cardW, cardH), { Name = g.Id, Corner = 20 })
		holder.LayoutOrder = i
		local iconSize = if compact then 130 else 150
		Bubble.icon(face, g.Icon, iconSize, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -20) })
		Bubble.chip(face, `LV {g.Level}/{g.MaxLevel}`, Vector2.new(78, 26), 15, nil, {
			Name = "Level",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
		})
		local y = iconSize - 26
		Bubble.text(face, string.upper(g.Name), if compact then 22 else 18, {
			Name = "GearName",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(6, y),
			Size = UDim2.new(1, -12, 0, 26),
			TextScaled = true,
			ZIndex = 4,
		})
		y += 30
		local pips = UIKit.new("Frame", { Name = "Pips", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 12), ZIndex = 4 }, face)
		UIKit.list(pips, Enum.FillDirection.Horizontal, 5, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
		for p = 1, g.MaxLevel do
			local pip = UIKit.new("Frame", {
				Name = "Pip" .. p,
				BackgroundColor3 = if p <= g.Level then Theme.Gold else Theme.White,
				BorderSizePixel = 0,
				LayoutOrder = p,
				Size = UDim2.fromOffset(20, 12),
				ZIndex = 4,
			}, pips)
			Bubble.corner(pip, 6)
			Bubble.stroke(pip, 2)
		end
		y += 20
		Bubble.text(face, g.Text, textSize, {
			Name = "Text",
			Position = UDim2.fromOffset(8, y),
			Size = UDim2.new(1, -16, 0, textSize * 2 + 6),
			TextWrapped = true,
			ZIndex = 4,
		})
		y += textSize * 2 + 10
		local buttonGap = (if compact then 72 else 56) + Theme.Lip + 18
		local stat = UIKit.new("Frame", {
			Name = "Stat",
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 1, -buttonGap),
			Size = UDim2.new(1, -16, 0, if compact then 66 else 64),
			ZIndex = 4,
		}, face)
		Bubble.corner(stat, 12)
		Bubble.stroke(stat, 2.5)
		Bubble.ink(stat, if g.State == "Max" then g.From else `{g.From} → {g.To}`, if compact then 28 else 24, {
			Name = "Step",
			FontFace = Theme.TitleFont,
			Size = UDim2.new(1, 0, 0.62, 0),
			ZIndex = 5,
		})
		Bubble.ink(stat, g.Unit, if compact then 15 else 13, {
			Name = "Unit",
			Position = UDim2.fromScale(0, 0.58),
			Size = UDim2.new(1, 0, 0.38, 0),
			TextColor3 = Theme.InkSoft,
			ZIndex = 5,
		})
		local buttonH = if compact then 72 else 56
		local face2, holder2
		if g.State == "Buy" then
			face2, holder2 = Bubble.button(face, { Name = "Buy", Text = "BUY", Role = "Go", Size = Vector2.new(cardW - 16, buttonH), Price = g.Price, PriceIcon = "coin", TextSize = if compact then 22 else 19 })
		else
			face2, holder2 = Bubble.button(face, {
				Name = "Buy",
				Text = if g.State == "Max" then "MAX" else "BOUGHT!",
				Role = "Plain",
				Size = Vector2.new(cardW - 16, buttonH),
				Icon = "check",
				TextSize = if compact then 22 else 19,
			})
			local label = face2:FindFirstChild("Label") :: TextLabel
			label.TextColor3 = Theme.Ink
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = false
				stroke.Transparency = 1
			end
		end
		holder2.AnchorPoint = Vector2.new(0.5, 1)
		holder2.Position = UDim2.new(0.5, 0, 1, -8)
		buy[g.Id] = face2
	end
	return { Window = window, Buy = buy }
end

return GearBubble
