--[[
	NightShiftConfig: Night Shift (owner 2026-11-07, his picture
	obrazky/napady_obrazky_2026-10-30/05_nocni_smena.jpg, golems later). While
	the player is away the base keeps working at EconomyConfig.Offline's rate:
	the podiums earn (PodiumService), the machines finish ore from the pen
	(Machines/NightShiftLine), and a long enough absence earns a free crate.
	NightShiftService runs it, UI/NightShiftView shows it on return.

	The crate is a random reward: its chances (Odds) are shown on it in the
	window. It can't be bought and no luck changes it.
]]

local MineFloors = require(script.Parent.MineFloors)

local NightShiftConfig = {}

NightShiftConfig.Crate = {
	MinAway = 3600, -- seconds away that earn one
	Every = 20 * 3600, -- seconds between two earned crates ("free every night": a little under a day)
	CoinSeconds = 600, -- Coins: seconds of the player's podium income...
	CoinMin = 2500, -- ...at least this many coins
	OreCount = 3, -- Ores: this many dirty ores from the player's deepest floor
}

NightShiftConfig.Odds = {
	{ Id = "Coins", Chance = 0.7, Text = "Coins" },
	{ Id = "Ores", Chance = 0.25, Text = "3 dirty ores" },
	{ Id = "Relic", Chance = 0.05, Text = "A relic" },
}

-- The prize of a roll in [0, 1).
function NightShiftConfig.pick(roll: number): string
	local walked = 0
	for _, line in NightShiftConfig.Odds do
		walked += line.Chance
		if roll < walked then
			return line.Id
		end
	end
	return NightShiftConfig.Odds[1].Id
end

-- "Coins 70% · 3 dirty ores 25% · A relic 5%"
function NightShiftConfig.oddsText(): string
	local parts = {}
	for _, line in NightShiftConfig.Odds do
		table.insert(parts, `{line.Text} {math.floor(line.Chance * 100 + 0.5)}%`)
	end
	return table.concat(parts, " · ")
end

-- Does this absence earn a crate? (`record` = data.NightShift)
function NightShiftConfig.earnsCrate(record: { [string]: any }, away: number, now: number): boolean
	local crate = NightShiftConfig.Crate
	return record.Ready ~= true and away >= crate.MinAway and now - (tonumber(record.CrateAt) or 0) >= crate.Every
end

function NightShiftConfig.coins(income: number): number
	local crate = NightShiftConfig.Crate
	local safe = if type(income) == "number" and income == income and income > 0 then income else 0
	return math.floor(math.max(safe * crate.CoinSeconds, crate.CoinMin))
end

-- The deepest floor a blaster of this level can mine.
function NightShiftConfig.floorFor(level: number): MineFloors.Floor
	local best = MineFloors.List[1]
	for _, floor in MineFloors.List do
		if floor.MinBlaster <= level and floor.Index > best.Index then
			best = floor
		end
	end
	return best
end

-- One ore of the floor's table for a roll in [0, 1) (by weight; a fixed order).
function NightShiftConfig.pickOre(floor: MineFloors.Floor, roll: number): string
	local ids = {}
	local total = 0
	for id, weight in floor.Ores do
		table.insert(ids, id)
		total += weight
	end
	table.sort(ids)
	local walked = 0
	for _, id in ids do
		walked += floor.Ores[id] / total
		if roll < walked then
			return id
		end
	end
	return ids[#ids]
end

return NightShiftConfig
