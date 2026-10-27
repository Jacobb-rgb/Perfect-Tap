--[[
	BackpackService: the backpacks you own and wear, and the BACKPACKS shop
	(owner 2026-10-24: ten packs, coins only; the packs, their looks, the shop
	building and its window belong to the "Styl a obchod batohu" chat:
	BackpackData, BackpackBuilder, Lobby/Districts/Backpacks, BackpackShopView).
	What a pack holds is CarryService's (data.BackpackItems); its capacity is
	the worn pack's (Bonuses' "Backpack" source).

	The save: data.Backpacks = { Equipped = id, Owned = { [id] = true } } (the
	starter pack, BackpackData.StarterId, is always owned; Migrations repairs
	it). The packs stay through a rebirth (owner 2026-10-25); their ore doesn't.

	The counter: every BasePart tagged "BackpackCounter" gets a "Backpacks"
	prompt (E / gamepad Y, PromptConfig "Main") at its Attachment
	"BackpackPromptPoint" (made over the counter's customer side when the
	building has none) that opens the shop: OpenUI "Backpacks" { Counter }.

	BackpackAction (Net, rate limited), checked here in one step with no yield:
	  ("Buy", { Id })   a pack this build sells (BackpackData.ById; "BadId"),
	                    not owned yet ("Owned"), within Range of a counter
	                    ("TooFar"), for its Price in coins (EconomyService.spend,
	                    "NoCoins"); any pack you can afford, in any order. A
	                    bought pack bigger than the one worn is worn at once.
	  ("Equip", { Id }) a pack you own ("NotOwned"), anywhere.
	  ("BadId" also for any other op or a broken payload.) Every request read
	  gets a BackpackResult { Id, Ok, Reason? }.
	The worn pack shows on the character: the player attribute "Backpack" =
	Equipped (every client builds that pack, BackpackBuilder). refresh(player)
	sets it again with the backpack attributes (CarryService) after any change.
	State.Backpacks (StateService builds it from the save): { Equipped, Owned =
	{ ids }, Count, Capacity, Items }.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BackpackData = require(Shared.Config.BackpackData)
local PromptConfig = require(Shared.Config.PromptConfig)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local CarryService = require(script.Parent.CarryService)

local BackpackService = {}

BackpackService.Tag = "BackpackCounter"
BackpackService.PointName = "BackpackPromptPoint"
BackpackService.PromptName = "BackpackShopPrompt"
BackpackService.Attribute = "Backpack" -- player attribute: the worn pack's id
-- studs from the counter's surface the server accepts (the window closes past 16)
BackpackService.Range = 16
BackpackService.Reasons = { "TooFar", "NoCoins", "Owned", "NotOwned", "BadId", "Locked" }

local PROMPT_DISTANCE = 10
local MAX_PAYLOAD = 2
local MAX_ID_LENGTH = 40

local counters: { BasePart } = {}
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

---------------------------------------------------------------- the save

-- The save's packs record (repaired in place when missing or broken).
function BackpackService.packsOf(data: { [string]: any }): { Equipped: string, Owned: { [string]: boolean } }
	local packs = data.Backpacks
	if type(packs) ~= "table" then
		packs = {}
		data.Backpacks = packs
	end
	if type(packs.Owned) ~= "table" then
		packs.Owned = {}
	end
	packs.Owned[BackpackData.StarterId] = true
	if type(packs.Equipped) ~= "string" then
		packs.Equipped = BackpackData.StarterId
	end
	return packs
end

-- Does the save own this pack? (the starter always)
function BackpackService.owns(data: { [string]: any }, id: string): boolean
	if id == BackpackData.StarterId then
		return true
	end
	local packs = data.Backpacks
	return type(packs) == "table" and type(packs.Owned) == "table" and packs.Owned[id] == true
end

-- The pack worn (its id; the starter when the save says nothing usable).
function BackpackService.equippedOf(data: { [string]: any }?): string
	local packs = data and data.Backpacks
	local id = if type(packs) == "table" then packs.Equipped else nil
	return if type(id) == "string" then id else BackpackData.StarterId
end

-- The worn pack's attribute and the backpack attributes, again (after a buy, an equip, a load).
function BackpackService.refresh(player: Player)
	local data = DataService.get(player)
	player:SetAttribute(BackpackService.Attribute, if data then BackpackService.equippedOf(data) else nil)
	CarryService.refreshWalkSpeed(player)
end

---------------------------------------------------------------- the counter

-- Distance from a point to the surface of a part's box (0 inside).
local function distanceToPart(part: BasePart, position: Vector3): number
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The BackpackCounter the player stands at (within `range`), or nil.
function BackpackService.counterNear(player: Player, range: number): BasePart?
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

---------------------------------------------------------------- buying and wearing

--[[
	Why `id` can't be bought (pure: the window predicts it too), or nil.
	`owned` = the save owns it, `coins` = the balance.
]]
function BackpackService.buyRefusal(id: any, owned: boolean, coins: number): string?
	local pack = if type(id) == "string" then BackpackData.ById[id] else nil
	if not pack then
		return "BadId"
	elseif owned then
		return "Owned"
	elseif coins < pack.Price then
		return "NoCoins"
	end
	return nil
end

-- Buys a pack (no range check: the request handler does it). One step, no yield.
function BackpackService.buy(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "Locked"
	end
	local reason = BackpackService.buyRefusal(id, BackpackService.owns(data, id), EconomyService.balance(player))
	if reason then
		return false, reason
	end
	local pack = BackpackData.ById[id]
	if pack.Price > 0 and not EconomyService.spend(player, pack.Price, "Backpack") then
		return false, "NoCoins"
	end
	local packs = BackpackService.packsOf(data)
	packs.Owned[id] = true
	if pack.Capacity > BackpackData.capacity(packs.Equipped) then
		packs.Equipped = id
	end
	DataService.changed(player)
	BackpackService.refresh(player)
	return true, nil
end

-- Wears a pack you own. One step, no yield.
function BackpackService.equip(player: Player, id: string): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "Locked"
	end
	if not BackpackData.ById[id] then
		return false, "BadId"
	end
	if not BackpackService.owns(data, id) then
		return false, "NotOwned"
	end
	BackpackService.packsOf(data).Equipped = id
	DataService.changed(player)
	BackpackService.refresh(player)
	return true, nil
end

local function answer(player: Player, id: string, ok: boolean, reason: string?)
	Net.fire("BackpackResult", player, { Id = id, Ok = ok, Reason = reason })
end

local function onAction(player: Player, op: any, payload: any)
	local args = Guard.table(payload, MAX_PAYLOAD)
	local id = if args then Guard.string(args.Id, MAX_ID_LENGTH) else nil
	if not id or (op ~= "Buy" and op ~= "Equip") then
		answer(player, if id then id else "", false, "BadId")
		return
	end
	local ok, reason
	if op == "Buy" then
		if not BackpackService.counterNear(player, BackpackService.Range) then
			answer(player, id, false, "TooFar")
			return
		end
		ok, reason = BackpackService.buy(player, id)
	else
		ok, reason = BackpackService.equip(player, id)
	end
	answer(player, id, ok, reason)
end

local function openView(player: Player, counter: BasePart)
	if not DataService.get(player) or not BackpackService.counterNear(player, BackpackService.Range) then
		return
	end
	Net.fire("OpenUI", player, "Backpacks", { Counter = counter })
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
	local point = part:FindFirstChild(BackpackService.PointName)
	if not point or not point:IsA("Attachment") then
		-- the building has none: over the counter's customer side (its +Z)
		local made = Instance.new("Attachment")
		made.Name = BackpackService.PointName
		made.CFrame = CFrame.new(0, part.Size.Y / 2 + 1.2, part.Size.Z / 2)
		made.Parent = part
		point = made
	end
	local old = (point :: Instance):FindFirstChild(BackpackService.PromptName)
	if old then
		old:Destroy()
	end
	local prompt = PromptConfig.make({
		Name = BackpackService.PromptName,
		ActionText = "Backpacks",
		ObjectText = "Backpack Shop",
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
	local point = counter:FindFirstChild(BackpackService.PointName)
	local prompt = point and point:FindFirstChild(BackpackService.PromptName)
	if prompt then
		prompt:Destroy()
	end
	pruneCounters()
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/BackpackService.spec.luau).
BackpackService._test = {
	action = onAction,
	open = openView,
	hookCounter = hookCounter,
	unhookCounter = unhookCounter,
	counters = function(): { BasePart }
		return table.clone(counters)
	end,
	reset = function()
		table.clear(counters)
	end,
}

function BackpackService.init()
	Net.on("BackpackAction", onAction)
	DataService.onLoaded(function(player)
		BackpackService.refresh(player)
	end)
end

function BackpackService.start()
	for _, instance in CollectionService:GetTagged(BackpackService.Tag) do
		hookCounter(instance)
	end
	CollectionService:GetInstanceAddedSignal(BackpackService.Tag):Connect(hookCounter)
	CollectionService:GetInstanceRemovedSignal(BackpackService.Tag):Connect(unhookCounter)
end

return BackpackService
