--[[
	CleaningController: the ore-cleaning minigame on the client.

	CleanBegin (server) -> close-up camera, build the ore from the seed,
	run CHISEL -> SCRAPE -> POLISH, send the recorded input (CleanSubmit),
	play the reveal, show the server's grade, restore everything.

	The client only draws and records input; the grade comes from the
	server re-scoring that input (CleanResult).
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
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local Format = require(Shared.Util.Format)
local CleaningPatterns = require(Shared.Cleaning.CleaningPatterns)
local CleaningScoring = require(Shared.Cleaning.CleaningScoring)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local ArtifactBuilder = require(Shared.Builders.ArtifactBuilder)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local Geo = require(Shared.Builders.Geo)

local Cleaning = script.Parent.Parent.Cleaning
local PointerInput = require(Cleaning.PointerInput)
local ChiselStep = require(Cleaning.ChiselStep)
local CameraFit = require(Cleaning.CameraFit)
local ScrapeStep = require(Cleaning.ScrapeStep)
local PolishStep = require(Cleaning.PolishStep)
local RevealFx = require(Cleaning.RevealFx)
local CleaningView = require(script.Parent.Parent.UI.CleaningView)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local StateController = require(script.Parent.StateController)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local LightingController = require(script.Parent.LightingController)
local HudController = require(script.Parent.HudController)
local InteractController = require(script.Parent.InteractController)
local MiningController = require(script.Parent.MiningController)

local CleaningController = {}

local player = Players.LocalPlayer
local active: any = nil
-- cleans in a row (CleaningView.nextStreak; cosmetic, never saved)
local streak = 0
local lastCleanAt: number? = nil
-- The camera from before cleaning. Kept here, not per session: a session that starts while
-- the last one's camera is still flying back must not save that half-restored camera.
local restoreCF: CFrame? = nil
local restoreFov: number? = nil

local pauses = CleaningScoring.ClientPauses
local LEAVE_CONFIRM_TIME = 2 -- seconds to press Leave again once a cut is done
local CHISEL_PRESSED_TRANSPARENCY = 0.55 -- a working chisel never hides the dots ahead

local STEPS: { { Module: any, Title: string, Text: string } } = {
	{ Module = ChiselStep, Title = "CHISEL", Text = "Trace the glowing line" },
	{ Module = ScrapeStep, Title = "SCRAPE", Text = "Brush away the dirt" },
	{ Module = PolishStep, Title = "POLISH", Text = "Rub in circles" },
}

local HINTS = {
	Mouse = "Hold the left mouse button and drag",
	Touch = "Drag with your finger",
	Gamepad = "Steer with the left stick, hold A to work, B to leave",
}

function CleaningController.isActive(): boolean
	return active ~= nil
end

---------------------------------------------------------------- tools in hand

local function toolProps(extra: { [string]: any }?): { [string]: any }
	local p = { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

-- Each tool is built pointing up (+Y) with its working tip at the origin.
local function buildTools(folder: Instance): { [string]: Model }
	local tools = {}
	local function newTool(name: string): Model
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = folder
		tools[name] = m
		return m
	end
	local chisel = newTool("Chisel")
	Geo.wedge(
		chisel,
		CFrame.new(0, 0.12, 0) * CFrame.Angles(math.pi, 0, 0),
		Vector3.new(0.16, 0.24, 0.12),
		Color3.fromRGB(200, 205, 215),
		Enum.Material.Metal,
		toolProps()
	)
	Geo.block(chisel, CFrame.new(0, 0.5, 0), Vector3.new(0.16, 0.55, 0.12), Color3.fromRGB(170, 176, 188), Enum.Material.Metal, toolProps())
	Geo.block(chisel, CFrame.new(0, 1.1, 0), Vector3.new(0.24, 0.7, 0.24), Color3.fromRGB(150, 98, 56), nil, toolProps())
	local brush = newTool("Brush")
	for x = -1, 1 do
		Geo.block(brush, CFrame.new(x * 0.11, 0.1, 0), Vector3.new(0.08, 0.22, 0.32), Color3.fromRGB(230, 205, 140), nil, toolProps())
	end
	Geo.block(brush, CFrame.new(0, 0.3, 0), Vector3.new(0.42, 0.18, 0.4), Color3.fromRGB(150, 98, 56), nil, toolProps())
	Geo.block(brush, CFrame.new(0, 0.75, 0.05), Vector3.new(0.16, 0.8, 0.16), Color3.fromRGB(120, 80, 48), nil, toolProps())
	local cloth = newTool("Cloth")
	Geo.block(cloth, CFrame.new(0, 0.1, 0), Vector3.new(0.6, 0.18, 0.5), Color3.fromRGB(240, 222, 190), nil, toolProps())
	Geo.block(
		cloth,
		CFrame.new(0.05, 0.25, 0.02) * CFrame.Angles(0, 0, 0.3),
		Vector3.new(0.45, 0.15, 0.4),
		Color3.fromRGB(226, 206, 170),
		nil,
		toolProps()
	)
	for _, m in tools do
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d:SetAttribute("BaseCF", d.CFrame)
				d.Transparency = 1
			end
		end
	end
	return tools
end

local function placeTool(model: Model, cf: CFrame, visible: boolean, transparency: number?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * (d:GetAttribute("BaseCF") :: CFrame)
			d.Transparency = if visible then transparency or 0 else 1
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
	local shell = OreShellBuilder.build(pattern, workCF, folder)
	OreShellBuilder.workLight(workCF, folder)
	-- a dusty relic: the real relic waits inside the rock (hidden until the reveal)
	local relicId = if type(data.Relic) == "string" and ArtifactConfig.ById[data.Relic] then data.Relic else nil
	local relicParts: { BasePart } = {}
	if relicId then
		local corePoint = workCF * CFrame.new(0, -0.55, OreShellBuilder.CoreFront - 0.4)
		local relicModel = ArtifactBuilder.build(relicId, corePoint, 0.8, true)
		if relicModel then
			relicModel.Parent = folder
			for _, d in relicModel:GetDescendants() do
				if d:IsA("BasePart") then
					d:SetAttribute("ShowAs", d.Transparency)
					d.Transparency = 1
					table.insert(relicParts, d)
				end
			end
		end
	end
	local view = CleaningView.build({ Touch = UserInputService.TouchEnabled })
	view.Gui:SetAttribute("TerraForge", true)

	local ctx: any = {
		Id = data.Id,
		station = station,
		pattern = pattern,
		ore = ore,
		rarity = Rarity.get(ore.Rarity),
		pointer = pointer,
		folder = folder,
		shell = shell,
		relic = relicId,
		relicParts = relicParts,
		view = view,
		camera = camera,
		camPoint = camPoint,
		orePoint = orePoint,
		tolerance = pattern.Tolerance * (CleaningScoring.InputLeniency[pointer.Kind] or 1),
		submission = {
			Cuts = {},
			Scrape = { Removed = {}, Fragile = {} },
			Polish = { Samples = {}, Mode = "Circle" },
			Input = pointer.Kind,
		},
		startClock = os.clock(),
		lastFineDust = 0,
		hintKind = pointer.Kind,
		chips = 0,
		stepScores = {},
		cancelled = false,
		result = nil,
		step = nil,
		connections = {},
	}
	ctx.tools = buildTools(folder)

	function ctx.now(): number
		return os.clock() - ctx.startClock
	end
	function ctx.worldAt(u: number, v: number, z: number): Vector3
		return OreShellBuilder.toWorld(shell, u, v, z)
	end
	function ctx.screenAt(u: number, v: number, z: number): Vector2?
		local screen, onScreen = camera:WorldToViewportPoint(ctx.worldAt(u, v, z))
		return if onScreen then Vector2.new(screen.X, screen.Y) else nil
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
		return Vector2.new(localPos.X / shell.Scale, localPos.Y / shell.Scale)
	end
	function ctx.setInstruction(text: string)
		view.Instruction.Text = text
	end
	function ctx.setProgress(text: string)
		view.Progress.Text = text
	end
	function ctx.setMeter(score: number)
		CleaningView.setMeter(view, score)
	end
	function ctx.addChip()
		ctx.chips += 1
		view.Chips.Text = "Chips: " .. ctx.chips
		view.Chips.TextColor3 = Theme.Bad
		ctx.setMeter(ctx.combinedScore())
	end
	-- a restarted chisel attempt takes its chips back (the server never sees them)
	function ctx.removeChips(count: number)
		ctx.chips = math.max(0, ctx.chips - count)
		view.Chips.Text = "Chips: " .. ctx.chips
		view.Chips.TextColor3 = if ctx.chips > 0 then Theme.Bad else Theme.TextDim
		ctx.setMeter(ctx.combinedScore())
	end
	-- Quality you'd get if the rest went perfectly (starts at the top, mistakes lower it).
	function ctx.combinedScore(): number
		local w = CleaningScoring.Weights
		local chisel = ctx.stepScores[1] or (if ctx.step and ctx.step.liveScore and ctx.stepIndex == 1 then ctx.step:liveScore() else 1)
		local scrape = ctx.stepScores[2] or (if ctx.step and ctx.stepIndex == 2 then ctx.step:liveScore() else 1)
		local polish = ctx.stepScores[3] or (if ctx.step and ctx.stepIndex == 3 then ctx.step:liveScore() else 1)
		local penalty = math.min(CleaningScoring.MaxChipPenalty, ctx.chips * CleaningScoring.ChipPenalty)
		return math.clamp(w.Chisel * chisel + w.Scrape * scrape + w.Polish * polish - penalty, 0, 1)
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
		view.Flash.BackgroundColor3 = color
		view.Flash.BackgroundTransparency = startTransparency
		TweenService:Create(view.Flash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end
	-- moves the tool for the current step under the pointer
	function ctx.updateTool(name: string, pressed: boolean)
		for toolName, model in ctx.tools do
			if toolName ~= name then
				placeTool(model, CFrame.new(0, -1000, 0), false)
			end
		end
		local model = ctx.tools[name]
		local p = ctx.faceAt(pointer.Position, OreShellBuilder.DotZ)
		-- a lifted finger has no hover: a tool left there would cover the groove tip marker
		if not p or p.Magnitude > 1.6 or (not pressed and pointer.Kind == "Touch") then
			placeTool(model, CFrame.new(0, -1000, 0), false)
			return
		end
		local depth = if pressed then OreShellBuilder.DotZ - 0.06 else OreShellBuilder.DotZ + 0.15
		-- the tool leans back toward the camera and to the upper right
		local axis = (workCF:VectorToWorldSpace(Vector3.new(0.35, 0.5, if pressed then 0.7 else 0.85))).Unit
		local tip = ctx.worldAt(p.X, p.Y, depth)
		local right = axis:Cross(workCF.LookVector * -1)
		right = if right.Magnitude > 1e-3 then right.Unit else workCF.RightVector
		local back = right:Cross(axis).Unit
		-- while working, the chisel turns see-through so the guide dots ahead stay visible
		local transparency = if pressed and name == "Chisel" then CHISEL_PRESSED_TRANSPARENCY else 0
		placeTool(model, CFrame.fromMatrix(tip, right, axis, back), true, transparency)
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
	local view = ctx.view
	view.Leave.Text = (if leaveConfirming(ctx) then "Sure?" else "Leave") .. (if gamepad then " (B)" else "")
	view.Collect.Text = if gamepad then "Collect (A)" else "Collect"
end

local function setRawItemHidden(ctx: any, hidden: boolean)
	for _, item in CollectionService:GetTagged("Item") do
		if item:IsA("Model") and item.PrimaryPart and item:GetAttribute("State") == "Machine" then
			if (item.PrimaryPart.Position - ctx.orePoint.Position).Magnitude < 3 then
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
		ViewportHeight = ctx.camera.ViewportSize.Y,
		InsetTop = GuiService:GetGuiInset().Y,
		FreeTop = if compact then 16 else CleaningView.BannerBottom,
		FreeBottom = CleaningView.BottomReserved,
		UiScale = scale,
		Outline = ctx.pattern.Outline,
		FaceScale = ctx.shell.Scale,
		CamPoint = ctx.camPoint,
		OrePoint = ctx.orePoint.Position,
	})
end

local function enter(ctx: any)
	-- the close-up takes the screen: no panel (the book, the wheel, a shop...) stays over it
	MenuPanels.closeAll()
	MiningController.setBusy(true)
	InteractController.suspend()
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
	local compact = scale <= 0.75 or ctx.camera.ViewportSize.Y < 520
	CleaningView.setCompact(ctx.view, compact, if UserInputService.TouchEnabled then 70 else 48)
	ctx.view.Gui.Parent = player:WaitForChild("PlayerGui")
	ctx.view.Hint.Text = HINTS[ctx.pointer.Kind] or HINTS.Mouse
	ctx.view.Cursor.Visible = ctx.pointer.Kind == "Gamepad"
	updateButtonLabels(ctx)
	ctx.popLighting = LightingController.push("Workbench", 0.6)
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.FocusDistance = (ctx.camPoint.Position - ctx.orePoint.Position).Magnitude
		dof.InFocusRadius = 2.5
		dof.FarIntensity = 0.75
		dof.NearIntensity = 0
		dof.Enabled = true
	end
	setRawItemHidden(ctx, true)
	local camera = ctx.camera
	-- a quick restart keeps the camera from before the first session (see restoreCF)
	ctx.savedCameraCF = restoreCF or camera.CFrame
	ctx.savedFov = restoreFov or camera.FieldOfView
	restoreCF, restoreFov = ctx.savedCameraCF, ctx.savedFov
	camera.CameraType = Enum.CameraType.Scriptable
	local target, fov = fitCamera(ctx, scale, compact)
	ctx.fitFov = fov
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
	for _, connection in ctx.connections do
		connection:Disconnect()
	end
	ContextActionService:UnbindAction("TerraForgeCleanBack")
	ContextActionService:UnbindAction("TerraForgeCleanCollect")
	if ctx.step and ctx.step.destroy then
		ctx.step:destroy()
	end
	ctx.pointer:stop()
	setRawItemHidden(ctx, false)
	local camera = ctx.camera
	local back = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		CFrame = ctx.savedCameraCF,
		FieldOfView = ctx.savedFov or 70,
	})
	back:Play()
	TweenService:Create(ctx.view.Flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		-- a new session may already own the camera
		if active == nil then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = ctx.savedFov or 70
			restoreCF, restoreFov = nil, nil
		end
		ctx.folder:Destroy()
		ctx.view.Gui:Destroy()
	end)
	if ctx.backpackWasEnabled ~= nil then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, ctx.backpackWasEnabled)
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
	MiningController.setBusy(false)
	if active == ctx then
		active = nil
	end
end

local function cancel(ctx: any)
	if ctx.revealing or ctx.exited then
		return
	end
	ctx.cancelled = true
	Net.send("CleanCancel", ctx.Id)
	Sfx.play("UIClick")
	exit(ctx)
end

-- Leave button, B or Backspace. Once a cut is done, the first press asks for a second one.
local function requestLeave(ctx: any)
	if ctx.revealing or ctx.exited then
		return
	end
	local invested = next(ctx.submission.Cuts) ~= nil
	if invested and not leaveConfirming(ctx) then
		local armedAt = os.clock()
		ctx.leaveArmedAt = armedAt
		Sfx.play("UIClick", nil, 0.8)
		ctx.feedback("Press again to leave", Theme.Bad)
		ctx.view.Hint.Text = "Your ore stays in the vise."
		updateButtonLabels(ctx)
		task.delay(LEAVE_CONFIRM_TIME, function()
			if ctx.leaveArmedAt == armedAt and not ctx.exited then
				ctx.leaveArmedAt = nil
				updateButtonLabels(ctx)
				if not ctx.revealing then
					ctx.view.Hint.Text = HINTS[ctx.pointer.Kind] or HINTS.Mouse
				end
			end
		end)
		return
	end
	cancel(ctx)
end

---------------------------------------------------------------- reveal

local function stars(level: number): string
	return string.rep("★", level) .. string.rep("☆", 4 - level)
end

-- The card for a cleaned dusty relic: its name, rarity and "into your collection".
local function showRelicCard(ctx: any, result: { [string]: any })
	local view = ctx.view
	local art = ArtifactConfig.ById[ctx.relic]
	local rarity = Rarity.get(art.Rarity)
	view.CardGrade.Text = "RELIC CLEANED"
	view.CardGrade.TextColor3 = rarity.Color
	view.CardStars.Text = ""
	view.CardOre.Text = `{art.Name}  ({rarity.Name})`
	view.CardOre.TextColor3 = rarity.Color
	view.CardValue.Text = if result.Collected then "Added to your collection" else "Your relic is safe"
	view.CardDetail.Text = string.format(
		"Chisel %d%%  ·  Scrape %d%%  ·  Polish %d%%",
		math.floor((result.Chisel or 0) * 100),
		math.floor((result.Scrape or 0) * 100),
		math.floor((result.Polish or 0) * 100)
	)
	view.Card.Visible = true
	local pop = view.Card:FindFirstChild("Pop") :: UIScale
	pop.Scale = 0.2
	TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	ctx.flash(rarity.Color, 0.4)
end

local function showCard(ctx: any, result: { [string]: any })
	if ctx.relic and result.Relic == ctx.relic then
		showRelicCard(ctx, result)
		return
	end
	local view = ctx.view
	local grade = ItemData.GradeById[result.Grade] or ItemData.Grades[1]
	view.CardGrade.Text = string.upper(grade.Name)
	view.CardGrade.TextColor3 = grade.Color
	view.CardStars.Text = stars(grade.Level)
	view.CardOre.Text = `{ctx.ore.Name}  ({ctx.rarity.Name})`
	view.CardOre.TextColor3 = ctx.rarity.Color
	-- what Tobin pays for it with the player's sell bonus (result.Value is the base price)
	local worth = math.floor((result.Value or 0) * StateController.sellMult() + 0.5)
	view.CardValue.Text = `Worth {Format.commas(worth)} coins`
	view.CardDetail.Text = string.format(
		"Chisel %d%%  ·  Scrape %d%%  ·  Polish %d%%  ·  Chips %d",
		math.floor((result.Chisel or 0) * 100),
		math.floor((result.Scrape or 0) * 100),
		math.floor((result.Polish or 0) * 100),
		result.Chips or 0
	)
	-- cleans in a row: a little chip on the card (nothing saved, no reward)
	local now = os.clock()
	streak = CleaningView.nextStreak(streak, lastCleanAt, now)
	lastCleanAt = now
	CleaningView.setStreak(view, streak)
	-- the grade stamp lands on the ore itself
	local face = ctx.shell.WorkCF
	local plate, stampPop = RevealFx.stamp(ctx.folder, face, OreShellBuilder.CoreFront + 1.2, grade.Name, grade.Color)
	stampPop.Scale = RevealFx.StampFrom
	TweenService:Create(stampPop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.16, function()
		if plate.Parent then
			Sfx.play("Place", plate.Position, 1.25)
			Vfx.burst("Dust", plate.Position, 4, grade.Color)
		end
	end)
	view.Card.Visible = true
	local pop = view.Card:FindFirstChild("Pop") :: UIScale
	pop.Scale = 0.2
	TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if grade.Id == "Flawless" then
		ctx.flash(grade.Color, 0.6)
		Sfx.play("Discovery", nil, 1.3)
	end
end

local function reveal(ctx: any)
	ctx.revealing = true
	local view = ctx.view
	CleaningView.setReveal(view, "Let's see what you uncovered...")
	view.Progress.Text = ""
	view.Hint.Text = ""
	-- nothing to leave any more (cancel() ignores it now): only Collect works from here
	view.Leave.Parent.Visible = false
	ContextActionService:UnbindAction("TerraForgeCleanBack")
	for _, model in ctx.tools do
		placeTool(model, CFrame.new(0, -1000, 0), false)
	end
	local order = ctx.rarity.Order
	local shell = ctx.shell
	-- everything that is the ore core rises out of the rock and spins
	local parts: { BasePart } = {}
	for _, p in shell.Core do
		table.insert(parts, p)
	end
	for _, p in shell.CoreRim do
		table.insert(parts, p)
		-- the glowing outline steps back so the polished ore itself reads
		TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 0.6 }):Play()
	end
	for _, p in shell.Fragile do
		if p.Parent then
			table.insert(parts, p)
		end
	end
	-- a relic: the ore stand-in fades and the real relic rises and spins instead
	if ctx.relic and #ctx.relicParts > 0 then
		for _, p in parts do
			p.Transparency = 1
		end
		parts = {}
		for _, p in ctx.relicParts do
			p.Transparency = (p:GetAttribute("ShowAs") :: number?) or 0
			table.insert(parts, p)
		end
	end
	local pivot = shell.WorkCF * CFrame.new(0, 0, OreShellBuilder.CoreFront - 0.4)
	local offsets = {}
	for i, p in parts do
		offsets[i] = pivot:ToObjectSpace(p.CFrame)
	end
	local center = pivot.Position
	-- the ore's own glow takes over from the work light
	local workLight = ctx.folder:FindFirstChild("WorkLight")
	local workLamp = workLight and workLight:FindFirstChildOfClass("PointLight")
	if workLamp then
		TweenService:Create(workLamp, TweenInfo.new(0.4), { Brightness = 0.4 }):Play()
	end
	local holder = Geo.ball(ctx.folder, center, 0.1, ctx.ore.Glow, nil, toolProps({ Transparency = 1 }))
	local light = Instance.new("PointLight")
	light.Color = ctx.ore.Glow
	light.Range = 18
	light.Brightness = 0
	light.Shadows = false
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 6 + order }):Play()
	task.delay(0.35, function()
		TweenService:Create(light, TweenInfo.new(1.2), { Brightness = 2 }):Play()
	end)
	local burst = Geo.ball(ctx.folder, center, 0.6, ctx.rarity.Color, Enum.Material.Neon, toolProps({ Transparency = 0.2 }))
	TweenService
		:Create(
			burst,
			TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(7, 7, 7), Transparency = 1 }
		)
		:Play()
	local plan = RevealFx.plan(order)
	Vfx.burst("Burst", center, 20 + order * 10, ctx.rarity.Color)
	Vfx.burst("Glint", center, 12 + order * 4, ctx.ore.Glow)
	Sfx.play("Reveal")
	if plan.Fanfare then
		Sfx.play("Discovery", center, 0.8 + 0.1 * (order - 5))
	end
	-- softer on phones and tablets (the shared module still has the last word: Settings)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	CameraShake.add(plan.Shake * (if touchOnly then RevealFx.TouchShake else 1))
	ctx.flash(ctx.rarity.Color, plan.Flash)
	-- Legendary and Mythic: the view narrows for a moment while the spin slows down
	local fitFov = ctx.fitFov
	if plan.FovPunch > 0 and fitFov then
		local camera = ctx.camera
		TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = fitFov - plan.FovPunch,
		}):Play()
		task.delay(plan.Duration * 0.6, function()
			if not ctx.exited then
				TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
					FieldOfView = fitFov,
				}):Play()
			end
		end)
	end
	-- a shine bar slides across the ore once it has risen
	local _, sweepAt = RevealFx.sweep(ctx.folder, shell.WorkCF, OreShellBuilder.CoreFront + 1.1, 1.5)
	-- light rays for Legendary and Mythic
	local rays = {}
	if plan.Rays > 0 then
		local count = plan.Rays
		for i = 1, count do
			local ray = Geo.block(
				ctx.folder,
				CFrame.new(center),
				Vector3.new(0.12, 0.12, 6),
				ctx.rarity.Color,
				Enum.Material.Neon,
				toolProps({ Transparency = 0.3 })
			)
			table.insert(rays, { part = ray, angle = i / count * math.pi * 2 })
		end
	end
	local spins = plan.Spins
	local duration = plan.Duration
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		local p = math.clamp(elapsed / duration, 0, 1)
		local ease = 1 - (1 - RevealFx.warp(p, plan.SlowMo)) ^ 3
		sweepAt((elapsed - RevealFx.SweepDelay) / RevealFx.SweepTime)
		local lift = math.min(1, p * 2.2)
		lift = 1 - (1 - lift) ^ 2
		local cf = pivot * CFrame.new(0, 0.2 * lift, 0.9 * lift) * CFrame.Angles(0, 0, ease * spins * math.pi * 2)
		for i, part in parts do
			if part.Parent then
				part.CFrame = cf * offsets[i]
			end
		end
		for _, r in rays do
			local a = r.angle + p * 1.5
			local dir = shell.WorkCF:VectorToWorldSpace(Vector3.new(math.cos(a), math.sin(a), 0.15))
			r.part.CFrame = CFrame.lookAt(center + dir * 3.2, center + dir * 4)
			r.part.Transparency = 0.3 + 0.7 * p
		end
		if p >= 1 then
			connection:Disconnect()
		end
	end)
	table.insert(ctx.connections, connection)
	-- grade card once the server answered
	task.delay(0.6, function()
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
		showCard(ctx, result)
		local function collect()
			Sfx.play("UIClick")
			exit(ctx)
		end
		table.insert(ctx.connections, view.Collect.Activated:Connect(collect))
		ContextActionService:BindAction("TerraForgeCleanCollect", function(_, state)
			if state == Enum.UserInputState.Begin then
				collect()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.E, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	end)
end

---------------------------------------------------------------- main flow

local function run(ctx: any)
	enter(ctx)
	table.insert(
		ctx.connections,
		ctx.view.Leave.Activated:Connect(function()
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
			ctx.connections,
			humanoid.Died:Connect(function()
				cancel(ctx)
			end)
		)
	end
	table.insert(
		ctx.connections,
		RunService.RenderStepped:Connect(function(dt)
			ctx.pointer:update(dt)
			local view = ctx.view
			if ctx.pointer.Kind ~= ctx.hintKind then
				ctx.hintKind = ctx.pointer.Kind
				if not ctx.revealing and not leaveConfirming(ctx) then
					view.Hint.Text = HINTS[ctx.pointer.Kind] or HINTS.Mouse
				end
				updateButtonLabels(ctx)
			end
			if ctx.pointer.Kind == "Gamepad" then
				view.Cursor.Visible = true
				local inset = GuiService:GetGuiInset()
				local p = ctx.pointer.Position - inset
				local scale = (view.Gui:FindFirstChild("Scale") :: UIScale).Scale
				view.Cursor.Position = UDim2.fromOffset(p.X / scale, p.Y / scale)
			else
				view.Cursor.Visible = false
			end
			if ctx.step and not ctx.revealing then
				local ok, err = pcall(function()
					if ctx.step:update(dt) then
						ctx.stepDone = true
					end
				end)
				if not ok then
					warn("[Cleaning] step error: " .. tostring(err))
				end
			end
			if not ctx.station.Parent then
				cancel(ctx)
			end
		end)
	)
	-- every wait in this flow is a ClientPauses value: the server's timeline check expects them
	task.wait(pauses.Intro)
	CleaningView.setMeter(ctx.view, 1)
	for index, def in STEPS do
		if ctx.cancelled or ctx.exited then
			return
		end
		CleaningView.setStep(ctx.view, index, def.Title, def.Text)
		Sfx.play("UIClick", nil, 0.8)
		ctx.stepIndex = index
		ctx.stepDone = false
		ctx.step = def.Module.new(ctx)
		while not ctx.stepDone and not ctx.cancelled and not ctx.exited do
			task.wait()
		end
		if ctx.cancelled or ctx.exited then
			return
		end
		ctx.stepScores[index] = ctx.step:liveScore()
		ctx.step:destroy()
		ctx.step = nil
		task.wait(pauses.StepGap)
	end
	if ctx.cancelled or ctx.exited then
		return
	end
	-- done: send the recording, then the big reveal
	Net.send("CleanSubmit", ctx.Id, ctx.submission)
	reveal(ctx)
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
		if not result.Ok and not ctx.revealing then
			ctx.feedback(result.Reason or "Cleaning cancelled.", Theme.Bad)
			task.delay(1.5, function()
				exit(ctx)
			end)
		end
	end)
end

return CleaningController
