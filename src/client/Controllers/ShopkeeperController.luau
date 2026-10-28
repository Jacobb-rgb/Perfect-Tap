--[[
	ShopkeeperController: a big golem behind every shop counter, a different
	one per shop, with emotes (owner 2026-10-24; Config/ShopkeeperConfig,
	Builders/GolemKeeper, Moves/GolemEmotes).

	- Every keeper spot (an Attachment tagged ShopkeeperSpot on a counter,
	  attribute Shop) that streams in is remembered; a spot that streams out
	  takes its golem along.
	- Every CheckEvery seconds: the nearest spot within ShowDistance of the
	  player that has no golem gets one built (GolemKeeper: the shop's kind
	  and size, feet on the spot, facing its LookVector; one build a check, so
	  arriving at the plaza spreads them out); past HideDistance a golem goes
	  again. Only this client has them: nothing more streams to phones, and a
	  phone draws only the one or two golems near the player.
	- Life (golems within AnimateDistance, one BulkMoveTo each frame for all):
	  the idle breath and sway; it turns toward the player inside
	  LookDistance; walking up inside GreetDistance makes it wave and say
	  hello (once per GreetCooldown); now and then (EmoteEvery) it hops,
	  spins, dances, bows or waves by itself. A golem that leaves
	  AnimateDistance (or when the player has no character) is put back in
	  its rest pose once and then left alone.
	- Thanks: a sale (Earned of Source "Sell") whose Position is within
	  ThanksDistance of the Sell golem's feet (its counter or its SellBin; a
	  Sell Box's popups on the plots are far away), or a bought item at a
	  shop (ShopkeeperConfig.buyShops: the purchase answers the shop
	  controllers handle) with the player within ThanksDistance of that
	  shop's golem, makes it cheer, say thanks and throw a gold burst; once
	  per ThanksCooldown (one sale, one thanks).
	- No snap: a hello or a thanks that comes during a Hop, Spin or Dance
	  waits until it is over; one that cuts into a Wave, Bow or Cheer blends
	  in over BlendSeconds.
	- Reduce Motion (UI/Motion.reduced: the game's SETTINGS toggle or Roblox's
	  own): only Bow and Wave by itself (no Spin, Hop or Dance), a Cheer
	  without its jump, the bubble shows without its pop, a smaller burst.
	  The idle breath and sway stay.
	- Light budget: only the nearest golem inside LightDistance has its soft
	  light on (the shops are dark; phones), unless its shop is bright
	  inside: ShopkeeperConfig.lit. A keeper has no other light (GolemKeeper).
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
local Motion = require(script.Parent.Parent.UI.Motion)

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
	Queued: string?, -- a hello or thanks waiting for a big move to end
	Pose: GolemEmotes.Pose?, -- the last pose shown (a cut-in blends from it)
	BlendFrom: GolemEmotes.Pose?,
	BlendAt: number,
	Still: boolean, -- in its rest pose, not animated (far away)
	Near: boolean,
	GreetedAt: number,
	ThankedAt: number,
	Lines: number,
	Seed: number,
	Bubble: BillboardGui?,
}

local spots: { [Attachment]: boolean } = {}
local keepers: { [Attachment]: Keeper } = {}
local folder: Folder? = nil

-- (the live golems, for the Lune specs: they put stand-ins in here)
ShopkeeperController.keepers = keepers

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

-- The move a golem does by itself now (Reduce Motion: only Bow or Wave).
function ShopkeeperController.pickMove(): string
	local own = GolemEmotes.own(Motion.reduced())
	return own[math.random(1, #own)]
end

local function play(k: Keeper, emote: string, now: number)
	local running = k.Emote
	-- cutting into a running emote: blend from where the golem is
	if running and k.Pose and now - k.EmoteAt < (GolemEmotes.Duration[running] or 0) then
		k.BlendFrom = k.Pose
		k.BlendAt = now
	end
	k.Emote = emote
	k.EmoteAt = now
	k.NextEmote = nextEmoteAt(now + (GolemEmotes.Duration[emote] or 0))
end

-- A hello or a thanks: now, or once a running Hop / Spin / Dance is over
-- (a thanks outranks a hello waiting with it).
local function react(k: Keeper, emote: string, now: number)
	local running = k.Emote
	if running and GolemEmotes.Big[running] and now - k.EmoteAt < (GolemEmotes.Duration[running] or 0) then
		if emote == "Cheer" or k.Queued == nil then
			k.Queued = emote
		end
		return
	end
	play(k, emote, now)
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
		Queued = nil,
		Pose = nil,
		BlendFrom = nil,
		BlendAt = 0,
		Still = true, -- (built in its rest pose)
		Near = false,
		GreetedAt = -math.huge,
		ThankedAt = -math.huge,
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

-- Takes the far golems away and builds the nearest missing one (one build a
-- check: no frame builds four golems at once when the player arrives).
local function refresh()
	local me = playerRoot()
	local from = if me then me.Position else Workspace.CurrentCamera.Focus.Position
	local pending: Attachment? = nil
	local pendingDistance = math.huge
	for spot in spots do
		local shown = keepers[spot] ~= nil
		local streamed = spot:IsDescendantOf(Workspace)
		local distance = if streamed then (spot.WorldPosition - from).Magnitude else math.huge
		local wanted = streamed and ShopkeeperConfig.wanted(distance, shown)
		if wanted and not shown then
			if distance < pendingDistance then
				pending, pendingDistance = spot, distance
			end
		elseif shown and not wanted then
			removeKeeper(spot)
		end
	end
	if pending then
		addKeeper(pending)
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
	local calm = Motion.reduced()
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Size = UDim2.fromScale(8, 1.6) -- studs: it shrinks with distance like the world
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + 2.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local scale = Instance.new("UIScale")
	scale.Scale = if calm then 1 else 0.5 -- (Reduce Motion: no pop)
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
	if not calm then
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(ShopkeeperConfig.BubbleSeconds, function()
		if k.Bubble ~= gui then
			return
		end
		k.Bubble = nil
		if Motion.reduced() then
			gui:Destroy()
			return
		end
		local out = TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		out.Completed:Once(function()
			gui:Destroy()
		end)
		out:Play()
	end)
end

---------------------------------------------------------------- thanks

-- The golem of one of `shops` nearest `at` that may say thanks at `now`.
local function thanker(shops: { string }, at: Vector3, now: number): Keeper?
	local best: Keeper? = nil
	local bestDistance = math.huge
	for _, k in keepers do
		local d = ShopkeeperConfig.thanksDistance(k.Shop, k.Feet, k.ThankedAt, shops, at, now)
		if d and d < bestDistance then
			best, bestDistance = k, d
		end
	end
	return best
end

local function thank(k: Keeper, now: number)
	k.ThankedAt = now
	react(k, "Cheer", now)
	k.Burst:Emit(if Motion.reduced() then ShopkeeperConfig.BurstCalm else ShopkeeperConfig.BurstCount)
	say(k, ShopkeeperConfig.line(k.Shop, "Thanks", k.Lines))
	k.Lines += 1
end

-- An Earned popup: a sale at the Sell golem's counter or bin makes it cheer
-- (`now`: os.clock(), the specs pass their own).
function ShopkeeperController.onEarned(payload: any, now: number?)
	if type(payload) ~= "table" or payload.Source ~= "Sell" or typeof(payload.Position) ~= "Vector3" then
		return
	end
	local at = now or os.clock()
	local k = thanker(ShopkeeperConfig.SellShops, payload.Position, at)
	if k then
		thank(k, at)
	end
end

-- A purchase answer (`event`: ShopResult, VaultResult, ActionResult,
-- BackpackResult): a bought item makes that shop's golem cheer when the player is at it.
function ShopkeeperController.onBought(event: string, payload: any, now: number?)
	local shops = ShopkeeperConfig.buyShops(event, payload)
	local me = playerRoot()
	if not shops or not me then
		return
	end
	local at = now or os.clock()
	local k = thanker(shops, me.CFrame.Position, at)
	if k then
		thank(k, at)
	end
end

---------------------------------------------------------------- every frame

local function step(dt: number)
	local me = playerRoot()
	local now = os.clock()
	local calm = Motion.reduced()
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
			-- far away (or no character): back to its rest pose once, then left alone
			if not k.Still then
				k.Still = true
				k.Emote, k.Queued, k.BlendFrom, k.Pose = nil, nil, nil, nil
				k.Yaw = 0
				local rest = GolemKeeper.frames(k.Rig, k.Feet, GolemEmotes.neutral(), 0)
				table.move(k.Rig.Parts, 1, #k.Rig.Parts, #parts + 1, parts)
				table.move(rest, 1, #rest, #frames + 1, frames)
			end
			continue
		end
		k.Still = false
		-- the hello when the player walks up (not every frame he stays close)
		local near = distance < ShopkeeperConfig.GreetDistance
		if near and not k.Near and now - k.GreetedAt > ShopkeeperConfig.GreetCooldown then
			k.GreetedAt = now
			react(k, "Wave", now)
			say(k, ShopkeeperConfig.line(k.Shop, "Hello", k.Lines))
			k.Lines += 1
		end
		k.Near = near
		-- a finished emote ends (a hello or thanks that waited for it plays now);
		-- now and then a move by itself
		local emote = k.Emote
		if emote and now - k.EmoteAt > (GolemEmotes.Duration[emote] or 0) then
			k.Emote = nil
			local queued = k.Queued
			if queued then
				k.Queued = nil
				play(k, queued, now)
			end
		end
		if not k.Emote and now >= k.NextEmote then
			play(k, ShopkeeperController.pickMove(), now)
		end
		-- it turns toward the player (or back to straight ahead)
		local want = if me and distance < ShopkeeperConfig.LookDistance then ShopkeeperConfig.lookYaw(k.Feet, me.Position) else 0
		k.Yaw += (want - k.Yaw) * turn
		local pose = GolemEmotes.pose(k.Emote, now - k.EmoteAt, now + k.Seed, calm)
		local from = k.BlendFrom
		if from then
			local w = (now - k.BlendAt) / ShopkeeperConfig.BlendSeconds
			if w < 1 then
				pose = GolemEmotes.mix(from, pose, w)
			else
				k.BlendFrom = nil
			end
		end
		k.Pose = pose
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
	Net.listen("Earned", function(payload: any)
		ShopkeeperController.onEarned(payload)
	end)
	for _, event in { "ShopResult", "VaultResult", "ActionResult", "BackpackResult" } do
		Net.listen(event, function(payload: any)
			ShopkeeperController.onBought(event, payload)
		end)
	end
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
