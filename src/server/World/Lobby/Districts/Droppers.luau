--[[
	The DROPPERS shop (owner 2026-10-23: a walk-in shop "bigger than a
	player, the droppers along the sides and the counter in the middle",
	"extremely good", its entrance to the plaza's crystal, wider, and at the
	end "in the modern tech style, so it fits our map"). It stands north-east
	of the plaza where the FOSSIL DIG was (the dig moved by the Tech shop),
	in the Districts' sci-fi look of SHOP and UPGRADES (Tech kit):
	  - a dark gunmetal floor slab with a blue neon front edge
	  - the front: light gunmetal window walls either side of a wide door
	    frame, big glass windows onto the showroom (orange frames), chunky
	    corner pillars with blue neon strips and orange bands
	  - the glowing DROPPERS sign box over the entrance
	  - dark side and back walls with the orange band
	  - (owner: "not a plain box") a round barrel roof of ribbed gunmetal
	    slats with a blue neon arc along its front edge, a gable plate under
	    the arc carrying the crystal logo (a glowing diamond frame with three
	    crystals in it), giant boulders round the house with glowing
	    crystals growing on them, vines down the roof edge, the pillars and
	    the boulders, warm uplights at the boulders' feet, and two big trees
	    at the back corners
	Inside, the server builds the solid shell only: the plinths of the six
	displays, the hero podium and the counter (the DropperCounter tag:
	ShopService's "Droppers" prompt opens the Tech shop, where the droppers
	and the Money Laser are machines). Every client builds the showroom
	itself while its camera is near (the house carries the
	DropperShopBuilder.Tag tag and its frame in the FrameAttribute
	attribute; DropperShopController): the real droppers, the DARK MATTER
	DROPPER on the podium, the Dropper Master, the floor, walls and lights.

	Frame: Kit.piece("DroppersHouse") (front = LookVector). The house is drawn
	in a frame turned to face +Z ("B"); fr() frames look to the front (the
	Tech kit's front = LookVector).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local DropperShopBuilder = require(Shared.Builders.DropperShopBuilder)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Droppers = {}

local C = Style.C
local NEON = Enum.Material.Neon

Droppers.CounterTag = "DropperCounter"

-- The round roof's rise; the grounds round the house (house frame, x / z,
-- studs): the boulders (size = rough width) and the trees behind (kept off
-- the east spur, the east plot road and the ore outcrops behind the house).
local ROOF_RISE = 6.5
local BOULDERS = {
	{ X = 18.6, Z = 2.6, Size = 6.8, Piece = "Left" },
	{ X = -18.2, Z = 1.8, Size = 5.6, Piece = "Right" },
	{ X = 20.2, Z = -5, Size = 7.4, Piece = "Left" },
	{ X = -18.6, Z = -5.6, Size = 5, Piece = "Right" },
	{ X = 16.8, Z = -16.2, Size = 4.4, Piece = "Left" },
}
local TREES = {
	{ X = 12.5, Z = -19, Scale = 1.15, Kind = "Green", Piece = "Back" },
	{ X = 20.5, Z = -13.2, Scale = 1.2, Kind = "Pink", Piece = "Left" },
}

function Droppers.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("DroppersHouse")
	local m = Style.model(piece.Id, parent)
	local TURN = CFrame.Angles(0, math.pi, 0)
	local B = cf * TURN -- local +Z = the house's front (the piece's LookVector)
	local function at(x: number, y: number, z: number): CFrame
		return B * CFrame.new(x, y, z)
	end
	-- a frame at (x, y, z) whose LookVector is the house's front (the Tech kit's front)
	local function fr(x: number, y: number, z: number): CFrame
		return at(x, y, z) * TURN
	end
	local function block(c: CFrame, size: Vector3, color: Color3, material: Enum.Material?, tiny: boolean?): Part
		return Style.block(m, c, size, color, material, if tiny then Style.tiny() else nil)
	end

	local ROOM = DropperShopBuilder.Room
	local W, D = ROOM.W, ROOM.D
	local z0 = ROOM.Front -- the front wall (local z)
	local zc = z0 - D / 2
	local plinth = ROOM.Plinth
	local wallH = ROOM.Wall -- the walls' height over the floor
	local top = plinth + wallH
	local doorW, doorH = ROOM.DoorW, ROOM.DoorH

	-- the floor slab and its blue neon front edge
	block(at(0, plinth / 2, zc), Vector3.new(W + 1, plinth, D + 1), Tech.MetalDark)
	Tech.glow(m, at(0, plinth - 0.2, z0 + 0.55), Vector3.new(W + 0.8, 0.18, 0.14), Tech.Neon)

	-- the front: window walls either side of the wide door frame
	local segW = (W - doorW) / 2
	for _, sx in { -1, 1 } do
		Tech.windowWall(m, fr(sx * (doorW + segW) / 2, plinth, z0), segW, wallH, 1.0, {
			Color = Tech.Metal,
			WindowWidth = ROOM.WindowW,
			WindowBottom = ROOM.WindowY - ROOM.WindowH / 2,
			WindowTop = ROOM.WindowY + ROOM.WindowH / 2,
			Frame = Tech.Band,
		})
	end
	Tech.doorFrame(m, fr(0, plinth, z0 - 0.05), doorW + 1.6, wallH, 1.2, {
		Color = Tech.MetalLight,
		OpeningWidth = doorW,
		OpeningHeight = doorH,
		Frame = Tech.Band,
		Neon = Tech.Neon,
	})
	-- chunky corner pillars at the front
	for _, sx in { -1, 1 } do
		Tech.pillar(m, fr(sx * (W / 2 - 0.4), plinth, z0 + 0.2), wallH + 1.2, 1.6)
	end

	-- the side and back walls with the orange band outside
	for _, sx in { -1, 1 } do
		block(at(sx * (W / 2 - 0.5), plinth + wallH / 2, zc - 0.5), Vector3.new(1, wallH, D - 1), Tech.MetalDark)
		block(at(sx * (W / 2 + 0.02), plinth + wallH * 0.62, zc - 0.5), Vector3.new(0.1, 0.9, D - 1), Tech.Band, nil, true)
	end
	block(at(0, plinth + wallH / 2, z0 - D + 0.5), Vector3.new(W - 2, wallH, 1), Tech.MetalDark)
	block(at(0, plinth + wallH * 0.62, z0 - D - 0.02), Vector3.new(W - 2, 0.9, 0.1), Tech.Band, nil, true)

	-- the roof slab, a blue neon edge tube along the back
	block(at(0, top + 0.3, zc), Vector3.new(W + 0.6, 0.6, D + 0.6), Tech.MetalDeep)
	Tech.channel(m, at(0, top + 0.3, z0 - D - 0.06), W + 0.4, Tech.EDGE)

	-- the round barrel roof: ribbed slats on an arc across the house, a blue
	-- neon arc along the front edge
	local spring = top + 0.6
	local chord, rise = W + 0.6, ROOF_RISE
	local radius = (chord * chord / 4 + rise * rise) / (2 * rise)
	local half = math.asin(chord / 2 / radius)
	local slats = 10
	local step = 2 * half / slats
	local slatW = 2 * radius * math.sin(step / 2) + 0.12
	local roofD = D + 0.6
	local frontZ = zc + roofD / 2
	for k = 0, slats - 1 do
		local a = -half + (k + 0.5) * step
		local c = at(radius * math.sin(a), spring + radius * math.cos(a) - (radius - rise), zc) * CFrame.Angles(0, 0, -a)
		block(c, Vector3.new(slatW, 0.5, roofD), if k % 2 == 0 then Tech.Metal else Tech.MetalDark)
		Tech.glow(m, c * CFrame.new(0, 0.1, roofD / 2 + 0.02), Vector3.new(slatW - 0.05, 0.22, 0.12), Tech.Tube)
	end
	-- the gable plate under the arc's front (three steps) and the crystal logo on it
	for k, f in { 0.92, 0.66, 0.36 } do
		local h = rise * 0.34
		block(at(0, spring + (k - 0.5) * h, z0 + 0.15), Vector3.new(chord * f, h, 0.5), Tech.MetalDark)
	end
	local logo = fr(0, spring + rise * 0.55, z0 + 0.5)
	block(logo * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(2.8, 2.8, 0.3), Tech.MetalDeep)
	-- (a diamond: four neon bars round the plate, each across its edge's midpoint)
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		Tech.glow(
			m,
			logo * CFrame.new(math.cos(a) * 1.45, math.sin(a) * 1.45, -0.2) * CFrame.Angles(0, 0, a + math.pi / 2),
			Vector3.new(3.0, 0.22, 0.1),
			Tech.Tube
		)
	end
	for _, cdef in
		{
			{ X = 0, H = 2.4, Wd = 0.62, Color = C.CrystalPurple, Tilt = 0 },
			{ X = -0.55, H = 1.6, Wd = 0.5, Color = C.CrystalBlue, Tilt = 0.35 },
			{ X = 0.55, H = 1.6, Wd = 0.5, Color = C.CrystalPink, Tilt = -0.35 },
		}
	do
		Style.crystal(m, logo * CFrame.new(cdef.X, -1.25, -0.35) * CFrame.Angles(0, 0, cdef.Tilt), cdef.H, cdef.Wd, cdef.Color, nil, 0.15)
	end
	-- the sign box over the entrance
	Tech.sign(m, fr(0, plinth + wallH - 1.55, z0 + 0.75), "DROPPERS", 14, 2.4, {
		Casing = false,
		Studs = false,
	})

	-- vines down the roof's front edge and the corner pillars
	local function vine(x: number, y: number, z: number, length: number, seed: number)
		local segs = 3
		local seg = length / segs
		for i = 0, segs - 1 do
			local sway = math.sin(seed + i * 1.7) * 0.25
			block(at(x + sway, y - seg * (i + 0.5), z), Vector3.new(0.22, seg + 0.1, 0.22), C.LeafGreenDark, nil, true)
		end
		block(at(x - 0.25, y - length * 0.35, z + 0.12), Vector3.new(0.7, 0.45, 0.25), C.LeafGreen, nil, true)
		block(at(x + 0.3, y - length * 0.75, z + 0.12), Vector3.new(0.6, 0.4, 0.25), C.LeafGreenLight, nil, true)
	end
	local function arcY(x: number): number
		return spring + math.sqrt(radius * radius - x * x) - (radius - rise)
	end
	for k, x in { -11.5, -4.5, 6, 12.5 } do
		vine(x, arcY(x) - 0.1, frontZ + 0.2, 2.6 + (k % 2) * 1.4, k * 2.3)
	end
	for _, sx in { -1, 1 } do
		vine(sx * (W / 2 - 0.4), top + 1.1, z0 + 1.15, 5.5, sx * 3.1)
	end

	-- the grounds (their own pieces: DroppersGroundsLeft / Back / Right, kept
	-- off the east plot road's lamps): giant boulders round the house with
	-- glowing crystals on three and warm uplights at their feet turned to
	-- the house, two big trees behind it
	local grounds: { [string]: Model } = {}
	for _, side in { "Left", "Back", "Right" } do
		grounds[side] = Style.model("DroppersGrounds" .. side, parent)
	end
	local CRYSTALS = { C.CrystalPurple, C.CrystalBlue, C.CrystalPink }
	for k, b in BOULDERS do
		local g = grounds[b.Piece]
		local p = at(b.X, 0, b.Z).Position
		Style.boulder(g, p, b.Size, rng, { Color = C.Stone })
		if k <= 3 then
			local c = at(b.X + (if b.X > 0 then -0.6 else 0.6), b.Size * 0.85, b.Z + 0.6)
			Style.crystal(
				g,
				c * CFrame.Angles(0.25, 0, if b.X > 0 then 0.3 else -0.3),
				b.Size * 0.55,
				b.Size * 0.16,
				CRYSTALS[k],
				nil,
				0.15
			)
		end
		local toward = (at(0, 0, zc).Position - p) * Vector3.new(1, 0, 1)
		local foot = p + toward.Unit * (b.Size * 0.7) + Vector3.new(0, 0.25, 0)
		Style.block(g, CFrame.lookAt(foot, at(0, wallH, zc).Position), Vector3.new(0.7, 0.35, 0.2), Tech.Lens, NEON, Style.tiny())
	end
	for _, t in TREES do
		Style.tree(grounds[t.Piece], at(t.X, 0, t.Z), t.Kind, rng, t.Scale)
	end

	-- inside: the solid shell of the showroom (DropperShopBuilder builds the rest
	-- on the clients): the displays' plinths, the hero podium, the counter
	for _, slot in DropperShopBuilder.Slots do
		block(at(slot.Center.X, slot.Center.Y + slot.Size.Y / 2, slot.Center.Z), slot.Size, Tech.MetalDeep)
	end
	local hero = DropperShopBuilder.Hero
	block(at(hero.Center.X, hero.Center.Y + hero.Size.Y / 2, hero.Center.Z), hero.Size, Tech.MetalDeep)
	local spec = DropperShopBuilder.Counter
	local cc, cs = spec.Center, spec.Size
	local counter = block(fr(cc.X, cc.Y + cs.Y / 2, cc.Z), cs, Tech.MetalDark)
	counter.Name = "DropperCounter"
	Kit.tag(counter, Droppers.CounterTag)
	block(at(cc.X, cc.Y + cs.Y + spec.Top / 2, cc.Z), Vector3.new(cs.X + 0.4, spec.Top, cs.Z + 0.4), Tech.MetalLight, nil, true)

	-- the clients' showroom
	Kit.tag(m, DropperShopBuilder.Tag)
	m:SetAttribute(DropperShopBuilder.FrameAttribute, B)

	m.PrimaryPart = counter
	return m
end

return Droppers
