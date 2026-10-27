--[[
	EmoteController: the EMOTES menu (UI/EmoteView; owner 2026-10-21: "add
	the emotes"; live while AnimConfig.Emotes is on, else nothing here runs).

	Opening it
	  PC        the N key (EmoteController.Key: free, see the Lune test
	            tests/EmotesLive.spec: no other KeyCode.N in the game, and no
	            Roblox core key), or the EMOTES tile
	  Touch     the EMOTES tile in the left HUD menu (no extra screen button)
	  Gamepad   the EMOTES tile: D-pad Left jumps onto the menu tiles
	            (SideMenuController), A opens it. No new pad button: every
	            face, shoulder, stick and D-pad button is taken already
	The menu is a panel (MenuPanels: it closes the others when it opens and
	closes when another opens); B / Backspace / the X close it. A gamepad
	gets the first card selected; the window is a SelectionGroup.

	Picking a card plays that emote (MoveController.playEmote) and closes
	the menu; picking the playing one stops it. The Blaster Spin card is
	grey with "Hold your blaster" while the blaster isn't in hand. A refused
	pick says why on the hint line (put the ore down first...).

	Never in a close-up (cleaning, build mode, the vault, any
	Scriptable camera): N and the tile do nothing there (every
	pick would be refused, and the menu's B / Backspace would take the key
	cleaning exits with).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimConfig = require(Shared.Config.AnimConfig)
local EmoteConfig = require(Shared.Config.EmoteConfig)
local EmoteRules = require(Shared.Moves.EmoteRules)
local EmoteView = require(script.Parent.Parent.UI.EmoteView)
local HudBubble = require(script.Parent.Parent.UI.HudBubble)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudController = require(script.Parent.HudController)
local MoveController = require(script.Parent.MoveController)

local EmoteController = {}

EmoteController.Key = Enum.KeyCode.N
EmoteController.TileId = "Emotes"

local NAME = "EmoteController"
local KEY_ACTION = "TerraForgeEmotes"
local CLOSE_ACTION = "TerraForgeEmotesClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10

-- what a refused pick says on the hint line
EmoteController.Reasons = {
	Building = "Not while building or cleaning.",
	Riding = "Get off the hoverboard first.",
	Seated = "Stand up first.",
	Dead = "Wait a moment.",
	NoBlaster = EmoteRules.NeedsBlaster .. " first.",
	Cooldown = "Wait a moment.",
	NoCharacter = "Wait a moment.",
	Off = "Emotes are off.",
} :: { [string]: string }

local refs: EmoteView.Refs? = nil
local isOpen = false
local watchers: { RBXScriptConnection } = {}
local cleaning: any = nil -- CleaningController (required on the first look: false = none)

-- A close-up now? (MoveController: a Scriptable camera or PlayerControls claimed; the cleaning minigame)
local function inCloseUp(): boolean
	if MoveController.inCloseUp() then
		return true
	end
	if cleaning == nil then
		cleaning = false
		local module = script.Parent:FindFirstChild("CleaningController")
		if module and module:IsA("ModuleScript") then
			local ok, controller = pcall(require, module :: any)
			if ok and type(controller) == "table" and type((controller :: any).isActive) == "function" then
				cleaning = controller
			end
		end
	end
	local controller = cleaning
	if not controller then
		return false
	end
	local ok, active = pcall(controller.isActive)
	return ok and active == true
end

function EmoteController.isOpen(): boolean
	return isOpen
end

local function hintText(): string
	if MenuPanels.usingGamepad() then
		return "A: play   B: close   Walk to stop it."
	elseif MenuPanels.isTouch() then
		return "Tap a move. Walk to stop it."
	end
	return "Pick a move. Walk to stop it.   " .. UserInputService:GetStringForKeyCode(EmoteController.Key) .. ": this menu"
end

local function refreshCards()
	local view = refs
	if not view then
		return
	end
	local playing = MoveController.emote()
	local blaster = MoveController.holdingBlaster()
	for _, name in EmoteConfig.List do
		if name == playing then
			EmoteView.setCard(view, name, "Playing", "pick again to stop")
		elseif EmoteRules.needsTool(name) and not blaster then
			EmoteView.setCard(view, name, "Locked", EmoteRules.NeedsBlaster)
		else
			EmoteView.setCard(view, name, "Ready")
		end
	end
end

local function fit(view: EmoteView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = EmoteView.compactFor(MenuPanels.isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	EmoteView.layout(view, size.X / scale, (size.Y - inset.Y) / scale, compact)
end

local function unwatch()
	for _, connection in watchers do
		connection:Disconnect()
	end
	table.clear(watchers)
end

function EmoteController.close()
	if not isOpen then
		return
	end
	isOpen = false
	unwatch()
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
		end, gui:FindFirstChild("Dim") :: GuiObject?)
	end
end

local function onPick(name: string)
	local view = refs
	if not view then
		return
	end
	local card = view.Cards[name]
	if card and card.State == "Locked" then
		EmoteView.setHint(view, EmoteController.Reasons.NoBlaster)
		Sfx.play("UIClick")
		return
	end
	local ok, reason = MoveController.playEmote(name)
	Sfx.play("UIClick")
	if ok then
		EmoteController.close()
	else
		EmoteView.setHint(view, EmoteController.Reasons[reason or ""] or "Not now.")
	end
end

local function onClose(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	EmoteController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function ensureView(): EmoteView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = EmoteView.build()
	view.Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	view.Window.Close.Activated:Connect(function()
		EmoteController.close()
		Sfx.play("UIClick")
	end)
	for name, card in view.Cards do
		card.Button.Activated:Connect(function()
			onPick(name)
		end)
	end
	TouchControls.follow(view.Gui)
	refs = view
	return view
end

function EmoteController.open()
	if isOpen or not AnimConfig.Emotes or inCloseUp() then
		return
	end
	MenuPanels.closeOthers(NAME)
	local view = ensureView()
	isOpen = true
	fit(view)
	refreshCards()
	EmoteView.setHint(view, hintText())
	view.Gui.Enabled = true
	-- the Blaster Spin card follows the blaster in your hand while the menu is open
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(watchers, character.ChildAdded:Connect(refreshCards))
		table.insert(watchers, character.ChildRemoved:Connect(refreshCards))
	end
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	local first = view.Cards[view.Order[1]]
	GuiService.SelectedObject = if MenuPanels.usingGamepad() and first then first.Button else nil
	Sfx.play("UIClick")
	Motion.pop(view.Group, view.Gui:FindFirstChild("Dim") :: GuiObject?)
end

function EmoteController.toggle()
	if isOpen then
		EmoteController.close()
	else
		EmoteController.open()
	end
end

local function onKey(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not isOpen and inCloseUp() then
		return Enum.ContextActionResult.Pass -- (cleaning, build mode, the vault...: no menu there)
	end
	EmoteController.toggle()
	return Enum.ContextActionResult.Sink
end

function EmoteController.start()
	if not AnimConfig.Emotes then
		return
	end
	ContextActionService:BindAction(KEY_ACTION, onKey, false, EmoteController.Key)
	-- the left HUD menu's EMOTES tile (the light UI; touch and gamepad open the menu here)
	local hud = HudController.refs()
	if hud and hud.Menu and hud.Menu:GetAttribute("Bubble") then
		local face = HudBubble.claimTile(hud.Menu, EmoteController.TileId, { Label = "EMOTES", IconName = "Emotes", Order = 40 })
		face.Activated:Connect(function()
			Sfx.play("UIClick")
			EmoteController.toggle()
		end)
	end
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if isOpen and view then
			EmoteView.setHint(view, hintText())
		end
	end)
end

return EmoteController
