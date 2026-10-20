--[[
	TrainService: every player's own ore train (design v2,
	docs/plans/STEP2_PLAN.md; all numbers in TrainConfig).

	Saved in data.Train (DataTemplate, cleaned by Migrations): CapacityLevel,
	SpeedLevel, Cargo (items waiting at the station), TripCargo (items on the
	train) and TripDepartAt / TripArriveAt (wall-clock Unix seconds with
	milliseconds, 0 = no trip; old whole-second saves read the same). An
	item is always in exactly one place: in the world (loose or carried),
	Cargo, TripCargo or the Ore Pen (data.Storage). Every move takes it from
	one place and puts it into the next without a yield in between. Only the
	saved trip times use the wall clock; everything inside a session runs on
	workspace:GetServerTimeNow() (the clock the clients animate with).

	- Intake: every BasePart tagged "TrainHopper" under Workspace.Map.Railway
	  (the Mine Station hopper and the Mine Lifts, World/Railway builds them;
	  hooks added later and a railway that is built again are picked up too)
	  is an IntakeService zone. A loose item that lands in one goes into its
	  OWNER's cargo (nobody can load another player's train) while the cargo
	  has room and the train is at the station; otherwise it bounces back out
	  toward the prompts with a throttled toast that says why (on its way /
	  waiting at a full pen / coming back / full).
	- Prompt rules (shared with the client; TrainConfig.PromptSlots): each
	  hook gets two ProximityPrompts at the "PromptPoint" attachment of its
	  station / lift (searched from the ancestor tagged "TrainStation" or
	  "MineLift"), tagged "TrainPrompt", with attributes Action = "Load" |
	  "Send" and Slot (UIOffset = (0, Slot * 72), PromptConfig.SlotHeight):
	    slot 0 (0, 0)    "TrainLoadPrompt"  "Load Train"  E / gamepad Y
	    slot 1 (0, 72)   "TrainSendPrompt"  "Send Train"  G / gamepad B
	    slot 2 (0, 144)  kept free for the client's own "Train" panel prompt
	                     (it must not stay at the default offset (0, 0))
	  The server never changes Enabled after creating them, so the client
	  decides what this screen shows: it hides every Action "Load" prompt while
	  the player carries nothing (CarryCount attribute), the way
	  PromptController treats machine LoadPrompts. A press with empty hands
	  only gets a throttled hint.
	- Departure: as soon as the cargo is full, on TrainAction "Send" (from
	  anywhere: it is harmless) or AutoDepartSeconds after the last load.
	  Cargo moves to TripCargo, the trip times are saved and every client gets
	  "TrainTrip" { UserId, PlotId, DepartAt, ArriveAt, Count, Color, Load }
	  (server time; Load = {} when all of it is dirty ore, so the client shows
	  its own dirt colors) and animates the trip. A timer wakes the train
	  exactly at ArriveAt, the 1 s loop is the safety net.
	- Arrival: TripCargo goes into the Ore Pen up to its capacity
	  (ItemService.penCapacity); what went in goes on to PenService.arrived
	  (the sorting billboard). Direct Unload (step 3, see that section):
	  with Upgrades.PenAutomation >= EconomyConfig.PenAutomation.DirectUnload
	  and a belt feeding from the TRAIN chute, the dirty ore stays on board
	  and pours out onto that belt one by one (PenService's Train lane), not
	  through the pen; the train stands at the stop until it is all out.
	  Once empty: trip times cleared, Stats.TrainTrips + 1, Fx "TrainUnload"
	  (plotId, count of items that went into the pen, when any) to
	  everyone, and the empty train rolls back for ReturnSeconds before it
	  can load again.
	- Waiting (shared with the client): when the pen can't take the whole
	  load, the rest stays on the train, which stands at the player's stop and
	  is tried again every DeliveryRetry seconds (one "pen full" toast per
	  trip). Everyone gets "TrainTrip" again with the same times and the
	  optional field Waiting = true (also in a joiner's list and when a
	  rejoining player's waiting train is announced); the owner's snapshot has
	  Waiting = true and Moving > 0. No "TrainUnload" comes until it really
	  unloads; then "TrainTrip" comes once more with ArriveAt = the unload
	  time (no Waiting; DepartAt kept unless the trip would get longer than
	  MaxTripSpan, which clients refuse) right before Fx "TrainUnload", and
	  it rolls back for ReturnSeconds from then.
	- Joining: a trip that arrived while you were away is delivered at once
	  (no animation, no return trip) with a "while you were away" toast; if
	  the pen can't take it all, the train waits at your stop as above, for
	  everyone to see. A running trip is announced again (same server times
	  as before when you rejoin the same server), and the joining player gets
	  the list of everyone else's trains that carry ore (on the move or
	  waiting; empty trains rolling back are left out: Count 0 never happens).
	  For JoinGrace seconds a full cargo does not leave by itself (perks such
	  as Express may still be on their way).
	- Upgrades: TrainAction "Upgrade" { Kind = "Capacity" | "Speed", Level }
	  buys the next level (TrainConfig.nextPrice, EconomyService.spend).
	  Level must be exactly the level being bought (current + 1, the one
	  the card shows), else nothing happens ("Stale", quietly: a double
	  click or a lagging card never buys two levels; Security #7). The
	  Express perk (Perks "TrainExpress") adds cargo and speed.
	- Over capacity: while the Ore Pen holds more than its capacity
	  (PenService.isOver, after a rescue move) nothing unloads into it: the
	  cargo waits at the stop as with a full pen, and the snapshot's
	  WaitReason says why ("PenOver", else "PenFull") so the chip can tell.
	- StateService gets Train = { Cargo, Capacity, Moving, DepartAt?,
	  ArriveAt?, CapacityLevel, SpeedLevel, NextCapacityPrice?,
	  NextSpeedPrice?, Express, TripSeconds, AutoDepartIn?, Waiting,
	  WaitReason? ("PenOver" | "PenFull" while Waiting), Unloading, UnloadWait? }.
	  DepartAt / ArriveAt (server time) are there while the train is on a
	  trip, waiting at a full pen or rolling back: it is back at the station
	  at ArriveAt + TrainConfig.ReturnSeconds. ArriveAt is the TrainTrip
	  arrival, or the moment it really unloaded when it had to wait.
	  Waiting = true while it stands at your stop because the pen is full
	  (then Moving > 0 and ArriveAt has passed); Unloading = true while it
	  stands there pouring its dirty ore onto the TRAIN chute's belt (Direct
	  Unload; not Waiting unless the pen is full too), and UnloadWait is why
	  that pouring waits right now (PenService.laneWait "Train": "Jammed" =
	  the belt at the chute is full, "TooMany" = too many of your items lie
	  loose); the train is away (no loading) whenever Moving > 0 or
	  ArriveAt + ReturnSeconds is ahead.
	Studio: Players.<you>:SetAttribute("Perk_TrainExpress", true) tries Express.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local PromptConfig = require(Shared.Config.PromptConfig)
local TrainConfig = require(Shared.Config.TrainConfig)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local Bonuses = require(script.Parent.Parent.Bonuses)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local PlotService = require(script.Parent.PlotService)
local IntakeService = require(script.Parent.IntakeService)
local EconomyService = require(script.Parent.EconomyService)
local ConveyorService = require(script.Parent.ConveyorService)
local PenService = require(script.Parent.PenService)

local TrainService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord

-- What clients get in "TrainTrip" (one per departure, a list on join).
export type Trip = {
	UserId: number,
	PlotId: number,
	DepartAt: number, -- server time
	ArriveAt: number, -- server time
	Count: number,
	Color: Color3, -- the plot banner
	Load: { Color3 }, -- ore colors for the wagon ({} = all dirty ore: the client's dirt colors)
	Waiting: boolean?, -- true: it stands at its stop, the pen is full (see the header)
}

type Train = {
	CapacityLevel: number,
	SpeedLevel: number,
	Cargo: { Desc },
	TripCargo: { Desc },
	TripDepartAt: number,
	TripArriveAt: number,
}

-- A station hopper or a lift: its intake box and where its prompts are.
type Hook = {
	Part: BasePart,
	Name: string, -- "Mine Station" | "Mine Lift"
	LiftId: string?,
	Point: Vector3, -- the prompt point (world)
	Out: Vector3, -- flat unit vector out of the hopper, toward the prompts
}

-- Per-player state that is not saved. Every time is server time (serverNow()).
type Runtime = {
	LastLoad: number?, -- the last load (auto departure)
	LoadedAt: number?, -- when the save was loaded (JoinGrace)
	DepartAt: number?, -- the trip clients animate; kept while the train rolls back
	ArriveAt: number?, -- its arrival, or the late unload after waiting at a full pen
	ReturnUntil: number?, -- the empty train is back at the station (ArriveAt + ReturnSeconds)
	NextRetry: number?, -- the next unloading try (pen full, or the Direct Unload check)
	Waiting: boolean, -- a try left ore on the train: it stands at the stop (until unloaded)
	PenFull: boolean, -- the last try left ore for the pen on board: the pen is full
	Chute: boolean, -- Direct Unload: its dirty ore pours onto the TRAIN chute's belt now
	ChuteFailed: boolean, -- spawning onto that belt failed for good: the rest goes the old way
	Delivered: number, -- items unloaded into the pen on this trip so far
	Chuted: number, -- items that left onto the TRAIN chute's belt on this trip so far
	Trip: Trip?, -- the last TrainTrip everyone got for this trip (kept while it rolls back)
	Prepared: boolean, -- the join checks (onLoaded) have run
	Announced: boolean, -- the trip from the last session was announced
	Toasts: { [string]: number }, -- the last throttled toast per kind
}

-- A trip's server times by UserId, so a player who rejoins this server
-- mid-trip gets exactly the times the other clients already animate.
type SessionTrip = {
	Wall: number, -- the saved TripDepartAt
	WallArrive: number, -- the saved TripArriveAt
	DepartAt: number,
	ArriveAt: number,
}

TrainService.HookTag = "TrainHopper"
TrainService.StationTag = "TrainStation"
TrainService.LiftTag = "MineLift"
-- The prompt rules (header; the numbers live in TrainConfig, the client reads the same ones):
-- Load and Send are the server's, Panel is the client's "Train" prompt.
TrainService.PromptTag = TrainConfig.PromptTag
TrainService.PromptSlotHeight = TrainConfig.PromptSlotHeight -- UIOffset pixels per prompt slot (as IntakeService's machine prompts)
TrainService.PromptSlots = TrainConfig.PromptSlots
TrainService.LoadRange = 14 -- studs from a hook's prompt point for "Load Train"
TrainService.FxRange = 90 -- players this close to a hopper see its TrainLoad puff
TrainService.JoinGrace = 10 -- seconds after joining before a full cargo leaves by itself
TrainService.MaxTripSpan = TrainConfig.MaxTripSpan -- clients ignore a TrainTrip with ArriveAt - DepartAt above this
TrainService.FullText = "Your train is full – press Send"
TrainService.AwayText = "Your train is on its way"
TrainService.ReturnText = "Your train is coming back"
TrainService.PenFullText = "Your Ore Pen is full – make room"
TrainService.PenOverText = "Your Ore Pen holds too much – take, sell or send some"
TrainService.ChuteText = "Your train is unloading at your TRAIN chute"
TrainService.EmptyText = "Your train is empty. Throw ore into a train hopper first."
TrainService.HandsText = "Carry ore here to load your train."
TrainService.NoPlotText = "Your train leaves once you have a plot."
-- PlotBuilder's banner colors (by plot id), for a plot whose Banner part can't be found.
TrainService.BannerColors = {
	Color3.fromRGB(220, 70, 50),
	Color3.fromRGB(240, 170, 40),
	Color3.fromRGB(80, 180, 90),
	Color3.fromRGB(60, 140, 220),
	Color3.fromRGB(160, 90, 220),
	Color3.fromRGB(230, 110, 170),
	Color3.fromRGB(60, 190, 190),
	Color3.fromRGB(240, 230, 210),
}

local RANGE_SLACK = 4 -- the server allows a little more (lag, walking while pressing)
local TOAST_COOLDOWN = 5
local PROMPT_TOAST_COOLDOWN = 2 -- hints for prompt presses and Send (a real press still gets one)
local MAX_LOAD = 64 -- more than any carry stack
local MAX_LOAD_COLORS = 6
local BOUNCE_GAP = 1.5 -- studs outside the hopper box where refused items come out
local OUT_SPEED = 8
local OUT_UP = 12
local WAKE_SLACK = 0.05 -- the arrival timer fires this much after ArriveAt
local SESSION_TRIP_KEEP = 3600 -- seconds after its arrival a session trip is forgotten
local CHUTE_RETRY = 1 -- seconds between Direct Unload checks (belt still there? room in the pen?)

-- Unix seconds with milliseconds (os.time() has whole seconds): only for the saved trip times
local function defaultWallClock(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

-- workspace:GetServerTimeNow(): every timer inside a session
local function defaultServerNow(): number
	return Workspace:GetServerTimeNow()
end

-- runs fn after `seconds` (an arrival timer)
local function defaultSchedule(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end

local wallClock: () -> number = defaultWallClock
local serverNow: () -> number = defaultServerNow
local schedule: (number, () -> ()) -> () = defaultSchedule

local runtimes: { [Player]: Runtime } = {}
local sessionTrips: { [number]: SessionTrip } = {}
local hooks: { Hook } = {} -- a list: a handful of hooks, compared by instance
local perkConnections: { [Player]: RBXScriptConnection } = {}
-- weak keys: the last Reject effect per bounced item (GameConfig.RejectCooldown)
local lastReject: { [ItemRecord]: number } = setmetatable({}, { __mode = "k" }) :: any
local watchedRailway: Instance? = nil
local railwayConnection: RBXScriptConnection? = nil
local mapConnection: RBXScriptConnection? = nil

---------------------------------------------------------------- state

local function runtimeOf(player: Player): Runtime
	local r = runtimes[player]
	if not r then
		r = {
			Waiting = false,
			PenFull = false,
			Chute = false,
			ChuteFailed = false,
			Delivered = 0,
			Chuted = 0,
			Prepared = false,
			Announced = false,
			Toasts = {},
		}
		runtimes[player] = r
	end
	return r
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- A saved level as a whole number. A level above this build's top (a newer
-- build's) stays: TrainConfig.capacity / tripSeconds / nextPrice clamp it.
local function wholeLevel(v: any): number
	return if finite(v) then math.clamp(math.floor(v), 0, GameConfig.MaxLevelKept) else 0
end

-- data.Train in the right shape (repaired in place; Migrations does the deep clean on load).
local function trainOf(data: { [string]: any }): Train
	local train = data.Train
	if type(train) ~= "table" then
		train = {}
		data.Train = train
	end
	if type(train.Cargo) ~= "table" then
		train.Cargo = {}
	end
	if type(train.TripCargo) ~= "table" then
		train.TripCargo = {}
	end
	train.CapacityLevel = wholeLevel(train.CapacityLevel)
	train.SpeedLevel = wholeLevel(train.SpeedLevel)
	for _, field in { "TripDepartAt", "TripArriveAt" } do
		local v = train[field]
		if not finite(v) or v < 0 then
			train[field] = 0
		end
	end
	return train :: Train
end

local function hasExpress(player: Player): boolean
	return Perks.has(player, "TrainExpress")
end

-- The share the rebirth's Express Rails cut off every trip (Bonuses TrainTimeCutPct).
local function tripCut(player: Player): number
	local ok, stats = pcall(Bonuses.stats, player)
	return if ok and type(stats) == "table" then tonumber(stats.TrainTimeCutPct) or 0 else 0
end

local function capacityOf(player: Player, train: Train): number
	return TrainConfig.capacity(train.CapacityLevel, hasExpress(player))
end

local function tripSecondsOf(player: Player, train: Train): number
	return TrainConfig.tripSeconds(train.SpeedLevel, hasExpress(player), tripCut(player))
end

-- The empty train is still rolling back after unloading.
local function isReturning(player: Player): boolean
	local r = runtimes[player]
	local returnUntil = r and r.ReturnUntil
	return returnUntil ~= nil and serverNow() < returnUntil
end

-- Not at the station: on the move, waiting at your stop (pen full) or rolling back.
local function isAway(player: Player, train: Train): boolean
	return #train.TripCargo > 0 or train.TripArriveAt > 0 or isReturning(player)
end

-- How many more items fit into the cargo (capacity and the save cap).
local function cargoRoom(player: Player, train: Train): number
	local byCapacity = capacityOf(player, train) - #train.Cargo
	local bySave = TrainConfig.MaxCargoSaved - #train.Cargo - #train.TripCargo
	return math.max(0, math.min(byCapacity, bySave))
end

-- Remembers a trip's server times for a rejoin on this server (and forgets old ones).
local function rememberTrip(userId: number, train: Train, departAt: number, arriveAt: number)
	local now = serverNow()
	for id, known in sessionTrips do
		if known.ArriveAt + SESSION_TRIP_KEEP < now then
			sessionTrips[id] = nil
		end
	end
	sessionTrips[userId] = {
		Wall = train.TripDepartAt,
		WallArrive = train.TripArriveAt,
		DepartAt = departAt,
		ArriveAt = arriveAt,
	}
end

-- Server times of the trip on the move (worked out from the save once per
-- session; the very same times again when this server announced the trip before).
local function tripTimes(userId: number, train: Train, r: Runtime): (number, number)
	local departAt, arriveAt = r.DepartAt, r.ArriveAt
	if departAt and arriveAt then
		return departAt, arriveAt
	end
	local known = sessionTrips[userId]
	local depart: number, arrive: number
	if known and known.Wall == train.TripDepartAt and known.WallArrive == train.TripArriveAt then
		depart, arrive = known.DepartAt, known.ArriveAt
	else
		local wall = wallClock()
		local server = serverNow()
		depart = server - (wall - train.TripDepartAt)
		arrive = server + (train.TripArriveAt - wall)
		rememberTrip(userId, train, depart, arrive)
	end
	r.DepartAt = depart
	r.ArriveAt = arrive
	return depart, arrive
end

-- The train stands at your stop with ore it can't unload (the pen is full).
local function isWaiting(player: Player, train: Train): boolean
	local r = runtimes[player]
	return #train.TripCargo > 0 and r ~= nil and r.Waiting and r.PenFull
end

-- The train stands at your stop pouring its dirty ore onto the TRAIN chute (Direct Unload).
local function isUnloading(player: Player, train: Train): boolean
	local r = runtimes[player]
	return #train.TripCargo > 0 and r ~= nil and r.Chute
end

---------------------------------------------------------------- toasts and looks

local function toast(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, { Text = text, Kind = kind or "Deny" })
end

-- At most one toast of this kind per `cooldown` (default TOAST_COOLDOWN) seconds:
-- exploit tools can fire prompts and remotes much faster than people.
local function throttledToast(player: Player, key: string, text: string, kind: string?, cooldown: number?)
	local r = runtimeOf(player)
	local now = serverNow()
	local last = r.Toasts[key]
	if last and now >= last and now - last < (cooldown or TOAST_COOLDOWN) then
		return
	end
	r.Toasts[key] = now
	toast(player, text, kind)
end

-- A hint for a prompt press or Send (keyed by its text).
local function hint(player: Player, text: string, kind: string?)
	throttledToast(player, text, text, kind, PROMPT_TOAST_COOLDOWN)
end

-- Why an away train can't load now: waiting at a full pen, unloading at the
-- TRAIN chute, coming back or on its way.
local function awayText(player: Player, train: Train): string
	if isWaiting(player, train) then
		local data = DataService.get(player)
		if data and PenService.isOver(data) then
			return TrainService.PenOverText
		end
		return TrainService.PenFullText
	elseif isUnloading(player, train) then
		return TrainService.ChuteText
	elseif #train.TripCargo == 0 and train.TripArriveAt <= 0 and isReturning(player) then
		return TrainService.ReturnText
	end
	return TrainService.AwayText
end

-- The plot's banner color (the train is painted in it).
function TrainService.bannerColor(plotId: number): Color3
	local model = PlotService.model(plotId)
	local banner = model and model:FindFirstChild("Banner", true)
	if banner and banner:IsA("BasePart") then
		return banner.Color
	end
	local colors = TrainService.BannerColors
	return colors[(math.floor(plotId) - 1) % #colors + 1]
end

-- What the wagon shows: the cargo's ore colors, most common first. Dirty ore
-- keeps its secret (one dirt color for every ore); a load of nothing but
-- dirty ore is {}, so the client uses its own shaded dirt colors.
function TrainService.loadColors(items: { Desc }): { Color3 }
	local counts: { [string]: number } = {}
	local colors: { [string]: Color3 } = {}
	local clean = 0
	for _, item in items do
		local ore = if item.K ~= "Raw" then OreData.ById[item.O] else nil
		local key = if ore then item.O else "~Dirt"
		counts[key] = (counts[key] or 0) + 1
		colors[key] = if ore then ore.Color else ItemBuilder.DirtyCrust
		if ore then
			clean += 1
		end
	end
	if clean == 0 then
		return {}
	end
	local keys = {}
	for key in counts do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: string, b: string): boolean
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	local list = {}
	for i = 1, math.min(#keys, MAX_LOAD_COLORS) do
		table.insert(list, colors[keys[i]])
	end
	return list
end

--[[
	The "TrainTrip" payload of a player's train while it carries ore (on the
	move or waiting at the stop); nil without a plot or ore on board. Count,
	Color and Load stay what everyone got at departure, so a repeat never
	rebuilds the client's train.
]]
local function tripOf(player: Player, train: Train): Trip?
	local plotId = PlotService.plotOf(player)
	if not plotId or #train.TripCargo == 0 then
		return nil
	end
	local r = runtimeOf(player)
	local departAt, arriveAt = tripTimes(player.UserId, train, r)
	local sent = r.Trip
	local trip: Trip = {
		UserId = player.UserId,
		PlotId = plotId,
		DepartAt = departAt,
		ArriveAt = arriveAt,
		Count = if sent then sent.Count else #train.TripCargo,
		Color = if sent then sent.Color else TrainService.bannerColor(plotId),
		Load = if sent then sent.Load else TrainService.loadColors(train.TripCargo),
	}
	if r.Waiting then
		trip.Waiting = true
	end
	return trip
end

-- Tells every client where this player's train is (TrainTrip). False when it carries nothing.
local function broadcast(player: Player, train: Train): boolean
	local trip = tripOf(player, train)
	if not trip then
		return false
	end
	local r = runtimeOf(player)
	r.Trip = trip
	r.Announced = true
	Net.fireAll("TrainTrip", trip)
	return true
end

---------------------------------------------------------------- Direct Unload (step 3, WP-Belts)

--[[
	Direct Unload (Upgrades.PenAutomation >= EconomyConfig.PenAutomation.DirectUnload):
	when the train arrives and a belt feeds from the player's TRAIN chute
	(ConveyorService.sourceBelt: there, not facing the yard), its dirty ore
	(spawnable Raw) STAYS IN TripCargo, which is saved, so leaving or a
	crash never loses it; only its other items go into the pen (deliver).
	PenService's Train lane takes that ore straight off the train: one item
	every SendInterval it removes one desc from TripCargo and spawns it onto
	the belt with no yield in between, or puts it back at the same index
	(PenService.setTrainCargo below: `list` hands it TripCargo while Chute
	is set, `sent` counts what left). The train stands at the stop
	(Waiting for everyone, Unloading in the owner's snapshot) until no
	dirty ore is left, then deliver finishes the trip as always; a full
	pen doesn't stop the dirty ore, only the items meant for the pen wait.
	Every CHUTE_RETRY seconds deliver looks again: when the belt is gone or
	faces the yard (or spawning failed for good), the rest goes into the
	pen as without the upgrade.
]]

-- Does this cargo item pour out of the TRAIN chute (dirty ore that can spawn)?
local function pours(item: any): boolean
	return type(item) == "table" and item.K == "Raw" and ConveyorService.spawnable(item)
end

-- Is there dirty ore for the chute on board?
local function chuteOre(train: Train): boolean
	for _, item in train.TripCargo do
		if pours(item) then
			return true
		end
	end
	return false
end

-- May the arrived train unload its dirty ore onto the TRAIN chute's belt now?
local function chuteReady(player: Player, data: { [string]: any }, r: Runtime): boolean
	if r.ChuteFailed then
		return false
	end
	local upgrades = data.Upgrades
	local level = if type(upgrades) == "table" then upgrades.PenAutomation else nil
	if type(level) ~= "number" or level ~= level or level < EconomyConfig.PenAutomation.DirectUnload then
		return false
	end
	local plotId = PlotService.plotOf(player)
	return plotId ~= nil and ConveyorService.sourceBelt(plotId, "Train") ~= nil
end

-- Items that went into the pen: the sorting billboard may send them on (never breaks unloading).
local function arrivedInPen(player: Player, delivered: { Desc })
	if #delivered > 0 then
		local ok, err = pcall(function()
			PenService.arrived(player, delivered, "Train")
		end)
		if not ok then
			warn(`[TrainService] pen arrival for {player.Name} failed: {err}`)
		end
	end
end

---------------------------------------------------------------- departure and arrival

local tickPlayer: (Player) -> ()

-- Wakes a player's train at a server time (the exact arrival).
local function wakeAt(player: Player, at: number)
	schedule(math.max(0, at - serverNow()) + WAKE_SLACK, function()
		tickPlayer(player)
	end)
end

-- Sends the train off with everything in its cargo. Returns true when it left.
function TrainService.depart(player: Player): boolean
	local data = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if not data or not plotId then
		return false
	end
	local train = trainOf(data)
	if #train.Cargo == 0 or isAway(player, train) then
		return false
	end
	-- no yield from here until the trip is saved
	for _, item in train.Cargo do
		table.insert(train.TripCargo, item)
	end
	train.Cargo = {}
	local seconds = tripSecondsOf(player, train)
	local wall = wallClock()
	train.TripDepartAt = wall
	train.TripArriveAt = wall + seconds
	local r = runtimeOf(player)
	local server = serverNow()
	r.LastLoad = nil
	r.DepartAt = server
	r.ArriveAt = server + seconds
	r.ReturnUntil = nil
	r.NextRetry = nil
	r.Waiting = false
	r.PenFull = false
	r.Chute = false
	r.ChuteFailed = false
	r.Delivered = 0
	r.Chuted = 0
	r.Trip = nil
	rememberTrip(player.UserId, train, server, server + seconds)
	DataService.changed(player)
	broadcast(player, train)
	wakeAt(player, server + seconds)
	return true
end

--[[
	Unloads an arrived train into the Ore Pen, up to the pen's capacity;
	with Direct Unload its dirty ore stays on board for the TRAIN chute
	(see that section). `away`: the trip arrived while the player was away
	(joining): it unloads without the unload effect and the return trip and
	says the count once. What doesn't fit (or pours out of the chute) stays
	on the train, which then waits at the stop for everyone to see
	(Waiting, see the header) and is tried again later; once it is empty it
	unloads with the effect and rolls back from then.
]]
local function deliver(player: Player, data: { [string]: any }, away: boolean?)
	local train = trainOf(data)
	local storage = data.Storage
	if type(storage) ~= "table" then
		return
	end
	local r = runtimeOf(player)
	local capacity = ItemService.penCapacity(data)
	local chute = chuteReady(player, data, r)
	local moved = 0
	local delivered: { Desc } = {}
	local penFull = false
	local onBoard = 0
	-- no yield between taking an item off the train and putting it into the pen
	local cargo = train.TripCargo
	local i = 1
	while i <= #cargo do
		local item = cargo[i]
		if chute and pours(item) then
			-- Direct Unload: it leaves from here, onto the TRAIN chute's belt
			onBoard += 1
			i += 1
		elseif #storage < capacity then
			table.remove(cargo, i)
			local stored = { K = item.K, O = item.O, G = item.G, R = item.R }
			table.insert(storage, stored)
			table.insert(delivered, stored)
			moved += 1
		else
			penFull = true
			i += 1
		end
	end
	r.Delivered += moved
	arrivedInPen(player, delivered)
	local was = `{r.Chute}/{r.PenFull}`
	r.Chute = onBoard > 0
	local newlyFull = penFull and not r.PenFull
	r.PenFull = penFull
	if r.Chute then
		PenService.unloadTrain(player)
	end
	local now = serverNow()
	if #cargo > 0 then
		r.NextRetry = now + (if r.Chute then CHUTE_RETRY else TrainConfig.DeliveryRetry)
		-- (shares the throttle with the bounce toasts that say the same)
		if newlyFull then
			-- over its capacity (a rescue overfilled it) or just full: one toast that says which
			local text = if PenService.isOver(data) then TrainService.PenOverText else TrainService.PenFullText
			throttledToast(player, text, text)
		end
		if r.Waiting then
			if moved > 0 or was ~= `{r.Chute}/{r.PenFull}` then
				DataService.changed(player)
			end
			return
		end
		-- the first try that leaves ore on the train: it waits at the stop
		r.Waiting = true
		if away and moved > 0 then
			toast(player, `Your train brought {moved} ore to your Ore Pen while you were away.`, "Info")
		end
		DataService.changed(player)
		-- everyone sees it standing there (without a plot yet: announced when it comes)
		broadcast(player, train)
		return
	end
	local count = r.Delivered
	local chuted = r.Chuted
	local waited = r.Waiting
	train.TripDepartAt = 0
	train.TripArriveAt = 0
	sessionTrips[player.UserId] = nil
	local stats = data.Stats
	if type(stats) == "table" then
		stats.TrainTrips = (tonumber(stats.TrainTrips) or 0) + 1
	end
	r.NextRetry = nil
	r.Waiting = false
	r.PenFull = false
	r.Chute = false
	r.ChuteFailed = false
	r.Delivered = 0
	r.Chuted = 0
	if (away and not waited) or count + chuted == 0 then
		-- arrived while away (or an empty trip from a broken save): no effect, no return
		r.DepartAt = nil
		r.ArriveAt = nil
		r.ReturnUntil = nil
		r.Trip = nil
		if count > 0 then
			toast(player, `Your train brought {count} ore to your Ore Pen while you were away.`, "Info")
		end
	else
		-- on time: the arrival the clients animate; after waiting at a full pen: now
		local unloadAt = if waited or not r.ArriveAt then now else r.ArriveAt :: number
		local departAt = r.DepartAt or unloadAt
		local plotId = PlotService.plotOf(player)
		local sent = r.Trip
		if waited and sent and plotId then
			-- everyone sees it unload now (a trip no longer than clients accept)
			if unloadAt - departAt > TrainService.MaxTripSpan then
				departAt = unloadAt - math.clamp(sent.ArriveAt - sent.DepartAt, 0, TrainService.MaxTripSpan)
			end
			local trip = table.clone(sent)
			trip.DepartAt = departAt
			trip.ArriveAt = unloadAt
			trip.Waiting = nil
			r.Trip = trip
			Net.fireAll("TrainTrip", trip)
		end
		r.DepartAt = departAt
		r.ArriveAt = unloadAt
		r.ReturnUntil = unloadAt + TrainConfig.ReturnSeconds
		if plotId and count > 0 then
			Net.fireAll("Fx", "TrainUnload", plotId, count)
		end
	end
	DataService.changed(player)
end

-- "Send": the train leaves now with what it has (TrainAction or the prompt).
function TrainService.send(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local train = trainOf(data)
	if isAway(player, train) then
		hint(player, awayText(player, train), "Info")
		return false
	end
	if #train.Cargo == 0 then
		hint(player, TrainService.EmptyText, "Info")
		return false
	end
	if not PlotService.plotOf(player) then
		hint(player, TrainService.NoPlotText, "Info")
		return false
	end
	return TrainService.depart(player)
end

-- After items went into the cargo: remember the time, tell the HUD, leave when full.
local function afterLoad(player: Player, train: Train, position: Vector3)
	runtimeOf(player).LastLoad = serverNow()
	DataService.changed(player)
	-- the station is shared: everyone close by sees the puff
	Net.fireNear("Fx", position, TrainService.FxRange, nil, "TrainLoad", position)
	if cargoRoom(player, train) <= 0 then
		TrainService.depart(player)
	end
end

---------------------------------------------------------------- intake and prompts

-- Pops a refused item out of a hopper, toward its prompts (out of the box).
local function bounceOut(hook: Hook, record: ItemRecord)
	local part = hook.Part
	local half = part.Size / 2
	local reach = math.sqrt(half.X * half.X + half.Z * half.Z) + BOUNCE_GAP
	local side = Vector3.new(-hook.Out.Z, 0, hook.Out.X) * ((math.random() - 0.5) * 2)
	local position = part.CFrame.Position + hook.Out * reach + side
	ItemService.release(record, CFrame.new(position), hook.Out * OUT_SPEED + Vector3.new(0, OUT_UP, 0))
end

-- Bounces a refused item and tells its owner (the effect at most once per
-- RejectCooldown per item, the toast throttled per kind).
local function refuse(hook: Hook, record: ItemRecord, owner: Player, text: string)
	local position = record.Body.CFrame.Position
	bounceOut(hook, record)
	throttledToast(owner, text, text)
	local now = serverNow()
	local last = lastReject[record]
	if last and now >= last and now - last < GameConfig.RejectCooldown then
		return
	end
	lastReject[record] = now
	Net.fire("Fx", owner, "Reject", position)
end

--[[
	An item came to rest in (or flew into) a hopper. It goes into its owner's
	cargo while there is room and the train is at the station; everything
	else bounces back out.
]]
local function onIntake(hook: Hook, record: ItemRecord)
	if record.State ~= "Loose" then
		return
	end
	local owner = Players:GetPlayerByUserId(record.Owner)
	local data = if owner then DataService.get(owner) else nil
	if not owner or not data or not PlotService.plotOf(owner) then
		bounceOut(hook, record)
		return
	end
	-- a dusty relic is cleaned, never shipped (ArtifactService)
	if record.Kind == "Relic" then
		refuse(hook, record, owner, ItemData.RelicRefused)
		return
	end
	local train = trainOf(data)
	if isAway(owner, train) then
		refuse(hook, record, owner, awayText(owner, train))
		return
	end
	if cargoRoom(owner, train) <= 0 then
		refuse(hook, record, owner, TrainService.FullText)
		return
	end
	local position = record.Body.CFrame.Position
	-- no yield between taking it out of the world and loading it
	table.insert(train.Cargo, ItemService.absorb(record))
	afterLoad(owner, train, position)
end

local function isNear(player: Player, position: Vector3, range: number): boolean
	local root = Guard.rootPart(player)
	return root ~= nil and (root.Position - position).Magnitude <= range + RANGE_SLACK
end

-- "Load Train": everything you carry goes into your cargo while there is room.
local function loadFromHands(player: Player, hook: Hook)
	local data = DataService.get(player)
	if not data or not PlotService.plotOf(player) then
		return
	end
	if not isNear(player, hook.Point, TrainService.LoadRange) then
		return
	end
	local train = trainOf(data)
	if #CarryService.list(player) == 0 then
		hint(player, TrainService.HandsText, "Info")
		return
	end
	if isAway(player, train) then
		hint(player, awayText(player, train))
		return
	end
	local loaded = 0
	for _ = 1, MAX_LOAD do
		if cargoRoom(player, train) <= 0 then
			break
		end
		local record = CarryService.takeTop(player, function(r: ItemRecord): boolean
			-- (a dusty relic stays in the hands: it is cleaned, never shipped)
			return r.Owner == player.UserId and r.State == "Carried" and r.Kind ~= "Relic"
		end)
		if not record then
			break
		end
		-- no yield between taking it off the stack and loading it
		table.insert(train.Cargo, ItemService.absorb(record))
		loaded += 1
	end
	if loaded > 0 then
		afterLoad(player, train, hook.Part.CFrame.Position)
	end
	if #CarryService.list(player) > 0 then
		hint(player, if isAway(player, train) then awayText(player, train) else TrainService.FullText)
	end
end

local function makePrompt(
	parent: Instance,
	name: string,
	action: string,
	text: string,
	objectText: string,
	role: PromptConfig.Role,
	slot: number
): ProximityPrompt
	-- UIOffset = (0, slot * PromptSlotHeight): TrainConfig's step is PromptConfig.SlotHeight
	local prompt = PromptConfig.make({
		Role = role,
		Name = name,
		ActionText = text,
		ObjectText = objectText,
		Distance = 10,
		Slot = slot,
	})
	prompt:SetAttribute("Action", action)
	prompt:SetAttribute("Slot", slot)
	prompt:AddTag(TrainService.PromptTag)
	prompt.Parent = parent
	return prompt
end

-- World position of an attachment (WorldPosition without needing the engine).
local function worldPoint(attachment: Attachment): Vector3
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return (parent.CFrame * attachment.CFrame).Position
	end
	return attachment.CFrame.Position
end

local function liftIdOf(instance: Instance): string?
	local value = instance:GetAttribute("LiftId")
	return if type(value) == "string" then value else nil
end

-- The station or lift a hopper belongs to: the ancestor tagged TrainStation /
-- MineLift (or a model with a LiftId), else the nearest model, never above
-- the railway.
local function hookRoot(part: BasePart): Instance?
	local node = part.Parent
	local nearest: Instance? = nil
	while node and node ~= Workspace and node ~= watchedRailway and node.Name ~= "Railway" do
		if node:HasTag(TrainService.StationTag) or node:HasTag(TrainService.LiftTag) then
			return node
		end
		if node:IsA("Model") then
			if liftIdOf(node) then
				return node
			end
			nearest = nearest or node
		end
		node = node.Parent
	end
	return nearest
end

-- Intake zone and prompts for one hopper (once per part).
local function setupHook(part: BasePart): Hook
	for _, existing in hooks do
		if existing.Part == part then
			return existing
		end
	end
	local root = hookRoot(part)
	local found = if root then root:FindFirstChild("PromptPoint", true) else nil
	local point = if found and found:IsA("Attachment") then found else nil
	local liftId = liftIdOf(part) or (if root then liftIdOf(root) else nil)
	local isLift = liftId ~= nil or (root ~= nil and root:HasTag(TrainService.LiftTag))
	local name = if isLift then "Mine Lift" else "Mine Station"
	local center = part.CFrame.Position
	local position = if point then worldPoint(point) else center
	local offset = position - center
	local out = Vector3.new(offset.X, 0, offset.Z)
	if out.Magnitude < 0.5 then
		local look = part.CFrame.LookVector
		out = Vector3.new(look.X, 0, look.Z)
		if out.Magnitude < 0.5 then
			out = Vector3.new(0, 0, 1)
		end
	end
	local hook: Hook = { Part = part, Name = name, LiftId = liftId, Point = position, Out = out.Unit }
	table.insert(hooks, hook)
	IntakeService.addZone("Train" .. (liftId or "Station"), part, function(record: ItemRecord)
		onIntake(hook, record)
	end)
	local anchor: Instance = point or part
	local slots = TrainService.PromptSlots
	local load = makePrompt(anchor, "TrainLoadPrompt", "Load", "Load Train", name, "Main", slots.Load)
	load.Triggered:Connect(function(player: Player)
		loadFromHands(player, hook)
	end)
	local send = makePrompt(anchor, "TrainSendPrompt", "Send", "Send Train", name, "Second", slots.Send)
	send.Triggered:Connect(function(player: Player)
		TrainService.send(player)
	end)
	return hook
end

local function tryHook(instance: Instance)
	if instance:IsA("BasePart") and instance:HasTag(TrainService.HookTag) and instance.Parent then
		setupHook(instance)
	end
end

-- Every hook under the railway, now and later (deferred: a model being
-- built gets its attachments before the hook is set up). `added` is the
-- railway's DescendantAdded (the tests pass their own). A railway built
-- again replaces the old one; hooks whose part is gone are dropped.
local function watchRailway(railway: Instance, added: RBXScriptSignal<Instance>?)
	watchedRailway = railway
	for i = #hooks, 1, -1 do
		if not hooks[i].Part.Parent then
			table.remove(hooks, i)
		end
	end
	for _, d in railway:GetDescendants() do
		tryHook(d)
	end
	local previous = railwayConnection
	if previous then
		previous:Disconnect()
	end
	local signal: RBXScriptSignal<Instance> = added or railway.DescendantAdded
	railwayConnection = signal:Connect(function(d: Instance)
		task.defer(tryHook, d)
	end)
end

-- The map's railway now and every "Railway" built into the map later
-- (`childAdded` is the map's ChildAdded; the tests pass their own).
local function watchMap(map: Instance, childAdded: RBXScriptSignal<Instance>?)
	local railway = map:FindFirstChild("Railway")
	if railway then
		watchRailway(railway)
	else
		warn("[TrainService] Workspace.Map has no Railway yet: the train hoppers come with it")
	end
	local previous = mapConnection
	if previous then
		previous:Disconnect()
	end
	local signal: RBXScriptSignal<Instance> = childAdded or map.ChildAdded
	mapConnection = signal:Connect(function(child: Instance)
		if child.Name == "Railway" and child ~= watchedRailway then
			watchRailway(child)
		end
	end)
end

-- A part tagged TrainHopper after it was built (or rebuilt) under the railway.
local function onTagged(instance: Instance)
	local railway = watchedRailway
	if railway and instance:IsDescendantOf(railway) then
		task.defer(tryHook, instance)
	end
end

---------------------------------------------------------------- TrainAction

--[[
	Buys the next Capacity / Speed level. `expected` is the level the
	player's card shows to buy (current + 1); anything else is "Stale" and
	changes nothing, without a toast (the State push shows the real level).
]]
function TrainService.upgrade(player: Player, kind: string, expected: number?): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	if kind ~= "Capacity" and kind ~= "Speed" then
		return false, "BadKind"
	end
	local train = trainOf(data)
	local isCapacity = kind == "Capacity"
	local list = if isCapacity then TrainConfig.Capacity else TrainConfig.Speed
	local level = if isCapacity then train.CapacityLevel else train.SpeedLevel
	if expected ~= level + 1 then
		return false, "Stale"
	end
	local price = TrainConfig.nextPrice(list, level)
	if not price then
		toast(player, "Your train is already at the top level.", "Info")
		return false, "Max"
	end
	if not EconomyService.spend(player, price, "Train" .. kind) then
		toast(player, `You need {Format.money(price)} for this train upgrade.`)
		return false, "Coins"
	end
	-- no yield between paying and the new level
	if isCapacity then
		train.CapacityLevel = level + 1
	else
		train.SpeedLevel = level + 1
	end
	DataService.changed(player)
	local express = hasExpress(player)
	local text = if isCapacity
		then `Train upgraded: {TrainConfig.capacity(level + 1, express)} cargo slots!`
		else `Train upgraded: {string.format("%g", TrainConfig.tripSeconds(level + 1, express, tripCut(player)))} s trips!`
	toast(player, text, "Reward")
	return true, nil
end

-- TrainAction ("Send") or ("Upgrade", { Kind = "Capacity" | "Speed", Level = the level bought })
local function onAction(player: Player, actionArg: any, argArg: any)
	local action = Guard.string(actionArg, 16)
	if not action or not DataService.get(player) then
		return
	end
	if action == "Send" then
		TrainService.send(player)
	elseif action == "Upgrade" then
		local arg = Guard.table(argArg, 4)
		local kind = if arg then Guard.string(arg.Kind, 16) else nil
		-- (a level that isn't a whole number in range is never the next one: Stale)
		local level = if arg then Guard.integer(arg.Level, 1, 1000) else nil
		if kind == "Capacity" or kind == "Speed" then
			TrainService.upgrade(player, kind, level)
		end
	end
end

---------------------------------------------------------------- the 1 s loop

local function tickOne(player: Player, now: number)
	if not player.Parent then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local train = trainOf(data)
	local r = runtimeOf(player)
	-- on the move or waiting at the stop: unload when it has arrived
	if #train.TripCargo > 0 or train.TripArriveAt > 0 then
		local _, arriveAt = tripTimes(player.UserId, train, r)
		local retry = r.NextRetry
		if now >= arriveAt and (not retry or now >= retry) then
			deliver(player, data)
		end
		return
	end
	-- back at the station after unloading
	if r.ReturnUntil and now >= r.ReturnUntil then
		r.ReturnUntil = nil
		r.DepartAt = nil
		r.ArriveAt = nil
		r.Trip = nil
		DataService.changed(player)
	end
	-- (no plot: the train can't leave, so no countdown either)
	if #train.Cargo == 0 or isReturning(player) or not PlotService.plotOf(player) then
		return
	end
	-- leave when full (not right after joining: perks may still come), or
	-- AutoDepartSeconds after the last load
	local lastLoad = r.LastLoad
	local loadedAt = r.LoadedAt
	local settled = not loadedAt or now < loadedAt or now - loadedAt >= TrainService.JoinGrace
	if settled and cargoRoom(player, train) <= 0 then
		TrainService.depart(player)
	elseif not lastLoad or now < lastLoad then
		r.LastLoad = now
		DataService.changed(player)
	elseif now - lastLoad >= TrainConfig.AutoDepartSeconds then
		TrainService.depart(player)
	end
end

-- One player's train, safely (an error never stops anyone else's).
tickPlayer = function(player: Player)
	local ok, err = pcall(tickOne :: any, player, serverNow())
	if not ok then
		warn(`[TrainService] train of {player.Name} failed: {err}`)
	end
end

--[[
	Direct Unload's hand-over to PenService's Train lane (PenService.TrainCargo):
	the cargo list while the arrived train pours out of the TRAIN chute,
	and what happened to each item it took. After the last dirty ore (or
	when spawning failed for good) the train unloads the rest right away.
]]
local cargoSource: PenService.TrainCargo = {
	list = function(player: Player, data: { [string]: any }): { Desc }?
		local r = runtimes[player]
		if not r or not r.Chute then
			return nil
		end
		return trainOf(data).TripCargo
	end,
	sent = function(player: Player, ok: boolean)
		local r = runtimes[player]
		local data = DataService.get(player)
		if not r or not data then
			return
		end
		if ok then
			r.Chuted += 1
		else
			r.ChuteFailed = true
		end
		if not ok or not chuteOre(trainOf(data)) then
			r.NextRetry = nil
			tickPlayer(player)
		end
	end,
}

-- Arrivals, pen-full retries, returns and auto departures for every player.
function TrainService.tick()
	for _, player in Players:GetPlayers() do
		tickPlayer(player)
	end
end

---------------------------------------------------------------- joining

-- A joining player's train to every client (once per session, when both
-- the save and the plot are ready): on the move, or waiting at its stop.
local function announce(player: Player)
	local r = runtimes[player]
	local data = DataService.get(player)
	if not r or not r.Prepared or r.Announced or not data then
		return
	end
	local train = trainOf(data)
	if #train.TripCargo == 0 then
		return
	end
	local _, arriveAt = tripTimes(player.UserId, train, r)
	-- (arrived but not tried yet: the arrival unloads it in a moment)
	if arriveAt > serverNow() or r.Waiting then
		broadcast(player, train)
	end
end

-- Everyone else's trains that carry ore, for a joining player (a list, maybe
-- empty). Empty trains rolling back are left out (Count 0 never happens).
local function sendTripsTo(player: Player)
	local list: { Trip } = {}
	for other in runtimes do
		local data = if other ~= player then DataService.get(other) else nil
		if data then
			local trip = tripOf(other, trainOf(data))
			if trip then
				table.insert(list, trip)
			end
		end
	end
	Net.fire("TrainTrip", player, list)
end

local function onLoaded(player: Player, data: { [string]: any })
	local train = trainOf(data)
	local r = runtimeOf(player)
	local wall = wallClock()
	local server = serverNow()
	r.LoadedAt = server
	if #train.TripCargo > 0 then
		-- a save from a server with a skewed clock: never more than a full trip away
		local longest = TrainConfig.tripSeconds(0, false)
		if train.TripArriveAt > wall + longest then
			train.TripArriveAt = wall + tripSecondsOf(player, train)
		end
		if train.TripDepartAt <= 0 or train.TripDepartAt > train.TripArriveAt then
			train.TripDepartAt = train.TripArriveAt - tripSecondsOf(player, train)
		end
		local _, arriveAt = tripTimes(player.UserId, train, r)
		if server >= arriveAt then
			-- arrived while away: no animation (unless the pen is full: then it waits at the stop)
			deliver(player, data, true)
		else
			wakeAt(player, arriveAt)
		end
	else
		train.TripDepartAt = 0
		train.TripArriveAt = 0
	end
	if #train.Cargo > 0 then
		r.LastLoad = server
	end
	r.Prepared = true
	sendTripsTo(player)
	announce(player)
	DataService.changed(player)
end

-- A rebirth (RebirthService) emptied the train in the save: forget the trip on
-- the way and start over from the save, as at a join.
function TrainService.resetRun(player: Player)
	local old = runtimes[player]
	local plotId = PlotService.plotOf(player)
	if old and old.Announced and plotId then
		-- everyone saw this train on its way or waiting at the stop: it empties and rolls back
		Net.fireAll("Fx", "TrainUnload", plotId, 0)
	end
	sessionTrips[player.UserId] = nil
	runtimes[player] = nil
	local data = DataService.get(player)
	if data then
		onLoaded(player, data)
	end
end

---------------------------------------------------------------- state snapshot

local function provide(player: Player, data: { [string]: any }, snapshot: { [string]: any })
	local train = trainOf(data)
	local r = runtimes[player]
	local express = hasExpress(player)
	local away = isAway(player, train)
	local now = serverNow()
	local departAt: number?, arriveAt: number? = nil, nil
	if r and #train.TripCargo > 0 then
		departAt, arriveAt = tripTimes(player.UserId, train, r)
	elseif r and isReturning(player) then
		-- rolling back: the client works out "returning" from ArriveAt + ReturnSeconds
		departAt, arriveAt = r.DepartAt, r.ArriveAt
	end
	local lastLoad = r and r.LastLoad
	local autoIn: number? = nil
	if not away and #train.Cargo > 0 and lastLoad and PlotService.plotOf(player) then
		autoIn = math.max(0, lastLoad + TrainConfig.AutoDepartSeconds - now)
	end
	local unloading = isUnloading(player, train)
	local waiting = isWaiting(player, train)
	snapshot.Train = {
		Cargo = #train.Cargo,
		Capacity = TrainConfig.capacity(train.CapacityLevel, express),
		Moving = #train.TripCargo,
		DepartAt = departAt,
		ArriveAt = arriveAt,
		CapacityLevel = train.CapacityLevel,
		SpeedLevel = train.SpeedLevel,
		NextCapacityPrice = TrainConfig.nextPrice(TrainConfig.Capacity, train.CapacityLevel),
		NextSpeedPrice = TrainConfig.nextPrice(TrainConfig.Speed, train.SpeedLevel),
		Express = express,
		TripSeconds = TrainConfig.tripSeconds(train.SpeedLevel, express, tripCut(player)),
		TripCut = tripCut(player),
		AutoDepartIn = autoIn,
		Waiting = waiting,
		-- why it waits: the pen is over its capacity, or full
		WaitReason = if waiting then (if PenService.isOver(data) then PenService.OverReason else "PenFull") else nil,
		Unloading = unloading,
		UnloadWait = if unloading then PenService.laneWait(player, "Train") else nil,
	}
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/TrainService.spec.luau).
TrainService._test = {
	action = onAction,
	intake = onIntake,
	load = loadFromHands,
	setupHook = setupHook,
	watch = watchRailway,
	watchMap = watchMap,
	hooks = function(): number
		return #hooks
	end,
	tagged = onTagged,
	loaded = onLoaded,
	announce = announce,
	provide = provide,
	tickOne = tickOne,
	cargo = cargoSource,
	runtime = function(player: Player): Runtime?
		return runtimes[player]
	end,
	-- what leaving does to the unsaved state (a rejoin starts from the save)
	forget = function(player: Player)
		runtimes[player] = nil
	end,
	-- wall: the wall clock for the saved times; server: GetServerTimeNow(); after: the arrival timer
	setClock = function(wall: (() -> number)?, server: (() -> number)?, after: ((number, () -> ()) -> ())?)
		wallClock = wall or defaultWallClock
		serverNow = server or defaultServerNow
		schedule = after or defaultSchedule
	end,
	reset = function()
		table.clear(runtimes)
		table.clear(sessionTrips)
		table.clear(hooks)
		watchedRailway = nil
		railwayConnection = nil
		mapConnection = nil
		wallClock = defaultWallClock
		serverNow = defaultServerNow
		schedule = defaultSchedule
	end,
}

local function watchPerk(player: Player)
	if perkConnections[player] then
		return
	end
	perkConnections[player] = player:GetAttributeChangedSignal("Perk_TrainExpress"):Connect(function()
		DataService.changed(player)
	end)
end

function TrainService.init()
	Net.on("TrainAction", onAction)
	PenService.setTrainCargo(cargoSource)
	StateService.addProvider(provide)
	DataService.onLoaded(onLoaded)
	PlotService.onAssigned(function(player: Player)
		announce(player)
	end)
	Players.PlayerAdded:Connect(watchPerk)
	for _, player in Players:GetPlayers() do
		watchPerk(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		runtimes[player] = nil
		-- the loop or an arrival timer may touch a leaving player once more before the save is released
		task.delay(5, function()
			runtimes[player] = nil
		end)
		local connection = perkConnections[player]
		if connection then
			connection:Disconnect()
			perkConnections[player] = nil
		end
	end)
end

function TrainService.start()
	CollectionService:GetInstanceAddedSignal(TrainService.HookTag):Connect(onTagged)
	-- WorldService.init has built (or kept) the map, the railway with it
	local map: Instance? = WorldService.Map or Workspace:FindFirstChild("Map")
	if map then
		watchMap(map)
	else
		task.spawn(function()
			watchMap(Workspace:WaitForChild("Map"))
		end)
	end
	while true do
		task.wait(1)
		TrainService.tick()
	end
end

return TrainService
