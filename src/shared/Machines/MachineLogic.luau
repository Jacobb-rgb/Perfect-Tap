--[[
	MachineLogic: pure machine rules and the In/Out queues of a placed
	machine's saved entry. No Roblox services; fuzz-tested in Lune for item
	conservation (nothing appears or disappears).

	entry.In  = input queue. In[1] is being worked; at most queueSize(id)
	            (MachineIntakeQueue = 4). Anvil ingots wait here too.
	entry.Out = finished items waiting to leave; at most MachineData.MaxOutBuffer.
	Empty queues are set to nil to keep saves small.

	Refusal reasons: 'Full' and 'Busy' mean the item waits; 'Wrong',
	'Foreign' and 'Mixed' mean it is pushed back out.
]]

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

-- Machines that turn one input into outputs on a timer (furnaces, Crusher, Auto Cleaner).
local function isProcessor(info: MachineData.Machine): boolean
	return info.Output ~= nil and info.Time ~= nil
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

-- How many items wait in In (the one being worked included). 0 for
-- machines that take items straight away (crate, chute) or never queue.
function MachineLogic.queueSize(id: string): number
	local info = MachineData.ById[id]
	if info and (isProcessor(info) or id == ANVIL) then
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
	elseif isProcessor(info) then
		if queued >= MachineLogic.queueSize(id) then
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
-- by machines with GradeChances (Auto Cleaner).
function MachineLogic.outputs(id: string, input: Desc, roll: number): { Desc }
	local info = MachineData.ById[id]
	local list: { Desc } = {}
	if not info or not isProcessor(info) then
		return list
	end
	local kind = info.Output :: string
	local grade: string
	if info.GradeChances then
		grade = MachineLogic.rollGrade(info.GradeChances, info.MaxGrade or "Flawless", roll)
	else
		grade = input.G or "Rough"
	end
	for _ = 1, info.OutputCount or 1 do
		table.insert(list, { K = kind, O = input.O, G = grade })
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
