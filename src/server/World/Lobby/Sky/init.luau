--[[
	Lobby package "Sky" (docs/plans/LOBBY_PLAN.md 6.1): everything above and
	around the town that sets the golden-hour mood of the concept
	(docs/art/lobby_concept.webp):

	  CloudBanks          pink/orange/purple voxel cloud clusters (Clouds)
	  SunGlitter          neon sun path on the west sea (Sea)
	  NearSea             a small far sail on the south horizon (Sea)
	  ShipA, ShipB        sailing ships with lit sterns, lying still (Sea)
	  CastleIsland        castle + lighthouse islet on the horizon (Sea)
	  WestPier            stairs down the west cliff, dock, boats (Sea)
	  FloatingIslandWest  cottage island with a waterfall (Islands)
	  FloatingIslandEast  watchtower island with a long waterfall (Islands)
	  NextIsland          tower house past NEXT AREA (Islands)
	  Balloon             striped hot air balloon, slowly turning (Balloon)

	Plus two sky pieces that are not LobbyLayout pieces (they hang far
	outside every footprint; positions live in their modules):

	  Planets             three big Kenney-Planets-style planets in the north sky (Planets)
	  Airship             the concept v2 airship over the east island, bobbing (Airship)

	Positions come from LobbyLayout (one Model per piece, named after its
	Id). Lighting/sky settings live in LightingConfig, default.project.json
	and LightingController. Pure builder: Instance creation only, the same
	result for the same rng (each piece gets its own stream, so changing one
	piece never reshuffles the others).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Airship = require(script.Airship)
local Balloon = require(script.Balloon)
local Clouds = require(script.Clouds)
local Islands = require(script.Islands)
local Planets = require(script.Planets)
local Sea = require(script.Sea)

type Builder = (parent: Instance, piece: LobbyLayout.Piece, rng: Rng.Rng) -> Model

local BUILDERS: { [string]: Builder } = {
	CloudBanks = Clouds.build,
	SunGlitter = Sea.sunGlitter,
	NearSea = Sea.nearSea,
	ShipA = Sea.shipA,
	ShipB = Sea.shipB,
	CastleIsland = Sea.castleIsland,
	WestPier = Sea.westPier,
	FloatingIslandWest = Islands.west,
	FloatingIslandEast = Islands.east,
	NextIsland = Islands.nextIsland,
	Balloon = Balloon.build,
}

local Sky = {}

Sky.Replaces = {} :: { string }

function Sky.build(parent: Model, rng: Rng.Rng)
	for _, piece in LobbyLayout.ofPackage("Sky") do
		local builder = BUILDERS[piece.Id]
		assert(builder, "no Sky builder for lobby piece " .. piece.Id)
		-- one draw per piece in layout order: every piece has its own stream
		local seed = rng:int(1, 2147483646)
		local model = builder(parent, piece, Rng.new(`Sky/{piece.Id}/{seed}`))
		model.Name = piece.Id
	end
	-- the extra sky pieces draw after the layout pieces, so they never
	-- reshuffle the streams of the pieces above
	Planets.build(parent, Rng.new(`Sky/Planets/{rng:int(1, 2147483646)}`))
	Airship.build(parent, Rng.new(`Sky/Airship/{rng:int(1, 2147483646)}`))
end

return Sky
