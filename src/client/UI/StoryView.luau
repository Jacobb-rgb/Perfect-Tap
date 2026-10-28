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

	The Pop look (owner 2026-10-21: "new, modern, colourful, Roblox style";
	the collection book's pieces, CollectionView): the bright band in the
	book's colour, the red square X, the chapters as painted buttons (the
	open one orange with a gold edge, the others blue, a locked one dark),
	the parchment page with a black border and painted PREV / NEXT.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local StoryConfig = require(Shared.Config.StoryConfig)
local PopTheme = require(Shared.Config.PopTheme)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local CollectionView = require(script.Parent.CollectionView)
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

local PARCHMENT = Color3.fromRGB(240, 224, 186)
local INK = Color3.fromRGB(62, 40, 26)
local INK_DIM = Color3.fromRGB(120, 88, 60)

StoryView.Paint = CollectionView.Paint -- the band (the book's colour)
StoryView.PickColor = CollectionView.SelectColor -- the open chapter's edge
StoryView.LockedPaint = {
	Top = Color3.fromRGB(70, 74, 88),
	Bottom = Color3.fromRGB(34, 36, 46),
	Edge = PopTheme.Outline,
} :: Pop.Paint

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
	gui:SetAttribute("PopSkin", true)
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
	-- the Pop window: the book's colour on the band, the dark studded floor
	CollectionView.chrome(panel, StoryView.Paint, m.Header)
	local room = CollectionView.titleRoom(panel) -- (the round look's band icon)
	local title = Pop.text(panel, Pop.caption("JOURNAL OF KALDRUM"), m.Title, {
		Name = "Title",
		Position = UDim2.fromOffset(m.Pad + 4 + room, 10),
		Size = UDim2.new(0, 560 - room, 0, m.Header - 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	Pop.shadow(title)
	local close = CollectionView.closeButton(panel, m.Close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
	})
	local list = UIKit.new("ScrollingFrame", {
		Name = "Chapters",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(200, 208, 226),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 2,
	}, panel)
	UIKit.list(list, Enum.FillDirection.Vertical, 8)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, list)
	-- the page: parchment with a black border and a light rim (ink on it, no edges)
	local page = UIKit.new("Frame", {
		Name = "Page",
		BackgroundColor3 = PARCHMENT,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, panel)
	UIKit.corner(page, 10)
	Pop.border(page, 4)
	Pop.rim(page, Color3.fromRGB(255, 246, 222), 10, 4, 2)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(226, 216, 200)), Rotation = 90 }, page)
	local function ink(name: string, size: number, color: Color3, props: { [string]: any }): TextLabel
		local label = UIKit.new("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			FontFace = PopTheme.Font,
			Text = "",
			TextColor3 = color,
			TextSize = size,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}, page)
		for key, value in props do
			(label :: any)[key] = value
		end
		return label
	end
	local chapter = ink("Chapter", m.Body, INK_DIM, {
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -48, 0, m.Body + 6),
	})
	local pageTitle = ink("PageTitle", m.Text + 8, INK, {
		Position = UDim2.fromOffset(24, 18 + m.Body + 6),
		Size = UDim2.new(1, -48, 0, m.Text + 14),
		FontFace = PopTheme.Heavy,
	})
	local text = ink("Text", m.Text, INK, {
		Position = UDim2.fromOffset(24, 26 + m.Body + m.Text + 20),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})
	local number = ink("Number", m.Body, INK_DIM, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(200, m.Body + 6),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local prev = CollectionView.popButton(page, "< PREV", "Blue", {
		Name = "Prev",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -12),
		Size = UDim2.fromOffset(150, m.Button),
		TextSize = 24,
	})
	local nextButton = CollectionView.popButton(page, "NEXT >", "Orange", {
		Name = "Next",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(150, m.Button),
		TextSize = 24,
	})
	local hint = Pop.text(panel, "", m.Hint, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = CollectionView.SoftInk,
		ZIndex = 3,
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
	CollectionView.layoutChrome(refs.Panel, m.Header)
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
		-- the open chapter orange, the others blue, a locked one dark
		local picked = entry.Key == refs.Key
		local paint = if picked then "Orange" elseif entry.Unlocked then "Blue" else StoryView.LockedPaint
		local button = CollectionView.popButton(refs.List, "", paint, {
			Name = entry.Key,
			LayoutOrder = i,
			Size = UDim2.new(1, -12, 0, m.Row),
		})
		local holder = button.Parent :: Frame
		if picked then
			local border = holder:FindFirstChild("Border") :: UIStroke?
			if border then
				border.Color = StoryView.PickColor
				border.Thickness = 4
			end
		end
		local lock = if entry.Unlocked then "" else "LOCKED: " -- (owner: no emoji, text only)
		Pop.text(button, lock .. entry.Title, m.Body, {
			Name = "Label",
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -24, 1, -8),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if entry.Unlocked or picked then PopTheme.Ink else CollectionView.SoftInk,
			TextWrapped = true,
			ZIndex = 6,
		})
		if entry.New then
			Pop.chip(button, "NEW", "Red", Vector2.new(52, 22), {
				Name = "New",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, -8),
				Rotation = 6,
				ZIndex = 9,
			})
		end
		refs.Buttons[entry.Key] = button
		if onPick then
			local key = entry.Key
			button.Activated:Connect(function()
				onPick(key)
			end)
		end
	end
	refs.List.CanvasSize = UDim2.fromOffset(0, #entries * (m.Row + 8) + 16)
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
-- The journal wears the Pop look (attribute PopSkin: never the LightSkin
-- recolouring). While the light UI is on it also hides Roblox's touch
-- controls while it is open.
local popBuild = StoryView.build
StoryView.build = function(compact: boolean): Refs
	local refs = popBuild(compact)
	if UIConfig.lightUI() then
		TouchControls.follow(refs.Gui)
	end
	return refs
end

return StoryView
