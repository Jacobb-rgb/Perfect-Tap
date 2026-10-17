--[[
	FoundryController: your Foundry on the client (FoundryService is the truth).

	- Prompts: "Open Foundry" (G / gamepad B) only on your own Foundry,
	  "Put In" (F / gamepad Y) only while you carry something.
	- Panel (FoundryView): opens on OpenUI "Foundry". Rows and the NEXT
	  BLASTER card come from the State snapshot (FoundryStock, BlasterLevel,
	  BlasterOre, Coins) and update live.
	    TAKE   FoundryAction "Take" { Key, Count = 1 } (the ore's cheapest ingot)
	    < >    pick the look among the ores of the usable ingots
	    FORGE  FoundryAction "Forge" { Ore = the look } (when it isn't ready
	           it only says why)
	  Closes with X, B, Backspace, walking away (FoundryService.Range from the
	  anvil) or respawning. Gamepads start on FORGE. Phones get the compact layout.
	- The hammer moment (FoundryBegin { Id, Level, Ore, Hits, Timeout }): a
	  close-up on the anvil, a glowing billet in the look's colour and a
	  hammer. STRIKE: the big button, a click or tap anywhere on the scene,
	  Space, gamepad A or R2. Every tap counts: taps during the camera move or
	  closer than MIN_GAP to the last one wait their turn (one queued). The
	  shrinking ring only decides PERFECT / GOOD / HIT (sparks, clang, shake).
	  After Hits taps the times go to the server (FoundryAction "Strike");
	  FoundryResult then shows the new blaster rising off the anvil with the
	  NEW BLASTER card (AWESOME: click, E, Enter or A), or why it failed.
	  LEAVE / B / Backspace cancel (nothing is taken).
	- Building: Molten / Glow parts pulse, the warning lights blink while its
	  owner forges (attribute Forging). Fx: FoundryIn (an item flies into the
	  chute's hood or the hopper), FoundryPut, FoundryForged (someone else's
	  new blaster).
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local Geo = require(Shared.Builders.Geo)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Net = require(Shared.Net)
local FoundryView = require(script.Parent.Parent.UI.FoundryView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local FxController = require(script.Parent.FxController)
local HudController = require(script.Parent.HudController)
local PromptController = require(script.Parent.PromptController)
local StateController = require(script.Parent.StateController)
local InteractController = require(script.Parent.InteractController)
local MiningController = require(script.Parent.MiningController)
local CleaningController = require(script.Parent.CleaningController)
local LightingController = require(script.Parent.LightingController)

local FoundryController = {}

-- keep in sync with FoundryService.Range (server)
FoundryController.Range = 24

local CLOSE_ACTION = "TerraForgeFoundryClose"
local STRIKE_ACTION = "TerraForgeFoundryStrike"
local LEAVE_ACTION = "TerraForgeFoundryLeave"
local COLLECT_ACTION = "TerraForgeFoundryCollect"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local RANGE_CHECK = 0.25
local INTRO = 0.6 -- the camera flies in; taps wait until it is there
local MIN_GAP = 0.3 -- client gap between counted taps (the server needs >= AnvilMinStrikeGap)
local MAX_QUEUED = 1
local RESULT_WAIT = 8
local PROMPT_TAG = "FoundryPrompt"
local BUILDING_TAG = "FoundryBuilding"

local REASONS: { [string]: string } = {
	NotEnough = "Not enough ingots or coins for that blaster.",
	MaxLevel = "Your blaster is already at the top level.",
	Busy = "You are already forging.",
	TooFar = "Walk back to your Foundry.",
	BadOre = "Pick a look from the ingots in your Foundry.",
	Cancelled = "Forging cancelled. Nothing was used.",
	Timeout = "The metal cooled down. Nothing was used, try again!",
	BadStrikes = "The hammering didn't work out. Nothing was used, try again!",
}

local player = Players.LocalPlayer
local refs: FoundryView.Refs? = nil
local isOpen = false
local rangeConnection: RBXScriptConnection? = nil
local chosenSkin: string? = nil
local forgePending = 0 -- os.clock() of the last Forge request (FORGE waits for the answer)
local lastStatus: any = nil
local session: any = nil

---------------------------------------------------------------- helpers

local function myPlotId(): number?
	local id = player:GetAttribute("PlotId")
	return if type(id) == "number" and WorldLayout.Plots[id] then id else nil
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

-- Your own Foundry building (nil while it isn't streamed in).
local function myBuilding(): Model?
	local plotId = myPlotId()
	if not plotId then
		return nil
	end
	for _, building in CollectionService:GetTagged(BUILDING_TAG) do
		if building:IsA("Model") and building:GetAttribute("PlotId") == plotId then
			return building
		end
	end
	return nil
end

local function attachmentWorld(building: Model?, name: string): CFrame?
	local base = building and building.PrimaryPart
	local a = base and base:FindFirstChild(name)
	if base and a and a:IsA("Attachment") then
		return base.CFrame * a.CFrame
	end
	return nil
end

local function reasonText(reason: any): string
	return REASONS[if type(reason) == "string" then reason else ""] or "That didn't work. Try again!"
end

---------------------------------------------------------------- prompts

local function applyPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local mine = prompt:GetAttribute("PlotId") == myPlotId()
	if prompt.Name == "FoundryPutIn" then
		prompt.Enabled = mine and carryCount() > 0
	else
		prompt.Enabled = mine
	end
end

local function refreshPrompts()
	for _, prompt in CollectionService:GetTagged(PROMPT_TAG) do
		applyPrompt(prompt)
	end
end

---------------------------------------------------------------- panel

local function keepSelection(view: FoundryView.Refs)
	if not usingGamepad() then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) and selected.Visible then
		local holder = selected.Parent
		if holder and holder:IsA("GuiObject") and holder.Visible then
			return
		end
	end
	local forgeHolder = view.Forge.Parent :: GuiObject
	GuiService.SelectedObject = if forgeHolder.Visible then view.Forge else view.Close
end

local function refresh(state: { [string]: any }?)
	local view = refs
	if not view or not isOpen then
		return
	end
	local s: { [string]: any } = state or {}
	local created = FoundryView.setRows(view, FoundryView.oreRows(s.FoundryStock, s.BlasterLevel), tonumber(s.FoundryCount) or 0)
	for _, row in created do
		local ore = row.Ore
		row.Take.Activated:Connect(function()
			local current = view.Rows[ore]
			if current and current.TakeKey ~= "" then
				Sfx.play("UIClick")
				Net.send("FoundryAction", "Take", { Key = current.TakeKey, Count = 1 })
			end
		end)
	end
	local status = FoundryView.status(s, chosenSkin)
	lastStatus = status
	FoundryView.setCard(view, status, s)
	if os.clock() - forgePending < 3 then
		FoundryView.setForgeEnabled(view, false)
	end
	keepSelection(view)
end

local function cycleSkin(step: number)
	local status = lastStatus
	if not status or #status.Skins < 2 then
		return
	end
	local index = table.find(status.Skins, status.Skin) or 1
	chosenSkin = status.Skins[(index - 1 + step) % #status.Skins + 1]
	Sfx.play("UIClick")
	refresh(StateController.get())
end

local function pressForge()
	local view = refs
	local status = lastStatus
	if not view or not status then
		return
	end
	if not status.Ready then
		Sfx.play("UIDeny")
		local current: { [string]: any } = StateController.get() or {}
		HudController.toast(FoundryView.reasonText(status, current.Coins), "Deny")
		return
	end
	if os.clock() - forgePending < 3 then
		return
	end
	forgePending = os.clock()
	FoundryView.setForgeEnabled(view, false)
	Sfx.play("UIClick")
	Net.send("FoundryAction", "Forge", { Ore = status.Skin })
end

local function updateHint(view: FoundryView.Refs)
	if usingGamepad() then
		FoundryView.setHint(
			view,
			"",
			UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA),
			UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
		)
	elseif isTouch() then
		FoundryView.setHint(view, "FORGE makes your next blaster  -  TAKE moves an ingot to the Ore Pen", nil, nil)
	else
		FoundryView.setHint(view, "FORGE makes your next blaster  -  TAKE moves an ingot to the Ore Pen  -  Backspace: close", nil, nil)
	end
end

function FoundryController.isOpen(): boolean
	return isOpen
end

function FoundryController.close()
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
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = nil
		end
		view.Gui.Enabled = false
	end
	PromptController.setSuppressed("FoundryPanel", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and isOpen then
		FoundryController.close()
		Sfx.play("UIClick")
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function ensureView(): FoundryView.Refs
	local view = refs
	if view then
		return view
	end
	local built = FoundryView.build()
	built.Gui.Parent = player:WaitForChild("PlayerGui")
	built.Close.Activated:Connect(function()
		FoundryController.close()
		Sfx.play("UIClick")
	end)
	built.Forge.Activated:Connect(pressForge)
	built.LookPrev.Activated:Connect(function()
		cycleSkin(-1)
	end)
	built.LookNext.Activated:Connect(function()
		cycleSkin(1)
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
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local anvil = attachmentWorld(myBuilding(), "AnvilPoint")
		if not root or not anvil then
			FoundryController.close()
			return
		end
		local offset = root.Position - anvil.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > FoundryController.Range then
			FoundryController.close()
		end
	end)
end

function FoundryController.open()
	if not myPlotId() or session then
		return
	end
	FoundryController.close()
	local view = ensureView()
	FoundryView.setCompact(view, HudController.uiScale() <= 0.75)
	updateHint(view)
	view.List.CanvasPosition = Vector2.zero
	view.Gui.Enabled = true
	isOpen = true
	forgePending = 0
	PromptController.setSuppressed("FoundryPanel", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	watchRange()
	refresh(StateController.get())
	if usingGamepad() then
		GuiService.SelectedObject = view.Forge
	end
	Sfx.play("UIClick")
end

---------------------------------------------------------------- the hammer moment

local function localProps(extra: { [string]: any }?): { [string]: any }
	local p: { [string]: any } = { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

-- A blaster tool as an anchored local model (the reveal).
local function blasterModel(level: number, ore: string, parent: Instance): (Model, BasePart)
	local tool = BlasterBuilder.build(level, ore)
	local model = Instance.new("Model")
	model.Name = "NewBlaster"
	local handle: BasePart? = nil
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			for _, child in d:GetChildren() do
				if child:IsA("WeldConstraint") then
					child:Destroy()
				end
			end
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d.Name == "Handle" then
				handle = d
			end
		end
	end
	local sum, n = Vector3.zero, 0
	for _, d in tool:GetChildren() do
		if d:IsA("BasePart") then
			sum += d.Position
			n += 1
		end
		d.Parent = model
	end
	tool:Destroy()
	local _ = handle
	-- an invisible pivot at the gun's middle, turned like the design frame
	local root = Geo.block(
		model,
		CFrame.new(if n > 0 then sum / n else Vector3.zero),
		Vector3.new(0.1, 0.1, 0.1),
		Color3.new(),
		nil,
		localProps({ Transparency = 1 })
	)
	root.Name = "Pivot"
	model.PrimaryPart = root
	model.Parent = parent
	return model, root
end

local function flash(view: FoundryView.ForgeRefs, color: Color3, from: number)
	view.Flash.BackgroundColor3 = color
	view.Flash.BackgroundTransparency = from
	TweenService:Create(view.Flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
end

-- A big popping word; it fades after `hold` seconds (default 0.5).
local function feedback(view: FoundryView.ForgeRefs, text: string, color: Color3, size: number?, hold: number?)
	local label = view.Feedback
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size or 44
	label.TextTransparency = 0
	local scale = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = label
	scale.Scale = 1.3
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService
		:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold or 0.5), { TextTransparency = 1 })
		:Play()
end

local function exit(s: any)
	if s.exited then
		return
	end
	s.exited = true
	for _, connection in s.connections do
		connection:Disconnect()
	end
	for _, action in { STRIKE_ACTION, LEAVE_ACTION, COLLECT_ACTION } do
		ContextActionService:UnbindAction(action)
	end
	local camera = s.camera :: Camera
	TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		CFrame = s.savedCF,
		FieldOfView = s.savedFov,
	}):Play()
	task.delay(0.5, function()
		if session == nil or session == s then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = s.savedFov
		end
		s.folder:Destroy()
		s.view.Gui:Destroy()
	end)
	if s.popLighting then
		s.popLighting()
	end
	if s.backpackWasEnabled ~= nil then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, s.backpackWasEnabled)
	end
	local hud = HudController.refs()
	if hud then
		hud.Gui.Enabled = true
	end
	pcall(function()
		GuiService.TouchControlsEnabled = true
	end)
	PlayerControls.set(true)
	PlayerControls.release("Foundry")
	PromptController.setSuppressed("Foundry", false)
	InteractController.resume()
	MiningController.setBusy(false)
	if session == s then
		session = nil
	end
end

local function leave(s: any)
	if s.exited or s.revealing then
		return
	end
	if not s.sent then
		Net.send("FoundryAction", "Cancel", { SessionId = s.Id })
	end
	exit(s)
end

local function fail(s: any, reason: any)
	if s.exited then
		return
	end
	s.failed = true
	feedback(s.view, reasonText(reason), Theme.Bad, 28, 2)
	s.view.Feedback.Size = UDim2.fromOffset(760, 70)
	task.delay(2.2, function()
		exit(s)
	end)
end

-- The hammer comes down: effects for one counted tap.
local function hit(s: any, grade: string)
	local anvil = s.anvil :: CFrame
	local strong = grade == "Perfect"
	local color = if strong then Theme.Coin elseif grade == "Good" then Theme.Good else Theme.Text
	feedback(s.view, if strong then "PERFECT!" elseif grade == "Good" then "GOOD!" else "HIT!", color)
	Sfx.play("AnvilClang", nil, if strong then 1.15 else 1)
	Vfx.burst("Sparks", anvil.Position + Vector3.new(0, 0.35, 0), if strong then 22 else 12, s.glow)
	if strong then
		Vfx.burst("Glint", anvil.Position + Vector3.new(0, 0.5, 0), 8, s.glow)
	end
	CameraShake.add(if strong then 0.32 else 0.18)
	flash(s.view, s.glow, if strong then 0.6 else 0.8)
	-- the hammer swings down and back, the billet flattens a little
	local hammer = s.hammer :: Model
	local up = s.hammerUp :: CFrame
	local down = s.hammerDown :: CFrame
	local value = Instance.new("NumberValue")
	value.Value = 0
	local swing = value.Changed:Connect(function(alpha: number)
		if hammer.Parent then
			hammer:PivotTo(up:Lerp(down, alpha))
		end
	end)
	local fall = TweenService:Create(value, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1 })
	fall.Completed:Connect(function()
		TweenService:Create(value, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 0 }):Play()
		task.delay(0.25, function()
			swing:Disconnect()
			value:Destroy()
		end)
	end)
	fall:Play()
	local billet = s.billet :: BasePart
	local done = #s.times / s.Hits
	billet.Size = Vector3.new(1.0 + 0.5 * done, 0.42 - 0.2 * done, 0.55 + 0.1 * done)
	billet.CFrame = anvil * CFrame.new(0, billet.Size.Y / 2, 0)
end

local function reveal(s: any, result: { [string]: any })
	s.revealing = true
	local level = tonumber(result.Level) or s.Level
	local ore = if type(result.Ore) == "string" and OreData.ById[result.Ore] then result.Ore else s.Ore
	local info = OreData.ById[ore]
	local rarity = info and Rarity.ById[info.Rarity]
	local anvil = s.anvil :: CFrame
	local center = anvil.Position + Vector3.new(0, 1.6, 0)
	s.billet.Transparency = 1
	s.hammer:Destroy()
	local burst = Geo.ball(s.folder, center, 0.6, s.glow, Enum.Material.Neon, localProps({ Transparency = 0.2 }))
	TweenService
		:Create(
			burst,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(6, 6, 6), Transparency = 1 }
		)
		:Play()
	Vfx.burst("Burst", center, 30, s.glow)
	Vfx.burst("Sparks", anvil.Position, 30, s.glow)
	Sfx.play("Reveal")
	CameraShake.add(0.4)
	flash(s.view, if rarity then rarity.Color else Theme.Accent, 0.4)
	local model = blasterModel(level, ore, s.folder)
	local light = Instance.new("PointLight")
	light.Color = s.glow
	light.Range = 14
	light.Brightness = 2
	light.Shadows = false
	light.Parent = model.PrimaryPart
	local camera = s.camera :: Camera
	local startedAt = os.clock()
	local rays: { BasePart } = {}
	local rayCount = if rarity and rarity.Order >= 3 then 8 else 0
	for _ = 1, rayCount do
		table.insert(
			rays,
			Geo.block(
				s.folder,
				CFrame.new(center),
				Vector3.new(0.14, 0.14, 5),
				rarity and rarity.Color or s.glow,
				Enum.Material.Neon,
				localProps({ Transparency = 0.4 })
			)
		)
	end
	table.insert(
		s.connections,
		RunService.RenderStepped:Connect(function()
			local t = os.clock() - startedAt
			local rise = math.min(1, t / 0.8)
			rise = 1 - (1 - rise) ^ 3
			local facing = CFrame.lookAt(center, camera.CFrame.Position)
			local spin = CFrame.Angles(0, t * 1.4, 0)
			local at = CFrame.new(anvil.Position:Lerp(center, rise)) * facing.Rotation * spin * CFrame.Angles(0, math.pi / 2, 0)
			model:PivotTo(at)
			for i, ray in rays do
				local a = i / #rays * math.pi * 2 + t * 0.8
				local dir = facing:VectorToWorldSpace(Vector3.new(math.cos(a), math.sin(a), -0.2))
				ray.CFrame = CFrame.lookAt(center + dir * 2.9, center + dir * 4)
				ray.Transparency = 0.4 + 0.5 * math.min(1, t / 3)
			end
		end)
	)
	FoundryView.showCard(s.view, level, ore, s.previousLevel, s.previousOre)
	-- A / B / Space no longer strike or leave: they collect
	ContextActionService:UnbindAction(STRIKE_ACTION)
	ContextActionService:UnbindAction(LEAVE_ACTION)
	local function collect()
		Sfx.play("UIClick")
		s.revealing = false
		exit(s)
	end
	table.insert(s.connections, s.view.Collect.Activated:Connect(collect))
	ContextActionService:BindActionAtPriority(
		COLLECT_ACTION,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				collect()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		CLOSE_PRIORITY,
		Enum.KeyCode.E,
		Enum.KeyCode.Return,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Backspace
	)
end

local function sendStrikes(s: any)
	s.sent = true
	Net.send("FoundryAction", "Strike", { SessionId = s.Id, Times = s.times })
	s.view.Sub.Text = "Forging..."
	s.view.RingHolder.Visible = false
	task.delay(RESULT_WAIT, function()
		if not s.exited and not s.result then
			fail(s, "Lost")
		end
	end)
end

-- Counts one tap now (the caller checked the gap).
local function count(s: any, now: number)
	local t = now - s.started
	local grade = FoundryView.grade(math.max(0, now - s.beatStart))
	s.beatStart = now
	table.insert(s.times, math.floor(t * 1000 + 0.5) / 1000)
	s.last = now
	FoundryView.setPips(s.view, s.Hits, #s.times)
	hit(s, grade)
	if #s.times >= s.Hits then
		local strikeHolder = s.view.Strike.Parent :: GuiObject
		strikeHolder.Visible = false
		s.view.StrikeHint.Visible = false
		sendStrikes(s)
	end
end

local function tap(s: any)
	if s.exited or s.sent or s.failed then
		return
	end
	local now = os.clock()
	if now - s.started >= INTRO and now - s.last >= MIN_GAP and s.queued == 0 then
		count(s, now)
	elseif s.queued < MAX_QUEUED then
		s.queued += 1 -- counted as soon as the gap allows (every tap counts)
	end
end

local function strikeHintText(s: any)
	local view = s.view :: FoundryView.ForgeRefs
	if usingGamepad() then
		view.StrikeHint.Text = "A or R2 to strike  -  B to leave"
	elseif isTouch() then
		view.StrikeHint.Text = "Tap STRIKE (or the anvil)"
	else
		view.StrikeHint.Text = "Click or press Space  -  Backspace: leave"
	end
end

local function begin(payload: { [string]: any })
	local id = payload.Id
	local hits = tonumber(payload.Hits)
	local level = tonumber(payload.Level)
	local ore = payload.Ore
	if type(id) ~= "string" or not hits or hits < 1 or hits > 20 or not level or type(ore) ~= "string" or not OreData.ById[ore] then
		if type(id) == "string" then
			Net.send("FoundryAction", "Cancel", { SessionId = id })
		end
		return
	end
	FoundryController.close()
	local building = myBuilding()
	local anvil = attachmentWorld(building, "AnvilPoint")
	local camPoint = attachmentWorld(building, "CamPoint")
	if session or not anvil or not camPoint or CleaningController.isActive() or not PlayerControls.claim("Foundry") then
		Net.send("FoundryAction", "Cancel", { SessionId = id })
		HudController.toast("Finish what you are doing first, then forge.", "Deny")
		return
	end
	local camera = Workspace.CurrentCamera :: Camera
	local info = OreData.ById[ore]
	local state: { [string]: any } = StateController.get() or {}
	local touch = isTouch()
	local folder = Instance.new("Folder")
	folder.Name = "ForgeMoment"
	folder.Parent = Workspace
	local view = FoundryView.buildForge(touch)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	local scaler = view.Gui:FindFirstChild("Scale")
	if scaler and scaler:IsA("UIScale") then
		scaler.Scale = HudController.uiScale()
	end
	view.Banner.Text = "FORGE: " .. string.upper(BlasterData.displayName(level, ore))
	FoundryView.setPips(view, hits, 0)
	local s: any = {
		Id = id,
		Hits = math.floor(hits),
		Level = level,
		Ore = ore,
		previousLevel = BlasterData.get(state.BlasterLevel).Level,
		previousOre = if type(state.BlasterOre) == "string" then state.BlasterOre else "",
		started = os.clock(),
		beatStart = os.clock() + INTRO - FoundryView.Beat * 0.4,
		last = -math.huge,
		queued = 0,
		times = {},
		connections = {},
		folder = folder,
		view = view,
		camera = camera,
		anvil = anvil,
		glow = info.Glow,
		savedCF = camera.CFrame,
		savedFov = camera.FieldOfView,
	}
	session = s
	-- take over: controls, prompts, grab/throw, blaster, HUD, backpack
	PlayerControls.set(false)
	PromptController.setSuppressed("Foundry", true)
	InteractController.suspend()
	MiningController.setBusy(true)
	local hud = HudController.refs()
	if hud then
		hud.Gui.Enabled = false
	end
	local okBackpack, backpackEnabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
	s.backpackWasEnabled = if okBackpack then backpackEnabled else nil
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	pcall(function()
		GuiService.TouchControlsEnabled = false
	end)
	s.popLighting = LightingController.push("Workbench", 0.5)
	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(camera, TweenInfo.new(INTRO, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		CFrame = camPoint,
		FieldOfView = 50,
	}):Play()
	-- the billet on the anvil (the look's colour, glowing hot) and the hammer
	local billet = Geo.block(
		folder,
		anvil * CFrame.new(0, 0.21, 0),
		Vector3.new(1.0, 0.42, 0.55),
		info.Color:Lerp(Color3.fromRGB(255, 140, 50), 0.45),
		Enum.Material.Neon,
		localProps()
	)
	billet.Name = "Billet"
	s.billet = billet
	local heat = Instance.new("PointLight")
	heat.Color = info.Glow
	heat.Range = 9
	heat.Brightness = 1.5
	heat.Shadows = false
	heat.Parent = billet
	local hammer = Instance.new("Model")
	hammer.Name = "Hammer"
	-- the hand end of the handle; the head comes down onto the billet's top
	local pivot = anvil * CFrame.new(1.75, 0.8, 0.1)
	Geo.block(hammer, pivot * CFrame.new(-0.85, 0, 0), Vector3.new(1.7, 0.18, 0.18), Color3.fromRGB(120, 80, 48), nil, localProps())
	Geo.block(
		hammer,
		pivot * CFrame.new(-1.75, 0, 0),
		Vector3.new(0.5, 0.75, 0.45),
		Color3.fromRGB(70, 72, 82),
		Enum.Material.Metal,
		localProps()
	)
	local grip = Geo.block(hammer, pivot, Vector3.new(0.1, 0.1, 0.1), Color3.new(), nil, localProps({ Transparency = 1 }))
	hammer.PrimaryPart = grip
	hammer.Parent = folder
	s.hammer = hammer
	s.hammerDown = pivot
	s.hammerUp = pivot * CFrame.Angles(0, 0, -1.0)
	hammer:PivotTo(s.hammerUp)
	strikeHintText(s)

	-- input: the button, a click / tap on the scene, Space, A, R2
	table.insert(
		s.connections,
		view.Strike.Activated:Connect(function()
			tap(s)
		end)
	)
	table.insert(
		s.connections,
		view.Leave.Activated:Connect(function()
			Sfx.play("UIClick")
			leave(s)
		end)
	)
	table.insert(
		s.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				tap(s)
			end
		end)
	)
	ContextActionService:BindActionAtPriority(STRIKE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tap(s)
		end
		return Enum.ContextActionResult.Sink
	end, false, CLOSE_PRIORITY, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority(LEAVE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			leave(s)
		end
		return Enum.ContextActionResult.Sink
	end, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	table.insert(
		s.connections,
		UserInputService.LastInputTypeChanged:Connect(function()
			strikeHintText(s)
		end)
	)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(
			s.connections,
			humanoid.Died:Connect(function()
				leave(s)
			end)
		)
	end
	table.insert(
		s.connections,
		player.CharacterRemoving:Connect(function()
			leave(s)
		end)
	)
	-- the ring, queued taps, the building streaming out
	table.insert(
		s.connections,
		RunService.RenderStepped:Connect(function()
			local now = os.clock()
			if not s.sent then
				local scale = FoundryView.ringScale(math.max(0, now - s.beatStart))
				view.Ring.Size = UDim2.fromScale(scale, scale)
				local close = math.abs(scale - 1) < 0.12
				view.RingStroke.Color = if close then Theme.Coin else Color3.new(1, 1, 1)
				if s.queued > 0 and now - s.started >= INTRO and now - s.last >= MIN_GAP then
					s.queued -= 1
					count(s, now)
				end
			end
			if not anvil or not building or not building.Parent then
				leave(s)
			end
		end)
	)
	Sfx.play("UIClick")
end

local function onResult(result: any)
	if type(result) ~= "table" then
		return
	end
	local s = session
	if s and result.Id == s.Id then
		s.result = result
		if result.Ok then
			reveal(s, result)
		else
			fail(s, result.Reason)
		end
		return
	end
	if result.Id == "" or result.Id == nil then
		-- "Forge" was refused before a session started
		forgePending = 0
		HudController.toast(reasonText(result.Reason), "Deny")
		Sfx.play("UIDeny")
		refresh(StateController.get())
	end
end

---------------------------------------------------------------- the building

type BuildingFx = { Tweens: { Tween }, Colors: { [BasePart]: Color3 }, Blink: Tween?, Lights: { BasePart }, Connection: RBXScriptConnection? }
local buildingFx: { [Instance]: BuildingFx } = {}

local LAMP_ON = Color3.fromRGB(255, 150, 20)
local LAMP_OFF = Color3.fromRGB(150, 90, 30)

local function setBlink(building: Model, fx: BuildingFx)
	local on = building:GetAttribute("Forging") == true
	if fx.Blink then
		fx.Blink:Cancel()
		fx.Blink = nil
	end
	for _, lamp in fx.Lights do
		lamp.Color = if on then LAMP_ON else LAMP_OFF
		if on then
			local tween = TweenService:Create(
				lamp,
				TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = Color3.fromRGB(90, 30, 10) }
			)
			tween:Play()
			fx.Blink = tween
		end
	end
end

-- Warning lights on every Foundry (they blink while its owner forges); the
-- molten metal only pulses on your own one (cheap on phones).
local function watchBuilding(building: Instance)
	if not building:IsA("Model") or buildingFx[building] then
		return
	end
	local fx: BuildingFx = { Tweens = {}, Colors = {}, Blink = nil, Lights = {}, Connection = nil }
	buildingFx[building] = fx
	local mine = building:GetAttribute("PlotId") == myPlotId()
	for _, d in building:GetDescendants() do
		if d:IsA("BasePart") and mine and (d.Name == "Molten" or d.Name == "Glow") then
			fx.Colors[d] = d.Color
			local hot = d.Color:Lerp(Color3.fromRGB(255, 190, 90), 0.45)
			local tween = TweenService:Create(
				d,
				TweenInfo.new(1.1 + math.random() * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = hot }
			)
			tween:Play()
			table.insert(fx.Tweens, tween)
		elseif d:IsA("BasePart") and d.Name == "WarnLight" then
			table.insert(fx.Lights, d)
		end
	end
	setBlink(building, fx)
	fx.Connection = building:GetAttributeChangedSignal("Forging"):Connect(function()
		setBlink(building, fx)
	end)
end

local function unwatchBuilding(building: Instance)
	local fx = buildingFx[building]
	if not fx then
		return
	end
	buildingFx[building] = nil
	for _, tween in fx.Tweens do
		tween:Cancel()
	end
	for part, color in fx.Colors do
		part.Color = color
	end
	if fx.Blink then
		fx.Blink:Cancel()
	end
	if fx.Connection then
		fx.Connection:Disconnect()
	end
end

-- Your plot changed: only your own Foundry pulses.
local function rewatchBuildings()
	for building in buildingFx do
		unwatchBuilding(building)
	end
	for _, building in CollectionService:GetTagged(BUILDING_TAG) do
		watchBuilding(building)
	end
end

-- A small copy of an item flies along an arc from `from` into `to`.
local function flyIn(from: Vector3, to: Vector3, kind: string, oreId: string)
	local model: Model? = nil
	if kind ~= "Raw" and OreData.ById[oreId] then
		local ok, built = pcall(ItemBuilder.display, { K = kind, O = oreId }, CFrame.new(from), "fly")
		if ok and typeof(built) == "Instance" then
			model = built :: Model
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "FoundryFly"
	folder.Parent = Workspace
	local mover: Model = model or Instance.new("Model")
	if not model then
		local chunk = Geo.block(mover, CFrame.new(from), Vector3.new(0.9, 0.7, 0.8), Color3.fromRGB(110, 96, 84), nil, localProps())
		mover.PrimaryPart = chunk
	end
	for _, d in mover:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	mover.Parent = folder
	local started = os.clock()
	local duration = 0.4
	local height = math.max(1.5, (to - from).Magnitude * 0.25)
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local p = math.min(1, (os.clock() - started) / duration)
		local position = from:Lerp(to, p) + Vector3.new(0, math.sin(p * math.pi) * height, 0)
		mover:PivotTo(CFrame.new(position) * CFrame.Angles(p * 3, p * 2, 0))
		if p >= 1 then
			connection:Disconnect()
			folder:Destroy()
			Vfx.burst("Sparks", to, 6)
			Sfx.play("Gulp", to)
		end
	end)
end

---------------------------------------------------------------- lifecycle

function FoundryController.init()
	Net.listen("OpenUI", function(kind)
		if kind == "Foundry" then
			FoundryController.open()
		end
	end)
	Net.listen("FoundryBegin", function(payload)
		if type(payload) == "table" then
			forgePending = 0
			begin(payload)
		end
	end)
	Net.listen("FoundryResult", onResult)
	StateController.onChanged(function(state)
		refresh(state)
	end)
	FxController.register("FoundryIn", function(from: any, to: any, kind: any, oreId: any)
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" and type(kind) == "string" then
			flyIn(from, to, kind, if type(oreId) == "string" then oreId else "")
		end
	end)
	FxController.register("FoundryPut", function(position: any)
		if typeof(position) == "Vector3" then
			Vfx.burst("Sparks", position, 10)
			Sfx.play("Gulp", position)
		end
	end)
	FxController.register("FoundryForged", function(position: any, oreId: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		local ore = if type(oreId) == "string" then OreData.ById[oreId] else nil
		local color = if ore then ore.Glow else Theme.Accent
		Vfx.burst("Burst", position + Vector3.new(0, 1.5, 0), 18, color)
		Vfx.burst("Sparks", position, 16, color)
		Sfx.play("AnvilClang", position)
	end)
	player.CharacterRemoving:Connect(function()
		FoundryController.close()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		local view = refs
		if view and isOpen then
			updateHint(view)
			keepSelection(view)
		end
	end)
end

function FoundryController.start()
	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(applyPrompt)
	refreshPrompts()
	player:GetAttributeChangedSignal("CarryCount"):Connect(refreshPrompts)
	player:GetAttributeChangedSignal("PlotId"):Connect(function()
		refreshPrompts()
		rewatchBuildings()
	end)
	CollectionService:GetInstanceAddedSignal(BUILDING_TAG):Connect(function(building)
		task.defer(watchBuilding, building)
	end)
	CollectionService:GetInstanceRemovedSignal(BUILDING_TAG):Connect(unwatchBuilding)
	for _, building in CollectionService:GetTagged(BUILDING_TAG) do
		watchBuilding(building)
	end
end

return FoundryController
