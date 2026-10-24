--[[
	ShopService: the Tech shop at the UPGRADES stall in town (design v2,
	step 3, docs/plans/STEP3_PLAN.md "WP-TechShop"). Machines, machine
	upgrades, Bellows, machine slots and pen automation are bought here for
	coins; the Robux items (big pass, podiums, offline extension, Express
	train) are not sold here. Machines can also be bought at your own base
	(build mode's SHOP button opens the same window there:
	TechShopController.openMachines).

	- UpgradeCounter (tag, a BasePart of the lobby's UPGRADES stall): this
	  service adds a "Tech Shop" prompt at runtime on the customer side of
	  the counter top; it opens the Tech shop view (OpenUI "Tech" { Counter }).
	- ShopBuy (Net, rate limited) { Shop = "Tech", Item, Count?, Level? }
	  (catalog and Item strings: EconomyConfig.TechShop / techItem):
	    <machineId>                 Count (1..TechShop.MaxCount, default 1)
	                                machines into data.MachineInventory, at most
	                                TechShop.MaxOwned (999) of one type
	    "Upgrade:<machineId>:Speed" / ":Quality"  data.MachineUpgrades[id][kind]
	    "Bellows" / "Slots" / "PenAutomation"     data.Upgrades.Bellows /
	                                ExtraSlots / PenAutomation
	  Levelled items buy exactly one level: Level must be the level being
	  bought (the one the card shows), else "Stale" (EconomyConfig.techQuote),
	  so a double tap or a lagging card never buys two levels.
	  Where (ShopService.placeFor): within ShopService.Range of an
	  UpgradeCounter, or (machines only, owner 2026-10-21: the SHOP button
	  in build mode) within GameConfig.BuildRange of your OWN plot, the
	  same PlotService.isNear test build mode uses (BuildService). Upgrades,
	  Bellows, Slots and pen automation still need the counter. Anywhere
	  else "TooFar" (the client closes a counter shop nearer than Range and
	  a base shop nearer than BuildRange, so lag never refuses a BUY).
	- Every ShopBuy the server reads gets a ShopResult { Item, Ok, Reason?,
	  Level?, Count? } (Reason: an EconomyConfig.TechShop.Reasons code; the
	  client shows the text on the card), also one from a player whose save
	  isn't loaded (yet / any more): "BadItem", nothing changes. A
	  successful buy also sends a "Reward" toast; a refused one only the
	  ShopResult (the client shows the reason on the card, or as a toast
	  when the shop is closed), so the player never reads the same message
	  twice. A machine toast says how to place it: "Open BUILD" at your
	  base, "Go to your BASE and open BUILD" at the counter (no key: B,
	  D-pad Up and a tap differ per device; the shop's notes name it).
	- Atomic: quote (techQuote), spend (EconomyService.spend) and write the
	  inventory / level happen in one step with no yield in between, and
	  every table the write needs is made before the coins are taken, so two
	  requests can never both pass the quote and nothing can fail after the
	  coins are gone. A data change always ends with DataService.changed
	  (EconomyService.spend calls it too); the State push that follows
	  refreshes the shop view and the Build menu.
	- ShopService.onBought(callback): stats / analytics / tutorial hooks,
	  (player, Bought) after every successful buy.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local PromptConfig = require(Shared.Config.PromptConfig)
local Placement = require(Shared.Machines.Placement)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)

local ShopService = {}

type TechItem = EconomyConfig.TechItem

-- What a successful buy gave (onBought listeners, tests).
export type Bought = {
	Item: string, -- the ShopBuy Item string
	Kind: EconomyConfig.TechKind,
	Machine: string?, -- Machine and Upgrade items
	Upgrade: string?, -- "Speed" | "Quality"
	Level: number?, -- the new level (levelled items)
	Count: number, -- machines bought (1 for levelled items)
	Price: number, -- coins paid
}
export type BoughtCallback = (Player, Bought) -> ...any
-- Where a buy happened: at an UpgradeCounter in the lobby, or at your own plot (machines only).
export type Place = "Counter" | "Base"

-- studs from an UpgradeCounter's surface the server accepts: the prompt reaches
-- 12, the client closes the shop past 24 (TechShopController), so the server is
-- the lenient side and lag never refuses a BUY from an open shop
ShopService.Range = 30
ShopService.Tag = "UpgradeCounter"
-- the DROPPERS house's porch counter (lobby Districts/Droppers): the same Tech shop, its own prompt words
ShopService.DropperTag = "DropperCounter"
ShopService.PromptName = "TechShopPrompt"
ShopService.PointName = "TechShopPromptPoint"

-- the pen automation steps by level (EconomyConfig.PenAutomation), for the toasts
ShopService.AutomationNames = { "Auto-Sort Billboard", "Train Direct Unload" }

local PROMPT_DISTANCE = 12
local MAX_ITEM_LENGTH = 64
local MAX_PAYLOAD = 8

local counters: { BasePart } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local boughtCallbacks: { BoughtCallback } = {}

-- Listeners: (player, Bought) after every successful Tech shop buy.
function ShopService.onBought(callback: BoughtCallback)
	table.insert(boughtCallbacks, callback)
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

-- The UpgradeCounter the player stands at (within `range`), or nil.
function ShopService.counterNear(player: Player, range: number): BasePart?
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

-- Is the player within GameConfig.BuildRange of their own plot (the test build mode uses)?
function ShopService.nearOwnPlot(player: Player): boolean
	local plotId = PlotService.plotOf(player)
	return plotId ~= nil and PlotService.isNear(player, plotId, GameConfig.BuildRange)
end

-- Where the player may buy `entry` right now: "Base" (a machine, at their
-- own plot), "Counter" (anything, at an UpgradeCounter), or nil (too far).
function ShopService.placeFor(player: Player, entry: TechItem): Place?
	if entry.Kind == "Machine" and ShopService.nearOwnPlot(player) then
		return "Base"
	end
	if ShopService.counterNear(player, ShopService.Range) then
		return "Counter"
	end
	return nil
end

---------------------------------------------------------------- texts

-- "Conveyors", "Iron Boxes", "Cleaning Plants"
function ShopService.plural(name: string): string
	local last = name:sub(-1)
	local lastTwo = name:sub(-2)
	if last == "x" or last == "s" or lastTwo == "ch" or lastTwo == "sh" then
		return name .. "es"
	end
	return name .. "s"
end

local function machineName(id: string?): string
	local machine = if id then MachineData.ById[id] else nil
	return if machine then machine.Name else "machine"
end

-- The toast after a successful buy (`place`: where it was bought, the
-- counter when nil). A machine's says how to place it from there.
function ShopService.boughtText(player: Player?, bought: Bought, place: Place?): string
	if bought.Kind == "Machine" then
		local name = machineName(bought.Machine)
		local how = if place == "Base" then "Open BUILD" else "Go to your BASE and open BUILD"
		if bought.Count == 1 then
			local article = if name:match("^[AEIOUaeiou]") then "an" else "a"
			return `Bought {article} {name}! {how} to place it.`
		end
		return `Bought {bought.Count} {ShopService.plural(name)}! {how} to place them.`
	end
	local level = bought.Level or 0
	if bought.Kind == "Upgrade" then
		local name = machineName(bought.Machine)
		if bought.Upgrade == "Quality" then
			return `{name} Quality level {level}: better grades on every {name}!`
		elseif bought.Upgrade == "Tier" and bought.Machine then
			-- the Furnace's tiers: every furnace of the player turns into the new one
			local tier = MachineData.info(bought.Machine, level)
			return `Every {name} is a {tier.Name} now: it smelts faster!`
		end
		return `{name} Speed level {level}: every {name} works faster!`
	elseif bought.Kind == "Bellows" then
		return `Bellows level {level}: all your machines work faster!`
	elseif bought.Kind == "Slots" then
		local workshop = player ~= nil and Perks.has(player, "Workshop")
		return `More room: {MachineData.machineSlots(level, workshop)} machine slots on your plot!`
	end
	-- as PenService runs them (and TechShopView.Automation says)
	local step = ShopService.AutomationNames[level] or "Pen automation"
	if level == EconomyConfig.PenAutomation.DirectUnload then
		return `{step} unlocked: your train's dirty ore now pours out of the TRAIN chute!`
	elseif level == EconomyConfig.PenAutomation.Billboard then
		return `{step} unlocked: what you don't keep now rides out of your PEN chute!`
	end
	return `{step} unlocked at your Ore Pen!`
end

---------------------------------------------------------------- buying

-- The table a levelled item's level lives in and its key, made if missing
-- (before any coins are taken, so the write after the spend can't fail).
local function levelSlot(data: { [string]: any }, entry: TechItem): ({ [string]: any }, string)
	if entry.Kind == "Upgrade" then
		local all = data.MachineUpgrades
		if type(all) ~= "table" then
			all = {}
			data.MachineUpgrades = all
		end
		local id = entry.Machine :: string
		local record = all[id]
		if type(record) ~= "table" then
			record = {}
			all[id] = record
		end
		return record, entry.Upgrade :: string
	end
	local bought = data.Upgrades
	if type(bought) ~= "table" then
		bought = {}
		data.Upgrades = bought
	end
	local field = if entry.Kind == "Bellows" then "Bellows" elseif entry.Kind == "Slots" then "ExtraSlots" else "PenAutomation"
	return bought, field
end

--[[
	Buys `entry` for the player: quotes (EconomyConfig.techQuote: count for
	machines, level = the level being bought for levelled items), spends and
	writes in one step with no yield. Returns (true, nil, Bought) or
	(false, reason) with a TechShop.Reasons code (or "NoData"). No range
	check here (the ShopBuy handler checks it with placeFor).
]]
function ShopService.buy(player: Player, entry: TechItem, count: any?, level: any?): (boolean, string?, Bought?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData", nil
	end
	local price, reason = EconomyConfig.techQuote(entry, data, count, level)
	if price == nil then
		return false, reason or "BadItem", nil
	end
	-- prepare the write target first: nothing below the spend can fail
	local machineCount = if entry.Kind == "Machine" then (if count == nil then 1 else count :: number) else 1
	local slot: { [string]: any }? = nil
	local key = ""
	local newLevel: number? = nil
	if entry.Kind == "Machine" then
		if type(data.MachineInventory) ~= "table" then
			data.MachineInventory = {}
		end
	else
		local current = EconomyConfig.techLevel(entry, data)
		newLevel = current + 1
		slot, key = levelSlot(data, entry)
	end
	if not EconomyService.spend(player, price, "Tech:" .. entry.Item) then
		return false, "NoCoins", nil
	end
	-- paid: grant in the same step (no yield since the quote)
	if entry.Kind == "Machine" then
		Placement.addInventory(data, entry.Machine :: string, machineCount)
	elseif slot then
		slot[key] = newLevel
	end
	DataService.changed(player)
	local bought: Bought = {
		Item = entry.Item,
		Kind = entry.Kind,
		Machine = entry.Machine,
		Upgrade = entry.Upgrade,
		Level = newLevel,
		Count = machineCount,
		Price = price,
	}
	for _, callback in boughtCallbacks do
		task.spawn(callback, player, bought)
	end
	return true, nil, bought
end

---------------------------------------------------------------- requests

local function answer(player: Player, item: string, ok: boolean, reason: string?, level: number?, count: number?)
	Net.fire("ShopResult", player, { Item = item, Ok = ok, Reason = reason, Level = level, Count = count })
end

-- ShopBuy { Shop = "Tech", Item, Count?, Level? }: every request read gets a ShopResult.
local function onShopBuy(player: Player, payload: any)
	local args = Guard.table(payload, MAX_PAYLOAD)
	local item = if args then Guard.string(args.Item, MAX_ITEM_LENGTH) else nil
	local echo = item or ""
	-- no save loaded (joining / leaving): nothing can be sold, but the client still gets its answer
	if not DataService.get(player) or not args or args.Shop ~= EconomyConfig.TechShop.Shop then
		answer(player, echo, false, "BadItem")
		return
	end
	local entry = EconomyConfig.techItem(item)
	if not entry then
		answer(player, echo, false, "BadItem")
		return
	end
	local place: Place? = ShopService.placeFor(player, entry)
	if not place then
		answer(player, echo, false, "TooFar")
		return
	end
	local ok, reason, bought = ShopService.buy(player, entry, args.Count, args.Level)
	if not ok or not bought then
		answer(player, echo, false, if reason == "NoData" or reason == nil then "BadItem" else reason)
		return
	end
	answer(player, echo, true, nil, bought.Level, if bought.Kind == "Machine" then bought.Count else nil)
	Net.fire("Notify", player, { Text = ShopService.boughtText(player, bought, place), Kind = "Reward" })
end

---------------------------------------------------------------- the counter

local function openView(player: Player, counter: BasePart)
	if not DataService.get(player) or not ShopService.counterNear(player, ShopService.Range) then
		return
	end
	Net.fire("OpenUI", player, "Tech", { Counter = counter })
end

-- Forgets counters that left the game (the lobby was rebuilt), so the list never only grows.
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
	-- a counter pruned while away comes back with one prompt, never two
	local old = part:FindFirstChild(ShopService.PointName)
	if old then
		old:Destroy()
	end
	-- the prompt sits on the customer side (-Z) of the counter top
	local point = Instance.new("Attachment")
	point.Name = ShopService.PointName
	point.CFrame = CFrame.new(0, part.Size.Y / 2 + 0.6, -part.Size.Z / 2)
	point.Parent = part
	local droppers = part:HasTag(ShopService.DropperTag)
	local prompt = PromptConfig.make({
		Name = ShopService.PromptName,
		ActionText = if droppers then "Droppers" else "Tech Shop",
		ObjectText = if droppers then "Droppers & Money Lasers" else "Machines & Upgrades",
		Distance = PROMPT_DISTANCE,
		Parent = point,
	})
	prompt.Triggered:Connect(function(player: Player)
		openView(player, part)
	end)
end

-- A counter lost its tag or left the game: drop it and its prompt (hooked
-- again, with a new prompt, if it comes back).
local function unhookCounter(counter: Instance)
	local index = table.find(counters, counter :: any)
	if index then
		table.remove(counters, index)
	end
	hooked[counter] = nil
	local point = counter:FindFirstChild(ShopService.PointName)
	if point then
		point:Destroy()
	end
	pruneCounters()
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/ShopService.spec.luau).
ShopService._test = {
	shopBuy = onShopBuy,
	hookCounter = hookCounter,
	unhookCounter = unhookCounter,
	counters = function(): { BasePart }
		return table.clone(counters)
	end,
	open = openView,
	reset = function()
		table.clear(counters)
		table.clear(boughtCallbacks)
	end,
}

function ShopService.init()
	Net.on("ShopBuy", onShopBuy)
end

function ShopService.start()
	-- the map is built in WorldService.init, so the UPGRADES stall exists by now
	for _, instance in CollectionService:GetTagged(ShopService.Tag) do
		hookCounter(instance)
	end
	CollectionService:GetInstanceAddedSignal(ShopService.Tag):Connect(hookCounter)
	CollectionService:GetInstanceRemovedSignal(ShopService.Tag):Connect(unhookCounter)
	for _, instance in CollectionService:GetTagged(ShopService.DropperTag) do
		hookCounter(instance)
	end
	CollectionService:GetInstanceAddedSignal(ShopService.DropperTag):Connect(hookCounter)
	CollectionService:GetInstanceRemovedSignal(ShopService.DropperTag):Connect(unhookCounter)
end

return ShopService
