--[[
	HudController: coins counter with the podium income under it, zone
	banner, toast notifications, carry slots and UI scaling for small screens.

	- Coins count up smoothly: between two updates the counter keeps
	  rising at the Income (coins per second, at most one tick ahead), so
	  podium money ticks up instead of jumping once a second. The balance and
	  the income come from the player attributes Coins / IncomePerSec
	  (StateService writes them at most every 0.25 s, also for the quiet
	  podium payouts); the State snapshot's Coins / Income are the fallback
	  while the attributes aren't there.
	  Bigger jumps (a sale) pop the panel. holdCoins(seconds) keeps the
	  counter still while another screen still has to reveal a reward (the
	  daily wheel's disc turning); releaseCoins shows it.
	- Earned { Amount, Source } shows a floating "+$X" under the coins;
	  payouts closer together than EconomyConfig.Sell.ComboWindow add up
	  into one popup. Offline earnings get the "While you were away" popup
	  instead (OpenUI "Offline" { Amount, Seconds, Hours }): COLLECT, B or
	  Backspace closes it; gamepads start on COLLECT.
	- Dirty ore in your hands shows as a grey "?" slot (no rarity hint).
]]

local CollectionService = game:GetService("CollectionService")
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
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local WorldLayout = require(Shared.Config.WorldLayout)
local Format = require(Shared.Util.Format)
local Loading = require(script.Parent.Parent.Util.Loading)
local Net = require(Shared.Net)
local HudView = require(script.Parent.Parent.UI.HudView)
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
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = frame
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if kind == "Deny" then
		Sfx.play("UIDeny")
	elseif kind == "Discovery" then
		Sfx.play("Discovery")
	end
	task.delay(3.2, function()
		if frame.Parent then
			TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 }):Play()
			task.wait(0.22)
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
end

local function rarityColorOfItem(model: Instance): Color3
	local ore = OreData.ById[model:GetAttribute("OreId") :: string]
	return if ore then Rarity.get(ore.Rarity).Color else Theme.PanelLight
end

local function refreshCarry()
	local capacity = (player:GetAttribute("CarryCapacity") :: number?) or 1
	local carried = {}
	for _, item in CollectionService:GetTagged("Item") do
		if item:GetAttribute("CarriedBy") == player.UserId then
			table.insert(carried, item)
		end
	end
	for _, child in refs.CarrySlots:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	-- at most HudView.MaxCarrySlots squares (the last one says "+N"): a big
	-- backpack never covers the phone's thumbstick and jump button
	local squares, shown, more, width = HudView.carryLayout(capacity, #carried)
	for i = 1, squares do
		if more > 0 and i == squares then
			HudView.moreSlot(refs.CarrySlots, more, i)
		else
			local item = if i <= shown then carried[i] else nil
			local dirty = item ~= nil and item:GetAttribute("Kind") == "Raw"
			HudView.slot(refs.CarrySlots, if item and not dirty then rarityColorOfItem(item) else nil, i, dirty)
		end
	end
	refs.CarryLabel.Text = `CARRYING {#carried}/{capacity}`
	refs.CarryPanel.Size = UDim2.fromOffset(width, HudView.CarryPanelHeight)
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
	refs.Income.TextColor3 = if newIncome > 0 then Theme.Good else Theme.TextDim
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
		pop.Scale = 1.25
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
	local scale = shown.Panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = shown.Panel
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
	refs.Gui:SetAttribute("TerraForge", true)
	refs.Gui.Parent = player:WaitForChild("PlayerGui")

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
	end
	player:WaitForChild("PlayerGui").ChildAdded:Connect(function()
		task.defer(updateScale)
	end)

	-- the item's CarriedBy attribute may arrive a moment after CarryCount, so refresh twice
	local function carryChanged()
		refreshCarry()
		task.delay(0.25, refreshCarry)
	end
	player:GetAttributeChangedSignal("CarryCount"):Connect(carryChanged)
	player:GetAttributeChangedSignal("CarryCapacity"):Connect(carryChanged)
	refreshCarry()

	task.spawn(zoneLoop)

	-- coin counter: glides toward the predicted coins; big jumps pop the panel
	local coinScale = Instance.new("UIScale")
	coinScale.Parent = refs.CoinsPanel
	local shownText = ""
	while true do
		if heldCoins and os.clock() >= holdUntil then
			HudController.releaseCoins()
		end
		local target = HudController.predictedCoins(os.clock())
		local diff = target - shownCoins
		if diff ~= 0 then
			-- a jump bigger than a few seconds of income is a sale or a reward
			if diff > math.max(1, income * 3) then
				coinScale.Scale = 1.12
				TweenService:Create(coinScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
				shownCoins += diff * 0.35
			elseif diff < 0 then
				shownCoins = target -- spending: no counting down
			else
				shownCoins = target
			end
			if math.abs(target - shownCoins) < 0.01 then
				shownCoins = target
			end
		end
		local text = Format.money(math.max(0, shownCoins))
		if text ~= shownText then
			shownText = text
			refs.Coins.Text = text
		end
		task.wait(0.05)
	end
end

return HudController
