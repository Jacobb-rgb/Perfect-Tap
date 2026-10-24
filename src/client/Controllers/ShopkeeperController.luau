--[[
	ShopkeeperController: the owner's avatar behind every shop counter (owner
	2026-10-24: one guy for every shop, from his skin; Config/ShopkeeperConfig).

	- ShopkeeperService puts ONE avatar model in ReplicatedStorage
	  (TemplateName). Every keeper spot (an Attachment tagged ShopkeeperSpot
	  on a counter, attribute Shop) that streams in gets a local clone of it;
	  a spot that streams out takes its keeper along. A new template (the
	  server built it again) replaces every keeper. The clones live only on
	  this client: nothing more streams to the phones.
	- Placement: the clone scaled to ShopkeeperConfig.scale(shop), its feet
	  (the lowest body part, not the accessories) on the spot, facing the
	  spot's LookVector.
	- Life: Roblox's idle loops; the head turns toward the player inside
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

local keepers: { [Attachment]: Keeper } = {}
local folder: Folder? = nil
local template: Model? = nil

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

-- The keeper's feet height under his root: the lowest body part's bottom
-- (accessories, hair or wings, don't count).
local function feetOffset(model: Model, root: BasePart): number
	local bottom = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root and not d:FindFirstAncestorWhichIsA("Accoutrement") then
			bottom = math.min(bottom, d.Position.Y - d.Size.Y / 2)
		end
	end
	return if bottom < math.huge then root.Position.Y - bottom else 3
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
	local source = template
	if not source or not spot:IsDescendantOf(Workspace) then
		return
	end
	local shop = spot:GetAttribute("Shop")
	local shopId = if type(shop) == "string" then shop else ""
	local model = source:Clone()
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		model:Destroy()
		return
	end
	model.Name = "Shopkeeper_" .. shopId
	model.PrimaryPart = root
	pcall(function()
		model:ScaleTo(ShopkeeperConfig.scale(shopId))
	end)
	-- feet on the spot, facing the customers (the root goes there, whatever the pivot)
	model:PivotTo(CFrame.new())
	local lift = feetOffset(model, root)
	local rootToPivot = root.CFrame:ToObjectSpace(model:GetPivot())
	model:PivotTo(spot.WorldCFrame * CFrame.new(0, lift, 0) * rootToPivot)

	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local head = model:FindFirstChild("Head")
	local torso = if r6 then model:FindFirstChild("Torso") else head
	local neck = if torso then torso:FindFirstChild("Neck") else nil
	-- the soft light in front of his chest
	local lamp = Instance.new("Attachment")
	lamp.Name = "FaceLight"
	lamp.Position = ShopkeeperConfig.FaceLight.Offset * model:GetScale()
	local light = Instance.new("PointLight")
	light.Range = ShopkeeperConfig.FaceLight.Range
	light.Brightness = ShopkeeperConfig.FaceLight.Brightness
	light.Color = ShopkeeperConfig.FaceLight.Color
	light.Shadows = false
	light.Parent = lamp
	lamp.Parent = root
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	model.Parent = container()

	local ids = if r6 then ShopkeeperConfig.Animations.R6 else ShopkeeperConfig.Animations.R15
	local idle = animation(animator, ids.Idle, true, Enum.AnimationPriority.Idle)
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
		Wave = animation(animator, ids.Wave, false, Enum.AnimationPriority.Action),
		Cheer = animation(animator, ids.Cheer, false, Enum.AnimationPriority.Action),
		Near = false,
		GreetedAt = -math.huge,
		Lines = math.random(1, 4),
		Bubble = nil,
	}
end

local function rebuildAll()
	for _, spot in CollectionService:GetTagged(ShopkeeperConfig.Tag) do
		if spot:IsA("Attachment") then
			addKeeper(spot)
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

local function playerRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
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
			-- turned about the torso's up axis at the neck (the same for R6 and R15)
			local base = k.NeckC0
			neck.C0 = CFrame.new(base.Position) * CFrame.Angles(0, k.Yaw, 0) * CFrame.Angles(k.Pitch, 0, 0) * base.Rotation
		end
	end
end

---------------------------------------------------------------- lifecycle

local function useTemplate(child: Instance)
	if child.Name == ShopkeeperConfig.TemplateName and child:IsA("Model") then
		template = child
		rebuildAll()
	end
end

function ShopkeeperController.start()
	ReplicatedStorage.ChildAdded:Connect(useTemplate)
	local existing = ReplicatedStorage:FindFirstChild(ShopkeeperConfig.TemplateName)
	if existing then
		useTemplate(existing)
	end
	CollectionService:GetInstanceAddedSignal(ShopkeeperConfig.Tag):Connect(function(spot: Instance)
		if spot:IsA("Attachment") then
			addKeeper(spot)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(ShopkeeperConfig.Tag):Connect(function(spot: Instance)
		if spot:IsA("Attachment") then
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
	RunService.Heartbeat:Connect(step)
end

return ShopkeeperController
