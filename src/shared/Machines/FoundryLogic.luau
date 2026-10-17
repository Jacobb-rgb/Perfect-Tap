--[[
	FoundryLogic: the pure rules of the Foundry (ingots -> blasters), shared
	by FoundryService (server, the truth) and FoundryView (client preview).
	No services, no instances: the Lune tests run it directly.

	The rules (docs/plans/STEP3_PLAN.md, GameConfig "Foundry"):
	  - The next blaster level is BlasterData.Levels[current + 1]; its Recipe
	    needs Recipe.Ingots ingots of rarity Recipe.MinRarity or better, plus
	    Recipe.Coins. Level 11 is "Coming soon" (no recipe).
	  - An ingot is "usable" when the next level's recipe takes it (an Ingot
	    of a known ore whose rarity is at least MinRarity).
	  - Forging uses exactly Recipe.Ingots usable ingots: ONE ingot of the
	    skin ore (its lowest-value one) plus the lowest-value other usable
	    ingots (ItemData.value ascending, ties in stock order), so the best
	    ones stay. The default skin is the ore of the most valuable usable
	    ingot (ties: the first in stock order).
	  - After a forge, stock ingots the NEW next level can't use go to the
	    Ore Pen (unusable()).
	  - Hammer taps: hits(level) for forging that level.
]]

local BlasterData = require(script.Parent.Parent.Config.BlasterData)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local ItemData = require(script.Parent.Parent.Config.ItemData)
local OreData = require(script.Parent.Parent.Config.OreData)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local FoundryLogic = {}

export type Desc = ItemData.Desc
export type Refusal = "MaxLevel" | "NotEnough" | "BadOre"

-- Hammer taps to forge blaster level `level` (the level being made): 4 for
-- level 2 up to 8 for level 10.
function FoundryLogic.hits(level: any): number
	local n = if type(level) == "number" and level == level then math.floor(level) else 2
	return math.clamp(3 + math.ceil(n / 2), 4, 8)
end

-- The saved blaster level as a whole number 1..MaxLevel.
function FoundryLogic.level(level: any): number
	return BlasterData.get(level).Level
end

-- The blaster after `level` (level 11 = the "Coming soon" entry).
function FoundryLogic.nextBlaster(level: any): BlasterData.Blaster
	local current = FoundryLogic.level(level)
	return BlasterData.Levels[current + 1] or BlasterData.Levels[#BlasterData.Levels]
end

-- The recipe of the next level, nil when the blaster is at its top level.
function FoundryLogic.recipe(level: any): BlasterData.Recipe?
	local current = FoundryLogic.level(level)
	if current >= BlasterData.MaxLevel then
		return nil
	end
	local nextLevel = BlasterData.ByLevel[current + 1]
	return nextLevel and nextLevel.Recipe
end

-- A well-formed ingot descriptor (known ore, known or no grade, no recipe).
function FoundryLogic.isIngot(desc: any): boolean
	if type(desc) ~= "table" or desc.K ~= "Ingot" or type(desc.O) ~= "string" or not OreData.ById[desc.O] then
		return false
	end
	if desc.G ~= nil and (type(desc.G) ~= "string" or not ItemData.GradeById[desc.G]) then
		return false
	end
	return desc.R == nil
end

-- Does the next level's recipe take this item?
function FoundryLogic.usable(desc: any, level: any): boolean
	local recipe = FoundryLogic.recipe(level)
	if not recipe or not FoundryLogic.isIngot(desc) then
		return false
	end
	local ore = OreData.ById[desc.O]
	local rarity = Rarity.ById[ore.Rarity]
	local needed = Rarity.ById[recipe.MinRarity]
	return rarity ~= nil and needed ~= nil and rarity.Order >= needed.Order
end

-- Sell value of an ingot (the forge's "lowest-value first" order).
function FoundryLogic.value(desc: Desc): number
	return ItemData.value("Ingot", desc.O, desc.G)
end

-- How many stock items the next level can use.
function FoundryLogic.usableCount(stock: { any }, level: any): number
	local n = 0
	for _, desc in stock do
		if FoundryLogic.usable(desc, level) then
			n += 1
		end
	end
	return n
end

--[[
	The ores a new blaster may take its look from: every ore among the usable
	stock ingots, the one with the most valuable ingot first (ties: the one
	whose best ingot comes first in the stock). skins(...)[1] is the default.
]]
function FoundryLogic.skins(stock: { any }, level: any): { string }
	local best: { [string]: { Value: number, Index: number } } = {}
	local list: { string } = {}
	for index, desc in stock do
		if FoundryLogic.usable(desc, level) then
			local value = FoundryLogic.value(desc)
			local entry = best[desc.O]
			if not entry then
				best[desc.O] = { Value = value, Index = index }
				table.insert(list, desc.O)
			elseif value > entry.Value then
				entry.Value = value
				entry.Index = index
			end
		end
	end
	table.sort(list, function(a: string, b: string): boolean
		local ea, eb = best[a], best[b]
		if ea.Value ~= eb.Value then
			return ea.Value > eb.Value
		end
		return ea.Index < eb.Index
	end)
	return list
end

-- The default skin: the ore of the most valuable usable ingot (nil when none).
function FoundryLogic.defaultSkin(stock: { any }, level: any): string?
	return FoundryLogic.skins(stock, level)[1]
end

--[[
	The stock indices a forge of the next level uses: the skin ore's
	lowest-value ingot first, then the lowest-value other usable ingots,
	value ascending, ties in stock order. `skin` nil = the default skin.
	Refusals: "MaxLevel" (no next recipe), "NotEnough" (fewer usable ingots
	than the recipe needs), "BadOre" (the skin isn't an ore among the usable
	ingots).
]]
function FoundryLogic.pick(stock: { any }, level: any, skin: string?): ({ number }?, Refusal?)
	local recipe = FoundryLogic.recipe(level)
	if not recipe then
		return nil, "MaxLevel"
	end
	local usable: { number } = {}
	for index, desc in stock do
		if FoundryLogic.usable(desc, level) then
			table.insert(usable, index)
		end
	end
	if #usable < recipe.Ingots then
		return nil, "NotEnough"
	end
	local ore = skin or FoundryLogic.defaultSkin(stock, level)
	local values: { [number]: number } = {}
	for _, index in usable do
		values[index] = FoundryLogic.value(stock[index])
	end
	table.sort(usable, function(a: number, b: number): boolean
		if values[a] ~= values[b] then
			return values[a] < values[b]
		end
		return a < b
	end)
	local skinIndex: number? = nil
	for _, index in usable do
		if stock[index].O == ore then
			skinIndex = index
			break
		end
	end
	if not skinIndex then
		return nil, "BadOre"
	end
	local picked = { skinIndex }
	for _, index in usable do
		if #picked >= recipe.Ingots then
			break
		end
		if index ~= skinIndex then
			table.insert(picked, index)
		end
	end
	return picked, nil
end

-- Stock indices (ascending) of items the next level of `level` can't use.
function FoundryLogic.unusable(stock: { any }, level: any): { number }
	local list = {}
	for index, desc in stock do
		if not FoundryLogic.usable(desc, level) then
			table.insert(list, index)
		end
	end
	return list
end

-- A stock list from a State summary ("Ingot|O|G|" -> count), sorted by key so
-- the client's preview is stable (at most GameConfig.MaxFoundryStock items).
function FoundryLogic.fromSummary(summary: any): { Desc }
	local list: { Desc } = {}
	if type(summary) ~= "table" then
		return list
	end
	local keys: { string } = {}
	for key, count in summary do
		if type(key) == "string" and type(count) == "number" and count >= 1 and count == count then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	for _, key in keys do
		local desc = ItemData.parseKey(key)
		if desc and FoundryLogic.isIngot(desc) then
			for _ = 1, math.min(math.floor(summary[key]), GameConfig.MaxFoundryStock) do
				if #list >= GameConfig.MaxFoundryStock then
					return list
				end
				table.insert(list, { K = desc.K, O = desc.O, G = desc.G })
			end
		end
	end
	return list
end

export type Status = {
	Level: number, -- the level being made next (11 = coming soon)
	Blaster: BlasterData.Blaster,
	Recipe: BlasterData.Recipe?,
	Have: number, -- usable ingots in the stock
	Need: number, -- ingots the recipe needs (0 at the top level)
	Coins: number, -- the recipe's coins
	CoinsOk: boolean,
	Skin: string?, -- the look the forge would use
	Skins: { string }, -- the looks to choose from
	Uses: { number }?, -- stock indices the forge would use
	Ready: boolean,
	Reason: "MaxLevel" | "NeedIngots" | "NeedCoins" | nil,
}

-- Everything the Foundry panel shows about the next level. `skin` is the
-- player's choice (ignored when it isn't one of the possible looks).
function FoundryLogic.status(stock: { any }, level: any, coins: any, skin: string?): Status
	local blaster = FoundryLogic.nextBlaster(level)
	local recipe = FoundryLogic.recipe(level)
	local balance = if type(coins) == "number" and coins == coins then coins else 0
	local skins = FoundryLogic.skins(stock, level)
	local chosen = if skin and table.find(skins, skin) then skin else skins[1]
	local status: Status = {
		Level = blaster.Level,
		Blaster = blaster,
		Recipe = recipe,
		Have = FoundryLogic.usableCount(stock, level),
		Need = if recipe then recipe.Ingots else 0,
		Coins = if recipe then recipe.Coins else 0,
		CoinsOk = recipe ~= nil and balance >= recipe.Coins,
		Skin = chosen,
		Skins = skins,
		Uses = nil,
		Ready = false,
		Reason = nil,
	}
	if not recipe then
		status.Reason = "MaxLevel"
		return status
	end
	status.Uses = FoundryLogic.pick(stock, level, chosen)
	if status.Have < recipe.Ingots then
		status.Reason = "NeedIngots"
	elseif not status.CoinsOk then
		status.Reason = "NeedCoins"
	else
		status.Ready = status.Uses ~= nil
	end
	return status
end

return FoundryLogic
