--[[
	Emberfall: the hub town lobby (target look: docs/art/lobby_concept.webp,
	style bible: docs/ART_DIRECTION.md, layout: docs/plans/LOBBY_PLAN.md).

	The lobby is built by five modules in World/Lobby/, one per art package:
	Sky, Backdrop, Plaza, Districts, Flora. Each module exports

	    Replaces: { string }?                   legacy pieces it takes over
	    build(parent: Model, rng: Rng.Rng): ()  builds into Emberfall.Lobby.<Name>

	A module that does not exist yet is skipped, and the legacy pieces
	(TownLegacy) it would replace keep being built, so every gameplay hook
	exists at all times. Every module gets its own random stream, so one
	package's changes never reshuffle another package's decoration.

	Gameplay hooks (CollectionService tags; services add prompts/zones):
	  SellBin (+ child part "Intake"), SellCounter, ShopCounter   the SHOP
	  UpgradeCounter   UPGRADES stall          EmberChest   on the SPIN & WIN wheel
	  GuildBoard       notice board            OreCodex     ROCK SCANNER terminal
	  FossilDig        FOSSIL DIG site         Spin         decor that rotates
	  TownSpawn        the SpawnLocation (always built here)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local TownLegacy = require(script.Parent.TownLegacy)

local Town = {}

export type LobbyModule = {
	Replaces: { string }?,
	build: (parent: Model, rng: Rng.Rng) -> (),
}

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- The lobby modules that exist, in package order.
function Town.lobbyModules(): { { Name: string, Module: LobbyModule } }
	local found = {}
	local folder = script.Parent:FindFirstChild("Lobby")
	if not folder then
		return found
	end
	for _, name in LobbyLayout.Packages do
		local moduleScript = folder:FindFirstChild(name)
		if moduleScript then
			local module = require(moduleScript :: any) :: any
			assert(type(module) == "table" and type(module.build) == "function", "Lobby." .. name .. " must export build()")
			table.insert(found, { Name = name, Module = module :: LobbyModule })
		end
	end
	return found
end

function Town.build(map: Model, rng: Rng.Rng)
	local town = model("Emberfall", map)
	local modules = Town.lobbyModules()

	-- legacy pieces that no landed lobby module replaces yet
	local replaced: { [string]: boolean } = {}
	for _, entry in modules do
		for _, piece in entry.Module.Replaces or {} do
			replaced[piece] = true
		end
	end
	for _, name in TownLegacy.Order do
		if not replaced[name] then
			TownLegacy.Pieces[name](town, rng)
		end
	end

	local lobby = model("Lobby", town)
	for _, entry in modules do
		local parent = model(entry.Name, lobby)
		entry.Module.build(parent, Rng.new(`Lobby/{entry.Name}/{WorldLayout.Seed}`))
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(WorldLayout.SpawnPoint + Vector3.new(0, 0.25, 0))
	spawn.Color = Color3.fromRGB(204, 180, 146)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Transparency = 0
	spawn.Parent = town
	-- no default decal: keep the stylized look
	return town
end

return Town
