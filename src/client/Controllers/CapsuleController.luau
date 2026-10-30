--[[
	CapsuleController: golem capsules on the client (step 7).

	- The eggs in the EGGS temple open from their own "Buy Egg!" prompts,
	  their panels' Open 1 / 3 / 10 and Auto (EggPanelController, owner
	  2026-10-28): CapsuleController.buy runs the same request as OPEN 1 /
	  3 / 10 below, with the odds the egg's panel shows, and the same
	  opening plays. buy(), quote(),
	  luckyShown(), openingState(), onStop() and setAuto() are for it.
	- The shop panel (CapsuleView, every egg with x1 / x3 / x10 and every
	  golem's name) opens from the golem inventory's EGGS button
	  (CapsuleController.open) and on OpenUI "Capsules" (an egg's own podium
	  out in the world, the SKY EGG's; the temple's old "Capsules" prompt is
	  off: CapsuleService.StallPrompt). Opening works anywhere, so the panel
	  doesn't close when you walk away.
	  Tabs (click / tap, LB / RB): the capsules this player may open. The
	  cards come from the State snapshot and update live (coins count up,
	  the Triple Lucky banner counts down).
	- The panel and the opening are built for the layout of the moment
	  (phone / TV compact or PC) and laid out again, text sizes included,
	  when the screen changes.
	- OPEN x1 / x3 / x10 sends CapsuleAction ("Open", { Capsule, Count,
	  Lucky }): Lucky = the odds the card shows (CapsuleView.luckyNow); the
	  server rolls exactly those or refuses "OddsChanged".
	  One open waits at a time; CapsuleConfig.ClientCooldown seconds between
	  two; the buttons come back after CapsuleConfig.ResultTimeout with no
	  answer (a CapsuleResult that still comes is shown anyway: the coins and
	  golems on screen always come from the State push). A greyed-out button
	  answers locally (not enough coins, no room) and sends nothing. Royal
	  capsules (Robux): a button per product that is live (a real id and
	  step 8's receipts ready: the ReplicatedStorage attribute
	  CapsuleView.ReceiptsAttribute), the others greyed "Coming soon"; the
	  server answers PurchasePrompt ("Full" reads: the golem inventory is
	  full, delete some golems first).
	- CapsuleResult plays the opening (owner 2026-10-29, the clicker-sim
	  video: "open them exactly like there, this clean, glowing by rarity";
	  docs/plans/CLICKER_VIDEO_2026-10-29.md section 1; UI/HatchFx holds the
	  flow, the timings and the maths, CapsuleView the pieces): the world stays
	  (softly blurred: a BlurEffect on the camera, nothing dims it), the HUD
	  steps away but the opening's Auto button (hideHud: scale 0, the touch
	  FIRE and Grab held), the eggs pop in HUGE in front of the camera (1 in
	  the middle, 3 side by side, the middle one bigger, 10 in two rows of 5),
	  wobble, white rings and a puff, their cracks glow in the colour of the
	  golem inside each (BrightTheme.crackColour, Mythic a moving rainbow) in
	  three steps, soft blobs of the best colour behind; a Legendary / Mythic
	  gets a suspense (brighter cracks, a harder shake) and stands centred,
	  bigger; each egg turns into a glowing silhouette and bursts: ONE flash
	  in the best colour (RevealKit.takeFlash: never sooner than FlashGap
	  after the last), shell pieces; the golems stand where their eggs were,
	  HUGE and SOLID (nothing see-through over them: the flash and the
	  sunburst sit under the stage) on a soft white sunburst with a little
	  confetti, each with its NAME and "1 in N" (the odds it was rolled at);
	  a bob, then they spin and fly to the player and the HUD comes back. A
	  click / tap (on touch off the thumbstick's zone) / Space / Enter / A
	  skips a step, Backspace / B skips to the end; every golem still shows
	  at least HatchFx.MinShow, named (paid random items). Auto plays the fast
	  timings (about 2 s) and opens the next egg at once; G (B while it runs)
	  or the Auto button toggles it; Reduce motion gets the calm version
	  (fades, no shake, rings, flash or spin). A result of more than 10
	  golems (a x50 limited Robux pack: paid random items show each result)
	  plays as consecutive openings of 10 (batches: "2 / 5" at the top, the
	  later ones in the fast timings, MinShow in each; a skip finishes the
	  opening it is in, never the next), including a pack's golems past the
	  inventory's hard cap (the result's Pending: shown won, "Waiting:
	  inventory full" under the name). The openings in a row are ONE chain:
	  the HUD hold, the blur, the keys and the selection lock carry across
	  them and come back once, after the last; a result that arrives
	  meanwhile (a new receipt) waits after the whole chain. While it plays
	  every prompt is suppressed ("CapsuleOpening"). Refusals stop Auto
	  (onStop with the reason).
- The CapsuleStall's OddsBoard (SurfaceGui) shows the real odds per
	  rarity: every BoardSeconds the next capsule the player may open (with
	  the player's own Triple Lucky odds, refreshed within a second when it
	  starts or ends), filled locally by CapsuleView.fillBoard as soon as
	  the board streams in.
	- Closes with X, B, Backspace, respawning or another panel opening
	  (OTHER_PANELS: every panel controller known so far, also those of
	  the step 6-7 packages; missing ones are skipped).
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local PromptConfig = require(Shared.Config.PromptConfig)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local CapsuleView = require(script.Parent.Parent.UI.CapsuleView)
local TechShopView = require(script.Parent.Parent.UI.TechShopView)
local HatchFx = require(script.Parent.Parent.UI.HatchFx)
local HatchStage = require(script.Parent.Parent.UI.HatchStage)
local RevealKit = require(script.Parent.Parent.Effects.RevealKit)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)

local CapsuleController = {}

type Panel = { isOpen: () -> boolean, close: () -> () }
-- (a golem Deleted: auto-deleted by the player's trash icon, Id 0, not kept: it shows greyed and stays;
-- Waiting: won past the inventory's hard cap, Id 0, in the pending credit: it shows won, with a note)
export type Golem = { Id: number, Kind: string, Deleted: boolean?, Waiting: boolean? }
-- One opening: a whole result, or batch `Batch` of `Batches` of a big one (at most Batch golems each).
export type Result = {
	Capsule: string,
	Count: number,
	Golems: { Golem },
	Lucky: boolean,
	Free: boolean?,
	Batch: number?,
	Batches: number?,
	Arrived: number?, -- os.clock() its result came (its first opening)
	Note: string?, -- a notice that came with it (a receipt's own "inventory full"): shown with its opening
}

CapsuleController.Batch = 10 -- the most golems one opening shows (CapsuleView.StageTags): a x50 is 5 openings
CapsuleController.RebuyGuard = 0.5 -- seconds after an opening ends the shop's OPEN buttons rest (A mashed to skip)
CapsuleController.BoardSeconds = 6 -- seconds each capsule's odds stay on the stall's board
CapsuleController.BoardTick = 1 -- seconds between two checks of the board (Triple Lucky starting / ending)
CapsuleController.BoardPixels = 120 -- the board's SurfaceGui PixelsPerStud (sharper text)

local CLOSE_ACTION = "TerraForgeCapsulesClose"
local TAB_ACTION = "TerraForgeCapsulesTab"
local SKIP_ACTION = "TerraForgeCapsuleSkip"
local SKIP_ALL_ACTION = "TerraForgeCapsuleSkipAll"
local AUTO_ACTION = "TerraForgeCapsuleAuto"
local STALL_TAG = "CapsuleStall"
local PODIUM_TAG = "EggPodium" -- an egg on its own podium (CapsuleService.PodiumTag)
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local OPEN_PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- the overlay is above every panel
local TICK = 0.25
local STATUS_TIME = 3.5
-- the other panels (one in the middle of the screen at a time): MenuPanels.Names,
-- the one list of every panel controller (a name that isn't in the game is skipped)

local player = Players.LocalPlayer
local refs: CapsuleView.Refs? = nil
local shown = false
local cards: { CapsuleView.Card } = {}
local tickConnection: RBXScriptConnection? = nil
local pendingUntil = 0
local pendingButton: TextButton? = nil
local lastSend = 0
local statusToken = 0
local openedAt = 0
local others: { Panel }? = nil
local stateAt: number? = nil -- server time the last State snapshot came (CapsuleView.luckyNow)

-- the opening
local opening: CapsuleView.OpenRefs? = nil
local eggPool: { [string]: { HatchFx.Record } } = {} -- capsule id (and crack steps) -> its eggs, built once
local playing = false
local queue: { Result } = {}
local skipStep = false
local skipAll = false
local autoOn = false -- the temple's Auto runs (setAuto: the fast timings, the Auto button on)
local autoNote: string? = nil -- why Auto stopped, while an opening is up (setAuto: by the Auto button)
type AutoHookRef = { available: () -> boolean, toggle: () -> () }
local autoHook: AutoHookRef? = nil -- what the opening's Auto button does (EggPanelController)
local stopListeners: { (string) -> () } = {}

function CapsuleController.isOpen(): boolean
	return shown
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Paid random items are restricted for this player, or the policy isn't known yet.
local function restricted(): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function otherPanels(): { Panel }
	local cached = others
	if cached then
		return cached
	end
	local list: { Panel } = {}
	for _, name in MenuPanels.Names do
		if name == "CapsuleController" then
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

-- A gamepad button's name on this platform ("A" / "Cross").
local function padName(key: Enum.KeyCode): string
	local name = string.gsub(UserInputService:GetStringForKeyCode(key), "^Button", "")
	if name == "" then
		name = string.gsub(key.Name, "^Button", "")
	end
	return name
end

---------------------------------------------------------------- the shop panel

local function status(text: string, color: Color3?)
	local view = refs
	if not view then
		return
	end
	CapsuleView.setStatus(view, text, color)
	statusToken += 1
	local token = statusToken
	task.delay(STATUS_TIME, function()
		local current = refs
		if statusToken == token and current then
			CapsuleView.setStatus(current, nil, nil)
		end
	end)
end

local function updateHint(view: CapsuleView.Refs)
	local sep = CapsuleView.Separator
	if usingGamepad() then
		CapsuleView.setHint(
			view,
			`{padName(Enum.KeyCode.ButtonL1)} / {padName(Enum.KeyCode.ButtonR1)}: capsule{sep}{padName(Enum.KeyCode.ButtonA)}: open{sep}{padName(
				Enum.KeyCode.ButtonB
			)}: close`
		)
	elseif isTouch() then
		CapsuleView.setHint(view, "Tap OPEN to wake golems")
	else
		CapsuleView.setHint(view, `Click OPEN to wake golems{sep}Backspace: close`)
	end
	local gamepad = usingGamepad()
	for i, image in view.TabGlyphs do
		image.Visible = gamepad
		if gamepad then
			image.Image = UserInputService:GetImageForKeyCode(if i == 1 then Enum.KeyCode.ButtonL1 else Enum.KeyCode.ButtonR1)
		end
	end
end

-- Phones and TVs get the compact layout (the same rule as the tech shop).
local function compactNow(): boolean
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return TechShopView.compactFor(isTouch(), GuiService:IsTenFootInterface(), HudController.uiScale(), size.Y)
end

-- The screen in design units (the HUD's scale, under the top bar).
local function room(): (number, number)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return size.X / scale, (size.Y - inset.Y) / scale
end

-- (layout sets every size and text size, so a layout change needs no rebuild)
local function fit(view: CapsuleView.Refs)
	local w, h = room()
	CapsuleView.layout(view, compactNow(), w, h)
end

-- Step 8's receipts take Royal capsules (set by CapsuleService.setReceiptsReady).
local function receiptsReady(): boolean
	return ReplicatedStorage:GetAttribute(CapsuleView.ReceiptsAttribute) == true
end

-- Every card as the player sees it now.
-- the podium-only egg the panel was opened at (OpenUI payload.Capsule), or nil:
-- a podium-only egg (CapsuleConfig Podium) shows its tab only then
local atPodium: string? = nil

local function currentCards(coins: number): { CapsuleView.Card }
	local list = CapsuleView.cards(StateController.get(), coins, restricted(), serverNow(), stateAt, receiptsReady())
	for _, card in list do
		local capsule = CapsuleConfig.ById[card.Id]
		if capsule and capsule.Podium and atPodium ~= card.Id then
			card.Visible = false
		end
	end
	return list
end

-- The Triple Lucky odds the cards show now.
local function luckyShown(): boolean
	return CapsuleView.luckyNow(StateController.get(), serverNow(), stateAt)
end

-- The same for the egg panels (EggPanelController): the odds every open sends.
function CapsuleController.luckyShown(): boolean
	return luckyShown()
end

-- One capsule's card as the window would show it now (its price at the
-- player's level, whether it can be bought and why not, its odds): the egg
-- panel's quote. nil when it isn't sold to this player here.
function CapsuleController.quote(capsuleId: string): CapsuleView.Card?
	for _, card in currentCards(HudController.predictedCoins(os.clock())) do
		if card.Id == capsuleId then
			return card
		end
	end
	return nil
end

local function refresh()
	local view = refs
	if not view or not shown then
		return
	end
	local coins = HudController.predictedCoins(os.clock())
	cards = currentCards(coins)
	CapsuleView.setCoins(view, coins)
	CapsuleView.setCards(view, cards)
end

local function cardOf(id: string): CapsuleView.Card?
	for _, card in cards do
		if card.Id == id then
			return card
		end
	end
	return nil
end

local function freeButton()
	local button = pendingButton
	pendingButton = nil
	pendingUntil = 0
	if button then
		button:SetAttribute("Busy", false)
	end
	refresh()
end

--[[
	Sends an open (from the panel, OPEN AGAIN or an egg's prompt). Returns
	whether it was sent and, when not, why: "Busy" (an open waits for its
	answer), "Cooldown" (ClientCooldown), "Hidden" (not sold to this
	player here), "OddsChanged" (`expectLucky`: the odds the egg's panel
	showed are no longer the card's) or the buy's own Reason (NoCoins,
	InventoryFull, ComingSoon).
]]
local chainEndedAt = -math.huge -- os.clock() when the last chain of openings ended

-- Did a chain of openings end less than RebuyGuard ago? (A tap or an A meant to skip it lands on
-- a buy button then: the window's OPEN, the egg panel's opens, Auto and trash rest that long.)
function CapsuleController.justEnded(): boolean
	return os.clock() - chainEndedAt < CapsuleController.RebuyGuard
end
local function request(capsuleId: string, count: number, button: TextButton?, expectLucky: boolean?): (boolean, string?)
	local now = os.clock()
	if button and now - chainEndedAt < CapsuleController.RebuyGuard then
		-- (an A or a tap pressed to skip the opening that just ended: never another egg; a real click says why)
		status("One moment...", Theme.Info)
		return false, "Busy"
	end
	if now < pendingUntil then
		status("Opening... one moment", Theme.Info)
		return false, "Busy"
	end
	if now - lastSend < CapsuleConfig.ClientCooldown then
		status("One moment...", Theme.Info)
		return false, "Cooldown"
	end
	local coins = HudController.predictedCoins(now)
	cards = currentCards(coins)
	local card = cardOf(capsuleId)
	local buy: CapsuleView.Buy? = nil
	if card then
		for _, b in card.Buys do
			if b.Count == count then
				buy = b
			end
		end
	end
	if not card or not card.Visible or not buy then
		return false, "Hidden"
	end
	if not buy.CanBuy then
		status(CapsuleView.reasonText(buy.Reason), Theme.Bad)
		Sfx.play("UIDeny")
		return false, buy.Reason
	end
	if expectLucky ~= nil and card.Lucky ~= expectLucky then
		status(CapsuleView.reasonText("OddsChanged"), Theme.Bad)
		Sfx.play("UIDeny")
		return false, "OddsChanged"
	end
	pendingUntil = now + CapsuleConfig.ResultTimeout
	lastSend = now
	pendingButton = button
	if button then
		button:SetAttribute("Busy", true)
		button.Text = "..."
	end
	Sfx.play("UIClick")
	-- the odds this card shows: the server rolls exactly these (or refuses)
	Net.send("CapsuleAction", "Open", { Capsule = capsuleId, Count = count, Lucky = card.Lucky })
	return true, nil
end

--[[
	The EGGS temple's "Buy Egg!", Open 1 / 3 / 10 and Auto
	(EggPanelController): opens `count` eggs (CapsuleConfig.Counts) through
	request() (the cooldown, the local refusals, the server's CapsuleAction
	"Open" and the opening: one egg, a row of 3, a grid of 10), with the
	odds the egg's panel shows (`lucky`; refused "OddsChanged" when the
	card's differ now). The capsule window is shut there, so a refusal is a
	toast; `quiet` (Auto) skips the toast for a "one moment" wait. Returns
	whether it was sent and request()'s reason.
]]
function CapsuleController.buy(capsuleId: string, count: number, lucky: boolean, quiet: boolean?): (boolean, string?)
	local sent, reason = request(capsuleId, count, nil, lucky)
	if not sent and not shown and reason ~= "Hidden" then
		local busy = reason == "Busy" or reason == "Cooldown"
		if not (busy and quiet) then
			HudController.toast(if busy then "One moment..." else CapsuleView.reasonText(reason), if busy then "Info" else "Deny")
		end
	end
	return sent, reason
end

local function switchTab(dir: number)
	local view = refs
	if not view then
		return
	end
	local tabs = CapsuleView.visibleTabs(cards)
	if #tabs < 2 then
		return
	end
	local index = table.find(tabs, view.Tab) or 1
	view.Tab = tabs[(index - 1 + dir) % #tabs + 1]
	refresh()
	Sfx.play("UIClick")
	if usingGamepad() then
		GuiService.SelectedObject = CapsuleView.firstButton(view)
	end
end

function CapsuleController.close()
	if not shown then
		return
	end
	shown = false
	atPodium = nil
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
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("Capsules", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not shown or playing then
		return Enum.ContextActionResult.Pass
	end
	CapsuleController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function onTab(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not shown or playing then
		return Enum.ContextActionResult.Pass
	end
	switchTab(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
	return Enum.ContextActionResult.Sink
end

local function openGolems()
	local module = script.Parent:FindFirstChild("GolemController")
	if module and module:IsA("ModuleScript") then
		local ok, controller = pcall(require, module :: any)
		local golems = controller :: any
		if ok and type(golems) == "table" and type(golems.open) == "function" then
			CapsuleController.close()
			golems.open()
		end
	end
end

local function ensureView(): CapsuleView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = CapsuleView.build(compactNow())
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	-- (while the opening plays the shop behind it does nothing)
	view.Close.Activated:Connect(function()
		if playing then
			return
		end
		CapsuleController.close()
		Sfx.play("UIClick")
	end)
	view.Golems.Activated:Connect(function()
		if playing then
			return
		end
		Sfx.play("UIClick")
		openGolems()
	end)
	for id, tab in view.Tabs do
		tab.Activated:Connect(function()
			if view.Tab ~= id and not playing then
				view.Tab = id
				refresh()
				Sfx.play("UIClick")
			end
		end)
	end
	for i, button in view.Buttons do
		button.Activated:Connect(function()
			if button:GetAttribute("Busy") == true or playing then
				return
			end
			request(view.Tab, CapsuleConfig.Counts[i], button)
		end)
	end
	refs = view
	return view
end

local function watch()
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		if pendingUntil > 0 and os.clock() > pendingUntil then
			freeButton()
			status("No answer yet: if it went through, your golems show up in MY GOLEMS", Theme.Bad)
		end
		if os.clock() - openedAt > 0.3 then
			for _, panel in otherPanels() do
				if panel.isOpen() then
					CapsuleController.close()
					return
				end
			end
		end
		refresh()
	end)
end

-- Opens the shop panel (from the stall's prompt or another screen).
function CapsuleController.open()
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
	fit(view)
	updateHint(view)
	view.Gui.Enabled = true
	PromptController.setSuppressed("Capsules", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(TAB_ACTION, onTab, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	watch()
	refresh()
	if usingGamepad() then
		GuiService.SelectedObject = CapsuleView.firstButton(view)
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

---------------------------------------------------------------- the opening

-- Tells the Auto listeners (onStop) why it must stop: a refusal's reason.
local function stopped(reason: string)
	for _, listener in stopListeners do
		local ok, err = pcall(function(): any
			listener(reason)
			return nil
		end)
		if not ok then
			warn("[CapsuleController] stop listener failed: " .. tostring(err))
		end
	end
end

-- Auto (EggPanelController) stops on these: the server refused an open (its reason code).
function CapsuleController.onStop(listener: (string) -> ())
	table.insert(stopListeners, listener)
end

local playingListeners: { (boolean) -> () } = {}
-- An opening starts (true) or the last one ends (false): the egg panel steps aside meanwhile.
function CapsuleController.onPlaying(listener: (boolean) -> ())
	table.insert(playingListeners, listener)
end

local function tellPlaying(on: boolean)
	for _, listener in playingListeners do
		local ok, err = pcall(function(): any
			listener(on)
			return nil
		end)
		if not ok then
			warn("[CapsuleController] playing listener failed: " .. tostring(err))
		end
	end
end

-- Is an opening on the screen (one plays, or another result waits its turn)? Its Auto note can show there.
function CapsuleController.showing(): boolean
	return playing
end

--[[
	Where the opening is, for Auto: "Waiting" (an open was sent, no answer
	yet), "Playing" (an opening plays, or another result waits its turn)
	or "Idle" (it ended: the golems flew to the player, the HUD is back).
]]
function CapsuleController.openingState(): (string, number)
	if pendingUntil > os.clock() then
		return "Waiting", 0
	elseif playing or #queue > 0 then
		return "Playing", 0
	end
	return "Idle", 0
end

-- The Auto key on the opening's button: G on a keyboard, the gamepad's B while Auto runs (B stops it), none on touch.
local function autoKey(): (string, string?)
	local keys = PromptConfig.keys("Second")
	if usingGamepad() then
		if not autoOn then
			return "", nil -- (B is skip-all while Auto is off: it never turns Auto on)
		end
		local image = UserInputService:GetImageForKeyCode(keys.Gamepad)
		return if image ~= "" then "" else padName(keys.Gamepad), if image ~= "" then image else nil
	elseif isTouch() then
		return "", nil
	end
	return keys.Keyboard.Name, nil
end

-- The Auto button: shown where Auto can run (the egg the player stands at, a coin egg) or while it runs.
local currentRun: HatchStage.Run? = nil -- the opening on the stage now (hatch)
local function refreshAuto(o: CapsuleView.OpenRefs)
	local hook = autoHook
	local available = hook ~= nil and (autoOn or hook.available())
	local text, glyph = autoKey()
	local was = o.AutoHolder.Visible
	CapsuleView.setAuto(o, available, autoOn, text, glyph)
	local run = currentRun
	if run and was ~= o.AutoHolder.Visible then
		HatchStage.retag(run) -- (the names step aside for the Auto button only while it shows)
	end
end

local noteToken = 0
-- A short note by the Auto button (the HUD's toasts hide while an opening plays).
local function showNote(o: CapsuleView.OpenRefs, text: string?)
	noteToken += 1
	local token = noteToken
	o.Note.Text = text or ""
	o.Note.Visible = text ~= nil and text ~= ""
	if text then
		task.delay(STATUS_TIME, function()
			if noteToken == token then
				o.Note.Visible = false
			end
		end)
	end
end

--[[
	Auto runs (EggPanelController): the opening's Auto button shows it on,
	the next egg opens as soon as one ends, in the fast timings. Off with a
	`note` (the odds changed under it): the note shows by the Auto button
	while an opening is up.
]]
function CapsuleController.setAuto(on: boolean, note: string?)
	autoOn = on
	local o = opening
	if o and playing then
		-- (shown now, once: the next opening of the chain doesn't show it again)
		autoNote = nil
		refreshAuto(o)
		if note and not on then
			showNote(o, note)
		end
	else
		autoNote = if on then nil else note -- (the next opening shows it)
	end
end

--[[
	The egg panel's trash icon: auto-delete golems of `kind` from now on
	(`on`) or not. CapsuleTrash, its own remote and rate limit (quick
	toggles never take an Open's token; the server checks the kind and the
	cap; the State push shows the change, a refusal is a toast).
]]
function CapsuleController.setAutoDelete(kind: string, on: boolean)
	Net.send("CapsuleTrash", { Kind = kind, On = on })
end

--[[
	What the opening's Auto button does (EggPanelController sets it): is
	Auto possible here (`available`), and `toggle` it for the egg the player
	stands at.
]]
export type AutoHook = { available: () -> boolean, toggle: () -> () }
function CapsuleController.setAutoHook(hook: AutoHook?)
	autoHook = hook
end

--[[
	`count` eggs of a capsule from the pool (built once with the opening's
	crack network: HatchFx.addCracks; put back whole: HatchFx.reset).
	`cracks`: the last crack step built (a phone opening many eggs: 2).
]]
local function takeEggs(capsuleId: string, count: number, cracks: number): { HatchFx.Record }
	local key = `{capsuleId}|{cracks}`
	local list = eggPool[key]
	if not list then
		list = {}
		eggPool[key] = list
	end
	local pool = list :: { HatchFx.Record }
	while #pool < count do
		local model = GolemBuilder.capsule(capsuleId)
		HatchFx.addCracks(model, cracks)
		model:SetAttribute("Pooled", true)
		table.insert(pool, HatchFx.record(model))
	end
	local out: { HatchFx.Record } = {}
	for i = 1, count do
		HatchFx.reset(pool[i])
		table.insert(out, pool[i])
	end
	return out
end

-- A golem's model for the stage: its height, the pivot's height over its feet.
local function golemModel(kind: string): (Model, number, number)
	local model = GolemBuilder.build(kind)
	local height = (model:GetAttribute("Height") :: number?) or 3
	local rootHeight = (model:GetAttribute("RootHeight") :: number?) or 1
	return model, height, rootHeight
end

---------------------------------------------------------------- the HUD steps away

--[[
	While an opening plays the HUD hides, except the opening's Auto button
	(the video: only Auto Open stays): every TerraForge ScreenGui with the
	HUD's "Scale" goes to scale 0 (no Enabled is touched: the windows and
	chips keep their own state; a Scale written meanwhile is kept and put
	back), the touch FIRE and Grab step aside (MiningController.hold,
	InteractController.hold); the egg panel steps aside itself
	(EggPanelController reads showing()). Not hidden: guis that aren't the
	game's own (Roblox's: the thumbstick, the chat),
	the fades of a teleport. Back when the last opening ends.
]]
type Hidden = { Scale: UIScale, Wanted: number, Connection: RBXScriptConnection }
local hiddenGuis: { [Instance]: Hidden } = {}
local hudHidden = false
local addedConnection: RBXScriptConnection? = nil
local HOLD_NAME = "CapsuleOpening"

local function holdControllers(on: boolean)
	for _, name in { "MiningController", "InteractController", "BoostController" } do
		local module = script.Parent:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, controller = pcall(require, module :: any)
			local c = controller :: any
			if ok and type(c) == "table" and type(c.hold) == "function" then
				pcall(c.hold, HOLD_NAME, on)
			end
		end
	end
end

local function hideGui(gui: Instance)
	local o = opening
	if hiddenGuis[gui] or not gui:IsA("ScreenGui") or string.sub(gui.Name, 1, 10) ~= "TerraForge" then
		return
	end
	if o and (gui == o.Gui or gui == o.Controls) then
		return
	end
	local scale = gui:FindFirstChild("Scale")
	if not scale or not scale:IsA("UIScale") then
		return -- (the fades and flying bits without the HUD's scale finish as they are)
	end
	local entry: Hidden = { Scale = scale, Wanted = scale.Scale, Connection = nil :: any }
	hiddenGuis[gui] = entry
	scale.Scale = 0
	entry.Connection = scale:GetPropertyChangedSignal("Scale"):Connect(function()
		if scale.Scale ~= 0 then
			entry.Wanted = scale.Scale -- (the HUD's scale changed: kept for later)
			scale.Scale = 0
		end
	end)
end

local function hideHud(on: boolean)
	if on == hudHidden then
		return
	end
	hudHidden = on
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if on then
		if playerGui then
			for _, gui in playerGui:GetChildren() do
				hideGui(gui)
			end
			addedConnection = playerGui.ChildAdded:Connect(function(gui: Instance)
				task.defer(function()
					if hudHidden and gui.Parent then
						hideGui(gui)
					end
				end)
			end)
		end
		-- (a gamepad selection on a hidden button would press it unseen)
		local selected = GuiService.SelectedObject
		if selected then
			for gui in hiddenGuis do
				if selected:IsDescendantOf(gui) then
					GuiService.SelectedObject = nil
				end
			end
		end
	else
		if addedConnection then
			addedConnection:Disconnect()
			addedConnection = nil
		end
		for _, entry in hiddenGuis do
			entry.Connection:Disconnect()
			-- (a scale written meanwhile wins: the watcher may not have seen the last write)
			local now = entry.Scale.Scale
			entry.Scale.Scale = if now ~= 0 then now else entry.Wanted
		end
		table.clear(hiddenGuis)
	end
	if on then
		holdControllers(true)
	else
		-- (a moment later: the HUD's frames measure again once its scale is back, so the boost
		-- corner, placed on its release, lands right; a new opening meanwhile keeps the holds)
		task.delay(0.05, function()
			if not hudHidden then
				holdControllers(false)
			end
		end)
	end
end

-- The world behind softly blurred while an opening plays (a client BlurEffect on the camera).
CapsuleController.BlurSize = 10
local blur: BlurEffect? = nil
local function setBlur(on: boolean)
	local camera = Workspace.CurrentCamera
	if on then
		if not camera then
			return -- (no camera this moment: the next opening of the chain puts it on)
		end
		local made = blur
		if not made or made.Parent ~= camera then
			if made then
				made:Destroy()
			end
			local effect = Instance.new("BlurEffect")
			effect.Name = "TerraForgeOpeningBlur"
			effect.Size = 0
			effect.Parent = camera
			blur = effect
			made = effect
		end
		TweenService:Create(made :: BlurEffect, TweenInfo.new(0.2), { Size = CapsuleController.BlurSize }):Play()
	elseif blur then
		local effect = blur :: BlurEffect
		blur = nil
		local tween = TweenService:Create(effect, TweenInfo.new(0.25), { Size = 0 })
		tween.Completed:Connect(function()
			effect:Destroy()
		end)
		tween:Play()
	end
end

---------------------------------------------------------------- the play

-- While an opening plays nothing is selected: a window's key (L1, R1, the D-pad) that opens a
-- window under the opening (scale 0) would leave a gamepad's A on a button nobody sees.
local selectionWatch: RBXScriptConnection? = nil
local function keepNoSelection(on: boolean)
	if selectionWatch then
		selectionWatch:Disconnect()
		selectionWatch = nil
	end
	if not on then
		return
	end
	GuiService.SelectedObject = nil
	selectionWatch = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		if playing and GuiService.SelectedObject ~= nil then
			task.defer(function()
				if playing then
					GuiService.SelectedObject = nil
				end
			end)
		end
	end)
end

-- The window keys, sunk while an opening plays (A, B, G, Space, Enter and Backspace are the
-- opening's own): a gamepad's (L3 opens the train window, R3 asks and confirms the tutorial's
-- Skip) and their keyboard twins (T the train, B build mode, and the keys other controllers own
-- and export, read from them: the backpack's, the emotes', the golems', the hoverboard's, the
-- book's, the boosts'): none acts unseen under it.
local SINK_ACTION = "TerraForgeCapsuleSink"
local SINK_KEYS = {
	Enum.KeyCode.T,
	Enum.KeyCode.B,
	Enum.KeyCode.ButtonL1,
	Enum.KeyCode.ButtonR1,
	Enum.KeyCode.ButtonL2,
	Enum.KeyCode.ButtonR2,
	Enum.KeyCode.ButtonL3,
	Enum.KeyCode.ButtonR3,
	Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY,
	Enum.KeyCode.DPadUp,
	Enum.KeyCode.DPadDown,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
}
-- (controller name, its exported key or list of keys: those keys are theirs alone, never named here)
local OWNED_KEYS = {
	{ "BackpackController", "Key" },
	{ "EmoteController", "Key" },
	{ "GolemController", "ToggleKey" },
	{ "HoverboardController", "Key" },
	{ "ArtifactController", "BookKey" },
	{ "BoostController", "OpenKeys" },
}

CapsuleController.OwnedKeys = OWNED_KEYS

local owners: { [string]: any }? = nil -- (the specs' stand-ins for those controllers: _test.setOwners)
local warnedOwner: { [string]: boolean } = {}

-- Every key sunk under an opening: the list above and the other controllers' own (one that exports
-- no key under its name is skipped, with a warning once: it would act unseen under an opening).
function CapsuleController.sinkKeys(): { Enum.KeyCode }
	local out = table.clone(SINK_KEYS)
	local function add(value: any): boolean
		local key: any = value
		if typeof(value) ~= "EnumItem" then
			return false
		end
		if not table.find(out, key) then
			table.insert(out, key)
		end
		return true
	end
	for _, entry in OWNED_KEYS do
		local controller: any = nil
		local stand = owners
		if stand then
			controller = stand[entry[1]]
		else
			local module = script.Parent:FindFirstChild(entry[1])
			if module and module:IsA("ModuleScript") then
				local ok, loaded = pcall(require, module :: any)
				controller = if ok then loaded else nil
			end
		end
		local value = if type(controller) == "table" then controller[entry[2]] else nil
		local found = false
		if type(value) == "table" then
			for _, key in value do
				found = add(key) or found
			end
		else
			found = add(value)
		end
		if not found and not warnedOwner[entry[1]] then
			warnedOwner[entry[1]] = true
			warn(`[CapsuleController] no {entry[1]}.{entry[2]} key to sink under an opening`)
		end
	end
	return out
end

local function onSink(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	return if playing then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

--[[
	The opening of a result (HatchFx, docs/plans/CLICKER_VIDEO_2026-10-29.md
	section 1): the eggs pop in huge in front of the camera, wobble, white
	rings and a puff, their cracks glow in the colour of the golem inside
	each, in steps, soft blobs of the best colour behind; a Legendary /
	Mythic's suspense; each egg a glowing silhouette, the burst, ONE flash
	in the best colour; the golems where their eggs were, huge and solid,
	on a soft white sunburst with a little confetti, their names and
	"1 in N"; a bob, then they spin and fly to the player. A tap (click,
	Space, Enter, A) skips a step, skip-all (Backspace, B) to the end; every
	golem always shows, named (HatchFx.MinShow: paid random items). Auto
	plays the fast timings, Reduce motion the calm ones.
]]
local stageGolems: { Model } = {} -- the golems of the opening that plays (freed when it ends)

-- The player's character on the screen (shares), where the golems fly; the bottom middle if it isn't seen.
local function playerOnScreen(): Vector2
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if camera and root and root:IsA("BasePart") then
		local point, inView = camera:WorldToViewportPoint(root.Position)
		local size = camera.ViewportSize
		if inView and size.X > 0 and size.Y > 0 then
			return Vector2.new(math.clamp(point.X / size.X, 0.25, 0.75), math.clamp(point.Y / size.Y, 0.55, 0.92))
		end
	end
	return Vector2.new(0.5, 0.86)
end

-- The sounds and the camera nudge of a run's events (HatchStage.pose).
local function onEvents(run: HatchStage.Run, events: { string })
	local reduced = run.Timeline.Reduced
	for _, event in events do
		if event == "Step1" or event == "Step2" or event == "Step3" then
			local step = tonumber(string.sub(event, 5)) or 1
			Sfx.play("NodeCrack", nil, 0.8 + 0.18 * step)
			if step == 1 and not reduced then
				Sfx.loop("CaseCharge", true)
			end
		elseif event == "Burst" then
			Sfx.loop("CaseCharge", false)
			Sfx.play("CaseBurst")
			if run.BestOrder >= 4 then
				Sfx.play("CaseBoom")
			end
			if run.BestOrder >= 5 and not reduced then
				CameraShake.add(if run.BestOrder >= 6 then 0.5 else 0.38)
			end
		elseif event == "Reveal" then
			if run.BestOrder >= 5 then
				Sfx.play("Discovery")
			end
			Sfx.play("Reveal", nil, 1 + 0.04 * math.min(run.BestOrder, 6))
			stageGolems = HatchStage.golems(run)
		elseif event == "Fly" and not reduced then
			Sfx.play("LevelWhoosh", nil, 1.1)
		elseif event == "End" and not reduced then
			Sfx.play("BagPop", nil, 1.2)
		end
	end
end

--[[
	Plays a result's opening (HatchStage poses it, frame by frame): a tap
	before the burst goes straight to it; a tap while the golems stand goes
	on to their flight once they showed MinShow (real time since they came
	out: it waits for that); skip-all does both.
]]
-- Which of an opening's golems were auto-deleted, and which won but wait for room (index -> true each).
function CapsuleController.marks(result: Result): ({ [number]: boolean }, { [number]: boolean })
	local deleted: { [number]: boolean } = {}
	local waiting: { [number]: boolean } = {}
	for i, g in result.Golems do
		if g.Deleted == true then
			deleted[i] = true
		elseif g.Waiting == true then
			waiting[i] = true
		end
	end
	return deleted, waiting
end

--[[
	The stage's arguments for one opening of `result` (its golems `kinds`):
	what hatch() plays and the specs pose (the marks, the timings: Auto's
	fast ones and a big pack's later openings, Reduce motion's calm ones,
	the eggs from the pool, RevealKit's flash gap).
]]
function CapsuleController.hatchArgs(o: CapsuleView.OpenRefs, result: Result, kinds: { string }): HatchStage.Args
	local n = math.clamp(#kinds, 1, CapsuleView.StageTags)
	local phone = compactNow()
	local deleted, waiting = CapsuleController.marks(result)
	return {
		Refs = o,
		Capsule = result.Capsule,
		Lucky = result.Lucky == true,
		Kinds = kinds,
		Deleted = deleted,
		Waiting = waiting,
		Eggs = takeEggs(result.Capsule, n, if phone and n > 3 then 2 else 3),
		-- (Auto's fast timings; a big pack's later openings too: the first one plays whole)
		Fast = autoOn or (result.Batch or 1) > 1,
		Reduced = Motion.reduced(),
		Phone = phone,
		Target = playerOnScreen(),
		Golem = golemModel,
		-- (RevealKit's one flash gap for every reveal; Reduce motion: none)
		Claim = function(): boolean
			return not Motion.reduced() and RevealKit.takeFlash(os.clock())
		end,
		Wait = function(): number
			return RevealKit.nextFlashAt() - os.clock()
		end,
	}
end

local function hatch(o: CapsuleView.OpenRefs, result: Result, kinds: { string })
	local run = HatchStage.new(CapsuleController.hatchArgs(o, result, kinds))
	currentRun = run
	local tl = run.Timeline
	if not tl.Reduced then
		Sfx.play("BagPop", nil, 0.9)
	end
	local start = os.clock()
	local offset = 0 -- (skips move the clock on)
	local revealedAt: number? = nil -- (os.clock() when the golems came out: MinShow counts from it)
	local wantFly = false -- (a skip asked for the flight: it waits for MinShow)
	while true do
		local now = os.clock()
		local shownFor = if revealedAt then now - revealedAt else 0
		if skipStep or skipAll then
			local t0 = now - start + offset
			local t1 = HatchFx.skipTo(t0, tl, shownFor)
			if t1 then
				offset += t1 - t0
			end
			if (t1 == nil or skipAll) and t0 < tl.Fly then
				wantFly = true
			end
			skipStep, skipAll = false, false
		end
		if wantFly then
			local t0 = now - start + offset
			local t1 = if t0 >= tl.Burst then HatchFx.skipTo(t0, tl, shownFor) else nil
			if t1 then
				offset += t1 - t0
				wantFly = false
			end
		end
		local t = math.min(now - start + offset, tl.Total)
		local events = HatchStage.pose(run, t)
		if table.find(events, "Reveal") then
			revealedAt = now
		end
		onEvents(run, events)
		if t >= tl.Total then
			break
		end
		task.wait()
	end
	currentRun = nil
	Sfx.loop("CaseCharge", false)
end

local function onSkip(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not playing then
		return Enum.ContextActionResult.Pass
	end
	skipStep = true
	return Enum.ContextActionResult.Sink
end

local function toggleAuto()
	local hook = autoHook
	if hook and (autoOn or hook.available()) then
		hook.toggle()
		local o = opening
		if o then
			refreshAuto(o)
		end
	end
end

-- B / Backspace: skip all; a gamepad's B while Auto runs stops Auto instead (its badge says so).
local function onSkipAll(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not playing then
		return Enum.ContextActionResult.Pass
	end
	if input.KeyCode == PromptConfig.keys("Second").Gamepad and autoOn then
		toggleAuto()
	else
		skipAll = true
	end
	return Enum.ContextActionResult.Sink
end

local function onAuto(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not playing then
		return Enum.ContextActionResult.Pass
	end
	toggleAuto()
	return Enum.ContextActionResult.Sink
end

local openingCompact: boolean? = nil -- the layout the opening was built for

-- The opening's screen: the whole screen in design units (the HUD's scale), Roblox's top bar row.
local function fitOpening(o: CapsuleView.OpenRefs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	for _, gui in { o.Gui, o.Controls } do
		local s = gui:FindFirstChild("Scale")
		if s and s:IsA("UIScale") then
			s.Scale = scale
		end
	end
	-- (what lies under the safe frame, a phone's home indicator: the Controls gui sits in that frame,
	-- CoreUISafeInsets; its Absolute* frame, as every gui's, starts under Roblox's top bar row)
	local safeBottom = 0
	pcall(function()
		local size = o.Controls.AbsoluteSize
		if size.Y > 0 then
			safeBottom = math.max(0, (view.Y - inset.Y) - (o.Controls.AbsolutePosition.Y + size.Y))
		end
	end)
	CapsuleView.layoutOpening(o, compactNow(), view.X / scale, view.Y / scale, {
		Touch = isTouch(),
		Inset = inset.Y / scale,
		SafeBottom = safeBottom / scale,
		TenFoot = GuiService:IsTenFootInterface(),
	})
end

local function ensureOpening(): CapsuleView.OpenRefs
	local compact = compactNow()
	local existing = opening
	if existing and openingCompact == compact then
		return existing
	end
	if existing then
		-- (only between two openings: play() calls this before it starts)
		existing.Gui:Destroy()
		existing.Controls:Destroy()
		opening = nil
	end
	openingCompact = compact
	local o = CapsuleView.buildOpening(compact)
	local playerGui = player:WaitForChild("PlayerGui")
	o.Gui.Parent = playerGui
	o.Controls.Parent = playerGui
	for _, tap in { o.Tap, o.TapTop } do
		tap.Activated:Connect(function()
			if playing then
				skipStep = true
			end
		end)
	end
	o.Auto.Activated:Connect(function()
		if playing then
			Sfx.play("UIClick")
			toggleAuto()
		end
	end)
	opening = o
	return o
end

--[[
	The chain: every opening queued plays one after another under ONE hold
	(beginChain .. endChain): the prompts suppressed, the HUD away, the
	blur, the keys and the selection lock carry across them (a x50 pack's 5
	openings, and a result that came meanwhile after them) and come back
	once, after the last opening, whatever happened (a failing opening, a
	death: the openings are ResetOnSpawn off and play on).
]]
local hatchOne = hatch -- (the specs swap in a recorder: _test.setHatch)

local function beginChain(o: CapsuleView.OpenRefs)
	playing = true
	-- (the keys never also fire a prompt behind it: an egg's Buy Egg! / Auto)
	PromptController.setSuppressed("CapsuleOpening", true)
	if not hudHidden then
		tellPlaying(true)
	end
	hideHud(true)
	setBlur(true)
	o.Gui.Enabled = true
	o.Controls.Enabled = true
	ContextActionService:BindActionAtPriority(
		SKIP_ACTION,
		onSkip,
		false,
		OPEN_PRIORITY,
		Enum.KeyCode.Space,
		Enum.KeyCode.Return,
		Enum.KeyCode.ButtonA
	)
	ContextActionService:BindActionAtPriority(
		SKIP_ALL_ACTION,
		onSkipAll,
		false,
		OPEN_PRIORITY,
		Enum.KeyCode.Backspace,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:BindActionAtPriority(AUTO_ACTION, onAuto, false, OPEN_PRIORITY, PromptConfig.keys("Second").Keyboard)
	ContextActionService:BindActionAtPriority(SINK_ACTION, onSink, false, OPEN_PRIORITY, table.unpack(CapsuleController.sinkKeys()))
	keepNoSelection(true)
end

local function endChain()
	ContextActionService:UnbindAction(SKIP_ACTION)
	ContextActionService:UnbindAction(SKIP_ALL_ACTION)
	ContextActionService:UnbindAction(AUTO_ACTION)
	ContextActionService:UnbindAction(SINK_ACTION)
	keepNoSelection(false)
	playing = false
	autoNote = nil
	local o = opening
	if o then
		o.Gui.Enabled = false
		o.Controls.Enabled = false
		CapsuleView.setChain(o, nil, nil)
	end
	setBlur(false)
	hideHud(false)
	tellPlaying(false)
	PromptController.setSuppressed("CapsuleOpening", false)
	chainEndedAt = os.clock()
	local view = refs
	if view and shown and usingGamepad() then
		GuiService.SelectedObject = CapsuleView.restButton(view) -- (never an OPEN button: A to skip must not buy)
	end
	pcall(Sfx.loop, "CaseCharge", false) -- (last: the HUD and the prompts never wait on a sound)
end

-- Plays one opening of the chain from start to end (a skip finishes this one only: the next plays whole).
local function play(result: Result)
	local o = ensureOpening() -- (the layout of the moment: rebuilt only between two openings)
	fitOpening(o)
	skipStep = false
	skipAll = false
	setBlur(true) -- (kept on: a new camera since the last opening gets it too)
	HatchStage.clear(o)
	refreshAuto(o)
	-- (its own notice, or why Auto stopped, once: a notice still showing from the last opening stays)
	if result.Note then
		showNote(o, result.Note)
	elseif autoNote then
		showNote(o, autoNote)
		autoNote = nil
	end
	CapsuleView.setChain(o, result.Batch, result.Batches)
	o.Gui.Enabled = true
	o.Controls.Enabled = true
	local kinds: { string } = {}
	for _, g in result.Golems do
		table.insert(kinds, g.Kind)
	end
	local ok, err = pcall(function()
		hatchOne(o, result, kinds)
	end)
	currentRun = nil -- (also after a failing one)
	if not ok then
		warn("[CapsuleController] opening failed: " .. tostring(err))
	end
	HatchStage.clear(o, stageGolems) -- (the golems destroyed, the eggs back in the pool: phones keep nothing)
	table.clear(stageGolems)
end

local function pump()
	if playing or #queue == 0 then
		return -- (the chain that plays takes it, after the ones before it)
	end
	local o = ensureOpening()
	fitOpening(o)
	beginChain(o)
	task.spawn(function()
		while #queue > 0 do
			local result = table.remove(queue, 1) :: Result
			play(result)
		end
		endChain()
	end)
end

--[[
	A CapsuleResult as the openings that show it (paid random items: a
	multi-open shows each result): its golems (the woken and the
	auto-deleted, then a Robux pack's Pending kinds, rolled past the
	inventory's hard cap: shown won, waiting), at most CapsuleConfig.MaxCount,
	cut into consecutive openings of Batch (a x50: 5). Junk is dropped
	(a Pending kind must be a known golem); none: nothing to play.
]]
function CapsuleController.batches(payload: any): { Result }
	if type(payload) ~= "table" or type(payload.Capsule) ~= "string" or type(payload.Golems) ~= "table" then
		return {}
	end
	local golems: { Golem } = {}
	local most = CapsuleConfig.MaxCount
	for _, g in payload.Golems do
		if #golems >= most then
			break
		end
		if type(g) == "table" and type(g.Id) == "number" and type(g.Kind) == "string" then
			table.insert(golems, { Id = g.Id, Kind = g.Kind, Deleted = if g.Deleted == true then true else nil })
		end
	end
	if type(payload.Pending) == "table" then
		for _, kind in payload.Pending do
			if #golems >= most then
				break
			end
			if type(kind) == "string" and GolemConfig.ById[kind] then
				table.insert(golems, { Id = 0, Kind = kind, Waiting = true })
			end
		end
	end
	local out: { Result } = {}
	local size = CapsuleController.Batch
	local count = math.ceil(#golems / size)
	for b = 1, count do
		local part: { Golem } = table.move(golems, (b - 1) * size + 1, math.min(b * size, #golems), 1, {})
		table.insert(out, {
			Capsule = payload.Capsule,
			Count = #part,
			Golems = part,
			Lucky = payload.Lucky == true,
			Free = payload.Free == true,
			Batch = b,
			Batches = count,
		})
	end
	return out
end

--[[
	A server notice while openings play (the HUD's toasts hide then): by
	the Auto button. One that comes right after a result still waiting in
	the queue (a receipt's own "your inventory is full") waits for that
	result's opening instead of landing on the one playing.
]]
CapsuleController.NoticeJoin = 1 -- seconds after its result a notice still belongs to it
local lastQueued: Result? = nil -- the first opening of the newest result queued (its notice joins it)
function CapsuleController.notice(message: any)
	local o = opening
	if not playing or not o or type(message) ~= "table" or type(message.Text) ~= "string" then
		return
	end
	local waiting = lastQueued
	-- (only a receipt's own kind of notice, "Info": another player's "woke a Legendary!" shows now)
	local joins = message.Kind == "Info" and waiting ~= nil and table.find(queue, waiting) ~= nil
	if waiting and joins and os.clock() - (waiting.Arrived or 0) < CapsuleController.NoticeJoin then
		waiting.Note = if waiting.Note then waiting.Note .. "  " .. message.Text else message.Text
		return
	end
	showNote(o, message.Text)
end

-- A CapsuleResult (also a late one, a wheel prize or a Robux receipt): its openings queue after
-- every one already queued (a chain that plays takes them on; else one starts).
local function onResult(payload: any)
	local openings = CapsuleController.batches(payload)
	if #openings == 0 then
		return
	end
	openings[1].Arrived = os.clock()
	lastQueued = openings[1]
	if pendingUntil > 0 or pendingButton then
		freeButton()
	end
	for _, result in openings do
		table.insert(queue, result)
	end
	pump()
end

local function onActionResult(payload: any)
	if type(payload) ~= "table" or payload.Action ~= "Capsule" then
		return
	end
	if payload.Op == "AutoDelete" then
		-- (the trash icon's answer: the State push shows it; a refusal says why)
		if payload.Ok ~= true then
			HudController.toast(CapsuleView.reasonText(payload.Reason), "Deny")
		end
		return
	end
	freeButton()
	if payload.Ok == true then
		return
	end
	local text = CapsuleView.reasonText(payload.Reason)
	stopped(if type(payload.Reason) == "string" then payload.Reason else "Refused")
	local o = opening
	if o and playing then
		showNote(o, text)
	end
	if shown then
		status(text, Theme.Bad)
		Sfx.play("UIDeny")
	elseif not playing then
		HudController.toast(text, "Deny")
	end
end

local function onPurchasePrompt(payload: any)
	if type(payload) ~= "table" or type(payload.Product) ~= "string" then
		return
	end
	local product = MonetizationConfig.get(payload.Product)
	if not product or not product.Capsule then
		return
	end
	freeButton()
	if payload.Status ~= "Prompted" then
		-- "Full" for a capsule: the golem inventory (and how to make room)
		local text = if payload.Status == "Full"
			then CapsuleView.reasonText("InventoryFull")
			else MonetizationConfig.StatusText[payload.Status] or "That isn't sold here."
		if shown then
			status(text, Theme.Info)
		else
			HudController.toast(text, "Info")
		end
	end
end

---------------------------------------------------------------- the stall's odds board

local boardPage = 0
local boardSeen: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local boardWatched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local boardQueued = false

-- The capsule the board shows now (cycles through those the player may open).
local function boardCapsule(): string?
	local list = {}
	for _, capsule in CapsuleConfig.Stall do
		if CapsuleView.visible(capsule.Id, restricted()) then
			table.insert(list, capsule.Id)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[boardPage % #list + 1]
end

local function updateBoards(): boolean
	local capsuleId = boardCapsule()
	if not capsuleId then
		return false
	end
	local lucky = luckyShown()
	local key = `{capsuleId}|{lucky}`
	-- an egg's own podium board always shows that egg (CapsuleService.hookPodium)
	for _, podium in CollectionService:GetTagged(PODIUM_TAG) do
		local holder = podium.Parent
		for _, board in if holder then holder:GetChildren() else {} do
			local own = board:GetAttribute("Capsule")
			local gui = if board.Name == "OddsBoard" then board:FindFirstChildWhichIsA("SurfaceGui") else nil
			if gui and type(own) == "string" and CapsuleConfig.ById[own] then
				local ownKey = `{own}|{lucky}`
				if boardSeen[gui] ~= ownKey then
					boardSeen[gui] = ownKey
					CapsuleView.fillBoard(gui, own, lucky)
				end
			end
		end
	end
	for _, stall in CollectionService:GetTagged(STALL_TAG) do
		local board = stall:FindFirstChild("OddsBoard", true)
		local gui = if board then board:FindFirstChildWhichIsA("SurfaceGui") else nil
		if gui and boardSeen[gui] ~= key then
			boardSeen[gui] = key
			gui.PixelsPerStud = CapsuleController.BoardPixels
			CapsuleView.fillBoard(gui, capsuleId, lucky)
		end
	end
	return true
end

-- One board update at the end of this frame (many parts may stream in at once).
local function queueBoards()
	if boardQueued then
		return
	end
	boardQueued = true
	task.defer(function()
		boardQueued = false
		local ok, err = pcall(updateBoards)
		if not ok then
			warn("[CapsuleController] odds board: " .. tostring(err))
		end
	end)
end

-- A stall streams in part by part: fill its board the moment it arrives
-- (not at the next tick), and again if an old label arrives after that.
local function watchStall(stall: Instance)
	if boardWatched[stall] then
		return
	end
	boardWatched[stall] = true
	stall.DescendantAdded:Connect(function(d: Instance)
		local gui = if d:IsA("SurfaceGui") then d else d:FindFirstAncestorWhichIsA("SurfaceGui")
		if not gui or d:GetAttribute(CapsuleView.BoardAttribute) == true then
			return
		end
		local board = gui.Parent
		if board and board.Name == "OddsBoard" then
			boardSeen[gui] = nil
			queueBoards()
		end
	end)
end

---------------------------------------------------------------- lifecycle

-- The Lune specs (tests/EggPanel.spec.luau, tests/EggRedo.spec.luau) drive these, on fakes.
CapsuleController._test = {
	close = function()
		playing, autoOn, autoNote = false, false, nil
		pendingUntil, lastSend = 0, -math.huge
	end,
	request = request,
	setAuto = CapsuleController.setAuto, -- (the real ones: the specs swap the module's for recorders)
	setAutoHook = CapsuleController.setAutoHook,
	opening = function(): CapsuleView.OpenRefs
		local o = ensureOpening()
		fitOpening(o)
		return o
	end,
	refreshAuto = function()
		local o = opening
		if o then
			refreshAuto(o)
		end
	end,
	hideHud = hideHud,
	onSkipAll = onSkipAll,
	setPlaying = function(on: boolean)
		playing = on
	end,
	-- the chain (tests/EggOpening.spec.luau): a result in, the openings it plays (a recorder for the hatch)
	result = function(payload: any)
		onResult(payload)
	end,
	setHatch = function(fn: ((CapsuleView.OpenRefs, Result, { string }) -> ())?)
		hatchOne = fn or hatch
	end,
	hudHidden = function(): boolean
		return hudHidden
	end,
	queued = function(): number
		return #queue
	end,
	playing = function(): boolean
		return playing
	end,
	skips = function(): (boolean, boolean)
		return skipStep, skipAll
	end,
	setOwners = function(map: { [string]: any }?)
		owners = map
	end,
	view = function(): CapsuleView.Refs
		return ensureView()
	end,
	ended = function(at: number?)
		chainEndedAt = at or -math.huge
	end,
	selectionWatched = function(): boolean
		return selectionWatch ~= nil
	end,
	onPlaying = CapsuleController.onPlaying, -- (the real one: the egg panel's specs swap the module's)
}

function CapsuleController.init()
	Net.listen("OpenUI", function(kind, payload)
		if kind == "Capsules" then
			-- an egg's own podium opens the panel on that egg's tab
			local capsuleId = if type(payload) == "table" then payload.Capsule else nil
			if type(capsuleId) == "string" and CapsuleConfig.ById[capsuleId] then
				ensureView().Tab = capsuleId
				atPodium = capsuleId
			else
				atPodium = nil
			end
			CapsuleController.open()
		end
	end)
	Net.listen("CapsuleResult", onResult)
	-- (the HUD's toasts hide under an opening: a notice then shows by its Auto button)
	Net.listen("Notify", function(message: any)
		CapsuleController.notice(message)
	end)
	Net.listen("ActionResult", onActionResult)
	Net.listen("PurchasePrompt", onPurchasePrompt)
	if StateController.get() then
		stateAt = serverNow()
	end
	StateController.onChanged(function()
		stateAt = serverNow()
		if shown then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(function()
		if shown then
			refresh()
		end
		table.clear(boardSeen)
		queueBoards()
	end)
	ReplicatedStorage:GetAttributeChangedSignal(CapsuleView.ReceiptsAttribute):Connect(function()
		if shown then
			refresh()
		end
	end)
	player.CharacterRemoving:Connect(function()
		CapsuleController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and shown then
			updateHint(view)
		end
		local o = opening
		if o and playing then
			refreshAuto(o)
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and shown then
				fit(view)
			end
			local o = opening
			if o and playing then
				fitOpening(o)
			end
		end)
	end
end

function CapsuleController.start()
	-- the stall's odds board: the next capsule every BoardSeconds, the
	-- Triple Lucky odds within BoardTick, and at once when it streams in
	for _, stall in CollectionService:GetTagged(STALL_TAG) do
		watchStall(stall)
	end
	CollectionService:GetInstanceAddedSignal(STALL_TAG):Connect(function(stall: Instance)
		watchStall(stall)
		queueBoards()
	end)
	local pageAt = os.clock()
	while true do
		local ok, err = pcall(updateBoards)
		if not ok then
			warn("[CapsuleController] odds board: " .. tostring(err))
		end
		task.wait(CapsuleController.BoardTick)
		if os.clock() - pageAt >= CapsuleController.BoardSeconds then
			pageAt = os.clock()
			boardPage += 1
		end
	end
end

return CapsuleController
