--[[
	SellController: Tobin's Sell view and the coin burst when you sell.

	- Opens on OpenUI "Sell" { Hands, Counter } (the stall's "Sell Ore"
	  prompt). The pen comes from the State snapshot (Storage summary), the
	  hands from the payload and then from State.Hands; both refresh on every
	  State update.
	- Buttons send SellAction ("Sell" { Key, Count, From } or "SellAll"
	  { Filter, From? }); the server checks everything. Selling more than
	  SellView.ConfirmCount items or anything Epic+ asks first (never by
	  rarity for Dirty Ore: that would give its secret away).
	- Closes with the X button, B (gamepad), Backspace, walking away from the
	  counter or respawning. B / Backspace close the confirm step first.
	  Other prompts are hidden while it is open; gamepads get a selected
	  button on open and after every refresh.
	- Earned { Amount, Source = "Sell", Position, Count }: a "+$X" popup
	  rises at the stall with a coin burst and coin sounds; sales within
	  EconomyConfig.Sell.ComboWindow pump the same popup with the running total.
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
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local SellView = require(script.Parent.Parent.UI.SellView)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local SellController = {}

type Section = SellView.Section
type Pending = { Run: () -> () }

local CLOSE_ACTION = "TerraForgeSellClose"
-- above the default player controls, so B / Backspace close the view first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local RANGE_CHECK = 0.25
-- a bit more than the server's SellService.Range (20), so lag never closes it early
local CLOSE_RANGE = 26
-- "Sell all" buttons wait for the next State (at most this long) before they work again
local ALL_LOCK = 1
-- seconds a message stays in the view's header
local RECEIPT_TIME = 5
local RECEIPT_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
	Discovery = Theme.Accent,
}

local player = Players.LocalPlayer
local refs: SellView.Refs? = nil
local counter: BasePart? = nil
local hands: { [string]: number } = {}
local rangeConnection: RBXScriptConnection? = nil
local pending: Pending? = nil
local lockedUntil = 0
local receiptToken = 0

function SellController.isOpen(): boolean
	return counter ~= nil
end

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function penSummary(): any
	local state = StateController.get()
	return state and state.Storage
end

---------------------------------------------------------------- sending

-- HUD toasts are hidden behind the panel: while it is open, messages also
-- show in its header for a few seconds.
local function receipt(text: string, kind: any, rarityId: any)
	local view = refs
	if not view or not counter then
		return
	end
	local color = if type(kind) == "string" then RECEIPT_COLORS[kind] or Theme.Info else Theme.Info
	local info = if type(rarityId) == "string" then Rarity.ById[rarityId] else nil
	if info then
		color = info.Color
	end
	SellView.showReceipt(view, text, color)
	receiptToken += 1
	local token = receiptToken
	task.delay(RECEIPT_TIME, function()
		local current = refs
		if receiptToken == token and current then
			SellView.hideReceipt(current)
		end
	end)
end

local function send(action: string, arg: { [string]: any }, lock: boolean)
	if lock then
		lockedUntil = os.clock() + ALL_LOCK
	end
	Sfx.play("UIClick")
	Net.send("SellAction", action, arg)
end

local function locked(): boolean
	return os.clock() < lockedUntil
end

local function closeHolder(view: SellView.Refs): Frame
	return view.Close.Parent :: Frame
end

local function setInteractable(view: SellView.Refs, on: boolean)
	-- Interactable is newer than some tools' API dumps: never let it break the view
	pcall(function()
		view.List.Interactable = on
		view.Footer.Interactable = on
		closeHolder(view).Interactable = on
	end)
end

-- The platform's own B / Circle glyph on the close button while a gamepad is used.
local function updateGlyph(view: SellView.Refs)
	local holder = closeHolder(view)
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
	local label = glyph :: ImageLabel
	local gamepad = usingGamepad()
	label.Visible = gamepad
	if gamepad then
		label.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
	end
end

local function selectDefault(view: SellView.Refs)
	if not usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) and selected.Visible then
		local holder = selected.Parent
		if not holder or not holder:IsA("GuiObject") or holder.Visible then
			return
		end
	end
	local first = SellView.firstRow(view)
	GuiService.SelectedObject = if first then first.SellOne else view.Close
end

local function cancelConfirm()
	local view = refs
	pending = nil
	if view and view.Confirm.Visible then
		SellView.hideConfirm(view)
		setInteractable(view, true)
		GuiService.SelectedObject = nil
		selectDefault(view)
	end
end

-- Runs `run` now, or after the player says yes.
local function confirmThen(needed: boolean, text: string, run: () -> ())
	local view = refs
	if not needed or not view then
		run()
		return
	end
	pending = { Run = run }
	SellView.showConfirm(view, text)
	setInteractable(view, false)
	if usingGamepad() then
		-- a confirm guards against mistakes: Cancel is the safe default
		GuiService.SelectedObject = view.ConfirmNo
	end
	Sfx.play("UIClick")
end

local function sellRow(row: SellView.Row, all: boolean)
	local entry = row.Entry
	local from: Section = entry.Section
	if all and locked() then
		return
	end
	if not all then
		local key = SellView.pickKey(entry, math.random())
		if not key then
			return
		end
		confirmThen(SellView.needsConfirm(1, entry.RarityOrder), SellView.confirmRowText(entry, 1), function()
			send("Sell", { Key = key, Count = 1, From = from }, false)
		end)
		return
	end
	local count = math.min(entry.Count, EconomyConfig.Sell.MaxPerRequest)
	local run: () -> ()
	if entry.Dirty then
		run = function()
			send("SellAll", { Filter = "Dirty", From = from }, true)
		end
	else
		local key = next(entry.Keys)
		if not key then
			return
		end
		run = function()
			send("Sell", { Key = key, Count = count, From = from }, true)
		end
	end
	confirmThen(SellView.needsConfirm(count, entry.RarityOrder), SellView.confirmRowText(entry, count), run)
end

local function sellFiltered(filter: string)
	if locked() then
		return
	end
	local plan = SellView.plan(penSummary(), hands, filter, nil)
	if plan.Count == 0 then
		receipt(
			if filter == "Dirty" then "You have no Dirty Ore to sell." else "Nothing to sell: Tobin leaves your best ores to you.",
			"Deny",
			nil
		)
		Sfx.play("UIDeny")
		return
	end
	confirmThen(SellView.needsConfirm(plan.Count, plan.BestOrder), SellView.confirmPlanText(plan, filter), function()
		send("SellAll", { Filter = filter }, true)
	end)
end

---------------------------------------------------------------- the view

local function wire(rows: { SellView.Row })
	for _, row in rows do
		row.SellOne.Activated:Connect(function()
			sellRow(row, false)
		end)
		row.SellAll.Activated:Connect(function()
			sellRow(row, true)
		end)
	end
end

local function refresh()
	local view = refs
	if not view or not counter then
		return
	end
	local pen = penSummary()
	wire(SellView.setEntries(view, "Pen", SellView.entries(pen, "Pen")))
	wire(SellView.setEntries(view, "Hands", SellView.entries(hands, "Hands")))
	SellView.setFooter(view, SellView.plan(pen, hands, "Dirty", nil), SellView.plan(pen, hands, "AllButBest", nil))
	if not view.Confirm.Visible then
		selectDefault(view)
	end
end

local function hint(): string
	if usingGamepad() then
		return "Choose a button to sell"
	elseif isPhone() then
		return "Tap Sell to sell to Tobin"
	end
	return "Click Sell to sell to Tobin   •   Backspace: close"
end

-- Fits the panel to the screen (phones get the compact layout).
local function fit(view: SellView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = isPhone() or scale <= 0.75 or size.Y < 520
	SellView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

function SellController.close()
	if not counter then
		return
	end
	counter = nil
	pending = nil
	if rangeConnection then
		rangeConnection:Disconnect()
		rangeConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		SellView.hideConfirm(view)
		SellView.hideReceipt(view)
		setInteractable(view, true)
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Sell", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not counter then
		return Enum.ContextActionResult.Pass
	end
	local view = refs
	if view and view.Confirm.Visible then
		cancelConfirm()
	else
		SellController.close()
	end
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function ensureView(): SellView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = SellView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		SellController.close()
		Sfx.play("UIClick")
	end)
	view.SellDirty.Activated:Connect(function()
		sellFiltered("Dirty")
	end)
	view.SellRest.Activated:Connect(function()
		sellFiltered("AllButBest")
	end)
	view.ConfirmYes.Activated:Connect(function()
		local job = pending
		cancelConfirm()
		if job then
			job.Run()
		end
	end)
	view.ConfirmNo.Activated:Connect(function()
		cancelConfirm()
		Sfx.play("UIClick")
	end)
	view.Confirm.Activated:Connect(cancelConfirm)
	-- gamepads can't leave the confirm box (links to themselves stop the move)
	local yes, no = view.ConfirmYes, view.ConfirmNo
	yes.NextSelectionLeft = yes
	yes.NextSelectionUp = yes
	yes.NextSelectionDown = yes
	no.NextSelectionRight = no
	no.NextSelectionUp = no
	no.NextSelectionDown = no
	refs = view
	return view
end

-- Closes when you walk away or the counter disappears (streamed out).
local function watchRange(part: BasePart)
	local elapsed = 0
	rangeConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < RANGE_CHECK then
			return
		end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not part:IsDescendantOf(Workspace) or not root then
			SellController.close()
			return
		end
		local p = part.CFrame:PointToObjectSpace(root.Position)
		local half = part.Size / 2
		local outside =
			Vector3.new(math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Y) - half.Y, 0), math.max(math.abs(p.Z) - half.Z, 0))
		if outside.Magnitude > CLOSE_RANGE then
			SellController.close()
		end
	end)
end

function SellController.open(part: BasePart, handsSummary: any)
	if type(handsSummary) == "table" then
		hands = handsSummary
	end
	if counter == part then
		refresh()
		return
	end
	SellController.close()
	MenuPanels.closeOthers("SellController") -- one panel at a time
	local view = ensureView()
	counter = part
	fit(view)
	view.Hint.Text = hint()
	updateGlyph(view)
	view.List.CanvasPosition = Vector2.zero
	view.Gui.Enabled = true
	PromptController.setSuppressed("Sell", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watchRange(part)
	GuiService.SelectedObject = nil
	refresh()
	Sfx.play("UIClick")
	-- a quick pop-in
	local pop = view.Panel:FindFirstChild("OpenPop") :: UIScale?
	if not pop then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = view.Panel
		pop = made
	end
	local scale = pop :: UIScale
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- coin popup

type Popup = {
	Part: Part,
	Gui: BillboardGui,
	Amount: TextLabel,
	Line: TextLabel,
	Scale: UIScale,
	Token: number,
	Total: number,
	Items: number,
	Sales: number,
	LastAt: number,
}

local POOL_SIZE = 3
local RISE = 3.5 -- studs
local RISE_TIME = 1.1
local FADE_TIME = 0.35

local pool: { Popup } = {}
local nextPopup = 1
local current: Popup? = nil

local function newPopup(folder: Folder, index: number): Popup
	local part = UIKit.new("Part", {
		Name = "SellPopup" .. index,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
	}, folder)
	local gui = UIKit.new("BillboardGui", {
		Name = "Earned",
		Size = UDim2.fromOffset(260, 100),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		Enabled = false,
		Adornee = part,
	}, part)
	local scale = UIKit.new("UIScale", { Scale = 1 }, gui)
	local amount = UIKit.label(gui, "+$0", 46, {
		Name = "Amount",
		Size = UDim2.new(1, 0, 0, 60),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Coin,
	})
	local line = UIKit.label(gui, "", 22, {
		Name = "Line",
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = Theme.Text,
	})
	return {
		Part = part,
		Gui = gui,
		Amount = amount,
		Line = line,
		Scale = scale,
		Token = 0,
		Total = 0,
		Items = 0,
		Sales = 0,
		LastAt = -math.huge,
	}
end

local function ensurePool()
	if #pool > 0 and pool[1].Part.Parent then
		return
	end
	table.clear(pool)
	local folder = Instance.new("Folder")
	folder.Name = "SellFx"
	folder.Parent = Workspace
	for i = 1, POOL_SIZE do
		table.insert(pool, newPopup(folder, i))
	end
	nextPopup = 1
	current = nil
end

local function setTransparency(popup: Popup, value: number, info: TweenInfo?)
	for _, label in { popup.Amount, popup.Line } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if info then
			TweenService:Create(label, info, { TextTransparency = value }):Play()
			if stroke then
				TweenService:Create(stroke, info, { Transparency = value }):Play()
			end
		else
			label.TextTransparency = value
			if stroke then
				stroke.Transparency = value
			end
		end
	end
end

local function showEarned(position: Vector3, amount: number, items: number)
	ensurePool()
	local now = os.clock()
	local popup: Popup
	local last = current
	if last and now - last.LastAt <= EconomyConfig.Sell.ComboWindow then
		popup = last
	else
		popup = pool[nextPopup]
		nextPopup = nextPopup % #pool + 1
		popup.Total, popup.Items, popup.Sales = 0, 0, 0
	end
	current = popup
	popup.Total += amount
	popup.Items += items
	popup.Sales += 1
	popup.LastAt = now
	popup.Token += 1
	local token = popup.Token

	popup.Part.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	popup.Amount.Text = "+" .. Format.money(popup.Total)
	popup.Line.Text = if popup.Sales > 1 then `COMBO x{popup.Sales}` elseif popup.Items > 1 then `{Format.commas(popup.Items)} items` else ""
	popup.Gui.StudsOffsetWorldSpace = Vector3.zero
	popup.Gui.Enabled = true
	setTransparency(popup, 0, nil)
	-- pop in, rise, then fade near the top
	popup.Scale.Scale = 1.4 + 0.05 * math.min(popup.Sales, 8)
	TweenService:Create(popup.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(popup.Gui, TweenInfo.new(RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, RISE, 0),
	}):Play()
	setTransparency(popup, 1, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, RISE_TIME - FADE_TIME))
	task.delay(RISE_TIME + 0.05, function()
		if popup.Token == token then
			popup.Gui.Enabled = false
		end
	end)

	Vfx.burst("Burst", position, math.min(30, 6 + items * 3), Theme.Coin)
	Vfx.burst("Glint", position, 6, Theme.Coin)
	local pitch = 1 + 0.05 * math.min(popup.Sales - 1, 8)
	Sfx.play("CoinBurst", nil, pitch)
	Sfx.play("Sell", nil, pitch)
end

local function onEarned(payload: any)
	if type(payload) ~= "table" or payload.Source ~= "Sell" then
		return
	end
	local amount = payload.Amount
	local position = payload.Position
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or typeof(position) ~= "Vector3" then
		return
	end
	local count = if type(payload.Count) == "number" and payload.Count == payload.Count then math.max(1, math.floor(payload.Count)) else 1
	showEarned(position, amount, count)
end

---------------------------------------------------------------- lifecycle

function SellController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Sell" or type(payload) ~= "table" then
			return
		end
		local part = payload.Counter
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			SellController.open(part, payload.Hands)
		end
	end)
	Net.listen("Earned", onEarned)
	Net.listen("Notify", function(message)
		if counter and type(message) == "table" and type(message.Text) == "string" then
			receipt(message.Text, message.Kind, message.Rarity)
		end
	end)
	StateController.onChanged(function(state)
		if type(state.Hands) == "table" then
			hands = state.Hands
		end
		-- a new snapshot means the last sale went through
		lockedUntil = 0
		if counter then
			refresh()
		end
	end)
	player.CharacterRemoving:Connect(function()
		SellController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and counter then
			view.Hint.Text = hint()
			updateGlyph(view)
			if not view.Confirm.Visible then
				selectDefault(view)
			elseif usingGamepad() and GuiService.SelectedObject == nil then
				GuiService.SelectedObject = view.ConfirmNo
			end
		end
	end)
end

return SellController
