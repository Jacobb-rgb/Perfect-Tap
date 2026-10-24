--[[
	Builds the ten backpacks (BackpackData) from parts only (no meshes), in the
	chunky low-poly look of the owner's reference (a royal blue rune pack with
	gold trim, a glowing crystal on the flap, a bedroll on top, a front pocket
	with two strapped buckles and side pockets). Worst to best:

	  BurlapSack       a round tan sack, rope-tied neck, ruffled top, a patch   9 parts
	  CanvasPack       canvas bag, leather flap, one strap, a tin mug          ~13
	  LeatherRucksack  the full anatomy in brown leather, brass buckles,
	                   a green bedroll                                         ~32
	  MinersPack       + copper rivets, a lantern and a rope coil              ~44
	  IronboundPack    + iron trim and corners, a blue gem clasp               ~47
	  ExplorersPack    brass trim, a red bedroll, a map tube, a compass        ~48
	  AmethystPack     silver trim, a glowing amethyst cluster, violet runes   ~55
	  RuneboundPack    the reference: gold trim, a rune ring with a star
	                   crystal, glowing runes on the flap and side pockets     ~66
	  EmberforgePack   obsidian with lava seams, a fire crystal, two ember
	                   chimneys                                                ~68
	  StarforgePack    pearl and gold, galaxy panels, a star crystal, a
	                   few floating star shards and two wings                  ~80
	Budget: BackpackBuilder.MaxParts (tests).

	Contract: a Model named after the pack id, PrimaryPart "Root" (an invisible
	part) at the wearer's BACK: the middle of UpperTorso's back face. +Z points
	away from the back (the side the camera sees from behind the player), +Y
	up, X across. The bag hangs from TOP (just above the shoulders) down past
	the waist. Attachments on Root: "Gem" (the flap's emblem, for sparkles)
	and "Top" (above the bedroll). Model attributes: BackpackId, BottomY / TopY
	(the lowest / highest point above Root, for stands and shop pedestals).
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
BackpackBuilder.MaxParts = 80

local TOP = BackpackBuilder.Top
local GAP = BackpackBuilder.Gap

local rgb = Color3.fromRGB
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local FABRIC = Enum.Material.Fabric

local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- Roblox cylinders run along X
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local DIAMOND = CFrame.Angles(0, 0, math.pi / 4) -- a square turned into a diamond (facing Z)

type Kind = "Block" | "Wedge" | "Cylinder" | "Ball"

-- The standard anatomy's frame (every pack after the sack).
type Frame = {
	w: number,
	h: number,
	d: number,
	top: number,
	bottom: number,
	zc: number, -- the body's middle (Z)
	zf: number, -- the body's outer face (Z)
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
}

-- What the standard anatomy builds (per pack, see STYLES).
type Style = {
	Material: Enum.Material, -- the bag body
	Tongue: boolean, -- a round tab under the flap (where the emblem sits)
	FlapStraps: number, -- 1 = one middle strap, 2 = two
	PocketStraps: boolean, -- two straps with buckles on the front pocket
	PocketWidth: number, -- of the body width
	SidePockets: boolean,
	Roll: boolean, -- the bedroll on top
	Trim: boolean, -- edge strips (Trim colour)
	Corners: boolean, -- iron corner caps
	Insets: boolean, -- buckles get a dark middle
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

-- A cylinder along X (bedroll, coils seen from the side) centered on `position`.
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

-- A disc facing +Z (emblems, compasses) centered on `position`.
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

-- A flat diamond facing +Z (gems, clasps).
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

-- A buckle facing +Z: a metal frame, with a dark middle when `inset`.
local function buckle(c: Ctx, position: Vector3, w: number, h: number, inset: boolean)
	block(c, "Buckle", CFrame.new(position), Vector3.new(w, h, 0.05), c.colors.Buckle, METAL)
	if inset then
		block(c, "BuckleHole", CFrame.new(position + Vector3.new(0, 0, 0.012)), Vector3.new(w * 0.5, h * 0.42, 0.05), c.colors.Leather)
	end
end

--[[
	A faceted crystal growing from `base` along its +Y: a diamond-section
	body and a two-tone pointed tip (two wedges), both glowing. 3 parts.
]]
local function crystal(c: Ctx, base: CFrame, height: number, width: number, body: Color3, tip: Color3)
	local bodyH = height * 0.7
	local tipH = height - bodyH
	local turned = base * CFrame.Angles(0, math.pi / 4, 0)
	block(c, "Crystal", turned * CFrame.new(0, bodyH / 2, 0), Vector3.new(width, bodyH, width), body, NEON)
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

-- A four-point light star (two crossed Neon bars) facing +Z.
local function twinkle(c: Ctx, position: Vector3, size: number, color: Color3)
	block(c, "Twinkle", CFrame.new(position), Vector3.new(size, size * 0.16, 0.03), color, NEON)
	block(c, "Twinkle", CFrame.new(position), Vector3.new(size * 0.16, size, 0.03), color, NEON)
end

local function attach(c: Ctx, name: string, position: Vector3)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = CFrame.new(position)
	a.Parent = c.root
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
	local pocketTop = pocketBottom + h * 0.3
	local rollD = math.min(0.64, d * 0.62)
	return {
		w = w,
		h = h,
		d = d,
		top = top,
		bottom = bottom,
		zc = zc,
		zf = zf,
		flapH = flapH,
		flapBottom = flapBottom,
		pocketW = w * style.PocketWidth,
		pocketBottom = pocketBottom,
		pocketTop = pocketTop,
		sideTop = bottom + 0.2 + h * 0.42,
		rollD = rollD,
		rollY = top + 0.14 + rollD / 2,
		rollZ = zc + 0.02,
		emblem = Vector3.new(0, flapBottom, zf + 0.14),
	}
end

local function standard(c: Ctx, style: Style)
	local f = c.f
	local col = c.colors
	local w, h, d = f.w, f.h, f.d
	local midY = (f.top + f.bottom) / 2

	-- the bag (round front edges: gold posts on trimmed packs), its leather
	-- bottom and the flap over the top (a rounded edge where it folds)
	local r = 0.13
	local body = block(c, "Body", at(0, midY, f.zc - r / 2), Vector3.new(w, h, d - r), col.Body, style.Material)
	body.CastShadow = true
	block(c, "Body", at(0, midY, f.zf - r / 2), Vector3.new(w - 2 * r, h, r), col.Body, style.Material)
	for _, s in { -1, 1 } do
		if style.Trim then
			post(c, "Trim", Vector3.new(s * (w / 2 - r), midY - 0.04, f.zf - r), h - 0.16, 2 * r + 0.04, col.Trim, METAL)
		else
			post(c, "Body", Vector3.new(s * (w / 2 - r), midY, f.zf - r), h, 2 * r, col.Body, style.Material)
		end
	end
	block(c, "Base", at(0, f.bottom + 0.09, f.zc), Vector3.new(w + 0.08, 0.22, d + 0.08), col.Leather)
	block(c, "FlapTop", at(0, f.top + 0.07, (GAP + f.zf) / 2), Vector3.new(w + 0.08, 0.14, d), col.Flap)
	block(c, "Flap", at(0, f.top - f.flapH / 2, f.zf + 0.07), Vector3.new(w + 0.08, f.flapH, 0.14), col.Flap)
	rod(c, "FlapFold", Vector3.new(0, f.top, f.zf), w + 0.08, 0.28, col.Flap)
	if style.Tongue then
		badge(c, "FlapTongue", Vector3.new(0, f.flapBottom, f.zf + 0.07), math.min(0.62, w * 0.3), 0.14, col.Flap)
	end

	-- straps from the flap down to the front pocket, a buckle under the flap
	local strapXs: { number } = if style.FlapStraps >= 2 then { -w * 0.27, w * 0.27 } else { 0 }
	local strapTop = f.top - 0.05
	local strapEnd = f.pocketTop + 0.05
	for _, x in strapXs do
		block(c, "Strap", at(x, (strapTop + strapEnd) / 2, f.zf + 0.155), Vector3.new(0.15, strapTop - strapEnd, 0.03), col.Leather)
		buckle(c, Vector3.new(x, f.flapBottom - 0.13, f.zf + 0.18), 0.25, 0.21, style.Insets)
	end

	-- the front pocket with its flap
	local pw = f.pocketW
	local ph = f.pocketTop - f.pocketBottom
	block(c, "Pocket", at(0, (f.pocketBottom + f.pocketTop) / 2, f.zf + 0.15), Vector3.new(pw, ph, 0.3), col.Body, style.Material)
	block(c, "PocketFlap", at(0, f.pocketTop - 0.07, f.zf + 0.17), Vector3.new(pw + 0.06, 0.2, 0.36), col.Flap)
	if style.PocketStraps then
		for _, x in { -pw * 0.3, pw * 0.3 } do
			local y0, y1 = f.pocketBottom + 0.04, f.pocketTop - 0.12
			block(c, "PocketStrap", at(x, (y0 + y1) / 2, f.zf + 0.315), Vector3.new(0.13, y1 - y0, 0.03), col.Leather)
			buckle(c, Vector3.new(x, f.pocketBottom + ph * 0.4, f.zf + 0.335), 0.21, 0.18, style.Insets)
		end
	end

	-- side pockets
	if style.SidePockets then
		local sh = f.sideTop - (f.bottom + 0.2)
		for _, s in { -1, 1 } do
			local x = s * (w / 2 + 0.11)
			block(c, "SidePocket", at(x, f.bottom + 0.2 + sh / 2, f.zc + 0.03), Vector3.new(0.22, sh, d * 0.7), col.Body, style.Material)
			block(c, "SideFlap", at(s * (w / 2 + 0.13), f.sideTop - 0.05, f.zc + 0.03), Vector3.new(0.26, 0.15, d * 0.74), col.Flap)
		end
	end

	-- the bedroll on top: two leather straps with buckles, spiral ends
	if style.Roll then
		local rollAt = Vector3.new(0, f.rollY, f.rollZ)
		local len = w * 0.96
		rod(c, "Bedroll", rollAt, len, f.rollD, col.Roll, FABRIC)
		for _, s in { -1, 1 } do
			rod(c, "BedrollEnd", rollAt + Vector3.new(s * len / 2, 0, 0), 0.04, f.rollD * 0.62, col.Roll:Lerp(BLACK, 0.25), FABRIC)
			local sx = s * w * 0.27
			rod(c, "BedrollStrap", Vector3.new(sx, f.rollY, f.rollZ), 0.13, f.rollD + 0.05, col.Leather)
			block(c, "BedrollBuckle", at(sx, f.rollY, f.rollZ + f.rollD / 2 + 0.03), Vector3.new(0.17, 0.15, 0.04), col.Buckle, METAL)
		end
	end

	-- trim: the flap's edges, the bag's outer corners, the pocket flap's lip
	if style.Trim then
		local z = f.zf + 0.155
		block(c, "Trim", at(0, f.flapBottom + 0.035, z), Vector3.new(w + 0.12, 0.08, 0.05), col.Trim, METAL)
		for _, s in { -1, 1 } do
			block(c, "Trim", at(s * (w / 2 + 0.03), f.top - f.flapH / 2, z), Vector3.new(0.07, f.flapH, 0.05), col.Trim, METAL)
		end
		block(c, "Trim", at(0, f.pocketTop - 0.155, f.zf + 0.355), Vector3.new(pw + 0.08, 0.06, 0.04), col.Trim, METAL)
	end

	-- iron corner caps
	if style.Corners then
		for _, s in { -1, 1 } do
			block(c, "Corner", at(s * (w / 2 + 0.01), f.bottom + 0.14, f.zf), Vector3.new(0.24, 0.24, 0.24), col.Buckle, METAL)
			block(c, "Corner", at(s * (w / 2 + 0.04), f.flapBottom + 0.07, f.zf + 0.155), Vector3.new(0.18, 0.18, 0.07), col.Buckle, METAL)
		end
	end
end

local function style(overrides: { [string]: any }): Style
	local s: Style = {
		Material = Enum.Material.SmoothPlastic,
		Tongue = true,
		FlapStraps = 2,
		PocketStraps = true,
		PocketWidth = 0.78,
		SidePockets = true,
		Roll = true,
		Trim = false,
		Corners = false,
		Insets = false,
	}
	local open: any = s
	for key, value in overrides do
		open[key] = value
	end
	return s
end

-- Glyphs in a column (top to bottom) on a face: +Z when sideX is nil.
local function runeColumn(c: Ctx, from: Vector3, step: number, kinds: { number }, scale: number, color: Color3, sideX: number?)
	for i, kind in kinds do
		rune(c, from - Vector3.new(0, (i - 1) * step, 0), kind, scale, color, sideX)
	end
end

---------------------------------------------------------------- the packs

local STYLES: { [string]: Style } = {
	CanvasPack = style({
		Material = FABRIC,
		FlapStraps = 1,
		PocketStraps = false,
		PocketWidth = 0.6,
		SidePockets = false,
		Roll = false,
	}),
	LeatherRucksack = style({}),
	MinersPack = style({ Material = FABRIC }),
	IronboundPack = style({ Trim = true, Corners = true, Insets = true }),
	ExplorersPack = style({ Material = FABRIC, Trim = true, Insets = true }),
	AmethystPack = style({ Trim = true, Insets = true }),
	RuneboundPack = style({ Trim = true, Insets = true }),
	EmberforgePack = style({ Trim = true, Insets = true, Corners = true }),
	StarforgePack = style({ Trim = true, Insets = true }),
}

-- 1: a round tan sack with a tied neck, a ruffled top of four flaps and a sewn-on patch.
local function burlapSack(c: Ctx, size: Vector3)
	local col = c.colors
	local d = size.X
	local cy = TOP - 0.25 - d / 2
	local zc = GAP + d / 2 - 0.05
	local sack = ball(c, "Body", Vector3.new(0, cy, zc), d, col.Body, FABRIC)
	sack.CastShadow = true
	local neckY = cy + d / 2 + 0.06
	post(c, "Neck", Vector3.new(0, neckY, zc), 0.36, 0.5, col.Panel, FABRIC)
	post(c, "Rope", Vector3.new(0, neckY + 0.04, zc), 0.1, 0.6, col.Leather)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local petal = CFrame.new(0, neckY + 0.2, zc) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.1, -0.17) * CFrame.Angles(-0.5, 0, 0)
		block(c, "Tuft", petal, Vector3.new(0.3, 0.32, 0.1), if i % 2 == 0 then col.Body else col.Flap, FABRIC)
	end
	-- a patch sewn on the front, a stitch across it
	local spot = Vector3.new(0.24, cy - 0.12, 0)
	local normal = Vector3.new(spot.X, spot.Y - cy, math.sqrt(math.max(0, (d / 2) ^ 2 - spot.X ^ 2 - (spot.Y - cy) ^ 2)))
	local onSack = Vector3.new(spot.X, spot.Y, zc + normal.Z)
	local face = CFrame.lookAt(onSack, onSack - normal) * CFrame.Angles(0, 0, 0.12)
	block(c, "Patch", face, Vector3.new(0.36, 0.34, 0.06), col.Flap, FABRIC)
	block(c, "Stitch", face * CFrame.new(0, 0, -0.035), Vector3.new(0.3, 0.03, 0.02), col.Leather)
	attach(c, "Gem", onSack)
	attach(c, "Top", Vector3.new(0, neckY + 0.5, zc))
end

-- 2: canvas with a leather flap, one middle strap and an iron buckle, a tin mug on the side.
local function canvasPack(c: Ctx)
	local f = c.f
	standard(c, STYLES.CanvasPack)
	local x = f.w / 2 + 0.17
	local y = f.bottom + 0.62
	post(c, "Mug", Vector3.new(x, y, f.zc), 0.34, 0.32, rgb(168, 174, 182), METAL)
	post(c, "MugRim", Vector3.new(x, y + 0.17, f.zc), 0.04, 0.34, rgb(120, 126, 134), METAL)
	block(c, "MugHandle", at(x + 0.19, y, f.zc), Vector3.new(0.06, 0.18, 0.05), rgb(120, 126, 134), METAL)
	block(c, "MugHook", at(f.w / 2 + 0.04, y + 0.14, f.zc), Vector3.new(0.12, 0.05, 0.05), c.colors.Leather)
end

-- 3: brown leather, brass buckles, a green bedroll and a brass clasp on the tongue.
local function leatherRucksack(c: Ctx)
	standard(c, STYLES.LeatherRucksack)
	block(c, "Clasp", CFrame.new(c.f.emblem), Vector3.new(0.2, 0.16, 0.05), c.colors.Buckle, METAL)
end

-- 4: olive canvas and leather, copper rivets, a lantern on the right, a rope coil on the left.
local function minersPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.MinersPack)
	diamond(c, "Clasp", f.emblem, 0.2, 0.05, col.Buckle, METAL)
	for _, s in { -1, 1 } do
		ball(c, "Rivet", Vector3.new(s * (f.w / 2 - 0.08), f.flapBottom + 0.1, f.zf + 0.15), 0.09, col.Buckle, METAL)
		ball(c, "Rivet", Vector3.new(s * (f.w / 2 - 0.08), f.top - 0.1, f.zf + 0.15), 0.09, col.Buckle, METAL)
		ball(c, "Rivet", Vector3.new(s * (f.pocketW / 2 - 0.06), f.pocketTop - 0.07, f.zf + 0.36), 0.08, col.Buckle, METAL)
	end
	-- the lantern hangs on a hook above the right side pocket
	local lx = f.w / 2 + 0.24
	local ly = f.top - 0.42
	local iron = rgb(58, 60, 72)
	block(c, "LanternHook", at(f.w / 2 + 0.06, ly + 0.27, f.zc), Vector3.new(0.2, 0.05, 0.05), iron, METAL)
	post(c, "LanternCap", Vector3.new(lx, ly + 0.19, f.zc), 0.07, 0.3, iron, METAL)
	post(c, "LanternTop", Vector3.new(lx, ly + 0.26, f.zc), 0.08, 0.16, iron, METAL)
	block(c, "LanternGlass", at(lx, ly, f.zc), Vector3.new(0.21, 0.3, 0.21), glow(col.Glow), NEON)
	post(c, "LanternBase", Vector3.new(lx, ly - 0.18, f.zc), 0.07, 0.3, iron, METAL)
	-- the rope coil on the left
	local rope = rgb(196, 158, 104)
	rod(c, "RopeCoil", Vector3.new(-(f.w / 2 + 0.12), f.top - 0.4, f.zc), 0.18, 0.62, rope, FABRIC)
	rod(c, "RopeHole", Vector3.new(-(f.w / 2 + 0.12), f.top - 0.4, f.zc), 0.2, 0.28, rope:Lerp(BLACK, 0.35), FABRIC)
	block(c, "RopeTie", at(-(f.w / 2 + 0.12), f.top - 0.12, f.zc), Vector3.new(0.21, 0.08, 0.12), col.Leather)
end

-- 5: slate leather in iron: trim, corner caps, rivets and a blue gem clasp.
local function ironboundPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.IronboundPack)
	diamond(c, "ClaspPlate", f.emblem + Vector3.new(0, 0, 0.01), 0.36, 0.06, col.Trim, METAL)
	diamond(c, "Gem", f.emblem + Vector3.new(0, 0, 0.04), 0.2, 0.08, glow(col.Glow), NEON)
	for i = -2, 2 do
		ball(c, "Rivet", Vector3.new(i * f.w * 0.2, f.flapBottom + 0.035, f.zf + 0.185), 0.07, col.Buckle, METAL)
	end
	for _, s in { -1, 1 } do
		diamond(
			c,
			"SideGem",
			Vector3.new(s * (f.w / 2 + 0.13), f.sideTop - 0.05, f.zc + 0.03 + f.d * 0.37),
			0.1,
			0.04,
			glow(col.Glow),
			NEON
		)
	end
end

-- 6: forest canvas, brass trim, a red bedroll, a map tube on the left, a compass on the tongue.
local function explorersPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.ExplorersPack)
	-- the compass: brass case, cream face, a glowing needle
	badge(c, "Compass", f.emblem + Vector3.new(0, 0, 0.02), 0.5, 0.08, col.Buckle, METAL)
	badge(c, "CompassFace", f.emblem + Vector3.new(0, 0, 0.03), 0.38, 0.08, rgb(246, 236, 210))
	block(
		c,
		"Needle",
		at(f.emblem.X, f.emblem.Y, f.emblem.Z + 0.08) * CFrame.Angles(0, 0, -0.5),
		Vector3.new(0.05, 0.3, 0.03),
		glow(col.Glow),
		NEON
	)
	ball(c, "CompassPin", f.emblem + Vector3.new(0, 0, 0.09), 0.07, col.Buckle, METAL)
	-- the map tube strapped to the left side
	local tx = -(f.w / 2 + 0.36)
	local len = f.h * 0.7
	local ty = f.bottom + 0.22 + len / 2
	post(c, "MapTube", Vector3.new(tx, ty, f.zc + 0.05), len, 0.32, rgb(226, 206, 160))
	for _, s in { -1, 1 } do
		post(c, "TubeCap", Vector3.new(tx, ty + s * (len / 2 - 0.02), f.zc + 0.05), 0.1, 0.36, col.Buckle, METAL)
	end
	post(c, "TubeStrap", Vector3.new(tx, ty + 0.12, f.zc + 0.05), 0.09, 0.35, col.Leather)
	block(c, "TubeStrap", at(tx + 0.21, ty + 0.12, f.zc + 0.05), Vector3.new(0.2, 0.09, 0.08), col.Leather)
end

-- 7: deep purple, silver trim, a glowing amethyst cluster on the tongue, violet runes on the sides.
local function amethystPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.AmethystPack)
	local gem = glow(rgb(96, 64, 255))
	local light = glow(rgb(160, 130, 255))
	badge(c, "Setting", f.emblem + Vector3.new(0, 0, 0.02), 0.5, 0.07, col.Trim, METAL)
	local base = CFrame.new(f.emblem + Vector3.new(0, -0.1, 0.07))
	crystal(c, base * CFrame.Angles(0.12, 0, 0), 0.74, 0.25, gem, light)
	crystal(c, base * CFrame.new(-0.14, 0, 0) * CFrame.Angles(0.12, 0, 0.55), 0.48, 0.18, gem, light)
	crystal(c, base * CFrame.new(0.14, 0, 0) * CFrame.Angles(0.12, 0, -0.6), 0.44, 0.17, gem, light)
	local runeColor = glow(col.Glow)
	for _, s in { -1, 1 } do
		runeColumn(c, Vector3.new(s * (f.w / 2 + 0.225), f.sideTop - 0.3, f.zc + 0.03), 0.2, { 3, 2, 1 }, 1, runeColor, s)
	end
end

-- 8: the owner's reference: royal blue, gold trim, a gold rune ring with a star crystal,
-- glowing runes down the flap and the side pockets, a diamond on the front pocket.
local function runeboundPack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.RuneboundPack)
	local runeColor = glow(col.Glow)
	-- the emblem: a gold ring, a navy middle, rune ticks and the crystal
	local e = f.emblem
	badge(c, "Ring", e + Vector3.new(0, 0, 0.02), 0.76, 0.06, col.Trim, METAL)
	badge(c, "RingInner", e + Vector3.new(0, 0, 0.03), 0.6, 0.06, col.Panel)
	for i = 0, 5 do
		local a = i * math.pi / 3 + math.pi / 6
		local p = e + Vector3.new(math.cos(a) * 0.235, math.sin(a) * 0.235, 0.07)
		block(c, "RingRune", CFrame.new(p) * CFrame.Angles(0, 0, a), Vector3.new(0.09, 0.035, 0.03), runeColor, NEON)
	end
	diamond(c, "ClaspPlate", e + Vector3.new(0, 0, 0.05), 0.3, 0.05, col.Buckle, METAL)
	diamond(c, "Crystal", e + Vector3.new(0, 0, 0.09), 0.22, 0.1, glow(col.Gem), NEON)
	-- rune columns down both sides of the flap
	for _, s in { -1, 1 } do
		runeColumn(
			c,
			Vector3.new(s * (f.w / 2 - 0.17), f.top - 0.14, f.zf + 0.145),
			0.2,
			if s < 0 then { 1, 3, 2 } else { 2, 3, 1 },
			1,
			runeColor
		)
	end
	-- the side pockets: rune columns on their outer faces, a gem on each flap
	for _, s in { -1, 1 } do
		runeColumn(c, Vector3.new(s * (f.w / 2 + 0.225), f.sideTop - 0.3, f.zc + 0.03), 0.2, { 2, 3, 4 }, 1, runeColor, s)
		diamond(c, "SideGem", Vector3.new(s * (f.w / 2 + 0.13), f.sideTop - 0.05, f.zc + 0.03 + f.d * 0.37), 0.11, 0.04, runeColor, NEON)
	end
	-- a small diamond between the pocket straps
	local pocketMid = Vector3.new(0, f.pocketBottom + (f.pocketTop - f.pocketBottom) * 0.38, f.zf + 0.31)
	diamond(c, "PocketSetting", pocketMid, 0.22, 0.04, col.Trim, METAL)
	diamond(c, "PocketGem", pocketMid + Vector3.new(0, 0, 0.03), 0.13, 0.05, glow(col.Gem), NEON)
end

-- 9: obsidian plates with lava seams, a fire crystal cluster, two ember chimneys behind the bedroll.
local function emberforgePack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.EmberforgePack)
	local lava = glow(col.Glow)
	local fire = glow(col.Gem)
	local hot = glow(rgb(255, 210, 60))
	badge(c, "Setting", f.emblem + Vector3.new(0, 0, 0.02), 0.48, 0.07, col.Trim, METAL)
	local base = CFrame.new(f.emblem + Vector3.new(0, -0.06, 0.06))
	crystal(c, base * CFrame.Angles(0.3, 0, 0), 0.62, 0.21, fire, hot)
	crystal(c, base * CFrame.new(-0.13, 0, 0) * CFrame.Angles(0.3, 0, 0.6), 0.4, 0.15, fire, hot)
	crystal(c, base * CFrame.new(0.13, 0, 0) * CFrame.Angles(0.3, 0, -0.55), 0.36, 0.14, fire, hot)
	-- lava seams: cracks across the flap, between flap and pocket, on the side pockets
	local seams = {
		{ -0.42, f.top - 0.22, 0.5, 0.35 },
		{ -0.2, f.top - 0.36, 0.3, -0.5 },
		{ 0.4, f.top - 0.28, 0.46, -0.3 },
		{ 0.62, f.top - 0.5, 0.26, 0.8 },
	}
	for _, s in seams do
		block(c, "Lava", at(s[1] * f.w / 2, s[2], f.zf + 0.145) * CFrame.Angles(0, 0, s[4]), Vector3.new(s[3], 0.04, 0.03), lava, NEON)
	end
	local gapY = (f.flapBottom + f.pocketTop) / 2
	block(c, "Lava", at(-f.w * 0.3, gapY, f.zf + 0.01) * CFrame.Angles(0, 0, 0.25), Vector3.new(0.34, 0.04, 0.03), lava, NEON)
	block(c, "Lava", at(f.w * 0.32, gapY - 0.06, f.zf + 0.01) * CFrame.Angles(0, 0, -0.4), Vector3.new(0.3, 0.04, 0.03), lava, NEON)
	for _, s in { -1, 1 } do
		runeColumn(c, Vector3.new(s * (f.w / 2 + 0.225), f.sideTop - 0.3, f.zc + 0.03), 0.22, { 4, 2, 4 }, 1.1, lava, s)
	end
	-- two ember chimneys behind the bedroll
	local iron = rgb(46, 44, 50)
	for _, s in { -1, 1 } do
		local cx = s * (f.w / 2 - 0.16)
		local cz = GAP + 0.17
		local y0 = f.top + 0.1
		local y1 = f.rollY + f.rollD / 2 + 0.16
		post(c, "Chimney", Vector3.new(cx, (y0 + y1) / 2, cz), y1 - y0, 0.26, iron, METAL)
		post(c, "ChimneyRim", Vector3.new(cx, y1, cz), 0.08, 0.32, col.Trim, METAL)
		post(c, "Ember", Vector3.new(cx, y1 + 0.03, cz), 0.04, 0.22, lava, NEON)
	end
end

-- 10: pearl and gold, a violet flap, galaxy panels, a star crystal, star shards and two wings.
local function starforgePack(c: Ctx)
	local f = c.f
	local col = c.colors
	standard(c, STYLES.StarforgePack)
	local galaxy = col.Panel
	local star = glow(col.Gem)
	local violet = glow(col.Glow)
	local gold = col.Trim
	-- a galaxy panel on the front pocket with three twinkles
	local ph = f.pocketTop - f.pocketBottom
	local panelY = f.pocketBottom + ph * 0.4
	block(c, "Galaxy", at(0, panelY, f.zf + 0.305), Vector3.new(f.pocketW * 0.62, ph * 0.5, 0.02), galaxy, NEON)
	twinkle(c, Vector3.new(-f.pocketW * 0.15, panelY + 0.06, f.zf + 0.32), 0.14, WHITE:Lerp(violet, 0.3))
	twinkle(c, Vector3.new(f.pocketW * 0.17, panelY - 0.05, f.zf + 0.32), 0.1, WHITE:Lerp(violet, 0.3))
	-- the star: gold rays behind a big crystal
	local e = f.emblem
	badge(c, "Setting", e + Vector3.new(0, 0, 0.02), 0.5, 0.06, gold, METAL)
	block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.05)), Vector3.new(0.86, 0.07, 0.04), gold, METAL)
	block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.05)), Vector3.new(0.07, 0.86, 0.04), gold, METAL)
	block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.05)) * DIAMOND, Vector3.new(0.56, 0.05, 0.04), gold, METAL)
	block(c, "Ray", CFrame.new(e + Vector3.new(0, 0, 0.05)) * DIAMOND, Vector3.new(0.05, 0.56, 0.04), gold, METAL)
	diamond(c, "Crystal", e + Vector3.new(0, 0, 0.09), 0.28, 0.1, star, NEON)
	-- galaxy runes on the side pockets
	for _, s in { -1, 1 } do
		runeColumn(c, Vector3.new(s * (f.w / 2 + 0.225), f.sideTop - 0.3, f.zc + 0.03), 0.2, { 3, 1, 3 }, 1, violet, s)
	end
	-- twinkles on the violet flap, two star shards floating over the bedroll ends
	local sparkle = WHITE:Lerp(violet, 0.25)
	twinkle(c, Vector3.new(-f.w * 0.4, f.top - 0.24, f.zf + 0.15), 0.16, sparkle)
	twinkle(c, Vector3.new(f.w * 0.41, f.top - 0.46, f.zf + 0.15), 0.12, sparkle)
	twinkle(c, Vector3.new(f.w * 0.12, f.top - 0.16, f.zf + 0.15), 0.1, sparkle)
	for _, s in { -1, 1 } do
		local shardAt = Vector3.new(s * (f.w / 2 - 0.15), f.rollY + f.rollD / 2 + 0.42, f.rollZ)
		block(c, "StarShard", CFrame.new(shardAt) * CFrame.Angles(0, s * 0.5, math.pi / 4), Vector3.new(0.14, 0.14, 0.14), violet, NEON)
		twinkle(c, shardAt + Vector3.new(s * 0.22, 0.2, 0.05), 0.1, sparkle)
	end
	-- two wings: three gold-edged pearl feathers each, swept out and up, violet glowing tips
	for _, s in { -1, 1 } do
		local rootAt = Vector3.new(s * (f.w / 2 + 0.02), f.top - 0.3, f.zc + 0.12)
		for i, spec in { { 1.35, 0.22 }, { 1.15, 0.6 }, { 0.92, 0.98 } } do
			local len, angle = spec[1], spec[2]
			local dir = Vector3.new(s * math.cos(angle), math.sin(angle), 0)
			local turn = CFrame.Angles(0, 0, s * angle)
			local height = 0.27 - i * 0.03
			block(c, "Feather", CFrame.new(rootAt + dir * (len / 2)) * turn, Vector3.new(len, height, 0.07), col.Body)
			block(
				c,
				"FeatherEdge",
				CFrame.new(rootAt + dir * (len / 2 - 0.08)) * turn * CFrame.new(0, -height / 2, 0),
				Vector3.new(len - 0.16, 0.06, 0.09),
				gold,
				METAL
			)
			block(c, "FeatherTip", CFrame.new(rootAt + dir * (len - 0.12)) * turn, Vector3.new(0.24, height + 0.03, 0.09), violet, NEON)
		end
	end
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	CanvasPack = canvasPack,
	LeatherRucksack = leatherRucksack,
	MinersPack = minersPack,
	IronboundPack = ironboundPack,
	ExplorersPack = explorersPack,
	AmethystPack = amethystPack,
	RuneboundPack = runeboundPack,
	EmberforgePack = emberforgePack,
	StarforgePack = starforgePack,
}

-- The lowest and highest point of the model's parts above Root (Y).
local function heightRange(model: Model): (number, number)
	local low, high = math.huge, -math.huge
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			local cf = p.CFrame
			local s = p.Size
			local half = math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
			low = math.min(low, cf.Position.Y - half)
			high = math.max(high, cf.Position.Y + half)
		end
	end
	return low, high
end

function BackpackBuilder.build(backpackId: string): Model
	local pack = BackpackData.ById[backpackId]
	assert(pack, "unknown backpack " .. tostring(backpackId))
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
	local styleOf = STYLES[pack.Id] or STYLES.LeatherRucksack
	local c: Ctx = { model = model, root = root, colors = pack.Colors, f = makeFrame(pack.Size, styleOf) }
	if pack.Id == BackpackData.StarterId then
		burlapSack(c, pack.Size)
	else
		local builder = BUILDERS[pack.Id]
		assert(builder, "no builder for backpack " .. pack.Id)
		builder(c)
		attach(c, "Gem", c.f.emblem + Vector3.new(0, 0, 0.12))
		attach(c, "Top", Vector3.new(0, c.f.rollY + c.f.rollD / 2 + 0.2, c.f.rollZ))
	end
	local low, high = heightRange(model)
	model:SetAttribute("BackpackId", pack.Id)
	model:SetAttribute("BottomY", low)
	model:SetAttribute("TopY", high)
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
