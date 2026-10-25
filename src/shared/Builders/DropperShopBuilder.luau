--[[
	The DROPPERS shop's showroom (owner 2026-10-23: "it must be extremely
	good", then "in the modern tech style, so it fits our map"): the detail
	every client builds inside the lobby's DROPPERS house while its camera is
	near, like the museums' relics (MuseumBuilder). The server keeps the
	solid shell (the tech walls and front, the counter with the shop prompt,
	the display plinths and the hero podium; Districts/Droppers.luau), so the
	map budget carries the structure only; the phone budget counts both
	(tests/DropperShop.spec.luau: the parts streamed round the door plus the
	showroom stay under LobbyLayout.Budget.StreamParts).

	Inside, in the Districts' sci-fi look (dark gunmetal, blue neon, orange
	accents):
	  - a dark metal floor with blue neon guide lines from the entrance to
	    the counter and across the aisle
	  - dark metal wall panels with a blue neon band all round and glowing
	    orange light strips, a dark ceiling with three long light panels
	  - the real droppers (DropperBuilder, the owner's picture; the lite
	    build) on plinths with a neon edge in their colour: two along each
	    side wall facing the aisle and one either side of the hero on the
	    back wall (cheapest at the entrance), each in front of a backlit wall
	    panel under a ceiling spot
	  - the DARK MATTER DROPPER, the best one, big on its podium behind the
	    counter in a glowing ring on the back wall, between glowing orbs
	  - a royal red carpet with gold borders from the door to the counter
	  - the counter: a neon edge, the DROPPERS plate, a big till (a gold "$"
	    drawer, keypad, receipt roll, a "$$$" customer display), a service
	    bell, coin stacks and a gold bar, a gem under a glass dome, a plant,
	    an OPEN sign and a small Money Laser gate (the shopkeeper is a big
	    golem beside the counter: ShopkeeperController)
	  - a heap of ore crystals and a terminal in the back corners
	Three local PointLights (two ceiling panels, the hero); every part is
	anchored, non-colliding and casts no shadow (the server's plinths and
	counter give the collisions); the droppers' own lights are left out.

	Frame: the house frame `frame` (the server's attribute FrameAttribute on
	the house model): y 0 = the ground, local +Z = the house's front, the
	shop's floor at Room.Plinth. Room holds the shared sizes the server's
	shell is built from.

	  build(frame)        the showroom model (not parented)
	  show(house, frame)  builds it into house.ShopDetail (once)
	  clear(house)        takes it away again
	Pure: only Instance creation (Lune previews and the client both build it).
]]

local Shared = script.Parent.Parent
local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)
local DropperBuilder = require(script.Parent.DropperBuilder)
local DropperConfig = require(Shared.Config.DropperConfig)
local LobbyLayout = require(Shared.Config.LobbyLayout)

local DropperShopBuilder = {}

DropperShopBuilder.Tag = "DropperShop" -- CollectionService tag on the house model (the clients' loop)
DropperShopBuilder.FrameAttribute = "ShopFrame" -- CFrame attribute on the house model
DropperShopBuilder.DetailName = "ShopDetail"
DropperShopBuilder.ShowDistance = 70 -- studs from the camera: the showroom is in the scene
DropperShopBuilder.HideDistance = 90 -- ...out of it again (kept, unparented)
DropperShopBuilder.DropDistance = 180 -- ...thrown away (the mine floors, the far plots)

-- The house (studs, in the house frame): W wide, D deep, the front wall at
-- z = Front (LobbyLayout.DroppersFront), a Plinth high floor, the shop
-- Ground high to its ceiling, the walls Wall high, the gateway DoorW wide
-- and DoorH high.
DropperShopBuilder.Room = {
	W = 30,
	D = 15,
	Front = LobbyLayout.DroppersFront,
	Plinth = 1,
	Ground = 9,
	Wall = 11.5,
	DoorW = 7,
	DoorH = 7.5,
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
local METAL = Enum.Material.Metal

-- the Districts' Tech kit shades (Lobby/Districts/Tech.luau)
local C = {
	Metal = rgb(66, 72, 92),
	MetalDark = rgb(44, 48, 64),
	MetalDeep = rgb(27, 29, 41),
	MetalLight = rgb(112, 120, 144),
	Neon = rgb(15, 95, 255),
	Band = rgb(255, 150, 36),
	Panel = rgb(120, 150, 215),
	Gold = rgb(255, 196, 64),
	Screen = rgb(30, 92, 214),
	Laser = rgb(0, 255, 105),
	LaserBody = rgb(40, 150, 70),
	Carpet = rgb(150, 24, 44),
	Leaf = rgb(70, 190, 90),
	Paper = rgb(245, 245, 240),
	Till = rgb(110, 255, 140),
}

local DECOR = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function glowOf(id: string): Color3
	local st = DropperBuilder.Styles[id]
	return if st then st.Glow[1] else C.Band
end

local function quiet(model: Instance)
	for _, d in model:GetDescendants() do
		-- (the showroom's own three lights only: the droppers' go, phones)
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

function DropperShopBuilder.build(frame: CFrame): Model
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
	local slots = DropperShopBuilder.Slots
	local counter = DropperShopBuilder.Counter
	local cc, cs = counter.Center, counter.Size
	local counterFront = cc.Z + cs.Z / 2

	---------------------------------------------------------------- floor, walls, ceiling
	part(at(0, floorY + 0.03, midZ), Vector3.new(IN_X * 2, 0.06, depth), C.MetalDeep, METAL)
	-- blue neon guide lines from the entrance to the counter, two across the aisle
	local guide = IN_FRONT - counterFront
	for _, sx in { -1, 1 } do
		glow(at(sx * 2.4, floorY + 0.08, IN_FRONT - guide / 2), Vector3.new(0.14, 0.04, guide), C.Neon)
	end
	local aisle = IN_X - 4.2
	glow(at(0, floorY + 0.08, counterFront + 0.6), Vector3.new(aisle * 2 - 0.4, 0.04, 0.14), C.Neon)
	-- (owner 2026-10-24: "a carpet on the floor") a royal red runner from the
	-- door to the counter between the guide lines, gold borders along it
	local runner = IN_FRONT - (counterFront + 0.8)
	local runnerZ = IN_FRONT - runner / 2
	part(at(0, floorY + 0.07, runnerZ), Vector3.new(3.9, 0.04, runner), C.Carpet, Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		part(at(sx * 1.7, floorY + 0.1, runnerZ), Vector3.new(0.16, 0.03, runner - 0.2), C.Gold)
	end
	-- dark metal wall panels on the side and back walls (the front's windows
	-- stay clear), a blue neon band round them
	for _, sx in { -1, 1 } do
		part(at(sx * (IN_X - 0.03), floorY + ROOM.Ground / 2, midZ), Vector3.new(0.06, ROOM.Ground, depth), C.MetalDark)
		glow(at(sx * (IN_X - 0.08), floorY + 7.4, midZ), Vector3.new(0.06, 0.16, depth), C.Neon)
	end
	part(at(0, floorY + ROOM.Ground / 2, IN_BACK + 0.03), Vector3.new(IN_X * 2, ROOM.Ground, 0.06), C.MetalDark)
	glow(at(0, floorY + 7.4, IN_BACK + 0.08), Vector3.new(IN_X * 2, 0.16, 0.06), C.Neon)
	-- glowing orange light strips up the walls between the displays
	for _, p in
		{
			Vector3.new(-IN_X + 0.08, 0, (slots[1].Center.Z + slots[3].Center.Z) / 2),
			Vector3.new(IN_X - 0.08, 0, (slots[2].Center.Z + slots[4].Center.Z) / 2),
			Vector3.new(-IN_X + 4.5, 0, IN_BACK + 0.08),
			Vector3.new(IN_X - 4.5, 0, IN_BACK + 0.08),
		}
	do
		glow(at(p.X, floorY + ROOM.Ground / 2, p.Z), Vector3.new(0.18, ROOM.Ground - 1, 0.18), C.Band)
	end
	-- the dark ceiling and three long light panels (two of them light the shop)
	part(at(0, ceilY - 0.05, midZ), Vector3.new(IN_X * 2, 0.1, depth), C.MetalDeep)
	for k, x in { -6.5, 0, 6.5 } do
		local panel = glow(at(x, ceilY - 0.14, midZ + 1), Vector3.new(0.8, 0.08, depth - 5), C.Panel)
		if k ~= 2 then
			light(panel, rgb(210, 225, 255), 20, 1.1)
		end
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
		-- the plinth's glowing front edge (the server's plinth is the block)
		local edge = c + n * (dep / 2)
		glow(at(edge.X, floorY + plinthH - 0.05, edge.Z), along(len, 0.1, 0.14), color)
		-- the backlit panel on the wall behind it, a ceiling spot
		local wall = c - n * (dep / 2)
		local panel, line = wall + n * 0.09, wall + n * 0.12
		part(at(panel.X, floorY + 3.6, panel.Z), along(len - 0.6, 5.4, 0.06), C.MetalDeep)
		glow(at(line.X, floorY + 6.35, line.Z), along(len - 0.6, 0.14, 0.06), color)
		glow(at(c.X, ceilY - 0.14, c.Z), Vector3.new(1.2, 0.06, 1.2), color)
		-- the dropper itself (the lite build)
		local cf = at(c.X, floorY + plinthH, c.Z) * CFrame.Angles(0, slot.Turn, 0)
		local model = DropperBuilder.build(slot.Id, cf, true)
		BlockKit.scale(model, cf, DropperShopBuilder.SideScale / DropperBuilder.Scale)
		model.Parent = m
	end

	---------------------------------------------------------------- the hero: the DARK MATTER DROPPER
	local hero = DropperShopBuilder.Hero
	local heroColor = glowOf(hero.Id)
	local hz = hero.Center.Z
	local top = floorY + hero.Size.Y
	glow(at(0, top - 0.05, hz + hero.Size.Z / 2), Vector3.new(hero.Size.X, 0.1, 0.14), heroColor)
	for _, sx in { -1, 1 } do
		glow(at(sx * hero.Size.X / 2, top - 0.05, hz), Vector3.new(0.14, 0.1, hero.Size.Z), heroColor)
		-- glowing orbs on posts at the front corners
		local px, pz = sx * (hero.Size.X / 2 - 0.3), hz + hero.Size.Z / 2 - 0.3
		part(at(px, top + 0.8, pz), Vector3.new(0.45, 1.6, 0.45), C.MetalLight)
		Geo.ball(m, at(px, top + 1.9, pz).Position, 0.6, heroColor, NEON, table.clone(DECOR))
	end
	-- the glowing ring on the back wall behind it
	local ringC = at(0, floorY + 5.2, IN_BACK + 0.14)
	local ringR, segs = 3.6, 14
	for k = 0, segs - 1 do
		local a = (k + 0.5) / segs * math.pi * 2
		local len = 2 * ringR * math.tan(math.pi / segs) + 0.05
		local arc = ringC * CFrame.new(math.cos(a) * ringR, math.sin(a) * ringR, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
		glow(arc, Vector3.new(len, 0.32, 0.1), heroColor)
	end
	local heroCf = at(0, top, hz)
	-- (the lite build like the side droppers: the counter's till and props fit the phone budget)
	local heroModel = DropperBuilder.build(hero.Id, heroCf, true)
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
	local ctop = floorY + cs.Y + counter.Top
	glow(at(0, ctop - 0.2, counterFront + 0.22), Vector3.new(cs.X + 0.3, 0.14, 0.08), C.Neon)
	glow(at(0, floorY + 0.25, counterFront + 0.05), Vector3.new(cs.X - 0.2, 0.1, 0.06), C.Band)
	local plate = BlockKit.text(
		m,
		at(0, floorY + cs.Y * 0.5, counterFront + 0.08),
		Vector3.new(5, 0.8, 0.08),
		"DROPPERS",
		rgb(255, 255, 255),
		rgb(16, 30, 78),
		C.Neon
	)
	plate.Name = "CounterPlate"
	-- (owner 2026-10-24: "the till bigger, accessories, mega cool") the till: a
	-- dark base with a gold "$" cash drawer and a glowing strip, a body, a
	-- keypad, a receipt roll, a customer display on a post ("$$$")
	local rx, rz = -2.3, cc.Z
	part(at(rx, ctop + 0.22, rz), Vector3.new(1.8, 0.44, 1.2), C.MetalDark)
	BlockKit.text(m, at(rx, ctop + 0.22, rz + 0.62), Vector3.new(1.5, 0.3, 0.06), "$", C.MetalDeep, C.Gold, nil, Enum.Font.LuckiestGuy)
	glow(at(rx, ctop + 0.03, rz + 0.62), Vector3.new(1.7, 0.06, 0.05), C.Band)
	part(at(rx - 0.1, ctop + 0.68, rz - 0.2), Vector3.new(1.5, 0.5, 0.75), C.Metal)
	part(at(rx + 0.35, ctop + 0.47, rz + 0.36), Vector3.new(0.75, 0.06, 0.4), C.MetalDeep)
	Geo.make("Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = at(rx + 0.85, ctop + 0.6, rz - 0.15),
		Size = Vector3.new(0.3, 0.34, 0.34),
		Color = C.Paper,
		Material = Enum.Material.SmoothPlastic,
	}, m)
	part(at(rx + 0.85, ctop + 0.46, rz + 0.12), Vector3.new(0.26, 0.02, 0.5), C.Paper)
	part(at(rx - 0.1, ctop + 1.15, rz - 0.2), Vector3.new(0.12, 0.5, 0.12), C.MetalLight)
	BlockKit.text(
		m,
		at(rx - 0.1, ctop + 1.6, rz - 0.2),
		Vector3.new(1.2, 0.5, 0.14),
		"$$$",
		C.Till,
		C.MetalDeep,
		nil,
		Enum.Font.LuckiestGuy
	)
	-- a gold service bell
	Geo.cylinder(m, at(-0.8, ctop + 0.04, cc.Z + 0.35).Position, 0.08, 0.55, C.MetalDeep, nil, table.clone(DECOR))
	Geo.ball(m, at(-0.8, ctop + 0.2, cc.Z + 0.35).Position, 0.42, C.Gold, nil, table.clone(DECOR))
	Geo.ball(m, at(-0.8, ctop + 0.45, cc.Z + 0.35).Position, 0.1, C.MetalLight, nil, table.clone(DECOR))
	-- coin stacks and a gold bar
	for k, p in { Vector3.new(0.5, 0, 0.3), Vector3.new(0.95, 0, 0.0), Vector3.new(0.15, 0, -0.25) } do
		local h = 0.3 + (k % 3) * 0.15
		Geo.cylinder(m, at(p.X, ctop + h / 2, cc.Z + p.Z).Position, h, 0.42, C.Gold, nil, table.clone(DECOR))
	end
	part(at(0.6, ctop + 0.1, cc.Z - 0.4) * CFrame.Angles(0, 0.3, 0), Vector3.new(0.6, 0.2, 0.28), C.Gold)
	-- a glowing gem under a glass dome on a round stand
	Geo.cylinder(m, at(1.6, ctop + 0.08, cc.Z).Position, 0.16, 0.7, C.MetalDark, nil, table.clone(DECOR))
	glow(at(1.6, ctop + 0.42, cc.Z) * CFrame.Angles(0, math.pi / 4, math.pi / 4), Vector3.new(0.3, 0.3, 0.3), heroColor)
	local dome = Geo.ball(m, at(1.6, ctop + 0.4, cc.Z).Position, 0.66, rgb(220, 240, 255), Enum.Material.Glass, table.clone(DECOR))
	dome.Transparency = 0.6
	-- a little plant at the left end, an OPEN sign at the right end
	Geo.cylinder(m, at(-4.0, ctop + 0.22, cc.Z - 0.2).Position, 0.44, 0.5, C.Band, nil, table.clone(DECOR))
	for _, a in { -0.5, 0.6 } do
		part(at(-4.0, ctop + 0.75, cc.Z - 0.2) * CFrame.Angles(0, a * 2, a), Vector3.new(0.18, 0.75, 0.42), C.Leaf)
	end
	BlockKit.text(
		m,
		at(4.05, ctop + 0.4, cc.Z + 0.25),
		Vector3.new(0.85, 0.42, 0.08),
		"OPEN",
		rgb(255, 120, 210),
		C.MetalDeep,
		nil,
		Enum.Font.LuckiestGuy
	)
	-- a small Money Laser gate on the counter: two green posts, a lintel, the beam
	local lx = 2.8
	for _, dx in { -0.45, 0.45 } do
		part(at(lx + dx, ctop + 0.6, cc.Z), Vector3.new(0.22, 1.2, 0.3), C.LaserBody)
	end
	part(at(lx, ctop + 1.25, cc.Z), Vector3.new(1.2, 0.2, 0.36), C.LaserBody)
	local beam = glow(at(lx, ctop + 0.6, cc.Z), Vector3.new(0.62, 1.1, 0.06), C.Laser)
	beam.Name = DropperConfig.Laser.Id
	beam.Transparency = 0.3

	---------------------------------------------------------------- the back corners
	-- a heap of ore crystals (left), a terminal with a glowing screen (right)
	local cornerX, cornerZ = IN_X - 2.1, IN_BACK + 1.4
	part(at(-cornerX, floorY + 0.4, cornerZ), Vector3.new(2.4, 0.8, 1.8), C.MetalDark)
	for k = 0, 4 do
		local id = slots[(k % #slots) + 1].Id
		local h = 1.0 + (k % 3) * 0.4
		glow(
			at(-cornerX - 0.8 + k * 0.4, floorY + 0.8 + h / 2, cornerZ + (if k % 2 == 0 then 0.25 else -0.25))
				* CFrame.Angles(0, k * 0.7, math.rad(-12 + k * 6)),
			Vector3.new(0.45, h, 0.45),
			glowOf(id)
		)
	end
	part(at(cornerX, floorY + 0.6, cornerZ), Vector3.new(2.2, 1.2, 1.2), C.Metal)
	part(at(cornerX, floorY + 2.0, cornerZ - 0.3), Vector3.new(2.0, 1.4, 0.3), C.MetalDark)
	glow(at(cornerX, floorY + 2.0, cornerZ - 0.12), Vector3.new(1.7, 1.1, 0.06), C.Screen)

	quiet(m)
	return m
end

function DropperShopBuilder.show(house: Instance, frame: CFrame): Model
	local old = house:FindFirstChild(DropperShopBuilder.DetailName)
	if old and old:IsA("Model") then
		return old
	end
	local m = DropperShopBuilder.build(frame)
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
