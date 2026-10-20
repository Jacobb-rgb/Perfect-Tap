--[[
	Badges (V2_PLAN step 8). Each badge is a real achievement read from the
	player's save data (DataService), never a reward for liking, favouriting,
	joining a group or playing with friends (docs/COMPLIANCE.md).

	Id = the badge's id from the Creator Dashboard; 0 = not created yet: the
	badge is skipped (never checked, never awarded). How to create the badges
	and paste the ids: docs/handoff/ODZNAKY_NAVOD.md (Czech, for the owner).
	Roblox gives 5 free badge creations per game per day: create them over a
	few days (Order is the suggested order).

	BadgeService awards a badge once its Check(data) is true and remembers it
	in data.Badges[Key] (a cache: Roblox is the source of truth).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local OreData = require(Shared.Config.OreData)

export type Badge = {
	Key: string, -- stable key (data.Badges[Key]); never rename once live
	Id: number, -- Creator Dashboard badge id; 0 = skip
	Name: string, -- the name to give it on the dashboard
	Description: string, -- the description to give it on the dashboard
	Check: ({ [string]: any }) -> boolean,
}

local BadgeConfig = {}

local function stat(data: { [string]: any }, name: string): number
	local stats = data.Stats
	local v = if type(stats) == "table" then stats[name] else nil
	return if type(v) == "number" then v else 0
end

local function number(data: { [string]: any }, name: string): number
	local v = data[name]
	return if type(v) == "number" then v else 0
end

-- Has the player discovered (cleaned) an ore of this rarity?
local function discovered(data: { [string]: any }, rarity: string): boolean
	local seen = data.Discovered
	if type(seen) ~= "table" then
		return false
	end
	for oreId, yes in seen do
		if yes and type(oreId) == "string" and OreData.exists(oreId) and OreData.get(oreId).Rarity == rarity then
			return true
		end
	end
	return false
end

local function discoveredCount(data: { [string]: any }): number
	local seen = data.Discovered
	local n = 0
	if type(seen) == "table" then
		for oreId, yes in seen do
			if yes and type(oreId) == "string" and OreData.exists(oreId) then
				n += 1
			end
		end
	end
	return n
end

-- TODO(owner): paste the badge ids from the Creator Dashboard (docs/handoff/ODZNAKY_NAVOD.md)
BadgeConfig.List = {
	{
		Key = "FirstOre",
		Id = 0,
		Name = "First Ore",
		Description = "Blast your first ore out of the rock.",
		Check = function(data)
			return stat(data, "OresMined") >= 1
		end,
	},
	{
		Key = "FirstClean",
		Id = 0,
		Name = "Fresh From the Rock",
		Description = "Clean your first ore at the Cleaning Station.",
		Check = function(data)
			return stat(data, "OresCleaned") >= 1
		end,
	},
	{
		Key = "TutorialDone",
		Id = 0,
		Name = "Forgekeeper",
		Description = "Finish the tutorial.",
		Check = function(data)
			local tutorial = data.Tutorial
			return type(tutorial) == "table" and tutorial.Done == true
		end,
	},
	{
		Key = "FirstFlawless",
		Id = 0,
		Name = "Flawless",
		Description = "Clean an ore to the Flawless grade.",
		Check = function(data)
			return stat(data, "FlawlessCleans") >= 1
		end,
	},
	{
		Key = "FirstBlaster",
		Id = 0,
		Name = "Blastsmith",
		Description = "Forge your first new blaster.",
		Check = function(data)
			return stat(data, "BlastersForged") >= 1 or number(data, "BlasterLevel") >= 2
		end,
	},
	{
		Key = "FirstLegendary",
		Id = 0,
		Name = "Legend Found",
		Description = "Discover a Legendary ore.",
		Check = function(data)
			return discovered(data, "Legendary")
		end,
	},
	{
		Key = "FirstMythic",
		Id = 0,
		Name = "Mythic Find",
		Description = "Discover a Mythic ore.",
		Check = function(data)
			return discovered(data, "Mythic")
		end,
	},
	{
		Key = "Collector",
		Id = 0,
		Name = "Ore Collector",
		Description = "Discover 15 different ores.",
		Check = function(data)
			return discoveredCount(data) >= 15
		end,
	},
	{
		Key = "TrainMaster",
		Id = 0,
		Name = "All Aboard",
		Description = "Bring 25 ore trains home.",
		Check = function(data)
			return stat(data, "TrainTrips") >= 25
		end,
	},
	{
		Key = "Tycoon",
		Id = 0,
		Name = "Tycoon",
		Description = "Earn 1,000,000 coins in total.",
		Check = function(data)
			return number(data, "TotalEarned") >= 1e6
		end,
	},
	{
		Key = "MaxBlaster",
		Id = 0,
		Name = "Ultimate Blaster",
		Description = "Reach blaster level 10.",
		Check = function(data)
			return number(data, "BlasterLevel") >= 10
		end,
	},
	-- (steps 6-7 badges go here at their merge: first golem, first capsule,
	-- a wheel spin, the first artifact; same shape, Id = 0 until created)
} :: { Badge }

BadgeConfig.ByKey = {} :: { [string]: Badge }
for _, badge in BadgeConfig.List do
	assert(BadgeConfig.ByKey[badge.Key] == nil, "duplicate badge key " .. badge.Key)
	BadgeConfig.ByKey[badge.Key] = badge
end

-- The keys of the badges `data` has earned that have a real id and are not
-- in data.Badges yet (pure: BadgeService and the tests use it).
function BadgeConfig.due(data: { [string]: any }): { string }
	local owned = if type(data.Badges) == "table" then data.Badges else {}
	local out: { string } = {}
	for _, badge in BadgeConfig.List do
		if badge.Id > 0 and not owned[badge.Key] then
			local ok, earned = pcall(badge.Check, data)
			if ok and earned == true then
				table.insert(out, badge.Key)
			end
		end
	end
	return out
end

return BadgeConfig
