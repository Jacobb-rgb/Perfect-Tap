--[[
	StarterPackService: the Starter Pack (MonetizationConfig "StarterPack",
	99 R$, a developer product sold once per account).

	- The offer: open while the save never bought it and the player has
	  played less than OfferSeconds (data.Stats.PlaySeconds, credited by
	  LeaderboardService), and coins are buyable (its coins are "coins for
	  Robux": MonetizationConfig.coinsBuyable). The State snapshot carries
	  StarterPack = { Open, Bought, Left } (Left: seconds of play the offer
	  still runs); the client shows the store card and a small popup once
	  per session (StarterPackController).
	- Prompting goes through StoreService (StoreAction "Buy"): "Owned" once
	  bought, "Unknown" when the offer is over (StarterPackService.promptState).
	- The "StarterPack" receipt handler (MonetizationService.register: grant
	  only on the server holding the session lock, saved before
	  PurchaseGranted). Nothing random: the entry's Golem (paid and locked,
	  past the inventory cap up to MaxSaved like a Royal capsule's; past
	  MaxSaved it waits in data.Golems.Pending), coinPackAmount coins
	  (CoinSeconds of the podium income now, at least MinCoins; kept through
	  a rebirth as PaidCoins), and the Pioneer podium skin + title
	  (ArtifactService.starterReward, shown while no collection reward is
	  equipped). Recorded in data.StarterPack (BoughtAt, Count). A second
	  receipt of the same account (two prompts open at once, or a prompt from
	  before the purchase) is granted in full again: a paid receipt is never
	  dropped. Refused (false: the receipt waits, nothing written) while coins
	  aren't buyable or the pending-golem credit is full. No yield.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)

local StarterPackService = {}

StarterPackService.Key = "StarterPack"
StarterPackService.OfferSeconds = MonetizationConfig.StarterOffer.Seconds -- seconds of play the offer runs

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- data.StarterPack as a record (made when missing or junk).
local function recordOf(data: { [string]: any }): { BoughtAt: number, Count: number }
	local record = data.StarterPack
	if type(record) ~= "table" then
		record = {}
		data.StarterPack = record
	end
	if not finite(record.BoughtAt) or record.BoughtAt < 0 then
		record.BoughtAt = 0
	end
	if not finite(record.Count) or record.Count < 0 then
		record.Count = 0
	end
	return record
end

-- Has this save bought the Starter Pack?
function StarterPackService.bought(data: any): boolean
	local record = if type(data) == "table" then data.StarterPack else nil
	return type(record) == "table" and finite(record.BoughtAt) and record.BoughtAt > 0
end

-- Seconds of play the offer still runs for this save (0: over).
function StarterPackService.left(data: any): number
	local stats = if type(data) == "table" then data.Stats else nil
	local played = if type(stats) == "table" and finite(stats.PlaySeconds) then math.max(0, stats.PlaySeconds) else 0
	return math.max(0, math.floor(StarterPackService.OfferSeconds - played))
end

-- Is the offer open for this save (not bought, in the first hour, coins buyable)?
function StarterPackService.offerOpen(data: any): boolean
	return MonetizationConfig.coinsBuyable() and not StarterPackService.bought(data) and StarterPackService.left(data) > 0
end

-- What StoreService does with a buy: "Owned" (bought), "Over" (the offer
-- ended: answered "Unknown") or "Open".
function StarterPackService.promptState(data: any): string
	if StarterPackService.bought(data) then
		return "Owned"
	end
	return if StarterPackService.offerOpen(data) then "Open" else "Over"
end

-- The State snapshot's StarterPack section.
function StarterPackService.summary(data: any): { [string]: any }
	return {
		Open = StarterPackService.offerOpen(data),
		Bought = StarterPackService.bought(data),
		Left = StarterPackService.left(data),
	}
end

-- data.Golems.Pending as a list (made when missing or junk).
local function pendingOf(data: { [string]: any }): { { [string]: any } }
	local golems = data.Golems
	if type(golems) ~= "table" then
		golems = { Owned = {}, Equipped = {}, NextId = 1 }
		data.Golems = golems
	end
	if type(golems.Pending) ~= "table" then
		golems.Pending = {}
	end
	return golems.Pending
end

-- The receipt handler (see the header). No yield.
local function grantStarter(player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local kind = entry.Golem
	if DataService.get(player) ~= data or not kind or not GolemConfig.ById[kind] then
		return false
	end
	if not MonetizationConfig.coinsBuyable() then
		return false -- (never coins while coins aren't buyable: the receipt waits)
	end
	local golems = data.Golems
	local fits = type(golems) ~= "table" or GolemConfig.count(golems) < GolemConfig.MaxSaved
	if not fits and #pendingOf(data) >= GolemConfig.MaxPending then
		return false
	end
	local PodiumService = require(script.Parent.PodiumService) :: any
	local amount = MonetizationConfig.coinPackAmount(entry.Key, PodiumService.incomeOf(player, data))
	if not amount or amount <= 0 then
		return false
	end
	amount = math.min(amount, EconomyConfig.MaxAward)
	-- the golem: paid and locked, past the inventory cap like a Royal capsule's
	if type(data.Golems) ~= "table" then
		data.Golems = { Owned = {}, Equipped = {}, NextId = 1 }
	end
	local woken = GolemConfig.add(data.Golems, kind, true, true)
	if woken then
		woken.Locked = true
		GolemConfig.equip(data.Golems, woken.Id) -- (into a free slot; none free: it waits in the inventory)
	else
		table.insert(pendingOf(data), { Kind = kind, Paid = true })
	end
	-- the coins (bought coins survive a rebirth while unspent)
	EconomyService.award(player, amount, "StarterPack", true)
	local paid = if finite(data.PaidCoins) then data.PaidCoins else 0
	data.PaidCoins = math.min(paid + amount, if finite(data.Coins) then data.Coins else amount)
	-- the record (the skin and title follow it)
	local record = recordOf(data)
	if record.BoughtAt <= 0 then
		record.BoughtAt = os.time()
	end
	record.Count = math.floor(record.Count) + 1
	task.defer(function()
		local ok, ArtifactService = pcall(require, script.Parent.ArtifactService)
		if ok and player.Parent and type(ArtifactService) == "table" then
			pcall((ArtifactService :: any).applyRewards, player)
		end
	end)
	local golem = GolemConfig.ById[kind]
	Net.fire("Notify", player, {
		Text = `Starter Pack: {golem.Name}, +{Format.big(amount)} coins and the Pioneer podium skin. Thank you!`,
		Kind = "Reward",
	})
	return true
end

-- Registers the "StarterPack" receipt handler (init(); idempotent).
function StarterPackService.registerGrants()
	MonetizationService.register("StarterPack", grantStarter)
end

-- Internals for the Lune tests only.
StarterPackService._test = {
	grant = grantStarter,
}

function StarterPackService.init()
	StarterPackService.registerGrants()
	StateService.addProvider(function(_player: Player, data: { [string]: any }, snapshot: { [string]: any })
		snapshot.StarterPack = StarterPackService.summary(data)
	end)
end

function StarterPackService.start() end

return StarterPackService
