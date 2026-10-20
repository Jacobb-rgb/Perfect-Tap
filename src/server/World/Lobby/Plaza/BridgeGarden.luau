--[[
	The bridge garden (owner 2026-10-20: "remake THE GREAT FORGE: behind it is
	the way into the cave in the mountains, so a bridge with a massive roof,
	little ponds with lily pads around, big trees, bamboo along, a beautiful
	stone path after the wooden bridge, and lights everywhere").

	Where THE GREAT FORGE stood (x -21..21, z -38..-86), on to the quarry
	ramp (z -112):

	  Landing   stone steps off the plaza's north edge (z -38..-44)
	  Pond      a wide pond under the bridge (z -47..-65), lily pads, reeds
	  Bridge    a humped wooden bridge (walkable) under a massive gable roof
	            on posts, lanterns hanging from the eaves
	  Path      a flagstone path from the bridge to the quarry ramp, lantern
	            posts on both sides, bamboo groves along it
	  Ponds     two small ponds left and right of the path, lily pads
	  Trees     big trees at the corners

	Three looks for the owner to choose from (BridgeGarden.Styles):
	  A  Garden   red lacquered posts, a two-tier dark slate roof with
	              upturned eaves and gold trim, pink blossom trees
	  B  Forest   heavy log posts, a thick moss-and-thatch roof, big green trees
	  C  Stone    stone piers and pillars, a copper-green roof, autumn trees
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Meadow = require(script.Parent.Parent.Flora.Meadow)
local VaultStatue = require(script.Parent.Parent.Vault.Statue)

local C = Style.C
local NEON = Enum.Material.Neon

export type Look = {
	Name: string,
	Post: Color3,
	PostSize: number,
	PostStone: boolean?,
	Beam: Color3,
	Roof: Color3,
	RoofDark: Color3,
	Trim: Color3,
	Tiers: number,
	Upturn: boolean,
	RoofThick: number,
	Trees: { string },
	Lamp: Color3,
	Slab: Color3,
	SlabDark: Color3,
}

local BridgeGarden = {}

BridgeGarden.Styles = {
	A = {
		Name = "Garden",
		Post = Color3.fromRGB(176, 38, 34),
		PostSize = 0.9,
		Beam = Color3.fromRGB(120, 24, 22),
		Roof = Color3.fromRGB(58, 62, 82),
		RoofDark = Color3.fromRGB(38, 40, 56),
		Trim = Color3.fromRGB(236, 184, 60),
		Tiers = 2,
		Upturn = true,
		RoofThick = 0.9,
		Trees = { "Pink", "Pink" },
		Lamp = Color3.fromRGB(255, 170, 70),
		Slab = Color3.fromRGB(176, 172, 162),
		SlabDark = Color3.fromRGB(128, 124, 118),
	},
	B = {
		Name = "Forest",
		Post = Color3.fromRGB(110, 76, 48),
		PostSize = 1.3,
		Beam = Color3.fromRGB(84, 58, 38),
		Roof = Color3.fromRGB(112, 120, 58),
		RoofDark = Color3.fromRGB(86, 74, 44),
		Trim = Color3.fromRGB(70, 50, 34),
		Tiers = 1,
		Upturn = false,
		RoofThick = 1.8,
		Trees = { "Green", "Green" },
		Lamp = Color3.fromRGB(255, 186, 90),
		Slab = Color3.fromRGB(150, 156, 130),
		SlabDark = Color3.fromRGB(104, 112, 92),
	},
	C = {
		Name = "Stone",
		Post = Color3.fromRGB(150, 146, 140),
		PostSize = 1.4,
		PostStone = true,
		Beam = Color3.fromRGB(96, 70, 46),
		Roof = Color3.fromRGB(70, 140, 122),
		RoofDark = Color3.fromRGB(48, 100, 88),
		Trim = Color3.fromRGB(206, 130, 70),
		Tiers = 1,
		Upturn = false,
		RoofThick = 1.1,
		Trees = { "Orange", "Red" },
		Lamp = Color3.fromRGB(255, 196, 110),
		Slab = Color3.fromRGB(184, 176, 164),
		SlabDark = Color3.fromRGB(140, 130, 120),
	},
} :: { [string]: Look }

-- the plan (world studs)
BridgeGarden.Area = { Min = Vector3.new(-22, 0, -112), Max = Vector3.new(22, 0, -38) }
BridgeGarden.BridgeFrom = Vector3.new(0, 0, -43)
BridgeGarden.BridgeTo = Vector3.new(0, 0, -69)
BridgeGarden.BridgeWidth = 8
BridgeGarden.Rise = 1.8
BridgeGarden.PathEnd = -112
BridgeGarden.PathWidth = 6
BridgeGarden.Pond = { Center = Vector3.new(0, 0, -56), Size = Vector2.new(40, 19) }
BridgeGarden.SidePonds = {
	{ Center = Vector3.new(-14.5, 0, -89), Size = Vector2.new(11, 15) },
	{ Center = Vector3.new(14.5, 0, -89), Size = Vector2.new(11, 15) },
}

local function lilies(parent: Instance, center: Vector3, sx: number, sz: number, count: number, rng: Rng.Rng)
	for _ = 1, count do
		local p = center + Vector3.new(rng:range(-sx * 0.36, sx * 0.36), 0.68, rng:range(-sz * 0.3, sz * 0.3))
		Geo.cylinder(parent, p, 0.1, rng:range(1.4, 2.4), Style.vary(C.LeafGreen, rng, 0.06), nil, Style.tiny())
		if rng:chance(0.45) then
			local flower = if rng:chance(0.5) then C.FlowerPink else C.FlowerWhite
			Style.block(parent, CFrame.new(p + Vector3.new(0.2, 0.22, 0.1)), Vector3.new(0.5, 0.35, 0.5), flower, NEON, Style.tiny())
		end
	end
end

local function reeds(parent: Instance, at: Vector3, rng: Rng.Rng)
	for k = 1, 3 do
		local q = at + Vector3.new(k * 0.5 - 1, 0, rng:range(-0.4, 0.4))
		local h = rng:range(2, 3.4)
		Style.block(parent, CFrame.new(q + Vector3.new(0, h / 2, 0)), Vector3.new(0.22, h, 0.22), C.GrassDark, nil, Style.tiny())
		if k == 2 then
			Style.block(parent, CFrame.new(q + Vector3.new(0, h + 0.3, 0)), Vector3.new(0.4, 0.8, 0.4), C.TrunkDark, nil, Style.tiny())
		end
	end
end

local function pond(parent: Instance, center: Vector3, size: Vector2, lilyCount: number, rng: Rng.Rng): Model
	local m = Style.pond(parent, center, size.X, size.Y, rng)
	lilies(m, center, size.X, size.Y, lilyCount, rng)
	reeds(m, center + Vector3.new(size.X * 0.36, 0, size.Y * 0.32), rng)
	reeds(m, center + Vector3.new(-size.X * 0.34, 0, -size.Y * 0.3), rng)
	return m
end

-- A bamboo grove: `count` stalks with a few darker nodes and leaf sprays at the top.
function BridgeGarden.bamboo(parent: Instance, base: Vector3, count: number, rng: Rng.Rng): Model
	local m = Style.model("Bamboo", parent)
	for _ = 1, count do
		local p = base + Vector3.new(rng:range(-1.2, 1.2), 0, rng:range(-1.2, 1.2))
		local h = rng:range(9, 14)
		local w = rng:range(0.42, 0.55)
		local tilt = CFrame.Angles(rng:range(-0.05, 0.05), 0, rng:range(-0.05, 0.05))
		local foot = CFrame.new(p) * tilt
		local green = Style.vary(Color3.fromRGB(122, 178, 70), rng, 0.06)
		Style.block(m, foot * CFrame.new(0, h / 2, 0), Vector3.new(w, h, w), green, nil, Style.decor())
		for i = 1, 3 do
			Style.block(
				m,
				foot * CFrame.new(0, h * i / 4, 0),
				Vector3.new(w + 0.14, 0.16, w + 0.14),
				Color3.fromRGB(88, 132, 50),
				nil,
				Style.tiny()
			)
		end
		for i = 0, 2 do
			local a = i * 2.1 + rng:range(0, 0.6)
			local leaf = foot * CFrame.new(0, h - 0.4 - i * 0.6, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1)
			Style.block(
				m,
				leaf * CFrame.Angles(math.rad(-25), 0, 0),
				Vector3.new(0.6, 0.12, 2.2),
				Style.vary(C.LeafGreen, rng, 0.06),
				nil,
				Style.tiny()
			)
		end
	end
	return m
end

-- A post lantern on the path (`light`: a real PointLight on this one; the rest are neon only).
local function postLantern(parent: Instance, at: Vector3, look: Look, light: boolean)
	local m = Style.model("PathLantern", parent)
	if look.PostStone then
		Style.block(m, CFrame.new(at + Vector3.new(0, 0.3, 0)), Vector3.new(1.4, 0.6, 1.4), C.StoneDark)
		Style.block(m, CFrame.new(at + Vector3.new(0, 1.6, 0)), Vector3.new(0.8, 2.2, 0.8), look.Post)
	else
		Style.block(m, CFrame.new(at + Vector3.new(0, 1.5, 0)), Vector3.new(0.45, 3, 0.45), look.Beam)
	end
	local cap = at + Vector3.new(0, 3.1, 0)
	Style.block(m, CFrame.new(cap + Vector3.new(0, 0.75, 0)), Vector3.new(1.3, 0.25, 1.3), look.RoofDark, nil, Style.tiny())
	local glow = Style.block(m, CFrame.new(cap + Vector3.new(0, 0.2, 0)), Vector3.new(0.75, 0.85, 0.75), look.Lamp, NEON, Style.tiny())
	glow.Name = "LanternGlow"
	if light then
		Style.light(glow, look.Lamp, 14, 1.2)
	end
end

-- The roof: one gable along the bridge (ridge along Z), `span` across, plus an
-- optional upper tier and upturned eave tips.
local function roof(parent: Instance, center: CFrame, length: number, span: number, look: Look, rng: Rng.Rng)
	local m = Style.model("Roof", parent)
	local turn = center * CFrame.Angles(0, math.pi / 2, 0) -- gableRoof's ridge runs along its X: turn it along Z
	local height = span * 0.5
	local slab = Style.ghost()
	Style.gableRoof(m, turn, length, span, height, { Color = look.Roof, Dark = look.RoofDark, Trim = look.Trim })
	-- the thick eave band (massive look) and the ridge beam
	for _, side in { -1, 1 } do
		Style.block(
			m,
			center * CFrame.new(side * (span / 2 - 0.2), -look.RoofThick / 2, 0),
			Vector3.new(0.9, look.RoofThick, length + 0.4),
			look.RoofDark,
			nil,
			slab
		)
		Style.block(
			m,
			center * CFrame.new(side * (span / 2 + 0.2), -look.RoofThick + 0.1, 0),
			Vector3.new(0.3, 0.3, length + 0.6),
			look.Trim,
			nil,
			Style.tiny()
		)
	end
	Style.block(m, center * CFrame.new(0, height + 0.25, 0), Vector3.new(1, 0.6, length + 1.2), look.Trim, nil, Style.tiny())
	if look.Tiers >= 2 then
		local up = center * CFrame.new(0, height * 0.72, 0)
		Style.gableRoof(
			m,
			up * CFrame.Angles(0, math.pi / 2, 0),
			length * 0.62,
			span * 0.55,
			height * 0.6,
			{ Color = look.Roof, Dark = look.RoofDark, Trim = look.Trim }
		)
		Style.block(m, up * CFrame.new(0, height * 0.6 + 0.25, 0), Vector3.new(0.8, 0.5, length * 0.62 + 1), look.Trim, nil, Style.tiny())
	end
	if look.Upturn then
		-- the eave tips curl up at the four corners
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local tip = center * CFrame.new(sx * (span / 2 + 0.6), -0.2, sz * (length / 2 + 0.4))
				Geo.wedge(
					m,
					tip * CFrame.Angles(0, if sz > 0 then 0 else math.pi, 0),
					Vector3.new(1.4, 1.4, 1.8),
					look.RoofDark,
					Enum.Material.SmoothPlastic,
					Style.tiny()
				)
				Style.block(m, tip * CFrame.new(0, 0.9, 0), Vector3.new(0.4, 0.4, 0.4), look.Trim, NEON, Style.tiny())
			end
		end
	end
	if look.Name == "Forest" then
		-- moss lumps and a few ferns on the thatch
		for _ = 1, 8 do
			local x = rng:range(-span * 0.35, span * 0.35)
			local z = rng:range(-length * 0.45, length * 0.45)
			local y = height * (1 - math.abs(x) / (span / 2)) + 0.2
			Style.block(
				m,
				center * CFrame.new(x, y, z),
				Vector3.new(rng:range(1.4, 2.6), 0.6, rng:range(1.4, 2.6)),
				Style.vary(C.LeafGreenDark, rng, 0.06),
				nil,
				Style.tiny()
			)
		end
	end
	return m
end

-- The covered bridge over the big pond.
local function bridge(parent: Instance, look: Look, rng: Rng.Rng): Model
	local m = Style.model("CoveredBridge", parent)
	local from, to = BridgeGarden.BridgeFrom, BridgeGarden.BridgeTo
	local deck = Style.archBridge(m, from, to, BridgeGarden.BridgeWidth, BridgeGarden.Rise, rng)
	deck.Name = "Deck"
	local length = (to - from).Magnitude
	local roofY = BridgeGarden.Rise + 8.2
	local half = BridgeGarden.BridgeWidth / 2 + 0.4
	-- posts (4 pairs) up to the roof beams
	local ts = { 0.06, 0.36, 0.64, 0.94 }
	for _, t in ts do
		local z = from.Z + (to.Z - from.Z) * t
		local deckY = BridgeGarden.Rise * (1 - (2 * t - 1) ^ 2)
		for _, side in { -1, 1 } do
			local x = side * half
			local h = roofY - deckY
			local s = look.PostSize
			Style.block(m, CFrame.new(x, deckY + h / 2, z), Vector3.new(s, h, s), look.Post, nil, Style.decor())
			if look.PostStone then
				Style.block(m, CFrame.new(x, deckY + 0.5, z), Vector3.new(s + 0.5, 1, s + 0.5), C.StoneDark, nil, Style.decor())
				-- stone piers under the deck down into the pond
				Style.block(
					m,
					CFrame.new(x, deckY / 2 - 0.2, z),
					Vector3.new(s + 0.3, deckY + 0.6, s + 0.6),
					C.StoneDark,
					nil,
					Style.tiny()
				)
			end
			-- brackets under the beam
			Style.block(m, CFrame.new(x - side * 0.5, roofY - 0.9, z), Vector3.new(1.2, 0.4, s * 0.8), look.Beam, nil, Style.tiny())
		end
	end
	-- the two long beams and the cross ties carrying the roof
	for _, side in { -1, 1 } do
		Style.block(
			m,
			CFrame.new(side * half, roofY - 0.3, (from.Z + to.Z) / 2),
			Vector3.new(0.9, 0.7, length + 1.6),
			look.Beam,
			nil,
			Style.ghost()
		)
	end
	for _, t in ts do
		local z = from.Z + (to.Z - from.Z) * t
		Style.block(m, CFrame.new(0, roofY - 0.3, z), Vector3.new(half * 2 + 0.9, 0.5, 0.5), look.Beam, nil, Style.tiny())
	end
	-- the massive roof
	local center = CFrame.new(0, roofY + look.RoofThick * 0.5, (from.Z + to.Z) / 2)
	local span = BridgeGarden.BridgeWidth + 10
	roof(m, center, length + 7, span, look, rng)
	-- string lights along both eaves
	local bulbZ = from.Z + 2.5
	while bulbZ > to.Z - 3 do
		for _, side in { -1, 1 } do
			Style.block(
				m,
				CFrame.new(side * (span / 2 + 0.25), roofY - look.RoofThick * 0.4, bulbZ),
				Vector3.new(0.35, 0.35, 0.35),
				look.Lamp,
				NEON,
				Style.tiny()
			)
		end
		bulbZ -= 2.4
	end
	-- lanterns hanging from the eave beams, 3 per side
	for i = 1, 3 do
		local t = i / 4
		local z = from.Z + (to.Z - from.Z) * t
		for _, side in { -1, 1 } do
			local at = Vector3.new(side * (half + 0.1), roofY - 1.8, z)
			Style.block(m, CFrame.new(at + Vector3.new(0, 0.8, 0)), Vector3.new(0.12, 0.9, 0.12), C.Iron, nil, Style.tiny())
			local g = Style.block(m, CFrame.new(at), Vector3.new(0.8, 1.1, 0.8), look.Lamp, NEON, Style.tiny())
			g.Name = "LanternGlow"
			Style.block(m, CFrame.new(at + Vector3.new(0, 0.62, 0)), Vector3.new(1, 0.16, 1), look.RoofDark, nil, Style.tiny())
			if i == 2 then
				Style.light(g, look.Lamp, 16, 1.3)
			end
		end
	end
	-- a name board over the plaza end
	local board = Style.block(m, CFrame.new(0, roofY - 1.6, from.Z + 0.6), Vector3.new(6, 1.5, 0.3), look.Beam, nil, Style.tiny())
	Style.sign(m, CFrame.new(0, roofY - 1.6, from.Z + 0.8) * CFrame.Angles(0, math.pi, 0), "TO THE DEPTHS", 5.4, 1.2, { Kind = "Wood" })
	board.Name = "BridgeBoard"
	return m
end

-- The flagstone path: big slabs in two shades with a dark border, from the bridge to the quarry ramp.
local function path(parent: Instance, look: Look, rng: Rng.Rng, z0: number, z1: number): Model
	local m = Style.model("StonePath", parent)
	local w = BridgeGarden.PathWidth
	Style.block(m, CFrame.new(0, 0.08, (z0 + z1) / 2), Vector3.new(w + 1.2, 0.16, z0 - z1), look.SlabDark, nil, Style.solid())
	local z = z0
	local row = 0
	while z > z1 + 0.5 do
		local len = rng:range(1.8, 2.6)
		row += 1
		local split = if row % 2 == 0 then rng:range(-0.8, 0.8) else 0
		for _, side in { -1, 1 } do
			local x0 = if side < 0 then -w / 2 + 0.25 else split + 0.12
			local x1 = if side < 0 then split - 0.12 else w / 2 - 0.25
			if split == 0 and side > 0 then
				break
			end
			local width = if split == 0 then w - 0.5 else x1 - x0
			local cx = if split == 0 then 0 else (x0 + x1) / 2
			local shade = if rng:chance(0.5) then look.Slab else Style.vary(look.Slab, rng, 0.06)
			Style.block(m, CFrame.new(cx, 0.22, z - len / 2), Vector3.new(width, 0.2, len - 0.24), shade, nil, Style.tiny())
		end
		z -= len
	end
	-- the landing off the plaza: three wide steps
	if z0 < -40 then
		return m
	end
	for i = 0, 2 do
		Style.block(
			m,
			CFrame.new(0, 0.12 + i * 0.12, -38.6 - i * 1.4),
			Vector3.new(13 - i * 1.6, 0.24 + i * 0.24, 1.4),
			Style.vary(look.SlabDark, rng, 0.04),
			nil,
			Style.solid()
		)
	end
	return m
end

-- The passage under THE GREAT FORGE's roof (GreatForge.Passage): no roof of
-- its own; the pond, the bridge and the hanging lanterns sit under the forge.
BridgeGarden.Passage = {
	Forecourt = { -38, -54 }, -- the stone forecourt off the plaza, under the board
	BridgeFrom = Vector3.new(0, 0, -54),
	BridgeTo = Vector3.new(0, 0, -85),
	Pond = { Center = Vector3.new(0, 0, -69.5), Size = Vector2.new(34, 26) },
	BeamY = 18, -- just under the forge's nave beams (GreatForge LINTEL_TOP 18.9)
	LanternZ = { -60, -69.5, -79 },
	SidePonds = {
		{ Center = Vector3.new(-14.5, 0, -98), Size = Vector2.new(10, 12) },
		{ Center = Vector3.new(14.5, 0, -98), Size = Vector2.new(10, 12) },
	},
	BambooZ = { -90, -105 },
	LampZ = { -88, -95, -102, -109 },
	Jungle = { { X = 17.5, Z = -90, H = 12, R = 4.4, Pink = true }, { X = 17, Z = -107, H = 15, R = 5.2, Pink = false } },
	-- (owner 2026-10-20: "stone statues on the free lawn in front, the stone kings again")
	-- two small stone kings guard the forecourt's steps, facing the plaza, blasters outward
	Kings = { X = 8.8, Z = -44.5, Scale = 0.42 },
	FenceX = 21.3, -- along the forge roads (x +-21.5 .. 30.5), behind the roof
	FenceZ = { -87, -111 },
	Crystals = {
		{ X = -9, Z = -59, Size = 4.3, Color = "Cyan" },
		{ X = 9.5, Z = -79, Size = 4.6, Color = "Purple" },
		{ X = -10, Z = -80, Size = 3.5, Color = "Pink" },
		{ X = 8.8, Z = -97.5, Size = 3.2, Color = "Cyan" },
		{ X = -8.8, Z = -98.5, Size = 3.5, Color = "Purple" },
		{ X = 9.5, Z = -110, Size = 4.9, Color = "Amber" },
		{ X = -9.5, Z = -109.5, Size = 4.3, Color = "Pink" },
	},
}

local CRYSTAL = {
	Cyan = C.CrystalCyan,
	Purple = C.CrystalPurple,
	Pink = C.CrystalPink,
	Amber = C.Fire,
}

local function hanging(parent: Instance, at: Vector3, top: number, look: Look, light: boolean)
	Style.block(parent, CFrame.new(at.X, (top + at.Y) / 2 + 0.5, at.Z), Vector3.new(0.14, top - at.Y - 1, 0.14), C.Iron, nil, Style.tiny())
	Style.block(parent, CFrame.new(at + Vector3.new(0, 0.75, 0)), Vector3.new(1.2, 0.2, 1.2), look.RoofDark, nil, Style.tiny())
	local g = Style.block(parent, CFrame.new(at), Vector3.new(0.95, 1.3, 0.95), look.Lamp, NEON, Style.tiny())
	g.Name = "LanternGlow"
	Style.block(parent, CFrame.new(at - Vector3.new(0, 0.75, 0)), Vector3.new(0.6, 0.2, 0.6), look.RoofDark, nil, Style.tiny())
	if light then
		Style.light(g, look.Lamp, 16, 1.3)
	end
end

local function finish(m: Model)
	-- water and leaves are decoration; the deck, the steps and the path stay walkable
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency > 0 then
			d.CanCollide = false
		end
	end
end

local function passage(m: Model, look: Look, rng: Rng.Rng)
	local P = BridgeGarden.Passage
	pond(m, P.Pond.Center, P.Pond.Size, 12, rng)
	for _, q in { Vector3.new(-11, 0, -62), Vector3.new(-9, 0, -76), Vector3.new(10, 0, -63), Vector3.new(12, 0, -75) } do
		Style.block(m, CFrame.new(q + Vector3.new(0, 0.62, 0)), Vector3.new(1.1, 0.2, 1.1), C.WoodDark, nil, Style.tiny())
		Style.block(m, CFrame.new(q + Vector3.new(0, 1.05, 0)), Vector3.new(0.7, 0.7, 0.7), look.Lamp, NEON, Style.tiny())
	end
	local deck = Style.archBridge(m, P.BridgeFrom, P.BridgeTo, BridgeGarden.BridgeWidth, 1.6, rng)
	deck.Name = "Deck"
	-- the forecourt and the path on to the quarry ramp
	path(m, look, rng, P.Forecourt[1], P.Forecourt[2])
	path(m, look, rng, P.BridgeTo.Z - 0.5, BridgeGarden.PathEnd)
	-- lanterns hanging from cross beams under the forge's roof, both sides of the deck
	for i, z in P.LanternZ do
		Style.block(m, CFrame.new(0, P.BeamY, z), Vector3.new(18.5, 0.6, 0.6), look.Beam, nil, Style.tiny())
		for _, side in { -1, 1 } do
			hanging(m, Vector3.new(side * 5.2, 11.5, z), P.BeamY, look, i == 2)
		end
	end
	for _, p in P.SidePonds do
		pond(m, p.Center, p.Size, 4, rng)
	end
	for _, side in { -1, 1 } do
		for _, z in P.BambooZ do
			BridgeGarden.bamboo(m, Vector3.new(side * 6.6, 0, z), 4, rng)
		end
		for i, z in P.LampZ do
			postLantern(m, Vector3.new(side * 4.2, 0, z), look, i == 2)
		end
		for _, t in P.Jungle do
			Meadow.jungleTree(m, Vector3.new(side * t.X, 0, t.Z), t.H, t.R, rng, if t.Pink then Style.TreeKinds.Pink else nil)
		end
		-- a timber fence with lantern posts along the forge road, behind the roof
		local x = side * P.FenceX
		Style.fence(m, Vector3.new(x, 0, P.FenceZ[1]), Vector3.new(x, 0, P.FenceZ[2]), { Height = 2.4, PostEvery = 4, Caps = true })
		local z = P.FenceZ[1]
		while z >= P.FenceZ[2] - 0.1 do
			Style.block(m, CFrame.new(x, 2.95, z), Vector3.new(0.85, 1, 0.85), look.Lamp, NEON, Style.tiny()).Name = "LanternGlow"
			Style.block(m, CFrame.new(x, 3.55, z), Vector3.new(1.1, 0.22, 1.1), C.Iron, nil, Style.tiny())
			z -= 8
		end
		-- stone abutments at both ends of the bridge
		for _, bz in { P.BridgeFrom.Z, P.BridgeTo.Z } do
			Style.block(
				m,
				CFrame.new(side * (BridgeGarden.BridgeWidth / 2 + 0.9), 0.9, bz),
				Vector3.new(1.8, 1.8, 2.4),
				Style.vary(C.StoneDark, rng, 0.04),
				nil,
				Style.decor()
			)
			Style.block(
				m,
				CFrame.new(side * (BridgeGarden.BridgeWidth / 2 + 0.9), 1.95, bz),
				Vector3.new(2.2, 0.3, 2.8),
				Style.vary(C.Stone, rng, 0.04),
				nil,
				Style.tiny()
			)
		end
	end
	-- stone piers under the deck in the pond
	for _, t in { 0.33, 0.67 } do
		local pz = P.BridgeFrom.Z + (P.BridgeTo.Z - P.BridgeFrom.Z) * t
		Style.block(
			m,
			CFrame.new(0, 0.7, pz),
			Vector3.new(BridgeGarden.BridgeWidth - 1, 1.4, 1.6),
			Style.vary(C.StoneDark, rng, 0.04),
			nil,
			Style.tiny()
		)
	end
	for _, side in { -1, 1 } do
		local king = VaultStatue.buildScaled(
			m,
			CFrame.new(side * P.Kings.X, 0, P.Kings.Z),
			side,
			if side < 0 then "ForgeKingWest" else "ForgeKingEast",
			P.Kings.Scale
		)
		king:SetAttribute("Guardian", true)
	end
	for _, c in P.Crystals do
		Style.crystalCluster(m, CFrame.new(c.X, 0, c.Z), c.Size, CRYSTAL[c.Color] or C.CrystalPurple, rng, { Count = 3 })
	end
	BridgeGarden.lawn(m, rng)
end

-- The garden's own lawn behind the roof: grass tufts, lusher patches, little
-- flower beds and mossy rocks, off the path, the ponds, the bamboo and the trees.
BridgeGarden.LawnArea = { MinX = -20.4, MaxX = 20.4, MinZ = -111, MaxZ = -87 }
function BridgeGarden.lawnFree(p: Vector3, r: number): boolean
	local P = BridgeGarden.Passage
	if math.abs(p.X) < 5.2 + r then
		return false -- the path and its lanterns
	end
	for _, pond in P.SidePonds do
		if math.abs(p.X - pond.Center.X) < pond.Size.X / 2 + r and math.abs(p.Z - pond.Center.Z) < pond.Size.Y / 2 + r then
			return false
		end
	end
	for _, z in P.BambooZ do
		if math.abs(math.abs(p.X) - 6.6) < 2 + r and math.abs(p.Z - z) < 2 + r then
			return false
		end
	end
	for _, t in P.Jungle do
		if math.abs(math.abs(p.X) - t.X) < 2.6 + r and math.abs(p.Z - t.Z) < 2.6 + r then
			return false
		end
	end
	for _, c in P.Crystals do
		if math.abs(p.X - c.X) < c.Size * 0.4 + r and math.abs(p.Z - c.Z) < c.Size * 0.4 + r then
			return false
		end
	end
	return true
end

function BridgeGarden.lawn(parent: Instance, rng: Rng.Rng)
	local m = Style.model("GardenLawn", parent)
	local a = BridgeGarden.LawnArea
	local function spot(r: number): Vector3?
		for _ = 1, 20 do
			local p = Vector3.new(rng:range(a.MinX, a.MaxX), 0, rng:range(a.MinZ, a.MaxZ))
			if BridgeGarden.lawnFree(p, r) then
				return p
			end
		end
		return nil
	end
	-- lusher grass patches (flat, two greens)
	for i = 1, 12 do
		local p = spot(1.5)
		if p then
			local green = if i % 2 == 0 then C.GrassLight else C.LeafGreen
			Style.block(
				m,
				CFrame.new(p + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, rng:range(0, 1.5), 0),
				Vector3.new(rng:range(2.4, 4), 0.1, rng:range(2, 3.4)),
				Style.vary(green, rng, 0.04),
				nil,
				Style.tiny()
			)
		end
	end
	-- grass tufts: three blades
	for _ = 1, 26 do
		local p = spot(0.5)
		if p then
			for k = -1, 1 do
				local h = rng:range(0.7, 1.3)
				Style.block(
					m,
					CFrame.new(p + Vector3.new(k * 0.25, h / 2, rng:range(-0.2, 0.2))) * CFrame.Angles(0, 0, k * 0.25),
					Vector3.new(0.18, h, 0.18),
					Style.vary(C.GrassDark, rng, 0.06),
					nil,
					Style.tiny()
				)
			end
		end
	end
	-- flower beds: four blooms on a dark soil pad
	local blooms = { C.FlowerPink, C.FlowerYellow, C.FlowerWhite, C.FlowerPurple }
	for i = 1, 6 do
		local p = spot(1.3)
		if p then
			Style.block(m, CFrame.new(p + Vector3.new(0, 0.1, 0)), Vector3.new(2.2, 0.2, 2.2), C.DirtDark, nil, Style.tiny())
			for k = 1, 4 do
				local q = p + Vector3.new(rng:range(-0.8, 0.8), 0.45, rng:range(-0.8, 0.8))
				Style.block(m, CFrame.new(q), Vector3.new(0.45, 0.45, 0.45), blooms[(i + k) % #blooms + 1], nil, Style.tiny())
			end
		end
	end
	-- mossy rocks
	for _ = 1, 6 do
		local p = spot(1.2)
		if p then
			local size = rng:range(1.2, 2)
			Style.block(
				m,
				CFrame.new(p + Vector3.new(0, size * 0.35, 0)) * CFrame.Angles(0, rng:range(0, 1.5), 0),
				Vector3.new(size, size * 0.7, size * 0.9),
				Style.vary(C.Stone, rng, 0.05),
				nil,
				Style.tiny()
			)
			Style.block(
				m,
				CFrame.new(p + Vector3.new(0, size * 0.72, 0)),
				Vector3.new(size * 0.8, 0.16, size * 0.7),
				Style.vary(C.LeafGreenDark, rng, 0.05),
				nil,
				Style.tiny()
			)
		end
	end
end

function BridgeGarden.build(parent: Instance, rng: Rng.Rng, styleId: string?, layout: string?): Model
	local look = BridgeGarden.Styles[styleId or "A"] or BridgeGarden.Styles.A
	local m = Style.model("BridgeGarden", parent)
	if layout == "Passage" then
		passage(m, look, rng)
		finish(m)
		return m
	end
	pond(m, BridgeGarden.Pond.Center, BridgeGarden.Pond.Size, 12, rng)
	-- floating lanterns on the big pond
	for _, q in { Vector3.new(-12, 0, -52), Vector3.new(-8, 0, -60), Vector3.new(10, 0, -51), Vector3.new(13, 0, -59) } do
		Style.block(m, CFrame.new(q + Vector3.new(0, 0.62, 0)), Vector3.new(1.1, 0.2, 1.1), C.WoodDark, nil, Style.tiny())
		Style.block(m, CFrame.new(q + Vector3.new(0, 1.05, 0)), Vector3.new(0.7, 0.7, 0.7), look.Lamp, NEON, Style.tiny())
	end
	bridge(m, look, rng)
	path(m, look, rng, BridgeGarden.BridgeTo.Z - 0.5, BridgeGarden.PathEnd)
	for _, p in BridgeGarden.SidePonds do
		pond(m, p.Center, p.Size, 5, rng)
	end
	for _, side in { -1, 1 } do
		for _, z in { -73, -81, -97, -105 } do
			BridgeGarden.bamboo(m, Vector3.new(side * 6.6, 0, z), 4, rng)
		end
		for i, z in { -70, -77.5, -85, -92.5, -100, -107.5 } do
			postLantern(m, Vector3.new(side * 4.2, 0, z), look, i == 2 or i == 5)
		end
		Style.tree(m, CFrame.new(side * 19, 0, -72), look.Trees[1], rng, 1.2)
		Style.tree(m, CFrame.new(side * 19.5, 0, -106), look.Trees[2], rng, 1.15)
		postLantern(m, Vector3.new(side * 8.5, 0, -44.5), look, false)
	end
	finish(m)
	return m
end

return BridgeGarden
