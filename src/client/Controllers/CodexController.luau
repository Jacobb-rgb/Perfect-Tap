--[[
	CodexController: the ORE CODEX (CodexView) on the client.

	- Opens from the "Ore Codex" prompt at the ROCK SCANNER terminal (a
	  ProximityPrompt this controller puts on every Model / BasePart tagged
	  OreCodex as it streams in; F / gamepad Y like the other stalls) or from
	  the side menu's CODEX button (CodexController.open / toggle).
	- The cards come from the State snapshot's Discovered record and update
	  live while it is open. Ores discovered since you last looked get a
	  NEW badge; the side menu shows how many are waiting (unseen /
	  onUnseenChanged). The first snapshot of a session counts as seen.
	- Click / tap a card, or move the gamepad selection onto it, to read it.
	- Closes with the X button, B (gamepad), Backspace, respawning or another
	  panel opening. Other prompts are hidden while it is open.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CodexView = require(script.Parent.Parent.UI.CodexView)
local MenuPanel = require(script.Parent.Parent.UI.MenuPanel)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local CodexController = {}

CodexController.Tag = "OreCodex"
CodexController.PromptName = "CodexPrompt"
CodexController.PromptDistance = 12

local NAME = "CodexController"
local CLOSE_ACTION = "TerraForgeCodexClose"
-- above the default player controls, so B / Backspace close the codex first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25

local player = Players.LocalPlayer
local refs: CodexView.Refs? = nil
local isOpen = false
local openedAt = 0
local tickConnection: RBXScriptConnection? = nil
-- discovered ores the player has looked at (nil until the first snapshot)
local seen: { [string]: boolean }? = nil
-- discovered since the last look: the NEW badges
local fresh: { [string]: boolean } = {}
local unseenListeners: { (number) -> () } = {}
local entriesNow: { CodexView.Entry } = {}

function CodexController.isOpen(): boolean
	return isOpen
end

-- How many ores were discovered since the codex was last looked at.
function CodexController.unseen(): number
	local n = 0
	for _ in fresh do
		n += 1
	end
	return n
end

function CodexController.onUnseenChanged(callback: (number) -> ())
	table.insert(unseenListeners, callback)
	task.spawn(callback, CodexController.unseen())
end

local function notifyUnseen()
	local n = CodexController.unseen()
	for _, callback in unseenListeners do
		task.spawn(callback, n)
	end
end

---------------------------------------------------------------- discovery

local function onState(state: { [string]: any })
	local discovered = if type(state.Discovered) == "table" then state.Discovered else {}
	local known = seen
	if not known then
		-- the first snapshot: everything already discovered counts as seen
		local first: { [string]: boolean } = {}
		for oreId, on in discovered do
			if type(oreId) == "string" and on == true then
				first[oreId] = true
			end
		end
		seen = first
	else
		local changed = false
		for oreId, on in discovered do
			if type(oreId) == "string" and on == true and not known[oreId] and not fresh[oreId] then
				fresh[oreId] = true
				changed = true
			end
		end
		if changed then
			notifyUnseen()
		end
	end
	if isOpen then
		CodexController.refresh()
	end
end

-- The NEW badges were looked at: they count as seen now.
local function markSeen()
	local known = seen
	if not known or next(fresh) == nil then
		return
	end
	for oreId in fresh do
		known[oreId] = true
	end
	table.clear(fresh)
	notifyUnseen()
end

---------------------------------------------------------------- view

local function entryFor(oreId: string?): CodexView.Entry?
	for _, entry in entriesNow do
		if entry.Ore.Id == oreId then
			return entry
		end
	end
	return nil
end

-- Redraws the cards from the latest snapshot (keeps the selected card).
function CodexController.refresh()
	local view = refs
	if not view then
		return
	end
	local state = StateController.get()
	entriesNow = CodexView.entries(if state then state.Discovered else nil, fresh)
	CodexView.setEntries(view, entriesNow)
	local current = entryFor(view.Selected)
	if not current then
		-- the first NEW ore, else the first discovered one, else the first card
		for _, entry in entriesNow do
			if entry.New then
				current = entry
				break
			end
		end
		if not current then
			for _, entry in entriesNow do
				if entry.Found then
					current = entry
					break
				end
			end
		end
		current = current or entriesNow[1]
	end
	if current then
		CodexView.select(view, current)
	end
end

local function fit(view: CodexView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = MenuPanel.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	CodexView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function updateGlyphs(view: CodexView.Refs)
	if MenuPanels.usingGamepad() then
		local image = MenuPanels.glyph(Enum.KeyCode.ButtonB)
		MenuPanel.setCloseGlyph(view.Frame, image)
		if image ~= "" then
			MenuPanel.setHint(view.Frame, "", { { Image = image, Word = "close" } })
		else
			MenuPanel.setHint(view.Frame, `Move to an ore to read it · {MenuPanels.padName(Enum.KeyCode.ButtonB)}: close`, nil)
		end
	else
		MenuPanel.setCloseGlyph(view.Frame, nil)
		MenuPanel.setHint(view.Frame, "Click an ore to read about it · Backspace: close", nil)
	end
end

local function selectDefault(view: CodexView.Refs)
	if not MenuPanels.usingGamepad() then
		return
	end
	local card = view.Selected and view.Cards[view.Selected]
	GuiService.SelectedObject = if card then card.Button else view.CardList[1].Button
end

local function ensureView(): CodexView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = CodexView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Frame.Close.Activated:Connect(function()
		CodexController.close()
		Sfx.play("UIClick")
	end)
	for _, card in view.CardList do
		card.Button.Activated:Connect(function()
			local entry = entryFor(card.OreId)
			if entry then
				CodexView.select(view, entry)
				Sfx.play("UIClick")
			end
		end)
	end
	-- the gamepad selection reads the card it lands on
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		if not isOpen or not selected or not selected:IsDescendantOf(view.Grid) then
			return
		end
		local oreId = selected:GetAttribute("Ore")
		local entry = if type(oreId) == "string" then entryFor(oreId) else nil
		if entry and view.Selected ~= oreId then
			CodexView.select(view, entry)
		end
	end)
	refs = view
	return view
end

---------------------------------------------------------------- open / close

function CodexController.close()
	if not isOpen then
		return
	end
	isOpen = false
	markSeen()
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Codex", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	CodexController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

-- Closes when another panel opens or the character is gone.
local function watch()
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		if os.clock() - openedAt > 0.3 and MenuPanels.otherOpen(NAME) then
			CodexController.close()
		end
	end)
end

function CodexController.open()
	if isOpen then
		CodexController.refresh()
		return
	end
	MenuPanels.closeOthers(NAME)
	local view = ensureView()
	isOpen = true
	openedAt = os.clock()
	view.Selected = nil
	fit(view)
	updateGlyphs(view)
	CodexController.refresh()
	view.Gui.Enabled = true
	PromptController.setSuppressed("Codex", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watch()
	GuiService.SelectedObject = nil
	selectDefault(view)
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

function CodexController.toggle()
	if isOpen then
		CodexController.close()
	else
		CodexController.open()
	end
end

---------------------------------------------------------------- the terminal prompt

local function promptPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		local primary = target.PrimaryPart
		if primary then
			return primary
		end
		local cabinet = target:FindFirstChild("Cabinet", true)
		if cabinet and cabinet:IsA("BasePart") then
			return cabinet
		end
		return target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function addPrompt(part: BasePart)
	if part:FindFirstChild(CodexController.PromptName) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CodexController.PromptName
	prompt.ActionText = "Ore Codex"
	prompt.ObjectText = "Rock Scanner"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CodexController.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		CodexController.open()
	end)
end

-- terminal models -> the watch for their parts streaming in
local watched: { [Instance]: RBXScriptConnection } = {}

-- A tagged terminal streamed in: its prompt goes on its cabinet. With
-- StreamingEnabled the model can stay while its parts stream out and back
-- in as new instances, so every part that arrives gets checked again (the
-- prompt is only added where it is missing).
local function attach(target: Instance)
	if target:IsA("BasePart") then
		addPrompt(target)
		return
	end
	local function try()
		local part = promptPart(target)
		if part then
			addPrompt(part)
		end
	end
	try()
	if not watched[target] then
		watched[target] = target.DescendantAdded:Connect(function(added: Instance)
			if added:IsA("BasePart") then
				task.defer(try)
			end
		end)
	end
end

local function detach(target: Instance)
	local connection = watched[target]
	if connection then
		connection:Disconnect()
		watched[target] = nil
	end
end

---------------------------------------------------------------- lifecycle

function CodexController.init()
	StateController.onChanged(onState)
	player.CharacterRemoving:Connect(function()
		CodexController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and isOpen then
			updateGlyphs(view)
			if MenuPanels.usingGamepad() then
				local selected = GuiService.SelectedObject
				if not selected or not selected:IsDescendantOf(view.Gui) then
					selectDefault(view)
				end
			end
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and isOpen then
				fit(view)
			end
		end)
	end
end

function CodexController.start()
	CollectionService:GetInstanceAddedSignal(CodexController.Tag):Connect(attach)
	CollectionService:GetInstanceRemovedSignal(CodexController.Tag):Connect(detach)
	for _, target in CollectionService:GetTagged(CodexController.Tag) do
		attach(target)
	end
end

return CodexController
