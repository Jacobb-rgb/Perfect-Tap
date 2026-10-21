--[[
	StoreService: the Robux STORE window's buys (StoreController, owner
	2026-10-20). It only PROMPTS: the one ProcessReceipt and every grant stay
	in MonetizationService (register / registerPass handlers).

	StoreAction ("Buy", { Key }) -> PurchasePrompt { Product = Key, Status }
	(MonetizationConfig.promptStatus through the receipts gate, then
	MarketplaceService's prompt via BoostService.promptPurchase). Key must be
	a product the Store sells (StoreConfig.sells), else "Unknown".
	By the product's Grant:
	  Capsule, Boost  bought through their own services' requests by the
	                  client (CapsuleAction "Open" / BoostAction "BuyRobux"),
	                  so the odds the player saw are the odds they get
	                  (CapsuleService remembers Triple Lucky at "Prompted")
	                  and "Full" follows the boost cap: answered "Unknown" here
	  Enchant         the Mythic's game pass: EnchantService.buy validates
	                  (owned tier, policy) and answers "Robux" for a valid buy
	  BlasterLevel    "Full" unless the band holds the player's next level
	                  (VaultService.paidStatus when present, else the same
	                  rule here)
	  ServerBoost     "Full" when it would pass ServerBoostService.MaxSeconds
	  RebirthWeapon   a STAR blaster's pass: "Full" until the player's rebirths
	                  reach it (StarBlasterData.unlocked), "Owned" once owned
	  StarterPack     once per account (StarterPackService.promptState):
	                  "Owned" once bought, "Unknown" when the offer is over
	  Perks, Hoverboard (passes), CoinPack: promptStatus with owns()
	Paid random products read the player's policy first (it may yield).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local StoreConfig = require(Shared.Config.StoreConfig)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local BoostService = require(script.Parent.BoostService)

local StoreService = {}

local MAX_PAYLOAD = 4
local MAX_KEY = 40

local function answer(player: Player, key: string, status: string)
	Net.fire("PurchasePrompt", player, { Product = key, Status = status })
end

-- "Full" unless the price band of `entry` holds the player's next blaster level.
function StoreService.blasterStatus(data: any, entry: MonetizationConfig.Product): string
	local services = script.Parent
	local vault = services:FindFirstChild("VaultService")
	if vault then
		local ok, status = pcall(function()
			local VaultService = require(vault) :: any
			if type(VaultService.paidStatus) == "function" then
				return VaultService.paidStatus(data, entry)
			end
			return nil
		end)
		if ok and type(status) == "string" then
			return status
		end
	end
	local level = if type(data) == "table" and type(data.BlasterLevel) == "number" then math.floor(data.BlasterLevel) else 1
	local nextLevel = level + 1
	if level >= BlasterData.MaxLevel or nextLevel < (entry.MinLevel or 2) or nextLevel > (entry.MaxLevel or BlasterData.MaxLevel) then
		return "Full"
	end
	return "Prompt"
end

-- The Mythic enchant behind a pass key (nil for other products).
local function enchantOf(key: string): string?
	for id, enchant in EnchantConfig.ById do
		if enchant.Product == key then
			return id
		end
	end
	return nil
end

local function buyEnchant(player: Player, key: string, data: any)
	local id = enchantOf(key)
	if not id then
		answer(player, key, "Unknown")
		return
	end
	local EnchantService = require(script.Parent.EnchantService) :: any
	local tier = EnchantConfig.tierOf(data.Enchants, id) + 1
	local _, reason = EnchantService.buy(player, id, "Robux", tier)
	if reason == "Robux" then
		BoostService.promptPurchase(player, key, false, false)
		return
	end
	answer(player, key, if reason == "Restricted" then "Restricted" elseif reason == "Max" or reason == "Stale" then "Owned" else "Unknown")
end

-- StoreAction "Buy" { Key }.
function StoreService.buy(player: Player, key: string)
	local product = MonetizationConfig.get(key)
	local data = DataService.get(player)
	if not product or not data or not StoreConfig.sells(key) then
		answer(player, key, "Unknown")
		return
	end
	local grant = product.Grant
	if grant == "Capsule" or grant == "Boost" then
		answer(player, key, "Unknown") -- (the client asks CapsuleService / BoostService)
		return
	end
	if grant == "Enchant" then
		buyEnchant(player, key, data)
		return
	end
	local full = false
	local owned = product.Kind == "GamePass" and MonetizationService.owns(player, key)
	if grant == "StarterPack" then
		local StarterPackService = require(script.Parent.StarterPackService) :: any
		local offer = StarterPackService.promptState(data)
		if offer == "Over" then
			answer(player, key, "Unknown")
			return
		end
		owned = offer == "Owned"
	elseif grant == "BlasterLevel" then
		full = StoreService.blasterStatus(data, product) ~= "Prompt"
	elseif grant == "RebirthWeapon" then
		-- a STAR blaster is sold once the player's rebirths reach it
		full = not StarBlasterData.unlocked(data, product.WeaponId)
	elseif grant == "ServerBoost" then
		local ServerBoostService = require(script.Parent.ServerBoostService) :: any
		full = ServerBoostService.full(product.Seconds or 0)
	end
	-- promptPurchase reads the policy for a paid random product, gates and prompts
	BoostService.promptPurchase(player, key, owned, full)
end

local function onAction(player: Player, action: any, payload: any)
	if action ~= "Buy" then
		return
	end
	local args = Guard.table(payload, MAX_PAYLOAD)
	local key = if args then Guard.string(args.Key, MAX_KEY) else nil
	if not key then
		return
	end
	StoreService.buy(player, key)
end

function StoreService.init()
	Net.on("StoreAction", onAction)
end

function StoreService.start() end

return StoreService
