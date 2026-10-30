--[[
	CleaningController: the spray-washing minigame on the client.

	CleanBegin (server) -> close-up camera, the same dirt from the seed
	(CleaningPatterns), the player sprays it off (PointerInput: the mouse, a
	finger, or the gamepad cursor with A / R2), every recorded sample goes
	through the shared SprayTracker (the code the server replays), the
	recording goes out (CleanSubmit), the server's grade comes back
	(CleanResult), the look plays the reveal, Collect restores everything.
	The client only draws and records input; the grade comes from the server.

	The look (CleaningController.setLook(look), nil = DefaultLook) is
	everything the player sees of the clump, the spray and the reveal. A
	look is a table of optional callbacks; each gets the session's ctx last:
	  begin(ctx)                     build the visuals (the session starts)
	  spray(uv, hitWorldPos, active) every frame: uv = the pointer on the
	                                 face (nil off it), active = spraying now
	  cleaned(cells)                 cell indices that just came clean
	  cracked(crystals)              crystal indices that just cracked
	  progress(fraction)             0..1 of the job done (1 = clean)
	  quality(score)                 0..1 live score estimate (the grade so far)
	  finished()                     all the dirt is off; the recording goes
	                                 to the server (start the reveal)
	  done(result)                   the server's CleanResult (Ok = true):
	                                 show the grade / relic card
	  cancel()                       the session ended without a result
	The ctx a look reads (never writes, apart from LookState):
	  Id, OreId, Ore (OreData), Rarity (Rarity info), Relic (artifact id or
	  nil), Pattern (CleaningPatterns: Grid, CellSize, Origin, Cells,
	  Crystals, Outline), Radius (spray reach in face units), Input
	  ("Mouse" | "Touch" | "Gamepad"), Station, WorkCF (the face frame: +Z
	  toward the camera), Scale (studs per face unit), Camera, FitFov,
	  Folder (parent for visuals, destroyed on exit), View (CleaningView
	  refs: Leave, Hint, Feedback, Flash, Card, Collect...), Streak (cleans
	  in a row, set before done), Connections (disconnected on exit),
	  LookState (the look's own table)
	  worldAt(u, v, z), dirtLeft(cellIndex) -> 0..1, now(), ended(),
	  feedback(text, color?), flash(color, startTransparency),
	  collect() (after done: closes the close-up)
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OreData = require(Shared.Config.OreData)
local SecretOreConfig = require(Shared.Config.SecretOreConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local CleaningPatterns = require(Shared.Cleaning.CleaningPatterns)
local SprayScoring = require(Shared.Cleaning.SprayScoring)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)

local Cleaning = script.Parent.Parent.Cleaning
local PointerInput = require(Cleaning.PointerInput)
local CameraFit = require(Cleaning.CameraFit)
local DefaultLook = require(Cleaning.DefaultLook)
local SecretCleanFx = require(Cleaning.SecretCleanFx)
local RevealKit = require(script.Parent.Parent.Effects.RevealKit)
local CleaningView = require(script.Parent.Parent.UI.CleaningView)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local Hotbar = require(script.Parent.Parent.Util.Hotbar)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local LightingController = require(script.Parent.LightingController)
local HudController = require(script.Parent.HudController)
local InteractController = require(script.Parent.InteractController)
local MiningController = require(script.Parent.MiningController)
local PromptController = require(script.Parent.PromptController)

local CleaningController = {}

local player = Players.LocalPlayer
local active: any = nil
local look: any = DefaultLook
-- cleans in a row (CleaningView.nextStreak; cosmetic, never saved)
local streak = 0
local lastCleanAt: number? = nil
-- The camera from before cleaning. Kept here, not per session: a session that starts while
-- the last one's camera is still flying back must not save that half-restored camera.
local restoreCF: CFrame? = nil
local restoreFov: number? = nil

local pauses = SprayScoring.ClientPauses
local LEAVE_CONFIRM_TIME = 2 -- seconds to press Leave again once some dirt is off

local HINTS = {
	Mouse = "Hold the left mouse button to spray",
	Touch = "Hold your finger on the dirt and drag",
	Gamepad = "Left stick aims, hold A or R2 to spray, B to leave",
}

function CleaningController.isActive(): boolean
	return active ~= nil
end

-- Swaps the look (nil = the default look). Takes effect from the next session.
function CleaningController.setLook(newLook: any?)
	look = newLook or DefaultLook
end

function CleaningController.defaultLook(): any
	return DefaultLook
end

-- Calls one of the look's callbacks (a broken look never breaks the session).
local function callLook(ctx: any, name: string, args: { n: number, [number]: any })
	local fn = ctx.look[name]
	if type(fn) ~= "function" then
		return
	end
	args[args.n + 1] = ctx
	local ok, err = pcall(fn, table.unpack(args, 1, args.n + 1))
	if not ok then
		warn(`[Cleaning] look.{name} error: {err}`)
	end
end

-- The look's callback, and for a SECRET ore the jackpot's build-up next to it (Cleaning/SecretCleanFx);
-- its done plays the BOOM and the jackpot screen first, then the look's done (the card).
local function call(ctx: any, name: string, ...: any)
	local args = table.pack(...)
	local secret = ctx.secretFx == true
	if secret and name == "done" then
		local ok, err = pcall(function()
			SecretCleanFx.done(args[1], ctx, function()
				callLook(ctx, "done", table.pack(table.unpack(args, 1, args.n)))
			end)
		end)
		if not ok then
			warn(`[Cleaning] SecretCleanFx.done error: {err}`)
			callLook(ctx, "done", args)
		end
		return
	end
	callLook(ctx, name, table.pack(table.unpack(args, 1, args.n)))
	local fx = if secret then (SecretCleanFx :: any)[name] else nil
	if type(fx) == "function" then
		args[args.n + 1] = ctx
		local ok, err = pcall(fx, table.unpack(args, 1, args.n + 1))
		if not ok then
			warn(`[Cleaning] SecretCleanFx.{name} error: {err}`)
		end
	end
end

---------------------------------------------------------------- run context

local function makeContext(data: { [string]: any }, station: Model): any
	local camera = Workspace.CurrentCamera
	local base = station.PrimaryPart :: BasePart
	local orePoint = (base:FindFirstChild("OrePoint") :: Attachment).WorldCFrame
	local camPoint = (base:FindFirstChild("CamPoint") :: Attachment).WorldCFrame
	local pattern = CleaningPatterns.generate(data.OreId, data.Seed)
	local ore = OreData.get(data.OreId)
	local pointer = PointerInput.new()
	local folder = Instance.new("Folder")
	folder.Name = "CleaningClient"
	folder.Parent = Workspace
	local toCamera = (camPoint.Position - orePoint.Position).Unit
	local workCF = CFrame.lookAt(orePoint.Position, orePoint.Position - toCamera)
	local relicId = if type(data.Relic) == "string" and ArtifactConfig.ById[data.Relic] then data.Relic else nil
	local view = CleaningView.build({ Touch = UserInputService.TouchEnabled })
	view.Gui:SetAttribute("TerraForge", true)
	local tracker = SprayScoring.SprayTracker.new(pattern, pointer.Kind)

	local ctx: any = {
		Id = data.Id,
		OreId = data.OreId,
		Ore = ore,
		Rarity = Rarity.get(ore.Rarity),
		Relic = relicId,
		Pattern = pattern,
		Radius = tracker.radius,
		Input = pointer.Kind,
		Station = station,
		WorkCF = workCF,
		Scale = OreShellBuilder.Scale,
		Camera = camera,
		CamPoint = camPoint,
		OrePoint = orePoint,
		Folder = folder,
		View = view,
		Streak = streak,
		Connections = {},
		LookState = {},
		look = look,
		-- a SECRET ore in the vise: the jackpot's build-up runs next to the look (SecretCleanFx)
		secretFx = relicId == nil and SecretOreConfig.isSecret(data.OreId),
		pointer = pointer,
		tracker = tracker,
		submission = { Strokes = {}, Input = pointer.Kind },
		samples = 0,
		stroke = nil,
		lastSampleT = -math.huge,
		live = false,
		startClock = os.clock(),
		hintKind = pointer.Kind,
		cancelled = false,
		result = nil,
	}

	function ctx.now(): number
		return os.clock() - ctx.startClock
	end
	function ctx.ended(): boolean
		return ctx.exited == true
	end
	function ctx.worldAt(u: number, v: number, z: number): Vector3
		return workCF:PointToWorldSpace(Vector3.new(u * OreShellBuilder.Scale, v * OreShellBuilder.Scale, z))
	end
	function ctx.dirtLeft(index: number): number
		return tracker:left(index)
	end
	-- screen point -> face coordinates on the plane at depth z
	function ctx.faceAt(position: Vector2, z: number): Vector2?
		local ray = camera:ViewportPointToRay(position.X, position.Y)
		local planePoint = workCF:PointToWorldSpace(Vector3.new(0, 0, z))
		local normal = workCF.LookVector * -1
		local denom = ray.Direction:Dot(normal)
		if math.abs(denom) < 1e-4 then
			return nil
		end
		local t = (planePoint - ray.Origin):Dot(normal) / denom
		if t < 0 then
			return nil
		end
		local hit = ray.Origin + ray.Direction * t
		local localPos = workCF:PointToObjectSpace(hit)
		return Vector2.new(localPos.X / OreShellBuilder.Scale, localPos.Y / OreShellBuilder.Scale)
	end
	function ctx.feedback(text: string, color: Color3?)
		local label = view.Feedback
		label.Text = text
		-- long messages get smaller so they stay on one or two lines
		label.TextSize = if #text > 24 then 28 elseif #text > 20 then 36 else 44
		label.TextColor3 = color or Theme.Text
		label.TextTransparency = 0
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
		local pop = label:FindFirstChild("Pop") :: UIScale
		pop.Scale = 0.5
		TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local token = {}
		ctx.feedbackToken = token
		task.delay(0.9, function()
			if ctx.feedbackToken == token then
				TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				end
			end
		end)
	end
	function ctx.flash(color: Color3, startTransparency: number)
		local function show()
			view.Flash.BackgroundColor3 = color
			view.Flash.BackgroundTransparency = startTransparency
			TweenService:Create(view.Flash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		end
		-- one flash clock for every reveal (RevealKit.FlashGap: 2.5 a second at most); a flash
		-- too soon after another (a crystal's crack just before the reveal) plays once it may
		local now = os.clock()
		if RevealKit.takeFlash(now) then
			show()
			return
		end
		task.delay(math.max(0, RevealKit.nextFlashAt() - now), function()
			if not ctx.ended() and RevealKit.takeFlash(os.clock()) then
				show()
			end
		end)
	end
	return ctx
end

---------------------------------------------------------------- enter / exit

local function leaveConfirming(ctx: any): boolean
	return ctx.leaveArmedAt ~= nil and os.clock() - ctx.leaveArmedAt < LEAVE_CONFIRM_TIME
end

-- Button texts; the controller cursor can't click buttons, so they name their keys.
local function updateButtonLabels(ctx: any)
	local gamepad = ctx.pointer.Kind == "Gamepad"
	local view = ctx.View
	view.Leave.Text = (if leaveConfirming(ctx) then "Sure?" else "Leave") .. (if gamepad then " (B)" else "")
	view.Collect.Text = if gamepad then "Collect (A)" else "Collect"
end

local function setRawItemHidden(ctx: any, hidden: boolean)
	for _, item in CollectionService:GetTagged("Item") do
		if item:IsA("Model") and item.PrimaryPart and item:GetAttribute("State") == "Machine" then
			if (item.PrimaryPart.Position - ctx.OrePoint.Position).Magnitude < 3 then
				for _, d in item:GetDescendants() do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = if hidden then 1 else 0
					end
				end
			end
		end
	end
end

local function playerControls(enabled: boolean)
	local ok, module = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		-- PlayerModule is inserted by Roblox at runtime (not a static path)
		local requireAny: any = require
		return if playerModule then requireAny(playerModule) else nil
	end)
	if ok and module then
		local controls = (module :: any):GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function fitCamera(ctx: any, scale: number, compact: boolean): (CFrame, number)
	return CameraFit.compute({
		ViewportHeight = ctx.Camera.ViewportSize.Y,
		InsetTop = GuiService:GetGuiInset().Y,
		FreeTop = if compact then 16 else CleaningView.BannerBottom,
		FreeBottom = CleaningView.BottomReserved,
		UiScale = scale,
		Outline = ctx.Pattern.Outline,
		FaceScale = OreShellBuilder.Scale,
		CamPoint = ctx.CamPoint,
		OrePoint = ctx.OrePoint.Position,
	})
end

local function enter(ctx: any)
	-- the close-up takes the screen: no panel (the book, the wheel, a shop...) stays over it
	MenuPanels.closeAll()
	MiningController.setBusy(true)
	InteractController.suspend()
	-- no prompt behind the close-up: the station's "Clean Ore" comes back the moment you
	-- submit, and E on the result card (Collect) must not fire it too
	PromptController.setSuppressed("Cleaning", true)
	playerControls(false)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	pcall(function()
		GuiService.TouchControlsEnabled = false
	end)
	local hud = HudController.refs()
	if hud then
		hud.Gui.Enabled = false
	end
	-- the hotbar would cover the bottom hints (and could re-equip the blaster)
	local okBackpack, backpackEnabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
	ctx.backpackWasEnabled = if okBackpack then backpackEnabled else nil
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	local scale = HudController.uiScale()
	local compact = scale <= 0.75 or ctx.Camera.ViewportSize.Y < 520
	CleaningView.setCompact(ctx.View, compact, if UserInputService.TouchEnabled then 70 else 48)
	ctx.View.Gui.Parent = player:WaitForChild("PlayerGui")
	ctx.View.Hint.Text = HINTS[ctx.pointer.Kind] or HINTS.Mouse
	ctx.View.Cursor.Visible = ctx.pointer.Kind == "Gamepad"
	updateButtonLabels(ctx)
	ctx.popLighting = LightingController.push("Workbench", 0.6)
	-- everything stays sharp (owner, 2026-10-20: no blurred close-up); a blur another feature left on goes off
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end
	setRawItemHidden(ctx, true)
	local camera = ctx.Camera
	-- a quick restart keeps the camera from before the first session (see restoreCF)
	ctx.savedCameraCF = restoreCF or camera.CFrame
	ctx.savedFov = restoreFov or camera.FieldOfView
	restoreCF, restoreFov = ctx.savedCameraCF, ctx.savedFov
	camera.CameraType = Enum.CameraType.Scriptable
	local target, fov = fitCamera(ctx, scale, compact)
	ctx.FitFov = fov
	TweenService:Create(camera, TweenInfo.new(pauses.Intro, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		CFrame = target,
		FieldOfView = fov,
	}):Play()
	ctx.pointer:start()
end

local function exit(ctx: any)
	if ctx.exited then
		return
	end
	ctx.exited = true
	if not ctx.result or not ctx.result.Ok then
		call(ctx, "cancel")
	end
	for _, connection in ctx.Connections do
		connection:Disconnect()
	end
	ContextActionService:UnbindAction("TerraForgeCleanBack")
	ContextActionService:UnbindAction("TerraForgeCleanCollect")
	ctx.pointer:stop()
	setRawItemHidden(ctx, false)
	local camera = ctx.Camera
	local back = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		CFrame = ctx.savedCameraCF,
		FieldOfView = ctx.savedFov or 70,
	})
	back:Play()
	TweenService:Create(ctx.View.Flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		-- a new session may already own the camera
		if active == nil then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = ctx.savedFov or 70
			restoreCF, restoreFov = nil, nil
		end
		ctx.Folder:Destroy()
		ctx.View.Gui:Destroy()
	end)
	if ctx.backpackWasEnabled ~= nil then
		Hotbar.restoreCore(ctx.backpackWasEnabled) -- (never back on with the light UI: its own BLASTER slot)
	end
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end
	if ctx.popLighting then
		ctx.popLighting()
	end
	local hud = HudController.refs()
	if hud then
		hud.Gui.Enabled = true
	end
	pcall(function()
		GuiService.TouchControlsEnabled = true
	end)
	playerControls(true)
	InteractController.resume()
	PromptController.setSuppressed("Cleaning", false)
	MiningController.setBusy(false)
	if active == ctx then
		active = nil
	end
end

local function cancel(ctx: any)
	if ctx.submitted or ctx.exited then
		return
	end
	ctx.cancelled = true
	Net.send("CleanCancel", ctx.Id)
	Sfx.play("UIClick")
	exit(ctx)
end

-- Leave button, B or Backspace. Once some dirt is off, the first press asks for a second one.
local function requestLeave(ctx: any)
	if ctx.submitted or ctx.exited then
		return
	end
	local invested = ctx.tracker.cleanedCount > 0
	if invested and not leaveConfirming(ctx) then
		local armedAt = os.clock()
		ctx.leaveArmedAt = armedAt
		Sfx.play("UIClick", nil, 0.8)
		ctx.feedback("Press again to leave", Theme.Bad)
		ctx.View.Hint.Text = "Your ore stays in the vise."
		updateButtonLabels(ctx)
		task.delay(LEAVE_CONFIRM_TIME, function()
			if ctx.leaveArmedAt == armedAt and not ctx.exited then
				ctx.leaveArmedAt = nil
				updateButtonLabels(ctx)
				if not ctx.submitted then
					ctx.View.Hint.Text = HINTS[ctx.pointer.Kind] or HINTS.Mouse
				end
			end
		end)
		return
	end
	cancel(ctx)
end

---------------------------------------------------------------- spraying

-- One recorded sample: into the submission and through the shared tracker. At a cap of the
-- server's (a very long or dabbed run) the session ends with a word instead of freezing.
local function record(ctx: any, uv: Vector2, t: number)
	if ctx.samples >= SprayScoring.MaxSamples or (not ctx.stroke and #ctx.submission.Strokes >= SprayScoring.MaxStrokes) then
		if not ctx.capped then
			ctx.capped = true
			ctx.feedback("Too long! Start again.", Theme.Bad)
			task.delay(1.2, function()
				cancel(ctx)
			end)
		end
		return
	end
	if not ctx.stroke then
		ctx.stroke = {}
		table.insert(ctx.submission.Strokes, ctx.stroke)
	end
	table.insert(ctx.stroke, uv.X)
	table.insert(ctx.stroke, uv.Y)
	table.insert(ctx.stroke, t)
	ctx.samples += 1
	ctx.lastSampleT = t
	local before = ctx.tracker.cleanedCount
	local cleanedNow, crackedNow = ctx.tracker:add(uv.X, uv.Y, t)
	if #cleanedNow > 0 then
		call(ctx, "cleaned", cleanedNow)
	end
	if #crackedNow > 0 then
		call(ctx, "cracked", crackedNow)
	end
	if ctx.tracker.cleanedCount ~= before then
		call(ctx, "progress", ctx.tracker:progress())
	end
	call(ctx, "quality", ctx.tracker:parts(t).Score)
end

local function lift(ctx: any)
	local stroke = ctx.stroke
	if stroke then
		-- a one-sample tap sprays nothing (the server's replay is the same without it)
		if #stroke == 3 then
			local strokes = ctx.submission.Strokes
			if strokes[#strokes] == stroke then
				table.remove(strokes)
				ctx.samples -= 1
			end
		end
		ctx.stroke = nil
		ctx.tracker:lift()
	end
end

-- Every frame while the session runs: the pointer on the face, the spray on or off.
local function sprayFrame(ctx: any)
	local pointer = ctx.pointer
	-- one reach for the recording and every look: past it the pointer is off the clump
	local uv = ctx.faceAt(pointer.Position, OreShellBuilder.DirtFront)
	if uv and uv.Magnitude > SprayScoring.AimReach then
		uv = nil
	end
	local spraying = ctx.live and not ctx.done and pointer.Down and uv ~= nil and not leaveConfirming(ctx)
	if spraying then
		local t = ctx.now()
		if not ctx.stroke or t - ctx.lastSampleT >= SprayScoring.SampleStep then
			record(ctx, uv :: Vector2, t)
		end
		if ctx.tracker:complete() then
			ctx.done = true
			lift(ctx)
		end
	else
		lift(ctx)
	end
	local hit = if uv then ctx.worldAt(uv.X, uv.Y, OreShellBuilder.DirtFront) else nil
	call(ctx, "spray", uv, hit, spraying and not ctx.done)
end

---------------------------------------------------------------- main flow

local function collect(ctx: any)
	if ctx.exited or not ctx.result or not ctx.result.Ok then
		return
	end
	Sfx.play("UIClick")
	exit(ctx)
end

local function run(ctx: any)
	enter(ctx)
	call(ctx, "begin")
	table.insert(
		ctx.Connections,
		ctx.View.Leave.Activated:Connect(function()
			requestLeave(ctx)
		end)
	)
	ContextActionService:BindAction("TerraForgeCleanBack", function(_, state)
		if state == Enum.UserInputState.Begin then
			requestLeave(ctx)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(
			ctx.Connections,
			humanoid.Died:Connect(function()
				cancel(ctx)
			end)
		)
	end
	table.insert(
		ctx.Connections,
		RunService.RenderStepped:Connect(function(dt)
			ctx.pointer:update(dt)
			local view = ctx.View
			if ctx.pointer.Kind ~= ctx.hintKind then
				ctx.hintKind = ctx.pointer.Kind
				if not ctx.submitted and not leaveConfirming(ctx) then
					view.Hint.Text = HINTS[ctx.pointer.Kind] or HINTS.Mouse
				end
				updateButtonLabels(ctx)
			end
			if ctx.pointer.Kind == "Gamepad" and not ctx.submitted then
				view.Cursor.Visible = true
				local inset = GuiService:GetGuiInset()
				local p = ctx.pointer.Position - inset
				local scale = (view.Gui:FindFirstChild("Scale") :: UIScale).Scale
				view.Cursor.Position = UDim2.fromOffset(p.X / scale, p.Y / scale)
			else
				view.Cursor.Visible = false
			end
			if not ctx.submitted then
				local ok, err = pcall(function(): any
					sprayFrame(ctx)
					return nil
				end)
				if not ok then
					warn("[Cleaning] spray error: " .. tostring(err))
				end
			end
			if not ctx.Station.Parent then
				cancel(ctx)
			end
		end)
	)
	-- every wait in this flow is a ClientPauses value: the server's timeline check expects them
	task.wait(pauses.Intro)
	ctx.live = true
	while not ctx.done and not ctx.cancelled and not ctx.exited do
		task.wait()
	end
	if ctx.cancelled or ctx.exited then
		return
	end
	-- all clean: nothing to leave any more, the look starts the reveal, then the recording goes out
	ctx.submitted = true
	ctx.View.Leave.Parent.Visible = false
	ctx.View.Hint.Text = ""
	ContextActionService:UnbindAction("TerraForgeCleanBack")
	call(ctx, "progress", 1)
	call(ctx, "finished")
	task.wait(pauses.Finish)
	if ctx.exited then
		return
	end
	Net.send("CleanSubmit", ctx.Id, ctx.submission)
	-- the card once the server answered
	local waited = 0
	while not ctx.result and waited < 8 and not ctx.exited do
		task.wait(0.1)
		waited += 0.1
	end
	if ctx.exited then
		return
	end
	local result = ctx.result
	if not result or not result.Ok then
		ctx.feedback(if result and result.Reason then result.Reason else "Couldn't reach the server, try again.", Theme.Bad)
		task.wait(2.5)
		exit(ctx)
		return
	end
	-- cleans in a row: a little chip on the card (nothing saved, no reward)
	local now = os.clock()
	streak = CleaningView.nextStreak(streak, lastCleanAt, now)
	lastCleanAt = now
	ctx.Streak = streak
	call(ctx, "done", result)
	ContextActionService:BindAction("TerraForgeCleanCollect", function(_, state)
		-- (a SECRET ore's jackpot screen is still up: its own skip gets the key, the card comes after it)
		if ctx.revealing then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			collect(ctx)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
end

function CleaningController.init()
	Net.listen("CleanBegin", function(data)
		if type(data) ~= "table" or type(data.Id) ~= "string" then
			return
		end
		if active then
			-- still on the last result card: tell the server so it doesn't hold a session nobody plays
			Net.send("CleanCancel", data.Id)
			return
		end
		if not OreData.exists(data.OreId) or type(data.Seed) ~= "number" then
			Net.send("CleanCancel", data.Id)
			return
		end
		local station = data.Station
		if typeof(station) ~= "Instance" or not station:IsA("Model") or not station.PrimaryPart then
			Net.send("CleanCancel", data.Id)
			return
		end
		local base = station.PrimaryPart :: BasePart
		if not base:FindFirstChild("OrePoint") or not base:FindFirstChild("CamPoint") then
			Net.send("CleanCancel", data.Id)
			return
		end
		local ok, ctx = pcall(makeContext, data, station :: Model)
		if not ok then
			warn("[Cleaning] could not start: " .. tostring(ctx))
			Net.send("CleanCancel", data.Id)
			return
		end
		function ctx.collect()
			collect(ctx)
		end
		active = ctx
		task.spawn(run, ctx)
	end)
	Net.listen("CleanResult", function(result)
		if type(result) ~= "table" then
			return
		end
		local ctx = active
		if not ctx or result.Id ~= ctx.Id then
			return
		end
		ctx.result = result
		if not result.Ok and not ctx.submitted then
			ctx.feedback(result.Reason or "Cleaning cancelled.", Theme.Bad)
			task.delay(1.5, function()
				exit(ctx)
			end)
		end
	end)
end

return CleaningController
