--[[
	Builds the hoverboards (HoverboardData) from parts only (no meshes), in
	the chunky Kenney toy style and the game palette. Every board reads by its
	silhouette at phone size:

	  TimberDrifter     a tidy skateboard: three wooden planks side by side with
	  (coins 1)         kicked nose and tail (symmetric about Root), iron straps
	                    with copper bolts over the kick seams, two round amber
	                    hover pads, two copper thruster cans under the tail    35 parts
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
	  RoyalPhoenix      a violet deck on gold and violet glow seams, a bird of
	  (coins 4)         fire at the nose (a slim three-piece neck curving up, a
	                    sleek head with a long pointed beak, glowing eyes, three
	                    flame crest feathers sweeping back, a crown gem), wings
	                    of four layered feather blades per side sweeping back
	                    and up (graduated, gold / violet with flame tips), three
	                    long tail blades, a gold diamond on the grip            68
	  TerraForgeCustom  (owner 2026-10-25: "a custom Terra Forge board like Pet
	  (Robux)           Simulator's" doodle deck) a white skateboard deck with a
	                    black marker outline, painted all over: bright paint
	                    blobs all over (nine colours) with doodles on them (a
	                    golem face with ears, a lightning bolt, a gem, a star,
	                    an orb, a pickaxe, a heart), marker scribbles and white
	                    dots, a hot pink glow seam, two sky-blue hover pads,
	                    two little thrusters                                    ~76
	Budgets (tests/Hoverboard.spec.luau): coin boards <= 70 parts (the Royal
	Phoenix is a coin board since 2026-10-25), Robux <= 80.

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
local IconAssets = require(script.Parent.Parent.Config.IconAssets)
local ItemBuilder = require(script.Parent.ItemBuilder)

local HoverboardBuilder = {}

HoverboardBuilder.DeckHeight = 1.5 -- deck top above Root (the feet)
HoverboardBuilder.HoverGap = 0.6 -- ground to the bottom of the hover pad
HoverboardBuilder.MaxParts = { Coins = 70, Robux = 80 } :: { [string]: number }
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

-- Coins 1: a tidy skateboard of three planks with kicked nose and tail, iron
-- straps with copper bolts over the kick seams, two round amber hover pads and
-- two small copper thruster cans tucked under the tail. Symmetric about Root.
local function timberDrifter(c: Ctx)
	local col = c.colors
	local woods = { col.Main:Lerp(BLACK, 0.12), col.Main:Lerp(WHITE, 0.08), col.Main:Lerp(BLACK, 0.04) }
	local thick = 0.3
	local y = TOP - thick / 2
	local width, gap = 0.82, 0.05
	local half = 1.8 -- the flat part runs z -half..half
	local kick, kickAngle = 1.0, 0.36
	for i, x in { -(width + gap), 0, width + gap } do
		local tone = woods[i]
		block(c, "Plank", CFrame.new(x, y, 0), Vector3.new(width, thick, half * 2), tone, WOOD, { Shadow = true })
		for _, s in { -1, 1 } do
			-- s = -1: the nose (-Z) tips up; s = 1: the tail tips up
			local kickCf = CFrame.new(x, y, s * half) * CFrame.Angles(-s * kickAngle, 0, 0) * CFrame.new(0, 0, s * (kick / 2 - 0.06))
			block(c, "PlankKick", kickCf, Vector3.new(width, thick, kick + 0.12), tone, WOOD, { Shadow = s == -1 })
		end
		-- one darker grain line per plank
		block(
			c,
			"Grain",
			CFrame.new(x + (i - 2) * 0.12 + 0.1, TOP, (i - 2) * 0.25),
			Vector3.new(0.07, 0.03, 2.2),
			tone:Lerp(BLACK, 0.3),
			WOOD
		)
	end
	-- iron straps over the kick seams, three copper bolts each
	for _, z in { -half + 0.12, half - 0.12 } do
		block(c, "Strap", CFrame.new(0, TOP + 0.03, z), Vector3.new(2.66, 0.08, 0.32), col.Accent, METAL)
		for _, x in { -(width + gap), 0, width + gap } do
			ball(c, "Bolt", Vector3.new(x, TOP + 0.08, z), 0.2, col.Trim, METAL)
		end
	end
	-- battens under the kick seams
	for _, z in { -half, half } do
		block(c, "Batten", CFrame.new(0, TOP - thick - 0.1, z), Vector3.new(2.4, 0.2, 0.4), woods[1]:Lerp(BLACK, 0.3), WOOD)
	end
	-- two round iron hover pads with a copper rim and an amber glow lens
	local padTop = TOP - thick
	for _, z in { -0.95, 0.95 } do
		disc(c, "PadHousing", CFrame.new(0, (padTop + GAP + 0.16) / 2, z), 1.4, padTop - GAP - 0.16, col.Accent)
		disc(c, "PadRim", CFrame.new(0, GAP + 0.26, z), 1.56, 0.1, col.Trim, METAL)
		disc(c, "PadGlow", CFrame.new(0, GAP + 0.08, z), 1.05, 0.16, glow(col.Glow), NEON)
	end
	-- two copper thruster cans under the tail, beside the back pad
	for _, s in { -1, 1 } do
		local x, py = s * 0.95, padTop - 0.21
		tube(c, "Thruster", CFrame.new(x, py, 1.7), 1.0, 0.42, col.Trim, METAL)
		tube(c, "Nozzle", CFrame.new(x, py, 2.26), 0.14, 0.48, col.Accent, METAL)
		tube(c, "NozzleGlow", CFrame.new(x, py, 2.35), 0.05, 0.34, glow(col.Glow), NEON)
		exhaust(c, Vector3.new(x, py, 2.4))
	end
	local tipZ = half + math.cos(kickAngle) * kick
	local tipY = TOP + math.sin(kickAngle) * kick
	commonAttachments(
		c,
		tipZ,
		0.95,
		tipY - 0.15,
		Vector3.new(-1.3, TOP - 0.15, 0),
		Vector3.new(1.3, TOP - 0.15, 0),
		Vector3.new(0, tipY, -tipZ)
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

---------------------------------------------------------------- the Royal Phoenix (coins 4)

-- A feather blade from `root` along `dir`: a slim body and a glowing pointed tip
-- (one straight edge, like a real feather); `face` = the blade's flat-side normal. 2 parts.
local function blade(c: Ctx, root: Vector3, dir: Vector3, face: Vector3, length: number, width: number, color: Color3, tip: Color3)
	local d = dir.Unit
	local normal = (face - d * face:Dot(d)).Unit
	local bodyLength = length * 0.7
	local mid = root + d * (bodyLength / 2)
	block(c, "Feather", CFrame.lookAt(mid, mid + d, normal), Vector3.new(width, 0.08, bodyLength), color)
	local across = d:Cross(normal).Unit
	local base = root + d * (bodyLength - 0.02)
	rightWedge(c, "FeatherTip", base - across * (width / 2), across * width, d * (length - bodyLength + 0.02), 0.1, tip, NEON)
end

-- Robux 2: a violet deck with a phoenix of fire: a slim neck curving up from the
-- nose, a sleek head with a long pointed beak, glowing eyes and three flame crest
-- feathers; wings of layered feather blades sweeping back and up; a long tail.
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
	-- the grip with a gold diamond and a gem in it
	block(c, "Grip", CFrame.new(0, TOP - 0.02, 0.4), Vector3.new(1.9, 0.04, 3.4), violet:Lerp(BLACK, 0.55))
	local d = Vector3.new(0, TOP, 0.4)
	local corners = { d + Vector3.new(0, 0, -1.05), d + Vector3.new(0.62, 0, 0), d + Vector3.new(0, 0, 1.05), d + Vector3.new(-0.62, 0, 0) }
	for i = 1, 4 do
		bar(c, "GoldInlay", corners[i], corners[i % 4 + 1], 0.1, 0.03, gold)
	end
	block(c, "GripGem", CFrame.new(d) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.34, 0.06, 0.34), vGlow, NEON)
	-- the neck: three slim pieces curving up from the nose, a little forward
	local head = Vector3.new(0, TOP + 1.16, -2.74)
	local neck = {
		Vector3.new(0, TOP - 0.05, -1.98),
		Vector3.new(0, TOP + 0.36, -2.46),
		Vector3.new(0, TOP + 0.8, -2.66),
		head + Vector3.new(0, -0.1, 0.08),
	}
	for i = 1, 3 do
		bar(
			c,
			"Neck",
			neck[i],
			neck[i + 1] + (neck[i + 1] - neck[i]).Unit * 0.06,
			0.34 - 0.04 * i,
			0.32 - 0.04 * i,
			gold:Lerp(fire, 0.06 * i)
		)
	end
	-- the head looks forward, a little down; the long beak is a spear point (upper and lower half)
	local headCf = CFrame.lookAt(head, head + Vector3.new(0, -0.18, -1))
	block(c, "Head", headCf, Vector3.new(0.3, 0.3, 0.56), gold, nil, { Shadow = true })
	local beakRoot = (headCf * CFrame.new(0, -0.02, -0.27)).Position
	local forward = headCf.LookVector
	local up = headCf.UpVector
	rightWedge(c, "Beak", beakRoot, up * 0.12, forward * 0.72, 0.18, gold:Lerp(WHITE, 0.15))
	rightWedge(c, "Beak", beakRoot, -up * 0.1, forward * 0.6, 0.16, fire)
	for _, s in { -1, 1 } do
		block(c, "Eye", headCf * CFrame.new(s * 0.155, 0.05, -0.12), Vector3.new(0.03, 0.09, 0.14), vGlow, NEON)
	end
	-- the crest: three flame feathers sweeping back from the head
	for i, spec in { { 0.35, 1.0 }, { 0.75, 1.3 }, { 1.15, 1.0 } } do
		local lift, length = spec[1], spec[2]
		local dir = Vector3.new(0, math.sin(lift), math.cos(lift))
		local root = (headCf * CFrame.new(0, 0.1, 0.18)).Position
		blade(c, root, dir, Vector3.new(1, 0, 0), length, 0.2, if i == 2 then flame else gold, if i == 2 then fire else vGlow)
	end
	block(
		c,
		"CrownGem",
		headCf * CFrame.new(0, 0.2, -0.1) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
		Vector3.new(0.16, 0.16, 0.16),
		vGlow,
		NEON
	)
	-- wings: four layered feather blades per side, sweeping back and up, longest on top
	local tips: { Vector3 } = {}
	for _, s in { -1, 1 } do
		local shoulder = Vector3.new(s * 1.18, TOP - 0.12, -0.75)
		ball(c, "Shoulder", shoulder, 0.5, gold)
		local face = Vector3.new(s * 0.75, 0.66, 0)
		for k, spec in { { 0.62, 0.8, 2.5 }, { 0.5, 0.62, 2.2 }, { 0.38, 0.46, 1.9 }, { 0.26, 0.3, 1.6 } } do
			local out, rise, length = spec[1], spec[2], spec[3]
			local dir = Vector3.new(s * out, rise, 1)
			local root = shoulder + Vector3.new(0, -0.05 * (k - 1), 0.2 * (k - 1))
			local color = if k % 2 == 1 then gold:Lerp(BLACK, 0.04 * (k - 1)) else violet:Lerp(WHITE, 0.18)
			local tip = if k % 2 == 1 then fire else vGlow
			blade(c, root, dir, face, length, 0.58 - 0.05 * (k - 1), color, tip)
			if k == 1 then
				table.insert(tips, root + dir.Unit * length)
			end
		end
	end
	-- three long tail feathers trailing back and rising
	for i, yaw in { -0.32, 0, 0.32 } do
		local dir = Vector3.new(math.sin(yaw), 0.38, math.cos(yaw))
		local length = if i == 2 then 2.4 else 1.9
		local root = Vector3.new(math.sin(yaw) * 0.3, TOP - 0.22, 2.55)
		blade(
			c,
			root,
			dir,
			Vector3.new(-math.sin(yaw) * 0.3, 1, -0.38),
			length,
			0.36,
			if i == 2 then violet:Lerp(WHITE, 0.15) else gold,
			fire
		)
	end
	-- the violet hover pad on a gold housing, two gold thrusters
	pill(c, "PadHousing", CFrame.new(0, GAP + 0.16, 0.2), 1.6, 3.6, 0.14, gold:Lerp(BLACK, 0.3))
	pill(c, "PadGlow", CFrame.new(0, GAP + 0.045, 0.2), 1.36, 3.3, 0.09, vGlow, NEON)
	for _, s in { -1, 1 } do
		tube(c, "Thruster", CFrame.new(s * 0.62, 0.98, 2.72), 0.6, 0.44, gold, METAL)
		tube(c, "ThrusterGlow", CFrame.new(s * 0.62, 0.98, 3.04), 0.05, 0.3, vGlow, NEON)
		exhaust(c, Vector3.new(s * 0.62, 0.98, 3.08))
	end
	commonAttachments(c, 3.0, 1.0, TOP - 0.3, tips[1], tips[2], (headCf * CFrame.new(0, 0.2, -0.1)).Position)
end

---------------------------------------------------------------- the Robux board

local DOODLE = {
	Green = rgb(96, 214, 80),
	Yellow = rgb(255, 214, 40),
	Blue = rgb(70, 160, 255),
	Orange = rgb(255, 150, 40),
	Purple = rgb(176, 90, 255),
	Pink = rgb(255, 110, 200),
	Stone = rgb(170, 180, 205),
	Brown = rgb(170, 110, 60),
	Red = rgb(255, 80, 90),
	Teal = rgb(40, 210, 190),
	Lime = rgb(200, 240, 70),
}

-- Terra Forge Custom: a doodle-painted skateboard deck (owner's Pet Simulator reference).
-- Layers on the deck top (thin flat parts, a little apart so nothing flickers):
-- paint blobs, then each doodle's black marker outline, then its fill, then details.
-- The camera looks along -X across the deck (the board lies across under the rider),
-- so doodles have their "up" toward -X.
local paintDoodles: (Ctx, number, number, number, number) -> ()
local underside: (Ctx) -> ()

local function terraForgeCustom(c: Ctx)
	local col = c.colors
	local ink = col.Trim
	local pink = glow(col.Glow)
	-- the paint layers stack up to the deck top (the feet stand on DeckHeight), each blob a
	-- little higher than the one before and every doodle layer 0.008 above the last, so
	-- overlapping paint never flickers
	local BLOB, LINE, FILL, DETAIL = TOP - 0.064, TOP - 0.022, TOP - 0.014, TOP - 0.006
	-- the deck: white, with a black marker edge showing all round
	pill(c, "Deck", CFrame.new(0, TOP - 0.19, 0), 2.6, 6.4, 0.24, col.Main, nil, { Shadow = true })
	pill(c, "Outline", CFrame.new(0, TOP - 0.235, 0), 2.84, 6.64, 0.2, ink)
	pill(c, "GlowSeam", CFrame.new(0, TOP - 0.37, 0), 2.7, 6.5, 0.08, pink, NEON)
	-- the painted deck art (tools/preview/make_board_doodle.py: wobbly marker blobs and doodles,
	-- uploaded by the owner as one Decal: IconAssets.Textures.board_custom_deck); until its id
	-- is in, the doodles below are built from flat parts
	local art = IconAssets.Textures.board_custom_deck
	if art and (art.Id > 0 or IconAssets.Previewing) then
		-- a see-through board whose Front face lies on the deck (image right = the nose,
		-- image up = the far side seen from behind the rider)
		local canvas = block(
			c,
			"DeckArt",
			CFrame.new(0, TOP - 0.091, 0) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(math.pi / 2, 0, 0),
			Vector3.new(6.4, 2.6, 0.05),
			col.Main,
			nil,
			{ Transparency = 1 }
		)
		local decal = Instance.new("Decal")
		decal.Name = "DeckArt"
		decal.Face = Enum.NormalId.Front
		decal.Texture = if art.Id > 0 then "rbxassetid://" .. tostring(art.Id) else ""
		decal:SetAttribute("PreviewImage", "/scenes/textures/" .. art.File)
		decal.Parent = canvas
	else
		paintDoodles(c, BLOB, LINE, FILL, DETAIL)
	end
	underside(c)
end

-- The deck's doodles from flat parts (until the painted art is uploaded).
function paintDoodles(c: Ctx, BLOB: number, LINE: number, FILL: number, DETAIL: number)
	local ink = c.colors.Trim
	-- paint blobs covering the whole deck (inside its rounded outline)
	local blobs: { { x: number, z: number, d: number, color: Color3 } } = {
		{ x = -0.3, z = -2.55, d = 1.1, color = DOODLE.Green },
		{ x = 0.5, z = -2.0, d = 1.3, color = DOODLE.Red },
		{ x = -0.48, z = -1.35, d = 1.55, color = DOODLE.Yellow },
		{ x = 0.5, z = -0.6, d = 1.55, color = DOODLE.Blue },
		{ x = -0.5, z = 0.15, d = 1.55, color = DOODLE.Orange },
		{ x = 0.5, z = 0.95, d = 1.55, color = DOODLE.Purple },
		{ x = -0.5, z = 1.65, d = 1.5, color = DOODLE.Pink },
		{ x = 0.48, z = 2.15, d = 1.25, color = DOODLE.Teal },
		{ x = -0.25, z = 2.6, d = 1.0, color = DOODLE.Lime },
	}
	for i, b in blobs do
		disc(c, "PaintBlob", CFrame.new(b.x, BLOB + (i - 1) * 0.004, b.z), b.d, 0.003, b.color)
	end
	-- a golem face on the yellow blob (eyes toward -X: upright from behind the rider), with ears
	block(c, "DoodleLine", CFrame.new(-0.45, LINE, -1.35), Vector3.new(0.98, 0.004, 1.04), ink)
	block(c, "GolemFace", CFrame.new(-0.45, FILL, -1.35), Vector3.new(0.84, 0.004, 0.9), DOODLE.Stone)
	for _, z in { -1.88, -0.82 } do
		block(c, "GolemEar", CFrame.new(-0.62, LINE, z), Vector3.new(0.3, 0.004, 0.22), ink)
	end
	for _, z in { -1.55, -1.15 } do
		block(c, "GolemEye", CFrame.new(-0.62, DETAIL, z), Vector3.new(0.2, 0.004, 0.16), ink)
		disc(c, "GolemEyeShine", CFrame.new(-0.66, DETAIL + 0.008, z - 0.03), 0.07, 0.004, WHITE)
	end
	block(c, "GolemMouth", CFrame.new(-0.2, DETAIL, -1.35), Vector3.new(0.09, 0.004, 0.42), ink)
	-- a lightning bolt on the red blob
	local bolt = { Vector3.new(0.2, 0, -2.4), Vector3.new(0.55, 0, -2.12), Vector3.new(0.42, 0, -1.95), Vector3.new(0.82, 0, -1.62) }
	for i = 1, 3 do
		local a, b = bolt[i], bolt[i + 1]
		bar(c, "DoodleLine", Vector3.new(a.X, LINE, a.Z), Vector3.new(b.X, LINE, b.Z), 0.26, 0.004, ink)
		bar(c, "Bolt", Vector3.new(a.X, FILL, a.Z), Vector3.new(b.X, FILL, b.Z), 0.14, 0.004, DOODLE.Yellow)
	end
	-- a gem on the blue blob: a diamond with a facet line and a white shine
	local gem = CFrame.new(0.5, 0, -0.6) * CFrame.Angles(0, math.pi / 4, 0)
	block(c, "DoodleLine", CFrame.new(0, LINE, 0) * gem, Vector3.new(0.82, 0.004, 0.82), ink)
	block(c, "Gem", CFrame.new(0, FILL, 0) * gem, Vector3.new(0.66, 0.004, 0.66), rgb(150, 230, 255))
	bar(c, "GemFacet", Vector3.new(0.5, DETAIL, -1.05), Vector3.new(0.5, DETAIL, -0.15), 0.05, 0.004, ink)
	block(c, "GemShine", CFrame.new(0.36, DETAIL, -0.62), Vector3.new(0.12, 0.004, 0.24), WHITE)
	-- a star on the orange blob: two crossed bars
	for _, turn in { math.pi / 4, -math.pi / 4 } do
		local star = CFrame.new(-0.5, 0, 0.15) * CFrame.Angles(0, turn, 0)
		block(c, "DoodleLine", CFrame.new(0, LINE, 0) * star, Vector3.new(1.0, 0.004, 0.3), ink)
		block(c, "Star", CFrame.new(0, FILL, 0) * star, Vector3.new(0.86, 0.004, 0.17), DOODLE.Yellow)
	end
	-- an orb on the purple blob
	disc(c, "DoodleLine", CFrame.new(0.5, LINE, 0.95), 0.96, 0.004, ink)
	disc(c, "Orb", CFrame.new(0.5, FILL, 0.95), 0.8, 0.004, rgb(220, 170, 255))
	disc(c, "OrbShine", CFrame.new(0.38, DETAIL, 0.85), 0.28, 0.004, WHITE)
	-- a pickaxe on the pink blob
	bar(c, "DoodleLine", Vector3.new(-0.75, LINE, 2.05), Vector3.new(-0.25, LINE, 1.3), 0.24, 0.004, ink)
	bar(c, "PickHandle", Vector3.new(-0.73, FILL, 2.02), Vector3.new(-0.27, FILL, 1.33), 0.11, 0.004, DOODLE.Brown)
	bar(c, "DoodleLine", Vector3.new(-0.55, LINE, 1.12), Vector3.new(0.02, LINE, 1.5), 0.26, 0.004, ink)
	bar(c, "PickHead", Vector3.new(-0.53, FILL, 1.14), Vector3.new(0.0, FILL, 1.48), 0.13, 0.004, DOODLE.Stone)
	-- a heart on the teal blob: two round lobes and a point
	disc(c, "DoodleLine", CFrame.new(0.38, LINE, 1.98), 0.52, 0.004, ink)
	disc(c, "DoodleLine", CFrame.new(0.38, LINE, 2.32), 0.52, 0.004, ink)
	block(c, "DoodleLine", CFrame.new(0.6, LINE, 2.15) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.52, 0.004, 0.52), ink)
	for _, z in { 1.98, 2.32 } do
		disc(c, "Heart", CFrame.new(0.38, FILL, z), 0.38, 0.004, DOODLE.Red)
	end
	block(c, "Heart", CFrame.new(0.56, FILL, 2.15) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.4, 0.004, 0.4), DOODLE.Red)
	-- marker scribbles and white dots between the doodles
	for _, sq in { { -0.95, -2.2, -0.75, -1.95 }, { 0.95, -1.2, 0.75, -0.95 }, { -0.95, 0.75, -0.7, 1.0 }, { 0.95, 1.6, 0.75, 1.85 } } do
		bar(c, "Scribble", Vector3.new(sq[1], DETAIL, sq[2]), Vector3.new(sq[3], DETAIL, sq[4]), 0.06, 0.004, ink)
	end
	for _, d in { { 0.7, -2.55 }, { -0.85, -0.55 }, { 0.9, 0.15 }, { 0.1, 0.55 }, { -0.1, 2.75 }, { 0.05, -1.75 } } do
		disc(c, "Dot", CFrame.new(d[1], DETAIL, d[2]), 0.16, 0.004, WHITE)
	end
end

-- Under the Terra Forge Custom: two sky-blue hover pads, two little thrusters at the tail.
function underside(c: Ctx)
	local col = c.colors
	local ink = col.Trim
	local pink, sky = glow(col.Glow), glow(col.Glow2)
	for _, z in { -1.6, 1.6 } do
		disc(c, "PadHousing", CFrame.new(0, GAP + 0.2, z), 1.5, 0.16, ink:Lerp(WHITE, 0.15))
		disc(c, "PadGlow", CFrame.new(0, GAP + 0.06, z), 1.2, 0.12, sky, NEON)
	end
	for _, s in { -1, 1 } do
		tube(c, "Thruster", CFrame.new(s * 0.6, TOP - 0.45, 2.85), 0.5, 0.42, col.Main)
		tube(c, "ThrusterGlow", CFrame.new(s * 0.6, TOP - 0.45, 3.12), 0.05, 0.3, if s < 0 then pink else sky, NEON)
		exhaust(c, Vector3.new(s * 0.6, TOP - 0.45, 3.16))
	end
	commonAttachments(
		c,
		3.25,
		0.9,
		TOP - 0.3,
		Vector3.new(-1.3, TOP + 0.05, 0),
		Vector3.new(1.3, TOP + 0.05, 0),
		Vector3.new(0, TOP + 0.1, -3.1)
	)
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	TimberDrifter = timberDrifter,
	CartCruiser = cartCruiser,
	EmberglassGlider = emberglassGlider,
	RoyalPhoenix = royalPhoenix,
	TerraForgeCustom = terraForgeCustom,
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
