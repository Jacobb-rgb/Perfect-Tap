--[[
	Fall heights: Roblox deletes anything below Workspace.FallenPartsDestroyHeight
	(default.project.json), a character included. Every mine floor, every elevator
	arrival and the floor 6 void catcher's reach must stay well above it, and the item
	rescue height (GameConfig.ItemFallKillY) must sit below every floor and above it
	(owner's playtest 2026-10-20: floors 5-6 at -300 / -400 killed every rider at -250).
]]
return function(T, Loader)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local process = require("@lune/process")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")

	local MARGIN = 100 -- studs a floor's lowest point keeps above the kill height

	T.test("fall heights: every mine floor, cave and the item rescue stay above the kill height", function()
		local project = serde.decode("json", fs.readFile(process.cwd .. "/default.project.json"))
		local kill = project.tree.Workspace["$properties"].FallenPartsDestroyHeight
		T.truthy(type(kill) == "number", "default.project.json sets Workspace.FallenPartsDestroyHeight")
		local lowest = math.huge
		for i, placement in MineFloors.Placement do
			-- a floor's ground plus the deepest local geometry the floors build (Floor6Core: local y -77)
			local bottom = placement.Position.Y - 80
			T.truthy(bottom > kill + MARGIN, `floor {i} (ground y {placement.Position.Y}) is well above the kill height {kill}`)
			lowest = math.min(lowest, bottom)
		end
		for name, cave in WorldLayout.Caves do
			T.truthy(cave.Min.Y > kill + MARGIN, `{name} (Min.Y {cave.Min.Y}) is well above the kill height {kill}`)
			lowest = math.min(lowest, cave.Min.Y)
		end
		T.truthy(GameConfig.ItemFallKillY < lowest, `items rescue only below the deepest floor ({GameConfig.ItemFallKillY} < {lowest})`)
		T.truthy(GameConfig.ItemFallKillY > kill + 50, `items are rescued before the engine deletes them ({GameConfig.ItemFallKillY} > {kill} + 50)`)
	end)
end
