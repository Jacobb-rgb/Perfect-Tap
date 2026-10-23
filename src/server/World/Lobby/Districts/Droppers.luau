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

	Inside, in the Blaster Vault's look (owner 2026-10-23: "like the chests
	with the blasters"): a stone stage with an orange neon edge along each
	side wall, a shelf behind it; the seven droppers and the Money Laser on
	it as display models on glowing pads in their own colour (a glowing ore
	falling from the spout, a crystal on the arm), each with a name and
	price plate on the stage front; a red runner with gold edges from the
	entrance to the counter in the middle (dark stone, plank top, neon
	edge); a candle ring overhead; the BUY DROPPERS sign between a gold and
	a purple banner on the back wall.

	The counter carries the DropperCounter tag: ShopService gives it the
	"Droppers" prompt that opens the Tech shop (the droppers and the Money
	Laser are machines there).

	Frame: Kit.piece("DroppersHouse") (front = LookVector). The house is drawn
	in a frame turned to face +Z ("B"), like the preview (tools/lune/lib/dropper_preview.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local DropperConfig = require(Shared.Config.DropperConfig)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Droppers = {}

local C = Style.C
local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon

Droppers.CounterTag = "DropperCounter"

-- The display models' colours (body, glow) by dropper id; they stand in
-- DropperConfig.List order, the left wall front to back, then the right wall.
local LOOKS: { [string]: { Color3 } } = {
	BasicDropper = { rgb(128, 136, 148), rgb(96, 232, 124) },
	BlueDropper = { rgb(58, 108, 220), rgb(96, 196, 255) },
	RedDropper = { rgb(204, 52, 52), rgb(255, 128, 84) },
	PurpleDropper = { rgb(132, 72, 204), rgb(214, 136, 255) },
	GoldDropper = { rgb(246, 194, 62), rgb(255, 232, 124) },
	RainbowDropper = { rgb(240, 240, 250), rgb(255, 120, 204) },
	DarkMatterDropper = { rgb(32, 26, 48), rgb(172, 92, 255) },
}

-- 5e9 -> "5B", 2.5e13 -> "25T"
local function short(n: number): string
	if n >= 1e12 then
		return string.format("%gT", n / 1e12)
	end
	return string.format("%gB", n / 1e9)
end

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

	local W, D = 24, 17
	local z0 = 2.9 -- the front wall (local z)
	local zc = z0 - D / 2
	local zBack = z0 - D + 0.5 -- the back wall's middle
	local plinth, ground, upper = 1.0, 7.5, 4.6
	local floor1 = plinth + ground
	local eave = floor1 + upper
	local PLASTER = rgb(238, 222, 190)
	local BEAM = C.WoodDark
	local doorW, doorH = 5, 6.6

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
			{ Cap = false, Density = 0.3, CourseEvery = 1.6 }
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
	timberFace(fr(0, floor1, z0 + 0.02), W, 4)

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

	-- lit windows
	for _, wx in { -7.6, 7.6 } do
		Style.window(m, fr(wx, plinth + 3.8, z0 + 0.62), 3.6, 2.6, { Bars = false })
		Style.window(m, fr(wx, floor1 + upper / 2, z0 + 0.3), 2, 2, { Bars = false })
	end

	-- the chimney
	Style.pillar(m, at(W / 2 - 4, eave + 1, zc - 1.5), 9, rng, { Width = 2.4, Glow = C.Ember })

	-- inside: along each side wall a stone stage with an orange neon edge and a
	-- shelf behind it (the Vault's lit steps)
	local stageH, stageIn = 0.9, W / 2 - 1 -- the inner wall face
	local stageOut = stageIn - 5 -- the stage's front edge (|x|)
	local zFront, zRear = z0 - 1, zBack + 0.5
	local stageZ, stageL = (zFront + zRear) / 2, zFront - zRear
	for _, sx in { -1, 1 } do
		block(at(sx * (stageIn + stageOut) / 2, plinth + stageH / 2, stageZ), Vector3.new(5, stageH, stageL), C.StoneDark)
		block(at(sx * (stageOut - 0.03), plinth + stageH - 0.04, stageZ), Vector3.new(0.18, 0.12, stageL), C.Fire, NEON, true)
		block(at(sx * (stageIn - 0.6), plinth + 1.2, stageZ), Vector3.new(1.2, 2.4, stageL), C.StoneDeep)
	end

	-- the display models on the stage: a 7 (base, column, arm) on a glowing
	-- pad, a glowing spout with an ore falling, a crystal on the arm, and the
	-- name and price plate on the stage front; `c` (on the stage top) looks
	-- into the aisle
	local slotZ = {}
	for k = 0, 3 do
		slotZ[k + 1] = zFront - stageL * (k + 0.5) / 4
	end
	local slotX = stageOut + 1.9
	local function slot(i: number): CFrame
		local left = i <= 4
		local z = slotZ[if left then i else i - 4]
		-- (left wall: look along +X; right wall: along -X)
		return at((if left then -1 else 1) * slotX, plinth + stageH, z) * CFrame.Angles(0, if left then -math.pi / 2 else math.pi / 2, 0)
	end
	local function plate(c: CFrame, text: string)
		Style.sign(m, c * CFrame.new(0, -stageH / 2, -1.95), text, 3.4, 0.7, { Kind = "Glow", Frame = false, Depth = 0.1 })
	end
	for i, dropper in DropperConfig.List do
		local look = LOOKS[dropper.Id] or { C.StoneLight, C.Fire }
		local body, glow = look[1], look[2]
		local c = slot(i)
		block(c * CFrame.new(0, 0.06, -0.1), Vector3.new(3.3, 0.12, 3.3), glow, NEON, true)
		block(c * CFrame.new(0, 0.62, 0), Vector3.new(3, 1, 2.8), body)
		block(c * CFrame.new(0, 3.2, 0.85), Vector3.new(1.1, 4.2, 1.1), body, nil, true)
		block(c * CFrame.new(0, 5.3, -0.25), Vector3.new(1.2, 0.9, 3.4), body, nil, true)
		block(c * CFrame.new(0, 4.7, -1.45), Vector3.new(0.8, 0.3, 0.8), glow, NEON, true)
		block(c * CFrame.new(0, 2.9, -1.45) * CFrame.Angles(0.6, 0.6, 0), Vector3.new(0.6, 0.6, 0.6), glow, NEON, true)
		block(c * CFrame.new(0, 6, 0.4) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), Vector3.new(0.55, 0.55, 0.55), glow, NEON, true)
		plate(c, string.upper((string.gsub(dropper.Name, " Dropper", ""))) .. "  " .. short(dropper.Price))
	end
	-- the Money Laser in the last slot: a green gate with a glowing beam
	local laser = slot(8)
	local GREEN, BEAMG = rgb(60, 190, 92), rgb(124, 255, 150)
	block(laser * CFrame.new(0, 0.06, -0.1), Vector3.new(3.3, 0.12, 3.3), BEAMG, NEON, true)
	for _, px in { -1.25, 1.25 } do
		block(laser * CFrame.new(px, 2.5, 0), Vector3.new(0.6, 4.8, 0.8), GREEN, nil, true)
	end
	block(laser * CFrame.new(0, 5.1, 0), Vector3.new(3.1, 0.6, 1), GREEN, nil, true)
	block(laser * CFrame.new(0, 2.5, 0), Vector3.new(1.9, 4.6, 0.15), BEAMG, NEON, true).Transparency = 0.35
	plate(laser, "2X LASER  " .. short(DropperConfig.Laser.Price))

	-- the counter in the middle (the shop prompt): dark stone, a plank top, a neon edge
	local zCounter = zc - 1
	local counter = block(fr(0, plinth + 0.75, zCounter), Vector3.new(6, 1.5, 1.6), C.StoneDeep)
	counter.Name = "DropperCounter"
	Kit.tag(counter, Droppers.CounterTag)
	block(at(0, plinth + 1.62, zCounter), Vector3.new(6.4, 0.25, 2), BEAM, nil, true)
	block(at(0, plinth + 1.4, zCounter + 0.84), Vector3.new(6, 0.14, 0.1), C.Fire, NEON, true)
	-- the red runner with gold edges from the entrance to the counter
	local runFrom, runTo = z0 + 0.5, zCounter + 0.8
	local runZ, runL = (runFrom + runTo) / 2, runFrom - runTo
	block(at(0, plinth + 0.03, runZ), Vector3.new(3.4, 0.06, runL), C.AwningRed, Enum.Material.Fabric, true)
	for _, sx in { -1, 1 } do
		block(at(sx * 1.6, plinth + 0.05, runZ), Vector3.new(0.25, 0.08, runL), C.Gold, nil, true)
	end
	-- the candle ring over the runner
	local ringY = floor1 - 1.2
	block(at(0, ringY, runZ), Vector3.new(2.8, 0.25, 2.8), BEAM, nil, true)
	for _, q in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		block(at(q[1] * 1.15, ringY + 0.4, runZ + q[2] * 1.15), Vector3.new(0.3, 0.5, 0.3), C.FireCore, NEON, true)
	end
	-- the back wall: BUY DROPPERS between a gold and a purple banner
	Style.sign(m, fr(0, plinth + 4.6, zBack + 0.56), "BUY DROPPERS", 8, 1.5, { Kind = "Glow", Frame = false, Depth = 0.1 })
	for _, sx in { -1, 1 } do
		local banner = if sx < 0 then C.Gold else rgb(132, 72, 204)
		block(at(sx * 6.4, plinth + 4.4, zBack + 0.58), Vector3.new(2.2, 3.6, 0.12), banner, Enum.Material.Fabric, true)
	end

	m.PrimaryPart = counter
	return m
end

return Droppers
