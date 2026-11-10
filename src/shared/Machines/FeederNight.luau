--[[
	FeederNight: what the machines do with the Ore Feeder's ore while the
	player is away (owner 2026-11-07: Night Shift's machines, only on ore the
	player put in the feeder, never the pen by itself; 25 % for 8 h, 50 % for
	12 h with the pass: EconomyConfig.Offline). Pure: a save's tables in, the
	feeders' queues and the pen's list changed in place, a report out; no yields.

	- The feeders feed one ore every MachineData.FeederSeconds of `work`
	  (seconds away, capped, x the offline rate), front first, feeder by
	  feeder in saved order.
	- Each ore walks the line as far as the base has a machine for its kind
	  (dirty -> Cleaning Plant -> clean -> Crusher -> crushed x2 -> Furnace ->
	  ingot), through MachineLogic.outputs with the owner's grade odds. Every
	  stage does at most (work x its jobs per second) items (line).
	- What comes out goes into the pen (data.Storage) while it has room; an
	  ore whose outputs don't fit stays in the feeder, and so does an ore no
	  machine takes, and a SECRET ore (that one is the player's own moment).
	- The line isn't walked belt by belt: a machine that stands on the plot
	  counts (the power it needs doesn't).
]]

local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local SecretOreConfig = require(script.Parent.Parent.Config.SecretOreConfig)
local MachineLogic = require(script.Parent.MachineLogic)

local FeederNight = {}

export type Stage = { Machine: string, PerSecond: number, Best: number }
export type Line = { [string]: Stage }
export type Report = {
	Fed: number, -- ores the feeders gave the line
	Total: number, -- pieces that went into the pen
	Bars: number,
	Made: { [string]: { K: string, O: string, G: string?, N: number } },
	Cleaned: { [string]: boolean }, -- ores that came out of the dirt (the codex finds them)
}

-- The kinds a line takes (the Alloy Furnace's ingots are the player's own choice).
local KINDS = { "Raw", "Clean", "Crushed" }

--[[
	This base's line: per item kind the fastest placed machine that moves it on
	(a Polisher's or an Extractor's output is what it took: no stage) and the jobs
	per second of all of those.
]]
function FeederNight.line(data: { [string]: any }): Line
	local line: Line = {}
	local placed = data.PlacedMachines
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	if type(placed) ~= "table" then
		return line
	end
	for _, entry in placed do
		local id = if type(entry) == "table" then entry.Id else nil
		local machine = if type(id) == "string" then MachineData.ById[id] else nil
		if machine and not machine.Retired and machine.Output and machine.Accepts and (machine.Inputs or 1) == 1 then
			local info = MachineData.info(id, MachineData.tierOf(data.MachineUpgrades, id))
			local seconds = MachineData.processTime(info, upgrades.Bellows, EconomyConfig.upgradeLevel(data, id, "Speed"))
			if seconds > 0 then
				local perSecond = (info.Batch or 1) / seconds
				for _, kind in KINDS do
					if machine.Accepts[kind] and machine.Output ~= kind then
						local stage = line[kind]
						if not stage then
							line[kind] = { Machine = id, PerSecond = perSecond, Best = perSecond }
						else
							stage.PerSecond += perSecond
							if perSecond > stage.Best then
								stage.Machine = id
								stage.Best = perSecond
							end
						end
					end
				end
			end
		end
	end
	return line
end

-- The feeders' queues in saved order (the live machines share these tables).
function FeederNight.queues(data: { [string]: any }): { { any } }
	local list = {}
	local placed = data.PlacedMachines
	if type(placed) ~= "table" then
		return list
	end
	for _, entry in placed do
		local info = if type(entry) == "table" and type(entry.Id) == "string" then MachineData.ById[entry.Id] else nil
		if info and info.Behaviour == "Feeder" and type(entry.In) == "table" and #entry.In > 0 then
			table.insert(list, entry.In)
		end
	end
	return list
end

-- Walks one ore through the line; the pieces it ends as, or nil when no stage takes it.
local function walk(
	first: any,
	line: Line,
	jobs: { [string]: number },
	odds: (string) -> { [string]: number }?,
	random: () -> number,
	cleaned: { [string]: boolean }
): { any }?
	local walking = { first }
	local done = {}
	local moved = false
	while #walking > 0 do
		local item: any = table.remove(walking)
		local stage = line[item.K]
		local outputs = nil
		if stage and (jobs[item.K] or 0) >= 1 then
			outputs = MachineLogic.outputs(stage.Machine, item, random(), odds(stage.Machine))
		end
		if outputs and #outputs > 0 then
			jobs[item.K] -= 1
			moved = true
			if item.K == "Raw" then
				cleaned[item.O] = true
			end
			for _, output in outputs do
				table.insert(walking, output)
			end
		else
			table.insert(done, item)
		end
	end
	return if moved then done else nil
end

--[[
	Runs `line` for `work` seconds over the feeders' `queues` (changed in place),
	putting what comes out into `storage` (data.Storage, changed in place) up to
	`capacity`. `odds(machineId)`: a machine's grade odds, or nil. `random`:
	rolls in [0, 1).
]]
function FeederNight.run(
	queues: { { any } },
	storage: { any },
	line: Line,
	work: number,
	capacity: number,
	odds: (string) -> { [string]: number }?,
	random: () -> number
): Report
	local report: Report = { Fed = 0, Total = 0, Bars = 0, Made = {}, Cleaned = {} }
	local feeds = math.floor(math.max(work, 0) / MachineData.FeederSeconds)
	local jobs: { [string]: number } = {}
	for kind, stage in line do
		jobs[kind] = math.floor(stage.PerSecond * math.max(work, 0))
	end
	for _, queue in queues do
		local kept = {}
		for index, ore in queue do
			local done: { any }? = nil
			local room = capacity - #storage
			if
				feeds > 0
				and room > 0
				and type(ore) == "table"
				and MachineLogic.isValidDesc(ore)
				and not SecretOreConfig.isSecret(ore.O)
			then
				-- (a try on copies: an ore that can't finish here stays in the feeder as it was)
				local trialJobs = table.clone(jobs)
				local cleaned = {}
				local pieces = walk(table.clone(ore), line, trialJobs, odds, random, cleaned)
				if pieces and #pieces <= room then
					done = pieces
					jobs = trialJobs
					for oreId in cleaned do
						report.Cleaned[oreId] = true
					end
				end
			end
			if done then
				feeds -= 1
				report.Fed += 1
				for _, item in done do
					table.insert(storage, item)
					report.Total += 1
					if item.K == "Ingot" then
						report.Bars += 1
					end
					local key = `{item.K}|{item.O}|{item.G or ""}`
					local row = report.Made[key]
					if row then
						row.N += 1
					else
						report.Made[key] = { K = item.K, O = item.O, G = item.G, N = 1 }
					end
				end
			else
				table.insert(kept, queue[index])
			end
		end
		table.clear(queue)
		for k, ore in kept do
			queue[k] = ore
		end
	end
	return report
end

return FeederNight
