--[[
	Sky package, floating islands (docs/plans/LOBBY_PLAN.md 6.1, items 7, 8):
	West (cottage, green + pink tree, short waterfall), East (trees,
	watchtower, long waterfall, blue crystals, two small islets) and the
	NEXT AREA island (tower house, stair-bridge down to the boardwalk). A
	piece's Center is the island's ground point (the top of its grass; the
	NEXT AREA island floats lower, see GROUND_Y); the rock hangs below it,
	buildings stand on it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

type Piece = LobbyLayout.Piece

local Islands = {}

-- Tree with only no-collide, shadowless parts (it floats far away).
local function tree(parent: Instance, frame: CFrame, at: Vector3, kind: string, rng: Rng.Rng, scale: number): Model
	local t = Style.tree(parent, frame * CFrame.new(at), kind, rng, scale)
	for _, d in t:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	return t
end

local function bush(parent: Instance, frame: CFrame, at: Vector3, color: Color3, rng: Rng.Rng, size: number)
	local b = Style.bush(parent, (frame * CFrame.new(at)).Position, color, rng, size)
	for _, d in b:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
end

-- Vines and grass tufts hanging over an island's edge (1 part each).
local function vines(parent: Instance, frame: CFrame, w: number, d: number, rng: Rng.Rng, count: number)
	for i = 1, count do
		local side = (i - 1) % 4
		local len = rng:range(3, 7)
		local at = if side == 0
			then Vector3.new(rng:range(-w * 0.4, w * 0.4), -1.5 - len / 2, -d / 2 - 0.3)
			elseif side == 1 then Vector3.new(w / 2 + 0.3, -1.5 - len / 2, rng:range(-d * 0.4, d * 0.4))
			elseif side == 2 then Vector3.new(-w / 2 - 0.3, -1.5 - len / 2, rng:range(-d * 0.4, d * 0.4))
			else Vector3.new(rng:range(-w * 0.4, w * 0.4), -1.5 - len / 2, d / 2 + 0.3)
		Kit.box(parent, frame, at, Vector3.new(rng:range(0.8, 1.4), len, rng:range(0.8, 1.4)), Style.vary(C.LeafGreenDark, rng, 0.06))
	end
end

---------------------------------------------------------------- west

--[[
	Cottage: stone walls on a plinth, a door, Lamp windows, a Wood gable
	roof and a chimney. `base` = bottom center of the walls, LookVector =
	the door side. About 27 parts.
]]
local function cottage(m: Model, base: CFrame, rng: Rng.Rng)
	local w, h, d = 9, 5.6, 7
	Style.block(m, base * CFrame.new(0, 0.4, 0), Vector3.new(w + 0.8, 0.8, d + 0.8), C.StoneDark, nil, Kit.far())
	Style.block(m, base * CFrame.new(0, 0.8 + h / 2, 0), Vector3.new(w, h, d), Style.vary(C.Stone, rng, 0.03), nil, Kit.far())
	-- corner stones (voxel accents)
	for _, c in { { -1, -1 }, { 1, -1 } } do
		Style.block(
			m,
			base * CFrame.new(c[1] * (w / 2), 0.8 + h / 2, c[2] * (d / 2)),
			Vector3.new(1.2, h, 1.2),
			C.StoneLight,
			nil,
			Kit.far()
		)
	end
	Style.block(m, base * CFrame.new(-1.8, 0.8 + 1.8, -d / 2 - 0.1), Vector3.new(1.8, 3.6, 0.3), C.WoodDark, nil, Kit.far())
	Kit.window(m, base * CFrame.new(1.9, 0.8 + 3, -d / 2 - 0.15), 1.5, 1.4)
	Kit.window(m, base * CFrame.new(w / 2 + 0.15, 0.8 + 3, 0) * CFrame.Angles(0, -math.pi / 2, 0), 1.4, 1.4)
	Kit.window(m, base * CFrame.new(-w / 2 - 0.15, 0.8 + 3, 0.6) * CFrame.Angles(0, math.pi / 2, 0), 1.2, 1.3)
	local roof = Style.gableRoof(m, base * CFrame.new(0, 0.8 + h, 0), w + 1.6, d + 1.8, 3.8, {
		Color = C.Wood,
		Dark = C.WoodDark,
		Trim = C.WoodDark,
	})
	for _, p in roof do
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
	end
	Style.block(m, base * CFrame.new(2.6, 0.8 + h + 3.4, 1.6), Vector3.new(1.4, 3.4, 1.4), C.StoneDark, nil, Kit.far())
	Style.block(m, base * CFrame.new(2.6, 0.8 + h + 5.25, 1.6), Vector3.new(1.7, 0.4, 1.7), C.StoneDeep, nil, Kit.far())
end

-- FloatingIslandWest: grass top at the piece center, cottage, a green and a
-- pink tree, a 30-stud waterfall off the front (south) edge ending in mist.
function Islands.west(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local frame = LobbyLayout.frame(piece)
	local w, d = 34, 28
	Kit.floatingIsland(m, frame, rng, { Width = w, Depth = d, Hang = 32, Tiers = 5 })
	vines(m, frame, w, d, rng, 6)
	cottage(m, frame * CFrame.new(-7, 0, 1), rng)
	tree(m, frame, Vector3.new(9, 0, 5), "Green", rng, 1.05)
	tree(m, frame, Vector3.new(7, 0, -6), "Pink", rng, 0.9)
	bush(m, frame, Vector3.new(-13, 0, -8), C.LeafGreen, rng, 2.6)
	bush(m, frame, Vector3.new(13, 0, -1), C.LeafPinkDark, rng, 2.2)
	for _, f in { { At = Vector3.new(-1, 0, -7), Color = C.FlowerYellow }, { At = Vector3.new(-12, 0, 8), Color = C.FlowerPink } } do
		for _, p in Style.flowers(m, (frame * CFrame.new(f.At)).Position, f.Color, rng, 4, 1.4) do
			p.CastShadow = false
		end
	end
	-- stream from the cottage to the edge, then the waterfall
	Kit.box(m, frame, Vector3.new(1.5, 0.12, -9.5), Vector3.new(2.4, 0.3, 9), C.Water, nil, Kit.far({ Transparency = 0.15 }))
	Kit.skyFall(m, frame * CFrame.new(1.5, -0.4, -d / 2 - 0.5), 30, 4.5, rng)
	-- a lantern by the door
	Kit.box(m, frame, Vector3.new(-12.2, 2, -5.2), Vector3.new(0.5, 4, 0.5), C.WoodDark)
	Kit.glow(m, frame * CFrame.new(-12.2, 4.4, -5.2), Vector3.new(0.9, 0.9, 0.9), C.LampAmber)
	Style.streaming(m, "Lod")
	return m
end

---------------------------------------------------------------- east

--[[
	Timber watchtower: four posts, X-braces, a plank platform, a small cabin
	with a lit window and a stepped roof. `base` = ground center, LookVector
	= the window side. About 14 parts.
]]
local function watchtower(m: Model, base: CFrame, rng: Rng.Rng)
	local h = 8
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Style.block(m, base * CFrame.new(c[1] * 2.2, h / 2, c[2] * 2.2), Vector3.new(0.8, h, 0.8), C.WoodDark, nil, Kit.far())
	end
	Kit.beam(m, (base * CFrame.new(-2.2, 0.6, -2.4)).Position, (base * CFrame.new(2.2, h - 0.8, -2.4)).Position, 0.4, C.Wood)
	Kit.beam(m, (base * CFrame.new(2.4, 0.6, -2.2)).Position, (base * CFrame.new(2.4, h - 0.8, 2.2)).Position, 0.4, C.Wood)
	Style.block(m, base * CFrame.new(0, h + 0.25, 0), Vector3.new(6.4, 0.5, 6.4), C.Plank, nil, Kit.far())
	Style.block(m, base * CFrame.new(0, h + 2.2, 0.4), Vector3.new(4.4, 3.4, 4), Style.vary(C.Wood, rng, 0.04), nil, Kit.far())
	Kit.window(m, base * CFrame.new(0, h + 2.4, -1.75), 1.6, 1.3)
	Style.block(m, base * CFrame.new(0, h + 4.2, 0.4), Vector3.new(5.6, 0.7, 5.2), C.WoodDark, nil, Kit.far())
	Style.block(m, base * CFrame.new(0, h + 5.0, 0.4), Vector3.new(3.6, 0.9, 3.2), C.WoodDark, nil, Kit.far())
	Style.block(m, base * CFrame.new(0, h + 6.2, 0.4), Vector3.new(0.25, 1.6, 0.25), C.WoodDark, nil, Kit.far())
	Style.block(m, base * CFrame.new(0, h + 6.6, 1.2), Vector3.new(0.15, 0.8, 1.4), C.AwningRed, nil, Kit.far())
end

-- FloatingIslandEast: bigger island with a green and an orange tree, a
-- watchtower, a 45-stud waterfall, blue crystals and two small islets.
function Islands.east(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local frame = LobbyLayout.frame(piece)
	local w, d = 32, 26
	local main = frame * CFrame.new(-3, 0, 2)
	Kit.floatingIsland(m, main, rng, { Width = w, Depth = d, Hang = 34, Tiers = 5 })
	vines(m, main, w, d, rng, 6)
	tree(m, main, Vector3.new(-8, 0, 5), "Green", rng, 1.2)
	tree(m, main, Vector3.new(-10, 0, -6), "Orange", rng, 1.0)
	watchtower(m, main * CFrame.new(8, 0, 4), rng)
	Style.crystalCluster(m, main * CFrame.new(2, 0, -8), 7, C.CrystalBlue, rng, { Count = 3 })
	bush(m, main, Vector3.new(11, 0, -6), C.LeafGreenLight, rng, 2.4)
	bush(m, main, Vector3.new(-1, 0, 9), C.LeafOrange, rng, 2.2)
	for _, p in Style.flowers(m, (main * CFrame.new(4, 0, -2)).Position, C.FlowerBlue, rng, 4, 1.6) do
		p.CastShadow = false
	end
	-- the long waterfall pours off the front edge into the mountains below
	Kit.box(m, main, Vector3.new(-3, 0.12, -9), Vector3.new(2.6, 0.3, 8), C.Water, nil, Kit.far({ Transparency = 0.15 }))
	Kit.skyFall(m, main * CFrame.new(-3, -0.4, -d / 2 - 0.5), 45, 5, rng)
	-- two small islets drifting beside it
	local isletA = frame * CFrame.new(15.5, -9, -11)
	Kit.floatingIsland(m, isletA, rng, { Width = 8, Depth = 7, Hang = 9, Tiers = 2 })
	tree(m, isletA, Vector3.new(0, 0, 0), "Yellow", rng, 0.55)
	local isletB = frame * CFrame.new(16.5, 7, 12)
	Kit.floatingIsland(m, isletB, rng, { Width = 6, Depth = 5, Hang = 7, Tiers = 2 })
	bush(m, isletB, Vector3.new(0, 0, 0), C.LeafGreen, rng, 2)
	Style.streaming(m, "Lod")
	return m
end

---------------------------------------------------------------- next island

--[[
	The island the NEXT AREA boardwalk points at: a tall tower house (stone
	base, two timber floors with Lamp windows, a steep plank roof, one
	PointLight), a tree, and a timber stair-bridge down to the end of Flora's
	boardwalk. The boardwalk ends in a landing at x 236..244, z ~-115 with
	its deck top at y 5.25 (art director note), so the island floats low
	(grass at GROUND_Y) and the bridge head sits flush with that landing.
	Piece frame: local -Z = west (toward the boardwalk), +X = north, so
	world z = -112 - local x and world x = 255 + local z.
]]
local GROUND_Y = 16 -- world height of the island's grass
local LANDING_TOP = 5.25 -- Flora's boardwalk landing deck top
local LANDING_EAST = 244.05 -- world x where the landing ends (the bridge head starts)
local LANDING_Z = -115

function Islands.nextIsland(parent: Instance, piece: Piece, rng: Rng.Rng): Model
	local m = Style.model(piece.Id, parent)
	local base = LobbyLayout.frame(piece) * CFrame.new(0, GROUND_Y - piece.Center.Y, 0)
	local w, d = 30, 17
	local main = base * CFrame.new(-2, 0, 10.5) -- spans world x 257..274
	Kit.floatingIsland(m, main, rng, { Width = w, Depth = d, Hang = 18, Tiers = 4 })
	vines(m, main, w, d, rng, 5)

	-- tower house, its door toward the bridge
	local house = main * CFrame.new(-5, 0, 1)
	local hw = 8
	Style.block(m, house * CFrame.new(0, 0.4, 0), Vector3.new(hw + 1, 0.8, hw + 1), C.StoneDark, nil, Kit.far())
	Style.block(m, house * CFrame.new(0, 3.6, 0), Vector3.new(hw, 5.6, hw), Style.vary(C.Stone, rng, 0.03), nil, Kit.far())
	Style.block(m, house * CFrame.new(1.4, 2.6, -hw / 2 - 0.1), Vector3.new(1.8, 3.6, 0.3), C.WoodDark, nil, Kit.far())
	local y = 6.4
	local lit: Part? = nil
	for floor = 1, 2 do
		local fw = hw + 0.6 * floor
		Style.block(m, house * CFrame.new(0, y + 0.3, 0), Vector3.new(fw + 0.6, 0.6, fw + 0.6), C.WoodDark, nil, Kit.far())
		Style.block(m, house * CFrame.new(0, y + 2.8, 0), Vector3.new(fw, 4.4, fw), Style.vary(C.WoodLight, rng, 0.04), nil, Kit.far())
		for _, c in { { -1, -1 }, { 1, -1 } } do
			Style.block(
				m,
				house * CFrame.new(c[1] * fw / 2, y + 2.8, c[2] * fw / 2),
				Vector3.new(0.8, 4.4, 0.8),
				C.WoodDark,
				nil,
				Kit.far()
			)
		end
		local pane = Kit.window(m, house * CFrame.new(-1.2, y + 3, -fw / 2 - 0.15), 1.6, 1.6)
		Kit.window(m, house * CFrame.new(-fw / 2 - 0.15, y + 3, 0) * CFrame.Angles(0, math.pi / 2, 0), 1.4, 1.5)
		if floor == 2 then
			lit = pane
		end
		y += 5
	end
	-- steep plank roof (pitch ~55 degrees) with a little finial
	local roof = Style.gableRoof(m, house * CFrame.new(0, y + 0.2, 0), hw + 2.6, hw + 2.6, 6, {
		Color = C.WoodDark,
		Dark = C.TrunkDark,
		Trim = C.RoofTrim,
	})
	for _, p in roof do
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
	end
	Style.block(m, house * CFrame.new(0, y + 7, 0), Vector3.new(0.3, 1.6, 0.3), C.WoodDark, nil, Kit.far())
	Style.block(m, house * CFrame.new(0, y + 7.4, 0.9), Vector3.new(0.15, 0.8, 1.6), C.AwningRed, nil, Kit.far())
	if lit then
		Style.light(lit, C.LampAmber, 16, 1.2)
	end

	tree(m, main, Vector3.new(8, 0, 3), "Yellow", rng, 0.9)
	bush(m, main, Vector3.new(11, 0, -5), C.LeafGreen, rng, 2.4)
	bush(m, main, Vector3.new(-12, 0, 5), C.LeafOrange, rng, 2)

	-- stair-bridge: a flat head flush with the landing, then treads up to the grass
	local x = -112 - LANDING_Z -- local x of the landing's center line
	local headFrom = LANDING_EAST - piece.Center.X
	local headTo = headFrom + 2
	local top = LANDING_TOP - GROUND_Y -- local height of the landing deck top
	local edge = 10.5 - d / 2 -- the island's west edge (local z)
	Kit.box(m, base, Vector3.new(x, top - 0.25, (headFrom + headTo) / 2), Vector3.new(4.6, 0.5, headTo - headFrom), C.Plank)
	local steps = 11
	local run, rise = (edge - headTo) / steps, -top / steps
	for i = 1, steps do
		Kit.box(
			m,
			base,
			Vector3.new(x, top + rise * i - 0.25, headTo + run * (i - 0.5)),
			Vector3.new(4.4, 0.5, run + 0.12),
			Style.vary(C.WoodLight, rng, 0.05)
		)
	end
	for _, side in { -1, 1 } do
		local a = (base * CFrame.new(x + side * 2.4, top - 0.6, headFrom + 0.2)).Position
		local b = (base * CFrame.new(x + side * 2.4, -0.6, edge + 0.4)).Position
		Kit.beam(m, a, b, 0.6, C.WoodDark)
		Kit.beam(m, a + Vector3.new(0, 3.4, 0), b + Vector3.new(0, 3.4, 0), 0.35, C.Wood)
		Kit.box(m, base, Vector3.new(x + side * 2.4, top + 1.4, headFrom + 0.3), Vector3.new(0.5, 3.4, 0.5), C.WoodDark)
	end
	-- lanterns at both ends of the bridge
	for _, at in { Vector3.new(x - 3.1, top, headFrom + 1), Vector3.new(x + 3.1, 0, edge + 1.5) } do
		Kit.box(m, base, at + Vector3.new(0, 1.75, 0), Vector3.new(0.5, 3.5, 0.5), C.WoodDark)
		Kit.glow(m, base * CFrame.new(at + Vector3.new(0, 3.9, 0)), Vector3.new(0.9, 0.9, 0.9), C.LampAmber)
	end
	Style.streaming(m, "Lod")
	return m
end

return Islands
