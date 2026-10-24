--[[
	BackpackShopController: the backpack shop at the BACKPACKS stall (client
	side; the server decides everything: BackpackService of the backpack
	inventory, "Návrhy strojů" contract 2026-10-24).

	- Opens on OpenUI "Backpacks" { Counter } (the stall counter's prompt,
	  added by BackpackService). The ten cards (BackpackShopView) come from
	  the State snapshot: State.Backpacks { Equipped, Owned = { ids }, Count,
	  Capacity } and your coins (counted up between snapshots like the HUD);
	  they refresh on every State and once a second while the shop is open.
	- BUY sends BackpackAction ("Buy", { Id }), EQUIP sends ("Equip", { Id }).
	  A greyed-out BUY (not enough coins) answers here with how much is
	  missing and sends nothing. The server answers BackpackResult { Id, Ok,
	  Reason? }: a refusal shows its reason (BackpackShopView.Reasons) in the
	  header; a buy that went through brings the new State (the bigger pack
	  is equipped by the server). One request at a time (SEND_LOCK, freed by
	  the answer or the next State).
	- Until the backpack inventory lands (Net has no BackpackAction /
	  BackpackResult yet) the buttons say the shop opens soon: nothing is sent.
	- Closes with the X, B (gamepad), Backspace, walking away from the
	  counter (BackpackShopView.CloseRange), the counter streaming out,
	  respawning or another panel opening (MenuPanels). Other prompts are
	  hidden while it is open. Gamepads get a selected card on open; the
	  footer shows the controls (not on phones).
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
local BackpackData = require(Shared.Config.BackpackData)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local BackpackShopView = require(script.Parent.Parent.UI.BackpackShopView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local BackpackShopController = {}

BackpackShopController.Name = "BackpackShopController" -- (MenuPanels.Names)

local CLOSE_ACTION = "TerraForgeBackpackShopClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local OPEN_KIND = "Backpacks" -- OpenUI kind
local ACTION = "BackpackAction"
local RESULT = "BackpackResult"
local TICK = 0.25
local SEND_LOCK = 1
local MESSAGE_TIME = 5
local MESSAGE_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
}

local player = Players.LocalPlayer
local refs: BackpackShopView.Refs? = nil
local counter: BasePart? = nil
local tickConnection: RBXScriptConnection? = nil
local lockedUntil = 0
local messageToken = 0
local openedAt = 0
local progress: NumberValue? = nil
local animTween: Tween? = nil

function BackpackShopController.isOpen(): boolean
	return counter ~= nil
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Is the backpack inventory's server side in this build (its remotes)?
local function serverReady(): boolean
	return Net.Events[ACTION] ~= nil and Net.Events[RESULT] ~= nil
end

local function coins(): number
	return HudController.predictedCoins(os.clock())
end

-- The State's backpack record: owned set, equipped id, ore inside, capacity.
local function snapshot(): ({ [string]: boolean }, string, number, number)
	local state = StateController.get()
	local record = state and (state :: any).Backpacks
	local owned = BackpackShopView.ownedSet(if type(record) == "table" then record.Owned else nil)
	local equipped = if type(record) == "table"
			and type(record.Equipped) == "string"
			and BackpackData.ById[record.Equipped]
		then record.Equipped
		else BackpackData.StarterId
	-- everyone owns the free starter pack
	owned[BackpackData.StarterId] = true
	local count = if type(record) == "table" and type(record.Count) == "number" then record.Count else 0
	local capacity = if type(record) == "table" and type(record.Capacity) == "number"
		then record.Capacity
		else BackpackData.capacity(equipped)
	return owned, equipped, count, capacity
end

local function refresh()
	local view = refs
	if not view then
		return
	end
	local owned, equipped, count, capacity = snapshot()
	BackpackShopView.setCards(view, owned, equipped, coins())
	BackpackShopView.setStatus(view, BackpackShopView.statusText(equipped, count, capacity))
end

local function showMessage(text: string, kind: string?)
	local view = refs
	if not view then
		return
	end
	messageToken += 1
	local token = messageToken
	BackpackShopView.showMessage(view, text, MESSAGE_COLORS[kind or "Info"] or Theme.Info)
	task.delay(MESSAGE_TIME, function()
		if token == messageToken and refs then
			BackpackShopView.hideMessage(refs)
		end
	end)
end

local function fit(view: BackpackShopView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = isPhone() or scale <= 0.75 or size.Y < 520
	BackpackShopView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function applyHint(view: BackpackShopView.Refs)
	if usingGamepad() then
		local ok, image = pcall(function(): string
			return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
		end)
		view.HintGlyph.Image = if ok and type(image) == "string" then image else ""
		BackpackShopView.setHint(view, "Gamepad", "Choose a backpack · B: close")
	elseif isPhone() then
		BackpackShopView.setHint(view, "Touch", "Tap a card")
	else
		BackpackShopView.setHint(view, "Mouse", "Click a card · Backspace: close")
	end
end

local function selectDefault(view: BackpackShopView.Refs)
	if usingGamepad() and counter then
		GuiService.SelectedObject = BackpackShopView.firstButton(view)
	end
end

local function send(op: string, id: string)
	if not serverReady() then
		showMessage("The backpack shop opens soon!", "Info")
		return
	end
	if os.clock() < lockedUntil then
		return
	end
	lockedUntil = os.clock() + SEND_LOCK
	Net.send(ACTION, op, { Id = id })
	Sfx.play("UIClick")
end

local function onCard(card: BackpackShopView.Card)
	if not counter then
		return
	end
	local pack = card.Pack
	local state = card.State
	if state == "Buy" then
		send("Buy", pack.Id)
	elseif state == "BuyLocked" then
		local missing = math.max(1, pack.Price - coins())
		showMessage(`The {pack.Name} costs {Format.money(pack.Price)}. You need {Format.money(missing)} more.`, "Deny")
		Sfx.play("UIClick")
	elseif state == "Equip" then
		send("Equip", pack.Id)
	else
		showMessage(`You're wearing the {pack.Name}: {Format.commas(pack.Capacity)} ore.`, "Info")
		Sfx.play("UIClick")
	end
end

local function onResult(result: any)
	if type(result) ~= "table" then
		return
	end
	-- an answer arrived: the next request may go
	lockedUntil = 0
	if result.Ok == false and counter then
		local reason = if type(result.Reason) == "string" then BackpackShopView.Reasons[result.Reason] else nil
		showMessage(reason or "That didn't work, try again.", "Deny")
	elseif result.Ok == true and counter then
		local pack = BackpackData.ById[result.Id]
		if pack then
			showMessage(`{pack.Name}: {Format.commas(pack.Capacity)} ore on your back!`, "Reward")
		end
	end
	refresh()
end

---------------------------------------------------------------- the opening animation

local function stopAnimation()
	local tween = animTween
	animTween = nil
	if tween then
		tween:Cancel()
	end
end

local function ensureProgress(): NumberValue
	local existing = progress
	if existing then
		return existing
	end
	local value = Instance.new("NumberValue")
	value.Name = "BackpackShopOpening"
	value.Value = BackpackShopView.OpenTime
	value.Changed:Connect(function(seconds: number)
		local view = refs
		if view then
			BackpackShopView.pose(view, seconds)
		end
	end)
	progress = value
	return value
end

local function play(to: number, seconds: number, done: (() -> ())?)
	stopAnimation()
	local value = ensureProgress()
	local tween = TweenService:Create(value, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Value = to })
	animTween = tween
	tween.Completed:Connect(function()
		if animTween == tween then
			animTween = nil
			if done then
				done()
			end
		end
	end)
	tween:Play()
end

---------------------------------------------------------------- open / close

local function ensureView(): BackpackShopView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = BackpackShopView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		BackpackShopController.close()
		Sfx.play("UIClick")
	end)
	for _, card in view.Cards do
		card.Button.Activated:Connect(function()
			onCard(card)
		end)
	end
	refs = view
	return view
end

function BackpackShopController.close(instant: boolean?)
	if not counter then
		return
	end
	counter = nil
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	PromptController.setSuppressed("BackpackShop", false)
	local view = refs
	if not view then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) then
		GuiService.SelectedObject = nil
	end
	local gui = view.Gui
	if instant then
		stopAnimation()
		gui.Enabled = false
		return
	end
	local value = ensureProgress()
	play(0, BackpackShopView.CloseTime * value.Value / BackpackShopView.OpenTime, function()
		if not counter then
			gui.Enabled = false
		end
	end)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not counter then
		return Enum.ContextActionResult.Pass
	end
	BackpackShopController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

-- Every TICK: close when you walk away, the counter streams out or another panel
-- opens; once a second the cards follow your coins as they count up.
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
			BackpackShopController.close()
			return
		end
		local p = part.CFrame:PointToObjectSpace(root.Position)
		local half = part.Size / 2
		local outside =
			Vector3.new(math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Y) - half.Y, 0), math.max(math.abs(p.Z) - half.Z, 0))
		if outside.Magnitude > BackpackShopView.CloseRange then
			BackpackShopController.close()
			return
		end
		if os.clock() - openedAt > 0.3 and MenuPanels.otherOpen(BackpackShopController.Name) then
			BackpackShopController.close()
			return
		end
		if sinceRefresh >= 1 then
			sinceRefresh = 0
			refresh()
		end
	end)
end

function BackpackShopController.open(part: BasePart)
	local view = ensureView()
	if counter == part then
		refresh()
		return
	end
	if counter then
		BackpackShopController.close(true)
	end
	MenuPanels.closeOthers(BackpackShopController.Name)
	counter = part
	openedAt = os.clock()
	lockedUntil = 0
	fit(view)
	BackpackShopView.hideMessage(view)
	applyHint(view)
	refresh()
	view.Gui.Enabled = true
	PromptController.setSuppressed("BackpackShop", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ensureProgress().Value = 0
	BackpackShopView.pose(view, 0)
	play(BackpackShopView.OpenTime, BackpackShopView.OpenTime)
	watch(part)
	selectDefault(view)
	Sfx.play("UIClick")
end

---------------------------------------------------------------- lifecycle

function BackpackShopController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= OPEN_KIND or type(payload) ~= "table" then
			return
		end
		local part = payload.Counter
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			BackpackShopController.open(part)
		end
	end)
	if serverReady() then
		Net.listen(RESULT, onResult)
	end
	Net.listen("Notify", function(message)
		if counter and type(message) == "table" and type(message.Text) == "string" then
			showMessage(message.Text, message.Kind)
		end
	end)
	StateController.onChanged(function()
		lockedUntil = 0
		refresh()
	end)
	player.CharacterRemoving:Connect(function()
		BackpackShopController.close(true)
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and counter then
			applyHint(view)
			selectDefault(view)
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

return BackpackShopController
