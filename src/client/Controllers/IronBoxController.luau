--[[
	IronBoxController: the keep list (client side).

	- Opens on OpenUI "IronBox" { Box, Position } (the "Keep List" prompt on
	  your own Iron Box or on your pen's sorting board; the server checks it
	  is yours and, for the board, the Pen Automation level). The panel (IronBoxView)
	  shows every ore you have discovered as a chip, from the State snapshot
	  (Discovered, KeepMode, KeepList), and updates live.
	    chip           IronBoxAction "SetKeep" { Ore, Keep = the other way }
	    mode buttons   IronBoxAction "SetMode" { Mode }
	    SET ALL: KEEP / SEND   IronBoxAction "SetKeepMany" { Ores = every chip, Keep }
	    RESET (MY LIST)        IronBoxAction "ClearList" (back to the Rare+ rule)
	  A tap shows at once: the action is applied to the last snapshot with
	  IronBoxView.predict (the server's rules) until the server's snapshot
	  catches up (pending actions are re-applied on newer snapshots for
	  PENDING_SECONDS, so an older snapshot never flips a chip back; after
	  that the panel shows the latest snapshot as it is).
	- Closes with X, B (gamepad), Backspace, walking away from the box or
	  board (Range; measured from the Position the server sent, or from
	  where you stood, while the model hasn't streamed in), it going away,
	  or respawning. Gamepads start on the first chip; other prompts are
	  hidden while it is open. Phones (uiScale <= 0.75) get the compact
	  layout; the chip rows fit the screen.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineData = require(Shared.Config.MachineData)
local Net = require(Shared.Net)
local IronBoxView = require(script.Parent.Parent.UI.IronBoxView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local IronBoxController = {}

IronBoxController.Range = 24 -- studs from the box (flat) before the panel closes

local CLOSE_ACTION = "TerraForgeIronBoxClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local RANGE_CHECK = 0.25
local PENDING_SECONDS = 1.5

type Pending = { At: number, Action: string, Arg: any }

local player = Players.LocalPlayer
local refs: IronBoxView.Refs? = nil
local isOpen = false
local box: Model? = nil
-- where the range check measures from when `box` isn't here (yet)
local anchor: Vector3? = nil
local rangeConnection: RBXScriptConnection? = nil
local resizeConnection: RBXScriptConnection? = nil
local pending: { Pending } = {}
-- the snapshot the panel shows (the server's, plus pending taps)
local shown: { [string]: any }? = nil
local shownEntries: { [string]: IronBoxView.Entry } = {}

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

---------------------------------------------------------------- panel

-- Gamepads need something selected; keep it on a chip that still exists.
local function keepSelection(view: IronBoxView.Refs)
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
	local first: IronBoxView.Chip? = nil
	for _, chip in view.Chips do
		if not first or chip.Button.LayoutOrder < first.Button.LayoutOrder then
			first = chip
		end
	end
	GuiService.SelectedObject = if first then first.Button else view.Modes[view.Mode]
end

local function redraw()
	local view = refs
	local state = shown
	if not view or not isOpen then
		return
	end
	local entries = IronBoxView.entries(state)
	table.clear(shownEntries)
	for _, entry in entries do
		shownEntries[entry.Ore] = entry
	end
	local created = IronBoxView.setEntries(view, entries)
	for _, chip in created do
		local oreId = chip.Ore
		chip.Button.Activated:Connect(function()
			local entry = shownEntries[oreId]
			if entry then
				IronBoxController.act("SetKeep", { Ore = oreId, Keep = not entry.Keep })
			end
		end)
	end
	IronBoxView.setMode(view, IronBoxView.modeOf(state), IronBoxView.hasList(state))
	keepSelection(view)
end

-- A new server snapshot: show it with the taps it may not have seen yet.
local function onState(state: { [string]: any })
	local now = os.clock()
	local view: { [string]: any } = state
	for i = #pending, 1, -1 do
		if now - pending[i].At > PENDING_SECONDS then
			table.remove(pending, i)
		end
	end
	for _, p in pending do
		view = IronBoxView.predict(view, p.Action, p.Arg)
	end
	shown = view
	redraw()
end

-- Sends one IronBoxAction and shows its result right away.
function IronBoxController.act(action: string, arg: any)
	local base = shown or StateController.get()
	if not base then
		return
	end
	Sfx.play("UIClick")
	Net.send("IronBoxAction", action, arg)
	table.insert(pending, { At = os.clock(), Action = action, Arg = arg })
	shown = IronBoxView.predict(base, action, arg)
	redraw()
	-- once the guess expires, show the server's word again (an action the
	-- rate limit dropped changes nothing there, so no new snapshot comes)
	task.delay(PENDING_SECONDS + 0.1, function()
		local state = StateController.get()
		if isOpen and state then
			onState(state)
		end
	end)
end

local function every(keep: boolean)
	local ores = {}
	for oreId in shownEntries do
		table.insert(ores, oreId)
	end
	if #ores > 0 then
		table.sort(ores)
		IronBoxController.act("SetKeepMany", { Ores = ores, Keep = keep })
	end
end

local function updateHint(view: IronBoxView.Refs)
	if usingGamepad() then
		local a = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
		local b = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
		IronBoxView.setHint(view, "", a, b)
	elseif isTouch() then
		IronBoxView.setHint(view, "Tap an ore to keep it or send it on", nil, nil)
	else
		IronBoxView.setHint(view, "Click an ore to keep it or send it on  -  Backspace: close", nil, nil)
	end
end

-- Compact on phones; the chip rows fit the screen (design units).
local function fit(view: IronBoxView.Refs)
	local scale = HudController.uiScale()
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	IronBoxView.layout(view, scale <= 0.75, size.X / scale, (size.Y - inset.Y) / scale)
end

function IronBoxController.isOpen(): boolean
	return isOpen
end

function IronBoxController.close()
	if not isOpen then
		return
	end
	isOpen = false
	box = nil
	anchor = nil
	if rangeConnection then
		rangeConnection:Disconnect()
		rangeConnection = nil
	end
	if resizeConnection then
		resizeConnection:Disconnect()
		resizeConnection = nil
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
	PromptController.setSuppressed("IronBox", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and isOpen then
		IronBoxController.close()
		Sfx.play("UIClick")
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function ensureView(): IronBoxView.Refs
	local view = refs
	if view then
		return view
	end
	local built = IronBoxView.build()
	built.Gui.Parent = player:WaitForChild("PlayerGui")
	built.Close.Activated:Connect(function()
		IronBoxController.close()
		Sfx.play("UIClick")
	end)
	for mode, button in built.Modes do
		button.Activated:Connect(function()
			if MachineData.isKeepMode(mode) then
				IronBoxController.act("SetMode", { Mode = mode })
			end
		end)
	end
	built.AllKeep.Activated:Connect(function()
		every(true)
	end)
	built.AllSend.Activated:Connect(function()
		every(false)
	end)
	built.Reset.Activated:Connect(function()
		IronBoxController.act("ClearList", nil)
	end)
	refs = built
	return built
end

local function watchRange()
	local elapsed = 0
	rangeConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < RANGE_CHECK then
			return
		end
		elapsed = 0
		local target = box
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (target and not target.Parent) then
			IronBoxController.close()
			return
		end
		local center = if target then target:GetPivot().Position else anchor
		if not center then
			-- no model and no position: measure from where you opened it
			center = root.Position
			anchor = center
		end
		local offset = root.Position - center
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > IronBoxController.Range then
			IronBoxController.close()
		end
	end)
end

--[[
	Opens the keep list. `target` = the box or board it was opened at, for
	the range check; `at` = its position (the server's word, used while the
	model hasn't streamed in to this client).
]]
function IronBoxController.open(target: Model?, at: Vector3?)
	IronBoxController.close()
	local view = ensureView()
	fit(view)
	updateHint(view)
	view.List.CanvasPosition = Vector2.zero
	view.Gui.Enabled = true
	isOpen = true
	box = target
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	anchor = at or (if root and root:IsA("BasePart") then root.Position else nil)
	PromptController.setSuppressed("IronBox", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watchRange()
	local camera = Workspace.CurrentCamera
	if camera then
		resizeConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if isOpen then
				fit(view)
			end
		end)
	end
	local state = StateController.get()
	if state then
		onState(state)
	end
	Sfx.play("UIClick")
end

---------------------------------------------------------------- lifecycle

function IronBoxController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "IronBox" then
			return
		end
		local target = if type(payload) == "table" then payload.Box else nil
		local at = if type(payload) == "table" then payload.Position else nil
		IronBoxController.open(
			if typeof(target) == "Instance" and target:IsA("Model") then target else nil,
			if typeof(at) == "Vector3" then at else nil
		)
	end)
	StateController.onChanged(function(state)
		if isOpen then
			onState(state)
		end
	end)
	player.CharacterRemoving:Connect(function()
		IronBoxController.close()
	end)
	-- switching between mouse, touch and gamepad updates the footer live
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and isOpen then
			updateHint(view)
			keepSelection(view)
		end
	end)
end

return IronBoxController
