--[[
	Lobby package "Plaza" (docs/plans/LOBBY_PLAN.md 6.3, restyled after
	concept v2, docs/art/lobby_concept_v2.webp): the round plaza of dark
	polished slate with concentric blue and orange neon rings (the spawn pad
	dressed in slate with an orange ring), the giant fire crystal (tag Spin)
	in a chunky two-tier mechanical ring, THE GREAT FORGE (dark slate roofs
	with brick-red trim, warm timber, crimson banners, a glowing
	crossed-hammers crest in the gable, a monumental flight of stairs up to a
	glowing workshop), dark neon walkways with orange edge strips and
	chevrons near the plaza, cobble and dirt roads further out, and dark
	metal lantern pillars with glowing orange slots and amber lamps (wooden
	post lanterns on the far roads).

	Replaces the legacy "roads", "plaza" and "greatForge" pieces
	(TownLegacy.luau). Pure builder: Instance creation only, deterministic
	from `rng`. TownSpawn stays in Town.luau; the spawn area stays flat.

	Submodules: Common (palette, strips, placement checks, path strips,
	walkways, neon rings, chevrons, lantern pillars), Paving, FireCrystal,
	GreatForge, Roads (roads, paths, lanterns).
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
