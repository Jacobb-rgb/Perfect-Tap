--[[
	All RemoteEvents in one place. The server creates them (Net.setupServer),
	the client waits for them. Server handlers are wrapped with a per-player
	rate limit (token bucket) and pcall, so a bad or spammy client can't
	break the server.

	Client -> server events carry *intents* only ("I swung at this node").
	The server validates everything (see Guard) before changing state.

	- An event from a player who already left (player.Parent ~= Players:
	  it arrived after PlayerRemoving) is dropped before its rate limit or
	  handler, so no per-player state is ever made again for them. The
	  rate-limit buckets are weak-keyed besides (Net.forget clears them).
	- Every remote with no Net.on handler (server -> client events, and
	  client -> server entries nothing handles yet) gets a do-nothing
	  listener from setupServer that only counts the drop
	  (Net.droppedCount / Net.unhandledCount), so a client firing them can't
	  fill the server's event queue or its logs. Net.on replaces it.
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
	BuildPlace = { Rate = 8, Burst = 12 }, -- (seq, machineId, x, z, r, level?); fast enough to paint belts (level: nil / 0 ground, 1 deck)
	BuildMove = { Rate = 4, Burst = 6 }, -- (seq, model, x, z, r, level?)
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
	TrainAction = { Rate = 4, Burst = 6 }, -- (action: "Send" | "Upgrade", arg: { Kind = "Capacity" | "Speed", Level = the level bought }?: "Stale" unless Level = current + 1)
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
	VaultBuy = { Rate = 2, Burst = 4 }, -- ({ Level: number }) buy your next blaster level at the Blaster Vault
	--   counter for coins (BlasterData.vaultPrice, the case's ore look BlasterData.vaultOre); every
	--   request read gets a VaultResult (see VaultService)
	-- hoverboards (HoverboardService), anywhere: { Action = "Buy", Board } a coin board (EconomyService);
	--   { Action = "Equip", Board } an owned board ("" = none); { Action = "Ride", On: boolean? } on / off
	--   (nil = toggle). Every request read gets a HoverboardResult. Robux boards are game passes:
	--   MarketplaceService:PromptGamePassPurchase on the client (MonetizationConfig ids, never id 0);
	--   MonetizationService grants them (ownership checked on load and on purchase)
	HoverboardAction = { Rate = 4, Burst = 8 },
	-- rebirth "STAR FORGE" (RebirthService), anywhere: { Action = "Rebirth" } (RebirthConfig.canRebirth:
	--   the whole reset in one step on the server) or { Action = "Buy", Perk } (a Star Shop level,
	--   RebirthConfig.quote). Every request read gets a RebirthResult
	RebirthAction = { Rate = 2, Burst = 4 },
	-- steps 6-7: gear, enchants, boosts, golems + capsules, wheel, artifacts (the configs in
	-- Shared/Config document each rule). Every request the server reads (except Capsule
	-- "Open" and Wheel "Spin", answered by CapsuleResult / WheelResult, and Robux requests,
	-- answered by PurchasePrompt) gets one ActionResult; a refused Capsule "Open" or Wheel
	-- "Spin" gets an ActionResult too. Successful changes push State (DataService.changed).
	GearAction = { Rate = 3, Burst = 5 }, -- ("Buy", { Line: GearConfig line id, Level: the
	--   level being bought, = current + 1 (GearConfig.quote, else "Stale") }); within
	--   GearConfig.Range of a ShopCounter
	EnchantAction = { Rate = 4, Burst = 8 }, -- (action, arg):
	--   "Buy"  { Id: EnchantConfig id, Currency: "Coins" | "Shards" | "Robux", Tier: the tier
	--          being bought, = current + 1 } (EnchantConfig.quote; within EnchantConfig.Range
	--          of an EnchantCounter; "Robux" -> PurchasePrompt for the Mythic's game pass,
	--          never granted here; "Restricted" for an odds booster where paid random items
	--          are restricted, EnchantConfig.isPaidRandom)
	--   "Slot" { Slot: 1..EnchantConfig.MaxSlots, Id: an owned enchant id, or nil / "" to empty
	--          the slot } (EnchantConfig.setSlot; free, anywhere)
	BoostAction = { Rate = 2, Burst = 4 }, -- (action, arg):
	--   "BuyCoins" { Id: BoostConfig.CoinOffers id } (BoostConfig.coinQuote: the price at the
	--              player's blaster level; refused "NoEffect" (BoostConfig.hasEffect false),
	--              "CoinLimit" (BoostConfig.CoinBuyBelow or more left), "Full" (past
	--              BoostConfig.MaxStackSeconds))
	--   "BuyRobux" { Id: BoostConfig.RobuxOffers id } -> PurchasePrompt
	--   refused ("Restricted") where paid random items are restricted (src/server/Policy.luau)
	--   and the offer is one (BoostConfig.isPaidRandom)
	CapsuleAction = { Rate = 1, Burst = 2 }, -- ("Open", { Capsule: CapsuleConfig id, Count: 1 | 3 | 10 }):
	--   coin capsules: price CapsuleConfig.price at the player's blaster level, needs Count
	--   free golem places (GolemConfig.room), Triple Lucky counts when active; Royal (Robux)
	--   -> PurchasePrompt; "Restricted" where paid random items are restricted and the
	--   capsule is one (CapsuleConfig.isPaidRandom). Answer: CapsuleResult (or an
	--   ActionResult when refused). Anywhere (side menu or the CapsuleStall). A request the
	--   rate limit drops gets NO answer: the client waits CapsuleConfig.ClientCooldown between
	--   opens and gives the buttons back after CapsuleConfig.ResultTimeout, but still shows a
	--   CapsuleResult that arrives later (same for WheelAction / WheelResult).
	GolemAction = { Rate = 4, Burst = 8 }, -- (action, arg):
	--   "Equip" { Id } | "Unequip" { Id } | "EquipBest" (no arg) |
	--   "Lock" { Id, Locked: boolean } (a locked golem is never deleted) |
	--   "Delete" { Ids: { Id } (1..GolemConfig.MaxDelete whole numbers; locked ones are
	--   skipped) } (GolemConfig helpers)
	WheelAction = { Rate = 1, Burst = 2 }, -- ("Spin"): the free daily spin when
	--   WheelConfig.ready(data.Wheel.NextSpinAt, now); answer WheelResult (the player's wheel:
	--   WheelConfig.pick(roll, CapsuleConfig.allRestricted(restricted)); client timing:
	--   WheelConfig.ClientCooldown / ResultTimeout) | ("Reveal"): the open wheel screen showed
	--   a capsule prize: that spin's CapsuleResult { Free } comes once (no answer otherwise)
	ArtifactAction = { Rate = 2, Burst = 4 }, -- ("ReadChapter", { Collection }): marks a
	--   completed collection's StoryConfig chapter read (data.Artifacts.Chapters) |
	--   ("Equip", { Collection: a completed collection id, or "" for none }): whose title +
	--   podium skin show (data.Artifacts.Equipped) | ("Restore", { Artifact }): buys back the
	--   ONE missing artifact of a collection with crystal shards (ArtifactConfig.restoreQuote;
	--   ArtifactFound { Restored = true } follows); all three answered by ActionResult
	GroupClaim = { Rate = 1, Burst = 2 },
	SetForgeName = { Rate = 0.5, Burst = 2 },
	TutorialAction = { Rate = 1, Burst = 3 }, -- ("Skip" | "Ack") the tutorial (TutorialService):
	--   Skip ends it (no reward), Ack is "Got it" on an info step; answered by Tutorial
	Teleport = { Rate = 1, Burst = 3 }, -- (destination: "Base" | "Lobby" | "Vault" | "Elevator") the quick
	--   teleports (TeleportConfig); the server answers every request it reads with TeleportResult
	SettingsSave = { Rate = 1, Burst = 4 }, -- ({ Music: 0..1, Sfx: 0..1, Shake: boolean, Rumble: boolean })
	--   the side menu's SETTINGS (SettingsConfig.sanitize; saved in data.Settings, sent back
	--   as snapshot.Settings); the client sends it SettingsConfig.SaveDelay after the last change
	CodexSeen = { Rate = 0.5, Burst = 3 }, -- ({ oreId, ... }) the ORE CODEX closed: these
	--   discovered ores were looked at (their NEW badges go; CodexService keeps them in
	--   data.OreCodex.Seen, sent back as snapshot.CodexSeen)
	StateSync = { Rate = 0.5, Burst = 2 }, -- (no arg) the client got a partial State push before
	--   any whole one (it missed the Full push): the server forgets what it sent and pushes the
	--   whole snapshot (StateService.resync; StateController asks at most every SyncSeconds)
	-- server -> client
	Notify = false,
	Fx = false,
	State = false,
	CleanBegin = false,
	CleanResult = false,
	OpenUI = false,
	Tutorial = false, -- { Step, Done, Total, Reward?, How = "Step" | "Done" | "Skip" | "Load" }
	BuildResult = false, -- { Seq, Op, Ok, Reason?, Id?, X?, Z?, R?, L? }
	AnvilBegin = false, -- { Id, Anvil, OreId, Grade, Count, Recipes, Timeout }
	AnvilResult = false, -- { Id, Ok, Reason?, Recipe?, OreId?, Grade?, Value?, ItemId? (a short per-session number) }
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
	-- the answer to a VaultBuy: { Level, Ok, Reason?: "BadLevel" | "Owned" | "Locked" | "Max" |
	--   "TooFar" | "NoCoins" | "NoData", Ore?: the new BlasterOre, Name?: BlasterData.displayName };
	--   on Ok the client plays the crate opening (a State push follows)
	VaultResult = false,
	-- the answer to a HoverboardAction: { Action, Board?, Ok, Reason?: a HoverboardService.Reasons
	--   code, Riding?: boolean }; a State push (Hoverboards) follows a change
	HoverboardResult = false,
	-- the answer to a RebirthAction: { Action, Ok, Reason?: a RebirthConfig.Reasons code, Perk?,
	--   Level? (the perk's new level), Stars? (paid by the rebirth), Rebirths? (the new count) };
	--   on a rebirth the client plays the moment, the server sends the character home after it
	RebirthResult = false,
	-- steps 6-7 answers:
	-- { Action: "Gear" | "Enchant" | "Boost" | "Capsule" | "Golem" | "Wheel" | "Artifact",
	--   Op: the action string ("Buy", "Slot", "BuyCoins", "Open", "Equip", "Spin", ...),
	--   Ok: boolean, Reason?: a code from that config's Reasons table,
	--   Id?: the item / line / golem id the request named, Level?: the new level or tier }
	ActionResult = false,
	-- a capsule opened: { Capsule, Count, Golems = { { Id, Kind } } (in opening order),
	--   Lucky: boolean (Triple Lucky was on), Free: boolean? (a wheel prize) }
	CapsuleResult = false,
	-- the daily spin: { Segment: 1..8 (WheelConfig.Segments index), Id: segment id,
	--   Kind: WheelConfig PrizeKind, Amount?: coins or shards, Boost?, Seconds?,
	--   Capsule?, Golem?: { Id, Kind } (a capsule prize), DirtyOre?: true (a dirty Rare+ ore
	--   went to the pen; WHICH ore stays secret until it is cleaned, the screen shows
	--   WheelConfig.oreOdds), Coins?: coins paid instead (full pen / full golem inventory /
	--   a boost past its cap), Full?: true (a capsule prize's coins: the golem inventory was full),
	--   Lucky?: Triple Lucky counted for the capsule, NextSpinAt: os.time() of the next free spin } (Segment/Id from the player's wheel,
	--   WheelConfig.segments(noCapsules): "TripleLuckyCoins" replaces "TripleLucky" there)
	WheelResult = false,
	-- an artifact turned up: { Artifact: id, Count: copies now, New: boolean,
	--   Collection: id, Completed: boolean (this find completed it), Shards?: a duplicate's
	--   shards, Position?: Vector3 where the rock broke, Restored?: true (bought back with
	--   shards: ArtifactAction "Restore", no rock) }
	ArtifactFound = false,
	-- a Robux item was asked for: { Product: MonetizationConfig key, Status: "ComingSoon" |
	--   "Restricted" | "Owned" | "Full" | "Unknown" | "Prompted" }
	--   (MonetizationConfig.promptStatus; "Prompted" = MarketplaceService prompt shown)
	PurchasePrompt = false,
	-- the lobby leaderboards (LeaderboardService, every LeaderboardConfig.RefreshSeconds and on
	--   join): { Live: boolean (false = no DataStores, e.g. Studio: the rows rank the players on
	--   this server), Boards = { [boardId] = { Rows = { { Rank, UserId, Name, Value } } (top
	--   LeaderboardConfig.TopCount, Value decoded), Ready: boolean (read at least once) } },
	--   Own = { [boardId] = { Value: your live value, Rank: number? (only inside Rows) } } }
	Leaderboards = false,
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

---------------------------------------------------------------- server

type Bucket = { tokens: number, last: number }
-- weak keys: a Player the game let go of never stays here
local buckets: { [Player]: { [string]: Bucket } } = setmetatable({}, { __mode = "k" }) :: any
local dropped: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
-- remotes with a Net.on handler, and the do-nothing listeners on the others
local handled: { [string]: boolean } = {}
local sinks: { [string]: RBXScriptConnection } = {}
local unhandled = 0

local playersService: Instance? = nil

-- Is the player still in the game? (An event can arrive after PlayerRemoving.)
local function present(player: Player): boolean
	local service = playersService
	if not service then
		service = game:GetService("Players")
		playersService = service
	end
	return player.Parent == service
end

local function countDrop(player: Player)
	if present(player) then
		dropped[player] = (dropped[player] or 0) + 1
	end
end

-- The do-nothing listener of a remote nothing handles: a client firing it
-- costs one counter, never a queued event or a warning.
local function connectSink(name: string)
	if handled[name] or sinks[name] then
		return
	end
	sinks[name] = Net.event(name).OnServerEvent:Connect(function(player: Player)
		unhandled += 1
		countDrop(player)
	end)
end

-- Server: create every remote up front so clients never wait, and give
-- every one without a handler (yet) its do-nothing listener.
function Net.setupServer()
	for name in Net.Events do
		Net.event(name)
		connectSink(name)
	end
end

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
-- Events from a player who already left are dropped first (no bucket, no
-- handler: nothing per player is made again after PlayerRemoving).
function Net.on(name: string, handler: (player: Player, ...any) -> ...any)
	local limit = Net.Events[name]
	assert(limit, name .. " is not a client->server event")
	handled[name] = true
	Net.event(name).OnServerEvent:Connect(function(player: Player, ...)
		if not present(player) then
			return
		end
		if not allow(player, name, limit :: Limit) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[Net] {name} from {player.Name} failed: {err}`)
		end
	end)
	-- the handler is connected: the do-nothing listener can go
	local sink = sinks[name]
	if sink then
		sinks[name] = nil
		sink:Disconnect()
	end
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

-- Events of this player the server dropped: over a rate limit, or fired
-- at a remote nothing handles.
function Net.droppedCount(player: Player): number
	return dropped[player] or 0
end

-- Events fired at remotes nothing handles, from anyone, since the start.
function Net.unhandledCount(): number
	return unhandled
end

-- Internals for the Lune tests only (tests/Net.spec.luau).
Net._test = {
	hasBucket = function(player: Player): boolean
		return buckets[player] ~= nil
	end,
	weakKeys = function(): boolean
		local a, b = getmetatable(buckets :: any), getmetatable(dropped :: any)
		return a ~= nil and a.__mode == "k" and b ~= nil and b.__mode == "k"
	end,
	hasSink = function(name: string): boolean
		local sink: RBXScriptConnection? = sinks[name]
		return sink ~= nil
	end,
	reset = function()
		table.clear(buckets)
		table.clear(dropped)
		table.clear(handled)
		for _, sink in sinks do
			sink:Disconnect()
		end
		table.clear(sinks)
		unhandled = 0
	end,
}

---------------------------------------------------------------- client

function Net.send(name: string, ...: any)
	Net.event(name):FireServer(...)
end

function Net.listen(name: string, handler: (...any) -> ()): RBXScriptConnection
	return Net.event(name).OnClientEvent:Connect(handler)
end

return Net
