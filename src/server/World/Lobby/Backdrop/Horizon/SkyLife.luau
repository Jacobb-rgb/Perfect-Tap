--[[
	More life in the sky (owner 2026-10-17): two more hot air balloons that
	turn and bob, three small floating islets with a tree and a waterfall
	pouring into the air, and three flocks of sea birds circling (each flock
	turns around its hub: tag Spin, client DecorController).

	All of it hangs over the sea or high over the town, clear of the Sky
	package's pieces (the islands, the balloon, the airship, the planets'
	windows). Unreachable decoration, no lights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)
local Place = require(script.Parent.Place)

local C = Style.C
local K = Place.K

local SkyLife = {}

type Balloon = { Az: number, Dist: number, Y: number, A: Color3, B: Color3 }
type Islet = { Az: number, Dist: number, Y: number, Width: number, Tree: string }
type Flock = { Az: number, Dist: number, Y: number, Radius: number, Birds: number, Speed: number }

SkyLife.Balloons = {
	{ Az = 140, Dist = 300, Y = 112, A = C.AwningPink, B = C.AwningWhite },
	{ Az = 228, Dist = 330, Y = 96, A = C.CrystalCyan, B = C.LeafYellow },
} :: { Balloon }

SkyLife.Islets = {
	{ Az = 122, Dist = 430, Y = 118, Width = 22, Tree = "Pink" },
	{ Az = 198, Dist = 470, Y = 140, Width = 18, Tree = "Orange" },
	{ Az = 62, Dist = 520, Y = 160, Width = 20, Tree = "Green" },
} :: { Islet }

SkyLife.Flocks = {
	{ Az = 180, Dist = 300, Y = 58, Radius = 42, Birds = 7, Speed = 0.12 },
	{ Az = 90, Dist = 290, Y = 74, Radius = 36, Birds = 6, Speed = -0.1 },
	{ Az = 330, Dist = 200, Y = 132, Radius = 30, Birds = 5, Speed = 0.09 },
} :: { Flock }

-- A striped balloon: envelope layers of two colours (one block turned 45
-- degrees), skirt, ropes, a wicker basket and a glowing burner. ~22 parts.
local function balloon(parent: Instance, name: string, at: Vector3, spec: Balloon, rng: Rng.Rng)
	local m = Style.model(name, parent)
	local frame = CFrame.new(at) * CFrame.Angles(0, rng:range(0, math.pi * 2), 0)
	local basket = Kit.box(m, frame, Vector3.new(0, 1.4, 0), Vector3.new(4, 2.8, 4), Style.vary(C.Wood, rng, 0.03))
	basket.Name = "Basket"
	Kit.box(m, frame, Vector3.new(0, 2.95, 0), Vector3.new(4.4, 0.4, 4.4), C.WoodDark)
	Kit.box(m, frame, Vector3.new(0, 6.4, 0), Vector3.new(1.8, 0.4, 1.8), C.Iron)
	Kit.glow(m, frame * CFrame.new(0, 7.2, 0), Vector3.new(1, 1.2, 1), C.Fire).Name = "Burner"
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local a = (frame * CFrame.new(c[1] * 1.9, 3.1, c[2] * 1.9)).Position
		local b = (frame * CFrame.new(c[1] * 2.6, 9, c[2] * 2.6)).Position
		Kit.beam(m, a, b, 0.18, C.WoodLight)
	end
	Kit.box(m, frame, Vector3.new(0, 9.4, 0), Vector3.new(5.6, 1.6, 5.6), spec.B)
	local y = 10.2
	local turned = CFrame.Angles(0, math.pi / 4, 0)
	for _, layer in { { 9, 2.6 }, { 12.6, 2.8 }, { 13.6, 3 }, { 13.6, 3 }, { 12.2, 2.8 }, { 8.6, 2.4 } } do
		local w, h = layer[1], layer[2]
		local cf = frame * CFrame.new(0, y + h / 2, 0)
		Style.block(m, cf, Vector3.new(w, h, w), spec.A, nil, Kit.far())
		Style.block(m, cf * turned, Vector3.new(w * 0.92, h, w * 0.92), spec.B, nil, Kit.far())
		y += h
	end
	Kit.box(m, frame, Vector3.new(0, y + 0.3, 0), Vector3.new(4.8, 0.6, 4.8), spec.A)
	m.PrimaryPart = basket
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", 0.05)
	m:SetAttribute("BobHeight", 2.4)
	m:SetAttribute("BobSpeed", 0.45)
end

-- A small floating islet with a tree and a waterfall off its town-facing edge.
local function islet(parent: Instance, name: string, at: Vector3, spec: Islet, rng: Rng.Rng)
	local m = Style.model(name, parent)
	local toTown = Vector3.new(-at.X, 0, -at.Z).Unit
	local frame = CFrame.lookAt(at, at + toTown)
	local w = spec.Width
	Kit.floatingIsland(m, frame, rng, { Width = w, Depth = w * 0.8, Hang = w * 1.3, Tiers = 4 })
	Style.tree(m, frame * CFrame.new(rng:range(-w * 0.15, w * 0.15), 0, w * 0.1), spec.Tree, rng, 1.1)
	local lip = frame * CFrame.new(w * 0.18, -0.6, -w * 0.4 - 0.4)
	Kit.skyFall(m, lip, w * 1.8, w * 0.22, rng)
end

-- A flock: birds (body + two raised wings) around an invisible hub, each
-- facing along the circle the hub turns them on.
local function flock(parent: Instance, name: string, center: Vector3, spec: Flock, rng: Rng.Rng)
	local m = Style.model(name, parent)
	local hub = Style.block(m, CFrame.new(center), Vector3.new(1, 1, 1), C.Foam, nil, Kit.far({ Transparency = 1 }))
	hub.Name = "Hub"
	local dir = if spec.Speed >= 0 then 1 else -1
	for i = 1, spec.Birds do
		local a = i * (math.pi * 2 / spec.Birds) + rng:range(-0.25, 0.25)
		local r = spec.Radius * rng:range(0.7, 1)
		local off = Vector3.new(math.cos(a) * r, rng:range(-5, 5), math.sin(a) * r)
		-- a hub turning by +angle moves a point (x, z) along (z, -x)
		local forward = Vector3.new(off.Z, 0, -off.X).Unit * dir
		local p = center + off
		local cf = CFrame.lookAt(p, p + forward)
		local s = rng:range(0.9, 1.2)
		Style.block(m, cf, Vector3.new(0.8 * s, 0.7 * s, 2.4 * s), C.Foam, nil, Kit.far())
		for _, side in { -1, 1 } do
			local wing = cf * CFrame.new(side * 1.9 * s, 0.5 * s, 0.2) * CFrame.Angles(0, 0, side * math.rad(24))
			Style.block(m, wing, Vector3.new(3.4 * s, 0.25, 1.3 * s), if rng:chance(0.3) then K.RockGrey else C.AwningWhite, nil, Kit.far())
		end
	end
	m.PrimaryPart = hub
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", spec.Speed)
	m:SetAttribute("BobHeight", 3)
	m:SetAttribute("BobSpeed", 0.35)
end

function SkyLife.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("SkyLife", parent)
	for i, spec in SkyLife.Balloons do
		balloon(m, `Balloon{i}`, Place.at(spec.Az, spec.Dist, spec.Y), spec, Rng.new(`Horizon/Balloon/{i}/{rng:nextU32()}`))
	end
	for i, spec in SkyLife.Islets do
		islet(m, `Islet{i}`, Place.at(spec.Az, spec.Dist, spec.Y), spec, Rng.new(`Horizon/Islet/{i}/{rng:nextU32()}`))
	end
	for i, spec in SkyLife.Flocks do
		flock(m, `Flock{i}`, Place.at(spec.Az, spec.Dist, spec.Y), spec, Rng.new(`Horizon/Flock/{i}/{rng:nextU32()}`))
	end
	return m
end

return SkyLife
