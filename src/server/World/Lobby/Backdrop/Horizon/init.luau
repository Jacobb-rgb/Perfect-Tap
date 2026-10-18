--[[
	Horizon (owner 2026-10-17): everything around the map so no side looks
	out on empty sea or the void.

	  Ring      the outer sea out to ~3000 studs and low cloud banks on the horizon
	  Isles     far islands all around: Kenney Hexagon Kit tiles and buildings,
	            Survival / Fantasy Town props, two lighthouses, Candy stacks
	  Fleet     Kenney Watercraft Kit ships: the ocean liner, a pirate galleon,
	            a container ship, a tug, a houseboat, sailing boats; bobbing
	  Heavens   five more Kenney Planets worlds, four constellations, clouds

	The Kenney models are the CC0 kits the owner sent, turned into boxes by
	tools/kenney/voxelize.mjs (Kenney/*) and rebuilt from parts (Blocks).

	Everything is unreachable decoration far outside the lobby (no
	collision, no raycasts, no shadows, no lights). StreamingTargetRadius is
	384 studs, so the whole model is Persistent: otherwise nothing out there
	would ever stream in (see Sky/Planets).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Ring = require(script.Ring)
local Isles = require(script.Isles)
local Fleet = require(script.Fleet)
local Heavens = require(script.Heavens)

local Horizon = {}

type Step = { Name: string, Build: (Instance, Rng.Rng) -> Model }
local STEPS: { Step } = {
	{ Name = "Ring", Build = Ring.build },
	{ Name = "Isles", Build = Isles.build },
	{ Name = "Fleet", Build = Fleet.build },
	{ Name = "Heavens", Build = Heavens.build },
}

function Horizon.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Horizon", parent)
	local seed = rng:nextU32()
	for _, step in STEPS do
		step.Build(m, Rng.new(`Horizon/{step.Name}/{seed}`))
	end
	-- nobody can reach any of it (shared helpers like Style.tree build
	-- collidable parts): no collision, raycasts, touches or shadows
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("Model") and d:HasTag("Spin") then
			-- a turning model needs all of its parts at once
			Style.streaming(d, "Persistent")
		end
	end
	Style.streaming(m, "Persistent")
	return m
end

return Horizon
