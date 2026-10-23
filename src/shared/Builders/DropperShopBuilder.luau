--[[
	The DROPPERS shop's showroom (owner 2026-10-23: "it must be extremely
	good", "like the chests with the blasters"): the detail every client
	builds inside the lobby's DROPPERS house while its camera is near, like
	the museums' relics (MuseumBuilder): the server keeps the solid shell (the
	walls, the counter with the shop prompt, the display plinths and the hero
	podium; Districts/Droppers.luau), so the map and phone budgets carry the
	structure only.

	Inside, in the Blaster Vault's look:
	  - a dark marble checker floor and a red runner with gold edges and
	    diamonds from the entrance to the counter
	  - dark stone brick walls, timber pilasters with wall torches, a dark
	    ceiling with beams and two candle chandeliers (local PointLights)
	  - the real droppers (DropperBuilder, the owner's picture) on lit
	    plinths, two along each side wall facing the aisle and one either
	    side of the hero on the back wall (cheapest at the entrance), each
	    under a ceiling spot, in front of a backlit wall panel and under a
	    banner in its colour
	  - the DARK MATTER DROPPER, the best one, big on a podium behind the
	    counter in a glowing ring on the back wall, with gold posts and orbs
	  - the counter: gold trim, the DROPPERS plate, a till, a bell, coin
	    stacks and a small MONEY LASER (LaserBuilder) on it, and the Dropper
	    Master (the shopkeeper) behind it
	  - ore crystal shelves either side of the entrance, an open chest of
	    gold and a heap of ore crystals in the back corners
	Outside: stones on the front wall, striped awnings and flower boxes at
	the windows, an OPEN sign, potted bushes by the porch, barrels and crates.

	Frame: the house frame `frame` (the server's attribute FrameAttribute on
	the house model): y 0 = the ground, local +Z = the house's front, the
	shop's floor at Room.Plinth; Room holds the shared sizes the server's
	shell is built from. Every detail part is anchored, non-colliding and
	casts no shadow (the server's plinths and counter give the collisions);
	the showroom keeps its own three PointLights only (phones).

	  show(house, frame)  builds the detail (once) into house.ShopDetail
	  clear(house)        takes it away again
	Pure: only Instance creation (Lune previews and the client both build it).
]]

local Shared = script.Parent.Parent
local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)
local DropperBuilder = require(script.Parent.DropperBuilder)
local LaserBuilder = require(script.Parent.LaserBuilder)
local DropperConfig = require(Shared.Config.DropperConfig)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)

local DropperShopBuilder = {}

DropperShopBuilder.Tag = "DropperShop" -- CollectionService tag on the house model (the clients' loop)
DropperShopBuilder.FrameAttribute = "ShopFrame" -- CFrame attribute on the house model
DropperShopBuilder.DetailName = "ShopDetail"
DropperShopBuilder.ShowDistance = 110 -- studs: clients build the showroom this near the camera
DropperShopBuilder.HideDistance = 140 -- ...and take it away past this

-- The house (studs, in the house frame): W wide, D deep, the front wall at
-- z = Front (LobbyLayout.DroppersFront), a Plinth high floor, a Ground high
-- shop under an Upper floor; the ground floor windows at x = +-WindowX.
DropperShopBuilder.Room = {
	W = 30,
	D = 15,
	Front = LobbyLayout.DroppersFront,
	Plinth = 1,
	Ground = 9,
	Upper = 4.6,
	DoorW = 6,
	DoorH = 7.5,
	WindowX = 9,
	WindowY = 4.4, -- above the floor
	WindowW = 4.6,
	WindowH = 2.8,
}

--[[
	The displays (house frame). Slots: a dropper's plinth center on the floor
	(y = Room.Plinth), its size, its turn (the dropper's front: 0 = to the
	entrance, +-pi/2 = into the aisle) and the wall behind it. Front to back:
	two a side along the side walls, one either side of the hero on the back
	wall, cheapest at the entrance, dearest at the back. The hero (the DARK
	MATTER DROPPER) on its podium in the middle of the back wall; the
	counter in the middle of the shop in front of it.
]]
local ROOM = DropperShopBuilder.Room
local IN_X = ROOM.W / 2 - 1 -- the inner wall faces
local IN_FRONT = ROOM.Front - 0.5
local IN_BACK = ROOM.Front - ROOM.D + 1
DropperShopBuilder.Inner = { X = IN_X, Front = IN_FRONT, Back = IN_BACK }
DropperShopBuilder.PlinthHeight = 0.4
DropperShopBuilder.SideScale = 0.52

export type Slot = { Id: string, Center: Vector3, Size: Vector3, Turn: number, Wall: string }
DropperShopBuilder.Hero = {
	Id = "DarkMatterDropper",
	Scale = 0.7,
	Center = Vector3.new(0, ROOM.Plinth, IN_BACK + 2.9),
	Size = Vector3.new(7.6, 0.6, 5.8),
}
DropperShopBuilder.Counter = {
	Center = Vector3.new(0, ROOM.Plinth, IN_BACK + 5.8 + 2.0),
	Size = Vector3.new(9, 1.5, 1.6),
	Top = 0.25,
}
DropperShopBuilder.Slots = {} :: { Slot }
do
	local ids = {}
	for _, dropper in DropperConfig.List do
		if dropper.Id ~= DropperShopBuilder.Hero.Id then
			table.insert(ids, dropper.Id)
		end
	end
	local side = Vector3.new(4.2, DropperShopBuilder.PlinthHeight, 5)
	local back = Vector3.new(5.2, DropperShopBuilder.PlinthHeight, 4.2)
	local sideX = IN_X - side.X / 2
	local z1 = IN_FRONT - 0.3 - side.Z / 2
	local z2 = z1 - side.Z - 0.4
	local backX = DropperShopBuilder.Hero.Size.X / 2 + 0.4 + back.X / 2
	local places = {
		{ Center = Vector3.new(-sideX, ROOM.Plinth, z1), Size = side, Turn = math.pi / 2, Wall = "Left" },
		{ Center = Vector3.new(sideX, ROOM.Plinth, z1), Size = side, Turn = -math.pi / 2, Wall = "Right" },
		{ Center = Vector3.new(-sideX, ROOM.Plinth, z2), Size = side, Turn = math.pi / 2, Wall = "Left" },
		{ Center = Vector3.new(sideX, ROOM.Plinth, z2), Size = side, Turn = -math.pi / 2, Wall = "Right" },
		{ Center = Vector3.new(-backX, ROOM.Plinth, IN_BACK + back.Z / 2), Size = back, Turn = 0, Wall = "Back" },
		{ Center = Vector3.new(backX, ROOM.Plinth, IN_BACK + back.Z / 2), Size = back, Turn = 0, Wall = "Back" },
	}
	for k, place in places do
		if ids[k] then
			table.insert(
				DropperShopBuilder.Slots,
				{ Id = ids[k], Center = place.Center, Size = place.Size, Turn = place.Turn, Wall = place.Wall }
			)
		end
	end
end

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local FABRIC = Enum.Material.Fabric
local MARBLE = Enum.Material.Marble
local WOOD = Enum.Material.Wood

local C = {
	FloorDark = rgb(40, 36, 52),
	FloorLight = rgb(70, 64, 86),
	Brick = rgb(58, 52, 66),
	Mortar = rgb(86, 80, 96),
	Ceiling = rgb(34, 28, 36),
	Beam = rgb(78, 52, 34),
	Timber = rgb(110, 74, 46),
	Iron = rgb(40, 40, 48),
	Gold = rgb(255, 196, 64),
	GoldDark = rgb(196, 138, 34),
	Red = rgb(180, 34, 40),
	Candle = rgb(250, 240, 220),
	Flame = rgb(255, 200, 96),
	Fire = rgb(255, 140, 32),
	Panel = rgb(30, 28, 40),
	Stone = rgb(56, 61, 80),
	Skin = rgb(236, 186, 140),
	Overalls = rgb(52, 96, 176),
	Shirt = rgb(232, 112, 40),
	Hat = rgb(255, 204, 40),
	Boots = rgb(60, 44, 34),
	Hair = rgb(120, 76, 44),
	Wood = rgb(150, 104, 62),
}

local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function glowOf(id: string): Color3
	local st = DropperBuilder.Styles[id]
	return if st then st.Glow[1] else C.Fire
end

local function quiet(model: Instance)
	for _, d in model:GetDescendants() do
		-- (the showroom's own three lights only: the droppers' and the laser's go, phones)
		if d:IsA("Light") and not d:GetAttribute("ShopLight") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l:SetAttribute("ShopLight", true)
	l.Parent = parent
end

function DropperShopBuilder.show(house: Instance, frame: CFrame): Model
	local old = house:FindFirstChild(DropperShopBuilder.DetailName)
	if old and old:IsA("Model") then
		return old
	end
	local m = Instance.new("Model")
	m.Name = DropperShopBuilder.DetailName
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local function part(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
		return Geo.block(m, cf, size, color, material, table.clone(DECOR))
	end
	local function glow(cf: CFrame, size: Vector3, color: Color3): Part
		return Geo.block(m, cf, size, color, NEON, table.clone(DECOR))
	end
	local floorY = ROOM.Plinth
	local ceilY = ROOM.Plinth + ROOM.Ground
	local depth = IN_FRONT - IN_BACK
	local midZ = (IN_FRONT + IN_BACK) / 2

	---------------------------------------------------------------- the floor
	part(at(0, floorY + 0.03, midZ), Vector3.new(IN_X * 2, 0.06, depth), C.FloorDark, MARBLE)
	local aisle = IN_X - 4.2 -- the side plinths' front edge (|x|)
	local cols, rows = 8, 6
	local tw, td = aisle * 2 / cols, depth / rows
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			if (i + j) % 2 == 0 then
				part(
					at(-aisle + (i + 0.5) * tw, floorY + 0.07, IN_FRONT - (j + 0.5) * td),
					Vector3.new(tw - 0.1, 0.04, td - 0.1),
					C.FloorLight,
					MARBLE
				)
			end
		end
	end
	-- the red runner with gold edges and diamonds, the entrance to the counter
	local counter = DropperShopBuilder.Counter
	local runFrom, runTo = IN_FRONT + 0.5, counter.Center.Z + counter.Size.Z / 2
	local runZ, runL = (runFrom + runTo) / 2, runFrom - runTo
	part(at(0, floorY + 0.11, runZ), Vector3.new(3.2, 0.05, runL), C.Red, FABRIC)
	for _, sx in { -1, 1 } do
		part(at(sx * 1.45, floorY + 0.13, runZ), Vector3.new(0.22, 0.05, runL), C.Gold)
	end
	for k = 0, 2 do
		part(at(0, floorY + 0.13, runFrom - runL * (k + 0.5) / 3) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.7, 0.05, 0.7), C.Gold)
	end

	---------------------------------------------------------------- walls and ceiling
	-- dark stone brick lining with mortar courses on the side and back walls
	for _, sx in { -1, 1 } do
		part(at(sx * (IN_X - 0.03), floorY + ROOM.Ground / 2, midZ), Vector3.new(0.06, ROOM.Ground, depth), C.Brick)
	end
	part(at(0, floorY + ROOM.Ground / 2, IN_BACK + 0.03), Vector3.new(IN_X * 2, ROOM.Ground, 0.06), C.Brick)
	-- (the entrance wall too, beside the door)
	local seg = IN_X - ROOM.DoorW / 2
	for _, sx in { -1, 1 } do
		part(at(sx * (ROOM.DoorW / 2 + seg / 2), floorY + ROOM.Ground / 2, IN_FRONT - 0.03), Vector3.new(seg, ROOM.Ground, 0.06), C.Brick)
	end
	for y = floorY + 1.6, ceilY - 0.8, 1.5 do
		for _, sx in { -1, 1 } do
			part(at(sx * (IN_X - 0.07), y, midZ), Vector3.new(0.04, 0.12, depth), C.Mortar)
		end
		part(at(0, y, IN_BACK + 0.07), Vector3.new(IN_X * 2, 0.12, 0.04), C.Mortar)
	end
	-- the dark ceiling, its beams
	part(at(0, ceilY - 0.05, midZ), Vector3.new(IN_X * 2, 0.1, depth), C.Ceiling)
	for k = 0, 3 do
		part(at(0, ceilY - 0.4, IN_FRONT - depth * (k + 0.5) / 4), Vector3.new(IN_X * 2, 0.6, 0.7), C.Beam, WOOD)
	end
	-- timber pilasters between the bays, a torch on each (n: into the room)
	local slots = DropperShopBuilder.Slots
	local pilasters = {
		{ P = Vector3.new(-IN_X + 0.3, 0, (slots[1].Center.Z + slots[3].Center.Z) / 2), N = Vector3.new(1, 0, 0) },
		{ P = Vector3.new(IN_X - 0.3, 0, (slots[2].Center.Z + slots[4].Center.Z) / 2), N = Vector3.new(-1, 0, 0) },
		{ P = Vector3.new(-IN_X + 4.4, 0, IN_BACK + 0.3), N = Vector3.new(0, 0, 1) },
		{ P = Vector3.new(IN_X - 4.4, 0, IN_BACK + 0.3), N = Vector3.new(0, 0, 1) },
	}
	for _, pil in pilasters do
		local p, n = pil.P, pil.N
		local size = if n.X ~= 0 then Vector3.new(0.6, ROOM.Ground, 0.7) else Vector3.new(0.7, ROOM.Ground, 0.6)
		part(at(p.X, floorY + ROOM.Ground / 2, p.Z), size, C.Timber, WOOD)
		local q1, q2 = p + n * 0.45, p + n * 0.65
		part(at(q1.X, floorY + 5.6, q1.Z), Vector3.new(0.4, 0.25, 0.4), C.Iron)
		part(at(q2.X, floorY + 5.95, q2.Z), Vector3.new(0.3, 0.5, 0.3), C.Iron)
		glow(at(q2.X, floorY + 6.4, q2.Z), Vector3.new(0.24, 0.42, 0.24), C.Flame)
	end
	-- two candle chandeliers either side of the counter
	for _, sx in { -1, 1 } do
		local x, z, y = sx * 6.4, (IN_FRONT + DropperShopBuilder.Counter.Center.Z) / 2, ceilY - 2.2
		local chain = part(at(x, y + 0.9, z), Vector3.new(0.12, 1.6, 0.12), C.Iron)
		Geo.cylinder(m, at(x, y, z).Position, 0.25, 2.8, C.Iron, nil, table.clone(DECOR))
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			local p = at(x + math.cos(a) * 1.2, y + 0.38, z + math.sin(a) * 1.2)
			part(p, Vector3.new(0.22, 0.5, 0.22), C.Candle)
			glow(p * CFrame.new(0, 0.38, 0), Vector3.new(0.16, 0.26, 0.16), C.Flame)
		end
		light(chain, C.Flame, 18, 1.3)
	end

	---------------------------------------------------------------- the displays
	local plinthH = DropperShopBuilder.PlinthHeight
	for _, slot in slots do
		local color = glowOf(slot.Id)
		local back = slot.Wall == "Back"
		local n = if back then Vector3.new(0, 0, 1) elseif slot.Wall == "Left" then Vector3.new(1, 0, 0) else Vector3.new(-1, 0, 0)
		local len = if back then slot.Size.X else slot.Size.Z
		local dep = if back then slot.Size.Z else slot.Size.X
		local function along(l: number, h: number, t: number): Vector3
			-- a box l along the wall, h high, t thick off it
			return if back then Vector3.new(l, h, t) else Vector3.new(t, h, l)
		end
		local c = slot.Center
		-- the plinth's glowing front edge (the server's plinth is the stone)
		local edge = c + n * (dep / 2)
		glow(at(edge.X, floorY + plinthH - 0.05, edge.Z), along(len, 0.1, 0.14), color)
		glow(at(edge.X, floorY + 0.05, edge.Z), along(len, 0.1, 0.14), color)
		-- the backlit panel on the wall behind it, a banner over it, a ceiling spot
		local wall = c - n * (dep / 2)
		local panel, line, cloth, rod = wall + n * 0.09, wall + n * 0.12, wall + n * 0.1, wall + n * 0.2
		part(at(panel.X, floorY + 3.6, panel.Z), along(len - 0.6, 5.2, 0.06), C.Panel)
		glow(at(line.X, floorY + 6.25, line.Z), along(len - 0.6, 0.12, 0.06), color)
		glow(at(line.X, floorY + 1.0, line.Z), along(len - 0.6, 0.12, 0.06), color)
		part(at(cloth.X, ceilY - 1.9, cloth.Z), along(2, 2.4, 0.08), color, FABRIC)
		part(at(rod.X, ceilY - 0.65, rod.Z), along(2.4, 0.18, 0.18), C.Gold)
		part(at(c.X, ceilY - 0.9, c.Z), Vector3.new(0.9, 0.5, 0.9), C.Iron)
		glow(at(c.X, ceilY - 1.18, c.Z), Vector3.new(0.7, 0.06, 0.7), color)
		-- the dropper itself
		local cf = at(c.X, floorY + plinthH, c.Z) * CFrame.Angles(0, slot.Turn, 0)
		local model = DropperBuilder.build(slot.Id, cf)
		BlockKit.scale(model, cf, DropperShopBuilder.SideScale / DropperBuilder.Scale)
		model.Parent = m
	end

	-- the back corners: an open chest of gold, a heap of ore crystals
	for _, sx in { -1, 1 } do
		local x, z = sx * (IN_X - 2.1), IN_BACK + 1.4
		if sx > 0 then
			local chest = at(x, floorY, z)
			part(chest * CFrame.new(0, 0.55, 0), Vector3.new(2, 1.1, 1.3), rgb(150, 98, 54), WOOD)
			part(chest * CFrame.new(0, 1.05, 0), Vector3.new(1.85, 0.2, 1.15), C.Gold)
			part(chest * CFrame.new(0, 1.55, -0.75) * CFrame.Angles(math.rad(-65), 0, 0), Vector3.new(2, 1.2, 0.2), rgb(130, 84, 46), WOOD)
			for _, bx in { -0.9, 0.9 } do
				part(chest * CFrame.new(bx, 0.55, 0), Vector3.new(0.14, 1.14, 1.34), C.GoldDark)
			end
			for k = 0, 2 do
				part(chest * CFrame.new(-0.4 + k * 0.4, 1.3, 0.1) * CFrame.Angles(0, k * 0.4, 0), Vector3.new(0.7, 0.25, 0.32), C.Gold)
			end
			glow(chest * CFrame.new(0.5, 1.4, -0.2), Vector3.new(0.35, 0.35, 0.35), rgb(255, 230, 120))
		else
			part(at(x, floorY + 0.4, z), Vector3.new(2.4, 0.8, 1.8), rgb(84, 80, 96))
			for k = 0, 4 do
				local id = slots[(k % #slots) + 1].Id
				local h = 1.0 + (k % 3) * 0.4
				glow(
					at(x - 0.8 + k * 0.4, floorY + 0.8 + h / 2, z + (if k % 2 == 0 then 0.25 else -0.25))
						* CFrame.Angles(0, k * 0.7, math.rad(-12 + k * 6)),
					Vector3.new(0.45, h, 0.45),
					glowOf(id)
				)
			end
		end
	end

	---------------------------------------------------------------- the hero: the DARK MATTER DROPPER
	local hero = DropperShopBuilder.Hero
	local heroColor = glowOf(hero.Id)
	local hz = hero.Center.Z
	local top = floorY + hero.Size.Y
	glow(at(0, top - 0.05, hz + hero.Size.Z / 2), Vector3.new(hero.Size.X, 0.1, 0.14), heroColor)
	for _, sx in { -1, 1 } do
		glow(at(sx * hero.Size.X / 2, top - 0.05, hz), Vector3.new(0.14, 0.1, hero.Size.Z), heroColor)
		-- gold posts with glowing orbs at the front corners
		local px, pz = sx * (hero.Size.X / 2 - 0.3), hz + hero.Size.Z / 2 - 0.3
		part(at(px, top + 0.8, pz), Vector3.new(0.45, 1.6, 0.45), C.Gold)
		part(at(px, top + 1.65, pz), Vector3.new(0.6, 0.12, 0.6), C.GoldDark)
		Geo.ball(m, at(px, top + 2.0, pz).Position, 0.55, heroColor, NEON, table.clone(DECOR))
	end
	-- the glowing ring on the back wall behind it
	local ringC = at(0, floorY + 5.2, IN_BACK + 0.12)
	local ringR, segs = 3.6, 16
	for k = 0, segs - 1 do
		local a = (k + 0.5) / segs * math.pi * 2
		local len = 2 * ringR * math.tan(math.pi / segs) + 0.05
		local arc = ringC * CFrame.new(math.cos(a) * ringR, math.sin(a) * ringR, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
		glow(arc, Vector3.new(len, 0.3, 0.1), heroColor)
		part(arc * CFrame.new(0, -0.32, -0.02), Vector3.new(len, 0.34, 0.1), C.Iron)
	end
	local heroCf = at(0, top, hz)
	local heroModel = DropperBuilder.build(hero.Id, heroCf)
	BlockKit.scale(heroModel, heroCf, hero.Scale / DropperBuilder.Scale)
	heroModel.Parent = m
	local heroLight = Geo.block(m, at(0, top + 4.5, hz + 3), Vector3.new(0.2, 0.2, 0.2), heroColor, NEON, table.clone(DECOR))
	heroLight.Transparency = 1
	light(heroLight, heroColor, 14, 2)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(heroColor, rgb(255, 255, 255))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.25, 0)
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Rate = 6
	sparkles.Speed = NumberRange.new(0.4, 1)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = heroLight

	---------------------------------------------------------------- the counter
	local cc, cs = counter.Center, counter.Size
	local ctop = floorY + cs.Y + counter.Top
	local front = cc.Z + cs.Z / 2
	part(at(0, ctop - 0.06, front + 0.12), Vector3.new(cs.X + 0.3, 0.14, 0.14), C.Gold)
	part(at(0, floorY + 0.1, front + 0.06), Vector3.new(cs.X + 0.1, 0.2, 0.14), C.Gold)
	glow(at(0, floorY + 0.3, front + 0.09), Vector3.new(cs.X - 0.2, 0.08, 0.06), C.Fire)
	local plate =
		BlockKit.text(m, at(0, floorY + cs.Y * 0.55, front + 0.08), Vector3.new(4.6, 0.8, 0.08), "DROPPERS", C.Gold, C.Panel, C.Fire)
	plate.Name = "CounterPlate"
	-- a till with a glowing screen
	part(at(-2.3, ctop + 0.45, cc.Z), Vector3.new(1.4, 0.9, 1.0), C.Iron)
	part(at(-2.3, ctop + 0.12, cc.Z + 0.1), Vector3.new(1.5, 0.24, 1.1), C.GoldDark)
	glow(at(-2.3, ctop + 0.95, cc.Z + 0.52) * CFrame.Angles(math.rad(-20), 0, 0), Vector3.new(0.9, 0.38, 0.05), rgb(60, 190, 110))
	-- a bell and coin stacks
	Geo.cylinder(m, at(-0.6, ctop + 0.05, cc.Z + 0.3).Position, 0.1, 0.7, C.GoldDark, nil, table.clone(DECOR))
	Geo.ball(m, at(-0.6, ctop + 0.25, cc.Z + 0.3).Position, 0.5, C.Gold, nil, table.clone(DECOR))
	for k, p in { Vector3.new(0.4, 0, 0.4), Vector3.new(0.85, 0, 0.1), Vector3.new(0.5, 0, -0.3) } do
		local h = 0.25 + k * 0.12
		Geo.cylinder(m, at(p.X, ctop + h / 2, cc.Z + p.Z).Position, h, 0.42, C.Gold, nil, table.clone(DECOR))
	end
	-- a small MONEY LASER on the counter
	local laserCf = at(2.75, ctop, cc.Z)
	local laser = LaserBuilder.build(laserCf, 0.16)
	laser.Parent = m

	---------------------------------------------------------------- the Dropper Master
	-- (beside the middle, behind the till: the DARK MATTER DROPPER stays in view)
	local kx, kz = -2.3, cc.Z - cs.Z / 2 - 0.6
	local function body(x: number, y: number, size: Vector3, color: Color3, material: Enum.Material?): Part
		return part(at(kx + x, floorY + y, kz), size, color, material)
	end
	for _, sx in { -1, 1 } do
		body(sx * 0.32, 0.8, Vector3.new(0.55, 1.6, 0.6), C.Overalls)
		body(sx * 0.32, 0.15, Vector3.new(0.6, 0.3, 0.75), C.Boots)
		body(sx * 1.08, 3.0, Vector3.new(0.5, 1.4, 0.55), C.Shirt)
		body(sx * 1.08, 2.15, Vector3.new(0.5, 0.4, 0.55), C.Skin)
	end
	body(0, 2.6, Vector3.new(1.65, 1.8, 0.9), C.Shirt)
	body(0, 2.35, Vector3.new(1.4, 1.3, 0.95), C.Overalls)
	body(0, 4.05, Vector3.new(1.15, 1.1, 1.1), C.Skin)
	body(0, 4.75, Vector3.new(1.3, 0.4, 1.3), C.Hat)
	body(0, 4.58, Vector3.new(1.5, 0.1, 1.55), C.Hat)
	for _, sx in { -1, 1 } do
		glow(at(kx + sx * 0.27, floorY + 4.8, kz + 0.66), Vector3.new(0.34, 0.3, 0.08), rgb(90, 220, 255))
		part(at(kx + sx * 0.25, floorY + 4.15, kz + 0.56), Vector3.new(0.16, 0.18, 0.05), rgb(30, 24, 30))
	end
	body(0, 3.82, Vector3.new(0.75, 0.2, 1.16), C.Hair)

	---------------------------------------------------------------- ore crystal shelves by the entrance
	for _, sx in { -1, 1 } do
		local x = sx * (ROOM.DoorW / 2 + 1.5)
		part(at(x, floorY + 3.6, IN_FRONT - 0.35), Vector3.new(2.6, 0.18, 0.7), C.Wood, WOOD)
		for k = 0, 2 do
			local slot = DropperShopBuilder.Slots[if sx < 0 then k + 1 else k + 4]
			local id = if slot then slot.Id else DropperShopBuilder.Hero.Id
			glow(
				at(x - 0.85 + k * 0.85, floorY + 4.0, IN_FRONT - 0.35) * CFrame.Angles(0.5, 0.6 + k, 0.4),
				Vector3.new(0.45, 0.6, 0.45),
				glowOf(id)
			)
		end
	end

	---------------------------------------------------------------- outside
	local rng = Rng.new(2310)
	local face = ROOM.Front + 0.5
	local winY = floorY + ROOM.WindowY
	-- stones on the front wall, off the windows, the entrance and the lanterns
	local stoneColors = { rgb(150, 156, 170), rgb(128, 134, 150), rgb(172, 176, 188), rgb(112, 116, 132) }
	local placed = 0
	for _ = 1, 120 do
		if placed >= 22 then
			break
		end
		local x = rng:range(ROOM.DoorW / 2 + 1.2, ROOM.W / 2 - 0.8) * (if rng:chance(0.5) then 1 else -1)
		local y = rng:range(floorY + 0.6, floorY + ROOM.Ground - 0.6)
		local inWindow = math.abs(math.abs(x) - ROOM.WindowX) < ROOM.WindowW / 2 + 0.8 and math.abs(y - winY) < 2.2
		local atLantern = math.abs(math.abs(x) - (ROOM.DoorW / 2 + 1.5)) < 1.2 and math.abs(y - (floorY + ROOM.DoorH - 0.4)) < 1.6
		local atBox = math.abs(math.abs(x) - ROOM.WindowX) < ROOM.WindowW / 2 + 0.6 and math.abs(y - (winY - 1.75)) < 0.8
		if not inWindow and not atLantern and not atBox then
			local w, h = rng:pick({ 1.4, 1.8, 2.2 }), rng:pick({ 0.7, 0.9, 1.1 })
			part(at(x, y, face + 0.08), Vector3.new(w, h, 0.18), rng:pick(stoneColors))
			placed += 1
		end
	end
	for _, sx in { -1, 1 } do
		local wx = sx * ROOM.WindowX
		-- a striped awning over the window
		local tilt = CFrame.Angles(math.rad(28), 0, 0)
		for k = 0, 3 do
			local stripe = if k % 2 == 0 then rgb(214, 56, 50) else rgb(250, 244, 232)
			part(at(wx - 1.65 + k * 1.1, winY + 2.2, face + 0.75) * tilt, Vector3.new(1.1, 0.12, 1.7), stripe)
		end
		for k = 0, 3 do
			local stripe = if k % 2 == 0 then rgb(214, 56, 50) else rgb(250, 244, 232)
			part(at(wx - 1.65 + k * 1.1, winY + 1.62, face + 1.5), Vector3.new(1.1, 0.4, 0.08), stripe)
		end
		-- a flower box under it
		part(at(wx, winY - 1.75, face + 0.4), Vector3.new(3.8, 0.6, 0.75), C.Wood, WOOD)
		part(at(wx, winY - 1.42, face + 0.4), Vector3.new(3.6, 0.1, 0.6), rgb(78, 150, 60))
		for k = 0, 4 do
			local color = ({ rgb(255, 120, 180), rgb(255, 214, 80), rgb(190, 120, 255), rgb(255, 255, 255), rgb(255, 120, 180) })[k + 1]
			part(
				at(wx - 1.4 + k * 0.7, winY - 1.15, face + 0.4 + (if k % 2 == 0 then 0.12 else -0.12)),
				Vector3.new(0.38, 0.38, 0.38),
				color
			)
		end
		-- a potted bush either side of the porch
		local px = sx * 6.1
		part(at(px, 0.45, face + 0.9), Vector3.new(1.1, 0.9, 1.1), rgb(176, 96, 60))
		part(at(px, 1.35, face + 0.9), Vector3.new(1.5, 1.1, 1.5), rgb(70, 160, 70))
		part(at(px + 0.15, 2.05, face + 0.85), Vector3.new(0.9, 0.6, 0.9), rgb(96, 190, 84))
	end
	-- an OPEN sign in the right window
	BlockKit.text(
		m,
		at(ROOM.WindowX, winY + 0.4, face - 0.35),
		Vector3.new(2, 0.7, 0.06),
		"OPEN",
		rgb(255, 230, 120),
		rgb(40, 20, 50),
		rgb(255, 80, 160)
	)
	-- barrels to the left, crates to the right
	for k, p in { Vector3.new(-ROOM.W / 2 + 2.2, 0, face + 1.2), Vector3.new(-ROOM.W / 2 + 1.1, 0, face + 2.3) } do
		local h = 1.7 - k * 0.15
		Geo.cylinder(m, at(p.X, h / 2 + 0.3, p.Z).Position, h, 1.3, rgb(150, 98, 54), WOOD, table.clone(DECOR))
		for _, ry in { 0.3, h - 0.3 } do
			Geo.cylinder(m, at(p.X, 0.3 + ry, p.Z).Position, 0.14, 1.38, C.Iron, nil, table.clone(DECOR))
		end
	end
	for k, p in { Vector3.new(ROOM.W / 2 - 2, 0.95, face + 1.3), Vector3.new(ROOM.W / 2 - 1.8, 2.35, face + 1.2) } do
		local sz = if k == 1 then 1.3 else 1.1
		local crate = at(p.X, p.Y, p.Z) * CFrame.Angles(0, math.rad(k * 9), 0)
		part(crate, Vector3.new(sz, sz, sz), rgb(196, 142, 84), WOOD)
		part(crate, Vector3.new(sz + 0.06, 0.2, sz + 0.06), rgb(120, 80, 44), WOOD)
		part(crate, Vector3.new(0.2, sz + 0.06, sz + 0.06), rgb(120, 80, 44), WOOD)
	end

	quiet(m)
	m.Parent = house
	return m
end

function DropperShopBuilder.clear(house: Instance)
	local detail = house:FindFirstChild(DropperShopBuilder.DetailName)
	if detail then
		detail:Destroy()
	end
end

return DropperShopBuilder
