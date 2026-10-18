--[[
	BoostController: the luck boosts view (BoostView) and the boost chips
	under the HUD coins (client side; BoostService decides everything).

	- BoostController.open(kind?) opens the view (the side menu calls it
	  later); also a tap on a chip, the BOOSTS launcher chip (shown while no
	  boost runs; setLauncher(false) hides it once the side menu has a
	  Boosts button), or the keys in BoostController.OpenKeys: L toggles
	  it, D-pad right only opens it (inside the view the D-pad moves the
	  gamepad selection; B closes).
	- The chips sit in the left column under the TRAIN chip (read from its
	  ScreenGui, so they follow its phone / PC size) and hide with the HUD
	  (the cleaning close-up turns the HUD off) and while a panel is open.
	- The cards and THE ODDS come from the State snapshot (Boosts, Bonuses,
	  BlasterLevel, Perks), the coins on screen (counted up like the HUD)
	  and workspace:GetServerTimeNow() for the timers, refreshed every
	  quarter second while open. Hexa Lucky's table starts on the zone you
	  stand in (or the hardest one you can mine); Triple Lucky's on the
	  Crystal capsule; < > switch (also on a gamepad: select them).
	  A boost whose package isn't in the game yet (the ReplicatedStorage
	  attribute BoostView.SoonAttribute) shows COMING SOON.
	- An offer sends BoostAction "BuyCoins" / "BuyRobux" { Id }; the button
	  shows "..." until the ActionResult (coins) or PurchasePrompt (Robux)
	  arrives, then "BOUGHT!" or the reason on the card's note line. One buy
	  waits at a time; with no answer the button is freed after a while (a
	  coin top-up is safe to repeat: the server refuses past its limits).
	  A greyed-out offer (can't afford, CoinLimit, Coming soon...) answers
	  locally and sends nothing. Robux packs are hidden where paid random
	  items are restricted (the player attribute PaidRandomRestricted; not
	  known yet = restricted).
	- Tabs: click / tap, or LB / RB on a gamepad. Opened without a kind,
	  the view shows the last tab while it can be bought, else the first
	  one that can (BoostView.openTab: Hexa Lucky while Triple Lucky is
	  coming soon). Gamepads start on the open tab, never on an offer (A
	  is also jump); the selection stays inside the panel.
	- Closes with the X button, B, Backspace, L again, respawning, the HUD
	  going away or another panel (shops, pen, train...) opening.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.Config.BoostConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local BoostView = require(script.Parent.Parent.UI.BoostView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local BoostController = {}

type Pending = { Op: string, Id: string, Product: string?, Button: number, Until: number }
type Panel = { isOpen: () -> boolean, close: () -> () }

-- keys that open the view (keyboard, gamepad); L also closes it, D-pad right never does
BoostController.OpenKeys = { Enum.KeyCode.L, Enum.KeyCode.DPadRight }

local CLOSE_ACTION = "TerraForgeBoostsClose"
local TAB_ACTION = "TerraForgeBoostsTab"
local OPEN_ACTION = "TerraForgeBoostsOpen"
local SCROLL_ACTION = "TerraForgeBoostsScroll"
local SCROLL_SPEED = 700 -- design units per second at full stick
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25
local CHIP_TICK = 0.5
local PENDING_TIMEOUT = 4
local FLASH_TIME = 0.9
local STATUS_TIME = 3.5
local RECEIPT_TIME = 5
local PROMPT_MEMORY = 10 -- seconds a Robux request waits for its PurchasePrompt answer
local RECEIPT_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
	Discovery = Theme.Accent,
}
-- panels that own the middle of the screen: one at a time (a name that
-- isn't in the game yet is skipped: the step 6-7 panels are built in parallel)
local OTHER_PANELS = {
	"TechShopController",
	"EnchantController",
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"GearShopController",
	"CapsuleController",
	"GolemController",
	"ArtifactController",
	"WheelController",
	"CodexController",
	"LeaderboardController",
	"SettingsController",
}

local player = Players.LocalPlayer
local refs: BoostView.Refs? = nil
local chipRefs: BoostView.ChipRefs? = nil
local isOpen = false
local launcherOn = true
local tickConnection: RBXScriptConnection? = nil
local scrollConnection: RBXScriptConnection? = nil
local stickY = 0 -- the right stick (scrolls the odds list)
local pending: Pending? = nil
local zoneId: string? = nil
local capsuleId: string? = nil
local cards: { [string]: BoostView.Card } = {}
local statusToken = 0
-- the message on the card's note line right now (refresh keeps it until its timer ends)
local shownStatus: { Text: string, Color: Color3 }? = nil
local receiptToken = 0
local openedAt = 0
local others: { Panel }? = nil
-- Robux products asked for, for a late PurchasePrompt answer (product -> os.clock())
local asked: { [string]: number } = {}

function BoostController.isOpen(): boolean
	return isOpen
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

local function restricted(): boolean
	return BoostView.restricted(player:GetAttribute(BoostView.RestrictedAttribute))
end

-- The boosts that are coming soon (their package isn't in the game yet).
local function soon(): { [string]: boolean }
	return BoostView.soonSet(ReplicatedStorage:GetAttribute(BoostView.SoonAttribute))
end

-- Is the HUD on screen (the cleaning close-up and other takeovers turn it off)?
local function hudShown(): boolean
	local hud = HudController.refs()
	return hud == nil or hud.Gui.Enabled
end

-- The HUD's layout for the train chip (as TrainController picks it).
local function compactHud(): boolean
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return isTouch() or HudController.uiScale() <= 0.75 or size.Y < 520
end

-- The train chip's frame (TrainView: ScreenGui "TerraForgeTrain", frame "TrainChip").
local function trainChip(): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = if playerGui then playerGui:FindFirstChild("TerraForgeTrain") else nil
	local frame = if gui then gui:FindFirstChild("TrainChip") else nil
	return if frame and frame:IsA("GuiObject") then frame else nil
end

local function coins(): number
	return HudController.predictedCoins(os.clock())
end

local function standingZone(): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local zone = WorldLayout.zoneAt(root.Position)
	return if zone then zone.Id else nil
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

---------------------------------------------------------------- messages

local function receipt(text: string, color: Color3)
	local view = refs
	if not view or not isOpen then
		return
	end
	BoostView.showReceipt(view, text, color)
	receiptToken += 1
	local token = receiptToken
	task.delay(RECEIPT_TIME, function()
		local current = refs
		if receiptToken == token and current then
			BoostView.hideReceipt(current)
		end
	end)
end

-- A message on the card's note line for a few seconds.
local function status(text: string, color: Color3)
	local view = refs
	if not view then
		return
	end
	local card = cards[view.Tab]
	shownStatus = { Text = text, Color = color }
	BoostView.setStatus(view, text, color, if card then card.Note else "")
	statusToken += 1
	local token = statusToken
	task.delay(STATUS_TIME, function()
		local current = refs
		if statusToken == token and current then
			shownStatus = nil
			local now = cards[current.Tab]
			BoostView.setStatus(current, nil, nil, if now then now.Note else "")
		end
	end)
end

local function clearStatus()
	statusToken += 1
	shownStatus = nil
end

---------------------------------------------------------------- refreshing

-- Is a panel open that owns the middle of the screen (this one included)?
local function panelOpen(): boolean
	if isOpen then
		return true
	end
	for _, panel in otherPanels() do
		if panel.isOpen() then
			return true
		end
	end
	return false
end

-- The chips hide with the HUD and while a panel is open (a wide panel would
-- cut them off; the Boosts panel shows the same timers). They stay under the
-- train chip, whatever size it has.
local function refreshChips()
	local chips = chipRefs
	if not chips then
		return
	end
	chips.Gui.Enabled = hudShown() and not panelOpen()
	BoostView.placeChips(chips, BoostView.chipsTop(trainChip(), compactHud()))
	BoostView.setChips(chips, BoostView.chips(StateController.get(), serverNow()), launcherOn)
end

local function refresh()
	local view = refs
	if not view or not isOpen then
		return
	end
	local state = StateController.get()
	local cash = coins()
	BoostView.setCoins(view, cash)
	table.clear(cards)
	for _, card in BoostView.cards(state, cash, serverNow(), restricted(), soon()) do
		cards[card.Kind] = card
	end
	local card = cards[view.Tab]
	if card then
		BoostView.setCard(view, card)
		-- a message on the note line stays until its timer clears it
		local shown = shownStatus
		if shown then
			BoostView.setStatus(view, shown.Text, shown.Color, card.Note)
		end
	end
	local kind = BoostConfig.Kinds[view.Tab]
	if kind and kind.Target == "Mining" then
		local zones = BoostView.zones(state)
		BoostView.setTable(view.Odds, BoostView.hexaOdds(state, zoneId), #zones > 1)
	else
		local capsules = BoostView.capsules(restricted())
		if capsuleId == nil or not table.find(capsules, capsuleId) then
			capsuleId = if table.find(capsules, "Crystal") then "Crystal" else capsules[1]
		end
		BoostView.setTable(view.Odds, BoostView.tripleOdds(capsuleId), #capsules > 1)
	end
end

local function selectDefault(view: BoostView.Refs, force: boolean)
	if not usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if not force and selected and selected:IsDescendantOf(view.Gui) then
		return
	end
	-- the open tab, never an offer (A is also jump)
	GuiService.SelectedObject = BoostView.firstButton(view)
end

local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

-- The footer hint and the glyphs (Xbox or PlayStation) on a gamepad.
local function updateGlyphs(view: BoostView.Refs)
	local gamepad = usingGamepad()
	for i, image in view.TabGlyphs do
		image.Visible = gamepad
		if gamepad then
			image.Image = UserInputService:GetImageForKeyCode(if i == 1 then Enum.KeyCode.ButtonL1 else Enum.KeyCode.ButtonR1)
		end
	end
	if gamepad then
		local keys = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.Thumbstick2 }
		local images: { string } = {}
		local complete = true
		for i, key in keys do
			images[i] = UserInputService:GetImageForKeyCode(key)
			complete = complete and images[i] ~= ""
		end
		if complete then
			BoostView.setHint(view, "", images)
		else
			local names: { string } = {}
			for i, key in keys do
				names[i] = padName(key)
			end
			BoostView.setHint(
				view,
				`{names[1]} / {names[2]}: switch boost{BoostView.Separator}{names[3]}: buy{BoostView.Separator}{names[4]}: close{BoostView.Separator}right stick: scroll`,
				nil
			)
		end
	elseif isTouch() then
		BoostView.setHint(view, "Tap a boost, then an offer", nil)
	else
		BoostView.setHint(view, `Click an offer to buy{BoostView.Separator}L or Backspace: close`, nil)
	end
end

local function updateChipGlyph()
	local chips = chipRefs
	if not chips then
		return
	end
	local gamepad = usingGamepad()
	local image = if gamepad then UserInputService:GetImageForKeyCode(BoostController.OpenKeys[2]) else ""
	chips.Glyph.Image = image
	chips.Glyph.Visible = gamepad and image ~= ""
end

local function fit(view: BoostView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = BoostView.compactFor(isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	BoostView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

---------------------------------------------------------------- buying

local function setBusy(button: TextButton, text: string?)
	button:SetAttribute("Busy", text ~= nil)
	if text then
		button.Text = text
	end
end

local function buy(index: number)
	local view = refs
	local card = if view then cards[view.Tab] else nil
	local offer = if card then card.Offers[index] else nil
	local button = if view then view.Card.Offers[index] else nil
	if not view or not card or not offer or not button or button:GetAttribute("Busy") == true then
		return
	end
	if pending then
		status("Wait for your last buy", Theme.Info)
		Sfx.play("UIDeny")
		return
	end
	if not offer.CanBuy then
		status(BoostView.reasonText(offer.Reason), if offer.Reason == "ComingSoon" then Theme.Info else Theme.Bad)
		Sfx.play("UIDeny")
		return
	end
	local op = if offer.Robux then "BuyRobux" else "BuyCoins"
	pending = { Op = op, Id = offer.Id, Product = offer.Product, Button = index, Until = os.clock() + PENDING_TIMEOUT }
	if offer.Product then
		asked[offer.Product] = os.clock()
	end
	setBusy(button, "...")
	Sfx.play("UIClick")
	Net.send("BoostAction", op, { Id = offer.Id })
end

local function pop(frame: GuiObject)
	local scale = frame:FindFirstChild("Pop") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "Pop"
		made.Parent = frame
		scale = made
	end
	local s = scale :: UIScale
	s.Scale = 1.04
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The button of the pending buy, freed (its text comes back on the next refresh).
local function release(): TextButton?
	local wait = pending
	pending = nil
	local view = refs
	local button = if wait and view then view.Card.Offers[wait.Button] else nil
	if button then
		setBusy(button, nil)
	end
	return button
end

local function onActionResult(payload: any)
	if type(payload) ~= "table" or payload.Action ~= "Boost" then
		return
	end
	local wait = pending
	if wait and (payload.Id ~= wait.Id or payload.Op ~= wait.Op) then
		return
	end
	local button = release()
	if payload.Ok == true then
		Sfx.play("CoinBurst")
		refreshChips()
		local view = refs
		if view and isOpen then
			pop(view.Card.Frame)
			if button then
				setBusy(button, "BOUGHT!")
				BoostView.style(button, true, Theme.Good, Theme.GoodDark)
				task.delay(FLASH_TIME, function()
					setBusy(button, nil)
					refresh()
				end)
			end
		end
		return
	end
	local reason = if type(payload.Reason) == "string" then payload.Reason else nil
	local text = BoostView.reasonText(reason)
	if isOpen then
		status(text, Theme.Bad)
		Sfx.play("UIDeny")
		refresh()
	else
		HudController.toast(text, "Deny")
	end
end

local function onPurchasePrompt(payload: any)
	if type(payload) ~= "table" or type(payload.Product) ~= "string" then
		return
	end
	local product = payload.Product :: string
	local wait = pending
	local mine = (wait ~= nil and wait.Product == product)
	local askedAt = asked[product]
	if not mine and not (askedAt and os.clock() - askedAt < PROMPT_MEMORY) then
		return -- another view's product
	end
	asked[product] = nil
	if mine then
		release()
	end
	local statusCode = if type(payload.Status) == "string" then payload.Status else "Unknown"
	if statusCode == "Prompted" then
		refresh()
		return
	end
	local text = MonetizationConfig.StatusText[statusCode] or MonetizationConfig.StatusText.Unknown
	if isOpen then
		status(text, if statusCode == "ComingSoon" then Theme.Info else Theme.Bad)
		refresh()
	else
		HudController.toast(text, "Info")
	end
end

-- A buy with no answer frees its button (the server may still answer: that is shown then).
local function expirePending(force: boolean?)
	local wait = pending
	if wait and (force or os.clock() > wait.Until) then
		release()
		if not force and isOpen then
			status("No answer, try again", Theme.Bad)
			refresh()
		end
	end
end

---------------------------------------------------------------- open / close

local function switchTab(kindId: string, moveSelection: boolean)
	local view = refs
	if not view or not BoostConfig.Kinds[kindId] or view.Tab == kindId then
		return
	end
	BoostView.setTab(view, kindId)
	clearStatus()
	refresh()
	Sfx.play("UIClick")
	if moveSelection then
		selectDefault(view, true)
	end
end

-- < > on the odds table: the next zone (Hexa Lucky) or capsule (Triple Lucky).
local function cycleOdds(step: number)
	local view = refs
	if not view then
		return
	end
	local kind = BoostConfig.Kinds[view.Tab]
	if kind and kind.Target == "Mining" then
		local ids = {}
		for _, zone in BoostView.zones(StateController.get()) do
			table.insert(ids, zone.Id)
		end
		zoneId = BoostView.cycle(ids, zoneId, step)
	else
		capsuleId = BoostView.cycle(BoostView.capsules(restricted()), capsuleId, step)
	end
	Sfx.play("UIClick")
	refresh()
end

function BoostController.close()
	if not isOpen then
		return
	end
	expirePending(true)
	clearStatus()
	isOpen = false
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	if scrollConnection then
		scrollConnection:Disconnect()
		scrollConnection = nil
	end
	stickY = 0
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(TAB_ACTION)
	ContextActionService:UnbindAction(SCROLL_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		BoostView.hideReceipt(view)
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Boosts", false)
	refreshChips()
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	BoostController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function onTab(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local view = refs
	if state ~= Enum.UserInputState.Begin or not isOpen or not view then
		return Enum.ContextActionResult.Pass
	end
	switchTab(BoostView.nextTab(view.Tab, if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1), true)
	return Enum.ContextActionResult.Sink
end

-- The right stick scrolls the odds list (its rows can't be selected).
local function onStick(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not isOpen then
		return Enum.ContextActionResult.Pass
	end
	stickY = if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then 0 else input.Position.Y
	return Enum.ContextActionResult.Sink
end

local function ensureView(): BoostView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = BoostView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		BoostController.close()
		Sfx.play("UIClick")
	end)
	for kindId, tab in view.Tabs do
		tab.Activated:Connect(function()
			switchTab(kindId, false)
		end)
	end
	for index, button in view.Card.Offers do
		button.Activated:Connect(function()
			buy(index)
		end)
	end
	view.Odds.Prev.Activated:Connect(function()
		cycleOdds(-1)
	end)
	view.Odds.Next.Activated:Connect(function()
		cycleOdds(1)
	end)
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
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					BoostController.close()
					return
				end
			end
		end
		expirePending()
		refresh()
	end)
end

-- Opens the view (on `kindId`'s tab when given). Refused while build mode or a minigame holds the controls.
function BoostController.open(kindId: string?)
	local owner = PlayerControls.owner()
	if owner ~= nil then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return
	end
	local view = ensureView()
	if kindId and BoostConfig.Kinds[kindId] then
		BoostView.setTab(view, kindId)
	elseif not isOpen then
		-- no boost asked for (the launcher, L, D-pad right, the side menu):
		-- the last tab while it can be bought, else the first one that can
		BoostView.setTab(view, BoostView.openTab(view.Tab, StateController.get(), soon()))
	end
	if isOpen then
		refresh()
		return
	end
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	isOpen = true
	openedAt = os.clock()
	zoneId = BoostView.defaultZone(StateController.get(), standingZone())
	fit(view)
	updateGlyphs(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("Boosts", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(TAB_ACTION, onTab, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority(SCROLL_ACTION, onStick, false, CLOSE_PRIORITY, Enum.KeyCode.Thumbstick2)
	scrollConnection = RunService.Heartbeat:Connect(function(dt)
		local list = view.Odds.List
		if math.abs(stickY) > 0.2 then
			BoostView.scrollBy(list, -stickY * SCROLL_SPEED * dt)
		end
	end)
	watch()
	GuiService.SelectedObject = nil
	refresh()
	refreshChips()
	selectDefault(view, true)
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

function BoostController.toggle(kindId: string?)
	if isOpen then
		BoostController.close()
	else
		BoostController.open(kindId)
	end
end

-- The BOOSTS launcher chip (shown while no boost runs). The side menu turns it off once it has a Boosts button.
function BoostController.setLauncher(visible: boolean)
	launcherOn = visible
	refreshChips()
end

local function onOpenKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if isOpen then
		-- L closes; the D-pad moves the gamepad selection inside the view (B closes)
		if input.KeyCode == Enum.KeyCode.DPadRight then
			return Enum.ContextActionResult.Pass
		end
		BoostController.close()
		return Enum.ContextActionResult.Sink
	end
	-- only when nothing else uses the selection or the controls
	if GuiService.SelectedObject ~= nil or PlayerControls.owner() ~= nil then
		return Enum.ContextActionResult.Pass
	end
	BoostController.open(nil)
	return Enum.ContextActionResult.Sink
end

---------------------------------------------------------------- lifecycle

function BoostController.init()
	local chips = BoostView.buildChips()
	chips.Gui.Parent = player:WaitForChild("PlayerGui")
	chips.Launcher.Activated:Connect(function()
		BoostController.open(nil)
	end)
	for kindId, button in chips.Chips do
		button.Activated:Connect(function()
			BoostController.open(kindId)
		end)
	end
	chipRefs = chips

	Net.listen("ActionResult", onActionResult)
	Net.listen("PurchasePrompt", onPurchasePrompt)
	Net.listen("Notify", function(message)
		if isOpen and type(message) == "table" and type(message.Text) == "string" then
			local color = if type(message.Kind) == "string" then RECEIPT_COLORS[message.Kind] or Theme.Info else Theme.Info
			local info = if type(message.Rarity) == "string" then Rarity.ById[message.Rarity] else nil
			receipt(message.Text, if info then info.Color else color)
		end
	end)
	StateController.onChanged(function()
		refreshChips()
		if isOpen then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal(BoostView.RestrictedAttribute):Connect(function()
		if isOpen then
			refresh()
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal(BoostView.SoonAttribute):Connect(function()
		if isOpen then
			refresh()
		end
	end)
	player.CharacterRemoving:Connect(function()
		BoostController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		updateChipGlyph()
		local view = refs
		if view and isOpen then
			updateGlyphs(view)
			selectDefault(view, false)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and isOpen then
				fit(view)
				refresh()
			end
		end)
	end
end

function BoostController.start()
	ContextActionService:BindAction(OPEN_ACTION, onOpenKey, false, table.unpack(BoostController.OpenKeys))
	updateChipGlyph()
	-- the chips follow the HUD (the cleaning close-up hides it), and the view closes with it
	local hud = HudController.refs()
	if hud then
		hud.Gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not hud.Gui.Enabled then
				BoostController.close()
			end
			refreshChips()
		end)
	end
	-- the chips' timers count down between snapshots
	while true do
		refreshChips()
		task.wait(CHIP_TICK)
	end
end

return BoostController
