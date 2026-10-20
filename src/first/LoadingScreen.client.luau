--[[
	Terra Forge loading screen (runs before everything else).

	Draws LoadingView (the logo on a dark stone and lava backdrop, the
	progress bar, a rotating tip, SKIP) and follows LoadingConfig's stages:
	the game loaded, the character, the persistent models, the spawn area
	streamed in (RequestStreamAroundAsync in a pcall + the ground under the
	character) and ContentProvider's queue. It fades once everything is in,
	at LoadingConfig.MaxSeconds whatever happens, or when the player skips
	(click / tap, gamepad A or B, Space / Enter). When the fade starts,
	ReplicatedFirst gets the attribute LoadingDone = true (Util/Loading.luau
	waits on it). Whatever goes wrong in here, that attribute is still set.
]]

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LoadingConfig = require(script.Parent.LoadingConfig)
local LoadingView = require(script.Parent.LoadingView)

local player = Players.LocalPlayer

ReplicatedFirst:RemoveDefaultLoadingScreen()

local function markDone()
	ReplicatedFirst:SetAttribute(LoadingConfig.Attribute, true)
end

local function inputKind(): string
	local last = UserInputService:GetLastInputType()
	if string.find(last.Name, "Gamepad", 1, true) then
		return "Gamepad"
	elseif last == Enum.UserInputType.Touch then
		return "Touch"
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Mouse"
end

local function glyphImage(): string
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
	end)
	return if ok and type(image) == "string" then image else ""
end

-- every GuiObject's starting transparencies, so the fade can take them all to 1
type Fadeable = { Object: Instance, Props: { [string]: number } }
local function collectFade(root: Instance): { Fadeable }
	local list: { Fadeable } = {}
	for _, d in root:GetDescendants() do
		local props: { [string]: number } = {}
		if d:IsA("GuiObject") then
			props.BackgroundTransparency = d.BackgroundTransparency
		end
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			props.TextTransparency = d.TextTransparency
		elseif d:IsA("ImageLabel") then
			props.ImageTransparency = d.ImageTransparency
		elseif d:IsA("UIStroke") then
			props.Transparency = d.Transparency
		end
		if next(props) then
			table.insert(list, { Object = d, Props = props })
		end
	end
	return list
end

local function run()
	local playerGui = player:WaitForChild("PlayerGui")
	local refs = LoadingView.build()
	local function relayout()
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		LoadingView.apply(refs, LoadingConfig.layout(viewport, touch, GuiService:IsTenFootInterface()))
	end
	relayout()
	refs.Gui.Parent = playerGui
	local camera = Workspace.CurrentCamera
	local viewportConn = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout) else nil

	local started = os.clock()
	local state = LoadingConfig.newState()
	local skipped = false
	local tipFirst = math.random(1, #LoadingConfig.Tips)
	LoadingView.setTip(refs, LoadingConfig.Tips[tipFirst])

	-- the persistent models (the horizon, the planets)
	local loadedAt: number? = nil
	local persistentConn: RBXScriptConnection? = nil
	pcall(function()
		persistentConn = (Workspace :: any).PersistentLoaded:Connect(function()
			state.Persistent = true
		end)
	end)

	-- ask for the spawn area once the character is there (or the town spawn)
	local streamAsked = false
	local streamDone = false
	local function askStream(at: Vector3)
		if streamAsked then
			return
		end
		streamAsked = true
		task.spawn(function()
			pcall(function()
				player:RequestStreamAroundAsync(at, LoadingConfig.StreamTimeout)
			end)
			streamDone = true
		end)
	end

	local function groundUnder(root: BasePart): boolean
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local character = player.Character
		params.FilterDescendantsInstances = if character then { character } else {}
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -LoadingConfig.GroundProbe, 0), params)
		return hit ~= nil
	end

	-- SKIP: a click / tap on the button, gamepad A / B / Start, Space / Enter
	local skipConn = refs.Skip.Activated:Connect(function()
		if LoadingConfig.canSkip(os.clock() - started) then
			skipped = true
		end
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(input: InputObject)
		local code = input.KeyCode
		if
			code == Enum.KeyCode.ButtonA
			or code == Enum.KeyCode.ButtonB
			or code == Enum.KeyCode.ButtonStart
			or code == Enum.KeyCode.Space
			or code == Enum.KeyCode.Return
		then
			if LoadingConfig.canSkip(os.clock() - started) then
				skipped = true
			end
		end
	end)

	-- a few embers rising from the lava (half on phones)
	local emberCount = if UserInputService.TouchEnabled then 4 else 8
	local embers: { { Frame: Frame, Speed: number, Phase: number } } = {}
	for i = 1, emberCount do
		local ember = Instance.new("Frame")
		ember.Name = "Ember"
		ember.BorderSizePixel = 0
		ember.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(255, 186, 70) else Color3.fromRGB(255, 120, 40)
		ember.Size = UDim2.fromOffset(6 + i % 3 * 2, 6 + i % 3 * 2)
		ember.ZIndex = 4
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = ember
		ember.Parent = refs.Embers
		table.insert(embers, { Frame = ember, Speed = 0.05 + (i % 4) * 0.015, Phase = i / emberCount })
	end

	local glyph = glyphImage()
	local shown = 0
	local last = os.clock()
	while true do
		local now = os.clock()
		local dt = now - last
		last = now
		local elapsed = now - started

		state.GameLoaded = game:IsLoaded()
		if state.GameLoaded and not loadedAt then
			loadedAt = now
		end
		if loadedAt and now - loadedAt >= LoadingConfig.PersistentGrace then
			state.Persistent = true
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		state.Character = root ~= nil and root:IsA("BasePart")
		if root and root:IsA("BasePart") then
			askStream(root.Position)
			local ground = groundUnder(root)
			state.Spawn = (if streamDone then 0.5 else 0) + (if ground then 0.5 else 0)
		end
		local queue = ContentProvider.RequestQueueSize
		state.AssetsLeft = queue
		state.AssetsPeak = math.max(state.AssetsPeak, queue)

		local target = LoadingConfig.progress(state)
		local finish = LoadingConfig.shouldFinish(state, elapsed, skipped)
		shown = if finish then 1 else LoadingConfig.smooth(shown, target, dt)
		LoadingView.setProgress(refs, shown, finish)
		LoadingView.setTip(refs, LoadingConfig.Tips[LoadingConfig.tipIndex(tipFirst, elapsed)])
		LoadingView.showSkip(refs, LoadingConfig.canSkip(elapsed) and not finish, inputKind(), glyph)
		for _, e in embers do
			local t = (elapsed * e.Speed + e.Phase) % 1
			e.Frame.Position = UDim2.fromScale(0.05 + ((e.Phase * 7.3) % 1) * 0.9 + math.sin(elapsed + e.Phase * 6) * 0.01, 1 - t)
			e.Frame.BackgroundTransparency = 0.15 + t * 0.85
		end
		if finish then
			break
		end
		RunService.RenderStepped:Wait()
	end

	-- the game may start: the gate opens as the fade begins
	markDone()
	local fades = collectFade(refs.Gui)
	local info = TweenInfo.new(LoadingConfig.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, f in fades do
		local goal: { [string]: number } = {}
		for prop in f.Props do
			goal[prop] = 1
		end
		TweenService:Create(f.Object, info, goal):Play()
	end
	task.wait(LoadingConfig.FadeTime + 0.05)
	skipConn:Disconnect()
	keyConn:Disconnect()
	if viewportConn then
		viewportConn:Disconnect()
	end
	if persistentConn then
		persistentConn:Disconnect()
	end
	refs.Gui:Destroy()
end

local ok, err = pcall(function(): any
	run()
	return nil
end)
if not ok then
	warn("[LoadingScreen] " .. tostring(err))
	local gui = player:FindFirstChild("PlayerGui")
	local leftover = gui and gui:FindFirstChild("LoadingScreen")
	if leftover then
		leftover:Destroy()
	end
end
markDone()
