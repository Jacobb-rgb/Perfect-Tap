--[[
	StateService: sends each player a small snapshot of their own data for
	the HUD and menus (coins, blaster, carry, machines, pen, podiums, codex,
	machine upgrades, keep settings, Foundry stock...).
	Other services add fields with StateService.addProvider().

	Network diet (perf pass 1, SERVER_PERF_AUDIT #1):
	- Pushes are coalesced per player: at most one every PushSeconds (0.5 s).
	  The first push after a join goes out at once (next resumption).
	- Only the top-level sections whose content changed since the last push
	  to that player go out (compared by fingerprint). A section the client
	  already has is left out: the client (StateController) keeps its copy,
	  so a missing section means "unchanged". So Placed (every machine and
	  belt) goes out only after a layout edit, Discovered only after a find.
	  A section that disappeared is listed in snapshot.Removed; the first
	  push after a join is whole and says snapshot.Full = true.
	- A changed flat section (string keys, plain values: the Storage and
	  Foundry summaries, Stats, Train, Build...) whose keys mostly stayed the
	  same goes as a patch instead: snapshot.Patch[section] = { Set = {key =
	  value}, Clear = {keys} }. One ore into the pen sends one count, not the
	  whole pen.
	- Steps 6-7 contract, kept: the big records that rarely change (STICKY:
	  Gear, Enchants, Golems, Artifacts, Bonuses, and the ore lists
	  Discovered and CodexSeen, CodexService's provider) are still listed in
	  snapshot.Kept when they are left out.
	- The coin balance and the podium income also live on the player as the
	  attributes Coins and IncomePerSec (at most every AttributeSeconds,
	  0.25 s): podium payouts and sales move the HUD counter without a
	  snapshot. The snapshot keeps its Coins / Income fields for the menus.
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
local EconomyService = require(script.Parent.EconomyService)

local StateService = {}

type Provider = (player: Player, data: { [string]: any }, snapshot: { [string]: any }) -> ...any

-- Seconds between two pushes to one player (changes in between go out together).
StateService.PushSeconds = 0.5
-- Seconds between two writes of the Coins / IncomePerSec player attributes.
StateService.AttributeSeconds = 0.25
StateService.CoinsAttribute = "Coins"
StateService.IncomeAttribute = "IncomePerSec"

-- Records listed in snapshot.Kept when they are left out (see the header).
StateService.Sticky = { "Gear", "Enchants", "Golems", "Artifacts", "Bonuses", "Discovered", "CodexSeen" }
-- Keys of the snapshot itself (never a section).
StateService.Reserved = { Full = true, Kept = true, Removed = true, Patch = true }

local providers: { Provider } = {}
local pending: { [Player]: boolean } = {}
-- player -> section -> fingerprint of what that player's client has
local sent: { [Player]: { [string]: string } } = {}
-- player -> flat section -> a copy of what that player's client has (for patches)
local copies: { [Player]: { [string]: { [string]: any }? } } = {}
local coinsPending: { [Player]: boolean } = {}

local isSticky: { [string]: boolean } = {}
for _, key in StateService.Sticky do
	isSticky[key] = true
end

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

-- Appends the text of `value` to `out` (one flat buffer, one concat at the end).
local function write(out: { string }, value: any, depth: number)
	local kind = type(value)
	if kind == "string" then
		-- length-prefixed: no text inside a string can pass for a separator
		table.insert(out, "s" .. #value .. ":")
		table.insert(out, value)
		return
	elseif kind ~= "table" then
		table.insert(out, string.sub(kind, 1, 1) .. tostring(value))
		return
	end
	if depth >= MAX_DEPTH then
		table.insert(out, "{...}")
		return
	end
	table.insert(out, "{")
	-- a plain list (keys 1..n, no holes): in order, no sort
	local n = #value
	local count = 0
	for _ in value do
		count += 1
	end
	local list = count == n
	if list then
		for i = 1, n do
			if value[i] == nil then
				list = false
				break
			end
		end
	end
	if list then
		for i = 1, n do
			write(out, value[i], depth + 1)
			table.insert(out, ",")
		end
	else
		local keys = table.create(count)
		local strings = true
		for key in value do
			table.insert(keys, key)
			if type(key) ~= "string" then
				strings = false
			end
		end
		if strings then
			table.sort(keys) -- the fast built-in order (the usual case)
		else
			table.sort(keys, keyOrder)
		end
		for _, key in keys do
			write(out, key, depth + 1)
			table.insert(out, "=")
			write(out, value[key], depth + 1)
			table.insert(out, ",")
		end
	end
	table.insert(out, "}")
end

-- A deterministic text for a save value (same content = same text, whatever
-- the key order; a different type or order of a list = a different text).
function StateService.fingerprint(value: any, depth: number?): string
	local out: { string } = {}
	write(out, value, depth or 0)
	return table.concat(out)
end

-- A copy of a flat section (string keys, no table values), else nil.
local function flatCopy(value: any): { [string]: any }?
	if type(value) ~= "table" then
		return nil
	end
	local copy = {}
	for key, item in value do
		if type(key) ~= "string" or type(item) == "table" then
			return nil
		end
		copy[key] = item
	end
	return copy
end

type Patch = { Set: { [string]: any }?, Clear: { string }? }

-- The patch from `old` to `new` (both flat), or nil when sending the whole
-- section is about as small (more than half of its keys changed).
local function diff(old: { [string]: any }, new: { [string]: any }): Patch?
	local set: { [string]: any } = {}
	local clear: { string } = {}
	local count, changes = 0, 0
	for key, item in new do
		count += 1
		if old[key] ~= item then
			set[key] = item
			changes += 1
		end
	end
	for key in old do
		if new[key] == nil then
			table.insert(clear, key)
			changes += 1
		end
	end
	if changes == 0 or changes * 2 > math.max(count, 1) then
		return nil
	end
	table.sort(clear)
	return { Set = if next(set) then set else nil, Clear = if #clear > 0 then clear else nil }
end

--[[
	Leaves out every section this player's client already has and remembers
	what it now has. `snapshot` is changed and returned:
	- unchanged sections: left out (sticky ones listed in Kept);
	- changed flat sections with few changed keys: in Patch;
	- sections the client has that are gone: listed in Removed;
	- the first push to a player: whole, with Full = true.
]]
function StateService.trim(player: Player, snapshot: { [string]: any }): { [string]: any }
	local known = sent[player]
	local full = known == nil
	if not known then
		known = {}
		sent[player] = known
	end
	local flat: { [string]: { [string]: any }? } = if full then {} else copies[player] or {}
	copies[player] = flat
	local present: { string } = {}
	for key in snapshot do
		if type(key) == "string" and not StateService.Reserved[key] then
			table.insert(present, key)
		end
	end
	local removed: { string } = {}
	for key in known do
		if snapshot[key] == nil then
			table.insert(removed, key)
		end
	end
	for _, key in removed do
		known[key] = nil
		flat[key] = nil
	end
	local kept: { string } = {}
	local patch: { [string]: Patch } = {}
	local patched = false
	for _, key in present do
		local value = snapshot[key]
		local mark = StateService.fingerprint(value)
		if known[key] == mark then
			snapshot[key] = nil
			if isSticky[key] then
				table.insert(kept, key)
			end
		else
			known[key] = mark
			local copy = flatCopy(value)
			local old = flat[key]
			local change = if copy and old then diff(old, copy) else nil
			if change then
				patch[key] = change
				snapshot[key] = nil
				patched = true
			end
			flat[key] = copy
		end
	end
	if full then
		snapshot.Full = true
	end
	if patched then
		snapshot.Patch = patch
	end
	if #kept > 0 then
		table.sort(kept)
		snapshot.Kept = kept
	end
	if #removed > 0 then
		table.sort(removed)
		snapshot.Removed = removed
	end
	return snapshot
end

-- Has this player's client had its first (whole) snapshot?
function StateService.hasSent(player: Player): boolean
	return sent[player] ~= nil
end

-- Forgets what a player's client has (it left): the next push is whole.
function StateService.forget(player: Player)
	pending[player] = nil
	sent[player] = nil
	copies[player] = nil
	coinsPending[player] = nil
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

---------------------------------------------------------------- coin attributes

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function setAttribute(player: Player, name: string, value: number)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

-- Writes the Coins attribute now (only when it changed).
function StateService.writeCoins(player: Player)
	local data = DataService.get(player)
	if data and finite(data.Coins) then
		setAttribute(player, StateService.CoinsAttribute, data.Coins)
	end
end

-- The Coins attribute follows the balance, at most every AttributeSeconds.
function StateService.touchCoins(player: Player)
	if coinsPending[player] then
		return
	end
	coinsPending[player] = true
	task.delay(StateService.AttributeSeconds, function()
		coinsPending[player] = nil
		if player.Parent then
			StateService.writeCoins(player)
		end
	end)
end

---------------------------------------------------------------- pushes

-- Builds, trims and sends one snapshot now; the coin attributes follow it.
function StateService.send(player: Player)
	local snapshot = StateService.snapshot(player)
	if not snapshot then
		return
	end
	local income = snapshot.Income
	if finite(income) then
		setAttribute(player, StateService.IncomeAttribute, income)
	end
	StateService.writeCoins(player)
	Net.fire("State", player, StateService.trim(player, snapshot))
end

-- Asks for a push: at most one per PushSeconds per player (the first one at once).
function StateService.push(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	local function flush()
		pending[player] = nil
		if player.Parent then
			StateService.send(player)
		end
	end
	if sent[player] then
		task.delay(StateService.PushSeconds, flush)
	else
		task.defer(flush)
	end
end

-- Internals for the Lune tests only (tests/StateService.spec.luau).
StateService._test = {
	reset = function()
		table.clear(pending)
		table.clear(sent)
		table.clear(copies)
		table.clear(coinsPending)
	end,
	-- removes the providers added after `count` (a spec's own)
	trimProviders = function(count: number)
		while #providers > count do
			table.remove(providers)
		end
	end,
	providerCount = function(): number
		return #providers
	end,
}

function StateService.init()
	DataService.onChanged(function(player: Player)
		StateService.push(player)
		StateService.touchCoins(player)
	end)
	-- podium income pays quietly (no data change event): the coin attribute still follows
	EconomyService.onEarned(function(player: Player)
		StateService.touchCoins(player)
	end)
	Players.PlayerRemoving:Connect(StateService.forget)
end

return StateService
