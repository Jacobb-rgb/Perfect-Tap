--[[
	BackpackController: the backpack inventory window (UI/BackpackView;
	owner 2026-10-24: everything you pick up goes into the backpack, a
	backpack icon next to the Blaster slot opens it; docs/plans/
	OWNER_PLAYTEST_1024.md "4 + 5").

	Opening it
	  PC        the HUD's backpack button (right of the blaster's hotbar
	            slot) or the Q key (BackpackController.Key: free since the
	            throw went; I would also zoom Roblox's camera, which binds I / O)
	  Touch     the backpack button
	  Gamepad   R1 (BackpackController.PadKey: free since the throw went),
	            or A on the backpack button while the selection is on it
	The button's corner names the key for the input in use (Q, the
	platform's R1 glyph, nothing on touch). The window is a panel
	(MenuPanels: it closes the others when it opens and closes when another
	opens); the X, B, Backspace and the open key again close it. A gamepad
	gets the first row selected (the list scrolls with the selection); the
	window is a SelectionGroup. While open it follows the backpack live
	(Util/BackpackState: CarryCount / CarryCapacity and every State push).

	Never in a close-up (cleaning, build mode, the vault, any Scriptable
	camera or claimed PlayerControls): the keys pass there (the cleaning
	minigame takes B / Backspace) and the HUD button is hidden anyway.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BackpackView = require(script.Parent.Parent.UI.BackpackView)
local HudView = require(script.Parent.Parent.UI.HudView)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local BackpackState = require(script.Parent.Parent.Util.BackpackState)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudController = require(script.Parent.HudController)
local CleaningController = require(script.Parent.CleaningController)

local BackpackController = {}

BackpackController.Key = Enum.KeyCode.Q
BackpackController.PadKey = Enum.KeyCode.ButtonR1

local NAME = "BackpackController"
local KEY_ACTION = "TerraForgeBackpack"
local CLOSE_ACTION = "TerraForgeBackpackClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10

local refs: BackpackView.Refs? = nil
local isOpen = false

function BackpackController.isOpen(): boolean
	return isOpen
end

-- A close-up now? (a Scriptable camera, claimed controls: build mode, the vault; the cleaning minigame)
local function inCloseUp(): boolean
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		return true
	end
	return PlayerControls.owner() ~= nil or CleaningController.isActive()
end

-- The window's footer line for the input in use.
function BackpackController.hintText(input: string, keyName: string?, closeName: string?): string
	if input == "Gamepad" then
		return `{closeName or "B"}: close`
	elseif input == "Touch" then
		return "Tap X to close."
	end
	return `{keyName or "Q"} or Backspace: close`
end

local function inputKind(): string
	if MenuPanels.usingGamepad() then
		return "Gamepad"
	elseif MenuPanels.isTouch() then
		return "Touch"
	end
	return "Mouse"
end

-- The HUD button's key hint: Q on a keyboard, R1's glyph on a gamepad, nothing on touch.
local function refreshKeyHint()
	local hud = HudController.refs()
	if not hud then
		return
	end
	local kind = inputKind()
	if kind == "Gamepad" then
		local glyph = MenuPanels.glyph(BackpackController.PadKey)
		HudView.setBackpackKey(hud, MenuPanels.padName(BackpackController.PadKey), if glyph ~= "" then glyph else nil)
	elseif kind == "Touch" then
		HudView.setBackpackKey(hud, nil, nil)
	else
		HudView.setBackpackKey(hud, UserInputService:GetStringForKeyCode(BackpackController.Key), nil)
	end
end

local function fit(view: BackpackView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = BackpackView.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	BackpackView.layout(view, size.X / scale, (size.Y - inset.Y) / scale, compact)
end

-- A gamepad selection on a row that went away goes to the first row (or the X).
local function keepSelection(view: BackpackView.Refs)
	if not MenuPanels.usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) and selected.Parent ~= nil then
		return
	end
	local first = BackpackView.firstRow(view)
	GuiService.SelectedObject = if first then first.Frame else view.Close
end

local function refresh()
	local view = refs
	if not view or not isOpen then
		return
	end
	BackpackView.setBackpack(view, BackpackState.get())
	keepSelection(view)
end

local function updateHint(view: BackpackView.Refs)
	local closeName = MenuPanels.padName(Enum.KeyCode.ButtonB)
	BackpackView.setHint(
		view,
		BackpackController.hintText(inputKind(), UserInputService:GetStringForKeyCode(BackpackController.Key), closeName)
	)
end

function BackpackController.close()
	if not isOpen then
		return
	end
	isOpen = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		local gui = view.Gui
		Motion.close(view.Group, function()
			if not isOpen then
				gui.Enabled = false
			end
		end, view.Dim)
	end
end

local function onClose(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	BackpackController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function ensureView(): BackpackView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = BackpackView.build()
	view.Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		BackpackController.close()
		Sfx.play("UIClick")
	end)
	TouchControls.follow(view.Gui)
	refs = view
	return view
end

function BackpackController.open()
	if isOpen or inCloseUp() then
		return
	end
	MenuPanels.closeOthers(NAME)
	local view = ensureView()
	isOpen = true
	fit(view)
	BackpackView.setBackpack(view, BackpackState.get())
	updateHint(view)
	view.Gui.Enabled = true
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	local first = BackpackView.firstRow(view)
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then (if first then first.Frame else view.Close) else nil
	Sfx.play("UIClick")
	Motion.pop(view.Group, view.Dim)
end

function BackpackController.toggle()
	if isOpen then
		BackpackController.close()
	else
		BackpackController.open()
	end
end

local function onKey(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not isOpen and inCloseUp() then
		return Enum.ContextActionResult.Pass -- (cleaning, build mode, the vault...: no window there)
	end
	BackpackController.toggle()
	if not isOpen then
		Sfx.play("UIClick")
	end
	return Enum.ContextActionResult.Sink
end

function BackpackController.init()
	-- the window follows the backpack while it is open
	BackpackState.onChanged(refresh)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		BackpackController.close()
	end)
end

function BackpackController.start()
	ContextActionService:BindAction(KEY_ACTION, onKey, false, BackpackController.Key, BackpackController.PadKey)
	-- the HUD's backpack button (right of the blaster's hotbar slot): click, tap, a gamepad's A
	local hud = HudController.refs()
	if hud then
		hud.Backpack.Activated:Connect(function()
			if not isOpen and inCloseUp() then
				return
			end
			BackpackController.toggle()
			if not isOpen then
				Sfx.play("UIClick")
			end
		end)
	end
	refreshKeyHint()
	UserInputService.LastInputTypeChanged:Connect(function()
		refreshKeyHint()
		local view = refs
		if isOpen and view then
			updateHint(view)
			keepSelection(view)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if isOpen and view then
				fit(view)
			end
		end)
	end
end

return BackpackController
