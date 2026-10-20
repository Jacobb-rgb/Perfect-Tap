--[[
	The journal of Kaldrum (step 7): the story chapters as journal pages.
	Pure builder, layout math and texts (ArtifactController fills it in and
	handles input; the Lune preview builds the same view). Read at the Guild
	board, at the FOSSIL DIG's story screen and from the collection book.

	  left    the chapters (a scrolling list): the Prologue (always open),
	          then one per artifact collection, open once that collection is
	          complete (StoryConfig / ArtifactConfig), with a lock and what
	          unlocks it otherwise, and NEW while it is unread
	  right   a parchment page: the chapter's title, the page's title and
	          text, "Page 2 / 4" and the PREV / NEXT buttons (LB / RB on a
	          gamepad, the arrow keys on a keyboard); a locked chapter shows
	          what to find instead of its pages
	X, B and Backspace close it. Opening an unread chapter marks it read
	(the controller sends ArtifactAction "ReadChapter").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local StoryConfig = require(Shared.Config.StoryConfig)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
local LightSkin = require(script.Parent.LightSkin)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)

local StoryView = {}

StoryView.PrologueKey = "Prologue"

export type Entry = {
	Key: string, -- "Prologue" or a collection id
	Title: string, -- "Chapter 1: The Ember Kings"
	Unlocked: boolean,
	New: boolean,
	Pages: { StoryConfig.Page },
	Locked: string, -- what unlocks it ("" when open)
}

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Title: TextLabel,
	Close: TextButton,
	List: ScrollingFrame,
	Buttons: { [string]: TextButton },
	Page: Frame,
	Chapter: TextLabel,
	PageTitle: TextLabel,
	Text: TextLabel,
	Number: TextLabel,
	Prev: TextButton,
	Next: TextButton,
	Hint: TextLabel,
	Key: string,
	PageIndex: number,
	Compact: boolean,
}

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Pad: number,
	ListWidth: number,
	Row: number,
	Button: number,
	Close: number,
	Title: number,
	Body: number,
	Text: number,
	Hint: number,
}

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 960,
		Height = 600,
		Header = 70,
		Pad = 16,
		ListWidth = 280,
		Row = 66,
		Button = 54,
		Close = 54,
		Title = 36,
		Body = 18,
		Text = 22,
		Hint = 16,
	},
	Compact = {
		Width = 1060,
		Height = 600,
		Header = 62,
		Pad = 12,
		ListWidth = 300,
		Row = 76,
		Button = 72,
		Close = 72,
		Title = 32,
		Body = 20,
		Text = 24,
		Hint = 18,
	},
}

local GOLD = Color3.fromRGB(255, 196, 64)
local PARCHMENT = Color3.fromRGB(236, 218, 176)
local PARCHMENT_EDGE = Color3.fromRGB(196, 160, 104)
local INK = Color3.fromRGB(62, 40, 26)
local INK_DIM = Color3.fromRGB(120, 88, 60)

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

-- The journal's chapters for a data.Artifacts record, in story order.
function StoryView.entries(artifacts: any): { Entry }
	local list: { Entry } = {
		{
			Key = StoryView.PrologueKey,
			Title = "Prologue: " .. StoryConfig.Prologue.Title,
			Unlocked = true,
			New = false,
			Pages = StoryConfig.Prologue.Pages,
			Locked = "",
		},
	}
	local chapters = table.clone(StoryConfig.Chapters)
	table.sort(chapters, function(a: StoryConfig.Chapter, b: StoryConfig.Chapter): boolean
		return a.Number < b.Number
	end)
	local read = if type(artifacts) == "table" and type(artifacts.Chapters) == "table" then artifacts.Chapters else {}
	for _, chapter in chapters do
		local collection = ArtifactConfig.CollectionById[chapter.Collection]
		local unlocked = ArtifactConfig.isComplete(artifacts, chapter.Collection)
		local count = #(ArtifactConfig.ByCollection[chapter.Collection] or {})
		table.insert(list, {
			Key = chapter.Collection,
			Title = `Chapter {chapter.Number}: {chapter.Title}`,
			Unlocked = unlocked,
			New = unlocked and read[chapter.Collection] ~= true,
			Pages = chapter.Pages,
			Locked = if unlocked
				then ""
				else `Find all {count} artifacts of {if collection then collection.Name else chapter.Collection} to unlock this chapter.`,
		})
	end
	return list
end

-- The entry for a key (nil when unknown).
function StoryView.entry(entries: { Entry }, key: string): Entry?
	for _, entry in entries do
		if entry.Key == key then
			return entry
		end
	end
	return nil
end

---------------------------------------------------------------- building

function StoryView.build(compact: boolean): Refs
	local m = metrics(compact)
	local gui = UIKit.screen("TerraForgeJournal", 20)
	gui:SetAttribute("TerraForge", true)
	gui.Enabled = false
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 140),
		Position = UDim2.fromOffset(0, -140),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active = true,
	}, gui)
	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(m.Width, m.Height),
		Active = true,
	})
	local title = UIKit.label(panel, "JOURNAL OF KALDRUM", m.Title, {
		Name = "Title",
		Position = UDim2.fromOffset(m.Pad + 4, 10),
		Size = UDim2.new(0, 560, 0, m.Header - 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = GOLD,
		TextWrapped = false,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(m.Close, m.Close),
		TextSize = 26,
	})
	local list = UIKit.new("ScrollingFrame", {
		Name = "Chapters",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	UIKit.list(list, Enum.FillDirection.Vertical, 8)
	UIKit.padding(list, 4)
	local page = UIKit.new("Frame", {
		Name = "Page",
		BackgroundColor3 = PARCHMENT,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(page, 10)
	UIKit.stroke(page, 4, PARCHMENT_EDGE)
	local chapter = UIKit.label(page, "", m.Body, {
		Name = "Chapter",
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -48, 0, m.Body + 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = INK_DIM,
		TextWrapped = false,
	})
	local pageTitle = UIKit.label(page, "", m.Text + 8, {
		Name = "PageTitle",
		Position = UDim2.fromOffset(24, 18 + m.Body + 6),
		Size = UDim2.new(1, -48, 0, m.Text + 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = INK,
		TextWrapped = false,
	})
	local text = UIKit.label(page, "", m.Text, {
		Name = "Text",
		Position = UDim2.fromOffset(24, 26 + m.Body + m.Text + 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = INK,
		TextWrapped = true,
	})
	-- ink on parchment: no light outline around the letters
	for _, label in { chapter, pageTitle, text } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke:Destroy()
		end
	end
	local number = UIKit.label(page, "", m.Body, {
		Name = "Number",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(200, m.Body + 6),
		TextColor3 = INK_DIM,
		TextWrapped = false,
	})
	local numberStroke = number:FindFirstChildOfClass("UIStroke")
	if numberStroke then
		numberStroke:Destroy()
	end
	local prev = UIKit.button(page, "< PREV", Theme.PanelLight, Theme.PanelDark, {
		Name = "Prev",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -12),
		Size = UDim2.fromOffset(150, m.Button),
		TextSize = 22,
	})
	local nextButton = UIKit.button(page, "NEXT >", Theme.Accent, Theme.AccentDark, {
		Name = "Next",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(150, m.Button),
		TextSize = 22,
	})
	local hint = UIKit.label(panel, "", m.Hint, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	return {
		Gui = gui,
		Dim = dim,
		Panel = panel,
		Title = title,
		Close = close,
		List = list,
		Buttons = {},
		Page = page,
		Chapter = chapter,
		PageTitle = pageTitle,
		Text = text,
		Number = number,
		Prev = prev,
		Next = nextButton,
		Hint = hint,
		Key = StoryView.PrologueKey,
		PageIndex = 1,
		Compact = compact,
	}
end

-- Fits the journal into `maxWidth` x `maxHeight` design units.
function StoryView.layout(refs: Refs, maxWidth: number, maxHeight: number)
	local m = metrics(refs.Compact)
	local width = math.min(m.Width, maxWidth - 16)
	local height = math.min(m.Height, maxHeight - 12)
	refs.Panel.Size = UDim2.fromOffset(width, height)
	local pad = m.Pad
	local hintH = m.Hint + 8
	local bodyH = height - m.Header - pad - hintH
	local listW = math.min(m.ListWidth, math.floor(width * 0.32))
	refs.List.Position = UDim2.fromOffset(pad, m.Header)
	refs.List.Size = UDim2.fromOffset(listW, bodyH)
	-- the page starts below the X, which reaches under the header on phones
	local pageX = pad + listW + pad
	local pageTop = math.max(m.Header, 8 + m.Close + 6)
	local pageH = bodyH - (pageTop - m.Header)
	refs.Page.Position = UDim2.fromOffset(pageX, pageTop)
	refs.Page.Size = UDim2.fromOffset(width - pageX - pad, pageH)
	local textTop = 26 + m.Body + m.Text + 20
	refs.Text.Size = UDim2.new(1, -48, 0, math.max(40, pageH - textTop - m.Button - 24))
	refs.Hint.Position = UDim2.fromOffset(pad, height - 6)
	refs.Hint.Size = UDim2.fromOffset(width - 2 * pad, m.Hint + 4)
end

-- Rebuilds the chapter list (one button per entry); `onPick(key)` runs
-- when a chapter's button is pressed.
function StoryView.setEntries(refs: Refs, entries: { Entry }, onPick: ((string) -> ())?)
	local m = metrics(refs.Compact)
	for _, child in refs.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(refs.Buttons)
	for i, entry in entries do
		local color = if entry.Key == refs.Key then Theme.Accent elseif entry.Unlocked then Theme.PanelLight else Theme.PanelDark
		local dark = if entry.Key == refs.Key then Theme.AccentDark else Theme.Outline
		local button = UIKit.button(refs.List, "", color, dark, {
			Name = entry.Key,
			LayoutOrder = i,
			Size = UDim2.new(1, -12, 0, m.Row),
		})
		local lock = if entry.Unlocked then "" else "🔒 "
		UIKit.label(button, lock .. entry.Title, m.Body, {
			Name = "Label",
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -24, 1, -8),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if entry.Unlocked or entry.Key == refs.Key then Theme.Text else Theme.TextDim,
			TextWrapped = true,
		})
		if entry.New then
			local badge = UIKit.chip(button, "NEW", Theme.Bad, {
				Name = "New",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, -8),
				Size = UDim2.fromOffset(52, 22),
				ZIndex = 4,
			})
			badge.TextSize = 14
		end
		refs.Buttons[entry.Key] = button
		if onPick then
			local key = entry.Key
			button.Activated:Connect(function()
				onPick(key)
			end)
		end
	end
	refs.List.CanvasSize = UDim2.fromOffset(0, #entries * (m.Row + 8) + 8)
end

-- Shows a page of an entry (clamped); a locked entry shows what unlocks it.
function StoryView.showPage(refs: Refs, entry: Entry, index: number)
	refs.Key = entry.Key
	local pages = entry.Pages
	local count = if entry.Unlocked then #pages else 0
	local i = math.clamp(index, 1, math.max(1, count))
	refs.PageIndex = i
	refs.Chapter.Text = entry.Title
	if not entry.Unlocked then
		refs.PageTitle.Text = "A sealed chapter"
		refs.Text.Text = entry.Locked
		refs.Number.Text = ""
	else
		local page = pages[i]
		refs.PageTitle.Text = if page then page.Title else ""
		refs.Text.Text = if page then page.Text else ""
		refs.Number.Text = `Page {i} / {count}`
	end
	local prevHolder = refs.Prev.Parent
	if prevHolder and prevHolder:IsA("Frame") then
		prevHolder.Visible = entry.Unlocked and i > 1
	end
	local nextHolder = refs.Next.Parent
	if nextHolder and nextHolder:IsA("Frame") then
		nextHolder.Visible = entry.Unlocked and i < count
	end
end


---------------------------------------------------------------- the light look (UIConfig.LightUI)
-- While the light UI is on (ships off), the same window wears the light
-- look (LightSkin); windows also hide Roblox's touch controls while open.
local darkBuild = StoryView.build
StoryView.build = function(compact: boolean): Refs
	local refs = darkBuild(compact)
	if UIConfig.lightUI() then
		LightSkin.apply(refs.Gui)
		TouchControls.follow(refs.Gui)
	end
	return refs
end

return StoryView
