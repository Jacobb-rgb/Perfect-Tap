--[[
	CapsuleService: golem capsules (step 7, CapsuleConfig). Each capsule
	holds a dormant golem core; opening one wakes a random golem
	(GolemConfig) into the player's inventory.

	- The CapsuleStall (tag, a Model in the lobby: PrimaryPart = the pedestal
	  "CapsuleMachine"): this service adds a "Capsules" prompt in front of the
	  big capsule at runtime; it opens the capsule view (OpenUI "Capsules"
	  { Stall }). Opening works anywhere (the side menu too), so the server
	  checks no range.
	- CapsuleAction ("Open", { Capsule, Count, Lucky? }) (Net, rate limited;
	  Count 1, 3 or 10; Lucky = whether the client showed the Triple Lucky
	  odds, see below):
	    coin capsules  price CapsuleConfig.price at the player's blaster
	                   level; needs Count free golem places (GolemConfig.room).
	                   Quote, roll, spend and grant happen in one step with no
	                   yield, so two requests can never both pass the checks,
	                   and nothing can fail after the coins are gone (every
	                   rolled kind is a known golem and the room was checked).
	                   Answer: CapsuleResult { Capsule, Count, Golems = { { Id,
	                   Kind } } (opening order), Lucky }.
	    Royal (Robux)  never granted here: answered with PurchasePrompt
	                   { Product, Status } (MonetizationConfig.promptStatus;
	                   "Full" when the inventory can't take Count more;
	                   "ComingSoon" too for a live product id until step 8
	                   turns the one receipts gate on (src/server/Receipts.luau,
	                   also CapsuleService.setReceiptsReady(true)) once its
	                   ProcessReceipt handler is registered, so nobody pays
	                   Robux for nothing). A "Prompted" answer stores
	                   { Product, TripleLucky, At, Until } for the player (the
	                   latest prompt per product): step 8's ProcessReceipt
	                   opens the capsules with the better of that Triple Lucky
	                   state and the one at the receipt (grantProduct), so a
	                   receipt never rolls worse odds than the card showed,
	                   whichever way the purchase came. Kept until Until =
	                   At + MonetizationConfig.PromptMemorySeconds, and a
	                   boosted one at most PurchaseGrace seconds past the end of
	                   the boost it came from (a purchase finished later uses
	                   the odds of that moment), so a prompt never stretches a
	                   boost; forgotten at once when the prompt closes without
	                   a purchase (PromptProductPurchaseFinished).
	  Paid random items (CapsuleConfig.isPaidRandom: Royal always, coin
	  capsules only while coins can be bought with Robux) are refused
	  ("Restricted") where PolicyService ArePaidRandomItemsRestricted is true
	  (src/server/Policy.luau; asked BEFORE the quote, it may yield once).
	  Every request the server reads gets one answer: a CapsuleResult, an
	  ActionResult { Action = "Capsule", Op = "Open", Ok = false, Reason
	  (CapsuleConfig.Reasons), Id = capsule } or a PurchasePrompt.
	- Triple Lucky (oddsFor): on while Bonuses.tripleLucky (data.Boosts.
	  TripleLuckyUntil and any later source of CapsuleLuckMult). A request
	  rolls exactly the odds its client showed (Lucky): shown boosted, it is
	  granted while Triple Lucky runs or ran out at most LuckyGrace seconds
	  ago (sent in its last moment); shown normal, it gets the normal odds,
	  also in that grace and in the boost's last EndSlack seconds (os.time
	  counts whole seconds, the client's server clock is fractional and may
	  show the normal odds a moment earlier). Otherwise (the boost ended long
	  ago, or started a moment ago and the client didn't know yet) the
	  request is refused "OddsChanged" and a fresh State is pushed, so the
	  client shows the odds that hold now. A request without Lucky (an older
	  client) and the wheel's free capsule get the server's view (on, or
	  within the grace).
	- Rolls: a fresh Random.new() per call (seeded by the engine; swappable
	  for the tests).
	- Data: golems through GolemConfig.add, Stats.CapsulesOpened counts every
	  golem woken; DataService.changed after every grant (EconomyService.spend
	  calls it too). The equipped golems' bonuses reach every system through
	  Bonuses (provider "Golems", podium income via EconomyService).
	- A Legendary or Mythic golem is announced to the other players (Notify
	  "Discovery").
	- Hooks for other packages: grantFree (the wheel's capsule prize: no
	  price, CapsuleResult with Free = true; quiet = true leaves sending it
	  to the caller, QuietFree says this service honors that), registerGrants (the
	  "Capsule" receipt handler: grantProduct, then the golems past MaxSaved wait
	  in data.Golems.Pending, woken by wakePending on load / change), grantProduct (step 8 receipts:
	  paid golems may pass the inventory cap up to GolemConfig.MaxSaved,
	  Paid = true and Locked = true, so a golem bought with Robux is never
	  deleted by a slip), setReceiptsReady (step 8, see Royal above; also
	  the ReplicatedStorage attribute ReceiptsAttribute, so the capsule card
	  shows "Coming soon" until then), promptedLucky, onOpened(callback).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Guard = require(script.Parent.Parent.Guard)
local Policy = require(script.Parent.Parent.Policy)
local Receipts = require(script.Parent.Parent.Receipts)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)

local CapsuleService = {}

export type Source = "Coins" | "Robux" | "Free"
export type Woken = { Id: number, Kind: string }
export type Result = {
	Capsule: string,
	Count: number,
	Golems: { Woken },
	Lucky: boolean,
	Free: boolean?,
}
export type Opened = { Capsule: string, Count: number, Kinds: { string }, Lucky: boolean, Source: Source, Price: number? }
export type OpenedCallback = (Player, Opened) -> ...any
export type Prompt = { Product: string, TripleLucky: boolean, At: number, Until: number }
type RandomLike = { NextNumber: (self: any) -> number }

CapsuleService.Tag = "CapsuleStall"
CapsuleService.PromptName = "CapsulePrompt"
CapsuleService.PointName = "CapsulePromptPoint"
CapsuleService.LuckyGrace = 3 -- seconds a request that showed Triple Lucky still gets it after it ran out (see the header)
CapsuleService.EndSlack = 1.5 -- seconds before the boost's end a request that showed the normal odds gets them (see the header)
CapsuleService.PurchaseGrace = 120 -- seconds a Royal prompt shown with Triple Lucky keeps it past the boost's end
CapsuleService.AnnounceFrom = "Legendary" -- golems this rare are announced to the server
CapsuleService.PromptDistance = 12
-- ReplicatedStorage attribute: true once step 8 handles receipts (Receipts, the
-- one gate for every Robux product; CapsuleView reads it)
CapsuleService.ReceiptsAttribute = Receipts.Attribute

local MAX_PAYLOAD = 4
local MAX_ID_LENGTH = 32

local callbacks: { OpenedCallback } = {}
-- player -> product key -> the prompt the player saw (step 8 contract)
local prompts: { [Player]: { [string]: Prompt } } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Swappable for the Lune tests.
local clock: () -> number = os.time
local newRandom: (player: Player) -> RandomLike = function(_player: Player): RandomLike
	return Random.new() :: any
end
local pushState: (player: Player) -> () = function(player: Player)
	StateService.push(player)
end
local listPlayers: () -> { Player } = function(): { Player }
	return Players:GetPlayers()
end
local prompter: (player: Player, productId: number) -> () = function(player: Player, productId: number)
	game:GetService("MarketplaceService"):PromptProductPurchase(player, productId)
end

-- Listeners: (player, Opened) after every grant (coins, Robux or free).
function CapsuleService.onOpened(callback: OpenedCallback)
	table.insert(callbacks, callback)
end

---------------------------------------------------------------- rolls and grants

-- Does Triple Lucky run for this player right now (no grace)?
local function luckyNow(player: Player, data: { [string]: any }, now: number): boolean
	return Bonuses.tripleLucky(Bonuses.stats(player)) or BoostConfig.untilOf(data.Boosts, "TripleLucky") > now
end

-- The server's own view: Triple Lucky runs, or ran out at most LuckyGrace seconds ago.
function CapsuleService.tripleLucky(player: Player, data: { [string]: any }, now: number): boolean
	if luckyNow(player, data, now) then
		return true
	end
	return BoostConfig.untilOf(data.Boosts, "TripleLucky") + CapsuleService.LuckyGrace > now
end

--[[
	The odds a request rolls (true = Triple Lucky): exactly the ones its
	client showed (`shown`, see the header), or nil when those no longer
	hold (the request is refused "OddsChanged"). `shown` nil: the server's
	view.
]]
function CapsuleService.oddsFor(player: Player, data: { [string]: any }, now: number, shown: boolean?): boolean?
	if shown == nil then
		return CapsuleService.tripleLucky(player, data, now)
	end
	if shown then
		return if CapsuleService.tripleLucky(player, data, now) then true else nil
	end
	-- shown normal: refused while the boost surely runs (not in its last
	-- EndSlack seconds) or another source of Triple Lucky is on
	local untilTime = BoostConfig.untilOf(data.Boosts, "TripleLucky")
	if untilTime - now > CapsuleService.EndSlack then
		return nil
	end
	if untilTime <= now and luckyNow(player, data, now) then
		return nil
	end
	return false
end

-- `count` golem kinds rolled from a capsule (CapsuleConfig.roll; opening order).
function CapsuleService.roll(capsuleId: string, count: number, lucky: boolean, random: RandomLike): { string }
	local kinds = {}
	for _ = 1, count do
		local kind = CapsuleConfig.roll(capsuleId, lucky, random:NextNumber())
		if kind and GolemConfig.ById[kind] then
			table.insert(kinds, kind)
		end
	end
	return kinds
end

-- Adds already-rolled kinds to the save (pure on `data`; the caller calls
-- DataService.changed). Returns the woken golems, how many didn't fit
-- (only with `overCap`, past GolemConfig.MaxSaved; otherwise the caller
-- checked the room first) and those kinds.
local function add(data: { [string]: any }, kinds: { string }, overCap: boolean?, paid: boolean?): ({ Woken }, number, { string })
	if type(data.Golems) ~= "table" then
		data.Golems = { Owned = {}, Equipped = {}, NextId = 1 }
	end
	local woken: { Woken } = {}
	local left: { string } = {}
	for _, kind in kinds do
		local entry = GolemConfig.add(data.Golems, kind, overCap, paid)
		if entry then
			if paid then
				entry.Locked = true -- bought with Robux: never deleted by a slip (the player may unlock it)
			end
			table.insert(woken, { Id = entry.Id, Kind = entry.Kind })
		else
			table.insert(left, kind)
		end
	end
	if type(data.Stats) ~= "table" then
		data.Stats = {}
	end
	local opened = tonumber(data.Stats.CapsulesOpened) or 0
	data.Stats.CapsulesOpened = (if opened == opened and opened >= 0 then math.floor(opened) else 0) + #woken
	return woken, #kinds - #woken, left
end

-- Tells the other players about a Legendary+ golem. Returns the text (nil: nothing to tell).
local function announce(player: Player, kinds: { string }): string?
	local from = Rarity.ById[CapsuleService.AnnounceFrom].Order
	local best: string? = nil
	for _, kind in kinds do
		if GolemConfig.order(kind) >= from and (best == nil or GolemConfig.score(kind) > GolemConfig.score(best)) then
			best = kind
		end
	end
	if not best then
		return nil
	end
	local golem = GolemConfig.ById[best]
	local text = `{player.DisplayName} woke a {golem.Rarity} {golem.Name}!`
	for _, other in listPlayers() do
		if other ~= player then
			Net.fire("Notify", other, { Text = text, Kind = "Discovery", Rarity = golem.Rarity })
		end
	end
	return text
end

local function opened(player: Player, info: Opened)
	for _, callback in callbacks do
		task.spawn(callback, player, info)
	end
	local ok, err = pcall(announce, player, info.Kinds)
	if not ok then
		warn("[CapsuleService] announce failed: " .. tostring(err))
	end
end

local function kindsOf(woken: { Woken }): { string }
	local kinds = {}
	for _, golem in woken do
		table.insert(kinds, golem.Kind)
	end
	return kinds
end

--[[
	Opens `count` coin capsules for the player: quote, roll, spend and grant
	with no yield in between. `shown`: the odds the client showed (oddsFor).
	Returns (true, nil, Result) or (false, reason) with a CapsuleConfig.Reasons
	code (or "OddsChanged"). No policy check here (the request handler asks
	Policy first).
]]
function CapsuleService.openCoins(player: Player, capsuleId: string, count: number, shown: boolean?): (boolean, string?, Result?)
	local data = DataService.get(player)
	local capsule = CapsuleConfig.ById[capsuleId]
	if not data or not capsule or capsule.Currency ~= "Coins" then
		return false, "BadCapsule", nil
	end
	if not CapsuleConfig.validCount(count) then
		return false, "BadCount", nil
	end
	local price = CapsuleConfig.price(capsuleId, count, BlasterData.priceLevel(data))
	if price == nil then
		return false, "BadCapsule", nil
	end
	if GolemConfig.room(data.Golems) < count then
		return false, "InventoryFull", nil
	end
	if not EconomyService.canAfford(player, price) then
		return false, "NoCoins", nil
	end
	local odds = CapsuleService.oddsFor(player, data, clock(), shown)
	if odds == nil then
		return false, "OddsChanged", nil
	end
	local lucky = odds == true
	local kinds = CapsuleService.roll(capsuleId, count, lucky, newRandom(player))
	if #kinds ~= count then
		return false, "BadCapsule", nil -- a broken odds table: nothing is spent
	end
	if type(data.Golems) ~= "table" then
		data.Golems = { Owned = {}, Equipped = {}, NextId = 1 }
	end
	if not EconomyService.spend(player, price, "Capsule:" .. capsuleId) then
		return false, "NoCoins", nil
	end
	-- paid: grant in the same step (the room was checked, every kind is known)
	local woken = add(data, kinds)
	DataService.changed(player)
	local result: Result = { Capsule = capsuleId, Count = count, Golems = woken, Lucky = lucky }
	opened(player, { Capsule = capsuleId, Count = count, Kinds = kindsOf(woken), Lucky = lucky, Source = "Coins", Price = price })
	return true, nil, result
end

--[[
	A free capsule (the daily wheel's prize): no price, the player's Triple
	Lucky counts. Refused ("InventoryFull") when there is no room for
	`count` (default 1): the caller pays its fallback instead. Returns the
	CapsuleResult (Free = true) and sends it, unless `quiet`: then the
	caller sends it when its own screen is ready (WheelService sends it on
	the wheel's "Reveal", so the opening never spoils the turning disc).
]]
CapsuleService.QuietFree = true -- grantFree honors `quiet` (WheelService reads this)

function CapsuleService.grantFree(player: Player, capsuleId: string, count: number?, quiet: boolean?): (Result?, string?)
	local data = DataService.get(player)
	local n = count or 1
	if not data or not CapsuleConfig.ById[capsuleId] or type(n) ~= "number" or n < 1 or n > 10 or n ~= math.floor(n) then
		return nil, "BadCapsule"
	end
	if GolemConfig.room(data.Golems) < n then
		return nil, "InventoryFull"
	end
	local lucky = CapsuleService.tripleLucky(player, data, clock())
	local kinds = CapsuleService.roll(capsuleId, n, lucky, newRandom(player))
	if #kinds ~= n then
		return nil, "BadCapsule"
	end
	local woken = add(data, kinds)
	DataService.changed(player)
	local result: Result = { Capsule = capsuleId, Count = n, Golems = woken, Lucky = lucky, Free = true }
	if quiet ~= true then
		Net.fire("CapsuleResult", player, result)
	end
	opened(player, { Capsule = capsuleId, Count = n, Kinds = kindsOf(woken), Lucky = lucky, Source = "Free" })
	return result, nil
end

---------------------------------------------------------------- Robux capsules (step 8 hooks)

-- The Triple Lucky state the player saw when the server last prompted
-- `productKey` (nil: no prompt, or it is past its Until; see the header).
function CapsuleService.promptedLucky(player: Player, productKey: string, now: number?): boolean?
	local list = prompts[player]
	local prompt = if list then list[productKey] else nil
	if not prompt then
		return nil
	end
	local t = now or clock()
	if t > prompt.Until or t - prompt.At > MonetizationConfig.PromptMemorySeconds then
		list[productKey] = nil
		return nil
	end
	return prompt.TripleLucky
end

--[[
	Step 8: ProcessReceipt for a Royal capsule product (call it on the server
	that holds the session lock, then save). Opens the product's capsules
	with Triple Lucky when the stored prompt had it OR it runs now (never
	worse odds than either screen showed: the prompt's, or the card of the
	moment for a purchase made another way, e.g. the Store tab); the golems
	are paid (Paid = true), locked (Locked = true) and may pass the
	inventory cap up to GolemConfig.MaxSaved. Returns the CapsuleResult
	(also sent), how many golems didn't fit past MaxSaved and their kinds
	(the receipt handler keeps those as a pending-golem credit, never coins:
	MonetizationConfig's step 8 contract). nil for a product that isn't a
	capsule.
]]
function CapsuleService.grantProduct(player: Player, productKey: string): (Result?, number, { string })
	local data = DataService.get(player)
	local product = MonetizationConfig.get(productKey)
	if not data or not product or not product.Capsule or not CapsuleConfig.ById[product.Capsule] then
		return nil, 0, {}
	end
	local count = math.clamp(math.floor(product.Count or 1), 1, 10)
	local remembered = CapsuleService.promptedLucky(player, productKey)
	local lucky = remembered == true or CapsuleService.tripleLucky(player, data, clock())
	local kinds = CapsuleService.roll(product.Capsule, count, lucky, newRandom(player))
	local woken, missing, left = add(data, kinds, true, true)
	missing += count - #kinds
	local list = prompts[player]
	if list then
		list[productKey] = nil
	end
	DataService.changed(player)
	local result: Result = { Capsule = product.Capsule, Count = count, Golems = woken, Lucky = lucky }
	Net.fire("CapsuleResult", player, result)
	opened(player, { Capsule = product.Capsule, Count = count, Kinds = kindsOf(woken), Lucky = lucky, Source = "Robux" })
	return result, missing, left
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

--[[
	The "Capsule" receipt handler (MonetizationService.register; step 8
	contract): opens the product's capsules with grantProduct (paid, locked,
	past InventoryCap up to MaxSaved; the stored prompt's Triple Lucky) and
	keeps the golems that don't fit past MaxSaved as a pending-golem credit
	(data.Golems.Pending, { Kind, Paid = true }), never coins. Refused
	(false, nothing written: the receipt waits) when even the credit has no
	room (GolemConfig.MaxPending). No yield.
]]
local function grantCapsule(player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	if not entry.Capsule or not CapsuleConfig.ById[entry.Capsule] or DataService.get(player) ~= data then
		return false
	end
	local count = math.clamp(math.floor(entry.Count or 1), 1, 10)
	local fits = math.max(0, GolemConfig.MaxSaved - GolemConfig.count(data.Golems))
	local waiting = if type(data.Golems) == "table" and type(data.Golems.Pending) == "table" then #data.Golems.Pending else 0
	if count - fits > GolemConfig.MaxPending - waiting then
		return false
	end
	local result, _missing, left = CapsuleService.grantProduct(player, entry.Key)
	if not result then
		return false
	end
	if #left > 0 then
		local pending = pendingOf(data)
		for _, kind in left do
			table.insert(pending, { Kind = kind, Paid = true })
		end
		Net.fire("Notify", player, {
			Text = `Your golem inventory is full: {#left} golem{if #left == 1 then "" else "s"} will wake as soon as there is room.`,
			Kind = "Info",
		})
	end
	return true
end

--[[
	Wakes the pending-golem credit (data.Golems.Pending) into the inventory
	while there is room (paid golems: up to MaxSaved), oldest first, Paid
	and Locked. Kinds this server doesn't know stay waiting. Returns how
	many woke. Runs on every load and save change; no yield.
]]
function CapsuleService.wakePending(player: Player): number
	local data = DataService.get(player)
	local golems = if data then data.Golems else nil
	local pending = if type(golems) == "table" then golems.Pending else nil
	if not data or type(pending) ~= "table" or #pending == 0 then
		return 0
	end
	local kinds: { string } = {}
	local stay = {}
	local room = GolemConfig.MaxSaved - GolemConfig.count(golems)
	for _, entry in pending do
		local kind = if type(entry) == "table" then entry.Kind else nil
		if #kinds < room and type(kind) == "string" and GolemConfig.ById[kind] then
			table.insert(kinds, kind)
		else
			table.insert(stay, entry)
		end
	end
	if #kinds == 0 then
		return 0
	end
	local woken, _missing, left = add(data, kinds, true, true)
	for _, kind in left do
		table.insert(stay, { Kind = kind, Paid = true })
	end
	table.clear(pending)
	for i, entry in stay do
		pending[i] = entry
	end
	if #woken > 0 then
		DataService.changed(player)
		Net.fire("Notify", player, {
			Text = `{#woken} golem{if #woken == 1 then "" else "s"} from your Royal Capsules woke up!`,
			Kind = "Reward",
		})
	end
	return #woken
end

-- Registers the "Capsule" receipt handler (init(); idempotent).
function CapsuleService.registerGrants()
	MonetizationService.register("Capsule", grantCapsule)
end

-- A Royal prompt closed (MarketplaceService.PromptProductPurchaseFinished):
-- without a purchase its stored state is forgotten (a later purchase made
-- another way uses the odds of its own moment, grantProduct).
local function purchaseFinished(player: Player, productId: number, purchased: boolean)
	local list = prompts[player]
	if purchased or not list then
		return
	end
	for key in list do
		local product = MonetizationConfig.get(key)
		if product and product.Id == productId then
			list[key] = nil
		end
	end
end

--[[
	Step 8 calls this (or Receipts.setReady) with true once its
	ProcessReceipt handler takes receipts (grantProduct for Royal capsules).
	It is the one receipts gate for every Robux product (src/server/Receipts):
	until then a live product still answers "ComingSoon" and is never
	prompted. Also sets the ReplicatedStorage attribute ReceiptsAttribute for
	the clients' cards.
]]
function CapsuleService.setReceiptsReady(ready: boolean)
	Receipts.setReady(ready)
end

function CapsuleService.receiptsReady(): boolean
	return Receipts.ready()
end

local function remember(player: Player, productKey: string, lucky: boolean, data: { [string]: any })
	local list = prompts[player]
	if not list then
		list = {}
		prompts[player] = list
	end
	local now = clock()
	local untilTime = now + MonetizationConfig.PromptMemorySeconds
	local boostEnd = BoostConfig.untilOf(data.Boosts, "TripleLucky")
	if lucky and boostEnd + CapsuleService.LuckyGrace > now then
		-- boosted by the coin-bought boost: never past its end + PurchaseGrace
		untilTime = math.min(untilTime, boostEnd + CapsuleService.PurchaseGrace)
	end
	list[productKey] = { Product = productKey, TripleLucky = lucky, At = now, Until = untilTime }
end

local function refuse(player: Player, reason: string, capsuleId: string?)
	Net.fire("ActionResult", player, { Action = "Capsule", Op = "Open", Ok = false, Reason = reason, Id = capsuleId })
	if reason == "OddsChanged" then
		pushState(player) -- the client shows the odds that hold now
	end
end

-- A Robux capsule request: PurchasePrompt { Product, Status } (see the
-- header), or "OddsChanged" (ActionResult) when the shown odds no longer hold.
local function promptRobux(player: Player, capsuleId: string, count: number, restricted: boolean, shown: boolean?)
	local key = CapsuleConfig.product(capsuleId, count)
	local product = if key then MonetizationConfig.get(key) else nil
	if not key or not product then
		Net.fire("ActionResult", player, { Action = "Capsule", Op = "Open", Ok = false, Reason = "BadCount", Id = capsuleId })
		return
	end
	local data = DataService.get(player)
	local full = data ~= nil and GolemConfig.room(data.Golems) < count
	local status = MonetizationConfig.promptStatus(key, restricted, nil, full)
	-- step 8's receipt handler isn't there yet: never take Robux for nothing
	status = Receipts.gate(status)
	if status == "Prompt" and not data then
		status = "Unknown" -- the player left while Policy answered
	elseif status == "Prompt" and data then
		local odds = CapsuleService.oddsFor(player, data, clock(), shown)
		if odds == nil then
			refuse(player, "OddsChanged", capsuleId)
			return
		end
		local ok, err = pcall(function(): boolean
			prompter(player, product.Id)
			return true
		end)
		if ok then
			remember(player, key, odds == true, data)
			status = "Prompted"
		else
			warn(`[CapsuleService] prompt for {key} failed: {err}`)
			status = "Unknown"
		end
	end
	Net.fire("PurchasePrompt", player, { Product = key, Status = status })
end

---------------------------------------------------------------- requests

-- CapsuleAction ("Open", { Capsule, Count, Lucky? }): see the header.
local function onCapsuleAction(player: Player, action: any, arg: any)
	if action ~= "Open" then
		Net.fire("ActionResult", player, {
			Action = "Capsule",
			Op = Guard.string(action, 16) or "",
			Ok = false,
			Reason = "BadCapsule",
		})
		return
	end
	local args = Guard.table(arg, MAX_PAYLOAD)
	local capsuleId = if args then Guard.string(args.Capsule, MAX_ID_LENGTH) else nil
	local capsule = if capsuleId then CapsuleConfig.ById[capsuleId] else nil
	if not capsule or not capsuleId then
		refuse(player, "BadCapsule", nil)
		return
	end
	local count = if args then Guard.integer(args.Count, 1, 10) else nil
	-- (a Robux capsule may also come in the Store's own counts: Royal x5)
	if not count or not (CapsuleConfig.validCount(count) or CapsuleConfig.product(capsuleId, count) ~= nil) then
		refuse(player, "BadCount", capsuleId)
		return
	end
	if not DataService.get(player) then
		refuse(player, "BadCapsule", capsuleId)
		return
	end
	-- the odds the client showed (junk = not sent)
	local shown = if args then Guard.boolean(args.Lucky) else nil
	-- the policy first (it may yield once): the quote / spend / grant below doesn't yield
	local restricted = CapsuleConfig.isPaidRandom(capsuleId) and Policy.paidRandomRestricted(player)
	if capsule.Currency == "Robux" then
		promptRobux(player, capsuleId, count, restricted, shown)
		return
	end
	if restricted then
		refuse(player, "Restricted", capsuleId)
		return
	end
	local ok, reason, result = CapsuleService.openCoins(player, capsuleId, count, shown)
	if not ok or not result then
		refuse(player, reason or "BadCapsule", capsuleId)
		return
	end
	Net.fire("CapsuleResult", player, result)
end

---------------------------------------------------------------- the stall

local function openView(player: Player, stall: Instance)
	if not DataService.get(player) then
		return
	end
	Net.fire("OpenUI", player, "Capsules", { Stall = stall })
end

-- Where the prompt goes: in front of the stall's pedestal (the OddsBoard
-- faces the stall's front), at chest height.
local function promptPoint(stall: Model): (BasePart?, CFrame)
	local base = stall.PrimaryPart or stall:FindFirstChild("CapsuleMachine", true)
	if not base or not base:IsA("BasePart") then
		return nil, CFrame.new()
	end
	local part = base :: BasePart
	local board = stall:FindFirstChild("OddsBoard", true)
	local front = if board and board:IsA("BasePart") then board.CFrame.LookVector else Vector3.zero
	local flat = Vector3.new(front.X, 0, front.Z)
	local radius = math.max(part.Size.Y, part.Size.Z) / 2
	local offset = if flat.Magnitude > 0.01 then flat.Unit * (radius + 0.6) else Vector3.zero
	local world = part.CFrame.Position + offset + Vector3.new(0, 3, 0)
	return part, part.CFrame:ToObjectSpace(CFrame.new(world))
end

local function hookStall(instance: Instance)
	if hooked[instance] or not instance:IsA("Model") then
		return
	end
	local stall = instance :: Model
	local part, offset = promptPoint(stall)
	if not part then
		return
	end
	hooked[instance] = true
	local old = part:FindFirstChild(CapsuleService.PointName)
	if old then
		old:Destroy()
	end
	local point = Instance.new("Attachment")
	point.Name = CapsuleService.PointName
	point.CFrame = offset
	point.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CapsuleService.PromptName
	prompt.ActionText = "Capsules"
	prompt.ObjectText = "Golem Capsules"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CapsuleService.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = point
	prompt.Triggered:Connect(function(player: Player)
		openView(player, stall)
	end)
end

local function unhookStall(instance: Instance)
	hooked[instance] = nil
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/Capsules.spec.luau).
CapsuleService._test = {
	action = onCapsuleAction,
	hookStall = hookStall,
	promptPoint = promptPoint,
	open = openView,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setRandom = function(fn: (Player) -> RandomLike)
		newRandom = fn
	end,
	setPrompter = function(fn: (Player, number) -> ())
		prompter = fn
	end,
	setPlayers = function(fn: () -> { Player })
		listPlayers = fn
	end,
	setPushState = function(fn: (Player) -> ())
		pushState = fn
	end,
	setPublish = function(fn: (boolean) -> ())
		Receipts._test.setPublisher(fn)
	end,
	purchaseFinished = purchaseFinished,
	announce = announce,
	prompts = function(player: Player): { [string]: Prompt }?
		return prompts[player]
	end,
	reset = function()
		table.clear(callbacks)
		table.clear(prompts)
		Receipts._test.reset()
		clock = os.time
		listPlayers = function(): { Player }
			return Players:GetPlayers()
		end
		pushState = function(player: Player)
			StateService.push(player)
		end
	end,
}

function CapsuleService.init()
	Net.on("CapsuleAction", onCapsuleAction)
	-- step 8: Royal capsule receipts; the pending-golem credit wakes when there is room
	CapsuleService.registerGrants()
	DataService.onLoaded(function(player: Player)
		CapsuleService.wakePending(player)
	end)
	DataService.onChanged(function(player: Player)
		CapsuleService.wakePending(player)
	end)
end

function CapsuleService.start()
	Players.PlayerRemoving:Connect(function(player: Player)
		prompts[player] = nil
	end)
	-- a Royal prompt closed without a purchase: forget its stored state
	local market = game:GetService("MarketplaceService")
	market.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			purchaseFinished(player, productId, purchased)
		end
	end)
	-- ask PolicyService early: the client hides paid random items until it knows
	for _, player in Players:GetPlayers() do
		Policy.prefetch(player)
	end
	Players.PlayerAdded:Connect(Policy.prefetch)
	-- the map is built in WorldService.init, so the stall exists by now
	for _, instance in CollectionService:GetTagged(CapsuleService.Tag) do
		hookStall(instance)
	end
	CollectionService:GetInstanceAddedSignal(CapsuleService.Tag):Connect(hookStall)
	CollectionService:GetInstanceRemovedSignal(CapsuleService.Tag):Connect(unhookStall)
end

return CapsuleService
