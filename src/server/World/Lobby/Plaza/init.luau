--[[
	Lobby package "Plaza" (docs/plans/LOBBY_PLAN.md 6.3, restyled after
	concept v2, docs/art/lobby_concept_v2.webp): the round plaza of dark
	polished slate with bold concentric orange and blue neon rings (the
	spawn pad dressed in slate, a glowing double chevron pointing to the
	forge), the giant fire crystal crown (tag Spin) in a low stepped
	mechanical ring round a molten bowl, THE GREAT FORGE (dark slate roofs
	with brick-red trim, warm timber, long crimson banners on dark piers, a
	glowing framed crossed-hammers crest in the gable; since 2026-10-20 an
	open passage under the roof with the bridge garden, Plaza/BridgeGarden,
	running through to the quarry and the DEPTHS), dark neon walkways with
	orange edge strips and double chevrons near the plaza, cobble and dirt
	roads further out, and dark
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
local BridgeGarden = require(script.BridgeGarden)
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
	if GreatForge.Passage then
		-- (owner 2026-10-20) under THE GREAT FORGE's roof: the bridge garden to the DEPTHS
		BridgeGarden.build(parent, Rng.new("Plaza/BridgeGarden"), "A", "Passage")
	end
end

return Plaza
