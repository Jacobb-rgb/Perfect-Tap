--[[
	UIMotionController: puts UI/Motion on the game's UI by itself, so the
	other controllers don't need edits.

	The switch: Config/AnimConfig.UIMotion (owner 2026-10-21: built, off until
	he says yes). Off, start() returns at once: no PlayerGui watcher, no
	Enabled watchers, no input hooks, no loop, nothing attached (it costs
	nothing; tests/UIMotion.spec.luau counts the connections). On, all of
	the below.

	- Windows: every PlayerGui ScreenGui with the attribute TerraForge is
	  watched; when its Enabled turns true (checked a moment later, after the
	  controller that opened it is done), its main window pops (findWindow:
	  the biggest top-level Frame named Window / Panel / Group / Fit, else the
	  biggest big Frame; a full-screen holder is looked into) and its dim
	  backdrop fades in (findDim). Left alone: the HUD (TerraForgeHud), the
	  HUD-like guis in Skip, guis with the attribute MotionSkip, and windows
	  that animate themselves (an "OpenPop" UIScale anywhere in the gui, any
	  other UIScale on the window, or a Motion.pop of their own just now).
	  A gui that hides: its animations jump to their end (Motion.settle).
	- Buttons (pressKind): the Pop kit's painted buttons (Pop.button, price,
	  close, pill, tile, card, check: a "Paint" gradient and a "Border"
	  stroke) and the old kit's chunky TextButtons named "Button" get
	  Motion.press + Motion.hover, once each, from PlayerGui.DescendantAdded
	  (batched into one deferred pass; never a scan per frame). Not in
	  BillboardGuis / SurfaceGuis (the world); the attribute Motion = "None"
	  opts a button out.
	- Attributes a view can set (read once, when the thing is added):
	    Motion = "Breathe"  Motion.breathe (the shop's BEST VALUE ribbons,
	                        the FEATURED banner's red x50 button)
	    Motion = "Shine"    Motion.shine (the shop's green price buttons;
	                        neighbours get staggered phases)
	    Motion = "PopIn"    Motion.popIn each time it turns Visible (the
	                        wheel's YOU WON card)
	- Input: hover grows only while the mouse is the last input (Motion.
	  setPointer); the gamepad's selection grows like a hover and its A
	  button squashes the selected button; touch squashes on the finger.
	- Reduce motion: the SETTINGS toggle (SettingsConfig.ReduceMotion) and
	  Roblox's own GuiService.ReducedMotionEnabled -> Motion.setReduced /
	  setSystemReduced. The windows that pop themselves (their own OpenPop
	  tween) and the chips' endless "Pulse" tweens are stilled too
	  (Motion.calm): in every gui that opens while it is on, and in the whole
	  PlayerGui the moment it turns on.
	- Loops (breathe, shine) run only while their gui shows: re-checked when
	  a watched gui opens or closes and once a second while there are loops.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Motion = require(script.Parent.Parent.UI.Motion)

local UIMotionController = {}

-- HUD-like guis (chips, bars, minigames, scripted openings): never popped as a window
UIMotionController.Skip = {
	TerraForgeHud = true,
	TerraForgeBlaster = true,
	TerraForgeBuild = true,
	TerraForgeTutorial = true,
	TerraForgeCleaning = true,
	TerraForgeFreeSpin = true,
	TerraForgeBoostChips = true,
	TerraForgeTrain = true,
	TerraForgeSideMenu = true,
	TerraForgeArtifactBanner = true,
	TerraForgeCrateOpening = true,
	TerraForgeCapsuleOpen = true,
	TerraForgeRebirthMoment = true,
	TerraForgeForge = true,
} :: { [string]: boolean }

UIMotionController.WindowNames = { Window = true, Panel = true, Group = true, Fit = true } :: { [string]: boolean }
UIMotionController.MinWindow = Vector2.new(240, 160) -- design units: smaller frames aren't windows
UIMotionController.FullScreen = 0.97 -- a frame this much of its parent both ways is a holder / backdrop

---------------------------------------------------------------- pure finders (tests)

local function isFrame(child: Instance): boolean
	return child:IsA("Frame") or child:IsA("CanvasGroup") or child:IsA("ScrollingFrame") or child:IsA("ImageLabel")
end

-- A child's size in its parent (`parent` design units).
local function sizeIn(gui: GuiObject, parent: Vector2): Vector2
	local size = gui.Size
	return Vector2.new(size.X.Scale * parent.X + size.X.Offset, size.Y.Scale * parent.Y + size.Y.Offset)
end

local function fullScreen(size: Vector2, parent: Vector2): boolean
	local k = UIMotionController.FullScreen
	return size.X >= parent.X * k and size.Y >= parent.Y * k
end

local function hasGuiChildren(gui: Instance): boolean
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			return true
		end
	end
	return false
end

--[[
	The main window of `gui` on a `screen`-sized screen (design units): the
	biggest visible top-level Frame named Window / Panel / Group / Fit, else
	the biggest one that is at least MinWindow; a full-screen holder with
	children (Fit) is looked into (two levels at most). Nil: no window (a
	HUD chip, a bar).
]]
function UIMotionController.findWindow(gui: Instance, screen: Vector2): GuiObject?
	local function pick(parent: Instance, area: Vector2, depth: number): GuiObject?
		local best: GuiObject? = nil
		local bestArea = -1
		local bestNamed = false
		local holder: GuiObject? = nil
		local holderNamed = false
		for _, child in parent:GetChildren() do
			if isFrame(child) and (child :: GuiObject).Visible then
				local frame = child :: GuiObject
				local size = sizeIn(frame, area)
				local named = UIMotionController.WindowNames[frame.Name] == true
				if fullScreen(size, area) then
					-- a holder (look inside) or a plain backdrop (no children: skip)
					if hasGuiChildren(frame) and (holder == nil or (named and not holderNamed)) then
						holder = frame
						holderNamed = named
					end
				elseif size.X >= UIMotionController.MinWindow.X and size.Y >= UIMotionController.MinWindow.Y then
					local a = size.X * size.Y
					if (named and not bestNamed) or (named == bestNamed and a > bestArea) then
						best = frame
						bestArea = a
						bestNamed = named
					end
				end
			end
		end
		if best and (bestNamed or not holderNamed) then
			return best
		end
		if holder and depth < 2 then
			local inside = pick(holder, sizeIn(holder, area), depth + 1)
			if inside then
				return inside
			end
		end
		return best
	end
	return pick(gui, screen, 0)
end

-- The dim backdrop of `gui`: a visible full-screen top-level Frame that
-- paints (BackgroundTransparency < 0.95) and holds nothing.
function UIMotionController.findDim(gui: Instance, screen: Vector2): GuiObject?
	for _, child in gui:GetChildren() do
		if child:IsA("Frame") and child.Visible and child.BackgroundTransparency < 0.95 then
			if fullScreen(sizeIn(child, screen), screen) and not hasGuiChildren(child) then
				return child
			end
		end
	end
	return nil
end

-- Does `gui` animate its window itself (an OpenPop, another UIScale on it)?
function UIMotionController.selfAnimated(gui: Instance, window: GuiObject): boolean
	if gui:FindFirstChild("OpenPop", true) then
		return true
	end
	local scale = window:FindFirstChildOfClass("UIScale")
	return scale ~= nil and scale.Name ~= "MotionPop"
end

-- Which kind of button gets the press / hover feel ("Pop" | "Kit"), nil: none.
function UIMotionController.pressKind(button: Instance): string?
	if not button:IsA("GuiButton") or button:GetAttribute("Motion") == "None" then
		return nil
	end
	local paint = button:FindFirstChild("Paint")
	local border = button:FindFirstChild("Border")
	if paint and paint:IsA("UIGradient") and border and border:IsA("UIStroke") then
		return "Pop"
	end
	if button:IsA("TextButton") and button.Name == "Button" then
		return "Kit"
	end
	return nil
end

--[[
	A button that fills its holder (the old kit's chunky button over its lip,
	a Pop tile's face: Size 1 x 1, AnchorPoint 0, 0) is held by its middle
	instead, in the very same place: Roblox scales a UIScale about the
	AnchorPoint, so the squash then shrinks it toward its centre with no
	anchor tween at all. Only these: their holder is what layouts move, never
	the button. (Every other button squashes about its centre too: Motion
	moves its AnchorPoint along with the scale.) True when it changed.
]]
function UIMotionController.centre(button: GuiObject): boolean
	local size = button.Size
	local at = button.Position
	local fills = size.X.Scale == 1 and size.Y.Scale == 1 and size.X.Offset == 0 and size.Y.Offset == 0
	if not fills or button.AnchorPoint ~= Vector2.zero or at.X.Scale ~= 0 or at.Y.Scale ~= 0 then
		return false
	end
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(0.5, at.X.Offset, 0.5, at.Y.Offset)
	return true
end

-- Press + hover on a button (idempotent: attaching twice adds one UIScale).
-- UI motion off: nothing (the button stays exactly as built).
function UIMotionController.attach(button: GuiButton)
	if not Motion.enabled() then
		return
	end
	UIMotionController.centre(button)
	Motion.press(button)
	Motion.hover(button)
end

---------------------------------------------------------------- runtime

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local seen: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local queue: { Instance } = {}
local flushing = false
local shines = 0
local lastSelected: GuiObject? = nil
-- every connection this controller makes (UI motion off: none, the tests check)
local connections: { RBXScriptConnection } = {}
local running = false

local function hook(signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

-- (tests) how many connections the controller holds, and whether its loop runs.
function UIMotionController.connectionCount(): number
	local n = 0
	for _, connection in connections do
		if connection.Connected then
			n += 1
		end
	end
	return n
end

function UIMotionController.isRunning(): boolean
	return running
end

local function inWorld(gui: Instance): boolean
	return gui:FindFirstAncestorWhichIsA("BillboardGui") ~= nil or gui:FindFirstAncestorWhichIsA("SurfaceGui") ~= nil
end

local function watchPopIn(gui: GuiObject)
	hook(gui:GetPropertyChangedSignal("Visible"), function()
		if gui.Visible then
			Motion.popIn(gui)
		end
	end)
end

local function consider(d: Instance)
	if not d:IsA("GuiObject") or d.Parent == nil or seen[d] then
		return
	end
	local motion = d:GetAttribute("Motion")
	local press = d:IsA("GuiButton") and UIMotionController.pressKind(d) ~= nil
	if not press and motion == nil then
		return -- (most of them: a label, a frame)
	end
	seen[d] = true
	if inWorld(d) then
		return
	end
	if press then
		UIMotionController.attach(d :: GuiButton)
	end
	if motion == "Breathe" then
		Motion.breathe(d)
	elseif motion == "Shine" then
		-- (staggered: the price buttons side by side never flash together)
		shines += 1
		Motion.shine(d, (shines * 0.53) % Motion.Shine.Period)
	elseif motion == "PopIn" then
		watchPopIn(d)
	end
end

local function flush()
	flushing = false
	local list = queue
	queue = {}
	for _, d in list do
		consider(d)
	end
end

local function enqueue(d: Instance)
	if not d:IsA("GuiObject") then
		return
	end
	table.insert(queue, d)
	if not flushing then
		flushing = true
		task.defer(flush)
	end
end

-- The gui's screen in design units (its pixels over its "Scale" UIScale).
local function designScreen(gui: ScreenGui): Vector2
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		local camera = Workspace.CurrentCamera
		size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	local scale = gui:FindFirstChild("Scale")
	local k = if scale and scale:IsA("UIScale") and scale.Scale > 0 then scale.Scale else 1
	return size / k
end

local function onOpened(gui: ScreenGui)
	Motion.refreshLoops()
	if not gui.Enabled then
		return
	end
	if Motion.reduced() then
		-- (a window that pops itself: its OpenPop tween stops at 1 before it shows)
		Motion.calm(gui)
	end
	if UIMotionController.Skip[gui.Name] or gui:GetAttribute("MotionSkip") then
		return
	end
	local screen = designScreen(gui)
	local window = UIMotionController.findWindow(gui, screen)
	if not window or Motion.poppedRecently(window) or UIMotionController.selfAnimated(gui, window) then
		return
	end
	Motion.pop(window, UIMotionController.findDim(gui, screen))
end

local function watchGui(gui: Instance)
	if watched[gui] or not gui:IsA("ScreenGui") or not gui:GetAttribute("TerraForge") then
		return
	end
	watched[gui] = true
	local screen = gui :: ScreenGui
	hook(screen:GetPropertyChangedSignal("Enabled"), function()
		if screen.Enabled then
			-- (a moment later: the controller that opened it lays it out first)
			task.defer(onOpened, screen)
		else
			Motion.settle(screen)
		end
	end)
end

local function pointerOf(kind: Enum.UserInputType): Motion.Pointer?
	if kind == Enum.UserInputType.Touch then
		return "Touch"
	end
	local name = kind.Name
	if name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	end
	if name:sub(1, 5) == "Mouse" or kind == Enum.UserInputType.Keyboard then
		return "Mouse"
	end
	return nil
end

function UIMotionController.start()
	if not Motion.enabled() then
		-- UI motion off (Config/AnimConfig.UIMotion): it costs nothing, no
		-- watcher, no input hook, no loop; the UI is the one main has
		return
	end
	running = true
	-- (required here: the pure finders above load in the Lune tests without a player)
	local SettingsController = require(script.Parent.SettingsController)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- reduce motion: Roblox's own setting, and the game's (SETTINGS panel); when
	-- it turns on, the other controllers' pops and pulses still running stop too
	local function calmIfReduced(was: boolean)
		if Motion.reduced() and not was then
			Motion.calm(playerGui)
		end
	end
	local function systemReduced()
		local ok, on = pcall(function()
			return GuiService.ReducedMotionEnabled
		end)
		local was = Motion.reduced()
		Motion.setSystemReduced(ok and on == true)
		calmIfReduced(was)
	end
	systemReduced()
	pcall(function()
		hook(GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"), systemReduced)
	end)
	SettingsController.onChanged(function(current)
		local was = Motion.reduced()
		Motion.setReduced(current.ReduceMotion == true)
		calmIfReduced(was)
	end)

	-- the pointer: hover only for the mouse
	local first: Motion.Pointer? = pointerOf(UserInputService:GetLastInputType())
	if first then
		Motion.setPointer(first)
	elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		Motion.setPointer("Touch")
	end
	hook(UserInputService.LastInputTypeChanged, function(kind: Enum.UserInputType)
		local now: Motion.Pointer? = pointerOf(kind)
		if now then
			Motion.setPointer(now)
		end
	end)

	-- the gamepad: its selection grows, its A squashes the selected button
	hook(GuiService:GetPropertyChangedSignal("SelectedObject"), function()
		local now = GuiService.SelectedObject
		if now ~= lastSelected then
			Motion.select(lastSelected, false)
			Motion.select(now, true)
			lastSelected = now
		end
	end)
	hook(UserInputService.InputBegan, function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.ButtonA then
			local selected = GuiService.SelectedObject
			if selected then
				Motion.pressDown(selected, input)
			end
		end
	end)

	-- windows and buttons: what is there now, then what comes
	for _, child in playerGui:GetChildren() do
		watchGui(child)
	end
	hook(playerGui.ChildAdded, watchGui)
	hook(playerGui.DescendantAdded, enqueue)
	for _, d in playerGui:GetDescendants() do
		enqueue(d)
	end

	-- the loops' visibility (a section or a card hiding inside an open gui)
	while true do
		task.wait(Motion.SweepEvery)
		if Motion.hasLoops() then
			Motion.refreshLoops()
		end
	end
end

return UIMotionController
