--[[
	Terra Forge server bootstrap.

	Every module in Services/ is a table with optional init() and start().
	init() runs first for all services in ORDER (set up state, remotes,
	MachineService behaviours), then start() runs for each in its own thread
	(loops, connections). MachineService spawns machines in start(), so every
	behaviour is registered before the first machine appears.
	A service listed here that doesn't exist yet is skipped with a warning
	(feature packages add theirs over time).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Services = script:WaitForChild("Services")

-- Remotes exist before any client script asks for them.
Net.setupServer()
game:GetService("Players").PlayerRemoving:Connect(Net.forget)

local ORDER = {
	"DataService",
	"WorldService",
	"StateService",
	"ItemService",
	"ToolService",
	"MiningService",
	"CarryService",
	"PlotService",
	"MachineService",
	"IntakeService",
	"ConveyorService", -- belts + chutes: before PenService / TrainService, which feed its chutes
	"EconomyService",
	"PenService",
	"PodiumService",
	"TrainService",
	"FoundryService",
	"CleaningService",
	"ProcessingService",
	"IronBoxService",
	"SellService",
	"LogisticsService", -- Splitter, Sorter, Robot Arm, Sell Box
	"PowerService", -- power networks: machine speeds, cable attributes
	"ShopService",
	"VaultService", -- the Blaster Vault shop (buy the next blaster level, the crate opening)
	"GearService", -- the Gear shop at the SHOP stall (boots, lamp, backpack, gloves, magnet)
	"BuildService",
	"AccessService",
	"TeleportService", -- the quick teleports (BASE / LOBBY / VAULT / elevator)
}

local loaded = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module then
		loaded[name] = require(module) :: any
	else
		warn("[TerraForge] missing service " .. name)
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.init then
		local ok, err = pcall(service.init)
		if not ok then
			warn(`[TerraForge] {name}.init failed: {err}`)
		end
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.start then
		task.spawn(function()
			local ok, err = pcall(service.start)
			if not ok then
				warn(`[TerraForge] {name}.start failed: {err}`)
			end
		end)
	end
end

print("[TerraForge] server ready")
