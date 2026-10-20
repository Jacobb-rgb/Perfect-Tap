--[[
	Capsule opening reveal in the light "Bubble" look (pure builder, preview
	first; step 7's opening keeps its 3D capsule + golem, this is the overlay).

	  single   rays in the rarity colour, the golem, its name, rarity + NEW!
	           chips, the bonus, OK / OPEN 1 AGAIN (price); "TRIPLE LUCKY ODDS"
	           on top while the boost runs
	  multi    "10 GOLEMS WOKE UP!", a card per golem (NEW! marks, the best one
	           outlined in gold), OK / OPEN 10 AGAIN
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local OpeningBubble = {}

export type Golem = {
	Id: string,
	Kind: string,
	Name: string,
	Rarity: string,
	Color: Color3,
	Bonus: string,
	New: boolean?,
	Best: boolean?,
}

export type Data = {
	Golems: { Golem },
	Again: string, -- "OPEN 1 AGAIN"
	Price: string,
	Currency: string, -- "Coins" | "Robux"
	Lucky: boolean?,
}

export type Refs = { Ok: TextButton, Again: TextButton, Cards: { [string]: TextButton } }

local function compact(uiScale: number): boolean
	return uiScale <= 0.75
end

local function buttons(parent: Instance, data: Data, small: boolean, y: UDim): (TextButton, TextButton)
	local h = if small then 72 else 64
	local row = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, y.Scale, y.Offset),
		Size = UDim2.fromOffset(560, h + Theme.Lip),
		ZIndex = 5,
	}, parent)
	UIKit.list(row, Enum.FillDirection.Horizontal, 16, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local ok = Bubble.button(row, { Name = "Ok", Text = "OK", Role = "Go", Size = Vector2.new(200, h), TextSize = 30, LayoutOrder = 1 })
	local again = Bubble.button(row, {
		Name = "Again",
		Text = data.Again,
		Role = "Build",
		Size = Vector2.new(330, h),
		Price = data.Price,
		PriceIcon = if data.Currency == "Robux" then "robux" else "coin",
		TextSize = if small then 24 else 22,
		LayoutOrder = 2,
	})
	return ok, again
end

local function luckyChip(parent: Instance)
	local chip = Bubble.chip(parent, "TRIPLE LUCKY ODDS", Vector2.new(260, 40), 20, "Build", {
		Name = "Lucky",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
	})
	Bubble.icon(chip, "clover", 50, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 4, 0.5, -2), ZIndex = 6 })
end

-- One golem: rays, the golem, name, chips, bonus, buttons.
function OpeningBubble.single(parent: Instance, uiScale: number, data: Data): Refs
	local small = compact(uiScale)
	local golem = data.Golems[1]
	local cy = if small then 0.36 else 0.42 -- the golem's height on screen
	local stage = UIKit.new("Frame", { Name = "Reveal", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, parent)
	if data.Lucky then
		luckyChip(stage)
	end
	local center = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, cy, 0),
		Size = UDim2.fromOffset(10, 10),
		ZIndex = 1,
	}, stage)
	for i = 0, 11 do
		UIKit.new("Frame", {
			Name = "Ray" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if i % 2 == 0 then golem.Color else Theme.White,
			BackgroundTransparency = if i % 2 == 0 then 0.55 else 0.8,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = i * 15,
			Size = UDim2.fromOffset(if small then 900 else 760, if i % 2 == 0 then 54 else 30),
			ZIndex = 1,
		}, center)
	end
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = golem.Color,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(250, 250),
		ZIndex = 2,
	}, center)
	Bubble.corner(glow, 125)
	Bubble.icon(stage, "golem_" .. golem.Kind, if small then 250 else 290, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, cy, -10),
		ZIndex = 3,
	})
	local name = Bubble.text(stage, string.upper(golem.Name), if small then 52 else 56, {
		Name = "GolemName",
		FontFace = Theme.TitleFont,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, cy, if small then 120 else 150),
		Size = UDim2.fromOffset(900, 64),
		ZIndex = 5,
	})
	local stroke = name:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 4
	end
	local chips = UIKit.new("Frame", {
		Name = "Chips",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, cy, if small then 186 else 218),
		Size = UDim2.fromOffset(400, 40),
		ZIndex = 5,
	}, stage)
	UIKit.list(chips, Enum.FillDirection.Horizontal, 10, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	Bubble.chip(chips, string.upper(golem.Rarity), Vector2.new(150, 38), 22, Bubble.roleFrom(golem.Color), { LayoutOrder = 1 })
	if golem.New then
		Bubble.chip(chips, "NEW!", Vector2.new(100, 38), 22, "Vault", { LayoutOrder = 2 })
	end
	Bubble.text(stage, golem.Bonus, if small then 30 else 28, {
		Name = "Bonus",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, cy, if small then 232 else 264),
		Size = UDim2.fromOffset(600, 36),
		TextColor3 = Theme.Good,
		ZIndex = 5,
	})
	local ok, again = buttons(stage, data, small, UDim.new(1, -18))
	return { Ok = ok, Again = again, Cards = {} }
end

-- Several golems at once (x3 / x10): a card each, the best one in gold.
function OpeningBubble.multi(parent: Instance, uiScale: number, data: Data): Refs
	local small = compact(uiScale)
	local stage = UIKit.new("Frame", { Name = "Reveal", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, parent)
	if data.Lucky then
		luckyChip(stage)
	end
	local title = Bubble.text(stage, `{#data.Golems} GOLEMS WOKE UP!`, if small then 46 else 48, {
		Name = "Title",
		FontFace = Theme.TitleFont,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if data.Lucky then 64 else 30),
		Size = UDim2.fromOffset(900, 56),
	})
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 4
	end
	local card = if small then Vector2.new(150, 150) else Vector2.new(150, 164)
	local cols = 5
	local rows = math.ceil(#data.Golems / cols)
	local gap = Vector2.new(16, 30)
	local grid = UIKit.new("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, (if data.Lucky then 64 else 30) + 80),
		Size = UDim2.fromOffset(cols * card.X + (cols - 1) * gap.X, rows * card.Y + (rows - 1) * gap.Y + 20),
	}, stage)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(card.X, card.Y),
		CellPadding = UDim2.fromOffset(gap.X, gap.Y),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local cards = {}
	for i, golem in data.Golems do
		cards[golem.Id] = Bubble.card(grid, {
			Name = golem.Id,
			Label = golem.Name,
			Icon = "golem_" .. golem.Kind,
			Color = golem.Color,
			Chip = golem.Bonus,
			ChipWidth = card.X - 10,
			Size = card,
			NameSize = if small then 21 else 19,
			ChipSize = if small then 17 else 15,
			Badge = if golem.New then "NEW" else nil,
			BadgeColor = Theme.Roles.Vault.Base,
			Selected = golem.Best,
			LayoutOrder = i,
		})
	end
	local ok, again = buttons(stage, data, small, UDim.new(1, -18))
	return { Ok = ok, Again = again, Cards = cards }
end

return OpeningBubble
