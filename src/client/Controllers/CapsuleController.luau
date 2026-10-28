--[[
	CapsuleController: golem capsules on the client (step 7).

	- The eggs in the EGGS temple open from their own "Buy Egg!" prompts,
	  their panels' Open 1 / 3 / 10 and Auto (EggPanelController, owner
	  2026-10-28): CapsuleController.buy runs the same request as OPEN 1 /
	  3 / 10 below, with the odds the egg's panel shows, and the same
	  opening plays. buy(), quote(),
	  luckyShown(), openingState(), onStop() and setAuto() are for it.
	- The shop panel (CapsuleView, every egg with x1 / x3 / x10 and every
	  golem's name) opens from the golem inventory's EGGS button
	  (CapsuleController.open) and on OpenUI "Capsules" (an egg's own podium
	  out in the world, the SKY EGG's; the temple's old "Capsules" prompt is
	  off: CapsuleService.StallPrompt). Opening works anywhere, so the panel
	  doesn't close when you walk away.
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
	  capsules (Robux): a button per product that is live (a real id and
	  step 8's receipts ready: the ReplicatedStorage attribute
	  CapsuleView.ReceiptsAttribute), the others greyed "Coming soon"; the
	  server answers PurchasePrompt ("Full" reads: the golem inventory is
	  full, delete some golems first).
	- CapsuleResult plays the opening (CapsuleView.buildOpening) with the
	  hatch of UI/HatchFx (owner 2026-10-28: "a wow effect"): the egg (x3: a
	  row of three, x10: rows of five, from a pool) wobbles harder and faster,
	  squashes and stretches, its cracks spread and glow and leak light in the
	  rarest golem's colour (a longer build-up and more light for rarer
	  golems) to a rising sound and a crack sound per crack, then bursts (the
	  eggs one after another): a flash, the halves flying, shell pieces, a
	  small camera nudge. Each golem pops out SOLID (owner: "the golems
	  mustn't be see-through": no flash or tint ever over a golem, in the
	  reveal or the grid; its glow is behind it) with a bounce in its
	  rarity's aura and rays, with its name, rarity, bonus and NEW! when it is the
	  first of its kind; Rare and up sparkle, Mythic tints the screen once, a
	  fanfare from Legendary (x1 and x3 one by one, then x3 as a row of
	  cards; x10 straight to a grid of 10 cards popping in). Flashes stay
	  HatchFx.FlashGap apart (2.5 a second at most); with Reduce motion
	  nothing shakes, flashes or nudges: the eggs fade and the golem fades
	  in. Click /
	  tap / A / Space / Enter skips a step; B / Backspace skips to the end;
	  a gamepad's selection stays on the overlay's buttons (their
	  SelectionGroup, and it is put back if anything moves it away), and the
	  shop's buttons behind it do nothing while it plays;
	  at the end OK closes and OPEN AGAIN opens the same capsules again (the
	  note above says which odds it uses now: "TRIPLE LUCKY ODDS" or
	  "Triple Lucky ended: normal odds"). Results that arrive while one
	  plays wait their turn; a waiting one starts as soon as the end screen
	  shows. A NEW golem bursts out in confetti (UI/Confetti; not with Reduce
	  motion). While the overlay is up every prompt is suppressed
	  ("CapsuleOpening"), so a key meant for it never also fires a prompt
	  behind it. With Auto on, OPEN AGAIN hides and the hint says OK stops
	  it; closing the end screen (OK, B, Backspace, Space, Enter) stops Auto
	  (onStop "Closed"), and so does every refusal (onStop with its reason).
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
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local CapsuleView = require(script.Parent.Parent.UI.CapsuleView)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local Confetti = require(script.Parent.Parent.UI.Confetti)
local HatchFx = require(script.Parent.Parent.UI.HatchFx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local Motion = require(script.Parent.Parent.UI.Motion)
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
local PODIUM_TAG = "EggPodium" -- an egg on its own podium (CapsuleService.PodiumTag)
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local OPEN_PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- the overlay is above every panel
local TICK = 0.25
local STATUS_TIME = 3.5
local REVEAL_TIME = 1.7 -- seconds one golem stays before the next (or the end) when not skipped
local LUCKY_COLOR = Color3.fromRGB(255, 206, 72)
-- the other panels (one in the middle of the screen at a time): MenuPanels.Names,
-- the one list of every panel controller (a name that isn't in the game is skipped)

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
local hatch: HatchFx.Overlay? = nil -- (the hatch's pieces, made with the overlay)
local eggPool: { [string]: { HatchFx.Record } } = {} -- capsule id -> its eggs, built once
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
local endAt = 0 -- os.clock() when the end screen showed (openingState)
local autoOn = false -- the temple's Auto runs (setAuto: the end screen's hint, no OPEN AGAIN)
local autoNote: string? = nil -- why Auto stopped, while the overlay is up (setAuto: its hint says so, over the dim)
local stopListeners: { (string) -> () } = {}
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
	for _, name in MenuPanels.Names do
		if name == "CapsuleController" then
			continue
		end
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

-- Step 8's receipts take Royal capsules (set by CapsuleService.setReceiptsReady).
local function receiptsReady(): boolean
	return ReplicatedStorage:GetAttribute(CapsuleView.ReceiptsAttribute) == true
end

-- Every card as the player sees it now.
-- the podium-only egg the panel was opened at (OpenUI payload.Capsule), or nil:
-- a podium-only egg (CapsuleConfig Podium) shows its tab only then
local atPodium: string? = nil

local function currentCards(coins: number): { CapsuleView.Card }
	local list = CapsuleView.cards(StateController.get(), coins, restricted(), serverNow(), stateAt, receiptsReady())
	for _, card in list do
		local capsule = CapsuleConfig.ById[card.Id]
		if capsule and capsule.Podium and atPodium ~= card.Id then
			card.Visible = false
		end
	end
	return list
end

-- The Triple Lucky odds the cards show now.
local function luckyShown(): boolean
	return CapsuleView.luckyNow(StateController.get(), serverNow(), stateAt)
end

-- The same for the egg panels (EggPanelController): the odds every open sends.
function CapsuleController.luckyShown(): boolean
	return luckyShown()
end

-- One capsule's card as the window would show it now (its price at the
-- player's level, whether it can be bought and why not, its odds): the egg
-- panel's quote. nil when it isn't sold to this player here.
function CapsuleController.quote(capsuleId: string): CapsuleView.Card?
	for _, card in currentCards(HudController.predictedCoins(os.clock())) do
		if card.Id == capsuleId then
			return card
		end
	end
	return nil
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

--[[
	Sends an open (from the panel, OPEN AGAIN or an egg's prompt). Returns
	whether it was sent and, when not, why: "Busy" (an open waits for its
	answer), "Cooldown" (ClientCooldown), "Hidden" (not sold to this
	player here), "OddsChanged" (`expectLucky`: the odds the egg's panel
	showed are no longer the card's) or the buy's own Reason (NoCoins,
	InventoryFull, ComingSoon).
]]
local function request(capsuleId: string, count: number, button: TextButton?, expectLucky: boolean?): (boolean, string?)
	local now = os.clock()
	if now < pendingUntil then
		status("Opening... one moment", Theme.Info)
		return false, "Busy"
	end
	if now - lastSend < CapsuleConfig.ClientCooldown then
		status("One moment...", Theme.Info)
		return false, "Cooldown"
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
		return false, "Hidden"
	end
	if not buy.CanBuy then
		status(CapsuleView.reasonText(buy.Reason), Theme.Bad)
		Sfx.play("UIDeny")
		return false, buy.Reason
	end
	if expectLucky ~= nil and card.Lucky ~= expectLucky then
		status(CapsuleView.reasonText("OddsChanged"), Theme.Bad)
		Sfx.play("UIDeny")
		return false, "OddsChanged"
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
	return true, nil
end

--[[
	The EGGS temple's "Buy Egg!", Open 1 / 3 / 10 and Auto
	(EggPanelController): opens `count` eggs (CapsuleConfig.Counts) through
	request() (the cooldown, the local refusals, the server's CapsuleAction
	"Open" and the opening: one egg, a row of 3, a grid of 10), with the
	odds the egg's panel shows (`lucky`; refused "OddsChanged" when the
	card's differ now). The capsule window is shut there, so a refusal is a
	toast; `quiet` (Auto) skips the toast for a "one moment" wait. Returns
	whether it was sent and request()'s reason.
]]
function CapsuleController.buy(capsuleId: string, count: number, lucky: boolean, quiet: boolean?): (boolean, string?)
	local sent, reason = request(capsuleId, count, nil, lucky)
	if not sent and not shown and reason ~= "Hidden" then
		local busy = reason == "Busy" or reason == "Cooldown"
		if not (busy and quiet) then
			HudController.toast(if busy then "One moment..." else CapsuleView.reasonText(reason), if busy then "Info" else "Deny")
		end
	end
	return sent, reason
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
	atPodium = nil
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
	-- (while the opening plays the shop behind it does nothing)
	view.Close.Activated:Connect(function()
		if playing then
			return
		end
		CapsuleController.close()
		Sfx.play("UIClick")
	end)
	view.Golems.Activated:Connect(function()
		if playing then
			return
		end
		Sfx.play("UIClick")
		openGolems()
	end)
	for id, tab in view.Tabs do
		tab.Activated:Connect(function()
			if view.Tab ~= id and not playing then
				view.Tab = id
				refresh()
				Sfx.play("UIClick")
			end
		end)
	end
	for i, button in view.Buttons do
		button.Activated:Connect(function()
			if button:GetAttribute("Busy") == true or playing then
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

-- Tells the Auto listeners (onStop) why it must stop: "Closed" or a refusal's reason.
local function stopped(reason: string)
	for _, listener in stopListeners do
		local ok, err = pcall(function(): any
			listener(reason)
			return nil
		end)
		if not ok then
			warn("[CapsuleController] stop listener failed: " .. tostring(err))
		end
	end
end

-- Auto (EggPanelController) stops on these: the player closed the end
-- screen ("Closed"), or the server refused an open (its reason code).
function CapsuleController.onStop(listener: (string) -> ())
	table.insert(stopListeners, listener)
end

--[[
	Where the opening is, for Auto: "Waiting" (an open was sent, no answer
	yet), "Playing" (an opening plays, or another result waits its turn),
	"End" (its end screen shows; the number: seconds since) or "Idle".
]]
function CapsuleController.openingState(): (string, number)
	if pendingUntil > os.clock() then
		return "Waiting", 0
	elseif playing and atEnd and #queue == 0 then
		return "End", os.clock() - endAt
	elseif playing or #queue > 0 then
		return "Playing", 0
	end
	return "Idle", 0
end

local function fitOpening(o: CapsuleView.OpenRefs)
	local w, h = room()
	CapsuleView.layoutOpening(o, compactNow(), w, h)
	local fx = hatch
	if fx then
		HatchFx.place(fx, o.Hero.Position, o.Hero.Size.X.Offset)
	end
end

local function openingHint(o: CapsuleView.OpenRefs, ending: boolean)
	local sep = CapsuleView.Separator
	if ending and autoOn then
		o.Hint.Text = `Auto is on{sep}{if usingGamepad() then padName(Enum.KeyCode.ButtonB) else "OK"}: stop`
	elseif ending then
		o.Hint.Text = if usingGamepad() then `{padName(Enum.KeyCode.ButtonB)}: close` else ""
	elseif usingGamepad() then
		o.Hint.Text = `{padName(Enum.KeyCode.ButtonA)}: next{sep}{padName(Enum.KeyCode.ButtonB)}: skip all`
	elseif isTouch() then
		o.Hint.Text = "Tap to skip"
	else
		o.Hint.Text = `Click or Space to skip{sep}Backspace: skip all`
	end
	local note = autoNote
	if note then
		o.Hint.Text = if o.Hint.Text == "" then note else note .. sep .. o.Hint.Text
	end
end

local againText: (o: CapsuleView.OpenRefs, result: Result?) -> () -- (below: the end screen's OPEN AGAIN and its note)

--[[
	Auto is on (the end screen says how to stop it and hides OPEN AGAIN).
	Off with a `note` (the odds changed under it): the overlay's hint says
	why until the overlay closes (a toast would sit under its dim).
]]
function CapsuleController.setAuto(on: boolean, note: string?)
	autoOn = on
	autoNote = if on then nil else note
	local o = opening
	if o and playing then
		openingHint(o, atEnd)
	end
	if o and playing and atEnd and not on then
		againText(o, shownResult) -- (Auto stopped on its end screen: OPEN AGAIN and the odds' note come back)
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

local lastFlash = -math.huge -- (flashes stay HatchFx.FlashGap apart: 2.5 a second at most)
local flashTween: Tween? = nil

-- A full-screen flash (never with Reduce motion, never sooner than FlashGap after the last).
local function flash(o: CapsuleView.OpenRefs, color: Color3, strength: number)
	local now = os.clock()
	if Motion.reduced() or not HatchFx.flashOk(lastFlash, now) then
		return
	end
	lastFlash = now
	o.Flash.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45)
	o.Flash.BackgroundTransparency = 1 - strength
	if flashTween then
		flashTween:Cancel()
	end
	local tween = TweenService:Create(o.Flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	flashTween = tween
	tween:Play()
end

-- No flash over a golem: a skip-all lands on the reveal or the grid while the break's flash still fades.
local function noFlash(o: CapsuleView.OpenRefs)
	if flashTween then
		flashTween:Cancel()
		flashTween = nil
	end
	o.Flash.BackgroundTransparency = 1
end

local function setRays(o: CapsuleView.OpenRefs, color: Color3?, visible: boolean)
	o.Rays.Visible = visible
	if color then
		CapsuleView.setRayColor(o, color)
	end
end

-- Empties the hero viewport (pooled eggs go back to the pool, golems are let go) and dims the aura.
local function clearHero(o: CapsuleView.OpenRefs)
	hero = nil
	for _, child in o.Hero:GetChildren() do
		if child:GetAttribute("Pooled") == true then
			child.Parent = nil
		elseif not child:IsA("Camera") then
			child:Destroy()
		end
	end
	local fx = hatch
	if fx then
		HatchFx.setAura(fx, Color3.new(1, 1, 1), 0)
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

--[[
	`count` eggs of a capsule from the pool (built once, put back whole:
	HatchFx.reset). `calm`: the calm eggs (no neon but the band, emblem and
	crown core: GolemBuilder.capsule's Calm), for many eggs on a phone.
]]
local function takeEggs(capsuleId: string, count: number, calm: boolean): { HatchFx.Record }
	local key = if calm then capsuleId .. "|Calm" else capsuleId
	local list = eggPool[key]
	if not list then
		list = {}
		eggPool[key] = list
	end
	local pool = list :: { HatchFx.Record }
	while #pool < count do
		local model = GolemBuilder.capsule(capsuleId, nil, { Calm = calm })
		model:SetAttribute("Pooled", true)
		table.insert(pool, HatchFx.record(model))
	end
	local out: { HatchFx.Record } = {}
	for i = 1, count do
		HatchFx.reset(pool[i])
		table.insert(out, pool[i])
	end
	return out
end

-- The hero viewport's own scale (the golem's bounce).
local function heroPop(o: CapsuleView.OpenRefs): UIScale
	local existing = o.Hero:FindFirstChild("HeroPop")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local made = Instance.new("UIScale")
	made.Name = "HeroPop"
	made.Parent = o.Hero
	return made
end

-- Some of a burst's pieces (`n` of them; the rest stay hidden).
local function some(list: { Frame }, n: number): { Frame }
	local out: { Frame } = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i]
	end
	return out
end

--[[
	The hatch (UI/HatchFx): `count` eggs (one, a row of 3, rows of 5) wobble
	together harder and faster, squash and stretch (one egg), crack, glow and
	leak light in `color` (the rarest golem's; a longer build-up and more
	light for rarer ones: plan), then burst one after another: a flash, the
	halves flying, shell pieces, a crack and a burst sound, a small camera
	nudge. A skip jumps to the break, a skip-all past it. Reduce motion: the
	eggs stand a moment and fade, nothing shakes or flashes.
]]
local function burst(o: CapsuleView.OpenRefs, capsuleId: string, count: number, plan: HatchFx.Plan, color: Color3, shell: Color3)
	clearHero(o)
	local fx = hatch
	local n = math.clamp(count, 1, 10)
	local spots, distance = HatchFx.arrange(n)
	-- (many eggs on a phone: the calm ones; they move rigidly anyway: HatchFx.pose)
	local eggs = takeEggs(capsuleId, n, n > 3 and compactNow())
	for _, rec in eggs do
		rec.Model.Parent = o.Hero
	end
	aim(o, Vector3.zero, distance)
	if Motion.reduced() then
		for i, rec in eggs do
			HatchFx.pose(rec, CFrame.new(spots[i]), 0, math.huge, plan, color, false)
		end
		pause(if skipAll then 0 else 0.5)
		local t0 = os.clock()
		while os.clock() - t0 < 0.3 and not skipAll do
			local k = (os.clock() - t0) / 0.3
			for _, rec in eggs do
				for i, part in rec.Parts do
					part.Transparency = rec.Trans[i] + (1 - rec.Trans[i]) * k
				end
			end
			task.wait()
		end
		skipStep = false
		for _, rec in eggs do
			rec.Model.Parent = nil
		end
		Sfx.play("NodeShatter")
		return
	end
	if fx then
		HatchFx.paint(fx, shell, color)
	end
	local squash = n == 1 -- (many eggs move rigidly, a PivotTo each: cheaper on phones)
	local last = plan.Shake + (n - 1) * HatchFx.Sequence
	local start = os.clock()
	local cracked = 0
	local burstDone = 0
	Sfx.loop("CaseCharge", true)
	while true do
		if skipAll then
			start = os.clock() - (last + HatchFx.BurstTime)
		elseif skipStep then
			skipStep = false
			if os.clock() - start < plan.Shake then
				start = os.clock() - plan.Shake -- (a skip: straight to the break)
			end
		end
		local t = os.clock() - start
		if t >= last + HatchFx.BurstTime then
			break
		end
		for i, rec in eggs do
			local at = plan.Shake + (i - 1) * HatchFx.Sequence
			HatchFx.pose(rec, CFrame.new(spots[i]), t, at, plan, color, squash)
			if t >= at and i > burstDone then
				burstDone = i
				if i == 1 then
					-- the break: a flash, the burst, shell pieces flying, a nudge
					Sfx.loop("CaseCharge", false)
					flash(o, color, 0.9)
					Sfx.play("CaseBurst")
					if plan.Order >= 4 then
						Sfx.play("CaseBoom")
					end
					CameraShake.add(plan.Trauma)
					if fx then
						Confetti.burst(fx.Shards, Vector2.new(0.5, 0.5), os.clock())
					end
				else
					Sfx.play("NodeShatter", nil, 1 + 0.04 * i)
				end
			end
		end
		-- a crack sound (higher each time) and a small nudge per crack of the first egg
		local lit = HatchFx.cracksAt(math.min(t, plan.Shake - 0.001), plan)
		while cracked < lit do
			cracked += 1
			Sfx.play("NodeCrack", nil, 0.85 + 0.2 * cracked)
			CameraShake.add(plan.Trauma * 0.3)
		end
		if fx then
			HatchFx.setLeak(fx, if t < plan.Shake then t else nil, plan, color)
		end
		-- (the camera leans in as it builds)
		aim(o, Vector3.zero, distance * (1 - 0.12 * math.clamp(t / plan.Shake, 0, 1)))
		task.wait()
	end
	Sfx.loop("CaseCharge", false)
	skipStep = false
	if fx then
		HatchFx.setLeak(fx, nil, plan, color)
	end
	for _, rec in eggs do
		rec.Model.Parent = nil
	end
end

-- The hero golem's frame: the camera rushes in (Back easing), the golem
-- hops once, then turns slowly from side to side (Reduce motion: still).
local function animateHero(o: CapsuleView.OpenRefs, h: Hero)
	if Motion.reduced() then
		aim(o, h.Target, h.Distance)
		h.Model:PivotTo(CFrame.new(0, h.RootHeight, 0))
		return
	end
	local t = os.clock() - h.Start
	local k = math.clamp(t / 0.35, 0, 1)
	local back = 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2
	aim(o, h.Target, h.Distance * (2.4 - 1.4 * back))
	local hop = math.max(0, math.sin(math.clamp(t / 0.45, 0, 1) * math.pi)) * 0.6
	-- (the pivot is the Body: RootHeight above the feet)
	h.Model:PivotTo(CFrame.new(0, h.RootHeight + hop, 0) * CFrame.Angles(0, math.sin(t * 0.9) * 0.6, 0))
end

--[[
	One golem pops out of the burst with a bounce, in its rarity's aura and
	the turning rays; Rare and up get sparkles, Mythic a short tint of the
	whole screen, a NEW golem confetti, bigger sounds for rarer golems (a
	fanfare from Legendary). Reduce motion: it only fades in. It stays
	REVEAL_TIME (or until a skip); a single golem stays for the end.
]]
local function reveal(o: CapsuleView.OpenRefs, kind: string, isNew: boolean, index: number, total: number)
	clearHero(o)
	noFlash(o)
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
	local order = if golem then Rarity.ById[golem.Rarity].Order else 1
	local plan = HatchFx.plan(order)
	local fx = hatch
	local pop = heroPop(o)
	-- the golem is SOLID (owner 2026-10-28: "the golems mustn't be see-through"): its
	-- view fully opaque, its own colours, no flash or leak over it; its rarity glows
	-- BEHIND it (the aura, the rays, the Mythic tint: all under the hero)
	o.Hero.ImageColor3 = Color3.new(1, 1, 1)
	o.Hero.ImageTransparency = 0
	if fx then
		fx.Leak.Visible = false
		HatchFx.setAura(fx, color, if order >= 4 then 1 else 0.55)
	end
	if Motion.reduced() then
		pop.Scale = 1
		plateScale.Scale = 1
		o.Hero.ImageTransparency = 1
		TweenService:Create(o.Hero, TweenInfo.new(0.35), { ImageTransparency = 0 }):Play()
	else
		o.Hero.ImageTransparency = 0
		pop.Scale = HatchFx.popAt(0)
		TweenService:Create(pop, TweenInfo.new(HatchFx.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		plateScale.Scale = 0.5
		TweenService:Create(plateScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if fx then
			-- (the glow bursts out behind the golem: never a flash over it)
			HatchFx.pulseAura(fx)
			if plan.Sparkles > 0 then
				Confetti.burst(some(fx.Sparkles, plan.Sparkles), Vector2.new(0.5, 0.5), os.clock() + index)
			end
			if isNew then
				Confetti.burst(fx.Confetti, Vector2.new(0.5, 0.5), os.clock())
			end
			if plan.Tint then
				-- Mythic: the whole screen glows its colour once and fades (no flashing)
				fx.Tint.BackgroundColor3 = color
				fx.Tint.BackgroundTransparency = 0.45
				TweenService:Create(fx.Tint, TweenInfo.new(HatchFx.TintTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 1,
				}):Play()
			end
		end
		if order >= 5 then
			CameraShake.add(plan.Trauma * 0.5)
		end
	end
	Sfx.play("Reveal")
	if order >= 3 then
		Sfx.play("CoinBurst")
	end
	if order >= 5 then
		Sfx.play("Discovery")
	end
	if order >= 6 then
		Sfx.play("CaseRise")
	end
	if total == 1 then
		return
	end
	pause(if skipAll then 0 else REVEAL_TIME)
	clearHero(o)
	o.Plate.Visible = false
end

-- The result grid pops in, card by card (a big opening: a card per kind with its count).
local function showGrid(o: CapsuleView.OpenRefs, allKinds: { string }, allNew: { [number]: boolean })
	clearHero(o)
	noFlash(o)
	o.Plate.Visible = false
	o.Counter.Text = `{#allKinds} GOLEMS WOKE UP!`
	local kinds, new, counts = allKinds, allNew, nil :: { [number]: number }?
	if #allKinds > CapsuleView.GridMax then
		kinds, new, counts = CapsuleView.summary(allKinds, allNew)
	end
	local bestIndex: number? = nil
	local best = CapsuleView.best(kinds)
	for i, kind in kinds do
		if kind == best then
			bestIndex = i
			break
		end
	end
	CapsuleView.setGrid(o, kinds, new, if #kinds > 1 then bestIndex else nil, counts)
	o.Grid.Visible = true
	local anyNew = false
	for _, isNew in new do
		anyNew = anyNew or isNew
	end
	local fx = hatch
	if anyNew and fx and not Motion.reduced() then
		Confetti.burst(fx.Confetti, Vector2.new(0.5, 0.5), os.clock())
	end
	setRays(o, if best then CapsuleView.rarityColor(best) else nil, best ~= nil and GolemConfig.order(best) >= 4)
	for _, cell in o.Cells do
		cell.Frame.Visible = true
		cell.Scale.Scale = if Motion.reduced() then 1 else 0.3
		if not Motion.reduced() then
			TweenService:Create(cell.Scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		local order = GolemConfig.order(cell.Kind)
		if order >= 4 then
			-- (no flash over the cards: their golems stay solid; the rare card pops and the rays glow behind)
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
function againText(o: CapsuleView.OpenRefs, result: Result?)
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
	local visible = again ~= nil and buy ~= nil and card ~= nil and card.Visible and not card.Robux and not autoOn
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
local selectionConnection: RBXScriptConnection? = nil

-- While the opening plays, a gamepad's selection stays on its buttons
-- (SKIP, or OK at the end): put back when anything moves it elsewhere.
local function keepSelection(o: CapsuleView.OpenRefs)
	if selectionConnection then
		selectionConnection:Disconnect()
	end
	selectionConnection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		if not playing or not selected or selected:IsDescendantOf(o.Controls) then
			return
		end
		task.defer(function()
			local now = GuiService.SelectedObject
			if playing and now and not now:IsDescendantOf(o.Controls) then
				GuiService.SelectedObject = if atEnd then o.Ok else o.Skip
			end
		end)
	end)
end

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
	hatch = HatchFx.overlay(o.Gui)
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
		local sent, reason = request(again.Capsule, again.Count, nil)
		if sent then
			againPending = true
			o.Again.Text = "..."
			o.Hint.Text = ""
		elseif reason == "Busy" or reason == "Cooldown" then
			o.Hint.Text = "One moment..."
		else
			o.Hint.Text = CapsuleView.reasonText(reason)
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
	-- (the overlay's keys never also fire a prompt behind it: an egg's Buy Egg! / Auto)
	PromptController.setSuppressed("CapsuleOpening", true)
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
	keepSelection(o)
	local fx = hatch
	if fx then
		HatchFx.clear(fx)
	end
	o.Hero.ImageTransparency = 0
	heroPop(o).Scale = 1
	local spin = 0
	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		if not Motion.reduced() then
			spin += dt * 14 -- (Reduce motion: the rays stand still)
		end
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
	local plan = HatchFx.plan(if best then GolemConfig.order(best) else 1)
	local capsule = CapsuleConfig.ById[result.Capsule]
	local shell = if capsule then (capsule.Shell or capsule.Color) else Theme.Accent
	local ok, err = pcall(function()
		burst(o, result.Capsule, #kinds, plan, color, shell)
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
	endAt = os.clock()
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
	-- (the player closed it: OK, B / Backspace, Space / Enter; a new result doesn't count)
	local closed = endDone
	endDone = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	clearHero(o)
	atEnd = false
	playing = false
	autoNote = nil
	if selectionConnection then
		selectionConnection:Disconnect()
		selectionConnection = nil
	end
	ContextActionService:UnbindAction(SKIP_ACTION)
	ContextActionService:UnbindAction(SKIP_ALL_ACTION)
	if #queue == 0 then
		o.Gui.Enabled = false
		Sfx.loop("CaseCharge", false)
		if fx then
			HatchFx.clear(fx)
		end
		PromptController.setSuppressed("CapsuleOpening", false)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(o.Gui) then
			GuiService.SelectedObject = nil
		end
		local view = refs
		if view and shown and usingGamepad() then
			GuiService.SelectedObject = CapsuleView.firstButton(view)
		end
	end
	if closed then
		stopped("Closed")
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
	stopped(if type(payload.Reason) == "string" then payload.Reason else "Refused")
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
		-- "Full" for a capsule: the golem inventory (and how to make room)
		local text = if payload.Status == "Full"
			then CapsuleView.reasonText("InventoryFull")
			else MonetizationConfig.StatusText[payload.Status] or "That isn't sold here."
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
	for _, capsule in CapsuleConfig.Stall do
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
	-- an egg's own podium board always shows that egg (CapsuleService.hookPodium)
	for _, podium in CollectionService:GetTagged(PODIUM_TAG) do
		local holder = podium.Parent
		for _, board in if holder then holder:GetChildren() else {} do
			local own = board:GetAttribute("Capsule")
			local gui = if board.Name == "OddsBoard" then board:FindFirstChildWhichIsA("SurfaceGui") else nil
			if gui and type(own) == "string" and CapsuleConfig.ById[own] then
				local ownKey = `{own}|{lucky}`
				if boardSeen[gui] ~= ownKey then
					boardSeen[gui] = ownKey
					CapsuleView.fillBoard(gui, own, lucky)
				end
			end
		end
	end
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

-- The Lune specs (tests/EggPanel.spec.luau) stage an end screen and send opens through these, on fakes.
CapsuleController._test = {
	-- the end screen of `result` after the player's own `count` open of `capsule`, Auto on or off
	endScreen = function(result: Result, capsule: string, count: number, auto: boolean): CapsuleView.OpenRefs
		local o = ensureOpening()
		playing, atEnd = true, true
		autoOn = auto
		shownResult = result
		lastOpen = { Capsule = capsule, Count = count }
		openingHint(o, true)
		againText(o, result)
		return o
	end,
	close = function()
		playing, atEnd, autoOn, autoNote = false, false, false, nil
		lastOpen = nil
		pendingUntil, lastSend = 0, -math.huge
	end,
	again = function(o: CapsuleView.OpenRefs): boolean
		return holderOf(o.Again).Visible
	end,
	request = request,
	setAuto = CapsuleController.setAuto, -- (the real one: the specs swap the module's for a recorder)
}

function CapsuleController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind == "Capsules" then
			-- an egg's own podium opens the panel on that egg's tab
			local capsuleId = if type(payload) == "table" then payload.Capsule else nil
			if type(capsuleId) == "string" and CapsuleConfig.ById[capsuleId] then
				ensureView().Tab = capsuleId
				atPodium = capsuleId
			else
				atPodium = nil
			end
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
	ReplicatedStorage:GetAttributeChangedSignal(CapsuleView.ReceiptsAttribute):Connect(function()
		if shown then
			refresh()
		end
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
