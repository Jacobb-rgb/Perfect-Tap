--[[
	Builds the 5 hoverboards (HoverboardData) from parts only (no meshes), in
	the chunky Kenney toy style and the game palette. Every board reads by its
	silhouette at phone size:

	  TimberDrifter     three wooden planks with a kicked, staggered nose, iron
	  (coins 1)         straps with copper bolts, two round iron hover pads with
	                    an amber glow, two copper thruster pods at the tail    37 parts
	  CartCruiser       a steel mine-cart tub: slanted walls above the deck
	  (coins 2)         (the rider stands in a shallow tub) with a copper lip,
	                    rivets and iron corner posts, four cart wheels with
	                    blue hubs, blue glow vents, two headlamps, twin blue
	                    exhausts, a long blue hover pad under the tapered tub   53
	  EmberglassGlider  an obsidian deck on a glowing lava seam over a basalt
	  (coins 3)         layer, lava cracks on top, amber crystal shards fanned
	                    forward on the nose and back on the tail (faceted
	                    hero shards in the middle), two spikes per side leaning
	                    out like fins, a lava hover pad and a lava nozzle      55
	  NeonComet         an indigo arrow deck on a cyan seam with a glowing comet
	  (Robux 1)         orb in a glass shell, a tilted magenta ring and a collar
	                    at the nose, magenta chevrons and speed dashes, raked
	                    tail fins with neon edges and tips, swept side fins,
	                    star twinkles, a big cyan thruster + two small ones     63
	  RoyalPhoenix      a violet deck on gold and violet glow seams, a golden
	  (Robux 2)         phoenix figurehead (slender neck, hooked beak, glowing
	                    eyes, flame crests, crown gem), golden wings raised in
	                    a V (a wing panel + three fanned feathers per side with
	                    flame edges), three fanned tail feathers, a gold
	                    diamond on the grip, the brightest hover glow           70
	Budgets (tests/Hoverboard.spec.luau): coin boards <= 60 parts, Robux <= 80.

	Contract (every board): a Model named after the board id, PrimaryPart "Root"
	(an invisible part) at the GROUND under the board's center, front = -Z, +Y up.
	The deck top (where the feet stand) is DeckHeight studs above Root; the
	lowest glow (the hover pad) floats HoverGap studs above the ground.
	Attachments on Root (HoverboardBuilder.Attachments):
	  Feet        deck top center: the character's feet
	  Pad         the bottom of the hover pad; its +Y points DOWN (emitters
	              there shoot at the ground)
	  Aura        the middle of the board (volume sparkles)
	  Nose        the nose piece (comet orb, phoenix head, plank tip ...)
	  TrailLeft,  the two ends of a flat trail at the tail (Trail.Attachment0 / 1)
	  TrailRight
	  TipLeft,    the outermost tips (wing tips, fin tips; deck sides on the
	  TipRight    coin boards)
	  Exhaust1..N thruster exits; their +Y points BACK (+Z), so emitters
	              there blow out behind the board (attribute "Exhausts" = N)
	Model attributes: BoardId, Effect, DeckHeight, Exhausts.
	Everything is anchored with CanCollide / CanTouch / CanQuery off and only
	the big deck parts cast shadows; HoverboardBuilder.rig(model) unanchors it
	and welds every part to Root (massless) for riding.
	Effects (particles, trails): HoverboardFx.luau.

	Pure and deterministic: only Instance creation, so Lune tests and previews
	can build it.
]]

local HoverboardData = require(script.Parent.Parent.Config.HoverboardData)
local ItemBuilder = require(script.Parent.ItemBuilder)

local HoverboardBuilder = {}

HoverboardBuilder.DeckHeight = 1.5 -- deck top above Root (the feet)
HoverboardBuilder.HoverGap = 0.6 -- ground to the bottom of the hover pad
HoverboardBuilder.MaxParts = { Coins = 60, Robux = 80 } :: { [string]: number }
HoverboardBuilder.Attachments = {
	"Feet",
	"Pad",
	"Aura",
	"Nose",
	"TrailLeft",
	"TrailRight",
	"TipLeft",
	"TipRight",
	"Exhaust1",
}

local TOP = HoverboardBuilder.DeckHeight
local GAP = HoverboardBuilder.HoverGap

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local IRON = rgb(58, 60, 72)
local BRASS = rgb(226, 178, 78)
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local WOOD = Enum.Material.Wood
local GLASS = Enum.Material.Glass
local PLATE = Enum.Material.DiamondPlate

local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- Roblox cylinders run along X
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

type Kind = "Block" | "Wedge" | "Cylinder" | "Ball"
type Opts = { Shadow: boolean?, Transparency: number? }
type Ctx = {
	model: Model,
	root: BasePart,
	colors: HoverboardData.Colors,
	exhausts: number,
}

local function glow(color: Color3): Color3
	return ItemBuilder.glowColor(color)
end

local function part(
	c: Ctx,
	name: string,
	kind: Kind,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if kind == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		elseif kind == "Ball" then
			block.Shape = Enum.PartType.Ball
		end
		p = block
	end
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = opts ~= nil and opts.Shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if opts and opts.Transparency then
		p.Transparency = opts.Transparency
	end
	p.Parent = c.model
	return p
end

local function block(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	return part(c, name, "Block", cf, size, color, material, opts)
end

-- A flat disc (cylinder standing on Y) centered on `cf`.
local function disc(
	c: Ctx,
	name: string,
	cf: CFrame,
	diameter: number,
	thick: number,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
): BasePart
	return part(c, name, "Cylinder", cf * ALONG_Y, Vector3.new(thick, diameter, diameter), color, material, opts)
end

-- A cylinder whose axis runs along the frame's Z (thrusters, nozzles).
local function tube(c: Ctx, name: string, cf: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	return part(c, name, "Cylinder", cf * ALONG_Z, Vector3.new(length, diameter, diameter), color, material)
end

-- A cylinder whose axis runs along X (wheels).
local function axle(
	c: Ctx,
	name: string,
	position: Vector3,
	width: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(c, name, "Cylinder", CFrame.new(position), Vector3.new(width, diameter, diameter), color, material)
end

local function ball(
	c: Ctx,
	name: string,
	position: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
): BasePart
	return part(c, name, "Ball", CFrame.new(position), Vector3.new(diameter, diameter, diameter), color, material, opts)
end

--[[
	A wedge whose triangle has its right angle at `corner`, one leg `legA`
	(becomes the wedge's height) and the other `legB` (perpendicular to legA),
	extruded `depth` studs across the triangle's plane, centered on it.
]]
local function rightWedge(
	c: Ctx,
	name: string,
	corner: Vector3,
	legA: Vector3,
	legB: Vector3,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
): BasePart
	local up = legA.Unit
	local back = -legB.Unit
	local right = up:Cross(back)
	local cf = CFrame.fromMatrix(corner + legA / 2 + legB / 2, right, up, back)
	return part(c, name, "Wedge", cf, Vector3.new(depth, legA.Magnitude, legB.Magnitude), color, material, opts)
end

-- A bar from `a` to `b` (w wide, h tall; `up` keeps its flat side up).
local function bar(
	c: Ctx,
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color: Color3,
	material: Enum.Material?,
	up: Vector3?
): BasePart
	local mid = (a + b) / 2
	return block(c, name, CFrame.lookAt(mid, b, up or Vector3.yAxis), Vector3.new(w, h, (b - a).Magnitude), color, material)
end

-- A rounded slab (block + a disc at each end) along Z, centered on `cf`. 3 parts.
local function pill(
	c: Ctx,
	name: string,
	cf: CFrame,
	width: number,
	length: number,
	thick: number,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
)
	local straight = math.max(0.05, length - width)
	block(c, name, cf, Vector3.new(width, thick, straight), color, material, opts)
	disc(c, name, cf * CFrame.new(0, 0, -straight / 2), width, thick, color, material, opts)
	disc(c, name, cf * CFrame.new(0, 0, straight / 2), width, thick, color, material, opts)
end

-- An arrow deck: a pointed nose (two wedges) from zNose to zJoint, a slab to
-- zTail and a round tail disc. 4 parts.
local function arrow(
	c: Ctx,
	name: string,
	y: number,
	thick: number,
	width: number,
	zNose: number,
	zJoint: number,
	zTail: number,
	color: Color3,
	material: Enum.Material?,
	opts: Opts?
)
	block(c, name, CFrame.new(0, y, (zJoint + zTail) / 2), Vector3.new(width, thick, zTail - zJoint), color, material, opts)
	disc(c, name, CFrame.new(0, y, zTail), width, thick, color, material, opts)
	for _, s in { -1, 1 } do
		rightWedge(
			c,
			name,
			Vector3.new(0, y, zJoint),
			Vector3.new(s * width / 2, 0, 0),
			Vector3.new(0, 0, zNose - zJoint),
			thick,
			color,
			material,
			opts
		)
	end
end

-- A faceted crystal shard standing on `base` (+Y = growth): a diamond-section
-- body (with a darker octagon facet block when `facet` is given) and a two-tone
-- glowing ridge tip. 3-4 parts.
local function shard(c: Ctx, base: CFrame, height: number, width: number, body: Color3, facet: Color3?, tipA: Color3, tipB: Color3)
	local bodyH = height * 0.74
	local tipH = height - bodyH
	local bodyCf = base * CFrame.Angles(0, math.pi / 4, 0)
	block(c, "Crystal", bodyCf * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), body)
	if facet then
		-- a darker octagon block through the body: alternating light and dark faces like a cut gem
		block(c, "CrystalFacet", base * CFrame.new(0, bodyH * 0.49, 0), Vector3.new(width * 0.84, bodyH * 0.98, width * 0.84), facet)
	end
	local tipAt = bodyCf * CFrame.new(0, bodyH + tipH / 2, 0)
	part(c, "CrystalTip", "Wedge", tipAt * CFrame.new(0, 0, -width / 4), Vector3.new(width, tipH, width / 2), tipA, NEON)
	part(
		c,
		"CrystalTip",
		"Wedge",
		tipAt * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(width, tipH, width / 2),
		tipB,
		NEON
	)
end

-- A little light star: two crossed neon bars. 2 parts.
local function twinkle(c: Ctx, position: Vector3, size: number, color: Color3, turn: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, turn, 0)
	block(c, "Twinkle", cf, Vector3.new(size, 0.03, size * 0.16), color, NEON)
	block(c, "Twinkle", cf * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(size * 0.7, 0.03, size * 0.16), color, NEON)
end

local function attach(c: Ctx, name: string, cf: CFrame)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = c.root
end

-- An exhaust pointing back (+Z): the attachment's +Y looks along +Z.
local function exhaust(c: Ctx, position: Vector3)
	c.exhausts += 1
	attach(c, "Exhaust" .. c.exhausts, CFrame.new(position) * CFrame.Angles(math.pi / 2, 0, 0))
end

local function commonAttachments(c: Ctx, tail: number, trailX: number, trailY: number, tipLeft: Vector3, tipRight: Vector3, nose: Vector3)
	attach(c, "Feet", CFrame.new(0, TOP, 0))
	attach(c, "Pad", CFrame.new(0, GAP, 0) * CFrame.Angles(math.pi, 0, 0))
	attach(c, "Aura", CFrame.new(0, TOP - 0.2, 0))
	attach(c, "Nose", CFrame.new(nose))
	attach(c, "TrailLeft", CFrame.new(-trailX, trailY, tail))
	attach(c, "TrailRight", CFrame.new(trailX, trailY, tail))
	attach(c, "TipLeft", CFrame.new(tipLeft))
	attach(c, "TipRight", CFrame.new(tipRight))
end

---------------------------------------------------------------- coin boards

-- Coins 1: planks, straps, copper bolts, two round pads, two thruster pods.
local function timberDrifter(c: Ctx)
	local col = c.colors
	local woods = { col.Main:Lerp(BLACK, 0.14), col.Main:Lerp(WHITE, 0.1), col.Main:Lerp(BLACK, 0.05) }
	local thick = 0.3
	local y = TOP - thick / 2
	local width, gap = 0.8, 0.06
	local tail, joint = 2.7, -1.75
	local kickAngle = 0.34
	for i, x in { -(width + gap), 0, width + gap } do
		local tone = woods[i]
		block(c, "Plank", CFrame.new(x, y, (tail + joint) / 2), Vector3.new(width, thick, tail - joint), tone, WOOD, { Shadow = true })
		-- the kicked nose: the middle plank sticks out further (a pointed, handmade nose)
		local kick = if i == 2 then 1.45 else 1.05
		local kickCf = CFrame.new(x, y, joint) * CFrame.Angles(kickAngle, 0, 0) * CFrame.new(0, 0, -kick / 2 + 0.06)
		block(c, "PlankKick", kickCf, Vector3.new(width, thick, kick + 0.12), tone, WOOD, { Shadow = true })
		-- a darker grain line along the plank
		local grainX = x + (if i == 1 then 0.18 elseif i == 2 then -0.14 else 0.1)
		block(
			c,
			"Grain",
			CFrame.new(grainX, TOP, 0.55 + (i - 2) * 0.3),
			Vector3.new(0.07, 0.03, 2.4 - math.abs(i - 2) * 0.4),
			tone:Lerp(BLACK, 0.3),
			WOOD
		)
	end
	-- iron straps across the planks, three copper bolts each
	for _, z in { joint + 0.25, tail - 0.45 } do
		block(c, "Strap", CFrame.new(0, TOP + 0.03, z), Vector3.new(2.74, 0.08, 0.34), col.Accent, METAL)
		for _, x in { -(width + gap), 0, width + gap } do
			ball(c, "Bolt", Vector3.new(x, TOP + 0.08, z), 0.2, col.Trim, METAL)
		end
	end
	-- battens under the planks (the front one hides the kick seam from below)
	for _, z in { joint - 0.15, tail - 0.25 } do
		block(c, "Batten", CFrame.new(0, TOP - thick - 0.1, z), Vector3.new(2.46, 0.2, 0.42), woods[1]:Lerp(BLACK, 0.3), WOOD)
	end
	-- the copper cap over the plank ends at the tail
	block(c, "TailCap", CFrame.new(0, y, tail + 0.05), Vector3.new(2.66, thick + 0.08, 0.12), col.Trim, METAL)
	-- two round iron hover pads with a copper rim and an amber glow lens
	for _, z in { -0.8, 1.3 } do
		local padTop = TOP - thick
		disc(c, "PadHousing", CFrame.new(0, (padTop + GAP + 0.16) / 2, z), 1.6, padTop - GAP - 0.16, col.Accent)
		disc(c, "PadRim", CFrame.new(0, GAP + 0.26, z), 1.78, 0.1, col.Trim, METAL)
		disc(c, "PadGlow", CFrame.new(0, GAP + 0.08, z), 1.2, 0.16, glow(col.Glow), NEON)
	end
	-- two copper thruster pods hanging off the tail corners
	for _, s in { -1, 1 } do
		local x, py = s * 1.44, 1.24
		tube(c, "Pod", CFrame.new(x, py, 1.95), 1.5, 0.62, col.Trim, METAL)
		ball(c, "PodNose", Vector3.new(x, py, 1.2), 0.62, col.Trim, METAL)
		tube(c, "PodBand", CFrame.new(x, py, 1.85), 0.14, 0.7, col.Accent, METAL)
		tube(c, "Nozzle", CFrame.new(x, py, 2.8), 0.2, 0.68, col.Accent, METAL)
		tube(c, "NozzleGlow", CFrame.new(x, py, 2.92), 0.06, 0.52, glow(col.Glow), NEON)
		exhaust(c, Vector3.new(x, py, 2.97))
	end
	local noseZ = joint - math.cos(kickAngle) * 1.45
	commonAttachments(
		c,
		tail + 0.1,
		0.95,
		TOP - 0.15,
		Vector3.new(-1.3, TOP - 0.15, 0),
		Vector3.new(1.3, TOP - 0.15, 0),
		Vector3.new(0, TOP + 0.3, noseZ)
	)
end

-- Coins 2: a riveted steel mine-cart tub with a copper rim, wheels, blue vents.
local function cartCruiser(c: Ctx)
	local col = c.colors
	local steel = col.Main
	local blue = glow(col.Glow)
	local bodyBottom, bodyTop = 1.0, TOP - 0.06
	block(
		c,
		"Tub",
		CFrame.new(0, (bodyBottom + bodyTop) / 2, 0),
		Vector3.new(2.5, bodyTop - bodyBottom, 5.0),
		steel,
		nil,
		{ Shadow = true }
	)
	block(c, "DeckPlate", CFrame.new(0, TOP - 0.03, 0), Vector3.new(2.16, 0.06, 4.5), col.Accent:Lerp(WHITE, 0.3), PLATE)
	-- the copper rim lip around the top edge
	for _, s in { -1, 1 } do
		-- slanted tub walls above the deck (the rider stands in a shallow mine-cart
		-- tub), a copper lip on top, rivets along the long sides
		local lean = 0.32
		local wallH = 0.62
		local side = CFrame.new(s * 1.2, bodyTop - 0.06, 0) * CFrame.Angles(0, 0, -s * lean) * CFrame.new(0, wallH / 2, 0)
		block(c, "TubWall", side, Vector3.new(0.14, wallH, 4.9), steel:Lerp(WHITE, 0.08))
		block(c, "Lip", side * CFrame.new(0, wallH / 2, 0), Vector3.new(0.24, 0.12, 5.06), col.Trim, METAL)
		local endWall = CFrame.new(0, bodyTop - 0.06, s * 2.45) * CFrame.Angles(s * lean, 0, 0) * CFrame.new(0, wallH / 2, 0)
		block(c, "TubWall", endWall, Vector3.new(2.4, wallH, 0.14), steel:Lerp(WHITE, 0.08))
		block(c, "Lip", endWall * CFrame.new(0, wallH / 2, 0), Vector3.new(2.78, 0.12, 0.24), col.Trim, METAL)
		for _, z in { -1.6, 0, 1.6 } do
			ball(c, "Rivet", (side * CFrame.new(s * 0.07, 0.02, z)).Position, 0.16, BRASS, METAL)
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local foot = Vector3.new(sx * 1.2, bodyTop - 0.06, sz * 2.45)
			local top = foot + Vector3.new(sx * 0.2, 0.6, sz * 0.2)
			bar(c, "CornerPost", foot, top, 0.2, 0.2, col.Accent, METAL, Vector3.new(sx, 0, sz))
		end
	end
	-- the tapered bottom of the tub: flanks + a narrower base
	local baseY = 0.76
	for _, s in { -1, 1 } do
		rightWedge(
			c,
			"Flank",
			Vector3.new(s * 0.85, bodyBottom, 0),
			Vector3.new(0, baseY - bodyBottom, 0),
			Vector3.new(s * 0.4, 0, 0),
			4.8,
			steel:Lerp(BLACK, 0.18)
		)
	end
	block(c, "TubBase", CFrame.new(0, (baseY + bodyBottom) / 2, 0), Vector3.new(1.7, bodyBottom - baseY, 4.6), steel:Lerp(BLACK, 0.28))
	-- the long blue hover pad
	block(c, "PadHousing", CFrame.new(0, baseY - 0.05, 0), Vector3.new(1.3, 0.1, 3.8), IRON)
	pill(c, "PadGlow", CFrame.new(0, GAP + 0.03, 0), 1.1, 3.6, 0.06, blue, NEON)
	-- four cart wheels outside the tub, blue glowing hubs
	for _, s in { -1, 1 } do
		for _, z in { -1.65, 1.65 } do
			axle(c, "Wheel", Vector3.new(s * 1.47, 1.05, z), 0.2, 0.9, col.Accent, METAL)
			axle(c, "WheelHub", Vector3.new(s * 1.49, 1.05, z), 0.28, 0.34, blue, NEON)
		end
		-- two blue glow vents on each side between the wheels
		for _, z in { -0.55, 0.55 } do
			block(c, "Vent", CFrame.new(s * 1.262, 1.125, z), Vector3.new(0.04, 0.17, 0.8), IRON)
			block(c, "VentGlow", CFrame.new(s * 1.275, 1.125, z), Vector3.new(0.05, 0.07, 0.62), blue, NEON)
		end
	end
	-- two headlamps and an iron bumper at the front
	for _, s in { -1, 1 } do
		tube(c, "Lamp", CFrame.new(s * 0.7, 1.12, -2.58), 0.16, 0.44, BRASS, METAL)
		tube(c, "LampGlow", CFrame.new(s * 0.7, 1.12, -2.68), 0.06, 0.32, glow(col.Glow2), NEON)
	end
	block(c, "Bumper", CFrame.new(0, 0.9, -2.5), Vector3.new(2.0, 0.14, 0.18), col.Accent, METAL)
	-- twin blue exhausts at the back
	for _, s in { -1, 1 } do
		tube(c, "Exhaust", CFrame.new(s * 0.7, 1.12, 2.68), 0.4, 0.36, col.Accent, METAL)
		tube(c, "ExhaustGlow", CFrame.new(s * 0.7, 1.12, 2.9), 0.05, 0.26, blue, NEON)
		exhaust(c, Vector3.new(s * 0.7, 1.12, 2.95))
	end
	commonAttachments(c, 2.7, 1.0, 1.25, Vector3.new(-1.5, 1.1, 0), Vector3.new(1.5, 1.1, 0), Vector3.new(0, 1.12, -2.75))
end

-- Coins 3: obsidian on a lava seam, lava cracks, amber crystal shards.
local function emberglassGlider(c: Ctx)
	local col = c.colors
	local lava = glow(col.Glow)
	local amber = col.Accent
	local tipA, tipB = glow(col.Glow2), lava
	pill(c, "Deck", CFrame.new(0, TOP - 0.12, 0), 2.6, 6.0, 0.24, col.Main, nil, { Shadow = true })
	pill(c, "LavaSeam", CFrame.new(0, TOP - 0.28, 0), 2.74, 6.14, 0.08, lava, NEON)
	pill(c, "Basalt", CFrame.new(0, TOP - 0.47, 0), 2.4, 5.7, 0.3, col.Trim, nil, { Shadow = true })
	-- lava cracks on the deck
	bar(c, "LavaCrack", Vector3.new(0, TOP, -2.35), Vector3.new(0, TOP, 2.35), 0.12, 0.03, lava, NEON)
	for _, crack in { { -1.6, 0.8, -2.3 }, { -0.4, -0.9, -1.05 }, { 0.8, 0.85, 1.5 }, { 1.7, -0.8, 2.35 } } do
		bar(c, "LavaCrack", Vector3.new(0, TOP, crack[1]), Vector3.new(crack[2], TOP, crack[3]), 0.1, 0.03, lava, NEON)
	end
	-- emberglass crystal clusters: three shards fanned forward on the nose, three
	-- fanned back on the tail (the middle ones with a lava core), and two short
	-- spikes on each side leaning far out like fins
	local light, dark = amber, amber:Lerp(BLACK, 0.35)
	for k, spec in { { 0, 1.3, 0.42, 0.0 }, { -1, 0.95, 0.32, 0.45 }, { 1, 0.95, 0.32, 0.45 } } do
		local sx, height, width, out = spec[1], spec[2], spec[3], spec[4]
		local nose = CFrame.new(sx * 0.42, TOP - 0.15, -2.35 + math.abs(sx) * 0.25) * CFrame.Angles(-0.8, 0, -sx * out)
		shard(c, nose, height, width, light, if k == 1 then dark else nil, tipA, tipB)
		local tail = CFrame.new(sx * 0.48, TOP - 0.15, 2.3 - math.abs(sx) * 0.2) * CFrame.Angles(0.55, 0, -sx * out)
		shard(c, tail, height * 1.2, width, light, if k == 1 then dark else nil, tipA, tipB)
	end
	for _, s in { -1, 1 } do
		for i, z in { -0.95, 0.75 } do
			local base = CFrame.new(s * 1.12, TOP - 0.22, z) * CFrame.Angles(0.35, 0, -s * 1.0)
			shard(c, base, 0.7 + 0.1 * i, 0.28, light:Lerp(BLACK, 0.12), nil, tipA, tipB)
		end
	end
	-- the lava hover pad and the rear nozzle
	pill(c, "PadHousing", CFrame.new(0, GAP + 0.2, 0), 1.6, 3.8, 0.16, col.Trim:Lerp(BLACK, 0.35))
	pill(c, "PadGlow", CFrame.new(0, GAP + 0.06, 0), 1.3, 3.4, 0.12, lava, NEON)
	tube(c, "Nozzle", CFrame.new(0, 1.05, 2.95), 0.5, 0.8, col.Main)
	tube(c, "NozzleGlow", CFrame.new(0, 1.05, 3.22), 0.06, 0.56, lava, NEON)
	exhaust(c, Vector3.new(0, 1.05, 3.28))
	commonAttachments(
		c,
		3.0,
		0.9,
		1.2,
		Vector3.new(-1.6, TOP + 0.5, -0.25),
		Vector3.new(1.6, TOP + 0.5, -0.25),
		Vector3.new(0, TOP + 0.55, -3.0)
	)
end

---------------------------------------------------------------- Robux boards

-- Robux 1: a navy arrow deck with a comet orb, fins and neon edges.
local function neonComet(c: Ctx)
	local col = c.colors
	local cyan, magenta = glow(col.Glow), glow(col.Glow2)
	local navy = col.Main
	local zNose, zJoint, zTail = -3.2, -1.4, 2.0
	arrow(c, "Deck", TOP - 0.15, 0.22, 2.5, zNose, zJoint, zTail, navy, nil, { Shadow = true })
	arrow(c, "NeonSeam", TOP - 0.3, 0.08, 2.64, zNose - 0.16, zJoint, zTail, cyan, NEON)
	arrow(c, "Hull", TOP - 0.48, 0.28, 2.3, zNose + 0.3, zJoint + 0.1, zTail - 0.1, navy:Lerp(BLACK, 0.3), nil, { Shadow = true })
	-- the grip with a cyan centre stripe, magenta chevrons on the nose
	block(c, "Grip", CFrame.new(0, TOP - 0.02, 0.35), Vector3.new(1.9, 0.04, 3.0), navy:Lerp(BLACK, 0.45))
	block(c, "Stripe", CFrame.new(0, TOP + 0.005, 0.35), Vector3.new(0.14, 0.03, 2.8), cyan, NEON)
	for _, z in { -1.45, -1.95, -2.45 } do
		for _, s in { -1, 1 } do
			bar(c, "Chevron", Vector3.new(s * 0.45, TOP - 0.03, z + 0.36), Vector3.new(0, TOP - 0.03, z), 0.13, 0.03, magenta, NEON)
		end
	end
	-- star twinkles on the deck sides
	for i, p in { { -1.08, -0.45 }, { 1.08, 0.2 }, { -1.08, 1.35 }, { 1.08, 1.75 } } do
		twinkle(c, Vector3.new(p[1], TOP - 0.03, p[2]), 0.3, glow(col.Glow:Lerp(col.Trim, 0.4)), i * 0.5)
	end
	-- the comet orb: a glowing core in a glass shell, a magenta ring around it
	local orb = Vector3.new(0, TOP - 0.18, zNose - 0.2)
	ball(c, "CometCore", orb, 0.78, cyan, NEON)
	ball(c, "CometShell", orb, 1.12, col.Trim, GLASS, { Transparency = 0.45 })
	disc(c, "CometRing", CFrame.new(orb) * CFrame.Angles(0.25, 0, 0), 1.5, 0.05, magenta, NEON)
	tube(c, "OrbCollar", CFrame.new(0, orb.Y, zNose + 0.05), 0.5, 0.6, navy:Lerp(WHITE, 0.15))
	tube(c, "OrbCollarGlow", CFrame.new(0, orb.Y, zNose - 0.2), 0.08, 0.7, cyan, NEON)
	-- magenta speed dashes along the deck sides
	for _, s in { -1, 1 } do
		for k, z in { -0.7, 0.25, 1.2 } do
			block(c, "SpeedDash", CFrame.new(s * 1.255, TOP - 0.13, z), Vector3.new(0.04, 0.07, 0.62 - 0.12 * (k - 1)), magenta, NEON)
		end
	end
	-- raked tail fins (canted out) with cyan leading edges
	for _, s in { -1, 1 } do
		local corner = Vector3.new(s * 0.9, TOP, 2.9)
		local legA = Vector3.new(s * math.sin(0.22), math.cos(0.22), 0) * 1.15
		local legB = Vector3.new(0, 0, -1.5)
		rightWedge(c, "TailFin", corner, legA, legB, 0.14, navy:Lerp(WHITE, 0.12))
		bar(c, "FinEdge", corner + legA, corner + legB, 0.1, 0.1, cyan, NEON, Vector3.new(s, 0, 0))
		ball(c, "FinTip", corner + legA, 0.24, magenta, NEON)
	end
	-- swept magenta side fins with neon edges
	local tips: { Vector3 } = {}
	for _, s in { -1, 1 } do
		local corner = Vector3.new(s * 1.2, TOP - 0.2, 1.9)
		local legA = Vector3.new(s * 0.94, 0.13, 0)
		local legB = Vector3.new(0, 0, -1.7)
		rightWedge(c, "SideFin", corner, legA, legB, 0.1, col.Accent:Lerp(BLACK, 0.2))
		bar(c, "SideFinEdge", corner + legA, corner + legB, 0.08, 0.12, magenta, NEON)
		table.insert(tips, corner + legA)
	end
	-- the big cyan thruster and two small magenta ones
	local thrusterY = TOP - 0.3
	tube(c, "Thruster", CFrame.new(0, thrusterY, 3.3), 0.5, 1.0, navy:Lerp(BLACK, 0.2))
	tube(c, "ThrusterRing", CFrame.new(0, thrusterY, 3.45), 0.12, 1.14, magenta, NEON)
	tube(c, "ThrusterGlow", CFrame.new(0, thrusterY, 3.57), 0.06, 0.66, cyan, NEON)
	exhaust(c, Vector3.new(0, thrusterY, 3.62))
	for _, s in { -1, 1 } do
		tube(c, "SideThruster", CFrame.new(s * 0.75, 1.02, 2.9), 0.6, 0.46, navy:Lerp(BLACK, 0.2))
		tube(c, "SideThrusterGlow", CFrame.new(s * 0.75, 1.02, 3.22), 0.05, 0.3, magenta, NEON)
		exhaust(c, Vector3.new(s * 0.75, 1.02, 3.26))
	end
	-- the cyan hover pad
	pill(c, "PadHousing", CFrame.new(0, GAP + 0.2, 0.2), 1.5, 3.6, 0.16, navy:Lerp(BLACK, 0.5))
	pill(c, "PadGlow", CFrame.new(0, GAP + 0.06, 0.2), 1.24, 3.3, 0.12, cyan, NEON)
	commonAttachments(c, 3.0, 1.0, TOP - 0.3, tips[1], tips[2], orb)
end

-- A wing feather that widens toward its outer end (a fanned wing reads as a
-- wing from every side): narrow at `root`, `width` wide at the end, a flame
-- strip along the end. 2 parts.
local function fanFeather(c: Ctx, root: Vector3, dir: Vector3, side: Vector3, length: number, width: number, color: Color3, tip: Color3)
	local legA = dir.Unit * length
	local legB = (side - dir.Unit * side:Dot(dir.Unit)).Unit * width
	local outer = root + legA
	rightWedge(c, "Feather", outer, -legA, legB, 0.1, color)
	local normal = legA:Cross(legB).Unit
	bar(c, "FeatherTip", outer - legA.Unit * 0.08, outer + legB - legA.Unit * 0.08, 0.16, 0.13, tip, NEON, normal)
end

-- Robux 2: a violet deck with a golden phoenix head, wings and tail feathers.
local function royalPhoenix(c: Ctx)
	local col = c.colors
	local violet, gold = col.Main, col.Trim
	local vGlow, flame = glow(col.Glow), glow(col.Glow2)
	local fire = glow(col.Accent)
	local center = CFrame.new(0, 0, 0.2)
	pill(c, "Deck", center * CFrame.new(0, TOP - 0.15, 0), 2.6, 5.6, 0.22, violet, nil, { Shadow = true })
	pill(c, "GoldSeam", center * CFrame.new(0, TOP - 0.31, 0), 2.76, 5.76, 0.1, gold)
	pill(c, "GlowSeam", center * CFrame.new(0, TOP - 0.395, 0), 2.5, 5.4, 0.07, vGlow, NEON)
	pill(c, "Hull", center * CFrame.new(0, TOP - 0.55, 0), 2.3, 5.1, 0.24, violet:Lerp(BLACK, 0.35), nil, { Shadow = true })
	-- the grip with a gold diamond and a crown gem in it
	block(c, "Grip", CFrame.new(0, TOP - 0.02, 0.4), Vector3.new(1.9, 0.04, 3.4), violet:Lerp(BLACK, 0.55))
	local d = Vector3.new(0, TOP, 0.4)
	local corners = { d + Vector3.new(0, 0, -1.05), d + Vector3.new(0.62, 0, 0), d + Vector3.new(0, 0, 1.05), d + Vector3.new(-0.62, 0, 0) }
	for i = 1, 4 do
		bar(c, "GoldInlay", corners[i], corners[i % 4 + 1], 0.1, 0.03, gold)
	end
	block(c, "GripGem", CFrame.new(d) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.34, 0.06, 0.34), vGlow, NEON)
	-- the phoenix figurehead at the nose: a slender two-piece neck, a small head
	-- with a hooked beak and glowing eyes, three flame crest feathers, a crown gem
	local head = Vector3.new(0, TOP + 1.0, -2.85)
	bar(c, "Neck", Vector3.new(0, TOP - 0.05, -1.85), Vector3.new(0, TOP + 0.5, -2.6), 0.5, 0.42, gold)
	bar(c, "Neck", Vector3.new(0, TOP + 0.4, -2.55), head + Vector3.new(0, -0.1, 0.05), 0.42, 0.36, gold)
	block(c, "Head", CFrame.new(head) * CFrame.Angles(-0.12, 0, 0), Vector3.new(0.5, 0.46, 0.64), gold, nil, { Shadow = true })
	rightWedge(c, "Beak", head + Vector3.new(0, -0.12, -0.3), Vector3.new(0, 0.2, 0), Vector3.new(0, 0, -0.32), 0.2, gold:Lerp(fire, 0.45))
	for _, s in { -1, 1 } do
		block(c, "Eye", CFrame.new(head + Vector3.new(s * 0.255, 0.06, -0.12)), Vector3.new(0.04, 0.1, 0.13), vGlow, NEON)
	end
	for i, x in { -0.14, 0, 0.14 } do
		local a = if i == 2 then 0.7 else 0.95
		local len = if i == 2 then 1.5 else 1.1
		local dir = Vector3.new(x * 0.6, math.cos(a), math.sin(a)).Unit
		local front = Vector3.new(0, math.sin(a), -math.cos(a))
		front = (front - dir * front:Dot(dir)).Unit
		local root = head + Vector3.new(x, 0.18, 0.12)
		local legA, legB = dir * len, front * 0.3
		rightWedge(c, "Crest", root, legA, legB, 0.1, if i == 2 then violet:Lerp(WHITE, 0.2) else gold)
		rightWedge(c, "CrestTip", root + legA * 0.62, legA * 0.38, legB * 0.38, 0.13, if i == 2 then vGlow else flame, NEON)
	end
	block(
		c,
		"CrownGem",
		CFrame.new(head + Vector3.new(0, 0.3, -0.18)) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
		Vector3.new(0.2, 0.2, 0.2),
		vGlow,
		NEON
	)
	-- golden wings: three feathers per side, swept back and raised in a V, flame tips
	local tips: { Vector3 } = {}
	for _, s in { -1, 1 } do
		local shoulder = Vector3.new(s * 1.2, TOP - 0.15, -0.5)
		ball(c, "Shoulder", shoulder, 0.55, gold)
		-- the wing panel: one solid gold triangle the feathers grow from
		local lead = Vector3.new(s * math.cos(0.2) * math.cos(0.62), math.sin(0.62), math.sin(0.2) * math.cos(0.62))
		local panelB = Vector3.new(0, 0, 1) - lead * lead.Z
		rightWedge(c, "WingPanel", shoulder, lead * 1.25, panelB.Unit * 1.1, 0.14, gold:Lerp(WHITE, 0.08))
		for k, spec in { { 0.1, 2.25, 1.0, 0.72 }, { 0.38, 2.0, 0.92, 0.6 }, { 0.66, 1.65, 0.82, 0.48 } } do
			local sweep, length, width, lift = spec[1], spec[2], spec[3], spec[4]
			local dir = Vector3.new(s * math.cos(sweep) * math.cos(lift), math.sin(lift), math.sin(sweep) * math.cos(lift))
			local root = shoulder + Vector3.new(0, -0.03 * k, 0.3 * (k - 1))
			local color = if k == 2 then violet:Lerp(WHITE, 0.15) else gold:Lerp(BLACK, 0.06 * (k - 1))
			fanFeather(c, root, dir, Vector3.new(0, 0, 1), length, width, color, fire)
			if k == 1 then
				table.insert(tips, root + dir * length)
			end
		end
	end
	-- three tail feathers fanning out and up behind the board
	for i, yaw in { -0.5, 0, 0.5 } do
		local dir = Vector3.new(math.sin(yaw), 0.42, math.cos(yaw))
		local root = Vector3.new(0, TOP - 0.25, 2.7)
		local length = if i == 2 then 2.5 else 2.0
		local color = if i == 2 then violet:Lerp(WHITE, 0.12) else gold
		for _, s in { -1, 1 } do
			local side = Vector3.new(s * math.cos(yaw), 0, -s * math.sin(yaw))
			fanFeather(c, root, dir, side, length, 0.34, color, fire)
		end
	end
	-- the violet hover pad on a gold housing, two gold thrusters
	pill(c, "PadHousing", CFrame.new(0, GAP + 0.16, 0.2), 1.6, 3.6, 0.14, gold:Lerp(BLACK, 0.3))
	pill(c, "PadGlow", CFrame.new(0, GAP + 0.045, 0.2), 1.36, 3.3, 0.09, vGlow, NEON)
	for _, s in { -1, 1 } do
		tube(c, "Thruster", CFrame.new(s * 0.62, 0.98, 2.72), 0.6, 0.44, gold, METAL)
		tube(c, "ThrusterGlow", CFrame.new(s * 0.62, 0.98, 3.04), 0.05, 0.3, vGlow, NEON)
		exhaust(c, Vector3.new(s * 0.62, 0.98, 3.08))
	end
	commonAttachments(c, 3.0, 1.0, TOP - 0.3, tips[1], tips[2], head + Vector3.new(0, 0.3, -0.18))
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	TimberDrifter = timberDrifter,
	CartCruiser = cartCruiser,
	EmberglassGlider = emberglassGlider,
	NeonComet = neonComet,
	RoyalPhoenix = royalPhoenix,
}

---------------------------------------------------------------- API

-- The board model for a HoverboardData id (errors on an unknown id).
function HoverboardBuilder.build(boardId: string): Model
	local board = HoverboardData.get(boardId)
	local builder = BUILDERS[boardId]
	assert(board and builder, "unknown hoverboard " .. tostring(boardId))
	local model = Instance.new("Model")
	model.Name = board.Id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Transparency = 1
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	local c: Ctx = { model = model, root = root, colors = board.Colors, exhausts = 0 }
	builder(c)
	model:SetAttribute("BoardId", board.Id)
	model:SetAttribute("Effect", board.Effect)
	model:SetAttribute("DeckHeight", HoverboardBuilder.DeckHeight)
	model:SetAttribute("Exhausts", c.exhausts)
	return model
end

-- The part budget of a board (HoverboardBuilder.MaxParts by its kind).
function HoverboardBuilder.maxParts(boardId: string): number
	local board = HoverboardData.get(boardId)
	return HoverboardBuilder.MaxParts[if board then board.Kind else "Coins"]
end

--[[
	Makes a built board ridable: unanchors every part, makes it massless and
	welds it to Root with a WeldConstraint (Root stays the one part to weld to
	the character). Call before parenting it to the character.
]]
function HoverboardBuilder.rig(model: Model)
	local root = model.PrimaryPart
	assert(root, "hoverboard without Root")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			if d ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
end

return HoverboardBuilder
