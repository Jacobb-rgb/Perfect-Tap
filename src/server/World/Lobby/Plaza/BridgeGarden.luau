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
	local z = from.Z + 2.5
	while z > to.Z - 3 do
		for _, side in { -1, 1 } do
			Style.block(
				m,
				CFrame.new(side * (span / 2 + 0.25), roofY - look.RoofThick * 0.4, z),
				Vector3.new(0.35, 0.35, 0.35),
				look.Lamp,
				NEON,
				Style.tiny()
			)
		end
		z -= 2.4
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
local function path(parent: Instance, look: Look, rng: Rng.Rng): Model
	local m = Style.model("StonePath", parent)
	local z0, z1 = BridgeGarden.BridgeTo.Z - 0.5, BridgeGarden.PathEnd
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

function BridgeGarden.build(parent: Instance, rng: Rng.Rng, styleId: string?): Model
	local look = BridgeGarden.Styles[styleId or "A"] or BridgeGarden.Styles.A
	local m = Style.model("BridgeGarden", parent)
	pond(m, BridgeGarden.Pond.Center, BridgeGarden.Pond.Size, 12, rng)
	-- floating lanterns on the big pond
	for _, q in { Vector3.new(-12, 0, -52), Vector3.new(-8, 0, -60), Vector3.new(10, 0, -51), Vector3.new(13, 0, -59) } do
		Style.block(m, CFrame.new(q + Vector3.new(0, 0.62, 0)), Vector3.new(1.1, 0.2, 1.1), C.WoodDark, nil, Style.tiny())
		Style.block(m, CFrame.new(q + Vector3.new(0, 1.05, 0)), Vector3.new(0.7, 0.7, 0.7), look.Lamp, NEON, Style.tiny())
	end
	bridge(m, look, rng)
	path(m, look, rng)
	for _, p in BridgeGarden.SidePonds do
		pond(m, p.Center, p.Size, 5, rng)
	end
	-- bamboo along the path (both sides, gaps for the lanterns)
	for _, side in { -1, 1 } do
		for _, z in { -73, -81, -97, -105 } do
			BridgeGarden.bamboo(m, Vector3.new(side * 6.6, 0, z), 4, rng)
		end
		-- lantern posts on both sides of the path
		for i, z in { -70, -77.5, -85, -92.5, -100, -107.5 } do
			postLantern(m, Vector3.new(side * 4.2, 0, z), look, i == 2 or i == 5)
		end
		-- big trees at the corners
		Style.tree(m, CFrame.new(side * 19, 0, -72), look.Trees[1], rng, 1.2)
		Style.tree(m, CFrame.new(side * 19.5, 0, -106), look.Trees[2], rng, 1.15)
		-- stone lanterns at the pond's plaza corners
		postLantern(m, Vector3.new(side * 8.5, 0, -44.5), look, false)
	end
	-- water and leaves are decoration; the deck, the steps and the path stay walkable
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency > 0 then
			d.CanCollide = false
		end
	end
	return m
end

return BridgeGarden
