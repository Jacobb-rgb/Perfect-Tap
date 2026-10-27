--[[
	VaultService: the Blaster Vault shop at the end of the lobby's south road
	(the owner-approved Forge Vault, src/server/World/Lobby/Vault).

	The counter (tag "VaultCounter") gets a "Blaster Vault" prompt (E /
	gamepad Y, like every prompt: PromptConfig "Main"; F is the grab key) that
	opens the shop on the client (OpenUI "Vault" { Counter }).

	The Vault is the only way to a better blaster (owner 2026-10-24: no
	Foundry). VaultBuy { Level } (Net, rate limited) buys your NEXT blaster
	level for coins (BlasterData.vaultPrice: the level's Coins x
	BlasterData.Vault.PriceMultiplier, in a rebirth run at least some minutes
	of the income the rebirth kept, Stats.RunIncome), in the look of that
	level's case (BlasterData.vaultOre). Checked here, in one step with no yield:
	a save is loaded, Level is a whole number and exactly your level + 1
	("Owned" for a level you have, "Locked" past the next one, "Max" at the
	top), you stand at the counter ("TooFar"), the coins are there
	("NoCoins", EconomyService.spend). Then BlasterLevel = Level, BlasterOre =
	the case's ore, Stats.BlastersBought + 1, Stats.RunForged = the level
	(the rebirth run's stars count it: RebirthConfig.reachedOf),
	DataService.changed (ToolService swaps the blaster). Every request read gets a VaultResult
	{ Level, Ok, Reason?, Ore?, Name?, Paid? }; the client plays the crate opening on Ok.

	Robux (the STORE's BlasterNextA-D, MonetizationConfig products with Grant
	"BlasterLevel" and MinLevel / MaxLevel = the next levels a product
	covers, priced in bands 49 / 99 / 199 / 399 R$): the "BlasterLevel"
	receipt handler gives the next level through the same setter (grantNext
	"Robux": Stats.BlastersPaid + 1, Stats.RunPaid so the rebirth run pays
	stars only for levels bought with coins) and the crate opening plays
	(VaultResult Paid = true). Every Robux level comes back at every later
	rebirth (RebirthConfig.startFor lifts the fresh blaster one level per
	BlastersPaid, up to MaxLevel - 1). On the first run the levels the grace
	counted so far stay counted (RunForged), only the bought ones pay no
	stars. The top level is never sold for Robux while this run has bought no
	rebirth level with coins (RebirthConfig.topBlocked), or nothing would be
	left to buy. It never refuses (the receipt would come
	back forever and the player paid for nothing): at the top level, off the
	product's band (a stale or client-made prompt) or while the top level
	waits, the Robux it cost are banked (Stats.BlasterCredit) and buy start
	lifts only at the band price of the start level they make (spendCredit:
	a cheap band never buys a high start). Never coins. The store asks
	paidStatus first ("Full" at the top / off-band / topBlocked).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local PromptConfig = require(Shared.Config.PromptConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local PodiumService = require(script.Parent.PodiumService)

local VaultService = {}

-- studs from the counter's surface the server accepts (the prompt reaches 12, the client closes past 24)
VaultService.Range = 30
VaultService.Tag = "VaultCounter"
VaultService.PromptName = "VaultShopPrompt"
VaultService.PointName = "VaultShopPromptPoint"

VaultService.Reasons = { "BadLevel", "Owned", "Locked", "Max", "TooFar", "NoCoins", "NoData" }

local PROMPT_DISTANCE = 12
local MAX_PAYLOAD = 4

local counters: { BasePart } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

---------------------------------------------------------------- range

-- Distance from a point to the surface of a part's box (0 inside).
local function distanceToPart(part: BasePart, position: Vector3): number
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The VaultCounter the player stands at (within `range`), or nil.
function VaultService.counterNear(player: Player, range: number): BasePart?
	local root = Guard.rootPart(player)
	if not root then
		return nil
	end
	for _, counter in counters do
		if counter.Parent and distanceToPart(counter, root.Position) <= range then
			return counter
		end
	end
	return nil
end

---------------------------------------------------------------- buying

-- The level a save holds (1..MaxLevel).
local function levelOf(data: { [string]: any }): number
	return BlasterData.get(data.BlasterLevel).Level
end

--[[
	Why `level` can't be bought by a player at `current` with `coins`, or nil
	when it can (pure: the client's cards use it too). `runIncome` = the
	rebirth run's price floor (RebirthConfig.runIncomeOf).
]]
function VaultService.refusal(level: number, current: number, coins: number, runIncome: number?): string?
	if current >= BlasterData.MaxLevel and level > current then
		return "Max"
	end
	local price = BlasterData.vaultPrice(level, runIncome)
	if not price then
		return if level == 1 then "Owned" else "BadLevel"
	end
	if level <= current then
		return "Owned"
	elseif level > current + 1 then
		return "Locked"
	elseif coins < price then
		return "NoCoins"
	end
	return nil
end

local function whole(v: any): number
	return if type(v) == "number" and v == v and v > 0 and v < math.huge then math.floor(v) else 0
end

--[[
	Buys `level` for the player (no range check: onBuy does it). Returns
	ok, reason. Quote, spend and write in one step with no yield, so a double
	tap buys one level.
]]
function VaultService.buy(player: Player, level: number): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	local current = levelOf(data)
	-- the floor is the factory's best income this run, up to this very moment
	PodiumService.raiseRunIncome(player, data)
	local runIncome = RebirthConfig.runIncomeOf(data)
	local reason = VaultService.refusal(level, current, EconomyService.balance(player), runIncome)
	if reason then
		return false, reason
	end
	local price = BlasterData.vaultPrice(level, runIncome) :: number
	local paidBefore = whole(data.PaidCoins)
	if not EconomyService.spend(player, price, "Vault") then
		return false, "NoCoins"
	end
	-- coins bought with Robux (spent last) paid part of it: like a Robux level, it pays no
	-- stars (the review of 2026-10-25; the owner decides later whether they should)
	VaultService.grantNext(player, data, if whole(data.PaidCoins) < paidBefore then "PaidCoins" else "Coins")
	return true, nil
end

--[[
	The one level setter (no yield): the player's next blaster level in that
	level's case look. "Coins" (the Vault) counts Stats.BlastersBought and
	raises Stats.RunForged (the rebirth run counts it); "Robux" counts
	Stats.BlastersPaid and marks the rebirth run as paid (Stats.RunPaid:
	RebirthConfig.reachedOf); "PaidCoins" (the Vault, partly paid with coins
	bought with Robux, data.PaidCoins) counts Stats.BlastersBought but pays no
	stars, like a Robux level. Returns the new level, or nil at the top level.
]]
function VaultService.grantNext(player: Player, data: { [string]: any }, source: string): number?
	local current = levelOf(data)
	if current >= BlasterData.MaxLevel then
		return nil
	end
	local level = current + 1
	data.BlasterLevel = level
	data.BlasterOre = BlasterData.vaultOre(level)
	local stats = data.Stats
	if type(stats) ~= "table" then
		stats = {}
		data.Stats = stats
	end
	if source == "Robux" or source == "PaidCoins" then
		-- the first run's grace counted the blaster as it was: keep those levels
		-- (only the bought ones pay nothing)
		if RebirthConfig.countOf(data) == 0 and stats.RunPaid ~= true then
			stats.RunForged = math.max(whole(stats.RunForged), current)
		end
		if source == "Robux" then
			stats.BlastersPaid = whole(stats.BlastersPaid) + 1
		else
			stats.BlastersBought = whole(stats.BlastersBought) + 1
		end
		stats.RunPaid = true
	else
		stats.BlastersBought = whole(stats.BlastersBought) + 1
		stats.RunForged = math.max(whole(stats.RunForged), level)
	end
	DataService.changed(player)
	return level
end

-- What the STORE answers before prompting a "BlasterLevel" product: "Prompt"
-- when its band holds the player's next level, else "Full" (MonetizationConfig.promptStatus;
-- also while the top level must be bought with coins first: RebirthConfig.topBlocked).
function VaultService.paidStatus(data: any, entry: any): string
	if type(data) ~= "table" or type(entry) ~= "table" then
		return "Full"
	end
	local current = levelOf(data)
	local nextLevel = current + 1
	local lo = tonumber(entry.MinLevel) or 2
	local hi = tonumber(entry.MaxLevel) or BlasterData.MaxLevel
	if current >= BlasterData.MaxLevel or nextLevel < lo or nextLevel > hi or RebirthConfig.topBlocked(data) then
		return "Full"
	end
	return "Prompt"
end

-- The "BlasterLevel" product whose band holds `level` (MonetizationConfig, the STORE's bands).
local function bandFor(level: number): MonetizationConfig.Entry?
	for _, entry in MonetizationConfig.list("Product") do
		local band: any = entry
		local lo = tonumber(band.MinLevel) or 2
		local hi = tonumber(band.MaxLevel) or BlasterData.MaxLevel
		if entry.Grant == "BlasterLevel" and level >= lo and level <= hi then
			return entry
		end
	end
	return nil
end

--[[
	Turns banked Robux (Stats.BlasterCredit) into rebirth start lifts while it
	covers the band price of the start level the next lift makes
	(RebirthConfig.startFor + 1, up to MaxLevel - 1): a cheap band never buys
	a high start. Returns the lifts added.
]]
function VaultService.spendCredit(data: { [string]: any }): number
	local stats = data.Stats
	if type(stats) ~= "table" then
		return 0
	end
	local lifts = 0
	while true do
		local target = RebirthConfig.startFor(data) + 1
		local band = if target <= BlasterData.MaxLevel - 1 then bandFor(target) else nil
		local price = if band then whole(band.Robux) else 0
		if price <= 0 or whole(stats.BlasterCredit) < price then
			break
		end
		stats.BlasterCredit = whole(stats.BlasterCredit) - price
		stats.BlastersPaid = whole(stats.BlastersPaid) + 1
		lifts += 1
	end
	return lifts
end

local function answer(player: Player, level: number, ok: boolean, reason: string?, paid: boolean?)
	local ore = if ok then BlasterData.vaultOre(level) else nil
	Net.fire("VaultResult", player, {
		Level = level,
		Ok = ok,
		Reason = reason,
		Ore = ore,
		Name = if ok then BlasterData.displayName(level, ore) else nil,
		Paid = if paid then true else nil,
	})
end

--[[
	The "BlasterLevel" receipt handler (MonetizationService.register): the
	next level when the product's band holds it, else its Robux banked as
	start-lift credit (spendCredit; see the header). Never refuses a loaded
	save; no yield.
]]
local function grantPaid(player: Player, data: { [string]: any }, entry: any): boolean
	if DataService.get(player) ~= data then
		return false
	end
	if VaultService.paidStatus(data, entry) == "Prompt" then
		local level = VaultService.grantNext(player, data, "Robux") :: number
		answer(player, level, true, nil, true)
		return true
	end
	local stats = data.Stats
	if type(stats) ~= "table" then
		stats = {}
		data.Stats = stats
	end
	-- off band / at the top / the top level waits for a coin level: the Robux it cost are banked
	-- and buy rebirth start lifts at the band prices (spendCredit)
	stats.BlasterCredit = whole(stats.BlasterCredit) + whole(entry.Robux)
	local lifts = VaultService.spendCredit(data)
	DataService.changed(player)
	local text = if lifts > 0
		then `Thank you! Every rebirth now starts your new blaster at LV {RebirthConfig.startFor(data)}.`
		else "Thank you! It is saved as credit: it lifts the blaster your rebirths start with."
	Net.fire("Notify", player, { Text = text, Kind = "Reward" })
	return true
end

-- Registers the "BlasterLevel" receipt handler (init(); idempotent).
function VaultService.registerGrants()
	MonetizationService.register("BlasterLevel", grantPaid)
end

-- VaultBuy { Level }: every request read gets a VaultResult.
local function onBuy(player: Player, payload: any)
	local args = Guard.table(payload, MAX_PAYLOAD)
	local raw = if args then args.Level else nil
	local level = if type(raw) == "number" and raw == raw and raw == math.floor(raw) and math.abs(raw) < 1000 then raw else nil
	if not level then
		answer(player, 0, false, "BadLevel")
		return
	end
	if not DataService.get(player) then
		answer(player, level, false, "NoData")
		return
	end
	if not VaultService.counterNear(player, VaultService.Range) then
		answer(player, level, false, "TooFar")
		return
	end
	local ok, reason = VaultService.buy(player, level)
	answer(player, level, ok, reason)
end

---------------------------------------------------------------- the counter

local function openView(player: Player, counter: BasePart)
	if not DataService.get(player) or not VaultService.counterNear(player, VaultService.Range) then
		return
	end
	Net.fire("OpenUI", player, "Vault", { Counter = counter })
end

local function pruneCounters()
	for i = #counters, 1, -1 do
		local counter = counters[i]
		if not counter.Parent then
			table.remove(counters, i)
			hooked[counter] = nil
		end
	end
end

local function hookCounter(counter: Instance)
	pruneCounters()
	if hooked[counter] or not counter:IsA("BasePart") then
		return
	end
	hooked[counter] = true
	local part = counter :: BasePart
	table.insert(counters, part)
	local old = part:FindFirstChild(VaultService.PointName)
	if old then
		old:Destroy()
	end
	-- the prompt sits over the customer side of the counter top (the vault's front, the counter's +Z)
	local point = Instance.new("Attachment")
	point.Name = VaultService.PointName
	point.CFrame = CFrame.new(0, part.Size.Y / 2 + 1.2, part.Size.Z / 2)
	point.Parent = part
	local prompt = PromptConfig.make({
		Name = VaultService.PromptName,
		ActionText = "Blaster Vault",
		ObjectText = "Blaster Cases",
		Distance = PROMPT_DISTANCE,
		Parent = point,
	})
	prompt.Triggered:Connect(function(player: Player)
		openView(player, part)
	end)
end

local function unhookCounter(counter: Instance)
	local index = table.find(counters, counter :: any)
	if index then
		table.remove(counters, index)
	end
	hooked[counter] = nil
	local point = counter:FindFirstChild(VaultService.PointName)
	if point then
		point:Destroy()
	end
	pruneCounters()
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/VaultService.spec.luau).
VaultService._test = {
	buy = onBuy,
	grantPaid = grantPaid,
	hookCounter = hookCounter,
	unhookCounter = unhookCounter,
	open = openView,
	counters = function(): { BasePart }
		return table.clone(counters)
	end,
	reset = function()
		table.clear(counters)
	end,
}

function VaultService.init()
	Net.on("VaultBuy", onBuy)
	VaultService.registerGrants()
end

function VaultService.start()
	for _, instance in CollectionService:GetTagged(VaultService.Tag) do
		hookCounter(instance)
	end
	CollectionService:GetInstanceAddedSignal(VaultService.Tag):Connect(hookCounter)
	CollectionService:GetInstanceRemovedSignal(VaultService.Tag):Connect(unhookCounter)
end

return VaultService
