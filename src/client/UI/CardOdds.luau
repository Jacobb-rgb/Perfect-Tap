--[[
	The STORE's odds panel lines (pure: the Lune specs check them).
	  tableLines(tbl)          an odds table (BoostView / EnchantView) as lines:
	                           its title, "Rare or better" and every row as
	                           "now → after", its note
	  enchantLines(state, id, now, soon)  an odds-boosting enchant's change in
	                           every zone the player can mine (EnchantView.odds
	                           per zone; zones without Rare ores only when every
	                           zone is such; the notes once, at the end)
]]

local BoostView = require(script.Parent.BoostView)
local EnchantView = require(script.Parent.EnchantView)

local CardOdds = {}

function CardOdds.tableLines(tbl: BoostView.OddsTable?, withNote: boolean?): { string }
	local lines: { string } = {}
	if not tbl then
		return lines
	end
	table.insert(lines, `{tbl.Title}  ({tbl.BeforeHeader} → {tbl.AfterHeader})`)
	local summary = tbl.Summary
	if summary then
		table.insert(lines, `   {summary.Name}:  {summary.Before}  →  {summary.After}`)
	end
	for _, row in tbl.Rows do
		table.insert(lines, `   {row.Name}:  {row.Before}  →  {row.After}`)
	end
	if withNote ~= false and tbl.Note ~= "" then
		table.insert(lines, tbl.Note)
	end
	return lines
end

-- Does an odds table say the luck changes nothing in its zone (no Rare ores: no
-- "Rare or better" line)?
local function noEffect(tbl: BoostView.OddsTable): boolean
	return tbl.Summary == nil
end

function CardOdds.enchantLines(state: any, id: string, now: number, soon: { [string]: boolean }?): { string }
	local lines: { string } = {}
	local note = ""
	local tables: { BoostView.OddsTable } = {}
	for _, zoneId in EnchantView.zoneIds(state) do
		local tbl = EnchantView.odds(state, id, zoneId, now, soon)
		if tbl then
			table.insert(tables, tbl)
		end
	end
	local useful: { BoostView.OddsTable } = {}
	for _, tbl in tables do
		if not noEffect(tbl) then
			table.insert(useful, tbl)
		end
	end
	if #useful == 0 then
		useful = tables -- every zone without Rare ores: say so once
	end
	for _, tbl in useful do
		for _, line in CardOdds.tableLines(tbl, false) do
			table.insert(lines, line)
		end
		note = tbl.Note
	end
	if note ~= "" then
		table.insert(lines, note)
	end
	return lines
end

return CardOdds
