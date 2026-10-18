--[[
	Every Robux product id of the game, in one place (docs/COMPLIANCE.md,
	roblox-rules skill). Other configs only name a product by its key
	(HoverboardData: ProductKey = "HoverboardComet").

	Developer products (bought again and again, granted by
	MonetizationService's one ProcessReceipt callback):
	  Id = 0 means the owner hasn't created the product yet. Such a product is
	  never prompted (MonetizationConfig.canPrompt is false) and no receipt can
	  match it; the shop shows "Coming soon".
	TODO(owner): create each product on the Creator Dashboard (Monetization ->
	Developer Products) with the name and price below, then write its id here.

	Kind picks the grant handler (MonetizationService.register(Kind, grant)):
	  "Hoverboard"  owns the board BoardId (HoverboardService)
]]

local MonetizationConfig = {}

export type Kind = "Hoverboard"

export type Product = {
	Key: string, -- the table key below (filled in)
	Id: number, -- developer product id; 0 = not created yet (never prompted)
	Robux: number, -- the price set on the dashboard (shown on buttons)
	Kind: Kind,
	Name: string, -- the product name on the dashboard
	BoardId: string?, -- Kind "Hoverboard": the HoverboardData id it grants
}

MonetizationConfig.Products = {
	-- TODO(owner): developer product "Neon Comet Hoverboard", 49 R$
	HoverboardComet = { Id = 0, Robux = 49, Kind = "Hoverboard", Name = "Neon Comet Hoverboard", BoardId = "NeonComet" },
	-- TODO(owner): developer product "Royal Phoenix Hoverboard", 49 R$
	HoverboardPhoenix = { Id = 0, Robux = 49, Kind = "Hoverboard", Name = "Royal Phoenix Hoverboard", BoardId = "RoyalPhoenix" },
} :: { [string]: Product }

for key, product in MonetizationConfig.Products do
	product.Key = key
end

local function wholeId(id: any): number?
	if type(id) ~= "number" or id ~= id or id <= 0 or id ~= math.floor(id) or id >= 2 ^ 53 then
		return nil
	end
	return id
end

-- The product for a key, or nil.
function MonetizationConfig.get(key: any): Product?
	if type(key) ~= "string" or #key > 64 then
		return nil
	end
	return MonetizationConfig.Products[key]
end

-- True once the owner has written a real id for the product (only then it may be prompted).
function MonetizationConfig.canPrompt(key: any): boolean
	local product = MonetizationConfig.get(key)
	return product ~= nil and wholeId(product.Id) ~= nil
end

-- The product a receipt's ProductId belongs to, or nil (0, junk and unknown ids never match).
function MonetizationConfig.byId(id: any): Product?
	local whole = wholeId(id)
	if not whole then
		return nil
	end
	for _, product in MonetizationConfig.Products do
		if product.Id == whole then
			return product
		end
	end
	return nil
end

return MonetizationConfig
