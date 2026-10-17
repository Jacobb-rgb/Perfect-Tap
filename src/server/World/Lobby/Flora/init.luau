--[[
	Lobby package Flora (docs/plans/LOBBY_PLAN.md 6.5): water, trees and
	wayfinding of the town lobby, matching docs/art/lobby_concept.webp.

	  Water    lily pond, koi pond, creek, arched bridge over the creek
	  Signs    MINE/UPGRADE/EXPLORE/BUILD signpost, NEXT AREA + rope gate, boardwalk
	  Trees    cherry grove behind UPGRADES, red hero tree, autumn corner,
	           the town-edge tree belts along both plot roads
	  Scatter  colorful voxel trees, bushes, flowers, boulders, fences, garden lanterns
	  Town     small town buildings along the plot roads and behind the stalls
	           in Kenney City Kit + Space Station Kit shapes with concept v2 neon trims

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
local Town = require(script.Town)

local Flora = {}

Flora.Replaces = { "scatter" }

function Flora.build(parent: Model, rng: Rng.Rng)
	local water = Kit.sub(rng)
	local signs = Kit.sub(rng)
	local trees = Kit.sub(rng)
	local scatter = Kit.sub(rng)
	local town = Kit.sub(rng)
	Water.build(Style.model("Water", parent), water)
	Signs.build(Style.model("Wayfinding", parent), signs)
	-- the belts keep their crowns off the town sites
	local sites: { Kit.Box } = {}
	for _, site in Town.Sites do
		table.insert(sites, { Min = site.Min, Max = site.Max })
	end
	Trees.build(Style.model("HeroTrees", parent), trees, sites)
	Town.build(Style.model("Town", parent), town)
	-- the scatter keeps 1 stud off every building site and off the town-edge belts
	local keepOut = Town.keepOut(1)
	for _, box in Trees.beltBoxes() do
		table.insert(keepOut, box)
	end
	Scatter.build(parent, scatter, keepOut)
	Flora.clearCrowns(parent)
end

--[[
	(lobby fix round 3) A last pass over the belt and scatter trees: no crown
	within a stud of a town building, none within 2 studs of a plaza lantern
	pillar (the Plaza package is built before Flora; on its own Flora skips
	the lanterns).
]]
function Flora.clearCrowns(parent: Instance)
	local lanterns: { Vector3 } = {}
	local lobby = parent.Parent
	local plaza = lobby and lobby:FindFirstChild("Plaza")
	if plaza then
		for _, d in plaza:GetDescendants() do
			if d:IsA("Model") and d.Name == "Lantern" and d.PrimaryPart then
				local p = d.PrimaryPart.CFrame.Position
				table.insert(lanterns, Vector3.new(p.X, 0, p.Z))
			end
		end
	end
	local doomed: { Instance } = {}
	for _, d in parent:GetDescendants() do
		if d:IsA("Model") and d.Name == "Tree" and (d:FindFirstAncestor("TownBelt") or d:FindFirstAncestor("Scatter")) then
			local lo = Vector3.new(math.huge, 0, math.huge)
			local hi = Vector3.new(-math.huge, 0, -math.huge)
			for _, part in d:GetDescendants() do
				if part:IsA("BasePart") then
					local a, b = Kit.partBox(part)
					lo = Vector3.new(math.min(lo.X, a.X), 0, math.min(lo.Z, a.Z))
					hi = Vector3.new(math.max(hi.X, b.X), 0, math.max(hi.Z, b.Z))
				end
			end
			local clash = false
			for _, site in Town.Sites do
				if lo.X < site.Max.X + 1 and hi.X > site.Min.X - 1 and lo.Z < site.Max.Y + 1 and hi.Z > site.Min.Y - 1 then
					clash = true
				end
			end
			for _, p in lanterns do
				local dx = math.max(lo.X - p.X, 0, p.X - hi.X)
				local dz = math.max(lo.Z - p.Z, 0, p.Z - hi.Z)
				if dx * dx + dz * dz < 4 then
					clash = true
				end
			end
			if clash then
				table.insert(doomed, d)
			end
		end
	end
	for _, d in doomed do
		d:Destroy()
	end
end

return Flora
