--[[
	SideMenuController: the button column on the left edge (SideMenuView).

	  SHOP       BoostController (Triple / Hexa Lucky) when it is in the game,
	             else a hint to visit the SHOP stall
	  GOLEMS     GolemController
	  CODEX      CodexController (badge: ores discovered since you last looked)
	  ARTIFACTS  ArtifactController (the collection book)
	  BOARDS     LeaderboardController (HALL OF FAME panel)
	  SETTINGS   SettingsController
	  STORE      StoreController (Robux items) when it is in the game, else
	             "Coming soon"

	Every other controller is called defensively (MenuPanels: required by
	name with pcall, its open / toggle / isOpen / close used when they
	exist), so the menu works before the packages that add them merge; a
	button whose controller is missing wears a "SOON" chip and answers with
	a toast. Pressing the button of an open panel closes it.
	Input: click / tap; gamepad: D-pad Left jumps into the column (its glyph
	shows over the menu while a gamepad is used), the D-pad moves, A opens,
	B or D-pad Left again leaves. The menu hides whenever the HUD's own menu
	is hidden (build mode, the cleaning minigame, the Foundry moment).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SideMenuView = require(script.Parent.Parent.UI.SideMenuView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local HudController = require(script.Parent.HudController)

local SideMenuController = {}

type Action = { Controller: string?, Missing: string, Soon: boolean }

-- What each button does: the controller it opens and the toast when that
-- controller isn't in the game (Soon = show the SOON chip then).
SideMenuController.Actions = {
	Shop = { Controller = "BoostController", Missing = "Visit the SHOP stall in town for gear and luck boosts!", Soon = false },
	Golems = { Controller = "GolemController", Missing = "Golem pets are coming soon!", Soon = true },
	Codex = { Controller = "CodexController", Missing = "The Ore Codex is at the ROCK SCANNER in town.", Soon = false },
	Collection = { Controller = "ArtifactController", Missing = "The artifact collection book is coming soon!", Soon = true },
	Boards = { Controller = "LeaderboardController", Missing = "The leaderboards are in the HALL OF FAME in town.", Soon = false },
	Settings = { Controller = "SettingsController", Missing = "Settings are coming soon!", Soon = true },
	Store = { Controller = "StoreController", Missing = "The Robux store is coming soon!", Soon = true },
} :: { [string]: Action }

local JUMP_ACTION = "TerraForgeSideMenuJump"
local LEAVE_ACTION = "TerraForgeSideMenuLeave"
local LEAVE_PRIORITY = Enum.ContextActionPriority.High.Value + 5

local player = Players.LocalPlayer
local refs: SideMenuView.Refs? = nil
local hudVisible = true
local leaveBound = false

function SideMenuController.refs(): SideMenuView.Refs?
	return refs
end

-- Runs a button: toggles its panel, or answers with the toast. Returns
-- what happened ("Opened" | "Closed" | "Missing").
function SideMenuController.press(id: string): string
	local action = SideMenuController.Actions[id]
	if not action then
		return "Missing"
	end
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

local function inMenu(object: GuiObject?): boolean
	local view = refs
	return object ~= nil and view ~= nil and object:IsDescendantOf(view.Column)
end

local function firstButton(view: SideMenuView.Refs): TextButton
	return view.Buttons[view.Order[1]]
end

local function leave()
	if inMenu(GuiService.SelectedObject) then
		GuiService.SelectedObject = nil
	end
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
	if state ~= Enum.UserInputState.Begin or not view or not view.Gui.Enabled then
		return Enum.ContextActionResult.Pass
	end
	if inMenu(GuiService.SelectedObject) then
		leave()
		return Enum.ContextActionResult.Sink
	end
	-- another panel owns the selection: leave it alone
	local selected = GuiService.SelectedObject
	if selected ~= nil then
		return Enum.ContextActionResult.Pass
	end
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
	SideMenuView.apply(view, SideMenuView.layout(scale, (size.Y - inset.Y) / scale))
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

-- The SOON chips: buttons whose controller isn't in the game.
local function updateSoon()
	local view = refs
	if not view then
		return
	end
	for id, action in SideMenuController.Actions do
		local missing = action.Controller == nil or MenuPanels.controller(action.Controller) == nil
		SideMenuView.setSoon(view, id, action.Soon and missing)
	end
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
		view.Gui.Enabled = visible
		if not visible then
			leave()
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
	relayout()
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
	local codex = MenuPanels.controller("CodexController")
	if codex and type(codex.onUnseenChanged) == "function" then
		codex.onUnseenChanged(function(count: number)
			local current = refs
			if current then
				SideMenuView.setBadge(current, "Codex", count)
			end
		end)
	end
	local hud = HudController.refs()
	if hud then
		hud.Gui:GetPropertyChangedSignal("Enabled"):Connect(followHud)
		hud.Menu:GetPropertyChangedSignal("Visible"):Connect(followHud)
		followHud()
	end
end

return SideMenuController
