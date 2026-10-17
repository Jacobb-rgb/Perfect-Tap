--[[
	Item stages, quality grades, anvil recipes, the sell-value formula and
	podium income (design v2).
	value = ore.Value * stage multiplier * grade multiplier (* recipe for gear)
	  (ore.Value = ore.Income * OreData.SellSeconds: what Tobin pays)
	income = ore.Income * grade multiplier, for cleaned ore on a podium
	Raw ore is "Dirty Ore": its name and rarity stay hidden until it is cleaned.
]]

local OreData = require(script.Parent.OreData)

local ItemData = {}

-- Physical item kinds, in processing order.
ItemData.Kinds = {
	Raw = { Id = "Raw", Name = "Raw", ValueMult = 0.4 },
	Clean = { Id = "Clean", Name = "Clean", ValueMult = 1.0 },
	Crushed = { Id = "Crushed", Name = "Crushed", ValueMult = 0.75 },
	Ingot = { Id = "Ingot", Name = "Ingot", ValueMult = 1.25 },
	Gear = { Id = "Gear", Name = "Gear", ValueMult = 1.25 }, -- per ingot used, times recipe bonus
	-- Alloy Furnace: two ingots of different ores -> one alloy of the more
	-- valuable ore, worth more than both ingots (2 x 1.25)
	Alloy = { Id = "Alloy", Name = "Alloy", ValueMult = 3.2 },
}

-- Quality grades from the cleaning minigame (index = grade level).
ItemData.Grades = {
	{ Id = "Rough", Name = "Rough", Level = 1, Mult = 1.0, MinScore = 0, Color = Color3.fromRGB(170, 150, 130) },
	{ Id = "Clean", Name = "Clean", Level = 2, Mult = 1.3, MinScore = 0.55, Color = Color3.fromRGB(120, 220, 255) },
	{ Id = "Pristine", Name = "Pristine", Level = 3, Mult = 1.7, MinScore = 0.78, Color = Color3.fromRGB(160, 255, 170) },
	{ Id = "Flawless", Name = "Flawless", Level = 4, Mult = 2.4, MinScore = 0.92, Color = Color3.fromRGB(255, 225, 110) },
}
ItemData.GradeById = {}
for _, grade in ItemData.Grades do
	ItemData.GradeById[grade.Id] = grade
end

-- Anvil recipes. Ingots must all be the same ore; gear grade = lowest input grade.
ItemData.Recipes = {
	{ Id = "Dagger", Name = "Dagger", Ingots = 1, Bonus = 1.5, Hits = 3 },
	{ Id = "ToolHead", Name = "Tool Head", Ingots = 2, Bonus = 1.6, Hits = 4 },
	{ Id = "Helm", Name = "Helm", Ingots = 3, Bonus = 1.7, Hits = 5 },
	{ Id = "Greatsword", Name = "Greatsword", Ingots = 4, Bonus = 1.9, Hits = 6 },
}
ItemData.RecipeById = {}
for _, recipe in ItemData.Recipes do
	ItemData.RecipeById[recipe.Id] = recipe
end

function ItemData.gradeFromScore(score: number): string
	local result = "Rough"
	for _, grade in ItemData.Grades do
		if score >= grade.MinScore then
			result = grade.Id
		end
	end
	return result
end

function ItemData.gradeLevel(gradeId: string?): number
	local grade = gradeId and ItemData.GradeById[gradeId]
	return grade and grade.Level or 1
end

function ItemData.gradeMult(gradeId: string?): number
	local grade = gradeId and ItemData.GradeById[gradeId]
	return grade and grade.Mult or 1
end

-- Sell value of one item. `recipeId` only matters for Gear.
function ItemData.value(kind: string, oreId: string, gradeId: string?, recipeId: string?): number
	local ore = OreData.ById[oreId]
	local kindInfo = ItemData.Kinds[kind]
	if not ore or not kindInfo then
		return 0
	end
	local value = ore.Value * kindInfo.ValueMult
	if kind ~= "Raw" then
		value *= ItemData.gradeMult(gradeId)
	end
	if kind == "Gear" then
		local recipe = recipeId and ItemData.RecipeById[recipeId]
		if not recipe then
			return 0
		end
		value *= recipe.Ingots * recipe.Bonus
	end
	return math.max(1, math.floor(value + 0.5))
end

-- One stored or moving item, as saved in data.Storage and machine queues.
export type Desc = { K: string, O: string, G: string?, R: string? }

local MAX_KEY_LENGTH = 80

-- Storage key "Kind|Ore|Grade|Recipe" (a missing grade or recipe is "").
-- The server, the client and the tests all use this one format.
function ItemData.storageKey(desc: Desc): string
	return `{desc.K}|{desc.O}|{desc.G or ""}|{desc.R or ""}`
end

-- The item a storage key stands for, or nil when the key is junk: too long,
-- an unknown kind, ore, grade or recipe, a Gear without a recipe, or a
-- recipe on something that isn't Gear.
function ItemData.parseKey(key: string): Desc?
	if type(key) ~= "string" or #key > MAX_KEY_LENGTH then
		return nil
	end
	local parts = string.split(key, "|")
	if #parts ~= 4 then
		return nil
	end
	local kind, oreId, gradeId, recipeId = parts[1], parts[2], parts[3], parts[4]
	if not ItemData.Kinds[kind] or not OreData.ById[oreId] then
		return nil
	end
	if gradeId ~= "" and not ItemData.GradeById[gradeId] then
		return nil
	end
	if kind == "Gear" then
		if not ItemData.RecipeById[recipeId] then
			return nil
		end
	elseif recipeId ~= "" then
		return nil
	end
	return {
		K = kind,
		O = oreId,
		G = if gradeId ~= "" then gradeId else nil,
		R = if recipeId ~= "" then recipeId else nil,
	}
end

-- Podium income per second of one item at grade multiplier only (bonuses
-- such as golems or passes are applied by EconomyService). 0 for anything a
-- podium can't hold (only cleaned ore goes on podiums).
function ItemData.income(desc: Desc?): number
	if type(desc) ~= "table" or desc.K ~= "Clean" then
		return 0
	end
	local ore = OreData.ById[desc.O]
	if not ore then
		return 0
	end
	return ore.Income * ItemData.gradeMult(desc.G)
end

ItemData.DirtyName = "Dirty Ore"

-- Name shown to players. Raw ore is always "Dirty Ore" (cleaning reveals it).
function ItemData.displayName(kind: string, oreId: string, gradeId: string?, recipeId: string?): string
	local ore = OreData.ById[oreId]
	local oreName = ore and ore.Name or oreId
	if kind == "Raw" then
		return ItemData.DirtyName
	elseif kind == "Clean" then
		return (gradeId or "Rough") .. " " .. oreName
	elseif kind == "Crushed" then
		return "Crushed " .. oreName
	elseif kind == "Ingot" then
		return oreName .. " Ingot"
	elseif kind == "Gear" then
		local recipe = recipeId and ItemData.RecipeById[recipeId]
		return oreName .. " " .. (recipe and recipe.Name or "Gear")
	elseif kind == "Alloy" then
		return oreName .. " Alloy"
	end
	return oreName
end

return ItemData
