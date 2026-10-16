--[[
	Sky package: the hot air balloon over the NW cliff (docs/plans/LOBBY_PLAN.md
	6.1 item 9). A red/yellow striped envelope (each layer is a red block and
	a yellow block turned 45 degrees: from any side the colors alternate like
	vertical stripes), a skirt, four ropes, a glowing burner with the one
	PointLight, and a little airship gondola with a propeller and a tail fin.
	The whole model turns slowly and bobs (tag Spin, client DecorController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

type Piece = LobbyLayout.Piece

local Balloon = {}

-- Envelope layers bottom to top: { width, height } (~14 across at the belly).
local LAYERS = { { 8, 2.4 }, { 11.4, 2.6 }, { 12.2, 2.8 }, { 12.2, 2.8 }, { 11, 2.6 }, { 8, 2.2 } }
-- the 45-degree block is a bit smaller: each color shows as a stripe from every side
local TURNED = 0.92

function Balloon.build(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local frame = LobbyLayout.frame(piece) -- bottom center, LookVector = the gondola's bow

	-- gondola: a small airship hull (the basket is the PrimaryPart)
	local basket = Kit.box(m, frame, Vector3.new(0, 1.5, 0), Vector3.new(2.8, 1.6, 5.2), Style.vary(C.Wood, rng, 0.03))
	basket.Name = "Basket"
	Kit.box(m, frame, Vector3.new(0, 0.45, 0.2), Vector3.new(1.6, 0.9, 4.4), C.WoodDark)
	Kit.box(m, frame, Vector3.new(0, 1.3, -3), Vector3.new(1.8, 1.2, 1), C.Wood)
	Kit.box(m, frame, Vector3.new(0, 1.15, -3.7), Vector3.new(0.9, 0.8, 0.6), C.WoodDark)
	Kit.box(m, frame, Vector3.new(0, 2.45, 0), Vector3.new(3.1, 0.35, 5.5), C.WoodDark)
	Kit.box(m, frame, Vector3.new(0, 1.6, 0), Vector3.new(2.95, 0.3, 5.3), C.RoofTrim)
	-- sandbags on the sides
	for _, side in { -1, 1 } do
		Kit.box(m, frame, Vector3.new(side * 1.6, 1.1, 1.2), Vector3.new(0.6, 0.8, 0.7), C.DirtLight)
	end
	-- propeller and tail fin at the stern (+Z)
	Kit.box(m, frame, Vector3.new(0, 1.5, 2.9), Vector3.new(0.5, 0.5, 0.8), C.Iron)
	Kit.box(m, frame, Vector3.new(0, 1.5, 3.35), Vector3.new(0.35, 3.2, 0.25), C.WoodLight)
	Kit.box(m, frame * CFrame.new(0, 1.5, 3.4) * CFrame.Angles(0, 0, math.pi / 2), Vector3.zero, Vector3.new(0.35, 3.2, 0.25), C.WoodLight)
	Kit.box(m, frame, Vector3.new(0, 2.9, 2.3), Vector3.new(0.25, 1.4, 1.4), C.AwningRed)

	-- burner over the gondola: iron frame + neon flame (the light)
	Kit.box(m, frame, Vector3.new(0, 6.6, 0), Vector3.new(1.8, 0.35, 1.8), C.Iron)
	local flame = Kit.glow(m, frame * CFrame.new(0, 7.35, 0), Vector3.new(0.9, 1.2, 0.9), C.Fire)
	flame.Name = "Burner"
	Style.light(flame, C.Fire, 14, 1.4)

	-- skirt under the envelope
	local skirtY = 8.6
	Kit.box(m, frame, Vector3.new(0, skirtY, 0), Vector3.new(4.8, 1.6, 4.8), C.LeafYellow)
	Kit.box(m, frame, Vector3.new(0, skirtY - 0.9, 0), Vector3.new(5.2, 0.3, 5.2), C.WoodDark)
	-- four ropes from the gondola rail to the skirt ring
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local a = (frame * CFrame.new(c[1] * 1.3, 2.6, c[2] * 2.4)).Position
		local b = (frame * CFrame.new(c[1] * 2.4, skirtY - 1, c[2] * 2.4)).Position
		Kit.beam(m, a, b, 0.16, C.WoodLight)
	end

	-- envelope: red block + yellow block turned 45 degrees per layer
	local y = skirtY + 0.8
	local turned = CFrame.Angles(0, math.pi / 4, 0)
	for _, layer in LAYERS do
		local w, h = layer[1], layer[2]
		local at = frame * CFrame.new(0, y + h / 2, 0)
		Style.block(m, at, Vector3.new(w, h, w), C.AwningRed, nil, Kit.far())
		Style.block(m, at * turned, Vector3.new(w * TURNED, h, w * TURNED), C.LeafYellow, nil, Kit.far())
		y += h
	end
	-- crown
	Kit.box(m, frame, Vector3.new(0, y + 0.3, 0), Vector3.new(4.4, 0.6, 4.4), C.AwningRed)

	m.PrimaryPart = basket
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", 0.05)
	m:SetAttribute("BobHeight", 2)
	m:SetAttribute("BobSpeed", 0.5)
	Style.streaming(m, "Atomic")
	return m
end

return Balloon
