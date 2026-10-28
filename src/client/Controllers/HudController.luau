--[[
	HudController: coins counter with the podium income under it, zone
	banner, toast notifications, the backpack button and UI scaling for
	small screens.

	- Coins count up smoothly: between two updates the counter keeps
	  rising at the Income (coins per second, at most one tick ahead), so
	  podium money ticks up instead of jumping once a second. The balance and
	  the income come from the player attributes Coins / IncomePerSec
	  (StateService writes them at most every 0.25 s, also for the quiet
	  podium payouts); the State snapshot's Coins / Income are the fallback
	  while the attributes aren't there.
	  Bigger jumps (a sale) pop the panel, roll the number up and send cash
	  flying into the pile (UI/Motion.countUp / flyTo; with UI motion off,
	  Config/AnimConfig, the number glides up instead). holdCoins(seconds) keeps the
	  counter still while another screen still has to reveal a reward (the
	  daily wheel's disc turning); releaseCoins shows it.
	- Earned { Amount, Source } shows a floating "+$X" under the coins;
	  payouts closer together than EconomyConfig.Sell.ComboWindow add up
	  into one popup. Offline earnings get the "While you were away" popup
	  instead (OpenUI "Offline" { Amount, Seconds, Hours }): COLLECT, B or
	  Backspace closes it; gamepads start on COLLECT.
	- The backpack button (HudView.setBackpack; the light HUD: right of its
	  own BLASTER slot, the pair centred at the bottom; the dark HUD: right of
	  the blaster's slot in Roblox's hotbar) says "n / cap" and turns red with
	  a FULL tag when the backpack is full: Util/BackpackState (the
	  CarryCount / CarryCapacity attributes and State.Backpacks), refreshed on
	  both. BackpackController opens the inventory from it,
	  BlasterSlotController equips the Blaster from the slot.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Theme = require(Shared.Config.UITheme)
local Rarity = require(Shared.Config.Rarity)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local BackpackState = require(script.Parent.Parent.Util.BackpackState)
local Loading = require(script.Parent.Parent.Util.Loading)
local Net = require(Shared.Net)
local HudView = require(script.Parent.Parent.UI.HudView)
local HudBubble = require(script.Parent.Parent.UI.HudBubble)
local TrainView = require(script.Parent.Parent.UI.TrainView)
local BoostView = require(script.Parent.Parent.UI.BoostView)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local StateController = require(script.Parent.StateController)

local HudController = {}

local player = Players.LocalPlayer
local refs: HudView.Refs
local offline: HudView.OfflineRefs? = nil
local MAX_TOASTS = 3
local OFFLINE_CLOSE = "TerraForgeOfflineClose"
-- above the default controls, so B / Backspace close the popup first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 20
local FLOAT_TIME = 1.4
-- player attributes written by StateService (CoinsAttribute / IncomeAttribute)
local COINS_ATTRIBUTE = "Coins"
local INCOME_ATTRIBUTE = "IncomePerSec"

-- coin counter: the server's coins at the last snapshot, the income then, and when it came
local serverCoins = 0
local income = 0
local snapshotAt = 0
local shownCoins = 0
local hasState = false

-- the floating "+$X" that is still collecting a combo
local comboLabel: TextLabel? = nil
local comboAmount = 0
local comboAt = 0

local TOAST_COLORS = {
	Info = Theme.Info,
	Deny = Theme.Bad,
	Discovery = Theme.Accent,
	Reward = Theme.Good,
}

function HudController.refs(): HudView.Refs
	return refs
end

function HudController.toast(text: string, kind: string?, color: Color3?)
	local frames = {}
	for _, child in refs.Toasts:GetChildren() do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	if #frames >= MAX_TOASTS then
		table.sort(frames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		frames[1]:Destroy()
	end
	local frame = HudView.toast(refs.Toasts, text, color or TOAST_COLORS[kind or "Info"] or Theme.Info)
	frame.LayoutOrder = math.floor(os.clock() * 100) % 1e6
	-- (UI/Motion's bounce in, none with Reduce motion; UI motion off: the pop main has)
	local scale = if Motion.full() then Motion.popIn(frame) else Motion.classicPop(frame, "UIScale", 0.6, 0.25)
	if kind == "Deny" then
		Sfx.play("UIDeny")
	elseif kind == "Discovery" then
		Sfx.play("Discovery")
	end
	task.delay(3.2, function()
		if frame.Parent then
			if not Motion.reduced() then -- (Reduce motion: it just goes)
				TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 }):Play()
				task.wait(0.22)
			end
			frame:Destroy()
		end
	end)
end

-- UI scale for the current screen (phones get a floor so text stays readable).
function HudController.uiScale(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local size = camera.ViewportSize
	return math.clamp(math.min(size.Y / Theme.BaseHeight, size.X / 1100), 0.62, 1.25)
end

-- The top bar row's free part in screen pixels (min x, max x), or nil when
-- Roblox doesn't say (GuiService.TopbarInset).
local function topBarFree(): Vector2?
	local ok, rect = pcall(function()
		return (GuiService :: any).TopbarInset
	end)
	if ok and typeof(rect) == "Rect" and rect.Width > 0 then
		return Vector2.new(rect.Min.X, rect.Max.X)
	end
	return nil
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local scale = HudController.uiScale()
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		local uiScale = gui:IsA("ScreenGui") and gui:FindFirstChild("Scale")
		if uiScale and uiScale:IsA("UIScale") and gui:GetAttribute("TerraForge") then
			uiScale.Scale = scale
		end
	end
	-- the Pop teleport bar sits in Roblox's top bar row: lifted by the real inset,
	-- centred but kept inside the row's free space (GuiService.TopbarInset: clear of
	-- Roblox's own buttons); if it doesn't fit there, it drops under the row
	local topBar = refs and refs.TopBar
	if topBar and topBar:GetAttribute("Pop") then
		local inset = GuiService:GetGuiInset()
		local x, inRow = HudBubble.topBarX(topBarFree(), refs.Gui.AbsolutePosition.X, refs.Gui.AbsoluteSize.X, topBar.Size.X.Offset, scale)
		topBar.Position = UDim2.new(0.5, x, 0, if inRow then HudBubble.topBarY(inset.Y, scale) else HudBubble.TopBarUnderRow)
	end
	-- the bottom group: the light HUD's BLASTER slot + backpack button stay centred (design
	-- units); the dark HUD's button stays right of Roblox's hotbar slot (real pixels)
	if refs then
		HudView.placeBackpack(refs, scale, GuiService:IsTenFootInterface())
	end
	-- phones: the boost chips stop short of the Shop pill on their row (BoostView.setChips)
	if refs then
		local width = refs.Gui.AbsoluteSize.X
		if width <= 0 then
			width = camera.ViewportSize.X
		end
		BoostView.HudChipsRight = HudBubble.chipsRight(refs.Gui, width / scale)
	end
end

-- The backpack button: "n / cap", red with the FULL tag when full.
local function refreshBackpack()
	HudView.setBackpack(refs, BackpackState.count(), BackpackState.capacity())
end

local currentZone = ""
local function zoneLoop()
	while true do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local zone = WorldLayout.zoneAt(root.Position)
			local name = if zone then zone.Name else "Terra"
			if name ~= currentZone then
				currentZone = name
				refs.Zone.Text = name
				refs.Zone.TextTransparency = 0
				local stroke = refs.Zone:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = 0
				end
				task.delay(2.5, function()
					if currentZone == name then
						TweenService:Create(refs.Zone, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
						if stroke then
							TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
						end
					end
				end)
			end
		end
		task.wait(0.5)
	end
end

---------------------------------------------------------------- coins and income

-- What the counter should show right now: the snapshot's coins plus the
-- income earned since (podium income alone sends a snapshot only every
-- StatePushSeconds, so count up for that long and a little more).
function HudController.predictedCoins(now: number): number
	local ahead = math.clamp(now - snapshotAt, 0, EconomyConfig.StatePushSeconds + EconomyConfig.IncomeTick)
	return serverCoins + income * ahead
end

-- a reward another screen reveals later (the daily wheel while it spins):
-- the counter holds its coins until then
local holdUntil = 0
local heldCoins: number? = nil

local function applyCoins(coins: number)
	-- only a change of coins restarts the count-up (other pushes in the
	-- middle of a second must not pull the counter back)
	if coins ~= serverCoins or not hasState then
		serverCoins = coins
		snapshotAt = os.clock()
	end
end

-- Keeps the coin counter where it is for up to `seconds` (a reward another
-- screen reveals later: the daily wheel holds it while its disc turns);
-- releaseCoins, or the time running out, shows the newest balance.
function HudController.holdCoins(seconds: number)
	if type(seconds) ~= "number" or seconds ~= seconds then
		return
	end
	holdUntil = math.max(holdUntil, os.clock() + math.clamp(seconds, 0, 15))
end

function HudController.releaseCoins()
	holdUntil = 0
	local coins = heldCoins
	heldCoins = nil
	if coins then
		applyCoins(coins)
	end
end

-- A finite number or nil.
local function number(value: any): number?
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

local function showCoins(coins: number, newIncome: number)
	if newIncome < 0 then
		newIncome = 0
	end
	if hasState and os.clock() < holdUntil then
		heldCoins = coins
	else
		heldCoins = nil
		applyCoins(coins)
	end
	income = newIncome
	if not hasState then
		hasState = true
		shownCoins = coins
	end
	refs.Income.Text = Format.perSecond(newIncome)
	if refs.Gui:GetAttribute("Bubble") then
		-- the light HUD: white on the green income chip (green text would vanish on it)
		refs.Income.TextTransparency = if newIncome > 0 then 0 else 0.35
	else
		refs.Income.TextColor3 = if newIncome > 0 then Theme.Good else Theme.TextDim
	end
end

-- The balance and income now: the attributes first, the last snapshot's
-- fields while an attribute is missing.
local lastState: { [string]: any }? = nil
local function refreshCoins()
	local state = lastState
	local coins = number(player:GetAttribute(COINS_ATTRIBUTE)) or (if state then number(state.Coins) else nil)
	local newIncome = number(player:GetAttribute(INCOME_ATTRIBUTE)) or (if state then number(state.Income) else nil)
	if coins == nil then
		return -- nothing known yet
	end
	showCoins(coins, newIncome or 0)
end

local function onState(state: { [string]: any })
	lastState = state
	refreshCoins()
end

---------------------------------------------------------------- Earned popups

local function floatAway(label: TextLabel)
	local start = label.Position
	TweenService:Create(label, TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = start + UDim2.fromOffset(0, -34),
		TextTransparency = 1,
	}):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(FLOAT_TIME), { Transparency = 1 }):Play()
	end
	task.delay(FLOAT_TIME + 0.05, function()
		if comboLabel == label then
			comboLabel = nil
		end
		label:Destroy()
	end)
end

-- A floating "+$X" under the coins; quick payouts add up in one label.
function HudController.earned(amount: number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	local now = os.clock()
	local label = comboLabel
	if label and label.Parent and now - comboAt <= EconomyConfig.Sell.ComboWindow then
		comboAmount += amount
		comboAt = now
		label.Text = "+" .. Format.money(comboAmount)
		local pop = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		pop.Scale = if Motion.reduced() then 1 else 1.25
		pop.Parent = label
		TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		return
	end
	comboAmount = amount
	comboAt = now
	local fresh = HudView.floater(refs.Floaters, "+" .. Format.money(amount))
	comboLabel = fresh
	-- hold still while a combo may still grow, then float away
	task.spawn(function()
		while fresh.Parent and os.clock() - comboAt < EconomyConfig.Sell.ComboWindow do
			task.wait(0.1)
		end
		if comboLabel == fresh then
			comboLabel = nil
		end
		if fresh.Parent then
			floatAway(fresh)
		end
	end)
end

---------------------------------------------------------------- offline popup

local function closeOffline()
	local view = offline
	if not view or not view.Gui.Enabled then
		return
	end
	view.Gui.Enabled = false
	ContextActionService:UnbindAction(OFFLINE_CLOSE)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) then
		GuiService.SelectedObject = nil
	end
end

-- "Away 7h 12m. Podiums pay 50% while you're offline, for up to 5 hours."
function HudController.offlineDetail(seconds: number, hours: number): string
	local o = EconomyConfig.Offline
	local rate = math.floor(o.Rate * 100 + 0.5)
	local text = `Away {Format.seconds(seconds)}. Podiums pay {rate}% while you're offline, for up to {hours} hours.`
	if seconds > hours * 3600 and hours < o.ExtendedHours then
		text ..= ` The Offline Extension makes it {o.ExtendedHours} hours.`
	end
	return text
end

function HudController.showOffline(amount: number, seconds: number, hours: number)
	-- never under the loading screen: wait for it (Util/Loading, at most MaxWait)
	if not Loading.isDone() then
		task.spawn(function()
			Loading.wait()
			HudController.showOffline(amount, seconds, hours)
		end)
		return
	end
	local view = offline
	if not view then
		local built = HudView.buildOffline()
		built.Gui:SetAttribute("TerraForge", true)
		built.Gui.Parent = player:WaitForChild("PlayerGui")
		built.Collect.Activated:Connect(function()
			Sfx.play("UIClick")
			closeOffline()
		end)
		offline = built
		view = built
		updateScale()
	end
	local shown = view :: HudView.OfflineRefs
	shown.Amount.Text = "+" .. Format.money(amount)
	shown.Detail.Text = HudController.offlineDetail(seconds, hours)
	shown.Gui.Enabled = true
	if Motion.enabled() then
		Motion.pop(shown.Panel, shown.Dim) -- (UI/Motion: none with Reduce motion)
	else
		Motion.classicPop(shown.Panel, nil, 0.6, 0.3) -- (UI motion off: the pop main has)
	end
	Sfx.play("CoinBurst")
	ContextActionService:BindActionAtPriority(OFFLINE_CLOSE, function(_, state)
		if state == Enum.UserInputState.Begin then
			closeOffline()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = shown.Collect
	end
end

---------------------------------------------------------------- lifecycle

function HudController.init()
	refs = HudView.build()
	-- the light HUD: the TRAIN chip (and the boost chips beside it) under its menu tiles (the
	-- round look: as wide as them, stacked on a mouse or a TV)
	if type(refs.Gui:GetAttribute("ChipTop")) == "number" then
		TrainView.useHud(refs.Gui)
	end
	refs.Gui:SetAttribute("TerraForge", true)
	refs.Gui.Parent = player:WaitForChild("PlayerGui")
	if refs.Gui:GetAttribute("Bubble") then
		-- the light UI: a gold outline around the gamepad's selection
		local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
		playerGui.SelectionImageObject = HudBubble.selectionImage()
	end

	Net.listen("Notify", function(message)
		if type(message) ~= "table" or type(message.Text) ~= "string" then
			return
		end
		local color = nil
		if type(message.Rarity) == "string" and Rarity.ById[message.Rarity] then
			color = Rarity.ById[message.Rarity].Color
		end
		HudController.toast(message.Text, message.Kind, color)
	end)

	Net.listen("Earned", function(payload)
		-- sales get their own popup at Tobin's stall (SellController)
		if type(payload) ~= "table" or payload.Source == "Offline" or payload.Source == "Sell" then
			return
		end
		HudController.earned(tonumber(payload.Amount) or 0)
	end)

	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Offline" or type(payload) ~= "table" then
			return
		end
		local amount = tonumber(payload.Amount) or 0
		local seconds = tonumber(payload.Seconds) or 0
		local hours = tonumber(payload.Hours) or EconomyConfig.Offline.BaseHours
		if amount > 0 and amount == amount and amount < math.huge then
			HudController.showOffline(amount, seconds, hours)
		end
	end)

	StateController.onChanged(onState)
	player:GetAttributeChangedSignal(COINS_ATTRIBUTE):Connect(refreshCoins)
	player:GetAttributeChangedSignal(INCOME_ATTRIBUTE):Connect(refreshCoins)
	if player:GetAttribute(COINS_ATTRIBUTE) ~= nil then
		refreshCoins()
	end
end

function HudController.start()
	local camera = Workspace.CurrentCamera
	updateScale()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		pcall(function() -- (Roblox's top row changes: voice chat, self view...)
			GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateScale)
		end)
	end
	player:WaitForChild("PlayerGui").ChildAdded:Connect(function()
		task.defer(updateScale)
	end)
	-- (the HUD's size lands a frame after the viewport's: the chips' limit follows it)
	refs.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)

	-- the round look's offers at the right edge: hidden while the last input is touch (a touch
	-- screen with a mouse or a keyboard got the PC layout: the touch tutorial's SKIP and Roblox's
	-- jump button take that edge as soon as it is touched)
	local offers = refs.Gui:FindFirstChild("Offers")
	if offers and offers:IsA("GuiObject") then
		local function showOffers()
			offers.Visible = UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
		end
		showOffers()
		UserInputService.LastInputTypeChanged:Connect(showOffers)
	end

	-- the backpack button: the CarryCount / CarryCapacity attributes and every State push
	BackpackState.onChanged(refreshBackpack)
	refreshBackpack()

	task.spawn(zoneLoop)

	-- coin counter: follows the predicted coins; a big jump pops the panel, rolls
	-- the number up and sends cash flying into the pile (UI/Motion: at most one
	-- burst a second; with Reduce motion the number just changes)
	local coinScale = Instance.new("UIScale")
	coinScale.Parent = refs.CoinsPanel
	local cashPile = refs.CoinsPanel:FindFirstChild("Cash") :: GuiObject?
	local shownText = ""
	while true do
		if heldCoins and os.clock() >= holdUntil then
			HudController.releaseCoins()
		end
		local target = HudController.predictedCoins(os.clock())
		local diff = target - shownCoins
		if diff ~= 0 then
			-- a jump bigger than a few seconds of income is a sale or a reward
			local big = diff > math.max(1, income * 3)
			if big and not Motion.full() then
				-- (UI motion off, Config/AnimConfig: the glide main has, the panel popping as it goes)
				coinScale.Scale = 1.12
				TweenService:Create(coinScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
				shownCoins += diff * 0.35
				if math.abs(target - shownCoins) < 0.01 then
					shownCoins = target
				end
			else
				if big then
					if not Motion.isCounting(refs.Coins) and not Motion.reduced() then
						coinScale.Scale = 1.12
						TweenService:Create(coinScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
						Motion.flyTo(nil, cashPile or refs.CoinsPanel, "cash")
					end
					Motion.countUp(refs.Coins, math.max(0, shownCoins), target, Format.money)
					shownText = ""
				end
				-- (spending: no counting down)
				shownCoins = target
			end
		end
		if not Motion.isCounting(refs.Coins) then
			local text = Format.money(math.max(0, shownCoins))
			if text ~= shownText then
				shownText = text
				refs.Coins.Text = text
			end
		end
		task.wait(0.05)
	end
end

return HudController
