--[[
	StateService: sends each player a small snapshot of their own data for
	the HUD and menus (coins, blaster, carry, machines, pen, podiums, codex,
	machine upgrades, keep settings, Foundry stock...).
	Pushes are coalesced: at most one every 0.2 s per player.
	Other services add fields with StateService.addProvider().

	Bandwidth (steps 6-7): the bigger records that rarely change (STICKY:
	Gear, Enchants, Golems, Artifacts, Bonuses) are sent only when they
	changed since the last push to that player (compared by fingerprint).
	An unchanged one is left out and its key listed in snapshot.Kept; the
	client (StateController) copies those keys from its previous snapshot,
	so every listener still sees a whole snapshot. The first push after a
	join is always whole.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local GearConfig = require(Shared.Config.GearConfig)
local ItemData = require(Shared.Config.ItemData)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local Perks = require(script.Parent.Parent.Perks)
local Shards = require(script.Parent.Parent.Shards)
local DataService = require(script.Parent.DataService)

local StateService = {}

type Provider = (player: Player, data: { [string]: any }, snapshot: { [string]: any }) -> ...any

local providers: { Provider } = {}
local pending: { [Player]: boolean } = {}
-- player -> sticky key -> fingerprint of what that player's client has
local sent: { [Player]: { [string]: string } } = {}

-- Records sent only when they change (see the header).
StateService.Sticky = { "Gear", "Enchants", "Golems", "Artifacts", "Bonuses" }

local MAX_DEPTH = 8

local function keyOrder(a: any, b: any): boolean
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta < tb
	end
	if ta == "number" or ta == "string" then
		return a < b
	end
	return tostring(a) < tostring(b)
end

-- A deterministic text for a save value (same content = same text).
function StateService.fingerprint(value: any, depth: number?): string
	local level = depth or 0
	if type(value) ~= "table" then
		return type(value):sub(1, 1) .. tostring(value)
	end
	if level >= MAX_DEPTH then
		return "{...}"
	end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, keyOrder)
	local parts = table.create(#keys)
	for i, key in keys do
		parts[i] = StateService.fingerprint(key, level + 1) .. "=" .. StateService.fingerprint(value[key], level + 1)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- Leaves out the sticky records this player's client already has (listing
-- them in snapshot.Kept) and remembers what it now has. `snapshot` is changed.
function StateService.trim(player: Player, snapshot: { [string]: any }): { [string]: any }
	local known = sent[player]
	if not known then
		known = {}
		sent[player] = known
	end
	local kept = {}
	for _, key in StateService.Sticky do
		local value = snapshot[key]
		if value ~= nil then
			local mark = StateService.fingerprint(value)
			if known[key] == mark then
				snapshot[key] = nil
				table.insert(kept, key)
			else
				known[key] = mark
			end
		end
	end
	if #kept > 0 then
		snapshot.Kept = kept
	end
	return snapshot
end

function StateService.addProvider(provider: Provider)
	table.insert(providers, provider)
end

local function storageSummary(storage: { ItemData.Desc }): { [string]: number }
	-- ItemData.storageKey ("Kind|Ore|Grade|Recipe") -> count (compact for the network)
	local summary = {}
	for _, entry in storage do
		local key = ItemData.storageKey(entry)
		summary[key] = (summary[key] or 0) + 1
	end
	return summary
end

function StateService.snapshot(player: Player): { [string]: any }?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local foundry = data.Foundry
	local foundryStock: { ItemData.Desc } = if type(foundry) == "table" and type(foundry.Stock) == "table" then foundry.Stock else {}
	local snapshot: { [string]: any } = {
		Coins = data.Coins,
		TotalEarned = data.TotalEarned,
		BlasterLevel = BlasterData.get(data.BlasterLevel).Level,
		BlasterOre = data.BlasterOre,
		Podiums = data.Podiums,
		-- deprecated mirror of the Backpack level (old CarryLevel = Backpack + 1)
		CarryLevel = GearConfig.level(data.Gear, "Backpack") + 1,
		-- the same number CarryService uses (Bonuses: Backpack, later providers, StrongBack)
		CarryCapacity = Bonuses.carryCapacity(Bonuses.stats(player), player),
		Upgrades = data.Upgrades,
		MachineInventory = data.MachineInventory,
		PlacedCount = #data.PlacedMachines,
		StorageCount = #data.Storage,
		Storage = storageSummary(data.Storage),
		-- step 3: Tech shop levels, the Iron Box / billboard keep settings, the Foundry's ingots
		MachineUpgrades = data.MachineUpgrades,
		KeepMode = data.KeepMode,
		KeepList = data.KeepList,
		FoundryStock = storageSummary(foundryStock),
		FoundryCount = #foundryStock,
		-- steps 6-7: the saved records as they are (times are os.time() seconds:
		-- compare with workspace:GetServerTimeNow()), crystal shards, and the
		-- player's bonus numbers (Bonuses.summary)
		Gear = data.Gear,
		Enchants = data.Enchants,
		Boosts = data.Boosts,
		Golems = data.Golems,
		Wheel = data.Wheel,
		Artifacts = data.Artifacts,
		Shards = Shards.get(data),
		Bonuses = Bonuses.summary(player),
		Discovered = data.Discovered,
		Stats = data.Stats,
		Tutorial = data.Tutorial,
		GroupRewardClaimed = data.GroupRewardClaimed,
		Perks = {
			StrongBack = Perks.has(player, "StrongBack"),
			ForgeVip = Perks.has(player, "ForgeVip"),
			Workshop = Perks.has(player, "Workshop"),
			Podiums = Perks.has(player, "Podiums"),
			OfflineExtension = Perks.has(player, "OfflineExtension"),
		},
	}
	for _, provider in providers do
		local ok, err = pcall(provider, player, data, snapshot)
		if not ok then
			warn("[StateService] provider failed: " .. tostring(err))
		end
	end
	return snapshot
end

function StateService.push(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(0.2, function()
		pending[player] = nil
		if player.Parent then
			local snapshot = StateService.snapshot(player)
			if snapshot then
				Net.fire("State", player, StateService.trim(player, snapshot))
			end
		end
	end)
end

function StateService.init()
	DataService.onChanged(StateService.push)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		sent[player] = nil
	end)
end

return StateService
