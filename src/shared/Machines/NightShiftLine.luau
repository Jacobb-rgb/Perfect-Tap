--[[
	NightShiftLine: what the machines do while the player is away (Night
	Shift, Config/NightShiftConfig). Pure: a save's tables in, the pen's list
	changed in place, a count out; no yields.

	No ore from nothing: the machines finish ore that already lies in the pen
	and that the sorting billboard would send them anyway (what
	MachineData.keeps doesn't keep; never a SECRET ore; dirty ore only if it
	wouldn't be kept once clean, NightShiftConfig.CleansKept). Each item walks the
	line as far as the base has a machine for its kind (dirty -> Auto Cleaner
	-> clean -> Crusher -> crushed x2 -> furnace -> ingot), through
	MachineLogic.outputs with the owner's own grade odds. Every stage can do
	(work seconds x its jobs per second) items. An item that would make more
	than one piece and the pen has no room for the rest stays as it is. An
	item's place in the pen is kept; a second output goes to the end of the list.

	The line isn't walked belt by belt: a machine that stands on the plot
	counts (the power it needs doesn't).
]]

local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local MachineData = require(script.Parent.Parent.Config.MachineData)
local NightShiftConfig = require(script.Parent.Parent.Config.NightShiftConfig)
local MachineLogic = require(script.Parent.MachineLogic)

local NightShiftLine = {}

export type Stage = { Machine: string, PerSecond: number, Best: number }
export type Line = { [string]: Stage }
export type Report = {
	Total: number,
	Bars: number,
	Made: { [string]: { K: string, O: string, G: string?, N: number } },
	Cleaned: { [string]: boolean }, -- ores that came out of the dirt (the codex finds them)
}

-- The kinds a line takes (the Anvil's and the Alloy Furnace's ingots are the player's own choice).
local KINDS = { "Raw", "Clean", "Crushed" }

-- This base's line: per item kind the fastest machine that moves it on (a Polisher's or an
-- Extractor's output is what it took: no stage) and the jobs per second of all of those.
function NightShiftLine.line(data: { [string]: any }): Line
	local line: Line = {}
	local placed = data.PlacedMachines
	local upgrades = if type(data.Upgrades) == "table" then data.Upgrades else {}
	if type(placed) ~= "table" then
		return line
	end
	for _, entry in placed do
		local id = if type(entry) == "table" then entry.Id else nil
		local machine = if type(id) == "string" then MachineData.ById[id] else nil
		if machine and machine.Output and machine.Accepts and (machine.Inputs or 1) == 1 then
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

--[[
	Runs `line` for `work` seconds over `storage` (data.Storage; changed in
	place). `capacity`: the pen's. keepMode / keepList: data.KeepMode /
	KeepList. `odds(machineId)`: a machine's grade odds, or nil. `random`:
	rolls in [0, 1).
]]
function NightShiftLine.run(
	storage: { any },
	line: Line,
	work: number,
	capacity: number,
	keepMode: any,
	keepList: any,
	odds: (string) -> { [string]: number }?,
	random: () -> number
): Report
	local report: Report = { Total = 0, Bars = 0, Made = {}, Cleaned = {} }
	local jobs: { [string]: number } = {}
	for kind, stage in line do
		jobs[kind] = math.floor(stage.PerSecond * math.max(work, 0))
	end
	local room = capacity - #storage
	for index = 1, #storage do
		local first = storage[index]
		if type(first) == "table" and MachineLogic.isValidDesc(first) and first.R == nil then
			local walking = { first }
			local done = {}
			while #walking > 0 do
				local item: any = table.remove(walking)
				local stage = line[item.K]
				local outputs = nil
				local leftDirty = item.K == "Raw" and not NightShiftConfig.CleansKept and MachineData.keepsOre(keepMode, keepList, item.O)
				if stage and jobs[item.K] >= 1 and not leftDirty and not MachineData.keeps(keepMode, keepList, item) then
					outputs = MachineLogic.outputs(stage.Machine, item, random(), odds(stage.Machine))
				end
				if outputs and #outputs > 0 and (#outputs == 1 or #outputs - 1 <= room) then
					jobs[item.K] -= 1
					room -= #outputs - 1
					if item.K == "Raw" then
						report.Cleaned[item.O] = true
					end
					for _, output in outputs do
						table.insert(walking, output)
					end
				else
					table.insert(done, item)
				end
			end
			storage[index] = done[1]
			for k = 2, #done do
				table.insert(storage, done[k])
			end
			for _, item in done do
				if item.K ~= first.K then
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
			end
		end
	end
	return report
end

return NightShiftLine
