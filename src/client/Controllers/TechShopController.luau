--[[
	TechShopController: the Tech shop at the UPGRADES stall (client side).

	- Opens on OpenUI "Tech" { Counter } (the stall's "Tech Shop" prompt,
	  added by ShopService), or with TechShopController.openMachines()
	  anywhere, on the MACHINES tab with no counter (build mode's SHOP
	  button calls it through MenuPanels.controller). The server still
	  checks every BUY: machines sell at your own plot or the counter,
	  everything else only at the counter (the view greys those BUYs out
	  and its notes say so: TechShopView.Where). The cards come from the
	  State snapshot (TechShopView.cards with your coins, counted up
	  between snapshots like the HUD) and update live while it is open.
	- BUY sends ShopBuy { Shop = "Tech", Item, Count?, Level? } (Level = the
	  level the card shows being bought). The button shows "..." until the
	  server's ShopResult arrives, then "BOUGHT!" for a moment, or the reason
	  (EconomyConfig.TechShop.Reasons) on the card's status line. One BUY per
	  item waits at a time: the card's other button says so. With no answer
	  (the rate limit dropped it, or a slow link) the button is freed after
	  a while (machines wait longer, and their card says to check the Build
	  menu: a repeat would buy again; levelled items are safe, the server
	  refuses a repeat as Stale); an answer that still comes marks the card
	  "Bought!" and refreshes it. A greyed-out button (can't afford, top
	  level, locked) answers locally with the same texts and sends nothing.
	  The success toast comes from the server (Notify); while the shop is
	  open messages also show in its header (HUD toasts hide behind the
	  panel). A refused buy with the shop closed shows a HUD toast.
	- Tabs: click / tap a tab, or LB / RB on a gamepad. Gamepads get a
	  selected button on open and on every tab switch; the selection stays
	  inside the panel (SelectionGroup).
	- Closes with the X button, B (gamepad), Backspace, walking away from the
	  counter (or from your plot, for a shop opened there), the counter
	  streaming out, respawning or another panel (Pen, Sell, Train...)
	  opening. Other prompts are hidden while it is open.
	- Build mode (PlacementController) takes the screen and the controls,
	  so the shop never sits over it: openMachines() from build mode LEAVES
	  build mode first (PlacementController.exit) and opens the shop as a
	  normal panel; when the player closes it (X, B, Backspace) it enters
	  build mode again (PlacementController.enter, deferred), where the
	  new machine waits in the tray. Any other close (walking away,
	  respawning, another panel) doesn't, so build mode never comes back
	  uninvited (build mode's own B key enters it anyway: entering closes
	  every panel). PlacementController is looked up on use
	  (MenuPanels.controller), never required here: it may require this
	  module's neighbours, and a missing one only skips the hand-off.
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
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local TechShopController = {}

type Pending = { Row: string, Button: number, Until: number, Machine: boolean }
type Panel = { isOpen: () -> boolean, close: () -> () }

local CLOSE_ACTION = "TerraForgeTechShopClose"
local TAB_ACTION = "TerraForgeTechShopTab"
-- above the default player controls, so B / Backspace close the shop first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local TICK = 0.25
-- less than the server's ShopService.Range: the shop closes before the server
-- would refuse a BUY as "TooFar", with room for lag (TechShopView.CloseRange)
local CLOSE_RANGE = TechShopView.CloseRange
-- a shop opened at your plot closes past this (horizontal studs from its
-- centre): under the server's GameConfig.BuildRange, with room for lag
local BASE_CLOSE_RANGE = TechShopView.BaseCloseRange
-- seconds a BUY waits for its ShopResult before its button is freed: a
-- levelled item can be tried again safely (a repeat is refused as Stale), a
-- machine BUY that went through slowly would buy again, so it waits longer
local PENDING_TIMEOUT = 3
local PENDING_TIMEOUT_MACHINE = 6
local FLASH_TIME = 0.9 -- "BOUGHT!" on the button
local STATUS_TIME = 3.5 -- a reason on the card's status line
local STATUS = TechShopView.StatusText
local RECEIPT_TIME = 5 -- a message in the header
local RECEIPT_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
	Discovery = Theme.Accent,
}
-- panels that own the middle of the screen: one at a time (MenuPanels.Names,
-- the one list of every panel controller)

local player = Players.LocalPlayer
local refs: TechShopView.Refs? = nil
local shown = false
local counter: BasePart? = nil -- the counter it was opened at (nil: openMachines)
local where: TechShopView.Where = "Counter"
local tickConnection: RBXScriptConnection? = nil
local pending: { [string]: Pending } = {}
local statusTokens: { [string]: number } = {}
local receiptToken = 0
local openedAt = 0
local others: { Panel }? = nil

function TechShopController.isOpen(): boolean
	return shown
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

-- Is your character within `range` studs (horizontally) of your own plot's
-- centre? The same test as the server's PlotService.isNear.
local function nearOwnPlot(range: number): boolean
	local id = player:GetAttribute("PlotId")
	local plot = if type(id) == "number" then WorldLayout.Plots[id] else nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not plot or not root then
		return false
	end
	local offset = root.Position - plot.Center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= range
end

-- Build mode is open (PlacementController, looked up on use).
local function building(): boolean
	local build = MenuPanels.controller("PlacementController")
	local isActive = if type(build) == "table" then build.isActive else nil
	if type(isActive) ~= "function" then
		return false
	end
	local ok, active = pcall(isActive)
	return ok and active == true
end

-- The other panel controllers that exist (required on first use: they may load after this one).
local function otherPanels(): { Panel }
	local cached = others
	if cached then
		return cached
	end
	local list: { Panel } = {}
	for _, name in MenuPanels.Names do
		if name == "TechShopController" then
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

-- A message in the header for a few seconds.
local function receipt(text: string, color: Color3)
	local view = refs
	if not view or not shown then
		return
	end
	TechShopView.showReceipt(view, text, color)
	receiptToken += 1
	local token = receiptToken
	task.delay(RECEIPT_TIME, function()
		local current = refs
		if receiptToken == token and current then
			TechShopView.hideReceipt(current)
		end
	end)
end

-- A message on a card's status line for a few seconds (instead of its detail line).
local function status(rowId: string, text: string, color: Color3)
	local view = refs
	if not view then
		return
	end
	TechShopView.setStatus(view, rowId, text, color)
	local token = (statusTokens[rowId] or 0) + 1
	statusTokens[rowId] = token
	task.delay(STATUS_TIME, function()
		local current = refs
		if statusTokens[rowId] == token and current then
			TechShopView.setStatus(current, rowId, nil, nil)
		end
	end)
end

-- The text for a reason code (TechShop.Reasons, or "Locked" with the card's note).
function TechShopController.reasonText(reason: any, note: string?): string
	if reason == "Locked" then
		return note or "Not available yet"
	end
	local text = if type(reason) == "string" then EconomyConfig.TechShop.Reasons[reason] else nil
	return text or "You can't buy that right now"
end

---------------------------------------------------------------- refreshing

local function refresh()
	local view = refs
	if not view or not shown then
		return
	end
	local cash = coins()
	TechShopView.setCoins(view, cash)
	TechShopView.setCards(view, TechShopView.cards(StateController.get(), cash, where))
end

local function selectDefault(view: TechShopView.Refs, force: boolean)
	if not usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if not force and selected and selected:IsDescendantOf(view.Gui) then
		local holder = selected.Parent
		if selected.Visible and (not holder or not holder:IsA("GuiObject") or holder.Visible) then
			return
		end
	end
	GuiService.SelectedObject = TechShopView.firstButton(view, view.Tab)
end

-- A gamepad button's name on this platform ("A" / "Cross"), for when it has no glyph image.
local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

-- The footer hint: the platform's own glyphs on a gamepad (Xbox or PlayStation).
local function updateHint(view: TechShopView.Refs)
	if usingGamepad() then
		local keys = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB }
		local images: { string } = {}
		local complete = true
		for i, key in keys do
			images[i] = UserInputService:GetImageForKeyCode(key)
			complete = complete and images[i] ~= ""
		end
		if complete then
			TechShopView.setHint(view, "", images)
		else
			-- no glyph images: the platform's button names
			local names: { string } = {}
			for i, key in keys do
				names[i] = padName(key)
			end
			local text =
				`{names[1]} / {names[2]}: switch tab{TechShopView.Separator}{names[3]}: buy{TechShopView.Separator}{names[4]}: close`
			TechShopView.setHint(view, text, nil)
		end
	elseif isTouch() then
		TechShopView.setHint(view, "Tap a tab, then BUY", nil)
	else
		TechShopView.setHint(view, `Click a tab, then BUY{TechShopView.Separator}Backspace: close`, nil)
	end
end

-- The platform's own glyphs: B on the close button, LB / RB at the tab bar's ends.
local function updateGlyphs(view: TechShopView.Refs)
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
	for i, image in view.TabGlyphs do
		image.Visible = gamepad
		if gamepad then
			image.Image = UserInputService:GetImageForKeyCode(if i == 1 then Enum.KeyCode.ButtonL1 else Enum.KeyCode.ButtonR1)
		end
	end
	if gamepad then
		closeGlyph.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
	end
	updateHint(view)
end

-- Fits the panel to the screen (phones and TVs get the compact layout's bigger texts).
local function fit(view: TechShopView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = TechShopView.compactFor(isTouch(), GuiService:IsTenFootInterface(), scale, size.Y)
	TechShopView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

---------------------------------------------------------------- buying

local function setBusy(button: TextButton, text: string?)
	button:SetAttribute("Busy", text ~= nil)
	if text then
		button.Text = text
	end
end

local function buy(row: TechShopView.Row, index: number)
	local card = row.Card
	local button = row.Buttons[index]
	local offer = card and card.Buys[index]
	if not card or not offer or not button or button:GetAttribute("Busy") == true then
		return
	end
	if pending[card.Item] then
		-- the other button of a card whose BUY waits for its answer
		status(row.Id, STATUS.Waiting, Theme.Info)
		Sfx.play("UIDeny")
		return
	end
	if not offer.CanBuy then
		local text = if card.Done and card.Tab == "Automation"
			then "You have this already"
			else TechShopController.reasonText(offer.Reason, card.Note)
		status(row.Id, text, if card.Done then Theme.Good else Theme.Bad)
		Sfx.play("UIDeny")
		return
	end
	local machine = card.Tab == "Machines"
	pending[card.Item] = {
		Row = row.Id,
		Button = index,
		Until = os.clock() + (if machine then PENDING_TIMEOUT_MACHINE else PENDING_TIMEOUT),
		Machine = machine,
	}
	setBusy(button, "...")
	Sfx.play("UIClick")
	Net.send("ShopBuy", { Shop = EconomyConfig.TechShop.Shop, Item = card.Item, Count = offer.Count, Level = offer.Level })
end

-- The row a ShopResult belongs to: the one that asked, else the first row selling that item.
local function rowFor(item: string, wait: Pending?): TechShopView.Row?
	local view = refs
	if not view then
		return nil
	end
	if wait then
		return view.Rows[wait.Row]
	end
	for _, row in view.RowList do
		if row.Item == item then
			return row
		end
	end
	return nil
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

local function onResult(payload: any)
	if type(payload) ~= "table" or type(payload.Item) ~= "string" then
		return
	end
	local item = payload.Item :: string
	local wait = pending[item]
	pending[item] = nil
	local row = rowFor(item, wait)
	local button = if row and wait then row.Buttons[wait.Button] else nil
	if payload.Ok == true then
		if row and shown then
			pop(row.Frame)
			if button then
				setBusy(button, "BOUGHT!")
				TechShopView.style(button, true, Theme.Good, Theme.GoodDark)
				task.delay(FLASH_TIME, function()
					setBusy(button, nil)
					refresh()
				end)
			elseif not wait then
				-- an answer after the BUY was given up on: it went through after all
				status(row.Id, STATUS.LateBought, Theme.Good)
				refresh()
			end
			Sfx.play("CoinBurst")
		elseif button then
			-- closed meanwhile: the server's toast says it; the card is fresh on the next open
			setBusy(button, nil)
		end
		return
	end
	if button then
		setBusy(button, nil)
	end
	-- machines sell at your base too: "TooFar" says both places
	local entry = EconomyConfig.techItem(item)
	local machine = entry ~= nil and entry.Kind == "Machine"
	local text = if payload.Reason == "TooFar" and machine then STATUS.TooFarMachine else TechShopController.reasonText(payload.Reason, nil)
	if row and shown then
		status(row.Id, text, Theme.Bad)
		Sfx.play("UIDeny")
		refresh()
	else
		HudController.toast(text, "Deny")
	end
end

-- Buys with no answer yet (the rate limit dropped them, or the link is slow)
-- free their button; with the shop open the card says so (a machine card:
-- check the Build menu, the buy may still go through; onResult marks it).
local function expirePending(force: boolean?)
	local now = os.clock()
	local view = refs
	local expired = false
	for item, wait in pending do
		if force or now > wait.Until then
			pending[item] = nil
			expired = true
			local row = view and view.Rows[wait.Row]
			local button = row and row.Buttons[wait.Button]
			if button then
				setBusy(button, nil)
			end
			if row and not force and shown then
				status(row.Id, if wait.Machine then STATUS.NoAnswerMachine else STATUS.NoAnswer, Theme.Bad)
			end
		end
	end
	if expired then
		refresh()
	end
end

---------------------------------------------------------------- open / close

local function switchTab(name: string, moveSelection: boolean)
	local view = refs
	if not view or not TechShopView.toTab(name) or view.Tab == name then
		return
	end
	TechShopView.setTab(view, name)
	refresh()
	Sfx.play("UIClick")
	if moveSelection then
		selectDefault(view, true)
	end
end

function TechShopController.close()
	if not shown then
		return
	end
	-- unanswered buys free their buttons (a late answer still shows as a toast)
	expirePending(true)
	shown = false
	counter = nil
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
		TechShopView.hideReceipt(view)
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("TechShop", false)
end

-- The player closed it (X, B, Backspace): a shop opened from build mode
-- goes back to build mode (deferred: never inside this input's handler).
local function closeByPlayer()
	local back = where == "Build"
	TechShopController.close()
	Sfx.play("UIClick")
	if back and nearOwnPlot(GameConfig.BuildRange) then
		task.defer(function()
			if not shown and not building() then
				MenuPanels.call("PlacementController", "enter")
			end
		end)
	end
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not shown then
		return Enum.ContextActionResult.Pass
	end
	closeByPlayer()
	return Enum.ContextActionResult.Sink
end

local function onTab(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local view = refs
	if state ~= Enum.UserInputState.Begin or not shown or not view then
		return Enum.ContextActionResult.Pass
	end
	local dir = if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
	switchTab(TechShopView.nextTab(view.Tab, dir), true)
	return Enum.ContextActionResult.Sink
end

local function ensureView(): TechShopView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = TechShopView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(closeByPlayer)
	for _, tab in TechShopView.Tabs do
		view.Tabs[tab].Activated:Connect(function()
			switchTab(tab, false)
		end)
	end
	for _, row in view.RowList do
		for index, button in row.Buttons do
			button.Activated:Connect(function()
				buy(row, index)
			end)
		end
	end
	refs = view
	return view
end

-- Every TICK: close when you walk away (from the counter, or from your
-- plot for a shop opened there), the counter streams out or another panel
-- opens; count the coins up; give up on unanswered buys.
local function watch(part: BasePart?, nearBase: boolean)
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
		if not root or (part and not part:IsDescendantOf(Workspace)) then
			TechShopController.close()
			return
		end
		if part then
			local p = part.CFrame:PointToObjectSpace(root.Position)
			local half = part.Size / 2
			local outside =
				Vector3.new(math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Y) - half.Y, 0), math.max(math.abs(p.Z) - half.Z, 0))
			if outside.Magnitude > CLOSE_RANGE then
				TechShopController.close()
				return
			end
		elseif nearBase and not nearOwnPlot(BASE_CLOSE_RANGE) then
			TechShopController.close()
			return
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					TechShopController.close()
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
				TechShopView.setCoins(view, coins())
			end
		end
	end)
end

-- Opens the window at `part` (a counter) or with no counter (`place`
-- "Base" / "Build"), on `tab` when given.
local function show(part: BasePart?, place: TechShopView.Where, tab: TechShopView.Tab?)
	TechShopController.close()
	-- one panel at a time (they bind B / Backspace too)
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	local view = ensureView()
	shown = true
	counter = part
	where = place
	openedAt = os.clock()
	TechShopView.setWhere(view, place)
	if tab then
		TechShopView.setTab(view, tab)
	end
	fit(view)
	updateGlyphs(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("TechShop", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(TAB_ACTION, onTab, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	-- a counterless shop opened at your plot closes when you walk away from it
	watch(part, part == nil and nearOwnPlot(BASE_CLOSE_RANGE))
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

-- Opens the shop at a counter (its "Tech Shop" prompt: OpenUI "Tech").
function TechShopController.open(part: BasePart)
	if shown and counter == part then
		refresh()
		return
	end
	local owner = PlayerControls.owner()
	if owner ~= nil then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return
	end
	show(part, "Counter", nil)
end

--[[
	Opens the shop on its MACHINES tab with no counter (build mode's SHOP
	button; it works anywhere, the server decides every BUY). From build
	mode (or `fromBuild`: the caller left build mode itself) it leaves
	build mode first and goes back to it when the player closes the shop
	(see the header). Already open: shows the MACHINES tab.
]]
function TechShopController.openMachines(fromBuild: boolean?)
	if shown then
		switchTab("Machines", true)
		return
	end
	local wasBuilding = building()
	if wasBuilding then
		MenuPanels.call("PlacementController", "exit")
	end
	if PlayerControls.owner() ~= nil then
		HudController.toast("Finish what you are doing first.", "Info")
		return
	end
	show(nil, if wasBuilding or fromBuild == true then "Build" else "Base", "Machines")
end

---------------------------------------------------------------- lifecycle

function TechShopController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Tech" or type(payload) ~= "table" then
			return
		end
		local part = payload.Counter
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			TechShopController.open(part)
		end
	end)
	Net.listen("ShopResult", onResult)
	Net.listen("Notify", function(message)
		if shown and type(message) == "table" and type(message.Text) == "string" then
			local color = if type(message.Kind) == "string" then RECEIPT_COLORS[message.Kind] or Theme.Info else Theme.Info
			local info = if type(message.Rarity) == "string" then Rarity.ById[message.Rarity] else nil
			receipt(message.Text, if info then info.Color else color)
		end
	end)
	StateController.onChanged(function()
		if shown then
			refresh()
		end
	end)
	player.CharacterRemoving:Connect(function()
		TechShopController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and shown then
			updateGlyphs(view)
			selectDefault(view, false)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and shown then
				fit(view)
			end
		end)
	end
end

return TechShopController
