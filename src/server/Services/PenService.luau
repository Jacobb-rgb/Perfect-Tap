--[[
	PenService: the Ore Pen in every base yard (design v2). Each player has
	one pen, saved as data.Storage (a list of item descriptors { K, O, G?, R? }).

	- Capacity: EconomyConfig.penCapacity(Upgrades.PenLevel, GameConfig.MaxStoredItems)
	  (pen upgrades are bought in the shops, step 6). Players can only fill
	  the pen up to it; system writes (leaving, the loose-item cap, packing a
	  machine up) go through ItemService.storeDesc, which pays Tobin's price
	  for anything that doesn't fit.
	- In: drop or throw your own items into the pen (the yard's Pen.Intake
	  box, an IntakeService zone), or press "Put In" (F / gamepad Y) at the
	  pen gate while carrying items. Items of other players are not taken:
	  they bounce back out of the gate. A full pen bounces items too (toast).
	- Out: "Open Pen" (G / gamepad B) opens PenView (OpenUI "Pen"). PenAction:
	    "Take"     { Key, Count 1..StorageTakeMax }: the items appear at the
	               gate and go into your hands while they have room
	    "ToPodium" { Key, Slot }: puts one cleaned ore on a podium (PodiumService)
	  Checks: types (Guard), ItemData.parseKey, your own plot, standing within
	  Range (+ slack) of your pen gate.
	- StateService gets PenCapacity.
	Prompts are made for every plot once; the client shows them only on your
	own pen ("Put In" only while you carry something), the server checks again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local PlotService = require(script.Parent.PlotService)
local IntakeService = require(script.Parent.IntakeService)

local PenService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord
export type PodiumPlacer = (player: Player, slot: number, key: string) -> (boolean, string?)

PenService.Range = 24 -- studs from your pen gate (PenView closes beyond this)
PenService.PromptTag = "PenPrompt"
local RANGE_SLACK = 4 -- the server allows a little more (lag, walking while clicking)
local FULL_TOAST_COOLDOWN = 5
local FOREIGN_TOAST_COOLDOWN = 8
local TAKE_SPACING = 0.6 -- taken items appear this much higher each
local MAX_PUT_IN = 64 -- more than any carry stack
local MAX_KEY_LENGTH = 80
local GATE_OUT = 1.6 -- studs in front of the gate where items come out
local HANDS_FULL = "Your hands are full and lots of items are lying around. Pick some up first!"

local lastFullToast: { [Player]: number } = {}
local lastForeignToast: { [Player]: number } = {}
local podiumPlacer: PodiumPlacer? = nil

---------------------------------------------------------------- capacity

function PenService.capacityOf(data: { [string]: any }): number
	return ItemService.penCapacity(data)
end

function PenService.capacity(player: Player): number
	local data = DataService.get(player)
	return if data then PenService.capacityOf(data) else 0
end

function PenService.count(player: Player): number
	local data = DataService.get(player)
	return if data then #data.Storage else 0
end

-- Room for `n` (default 1) more items?
function PenService.hasRoom(player: Player, n: number?): boolean
	local data = DataService.get(player)
	return data ~= nil and #data.Storage + (n or 1) <= PenService.capacityOf(data)
end

-- Puts one item into the pen when it has room (no sale fallback). The
-- caller calls DataService.changed (several changes, one push).
function PenService.store(player: Player, desc: Desc): boolean
	local data = DataService.get(player)
	if not data or #data.Storage >= PenService.capacityOf(data) then
		return false
	end
	table.insert(data.Storage, { K = desc.K, O = desc.O, G = desc.G, R = desc.R })
	return true
end

-- Takes one item with this storage key out of the pen (the newest one).
-- The caller calls DataService.changed.
function PenService.takeOne(player: Player, key: string): Desc?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local storage = data.Storage
	for i = #storage, 1, -1 do
		local entry = storage[i]
		if type(entry) == "table" and type(entry.K) == "string" and type(entry.O) == "string" and ItemData.storageKey(entry) == key then
			table.remove(storage, i)
			return entry :: Desc
		end
	end
	return nil
end

-- PodiumService plugs in here ("ToPodium" lives in PenAction).
function PenService.setPodiumPlacer(placer: PodiumPlacer)
	podiumPlacer = placer
end

---------------------------------------------------------------- the pen in the world

-- The yard model of a plot (nil on maps from before the yards).
function PenService.yard(plotId: number): Model?
	local plot = PlotService.model(plotId)
	local yard = plot and plot:FindFirstChild("Yard")
	return if yard and yard:IsA("Model") then yard else nil
end

-- World CFrame of the pen gate (BaseLayout.Pen.PromptPoint), LookVector
-- toward the machine grid (out of the pen).
function PenService.gateCFrame(plotId: number): CFrame
	return PlotService.plotCFrame(plotId) * CFrame.new(BaseLayout.Pen.PromptPoint)
end

-- Is the player standing near their own pen gate (flat distance)?
function PenService.isNear(player: Player, plotId: number, range: number?): boolean
	local root = Guard.rootPart(player)
	if not root then
		return false
	end
	local gate = PenService.gateCFrame(plotId).Position
	local offset = root.Position - gate
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= (range or PenService.Range) + RANGE_SLACK
end

local function toast(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, { Text = text, Kind = kind or "Deny" })
end

local function fullText(data: { [string]: any }): string
	return `Your Ore Pen is full ({#data.Storage}/{PenService.capacityOf(data)}). Sell ore at Tobin's stall or put some on a podium.`
end

local function fullToast(player: Player, data: { [string]: any })
	local now = os.clock()
	if now - (lastFullToast[player] or -math.huge) < FULL_TOAST_COOLDOWN then
		return
	end
	lastFullToast[player] = now
	toast(player, fullText(data))
end

-- Pops a loose item out of the pen gate (refused: pen full or not yours).
local function bounceOut(plotId: number, record: ItemRecord)
	local gate = PenService.gateCFrame(plotId)
	local side = (math.random() - 0.5) * 3
	local out = gate * CFrame.new(side, 0, -GATE_OUT)
	ItemService.release(record, out, gate.LookVector * 8 + Vector3.new(0, 12, 0))
end

--[[
	An item came to rest in (or flew into) a pen's intake box. The owner's
	own items go in while there is room; everything else bounces out.
]]
local function onIntake(plotId: number, record: ItemRecord)
	if record.State ~= "Loose" then
		return
	end
	local owner = PlotService.ownerOf(plotId)
	if not owner or owner.UserId ~= record.Owner then
		bounceOut(plotId, record)
		local thrower = Players:GetPlayerByUserId(record.Owner)
		if thrower then
			local now = os.clock()
			if now - (lastForeignToast[thrower] or -math.huge) >= FOREIGN_TOAST_COOLDOWN then
				lastForeignToast[thrower] = now
				toast(thrower, "That's not your Ore Pen. Your pen is in the yard behind your own forge.", "Info")
			end
		end
		return
	end
	local data = DataService.get(owner)
	if not data then
		bounceOut(plotId, record)
		return
	end
	if #data.Storage >= PenService.capacityOf(data) then
		bounceOut(plotId, record)
		fullToast(owner, data)
		Net.fire("Fx", owner, "Reject", record.Body.CFrame.Position)
		return
	end
	local position = record.Body.CFrame.Position
	local desc = ItemService.absorb(record)
	table.insert(data.Storage, desc)
	DataService.changed(owner)
	Net.fire("Fx", owner, "PenIn", position)
end

---------------------------------------------------------------- prompts

-- "Put In": everything you carry goes in while the pen has room.
local function putIn(player: Player, plotId: number)
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your Ore Pen.")
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	if #CarryService.list(player) == 0 then
		toast(player, "Carry ore here to put it in your pen.", "Info")
		return
	end
	local stored = 0
	for _ = 1, MAX_PUT_IN do
		if #data.Storage >= PenService.capacityOf(data) then
			break
		end
		local record = CarryService.takeTop(player)
		if not record then
			break
		end
		-- no yield between taking it off the stack and storing it
		table.insert(data.Storage, ItemService.absorb(record))
		stored += 1
	end
	if stored > 0 then
		DataService.changed(player)
		Net.fire("Fx", player, "PenIn", PenService.gateCFrame(plotId).Position + Vector3.new(0, 1, 0))
	end
	if #CarryService.list(player) > 0 then
		toast(player, fullText(data))
	end
end

local function openPen(player: Player, plotId: number)
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your Ore Pen.")
		return
	end
	if DataService.get(player) then
		Net.fire("OpenUI", player, "Pen", {})
	end
end

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
	prompt.ObjectText = "Ore Pen"
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
	prompt:SetAttribute("PlotId", plotId)
	prompt:AddTag(PenService.PromptTag)
	prompt.Parent = parent
	return prompt
end

-- Intake zone and prompts for one plot's pen (once, at start).
local function setupPen(plotId: number): boolean
	local yard = PenService.yard(plotId)
	local pen = yard and yard:FindFirstChild("Pen")
	local intake = pen and pen:FindFirstChild("Intake")
	if not intake or not intake:IsA("BasePart") then
		warn(`[PenService] plot {plotId} has no Yard.Pen.Intake (old map?)`)
		return false
	end
	IntakeService.addZone("Pen" .. plotId, intake, function(record: ItemRecord)
		onIntake(plotId, record)
	end)
	local anchor = intake:FindFirstChild("Prompt") or intake
	local put = makePrompt(anchor, plotId, "PenPutIn", "Put In", Enum.KeyCode.F, Enum.KeyCode.ButtonY, 0)
	put.Triggered:Connect(function(player: Player)
		putIn(player, plotId)
	end)
	local open = makePrompt(anchor, plotId, "PenOpen", "Open Pen", Enum.KeyCode.G, Enum.KeyCode.ButtonB, 1)
	open.Triggered:Connect(function(player: Player)
		openPen(player, plotId)
	end)
	return true
end

---------------------------------------------------------------- PenAction

--[[
	"Take": at most what fits in free hands plus the room left under the
	loose-item cap (so taking never pushes other items back into the pen).
	Each item appears at the pen gate and goes into your hands while they
	have room.
]]
local function takeItems(player: Player, plotId: number, data: { [string]: any }, key: string, count: number): number
	local freeHands = math.max(0, CarryService.capacity(player) - #CarryService.list(player))
	local looseRoom = math.max(0, GameConfig.MaxLooseItemsPerPlayer - GameConfig.LooseHeadroom - ItemService.looseCount(player.UserId))
	local allowed = math.min(count, freeHands + looseRoom)
	if allowed <= 0 then
		toast(player, HANDS_FULL)
		return 0
	end
	local gate = PenService.gateCFrame(plotId) * CFrame.new(0, 0.6, -GATE_OUT)
	local taken = 0
	for i = 1, allowed do
		local entry = PenService.takeOne(player, key)
		if not entry then
			break
		end
		local record = ItemService.spawnDesc(entry, player.UserId, gate + Vector3.new(0, TAKE_SPACING * (i - 1), 0))
		if not record then
			-- never lose it: back into the pen
			table.insert(data.Storage, entry)
			warn(`[PenService] could not take {key} out for {player.Name}`)
			break
		end
		taken += 1
		if freeHands > 0 and CarryService.pickup(player, record) then
			freeHands -= 1
		end
	end
	if taken > 0 then
		DataService.changed(player)
	end
	return taken
end

local function onAction(player: Player, actionArg: any, argArg: any)
	local action = Guard.string(actionArg, 16)
	local arg = Guard.table(argArg, 4)
	if not action or not arg then
		return
	end
	local keyText = Guard.string(arg.Key, MAX_KEY_LENGTH)
	local desc = if keyText then ItemData.parseKey(keyText) else nil
	if not desc then
		return
	end
	local key = ItemData.storageKey(desc)
	local plotId = PlotService.plotOf(player)
	local data = DataService.get(player)
	if not plotId or not data then
		return
	end
	if not PenService.isNear(player, plotId) then
		toast(player, "Walk back to your Ore Pen first.")
		return
	end
	if action == "Take" then
		local count = Guard.integer(arg.Count, 1, GameConfig.StorageTakeMax)
		if count then
			takeItems(player, plotId, data, key, count)
		end
	elseif action == "ToPodium" then
		local slot = Guard.integer(arg.Slot, 1, EconomyConfig.Podiums.Max)
		local placer = podiumPlacer
		if slot and placer then
			placer(player, slot, key)
		end
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/PenService.spec.luau).
PenService._test = {
	action = onAction,
	intake = onIntake,
	putIn = putIn,
	open = openPen,
	setupPen = setupPen,
	reset = function()
		table.clear(lastFullToast)
		table.clear(lastForeignToast)
		podiumPlacer = nil
	end,
}

function PenService.init()
	Net.on("PenAction", onAction)
	StateService.addProvider(function(_, data, snapshot)
		snapshot.PenCapacity = PenService.capacityOf(data)
	end)
	for _, plot in WorldLayout.Plots do
		setupPen(plot.Id)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastFullToast[player] = nil
		lastForeignToast[player] = nil
	end)
end

return PenService
