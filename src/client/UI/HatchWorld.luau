--[[
	HatchWorld: the egg opening's stage in the real 3D world (owner
	2026-11-15: "the eggs look pixelated, blurry ... I want actual
	improvements to the models and rendering quality").

	Why: the opening used to draw its eggs and golems in a full-screen
	ViewportFrame. A ViewportFrame has no anti-aliasing on its see-through
	edges (every egg's outline against the world was jagged), renders at a
	lower resolution, and has only a flat ambient + one light: no
	environment light, no specular, no Neon glow, no particles. In the world
	the same models get the renderer's anti-aliasing, its full PBR lighting,
	real Neon glow (bloom) and their particles.

	How: everything stands right in front of the camera, small (the eggs at
	Scale of their size, a golem at most GolemDepth studs away), so nothing
	of the world is ever between the camera and the stage (the camera's
	least zoom is 4 studs; its popper ignores parts that don't collide).
	HatchStage poses in its own camera space (HatchFx's camera at the
	origin, FieldOfView HatchFx.Fov) and this turns that into the world each
	frame: the camera's CFrame on top, the depths matched to the camera's
	real FieldOfView (DepthK), so a pose lands on exactly the same spot of
	the screen as before, whatever the camera does. The pieces that used to
	sit UNDER the viewport (the soft blobs, the flash, the sunburst, the
	auras, the platforms, the world's tint) move onto a SurfaceGui on a
	plane right behind the stage (CapsuleView.useBackdrop): it fills the
	view exactly, so they keep their screen layout, and it is depth-tested,
	so the eggs and golems stand IN FRONT of them, as before. Two lights
	ride with the camera (a soft key light from the upper left, a cool rim
	light from behind) so an egg looks the same in the bright lobby and in a
	dark cave. 3D motes stream into each charging egg and sparks fly at the
	burst and the reveal (particles a viewport never drew).

	  world = HatchWorld.new(opts)        the stage's instances (made once)
	  HatchWorld.show(world, on)          in the world while an opening plays
	  HatchWorld.begin(world, space, fov) a frame starts: the camera now
	  HatchWorld.place(world, rig, cf, top?, bottom?)   a model's pose (stage space)
	  HatchWorld.flush(world, aspect, farthest)   moves everything, the backdrop and lights
	  HatchWorld.energy(world, slot, cf, radius, rate, color)   the motes of an egg
	  HatchWorld.burst(world, slot, cf, radius, color, count)   sparks now
	  HatchWorld.setLight(world, lift, hue)   a Mythic's stage light
	  HatchWorld.clear(world)             the particles stopped (between openings)
]]

local HatchFx = require(script.Parent.HatchFx)
local HatchRig = require(script.Parent.HatchRig)

local HatchWorld = {}

HatchWorld.Scale = 0.08 -- the eggs' size on the stage (a single egg rests about 0.9 studs away)
-- The golems: built at most GolemScale of their size, and small enough to rest within GolemDepth (their
-- stone and metal textures tile in world studs: the bigger, the sharper they read).
HatchWorld.GolemScale = 0.25
HatchWorld.GolemDepth = 3.6
--[[
	The band the stage stands in, worked out every frame from the camera
	(begin): no part of it nearer than DepthLeast, nor than NearMargin times
	the camera's near clipping plane (Camera.NearPlaneZ: up to half a stud on
	some devices: a model's nearest part, by its rig's Reach); no model's
	middle further than FocusShare of the way to the player
	(the camera's Focus: its least zoom is 4 studs, but its popper pulls it
	closer in a tight tunnel or against a wall), nor than DepthMost. What a
	pose puts outside the band (an egg coming in small, a golem growing out
	of its egg: their size comes from their distance; the stage's depths at
	a wide view) is drawn that much smaller or bigger at its edge instead,
	on the same ray: the same on the screen (HatchStage.place). Only the
	golems flying to the player go further, fading. The backdrop stands
	behind the farthest model (BackdropBehind), at least BackdropDepth where
	there is room, never further than BackShare of the way to the player
	nor than BackdropMost (further, the world close by would cut into its
	glow).
]]
HatchWorld.DepthLeast = 0.55
HatchWorld.NearMargin = 1.6
HatchWorld.FocusShare = 0.55
HatchWorld.DepthMost = 4.0
HatchWorld.BackdropDepth = 2.6
HatchWorld.BackdropBehind = 1.15
HatchWorld.BackShare = 0.78
HatchWorld.BackdropMost = 5.0
--[[
	(owner 2026-11-15, his Studio test of the 3D stage: "too bright and overexposed ... lower the
	glow, fewer bright flashes and particles; the eggs and pets clearly visible with all their
	details, the magic kept, the light softer") The stage's own light is a soft fill on top of the
	world's: the key and rim lights a quarter down, the motes fewer, see-through and in their
	colour more than white (Glow: their LightEmission; 1 adds every mote's colour onto the egg),
	the sparks a softer white. The opening's bloom: CapsuleController.SoftBloom.
]]
HatchWorld.Key = { Position = Vector3.new(-0.7, 0.85, 0.2), Aim = Vector3.new(0, -0.05, -1.3), Brightness = 0.68, Range = 4.5, Angle = 80 }
HatchWorld.KeyColor = Color3.fromRGB(255, 248, 238)
HatchWorld.Rim = { Position = Vector3.new(0.75, 1.0, -2.8), Brightness = 0.55, Range = 3.0 }
HatchWorld.RimColor = Color3.fromRGB(214, 230, 255)
HatchWorld.SparkTexture = "rbxasset://textures/particles/sparkles_main.dds" -- built in: no upload
HatchWorld.MoteRate = 30 -- motes a second into one egg at the charge's peak
HatchWorld.Glow = 0.45 -- the motes' and sparks' LightEmission (1: fully additive, they whitened the eggs)
HatchWorld.White = 0.15 -- how far a mote leans from its colour to white
HatchWorld.SparkWhite = 0.45 -- how white a spark starts (it turns into its colour)
HatchWorld.Slots = 10 -- CapsuleView.StageTags

export type Opts = {
	Parent: Instance?, -- where the stage goes while an opening plays (Workspace)
	Bulk: ((parts: { BasePart }, frames: { CFrame }) -> ())?, -- Workspace:BulkMoveTo
	Emit: ((emitter: ParticleEmitter, count: number) -> ())?, -- ParticleEmitter:Emit
}

export type World = {
	Folder: Folder,
	Holder: Folder, -- the eggs and golems
	Backdrop: Part,
	Surface: SurfaceGui,
	KeyPart: Part,
	KeyLight: SpotLight,
	RimPart: Part,
	RimLight: PointLight,
	Motes: { Part }, -- per slot: the motes streaming into its egg (a sphere shell emitting inward)
	MoteFx: { ParticleEmitter },
	Sparks: { Part }, -- per slot: the sparks of its burst (its golem comes out of them)
	SparkFx: { ParticleEmitter },
	MoteAt: { [number]: CFrame }, -- per slot: where its motes are (stage space): followed every frame
	SparkAt: { [number]: CFrame }, -- per slot: where its sparks flew from (their particles ride on it)
	Sink: HatchRig.Sink,
	Space: CFrame, -- the camera this frame
	Fov: number, -- its FieldOfView this frame
	DepthK: number, -- a stage depth at Fov against at HatchFx.Fov (the same spot of the screen)
	Least: number, -- this frame's band (studs from the camera): no part of the stage nearer...
	Most: number, -- ...nor a model's middle further (begin)
	BackFar: number, -- the backdrop never further this frame
	Back: number, -- where the backdrop is this frame (flush; the focus follows it)
	Lift: number, -- the Mythic light's lift now
	Bulk: (parts: { BasePart }, frames: { CFrame }) -> (),
	Emit: (emitter: ParticleEmitter, count: number) -> (),
	Parent: Instance?,
	Shown: boolean,
}

local function invisible(name: string, size: Vector3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function emitter(parent: Part, inward: boolean): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = if inward then "Motes" else "Sparks"
	e.Texture = HatchWorld.SparkTexture
	e.LightEmission = HatchWorld.Glow
	e.LightInfluence = 0
	e.LockedToPart = true -- (the stage rides with the camera: so do its particles)
	e.Rate = 0
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = if inward then Enum.ParticleEmitterShapeStyle.Surface else Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = if inward then Enum.ParticleEmitterShapeInOut.Inward else Enum.ParticleEmitterShapeInOut.Outward
	e.Lifetime = if inward then NumberRange.new(0.38, 0.52) else NumberRange.new(0.45, 0.85)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Drag = if inward then 0 else 5
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.3),
		NumberSequenceKeypoint.new(0.8, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = parent
	return e
end

function HatchWorld.new(opts: Opts?): World
	local o: Opts = opts or {}
	local folder = Instance.new("Folder")
	folder.Name = "TerraForgeHatchStage"
	local holder = Instance.new("Folder")
	holder.Name = "Holder"
	holder.Parent = folder
	local backdrop = invisible("Backdrop", Vector3.new(4, 2.25, 0.02), folder)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Behind"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(1280, 720)
	surface.LightInfluence = 0 -- (as bright as on the screen: the world's light never dims it)
	surface.Brightness = 1
	surface.AlwaysOnTop = false -- (depth-tested: the eggs and golems in front of it)
	surface.ClipsDescendants = true
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surface.Parent = backdrop
	local keyPart = invisible("Key", Vector3.new(0.05, 0.05, 0.05), folder)
	local keyLight = Instance.new("SpotLight")
	keyLight.Name = "KeyLight"
	keyLight.Face = Enum.NormalId.Front
	keyLight.Angle = HatchWorld.Key.Angle
	keyLight.Range = HatchWorld.Key.Range
	keyLight.Brightness = HatchWorld.Key.Brightness
	keyLight.Color = HatchWorld.KeyColor
	keyLight.Shadows = false
	keyLight.Parent = keyPart
	local rimPart = invisible("Rim", Vector3.new(0.05, 0.05, 0.05), folder)
	local rimLight = Instance.new("PointLight")
	rimLight.Name = "RimLight"
	rimLight.Range = HatchWorld.Rim.Range
	rimLight.Brightness = HatchWorld.Rim.Brightness
	rimLight.Color = HatchWorld.RimColor
	rimLight.Shadows = false
	rimLight.Parent = rimPart
	local fx = Instance.new("Folder")
	fx.Name = "Fx"
	fx.Parent = folder
	local motes, moteFx, sparks, sparkFx = {}, {}, {}, {}
	for i = 1, HatchWorld.Slots do
		local m = invisible("Motes" .. i, Vector3.new(0.5, 0.5, 0.5), fx)
		m.Shape = Enum.PartType.Ball
		table.insert(motes, m)
		table.insert(moteFx, emitter(m, true))
		local s = invisible("Sparks" .. i, Vector3.new(0.2, 0.2, 0.2), fx)
		s.Shape = Enum.PartType.Ball
		table.insert(sparks, s)
		table.insert(sparkFx, emitter(s, false))
	end
	return {
		Folder = folder,
		Holder = holder,
		Backdrop = backdrop,
		Surface = surface,
		KeyPart = keyPart,
		KeyLight = keyLight,
		RimPart = rimPart,
		RimLight = rimLight,
		Motes = motes,
		MoteFx = moteFx,
		Sparks = sparks,
		SparkFx = sparkFx,
		MoteAt = {},
		SparkAt = {},
		Sink = { Parts = {}, Frames = {} },
		Space = CFrame.new(),
		Fov = HatchFx.Fov,
		DepthK = 1,
		Least = HatchWorld.DepthLeast,
		Most = HatchWorld.DepthMost,
		BackFar = HatchWorld.BackdropMost,
		Back = HatchWorld.BackdropDepth,
		Lift = 0,
		Bulk = o.Bulk or function(parts: { BasePart }, frames: { CFrame })
			for i, part in parts do
				part.CFrame = frames[i]
			end
		end,
		Emit = o.Emit or function(e: ParticleEmitter, count: number)
			pcall(function()
				e:Emit(count)
			end)
		end,
		Parent = o.Parent,
		Shown = false,
	}
end

local function tanHalf(fov: number): number
	return math.tan(math.rad(math.clamp(fov, 1, 120) / 2))
end

-- The stage's depths at FieldOfView `fov` against at HatchFx.Fov: a point that far keeps its spot of the screen.
function HatchWorld.depthK(fov: number): number
	return tanHalf(HatchFx.Fov) / tanHalf(fov)
end

-- In the world while an opening plays (the particles stop when it goes).
function HatchWorld.show(world: World, on: boolean)
	world.Shown = on
	world.Folder.Parent = if on then world.Parent else nil
	if not on then
		HatchWorld.clear(world)
	end
end

--[[
	A frame starts: the camera now (its CFrame and FieldOfView; `near`: its
	near clipping plane's distance, `reach`: how far its focus, the player,
	is; nil: none known) and the band the stage stands in this frame.
]]
function HatchWorld.begin(world: World, space: CFrame, fov: number, near: number?, reach: number?)
	world.Space = space
	world.Fov = fov
	world.DepthK = HatchWorld.depthK(fov)
	local least = math.max(HatchWorld.DepthLeast, HatchWorld.NearMargin * math.abs(near or 0))
	local far = if reach and reach == reach and reach > 0 then reach else math.huge
	world.Least = least
	world.Most = math.clamp(HatchWorld.FocusShare * far, least, HatchWorld.DepthMost)
	world.BackFar = math.clamp(HatchWorld.BackShare * far, world.Most + 0.25, HatchWorld.BackdropMost)
	table.clear(world.Sink.Parts)
	table.clear(world.Sink.Frames)
end

-- A stage CFrame (HatchFx's camera space) in the world this frame.
function HatchWorld.toWorld(world: World, cf: CFrame): CFrame
	local p = cf.Position
	return world.Space * (cf - p + Vector3.new(p.X, p.Y, p.Z * world.DepthK))
end

-- How far a stage depth is in the world this frame (studs from the camera).
function HatchWorld.liveDepth(world: World, depth: number): number
	return depth * world.DepthK
end

function HatchWorld.place(world: World, rig: HatchRig.Rig, cf: CFrame, top: CFrame?, bottom: CFrame?, size: number?)
	HatchRig.place(rig, HatchWorld.toWorld(world, cf), top, bottom, world.Sink, size)
end

--[[
	Moves this frame's poses (one BulkMoveTo), the backdrop (it fills the
	view `aspect` wide, BackdropBehind behind the farthest model: `farthest`,
	studs of stage depth) and the lights.
]]
function HatchWorld.flush(world: World, aspect: number, farthest: number)
	local sink = world.Sink
	-- (the motes and sparks still flying keep to the stage: their particles are locked to these parts)
	for slot, cf in world.MoteAt do
		table.insert(sink.Parts, world.Motes[slot])
		table.insert(sink.Frames, HatchWorld.toWorld(world, cf))
	end
	for slot, cf in world.SparkAt do
		table.insert(sink.Parts, world.Sparks[slot])
		table.insert(sink.Frames, HatchWorld.toWorld(world, cf))
	end
	if #sink.Parts > 0 then
		world.Bulk(sink.Parts, sink.Frames)
		table.clear(sink.Parts)
		table.clear(sink.Frames)
	end
	local depth = math.clamp(
		HatchWorld.liveDepth(world, farthest) * HatchWorld.BackdropBehind,
		math.min(HatchWorld.BackdropDepth, world.BackFar),
		world.BackFar
	)
	world.Back = depth
	local t = tanHalf(world.Fov)
	local a = if aspect == aspect and aspect > 0 then aspect else 16 / 9
	world.Backdrop.Size = Vector3.new(2 * depth * t * a, 2 * depth * t, 0.02)
	-- (its Front face toward the camera: the SurfaceGui reads upright, left to right)
	world.Backdrop.CFrame = world.Space * CFrame.new(0, 0, -depth) * CFrame.Angles(0, math.pi, 0)
	-- (the lights keep their places against the stage: further and wider as it stands further)
	local f = depth / HatchWorld.BackdropDepth
	local key = HatchWorld.Key
	world.KeyPart.CFrame = world.Space * CFrame.lookAt(key.Position * f, key.Aim * f)
	world.RimPart.CFrame = world.Space * CFrame.new(HatchWorld.Rim.Position * f)
	world.KeyLight.Range = key.Range * f
	world.RimLight.Range = HatchWorld.Rim.Range * f
end

-- The SurfaceGui's canvas: the opening's screen in design units (its layout lands where it did on the screen).
function HatchWorld.canvas(world: World, size: Vector2)
	if world.Surface.CanvasSize ~= size then
		world.Surface.CanvasSize = size
	end
end

-- (V2) A Mythic's stage light: the key and rim lights lift and drift through the rainbow (`lift` 0..1).
function HatchWorld.setLight(world: World, lift: number, hue: number)
	local k = math.clamp(if lift == lift then lift else 0, 0, 1)
	if k <= 0 and world.Lift <= 0 then
		return
	end
	world.Lift = k
	world.KeyLight.Color = HatchWorld.KeyColor:Lerp(Color3.fromHSV(hue % 1, 0.3, 1), k * 0.8)
	world.RimLight.Color = HatchWorld.RimColor:Lerp(Color3.fromHSV((hue + 0.5) % 1, 0.4, 1), k)
	world.KeyLight.Brightness = HatchWorld.Key.Brightness * (1 + 0.25 * k)
	world.RimLight.Brightness = HatchWorld.Rim.Brightness * (1 + 0.4 * k)
end

--[[
	Slot `slot`'s motes: a sphere shell `radius` studs round its egg's
	middle (`cf`, stage space) emitting inward, `rate` a second, in `color`
	(0: none). Posed every frame (the rate follows the charge).
]]
function HatchWorld.energy(world: World, slot: number, cf: CFrame, radius: number, rate: number, color: Color3)
	local part, e = world.Motes[slot], world.MoteFx[slot]
	if not part or not e then
		return
	end
	if rate <= 0 then
		if e.Rate ~= 0 then
			e.Rate = 0
		end
		return
	end
	local r = math.max(0.01, radius)
	world.MoteAt[slot] = cf
	part.Size = Vector3.new(2 * r, 2 * r, 2 * r)
	e.Rate = rate
	-- (they reach the middle as they fade: the shell's radius over their life)
	e.Speed = NumberRange.new(r / 0.5, r / 0.42)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, r * 0.05),
		NumberSequenceKeypoint.new(0.7, r * 0.04),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), HatchWorld.White), color)
end

--[[
	Sparks out of slot `slot` now: `count` of them from a ball `radius`
	studs round `cf` (stage space), in `color` and white, slowing as they
	go (the burst of an egg, the reveal of its golem).
]]
function HatchWorld.burst(world: World, slot: number, cf: CFrame, radius: number, color: Color3, count: number)
	local part, e = world.Sparks[slot], world.SparkFx[slot]
	if not part or not e or count <= 0 then
		return
	end
	local r = math.max(0.01, radius)
	-- (moved now, not with the frame's poses: they leave from where it is when they're made; then
	-- it rides with the stage, flush)
	part.CFrame = HatchWorld.toWorld(world, cf)
	world.SparkAt[slot] = cf
	part.Size = Vector3.new(2 * r, 2 * r, 2 * r) * 0.35
	e.Speed = NumberRange.new(r * 2.6, r * 6.5)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, r * 0.075),
		NumberSequenceKeypoint.new(0.6, r * 0.05),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Acceleration = Vector3.new(0, -r * 1.6, 0)
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), HatchWorld.SparkWhite)),
		ColorSequenceKeypoint.new(0.25, color),
		ColorSequenceKeypoint.new(1, color),
	})
	world.Emit(e, math.floor(count))
end

-- Between openings: no motes, the sparks gone, the stage light back.
function HatchWorld.clear(world: World)
	for _, e in world.MoteFx do
		e.Rate = 0
		pcall(function()
			e:Clear()
		end)
	end
	for _, e in world.SparkFx do
		pcall(function()
			e:Clear()
		end)
	end
	table.clear(world.MoteAt)
	table.clear(world.SparkAt)
	world.Lift = 0
	world.KeyLight.Color = HatchWorld.KeyColor
	world.RimLight.Color = HatchWorld.RimColor
	world.KeyLight.Brightness = HatchWorld.Key.Brightness
	world.RimLight.Brightness = HatchWorld.Rim.Brightness
end

return HatchWorld
