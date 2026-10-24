--[[
	ElevatorController: the mine elevator on the client (the server decides
	everything: ElevatorService, TeleportService). Owner's flow (2026-10-18):
	the elevator button takes you TO the elevator, E at the elevator opens
	the floor picker, and the ride between floors is a short animation.

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
	- Prompt: every "ElevatorPrompt" shows "Use" when you own the elevator and
	  "Buy $500K" when you don't (a local text change; refreshed on every
	  State). Triggering it is the only way to open the panel (OpenUI
	  "Elevator" { Stop, Floor, Owned }; openAt): the Buy page or the floor
	  cards; the other panels close (MenuPanels.closeOthers).
	- Panel: BUY is greyed out while you can't afford it (pressing it says how
	  much is missing); GO sends ElevatorAction { Action = "Go", Floor },
	  LOCKED says which blaster the floor needs. Buying switches to the floor
	  cards as soon as the next State says ElevatorOwned. "YOU ARE HERE" =
	  the stop's floor.
	- Opening: the doors slide apart, the panel pops, the cards drop in
	  (ElevatorView.pose driven by one tween, about 0.56 s); any click, tap or
	  key skips to the end. Closing plays it backwards (0.24 s).
	- Closes with the X button, B (gamepad), Backspace, walking away from the
	  stop, respawning or a ride starting. Other prompts are hidden while it
	  is open; gamepads get a selected button on open and after every refresh.
	- The ride (ElevatorRideView): ElevatorRide "Depart" { Floor, From, Name,
	  Duration, DoorsClose } closes the panel and plays the full-screen ride
	  (doors slam shut with a thud, the floor counter ticks with a click per
	  floor, light sweeps, rumble and hum); the character's controls are
	  frozen. "Arrive" (and at least Duration seconds of ride) ding, the doors
	  open on the new floor and the floor banner slides through with a short
	  arrival sting (0.2 s after the ding); the controls
	  come back when the doors are open. Without "Arrive" the doors open by
	  themselves (ElevatorRideView.Timing.FailSafe). A void rescue ("Arrive"
	  with Rescue) only dips the screen to black.
	- Reduced motion (Roblox's setting, or ElevatorController.ReducedMotion):
	  no opening animation, no idle pulse, and the ride shows the doors and
	  the numbers without shake or sweeps.
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
local ElevatorRideView = require(script.Parent.Parent.UI.ElevatorRideView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local TeleportController = require(script.Parent.TeleportController)
local SideMenuController = require(script.Parent.SideMenuController)
local SideMenuView = require(script.Parent.Parent.UI.SideMenuView)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local ElevatorController = {}

-- true = no opening animation and no idle pulse, whatever Roblox's setting says
ElevatorController.ReducedMotion = false

local CLOSE_ACTION = "TerraForgeElevatorClose"
-- above the default player controls, so B / Backspace close the view first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local PROMPT_NAME = "ElevatorPrompt"
local RANGE_CHECK = 0.25
-- a bit more than the server's ElevatorService.Range (16), so lag never closes it early
local CLOSE_RANGE = 22
-- BUY / GO wait for the server's answer (at most this long) before they work again
local SEND_LOCK = 1
-- seconds a message stays in the header
local MESSAGE_TIME = 5
-- the void rescue's dip to black
local FADE_HOLD = 0.2
local FADE_IN = 0.5
local MESSAGE_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
	Discovery = Theme.Accent,
}

local player = Players.LocalPlayer
local refs: ElevatorView.Refs? = nil
local fade: ElevatorView.Fade? = nil
local stop: Model? = nil
local stopFloor: number? = nil
local isOpen = false
local rangeConnection: RBXScriptConnection? = nil
local lockedUntil = 0
local messageToken = 0
local rideToken = 0
local progress: NumberValue? = nil
local animTween: Tween? = nil
local skipConnection: RBXScriptConnection? = nil
-- weak keys: prompts of stops that streamed out drop out by themselves
local prompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

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

local function reducedMotion(): boolean
	if ElevatorController.ReducedMotion then
		return true
	end
	local ok, on = pcall(function(): any
		local service: any = GuiService
		return service.ReducedMotionEnabled
	end)
	return ok and on == true
end

---------------------------------------------------------------- state

local function owned(): boolean
	local state = StateController.get()
	return state ~= nil and state.ElevatorOwned == true
end

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

---------------------------------------------------------------- prompts

local function promptText(): string
	return if owned() then "Use" else "Buy " .. Format.money(MineFloors.Elevator.Price)
end

local function applyPrompt(prompt: ProximityPrompt)
	prompt.ActionText = promptText()
end

local function refreshPrompts()
	for prompt in prompts do
		if prompt.Parent then
			applyPrompt(prompt)
		end
	end
end

---------------------------------------------------------------- the view

local function applyHint(view: ElevatorView.Refs)
	local buy = view.Mode == "Buy"
	if usingGamepad() then
		ElevatorView.setHint(view, "Gamepad", if buy then "Buy once, ride forever · B: close" else "Choose a floor · B: close")
		view.HintGlyph.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
	elseif isPhone() then
		ElevatorView.setHint(view, "Touch", if buy then "Buy once, ride forever" else "Tap GO to ride")
	else
		ElevatorView.setHint(
			view,
			"Mouse",
			if buy then "Buy once, ride forever · Backspace: close" else "Click GO to ride · Backspace: close"
		)
	end
end

-- The platform's own B / Circle glyph on the close button while a gamepad is used.
local function updateGlyph(view: ElevatorView.Refs)
	local holder = view.CloseLook.Holder
	local glyph = holder:FindFirstChild("Glyph") :: ImageLabel?
	if not glyph then
		local image = Instance.new("ImageLabel")
		image.Name = "Glyph"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.new(0, 2, 1, -2)
		image.Size = UDim2.fromOffset(30, 30)
		image.ZIndex = 3
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

local function defaultButton(view: ElevatorView.Refs): GuiObject
	if view.Mode == "Buy" then
		return if view.CanAfford then view.BuyButton else view.Close
	end
	return ElevatorView.firstGo(view) or view.Close
end

local function selectDefault(view: ElevatorView.Refs, force: boolean?)
	if not usingGamepad() or not isOpen then
		return
	end
	local selected = GuiService.SelectedObject
	if not force and selected and selected:IsDescendantOf(view.Gui) and selected.Visible and selected.Selectable then
		local holder = selected.Parent
		local page = if view.Mode == "Buy" then view.BuyPage else view.FloorPage
		if (not holder or not holder:IsA("GuiObject") or holder.Visible) and (selected == view.Close or selected:IsDescendantOf(page)) then
			return
		end
	end
	GuiService.SelectedObject = defaultButton(view)
end

local function showMessage(text: string, kind: any)
	local view = refs
	if not view or not isOpen then
		return
	end
	local color = if type(kind) == "string" then MESSAGE_COLORS[kind] or Theme.Info else Theme.Info
	ElevatorView.showMessage(view, text, color)
	messageToken += 1
	local token = messageToken
	task.delay(MESSAGE_TIME, function()
		local current = refs
		if messageToken == token and current then
			ElevatorView.hideMessage(current)
		end
	end)
end

local function refresh()
	local view = refs
	if not view or not isOpen then
		return
	end
	local mode: ElevatorView.Mode = if owned() then "Floors" else "Buy"
	local switched = view.Mode ~= mode
	if switched then
		ElevatorView.setMode(view, mode)
		applyHint(view)
	end
	local level = blasterLevel()
	ElevatorView.setPurchase(view, coins(), MineFloors.Elevator.Price)
	ElevatorView.setFloors(view, ElevatorView.entries(level, stopFloor), level)
	selectDefault(view, switched)
end

local function locked(): boolean
	return os.clock() < lockedUntil
end

local function send(arg: { [string]: any })
	lockedUntil = os.clock() + SEND_LOCK
	Sfx.play("UIClick")
	Net.send("ElevatorAction", arg)
end

local function onBuy()
	local view = refs
	if not view or not isOpen or locked() then
		return
	end
	if not view.CanAfford then
		local missing = MineFloors.Elevator.Price - coins()
		showMessage(`You need {Format.money(math.max(missing, 1))} more for the Elevator.`, "Deny")
		Sfx.play("UIDeny")
		return
	end
	send({ Action = "Buy" })
end

local function onCard(card: ElevatorView.Card)
	if not isOpen then
		return
	end
	local entry = card.Entry
	if entry.State == "Open" then
		if not locked() then
			send({ Action = "Go", Floor = entry.Index })
		end
	elseif entry.State == "Locked" then
		showMessage(`{entry.Name} needs Blaster {entry.MinBlaster}+. Buy a better blaster at the Blaster Vault.`, "Deny")
		Sfx.play("UIDeny")
	elseif entry.State == "Here" then
		showMessage("You are on this floor.", "Info")
	else
		showMessage("More floors are coming in an update!", "Info")
	end
end

-- Fits the panel to the screen (phones get the compact layout).
local function fit(view: ElevatorView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = isPhone() or scale <= 0.75 or size.Y < 520
	ElevatorView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

---------------------------------------------------------------- opening / closing animation

local function stopAnimation()
	local tween = animTween
	animTween = nil
	if tween then
		tween:Cancel()
	end
	if skipConnection then
		skipConnection:Disconnect()
		skipConnection = nil
	end
end

local function ensureProgress(): NumberValue
	local existing = progress
	if existing then
		return existing
	end
	local value = Instance.new("NumberValue")
	value.Name = "ElevatorOpening"
	value.Value = ElevatorView.OpenTime
	value.Changed:Connect(function(seconds: number)
		local view = refs
		if view then
			ElevatorView.pose(view, seconds)
		end
	end)
	progress = value
	return value
end

local function finishOpening()
	stopAnimation()
	local value = ensureProgress()
	value.Value = ElevatorView.OpenTime
	local view = refs
	if view then
		ElevatorView.pose(view, ElevatorView.OpenTime)
	end
end

local function playOpen(view: ElevatorView.Refs)
	stopAnimation()
	local value = ensureProgress()
	if reducedMotion() then
		finishOpening()
		return
	end
	value.Value = 0
	ElevatorView.pose(view, 0)
	local tween =
		TweenService:Create(value, TweenInfo.new(ElevatorView.OpenTime, Enum.EasingStyle.Linear), { Value = ElevatorView.OpenTime })
	animTween = tween
	tween.Completed:Connect(function()
		if animTween == tween then
			animTween = nil
			if skipConnection then
				skipConnection:Disconnect()
				skipConnection = nil
			end
		end
	end)
	-- any click, tap or key skips to the end
	skipConnection = UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or kind == Enum.UserInputType.Keyboard
			or kind.Name:sub(1, 7) == "Gamepad" and input.KeyCode.Name:sub(1, 6) == "Button"
		then
			finishOpening()
		end
	end)
	tween:Play()
end

local function playClose(done: () -> ())
	stopAnimation()
	local value = ensureProgress()
	if reducedMotion() or value.Value <= 0 then
		done()
		return
	end
	local seconds = ElevatorView.CloseTime * value.Value / ElevatorView.OpenTime
	local tween = TweenService:Create(value, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Value = 0 })
	animTween = tween
	tween.Completed:Connect(function()
		if animTween == tween then
			animTween = nil
			done()
		end
	end)
	tween:Play()
end

function ElevatorController.close(instant: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	stop = nil
	stopFloor = nil
	if rangeConnection then
		rangeConnection:Disconnect()
		rangeConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		ElevatorView.hideMessage(view)
		local gui = view.Gui
		if instant then
			stopAnimation()
			gui.Enabled = false
		else
			playClose(function()
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

local function ensureView(): ElevatorView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = ElevatorView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		ElevatorController.close()
		Sfx.play("UIClick")
	end)
	view.BuyButton.Activated:Connect(onBuy)
	for _, card in view.Cards do
		card.Button.Activated:Connect(function()
			onCard(card)
		end)
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
	Opens the panel at a stop (its prompt: OpenUI). `model` = the stop (nil =
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
	local view = ensureView()
	isOpen = true
	stop = model
	stopFloor = floorIndex
	fit(view)
	local mode: ElevatorView.Mode = if owned() then "Floors" else "Buy"
	ElevatorView.setMode(view, mode)
	ElevatorView.hideMessage(view)
	applyHint(view)
	updateGlyph(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("Elevator", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	if model then
		watchRange(model)
	end
	GuiService.SelectedObject = nil
	refresh()
	selectDefault(view, true)
	Sfx.play("UIClick")
	playOpen(view)
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

type Driving = {
	Ride: ElevatorRideView.Ride,
	T: number, -- seconds since "Depart"
	Arrived: boolean,
	Number: number, -- the floor the indicator shows (a click when it changes)
	Thud: boolean,
	Sting: boolean, -- the arrival sting has played
	Restored: boolean,
	Frozen: boolean, -- we hold the controls lock
	Connection: RBXScriptConnection?,
}

local RIDE_LOCK = "Elevator"
-- the arrival sting (SoundConfig.ElevatorArrive) plays this long after the doors start to open:
-- the ding plays at the open, the sting comes with the floor banner
local ARRIVE_STING = 0.2
local rideRefs: ElevatorRideView.Refs? = nil
local driving: Driving? = nil

local function ensureRide(): ElevatorRideView.Refs
	local existing = rideRefs
	if existing then
		return existing
	end
	local made = ElevatorRideView.build()
	made.Gui.Parent = player:WaitForChild("PlayerGui")
	rideRefs = made
	return made
end

local function unfreeze(state: Driving)
	if state.Frozen then
		state.Frozen = false
		task.spawn(PlayerControls.set, true)
		PlayerControls.release(RIDE_LOCK)
	end
end

local function endRide()
	local state = driving
	driving = nil
	if not state then
		return
	end
	local connection = state.Connection
	if connection then
		connection:Disconnect()
	end
	Sfx.loop("MachineHum", false)
	unfreeze(state)
	local view = rideRefs
	if view then
		view.Gui.Enabled = false
	end
end

local function stepRide(dt: number)
	local state = driving
	local view = rideRefs
	if not state or not view then
		return
	end
	state.T += dt
	local ride = state.Ride
	local t = state.T
	if not state.Thud and t >= ride.Close then
		state.Thud = true
		Sfx.play("DoorThud")
		Sfx.loop("MachineHum", true)
	end
	if ElevatorRideView.shouldOpen(ride, t, state.Arrived) then
		ride.OpenAt = t
		Sfx.loop("MachineHum", false)
		Sfx.play("ElevatorDing")
	end
	local openAt = ride.OpenAt
	if not state.Sting and openAt and t >= openAt + ARRIVE_STING then
		state.Sting = true
		Sfx.play("ElevatorArrive")
	end
	local number = ElevatorRideView.numberAt(ride, t)
	if number ~= state.Number then
		state.Number = number
		Sfx.play("BuildRotate")
	end
	ElevatorRideView.pose(view, ride, t)
	if not state.Restored and t >= ElevatorRideView.openedAt(ride) then
		state.Restored = true
		unfreeze(state)
	end
	if t >= ElevatorRideView.doneAt(ride) then
		endRide()
	end
end

local function startRide(payload: { [string]: any })
	ElevatorController.close(true)
	endRide()
	local to = if type(payload.Floor) == "number" and payload.Floor == payload.Floor then math.floor(payload.Floor) else 1
	local name = if type(payload.Name) == "string" then payload.Name else MineFloors.get(to).Name
	local ride = ElevatorRideView.newRide(payload.From, to, name, payload.Duration, payload.DoorsClose, reducedMotion())
	local view = ensureRide()
	local inset = GuiService:GetGuiInset()
	ElevatorRideView.layout(view, HudController.uiScale(), inset.Y)
	ElevatorRideView.setRide(view, ride)
	local state: Driving = {
		Ride = ride,
		T = 0,
		Arrived = false,
		Number = ride.From,
		Thud = false,
		Sting = false,
		Restored = false,
		Frozen = false,
		Connection = nil,
	}
	-- the character stands still while the doors are shut
	if PlayerControls.claim(RIDE_LOCK) then
		state.Frozen = true
		task.spawn(PlayerControls.set, false)
	end
	driving = state
	ElevatorRideView.pose(view, ride, 0)
	view.Gui.Enabled = true
	state.Connection = RunService.Heartbeat:Connect(stepRide)
end

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
		startRide(payload)
	elseif payload.Phase == "Arrive" then
		local state = driving
		if payload.Rescue == true then
			local floorIndex = if type(payload.Floor) == "number" and payload.Floor == payload.Floor then math.floor(payload.Floor) else 1
			rescued(floorIndex)
		elseif state then
			-- the character stands at the target stop: the doors may open
			state.Arrived = true
		end
	end
end

---------------------------------------------------------------- lifecycle

function ElevatorController.init()
	-- exact text widths in the game (the view's tables are for tests and previews)
	ElevatorView.Measure = function(text: string, size: number, title: boolean): number
		local font = if title then Enum.Font.LuckiestGuy else Enum.Font.FredokaOne
		return TextService:GetTextSize(text, size, font, Vector2.new(10000, 1000)).X
	end
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Elevator" or type(payload) ~= "table" then
			return
		end
		-- only the stop's prompt opens the panel (the server checked the range)
		local model = payload.Stop
		local floorIndex = if type(payload.Floor) == "number" and payload.Floor == payload.Floor then payload.Floor else nil
		if driving then
			return
		end
		ElevatorController.openAt(if typeof(model) == "Instance" and model:IsA("Model") then model else nil, floorIndex)
	end)
	Net.listen("ElevatorRide", onRide)
	Net.listen("Notify", function(message)
		if isOpen and type(message) == "table" and type(message.Text) == "string" then
			showMessage(message.Text, message.Kind)
		end
	end)
	StateController.onChanged(function()
		-- a new snapshot means the last request was answered
		lockedUntil = 0
		refreshPrompts()
		refresh()
	end)
	player.CharacterRemoving:Connect(function()
		ElevatorController.close(true)
		endRide()
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
			prompts[prompt] = true
			applyPrompt(prompt)
		end
	end)
	-- the side menu shows ELEVATOR only while the world has a stop
	Workspace:GetAttributeChangedSignal(TeleportConfig.ElevatorAttribute):Connect(SideMenuController.refresh)
	SideMenuController.refresh()
end

return ElevatorController
