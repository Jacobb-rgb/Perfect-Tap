--[[
	LeaderboardController: the four lobby leaderboards and the side menu's
	HALL OF FAME panel (LeaderboardView) on the client.

	- The server sends Leaderboards { Live, Boards, Own } every
	  LeaderboardConfig.RefreshSeconds and when you join (LeaderboardService).
	- Every BasePart tagged Leaderboard with a Board attribute (1..4) gets a
	  SurfaceGui in PlayerGui (Adornee = the board) as it streams in: the top
	  LeaderboardConfig.BoardRows and YOUR line (your rank inside the top
	  LeaderboardConfig.TopCount, your live value). The board's "Placeholder"
	  table (built by the lobby) is removed on this client when the real one
	  shows. A board that streams out loses its gui; it comes back with it.
	- The panel (LeaderboardController.open / toggle, the side menu's BOARDS
	  button): a tab per board, the top TopCount and YOUR line. Tabs: click /
	  tap, or LB / RB on a gamepad. Closes with the X button, B, Backspace,
	  respawning, another panel opening or the HUD hiding
	  (SideMenuController). Other prompts are hidden while it is open.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local Net = require(Shared.Net)
local LeaderboardView = require(script.Parent.Parent.UI.LeaderboardView)
local MenuPanel = require(script.Parent.Parent.UI.MenuPanel)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)

local LeaderboardController = {}

export type Payload = LeaderboardView.Payload

type Shown = { Gui: SurfaceGui, Canvas: LeaderboardView.Canvas, Board: LeaderboardConfig.Board, Watch: RBXScriptConnection }

local NAME = "LeaderboardController"
local CLOSE_ACTION = "TerraForgeBoardsClose"
local TAB_ACTION = "TerraForgeBoardsTab"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25

local player = Players.LocalPlayer
local payload: Payload? = nil
local shown: { [BasePart]: Shown } = {}
local panel: LeaderboardView.Panel? = nil
local isOpen = false
local openedAt = 0
local tickConnection: RBXScriptConnection? = nil

function LeaderboardController.isOpen(): boolean
	return isOpen
end

function LeaderboardController.data(): Payload?
	return payload
end

---------------------------------------------------------------- the payload

local LOADING: LeaderboardView.BoardData = { Rows = {}, Ready = false }

local function linesFor(boardId: string, rowCount: number): LeaderboardView.Lines
	local p = payload
	local data = if p then p.Boards[boardId] or LOADING else LOADING
	local own = if p then p.Own[boardId] else nil
	return LeaderboardView.lines(boardId, data, own, player.UserId, rowCount, if p then p.Live else true)
end

---------------------------------------------------------------- the lobby boards

local function fillBoard(entry: Shown)
	LeaderboardView.fill(entry.Canvas, linesFor(entry.Board.Id, LeaderboardConfig.BoardRows))
end

local function removePlaceholder(part: Instance)
	local placeholder = part:FindFirstChild("Placeholder")
	if placeholder then
		placeholder:Destroy()
	end
end

local function attach(target: Instance)
	if not target:IsA("BasePart") or shown[target] then
		return
	end
	local index = target:GetAttribute("Board")
	local board = if type(index) == "number" then LeaderboardConfig.ByIndex[index] else nil
	if not board then
		return
	end
	local gui, canvas = LeaderboardView.surface(board, target.Size.X)
	gui.Adornee = target
	gui.Parent = player:WaitForChild("PlayerGui")
	removePlaceholder(target)
	-- the placeholder may stream in after the board itself
	local watch = target.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Placeholder" then
			task.defer(removePlaceholder, target)
		end
	end)
	local entry: Shown = { Gui = gui, Canvas = canvas, Board = board, Watch = watch }
	shown[target] = entry
	fillBoard(entry)
end

local function detach(target: Instance)
	if not target:IsA("BasePart") then
		return
	end
	local entry = shown[target]
	if entry then
		shown[target] = nil
		entry.Watch:Disconnect()
		entry.Gui:Destroy()
	end
end

---------------------------------------------------------------- the panel

local function fillPanel()
	local view = panel
	if not view then
		return
	end
	for id, canvas in view.Canvases do
		LeaderboardView.fill(canvas, linesFor(id, LeaderboardConfig.TopCount))
	end
end

local function fit(view: LeaderboardView.Panel)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = MenuPanel.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	LeaderboardView.layoutPanel(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function updateGlyphs(view: LeaderboardView.Panel)
	local gamepad = MenuPanels.usingGamepad()
	for i, image in view.TabGlyphs do
		image.Visible = gamepad
		if gamepad then
			image.Image = MenuPanels.glyph(if i == 1 then Enum.KeyCode.ButtonL1 else Enum.KeyCode.ButtonR1)
		end
	end
	if gamepad then
		local b = MenuPanels.glyph(Enum.KeyCode.ButtonB)
		local l = MenuPanels.glyph(Enum.KeyCode.ButtonL1)
		local r = MenuPanels.glyph(Enum.KeyCode.ButtonR1)
		MenuPanel.setCloseGlyph(view.Frame, b)
		if b ~= "" and l ~= "" and r ~= "" then
			MenuPanel.setHint(view.Frame, "", { { Image = l, Word = "" }, { Image = r, Word = "board" }, { Image = b, Word = "close" } })
		else
			local lName = MenuPanels.padName(Enum.KeyCode.ButtonL1)
			local rName = MenuPanels.padName(Enum.KeyCode.ButtonR1)
			local bName = MenuPanels.padName(Enum.KeyCode.ButtonB)
			MenuPanel.setHint(view.Frame, `{lName} / {rName}: board · {bName}: close`, nil)
		end
	else
		MenuPanel.setCloseGlyph(view.Frame, nil)
		MenuPanel.setHint(view.Frame, "Click a tab to see a board · Backspace: close", nil)
	end
end

local function switchTab(boardId: string, moveSelection: boolean)
	local view = panel
	if not view or view.Tab == boardId then
		return
	end
	LeaderboardView.setTab(view, boardId)
	Sfx.play("UIClick")
	if moveSelection and MenuPanels.usingGamepad() then
		GuiService.SelectedObject = view.Tabs[boardId]
	end
end

local function ensurePanel(): LeaderboardView.Panel
	local existing = panel
	if existing then
		return existing
	end
	local view = LeaderboardView.buildPanel(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Frame.Close.Activated:Connect(function()
		LeaderboardController.close()
		Sfx.play("UIClick")
	end)
	for id, button in view.Tabs do
		button.Activated:Connect(function()
			switchTab(id, false)
		end)
	end
	panel = view
	return view
end

function LeaderboardController.close()
	if not isOpen then
		return
	end
	isOpen = false
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(TAB_ACTION)
	local view = panel
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Boards", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	LeaderboardController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function onTab(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local view = panel
	if state ~= Enum.UserInputState.Begin or not isOpen or not view then
		return Enum.ContextActionResult.Pass
	end
	local dir = if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
	switchTab(LeaderboardView.nextTab(view.Tab, dir), true)
	return Enum.ContextActionResult.Sink
end

function LeaderboardController.open(boardId: string?)
	local view = ensurePanel()
	if type(boardId) == "string" and LeaderboardConfig.ById[boardId] then
		LeaderboardView.setTab(view, boardId)
	end
	if isOpen then
		fillPanel()
		return
	end
	MenuPanels.closeOthers(NAME)
	isOpen = true
	openedAt = os.clock()
	-- the glyphs first: the gamepad footer's room is part of the layout
	updateGlyphs(view)
	fit(view)
	fillPanel()
	view.Gui.Enabled = true
	PromptController.setSuppressed("Boards", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(TAB_ACTION, onTab, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		if os.clock() - openedAt > 0.3 and MenuPanels.otherOpen(NAME) then
			LeaderboardController.close()
		end
	end)
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then view.Tabs[view.Tab] else nil
	Sfx.play("UIClick")
	local scale = view.Frame.Panel:FindFirstChild("OpenPop") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = view.Frame.Panel
		scale = made
	end
	local s = scale :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function LeaderboardController.toggle()
	if isOpen then
		LeaderboardController.close()
	else
		LeaderboardController.open()
	end
end

---------------------------------------------------------------- lifecycle

function LeaderboardController.init()
	Net.listen("Leaderboards", function(raw)
		local clean = LeaderboardView.sanitize(raw)
		if not clean then
			return
		end
		payload = clean
		for _, entry in shown do
			fillBoard(entry)
		end
		if isOpen then
			fillPanel()
		end
	end)
	player.CharacterRemoving:Connect(function()
		LeaderboardController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = panel
		if view and isOpen then
			local wasPad = view.Frame.PadMode
			updateGlyphs(view)
			if view.Frame.PadMode ~= wasPad then
				-- the gamepad footer came or went: its room changes the layout
				fit(view)
			end
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = panel
			if view and isOpen then
				fit(view)
			end
		end)
	end
end

function LeaderboardController.start()
	CollectionService:GetInstanceAddedSignal(LeaderboardConfig.Tag):Connect(attach)
	CollectionService:GetInstanceRemovedSignal(LeaderboardConfig.Tag):Connect(detach)
	for _, target in CollectionService:GetTagged(LeaderboardConfig.Tag) do
		attach(target)
	end
end

return LeaderboardController
