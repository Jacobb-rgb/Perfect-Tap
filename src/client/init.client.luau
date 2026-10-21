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
	"CleaningLookController", -- the store-card spray look (Cleaning/CardLook) on the cleaning minigame
	"MachineFxController",
	"PowerController", -- cables between poles and the machines they power
	"PenController",
	"IronBoxController",
	"PodiumController",
	"SellController",
	"TrainController",
	"FoundryController",
	"TechShopController",
	"ElevatorController",
	"VaultController", -- the Blaster Vault shop and its crate opening
	"HoverboardController", -- the hoverboards panel (the side menu's HOVER), RIDE, every rider's board
	"GearShopController", -- the Gear shop at the SHOP stall
	"GearFxController", -- head lamps on characters, the Ore Magnet's pull lines
	"BoostController", -- luck boosts view + the boost chips under the HUD coins
	"EnchantController", -- the Enchant shop at the rune table
	"GolemController", -- golem inventory + followers (step 7; the side menu's GOLEMS opens it)
	"WorldMotionController", -- world animations: golem hops / equip jump, ore pops, hit flash, sell cash burst
	"CapsuleController", -- capsule shop, the opening, the stall's odds board (step 7)
	"PlacementController",
	"TeleportController", -- the quick-teleport bar at the top centre (after HudController)
	"MusicController", -- background music per zone (MusicConfig; volume = the TerraForgeMusic SoundGroup)
	"AmbienceController", -- quiet lobby sounds at the waterfalls, ponds, forge (AmbienceConfig; volume = the TerraForgeAmbience SoundGroup)
	"WheelController", -- step 7: the daily wheel screen and the FREE SPIN! chip
	"ArtifactController", -- step 7: the found moment, the collection book, the journal
	"LeaderboardController", -- the lobby boards + the HALL OF FAME panel
	"CodexController", -- the ORE CODEX (ROCK SCANNER prompt, side menu)
	"SettingsController", -- the SETTINGS panel; applies volumes / shake / rumble
	"RebirthController", -- rebirth STAR FORGE: the window, the moment, the stars over names
	"StoreController", -- the Robux STORE window (side menu STORE, the HUD's Shop button)
	"SideMenuController", -- the button column on the left (after the panels it opens)
	"TutorialController", -- the tutorial bubble and the guide beam to the step's target
	"LightWorldController", -- the light UI's world labels and prompts (only with UIConfig.LightUI on)
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
