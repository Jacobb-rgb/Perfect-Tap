--[[
	Crystal shards (data.Shards, a whole number >= 0): the Crystal Extractor
	finds them, the wheel and duplicate artifacts give them, the Enchant shop
	spends them. The machines work adds the field to DataTemplate/Migrations;
	until then (and always) these helpers read it defensively, so steps 6-7
	read and write shards only through here.

	Pure on the save table: the caller calls DataService.changed(player) after
	a change (and does the check + write with no yield in between).
]]

local Shards = {}

Shards.Max = 1e12 -- never more than this in a save

-- The shard balance of a save (broken values count as 0).
function Shards.get(data: { [string]: any }): number
	local n = tonumber(data.Shards) or 0
	if n ~= n or n <= 0 then
		return 0
	end
	return math.floor(math.min(n, Shards.Max))
end

-- Adds `amount` (a whole number > 0) shards. Returns the new balance.
function Shards.add(data: { [string]: any }, amount: number): number
	local balance = Shards.get(data)
	if type(amount) ~= "number" or amount ~= amount or amount < 1 then
		return balance
	end
	data.Shards = math.min(Shards.Max, balance + math.floor(math.min(amount, Shards.Max)))
	return data.Shards
end

-- Takes `amount` (a whole number >= 0) shards when the save has them. Returns true when paid.
function Shards.spend(data: { [string]: any }, amount: number): boolean
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount ~= math.floor(amount) then
		return false
	end
	local balance = Shards.get(data)
	if balance < amount then
		return false
	end
	data.Shards = balance - amount
	return true
end

return Shards
