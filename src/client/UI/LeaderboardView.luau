--[[
	The leaderboards on screen (pure builder + pure helpers;
	LeaderboardController fills them in). Two places:

	  board  a SurfaceGui on each lobby board (Board1..Board4, tag
	         Leaderboard), Adornee = the board, parented to PlayerGui: the
	         title (the hall's own title strip covers it; it shows when a
	         board has none), the top LeaderboardConfig.BoardRows rows (rank
	         medal, name, value) and YOUR line at the bottom (your live
	         value; your rank "#4" when you are in the top
	         LeaderboardConfig.TopCount that was read, "~#4" when your live
	         value would place you there before your next write lands,
	         else "#11+")
	  panel  the side menu's HALL OF FAME panel (a MenuPanel): a tab per board
	         (LB / RB on a gamepad), the top LeaderboardConfig.TopCount and
	         YOUR line

	Both use one canvas builder; LeaderboardView.lines turns the server's
	Leaderboards payload into the texts (tested in Lune). Values go through
	LeaderboardConfig.format ("+$1.3K/s", "$4.5M", "1,234", "12.5 h").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
local MenuPanel = require(script.Parent.MenuPanel)

local LeaderboardView = {}

export type RowData = { Rank: number, UserId: number, Name: string, Value: number }
export type BoardData = { Rows: { RowData }, Ready: boolean }
export type Own = { Value: number, Rank: number? }

export type Line = { Rank: string, Name: string, Value: string, Mine: boolean, Medal: number? }
export type Lines = { Rows: { Line }, OwnRank: string, OwnValue: string, Note: string? }

export type RowRefs = { Frame: Frame, Rank: TextLabel, Name: TextLabel, Value: TextLabel }
export type Canvas = {
	Root: Frame,
	Title: TextLabel,
	Rows: { RowRefs },
	Own: Frame,
	OwnRank: TextLabel,
	OwnLabel: TextLabel,
	OwnValue: TextLabel,
	Note: TextLabel,
	Board: LeaderboardConfig.Board,
	Width: number, -- the canvas width in pixels (texts are fitted to it)
	TextSize: number, -- the biggest text size
}

LeaderboardView.PixelsPerStud = 50
LeaderboardView.BoardStuds = 5.4 -- the hall's boards are 5.4 x 5 studs
LeaderboardView.MaxDistance = 140
LeaderboardView.Board = Color3.fromRGB(26, 40, 90) -- the hall's navy boards
LeaderboardView.Medals = {
	Color3.fromRGB(255, 206, 72), -- gold
	Color3.fromRGB(214, 222, 232), -- silver
	Color3.fromRGB(226, 140, 86), -- bronze
}
LeaderboardView.RowText = Color3.fromRGB(236, 242, 255)
LeaderboardView.MineColor = Color3.fromRGB(255, 176, 64)
LeaderboardView.Empty = "—"
LeaderboardView.Short = {
	MoneyPerSec = "MONEY/S",
	TotalEarned = "EARNED",
	Artifacts = "ARTIFACTS",
	HoursPlayed = "HOURS",
} :: { [string]: string }

---------------------------------------------------------------- pure helpers

export type Payload = { Live: boolean, Boards: { [string]: BoardData }, Own: { [string]: Own } }

LeaderboardView.MaxName = 40
-- the boards rank this server's players (no DataStores: Studio, or a live
-- server whose stores can't be opened)
LeaderboardView.LocalNote = "This server only (no global data)"

local function finite(v: any): number?
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return nil
end

-- A checked copy of the server's Leaderboards payload (nil when it is junk):
-- known boards only, at most TopCount rows of finite numbers, short names.
function LeaderboardView.sanitize(raw: any): Payload?
	if type(raw) ~= "table" or type(raw.Boards) ~= "table" then
		return nil
	end
	local boards: { [string]: BoardData } = {}
	local own: { [string]: Own } = {}
	for _, board in LeaderboardConfig.Boards do
		local data = raw.Boards[board.Id]
		if type(data) == "table" then
			local rows: { RowData } = {}
			if type(data.Rows) == "table" then
				for _, row in data.Rows do
					if #rows >= LeaderboardConfig.TopCount then
						break
					end
					local value = if type(row) == "table" then finite(row.Value) else nil
					local userId = if type(row) == "table" then finite(row.UserId) else nil
					if value and userId then
						local name = if type(row.Name) == "string" then string.sub(row.Name, 1, LeaderboardView.MaxName) else ""
						table.insert(rows, { Rank = finite(row.Rank) or #rows + 1, UserId = userId, Name = name, Value = value })
					end
				end
			end
			boards[board.Id] = { Rows = rows, Ready = data.Ready ~= false }
		end
		local mine = if type(raw.Own) == "table" then raw.Own[board.Id] else nil
		if type(mine) == "table" then
			own[board.Id] = { Value = finite(mine.Value) or 0, Rank = finite(mine.Rank) }
		end
	end
	return { Live = raw.Live ~= false, Boards = boards, Own = own }
end

-- Your rank when you aren't in the rows that were read but your live value
-- would place you there (scores are written every 120 s and read every
-- 60 s, so a value that just passed #10 isn't on the board yet): 1 + the
-- rows (not yours) worth more than your value as the board stores it. nil
-- past the rows read (all TopCount of them full) or without a value.
function LeaderboardView.estimateRank(boardId: string, rows: { RowData }, value: number, myUserId: number): number?
	local mine = LeaderboardConfig.decode(boardId, LeaderboardConfig.encode(boardId, value))
	if mine <= 0 then
		return nil
	end
	local above = 0
	for _, row in rows do
		if type(row) == "table" and row.UserId ~= myUserId and type(row.Value) == "number" then
			if row.Value > mine then
				above += 1
			end
		end
	end
	-- (below every row of a full page: somewhere past it)
	local rank = above + 1
	return if rank <= LeaderboardConfig.TopCount then rank else nil
end

-- The texts for one board: `rowCount` rows (empty places as "—"), your rank
-- and value. `live` false = the rows rank this server only (no DataStores).
function LeaderboardView.lines(boardId: string, data: BoardData?, own: Own?, myUserId: number, rowCount: number, live: boolean): Lines
	local rows: { Line } = {}
	local list = if data and type(data.Rows) == "table" then data.Rows else {}
	for i = 1, rowCount do
		local row = list[i]
		if type(row) == "table" and type(row.Value) == "number" then
			local rank = if type(row.Rank) == "number" then row.Rank else i
			table.insert(rows, {
				Rank = tostring(rank),
				Name = if type(row.Name) == "string" and row.Name ~= "" then row.Name else "Miner",
				Value = LeaderboardConfig.format(boardId, row.Value),
				Mine = row.UserId == myUserId,
				Medal = if rank <= 3 then rank else nil,
			})
		else
			table.insert(rows, { Rank = tostring(i), Name = LeaderboardView.Empty, Value = "", Mine = false, Medal = nil })
		end
	end
	local value = if own and type(own.Value) == "number" then own.Value else 0
	local ownRank: string
	local estimate = if value > 0 and data and data.Ready ~= false then LeaderboardView.estimateRank(boardId, list, value, myUserId) else nil
	if own and type(own.Rank) == "number" then
		ownRank = "#" .. tostring(own.Rank)
	elseif estimate then
		-- your live value already places you here (the board catches up after your next write)
		ownRank = `~#{estimate}`
	elseif value > 0 then
		-- below the rows that were read: rank TopCount + 1 or worse
		ownRank = `#{LeaderboardConfig.TopCount + 1}+`
	else
		ownRank = LeaderboardView.Empty
	end
	local note: string? = nil
	if not live then
		note = LeaderboardView.LocalNote
	elseif data and data.Ready == false then
		note = "Loading..."
	end
	return { Rows = rows, OwnRank = ownRank, OwnValue = LeaderboardConfig.format(boardId, value), Note = note }
end

-- Columns of a row (scale of the row's width): rank, name, value (right-aligned).
LeaderboardView.Columns = { Rank = { 0, 0.12 }, Name = { 0.13, 0.49 }, Value = { 0.63, 0.35 } }
LeaderboardView.MinText = 11
LeaderboardView.NameFloor = 0.8 -- a long name shrinks the rows' text to this share at most

-- A generous guess of a text's width in em (rounded fonts; never smaller
-- than the real text, so a fitted text never spills).
function LeaderboardView.textWidth(text: string): number
	local w = 0
	for _, code in utf8.codes(text) do
		if code == 32 then
			w += 0.3
		elseif code >= 65 and code <= 90 then
			w += 0.66 -- capitals
		elseif (code >= 48 and code <= 57) or code == 36 or code == 43 then
			w += 0.6 -- digits, $ and +
		elseif code == 46 or code == 44 or code == 39 or code == 58 then
			w += 0.3 -- . , ' :
		elseif code > 127 then
			w += 0.9
		else
			w += 0.56
		end
	end
	return w
end

-- The biggest text size (max .. min) at which `text` fits `width` pixels.
function LeaderboardView.fitSize(text: string, width: number, max: number, min: number): number
	local em = LeaderboardView.textWidth(text)
	if em <= 0 then
		return max
	end
	return math.clamp(math.floor(width / em), min, max)
end

---------------------------------------------------------------- builders

-- The board content inside `parent` (sized by scale, so it fits the board
-- part or a panel; `width` = its width in pixels, for fitting the texts).
-- `title` = room for a title band on top.
function LeaderboardView.canvas(
	parent: Instance,
	board: LeaderboardConfig.Board,
	rowCount: number,
	title: boolean,
	textSize: number,
	width: number
): Canvas
	local root = UIKit.new("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, parent)
	local top = if title then 0.21 else 0
	local ownH = if title then 0.15 else 0.12
	local bottom = 1 - ownH - 0.02
	local titleLabel = UIKit.label(root, board.Title, textSize + 4, {
		Name = "Title",
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.92, 0.16),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Text,
		TextWrapped = false,
		Visible = title,
	})
	local rows: { RowRefs } = {}
	local rowH = (bottom - top) / rowCount
	for i = 1, rowCount do
		local frame = UIKit.new("Frame", {
			Name = "Row" .. i,
			Position = UDim2.fromScale(0.03, top + (i - 1) * rowH),
			Size = UDim2.new(0.94, 0, rowH, -2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = if i % 2 == 1 then 0.93 else 1,
			BorderSizePixel = 0,
		}, root)
		UIKit.corner(frame, 6)
		local cols = LeaderboardView.Columns
		local rank = UIKit.label(frame, tostring(i), textSize, {
			Name = "Rank",
			Position = UDim2.fromScale(cols.Rank[1], 0),
			Size = UDim2.fromScale(cols.Rank[2], 1),
			FontFace = Theme.TitleFont,
			TextColor3 = LeaderboardView.RowText,
			TextWrapped = false,
		})
		local name = UIKit.label(frame, LeaderboardView.Empty, textSize, {
			Name = "PlayerName",
			Position = UDim2.fromScale(cols.Name[1], 0),
			Size = UDim2.fromScale(cols.Name[2], 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = LeaderboardView.RowText,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local value = UIKit.label(frame, "", textSize, {
			Name = "Value",
			Position = UDim2.fromScale(cols.Value[1], 0),
			Size = UDim2.fromScale(cols.Value[2], 1),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.Coin,
			TextWrapped = false,
		})
		table.insert(rows, { Frame = frame, Rank = rank, Name = name, Value = value })
	end
	-- YOUR line
	local own = UIKit.new("Frame", {
		Name = "Own",
		Position = UDim2.fromScale(0.03, 1 - ownH - 0.01),
		Size = UDim2.fromScale(0.94, ownH),
		BackgroundColor3 = LeaderboardView.MineColor,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	}, root)
	UIKit.corner(own, 8)
	UIKit.stroke(own, 2, LeaderboardView.MineColor, 0.2)
	local ownRank = UIKit.label(own, LeaderboardView.Empty, textSize, {
		Name = "Rank",
		Size = UDim2.fromScale(0.22, 1),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Text,
		TextWrapped = false,
	})
	local ownLabel = UIKit.label(own, "YOU", textSize, {
		Name = "You",
		Position = UDim2.fromScale(0.23, 0),
		Size = UDim2.fromScale(0.3, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Text,
		TextWrapped = false,
	})
	local ownValue = UIKit.label(own, "", textSize, {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0),
		Size = UDim2.fromScale(0.46, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
	})
	-- a short note in the last row's place (Studio test / loading)
	local note = UIKit.label(root, "", math.max(12, textSize - 4), {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, top + (rowCount - 0.5) * rowH),
		Size = UDim2.fromScale(0.94, rowH),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		Visible = false,
	})
	return {
		Root = root,
		Title = titleLabel,
		Rows = rows,
		Own = own,
		OwnRank = ownRank,
		OwnLabel = ownLabel,
		OwnValue = ownValue,
		Note = note,
		Board = board,
		Width = width,
		TextSize = textSize,
	}
end

-- The one text size of a canvas's names and values: the biggest at which
-- every shown value fits its column (values are never cut) and every name
-- fits too, but a long name only pulls it down to NameFloor of the full
-- size (past that the name is cut off with "..."), so the rows stay even.
function LeaderboardView.rowTextSize(lines: Lines, rowCount: number, width: number, max: number): number
	local rowW = width * 0.94
	local cols = LeaderboardView.Columns
	local min = LeaderboardView.MinText
	local nameFloor = math.max(min, math.floor(max * LeaderboardView.NameFloor))
	local size = max
	for i = 1, rowCount do
		local line = lines.Rows[i]
		if line and not (lines.Note ~= nil and i == rowCount) then
			size = math.min(size, LeaderboardView.fitSize(line.Value, rowW * cols.Value[2], max, min))
			size = math.min(size, math.max(nameFloor, LeaderboardView.fitSize(line.Name, rowW * cols.Name[2], max, min)))
		end
	end
	return size
end

-- Shows the texts of LeaderboardView.lines on a canvas (one text size for
-- every row: rowTextSize).
function LeaderboardView.fill(canvas: Canvas, lines: Lines)
	local count = #canvas.Rows
	local rowW = canvas.Width * 0.94
	local max, min = canvas.TextSize, LeaderboardView.MinText
	local size = LeaderboardView.rowTextSize(lines, count, canvas.Width, max)
	for i, refs in canvas.Rows do
		local line = lines.Rows[i]
		refs.Name.TextSize = size
		refs.Value.TextSize = size
		if lines.Note ~= nil and i == count then
			-- the note takes the last row's place
			refs.Rank.Text = ""
			refs.Name.Text = ""
			refs.Value.Text = ""
			refs.Frame.BackgroundTransparency = 1
		elseif line then
			refs.Rank.Text = line.Rank
			refs.Name.Text = line.Name
			refs.Value.Text = line.Value
			local medal = if line.Medal then LeaderboardView.Medals[line.Medal] else nil
			refs.Rank.TextColor3 = medal or LeaderboardView.RowText
			refs.Name.TextColor3 = if line.Mine then LeaderboardView.MineColor else LeaderboardView.RowText
			refs.Frame.BackgroundColor3 = if line.Mine then LeaderboardView.MineColor else Color3.new(1, 1, 1)
			refs.Frame.BackgroundTransparency = if line.Mine then 0.7 elseif i % 2 == 1 then 0.93 else 1
		end
	end
	canvas.OwnRank.Text = lines.OwnRank
	canvas.OwnValue.Text = lines.OwnValue
	canvas.OwnRank.TextSize = LeaderboardView.fitSize(lines.OwnRank, rowW * 0.22, max, min)
	canvas.OwnValue.TextSize = LeaderboardView.fitSize(lines.OwnValue, rowW * 0.46, max, min)
	canvas.Note.Text = lines.Note or ""
	canvas.Note.TextSize = LeaderboardView.fitSize(lines.Note or "", rowW - 8, math.max(min, max - 4), min)
	canvas.Note.Visible = lines.Note ~= nil
end

-- The SurfaceGui for one lobby board (the controller sets Adornee and parents
-- it). `studs` = the board's width (its Front face), 5.4 in the hall.
function LeaderboardView.surface(board: LeaderboardConfig.Board, studs: number?): (SurfaceGui, Canvas)
	local gui = UIKit.new("SurfaceGui", {
		Name = "TerraForgeBoard" .. board.Index,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = LeaderboardView.PixelsPerStud,
		LightInfluence = 0,
		MaxDistance = LeaderboardView.MaxDistance,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local width = (studs or LeaderboardView.BoardStuds) * LeaderboardView.PixelsPerStud
	local canvas = LeaderboardView.canvas(gui, board, LeaderboardConfig.BoardRows, true, 20, width)
	return gui, canvas
end

---------------------------------------------------------------- the panel

export type Panel = {
	Frame: MenuPanel.Refs,
	Gui: ScreenGui,
	Tabs: { [string]: TextButton },
	TabBar: Frame,
	TabGlyphs: { ImageLabel },
	Sheet: Frame,
	Canvases: { [string]: Canvas },
	Tab: string,
	Compact: boolean,
}

LeaderboardView.PanelMetrics = {
	Normal = { Width = 600, Height = 640, TabBar = 60, TabHeight = 48, Text = 22, TabText = 18 },
	-- phones: at uiScale 0.62 a 72-unit tab is about 44 pt
	Compact = { Width = 760, Height = 640, TabBar = 82, TabHeight = 72, Text = 20, TabText = 20 },
}

function LeaderboardView.buildPanel(compact: boolean?): Panel
	local frame = MenuPanel.build("TerraForgeHallOfFame", "HALL OF FAME", "The best Forgekeepers of all servers. Updated every minute.", 16)
	local tabBar = UIKit.new("Frame", { Name = "TabBar", BackgroundTransparency = 1 }, frame.Body)
	local tabs: { [string]: TextButton } = {}
	for _, board in LeaderboardConfig.Boards do
		tabs[board.Id] = UIKit.button(tabBar, LeaderboardView.Short[board.Id] or board.Title, Theme.Accent, Theme.AccentDark, {
			Name = "Tab" .. board.Id,
			TextSize = 18,
		})
	end
	local glyphs: { ImageLabel } = {}
	for _, name in { "GlyphL", "GlyphR" } do
		table.insert(
			glyphs,
			UIKit.new("ImageLabel", {
				Name = name,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(30, 30),
				Visible = false,
				ZIndex = 4,
			}, tabBar)
		)
	end
	local sheet = UIKit.new("Frame", {
		Name = "Sheet",
		BackgroundColor3 = LeaderboardView.Board,
		BorderSizePixel = 0,
	}, frame.Body)
	UIKit.corner(sheet, 12)
	UIKit.stroke(sheet, 3)
	local canvases: { [string]: Canvas } = {}
	for _, board in LeaderboardConfig.Boards do
		local holder = UIKit.new("Frame", {
			Name = "Board" .. board.Id,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = board.Index == 1,
		}, sheet)
		canvases[board.Id] = LeaderboardView.canvas(holder, board, LeaderboardConfig.TopCount, false, 22, 560)
	end
	local panel: Panel = {
		Frame = frame,
		Gui = frame.Gui,
		Tabs = tabs,
		TabBar = tabBar,
		TabGlyphs = glyphs,
		Sheet = sheet,
		Canvases = canvases,
		Tab = LeaderboardConfig.Boards[1].Id,
		Compact = compact == true,
	}
	LeaderboardView.layoutPanel(panel, panel.Compact, math.huge, math.huge)
	LeaderboardView.setTab(panel, panel.Tab)
	return panel
end

function LeaderboardView.layoutPanel(panel: Panel, compact: boolean, maxWidth: number, maxHeight: number)
	panel.Compact = compact
	local m = if compact then LeaderboardView.PanelMetrics.Compact else LeaderboardView.PanelMetrics.Normal
	local body = MenuPanel.layout(panel.Frame, compact, m.Width, m.Height, maxWidth, maxHeight)
	panel.TabBar.Position = UDim2.fromOffset(0, 0)
	panel.TabBar.Size = UDim2.new(1, 0, 0, m.TabBar)
	local count = #LeaderboardConfig.Boards
	local inset = 22 -- room for the LB / RB glyphs at the ends
	local gap = 8
	local tabW = (body.X - inset * 2 - gap * (count - 1)) / count
	for _, board in LeaderboardConfig.Boards do
		local holder = MenuPanel.holderOf(panel.Tabs[board.Id])
		holder.Position = UDim2.fromOffset(inset + (board.Index - 1) * (tabW + gap), 6)
		holder.Size = UDim2.fromOffset(tabW, m.TabHeight)
		panel.Tabs[board.Id].TextSize = m.TabText
	end
	panel.TabGlyphs[1].Position = UDim2.new(0, 10, 0, 6 + m.TabHeight / 2 - 3)
	panel.TabGlyphs[2].Position = UDim2.new(1, -10, 0, 6 + m.TabHeight / 2 - 3)
	panel.Sheet.Position = UDim2.fromOffset(0, m.TabBar + 4)
	panel.Sheet.Size = UDim2.new(1, 0, 1, -(m.TabBar + 8))
	-- rows of the sheet: as big as the room allows (between 14 and the
	-- metric); fill() fits long names and values into their columns
	local rowH = (body.Y - m.TabBar - 12) * 0.86 / LeaderboardConfig.TopCount
	local size = math.clamp(math.floor(rowH * 0.62), 14, m.Text)
	for _, canvas in panel.Canvases do
		canvas.Width = body.X
		canvas.TextSize = size
		for _, row in canvas.Rows do
			row.Rank.TextSize = size
			row.Name.TextSize = size
			row.Value.TextSize = size
		end
		canvas.OwnRank.TextSize = size
		canvas.OwnLabel.TextSize = size
		canvas.OwnValue.TextSize = size
		canvas.Note.TextSize = math.max(12, size - 6)
	end
end

function LeaderboardView.setTab(panel: Panel, boardId: string)
	if not LeaderboardConfig.ById[boardId] then
		return
	end
	panel.Tab = boardId
	for id, button in panel.Tabs do
		local on = id == boardId
		MenuPanel.style(button, if on then Theme.Accent else Theme.PanelLight, if on then Theme.AccentDark else Theme.PanelDark)
		button.TextColor3 = if on then Theme.Text else Theme.TextDim
	end
	for id, canvas in panel.Canvases do
		local holder = canvas.Root.Parent :: Frame
		holder.Visible = id == boardId
	end
end

-- The next tab to the left (dir -1) or right (dir 1), wrapping around.
function LeaderboardView.nextTab(boardId: string, dir: number): string
	local board = LeaderboardConfig.ById[boardId]
	local count = #LeaderboardConfig.Boards
	local index = if board then board.Index else 1
	local nextIndex = (index - 1 + (if dir < 0 then -1 else 1)) % count + 1
	return LeaderboardConfig.ByIndex[nextIndex].Id
end

-- Every tappable thing (for the touch-size tests).
function LeaderboardView.touchTargets(panel: Panel): { GuiObject }
	local list: { GuiObject } = { MenuPanel.holderOf(panel.Frame.Close) }
	for _, board in LeaderboardConfig.Boards do
		table.insert(list, MenuPanel.holderOf(panel.Tabs[board.Id]))
	end
	return list
end

return LeaderboardView
