--[[
	ShopkeeperController: a big golem behind every shop counter, a different
	one per shop, with emotes (owner 2026-10-24; Config/ShopkeeperConfig,
	Builders/GolemKeeper, Moves/GolemEmotes).

	- Every keeper spot (an Attachment tagged ShopkeeperSpot on a counter,
	  attribute Shop) that streams in is remembered; a spot that streams out
	  takes its golem along.
	- Every CheckEvery seconds: a spot within ShowDistance of the player gets
	  its golem built (GolemKeeper: the shop's kind and size, feet on the
	  spot, facing its LookVector); past HideDistance the golem goes again.
	  Only this client has them: nothing more streams to phones, and a phone
	  draws only the one or two golems near the player.
	- Life (golems within AnimateDistance, one BulkMoveTo each frame for all):
	  the idle breath and sway; it turns toward the player inside
	  LookDistance; walking up inside GreetDistance makes it wave and say
	  hello (once per GreetCooldown); a buy (a Notify of Kind "Reward") or a
	  sale (Earned from "Sell") inside ThanksDistance makes the nearest one
	  cheer, say thanks and throw a gold burst; now and then (EmoteEvery) it
	  hops, spins, dances, bows or waves by itself.
	- Light budget: only the nearest golem inside LightDistance has its soft
	  light on (the shops are dark; phones), unless its shop is bright inside
	  (ShopkeeperConfig.lit).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BubbleTheme = require(Shared.Config.BubbleTheme)
local GolemEmotes = require(Shared.Moves.GolemEmotes)
local GolemKeeper = require(Shared.Builders.GolemKeeper)
local Net = require(Shared.Net)
local ShopkeeperConfig = require(Shared.Config.ShopkeeperConfig)

local ShopkeeperController = {}

type Keeper = {
	Spot: Attachment,
	Shop: string,
	Feet: CFrame,
	Rig: GolemKeeper.Rig,
	Head: BasePart?,
	Light: PointLight,
	Burst: ParticleEmitter,
	Lit: boolean,
	Yaw: number,
	Emote: string?,
	EmoteAt: number,
	NextEmote: number,
	Near: boolean,
	GreetedAt: number,
	Lines: number,
	Seed: number,
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

local function nextEmoteAt(now: number): number
	local range = ShopkeeperConfig.EmoteEvery
	return now + range[1] + math.random() * (range[2] - range[1])
end

local function play(k: Keeper, emote: string, now: number)
	k.Emote = emote
	k.EmoteAt = now
	k.NextEmote = nextEmoteAt(now + (GolemEmotes.Duration[emote] or 0))
end

local function removeKeeper(spot: Attachment)
	local k = keepers[spot]
	if k then
		keepers[spot] = nil
		k.Rig.Model:Destroy()
	end
end

local function addKeeper(spot: Attachment)
	removeKeeper(spot)
	if not spot:IsDescendantOf(Workspace) then
		return
	end
	local shop = spot:GetAttribute("Shop")
	local shopId = if type(shop) == "string" then shop else ""
	local kind, size = ShopkeeperConfig.golem(shopId)
	local feet = spot.WorldCFrame
	local rig = GolemKeeper.build(kind, feet, size)
	local model = rig.Model
	model.Name = "Shopkeeper_" .. shopId
	local body = model:FindFirstChild("Body")
	local head = model:FindFirstChild("Head")
	local holder: BasePart = if body and body:IsA("BasePart") then body else rig.Parts[1]

	-- the soft light in front of it (on only for the nearest golem)
	local glow = ShopkeeperConfig.FaceLight
	local lamp = Instance.new("Attachment")
	lamp.Name = "FaceLight"
	lamp.Parent = holder
	lamp.WorldCFrame = feet * CFrame.new(0, rig.Height * glow.Up, -glow.Ahead)
	local light = Instance.new("PointLight")
	light.Range = glow.Range
	light.Brightness = glow.Brightness
	light.Color = glow.Color
	light.Shadows = false
	light.Enabled = false
	light.Parent = lamp
	-- the gold burst of its thanks (Rate 0: emitted)
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "CoinBurst"
	burst.Texture = ShopkeeperConfig.Sparkle
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.7, 1.1)
	burst.Speed = NumberRange.new(9, 13)
	burst.SpreadAngle = Vector2.new(50, 50)
	burst.Acceleration = Vector3.new(0, -18, 0)
	burst.EmissionDirection = Enum.NormalId.Top
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 214, 70), Color3.fromRGB(255, 160, 30))
	burst.LightEmission = 0.8
	burst.LightInfluence = 0
	burst.Parent = if head and head:IsA("BasePart") then head else holder
	model.Parent = container()

	local now = os.clock()
	keepers[spot] = {
		Spot = spot,
		Shop = shopId,
		Feet = feet,
		Rig = rig,
		Head = if head and head:IsA("BasePart") then head else nil,
		Light = light,
		Burst = burst,
		Lit = false,
		Yaw = 0,
		Emote = nil,
		EmoteAt = 0,
		NextEmote = nextEmoteAt(now),
		Near = false,
		GreetedAt = -math.huge,
		Lines = math.random(1, 4),
		Seed = math.random() * 10,
		Bubble = nil,
	}
end

local function playerRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- Builds the golems near the player, takes the far ones away.
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
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Size = UDim2.fromScale(8, 1.6) -- studs: it shrinks with distance like the world
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + 2.2, 0)
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

-- A buy or a sale: the nearest golem inside ThanksDistance cheers.
local function thank()
	local me = playerRoot()
	if not me then
		return
	end
	local best: Keeper? = nil
	local bestDistance = ShopkeeperConfig.ThanksDistance
	for _, k in keepers do
		local d = (k.Feet.Position - me.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = k, d
		end
	end
	if best then
		play(best, "Cheer", os.clock())
		best.Burst:Emit(ShopkeeperConfig.BurstCount)
		say(best, ShopkeeperConfig.line(best.Shop, "Thanks", best.Lines))
		best.Lines += 1
	end
end

---------------------------------------------------------------- every frame

local function step(dt: number)
	local me = playerRoot()
	local now = os.clock()
	local turn = 1 - math.exp(-ShopkeeperConfig.LookSpeed * dt)
	-- the light budget: one light, on the nearest golem inside LightDistance
	local nearest: Keeper? = nil
	local nearestDistance = ShopkeeperConfig.LightDistance
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for _, k in keepers do
		local distance = if me then (k.Feet.Position - me.Position).Magnitude else math.huge
		if distance < nearestDistance then
			nearest, nearestDistance = k, distance
		end
		if distance > ShopkeeperConfig.AnimateDistance then
			continue
		end
		-- the hello when the player walks up (not every frame he stays close)
		local near = distance < ShopkeeperConfig.GreetDistance
		if near and not k.Near and now - k.GreetedAt > ShopkeeperConfig.GreetCooldown then
			k.GreetedAt = now
			play(k, "Wave", now)
			say(k, ShopkeeperConfig.line(k.Shop, "Hello", k.Lines))
			k.Lines += 1
		end
		k.Near = near
		-- a move by itself now and then; a finished one ends
		local emote = k.Emote
		if emote and now - k.EmoteAt > (GolemEmotes.Duration[emote] or 0) then
			k.Emote = nil
		end
		if not k.Emote and now >= k.NextEmote then
			local own = GolemEmotes.OnTheirOwn
			play(k, own[math.random(1, #own)], now)
		end
		-- it turns toward the player (or back to straight ahead)
		local want = if me and distance < ShopkeeperConfig.LookDistance then ShopkeeperConfig.lookYaw(k.Feet, me.Position) else 0
		k.Yaw += (want - k.Yaw) * turn
		local pose = GolemEmotes.pose(k.Emote, now - k.EmoteAt, now + k.Seed)
		local placed = GolemKeeper.frames(k.Rig, k.Feet, pose, k.Yaw)
		table.move(k.Rig.Parts, 1, #k.Rig.Parts, #parts + 1, parts)
		table.move(placed, 1, #placed, #frames + 1, frames)
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for _, k in keepers do
		local lit = k == nearest and ShopkeeperConfig.lit(k.Shop)
		if lit ~= k.Lit then
			k.Lit = lit
			k.Light.Enabled = lit
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
