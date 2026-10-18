--[[
	ProcessingService: the machines that work on their own. Clay, Brick,
	Blast and Plasma Furnace smelt clean or crushed ore into ingots, the
	Crusher turns 1 clean ore into 2 crushed piles, the Cleaning Plant (Id
	AutoCleaner) cleans raw ore with the grade odds of its Quality level
	(MachineData.QualityLevels / gradeOdds: 60% Rough / 40% Clean at level
	0, up to 30% Flawless at level 5; MachineLogic.outputs takes the odds).
	The roster processors (docs/plans/MACHINES_GAME_PLAN.md, MachineData):
	  Plasma Furnace     Batch = 2: one job works up to 2 queued items at
	                     once, one ingot each (MachineLogic.batch: never more
	                     results than fit in Out)
	  Polisher           Clean -> Clean, GradeUpChance: one grade better
	                     (MachineLogic.gradeUp; Flawless stays)
	  Crystal Extractor  Crushed -> Crushed (the same item), ShardChance: the
	                     owner's data.Shards + 1 and a "+1 Crystal Shard!" toast.
	                     Each crushed pile is shaken for a shard ONCE: every
	                     pile another machine (the Crusher) makes adds one to
	                     the owner's data.ShardRolls, every extractor job spends
	                     one, and a job with none left passes the pile on
	                     without a roll. So feeding the extractor its own
	                     output (a belt loop, Put In again) finds nothing: at
	                     most one roll per pile ever crushed.
	  Alloy Furnace      Behaviour "Alloy": a job starts once the queue holds
	                     ingots of two DIFFERENT ores and takes In[1] and the
	                     first ingot of another ore (MachineLogic.alloyPair);
	                     it gives ONE alloy of the more valuable ore with the
	                     lower grade (MachineLogic.alloyDesc). While only one
	                     ore waits, the Status attribute says "NeedsOtherOre"
	                     (only when no other status is shown; cleared when a
	                     job starts). The last queue place is kept for another
	                     ore (MachineLogic.accepts).

	- Items arrive through MachineService (hopper, belt, Put In prompt or a
	  machine in front): canAccept = MachineLogic.accepts, insert = push onto
	  the saved queue (Entry.In, at most 4; In[1] is being worked).
	- The 10 Hz MachineService tick runs one job at a time per machine. A
	  finished job moves its inputs out of In and its results into Entry.Out
	  (at most MachineData.MaxOutBuffer); MachineService then sends Out
	  through the machine's front. If Out has no room, the job waits
	  ('OutputBlocked'). Cycles counts finished jobs (a batch is one job).
	- Job time = MachineData.processTime with the owner's Bellows level and
	  the machine type's Speed level (Tech shop, data.MachineUpgrades, read
	  through EconomyConfig.upgradeLevel), divided by
	  MachineService.speedFactor (power: 1 when nothing slows the machine),
	  all read when each job starts, never below GameConfig.MinProcessTime.
	- Grade odds (Cleaning Plant) = MachineData.gradeOdds of the machine
	  type's Quality level, read when each job starts. The plant shows them:
	  attributes Quality (level) and QualityOdds ("30% Rough · 50% Clean ·
	  20% Pristine", the client's billboard note), and the level on its Put
	  In prompt's ObjectText ("Cleaning Plant · Quality 2": short, so the
	  prompt stays narrow on phones); refreshed every QUALITY_CHECK seconds,
	  so a level bought in the Tech shop shows at once.
	- Random rolls (grades, grade-ups, shards) happen once, when a job
	  finishes; a job waiting for room in Out keeps its roll.
	- Queue and Out live in the save (Entry.In / Entry.Out), so leaving,
	  autosaves and shutdowns keep them. Job progress is not saved: after a
	  rejoin the job on In[1] starts over. A Speed buy in the Tech shop
	  (ShopService.onBought) rebuilds the player's machines of that type with
	  the new upgrade look (MachineService.refreshType: a "Refresh" removal,
	  like "Unload": the queues stay, a job in progress starts over).
	- Clients animate everything from model attributes (MachineFxController):
	  Queue, QueueMax, OutCount, Working, WorkStart, WorkTime, WorkOre, Cycles.
	  WorkOre is "" while dirty ore is worked: nobody can see through the
	  dirt (the Cleaning Plant reveals it when the clean ore comes out).
	- A sorter (a machine with a Time but no Output, the Iron Box) runs on
	  these jobs too, with the behaviour ProcessingService.sorterBehaviour
	  builds: its item comes back out unchanged, unless the sorter's `take`
	  puts it somewhere else (the Ore Pen) in the same step; never both. A
	  sorter job counts toward nothing (no IngotsSmelted, first-ingot toast,
	  Discovery or onProcessed; MachineLogic).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local MachineData = require(Shared.Config.MachineData)
local MachineLogic = require(Shared.Machines.MachineLogic)
local Rng = require(Shared.Util.Rng)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local Discovery = require(script.Parent.Parent.Discovery)
local MachineService = require(script.Parent.MachineService)
local IntakeService = require(script.Parent.IntakeService)
local ShopService = require(script.Parent.ShopService)

local ProcessingService = {}

type PlacedMachine = MachineService.PlacedMachine
type Desc = MachineLogic.Desc
type Via = MachineService.Via
type Bought = ShopService.Bought

--[[
	What a sorter does with an item whose sort job finished.
	  take    put `desc` somewhere else right now (the Ore Pen) and return
	          true, with no yield; false = it leaves the front like any
	          output. Called again every tick while the front is blocked.
	          Whatever it changes must be its last step: an error before
	          that leaves the item in the machine (it passes on instead).
	  sorted  after the item went its way (kept = `take` took it): model
	          attributes, counters
	  spawned extra set-up when a machine of this type appears (prompts)
]]
export type Sorter = {
	take: (machine: PlacedMachine, desc: Desc) -> boolean,
	sorted: ((machine: PlacedMachine, desc: Desc, kept: boolean) -> ...any)?,
	spawned: ((machine: PlacedMachine) -> ...any)?,
}

-- What one worked item gave (an alloy job: its first ingot gives the alloy).
type Result = {
	Input: Desc,
	Outputs: { Desc },
	Shard: boolean, -- Crystal Extractor: this item also gave a crystal shard
}

-- Runtime job state, kept in machine.State.Job (never saved).
type Job = {
	Input: Desc, -- the In[1] table being worked
	Inputs: { Desc }, -- every queued table the job works, In[1] first (Batch: a few; Alloy: the pair)
	EndsAt: number, -- os.clock() time the job finishes
	Odds: { [string]: number }?, -- grade odds of the Quality level when it started (Cleaning Plant)
	Results: { Result }?, -- rolled once when it finishes (a blocked job keeps its roll)
	Outputs: { Desc }?, -- every result's outputs, in order
	PassThrough: boolean, -- the input doesn't belong here and comes back out as is
	Blocked: boolean, -- finished but Out had no room
}

local MACHINES = {
	"ClayFurnace",
	"BlastFurnace",
	"Crusher",
	"AutoCleaner",
	"BrickFurnace",
	"Polisher",
	"CrystalExtractor",
	"PlasmaFurnace",
	"AlloyFurnace",
}
local FIRST_INGOT = "Your first ingot! Ingots go into the Foundry (soon) to forge stronger blasters, or sell them to Tobin."
local SHARD_TOAST = "+1 Crystal Shard!"
-- data.ShardRolls never holds more than this (a sanity cap far above any pen)
ProcessingService.MaxShardRolls = 100000
local ALLOY = "Alloy" -- MachineData Behaviour of the Alloy Furnace
local NEEDS_OTHER_ORE = "NeedsOtherOre" -- Status while an Alloy Furnace waits for a second ore
-- speedFactor outside this range is a broken modifier (power never goes there)
local MIN_SPEED, MAX_SPEED = 0.05, 20
-- seconds between checks of the Cleaning Plant's Quality level (shown odds)
local QUALITY_CHECK = 1
local WARN_COOLDOWN = 10

local processedCallbacks: { (Player, string, Desc, { Desc }) -> ...any } = {}
-- output grade rolls (Auto Cleaner, Polisher) and shard rolls; the seed only needs to differ per server
local rng = Rng.new((os.time() * 1000 + math.floor(os.clock() * 1000)) % 2147483647)
local lastWarn: { [string]: number } = {}

local function warnThrottled(key: string, message: string)
	local now = os.clock()
	if now - (lastWarn[key] or -math.huge) >= WARN_COOLDOWN then
		lastWarn[key] = now
		warn(message)
	end
end

-- Listeners (tutorial, quests, analytics): (player, machineId, input, outputs).
-- They get copies, so changing them can't touch the machine's queues. A
-- batch job calls them once per item; an alloy job once, with its first ingot.
function ProcessingService.onProcessed(callback: (Player, string, Desc, { Desc }) -> ...any)
	table.insert(processedCallbacks, callback)
end

local function copyDesc(desc: Desc): Desc
	return { K = desc.K, O = desc.O, G = desc.G, R = desc.R }
end

local function count(list: { Desc }?): number
	return if list then #list else 0
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function isAlloy(machine: PlacedMachine): boolean
	return machine.Info.Behaviour == ALLOY
end

---------------------------------------------------------------- upgrades

-- The owner's level of an upgrade of this machine type (0 without a save).
local function upgradeLevel(machine: PlacedMachine, kind: string): number
	local data = DataService.get(machine.Owner)
	return if data then EconomyConfig.upgradeLevel(data, machine.Id, kind) else 0
end

-- How fast power (MachineService.speedFactor) lets the machine work now;
-- a broken value counts as 1.
local function speedOf(machine: PlacedMachine): number
	local factor = MachineService.speedFactor(machine)
	if type(factor) ~= "number" or factor ~= factor or factor <= 0 or factor == math.huge then
		return 1
	end
	return math.clamp(factor, MIN_SPEED, MAX_SPEED)
end

-- Seconds one job takes for this machine's owner right now (Bellows +
-- Speed, then divided by the power speed factor).
local function jobTime(machine: PlacedMachine): number
	local data = DataService.get(machine.Owner)
	local upgrades = data and data.Upgrades
	local level = if type(upgrades) == "table" then tonumber(upgrades.Bellows) else nil
	if level == nil or level ~= level then
		level = 0
	end
	local seconds = MachineData.processTime(machine.Info, level :: number, upgradeLevel(machine, "Speed"))
	if seconds ~= seconds or seconds == math.huge then
		seconds = machine.Info.Time or GameConfig.MinProcessTime
	end
	return math.max(GameConfig.MinProcessTime, seconds / speedOf(machine))
end

-- Grade odds for the next job (machines with QualityLevels), else nil.
local function jobOdds(machine: PlacedMachine): { [string]: number }?
	if not machine.Info.QualityLevels then
		return nil
	end
	return MachineData.gradeOdds(upgradeLevel(machine, "Quality"))
end

--[[
	Grade odds as text, lowest grade first, whole percents, grades at 0%
	left out: "30% Rough · 50% Clean · 20% Pristine". Pure (tested).
]]
function ProcessingService.oddsText(odds: { [string]: number }): string
	local parts = {}
	for _, grade in ItemData.Grades do
		local chance = odds[grade.Id]
		if type(chance) == "number" and chance == chance and chance > 0 then
			table.insert(parts, `{math.floor(chance * 100 + 0.5)}% {grade.Name}`)
		end
	end
	return table.concat(parts, " · ")
end

-- The Cleaning Plant's shown Quality level and odds (attributes + prompt).
local function showQuality(machine: PlacedMachine)
	if not machine.Info.QualityLevels or machine.Removed then
		return
	end
	local level = upgradeLevel(machine, "Quality")
	if machine.Model:GetAttribute("Quality") == level and machine.State.QualityShown then
		return
	end
	machine.State.QualityShown = true
	local text = ProcessingService.oddsText(MachineData.gradeOdds(level))
	MachineService.setAttrs(machine, { Quality = level, QualityOdds = text })
	local base = machine.Model.PrimaryPart
	local anchor = base and (base:FindFirstChild("Prompt") or base)
	local prompt = anchor and anchor:FindFirstChild("LoadPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ObjectText = `{machine.Info.Name} · Quality {level}`
	end
end

--[[
	After a Tech shop buy (ShopService.onBought): a Speed level changes the
	machine type's upgrade look (MachineData.lookLevel), so the player's
	placed machines of that type are rebuilt (MachineService.refreshType;
	queues stay, a job in progress starts over). A level that keeps the look
	(level 5 looks like level 4) rebuilds nothing.
]]
local function onBought(player: Player, bought: Bought)
	if bought.Kind ~= "Upgrade" or bought.Upgrade ~= "Speed" then
		return
	end
	local machineId = bought.Machine
	if type(machineId) ~= "string" or not MachineData.ById[machineId] then
		return
	end
	local level = bought.Level
	if type(level) == "number" and MachineData.lookLevel(level) == MachineData.lookLevel(level - 1) then
		return
	end
	MachineService.refreshType(player, machineId)
end

---------------------------------------------------------------- jobs

local function syncCounts(machine: PlacedMachine)
	MachineService.setAttrs(machine, {
		Queue = count(machine.Entry.In),
		OutCount = count(machine.Entry.Out),
	})
end

-- Alloy Furnace: shows "NeedsOtherOre" while it waits for a second ore. A
-- status MachineService set (OutputBlocked, TooManyItems) is never replaced.
local function showWaiting(machine: PlacedMachine, waiting: boolean)
	local status = machine.Model:GetAttribute("Status")
	if waiting then
		if status == nil or status == "" then
			MachineService.setAttrs(machine, { Status = NEEDS_OTHER_ORE })
		end
	elseif status == NEEDS_OTHER_ORE then
		MachineService.setAttrs(machine, { Status = "" })
	end
end

-- The queued items the next job takes (In[1] first; In[1] is a valid
-- item), and whether In[1] only passes through (it doesn't belong here:
-- a damaged save). nil while an Alloy Furnace waits for another ore.
local function jobInputs(machine: PlacedMachine, queue: { Desc }): ({ Desc }?, boolean)
	local first = queue[1]
	local accepts = machine.Info.Accepts
	if not accepts or not accepts[first.K] then
		return { first }, true
	end
	if isAlloy(machine) then
		local i, j = MachineLogic.alloyPair(queue)
		if not i or not j then
			return nil, false
		end
		return { queue[i], queue[j] }, false
	end
	return MachineLogic.batch(machine.Id, queue, count(machine.Entry.Out)), false
end

local function startJob(machine: PlacedMachine, inputs: { Desc }, passThrough: boolean, startedAt: number, now: number)
	local input = inputs[1]
	local seconds = jobTime(machine)
	machine.State.Job = {
		Input = input,
		Inputs = inputs,
		EndsAt = startedAt + seconds,
		Odds = jobOdds(machine),
		Results = nil,
		Outputs = nil,
		PassThrough = passThrough,
		Blocked = false,
	} :: Job
	MachineService.setAttrs(machine, {
		Working = true,
		-- the job may have begun a moment before this tick (chained jobs)
		WorkStart = serverNow() - (now - startedAt),
		WorkTime = seconds,
		-- dirty ore hides what it is (its colour would give it away)
		WorkOre = if input.K == "Raw" then "" else input.O,
	})
end

-- Are all of the job's items still where it found them (In[1] first)?
local function stillQueued(queue: { Desc }?, job: Job): boolean
	if not queue or queue[1] ~= job.Input then
		return false
	end
	for _, input in job.Inputs do
		if not table.find(queue, input) then
			return false
		end
	end
	return true
end

-- Stats and the first-ingot toast for furnace output.
local function countIngots(player: Player, outputs: { Desc })
	local ingots = 0
	for _, desc in outputs do
		if desc.K == "Ingot" then
			ingots += 1
		end
	end
	local data = DataService.get(player)
	if ingots == 0 or not data or type(data.Stats) ~= "table" then
		return
	end
	local before = tonumber(data.Stats.IngotsSmelted) or 0
	data.Stats.IngotsSmelted = before + ingots
	if before <= 0 and player.Parent then
		Net.fire("Notify", player, { Text = FIRST_INGOT, Kind = "Reward" })
	end
end

-- Crystal Extractor: whole shards into the owner's save (a broken or
-- negative count starts again from 0) and a toast. The caller marks the
-- save changed.
local function giveShards(player: Player, shards: number)
	local data = DataService.get(player)
	if shards <= 0 or not data then
		return
	end
	local before = tonumber(data.Shards)
	if before == nil or before ~= before or before < 0 or before == math.huge then
		before = 0
	end
	data.Shards = math.floor(before :: number) + shards
	if player.Parent then
		local text = if shards == 1 then SHARD_TOAST else `+{shards} Crystal Shards!`
		Net.fire("Notify", player, { Text = text, Kind = "Reward" })
	end
end

-- The crushed piles of a save not shaken for a shard yet (broken = 0).
local function shardRolls(data: { [string]: any }): number
	local n = tonumber(data.ShardRolls) or 0
	if n ~= n or n <= 0 then
		return 0
	end
	return math.floor(math.min(n, ProcessingService.MaxShardRolls))
end

-- Crushed piles a (non-extractor) job made: each gets one shard roll later.
local function addShardRolls(data: { [string]: any }?, outputs: { Desc })
	if not data then
		return
	end
	local crushed = 0
	for _, desc in outputs do
		if desc.K == "Crushed" then
			crushed += 1
		end
	end
	if crushed > 0 then
		data.ShardRolls = math.min(ProcessingService.MaxShardRolls, shardRolls(data) + crushed)
	end
end

local function announce(player: Player, machineId: string, input: Desc, outputs: { Desc })
	for _, callback in processedCallbacks do
		local copies = {}
		for _, desc in outputs do
			table.insert(copies, copyDesc(desc))
		end
		task.spawn(callback, player, machineId, copyDesc(input), copies)
	end
end

-- What a finished job gives. Items that don't belong in this machine (only
-- possible in a damaged save) come back out unchanged.
local function rollResults(machine: PlacedMachine, job: Job): { Result }
	if job.PassThrough then
		return { { Input = job.Input, Outputs = { copyDesc(job.Input) }, Shard = false } }
	end
	local second = job.Inputs[2]
	if isAlloy(machine) and second then
		return { { Input = job.Input, Outputs = { MachineLogic.alloyDesc(job.Input, second) }, Shard = false } }
	end
	local shardChance = machine.Info.ShardChance
	local data = if shardChance then DataService.get(machine.Owner) else nil
	local results: { Result } = {}
	for _, input in job.Inputs do
		local outputs = MachineLogic.outputs(machine.Id, input, rng:next(), job.Odds)
		local shard = false
		-- one roll per crushed pile ever made (see the header): none left = no roll
		if shardChance and data and shardRolls(data) > 0 then
			data.ShardRolls = shardRolls(data) - 1
			shard = MachineLogic.rollShard(shardChance, rng:next())
		end
		table.insert(results, { Input = input, Outputs = outputs, Shard = shard })
	end
	return results
end

-- Does the sorter take the finished item (into the pen) right now?
local function sorterTakes(machine: PlacedMachine, job: Job, sorter: Sorter?): boolean
	if not sorter or job.PassThrough then
		return false
	end
	local ok, taken = pcall(sorter.take, machine, copyDesc(job.Input))
	if not ok then
		warnThrottled(machine.Id .. ".take", `[ProcessingService] {machine.Id} sorter failed: {taken}`)
		return false
	end
	return taken == true
end

-- Tries to finish the running job. Returns true when it finished (Out had
-- room, or the sorter took the item).
local function finishJob(machine: PlacedMachine, job: Job, sorter: Sorter?): boolean
	local entry = machine.Entry
	local outputs = job.Outputs
	if not outputs then
		local results = rollResults(machine, job)
		local all: { Desc } = {}
		for _, result in results do
			for _, desc in result.Outputs do
				table.insert(all, desc)
			end
		end
		job.Results = results
		job.Outputs = all
		outputs = all
	end
	local list = outputs :: { Desc }
	-- the sorter's take and consume() below run with no yield between them,
	-- so a kept item is in the pen and gone from In in one step
	local kept = sorterTakes(machine, job, sorter)
	if kept then
		list = {}
	elseif count(entry.Out) + #list > MachineData.MaxOutBuffer then
		if not job.Blocked then
			job.Blocked = true
			-- idle while waiting; keep a more specific reason MachineService set
			local status = machine.Model:GetAttribute("Status")
			MachineService.setAttrs(machine, {
				Working = false,
				Status = if status == nil or status == "" then "OutputBlocked" else status,
			})
		end
		return false
	end
	MachineLogic.consume(entry, job.Inputs, list)
	machine.State.Job = nil
	syncCounts(machine)
	local player = machine.Owner
	if not job.PassThrough then
		local sorted = sorter and sorter.sorted
		if sorted then
			local ok, err = pcall(sorted, machine, job.Input, kept)
			if not ok then
				warnThrottled(machine.Id .. ".sorted", `[ProcessingService] {machine.Id} sorted hook failed: {err}`)
			end
		end
		local cycles = machine.Model:GetAttribute("Cycles")
		MachineService.setAttrs(machine, { Cycles = (if type(cycles) == "number" then cycles else 0) + 1 })
		-- a sorter (Iron Box: no Output) only passes the item on: nothing was
		-- smelted, cleaned or discovered, so no stats, toasts or listeners
		if machine.Info.Output ~= nil then
			countIngots(player, list)
			local data = DataService.get(player)
			if not machine.Info.ShardChance then
				addShardRolls(data, list)
			end
			local shards = 0
			local results: { Result } = job.Results or {}
			for _, result in results do
				-- dirty ore that comes out clean reveals what it was (design v2)
				if data and result.Input.K == "Raw" then
					for _, desc in result.Outputs do
						if desc.K == "Clean" then
							Discovery.mark(player, data, desc.O)
						end
					end
				end
				if result.Shard then
					shards += 1
				end
				announce(player, machine.Id, result.Input, result.Outputs)
			end
			giveShards(player, shards)
		end
	end
	DataService.changed(player)
	return true
end

local function tickWith(machine: PlacedMachine, now: number, sorter: Sorter?)
	if machine.Info.QualityLevels and now >= (machine.State.NextQualityCheck or 0) then
		machine.State.NextQualityCheck = now + QUALITY_CHECK
		showQuality(machine)
	end
	local entry = machine.Entry
	local job = machine.State.Job :: Job?
	local startedAt = now
	if job then
		if not stillQueued(entry.In, job) then
			-- the queue changed under the job (repaired save): start over
			machine.State.Job = nil
			job = nil
		elseif now < job.EndsAt then
			return
		else
			local wasBlocked = job.Blocked
			if not finishJob(machine, job, sorter) then
				return
			end
			-- chain the next job from the moment this one ended, unless it waited
			startedAt = if wasBlocked then now else math.max(job.EndsAt, now - GameConfig.MachineTick)
		end
	end
	local queue = entry.In
	local input = queue and queue[1]
	if input == nil then
		MachineService.setAttrs(machine, { Working = false })
		if isAlloy(machine) then
			showWaiting(machine, false)
		end
		return
	end
	if not MachineLogic.isValidDesc(input) then
		-- junk from a damaged save: drop it so the machine doesn't jam
		table.remove(queue :: { Desc }, 1)
		if #(queue :: { Desc }) == 0 then
			entry.In = nil
		end
		warn(`[ProcessingService] dropped a bad item from {machine.Owner.Name}'s {machine.Id}`)
		syncCounts(machine)
		DataService.changed(machine.Owner)
		return
	end
	local inputs, passThrough = jobInputs(machine, queue :: { Desc })
	if isAlloy(machine) then
		showWaiting(machine, inputs == nil)
	end
	if not inputs then
		MachineService.setAttrs(machine, { Working = false })
		return
	end
	startJob(machine, inputs, passThrough, startedAt, now)
end

local function spawned(machine: PlacedMachine)
	MachineService.setAttrs(machine, {
		Queue = count(machine.Entry.In),
		QueueMax = MachineLogic.queueSize(machine.Id),
		OutCount = count(machine.Entry.Out),
		Working = false,
		WorkStart = 0,
		WorkTime = 0,
		Cycles = 0,
		Status = "",
	})
	IntakeService.addLoadPrompt(machine, machine.Info.LoadText or "Put In", 0)
	showQuality(machine)
end

-- The model goes. "Unload" (the player left) and "Refresh" (rebuilt with a
-- new upgrade look) keep the queues in the save: only the job in progress
-- is dropped, and the next model starts it over. "Pickup": MachineService
-- drains the queues into storage after this.
local function removed(machine: PlacedMachine, _reason: MachineService.RemoveReason)
	machine.State.Job = nil
end

local function canAccept(machine: PlacedMachine, desc: Desc, ownerUserId: number, _via: Via)
	return MachineLogic.accepts(machine.Id, desc, machine.Entry, ownerUserId == machine.Owner.UserId)
end

local function insert(machine: PlacedMachine, desc: Desc, _ownerUserId: number, _via: Via)
	MachineLogic.push(machine.Entry, desc)
	syncCounts(machine)
	DataService.changed(machine.Owner)
end

local behaviour: MachineService.Behaviour = {
	spawned = spawned,
	removed = removed,
	canAccept = canAccept,
	insert = insert,
	tick = function(machine: PlacedMachine, now: number)
		tickWith(machine, now, nil)
	end,
}

--[[
	The behaviour of a sorter machine type (register it with
	MachineService.register): the same queue, timed jobs (Bellows + Speed)
	and attributes as the processors, and `sorter` decides where each
	finished item goes (see Sorter).
]]
function ProcessingService.sorterBehaviour(sorter: Sorter): MachineService.Behaviour
	return {
		spawned = function(machine: PlacedMachine)
			spawned(machine)
			local hook = sorter.spawned
			if hook then
				hook(machine)
			end
		end,
		removed = removed,
		canAccept = canAccept,
		insert = insert,
		tick = function(machine: PlacedMachine, now: number)
			tickWith(machine, now, sorter)
		end,
	}
end

-- Internals for the Lune tests only (tests/ProcessingService.spec.luau).
ProcessingService._test = {
	behaviour = behaviour,
	jobTime = jobTime,
	onBought = onBought,
	reseed = function(seed: number)
		rng = Rng.new(seed)
	end,
	reset = function()
		table.clear(processedCallbacks)
	end,
}

function ProcessingService.init()
	for _, id in MACHINES do
		assert(MachineData.ById[id], "unknown processing machine " .. id)
		MachineService.register(id, behaviour)
	end
end

function ProcessingService.start()
	-- in start(), not init(): the Lune specs call init() again for every test
	ShopService.onBought(onBought)
end

return ProcessingService
