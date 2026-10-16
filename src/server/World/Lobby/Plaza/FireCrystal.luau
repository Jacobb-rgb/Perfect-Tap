--[[
	The giant fire crystal in the middle of the plaza (LOBBY_PLAN 6.3.2):
	a glowing ember moat inside a ring of dark stone blocks with Fire
	insets (open N and S, a threshold step in each gap), a stepped
	star-shaped stone base with a glowing fire bed, an octagonal pedestal
	with an Ember seam, and the crystal cluster on top.

	Hook: the crystal cluster is the Model "FireCrystal", tagged Spin
	(SpinSpeed 0.25, BobHeight 0.5, BobSpeed 0.9), streamed Atomic, its
	PrimaryPart the main crystal body (Y axis = the spin axis). The one
	PointLight sits on the main body.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local C = Style.C
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local FireCrystal = {}

FireCrystal.SpinSpeed = 0.25
FireCrystal.BobHeight = 0.5
FireCrystal.BobSpeed = 0.9

local RING_R = 11
local RING_SEGMENTS = 18 -- one block centered on S (90 deg) and N (270 deg)
local RING_H = 1.6
local INNER = 12.4 -- side of the star base blocks
local INNER_H = 1.6
local PEDESTAL = 6.6
local PEDESTAL_H = 1.4
local CRYSTAL_H = 10.5
local CRYSTAL_W = 3.4

-- Two square slabs turned 45 degrees to each other (an 8-point star).
local function star(
	parent: Instance,
	cf: CFrame,
	side: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	props: { [string]: any }?
): { Part }
	local p = props or Style.solid()
	return {
		Style.block(parent, cf, Vector3.new(side, height, side), color, material or SMOOTH, p),
		Style.block(parent, cf * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(side, height, side), color, material or SMOOTH, p),
	}
end

--[[
	The main crystal: a see-through orange shell (Transparency 0.3, so its
	facets catch the sun and the lamps) around a slim neon core, so the
	crystal reads as a faceted gem that glows from within instead of a flat
	neon blob. Returns the core body (the spin pivot).
]]
local function mainCrystal(parent: Instance, base: CFrame): BasePart
	local shell = Style.crystal(parent, base, CRYSTAL_H, CRYSTAL_W, C.Fire, C.LeafOrange)
	for i, part in shell do
		part.Material = SMOOTH
		part.Transparency = if i == 1 then 0.3 else 0.22
		part.Name = "CrystalShell"
	end
	local core = Style.crystal(parent, base * CFrame.new(0, 0.4, 0), CRYSTAL_H * 0.86, CRYSTAL_W * 0.46, C.Fire, C.FireCore)
	core[1].Name = "CrystalBody"
	return core[1]
end

local function crystalCluster(parent: Instance, base: CFrame, rng: Rng.Rng): Model
	local m = Style.model("FireCrystal", parent)
	local body = mainCrystal(m, base)
	-- leaning side crystals (deep Ember glow, Fire tips) and small shards
	local sides = {
		{ A = 25, H = 7.2, Lean = 0.38, Color = C.Ember },
		{ A = 115, H = 5.6, Lean = 0.46, Color = C.Ember },
		{ A = 205, H = 6.6, Lean = 0.4, Color = C.Ember },
		{ A = 295, H = 5.2, Lean = 0.5, Color = C.Ember },
		{ A = 70, H = 3.4, Lean = 0.7, Color = C.Fire },
		{ A = 160, H = 3.0, Lean = 0.75, Color = C.Ember },
		{ A = 250, H = 3.6, Lean = 0.65, Color = C.Fire },
	}
	for i, s in sides do
		local a = math.rad(s.A + rng:range(-6, 6))
		local foot = base * CFrame.new(math.cos(a) * 1.6, 0.1, math.sin(a) * 1.6)
		local tilt = CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -s.Lean) * CFrame.Angles(0, a, 0)
		local parts = Style.crystal(m, foot * tilt, s.H, s.H * 0.3, s.Color, C.Fire)
		if i <= 4 then
			-- the big side crystals: shaded amber bodies (facets read), glowing tips
			parts[1].Material = SMOOTH
			parts[1].Color = if i % 2 == 0 then C.LeafOrange else C.Fire
			parts[1].Transparency = 0.12
		end
	end
	m.PrimaryPart = body
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", FireCrystal.SpinSpeed)
	m:SetAttribute("BobHeight", FireCrystal.BobHeight)
	m:SetAttribute("BobSpeed", FireCrystal.BobSpeed)
	Style.streaming(m, "Atomic")
	Style.light(body, C.Fire, 40, 2.2)
	Style.emitter(body, "Sparkle", C.FireCore, 3)
	return m
end

function FireCrystal.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("FireCrystal")
	local center = piece.Center
	local y0 = Common.TileTop
	local m = Style.model("FireCrystalRing", parent)

	-- glowing ember moat between the outer ring and the star base
	local moat = Geo.cylinder(m, center + Vector3.new(0, y0 - 0.01, 0), 0.1, (RING_R - 1.25) * 2, C.Ember, NEON, Style.tiny())
	moat.Name = "EmberMoat"

	-- outer ring: dark stone blocks with Fire insets, open toward S and N
	local gaps = {
		{ math.rad(80), math.rad(100) },
		{ math.rad(260), math.rad(280) },
	}
	local ring = Style.stoneRing(m, center, RING_R, rng, {
		Segments = RING_SEGMENTS,
		Height = RING_H,
		Width = 2.4,
		Color = C.StoneDark,
		Glow = C.Fire,
		Y = y0,
		Gaps = gaps,
	})
	for _, block in ring do
		block.Name = "RingStone"
	end
	-- threshold steps in the two gaps
	for _, deg in { 90, 270 } do
		local a = math.rad(deg)
		local frame = CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(RING_R, y0 + 0.25, 0)
		Style.block(m, frame, Vector3.new(2.4, 0.5, 3.6), Style.vary(C.StoneLight, rng, 0.04), nil, Style.solid())
	end
	-- little ground lamps on four ring blocks
	for _, i in { 2, 6, 11, 15 } do
		local a = (i + 0.5) / RING_SEGMENTS * 2 * math.pi
		local top = y0 + RING_H + (if i % 3 == 0 then 0.3 else 0)
		local base = CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(RING_R, top, 0)
		Style.lantern(m, base, { Kind = "Ground", Color = C.Fire })
	end

	-- stepped star base, StoneDark cap and the glowing fire bed
	local yInner = y0 + INNER_H
	star(m, CFrame.new(center + Vector3.new(0, y0 + INNER_H / 2, 0)), INNER, INNER_H, Style.vary(C.Stone, rng, 0.03))
	star(m, CFrame.new(center + Vector3.new(0, yInner + 0.2, 0)), INNER + 0.6, 0.4, Style.vary(C.StoneDark, rng, 0.03))
	local bed = star(m, CFrame.new(center + Vector3.new(0, yInner + 0.4, 0)), INNER - 3.4, 0.2, C.Ember, NEON, Style.tiny())
	bed[1].Name = "FireBed"
	bed[2].Name = "FireBed"
	Style.emitter(bed[1], "Fire", C.Fire, 12)
	Style.emitter(bed[1], "Embers", C.Fire, 6)

	-- octagonal pedestal with an Ember seam
	local yPed = yInner + 0.4
	star(
		m,
		CFrame.new(center + Vector3.new(0, yPed + PEDESTAL_H / 2, 0)) * CFrame.Angles(0, math.pi / 8, 0),
		PEDESTAL,
		PEDESTAL_H,
		Style.vary(C.StoneDark, rng, 0.03)
	)
	star(
		m,
		CFrame.new(center + Vector3.new(0, yPed + PEDESTAL_H * 0.45, 0)) * CFrame.Angles(0, math.pi / 8, 0),
		PEDESTAL + 0.25,
		0.25,
		C.Ember,
		NEON,
		Style.tiny()
	)

	crystalCluster(parent, CFrame.new(center + Vector3.new(0, yPed + PEDESTAL_H, 0)), rng)
end

return FireCrystal
