--[[
	The two small set pieces in front of the shop modules, in the same metal
	and neon language (concept v2). Both stay LOW so the shop windows and the
	glass showcases behind them read from the plaza:
	  ShopFront      Tobin's Sell stall south of the SHOP's door lane at the
	                 plaza rim (sellStall below), and the floodlight that
	                 lights the SHOP sign (it faces away from the sun).
	  UpgradesFront  a glowing laser blaster floating over a low
	                 table-display-planet pedestal inside a neon ring (tag
	                 Spin) on the viewer's left, a computer-screen kiosk on
	                 the outer front corner and a purple loot chest at the back
	                 on the right, so the door and the right showcase stay in
	                 view.
	Both leave a walk lane in the middle so players reach the shop counter.
	Local frame: 14 wide, front = -Z (toward the plaza), +X = viewer's left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Fronts = {}

local C = Kit.C

-- Deep glowing ore (orange-gold, never near-white under bloom).
local GLOW_ORE = { C.Molten, Color3.fromRGB(226, 140, 20) }

-- A heap of ore chunks: stone, copper, iron, brass and one or two small
-- glowing pieces in deep molten/gold colors.
local function oreHeap(parent: Instance, center: CFrame, spreadX: number, spreadZ: number, count: number, rng: Rng.Rng, glowCount: number?)
	local colors = { C.Stone, C.Copper, C.Iron, C.Brass, C.StoneDark, C.Copper }
	for i = 1, count do
		local glowing = if glowCount then i <= glowCount else (i == 2 or i == 5)
		local color = if glowing then GLOW_ORE[(i % 2) + 1] else colors[(i - 1) % #colors + 1]
		local s = if glowing then rng:range(0.5, 0.65) * (if glowCount then 1.6 else 1) else rng:range(0.8, 1.2)
		local offset = Vector3.new(rng:range(-spreadX, spreadX), rng:range(0, 0.4), rng:range(-spreadZ, spreadZ))
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

--[[
	Tobin's Sell stall, south of the SHOP's door lane at the plaza rim (the
	door lane and the SHOP's showcases stay clear): at the back the SellBin
	(tag SellBin, child part Intake) as a low gunmetal hopper with an orange
	band and a thick blue neon rim, full of ore and coins; at the front
	Tobin's ore cart on a short stub of rails with the counter laid across
	it (tag SellCounter) and a small brass scale; the big two-faced SELL
	sign box (6 x 2.4, a gold neon frame, round 2) high on a gunmetal arch
	over the stall's front, facing the plaza; Tobin the Miner behind his
	counter, between the cart and the bin, facing the plaza like the sign
	(customers stand on the plaza side). Everything but the sign arch (model SellSign) stays
	under 5 studs, so the SHOP's windows show over it.
	Local frame: 6.6 wide, 8 deep, front = -Z (the plaza), +X = the
	viewer's left (south, away from the lane).
]]
local function sellStall(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("ShopFront")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- the SellBin at the back: a low gunmetal hopper full of ore and coins
	local bin = Style.model("SellBin", m)
	local bx, bz = 0.5, 2.25
	local w, d = 5.2, 3.5
	local wallH = 2.2
	local wallY = 0.5 + wallH / 2
	local rimY = 0.5 + wallH + 0.06
	Style.block(bin, at(bx, 0.25, bz), Vector3.new(w, 0.5, d), Tech.MetalDark, nil, Style.solid())
	for _, side in { -1, 1 } do
		Style.block(
			bin,
			at(bx, wallY, bz + side * (d / 2 - 0.25)),
			Vector3.new(w, wallH, 0.5),
			Style.vary(Tech.Metal, rng, 0.03),
			nil,
			Style.solid()
		)
		Style.block(
			bin,
			at(bx + side * (w / 2 - 0.25), wallY, bz),
			Vector3.new(0.5, wallH, d - 1),
			Style.vary(Tech.Metal, rng, 0.03),
			nil,
			Style.solid()
		)
		-- the Kenney orange band and the thick blue neon rim
		Kit.bit(bin, at(bx, 1.0, bz + side * (d / 2 + 0.03)), Vector3.new(w - 1.2, 0.45, 0.1), Tech.Band)
		Tech.glow(bin, at(bx, rimY, bz + side * (d / 2 - 0.25)), Vector3.new(w, Tech.TUBE, 0.6), Tech.Tube)
		Tech.glow(bin, at(bx + side * (w / 2 - 0.25), rimY, bz), Vector3.new(0.6, Tech.TUBE, d - 1), Tech.Tube)
	end
	-- (round 2: filled up to the rim with coins and four glowing ore chunks)
	local coins = Kit.block(bin, at(bx, 2.15, bz), Vector3.new(w - 1.2, 0.3, d - 1.2), C.Brass, Kit.METAL, Style.tiny())
	coins.Name = "Coins"
	oreHeap(bin, at(bx, 2.55, bz), 1.4, 0.9, 6, rng, 4)
	local intake = Kit.block(bin, at(bx, 2.6, bz - 0.3), Vector3.new(4.6, 5, 4.5), C.Gold, nil, {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	intake.Name = "Intake"
	Kit.tag(bin, "SellBin")
	bin.PrimaryPart = intake

	-- Tobin's ore cart at the front on a short stub of rails that ends under
	-- it, the counter across its front (tag SellCounter), a small brass scale
	local cx, cz = 0.9, -2.5
	-- (narrow gauge: two iron rails on three sleepers, ending under the cart)
	for _, x in { -1.1, 0, 1.1 } do
		Kit.bit(m, at(cx + x, 0.08, cz), Vector3.new(0.45, 0.16, 2.2), C.WoodDark)
	end
	for _, z in { -0.75, 0.75 } do
		Kit.bit(m, at(cx, 0.24, cz + z), Vector3.new(3.0, 0.16, 0.2), C.Iron, Kit.METAL)
	end
	Style.block(m, at(cx, 1.4, cz), Vector3.new(2.8, 1.4, 2.2), Tech.Metal, nil, Style.solid())
	Kit.bit(m, at(cx, 2.22, cz), Vector3.new(3.0, 0.3, 2.4), Tech.MetalLight, Kit.METAL)
	Kit.bit(m, at(cx, 1.3, cz - 1.13), Vector3.new(2.3, 0.4, 0.1), Tech.Band)
	for _, x in { -0.9, 0.9 } do
		for _, z in { -1.2, 1.2 } do
			Tech.faceDisc(m, at(cx + x, 0.65, cz + z), 0.3, 1.1, Tech.MetalDeep)
		end
	end
	oreHeap(m, at(cx + 0.3, 2.45, cz + 0.4), 0.8, 0.35, 4, rng)
	local counter = Style.block(m, at(cx, 2.55, cz - 0.85), Vector3.new(3.0, 0.3, 1.1), Tech.MetalLight, nil, Style.solid())
	counter.Name = "SellCounter"
	Kit.tag(counter, "SellCounter")
	Tech.glow(m, at(cx, 2.53, cz - 1.42), Vector3.new(3.0, 0.2, 0.1), Tech.Neon)
	-- the small brass scale on the counter's lane end, a nugget on one pan
	local sx, sz = cx - 0.9, cz - 0.85
	Kit.bit(m, at(sx, 2.8, sz), Vector3.new(0.7, 0.2, 0.5), C.Brass)
	Kit.bit(m, at(sx, 3.3, sz), Vector3.new(0.16, 0.9, 0.16), C.Brass)
	Kit.bit(m, at(sx, 3.76, sz), Vector3.new(1.4, 0.14, 0.14), C.Brass)
	for _, x in { -0.6, 0.6 } do
		Kit.bit(m, at(sx + x, 3.38, sz), Vector3.new(0.55, 0.08, 0.55), C.Brass)
	end
	local nugget = Kit.glow(m, at(sx - 0.6, 3.52, sz), Vector3.new(0.26, 0.2, 0.26), C.Molten)
	nugget.Name = "StallLamp"
	Style.light(nugget, C.LampAmber, 12, 0.9)
	Kit.disc(m, at(cx + 0.9, 2.9, sz).Position, 0.4, 0.5, C.Gold, nil, Style.tiny())

	-- the big two-faced SELL sign box high on a gunmetal arch over the
	-- stall's front (round 2: 6 x 2.4, a gold neon frame, not the SHOP's
	-- blue), facing the plaza on both faces
	local arch = Style.model("SellSign", m)
	local mz = -3.35
	for _, x in { -2.85, 2.85 } do
		Style.block(arch, at(x, 2.9, mz + 0.35), Vector3.new(0.45, 5.8, 0.45), Tech.MetalDark, nil, Style.decor())
	end
	Tech.sign(arch, at(0, 7.0, mz), "SELL", 5.6, 2.4, {
		CasingDepth = 0.6,
		Margin = 0.22,
		Lip = 0.16,
		Back = "SELL",
		BackFrame = true,
		Frame = Tech.GoldGlow,
		StudColor = Tech.GoldGlow,
	})

	-- Tobin the Miner behind his cart beside the bin, facing the plaza (the
	-- sign's direction; customers stand at the counter on the plaza side):
	-- hard hat with a small amber head lamp, a ginger beard, copper shirt and
	-- brown overalls
	Kit.npc(m, at(0.9, 0, -0.4), {
		Name = "Tobin",
		Tag = "Tobin the Miner",
		Shirt = C.Copper,
		Overalls = C.DirtDark,
		Boots = C.WoodDark,
		Beard = Color3.fromRGB(196, 120, 60), -- ginger
		Helmet = C.LeafYellow,
		HelmetLamp = true,
		HeadScale = 0.85,
		Lens = Color3.fromRGB(255, 150, 50),
	})

	-- a flat metal floor plate under the stall with a warm front edge (no collision)
	Kit.bit(m, at(0, 0.04, -0.3), Vector3.new(6.4, 0.08, 7.6), Tech.MetalDark)
	Tech.glow(m, at(0, 0.06, -4.05), Vector3.new(6.4, 0.08, 0.16), Tech.Warm)

	-- the floodlight that lights the SHOP sign's letters (the sign faces away
	-- from the sun): an invisible anchor high over the stall, in front of the
	-- sign's text, so the light falls evenly on the letters
	local flood = Kit.block(m, at(-2.6, 8.6, 3.2), Vector3.new(0.2, 0.2, 0.2), C.GlowText, nil, Style.tiny({ Transparency = 1 }))
	flood.Name = "SignFlood"
	Style.light(flood, C.GlowText, 18, 2.0)
end

---------------------------------------------------------------- the blaster display

local function blasterDisplay(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("UpgradesFront")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- a low table-display-planet pedestal at the outer front corner (viewer's
	-- left, in front of the gap between the showcases, off their line) with
	-- its ring of neon bars set on its top
	local px, pz = 4.9, -1.5
	local top = Tech.pedestal(m, at(px, 0, pz), 2.8, 1.6, { Neon = Tech.Neon })
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		local r = 0.95
		local seg = top * CFrame.new(r * math.cos(a), 0.1, r * math.sin(a)) * CFrame.Angles(0, -a, 0)
		Tech.glow(m, seg, Vector3.new(0.14, 0.12, 0.8), C.CrystalPurple)
	end
	Kit.bit(m, top * CFrame.new(0, 0.06, 0), Vector3.new(0.6, 0.12, 0.6), Tech.MetalLight)

	-- the laser blaster (Kenney Blaster Kit look, forge palette): floats and
	-- turns, level, about 1.5 studs over the pedestal (round 2: the mount is
	-- raised, the model itself is unchanged)
	local blaster = Style.model("Blaster", m)
	local pivot = at(px, 4.1, pz)
	local orb = Kit.ball(blaster, pivot.Position + Vector3.new(0, -0.95, 0), 0.5, C.CrystalCyan, Kit.NEON)
	orb.Name = "HoverOrb"
	local bf = pivot * CFrame.Angles(0, 0.5, 0)
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

	-- viewer's right: a computer-screen kiosk on the outer front corner (it
	-- stands beside the window instead of in front of it), a purple loot
	-- chest and a crate at the back
	Tech.computer(m, at(-6.0, 0, -2.6), 2.4, Tech.Screen, { Bars = C.FlowerWhite })
	local chest = at(-4.6, 0, 1.9)
	Style.block(m, chest * CFrame.new(0, 0.75, 0), Vector3.new(2.6, 1.5, 1.7), Tech.Metal)
	Style.block(m, chest * CFrame.new(0, 1.75, 0), Vector3.new(2.7, 0.5, 1.8), Tech.MetalLight)
	for _, x in { -0.85, 0.85 } do
		Kit.bit(m, chest * CFrame.new(x, 1.0, 0), Vector3.new(0.25, 2.05, 1.85), C.AwningPurple)
	end
	Tech.glow(m, chest * CFrame.new(0, 1.42, -0.9), Vector3.new(2.4, 0.2, 0.08), C.CrystalPurple)
	Kit.glow(m, chest * CFrame.new(-0.4, 2.15, 0) * CFrame.Angles(0.3, 0.6, 0.2), Vector3.new(0.5, 0.4, 0.5), C.Gold)
	Kit.glow(m, chest * CFrame.new(0.45, 2.1, 0.1) * CFrame.Angles(0.2, 0.2, 0.4), Vector3.new(0.45, 0.35, 0.45), C.CrystalCyan)
	Kit.crate(m, at(-6.3, 0, 3.0), 1.6, rng, Tech.MetalLight)
end

function Fronts.build(parent: Instance, rng: Rng.Rng)
	sellStall(parent, rng)
	blasterDisplay(parent, rng)
end

return Fronts
