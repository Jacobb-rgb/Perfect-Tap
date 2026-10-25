--[[
	TutorialController: the tutorial bubble (TutorialView) and the 3D guide.

	  - the step comes from the server: State's Tutorial { Step, Done } and
	    Net "Tutorial" { Step, Done, Total, Reward?, How } (TutorialService)
	  - the bubble shows the step's title, text and the control hint for the
	    input in use (mouse, touch or gamepad); a new step pops it in with a
	    sound, the end shows the finish card ("+250 coins")
	  - SKIP (press twice: "SURE?") and GOT IT (info steps) send
	    TutorialAction; gamepad: R3 presses the shown one (its glyph sits on
	    the button), and both buttons are selectable
	  - the guide: a sparkly Beam from your character to the step's target
	    and a bobbing arrow with the target's name over it (BillboardGui,
	    seen through walls). Targets are found by tag / plot
	    (TutorialConfig.Tags), else at TutorialConfig.layoutPoint while the
	    real thing hasn't streamed in. The beam fades out within
	    ArriveRadius; the arrow stays
	  - everything hides while the cleaning minigame runs
	    (CleaningController.isActive), something holds the controls
	    (PlayerControls: build mode, the crate opening) or a
	    panel other than the steps' own is open (TutorialView.panelHides:
	    the side menu's CODEX, GOLEMS, ARTIFACTS, BOOSTS, SETTINGS, HALL OF
	    FAME, the wheel, ...); R3 is unbound meanwhile, so it can't arm SKIP
	    inside a panel
	  - on touch the bubble sits in the HUD's top row right of the teleport
	    bar, where the FREE SPIN! chip goes too: inTopRow / onTopRowChanged
	    tell WheelController to keep the chip away while the bubble is there
	  - at join nothing shows under the loading screen: the bubble and the
	    guide wait for Loading.wait() (done, or its MaxWait time-out) and
	    then show either way
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local Net = require(Shared.Net)
local TutorialView = require(script.Parent.Parent.UI.TutorialView)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Loading = require(script.Parent.Parent.Util.Loading)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)
local CleaningController = require(script.Parent.CleaningController)
local SideMenuController = require(script.Parent.SideMenuController)

local TutorialController = {}

type Target = TutorialConfig.Target
type Input = TutorialConfig.Input

local player = Players.LocalPlayer
local refs: TutorialView.Refs? = nil
local step = 0 -- 0 = not known yet
local done = true
local asking = 0 -- os.clock() until SKIP waits for its second press (0 = not asking)
local shownStep = 0 -- the step the bubble shows (pops when it changes)
local visible = false
local bound = false
local cardShown = false -- the finish card shows once
local lastKind: Input? = nil
local touchLayout = false -- the bubble uses the touch layout (the top row, right of the teleport bar)
local inTopRow = false -- the bubble shows there (what onTopRowChanged listeners last heard)
local topRowListeners: { (boolean) -> () } = {}
local loaded = false -- the loading screen is gone (or Loading.wait timed out)

local PAD_KEY = Enum.KeyCode.ButtonR3
local ACTION = "TerraForgeTutorial"
local ASK_SECONDS = 3
local UPDATE = 0.25 -- seconds between bubble / guide updates
local RESOLVE = 0.5 -- seconds between target searches
local KEEP = 1.5 -- keep the current rock until another is this much closer

-- the guide (client-only, under the camera)
local guidePart: Part? = nil
local beam: Beam? = nil
local core: Beam? = nil
local arrow: BillboardGui? = nil
local arrowLabel: TextLabel? = nil
local rootAttachment: Attachment? = nil
local bob: Tween? = nil
local arrowHeight = 0 -- the height the bob runs at
local currentRock: Instance? = nil
local lastResolve = 0
local targetPoint: Vector3? = nil

---------------------------------------------------------------- input type

local function inputKind(): Input
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "Touch"
	end
	return "Mouse"
end

-- The screen in pt below Roblox's top bar (the ScreenGui's own size), else the camera's.
local function screenSize(): Vector2
	local r = refs
	local size = if r then r.Gui.AbsoluteSize else Vector2.zero
	if size.X > 0 and size.Y > 0 then
		return size
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function tenFoot(): boolean
	local ok, result = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and result == true
end

-- The top of the right-side menu's buttons (design units; the list is centred on the screen).
local function menuTop(scale: number): number?
	local menu = HudController.refs().Menu
	local list = menu and menu:FindFirstChildOfClass("UIListLayout")
	if not list then
		return nil
	end
	return screenSize().Y / scale / 2 - list.AbsoluteContentSize.Y / scale / 2
end

local function relayout()
	local r = refs
	if not r then
		return
	end
	local scale = HudController.uiScale()
	local uiScale = r.Gui:FindFirstChild("Scale")
	if uiScale and uiScale:IsA("UIScale") then
		uiScale.Scale = scale
	end
	local touch = inputKind() == "Touch"
	touchLayout = touch
	TutorialView.apply(r, TutorialView.layout(scale, screenSize(), touch, tenFoot(), menuTop(scale)))
end

-- Tells the listeners when the bubble comes into or leaves the top row.
local function topRowChanged()
	local now = visible and touchLayout
	if now == inTopRow then
		return
	end
	inTopRow = now
	for _, listener in topRowListeners do
		local ok, err = pcall(function(): any
			listener(now)
			return nil
		end)
		if not ok then
			warn(`[TutorialController] top row listener failed: {err}`)
		end
	end
end

---------------------------------------------------------------- the bubble

local function currentDef(): TutorialConfig.Step?
	if done or step < 1 then
		return nil
	end
	return TutorialConfig.get(step)
end

local function fill()
	local r = refs
	local def = currentDef()
	if not r or not def then
		return
	end
	local hint = if def.Hint then def.Hint[inputKind()] else nil
	TutorialView.setStep(r, step, def, hint)
	asking = 0
	local glyph = ""
	if inputKind() == "Gamepad" then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(PAD_KEY)
		end)
		glyph = if ok and type(image) == "string" then image else ""
	end
	TutorialView.setGlyph(r, glyph, def.Optional == true)
end

local function pop(frame: GuiObject)
	local scale = frame:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Scale = 1 }, frame)
	scale.Scale = 0.7
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function showDone(reward: number?)
	local r = refs
	if not r then
		return
	end
	r.DoneText.Text = TutorialView.doneText(reward)
	r.Done.Visible = true
	pop(r.Done)
	Sfx.play("CoinBurst")
	task.delay(4, function()
		if r.Done.Parent then
			r.Done.Visible = false
		end
	end)
end

local function skip()
	if done then
		return
	end
	if asking > os.clock() then
		asking = 0
		Sfx.play("UIClick")
		Net.send("TutorialAction", "Skip")
		return
	end
	asking = os.clock() + ASK_SECONDS
	Sfx.play("UIClick")
	local r = refs
	if r then
		TutorialView.setSkipAsk(r, true)
	end
end

local function ack()
	local def = currentDef()
	if def and def.Optional then
		Sfx.play("UIClick")
		Net.send("TutorialAction", "Ack")
	end
end

local function onPadKey(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not visible then
		return Enum.ContextActionResult.Pass
	end
	local def = currentDef()
	if def and def.Optional then
		ack()
	else
		skip()
	end
	return Enum.ContextActionResult.Sink
end

local function setBound(on: boolean)
	if on == bound then
		return
	end
	bound = on
	if on then
		ContextActionService:BindAction(ACTION, onPadKey, false, PAD_KEY)
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

---------------------------------------------------------------- the guide

local function buildGuide()
	local part = UIKit.new("Part", {
		Name = "TutorialTarget",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
	})
	local a1 = UIKit.new("Attachment", { Name = "Guide1" }, part)
	local b = UIKit.new("Beam", {
		Name = "GuideBeam",
		Attachment1 = a1,
		Color = ColorSequence.new(Theme.Accent, Theme.Coin),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.85, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		LightEmission = 0.7,
		LightInfluence = 0,
		FaceCamera = true,
		Width0 = 1.1,
		Width1 = 0.7,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 2.5,
		TextureSpeed = 1.2,
		Segments = 24,
		Enabled = false,
	}, part)
	-- a soft solid line under the sparkles, so the path reads from afar
	local line = UIKit.new("Beam", {
		Name = "GuideCore",
		Attachment1 = a1,
		Color = ColorSequence.new(Theme.Accent),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.85, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		Width0 = 0.35,
		Width1 = 0.25,
		Segments = 1,
		Enabled = false,
	}, part)
	local gui = UIKit.new("BillboardGui", {
		Name = "GuideArrow",
		Adornee = part,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(150, 96),
		MaxDistance = 2000,
		Enabled = false,
	}, part)
	local label = UIKit.label(gui, "", 18, {
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Theme.Coin,
	})
	-- a chunky chevron pointing down (two bars meeting at the tip)
	for _, side in { -1, 1 } do
		local arm = UIKit.new("Frame", {
			Name = if side < 0 then "ArmLeft" else "ArmRight",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(75 + side * 14, 68),
			Size = UDim2.fromOffset(14, 44),
			Rotation = side * 45,
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
		}, gui)
		UIKit.corner(arm, 7)
		UIKit.stroke(arm, 3)
	end
	part.Parent = Workspace.CurrentCamera or Workspace
	guidePart, beam, core, arrow, arrowLabel = part, b, line, gui, label
end

-- The arrow floats `height` studs over the target and bobs (a looping tween, no per-frame code).
local function setArrowHeight(height: number)
	local a = arrow
	if not a or height == arrowHeight then
		return
	end
	arrowHeight = height
	local old = bob
	if old then
		old:Cancel()
	end
	a.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	local tween = TweenService:Create(
		a,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffsetWorldSpace = Vector3.new(0, height + 1.2, 0) }
	)
	tween:Play()
	bob = tween
end

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function attachTo(root: BasePart)
	local a0 = rootAttachment
	if a0 and a0.Parent == root then
		return
	end
	local made = UIKit.new("Attachment", { Name = "TutorialGuide0", Position = Vector3.new(0, -1.6, 0) }, root)
	rootAttachment = made
	for _, b in { beam, core } do
		if b then
			b.Attachment0 = made
		end
	end
end

local function pointOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	elseif instance:IsA("ProximityPrompt") and instance.Parent then
		return pointOf(instance.Parent)
	end
	return nil
end

local function myLevel(): number
	local snapshot = StateController.get()
	local level = snapshot and snapshot.BlasterLevel
	return if type(level) == "number" then level else 1
end

-- A rock you can break now (your blaster is strong enough, not a VIP zone, not broken).
local function usableRock(rock: Instance): boolean
	if not rock:IsDescendantOf(Workspace) then
		return false
	end
	local needed = rock:GetAttribute("MinBlaster")
	local health = rock:GetAttribute("Health")
	return rock:GetAttribute("VipOnly") ~= true
		and (type(needed) ~= "number" or needed <= myLevel())
		and (type(health) ~= "number" or health > 0)
end

local function nearestTagged(tag: string, from: Vector3, keep: (Instance) -> boolean): (Instance?, number)
	local best: Instance? = nil
	local bestDistance = math.huge
	for _, instance in CollectionService:GetTagged(tag) do
		if keep(instance) then
			local at = pointOf(instance)
			if at then
				local distance = (at - from).Magnitude
				if distance < bestDistance then
					best, bestDistance = instance, distance
				end
			end
		end
	end
	return best, bestDistance
end

local function always(_instance: Instance): boolean
	return true
end

-- Where the guide points for a target now (nil = nowhere to point).
local function resolve(target: Target, from: Vector3): Vector3?
	local plotId = tonumber(player:GetAttribute("PlotId"))
	if target == "Rock" then
		-- a loose dirty chunk close by first (just blasted), else the nearest rock
		local chunk = nearestTagged("Item", from, function(item: Instance): boolean
			return item:GetAttribute("Kind") == "Raw" and item:GetAttribute("State") == "Loose" and item:GetAttribute("CarriedBy") == nil
		end)
		if chunk then
			local at = pointOf(chunk)
			if at and (at - from).Magnitude < 24 then
				return at
			end
		end
		local rock, distance = nearestTagged(TutorialConfig.Tags.Rock, from, usableRock)
		local current = currentRock
		if current and usableRock(current) then
			local at = pointOf(current)
			if at and (not rock or (at - from).Magnitude <= distance * KEEP) then
				return at
			end
		end
		currentRock = rock
		return if rock then pointOf(rock) else TutorialConfig.layoutPoint(target, plotId)
	elseif target == "Hopper" then
		local hopper = nearestTagged(TutorialConfig.Tags.Hopper, from, always)
		local at = if hopper then pointOf(hopper) else nil
		return at or TutorialConfig.layoutPoint(target, plotId)
	elseif target == "Cleaning" then
		local machine = nearestTagged(TutorialConfig.Tags.Cleaning, from, function(m: Instance): boolean
			return m:GetAttribute("Owner") == player.UserId and m:GetAttribute("MachineId") == "CleaningStation"
		end)
		local at = if machine then pointOf(machine) else nil
		return if at then at + Vector3.new(0, 3, 0) else TutorialConfig.layoutPoint(target, plotId)
	elseif target == "Sell" then
		local counter = nearestTagged(TutorialConfig.Tags.Sell, from, always)
		return if counter then pointOf(counter) else nil
	elseif target == "Vault" then
		local counter = nearestTagged(TutorialConfig.Tags.Vault, from, always)
		local at = if counter then pointOf(counter) else nil
		return at or TutorialConfig.layoutPoint(target, plotId)
	elseif target == "Capsules" or target == "Wheel" then
		-- lobby stalls (steps 6-7 hints): nothing to fall back to while they haven't streamed in
		local thing = nearestTagged(TutorialConfig.Tags[target], from, always)
		return if thing then pointOf(thing) else nil
	end
	return TutorialConfig.layoutPoint(target, plotId)
end

local function hideGuide()
	local a = arrow
	for _, b in { beam, core } do
		if b then
			b.Enabled = false
		end
	end
	if a then
		a.Enabled = false
	end
end

local function updateGuide(def: TutorialConfig.Step)
	local part, b, a, label = guidePart, beam, arrow, arrowLabel
	local root = rootOf()
	if not part or not b or not a or not label or not root then
		hideGuide()
		return
	end
	local carrying = tonumber(player:GetAttribute("CarryCount")) or 0
	local target = TutorialConfig.targetOf(def, carrying)
	if not target then
		hideGuide()
		return
	end
	local from = root.Position
	local now = os.clock()
	if now - lastResolve >= RESOLVE or not targetPoint then
		lastResolve = now
		targetPoint = resolve(target, from)
	end
	local at = targetPoint
	if not at then
		hideGuide()
		return
	end
	attachTo(root)
	part.CFrame = CFrame.new(at)
	label.Text = TutorialConfig.TargetNames[target] or ""
	setArrowHeight(TutorialConfig.arrowHeight(target))
	a.Enabled = true
	local far = (at - from).Magnitude > TutorialConfig.ArriveRadius
	b.Enabled = far
	local line = core
	if line then
		line.Enabled = far
	end
end

---------------------------------------------------------------- state

-- The panels open right now (MenuPanels.Names; the missing ones are skipped).
local function openPanels(): { string }
	local list = {}
	for _, name in MenuPanels.Names do
		if MenuPanels.isOpen(name) then
			table.insert(list, name)
		end
	end
	return list
end

-- The on-screen arrow at the step's side-menu button (UiTarget): on the
-- touch layout's shut grid it points at MENU, which opens it.
local function updatePointer(r: TutorialView.Refs, def: TutorialConfig.Step?, show: boolean)
	local pointer = r.Pointer
	local id = if show and def then def.UiTarget else nil
	local menu = if id then SideMenuController.refs() else nil
	local button: GuiObject? = nil
	if menu and id then
		local layout = menu.Layout
		if layout and layout.Toggle and not menu.Expanded then
			button = menu.Toggle
		else
			button = menu.Buttons[id]
		end
	end
	if not button or not button.Visible or button.AbsoluteSize.X <= 0 then
		pointer.Visible = false
		return
	end
	local column = if menu then menu.Column else nil
	local rightEdge = if column then column.AbsolutePosition.X + column.AbsoluteSize.X else nil
	local spot =
		TutorialView.pointerSpot(button.AbsolutePosition, button.AbsoluteSize, r.Gui.AbsolutePosition, HudController.uiScale(), rightEdge)
	pointer.Position = UDim2.fromOffset(spot.X, spot.Y)
	pointer.Visible = true
end

local function update()
	local r = refs
	if not r then
		return
	end
	local def = currentDef()
	local blocked = CleaningController.isActive() or PlayerControls.owner() ~= nil or TutorialView.panelHides(openPanels())
	local show = loaded and def ~= nil and not blocked
	if show ~= visible then
		visible = show
		r.Bubble.Visible = show
		if show then
			pop(r.Bubble)
		end
	end
	setBound(show)
	topRowChanged()
	if asking > 0 and os.clock() > asking then
		asking = 0
		TutorialView.setSkipAsk(r, false)
	end
	if show and def then
		updateGuide(def)
	else
		hideGuide()
	end
	updatePointer(r, def, show)
end

local function setState(newStep: number, newDone: boolean)
	step = TutorialConfig.clamp(newStep)
	done = newDone
	targetPoint = nil
	currentRock = nil
	if not done and step ~= shownStep then
		local first = shownStep == 0
		shownStep = step
		fill()
		local r = refs
		if r and not first and r.Bubble.Visible then
			pop(r.Bubble)
			Sfx.play("Discovery")
		end
	end
	update()
end

local function onTutorial(payload: any)
	if type(payload) ~= "table" or type(payload.Step) ~= "number" then
		return
	end
	setState(payload.Step, payload.Done == true)
	if payload.How == "Done" and not cardShown then
		cardShown = true
		showDone(if type(payload.Reward) == "number" then payload.Reward else nil)
	end
end

local function onSnapshot(snapshot: { [string]: any })
	local t = snapshot.Tutorial
	if type(t) ~= "table" or type(t.Step) ~= "number" then
		return
	end
	-- State only fills in what's missing (the Tutorial event brings the moments)
	if step == 0 or (t.Done == true) ~= done or t.Step ~= step then
		setState(t.Step, t.Done == true)
	end
end

function TutorialController.init()
	local built = TutorialView.build()
	refs = built
	built.Gui.Parent = player:WaitForChild("PlayerGui")
	built.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	built.Skip.Activated:Connect(skip)
	built.Ack.Activated:Connect(ack)
	relayout()
	Net.listen("Tutorial", onTutorial)
	-- the on-screen arrow bobs toward its button (a looping tween, no per-frame code)
	for _, arm in built.Pointer:GetChildren() do
		if arm:IsA("Frame") then
			TweenService:Create(
				arm,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = arm.Position - UDim2.fromOffset(8, 0) }
			):Play()
		end
	end
end

function TutorialController.start()
	buildGuide()
	StateController.onChanged(onSnapshot)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	-- the right-side menu grows (the elevator icon) -> the phone bubble keeps above it
	local menu = HudController.refs().Menu
	local list = menu and menu:FindFirstChildOfClass("UIListLayout")
	if list then
		list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(relayout)
	end
	lastKind = inputKind()
	UserInputService.LastInputTypeChanged:Connect(function()
		local kind = inputKind()
		if kind ~= lastKind then
			lastKind = kind
			relayout()
			fill()
			topRowChanged()
		end
	end)
	task.spawn(function()
		while true do
			update()
			task.wait(UPDATE)
		end
	end)
	-- the first bubble waits for the loading screen (shown either way after the wait)
	task.spawn(function()
		Loading.wait()
		loaded = true
		update()
	end)
end

-- Is the bubble on screen? (other controllers may want to keep clear)
function TutorialController.isShown(): boolean
	return visible
end

-- Is the bubble on screen in the HUD's top row, right of the teleport bar
-- (the touch layout)? The FREE SPIN! chip's spot: WheelController keeps
-- the chip away meanwhile.
function TutorialController.inTopRow(): boolean
	return visible and touchLayout
end

-- Calls listener(inTopRow) whenever that changes (in the same frame, so
-- the chip and the bubble never show together).
function TutorialController.onTopRowChanged(listener: (boolean) -> ())
	table.insert(topRowListeners, listener)
end

return TutorialController
