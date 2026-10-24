--[[
	PenService: the Ore Pen in every base yard (design v2). Each player has
	one pen, saved as data.Storage (a list of item descriptors { K, O, G?, R? }).

	- Capacity: EconomyConfig.penCapacity(Upgrades.PenLevel, GameConfig.MaxStoredItems)
	  (pen upgrades are bought in the shops, step 6). Players and their
	  automation can only fill the pen up to it (store, hasRoom, refusal).
	  Only rescue moves (ItemService.storeDesc: leaving, an item the engine
	  lost, Placement repair, an item returned from someone else's plot)
	  may overfill it, up to GameConfig.MaxStoredItems.
	- Over capacity (#Storage > capacity, after a rescue or a smaller pen):
	  the pen takes nothing new from the player or their automation, all
	  with ONE reason code, PenService.OverReason ("PenOver"): throwing ore
	  in and Put In bounce / refuse with OverText, the train's cargo waits
	  at the station (TrainService: Train.WaitReason "PenOver"), a podium's
	  Remove is refused (PodiumService), the sinks and the Iron Box keep
	  route (store / hasRoom) refuse. Take, Sell and Send still work, so the
	  player can always get back under it. The State shows it: PenOver =
	  true next to StorageCount / PenCapacity (PenView turns red).
	- In: drop or throw your own items into the pen (the yard's Pen.Intake
	  box, an IntakeService zone), or press "Put In" (E / gamepad Y) at the
	  pen gate while carrying items. Items of other players are not taken:
	  they bounce back out of the gate. A full pen bounces items too (toast).
	- Out: "Open Pen" (G / gamepad B) opens PenView (OpenUI "Pen"). PenAction:
	    "Take"     { Key, Count 1..StorageTakeMax }: the items appear at the
	               gate and go into your hands while they have room
	    "ToPodium" { Key, Slot }: puts one cleaned ore on a podium (PodiumService)
	    "Send"     { Key, Count? } | { Key, All = true } | { Filter, Count? }:
	               a send intent (below). A Count (a key alone: 1) is that
	               many more; All and a filter without Count are all of
	               them: what is in the pen now, the queued ones included
	               (a second press never sends extra)
	    "StopSend" (no arg): drops every send intent of the pen (Pen lane)
	    "AutoSort" { On: boolean }: the sorting billboard on / off (below)
	  Checks: types (Guard), ItemData.parseKey, your own plot, standing within
	  Range (+ slack) of your pen gate (StopSend and AutoSort: anywhere).
	- Send (step 3, WP-Belts, docs/plans/STEP3_PLAN.md): every player has a
	  send queue with two lanes, one per Source chute (BaseLayout.Chutes):
	    Pen    "Send" from the pen panel, and the sorting billboard
	    Train  the train's Direct Unload (straight from the train, below)
	  A lane holds INTENTS only ({ Key, Left } or { Filter, Left }, or the
	  Train lane's Cargo intent), never items: every item stays where it is
	  (data.Storage, or the train's TripCargo) until the step that spawns it,
	  which takes it out of that list and puts it onto the chute's belt
	  (ConveyorService.spawnAtSource) with no yield in between; when nothing
	  spawned it goes straight back to the same index. One item per lane
	  every SendInterval seconds, while the belt on the chute cell feeds
	  (ConveyorService.sourceReady: a belt there, not facing the yard, with
	  room, the owner below ConveyorService.sourceCeiling() loose items,
	  which leaves room for their machines' finished items, so a long line
	  keeps draining); otherwise the lane waits and the State says why, per
	  lane. An intent ends when nothing matches it any more.
	  Only entries that can become an item match (ConveyorService.spawnable:
	  a known kind, ore, grade and recipe): a broken save entry stays in the
	  pen and never blocks a lane; an entry that still fails to spawn
	  ("Bad") is kept and its intent dropped, so nothing waits behind it.
	  Leaving, losing the plot or StopSend just drops the intents: there is
	  nothing to put back. Filters: "Dirty" (dirty ore), "Unkept"
	  (everything MachineData.keeps doesn't keep; needs PenAutomation >= 1)
	  and "All"; a Filter intent covers what matched when it was asked for.
	- Sorting billboard (Upgrades.PenAutomation >= EconomyConfig.PenAutomation.Billboard,
	  while data.AutoSort ~= false; PenAction "AutoSort" switches it, the pen
	  panel has the button): items a player brings to the pen (thrown in, Put
	  In, a train delivery: arrived()) that MachineData.keeps doesn't keep
	  (data.KeepMode / KeepList: dirty ore, crushed ore, ingots and the clean
	  ore the player doesn't keep) get a Pen-lane intent at once (marked Auto:
	  switching auto-sort off drops those), while a belt feeds from the PEN
	  chute (no belt: they simply stay in the pen); a full queue says so.
	  An Auto intent only sends what is still unkept when it spawns (keeping
	  that ore later in the Iron Box view stops it). The first time in a
	  session the billboard sends something, a toast says so and where to
	  switch it off. A board on the pen's front wall shows "AUTO-SORT ON" /
	  "OFF", what is kept and the lane's state. WP-Belts owns the board and
	  arrived(); the Iron Box view (WP-CleanerBox) only edits KeepMode /
	  KeepList.
	  arrived() is ONLY for those sources: machines (the Iron Box) store
	  with PenService.store (it refuses at the pen's capacity: then their
	  item waits), or
	  the billboard would send their items out again in a loop.
	- Direct Unload (PenAutomation >= EconomyConfig.PenAutomation.DirectUnload,
	  TrainService): with a belt feeding from the TRAIN chute, the arrived
	  train keeps its dirty ore on board (TripCargo, saved) and stands at
	  your stop while the Train lane's Cargo intent pours it out onto that
	  belt, one item every SendInterval, never through the pen (a full pen
	  doesn't matter); only its other items go into the pen. TrainService
	  registers where that cargo is (setTrainCargo) and adds the intent
	  (unloadTrain); the intent ends when no dirty ore is left on board or
	  the train stops unloading that way (belt gone: the rest goes into the
	  pen as without the upgrade).
	- StateService gets PenCapacity, PenOver (true while over capacity), AutoSort and PenSend = { Pen, Train
	  (items still to send per lane), PenWait?, TrainWait? (why that lane
	  waits, a line for the player) }; TrainService puts the Train lane's
	  reason (laneWait) into its Train snapshot (UnloadWait) for TrainView.
	Prompts are made for every plot once; the client shows them only on your
	own pen ("Put In" only while you carry something), the server checks again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local MachineData = require(Shared.Config.MachineData)
local OreData = require(Shared.Config.OreData)
local PromptConfig = require(Shared.Config.PromptConfig)
local Rarity = require(Shared.Config.Rarity)
local WorldLayout = require(Shared.Config.WorldLayout)
local Geo = require(Shared.Builders.Geo)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local PlotService = require(script.Parent.PlotService)
local MachineService = require(script.Parent.MachineService)
local IntakeService = require(script.Parent.IntakeService)
local ConveyorService = require(script.Parent.ConveyorService)

local PenService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord
type SourceWait = ConveyorService.SourceWait
export type PodiumPlacer = (player: Player, slot: number, key: string) -> (boolean, string?)
export type SendFilter = "Dirty" | "Unkept" | "All"
export type SendLane = "Pen" | "Train" -- = the Source chute it spawns on (BaseLayout.Chutes)
-- Where items reach the pen from, for arrived() (nothing else may call it: header).
export type ArrivalSource = "Pen" | "Train"
--[[
	Direct Unload (TrainService registers it with setTrainCargo):
	  list(player, data)  the train's cargo while it stands at your stop
	                      pouring its dirty ore onto the TRAIN chute's
	                      belt (data.Train.TripCargo), else nil
	  sent(player, ok)    one of its items just rode out (ok), or spawning
	                      one failed for good (not ok: unload the rest the
	                      old way); TrainService finishes the unload
]]
export type TrainCargo = {
	list: (player: Player, data: { [string]: any }) -> { Desc }?,
	sent: (player: Player, ok: boolean) -> (),
}
-- one send intent: that many of one storage key, or of a filter; Auto =
-- queued by the sorting billboard; Cargo = the Train lane's Direct Unload
-- (the train's dirty ore, as long as there is any; Left unused)
type Intent = { Key: string?, Filter: SendFilter?, Left: number, Auto: boolean?, Cargo: boolean? }
type Lane = { Intents: { Intent }, NextAt: number, Wait: SourceWait? }
type Queue = { Pen: Lane, Train: Lane }
type Board = { Model: Model, Title: TextLabel, Body: TextLabel, Status: TextLabel }

PenService.Range = 24 -- studs from your pen gate (PenView closes beyond this)
PenService.PromptTag = "PenPrompt"
local RANGE_SLACK = 4 -- the server allows a little more (lag, walking while clicking)
local FULL_TOAST_COOLDOWN = 5
local FOREIGN_TOAST_COOLDOWN = 8
local TAKE_SPACING = 0.6 -- taken items appear this much higher each
local MAX_PUT_IN = 64 -- more than any carry stack
local MAX_KEY_LENGTH = 80
local GATE_OUT = 1.6 -- studs in front of the gate where items come out
local HANDS_FULL = "Your hands are full and lots of items are lying around. Pick some up first!"
local OVER_TOAST_COOLDOWN = 5

-- The one reason code for "the pen is over its capacity" (see the header).
PenService.OverReason = "PenOver"
PenService.FullReason = "PenFull"

-- send queue (WP-Belts)
PenService.SendInterval = 0.5 -- seconds between two items leaving one chute
PenService.MaxIntents = 24 -- send intents per lane (equal ones are merged)
PenService.SendFilters = { Dirty = true, Unkept = true, All = true } :: { [string]: boolean }
PenService.BoardTitle = "AUTO-SORT ON"
PenService.BoardTitleOff = "AUTO-SORT OFF"
PenService.AutoOnText = "Auto-sort on: ore you don't keep rides out of your PEN chute. The Iron Box sets what you keep."
PenService.AutoOffText = "Auto-sort off: everything you bring stays in your Ore Pen."
PenService.QueueFullText = "Your send queue is full: some ore stays in your Ore Pen."
PenService.AutoFirstText = "Auto-sort is sending ore you don't keep out of your PEN chute. You can switch it off in your Ore Pen."
local SEND_TICK = 0.1
local SEND_RETRY = 0.25 -- a waiting lane looks again this often
local LANES: { SendLane } = { "Pen", "Train" }
local CHUTE_PLACE = "(the blue plate on the back row of your build grid)"

local lastFullToast: { [Player]: number } = {}
local lastOverToast: { [Player]: number } = {}
local lastForeignToast: { [Player]: number } = {}
local lastQueueToast: { [Player]: number } = {}
local autoTold: { [Player]: boolean } = {} -- the first auto-sort toast of the session
local podiumPlacer: PodiumPlacer? = nil
local trainCargo: TrainCargo? = nil
local queues: { [Player]: Queue } = {}
local boards: { [number]: Board } = {}
local boardDirty: { [number]: boolean } = {}

---------------------------------------------------------------- capacity

function PenService.capacityOf(data: { [string]: any }): number
	return ItemService.penCapacity(data)
end

function PenService.capacity(player: Player): number
	local data = DataService.get(player)
	return if data then PenService.capacityOf(data) else 0
end

function PenService.count(player: Player): number
	local data = DataService.get(player)
	return if data then #data.Storage else 0
end

-- Is the pen holding more than its capacity (a rescue move overfilled it)?
function PenService.isOver(data: { [string]: any }): boolean
	return #data.Storage > PenService.capacityOf(data)
end

--[[
	Why the pen refuses `n` (default 1) more items from the player or their
	automation: "PenOver" (over its capacity: nothing new until it is back
	under), "PenFull" (no room for them), nil = they fit.
]]
function PenService.refusal(data: { [string]: any }, n: number?): string?
	local capacity = PenService.capacityOf(data)
	local count = #data.Storage
	if count > capacity then
		return PenService.OverReason
	elseif count + (n or 1) > capacity then
		return PenService.FullReason
	end
	return nil
end

-- Room for `n` (default 1) more items?
function PenService.hasRoom(player: Player, n: number?): boolean
	local data = DataService.get(player)
	return data ~= nil and PenService.refusal(data, n) == nil
end

-- Puts one item into the pen when it has room (no sale fallback); else
-- false and the reason ("PenOver" | "PenFull" | "NoData"). The caller calls
-- DataService.changed (several changes, one push).
function PenService.store(player: Player, desc: Desc): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	-- a dropper's Drop is never stored (DropperConfig)
	if type(desc) == "table" and desc.K == "Drop" then
		return false, "Wrong"
	end
	local why = PenService.refusal(data)
	if why then
		return false, why
	end
	table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
	return true, nil
end

-- Takes one item with this storage key out of the pen (the newest one).
-- The caller calls DataService.changed.
function PenService.takeOne(player: Player, key: string): Desc?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local storage = data.Storage
	for i = #storage, 1, -1 do
		local entry = storage[i]
		if type(entry) == "table" and type(entry.K) == "string" and type(entry.O) == "string" and ItemData.storageKey(entry) == key then
			table.remove(storage, i)
			return entry :: Desc
		end
	end
	return nil
end

-- PodiumService plugs in here ("ToPodium" lives in PenAction).
function PenService.setPodiumPlacer(placer: PodiumPlacer)
	podiumPlacer = placer
end

---------------------------------------------------------------- the pen in the world

-- The yard model of a plot (nil on maps from before the yards).
function PenService.yard(plotId: number): Model?
	local plot = PlotService.model(plotId)
	local yard = plot and plot:FindFirstChild("Yard")
	return if yard and yard:IsA("Model") then yard else nil
end

-- World CFrame of the pen gate (BaseLayout.Pen.PromptPoint), LookVector
-- toward the machine grid (out of the pen).
function PenService.gateCFrame(plotId: number): CFrame
	return PlotService.plotCFrame(plotId) * CFrame.new(BaseLayout.Pen.PromptPoint)
end

-- Is the player standing near their own pen gate (flat distance)?
function PenService.isNear(player: Player, plotId: number, range: number?): boolean
	local root = Guard.rootPart(player)
	if not root then
		return false
	end
	local gate = PenService.gateCFrame(plotId).Position
	local offset = root.Position - gate
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= (range or PenService.Range) + RANGE_SLACK
end

local function toast(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, { Text = text, Kind = kind or "Deny" })
end

local function fullText(data: { [string]: any }): string
	return `Your Ore Pen is full ({#data.Storage}/{PenService.capacityOf(data)}). Sell ore at Tobin's stall or put some on a podium.`
end

-- The over-capacity line (the same everywhere the pen says "PenOver").
function PenService.overText(data: { [string]: any }): string
	return `Your Ore Pen holds more than it fits ({#data.Storage}/{PenService.capacityOf(data)}): nothing new goes in until you take, sell or send some.`
end

-- The refusal line for a reason from PenService.refusal.
function PenService.refusalText(data: { [string]: any }, why: string?): string
	return if why == PenService.OverReason then PenService.overText(data) else fullText(data)
end

-- The over-capacity toast (at most every OVER_TOAST_COOLDOWN seconds).
local function overToast(player: Player, data: { [string]: any })
	local now = os.clock()
	if now - (lastOverToast[player] or -math.huge) < OVER_TOAST_COOLDOWN then
		return
	end
	lastOverToast[player] = now
	toast(player, PenService.overText(data))
end

local function fullToast(player: Player, data: { [string]: any })
	local now = os.clock()
	if now - (lastFullToast[player] or -math.huge) < FULL_TOAST_COOLDOWN then
		return
	end
	lastFullToast[player] = now
	toast(player, fullText(data))
end

-- Pops a loose item out of the pen gate (refused: pen full or not yours).
local function bounceOut(plotId: number, record: ItemRecord)
	local gate = PenService.gateCFrame(plotId)
	local side = (math.random() - 0.5) * 3
	local out = gate * CFrame.new(side, 0, -GATE_OUT)
	ItemService.release(record, out, gate.LookVector * 8 + Vector3.new(0, 12, 0))
end

--[[
	An item came to rest in (or flew into) a pen's intake box. The owner's
	own items go in while there is room; everything else bounces out.
]]
local function onIntake(plotId: number, record: ItemRecord)
	if record.State ~= "Loose" then
		return
	end
	local owner = PlotService.ownerOf(plotId)
	if not owner or owner.UserId ~= record.Owner then
		bounceOut(plotId, record)
		local thrower = Players:GetPlayerByUserId(record.Owner)
		if thrower then
			local now = os.clock()
			if now - (lastForeignToast[thrower] or -math.huge) >= FOREIGN_TOAST_COOLDOWN then
				lastForeignToast[thrower] = now
				toast(thrower, "That's not your Ore Pen. Your pen is in the yard behind your own forge.", "Info")
			end
		end
		return
	end
	local data = DataService.get(owner)
	if not data then
		bounceOut(plotId, record)
		return
	end
	-- a dusty relic is cleaned, never stored (ArtifactService)
	if record.Kind == "Relic" then
		bounceOut(plotId, record)
		toast(owner, ItemData.RelicRefused, "Info")
		return
	end
	-- a dropper's Drop is never stored (DropperConfig): it just goes
	if record.Kind == "Drop" then
		ItemService.destroy(record)
		return
	end
	local why = PenService.refusal(data)
	if why then
		bounceOut(plotId, record)
		if why == PenService.OverReason then
			overToast(owner, data)
		else
			fullToast(owner, data)
		end
		Net.fire("Fx", owner, "Reject", record.Body.CFrame.Position)
		return
	end
	local position = record.Body.CFrame.Position
	local desc = ItemService.absorb(record)
	table.insert(data.Storage, desc)
	DataService.changed(owner)
	Net.fire("Fx", owner, "PenIn", position)
	PenService.arrived(owner, { desc }, "Pen")
end

---------------------------------------------------------------- prompts

-- "Put In": everything you carry goes in while the pen has room (none
-- while it is over its capacity: "PenOver"). Returns the refusal, if any.
local function putIn(player: Player, plotId: number): string?
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your Ore Pen.")
		return nil
	end
	local data = DataService.get(player)
	if not data then
		return nil
	end
	if #CarryService.list(player) == 0 then
		toast(player, "Carry ore here to put it in your pen.", "Info")
		return nil
	end
	local why = PenService.refusal(data)
	if why == PenService.OverReason then
		toast(player, PenService.overText(data))
		return why
	end
	local stored: { Desc } = {}
	for _ = 1, MAX_PUT_IN do
		if PenService.refusal(data) then
			break
		end
		-- (a dusty relic stays in the hands: it is cleaned, never stored)
		local record = CarryService.takeTop(player, function(r: ItemRecord): boolean
			return r.Kind ~= "Relic"
		end)
		if not record then
			break
		end
		-- no yield between taking it off the stack and storing it
		local desc = ItemService.absorb(record)
		table.insert(data.Storage, desc)
		table.insert(stored, desc)
	end
	if #stored > 0 then
		DataService.changed(player)
		Net.fire("Fx", player, "PenIn", PenService.gateCFrame(plotId).Position + Vector3.new(0, 1, 0))
		PenService.arrived(player, stored, "Pen")
	end
	local held = CarryService.list(player)
	if #held > 0 then
		local left = PenService.refusal(data)
		local onlyRelics = true
		for _, record in held do
			onlyRelics = onlyRelics and record.Kind == "Relic"
		end
		if not left and onlyRelics then
			-- room left: only dusty relics stayed in the hands (never stored)
			toast(player, ItemData.RelicRefused, "Info")
			return nil
		end
		toast(player, PenService.refusalText(data, left))
		return left
	end
	return nil
end

local function openPen(player: Player, plotId: number)
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your Ore Pen.")
		return
	end
	if DataService.get(player) then
		Net.fire("OpenUI", player, "Pen", {})
	end
end

local function makePrompt(
	parent: Instance,
	plotId: number,
	name: string,
	action: string,
	role: PromptConfig.Role,
	order: number
): ProximityPrompt
	local prompt = PromptConfig.make({
		Role = role,
		Name = name,
		ActionText = action,
		ObjectText = "Ore Pen",
		Distance = 10,
		Slot = order,
	})
	prompt:SetAttribute("PlotId", plotId)
	prompt:AddTag(PenService.PromptTag)
	prompt.Parent = parent
	return prompt
end

-- Intake zone and prompts for one plot's pen (once, at start).
local function setupPen(plotId: number): boolean
	local yard = PenService.yard(plotId)
	local pen = yard and yard:FindFirstChild("Pen")
	local intake = pen and pen:FindFirstChild("Intake")
	if not intake or not intake:IsA("BasePart") then
		warn(`[PenService] plot {plotId} has no Yard.Pen.Intake (old map?)`)
		return false
	end
	IntakeService.addZone("Pen" .. plotId, intake, function(record: ItemRecord)
		onIntake(plotId, record)
	end)
	local anchor = intake:FindFirstChild("Prompt") or intake
	local put = makePrompt(anchor, plotId, "PenPutIn", "Put In", "Main", 0)
	put.Triggered:Connect(function(player: Player)
		putIn(player, plotId)
	end)
	local open = makePrompt(anchor, plotId, "PenOpen", "Open Pen", "Second", 1)
	open.Triggered:Connect(function(player: Player)
		openPen(player, plotId)
	end)
	return true
end

---------------------------------------------------------------- PenAction

--[[
	"Take": at most what fits in free hands plus the room left under the
	loose-item cap (so taking never pushes other items back into the pen).
	Each item appears at the pen gate and goes into your hands while they
	have room.
]]
local function takeItems(player: Player, plotId: number, data: { [string]: any }, key: string, count: number): number
	local freeHands = math.max(0, CarryService.capacity(player) - #CarryService.list(player))
	local baseRoom =
		math.max(0, GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom - ItemService.looseCount(player.UserId, "Base"))
	-- and never past the hard ceiling of loose items (GameConfig.MaxLooseItemsTotal)
	local looseRoom = math.min(baseRoom, ItemService.totalRoom(player.UserId))
	local allowed = math.min(count, freeHands + looseRoom)
	if allowed <= 0 then
		toast(player, HANDS_FULL)
		return 0
	end
	local gate = PenService.gateCFrame(plotId) * CFrame.new(0, 0.6, -GATE_OUT)
	local taken = 0
	for i = 1, allowed do
		local entry = PenService.takeOne(player, key)
		if not entry then
			break
		end
		local record = ItemService.spawnDesc(entry, player.UserId, gate + Vector3.new(0, TAKE_SPACING * (i - 1), 0))
		if not record then
			-- never lose it: back into the pen
			table.insert(data.Storage, entry)
			warn(`[PenService] could not take {key} out for {player.Name}`)
			break
		end
		taken += 1
		if freeHands > 0 and CarryService.pickup(player, record) then
			freeHands -= 1
		end
	end
	if taken > 0 then
		DataService.changed(player)
	end
	return taken
end

---------------------------------------------------------------- send queue (step 3, WP-Belts)

-- The player's pen automation level (0 for broken values).
local function automationOf(data: { [string]: any }): number
	local upgrades = data.Upgrades
	local level = if type(upgrades) == "table" then upgrades.PenAutomation else nil
	if type(level) ~= "number" or level ~= level or level < 0 or level == math.huge then
		return 0
	end
	return math.floor(level)
end

-- Is the sorting billboard switched on? (data.AutoSort; anything but false is on)
function PenService.autoSortOn(data: { [string]: any }): boolean
	return data.AutoSort ~= false
end

--[[
	Does this entry (of data.Storage, or of the train's cargo for a Cargo
	intent) belong to the intent? Only entries that can become an item
	(ConveyorService.spawnable) ever match, so a broken one never blocks.
	The billboard's (Auto) intents only take what is still unkept right now:
	ore the player has marked Keep since then stays.
]]
local function matches(intent: Intent, entry: any, data: { [string]: any }): boolean
	if not ConveyorService.spawnable(entry) then
		return false
	end
	if intent.Cargo then
		return entry.K == "Raw"
	end
	local key = intent.Key
	if key then
		if ItemData.storageKey(entry) ~= key then
			return false
		end
		return not intent.Auto or not MachineData.keeps(data.KeepMode, data.KeepList, entry)
	end
	local filter = intent.Filter
	if filter == "Dirty" then
		return entry.K == "Raw"
	elseif filter == "Unkept" then
		return not MachineData.keeps(data.KeepMode, data.KeepList, entry)
	end
	return filter == "All"
end

-- The list an intent takes from: the pen, or (Cargo) the unloading train's cargo.
local function listOf(player: Player, data: { [string]: any }, intent: Intent): { any }?
	if not intent.Cargo then
		return data.Storage
	end
	local source = trainCargo
	if not source then
		return nil
	end
	local ok, list = pcall(source.list, player, data)
	return if ok and type(list) == "table" then list else nil
end

local function countMatching(data: { [string]: any }, intent: Intent): number
	local n = 0
	for _, entry in data.Storage do
		if matches(intent, entry, data) then
			n += 1
		end
	end
	return n
end

local function newLane(): Lane
	return { Intents = {}, NextAt = 0, Wait = nil }
end

local function queueOf(player: Player): Queue
	local queue = queues[player]
	if not queue then
		queue = { Pen = newLane(), Train = newLane() }
		queues[player] = queue
	end
	return queue
end

local function laneOf(queue: Queue, name: SendLane): Lane
	return if name == "Train" then queue.Train else queue.Pen
end

--[[
	Adds a send intent to a lane, merged with an equal one (the same Key and
	the same Auto mark, or the same Filter): a count adds up ("one more"),
	`atLeast` keeps the bigger one ("all of them": what is in the pen now,
	so the ones already queued are part of it, never on top). `cap` (the
	matching items in the pen) bounds the result: an intent never asks for
	more than there is. Returns false when the lane already holds
	MaxIntents other intents. The caller pushes the State.
]]
local function addIntent(
	lane: Lane,
	key: string?,
	filter: SendFilter?,
	count: number,
	auto: boolean?,
	atLeast: boolean?,
	cap: number?
): boolean
	local isAuto = auto == true
	local limit = math.min(cap or GameConfig.MaxStoredItems, GameConfig.MaxStoredItems)
	for _, intent in lane.Intents do
		local sameKey = key ~= nil and intent.Key == key and (intent.Auto == true) == isAuto
		local same = sameKey or (filter ~= nil and intent.Filter == filter)
		if same then
			local left = if atLeast then math.max(intent.Left, count) else intent.Left + count
			intent.Left = math.min(left, limit)
			return true
		end
	end
	if #lane.Intents >= PenService.MaxIntents then
		return false
	end
	table.insert(lane.Intents, {
		Key = key,
		Filter = filter,
		Left = math.min(count, limit),
		Auto = if isAuto then true else nil,
	})
	return true
end

--[[
	How many items each lane will still send: the intents in order, each
	taking from what is in the pen right now (an item counts once, even when
	two intents could send it); the Train lane counts the dirty ore still on
	the unloading train.
]]
function PenService.sendCounts(player: Player): (number, number)
	local queue = queues[player]
	local data = DataService.get(player)
	if not queue or not data then
		return 0, 0
	end
	local available: { [string]: number } = {}
	local sample: { [string]: Desc } = {}
	for _, entry in data.Storage do
		if ConveyorService.spawnable(entry) then
			local key = ItemData.storageKey(entry)
			available[key] = (available[key] or 0) + 1
			sample[key] = entry
		end
	end
	local function lane(l: Lane): number
		local total = 0
		for _, intent in l.Intents do
			if intent.Cargo then
				local list: { any } = listOf(player, data, intent) or {}
				for _, entry in list do
					if matches(intent, entry, data) then
						total += 1
					end
				end
				continue
			end
			local need = intent.Left
			for key, n in available do
				if need <= 0 then
					break
				end
				if n > 0 and matches(intent, sample[key], data) then
					local take = math.min(n, need)
					available[key] = n - take
					need -= take
					total += take
				end
			end
		end
		return total
	end
	local pen = lane(queue.Pen)
	return pen, lane(queue.Train)
end

-- Why a lane waits right now (nil: it has nothing queued or doesn't wait).
function PenService.laneWait(player: Player, name: SendLane): SourceWait?
	local queue = queues[player]
	if not queue then
		return nil
	end
	local lane = laneOf(queue, name)
	return if #lane.Intents > 0 then lane.Wait else nil
end

-- The same as a line for the player (the pen panel, the board).
local function waitLine(player: Player, name: SendLane): string?
	local why: SourceWait? = PenService.laneWait(player, name)
	if not why then
		return nil
	end
	return ConveyorService.waitText(name, why)
end

local function markBoard(player: Player)
	local plotId = PlotService.plotOf(player)
	if plotId then
		boardDirty[plotId] = true
	end
end

-- Tells TrainService how its Direct Unload went (never breaks the lane).
local function tellTrain(player: Player, ok: boolean)
	local source = trainCargo
	if source then
		local fine, err = pcall(function()
			source.sent(player, ok)
		end)
		if not fine then
			warn(`[PenService] Direct Unload of {player.Name}: {err}`)
		end
	end
end

--[[
	One step of a lane: at most one item leaves its list (the pen, or the
	unloading train) onto its chute's belt. Returns true when the lane's
	state changed without a pen change (the caller pushes the State once);
	a sent item pushes it itself.
]]
local function stepLane(player: Player, data: { [string]: any }, plotId: number, name: SendLane, lane: Lane, now: number): boolean
	if #lane.Intents == 0 then
		return false
	end
	-- Direct Unload ends as soon as the train doesn't unload that way any more
	local changed = false
	for i = #lane.Intents, 1, -1 do
		local intent = lane.Intents[i]
		if intent.Cargo and not listOf(player, data, intent) then
			table.remove(lane.Intents, i)
			changed = true
		end
	end
	if #lane.Intents == 0 then
		lane.Wait = nil
		return changed
	end
	if now < lane.NextAt then
		return changed
	end
	local ready: boolean, why: SourceWait? = ConveyorService.sourceReady(plotId, name, player.UserId)
	if not ready then
		lane.NextAt = now + SEND_RETRY
		if lane.Wait ~= why then
			lane.Wait = why
			return true
		end
		return changed
	end
	while #lane.Intents > 0 do
		local intent = lane.Intents[1]
		local list = listOf(player, data, intent)
		local index: number? = nil
		if list then
			if intent.Cargo then
				-- the train unloads front to back
				for i = 1, #list do
					if matches(intent, list[i], data) then
						index = i
						break
					end
				end
			else
				for i = #list, 1, -1 do
					if matches(intent, list[i], data) then
						index = i
						break
					end
				end
			end
		end
		if not list or not index then
			-- nothing left for this intent
			table.remove(lane.Intents, 1)
			changed = true
			continue
		end
		-- no yield from taking it out of its list until it rides the belt; if
		-- nothing spawned (or it errored), it goes straight back where it was
		local entry = table.remove(list, index) :: Desc
		-- (sourceReady said yes above, in this same step)
		local spawned, record, fail = pcall(ConveyorService.spawnAtSource, plotId, name, entry, player.UserId, true)
		if not spawned or not record then
			table.insert(list, index, entry)
			if spawned and fail ~= "Bad" then
				-- the chute filled up just now: try again soon
				lane.NextAt = now + SEND_RETRY
				return changed
			end
			-- it won't spawn: keep it, drop the intent, so nothing waits behind it
			if not spawned then
				warn(`[PenService] sending an item for {player.Name} failed: {record}`)
			end
			table.remove(lane.Intents, 1)
			changed = true
			if intent.Cargo then
				tellTrain(player, false)
			end
			continue
		end
		if not intent.Cargo then
			intent.Left -= 1
			if intent.Left <= 0 then
				table.remove(lane.Intents, 1)
			end
		end
		lane.NextAt = now + PenService.SendInterval
		lane.Wait = nil
		DataService.changed(player)
		if intent.Cargo then
			tellTrain(player, true)
		end
		return false
	end
	lane.Wait = nil
	return true
end

-- Every send queue, one step (the loop runs it every SEND_TICK; the tests call it).
function PenService.tickSend(now: number)
	for player, queue in queues do
		local data = DataService.get(player)
		local plotId = PlotService.plotOf(player)
		if not data or not plotId or not player.Parent then
			-- intents only: the queue simply stops, every item is still where it was
			queues[player] = nil
			continue
		end
		local changed = false
		for _, name: SendLane in LANES do
			local ok, result = pcall(stepLane, player, data, plotId, name, laneOf(queue, name), now)
			if not ok then
				warn(`[PenService] send lane {name} of {player.Name} failed: {result}`)
				table.clear(laneOf(queue, name).Intents)
				changed = true
			elseif result then
				changed = true
			end
		end
		if #queue.Pen.Intents == 0 and #queue.Train.Intents == 0 and queues[player] == queue then
			queues[player] = nil
			changed = true
		end
		if changed then
			DataService.changed(player)
		end
	end
end

-- Drops every send intent of the pen (nothing to put back: intents only).
-- The train's Direct Unload goes on (it is the train unloading, not a send).
function PenService.stopSend(player: Player): boolean
	local queue = queues[player]
	if not queue or #queue.Pen.Intents == 0 then
		return false
	end
	table.clear(queue.Pen.Intents)
	queue.Pen.Wait = nil
	if #queue.Train.Intents == 0 then
		queues[player] = nil
	end
	return true
end

--[[
	Direct Unload: TrainService registers where its unloading cargo is (see
	TrainCargo; nil removes it) and calls unloadTrain while its train pours
	dirty ore out of the TRAIN chute (once is enough: true when the Cargo
	intent was added now).
]]
function PenService.setTrainCargo(source: TrainCargo?)
	trainCargo = source
end

function PenService.unloadTrain(player: Player): boolean
	local lane = queueOf(player).Train
	for _, intent in lane.Intents do
		if intent.Cargo then
			return false
		end
	end
	table.insert(lane.Intents, { Left = 0, Cargo = true })
	return true
end

--[[
	A player brought items into the pen: `source` "Pen" (thrown in or Put
	In) or "Train" (a train delivery). With the sorting billboard switched
	on, the ones the player doesn't keep get a Pen-lane intent (marked
	Auto), while a belt feeds from the PEN chute (the header). The items
	stay in the pen until sent. Only these sources: sinks and machines
	store with PenService.store (header), anything else is ignored here.
]]
function PenService.arrived(player: Player, descs: { Desc }, source: ArrivalSource)
	if source ~= "Pen" and source ~= "Train" then
		return
	end
	local data = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if not data or not plotId or #descs == 0 then
		return
	end
	if automationOf(data) < EconomyConfig.PenAutomation.Billboard or not PenService.autoSortOn(data) then
		return
	end
	if ConveyorService.sourceBelt(plotId, "Pen") == nil then
		return
	end
	local lane: Lane? = nil
	local queued, full = 0, false
	for _, desc in descs do
		if ConveyorService.spawnable(desc) and not MachineData.keeps(data.KeepMode, data.KeepList, desc) then
			local l = lane or queueOf(player).Pen
			lane = l
			if addIntent(l, ItemData.storageKey(desc), nil, 1, true) then
				queued += 1
			else
				full = true
			end
		end
	end
	if full then
		local now = os.clock()
		if now - (lastQueueToast[player] or -math.huge) >= FULL_TOAST_COOLDOWN then
			lastQueueToast[player] = now
			toast(player, PenService.QueueFullText, "Info")
		end
	end
	if queued > 0 then
		if not autoTold[player] then
			-- once a session: ore leaving the pen by itself must not surprise anyone
			autoTold[player] = true
			toast(player, PenService.AutoFirstText, "Info")
		end
		DataService.changed(player)
		markBoard(player)
	end
end

-- PenAction "AutoSort" { On }: the sorting billboard on or off (from anywhere).
local function setAutoSort(player: Player, data: { [string]: any }, on: boolean)
	if automationOf(data) < EconomyConfig.PenAutomation.Billboard then
		toast(player, "Auto-sort needs Pen Automation from the Tech shop.", "Info")
		return
	end
	if PenService.autoSortOn(data) == on then
		return
	end
	data.AutoSort = on
	if not on then
		-- what the billboard queued stops too (the player's own SENDs go on)
		local queue = queues[player]
		if queue then
			for i = #queue.Pen.Intents, 1, -1 do
				if queue.Pen.Intents[i].Auto then
					table.remove(queue.Pen.Intents, i)
				end
			end
		end
	end
	toast(player, if on then PenService.AutoOnText else PenService.AutoOffText, "Info")
	DataService.changed(player)
	markBoard(player)
end

-- PenAction "Send" (the pen panel): a Pen-lane intent.
local function send(player: Player, plotId: number, data: { [string]: any }, arg: { [any]: any })
	local count: number? = nil
	if arg.Count ~= nil then
		count = Guard.integer(arg.Count, 1, GameConfig.MaxStoredItems)
		if not count then
			return
		end
	end
	local key: string? = nil
	local filter: SendFilter? = nil
	local all = false
	if arg.All ~= nil then
		-- { Key, All = true }: every item of that key (no Count, no Filter)
		if arg.All ~= true or arg.Key == nil or arg.Count ~= nil then
			return
		end
		all = true
	end
	if arg.Key ~= nil then
		local text = Guard.string(arg.Key, MAX_KEY_LENGTH)
		local desc = if text and arg.Filter == nil then ItemData.parseKey(text) else nil
		if not desc then
			return
		end
		key = ItemData.storageKey(desc)
	else
		local text = Guard.string(arg.Filter, 8)
		if not text or not PenService.SendFilters[text] then
			return
		end
		filter = text :: SendFilter
		if filter == "Unkept" and automationOf(data) < EconomyConfig.PenAutomation.Billboard then
			toast(player, "Sending unkept ore needs Pen Automation from the Tech shop.", "Info")
			return
		end
	end
	local available = countMatching(data, { Key = key, Filter = filter, Left = 0 })
	if available == 0 then
		toast(player, "There is nothing like that in your pen.", "Info")
		return
	end
	local n = math.min(count or (if key and not all then 1 else available), available)
	-- a Count is "that many more"; All (a key) and a filter without Count are
	-- "all of them": what is in the pen now, the ones already queued included
	local atLeast = if filter then count == nil else all
	if not addIntent(queueOf(player).Pen, key, filter, n, nil, atLeast, available) then
		toast(player, "Your send queue is full. Wait a moment or press STOP.")
		return
	end
	local _, why: SourceWait? = ConveyorService.sourceBelt(plotId, "Pen")
	if why then
		toast(player, `{ConveyorService.waitText("Pen", why)} {CHUTE_PLACE}: your ore waits in the pen until then.`, "Info")
	end
	DataService.changed(player)
	markBoard(player)
end

---------------------------------------------------------------- sorting billboard

-- What the board says the player keeps (pure: data.KeepMode, data.KeepList).
function PenService.keepSummary(mode: any, keepList: any): string
	local rareFrom = Rarity.get(MachineData.Keep.RareFrom).Order
	local function rarePlus(): string
		return `Keeps clean {Rarity.get(MachineData.Keep.RareFrom).Name}+ ore`
	end
	local m = if MachineData.isKeepMode(mode) then mode else MachineData.Keep.Default
	if m == "All" then
		return "Keeps every clean ore"
	elseif m ~= "List" or type(keepList) ~= "table" then
		return rarePlus()
	end
	local kept: { OreData.Ore } = {}
	local unsetRare = false
	local anySet = false
	for _, ore in OreData.List do
		local choice = keepList[ore.Id]
		if choice == true then
			table.insert(kept, ore)
			anySet = true
		elseif choice == false then
			anySet = true
		elseif Rarity.get(ore.Rarity).Order >= rareFrom then
			unsetRare = true
		end
	end
	if not anySet then
		return rarePlus()
	end
	table.sort(kept, function(a, b)
		local ra, rb = Rarity.get(a.Rarity).Order, Rarity.get(b.Rarity).Order
		if ra ~= rb then
			return ra > rb
		end
		return a.Name < b.Name
	end)
	local names = {}
	for i, ore in kept do
		if i > 6 then
			table.insert(names, `+{#kept - 6} more`)
			break
		end
		table.insert(names, ore.Name)
	end
	local text = if #names > 0 then "Keeps " .. table.concat(names, ", ") else "Keeps no clean ore you set"
	if unsetRare then
		text ..= " + Rare+ ore you haven't set"
	end
	return text
end

--[[
	The board's lines for a plot's owner: the title, what is kept and what
	the PEN chute does; nil when they have no billboard.
]]
function PenService.boardLines(player: Player): (string?, string?, string?)
	local data = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if not data or not plotId or automationOf(data) < EconomyConfig.PenAutomation.Billboard then
		return nil, nil, nil
	end
	local body = PenService.keepSummary(data.KeepMode, data.KeepList)
	if not PenService.autoSortOn(data) then
		return PenService.BoardTitleOff, body, "Off: new ore stays in your pen"
	end
	local _, why: SourceWait? = ConveyorService.sourceBelt(plotId, "Pen")
	local pen = PenService.sendCounts(player)
	local waiting = if pen > 0 then waitLine(player, "Pen") else nil
	local status = if why
		then ConveyorService.waitText("Pen", why) or ""
		elseif waiting then waiting
		elseif pen > 0 then `Sending {pen}…`
		else "The rest rides out of the PEN chute"
	return PenService.BoardTitle, body, status
end

local BOARD_WOOD = Color3.fromRGB(46, 40, 44)
local BOARD_EDGE = Color3.fromRGB(96, 200, 110)
local BOARD_OFF = Color3.fromRGB(150, 142, 136)
local BOARD_POST = Color3.fromRGB(86, 90, 106)
local BOARD_TEXT = Color3.fromRGB(255, 244, 228)
local BOARD_DIM = Color3.fromRGB(206, 196, 180)
local BOARD_DECOR = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
-- on the pen's front wall, left of the gate as seen from the grid (clear of
-- the ORE PEN sign over the gate), facing the grid (plot-local): 2.9 in from
-- the pen's right edge (x -1 at any grid size, so the board stays at x -3.9)
local penArea = BaseLayout.Pen.Area
PenService.BoardCenter = Vector3.new(penArea.Center.X + penArea.Size.X / 2 - 2.9, 4.0, penArea.Center.Z - penArea.Size.Z / 2 + 0.47)
PenService.BoardSize = Vector3.new(4.6, 2.6, 0.22)
local STRIP_DEPTH = 0.02

-- One text strip on the board: a thin part with one SurfaceGui and one
-- label (wrapped, scaled), so every line also shows in the preview renders.
local function boardStrip(model: Model, cf: CFrame, size: Vector3, name: string, color: Color3, font: Enum.Font, back: Color3): TextLabel
	local part = Geo.block(model, cf, size, back, nil, BOARD_DECOR)
	part.Name = name
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.3
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = ""
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.FontFace = Font.fromEnum(font)
	l.Parent = gui
	return l
end

local function buildBoard(plotId: number): Board?
	local yard = PenService.yard(plotId)
	local pen = yard and yard:FindFirstChild("Pen")
	if not pen then
		return nil
	end
	local plotCF = PlotService.plotCFrame(plotId)
	local model = Instance.new("Model")
	model.Name = "SortBoard"
	local c, size = PenService.BoardCenter, PenService.BoardSize
	-- front (-Z model space) toward the grid
	local center = plotCF * CFrame.new(c)
	local edge = Geo.block(model, center, size + Vector3.new(0.3, 0.3, -0.06), BOARD_EDGE, nil, BOARD_DECOR)
	edge.Name = "Edge"
	local titleSize = Vector3.new(size.X * 0.8, 0.8, 0.26)
	local titleCF = center * CFrame.new(0, size.Y / 2 + 0.5, 0)
	local titleBack = Geo.block(model, titleCF, titleSize, BOARD_EDGE, nil, BOARD_DECOR)
	titleBack.Name = "TitleBack"
	local title = boardStrip(
		model,
		titleCF * CFrame.new(0, 0, -titleSize.Z / 2 - STRIP_DEPTH / 2),
		Vector3.new(titleSize.X * 0.92, titleSize.Y * 0.84, STRIP_DEPTH),
		"Title",
		BOARD_WOOD,
		Enum.Font.LuckiestGuy,
		BOARD_EDGE
	)
	local board = Geo.block(model, center, size, BOARD_WOOD, nil, BOARD_DECOR)
	board.Name = "Board"
	local front = -size.Z / 2 - STRIP_DEPTH / 2
	local w = size.X * 0.9
	local body = boardStrip(
		model,
		center * CFrame.new(0, size.Y * 0.2, front),
		Vector3.new(w, size.Y * 0.5, STRIP_DEPTH),
		"Body",
		BOARD_TEXT,
		Enum.Font.FredokaOne,
		BOARD_WOOD
	)
	local status = boardStrip(
		model,
		center * CFrame.new(0, -size.Y * 0.27, front),
		Vector3.new(w, size.Y * 0.34, STRIP_DEPTH),
		"Status",
		BOARD_DIM,
		Enum.Font.FredokaOne,
		BOARD_WOOD
	)
	-- two posts down to the pen wall's cap
	local wallTop = 1.9
	local bottom = c.Y - size.Y / 2
	for _, side in { -1, 1 } do
		local post = Geo.block(
			model,
			plotCF * CFrame.new(c.X + side * (size.X / 2 - 0.5), (wallTop + bottom) / 2, c.Z),
			Vector3.new(0.24, bottom - wallTop + 0.1, 0.24),
			BOARD_POST,
			nil,
			BOARD_DECOR
		)
		post.Name = "Post"
	end
	model.Parent = pen
	return { Model = model, Title = title, Body = body, Status = status }
end

-- Shows, updates or removes a plot's board (only for owners with the billboard).
local function updateBoard(plotId: number)
	local owner = PlotService.ownerOf(plotId)
	local title: string?, body: string?, status: string? = nil, nil, nil
	if owner then
		title, body, status = PenService.boardLines(owner)
	end
	local board: Board? = boards[plotId]
	if not title then
		if board then
			board.Model:Destroy()
			boards[plotId] = nil
		end
		return
	end
	if not board then
		board = buildBoard(plotId)
	end
	if not board then
		return
	end
	boards[plotId] = board
	if board.Title.Text ~= title then
		board.Title.Text = title
		-- off: the green frame goes grey
		local color = if title == PenService.BoardTitle then BOARD_EDGE else BOARD_OFF
		for _, name in { "Edge", "TitleBack", "Title" } do
			local part = board.Model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.Color = color
			end
		end
	end
	local text = body or ""
	if board.Body.Text ~= text then
		board.Body.Text = text
	end
	local line = status or ""
	if board.Status.Text ~= line then
		board.Status.Text = line
	end
end

local function flushBoards()
	for plotId in boardDirty do
		boardDirty[plotId] = nil
		local ok, err = pcall(function()
			updateBoard(plotId)
		end)
		if not ok then
			warn(`[PenService] sorting board of plot {plotId}: {err}`)
		end
	end
end

---------------------------------------------------------------- PenAction

local function onAction(player: Player, actionArg: any, argArg: any)
	local action = Guard.string(actionArg, 16)
	if not action then
		return
	end
	if action == "StopSend" then
		-- from anywhere: it is harmless
		if PenService.stopSend(player) then
			toast(player, "Sending stopped. The rest stays in your pen.", "Info")
			DataService.changed(player)
			markBoard(player)
		end
		return
	end
	local arg = Guard.table(argArg, 4)
	if not arg then
		return
	end
	local plotId = PlotService.plotOf(player)
	local data = DataService.get(player)
	if not plotId or not data then
		return
	end
	if action == "AutoSort" then
		-- a setting: from anywhere
		if type(arg.On) == "boolean" then
			setAutoSort(player, data, arg.On)
		end
		return
	end
	if action == "Send" then
		if PenService.isNear(player, plotId) then
			send(player, plotId, data, arg)
		else
			toast(player, "Walk back to your Ore Pen first.")
		end
		return
	end
	local keyText = Guard.string(arg.Key, MAX_KEY_LENGTH)
	local desc = if keyText then ItemData.parseKey(keyText) else nil
	if not desc or (action ~= "Take" and action ~= "ToPodium") then
		return
	end
	local key = ItemData.storageKey(desc)
	if not PenService.isNear(player, plotId) then
		toast(player, "Walk back to your Ore Pen first.")
		return
	end
	if action == "Take" then
		local count = Guard.integer(arg.Count, 1, GameConfig.StorageTakeMax)
		if count then
			takeItems(player, plotId, data, key, count)
		end
	else
		local slot = Guard.integer(arg.Slot, 1, EconomyConfig.Podiums.Max)
		local placer = podiumPlacer
		if slot and placer then
			placer(player, slot, key)
		end
	end
end

---------------------------------------------------------------- lifecycle

-- The State snapshot's pen fields (StateService provider).
local function provide(player: Player, data: { [string]: any }, snapshot: { [string]: any })
	snapshot.PenCapacity = PenService.capacityOf(data)
	snapshot.PenOver = PenService.isOver(data)
	snapshot.AutoSort = PenService.autoSortOn(data)
	local pen, train = PenService.sendCounts(player)
	snapshot.PenSend = {
		Pen = pen,
		Train = train,
		PenWait = waitLine(player, "Pen"),
		TrainWait = waitLine(player, "Train"),
	}
end

-- Internals for the Lune tests only (tests/PenService.spec.luau).
PenService._test = {
	action = onAction,
	intake = onIntake,
	putIn = putIn,
	open = openPen,
	setupPen = setupPen,
	updateBoard = updateBoard,
	board = function(plotId: number): Board?
		return boards[plotId]
	end,
	queue = function(player: Player): Queue?
		return queues[player]
	end,
	waitLine = waitLine,
	provide = provide,
	reset = function()
		table.clear(lastFullToast)
		table.clear(lastOverToast)
		table.clear(lastForeignToast)
		table.clear(lastQueueToast)
		table.clear(autoTold)
		table.clear(queues)
		trainCargo = nil
		for _, board in boards do
			board.Model:Destroy()
		end
		table.clear(boards)
		table.clear(boardDirty)
		podiumPlacer = nil
	end,
}

function PenService.init()
	Net.on("PenAction", onAction)
	StateService.addProvider(provide)
	for _, plot in WorldLayout.Plots do
		setupPen(plot.Id)
	end
	-- the board follows the owner's data and the belt on the PEN chute
	DataService.onChanged(markBoard)
	MachineService.onLayoutChanged(function(_, plotId)
		boardDirty[plotId] = true
	end)
	PlotService.onReleased(function(player, plotId)
		queues[player] = nil
		boardDirty[plotId] = true
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastFullToast[player] = nil
		lastOverToast[player] = nil
		lastForeignToast[player] = nil
		lastQueueToast[player] = nil
		autoTold[player] = nil
		-- intents only: nothing to put back (the train's cargo is saved on the train)
		queues[player] = nil
	end)
end

function PenService.start()
	while true do
		task.wait(SEND_TICK)
		PenService.tickSend(os.clock())
		flushBoards()
	end
end

return PenService
