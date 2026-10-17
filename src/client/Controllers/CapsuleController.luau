--[[
	CapsuleController: golem capsules on the client (step 7).

	- The shop panel (CapsuleView) opens on OpenUI "Capsules" (the
	  CapsuleStall's "Capsules" prompt, added by CapsuleService) and from the
	  golem inventory's CAPSULES button (CapsuleController.open). Opening
	  works anywhere, so the panel doesn't close when you walk away.
	  Tabs (click / tap, LB / RB): the capsules this player may open. The
	  cards come from the State snapshot and update live (coins count up,
	  the Triple Lucky banner counts down).
	- The panel and the opening are built for the layout of the moment
	  (phone / TV compact or PC) and laid out again, text sizes included,
	  when the screen changes.
	- OPEN x1 / x3 / x10 sends CapsuleAction ("Open", { Capsule, Count,
	  Lucky }): Lucky = the odds the card shows (CapsuleView.luckyNow); the
	  server rolls exactly those or refuses "OddsChanged".
	  One open waits at a time; CapsuleConfig.ClientCooldown seconds between
	  two; the buttons come back after CapsuleConfig.ResultTimeout with no
	  answer (a CapsuleResult that still comes is shown anyway: the coins and
	  golems on screen always come from the State push). A greyed-out button
	  answers locally (not enough coins, no room) and sends nothing. Royal
	  capsules (Robux) only have buttons while their products are live; the
	  server answers PurchasePrompt.
	- CapsuleResult plays the opening (CapsuleView.buildOpening): the
	  capsule shakes in its glow, cracks (cracks light up, the band turns the
	  color of the rarest golem inside), bursts with a flash, and each golem
	  pops out with rays in its rarity color, its name, rarity, bonus and
	  NEW! when it is the first of its kind (x1 and x3 one by one, then x3 as
	  a row of cards; x10 straight to a grid of 10 cards popping in). Click /
	  tap / A / Space / Enter skips a step; B / Backspace skips to the end;
	  at the end OK closes and OPEN AGAIN opens the same capsules again (the
	  note above says which odds it uses now: "TRIPLE LUCKY ODDS" or
	  "Triple Lucky ended: normal odds"). Results that arrive while one
	  plays wait their turn; a waiting one starts as soon as the end screen
	  shows.
	- The CapsuleStall's OddsBoard (SurfaceGui) shows the real odds per
	  rarity: every BoardSeconds the next capsule the player may open (with
	  the player's own Triple Lucky odds, refreshed within a second when it
	  starts or ends), filled locally by CapsuleView.fillBoard as soon as
	  the board streams in.
	- Closes with X, B, Backspace, respawning or another panel opening
	  (OTHER_PANELS: every panel controller known so far, also those of
	  the step 6-7 packages; missing ones are skipped).
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
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local CapsuleView = require(script.Parent.Parent.UI.CapsuleView)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local CapsuleController = {}

type Panel = { isOpen: () -> boolean, close: () -> () }
type Result = { Capsule: string, Count: number, Golems: { { Id: number, Kind: string } }, Lucky: boolean, Free: boolean? }

CapsuleController.BoardSeconds = 6 -- seconds each capsule's odds stay on the stall's board
CapsuleController.BoardTick = 1 -- seconds between two checks of the board (Triple Lucky starting / ending)
CapsuleController.BoardPixels = 120 -- the board's SurfaceGui PixelsPerStud (sharper text)

local CLOSE_ACTION = "TerraForgeCapsulesClose"
local TAB_ACTION = "TerraForgeCapsulesTab"
local SKIP_ACTION = "TerraForgeCapsuleSkip"
local SKIP_ALL_ACTION = "TerraForgeCapsuleSkipAll"
local STALL_TAG = "CapsuleStall"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local OPEN_PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- the overlay is above every panel
local TICK = 0.25
local STATUS_TIME = 3.5
local REVEAL_TIME = 1.7 -- seconds one golem stays before the next (or the end) when not skipped
local SHAKE_TIME = 1.35
local LUCKY_COLOR = Color3.fromRGB(255, 206, 72)
-- panels that own the middle of the screen: one at a time (the step 6-7
-- packages' panels too; a name that isn't in the game is skipped)
local OTHER_PANELS = {
	"GolemController",
	"TechShopController",
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"GearShopController",
	"BoostController",
	"EnchantController",
	"WheelController",
	"ArtifactController",
	"CodexController",
	"LeaderboardController",
	"SettingsController",
	"StoreController",
}

local player = Players.LocalPlayer
local refs: CapsuleView.Refs? = nil
local shown = false
local cards: { CapsuleView.Card } = {}
local tickConnection: RBXScriptConnection? = nil
local pendingUntil = 0
local pendingButton: TextButton? = nil
local lastSend = 0
local statusToken = 0
local openedAt = 0
local others: { Panel }? = nil
local stateAt: number? = nil -- server time the last State snapshot came (CapsuleView.luckyNow)

-- the opening overlay
local opening: CapsuleView.OpenRefs? = nil
local playing = false
local atEnd = false
local queue: { Result } = {}
local skipStep = false
local skipAll = false
local endDone = false -- the end screen's OK / B / a click (play() polls it)
local lastOpen: { Capsule: string, Count: number }? = nil
local againPending = false
local renderConnection: RBXScriptConnection? = nil
local shownResult: Result? = nil -- the result on the end screen
-- the golem in the hero viewport (animated every frame while it shows)
type Hero = { Model: Model, Start: number, Target: Vector3, Distance: number, RootHeight: number }
local hero: Hero? = nil

function CapsuleController.isOpen(): boolean
	return shown
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Paid random items are restricted for this player, or the policy isn't known yet.
local function restricted(): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
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
				if type(c.isOpen) == "function" and type(c.close) == "function" then
					table.insert(list, c :: Panel)
				end
			end
		end
	end
	others = list
	return list
end

-- A gamepad button's name on this platform ("A" / "Cross").
local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

---------------------------------------------------------------- the shop panel

local function status(text: string, color: Color3?)
	local view = refs
	if not view then
		return
	end
	CapsuleView.setStatus(view, text, color)
	statusToken += 1
	local token = statusToken
	task.delay(STATUS_TIME, function()
		local current = refs
		if statusToken == token and current then
			CapsuleView.setStatus(current, nil, nil)
		end
	end)
end

local function updateHint(view: CapsuleView.Refs)
	local sep = CapsuleView.Separator
	if usingGamepad() then
		CapsuleView.setHint(
			view,
			`{padName(Enum.KeyCode.ButtonL1)} / {padName(Enum.KeyCode.ButtonR1)}: capsule{sep}{padName(Enum.KeyCode.ButtonA)}: open{sep}{padName(
				Enum.KeyCode.ButtonB
			)}: close`
		)
	elseif isTouch() then
		CapsuleView.setHint(view, "Tap OPEN to wake golems")
	else
		CapsuleView.setHint(view, `Click OPEN to wake golems{sep}Backspace: close`)
	end
	local gamepad = usingGamepad()
	for i, image in view.TabGlyphs do
		image.Visible = gamepad
		if gamepad then
			image.Image = UserInputService:GetImageForKeyCode(if i == 1 then Enum.KeyCode.ButtonL1 else Enum.KeyCode.ButtonR1)
		end
	end
end

-- Phones and TVs get the compact layout (the same rule as the tech shop).
local function compactNow(): boolean
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return TechShopView.compactFor(isTouch(), GuiService:IsTenFootInterface(), HudController.uiScale(), size.Y)
end

-- The screen in design units (the HUD's scale, under the top bar).
local function room(): (number, number)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return size.X / scale, (size.Y - inset.Y) / scale
end

-- (layout sets every size and text size, so a layout change needs no rebuild)
local function fit(view: CapsuleView.Refs)
	local w, h = room()
	CapsuleView.layout(view, compactNow(), w, h)
end

-- Every card as the player sees it now.
local function currentCards(coins: number): { CapsuleView.Card }
	return CapsuleView.cards(StateController.get(), coins, restricted(), serverNow(), stateAt)
end

-- The Triple Lucky odds the cards show now.
local function luckyShown(): boolean
	return CapsuleView.luckyNow(StateController.get(), serverNow(), stateAt)
end

local function refresh()
	local view = refs
	if not view or not shown then
		return
	end
	local coins = HudController.predictedCoins(os.clock())
	cards = currentCards(coins)
	CapsuleView.setCoins(view, coins)
	CapsuleView.setCards(view, cards)
end

local function cardOf(id: string): CapsuleView.Card?
	for _, card in cards do
		if card.Id == id then
			return card
		end
	end
	return nil
end

local function freeButton()
	local button = pendingButton
	pendingButton = nil
	pendingUntil = 0
	if button then
		button:SetAttribute("Busy", false)
	end
	refresh()
end

-- Sends an open (from the panel or OPEN AGAIN). Returns whether it was sent.
local function request(capsuleId: string, count: number, button: TextButton?): boolean
	local now = os.clock()
	if now < pendingUntil then
		status("Opening... one moment", Theme.Info)
		return false
	end
	if now - lastSend < CapsuleConfig.ClientCooldown then
		status("One moment...", Theme.Info)
		return false
	end
	local coins = HudController.predictedCoins(now)
	cards = currentCards(coins)
	local card = cardOf(capsuleId)
	local buy: CapsuleView.Buy? = nil
	if card then
		for _, b in card.Buys do
			if b.Count == count then
				buy = b
			end
		end
	end
	if not card or not card.Visible or not buy then
		return false
	end
	if not buy.CanBuy then
		status(CapsuleView.reasonText(buy.Reason), Theme.Bad)
		Sfx.play("UIDeny")
		return false
	end
	pendingUntil = now + CapsuleConfig.ResultTimeout
	lastSend = now
	pendingButton = button
	if button then
		button:SetAttribute("Busy", true)
		button.Text = "..."
	end
	lastOpen = { Capsule = capsuleId, Count = count }
	Sfx.play("UIClick")
	-- the odds this card shows: the server rolls exactly these (or refuses)
	Net.send("CapsuleAction", "Open", { Capsule = capsuleId, Count = count, Lucky = card.Lucky })
	return true
end

local function switchTab(dir: number)
	local view = refs
	if not view then
		return
	end
	local tabs = CapsuleView.visibleTabs(cards)
	if #tabs < 2 then
		return
	end
	local index = table.find(tabs, view.Tab) or 1
	view.Tab = tabs[(index - 1 + dir) % #tabs + 1]
	refresh()
	Sfx.play("UIClick")
	if usingGamepad() then
		GuiService.SelectedObject = CapsuleView.firstButton(view)
	end
end

function CapsuleController.close()
	if not shown then
		return
	end
	shown = false
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(TAB_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Capsules", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not shown or playing then
		return Enum.ContextActionResult.Pass
	end
	CapsuleController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function onTab(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not shown or playing then
		return Enum.ContextActionResult.Pass
	end
	switchTab(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
	return Enum.ContextActionResult.Sink
end

local function openGolems()
	local module = script.Parent:FindFirstChild("GolemController")
	if module and module:IsA("ModuleScript") then
		local ok, controller = pcall(require, module :: any)
		local golems = controller :: any
		if ok and type(golems) == "table" and type(golems.open) == "function" then
			CapsuleController.close()
			golems.open()
		end
	end
end

local function ensureView(): CapsuleView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = CapsuleView.build(compactNow())
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		CapsuleController.close()
		Sfx.play("UIClick")
	end)
	view.Golems.Activated:Connect(function()
		Sfx.play("UIClick")
		openGolems()
	end)
	for id, tab in view.Tabs do
		tab.Activated:Connect(function()
			if view.Tab ~= id then
				view.Tab = id
				refresh()
				Sfx.play("UIClick")
			end
		end)
	end
	for i, button in view.Buttons do
		button.Activated:Connect(function()
			if button:GetAttribute("Busy") == true then
				return
			end
			request(view.Tab, CapsuleConfig.Counts[i], button)
		end)
	end
	refs = view
	return view
end

local function watch()
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		if pendingUntil > 0 and os.clock() > pendingUntil then
			freeButton()
			status("No answer yet: if it went through, your golems show up in MY GOLEMS", Theme.Bad)
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					CapsuleController.close()
					return
				end
			end
		end
		refresh()
	end)
end

-- Opens the shop panel (from the stall's prompt or another screen).
function CapsuleController.open()
	if shown then
		refresh()
		return
	end
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	local view = ensureView()
	shown = true
	openedAt = os.clock()
	fit(view)
	updateHint(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("Capsules", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(TAB_ACTION, onTab, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	watch()
	refresh()
	if usingGamepad() then
		GuiService.SelectedObject = CapsuleView.firstButton(view)
	end
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

---------------------------------------------------------------- the opening

local function fitOpening(o: CapsuleView.OpenRefs)
	local w, h = room()
	CapsuleView.layoutOpening(o, compactNow(), w, h)
end

local function openingHint(o: CapsuleView.OpenRefs, ending: boolean)
	local sep = CapsuleView.Separator
	if ending then
		o.Hint.Text = if usingGamepad() then `{padName(Enum.KeyCode.ButtonB)}: close` else ""
	elseif usingGamepad() then
		o.Hint.Text = `{padName(Enum.KeyCode.ButtonA)}: next{sep}{padName(Enum.KeyCode.ButtonB)}: skip all`
	elseif isTouch() then
		o.Hint.Text = "Tap to skip"
	else
		o.Hint.Text = `Click or Space to skip{sep}Backspace: skip all`
	end
end

-- Waits up to `seconds`, cut short by a skip. Returns true when skipped.
local function pause(seconds: number): boolean
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime do
		if skipStep or skipAll then
			skipStep = false
			return true
		end
		task.wait()
	end
	return false
end

local function flash(o: CapsuleView.OpenRefs, color: Color3, strength: number)
	o.Flash.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45)
	o.Flash.BackgroundTransparency = 1 - strength
	TweenService:Create(o.Flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		:Play()
end

local function setRays(o: CapsuleView.OpenRefs, color: Color3?, visible: boolean)
	o.Rays.Visible = visible
	if color then
		CapsuleView.setRayColor(o, color)
	end
end

local function clearHero(o: CapsuleView.OpenRefs)
	hero = nil
	for _, child in o.Hero:GetChildren() do
		if not child:IsA("Camera") then
			child:Destroy()
		end
	end
end

-- Camera looking at a point of the hero viewport from the front, a 3/4 turn.
local function aim(o: CapsuleView.OpenRefs, target: Vector3, distance: number)
	local a = 0.32
	local eye = target + Vector3.new(math.sin(a) * distance, distance * 0.12, -math.cos(a) * distance)
	o.Camera.CFrame = CFrame.lookAt(eye, target)
end

-- Kinds the player owned before this result (State minus the result's golems).
local function ownedBefore(result: Result): { [string]: boolean }
	local state = StateController.get()
	local golems = if state then state.Golems else nil
	local owned = if type(golems) == "table" and type(golems.Owned) == "table" then golems.Owned else {}
	local fresh: { [number]: boolean } = {}
	for _, g in result.Golems do
		fresh[g.Id] = true
	end
	local kinds: { [string]: boolean } = {}
	for _, entry in owned do
		if type(entry) == "table" and not fresh[entry.Id] and type(entry.Kind) == "string" then
			kinds[entry.Kind] = true
		end
	end
	return kinds
end

-- The capsule shakes, cracks and bursts (`color`: the rarest golem's).
local function burst(o: CapsuleView.OpenRefs, capsuleId: string, color: Color3)
	clearHero(o)
	local model = GolemBuilder.capsule(capsuleId)
	model.Parent = o.Hero
	aim(o, Vector3.zero, 15)
	local band = model:FindFirstChild("Band", true) :: BasePart?
	local glow = if band then band.Color else color
	local cracks: { BasePart } = {}
	for i = 1, 3 do
		local crack = model:FindFirstChild("Crack" .. i, true)
		if crack and crack:IsA("BasePart") then
			table.insert(cracks, crack)
		end
	end
	local start = os.clock()
	local shake = if skipAll then 0 else SHAKE_TIME
	local cracked = 0
	while os.clock() - start < shake and not skipStep and not skipAll do
		local t = (os.clock() - start) / shake
		local amp = 0.05 + 0.3 * t * t
		local wobble = math.sin(os.clock() * (16 + 14 * t)) * amp
		local pop = 1 + 0.04 * math.sin(os.clock() * 30) * t
		model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, 0.4 * math.sin(os.clock() * 2), wobble))
		aim(o, Vector3.zero, 15 / pop - t * 1.5)
		if band then
			band.Color = glow:Lerp(color, t)
		end
		local due = math.floor(t * 3.2)
		while cracked < math.min(due, #cracks) do
			cracked += 1
			cracks[cracked].Transparency = 0
			cracks[cracked].Color = color:Lerp(Color3.new(1, 1, 1), 0.3)
			Sfx.play("NodeCrack")
		end
		task.wait()
	end
	skipStep = false
	-- burst: flash, the halves fly apart and fade
	flash(o, color, 0.9)
	Sfx.play("NodeShatter")
	local top = model:FindFirstChild("Top") :: Model?
	local bottom = model:FindFirstChild("Bottom") :: Model?
	local t0 = os.clock()
	while os.clock() - t0 < 0.4 do
		local k = (os.clock() - t0) / 0.4
		if top then
			top:PivotTo(CFrame.new(1.4 * k, 1.4 + 5 * k, 0) * CFrame.Angles(0, 0, -1.6 * k))
		end
		if bottom then
			bottom:PivotTo(CFrame.new(-0.8 * k, -4 * k * k, 0) * CFrame.Angles(0, 0, 0.8 * k))
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name:sub(1, 5) ~= "Crack" and d.Name:sub(-4) ~= "Root" then
				d.Transparency = k
			end
		end
		task.wait()
	end
	model:Destroy()
end

-- The hero golem's frame: the camera rushes in (Back easing), the golem
-- hops once, then turns slowly from side to side.
local function animateHero(o: CapsuleView.OpenRefs, h: Hero)
	local t = os.clock() - h.Start
	local k = math.clamp(t / 0.35, 0, 1)
	local back = 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2
	aim(o, h.Target, h.Distance * (2.4 - 1.4 * back))
	local hop = math.max(0, math.sin(math.clamp(t / 0.45, 0, 1) * math.pi)) * 0.6
	-- (the pivot is the Body: RootHeight above the feet)
	h.Model:PivotTo(CFrame.new(0, h.RootHeight + hop, 0) * CFrame.Angles(0, math.sin(t * 0.9) * 0.6, 0))
end

-- One golem pops out of the burst; it stays REVEAL_TIME (or until a skip).
-- A single golem stays on screen for the end.
local function reveal(o: CapsuleView.OpenRefs, kind: string, isNew: boolean, index: number, total: number)
	clearHero(o)
	local golem = GolemConfig.ById[kind]
	local color = CapsuleView.rarityColor(kind)
	local model = GolemBuilder.build(kind)
	model.Parent = o.Hero
	local height = (model:GetAttribute("Height") :: number?) or 3
	local h: Hero = {
		Model = model,
		Start = os.clock(),
		Target = Vector3.new(0, height * 0.5, 0),
		Distance = height * 2.9 + 1,
		RootHeight = (model:GetAttribute("RootHeight") :: number?) or 1,
	}
	hero = h
	animateHero(o, h)
	setRays(o, color, true)
	CapsuleView.setPlate(o, kind, isNew)
	o.Counter.Text = if total > 1 then `{index} / {total}` else ""
	local plateScale = o.Plate:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	plateScale.Parent = o.Plate
	plateScale.Scale = 0.5
	TweenService:Create(plateScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local order = if golem then Rarity.ById[golem.Rarity].Order else 1
	flash(o, color, if order >= 4 then 0.7 else 0.35)
	Sfx.play("Reveal")
	if order >= 5 then
		Sfx.play("Discovery")
	end
	if total == 1 then
		return
	end
	pause(if skipAll then 0 else REVEAL_TIME)
	clearHero(o)
	o.Plate.Visible = false
end

-- The result grid pops in, card by card.
local function showGrid(o: CapsuleView.OpenRefs, kinds: { string }, new: { [number]: boolean })
	clearHero(o)
	o.Plate.Visible = false
	o.Counter.Text = `{#kinds} GOLEMS WOKE UP!`
	local bestIndex: number? = nil
	local best = CapsuleView.best(kinds)
	for i, kind in kinds do
		if kind == best then
			bestIndex = i
			break
		end
	end
	CapsuleView.setGrid(o, kinds, new, if #kinds > 1 then bestIndex else nil)
	o.Grid.Visible = true
	setRays(o, if best then CapsuleView.rarityColor(best) else nil, best ~= nil and GolemConfig.order(best) >= 4)
	for _, cell in o.Cells do
		cell.Frame.Visible = true
		cell.Scale.Scale = 0.3
		TweenService:Create(cell.Scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local order = GolemConfig.order(cell.Kind)
		if order >= 4 then
			flash(o, CapsuleView.rarityColor(cell.Kind), 0.35)
			Sfx.play(if order >= 5 then "Discovery" else "Reveal")
		else
			Sfx.play("Pickup")
		end
		if not skipAll and not skipStep then
			pause(if #kinds > 3 then 0.09 else 0.22)
		end
	end
	skipStep = false
end

-- The end screen's note: which odds the result had, or (with OPEN AGAIN)
-- which odds OPEN AGAIN uses now.
local function endNote(o: CapsuleView.OpenRefs, result: Result, againShown: boolean)
	local lucky = luckyShown()
	if result.Free then
		o.Note.Text = "A FREE CAPSULE!"
		o.Note.TextColor3 = Theme.Accent
	elseif againShown and result.Lucky and not lucky then
		o.Note.Text = "Triple Lucky ended: normal odds now"
		o.Note.TextColor3 = Theme.Text
	elseif againShown and lucky and not result.Lucky then
		o.Note.Text = "Triple Lucky is on: OPEN AGAIN uses its odds"
		o.Note.TextColor3 = LUCKY_COLOR
	elseif result.Lucky then
		o.Note.Text = "TRIPLE LUCKY ODDS"
		o.Note.TextColor3 = LUCKY_COLOR
	else
		o.Note.Text = ""
	end
end

-- OPEN AGAIN: only after the player's own coin open (not a wheel prize or a Robux receipt).
local function againText(o: CapsuleView.OpenRefs, result: Result?)
	local again = lastOpen
	if again and result and (result.Free or result.Capsule ~= again.Capsule or result.Count ~= again.Count) then
		again = nil
	end
	if again then
		cards = currentCards(HudController.predictedCoins(os.clock()))
	end
	local card = if again then cardOf(again.Capsule) else nil
	local buy: CapsuleView.Buy? = nil
	if card and again then
		for _, b in card.Buys do
			if b.Count == again.Count then
				buy = b
			end
		end
	end
	local visible = again ~= nil and buy ~= nil and card ~= nil and card.Visible and not card.Robux
	holderOf(o.Again).Visible = visible
	if visible and buy and not againPending then
		o.Again.Text = `OPEN {buy.Count} AGAIN  {buy.PriceText}`
		CapsuleView.style(o.Again, buy.CanBuy, Theme.Accent, Theme.AccentDark)
	end
	if result then
		endNote(o, result, visible)
	end
end

local function onSkip(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not playing then
		return Enum.ContextActionResult.Pass
	end
	if atEnd then
		endDone = true
	else
		skipStep = true
	end
	return Enum.ContextActionResult.Sink
end

local function onSkipAll(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not playing then
		return Enum.ContextActionResult.Pass
	end
	if atEnd then
		endDone = true
	else
		skipAll = true
	end
	return Enum.ContextActionResult.Sink
end

local openingCompact: boolean? = nil -- the layout the opening was built for

local function ensureOpening(): CapsuleView.OpenRefs
	local compact = compactNow()
	local existing = opening
	if existing and openingCompact == compact then
		return existing
	end
	if existing then
		-- (only between two openings: play() calls this before it starts)
		existing.Gui:Destroy()
		opening = nil
	end
	openingCompact = compact
	local o = CapsuleView.buildOpening(compact)
	o.Gui.Parent = player:WaitForChild("PlayerGui")
	o.Dim.Activated:Connect(function()
		if playing and not atEnd then
			skipStep = true
		end
	end)
	o.Skip.Activated:Connect(function()
		if playing and not atEnd then
			skipStep = true
		end
	end)
	o.Ok.Activated:Connect(function()
		if playing and atEnd then
			Sfx.play("UIClick")
			endDone = true
		end
	end)
	o.Again.Activated:Connect(function()
		local again = lastOpen
		if not again or againPending or not atEnd then
			return
		end
		if request(again.Capsule, again.Count, nil) then
			againPending = true
			o.Again.Text = "..."
			o.Hint.Text = ""
		else
			o.Hint.Text = refs and refs.Status.Text or ""
		end
	end)
	opening = o
	return o
end

-- Plays one result from start to end, then waits for OK (or the next open).
local function play(result: Result)
	local o = ensureOpening()
	fitOpening(o)
	playing = true
	atEnd = false
	skipStep = false
	skipAll = false
	o.Gui.Enabled = true
	o.Grid.Visible = false
	o.Plate.Visible = false
	setRays(o, nil, false)
	holderOf(o.Skip).Visible = true
	holderOf(o.Ok).Visible = false
	holderOf(o.Again).Visible = false
	o.Counter.Text = ""
	endNote(o, result, false)
	openingHint(o, false)
	ContextActionService:BindActionAtPriority(SKIP_ACTION, onSkip, false, OPEN_PRIORITY, Enum.KeyCode.Space, Enum.KeyCode.Return)
	ContextActionService:BindActionAtPriority(
		SKIP_ALL_ACTION,
		onSkipAll,
		false,
		OPEN_PRIORITY,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Backspace
	)
	if usingGamepad() then
		GuiService.SelectedObject = o.Skip
	end
	local spin = 0
	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		spin += dt * 14
		o.Rays.Rotation = spin
		local h = hero
		if h and h.Model.Parent then
			animateHero(o, h)
		end
	end)

	local kinds: { string } = {}
	for _, g in result.Golems do
		table.insert(kinds, g.Kind)
	end
	local before = ownedBefore(result)
	local new: { [number]: boolean } = {}
	for i, kind in kinds do
		new[i] = not before[kind]
		before[kind] = true
	end
	local best = CapsuleView.best(kinds)
	local color = if best then CapsuleView.rarityColor(best) else Theme.Accent
	local ok, err = pcall(function()
		burst(o, result.Capsule, color)
		if #kinds <= 3 then
			for i, kind in kinds do
				reveal(o, kind, new[i] == true, i, #kinds)
			end
		end
		if #kinds > 1 then
			showGrid(o, kinds, new)
		end
	end)
	if not ok then
		warn("[CapsuleController] opening failed: " .. tostring(err))
	end
	-- the end: OK / OPEN AGAIN
	atEnd = true
	endDone = false
	againPending = false
	holderOf(o.Skip).Visible = false
	holderOf(o.Ok).Visible = true
	shownResult = result
	againText(o, result)
	openingHint(o, true)
	if usingGamepad() then
		GuiService.SelectedObject = o.Ok
	end
	-- until OK / B / a click, or a new result (OPEN AGAIN, one already
	-- waiting, a wheel prize) starts at once; the note and OPEN AGAIN
	-- follow the odds of the moment (Triple Lucky may end meanwhile)
	local nextCheck = 0
	while not endDone and #queue == 0 do
		if os.clock() >= nextCheck then
			nextCheck = os.clock() + TICK
			againText(o, result)
		end
		task.wait()
	end
	endDone = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	clearHero(o)
	atEnd = false
	playing = false
	ContextActionService:UnbindAction(SKIP_ACTION)
	ContextActionService:UnbindAction(SKIP_ALL_ACTION)
	if #queue == 0 then
		o.Gui.Enabled = false
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(o.Gui) then
			GuiService.SelectedObject = nil
		end
		local view = refs
		if view and shown and usingGamepad() then
			GuiService.SelectedObject = CapsuleView.firstButton(view)
		end
	end
end

local function pump()
	if playing then
		return
	end
	task.spawn(function()
		while #queue > 0 do
			local result = table.remove(queue, 1) :: Result
			play(result)
		end
	end)
end

-- A CapsuleResult (also a late one, a wheel prize or a Robux receipt).
local function onResult(payload: any)
	if type(payload) ~= "table" or type(payload.Capsule) ~= "string" or type(payload.Golems) ~= "table" then
		return
	end
	local golems: { { Id: number, Kind: string } } = {}
	for _, g in payload.Golems do
		if type(g) == "table" and type(g.Id) == "number" and type(g.Kind) == "string" and #golems < 10 then
			table.insert(golems, { Id = g.Id, Kind = g.Kind })
		end
	end
	if #golems == 0 then
		return
	end
	if pendingUntil > 0 or pendingButton then
		freeButton()
	end
	againPending = false
	table.insert(queue, {
		Capsule = payload.Capsule,
		Count = #golems,
		Golems = golems,
		Lucky = payload.Lucky == true,
		Free = payload.Free == true,
	})
	pump()
end

local function onActionResult(payload: any)
	if type(payload) ~= "table" or payload.Action ~= "Capsule" then
		return
	end
	freeButton()
	if payload.Ok == true then
		return
	end
	local text = CapsuleView.reasonText(payload.Reason)
	againPending = false
	local o = opening
	if o and playing and atEnd then
		o.Hint.Text = text
		againText(o, shownResult)
	end
	if shown then
		status(text, Theme.Bad)
		Sfx.play("UIDeny")
	elseif not playing then
		HudController.toast(text, "Deny")
	end
end

local function onPurchasePrompt(payload: any)
	if type(payload) ~= "table" or type(payload.Product) ~= "string" then
		return
	end
	local product = MonetizationConfig.get(payload.Product)
	if not product or not product.Capsule then
		return
	end
	freeButton()
	if payload.Status ~= "Prompted" then
		local text = MonetizationConfig.StatusText[payload.Status] or "That isn't sold here."
		if shown then
			status(text, Theme.Info)
		else
			HudController.toast(text, "Info")
		end
	end
end

---------------------------------------------------------------- the stall's odds board

local boardPage = 0
local boardSeen: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local boardWatched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local boardQueued = false

-- The capsule the board shows now (cycles through those the player may open).
local function boardCapsule(): string?
	local list = {}
	for _, capsule in CapsuleConfig.List do
		if CapsuleView.visible(capsule.Id, restricted()) then
			table.insert(list, capsule.Id)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[boardPage % #list + 1]
end

local function updateBoards(): boolean
	local capsuleId = boardCapsule()
	if not capsuleId then
		return false
	end
	local lucky = luckyShown()
	local key = `{capsuleId}|{lucky}`
	for _, stall in CollectionService:GetTagged(STALL_TAG) do
		local board = stall:FindFirstChild("OddsBoard", true)
		local gui = if board then board:FindFirstChildWhichIsA("SurfaceGui") else nil
		if gui and boardSeen[gui] ~= key then
			boardSeen[gui] = key
			gui.PixelsPerStud = CapsuleController.BoardPixels
			CapsuleView.fillBoard(gui, capsuleId, lucky)
		end
	end
	return true
end

-- One board update at the end of this frame (many parts may stream in at once).
local function queueBoards()
	if boardQueued then
		return
	end
	boardQueued = true
	task.defer(function()
		boardQueued = false
		local ok, err = pcall(updateBoards)
		if not ok then
			warn("[CapsuleController] odds board: " .. tostring(err))
		end
	end)
end

-- A stall streams in part by part: fill its board the moment it arrives
-- (not at the next tick), and again if an old label arrives after that.
local function watchStall(stall: Instance)
	if boardWatched[stall] then
		return
	end
	boardWatched[stall] = true
	stall.DescendantAdded:Connect(function(d: Instance)
		local gui = if d:IsA("SurfaceGui") then d else d:FindFirstAncestorWhichIsA("SurfaceGui")
		if not gui or d:GetAttribute(CapsuleView.BoardAttribute) == true then
			return
		end
		local board = gui.Parent
		if board and board.Name == "OddsBoard" then
			boardSeen[gui] = nil
			queueBoards()
		end
	end)
end

---------------------------------------------------------------- lifecycle

function CapsuleController.init()
	Net.listen("OpenUI", function(kind)
		if kind == "Capsules" then
			CapsuleController.open()
		end
	end)
	Net.listen("CapsuleResult", onResult)
	Net.listen("ActionResult", onActionResult)
	Net.listen("PurchasePrompt", onPurchasePrompt)
	if StateController.get() then
		stateAt = serverNow()
	end
	StateController.onChanged(function()
		stateAt = serverNow()
		if shown then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(function()
		if shown then
			refresh()
		end
		table.clear(boardSeen)
		queueBoards()
	end)
	player.CharacterRemoving:Connect(function()
		CapsuleController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and shown then
			updateHint(view)
		end
		local o = opening
		if o and playing then
			openingHint(o, atEnd)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and shown then
				fit(view)
			end
			local o = opening
			if o and playing then
				fitOpening(o)
			end
		end)
	end
end

function CapsuleController.start()
	-- the stall's odds board: the next capsule every BoardSeconds, the
	-- Triple Lucky odds within BoardTick, and at once when it streams in
	for _, stall in CollectionService:GetTagged(STALL_TAG) do
		watchStall(stall)
	end
	CollectionService:GetInstanceAddedSignal(STALL_TAG):Connect(function(stall: Instance)
		watchStall(stall)
		queueBoards()
	end)
	local pageAt = os.clock()
	while true do
		local ok, err = pcall(updateBoards)
		if not ok then
			warn("[CapsuleController] odds board: " .. tostring(err))
		end
		task.wait(CapsuleController.BoardTick)
		if os.clock() - pageAt >= CapsuleController.BoardSeconds then
			pageAt = os.clock()
			boardPage += 1
		end
	end
end

return CapsuleController
