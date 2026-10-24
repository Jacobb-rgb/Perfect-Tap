--[[
	Builds the ten backpacks (BackpackData) from parts only (no meshes), in the
	clean look of the owner's reference (a royal blue rune pack: rounded
	panels with gold rims, a glowing crystal in a ring on the flap, a bedroll
	on top, a rimmed front pocket, side pouches with runes). Owner on v2
	(2026-10-24): "nejsi tak clean a do detailu ani tak dobre vypadajici jako
	na tom obrazku", so v3 is made of round-cornered slabs with rims (slab,
	framed) instead of loose boxes. Worst to best:

	  RookiePack       a cute school bag: an arched body, an orange arched
	                   panel, a zip pocket, a gem patch, a star charm, a
	                   water bottle and a mini wooden pickaxe
	  TrailPack        khaki canvas, a mountain patch, a leaf charm, a tin mug
	  LeatherRucksack  leather in brass rims, a brass shield, a canteen
	  MinersPack       copper rims, crossed pickaxes, a lantern, a rope coil,
	                   a pickaxe across the top, ore spilling out
	  IronboundPack    steel rims, a riveted steel plate, a chained blue gem,
	                   blue crystals in the side pouches
	  ExplorersPack    brass rims, a glowing compass, a map tube, a spyglass,
	                   a plume
	  AmethystPack     silver rims and filigree, an amethyst cluster, crystals
	                   out of the top and the pouches, violet runes
	  RuneboundPack    the reference: gold rims, a navy panel with star dots
	                   and rune columns, a rune ring with a cut crystal
	  EmberforgePack   lava cracks in obsidian, a fire crystal, gold
	                   horns, a molten pocket window, two chimneys
	  StarforgePack    pearl and gold, a galaxy panel, a star crystal with
	                   rays, orbiting star shards, two feathered wings
	Budget: BackpackBuilder.MaxParts (tests). Effects (particles, the light)
	are BackpackFx's: the builder only leaves invisible "FxBox" parts where
	they go.

	Contract: a Model named after the pack id, PrimaryPart "Root" (an invisible
	part) at the wearer's BACK: the middle of UpperTorso's back face. +Z points
	away from the back (the side the camera sees from behind the player), +Y
	up, X across. The bag hangs from TOP (UpperTorso's top edge) down past the
	waist; padded straps go over the shoulders to the chest (z = -1, a 1 stud
	deep torso) unless it is built for display. Attachments on Root: "Gem"
	(the emblem) and "Top" (above the bedroll). FxBox parts: invisible,
	attribute "FxBox" = their name (Gem, Light, Lantern, Ore, Crystals,
	TopCrystals, Runes, ChimneyLeft / ChimneyRight, Aura, WingLeft /
	WingRight), the volume an effect fills. Model attributes: BackpackId,
	BottomY / TopY (the lowest / highest visible point above Root, for stands
	and shop pedestals), Parts.
	Everything is anchored with CanCollide / CanTouch / CanQuery off, no
	shadows but the bag's; BackpackBuilder.rig(model) unanchors it and welds
	every part to Root (massless) for wearing.

	Pure and deterministic: only Instance creation, so Lune tests and previews
	can build it.
]]

local BackpackData = require(script.Parent.Parent.Config.BackpackData)
local ItemBuilder = require(script.Parent.ItemBuilder)

local BackpackBuilder = {}

BackpackBuilder.Top = 0.8 -- the bag's top above Root (UpperTorso's top edge)
BackpackBuilder.Gap = 0.04 -- Root (the back) to the bag's inner face
BackpackBuilder.MaxParts = 200

local TOP = BackpackBuilder.Top
local GAP = BackpackBuilder.Gap

local rgb = Color3.fromRGB
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local FOIL = Enum.Material.Foil

local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- Roblox cylinders run along X
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local DIAMOND = CFrame.Angles(0, 0, math.pi / 4) -- a square turned into a diamond (facing Z)

type Kind = "Block" | "Wedge" | "Cylinder" | "Ball"

-- Where the parts of the common anatomy are (every pack has one, the Rookie Pack builds its own shape).
type Layout = {
	w: number,
	h: number,
	d: number,
	r: number, -- the bag's corner radius
	top: number,
	bottom: number,
	zc: number, -- the bag's middle (Z)
	zf: number, -- the bag's outer face (Z)
	ff: number, -- the flap's outer face (Z)
	flapTop: number,
	flapBottom: number,
	flapMid: number,
	inner: CFrame, -- the flap's inner panel: its middle, on the flap face
	innerW: number,
	innerH: number,
	emblem: Vector3, -- the flap's centrepiece, on its face
	baseH: number, -- the leather bottom's height
	pocketY: number,
	pocketW: number,
	pocketH: number,
	pf: number, -- the front pocket's outer face (Z)
	pouches: { CFrame }, -- [1] left, [2] right side pouch: its middle, +Z facing out
	pouchH: number,
	pouchTop: number,
	rollY: number,
	rollD: number,
	rollLength: number,
}

type Ctx = {
	model: Model,
	root: BasePart,
	colors: BackpackData.Colors,
	size: Vector3,
	f: Layout,
	display: boolean, -- on a stand (shop, previews): no shoulder straps
	gemAt: Vector3?, -- the emblem / the top when not the layout's (the Rookie Pack)
	topAt: Vector3?,
}

-- What the common anatomy builds.
type Anatomy = {
	Inner: boolean?, -- a panel inside the flap (Panel colour) with a rim-coloured line
	InnerMaterial: Enum.Material?, -- Neon: the glowing lava / galaxy panels
	Pocket: boolean?, -- the rimmed front pocket
	SidePouches: boolean?,
	Roll: boolean?, -- the bedroll on top
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
	p.Material = material or SMOOTH
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

-- A cylinder along X (the bedroll, coils) centered on `position`.
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

-- A disc facing +Z (rings, patches, compasses) centered on `position`.
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

-- A soft rounded pouch: a part drawn as the ellipsoid that fills `size` (a Sphere SpecialMesh: built in, no upload).
local function puff(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3): BasePart
	local p = block(c, name, cf, size, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
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

-- A four-point star (two crossed bars) facing +Z.
local function twinkle(c: Ctx, position: Vector3, size: number, color: Color3)
	block(c, "Twinkle", CFrame.new(position), Vector3.new(size, size * 0.18, 0.03), color, NEON)
	block(c, "Twinkle", CFrame.new(position), Vector3.new(size * 0.18, size, 0.03), color, NEON)
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

-- Moves an FxBox the anatomy placed (a lantern's light, say).
local function moveFx(c: Ctx, name: string, cf: CFrame)
	for _, p in c.model:GetChildren() do
		if p:IsA("BasePart") and p:GetAttribute("FxBox") == name then
			p.CFrame = cf
		end
	end
end

local function castShadows(c: Ctx, name: string)
	for _, p in c.model:GetChildren() do
		if p:IsA("BasePart") and p.Name == name then
			p.CastShadow = true
		end
	end
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

---------------------------------------------------------------- the clean kit

--[[
	A rounded rectangle slab facing ±Z of `cf` (its middle): w × h, the top
	corners rounded by rTop and the bottom ones by rBottom, `depth` thick.
	Up to 7 parts (one block when both radii are 0; a full half-round when a
	radius is half the width).
]]
local function slab(
	c: Ctx,
	name: string,
	cf: CFrame,
	w: number,
	h: number,
	depth: number,
	rTop: number,
	rBottom: number,
	color: Color3,
	material: Enum.Material?
)
	local rt = math.clamp(rTop, 0, math.min(w, h) / 2)
	local rb = math.clamp(rBottom, 0, math.min(w, h) / 2)
	local midH = h - rt - rb
	if midH > 0.005 then
		block(c, name, cf * CFrame.new(0, (rb - rt) / 2, 0), Vector3.new(w, midH, depth), color, material)
	end
	for _, spec in { { rt, 1 }, { rb, -1 } } do
		local r, sy = spec[1], spec[2]
		if r > 0.005 then
			local xs: { number } = if w - 2 * r > 0.005 then { -1, 1 } else { 0 }
			if w - 2 * r > 0.005 then
				block(c, name, cf * CFrame.new(0, sy * (h / 2 - r / 2), 0), Vector3.new(w - 2 * r, r, depth), color, material)
			end
			for _, sx in xs do
				local corner = cf * CFrame.new(sx * (w / 2 - r), sy * (h / 2 - r), 0) * ALONG_Z
				part(c, name, "Cylinder", corner, Vector3.new(depth, 2 * r, 2 * r), color, material)
			end
		end
	end
end

-- A slab with a rim: the same shape `t` bigger all round, just behind it.
local function framed(
	c: Ctx,
	name: string,
	cf: CFrame,
	w: number,
	h: number,
	depth: number,
	rTop: number,
	rBottom: number,
	color: Color3,
	rim: Color3,
	t: number
)
	slab(c, name .. "Rim", cf * CFrame.new(0, 0, -0.012), w + 2 * t, h + 2 * t, depth, rTop + t, rBottom + t, rim)
	slab(c, name, cf, w, h, depth, rTop, rBottom, color)
end

-- A cut gem facing +Z: the glowing outer cut, a brighter table facet and a white shine. 3 parts.
local function cutGem(c: Ctx, position: Vector3, size: number, rim: Color3, core: Color3)
	diamond(c, "Gem", position, size, 0.1, rim, NEON)
	diamond(c, "GemTable", position + Vector3.new(0, 0, 0.045), size * 0.56, 0.06, core, NEON)
	diamond(c, "GemShine", position + Vector3.new(-size * 0.13, size * 0.13, 0.08), size * 0.16, 0.02, WHITE, NEON)
end

--[[
	One rune glyph (Neon, 1-2 thin strokes) `s` tall on the face `face` (its
	+Z is the outward normal): 1 a stem with a slanted branch, 2 a cross,
	3 a small diamond, 4 a stem with a bar on top.
]]
local function glyph(c: Ctx, face: CFrame, kind: number, s: number, color: Color3)
	local t = 0.03
	if kind == 1 then
		block(c, "Rune", face, Vector3.new(t, s, 0.03), color, NEON)
		local branch = face * CFrame.new(s * 0.12, s * 0.12, 0) * CFrame.Angles(0, 0, -0.75)
		block(c, "Rune", branch, Vector3.new(t, s * 0.5, 0.03), color, NEON)
	elseif kind == 2 then
		block(c, "Rune", face * CFrame.Angles(0, 0, 0.5), Vector3.new(t, s, 0.03), color, NEON)
		block(c, "Rune", face * CFrame.Angles(0, 0, -0.5), Vector3.new(t, s, 0.03), color, NEON)
	elseif kind == 3 then
		block(c, "Rune", face * DIAMOND, Vector3.new(s * 0.5, s * 0.5, 0.03), color, NEON)
	else
		block(c, "Rune", face, Vector3.new(t, s, 0.03), color, NEON)
		block(c, "Rune", face * CFrame.new(0, s * 0.45, 0), Vector3.new(s * 0.6, t, 0.03), color, NEON)
	end
end

-- `count` glyphs down from `face`, `step` apart, cycling the kinds from `first`.
local function glyphColumn(c: Ctx, face: CFrame, count: number, step: number, s: number, color: Color3, first: number)
	for i = 1, count do
		glyph(c, face * CFrame.new(0, -(i - 1) * step, 0), (first + i - 2) % 4 + 1, s, color)
	end
end

-- A buckle facing +Z: a metal frame, the strap showing through, a prong. 3 parts.
local function buckle(c: Ctx, position: Vector3)
	block(c, "Buckle", CFrame.new(position), Vector3.new(0.27, 0.23, 0.05), c.colors.Buckle)
	block(c, "BuckleHole", CFrame.new(position + Vector3.new(0, 0, 0.012)), Vector3.new(0.14, 0.1, 0.05), c.colors.Leather)
	block(c, "BuckleProng", CFrame.new(position + Vector3.new(0, 0, 0.03)), Vector3.new(0.03, 0.15, 0.03), c.colors.Buckle)
end

-- A small pickaxe: a handle from `low` to `high`, an iron head across its top. 5 parts.
local function pickaxe(c: Ctx, low: Vector3, high: Vector3, headLength: number, wood: Color3, iron: Color3)
	bar(c, "PickHandle", low, high, 0.1, 0.1, wood)
	local dir = (high - low).Unit
	local across = Vector3.new(dir.Y, -dir.X, 0).Unit
	local head = CFrame.fromMatrix(high, across, dir)
	block(c, "PickHead", head, Vector3.new(headLength, 0.13, 0.11), iron)
	block(c, "PickCollar", head, Vector3.new(0.15, 0.2, 0.14), iron:Lerp(BLACK, 0.3))
	for _, s in { -1, 1 } do
		local point = head
			* CFrame.new(s * (headLength / 2 + 0.07), -0.02, 0)
			* CFrame.Angles(0, 0, s * math.pi / 2)
			* CFrame.Angles(0, math.pi / 2, 0)
		part(c, "PickPoint", "Wedge", point, Vector3.new(0.11, 0.1, 0.14), iron)
	end
end

---------------------------------------------------------------- the common anatomy

local function layout(size: Vector3): Layout
	local w, h, d = size.X, size.Y, size.Z
	local top = TOP
	local bottom = top - h
	local zc, zf = GAP + d / 2, GAP + d
	local flapTop = top + 0.05
	local flapBottom = top - h * 0.47
	local flapMid = (flapTop + flapBottom) / 2
	local ff = zf + 0.1
	local pocketH = h * 0.27
	local pouchH = h * 0.45
	local rollD = math.min(0.64, d * 0.62)
	local pouches = {}
	for i, s in { -1, 1 } do
		pouches[i] = CFrame.new(s * (w / 2 + 0.1), bottom + 0.22 + pouchH / 2, zc) * CFrame.Angles(0, s * math.pi / 2, 0)
	end
	return {
		w = w,
		h = h,
		d = d,
		r = w * 0.15,
		top = top,
		bottom = bottom,
		zc = zc,
		zf = zf,
		ff = ff,
		flapTop = flapTop,
		flapBottom = flapBottom,
		flapMid = flapMid,
		inner = CFrame.new(0, flapMid + 0.02, ff + 0.012),
		innerW = w - 0.46,
		innerH = flapTop - flapBottom - 0.46,
		emblem = Vector3.new(0, flapMid - 0.06, ff + 0.02),
		baseH = h * 0.23,
		pocketY = bottom + 0.2 + pocketH / 2,
		pocketW = w * 0.5,
		pocketH = pocketH,
		pf = zf + 0.23,
		pouches = pouches,
		pouchH = pouchH,
		pouchTop = bottom + 0.22 + pouchH,
		rollY = top + 0.1 + rollD / 2,
		rollD = rollD,
		rollLength = w * 0.92,
	}
end

local function bedroll(c: Ctx)
	local f = c.f
	local col = c.colors
	rod(c, "Bedroll", Vector3.new(0, f.rollY, f.zc), f.rollLength, f.rollD, col.Roll)
	for _, s in { -1, 1 } do
		local endAt = Vector3.new(s * f.rollLength / 2, f.rollY, f.zc)
		rod(c, "BedrollEnd", endAt, 0.05, f.rollD * 0.9, col.Roll:Lerp(BLACK, 0.3))
		rod(c, "BedrollCurl", endAt + Vector3.new(s * 0.012, 0.04, 0.03), 0.05, f.rollD * 0.46, col.Roll:Lerp(WHITE, 0.2))
		local sx = s * f.w * 0.28
		rod(c, "BedrollStrap", Vector3.new(sx, f.rollY, f.zc), 0.13, f.rollD + 0.05, col.Leather)
		block(c, "BedrollBuckle", at(sx, f.rollY, f.zc + f.rollD / 2 + 0.03), Vector3.new(0.18, 0.15, 0.05), col.Buckle)
	end
end

--[[
	The common anatomy: the round-cornered bag with a leather bottom, the
	rimmed flap wrapping over the top (+ an inner panel), two straps from
	under the flap to the bottom with prong buckles, the rimmed front pocket
	and side pouches, the bedroll, the light box, the shoulder straps.
]]
local function anatomy(c: Ctx, a: Anatomy)
	local f = c.f
	local col = c.colors
	local w, h, d, r = f.w, f.h, f.d, f.r
	local t = 0.05
	slab(c, "Body", at(0, (f.top + f.bottom) / 2, f.zc), w, h, d, r, r, col.Body)
	castShadows(c, "Body")
	slab(c, "Base", at(0, f.bottom + f.baseH / 2 - 0.02, f.zc), w + 0.06, f.baseH, d + 0.06, 0, r + 0.03, col.Leather)

	local fh = f.flapTop - f.flapBottom
	framed(c, "Flap", at(0, f.flapMid, f.zf + 0.02), w + 0.06, fh, 0.16, r + 0.03, r * 0.73, col.Flap, col.Trim, t)
	block(c, "FlapTop", at(0, f.top + 0.03, (GAP + f.zf) / 2), Vector3.new(w - 2 * r, 0.1, d), col.Flap)
	for _, s in { -1, 1 } do
		local corner = at(s * (w / 2 - r), f.top - r, (GAP + f.zf) / 2) * ALONG_Z
		part(c, "FlapTop", "Cylinder", corner, Vector3.new(d, 2 * r + 0.1, 2 * r + 0.1), col.Flap)
	end
	if a.Inner then
		block(c, "InnerLine", f.inner * CFrame.new(0, 0, -0.004), Vector3.new(f.innerW + 0.07, f.innerH + 0.07, 0.02), col.Trim)
		block(c, "Inner", f.inner, Vector3.new(f.innerW, f.innerH, 0.02), col.Panel, a.InnerMaterial)
	end

	for _, s in { -1, 1 } do
		local x = s * w * 0.34
		local y0, y1 = f.flapBottom + 0.05, f.bottom + f.baseH - 0.08
		block(c, "Strap", at(x, (y0 + y1) / 2, f.zf + 0.015), Vector3.new(0.17, y0 - y1, 0.03), col.Leather)
		buckle(c, Vector3.new(x, f.flapBottom - 0.24, f.zf + 0.04))
		ball(c, "Rivet", Vector3.new(x, y1 + 0.02, f.zf + 0.06), 0.08, col.Buckle)
	end

	if a.Pocket then
		local pr = f.pocketH * 0.3
		framed(c, "Pocket", at(0, f.pocketY, f.zf + 0.1), f.pocketW, f.pocketH, 0.26, pr, pr, col.Body, col.Trim, t)
	end
	if a.SidePouches then
		for _, pouch in f.pouches do
			framed(c, "SidePouch", pouch, d * 0.78, f.pouchH, 0.22, 0.2, 0.2, col.Body, col.Trim, t * 0.9)
		end
	end
	if a.Roll then
		bedroll(c)
	end
	fxBox(c, "Light", at(0, f.flapMid, f.ff + 0.9), Vector3.new(0.2, 0.2, 0.2))
	shoulderStraps(c)
end

-- The standard set: everything but a glowing inner panel.
local FULL: Anatomy = { Inner = true, Pocket = true, SidePouches = true, Roll = true }

---------------------------------------------------------------- the packs

-- 1: a cute school bag: an arched body, an orange arched panel with a gem
-- patch, a rimmed zip pocket, a top handle with a gold star charm, a water
-- bottle and a mini wooden pickaxe in the side pouches.
local function rookiePack(c: Ctx)
	local col = c.colors
	local w, h, d = c.size.X, c.size.Y, c.size.Z
	local top, bottom = TOP, TOP - h
	local zc, zf = GAP + d / 2, GAP + d
	slab(c, "Body", at(0, (top + bottom) / 2, zc), w, h, d, w / 2, 0.24, col.Body)
	castShadows(c, "Body")
	slab(c, "Base", at(0, bottom + 0.16, zc), w + 0.05, 0.34, d + 0.05, 0, 0.26, col.Leather)
	-- the arched panel
	local panelW = w - 0.26
	local panelTop, panelBottom = top - 0.13, bottom + 0.3
	local panelMid = (panelTop + panelBottom) / 2
	framed(c, "Panel", at(0, panelMid, zf + 0.03), panelW, panelTop - panelBottom, 0.08, panelW / 2, 0.14, col.Flap, col.Trim, 0.035)
	local patchAt = Vector3.new(0, panelTop - panelW / 2 + 0.02, zf + 0.09)
	badge(c, "Patch", patchAt, 0.38, 0.03, rgb(70, 150, 210))
	diamond(c, "PatchGem", patchAt + Vector3.new(0, 0, 0.02), 0.18, 0.03, col.Gem)
	diamond(c, "PatchShine", patchAt + Vector3.new(-0.03, 0.03, 0.035), 0.06, 0.02, WHITE)
	-- the zip pocket: a rimmed pill
	local pocketW, pocketH = w * 0.62, 0.42
	local pocketY = bottom + 0.52
	local pocketColor = col.Body:Lerp(WHITE, 0.25)
	framed(c, "Pocket", at(0, pocketY, zf + 0.14), pocketW, pocketH, 0.2, pocketH / 2, pocketH / 2, pocketColor, col.Trim, 0.035)
	block(c, "Zip", at(0, pocketY + 0.09, zf + 0.245), Vector3.new(pocketW - 0.12, 0.035, 0.02), col.Trim)
	block(c, "ZipPull", at(pocketW * 0.28, pocketY + 0.03, zf + 0.26), Vector3.new(0.07, 0.14, 0.03), col.Buckle)
	-- the top handle and a gold star charm
	local handleY = top + 0.12
	for _, s in { -1, 1 } do
		post(c, "Handle", Vector3.new(s * 0.18, top + 0.05, zc), 0.16, 0.08, col.Leather)
	end
	rod(c, "Handle", Vector3.new(0, handleY, zc), 0.44, 0.09, col.Leather)
	local charmAt = Vector3.new(0.34, top - 0.28, zf + 0.12)
	bar(c, "CharmCord", Vector3.new(0.18, handleY, zc + 0.2), charmAt + Vector3.new(0, 0.1, 0), 0.03, 0.03, col.Leather)
	diamond(c, "Charm", charmAt, 0.16, 0.05, col.Buckle)
	block(c, "Charm", CFrame.new(charmAt), Vector3.new(0.16, 0.16, 0.04), col.Buckle)
	-- side pouches: a water bottle on the left, the mini pickaxe on the right
	for _, s in { -1, 1 } do
		puff(c, "SidePouch", at(s * (w / 2 + 0.05), bottom + 0.42, zc), Vector3.new(0.34, 0.56, d * 0.8), col.Body:Lerp(BLACK, 0.06))
	end
	local bx = -(w / 2 + 0.1)
	post(c, "Bottle", Vector3.new(bx, bottom + 0.7, zc), 0.62, 0.26, rgb(84, 156, 214))
	post(c, "BottleBand", Vector3.new(bx, bottom + 0.82, zc), 0.06, 0.27, WHITE)
	post(c, "BottleCap", Vector3.new(bx, bottom + 1.04, zc), 0.1, 0.18, WHITE)
	local px = w / 2 + 0.1
	pickaxe(
		c,
		Vector3.new(px, bottom + 0.3, zc + 0.04),
		Vector3.new(px + 0.1, top - 0.02, zc + 0.04),
		0.52,
		rgb(176, 120, 70),
		rgb(150, 156, 166)
	)
	shoulderStraps(c)
	c.gemAt = patchAt
	c.topAt = Vector3.new(0, handleY + 0.3, zc)
end

-- 2: khaki canvas in dark piping: a mountain patch on the flap, a toggle and a
-- leaf charm under it, a green bedroll, a tin mug on the right.
local function trailPack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, { Pocket = true, SidePouches = true, Roll = true })
	local e = f.emblem
	badge(c, "PatchRim", e - Vector3.new(0, 0, 0.01), 0.58, 0.04, col.Trim)
	badge(c, "Patch", e, 0.5, 0.04, rgb(240, 230, 200))
	diamond(c, "Mountain", e + Vector3.new(-0.06, -0.05, 0.025), 0.22, 0.03, col.Roll)
	diamond(c, "Mountain", e + Vector3.new(0.08, -0.08, 0.03), 0.16, 0.03, col.Roll:Lerp(BLACK, 0.25))
	diamond(c, "Snow", e + Vector3.new(-0.06, 0.04, 0.035), 0.07, 0.03, WHITE)
	-- the toggle at the flap's edge and a leaf charm on a cord
	block(c, "Toggle", at(0, f.flapBottom + 0.02, f.ff + 0.03), Vector3.new(0.22, 0.09, 0.06), col.Buckle)
	local leafAt = Vector3.new(0.06, f.flapBottom - 0.3, f.ff + 0.03)
	bar(c, "Cord", Vector3.new(0, f.flapBottom - 0.02, f.ff + 0.03), leafAt + Vector3.new(0, 0.1, 0), 0.03, 0.03, col.Leather)
	block(c, "Leaf", CFrame.new(leafAt) * CFrame.Angles(0, 0, 0.45) * DIAMOND, Vector3.new(0.18, 0.18, 0.03), rgb(110, 176, 70))
	block(
		c,
		"LeafVein",
		CFrame.new(leafAt + Vector3.new(0, 0, 0.02)) * CFrame.Angles(0, 0, 0.45),
		Vector3.new(0.02, 0.22, 0.02),
		rgb(70, 120, 46)
	)
	-- a wooden button on the pocket
	ball(c, "Button", Vector3.new(0, f.pocketY + 0.04, f.pf + 0.02), 0.12, rgb(150, 100, 60))
	-- the tin mug on the right, above the side pouch
	local mx = f.w / 2 + 0.22
	local my = f.pouchTop + 0.26
	post(c, "Mug", Vector3.new(mx, my, f.zc), 0.32, 0.3, rgb(176, 182, 190))
	post(c, "MugRim", Vector3.new(mx, my + 0.16, f.zc), 0.04, 0.32, rgb(126, 132, 140))
	block(c, "MugHandle", at(mx + 0.18, my, f.zc), Vector3.new(0.06, 0.18, 0.05), rgb(126, 132, 140))
	block(c, "MugHook", at(f.w / 2 + 0.08, my + 0.12, f.zc), Vector3.new(0.12, 0.05, 0.05), col.Leather)
end

-- 3: leather in brass rims: a brass shield on the flap, brass rivets on the
-- inner panel's corners, a canteen on the left.
local function leatherRucksack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, FULL)
	local e = f.emblem
	slab(c, "Shield", CFrame.new(e + Vector3.new(0, 0.07, 0.01)), 0.44, 0.3, 0.05, 0.07, 0, col.Trim)
	diamond(c, "Shield", e + Vector3.new(0, -0.07, 0.01), 0.311, 0.05, col.Trim)
	slab(c, "ShieldInner", CFrame.new(e + Vector3.new(0, 0.07, 0.03)), 0.34, 0.22, 0.03, 0.05, 0, col.Flap)
	diamond(c, "ShieldInner", e + Vector3.new(0, -0.05, 0.03), 0.226, 0.03, col.Flap)
	ball(c, "ShieldBoss", e + Vector3.new(0, 0.02, 0.06), 0.12, col.Trim)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.1)), Vector3.new(0.4, 0.4, 0.1))
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			ball(
				c,
				"Rivet",
				(f.inner * CFrame.new(sx * (f.innerW / 2 - 0.09), sy * (f.innerH / 2 - 0.09), 0.02)).Position,
				0.08,
				col.Buckle
			)
		end
	end
	-- the canteen hanging on the left, above the side pouch
	local cx = -(f.w / 2 + 0.24)
	local cy = f.pouchTop + 0.3
	rod(c, "Canteen", Vector3.new(cx, cy, f.zc), 0.2, 0.48, rgb(70, 100, 76))
	rod(c, "CanteenRim", Vector3.new(cx, cy, f.zc), 0.22, 0.2, rgb(56, 80, 60))
	post(c, "CanteenNeck", Vector3.new(cx, cy + 0.28, f.zc), 0.1, 0.12, col.Trim)
	post(c, "CanteenCap", Vector3.new(cx, cy + 0.34, f.zc), 0.06, 0.16, col.Trim)
end

-- 4: olive canvas in copper rims: crossed pickaxes on a copper badge, a
-- lantern on the right, a rope coil on the left, a pickaxe across the top,
-- ore spilling out of the front pocket.
local function minersPack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, FULL)
	local e = f.emblem
	badge(c, "Badge", e, 0.62, 0.05, col.Trim)
	badge(c, "BadgeInner", e + Vector3.new(0, 0, 0.012), 0.5, 0.05, col.Panel)
	for _, s in { -1, 1 } do
		local handle = CFrame.new(e + Vector3.new(0, 0, 0.045)) * CFrame.Angles(0, 0, s * 0.78)
		block(c, "BadgePick", handle, Vector3.new(0.05, 0.4, 0.03), rgb(150, 100, 60))
		block(c, "BadgePickHead", handle * CFrame.new(0, 0.17, 0.005), Vector3.new(0.22, 0.06, 0.03), rgb(190, 196, 206))
	end
	-- the lantern hangs on a hook on the right
	local lx = f.w / 2 + 0.26
	local ly = f.pouchTop + 0.42
	local iron = rgb(58, 60, 72)
	block(c, "LanternHook", at(f.w / 2 + 0.08, ly + 0.3, f.zc), Vector3.new(0.22, 0.05, 0.05), iron)
	post(c, "LanternCap", Vector3.new(lx, ly + 0.19, f.zc), 0.07, 0.32, iron)
	post(c, "LanternTop", Vector3.new(lx, ly + 0.27, f.zc), 0.1, 0.18, col.Buckle)
	block(c, "LanternGlass", at(lx, ly, f.zc), Vector3.new(0.22, 0.3, 0.22), glow(col.Glow), NEON)
	for _, s in { -1, 1 } do
		block(c, "LanternBar", at(lx + s * 0.12, ly, f.zc + 0.12), Vector3.new(0.03, 0.3, 0.03), iron)
	end
	post(c, "LanternBase", Vector3.new(lx, ly - 0.18, f.zc), 0.07, 0.32, iron)
	fxBox(c, "Lantern", at(lx, ly, f.zc), Vector3.new(0.3, 0.36, 0.3))
	moveFx(c, "Light", at(lx + 0.6, ly, f.zc + 0.7))
	-- the rope coil on the left
	local rope = rgb(198, 160, 106)
	local rx = -(f.w / 2 + 0.14)
	local ry = f.pouchTop + 0.36
	rod(c, "RopeCoil", Vector3.new(rx, ry, f.zc), 0.18, 0.62, rope)
	rod(c, "RopeTurn", Vector3.new(rx - 0.02, ry, f.zc), 0.19, 0.44, rope:Lerp(BLACK, 0.15))
	rod(c, "RopeHole", Vector3.new(rx - 0.03, ry, f.zc), 0.2, 0.24, rope:Lerp(BLACK, 0.4))
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
	local oreY = f.pocketY + f.pocketH / 2 + 0.04
	local oreZ = f.zf + 0.12
	block(c, "Ore", at(-0.2, oreY, oreZ) * CFrame.Angles(0.4, 0.3, 0.5), Vector3.new(0.22, 0.2, 0.2), rgb(214, 124, 64))
	block(
		c,
		"Ore",
		at(0.05, oreY + 0.06, oreZ) * CFrame.Angles(0.2, 0.7, 0.2),
		Vector3.new(0.18, 0.26, 0.18),
		glow(rgb(60, 220, 200)),
		NEON
	)
	block(c, "Ore", at(0.24, oreY, oreZ) * CFrame.Angles(0.6, 0.2, -0.4), Vector3.new(0.2, 0.18, 0.2), rgb(240, 192, 64))
	fxBox(c, "Ore", at(0.02, oreY + 0.05, oreZ), Vector3.new(0.6, 0.3, 0.3))
end

-- 5: slate leather in steel rims: a riveted steel plate, a chained blue gem
-- in a steel diamond, blue crystals in the side pouches.
local function ironboundPack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, FULL)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			ball(
				c,
				"Rivet",
				(f.inner * CFrame.new(sx * (f.innerW / 2 - 0.09), sy * (f.innerH / 2 - 0.09), 0.02)).Position,
				0.09,
				col.Buckle
			)
		end
	end
	local e = f.emblem
	diamond(c, "ClaspPlate", e, 0.52, 0.06, col.Trim)
	diamond(c, "ClaspRim", e + Vector3.new(0, 0, 0.02), 0.42, 0.05, col.Flap)
	cutGem(c, e + Vector3.new(0, 0, 0.06), 0.3, glow(col.Gem), glow(col.Glow))
	for i = 1, 3 do
		local turn = if i % 2 == 0 then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity
		block(c, "Chain", CFrame.new(e + Vector3.new(0, -0.34 - (i - 1) * 0.1, 0.03)) * turn, Vector3.new(0.07, 0.12, 0.03), col.Buckle)
	end
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.12)), Vector3.new(0.5, 0.5, 0.15))
	local gem, tip = glow(col.Gem), glow(col.Glow)
	for i, s in { -1, 1 } do
		local top = (f.pouches[i] * CFrame.new(0, f.pouchH / 2 - 0.04, 0)).Position
		crystal(c, CFrame.new(top + Vector3.new(0, 0, -0.08)) * CFrame.Angles(0, 0, -s * 0.25), 0.42, 0.13, gem, tip)
		crystal(c, CFrame.new(top + Vector3.new(0, 0, 0.1)) * CFrame.Angles(0.2, 0, -s * 0.5), 0.3, 0.1, gem, tip)
	end
end

-- 6: forest green in brass rims: a big compass with a glowing needle, a map
-- tube on the left, a spyglass on the right, a red plume, a red bedroll.
local function explorersPack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, FULL)
	local e = f.emblem
	badge(c, "Compass", e, 0.68, 0.06, col.Trim)
	badge(c, "CompassRing", e + Vector3.new(0, 0, 0.012), 0.58, 0.06, col.Trim:Lerp(BLACK, 0.3))
	badge(c, "CompassFace", e + Vector3.new(0, 0, 0.022), 0.5, 0.06, rgb(226, 214, 184))
	for i = 0, 3 do
		local a = i * math.pi / 2
		block(
			c,
			"CompassMark",
			at(e.X + math.sin(a) * 0.19, e.Y + math.cos(a) * 0.19, e.Z + 0.06),
			Vector3.new(0.035, 0.035, 0.02),
			col.Panel
		)
	end
	local needle = CFrame.new(e + Vector3.new(0, 0, 0.065)) * CFrame.Angles(0, 0, -0.5)
	block(c, "Needle", needle * CFrame.new(0, 0.09, 0), Vector3.new(0.06, 0.19, 0.03), glow(col.Glow), NEON)
	block(c, "Needle", needle * CFrame.new(0, -0.09, 0), Vector3.new(0.06, 0.19, 0.03), rgb(200, 60, 50))
	ball(c, "CompassPin", e + Vector3.new(0, 0, 0.08), 0.08, col.Trim)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.12)), Vector3.new(0.6, 0.6, 0.15))
	-- the map tube on the left
	local tx = -(f.w / 2 + 0.4)
	local len = f.h * 0.7
	local ty = f.bottom + 0.22 + len / 2
	post(c, "MapTube", Vector3.new(tx, ty, f.zc + 0.05), len, 0.32, rgb(226, 206, 160))
	for _, s in { -1, 1 } do
		post(c, "TubeCap", Vector3.new(tx, ty + s * (len / 2 - 0.03), f.zc + 0.05), 0.12, 0.36, col.Trim)
	end
	post(c, "TubeStrap", Vector3.new(tx, ty + 0.12, f.zc + 0.05), 0.09, 0.35, col.Leather)
	-- the spyglass on the right: three brass sections, a glass at the top
	local gx = f.w / 2 + 0.4
	local gy = f.bottom + 0.4
	post(c, "Spyglass", Vector3.new(gx, gy + 0.3, f.zc), 0.6, 0.26, col.Trim)
	post(c, "SpyglassGrip", Vector3.new(gx, gy + 0.3, f.zc), 0.3, 0.28, col.Leather)
	post(c, "Spyglass", Vector3.new(gx, gy + 0.78, f.zc), 0.36, 0.2, col.Trim)
	post(c, "Spyglass", Vector3.new(gx, gy + 1.08, f.zc), 0.26, 0.15, col.Trim:Lerp(BLACK, 0.15))
	post(c, "SpyglassLens", Vector3.new(gx, gy + 1.22, f.zc), 0.03, 0.13, glow(rgb(120, 200, 255)), NEON)
	-- a red plume tucked behind the right bedroll strap
	local plume = at(f.w * 0.28, f.rollY + 0.1, f.zc - 0.12) * CFrame.Angles(0, 0, -0.45)
	block(c, "Plume", plume * CFrame.new(0, 0.38, 0), Vector3.new(0.16, 0.8, 0.05), rgb(212, 58, 46))
	block(c, "PlumeTip", plume * CFrame.new(0, 0.74, 0.01), Vector3.new(0.12, 0.2, 0.05), rgb(250, 240, 220))
end

-- 7: purple in silver rims: a lavender panel with silver filigree and violet
-- runes, an amethyst cluster in a silver ring, crystals out of the top and
-- the side pouches.
local function amethystPack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, FULL)
	local gem = col.Gem -- shaded violet bodies (Foil: a glassy shine), glowing lavender tips
	local light = glow(rgb(170, 140, 255))
	local runeColor = glow(col.Glow)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local corner = f.inner * CFrame.new(sx * (f.innerW / 2 - 0.09), sy * (f.innerH / 2 - 0.09), 0.015)
			diamond(c, "Filigree", corner.Position, 0.13, 0.03, col.Trim)
		end
		local runes = f.inner * CFrame.new(sx * (f.innerW / 2 - 0.12), f.innerH / 2 - 0.3, 0.02)
		glyphColumn(c, runes, 3, 0.18, 0.12, runeColor, if sx < 0 then 1 else 3)
	end
	local e = f.emblem
	badge(c, "Ring", e, 0.74, 0.06, col.Trim)
	badge(c, "RingInner", e + Vector3.new(0, 0, 0.012), 0.6, 0.06, col.Flap:Lerp(BLACK, 0.3))
	local base = CFrame.new(e + Vector3.new(0, -0.16, 0.07))
	crystal(c, base * CFrame.Angles(0.12, 0, 0), 0.62, 0.22, gem, light, FOIL)
	crystal(c, base * CFrame.new(-0.12, 0, 0) * CFrame.Angles(0.12, 0, 0.55), 0.42, 0.16, gem, light, FOIL)
	crystal(c, base * CFrame.new(0.12, 0, 0) * CFrame.Angles(0.12, 0, -0.6), 0.38, 0.15, gem, light, FOIL)
	fxBox(c, "Crystals", CFrame.new(e + Vector3.new(0, 0.2, 0.2)), Vector3.new(0.7, 0.6, 0.3))
	-- crystals out of the top, behind the bedroll
	local topBase = at(0, f.top + 0.12, GAP + 0.22)
	crystal(c, topBase * CFrame.new(-0.35, 0, 0) * CFrame.Angles(-0.15, 0, 0.3), 0.9, 0.24, gem, light, FOIL)
	crystal(c, topBase * CFrame.new(-0.1, 0, 0) * CFrame.Angles(-0.1, 0, 0.05), 1.2, 0.3, gem, light, FOIL)
	crystal(c, topBase * CFrame.new(0.22, 0, 0) * CFrame.Angles(-0.15, 0, -0.35), 0.8, 0.22, gem, light, FOIL)
	fxBox(c, "TopCrystals", at(0, f.top + 0.8, GAP + 0.25), Vector3.new(0.9, 0.9, 0.4))
	-- crystals in the side pouches
	for i, s in { -1, 1 } do
		local top = (f.pouches[i] * CFrame.new(0, f.pouchH / 2 - 0.04, 0)).Position
		crystal(c, CFrame.new(top + Vector3.new(0, 0, -0.06)) * CFrame.Angles(0, 0, -s * 0.3), 0.48, 0.14, gem, light, FOIL)
		crystal(c, CFrame.new(top + Vector3.new(0, 0, 0.12)) * CFrame.Angles(0.25, 0, -s * 0.55), 0.32, 0.11, gem, light, FOIL)
	end
end

-- 8: the owner's reference: royal blue in gold rims, a navy panel with star
-- dots and rune columns, a gold rune ring with a four-point star and a cut
-- crystal, a clasp tab, a crystal on the pocket, runes and crystals on the pouches.
local function runeboundPack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, FULL)
	local gold = col.Trim
	local runeColor = glow(col.Glow)
	local gemRim, gemCore = glow(col.Gem:Lerp(col.Glow, 0.5)), glow(col.Gem)
	local dots = {
		{ -0.27, 0.36, 0.05 },
		{ -0.08, 0.42, 0.04 },
		{ 0.17, 0.38, 0.05 },
		{ 0.3, 0.14, 0.04 },
		{ -0.3, -0.06, 0.04 },
		{ 0.26, -0.33, 0.05 },
		{ -0.22, -0.38, 0.04 },
	}
	for _, p in dots do
		ball(c, "Star", f.inner.Position + Vector3.new(p[1] * f.innerW, p[2] * f.innerH, 0.012), p[3], runeColor, NEON)
	end
	for _, s in { -1, 1 } do
		glyphColumn(c, at(s * (f.innerW / 2 - 0.11), f.flapTop - 0.36, f.ff + 0.03), 4, 0.18, 0.13, runeColor, if s < 0 then 1 else 3)
	end
	local e = f.emblem
	badge(c, "Ring", e, 0.8, 0.06, gold)
	badge(c, "RingInner", e + Vector3.new(0, 0, 0.012), 0.64, 0.06, col.Panel:Lerp(BLACK, 0.25))
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local tick = CFrame.new(e + Vector3.new(math.cos(a) * 0.255, math.sin(a) * 0.255, 0.05)) * CFrame.Angles(0, 0, a + math.pi / 2)
		block(c, "RingRune", tick, Vector3.new(0.09, 0.028, 0.03), runeColor, NEON)
	end
	block(c, "StarRay", CFrame.new(e + Vector3.new(0, 0, 0.04)), Vector3.new(0.5, 0.06, 0.03), gold)
	block(c, "StarRay", CFrame.new(e + Vector3.new(0, 0, 0.04)), Vector3.new(0.06, 0.5, 0.03), gold)
	diamond(c, "Setting", e + Vector3.new(0, 0, 0.05), 0.3, 0.05, gold)
	cutGem(c, e + Vector3.new(0, 0, 0.09), 0.22, gemRim, gemCore)
	local claspTop, claspBottom = e.Y - 0.4, f.flapBottom - 0.14
	block(c, "Clasp", at(0, (claspTop + claspBottom) / 2, f.ff + 0.015), Vector3.new(0.13, claspTop - claspBottom, 0.05), gold)
	ball(c, "ClaspStud", Vector3.new(0, claspBottom, f.ff + 0.02), 0.13, gold)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.15)), Vector3.new(0.7, 0.7, 0.15))
	fxBox(c, "Runes", at(0, f.flapTop - 0.2, f.ff + 0.15), Vector3.new(f.w, 0.6, 0.2))
	-- a crystal in a gold diamond on the pocket
	diamond(c, "PocketSetting", Vector3.new(0, f.pocketY, f.pf + 0.01), 0.28, 0.04, gold)
	cutGem(c, Vector3.new(0, f.pocketY, f.pf + 0.04), 0.17, gemRim, gemCore)
	-- runes down the pouches' outer faces, a crystal on each
	for i, s in { -1, 1 } do
		local pouch = f.pouches[i]
		glyphColumn(c, pouch * CFrame.new(0, 0.26, 0.125), 3, 0.21, 0.13, runeColor, if s < 0 then 2 else 4)
		local top = (pouch * CFrame.new(0, f.pouchH / 2, 0)).Position
		crystal(c, CFrame.new(top + Vector3.new(0, 0.02, f.d * 0.22)) * CFrame.Angles(0, 0, -s * 0.18), 0.34, 0.12, gemRim, gemCore)
	end
end

-- 9: obsidian in gold rims: lava cracks glowing in an obsidian panel, a fire
-- crystal in a gold ring, gold horns, a molten window in the pocket, lava
-- runes on the pouches, two chimneys behind the bedroll (fire and smoke: BackpackFx).
local function emberforgePack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, FULL)
	local lava = glow(col.Glow)
	local fire, hot = glow(rgb(255, 56, 12)), glow(rgb(255, 150, 40))
	-- glowing lava cracks zig-zagging down the obsidian panel, a branch off each
	local cracks = {
		{ { -0.45, 0.42 }, { -0.36, 0.18 }, { -0.42, -0.05 }, { -0.3, -0.28 }, { -0.37, -0.45 } },
		{ { 0.44, 0.45 }, { 0.34, 0.2 }, { 0.41, -0.02 }, { 0.28, -0.22 }, { 0.36, -0.44 } },
		{ { -0.36, 0.18 }, { -0.22, 0.27 } },
		{ { 0.41, -0.02 }, { 0.25, 0.05 } },
	}
	for _, crack in cracks do
		for i = 1, #crack - 1 do
			local a = (f.inner * CFrame.new(crack[i][1] * f.innerW, crack[i][2] * f.innerH, 0.015)).Position
			local b = (f.inner * CFrame.new(crack[i + 1][1] * f.innerW, crack[i + 1][2] * f.innerH, 0.015)).Position
			bar(c, "Lava", a, b, 0.05, 0.02, lava, NEON)
			if i > 1 then
				ball(c, "Lava", a, 0.055, lava, NEON) -- a round joint where the crack turns
			end
		end
	end
	local e = f.emblem
	badge(c, "Ring", e, 0.74, 0.06, col.Trim)
	badge(c, "RingInner", e + Vector3.new(0, 0, 0.012), 0.6, 0.06, col.Flap:Lerp(BLACK, 0.4))
	local base = CFrame.new(e + Vector3.new(0, -0.16, 0.07))
	crystal(c, base * CFrame.Angles(0.15, 0, 0), 0.62, 0.22, fire, hot)
	crystal(c, base * CFrame.new(-0.12, 0, 0) * CFrame.Angles(0.15, 0, 0.6), 0.42, 0.16, fire, hot)
	crystal(c, base * CFrame.new(0.12, 0, 0) * CFrame.Angles(0.15, 0, -0.55), 0.38, 0.15, fire, hot)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0.2, 0.2)), Vector3.new(0.7, 0.6, 0.25))
	-- the molten window in the pocket, behind gold grill bars
	block(c, "Molten", at(0, f.pocketY, f.pf + 0.005), Vector3.new(f.pocketW * 0.5, f.pocketH * 0.42, 0.02), lava, NEON)
	for i = -1, 1 do
		block(c, "Grill", at(i * f.pocketW * 0.12, f.pocketY, f.pf + 0.02), Vector3.new(0.04, f.pocketH * 0.48, 0.03), col.Trim)
	end
	for i, s in { -1, 1 } do
		glyphColumn(c, f.pouches[i] * CFrame.new(0, 0.26, 0.125), 3, 0.21, 0.13, lava, if s < 0 then 2 else 4)
	end
	-- gold horns on the top corners
	for _, s in { -1, 1 } do
		local hornBase = at(s * (f.w / 2 - 0.12), f.top + 0.08, f.zc) * CFrame.Angles(0, 0, -s * 0.5)
		block(c, "Horn", hornBase * CFrame.new(0, 0.12, 0), Vector3.new(0.2, 0.26, 0.2), col.Trim)
		local tipTurn = CFrame.Angles(0, if s < 0 then 0 else math.pi, 0)
		part(c, "HornTip", "Wedge", hornBase * CFrame.new(0, 0.38, 0) * tipTurn, Vector3.new(0.2, 0.26, 0.2), col.Trim)
	end
	-- two chimneys behind the bedroll
	local iron = rgb(46, 44, 50)
	for _, s in { -1, 1 } do
		local cx = s * (f.w / 2 - 0.3)
		local cz = GAP + 0.17
		local y0 = f.top + 0.1
		local y1 = f.rollY + f.rollD / 2 + 0.22
		post(c, "Chimney", Vector3.new(cx, (y0 + y1) / 2, cz), y1 - y0, 0.26, iron)
		post(c, "ChimneyBand", Vector3.new(cx, y1 - 0.2, cz), 0.06, 0.29, col.Trim)
		post(c, "ChimneyRim", Vector3.new(cx, y1, cz), 0.08, 0.33, col.Trim)
		post(c, "Ember", Vector3.new(cx, y1 + 0.03, cz), 0.04, 0.22, lava, NEON)
		fxBox(c, if s < 0 then "ChimneyLeft" else "ChimneyRight", at(cx, y1 + 0.2, cz), Vector3.new(0.24, 0.3, 0.24))
	end
	fxBox(c, "Aura", at(0, (f.top + f.bottom) / 2, f.zc), Vector3.new(f.w + 0.4, f.h, f.d + 0.4))
end

-- 10: pearl in gold rims: a glowing galaxy panel with twinkles, a star
-- crystal on gold rays in a gold ring, a galaxy window in the pocket, star
-- runes on the pouches, three star shards over the bedroll, two feathered wings.
local function starforgePack(c: Ctx)
	local f = c.f
	local col = c.colors
	anatomy(c, { Inner = true, InnerMaterial = NEON, Pocket = true, SidePouches = true, Roll = true })
	local star = glow(col.Gem)
	local violet = glow(col.Glow)
	local gold = col.Trim
	local sparkle = WHITE:Lerp(violet, 0.25)
	for _, p in { { -0.34, 0.3, 0.16 }, { 0.36, 0.06, 0.12 }, { 0.12, 0.38, 0.1 }, { -0.16, -0.3, 0.09 }, { 0.3, -0.34, 0.1 } } do
		twinkle(c, (f.inner * CFrame.new(p[1] * f.innerW, p[2] * f.innerH, 0.02)).Position, p[3], sparkle)
	end
	local e = f.emblem
	badge(c, "Ring", e, 0.8, 0.06, gold)
	badge(c, "RingInner", e + Vector3.new(0, 0, 0.012), 0.66, 0.06, col.Panel:Lerp(BLACK, 0.35))
	for _, turn in { CFrame.identity, DIAMOND } do
		local long = if turn == DIAMOND then 0.5 else 0.66
		block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.04)) * turn, Vector3.new(long, 0.06, 0.03), gold)
		block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.04)) * turn, Vector3.new(0.06, long, 0.03), gold)
	end
	cutGem(c, e + Vector3.new(0, 0, 0.08), 0.26, glow(col.Gem:Lerp(col.Glow, 0.5)), star)
	fxBox(c, "Gem", CFrame.new(e + Vector3.new(0, 0, 0.15)), Vector3.new(0.8, 0.8, 0.15))
	-- the galaxy window in the pocket
	block(c, "Galaxy", at(0, f.pocketY, f.pf + 0.005), Vector3.new(f.pocketW * 0.56, f.pocketH * 0.5, 0.02), col.Panel, NEON)
	twinkle(c, Vector3.new(-f.pocketW * 0.1, f.pocketY + 0.04, f.pf + 0.02), 0.11, sparkle)
	for i, s in { -1, 1 } do
		glyphColumn(c, f.pouches[i] * CFrame.new(0, 0.26, 0.125), 3, 0.21, 0.13, violet, if s < 0 then 3 else 1)
	end
	-- three star shards over the bedroll's ends (clear of the wearer's head)
	for i, spec in { { -0.9, 0.3, 0.5 }, { 0.92, 0.5, -0.1 }, { -0.7, 0.78, 0.3 } } do
		local shardAt = Vector3.new(spec[1] * f.w / 2, f.rollY + f.rollD / 2 + spec[2], f.zc + spec[3] * 0.3)
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
		local armCf = CFrame.new(rootAt + arm * (armLength / 2)) * CFrame.Angles(0, 0, s * armAngle)
		block(c, "WingArm", armCf, Vector3.new(armLength, 0.14, 0.14), gold)
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
		size = pack.Size,
		f = layout(pack.Size),
		display = display == true,
		gemAt = nil,
		topAt = nil,
	}
	builder(c)
	attach(c, "Gem", c.gemAt or c.f.emblem + Vector3.new(0, 0, 0.12))
	attach(c, "Top", c.topAt or Vector3.new(0, c.f.rollY + c.f.rollD / 2 + 0.2, c.f.zc))
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
