--[[
	The clean armour every egg golem's costume is cut from (EggGear; owner
	2026-10-30: "make the golems like in this picture, those are cleaner":
	the Sky and Dragonforge limited golems). Instead of the rock golem's
	turned stone chunks: gauntlets lined up with the arms, a rounded plate
	on each shoulder, a framed gem emblem on the chest, a belt with a
	buckle, a dark visor (or a slim brow) for the glowing eyes;
	GolemBuilder rounds the body and the head (or helm) afterwards.
	Positions are unscaled golem units from the feet (GolemBuilder's Ctx),
	the front is -Z.

	  dress(c, d)      re-dress the body's own parts (no part cost): skin,
	                   arms, boots, gauntlets (Fist1/2), the face (the Brow:
	                   a visor, a slim brow or nothing), the belt (the rock
	                   golem's Boulder) and its buckle (its Crystal)
	  pauldrons(c, color, material, rim?, rimMaterial?)
	                   rounded Pauldron1/2 (they swing with the arms; a rim under each)
	  emblem(c, frame, frameMaterial, gem, y?)   the framed gem on the chest
	                   (the body's Core is the gem)
	  collar(c, color, material)   a trim strip along the top of the chest,
	                   under the big head (it keeps the head apart from the body)
	  shard(c, name, at, w, h, color, material)   a crystal (a square prism
	                   turned on its length)
	  crystal(c, name, from, to, w, color, material)   a crystal growing from
	                   one golem-local point to another (the big head hangs
	                   over the back: gear there stays low or reaches out behind it)
	  backCluster(c, name, list, color, material)   crystals from the back up
	                   and out behind the head: { x0, y0, x1, y1, z1, w } each
	  diamond(...)     a square turned 45 degrees about its facing axis
	  ring(c, name, y, z, r, n, width, color, material, tilt)   a halo
	  crown(c, spec)   a band with points and gems (parts named Crown*: they
	                   ride on the head)
	  held(c, name, from, to, width, color, material)   a shaft in the right
	                   fist (a staff, a sword's blade)
	Every helper adds its parts only while c.Room() allows.
]]

local Types = require(script.Parent.Parent.LimitedGearTypes)

type Ctx = Types.Ctx
type Kit = Types.Kit
type Tools = Types.Tools

local Clean = {}

local M = Enum.Material
local NEON = M.Neon
local PI = math.pi

-- the face (the body's Brow): a dark band the eyes glow on, a slim
-- straight brow over them, or nothing (a bare face; a covered one has no Brow)
export type Face = "Visor" | "Brow" | "Bare"

export type Dress = {
	Skin: Color3, -- the head
	SkinMaterial: Enum.Material,
	Torso: Color3?, -- the body (nil: the skin; a deeper shade keeps the big head apart from it)
	Limbs: Color3?, -- the arms (nil: the torso a little toward the boots)
	Boots: Color3, -- the legs
	BootMaterial: Enum.Material,
	Armour: Color3, -- the gauntlets (Fist1/2)
	ArmourMaterial: Enum.Material,
	Belt: Color3, -- the belt (the body's Boulder)
	BeltMaterial: Enum.Material,
	Buckle: Color3, -- its buckle (the body's Crystal)
	BuckleMaterial: Enum.Material,
	Face: Face,
	FaceColor: Color3?, -- the visor's or the brow's
	FaceMaterial: Enum.Material?,
}

export type Crown = {
	Y: number, -- the band's middle
	Radius: number,
	Height: number, -- the band's height
	Points: number, -- around the band, the first at the front
	Point: number, -- a point's size (the front one is a third bigger)
	Color: Color3,
	Material: Enum.Material,
	Gems: { Color3 }?, -- gems on the band's front (the middle first)
}

export type Gear = {
	diamond: (parent: Instance, name: string, cf: CFrame, w: number, thick: number, color: Color3, material: Enum.Material?) -> Part,
	dress: (c: Ctx, d: Dress) -> (),
	pauldrons: (c: Ctx, color: Color3, material: Enum.Material, rim: Color3?, rimMaterial: Enum.Material?) -> (),
	emblem: (c: Ctx, frame: Color3, frameMaterial: Enum.Material, gem: Color3, y: number?) -> (),
	collar: (c: Ctx, color: Color3, material: Enum.Material) -> (),
	shard: (c: Ctx, name: string, at: CFrame, w: number, h: number, color: Color3, material: Enum.Material?) -> Part?,
	crystal: (c: Ctx, name: string, from: Vector3, to: Vector3, w: number, color: Color3, material: Enum.Material?) -> Part?,
	backCluster: (c: Ctx, name: string, list: { { number } }, color: Color3, material: Enum.Material) -> (),
	ring: (
		c: Ctx,
		name: string,
		y: number,
		z: number,
		r: number,
		n: number,
		width: number,
		color: Color3,
		material: Enum.Material,
		tilt: number
	) -> (),
	crown: (c: Ctx, spec: Crown) -> number,
	held: (c: Ctx, name: string, from: Vector3, to: Vector3, width: number, color: Color3, material: Enum.Material) -> Part?,
}

-- The helpers for one build kit (GolemBuilder's part makers and the limited sets' tools).
function Clean.new(K: Kit, T: Tools): Gear
	local function diamond(
		parent: Instance,
		name: string,
		cf: CFrame,
		w: number,
		thick: number,
		color: Color3,
		material: Enum.Material?
	): Part
		return K.part(parent, name, cf * CFrame.Angles(0, 0, PI / 4), Vector3.new(w, w, thick), color, material)
	end

	local function dress(c: Ctx, d: Dress)
		local torso = d.Torso or d.Skin
		T.recolor(c, "Head", d.Skin, d.SkinMaterial)
		T.recolor(c, "Body", torso, d.SkinMaterial)
		for _, name in { "Arm1", "Arm2" } do
			T.recolor(c, name, d.Limbs or torso:Lerp(d.Boots, 0.2), d.SkinMaterial)
		end
		for _, name in { "Leg1", "Leg2" } do
			T.recolor(c, name, d.Boots, d.BootMaterial)
		end
		for i, side in { -1, 1 } do
			-- gauntlets in line with the arms (not turned rock chunks)
			T.redress(
				c,
				"Fist" .. i,
				c.At(side * 0.845, 0.66, -0.02) * CFrame.Angles(0, 0, side * 0.1),
				c.V(0.48, 0.42, 0.52),
				d.Armour,
				d.ArmourMaterial
			)
		end
		-- the rock golem's shoulder boulder and crystal become the belt and its buckle
		T.redress(c, "Boulder", c.At(0, 0.6, 0), c.V(1.24, 0.12, 0.89), d.Belt, d.BeltMaterial)
		T.redress(c, "Crystal", c.At(0, 0.6, -0.455), c.V(0.24, 0.17, 0.04), d.Buckle, d.BuckleMaterial)
		local faceColor = d.FaceColor or Color3.fromRGB(28, 24, 32)
		local faceMaterial = d.FaceMaterial or M.SmoothPlastic
		if d.Face == "Visor" then
			T.redress(c, "Brow", c.At(0, 2.02, -0.66), c.V(1.04, 0.36, 0.03), faceColor, faceMaterial)
		elseif d.Face == "Brow" then
			T.redress(c, "Brow", c.At(0, 2.33, -0.675), c.V(1.0, 0.13, 0.08), faceColor, faceMaterial)
		else
			-- (a bare face: the brow shrinks away inside the head)
			T.redress(c, "Brow", c.At(0, 2.1, 0), c.V(0.1, 0.1, 0.1), d.Skin, d.SkinMaterial)
		end
	end

	local function pauldrons(c: Ctx, color: Color3, material: Enum.Material, rim: Color3?, rimMaterial: Enum.Material?)
		for i, side in { -1, 1 } do
			if c.Room() < 1 then
				return
			end
			local at = c.At(side * 0.8, 1.42, 0) * CFrame.Angles(0, 0, -side * 0.25)
			T.ellipsoid(c.Model, "Pauldron" .. i, at, c.V(0.66, 0.42, 0.72), color, material)
			if rim and c.Room() >= 1 then
				K.upright(
					c.Model,
					"PauldronRim" .. i,
					at * CFrame.new(0, -0.03 * c.S, 0),
					0.07 * c.S,
					0.76 * c.S,
					rim,
					rimMaterial or material
				)
			end
		end
	end

	local function emblem(c: Ctx, frame: Color3, frameMaterial: Enum.Material, gem: Color3, y: number?)
		local h = y or 1.08
		if c.Room() >= 1 then
			diamond(c.Model, "CorePlate", c.At(0, h, -0.48), 0.42 * c.S, 0.03 * c.S, frame, frameMaterial)
		end
		T.redress(c, "Core", c.At(0, h, -0.505) * CFrame.Angles(0, 0, PI / 4), c.V(0.26, 0.26, 0.03), gem, NEON)
	end

	local function collar(c: Ctx, color: Color3, material: Enum.Material)
		if c.Room() >= 1 then
			K.part(c.Model, "Collar", c.At(0, 1.37, -0.005), c.V(1.0, 0.13, 0.9), color, material)
		end
	end

	local function shard(c: Ctx, name: string, at: CFrame, w: number, h: number, color: Color3, material: Enum.Material?): Part?
		if c.Room() < 1 then
			return nil
		end
		return K.part(c.Model, name, at * CFrame.Angles(0, PI / 4, 0), c.V(w, h, w), color, material)
	end

	local function crystal(c: Ctx, name: string, from: Vector3, to: Vector3, w: number, color: Color3, material: Enum.Material?): Part?
		if c.Room() < 1 then
			return nil
		end
		local a, b = T.P(c, from.X, from.Y, from.Z), T.P(c, to.X, to.Y, to.Z)
		local up = if math.abs((b - a).Unit.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
		local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, 0, PI / 4)
		return K.part(c.Model, name, cf, Vector3.new(w * c.S, w * c.S, (b - a).Magnitude), color, material)
	end

	local function backCluster(c: Ctx, name: string, list: { { number } }, color: Color3, material: Enum.Material)
		for i, k in list do
			if crystal(c, name .. i, Vector3.new(k[1], k[2], 0.46), Vector3.new(k[3], k[4], k[5]), k[6], color, material) == nil then
				return
			end
		end
	end

	local function ring(
		c: Ctx,
		name: string,
		y: number,
		z: number,
		r: number,
		n: number,
		width: number,
		color: Color3,
		material: Enum.Material,
		tilt: number
	)
		local frame = c.At(0, y, z) * CFrame.Angles(tilt, 0, 0)
		local w = width * c.S
		for i = 1, n do
			if c.Room() < 1 then
				return
			end
			local a0, a1 = (i - 1) / n * 2 * PI, i / n * 2 * PI
			local p0 = (frame * CFrame.new(math.cos(a0) * r * c.S, 0, math.sin(a0) * r * c.S)).Position
			local p1 = (frame * CFrame.new(math.cos(a1) * r * c.S, 0, math.sin(a1) * r * c.S)).Position
			-- (a little past each corner: no notches between the segments)
			local dir = (p1 - p0).Unit
			T.seg(c.Model, name .. i, p0 - dir * (w * 0.3), p1 + dir * (w * 0.3), w, w, color, material)
		end
	end

	local function crown(c: Ctx, spec: Crown): number
		local top = spec.Y + spec.Height / 2
		if c.Room() < 1 then
			return top
		end
		K.upright(c.Model, "CrownBand", c.At(0, spec.Y, 0), spec.Height * c.S, 2 * spec.Radius * c.S, spec.Color, spec.Material)
		for i = 1, spec.Points do
			if c.Room() < 1 then
				break
			end
			local a = (i - 1) / spec.Points * 2 * PI
			local size = if i == 1 then spec.Point * 1.35 else spec.Point
			local y = spec.Y + spec.Height / 2 + size * 0.2
			diamond(
				c.Model,
				"CrownPoint" .. i,
				c.At(math.sin(a) * spec.Radius * 0.96, y, -math.cos(a) * spec.Radius * 0.96) * CFrame.Angles(0, -a, 0),
				size * c.S,
				0.07 * c.S,
				spec.Color,
				spec.Material
			)
			top = math.max(top, y + size * 0.71)
		end
		local gems: { Color3 } = spec.Gems or {}
		for i, color in gems do
			if c.Room() < 1 then
				break
			end
			-- the middle gem at the front, the next ones to its sides
			local a = if i == 1 then 0 elseif i == 2 then -0.55 else 0.55
			local size = if i == 1 then 0.17 else 0.12
			diamond(
				c.Model,
				"CrownGem" .. i,
				c.At(math.sin(a) * (spec.Radius + 0.02), spec.Y, -math.cos(a) * (spec.Radius + 0.02)) * CFrame.Angles(0, -a, 0),
				size * c.S,
				0.04 * c.S,
				color,
				NEON
			)
		end
		return top
	end

	local function held(c: Ctx, name: string, from: Vector3, to: Vector3, width: number, color: Color3, material: Enum.Material): Part?
		if c.Room() < 1 then
			return nil
		end
		return T.seg(c.Model, name, T.P(c, from.X, from.Y, from.Z), T.P(c, to.X, to.Y, to.Z), width * c.S, width * c.S, color, material)
	end

	return {
		diamond = diamond,
		dress = dress,
		pauldrons = pauldrons,
		emblem = emblem,
		collar = collar,
		shard = shard,
		crystal = crystal,
		backCluster = backCluster,
		ring = ring,
		crown = crown,
		held = held,
	}
end

return Clean
