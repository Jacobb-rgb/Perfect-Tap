--[[
	WheelController: the daily wheel of fortune on this screen (step 7).

	- Opens on OpenUI "Wheel" (the "Spin & Win" prompt at the EmberChest,
	  added by WheelService) or the HUD's FREE SPIN! chip (shown only while
	  the free spin is ready, anywhere). The screen (WheelView) shows the
	  player's 8 segments with their exact odds, what each pays them, and
	  the countdown from State.Wheel.NextSpinAt (os.time() seconds, compared
	  with Workspace:GetServerTimeNow()).
	- SPIN! sends WheelAction "Spin" (one request per WheelConfig.
	  ClientCooldown; the button waits for the answer). WheelResult: the
	  disc turns WheelView.Turns times and stops with the won segment under
	  the pointer (WheelConfig.SpinSeconds, ticking past every segment),
	  then the prize card, confetti and the row lights up. A refusal
	  (ActionResult "NotReady") or no answer within WheelConfig.ResultTimeout
	  gives the button back; a WheelResult that comes later is still shown
	  (or, with the screen closed, a toast says what was won).
	- The big lobby wheel (SpinWheel's "Wheel" sub-model, tag Spin) gets a
	  celebration spin on THIS screen only while the screen wheel turns:
	  fast, then slowing back to its idle turn, with confetti from its hub
	  when the prize shows. It is decoration only (WheelConfig: 10 equal
	  segments with made-up icons), so it never stops on purpose at a
	  "result": the prize is shown on the 8-segment screen wheel alone. To
	  turn it, its Spin tag is taken off locally (DecorController lets go)
	  and this controller keeps turning it at its own SpinSpeed afterwards.
	- Closes with the X, B (gamepad), Backspace, respawning or another big
	  panel opening; it never locks movement. Gamepads start on SPIN! (or
	  the X when the spin isn't ready); the odds list is selectable to scroll.
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
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local WheelConfig = require(Shared.Config.WheelConfig)
local Net = require(Shared.Net)
local WheelView = require(script.Parent.Parent.UI.WheelView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)

local WheelController = {}

type Panel = { isOpen: () -> boolean, close: () -> () }

local CLOSE_ACTION = "TerraForgeWheelClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local OTHER_PANELS = {
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"TechShopController",
	"ArtifactController",
}
local RESTRICTED_ATTRIBUTE = "PaidRandomRestricted" -- set by the server's Policy
local SPIN_TAG = "Spin"
local CELEBRATE_SPEED = 7 -- rad/s at the top of the lobby wheel's celebration

local player = Players.LocalPlayer
local refs: WheelView.Refs? = nil
local chip: WheelView.ChipRefs? = nil
local open = false
local openedAt = 0
local busy = false -- a spin is in flight or the disc is turning
local waitUntil = 0 -- os.clock() when an unanswered spin is given up on
local lastSent = -math.huge
local animating = false
local animToken = 0
local noCapsulesShown: boolean? = nil
local litId: string? = nil -- the odds row of the last prize
local rowsKey = "" -- what the odds rows show now (rebuilt only when it changes)
local current: { [string]: any }? = nil -- the WheelResult the disc is turning to
local others: { Panel }? = nil

-- the lobby wheel(s) this controller turns: model -> spinner
type Spinner = { Pivot: CFrame, Parts: { { Part: BasePart, Offset: CFrame } }, Angle: number, Idle: number, Boost: number }
local wheels: { [Model]: Spinner } = {}
local wheelLoop: RBXScriptConnection? = nil

function WheelController.isOpen(): boolean
	return open
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function otherPanels(): { Panel }
	local cached = others
	if cached then
		return cached
	end
	local list: { Panel } = {}
	for _, name in OTHER_PANELS do
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, controller = pcall(require, module :: any)
			if ok and type(controller) == "table" then
				local c = controller :: any
				if c ~= WheelController and type(c.isOpen) == "function" and type(c.close) == "function" then
					table.insert(list, c :: Panel)
				end
			end
		end
	end
	others = list
	return list
end

---------------------------------------------------------------- state

local function noCapsules(): boolean
	-- unknown (no attribute yet) counts as restricted, like the server's strict default
	return CapsuleConfig.allRestricted(player:GetAttribute(RESTRICTED_ATTRIBUTE) ~= false)
end

-- What the odds rows need (WheelView.Info) from the latest State snapshot.
function WheelController.info(state: { [string]: any }?, restricted: boolean): WheelView.Info
	local s: { [string]: any } = state or {}
	local perks = if type(s.Perks) == "table" then s.Perks else {}
	local bonuses = if type(s.Bonuses) == "table" then s.Bonuses else {}
	local income = tonumber(s.Income) or 0
	return {
		NoCapsules = restricted,
		Income = if income == income then income else 0,
		Ore = {
			BlasterLevel = tonumber(s.BlasterLevel) or 1,
			BestIncome = WheelConfig.bestIncome(s.Discovered),
			Vip = perks.ForgeVip == true,
		},
		TripleLucky = bonuses.TripleLucky == true,
	}
end

-- Seconds until the free spin (0 = ready) from the latest snapshot.
local function secondsLeft(): number
	local state = StateController.get()
	local wheel = if state and type(state.Wheel) == "table" then state.Wheel else nil
	return WheelConfig.secondsLeft(if wheel then wheel.NextSpinAt else 0, serverNow())
end

local function isReady(): boolean
	return StateController.get() ~= nil and secondsLeft() <= 0
end

---------------------------------------------------------------- the lobby wheel

local function lobbyWheels(): { Model }
	local list: { Model } = {}
	for _, instance in CollectionService:GetTagged(SPIN_TAG) do
		local parent = instance.Parent
		if instance:IsA("Model") and instance.Name == "Wheel" and parent and parent.Name == WheelConfig.ModelName then
			table.insert(list, instance)
		end
	end
	for model in wheels do
		if model.Parent and not table.find(list, model) then
			table.insert(list, model)
		end
	end
	return list
end

local function stepWheels(dt: number)
	for model, spinner in wheels do
		if not model.Parent then
			wheels[model] = nil
			continue
		end
		spinner.Boost = math.max(0, spinner.Boost - dt)
		local speed = spinner.Idle
		if spinner.Boost > 0 then
			-- quick spin-up, then a long ease back down to the idle turn
			local total = WheelConfig.SpinSeconds
			local t = 1 - spinner.Boost / total
			local k = if t < 0.08 then t / 0.08 else 1 - WheelView.ease((t - 0.08) / 0.92)
			speed = spinner.Idle + (CELEBRATE_SPEED - spinner.Idle) * k
		end
		spinner.Angle += speed * dt
		local cf = spinner.Pivot * CFrame.Angles(0, spinner.Angle, 0)
		for _, entry in spinner.Parts do
			entry.Part.CFrame = cf * entry.Offset
		end
	end
	if next(wheels) == nil and wheelLoop then
		wheelLoop:Disconnect()
		wheelLoop = nil
	end
end

-- Takes a lobby wheel over from DecorController (its Spin tag off, locally).
local function takeOver(model: Model): Spinner
	model:RemoveTag(SPIN_TAG)
	local pivot = model:GetPivot()
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { Part = d, Offset = pivot:ToObjectSpace(d.CFrame) })
		end
	end
	local idle = model:GetAttribute("SpinSpeed")
	local spinner: Spinner = { Pivot = pivot, Parts = parts, Angle = 0, Idle = if type(idle) == "number" then idle else 0.6, Boost = 0 }
	wheels[model] = spinner
	return spinner
end

-- Gives the lobby wheel a celebration spin (it keeps its idle turn afterwards).
local function celebrate()
	for _, model in lobbyWheels() do
		local spinner = wheels[model] or takeOver(model)
		spinner.Boost = WheelConfig.SpinSeconds
	end
	if next(wheels) ~= nil and not wheelLoop then
		wheelLoop = RunService.RenderStepped:Connect(stepWheels)
	end
end

-- Confetti out of the lobby wheel's hub (pooled bursts).
local function lobbyConfetti()
	for model in wheels do
		local hub = model.PrimaryPart
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hub and root and (hub.Position - root.Position).Magnitude < 160 then
			for i, color in WheelView.ConfettiColors do
				if i <= 4 then
					Vfx.burst("Burst", hub.Position, 18, color)
				end
			end
		end
	end
end

---------------------------------------------------------------- the screen

local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

local function updateHint(view: WheelView.Refs)
	if usingGamepad() then
		view.Hint.Text = `{padName(Enum.KeyCode.ButtonA)}: spin  ·  {padName(Enum.KeyCode.ButtonB)}: close`
	elseif isTouch() then
		view.Hint.Text = "Tap SPIN!"
	else
		view.Hint.Text = "Click SPIN!  ·  Backspace: close"
	end
end

local function refresh()
	local view = refs
	if not view or not open then
		return
	end
	local restricted = noCapsules()
	if noCapsulesShown ~= restricted and not animating then
		noCapsulesShown = restricted
		WheelView.setSegments(view, WheelConfig.segments(restricted))
	end
	-- the rows only change with the player's income, blaster, finds or luck
	local rows = WheelView.rows(WheelController.info(StateController.get(), restricted))
	local parts = {}
	for _, row in rows do
		table.insert(parts, row.Id .. "=" .. row.Detail)
	end
	local key = table.concat(parts, "|")
	if key ~= rowsKey then
		rowsKey = key
		WheelView.setRows(view, rows)
	end
	WheelView.highlight(view, litId)
	if not animating then
		WheelView.setReady(view, isReady(), secondsLeft(), busy)
	end
end

local function fit(view: WheelView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	WheelView.layout(view, size.X / scale, (size.Y - inset.Y) / scale)
end

local function selectDefault(view: WheelView.Refs)
	if not usingGamepad() then
		return
	end
	if view.Result.Visible then
		GuiService.SelectedObject = view.ResultOk
	elseif isReady() and not busy then
		GuiService.SelectedObject = view.Spin
	else
		GuiService.SelectedObject = view.Close
	end
end

local function compactNow(): boolean
	return isTouch() or GuiService:IsTenFootInterface() or HudController.uiScale() <= 0.75
end

local onSpin: () -> ()

local function ensureView(): WheelView.Refs
	local existing = refs
	if existing and existing.Compact == compactNow() then
		return existing
	end
	if existing then
		existing.Gui:Destroy()
	end
	local view = WheelView.build(compactNow())
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		WheelController.close()
		Sfx.play("UIClick")
	end)
	view.Spin.Activated:Connect(function()
		onSpin()
	end)
	view.ResultOk.Activated:Connect(function()
		WheelView.hideResult(view)
		Sfx.play("UIClick")
		selectDefault(view)
	end)
	refs = view
	noCapsulesShown = nil
	rowsKey = ""
	return view
end

---------------------------------------------------------------- spinning

-- Lets the confetti pieces fall and fade (a short tween each).
local function dropConfetti(view: WheelView.Refs)
	for _, piece in WheelView.confetti(view, math.floor(os.clock() * 1000) % 100000 + 1) do
		local fall = TweenInfo.new(1.4 + math.random() * 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local target = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.15, 1.1)
		TweenService:Create(piece, fall, { Position = target, Rotation = piece.Rotation + 360 * (math.random() - 0.5) }):Play()
	end
end

local function finish(view: WheelView.Refs, result: { [string]: any }, segmentColor: Color3)
	animating = false
	busy = false
	current = nil
	local prize, detail = WheelView.prizeText(result)
	litId = tostring(result.Id)
	WheelView.highlight(view, litId)
	WheelView.showResult(view, prize, detail, segmentColor)
	dropConfetti(view)
	lobbyConfetti()
	Sfx.play("Reveal")
	refresh()
	selectDefault(view)
end

-- Turns the screen disc to the won segment, then shows the prize.
local function animate(view: WheelView.Refs, result: { [string]: any })
	local id = tostring(result.Id)
	local segment = WheelConfig.ById[id]
	if not segment then
		busy = false
		refresh()
		return
	end
	-- a substitute id means the player's wheel has the substitutes (and the other way round)
	local substitute = WheelConfig.Segments[segment.Index] ~= segment
	if view.SegmentIds[segment.Index] ~= id then
		noCapsulesShown = substitute
		WheelView.setSegments(view, WheelConfig.segments(substitute))
	end
	WheelView.hideResult(view)
	litId = nil
	WheelView.highlight(view, nil)
	current = result
	animating = true
	busy = true
	WheelView.setReady(view, false, 0, true)
	animToken += 1
	local token = animToken
	local count = #view.SegmentIds
	local from = view.Disc.Rotation % 360
	local target = WheelView.spinTarget(from, segment.Index, count, WheelView.Turns, math.random() - 0.5)
	local started = os.clock()
	local lastSegment = WheelView.segmentAt(from, count)
	celebrate()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if token ~= animToken or not open then
			connection:Disconnect()
			return
		end
		local t = (os.clock() - started) / WheelConfig.SpinSeconds
		local rotation = from + (target - from) * WheelView.ease(t)
		view.Disc.Rotation = rotation
		local now = WheelView.segmentAt(rotation, count)
		if now ~= lastSegment then
			lastSegment = now
			Sfx.play("BuildRotate")
			for i, stud in view.Studs do
				stud.BackgroundTransparency = if (i + now) % 2 == 0 then 0 else 0.6
			end
		end
		if t >= 1 then
			connection:Disconnect()
			view.Disc.Rotation = target % 360
			for _, stud in view.Studs do
				stud.BackgroundTransparency = 0
			end
			finish(view, result, segment.Color)
		end
	end)
end

local function onResult(payload: any)
	if type(payload) ~= "table" or type(payload.Id) ~= "string" then
		return
	end
	waitUntil = 0
	local view = refs
	if view and open then
		animate(view, payload)
	else
		busy = false
		local prize, detail = WheelView.prizeText(payload)
		HudController.toast(`Daily wheel: {prize}. {detail}`, "Reward")
	end
end

local function onActionResult(payload: any)
	if type(payload) ~= "table" or payload.Action ~= "Wheel" or payload.Ok == true then
		return
	end
	busy = false
	waitUntil = 0
	local reason = if type(payload.Reason) == "string" then WheelConfig.Reasons[payload.Reason] else nil
	local text = reason or "You can't spin right now"
	local view = refs
	if view and open then
		refresh()
		view.Status.Text = text
		Sfx.play("UIDeny")
	else
		HudController.toast(text, "Deny")
	end
end

onSpin = function()
	local view = refs
	if not view or not open or animating then
		return
	end
	if busy or os.clock() - lastSent < WheelConfig.ClientCooldown then
		Sfx.play("UIDeny")
		return
	end
	if not isReady() then
		view.Status.Text = "Next free spin in " .. WheelView.countdown(secondsLeft())
		Sfx.play("UIDeny")
		return
	end
	busy = true
	lastSent = os.clock()
	waitUntil = os.clock() + WheelConfig.ResultTimeout
	WheelView.setReady(view, false, 0, true)
	Sfx.play("UIClick")
	Net.send("WheelAction", "Spin")
end

---------------------------------------------------------------- open / close

function WheelController.close()
	if not open then
		return
	end
	open = false
	if animating then
		-- the spin went through: a toast says what it was
		animating = false
		busy = false
		animToken += 1
		local result = current
		current = nil
		if result then
			local prize, detail = WheelView.prizeText(result)
			HudController.toast(`Daily wheel: {prize}. {detail}`, "Reward")
		end
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		WheelView.hideResult(view)
		view.Gui.Enabled = false
	end
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not open then
		return Enum.ContextActionResult.Pass
	end
	local view = refs
	if view and view.Result.Visible then
		WheelView.hideResult(view)
		selectDefault(view)
	else
		WheelController.close()
	end
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

function WheelController.open()
	if open then
		refresh()
		return
	end
	local owner = PlayerControls.owner()
	if owner ~= nil then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return
	end
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	local view = ensureView()
	open = true
	openedAt = os.clock()
	fit(view)
	updateHint(view)
	WheelView.hideResult(view)
	view.Gui.Enabled = true
	refresh()
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	GuiService.SelectedObject = nil
	selectDefault(view)
	Sfx.play("UIClick")
	local scale = view.Panel:FindFirstChild("OpenPop") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = view.Panel
		scale = made
	end
	local s = scale :: UIScale
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- the chip

local function updateChip()
	local c = chip
	if not c then
		return
	end
	local show = isReady() and not open and not busy
	if c.Gui.Enabled ~= show then
		c.Gui.Enabled = show
		if show then
			Sfx.play("Discovery")
		end
	end
end

local function buildChip()
	local c = WheelView.buildChip(HudController.uiScale())
	c.Gui.Parent = player:WaitForChild("PlayerGui")
	c.Button.Activated:Connect(function()
		WheelController.open()
	end)
	chip = c
	-- a slow pulse so it reads as new
	local holder = c.Button.Parent :: Frame
	local pulse = Instance.new("UIScale")
	pulse.Name = "Pulse"
	pulse.Parent = holder
	TweenService:Create(pulse, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
end

-- Every 0.25 s: the countdown, an unanswered spin, the chip, other panels.
local function step()
	local view = refs
	if open and view then
		if busy and not animating and waitUntil > 0 and os.clock() > waitUntil then
			busy = false
			waitUntil = 0
			refresh()
			view.Status.Text = "No answer, try again"
		elseif not animating then
			WheelView.setReady(view, isReady(), secondsLeft(), busy)
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					WheelController.close()
					break
				end
			end
		end
	end
	updateChip()
end

---------------------------------------------------------------- lifecycle

function WheelController.init()
	Net.listen("OpenUI", function(kind)
		if kind == "Wheel" then
			WheelController.open()
		end
	end)
	Net.listen("WheelResult", onResult)
	Net.listen("ActionResult", onActionResult)
	StateController.onChanged(function()
		if open and not animating then
			refresh()
		end
		updateChip()
	end)
	player:GetAttributeChangedSignal(RESTRICTED_ATTRIBUTE):Connect(function()
		if open and not animating then
			refresh()
		end
	end)
	player.CharacterRemoving:Connect(function()
		WheelController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and open then
			updateHint(view)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and open then
				fit(view)
			end
			local c = chip
			if c then
				WheelView.placeChip(c, HudController.uiScale())
			end
		end)
	end
end

function WheelController.start()
	buildChip()
	while true do
		local ok, err = pcall(function()
			step()
		end)
		if not ok then
			warn("[WheelController] " .. tostring(err))
		end
		task.wait(0.25)
	end
end

return WheelController
