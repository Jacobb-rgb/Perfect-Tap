--[[
	HoverboardController: hoverboards on the client (the server decides
	everything: HoverboardService, MonetizationService).

	- Boards panel (HoverboardView): the "Boards" button in the left side menu
	  (ElevatorController.sideMenu(), under the elevator button) opens it from
	  anywhere. Cards: BUY sends HoverboardAction { Action = "Buy", Board }
	  (greyed out with a lock while you can't afford it: pressing it says how
	  much is missing), EQUIP sends { Action = "Equip" }, the Robux button
	  prompts the developer product (MarketplaceService:PromptProductPurchase,
	  only for MonetizationConfig ids > 0; "COMING SOON" otherwise). The cards
	  refresh on every State. Closes with the X, B (gamepad), Backspace or
	  the side button again; gamepads get a selected card on open.
	- RIDE: a round button in the HUD's right menu (above BUILD: clear of the
	  touch jump button at the bottom right), the H key and the gamepad's
	  GamepadKey (D-pad Right; D-pad Down already opens the teleport bar and
	  D-pad Left the elevator) send { Action = "Ride", On } (no board yet:
	  the panel opens). The button shows only while a board is equipped:
	  RIDE / STOP, with an "H" chip or the gamepad glyph (none on touch).
	  Refused on the client while a minigame or build mode holds the controls.
	- Every rider's board (also other players): when a character has the
	  attribute HoverboardData.Attribute, this client builds that board
	  (HoverboardBuilder, rigged: massless, no collision; pooled per board,
	  PoolPerBoard spares) into a ClientHoverboards folder and welds it under
	  the HumanoidRootPart (Weld C0: down by HRP half height + HipHeight, +2
	  for R6 legs: the deck top meets the feet). Every frame the weld's C0 adds
	  a slow bob, a nose-up lean with speed and a roll into turns. Range
	  (StreamingEnabled friendly, checked every LodInterval): beyond ShowRange
	  studs or streamed out = no board; beyond FxRange = no effects; your own
	  board always shows. Robux boards get their HoverboardFx (pooled; lite on
	  phones and with many riders), the rates follow the speed.
	- Riding pose (your own character only; animations replicate): the
	  character's own idle animation (Animate.idle, nothing uploaded) plays at
	  Action priority and the walk / run tracks are silenced (weight 0, so the
	  Animate script's state machine stays happy; weight back on dismount).
	  No Animate script or no idle animation = no pose, nothing breaks.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HoverboardData = require(Shared.Config.HoverboardData)
local Theme = require(Shared.Config.UITheme)
local HoverboardBuilder = require(Shared.Builders.HoverboardBuilder)
local HoverboardFx = require(Shared.Builders.HoverboardFx)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local HoverboardView = require(script.Parent.Parent.UI.HoverboardView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)
local CleaningController = require(script.Parent.CleaningController)
local ElevatorController = require(script.Parent.ElevatorController)

local HoverboardController = {}

HoverboardController.ShowRange = 150 -- studs: farther boards aren't built
HoverboardController.FxRange = 80 -- studs: farther boards get no particles / trails
HoverboardController.LodInterval = 0.3
HoverboardController.PoolPerBoard = 3
HoverboardController.LiteRiders = 4 -- more riders with effects than this: lite effects
HoverboardController.Key = Enum.KeyCode.H
HoverboardController.GamepadKey = Enum.KeyCode.DPadRight

local RIDE_ACTION = "TerraForgeHoverRide"
local CLOSE_ACTION = "TerraForgeHoverClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local SEND_LOCK = 1
local RIDE_LOCK = 0.35
local MESSAGE_TIME = 5
local BOB_HEIGHT = 0.09
local BOB_SPEED = 2.6
local MESSAGE_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
}

type Rider = {
	Player: Player,
	Character: Model,
	BoardId: string,
	Speed: number,
	Model: Model?,
	Weld: Weld?,
	Fx: HoverboardFx.FxSet?,
	Phase: number,
	Pitch: number,
	Roll: number,
	Yaw: number?,
}

local player = Players.LocalPlayer
local refs: HoverboardView.Refs? = nil
local side: HoverboardView.SideButton? = nil
local ride: HoverboardView.RideButton? = nil
local isOpen = false
local lockedUntil = 0
local rideLockedUntil = 0
local messageToken = 0
local progress: NumberValue? = nil
local animTween: Tween? = nil
local riders: { [Player]: Rider } = {}
local pools: { [string]: { Model } } = {}
local folder: Folder? = nil
local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local poseTrack: AnimationTrack? = nil
local poseConnection: RBXScriptConnection? = nil
local silenced: { AnimationTrack } = {}

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function snapshotBoards(): ({ [string]: boolean }, string, number)
	local snapshot = StateController.get()
	local record = snapshot and snapshot.Hoverboards
	local owned = HoverboardView.ownedSet(if type(record) == "table" then record.Owned else nil)
	local equipped = if type(record) == "table" and type(record.Equipped) == "string" then record.Equipped else ""
	local coins = if snapshot and type(snapshot.Coins) == "number" then snapshot.Coins else 0
	return owned, equipped, coins
end

-- True while your own character stands on a board.
function HoverboardController.isRiding(): boolean
	local character = player.Character
	return character ~= nil and HoverboardData.get(character:GetAttribute(HoverboardData.Attribute)) ~= nil
end

function HoverboardController.isOpen(): boolean
	return isOpen
end

---------------------------------------------------------------- the riding pose

local function stopPose()
	if poseConnection then
		poseConnection:Disconnect()
		poseConnection = nil
	end
	local track = poseTrack
	poseTrack = nil
	if track then
		track:Stop(0.2)
		task.delay(0.3, function()
			track:Destroy()
		end)
	end
	for _, silencedTrack in silenced do
		if silencedTrack.IsPlaying then
			silencedTrack:AdjustWeight(1, 0.2)
		end
	end
	table.clear(silenced)
end

local function animationIds(animate: Instance, names: { string }): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	for _, name in names do
		local holder = animate:FindFirstChild(name)
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("Animation") then
					ids[child.AnimationId] = true
				end
			end
		end
	end
	return ids
end

local function startPose(character: Model)
	stopPose()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = character:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	if not animator or not animate or not idle then
		return
	end
	local animation: Animation? = nil
	for _, child in idle:GetChildren() do
		if child:IsA("Animation") then
			animation = child
			break
		end
	end
	if not animation then
		return
	end
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation :: Animation)
	end)
	if not ok or not track then
		return
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.2)
	poseTrack = track
	local moving = animationIds(animate, { "walk", "run" })
	local function quiet(other: AnimationTrack)
		if other ~= track and other.Animation and moving[other.Animation.AnimationId] then
			other:AdjustWeight(0.001, 0.1)
			if not table.find(silenced, other) then
				table.insert(silenced, other)
			end
		end
	end
	for _, playing in animator:GetPlayingAnimationTracks() do
		quiet(playing)
	end
	poseConnection = animator.AnimationPlayed:Connect(quiet)
end

---------------------------------------------------------------- boards under the riders

local function ensureFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ClientHoverboards"
	made.Parent = Workspace
	folder = made
	return made
end

local function acquireModel(boardId: string): Model
	local pool = pools[boardId]
	if pool and #pool > 0 then
		return table.remove(pool) :: Model
	end
	local model = HoverboardBuilder.build(boardId)
	HoverboardBuilder.rig(model)
	return model
end

local function releaseModel(boardId: string, model: Model)
	model.Parent = nil
	local pool = pools[boardId]
	if not pool then
		pool = {}
		pools[boardId] = pool
	end
	if #pool < HoverboardController.PoolPerBoard then
		table.insert(pool, model)
	else
		model:Destroy()
	end
end

-- Where the board's Root sits under a character (the deck top at the feet), or nil.
local function boardOffset(character: Model): CFrame?
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return nil
	end
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
	return CFrame.new(0, -(root.Size.Y / 2 + humanoid.HipHeight + legs), 0)
end

local function hideFx(rider: Rider)
	local set = rider.Fx
	rider.Fx = nil
	if set then
		HoverboardFx.release(set)
	end
end

local function hide(rider: Rider)
	hideFx(rider)
	local weld = rider.Weld
	rider.Weld = nil
	if weld then
		weld:Destroy()
	end
	local model = rider.Model
	rider.Model = nil
	if model then
		releaseModel(rider.BoardId, model)
	end
end

local function show(rider: Rider): boolean
	if rider.Model then
		return true
	end
	local root = rider.Character:FindFirstChild("HumanoidRootPart")
	local offset = boardOffset(rider.Character)
	if not root or not root:IsA("BasePart") or not offset then
		return false
	end
	local model = acquireModel(rider.BoardId)
	local boardRoot = model.PrimaryPart
	if not boardRoot then
		model:Destroy()
		return false
	end
	local weld = Instance.new("Weld")
	weld.Name = "HoverboardWeld"
	weld.Part0 = root
	weld.Part1 = boardRoot
	weld.C0 = offset
	weld.Parent = boardRoot
	model.Parent = ensureFolder()
	rider.Model = model
	rider.Weld = weld
	return true
end

local function fxCount(): number
	local n = 0
	for _, rider in riders do
		if rider.Fx then
			n += 1
		end
	end
	return n
end

local function showFx(rider: Rider)
	local model = rider.Model
	if rider.Fx or not model then
		return
	end
	local lite = isPhone() or fxCount() >= HoverboardController.LiteRiders
	local set = HoverboardFx.acquire(rider.BoardId, lite)
	if not set then
		return
	end
	if HoverboardFx.mount(set, model) then
		rider.Fx = set
	else
		HoverboardFx.release(set)
	end
end

local function removeRider(p: Player)
	local rider = riders[p]
	if rider then
		hide(rider)
		riders[p] = nil
	end
	if p == player then
		stopPose()
	end
end

local updateRideButton: () -> () = function() end

-- Builds / drops the rider entry from the character's attribute.
local function refreshRider(p: Player)
	local character = p.Character
	local board = if character then HoverboardData.get(character:GetAttribute(HoverboardData.Attribute)) else nil
	local existing: Rider? = riders[p]
	if existing and (not board or existing.Character ~= character or existing.BoardId ~= board.Id) then
		removeRider(p)
		existing = nil
	end
	if board and character and not existing then
		local rider: Rider = {
			Player = p,
			Character = character,
			BoardId = board.Id,
			Speed = board.Speed,
			Model = nil,
			Weld = nil,
			Fx = nil,
			Phase = math.random() * math.pi * 2,
			Pitch = 0,
			Roll = 0,
			Yaw = nil,
		}
		riders[p] = rider
		if p == player then
			show(rider)
			startPose(character)
		end
	end
	if p == player then
		updateRideButton()
	end
end

local function watchCharacter(p: Player, character: Model)
	if watched[character] then
		refreshRider(p)
		return
	end
	watched[character] = true
	character:GetAttributeChangedSignal(HoverboardData.Attribute):Connect(function()
		refreshRider(p)
	end)
	refreshRider(p)
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(function(character: Model)
		watchCharacter(p, character)
	end)
	p.CharacterRemoving:Connect(function()
		removeRider(p)
	end)
	if p.Character then
		watchCharacter(p, p.Character)
	end
end

-- Every LodInterval: boards in / out of range, streamed-out characters, effects on / off.
local function lodStep()
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	-- characters that streamed in with the attribute already set
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if character and not riders[p] and character:GetAttribute(HoverboardData.Attribute) ~= nil then
			watchCharacter(p, character)
		end
	end
	local stale: { Player } = {}
	for p, rider in riders do
		if p.Parent == nil or p.Character ~= rider.Character then
			table.insert(stale, p)
		end
	end
	-- stale riders are rebuilt here, between the loops (no keys added while iterating)
	for _, p in stale do
		removeRider(p)
		if p.Parent then
			refreshRider(p)
		end
	end
	for p, rider in riders do
		local root = rider.Character.Parent and rider.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			hide(rider)
			continue
		end
		local isLocal = p == player
		local distance = (root.Position - focus).Magnitude
		if isLocal or distance <= HoverboardController.ShowRange then
			show(rider)
		else
			hide(rider)
		end
		if rider.Model and (isLocal or distance <= HoverboardController.FxRange) then
			showFx(rider)
			local set = rider.Fx
			if set then
				local velocity = root.AssemblyLinearVelocity
				local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				HoverboardFx.setActive(set, true, math.max(0.2, math.clamp(speed / rider.Speed, 0, 1)))
			end
		else
			hideFx(rider)
		end
	end
end

-- Every frame: bob, lean and roll of the boards on screen.
local function animate(dt: number)
	local now = os.clock()
	for _, rider in riders do
		local weld = rider.Weld
		local root = weld and weld.Part0
		if weld and root then
			local offset = boardOffset(rider.Character)
			if offset then
				local velocity = root.AssemblyLinearVelocity
				local speed01 = math.clamp(Vector3.new(velocity.X, 0, velocity.Z).Magnitude / rider.Speed, 0, 1)
				local look = root.CFrame.LookVector
				local yaw = math.atan2(look.X, look.Z)
				local last = rider.Yaw or yaw
				local turn = (yaw - last + math.pi) % (2 * math.pi) - math.pi
				rider.Yaw = yaw
				local rate = if dt > 0 then turn / dt else 0
				local k = math.min(1, dt * 6)
				rider.Roll += (math.clamp(rate * 0.07, -0.22, 0.22) - rider.Roll) * k
				rider.Pitch += (speed01 * 0.07 - rider.Pitch) * math.min(1, dt * 4)
				local bob = math.sin(now * BOB_SPEED + rider.Phase) * BOB_HEIGHT * (1 - 0.5 * speed01)
				weld.C0 = offset * CFrame.new(0, bob, 0) * CFrame.Angles(rider.Pitch, 0, rider.Roll)
			end
		end
	end
end

---------------------------------------------------------------- RIDE

local function rideHint(): (string, string)
	if usingGamepad() then
		local ok, image = pcall(function(): string
			return UserInputService:GetImageForKeyCode(HoverboardController.GamepadKey)
		end)
		return "", if ok and type(image) == "string" then image else ""
	elseif isPhone() then
		return "", ""
	end
	return "H", ""
end

updateRideButton = function()
	local button = ride
	if not button then
		return
	end
	local _, equipped = snapshotBoards()
	local riding = HoverboardController.isRiding()
	button.Holder.Visible = equipped ~= "" or riding
	local hint, glyph = rideHint()
	HoverboardView.setRiding(button, riding, hint, glyph)
end

local function showMessage(text: string, kind: string?)
	local view = refs
	if not view then
		return
	end
	messageToken += 1
	local token = messageToken
	HoverboardView.showMessage(view, text, MESSAGE_COLORS[kind or "Info"] or Theme.Info)
	task.delay(MESSAGE_TIME, function()
		if token == messageToken and refs then
			HoverboardView.hideMessage(refs)
		end
	end)
end

-- The RIDE button / H / D-pad Right: on or off the equipped board (no board: the panel opens).
function HoverboardController.toggleRide()
	local _, equipped = snapshotBoards()
	local riding = HoverboardController.isRiding()
	if equipped == "" and not riding then
		HudController.toast("Get a hoverboard first!", "Info")
		HoverboardController.open()
		return
	end
	if PlayerControls.owner() ~= nil or CleaningController.isActive() then
		return
	end
	local now = os.clock()
	if now < rideLockedUntil then
		return
	end
	rideLockedUntil = now + RIDE_LOCK
	Net.send("HoverboardAction", { Action = "Ride", On = not riding })
	Sfx.play("UIClick")
end

local function onRideKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	-- while a menu has the gamepad selection the D-pad moves it: leave it alone
	if input.KeyCode == HoverboardController.GamepadKey and GuiService.SelectedObject ~= nil then
		return Enum.ContextActionResult.Pass
	end
	HoverboardController.toggleRide()
	return Enum.ContextActionResult.Sink
end

---------------------------------------------------------------- the panel

local function locked(): boolean
	return os.clock() < lockedUntil
end

local function send(payload: { [string]: any })
	lockedUntil = os.clock() + SEND_LOCK
	Net.send("HoverboardAction", payload)
	Sfx.play("UIClick")
end

local function refresh()
	local view = refs
	if not view then
		return
	end
	local owned, equipped, coins = snapshotBoards()
	HoverboardView.setCards(view, owned, equipped, coins)
end

local function fit(view: HoverboardView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = isPhone() or scale <= 0.75 or size.Y < 520
	HoverboardView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function applyHint(view: HoverboardView.Refs)
	if usingGamepad() then
		local ok, image = pcall(function(): string
			return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
		end)
		view.HintGlyph.Image = if ok and type(image) == "string" then image else ""
		HoverboardView.setHint(view, "Gamepad", "Choose a board · B: close")
	elseif isPhone() then
		HoverboardView.setHint(view, "Touch", "Tap a card")
	else
		HoverboardView.setHint(view, "Mouse", "Click a card · H: ride · Backspace: close")
	end
end

local function selectDefault(view: HoverboardView.Refs)
	if usingGamepad() and isOpen then
		GuiService.SelectedObject = HoverboardView.firstButton(view)
	end
end

local function onCard(card: HoverboardView.Card)
	if not isOpen then
		return
	end
	local board = card.Board
	local state = card.State
	if state == "Buy" then
		if not locked() then
			send({ Action = "Buy", Board = board.Id })
		end
	elseif state == "BuyLocked" then
		local _, _, coins = snapshotBoards()
		local missing = math.max(1, (board.Price or 0) - coins)
		showMessage(`The {board.Name} costs {Format.money(board.Price or 0)}. You need {Format.money(missing)} more.`, "Deny")
	elseif state == "Equip" then
		if not locked() then
			send({ Action = "Equip", Board = board.Id })
		end
	elseif state == "Robux" then
		local id = HoverboardData.productId(board)
		if HoverboardData.canPrompt(board) and id > 0 then
			Sfx.play("UIClick")
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, id)
			end)
		end
	elseif state == "Soon" then
		showMessage(`The {board.Name} is coming soon!`, "Info")
	else
		showMessage(`The {board.Name} is your board. Press RIDE to hover.`, "Info")
	end
end

local function stopAnimation()
	local tween = animTween
	animTween = nil
	if tween then
		tween:Cancel()
	end
end

local function ensureProgress(): NumberValue
	local existing = progress
	if existing then
		return existing
	end
	local value = Instance.new("NumberValue")
	value.Name = "HoverboardsOpening"
	value.Value = HoverboardView.OpenTime
	value.Changed:Connect(function(seconds: number)
		local view = refs
		if view then
			HoverboardView.pose(view, seconds)
		end
	end)
	progress = value
	return value
end

local function play(to: number, seconds: number, done: (() -> ())?)
	stopAnimation()
	local value = ensureProgress()
	local tween = TweenService:Create(value, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Value = to })
	animTween = tween
	tween.Completed:Connect(function()
		if animTween == tween then
			animTween = nil
			if done then
				done()
			end
		end
	end)
	tween:Play()
end

local function ensureView(): HoverboardView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = HoverboardView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		HoverboardController.close()
		Sfx.play("UIClick")
	end)
	for _, card in view.Cards do
		card.Button.Activated:Connect(function()
			onCard(card)
		end)
	end
	refs = view
	return view
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	HoverboardController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

function HoverboardController.open()
	local view = ensureView()
	if isOpen then
		refresh()
		return
	end
	isOpen = true
	fit(view)
	HoverboardView.hideMessage(view)
	applyHint(view)
	refresh()
	view.Gui.Enabled = true
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ensureProgress().Value = 0
	HoverboardView.pose(view, 0)
	play(HoverboardView.OpenTime, HoverboardView.OpenTime)
	selectDefault(view)
	Sfx.play("UIClick")
end

function HoverboardController.close(instant: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if not view then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) then
		GuiService.SelectedObject = nil
	end
	local gui = view.Gui
	if instant then
		stopAnimation()
		gui.Enabled = false
		return
	end
	local value = ensureProgress()
	play(0, HoverboardView.CloseTime * value.Value / HoverboardView.OpenTime, function()
		if not isOpen then
			gui.Enabled = false
		end
	end)
end

---------------------------------------------------------------- side menu button

local function bounce(scale: UIScale, target: number, seconds: number)
	TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end

local function hookBounce(button: GuiButton, scale: UIScale)
	button.MouseEnter:Connect(function()
		bounce(scale, 1.08, 0.18)
	end)
	button.MouseLeave:Connect(function()
		bounce(scale, 1, 0.18)
	end)
	button.SelectionGained:Connect(function()
		bounce(scale, 1.08, 0.18)
	end)
	button.SelectionLost:Connect(function()
		bounce(scale, 1, 0.18)
	end)
	button.MouseButton1Down:Connect(function()
		bounce(scale, 0.9, 0.08)
	end)
	button.MouseButton1Up:Connect(function()
		bounce(scale, 1, 0.25)
	end)
end

local function buildSide()
	-- ElevatorController builds the side menu in its start(): wait for it a little
	local menu: Frame? = nil
	for _ = 1, 60 do
		menu = ElevatorController.sideMenu()
		if menu then
			break
		end
		task.wait(0.25)
	end
	if not menu then
		warn("[HoverboardController] no side menu: the Boards button is missing")
		return
	end
	local button = HoverboardView.sideButton(menu, HoverboardView.SideButtonSize)
	button.Holder.LayoutOrder = 20
	side = button
	hookBounce(button.Button, button.Scale)
	button.Button.Activated:Connect(function()
		if isOpen then
			HoverboardController.close()
		else
			HoverboardController.open()
		end
	end)
end

local function buildRide()
	local hud = HudController.refs()
	local button = HoverboardView.rideButton(hud.Menu)
	ride = button
	hookBounce(button.Button, button.Scale)
	button.Button.Activated:Connect(HoverboardController.toggleRide)
	updateRideButton()
end

---------------------------------------------------------------- lifecycle

function HoverboardController.init()
	Net.listen("HoverboardResult", function(result)
		if type(result) ~= "table" then
			return
		end
		-- an answer arrived: the next request may go
		lockedUntil = 0
		if result.Action == "Ride" and result.Ok == false and result.Reason == "NoBoard" then
			HoverboardController.open()
		end
	end)
	Net.listen("Notify", function(message)
		if isOpen and type(message) == "table" and type(message.Text) == "string" then
			showMessage(message.Text, message.Kind)
		end
	end)
	StateController.onChanged(function()
		lockedUntil = 0
		refresh()
		updateRideButton()
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
		-- never grant here (the server's ProcessReceipt does): only a friendly line
		if userId == player.UserId and purchased and isOpen then
			showMessage("Thank you! Unlocking your board...", "Reward")
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		updateRideButton()
		local view = refs
		if view and isOpen then
			applyHint(view)
			selectDefault(view)
		end
		local button = side
		if button then
			button.Glyph.Visible = false
		end
	end)
	player.CharacterRemoving:Connect(function()
		HoverboardController.close(true)
	end)
end

function HoverboardController.start()
	buildRide()
	ContextActionService:BindAction(RIDE_ACTION, onRideKey, false, HoverboardController.Key, HoverboardController.GamepadKey)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerRemoving:Connect(removeRider)
	RunService.RenderStepped:Connect(animate)
	task.spawn(function()
		while true do
			task.wait(HoverboardController.LodInterval)
			local ok, err: any = pcall(lodStep)
			if not ok then
				warn("[HoverboardController] " .. tostring(err))
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
	buildSide()
end

return HoverboardController
