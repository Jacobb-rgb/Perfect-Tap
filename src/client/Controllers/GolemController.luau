--[[
	GolemController: golem pets on the client (step 7).

	Inventory (GolemView):
	- Opens from the HUD's GOLEMS button (right-side menu, under BUILD; 44 pt
	  tall at the phone scale), the toggle key P (keyboard) / L1 (gamepad,
	  only while no other screen holds the selection or the controls; the
	  button shows the key or the platform's glyph), the capsule view's MY
	  GOLEMS button (GolemController.open) or OpenUI "Golems". Cards come
	  from the State snapshot and update live.
	- Select a golem (click / tap / A) to see it turn in 3D (a ViewportFrame
	  over its portrait) with EQUIP / UNEQUIP, LOCK / UNLOCK and DELETE
	  (asks first). EQUIP BEST equips the 3 best. DELETE... enters delete
	  mode: pick golems (locked ones can't be picked), + ALL COMMON /
	  + ALL UNCOMMON pick every unlocked, unequipped golem of that rarity,
	  DELETE n asks, then sends one GolemAction "Delete" (at most
	  GolemConfig.MaxDelete ids: the box says how many go now, the rest
	  stay picked for the next press).
	- Every request is a GolemAction; the server answers ActionResult
	  { Action = "Golem" } and the State push redraws the cards. A button
	  shows "..." until the answer (freed after a few seconds without one).
	- Closes with X, B / Backspace (first the confirm box, then delete mode),
	  P / L1, respawning or another panel opening. With a gamepad the
	  selection never gets lost: when the selected button hides or its card
	  goes (a delete), it moves to the first card (or EQUIP BEST / X).

	Followers:
	- Every player's equipped golems follow them (the player attribute
	  GolemConfig.EquippedAttribute, kept by GolemService). Built here, on
	  each client, only for players within GolemConfig.FollowerHideDistance
	  of the camera (built again when they come back); nothing is replicated.
	  Models: GolemBuilder.build(kind, start, { Welded = true, Size =
	  FollowerSize }) in a local folder, every part created in place at the
	  start CFrame (so the welds hold the shape whenever they switch on):
	  one anchored Body per golem moves the whole golem (one CFrame write
	  per golem per frame), no part collides, touches or is queried.
	- Movement: each golem eases toward its slot behind its owner (left,
	  right, back), hopping as it walks (one hop per HopStride studs, a
	  little forward tilt and side roll; a Premium golem, Legendary or
	  Mythic, glides on its aura instead, bobbing), faces where it walks,
	  turns to its owner's facing when it stops, bobs gently while idle
	  (only within GolemConfig.FollowerLodDistance), and jumps straight to
	  its slot when it falls far behind (teleports, respawns). The ground
	  height comes from a short downward raycast every GroundSeconds per
	  golem (staggered; only parts that collide, never characters: the
	  filter is renewed when a character spawns), else the owner's feet.
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
local GolemConfig = require(Shared.Config.GolemConfig)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local GolemView = require(script.Parent.Parent.UI.GolemView)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local CleaningController = require(script.Parent.CleaningController)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local GolemController = {}

type Panel = { isOpen: () -> boolean, close: () -> () }

GolemController.FollowerSize = 0.85 -- followers a little smaller than the capsule reveal
GolemController.HopStride = 1.7 -- studs per hop
GolemController.GroundSeconds = 0.3
GolemController.CatchUpDistance = 45 -- further behind: jump to the slot
GolemController.LookAround = 1.3 -- radians an idle golem may turn away from its owner's facing
GolemController.LookSeconds = { 2.5, 6 } -- how long it looks one way
-- slots behind the owner (owner space: +X right, +Z behind)
GolemController.Slots = { Vector3.new(-3.1, 0, 3.0), Vector3.new(3.1, 0, 3.0), Vector3.new(0, 0, 5.2) }
-- open / close the inventory from anywhere (D-pad: Up BUILD, Down teleports,
-- Left the side menu, Right the luck boosts; L1 is free outside panels)
GolemController.ToggleKey = Enum.KeyCode.P
GolemController.ToggleButton = Enum.KeyCode.ButtonL1

local CLOSE_ACTION = "TerraForgeGolemsClose"
local TOGGLE_ACTION = "TerraForgeGolemsToggle"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local PENDING_TIMEOUT = 3
local STATUS_TIME = 3
-- panels that own the middle of the screen: one at a time (the step 6-7
-- packages' panels too; a name that isn't in the game is skipped)
local OTHER_PANELS = {
	"CapsuleController",
	"TechShopController",
	"PenController",
	"SellController",
	"TrainController",
	"IronBoxController",
	"FoundryController",
	"GearShopController",
	"BoostController",
	"EnchantController",
	"WheelController",
	"ArtifactController",
	"CodexController",
	"LeaderboardController",
	"SettingsController",
	"StoreController",
}

local player = Players.LocalPlayer
local refs: GolemView.Refs? = nil
local shown = false
local cards: { GolemView.Card } = {}
local selected: number? = nil
local deleting = false
local picked: { [number]: boolean } = {}
local confirmAction: (() -> ())? = nil
local pendingButton: TextButton? = nil
local pendingText = ""
local pendingUntil = 0
local statusToken = 0
local openedAt = 0
local tickConnection: RBXScriptConnection? = nil
local others: { Panel }? = nil
local viewModel: Model? = nil
local viewKind: string? = nil
local menuButton: TextButton? = nil
local deleteSent: { number }? = nil -- the ids of the Delete waiting for its answer

function GolemController.isOpen(): boolean
	return shown
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

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

---------------------------------------------------------------- the inventory

local function status(text: string, color: Color3?)
	local view = refs
	if not view then
		return
	end
	GolemView.setStatus(view, text, color)
	statusToken += 1
	local token = statusToken
	task.delay(STATUS_TIME, function()
		local current = refs
		if statusToken == token and current then
			GolemView.setStatus(current, nil, nil)
		end
	end)
end

local function updateHint(view: GolemView.Refs)
	local sep = GolemView.Separator
	local toggle = GolemController.ToggleKey.Name
	if usingGamepad() then
		GolemView.setHint(
			view,
			`{padName(Enum.KeyCode.ButtonA)}: pick / press{sep}{padName(Enum.KeyCode.ButtonB)}: back{sep}{padName(
				GolemController.ToggleButton
			)}: close`
		)
	elseif isTouch() then
		GolemView.setHint(view, if deleting then "Tap the golems to delete" else "Tap a golem to see it")
	elseif deleting then
		GolemView.setHint(view, `Click the golems to delete{sep}Backspace: back`)
	else
		GolemView.setHint(view, `Click a golem to see it{sep}{toggle} / Backspace: close`)
	end
end

-- Is `object` shown (it and every frame above it up to the panel's gui)?
local function onScreen(view: GolemView.Refs, object: Instance): boolean
	local node: Instance? = object
	while node and node ~= view.Gui do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node == view.Gui
end

-- Where a gamepad's selection goes when it has nowhere to be.
local function homeSelection(view: GolemView.Refs): GuiObject
	if confirmAction then
		return view.ConfirmNo
	end
	for _, card in cards do
		local c = view.Cards[card.Id]
		if c and card.Order == 1 then
			return c.Button
		end
	end
	if deleting then
		return view.DeleteCancel
	end
	return if onScreen(view, view.EquipBest) then view.EquipBest else view.Close
end

-- With a gamepad, keeps the selection on something shown in the panel
-- (a deleted card or a hidden button would leave it nowhere).
local function keepSelection(view: GolemView.Refs)
	if not shown or not usingGamepad() then
		return
	end
	local current = GuiService.SelectedObject
	if current and current:IsDescendantOf(view.Gui) and onScreen(view, current) then
		return
	end
	GuiService.SelectedObject = homeSelection(view)
end

local function cardOf(id: number?): GolemView.Card?
	if not id then
		return nil
	end
	for _, card in cards do
		if card.Id == id then
			return card
		end
	end
	return nil
end

-- The selected golem turning in 3D over its portrait.
local function showModel(view: GolemView.Refs, card: GolemView.Card?)
	local kind = if card and card.Known then card.Kind else nil
	if kind == viewKind then
		return
	end
	viewKind = kind
	local old = viewModel
	if old then
		old:Destroy()
		viewModel = nil
	end
	-- (short screens have no room for the portrait: no 3D either)
	local room = view.DetailHolder.Size.X.Offset > 0
	view.Viewport.Visible = kind ~= nil and room
	view.DetailHolder.Visible = kind == nil
	if not kind or not room then
		return
	end
	local model = GolemBuilder.build(kind)
	model.Parent = view.Viewport
	viewModel = model
	local camera = view.Viewport.CurrentCamera
	if not camera then
		local made = Instance.new("Camera")
		made.FieldOfView = 30
		made.Parent = view.Viewport
		view.Viewport.CurrentCamera = made
		camera = made
	end
	local height = (model:GetAttribute("Height") :: number?) or 3
	local target = Vector3.new(0, height * 0.48, 0)
	local distance = height * 2.6 + 1
	local cam = camera :: Camera
	cam.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(0.35) * distance, distance * 0.15, -math.cos(0.35) * distance), target)
end

local onCard: (id: number) -> () -- (defined below)

local function hookCards(view: GolemView.Refs)
	for id, c in view.Cards do
		if c.Button:GetAttribute("Hooked") ~= true then
			c.Button:SetAttribute("Hooked", true)
			c.Button.Activated:Connect(function()
				onCard(id)
			end)
		end
	end
end

local function refresh()
	local view = refs
	if not view or not shown then
		return
	end
	local state = StateController.get()
	cards = GolemView.cards(state)
	if selected and not cardOf(selected) then
		selected = nil
	end
	for id in picked do
		local card = cardOf(id)
		if not card or card.Locked or not card.Known then
			picked[id] = nil
		end
	end
	local count = 0
	for _ in picked do
		count += 1
	end
	GolemView.setCount(view, GolemView.countText(state), GolemConfig.count(if state then state.Golems else nil) >= GolemConfig.InventoryCap)
	GolemView.setEquipped(view, GolemView.equipped(state), GolemView.totals(state))
	GolemView.setCards(view, cards, selected, if deleting then picked else nil)
	GolemView.setDeleteMode(view, deleting, count)
	local card = cardOf(selected)
	if pendingButton == nil then
		GolemView.setDetail(view, card)
	end
	showModel(view, if deleting then nil else card)
	GolemView.style(view.EquipBest, #cards > 0, Theme.Good, Theme.GoodDark)
	updateHint(view)
	hookCards(view)
	keepSelection(view)
end

local function freePending()
	local button = pendingButton
	pendingButton = nil
	pendingUntil = 0
	if button then
		button.Text = pendingText
		button:SetAttribute("Busy", false)
	end
	refresh()
end

-- Sends one GolemAction; `button` shows "..." until the answer.
local function send(op: string, arg: any?, button: TextButton?)
	if pendingButton then
		status("One moment...", Theme.Info)
		return
	end
	if button then
		pendingButton = button
		pendingText = button.Text
		pendingUntil = os.clock() + PENDING_TIMEOUT
		button.Text = "..."
		button:SetAttribute("Busy", true)
	end
	Sfx.play("UIClick")
	Net.send("GolemAction", op, arg)
end

local function hideConfirm()
	local view = refs
	confirmAction = nil
	if view then
		GolemView.hideConfirm(view)
		if usingGamepad() then
			GuiService.SelectedObject = if deleting then view.DeleteConfirm else view.Delete
		end
	end
end

local function askConfirm(text: string, action: () -> ())
	local view = refs
	if not view then
		return
	end
	confirmAction = action
	GolemView.showConfirm(view, text)
	if usingGamepad() then
		GuiService.SelectedObject = view.ConfirmNo
	end
	Sfx.play("UIClick")
end

local function setDeleting(on: boolean)
	deleting = on
	table.clear(picked)
	refresh()
	local view = refs
	if view then
		updateHint(view)
	end
	if view and usingGamepad() then
		local first = next(view.Cards)
		GuiService.SelectedObject = if on then view.DeleteCancel elseif first then view.Cards[first].Button else view.Close
	end
end

onCard = function(id: number)
	local card = cardOf(id)
	if not card then
		return
	end
	if deleting then
		if card.Locked or not card.Known then
			status(if card.Locked then "Locked golems can't be deleted: unlock it first" else "You can't delete this golem", Theme.Bad)
			Sfx.play("UIDeny")
			return
		end
		if picked[id] then
			picked[id] = nil
		else
			picked[id] = true
		end
		Sfx.play("UIClick")
		refresh()
		return
	end
	selected = id
	Sfx.play("UIClick")
	refresh()
end

local function pickRarity(rarityId: string)
	for _, id in GolemView.pickRarity(cards, rarityId) do
		picked[id] = true
	end
	Sfx.play("UIClick")
	refresh()
end

local function deletePicked()
	local ids: { number } = {}
	for _, card in cards do
		if picked[card.Id] then
			table.insert(ids, card.Id)
		end
	end
	if #ids == 0 then
		status("Pick the golems to delete first", Theme.Bad)
		Sfx.play("UIDeny")
		return
	end
	-- the server takes at most GolemConfig.MaxDelete ids per request: the
	-- box names what goes now, the rest stay picked for the next press
	local total = #ids
	while #ids > GolemConfig.MaxDelete do
		table.remove(ids)
	end
	local now: { [number]: boolean } = {}
	for _, id in ids do
		now[id] = true
	end
	local text = GolemView.confirmText(cards, now)
	if total > #ids then
		text ..= ` {total - #ids} more stay picked: press DELETE again for them.`
	end
	askConfirm(text, function()
		local view = refs
		deleteSent = ids
		send("Delete", { Ids = ids }, if view then view.DeleteConfirm else nil)
	end)
end

function GolemController.close()
	if not shown then
		return
	end
	shown = false
	deleting = false
	table.clear(picked)
	confirmAction = nil
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if view then
		local s = GuiService.SelectedObject
		if s and s:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		GolemView.hideConfirm(view)
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Golems", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not shown then
		return Enum.ContextActionResult.Pass
	end
	if confirmAction then
		hideConfirm()
	elseif deleting then
		setDeleting(false)
	else
		GolemController.close()
	end
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function openCapsules()
	local module = script.Parent:FindFirstChild("CapsuleController")
	if module and module:IsA("ModuleScript") then
		local ok, controller = pcall(require, module :: any)
		local capsules = controller :: any
		if ok and type(capsules) == "table" and type(capsules.open) == "function" then
			GolemController.close()
			capsules.open()
		end
	end
end

local builtCompact: boolean? = nil

local function compactNow(): boolean
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return TechShopView.compactFor(isTouch(), GuiService:IsTenFootInterface(), HudController.uiScale(), size.Y)
end

local function fit(view: GolemView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	GolemView.layout(view, view.Compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function ensureView(): GolemView.Refs
	local compact = compactNow()
	local existing = refs
	if existing and builtCompact == compact then
		return existing
	end
	if existing then
		existing.Gui:Destroy()
		viewModel = nil
		viewKind = nil
	end
	builtCompact = compact
	local view = GolemView.build(compact)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		Sfx.play("UIClick")
		GolemController.close()
	end)
	view.Capsules.Activated:Connect(function()
		Sfx.play("UIClick")
		openCapsules()
	end)
	view.DeleteMode.Activated:Connect(function()
		Sfx.play("UIClick")
		setDeleting(not deleting)
	end)
	view.EquipBest.Activated:Connect(function()
		if #cards > 0 then
			send("EquipBest", nil, view.EquipBest)
		end
	end)
	view.Equip.Activated:Connect(function()
		local card = cardOf(selected)
		if not card or not card.Known then
			return
		end
		if not card.Equipped and #GolemView.equipped(StateController.get()) >= GolemConfig.EquipSlots then
			status(GolemConfig.Reasons.SlotsFull .. ": unequip one first", Theme.Bad)
			Sfx.play("UIDeny")
			return
		end
		send(if card.Equipped then "Unequip" else "Equip", { Id = card.Id }, view.Equip)
	end)
	view.Lock.Activated:Connect(function()
		local card = cardOf(selected)
		if card then
			send("Lock", { Id = card.Id, Locked = not card.Locked }, view.Lock)
		end
	end)
	view.Delete.Activated:Connect(function()
		local card = cardOf(selected)
		if not card or not card.Known then
			return
		end
		if card.Locked then
			status("Locked golems can't be deleted: unlock it first", Theme.Bad)
			Sfx.play("UIDeny")
			return
		end
		local one = { [card.Id] = true }
		askConfirm(GolemView.confirmText(cards, one), function()
			deleteSent = { card.Id }
			send("Delete", { Ids = { card.Id } }, view.Delete)
		end)
	end)
	view.PickCommon.Activated:Connect(function()
		pickRarity("Common")
	end)
	view.PickUncommon.Activated:Connect(function()
		pickRarity("Uncommon")
	end)
	view.DeleteConfirm.Activated:Connect(deletePicked)
	view.DeleteCancel.Activated:Connect(function()
		Sfx.play("UIClick")
		setDeleting(false)
	end)
	view.ConfirmYes.Activated:Connect(function()
		local action = confirmAction
		hideConfirm()
		if action then
			action()
		end
	end)
	view.ConfirmNo.Activated:Connect(function()
		Sfx.play("UIClick")
		hideConfirm()
	end)
	refs = view
	return view
end

local function watch(view: GolemView.Refs)
	local elapsed = 0
	local spin = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		spin += dt
		local model = viewModel
		if model and model.Parent then
			-- (the pivot is the Body: RootHeight above the feet)
			local rootHeight = (model:GetAttribute("RootHeight") :: number?) or 1
			model:PivotTo(CFrame.new(0, rootHeight, 0) * CFrame.Angles(0, math.sin(spin * 0.8) * 0.7, 0))
		end
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		if pendingButton and os.clock() > pendingUntil then
			freePending()
			status("No answer, try again", Theme.Bad)
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					GolemController.close()
					return
				end
			end
		end
		hookCards(view)
	end)
end

-- Opens the inventory.
function GolemController.open()
	if shown then
		refresh()
		return
	end
	for _, panel in otherPanels() do
		if panel.isOpen() then
			panel.close()
		end
	end
	local view = ensureView()
	shown = true
	openedAt = os.clock()
	deleting = false
	table.clear(picked)
	fit(view)
	updateHint(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("Golems", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	refresh()
	hookCards(view)
	watch(view)
	if usingGamepad() then
		local first: GuiObject = view.Close
		for _, card in cards do
			local c = view.Cards[card.Id]
			if c and card.Order == 1 then
				first = c.Button
			end
		end
		GuiService.SelectedObject = first
	end
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

local DONE_TEXT: { [string]: string } = {
	Equip = "Equipped!",
	Unequip = "Unequipped",
	EquipBest = "Your best golems are equipped!",
}

local function onActionResult(payload: any)
	if type(payload) ~= "table" or payload.Action ~= "Golem" then
		return
	end
	local sent = deleteSent
	if payload.Op == "Delete" then
		deleteSent = nil
	end
	if payload.Ok == true then
		local op = payload.Op
		local text = DONE_TEXT[op]
		if op == "Lock" then
			local card = cardOf(if type(payload.Id) == "number" then payload.Id else nil)
			text = if card and card.Locked then "Unlocked" else "Locked: it can't be deleted"
		elseif op == "Delete" then
			local n = if type(payload.Count) == "number" then payload.Count else 0
			text = `Deleted {n} golem{if n == 1 then "" else "s"}`
			-- the sent ones are gone; golems still picked (past MaxDelete) stay in delete mode
			if sent then
				for _, id in sent do
					picked[id] = nil
				end
			end
			if next(picked) == nil then
				deleting = false
			else
				text ..= ": press DELETE again for the rest"
			end
			selected = nil
		end
		-- (the state above first: freePending redraws, and the selection moves to a card)
		freePending()
		if shown and text then
			status(text, Theme.Good)
		end
		Sfx.play(if op == "Delete" then "Drop" else "CoinBurst")
		return
	end
	freePending()
	local reason = payload.Reason
	local text = if type(reason) == "string" and GolemConfig.Reasons[reason]
		then GolemConfig.Reasons[reason]
		else "You can't do that right now"
	if shown then
		status(text, Theme.Bad)
	else
		HudController.toast(text, "Deny")
	end
	Sfx.play("UIDeny")
end

---------------------------------------------------------------- followers

type Pet = {
	Model: Model,
	Root: BasePart,
	RootHeight: number,
	Slot: number,
	Pos: Vector3, -- feet position (x, z follow; y = ground)
	Ground: number,
	NextGround: number,
	Yaw: number,
	Phase: number,
	Seed: number,
	Look: number, -- idle: the turn away from the owner's facing (looking around)
	NextLook: number,
	Floats: boolean, -- a Premium golem (GolemBuilder "Hover"): glides, never hops
}
type Follower = { Player: Player, Kinds: string, Pets: { Pet } }

local followers: { [Player]: Follower } = {}
local folder: Folder? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- decor, glass, zones, trims and loose chunks don't carry golems

local function followersFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "GolemFollowers"
	made.Parent = Workspace
	folder = made
	return made
end

local function rootOf(owner: Player): BasePart?
	local character = owner.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- The owner's feet height (fallback ground).
local function feetY(owner: Player, root: BasePart): number
	local character = owner.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local hip = if humanoid then humanoid.HipHeight else 2
	return root.Position.Y - root.Size.Y / 2 - hip
end

local function clearPets(f: Follower)
	for _, pet in f.Pets do
		pet.Model:Destroy()
	end
	table.clear(f.Pets)
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- Builds the follower's golems from its kinds (at the owner's slots).
local function buildPets(f: Follower)
	clearPets(f)
	local root = rootOf(f.Player)
	if f.Kinds == "" or not root then
		return
	end
	local list = string.split(f.Kinds, ",")
	for i, kind in list do
		if i > GolemConfig.EquipSlots then
			break
		end
		if GolemConfig.ById[kind] then
			local slot = GolemController.Slots[i]
			local feet = (root.CFrame * CFrame.new(slot)).Position
			local ground = feetY(f.Player, root)
			local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
			-- every part is created in place (the welds then hold this shape)
			local start = CFrame.new(feet.X, ground, feet.Z) * CFrame.Angles(0, yaw, 0)
			local model = GolemBuilder.build(kind, start, { Welded = true, Size = GolemController.FollowerSize })
			local body = model.PrimaryPart :: BasePart
			local rootHeight = (model:GetAttribute("RootHeight") :: number?) or 1
			local hover = (model:GetAttribute("Hover") :: number?) or 0
			model.Name = `{f.Player.Name}_{kind}`
			model.Parent = followersFolder()
			table.insert(f.Pets, {
				Model = model,
				Root = body,
				RootHeight = rootHeight,
				Slot = i,
				Pos = Vector3.new(feet.X, ground, feet.Z),
				Ground = ground,
				NextGround = 0,
				Yaw = yaw,
				Phase = 0,
				Seed = i * 1.7 + (f.Player.UserId % 97) * 0.13,
				Look = 0,
				NextLook = 0,
				Floats = hover > 0,
			})
		end
	end
end

-- The raycast skips every character and the followers (renewed when one spawns or leaves).
local function refreshFilter()
	local list: { Instance } = { followersFolder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function track(owner: Player)
	if followers[owner] then
		return
	end
	local f: Follower = { Player = owner, Kinds = "", Pets = {} }
	followers[owner] = f
	owner.CharacterAdded:Connect(function()
		task.defer(refreshFilter)
	end)
	if owner.Character then
		task.defer(refreshFilter)
	end
	owner:GetAttributeChangedSignal(GolemConfig.EquippedAttribute):Connect(function()
		local kinds = owner:GetAttribute(GolemConfig.EquippedAttribute)
		f.Kinds = if type(kinds) == "string" then kinds else ""
		-- shown ones change now; far ones are built when they come near (refreshVisibility)
		if #f.Pets > 0 then
			buildPets(f)
		end
	end)
	local kinds = owner:GetAttribute(GolemConfig.EquippedAttribute)
	f.Kinds = if type(kinds) == "string" then kinds else ""
end

local function untrack(owner: Player)
	local f = followers[owner]
	if f then
		clearPets(f)
		followers[owner] = nil
	end
	task.defer(refreshFilter)
end

-- Builds / removes followers by distance to the camera (every half second).
local function refreshVisibility()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.Focus.Position else Vector3.zero
	for owner, f in followers do
		local root = rootOf(owner)
		local distance = if root then (root.Position - eye).Magnitude else math.huge
		local want = f.Kinds ~= "" and distance <= GolemConfig.FollowerHideDistance
		local far = distance > GolemConfig.FollowerHideDistance + 10
		if want and #f.Pets == 0 then
			buildPets(f)
		elseif (far or f.Kinds == "" or not root) and #f.Pets > 0 then
			clearPets(f)
		end
	end
end

local function groundAt(position: Vector3, fromY: number): number?
	local hit = Workspace:Raycast(Vector3.new(position.X, fromY + 3, position.Z), Vector3.new(0, -14, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

local function stepPets(dt: number): boolean
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.Focus.Position else Vector3.zero
	for owner, f in followers do
		local root = if #f.Pets > 0 then rootOf(owner) else nil
		if root then
			local ownerCF = root.CFrame
			local feet = feetY(owner, root)
			local _, ownerYaw, _ = ownerCF:ToEulerAnglesYXZ()
			local near = (root.Position - eye).Magnitude <= GolemConfig.FollowerLodDistance
			for _, pet in f.Pets do
				local slot = GolemController.Slots[pet.Slot] or Vector3.zero
				local flatYaw = CFrame.new(ownerCF.Position) * CFrame.Angles(0, ownerYaw, 0)
				local target = (flatYaw * CFrame.new(slot)).Position
				-- the ground under the slot (raycast now and then), else the owner's feet
				if now >= pet.NextGround then
					pet.NextGround = now + GolemController.GroundSeconds + (pet.Seed % 0.1)
					pet.Ground = groundAt(target, root.Position.Y) or feet
				end
				local flat = Vector3.new(target.X - pet.Pos.X, 0, target.Z - pet.Pos.Z)
				local distance = flat.Magnitude
				local moved = 0
				if distance > GolemController.CatchUpDistance then
					pet.Pos = Vector3.new(target.X, pet.Ground, target.Z)
				else
					local step = flat * (1 - math.exp(-dt * 3.2))
					moved = step.Magnitude
					pet.Pos =
						Vector3.new(pet.Pos.X + step.X, pet.Pos.Y + (pet.Ground - pet.Pos.Y) * (1 - math.exp(-dt * 10)), pet.Pos.Z + step.Z)
				end
				local speed = moved / math.max(dt, 1e-3)
				local walking = speed > 0.8
				-- face where it walks; standing, the owner's way, now and then looking around
				if walking then
					pet.Look = 0
					pet.NextLook = now + GolemController.LookSeconds[1]
				elseif near and now >= pet.NextLook then
					local range = GolemController.LookSeconds
					pet.NextLook = now + range[1] + (range[2] - range[1]) * ((math.sin(now * 12.9898 + pet.Seed) + 1) / 2)
					pet.Look = if pet.Look ~= 0 then 0 else GolemController.LookAround * math.sin(now * 7.13 + pet.Seed * 3)
				end
				local wantYaw = if walking then math.atan2(-flat.X, -flat.Z) else ownerYaw + pet.Look
				pet.Yaw = lerpAngle(pet.Yaw, wantYaw, 1 - math.exp(-dt * (if walking then 9 else 3)))
				local y = pet.Pos.Y
				local pitch, roll = 0, 0
				if pet.Floats then
					-- glides on its aura: a slow bob, leaning into the glide
					local k = if walking then math.clamp(speed / 10, 0, 1) else 0
					if near then
						y += math.sin(now * 2.2 + pet.Seed) * 0.08
						pitch = -0.08 * k
					end
				elseif walking then
					pet.Phase += moved / GolemController.HopStride * math.pi
					local k = math.clamp(speed / 10, 0, 1)
					y += math.abs(math.sin(pet.Phase)) * 0.55 * k
					if near then
						pitch = -0.12 * k
						roll = math.sin(pet.Phase) * 0.08 * k
					end
				elseif near then
					y += math.sin(now * 2.2 + pet.Seed) * 0.05
				end
				pet.Root.CFrame = CFrame.new(pet.Pos.X, y + pet.RootHeight, pet.Pos.Z)
					* CFrame.Angles(0, pet.Yaw, 0)
					* CFrame.Angles(pitch, 0, roll)
			end
		end
	end
	return true
end

---------------------------------------------------------------- lifecycle

function GolemController.init()
	Net.listen("ActionResult", onActionResult)
	Net.listen("OpenUI", function(kind)
		if kind == "Golems" then
			GolemController.open()
		end
	end)
	StateController.onChanged(function()
		if shown then
			refresh()
			local view = refs
			if view then
				hookCards(view)
			end
		end
	end)
	player.CharacterRemoving:Connect(function()
		GolemController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and shown then
			updateHint(view)
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

-- P (keyboard) toggles the inventory; L1 (gamepad) too, but opens it only
-- while no other screen uses the selection or holds the controls.
local function onToggle(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if shown then
		GolemController.close()
		Sfx.play("UIClick")
		return Enum.ContextActionResult.Sink
	end
	local gamepad = input.KeyCode == GolemController.ToggleButton
	if (gamepad and GuiService.SelectedObject ~= nil) or PlayerControls.owner() ~= nil or CleaningController.isActive() then
		return Enum.ContextActionResult.Pass
	end
	GolemController.open()
	return Enum.ContextActionResult.Sink
end

-- The HUD button: 44 pt tall on phones, the toggle key or glyph in its corner.
local function updateMenu()
	local button = menuButton
	if not button then
		return
	end
	local input = if usingGamepad() then "Gamepad" elseif isTouch() then "Touch" else "Keyboard"
	local glyph = ""
	if input == "Gamepad" then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(GolemController.ToggleButton)
		end)
		glyph = if ok and type(image) == "string" then image else ""
	end
	GolemView.menuLayout(button, HudController.uiScale(), input, glyph)
end

function GolemController.start()
	-- the HUD's GOLEMS button
	local hud = HudController.refs()
	if hud and not menuButton then
		local button = GolemView.menuButton(hud.Menu, GolemController.ToggleKey.Name)
		menuButton = button
		button.Activated:Connect(function()
			if shown then
				GolemController.close()
			else
				GolemController.open()
			end
		end)
		UserInputService.LastInputTypeChanged:Connect(updateMenu)
		local scale = hud.Gui:FindFirstChild("Scale")
		if scale and scale:IsA("UIScale") then
			scale:GetPropertyChangedSignal("Scale"):Connect(updateMenu)
		end
		updateMenu()
	end
	ContextActionService:BindAction(TOGGLE_ACTION, onToggle, false, GolemController.ToggleKey, GolemController.ToggleButton)
	-- followers
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(stepPets, dt)
		if not ok then
			warn("[GolemController] followers: " .. tostring(err))
		end
	end)
	while true do
		refreshVisibility()
		task.wait(0.5)
	end
end

-- Pure follower math for the tests: the slot target of golem `slot` for an
-- owner at `ownerCF` (flattened to its yaw).
function GolemController.slotTarget(ownerCF: CFrame, slot: number): Vector3
	local _, yaw, _ = ownerCF:ToEulerAnglesYXZ()
	local flat = CFrame.new(ownerCF.Position) * CFrame.Angles(0, yaw, 0)
	return (flat * CFrame.new(GolemController.Slots[slot] or Vector3.zero)).Position
end

return GolemController
