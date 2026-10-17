--[[
	SettingsController: the SETTINGS panel (SettingsView) and applying the
	player's settings (SettingsConfig) on this client.

	- The saved record arrives once in the State snapshot (snapshot.Settings,
	  the first snapshot of the session); after that this client is the one
	  that changes it, so later snapshots don't move the sliders back.
	- A change applies at once and is sent to the server (SettingsSave)
	  SettingsConfig.SaveDelay seconds after the last change (a drag sends one
	  request), or right away when the panel closes.
	- Applying (simple hooks, each skipped when its target doesn't exist):
	    Music  -> the SoundService SoundGroup SettingsConfig.MusicGroup
	              ("TerraForgeMusic", created here: music tracks play through it)
	    Sfx    -> the SoundGroup SettingsConfig.SfxGroup ("TerraForgeSfx", made by
	              Effects/Sfx on the first sound; applied when it appears)
	    Shake  -> Effects/CameraShake.setEnabled
	    Rumble -> MiningController.setRumble
	  Other code can read SettingsController.get() and listen with onChanged.
	- Opens from the side menu (SettingsController.open / toggle); closes with
	  the X button, B (gamepad), Backspace, respawning or another panel
	  opening. Mouse / touch: click or drag a bar, or the - / + buttons;
	  gamepad: the - / + buttons and the toggles (GuiService selection).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.SettingsConfig)
local Net = require(Shared.Net)
local SettingsView = require(script.Parent.Parent.UI.SettingsView)
local MenuPanel = require(script.Parent.Parent.UI.MenuPanel)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)

local SettingsController = {}

local NAME = "SettingsController"
local CLOSE_ACTION = "TerraForgeSettingsClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25

local player = Players.LocalPlayer
local current: SettingsConfig.Settings = SettingsConfig.sanitize(nil)
local adopted = false -- the saved record from the first snapshot was taken
local dirty = false -- changed here, not sent yet
local saveToken = 0
local listeners: { (SettingsConfig.Settings) -> () } = {}
local refs: SettingsView.Refs? = nil
local isOpen = false
local openedAt = 0
local tickConnection: RBXScriptConnection? = nil
local dragging: { Row: SettingsView.VolumeRow, Input: InputObject }? = nil

function SettingsController.isOpen(): boolean
	return isOpen
end

-- A copy of the settings in use.
function SettingsController.get(): SettingsConfig.Settings
	return table.clone(current)
end

function SettingsController.onChanged(callback: (SettingsConfig.Settings) -> ())
	table.insert(listeners, callback)
	task.spawn(callback, table.clone(current))
end

---------------------------------------------------------------- applying

local function musicGroup(): SoundGroup
	local existing = SoundService:FindFirstChild(SettingsConfig.MusicGroup)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = SettingsConfig.MusicGroup
	group.Volume = current.Music
	group.Parent = SoundService
	return group
end

local function applySfx(group: Instance)
	if group.Name == SettingsConfig.SfxGroup and group:IsA("SoundGroup") then
		group.Volume = current.Sfx
	end
end

local function apply()
	musicGroup().Volume = current.Music
	for _, child in SoundService:GetChildren() do
		applySfx(child)
	end
	CameraShake.setEnabled(current.Shake)
	MenuPanels.call("MiningController", "setRumble", current.Rumble)
	for _, callback in listeners do
		task.spawn(callback, table.clone(current))
	end
end

local function send()
	if not dirty then
		return
	end
	dirty = false
	Net.send("SettingsSave", table.clone(current))
end

-- A new value from the panel: applied now, sent a moment after the last change.
function SettingsController.set(id: string, value: any)
	local raw = table.clone(current) :: { [string]: any }
	raw[id] = value
	local clean = SettingsConfig.sanitize(raw)
	if SettingsConfig.equal(clean, current) then
		return
	end
	current = clean
	-- a change before the snapshot arrived wins over the saved record
	adopted = true
	dirty = true
	apply()
	local view = refs
	if view then
		SettingsView.set(view, current)
	end
	saveToken += 1
	local token = saveToken
	task.delay(SettingsConfig.SaveDelay, function()
		if token == saveToken then
			send()
		end
	end)
end

local function onState(state: { [string]: any })
	if adopted or type(state.Settings) ~= "table" then
		return
	end
	adopted = true
	current = SettingsConfig.sanitize(state.Settings)
	apply()
	local view = refs
	if view then
		SettingsView.set(view, current)
	end
end

---------------------------------------------------------------- the panel

local function fit(view: SettingsView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = MenuPanel.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	SettingsView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function updateGlyphs(view: SettingsView.Refs)
	if MenuPanels.usingGamepad() then
		local a = MenuPanels.glyph(Enum.KeyCode.ButtonA)
		local b = MenuPanels.glyph(Enum.KeyCode.ButtonB)
		MenuPanel.setCloseGlyph(view.Frame, b)
		if a ~= "" and b ~= "" then
			MenuPanel.setHint(view.Frame, "", { { Image = a, Word = "change" }, { Image = b, Word = "close" } })
		else
			local names = `{MenuPanels.padName(Enum.KeyCode.ButtonA)}: change · {MenuPanels.padName(Enum.KeyCode.ButtonB)}: close`
			MenuPanel.setHint(view.Frame, names, nil)
		end
	else
		MenuPanel.setCloseGlyph(view.Frame, nil)
		MenuPanel.setHint(view.Frame, "Drag a bar or use - and + · Backspace: close", nil)
	end
end

local function step(id: string, dir: number)
	local value = (current :: { [string]: any })[id]
	if type(value) == "number" then
		SettingsController.set(id, SettingsConfig.stepVolume(value, dir))
		Sfx.play("UIClick")
	end
end

local function dragTo(row: SettingsView.VolumeRow, x: number)
	local bar = row.Track
	SettingsController.set(row.Id, SettingsView.fraction(x, bar.AbsolutePosition.X, bar.AbsoluteSize.X))
end

local function ensureView(): SettingsView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = SettingsView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Frame.Close.Activated:Connect(function()
		SettingsController.close()
		Sfx.play("UIClick")
	end)
	for id, row in view.Volumes do
		row.Minus.Activated:Connect(function()
			step(id, -1)
		end)
		row.Plus.Activated:Connect(function()
			step(id, 1)
		end)
		row.Track.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				dragging = { Row = row, Input = input }
				dragTo(row, input.Position.X)
			end
		end)
	end
	for id, row in view.Toggles do
		row.Button.Activated:Connect(function()
			SettingsController.set(id, not ((current :: { [string]: any })[id] == true))
			Sfx.play("UIClick")
		end)
	end
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local drag = dragging
		if not drag or not isOpen then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or (kind == Enum.UserInputType.Touch and input == drag.Input) then
			dragTo(drag.Row, input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local drag = dragging
		if not drag then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or input == drag.Input then
			dragging = nil
		end
	end)
	refs = view
	SettingsView.set(view, current)
	return view
end

function SettingsController.close()
	if not isOpen then
		return
	end
	isOpen = false
	dragging = nil
	send()
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
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	SettingsController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

function SettingsController.open()
	if isOpen then
		return
	end
	MenuPanels.closeOthers(NAME)
	local view = ensureView()
	isOpen = true
	openedAt = os.clock()
	fit(view)
	updateGlyphs(view)
	SettingsView.set(view, current)
	view.Gui.Enabled = true
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		if os.clock() - openedAt > 0.3 and MenuPanels.otherOpen(NAME) then
			SettingsController.close()
		end
	end)
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then SettingsView.firstButton(view) else nil
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

function SettingsController.toggle()
	if isOpen then
		SettingsController.close()
	else
		SettingsController.open()
	end
end

---------------------------------------------------------------- lifecycle

function SettingsController.init()
	SoundService.ChildAdded:Connect(applySfx)
	StateController.onChanged(onState)
	player.CharacterRemoving:Connect(function()
		SettingsController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and isOpen then
			updateGlyphs(view)
			local selected = GuiService.SelectedObject
			if MenuPanels.usingGamepad() and (not selected or not selected:IsDescendantOf(view.Gui)) then
				GuiService.SelectedObject = SettingsView.firstButton(view)
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

function SettingsController.start()
	apply()
	-- a last save when the player leaves with an unsent change
	Players.PlayerRemoving:Connect(function(leaving: Player)
		if leaving == player then
			send()
		end
	end)
end

return SettingsController
