--[[
	CodexController: the ORE CODEX (CodexView) on the client.

	- Opens from the side menu's CODEX button (CodexController.open /
	  toggle). The ROCK SCANNER terminal went 2026-10-24 (owner: the
	  BACKPACKS shop took its place); a model tagged OreCodex would still
	  get the "Ore Codex" prompt (one ProximityPrompt on its PrimaryPart or
	  the part named Cabinet, added when it streams in; a tagged BasePart
	  gets it itself; E / gamepad Y like the other stalls).
	- The cards come from the State snapshot's Discovered record and update
	  live while it is open (only when what they show changes:
	  CodexView.fingerprint). Ores discovered that you haven't looked at
	  get a NEW badge; the side menu shows how many are waiting (unseen /
	  onUnseenChanged). What was looked at is saved (CodexSeen ->
	  CodexService, back as snapshot.CodexSeen), so a discovery right
	  before leaving still shows NEW next session. (A server without
	  snapshot.CodexSeen: the first snapshot of a session counts as seen.)
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local PromptConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.PromptConfig)
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
-- discovered ores the player has looked at, without a saved record (nil
-- until the first snapshot)
local seen: { [string]: boolean }? = nil
-- looked at here, not in the saved record yet (sent with CodexSeen)
local lookedAt: { [string]: boolean } = {}
-- discovered, not looked at: the NEW badges
local fresh: { [string]: boolean } = {}
local unseenListeners: { (number) -> () } = {}
local entriesNow: { CodexView.Entry } = {}
-- what the cards show now (CodexView.fingerprint): State pushes that
-- don't change it (coins...) don't redraw the codex
local shownPrint: string? = nil

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
	local saved = state.CodexSeen
	if type(saved) == "table" then
		-- the saved record: NEW = discovered, not saved as seen, not looked at here
		for oreId in lookedAt do
			if saved[oreId] == true then
				lookedAt[oreId] = nil
			end
		end
		local changed = false
		for oreId in fresh do
			if discovered[oreId] ~= true or saved[oreId] == true or lookedAt[oreId] then
				fresh[oreId] = nil
				changed = true
			end
		end
		for oreId, on in discovered do
			if type(oreId) == "string" and on == true and saved[oreId] ~= true and not lookedAt[oreId] and not fresh[oreId] then
				fresh[oreId] = true
				changed = true
			end
		end
		if changed then
			notifyUnseen()
		end
		if isOpen and CodexView.fingerprint(discovered, fresh) ~= shownPrint then
			CodexController.refresh()
		end
		return
	end
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
	if isOpen and CodexView.fingerprint(discovered, fresh) ~= shownPrint then
		CodexController.refresh()
	end
end

-- The NEW badges were looked at: they count as seen now, and the server
-- saves them (every one it hasn't confirmed yet, so a dropped request is
-- sent again next time).
local function markSeen()
	if next(fresh) == nil then
		return
	end
	local known = seen
	for oreId in fresh do
		lookedAt[oreId] = true
		if known then
			known[oreId] = true
		end
	end
	table.clear(fresh)
	notifyUnseen()
	local ids: { string } = {}
	for oreId in lookedAt do
		table.insert(ids, oreId)
	end
	Net.send("CodexSeen", ids)
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
	local discovered = if state then state.Discovered else nil
	shownPrint = CodexView.fingerprint(discovered, fresh)
	entriesNow = CodexView.entries(discovered, fresh)
	for _, entry in CodexView.secretEntries(discovered, fresh) do
		table.insert(entriesNow, entry)
	end
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
	if card and not card.Button.Visible then
		card = nil -- (the rarity filter hides it: the first card it shows instead)
	end
	local first = nil
	for _, shown in view.CardList do
		if shown.Button.Visible then
			first = shown
			break
		end
	end
	local pick = card or first
	GuiService.SelectedObject = if pick then pick.Button else view.Frame.Close
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
	-- the glyphs first: the gamepad footer's room is part of the layout
	updateGlyphs(view)
	fit(view)
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

-- Puts the prompt on `part` (once), and takes any other copy off the
-- terminal: one Ore Codex prompt per terminal.
local function addPrompt(part: BasePart, terminal: Instance)
	if part:FindFirstChild(CodexController.PromptName) then
		return
	end
	if terminal ~= part then
		for _, object in terminal:GetDescendants() do
			if object.Name == CodexController.PromptName and object:IsA("ProximityPrompt") then
				object:Destroy()
			end
		end
	end
	local prompt = PromptConfig.make({
		Name = CodexController.PromptName,
		ActionText = "Ore Codex",
		ObjectText = "Rock Scanner",
		Distance = CodexController.PromptDistance,
		Parent = part,
	})
	prompt.Triggered:Connect(function()
		CodexController.open()
	end)
end

-- terminal models -> the watch for their parts streaming in
local watched: { [Instance]: RBXScriptConnection } = {}

-- A tagged terminal streamed in: its prompt goes on its cabinet. With
-- StreamingEnabled the model can arrive before its cabinet, and its parts
-- can stream out and back in as new instances, so every part that arrives
-- gets checked again (the prompt is only added where it is missing).
local function attach(target: Instance)
	if target:IsA("BasePart") then
		addPrompt(target, target)
		return
	end
	local function try()
		local part = CodexView.promptPart(target)
		if part then
			addPrompt(part, target)
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
			local wasPad = view.Frame.PadMode
			updateGlyphs(view)
			if view.Frame.PadMode ~= wasPad then
				-- the gamepad footer came or went: its room changes the layout
				fit(view)
			end
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
