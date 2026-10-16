--[[
	SellService: every way to turn items into coins. A sale always pays the
	item's OWNER (never whoever pushed it in), so dumping someone else's ore
	into your chute gains you nothing.

	- Pell's SellBin (town): throw or drop items in (an IntakeService zone).
	- Pell's SellCounter: "Sell What You Carry" sells everything in your hands.
	- Sell Chute machine: sells whatever drops or rolls in, from anyone.

	Selling is synchronous: the item is absorbed (gone from the world) before
	the coins are added, with no yield in between, so an item can never be
	sold twice. Sales close together (SellComboWindow) form a combo: the
	owner sees one rising '+N' with the running total (Fx 'Sold'), and
	players nearby see a small puff (Fx 'SellPuff'). Effects are sent at most
	once per player per frame, so selling a full stack costs one remote.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local MachineLogic = require(Shared.Machines.MachineLogic)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local MachineService = require(script.Parent.MachineService)
local IntakeService = require(script.Parent.IntakeService)
local EconomyService = require(script.Parent.EconomyService)

local SellService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord
type PlacedMachine = MachineService.PlacedMachine
export type Source = "Bin" | "Counter" | "Chute"
export type SoldCallback = (Player, Desc, number) -> ...any

type Combo = {
	Total: number, -- coins in this combo so far
	Count: number, -- items in this combo so far
	Best: string, -- best rarity id sold in it
	BestOrder: number,
	LastAt: number, -- os.clock() of the last sale
	Position: Vector3, -- where the last sale happened
	Dirty: boolean, -- has news the owner hasn't been sent yet
	HadRaw: boolean, -- raw ore sold since the last send
}

-- Pell's counter prompt
local COUNTER_DISTANCE = 12
-- the server allows a little more than the prompt (lag, a long counter)
local COUNTER_SLACK = 8
-- "Sell What You Carry": loop guard, more than any carry stack
local MAX_COUNTER_SALE = 64
-- "clean raw ore first" tip: only for new sellers, at most this often
local RAW_TIP_UNTIL_SOLD = 40
local RAW_TIP_COOLDOWN = 60
local RAW_TIP = "Tip: clean raw ore first, it sells for 2.5x more!"
local EMPTY_HANDS = "Bring items to sell! Pell buys raw ore, clean ore, ingots and gear."

local combos: { [Player]: Combo } = {}
local flushQueued: { [Player]: boolean } = {}
local lastTip: { [Player]: number } = {}
local soldCallbacks: { SoldCallback } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Listeners: (player, desc, value) after every single sale.
function SellService.onSold(callback: SoldCallback)
	table.insert(soldCallbacks, callback)
end

local function rarityOf(oreId: string): (string, number)
	local ore = OreData.ById[oreId]
	local info = ore and Rarity.ById[ore.Rarity]
	if info then
		return info.Id, info.Order
	end
	return "Common", 0
end

-- Sends the owner's combo so far ('Sold' to them, 'SellPuff' to others nearby).
local function flush(player: Player)
	flushQueued[player] = nil
	local combo = combos[player]
	if not combo or not combo.Dirty or not player.Parent then
		return
	end
	combo.Dirty = false
	Net.fire("Fx", player, "Sold", combo.Position, combo.Total, combo.Count, combo.Best)
	Net.fireNear("Fx", combo.Position, GameConfig.SellOthersRadius, player, "SellPuff", combo.Position)
	if combo.HadRaw then
		combo.HadRaw = false
		local data = DataService.get(player)
		local stats = data and data.Stats
		local sold = if type(stats) == "table" then tonumber(stats.ItemsSold) or 0 else 0
		local now = os.clock()
		if sold < RAW_TIP_UNTIL_SOLD and now - (lastTip[player] or -math.huge) >= RAW_TIP_COOLDOWN then
			lastTip[player] = now
			Net.fire("Notify", player, { Text = RAW_TIP, Kind = "Info" })
		end
	end
end

local function queueFlush(player: Player)
	if flushQueued[player] then
		return
	end
	flushQueued[player] = true
	task.defer(flush, player)
end

-- Pays the owner for an item that is already out of the world.
local function credit(player: Player, data: { [string]: any }, desc: Desc, value: number, position: Vector3)
	local stats = data.Stats
	if type(stats) == "table" then
		stats.ItemsSold = (tonumber(stats.ItemsSold) or 0) + 1
	end
	EconomyService.award(player, value, "Sell")

	local now = os.clock()
	local rarityId, order = rarityOf(desc.O)
	local combo = combos[player]
	if not combo or now - combo.LastAt > GameConfig.SellComboWindow then
		combo = {
			Total = 0,
			Count = 0,
			Best = rarityId,
			BestOrder = order,
			LastAt = now,
			Position = position,
			Dirty = false,
			HadRaw = false,
		}
		combos[player] = combo
	end
	combo.Total += value
	combo.Count += 1
	combo.LastAt = now
	combo.Position = position
	combo.Dirty = true
	if order > combo.BestOrder then
		combo.Best, combo.BestOrder = rarityId, order
	end
	if desc.K == "Raw" then
		combo.HadRaw = true
	end
	queueFlush(player)

	for _, callback in soldCallbacks do
		task.spawn(callback, player, desc, value)
	end
end

-- Coins an item is worth (0 = Pell can't buy it).
local function valueOf(desc: Desc): number
	if not MachineLogic.isValidDesc(desc) then
		return 0
	end
	return ItemData.value(desc.K, desc.O, desc.G, desc.R)
end

--[[
	Sells a physical item (loose, or carried and already taken off the carry
	stack with CarryService.takeTop). Pays the owner and returns the value.
	Returns 0 and leaves the item alone when it can't be sold right now
	(already sold, owner's data not loaded, worthless).
]]
function SellService.sell(record: ItemRecord, source: Source): number
	if record.State ~= "Loose" and record.State ~= "Carried" then
		return 0
	end
	local player = Players:GetPlayerByUserId(record.Owner)
	local data = player and DataService.get(player)
	if not player or not data then
		return 0
	end
	local desc = ItemService.descOf(record)
	local value = valueOf(desc)
	if value <= 0 then
		return 0
	end
	local position = record.Body.CFrame.Position
	-- out of the world first, then paid: no yield in between
	ItemService.absorb(record)
	credit(player, data, desc, value, position)
	return value
end

--[[
	Sells an item descriptor that is already out of the world (the Sell
	Chute's intake). Pays the owner; returns 0 (and sells nothing) when the
	owner's data isn't loaded or the item is worthless, so the caller can
	put the item back.
]]
function SellService.sellDesc(ownerUserId: number, desc: Desc, position: Vector3, source: string): number
	local player = Players:GetPlayerByUserId(ownerUserId)
	local data = player and DataService.get(player)
	if not player or not data then
		return 0
	end
	local value = valueOf(desc)
	if value <= 0 then
		return 0
	end
	credit(player, data, { K = desc.K, O = desc.O, G = desc.G, R = desc.R }, value, position)
	return value
end

---------------------------------------------------------------- Sell Chute

local function chutePosition(machine: PlacedMachine): Vector3
	local intake = MachineService.point(machine, "Intake")
	return if intake then intake.Position else machine.Model:GetPivot().Position + Vector3.new(0, 3, 0)
end

local chuteBehaviour: MachineService.Behaviour = {
	spawned = function(machine: PlacedMachine)
		machine.Model:SetAttribute("Cycles", 0)
		IntakeService.addLoadPrompt(machine, machine.Info.LoadText or "Sell Items", 0)
	end,
	-- anything worth something, from anyone (the sale pays the item's owner)
	canAccept = function(machine: PlacedMachine, desc: Desc, ownerUserId: number, _via: MachineService.Via): (boolean, MachineService.Reason?)
		local ok, reason = MachineLogic.accepts(machine.Id, desc, machine.Entry, ownerUserId == machine.Owner.UserId)
		if not ok then
			return false, reason
		end
		local owner = Players:GetPlayerByUserId(ownerUserId)
		if not owner or not DataService.get(owner) then
			return false, "Busy"
		end
		return true, nil
	end,
	insert = function(machine: PlacedMachine, desc: Desc, ownerUserId: number, _via: MachineService.Via)
		if SellService.sellDesc(ownerUserId, desc, chutePosition(machine), "Chute") <= 0 then
			-- MachineService puts the item back out instead of losing it
			error("the Sell Chute could not sell the item")
		end
		local cycles = machine.Model:GetAttribute("Cycles")
		machine.Model:SetAttribute("Cycles", (if type(cycles) == "number" then cycles else 0) + 1)
	end,
}

---------------------------------------------------------------- Pell's trading post

-- Something thrown into Pell's SellBin. An item Pell can't buy goes to
-- the owner's Storage instead of bouncing around in the bin.
local function binHandler(record: ItemRecord)
	if SellService.sell(record, "Bin") > 0 then
		return
	end
	if record.State == "Loose" then
		local owner = Players:GetPlayerByUserId(record.Owner)
		if owner and DataService.get(owner) then
			ItemService.stash(record, "Pell can't buy that")
		end
	end
end

-- "Sell What You Carry": sells every carried item Pell buys, top first.
-- `at` = the prompt's world position.
local function sellCarried(player: Player, at: Vector3)
	if not DataService.get(player) then
		return
	end
	local root = Guard.rootPart(player)
	if not root or (root.Position - at).Magnitude > COUNTER_DISTANCE + COUNTER_SLACK then
		return
	end
	local function sellable(record: ItemRecord): boolean
		return record.Owner == player.UserId and valueOf(ItemService.descOf(record)) > 0
	end
	local count, total = 0, 0
	for _ = 1, MAX_COUNTER_SALE do
		local record = CarryService.takeTop(player, sellable)
		if not record then
			break
		end
		-- no yield between taking it off the stack and selling it
		local value = SellService.sell(record, "Counter")
		if value <= 0 then
			-- can't happen for a checked item, but never lose one: put it down
			if record.State == "Carried" then
				ItemService.eject(record, Vector3.zero)
			end
			break
		end
		count += 1
		total += value
	end
	if count == 0 then
		Net.fire("Notify", player, { Text = EMPTY_HANDS, Kind = "Info" })
		return
	end
	local items = if count == 1 then "1 item" else `{count} items`
	Net.fire("Notify", player, { Text = `Sold {items}: +{Format.commas(total)} coins`, Kind = "Reward" })
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
	IntakeService.addZone("SellBin", part :: BasePart, binHandler)
end

local function hookCounter(counter: Instance)
	if hooked[counter] or not counter:IsA("BasePart") then
		return
	end
	hooked[counter] = true
	local part = counter :: BasePart
	-- the prompt sits on the customer side of the counter top
	local point = Instance.new("Attachment")
	point.Name = "SellPromptPoint"
	point.CFrame = CFrame.new(0, part.Size.Y / 2 + 0.6, -part.Size.Z / 2)
	point.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = "Sell What You Carry"
	prompt.ObjectText = "Pell the Trader"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = COUNTER_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = point
	prompt.Triggered:Connect(function(player)
		sellCarried(player, (part.CFrame * point.CFrame).Position)
	end)
end

local function hookTagged(tag: string, hook: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		hook(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/SellService.spec.luau).
SellService._test = {
	chute = chuteBehaviour,
	bin = binHandler,
	counter = sellCarried,
	hookBin = hookBin,
	hookCounter = hookCounter,
	flush = function()
		for player in flushQueued do
			flush(player)
		end
	end,
	reset = function()
		table.clear(combos)
		table.clear(flushQueued)
		table.clear(lastTip)
		table.clear(soldCallbacks)
	end,
}

function SellService.init()
	MachineService.register("SellChute", chuteBehaviour)
	Players.PlayerRemoving:Connect(function(player)
		combos[player] = nil
		flushQueued[player] = nil
		lastTip[player] = nil
	end)
end

function SellService.start()
	-- the map is built in WorldService.init, so Pell's stall exists by now
	hookTagged("SellBin", hookBin)
	hookTagged("SellCounter", hookCounter)
end

return SellService
