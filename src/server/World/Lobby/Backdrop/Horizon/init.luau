--[[
	Horizon (owner 2026-10-17): everything around the map so no side looks
	out on empty sea or the void.

	  Ring      the outer sea out to ~3000 studs and low cloud banks on the horizon
	  Isles     far islands all around (Kenney Pirate Kit shapes + Candy sea stacks)
	  Pirates   big pirate ships and a merchant galleon, bobbing
	  SkyLife   two more balloons, three floating islets, circling bird flocks

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
local Pirates = require(script.Pirates)
local SkyLife = require(script.SkyLife)

local Horizon = {}

type Step = { Name: string, Build: (Instance, Rng.Rng) -> Model }
local STEPS: { Step } = {
	{ Name = "Ring", Build = Ring.build },
	{ Name = "Isles", Build = Isles.build },
	{ Name = "Pirates", Build = Pirates.build },
	{ Name = "SkyLife", Build = SkyLife.build },
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
