--[[
	BackpackShopDecor: the small things of the BACKPACKS shop (owner
	2026-10-24: "more details and decorations, more lights and effects").
	The server builds the shop's shell (Lobby/Districts/Backpacks: walls,
	gateway, sign, roof, counter, the display markers); every client builds
	these while its camera is near (BackpackWearController), so they cost
	the map and the phones' streaming nothing:
	  - two royal blue rune banners with gold edges and a teal gem on the
	    front wall, two warm sign lamps under the BACKPACKS board, the rune
	    crest between two teal neon strips on each side wall outside
	  - two hanging lanterns inside (their PointLights start off: the
	    controller lights them on a PC near the shop)
	  - a teal rug with a gold border, the big rune crest behind the
	    shopkeeper (a gold ring round a glowing teal crystal, like the
	    owner's reference backpack)
	  - crates and a bedroll shelf in the back corners, a barrel and a rope
	    coil, gold brackets under the racks, two trail maps on the walls
	  - a coin pile, a ledger and a bell on the counter
	  - planters at the porch, gold dust drifting in the gateway (one
	    emitter, off until the controller turns the effects on)
	Layout is the shop's local frame shared with the server builder: origin
	= the footprint's ground center, front = -Z (the gateway), +Y up.
	Pure (only creates Instances), so the Lune tests and previews run it.
]]

local Geo = require(script.Parent.Geo)

local BackpackShopDecor = {}

BackpackShopDecor.FrameAttribute = "ShopFrame" -- on the stall model: the shop's frame (CFrame)
BackpackShopDecor.MaxParts = 120
BackpackShopDecor.ShowRange = 30 -- studs from the camera to the shop: the clients build the decor (the DROPPERS door stays clear)
BackpackShopDecor.LightName = "ShopLanternLight"

BackpackShopDecor.Layout = {
	Floor = 0.8, -- the floor's top
	Wall = 10, -- the walls' height over the floor
	Width = 17.6, -- outside, along local X (owner: "a bit wider", 15.6 -> 17.6)
	Wall0 = 0.8, -- the walls' thickness
	FrontZ = -2.6, -- the front wall's middle
	BackZ = 5.4, -- the back wall's middle
	PorchZ = -5.0, -- the porch floor's front edge
	Gate = 9, -- the gateway frame's width
	Opening = Vector2.new(7.2, 6.8), -- the walk-in opening (width, height)
	CounterZ = 2.0, -- the counter's middle
	KeeperZ = 3.9, -- where the shopkeeper's feet stand (on a step 1 stud up)
	Racks = { -1.0, 1.4, 3.8 }, -- the side wall racks' pack spots (local z)
	BannerX = 6.1,
}

local rgb = Color3.fromRGB
local GOLD = rgb(255, 196, 64)
local GOLD_GLOW = rgb(200, 116, 14)
local TEAL = rgb(16, 176, 168)
local TEAL_DARK = rgb(14, 92, 96)
local ROYAL = rgb(38, 70, 170)
local NAVY = rgb(18, 22, 54)
local WOOD = rgb(150, 98, 56)
local WOOD_DARK = rgb(96, 60, 34)
local IRON = rgb(58, 60, 72)
local PAPER = rgb(236, 220, 176)
local LEAF = rgb(70, 160, 60)
local LEAF_LIGHT = rgb(120, 200, 80)
local WARM = rgb(255, 170, 70)
local NEON = Enum.Material.Neon
local FABRIC = Enum.Material.Fabric

local DECOR = { CanCollide = false, CanTouch = false, CanQuery = false }
local TINY = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }

local function props(base: { [string]: any }): { [string]: any }
	local copy = {}
	for k, v in base do
		copy[k] = v
	end
	return copy
end

function BackpackShopDecor.build(frame: CFrame): Model
	local L = BackpackShopDecor.Layout
	local P = L.Floor
	local m = Instance.new("Model")
	m.Name = "BackpackShopDecor"
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local function block(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, tiny: boolean?): Part
		return Geo.block(m, cf, size, color, material, props(if tiny then TINY else DECOR))
	end
	-- a cylinder lying along the frame's X axis
	local function roll(cf: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?): Part
		local p = block(cf, Vector3.new(length, diameter, diameter), color, material, true)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- a cylinder standing up
	local function drum(cf: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material?): Part
		return roll(cf * CFrame.Angles(0, 0, math.pi / 2), height, diameter, color, material)
	end
	-- a disc facing the frame's -Z
	local function face(cf: CFrame, thickness: number, diameter: number, color: Color3, material: Enum.Material?): Part
		return roll(cf * CFrame.Angles(0, math.pi / 2, 0), thickness, diameter, color, material)
	end

	---------------------------------------------------------------- the front
	-- royal blue rune banners on the front wall either side of the gateway
	local zf = L.FrontZ - L.Wall0 / 2 -- the front wall's face
	for _, sx in { -1, 1 } do
		local x = sx * L.BannerX
		block(at(x, P + 8.95, zf - 0.2), Vector3.new(1.9, 0.2, 0.2), GOLD, nil, true)
		block(at(x, P + 6.6, zf - 0.12), Vector3.new(1.4, 4.6, 0.12), ROYAL, FABRIC)
		block(at(x, P + 4.3, zf - 0.12) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.99, 0.99, 0.12), ROYAL, FABRIC, true)
		for _, ex in { -1, 1 } do
			block(at(x + ex * 0.66, P + 6.6, zf - 0.2), Vector3.new(0.1, 4.4, 0.06), GOLD_GLOW, NEON, true)
		end
		block(at(x, P + 7.5, zf - 0.19) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.72, 0.72, 0.06), GOLD, nil, true)
		block(at(x, P + 7.5, zf - 0.24) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.46, 0.46, 0.06), TEAL, NEON, true)
	end
	-- two warm lamps under the sign board, lighting it from below
	for _, sx in { -1, 1 } do
		block(at(sx * 2.6, P + 7.05, zf - 1.0), Vector3.new(0.18, 0.18, 0.9), IRON, nil, true)
		block(at(sx * 2.6, P + 7.15, zf - 1.42), Vector3.new(0.45, 0.3, 0.3), WARM, NEON, true)
	end
	-- planters at the porch's front corners
	for _, sx in { -1, 1 } do
		local x = sx * 6.9
		block(at(x, 0.4, L.PorchZ - 0.45), Vector3.new(1.2, 0.8, 0.9), IRON)
		block(at(x, 1.0, L.PorchZ - 0.45), Vector3.new(1.0, 0.6, 0.75), LEAF, nil, true)
		block(at(x + sx * 0.15, 1.45, L.PorchZ - 0.5), Vector3.new(0.6, 0.45, 0.5), LEAF_LIGHT, nil, true)
	end
	-- gold dust drifting in the gateway (the emitter starts off)
	local dust = block(at(0, P + 3.4, L.FrontZ), Vector3.new(L.Opening.X - 0.6, L.Opening.Y - 0.8, 0.2), GOLD, nil, true)
	dust.Name = "GateDust"
	dust.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "GateDust"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(GOLD, rgb(255, 240, 190))
	emitter.LightEmission = 1
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.5, 0.22), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(2, 3.5)
	emitter.Rate = 5
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.25, 0)
	emitter.Enabled = false
	emitter.Parent = dust

	-- on each side wall outside: the rune crest (seen from the spawn and the
	-- plaza road) between two teal neon strips
	local zMid = (L.FrontZ + L.BackZ) / 2
	for _, sx in { -1, 1 } do
		local wallX = sx * (L.Width / 2 + 0.01)
		-- a frame on the wall's outside face, its front (-Z) turned outward
		local crest = at(wallX, P + 4.6, zMid + 0.4) * CFrame.Angles(0, -sx * math.pi / 2, 0)
		block(crest, Vector3.new(3.6, 3.6, 0.08), NAVY, nil, true)
		face(crest * CFrame.new(0, 0, -0.05), 0.06, 3.0, GOLD)
		face(crest * CFrame.new(0, 0, -0.08), 0.06, 2.3, TEAL, NEON)
		block(
			crest * CFrame.new(0, 0, -0.12) * CFrame.Angles(0, 0, math.pi / 4),
			Vector3.new(0.7, 0.7, 0.04),
			rgb(220, 255, 250),
			NEON,
			true
		)
		for _, ez in { -1, 1 } do
			block(crest * CFrame.new(ez * 3.1, 0.6, -0.04), Vector3.new(0.18, 6.4, 0.06), TEAL, NEON, true)
		end
	end

	---------------------------------------------------------------- inside
	-- the rug: teal with a gold border
	block(at(0, P + 0.02, -0.6), Vector3.new(6.6, 0.04, 3.4), GOLD, nil, true)
	block(at(0, P + 0.04, -0.6), Vector3.new(6.2, 0.04, 3.0), TEAL_DARK, FABRIC, true)
	-- two hanging lanterns (lights off until the controller lights them)
	for _, sx in { -1, 1 } do
		local x, z = sx * 3.4, 0.2
		block(at(x, P + 9.5, z), Vector3.new(0.12, 1.0, 0.12), IRON, nil, true)
		block(at(x, P + 8.95, z), Vector3.new(0.9, 0.18, 0.9), IRON, nil, true)
		local glow = block(at(x, P + 8.5, z), Vector3.new(0.7, 0.7, 0.7), WARM, NEON, true)
		block(at(x, P + 8.08, z), Vector3.new(0.8, 0.14, 0.8), IRON, nil, true)
		local light = Instance.new("PointLight")
		light.Name = BackpackShopDecor.LightName
		light.Color = rgb(255, 200, 140)
		light.Range = 11
		light.Brightness = 0.9
		light.Shadows = false
		light.Enabled = false
		light.Parent = glow
	end
	-- the rune crest behind the shopkeeper: a navy board in a gold frame, a
	-- gold ring round a glowing teal crystal (the reference backpack's gem)
	local zb = L.BackZ - L.Wall0 / 2 -- the back wall's inner face
	local cy = P + 7.8
	block(at(0, cy, zb - 0.05), Vector3.new(4.6, 4.2, 0.1), NAVY)
	for _, sy in { -1, 1 } do
		block(at(0, cy + sy * 2.1, zb - 0.12), Vector3.new(4.9, 0.25, 0.12), GOLD, nil, true)
	end
	for _, sx in { -1, 1 } do
		block(at(sx * 2.33, cy, zb - 0.12), Vector3.new(0.25, 4.2, 0.12), GOLD, nil, true)
	end
	face(at(0, cy, zb - 0.16), 0.12, 3.0, GOLD)
	face(at(0, cy, zb - 0.22), 0.1, 2.3, TEAL, NEON)
	block(at(0, cy, zb - 0.3) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.7, 0.7, 0.08), rgb(220, 255, 250), NEON, true)
	-- the back-left corner: two crates under the pack shelf
	local function crate(base: CFrame, s: number)
		block(base * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), WOOD)
		block(base * CFrame.new(0, s - 0.06, 0), Vector3.new(s + 0.06, 0.12, s + 0.06), WOOD_DARK, nil, true)
		block(base * CFrame.new(0, s / 2, -s / 2 - 0.02), Vector3.new(s * 0.86, 0.14, 0.04), WOOD_DARK, nil, true)
	end
	crate(at(-5.6, P, 4.2), 1.3)
	crate(at(-4.5, P, 4.35) * CFrame.Angles(0, math.rad(12), 0), 0.9)
	-- the back-right corner: a shelf of bedrolls, a barrel and a rope coil under it
	block(at(4.5, P + 3.5, 4.55), Vector3.new(2.4, 0.2, 0.9), WOOD_DARK)
	for k, color in { rgb(176, 52, 46), rgb(62, 110, 176), rgb(70, 140, 70) } do
		local y = P + 3.6 + 0.3 + (if k == 3 then 0.55 else 0)
		local x = 4.5 + (if k == 1 then -0.55 elseif k == 2 then 0.55 else 0)
		roll(at(x, y, 4.55), 1.0, 0.6, color, FABRIC)
		block(at(x, y, 4.55), Vector3.new(0.12, 0.64, 0.64), rgb(120, 78, 40), nil, true)
	end
	drum(at(5.6, P + 0.65, 4.3), 1.3, 1.0, WOOD)
	for _, y in { 0.25, 1.05 } do
		drum(at(5.6, P + y, 4.3), 0.12, 1.06, IRON)
	end
	drum(at(4.4, P + 0.12, 4.4), 0.24, 0.9, rgb(196, 160, 110))
	drum(at(4.4, P + 0.2, 4.4), 0.1, 0.5, rgb(120, 90, 60))
	-- gold brackets under the side racks, a trail map above each rack
	for _, sx in { -1, 1 } do
		local wall = sx * (L.Width / 2 - L.Wall0)
		for _, z in L.Racks do
			block(at(wall - sx * 0.3, P + 2.55, z), Vector3.new(0.6, 0.5, 0.12), GOLD, nil, true)
		end
		local map = at(wall - sx * 0.06, P + 6.9, 1.4) * CFrame.Angles(0, -sx * math.pi / 2, 0)
		block(map, Vector3.new(2.4, 1.6, 0.06), WOOD_DARK, nil, true)
		block(map * CFrame.new(0, 0, -0.05), Vector3.new(2.1, 1.3, 0.04), PAPER, nil, true)
	end
	-- on the counter: a coin pile, a ledger and a bell
	local top = P + 3.0
	local cz = L.CounterZ
	for k, q in { { 2.3, 0.35 }, { 2.7, 0.25 }, { 2.0, 0.2 } } do
		drum(at(q[1], top + q[2] / 2, cz - 0.1 + k * 0.12), q[2], 0.42, GOLD)
	end
	block(at(-2.3, top + 0.1, cz), Vector3.new(0.9, 0.2, 0.65), rgb(120, 40, 36), nil, true)
	block(at(-2.3, top + 0.21, cz), Vector3.new(0.82, 0.04, 0.58), PAPER, nil, true)
	drum(at(0.9, top + 0.05, cz - 0.4), 0.1, 0.5, IRON)
	local bell = block(at(0.9, top + 0.24, cz - 0.4), Vector3.new(0.36, 0.3, 0.36), GOLD, nil, true)
	bell.Shape = Enum.PartType.Ball

	return m
end

return BackpackShopDecor
