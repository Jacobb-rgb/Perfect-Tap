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
	PenAction = { Rate = 8, Burst = 12 }, -- (action: "Take" | "ToPodium" | "Send" | "StopSend" | "AutoSort", arg)
	--   "Take"     { Key, Count }  items to your hands at the pen gate
	--   "ToPodium" { Key, Slot }   one cleaned ore onto a podium
	--   "Send"     { Key?, Count?, Filter? }  add a send intent to your send queue for
	--              the PEN chute cell (BaseLayout.Chutes.Pen): one item every 0.5 s
	--              spawns on the belt standing on that cell (BaseLayout.sourceFeeds);
	--              with no such belt, or no room on it, the queue waits. Key
	--              ("K|O|G|R") + Count (whole number 1..GameConfig.MaxStoredItems,
	--              default 1) = that many of one item type; or no Key and Filter =
	--              "Dirty" (all dirty ore) | "Unkept" (everything MachineData.keeps
	--              doesn't keep: dirty ore, crushed ore, ingots and the unkept clean
	--              ore; needs Upgrades.PenAutomation >= 1) | "All" (everything in the pen)
	--   "StopSend" (no arg)        empties your send queue (the train's Direct Unload goes on)
	--   "AutoSort" { On: boolean } the sorting billboard (PenAutomation >= 1) on / off:
	--              data.AutoSort; off drops what it queued (State: AutoSort)
	--   The send queue holds intents only (Key/Count or Filter, how many are left),
	--   never items: every item stays in data.Storage until the step that spawns it,
	--   which finds a matching item in Storage, removes it and spawns it on the belt
	--   with no yield in between (none left: that intent ends). So a crash, a
	--   shutdown or an autosave never finds an item outside the pen or the belt
	--   (once spawned it is a loose item like any other), and StopSend or leaving
	--   just drops the intents: there is nothing to put back.
	PodiumAction = { Rate = 6, Burst = 10 }, -- (slot: 1..4, action: "Remove" | "Place", arg: { Key }?)
	SellAction = { Rate = 4, Burst = 8 }, -- (action: "Sell" | "SellAll", arg: { Key?, Count?, Dirty? })
	TrainAction = { Rate = 4, Burst = 6 }, -- (action: "Send" | "Upgrade", arg: { Kind = "Capacity" | "Speed" }?)
	-- automation + Foundry (step 3, docs/plans/STEP3_PLAN.md)
	IronBoxAction = { Rate = 4, Burst = 12 }, -- (action, arg) what clean ore the Iron Box and
	--   the pen's sorting billboard keep (MachineData.Keep / keeps / keepsOre; State:
	--   KeepMode, KeepList; dirty ore, crushed ore and ingots always pass on):
	--   "SetMode"     { Mode: "RarePlus" | "List" | "All" }  data.KeepMode
	--   "SetKeep"     { Ore: oreId, Keep: boolean }            the player's choice for one ore
	--                                                          on data.KeepList ("List" mode)
	--   "SetKeepMany" { Ores: { oreId }, Keep: boolean }       up to #OreData.List ores at once (presets)
	--   "ClearList"   (no arg)                                 empties data.KeepList: every ore
	--                                                          follows the Rare+ rule again
	--   The client redraws from the next State snapshot, so a dropped event never
	--   leaves it out of step with the save.
	FoundryAction = { Rate = 4, Burst = 8 }, -- (action, arg?):
	--   "Open"                                    open your Foundry's panel (server answers OpenUI "Foundry")
	--   "Forge"  { Ore: oreId? }                  start forging the next blaster level from data.Foundry.Stock;
	--                                             Ore = the skin, an ore among the usable stock ingots
	--                                             (default: the ore of the most valuable one). It uses
	--                                             one ingot of the skin ore plus the lowest-value other
	--                                             usable ingots (GameConfig, Foundry), never the best
	--   "Strike" { SessionId, Times: { number } } the hammer taps, seconds since FoundryBegin, oldest first
	--   "Cancel" { SessionId }
	--   "Take"   { Key, Count }                   stock ingots of one type ("Ingot|O|G|", whole Count
	--                                             1..GameConfig.MaxFoundryStock) back into the Ore Pen, as
	--                                             many as fit (checked and moved with no yield; refused
	--                                             while a forge session runs)
	--   Nothing is taken when forging starts: on the Strike that finishes the
	--   session the server checks the ingots and coins again and takes both in
	--   one step with no yield (FoundryResult "NotEnough" if either is gone by
	--   then); in that same step the stock ingots the new next level can't use
	--   move to the pen (as many as fit). Cancel, Timeout and BadStrikes cost nothing.
	-- mine elevator (ElevatorService), only within ElevatorService.Range of a stop:
	--   ({ Action = "Buy" }) buys it once for MineFloors.Elevator.Price coins (data.Upgrades.Elevator);
	--   ({ Action = "Go", Floor }) rides to that floor's stop: owned, whole Floor 1..#MineFloors.List,
	--   unlocked (BlasterLevel >= MinBlaster), not that stop's own floor, not while cleaning,
	--   not right after the last ride. Refusals answer with a "Deny" Notify; a ride with ElevatorRide.
	ElevatorAction = { Rate = 3, Burst = 5 },
	-- economy / meta
	ShopBuy = { Rate = 3, Burst = 5 }, -- ({ Shop = "Tech", Item: string, Count: number?, Level: number? }), Item:
	--   <machineId> (Count 1..EconomyConfig.TechShop.MaxCount; at most TechShop.MaxOwned of a type
	--   in the inventory) | "Upgrade:<machineId>:Speed" | "Upgrade:<machineId>:Quality" |
	--   "PenAutomation" | "Bellows" | "Slots" (EconomyConfig.techItem).
	--   Levelled items need Level = the level being bought (the one on the card); the server
	--   refuses any other ("Stale", EconomyConfig.techQuote). The handler quotes, spends and
	--   writes the level / inventory in one step with no yield, so a double tap buys one
	--   level. Every request (except one the rate limit drops) gets a ShopResult answer.
	DailyClaim = { Rate = 1, Burst = 2 },
	GroupClaim = { Rate = 1, Burst = 2 },
	SetForgeName = { Rate = 0.5, Burst = 2 },
	TutorialSkip = { Rate = 1, Burst = 2 },
	Teleport = { Rate = 1, Burst = 3 }, -- (destination: "Base" | "Lobby" | "Vault" | "Elevator") the quick
	--   teleports (TeleportConfig); the server answers every request it reads with TeleportResult
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
	-- the Foundry's hammer moment starts: { Id: SessionId, Level: the blaster level being forged,
	--   Ore: skin oreId, Hits: taps needed, Timeout: seconds, Ingots: number to be used,
	--   Coins: the price, taken only on success (see FoundryAction) }
	FoundryBegin = false,
	-- { Id: SessionId ("" when "Forge" is refused before a session starts), Ok,
	--   Reason?: "NotEnough" (ingots or coins missing, at Forge or at the final Strike) | "MaxLevel" |
	--   "Busy" (a session already runs) | "TooFar" (not at your Foundry) | "BadOre" (the skin isn't
	--   a known ore among the usable ingots) | "Cancelled" | "Timeout" | "BadStrikes",
	--   Level?: new BlasterLevel, Ore?: new BlasterOre, Name?: BlasterData.displayName }
	FoundryResult = false,
	-- the answer to every ShopBuy the server reads: { Item, Ok, Reason?: an
	--   EconomyConfig.TechShop.Reasons code ("BadItem" | "BadCount" | "MaxOwned" | "Max" |
	--   "Stale" | "NoCoins" | "TooFar"), Level?: the item's level after a levelled buy,
	--   Count?: machines bought }; a State push follows a successful buy
	ShopResult = false,
	-- an elevator ride (ElevatorService): { Phase = "Depart", Floor, From?, Name, Duration, DoorsClose }
	--   starts the client's full-screen ride (the doors shut within DoorsClose seconds, the
	--   counter runs at least Duration seconds); { Phase = "Arrive", Floor, Name, Ok } once the
	--   character stands at the target stop (the doors open); { Phase = "Arrive", Rescue = true }
	--   after a VoidCatcher rescue (a short fade, no ride)
	ElevatorRide = false,
	-- the answer to a Teleport: { Destination, Ok, Reason?: a TeleportConfig.Reasons code }
	TeleportResult = false,
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
