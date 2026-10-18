--[[
	GearShopController: the Gear shop at the SHOP stall (client side).

	- Opens on OpenUI "Gear" { Counter, Preview } (the stall's "Gear Shop"
	  prompt, added by GearService). The five cards come from the State
	  snapshot (GearShopView.cards with your coins, counted up between
	  snapshots like the HUD) and the server's Preview (the real numbers
	  with every bonus; every Gear ActionResult brings a fresh one) and
	  update live while it is open.
	- BUY sends GearAction ("Buy", { Line, Level }) with Level = the level
	  the card shows being bought. The button shows "..." until the server's
	  ActionResult (Action "Gear") arrives, then "BOUGHT!" for a moment, or
	  the reason (GearConfig.Reasons) in the card's effect box. One BUY per
	  card waits at a time. With no answer (the rate limit dropped it, or a
	  slow link) the button is freed after PENDING_TIMEOUT: trying again is
	  safe, the server refuses a repeat of a level that went through as
	  "Stale"; an answer that still comes marks the card "Bought!". A
	  greyed-out button (can't afford, top level) answers locally with the
	  same texts and sends nothing. The success toast comes from the server
	  (Notify); while the shop is open messages also show in its header.
	  A refused buy with the shop closed shows a HUD toast.
	- Gamepads get a selected BUY button on open; the selection stays inside
	  the panel (SelectionGroup). The footer shows the platform's glyphs
	  (A buy, B close), on TVs too (the compact layout makes room for it).
	  Once every line is at the top level the hint says "All gear at the
	  top level" instead of asking to buy.
	- Closes with the X button, B (gamepad), Backspace, walking away from the
	  counter, the counter streaming out, respawning or another panel (Pen,
	  Sell, Train, Tech shop...) opening. Other prompts are hidden while it
	  is open.
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
local GearConfig = require(Shared.Config.GearConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local GearShopView = require(script.Parent.Parent.UI.GearShopView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local GearShopController = {}

type Pending = { Line: string, Until: number }
type Panel = { isOpen: () -> boolean, close: () -> () }

local CLOSE_ACTION = "TerraForgeGearShopClose"
-- above the default player controls, so B / Backspace close the shop first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25
local CLOSE_RANGE = GearShopView.CloseRange
-- seconds a BUY waits for its ActionResult before its button is freed
local PENDING_TIMEOUT = 3
local FLASH_TIME = 0.9 -- "BOUGHT!" on the button
local STATUS_TIME = 3.5 -- a reason in the card's effect box
local STATUS = GearShopView.StatusText
local RECEIPT_TIME = 5 -- a message in the header
local RECEIPT_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
	Discovery = Theme.Accent,
}
-- panels that own the middle of the screen: one at a time (names that
-- don't exist yet are skipped; the steps 6-7 shops and menus are listed so
-- they close each other once they are merged in)
local OTHER_PANELS = {
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"TechShopController",
	"EnchantController",
	"BoostController",
	"CapsuleController",
	"GolemController",
	"WheelController",
	"ArtifactController",
	"CodexController",
	"LeaderboardController",
	"SettingsController",
}

local player = Players.LocalPlayer
local refs: GearShopView.Refs? = nil
local counter: BasePart? = nil
local tickConnection: RBXScriptConnection? = nil
local pending: { [string]: Pending } = {}
local statusTokens: { [string]: number } = {}
local receiptToken = 0
local openedAt = 0
local others: { Panel }? = nil
-- the server's numbers for the cards (GearService.preview), from OpenUI and every ActionResult
local preview: { [string]: any }? = nil
-- every line at the top level: the hint says so instead of "BUY"
local allDone = false

function GearShopController.isOpen(): boolean
	return counter ~= nil
end

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function coins(): number
	return HudController.predictedCoins(os.clock())
end

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

-- The other panel controllers that exist (required on first use: they may load after this one).
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

-- A message in the header for a few seconds.
local function receipt(text: string, color: Color3)
	local view = refs
	if not view or not counter then
		return
	end
	GearShopView.showReceipt(view, text, color)
	receiptToken += 1
	local token = receiptToken
	task.delay(RECEIPT_TIME, function()
		local current = refs
		if receiptToken == token and current then
			GearShopView.hideReceipt(current)
		end
	end)
end

-- A message in a card's effect box for a few seconds.
local function status(lineId: string, text: string, color: Color3)
	local view = refs
	if not view then
		return
	end
	GearShopView.setStatus(view, lineId, text, color)
	local token = (statusTokens[lineId] or 0) + 1
	statusTokens[lineId] = token
	task.delay(STATUS_TIME, function()
		local current = refs
		if statusTokens[lineId] == token and current then
			GearShopView.setStatus(current, lineId, nil, nil)
		end
	end)
end

-- The text for a reason code (GearConfig.Reasons).
function GearShopController.reasonText(reason: any): string
	local text = if type(reason) == "string" then GearConfig.Reasons[reason] else nil
	return text or "You can't buy that right now"
end

---------------------------------------------------------------- refreshing

local function selectDefault(view: GearShopView.Refs, force: boolean)
	if not usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if not force and selected and selected:IsDescendantOf(view.Gui) then
		return
	end
	GuiService.SelectedObject = GearShopView.firstButton(view)
end

-- A gamepad button's name on this platform ("A" / "Cross"), for when it has no glyph image.
local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

-- The footer hint: the platform's own glyphs on a gamepad (Xbox or
-- PlayStation; the compact TV layout shows it too), and no "buy" once
-- every line is at the top level (allDone, set by refresh).
local function updateHint(view: GearShopView.Refs)
	if usingGamepad() then
		local keys = { Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB }
		local images: { string } = {}
		local complete = true
		for i, key in keys do
			images[i] = UserInputService:GetImageForKeyCode(key)
			complete = complete and images[i] ~= ""
		end
		if complete then
			GearShopView.setHint(view, "", images, true, allDone)
		else
			local text = GearShopView.hintText("Pad", allDone, padName(keys[1]), padName(keys[2]))
			GearShopView.setHint(view, text, nil, true, allDone)
		end
	elseif isTouch() then
		GearShopView.setHint(view, GearShopView.hintText("Touch", allDone), nil, false, allDone)
	else
		GearShopView.setHint(view, GearShopView.hintText("Mouse", allDone), nil, false, allDone)
	end
end

local function refresh()
	local view = refs
	if not view or not counter then
		return
	end
	local cash = coins()
	GearShopView.setCoins(view, cash)
	local cards = GearShopView.cards(StateController.get(), cash, preview)
	GearShopView.setCards(view, cards)
	local done = GearShopView.allDone(cards)
	if done ~= allDone then
		allDone = done
		updateHint(view)
	end
end

-- The platform's own B glyph on the close button.
local function updateGlyphs(view: GearShopView.Refs)
	local gamepad = usingGamepad()
	local holder = holderOf(view.Close)
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
	end
	updateHint(view)
end

-- Fits the panel to the screen (phones and TVs get the compact layout).
local function fit(view: GearShopView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = GearShopView.compactFor(isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	GearShopView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

---------------------------------------------------------------- buying

local function setBusy(button: TextButton, text: string?)
	button:SetAttribute("Busy", text ~= nil)
	if text then
		button.Text = text
	end
end

local function buy(slot: GearShopView.Slot)
	local card = slot.Card
	local button = slot.Button
	if not card or button:GetAttribute("Busy") == true then
		return
	end
	if pending[card.Line] then
		status(card.Line, STATUS.Waiting, Theme.Info)
		Sfx.play("UIDeny")
		return
	end
	local offer = card.Buy
	if not offer.CanBuy then
		local text = if card.Done then "Already at the top level" else GearShopController.reasonText(offer.Reason)
		status(card.Line, text, if card.Done then Theme.Good else Theme.Bad)
		Sfx.play("UIDeny")
		return
	end
	pending[card.Line] = { Line = card.Line, Until = os.clock() + PENDING_TIMEOUT }
	setBusy(button, "...")
	Sfx.play("UIClick")
	Net.send("GearAction", "Buy", { Line = card.Line, Level = offer.Level })
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
	s.Scale = 1.05
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- ActionResult { Action = "Gear", Op, Ok, Reason?, Id: line, Level?, Preview? }.
local function onResult(payload: any)
	if type(payload) ~= "table" or payload.Action ~= "Gear" then
		return
	end
	if type(payload.Preview) == "table" then
		preview = payload.Preview
	end
	local lineId = if type(payload.Id) == "string" then payload.Id else nil
	local wait = if lineId then pending[lineId] else nil
	if lineId then
		pending[lineId] = nil
	end
	local view = refs
	local slot = if view and lineId then view.Slots[lineId] else nil
	local button = if slot and wait then slot.Button else nil
	if payload.Ok == true then
		if slot and counter then
			pop(slot.Frame)
			if button then
				setBusy(button, "BOUGHT!")
				GearShopView.style(button, true, Theme.Good, Theme.GoodDark)
				task.delay(FLASH_TIME, function()
					setBusy(button, nil)
					refresh()
				end)
			else
				-- an answer after the BUY was given up on: it went through after all
				status(slot.Line, STATUS.LateBought, Theme.Good)
				refresh()
			end
			Sfx.play("CoinBurst")
		elseif button then
			-- closed meanwhile: the server's toast says it
			setBusy(button, nil)
		end
		return
	end
	if button then
		setBusy(button, nil)
	end
	local text = GearShopController.reasonText(payload.Reason)
	if slot and counter then
		status(slot.Line, text, Theme.Bad)
		Sfx.play("UIDeny")
		refresh()
	else
		HudController.toast(text, "Deny")
	end
end

-- Buys with no answer yet free their button; with the shop open the card says so.
local function expirePending(force: boolean?)
	local now = os.clock()
	local view = refs
	local expired = false
	for lineId, wait in pending do
		if force or now > wait.Until then
			pending[lineId] = nil
			expired = true
			local slot = view and view.Slots[lineId]
			if slot then
				setBusy(slot.Button, nil)
				if not force and counter then
					status(lineId, STATUS.NoAnswer, Theme.Bad)
				end
			end
		end
	end
	if expired then
		refresh()
	end
end

---------------------------------------------------------------- open / close

function GearShopController.close()
	if not counter then
		return
	end
	expirePending(true)
	counter = nil
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		GearShopView.hideReceipt(view)
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("GearShop", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not counter then
		return Enum.ContextActionResult.Pass
	end
	GearShopController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function ensureView(): GearShopView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = GearShopView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		GearShopController.close()
		Sfx.play("UIClick")
	end)
	for _, slot in view.SlotList do
		slot.Button.Activated:Connect(function()
			buy(slot)
		end)
	end
	refs = view
	return view
end

-- Every TICK: close when you walk away, the counter streams out or another
-- panel opens; count the coins up; give up on unanswered buys.
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
			GearShopController.close()
			return
		end
		local p = part.CFrame:PointToObjectSpace(root.Position)
		local half = part.Size / 2
		local outside =
			Vector3.new(math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Y) - half.Y, 0), math.max(math.abs(p.Z) - half.Z, 0))
		if outside.Magnitude > CLOSE_RANGE then
			GearShopController.close()
			return
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					GearShopController.close()
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
				GearShopView.setCoins(view, coins())
			end
		end
	end)
end

function GearShopController.open(part: BasePart)
	if counter == part then
		refresh()
		return
	end
	local owner = PlayerControls.owner()
	if owner ~= nil then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return
	end
	GearShopController.close()
	-- one panel at a time (they bind B / Backspace too)
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	local view = ensureView()
	counter = part
	openedAt = os.clock()
	fit(view)
	updateGlyphs(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("GearShop", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watch(part)
	GuiService.SelectedObject = nil
	refresh()
	selectDefault(view, true)
	Sfx.play("UIClick")
	-- a quick pop-in
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

function GearShopController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Gear" or type(payload) ~= "table" then
			return
		end
		local part = payload.Counter
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			if type(payload.Preview) == "table" then
				preview = payload.Preview
			end
			GearShopController.open(part)
		end
	end)
	Net.listen("ActionResult", onResult)
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
	player.CharacterRemoving:Connect(function()
		GearShopController.close()
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
			end
		end)
	end
end

return GearShopController
