--[[
	EGGS: the golem egg stall left of the spawn, after the owner's concept
	docs/art/egg_stall_concept.webp (owner 2026-10-21: "with extreme hype, so
	it grabs attention"; the eggs replace the capsules). A royal ROTUNDA in
	the old capsule stall's footprint (14 x 12, up to ~24 tall):

	- a round navy-slate dais with a glowing gold and cyan rim and a step
	  at the front
	- six gold pillars on a ring, open at the front, each with a cyan neon
	  strip on its outer face
	- a thick round navy drum on them with gold trim and two cyan neon
	  rings
	- the big EGGS sign on the drum's front: gold letters on navy in a cyan
	  neon frame, a gold crown on each side
	- on the roof a navy dome with gold ribs and on it a GIANT
	  crowned egg: white with glowing gold cracks, a gold cup, a gold crown,
	  two tilted gold neon orbit rings (they turn slowly on the client),
	  four gold "cannon" spokes with gold balls and a light beam up from the
	  crown
	- two navy banners with a gold egg emblem on gold poles at the drum's
	  sides
	- inside, the three eggs (GolemBuilder.capsule with { Calm = true },
	  1.45 times the opening's egg): Stone (viewer's left, +X), ROYAL in the
	  middle (raised, a little back), Crystal (right), on navy podiums with
	  gold trim, a gold crown plate and a cyan neon ring; a soft golden
	  light column behind the Royal egg. The eggs turn slowly on the client
	  (tagged "Spin": DecorController, no bob, streams atomically)
	- in front, two navy lantern posts with warm lanterns (a cyan strip);
	  the right one carries the odds board (part "OddsBoard": RARITIES and
	  the rarity names from Shared.Config.Rarity on one SurfaceGui with a
	  rarity-coloured RarityChip per row; the client fills it with the real
	  odds, CapsuleController / CapsuleView.fillBoard)

	Contracts (CapsuleService, CapsuleController, tests): the Model is tagged
	CapsuleStall, PrimaryPart = the middle podium named "CapsuleMachine"
	(the "Capsules" prompt stands in front of it, toward the OddsBoard's
	front), one "OddsBoard" part with a SurfaceGui.
	Collision: the dais, the step and the podiums are walkable (solid), the
	pillars and the lantern posts are bumped into (decor), everything else
	(drum, roof, eggs, sign, banners) never collides.
	Local frame: 14 wide (piece Size.X), 12 deep, front = -Z (toward the
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

local FLOOR = 0.8 -- the dais top
local DAIS_D = 11.6 -- the dais diameter (the footprint is 12 deep)
local PILLAR_R = 5.1 -- the pillar ring's radius
-- the pillars' angles from the front (-Z) toward +X: open at the front
local PILLAR_ANGLES = { 80, 128, 166, -166, -128, -80 }
local DRUM_Y0, DRUM_H = 10.0, 3.2 -- the drum's underside and height
local DRUM_D = 11.0 -- (the sign's board stands in front of its curve)
local DRUM_TOP = DRUM_Y0 + DRUM_H
Capsules.EggScale = 1.45 -- the eggs on the podiums against the opening's egg
Capsules.EggSpin = 0.5 -- radians per second (client, DecorController)
Capsules.SignY = DRUM_Y0 + DRUM_H / 2 -- the EGGS sign center
Capsules.GiantEggY = DRUM_TOP + 4.3 -- the giant egg's center
Capsules.Top = 24 -- the light beam's top: the stall's own height cap (over the layout's 16: the giant egg on the roof)

local GOLD = rgb(255, 196, 56)
local GOLD_GLOW = rgb(240, 160, 20) -- neon gold that stays gold under bloom
local CYAN = rgb(30, 190, 255)
local NAVY = rgb(24, 32, 74)
local NAVY_DARK = rgb(14, 18, 46)
local DAIS = rgb(40, 46, 78)
local SHELL = rgb(250, 246, 236)
local LAMP = rgb(255, 180, 90)

-- the eggs on their podiums: Stone (left), ROYAL in the middle (raised, back), Crystal (right)
local PODIUMS = {
	{ Id = "Stone", X = 3.1, Z = -0.4, H = 1.0, Ring = rgb(255, 160, 50) },
	{ Id = "Royal", X = 0, Z = 1.5, H = 1.7, Ring = rgb(255, 210, 80) },
	{ Id = "Crystal", X = -3.1, Z = -0.4, H = 1.0, Ring = CYAN },
}
local PODIUM_D = 2.7

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

--[[
	Part budget: the lobby is at its cap (LobbyLayout.Budget.LobbyParts,
	tests/LobbyBudget.spec.luau): the three eggs take ~186 parts, so the
	rotunda round them is drawn with ~120 (the stall stays under ~315, the
	old capsule stall's 238 plus the lobby's free parts). Count before
	adding anything.
]]
function Capsules.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("CapsuleStall")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function pos(x: number, y: number, z: number): Vector3
		return at(x, y, z).Position
	end
	-- a point on the ring of radius r at angle a (degrees from the front toward +X)
	local function onRing(r: number, a: number): (number, number)
		local rad = math.rad(a)
		return math.sin(rad) * r, -math.cos(rad) * r
	end

	---------------------------------------------------------------- dais (5 parts)
	Tech.disc(m, pos(0, FLOOR / 2, 0), FLOOR, DAIS_D, Style.vary(DAIS, rng, 0.02), SLATE, Style.solid()).Name = "Dais"
	-- the glowing rim: a gold band at the top edge, a cyan one near the ground
	Tech.disc(m, pos(0, FLOOR - 0.1, 0), 0.16, DAIS_D + 0.16, GOLD_GLOW, NEON).Name = "DaisRim"
	Tech.disc(m, pos(0, 0.25, 0), 0.12, DAIS_D + 0.14, CYAN, NEON).Name = "DaisRim"
	-- the step up at the front (inside the footprint's front line)
	Style.block(m, at(0, 0.2, -5.7), Vector3.new(4.6, 0.4, 0.56), NAVY_DARK, SLATE, Style.solid())
	Kit.glow(m, at(0, 0.41, -5.96), Vector3.new(4.6, 0.06, 0.08), GOLD_GLOW)

	---------------------------------------------------------------- podiums (15) and eggs (~186)
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
		miniCrown(m, at(pd.X, FLOOR + pd.H / 2 - 0.08, pd.Z - PODIUM_D / 2 - 0.02), 0.75, GOLD, { 0 })
		egg(m, pd.Id, at(pd.X, top, pd.Z), 0.3 * (i - 2))
	end
	-- a soft golden light column behind the Royal egg (1)
	local column =
		Tech.disc(m, pos(0, (FLOOR + DRUM_Y0) / 2, 3.4), DRUM_Y0 - FLOOR, 2.0, GOLD_GLOW, NEON, Style.tiny({ Transparency = 0.6 }))
	column.Name = "LightColumn" -- (no PointLight: the lobby's light budget is full; the neon carries it)

	---------------------------------------------------------------- pillars (12)
	for _, a in PILLAR_ANGLES do
		local x, z = onRing(PILLAR_R, a)
		local h = DRUM_Y0 - FLOOR
		Kit.disc(m, pos(x, FLOOR + h / 2, z), h, 0.8, GOLD, FOIL, Style.decor()).Name = "Pillar"
		-- a cyan strip on the pillar's outer face
		local out = CFrame.lookAt(pos(x, FLOOR + h / 2, z), pos(x * 2, FLOOR + h / 2, z * 2))
		Kit.glow(m, out * CFrame.new(0, 0, -0.4), Vector3.new(0.14, h - 2.0, 0.08), CYAN)
	end

	---------------------------------------------------------------- the drum (4)
	Tech.disc(m, pos(0, DRUM_Y0 + DRUM_H / 2, 0), DRUM_H, DRUM_D, NAVY, nil, Style.ghost()).Name = "Drum"
	Tech.disc(m, pos(0, DRUM_TOP - 0.1, 0), 0.2, DRUM_D + 0.16, GOLD, FOIL)
	-- (the rings run above and below the sign's board: they pass in front of it)
	for _, y in { DRUM_Y0 + 0.3, DRUM_TOP - 0.3 } do
		Tech.disc(m, pos(0, y, 0), 0.14, DRUM_D + 0.14, CYAN, NEON).Name = "DrumRing"
	end

	---------------------------------------------------------------- the EGGS sign (~20)
	local signAt = at(0, Capsules.SignY, -5.5)
	-- the casing: a wide navy box with gold lips (the crowns sit on its wings)
	Style.block(m, signAt * CFrame.new(0, 0, 0.5), Vector3.new(9.4, 2.3, 1.0), NAVY_DARK, nil, Style.ghost())
	Kit.bit(m, signAt * CFrame.new(0, 1.2, 0.5), Vector3.new(9.6, 0.16, 1.1), GOLD, FOIL)
	Kit.bit(m, signAt * CFrame.new(0, -1.2, 0.5), Vector3.new(9.6, 0.16, 1.1), GOLD, FOIL)
	Tech.sign(m, signAt, "EGGS", 5.6, 2.1, {
		Casing = false,
		Board = NAVY,
		TextColor = rgb(255, 184, 24),
		Frame = CYAN,
		Studs = false,
	})
	for _, sx in { -1, 1 } do
		miniCrown(m, signAt * CFrame.new(sx * 3.65, -0.1, -0.06), 1.2, GOLD, CROWN)
	end

	---------------------------------------------------------------- banners (6)
	for _, sx in { -1, 1 } do
		local bx, bz = sx * 6.05, -1.6
		local top = DRUM_TOP + 0.8
		-- a gold arm out of the drum, the navy banner and a glowing gold egg emblem
		Tech.rod(m, pos(sx * 5.2, top, bz), pos(bx + sx * 0.7, top, bz), 0.2, GOLD, FOIL)
		local bannerH = 3.0
		local mid = top - 0.1 - bannerH / 2
		Style.block(m, at(bx, mid, bz), Vector3.new(1.3, bannerH, 0.08), NAVY, nil, Style.tiny()).Name = "Banner"
		ellipsoid(m, at(bx, mid + 0.15, bz - 0.06), Vector3.new(0.7, 0.95, 0.04), GOLD_GLOW, NEON)
	end

	---------------------------------------------------------------- the dome (7) and the giant egg
	Tech.disc(m, pos(0, DRUM_TOP + 0.5, 0), 1.0, 8.4, NAVY_DARK, nil, Style.ghost())
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * 360
		local x0, z0 = onRing(5.3, a)
		local x1, z1 = onRing(1.9, a)
		Kit.beam(m, pos(x0, DRUM_TOP, z0), pos(x1, DRUM_TOP + 1.9, z1), 0.32, 0.32, GOLD).Material = FOIL
	end
	-- the giant egg (11): a gold cup, a white shell, glowing gold cracks, a crown, a beam of light
	local ey = Capsules.GiantEggY
	Tech.disc(m, pos(0, DRUM_TOP + 1.65, 0), 0.7, 4.2, GOLD, FOIL)
	Tech.disc(m, pos(0, DRUM_TOP + 2.05, 0), 0.2, 4.4, GOLD_GLOW, NEON)
	local eggAt = at(0, ey, 0)
	ellipsoid(m, eggAt, Vector3.new(4.4, 5.6, 4.4), SHELL, Enum.Material.SmoothPlastic).Name = "GiantEgg"
	-- a crack down the egg's front surface (an ellipsoid with half axes 2.2, 2.8)
	local crack = { { -0.9, 1.9 }, { -0.2, 1.0 }, { -0.7, 0.1 }, { 0.2, -0.9 } }
	local function surf(q: { number }): Vector3
		local x, y = q[1], q[2]
		local s = 1 - (x / 2.2) ^ 2 - (y / 2.8) ^ 2
		return (eggAt * CFrame.new(x, y, -2.2 * math.sqrt(math.max(s, 0.02)) - 0.02)).Position
	end
	for j = 1, #crack - 1 do
		Kit.beam(m, surf(crack[j]), surf(crack[j + 1]), 0.16, 0.1, GOLD_GLOW).Material = NEON
	end
	miniCrown(m, eggAt * CFrame.new(0, 2.9, -0.2), 2.0, GOLD, CROWN)
	local beamY0 = ey + 3.8
	Tech.disc(
		m,
		pos(0, (beamY0 + Capsules.Top) / 2, 0),
		Capsules.Top - beamY0,
		0.7,
		rgb(255, 226, 140),
		NEON,
		Style.tiny({ Transparency = 0.45 })
	).Name =
		"LightBeam"
	-- four gold cannon spokes round the egg's foot, gold balls at their tips (8)
	for i = 1, 4 do
		local a = (i - 0.5) / 4 * 360
		local x0, z0 = onRing(1.8, a)
		local x1, z1 = onRing(4.4, a)
		local p1 = pos(x1, DRUM_TOP + 3.2, z1)
		Tech.rod(m, pos(x0, DRUM_TOP + 1.9, z0), p1, 0.42, GOLD, FOIL)
		Kit.ball(m, p1, 0.75, GOLD, FOIL)
	end
	-- two tilted gold neon orbit rings round the egg, turning on the client (15)
	local orbit = Style.model("Orbit", m)
	local hub = Style.block(orbit, eggAt, Vector3.new(0.2, 0.2, 0.2), GOLD, nil, Style.tiny({ Transparency = 1 }))
	hub.Name = "OrbitHub"
	for r, ring in { { 3.4, 0.38, 0.0 }, { 3.0, -0.42, 0.9 } } do
		local frame = eggAt * CFrame.Angles(0, ring[3], 0) * CFrame.Angles(ring[2], 0, 0)
		local n = 7
		for i = 1, n do
			local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
			local p0 = (frame * CFrame.new(math.cos(a0) * ring[1], 0, math.sin(a0) * ring[1])).Position
			local p1 = (frame * CFrame.new(math.cos(a1) * ring[1], 0, math.sin(a1) * ring[1])).Position
			Kit.beam(orbit, p0, p1, 0.22, 0.22, if r == 1 then GOLD_GLOW else rgb(255, 200, 70)).Material = NEON
		end
	end
	orbit.PrimaryPart = hub
	orbit:SetAttribute("SpinSpeed", 0.6)
	orbit:SetAttribute("BobHeight", 0)
	Style.streaming(orbit, "Atomic")
	Kit.tag(orbit, "Spin")

	---------------------------------------------------------------- lantern posts (7) and the odds board (11)
	-- two navy posts at the front corners, a warm lantern on each; the
	-- right one (viewer's right, -X) carries the RARITIES board
	local postZ = -5.45
	for _, sx in { -1, 1 } do
		local px = sx * 5.7
		local hasBoard = sx < 0
		local postH = if hasBoard then 5.3 else 4.6
		local postW = if hasBoard then 2.3 else 0.9
		Style.block(m, at(px, postH / 2, postZ + 0.1), Vector3.new(postW, postH, 0.6), NAVY_DARK, nil, Style.decor())
		local ly = postH + 0.5
		local lantern = Kit.glow(m, at(px, ly, postZ + 0.1), Vector3.new(0.7, 1.0, 0.7), LAMP)
		lantern.Name = "Lantern"
		Kit.bit(m, at(px, ly + 0.6, postZ + 0.1), Vector3.new(1.0, 0.2, 1.0), GOLD, FOIL)
		Style.light(lantern, LAMP, 12, 1)
		if not hasBoard then
			Kit.glow(m, at(px, postH * 0.45, postZ - 0.22), Vector3.new(0.14, postH * 0.6, 0.06), CYAN)
		end
	end

	local ox, oz = -5.7, postZ - 0.3
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
