--[[
	The Backdrop pieces inside the town (LOBBY_PLAN 6.2 items 10-12):
	NWCliff + NWPool (dark voxel cliff left of the forge with a waterfall,
	trees, ivy and purple crystals), MineEntrance (rock hill with a timber
	portal, MINE sign, dark mouth `MineMouth`, lanterns) and MineYard (rails
	with two gold carts, buffer stop, gold pile, wheelbarrow, lantern post).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C
local NEON = Enum.Material.Neon

local Lowlands = {}

local SOUTH = Vector3.new(0, 0, 1)
local EAST = Vector3.new(1, 0, 0)

-- Mine mouth (recess in the hill's east face) and its portal.
Lowlands.Mouth = { X0 = -42, X1 = -38, Z0 = 84, Z1 = 92, Top = 8 }

function Lowlands.buildNWCliff(parent: Instance, rng: Rng.Rng)
	local m, piece = Kit.piece(parent, "NWCliff")
	local cx, cz = piece.Center.X, piece.Center.Z
	local x0 = cx - piece.Size.X / 2
	local back = cz - piece.Size.Z / 2
	local w = piece.Size.X / 5
	-- { top, front z offset, step top (0 = none) }
	local cols = { { 14, -1, 6 }, { 20, 0, 0 }, { 17, -0.5, 0 }, { 22, 0, 0 }, { 15, -1.5, 8 } }
	local tops: { Vector3 } = {}
	for i, col in cols do
		local a, b = x0 + (i - 1) * w, x0 + i * w
		local front = cz + piece.Size.Z / 2 + col[2]
		Kit.column(
			m,
			a,
			back,
			b,
			front,
			-0.5,
			col[1],
			rng,
			{ Color = if i % 2 == 0 then C.StoneDark else C.StoneDeep, Front = SOUTH, Accents = 2 }
		)
		table.insert(tops, Vector3.new((a + b) / 2, col[1] + 0.8, (back + front) / 2))
		if col[3] > 0 then
			Kit.column(m, a + 0.6, front - 1, b - 0.6, front + 3, -0.5, col[3], rng, { Color = C.StoneDark, Front = SOUTH, Accents = 1 })
			-- purple crystals on the step; the right one is lit
			Style.crystalCluster(m, CFrame.new((a + b) / 2, col[3] + 0.8, front + 1), if i == 1 then 6 else 7, C.CrystalPurple, rng, {
				Count = 3,
				Light = i == 5,
				Range = 16,
			})
		end
		-- ivy cubes hanging over the front edge
		if i ~= 3 then
			for k = 1, 2 do
				local s = rng:range(1.1, 1.7)
				local x = rng:range(a + 1, b - 1)
				Style.block(
					m,
					CFrame.new(x, col[1] - (k - 1) * s * 1.1 - 0.4, front + 0.35),
					Vector3.new(s, s * 1.1, 0.7),
					Style.vary(C.LeafGreenDark, rng, 0.06),
					nil,
					Style.tiny()
				)
			end
		end
	end
	Style.tree(m, CFrame.new(tops[2] + Vector3.new(-0.5, 0, -1)), "Green", rng, 1.0)
	Style.tree(m, CFrame.new(tops[4] + Vector3.new(0.5, 0, -1.5)), "Orange", rng, 0.95)
	-- the waterfall from the middle column into the pool
	local fallX = cx
	local lipY = cols[3][1] + 0.6
	local front = cz + piece.Size.Z / 2 + cols[3][2] + 0.4
	Style.waterfall(m, CFrame.lookAt(Vector3.new(fallX, lipY, front), Vector3.new(fallX, lipY, front + 1)), lipY - 0.3, 5, rng)
end

function Lowlands.buildNWPool(parent: Instance, rng: Rng.Rng)
	local m, piece = Kit.piece(parent, "NWPool")
	Style.pond(m, piece.Center, piece.Size.X, piece.Size.Z, rng, { LilyPads = 2, RimColor = C.StoneDark })
end

function Lowlands.buildMineEntrance(parent: Instance, rng: Rng.Rng)
	local m = Kit.piece(parent, "MineEntrance")
	local mouth = Lowlands.Mouth
	local function col(x0: number, z0: number, x1: number, z1: number, bottom: number, top: number, accents: number)
		Kit.column(m, x0, z0, x1, z1, bottom, top, rng, {
			Color = if rng:chance(0.5) then C.StoneDark else C.StoneDeep,
			Front = if accents > 0 then EAST else nil,
			Accents = accents,
		})
	end
	-- rock hill around the mouth (east face at x -38)
	col(-56, 75, -38.5, 80, -0.5, 12, 1)
	col(-56, 80, -39, mouth.Z0, -0.5, 16, 1)
	col(-56, mouth.Z0, mouth.X0, mouth.Z1, -0.5, 18, 0)
	col(mouth.X0 - 0.1, mouth.Z0, mouth.X1, mouth.Z1, mouth.Top, 15.5, 0)
	col(-56, mouth.Z1, -39, 96.5, -0.5, 15, 1)
	col(-56, 96.5, -44, 101, -0.5, 11, 0)
	col(-44, 96.5, -38.5, 101, -0.5, 5, 1)
	-- the dark mouth: back plate (future teleport), floor, a dim ember strip
	local back = Kit.box(
		m,
		Vector3.new(mouth.X0 - 0.3, 0, mouth.Z0),
		Vector3.new(mouth.X0 + 0.3, mouth.Top, mouth.Z1),
		C.StoneDeep,
		nil,
		Style.decor()
	)
	back.Name = "MineMouth"
	Kit.box(m, Vector3.new(mouth.X0, 0, mouth.Z0), Vector3.new(mouth.X1, 0.12, mouth.Z1), C.StoneDeep, nil, Style.tiny())
	Kit.box(
		m,
		Vector3.new(mouth.X0 + 0.3, 0.3, mouth.Z0 + 1),
		Vector3.new(mouth.X0 + 0.6, 1.1, mouth.Z1 - 1),
		C.Ember,
		NEON,
		Style.tiny({ Transparency = 0.35 })
	)
	-- timber portal: posts 1.4 x 10, lintel 12, braces
	local px0, px1 = -38, -36.6
	for _, z in { mouth.Z0 - 0.7, mouth.Z1 + 0.7 } do
		Kit.box(m, Vector3.new(px0, 0, z - 0.7), Vector3.new(px1, 10, z + 0.7), Style.vary(C.WoodDark, rng, 0.04), nil, Style.decor())
	end
	Kit.box(m, Vector3.new(px0 - 0.1, 10, 82), Vector3.new(px1 + 0.2, 11.4, 94), Style.vary(C.Wood, rng, 0.04), nil, Style.decor())
	for _, side in { -1, 1 } do
		local zPost = if side < 0 then mouth.Z0 - 0.7 else mouth.Z1 + 0.7
		Kit.beam(m, Vector3.new(-37.2, 7.4, zPost - side * 0.5), Vector3.new(-37.2, 10.2, zPost - side * 3.2), 0.55, C.WoodDark)
	end
	-- MINE sign with crossed pickaxes (the icon on the viewer's left = south)
	local signX = -37.0
	for _, z in { 84.5, 91.5 } do
		Kit.box(m, Vector3.new(signX - 0.6, 11.4, z - 0.3), Vector3.new(signX - 0.1, 13.4, z + 0.3), C.WoodDark, nil, Style.tiny())
	end
	Style.sign(m, Kit.facing(Vector3.new(signX, 15.2, 85.9), EAST), "MINE", 12, 4.2, { Kind = "Wood" })
	Style.sign(m, Kit.facing(Vector3.new(signX, 15.2, 94.2), EAST), "", 4.2, 4.2, { Kind = "Wood" })
	Style.icon(m, Kit.facing(Vector3.new(signX + 0.6, 15.2, 94.2), EAST), "CrossedPickaxes", 3.4, C.SignText)
	-- two hanging lanterns at the posts (one light)
	for i, z in { 82.4, 93.6 } do
		Kit.beam(m, Vector3.new(px1, 9.4, z), Vector3.new(px1 + 1.4, 9.4, z), 0.3, C.Iron)
		Style.lantern(m, CFrame.new(px1 + 1.3, 9.4, z), { Kind = "Hanging", Light = i == 1, Range = 16, Brightness = 1.4 })
	end
	-- tools and crates
	Kit.beam(m, Vector3.new(-35.6, 0, 81.2), Vector3.new(-36.4, 4.6, 81.6), 0.35, C.Wood)
	Kit.beam(m, Vector3.new(-37.2, 4.4, 80.6), Vector3.new(-35.6, 4.8, 82.6), 0.45, C.IronLight)
	Style.crate(m, CFrame.new(-35.6, 0, 78.4), rng, 2.4)
	Style.crate(m, CFrame.new(-35.8, 2.4, 78.5), rng, 1.6)
	Style.barrel(m, Vector3.new(-35.4, 0, 97.6), rng)
	Style.tree(m, CFrame.new(-41.2, 5.8, 98.8), "Yellow", rng, 0.95)
end

function Lowlands.buildMineYard(parent: Instance, rng: Rng.Rng)
	local m = Kit.piece(parent, "MineYard")
	local z = 88
	local x0, x1 = -40.5, -8
	Style.rails(m, Vector3.new(x0, 0, z), Vector3.new(x1, 0, z), { SleeperEvery = 2.4 })
	for _, x in { -28.5, -18 } do
		Style.mineCart(m, Kit.facing(Vector3.new(x, 0, z), EAST), rng, { Load = "Gold" })
	end
	-- buffer stop
	for _, side in { -1, 1 } do
		Kit.box(m, Vector3.new(x1 - 0.2, 0, z + side * 1.3), Vector3.new(x1 + 0.8, 2.6, z + side * 2.1), C.WoodDark, nil, Style.decor())
	end
	Kit.box(m, Vector3.new(x1 + 0.8, 1.4, z - 2.4), Vector3.new(x1 + 1.3, 2.4, z + 2.4), C.Hazard, nil, Style.tiny())
	-- gold nugget pile
	local pile = Vector3.new(-11.5, 0, 92.6)
	for i = 1, 5 do
		local s = rng:range(0.9, 1.5)
		local q = pile + Vector3.new(rng:range(-1.2, 1.2), s * 0.4 + (if i > 3 then 0.8 else 0), rng:range(-0.9, 0.9))
		Style.block(
			m,
			CFrame.new(q) * Geo.randomTilt(rng, 0.5),
			Vector3.new(s, s * 0.8, s),
			Style.vary(C.Gold, rng, 0.05),
			if i <= 2 then NEON else nil,
			Style.tiny()
		)
	end
	-- wheelbarrow
	local wb = Kit.facing(Vector3.new(-14, 0, 83.4), Vector3.new(-1, 0, 0.3))
	Style.block(m, wb * CFrame.new(0, 1.5, 0), Vector3.new(2.2, 0.9, 2.8), C.Wood, nil, Style.decor())
	Geo.make(
		"Part",
		Style.tiny({
			Shape = Enum.PartType.Cylinder,
			CFrame = wb * CFrame.new(0, 0.6, -1.6),
			Size = Vector3.new(0.4, 1.2, 1.2),
			Color = C.StoneDeep,
			Material = Enum.Material.SmoothPlastic,
		}),
		m
	)
	for _, side in { -1, 1 } do
		Style.block(m, wb * CFrame.new(side * 0.8, 1.1, 2), Vector3.new(0.25, 0.25, 2.2), C.WoodDark, nil, Style.tiny())
		Style.block(m, wb * CFrame.new(side * 0.8, 0.5, 0.9), Vector3.new(0.25, 1, 0.25), C.WoodDark, nil, Style.tiny())
	end
	Style.lantern(m, Kit.facing(Vector3.new(-8.5, 0, 82.6), Vector3.new(0, 0, 1)), { Kind = "Post", Height = 6.5 })
end

function Lowlands.build(parent: Instance, rng: Rng.Rng)
	Lowlands.buildNWCliff(parent, rng)
	Lowlands.buildNWPool(parent, rng)
	Lowlands.buildMineEntrance(parent, rng)
	Lowlands.buildMineYard(parent, rng)
end

return Lowlands
