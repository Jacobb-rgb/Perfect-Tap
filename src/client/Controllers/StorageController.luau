--[[
	StorageController: the Storage Crate panel.

	- Opens when the server says so (OpenUI 'Storage' { Machine }, sent by
	  the crate's "Open Crate" prompt).
	- Lists the shared store from the State snapshot (Storage summary
	  'K|O|G|R' -> count), most valuable first, and updates live.
	- TAKE / TAKE 5 send MachineAction(crate, 'StorageTake', { Key, Count });
	  the server checks everything and puts the items into your hands.
	- Closes with the X button, B (gamepad), Backspace, walking more than
	  MachineUseRange from the crate, or the crate going away.
	- Other prompts are hidden while it is open (so the key that opened it
	  can't fire a prompt behind the panel). Gamepads select the first TAKE
	  button.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local StorageView = require(script.Parent.Parent.UI.StorageView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local StorageController = {}

local CLOSE_ACTION = "TerraForgeStorageClose"
-- above the default player controls, so B / Backspace close the panel first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
-- under this many design units of screen width the panel uses 3 columns
local SIX_COLUMN_WIDTH = StorageView.panelWidth(6) + 40
local RANGE_CHECK = 0.25

local player = Players.LocalPlayer
local refs: StorageView.Refs? = nil
local crate: Model? = nil
local rangeConnection: RBXScriptConnection? = nil

function StorageController.isOpen(): boolean
	return crate ~= nil
end

local function rarityColor(oreId: string): Color3
	local ore = OreData.ById[oreId]
	local info = ore and Rarity.ById[ore.Rarity]
	return if info then info.Color else Theme.Text
end

-- The State summary as panel entries: known keys only, most valuable first.
local function entriesFrom(state: { [string]: any }?): { StorageView.Entry }
	local list: { StorageView.Entry } = {}
	local summary = state and state.Storage
	if type(summary) ~= "table" then
		return list
	end
	for key, count in summary do
		local desc = if type(key) == "string" then ItemData.parseKey(key) else nil
		if desc and type(count) == "number" and count >= 1 then
			table.insert(list, {
				Key = key,
				Name = ItemData.displayName(desc.K, desc.O, desc.G, desc.R),
				Count = math.floor(count),
				Value = ItemData.value(desc.K, desc.O, desc.G, desc.R),
				Color = rarityColor(desc.O),
			})
		end
	end
	table.sort(list, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		elseif a.Name ~= b.Name then
			return a.Name < b.Name
		end
		return a.Key < b.Key
	end)
	return list
end

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function take(key: string, count: number)
	local target = crate
	if not target then
		return
	end
	Sfx.play("UIClick")
	Net.send("MachineAction", target, "StorageTake", { Key = key, Count = math.clamp(count, 1, GameConfig.StorageTakeMax) })
end

-- Hooks up the buttons of newly created cards.
local function wire(cells: { StorageView.Cell })
	for _, cell in cells do
		local key = cell.Key
		cell.Take.Activated:Connect(function()
			take(key, 1)
		end)
		cell.TakeFive.Activated:Connect(function()
			local snapshot = StateController.get()
			local summary = snapshot and snapshot.Storage
			local have = if type(summary) == "table" then tonumber(summary[key]) or 1 else 1
			take(key, math.min(GameConfig.StorageTakeMax, have))
		end)
	end
end

-- Gamepads need something selected; keep it on a card that still exists.
local function keepSelection(view: StorageView.Refs)
	if not usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) then
		return
	end
	local first: StorageView.Cell? = nil
	for _, cell in view.Cells do
		if not first or cell.Frame.LayoutOrder < first.Frame.LayoutOrder then
			first = cell
		end
	end
	GuiService.SelectedObject = if first then first.Take else view.Close
end

local function refresh(state: { [string]: any }?)
	local view = refs
	if not view or not crate then
		return
	end
	wire(StorageView.setEntries(view, entriesFrom(state)))
	local count = if state then tonumber(state.StorageCount) or 0 else 0
	local capacity = if state then tonumber(state.StorageCapacity) or 0 else 0
	StorageView.setHeader(view, count, capacity)
	keepSelection(view)
end

local function hint(): string
	if usingGamepad() then
		return "A: take   B: close"
	elseif isPhone() then
		return "TAKE puts items in your hands"
	end
	return "TAKE puts items in your hands   •   Backspace: close"
end

function StorageController.close()
	if not crate then
		return
	end
	crate = nil
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
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Storage", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and crate then
		StorageController.close()
		Sfx.play("UIClick")
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function ensureView(): StorageView.Refs
	local view = refs
	if view then
		return view
	end
	local built = StorageView.build(6)
	built.Gui:SetAttribute("TerraForge", true)
	built.Gui.Parent = player:WaitForChild("PlayerGui")
	built.Close.Activated:Connect(function()
		StorageController.close()
		Sfx.play("UIClick")
	end)
	refs = built
	return built
end

-- Closes when you walk away or the crate disappears (packed up, streamed out).
local function watchRange(model: Model)
	local elapsed = 0
	rangeConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < RANGE_CHECK then
			return
		end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not model:IsDescendantOf(Workspace) or not root then
			StorageController.close()
			return
		end
		if (root.Position - model:GetPivot().Position).Magnitude > GameConfig.MachineUseRange then
			StorageController.close()
		end
	end)
end

function StorageController.open(model: Model)
	if crate == model then
		refresh(StateController.get())
		return
	end
	StorageController.close()
	local view = ensureView()
	crate = model
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X / HudController.uiScale() else math.huge
	StorageView.setColumns(view, if isPhone() or width < SIX_COLUMN_WIDTH then 3 else 6)
	view.Hint.Text = hint()
	view.Grid.CanvasPosition = Vector2.zero
	view.Gui.Enabled = true
	PromptController.setSuppressed("Storage", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watchRange(model)
	refresh(StateController.get())
	Sfx.play("UIClick")
end

function StorageController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Storage" or type(payload) ~= "table" then
			return
		end
		local model = payload.Machine
		if typeof(model) == "Instance" and model:IsA("Model") and model:GetAttribute("MachineId") == "StorageCrate" then
			StorageController.open(model)
		end
	end)
	StateController.onChanged(function(state)
		if crate then
			refresh(state)
		end
	end)
	player.CharacterRemoving:Connect(function()
		StorageController.close()
	end)
end

return StorageController
