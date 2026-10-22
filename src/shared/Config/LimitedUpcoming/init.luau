--[[
	UPCOMING limited editions: the sets the owner may launch in later months
	(Galaxy, Mecha Neon, Frost Titans), one module each, for the preview
	pictures. Their golems are NOT real kinds (not in GolemConfig.List, never
	in a save, never sold); GolemBuilder builds their looks from here so the
	costumes and shards can be shown before a launch. To launch one: move its
	golems into GolemConfig.List, add its capsule and products, point
	LimitedGolems.Current at it and drop it from here.

	  Sets       set id -> { Id, Title, Tagline, Backdrop, Golems (Rare,
	             Rare, Epic, Epic, Legendary, Mythic) }
	  ById       golem id -> its look (GolemConfig.Golem, Edition = set id)
]]

local GolemConfig = require(script.Parent.GolemConfig)

export type Set = {
	Id: string,
	Title: string,
	Tagline: string,
	Backdrop: {
		SkyTop: Color3,
		SkyHorizon: Color3,
		Ground: Color3,
		Accent: Color3,
		Title: { Color3 },
	},
	Golems: { GolemConfig.Golem },
}

local LimitedUpcoming = {}

LimitedUpcoming.Order = { "Galaxy", "MechaNeon", "FrostTitans" }
LimitedUpcoming.Sets = {} :: { [string]: Set }
LimitedUpcoming.ById = {} :: { [string]: GolemConfig.Golem }

for _, id in LimitedUpcoming.Order do
	local module = script:FindFirstChild(id)
	if module and module:IsA("ModuleScript") then
		local set = (require :: any)(module) :: Set
		LimitedUpcoming.Sets[id] = set
		for _, golem in set.Golems do
			-- (a launched set's golems are real kinds: GolemConfig wins)
			if GolemConfig.ById[golem.Id] == nil then
				LimitedUpcoming.ById[golem.Id] = golem
			end
		end
	end
end

-- the SKY EGG's proposed golems (preview looks only, SkyEgg.luau): by id, no set
local sky = script:FindFirstChild("SkyEgg")
if sky and sky:IsA("ModuleScript") then
	for _, golem in (require :: any)(sky) :: { GolemConfig.Golem } do
		if GolemConfig.ById[golem.Id] == nil then
			LimitedUpcoming.ById[golem.Id] = golem
		end
	end
end

return LimitedUpcoming
