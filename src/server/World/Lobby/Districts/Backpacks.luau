--[[
	BACKPACKS: the backpack shop (owner 2026-10-24: "Nový stánek v lobby",
	coins only; then "in place of the ROCK SCANNER in front of the Vault,
	more details, bigger like a shop, a shopkeeper at the counter, more
	lights and effects"). A small walk-in shop at the end of the ToScanner
	path, its gateway to the path, in the Districts' dark metal and neon
	look with the backpacks' colours (teal neon, gold, royal blue):
	  - a floor with a teal front edge and a lit step, a porch with two round
	    plinths for the Runebound and the Emberforge packs
	  - dark front walls either side of a gold-framed gateway (a teal neon
	    frame, a second one set back in the opening), the BACKPACKS board
	    over it with teal tubes
	  - side and back walls with the orange band, a roof with a parapet,
	    crenels and teal tubes; two corner pillars with warm lantern cubes
	  - on the roof a podium with neon rings: the giant Starforge pack on it is
	    the shop's emblem (it turned slowly until the owner said no, 2026-10-25)
	  - inside: racks on both side walls (three packs each), a shelf in the
	    back-left corner (the Amethyst pack), the counter (its warm top is
	    the BasePart tagged BackpackCounter with the Attachment
	    BackpackPromptPoint on the customer side: BackpackService puts the
	    "Backpacks" prompt there) and the shopkeeper's step behind it (the
	    Attachment KeeperFeet on the counter: where a golem's feet stand,
	    facing the customers; ShopkeeperConfig.mark), one warm light
	The ten packs are NOT map parts: the plates they stand on carry the
	attribute BackpackId (no tag: Plaza Life keeps its miners off tagged
	parts) and every client finds them through the counter's model and
	builds the packs while it is near (BackpackWearController; the roof's
	plate adds DisplayScale and DisplaySpin). The small things (banners,
	lanterns, crates, the crest, the rug, the counter's coins) are built by
	the clients too (Builders/BackpackShopDecor, from the model's ShopFrame
	attribute). Local frame: BackpackShopDecor.Layout (front = -Z toward
	the path); every part stays inside the 18 x 16 x 12 footprint
	(tests/LobbyDistricts.spec.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BackpackShopDecor = require(Shared.Builders.BackpackShopDecor)
local ShopkeeperConfig = require(Shared.Config.ShopkeeperConfig)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Backpacks = {}

Backpacks.CounterTag = "BackpackCounter"
Backpacks.PromptPoint = "BackpackPromptPoint"
Backpacks.KeeperFeet = "KeeperFeet" -- Attachment on the counter: the shopkeeper's feet, facing the customers
Backpacks.DisplayAttribute = "BackpackId" -- (BackpackWearController: the shop's display markers)
-- what stands where (every pack once): the porch plinths, the side racks
-- (front to back), the back-left shelf and the roof
Backpacks.Displays = {
	PorchLeft = "RuneboundPack",
	PorchRight = "EmberforgePack",
	RackLeft = { "RookiePack", "TrailPack", "LeatherRucksack" },
	RackRight = { "MinersPack", "IronboundPack", "ExplorersPack" },
	Shelf = "AmethystPack",
	Roof = "StarforgePack",
}
-- the golem by the porch (LobbyLayout piece BackpackGolem) and the pack on its back
Backpacks.Golem = {
	Pack = "RuneboundPack",
	Size = 2.3,
	Range = 28, -- (with the clients' hysteresis the DROPPERS door, ~39 studs away, stays clear of it)
	Look = {
		Body = Color3.fromRGB(176, 182, 196),
		Accent = Color3.fromRGB(92, 96, 116),
		Eyes = Color3.fromRGB(16, 176, 168),
		Gem = Color3.fromRGB(16, 176, 168),
	},
}
Backpacks.RoofScale = 2.8 -- the roof emblem's size against a normal pack (owner: a big turning pack on the roof)
Backpacks.RoofSpin = 0 -- radians per second (owner 2026-10-25: it stands still)
-- how near the player must be for the clients to build each display pack
-- (studs from the player's HumanoidRootPart, dropped again beyond the range +
-- BackpackShopDecor.Hysteresis: the phones' budget spots, the spawn and the DROPPERS
-- door ~39 studs from the porch, stay at least 3 studs clear of them even after a
-- visit, tests/Backpacks.spec.luau): the roof emblem, the porch, inside. (The inside
-- plates and the golem's also carry DisplayLite: phones show those packs without
-- their small details, inside the shop too.)
Backpacks.Ranges = { Roof = 36, Porch = 30, Inside = 28 }

local rgb = Color3.fromRGB
local TEAL = rgb(16, 176, 168) -- deep enough to stay teal under bloom
local GOLD = rgb(255, 196, 64)
local NAVY = rgb(18, 22, 54)
local WOOD = rgb(176, 120, 72)

local function display(part: BasePart, packId: string)
	part:SetAttribute(Backpacks.DisplayAttribute, packId)
end

function Backpacks.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("BackpackStall")
	local m = Style.model(piece.Id, parent)
	local L = BackpackShopDecor.Layout
	local P, H = L.Floor, L.Wall
	local hw = L.Width / 2
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function block(c: CFrame, size: Vector3, color: Color3, material: Enum.Material?, tiny: boolean?): Part
		return Style.block(m, c, size, color, material, if tiny then Style.tiny() else Style.solid())
	end
	local function glow(c: CFrame, size: Vector3, color: Color3): Part
		return Tech.glow(m, c, size, color)
	end
	local function plate(c: CFrame, size: number, packId: string, name: string, range: number): Part
		local p = Style.block(m, c, Vector3.new(size, 0.14, size), Tech.MetalLight, nil, Style.decor())
		p.Name = name
		display(p, packId)
		p:SetAttribute("DisplayRange", range)
		if range == Backpacks.Ranges.Inside then
			-- (phones show the inside packs without their small details, inside the shop too)
			p:SetAttribute("DisplayLite", true)
		end
		return p
	end

	---------------------------------------------------------------- the floor and the porch
	local zFront, zBack = L.FrontZ, L.BackZ
	local porch = L.PorchZ
	local floorD = (zBack + L.Wall0 / 2 + 0.1) - porch
	block(at(0, P / 2, porch + floorD / 2), Vector3.new(L.Width, P, floorD), Style.vary(Tech.MetalDark, rng, 0.03))
	glow(at(0, P - 0.2, porch - 0.04), Vector3.new(L.Width - 0.4, 0.16, 0.12), TEAL)
	block(at(0, 0.27, porch - 0.45), Vector3.new(L.Gate, 0.54, 0.9), Tech.Metal)
	glow(at(0, 0.42, porch - 0.92), Vector3.new(L.Gate - 0.4, 0.08, 0.06), TEAL)
	-- the porch plinths: a round foot, a teal ring, the square plate (the marker)
	for _, spec in { { Side = -1, Pack = Backpacks.Displays.PorchLeft }, { Side = 1, Pack = Backpacks.Displays.PorchRight } } do
		local base = at(spec.Side * 6.3, P, -4.1)
		Tech.disc(m, (base * CFrame.new(0, 0.55, 0)).Position, 1.1, 1.8, Tech.Metal, nil, Style.solid())
		Tech.disc(m, (base * CFrame.new(0, 1.15, 0)).Position, 0.1, 1.9, TEAL, Kit.NEON, Style.tiny())
		plate(base * CFrame.new(0, 1.27, 0), 1.5, spec.Pack, "DisplayPlinth", Backpacks.Ranges.Porch)
	end

	---------------------------------------------------------------- the walls
	local segW = (L.Width - L.Gate) / 2
	for _, sx in { -1, 1 } do
		Tech.wall(m, at(sx * (L.Gate + segW) / 2, P, zFront), segW, H, L.Wall0, {
			Color = Tech.MetalDark,
			Band = false,
			Foot = false,
			TopNeon = TEAL,
		})
	end
	-- the gateway: a gold frame with teal neon, a second teal frame set back in the opening
	local ow, oh = L.Opening.X, L.Opening.Y
	Tech.doorFrame(m, at(0, P, zFront), L.Gate, H, L.Wall0 + 0.4, {
		Color = Tech.MetalDark,
		OpeningWidth = ow,
		OpeningHeight = oh,
		Frame = GOLD,
		Neon = TEAL,
	})
	for _, sx in { -1, 1 } do
		glow(at(sx * (ow / 2 - 0.2), P + oh / 2, zFront + 0.75), Vector3.new(0.22, oh - 0.2, 0.22), TEAL)
	end
	glow(at(0, P + oh - 0.2, zFront + 0.75), Vector3.new(ow - 0.3, 0.22, 0.22), TEAL)
	-- the side and back walls, the orange band round them outside
	local sideD = zBack - zFront
	local zMid = (zBack + zFront) / 2
	for _, sx in { -1, 1 } do
		block(at(sx * (hw - L.Wall0 / 2), P + H / 2, zMid), Vector3.new(L.Wall0, H, sideD), Tech.MetalDark)
		Kit.bit(m, at(sx * (hw + 0.03), P + H * 0.62, zMid), Vector3.new(0.06, 0.9, sideD), Tech.Band)
	end
	block(at(0, P + H / 2, zBack), Vector3.new(L.Width, H, L.Wall0), Tech.MetalDark)
	Kit.bit(m, at(0, P + H * 0.62, zBack + L.Wall0 / 2 + 0.03), Vector3.new(L.Width, 0.9, 0.06), Tech.Band)

	---------------------------------------------------------------- the roof
	local top = P + H
	local roofD = zBack - zFront + L.Wall0 + 0.2
	block(at(0, top + 0.3, zMid), Vector3.new(L.Width, 0.6, roofD), Tech.MetalDeep)
	glow(at(0, top + 0.3, zMid + roofD / 2 - 0.02), Vector3.new(L.Width - 0.4, Tech.TUBE, 0.1), TEAL)
	for _, sx in { -1, 1 } do
		glow(at(sx * (hw - 0.02), top + 0.3, zMid), Vector3.new(0.1, Tech.TUBE, roofD - 0.4), TEAL)
	end
	-- the parapet over the front with teal tube and crenels
	block(at(0, top + 1.2, zFront - 0.1), Vector3.new(L.Width - 2.4, 1.2, 0.8), Tech.Metal)
	glow(at(0, top + 1.62, zFront - 0.52), Vector3.new(L.Width - 2.6, Tech.TUBE, 0.12), TEAL)
	for _, x in { -6.6, -4.6, 4.6, 6.6 } do
		block(at(x, top + 2.25, zFront - 0.1), Vector3.new(1.2, 0.9, 0.8), Tech.Metal)
	end
	-- the corner pillars with warm lantern cubes
	for _, sx in { -1, 1 } do
		local x, ph = sx * (hw - 0.9), H + 2.6
		block(at(x, P + ph / 2, zFront), Vector3.new(1.2, ph, 1.2), Tech.Metal)
		for _, ex in { -1, 1 } do
			glow(at(x + ex * 0.6, P + 2 + (ph - 3) / 2, zFront - 0.6), Vector3.new(Tech.TUBE, ph - 3, Tech.TUBE), TEAL)
		end
		local ly = P + ph + 0.05
		block(at(x, ly + 0.8, zFront), Vector3.new(1.6, 1.6, 1.6), Tech.MetalDark)
		glow(at(x, ly + 0.8, zFront - 0.82), Vector3.new(1.0, 1.0, 0.06), Tech.Warm)
		block(at(x, ly + 1.75, zFront), Vector3.new(1.8, 0.3, 1.8), Tech.MetalLight, nil, true)
	end
	-- the roof podium, two round tiers with teal rings: the giant turning Starforge pack stands on its plate
	local podium = at(0, top + 0.6, zMid - 1.6)
	Tech.disc(m, (podium * CFrame.new(0, 0.4, 0)).Position, 0.8, 4.0, Tech.Metal, nil, Style.solid())
	Tech.disc(m, (podium * CFrame.new(0, 0.5, 0)).Position, 0.12, 4.2, TEAL, Kit.NEON, Style.tiny())
	Tech.disc(m, (podium * CFrame.new(0, 1.2, 0)).Position, 0.8, 3.0, Tech.MetalDark, nil, Style.solid())
	Tech.disc(m, (podium * CFrame.new(0, 1.3, 0)).Position, 0.12, 3.2, TEAL, Kit.NEON, Style.tiny())
	local roof = plate(podium * CFrame.new(0, 1.67, 0), 2.4, Backpacks.Displays.Roof, "DisplayRoof", Backpacks.Ranges.Roof)
	roof:SetAttribute("DisplayScale", Backpacks.RoofScale)
	if Backpacks.RoofSpin ~= 0 then
		roof:SetAttribute("DisplaySpin", Backpacks.RoofSpin)
	end

	---------------------------------------------------------------- the sign
	local signY = P + oh + 1.6
	block(at(0, signY, zFront - 0.9), Vector3.new(L.Gate - 0.4, 2.6, 0.4), NAVY, nil, true)
	for _, sy in { -1, 1 } do
		glow(at(0, signY + sy * 1.25, zFront - 1.12), Vector3.new(L.Gate - 0.4, Tech.TUBE, 0.14), TEAL)
	end
	Style.sign(m, at(0, signY + 0.05, zFront - 1.14), "BACKPACKS", L.Gate - 0.8, 2.0, {
		Kind = "Glow",
		Frame = false,
		BoardColor = NAVY,
		Depth = 0.08,
		TextColor = Color3.new(1, 1, 1),
		StrokeColor = TEAL,
		StrokeTransparency = 0.2,
	})

	---------------------------------------------------------------- inside
	-- the side racks: a shelf on each wall, a plate per pack facing into the shop
	local rackY = P + 2.9
	local inner = hw - L.Wall0
	for _, spec in { { Side = -1, Packs = Backpacks.Displays.RackLeft }, { Side = 1, Packs = Backpacks.Displays.RackRight } } do
		local sx = spec.Side
		block(at(sx * (inner - 0.55), rackY, zMid + 0.2), Vector3.new(1.1, 0.2, sideD - L.Wall0 - 0.4), Tech.MetalLight, nil, true)
		for k, z in L.Racks do
			-- (the plate's front = toward the middle of the shop)
			plate(
				at(sx * (inner - 0.6), rackY + 0.17, z) * CFrame.Angles(0, sx * math.pi / 2, 0),
				1.2,
				spec.Packs[k],
				"DisplayRack",
				Backpacks.Ranges.Inside
			)
		end
	end
	-- the back-left shelf (the back-right one with the bedrolls is the clients' decor)
	local zIn = zBack - L.Wall0 / 2
	block(at(-4.6, P + 3.5, zIn - 0.45), Vector3.new(2.4, 0.2, 0.9), Tech.MetalLight, nil, true)
	plate(at(-4.6, P + 3.67, zIn - 0.5), 1.2, Backpacks.Displays.Shelf, "DisplayShelf", Backpacks.Ranges.Inside)
	-- the counter: a light metal body with a teal stripe, the warm top (the hook)
	local cz = L.CounterZ
	block(at(0, P + 1.35, cz), Vector3.new(7.0, 2.7, 1.4), Tech.MetalLight)
	glow(at(0, P + 1.9, cz - 0.72), Vector3.new(6.6, 0.16, 0.08), TEAL)
	local counter = block(at(0, P + 2.85, cz), Vector3.new(7.4, 0.3, 1.7), WOOD)
	counter.Name = Backpacks.CounterTag
	Kit.tag(counter, Backpacks.CounterTag)
	local point = Instance.new("Attachment")
	point.Name = Backpacks.PromptPoint
	point.CFrame = CFrame.new(0, 0.15, -0.85) -- the customer side of the top
	point.Parent = counter
	-- the shopkeeper's step behind the counter and its feet on it, facing the customers
	block(at(0, P + 0.5, L.KeeperZ - 0.05), Vector3.new(7.0, 1.0, 2.2), Tech.MetalDeep)
	local feetAt = at(0, P + 1.0, L.KeeperZ)
	local feet = Instance.new("Attachment")
	feet.Name = Backpacks.KeeperFeet
	feet.CFrame = counter.CFrame:ToObjectSpace(feetAt)
	feet:SetAttribute("Shop", "Backpacks")
	feet.Parent = counter
	-- the shopkeeper golem (ShopkeeperConfig.Shops.Backpacks; the clients build it)
	ShopkeeperConfig.mark(counter, feetAt, "Backpacks")
	-- one warm light from the counter
	Style.light(counter, rgb(255, 214, 170), 16, 0.8)

	-- the clients' decor
	m:SetAttribute(BackpackShopDecor.FrameAttribute, cf)
	m.PrimaryPart = counter

	-- the golem by the porch with a pack on its back (an invisible plate behind it:
	-- the clients stand the pack on it, its outer face away from the golem)
	local golemPiece, golemCf = Kit.piece("BackpackGolem")
	local g = Style.model(golemPiece.Id, parent)
	local spec = Backpacks.Golem
	local s = spec.Size
	local golem = Kit.golem(g, golemCf, s, spec.Look)
	golem.Parent = g
	local back = Style.block(
		g,
		golemCf * CFrame.new(0, 0.58 * s - 0.07, 0.425 * s + 0.54) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(1.4, 0.14, 1.0),
		Tech.MetalLight,
		nil,
		Style.ghost()
	)
	back.Name = "GolemPack"
	back.Transparency = 1
	display(back, spec.Pack)
	back:SetAttribute("DisplayRange", spec.Range)
	back:SetAttribute("DisplayLite", true)
	g.PrimaryPart = golem.PrimaryPart
end

return Backpacks
