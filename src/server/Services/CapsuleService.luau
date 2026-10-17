--[[
	CapsuleService: golem capsules (step 7, CapsuleConfig). Each capsule
	holds a dormant golem core; opening one wakes a random golem
	(GolemConfig) into the player's inventory.

	- The CapsuleStall (tag, a Model in the lobby: PrimaryPart = the pedestal
	  "CapsuleMachine"): this service adds a "Capsules" prompt in front of the
	  big capsule at runtime; it opens the capsule view (OpenUI "Capsules"
	  { Stall }). Opening works anywhere (the side menu too), so the server
	  checks no range.
	- CapsuleAction ("Open", { Capsule, Count }) (Net, rate limited; Count
	  1, 3 or 10):
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
	                   "Full" when the inventory can't take Count more). A
	                   "Prompted" answer stores { Product, TripleLucky, At } for
	                   the player (the latest prompt per product, kept
	                   MonetizationConfig.PromptMemorySeconds): step 8's
	                   ProcessReceipt opens the capsules with that Triple Lucky
	                   state (grantProduct), so the odds the player saw are the
	                   odds they get.
	  Paid random items (CapsuleConfig.isPaidRandom: Royal always, coin
	  capsules only while coins can be bought with Robux) are refused
	  ("Restricted") where PolicyService ArePaidRandomItemsRestricted is true
	  (src/server/Policy.luau; asked BEFORE the quote, it may yield once).
	  Every request the server reads gets one answer: a CapsuleResult, an
	  ActionResult { Action = "Capsule", Op = "Open", Ok = false, Reason
	  (CapsuleConfig.Reasons), Id = capsule } or a PurchasePrompt.
	- Triple Lucky: Bonuses.tripleLucky (data.Boosts.TripleLuckyUntil and any
	  later source), plus LuckyGrace seconds after it ran out: the client shows
	  the boosted odds right up to the end, and a request sent in its last
	  moment arrives a little later, so it still gets the odds it showed.
	- Rolls: a fresh Random per call, seeded from the clock, the player and a
	  counter (swappable for the tests).
	- Data: golems through GolemConfig.add, Stats.CapsulesOpened counts every
	  golem woken; DataService.changed after every grant (EconomyService.spend
	  calls it too). The equipped golems' bonuses reach every system through
	  Bonuses (provider "Golems", podium income via EconomyService).
	- A Legendary or Mythic golem is announced to the other players (Notify
	  "Discovery").
	- Hooks for other packages: grantFree (the wheel's capsule prize: no
	  price, CapsuleResult with Free = true), grantProduct (step 8 receipts:
	  paid golems may pass the inventory cap up to GolemConfig.MaxSaved,
	  Paid = true), promptedLucky, onOpened(callback).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.Config.BoostConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Guard = require(script.Parent.Parent.Guard)
local Policy = require(script.Parent.Parent.Policy)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

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
export type Prompt = { Product: string, TripleLucky: boolean, At: number }
type RandomLike = { NextNumber: (self: any) -> number }

CapsuleService.Tag = "CapsuleStall"
CapsuleService.PromptName = "CapsulePrompt"
CapsuleService.PointName = "CapsulePromptPoint"
CapsuleService.LuckyGrace = 3 -- seconds Triple Lucky still counts after it ran out (see the header)
CapsuleService.AnnounceFrom = "Legendary" -- golems this rare are announced to the server
CapsuleService.PromptDistance = 12

local MAX_PAYLOAD = 4
local MAX_ID_LENGTH = 32

local callbacks: { OpenedCallback } = {}
-- player -> product key -> the prompt the player saw (step 8 contract)
local prompts: { [Player]: { [string]: Prompt } } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local seedCounter = 0

-- Swappable for the Lune tests.
local clock: () -> number = os.time
local newRandom: (player: Player) -> RandomLike = function(player: Player): RandomLike
	seedCounter = (seedCounter + 1) % 1e6
	local seed = math.floor((os.clock() * 1e4) % 2e9) + seedCounter * 7919 + (player.UserId % 1e6) * 104729
	return Random.new(seed % 2 ^ 31) :: any
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

-- Is Triple Lucky on for this player's capsules now (see the header)?
function CapsuleService.tripleLucky(player: Player, data: { [string]: any }, now: number): boolean
	if Bonuses.tripleLucky(Bonuses.stats(player)) then
		return true
	end
	return BoostConfig.untilOf(data.Boosts, "TripleLucky") + CapsuleService.LuckyGrace > now
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
-- DataService.changed). Returns the woken golems and how many didn't fit
-- (only with `overCap`, past GolemConfig.MaxSaved; otherwise the caller
-- checked the room first).
local function add(data: { [string]: any }, kinds: { string }, overCap: boolean?, paid: boolean?): ({ Woken }, number)
	if type(data.Golems) ~= "table" then
		data.Golems = { Owned = {}, Equipped = {}, NextId = 1 }
	end
	local woken: { Woken } = {}
	for _, kind in kinds do
		local entry = GolemConfig.add(data.Golems, kind, overCap, paid)
		if entry then
			table.insert(woken, { Id = entry.Id, Kind = entry.Kind })
		end
	end
	if type(data.Stats) ~= "table" then
		data.Stats = {}
	end
	local opened = tonumber(data.Stats.CapsulesOpened) or 0
	data.Stats.CapsulesOpened = (if opened == opened and opened >= 0 then math.floor(opened) else 0) + #woken
	return woken, #kinds - #woken
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
	with no yield in between. Returns (true, nil, Result) or (false, reason)
	with a CapsuleConfig.Reasons code. No policy check here (the request
	handler asks Policy first).
]]
function CapsuleService.openCoins(player: Player, capsuleId: string, count: number): (boolean, string?, Result?)
	local data = DataService.get(player)
	local capsule = CapsuleConfig.ById[capsuleId]
	if not data or not capsule or capsule.Currency ~= "Coins" then
		return false, "BadCapsule", nil
	end
	if not CapsuleConfig.validCount(count) then
		return false, "BadCount", nil
	end
	local price = CapsuleConfig.price(capsuleId, count, data.BlasterLevel)
	if price == nil then
		return false, "BadCapsule", nil
	end
	if GolemConfig.room(data.Golems) < count then
		return false, "InventoryFull", nil
	end
	if not EconomyService.canAfford(player, price) then
		return false, "NoCoins", nil
	end
	local lucky = CapsuleService.tripleLucky(player, data, clock())
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
	`count` (default 1): the caller pays its fallback instead. Sends the
	CapsuleResult (Free = true) and returns it.
]]
function CapsuleService.grantFree(player: Player, capsuleId: string, count: number?): (Result?, string?)
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
	Net.fire("CapsuleResult", player, result)
	opened(player, { Capsule = capsuleId, Count = n, Kinds = kindsOf(woken), Lucky = lucky, Source = "Free" })
	return result, nil
end

---------------------------------------------------------------- Robux capsules (step 8 hooks)

-- The Triple Lucky state the player saw when the server last prompted
-- `productKey` (nil: no prompt in the last PromptMemorySeconds).
function CapsuleService.promptedLucky(player: Player, productKey: string, now: number?): boolean?
	local list = prompts[player]
	local prompt = if list then list[productKey] else nil
	if not prompt then
		return nil
	end
	if (now or clock()) - prompt.At > MonetizationConfig.PromptMemorySeconds then
		list[productKey] = nil
		return nil
	end
	return prompt.TripleLucky
end

--[[
	Step 8: ProcessReceipt for a Royal capsule product (call it on the server
	that holds the session lock, then save). Opens the product's capsules
	with the Triple Lucky state stored at its prompt (else the current one);
	the golems are paid (Paid = true) and may pass the inventory cap up to
	GolemConfig.MaxSaved. Returns the CapsuleResult (also sent) and how many
	golems didn't fit past MaxSaved (the receipt handler compensates those).
	nil for a product that isn't a capsule.
]]
function CapsuleService.grantProduct(player: Player, productKey: string): (Result?, number)
	local data = DataService.get(player)
	local product = MonetizationConfig.get(productKey)
	if not data or not product or not product.Capsule or not CapsuleConfig.ById[product.Capsule] then
		return nil, 0
	end
	local count = math.clamp(math.floor(product.Count or 1), 1, 10)
	local remembered = CapsuleService.promptedLucky(player, productKey)
	local lucky = if remembered ~= nil then remembered else CapsuleService.tripleLucky(player, data, clock())
	local kinds = CapsuleService.roll(product.Capsule, count, lucky, newRandom(player))
	local woken, missing = add(data, kinds, true, true)
	missing += count - #kinds
	local list = prompts[player]
	if list then
		list[productKey] = nil
	end
	DataService.changed(player)
	local result: Result = { Capsule = product.Capsule, Count = count, Golems = woken, Lucky = lucky }
	Net.fire("CapsuleResult", player, result)
	opened(player, { Capsule = product.Capsule, Count = count, Kinds = kindsOf(woken), Lucky = lucky, Source = "Robux" })
	return result, missing
end

local function remember(player: Player, productKey: string, lucky: boolean)
	local list = prompts[player]
	if not list then
		list = {}
		prompts[player] = list
	end
	list[productKey] = { Product = productKey, TripleLucky = lucky, At = clock() }
end

-- A Robux capsule request: PurchasePrompt { Product, Status } (see the header).
local function promptRobux(player: Player, capsuleId: string, count: number, restricted: boolean)
	local key = CapsuleConfig.product(capsuleId, count)
	local product = if key then MonetizationConfig.get(key) else nil
	if not key or not product then
		Net.fire("ActionResult", player, { Action = "Capsule", Op = "Open", Ok = false, Reason = "BadCount", Id = capsuleId })
		return
	end
	local data = DataService.get(player)
	local full = data ~= nil and GolemConfig.room(data.Golems) < count
	local status = MonetizationConfig.promptStatus(key, restricted, nil, full)
	if status == "Prompt" then
		local lucky = data ~= nil and CapsuleService.tripleLucky(player, data, clock())
		local ok, err = pcall(function(): boolean
			prompter(player, product.Id)
			return true
		end)
		if ok then
			remember(player, key, lucky)
			status = "Prompted"
		else
			warn(`[CapsuleService] prompt for {key} failed: {err}`)
			status = "Unknown"
		end
	end
	Net.fire("PurchasePrompt", player, { Product = key, Status = status })
end

---------------------------------------------------------------- requests

local function refuse(player: Player, reason: string, capsuleId: string?)
	Net.fire("ActionResult", player, { Action = "Capsule", Op = "Open", Ok = false, Reason = reason, Id = capsuleId })
end

-- CapsuleAction ("Open", { Capsule, Count }): see the header.
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
	if not count or not CapsuleConfig.validCount(count) then
		refuse(player, "BadCount", capsuleId)
		return
	end
	if not DataService.get(player) then
		refuse(player, "BadCapsule", capsuleId)
		return
	end
	-- the policy first (it may yield once): the quote / spend / grant below doesn't yield
	local restricted = CapsuleConfig.isPaidRandom(capsuleId) and Policy.paidRandomRestricted(player)
	if capsule.Currency == "Robux" then
		promptRobux(player, capsuleId, count, restricted)
		return
	end
	if restricted then
		refuse(player, "Restricted", capsuleId)
		return
	end
	local ok, reason, result = CapsuleService.openCoins(player, capsuleId, count)
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
	announce = announce,
	prompts = function(player: Player): { [string]: Prompt }?
		return prompts[player]
	end,
	reset = function()
		table.clear(callbacks)
		table.clear(prompts)
		clock = os.time
		listPlayers = function(): { Player }
			return Players:GetPlayers()
		end
	end,
}

function CapsuleService.init()
	Net.on("CapsuleAction", onCapsuleAction)
end

function CapsuleService.start()
	Players.PlayerRemoving:Connect(function(player: Player)
		prompts[player] = nil
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
