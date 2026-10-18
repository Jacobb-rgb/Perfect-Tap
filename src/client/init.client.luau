--[[
	Terra Forge client bootstrap. Controllers are modules with optional
	init() and start(); same lifecycle as the server services.
	The client only does visuals and input; the server decides everything else.
	A controller listed here that doesn't exist yet is skipped with a warning.
]]

local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"StateController",
	"LightingController",
	"DecorController",
	"HudController",
	"FxController",
	"MiningController",
	"InteractController",
	"AccessController",
	"PromptController",
	"CleaningController",
	"MachineFxController",
	"PowerController", -- cables between poles and the machines they power
	"PenController",
	"IronBoxController",
	"PodiumController",
	"SellController",
	"TrainController",
	"FoundryController",
	"TechShopController",
	"VaultController", -- the Blaster Vault shop and its crate opening
	"GearShopController", -- the Gear shop at the SHOP stall
	"GearFxController", -- head lamps on characters, the Ore Magnet's pull lines
	"PlacementController",
	"TeleportController", -- the quick-teleport bar at the top centre (after HudController)
}

local loaded = {}
for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	if module then
		loaded[name] = require(module) :: any
	else
		warn("[TerraForge] missing controller " .. name)
	end
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller and controller.init then
		local ok, err = pcall(controller.init)
		if not ok then
			warn(`[TerraForge] {name}.init failed: {err}`)
		end
	end
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller and controller.start then
		task.spawn(function()
			local ok, err = pcall(controller.start)
			if not ok then
				warn(`[TerraForge] {name}.start failed: {err}`)
			end
		end)
	end
end
