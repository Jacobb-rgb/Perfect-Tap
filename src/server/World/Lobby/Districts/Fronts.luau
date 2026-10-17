--[[
	The two small set pieces in front of the shop modules, in the same metal
	and neon language (concept v2). Both stay LOW so the shop windows and the
	glass showcases behind them read from the plaza:
	  ShopFront      Tobin's Sell stall next to the SHOP, split to the outer
	                 thirds and pulled toward the plaza: the SellBin (tag
	                 SellBin, child part Intake) as a low gunmetal hopper with
	                 an orange band and a thick blue neon rim, the glowing
	                 SELL sign box on its front wall, Tobin's ore cart on its
	                 rails with a counter (tag SellCounter) and a brass scale,
	                 Tobin the Miner at the cart's outer end.
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
local function oreHeap(parent: Instance, center: CFrame, spreadX: number, spreadZ: number, count: number, rng: Rng.Rng)
	local colors = { C.Stone, C.Copper, C.Iron, C.Brass, C.StoneDark, C.Copper }
	for i = 1, count do
		local glowing = i == 2 or i == 5
		local color = if glowing then GLOW_ORE[(i % 2) + 1] else colors[(i - 1) % #colors + 1]
		local s = if glowing then rng:range(0.5, 0.65) else rng:range(0.8, 1.2)
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

local function sellStall(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("ShopFront")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- the SellBin (outer third, viewer's right, pulled toward the plaza): a
	-- low gunmetal hopper full of ore and coins (its rim 0.5 lower than a
	-- full bin, so the SHOP window behind it shows)
	local bin = Style.model("SellBin", m)
	local bx, bz = -4.35, -0.4
	local w, d = 5.3, 5.6
	local wallH = 2.6
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
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Style.block(bin, at(bx + sx * (w / 2 - 0.35), 1.7, bz + sz * (d / 2 - 0.35)), Vector3.new(0.8, 3.4, 0.8), Tech.MetalLight)
		end
	end
	local coins = Kit.block(bin, at(bx, 1.8, bz), Vector3.new(w - 1.2, 0.3, d - 1.2), C.Brass, Kit.METAL, Style.tiny())
	coins.Name = "Coins"
	oreHeap(bin, at(bx, 2.2, bz), 1.4, 1.7, 6, rng)
	local intake = Kit.block(bin, at(bx, 2.3, bz), Vector3.new(w - 0.7, 5, d - 1.0), C.Gold, nil, {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	intake.Name = "Intake"
	Kit.tag(bin, "SellBin")
	bin.PrimaryPart = intake

	-- the glowing SELL sign box set into the bin's front wall (its top about
	-- flush with the bin's rim)
	Tech.sign(m, at(bx, 1.75, bz - d / 2 - 0.5), "SELL", 3.6, 1.4, { CasingDepth = 0.7 })

	-- Tobin's ore cart on a stub of rails (outer third, viewer's left, pulled
	-- toward the plaza): a metal counter laid across its front (tag
	-- SellCounter) with a brass scale and coin stacks
	local cx, cz = 3.65, -1.6
	Style.rails(m, at(cx - 1.65, 0, cz).Position, at(cx + 1.65, 0, cz).Position)
	Style.block(m, at(cx, 1.6, cz), Vector3.new(3.0, 1.5, 2.6), Tech.Metal, nil, Style.solid())
	Kit.bit(m, at(cx, 2.5, cz), Vector3.new(3.3, 0.35, 2.9), Tech.MetalLight, Kit.METAL)
	Kit.bit(m, at(cx, 1.45, cz - 1.33), Vector3.new(2.5, 0.45, 0.1), Tech.Band)
	for _, x in { -0.95, 0.95 } do
		for _, z in { -1.45, 1.45 } do
			Tech.faceDisc(m, at(cx + x, 0.75, cz + z), 0.35, 1.3, Tech.MetalDeep)
		end
	end
	oreHeap(m, at(cx, 2.75, cz + 0.55), 0.9, 0.4, 5, rng)
	local counter = Style.block(m, at(cx, 2.85, cz - 1.05), Vector3.new(3.3, 0.3, 1.3), Tech.MetalLight, nil, Style.solid())
	counter.Name = "SellCounter"
	Kit.tag(counter, "SellCounter")
	Tech.glow(m, at(cx, 2.83, cz - 1.75), Vector3.new(3.3, 0.22, 0.1), Tech.Neon)
	-- brass scale: base, post, beam, two pans on strings, a small nugget weighed
	local sx, sz = cx - 0.6, cz - 1.05
	Kit.bit(m, at(sx, 3.1, sz), Vector3.new(0.9, 0.2, 0.6), C.Brass)
	Kit.bit(m, at(sx, 3.85, sz), Vector3.new(0.18, 1.3, 0.18), C.Brass)
	Kit.bit(m, at(sx, 4.52, sz), Vector3.new(2.0, 0.16, 0.16), C.Brass)
	for _, x in { -0.9, 0.9 } do
		Kit.bit(m, at(sx + x, 4.15, sz), Vector3.new(0.06, 0.7, 0.06), C.Iron)
		Kit.bit(m, at(sx + x, 3.75, sz), Vector3.new(0.75, 0.1, 0.75), C.Brass)
	end
	-- the nugget on the scale glows and lights the stall (the stall's one light)
	local nugget = Kit.glow(m, at(sx - 0.9, 3.92, sz), Vector3.new(0.3, 0.24, 0.3), C.Molten)
	nugget.Name = "StallLamp"
	Style.light(nugget, C.Lamp, 14, 1.4)
	for i, x in { 0.9, 1.3 } do
		Kit.disc(m, at(cx + x, 3.0 + 0.2 * i, sz).Position, 0.4 * i, 0.55, C.Gold, nil, Style.tiny())
	end

	-- Tobin the Miner at the outer end of his cart, facing the walk lane (so
	-- he stands in front of the SHOP's pylon, not its window): hard hat with
	-- a head lamp, beard, overalls
	Kit.npc(m, at(cx + 2.55, 0, cz) * CFrame.Angles(0, math.pi / 2, 0), {
		Name = "Tobin",
		Tag = "Tobin the Miner",
		Shirt = C.AwningRed,
		Overalls = C.WaterDeep,
		Boots = C.WoodDark,
		Beard = C.StoneLight,
		Helmet = C.LeafYellow,
		HelmetLamp = true,
	})

	-- a flat metal floor plate under the cart and Tobin with a warm front edge (no collision)
	Kit.bit(m, at(cx + 0.8, 0.04, cz + 0.2), Vector3.new(5.1, 0.08, 4.4), Tech.MetalDark)
	Tech.glow(m, at(cx + 0.8, 0.06, cz - 2.05), Vector3.new(5.1, 0.08, 0.16), Tech.Warm)
end

---------------------------------------------------------------- the blaster display

local function blasterDisplay(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("UpgradesFront")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- a low table-display-planet pedestal (viewer's left) inside a ring of neon bars
	local px, pz = 4.9, 0.6
	local top = Tech.pedestal(m, at(px, 0, pz), 2.8, 1.6, { Neon = C.CrystalCyan })
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		local r = 1.75
		local seg = at(px + r * math.cos(a), 2.1, pz + r * math.sin(a)) * CFrame.Angles(0, -a, 0)
		Tech.glow(m, seg, Vector3.new(0.16, 0.16, 1.45), C.CrystalPurple)
	end
	Kit.bit(m, top * CFrame.new(0, 0.06, 0), Vector3.new(0.6, 0.12, 0.6), Tech.MetalLight)

	-- the laser blaster (Kenney Blaster Kit look, forge palette): floats and turns
	local blaster = Style.model("Blaster", m)
	local pivot = at(px, 3.4, pz)
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
