--[[
	ProcessingService: the machines that work on their own. Clay Furnace and
	Blast Furnace smelt clean or crushed ore into ingots, the Crusher turns 1
	clean ore into 2 crushed piles, the Cleaning Plant (Id AutoCleaner)
	cleans raw ore with the grade odds of its Quality level
	(MachineData.QualityLevels / gradeOdds: 60% Rough / 40% Clean at level
	0, up to 30% Flawless at level 5; MachineLogic.outputs takes the odds).

	- Items arrive through MachineService (hopper, belt, Put In prompt or a
	  machine in front): canAccept = MachineLogic.accepts, insert = push onto
	  the saved queue (Entry.In, at most 4; In[1] is being worked).
	- The 10 Hz MachineService tick runs one job at a time per machine. A
	  finished job moves In[1] out and its results into Entry.Out (at most
	  MachineData.MaxOutBuffer); MachineService then sends Out through the
	  machine's front. If Out has no room, the job waits ('OutputBlocked').
	- Job time = MachineData.processTime with the owner's Bellows level and
	  the machine type's Speed level (Tech shop, data.MachineUpgrades, read
	  through EconomyConfig.upgradeLevel), both read when each job starts,
	  never below GameConfig.MinProcessTime.
	- Grade odds (Cleaning Plant) = MachineData.gradeOdds of the machine
	  type's Quality level, read when each job starts. The plant shows them:
	  attributes Quality (level) and QualityOdds ("30% Rough · 50% Clean ·
	  20% Pristine"), also on its Put In prompt's ObjectText; refreshed every
	  QUALITY_CHECK seconds, so a level bought in the Tech shop shows at once.
	- Queue and Out live in the save (Entry.In / Entry.Out), so leaving,
	  autosaves and shutdowns keep them. Job progress is not saved: after a
	  rejoin the job on In[1] starts over.
	- Clients animate everything from model attributes (MachineFxController):
	  Queue, QueueMax, OutCount, Working, WorkStart, WorkTime, WorkOre, Cycles.
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

local ProcessingService = {}

type PlacedMachine = MachineService.PlacedMachine
type Desc = MachineLogic.Desc
type Via = MachineService.Via

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

-- Runtime job state, kept in machine.State.Job (never saved).
type Job = {
	Input: Desc, -- the In[1] table being worked
	EndsAt: number, -- os.clock() time the job finishes
	Odds: { [string]: number }?, -- grade odds of the Quality level when it started (Cleaning Plant)
	Outputs: { Desc }?, -- rolled once when it finishes (a blocked job keeps its roll)
	PassThrough: boolean, -- the input doesn't belong here and comes back out as is
	Blocked: boolean, -- finished but Out had no room
}

local MACHINES = { "ClayFurnace", "BlastFurnace", "Crusher", "AutoCleaner" }
local FIRST_INGOT = "Your first ingot! Ingots go into the Foundry (soon) to forge stronger blasters, or sell them to Tobin."
-- seconds between checks of the Cleaning Plant's Quality level (shown odds)
local QUALITY_CHECK = 1
local WARN_COOLDOWN = 10

local processedCallbacks: { (Player, string, Desc, { Desc }) -> ...any } = {}
-- output grade rolls (Auto Cleaner); the seed only needs to differ per server
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
-- They get copies, so changing them can't touch the machine's queues.
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

---------------------------------------------------------------- upgrades

-- The owner's level of an upgrade of this machine type (0 without a save).
local function upgradeLevel(machine: PlacedMachine, kind: string): number
	local data = DataService.get(machine.Owner)
	return if data then EconomyConfig.upgradeLevel(data, machine.Id, kind) else 0
end

-- Seconds one job takes for this machine's owner right now (Bellows + Speed).
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
	return math.max(GameConfig.MinProcessTime, seconds)
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
		prompt.ObjectText = `{machine.Info.Name} · Quality {level}: {text}`
	end
end

---------------------------------------------------------------- jobs

local function syncCounts(machine: PlacedMachine)
	MachineService.setAttrs(machine, {
		Queue = count(machine.Entry.In),
		OutCount = count(machine.Entry.Out),
	})
end

local function startJob(machine: PlacedMachine, startedAt: number, now: number)
	local queue = machine.Entry.In
	local input = queue and queue[1]
	if not input then
		return
	end
	local seconds = jobTime(machine)
	machine.State.Job = {
		Input = input,
		EndsAt = startedAt + seconds,
		Odds = jobOdds(machine),
		Outputs = nil,
		PassThrough = false,
		Blocked = false,
	} :: Job
	MachineService.setAttrs(machine, {
		Working = true,
		-- the job may have begun a moment before this tick (chained jobs)
		WorkStart = serverNow() - (now - startedAt),
		WorkTime = seconds,
		WorkOre = input.O,
	})
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

local function announce(player: Player, machineId: string, input: Desc, outputs: { Desc })
	for _, callback in processedCallbacks do
		local copies = {}
		for _, desc in outputs do
			table.insert(copies, copyDesc(desc))
		end
		task.spawn(callback, player, machineId, copyDesc(input), copies)
	end
end

-- What a finished job on `input` gives. Items that don't belong in this
-- machine (only possible in a damaged save) come back out unchanged.
local function rollOutputs(machine: PlacedMachine, job: Job): { Desc }
	local accepts = machine.Info.Accepts
	if not accepts or not accepts[job.Input.K] then
		job.PassThrough = true
		return { copyDesc(job.Input) }
	end
	return MachineLogic.outputs(machine.Id, job.Input, rng:next(), job.Odds)
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
		outputs = rollOutputs(machine, job)
		job.Outputs = outputs
	end
	local list = outputs :: { Desc }
	-- the sorter's take and complete() below run with no yield between them,
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
	MachineLogic.complete(entry, list)
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
			-- dirty ore that comes out clean reveals what it was (design v2)
			local data = DataService.get(player)
			if data and job.Input.K == "Raw" then
				for _, desc in list do
					if desc.K == "Clean" then
						Discovery.mark(player, data, desc.O)
					end
				end
			end
			announce(player, machine.Id, job.Input, list)
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
		local queue = entry.In
		if not queue or queue[1] ~= job.Input then
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
	startJob(machine, startedAt, now)
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

return ProcessingService
