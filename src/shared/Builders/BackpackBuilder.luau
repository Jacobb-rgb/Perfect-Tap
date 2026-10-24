--[[
	Builds the ten backpacks (BackpackData) from parts only (no meshes), in the
	chunky low-poly look of the owner's reference (a royal blue rune pack with
	gold trim, a glowing crystal on the flap, a bedroll on top, a front pocket
	with two strapped buckles and side pockets). Owner on the first proposal
	(2026-10-24): the starter sack out, far more detail on every pack. Worst
	to best:

	  RookiePack       a cute school bag: an arched canvas body, an orange
	                   panel, a zip pocket, a gem patch, a star charm, a
	                   water bottle and a mini wooden pickaxe
	  TrailPack        khaki, a green bedroll, a tin mug, a leaf charm,
	                   a mountain patch
	  LeatherRucksack  leather and brass, a brass shield, rivets, a canteen
	  MinersPack       a lantern, a pickaxe across the top, a rope coil,
	                   ore spilling out of the pocket
	  IronboundPack    steel plate and bands, a chained blue gem, blue
	                   crystals in the side pockets
	  ExplorersPack    brass, a glowing compass, a map tube, a spyglass,
	                   a plume
	  AmethystPack     silver filigree, amethyst crystals on the flap, out
	                   of the top and the side pockets, violet runes
	  RuneboundPack    the reference: gold trim, a rune ring with a star
	                   crystal and rays, star dots, rune columns
	  EmberforgePack   obsidian plates, lava seams, a fire crystal, gold
	                   horns, a molten pocket window, two chimneys
	  StarforgePack    pearl and gold, a galaxy flap, a star crystal,
	                   orbiting star shards, two feathered wings
	Budget: BackpackBuilder.MaxParts (tests). Effects (particles, the light)
	are BackpackFx's: the builder only leaves invisible "FxBox" parts where
	they go.

	Contract: a Model named after the pack id, PrimaryPart "Root" (an invisible
	part) at the wearer's BACK: the middle of UpperTorso's back face. +Z points
	away from the back (the side the camera sees from behind the player), +Y
	up, X across. The bag hangs from TOP (UpperTorso's top edge) down past the
	waist; padded straps go over the shoulders to the chest (z = -1, a 1 stud
	deep torso). Attachments on Root: "Gem" (the flap's emblem) and "Top"
	(above the bedroll). FxBox parts: invisible, attribute "FxBox" = their
	name (Gem, Lantern, Ore, Crystals, TopCrystals, Runes, ChimneyLeft /
	ChimneyRight, Aura, WingLeft / WingRight), the volume an effect fills.
	Model attributes: BackpackId, BottomY / TopY (the lowest / highest visible
	point above Root, for stands and shop pedestals), Parts.
	Everything is anchored with CanCollide / CanTouch / CanQuery off and no
	shadows except the body; BackpackBuilder.rig(model) unanchors it and welds
	every part to Root (massless) for wearing.

	Pure and deterministic: only Instance creation, so Lune tests and previews
	can build it.
]]

local BackpackData = require(script.Parent.Parent.Config.BackpackData)
local ItemBuilder = require(script.Parent.ItemBuilder)

local BackpackBuilder = {}

BackpackBuilder.Top = 0.8 -- the bag's top above Root (UpperTorso's top edge)
BackpackBuilder.Gap = 0.04 -- Root (the back) to the bag's inner face
BackpackBuilder.MaxParts = 150

local TOP = BackpackBuilder.Top
local GAP = BackpackBuilder.Gap

local rgb = Color3.fromRGB
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local FABRIC = Enum.Material.Fabric
local WOOD = Enum.Material.Wood

local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- Roblox cylinders run along X
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local DIAMOND = CFrame.Angles(0, 0, math.pi / 4) -- a square turned into a diamond (facing Z)

type Kind = "Block" | "Wedge" | "Cylinder" | "Ball"

-- The standard anatomy's frame.
type Frame = {
	w: number,
	h: number,
	d: number,
	top: number,
	bottom: number,
	midY: number,
	zc: number, -- the body's middle (Z)
	zf: number, -- the body's outer face (Z)
	ff: number, -- the flap's outer face (Z)
	pf: number, -- the front pocket's outer face (Z)
	flapH: number,
	flapBottom: number,
	pocketW: number,
	pocketBottom: number,
	pocketTop: number,
	sideTop: number,
	rollD: number,
	rollY: number,
	rollZ: number,
	emblem: Vector3, -- the flap tongue's front middle
}

type Ctx = {
	model: Model,
	root: BasePart,
	colors: BackpackData.Colors,
	f: Frame,
	display: boolean, -- on a stand (shop, previews): no shoulder straps
	gemAt: Vector3?, -- where the emblem and the top are when not the frame's (the Rookie Pack)
	topAt: Vector3?,
}

-- What the standard anatomy builds (per pack, see STYLES).
type Style = {
	Material: Enum.Material, -- the bag body
	FlapStraps: number, -- 1 = one middle strap, 2 = two
	PocketStraps: boolean, -- two straps with buckles on the front pocket (else a stud)
	PocketWidth: number, -- of the body width
	SidePockets: boolean,
	Roll: boolean, -- the bedroll on top
	Inset: boolean, -- a contrasting panel inside the flap (Panel colour)
	Trim: boolean, -- metal edge posts and strips (Trim colour)
	Corners: boolean, -- metal corner caps
	Prongs: boolean, -- buckles with a dark middle and a prong
}

local function glow(color: Color3): Color3
	return ItemBuilder.glowColor(color)
end

local function part(c: Ctx, name: string, kind: Kind, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
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
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = c.model
	return p
end

local function block(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	return part(c, name, "Block", cf, size, color, material)
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- A cylinder along X (bedroll, rounded edges) centered on `position`.
local function rod(
	c: Ctx,
	name: string,
	position: Vector3,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(c, name, "Cylinder", CFrame.new(position), Vector3.new(length, diameter, diameter), color, material)
end

-- A standing cylinder (axis Y).
local function post(
	c: Ctx,
	name: string,
	position: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(c, name, "Cylinder", CFrame.new(position) * ALONG_Y, Vector3.new(height, diameter, diameter), color, material)
end

-- A disc facing +Z (emblems, patches, compasses) centered on `position`.
local function badge(
	c: Ctx,
	name: string,
	position: Vector3,
	diameter: number,
	thick: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(c, name, "Cylinder", CFrame.new(position) * ALONG_Z, Vector3.new(thick, diameter, diameter), color, material)
end

local function ball(c: Ctx, name: string, position: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	return part(c, name, "Ball", CFrame.new(position), Vector3.new(diameter, diameter, diameter), color, material)
end

-- A flat diamond facing +Z (gems, settings).
local function diamond(
	c: Ctx,
	name: string,
	position: Vector3,
	size: number,
	thick: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return block(c, name, CFrame.new(position) * DIAMOND, Vector3.new(size, size, thick), color, material)
end

-- A strip from `a` to `b` (w wide, t thick, its flat side facing +Z where it can).
local function bar(c: Ctx, name: string, a: Vector3, b: Vector3, w: number, t: number, color: Color3, material: Enum.Material?): BasePart
	local mid = (a + b) / 2
	local along = (b - a).Unit
	local side = along:Cross(Vector3.zAxis)
	if side.Magnitude < 0.01 then
		side = Vector3.xAxis
	end
	local cf = CFrame.fromMatrix(mid, side.Unit, along)
	return block(c, name, cf, Vector3.new(w, (b - a).Magnitude, t), color, material)
end

-- A buckle facing +Z: a metal frame; with `prong`, a dark middle and a prong across it.
local function buckle(c: Ctx, position: Vector3, w: number, h: number, prong: boolean)
	block(c, "Buckle", CFrame.new(position), Vector3.new(w, h, 0.05), c.colors.Buckle, METAL)
	if prong then
		block(c, "BuckleHole", CFrame.new(position + Vector3.new(0, 0, 0.012)), Vector3.new(w * 0.52, h * 0.46, 0.05), c.colors.Leather)
		block(c, "BuckleProng", CFrame.new(position + Vector3.new(0, 0, 0.03)), Vector3.new(0.035, h * 0.62, 0.03), c.colors.Buckle, METAL)
	end
end

-- A row of stitches (short light dashes) across X at height y on the face z.
local function stitches(c: Ctx, y: number, z: number, width: number, count: number)
	local step = width / count
	for i = 1, count do
		block(c, "Stitch", at(-width / 2 + (i - 0.5) * step, y, z), Vector3.new(step * 0.55, 0.035, 0.02), c.colors.Stitch)
	end
end

--[[
	A faceted crystal growing from `base` along its +Y: a diamond-section
	body (glowing unless `bodyMaterial` says otherwise: a shaded body shows
	its facets) and a two-tone glowing pointed tip (two wedges). 3 parts.
]]
local function crystal(c: Ctx, base: CFrame, height: number, width: number, body: Color3, tip: Color3, bodyMaterial: Enum.Material?)
	local bodyH = height * 0.7
	local tipH = height - bodyH
	local turned = base * CFrame.Angles(0, math.pi / 4, 0)
	block(c, "Crystal", turned * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), body, bodyMaterial or NEON)
	local tipAt = turned * CFrame.new(0, bodyH + tipH / 2, 0)
	part(c, "CrystalTip", "Wedge", tipAt * CFrame.new(0, 0, -width / 4), Vector3.new(width, tipH, width / 2), tip, NEON)
	part(
		c,
		"CrystalTip",
		"Wedge",
		tipAt * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(width, tipH, width / 2),
		body,
		NEON
	)
end

--[[
	A little rune glyph (one Neon part) facing +Z at `position`, or facing
	±X (a side pocket's outer face) when `sideX` is -1 / 1. `kind` 1..4:
	a bar, a tall bar, a small diamond, a slanted stroke.
]]
local function rune(c: Ctx, position: Vector3, kind: number, scale: number, color: Color3, sideX: number?)
	local thin = 0.03
	local size: Vector3
	local turn = CFrame.identity
	if kind == 1 then
		size = Vector3.new(0.13, 0.045, thin)
	elseif kind == 2 then
		size = Vector3.new(0.045, 0.15, thin)
	elseif kind == 3 then
		size = Vector3.new(0.08, 0.08, thin)
		turn = DIAMOND
	else
		size = Vector3.new(0.045, 0.14, thin)
		turn = CFrame.Angles(0, 0, 0.6)
	end
	size = Vector3.new(size.X * scale, size.Y * scale, size.Z)
	local face = if sideX then CFrame.Angles(0, sideX * math.pi / 2, 0) else CFrame.identity
	block(c, "Rune", CFrame.new(position) * face * turn, size, color, NEON)
end

-- Glyphs in a column (top to bottom) on a face: +Z when sideX is nil.
local function runeColumn(c: Ctx, from: Vector3, step: number, kinds: { number }, scale: number, color: Color3, sideX: number?)
	for i, kind in kinds do
		rune(c, from - Vector3.new(0, (i - 1) * step, 0), kind, scale, color, sideX)
	end
end

-- A four-point star (two crossed bars) facing +Z; Neon unless `material` says otherwise.
local function twinkle(c: Ctx, position: Vector3, size: number, color: Color3, material: Enum.Material?)
	block(c, "Twinkle", CFrame.new(position), Vector3.new(size, size * 0.18, 0.03), color, material or NEON)
	block(c, "Twinkle", CFrame.new(position), Vector3.new(size * 0.18, size, 0.03), color, material or NEON)
end

local function attach(c: Ctx, name: string, position: Vector3)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = CFrame.new(position)
	a.Parent = c.root
end

-- An invisible box where an effect goes (BackpackFx fills it).
local function fxBox(c: Ctx, name: string, cf: CFrame, size: Vector3)
	local p = block(c, "FxBox", cf, size, WHITE)
	p.Transparency = 1
	p:SetAttribute("FxBox", name)
end

-- Padded straps over the shoulders and a little way down the chest (worn packs only).
local function shoulderStraps(c: Ctx)
	if c.display then
		return
	end
	for _, s in { -1, 1 } do
		local x = s * 0.52
		block(c, "ShoulderStrap", at(x, TOP + 0.05, -0.47), Vector3.new(0.34, 0.1, 1.06), c.colors.Leather)
		block(c, "ShoulderStrap", at(x, TOP - 0.25, -1.04), Vector3.new(0.32, 0.6, 0.08), c.colors.Leather)
	end
end

-- A soft rounded pouch: a part drawn as the ellipsoid that fills `size`
-- (a Sphere SpecialMesh: built in, no upload).
local function puff(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = block(c, name, cf, size, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

---------------------------------------------------------------- the standard anatomy

local function makeFrame(size: Vector3, style: Style): Frame
	local w, h, d = size.X, size.Y, size.Z
	local top = TOP
	local bottom = top - h
	local zc = GAP + d / 2
	local zf = GAP + d
	local flapH = h * 0.4
	local flapBottom = top - flapH
	local pocketBottom = bottom + 0.2
	local rollD = math.min(0.66, d * 0.64)
	return {
		w = w,
		h = h,
		d = d,
		top = top,
		bottom = bottom,
		midY = (top + bottom) / 2,
		zc = zc,
		zf = zf,
		ff = zf + 0.17,
		pf = zf + 0.34,
		flapH = flapH,
		flapBottom = flapBottom,
		pocketW = w * style.PocketWidth,
		pocketBottom = pocketBottom,
		pocketTop = pocketBottom + h * 0.3,
		sideTop = bottom + 0.2 + h * 0.42,
		rollD = rollD,
		rollY = top + 0.14 + rollD / 2,
		rollZ = zc + 0.02,
		emblem = Vector3.new(0, flapBottom, zf + 0.17),
	}
end

local function standard(c: Ctx, style: Style)
	local f = c.f
	local col = c.colors
	local w, h, d = f.w, f.h, f.d
	local front = col.Body:Lerp(WHITE, 0.08)
	local r = 0.14

	-- the bag: a back block, a lighter bulging front, round front edges (metal on trimmed packs)
	local body = block(c, "Body", at(0, f.midY, f.zc - r / 2), Vector3.new(w, h, d - r), col.Body, style.Material)
	body.CastShadow = true
	block(c, "BodyFront", at(0, f.midY, f.zf - r / 2 + 0.02), Vector3.new(w - 2 * r, h - 0.04, r + 0.04), front, style.Material)
	for _, s in { -1, 1 } do
		if style.Trim then
			post(c, "Trim", Vector3.new(s * (w / 2 - r), f.midY - 0.04, f.zf - r), h - 0.16, 2 * r + 0.05, col.Trim, METAL)
		else
			post(c, "Body", Vector3.new(s * (w / 2 - r), f.midY, f.zf - r), h, 2 * r, col.Body, style.Material)
		end
	end
	-- the leather bottom with a round lip
	block(c, "Base", at(0, f.bottom + 0.09, f.zc), Vector3.new(w + 0.08, 0.22, d + 0.08), col.Leather)
	rod(c, "BaseLip", Vector3.new(0, f.bottom + 0.1, f.zf + 0.03), w + 0.04, 0.24, col.Leather)

	-- the flap folded over the top: a round fold, the front, a stitched edge, a tongue
	block(c, "FlapTop", at(0, f.top + 0.07, (GAP + f.zf) / 2), Vector3.new(w + 0.08, 0.14, d), col.Flap)
	rod(c, "FlapFold", Vector3.new(0, f.top, f.zf + 0.03), w + 0.08, 0.28, col.Flap)
	block(c, "Flap", at(0, f.top - f.flapH / 2, f.zf + 0.1), Vector3.new(w + 0.08, f.flapH, 0.14), col.Flap)
	if style.Inset then
		block(c, "FlapInset", at(0, f.top - f.flapH / 2 + 0.03, f.ff + 0.005), Vector3.new(w - 0.34, f.flapH - 0.3, 0.03), col.Panel)
	end
	badge(c, "FlapTongue", Vector3.new(0, f.flapBottom, f.zf + 0.1), math.min(0.66, w * 0.32), 0.14, col.Flap)
	stitches(c, f.flapBottom + 0.08, f.ff + 0.01, w - 0.16, 9)

	-- straps down the flap and on to the front pocket, a buckle on each
	local strapXs: { number } = if style.FlapStraps >= 2 then { -w * 0.27, w * 0.27 } else { 0 }
	for _, x in strapXs do
		bar(c, "Strap", Vector3.new(x, f.top - 0.04, f.ff + 0.02), Vector3.new(x, f.flapBottom, f.ff + 0.02), 0.15, 0.03, col.Leather)
		bar(c, "Strap", Vector3.new(x, f.flapBottom + 0.02, f.ff + 0.01), Vector3.new(x, f.pocketTop, f.zf + 0.3), 0.15, 0.03, col.Leather)
		buckle(c, Vector3.new(x, f.flapBottom + 0.17, f.ff + 0.045), 0.25, 0.21, style.Prongs)
	end

	-- the front pocket: a round bottom, a flap with a round edge and stitches
	local pw = f.pocketW
	local ph = f.pocketTop - f.pocketBottom
	local pocketZ = f.zf + 0.19
	local pocketMidY = (f.pocketBottom + 0.15 + f.pocketTop) / 2
	block(c, "Pocket", at(0, pocketMidY, pocketZ), Vector3.new(pw - 0.3, ph - 0.15, 0.3), front, style.Material)
	for _, s in { -1, 1 } do
		post(c, "Pocket", Vector3.new(s * (pw / 2 - 0.15), pocketMidY, pocketZ), ph - 0.15, 0.3, front, style.Material)
	end
	rod(c, "PocketBottom", Vector3.new(0, f.pocketBottom + 0.15, pocketZ), pw - 0.3, 0.3, front, style.Material)
	block(c, "PocketFlap", at(0, f.pocketTop - 0.07, f.zf + 0.2), Vector3.new(pw + 0.06, 0.2, 0.36), col.Flap)
	rod(c, "PocketFlapEdge", Vector3.new(0, f.pocketTop - 0.17, f.zf + 0.3), pw + 0.06, 0.16, col.Flap)
	stitches(c, f.pocketTop - 0.1, f.zf + 0.385, pw - 0.12, 7)
	if style.PocketStraps then
		for _, x in { -pw * 0.3, pw * 0.3 } do
			local y0, y1 = f.pocketBottom + 0.06, f.pocketTop - 0.2
			block(c, "PocketStrap", at(x, (y0 + y1) / 2, f.pf + 0.015), Vector3.new(0.13, y1 - y0, 0.03), col.Leather)
			buckle(c, Vector3.new(x, f.pocketBottom + ph * 0.4, f.pf + 0.035), 0.21, 0.18, style.Prongs)
		end
	else
		ball(c, "PocketStud", Vector3.new(0, f.pocketTop - 0.16, f.zf + 0.39), 0.11, col.Buckle, METAL)
	end

	-- side pockets with a studded flap
	if style.SidePockets then
		local sh = f.sideTop - (f.bottom + 0.2)
		for _, s in { -1, 1 } do
			puff(
				c,
				"SidePocket",
				at(s * (w / 2 + 0.06), f.bottom + 0.2 + sh / 2, f.zc + 0.03),
				Vector3.new(0.4, sh + 0.06, d * 0.78),
				front,
				style.Material
			)
			block(c, "SideFlap", at(s * (w / 2 + 0.13), f.sideTop - 0.05, f.zc + 0.03), Vector3.new(0.26, 0.15, d * 0.74), col.Flap)
			ball(c, "SideStud", Vector3.new(s * (w / 2 + 0.26), f.sideTop - 0.08, f.zc + 0.03), 0.08, col.Buckle, METAL)
		end
	end

	-- the bedroll: spiral ends, two straps with buckles
	if style.Roll then
		local len = w * 0.96
		local rollAt = Vector3.new(0, f.rollY, f.rollZ)
		rod(c, "Bedroll", rollAt, len, f.rollD, col.Roll, FABRIC)
		for _, s in { -1, 1 } do
			local endAt = rollAt + Vector3.new(s * len / 2, 0, 0)
			rod(c, "BedrollEnd", endAt, 0.04, f.rollD * 0.7, col.Roll:Lerp(BLACK, 0.28), FABRIC)
			rod(
				c,
				"BedrollCurl",
				endAt + Vector3.new(s * 0.012, f.rollD * 0.07, 0.02),
				0.04,
				f.rollD * 0.34,
				col.Roll:Lerp(WHITE, 0.15),
				FABRIC
			)
			local sx = s * w * 0.27
			rod(c, "BedrollStrap", Vector3.new(sx, f.rollY, f.rollZ), 0.13, f.rollD + 0.05, col.Leather)
			block(c, "BedrollBuckle", at(sx, f.rollY, f.rollZ + f.rollD / 2 + 0.03), Vector3.new(0.17, 0.15, 0.04), col.Buckle, METAL)
		end
	end

	shoulderStraps(c)

	-- trim: the flap's edges (an engraved line along the bottom), the pocket flap's lip
	if style.Trim then
		local z = f.ff + 0.01
		block(c, "Trim", at(0, f.flapBottom + 0.035, z), Vector3.new(w + 0.12, 0.08, 0.05), col.Trim, METAL)
		block(c, "TrimLine", at(0, f.flapBottom + 0.035, z + 0.026), Vector3.new(w + 0.04, 0.02, 0.01), col.Trim:Lerp(BLACK, 0.45))
		for _, s in { -1, 1 } do
			block(c, "Trim", at(s * (w / 2 + 0.03), f.top - f.flapH / 2, z), Vector3.new(0.07, f.flapH, 0.05), col.Trim, METAL)
		end
		block(c, "Trim", at(0, f.pocketTop - 0.17, f.zf + 0.39), Vector3.new(pw + 0.08, 0.06, 0.04), col.Trim, METAL)
	end

	-- where the pack's light sits (BackpackFx): out in front of the flap, so it lights the whole pack
	fxBox(c, "Light", at(0, f.top - f.flapH * 0.5, f.ff + 0.9), Vector3.new(0.2, 0.2, 0.2))

	-- metal corner caps
	if style.Corners then
		for _, s in { -1, 1 } do
			block(c, "Corner", at(s * (w / 2 + 0.01), f.bottom + 0.14, f.zf), Vector3.new(0.24, 0.24, 0.24), col.Buckle, METAL)
			block(c, "Corner", at(s * (w / 2 + 0.04), f.flapBottom + 0.07, f.ff + 0.01), Vector3.new(0.18, 0.18, 0.07), col.Buckle, METAL)
		end
	end
end

local function style(overrides: { [string]: any }): Style
	local s: Style = {
		Material = Enum.Material.SmoothPlastic,
		FlapStraps = 2,
		PocketStraps = true,
		PocketWidth = 0.78,
		SidePockets = true,
		Roll = true,
		Inset = true,
		Trim = false,
		Corners = false,
		Prongs = true,
	}
	local open: any = s
	for key, value in overrides do
		open[key] = value
	end
	return s
end

local STYLES: { [string]: Style } = {
	RookiePack = style({
		Material = FABRIC,
		FlapStraps = 1,
		PocketStraps = false,
		PocketWidth = 0.62,
		SidePockets = false,
		Roll = false,
		Inset = false,
		Prongs = false,
	}),
	TrailPack = style({ Material = FABRIC, Inset = false, Prongs = false }),
	LeatherRucksack = style({}),
	MinersPack = style({ Material = FABRIC }),
	IronboundPack = style({ Trim = true, Corners = true }),
	ExplorersPack = style({ Material = FABRIC, Trim = true }),
	AmethystPack = style({ Trim = true }),
	RuneboundPack = style({ Trim = true }),
	EmberforgePack = style({ Trim = true, Corners = true }),
	StarforgePack = style({ Trim = true }),
}

---------------------------------------------------------------- shared props

-- A small pickaxe: a handle from `low` to `high`, an iron head across its top. 5 parts.
local function pickaxe(c: Ctx, low: Vector3, high: Vector3, headLength: number, wood: Color3, iron: Color3)
	bar(c, "PickHandle", low, high, 0.1, 0.1, wood, WOOD)
	local dir = (high - low).Unit
	local across = Vector3.new(dir.Y, -dir.X, 0).Unit
	local head = CFrame.fromMatrix(high, across, dir)
	block(c, "PickHead", head, Vector3.new(headLength, 0.13, 0.11), iron, METAL)
	block(c, "PickCollar", head, Vector3.new(0.15, 0.2, 0.14), iron:Lerp(BLACK, 0.3), METAL)
	for _, s in { -1, 1 } do
		part(
			c,
			"PickPoint",
			"Wedge",
			head
				* CFrame.new(s * (headLength / 2 + 0.07), -0.02, 0)
				* CFrame.Angles(0, 0, s * math.pi / 2)
				* CFrame.Angles(0, math.pi / 2, 0),
			Vector3.new(0.11, 0.1, 0.14),
			iron,
			METAL
		)
	end
end

-- A metal crest disc behind the emblem (most packs set their gem in one).
local function setting(c: Ctx, diameter: number)
	badge(c, "Setting", c.f.emblem + Vector3.new(0, 0, 0.02), diameter, 0.06, c.colors.Trim, METAL)
end

---------------------------------------------------------------- the packs

-- 1: a cute school-bag shape: an arched canvas body with an orange arched
-- panel, a rounded zip pocket with a gem patch above it, a top handle with
-- a star charm, a water bottle and a mini wooden pickaxe in the side pouches.
local function rookiePack(c: Ctx)
	local f = c.f
	local col = c.colors
	local w, d = f.w, f.d
	local radius = w / 2
	local archY = f.top - radius -- the arch's middle: the block below, the half disc above
	local blockH = archY - f.bottom
	local panel = rgb(236, 136, 52)
	-- the body: a block with a half-round top (a disc along Z), a rounded leather bottom
	local body = block(c, "Body", at(0, f.bottom + blockH / 2, f.zc), Vector3.new(w, blockH, d), col.Body, FABRIC)
	body.CastShadow = true
	badge(c, "Body", Vector3.new(0, archY, f.zc), w, d, col.Body, FABRIC)
	block(c, "Base", at(0, f.bottom + 0.08, f.zc), Vector3.new(w + 0.06, 0.18, d + 0.06), col.Leather)
	rod(c, "BaseLip", Vector3.new(0, f.bottom + 0.09, f.zf + 0.02), w + 0.02, 0.2, col.Leather)
	-- the orange arched panel on the back with stitches along its foot
	local panelW = w - 0.26
	local panelBottom = f.bottom + 0.3
	block(c, "Panel", at(0, (panelBottom + archY) / 2, f.zf + 0.03), Vector3.new(panelW, archY - panelBottom, 0.06), panel, FABRIC)
	badge(c, "Panel", Vector3.new(0, archY, f.zf + 0.03), panelW, 0.06, panel, FABRIC)
	stitches(c, archY + panelW / 2 - 0.08, f.zf + 0.065, 0.36, 4)
	-- the gem patch high on the panel
	local patchAt = Vector3.new(0, archY + 0.14, f.zf + 0.07)
	badge(c, "Patch", patchAt, 0.36, 0.03, rgb(70, 150, 200), FABRIC)
	diamond(c, "PatchGem", patchAt + Vector3.new(0, 0, 0.02), 0.17, 0.03, rgb(255, 214, 80), FABRIC)
	diamond(c, "PatchGemShine", patchAt + Vector3.new(-0.025, 0.025, 0.035), 0.06, 0.02, col.Stitch, FABRIC)
	-- the front pocket: a stadium (a block with round ends), a zip with a pull
	local pocketY = f.bottom + 0.5
	local pocketH = 0.44
	local pocketW = w * 0.56
	local pocketZ = f.zf + 0.15
	block(c, "Pocket", at(0, pocketY, pocketZ), Vector3.new(pocketW, pocketH, 0.22), col.Body:Lerp(WHITE, 0.12), FABRIC)
	for _, s in { -1, 1 } do
		badge(c, "Pocket", Vector3.new(s * pocketW / 2, pocketY, pocketZ), pocketH, 0.22, col.Body:Lerp(WHITE, 0.12), FABRIC)
	end
	block(c, "Zip", at(0, pocketY + 0.1, pocketZ + 0.115), Vector3.new(pocketW + 0.2, 0.035, 0.02), col.Leather)
	block(c, "ZipPull", at(pocketW * 0.3, pocketY + 0.03, pocketZ + 0.13), Vector3.new(0.06, 0.13, 0.03), col.Buckle, METAL)
	stitches(c, pocketY - 0.12, pocketZ + 0.115, pocketW, 5)
	-- the top handle and a star charm hanging from it
	local handleY = f.top + 0.12
	for _, s in { -1, 1 } do
		post(c, "Handle", Vector3.new(s * 0.18, f.top + 0.05, f.zc), 0.16, 0.08, col.Leather)
	end
	rod(c, "Handle", Vector3.new(0, handleY, f.zc), 0.44, 0.09, col.Leather)
	local charmAt = Vector3.new(0.3, f.top - 0.22, f.zf + 0.1)
	bar(c, "CharmCord", Vector3.new(0.16, handleY, f.zc + 0.2), charmAt + Vector3.new(0, 0.09, 0), 0.03, 0.03, col.Leather)
	block(c, "Charm", CFrame.new(charmAt) * DIAMOND, Vector3.new(0.15, 0.15, 0.05), rgb(255, 206, 70), METAL)
	block(c, "Charm", CFrame.new(charmAt), Vector3.new(0.17, 0.17, 0.04), rgb(255, 206, 70), METAL)
	-- side pouches: a water bottle on the left, the mini pickaxe on the right
	for _, s in { -1, 1 } do
		puff(
			c,
			"SidePouch",
			at(s * (w / 2 + 0.05), f.bottom + 0.42, f.zc),
			Vector3.new(0.34, 0.56, d * 0.8),
			col.Body:Lerp(BLACK, 0.06),
			FABRIC
		)
	end
	local bx = -(w / 2 + 0.1)
	post(c, "Bottle", Vector3.new(bx, f.bottom + 0.7, f.zc), 0.62, 0.26, rgb(84, 156, 214))
	post(c, "BottleCap", Vector3.new(bx, f.bottom + 1.04, f.zc), 0.1, 0.18, rgb(240, 240, 244))
	post(c, "BottleBand", Vector3.new(bx, f.bottom + 0.82, f.zc), 0.06, 0.27, rgb(240, 240, 244))
	local px = w / 2 + 0.1
	pickaxe(
		c,
		Vector3.new(px, f.bottom + 0.3, f.zc + 0.04),
		Vector3.new(px + 0.1, f.top - 0.02, f.zc + 0.04),
		0.52,
		rgb(176, 120, 70),
		rgb(150, 156, 166)
	)
	shoulderStraps(c)
	c.gemAt = patchAt
	c.topAt = Vector3.new(0, handleY + 0.3, f.zc)
end

-- 2: khaki canvas, a green bedroll, a tin mug, a leaf charm on the tongue, a mountain patch.
local function trailPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.TrailPack)
	block(c, "Toggle", CFrame.new(f.emblem + Vector3.new(0, -0.04, 0.02)), Vector3.new(0.2, 0.09, 0.06), col.Buckle, METAL)
	-- the leaf charm hanging from the tongue
	local hang = f.emblem + Vector3.new(0.02, -0.28, 0.04)
	bar(c, "Cord", f.emblem + Vector3.new(0, -0.08, 0.04), hang + Vector3.new(0, 0.08, 0), 0.03, 0.03, col.Leather)
	block(c, "Leaf", CFrame.new(hang) * CFrame.Angles(0, 0, 0.5) * DIAMOND, Vector3.new(0.17, 0.17, 0.03), rgb(110, 176, 70))
	block(
		c,
		"LeafVein",
		CFrame.new(hang + Vector3.new(0, 0, 0.02)) * CFrame.Angles(0, 0, 0.5),
		Vector3.new(0.02, 0.2, 0.02),
		rgb(70, 120, 46)
	)
	-- the mountain patch on the pocket, between the straps
	local ph = f.pocketTop - f.pocketBottom
	local patchAt = Vector3.new(0, f.pocketBottom + ph * 0.38, f.pf + 0.01)
	badge(c, "Patch", patchAt, 0.3, 0.03, rgb(240, 230, 200), FABRIC)
	block(c, "Mountain", CFrame.new(patchAt + Vector3.new(-0.04, -0.03, 0.02)) * DIAMOND, Vector3.new(0.13, 0.13, 0.03), rgb(96, 150, 74))
	block(c, "Mountain", CFrame.new(patchAt + Vector3.new(0.05, -0.05, 0.025)) * DIAMOND, Vector3.new(0.1, 0.1, 0.03), rgb(80, 128, 62))
	-- the tin mug hanging on the right, above the side pocket
	local mx = f.w / 2 + 0.2
	local my = f.sideTop + 0.24
	post(c, "Mug", Vector3.new(mx, my, f.zc), 0.32, 0.3, rgb(170, 176, 184), METAL)
	post(c, "MugRim", Vector3.new(mx, my + 0.16, f.zc), 0.04, 0.32, rgb(120, 126, 134), METAL)
	block(c, "MugHandle", at(mx + 0.18, my, f.zc), Vector3.new(0.06, 0.18, 0.05), rgb(120, 126, 134), METAL)
	block(c, "MugHook", at(f.w / 2 + 0.06, my + 0.12, f.zc), Vector3.new(0.12, 0.05, 0.05), col.Leather)
end

-- 3: brown leather and brass: a brass shield on the tongue, rivets on the
-- inset's corners, a green canteen on the left.
local function leatherRucksack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.LeatherRucksack)
	local e = f.emblem + Vector3.new(0, 0.02, 0.02)
	block(c, "Shield", CFrame.new(e + Vector3.new(0, 0.04, 0)), Vector3.new(0.36, 0.22, 0.05), col.Trim, METAL)
	block(c, "Shield", CFrame.new(e + Vector3.new(0, -0.08, 0)) * DIAMOND, Vector3.new(0.255, 0.255, 0.05), col.Trim, METAL)
	block(c, "ShieldInner", CFrame.new(e + Vector3.new(0, 0.02, 0.02)), Vector3.new(0.26, 0.15, 0.03), col.Panel)
	ball(c, "ShieldBoss", e + Vector3.new(0, 0, 0.04), 0.1, col.Trim, METAL)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.08)), Vector3.new(0.4, 0.4, 0.1))
	for _, sx in { -1, 1 } do
		for _, y in { f.top - 0.2, f.flapBottom + 0.22 } do
			ball(c, "Rivet", Vector3.new(sx * (f.w / 2 - 0.2), y, f.ff + 0.02), 0.08, col.Buckle, METAL)
		end
	end
	-- the canteen on the left, above the side pocket
	local cx = -(f.w / 2 + 0.22)
	local cy = f.sideTop + 0.28
	badge(c, "Canteen", Vector3.new(cx, cy, f.zc), 0.46, 0.2, rgb(70, 98, 74), METAL)
	post(c, "CanteenNeck", Vector3.new(cx, cy + 0.27, f.zc), 0.1, 0.12, col.Trim, METAL)
	post(c, "CanteenCap", Vector3.new(cx, cy + 0.33, f.zc), 0.06, 0.16, col.Trim, METAL)
	block(c, "CanteenStrap", at(cx, cy, f.zc), Vector3.new(0.24, 0.06, 0.48), col.Leather)
end

-- 4: olive canvas, copper rivets, a lantern on the right, a rope coil on the
-- left, a pickaxe across the top and ore spilling out of the front pocket.
local function minersPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.MinersPack)
	setting(c, 0.34)
	diamond(c, "Clasp", f.emblem + Vector3.new(0, 0, 0.05), 0.2, 0.05, col.Buckle, METAL)
	for _, sx in { -1, 1 } do
		for _, y in { f.top - 0.2, f.flapBottom + 0.22 } do
			ball(c, "Rivet", Vector3.new(sx * (f.w / 2 - 0.2), y, f.ff + 0.02), 0.09, col.Buckle, METAL)
		end
		ball(c, "Rivet", Vector3.new(sx * (f.pocketW / 2 - 0.07), f.pocketTop - 0.08, f.zf + 0.39), 0.08, col.Buckle, METAL)
	end
	-- the lantern hangs on a hook on the right
	local lx = f.w / 2 + 0.26
	local ly = f.top - 0.42
	local iron = rgb(58, 60, 72)
	block(c, "LanternHook", at(f.w / 2 + 0.08, ly + 0.3, f.zc), Vector3.new(0.22, 0.05, 0.05), iron, METAL)
	block(c, "LanternBail", at(lx, ly + 0.36, f.zc), Vector3.new(0.18, 0.04, 0.04), iron, METAL)
	post(c, "LanternCap", Vector3.new(lx, ly + 0.19, f.zc), 0.07, 0.32, iron, METAL)
	post(c, "LanternTop", Vector3.new(lx, ly + 0.27, f.zc), 0.1, 0.18, col.Buckle, METAL)
	block(c, "LanternGlass", at(lx, ly, f.zc), Vector3.new(0.22, 0.3, 0.22), glow(col.Glow), NEON)
	for _, s in { -1, 1 } do
		block(c, "LanternBar", at(lx + s * 0.12, ly, f.zc + 0.12), Vector3.new(0.03, 0.3, 0.03), iron, METAL)
	end
	post(c, "LanternBase", Vector3.new(lx, ly - 0.18, f.zc), 0.07, 0.32, iron, METAL)
	fxBox(c, "Lantern", at(lx, ly, f.zc), Vector3.new(0.3, 0.36, 0.3))
	for _, p in c.model:GetChildren() do
		if p:GetAttribute("FxBox") == "Light" and p:IsA("BasePart") then
			p.CFrame = at(lx + 0.6, ly, f.zc + 0.7) -- the lantern lights the pack's side and back
		end
	end
	-- the rope coil on the left
	local rope = rgb(198, 160, 106)
	local rx = -(f.w / 2 + 0.12)
	local ry = f.top - 0.52
	rod(c, "RopeCoil", Vector3.new(rx, ry, f.zc), 0.18, 0.64, rope, FABRIC)
	rod(c, "RopeHole", Vector3.new(rx, ry, f.zc), 0.2, 0.28, rope:Lerp(BLACK, 0.4), FABRIC)
	rod(c, "RopeTurn", Vector3.new(rx - 0.02, ry, f.zc), 0.19, 0.46, rope:Lerp(BLACK, 0.12), FABRIC)
	block(c, "RopeTie", at(rx, ry + 0.3, f.zc), Vector3.new(0.21, 0.08, 0.14), col.Leather)
	-- the pickaxe across the top behind the bedroll, its head out on the left
	pickaxe(
		c,
		Vector3.new(f.w / 2 + 0.05, f.rollY - 0.02, GAP + 0.16),
		Vector3.new(-(f.w / 2 + 0.35), f.rollY + 0.02, GAP + 0.16),
		0.8,
		rgb(150, 100, 60),
		rgb(130, 136, 148)
	)
	-- ore spilling out of the front pocket: copper, a glowing teal crystal, gold
	local oreY = f.pocketTop + 0.03
	block(c, "Ore", at(-0.2, oreY, f.zf + 0.2) * CFrame.Angles(0.4, 0.3, 0.5), Vector3.new(0.22, 0.2, 0.2), rgb(214, 124, 64), METAL)
	block(
		c,
		"Ore",
		at(0.05, oreY + 0.06, f.zf + 0.18) * CFrame.Angles(0.2, 0.7, 0.2),
		Vector3.new(0.18, 0.26, 0.18),
		glow(rgb(60, 220, 200)),
		NEON
	)
	block(c, "Ore", at(0.24, oreY, f.zf + 0.2) * CFrame.Angles(0.6, 0.2, -0.4), Vector3.new(0.2, 0.18, 0.2), rgb(240, 192, 64), METAL)
	fxBox(c, "Ore", at(0.02, oreY + 0.05, f.zf + 0.2), Vector3.new(0.6, 0.3, 0.3))
end

-- 5: slate leather in steel: a riveted steel plate on the flap, steel bands
-- round the body, a chained blue gem clasp, blue crystals in the side pockets.
local function ironboundPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.IronboundPack)
	local steel = col.Panel
	for _, sx in { -1, 1 } do
		for _, y in { f.top - 0.18, f.flapBottom + 0.22 } do
			ball(c, "Rivet", Vector3.new(sx * (f.w / 2 - 0.22), y, f.ff + 0.03), 0.09, col.Buckle, METAL)
		end
	end
	-- a steel band round the body between the flap and the pocket
	local bandY = (f.flapBottom + f.pocketTop) / 2 - 0.12
	block(c, "Band", at(0, bandY, f.zf + 0.035), Vector3.new(f.w + 0.02, 0.13, 0.05), steel, METAL)
	for _, s in { -1, 1 } do
		block(c, "Band", at(s * (f.w / 2 + 0.01), bandY, f.zc), Vector3.new(0.05, 0.13, f.d), steel, METAL)
		ball(c, "Rivet", Vector3.new(s * f.w * 0.36, bandY, f.zf + 0.07), 0.07, col.Buckle, METAL)
	end
	-- the gem clasp: a steel diamond, the glowing gem and a highlight; a short chain below
	local e = f.emblem
	diamond(c, "ClaspPlate", e + Vector3.new(0, 0, 0.02), 0.42, 0.06, steel, METAL)
	diamond(c, "ClaspRim", e + Vector3.new(0, 0, 0.04), 0.32, 0.05, col.Buckle, METAL)
	diamond(c, "Gem", e + Vector3.new(0, 0, 0.07), 0.24, 0.08, glow(col.Gem), NEON)
	diamond(c, "GemShine", e + Vector3.new(-0.03, 0.03, 0.11), 0.08, 0.02, glow(col.Glow):Lerp(WHITE, 0.4), NEON)
	for i = 1, 3 do
		local link = CFrame.new(e + Vector3.new(0, -0.24 - (i - 1) * 0.1, 0.06))
			* CFrame.Angles(0, if i % 2 == 0 then math.pi / 2 else 0, 0)
		block(c, "Chain", link, Vector3.new(0.07, 0.12, 0.03), col.Buckle, METAL)
	end
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.1)), Vector3.new(0.5, 0.5, 0.15))
	-- blue crystals peeking out of the side pockets
	local gem, tip = glow(col.Gem), glow(col.Glow)
	for _, s in { -1, 1 } do
		local base = CFrame.new(s * (f.w / 2 + 0.11), f.sideTop - 0.02, f.zc - 0.08)
		crystal(c, base * CFrame.Angles(0, 0, -s * 0.25), 0.42, 0.13, gem, tip)
		crystal(c, base * CFrame.new(0, 0, 0.16) * CFrame.Angles(0.2, 0, -s * 0.5), 0.3, 0.1, gem, tip)
	end
end

-- 6: forest canvas and brass: a big compass with a glowing needle, a map tube
-- on the left, a spyglass on the right, a red plume, a red bedroll.
local function explorersPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.ExplorersPack)
	local e = f.emblem
	badge(c, "Compass", e + Vector3.new(0, 0, 0.02), 0.6, 0.08, col.Buckle, METAL)
	badge(c, "CompassRing", e + Vector3.new(0, 0, 0.03), 0.5, 0.08, col.Buckle:Lerp(BLACK, 0.3), METAL)
	badge(c, "CompassFace", e + Vector3.new(0, 0, 0.04), 0.44, 0.08, rgb(246, 236, 210))
	for i = 0, 3 do
		local a = i * math.pi / 2
		block(
			c,
			"CompassMark",
			at(e.X + math.sin(a) * 0.17, e.Y + math.cos(a) * 0.17, e.Z + 0.085),
			Vector3.new(0.03, 0.03, 0.02),
			col.Panel
		)
	end
	local needle = CFrame.new(e + Vector3.new(0, 0, 0.09)) * CFrame.Angles(0, 0, -0.5)
	block(c, "Needle", needle * CFrame.new(0, 0.08, 0), Vector3.new(0.05, 0.17, 0.03), glow(col.Glow), NEON)
	block(c, "Needle", needle * CFrame.new(0, -0.08, 0), Vector3.new(0.05, 0.17, 0.03), rgb(200, 60, 50))
	ball(c, "CompassPin", e + Vector3.new(0, 0, 0.1), 0.07, col.Buckle, METAL)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.12)), Vector3.new(0.6, 0.6, 0.15))
	-- the map tube on the left, outside the side pocket
	local tx = -(f.w / 2 + 0.38)
	local len = f.h * 0.72
	local ty = f.bottom + 0.22 + len / 2
	post(c, "MapTube", Vector3.new(tx, ty, f.zc + 0.05), len, 0.32, rgb(226, 206, 160))
	for _, s in { -1, 1 } do
		post(c, "TubeCap", Vector3.new(tx, ty + s * (len / 2 - 0.02), f.zc + 0.05), 0.1, 0.36, col.Buckle, METAL)
	end
	post(c, "TubeStrap", Vector3.new(tx, ty + 0.12, f.zc + 0.05), 0.09, 0.35, col.Leather)
	block(c, "TubeStrap", at(tx + 0.22, ty + 0.12, f.zc + 0.05), Vector3.new(0.22, 0.09, 0.08), col.Leather)
	-- the spyglass on the right: three brass sections, a glass at the top
	local gx = f.w / 2 + 0.36
	local gy = f.bottom + 0.4
	post(c, "Spyglass", Vector3.new(gx, gy + 0.3, f.zc), 0.6, 0.26, col.Buckle, METAL)
	post(c, "SpyglassGrip", Vector3.new(gx, gy + 0.3, f.zc), 0.3, 0.28, col.Leather)
	post(c, "Spyglass", Vector3.new(gx, gy + 0.78, f.zc), 0.36, 0.2, col.Buckle, METAL)
	post(c, "Spyglass", Vector3.new(gx, gy + 1.08, f.zc), 0.26, 0.15, col.Buckle:Lerp(BLACK, 0.15), METAL)
	post(c, "SpyglassLens", Vector3.new(gx, gy + 1.22, f.zc), 0.03, 0.13, glow(rgb(120, 200, 255)), NEON)
	block(c, "SpyglassStrap", at(f.w / 2 + 0.24, gy + 0.3, f.zc), Vector3.new(0.18, 0.08, 0.1), col.Leather)
	-- a red plume tucked behind the right bedroll strap
	local plume = CFrame.new(f.w * 0.27, f.rollY + 0.1, f.rollZ - 0.12) * CFrame.Angles(0, 0, -0.45)
	block(c, "Plume", plume * CFrame.new(0, 0.38, 0), Vector3.new(0.16, 0.8, 0.05), rgb(212, 58, 46))
	block(c, "PlumeTip", plume * CFrame.new(0, 0.74, 0.01), Vector3.new(0.12, 0.2, 0.05), rgb(250, 240, 220))
end

-- 7: deep purple and silver filigree; amethyst crystals grow on the flap, out
-- of the top and the side pockets; violet runes down the flap.
local function amethystPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.AmethystPack)
	local gem = col.Gem -- shaded violet bodies (Foil: a glassy shine), glowing lavender tips
	local light = glow(rgb(170, 140, 255))
	local runeColor = glow(col.Glow)
	local FOIL = Enum.Material.Foil
	setting(c, 0.54)
	local base = CFrame.new(f.emblem + Vector3.new(0, -0.1, 0.07))
	crystal(c, base * CFrame.Angles(0.12, 0, 0), 0.76, 0.26, gem, light, FOIL)
	crystal(c, base * CFrame.new(-0.15, 0, 0) * CFrame.Angles(0.12, 0, 0.55), 0.5, 0.19, gem, light, FOIL)
	crystal(c, base * CFrame.new(0.15, 0, 0) * CFrame.Angles(0.12, 0, -0.6), 0.46, 0.18, gem, light, FOIL)
	crystal(c, base * CFrame.new(-0.24, 0.05, 0) * CFrame.Angles(0.12, 0, 1.0), 0.28, 0.12, gem, light, FOIL)
	crystal(c, base * CFrame.new(0.24, 0.05, 0) * CFrame.Angles(0.12, 0, -1.05), 0.26, 0.11, gem, light, FOIL)
	fxBox(c, "Crystals", CFrame.new(f.emblem + Vector3.new(0, 0.25, 0.2)), Vector3.new(0.8, 0.7, 0.3))
	-- crystals out of the top, behind the bedroll
	local topBase = CFrame.new(0, f.top + 0.12, GAP + 0.22)
	crystal(c, topBase * CFrame.new(-0.35, 0, 0) * CFrame.Angles(-0.15, 0, 0.3), 0.9, 0.24, gem, light, FOIL)
	crystal(c, topBase * CFrame.new(-0.1, 0, 0) * CFrame.Angles(-0.1, 0, 0.05), 1.2, 0.3, gem, light, FOIL)
	crystal(c, topBase * CFrame.new(0.22, 0, 0) * CFrame.Angles(-0.15, 0, -0.35), 0.8, 0.22, gem, light, FOIL)
	fxBox(c, "TopCrystals", CFrame.new(0, f.top + 0.8, GAP + 0.25), Vector3.new(0.9, 0.9, 0.4))
	-- crystal shards in the side pockets
	for _, s in { -1, 1 } do
		local side = CFrame.new(s * (f.w / 2 + 0.11), f.sideTop - 0.02, f.zc - 0.05)
		crystal(c, side * CFrame.Angles(0, 0, -s * 0.3), 0.48, 0.14, gem, light, FOIL)
		crystal(c, side * CFrame.new(0, 0, 0.17) * CFrame.Angles(0.25, 0, -s * 0.55), 0.32, 0.11, gem, light, FOIL)
	end
	-- silver filigree diamonds on the inset's corners, runes down the flap's sides
	for _, sx in { -1, 1 } do
		for _, y in { f.top - 0.18, f.flapBottom + 0.2 } do
			diamond(c, "Filigree", Vector3.new(sx * (f.w / 2 - 0.2), y, f.ff + 0.025), 0.12, 0.03, col.Trim, METAL)
		end
		runeColumn(c, Vector3.new(sx * (f.w / 2 - 0.2), f.top - 0.36, f.ff + 0.025), 0.17, { 2, 3 }, 0.9, runeColor)
	end
end

-- 8: the owner's reference: royal blue and gold, a navy inset with star dots,
-- a gold rune ring with gold rays and a big star crystal, glowing rune columns
-- down the flap and the side pockets, crystals on the side and front pockets.
local function runeboundPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.RuneboundPack)
	local runeColor = glow(col.Glow)
	local e = f.emblem
	-- the emblem: gold rays behind a gold ring, a navy middle, rune ticks, the crystal
	for _, turn in { CFrame.identity, DIAMOND } do
		local long = if turn == DIAMOND then 0.72 else 0.98
		block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.015)) * turn, Vector3.new(long, 0.06, 0.04), col.Trim, METAL)
		block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.015)) * turn, Vector3.new(0.06, long, 0.04), col.Trim, METAL)
	end
	badge(c, "Ring", e + Vector3.new(0, 0, 0.03), 0.66, 0.06, col.Trim, METAL)
	badge(c, "RingInner", e + Vector3.new(0, 0, 0.04), 0.52, 0.06, col.Panel)
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local p = e + Vector3.new(math.cos(a) * 0.205, math.sin(a) * 0.205, 0.075)
		block(c, "RingRune", CFrame.new(p) * CFrame.Angles(0, 0, a), Vector3.new(0.075, 0.03, 0.03), runeColor, NEON)
	end
	diamond(c, "ClaspPlate", e + Vector3.new(0, 0, 0.06), 0.27, 0.05, col.Buckle, METAL)
	diamond(c, "Crystal", e + Vector3.new(0, 0, 0.09), 0.2, 0.1, glow(col.Gem), NEON)
	diamond(c, "CrystalShine", e + Vector3.new(-0.025, 0.025, 0.14), 0.07, 0.02, WHITE, NEON)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.15)), Vector3.new(0.7, 0.7, 0.15))
	-- star dots on the navy inset
	for _, p in { { -0.3, -0.12 }, { -0.12, -0.28 }, { 0.16, -0.1 }, { 0.32, -0.3 }, { -0.36, -0.42 }, { 0.06, -0.44 } } do
		ball(c, "StarDot", Vector3.new(p[1] * f.w / 1.95, f.top + p[2], f.ff + 0.02), 0.05, runeColor, NEON)
	end
	-- rune columns down both sides of the flap and on the side pockets' faces
	for _, s in { -1, 1 } do
		local flapKinds = if s < 0 then { 1, 3, 2, 4 } else { 2, 4, 3, 1 }
		runeColumn(c, Vector3.new(s * (f.w / 2 - 0.15), f.top - 0.12, f.ff + 0.025), 0.17, flapKinds, 1, runeColor)
		runeColumn(c, Vector3.new(s * (f.w / 2 + 0.225), f.sideTop - 0.28, f.zc + 0.03), 0.19, { 2, 3, 4 }, 1, runeColor, s)
		diamond(c, "SideGem", Vector3.new(s * (f.w / 2 + 0.13), f.sideTop - 0.05, f.zc + 0.03 + f.d * 0.37), 0.12, 0.04, runeColor, NEON)
	end
	fxBox(c, "Runes", CFrame.new(0, f.top - 0.2, f.ff + 0.15), Vector3.new(f.w, 0.6, 0.2))
	-- a gold-set crystal between the pocket straps
	local ph = f.pocketTop - f.pocketBottom
	local pocketMid = Vector3.new(0, f.pocketBottom + ph * 0.38, f.pf + 0.02)
	diamond(c, "PocketSetting", pocketMid, 0.24, 0.04, col.Trim, METAL)
	diamond(c, "PocketGem", pocketMid + Vector3.new(0, 0, 0.03), 0.15, 0.05, glow(col.Gem), NEON)
end

-- 9: obsidian plates with lava seams, a fire crystal cluster, gold horns, a
-- molten window in the pocket, two chimneys behind the bedroll (fire and smoke: BackpackFx).
local function emberforgePack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.EmberforgePack)
	local lava = glow(col.Glow)
	local fire = glow(col.Gem)
	local hot = glow(rgb(255, 214, 70))
	-- obsidian plates over the inset with lava glowing in the gaps
	local plateTop = f.top - 0.17
	local plateH = f.flapH - 0.36
	block(c, "LavaGlow", at(0, plateTop - plateH / 2, f.ff + 0.01), Vector3.new(f.w - 0.38, plateH, 0.02), lava, NEON)
	for i, spec in { { -0.3, 0.26, 0.05 }, { 0.0, 0.3, -0.04 }, { 0.3, 0.26, 0.06 } } do
		local y = plateTop - plateH / 2 + (if i == 2 then 0.03 else 0)
		block(
			c,
			"Plate",
			at(spec[1] * f.w, y, f.ff + 0.03) * CFrame.Angles(0, 0, spec[3]),
			Vector3.new(spec[2] * f.w, plateH - 0.06, 0.04),
			col.Panel
		)
	end
	-- the fire crystal cluster in a gold crest
	setting(c, 0.56)
	local base = CFrame.new(f.emblem + Vector3.new(0, -0.1, 0.07))
	crystal(c, base * CFrame.Angles(0.15, 0, 0), 0.78, 0.25, fire, hot)
	crystal(c, base * CFrame.new(-0.15, 0, 0) * CFrame.Angles(0.15, 0, 0.6), 0.5, 0.18, fire, hot)
	crystal(c, base * CFrame.new(0.15, 0, 0) * CFrame.Angles(0.15, 0, -0.55), 0.46, 0.17, fire, hot)
	fxBox(c, "Gem", CFrame.new(f.emblem + Vector3.new(0, 0.2, 0.2)), Vector3.new(0.7, 0.7, 0.25))
	-- lava seams between the flap and the pocket and on the side pockets
	local gapY = (f.flapBottom + f.pocketTop) / 2 - 0.08
	local z = f.zf + 0.045
	bar(c, "Lava", Vector3.new(-f.w * 0.42, gapY + 0.08, z), Vector3.new(-f.w * 0.2, gapY - 0.04, z), 0.045, 0.02, lava, NEON)
	bar(c, "Lava", Vector3.new(-f.w * 0.2, gapY - 0.04, z), Vector3.new(-f.w * 0.06, gapY + 0.05, z), 0.045, 0.02, lava, NEON)
	bar(c, "Lava", Vector3.new(f.w * 0.42, gapY - 0.06, z), Vector3.new(f.w * 0.18, gapY + 0.06, z), 0.045, 0.02, lava, NEON)
	for _, s in { -1, 1 } do
		runeColumn(c, Vector3.new(s * (f.w / 2 + 0.225), f.sideTop - 0.28, f.zc + 0.03), 0.2, { 4, 2, 4 }, 1.1, lava, s)
	end
	-- the molten window in the front pocket, behind gold grill bars
	local ph = f.pocketTop - f.pocketBottom
	local winY = f.pocketBottom + ph * 0.36
	block(c, "Molten", at(0, winY, f.pf + 0.005), Vector3.new(f.pocketW * 0.4, ph * 0.38, 0.02), lava, NEON)
	for i = -1, 1 do
		block(c, "Grill", at(i * f.pocketW * 0.1, winY, f.pf + 0.02), Vector3.new(0.04, ph * 0.42, 0.03), col.Trim, METAL)
	end
	-- gold horns on the top corners
	for _, s in { -1, 1 } do
		local hornBase = CFrame.new(s * (f.w / 2 - 0.05), f.top + 0.12, f.zc) * CFrame.Angles(0, 0, -s * 0.5)
		block(c, "Horn", hornBase * CFrame.new(0, 0.12, 0), Vector3.new(0.18, 0.26, 0.18), col.Trim, METAL)
		local tipTurn = CFrame.Angles(0, if s < 0 then 0 else math.pi, 0)
		part(c, "HornTip", "Wedge", hornBase * CFrame.new(0, 0.37, 0) * tipTurn, Vector3.new(0.18, 0.26, 0.18), col.Trim, METAL)
	end
	-- two chimneys behind the bedroll
	local iron = rgb(46, 44, 50)
	for _, s in { -1, 1 } do
		local cx = s * (f.w / 2 - 0.2)
		local cz = GAP + 0.17
		local y0 = f.top + 0.1
		local y1 = f.rollY + f.rollD / 2 + 0.2
		post(c, "Chimney", Vector3.new(cx, (y0 + y1) / 2, cz), y1 - y0, 0.26, iron, METAL)
		post(c, "ChimneyBand", Vector3.new(cx, y0 + 0.25, cz), 0.06, 0.29, col.Trim, METAL)
		post(c, "ChimneyRim", Vector3.new(cx, y1, cz), 0.08, 0.33, col.Trim, METAL)
		post(c, "Ember", Vector3.new(cx, y1 + 0.03, cz), 0.04, 0.22, lava, NEON)
		fxBox(c, if s < 0 then "ChimneyLeft" else "ChimneyRight", at(cx, y1 + 0.2, cz), Vector3.new(0.24, 0.3, 0.24))
	end
	fxBox(c, "Aura", at(0, f.midY, f.zc), Vector3.new(f.w + 0.4, f.h, f.d + 0.4))
end

-- 10: pearl and gold, a galaxy flap with twinkles, a star crystal in a gold
-- star, a galaxy window in the pocket, orbiting star shards and two wings of
-- pearl feathers on gold arms with glowing tips.
local function starforgePack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.StarforgePack)
	local star = glow(col.Gem)
	local violet = glow(col.Glow)
	local gold = col.Trim
	local sparkle = WHITE:Lerp(violet, 0.25)
	-- the galaxy flap: a glowing violet inset with twinkles
	block(c, "Galaxy", at(0, f.top - f.flapH / 2 + 0.03, f.ff + 0.012), Vector3.new(f.w - 0.4, f.flapH - 0.36, 0.02), col.Panel, NEON)
	twinkle(c, Vector3.new(-f.w * 0.36, f.top - 0.22, f.ff + 0.03), 0.16, sparkle)
	twinkle(c, Vector3.new(f.w * 0.37, f.top - 0.44, f.ff + 0.03), 0.12, sparkle)
	twinkle(c, Vector3.new(f.w * 0.12, f.top - 0.17, f.ff + 0.03), 0.1, sparkle)
	twinkle(c, Vector3.new(-f.w * 0.14, f.top - 0.5, f.ff + 0.03), 0.08, sparkle)
	-- the star: a gold eight-point star and ring behind a big crystal
	local e = f.emblem
	badge(c, "Setting", e + Vector3.new(0, 0, 0.02), 0.5, 0.06, gold, METAL)
	for _, turn in { CFrame.identity, DIAMOND } do
		local long = if turn == DIAMOND then 0.66 else 1.0
		block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.04)) * turn, Vector3.new(long, 0.07, 0.04), gold, METAL)
		block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.04)) * turn, Vector3.new(0.07, long, 0.04), gold, METAL)
	end
	diamond(c, "Crystal", e + Vector3.new(0, 0, 0.09), 0.3, 0.1, star, NEON)
	diamond(c, "CrystalShine", e + Vector3.new(-0.04, 0.04, 0.14), 0.09, 0.02, WHITE, NEON)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.15)), Vector3.new(0.8, 0.8, 0.15))
	-- a galaxy window in the front pocket
	local ph = f.pocketTop - f.pocketBottom
	local panelY = f.pocketBottom + ph * 0.38
	block(c, "Galaxy", at(0, panelY, f.pf + 0.005), Vector3.new(f.pocketW * 0.36, ph * 0.46, 0.02), col.Panel, NEON)
	twinkle(c, Vector3.new(-f.pocketW * 0.06, panelY + 0.05, f.pf + 0.02), 0.1, sparkle)
	-- star runes on the side pockets
	for _, s in { -1, 1 } do
		runeColumn(c, Vector3.new(s * (f.w / 2 + 0.225), f.sideTop - 0.28, f.zc + 0.03), 0.19, { 3, 1, 3 }, 1, violet, s)
	end
	-- three star shards orbiting over the bedroll
	for i, spec in { { -0.62, 0.38, 0.5 }, { 0.0, 0.62, -0.1 }, { 0.6, 0.42, 0.3 } } do
		local shardAt = Vector3.new(spec[1] * f.w / 2, f.rollY + f.rollD / 2 + spec[2], f.rollZ + spec[3] * 0.3)
		local shardColor = if i == 2 then star else violet
		block(c, "StarShard", CFrame.new(shardAt) * CFrame.Angles(0, i * 0.6, math.pi / 4), Vector3.new(0.14, 0.14, 0.14), shardColor, NEON)
		twinkle(c, shardAt + Vector3.new(0.14, 0.14, 0.04), 0.09, sparkle)
	end
	fxBox(c, "Aura", at(0, f.top + 0.4, f.zc), Vector3.new(f.w + 0.8, 1.4, f.d + 0.4))
	-- two wings: a gold arm sweeping out and up, five pearl feathers hanging
	-- from it (longer toward the tip, pointing out and down), glowing tips
	for _, s in { -1, 1 } do
		local rootAt = Vector3.new(s * (f.w / 2 + 0.02), f.top - 0.12, f.zc + 0.12)
		local armAngle = 0.5
		local armLength = 1.25
		local arm = Vector3.new(s * math.cos(armAngle), math.sin(armAngle), 0)
		block(
			c,
			"WingArm",
			CFrame.new(rootAt + arm * (armLength / 2)) * CFrame.Angles(0, 0, s * armAngle),
			Vector3.new(armLength, 0.14, 0.14),
			gold,
			METAL
		)
		for i, spec in { { 0.12, 0.55, -1.25 }, { 0.32, 0.7, -1.0 }, { 0.52, 0.85, -0.75 }, { 0.72, 1.0, -0.5 }, { 0.92, 1.08, -0.25 } } do
			local from = rootAt + arm * (armLength * spec[1])
			local len, angle = spec[2], spec[3]
			local dir = Vector3.new(s * math.cos(angle), math.sin(angle), 0)
			local turn = CFrame.Angles(0, 0, s * angle)
			local z = Vector3.new(0, 0, if i % 2 == 0 then -0.03 else 0.03)
			block(c, "Feather", CFrame.new(from + dir * (len / 2) + z) * turn, Vector3.new(len, 0.3, 0.06), col.Body)
			block(c, "FeatherTip", CFrame.new(from + dir * (len - 0.11) + z) * turn, Vector3.new(0.22, 0.32, 0.08), violet, NEON)
		end
		local wingBox = at(s * (f.w / 2 + 0.9), f.top + 0.1, f.zc + 0.12)
		fxBox(c, if s < 0 then "WingLeft" else "WingRight", wingBox, Vector3.new(1.0, 0.9, 0.3))
	end
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	RookiePack = rookiePack,
	TrailPack = trailPack,
	LeatherRucksack = leatherRucksack,
	MinersPack = minersPack,
	IronboundPack = ironboundPack,
	ExplorersPack = explorersPack,
	AmethystPack = amethystPack,
	RuneboundPack = runeboundPack,
	EmberforgePack = emberforgePack,
	StarforgePack = starforgePack,
}

-- The lowest and highest point of the model's visible parts above Root (Y).
local function heightRange(model: Model): (number, number)
	local low, high = math.huge, -math.huge
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf = p.CFrame
			local s = p.Size
			local half = math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
			low = math.min(low, cf.Position.Y - half)
			high = math.max(high, cf.Position.Y + half)
		end
	end
	return low, high
end

--[[
	Builds a pack. `display` (shop stands, pedestals, previews): leaves out
	the shoulder straps, which only make sense on a body.
]]
function BackpackBuilder.build(backpackId: string, display: boolean?): Model
	local pack = BackpackData.ById[backpackId]
	local builder = BUILDERS[backpackId]
	assert(pack and builder, "unknown backpack " .. tostring(backpackId))
	local model = Instance.new("Model")
	model.Name = pack.Id
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
	local c: Ctx = {
		model = model,
		root = root,
		colors = pack.Colors,
		f = makeFrame(pack.Size, STYLES[pack.Id]),
		display = display == true,
		gemAt = nil,
		topAt = nil,
	}
	builder(c)
	attach(c, "Gem", c.gemAt or c.f.emblem + Vector3.new(0, 0, 0.12))
	attach(c, "Top", c.topAt or Vector3.new(0, c.f.rollY + c.f.rollD / 2 + 0.2, c.f.rollZ))
	local low, high = heightRange(model)
	local parts = 0
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			parts += 1
		end
	end
	model:SetAttribute("BackpackId", pack.Id)
	model:SetAttribute("BottomY", low)
	model:SetAttribute("TopY", high)
	model:SetAttribute("Parts", parts)
	return model
end

--[[
	Makes a built pack wearable: unanchors every part, makes it massless and
	welds it to Root with a WeldConstraint (Root stays the one part to weld
	to the character's UpperTorso). Call before parenting it to the character.
]]
function BackpackBuilder.rig(model: Model)
	local root = model.PrimaryPart
	assert(root, "backpack without Root")
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			if p ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
end

return BackpackBuilder
