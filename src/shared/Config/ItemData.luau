--[[
	Item stages, quality grades, anvil recipes and the sell-value formula.
	value = ore.Value * stage multiplier * grade multiplier (* recipe for gear)
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

function ItemData.displayName(kind: string, oreId: string, gradeId: string?, recipeId: string?): string
	local ore = OreData.ById[oreId]
	local oreName = ore and ore.Name or oreId
	if kind == "Raw" then
		return "Raw " .. oreName
	elseif kind == "Clean" then
		return (gradeId or "Rough") .. " " .. oreName
	elseif kind == "Crushed" then
		return "Crushed " .. oreName
	elseif kind == "Ingot" then
		return oreName .. " Ingot"
	elseif kind == "Gear" then
		local recipe = recipeId and ItemData.RecipeById[recipeId]
		return oreName .. " " .. (recipe and recipe.Name or "Gear")
	end
	return oreName
end

return ItemData
