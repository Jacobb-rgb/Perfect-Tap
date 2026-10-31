--[[
	The armour set every egg golem's costume is cut from (EggGear; owner
	2026-10-30: "make the golems like in this picture, those are cleaner":
	the Sky and Dragonforge limited golems, crisp two-tone armour). The
	rock golem becomes a little knight of its egg: a dark under-suit (body,
	arms, legs), plates in the golem's own colour (the head, a breastplate,
	domed shoulder plates, boots) and trim in the egg's metal (gauntlets, a
	collar, rims under the shoulder plates, a band round the head, the belt's
	buckle, the emblem's frame), the glowing eyes in a dark visor.
	GolemBuilder rounds the head (or helm) afterwards.
	Positions are unscaled golem units from the feet (GolemBuilder's Ctx),
	the front is -Z.

	  dress(c, d)      the set: re-dresses the body's own parts (no part
	                   cost: the under-suit, the head, the gauntlets Fist1/2,
	                   the face on the Brow, the belt on the rock golem's
	                   Boulder, its buckle on its Crystal), then adds the
	                   breastplate, the shoulder plates, the collar, the boots,
	                   the rims, the band round the head, the dark cap over it,
	                   the guards on its sides and the bracers
	  cog / gemFrame / crest   the eggs' emblems round the glowing Core on the
	                   breastplate: Stone a bronze cog, Crystal a silver frame
	                   holding a crystal, Royal a gold crest
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
	  held(c, name, from, to, width, color, material)   a shaft in a fist (a
	                   staff, a handle; held ones stay clear of the big head,
	                   x >= 0.95, so they swing with the arm)
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

Clean.Visor = Color3.fromRGB(26, 22, 30)

-- the face (the body's Brow): a dark visor the eyes glow on, or nothing (a
-- bare face; a covered one has no Brow)
export type Face = "Visor" | "Bare"

export type Dress = {
	Plate: Color3, -- the armour plates: breastplate, shoulder plates, boots (and the head)
	PlateMaterial: Enum.Material,
	Head: Color3?, -- (nil: the plates' colour)
	HeadMaterial: Enum.Material?,
	Suit: Color3, -- the under-suit: body, arms, legs (a shade darker)
	SuitMaterial: Enum.Material,
	Metal: Color3, -- the trim: gauntlets, collar, rims, the band round the head
	MetalMaterial: Enum.Material,
	Belt: Color3,
	BeltMaterial: Enum.Material,
	Buckle: Color3,
	BuckleMaterial: Enum.Material,
	Face: Face,
	FaceZ: number?, -- the visor's depth (a helm's front is further out than the head's)
	Band: boolean?, -- false: no band round the head (a hat, a hood, a helm brings its own)
	Guards: boolean?, -- false: no metal guards on the head's sides (a closed helm covers them)
	Ridge: boolean?, -- false: no dark cap over the band (a sprout grows there)
	Boots: Color3?, -- (nil: the plates' colour)
	BootMaterial: Enum.Material?,
}

export type Crown = {
	Y: number, -- the band's middle
	Radius: number,
	Height: number, -- the band's height
	Points: number, -- around the band, the first at the front
	Point: number, -- a point's size (the front one is a third bigger)
	Color: Color3,
	Material: Enum.Material,
	PointMaterial: Enum.Material?, -- (nil: the band's; Neon: points of light)
	PointColor: Color3?,
	Gems: { Color3 }?, -- gems on the band's front (the middle first)
}

export type Gear = {
	diamond: (parent: Instance, name: string, cf: CFrame, w: number, thick: number, color: Color3, material: Enum.Material?) -> Part,
	dress: (c: Ctx, d: Dress) -> (),
	cog: (c: Ctx, color: Color3, material: Enum.Material, gem: Color3) -> (),
	gemFrame: (c: Ctx, color: Color3, material: Enum.Material, crystal: Color3, gem: Color3) -> (),
	crest: (c: Ctx, color: Color3, material: Enum.Material, gem: Color3) -> (),
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

-- where the shoulder plates sit (their rims, gems and spikes build on it)
function Clean.shoulder(c: Ctx, side: number): CFrame
	return c.At(side * 0.84, 1.44, 0) * CFrame.Angles(0, 0, -side * 0.25)
end

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
		-- the body's own parts: the under-suit, the head, the gauntlets
		for _, name in { "Body", "Arm1", "Arm2", "Leg1", "Leg2" } do
			T.recolor(c, name, d.Suit, d.SuitMaterial)
		end
		T.recolor(c, "Head", d.Head or d.Plate, d.HeadMaterial or d.PlateMaterial)
		for i, side in { -1, 1 } do
			-- (in line with the arms, not turned rock chunks)
			T.redress(
				c,
				"Fist" .. i,
				c.At(side * 0.845, 0.66, -0.02) * CFrame.Angles(0, 0, side * 0.1),
				c.V(0.48, 0.42, 0.52),
				d.Metal,
				d.MetalMaterial
			)
		end
		-- the rock golem's shoulder boulder and crystal become the belt and its buckle
		T.redress(c, "Boulder", c.At(0, 0.6, 0), c.V(1.24, 0.13, 0.9), d.Belt, d.BeltMaterial)
		T.redress(c, "Crystal", c.At(0, 0.6, -0.465), c.V(0.26, 0.19, 0.05), d.Buckle, d.BuckleMaterial)
		local z = d.FaceZ or -0.66
		if d.Face == "Visor" then
			T.redress(c, "Brow", c.At(0, 2.02, z), c.V(1.12, 0.42, 0.03), Clean.Visor, M.SmoothPlastic)
			for i, x in { -0.28, 0.28 } do
				T.redress(c, "Eye" .. i, c.At(x, 2.02, z - 0.025), c.V(0.3, 0.24, 0.03), c.Glow, NEON)
			end
		else
			-- (a bare face: the brow shrinks away inside the head)
			T.redress(c, "Brow", c.At(0, 2.1, 0), c.V(0.1, 0.1, 0.1), d.Head or d.Plate, d.HeadMaterial or d.PlateMaterial)
		end
		-- the plates and the trim, the ones that change the look most first
		if c.Room() >= 1 then
			K.part(c.Model, "Breastplate", c.At(0, 1.0, -0.45), c.V(0.96, 0.62, 0.06), d.Plate, d.PlateMaterial)
		end
		for i, side in { -1, 1 } do
			if c.Room() >= 1 then
				T.ellipsoid(c.Model, "Pauldron" .. i, Clean.shoulder(c, side), c.V(0.86, 0.54, 0.92), d.Plate, d.PlateMaterial)
			end
		end
		if c.Room() >= 1 then
			K.part(c.Model, "Collar", c.At(0, 1.37, -0.005), c.V(1.0, 0.13, 0.9), d.Metal, d.MetalMaterial)
		end
		for i, x in { -0.3, 0.3 } do
			if c.Room() >= 1 then
				K.part(
					c.Model,
					"Boot" .. i,
					c.At(x, 0.12, -0.05),
					c.V(0.5, 0.24, 0.64),
					d.Boots or d.Plate,
					d.BootMaterial or d.PlateMaterial
				)
			end
		end
		for i, side in { -1, 1 } do
			if c.Room() >= 1 then
				local rim = Clean.shoulder(c, side) * CFrame.new(0, -0.04 * c.S, 0)
				K.upright(c.Model, "PauldronRim" .. i, rim, 0.09 * c.S, 0.98 * c.S, d.Metal, d.MetalMaterial)
			end
		end
		if d.Band ~= false and c.Room() >= 1 then
			K.part(c.Model, "HeadBand", c.At(0, 2.4, 0), c.V(1.54, 0.13, 1.34), d.Metal, d.MetalMaterial)
		end
		-- the helmet's dark cap over the band (the head two-toned like the body)
		if d.Ridge ~= false and d.Band ~= false and c.Room() >= 1 then
			K.part(c.Model, "HeadCap", c.At(0, 2.585, 0), c.V(1.52, 0.25, 1.32), d.Suit, d.SuitMaterial)
		end
		-- metal guards on the head's sides (a helmet's cheeks), plate bracers on the dark forearms
		for i, side in { -1, 1 } do
			if d.Guards ~= false and c.Room() >= 1 then
				K.part(c.Model, "HeadGuard" .. i, c.At(side * 0.78, 1.98, -0.04), c.V(0.08, 0.76, 0.96), d.Metal, d.MetalMaterial)
			end
		end
		for i, side in { -1, 1 } do
			if c.Room() >= 1 then
				local at = c.At(side * 0.83, 0.95, -0.01) * CFrame.Angles(0, 0, side * 0.1)
				K.part(c.Model, "Bracer" .. i, at, c.V(0.46, 0.14, 0.56), d.Plate, d.PlateMaterial)
			end
		end
	end

	-- the Stone egg's emblem: a bronze cog round the glowing core
	local function cog(c: Ctx, color: Color3, material: Enum.Material, gem: Color3)
		if c.Room() >= 3 then
			local at = c.At(0, 1.0, -0.5)
			K.facing(c.Model, "Cog", at, 0.04 * c.S, 0.4 * c.S, color, material)
			K.part(c.Model, "CogTeeth1", at, c.V(0.54, 0.1, 0.04), color, material)
			K.part(c.Model, "CogTeeth2", at * CFrame.Angles(0, 0, PI / 2), c.V(0.54, 0.1, 0.04), color, material)
		end
		T.redress(c, "Core", c.At(0, 1.0, -0.53) * CFrame.Angles(0, 0, PI / 4), c.V(0.2, 0.2, 0.03), gem, NEON)
	end

	-- the Crystal egg's emblem: a silver frame holding a crystal over the glowing core
	local function gemFrame(c: Ctx, color: Color3, material: Enum.Material, crystal: Color3, gem: Color3)
		if c.Room() >= 1 then
			diamond(c.Model, "CorePlate", c.At(0, 1.0, -0.495), 0.46 * c.S, 0.04 * c.S, color, material)
		end
		T.redress(c, "Core", c.At(0, 0.98, -0.525) * CFrame.Angles(0, 0, PI / 4), c.V(0.22, 0.22, 0.03), gem, NEON)
		if c.Room() >= 1 then
			K.part(c.Model, "CoreCrystal", c.At(0, 1.2, -0.53) * CFrame.Angles(0, PI / 4, 0), c.V(0.12, 0.3, 0.12), crystal, M.Glass)
		end
	end

	-- the Royal egg's emblem: a gold crest (a little shield) with the gem in it
	local function crest(c: Ctx, color: Color3, material: Enum.Material, gem: Color3)
		if c.Room() >= 2 then
			K.part(c.Model, "Crest", c.At(0, 1.06, -0.495), c.V(0.44, 0.3, 0.04), color, material)
			diamond(c.Model, "CrestPoint", c.At(0, 0.92, -0.495), 0.31 * c.S, 0.04 * c.S, color, material)
		end
		T.redress(c, "Core", c.At(0, 1.0, -0.525) * CFrame.Angles(0, 0, PI / 4), c.V(0.2, 0.2, 0.03), gem, NEON)
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
				spec.PointColor or spec.Color,
				spec.PointMaterial or spec.Material
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
		cog = cog,
		gemFrame = gemFrame,
		crest = crest,
		shard = shard,
		crystal = crystal,
		backCluster = backCluster,
		ring = ring,
		crown = crown,
		held = held,
	}
end

return Clean
