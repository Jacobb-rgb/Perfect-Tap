--[[
	MachineLogic: pure machine rules and the In/Out queues of a placed
	machine's saved entry. No Roblox services; fuzz-tested in Lune for item
	conservation (nothing appears or disappears).

	entry.In  = input queue. In[1] is being worked; at most queueSize(id)
	            (MachineIntakeQueue = 4). Anvil ingots wait here too, and so
	            do the items a sorter shows and sorts (Iron Box: a Time but
	            no Output). A sorter's outputs are a copy of its input, so a
	            generic complete() passes the item on unchanged; its service
	            may instead complete with {} and put the item into the pen in
	            the same step (kept ore), never both. A sorter job processes
	            nothing: it never counts toward Stats (IngotsSmelted, the
	            first-ingot toast), Discovery or ProcessingService.onProcessed
	            (ProcessingService only runs those for machines with an Output).
	entry.Out = finished items waiting to leave; at most MachineData.MaxOutBuffer.
	Empty queues are set to nil to keep saves small.

	The roster processors (docs/plans/MACHINES_GAME_PLAN.md):
	  Batch          one job works up to Batch queued items from In[1] at
	                 once, one result each (Plasma Furnace: batch), never more
	                 results than fit in Out
	  GradeUpChance  each output is one grade better with that chance, never
	                 past MaxGrade (Polisher: gradeUp up to Pristine; Flawless
	                 stays Flawless, it only comes from cleaning by hand)
	  ShardChance    a job also gives a crystal shard with that chance
	                 (Crystal Extractor: rollShard; the item passes through;
	                 ProcessingService rolls each crushed pile only once)
	  "Alloy"        a job takes In[1] and the first queued ingot of another
	                 ore (alloyPair) and gives ONE alloy of the more valuable
	                 ore with the lower grade (alloyDesc). The last queue place
	                 is kept for an ingot of another ore, so a queue full of
	                 one ore can never jam the furnace (accepts: 'Full').
	consume() finishes a job on any set of queued items.

	Refusal reasons: 'Full' and 'Busy' mean the item waits; 'Wrong',
	'Foreign' and 'Mixed' mean it is pushed back out.
]]

local ArtifactConfig = require(script.Parent.Parent.Config.ArtifactConfig)
local DropperConfig = require(script.Parent.Parent.Config.DropperConfig)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local ItemData = require(script.Parent.Parent.Config.ItemData)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local OreData = require(script.Parent.Parent.Config.OreData)
local Placement = require(script.Parent.Placement)

local MachineLogic = {}

export type Desc = ItemData.Desc
export type Reason = "Wrong" | "Foreign" | "Mixed" | "Full" | "Busy"
type Entry = Placement.Entry

local ANVIL = "Anvil"
local ALLOY = "Alloy" -- MachineData Behaviour of the Alloy Furnace

-- Machines that turn one input into outputs on a timer (furnaces, Crusher, Auto Cleaner).
local function isProcessor(info: MachineData.Machine): boolean
	return info.Output ~= nil and info.Time ~= nil
end

-- Machines that hold each item for a timed job and pass it on unchanged (Iron Box).
local function isSorter(info: MachineData.Machine): boolean
	return info.Output == nil and info.Time ~= nil and info.Accepts ~= nil
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- A well-formed item: known kind and ore, a known grade (or none), and a
-- known recipe on Gear only (Gear needs one).
function MachineLogic.isValidDesc(desc: any): boolean
	if type(desc) ~= "table" then
		return false
	end
	local kind, oreId, gradeId, recipeId = desc.K, desc.O, desc.G, desc.R
	if type(kind) ~= "string" or not ItemData.Kinds[kind] then
		return false
	end
	-- a Drop carries its dropper's id and at most the Money Laser's mark (DropperConfig)
	if kind == DropperConfig.DropKind then
		return DropperConfig.validDrop(desc)
	end
	-- a dusty relic carries its artifact id, never a grade or recipe
	if kind == "Relic" then
		return type(oreId) == "string" and ArtifactConfig.ById[oreId] ~= nil and gradeId == nil and recipeId == nil
	end
	if type(oreId) ~= "string" or not OreData.ById[oreId] then
		return false
	end
	if gradeId ~= nil and (type(gradeId) ~= "string" or not ItemData.GradeById[gradeId]) then
		return false
	end
	if kind == "Gear" then
		return type(recipeId) == "string" and ItemData.RecipeById[recipeId] ~= nil
	end
	return recipeId == nil
end

-- How many items wait in In (the one being worked included): processors,
-- the Anvil and every other machine with a job Time (Iron Box). 0 for
-- machines that take items straight away (crate, chute) or never queue.
function MachineLogic.queueSize(id: string): number
	local info = MachineData.ById[id]
	if info and (isProcessor(info) or isSorter(info) or id == ANVIL) then
		return GameConfig.MachineIntakeQueue
	end
	return 0
end

-- Would the machine take this item right now? `sameOwner` = the item belongs
-- to the machine's owner.
function MachineLogic.accepts(id: string, desc: Desc, entry: Entry, sameOwner: boolean): (boolean, Reason?)
	local info = MachineData.ById[id]
	if not info or not MachineLogic.isValidDesc(desc) then
		return false, "Wrong"
	end
	if info.AcceptsForeign then
		-- Sell Chute: anything worth something, from anyone
		local accepted = info.Accepts ~= nil and info.Accepts[desc.K] == true
		if accepted and ItemData.value(desc.K, desc.O, desc.G, desc.R) > 0 then
			return true, nil
		end
		return false, "Wrong"
	end
	if not sameOwner then
		return false, "Foreign"
	end
	if info.IsConveyor or id == "CleaningStation" or not info.Accepts or not info.Accepts[desc.K] then
		return false, "Wrong"
	end
	local queue = entry.In
	local queued = if queue then #queue else 0
	if id == ANVIL then
		if queue and queue[1] and queue[1].O ~= desc.O then
			return false, "Mixed"
		end
		if queued >= MachineLogic.queueSize(id) then
			return false, "Full"
		end
	elseif MachineLogic.queueSize(id) > 0 then
		local size = MachineLogic.queueSize(id)
		if queued >= size then
			return false, "Full"
		end
		if info.Behaviour == ALLOY and queued + 1 >= size and not MachineLogic.hasOtherOre(queue, desc.O) then
			-- the last place waits for an ingot of another ore (else the queue
			-- could fill up with one ore and never make an alloy)
			return false, "Full"
		end
	end
	-- Storage Crate: the shared store's capacity is checked by StorageService
	return true, nil
end

-- Output grade from odds like { Rough = 0.6, Clean = 0.4 } and a roll in
-- [0, 1). Grades are walked from lowest to highest; a grade above maxGrade
-- counts as maxGrade. Odds that don't add up to 1 are scaled.
function MachineLogic.rollGrade(chances: { [string]: number }, maxGrade: string, roll: number): string
	local total = 0
	for _, grade in ItemData.Grades do
		local chance = chances[grade.Id]
		if isFinite(chance) and chance > 0 then
			total += chance
		end
	end
	local pick = "Rough"
	if total > 0 then
		local target = math.clamp(if isFinite(roll) then roll else 0, 0, 1) * total
		local cumulative = 0
		for _, grade in ItemData.Grades do
			local chance = chances[grade.Id]
			if isFinite(chance) and chance > 0 then
				cumulative += chance
				pick = grade.Id
				if target < cumulative then
					break
				end
			end
		end
	end
	if ItemData.gradeLevel(pick) > ItemData.gradeLevel(maxGrade) then
		return maxGrade
	end
	return pick
end

-- What one finished job turns `input` into. `roll` in [0, 1) is only used
-- by machines with GradeChances (Cleaning Plant) or GradeUpChance
-- (Polisher: roll < chance = one grade better); `odds` replaces their
-- GradeChances (the Cleaning Plant's Quality level: MachineData.gradeOdds).
-- A sorter (Iron Box) gives back a copy of `input`, so no item is ever lost.
-- An Alloy Furnace job needs two ingots: alloyDesc makes its output.
function MachineLogic.outputs(id: string, input: Desc, roll: number, odds: { [string]: number }?): { Desc }
	local info = MachineData.ById[id]
	local list: { Desc } = {}
	if not info then
		return list
	end
	if isSorter(info) then
		table.insert(list, { K = input.K, O = input.O, G = input.G, R = input.R })
		return list
	end
	if not isProcessor(info) or info.Behaviour == ALLOY then
		return list
	end
	local kind = info.Output :: string
	local grade: string
	local chances = if info.GradeChances then odds or info.GradeChances else nil
	if chances then
		grade = MachineLogic.rollGrade(chances, info.MaxGrade or "Flawless", roll)
	else
		grade = input.G or "Rough"
	end
	if info.GradeUpChance then
		grade = MachineLogic.gradeUp(grade, info.GradeUpChance, roll, info.MaxGrade)
	end
	for _ = 1, info.OutputCount or 1 do
		table.insert(list, { K = kind, O = input.O, G = grade })
	end
	return list
end

---------------------------------------------------------------- roster processors

-- The grade one better (Rough -> Clean -> Pristine -> Flawless; Flawless
-- stays; nil or unknown counts as Rough).
function MachineLogic.nextGrade(gradeId: string?): string
	local level = ItemData.gradeLevel(gradeId)
	local grade = ItemData.Grades[math.clamp(level + 1, 1, #ItemData.Grades)]
	return grade.Id
end

-- Polisher: `gradeId` one grade better when roll < chance, else as it is
-- (nil or unknown counts as Rough). A broken chance or roll never
-- upgrades; a chance above 1 counts as 1. Never past `maxGrade` (a grade
-- already at or above it stays as it is: Flawless stays Flawless).
function MachineLogic.gradeUp(gradeId: string?, chance: number?, roll: number, maxGrade: string?): string
	local grade = if gradeId and ItemData.GradeById[gradeId] then gradeId else "Rough"
	local odds = if isFinite(chance) then math.clamp(chance :: number, 0, 1) else 0
	if maxGrade and ItemData.GradeById[maxGrade] and ItemData.gradeLevel(grade) >= ItemData.gradeLevel(maxGrade) then
		return grade
	end
	if isFinite(roll) and roll < odds then
		return MachineLogic.nextGrade(grade)
	end
	return grade
end

-- Crystal Extractor: does a job with this roll in [0, 1) give a shard?
function MachineLogic.rollShard(chance: number?, roll: number): boolean
	local odds = if isFinite(chance) then math.clamp(chance :: number, 0, 1) else 0
	return isFinite(roll) and roll < odds
end

-- Does the queue hold a valid ingot of an ore other than `oreId`?
function MachineLogic.hasOtherOre(queue: { Desc }?, oreId: string): boolean
	if not queue then
		return false
	end
	for _, desc in queue do
		if MachineLogic.isValidDesc(desc) and desc.K == "Ingot" and desc.O ~= oreId then
			return true
		end
	end
	return false
end

-- The two queued items an Alloy Furnace job takes: In[1] (an ingot) and
-- the first queued ingot of another ore. Returns (1, j), or (nil, nil)
-- while every queued ingot is of In[1]'s ore or In[1] is no valid ingot.
function MachineLogic.alloyPair(queue: { Desc }?): (number?, number?)
	if not queue then
		return nil, nil
	end
	local first = queue[1]
	if not MachineLogic.isValidDesc(first) or first.K ~= "Ingot" then
		return nil, nil
	end
	for j = 2, #queue do
		local desc = queue[j]
		if MachineLogic.isValidDesc(desc) and desc.K == "Ingot" and desc.O ~= first.O then
			return 1, j
		end
	end
	return nil, nil
end

-- What one Rough item of an ore sells for, then its podium income (which
-- of two ores is worth more). Unknown ores are worth nothing.
local function oreWorth(oreId: string): (number, number)
	local ore = OreData.ById[oreId]
	if not ore then
		return -1, -1
	end
	return ore.Value, ore.Income
end

-- The alloy two ingots make: ONE item of the more valuable ore (OreData
-- Value, then Income; a tie keeps `a`'s ore) with the lower of the two
-- grades (nil counts as Rough).
function MachineLogic.alloyDesc(a: Desc, b: Desc): Desc
	local valueA, incomeA = oreWorth(a.O)
	local valueB, incomeB = oreWorth(b.O)
	local oreId = if valueB > valueA or (valueB == valueA and incomeB > incomeA) then b.O else a.O
	local gradeA = if a.G and ItemData.GradeById[a.G] then a.G else "Rough"
	local gradeB = if b.G and ItemData.GradeById[b.G] then b.G else "Rough"
	local grade = if ItemData.gradeLevel(gradeB) < ItemData.gradeLevel(gradeA) then gradeB else gradeA
	return { K = "Alloy", O = oreId, G = grade }
end

--[[
	The queued items one job of machine `id` takes, in order from In[1]:
	just In[1] for most machines; up to Batch items for a batch machine
	(Plasma Furnace), but never more results than fit in Out
	(MaxOutBuffer - outCount; In[1] always goes), and only items the
	machine accepts join In[1]. Empty without a queue. (Alloy: alloyPair.)
]]
function MachineLogic.batch(id: string, queue: { Desc }?, outCount: number): { Desc }
	local list: { Desc } = {}
	local info = MachineData.ById[id]
	if not info or not queue or #queue == 0 then
		return list
	end
	table.insert(list, queue[1])
	local size = if isFinite(info.Batch) then math.floor(info.Batch :: number) else 1
	if size <= 1 then
		return list
	end
	local per = math.max(1, info.OutputCount or 1)
	local used = if isFinite(outCount) then outCount else 0
	local room = math.floor((MachineData.MaxOutBuffer - used) / per)
	local accepts = info.Accepts
	for i = 2, math.min(size, room, #queue) do
		local desc = queue[i]
		if not accepts or not MachineLogic.isValidDesc(desc) or not accepts[desc.K] then
			break
		end
		table.insert(list, desc)
	end
	return list
end

-- Adds an item to the input queue (check accepts first).
function MachineLogic.push(entry: Entry, desc: Desc)
	local queue: { Desc } = entry.In or {}
	entry.In = queue
	table.insert(queue, desc)
end

-- Finishes the job on In[1]: removes it and appends the outputs to Out.
-- (Check #Out + #outputs <= MaxOutBuffer first.)
function MachineLogic.complete(entry: Entry, outputs: { Desc })
	local queue = entry.In
	if queue and #queue > 0 then
		table.remove(queue, 1)
		if #queue == 0 then
			entry.In = nil
		end
	end
	if #outputs > 0 then
		local out: { Desc } = entry.Out or {}
		entry.Out = out
		for _, desc in outputs do
			table.insert(out, desc)
		end
	end
end

-- Finishes a job on several queued items (Batch, Alloy): takes each of
-- `inputs` (the very tables in In, found by identity) out of In and
-- appends the outputs to Out. (Check #Out + #outputs <= MaxOutBuffer first.)
function MachineLogic.consume(entry: Entry, inputs: { Desc }, outputs: { Desc })
	local queue = entry.In
	if queue then
		for _, input in inputs do
			local index = table.find(queue, input)
			if index then
				table.remove(queue, index)
			end
		end
		if #queue == 0 then
			entry.In = nil
		end
	end
	if #outputs > 0 then
		local out: { Desc } = entry.Out or {}
		entry.Out = out
		for _, desc in outputs do
			table.insert(out, desc)
		end
	end
end

-- Takes the next finished item out of Out.
function MachineLogic.popOut(entry: Entry): Desc?
	local out = entry.Out
	if not out or #out == 0 then
		entry.Out = nil
		return nil
	end
	local desc = table.remove(out, 1)
	if #out == 0 then
		entry.Out = nil
	end
	return desc
end

-- Empties the machine: In first, then Out. Both become nil.
function MachineLogic.drain(entry: Entry): { Desc }
	local list: { Desc } = {}
	for _, queue in { entry.In, entry.Out } do
		if queue then
			for _, desc in queue do
				table.insert(list, desc)
			end
		end
	end
	entry.In = nil
	entry.Out = nil
	return list
end

-- Anvil recipes you can make with `count` ingots, in ItemData.Recipes order.
function MachineLogic.recipeOptions(count: number): { string }
	local list = {}
	for _, recipe in ItemData.Recipes do
		if recipe.Ingots <= count then
			table.insert(list, recipe.Id)
		end
	end
	return list
end

-- Forges the first N ingots in In (oldest first) into one Gear with the
-- lowest grade among them. Returns the gear and N, or (nil, 0) when the
-- recipe is unknown or the ingots aren't there (nothing changes then).
function MachineLogic.forge(entry: Entry, recipeId: string): (Desc?, number)
	local recipe = ItemData.RecipeById[recipeId]
	local queue = entry.In
	if not recipe or not queue or #queue < recipe.Ingots then
		return nil, 0
	end
	local oreId = queue[1].O
	local lowest: string? = nil
	for i = 1, recipe.Ingots do
		local ingot = queue[i]
		if ingot.K ~= "Ingot" or ingot.O ~= oreId then
			return nil, 0
		end
		local grade = ingot.G or "Rough"
		if lowest == nil or ItemData.gradeLevel(grade) < ItemData.gradeLevel(lowest) then
			lowest = grade
		end
	end
	for _ = 1, recipe.Ingots do
		table.remove(queue, 1)
	end
	if #queue == 0 then
		entry.In = nil
	end
	return { K = "Gear", O = oreId, G = lowest or "Rough", R = recipe.Id }, recipe.Ingots
end

-- Checks the hammer strike times a client sends (seconds since the session
-- began). Needs exactly `hits` finite times, each in 0..elapsed+1, strictly
-- increasing, at least AnvilMinStrikeGap apart, the last one at least
-- hits * AnvilMinSecondsPerHit. Returns (false, why) otherwise.
function MachineLogic.validateStrikes(strikes: any, hits: number, elapsed: number): (boolean, string?)
	if type(strikes) ~= "table" then
		return false, "not a list"
	end
	if not isFinite(hits) or hits < 1 or hits ~= math.floor(hits) or not isFinite(elapsed) then
		return false, "bad session"
	end
	local count = 0
	for _ in strikes do
		count += 1
		if count > hits then
			return false, "wrong count"
		end
	end
	if count ~= hits then
		return false, "wrong count"
	end
	local last = -math.huge
	for i = 1, hits do
		local t = strikes[i]
		if not isFinite(t) then
			return false, "bad time"
		end
		if t < 0 or t > elapsed + 1 then
			return false, "time out of range"
		end
		if t <= last then
			return false, "not increasing"
		end
		if i > 1 and t - last < GameConfig.AnvilMinStrikeGap then
			return false, "too fast"
		end
		last = t
	end
	if last < hits * GameConfig.AnvilMinSecondsPerHit then
		return false, "too quick overall"
	end
	return true, nil
end

return MachineLogic
