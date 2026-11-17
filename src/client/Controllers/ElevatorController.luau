--[[
	ElevatorController: the mine elevator on the client (the server decides
	everything: ElevatorService, TeleportService). Owner's flow (2026-10-18):
	the elevator button takes you TO the elevator, E at the elevator opens
	the floor picker, and the ride between floors is a short animation.
	The picker is the ELEVATOR window (owner 2026-11-15, UI/ElevatorWindow):
	a card per floor, bought one by one with coins.

	- Side menu: the ELEVATOR button of main's left side menu
	  (SideMenuView entry "Elevator", SideMenuController action) calls open()
	  / toggle(): the "Elevator" teleport (TeleportController.request: same
	  fade, cooldown and refusal toasts as the top bar); the server puts you
	  at the stop of the floor you are on, else floor 1's. isOpen() / close()
	  are the floor picker's (MenuPanels: one panel at a time, build mode
	  closes it). available() = the world has a stop (Workspace attribute
	  TeleportConfig.ElevatorAttribute): the side menu hides the button
	  otherwise and is refreshed when that attribute changes. (D-pad Left is
	  the side menu's: it jumps into the column.)
	- Prompt: every "ElevatorPrompt" says "Use". Triggering it is the only
	  way to open the window (OpenUI "Elevator" { Stop, Floor }; openAt); the
	  other panels close (MenuPanels.closeOthers).
	- Window: the cards come from the State (BlasterLevel, Coins and
	  ElevatorFloors, the floors bought): YOU ARE HERE = the stop's floor;
	  TRAVEL sends ElevatorAction { Action = "Go", Floor } (its card lights
	  up, the others dim; a refusal puts them back); PURCHASE sends
	  { Action = "Buy", Floor } (without the coins it shakes and says how
	  many are missing; a purchase never rides). When the next State has the
	  floor bought, its card turns to TRAVEL with the gold unlock and the
	  coins count down. LOCKED shakes and says which blaster the floor
	  needs. The + opens the Robux Shop's coins. The window's loops (ShopFx
	  marks) play while it is open and restart only when a card changes.
	- Closes with the X button, B (gamepad), Backspace, walking away from the
	  stop, respawning or a ride starting. Other prompts are hidden while it
	  is open; gamepads get a selected button on open and after every change.
	- The ride is the travel cinematic (ElevatorTravelController, owner
	  2026-11-15): ElevatorRide "Depart" / "Arrive" / "Cancel" go to it; the
	  window stays up for its preparation and closes at its phase "Enter" (the
	  camera steps into the cabin). A void rescue ("Arrive" with Rescue) only
	  dips the screen to black.
	- Reduced motion (Roblox's setting): the window opens and changes without
	  motion (ShopFx.quiet); the cinematic reads UI/Motion.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared.Config.MineFloors)
local TeleportConfig = require(Shared.Config.TeleportConfig)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local ElevatorView = require(script.Parent.Parent.UI.ElevatorView)
local ElevatorWindow = require(script.Parent.Parent.UI.ElevatorWindow)
local Motion = require(script.Parent.Parent.UI.Motion)
local ShopFx = require(script.Parent.Parent.UI.ShopFx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)
local ElevatorTravelController = require(script.Parent.ElevatorTravelController)
local TeleportController = require(script.Parent.TeleportController)
local SideMenuController = require(script.Parent.SideMenuController)
local SideMenuView = require(script.Parent.Parent.UI.SideMenuView)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local ElevatorController = {}

local CLOSE_ACTION = "TerraForgeElevatorClose"
-- above the default player controls, so B / Backspace close the view first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local PROMPT_NAME = "ElevatorPrompt"
local RANGE_CHECK = 0.25
-- a bit more than the server's ElevatorService.Range (16), so lag never closes it early
local CLOSE_RANGE = 22
-- PURCHASE / TRAVEL wait for the server's answer (at most this long) before they work again
local SEND_LOCK = 1
-- seconds a message stays over the cards
local MESSAGE_TIME = 5
-- the void rescue's dip to black
local FADE_HOLD = 0.2
local FADE_IN = 0.5
-- the card the + opens in the Robux Shop (its coins)
local COINS_CARD = "CoinsSmall"
local MESSAGE_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
	Discovery = Theme.Accent,
}

local player = Players.LocalPlayer
local refs: ElevatorWindow.Refs? = nil
local fade: ElevatorView.Fade? = nil
local stop: Model? = nil
local stopFloor: number? = nil
local isOpen = false
local rangeConnection: RBXScriptConnection? = nil
local lockedUntil = 0
local messageToken = 0
local rideToken = 0
local playing: ShopFx.Playing? = nil
local playingKey = ""
-- the floor a PURCHASE was sent for (its unlock plays when the State has it bought)
local pendingBuy: number? = nil

function ElevatorController.isOpen(): boolean
	return isOpen
end

-- The left side menu (main's SideMenuController; kept for older callers).
function ElevatorController.sideMenu(): SideMenuView.Refs?
	return SideMenuController.refs()
end

-- True while the world has an elevator stop (the side menu shows ELEVATOR only then).
function ElevatorController.available(): boolean
	return Workspace:GetAttribute(TeleportConfig.ElevatorAttribute) == true
end

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

---------------------------------------------------------------- state

local function coins(): number
	local state = StateController.get()
	local value = state and state.Coins
	return if type(value) == "number" and value == value then value else 0
end

local function blasterLevel(): number
	local state = StateController.get()
	local value = state and state.BlasterLevel
	return if type(value) == "number" and value == value then value else 1
end

-- The floors bought (State ElevatorFloors: Id -> true).
local function bought(): { [string]: any }
	local state = StateController.get()
	local value = state and state.ElevatorFloors
	return if type(value) == "table" then value else {}
end

---------------------------------------------------------------- prompts

-- (an older build said "Buy $3.3M" here: every floor is bought in the window now)
local function applyPrompt(prompt: ProximityPrompt)
	prompt.ActionText = "Use"
end

---------------------------------------------------------------- the window

local function applyHint(view: ElevatorWindow.Refs)
	if usingGamepad() then
		ElevatorWindow.setHint(view, "Choose a floor  ·  B: close")
	elseif isPhone() then
		ElevatorWindow.setHint(view, "")
	else
		ElevatorWindow.setHint(view, "Click a floor  ·  Backspace: close")
	end
end

-- The platform's own B / Circle glyph on the close button while a gamepad is used.
local function updateGlyph(view: ElevatorWindow.Refs)
	local holder = view.CloseHolder
	local glyph = holder:FindFirstChild("Glyph") :: ImageLabel?
	if not glyph then
		local image = Instance.new("ImageLabel")
		image.Name = "Glyph"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.new(0, 2, 1, -2)
		image.Size = UDim2.fromOffset(30, 30)
		image.ZIndex = 12
		image.Parent = holder
		glyph = image
	end
	local label = glyph :: ImageLabel
	local gamepad = usingGamepad()
	label.Visible = gamepad
	if gamepad then
		label.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
	end
end

local function selectDefault(view: ElevatorWindow.Refs, force: boolean?)
	if not usingGamepad() or not isOpen then
		return
	end
	local selected = GuiService.SelectedObject
	if not force and selected and selected:IsDescendantOf(view.Gui) and selected.Visible and selected.Selectable then
		return
	end
	GuiService.SelectedObject = ElevatorWindow.firstButton(view) or view.Close
end

local function showMessage(text: string, kind: any)
	local view = refs
	if not view or not isOpen then
		return
	end
	local color = if type(kind) == "string" then MESSAGE_COLORS[kind] or Theme.Info else Theme.Info
	ElevatorWindow.showMessage(view, text, color)
	messageToken += 1
	local token = messageToken
	task.delay(MESSAGE_TIME, function()
		local current = refs
		if messageToken == token and current then
			ElevatorWindow.hideMessage(current)
		end
	end)
end

-- The window's loops: started on open, restarted only when a card's look changes.
local function stopLoops()
	ShopFx.stop(playing)
	playing = nil
	playingKey = ""
end

local function playLoops(view: ElevatorWindow.Refs)
	local key = ""
	for _, entry in view.Entries do
		key ..= entry.State .. (if entry.Afford then "+" else "-")
	end
	if playing and key == playingKey then
		return
	end
	ShopFx.stop(playing)
	playing = ShopFx.play(ElevatorWindow.loops(view))
	playingKey = key
end

local function refresh()
	local view = refs
	if not view or not isOpen then
		return
	end
	local level = blasterLevel()
	local money = coins()
	local owned = bought()
	-- a purchase went through: its card turns to TRAVEL with the gold unlock, the coins count down
	local unlocked: ElevatorWindow.Card? = nil
	local pending = pendingBuy
	if pending then
		local floor = MineFloors.ByIndex[pending]
		if floor and owned[floor.Id] == true then
			unlocked = view.Cards[pending]
			pendingBuy = nil
		end
	end
	ElevatorWindow.setFloors(view, ElevatorWindow.entries(level, stopFloor, owned, money))
	if unlocked then
		ElevatorWindow.setStatus(view, level, view.Coins)
		ElevatorWindow.countCoins(view, money)
		ElevatorWindow.unlock(view, unlocked)
		Sfx.play("CoinBurst")
	else
		ElevatorWindow.setStatus(view, level, money)
	end
	playLoops(view)
	selectDefault(view)
end

local function locked(): boolean
	return os.clock() < lockedUntil
end

local function send(arg: { [string]: any })
	lockedUntil = os.clock() + SEND_LOCK
	Sfx.play("UIClick")
	Net.send("ElevatorAction", arg)
end

-- The travel cinematic (anim/elevator-travel: ElevatorTravelController, when it is in the game) is playing.
local function traveling(): boolean
	local travel = MenuPanels.controller("ElevatorTravelController")
	local playing = travel and travel.isTraveling
	return type(playing) == "function" and playing() == true
end

local function onCard(card: ElevatorWindow.Card)
	local view = refs
	local entry = card.Entry
	if not isOpen or not view or not entry then
		return
	end
	local state: string = entry.State
	if (state == "Travel" or state == "Buy") and traveling() then
		return -- (the ride is starting: the window goes in a moment)
	end
	if entry.State == "Travel" then
		if not locked() then
			ElevatorWindow.pick(view, entry.Index)
			send({ Action = "Go", Floor = entry.Index })
		end
	elseif entry.State == "Buy" then
		if not entry.Afford then
			ElevatorWindow.refuse(card)
			local missing = math.max(1, math.ceil(entry.Price - coins()))
			showMessage(`You need {Format.short(missing)} more coins for {entry.Name}.`, "Deny")
			Sfx.play("UIDeny")
		elseif not locked() then
			pendingBuy = entry.Index
			send({ Action = "Buy", Floor = entry.Index })
		end
	elseif entry.State == "Locked" then
		ElevatorWindow.shake(card)
		showMessage(`{entry.Name} needs Blaster {entry.MinBlaster}+. Buy a better blaster at the Blaster Vault.`, "Deny")
		Sfx.play("UIDeny")
	else
		showMessage("You are on this floor.", "Info")
	end
end

-- The room the screen leaves for the window (design units) and whether it is a phone's.
local function room(): (boolean, number, number)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = isPhone() or scale <= 0.75 or size.Y < 520
	return compact, size.X / scale, (size.Y - inset.Y) / scale
end

function ElevatorController.close(instant: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	stop = nil
	stopFloor = nil
	pendingBuy = nil
	if rangeConnection then
		rangeConnection:Disconnect()
		rangeConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	stopLoops()
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		ElevatorWindow.hideMessage(view)
		local gui = view.Gui
		if instant then
			gui.Enabled = false
		else
			ElevatorWindow.playClose(view, function()
				if not isOpen then
					gui.Enabled = false
				end
			end)
		end
	end
	PromptController.setSuppressed("Elevator", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	ElevatorController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

-- A card's mouse hover and gamepad selection (its rise, its button's light, its picture's pan).
local function bindCard(card: ElevatorWindow.Card)
	card.Button.Activated:Connect(function()
		onCard(card)
	end)
	card.Face.Activated:Connect(function()
		onCard(card)
	end)
	ShopFx.bindPress(card.Button, card.ButtonHolder)
	local mouseOver, selected = false, false
	local function update()
		ElevatorWindow.hover(card, mouseOver or selected)
	end
	card.Face.MouseEnter:Connect(function()
		mouseOver = not usingGamepad() and not isPhone()
		update()
	end)
	card.Face.MouseLeave:Connect(function()
		mouseOver = false
		update()
	end)
	card.Button.SelectionGained:Connect(function()
		selected = true
		update()
	end)
	card.Button.SelectionLost:Connect(function()
		selected = false
		update()
	end)
end

-- The window for this screen (a phone's is built compact: rebuilt when that changes).
local function ensureView(compact: boolean): ElevatorWindow.Refs
	local existing = refs
	if existing and not ElevatorWindow.needsRebuild(existing, compact) then
		return existing
	end
	if existing then
		existing.Gui:Destroy()
		refs = nil
	end
	local view = ElevatorWindow.build(compact)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		ElevatorController.close()
		Sfx.play("UIClick")
	end)
	view.Plus.Activated:Connect(function()
		Sfx.play("UIClick")
		MenuPanels.call("StoreController", "openAt", COINS_CARD)
	end)
	view.BannerFace.Activated:Connect(function()
		showMessage(`Floor {MineFloors.ComingSoon.Index} is coming in the next update!`, "Info")
	end)
	for _, card in view.Cards do
		bindCard(card)
	end
	refs = view
	return view
end

-- Closes when you walk away from the stop it was opened at (or the stop streams out).
local function watchRange(model: Model)
	local base = model:FindFirstChild("Base")
	local part = if base and base:IsA("BasePart") then base else model.PrimaryPart
	if not part then
		return
	end
	local watched = part :: BasePart
	local elapsed = 0
	rangeConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < RANGE_CHECK then
			return
		end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not watched:IsDescendantOf(Workspace) or not root then
			ElevatorController.close()
			return
		end
		local p = watched.CFrame:PointToObjectSpace(root.Position)
		local half = watched.Size / 2
		local outside =
			Vector3.new(math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Y) - half.Y, 0), math.max(math.abs(p.Z) - half.Z, 0))
		if outside.Magnitude > CLOSE_RANGE then
			ElevatorController.close()
		end
	end)
end

--[[
	Opens the window at a stop (its prompt: OpenUI). `model` = the stop (nil =
	not streamed in: no range check), `floorIndex` = the floor shown as "YOU
	ARE HERE". The other panels close.
]]
function ElevatorController.openAt(model: Model?, floorIndex: number?)
	if isOpen and model ~= nil and model == stop then
		refresh()
		return
	end
	ElevatorController.close(true)
	MenuPanels.closeOthers("ElevatorController")
	local compact, maxW, maxH = room()
	local view = ensureView(compact)
	isOpen = true
	stop = model
	stopFloor = floorIndex
	pendingBuy = nil
	ElevatorWindow.layout(view, maxW, maxH)
	ElevatorWindow.hideMessage(view)
	applyHint(view)
	updateGlyph(view)
	view.Grid.CanvasPosition = Vector2.zero
	view.Gui.Enabled = true
	PromptController.setSuppressed("Elevator", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	if model then
		watchRange(model)
	end
	GuiService.SelectedObject = nil
	stopLoops()
	refresh()
	selectDefault(view, true)
	Sfx.play("UIClick")
	ElevatorWindow.playOpen(view)
end

-- The side menu's ELEVATOR button: a teleport to the elevator (the floor picker opens from its prompt).
function ElevatorController.open()
	if isOpen then
		ElevatorController.close()
	end
	MenuPanels.closeOthers("ElevatorController")
	TeleportController.request("Elevator")
end

-- The side menu calls toggle() when open() is missing: the same teleport (the picker's own close is close()).
function ElevatorController.toggle()
	ElevatorController.open()
end

---------------------------------------------------------------- the ride

--[[
	The ride is the travel cinematic (ElevatorTravelController, owner
	2026-11-15): "Depart" hands it over at once and the floor window stays up
	for the preparation (the picked card stays lit) until the cinematic's
	phase "Enter" closes it; "Arrive" and "Cancel" go to it too.
]]
ElevatorTravelController.onPhase(function(phaseName: string)
	if phaseName == "Enter" or phaseName == "Cancel" then
		ElevatorController.close(true)
	end
end)

---------------------------------------------------------------- the void rescue fade

local function ensureFade(): ElevatorView.Fade
	local existing = fade
	if existing then
		return existing
	end
	local made = ElevatorView.buildFade()
	made.Gui.Parent = player:WaitForChild("PlayerGui")
	fade = made
	return made
end

local function tweenText(label: TextLabel, transparency: number, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { TextTransparency = transparency }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = transparency }):Play()
	end
end

-- A void rescue: a quick dip to black with the floor's name, then back.
local function rescued(floorIndex: number)
	local screen = ensureFade()
	rideToken += 1
	local token = rideToken
	ElevatorView.setFadeText(screen, floorIndex, "Back to safety")
	screen.Gui.Enabled = true
	screen.Black.BackgroundTransparency = 0
	for _, label in { screen.Title, screen.Name } do
		label.TextTransparency = 0
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end
	Sfx.play("MachineDone")
	task.delay(FADE_HOLD, function()
		if rideToken ~= token then
			return
		end
		local info = TweenInfo.new(FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(screen.Black, info, { BackgroundTransparency = 1 }):Play()
		tweenText(screen.Title, 1, FADE_IN)
		tweenText(screen.Name, 1, FADE_IN)
		task.delay(FADE_IN + 0.05, function()
			if rideToken == token then
				screen.Gui.Enabled = false
			end
		end)
	end)
end

local function onRide(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.Phase == "Depart" then
		ElevatorTravelController.depart(payload)
	elseif payload.Phase == "Arrive" then
		if payload.Rescue == true then
			local floorIndex = if type(payload.Floor) == "number" and payload.Floor == payload.Floor then math.floor(payload.Floor) else 1
			rescued(floorIndex)
		else
			-- the character stands at the target stop: the cabin may brake and open
			ElevatorTravelController.arrive(payload)
		end
	elseif payload.Phase == "Cancel" then
		ElevatorTravelController.cancel(payload)
	end
end

---------------------------------------------------------------- lifecycle

function ElevatorController.init()
	-- exact text widths in the game (the shared Pop pieces' tables are for tests and previews)
	ElevatorView.Measure = function(text: string, size: number, title: boolean): number
		local font = if title then Enum.Font.LuckiestGuy else Enum.Font.FredokaOne
		return TextService:GetTextSize(text, size, font, Vector2.new(10000, 1000)).X
	end
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Elevator" or type(payload) ~= "table" then
			return
		end
		-- only the stop's prompt opens the window (the server checked the range)
		local model = payload.Stop
		local floorIndex = if type(payload.Floor) == "number" and payload.Floor == payload.Floor then payload.Floor else nil
		if ElevatorTravelController.isTraveling() then
			return
		end
		ElevatorController.openAt(if typeof(model) == "Instance" and model:IsA("Model") then model else nil, floorIndex)
	end)
	Net.listen("ElevatorRide", onRide)
	Net.listen("Notify", function(message)
		if not isOpen or type(message) ~= "table" or type(message.Text) ~= "string" then
			return
		end
		showMessage(message.Text, message.Kind)
		if message.Kind == "Deny" then
			-- refused: the purchase is off, the picked card lets go
			pendingBuy = nil
			local view = refs
			if view and view.Picked then
				ElevatorWindow.unpick(view)
			end
		end
	end)
	-- Reduce motion turned on or off while the window is open: its loops start over (none when quiet)
	Motion.onReducedChanged(function()
		local view = refs
		if view and isOpen then
			stopLoops()
			playLoops(view)
		end
	end)
	StateController.onChanged(function()
		-- a new snapshot means the last request was answered
		lockedUntil = 0
		refresh()
	end)
	player.CharacterRemoving:Connect(function()
		ElevatorController.close(true)
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and isOpen then
			applyHint(view)
			updateGlyph(view)
			selectDefault(view)
		end
	end)
end

function ElevatorController.start()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == PROMPT_NAME then
			applyPrompt(prompt)
		end
	end)
	-- the side menu shows ELEVATOR only while the world has a stop
	Workspace:GetAttributeChangedSignal(TeleportConfig.ElevatorAttribute):Connect(SideMenuController.refresh)
	SideMenuController.refresh()
end

return ElevatorController
