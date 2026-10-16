--[[
	Flora hero trees (LOBBY_PLAN 6.5 items 8-10): the pink cherry grove
	behind UPGRADES, the big red tree in the south-east foreground and the
	yellow/orange autumn corner in the south-west.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

local Trees = {}

local function falling(part: BasePart, color: Color3)
	local e = Style.emitter(part, "Sparkle", color, 2)
	e.Name = "PetalParticles"
	e.Speed = NumberRange.new(0.5, 1.5)
	e.Acceleration = Vector3.new(0.6, -1.6, 0.3)
	e.Lifetime = NumberRange.new(3, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
end

local function crownPart(tree: Model): BasePart?
	-- the first ghost (non-colliding, shadow-casting) block is the crown core
	for _, child in tree:GetChildren() do
		if child:IsA("BasePart") and not child.CanCollide and child.CastShadow then
			return child
		end
	end
	return nil
end

function Trees.pinkGrove(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("PinkGrove")
	local c = piece.Center
	local m = Style.model("PinkGrove", parent)
	-- the big one leans its side crown toward the forge (like the concept)
	local big = Kit.bigTree(m, CFrame.new(c + Vector3.new(-4, 0, -2)), "Pink", rng, 1.5, -1)
	Kit.bigTree(m, CFrame.new(c + Vector3.new(5, 0, 4)), "Pink", rng, 1.3, 1)
	Style.bush(m, c + Vector3.new(2.5, 0, -5.5), C.LeafPink, rng, 2.6)
	Style.bush(m, c + Vector3.new(-6.5, 0, 4.5), C.LeafPinkDark, rng, 2.2)
	Style.bush(m, c + Vector3.new(6.8, 0, -2.5), C.FlowerPurple, rng, 2.2)
	local crown = crownPart(big)
	if crown then
		falling(crown, C.LeafPinkLight)
	end
	return m
end

function Trees.redTree(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("RedTree")
	local c = piece.Center
	local m = Style.model("RedTree", parent)
	-- side crown east, away from the Hall of Fame boards
	Kit.bigTree(m, CFrame.new(c), "Red", rng, 1.4, 1)
	Style.bush(m, c + Vector3.new(3.6, 0, 2.8), C.LeafRed, rng, 2.2)
	Style.bush(m, c + Vector3.new(-3.4, 0, 3.2), C.LeafOrange, rng, 1.9)
	Kit.flowerRing(m, c, 2.6, { C.FlowerYellow, C.FlowerRed, C.FlowerWhite }, rng, 5)
	return m
end

function Trees.autumnCorner(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("AutumnCorner")
	local c = piece.Center
	local m = Style.model("AutumnCorner", parent)
	Kit.bigTree(m, CFrame.new(c + Vector3.new(-4, 0, -3)), "Yellow", rng, 1.25)
	Style.tree(m, CFrame.new(c + Vector3.new(5, 0, -6)), "Orange", rng, 1.1)
	Style.tree(m, CFrame.new(c + Vector3.new(4, 0, 5)), "Yellow", rng, 1.05)
	Kit.leanTree(m, CFrame.new(c + Vector3.new(-6, 0, 6)), "Orange", rng, 1.0)
	Kit.leanTree(m, CFrame.new(c + Vector3.new(-1, 0, 9)), "Yellow", rng, 0.9)
	Style.bush(m, c + Vector3.new(1.5, 0, 0.5), C.LeafOrangeDark, rng, 2.2)
	Kit.pumpkin(m, c + Vector3.new(0.5, 0, -2.5), rng, 1.6)
	Kit.pumpkin(m, c + Vector3.new(-1.6, 0, 2.6), rng, 1.2)
	Kit.pumpkin(m, c + Vector3.new(8.6, 0, 0.6), rng, 1.4)
	Style.flowers(m, c + Vector3.new(-8.5, 0, -0.5), C.FlowerYellow, rng, 4, 1.2)
	return m
end

function Trees.build(parent: Instance, rng: Rng.Rng)
	Trees.pinkGrove(parent, Kit.sub(rng))
	Trees.redTree(parent, Kit.sub(rng))
	Trees.autumnCorner(parent, Kit.sub(rng))
end

return Trees
