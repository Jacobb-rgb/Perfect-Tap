--[[
	GearService: the Gear shop at the SHOP stall in town (steps 6-7, step 6
	"Gear"). Five gear lines (GearConfig: Boots, HelmetLamp, Backpack,
	Gloves, Magnet), levels 0..GearConfig.MaxLevel, bought for coins.

	- ShopCounter (tag GearConfig.Tag, a BasePart of the lobby's SHOP stall):
	  this service adds a "Gear Shop" prompt at runtime on the customer side
	  (-Z) of the counter top; it opens the Gear shop view (OpenUI "Gear"
	  { Counter, Preview }).
	- GearAction (Net, rate limited) ("Buy", { Line, Level }): Level must be
	  the level being bought (current + 1, the one the card shows), else
	  "Stale" (GearConfig.quote), so a double tap or a lagging card never
	  buys two levels. Only within GearConfig.Range of a ShopCounter
	  ("TooFar"; the client closes the shop nearer than that).
	- Every GearAction the server reads gets one ActionResult { Action =
	  "Gear", Op, Ok, Reason?, Id?: the line, Level?: the new level,
	  Preview? } (Reason: a GearConfig.Reasons code; Preview:
	  GearService.preview), also one from a player whose save isn't loaded:
	  "BadItem", nothing changes. A successful buy also sends a "Reward"
	  toast (the client shows refusals on the card).
	- Atomic: quote, EconomyService.spend and the level write happen in one
	  step with no yield in between; data.Gear is made a table before the
	  coins are taken, so nothing can fail after the spend. Levels a newer
	  server gave (past MaxLevel, kept by Migrations) are never lowered: the
	  quote says "Max" for them.
	- Effects (src/server/Bonuses.luau reads data.Gear) apply at once and
	  after every respawn: the save change invalidates the bonus cache and
	  CarryService sets the walk speed (Boots), the carry capacity
	  (Backpack) and the PickupRange attribute (Gloves) again; throw power
	  (Gloves) and the Ore Magnet pull (ItemService) read the bonuses when
	  they act. The player attribute GearConfig.LampAttribute ("LampLevel",
	  the HelmetLamp level) is kept in step for every client: the clients
	  build the head lamps from it (GearFxController).
	- GearService.onBought(callback): stats / analytics / tutorial hooks,
	  (player, Bought) after every successful buy.
	- The cards show what the player really gets (GearConfig.LinePreview:
	  every bonus counted, the Magnetism enchant on the magnet, golems on
	  the boots...): GearService.preview(player) rides along with OpenUI
	  "Gear" { Counter, Preview } and every Gear ActionResult (Preview), and
	  the success toast says the real numbers too.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearConfig = require(Shared.Config.GearConfig)
local PromptConfig = require(Shared.Config.PromptConfig)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Perks = require(script.Parent.Parent.Perks)
local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local GearService = {}

-- What a successful buy gave (onBought listeners, tests).
export type Bought = {
	Line: string,
	Level: number, -- the new level
	Price: number, -- coins paid
}
export type BoughtCallback = (Player, Bought) -> ...any

GearService.Range = GearConfig.Range
GearService.Tag = GearConfig.Tag
GearService.PromptName = "GearShopPrompt"
GearService.PointName = "GearShopPromptPoint"
GearService.Action = "Gear" -- ActionResult.Action

-- level names on the toasts ("Miner's Boots III")
GearService.Numerals = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

local PROMPT_DISTANCE = 12
local MAX_PAYLOAD = 4
local MAX_LINE_LENGTH = 32
local MAX_OP_LENGTH = 16

local counters: { BasePart } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local boughtCallbacks: { BoughtCallback } = {}

-- Listeners: (player, Bought) after every successful gear buy.
function GearService.onBought(callback: BoughtCallback)
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

-- The ShopCounter the player stands at (within `range`), or nil.
function GearService.counterNear(player: Player, range: number): BasePart?
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

---------------------------------------------------------------- texts

-- "Miner's Boots III"
function GearService.levelName(lineId: string, level: number): string
	local line = GearConfig.ById[lineId]
	local name = if line then line.Name else "Gear"
	return `{name} {GearService.Numerals[level] or tostring(level)}`
end

-- A gear value as the toasts and cards say it ("x1.08", "20", "8").
local function number(value: number): string
	if value == math.floor(value) then
		return tostring(value)
	end
	local text = string.format("%.2f", value):gsub("0+$", "")
	return text
end

--[[
	The toast after a successful buy: what the new level gives. With
	`values` (the line's preview after the buy) the numbers count every
	bonus, else they are the gear table's.
]]
function GearService.boughtText(lineId: string, level: number, strongBack: boolean?, values: GearConfig.LinePreview?): string
	local name = GearService.levelName(lineId, level)
	local live = if values and values.Level == level then values else nil
	local function main(fallback: number): string
		return number(if live then live.Now else fallback)
	end
	local function extra(fallback: number): string
		local value = if live then live.ExtraNow else nil
		return number(value or fallback)
	end
	if lineId == "Boots" then
		return `{name}: walk speed {main(GearConfig.value("Boots", level))}!`
	elseif lineId == "HelmetLamp" then
		return `{name}: your lamp lights {main(GearConfig.value("HelmetLamp", level))} studs in dark caves!`
	elseif lineId == "Backpack" then
		local gear = { Backpack = level }
		return `{name}: you can carry {main(GearConfig.carryCapacity(gear, strongBack == true))} items!`
	elseif lineId == "Gloves" then
		local reach = main(GearConfig.value("Gloves", level))
		local throw = extra(GearConfig.value("Gloves", level, "ThrowMult"))
		return `{name}: grab from {reach} studs, throw x{throw}!`
	elseif lineId == "Magnet" then
		return `{name}: mined ore flies into your hands from {main(GearConfig.value("Magnet", level))} studs (not on bases)!`
	end
	return `{name} bought!`
end

---------------------------------------------------------------- what the cards show

-- A line's main and extra value from bonus totals (see GearConfig.LinePreview).
local function lineValues(lineId: string, stats: Bonuses.Stats, player: Player): (number, number?)
	if lineId == "Boots" then
		return Bonuses.walkSpeed(stats), nil
	elseif lineId == "HelmetLamp" then
		local range, brightness = Bonuses.lamp(stats)
		return range, brightness
	elseif lineId == "Backpack" then
		return Bonuses.carryCapacity(stats, player), nil
	elseif lineId == "Gloves" then
		return Bonuses.pickupRange(stats), Bonuses.throwMult(stats)
	elseif lineId == "Magnet" then
		return Bonuses.magnetRadius(stats), nil
	end
	return 0, nil
end

--[[
	What every gear line gives the player now and at its next level, every
	bonus counted (Bonuses: the save as it is, and the save with that one
	line a level higher). nil when the save isn't loaded. Pure reads.
]]
function GearService.preview(player: Player): GearConfig.Preview?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local now = os.time()
	local stats = Bonuses.compute(data, now, player)
	local out: GearConfig.Preview = {}
	for _, line in GearConfig.Lines do
		local level = GearConfig.level(data.Gear, line.Id)
		local mainNow, extraNow = lineValues(line.Id, stats, player)
		local entry: GearConfig.LinePreview = { Level = level, Now = mainNow, ExtraNow = extraNow }
		if level < GearConfig.MaxLevel then
			local gear: { [string]: any } = if type(data.Gear) == "table" then table.clone(data.Gear) else {}
			gear[line.Id] = level + 1
			local after = table.clone(data)
			after.Gear = gear
			local mainNext, extraNext = lineValues(line.Id, Bonuses.compute(after, now, player), player)
			entry.Next = mainNext
			entry.ExtraNext = extraNext
		end
		out[line.Id] = entry
	end
	return out
end

---------------------------------------------------------------- effects

-- Keeps the LampLevel attribute (the HelmetLamp level) in step with the save.
function GearService.refreshLamp(player: Player)
	local data = DataService.get(player)
	local level = if data then GearConfig.level(data.Gear, "HelmetLamp") else 0
	if player:GetAttribute(GearConfig.LampAttribute) ~= level then
		player:SetAttribute(GearConfig.LampAttribute, level)
	end
end

---------------------------------------------------------------- buying

--[[
	Buys the next level of `lineId` for the player: quotes (GearConfig.quote
	with `level` = the level being bought), spends and writes in one step
	with no yield. Returns (true, nil, Bought) or (false, reason) with a
	GearConfig.Reasons code (or "NoData"). No range check here (the
	GearAction handler checks it).
]]
function GearService.buy(player: Player, lineId: any, level: any): (boolean, string?, Bought?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData", nil
	end
	local price, reason = GearConfig.quote(data.Gear, lineId, level)
	if price == nil then
		return false, reason or "BadItem", nil
	end
	local line = lineId :: string
	-- prepare the write target first: nothing below the spend can fail
	local gear = data.Gear
	if type(gear) ~= "table" then
		gear = {}
		data.Gear = gear
	end
	local newLevel = GearConfig.level(gear, line) + 1
	if not EconomyService.spend(player, price, "Gear:" .. line) then
		return false, "NoCoins", nil
	end
	-- paid: grant in the same step (no yield since the quote)
	gear[line] = newLevel
	DataService.changed(player)
	-- the effects right away (the save change does it too, this is just sooner)
	Bonuses.invalidate(player)
	CarryService.refreshWalkSpeed(player)
	GearService.refreshLamp(player)
	local bought: Bought = { Line = line, Level = newLevel, Price = price }
	for _, callback in boughtCallbacks do
		task.spawn(callback, player, bought)
	end
	return true, nil, bought
end

---------------------------------------------------------------- requests

local function answer(player: Player, op: string, ok: boolean, reason: string?, id: string?, level: number?, preview: GearConfig.Preview?)
	Net.fire("ActionResult", player, {
		Action = GearService.Action,
		Op = op,
		Ok = ok,
		Reason = reason,
		Id = id,
		Level = level,
		-- what the cards show from now on (nil when the save isn't loaded)
		Preview = preview or GearService.preview(player),
	})
end

-- GearAction ("Buy", { Line, Level }): every request read gets an ActionResult.
local function onGearAction(player: Player, action: any, payload: any)
	local op = Guard.string(action, MAX_OP_LENGTH) or ""
	local args = Guard.table(payload, MAX_PAYLOAD)
	local line = if args then Guard.string(args.Line, MAX_LINE_LENGTH) else nil
	-- no save loaded (joining / leaving): nothing can be sold, but the client still gets its answer
	if op ~= "Buy" or not args or not line or not DataService.get(player) then
		answer(player, op, false, "BadItem", line)
		return
	end
	if not GearConfig.ById[line] then
		answer(player, op, false, "BadItem", line)
		return
	end
	if not GearService.counterNear(player, GearService.Range) then
		answer(player, op, false, "TooFar", line)
		return
	end
	-- a level that isn't a whole number in range is never the next one: "Stale"
	local level = Guard.integer(args.Level, 1, GearConfig.MaxLevel)
	local ok, reason, bought = GearService.buy(player, line, level)
	if not ok or not bought then
		answer(player, op, false, if reason == "NoData" or reason == nil then "BadItem" else reason, line)
		return
	end
	local preview = GearService.preview(player)
	answer(player, op, true, nil, line, bought.Level, preview)
	Net.fire("Notify", player, {
		Text = GearService.boughtText(line, bought.Level, Perks.has(player, "StrongBack"), if preview then preview[line] else nil),
		Kind = "Reward",
	})
end

---------------------------------------------------------------- the counter

local function openView(player: Player, counter: BasePart)
	if not DataService.get(player) or not GearService.counterNear(player, GearService.Range) then
		return
	end
	Net.fire("OpenUI", player, "Gear", { Counter = counter, Preview = GearService.preview(player) })
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
	local old = part:FindFirstChild(GearService.PointName)
	if old then
		old:Destroy()
	end
	-- the prompt sits on the customer side (-Z) of the counter top
	local point = Instance.new("Attachment")
	point.Name = GearService.PointName
	point.CFrame = CFrame.new(0, part.Size.Y / 2 + 0.6, -part.Size.Z / 2)
	point.Parent = part
	local prompt = PromptConfig.make({
		Name = GearService.PromptName,
		ActionText = "Gear Shop",
		ObjectText = "Boots, Lamp, Backpack, Gloves, Magnet",
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
	local point = counter:FindFirstChild(GearService.PointName)
	if point then
		point:Destroy()
	end
	pruneCounters()
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/GearService.spec.luau).
GearService._test = {
	gearAction = onGearAction,
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

function GearService.init()
	Net.on("GearAction", onGearAction)
	-- the lamp level for every client (head lamps), on join and after every save change
	DataService.onLoaded(function(player)
		GearService.refreshLamp(player)
	end)
	DataService.onChanged(function(player)
		if player.Parent then
			GearService.refreshLamp(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			GearService.refreshLamp(player)
		end
	end
end

function GearService.start()
	-- the map is built in WorldService.init, so the SHOP stall exists by now
	for _, instance in CollectionService:GetTagged(GearService.Tag) do
		hookCounter(instance)
	end
	CollectionService:GetInstanceAddedSignal(GearService.Tag):Connect(hookCounter)
	CollectionService:GetInstanceRemovedSignal(GearService.Tag):Connect(unhookCounter)
end

return GearService
