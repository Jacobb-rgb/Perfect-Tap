--[[
	ARTIFACTS OF KALDRUM + the JOURNAL in the light "Bubble" look (pure
	builders, preview first; steps 6-7's CollectionView / StoryView move onto
	them).

	  build    collections on the left (progress bar, NEW when complete), the
	           selected collection's artifacts as rarity cards ("?" until
	           found, "x2" for spares), the selected artifact on the right:
	           picture, rarity, found count, lore, where it drops, the
	           collection reward and the chapter button
	  journal  chapters on the left (locked ones with a lock), a paper page
	           with the chapter text, PREV / NEXT and the page number
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local ArtifactsBubble = {}

export type Collection = { Id: string, Name: string, Found: number, Total: number, New: boolean? }
export type Artifact = { Id: string, Name: string, Rarity: string, Color: Color3, Found: number }
export type Data = {
	Collections: { Collection },
	Selected: string,
	Artifacts: { Artifact },
	Artifact: string,
	Lore: string,
	Where: string,
	Reward: string,
	Button: string,
	Found: number,
	Total: number,
}
export type Refs = { Window: Bubble.Window, Collections: { [string]: TextButton }, Cards: { [string]: TextButton }, Journal: TextButton }

local function stretch(holder: Frame, face: GuiObject, height: number)
	holder.Size = UDim2.new(1, 0, 0, height + Theme.Lip)
	for _, part in { "Shadow", "Lip" } do
		local piece = holder:FindFirstChild(part) :: Frame
		piece.Size = UDim2.new(1, 0, 0, height)
	end
	face.Size = UDim2.new(1, 0, 0, height)
end

local function headerButton(window: Bubble.Window, text: string, icon: string, width: number): TextButton
	local face, holder = Bubble.button(window.Header, { Name = text, Text = text, Role = "Plain", Size = Vector2.new(width, 46), Icon = icon, TextSize = 20 })
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -60, 0.5, -2)
	holder.ZIndex = 5
	local label = face:FindFirstChild("Label") :: TextLabel
	label.TextColor3 = Theme.Ink
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = false
		stroke.Transparency = 1
	end
	return face
end

function ArtifactsBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "Artifacts",
		Title = "ARTIFACTS OF KALDRUM",
		Icon = "artifact",
		Role = "Artifacts",
		Size = size,
		HeaderHeight = header,
		TitleSize = if compact then 34 else 34,
	})
	local journal = headerButton(window, "JOURNAL", "book", 180)
	Bubble.chip(window.Header, `{data.Found} / {data.Total} FOUND`, Vector2.new(180, 40), 20, nil, {
		Name = "Found",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60 - 180 - 14, 0.5, 0),
		ZIndex = 5,
	})
	local body = window.Body
	local leftW = if compact then 300 else 250
	local rightW = if compact then 390 else 290
	local textSize = if compact then 20 else 16

	-- collections
	local list = UIKit.new("Frame", { Name = "Collections", BackgroundTransparency = 1, Size = UDim2.new(0, leftW, 1, 0) }, body)
	UIKit.list(list, Enum.FillDirection.Vertical, 10)
	local rowH = if compact then 86 else 92
	local collections = {}
	for i, c in data.Collections do
		local on = c.Id == data.Selected
		local holder, face = Bubble.body(list, if on then Bubble.role("Artifacts") else Bubble.role("Plain"), Vector2.new(0, rowH), {
			Name = c.Id,
			Corner = 16,
			Clickable = true,
		})
		holder.LayoutOrder = i
		stretch(holder, face, rowH)
		if on then
			Bubble.select(face, true)
		end
		Bubble.ink(face, c.Name, textSize + 2, {
			Name = "Name",
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, if c.New then -84 else -24, 0, textSize + 6),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		local done = c.Found >= c.Total
		Bubble.progress(face, c.Found / c.Total, if done then Theme.Good else Color3.fromRGB(255, 189, 26), Vector2.new(leftW - 24, if compact then 28 else 24), if done then `{c.Found} / {c.Total} COMPLETE` else `{c.Found} / {c.Total} FOUND`, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -10),
		})
		if c.New then
			Bubble.badge(face, "NEW", Theme.Roles.Vault.Base)
		end
		collections[c.Id] = face :: TextButton
	end

	-- the selected collection's artifacts
	local mid = Bubble.inset(body, "Artifacts", UDim2.fromOffset(leftW + 16, 0), UDim2.new(1, -leftW - rightW - 32, 1, 0))
	local card = if compact then Vector2.new(150, 150) else Vector2.new(118, 140)
	local selectedName = ""
	for _, c in data.Collections do
		if c.Id == data.Selected then
			selectedName = string.upper(c.Name)
		end
	end
	Bubble.ink(mid, selectedName, if compact then 22 else 20, {
		Name = "Heading",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 26),
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local grid = UIKit.new("Frame", { Name = "Grid", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, if compact then 46 else 60), Size = UDim2.new(1, -16, 1, -66), ZIndex = 3 }, mid)
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(card.X, card.Y),
		CellPadding = UDim2.fromOffset(12, 30),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local cards = {}
	local selected: Artifact? = nil
	for i, a in data.Artifacts do
		if a.Found > 0 then
			if a.Id == data.Artifact then
				selected = a
			end
			cards[a.Id] = Bubble.card(grid, {
				Name = a.Id,
				Label = a.Name,
				Icon = "artifact_" .. a.Id,
				Color = a.Color,
				Chip = string.upper(a.Rarity),
				ChipWidth = card.X - 10,
				Size = card,
				NameSize = if compact then 19 else 15,
				ChipSize = if compact then 16 else 13,
				Badge = if a.Found > 1 then `x{a.Found}` else nil,
				BadgeColor = Theme.Roles.Lobby.Base,
				Selected = a.Id == data.Artifact,
				LayoutOrder = i,
			})
		else
			local holder, face = Bubble.body(grid, Bubble.role("Plain"), Vector2.new(card.X, card.Y - Theme.Lip), { Name = a.Id, Corner = 16, Clickable = true })
			holder.LayoutOrder = i
			Bubble.ink(face, "?", math.floor(card.Y * 0.5), { Name = "Mystery", FontFace = Theme.TitleFont, Size = UDim2.new(1, 0, 1, -16), TextColor3 = Theme.InkSoft, ZIndex = 4 })
			Bubble.chip(face, string.upper(a.Rarity), Vector2.new(card.X - 10, (if compact then 16 else 13) + 8), if compact then 16 else 13, Bubble.roleFrom(a.Color), {
				Name = "Chance",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, 0),
			})
			cards[a.Id] = face :: TextButton
		end
	end

	-- the selected artifact
	local right = Bubble.inset(body, "Detail", UDim2.new(1, -rightW, 0, 0), UDim2.new(0, rightW, 1, 0))
	local a = selected or data.Artifacts[1]
	local y = 10
	if compact then
		Bubble.glowIcon(right, "artifact_" .. a.Id, a.Color, 90, { Position = UDim2.fromOffset(12, 10) })
		Bubble.ink(right, string.upper(a.Name), 26, {
			Name = "ArtifactName",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(112, 16),
			Size = UDim2.new(1, -124, 0, 30),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Bubble.chip(right, string.upper(a.Rarity), Vector2.new(124, 30), 18, Bubble.roleFrom(a.Color), { Position = UDim2.fromOffset(112, 54) })
		y = 112
	else
		Bubble.glowIcon(right, "artifact_" .. a.Id, a.Color, 100, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10) })
		Bubble.ink(right, string.upper(a.Name), 26, {
			Name = "ArtifactName",
			FontFace = Theme.TitleFont,
			Position = UDim2.fromOffset(12, 116),
			Size = UDim2.new(1, -24, 0, 30),
			TextScaled = true,
			ZIndex = 4,
		})
		Bubble.chip(right, string.upper(a.Rarity) .. ` · FOUND {a.Found}`, Vector2.new(200, 28), 15, Bubble.roleFrom(a.Color), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 150),
		})
		y = 188
	end
	Bubble.ink(right, data.Lore, textSize - 1, {
		Name = "Lore",
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, if compact then 48 else 58),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})
	y += if compact then 50 else 60
	if not compact then
		Bubble.ink(right, data.Where, 13, {
			Name = "Where",
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.new(1, -28, 0, 32),
			TextColor3 = Theme.InkSoft,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 4,
		})
	end
	local reward = UIKit.new("Frame", {
		Name = "Reward",
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 244, 205),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 1, -(if compact then 72 else 60) - Theme.Lip - 20),
		Size = UDim2.new(1, -20, 0, if compact then 62 else 64),
		ZIndex = 3,
	}, right)
	Bubble.corner(reward, 12)
	Bubble.stroke(reward, 2.5, Color3.fromRGB(208, 138, 0))
	Bubble.ink(reward, "REWARD: " .. data.Reward, if compact then 16 else 13, {
		Name = "Text",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local button, buttonHolder = Bubble.button(right, {
		Name = "Chapter",
		Text = data.Button,
		Role = "Plain",
		Size = Vector2.new(rightW - 20, if compact then 72 else 60),
		TextSize = if compact then 19 else 16,
	})
	buttonHolder.AnchorPoint = Vector2.new(0, 1)
	buttonHolder.Position = UDim2.new(0, 10, 1, -10)
	local label = button:FindFirstChild("Label") :: TextLabel
	label.TextColor3 = Theme.InkSoft
	label.TextWrapped = true
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = false
		stroke.Transparency = 1
	end
	return { Window = window, Collections = collections, Cards = cards, Journal = journal }
end

export type Chapter = { Id: string, Name: string, Locked: boolean?, New: boolean? }
export type JournalData = { Chapters: { Chapter }, Selected: string, Kicker: string, Title: string, Text: string, Page: number, Pages: number }
export type JournalRefs = { Window: Bubble.Window, Chapters: { [string]: TextButton }, Prev: TextButton, Next: TextButton }

function ArtifactsBubble.journal(parent: Instance, uiScale: number, data: JournalData): JournalRefs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "Journal",
		Title = "JOURNAL OF KALDRUM",
		Icon = "book",
		Role = "Artifacts",
		Size = size,
		HeaderHeight = header,
	})
	local body = window.Body
	local leftW = if compact then 340 else 280
	local textSize = if compact then 20 else 17
	local list = UIKit.new("Frame", { Name = "Chapters", BackgroundTransparency = 1, Size = UDim2.new(0, leftW, 1, 0) }, body)
	UIKit.list(list, Enum.FillDirection.Vertical, 10)
	local rowH = if compact then 72 else 64
	local chapters = {}
	for i, c in data.Chapters do
		local on = c.Id == data.Selected
		local holder, face = Bubble.body(list, if on then Bubble.role("Artifacts") else Bubble.role("Plain"), Vector2.new(0, rowH), {
			Name = c.Id,
			Corner = 16,
			Clickable = not c.Locked,
		})
		holder.LayoutOrder = i
		stretch(holder, face, rowH)
		if on then
			Bubble.select(face, true)
		end
		local x = 12
		if c.Locked then
			Bubble.icon(face, "lock", 40, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0) })
			x = 48
		end
		Bubble.ink(face, c.Name, textSize, {
			Name = "Name",
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x - 12, 1, 0),
			TextColor3 = if c.Locked then Theme.InkSoft else Theme.Ink,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		if c.New then
			Bubble.badge(face, "NEW", Theme.Roles.Vault.Base)
		end
		chapters[c.Id] = face :: TextButton
	end
	-- the page
	local page = UIKit.new("Frame", {
		Name = "Page",
		BackgroundColor3 = Color3.fromRGB(255, 246, 222),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(leftW + 18, 0),
		Size = UDim2.new(1, -leftW - 18, 1, 0),
		ZIndex = 2,
	}, body)
	Bubble.corner(page, 20)
	Bubble.stroke(page, 3.5, Color3.fromRGB(150, 100, 40))
	UIKit.padding(page, if compact then 18 else 22)
	Bubble.ink(page, data.Kicker, textSize, {
		Name = "Kicker",
		Size = UDim2.new(1, 0, 0, textSize + 4),
		TextColor3 = Color3.fromRGB(150, 100, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	Bubble.ink(page, string.upper(data.Title), if compact then 34 else 32, {
		Name = "Title",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(0, textSize + 8),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	Bubble.ink(page, data.Text, if compact then 22 else 20, {
		Name = "Text",
		Position = UDim2.fromOffset(0, textSize + 56),
		Size = UDim2.new(1, 0, 1, -textSize - 56 - 90),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 3,
	})
	local h = if compact then 72 else 58
	local prev, prevHolder = Bubble.button(page, { Name = "Prev", Text = "< PREV", Role = "Plain", Size = Vector2.new(170, h), TextSize = 24 })
	prevHolder.AnchorPoint = Vector2.new(0, 1)
	prevHolder.Position = UDim2.fromScale(0, 1)
	local prevLabel = prev:FindFirstChild("Label") :: TextLabel
	prevLabel.TextColor3 = Theme.Ink
	local prevStroke = prevLabel:FindFirstChildOfClass("UIStroke")
	if prevStroke then
		prevStroke.Enabled = false
		prevStroke.Transparency = 1
	end
	local nextButton, nextHolder = Bubble.button(page, { Name = "Next", Text = "NEXT >", Role = "Artifacts", Size = Vector2.new(170, h), TextSize = 24 })
	nextHolder.AnchorPoint = Vector2.new(1, 1)
	nextHolder.Position = UDim2.fromScale(1, 1)
	Bubble.ink(page, `Page {data.Page} / {data.Pages}`, textSize, {
		Name = "PageNumber",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -h // 2 + 8),
		Size = UDim2.fromOffset(200, 30),
		TextColor3 = Color3.fromRGB(150, 100, 40),
		ZIndex = 3,
	})
	return { Window = window, Chapters = chapters, Prev = prev, Next = nextButton }
end

return ArtifactsBubble
