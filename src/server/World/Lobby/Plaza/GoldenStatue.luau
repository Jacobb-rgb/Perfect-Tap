--[[
	THE GOLDEN DRAGON in the middle of the plaza (owner 2026-10-25: "a big
	golden statue of this dragon holding the TERRA FORGE sign" - the
	Flamewing golem of the Dragonforge set): the real Flamewing (GolemBuilder)
	built statue-sized and cast in gold, its stubby arms raised in a cheer,
	each fist gripping a gold pole that lifts the big sign (DEEP TERRA since the rename, owner 2026-10-30) over
	its horns and flame mohawk. Its wings, the mohawk and the tail flame keep
	burning in the Flamewing's fire colors with real flames and embers on
	them (owner's pick B, 2026-10-25: "the golden dragon with burning
	wings"); the eyes, the core, the nostrils and the goggle lenses glow.

	It stands on an octagonal pedestal inside the plaza's mechanical ring
	(FireCrystal keeps the ring: the wide base tier and the armor tier): a
	dark metal floor with an orange glow ring, a stepped octagon, a tall
	octagonal drum with gold pilasters, orange and blue glow slits and a
	crossed-hammers emblem front and back, a gold-edged cap.

	The sign (GoldenStatue.Sign):
	  "Wide"  one line, DEEP | hammers medallion | TERRA, gold banner rods
	          at both ends
	  "Logo"  the loading screen's logo: DEEP over TERRA, the hammers
	          medallion on top
	Silver DEEP and gold TERRA on a dark plum board (the loading screen's
	colors), a thick gold frame, an orange glow line inside it, warm bulbs
	round it, readable from both sides.

	build(ring, parent, center, floorY): the pedestal into `ring` (the
	FireCrystalRing model), the dragon and the sign into the Model
	"GoldenStatue" under `parent` (tagged NoStuds: polished gold and fire,
	no classic studs). About 330 parts, no PointLights, 3 emitters
	(owner's Studio test 2026-10-25: "the dragon is terribly overexposed":
	two lights on polished gold, a pale gold and big neon wing panels
	glared in Roblox's Future lighting; the preview's bloom is gentler). The
	statue faces +Z (the spawn); the Star Forge prompt stands at the
	pedestal's front (RebirthService.CrystalFront).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local GolemBuilder = require(Shared.Builders.GolemBuilder)
local GolemConfig = require(Shared.Config.GolemConfig)
local LightingConfig = require(Shared.Config.LightingConfig)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local C = Style.C
local K = Common.Colors
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic
local rgb = Color3.fromRGB

local GoldenStatue = {}

GoldenStatue.Golem = "Flamewing"
GoldenStatue.Size = 6.5 -- x the golem's own Scale (1.15): the horns about 25 studs over its feet
GoldenStatue.Sign = "Wide" -- "Wide" | "Logo"
-- true: the Flamewing's fire stays fire (its wings, flame mohawk and tail
-- flame burn in their own colors on the gold body; owner's pick B)
GoldenStatue.Fire = true
GoldenStatue.ArmRaise = math.rad(145) -- how far the arms swing up from hanging (35 degrees off upright)
-- the wings spread bigger than the pet's (about their shoulder root), so
-- their tips still show past the raised fists from the front
GoldenStatue.WingSpread = 1.4
GoldenStatue.WingLift = math.rad(12) -- and swing a little up and out

-- The town's exposure the statue was toned down under (map v61, owner's
-- Studio test 2026-10-25). When the Surface preset's exposure is higher
-- (owner 2026-10-28: "the town a tiny bit brighter, not the statue") every
-- color on the statue, its pedestal and its sign goes the matching step
-- deeper (GoldenStatue.shade), so the statue keeps the look he approved.
GoldenStatue.TunedExposure = 0.05

-- The per-channel factor that cancels the exposure step (sRGB ~ linear^(1/2.2)).
function GoldenStatue.shadeFactor(): number
	local step = LightingConfig.Presets.Surface.Lighting.ExposureCompensation - GoldenStatue.TunedExposure
	return 2 ^ (-step / 2.2)
end

-- the pedestal (octagon apothems and heights, studs)
GoldenStatue.FloorRadius = 8.6 -- the dark floor inside the armor ring (round)
GoldenStatue.FloorHeight = 0.7
GoldenStatue.GlowRadius = 7.6 -- the orange ring round the step
GoldenStatue.Step = { A = 6.4, H = 1.0 }
GoldenStatue.Drum = { A = 5.0, H = 2.6 }
GoldenStatue.Cap = { A = 5.7, H = 0.6 }
GoldenStatue.Plinth = { A = 3.4, H = 0.5 } -- the gold slab under the feet

-- gold: three tones of one metal (shade by part, never by noise); a deep,
-- saturated gold (Roblox's Metal reflects the bright sunset sky on top of it:
-- the first, paler gold read as a white-hot blob in Studio)
local GOLD = rgb(222, 156, 40)
local GOLD_DEEP = rgb(184, 116, 26)
local GOLD_LIGHT = rgb(236, 180, 70)
local GOLD_PALE = rgb(242, 198, 110)
local AMBER = rgb(255, 128, 22) -- the eyes, the core, the nostrils (deep: no white bloom)
local LENS = rgb(60, 170, 255)
local FIRE_GLOW = rgb(240, 90, 14) -- the fire's neon edges (deep: stays orange under bloom)
local WING_HOT = rgb(255, 140, 36) -- the wings' hot inner panels (plain, not neon: big neon glared)
local FIRE_PLAIN = rgb(240, 96, 24) -- the mohawk's outer flames (plain)
-- the sign
local BOARD = rgb(40, 30, 58) -- the loading screen's dark plum
local SILVER = rgb(232, 234, 244)
local FORGE_GOLD = rgb(255, 178, 36)
local OUTLINE = rgb(22, 14, 30)
local BULB = rgb(255, 146, 40)

local OCT = math.tan(math.pi / 8)

---------------------------------------------------------------- shapes

-- An octagonal prism from four slabs turned 0/45/90/135 degrees (their
-- union is the octagon; a face points to +Z). a = apothem, y = its bottom.
local function octagon(
	parent: Instance,
	center: Vector3,
	y: number,
	a: number,
	h: number,
	color: Color3,
	material: Enum.Material,
	props: { [string]: any }
): { Part }
	local parts = {}
	for i = 0, 3 do
		local cf = CFrame.new(center.X, y + h / 2, center.Z) * CFrame.Angles(0, i * math.pi / 4, 0)
		table.insert(parts, Style.block(parent, cf, Vector3.new(2 * a * OCT, h, 2 * a), color, material, props))
	end
	return parts
end

-- A cylinder along `cf`'s Z (discs facing front).
local function disc(
	parent: Instance,
	cf: CFrame,
	depth: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	props: { [string]: any }
): Part
	local p = Geo.cylinder(parent, cf.Position, depth, diameter, color, material, props)
	p.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	return p
end

-- A cylinder along `cf`'s X (rods lying sideways).
local function rod(
	parent: Instance,
	cf: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	props: { [string]: any }
): Part
	local p = Geo.cylinder(parent, cf.Position, length, diameter, color, material, props)
	p.CFrame = cf
	return p
end

---------------------------------------------------------------- shade

local function shaded(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

-- Every part, particle, letter and outline color under `root` times `k`.
function GoldenStatue.shade(root: Instance, k: number)
	if k == 1 then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = shaded(d.Color, k)
		elseif d:IsA("ParticleEmitter") then
			local keys = {}
			for _, key in d.Color.Keypoints do
				table.insert(keys, ColorSequenceKeypoint.new(key.Time, shaded(key.Value, k)))
			end
			d.Color = ColorSequence.new(keys)
		elseif d:IsA("TextLabel") then
			d.TextColor3 = shaded(d.TextColor3, k)
		elseif d:IsA("UIStroke") then
			d.Color = shaded(d.Color, k)
		end
	end
end

---------------------------------------------------------------- pedestal

local function pedestal(m: Model, center: Vector3, y0: number): number
	local floor = Geo.cylinder(
		m,
		center + Vector3.new(0, y0 + GoldenStatue.FloorHeight / 2, 0),
		GoldenStatue.FloorHeight,
		GoldenStatue.FloorRadius * 2,
		K.MetalDark,
		SMOOTH,
		Style.solid({ CastShadow = false })
	)
	floor.Name = "StatueFloor"
	local y = y0 + GoldenStatue.FloorHeight
	local glow = Geo.cylinder(m, center + Vector3.new(0, y + 0.03, 0), 0.08, GoldenStatue.GlowRadius * 2, K.RingOrange, NEON, Style.tiny())
	glow.Name = "StatueGlow"
	-- the step (dark metal, a gold lip)
	local step = GoldenStatue.Step
	for _, p in octagon(m, center, y, step.A, step.H, K.MetalDark, SMOOTH, Style.solid()) do
		p.Name = "StatueStep"
	end
	for _, p in octagon(m, center, y + step.H - 0.18, step.A + 0.1, 0.18, GOLD_DEEP, METAL, Style.tiny()) do
		p.Name = "StatueTrim"
	end
	y += step.H
	-- the drum: dark machine metal, gold bands, gold pilasters on the corners
	local drum = GoldenStatue.Drum
	for _, p in octagon(m, center, y, drum.A, drum.H, K.Metal, SMOOTH, Style.solid()) do
		p.Name = "StatueDrum"
	end
	for _, band in { { y, 0.35 }, { y + drum.H - 0.4, 0.4 } } do
		for _, p in octagon(m, center, band[1], drum.A + 0.12, band[2], GOLD, METAL, Style.tiny()) do
			p.Name = "StatueBand"
		end
	end
	local vertex = drum.A / math.cos(math.pi / 8)
	local faceW = 2 * drum.A * OCT
	for i = 0, 7 do
		local corner = CFrame.new(center) * CFrame.Angles(0, (i + 0.5) * math.pi / 4, 0)
		Style.block(
			m,
			corner * CFrame.new(0, y + drum.H / 2, vertex - 0.05),
			Vector3.new(0.7, drum.H - 0.5, 0.7),
			GOLD,
			METAL,
			Style.tiny()
		).Name =
			"StatuePilaster"
		local face = CFrame.new(center) * CFrame.Angles(0, i * math.pi / 4, 0)
		-- an orange slit under the top band and a thin blue one over the bottom band
		Style.block(
			m,
			face * CFrame.new(0, y + drum.H - 0.85, drum.A + 0.03),
			Vector3.new(faceW - 1.4, 0.24, 0.08),
			C.Ember,
			NEON,
			Style.tiny()
		).Name =
			"StatueSlot"
		Style.block(
			m,
			face * CFrame.new(0, y + 0.7, drum.A + 0.03),
			Vector3.new(faceW - 1.4, 0.12, 0.08),
			K.NeonBlueDeep,
			NEON,
			Style.tiny()
		).Name =
			"StatueSlotBlue"
		if i % 4 == 0 then
			-- the forge's crossed hammers, gold on a dark disc (front and back)
			local at = face * CFrame.new(0, y + drum.H / 2 - 0.1, drum.A + 0.06)
			disc(m, at, 0.12, 2.3, GOLD_DEEP, METAL, Style.tiny()).Name = "StatueEmblemRim"
			disc(m, at * CFrame.new(0, 0, 0.04), 0.12, 2.0, K.MetalDark, SMOOTH, Style.tiny()).Name = "StatueEmblem"
			-- (Style.icon faces its LookVector: turn the frame to look outward)
			Style.icon(m, at * CFrame.new(0, 0, 0.12) * CFrame.Angles(0, math.pi, 0), "CrossedHammersV2", 1.7, GOLD_LIGHT, METAL)
		end
	end
	y += drum.H
	-- the cap and the gold plinth the dragon stands on
	local cap = GoldenStatue.Cap
	for _, p in octagon(m, center, y, cap.A, cap.H, K.MetalDark, SMOOTH, Style.solid()) do
		p.Name = "StatueCap"
	end
	for _, p in octagon(m, center, y + cap.H - 0.22, cap.A + 0.1, 0.22, GOLD, METAL, Style.tiny()) do
		p.Name = "StatueTrim"
	end
	y += cap.H
	local plinth = GoldenStatue.Plinth
	for _, p in octagon(m, center, y, plinth.A, plinth.H, GOLD_DEEP, METAL, Style.solid()) do
		p.Name = "StatuePlinth"
	end
	return y + plinth.H
end

---------------------------------------------------------------- the dragon

-- part name -> gold tone (by the name before its number)
local DEEP = { Leg = true, Tail = true, Brow = true, GoggleStrap = true, Belt = true, Bracer = true, Arm = true }
local LIGHT = {
	Horn = true,
	Claw = true,
	BellyScale = true,
	WingBone = true,
	Goggle = true,
	Scarf = true,
	ScarfEnd = true,
	Boulder = true,
	Crystal = true,
	TailFlameCore = true,
}
local GLOWS = { Eye = AMBER, Core = AMBER, Nostril = AMBER, Lens = LENS }
local KEEP = { Pupil = true, Sparkle = true }
local FIRE = { WingBone = true, Wing = true, Flame = true, TailFlame = true, TailFlameCore = true }

local function stem(name: string): string
	return (string.match(name, "^(%a+)") or name)
end

local function toneOf(name: string): Color3
	local base = stem(name)
	if string.sub(name, 1, 4) == "Wing" and base ~= "WingBone" then
		-- the three panels: outer gold, middle light, inner pale (the fire wing's
		-- layers; their backs face away from the sun, deep gold read brown there)
		local panel = string.match(name, "_(%d)")
		return if panel == "1" then GOLD elseif panel == "3" then GOLD_PALE else GOLD_LIGHT
	end
	if name == "Flame2" then
		return GOLD_LIGHT
	end
	if DEEP[base] then
		return GOLD_DEEP
	elseif LIGHT[base] then
		return GOLD_LIGHT
	end
	return GOLD
end

-- Swings the arm `i` (with its fist, bracer and claws) up and out round its shoulder.
local function raiseArm(golem: Model, feet: CFrame, i: number)
	local arm = golem:FindFirstChild("Arm" .. i)
	if not (arm and arm:IsA("BasePart")) then
		return
	end
	local shoulder = (arm.CFrame * CFrame.new(0, arm.Size.Y * 0.42, 0)).Position
	local side = if feet:PointToObjectSpace(shoulder).X < 0 then -1 else 1
	local spin = feet.Rotation * CFrame.Angles(0, 0, side * GoldenStatue.ArmRaise) * feet.Rotation:Inverse()
	local turn = CFrame.new(shoulder) * spin * CFrame.new(-shoulder)
	for _, d in golem:GetChildren() do
		if d:IsA("BasePart") then
			local n = d.Name
			if n == "Arm" .. i or n == "Fist" .. i or n == "Bracer" .. i or string.sub(n, 1, 6) == "Claw" .. i .. "_" then
				d.CFrame = turn * d.CFrame
			end
		end
	end
end

-- Spreads both wings (every part named Wing*) about their shoulder root:
-- bigger by WingSpread and swung WingLift up and out. (The root is the
-- Dragonforge wing frame's shoulder point R, golem units x the golem's scale.)
local WING_ROOT = Vector3.new(0.38, 1.42, 0.46)
local function spreadWings(golem: Model, feet: CFrame, s: number)
	for _, d in golem:GetChildren() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Wing" then
			local localPos = feet:PointToObjectSpace(d.CFrame.Position)
			local side = if localPos.X < 0 then -1 else 1
			local root = feet * CFrame.new(side * WING_ROOT.X * s, WING_ROOT.Y * s, WING_ROOT.Z * s)
			local rel = root:ToObjectSpace(d.CFrame)
			local lift = CFrame.Angles(0, 0, side * GoldenStatue.WingLift)
			d.Size *= GoldenStatue.WingSpread
			d.CFrame = root * lift * (CFrame.new(rel.Position * GoldenStatue.WingSpread) * rel.Rotation)
		end
	end
end

local function dragon(parent: Instance, feet: CFrame): Model
	-- (GolemBuilder fronts are their LookVector: turn the feet to face +Z, the spawn)
	local base = CFrame.lookAt(feet.Position, feet.Position + Vector3.new(0, 0, 1))
	local golem = GolemBuilder.build(GoldenStatue.Golem, base, { Size = GoldenStatue.Size })
	golem.Name = "GoldenDragon"
	for _, key in { "Golem", "RootHeight", "Height", "Hover" } do
		golem:SetAttribute(key, nil)
	end
	raiseArm(golem, base, 1)
	raiseArm(golem, base, 2)
	local look = GolemConfig.ById[GoldenStatue.Golem]
	spreadWings(golem, base, (if look then look.Scale or 1 else 1) * GoldenStatue.Size)
	for _, d in golem:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = stem(d.Name)
			local glow = GLOWS[kind]
			if glow then
				d.Color = glow
				d.Material = NEON
			elseif GoldenStatue.Fire and FIRE[kind] then
				-- (the pet's white-hot and yellow neon, statue-sized, bloomed into a
				-- white glare over the plaza: the big wing panels and the flames of
				-- the mohawk and the tail turn plain hot orange, only the thin wing
				-- bones and the tail flame's small core still glow, deep; the
				-- particles keep them burning)
				if d.Material == NEON then
					if kind == "Wing" or kind == "Flame" or kind == "TailFlame" then
						d.Color = if d.Name == "Flame1" or d.Name == "Flame3" then FIRE_PLAIN else WING_HOT
						d.Material = SMOOTH
					else
						d.Color = FIRE_GLOW
					end
				end
			elseif not KEEP[kind] then
				d.Color = toneOf(d.Name)
				d.Material = METAL
			end
			local big = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			d.CastShadow = big > 2 and d.Material ~= NEON
			-- the body blocks collide (players climbing the pedestal can't walk into it)
			if
				kind == "Body"
				or kind == "BodyFill"
				or kind == "Head"
				or kind == "HeadFill"
				or kind == "Leg"
				or kind == "Arm"
				or kind == "Fist"
			then
				d.CanCollide = true
			end
		elseif d:IsA("PointLight") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	golem.Parent = parent
	return golem
end

---------------------------------------------------------------- the sign

-- A word plate (the board behind one word): self-lit text on both faces,
-- a thick dark outline in Roblox (UIStroke). `cf` faces +Z (its LookVector).
-- `back` = the word on its back face (a one-line sign reads its words the
-- other way round from behind: the left plate shows the right word there).
type Word = { Text: string, Color: Color3 }
local function wordPlate(parent: Instance, cf: CFrame, w: number, h: number, depth: number, front: Word, back: Word): Part
	local plate = Style.block(parent, cf, Vector3.new(w, h, depth), BOARD, SMOOTH, Style.ghost())
	plate.Name = "SignWord"
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local word = if face == Enum.NormalId.Front then front else back
		local gui = Instance.new("SurfaceGui")
		gui.Name = if face == Enum.NormalId.Front then "FrontText" else "BackText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.MaxDistance = 600
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(0.94, 0.86)
		label.Position = UDim2.fromScale(0.03, 0.07)
		label.BackgroundTransparency = 1
		label.Text = word.Text
		label.TextScaled = true
		label.TextColor3 = word.Color
		label.FontFace = Font.fromEnum(Style.SignFont)
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = OUTLINE
		stroke.Thickness = 5
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	end
	return plate
end

-- The gold frame round a w x h board centered on `cf` (+Z front), its
-- orange glow line inside and a row of bulbs on both faces.
local function frame(m: Model, cf: CFrame, w: number, h: number, depth: number, t: number)
	local gold = Style.ghost()
	local fd = depth + 0.5
	Style.block(m, cf * CFrame.new(0, h / 2 + t / 2, 0), Vector3.new(w + 2 * t, t, fd), GOLD, METAL, gold).Name = "SignFrame"
	Style.block(m, cf * CFrame.new(0, -h / 2 - t / 2, 0), Vector3.new(w + 2 * t, t, fd), GOLD, METAL, gold).Name = "SignFrame"
	for _, sx in { -1, 1 } do
		Style.block(m, cf * CFrame.new(sx * (w / 2 + t / 2), 0, 0), Vector3.new(t, h, fd), GOLD, METAL, gold).Name = "SignFrame"
	end
	for _, sz in { -1, 1 } do
		local z = sz * (depth / 2 + 0.03)
		local inset = 0.35
		Style.block(m, cf * CFrame.new(0, h / 2 - inset, z), Vector3.new(w - 2 * inset, 0.16, 0.06), C.Fire, NEON, Style.tiny()).Name =
			"SignGlow"
		Style.block(m, cf * CFrame.new(0, -h / 2 + inset, z), Vector3.new(w - 2 * inset, 0.16, 0.06), C.Fire, NEON, Style.tiny()).Name =
			"SignGlow"
		for _, sx in { -1, 1 } do
			Style.block(m, cf * CFrame.new(sx * (w / 2 - inset), 0, z), Vector3.new(0.16, h - 2 * inset, 0.06), C.Fire, NEON, Style.tiny()).Name =
				"SignGlow"
		end
		-- the bulbs along the top and bottom bars
		local fz = sz * (fd / 2 + 0.05)
		local n = math.max(2, math.floor((w + 2 * t) / 2.4))
		for j = 0, n - 1 do
			local x = (j - (n - 1) / 2) * (w + 2 * t - 1.2) / (n - 1)
			for _, yy in { h / 2 + t / 2, -h / 2 - t / 2 } do
				Geo.ball(m, (cf * CFrame.new(x, yy, fz)).Position, 0.42, BULB, NEON, Style.tiny()).Name = "SignBulb"
			end
		end
	end
end

-- The round crossed-hammers medallion (the logo's emblem) centered on `cf`.
local function medallion(m: Model, cf: CFrame, d: number, depth: number)
	disc(m, cf, depth, d, GOLD, METAL, Style.ghost()).Name = "SignMedallion"
	disc(m, cf, depth + 0.1, d - 0.9, OUTLINE, SMOOTH, Style.tiny()).Name = "SignMedallionRing"
	disc(m, cf, depth + 0.2, d - 1.5, K.RingOrange, NEON, Style.tiny()).Name = "SignMedallionFace"
	for _, sz in { -1, 1 } do
		local at = cf * CFrame.new(0, 0, sz * (depth / 2 + 0.25))
		-- (Style.icon faces its frame's LookVector, -Z: turn it for the +Z face)
		local face = if sz > 0 then at * CFrame.Angles(0, math.pi, 0) else at
		Style.icon(m, face, "CrossedHammersV2", d * 0.62, SILVER, METAL)
	end
	-- a ring of bulbs on the rim
	for j = 0, 11 do
		local a = j / 12 * 2 * math.pi
		for _, sz in { -1, 1 } do
			local p = cf * CFrame.new(math.cos(a) * (d / 2 - 0.25), math.sin(a) * (d / 2 - 0.25), sz * (depth / 2 + 0.05))
			Geo.ball(m, p.Position, 0.36, BULB, NEON, Style.tiny()).Name = "SignBulb"
		end
	end
end

-- A gold banner rod standing at a sign's end (ball finials top and bottom).
local function endRod(m: Model, cf: CFrame, h: number)
	local up = cf * CFrame.Angles(0, 0, math.pi / 2)
	rod(m, up, h, 1.5, GOLD, METAL, Style.ghost()).Name = "SignRod"
	for _, sy in { -1, 1 } do
		Geo.ball(m, (cf * CFrame.new(0, sy * (h / 2 + 0.55), 0)).Position, 1.9, GOLD_LIGHT, METAL, Style.tiny()).Name = "SignFinial"
		rod(m, up * CFrame.new(sy * (h / 2 - 0.4), 0, 0), 0.35, 1.9, GOLD_DEEP, METAL, Style.tiny()).Name = "SignRodRing"
	end
end

-- The sign over the dragon: `bottom` = the sign's lowest point (its frame's
-- underside), x/z its center. Nothing up there collides (Style.ghost: 30
-- studs over the plaza no one reaches it, and the walkable plaza stays free). Returns the board's frame (+Z front) and its
-- outer half width.
local FLIP = CFrame.Angles(0, math.pi, 0) -- a part's Front face (its -Z) to the world's +Z
local DEEP_WORD: Word = { Text = "DEEP", Color = SILVER }
local TERRA_WORD: Word = { Text = "TERRA", Color = FORGE_GOLD }
local function sign(m: Model, x: number, bottom: number, z: number): (CFrame, number)
	local t = 0.8
	local depth = 1.0
	if GoldenStatue.Sign == "Logo" then
		local w, h = 20, 11.6
		local cf = CFrame.new(x, bottom + t + h / 2, z)
		wordPlate(m, cf * CFrame.new(0, h / 4, 0) * FLIP, w, h / 2, depth, DEEP_WORD, DEEP_WORD)
		wordPlate(m, cf * CFrame.new(0, -h / 4, 0) * FLIP, w, h / 2, depth, TERRA_WORD, TERRA_WORD)
		frame(m, cf, w, h, depth, t)
		medallion(m, cf * CFrame.new(0, h / 2 + t + 1.6, 0), 6.4, 1.6)
		for _, sx in { -1, 1 } do
			Geo.ball(m, (cf * CFrame.new(sx * (w / 2 + t / 2), h / 2 + t + 0.5, 0)).Position, 1.5, GOLD_LIGHT, METAL, Style.tiny()).Name =
				"SignFinial"
		end
		return cf, w / 2 + t
	end
	-- Wide: DEEP | medallion | TERRA
	local w, h = 33, 6.8
	local md = 9.8
	local cf = CFrame.new(x, bottom + t + h / 2, z)
	local half = (w - md) / 2 - 0.2
	local mid = md / 2 + 0.2 + half / 2
	-- (the spawn side reads DEEP on the left, world -X; from behind that plate is on the right)
	wordPlate(m, cf * CFrame.new(-mid, 0, 0) * FLIP, half, h, depth, DEEP_WORD, TERRA_WORD)
	wordPlate(m, cf * CFrame.new(mid, 0, 0) * FLIP, half, h, depth, TERRA_WORD, DEEP_WORD)
	-- (the board behind the medallion, so the frame's glow line runs unbroken)
	Style.block(m, cf, Vector3.new(md + 0.6, h, depth), BOARD, SMOOTH, Style.tiny()).Name = "SignBoard"
	frame(m, cf, w, h, depth, t)
	medallion(m, cf, md, 1.8)
	for _, sx in { -1, 1 } do
		endRod(m, cf * CFrame.new(sx * (w / 2 + t + 0.5), 0, 0), h + 2 * t + 0.6)
	end
	return cf, w / 2 + t + 1.3
end

---------------------------------------------------------------- build

function GoldenStatue.build(ring: Model, parent: Instance, center: Vector3, floorY: number)
	local k = GoldenStatue.shadeFactor()
	-- the pedestal joins the ring's model, shaded on its own first (the
	-- ring's own pieces keep their colors)
	local base = Instance.new("Model")
	local feetY = pedestal(base, center, floorY)
	GoldenStatue.shade(base, k)
	for _, child in base:GetChildren() do
		child.Parent = ring
	end
	base:Destroy()
	local m = Style.model("GoldenStatue", parent)
	m:AddTag("NoStuds")
	local golem = dragon(m, CFrame.new(center.X, feetY, center.Z))
	-- the poles stand in the raised fists and carry the sign over the head
	local top = feetY
	for _, d in golem:GetDescendants() do
		if d:IsA("BasePart") then
			top = math.max(top, d.CFrame.Position.Y + d.Size.Magnitude * 0.3)
		end
	end
	local bottom = top + 0.8
	local poleZ = 0
	local fists = {}
	for i = 1, 2 do
		local fist = golem:FindFirstChild("Fist" .. i)
		if fist and fist:IsA("BasePart") then
			local p = fist.CFrame.Position
			table.insert(fists, p)
			poleZ += p.Z / 2
		end
	end
	sign(m, center.X, bottom, poleZ)
	for _, p in fists do
		local from = Vector3.new(p.X, p.Y - 2.6, poleZ)
		local to = Vector3.new(p.X, bottom + 0.4, poleZ)
		local pole = rod(
			m,
			CFrame.new((from + to) / 2) * CFrame.Angles(0, 0, math.pi / 2),
			(to - from).Magnitude,
			0.95,
			GOLD_LIGHT,
			METAL,
			Style.ghost()
		)
		pole.Name = "SignPole"
		Geo.ball(m, from, 1.4, GOLD, METAL, Style.tiny()).Name = "SignPoleEnd"
		-- a collar where the pole meets the frame
		Style.block(m, CFrame.new(to.X, bottom + 0.15, poleZ), Vector3.new(1.6, 0.5, 1.6), GOLD_DEEP, METAL, Style.tiny()).Name =
			"SignCollar"
	end
	-- (no lights, no sparkles: the sunset lights the gold; in Studio a light on
	-- the sign and a warm wash on the dragon made the polished gold glare)
	if GoldenStatue.Fire then
		-- the burning wings: flames licking up off each wing's hot inner panel,
		-- embers rising from the flame mohawk
		for i = 1, 2 do
			local panel = golem:FindFirstChild(`Wing{i}_2B`)
			if panel and panel:IsA("BasePart") then
				local flames = Style.emitter(panel, "Fire", C.Fire, 6)
				flames.LightEmission = 0.4 -- (1 added up to a white glow over the wings)
			end
		end
		local mohawk = golem:FindFirstChild("Flame2")
		if mohawk and mohawk:IsA("BasePart") then
			Style.emitter(mohawk, "Embers", C.Fire, 4)
		end
	end
	GoldenStatue.shade(m, k)
end

return GoldenStatue
