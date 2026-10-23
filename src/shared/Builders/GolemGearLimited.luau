--[[
	The LIMITED EDITION golems' costumes and shards (GolemConfig Edition,
	Config/LimitedGolems). Each set lives in its own module under
	Builders/LimitedGear/<Set>.luau:

	  Faces          gear that covers the face (GolemBuilder.Faces)
	  accessories(kit, tools)   name -> builder: the set's costumes,
	                 registered into GolemBuilder's ACCESSORIES
	  shard(kit, tools, s)      the set's egg-shaped SHARD that replaces the
	                 pill capsule in the opening (GolemBuilder.capsule for a
	                 capsule whose Limited is the set; see Shard below)

	Every costume follows GolemBuilder's contract: it adds its parts to
	c.Model (positions in unscaled golem units from the feet: c.At / c.V /
	tools.P) and returns the top of what it added. It may also re-dress the
	body's own parts (tools.redress / recolor) at no part cost. Parts beyond
	the first few are added in priority order only while c.Room() says the
	golem's budget allows (GolemConfig.LimitedMaxParts by rarity).

	The tools (shared by every set):
	  P(c, x, y, z)            a golem-local point (unscaled) -> world Vector3
	  seg(parent, name, a, b, w, d, color, material)
	                           a box from world point a to b (w x d thick,
	                           world studs): bones, horn and tail segments
	  tri(parent, name, a, b, p, thick, color, material, room?)
	                           a flat triangle through three world points from
	                           one or two wedges (one when it is right-angled);
	                           returns the parts used. `room` caps it at 1.
	  ellipsoid(parent, name, cf, size, color, material)
	                           a Part with a Sphere SpecialMesh (no upload):
	                           an egg or a smooth dome of any proportions
	  redress(c, name, cf, size, color, material) / recolor(c, name, color, material)
	  embers(part, color, rate, size?)   one slow ParticleEmitter (built-in
	                           texture) on a part: Legendary / Mythic only
	  light(part, color, range, brightness)   the Mythic's one PointLight

	The shard contract (GolemBuilder.capsule builds the frame; the set fills
	it): s = { Top: Model, Bottom: Model, Center: CFrame, Color, Glow,
	Room: () -> number }. Put the upper shell in s.Top and the lower in
	s.Bottom (they fly apart in the burst), one Neon part named "Band" in
	s.Bottom (the controller tints it while it shakes) and three parts named
	"Crack1".."Crack3" in s.Bottom (hidden until the shard shakes;
	GolemBuilder hides them). Stay inside GolemBuilder.ShardMaxParts.

	A new edition adds its own module (and its golems' accessory names to
	GolemConfig.Accessories); an old one stays: its golems live on in the
	saves.
]]

local LimitedGear = script.Parent:WaitForChild("LimitedGear")

local GolemGearLimited = {}

local Types = require(script.Parent.LimitedGearTypes)
export type Ctx = Types.Ctx
export type Kit = Types.Kit
export type Shard = Types.Shard
export type Tools = Types.Tools
export type SetModule = Types.SetModule

-- The sets with costumes (each module: Builders/LimitedGear/<Id>.luau).
GolemGearLimited.SetIds = { "Dragonforge", "Galaxy", "MechaNeon", "FrostTitans", "Sky" }

local SETS: { [string]: SetModule } = {}
for _, id in GolemGearLimited.SetIds do
	local module = LimitedGear:FindFirstChild(id)
	if module and module:IsA("ModuleScript") then
		SETS[id] = (require :: any)(module)
	end
end

-- Gear that covers the face (GolemBuilder.Faces): "Closed" = no stone brow,
-- the eyes sit a little forward (they glow through a slit); "Visor" = no brow.
GolemGearLimited.Faces = {} :: { [string]: string }
for _, set in SETS do
	for name, face in set.Faces do
		GolemGearLimited.Faces[name] = face
	end
end

-- The ember texture every set shares (built into Roblox: no upload).
GolemGearLimited.EmberTexture = "rbxasset://textures/particles/sparkles_main.dds"

local function makeTools(kit: Kit): Tools
	local part, wedge = kit.part, kit.wedge

	local function P(c: Ctx, x: number, y: number, z: number): Vector3
		return c.At(x, y, z).Position
	end

	local function seg(
		parent: Instance,
		name: string,
		a: Vector3,
		b: Vector3,
		w: number,
		d: number,
		color: Color3,
		material: Enum.Material?
	): Part
		local length = math.max((b - a).Magnitude, 0.01)
		-- (lookAt needs an up that isn't along the segment)
		local dir = (b - a).Unit
		local up = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
		local cf = CFrame.lookAt((a + b) / 2, b, up)
		return part(parent, name, cf, Vector3.new(w, d, length), color, material)
	end

	-- a triangle a, b, p from two wedges (the classic split at the foot of
	-- the height over the longest side); a right angle needs only one
	local function tri(
		parent: Instance,
		name: string,
		a0: Vector3,
		b0: Vector3,
		c0: Vector3,
		thick: number,
		color: Color3,
		material: Enum.Material?,
		room: number?
	): number
		local a, b, c = a0, b0, c0
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		-- make bc the longest side (a is the apex)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local right = ac:Cross(ab)
		if right.Magnitude < 1e-6 then
			return 0
		end
		right = right.Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		local d1 = math.abs(ab:Dot(back))
		local d2 = math.abs(ac:Dot(back))
		local used = 0
		local minDepth = 0.02
		local cap = room or 2
		if d1 > minDepth and used < cap then
			wedge(parent, name .. "A", CFrame.fromMatrix((a + b) / 2, right, up, back), Vector3.new(thick, height, d1), color, material)
			used += 1
		end
		if d2 > minDepth and used < cap then
			wedge(parent, name .. "B", CFrame.fromMatrix((a + c) / 2, -right, up, -back), Vector3.new(thick, height, d2), color, material)
			used += 1
		end
		return used
	end

	local function ellipsoid(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
		local p = part(parent, name, cf, size, color, material)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end

	local function redress(c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material)
		local p = c.Model:FindFirstChild(name)
		if p and p:IsA("Part") then
			p.CFrame = cf
			p.Size = size
			p.Color = color
			p.Material = material
		end
	end

	local function recolor(c: Ctx, name: string, color: Color3, material: Enum.Material)
		local p = c.Model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = color
			p.Material = material
		end
	end

	local function embers(p: BasePart, color: Color3, rate: number, size: number?): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name = "Embers"
		e.Texture = GolemGearLimited.EmberTexture
		e.Color = ColorSequence.new(color, Color3.new(1, 0.95, 0.7))
		e.LightEmission = 1
		e.Rate = rate
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(0.6, 1.4)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Acceleration = Vector3.new(0, 1.2, 0)
		local k = size or 0.18
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, k), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = p
		return e
	end

	local function light(p: BasePart, color: Color3, range: number, brightness: number): PointLight
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = p
		return l
	end

	return {
		P = P,
		seg = seg,
		tri = tri,
		ellipsoid = ellipsoid,
		redress = redress,
		recolor = recolor,
		embers = embers,
		light = light,
	}
end

GolemGearLimited.tools = makeTools

-- Every set's costumes (GolemBuilder registers them as accessories).
function GolemGearLimited.accessories(kit: Kit): { [string]: (Ctx) -> number }
	local tools = makeTools(kit)
	local all: { [string]: (Ctx) -> number } = {}
	for _, set in SETS do
		for name, add in set.accessories(kit, tools) do
			all[name] = add
		end
	end
	return all
end

-- The set's shard builder (nil: the set keeps the pill capsule).
function GolemGearLimited.shard(setId: string, kit: Kit): ((Shard) -> ())?
	local set = SETS[setId]
	local build = if set then set.shard else nil
	if not build then
		return nil
	end
	local tools = makeTools(kit)
	return function(s: Shard)
		build(kit, tools, s)
	end
end

return GolemGearLimited
