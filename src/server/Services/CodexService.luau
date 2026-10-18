--[[
	CodexService: the ORE CODEX's "seen" record, so its NEW badges survive
	sessions (an ore discovered right before leaving still shows NEW next
	time). data.OreCodex = { Seen = { [oreId] = true }, Ready = boolean }.

	- On load prepare() makes the record whole: Seen keeps only discovered
	  ores of OreData; a save made before the record existed (Ready false)
	  takes the ores it has already discovered as seen, once (no flood of NEW
	  badges for old saves).
	- CodexSeen (Net, rate limited): { oreId, ... } the ores the player just
	  looked at (the codex closed with NEW badges). Only discovered ores of
	  OreData go in; DataService.changed when something did. Nothing else in
	  the save can change here.
	- The snapshot carries snapshot.CodexSeen = Seen; the client's NEW
	  badges are the discovered ores that aren't in it
	  (CodexController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

local CodexService = {}

export type Record = { Seen: { [string]: boolean }, Ready: boolean }

CodexService.MaxIds = #OreData.List + 5 -- a request names at most this many ores
CodexService.MaxIdLength = 40

local function discovered(data: { [string]: any }): { [any]: any }
	return if type(data.Discovered) == "table" then data.Discovered else {}
end

-- The save's record, whole and clean (made on a save that has none or a
-- broken one; an old save's discovered ores count as seen).
function CodexService.prepare(data: { [string]: any }): Record
	local raw = data.OreCodex
	local found = discovered(data)
	local seen: { [string]: boolean } = {}
	local ready = false
	if type(raw) == "table" then
		ready = raw.Ready == true
		if type(raw.Seen) == "table" then
			for oreId, on in raw.Seen do
				if on == true and type(oreId) == "string" and OreData.ById[oreId] and found[oreId] == true then
					seen[oreId] = true
				end
			end
		end
	end
	if not ready then
		-- a save from before the record: what it found so far was seen
		for oreId, on in found do
			if on == true and type(oreId) == "string" and OreData.ById[oreId] then
				seen[oreId] = true
			end
		end
	end
	local record: Record = { Seen = seen, Ready = true }
	data.OreCodex = record
	return record
end

-- A client's CodexSeen request. Returns how many ores became seen.
function CodexService.markSeen(player: Player, raw: any): number
	local data = DataService.get(player)
	if not data or not Guard.table(raw, CodexService.MaxIds) then
		return 0
	end
	local record = data.OreCodex
	if type(record) ~= "table" or type(record.Seen) ~= "table" then
		record = CodexService.prepare(data)
	end
	local seen = record.Seen
	local found = discovered(data)
	local added = 0
	for _, value in raw do
		local oreId = Guard.string(value, CodexService.MaxIdLength)
		if oreId and OreData.ById[oreId] and found[oreId] == true and seen[oreId] ~= true then
			seen[oreId] = true
			added += 1
		end
	end
	if added > 0 then
		DataService.changed(player)
	end
	return added
end

function CodexService.init()
	DataService.onLoaded(function(_player: Player, data: { [string]: any })
		CodexService.prepare(data)
	end)
	StateService.addProvider(function(_player: Player, data: { [string]: any }, snapshot: { [string]: any })
		local record = data.OreCodex
		snapshot.CodexSeen = if type(record) == "table" and type(record.Seen) == "table" then record.Seen else {}
	end)
	Net.on("CodexSeen", function(player: Player, raw: any)
		CodexService.markSeen(player, raw)
	end)
end

return CodexService
