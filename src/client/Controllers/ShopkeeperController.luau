--[[
	ShopkeeperController: the owner's miner behind every shop counter (owner
	2026-10-24: one and the same keeper for every shop, exactly his 3D model;
	Config/ShopkeeperConfig, Builders/ShopkeeperBuilder).

	- Every keeper spot (an Attachment tagged ShopkeeperSpot on a counter,
	  attribute Shop) that streams in is remembered; a spot that streams out
	  takes its keeper along.
	- Every CheckEvery seconds: a spot within ShowDistance of the player gets
	  his keeper built (ShopkeeperBuilder at ShopkeeperConfig.scale(shop),
	  feet on the spot, facing its LookVector); past HideDistance the keeper
	  goes again. Only this client has them: nothing more streams to phones,
	  and a phone draws only the one or two keepers near the player.
	- Life: Roblox's R6 idle loops; the head turns toward the player inside
	  LookDistance (the neck joint, clamped); walking up inside GreetDistance
	  makes him wave and say hello (once per GreetCooldown); a buy (a Notify
	  of Kind "Reward") or a sale (Earned from "Sell") inside ThanksDistance
	  makes the nearest keeper cheer and say thanks.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BubbleTheme = require(Shared.Config.BubbleTheme)
local Net = require(Shared.Net)
local ShopkeeperBuilder = require(Shared.Builders.ShopkeeperBuilder)
local ShopkeeperConfig = require(Shared.Config.ShopkeeperConfig)

local ShopkeeperController = {}

type Keeper = {
	Spot: Attachment,
	Shop: string,
	Model: Model,
	Root: BasePart,
	Head: BasePart?,
	Neck: Motor6D?,
	NeckC0: CFrame,
	Yaw: number,
	Pitch: number,
	Wave: AnimationTrack?,
	Cheer: AnimationTrack?,
	Near: boolean,
	GreetedAt: number,
	Lines: number,
	Bubble: BillboardGui?,
}

local spots: { [Attachment]: boolean } = {}
local keepers: { [Attachment]: Keeper } = {}
local folder: Folder? = nil

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "Shopkeepers"
	f.Parent = Workspace
	folder = f
	return f
end

local function animation(animator: Animator, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(anim)
	end)
	if not ok then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	return track
end

local function removeKeeper(spot: Attachment)
	local k = keepers[spot]
	if k then
		keepers[spot] = nil
		k.Model:Destroy()
	end
end

local function addKeeper(spot: Attachment)
	removeKeeper(spot)
	if not spot:IsDescendantOf(Workspace) then
		return
	end
	local shop = spot:GetAttribute("Shop")
	local shopId = if type(shop) == "string" then shop else ""
	local scale = ShopkeeperConfig.scale(shopId)
	local model = ShopkeeperBuilder.build(spot.WorldCFrame, scale)
	model.Name = "Shopkeeper_" .. shopId
	local root = model.PrimaryPart :: BasePart
	local torso = model:FindFirstChild("Torso")
	local head = model:FindFirstChild("Head")
	local neck = if torso then torso:FindFirstChild("Neck") else nil

	-- the soft light in front of his chest
	local lamp = Instance.new("Attachment")
	lamp.Name = "FaceLight"
	lamp.Parent = root
	lamp.WorldCFrame = spot.WorldCFrame * CFrame.new(ShopkeeperConfig.FaceLight.Offset * scale)
	local light = Instance.new("PointLight")
	light.Range = ShopkeeperConfig.FaceLight.Range
	light.Brightness = ShopkeeperConfig.FaceLight.Brightness
	light.Color = ShopkeeperConfig.FaceLight.Color
	light.Shadows = false
	light.Parent = lamp
	model.Parent = container()

	local controller = model:FindFirstChildOfClass("AnimationController")
	local animator = if controller then controller:FindFirstChildOfClass("Animator") else nil
	local ids = ShopkeeperConfig.Animations
	local idle = if animator then animation(animator, ids.Idle, true, Enum.AnimationPriority.Idle) else nil
	if idle then
		-- every keeper a little out of step with the others
		idle:Play(0.2)
		idle.TimePosition = math.random() * math.max(idle.Length, 1)
	end
	keepers[spot] = {
		Spot = spot,
		Shop = shopId,
		Model = model,
		Root = root,
		Head = if head and head:IsA("BasePart") then head else nil,
		Neck = if neck and neck:IsA("Motor6D") then neck else nil,
		NeckC0 = if neck and neck:IsA("Motor6D") then neck.C0 else CFrame.identity,
		Yaw = 0,
		Pitch = 0,
		Wave = if animator then animation(animator, ids.Wave, false, Enum.AnimationPriority.Action) else nil,
		Cheer = if animator then animation(animator, ids.Cheer, false, Enum.AnimationPriority.Action) else nil,
		Near = false,
		GreetedAt = -math.huge,
		Lines = math.random(1, 4),
		Bubble = nil,
	}
end

local function playerRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- Builds the keepers near the player, takes the far ones away.
local function refresh()
	local me = playerRoot()
	local from = if me then me.Position else Workspace.CurrentCamera.Focus.Position
	for spot in spots do
		local shown = keepers[spot] ~= nil
		local wanted = spot:IsDescendantOf(Workspace) and ShopkeeperConfig.wanted((spot.WorldPosition - from).Magnitude, shown)
		if wanted and not shown then
			addKeeper(spot)
		elseif shown and not wanted then
			removeKeeper(spot)
		end
	end
end

---------------------------------------------------------------- the speech bubble

local function say(k: Keeper, text: string)
	local head = k.Head
	if not head then
		return
	end
	if k.Bubble then
		k.Bubble:Destroy()
	end
	local s = ShopkeeperConfig.scale(k.Shop)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Size = UDim2.fromScale(7.5 * s, 1.5 * s) -- studs: it shrinks with distance like the world
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.3 * s, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = gui
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.fromScale(0.5, 0.5)
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = BubbleTheme.White
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = BubbleTheme.Outline
	stroke.Thickness = 3
	stroke.Parent = bubble
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.9, 0.72)
	label.FontFace = BubbleTheme.Font
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = BubbleTheme.DarkInk
	label.Parent = bubble
	bubble.Parent = gui
	gui.Parent = head
	k.Bubble = gui
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(ShopkeeperConfig.BubbleSeconds, function()
		if k.Bubble ~= gui then
			return
		end
		local out = TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		out.Completed:Once(function()
			gui:Destroy()
		end)
		out:Play()
		k.Bubble = nil
	end)
end

local function greet(k: Keeper, now: number)
	k.GreetedAt = now
	if k.Wave then
		k.Wave:Play(0.15)
	end
	say(k, ShopkeeperConfig.line(k.Shop, "Hello", k.Lines))
	k.Lines += 1
end

-- A buy or a sale: the nearest keeper inside ThanksDistance cheers.
local function thank()
	local me = playerRoot()
	if not me then
		return
	end
	local best: Keeper? = nil
	local bestDistance = ShopkeeperConfig.ThanksDistance
	for _, k in keepers do
		local d = (k.Root.Position - me.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = k, d
		end
	end
	if best then
		if best.Cheer then
			best.Cheer:Play(0.15)
		end
		say(best, ShopkeeperConfig.line(best.Shop, "Thanks", best.Lines))
		best.Lines += 1
	end
end

---------------------------------------------------------------- every frame

local function step(dt: number)
	local me = playerRoot()
	local now = os.clock()
	local catchUp = 1 - math.exp(-ShopkeeperConfig.LookSpeed * dt)
	for _, k in keepers do
		local yaw, pitch = 0, 0
		local distance = math.huge
		if me then
			distance = (k.Root.Position - me.Position).Magnitude
			if distance < ShopkeeperConfig.LookDistance and k.Head then
				local eyes = me.Position + Vector3.new(0, 1.5, 0)
				yaw, pitch = ShopkeeperConfig.lookAngles(k.Root.CFrame, k.Head.Position, eyes)
			end
		end
		-- the hello when the player walks up (not every frame he stays close)
		local near = distance < ShopkeeperConfig.GreetDistance
		if near and not k.Near and now - k.GreetedAt > ShopkeeperConfig.GreetCooldown then
			greet(k, now)
		end
		k.Near = near
		-- the head eases toward the player (or back to straight ahead)
		local neck = k.Neck
		if neck and (math.abs(yaw - k.Yaw) > 1e-3 or math.abs(pitch - k.Pitch) > 1e-3) then
			k.Yaw += (yaw - k.Yaw) * catchUp
			k.Pitch += (pitch - k.Pitch) * catchUp
			-- turned about the torso's up axis at the neck
			local base = k.NeckC0
			neck.C0 = CFrame.new(base.Position) * CFrame.Angles(0, k.Yaw, 0) * CFrame.Angles(k.Pitch, 0, 0) * base.Rotation
		end
	end
end

---------------------------------------------------------------- lifecycle

function ShopkeeperController.start()
	local function added(spot: Instance)
		if spot:IsA("Attachment") then
			spots[spot] = true
		end
	end
	for _, spot in CollectionService:GetTagged(ShopkeeperConfig.Tag) do
		added(spot)
	end
	CollectionService:GetInstanceAddedSignal(ShopkeeperConfig.Tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(ShopkeeperConfig.Tag):Connect(function(spot: Instance)
		if spot:IsA("Attachment") then
			spots[spot] = nil
			removeKeeper(spot)
		end
	end)
	Net.listen("Notify", function(message: any)
		if type(message) == "table" and message.Kind == "Reward" then
			thank()
		end
	end)
	Net.listen("Earned", function(payload: any)
		if type(payload) == "table" and payload.Source == "Sell" then
			thank()
		end
	end)
	task.spawn(function()
		while true do
			xpcall(refresh, function(err: any)
				warn("[ShopkeeperController] " .. tostring(err))
			end)
			task.wait(ShopkeeperConfig.CheckEvery)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return ShopkeeperController
