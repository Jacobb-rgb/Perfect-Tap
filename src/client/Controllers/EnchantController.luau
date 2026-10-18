--[[
	EnchantController: the Enchant shop at the rune table (client side;
	EnchantService decides everything).

	- Opens on OpenUI "Enchant" { Counter } (the table's "Enchant" prompt,
	  added by EnchantService). Slots, catalog and the picked enchant's card
	  come from the State snapshot (EnchantView.cards / slotCards / odds),
	  the coins on screen (counted up like the HUD) and the shards, and
	  update live while it is open.
	- Pick an enchant in the list (click / tap / A); its card shows what it
	  does, now -> next tier, and for the odds boosters THE NEW ODDS per zone
	  before any buy (< > switch zones; it starts on the zone you stand in).
	- BUY sends EnchantAction "Buy" { Id, Currency, Tier } (Tier = the tier
	  the card shows being bought); the button shows "..." until the
	  ActionResult (or, for 20 R$, the PurchasePrompt) arrives, then
	  "BOUGHT!" or the reason on the status line. One request waits at a
	  time; with no answer the button is freed after a while (a repeat is
	  safe: the server refuses it as Stale). Greyed-out buttons (not
	  enough coins / shards, Coming soon, top tier) answer locally. An
	  enchant whose package isn't in the game yet (the ReplicatedStorage
	  attribute BoostView.SoonAttribute) shows COMING SOON.
	- EQUIP puts an owned enchant into the first free open slot; with every
	  open slot full it asks you to pick a slot on the left (the open slots
	  light up). UNEQUIP empties its slot. A tap on a filled slot shows that
	  enchant; on an empty slot it equips the picked enchant there. Slot
	  changes are free and work anywhere (EnchantAction "Slot").
	- A gamepad starts on the picked enchant's row, never on a buy button
	  (A is also jump: a reflex press right after the prompt buys nothing).
	- Closes with the X button, B (gamepad), Backspace, walking away from
	  the table, the table streaming out, respawning or another panel
	  opening. Other prompts are hidden while it is open.
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
local EnchantConfig = require(Shared.Config.EnchantConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local BoostView = require(script.Parent.Parent.UI.BoostView)
local EnchantView = require(script.Parent.Parent.UI.EnchantView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local EnchantController = {}

type Pending = { Op: string, Id: string, Product: string?, Button: TextButton?, Until: number }
type Panel = { isOpen: () -> boolean, close: () -> () }

local CLOSE_ACTION = "TerraForgeEnchantClose"
local SCROLL_ACTION = "TerraForgeEnchantScroll"
local SCROLL_SPEED = 700 -- design units per second at full stick
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25
local CLOSE_RANGE = EnchantView.CloseRange
local PENDING_TIMEOUT = 4
local FLASH_TIME = 0.9
local STATUS_TIME = 3.5
local RECEIPT_TIME = 5
local STATUS = EnchantView.StatusText
local RECEIPT_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
	Discovery = Theme.Accent,
}
-- the other panels (one in the middle of the screen at a time): MenuPanels.Names,
-- the one list of every panel controller (a name that isn't in the game is skipped)

local player = Players.LocalPlayer
local refs: EnchantView.Refs? = nil
local counter: BasePart? = nil
local tickConnection: RBXScriptConnection? = nil
local scrollConnection: RBXScriptConnection? = nil
local stickY = 0 -- the right stick (scrolls the card's middle on small screens)
local pending: Pending? = nil
local selected = EnchantConfig.List[1].Id
local zoneId: string? = nil
local picking: string? = nil -- an enchant waiting for a slot (every open slot was full)
local cardById: { [string]: EnchantView.Card } = {}
local slotCards: { EnchantView.SlotCard } = {}
local statusToken = 0
local shownStatus: { Text: string, Color: Color3 }? = nil
local receiptToken = 0
local openedAt = 0
local others: { Panel }? = nil

function EnchantController.isOpen(): boolean
	return counter ~= nil
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function restricted(): boolean
	return BoostView.restricted(player:GetAttribute(BoostView.RestrictedAttribute))
end

-- The enchants that are coming soon (their package isn't in the game yet).
local function soon(): { [string]: boolean }
	return BoostView.soonSet(ReplicatedStorage:GetAttribute(BoostView.SoonAttribute))
end

local function coins(): number
	return HudController.predictedCoins(os.clock())
end

local function blasterLevel(): number
	local state = StateController.get()
	local level = if state then tonumber(state.BlasterLevel) else nil
	return level or 1
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
	for _, name in MenuPanels.Names do
		if name == "EnchantController" then
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

---------------------------------------------------------------- messages

local function receipt(text: string, color: Color3)
	local view = refs
	if not view or not counter then
		return
	end
	EnchantView.showReceipt(view, text, color)
	receiptToken += 1
	local token = receiptToken
	task.delay(RECEIPT_TIME, function()
		local current = refs
		if receiptToken == token and current then
			EnchantView.hideReceipt(current)
		end
	end)
end

-- A message on the status line for a few seconds.
local function status(text: string, color: Color3)
	local view = refs
	if not view then
		return
	end
	shownStatus = { Text = text, Color = color }
	EnchantView.setStatus(view, text, color)
	statusToken += 1
	local token = statusToken
	task.delay(STATUS_TIME, function()
		local current = refs
		if statusToken == token and current then
			shownStatus = nil
			EnchantView.setStatus(current, nil, nil)
		end
	end)
end

local function clearStatus()
	statusToken += 1
	shownStatus = nil
	local view = refs
	if view then
		EnchantView.setStatus(view, nil, nil)
	end
end

---------------------------------------------------------------- refreshing

local function refresh()
	local view = refs
	if not view or not counter then
		return
	end
	local state = StateController.get()
	local cash = coins()
	EnchantView.setBalances(view, cash, EnchantView.shards(state))
	table.clear(cardById)
	local cards = EnchantView.cards(state, cash, restricted(), soon())
	for _, card in cards do
		cardById[card.Id] = card
	end
	slotCards = EnchantView.slotCards(state)
	EnchantView.setSlots(view, slotCards, blasterLevel(), picking)
	EnchantView.setRows(view, cards, selected)
	local card = cardById[selected]
	if card then
		local odds, canSwitch = EnchantView.odds(state, selected, zoneId, Workspace:GetServerTimeNow(), soon())
		EnchantView.setDetail(view, card, odds, canSwitch and #EnchantView.zoneIds(state) > 1)
	end
	local shown = shownStatus
	if shown then
		EnchantView.setStatus(view, shown.Text, shown.Color)
	elseif picking then
		EnchantView.setStatus(view, STATUS.PickSlot, Theme.Accent)
	end
end

local function selectDefault(view: EnchantView.Refs, force: boolean)
	if not usingGamepad() then
		return
	end
	local current = GuiService.SelectedObject
	if not force and current and current:IsDescendantOf(view.Gui) then
		return
	end
	-- the picked row, never a buy button (A is also jump)
	GuiService.SelectedObject = EnchantView.firstButton(view)
end

local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

local function updateGlyphs(view: EnchantView.Refs)
	local gamepad = usingGamepad()
	local holder = BoostView.holderOf(view.Close)
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
	local closeGlyph = glyph :: ImageLabel
	closeGlyph.Visible = gamepad
	if gamepad then
		closeGlyph.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
		local keys = { Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.Thumbstick2 }
		local images: { string } = {}
		local complete = true
		for i, key in keys do
			images[i] = UserInputService:GetImageForKeyCode(key)
			complete = complete and images[i] ~= ""
		end
		if complete then
			EnchantView.setHint(view, "", images)
		else
			EnchantView.setHint(
				view,
				`{padName(keys[1])}: pick / buy{EnchantView.Separator}{padName(keys[2])}: close{EnchantView.Separator}right stick: scroll`,
				nil
			)
		end
	elseif isTouch() then
		EnchantView.setHint(view, "Tap an enchant, then BUY or EQUIP", nil)
	else
		EnchantView.setHint(view, `Click an enchant, then BUY or EQUIP{EnchantView.Separator}Backspace: close`, nil)
	end
end

local function fit(view: EnchantView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = BoostView.compactFor(isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	EnchantView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

---------------------------------------------------------------- actions

local function setBusy(button: TextButton, text: string?)
	button:SetAttribute("Busy", text ~= nil)
	if text then
		button.Text = text
	end
end

local function send(op: string, id: string, args: { [string]: any }, button: TextButton?, product: string?)
	pending = { Op = op, Id = id, Product = product, Button = button, Until = os.clock() + PENDING_TIMEOUT }
	if button then
		setBusy(button, "...")
	end
	Sfx.play("UIClick")
	Net.send("EnchantAction", op, args)
end

local function choose(id: string)
	if not EnchantConfig.ById[id] then
		return
	end
	if selected ~= id then
		selected = id
		clearStatus()
	end
	refresh()
	Sfx.play("UIClick")
end

local function buy(index: number)
	local view = refs
	local card = cardById[selected]
	local option = if card then card.Buys[index] else nil
	local button = if view then view.Detail.Buttons[index] else nil
	if not view or not card or not option or not button or button:GetAttribute("Busy") == true then
		return
	end
	if pending then
		status(STATUS.Waiting, Theme.Info)
		Sfx.play("UIDeny")
		return
	end
	if not option.CanBuy then
		status(EnchantView.reasonText(option.Reason), if option.Reason == "ComingSoon" then Theme.Info else Theme.Bad)
		Sfx.play("UIDeny")
		return
	end
	picking = nil
	send("Buy", card.Id, { Id = card.Id, Currency = option.Currency, Tier = option.Tier }, button, option.Product)
end

-- Puts `id` into `slot` ("" empties it).
local function setSlot(slot: number, id: string)
	if pending then
		status(STATUS.Waiting, Theme.Info)
		Sfx.play("UIDeny")
		return
	end
	local view = refs
	send("Slot", id, { Slot = slot, Id = id }, if view then view.Detail.Equip else nil, nil)
end

local function equip()
	local card = cardById[selected]
	if not card or not card.Owned then
		return
	end
	if card.Slot then
		picking = nil
		setSlot(card.Slot, "")
		return
	end
	local state = StateController.get()
	local free = EnchantConfig.firstFreeSlot(if state then state.Enchants else nil, blasterLevel())
	if free then
		picking = nil
		setSlot(free, card.Id)
		return
	end
	-- every open slot is full: pick one on the left
	picking = card.Id
	clearStatus()
	refresh()
	Sfx.play("UIClick")
	local view = refs
	if view and usingGamepad() then
		GuiService.SelectedObject = view.Slots[1].Button
	end
end

local function onSlot(index: number)
	local slot = slotCards[index]
	if not slot then
		return
	end
	if not slot.Open then
		status(EnchantConfig.Reasons.Locked .. ` (level {slot.Need})`, Theme.Bad)
		Sfx.play("UIDeny")
		return
	end
	local waiting = picking
	if waiting then
		picking = nil
		setSlot(index, waiting)
		return
	end
	if slot.Id then
		choose(slot.Id)
		return
	end
	-- an empty slot: the picked enchant goes there when you own it
	local card = cardById[selected]
	if card and card.Owned then
		setSlot(index, card.Id)
	else
		status("Pick an enchant you own, then a slot", Theme.Info)
		Sfx.play("UIDeny")
	end
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

local function release(): TextButton?
	local wait = pending
	pending = nil
	local button = if wait then wait.Button else nil
	if button then
		setBusy(button, nil)
	end
	return button
end

local function onActionResult(payload: any)
	if type(payload) ~= "table" or payload.Action ~= "Enchant" then
		return
	end
	local wait = pending
	if wait and payload.Op ~= wait.Op then
		return
	end
	local button = release()
	local view = refs
	if payload.Ok == true then
		if payload.Op == "Buy" then
			Sfx.play("CoinBurst")
			if view and counter then
				pop(view.Detail.Frame)
				if button then
					setBusy(button, "BOUGHT!")
					BoostView.style(button, true, Theme.Good, Theme.GoodDark)
					task.delay(FLASH_TIME, function()
						setBusy(button, nil)
						refresh()
					end)
				elseif not wait then
					status(STATUS.LateBought, Theme.Good)
				end
			end
		else
			Sfx.play("UIClick")
			if counter then
				status(if payload.Id == "" then STATUS.Unequipped else STATUS.Equipped, Theme.Good)
			end
		end
		refresh()
		return
	end
	local reason = if type(payload.Reason) == "string" then payload.Reason else nil
	local text = EnchantView.reasonText(reason)
	if counter then
		status(text, Theme.Bad)
		Sfx.play("UIDeny")
		refresh()
	else
		HudController.toast(text, "Deny")
	end
end

local function onPurchasePrompt(payload: any)
	local wait = pending
	if type(payload) ~= "table" or not wait or wait.Product == nil or payload.Product ~= wait.Product then
		return
	end
	release()
	local code = if type(payload.Status) == "string" then payload.Status else "Unknown"
	if code ~= "Prompted" and counter then
		status(
			MonetizationConfig.StatusText[code] or MonetizationConfig.StatusText.Unknown,
			if code == "ComingSoon" then Theme.Info else Theme.Bad
		)
	end
	refresh()
end

local function expirePending(force: boolean?)
	local wait = pending
	if wait and (force or os.clock() > wait.Until) then
		release()
		if not force and counter then
			status(STATUS.NoAnswer, Theme.Bad)
			refresh()
		end
	end
end

local function cycleZone(step: number)
	zoneId = BoostView.cycle(EnchantView.zoneIds(StateController.get()), zoneId, step)
	Sfx.play("UIClick")
	refresh()
end

---------------------------------------------------------------- open / close

function EnchantController.close()
	if not counter then
		return
	end
	expirePending(true)
	clearStatus()
	counter = nil
	picking = nil
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
	ContextActionService:UnbindAction(SCROLL_ACTION)
	local view = refs
	if view then
		local current = GuiService.SelectedObject
		if current and current:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		EnchantView.hideReceipt(view)
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Enchant", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not counter then
		return Enum.ContextActionResult.Pass
	end
	-- B while picking a slot: stop picking first
	if picking then
		picking = nil
		clearStatus()
		refresh()
		return Enum.ContextActionResult.Sink
	end
	EnchantController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

-- The right stick scrolls the card's middle (and the odds in it) on small screens.
local function onStick(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not counter then
		return Enum.ContextActionResult.Pass
	end
	stickY = if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then 0 else input.Position.Y
	return Enum.ContextActionResult.Sink
end

local function ensureView(): EnchantView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = EnchantView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		EnchantController.close()
		Sfx.play("UIClick")
	end)
	for _, row in view.RowList do
		local id = row.Id
		row.Button.Activated:Connect(function()
			-- a pick for a slot ends when you choose another row
			if picking then
				picking = nil
				clearStatus()
			end
			choose(id)
		end)
	end
	for index, slot in view.Slots do
		slot.Button.Activated:Connect(function()
			onSlot(index)
		end)
	end
	for index, button in view.Detail.Buttons do
		button.Activated:Connect(function()
			buy(index)
		end)
	end
	view.Detail.Equip.Activated:Connect(equip)
	view.Detail.Odds.Prev.Activated:Connect(function()
		cycleZone(-1)
	end)
	view.Detail.Odds.Next.Activated:Connect(function()
		cycleZone(1)
	end)
	refs = view
	return view
end

local function watch(part: BasePart)
	local elapsed = 0
	local sinceRefresh = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		sinceRefresh += elapsed
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not part:IsDescendantOf(Workspace) or not root then
			EnchantController.close()
			return
		end
		local p = part.CFrame:PointToObjectSpace(root.Position)
		local half = part.Size / 2
		local outside =
			Vector3.new(math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Y) - half.Y, 0), math.max(math.abs(p.Z) - half.Z, 0))
		if outside.Magnitude > CLOSE_RANGE then
			EnchantController.close()
			return
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					EnchantController.close()
					return
				end
			end
		end
		expirePending()
		-- coins count up between snapshots: affordability follows them
		if sinceRefresh >= 1 then
			sinceRefresh = 0
			refresh()
		else
			local view = refs
			if view then
				EnchantView.setBalances(view, coins(), EnchantView.shards(StateController.get()))
			end
		end
	end)
end

function EnchantController.open(part: BasePart)
	if counter == part then
		refresh()
		return
	end
	local owner = PlayerControls.owner()
	if owner ~= nil then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return
	end
	EnchantController.close()
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	local view = ensureView()
	counter = part
	openedAt = os.clock()
	picking = nil
	zoneId = BoostView.defaultZone(StateController.get(), standingZone())
	fit(view)
	updateGlyphs(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("Enchant", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(SCROLL_ACTION, onStick, false, CLOSE_PRIORITY, Enum.KeyCode.Thumbstick2)
	scrollConnection = RunService.Heartbeat:Connect(function(dt)
		if math.abs(stickY) > 0.2 then
			BoostView.scrollBy(view.Detail.Body, -stickY * SCROLL_SPEED * dt)
		end
	end)
	watch(part)
	GuiService.SelectedObject = nil
	refresh()
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

---------------------------------------------------------------- lifecycle

function EnchantController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Enchant" or type(payload) ~= "table" then
			return
		end
		local part = payload.Counter
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			EnchantController.open(part)
		end
	end)
	Net.listen("ActionResult", onActionResult)
	Net.listen("PurchasePrompt", onPurchasePrompt)
	Net.listen("Notify", function(message)
		if counter and type(message) == "table" and type(message.Text) == "string" then
			local color = if type(message.Kind) == "string" then RECEIPT_COLORS[message.Kind] or Theme.Info else Theme.Info
			local info = if type(message.Rarity) == "string" then Rarity.ById[message.Rarity] else nil
			receipt(message.Text, if info then info.Color else color)
		end
	end)
	StateController.onChanged(function()
		if counter then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal(BoostView.RestrictedAttribute):Connect(function()
		if counter then
			refresh()
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal(BoostView.SoonAttribute):Connect(function()
		if counter then
			refresh()
		end
	end)
	player.CharacterRemoving:Connect(function()
		EnchantController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and counter then
			updateGlyphs(view)
			selectDefault(view, false)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and counter then
				fit(view)
				refresh()
			end
		end)
	end
end

return EnchantController
