--[[
	PenController: the Ore Pen on your base yard (client side).

	- Panel (PenView): opens on OpenUI "Pen" {} (the pen's "Open Pen"
	  prompt) or OpenUI "Pen" { Slot } (a podium's "Place Ore": pick mode).
	  Rows come from the State snapshot (Storage summary, Podiums,
	  PodiumSlots, PenCapacity) and update live.
	    TAKE    PenAction "Take" { Key, Count = 1 }: the ore comes out at the
	            pen gate, into your hands
	    SEND    PenAction "Send" { Key, Count = 1 } (like TAKE, one per
	            press; the merged Dirty Ore row: { Filter = "Dirty", Count
	            = 1 }): the server sends it onto your belts at the PEN
	            chute. For SendAllWindow seconds after, the button reads
	            "ALL xN?" (N = the stack, the one just sent included) and a
	            second press sends exactly that: { Key, All = true } (the
	            Dirty Ore row: { Filter = "Dirty" }), "all of this key",
	            which the server counts with the one already queued, so the
	            number shown is the number sent and nothing extra stays
	            queued. A mis-tap never sends a whole stack of podium ore
	    PODIUM  PenAction "ToPodium" { Key, Slot = first free unlocked slot }
	    PLACE   (pick mode) PodiumAction(slot, "Place", { Key }), then closes
	  The toolbar: SEND ALL DIRTY ({ Filter = "Dirty" }), SEND UNKEPT
	  ({ Filter = "Unkept" }, only with Upgrades.PenAutomation >= 1), STOP
	  (PenAction "StopSend") and the status from the State's PenSend. The
	  header's AUTO-SORT switch (with the billboard) sends PenAction
	  "AutoSort" { On } (State AutoSort).
	  Closes with X, B (gamepad), Backspace, walking away (pen: Range from
	  the gate; pick mode: from the podium) or respawning. Gamepads start on
	  the first button; other prompts are hidden while it is open. Phones
	  (uiScale <= 0.75) get the compact layout.
	- Prompts: "Open Pen" shows only on your own pen, "Put In" only while
	  you carry something (the server checks again).
	- Pile: up to BaseLayout.Pen.ShowMax display copies of what is in your
	  pen lie inside it (client-only parts, no collision). Only the
	  difference is rebuilt when the pen changes, so items don't jump around.
	- Fx "PenIn": a puff and a thud where ore went into the pen.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ItemData = require(Shared.Config.ItemData)
local WorldLayout = require(Shared.Config.WorldLayout)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Net = require(Shared.Net)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PenView = require(script.Parent.Parent.UI.PenView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local FxController = require(script.Parent.FxController)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local PenController = {}

-- keep in sync with PenService.Range / PodiumService.Range (server)
PenController.PenRange = 24
PenController.PodiumRange = 30
PenController.SendAllWindow = 3 -- seconds a row's SEND reads "ALL xN?" after a press

local CLOSE_ACTION = "TerraForgePenClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local RANGE_CHECK = 0.25
local PILE_LIGHTS = 2 -- display copies keep at most this many lights in the pile
local PILE_EMITTERS = 6

local player = Players.LocalPlayer
local refs: PenView.Refs? = nil
local isOpen = false
local rangeConnection: RBXScriptConnection? = nil

---------------------------------------------------------------- helpers

local function myPlotId(): number?
	local id = player:GetAttribute("PlotId")
	return if type(id) == "number" and WorldLayout.Plots[id] then id else nil
end

local function plotCFrame(plotId: number): CFrame
	return WorldLayout.plotCFrame(WorldLayout.Plots[plotId])
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function carryCount(): number
	return (player:GetAttribute("CarryCount") :: number?) or 0
end

---------------------------------------------------------------- prompts

local function applyPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local mine = prompt:GetAttribute("PlotId") == myPlotId()
	if prompt.Name == "PenPutIn" then
		prompt.Enabled = mine and carryCount() > 0
	else
		prompt.Enabled = mine
	end
end

local function refreshPrompts()
	for _, prompt in CollectionService:GetTagged("PenPrompt") do
		applyPrompt(prompt)
	end
end

---------------------------------------------------------------- panel

-- rows on screen by key (the merged Dirty Ore row holds its real keys)
local shownEntries: { [string]: PenView.Entry } = {}
-- rows whose SEND reads "ALL xN?" until this os.clock()
local armedUntil: { [string]: number } = {}

local function disarm(view: PenView.Refs, rowKey: string)
	armedUntil[rowKey] = nil
	local row = view.Rows[rowKey]
	if row then
		row.Send.Text = PenView.sendButtonText(nil)
	end
end

--[[
	SEND: one item; pressed again while it reads "ALL xN?" (N = the stack):
	all of it. The server counts "all" with the one already queued, so N is
	exactly what goes out, whether that one has left yet or not.
]]
local function sendRow(view: PenView.Refs, rowKey: string, entry: PenView.Entry?, key: string)
	local deadline = armedUntil[rowKey]
	if entry and deadline and os.clock() < deadline then
		disarm(view, rowKey)
		if entry.Keys then
			Net.send("PenAction", "Send", { Filter = "Dirty" })
		else
			Net.send("PenAction", "Send", { Key = entry.Key, All = true })
		end
		return
	end
	if entry and entry.Keys then
		Net.send("PenAction", "Send", { Filter = "Dirty", Count = 1 })
	else
		Net.send("PenAction", "Send", { Key = key, Count = 1 })
	end
	local all = if entry then entry.Count else 0
	local row = view.Rows[rowKey]
	if all <= 1 or not row then
		return
	end
	local stamp = os.clock() + PenController.SendAllWindow
	armedUntil[rowKey] = stamp
	row.Send.Text = PenView.sendButtonText(all)
	task.delay(PenController.SendAllWindow, function()
		if armedUntil[rowKey] == stamp then
			disarm(view, rowKey)
		end
	end)
end

local function send(rowKey: string, button: string)
	local view = refs
	if not view then
		return
	end
	local entry = shownEntries[rowKey]
	local key = if entry then PenView.keyFor(entry, math.random()) else rowKey
	if not key then
		return
	end
	Sfx.play("UIClick")
	if button == "Send" then
		sendRow(view, rowKey, entry, key)
	elseif view.Mode == "Pick" then
		local slot = view.Slot
		if slot then
			Net.send("PodiumAction", slot, "Place", { Key = key })
		end
		PenController.close()
	elseif button == "Take" then
		Net.send("PenAction", "Take", { Key = key, Count = 1 })
	else
		local state = StateController.get()
		local slot = state and PenView.freeSlot(state.Podiums, state.PodiumSlots)
		if slot then
			Net.send("PenAction", "ToPodium", { Key = key, Slot = slot })
		else
			HudController.toast("Every podium is taken. Remove an ore from a podium first.", "Deny")
		end
	end
end

local function wire(rows: { PenView.Row })
	for _, row in rows do
		local key = row.Key
		row.Take.Activated:Connect(function()
			send(key, "Take")
		end)
		row.Send.Activated:Connect(function()
			send(key, "Send")
		end)
		row.Podium.Activated:Connect(function()
			send(key, "Podium")
		end)
	end
end

-- Gamepads need something selected; keep it on a row that still exists.
local function keepSelection(view: PenView.Refs)
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
	local first: PenView.Row? = nil
	for _, row in view.Rows do
		if not first or row.Frame.LayoutOrder < first.Frame.LayoutOrder then
			first = row
		end
	end
	local target: GuiObject = view.Close
	if first then
		local take = first.Take.Parent :: GuiObject
		target = if take.Visible then first.Take else first.Podium
	end
	GuiService.SelectedObject = target
end

local function refresh(state: { [string]: any }?)
	local view = refs
	if not view or not isOpen then
		return
	end
	-- "+$X/s" with the income bonus, like the podium tags and the HUD
	local entries = PenView.entries(state and state.Storage, view.Mode, PenView.incomeMult(state and state.Bonuses))
	table.clear(shownEntries)
	for _, entry in entries do
		shownEntries[entry.Key] = entry
	end
	local canPodium = state ~= nil and PenView.freeSlot(state.Podiums, state.PodiumSlots) ~= nil
	wire(PenView.setEntries(view, entries, canPodium))
	-- an armed SEND follows the stack: "ALL xN?" is always what a press sends
	-- (back to SEND when it is gone)
	local now = os.clock()
	for rowKey, deadline in armedUntil do
		local entry = shownEntries[rowKey]
		local row = view.Rows[rowKey]
		if not entry or not row or now >= deadline then
			disarm(view, rowKey)
		else
			row.Send.Text = PenView.sendButtonText(entry.Count)
		end
	end
	local upgrades = state and state.Upgrades
	local automation = if type(upgrades) == "table" then tonumber(upgrades.PenAutomation) or 0 else 0
	PenView.setAutoSort(view, automation >= EconomyConfig.PenAutomation.Billboard, state == nil or state.AutoSort ~= false)
	local dirty = 0
	for _, entry in entries do
		if entry.Keys then
			dirty += entry.Count
		end
	end
	PenView.setSending(view, state and state.PenSend, automation >= EconomyConfig.PenAutomation.Billboard, dirty)
	local count = if state then tonumber(state.StorageCount) or 0 else 0
	local capacity = if state then tonumber(state.PenCapacity) or 0 else 0
	PenView.setHeader(view, count, capacity)
	keepSelection(view)
end

-- Footer hint for the current device (gamepads get their own button glyphs).
local function updateHint(view: PenView.Refs)
	if usingGamepad() then
		local a = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
		local b = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
		PenView.setHint(view, "", a, b)
	elseif view.Mode == "Pick" then
		PenView.setHint(view, "Pick the ore this podium shows off", nil, nil)
	elseif isTouch() then
		PenView.setHint(view, "TAKE: carry it  -  SEND: onto your belts (twice: all)  -  PODIUM: money every second", nil, nil)
	else
		PenView.setHint(view, "TAKE: to your hands  -  SEND: to your belts (twice: all)  -  PODIUM: money/s  -  Backspace: close", nil, nil)
	end
end

function PenController.isOpen(): boolean
	return isOpen
end

function PenController.close()
	if not isOpen then
		return
	end
	isOpen = false
	if rangeConnection then
		rangeConnection:Disconnect()
		rangeConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		for rowKey in armedUntil do
			disarm(view, rowKey)
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Pen", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and isOpen then
		PenController.close()
		Sfx.play("UIClick")
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function ensureView(): PenView.Refs
	local view = refs
	if view then
		return view
	end
	local built = PenView.build()
	built.Gui.Parent = player:WaitForChild("PlayerGui")
	built.Close.Activated:Connect(function()
		PenController.close()
		Sfx.play("UIClick")
	end)
	built.SendDirty.Activated:Connect(function()
		Sfx.play("UIClick")
		Net.send("PenAction", "Send", { Filter = "Dirty" })
	end)
	built.SendUnkept.Activated:Connect(function()
		Sfx.play("UIClick")
		Net.send("PenAction", "Send", { Filter = "Unkept" })
	end)
	built.StopSend.Activated:Connect(function()
		Sfx.play("UIClick")
		Net.send("PenAction", "StopSend", {})
	end)
	built.AutoSort.Activated:Connect(function()
		Sfx.play("UIClick")
		local state = StateController.get()
		local on = state == nil or state.AutoSort ~= false
		Net.send("PenAction", "AutoSort", { On = not on })
	end)
	refs = built
	return built
end

-- The screen in design units (what the panel's UIScale sees), below the top bar.
local function screenRoom(scale: number): Vector2?
	local camera = Workspace.CurrentCamera
	if not camera or scale <= 0 then
		return nil
	end
	local topLeft, bottomRight = GuiService:GetGuiInset()
	local size = camera.ViewportSize - topLeft - bottomRight
	return Vector2.new(size.X / scale, size.Y / scale)
end

-- Where the panel belongs: the pen gate, or the podium in pick mode.
local function anchorPoint(plotId: number, slot: number?): (Vector3, number)
	local cf = plotCFrame(plotId)
	if slot and BaseLayout.Podiums[slot] then
		local rect = BaseLayout.Podiums[slot]
		return (cf * CFrame.new(rect.Center.X, 0, rect.Center.Z)).Position, PenController.PodiumRange
	end
	return (cf * CFrame.new(BaseLayout.Pen.PromptPoint)).Position, PenController.PenRange
end

local function watchRange(plotId: number, slot: number?)
	local point, range = anchorPoint(plotId, slot)
	local elapsed = 0
	rangeConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < RANGE_CHECK then
			return
		end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or myPlotId() ~= plotId then
			PenController.close()
			return
		end
		local offset = root.Position - point
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > range then
			PenController.close()
		end
	end)
end

-- Opens the panel (slot = pick mode for that podium).
function PenController.open(slot: number?)
	local plotId = myPlotId()
	if not plotId then
		return
	end
	PenController.close()
	MenuPanels.closeOthers("PenController") -- one panel at a time
	local view = ensureView()
	local scale = HudController.uiScale()
	PenView.setCompact(view, scale <= 0.75, screenRoom(scale))
	PenView.setMode(view, if slot then "Pick" else "Pen", slot)
	updateHint(view)
	view.List.CanvasPosition = Vector2.zero
	view.Gui.Enabled = true
	isOpen = true
	PromptController.setSuppressed("Pen", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watchRange(plotId, slot)
	refresh(StateController.get())
	Sfx.play("UIClick")
end

---------------------------------------------------------------- pile

type PileItem = { Key: string, Spot: number, Model: Model }

local pileFolder: Folder? = nil
local pile: { PileItem } = {}
local pilePlot: number? = nil
local pileSignature = ""
local spots: { CFrame } = {}

local function clearPile()
	for _, item in pile do
		item.Model:Destroy()
	end
	table.clear(pile)
	pileSignature = ""
end

local function pileModel(key: string, spot: CFrame, seed: string): Model?
	local desc = ItemData.parseKey(key)
	if not desc then
		return nil
	end
	local ok, built = pcall(ItemBuilder.display, desc, spot, seed)
	if not ok or typeof(built) ~= "Instance" then
		return nil
	end
	local model = built :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	return model
end

-- Keeps the light and particle budget of the whole pile small.
local function trimEffects()
	local lights, emitters = 0, 0
	for _, item in pile do
		for _, d in item.Model:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				if lights > PILE_LIGHTS then
					d:Destroy()
				end
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
				if emitters > PILE_EMITTERS then
					d:Destroy()
				end
			end
		end
	end
end

local function updatePile(state: { [string]: any }?)
	local plotId = myPlotId()
	if plotId ~= pilePlot then
		clearPile()
		pilePlot = plotId
		spots = if plotId then PenView.pileSpots(plotCFrame(plotId), plotId) else {}
	end
	if not plotId or not state then
		return
	end
	local counts = PenView.pileCounts(state.Storage, BaseLayout.Pen.ShowMax)
	local keys = {}
	for key, n in counts do
		table.insert(keys, `{key}={n}`)
	end
	table.sort(keys)
	local signature = table.concat(keys, ";")
	if signature == pileSignature then
		return
	end
	pileSignature = signature
	local folder = pileFolder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "PenPile"
		f.Parent = Workspace
		folder = f
		pileFolder = f
	end
	-- remove what is no longer wanted
	local have: { [string]: number } = {}
	local used: { [number]: boolean } = {}
	for i = #pile, 1, -1 do
		local item = pile[i]
		local n = (have[item.Key] or 0) + 1
		if n > (counts[item.Key] or 0) then
			item.Model:Destroy()
			table.remove(pile, i)
		else
			have[item.Key] = n
			used[item.Spot] = true
		end
	end
	-- add what is missing, on free spots
	for key, want in counts do
		for _ = (have[key] or 0) + 1, want do
			local spot: number? = nil
			for i = 1, #spots do
				if not used[i] then
					spot = i
					break
				end
			end
			if not spot then
				break
			end
			used[spot] = true
			local model = pileModel(key, spots[spot], `{key}/{spot}`)
			if model then
				model.Parent = folder
				table.insert(pile, { Key = key, Spot = spot, Model = model })
			end
		end
	end
	trimEffects()
end

---------------------------------------------------------------- lifecycle

function PenController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind ~= "Pen" then
			return
		end
		local slot = if type(payload) == "table" then payload.Slot else nil
		local valid = type(slot) == "number" and BaseLayout.Podiums[slot] ~= nil
		PenController.open(if valid then slot :: number else nil)
	end)
	StateController.onChanged(function(state)
		refresh(state)
		updatePile(state)
	end)
	FxController.register("PenIn", function(position: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		Vfx.burst("Dust", position, 6)
		Sfx.play("Drop", position)
	end)
	player.CharacterRemoving:Connect(function()
		PenController.close()
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

function PenController.start()
	CollectionService:GetInstanceAddedSignal("PenPrompt"):Connect(applyPrompt)
	refreshPrompts()
	player:GetAttributeChangedSignal("CarryCount"):Connect(refreshPrompts)
	player:GetAttributeChangedSignal("PlotId"):Connect(function()
		refreshPrompts()
		updatePile(StateController.get())
	end)
end

return PenController
