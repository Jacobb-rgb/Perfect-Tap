--[[
	MachineUpgradeController: a machine's upgrades, at the machine (owner
	2026-11-07: press E at the machine, a window with its upgrades and short
	stats; never in a shop any more).

	- Prompt: every machine of yours with something to upgrade
	  (MachineUpgradeView.has) gets a client "Upgrades" prompt on its Prompt
	  attachment. It is on E while the machine's "Put In" is hidden (your
	  hands hold nothing it takes: PromptController); while "Put In" shows,
	  "Put In" keeps E and "Upgrades" steps to the Panel keys (T / L3) in
	  the next free slot (under a "Keep List" / "Change Sort" on G).
	  Other players' machines get none. Made by PromptConfig, so the keys
	  come from there (PromptKeys.spec).
	- Window (MachineUpgradeView): one row per upgrade from the State
	  snapshot and your coins (HudController.predictedCoins), refreshed on
	  every State push and twice a second (coins count up). BUY sends
	  ShopBuy { Shop = "Tech", Item, Level } (the level the row shows being
	  bought; the server refuses a repeat as "Stale"); the row says
	  "BOUGHT!" or the reason (EconomyConfig.TechShop.Reasons). One BUY per
	  item waits at a time; with no answer the row is freed after
	  ResultTimeout. A greyed-out BUY (not enough coins) answers locally.
	- A Speed level or a tier rebuilds your machines of that type (the new
	  look): the window follows the new model on the same spot (Owner,
	  MachineId, GridX / GridZ / GridL) for RebuildWait seconds.
	- Closes with the X, B (gamepad), Backspace, walking away from the
	  machine (past CloseRange, under the server's ShopService.MachineRange,
	  so lag never refuses a BUY), the machine going away, respawning or
	  another panel opening (MenuPanels: one panel at a time). Other prompts
	  are hidden while it is open.
]]

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MachineData = require(Shared.Config.MachineData)
local PromptConfig = require(Shared.Config.PromptConfig)
local Net = require(Shared.Net)
local MachineUpgradeView = require(script.Parent.Parent.UI.MachineUpgradeView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local MachineUpgradeController = {}

MachineUpgradeController.Name = "MachineUpgradeController"
MachineUpgradeController.PromptName = "UpgradePrompt"
MachineUpgradeController.ActionText = "Upgrades"
MachineUpgradeController.ResultTimeout = 5
MachineUpgradeController.MessageTime = 2.5
MachineUpgradeController.Tick = 0.5
MachineUpgradeController.RebuildWait = 3 -- seconds the window waits for a rebuilt machine

local CLOSE_ACTION = "TerraForgeMachineUpgradeClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local GOOD = Color3.fromRGB(130, 240, 120)
local BAD = Color3.fromRGB(255, 120, 110)
local WHITE = Color3.new(1, 1, 1)

type Message = { Text: string, Color: Color3, Until: number }

local refs: MachineUpgradeView.Refs? = nil
local shown = false
local machine: Model? = nil
local machineId: string? = nil
local pending: { [string]: number } = {} -- item -> give up at (os.clock)
local messages: { [string]: Message } = {}
local tickConnection: RBXScriptConnection? = nil
-- the open machine's spot while the server rebuilds it (a Speed level or a tier changes its look)
local lostSpot: string? = nil
local lostUntil = 0
local nextTick = 0
-- weak keys: machines that stream out drop out by themselves
local prompts: { [Model]: ProximityPrompt } = setmetatable({}, { __mode = "k" }) :: any
local watching: { [Model]: { RBXScriptConnection } } = {}

local function userId(): number
	return Players.LocalPlayer.UserId
end

---------------------------------------------------------------- prompts

local function machineIdOf(model: Instance): string?
	local id = model:GetAttribute("MachineId")
	return if type(id) == "string" then id else nil
end

local function own(model: Instance): boolean
	return model:GetAttribute("Owner") == userId()
end

-- Where a machine model stands (MachineUpgradeView.spotKey of its attributes).
local function spotOf(model: Instance): string
	return MachineUpgradeView.spotKey(
		model:GetAttribute("Owner"),
		model:GetAttribute("MachineId"),
		model:GetAttribute("GridX"),
		model:GetAttribute("GridZ"),
		model:GetAttribute("GridL")
	)
end

-- The open machine came back rebuilt (same owner, type and spot): the window follows it.
local function follow(model: Model)
	if shown and lostSpot and spotOf(model) == lostSpot then
		machine = model
		lostSpot = nil
	end
end

-- "Put In" visible, and a G prompt ("Keep List", "Change Sort") on the same spot.
local function neighbours(prompt: ProximityPrompt): (boolean, boolean)
	local spot = prompt.Parent
	local loadShown, second = false, false
	if spot then
		for _, other in spot:GetChildren() do
			if other ~= prompt and other:IsA("ProximityPrompt") then
				if other.Name == "LoadPrompt" then
					loadShown = other.Enabled
				elseif other.KeyboardKeyCode == PromptConfig.Keys.Second.Keyboard then
					second = true
				end
			end
		end
	end
	return loadShown, second
end

local function place(prompt: ProximityPrompt)
	local loadShown, second = neighbours(prompt)
	local role: PromptConfig.Role, slot = MachineUpgradeView.placement(loadShown, second)
	PromptConfig.setRole(prompt, role, slot)
end

local function unwatch(model: Model)
	local list = watching[model]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		watching[model] = nil
	end
	local prompt = prompts[model]
	if prompt then
		prompt:Destroy()
		prompts[model] = nil
	end
end

-- Makes the model's prompt once its Prompt attachment is there (models stream in whole, but late children are fine too).
local function tryPrompt(model: Model)
	if prompts[model] then
		return
	end
	local id = machineIdOf(model)
	local base = model.PrimaryPart
	if not id or not base or not own(model) or not MachineUpgradeView.has(id) then
		return
	end
	local spot = base:FindFirstChild("Prompt") or base
	local tier = model:GetAttribute("Tier")
	local prompt = PromptConfig.make({
		Name = MachineUpgradeController.PromptName,
		ActionText = MachineUpgradeController.ActionText,
		ObjectText = MachineData.info(id, tier).Name,
		Distance = 10,
	})
	prompt.Triggered:Connect(function()
		MachineUpgradeController.open(model)
	end)
	prompts[model] = prompt -- before parenting: its own DescendantAdded must never make a second one
	prompt.Parent = spot
	place(prompt)
	local list = watching[model]
	if list then
		-- "Put In" shows and hides with your hands (PromptController sets its Enabled here)
		for _, other in spot:GetChildren() do
			if other:IsA("ProximityPrompt") and other.Name == "LoadPrompt" then
				table.insert(
					list,
					other:GetPropertyChangedSignal("Enabled"):Connect(function()
						if prompt.Parent then
							place(prompt)
						end
					end)
				)
			end
		end
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") or watching[model] then
		return
	end
	local m = model :: Model
	follow(m)
	watching[m] = {}
	tryPrompt(m)
	table.insert(
		watching[m],
		m.DescendantAdded:Connect(function(child)
			local prompt = prompts[m]
			if not prompt then
				tryPrompt(m)
			elseif child:IsA("ProximityPrompt") and child.Parent == prompt.Parent then
				-- a late "Put In" / "Keep List": step aside, and follow "Put In"
				place(prompt)
				if child.Name == "LoadPrompt" then
					table.insert(
						watching[m],
						child:GetPropertyChangedSignal("Enabled"):Connect(function()
							if prompt.Parent then
								place(prompt)
							end
						end)
					)
				end
			end
		end)
	)
	-- a tier change (the Furnace) renames the prompt
	table.insert(
		watching[m],
		m:GetAttributeChangedSignal("Tier"):Connect(function()
			local prompt = prompts[m]
			local id = machineIdOf(m)
			if prompt and id then
				prompt.ObjectText = MachineData.info(id, m:GetAttribute("Tier")).Name
			end
		end)
	)
end

---------------------------------------------------------------- window

function MachineUpgradeController.isOpen(): boolean
	return shown
end

local function coins(): number
	return HudController.predictedCoins(os.clock())
end

local function rowFor(item: string): MachineUpgradeView.RowRefs?
	local view = refs
	if not view then
		return nil
	end
	for _, r in view.Rows do
		if r.Frame.Visible and r.Item == item then
			return r
		end
	end
	return nil
end

local function title(): string
	local id = machineId
	if not id then
		return "Upgrades"
	end
	local state = StateController.get()
	local tier = MachineData.tierOf(if state then state.MachineUpgrades else nil, id)
	return `{MachineData.info(id, tier).Name} Upgrades`
end

local buy: (k: number) -> ()

-- Hooks up BUY on rows the view made since (it makes them as a machine needs more).
local hooked = 0
local function hookRows(view: MachineUpgradeView.Refs)
	for k = hooked + 1, #view.Rows do
		view.Rows[k].Buy.Activated:Connect(function()
			buy(k)
		end)
	end
	hooked = #view.Rows
end

local function refresh()
	local view = refs
	local id = machineId
	if not view or not id or not shown then
		return
	end
	MachineUpgradeView.fill(view, title(), MachineUpgradeView.rows(id, StateController.get(), coins()))
	local now = os.clock()
	for _, r in view.Rows do
		local item = r.Item
		if r.Frame.Visible and item then
			local message = messages[item]
			if message and now < message.Until then
				MachineUpgradeView.say(r, message.Text)
				r.Why.TextColor3 = message.Color
			else
				messages[item] = nil
				r.Why.TextColor3 = WHITE
			end
			if pending[item] then
				MachineUpgradeView.busy(r)
			end
		end
	end
	hookRows(view)
end

local function tell(item: string, text: string, color: Color3)
	messages[item] = { Text = text, Color = color, Until = os.clock() + MachineUpgradeController.MessageTime }
	refresh()
end

function buy(k: number)
	local view = refs
	local r = view and view.Rows[k]
	if not r or not shown or not r.Frame.Visible then
		return
	end
	local item, level = r.Item, r.Next
	if not item or not level or pending[item] then
		return
	end
	if not r.Buy.Active then
		Sfx.play("UIDeny")
		tell(item, MachineUpgradeView.reasonText("NoCoins"), BAD)
		return
	end
	pending[item] = os.clock() + MachineUpgradeController.ResultTimeout
	Net.send("ShopBuy", { Shop = EconomyConfig.TechShop.Shop, Item = item, Level = level })
	Sfx.play("UIClick")
	refresh()
end

local function onResult(payload: any)
	if type(payload) ~= "table" or type(payload.Item) ~= "string" then
		return
	end
	local item = payload.Item :: string
	if not pending[item] then
		return -- not ours (the Tech shop's), or given up on
	end
	pending[item] = nil
	if not shown then
		return
	end
	if payload.Ok == true then
		Sfx.play("CoinBurst")
		local r = rowFor(item)
		if r then
			local scale = r.Frame:FindFirstChild("Pop") :: UIScale?
			if not scale then
				local made = Instance.new("UIScale")
				made.Name = "Pop"
				made.Parent = r.Frame
				scale = made
			end
			local s = scale :: UIScale
			s.Scale = 1.04
			TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		tell(item, MachineUpgradeView.Reasons.Bought, GOOD)
	else
		Sfx.play("UIDeny")
		tell(item, MachineUpgradeView.reasonText(payload.Reason), BAD)
	end
end

local function firstButton(view: MachineUpgradeView.Refs): GuiObject?
	for _, r in view.Rows do
		if r.Frame.Visible and r.Buy.Visible then
			return r.Buy
		end
	end
	return nil
end

function MachineUpgradeController.close()
	if not shown then
		return
	end
	shown = false
	machine = nil
	machineId = nil
	lostSpot = nil
	pending = {}
	messages = {}
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
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("MachineUpgrade", false)
end

local function closeByPlayer()
	MachineUpgradeController.close()
	Sfx.play("UIClick")
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not shown then
		return Enum.ContextActionResult.Pass
	end
	closeByPlayer()
	return Enum.ContextActionResult.Sink
end

local function ensureView(): MachineUpgradeView.Refs
	if refs then
		return refs :: MachineUpgradeView.Refs
	end
	local view = MachineUpgradeView.build()
	view.Gui:SetAttribute("TerraForge", true)
	view.Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(closeByPlayer)
	view.Dim.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			closeByPlayer()
		end
	end)
	refs = view
	return view
end

local function tick()
	local now = os.clock()
	if now < nextTick then
		return
	end
	nextTick = now + MachineUpgradeController.Tick
	local model = machine
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		MachineUpgradeController.close()
		return
	end
	if not model or not model.Parent then
		-- being rebuilt: wait a moment for the new model at the same spot
		if not (lostSpot and now < lostUntil) then
			MachineUpgradeController.close()
			return
		end
	elseif (model:GetPivot().Position - root.Position).Magnitude > MachineUpgradeView.CloseRange then
		MachineUpgradeController.close()
		return
	end
	for item, giveUp in pending do
		if now > giveUp then
			pending[item] = nil
			messages[item] = { Text = MachineUpgradeView.Reasons.NoAnswer, Color = BAD, Until = now + MachineUpgradeController.MessageTime }
		end
	end
	refresh()
end

-- Opens the window for one of your machines (its "Upgrades" prompt).
function MachineUpgradeController.open(model: Model)
	local id = machineIdOf(model)
	if not id or not own(model) or not MachineUpgradeView.has(id) then
		return
	end
	if shown and machine == model then
		refresh()
		return
	end
	MachineUpgradeController.close()
	MenuPanels.closeOthers(MachineUpgradeController.Name)
	local view = ensureView()
	shown = true
	machine = model
	machineId = id
	local uiScale = view.Gui:FindFirstChild("Scale") :: UIScale?
	if uiScale then
		uiScale.Scale = HudController.uiScale()
	end
	refresh()
	view.Gui.Enabled = true
	PromptController.setSuppressed("MachineUpgrade", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	nextTick = os.clock() + MachineUpgradeController.Tick
	tickConnection = RunService.Heartbeat:Connect(tick)
	GuiService.SelectedObject = if MenuPanels.usingGamepad() then firstButton(view) else nil
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

function MachineUpgradeController.init()
	Net.listen("ShopResult", onResult)
	StateController.onChanged(function()
		if shown then
			refresh()
		end
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		MachineUpgradeController.close()
	end)
end

function MachineUpgradeController.start()
	CollectionService:GetInstanceAddedSignal("Machine"):Connect(watch)
	CollectionService:GetInstanceRemovedSignal("Machine"):Connect(function(gone: Instance)
		if gone:IsA("Model") then
			local model = gone :: Model
			if machine == model then
				-- a rebuild (a Speed level, a tier) puts a new model on the same spot: follow it
				machine = nil
				lostSpot = spotOf(model)
				lostUntil = os.clock() + MachineUpgradeController.RebuildWait
				for _, other in CollectionService:GetTagged("Machine") do
					if other ~= model and other:IsA("Model") then
						follow(other)
					end
				end
			end
			unwatch(model)
		end
	end)
	for _, model in CollectionService:GetTagged("Machine") do
		watch(model)
	end
end

-- (tests)
MachineUpgradeController._test = {
	onResult = onResult,
	buy = buy,
	tick = tick,
	pending = function()
		return pending
	end,
	refs = function()
		return refs
	end,
	prompts = prompts,
	watch = watch,
}

return MachineUpgradeController
