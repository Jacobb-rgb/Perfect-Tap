--[[
	All RemoteEvents in one place. The server creates them (Net.setupServer),
	the client waits for them. Server handlers are wrapped with a per-player
	rate limit (token bucket) and pcall, so a bad or spammy client can't
	break the server.

	Client -> server events carry *intents* only ("I swung at this node").
	The server validates everything (see Guard) before changing state.
]]

local Net = {}

export type Limit = { Rate: number, Burst: number }

-- name = rate limit for client->server traffic (nil = server->client only)
Net.Events = {
	-- mining / carrying
	MineBlast = { Rate = 10, Burst = 14 }, -- (rock: Model?) aim the held beam at a rock; nil = stop firing
	CarryPickup = { Rate = 8, Burst = 10 },
	CarryDrop = { Rate = 8, Burst = 10 },
	CarryThrow = { Rate = 6, Burst = 8 },
	-- cleaning minigame
	CleanStart = { Rate = 2, Burst = 3 },
	CleanSubmit = { Rate = 2, Burst = 3 },
	CleanCancel = { Rate = 2, Burst = 3 },
	-- machines / building (payloads: docs/plans/STEP_D_PLAN.md, "Remotes")
	BuildPlace = { Rate = 8, Burst = 12 }, -- (seq, machineId, x, z, r); fast enough to paint belts
	BuildMove = { Rate = 4, Burst = 6 }, -- (seq, model, x, z, r)
	BuildPickup = { Rate = 6, Burst = 10 }, -- (seq, model)
	MachineAction = { Rate = 8, Burst = 12 }, -- (model, action, arg?)
	-- anvil forging
	AnvilSubmit = { Rate = 2, Burst = 3 }, -- (sessionId, recipeId, strikes)
	AnvilCancel = { Rate = 2, Burst = 3 }, -- (sessionId)
	-- base: Ore Pen, podiums, Sell stall (design v2)
	PenAction = { Rate = 8, Burst = 12 }, -- (action: "Take" | "ToPodium", arg: { Key, Count?, Slot? })
	PodiumAction = { Rate = 6, Burst = 10 }, -- (slot: 1..4, action: "Remove" | "Place", arg: { Key }?)
	SellAction = { Rate = 4, Burst = 8 }, -- (action: "Sell" | "SellAll", arg: { Key?, Count?, Dirty? })
	TrainAction = { Rate = 4, Burst = 6 }, -- (action: "Send" | "Upgrade", arg: { Kind = "Capacity" | "Speed" }?)
	-- economy / meta
	ShopBuy = { Rate = 3, Burst = 5 },
	DailyClaim = { Rate = 1, Burst = 2 },
	GroupClaim = { Rate = 1, Burst = 2 },
	SetForgeName = { Rate = 0.5, Burst = 2 },
	TutorialSkip = { Rate = 1, Burst = 2 },
	-- server -> client
	Notify = false,
	Fx = false,
	State = false,
	CleanBegin = false,
	CleanResult = false,
	OpenUI = false,
	Tutorial = false,
	BuildResult = false, -- { Seq, Op, Ok, Reason?, Id?, X?, Z?, R? }
	AnvilBegin = false, -- { Id, Anvil, OreId, Grade, Count, Recipes, Timeout }
	AnvilResult = false, -- { Id, Ok, Reason?, Recipe?, OreId?, Grade?, Value?, ItemId? }
	Earned = false, -- { Amount, Source, Position? } coin popups ("Sell", "Offline", ...)
	TrainTrip = false, -- { UserId, PlotId, DepartAt, ArriveAt, Count, Color, Load = { oreColor... } } (also a list on join)
} :: { [string]: Limit | false }

local FOLDER_NAME = "Remotes"

local folder: Folder? = nil
local events: { [string]: RemoteEvent } = {}

local function getFolder(): Folder
	local cached = folder
	if cached then
		return cached
	end
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local result: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			result = existing :: Folder
		else
			result = Instance.new("Folder")
			result.Name = FOLDER_NAME
			result.Parent = ReplicatedStorage
		end
	else
		result = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	folder = result
	return result
end

function Net.event(name: string): RemoteEvent
	local cached = events[name]
	if cached then
		return cached
	end
	assert(Net.Events[name] ~= nil, "Unknown remote " .. name)
	local f = getFolder()
	local RunService = game:GetService("RunService")
	local remote: RemoteEvent
	if RunService:IsServer() then
		local existing = f:FindFirstChild(name)
		if existing then
			remote = existing :: RemoteEvent
		else
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = f
		end
	else
		remote = f:WaitForChild(name) :: RemoteEvent
	end
	events[name] = remote
	return remote
end

-- Server: create every remote up front so clients never wait.
function Net.setupServer()
	for name in Net.Events do
		Net.event(name)
	end
end

---------------------------------------------------------------- server

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
local dropped: { [Player]: number } = {}

local function allow(player: Player, name: string, limit: Limit): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = limit.Burst, last = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(limit.Burst, bucket.tokens + (now - bucket.last) * limit.Rate)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	dropped[player] = (dropped[player] or 0) + 1
	return false
end

-- Server: listen to a client event with rate limiting and error isolation.
function Net.on(name: string, handler: (player: Player, ...any) -> ...any)
	local limit = Net.Events[name]
	assert(limit, name .. " is not a client->server event")
	Net.event(name).OnServerEvent:Connect(function(player: Player, ...)
		if not allow(player, name, limit :: Limit) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[Net] {name} from {player.Name} failed: {err}`)
		end
	end)
end

function Net.fire(name: string, player: Player, ...: any)
	Net.event(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	Net.event(name):FireAllClients(...)
end

-- Fire to every player within `radius` studs of `position` (optionally skipping one).
function Net.fireNear(name: string, position: Vector3, radius: number, except: Player?, ...: any)
	local Players = game:GetService("Players")
	for _, player in Players:GetPlayers() do
		if player ~= except then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - position).Magnitude <= radius then
				Net.event(name):FireClient(player, ...)
			end
		end
	end
end

function Net.forget(player: Player)
	buckets[player] = nil
	dropped[player] = nil
end

function Net.droppedCount(player: Player): number
	return dropped[player] or 0
end

---------------------------------------------------------------- client

function Net.send(name: string, ...: any)
	Net.event(name):FireServer(...)
end

function Net.listen(name: string, handler: (...any) -> ()): RBXScriptConnection
	return Net.event(name).OnClientEvent:Connect(handler)
end

return Net
