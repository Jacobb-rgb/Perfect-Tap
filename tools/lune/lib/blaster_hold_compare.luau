--[[
	Preview scene "blaster_hold_compare" (tools/lune/export_scene.luau): the
	world with miners on the plaza holding blasters, BEFORE (the classic
	in-game guns, BlasterBuilder.buildClassic) next to AFTER (the Kenney
	shapes, BlasterBuilder.build), at levels 3, 7 and 10; and one miner per
	style blasting a rock in the quarry. Shots:
	tools/preview/blaster_hold_compare_shots.json (PC and phone framings).
]]

local roblox = require("@lune/roblox") :: any

local Compare = {}

function Compare.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local Gallery = require("./blaster_gallery")
	local Concepts = require("./blaster_concepts")
	WorldBuilder.build(parent)
	local root = roblox.Instance.new("Model")
	root.Name = "BlasterHoldCompare"
	root.Parent = parent
	local newBuild = BlasterBuilder.build
	local AIM = V3.new(1, 0, 0.3).Unit -- the guns point right, the camera sees their right side
	local function holder(feet: any, level: number, classic: boolean, outfit: number)
		-- forgekeeper builds with BlasterBuilder.build: point it at the classic builder for the BEFORE miners
		BlasterBuilder.build = if classic then BlasterBuilder.buildClassic else newBuild
		local ok, err = pcall(function()
			Gallery.forgekeeper(
				Loader,
				root,
				CF.lookAt(feet, feet + AIM),
				feet + AIM * 12 + V3.new(0, 3.6, 0),
				level,
				BlasterData.vaultOre(level),
				Concepts.Outfits[outfit]
			)
		end)
		BlasterBuilder.build = newBuild
		if not ok then
			error(err)
		end
	end
	-- three pairs on the plaza: BEFORE on the left, AFTER on the right
	for i, level in { 3, 7, 10 } do
		local x = -27 + (i - 1) * 19
		holder(V3.new(x, 0, 24), level, true, 1 + (i - 1) % 3)
		holder(V3.new(x + 8.5, 0, 24), level, false, 1 + i % 3)
	end
	return root
end

return Compare
