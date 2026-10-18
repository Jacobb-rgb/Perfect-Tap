--[[
	Every Robux item of the game, in one place (docs/COMPLIANCE.md,
	roblox-rules skill). Other configs only name an entry by its key
	(HoverboardData: PassKey = "HoverboardComet").

	Two kinds:
	  "GamePass"  bought once, owned forever (the owner can't sell it twice and
	              Roblox refunds go through it): MonetizationService checks
	              MarketplaceService:UserOwnsGamePassAsync every time a save
	              loads and on PromptGamePassPurchaseFinished, then calls the
	              pass handler of the entry's Grant (registerPass): grant when
	              owned, revoke what the pass granted when Roblox says "not owned"
	  "Product"   a developer product, bought again and again: granted by
	              MonetizationService's one ProcessReceipt callback through the
	              handler of the entry's Grant (register)
	Id = 0 means the owner hasn't created the item yet: it is never prompted
	(canPrompt is false), never checked and no receipt / purchase matches it;
	the shop shows "Coming soon".

	TODO(owner): create the game passes on the Creator Dashboard under
	Monetization -> Passes (name, picture, 49 R$ each, "Item for sale" on),
	then write each pass id below. Developer products (none yet) go under
	Monetization -> Developer Products.

	Grant -> handler:
	  "Hoverboard"  owns the board BoardId (HoverboardService)
]]

local MonetizationConfig = {}

export type Kind = "GamePass" | "Product"

export type Entry = {
	Key: string, -- the table key below (filled in)
	Kind: Kind,
	Id: number, -- pass / product id; 0 = not created yet (never prompted, never matched)
	Robux: number, -- the price set on the dashboard (shown on buttons)
	Name: string, -- the name on the dashboard
	Description: string?,
	Grant: string, -- which handler gives it (MonetizationService.register / registerPass)
	BoardId: string?, -- Grant "Hoverboard": the HoverboardData id it unlocks
}

MonetizationConfig.Entries = {
	-- TODO(owner): game pass "Neon Comet Hoverboard", 49 R$
	HoverboardComet = {
		Kind = "GamePass",
		Id = 0,
		Robux = 49,
		Name = "Neon Comet Hoverboard",
		Description = "The Neon Comet hoverboard: speed 35, no carry slowdown, a trail of stars.",
		Grant = "Hoverboard",
		BoardId = "NeonComet",
	},
	-- TODO(owner): game pass "Royal Phoenix Hoverboard", 49 R$
	HoverboardPhoenix = {
		Kind = "GamePass",
		Id = 0,
		Robux = 49,
		Name = "Royal Phoenix Hoverboard",
		Description = "The fastest hoverboard: speed 38, no carry slowdown, golden wings and a flame trail.",
		Grant = "Hoverboard",
		BoardId = "RoyalPhoenix",
	},
} :: { [string]: Entry }

for key, entry in MonetizationConfig.Entries do
	entry.Key = key
end

-- True for a real dashboard id (a whole number > 0); 0, junk and NaN are not.
function MonetizationConfig.isLive(id: any): boolean
	return type(id) == "number" and id == id and id > 0 and id == math.floor(id) and id < 2 ^ 53
end

-- The entry for a key, or nil.
function MonetizationConfig.get(key: any): Entry?
	if type(key) ~= "string" or #key > 64 then
		return nil
	end
	return MonetizationConfig.Entries[key]
end

-- True once the owner has written a real id for the entry (only then it may be prompted).
function MonetizationConfig.canPrompt(key: any): boolean
	local entry = MonetizationConfig.get(key)
	return entry ~= nil and MonetizationConfig.isLive(entry.Id)
end

-- The entry with this id (of this kind, when given), or nil (0, junk and unknown ids never match).
function MonetizationConfig.byId(id: any, kind: Kind?): Entry?
	if not MonetizationConfig.isLive(id) then
		return nil
	end
	for _, entry in MonetizationConfig.Entries do
		if entry.Id == id and (kind == nil or entry.Kind == kind) then
			return entry
		end
	end
	return nil
end

-- Every entry of a kind, sorted by key (a stable order for checks and tests).
function MonetizationConfig.list(kind: Kind): { Entry }
	local out: { Entry } = {}
	for _, entry in MonetizationConfig.Entries do
		if entry.Kind == kind then
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a: Entry, b: Entry): boolean
		return a.Key < b.Key
	end)
	return out
end

return MonetizationConfig
