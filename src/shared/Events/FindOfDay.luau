--[[
	FindOfDay: the pure part of the Find of the Day (owner 2026-11-07: "nález dne",
	shown ONLY on the big iron billboard, never on the player's screen). The
	best ore cleaned today on any server: the rarest ore (OreData's order, a
	secret ore above all others), then the better grade; the first to find it
	keeps it. A day is a UTC day. FindOfDayService keeps it, EventBoard shows it.

	  Entry = { Day, Name, Ore, Grade } (Name: a DisplayName)
]]

local ItemData = require(script.Parent.Parent.Config.ItemData)
local OreData = require(script.Parent.Parent.Config.OreData)

local FindOfDay = {}

FindOfDay.MaxName = 20 -- characters: a DisplayName is at most 20

export type Entry = { Day: number, Name: string, Ore: string, Grade: string }

function FindOfDay.day(now: number): number
	return math.floor(now / 86400)
end

-- A find's rank: the higher the better (0 for an unknown ore).
function FindOfDay.rank(oreId: any, gradeId: any): number
	local ore: any = if type(oreId) == "string" then OreData.ById[oreId] else nil
	if not ore then
		return 0
	end
	return ore.Index * 10 + ItemData.gradeLevel(gradeId)
end

-- Is `find` better than `best` for `day`? (a best of another day doesn't count)
function FindOfDay.better(find: Entry, best: Entry?, day: number): boolean
	if find.Day ~= day then
		return false
	end
	if not best or best.Day ~= day then
		return true
	end
	return FindOfDay.rank(find.Ore, find.Grade) > FindOfDay.rank(best.Ore, best.Grade)
end

-- A stored or received entry, checked; nil if anything is wrong with it.
function FindOfDay.read(data: any): Entry?
	if type(data) ~= "table" then
		return nil
	end
	local day, name, ore, grade = data.Day, data.Name, data.Ore, data.Grade
	if type(day) ~= "number" or day ~= day or day % 1 ~= 0 then
		return nil
	end
	local length = if type(name) == "string" then utf8.len(name) else nil
	if not length or length == 0 or length > FindOfDay.MaxName then
		return nil
	end
	if FindOfDay.rank(ore, grade) == 0 or type(grade) ~= "string" then
		return nil
	end
	return { Day = day, Name = name, Ore = ore, Grade = grade }
end

return FindOfDay
