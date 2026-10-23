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
	  - a massive header across the front with the glowing DROPPERS sign box,
	    a little gold dropper on top
	  - dark side and back walls with the orange band, a flat roof with blue
	    neon edge tubes in dark channels and two roof containers
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
local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon

Droppers.CounterTag = "DropperCounter"

function Droppers.build(parent: Instance, _rng: Rng.Rng)
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

	-- the flat roof with blue neon edge tubes in dark channels, two roof containers
	block(at(0, top + 0.3, zc), Vector3.new(W + 0.6, 0.6, D + 0.6), Tech.MetalDeep)
	for _, sx in { -1, 1 } do
		Tech.channel(m, at(sx * (W / 2 + 0.36), top + 0.3, zc) * CFrame.Angles(0, -sx * math.pi / 2, 0), D + 0.4, Tech.EDGE)
	end
	Tech.channel(m, at(0, top + 0.3, z0 - D - 0.06), W + 0.4, Tech.EDGE)
	for k, x in { -7, 8.5 } do
		Tech.container(m, at(x, top + 0.6, zc - 2.5 + k), 2.4, 2, if k == 1 then Tech.Metal else Tech.MetalLight)
	end

	-- the header across the front with the glowing DROPPERS sign box
	local headerH = ROOM.Header
	Tech.wall(m, fr(0, top - 0.6, z0 + 0.45), W + 0.4, headerH, 1.9, {
		Color = Tech.MetalDark,
		Band = false,
		Foot = false,
		TopNeon = Tech.Tube,
	})
	Tech.sign(m, fr(0, top - 0.6 + headerH / 2, z0 + 1.45), "DROPPERS", 15, headerH - 0.9, {
		Casing = false,
		Studs = false,
	})

	-- the little gold dropper on the header (a 7: base, column, arm, glowing spout)
	local hy = top - 0.6 + headerH
	local GOLD, GOLD_DARK = rgb(246, 194, 62), rgb(186, 126, 28)
	block(at(0, hy + 0.2, z0 + 0.6), Vector3.new(2.6, 0.4, 1.2), GOLD_DARK)
	block(at(0.5, hy + 1.3, z0 + 0.6), Vector3.new(0.8, 1.8, 0.8), GOLD)
	block(at(-0.15, hy + 2.4, z0 + 0.6), Vector3.new(2.1, 0.6, 0.8), GOLD)
	block(at(-0.95, hy + 1.95, z0 + 0.6), Vector3.new(0.45, 0.22, 0.45), rgb(255, 214, 80), NEON, true)
	block(at(-0.95, hy + 1.1, z0 + 0.6), Vector3.new(0.4, 0.4, 0.4), C.CrystalPurple, NEON, true)

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
