--[[
	Lobby package Flora (docs/plans/LOBBY_PLAN.md 6.5): water, trees and
	wayfinding of the town lobby, matching docs/art/lobby_concept.webp.

	  Water    lily pond, koi pond, creek, arched bridge over the creek
	  Signs    MINE/UPGRADE/EXPLORE/BUILD signpost, NEXT AREA + rope gate, boardwalk
	  Trees    pink grove behind UPGRADES, red hero tree, autumn corner
	  Scatter  colorful voxel trees, bushes, flowers, boulders, fences, garden lanterns

	Replaces the legacy `scatter` (TownLegacy). Pure builder: Instance
	creation only, deterministic from `rng`; every section draws from its
	own sub-stream so changing one never reshuffles the others.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Style)
local Kit = require(script.Kit)
local Water = require(script.Water)
local Signs = require(script.Signs)
local Trees = require(script.Trees)
local Scatter = require(script.Scatter)

local Flora = {}

Flora.Replaces = { "scatter" }

function Flora.build(parent: Model, rng: Rng.Rng)
	local water = Kit.sub(rng)
	local signs = Kit.sub(rng)
	local trees = Kit.sub(rng)
	local scatter = Kit.sub(rng)
	Water.build(Style.model("Water", parent), water)
	Signs.build(Style.model("Wayfinding", parent), signs)
	Trees.build(Style.model("HeroTrees", parent), trees)
	Scatter.build(parent, scatter)
end

return Flora
