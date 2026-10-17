--[[
	FoundryService: the Foundry on every base yard (step 3): ingots in,
	stronger blasters out (docs/plans/STEP3_PLAN.md "WP-Foundry"; the rules
	live in Shared/Machines/FoundryLogic, the numbers in BlasterData and
	GameConfig "Foundry" / "Anvil").

	The building
	  At server start every plot's PlotBuilder placeholder (Yard.Foundry) is
	  replaced by World/FoundryBuilder's building, and the FOUNDRY chute gets
	  its receiver (Plot_<id>.FoundryReceiver at BaseLayout.FoundryIntake).
	  The rack shows the plot owner's next blaster level as a silhouette.
	  Attribute Forging = true while the owner hammers (warning lights).

	Ingots in (data.Foundry.Stock, at most GameConfig.MaxFoundryStock)
	  - FOUNDRY chute (BaseLayout.Chutes.Foundry): registered with
	    ConveyorService.setSink("Foundry", handler) when the Belts package
	    provides it. CONTRACT for ConveyorService:
	      handler(plotId: number, record: ItemRecord) -> (taken: boolean, reason: string?)
	      (the handler also accepts the two the other way round, a Player
	      instead of the plot id, or the item's Model; a number counts as the
	      plot id only when WorldLayout.Plots has it, otherwise the plot comes
	      from the item's position)
	      true            the item is gone (absorbed): an ingot the next level
	                      can use went into the stock, anything else into the
	                      Ore Pen; the owner sees it fly into the hood (Fx
	                      FoundryIn, only to the owner, with its destination
	                      "Stock" | "Pen") and, for the pen, a throttled toast
	                      saying why
	      false, "Full"   the stock and the pen are both full: leave the item
	                      waiting on the cell; the receiver shows "Ore Pen full"
	      false, "Foreign" not the plot owner's item: push it off (as at machines)
	      false, "Wrong"  not a loose item: ignore it
	    ConveyorService calls it for an item at the end of a belt on the
	    FOUNDRY cell facing BaseLayout.SinkRotation and, with no belt on the
	    cell, for an item lying on the cell. Without ConveyorService.setSink
	    this service scans that cell itself (no belt on it only).
	  - The furnace's hopper (an IntakeService zone): your own ingots the next
	    level can use go in while the stock has room; everything else bounces
	    back out with a hint.
	  - "Put In" prompt (F / gamepad Y, shown while you carry something): the
	    carried ingots the next level can use.

	FoundryAction (Net), all checked here:
	  "Open"   open the panel (also the "Open Foundry" prompt, G / gamepad B)
	  "Forge"  { Ore? }  start the hammer moment: FoundryBegin { Id, Level,
	           Ore, Hits, Timeout, Ingots, Coins }. Nothing is taken yet.
	           Refused with FoundryResult { Id = "", Ok = false, Reason }:
	           "Busy" | "TooFar" | "MaxLevel" | "BadOre" | "NotEnough".
	  "Strike" { SessionId, Times }  the taps (seconds since FoundryBegin).
	           The session ends first (one Strike per session); the taps must
	           pass MachineLogic.validateStrikes (count = Hits, increasing, at
	           least AnvilMinStrikeGap apart, the last >= Hits x
	           AnvilMinSecondsPerHit) and the server's own clock must have seen
	           at least Hits x AnvilMinSecondsPerHit ("BadStrikes"); you must
	           still stand at your Foundry ("TooFar"). Then, in one step with no
	           yield: pick the ingots again (FoundryLogic.pick, the session's
	           skin), spend the coins (EconomyService.spend), remove exactly
	           those ingots, BlasterLevel + 1, BlasterOre = skin,
	           Stats.BlastersForged + 1, the stock ingots the new next level
	           can't use move into the pen (as many as fit). FoundryResult
	           { Id, Ok = true, Level, Ore, Name } (or Reason "NotEnough").
	           ToolService swaps the blaster on the data change.
	  "Cancel" { SessionId }  ends the session ("Cancelled"); nothing is taken.
	  "Take"   { Key, Count, All? }  stock ingots of one type back into the Ore
	           Pen (as many as fit; refused while a session runs). All = true
	           takes ingots of the key's ore in any grade (the panel's TAKE ALL).
	Sessions end on Timeout (GameConfig.AnvilTimeout), walking away from the
	anvil past AnvilWalkAway ("TooFar"), death ("Cancelled"), leaving and
	losing the plot. Fail or cancel never takes anything.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local BlasterData = require(Shared.Config.BlasterData)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local WorldLayout = require(Shared.Config.WorldLayout)
local FoundryLogic = require(Shared.Machines.FoundryLogic)
local Grid = require(Shared.Machines.Grid)
local MachineLogic = require(Shared.Machines.MachineLogic)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local FoundryBuilder = require(script.Parent.Parent.World.FoundryBuilder)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local PlotService = require(script.Parent.PlotService)
local MachineService = require(script.Parent.MachineService)
local IntakeService = require(script.Parent.IntakeService)

local FoundryService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord
export type Destination = "Stock" | "Pen"
export type StockRefusal = "MaxLevel" | "Wrong" | "TooCommon" | "Full"

export type Session = {
	Id: string,
	PlotId: number,
	Level: number, -- the blaster level being forged
	Ore: string, -- the skin
	Hits: number,
	Started: number, -- clock() when FoundryBegin went out
	Timeout: number,
}

FoundryService.Range = 24 -- studs from the anvil (FoundryController closes the panel beyond this)
FoundryService.PromptTag = "FoundryPrompt"
FoundryService.BuildingTag = "FoundryBuilding"
FoundryService.SinkName = "Foundry"

local RANGE_SLACK = 4 -- lag, walking while clicking
local TOAST_COOLDOWN = 5
local PEN_FULL_SHOW = 2.5 -- seconds the "Ore Pen full" sign stays after the last waiting item
local MONITOR_TICK = 0.5
local MAX_PUT_IN = 64 -- more than any carry stack
local MAX_KEY_LENGTH = 80
local FX_RANGE = 90
local PEN_TOAST_COOLDOWN = 30 -- "sent to your Ore Pen" toasts (a busy chute line)

local sessions: { [Player]: Session } = {}
local lastToast: { [Player]: { [string]: number } } = {}
local penFullAt: { [number]: number } = {}
local rackLevel: { [number]: number } = {}
local sinkRegistered = false
local warnedNoPlot = false
local clock: () -> number = os.clock

---------------------------------------------------------------- data helpers

-- data.Foundry.Stock (made when an old save somehow lacks it).
function FoundryService.stockOf(data: { [string]: any }): { Desc }
	local foundry = data.Foundry
	if type(foundry) ~= "table" then
		foundry = {}
		data.Foundry = foundry
	end
	if type(foundry.Stock) ~= "table" then
		foundry.Stock = {}
	end
	return foundry.Stock
end

local function penRoom(data: { [string]: any }): number
	return math.max(0, ItemService.penCapacity(data) - #data.Storage)
end

local function copy(desc: Desc): Desc
	return { K = desc.K, O = desc.O, G = desc.G, R = desc.R }
end

-- Why this item can't go into the stock right now (nil = it can).
function FoundryService.stockRefusal(data: { [string]: any }, desc: Desc): StockRefusal?
	if not FoundryLogic.recipe(data.BlasterLevel) then
		return "MaxLevel"
	end
	if not FoundryLogic.isIngot(desc) then
		return "Wrong"
	end
	if not FoundryLogic.usable(desc, data.BlasterLevel) then
		return "TooCommon"
	end
	if #FoundryService.stockOf(data) >= GameConfig.MaxFoundryStock then
		return "Full"
	end
	return nil
end

-- Where the FOUNDRY chute puts an item: the stock (a usable ingot with
-- room), else the Ore Pen (room left), else nowhere (it waits).
function FoundryService.destination(data: { [string]: any }, desc: Desc): Destination?
	if FoundryService.stockRefusal(data, desc) == nil then
		return "Stock"
	end
	if penRoom(data) > 0 then
		return "Pen"
	end
	return nil
end

local function refusalText(data: { [string]: any }, reason: string): string
	if reason == "MaxLevel" then
		return "Your blaster is already at the top level. Keep your ingots in the Ore Pen."
	elseif reason == "Wrong" then
		return "Only ingots go into the Foundry. Smelt ore in a furnace first."
	elseif reason == "TooCommon" then
		local nextBlaster = FoundryLogic.nextBlaster(data.BlasterLevel)
		local recipe = FoundryLogic.recipe(data.BlasterLevel)
		local rarity = if recipe then recipe.MinRarity else "Common"
		return `The {nextBlaster.Name} needs {rarity} or better ingots.`
	end
	return `Your Foundry is full ({#FoundryService.stockOf(data)}/{GameConfig.MaxFoundryStock} ingots). Forge a blaster or take some out.`
end

---------------------------------------------------------------- the world

local function toast(player: Player, text: string, kind: string?, key: string?, cooldown: number?)
	if key then
		local times = lastToast[player]
		if not times then
			times = {}
			lastToast[player] = times
		end
		local now = clock()
		if now - (times[key] or -math.huge) < (cooldown or TOAST_COOLDOWN) then
			return
		end
		times[key] = now
	end
	Net.fire("Notify", player, { Text = text, Kind = kind or "Deny" })
end

-- The Foundry building of a plot (nil before setup or on maps without yards).
function FoundryService.building(plotId: number): Model?
	local plot = PlotService.model(plotId)
	local yard = plot and plot:FindFirstChild("Yard")
	local building = yard and yard:FindFirstChild("Foundry")
	return if building and building:IsA("Model") and building:GetAttribute("PlotId") == plotId then building else nil
end

function FoundryService.receiver(plotId: number): Model?
	local plot = PlotService.model(plotId)
	local receiver = plot and plot:FindFirstChild("FoundryReceiver")
	return if receiver and receiver:IsA("Model") then receiver else nil
end

-- World position of a plot's anvil top.
function FoundryService.anvilPosition(plotId: number): Vector3
	return (PlotService.plotCFrame(plotId) * CFrame.new(FoundryBuilder.AnvilLocal)).Position
end

local function mouthPosition(plotId: number): Vector3
	return (PlotService.plotCFrame(plotId) * CFrame.new(BaseLayout.FoundryIntake.Mouth)).Position
end

local function attachmentWorld(building: Model?, name: string): CFrame?
	local base = building and building.PrimaryPart
	local a = base and base:FindFirstChild(name)
	if base and a and a:IsA("Attachment") then
		return base.CFrame * a.CFrame
	end
	return nil
end

-- Is the player standing within `range` (flat studs, + slack) of their anvil?
function FoundryService.isNear(player: Player, plotId: number, range: number?): boolean
	local root = Guard.rootPart(player)
	if not root then
		return false
	end
	local offset = root.Position - FoundryService.anvilPosition(plotId)
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= (range or FoundryService.Range) + RANGE_SLACK
end

local function setForging(plotId: number, on: boolean)
	local building = FoundryService.building(plotId)
	if building then
		building:SetAttribute("Forging", on)
	end
end

-- The rack shows blaster level `level + 1` (the owner's next one).
local function updateRack(plotId: number, level: number)
	if rackLevel[plotId] == level then
		return
	end
	local building = FoundryService.building(plotId)
	if not building then
		return
	end
	rackLevel[plotId] = level
	local ok, err = pcall(function()
		FoundryBuilder.setRack(building, level + 1)
	end)
	if not ok then
		warn(`[FoundryService] rack of plot {plotId}: {err}`)
	end
end

local function showPenFull(plotId: number, on: boolean)
	local receiver = FoundryService.receiver(plotId)
	local hood = receiver and receiver.PrimaryPart
	local sign = hood and hood:FindFirstChild("PenFull")
	if sign and sign:IsA("BillboardGui") and sign.Enabled ~= on then
		sign.Enabled = on
	end
end

-- The owner sees the item fly in (only the owner: a busy line next door
-- costs other phones nothing). destination: "Stock" | "Pen".
local function fireIn(owner: Player, from: Vector3, to: Vector3, desc: Desc, destination: Destination)
	-- dirty ore keeps its secret: no ore id for raw chunks
	local oreId = if desc.K == "Raw" then "" else desc.O
	Net.fire("Fx", owner, "FoundryIn", from, to, desc.K, oreId, destination)
end

-- Why the chute sent an item to the Ore Pen instead of the stock.
function FoundryService.penText(data: { [string]: any }, desc: Desc, reason: StockRefusal): string
	if reason == "TooCommon" then
		local ore = OreData.ById[desc.O]
		local nextBlaster = FoundryLogic.nextBlaster(data.BlasterLevel)
		local recipe = FoundryLogic.recipe(data.BlasterLevel)
		local rarity = if recipe then recipe.MinRarity else "Common"
		return `{if ore then ore.Name else "Those"} ingots aren't needed for the {nextBlaster.Name} ({rarity}+): sent to your Ore Pen.`
	elseif reason == "Full" then
		return `Your Foundry is full ({GameConfig.MaxFoundryStock} ingots): more ingots go to your Ore Pen.`
	elseif reason == "MaxLevel" then
		return "Your blaster is at the top level: the Foundry sends ingots to your Ore Pen."
	end
	return "Only ingots go into the Foundry: the chute sent that to your Ore Pen."
end

---------------------------------------------------------------- ingots in

--[[
	The FOUNDRY chute takes an item (see the header for the contract).
	Everything happens with no yield: the item is absorbed and written to
	the stock or the pen in the same step.
]]
function FoundryService.sink(plotId: number, record: ItemRecord): (boolean, string?)
	if record.State ~= "Loose" then
		return false, "Wrong"
	end
	local owner = PlotService.ownerOf(plotId)
	if not owner or owner.UserId ~= record.Owner then
		return false, "Foreign"
	end
	local data = DataService.get(owner)
	if not data then
		return false, "Full"
	end
	local desc = ItemService.descOf(record)
	local destination: Destination? = FoundryService.destination(data, desc)
	if destination == nil then
		penFullAt[plotId] = clock()
		showPenFull(plotId, true)
		toast(owner, "Your Ore Pen is full: items wait at the Foundry chute. Sell ore or put some on a podium.", "Info", "PenFull")
		return false, "Full"
	end
	local where: Destination = destination :: Destination
	local refusal: StockRefusal? = if where == "Pen" then FoundryService.stockRefusal(data, desc) else nil
	local from = record.Body.CFrame.Position
	local item = copy(ItemService.absorb(record))
	if where == "Stock" then
		table.insert(FoundryService.stockOf(data), item)
	else
		table.insert(data.Storage, item)
	end
	DataService.changed(owner)
	fireIn(owner, from, mouthPosition(plotId), item, where)
	if refusal ~= nil then
		toast(owner, FoundryService.penText(data, item, refusal), "Info", "Pen" .. refusal, PEN_TOAST_COOLDOWN)
	end
	return true, nil
end

-- ConveyorService may call the sink with its arguments in another order or
-- shape (it is written in parallel): find the plot and the item record.
local function sinkAdapter(...: any): (boolean, string?)
	local plotId: number? = nil
	local record: ItemRecord? = nil
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) == "number" then
			-- only a real plot id (never a clock value or a count)
			if plotId == nil and WorldLayout.Plots[value] ~= nil then
				plotId = value
			end
		elseif type(value) == "table" and record == nil and value.Body ~= nil and value.Owner ~= nil then
			record = value :: ItemRecord
		elseif typeof(value) == "Instance" then
			if value:IsA("Player") and plotId == nil then
				plotId = PlotService.plotOf(value :: Player)
			elseif value:IsA("Model") and record == nil then
				record = ItemService.get(value)
			end
		end
	end
	if not record then
		return false, "Wrong"
	end
	local found = record :: ItemRecord
	if not plotId then
		plotId = PlotService.plotAt(found.Body.CFrame.Position)
	end
	if not plotId or not WorldLayout.Plots[plotId] then
		if not warnedNoPlot then
			warnedNoPlot = true
			warn("[FoundryService] the FOUNDRY sink got an item without a plot (check the ConveyorService.setSink call)")
		end
		return false, "Wrong"
	end
	return FoundryService.sink(plotId :: number, found)
end
FoundryService.sinkHandler = sinkAdapter

-- Pops a refused item back out of the hopper (toward the yard).
local function bounce(plotId: number, record: ItemRecord)
	local building = FoundryService.building(plotId)
	local out = attachmentWorld(building, "HopperOut")
		or PlotService.plotCFrame(plotId) * CFrame.new(FoundryBuilder.AnvilLocal + Vector3.new(0, 3, -3))
	local look = PlotService.plotCFrame(plotId).LookVector
	ItemService.release(record, CFrame.new(out.Position), look * 9 + Vector3.new(0, 10, 0))
end

-- An item came to rest in (or flew into) the furnace's hopper.
local function onHopper(plotId: number, record: ItemRecord)
	if record.State ~= "Loose" then
		return
	end
	local owner = PlotService.ownerOf(plotId)
	if not owner or owner.UserId ~= record.Owner then
		bounce(plotId, record)
		local thrower = Players:GetPlayerByUserId(record.Owner)
		if thrower then
			toast(thrower, "That's not your Foundry. Yours is in the yard behind your own forge.", "Info", "Foreign")
		end
		return
	end
	local data = DataService.get(owner)
	if not data then
		bounce(plotId, record)
		return
	end
	local desc = ItemService.descOf(record)
	local reason = FoundryService.stockRefusal(data, desc)
	if reason then
		Net.fire("Fx", owner, "Reject", record.Body.CFrame.Position)
		bounce(plotId, record)
		local why: string = reason
		toast(owner, refusalText(data, why), nil, "Hopper" .. why)
		return
	end
	local from = record.Body.CFrame.Position
	local item = copy(ItemService.absorb(record))
	table.insert(FoundryService.stockOf(data), item)
	DataService.changed(owner)
	local hopper = attachmentWorld(FoundryService.building(plotId), "HopperIn")
	fireIn(owner, from, if hopper then hopper.Position else from, item, "Stock")
end

-- "Put In": the carried ingots the next level can use.
local function putIn(player: Player, plotId: number)
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your Foundry.")
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local carried = CarryService.list(player)
	if #carried == 0 then
		toast(player, "Carry ingots here to put them into your Foundry.", "Info")
		return
	end
	local stock = FoundryService.stockOf(data)
	local loaded = 0
	for _ = 1, MAX_PUT_IN do
		local record = CarryService.takeTop(player, function(r: ItemRecord): boolean
			return FoundryService.stockRefusal(data, ItemService.descOf(r)) == nil
		end)
		if not record then
			break
		end
		-- no yield between taking it off the stack and storing it
		table.insert(stock, copy(ItemService.absorb(record)))
		loaded += 1
	end
	if loaded > 0 then
		DataService.changed(player)
		local hopper = attachmentWorld(FoundryService.building(plotId), "HopperIn")
		if hopper then
			Net.fire("Fx", player, "FoundryPut", hopper.Position, loaded)
		end
		return
	end
	-- nothing went in: say why (for the item on top of the stack)
	local stack = CarryService.list(player)
	local top = stack[#stack]
	local reason = if top then FoundryService.stockRefusal(data, ItemService.descOf(top)) else nil
	local why: string = reason or "Wrong"
	toast(player, refusalText(data, why))
end

local function openPanel(player: Player, plotId: number)
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your Foundry.")
		return
	end
	if DataService.get(player) then
		Net.fire("OpenUI", player, "Foundry", {})
	end
end

---------------------------------------------------------------- forging

local function result(player: Player, id: string, ok: boolean, reason: string?, extra: { [string]: any }?)
	local payload: { [string]: any } = { Id = id, Ok = ok, Reason = reason }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	Net.fire("FoundryResult", player, payload)
end

-- Ends a session (nothing is taken). With a reason the client is told.
local function endSession(player: Player, reason: string?)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	setForging(session.PlotId, false)
	if reason and player.Parent then
		result(player, session.Id, false, reason)
	end
end

local function startForge(player: Player, plotId: number, data: { [string]: any }, oreArg: any)
	if sessions[player] then
		result(player, "", false, "Busy")
		return
	end
	-- the walk-away range, so a session never starts already "too far"
	if not FoundryService.isNear(player, plotId, GameConfig.AnvilWalkAway) then
		result(player, "", false, "TooFar")
		return
	end
	local level = FoundryLogic.level(data.BlasterLevel)
	local recipe = FoundryLogic.recipe(level)
	if not recipe then
		result(player, "", false, "MaxLevel")
		return
	end
	local skin: string? = nil
	if oreArg ~= nil then
		skin = Guard.string(oreArg, 40)
		if not skin or not OreData.exists(skin) then
			result(player, "", false, "BadOre")
			return
		end
	end
	local stock = FoundryService.stockOf(data)
	local picked, why = FoundryLogic.pick(stock, level, skin)
	if not picked then
		result(player, "", false, why or "NotEnough")
		return
	end
	if not EconomyService.canAfford(player, recipe.Coins) then
		result(player, "", false, "NotEnough")
		return
	end
	local ore = skin or stock[picked[1]].O
	local session: Session = {
		Id = HttpService:GenerateGUID(false),
		PlotId = plotId,
		Level = level + 1,
		Ore = ore,
		Hits = FoundryLogic.hits(level + 1),
		Started = clock(),
		Timeout = GameConfig.AnvilTimeout,
	}
	sessions[player] = session
	setForging(plotId, true)
	Net.fire("FoundryBegin", player, {
		Id = session.Id,
		Level = session.Level,
		Ore = ore,
		Hits = session.Hits,
		Timeout = session.Timeout,
		Ingots = recipe.Ingots,
		Coins = recipe.Coins,
	})
end

-- Moves stock items the next level can't use into the pen (as many as fit).
local function moveUnusable(data: { [string]: any }): number
	local stock = FoundryService.stockOf(data)
	local room = penRoom(data)
	local moved = 0
	local i = 1
	while i <= #stock and moved < room do
		if FoundryLogic.usable(stock[i], data.BlasterLevel) then
			i += 1
		else
			table.insert(data.Storage, table.remove(stock, i) :: Desc)
			moved += 1
		end
	end
	return moved
end

-- The final step: checks again and takes ingots + coins with no yield.
local function commit(player: Player, session: Session): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NotEnough"
	end
	local level = FoundryLogic.level(data.BlasterLevel)
	local recipe = FoundryLogic.recipe(level)
	if not recipe or level + 1 ~= session.Level then
		return false, "NotEnough"
	end
	local stock = FoundryService.stockOf(data)
	local picked = FoundryLogic.pick(stock, level, session.Ore)
	if not picked or not EconomyService.spend(player, recipe.Coins, "Foundry") then
		return false, "NotEnough"
	end
	table.sort(picked, function(a: number, b: number): boolean
		return a > b
	end)
	for _, index in picked do
		table.remove(stock, index)
	end
	data.BlasterLevel = level + 1
	data.BlasterOre = session.Ore
	local stats = data.Stats
	if type(stats) == "table" then
		local forged = stats.BlastersForged
		stats.BlastersForged = (if type(forged) == "number" and forged == forged then forged else 0) + 1
	end
	moveUnusable(data)
	DataService.changed(player)
	return true, nil
end

local function strike(player: Player, idArg: any, timesArg: any)
	local session = sessions[player]
	local id = Guard.string(idArg, 64)
	if not session or id ~= session.Id then
		return
	end
	-- one Strike per session, whatever happens next
	endSession(player, nil)
	local elapsed = clock() - session.Started
	local valid = MachineLogic.validateStrikes(timesArg, session.Hits, elapsed)
	if not valid or elapsed < session.Hits * GameConfig.AnvilMinSecondsPerHit then
		result(player, session.Id, false, "BadStrikes")
		return
	end
	if PlotService.plotOf(player) ~= session.PlotId or not FoundryService.isNear(player, session.PlotId, GameConfig.AnvilWalkAway) then
		result(player, session.Id, false, "TooFar")
		return
	end
	local ok, reason = commit(player, session)
	if not ok then
		result(player, session.Id, false, reason)
		return
	end
	result(player, session.Id, true, nil, {
		Level = session.Level,
		Ore = session.Ore,
		Name = BlasterData.displayName(session.Level, session.Ore),
	})
	updateRack(session.PlotId, session.Level)
	local anvil = FoundryService.anvilPosition(session.PlotId)
	Net.fireNear("Fx", anvil, FX_RANGE, player, "FoundryForged", anvil, session.Ore)
end

local function take(player: Player, plotId: number, data: { [string]: any }, keyArg: any, countArg: any, allArg: any)
	local keyText = Guard.string(keyArg, MAX_KEY_LENGTH)
	local desc = if keyText then ItemData.parseKey(keyText) else nil
	local count = Guard.integer(countArg, 1, GameConfig.MaxFoundryStock)
	local anyGrade = if allArg == nil then false else Guard.boolean(allArg)
	if not desc or desc.K ~= "Ingot" or not count or anyGrade == nil then
		return
	end
	if sessions[player] then
		toast(player, "Finish forging first.")
		return
	end
	if not FoundryService.isNear(player, plotId) then
		toast(player, "Walk back to your Foundry first.")
		return
	end
	local key = ItemData.storageKey(desc)
	local stock = FoundryService.stockOf(data)
	local room = penRoom(data)
	local moved = 0
	for i = #stock, 1, -1 do
		if moved >= count or moved >= room then
			break
		end
		local entry = stock[i]
		local same = type(entry) == "table"
			and type(entry.K) == "string"
			and type(entry.O) == "string"
			and (if anyGrade then entry.K == "Ingot" and entry.O == desc.O else ItemData.storageKey(entry) == key)
		if same then
			table.insert(data.Storage, table.remove(stock, i) :: Desc)
			moved += 1
		end
	end
	if moved > 0 then
		DataService.changed(player)
		toast(player, if moved == 1 then "Moved 1 ingot to your Ore Pen." else `Moved {moved} ingots to your Ore Pen.`, "Info")
	elseif room <= 0 then
		toast(player, "Your Ore Pen is full. Sell ore or put some on a podium first.")
	end
end

local function onAction(player: Player, actionArg: any, argArg: any)
	local action = Guard.string(actionArg, 16)
	local arg: { [any]: any }? = if argArg == nil then {} else Guard.table(argArg, 4)
	if not action or not arg then
		return
	end
	local plotId = PlotService.plotOf(player)
	local data = DataService.get(player)
	if not plotId or not data then
		return
	end
	if action == "Open" then
		if FoundryService.isNear(player, plotId) then
			openPanel(player, plotId)
		else
			toast(player, "Walk to your Foundry first.")
		end
	elseif action == "Forge" then
		startForge(player, plotId, data, arg.Ore)
	elseif action == "Strike" then
		strike(player, arg.SessionId, arg.Times)
	elseif action == "Cancel" then
		local session = sessions[player]
		if session and Guard.string(arg.SessionId, 64) == session.Id then
			endSession(player, "Cancelled")
		end
	elseif action == "Take" then
		take(player, plotId, data, arg.Key, arg.Count, arg.All)
	end
end

-- Timeouts, walking away, death, leaving (every MONITOR_TICK) and the
-- "Ore Pen full" signs.
local function monitor(now: number)
	for player, session in sessions do
		if not player.Parent then
			sessions[player] = nil
			setForging(session.PlotId, false)
		elseif now - session.Started >= session.Timeout then
			endSession(player, "Timeout")
		elseif not Guard.rootPart(player) then
			endSession(player, "Cancelled")
		elseif
			PlotService.plotOf(player) ~= session.PlotId or not FoundryService.isNear(player, session.PlotId, GameConfig.AnvilWalkAway)
		then
			endSession(player, "TooFar")
		end
	end
	for plotId, at in penFullAt do
		if now - at >= PEN_FULL_SHOW then
			penFullAt[plotId] = nil
			showPenFull(plotId, false)
		end
	end
end

---------------------------------------------------------------- the chute without ConveyorService

-- With no belt on the FOUNDRY cell, items lying there go into the sink
-- (only used when ConveyorService.setSink isn't there to do it).
local function scanChuteFloor()
	local cx, cz = BaseLayout.chuteCell("Foundry")
	local now = clock()
	for _, record in ItemService.looseList() do
		if record.State == "Loose" then
			local plotId, localPos = PlotService.plotAt(record.Body.CFrame.Position)
			if plotId and localPos and localPos.Y < 3 then
				local gx, gz = Grid.cellFromLocal(localPos)
				if gx == cx and gz == cz and not MachineService.atCell(plotId, cx, cz) and ItemService.isTrusted(record, now) then
					FoundryService.sink(plotId, record)
				end
			end
		end
	end
end

local function registerSink(): boolean
	local module = script.Parent:FindFirstChild("ConveyorService")
	if not module or not module:IsA("ModuleScript") then
		return false
	end
	local requireAny: any = require
	local ok, service = pcall(requireAny, module)
	if not ok or type(service) ~= "table" or type(service.setSink) ~= "function" then
		return false
	end
	local registered, err = pcall(service.setSink, FoundryService.SinkName, sinkAdapter)
	if not registered then
		warn("[FoundryService] ConveyorService.setSink failed: " .. tostring(err))
	end
	return registered
end

---------------------------------------------------------------- setup

local function makePrompt(
	parent: Instance,
	plotId: number,
	name: string,
	action: string,
	key: Enum.KeyCode,
	pad: Enum.KeyCode,
	order: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = "Foundry"
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
	prompt:SetAttribute("PlotId", plotId)
	prompt:AddTag(FoundryService.PromptTag)
	prompt.Parent = parent
	return prompt
end

-- Replaces a plot's placeholder with the Foundry building and builds the
-- chute receiver, the hopper zone and the prompts (once, at start).
local function setupPlot(plotId: number): boolean
	local plot = PlotService.model(plotId)
	local yard = plot and plot:FindFirstChild("Yard")
	if not plot or not yard then
		warn(`[FoundryService] plot {plotId} has no Yard (old map?)`)
		return false
	end
	local cf = PlotService.plotCFrame(plotId)
	local old = yard:FindFirstChild("Foundry")
	if old and old:GetAttribute("PlotId") == plotId then
		return true -- already built
	end
	local building = FoundryBuilder.build(cf, 2)
	building:SetAttribute("PlotId", plotId)
	building:SetAttribute("Forging", false)
	building:AddTag(FoundryService.BuildingTag)
	building.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	if old then
		old:Destroy()
	end
	building.Parent = yard
	rackLevel[plotId] = 1
	local oldReceiver = plot:FindFirstChild("FoundryReceiver")
	if oldReceiver then
		oldReceiver:Destroy()
	end
	local receiver = FoundryBuilder.receiver(cf)
	receiver:SetAttribute("PlotId", plotId)
	receiver.Parent = plot
	local intake = building:FindFirstChild("Intake")
	if intake and intake:IsA("BasePart") then
		IntakeService.addZone("Foundry" .. plotId, intake, function(record: ItemRecord)
			onHopper(plotId, record)
		end)
	end
	local base = building.PrimaryPart :: BasePart
	local anchor = base:FindFirstChild("Prompt") or base
	local put = makePrompt(anchor, plotId, "FoundryPutIn", "Put In", Enum.KeyCode.F, Enum.KeyCode.ButtonY, 0)
	put.Triggered:Connect(function(player: Player)
		putIn(player, plotId)
	end)
	local open = makePrompt(anchor, plotId, "FoundryOpen", "Open Foundry", Enum.KeyCode.G, Enum.KeyCode.ButtonB, 1)
	open.Triggered:Connect(function(player: Player)
		openPanel(player, plotId)
	end)
	return true
end

local function levelOf(player: Player): number?
	local data = DataService.get(player)
	return if data then FoundryLogic.level(data.BlasterLevel) else nil
end

-- Internals for the Lune tests only (tests/Foundry.spec.luau).
FoundryService._test = {
	action = onAction,
	hopper = onHopper,
	putIn = putIn,
	open = openPanel,
	setupPlot = setupPlot,
	monitor = monitor,
	scanChuteFloor = scanChuteFloor,
	updateRack = updateRack,
	sessions = sessions,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	reset = function()
		table.clear(sessions)
		table.clear(lastToast)
		table.clear(penFullAt)
		table.clear(rackLevel)
		warnedNoPlot = false
		clock = os.clock
	end,
}

function FoundryService.init()
	Net.on("FoundryAction", onAction)
	for _, plot in WorldLayout.Plots do
		local ok, err = pcall(setupPlot, plot.Id)
		if not ok then
			warn(`[FoundryService] plot {plot.Id}: {err}`)
		end
	end
	PlotService.onAssigned(function(player: Player, plotId: number)
		local level = levelOf(player)
		if level then
			updateRack(plotId, level)
		end
	end)
	PlotService.onReleased(function(player: Player, plotId: number)
		local session = sessions[player]
		if session and session.PlotId == plotId then
			endSession(player, "Cancelled")
		end
		updateRack(plotId, 1)
		penFullAt[plotId] = nil
		showPenFull(plotId, false)
	end)
	-- a new blaster level (any source) updates the rack
	DataService.onChanged(function(player: Player)
		local plotId = PlotService.plotOf(player)
		local level = levelOf(player)
		if plotId and level then
			updateRack(plotId, level)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		if session then
			sessions[player] = nil
			setForging(session.PlotId, false)
		end
		lastToast[player] = nil
	end)
end

function FoundryService.start()
	sinkRegistered = registerSink()
	if not sinkRegistered then
		warn("[FoundryService] no ConveyorService.setSink: the Foundry scans its chute cell itself")
	end
	local sinceMonitor = 0
	while true do
		task.wait(GameConfig.IntakeTick)
		sinceMonitor += GameConfig.IntakeTick
		if not sinkRegistered then
			local ok, err = pcall(function()
				scanChuteFloor()
			end)
			if not ok then
				warn("[FoundryService] chute scan failed: " .. tostring(err))
			end
		end
		if sinceMonitor >= MONITOR_TICK then
			sinceMonitor = 0
			local ok, err = pcall(function()
				monitor(clock())
			end)
			if not ok then
				warn("[FoundryService] monitor failed: " .. tostring(err))
			end
		end
	end
end

return FoundryService
