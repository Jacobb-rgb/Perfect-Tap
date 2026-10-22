--[[
	HALL OF FAME (the 4 leaderboards) and SETTINGS in the light "Bubble" look
	(pure builders, preview first; steps 6-7's LeaderboardView / SettingsView
	move onto them).

	  boards    tabs MONEY/S / EARNED / ARTIFACTS / HOURS, the top 10 with gold /
	            silver / bronze medals for 1-3 (your row highlighted), your rank
	            at the bottom (2 columns of 5 on phones)
	  settings  one row per setting: icon, name, what it does, and a slider
	            (with - / +) or an ON / OFF switch; "coming soon" rows say so
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local BoardsBubble = {}

export type Entry = { Rank: number, Name: string, Value: string, You: boolean? }
export type BoardsData = { Tab: string, Entries: { Entry }, You: Entry, Note: string }
export type BoardsRefs = { Window: Bubble.Window, Tabs: { [string]: TextButton } }

BoardsBubble.Tabs = {
	{ Id = "MoneyPerSec", Label = "MONEY/S", Icon = "coin", Role = "Boards" },
	{ Id = "TotalEarned", Label = "EARNED", Icon = "coins", Role = "Boards" },
	{ Id = "Artifacts", Label = "ARTIFACTS", Icon = "artifact", Role = "Boards" },
	{ Id = "HoursPlayed", Label = "HOURS", Icon = "medal", Role = "Boards" },
	{ Id = "Level", Label = "LEVEL", Icon = "medal", Role = "Boards" },
}

local MEDALS = {
	Color3.fromRGB(255, 203, 46),
	Color3.fromRGB(205, 214, 228),
	Color3.fromRGB(222, 140, 80),
}

local function row(parent: Instance, e: Entry, h: number, textSize: number, order: number): Frame
	local role = if e.You then Bubble.role("Artifacts") else Bubble.role("Plain")
	local holder, face = Bubble.body(parent, role, Vector2.new(0, h), { Name = "Rank" .. e.Rank, Corner = 12, Gloss = false })
	holder.LayoutOrder = order
	holder.Size = UDim2.new(1, 0, 0, h + Theme.Lip)
	for _, part in { "Shadow", "Lip" } do
		local piece = holder:FindFirstChild(part) :: Frame
		piece.Size = UDim2.new(1, 0, 0, h)
	end
	face.Size = UDim2.new(1, 0, 0, h)
	local medal = UIKit.new("Frame", {
		Name = "Medal",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = MEDALS[e.Rank] or Theme.PanelTint,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(h - 8, h - 8),
		ZIndex = 4,
	}, face)
	Bubble.corner(medal, h)
	Bubble.stroke(medal, 2.5)
	Bubble.ink(medal, tostring(e.Rank), textSize, { Name = "Number", Size = UDim2.fromScale(1, 1), ZIndex = 5 })
	Bubble.ink(face, e.Name, textSize, {
		Name = "PlayerName",
		Position = UDim2.fromOffset(h + 6, 0),
		Size = UDim2.new(0.62, -h - 6, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	Bubble.ink(face, e.Value, textSize, {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0.38, -12, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	return holder
end

function BoardsBubble.boards(parent: Instance, uiScale: number, data: BoardsData): BoardsRefs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "Boards",
		Title = "HALL OF FAME",
		Icon = "trophy",
		Role = "Boards",
		Size = size,
		HeaderHeight = header,
	})
	local body = window.Body
	local tabs = Bubble.tabs(body, BoardsBubble.Tabs, data.Tab, if compact then Vector2.new(220, 72) else Vector2.new(170, 54), if compact then 22 else 19)
	Bubble.ink(body, data.Note, if compact then 17 else 15, {
		Name = "Note",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(if compact then 260 else 220, if compact then 72 else 54),
		TextColor3 = Theme.InkSoft,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	})
	local top = (if compact then 72 else 54) + Theme.Lip + 12
	local youH = if compact then 52 else 46
	local list = Bubble.inset(body, "List", UDim2.fromOffset(0, top), UDim2.new(1, 0, 1, -top - youH - Theme.Lip - 12))
	local rows = UIKit.new("Frame", { Name = "Rows", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), ZIndex = 3 }, list)
	local textSize = if compact then 22 else 18
	local h
	if compact then
		h = 38
		textSize = 20
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, h + Theme.Lip),
			CellPadding = UDim2.fromOffset(12, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, rows)
	else
		h = 24
		textSize = 16
		UIKit.list(rows, Enum.FillDirection.Vertical, 3)
	end
	for i, e in data.Entries do
		row(rows, e, h, textSize, i)
	end
	local youHolder = row(body, data.You, youH, textSize + 2, 0)
	youHolder.AnchorPoint = Vector2.new(0, 1)
	youHolder.Position = UDim2.fromScale(0, 1)
	youHolder.Name = "You"
	return { Window = window, Tabs = tabs }
end

export type Setting = {
	Id: string,
	Name: string,
	Hint: string,
	Icon: string,
	Kind: string, -- "Slider" | "Toggle" | "Soon"
	Value: number?, -- 0..1 (Slider)
	On: boolean?, -- (Toggle)
}
export type SettingsRefs = { Window: Bubble.Window, Rows: { [string]: Frame } }

function BoardsBubble.settings(parent: Instance, uiScale: number, settings: { Setting }, note: string): SettingsRefs
	local compact = uiScale <= 0.75
	local size = if compact then Vector2.new(1100, 500) else Vector2.new(780, 470)
	local window = Bubble.window(parent, {
		Name = "Settings",
		Title = "SETTINGS",
		Icon = "cog",
		Role = "Settings",
		Size = size,
		HeaderHeight = if compact then 60 else 68,
	})
	local body = window.Body
	Bubble.ink(body, note, if compact then 19 else 16, {
		Name = "Note",
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local list = UIKit.new("Frame", { Name = "Rows", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34) }, body)
	UIKit.list(list, Enum.FillDirection.Vertical, 10)
	local h = if compact then 82 else 74
	local button = if compact then 72 else 52
	local rows = {}
	for i, setting in settings do
		local holder, face = Bubble.body(list, Bubble.role("Plain"), Vector2.new(0, h), { Name = setting.Id, Corner = 18, Gloss = false })
		holder.LayoutOrder = i
		holder.Size = UDim2.new(1, 0, 0, h + Theme.Lip)
		for _, part in { "Shadow", "Lip" } do
			local piece = holder:FindFirstChild(part) :: Frame
			piece.Size = UDim2.new(1, 0, 0, h)
		end
		face.Size = UDim2.new(1, 0, 0, h)
		Bubble.icon(face, setting.Icon, h + 6, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, -2) })
		Bubble.ink(face, setting.Name, if compact then 26 else 22, {
			Name = "Name",
			Position = UDim2.fromOffset(h + 12, 8),
			Size = UDim2.new(0.5, -h - 12, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		Bubble.ink(face, setting.Hint, if compact then 18 else 15, {
			Name = "Hint",
			Position = UDim2.fromOffset(h + 12, if compact then 42 else 38),
			Size = UDim2.new(0.5, -h - 12, 0, 24),
			TextColor3 = Theme.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		local controls = UIKit.new("Frame", {
			Name = "Controls",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -14, 0.5, -2),
			Size = UDim2.new(0.5, 0, 0, button + Theme.Lip),
			ZIndex = 4,
		}, face)
		if setting.Kind == "Slider" then
			local _, minusHolder = Bubble.button(controls, { Name = "Minus", Text = "-", Role = "Build", Size = Vector2.new(button, button), TextSize = 30 })
			minusHolder.Position = UDim2.fromOffset(0, 0)
			Bubble.slider(controls, setting.Value or 0, Theme.Roles.Gear.Base, Vector2.new(if compact then 220 else 150, 14), {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, button + 26, 0.5, -2),
			})
			local _, plusHolder = Bubble.button(controls, { Name = "Plus", Text = "+", Role = "Build", Size = Vector2.new(button, button), TextSize = 30 })
			plusHolder.Position = UDim2.fromOffset(button + 52 + (if compact then 220 else 150), 0)
			Bubble.ink(controls, `{math.floor((setting.Value or 0) * 100 + 0.5)}%`, if compact then 24 else 20, {
				Name = "Percent",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, -2),
				Size = UDim2.fromOffset(70, 30),
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 5,
			})
		elseif setting.Kind == "Toggle" then
			Bubble.toggle(controls, setting.On == true, Vector2.new(if compact then 150 else 120, button), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
			})
		else
			Bubble.chip(controls, "COMING SOON", Vector2.new(if compact then 200 else 170, 36), if compact then 20 else 17, nil, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
			})
		end
		rows[setting.Id] = holder
	end
	return { Window = window, Rows = rows }
end

return BoardsBubble
