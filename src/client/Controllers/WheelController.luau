--[[
	WheelController: the daily wheel of fortune on this screen (step 7).

	- Opens on OpenUI "Wheel" (the "Spin & Win" prompt at the EmberChest,
	  added by WheelService) or the HUD's FREE SPIN! chip (a click / tap;
	  no gamepad shortcut of its own: the D-pad belongs to the side menu,
	  build mode and the teleport bar, and a gamepad reaches the chip with
	  the UI selection or spins at the chest). The chip shows only while
	  the free spin is ready AND the HUD itself shows: never over the
	  cleaning minigame, the Foundry moment or build mode (HUD hidden,
	  CleaningController.isActive, PlayerControls.owner), and the screen
	  doesn't open then either. The screen (WheelView) shows the
	  player's 8 segments with their exact odds, what each pays them, and
	  the countdown from State.Wheel.NextSpinAt (os.time() seconds, compared
	  with Workspace:GetServerTimeNow()). A row opens its details card (the
	  whole text, a capsule's chance of every golem); X, B or the row again
	  close it.
	- SPIN! sends WheelAction "Spin" (one request per WheelConfig.
	  ClientCooldown; the button waits for the answer). WheelResult: the
	  disc turns WheelView.Turns times and stops with the won segment under
	  the pointer (WheelConfig.SpinSeconds, ticking past every segment),
	  then the prize card, confetti and the row lights up. Meanwhile the
	  HUD's coin counter holds (HudController.holdCoins), so a coin prize
	  doesn't show in the balance before the wheel stops. A capsule prize
	  asks for its opening (WheelAction "Reveal") 1.5 s after the card,
	  only while the screen is still open; a free capsule opening
	  (CapsuleResult Free) closes the wheel screen, so the opening never
	  plays on top of it. A refusal (ActionResult
	  "NotReady") or no answer within WheelConfig.ResultTimeout gives the
	  button back; a WheelResult that comes later is still shown (or, with
	  the screen closed, a toast says what was won).
	- The big lobby wheel (SpinWheel's "Wheel" sub-model, tag Spin) keeps
	  its idle turn (DecorController): it is decoration with 10 made-up
	  segments (WheelConfig), so it must never look like it shows a result.
	  Only confetti comes out of its hub when the prize shows. Asked of the
	  lobby owner: rebuild its disc with WheelConfig's 8 segments; then it
	  can turn with WheelView.spinTarget to land on result.Segment.
	- Closes with the X, B (gamepad), Backspace, respawning or another big
	  panel opening (OtherPanels, plus the side menu's MenuPanels.Names
	  when that module is in the game); it never locks movement. Gamepads
	  start on SPIN! (or the X when the spin isn't ready); the rows are
	  selectable.
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
local CleaningController = require(script.Parent.CleaningController)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)

local WheelController = {}

type Panel = { isOpen: () -> boolean, close: () -> () }

local CLOSE_ACTION = "TerraForgeWheelClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local REVEAL_DELAY = 1.5 -- seconds after the prize card before a capsule's opening
-- Every big panel of the game so far (missing ones are skipped); the side
-- menu's MenuPanels.Names are added when that module is in the game.
WheelController.OtherPanels = {
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"TechShopController",
	"GearShopController",
	"GearController",
	"EnchantController",
	"BoostController",
	"CapsuleController",
	"GolemController",
	"ArtifactController",
	"CodexController",
	"SettingsController",
	"LeaderboardController",
	"StoreController",
}
local RESTRICTED_ATTRIBUTE = "PaidRandomRestricted" -- set by the server's Policy
local SPIN_TAG = "Spin"

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
local chipReady = false -- the free spin was ready at the last chip update

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

-- The names of every other big panel: OtherPanels plus the side menu's list.
function WheelController.panelNames(): { string }
	local names = table.clone(WheelController.OtherPanels)
	local util = script.Parent.Parent:FindFirstChild("Util")
	local menuPanels = util and util:FindFirstChild("MenuPanels")
	if menuPanels and menuPanels:IsA("ModuleScript") then
		local ok, module = pcall(require, menuPanels :: any)
		local listed = if ok and type(module) == "table" then (module :: any).Names else nil
		if type(listed) == "table" then
			for _, name in listed do
				if type(name) == "string" and not table.find(names, name) then
					table.insert(names, name)
				end
			end
		end
	end
	return names
end

local function otherPanels(): { Panel }
	local cached = others
	if cached then
		return cached
	end
	local list: { Panel } = {}
	for _, name in WheelController.panelNames() do
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

-- Something else has the screen: the cleaning minigame, build mode / the
-- anvil (PlayerControls), or the HUD is hidden (the Foundry moment, build
-- mode's top bar).
local function screenBusy(): boolean
	if CleaningController.isActive() or PlayerControls.owner() ~= nil then
		return true
	end
	local hud = HudController.refs()
	if hud and (not hud.Gui.Enabled or not hud.TopBar.Visible) then
		return true
	end
	return false
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

-- The lobby wheel(s): SpinWheel's "Wheel" sub-model (tag Spin). They keep
-- their idle turn; only confetti comes out of the hub.
local function lobbyWheels(): { Model }
	local list: { Model } = {}
	for _, instance in CollectionService:GetTagged(SPIN_TAG) do
		local parent = instance.Parent
		if instance:IsA("Model") and instance.Name == "Wheel" and parent and parent.Name == WheelConfig.ModelName then
			table.insert(list, instance)
		end
	end
	return list
end

-- Confetti out of the lobby wheel's hub (pooled bursts), when it is near.
local function lobbyConfetti()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, model in lobbyWheels() do
		local hub = model.PrimaryPart
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
		view.Hint.Text = `{padName(Enum.KeyCode.ButtonA)}: spin / details  ·  {padName(Enum.KeyCode.ButtonB)}: close`
	elseif isTouch() then
		view.Hint.Text = "Tap a row for details  ·  Tap SPIN!"
	else
		view.Hint.Text = "Click a row for details  ·  Backspace: close"
	end
end

-- A row opens its details card (the same row again, X or B close it).
local function toggleInfo(view: WheelView.Refs, id: string)
	if view.InfoId == id then
		WheelView.hideInfo(view)
		if usingGamepad() then
			GuiService.SelectedObject = view.Rows[id]
		end
	else
		WheelView.showInfo(view, id)
		if usingGamepad() then
			GuiService.SelectedObject = view.InfoClose
		end
	end
	WheelView.highlight(view, litId)
	Sfx.play("UIClick")
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
		local selected = GuiService.SelectedObject
		local selectedId = if selected and selected:IsDescendantOf(view.Odds) then selected.Name else nil
		local infoId = view.InfoId
		WheelView.setRows(view, rows)
		for id, button in view.Rows do
			button.Activated:Connect(function()
				toggleInfo(view, id)
			end)
		end
		-- an open card and a gamepad's selection stay on their row
		if infoId and view.RowData[infoId] then
			WheelView.showInfo(view, infoId)
		elseif infoId then
			WheelView.hideInfo(view)
		end
		if selectedId and view.Rows[selectedId] then
			GuiService.SelectedObject = view.Rows[selectedId]
		end
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
	view.InfoClose.Activated:Connect(function()
		local id = view.InfoId
		if id then
			toggleInfo(view, id)
		end
	end)
	view.Odds:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		WheelView.updateMore(view)
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

-- Does this prize change the coin balance (the HUD holds it while the disc turns)?
local function paysCoins(result: { [string]: any }): boolean
	return result.Kind == "Coins" or (tonumber(result.Coins) or 0) > 0
end

local function finish(view: WheelView.Refs, result: { [string]: any }, segmentColor: Color3)
	animating = false
	busy = false
	current = nil
	HudController.releaseCoins()
	local prize, detail = WheelView.prizeText(result)
	litId = tostring(result.Id)
	WheelView.highlight(view, litId)
	WheelView.showResult(view, prize, detail, segmentColor)
	dropConfetti(view)
	lobbyConfetti()
	Sfx.play("Reveal")
	refresh()
	selectDefault(view)
	-- a capsule prize: its opening, if the screen is still open by then
	if result.Kind == "Capsule" and type(result.Golem) == "table" then
		local token = animToken
		task.delay(REVEAL_DELAY, function()
			if open and token == animToken then
				Net.send("WheelAction", "Reveal")
			end
		end)
	end
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
	WheelView.hideInfo(view)
	litId = nil
	WheelView.highlight(view, nil)
	current = result
	animating = true
	busy = true
	WheelView.setReady(view, false, 0, true)
	if paysCoins(result) then
		HudController.holdCoins(WheelConfig.SpinSeconds + 1)
	end
	animToken += 1
	local token = animToken
	local count = #view.SegmentIds
	local from = view.Disc.Rotation % 360
	local target = WheelView.spinTarget(from, segment.Index, count, WheelView.Turns, math.random() - 0.5)
	local started = os.clock()
	local lastSegment = WheelView.segmentAt(from, count)
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
		local result = current
		current = nil
		HudController.releaseCoins()
		if result then
			local prize, detail = WheelView.prizeText(result)
			HudController.toast(`Daily wheel: {prize}. {detail}`, "Reward")
		end
	end
	-- no capsule opening for a closed screen (the toast / card told it)
	animToken += 1
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		WheelView.hideResult(view)
		WheelView.hideInfo(view)
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
	elseif view and view.InfoId then
		toggleInfo(view, view.InfoId)
		return Enum.ContextActionResult.Sink
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
	if owner ~= nil or CleaningController.isActive() then
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
	local ready = isReady()
	local busyScreen = screenBusy()
	local show = WheelView.chipVisible(ready, open, busy, busyScreen)
	if c.Gui.Enabled ~= show then
		c.Gui.Enabled = show
	end
	-- the sound only when the spin BECOMES ready (not after every close, and
	-- not in the middle of the minigame: it chimes once the HUD is back)
	if ready and not chipReady and not open and not busyScreen then
		Sfx.play("Discovery")
	end
	if not busyScreen or not ready then
		chipReady = ready
	end
end

local function buildChip()
	local c = WheelView.buildChip(HudController.uiScale())
	c.Gui.Parent = player:WaitForChild("PlayerGui")
	c.Button.Activated:Connect(function()
		-- (a stray tap while something else has the screen does nothing)
		if screenBusy() then
			return
		end
		WheelController.open()
	end)
	chip = c
	-- a slow pulse so it reads as new
	local holder = c.Button.Parent :: Frame
	local pulse = Instance.new("UIScale")
	pulse.Name = "Pulse"
	pulse.Parent = holder
	TweenService:Create(pulse, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
	-- a spin that is already ready when the player joins doesn't chime at once
	chipReady = isReady()
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
	-- a free capsule's opening (the wheel's prize) plays instead of the wheel screen
	Net.listen("CapsuleResult", function(payload: any)
		if open and type(payload) == "table" and payload.Free == true then
			WheelController.close()
		end
	end)
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
	-- the chip follows the HUD (hidden by the minigame, the Foundry moment, build mode)
	local hud = HudController.refs()
	if hud then
		hud.Gui:GetPropertyChangedSignal("Enabled"):Connect(updateChip)
		hud.TopBar:GetPropertyChangedSignal("Visible"):Connect(updateChip)
	end
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
