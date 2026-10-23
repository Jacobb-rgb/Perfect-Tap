--[[
	The DROPPERS shop (owner 2026-10-23: in the town's style, stone walls,
	planks, details; "a shop you walk into, bigger than a player, the
	droppers along the sides and the counter in the middle"). It stands
	where the FOSSIL DIG was (the dig moved by the Tech shop). The lobby
	Style kit's look, lean for phones: a cobble plinth, a stone ground floor
	(stones and mortar courses on the front) with a wide open entrance, a
	timber-framed plaster upper floor, a terracotta roof with a front cross
	gable over a plank porch, the glowing DROPPERS sign under the gable, a
	little gold dropper on a shelf on the plank gable, lanterns, lit windows and a stone chimney with an ember glow.

	Inside (owner 2026-10-23: "extremely good", "like the chests with the
	blasters"): the server builds the solid shell only: the stone plinths of
	the six side displays, the hero podium and the counter. Every client
	builds the showroom itself while its camera is near (the house carries
	the DropperShopBuilder.Tag tag and its frame in the FrameAttribute
	attribute; DropperShopController): the real droppers, the DARK MATTER
	DROPPER on the podium, the Dropper Master, the floor, the walls, the
	chandeliers (DropperShopBuilder), so the map and phone budgets carry the
	shell only.

	The counter carries the DropperCounter tag: ShopService gives it the
	"Droppers" prompt that opens the Tech shop (the droppers and the Money
	Laser are machines there).

	Frame: Kit.piece("DroppersHouse") (front = LookVector). The house is drawn
	in a frame turned to face +Z ("B"), like the preview (tools/lune/lib/dropper_preview.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local DropperShopBuilder = require(Shared.Builders.DropperShopBuilder)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Droppers = {}

local C = Style.C
local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon

Droppers.CounterTag = "DropperCounter"

function Droppers.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("DroppersHouse")
	local m = Style.model(piece.Id, parent)
	local TURN = CFrame.Angles(0, math.pi, 0)
	local B = cf * TURN -- local +Z = the house's front (the piece's LookVector)
	local function at(x: number, y: number, z: number): CFrame
		return B * CFrame.new(x, y, z)
	end
	-- a frame at (x, y, z) whose LookVector is the house's front (Style's front)
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
	local zBack = z0 - D + 0.5 -- the back wall's middle
	local plinth, ground, upper = ROOM.Plinth, ROOM.Ground, ROOM.Upper
	local floor1 = plinth + ground
	local eave = floor1 + upper
	local PLASTER = rgb(238, 222, 190)
	local BEAM = C.WoodDark
	local doorW, doorH = ROOM.DoorW, ROOM.DoorH

	-- the plinth (the shop's dark floor)
	block(at(0, plinth / 2, zc), Vector3.new(W + 1, plinth, D + 1), C.CobbleDark)
	-- the front wall of stones and mortar courses either side of the entrance,
	-- a stone lintel over it, plain stone sides and back
	local segW = (W - doorW) / 2
	for _, sx in { -1, 1 } do
		Style.stoneWall(
			m,
			fr(sx * (doorW + segW) / 2, plinth, z0),
			Vector3.new(segW, ground, 1),
			rng,
			{ Cap = false, Density = 0.2, CourseEvery = 2.2 }
		)
		block(at(sx * (W / 2 - 0.5), plinth + ground / 2, zc), Vector3.new(1, ground, D), C.Stone)
		-- the entrance's stone frame
		block(at(sx * (doorW / 2 + 0.4), plinth + doorH / 2, z0 + 0.6), Vector3.new(0.8, doorH + 0.4, 0.5), C.StoneLight)
		Style.lantern(m, fr(sx * (doorW / 2 + 1.5), plinth + doorH - 0.4, z0 + 1.0), { Kind = "Hanging" })
	end
	block(at(0, plinth + doorH + (ground - doorH) / 2, z0), Vector3.new(doorW, ground - doorH, 1), C.Stone)
	block(at(0, plinth + ground / 2, zBack), Vector3.new(W - 2, ground, 1), C.Stone)

	-- the timber-framed upper floor (its underside is the shop's ceiling)
	block(at(0, floor1 + upper / 2, zc), Vector3.new(W, upper, D), PLASTER)
	local function timberFace(face: CFrame, width: number, posts: number)
		block(face * CFrame.new(0, 0.3, -0.25), Vector3.new(width + 0.4, 0.6, 0.5), BEAM, nil, true)
		block(face * CFrame.new(0, upper - 0.3, -0.25), Vector3.new(width + 0.4, 0.6, 0.5), BEAM, nil, true)
		for i = 0, posts do
			local x = -width / 2 + i * width / posts
			block(face * CFrame.new(x, upper / 2, -0.25), Vector3.new(0.6, upper, 0.5), BEAM, nil, true)
		end
		local span = width / posts
		local len = math.sqrt(span * span + (upper - 1.2) ^ 2)
		local ang = math.atan2(upper - 1.2, span)
		for _, i in { 0, posts - 1 } do
			local mid = -width / 2 + (i + 0.5) * span
			block(
				face * CFrame.new(mid, upper / 2, -0.22) * CFrame.Angles(0, 0, if i == 0 then ang else -ang),
				Vector3.new(len, 0.45, 0.4),
				BEAM,
				nil,
				true
			)
		end
	end
	timberFace(fr(0, floor1, z0 + 0.02), W, 5)

	-- the roof (plank gable ends) and the front cross gable with the sign
	Style.gableRoof(m, at(0, eave, zc), W + 1.2, D + 1, 6, {
		Color = C.RoofTerracotta,
		Dark = C.RoofTerracottaDark,
		Trim = C.RoofTrim,
		Rows = 3,
	})
	for _, sx in { -1, 1 } do
		block(at(sx * (W / 2 - 0.1), eave + 1.5, zc), Vector3.new(0.4, 3, (D + 1) * 0.75), Style.vary(C.Plank, rng, 0.05))
	end
	local gw = 11
	Style.gableRoof(m, at(0, eave - 0.5, z0 + 1.6) * CFrame.Angles(0, math.pi / 2, 0), 8.6, gw, 5, {
		Color = C.RoofTerracotta,
		Dark = C.RoofTerracottaDark,
		Trim = C.RoofTrim,
		Rows = 2,
	})
	for k = 0, 3 do
		local h = 5 * (1 - k / 4)
		block(
			at(0, eave - 0.5 + k * 1.25 + 0.62, z0 + 5.9),
			Vector3.new(math.max(0.6, (gw - 1) * h / 5), 1.25, 0.3),
			Style.vary(C.Plank, rng, 0.05)
		)
	end
	for _, sx in { -1, 1 } do
		block(at(sx * (gw / 2 - 0.6), (plinth + eave - 0.5) / 2, z0 + 5.4), Vector3.new(0.9, eave - 0.5 - plinth, 0.9), C.Wood)
	end
	block(at(0, eave - 0.85, z0 + 5.4), Vector3.new(gw, 0.7, 0.9), BEAM)
	Style.sign(m, fr(0, floor1 + 1.9, z0 + 5.95), "DROPPERS", 9.4, 2.5, { Kind = "Glow" })

	-- the little gold dropper on its shelf on the plank gable (a 7: base, column, arm, glowing spout)
	block(at(0, eave + 0.1, z0 + 6.4), Vector3.new(3.2, 0.3, 1.1), BEAM)
	local GOLD, GOLD_DARK = rgb(246, 194, 62), rgb(186, 126, 28)
	block(at(0.4, eave + 0.45, z0 + 6.4), Vector3.new(1.6, 0.4, 0.9), GOLD_DARK)
	block(at(0.5, eave + 1.35, z0 + 6.4), Vector3.new(0.7, 1.5, 0.7), GOLD)
	block(at(-0.1, eave + 2.25, z0 + 6.4), Vector3.new(1.9, 0.5, 0.7), GOLD)
	block(at(-0.85, eave + 1.9, z0 + 6.4), Vector3.new(0.4, 0.2, 0.4), rgb(255, 214, 80), NEON, true)
	block(at(-0.85, eave + 1.2, z0 + 6.5), Vector3.new(0.35, 0.35, 0.35), C.CrystalPurple, NEON, true)

	-- the porch planks
	Style.planks(m, fr(0, plinth + 0.05, z0 + 2.7), Vector3.new(gw - 0.4, 0.3, 4.8), rng)

	-- lit windows: a big one either side of the entrance, one upstairs over each
	for _, sx in { -1, 1 } do
		Style.window(m, fr(sx * ROOM.WindowX, plinth + ROOM.WindowY, z0 + 0.62), ROOM.WindowW, ROOM.WindowH, { Bars = false })
		Style.window(m, fr(sx * 9, floor1 + upper / 2, z0 + 0.3), 2.4, 2, { Bars = false })
	end

	-- the chimney
	Style.pillar(m, at(W / 2 - 4, eave + 1, zc - 1.5), 9, rng, { Width = 2.4, Glow = C.Ember })

	-- inside: the solid shell of the showroom (DropperShopBuilder builds the rest
	-- on the clients): the side displays' stone plinths, the hero podium, the counter
	for _, slot in DropperShopBuilder.Slots do
		block(at(slot.Center.X, slot.Center.Y + slot.Size.Y / 2, slot.Center.Z), slot.Size, C.StoneDark)
	end
	local hero = DropperShopBuilder.Hero
	block(at(hero.Center.X, hero.Center.Y + hero.Size.Y / 2, hero.Center.Z), hero.Size, C.StoneDeep)
	local spec = DropperShopBuilder.Counter
	local cc, cs = spec.Center, spec.Size
	local counter = block(fr(cc.X, cc.Y + cs.Y / 2, cc.Z), cs, C.StoneDeep)
	counter.Name = "DropperCounter"
	Kit.tag(counter, Droppers.CounterTag)
	block(at(cc.X, cc.Y + cs.Y + spec.Top / 2, cc.Z), Vector3.new(cs.X + 0.4, spec.Top, cs.Z + 0.4), BEAM, nil, true)

	-- the clients' showroom
	Kit.tag(m, DropperShopBuilder.Tag)
	m:SetAttribute(DropperShopBuilder.FrameAttribute, B)
	m.PrimaryPart = counter
	return m
end

return Droppers
