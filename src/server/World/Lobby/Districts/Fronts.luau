--[[
	The two small set pieces in front of the stalls:
	  ShopFront      Tobin's Sell stall next to the SHOP: the SellBin (tag
	                 SellBin, child part Intake), an ore cart with a counter
	                 and a brass scale (tag SellCounter), Tobin the Miner and
	                 a hanging SELL sign.
	  UpgradesFront  a glowing laser blaster floating over a pedestal (tag
	                 Spin), a gear crate and a purple loot chest.
	Both leave a walk lane in the middle so players reach the shop counter.
	Local frame: 14 wide, front = -Z (toward the plaza), +X = viewer's left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local Fronts = {}

local C = Kit.C

-- A heap of ore chunks: stone, copper, iron and a few glowing ones.
local function oreHeap(parent: Instance, center: CFrame, spreadX: number, spreadZ: number, count: number, rng: Rng.Rng)
	local colors = { C.Stone, C.Copper, C.Gold, C.IronLight, C.StoneLight, C.CrystalPurple, C.Gold, C.CrystalBlue }
	for i = 1, count do
		local color = colors[(i - 1) % #colors + 1]
		local glowing = color == C.Gold or color == C.CrystalPurple or color == C.CrystalBlue
		local s = rng:range(0.8, 1.25)
		local offset = Vector3.new(rng:range(-spreadX, spreadX), rng:range(0, 0.45), rng:range(-spreadZ, spreadZ))
		Kit.block(
			parent,
			center * CFrame.new(offset) * Geo.randomTilt(rng, 0.45),
			Vector3.new(s, s * 0.8, s),
			Style.vary(color, rng, 0.05),
			if glowing then Kit.NEON else Kit.SMOOTH,
			Style.tiny()
		)
	end
end

---------------------------------------------------------------- Tobin's Sell stall

local function sellStall(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("ShopFront")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- the SellBin (viewer's right): a banded wooden bin full of ore
	local bin = Style.model("SellBin", m)
	local bx, bz = -3.75, 0.2
	local w, d = 6.4, 7.6
	Style.block(bin, at(bx, 0.25, bz), Vector3.new(w, 0.5, d), C.WoodDark, nil, Style.solid())
	for _, side in { -1, 1 } do
		Style.block(
			bin,
			at(bx, 2.05, bz + side * (d / 2 - 0.25)),
			Vector3.new(w, 3.1, 0.5),
			Style.vary(C.Wood, rng, 0.04),
			nil,
			Style.solid()
		)
		Style.block(
			bin,
			at(bx + side * (w / 2 - 0.25), 2.05, bz),
			Vector3.new(0.5, 3.1, d - 1),
			Style.vary(C.Wood, rng, 0.04),
			nil,
			Style.solid()
		)
		Kit.bit(bin, at(bx, 3.2, bz + side * (d / 2 + 0.03)), Vector3.new(w + 0.1, 0.4, 0.1), C.Gold)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Style.block(bin, at(bx + sx * (w / 2 - 0.35), 1.95, bz + sz * (d / 2 - 0.35)), Vector3.new(0.8, 3.9, 0.8), C.WoodDark)
		end
	end
	local coins = Kit.block(bin, at(bx, 2.3, bz), Vector3.new(w - 1.2, 0.3, d - 1.2), C.Gold, Kit.NEON, Style.tiny({ Transparency = 0.2 }))
	coins.Name = "Coins"
	oreHeap(bin, at(bx, 2.7, bz), 1.8, 2.4, 9, rng)
	Style.sign(bin, at(bx, 1.9, bz - d / 2 - 0.15), "SELL", 4.6, 1.5, { Depth = 0.3, Frame = false })
	local intake = Kit.block(bin, at(bx, 2.6, bz), Vector3.new(w - 0.8, 5, d - 1.0), C.Gold, nil, {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	intake.Name = "Intake"
	Kit.tag(bin, "SellBin")
	bin.PrimaryPart = intake

	-- Tobin's ore cart on a stub of rails (viewer's left): a plank counter laid
	-- across its front (tag SellCounter) with a brass scale and coin stacks
	local cx, cz = 4.85, -1.3
	Style.rails(m, at(2.6, 0, cz).Position, at(7.0, 0, cz).Position)
	Style.block(m, at(cx, 1.6, cz), Vector3.new(3.6, 1.5, 2.6), C.Iron, nil, Style.solid())
	Kit.bit(m, at(cx, 2.5, cz), Vector3.new(4.0, 0.35, 3.0), C.IronLight, Kit.METAL)
	for _, x in { -1.0, 1.0 } do
		Kit.bit(m, at(cx + x, 1.6, cz - 1.33), Vector3.new(0.35, 1.6, 0.1), C.Copper)
		for _, z in { -1.45, 1.45 } do
			Kit.faceDisc(m, at(cx + x * 1.1, 0.75, cz + z), 0.35, 1.3, C.StoneDeep)
		end
	end
	oreHeap(m, at(cx, 2.75, cz + 0.55), 1.2, 0.45, 7, rng)
	local counter = Style.block(m, at(cx, 2.85, cz - 1.05), Vector3.new(4.2, 0.3, 1.3), C.WoodLight, nil, Style.solid())
	counter.Name = "SellCounter"
	Kit.tag(counter, "SellCounter")
	Style.sign(m, at(cx, 1.75, cz - 1.9), "SELL", 3.0, 1.0, { Depth = 0.2, Frame = false })
	-- brass scale: base, post, beam, two pans on strings, an ore nugget weighed
	local sx, sz = cx - 1.0, cz - 1.05
	Kit.bit(m, at(sx, 3.1, sz), Vector3.new(0.9, 0.2, 0.6), C.Brass)
	Kit.bit(m, at(sx, 3.85, sz), Vector3.new(0.18, 1.3, 0.18), C.Brass)
	Kit.bit(m, at(sx, 4.52, sz), Vector3.new(2.0, 0.16, 0.16), C.Brass)
	for _, x in { -0.9, 0.9 } do
		Kit.bit(m, at(sx + x, 4.15, sz), Vector3.new(0.06, 0.7, 0.06), C.Iron)
		Kit.bit(m, at(sx + x, 3.75, sz), Vector3.new(0.75, 0.1, 0.75), C.Brass)
	end
	Kit.glow(m, at(sx - 0.9, 3.95, sz), Vector3.new(0.4, 0.32, 0.4), C.Gold)
	for i, x in { 1.0, 1.6 } do
		Kit.disc(m, at(cx + x, 3.0 + 0.2 * i, sz).Position, 0.4 * i, 0.6, C.Gold, nil, Style.tiny())
	end

	-- Tobin the Miner behind his cart: hard hat with a head lamp, beard, overalls
	Kit.npc(m, at(cx, 0, 1.75), {
		Name = "Tobin",
		Tag = "Tobin the Miner",
		Shirt = C.AwningRed,
		Overalls = C.WaterDeep,
		Boots = C.WoodDark,
		Beard = C.StoneLight,
		Helmet = C.LeafYellow,
		HelmetLamp = true,
	})

	-- a tall post with a SELL blade sign (seen from the south and the hero view,
	-- edge-on from the plaza so it never hides the SHOP awning) and a lit lantern
	local px, pz = 6.5, 3.3
	Style.block(m, at(px, 4.8, pz), Vector3.new(0.8, 9.6, 0.8), C.WoodDark)
	Kit.bit(m, at(px, 9.75, pz), Vector3.new(1.0, 0.3, 1.0), C.Wood)
	Style.sign(
		m,
		at(px, 8.5, pz - 2.2) * CFrame.Angles(0, -math.pi / 2, 0),
		"SELL",
		3.6,
		1.6,
		{ Kind = "Wood", DoubleSided = true, Depth = 0.4 }
	)
	Style.block(m, at(px - 1.5, 9.25, pz), Vector3.new(3.0, 0.45, 0.45), C.WoodDark, nil, Style.tiny({ CastShadow = true }))
	Kit.hangingLamp(m, at(px - 2.7, 9.0, pz), C.Lamp, 14)
end

---------------------------------------------------------------- the blaster display

local function blasterDisplay(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("UpgradesFront")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- pedestal with a glowing band and a glowing plate (viewer's left)
	local px, pz = 4.4, 0.4
	Style.pillar(m, at(px, 0, pz), 3, rng, { Width = 1.8, Glow = C.GlowEdge })
	Kit.disc(m, at(px, 3.06, pz).Position, 0.12, 1.9, C.CrystalCyan, Kit.NEON, Style.tiny())

	-- the laser blaster (Kenney Blaster Kit look, forge palette): floats and turns
	local blaster = Style.model("Blaster", m)
	local pivot = at(px, 4.7, pz)
	local orb = Kit.ball(blaster, pivot.Position + Vector3.new(0, -0.95, 0), 0.5, C.CrystalCyan, Kit.NEON)
	orb.Name = "HoverOrb"
	local bf = pivot * CFrame.Angles(0, 0.5, 0) * CFrame.Angles(0, 0, -0.18)
	Kit.bit(blaster, bf, Vector3.new(2.1, 0.95, 0.95), C.IronLight)
	Kit.glow(blaster, bf * CFrame.new(0.1, 0.42, 0), Vector3.new(1.0, 0.3, 1.0), C.CrystalBlue)
	Kit.bit(blaster, bf * CFrame.new(-1.55, 0.05, 0), Vector3.new(1.1, 0.55, 0.55), C.Iron)
	for _, x in { -1.25, -1.9 } do
		Kit.bit(blaster, bf * CFrame.new(x, 0.05, 0), Vector3.new(0.25, 0.8, 0.8), C.Brass)
	end
	Kit.glow(blaster, bf * CFrame.new(-2.15, 0.05, 0), Vector3.new(0.18, 0.42, 0.42), C.CrystalCyan)
	Kit.bit(blaster, bf * CFrame.new(0.55, -0.8, 0) * CFrame.Angles(0, 0, -0.3), Vector3.new(0.55, 1.1, 0.6), C.WoodDark)
	Kit.bit(blaster, bf * CFrame.new(1.2, 0.25, 0), Vector3.new(0.45, 0.85, 0.3), C.Iron)
	Kit.bit(blaster, bf * CFrame.new(-0.2, 0.75, 0), Vector3.new(1.0, 0.3, 0.3), C.Iron)
	for _, z in { -0.55, 0.55 } do
		Kit.bit(blaster, bf * CFrame.new(0.3, -0.1, z), Vector3.new(0.9, 0.12, 0.35), C.Copper)
	end
	Style.emitter(orb, "Sparkle", C.CrystalCyan, 2)
	blaster.PrimaryPart = orb
	blaster:SetAttribute("SpinSpeed", 0.7)
	blaster:SetAttribute("BobHeight", 0.25)
	blaster:SetAttribute("BobSpeed", 1.2)
	Style.streaming(blaster, "Atomic")
	Kit.tag(blaster, "Spin")

	-- viewer's right: a gear crate and the purple loot chest (concept)
	Kit.crate(m, at(-4.6, 0, 1.6), 2.2, rng)
	Style.icon(m, at(-4.6, 1.1, 1.6 - 1.25), "Gear", 1.5, C.GlowEdge, Kit.NEON)
	local chest = at(-4.4, 0, -2.0)
	Style.block(m, chest * CFrame.new(0, 0.75, 0), Vector3.new(2.6, 1.5, 1.7), C.AwningPurple)
	Style.block(m, chest * CFrame.new(0, 1.75, 0), Vector3.new(2.7, 0.5, 1.8), C.AwningPurple:Lerp(Kit.Dark, 0.3))
	for _, x in { -0.85, 0.85 } do
		Kit.bit(m, chest * CFrame.new(x, 1.0, 0), Vector3.new(0.25, 2.05, 1.85), C.Gold)
	end
	Kit.glow(m, chest * CFrame.new(-0.4, 2.15, 0) * CFrame.Angles(0.3, 0.6, 0.2), Vector3.new(0.5, 0.4, 0.5), C.Gold)
	Kit.glow(m, chest * CFrame.new(0.45, 2.1, 0.1) * CFrame.Angles(0.2, 0.2, 0.4), Vector3.new(0.45, 0.35, 0.45), C.CrystalCyan)
end

function Fronts.build(parent: Instance, rng: Rng.Rng)
	sellStall(parent, rng)
	blasterDisplay(parent, rng)
end

return Fronts
