--[[
	Lobby package Backdrop (docs/plans/LOBBY_PLAN.md 6.2): everything behind
	and around the town that makes the concept's skyline.

	  ForgeMountain        dark stepped voxel massif on the cave roof (Massif)
	  DepthsPortal/Rails   the portal framing the Ember Caves entrance (Depths)
	  QuarryFalls W/E      waterfalls into pools at the quarry wall (Falls)
	  ForgeWorks, Crane, Beacon   THE FORGE works, the crane, the peak tower (Works)
	  ScaffoldWest/2       timber derricks on the west shelf (Scaffolds)
	  NWCliff/Pool, MineEntrance/Yard   the pieces inside the town (Lowlands)

	Each piece is a Model named by its LobbyLayout Id under
	Emberfall.Lobby.Backdrop and gets its own random stream, so changing one
	piece never reshuffles another. Land.luau (restyled by this package)
	leaves the ForgeMountain box empty and cuts the west shelf for the
	scaffolds. Replaces nothing in TownLegacy.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Massif = require(script.Massif)
local Depths = require(script.Depths)
local Falls = require(script.Falls)
local Works = require(script.Works)
local Scaffolds = require(script.Scaffolds)
local Lowlands = require(script.Lowlands)

local Backdrop = {}

Backdrop.Replaces = {} :: { string }

-- Build steps in a fixed order; each gets a random stream from its name.
type Step = { Name: string, Build: (Instance, Rng.Rng) -> () }
local STEPS: { Step } = {
	{
		Name = "ForgeMountain",
		Build = function(parent: Instance, rng: Rng.Rng)
			Massif.build(parent, rng)
		end,
	},
	{
		Name = "DepthsPortal",
		Build = function(parent: Instance, rng: Rng.Rng)
			Depths.buildPortal(parent, rng)
		end,
	},
	{
		Name = "DepthsRails",
		Build = function(parent: Instance, rng: Rng.Rng)
			Depths.buildRails(parent, rng)
		end,
	},
	{ Name = "QuarryFalls", Build = Falls.build },
	{
		Name = "ForgeWorks",
		Build = function(parent: Instance, rng: Rng.Rng)
			Works.buildForgeWorks(parent, rng)
		end,
	},
	{
		Name = "Crane",
		Build = function(parent: Instance, rng: Rng.Rng)
			Works.buildCrane(parent, rng)
		end,
	},
	{
		Name = "Beacon",
		Build = function(parent: Instance, rng: Rng.Rng)
			Works.buildBeacon(parent, rng)
		end,
	},
	{ Name = "Scaffolds", Build = Scaffolds.build },
	{ Name = "Lowlands", Build = Lowlands.build },
}

function Backdrop.build(parent: Model, rng: Rng.Rng)
	local seed = rng:nextU32()
	for _, step in STEPS do
		step.Build(parent, Rng.new(`Backdrop/{step.Name}/{seed}`))
	end
end

return Backdrop
