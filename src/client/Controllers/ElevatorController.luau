--[[
	ElevatorController: the mine elevator's panel, its prompt text and the
	screen fade of a ride (the server decides everything: ElevatorService).

	- Prompt: every "ElevatorPrompt" shows "Use" when you own the elevator and
	  "Buy $500K" when you don't (a local text change; refreshed on every State).
	- Opens on OpenUI "Elevator" { Stop, Floor, Owned } (the stop's prompt).
	  Not owned: the Buy page (BUY greyed out while you can't afford it;
	  pressing it then says how much is missing). Owned: the floor cards; GO
	  sends ElevatorAction { Action = "Go", Floor }, LOCKED says which blaster
	  the floor needs. Buying switches to the floor cards as soon as the next
	  State says ElevatorOwned.
	- Closes with the X button, B (gamepad), Backspace, walking away from the
	  stop, respawning or a ride starting. Other prompts are hidden while it is
	  open; gamepads get a selected button on open and after every refresh.
	- ElevatorRide "Depart": the screen fades to black with "FLOOR N" and the
	  floor's name; "Arrive": it fades back in (also after a void rescue). If
	  no "Arrive" comes, the screen comes back by itself after RIDE_TIMEOUT.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared.Config.MineFloors)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local ElevatorView = require(script.Parent.Parent.UI.ElevatorView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)
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
-- BUY / GO wait for the server's answer (at most this long) before they work again
local SEND_LOCK = 1
-- seconds a message stays in the header
local MESSAGE_TIME = 5
local FADE_OUT = 0.35
local FADE_HOLD = 0.2
local FADE_IN = 0.5
-- the screen comes back by itself if no "Arrive" comes
local RIDE_TIMEOUT = 8
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
-- weak keys: prompts of stops that streamed out drop out by themselves
local prompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function ElevatorController.isOpen(): boolean
	return isOpen
end

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
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

local function hint(): string
	if not owned() then
		return if usingGamepad() then "Buy once, ride forever   •   B: close" else "Buy once, ride forever   •   Backspace: close"
	end
	if usingGamepad() then
		return "Choose a floor and press A   •   B: close"
	end
	return "Click GO to ride   •   Backspace: close"
end

local function closeHolder(view: ElevatorView.Refs): Frame
	return view.Close.Parent :: Frame
end

-- The platform's own B / Circle glyph on the close button while a gamepad is used.
local function updateGlyph(view: ElevatorView.Refs)
	local holder = closeHolder(view)
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
	if not usingGamepad() then
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
		view.Hint.Text = hint()
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
		showMessage(`{entry.Name} needs Blaster {entry.MinBlaster}+. Forge a better blaster at your Foundry.`, "Deny")
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

function ElevatorController.close()
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
		view.Gui.Enabled = false
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

-- Closes when you walk away or the stop disappears (streamed out).
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

function ElevatorController.open(model: Model?, floorIndex: number?)
	if isOpen and model ~= nil and model == stop then
		refresh()
		return
	end
	ElevatorController.close()
	local view = ensureView()
	isOpen = true
	stop = model
	stopFloor = floorIndex
	fit(view)
	local mode: ElevatorView.Mode = if owned() then "Floors" else "Buy"
	ElevatorView.setMode(view, mode)
	ElevatorView.hideMessage(view)
	view.Hint.Text = hint()
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
	-- a quick pop-in
	local pop = view.Panel:FindFirstChild("OpenPop") :: UIScale?
	if not pop then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = view.Panel
		pop = made
	end
	local scale = pop :: UIScale
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- the ride fade

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

local function fadeIn(screen: ElevatorView.Fade, token: number)
	local info = TweenInfo.new(FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(screen.Black, info, { BackgroundTransparency = 1 }):Play()
	tweenText(screen.Title, 1, FADE_IN)
	tweenText(screen.Name, 1, FADE_IN)
	task.delay(FADE_IN + 0.05, function()
		if rideToken == token then
			screen.Gui.Enabled = false
		end
	end)
end

local function depart(floorIndex: number, name: string, seconds: number)
	ElevatorController.close()
	local screen = ensureFade()
	rideToken += 1
	local token = rideToken
	ElevatorView.setFadeText(screen, floorIndex, name)
	screen.Gui.Enabled = true
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(screen.Black, info, { BackgroundTransparency = 0 }):Play()
	tweenText(screen.Title, 0, seconds)
	tweenText(screen.Name, 0, seconds)
	task.delay(RIDE_TIMEOUT, function()
		if rideToken == token and screen.Gui.Enabled then
			fadeIn(screen, token)
		end
	end)
end

local function arrive(floorIndex: number, name: string, rescue: boolean)
	local screen = ensureFade()
	rideToken += 1
	local token = rideToken
	ElevatorView.setFadeText(screen, floorIndex, if rescue then "Back to safety" else name)
	if rescue or not screen.Gui.Enabled then
		-- a void rescue: a quick dip to black
		screen.Gui.Enabled = true
		screen.Black.BackgroundTransparency = 0
		for _, label in { screen.Title, screen.Name } do
			label.TextTransparency = 0
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0
			end
		end
	end
	Sfx.play("MachineDone")
	task.delay(FADE_HOLD, function()
		if rideToken == token then
			fadeIn(screen, token)
		end
	end)
end

local function onRide(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local floorIndex = if type(payload.Floor) == "number" and payload.Floor == payload.Floor then math.floor(payload.Floor) else 1
	local name = if type(payload.Name) == "string" then payload.Name else ""
	if payload.Phase == "Depart" then
		local seconds = if type(payload.Fade) == "number" and payload.Fade == payload.Fade
			then math.clamp(payload.Fade, 0.05, 1.5)
			else FADE_OUT
		depart(floorIndex, name, seconds)
	elseif payload.Phase == "Arrive" then
		arrive(floorIndex, name, payload.Rescue == true)
	end
end

---------------------------------------------------------------- lifecycle

function ElevatorController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Elevator" or type(payload) ~= "table" then
			return
		end
		local model = payload.Stop
		local floorIndex = if type(payload.Floor) == "number" and payload.Floor == payload.Floor then payload.Floor else nil
		if typeof(model) == "Instance" and model:IsA("Model") then
			ElevatorController.open(model, floorIndex)
		else
			ElevatorController.open(nil, floorIndex)
		end
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
		ElevatorController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and isOpen then
			view.Hint.Text = hint()
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
end

return ElevatorController
