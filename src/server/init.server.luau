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
	"MovementService", -- the movement check: samples characters, trustedPosition for range checks (logging only)
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
	"ElevatorService", -- the mine elevator (after EconomyService, StateService and WorldService)
	"VaultService", -- the Blaster Vault shop (buy the next blaster level, the crate opening)
	"MonetizationService", -- the one ProcessReceipt callback (grant handlers register in init)
	"HoverboardService", -- hoverboards: buy, equip, ride (after Carry, Cleaning, Elevator, Monetization)
	"GearService", -- the Gear shop at the SHOP stall (boots, lamp, backpack, gloves, magnet)
	"BoostService", -- luck boosts (Triple / Hexa Lucky), purchase prompts, boost expiry pushes
	"EnchantService", -- the Enchant shop at the rune table (EnchantCounter)
	"GolemService", -- golem pets: GolemAction, the followers attribute (step 7)
	"CapsuleService", -- golem capsules: CapsuleAction, the CapsuleStall prompt (step 7)
	"BuildService",
	"AccessService",
	"TeleportService", -- the quick teleports (BASE / LOBBY / VAULT / elevator)
	"BadgeService", -- badges from save data (BadgeConfig)
	"AnalyticsService", -- onboarding funnel, progression and coin flow (Roblox AnalyticsService)
	"WheelService", -- step 7: the free daily wheel (EmberChest prompt, WheelAction)
	"ArtifactService", -- step 7: artifact finds, the book / journal prompts, the base museums
	"LevelService", -- the player LEVEL: XP from the counters, level-up coins + income bonus (before LeaderboardService)
	"LeaderboardService", -- the 4 lobby leaderboards + hours played (after PodiumService)
	"ChampionService", -- the #1 avatars hopping on the HALL OF FAME (after LeaderboardService)
	"SettingsService", -- the side menu's SETTINGS record
	"CodexService", -- the ORE CODEX's NEW badges (seen ores)
	"RebirthService", -- rebirth STAR FORGE: the reset, Forge Stars, the Star Shop (after Plot, Train, Podium)
	"ServerBoostService", -- Server Luck: x2 ore luck for the whole server (the "ServerBoost" receipts)
	"StoreService", -- the Robux STORE window: StoreAction -> purchase prompts (grants: MonetizationService)
	"StarterPackService", -- the one-time Starter Pack: its receipt handler and the State offer
	"TutorialService", -- the first-time tutorial: steps from the save data, Skip / Got it
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
