--[[
	Sky package, on the sea: the sun path glitter, two sailing ships, the
	castle islet on the horizon and the west pier with its boats
	(docs/plans/LOBBY_PLAN.md 6.1, items 4, 5, 6, 10).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

type Piece = LobbyLayout.Piece

local Sea = {}

-- Sea surface top (Land.luau: sea parts span y -23..-21).
local SEA_TOP = -21

---------------------------------------------------------------- sun glitter

--[[
	Broken neon strips on the sea along the sun path: thin (0.2), 1-3 studs
	along the path, 4-24 across it, spread +-6 near the shore to +-18 at the
	horizon, denser far out (perspective squeezes them there).
]]
function Sea.sunGlitter(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local frame = LobbyLayout.frame(piece)
	local half = piece.Size.Z / 2 - 1
	local halfW = piece.Size.X / 2
	local y = SEA_TOP + 0.15 - piece.Center.Y -- strip tops at -20.85
	local count = 92
	for i = 1, count do
		local s = math.clamp(((i - 0.5) / count) ^ 0.62 + rng:range(-0.004, 0.004), 0, 1)
		local z = half - s * 2 * half -- +half = near the shore, -half = toward the sun
		local spread = 6 + 12 * s
		local x = (rng:range(-1, 1) + rng:range(-1, 1)) * 0.5 * spread
		local across = (4 + 20 * s) * rng:range(0.45, 1)
		across = math.min(across, 2 * (halfW - math.abs(x)))
		local along = rng:range(1, 3) * (0.8 + 0.5 * s)
		local color = if math.abs(x) < spread * 0.4 or rng:chance(0.35) then C.Sun else C.CloudOrange
		local transparency = rng:range(0.25, 0.5)
		if across > 9 and rng:chance(0.3) then
			-- broken strip: two pieces with a gap
			local gap = rng:range(1, 2.5)
			local a = (across - gap) * rng:range(0.35, 0.65)
			local b = across - gap - a
			local left = x - across / 2
			Kit.glow(m, frame * CFrame.new(left + a / 2, y - 0.1, z), Vector3.new(a, 0.2, along), color, transparency)
			Kit.glow(m, frame * CFrame.new(left + a + gap + b / 2, y - 0.1, z + rng:range(-0.6, 0.6)), Vector3.new(b, 0.2, along), color, transparency)
		else
			Kit.glow(m, frame * CFrame.new(x, y - 0.1, z), Vector3.new(math.max(1, across), 0.2, along), color, transparency)
		end
	end
	Style.streaming(m, "Persistent")
	return m
end

---------------------------------------------------------------- ships

local function sternLights(m: Model, frame: CFrame, len: number, beam: number, deckY: number, windows: number)
	-- the stern castle's back face (local +Z) gets Lamp windows, the sides a few too
	local castleLen = len * 0.24
	local back = len * 0.4 + 0.04 * len + 0.2
	for i = 1, windows do
		local x = (i - (windows + 1) / 2) * (beam * 0.7 / windows)
		local cf = frame * CFrame.new(x, deckY + 1.3, back) * CFrame.Angles(0, math.pi, 0)
		Kit.window(m, cf, 1.1, 1.1)
	end
	for _, side in { -1, 1 } do
		local at = frame * CFrame.new(side * (beam * 0.48 + 0.12), deckY + 1.3, len * 0.4 - castleLen * 0.4)
		Kit.glow(m, at, Vector3.new(0.2, 0.9, 1.2), C.Lamp)
	end
	-- stern lantern on a short post
	local post = frame * CFrame.new(0, deckY + 2.8, back - 0.6)
	Style.block(m, post * CFrame.new(0, 0.9, 0), Vector3.new(0.35, 1.8, 0.35), C.WoodDark, nil, Kit.far())
	Kit.glow(m, post * CFrame.new(0, 2.2, 0), Vector3.new(1.1, 1.3, 1.1), C.Fire).Name = "SternLantern"
	Style.block(m, post * CFrame.new(0, 3, 0), Vector3.new(1.3, 0.35, 1.3), C.Iron, nil, Kit.far())
end

local function rigging(m: Model, frame: CFrame, from: Vector3, to: Vector3)
	Kit.beam(m, (frame * CFrame.new(from)).Position, (frame * CFrame.new(to)).Position, 0.18, C.WoodDark)
end

local function bobbing(m: Model, primary: BasePart)
	m.PrimaryPart = primary
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", 0)
	m:SetAttribute("BobHeight", 0.5)
	m:SetAttribute("BobSpeed", 0.8)
	Style.streaming(m, "Atomic")
end

-- ShipA: a two-masted ship sailing south past the west cliffs.
function Sea.shipA(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	-- keel 0.6 under the piece's base, shifted aft so the bowsprit stays in the footprint
	local frame = LobbyLayout.frame(piece) * CFrame.new(0, -0.6, 2)
	local len, beam = 29, 11
	local _, deckY, keel = Kit.hull(m, frame, rng, { Length = len, Beam = beam, Height = 4 })
	local main = Kit.mast(m, frame * CFrame.new(0, deckY, -1.5), 21, { { 10.5, 5.6 }, { 8.4, 4.2 } }, rng)
	main.Name = "MainMast"
	local fore = Kit.mast(m, frame * CFrame.new(0, deckY, -10), 17, { { 8.6, 4.6 }, { 6.6, 3.4 } }, rng)
	fore.Name = "ForeMast"
	-- crow's nest on the main mast
	Kit.box(m, frame, Vector3.new(0, deckY + 16.4, -1.5), Vector3.new(2.2, 0.9, 2.2), C.Wood)
	-- rigging: bowsprit to fore top, fore top to main top, main top to the stern
	rigging(m, frame, Vector3.new(0, deckY + 2.2, -len * 0.64), Vector3.new(0, deckY + 16.6, -10))
	rigging(m, frame, Vector3.new(0, deckY + 16.6, -10), Vector3.new(0, deckY + 20.5, -1.5))
	rigging(m, frame, Vector3.new(0, deckY + 20.5, -1.5), Vector3.new(0, deckY + 3, len * 0.42))
	sternLights(m, frame, len, beam, deckY, 3)
	-- stern flag, deck cargo
	Kit.box(m, frame, Vector3.new(0, deckY + 4.6, len * 0.43), Vector3.new(0.25, 3.6, 0.25), C.WoodDark)
	Kit.box(m, frame, Vector3.new(0, deckY + 5.8, len * 0.43 + 1.1), Vector3.new(0.15, 1.4, 2), C.AwningRed)
	Kit.box(m, frame, Vector3.new(-2.6, deckY + 0.9, 3.8), Vector3.new(1.6, 1.6, 1.6), C.WoodLight)
	Kit.box(m, frame, Vector3.new(2.4, deckY + 0.8, 5), Vector3.new(1.4, 1.4, 1.4), C.Wood)
	bobbing(m, keel)
	return m
end

-- ShipB: a smaller one-masted ship heading north-north-east toward the island.
function Sea.shipB(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local frame = LobbyLayout.frame(piece) * CFrame.new(0, -0.6, 1.5)
	local len, beam = 20, 8
	local _, deckY, keel = Kit.hull(m, frame, rng, { Length = len, Beam = beam, Height = 3.2 })
	Kit.mast(m, frame * CFrame.new(0, deckY, -2), 16, { { 8, 4.6 }, { 6.2, 3.3 } }, rng).Name = "MainMast"
	rigging(m, frame, Vector3.new(0, deckY + 2.2, -len * 0.64), Vector3.new(0, deckY + 15.5, -2))
	rigging(m, frame, Vector3.new(0, deckY + 15.5, -2), Vector3.new(0, deckY + 3, len * 0.42))
	sternLights(m, frame, len, beam, deckY, 2)
	Kit.box(m, frame, Vector3.new(1.6, deckY + 0.8, 2.6), Vector3.new(1.4, 1.4, 1.4), C.WoodLight)
	bobbing(m, keel)
	return m
end

---------------------------------------------------------------- castle islet

local function merlons(m: Model, frame: CFrame, center: Vector3, length: number, alongX: boolean, count: number, color: Color3)
	for i = 1, count do
		local t = (i - 0.5) / count - 0.5
		local at = if alongX then center + Vector3.new(t * length, 0, 0) else center + Vector3.new(0, 0, t * length)
		Kit.box(m, frame, at, Vector3.new(1.8, 2, 1.8), color)
	end
end

--[[
	Distant rocky islet with a castle and a lighthouse: a low-detail
	silhouette in muted StoneDeep/SkyPurple that the haze softens.
]]
function Sea.castleIsland(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local frame = LobbyLayout.frame(piece)
	local rockA, rockB = C.StoneDeep, C.StoneDark
	-- rock: three stepped tiers rising ~20 above the sea, plus accent blocks
	Kit.box(m, frame, Vector3.new(-6, 4, 0), Vector3.new(84, 12, 52), Style.vary(rockA, rng, 0.04))
	Kit.box(m, frame, Vector3.new(-10, 12.5, -2), Vector3.new(60, 7, 38), Style.vary(rockB, rng, 0.04))
	Kit.box(m, frame, Vector3.new(-12, 18.5, -1), Vector3.new(42, 5, 28), Style.vary(rockA, rng, 0.04))
	Kit.box(m, frame, Vector3.new(-12, 21.2, -1), Vector3.new(40, 0.6, 26), Style.vary(C.GrassDark, rng, 0.04))
	for _ = 1, 6 do
		local s = Vector3.new(rng:range(8, 16), rng:range(5, 10), rng:range(6, 12))
		local at = Vector3.new(rng:range(-44, 30), s.Y / 2 - 1, if rng:chance(0.6) then -24 else 24)
		Kit.box(m, frame, at, s, Style.vary(if rng:chance(0.5) then rockA else rockB, rng, 0.05))
	end
	-- the lighthouse rock at the east end
	Kit.box(m, frame, Vector3.new(42, 5, 4), Vector3.new(18, 14, 16), Style.vary(rockB, rng, 0.04))
	Kit.box(m, frame, Vector3.new(42, 13, 4), Vector3.new(11, 4, 10), Style.vary(rockA, rng, 0.04))

	local wall, wallDark, roof = C.StoneDark, C.StoneDeep, C.SkyPurple
	local base = 21.5
	-- curtain walls around a courtyard
	Kit.box(m, frame, Vector3.new(-12, base + 3.5, -11), Vector3.new(32, 7, 2), Style.vary(wall, rng, 0.03))
	Kit.box(m, frame, Vector3.new(-12, base + 3.5, 9), Vector3.new(32, 7, 2), Style.vary(wallDark, rng, 0.03))
	Kit.box(m, frame, Vector3.new(-27, base + 3.5, -1), Vector3.new(2, 7, 20), Style.vary(wall, rng, 0.03))
	Kit.box(m, frame, Vector3.new(3, base + 3.5, -1), Vector3.new(2, 7, 20), Style.vary(wall, rng, 0.03))
	merlons(m, frame, Vector3.new(-12, base + 8, -11), 26, true, 6, wall)
	merlons(m, frame, Vector3.new(3, base + 8, -1), 16, false, 3, wall)
	merlons(m, frame, Vector3.new(-27, base + 8, -1), 16, false, 3, wall)
	-- gate
	Kit.box(m, frame, Vector3.new(-12, base + 2.2, -12.1), Vector3.new(4, 4.4, 0.4), C.WoodDark)
	-- the keep
	Kit.box(m, frame, Vector3.new(-14, base + 9, 0), Vector3.new(12, 18, 10), Style.vary(wall, rng, 0.03))
	merlons(m, frame, Vector3.new(-14, base + 19, -4.6), 10, true, 3, wall)
	Kit.box(m, frame, Vector3.new(-14, base + 18.6, 0), Vector3.new(12.6, 0.8, 10.6), wallDark)
	Kit.box(m, frame, Vector3.new(-14, base + 20.5, 0), Vector3.new(7, 3, 6), roof)
	Kit.box(m, frame, Vector3.new(-14, base + 23, 0), Vector3.new(4, 2.4, 3.6), roof)
	for _, x in { -17, -11 } do
		Kit.glow(m, frame * CFrame.new(x, base + 13, -5.05), Vector3.new(1.2, 1.8, 0.2), C.Lamp)
	end
	Kit.glow(m, frame * CFrame.new(-14, base + 8, -5.05), Vector3.new(1.4, 2, 0.2), C.Lamp)
	-- three towers: two crenellated, the tallest with a pointed roof and a flag
	local towers = {
		{ At = Vector3.new(-27, 0, -11), Height = 15, Pointed = false },
		{ At = Vector3.new(3, 0, -11), Height = 13, Pointed = false },
		{ At = Vector3.new(-27, 0, 9), Height = 21, Pointed = true },
	}
	for _, t in towers do
		local p, h, pointed = t.At, t.Height, t.Pointed
		Kit.box(m, frame, p + Vector3.new(0, base + h / 2, 0), Vector3.new(6, h, 6), Style.vary(wall, rng, 0.03))
		Kit.box(m, frame, p + Vector3.new(0, base + h + 0.4, 0), Vector3.new(7.2, 0.8, 7.2), wallDark)
		if pointed then
			Kit.box(m, frame, p + Vector3.new(0, base + h + 2.3, 0), Vector3.new(5, 3, 5), roof)
			Kit.box(m, frame, p + Vector3.new(0, base + h + 4.8, 0), Vector3.new(2.8, 2.4, 2.8), roof)
			Kit.box(m, frame, p + Vector3.new(0, base + h + 7.2, 0), Vector3.new(0.3, 2.6, 0.3), C.WoodDark)
			Kit.box(m, frame, p + Vector3.new(0, base + h + 8, 1.1), Vector3.new(0.2, 1, 2), C.AwningRed)
		else
			for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
				Kit.box(m, frame, p + Vector3.new(c[1] * 2.7, base + h + 1.6, c[2] * 2.7), Vector3.new(1.8, 1.8, 1.8), wall)
			end
		end
		Kit.glow(m, frame * CFrame.new(p + Vector3.new(0, base + h * 0.62, -3.05)), Vector3.new(1, 1.6, 0.2), C.Lamp)
	end
	-- lighthouse: banded tapered tower, gallery, lamp room, cap
	local lh = Vector3.new(42, 15, 4)
	Kit.box(m, frame, lh + Vector3.new(0, 5, 0), Vector3.new(6, 10, 6), C.StoneLight)
	Kit.box(m, frame, lh + Vector3.new(0, 10.5, 0), Vector3.new(6.2, 1.6, 6.2), C.RoofDark)
	Kit.box(m, frame, lh + Vector3.new(0, 15.5, 0), Vector3.new(5, 8.4, 5), C.StoneLight)
	Kit.box(m, frame, lh + Vector3.new(0, 20, 0), Vector3.new(6.6, 0.6, 6.6), C.Iron)
	local lamp = Kit.glow(m, frame * CFrame.new(lh + Vector3.new(0, 21.8, 0)), Vector3.new(3, 3, 3), C.Lamp)
	lamp.Name = "LighthouseLamp"
	Kit.box(m, frame, lh + Vector3.new(0, 23.8, 0), Vector3.new(4.2, 1, 4.2), C.RoofDark)
	Kit.box(m, frame, lh + Vector3.new(0, 25, 0), Vector3.new(1.6, 1.4, 1.6), C.RoofDark)
	Style.streaming(m, "Lod")
	return m
end

---------------------------------------------------------------- west pier

local function lanternPost(m: Model, cf: CFrame, height: number): Part
	Style.block(m, cf * CFrame.new(0, height / 2, 0), Vector3.new(0.6, height, 0.6), C.WoodDark, nil, Kit.far())
	local glow = Kit.glow(m, cf * CFrame.new(0, height + 0.5, 0), Vector3.new(0.9, 1, 0.9), C.Lamp)
	glow.Name = "LanternGlow"
	Style.block(m, cf * CFrame.new(0, height + 1.15, 0), Vector3.new(1.2, 0.3, 1.2), C.Iron, nil, Kit.far())
	return glow
end

-- Rowboat: `cf` = bottom center on the water, LookVector = bow. 6 parts.
local function rowboat(m: Model, cf: CFrame, rng: Rng.Rng)
	Style.block(m, cf * CFrame.new(0, 0.3, 0), Vector3.new(1.4, 0.6, 4.4), C.WoodDark, nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 0.9, 0), Vector3.new(2.2, 0.8, 4.8), Style.vary(C.Wood, rng, 0.04), nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 0.95, -2.7), Vector3.new(1.2, 0.7, 0.8), C.Wood, nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 1.2, 0.3), Vector3.new(2, 0.25, 0.9), C.Plank, nil, Kit.far())
	for _, side in { -1, 1 } do
		local oar = cf * CFrame.new(side * 1.5, 1.3, 0.4) * CFrame.Angles(0, side * 0.5, side * 0.35)
		Style.block(m, oar, Vector3.new(0.2, 0.2, 3.4), C.WoodLight, nil, Kit.far())
	end
end

-- Small sailboat with a fore-and-aft sail. 7 parts.
local function sailboat(m: Model, cf: CFrame, rng: Rng.Rng)
	Style.block(m, cf * CFrame.new(0, 0.35, 0), Vector3.new(1.6, 0.7, 5.6), C.WoodDark, nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 1.05, 0.2), Vector3.new(2.6, 0.8, 6), Style.vary(C.Wood, rng, 0.04), nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 1.15, 0.2), Vector3.new(2.7, 0.25, 6.1), C.RoofTrim, nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 4.6, -0.6), Vector3.new(0.35, 7, 0.35), C.WoodDark, nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 4.4, 0.9), Vector3.new(0.2, 5, 2.8), C.AwningWhite, nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 1.9, 0.9), Vector3.new(0.3, 0.3, 3.4), C.WoodDark, nil, Kit.far())
	Style.block(m, cf * CFrame.new(0, 7.7, -0.1), Vector3.new(0.15, 0.7, 1.4), C.AwningRed, nil, Kit.far())
end

--[[
	Pier below the west cliff (decor only, beyond the island's invisible
	wall): timber stairs in two flights from the cliff top down to a plank
	dock 2.5 above the sea, a narrow finger pier with a moored rowboat and a
	small sailboat, posts into the water, four glowing lantern posts (one
	PointLight, outside the lobby area).
	Piece frame: local +Z = east (the cliff), -Z = west (the sea), +X = north.
]]
function Sea.westPier(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local frame = LobbyLayout.frame(piece)
	local deckY = SEA_TOP + 1.5 - piece.Center.Y -- local height of the dock top (world -19.5)
	local topY = 0 - piece.Center.Y -- island ground (world 0)
	local stairX = -4 -- the stairs start at world (-178, 0, -32)
	local deck = Style.decor()

	-- landing on the cliff top
	Kit.box(m, frame, Vector3.new(stairX + 0.4, topY - 0.2, 19.4), Vector3.new(4.6, 0.4, 3.4), C.Plank, nil, deck)
	-- two flights with a landing; every step is one chunky tread
	local flights = {
		{ fromZ = 17.6, fromY = topY, toZ = 9.6, toY = topY - 9.6, steps = 8 },
		{ fromZ = 7.2, fromY = topY - 9.8, toZ = -0.4, toY = deckY + 0.4, steps = 8 },
	}
	for _, f in flights do
		local run = (f.fromZ - f.toZ) / f.steps
		local rise = (f.fromY - f.toY) / f.steps
		for i = 1, f.steps do
			local z = f.fromZ - run * (i - 0.5)
			local y = f.fromY - rise * i
			Kit.box(m, frame, Vector3.new(stairX, y - 0.25, z), Vector3.new(3.6, 0.5, run + 0.15), Style.vary(C.WoodLight, rng, 0.05), nil, deck)
		end
		for _, side in { -1, 1 } do
			local x = stairX + side * 2
			local a = frame * CFrame.new(x, f.fromY - 0.5, f.fromZ)
			local b = frame * CFrame.new(x, f.toY - 0.5, f.toZ)
			Kit.beam(m, a.Position, b.Position, 0.6, C.WoodDark)
			-- handrail 3 studs above the treads
			Kit.beam(m, a.Position + Vector3.new(0, 3.2, 0), b.Position + Vector3.new(0, 3.2, 0), 0.35, C.Wood)
		end
	end
	-- mid landing on two stilts
	Kit.box(m, frame, Vector3.new(stairX, topY - 9.8, 8.4), Vector3.new(4, 0.5, 2.8), C.Plank, nil, deck)
	for _, side in { -1, 1 } do
		local x = stairX + side * 1.6
		local top = topY - 10
		Kit.box(m, frame, Vector3.new(x, (top + deckY - 4) / 2, 8.4), Vector3.new(0.8, top - deckY + 4, 0.8), C.WoodDark)
	end

	-- the dock (8 wide) and the finger pier (3 wide)
	local dockFrom, dockTo = 0.6, -14
	Style.planks(m, frame * CFrame.new(0, deckY, (dockFrom + dockTo) / 2), Vector3.new(8, 0.6, dockFrom - dockTo), rng)
	Style.planks(m, frame * CFrame.new(0, deckY, -18), Vector3.new(3, 0.6, 8), rng, { PlankWidth = 1.4 })
	for _, z in { 0, -6.5, -13.5 } do
		for _, x in { -3.6, 3.6 } do
			Kit.box(m, frame, Vector3.new(x, deckY - 2.6, z), Vector3.new(0.8, 5.6, 0.8), C.WoodDark)
		end
	end
	Kit.box(m, frame, Vector3.new(0, deckY - 2.6, -21.6), Vector3.new(0.8, 5.6, 0.8), C.WoodDark)
	-- lantern posts: top of the stairs, foot of the stairs, both dock corners
	lanternPost(m, frame * CFrame.new(stairX - 1.2, topY, 20.6), 2.8)
	lanternPost(m, frame * CFrame.new(3.6, deckY, 0.2), 4)
	lanternPost(m, frame * CFrame.new(-3.6, deckY, -13.6), 4)
	local lit = lanternPost(m, frame * CFrame.new(3.6, deckY, -13.6), 4)
	Style.light(lit, C.Lamp, 16, 1.3)
	-- moored boats beside the finger pier
	local water = SEA_TOP - piece.Center.Y - 0.3
	rowboat(m, frame * CFrame.new(-3.2, water, -18) * CFrame.Angles(0, 0.06, 0), rng)
	sailboat(m, frame * CFrame.new(3.4, water, -18.2) * CFrame.Angles(0, -0.05, 0), rng)
	-- cargo on the dock
	Style.crate(m, frame * CFrame.new(-2.4, deckY, -3), rng, 1.6)
	Kit.box(m, frame, Vector3.new(-2.6, deckY + 0.5, -5), Vector3.new(1.4, 1, 1.4), C.Wood)
	return m
end

return Sea
