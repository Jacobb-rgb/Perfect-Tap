--[[
	PenService: the Ore Pen in every base yard (design v2). Each player has
	one pen, saved as data.Storage (a list of item descriptors { K, O, G?, R? }).

	- Capacity: EconomyConfig.penCapacity(Upgrades.PenLevel, GameConfig.MaxStoredItems)
	  (pen upgrades are bought in the shops, step 6). Players can only fill
	  the pen up to it; system writes (leaving, the loose-item cap, packing a
	  machine up) go through ItemService.storeDesc, which pays Tobin's price
	  for anything that doesn't fit.
	- In: drop or throw your own items into the pen (the yard's Pen.Intake
	  box, an IntakeService zone), or press "Put In" (F / gamepad Y) at the
	  pen gate while carrying items. Items of other players are not taken:
	  they bounce back out of the gate. A full pen bounces items too (toast).
	- Out: "Open Pen" (G / gamepad B) opens PenView (OpenUI "Pen"). PenAction:
	    "Take"     { Key, Count 1..StorageTakeMax }: the items appear at the
	               gate and go into your hands while they have room
	    "ToPodium" { Key, Slot }: puts one cleaned ore on a podium (PodiumService)
	    "Send"     { Key, Count? } | { Filter, Count? }: a send intent (below)
	    "StopSend" (no arg): drops every send intent
	  Checks: types (Guard), ItemData.parseKey, your own plot, standing within
	  Range (+ slack) of your pen gate (StopSend: anywhere).
	- Send (step 3, WP-Belts, docs/plans/STEP3_PLAN.md): every player has a
	  send queue with two lanes, one per Source chute (BaseLayout.Chutes):
	    Pen    "Send" from the pen panel, and the sorting billboard
	    Train  the train's Direct Unload
	  A lane holds INTENTS only ({ Key, Left } or { Filter, Left }), never
	  items: every item stays in data.Storage until the step that spawns it,
	  which takes it out of the pen and puts it onto the chute's belt
	  (ConveyorService.spawnAtSource) with no yield in between. One item per
	  lane every SendInterval seconds, while the belt on the chute cell feeds
	  (ConveyorService.sourceReady: a belt there, not facing the yard, with
	  room, the owner below the loose-item cap); otherwise the lane waits and
	  the State says why. An intent ends when nothing in the pen matches it
	  any more. Leaving, losing the plot or StopSend just drops the intents:
	  there is nothing to put back. Filters: "Dirty" (dirty ore), "Unkept"
	  (everything MachineData.keeps doesn't keep; needs PenAutomation >= 1)
	  and "All"; a Filter intent covers what matched when it was asked for.
	- Sorting billboard (Upgrades.PenAutomation >= EconomyConfig.PenAutomation.Billboard):
	  items arriving in the pen (thrown in, Put In, train delivery: arrived())
	  that MachineData.keeps doesn't keep (data.KeepMode / KeepList: dirty ore,
	  crushed ore, ingots and the clean ore the player doesn't keep) get a
	  Pen-lane intent at once, while a belt feeds from the PEN chute (no belt:
	  they simply stay in the pen). A board on the pen's front wall shows
	  "AUTO-SORT ON", what is kept and the lane's state (no editing here: the
	  Iron Box view edits KeepMode / KeepList).
	- Direct Unload (PenAutomation >= EconomyConfig.PenAutomation.DirectUnload):
	  the train unloads into the pen as before (TrainService, same capacity
	  rule and animation), and its dirty ore gets Train-lane intents at once,
	  so it pours out of the TRAIN chute one by one while a belt feeds from
	  there (no belt: it stays in the pen, as without the upgrade).
	- StateService gets PenCapacity and PenSend = { Pen, Train (items still
	  to send per lane), Wait? (why a lane waits, a line for the player) }.
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
-- one send intent: that many of one storage key, or of a filter
type Intent = { Key: string?, Filter: SendFilter?, Left: number }
type Lane = { Intents: { Intent }, NextAt: number, Wait: SourceWait? }
type Queue = { Pen: Lane, Train: Lane }
type Board = { Model: Model, Body: TextLabel, Status: TextLabel }

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

-- send queue (WP-Belts)
PenService.SendInterval = 0.5 -- seconds between two items leaving one chute
PenService.MaxIntents = 24 -- send intents per lane (equal ones are merged)
PenService.SendFilters = { Dirty = true, Unkept = true, All = true } :: { [string]: boolean }
PenService.BoardTitle = "AUTO-SORT ON"
local SEND_TICK = 0.1
local SEND_RETRY = 0.25 -- a waiting lane looks again this often
local LANES: { SendLane } = { "Pen", "Train" }
local CHUTE_PLACE = "(the blue plate on the back row of your build grid)"

local lastFullToast: { [Player]: number } = {}
local lastForeignToast: { [Player]: number } = {}
local podiumPlacer: PodiumPlacer? = nil
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

-- Room for `n` (default 1) more items?
function PenService.hasRoom(player: Player, n: number?): boolean
	local data = DataService.get(player)
	return data ~= nil and #data.Storage + (n or 1) <= PenService.capacityOf(data)
end

-- Puts one item into the pen when it has room (no sale fallback). The
-- caller calls DataService.changed (several changes, one push).
function PenService.store(player: Player, desc: Desc): boolean
	local data = DataService.get(player)
	if not data or #data.Storage >= PenService.capacityOf(data) then
		return false
	end
	table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
	return true
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
	if #data.Storage >= PenService.capacityOf(data) then
		bounceOut(plotId, record)
		fullToast(owner, data)
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

-- "Put In": everything you carry goes in while the pen has room.
local function putIn(player: Player, plotId: number)
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your Ore Pen.")
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	if #CarryService.list(player) == 0 then
		toast(player, "Carry ore here to put it in your pen.", "Info")
		return
	end
	local stored: { Desc } = {}
	for _ = 1, MAX_PUT_IN do
		if #data.Storage >= PenService.capacityOf(data) then
			break
		end
		local record = CarryService.takeTop(player)
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
	if #CarryService.list(player) > 0 then
		toast(player, fullText(data))
	end
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
	key: Enum.KeyCode,
	pad: Enum.KeyCode,
	order: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = "Ore Pen"
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
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
	local put = makePrompt(anchor, plotId, "PenPutIn", "Put In", Enum.KeyCode.F, Enum.KeyCode.ButtonY, 0)
	put.Triggered:Connect(function(player: Player)
		putIn(player, plotId)
	end)
	local open = makePrompt(anchor, plotId, "PenOpen", "Open Pen", Enum.KeyCode.G, Enum.KeyCode.ButtonB, 1)
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
	local looseRoom = math.max(0, GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom - ItemService.looseCount(player.UserId))
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

-- Does this pen entry belong to the intent?
local function matches(intent: Intent, entry: any, data: { [string]: any }): boolean
	if type(entry) ~= "table" or type(entry.K) ~= "string" or type(entry.O) ~= "string" then
		return false
	end
	local key = intent.Key
	if key then
		return ItemData.storageKey(entry) == key
	end
	local filter = intent.Filter
	if filter == "Dirty" then
		return entry.K == "Raw"
	elseif filter == "Unkept" then
		return not MachineData.keeps(data.KeepMode, data.KeepList, entry)
	end
	return filter == "All"
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
	Adds a send intent to a lane, merged with an equal one (the same Key adds
	up, the same Filter keeps the bigger count). Returns false when the lane
	already holds MaxIntents other intents. The caller pushes the State.
]]
local function addIntent(lane: Lane, key: string?, filter: SendFilter?, count: number): boolean
	for _, intent in lane.Intents do
		if key and intent.Key == key then
			intent.Left = math.min(intent.Left + count, GameConfig.MaxStoredItems)
			return true
		elseif filter and intent.Filter == filter then
			intent.Left = math.max(intent.Left, count)
			return true
		end
	end
	if #lane.Intents >= PenService.MaxIntents then
		return false
	end
	table.insert(lane.Intents, { Key = key, Filter = filter, Left = math.min(count, GameConfig.MaxStoredItems) })
	return true
end

--[[
	How many items each lane will still send: the intents in order, each
	taking from what is in the pen right now (an item counts once, even when
	two intents could send it).
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
		if type(entry) == "table" and type(entry.K) == "string" and type(entry.O) == "string" then
			local key = ItemData.storageKey(entry)
			available[key] = (available[key] or 0) + 1
			sample[key] = entry
		end
	end
	local function lane(l: Lane): number
		local total = 0
		for _, intent in l.Intents do
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

-- Why a lane waits, as a line for the player (nil: it doesn't wait).
local function waitLine(player: Player): string?
	local queue = queues[player]
	if not queue then
		return nil
	end
	for _, name: SendLane in LANES do
		local lane = laneOf(queue, name)
		if #lane.Intents > 0 and lane.Wait then
			return ConveyorService.waitText(name, lane.Wait)
		end
	end
	return nil
end

local function markBoard(player: Player)
	local plotId = PlotService.plotOf(player)
	if plotId then
		boardDirty[plotId] = true
	end
end

--[[
	One step of a lane: at most one item leaves the pen onto its chute's
	belt. Returns true when the lane's state changed without a pen change
	(the caller pushes the State once); a sent item pushes it itself.
]]
local function stepLane(player: Player, data: { [string]: any }, plotId: number, name: SendLane, lane: Lane, now: number): boolean
	if #lane.Intents == 0 or now < lane.NextAt then
		return false
	end
	local ready: boolean, why: SourceWait? = ConveyorService.sourceReady(plotId, name, player.UserId)
	if not ready then
		lane.NextAt = now + SEND_RETRY
		if lane.Wait ~= why then
			lane.Wait = why
			return true
		end
		return false
	end
	local storage = data.Storage
	while #lane.Intents > 0 do
		local intent = lane.Intents[1]
		local index: number? = nil
		for i = #storage, 1, -1 do
			if matches(intent, storage[i], data) then
				index = i
				break
			end
		end
		if not index then
			-- nothing left for this intent
			table.remove(lane.Intents, 1)
			continue
		end
		-- no yield from taking it out of the pen until it rides the belt; if
		-- spawning fails (or errors), it goes straight back where it was
		local entry = table.remove(storage, index) :: Desc
		local spawned, record = pcall(function(): ItemRecord?
			return (ConveyorService.spawnAtSource(plotId, name, entry, player.UserId))
		end)
		if not spawned or not record then
			table.insert(storage, index, entry)
			lane.NextAt = now + SEND_RETRY
			if not spawned then
				warn(`[PenService] sending an item for {player.Name} failed: {record}`)
			end
			return false
		end
		intent.Left -= 1
		if intent.Left <= 0 then
			table.remove(lane.Intents, 1)
		end
		lane.NextAt = now + PenService.SendInterval
		lane.Wait = nil
		DataService.changed(player)
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
			-- intents only: the queue simply stops, every item is still in the pen
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
		if #queue.Pen.Intents == 0 and #queue.Train.Intents == 0 then
			queues[player] = nil
			changed = true
		end
		if changed then
			DataService.changed(player)
		end
	end
end

-- Drops every send intent of a player (nothing to put back: intents only).
function PenService.stopSend(player: Player): boolean
	local queue = queues[player]
	if not queue then
		return false
	end
	queues[player] = nil
	return #queue.Pen.Intents > 0 or #queue.Train.Intents > 0
end

--[[
	Items just went into the pen (`source`: "Pen" = thrown in or Put In,
	"Train" = a train delivery). With the sorting billboard the ones the
	player doesn't keep get a Pen-lane intent, with Direct Unload the train's
	dirty ore a Train-lane intent, each only while a belt feeds from that
	chute (the header). The items themselves stay in the pen until sent.
]]
function PenService.arrived(player: Player, descs: { Desc }, source: "Pen" | "Train")
	local data = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if not data or not plotId or #descs == 0 then
		return
	end
	local level = automationOf(data)
	if level < EconomyConfig.PenAutomation.Billboard then
		return
	end
	local direct = source == "Train"
		and level >= EconomyConfig.PenAutomation.DirectUnload
		and ConveyorService.sourceBelt(plotId, "Train") ~= nil
	local sorting = ConveyorService.sourceBelt(plotId, "Pen") ~= nil
	local queued = 0
	for _, desc in descs do
		if type(desc) == "table" and type(desc.K) == "string" and type(desc.O) == "string" then
			local key = ItemData.storageKey(desc)
			if direct and desc.K == "Raw" then
				if addIntent(queueOf(player).Train, key, nil, 1) then
					queued += 1
				end
			elseif sorting and not MachineData.keeps(data.KeepMode, data.KeepList, desc) then
				if addIntent(queueOf(player).Pen, key, nil, 1) then
					queued += 1
				end
			end
		end
	end
	if queued > 0 then
		DataService.changed(player)
	end
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
	local n = math.min(count or (if key then 1 else available), available)
	if not addIntent(queueOf(player).Pen, key, filter, n) then
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

-- The board's lines for a plot's owner, or nil when they have no billboard.
function PenService.boardLines(player: Player): (string?, string?)
	local data = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if not data or not plotId or automationOf(data) < EconomyConfig.PenAutomation.Billboard then
		return nil, nil
	end
	local body = PenService.keepSummary(data.KeepMode, data.KeepList)
	local _, why: SourceWait? = ConveyorService.sourceBelt(plotId, "Pen")
	local pen = PenService.sendCounts(player)
	local status = if why
		then ConveyorService.waitText("Pen", why) or ""
		elseif pen > 0 then `Sending {pen}…`
		else "Everything else rides out of the PEN chute"
	return body, status
end

local BOARD_WOOD = Color3.fromRGB(46, 40, 44)
local BOARD_EDGE = Color3.fromRGB(96, 200, 110)
local BOARD_POST = Color3.fromRGB(86, 90, 106)
local BOARD_TEXT = Color3.fromRGB(255, 244, 228)
local BOARD_DIM = Color3.fromRGB(206, 196, 180)
local BOARD_DECOR = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
-- on the pen's front wall, right of the gate, facing the grid (plot-local)
PenService.BoardCenter = Vector3.new(-4.6, 4.2, BaseLayout.Pen.Area.Center.Z - BaseLayout.Pen.Area.Size.Z / 2 + 0.47)
PenService.BoardSize = Vector3.new(5.6, 2.9, 0.22)

local function boardLabel(gui: SurfaceGui, name: string, y: number, h: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(0.05, y)
	l.Size = UDim2.fromScale(0.9, h)
	l.Text = ""
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.FontFace = Font.fromEnum(font)
	l.Parent = gui
	return l
end

local function boardGui(part: Part): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.3
	gui.Parent = part
	return gui
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
	local title = Geo.block(model, center * CFrame.new(0, size.Y / 2 + 0.5, 0), Vector3.new(size.X * 0.72, 0.8, 0.26), BOARD_EDGE, nil, BOARD_DECOR)
	title.Name = "Title"
	local titleText = boardLabel(boardGui(title), "Text", 0.08, 0.84, BOARD_WOOD, Enum.Font.LuckiestGuy)
	titleText.Text = PenService.BoardTitle
	local board = Geo.block(model, center, size, BOARD_WOOD, nil, BOARD_DECOR)
	board.Name = "Board"
	local gui = boardGui(board)
	local body = boardLabel(gui, "Body", 0.07, 0.56, BOARD_TEXT, Enum.Font.FredokaOne)
	local status = boardLabel(gui, "Status", 0.68, 0.25, BOARD_DIM, Enum.Font.FredokaOne)
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
	return { Model = model, Body = body, Status = status }
end

-- Shows, updates or removes a plot's board (only for owners with the billboard).
local function updateBoard(plotId: number)
	local owner = PlotService.ownerOf(plotId)
	local body, status = nil, nil
	if owner then
		body, status = PenService.boardLines(owner)
	end
	local board: Board? = boards[plotId]
	if not body then
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
	if board.Body.Text ~= body then
		board.Body.Text = body
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
	reset = function()
		table.clear(lastFullToast)
		table.clear(lastForeignToast)
		table.clear(queues)
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
	StateService.addProvider(function(player, data, snapshot)
		snapshot.PenCapacity = PenService.capacityOf(data)
		local pen, train = PenService.sendCounts(player)
		snapshot.PenSend = { Pen = pen, Train = train, Wait = waitLine(player) }
	end)
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
		lastForeignToast[player] = nil
		-- intents only: nothing to put back
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
