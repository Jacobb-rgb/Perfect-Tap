--[[
	The DROPPERS SHOP (owner 2026-10-23: a walk-in shop "bigger than a
	player, the droppers along the sides and the counter in the middle",
	its entrance to the plaza's crystal, in the modern tech style, and at
	the end his concept picture "this is how it should look"). It stands
	north-east of the plaza where the FOSSIL DIG was (the dig moved by the
	Tech shop), a dark tech fortress in the Districts' look (Tech kit):
	  - the gateway: a wide opening in a thick frame with blue neon tubes, a
	    recessed second neon frame, two lit steps
	  - over it the big curved DROPPERS / SHOP sign (white and gold letters
	    in a blue neon outline) under a big gold crown
	  - gate towers either side and taller corner towers, each with a glowing
	    orange lantern cube on top; two more towers rising behind the roof
	  - navy banners with a white crown and purple neon edges, and little
	    colourful voxel rocks either side like the Candy mountains (the owner
	    took them in place of two big screens)
	  - lantern pillars, planters with bushes and a SHOP kiosk in front
	  - dark walls with blue neon top tubes, the orange band round the side
	    and back walls, a parapet with crenels on the roof
	(the round rings on the ground are on the apron, Plaza/Roads)
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
local ShopkeeperConfig = require(Shared.Config.ShopkeeperConfig)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Droppers = {}

local C = Style.C
local rgb = Color3.fromRGB

Droppers.CounterTag = "DropperCounter"

local NAVY = rgb(18, 22, 54)
local BANNER = rgb(44, 40, 120)
local PURPLE = rgb(150, 70, 255)
local GOLD = rgb(255, 196, 64)

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
	local function glow(c: CFrame, size: Vector3, color: Color3): Part
		return Tech.glow(m, c, size, color)
	end

	local ROOM = DropperShopBuilder.Room
	local W, D = ROOM.W, ROOM.D
	local z0 = ROOM.Front -- the front wall (local z)
	local zc = z0 - D / 2
	local plinth = ROOM.Plinth
	local wallH = ROOM.Wall -- the walls' height over the floor
	local top = plinth + wallH
	local doorW, doorH = ROOM.DoorW, ROOM.DoorH
	local gateW = doorW + 3 -- the gateway frame

	---------------------------------------------------------------- the shell
	-- the floor slab and its blue neon front edge
	block(at(0, plinth / 2, zc), Vector3.new(W + 1, plinth, D + 1), Tech.MetalDark)
	glow(at(0, plinth - 0.2, z0 + 0.55), Vector3.new(W + 0.8, 0.18, 0.14), Tech.Neon)
	-- dark front walls either side of the gateway, blue neon tubes along their tops
	local segW = (W - gateW) / 2
	for _, sx in { -1, 1 } do
		Tech.wall(m, fr(sx * (gateW + segW) / 2, plinth, z0), segW, wallH, 1.0, {
			Color = Tech.MetalDark,
			Band = false,
			TopNeon = Tech.Tube,
		})
	end
	-- the side and back walls with the orange band outside
	for _, sx in { -1, 1 } do
		block(at(sx * (W / 2 - 0.5), plinth + wallH / 2, zc - 0.5), Vector3.new(1, wallH, D - 1), Tech.MetalDark)
		block(at(sx * (W / 2 + 0.02), plinth + wallH * 0.62, zc - 0.5), Vector3.new(0.1, 0.9, D - 1), Tech.Band, nil, true)
	end
	block(at(0, plinth + wallH / 2, z0 - D + 0.5), Vector3.new(W - 2, wallH, 1), Tech.MetalDark)
	block(at(0, plinth + wallH * 0.62, z0 - D - 0.02), Vector3.new(W - 2, 0.9, 0.1), Tech.Band, nil, true)
	-- the roof slab, a blue neon tube along the back, a parapet with crenels on the front
	block(at(0, top + 0.3, zc), Vector3.new(W + 0.6, 0.6, D + 0.6), Tech.MetalDeep)
	Tech.channel(m, at(0, top + 0.3, z0 - D - 0.06), W + 0.4, Tech.EDGE)
	block(at(0, top + 1.2, z0 - 0.1), Vector3.new(W - 4, 1.2, 0.8), Tech.Metal)
	glow(at(0, top + 1.85, z0 + 0.2), Vector3.new(W - 4, Tech.TUBE, 0.16), Tech.Tube)
	for _, x in { -11, -8.5, 8.5, 11 } do
		block(at(x, top + 2.25, z0 - 0.1), Vector3.new(1.4, 0.9, 0.8), Tech.Metal)
	end

	---------------------------------------------------------------- the gateway
	Tech.doorFrame(m, fr(0, plinth, z0 + 0.1), gateW, wallH, 1.6, {
		Color = Tech.MetalDark,
		OpeningWidth = doorW,
		OpeningHeight = doorH,
		Frame = Tech.MetalLight,
		Neon = Tech.Tube,
	})
	-- a second neon frame set back in the opening
	for _, sx in { -1, 1 } do
		glow(at(sx * (doorW / 2 - 0.2), plinth + doorH / 2, z0 - 0.45), Vector3.new(0.22, doorH - 0.2, 0.22), Tech.Neon)
	end
	glow(at(0, plinth + doorH - 0.2, z0 - 0.45), Vector3.new(doorW - 0.3, 0.22, 0.22), Tech.Neon)
	-- two lit steps in front of it
	for k = 0, 1 do
		local depth = 1.2
		local y = plinth - 0.18 - k * 0.32
		block(at(0, y, z0 + 1.2 + k * depth), Vector3.new(gateW - k * 0.8, 0.36, depth), Tech.Metal)
		glow(at(0, y + 0.12, z0 + 1.2 + (k + 0.5) * depth + 0.02), Vector3.new(gateW - k * 0.8 - 0.2, 0.08, 0.06), Tech.Tube)
	end

	---------------------------------------------------------------- the towers
	local function lantern(x: number, y: number, z: number, size: number)
		block(at(x, y + size / 2, z), Vector3.new(size, size, size), Tech.MetalDark)
		glow(fr(x, y + size / 2, z) * CFrame.new(0, 0, -size / 2 - 0.02), Vector3.new(size * 0.62, size * 0.62, 0.1), Tech.Warm)
		block(at(x, y + size + 0.15, z), Vector3.new(size + 0.3, 0.3, size + 0.3), Tech.Metal)
	end
	-- gate towers either side of the gateway, taller corner towers
	local gateX = gateW / 2 + 0.9
	for _, sx in { -1, 1 } do
		Tech.pillar(m, fr(sx * gateX, plinth, z0 + 0.7), wallH + 1.8, 1.8)
		lantern(sx * gateX, top + 1.8 + 0.1, z0 + 0.7, 2.2)
		Tech.pillar(m, fr(sx * (W / 2 - 0.6), plinth, z0 + 0.3), wallH + 2.6, 2.2)
		lantern(sx * (W / 2 - 0.6), top + 2.6 + 0.1, z0 + 0.3, 2.6)
	end
	-- two towers rising behind the roof
	for _, sx in { -1, 1 } do
		local x, z = sx * 9.5, zc - 1.5
		block(at(x, top + 0.6 + 3, z), Vector3.new(2.8, 6, 2.8), Tech.MetalDark)
		glow(at(x, top + 0.6 + 3.6, z + 1.42), Vector3.new(1.2, 1.8, 0.1), Tech.Warm)
		glow(at(x + sx * 1.42, top + 0.6 + 3, z + 1.42), Vector3.new(0.14, 5.6, 0.14), Tech.Tube)
		block(at(x, top + 6.75, z), Vector3.new(3.2, 0.3, 3.2), Tech.Metal)
	end

	---------------------------------------------------------------- the sign and the crown
	-- a curved board: a flat middle and two wings turned back, a blue neon
	-- outline, DROPPERS in white and SHOP in gold
	local signY, signH = plinth + doorH + 3.0, 4.6
	local midW, wingW, wingTurn = 9.6, 3.4, math.rad(24)
	local signZ = z0 + 2.0
	local mid = fr(0, signY, signZ)
	block(mid, Vector3.new(midW, signH, 0.6), NAVY)
	for _, edge in { 1, -1 } do
		glow(mid * CFrame.new(0, edge * (signH / 2 - 0.05), -0.32), Vector3.new(midW, Tech.TUBE, 0.14), Tech.Tube)
	end
	for _, sx in { -1, 1 } do
		-- (seen from the front local +X is the viewer's left)
		local hinge = mid * CFrame.new(sx * midW / 2, 0, 0) * CFrame.Angles(0, sx * wingTurn, 0)
		local wing = hinge * CFrame.new(sx * wingW / 2, 0, 0)
		block(wing, Vector3.new(wingW, signH * 0.86, 0.6), NAVY)
		for _, edge in { 1, -1 } do
			glow(wing * CFrame.new(0, edge * (signH * 0.43 - 0.05), -0.32), Vector3.new(wingW, Tech.TUBE, 0.14), Tech.Tube)
		end
		glow(wing * CFrame.new(sx * (wingW / 2 - 0.05), 0, -0.32), Vector3.new(Tech.TUBE, signH * 0.86, 0.14), Tech.Tube)
	end
	Style.sign(m, mid * CFrame.new(0, 0.95, -0.36), "DROPPERS", midW + 2.4, 2.1, {
		Kind = "Glow",
		Frame = false,
		BoardColor = NAVY,
		Depth = 0.08,
		TextColor = Color3.new(1, 1, 1),
		StrokeColor = Tech.Neon,
		StrokeTransparency = 0.2,
	})
	Style.sign(m, mid * CFrame.new(0, -1.1, -0.36), "SHOP", 5.4, 1.8, {
		Kind = "Glow",
		Frame = false,
		BoardColor = NAVY,
		Depth = 0.08,
		TextColor = GOLD,
		StrokeColor = rgb(120, 60, 0),
		StrokeTransparency = 0,
	})
	-- the big gold crown on a dark shield over the sign
	local crownY = signY + signH / 2 + 0.2
	block(fr(0, crownY + 2.2, signZ - 0.6), Vector3.new(6.2, 4.4, 0.6), Tech.MetalDark)
	glow(fr(0, crownY + 4.45, signZ - 0.6) * CFrame.new(0, 0, -0.32), Vector3.new(6.2, Tech.TUBE, 0.14), Tech.Tube)
	Tech.crown(m, fr(0, crownY + 0.3, signZ - 0.15), 5.2, GOLD, { Gem = C.AwningRed })

	---------------------------------------------------------------- banners and screens
	-- a navy banner with a white crown and purple neon edges, its point down
	local bannerX = gateX + 2.5
	for _, sx in { -1, 1 } do
		local x, y0 = sx * bannerX, plinth + doorH + 0.3
		local bw, bh = 1.6, 4.6
		block(at(x, y0 + 0.15, z0 + 0.7), Vector3.new(bw + 0.5, 0.2, 0.2), Tech.MetalLight)
		block(at(x, y0 - bh / 2, z0 + 0.62), Vector3.new(bw, bh, 0.12), BANNER, Enum.Material.Fabric)
		block(
			at(x, y0 - bh, z0 + 0.62) * CFrame.Angles(0, 0, math.pi / 4),
			Vector3.new(bw * 0.707, bw * 0.707, 0.12),
			BANNER,
			Enum.Material.Fabric
		)
		for _, ex in { -1, 1 } do
			glow(at(x + ex * (bw / 2 - 0.08), y0 - bh / 2, z0 + 0.69), Vector3.new(0.16, bh - 0.2, 0.06), PURPLE)
		end
		-- the white crown: a band and three points
		local cy = y0 - 1.3
		block(at(x, cy, z0 + 0.7), Vector3.new(1.1, 0.3, 0.06), Color3.new(1, 1, 1), nil, true)
		for _, px in { -0.42, 0, 0.42 } do
			block(
				at(x + px, cy + 0.32, z0 + 0.7) * CFrame.Angles(0, 0, math.pi / 4),
				Vector3.new(0.3, 0.3, 0.06),
				Color3.new(1, 1, 1),
				nil,
				true
			)
		end
	end
	-- little colourful voxel rocks either side, like the Candy mountains
	-- (owner 2026-10-23: in place of the two screens): stepped square columns
	-- in the range's colours, the taller ones with a light tinted top
	local ROCKS = {
		{ X = -(W / 2 - 3.6), Colors = { rgb(206, 92, 168), rgb(166, 128, 240), rgb(238, 118, 176), rgb(214, 140, 232) } },
		{ X = W / 2 - 3.6, Colors = { rgb(234, 124, 36), rgb(226, 84, 126), rgb(246, 186, 52), rgb(240, 132, 56) } },
	}
	local COLUMNS = {
		{ X = 0, Z = 0, W = 2.2, H = 5.4 },
		{ X = -1.7, Z = 0.5, W = 1.7, H = 3.8 },
		{ X = 1.6, Z = 0.3, W = 1.8, H = 4.4 },
		{ X = 0.7, Z = 1.6, W = 1.3, H = 2.2 },
		{ X = -0.9, Z = 1.7, W = 1.1, H = 1.4 },
	}
	for _, rock in ROCKS do
		for k, col in COLUMNS do
			local color = rock.Colors[(k - 1) % #rock.Colors + 1]
			local x, z = rock.X + col.X, z0 + 1.5 + col.Z
			block(at(x, col.H / 2, z), Vector3.new(col.W, col.H, col.W), color)
			if k <= 3 then
				block(at(x, col.H + 0.12, z), Vector3.new(col.W + 0.1, 0.24, col.W + 0.1), color:Lerp(Color3.new(1, 1, 1), 0.55), nil, true)
			end
		end
	end

	---------------------------------------------------------------- in front: lanterns, planters, the kiosk
	for _, sx in { -1, 1 } do
		Tech.lanternPillar(m, fr(sx * (W / 2 - 1.5), 0, z0 + 3.6), 4.2, 0.9)
		local px = sx * (gateW / 2 + 2.6)
		block(at(px, 0.45, z0 + 2.4), Vector3.new(2.2, 0.9, 1.3), Tech.MetalDark)
		block(at(px, 1.2, z0 + 2.4), Vector3.new(1.9, 0.9, 1.0), C.LeafGreen)
		block(at(px + 0.3, 1.8, z0 + 2.35), Vector3.new(1.0, 0.6, 0.8), C.LeafGreenLight)
	end
	-- the SHOP kiosk on the right (as seen from the plaza), turned to the path
	local kiosk = fr(W / 2 - 2.4, 0, z0 + 5.4) * CFrame.Angles(0, math.rad(28), 0)
	block(kiosk * CFrame.new(0, 0.6, 0), Vector3.new(2.4, 1.2, 1.4), Tech.MetalDark)
	block(kiosk * CFrame.new(0, 1.35, -0.2) * CFrame.Angles(math.rad(-25), 0, 0), Vector3.new(2.2, 0.3, 1.1), Tech.Metal)
	glow(kiosk * CFrame.new(0, 1.52, -0.25) * CFrame.Angles(math.rad(-25), 0, 0), Vector3.new(1.6, 0.06, 0.6), Tech.Screen)
	block(kiosk * CFrame.new(0, 2.7, 0.45) * CFrame.Angles(math.rad(10), 0, 0), Vector3.new(2.6, 2.2, 0.5), Tech.MetalDark)
	local kioskScreen = glow(kiosk * CFrame.new(0, 2.7, 0.18) * CFrame.Angles(math.rad(10), 0, 0), Vector3.new(2.2, 1.8, 0.08), Tech.Tube)
	Tech.label(m, kioskScreen.CFrame * CFrame.new(0, -0.35, -0.06), "SHOP", 1.9, 0.7, Color3.new(1, 1, 1), 0.04)

	---------------------------------------------------------------- inside: the shell
	-- the solid shell of the showroom (DropperShopBuilder builds the rest on
	-- the clients): the displays' plinths, the hero podium, the counter
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
	-- the shopkeeper golem (ShopkeeperController) by the counter's left end,
	-- between the DARK MATTER DROPPER's podium and the side displays, turned a
	-- little to the shop's middle (behind the counter the hero leaves no room)
	local inner = DropperShopBuilder.Inner
	ShopkeeperConfig.mark(counter, fr(-6.3, cc.Y, inner.Back + 6.2) * CFrame.Angles(0, 0.35, 0), "Droppers")

	-- the clients' showroom
	Kit.tag(m, DropperShopBuilder.Tag)
	m:SetAttribute(DropperShopBuilder.FrameAttribute, B)

	m.PrimaryPart = counter
	return m
end

return Droppers
