--[[
	Lobby package "Plaza" (docs/plans/LOBBY_PLAN.md 6.3): the round
	flagstone plaza with the spawn's compass-rose inlay, the giant fire
	crystal in its glowing stone ring (tag Spin), THE GREAT FORGE, every
	road and path as cobble or dirt, and the lanterns along them.

	Replaces the legacy "roads", "plaza" and "greatForge" pieces
	(TownLegacy.luau). Pure builder: Instance creation only, deterministic
	from `rng`. TownSpawn stays in Town.luau; the spawn area stays flat.

	Submodules: Common (strips, placement checks, path strips), Paving,
	FireCrystal, GreatForge, Roads (roads, paths, lanterns).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local FireCrystal = require(script.FireCrystal)
local GreatForge = require(script.GreatForge)
local Paving = require(script.Paving)
local Roads = require(script.Roads)

local Plaza = {}

Plaza.Replaces = { "roads", "plaza", "greatForge" }

function Plaza.build(parent: Model, rng: Rng.Rng)
	Roads.build(parent, rng)
	Paving.build(parent, rng)
	FireCrystal.build(parent, rng)
	GreatForge.build(parent, rng)
end

return Plaza
