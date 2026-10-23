--[[
	EGGS: the golem egg temple left of the spawn, after the owner's concept
	docs/art/egg_stall_concept.webp (owner 2026-10-21: "with extreme hype, so
	it grabs attention"; 2026-10-22: "it looks narrow and poor; make it wider
	and bigger, walls, cooler details, and some shards"). In the CapsuleStall
	footprint (25 wide, 18 deep, 26 tall; the eggs ~7.6 studs apart, owner
	2026-10-22):

	- a wide two-step staircase up to a round navy-slate dais with a glowing
	  gold and cyan rim; on the floor glowing rings and gold rays
	- four gold pillars behind the side eggs (the front is open), cyan strips on their
	  outer faces, under a thick round navy drum with gold trim and two cyan
	  rings; the big EGGS sign on its front (gold letters on navy, a cyan
	  neon frame, a gold crown on each side)
	- behind the rotunda a curved half ring of navy WALL panels (the egg
	  temple's back and sides) with gold caps, cyan neon strips, gold egg
	  and crown emblems and two hanging banners; the front stays open
	- on the roof a navy dome with gold ribs and a GIANT crowned egg: white
	  with a glowing gold crack, a gold cup, a crown, a beam of light up
	  from it, four gold cannon spokes, two tilted gold orbit rings and four
	  floating crystal shards (rings and shards turn slowly on the client)
	- glowing crystal SHARDS (cyan, violet, gold) in clusters at the wall
	  feet and at the dais' front corners
	- inside, the three eggs (GolemBuilder.capsule with { Calm = true },
	  1.45 times the opening's egg): Stone (viewer's left, +X), ROYAL in the
	  middle (raised, back), Crystal (right), on navy podiums with gold trim,
	  a gold crown plate and a neon ring in the egg's colour; a soft golden
	  light column behind the Royal egg. The eggs turn slowly on the client
	  (tagged "Spin": DecorController, no bob, streams atomically)
	- in front, two navy lantern posts with warm lanterns; the right one
	  carries the odds board (part "OddsBoard": RARITIES and the rarity
	  names from Shared.Config.Rarity on one SurfaceGui with a rarity-
	  coloured RarityChip per row; the client fills it with the real odds,
	  CapsuleController / CapsuleView.fillBoard)

	Contracts (CapsuleService, CapsuleController, tests): the Model is tagged
	CapsuleStall, PrimaryPart = the middle podium named "CapsuleMachine"
	(the "Capsules" prompt stands in front of it, toward the OddsBoard's
	front), one "OddsBoard" part with a SurfaceGui.
	Collision: the stairs, the dais and the podiums are walkable (solid), the
	pillars, the walls and the lantern posts are bumped into (decor),
	everything else (drum, roof, eggs, sign, banners, shards) never collides.
	Part budget: the lobby is near its cap (LobbyLayout.Budget.LobbyParts,
	MapParts; tests/LobbyBudget.spec.luau): the three eggs take ~186 parts,
	the temple round them ~210. Count before adding anything.
	Local frame: 25 wide (piece Size.X), 18 deep, front = -Z (toward the
	plaza and the spawn), +X = the viewer's left (south).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Rarity = require(Shared.Config.Rarity)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Capsules = {}

local rgb = Color3.fromRGB
local NEON = Kit.NEON
local FOIL = Enum.Material.Foil
local SLATE = Enum.Material.Slate
local PI = math.pi

local CZ = 0.3 -- the rotunda's center (local z)
local FLOOR = 1.2 -- the dais top (a plinth and the dais on it)
local PLINTH_D = 17.6 -- the wider plinth under the dais
local DAIS_D = 16.6
local PILLAR_R = 8.1 -- the pillar ring's radius
-- the pillars' angles from the front (-Z) toward +X: open at the front
-- (owner 2026-10-22: the eggs further apart, easy to click: no pillar in
-- front of any egg; the pillars stand behind the side eggs and the walls
-- carry the drum at the back)
local PILLAR_ANGLES = { 100, 124, -124, -100 }
local DRUM_Y0, DRUM_H = 10.5, 3.4 -- the drum's underside and height
local DRUM_D = 17.4
local DRUM_TOP = DRUM_Y0 + DRUM_H
-- the curved back wall: a half ellipse round the rotunda's center
local WALL_RX, WALL_RZ = 11.2, 7.7 -- (the north wall end keeps clear of the west spur lamps)
local WALL_T = 1.8 -- the walls' thickness (owner 2026-10-22: THICK walls)
local WALL_H = 10.4 -- (up to the drum: a closed temple back)
local WALL_FROM, WALL_TO, WALL_SEGS = 72, 288, 10
Capsules.EggScale = 1.45 -- the eggs on the podiums against the opening's egg
Capsules.EggSpin = 0.5 -- radians per second (client, DecorController)
Capsules.SignY = DRUM_Y0 + DRUM_H / 2 -- the EGGS sign center
Capsules.GiantEggY = DRUM_TOP + 5.0 -- the giant egg's center
Capsules.Top = 26 -- the light beam's top (the piece's height)

local GOLD = rgb(255, 196, 56)
local GOLD_GLOW = rgb(240, 160, 20) -- neon gold that stays gold under bloom
local CYAN = rgb(30, 190, 255)
-- the shards: deep enough that the neon keeps its hue under bloom
local SHARD_CYAN = rgb(0, 140, 255)
local SHARD_VIOLET = rgb(110, 30, 255)
local SHARD_GOLD = rgb(225, 130, 0)
local NAVY = rgb(24, 32, 74)
local NAVY_DARK = rgb(14, 18, 46)
local DAIS = rgb(40, 46, 78)
local SHELL = rgb(250, 246, 236)
local LAMP = rgb(255, 180, 90)
local SHARD_COLORS = { SHARD_CYAN, SHARD_VIOLET, SHARD_GOLD }

-- the eggs on their podiums: Stone (left), ROYAL in the middle (raised, back), Crystal (right)
local PODIUMS = {
	{ Id = "Stone", X = 7.2, Z = CZ - 0.6, H = 1.0, Ring = rgb(255, 160, 50) },
	{ Id = "Royal", X = 0, Z = CZ + 2.0, H = 1.8, Ring = rgb(255, 210, 80) },
	{ Id = "Crystal", X = -7.2, Z = CZ - 0.6, H = 1.0, Ring = CYAN },
}
local PODIUM_D = 2.8

-- The egg `id` standing on a podium top at `top` (a CFrame on the podium's
-- axis at its top face), turned by `turn`, scaled about its center.
local function egg(parent: Instance, id: string, top: CFrame, turn: number): Model
	local k = Capsules.EggScale
	local center = top * CFrame.new(0, (1.25 + 0.15) * k, 0) * CFrame.Angles(0, turn, 0)
	local model = GolemBuilder.capsule(id, center, { Calm = true })
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = center:ToObjectSpace(d.CFrame)
			d.CFrame = center * CFrame.new(rel.Position * k) * rel.Rotation
			d.Size *= k
		end
	end
	model.Name = "Egg" .. id
	model.Parent = parent
	-- (the turn is client-side: DecorController spins tagged models about their pivot)
	model:SetAttribute("SpinSpeed", Capsules.EggSpin)
	model:SetAttribute("BobHeight", 0)
	Style.streaming(model, "Atomic")
	Kit.tag(model, "Spin")
	return model
end

-- A small flat crown emblem: a band and diamond points at `points` (shares
-- of w across, 0 = the middle, the middle one bigger), `cf` = the band's
-- center, front = LookVector, w wide. 1 + #points parts.
local function miniCrown(parent: Instance, cf: CFrame, w: number, color: Color3, points: { number }, material: Enum.Material?)
	Kit.bit(parent, cf, Vector3.new(w, w * 0.28, 0.1), color, material or FOIL)
	for _, x in points do
		local s = if x == 0 then w * 0.36 else w * 0.28
		Kit.bit(parent, cf * CFrame.new(x * w, w * 0.2, 0) * CFrame.Angles(0, 0, PI / 4), Vector3.new(s, s, 0.08), color, material or FOIL)
	end
end
local CROWN = { -0.36, 0, 0.36 }

-- An ellipsoid (a block with a sphere mesh), no collision, no shadow.
local function ellipsoid(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Style.block(parent, cf, size, color, material, Style.tiny())
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A glowing crystal shard standing at `base` (its foot), h tall, w thick,
-- leaning by `lean` radians: a square prism turned 45 deg (1 part), with a
-- diamond tip for the big ones (2 parts).
local function shard(parent: Instance, base: CFrame, h: number, w: number, color: Color3, lean: number, tip: boolean?): Part
	local at = base * CFrame.Angles(lean, 0, lean * 0.6) * CFrame.Angles(0, PI / 4, 0)
	local body = Style.block(parent, at * CFrame.new(0, h / 2, 0), Vector3.new(w, h, w), color, NEON, Style.tiny())
	body.Name = "Shard"
	if tip then
		Style.block(
			parent,
			at * CFrame.new(0, h, 0) * CFrame.Angles(PI / 4, 0, 0),
			Vector3.new(w * 0.98, w * 0.7, w * 0.7),
			color:Lerp(Color3.new(1, 1, 1), 0.3),
			NEON,
			Style.tiny()
		).Name =
			"ShardTip"
	end
	return body
end

-- A cluster of shards at `base` (its foot, front = LookVector): a big
-- tipped one and a leaning one beside it, scaled by k; slow sparkles on
-- the big one when `sparkle` (3 parts).
local function cluster(parent: Instance, base: CFrame, k: number, colors: { Color3 }, sparkle: boolean?)
	local big = shard(parent, base, 4.2 * k, 0.95 * k, colors[1], 0.06, true)
	shard(parent, base * CFrame.new(0.75 * k, 0, 0.2 * k), 2.6 * k, 0.6 * k, colors[2], -0.4)
	if sparkle then
		local e = Style.emitter(big, "Sparkle", colors[1]:Lerp(Color3.new(1, 1, 1), 0.4), 2)
		e.LightEmission = 1
	end
end

-- A wall emblem: a glowing gold egg (1 part), `cf` = its center, front = LookVector.
local function eggEmblem(parent: Instance, cf: CFrame, s: number)
	ellipsoid(parent, cf, Vector3.new(0.8 * s, 1.05 * s, 0.08), GOLD_GLOW, NEON).Name = "EggEmblem"
end

function Capsules.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("CapsuleStall")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function pos(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	-- a point on the circle of radius r round the rotunda at angle a
	-- (degrees from the front toward +X)
	local function onRing(r: number, a: number): (number, number)
		local rad = math.rad(a)
		return math.sin(rad) * r, CZ - math.cos(rad) * r
	end
	-- a point on the wall's half ellipse (radius scale k)
	local function onWall(a: number, k: number?): (number, number)
		local rad = math.rad(a)
		local s = k or 1
		return math.sin(rad) * WALL_RX * s, CZ - math.cos(rad) * WALL_RZ * s
	end
	-- a frame at local (x, y, z) facing the rotunda's axis (front = LookVector)
	local function facingIn(x: number, y: number, z: number): CFrame
		return CFrame.lookAt(pos(x, y, z), pos(0, y, CZ))
	end

	---------------------------------------------------------------- stairs and dais
	-- a wide staircase at the front (walkable): three rises of 0.4, gold and cyan neon edges
	local front = CZ - PLINTH_D / 2
	Style.block(m, at(0, 0.2, front - 0.25), Vector3.new(13, 0.4, 0.9), NAVY_DARK, SLATE, Style.solid())
	Style.block(m, at(0, 0.6, front + 0.3), Vector3.new(11, 0.4, 1.0), NAVY_DARK, SLATE, Style.solid())
	Kit.glow(m, at(0, 0.41, front - 0.68), Vector3.new(13, 0.06, 0.08), GOLD_GLOW)
	-- the plinth (walkable) with a gold trim, a band of cyan light, then the dais with a gold rim
	Tech.disc(m, pos(0, 0.4, CZ), 0.8, PLINTH_D, NAVY_DARK, SLATE, Style.solid()).Name = "Plinth"
	Tech.disc(m, pos(0, 0.83, CZ), 0.06, PLINTH_D + 0.12, GOLD, FOIL)
	Tech.disc(m, pos(0, 0.93, CZ), 0.14, DAIS_D + 0.24, CYAN, NEON).Name = "DaisRim"
	Tech.disc(m, pos(0, (0.8 + FLOOR) / 2, CZ), FLOOR - 0.8, DAIS_D, Style.vary(DAIS, rng, 0.02), SLATE, Style.solid()).Name = "Dais"
	Tech.disc(m, pos(0, FLOOR - 0.06, CZ), 0.12, DAIS_D + 0.14, GOLD, FOIL).Name = "DaisRim"
	-- the glowing floor: a gold ring near the edge, a cyan ring in the middle and gold rays between
	-- (owner 2026-10-23: "too bright, I can hardly see the eggs": the floor's gold is gold, not light)
	Tech.disc(m, pos(0, FLOOR + 0.02, CZ), 0.04, DAIS_D - 1.4, GOLD, FOIL)
	Tech.disc(m, pos(0, FLOOR + 0.04, CZ), 0.04, DAIS_D - 1.9, DAIS, SLATE)
	Tech.disc(m, pos(0, FLOOR + 0.06, CZ), 0.04, 4.2, CYAN, NEON)
	Tech.disc(m, pos(0, FLOOR + 0.08, CZ), 0.04, 3.8, DAIS, SLATE)
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * 360
		local x0, z0 = onRing(2.6, a)
		local x1, z1 = onRing(7.4, a)
		Kit.beam(m, pos(x0, FLOOR + 0.07, z0), pos(x1, FLOOR + 0.07, z1), 0.18, 0.04, GOLD).Material = FOIL
	end

	---------------------------------------------------------------- podiums and eggs
	local base: Part? = nil
	for i, pd in PODIUMS do
		local top = FLOOR + pd.H
		local podium = Tech.disc(m, pos(pd.X, FLOOR + pd.H / 2, pd.Z), pd.H, PODIUM_D, NAVY, nil, Style.solid())
		if pd.Id == "Royal" then
			podium.Name = "CapsuleMachine"
			base = podium
		end
		Tech.disc(m, pos(pd.X, top + 0.07, pd.Z), 0.14, PODIUM_D + 0.2, GOLD, FOIL)
		Tech.disc(m, pos(pd.X, top + 0.17, pd.Z), 0.06, PODIUM_D - 0.4, pd.Ring, NEON).Name = "PodiumRing"
		-- a gold crown plate on the podium's front (facing the stall's front)
		miniCrown(m, at(pd.X, FLOOR + pd.H / 2 - 0.08, pd.Z - PODIUM_D / 2 - 0.02), 0.8, GOLD, { 0 })
		egg(m, pd.Id, at(pd.X, top, pd.Z), 0.3 * (i - 2))
	end
	-- a soft golden light column behind the Royal egg
	local column =
		Tech.disc(m, pos(0, (FLOOR + DRUM_Y0) / 2, CZ + 4.8), DRUM_Y0 - FLOOR, 2.4, GOLD_GLOW, NEON, Style.tiny({ Transparency = 0.88 }))
	column.Name = "LightColumn" -- (no PointLight: the lobby's light budget is full; the neon carries it)

	---------------------------------------------------------------- pillars and the drum
	for _, a in PILLAR_ANGLES do
		local x, z = onRing(PILLAR_R, a)
		local h = DRUM_Y0 - FLOOR
		Kit.disc(m, pos(x, FLOOR + h / 2, z), h, 0.85, GOLD, FOIL, Style.decor()).Name = "Pillar"
		-- a cyan strip on the pillar's outer face
		local out = CFrame.lookAt(pos(x, FLOOR + h / 2, z), pos(2 * x, FLOOR + h / 2, 2 * z - CZ))
		Kit.glow(m, out * CFrame.new(0, 0, -0.42), Vector3.new(0.14, h - 2.0, 0.08), CYAN)
	end
	Tech.disc(m, pos(0, DRUM_Y0 + DRUM_H / 2, CZ), DRUM_H, DRUM_D, NAVY, nil, Style.ghost()).Name = "Drum"
	Tech.disc(m, pos(0, DRUM_TOP - 0.1, CZ), 0.2, DRUM_D + 0.16, GOLD, FOIL)
	-- (the rings run above and below the sign's board: they pass in front of it)
	for _, y in { DRUM_Y0 + 0.4, DRUM_TOP - 0.4 } do
		Tech.disc(m, pos(0, y, CZ), 0.14, DRUM_D + 0.14, CYAN, NEON).Name = "DrumRing"
	end

	---------------------------------------------------------------- the EGGS sign
	local signAt = at(0, Capsules.SignY, CZ - DRUM_D / 2 - 0.3)
	-- the casing: a wide navy box with gold lips (the crowns sit on its wings)
	Style.block(m, signAt * CFrame.new(0, 0, 0.5), Vector3.new(11.4, 2.6, 1.0), NAVY_DARK, nil, Style.ghost())
	Kit.bit(m, signAt * CFrame.new(0, 1.36, 0.5), Vector3.new(11.6, 0.18, 1.1), GOLD, FOIL)
	Kit.bit(m, signAt * CFrame.new(0, -1.36, 0.5), Vector3.new(11.6, 0.18, 1.1), GOLD, FOIL)
	Tech.sign(m, signAt, "EGGS", 6.8, 2.4, {
		Casing = false,
		Board = NAVY,
		TextColor = rgb(255, 184, 24),
		Frame = CYAN,
		Studs = false,
	})
	for _, sx in { -1, 1 } do
		miniCrown(m, signAt * CFrame.new(sx * 4.5, -0.15, -0.06), 1.5, GOLD, CROWN)
	end

	---------------------------------------------------------------- the temple wall
	-- a THICK curved half ring of navy stone behind the rotunda: a gold cap
	-- moulding, pilasters with gold caps at every other seam, glowing cyan
	-- windows, gold egg and crown emblems and two banners; the front is open
	local step = (WALL_TO - WALL_FROM) / WALL_SEGS
	local inner = -WALL_T / 2 -- the wall's inner face (local z of a wall frame)
	for i = 1, WALL_SEGS do
		local a0, a1 = WALL_FROM + (i - 1) * step, WALL_FROM + i * step
		local x0, z0 = onWall(a0)
		local x1, z1 = onWall(a1)
		local wa, wb = at(x0, WALL_H / 2, z0).Position, at(x1, WALL_H / 2, z1).Position
		local len = (wb - wa).Magnitude + 0.5
		local dir = (wb - wa).Unit
		local wallCf = CFrame.fromMatrix((wa + wb) / 2, dir, Vector3.yAxis)
		if wallCf.LookVector:Dot(pos(0, WALL_H / 2, CZ) - wallCf.Position) < 0 then
			wallCf = CFrame.fromMatrix((wa + wb) / 2, -dir, Vector3.yAxis)
		end
		-- wallCf: x along the wall, front (LookVector) toward the rotunda
		Style.block(m, wallCf, Vector3.new(len, WALL_H, WALL_T), Style.vary(NAVY, rng, 0.03), SLATE, Style.decor()).Name = "TempleWall"
		Kit.bit(m, wallCf * CFrame.new(0, WALL_H / 2 + 0.22, 0), Vector3.new(len + 0.1, 0.45, WALL_T + 0.5), GOLD, FOIL)
		if i % 2 == 0 and i < WALL_SEGS then
			-- a pilaster on the seam (under the wall's gold cap)
			local px = len / 2 - 0.25
			Style.block(m, wallCf * CFrame.new(px, -0.3, inner - 0.3), Vector3.new(1.0, WALL_H - 0.6, 0.6), NAVY_DARK, SLATE, Style.decor())
		end
		-- emblems: gold eggs on the side panels, banners, crowns in the back, cyan windows between
		if i == 2 or i == WALL_SEGS - 1 then
			eggEmblem(m, wallCf * CFrame.new(0, 1.2, inner - 0.05), 1.7)
		elseif i == 4 or i == WALL_SEGS - 3 then
			-- a banner on the wall: a gold bar, the navy cloth, a glowing egg
			Kit.bit(m, wallCf * CFrame.new(0, 2.9, inner - 0.15), Vector3.new(2.0, 0.18, 0.18), GOLD, FOIL)
			Style.block(m, wallCf * CFrame.new(0, 0.9, inner - 0.08), Vector3.new(1.7, 4.0, 0.06), NAVY_DARK, nil, Style.tiny()).Name =
				"Banner"
			eggEmblem(m, wallCf * CFrame.new(0, 1.3, inner - 0.13), 1.1)
		elseif i == WALL_SEGS / 2 or i == WALL_SEGS / 2 + 1 then
			miniCrown(m, wallCf * CFrame.new(0, 2.6, inner - 0.05), 1.8, GOLD, CROWN)
		else
			-- a tall glowing cyan window set into the wall
			Kit.glow(m, wallCf * CFrame.new(0, 0.4, inner + 0.02), Vector3.new(0.9, 4.4, 0.08), CYAN).Name = "WallWindow"
		end
	end

	---------------------------------------------------------------- shards
	-- big clusters at the wall ends, in front of the wall feet and on gold-trimmed plinths at the plinth's front corners
	local C1 = { SHARD_CYAN, SHARD_VIOLET, SHARD_GOLD }
	local C2 = { SHARD_VIOLET, SHARD_GOLD, SHARD_CYAN }
	local C3 = { SHARD_GOLD, SHARD_CYAN, SHARD_VIOLET }
	for _, sx in { -1, 1 } do
		-- the wall ends
		local x, z = onWall(sx * 75)
		cluster(m, facingIn(x - sx * 0.2, 0, z - 1.6), 1.1, if sx > 0 then C2 else C1, true)
		-- the wall feet, inside
		for j, a in { 103 } do
			local wx, wz = onWall(sx * a)
			local feet = facingIn(wx, FLOOR - 0.15, wz) * CFrame.new(0, 0, -(WALL_T / 2 + 0.9))
			cluster(m, feet, 0.85, if j == 1 then C3 else (if sx > 0 then C1 else C2))
		end
		-- the front corners: a navy plinth with a gold top and a big cluster on it
		local cx, cz = sx * 10.6, CZ - 6.9
		Style.block(m, at(cx, 0.35, cz), Vector3.new(1.8, 0.7, 1.8), NAVY_DARK, SLATE, Style.decor())
		Kit.bit(m, at(cx, 0.72, cz), Vector3.new(1.95, 0.08, 1.95), GOLD, FOIL)
		cluster(m, at(cx, 0.7, cz) * CFrame.Angles(0, sx * 0.4, 0), 0.9, if sx > 0 then C1 else C2, true)
	end

	---------------------------------------------------------------- the dome and the giant egg
	Tech.disc(m, pos(0, DRUM_TOP + 0.5, CZ), 1.0, 13.0, NAVY_DARK, nil, Style.ghost())
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * 360
		local x0, z0 = onRing(8.5, a)
		local x1, z1 = onRing(2.2, a)
		Kit.beam(m, pos(x0, DRUM_TOP, z0), pos(x1, DRUM_TOP + 2.2, z1), 0.34, 0.34, GOLD).Material = FOIL
	end
	local ey = Capsules.GiantEggY
	Tech.disc(m, pos(0, DRUM_TOP + 1.85, CZ), 0.8, 4.8, GOLD, FOIL)
	Tech.disc(m, pos(0, DRUM_TOP + 2.3, CZ), 0.2, 5.0, GOLD_GLOW, NEON)
	local eggAt = at(0, ey, CZ)
	local ew, eh = 5.2, 6.6
	local giant = ellipsoid(m, eggAt, Vector3.new(ew, eh, ew), SHELL, Enum.Material.SmoothPlastic)
	giant.Name = "GiantEgg"
	local glitter = Style.emitter(giant, "Sparkle", rgb(255, 226, 140), 2)
	glitter.LightEmission = 1
	-- a crack down the egg's front surface
	local crack = { { -1.1, 2.2 }, { -0.2, 1.2 }, { -0.8, 0.1 }, { 0.3, -1.1 } }
	local function surf(q: { number }): Vector3
		local x, y = q[1], q[2]
		local s = 1 - (x / (ew / 2)) ^ 2 - (y / (eh / 2)) ^ 2
		return (eggAt * CFrame.new(x, y, -(ew / 2) * math.sqrt(math.max(s, 0.02)) - 0.02)).Position
	end
	for j = 1, #crack - 1 do
		Kit.beam(m, surf(crack[j]), surf(crack[j + 1]), 0.18, 0.1, GOLD_GLOW).Material = NEON
	end
	miniCrown(m, eggAt * CFrame.new(0, eh / 2 + 0.2, -0.25), 2.3, GOLD, CROWN)
	local beamY0 = ey + eh / 2 + 1.2
	Tech.disc(
		m,
		pos(0, (beamY0 + Capsules.Top) / 2, CZ),
		Capsules.Top - beamY0,
		0.8,
		rgb(255, 226, 140),
		NEON,
		Style.tiny({ Transparency = 0.7 })
	).Name =
		"LightBeam"
	-- four gold cannon spokes round the egg's foot, gold balls at their tips
	for i = 1, 4 do
		local a = (i - 0.5) / 4 * 360
		local x0, z0 = onRing(2.2, a)
		local x1, z1 = onRing(6.8, a)
		local p1 = pos(x1, DRUM_TOP + 3.6, z1)
		Tech.rod(m, pos(x0, DRUM_TOP + 2.2, z0), p1, 0.48, GOLD, FOIL)
		Kit.ball(m, p1, 0.85, GOLD, FOIL)
	end
	-- two tilted gold neon orbit rings and four floating shards round the egg, turning on the client
	local orbit = Style.model("Orbit", m)
	local hub = Style.block(orbit, eggAt, Vector3.new(0.2, 0.2, 0.2), GOLD, nil, Style.tiny({ Transparency = 1 }))
	hub.Name = "OrbitHub"
	for r, ring in { { 4.0, 0.38, 0.0 }, { 3.6, -0.42, 0.9 } } do
		local frame = eggAt * CFrame.Angles(0, ring[3], 0) * CFrame.Angles(ring[2], 0, 0)
		local n = 6
		for i = 1, n do
			local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
			local p0 = (frame * CFrame.new(math.cos(a0) * ring[1], 0, math.sin(a0) * ring[1])).Position
			local p1 = (frame * CFrame.new(math.cos(a1) * ring[1], 0, math.sin(a1) * ring[1])).Position
			Kit.beam(orbit, p0, p1, 0.24, 0.24, if r == 1 then GOLD_GLOW else rgb(255, 200, 70)).Material = NEON
		end
	end
	for i = 1, 4 do
		local a = i / 4 * 2 * PI + 0.4
		local p = eggAt * CFrame.new(math.cos(a) * 5.0, (i % 2 - 0.5) * 2.6, math.sin(a) * 5.0)
		Style.block(orbit, p * CFrame.Angles(0.5, a, PI / 4), Vector3.new(0.7, 1.4, 0.7), SHARD_COLORS[(i - 1) % 3 + 1], NEON, Style.tiny()).Name =
			"FloatShard"
	end
	orbit.PrimaryPart = hub
	orbit:SetAttribute("SpinSpeed", 0.6)
	orbit:SetAttribute("BobHeight", 0)
	Style.streaming(orbit, "Atomic")
	Kit.tag(orbit, "Spin")

	---------------------------------------------------------------- lantern posts and the odds board
	-- two navy posts at the front corners, a warm lantern on each; the
	-- right one (viewer's right, -X) carries the RARITIES board
	local postZ = -8.4
	for _, sx in { -1, 1 } do
		local px = sx * 11.4
		local hasBoard = sx < 0
		local postH = if hasBoard then 5.3 else 4.6
		local postW = if hasBoard then 2.3 else 0.9
		Style.block(m, at(px, postH / 2, postZ + 0.1), Vector3.new(postW, postH, 0.6), NAVY_DARK, nil, Style.decor())
		local ly = postH + 0.5
		local lantern = Kit.glow(m, at(px, ly, postZ + 0.1), Vector3.new(0.7, 1.0, 0.7), LAMP)
		lantern.Name = "Lantern"
		Kit.bit(m, at(px, ly + 0.6, postZ + 0.1), Vector3.new(1.0, 0.2, 1.0), GOLD, FOIL)
		Style.light(lantern, LAMP, 12, 1)
	end

	local ox, oz = -11.4, postZ - 0.3
	local by = 2.95 -- the board's center
	local odds = Style.block(m, at(ox, by, oz + 0.02), Vector3.new(1.9, 3.9, 0.1), Tech.Board, nil, Style.decor())
	odds.Name = "OddsBoard"
	odds.CastShadow = false
	-- a gold frame round it
	for _, sy in { -1, 1 } do
		Kit.bit(m, at(ox, by + sy * 2.02, oz), Vector3.new(2.1, 0.14, 0.12), GOLD, FOIL)
		Kit.bit(m, at(ox + sy * 1.0, by, oz), Vector3.new(0.14, 3.9, 0.12), GOLD, FOIL)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Rarities"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = odds
	local rows = #Rarity.List
	local function label(name: string, text: string, ly: number, h: number, lx: number, w: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(lx, ly)
		l.Size = UDim2.fromScale(w, h)
		l.Text = text
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeColor3 = Tech.Board
		l.TextStrokeTransparency = 0
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.FontFace = Font.fromEnum(Style.LabelFont)
		l.Parent = gui
	end
	label("Title", "RARITIES", 0.03, 0.12, 0.08, 0.84, Color3.new(1, 1, 1))
	local rowH = 0.8 / rows
	for i, info in Rarity.List do
		local ry = 0.17 + (i - 1) * rowH
		local marker = Instance.new("Frame")
		marker.Name = "Marker" .. i
		marker.BorderSizePixel = 0
		marker.BackgroundColor3 = info.Color
		marker.Position = UDim2.fromScale(0.08, ry + rowH * 0.22)
		marker.Size = UDim2.fromScale(0.13, rowH * 0.56)
		marker.Parent = gui
		label("Row" .. i, info.Name, ry + rowH * 0.12, rowH * 0.76, 0.27, 0.68, Color3.new(1, 1, 1))
		-- a small rarity-coloured chip beside each row, so the colours read
		-- from afar (and in the preview, which draws no frames)
		if i <= 6 then
			local boardH = 3.9
			local cy = by + boardH / 2 - (ry + rowH * 0.5) * boardH
			Kit.glow(m, at(ox + 0.62, cy, oz - 0.05), Vector3.new(0.3, rowH * boardH * 0.55, 0.05), info.Color).Name = "RarityChip"
		end
	end

	m.PrimaryPart = base
	Kit.tag(m, "CapsuleStall")
end

return Capsules
