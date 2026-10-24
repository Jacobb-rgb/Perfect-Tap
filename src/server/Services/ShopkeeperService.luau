--[[
	ShopkeeperService: builds the ONE shopkeeper avatar (the owner's own Roblox
	skin, owner 2026-10-24) that ShopkeeperController clones behind every shop
	counter (Config/ShopkeeperConfig).

	- Whose avatar: ShopkeeperConfig.ownerId (UserId set in the config, else
	  the game's creator when a user owns the game, else in Studio the first
	  player who joins = the one pressing Play).
	- Players:CreateHumanoidModelFromUserId (it yields: own thread, pcall'd,
	  retried Retries times with a doubling delay). A failure leaves the shops
	  without keepers; nothing else depends on them.
	- The model goes to ReplicatedStorage as TemplateName: scripts stripped,
	  every part unanchored except the HumanoidRootPart (the client animates
	  the joints), no collision, touch, queries or shadows, the Humanoid's
	  name and health bar hidden, its state machine off. ReplicatedStorage
	  holds it once; nothing of it is in the streamed map.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopkeeperConfig = require(Shared.Config.ShopkeeperConfig)

local ShopkeeperService = {}

-- (tests swap the avatar maker and the wait)
local makeAvatar: (userId: number) -> Model? = function(userId: number): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	return if ok then model else nil
end
local pause: (seconds: number) -> () = function(seconds: number)
	task.wait(seconds)
end

-- Makes `model` the still, harmless template the clients clone.
function ShopkeeperService.dress(model: Model, userId: number)
	model.Name = ShopkeeperConfig.TemplateName
	model:SetAttribute("UserId", userId)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			d.Massless = true
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		model:SetAttribute("Rig", if humanoid.RigType == Enum.HumanoidRigType.R6 then "R6" else "R15")
		pcall(function()
			humanoid.EvaluateStateMachine = false -- he never walks: no physics states
		end)
	end
	if root and root:IsA("BasePart") then
		model.PrimaryPart = root
	end
end

-- Builds the template for `userId` into `into` (default ReplicatedStorage;
-- true when it is there).
function ShopkeeperService.build(userId: number, into: Instance?): boolean
	if userId <= 0 then
		return false
	end
	local home: Instance = into or ReplicatedStorage
	local delay = ShopkeeperConfig.RetryDelay
	for attempt = 1, ShopkeeperConfig.Retries do
		local model = makeAvatar(userId)
		if model then
			ShopkeeperService.dress(model, userId)
			local old = home:FindFirstChild(ShopkeeperConfig.TemplateName)
			if old then
				old:Destroy()
			end
			model.Parent = home
			return true
		end
		if attempt < ShopkeeperConfig.Retries then
			pause(delay)
			delay *= 2
		end
	end
	warn(`[ShopkeeperService] no avatar for UserId {userId}: the shops stay without keepers`)
	return false
end

-- (tests swap the avatar maker and the wait)
function ShopkeeperService._setMaker(maker: (userId: number) -> Model?, wait: ((seconds: number) -> ())?)
	makeAvatar = maker
	if wait then
		pause = wait
	end
end

function ShopkeeperService.start()
	local creatorIsUser = game.CreatorType == Enum.CreatorType.User
	local userId = ShopkeeperConfig.ownerId(ShopkeeperConfig.UserId, creatorIsUser, game.CreatorId)
	if userId > 0 then
		task.spawn(ShopkeeperService.build, userId)
	elseif RunService:IsStudio() then
		-- an unpublished place in Studio: the first player is the one pressing Play
		local function first(player: Player)
			if userId == 0 and player.UserId > 0 then
				userId = player.UserId
				task.spawn(ShopkeeperService.build, userId)
			end
		end
		Players.PlayerAdded:Connect(first)
		for _, player in Players:GetPlayers() do
			first(player)
		end
	end
end

return ShopkeeperService
