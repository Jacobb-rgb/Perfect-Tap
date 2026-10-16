--[[
	Ore discovery (design v2): dirty ore hides what it is, so an ore counts
	as discovered the first time the player gets it CLEAN (by hand at the
	Cleaning Station or from an Auto Cleaner), not when it is mined.
	mark() records it in data.Discovered and shows the "New ore discovered"
	toast. The caller calls DataService.changed afterwards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)

local Discovery = {}

local callbacks: { (Player, string) -> ...any } = {}

-- Listeners (badges, codex, analytics): (player, oreId) for every new ore.
function Discovery.onDiscovered(callback: (Player, string) -> ...any)
	table.insert(callbacks, callback)
end

-- Returns true when `oreId` was new for this player.
function Discovery.mark(player: Player, data: { [string]: any }, oreId: string): boolean
	local ore = OreData.ById[oreId]
	if not ore then
		return false
	end
	if type(data.Discovered) ~= "table" then
		data.Discovered = {}
	end
	if data.Discovered[oreId] then
		return false
	end
	data.Discovered[oreId] = true
	if player.Parent then
		Net.fire("Notify", player, {
			Text = "New ore discovered: " .. ore.Name .. "!",
			Kind = "Discovery",
			Rarity = ore.Rarity,
		})
	end
	for _, callback in callbacks do
		task.spawn(callback, player, oreId)
	end
	return true
end

return Discovery
