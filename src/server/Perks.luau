--[[
	Game pass perks as player attributes (readable by the client for UI,
	but only the server can set them). MonetizationService sets them when a
	player owns or buys a pass.
	Perk ids: "StrongBack" (2x carry), "ForgeVip" (Glimmer Grotto), "Workshop" (extra slots),
	"Podiums" (podiums 3 and 4), "OfflineExtension" (offline earnings for 12 h instead of 5),
	"TrainExpress" (step 2). The big pass grants Podiums + OfflineExtension + more.
]]

local Perks = {}

function Perks.has(player: Player, perkId: string): boolean
	return player:GetAttribute("Perk_" .. perkId) == true
end

function Perks.set(player: Player, perkId: string, owned: boolean)
	player:SetAttribute("Perk_" .. perkId, if owned then true else nil)
end

return Perks
