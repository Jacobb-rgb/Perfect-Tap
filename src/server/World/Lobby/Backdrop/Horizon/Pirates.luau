--[[
	Big pirate ships on the far sea (owner 2026-10-17), after the Kenney
	Pirate Kit ships: a warm orange-brown hull with a dark wale, a stepped
	bow with a bowsprit, a tall two-deck stern castle with lit windows, gun
	ports, black sails with a white skull on the main sail and a black flag
	(or white sails for the merchant galleon), a crow's nest.

	Each ship bobs on the swell (tag Spin, SpinSpeed 0; client
	DecorController). Unreachable decoration, no lights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)
local Place = require(script.Parent.Place)

local C = Style.C
local K = Place.K

local Pirates = {}

type Spot = { Az: number, Dist: number, Heading: number, Length: number, Masts: number, Sails: string }

-- Bearing / studs from the plaza, the bearing the bow points to, size.
-- Broadsides face the town where they can.
Pirates.Spots = {
	{ Az = 160, Dist = 430, Heading = 270, Length = 74, Masts = 3, Sails = "Black" }, -- south: the flagship
	{ Az = 75, Dist = 470, Heading = 185, Length = 52, Masts = 2, Sails = "Black" }, -- east
	{ Az = 205, Dist = 520, Heading = 100, Length = 62, Masts = 3, Sails = "White" }, -- south-west: a merchant galleon
	{ Az = 86, Dist = 650, Heading = 20, Length = 36, Masts = 1, Sails = "Black" }, -- a sloop off the fort
} :: { Spot }

-- One mast with two square sails (flat sheet + bowed belly + yard each);
-- `emblem` paints a skull on the lower sail. `base` = foot on the deck,
-- LookVector = the bow.
local function mast(m: Model, base: CFrame, height: number, width: number, sail: Color3, emblem: boolean, rng: Rng.Rng)
	local t = math.max(0.9, height * 0.022)
	Style.block(m, base * CFrame.new(0, height / 2, 0), Vector3.new(t, height, t), K.HullTrim, nil, Kit.far())
	local y = height * 0.2
	for i, k in { 1, 0.78 } do
		local sw, sh = width * k, height * 0.36 * k
		local cy = y + sh / 2
		Style.block(m, base * CFrame.new(0, cy, -0.5), Vector3.new(sw, sh, 0.3), Style.vary(sail, rng, 0.02), nil, Kit.far())
		Style.block(m, base * CFrame.new(0, cy - sh * 0.04, -1.2), Vector3.new(sw * 0.8, sh * 0.76, 0.8), Style.vary(sail, rng, 0.03), nil, Kit.far())
		Style.block(m, base * CFrame.new(0, y + sh + 0.3, -0.4), Vector3.new(sw + 1.6, 0.6, 0.6), K.HullTrim, nil, Kit.far())
		if emblem and i == 1 then
			-- skull on the forward face of the belly: head, two eyes, jaw
			local face = base * CFrame.new(0, cy + sh * 0.04, -1.7)
			local s = sh * 0.34
			Style.block(m, face, Vector3.new(s, s * 0.9, 0.2), K.Skull, nil, Kit.far())
			Style.block(m, face * CFrame.new(0, -s * 0.55, 0), Vector3.new(s * 0.6, s * 0.3, 0.2), K.Skull, nil, Kit.far())
			for _, side in { -1, 1 } do
				Style.block(m, face * CFrame.new(side * s * 0.22, s * 0.05, -0.06), Vector3.new(s * 0.26, s * 0.26, 0.2), K.SailBlack, nil, Kit.far())
			end
		end
		y += sh + 1.2
	end
end

-- Height `k` hull-heights above the deck (the deck is at 0.95 H).
local function deckPlus(H: number, k: number): number
	return H * (0.95 + k)
end

-- A ship: `frame` = keel bottom center at the waterline, LookVector = bow.
local function ship(parent: Instance, name: string, frame: CFrame, spot: Spot, rng: Rng.Rng): Model
	local m = Style.model(name, parent)
	local L = spot.Length
	local B = L * 0.32
	local H = L * 0.17
	local sail = if spot.Sails == "White" then K.SailWhite else K.SailBlack
	local function box(at: Vector3, size: Vector3, color: Color3): Part
		return Kit.box(m, frame, at, size, color)
	end

	-- hull: dark bottom, warm planked sides, wale stripe, gunwale, deck
	local keel = box(Vector3.new(0, H * 0.18, 0.02 * L), Vector3.new(B * 0.62, H * 0.5, L * 0.74), K.HullDark)
	keel.Name = "Keel"
	box(Vector3.new(0, H * 0.62, 0.02 * L), Vector3.new(B, H * 0.6, L * 0.78), Style.vary(K.Hull, rng, 0.03))
	box(Vector3.new(0, H * 0.5, 0.02 * L), Vector3.new(B + 0.3, H * 0.12, L * 0.79), K.HullTrim)
	box(Vector3.new(0, H * 0.95 + 0.3, 0.02 * L), Vector3.new(B + 0.2, 0.6, L * 0.8), K.HullTrim)
	box(Vector3.new(0, H * 0.95, 0.02 * L), Vector3.new(B - 1, 0.3, L * 0.76), C.Plank)
	local deck = H * 0.95
	-- bow tapering in three steps and sweeping up, a raised forecastle, the bowsprit
	box(Vector3.new(0, H * 0.66, -L * 0.405), Vector3.new(B * 0.8, H * 0.96, L * 0.07), Style.vary(K.Hull, rng, 0.03))
	box(Vector3.new(0, H * 0.74, -L * 0.455), Vector3.new(B * 0.56, H * 1.04, L * 0.04), Style.vary(K.Hull, rng, 0.03))
	box(Vector3.new(0, H * 0.84, -L * 0.49), Vector3.new(B * 0.3, H * 1.02, L * 0.035), K.HullDark)
	box(Vector3.new(0, H * 0.5, -L * 0.43), Vector3.new(B * 0.82, H * 0.12, L * 0.12), K.HullTrim)
	box(Vector3.new(0, deckPlus(H, 0.17), -L * 0.31), Vector3.new(B * 0.94, H * 0.34, L * 0.16), Style.vary(K.Hull, rng, 0.03))
	box(Vector3.new(0, deckPlus(H, 0.36), -L * 0.31), Vector3.new(B * 0.98, 0.5, L * 0.17), K.HullTrim)
	Kit.beam(m, (frame * CFrame.new(0, deck + 0.6, -L * 0.48)).Position, (frame * CFrame.new(0, deck + L * 0.1, -L * 0.7)).Position, math.max(0.7, L * 0.014), K.HullTrim)
	-- stern castle: two decks, trims, lit windows on the back and sides
	local castle1 = Vector3.new(B * 0.98, H * 0.6, L * 0.26)
	local z1 = L * 0.39 - castle1.Z / 2 + 0.02 * L
	box(Vector3.new(0, deck + castle1.Y / 2, z1), castle1, Style.vary(K.Hull, rng, 0.03))
	box(Vector3.new(0, deck + castle1.Y + 0.25, z1), Vector3.new(castle1.X + 0.4, 0.5, castle1.Z + 0.4), K.HullTrim)
	local castle2 = Vector3.new(B * 0.86, H * 0.45, L * 0.13)
	local z2 = L * 0.39 - castle2.Z / 2 + 0.02 * L
	box(Vector3.new(0, deck + castle1.Y + castle2.Y / 2 + 0.5, z2), castle2, Style.vary(K.Hull, rng, 0.03))
	box(Vector3.new(0, deck + castle1.Y + castle2.Y + 0.75, z2), Vector3.new(castle2.X + 0.4, 0.5, castle2.Z + 0.4), K.HullTrim)
	local back = L * 0.41 + 0.1
	local n = if L > 50 then 3 else 2
	for i = 1, n do
		local x = (i - (n + 1) / 2) * (B * 0.7 / n)
		Kit.window(m, frame * CFrame.new(x, deck + castle1.Y * 0.5, back) * CFrame.Angles(0, math.pi, 0), B * 0.12, H * 0.2)
	end
	for _, side in { -1, 1 } do
		Kit.glow(m, frame * CFrame.new(side * (B * 0.49 + 0.15), deck + castle1.Y * 0.5, z1), Vector3.new(0.2, H * 0.18, castle1.Z * 0.5), C.Lamp)
	end
	Kit.glow(m, frame * CFrame.new(0, deck + castle1.Y + castle2.Y + 2.4, back - 1), Vector3.new(1.3, 1.6, 1.3), C.Fire).Name = "SternLantern"
	-- gun ports along both sides
	local ports = math.floor(L / 14)
	for i = 1, ports do
		local z = -L * 0.3 + (i - 0.5) * (L * 0.5 / ports)
		for _, side in { -1, 1 } do
			box(Vector3.new(side * (B / 2 + 0.1), H * 0.74, z), Vector3.new(0.3, H * 0.16, H * 0.2), Color3.fromRGB(40, 28, 26))
		end
	end

	-- masts: fore, main (tallest, skull), mizzen
	local masts: { { Z: number, Height: number } } = if spot.Masts >= 3
		then { { Z = -0.27, Height = 0.66 }, { Z = -0.04, Height = 0.8 }, { Z = 0.17, Height = 0.6 } }
		elseif spot.Masts == 2 then { { Z = -0.2, Height = 0.72 }, { Z = 0.08, Height = 0.82 } }
		else { { Z = -0.08, Height = 0.95 } }
	local tallest = 1
	for i, mt in masts do
		if mt.Height > masts[tallest].Height then
			tallest = i
		end
	end
	local tops: { Vector3 } = {}
	for i, mt in masts do
		local h = L * mt.Height
		local base = frame * CFrame.new(0, deck, L * mt.Z)
		mast(m, base, h, B * 1.25 * mt.Height / 0.8, sail, i == tallest and spot.Sails == "Black", rng)
		table.insert(tops, (base * CFrame.new(0, h, 0)).Position)
		if i == tallest then
			-- crow's nest and the flag
			Style.block(m, base * CFrame.new(0, h * 0.86, 0), Vector3.new(B * 0.22, 1.4, B * 0.22), K.HullDark, nil, Kit.far())
			local flagColor = if spot.Sails == "White" then C.AwningRed else K.SailBlack
			Style.block(m, base * CFrame.new(0, h + 1.2, 2.4), Vector3.new(0.3, 3, 4.4), flagColor, nil, Kit.far())
			if spot.Sails == "Black" then
				Style.block(m, base * CFrame.new(0.2, h + 1.3, 2.2), Vector3.new(0.3, 1.2, 1.2), K.Skull, nil, Kit.far())
			end
		end
	end
	-- rigging: bowsprit tip -> fore top -> ... -> stern
	local prev = (frame * CFrame.new(0, deck + L * 0.1, -L * 0.7)).Position
	for _, top in tops do
		Kit.beam(m, prev, top, 0.3, K.HullTrim)
		prev = top
	end
	Kit.beam(m, prev, (frame * CFrame.new(0, deck + castle1.Y + castle2.Y, back - 1)).Position, 0.3, K.HullTrim)

	m.PrimaryPart = keel
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", 0)
	m:SetAttribute("BobHeight", 0.8)
	m:SetAttribute("BobSpeed", 0.55)
	return m
end

function Pirates.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Pirates", parent)
	for i, spot in Pirates.Spots do
		local p = Place.at(spot.Az, spot.Dist, Place.Sea - spot.Length * 0.04)
		ship(m, `Ship{i}`, Place.heading(p, spot.Heading), spot, Rng.new(`Horizon/Pirates/{i}/{rng:nextU32()}`))
	end
	return m
end

return Pirates
