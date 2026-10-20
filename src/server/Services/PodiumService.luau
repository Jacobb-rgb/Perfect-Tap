--[[
	PodiumService: the podiums in every base yard and money per second
	(design v2).

	- data.Podiums = EconomyConfig.Podiums.Max storage keys ("" = empty).
	  Only cleaned ore (EconomyConfig.Podiums.Kinds) goes on a podium.
	  Slots 1..Free always work; the rest need the Podiums perk (100 R$).
	  An ore on a locked slot (perk gone) earns nothing but can be removed.
	- Place: one matching ore out of the Ore Pen onto a free, unlocked slot
	  (PodiumAction "Place" { Key }, or PenAction "ToPodium" via PenService).
	  Remove: back into the pen; refused (a toast, the ore stays on the
	  podium) while the pen is full ("PenFull") or over its capacity ("PenOver").
	  Prompts on every podium (the client shows the one that fits):
	    "Remove"         the ore goes back into the pen
	    "Place Ore"      opens PenView in pick mode (OpenUI "Pen" { Slot })
	    "Put On Podium"  the best cleaned ore you carry goes on the podium
	  Every change happens without a yield between the check and the write,
	  so racing requests can never duplicate an ore.
	- Looks: ItemBuilder.display on the podium's OrePoint (anchored, no
	  collision/query; PodiumController turns the ones near the camera
	  slowly) and a BillboardGui with "+$1.3K/s". Locked slots show a lock and a "100 R$"
	  plate until the owner has the perk.
	- Income: every EconomyConfig.IncomeTick seconds each loaded player gets
	  sum(ItemData.income(ore)) * EconomyService.incomeMultiplier(player) per
	  second (EconomyService.award, quiet), Stats.PodiumEarned grows,
	  LastSeen = now, and DataService.changed runs once (only when paid).
	- Offline: on load, EconomyConfig.offlineEarnings(income, now - LastSeen,
	  OfflineExtension perk) is paid (after OfflineDelay, and once the load's
	  game pass checks are done, MonetizationService.passesChecked, at most
	  PassWait seconds more, so the Night Shift perk counts) and the client
	  shows "While you were away"
	  (OpenUI "Offline" { Amount, Seconds, Hours }). LastSeen is written on
	  load, every tick and in beforeRelease. A LastSeen in the future (clock
	  skew between servers) or older than MIN_VALID_TIME pays nothing.
	- StateService gets Income (per second), PodiumSlots (2 or 4) and
	  PodiumIncome (per slot).
	- Step 8: the "CoinPack" receipt handler (registerGrants): coin packs
	  pay MonetizationConfig.coinPackAmount at the income now, only while
	  CoinPacksEnabled.
	Studio: perks are player attributes, e.g. Players.<you>:SetAttribute("Perk_Podiums", true).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Perks = require(script.Parent.Parent.Perks)
local PlotBuilder = require(script.Parent.Parent.World.PlotBuilder)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local EconomyService = require(script.Parent.EconomyService)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)
local PenService = require(script.Parent.PenService)

local PodiumService = {}

type Desc = ItemData.Desc
type ItemRecord = ItemService.ItemRecord
-- why an action was refused: NoData | BadSlot | Locked | NotClean | Taken | NotInPen | Empty | PenFull |
-- PenOver (PenService.OverReason: the pen holds more than its capacity) | NothingCarried
export type Reason = string

PodiumService.Range = 30 -- studs from a podium for PodiumAction (the hover button shows within this)
PodiumService.PromptTag = "PodiumPrompt"
PodiumService.OfflineDelay = 3 -- seconds after loading before offline earnings are paid
-- at most this many seconds more for the load's game pass checks (Night Shift's 12 h)
PodiumService.PassWait = 30
local RANGE_SLACK = 4
local TAG_HEIGHT = 2.6 -- studs from the ore point up to the income tag
local MIN_VALID_TIME = 1.5e9 -- os.time() of 2017: anything older is a broken LastSeen
local MAX_OFFLINE_SECONDS = 5 * 365 * 24 * 3600 -- longer is a broken clock, not a holiday
local MAX = EconomyConfig.Podiums.Max
local FREE = EconomyConfig.Podiums.Free

local clock: () -> number = os.time
-- plotId -> slot -> what that podium shows now
type Shown = { Key: string, Model: Model?, Tag: BillboardGui?, Text: string }
local shown: { [number]: { [number]: Shown } } = {}
local pendingOffline: { [Player]: number } = {} -- seconds away, paid after OfflineDelay
-- when each player last got a State push from podium income alone
local lastPush: { [Player]: number } = {}
local perkConnections: { [Player]: RBXScriptConnection } = {}
-- players whose offline payout waits for their pass checks
local waitingPasses: { [Player]: boolean } = {}
-- Swappable for the Lune tests: are the player's pass checks done?
local passesKnown: (player: Player) -> boolean = function(player: Player): boolean
	return MonetizationService.passesChecked(player)
end

local function toast(player: Player, text: string, kind: string?)
	Net.fire("Notify", player, { Text = text, Kind = kind or "Deny" })
end

---------------------------------------------------------------- slots and keys

function PodiumService.slotsFor(player: Player): number
	return if Perks.has(player, "Podiums") then MAX else FREE
end

function PodiumService.isUnlocked(player: Player, slot: number): boolean
	return slot >= 1 and slot <= PodiumService.slotsFor(player)
end

-- data.Podiums as exactly MAX strings (repaired in place).
local function podiumsOf(data: { [string]: any }): { string }
	local list = data.Podiums
	if type(list) ~= "table" then
		list = {}
		data.Podiums = list
	end
	for i = 1, MAX do
		if type(list[i]) ~= "string" then
			list[i] = ""
		end
	end
	return list
end

-- The ore a key stands for, if it may stand on a podium.
local function podiumDesc(key: any): Desc?
	if type(key) ~= "string" or key == "" then
		return nil
	end
	local desc = ItemData.parseKey(key)
	if desc and EconomyConfig.Podiums.Kinds[desc.K] then
		return desc
	end
	return nil
end

-- Coins per second from one slot (0 when empty, junk or locked).
function PodiumService.slotIncome(player: Player, data: { [string]: any }, slot: number, multiplier: number?): number
	if not PodiumService.isUnlocked(player, slot) then
		return 0
	end
	local desc = podiumDesc(podiumsOf(data)[slot])
	if not desc then
		return 0
	end
	return ItemData.income(desc) * (multiplier or EconomyService.incomeMultiplier(player))
end

-- Coins per second from all podiums.
function PodiumService.incomeOf(player: Player, data: { [string]: any }?): number
	local d = data or DataService.get(player)
	if not d then
		return 0
	end
	local multiplier = EconomyService.incomeMultiplier(player)
	local total = 0
	for slot = 1, MAX do
		total += PodiumService.slotIncome(player, d, slot, multiplier)
	end
	return total
end

---------------------------------------------------------------- the podiums in the world

local function podiumModel(plotId: number, slot: number): Model?
	local yard = PenService.yard(plotId)
	local m = yard and yard:FindFirstChild("Podium" .. slot)
	return if m and m:IsA("Model") then m else nil
end

-- World CFrame of a podium's ore point (bottom center of the shown ore).
local function orePoint(plotId: number, slot: number): CFrame
	local rect = BaseLayout.Podiums[slot]
	return PlotService.plotCFrame(plotId) * CFrame.new(rect.Center.X, BaseLayout.PodiumOreHeight, rect.Center.Z)
end

local function tagText(player: Player?, data: { [string]: any }?, slot: number): string
	if not player or not data then
		return ""
	end
	if not PodiumService.isUnlocked(player, slot) then
		return "Locked"
	end
	return Format.perSecond(PodiumService.slotIncome(player, data, slot))
end

-- "+$1.3K/s" and the ore's name, floating over the ore (oreY = world Y of the ore point).
local function makeTag(top: BasePart, desc: Desc, oreY: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "IncomeTag"
	gui.Size = UDim2.fromScale(5.5, 1.7) -- studs: it shrinks with distance like the podium
	gui.StudsOffsetWorldSpace = Vector3.new(0, oreY - top.CFrame.Position.Y + TAG_HEIGHT, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Size = UDim2.fromScale(1, 0.6)
	amount.FontFace = Theme.TitleFont
	amount.TextScaled = true
	amount.TextColor3 = Theme.Coin
	amount.TextStrokeTransparency = 0.2
	amount.TextStrokeColor3 = Theme.Outline
	amount.Text = ""
	amount.Parent = gui
	local ore = OreData.ById[desc.O]
	local rarity = ore and Rarity.ById[ore.Rarity]
	local name = Instance.new("TextLabel")
	name.Name = "OreName"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0, 0.6)
	name.Size = UDim2.fromScale(1, 0.4)
	name.FontFace = Theme.Font
	name.TextScaled = true
	name.TextColor3 = if rarity then rarity.Color else Theme.Text
	name.TextStrokeTransparency = 0.3
	name.TextStrokeColor3 = Theme.Outline
	name.Text = ItemData.displayName(desc.K, desc.O, desc.G, desc.R)
	name.Parent = gui
	gui.Adornee = top
	gui.Parent = top
	return gui
end

local function setTagText(entry: Shown, text: string)
	if entry.Text == text then
		return
	end
	entry.Text = text
	local tag = entry.Tag
	local label = tag and tag:FindFirstChild("Amount")
	if label and label:IsA("TextLabel") then
		label.Text = text
		label.TextColor3 = if text == "Locked" then Theme.TextDim else Theme.Coin
	end
end

local function clearShown(entry: Shown)
	if entry.Model then
		entry.Model:Destroy()
	end
	if entry.Tag then
		entry.Tag:Destroy()
	end
	entry.Model = nil
	entry.Tag = nil
	entry.Key = ""
	entry.Text = ""
end

local function buildDisplay(plotId: number, slot: number, desc: Desc): (Model?, BillboardGui?)
	local podium = podiumModel(plotId, slot)
	local top = podium and podium:FindFirstChild("Top")
	if not podium or not top or not top:IsA("BasePart") then
		return nil, nil
	end
	local point = orePoint(plotId, slot)
	local ok, built = pcall(ItemBuilder.display, desc, point, `{plotId}/{slot}/{desc.O}`)
	if not ok or typeof(built) ~= "Instance" then
		warn(`[PodiumService] could not build the {desc.O} display: {built}`)
		return nil, nil
	end
	local model = built :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	model.Name = "Display"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = podium
	return model, makeTag(top, desc, point.Position.Y)
end

-- Locked slots: lock + price plate visible and a dull rim until the owner has the perk.
local function refreshLocks(plotId: number, owner: Player?)
	for slot = FREE + 1, MAX do
		local podium = podiumModel(plotId, slot)
		if podium then
			local unlocked = owner ~= nil and PodiumService.isUnlocked(owner, slot)
			local lock = podium:FindFirstChild("Lock")
			if lock then
				for _, d in lock:GetDescendants() do
					if d:IsA("BasePart") then
						d.Transparency = if unlocked then 1 else 0
					end
				end
			end
			local plate = podium:FindFirstChild("PricePlate")
			if plate and plate:IsA("BasePart") then
				plate.Transparency = if unlocked then 1 else 0
				local gui = plate:FindFirstChildOfClass("SurfaceGui")
				if gui then
					gui.Enabled = not unlocked
				end
			end
			local rim = podium:FindFirstChild("Rim")
			if rim and rim:IsA("BasePart") then
				rim.Color = if unlocked then PlotBuilder.RimGold else PlotBuilder.RimLocked
				rim.Material = if unlocked then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end

-- Makes a plot's podiums show what its owner's data says (nothing when free).
function PodiumService.refreshPlot(plotId: number)
	local owner = PlotService.ownerOf(plotId)
	local data = if owner then DataService.get(owner) else nil
	local list = if data then podiumsOf(data) else nil
	local perPlot = shown[plotId]
	if not perPlot then
		perPlot = {}
		shown[plotId] = perPlot
	end
	for slot = 1, MAX do
		local entry = perPlot[slot]
		if not entry then
			entry = { Key = "", Model = nil, Tag = nil, Text = "" }
			perPlot[slot] = entry
		end
		local key = if list then list[slot] else ""
		local desc = podiumDesc(key)
		local want = if desc then key else ""
		if entry.Key ~= want then
			clearShown(entry)
			if desc then
				entry.Key = want
				entry.Model, entry.Tag = buildDisplay(plotId, slot, desc)
			end
		end
		if entry.Key ~= "" then
			setTagText(entry, tagText(owner, data, slot))
		end
	end
	refreshLocks(plotId, owner)
end

local function refreshPlayer(player: Player)
	local plotId = PlotService.plotOf(player)
	if plotId then
		PodiumService.refreshPlot(plotId)
	end
end

local function effect(player: Player, plotId: number, slot: number, kind: string, oreId: string)
	Net.fire("Fx", player, kind, orePoint(plotId, slot).Position, oreId)
end

---------------------------------------------------------------- actions

-- Common checks: data loaded, a real slot. Returns the podium list.
local function begin(player: Player, slot: number): ({ string }?, Reason?)
	local data = DataService.get(player)
	if not data then
		return nil, "NoData"
	end
	if type(slot) ~= "number" or slot ~= slot or slot < 1 or slot > MAX or slot ~= math.floor(slot) then
		return nil, "BadSlot"
	end
	return podiumsOf(data), nil
end

local function lockedToast(player: Player)
	toast(player, "Podiums 3 and 4 come with the Podium Pass (100 R$). Coming soon!", "Info")
end

-- Places one ore with this storage key from the pen onto a slot.
function PodiumService.place(player: Player, slot: number, key: string): (boolean, Reason?)
	local list, why = begin(player, slot)
	if not list then
		return false, why
	end
	if not PodiumService.isUnlocked(player, slot) then
		lockedToast(player)
		return false, "Locked"
	end
	local desc = podiumDesc(key)
	if not desc then
		toast(player, "Only cleaned ore can go on a podium. Clean dirty ore at the Cleaning Station.")
		return false, "NotClean"
	end
	if list[slot] ~= "" then
		toast(player, "That podium already has an ore. Remove it first.")
		return false, "Taken"
	end
	local canonical = ItemData.storageKey(desc)
	local taken = PenService.takeOne(player, canonical)
	if not taken then
		toast(player, "That ore is not in your Ore Pen anymore.")
		return false, "NotInPen"
	end
	list[slot] = canonical
	DataService.changed(player)
	local plotId = PlotService.plotOf(player)
	if plotId then
		PodiumService.refreshPlot(plotId)
		effect(player, plotId, slot, "PodiumPlaced", desc.O)
	end
	return true, nil
end

-- Moves the ore on a slot back into the pen (locked slots too).
function PodiumService.remove(player: Player, slot: number): (boolean, Reason?)
	local list, why = begin(player, slot)
	if not list then
		return false, why
	end
	local key = list[slot]
	if key == "" then
		return false, "Empty"
	end
	local desc = podiumDesc(key)
	if not desc then
		local parts = string.split(key, "|")
		if ItemData.parseKey(key) == nil and #parts == 4 and parts[1] ~= "" and parts[2] ~= "" then
			-- an ore a newer build knows (docs/SAVE_AUDIT.md #1(b)): it goes into the pen as it
			-- is (the newer build reads it there again) and the slot is free
			local kept: Desc = {
				K = parts[1],
				O = parts[2],
				G = if parts[3] ~= "" then parts[3] else nil,
				R = if parts[4] ~= "" then parts[4] else nil,
			} :: any
			if not PenService.store(player, kept) then
				local data = DataService.get(player) :: { [string]: any }
				toast(player, `Your Ore Pen is full ({#data.Storage}/{PenService.capacityOf(data)}). Make room first.`)
				return false, "PenFull"
			end
			list[slot] = ""
			DataService.changed(player)
			refreshPlayer(player)
			toast(player, "This ore needs the newest version of the game. It is in your Ore Pen, rejoin to see it.", "Info")
			return true, nil
		end
		-- junk that slipped past the migration: just clear it
		list[slot] = ""
		DataService.changed(player)
		refreshPlayer(player)
		return false, "Empty"
	end
	-- the pen must take it (never over its capacity, never while it is over
	-- it: "PenOver"); refused, the ore simply stays on the podium
	local stored, refusal = PenService.store(player, desc)
	if not stored then
		local data = DataService.get(player) :: { [string]: any }
		if refusal == PenService.OverReason then
			toast(player, PenService.overText(data))
			return false, PenService.OverReason
		end
		toast(player, `Your Ore Pen is full ({#data.Storage}/{PenService.capacityOf(data)}). Make room first.`)
		return false, "PenFull"
	end
	list[slot] = ""
	DataService.changed(player)
	local plotId = PlotService.plotOf(player)
	if plotId then
		PodiumService.refreshPlot(plotId)
		effect(player, plotId, slot, "PodiumRemoved", desc.O)
	end
	return true, nil
end

-- "Put On Podium": the best cleaned ore you carry goes onto the slot.
function PodiumService.placeFromHands(player: Player, slot: number): (boolean, Reason?)
	local list, why = begin(player, slot)
	if not list then
		return false, why
	end
	if not PodiumService.isUnlocked(player, slot) then
		lockedToast(player)
		return false, "Locked"
	end
	if list[slot] ~= "" then
		toast(player, "That podium already has an ore. Remove it first.")
		return false, "Taken"
	end
	local best: ItemRecord? = nil
	local bestIncome = -1
	for _, record in CarryService.list(player) do
		if record.State == "Carried" and EconomyConfig.Podiums.Kinds[record.Kind] then
			local income = ItemData.income(ItemService.descOf(record))
			if income > bestIncome then
				best, bestIncome = record, income
			end
		end
	end
	local chosen = best
	if not chosen then
		return false, "NothingCarried"
	end
	local record = CarryService.takeTop(player, function(r: ItemRecord): boolean
		return r == chosen
	end)
	if not record then
		return false, "NothingCarried"
	end
	-- no yield between taking it off the stack and putting it on the podium
	local desc = ItemService.absorb(record)
	list[slot] = ItemData.storageKey(desc)
	DataService.changed(player)
	local plotId = PlotService.plotOf(player)
	if plotId then
		PodiumService.refreshPlot(plotId)
		effect(player, plotId, slot, "PodiumPlaced", desc.O)
	end
	return true, nil
end

-- "Place Ore": opens the pen in pick mode for an empty, unlocked slot.
local function openPicker(player: Player, slot: number)
	local list = begin(player, slot)
	if not list then
		return
	end
	if not PodiumService.isUnlocked(player, slot) then
		lockedToast(player)
		return
	end
	if list[slot] ~= "" then
		toast(player, "That podium already has an ore. Remove it first.")
		return
	end
	Net.fire("OpenUI", player, "Pen", { Slot = slot })
end

-- Is the player standing near one of their own podiums (flat distance)?
local function isNear(player: Player, plotId: number, slot: number): boolean
	local root = Guard.rootPart(player)
	if not root then
		return false
	end
	local offset = root.Position - orePoint(plotId, slot).Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= PodiumService.Range + RANGE_SLACK
end

-- PodiumAction (slot 1..4, "Remove" | "Place", { Key }?)
local function onAction(player: Player, slotArg: any, actionArg: any, argArg: any)
	local slot = Guard.integer(slotArg, 1, MAX)
	local action = Guard.string(actionArg, 16)
	if not slot or not action then
		return
	end
	local plotId = PlotService.plotOf(player)
	if not plotId or not DataService.get(player) then
		return
	end
	if not isNear(player, plotId, slot) then
		toast(player, "Walk closer to your podium.")
		return
	end
	if action == "Remove" then
		PodiumService.remove(player, slot)
	elseif action == "Place" then
		local arg = Guard.table(argArg, 4)
		local key = arg and Guard.string(arg.Key, 80)
		if key then
			PodiumService.place(player, slot, key)
		end
	end
end

-- A podium prompt was used (the client shows only the one that fits).
local function onPrompt(player: Player, plotId: number, slot: number, action: string)
	if PlotService.ownerOf(plotId) ~= player then
		toast(player, "That's not your podium.")
		return
	end
	if not isNear(player, plotId, slot) then
		return
	end
	if action == "Remove" then
		PodiumService.remove(player, slot)
	elseif action == "Put" then
		local ok, why = PodiumService.placeFromHands(player, slot)
		if not ok and why == "NothingCarried" then
			openPicker(player, slot)
		end
	else
		openPicker(player, slot)
	end
end

local PROMPTS = {
	{ Name = "PodiumRemove", Action = "Remove", Text = "Remove" },
	{ Name = "PodiumPlace", Action = "Place", Text = "Place Ore" },
	{ Name = "PodiumPut", Action = "Put", Text = "Put On Podium" },
}

local function setupPrompts(plotId: number)
	for slot = 1, MAX do
		local podium = podiumModel(plotId, slot)
		local top = podium and podium:FindFirstChild("Top")
		if top then
			local anchor = top:FindFirstChild("Prompt") or top
			for _, info in PROMPTS do
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = info.Name
				prompt.ActionText = info.Text
				prompt.ObjectText = "Podium " .. slot
				prompt.KeyboardKeyCode = Enum.KeyCode.F
				prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 9
				prompt.RequiresLineOfSight = false
				prompt:SetAttribute("PlotId", plotId)
				prompt:SetAttribute("Slot", slot)
				prompt:SetAttribute("Action", info.Action)
				prompt:AddTag(PodiumService.PromptTag)
				prompt.Parent = anchor
				local action = info.Action
				prompt.Triggered:Connect(function(player: Player)
					onPrompt(player, plotId, slot, action)
				end)
			end
		end
	end
end

---------------------------------------------------------------- income

local function payOne(player: Player, now: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.LastSeen = now
	local amount = PodiumService.incomeOf(player, data) * EconomyConfig.IncomeTick
	if amount >= 0.001 and amount <= EconomyConfig.MaxAward then
		EconomyService.award(player, amount, "Podium", true)
		local stats = data.Stats
		if type(stats) == "table" then
			stats.PodiumEarned = (tonumber(stats.PodiumEarned) or 0) + amount
		end
		-- the HUD counts up by itself; a full snapshot only every few seconds
		local last = lastPush[player]
		if not last or now - last >= EconomyConfig.StatePushSeconds or now < last then
			lastPush[player] = now
			DataService.changed(player)
		end
	end
end

-- One payout to every loaded player (EconomyConfig.IncomeTick seconds of income).
-- One player's error never stops the others' income.
function PodiumService.tick()
	local now = clock()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(payOne :: any, player, now)
		if not ok then
			warn(`[PodiumService] income for {player.Name} failed: {err}`)
		end
	end
end

-- Seconds away that count for offline earnings (0 for a broken or skewed clock).
function PodiumService.offlineSeconds(lastSeen: any, now: number): number
	if type(lastSeen) ~= "number" or lastSeen ~= lastSeen or lastSeen < MIN_VALID_TIME then
		return 0
	end
	local elapsed = now - lastSeen
	if elapsed ~= elapsed or elapsed <= 0 or elapsed > MAX_OFFLINE_SECONDS then
		return 0
	end
	return elapsed
end

-- Pays the offline earnings that were waiting for this player. Returns the amount.
local function payOffline(player: Player, popup: boolean): number
	local seconds = pendingOffline[player]
	pendingOffline[player] = nil
	local data = DataService.get(player)
	if not seconds or not data then
		return 0
	end
	local extended = Perks.has(player, "OfflineExtension")
	local amount = EconomyConfig.offlineEarnings(PodiumService.incomeOf(player, data), seconds, extended)
	if amount < 0.001 or amount > EconomyConfig.MaxAward then
		return 0
	end
	EconomyService.award(player, amount, "Offline")
	local stats = data.Stats
	if type(stats) == "table" then
		stats.PodiumEarned = (tonumber(stats.PodiumEarned) or 0) + amount
	end
	if popup and player.Parent then
		local o = EconomyConfig.Offline
		Net.fire("OpenUI", player, "Offline", {
			Amount = amount,
			Seconds = seconds,
			Hours = if extended then o.ExtendedHours else o.BaseHours,
		})
	end
	return amount
end

-- OfflineDelay after the load: pay now when the pass checks are done, else when they
-- are (onPassesChecked) or after PassWait (the OfflineExtension perk comes from a pass).
local function offlineDue(player: Player)
	if not pendingOffline[player] then
		return
	end
	if passesKnown(player) then
		payOffline(player, true)
		return
	end
	waitingPasses[player] = true
	task.delay(PodiumService.PassWait, function()
		waitingPasses[player] = nil
		if pendingOffline[player] then
			payOffline(player, true)
		end
	end)
end

local function onLoaded(player: Player, data: { [string]: any })
	local now = clock()
	podiumsOf(data)
	local seconds = PodiumService.offlineSeconds(data.LastSeen, now)
	data.LastSeen = now
	if seconds >= EconomyConfig.Offline.MinSeconds then
		pendingOffline[player] = seconds
		task.delay(PodiumService.OfflineDelay, function()
			offlineDue(player)
		end)
	end
end

-- MonetizationService.onPassesChecked: a payout that waited for the pass checks goes now.
local function onPassesChecked(player: Player)
	if not waitingPasses[player] then
		return
	end
	waitingPasses[player] = nil
	if pendingOffline[player] then
		payOffline(player, true)
	end
end

--[[
	The "CoinPack" receipt handler (MonetizationService.register; step 8
	contract): only while MonetizationConfig.CoinPacksEnabled (else false:
	the receipt waits, never coins while coins aren't buyable), coins =
	MonetizationConfig.coinPackAmount at the player's podium income now.
	No yield.
]]
local function grantCoins(player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	if not MonetizationConfig.coinsBuyable() or not entry.CoinPack or DataService.get(player) ~= data then
		return false
	end
	local amount = MonetizationConfig.coinPackAmount(entry.Key, PodiumService.incomeOf(player, data))
	if not amount or amount <= 0 then
		return false
	end
	amount = math.min(amount, EconomyConfig.MaxAward)
	local before = EconomyService.balance(player)
	if EconomyService.award(player, amount, "CoinPack:" .. entry.Key) <= before then
		return false
	end
	toast(player, `+{Format.big(amount)} coins. Thank you!`, "Reward")
	return true
end

-- Registers the "CoinPack" receipt handler (init(); idempotent).
function PodiumService.registerGrants()
	MonetizationService.register("CoinPack", grantCoins)
end

local function onRelease(player: Player, data: { [string]: any })
	-- left before the welcome-back payout: pay it now (no popup)
	if pendingOffline[player] then
		payOffline(player, false)
	end
	data.LastSeen = clock()
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/PodiumService.spec.luau).
PodiumService._test = {
	action = onAction,
	prompt = onPrompt,
	openPicker = openPicker,
	loaded = onLoaded,
	release = onRelease,
	payOffline = payOffline,
	setupPrompts = setupPrompts,
	pending = function(player: Player): number?
		return pendingOffline[player]
	end,
	setPassesKnown = function(fn: (Player) -> boolean)
		passesKnown = fn
	end,
	waiting = function(player: Player): boolean
		return waitingPasses[player] == true
	end,
	passesChecked = onPassesChecked,
	offlineDue = offlineDue,
	shown = function(plotId: number, slot: number): Shown?
		local perPlot = shown[plotId]
		return perPlot and perPlot[slot]
	end,
	setClock = function(fn: (() -> number)?)
		clock = fn or os.time
	end,
	reset = function()
		for _, perPlot in shown do
			for _, entry in perPlot do
				clearShown(entry)
			end
		end
		table.clear(shown)
		table.clear(lastPush)
		table.clear(pendingOffline)
		table.clear(waitingPasses)
		clock = os.time
		passesKnown = function(player: Player): boolean
			return MonetizationService.passesChecked(player)
		end
	end,
}

local function watchPerks(player: Player)
	if perkConnections[player] then
		return
	end
	perkConnections[player] = player:GetAttributeChangedSignal("Perk_Podiums"):Connect(function()
		refreshPlayer(player)
		DataService.changed(player)
	end)
end

function PodiumService.init()
	Net.on("PodiumAction", onAction)
	PenService.setPodiumPlacer(PodiumService.place)
	StateService.addProvider(function(player, data, snapshot)
		local multiplier = EconomyService.incomeMultiplier(player)
		local perSlot = {}
		local total = 0
		for slot = 1, MAX do
			local income = PodiumService.slotIncome(player, data, slot, multiplier)
			perSlot[slot] = income
			total += income
		end
		snapshot.Income = total
		snapshot.PodiumIncome = perSlot
		snapshot.PodiumSlots = PodiumService.slotsFor(player)
	end)
	for _, plot in WorldLayout.Plots do
		setupPrompts(plot.Id)
		refreshLocks(plot.Id, nil)
	end
	DataService.onLoaded(onLoaded)
	DataService.beforeRelease(onRelease)
	-- step 8: coin pack receipts (off while CoinPacksEnabled is false); the offline payout
	-- waits for the pass checks (Night Shift)
	PodiumService.registerGrants()
	MonetizationService.onPassesChecked(onPassesChecked)
	PlotService.onAssigned(function(_, plotId)
		PodiumService.refreshPlot(plotId)
	end)
	PlotService.onReleased(function(_, plotId)
		-- runs before the plot is freed: show it empty and locked again
		local perPlot = shown[plotId]
		if perPlot then
			for _, entry in perPlot do
				clearShown(entry)
			end
		end
		refreshLocks(plotId, nil)
	end)
	Players.PlayerAdded:Connect(watchPerks)
	for _, player in Players:GetPlayers() do
		watchPerks(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- pendingOffline is cleared by payOffline (also run from beforeRelease,
		-- whose order against this handler is not guaranteed); drop leftovers later
		task.delay(10, function()
			pendingOffline[player] = nil
			waitingPasses[player] = nil
		end)
		lastPush[player] = nil
		local connection = perkConnections[player]
		if connection then
			connection:Disconnect()
			perkConnections[player] = nil
		end
	end)
end

function PodiumService.start()
	local lastTags = os.clock()
	while true do
		task.wait(EconomyConfig.IncomeTick)
		PodiumService.tick()
		-- income tags follow bonus changes (golems, passes) every few seconds
		if os.clock() - lastTags >= 5 then
			lastTags = os.clock()
			for plotId in shown do
				local ok, err = pcall(PodiumService.refreshPlot :: any, plotId)
				if not ok then
					warn(`[PodiumService] refreshing plot {plotId} failed: {err}`)
				end
			end
		end
	end
end

return PodiumService
