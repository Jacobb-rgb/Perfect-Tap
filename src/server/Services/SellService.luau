--[[
	SellService: Tobin's Sell stall in town (design v2). Money comes mainly
	from podiums; ore you don't need is sold to Tobin the Miner.

	- SellCounter (tag, a BasePart): a "Sell Ore" prompt opens the Sell view
	  (OpenUI "Sell" { Hands, Counter }). The view lists the Ore Pen
	  (data.Storage, from the State snapshot) and your backpack ("Hands":
	  the protocol kept its name; CarryService's data.BackpackItems, added to
	  every State snapshot by this service).
	- SellAction (Net, rate limited), only within SELL_RANGE of a counter:
	    ("Sell", { Key, Count, From = "Pen" | "Hands" })
	    ("SellAll", { Filter = "Dirty" | "AllButBest", From = "Pen" | "Hands" | nil })
	  "Dirty" sells Dirty Ore (raw ore). "AllButBest" sells everything that
	  is not Dirty Ore, but keeps the KEEP_BEST cleaned ores with the highest
	  podium income. At most EconomyConfig.sellCap(From) items per request (the pen
	  50, the backpack 3000: a whole backpack in one press).
	- SellBin (tag, a Model with a child part "Intake"): items thrown or
	  dropped in are sold (an IntakeService zone). The item's OWNER is paid,
	  never whoever threw it, so dumping someone else's ore gains nothing.
	- Podium ore (data.Podiums) is never sold here: only data.Storage and
	  the backpack are ever touched.

	Price = ItemData.value (Raw = Dirty Ore pays the raw price; its name is
	revealed in the toast after the sale), times the player's sell bonus
	(Bonuses.sellAmount: the Midas enchant, SellValue golems, the Royal
	Railway collection; the Sell view shows the same numbers with
	State.Bonuses.SellMult). Every sale: EconomyService.award
	(source "Sell"), Stats.ItemsSold, DataService.changed, Net "Earned"
	{ Amount, Source = "Sell", Position, Count } for the coin burst, and a
	toast "Tobin paid $1.2K for 3 items".

	Selling never yields between taking items away (pen entries removed,
	carried items taken off the stack and absorbed) and paying, so two
	requests can't sell the same item twice.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DropperConfig = require(Shared.Config.DropperConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local SecretOreConfig = require(Shared.Config.SecretOreConfig)
local PromptConfig = require(Shared.Config.PromptConfig)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Bonuses = require(script.Parent.Parent.Bonuses)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local IntakeService = require(script.Parent.IntakeService)
local EconomyService = require(script.Parent.EconomyService)

local SellService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord
export type From = "Pen" | "Hands"
export type SoldCallback = (Player, Desc, number) -> ...any

-- one item picked for a sale (from the pen or the hands)
type Pick = { From: From, Desc: Desc, Entry: Desc?, Key: string? }

-- studs from a SellCounter's surface the server accepts (the prompt itself reaches less)
SellService.Range = 20
-- "Sell all except the best N"
SellService.KeepBest = 4
SellService.NpcName = "Tobin the Miner"

local PROMPT_DISTANCE = 12
local MAX_KEY_LENGTH = 80
-- bin sales of one owner closer together than this become one toast/popup
local BIN_BATCH = 0.3
-- names listed in a "the dirty ore was ..." reveal
local MAX_REVEAL_NAMES = 4
-- a viewer this far from every counter stops getting hand refreshes
local VIEW_FORGET_RANGE = 40

type BinBatch = { Total: number, Count: number, Descs: { Desc }, Position: Vector3 }

local counters: { BasePart } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local viewers: { [Player]: boolean } = {}
local binBatches: { [Player]: BinBatch } = {}
local soldCallbacks: { SoldCallback } = {}

-- Listeners: (player, desc, value) after every single item sold (value =
-- Tobin's base price, before the player's sell bonus).
function SellService.onSold(callback: SoldCallback)
	table.insert(soldCallbacks, callback)
end

-- Tells the onSold listeners about an item sold somewhere else (the Sell Box
-- machine pays by itself and calls this after paying).
function SellService.notifySold(player: Player, desc: Desc, value: number)
	for _, callback in soldCallbacks do
		task.spawn(callback, player, desc, value)
	end
end

---------------------------------------------------------------- prices

-- Coins Tobin pays for one item (0 = not a real item).
function SellService.priceOf(desc: Desc): number
	if type(desc) ~= "table" or type(desc.K) ~= "string" or type(desc.O) ~= "string" then
		return 0
	end
	-- a dropper's Drop is not Tobin's: only a Sell Box sells it (boxPriceOf)
	if DropperConfig.isDrop(desc) then
		return 0
	end
	local key = ItemData.storageKey(desc)
	if not ItemData.parseKey(key) then
		return 0
	end
	return ItemData.value(desc.K, desc.O, desc.G, desc.R)
end

-- Coins a Sell Box pays for one item before bonuses: Tobin's price, and a
-- dropper's Drop (DropperConfig.dropValue: the dropper's id and the laser's
-- mark, read on the server; 0 for a forged one), which Tobin never buys.
function SellService.boxPriceOf(desc: Desc): number
	if DropperConfig.isDrop(desc) then
		return if DropperConfig.validDrop(desc) then ItemData.value(desc.K, desc.O, desc.G, desc.R) else 0
	end
	return SellService.priceOf(desc)
end

local function isDirty(desc: Desc): boolean
	return desc.K == "Raw"
end

local function rarityOrder(oreId: string): number
	local ore = OreData.ById[oreId]
	local info = ore and Rarity.ById[ore.Rarity]
	return if info then info.Order else 0
end

-- Storage key -> count of the items in the player's backpack Tobin buys (the
-- keys this build reads; dusty relics go to the guild, never to him).
function SellService.handsSummary(player: Player): { [string]: number }
	local summary: { [string]: number } = {}
	for _, stack in CarryService.stacks(player) do
		if SellService.priceOf(stack.Desc) > 0 then
			summary[stack.Key] = stack.Count
		end
	end
	return summary
end

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

-- The counter the player stands at (within `range`), or nil.
local function counterNear(player: Player, range: number): BasePart?
	local root = Guard.rootPart(player)
	if not root then
		return nil
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, counter in counters do
		if counter.Parent then
			local distance = distanceToPart(counter, root.Position)
			if distance <= range and distance < bestDistance then
				best, bestDistance = counter, distance
			end
		end
	end
	return best
end

-- Where the coin burst appears: on the customer side of the counter top.
local function popupPosition(counter: BasePart): Vector3
	local point = counter:FindFirstChild("SellPromptPoint")
	if point and point:IsA("Attachment") then
		return (counter.CFrame * point.CFrame).Position + Vector3.new(0, 1, 0)
	end
	return counter.CFrame.Position + Vector3.new(0, counter.Size.Y / 2 + 1.5, 0)
end

---------------------------------------------------------------- toasts

local function oreName(oreId: string): string
	local ore = OreData.ById[oreId]
	return if ore then ore.Name else oreId
end

-- " It was Gold!" / " The Dirty Ore was: 2x Coal, Gold." / "" (no dirty ore)
function SellService.revealText(descs: { Desc }): (string, string?)
	local counts: { [string]: number } = {}
	local order: { string } = {}
	local best, bestOrder = nil :: string?, 0
	local total = 0
	for _, desc in descs do
		if isDirty(desc) then
			total += 1
			if not counts[desc.O] then
				counts[desc.O] = 0
				table.insert(order, desc.O)
			end
			counts[desc.O] += 1
			local rank = rarityOrder(desc.O)
			if rank > bestOrder then
				local ore = OreData.ById[desc.O]
				best, bestOrder = if ore then ore.Rarity else nil, rank
			end
		end
	end
	if total == 0 then
		return "", nil
	end
	if total == 1 then
		return ` It was {oreName(order[1])}!`, best
	end
	-- rarest first, then most
	table.sort(order, function(a, b)
		local ra, rb = rarityOrder(a), rarityOrder(b)
		if ra ~= rb then
			return ra > rb
		elseif counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	local parts = {}
	for i, oreId in order do
		if i > MAX_REVEAL_NAMES then
			table.insert(parts, "...")
			break
		end
		local n = counts[oreId]
		table.insert(parts, if n > 1 then `{n}x {oreName(oreId)}` else oreName(oreId))
	end
	return ` The Dirty Ore was: {table.concat(parts, ", ")}.`, best
end

function SellService.paidText(total: number, count: number): string
	local items = if count == 1 then "1 item" else `{Format.commas(count)} items`
	return `Tobin paid {Format.money(total)} for {items}.`
end

---------------------------------------------------------------- paying

-- The toast after a sale: "Tobin paid $X for N items." plus the Dirty Ore
-- reveal (coloured by the rarest revealed ore from Rare up).
local function saleToast(descs: { Desc }, total: number): { [string]: any }
	local reveal, rarityId = SellService.revealText(descs)
	local message: { [string]: any } = { Text = SellService.paidText(total, #descs) .. reveal, Kind = "Reward" }
	local info = rarityId and Rarity.ById[rarityId]
	if info and info.Order >= 3 then
		message.Rarity = rarityId
	end
	return message
end

--[[
	Pays the player for items that are already gone (out of the pen or out
	of the world): one award, stats, DataService.changed, the Earned popup
	and the toast.
]]
local function payout(player: Player, data: { [string]: any }, descs: { Desc }, base: number, position: Vector3)
	local count = #descs
	if count == 0 then
		return
	end
	local total = Bonuses.sellAmount(Bonuses.stats(player), base)
	local stats = data.Stats
	if type(stats) == "table" then
		local before = tonumber(stats.ItemsSold) or 0
		stats.ItemsSold = (if before == before then before else 0) + count
	end
	EconomyService.award(player, total, "Sell")
	DataService.changed(player)
	Net.fire("Earned", player, { Amount = total, Source = "Sell", Position = position, Count = count })
	Net.fire("Notify", player, saleToast(descs, total))
	for _, desc in descs do
		local value = SellService.priceOf(desc)
		for _, callback in soldCallbacks do
			task.spawn(callback, player, desc, value)
		end
	end
end

-- Takes the picked items away and returns what was really taken.
-- No yields in here: the caller pays right after.
local function takePicks(player: Player, data: { [string]: any }, picks: { Pick }): ({ Desc }, number)
	local taken: { Desc } = {}
	local total = 0
	-- pen entries by identity (the list shifts as entries go)
	local fromPen: { [any]: boolean } = {}
	local wantPen = false
	for _, pick in picks do
		if pick.From == "Pen" and pick.Entry then
			fromPen[pick.Entry] = true
			wantPen = true
		end
	end
	if wantPen and type(data.Storage) == "table" then
		local storage = data.Storage :: { Desc }
		for i = #storage, 1, -1 do
			local entry = storage[i]
			if fromPen[entry] then
				fromPen[entry] = nil
				table.remove(storage, i)
				local desc = { K = entry.K, O = entry.O, G = entry.G, R = entry.R }
				local price = SellService.priceOf(desc)
				if price > 0 then
					table.insert(taken, desc)
					total += price
				end
			end
		end
	end
	-- backpack items by key (the backpack keeps counts)
	local fromBackpack: { [string]: number } = {}
	for _, pick in picks do
		local key = pick.Key
		if pick.From == "Hands" and key then
			fromBackpack[key] = (fromBackpack[key] or 0) + 1
		end
	end
	for key, n in fromBackpack do
		for _, desc in
			CarryService.take(player, function(d: Desc): boolean
				return ItemData.storageKey(d) == key
			end, n)
		do
			local price = SellService.priceOf(desc)
			if price > 0 then
				table.insert(taken, desc)
				total += price
			end
		end
	end
	return taken, total
end

-- Everything the player could sell right now: the backpack's items (one pick
-- per item, stack by stack), then pen entries. Junk entries are never picked.
local function candidates(player: Player, data: { [string]: any }): { Pick }
	local list: { Pick } = {}
	for _, stack in CarryService.stacks(player) do
		if SellService.priceOf(stack.Desc) > 0 then
			for _ = 1, stack.Count do
				table.insert(list, { From = "Hands", Desc = stack.Desc, Key = stack.Key })
			end
		end
	end
	if type(data.Storage) == "table" then
		for _, entry in data.Storage :: { Desc } do
			if type(entry) == "table" and SellService.priceOf(entry) > 0 then
				table.insert(list, { From = "Pen", Desc = entry, Entry = entry })
			end
		end
	end
	return list
end

-- The KEEP_BEST cleaned ores with the highest income, by identity.
local function bestKept(list: { Pick }): { [Pick]: boolean }
	local clean: { Pick } = {}
	for _, pick in list do
		if ItemData.income(pick.Desc) > 0 then
			table.insert(clean, pick)
		end
	end
	local position: { [Pick]: number } = {}
	for i, pick in clean do
		position[pick] = i
	end
	table.sort(clean, function(a, b)
		local ia, ib = ItemData.income(a.Desc), ItemData.income(b.Desc)
		if ia ~= ib then
			return ia > ib
		end
		-- equal income: keep what is in the pen, then the older entry
		if a.From ~= b.From then
			return a.From == "Pen"
		end
		return position[a] < position[b]
	end)
	local kept: { [Pick]: boolean } = {}
	for i = 1, math.min(SellService.KeepBest, #clean) do
		kept[clean[i]] = true
	end
	return kept
end

---------------------------------------------------------------- requests

local function deny(player: Player, text: string)
	Net.fire("Notify", player, { Text = text, Kind = "Deny" })
	-- the view may be out of date: send a fresh snapshot
	StateService.push(player)
end

local function sellKey(player: Player, data: { [string]: any }, counter: BasePart, arg: { [any]: any })
	local key = Guard.string(arg.Key, MAX_KEY_LENGTH)
	local desc = key and ItemData.parseKey(key)
	local from = arg.From
	local count = Guard.integer(arg.Count, 1, EconomyConfig.sellCap(from))
	if not key or not desc or not count or (from ~= "Pen" and from ~= "Hands") then
		return
	end
	if desc.K == "Raw" and SecretOreConfig.isSecret(desc.O) then
		deny(player, "Something special is inside this ore: clean it at the Cleaning Station first!")
		return
	end
	local picks: { Pick } = {}
	for _, pick in candidates(player, data) do
		if #picks >= count then
			break
		end
		if pick.From == from and ItemData.storageKey(pick.Desc) == key then
			table.insert(picks, pick)
		end
	end
	if #picks == 0 then
		deny(player, if from == "Pen" then "That's not in your Ore Pen anymore." else "That's not in your backpack anymore.")
		return
	end
	local taken, total = takePicks(player, data, picks)
	payout(player, data, taken, total, popupPosition(counter))
end

local function sellAll(player: Player, data: { [string]: any }, counter: BasePart, arg: { [any]: any })
	local filter = arg.Filter
	local from = arg.From
	if filter ~= "Dirty" and filter ~= "AllButBest" then
		return
	end
	if from ~= nil and from ~= "Pen" and from ~= "Hands" then
		return
	end
	local list = {}
	for _, pick in candidates(player, data) do
		-- a SECRET ore is never sold in a batch (owner 2026-10-29): only on its own, by choice
		if not SecretOreConfig.isSecret(pick.Desc.O) then
			table.insert(list, pick)
		end
	end
	local kept = if filter == "AllButBest" then bestKept(list) else {}
	local picks: { Pick } = {}
	local counted: { [string]: number } = { Pen = 0, Hands = 0 }
	local left = 0
	for _, pick in list do
		local wanted = (from == nil or pick.From == from)
			and (if filter == "Dirty" then isDirty(pick.Desc) else not isDirty(pick.Desc) and not kept[pick])
		if wanted then
			-- each section to its own cap (a whole backpack at once, the pen 50 at a time)
			if counted[pick.From] < EconomyConfig.sellCap(pick.From) then
				counted[pick.From] += 1
				table.insert(picks, pick)
			else
				left += 1
			end
		end
	end
	if #picks == 0 then
		deny(player, if filter == "Dirty" then "You have no Dirty Ore to sell." else "Nothing to sell: Tobin leaves your best ores to you.")
		return
	end
	local taken, total = takePicks(player, data, picks)
	payout(player, data, taken, total, popupPosition(counter))
	if left > 0 then
		Net.fire("Notify", player, {
			Text = `{left} more left: Tobin buys {EconomyConfig.Sell.MaxPerRequest} at a time from your Ore Pen.`,
			Kind = "Info",
		})
	end
end

local function onSellAction(player: Player, action: any, arg: any)
	local data = DataService.get(player)
	local args = Guard.table(arg, 8)
	if not data or not args or (action ~= "Sell" and action ~= "SellAll") then
		return
	end
	local counter = counterNear(player, SellService.Range)
	if not counter then
		deny(player, "Walk up to Tobin's stall to sell.")
		return
	end
	if action == "Sell" then
		sellKey(player, data, counter, args)
	else
		sellAll(player, data, counter, args)
	end
end

---------------------------------------------------------------- the SellBin

local function flushBin(player: Player)
	local batch = binBatches[player]
	binBatches[player] = nil
	if not batch or not player.Parent then
		return
	end
	Net.fire("Earned", player, { Amount = batch.Total, Source = "Sell", Position = batch.Position, Count = batch.Count })
	Net.fire("Notify", player, saleToast(batch.Descs, batch.Total))
end

--[[
	Sells a loose item (something in the SellBin). Pays the item's owner and
	returns the price; 0 (item left alone) when the owner's data isn't
	loaded or the item isn't a real item.
]]
function SellService.sellRecord(record: ItemRecord, position: Vector3?): number
	if record.State ~= "Loose" then
		return 0
	end
	local owner = Players:GetPlayerByUserId(record.Owner)
	local data = owner and DataService.get(owner)
	if not owner or not data then
		return 0
	end
	local base = SellService.priceOf(ItemService.descOf(record))
	if base <= 0 then
		return 0
	end
	local price = Bonuses.sellAmount(Bonuses.stats(owner), base)
	local at = position or record.Body.CFrame.Position
	-- out of the world first, then paid: no yield in between
	local desc = ItemService.absorb(record)
	local stats = data.Stats
	if type(stats) == "table" then
		local before = tonumber(stats.ItemsSold) or 0
		stats.ItemsSold = (if before == before then before else 0) + 1
	end
	EconomyService.award(owner, price, "Sell")
	DataService.changed(owner)
	for _, callback in soldCallbacks do
		task.spawn(callback, owner, desc, base)
	end
	-- one popup and toast for items landing together
	local batch = binBatches[owner]
	if not batch then
		batch = { Total = 0, Count = 0, Descs = {}, Position = at }
		binBatches[owner] = batch
		task.delay(BIN_BATCH, flushBin, owner)
	end
	batch.Total += price
	batch.Count += 1
	batch.Position = at
	table.insert(batch.Descs, desc)
	return price
end

local function binHandler(bin: BasePart): (ItemRecord) -> ()
	return function(record: ItemRecord)
		local position = bin.CFrame.Position + Vector3.new(0, bin.Size.Y / 2, 0)
		-- a dusty relic: Tobin passes it to the guild, who clean it into the owner's collection
		if record.Kind == "Relic" and record.State == "Loose" then
			ItemService.stash(record, nil)
			return
		end
		if SellService.sellRecord(record, position) > 0 then
			return
		end
		-- not sellable but owned by someone here (junk data): keep it for them
		if record.State == "Loose" and SellService.priceOf(ItemService.descOf(record)) <= 0 then
			local owner = Players:GetPlayerByUserId(record.Owner)
			if owner and DataService.get(owner) then
				ItemService.stash(record, "Tobin can't buy that")
			end
		end
	end
end

---------------------------------------------------------------- hooks

local function openView(player: Player, counter: BasePart)
	if not DataService.get(player) or not counterNear(player, SellService.Range) then
		return
	end
	viewers[player] = true
	Net.fire("OpenUI", player, "Sell", { Hands = SellService.handsSummary(player), Counter = counter })
end

local function hookBin(bin: Instance)
	if hooked[bin] then
		return
	end
	local intake = bin:FindFirstChild("Intake")
	local part = if intake and intake:IsA("BasePart") then intake elseif bin:IsA("BasePart") then bin else nil
	if not part then
		warn("[SellService] a SellBin has no Intake part: " .. bin:GetFullName())
		return
	end
	hooked[bin] = true
	IntakeService.addZone("SellBin", part :: BasePart, binHandler(part :: BasePart))
end

local function hookCounter(counter: Instance)
	if hooked[counter] or not counter:IsA("BasePart") then
		return
	end
	hooked[counter] = true
	local part = counter :: BasePart
	table.insert(counters, part)
	-- the prompt sits on the customer side of the counter top
	local point = Instance.new("Attachment")
	point.Name = "SellPromptPoint"
	point.CFrame = CFrame.new(0, part.Size.Y / 2 + 0.6, -part.Size.Z / 2)
	point.Parent = part
	local prompt = PromptConfig.make({
		Name = "SellOrePrompt",
		ActionText = "Sell Ore",
		ObjectText = SellService.NpcName,
		Distance = PROMPT_DISTANCE,
		Parent = point,
	})
	prompt.Triggered:Connect(function(player: Player)
		openView(player, part)
	end)
end

local function hookTagged(tag: string, hook: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		hook(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
end

-- Carried items changed while the Sell view may be open: refresh it.
local function onCarryChanged(player: Player)
	if not viewers[player] then
		return
	end
	if not counterNear(player, VIEW_FORGET_RANGE) then
		viewers[player] = nil
		return
	end
	StateService.push(player)
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/SellService.spec.luau).
SellService._test = {
	action = onSellAction,
	hookBin = hookBin,
	hookCounter = hookCounter,
	open = openView,
	binHandler = binHandler,
	flushBins = function()
		for player in binBatches do
			flushBin(player)
		end
	end,
	reset = function()
		table.clear(counters)
		table.clear(viewers)
		table.clear(binBatches)
		table.clear(soldCallbacks)
	end,
}

function SellService.init()
	Net.on("SellAction", onSellAction)
	-- what you carry, for the Sell view (refreshed with every State push)
	StateService.addProvider(function(player: Player, _data: { [string]: any }, snapshot: { [string]: any })
		snapshot.Hands = SellService.handsSummary(player)
	end)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("CarryCount"):Connect(function()
			onCarryChanged(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		viewers[player] = nil
		binBatches[player] = nil
	end)
end

function SellService.start()
	-- the map is built in WorldService.init, so Tobin's stall exists by now
	hookTagged("SellBin", hookBin)
	hookTagged("SellCounter", hookCounter)
end

return SellService
