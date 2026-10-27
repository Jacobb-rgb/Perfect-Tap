--[[
	SideMenuController: the button column on the left edge (SideMenuView;
	its entries are data: Group "Main" / "More", Order, IconName, shown by
	Group then Order).

	  GOLEMS     GolemController (hidden while it isn't in the game)
	  ELEVATOR   ElevatorController: a teleport to the mine elevator stop of
	             your floor (its open(); the floor picker then opens from the
	             stop's prompt); hidden while the world has no stop (its
	             available(): Workspace attribute TeleportConfig.ElevatorAttribute;
	             ElevatorController calls SideMenuController.refresh when it changes)
	  SHOP       BoostController (Triple / Hexa Lucky) when it is in the game,
	             else a hint to visit the SHOP stall
	  CODEX      CodexController (badge: ores discovered since you last looked)
	  ARTIFACTS  ArtifactController (the collection book; badge: completed
	             chapters waiting unread; hidden while it isn't in the game)
	  BOARDS     LeaderboardController (HALL OF FAME panel)
	  SETTINGS   SettingsController
	  STORE      StoreController (Robux items; hidden while it isn't in the
	             game, step 8)
	  HOVER      HoverboardController (the hoverboards panel; its RIDE button
	             and the H key stay in the HUD)
	  REBIRTH    RebirthController (STAR FORGE; badge: a rebirth is ready
	             and the window wasn't opened since)
	QUESTS     QuestController (daily / weekly quests + the login streak;
	             badge: quests and the streak day waiting to be claimed)

	Every other controller is called defensively (MenuPanels: required by
	name with pcall, its open / toggle / isOpen / close used when they
	exist), so the menu works before the packages that add them merge: a
	button whose controller is missing is hidden (GOLEMS, ARTIFACTS, STORE:
	no dead buttons), or answers with a hint (SHOP). (An entry with Soon and
	without Hide would wear a "SOON" chip and answer with a toast.) A
	controller with available() that returns false hides its button too
	(ELEVATOR without a stop). Pressing the button of an open panel closes
	it.
	One entry per panel: the side menu is THE entry for the panels it
	opens, so the controllers leave out their own HUD buttons while it is
	in the game (GolemController's GOLEMS, ArtifactController's BOOK) and
	the BOOSTS launcher chip is turned off (BoostController.setLauncher);
	hotkeys (P, L, J), world prompts and the boost chips stay.
	Layout: SideMenuView.layout (the left column has one order: coins,
	TRAIN chip, boost chips, then this menu, so nothing covers anything:
	mouse layouts start under the boost chips; touch screens
	(MenuPanels.isTouch, the same test the panels use) get one MENU button
	first in the train chip's row that opens the grid in the chips' place
	(the TRAIN chip and the boost chips hide while it is open:
	MenuPanels.setGridOpen, so it never covers them half-way) and keep the
	thumbstick's bottom-left corner free; TVs keep the title-safe
	margin and get bigger texts). The touch grid shuts again when a button runs, after
	AutoShut seconds without a tap, when the gamepad selection leaves it or
	when the HUD hides.
	Input: click / tap; gamepad: D-pad Left jumps into the column (its glyph
	shows over the menu while a gamepad is used; the touch grid opens), the
	D-pad moves, A opens, B leaves; D-pad Left leaves from the first column
	only (in a grid it moves left). The menu hides whenever the HUD's own
	menu is hidden (build mode, the cleaning minigame, the crate opening),
	and the side menu's own panels (CODEX, SETTINGS, HALL OF FAME) close then.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SideMenuView = require(script.Parent.Parent.UI.SideMenuView)
local HudBubble = require(script.Parent.Parent.UI.HudBubble)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)

local SideMenuController = {}

type Action = { Controller: string?, Missing: string, Soon: boolean, Hide: boolean }

-- What each button does: the controller it opens and the toast when that
-- controller isn't in the game (Soon = show the SOON chip then; Hide = hide
-- the button then).
SideMenuController.Actions = {
	Shop = {
		Controller = "BoostController",
		Missing = "Visit the SHOP stall in town for gear and luck boosts!",
		Soon = false,
		Hide = false,
	},
	Golems = { Controller = "GolemController", Missing = "Golem pets are coming soon!", Soon = false, Hide = true },
	Codex = { Controller = "CodexController", Missing = "The Ore Codex is at the ROCK SCANNER in town.", Soon = false, Hide = false },
	Collection = { Controller = "ArtifactController", Missing = "The artifact collection book is coming soon!", Soon = false, Hide = true },
	Boards = {
		Controller = "LeaderboardController",
		Missing = "The leaderboards are in the HALL OF FAME in town.",
		Soon = false,
		Hide = false,
	},
	Settings = { Controller = "SettingsController", Missing = "Settings are coming soon!", Soon = false, Hide = false },
	-- a teleport to the elevator stop (hidden while the world has none: ElevatorController.available)
	Elevator = { Controller = "ElevatorController", Missing = "The mine elevator isn't open yet.", Soon = false, Hide = true },
	Hoverboards = { Controller = "HoverboardController", Missing = "Hoverboards are coming soon!", Soon = false, Hide = true },
	-- hidden until step 8's StoreController is in the game (no dead buttons); it comes back by itself
	Store = { Controller = "StoreController", Missing = "The Robux store is coming soon!", Soon = true, Hide = true },
	Rebirth = { Controller = "RebirthController", Missing = "Rebirth is coming soon!", Soon = false, Hide = true },
	Quests = { Controller = "QuestController", Missing = "Quests are coming soon!", Soon = false, Hide = true },
} :: { [string]: Action }

-- Buttons whose controller has onUnseenChanged(callback(count)): its count
-- is the button's badge.
SideMenuController.Badges = { "Codex", "Collection", "Rebirth", "Quests" }

-- The side menu's own panels: they close when the HUD hides (build mode,
-- the cleaning minigame...), like the menu itself.
SideMenuController.Panels = {
	"CodexController",
	"SettingsController",
	"LeaderboardController",
	"ElevatorController",
	"HoverboardController",
	"QuestController",
}
-- the touch grid shuts by itself after this many seconds without a tap
SideMenuController.AutoShut = 10

local JUMP_ACTION = "TerraForgeSideMenuJump"
local LEAVE_ACTION = "TerraForgeSideMenuLeave"
local LEAVE_PRIORITY = Enum.ContextActionPriority.High.Value + 5

local player = Players.LocalPlayer
local refs: SideMenuView.Refs? = nil
-- the light UI (the HUD's menu is the light tile grid): id -> the light tile's
-- button; the side menu's own column stays hidden and the tiles mirror it
local light: { [string]: TextButton }? = nil
local hudVisible = true
local leaveBound = false
local shutToken = 0

function SideMenuController.refs(): SideMenuView.Refs?
	return refs
end

-- Is `object` one of the light UI's menu tiles (the HUD's tile grid or its MORE flyout)?
local function inLightMenu(object: GuiObject?): boolean
	local hud = if light and object then HudController.refs() else nil
	if not hud or not object then
		return false
	end
	local flyout = (hud.Menu.Parent :: Instance):FindFirstChild("MoreFlyout")
	return object:IsDescendantOf(hud.Menu) or (flyout ~= nil and object:IsDescendantOf(flyout))
end

local function inMenu(object: GuiObject?): boolean
	local view = refs
	return object ~= nil and view ~= nil and (object:IsDescendantOf(view.Column) or inLightMenu(object))
end

-- Opens or shuts the touch layout's grid (no-op on other layouts). An open
-- grid shuts by itself after AutoShut seconds unless the gamepad
-- selection is in it.
function SideMenuController.setExpanded(on: boolean)
	local view = refs
	if not view then
		return
	end
	local layout = view.Layout
	if not layout or not layout.Toggle then
		on = false
	end
	if view.Expanded ~= on then
		SideMenuView.setExpanded(view, on)
		-- a gamepad selection on a button that just hid goes back to MENU
		local selected = GuiService.SelectedObject
		if not on and layout and layout.Toggle and selected and inMenu(selected) and selected ~= view.Toggle then
			GuiService.SelectedObject = view.Toggle
		end
	end
	-- the TRAIN chip and the boost chips hide while the grid is open in their place
	MenuPanels.setGridOpen(view.Expanded == true)
	shutToken += 1
	if on then
		local token = shutToken
		task.delay(SideMenuController.AutoShut, function()
			if token == shutToken and not inMenu(GuiService.SelectedObject) then
				SideMenuController.setExpanded(false)
			end
		end)
	end
end

-- Runs a button: toggles its panel, or answers with the toast (the touch
-- grid shuts). Returns what happened ("Opened" | "Closed" | "Missing").
function SideMenuController.press(id: string): string
	local action = SideMenuController.Actions[id]
	if not action then
		return "Missing"
	end
	SideMenuController.setExpanded(false)
	local name = action.Controller
	local controller = if name then MenuPanels.controller(name) else nil
	if name and controller then
		if MenuPanels.isOpen(name) and MenuPanels.call(name, "close") then
			return "Closed"
		end
		if MenuPanels.call(name, "open") or MenuPanels.call(name, "toggle") then
			return "Opened"
		end
	end
	HudController.toast(action.Missing, "Info")
	return "Missing"
end

local function firstButton(view: SideMenuView.Refs): TextButton
	local shown = SideMenuView.shown(view)
	return view.Buttons[shown[1] or view.Order[1]]
end

local function leave()
	if inMenu(GuiService.SelectedObject) then
		GuiService.SelectedObject = nil
	end
	local hud = if light then HudController.refs() else nil
	if hud then
		HudBubble.toggleMore(hud.Menu, false)
	end
	SideMenuController.setExpanded(false)
end

local function onLeave(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not inMenu(GuiService.SelectedObject) then
		return Enum.ContextActionResult.Pass
	end
	leave()
	return Enum.ContextActionResult.Sink
end

-- B leaves the menu while the selection is in it (bound only then, so B
-- keeps its other jobs the rest of the time).
local function updateLeave()
	local want = inMenu(GuiService.SelectedObject)
	if want and not leaveBound then
		leaveBound = true
		ContextActionService:BindActionAtPriority(LEAVE_ACTION, onLeave, false, LEAVE_PRIORITY, Enum.KeyCode.ButtonB)
	elseif not want and leaveBound then
		leaveBound = false
		ContextActionService:UnbindAction(LEAVE_ACTION)
	end
end

local function onJump(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	local view = refs
	if light and state == Enum.UserInputState.Begin and inLightMenu(GuiService.SelectedObject) then
		-- the light UI: D-pad Left from a tile in the grid's left column leaves the menu
		-- (further right, or in the MORE flyout, it moves left as usual; B leaves from anywhere)
		local selected = GuiService.SelectedObject :: GuiObject
		local hud = HudController.refs()
		if not hud or not selected:IsDescendantOf(hud.Menu) then
			return Enum.ContextActionResult.Pass
		end
		local columns = (hud.Menu:GetAttribute("Columns") :: number?) or 2
		for i, face in HudBubble.linkMenu(hud.Menu) do
			if (selected == face or selected:IsDescendantOf(face)) and (i - 1) % columns ~= 0 then
				return Enum.ContextActionResult.Pass
			end
		end
		leave()
		return Enum.ContextActionResult.Sink
	end
	if light and state == Enum.UserInputState.Begin and GuiService.SelectedObject == nil then
		-- the light UI: D-pad Left jumps onto the first light tile (not while the HUD is hidden:
		-- the cleaning minigame, the crate opening)
		local hud = HudController.refs()
		local faces = if hud and hudVisible then HudBubble.linkMenu(hud.Menu) else {}
		if faces[1] then
			GuiService.SelectedObject = faces[1]
			Sfx.play("UIClick")
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	if state ~= Enum.UserInputState.Begin or not view or not view.Gui.Enabled then
		return Enum.ContextActionResult.Pass
	end
	local selected = GuiService.SelectedObject
	if selected and inMenu(selected) then
		-- from the first column it leaves; further right it moves left in the grid
		local layout = view.Layout
		local cell = SideMenuView.cellOf(view, selected)
		if layout and cell and cell % layout.Columns ~= 0 then
			return Enum.ContextActionResult.Pass
		end
		leave()
		return Enum.ContextActionResult.Sink
	end
	-- another panel owns the selection: leave it alone
	if selected ~= nil then
		return Enum.ContextActionResult.Pass
	end
	SideMenuController.setExpanded(true)
	GuiService.SelectedObject = firstButton(view)
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

local function relayout()
	local view = refs
	if not view then
		return
	end
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local scale = HudController.uiScale()
	local inset = GuiService:GetGuiInset()
	local layout = SideMenuView.layout(scale, (size.Y - inset.Y) / scale, {
		Count = #SideMenuView.shown(view),
		Touch = MenuPanels.isTouch(),
		TenFoot = GuiService:IsTenFootInterface(),
		DesignWidth = size.X / scale,
	})
	if not layout.Toggle then
		-- (a mouse layout has no grid to shut; a later touch layout starts shut)
		view.Expanded = false
		MenuPanels.setGridOpen(false)
	end
	SideMenuView.apply(view, layout)
end

local function updateGlyph()
	local view = refs
	if not view then
		return
	end
	local gamepad = MenuPanels.usingGamepad()
	local image = if gamepad then MenuPanels.glyph(Enum.KeyCode.DPadLeft) else ""
	view.PadGlyph.Visible = gamepad and image ~= ""
	view.PadGlyph.Image = image
end

-- The light tiles follow the side menu's state: hidden entries hide, the
-- badge counts show on the tiles (and the MORE tile adds up its flyout's).
local function mirrorLight()
	local view, tiles = refs, light
	local hud = HudController.refs()
	if not view or not tiles or not hud then
		return
	end
	local more = 0
	for _, entry in SideMenuView.Entries do
		local face = tiles[entry.Id]
		if face then
			local hidden = view.Hidden[entry.Id] == true
			if entry.Group == "Main" then
				HudBubble.setTileVisible(hud.Menu, entry.Id, not hidden)
			else
				local holder = face.Parent :: Frame
				holder.Visible = not hidden
			end
			local count = if hidden then 0 else (view.Counts[entry.Id] or 0)
			HudBubble.setTileBadge(face, count)
			if entry.Group == "More" then
				more += count
			end
		end
	end
	local moreTile = hud.Menu:FindFirstChild("More")
	local moreFace = moreTile and moreTile:FindFirstChild("Face") :: GuiObject?
	if moreFace then
		HudBubble.setTileBadge(moreFace, more)
	end
end

-- The light UI: the entries become tiles of the HUD's light menu ("Main") and
-- of its MORE flyout ("More"); they press the same actions.
local function buildLight(view: SideMenuView.Refs)
	local hud = HudController.refs()
	if not hud or not hud.Menu:GetAttribute("Bubble") then
		return
	end
	-- the MORE flyout opens over the TRAIN / boost chips' row: they hide meanwhile
	HudBubble.onMoreToggled = function(open: boolean)
		MenuPanels.setGridOpen(open)
	end
	view.Gui.Enabled = false
	local tiles: { [string]: TextButton } = {}
	for _, entry in SideMenuView.sorted() do
		local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
		local face = if entry.Group == "Main"
			then HudBubble.claimTile(hud.Menu, entry.Id, spec)
			else HudBubble.addMore(hud.Menu, entry.Id, spec)
		face.Activated:Connect(function()
			Sfx.play("UIClick")
			if entry.Group == "More" then
				HudBubble.toggleMore(hud.Menu, false)
			end
			SideMenuController.press(entry.Id)
		end)
		tiles[entry.Id] = face
	end
	light = tiles
	mirrorLight()
end

-- Is a controller's feature there right now? (available() when it has one,
-- e.g. ElevatorController: false while the world has no elevator stop)
local function unavailable(controller: any): boolean
	if type(controller) ~= "table" or type(controller.available) ~= "function" then
		return false
	end
	local ok, there = pcall(controller.available)
	return ok and there == false
end

-- Buttons whose controller isn't in the game: hidden, or a SOON chip; and
-- buttons whose controller says it isn't available: hidden.
local function updateSoon()
	local view = refs
	if not view then
		return
	end
	local changed = false
	for id, action in SideMenuController.Actions do
		local controller = if action.Controller then MenuPanels.controller(action.Controller) else nil
		local missing = controller == nil
		SideMenuView.setSoon(view, id, action.Soon and missing)
		local hide = (action.Hide and missing) or unavailable(controller)
		if (view.Hidden[id] == true) ~= hide then
			SideMenuView.setHidden(view, id, hide)
			changed = true
		end
	end
	if changed then
		relayout()
	end
	mirrorLight()
end

-- Re-checks which buttons show (a controller's available() changed: the
-- elevator stop appeared or went).
function SideMenuController.refresh()
	updateSoon()
end

-- The menu follows the HUD's own right-side menu (hidden in build mode,
-- the cleaning minigame...).
local function followHud()
	local hud = HudController.refs()
	local view = refs
	if not hud or not view then
		return
	end
	local visible = hud.Gui.Enabled and hud.Menu.Visible
	if visible ~= hudVisible then
		hudVisible = visible
		view.Gui.Enabled = visible and light == nil -- (the light tiles live in the HUD itself)
		if light and not visible then
			HudBubble.toggleMore(hud.Menu, false)
		end
		if not visible then
			leave()
			SideMenuController.setExpanded(false)
			for _, name in SideMenuController.Panels do
				if MenuPanels.isOpen(name) then
					MenuPanels.call(name, "close")
				end
			end
		end
	end
end

function SideMenuController.init()
	local view = SideMenuView.build()
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	refs = view
	for id, button in view.Buttons do
		button.Activated:Connect(function()
			Sfx.play("UIClick")
			SideMenuController.press(id)
		end)
	end
	view.Toggle.Activated:Connect(function()
		Sfx.play("UIClick")
		local open = not view.Expanded
		SideMenuController.setExpanded(open)
		local selected = GuiService.SelectedObject
		if open and selected and selected == view.Toggle then
			-- a gamepad press on MENU: on to the first button
			GuiService.SelectedObject = firstButton(view)
		end
	end)
	relayout()
	buildLight(view)
end

function SideMenuController.start()
	local view = refs
	if not view then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	ContextActionService:BindAction(JUMP_ACTION, onJump, false, Enum.KeyCode.DPadLeft)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(updateLeave)
	UserInputService.LastInputTypeChanged:Connect(updateGlyph)
	updateGlyph()
	updateSoon()
	-- controllers that load late (or a codex discovery count) update the chips
	task.delay(5, updateSoon)
	for _, id in SideMenuController.Badges do
		local action = SideMenuController.Actions[id]
		local controller = if action and action.Controller then MenuPanels.controller(action.Controller) else nil
		if controller and type(controller.onUnseenChanged) == "function" then
			controller.onUnseenChanged(function(count: number)
				local current = refs
				if current then
					SideMenuView.setBadge(current, id, count)
					mirrorLight()
				end
			end)
		end
	end
	-- SHOP opens the luck boosts: the boost chips' own BOOSTS launcher would
	-- be a second entry
	local shop = SideMenuController.Actions.Shop.Controller
	if shop then
		MenuPanels.call(shop, "setLauncher", false)
	end
	local hud = HudController.refs()
	if hud then
		hud.Gui:GetPropertyChangedSignal("Enabled"):Connect(followHud)
		hud.Menu:GetPropertyChangedSignal("Visible"):Connect(followHud)
		followHud()
	end
end

return SideMenuController
