--[[
	StateService: sends each player a small snapshot of their own data for
	the HUD and menus (coins, blaster, carry, machines, pen, podiums, codex,
	machine upgrades, keep settings, Foundry stock...).
	Pushes are coalesced: at most one every 0.2 s per player.
	Other services add fields with StateService.addProvider().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local ItemData = require(Shared.Config.ItemData)
local ToolData = require(Shared.Config.ToolData)
local Net = require(Shared.Net)
local Perks = require(script.Parent.Parent.Perks)
local DataService = require(script.Parent.DataService)

local StateService = {}

type Provider = (player: Player, data: { [string]: any }, snapshot: { [string]: any }) -> ...any

local providers: { Provider } = {}
local pending: { [Player]: boolean } = {}

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
		CarryLevel = data.CarryLevel,
		CarryCapacity = ToolData.carryCapacity(data.CarryLevel, Perks.has(player, "StrongBack")),
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
				Net.fire("State", player, snapshot)
			end
		end
	end)
end

function StateService.init()
	DataService.onChanged(StateService.push)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return StateService
