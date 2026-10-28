--[[
	RockFx: the juicy breaking animation of mine rocks (client only; the math
	is in RockFxLogic so the previews show the same motion).

	  RockFx.shake(rock)      a tiny tremble while the rock is blasted (any shooter)
	  RockFx.crack(...)       a crack stage: dust in the rock color, glowing shards
	                          in the stage's ore glow, a flash, the crack sound, a
	                          punch of the rock
	  RockFx.shatter(...)     the last stage: rock chunks and crystal shards fly
	                          out, bounce and fade, dust puff, flash, a ground ring,
	                          sound, camera shake (stronger for the shooter, Giant
	                          Crystals bigger)
	  RockFx.chips(...)       a few chips knocked off by one hit (MineJuiceController)

	Phones: debris parts are pooled (anchored, no collisions, no shadows), at
	most RockFxLogic.Cap = 30 alive (plus at most RockFxLogic.ChipCap = 8 hit
	chips with a cap of their own: a busy floor's chips never take the room
	of a crack or a break) and each gone within 1.5 s; at most 3 ground
	rings (16 bars each) and 4 flash lights at once; one RenderStepped
	connection runs only while something moves. The shake moves the rock's
	anchored parts on this client only (the server never sees it) and puts
	them back exactly; at most MAX_SHAKES rocks tremble at once.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RockFxLogic = require(script.Parent.RockFxLogic)
local Vfx = require(script.Parent.Vfx)
local Sfx = require(script.Parent.Sfx)
local CameraShake = require(script.Parent.CameraShake)

local RockFx = {}

local ROCK_TAG = "Rock"
local PARK = CFrame.new(0, -5000, 0)
local MAX_SHAKES = 3
local SHAKE_VIEW = 70 -- rocks farther from the camera than this don't tremble
local SHAKE_GAP = 0.12 -- a rock re-kicks its tremble at most this often
local SHAKE_TIME = 0.22
local SHAKE_RANGE = 30 -- cracks farther from the camera than this don't shake it
local SHOOTER_TIME = 0.8 -- seconds a blasted rock still counts as "yours" for the shatter shake
local WHITE = Color3.new(1, 1, 1)
local RING_BARS = 16 -- the ground ring is drawn with this many thin neon bars
local MAX_RINGS = 3 -- at once (many rocks breaking together skip the extra rings)
local MAX_FLASHES = 4 -- flash lights at once

type Live = { Part: BasePart, Piece: RockFxLogic.Piece, Born: number, Scale: number, Fade: number, Chip: boolean }
type Flash = { Part: BasePart, Light: PointLight, Born: number, Duration: number, Peak: number }
type Ring = { Parts: { BasePart }, Born: number, Duration: number, R0: number, R1: number, Center: Vector3, Width: number }
type Shake = { Parts: { BasePart }, Base: { CFrame }, Pivot: CFrame, Born: number, Duration: number, Strength: number, Seed: number }

local idle: { [boolean]: { BasePart } } = { [true] = {}, [false] = {} } -- wedge? -> parked parts
local live: { Live } = {}
local flashPool: { Flash } = {}
local ringPool: { Ring } = {}
local flashes: { Flash } = {}
local rings: { Ring } = {}
local shakes: { [Model]: Shake } = {}
local lastShake: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local connection: RBXScriptConnection? = nil
local shooterAt: Vector3? = nil
local shooterRock: Model? = nil
local chipsAlive = 0 -- hit chips among `live` (their own cap)
local shooterClock = -math.huge
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

---------------------------------------------------------------- pools

local function newPart(wedge: boolean): BasePart
	local part: BasePart = if wedge then Instance.new("WedgePart") :: BasePart else Instance.new("Part") :: BasePart
	part.Name = "RockDebris"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = PARK
	part.Parent = Vfx.folder()
	return part
end

local function park(part: BasePart, wedge: boolean)
	part.Transparency = 1
	part.CFrame = PARK
	table.insert(idle[wedge], part)
end

local function takeFlash(): Flash
	local item = table.remove(flashPool)
	if item and item.Part.Parent then
		return item
	end
	local part = Instance.new("Part")
	part.Name = "RockFlash"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = Vfx.folder()
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Enabled = false
	light.Parent = part
	return { Part = part, Light = light, Born = 0, Duration = 0.2, Peak = 1 }
end

local function takeRing(): Ring
	local item = table.remove(ringPool)
	if item and item.Parts[1].Parent then
		return item
	end
	local parts: { BasePart } = {}
	for i = 1, RING_BARS do
		local part = Instance.new("Part")
		part.Name = "RockRing" .. i
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Transparency = 1
		part.CFrame = PARK
		part.Parent = Vfx.folder()
		table.insert(parts, part)
	end
	return { Parts = parts, Born = 0, Duration = 0.4, R0 = 1, R1 = 2, Center = Vector3.zero, Width = 0.3 }
end

---------------------------------------------------------------- frame loop

local step: (number) -> ()

local function ensureLoop()
	if not connection then
		connection = RunService.RenderStepped:Connect(function(dt: number)
			step(dt)
		end)
	end
end

-- Moves a trembling rock's parts to `m` * their resting frames (identity = back home).
local function placeShake(rock: Model, shake: Shake, m: CFrame)
	table.clear(moveParts)
	table.clear(moveFrames)
	if rock.Parent then
		for i, part in shake.Parts do
			-- skip pieces the server broke off (unanchored) or removed
			if part.Parent and part.Anchored then
				table.insert(moveParts, part)
				table.insert(moveFrames, m * shake.Base[i])
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function stepShakes(now: number)
	for rock, shake in shakes do
		local t = now - shake.Born
		if t >= shake.Duration or not rock.Parent then
			placeShake(rock, shake, CFrame.identity)
			shakes[rock] = nil
		else
			local offset = RockFxLogic.shakeOffset(t, shake.Duration, shake.Strength, shake.Seed)
			placeShake(rock, shake, shake.Pivot * offset * shake.Pivot:Inverse())
		end
	end
end

step = function(_dt: number)
	local now = os.clock()
	-- debris
	table.clear(moveParts)
	table.clear(moveFrames)
	local i = 1
	while i <= #live do
		local item = live[i]
		local cf, scale, transparency, done = RockFxLogic.sample(item.Piece, now - item.Born)
		if done or not item.Part.Parent then
			if item.Part.Parent then
				park(item.Part, item.Piece.Wedge)
			end
			if item.Chip then
				chipsAlive -= 1
			end
			live[i] = live[#live]
			live[#live] = nil
		else
			table.insert(moveParts, item.Part)
			table.insert(moveFrames, cf)
			if math.abs(scale - item.Scale) > 0.04 then
				item.Scale = scale
				item.Part.Size = item.Piece.Size * scale
			end
			if math.abs(transparency - item.Fade) > 0.04 then
				item.Fade = transparency
				item.Part.Transparency = transparency
			end
			i += 1
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- flash lights
	for k = #flashes, 1, -1 do
		local flash = flashes[k]
		local t = now - flash.Born
		if t >= flash.Duration then
			flash.Light.Enabled = false
			table.insert(flashPool, flash)
			table.remove(flashes, k)
		else
			flash.Light.Brightness = flash.Peak * RockFxLogic.flash(t, flash.Duration)
		end
	end
	-- ground rings
	for k = #rings, 1, -1 do
		local ring = rings[k]
		local t = now - ring.Born
		if t >= ring.Duration then
			for _, part in ring.Parts do
				part.Transparency = 1
				part.CFrame = PARK
			end
			table.insert(ringPool, ring)
			table.remove(rings, k)
		else
			local diameter, transparency = RockFxLogic.ring(t, ring.Duration, ring.R0, ring.R1)
			local frames, length = RockFxLogic.ringSegments(ring.Center, diameter, #ring.Parts)
			local size = Vector3.new(ring.Width, 0.12, length)
			for _, part in ring.Parts do
				part.Size = size
				part.Transparency = transparency
			end
			Workspace:BulkMoveTo(ring.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	stepShakes(now)
	if #live == 0 and #flashes == 0 and #rings == 0 and next(shakes) == nil then
		local current = connection
		connection = nil
		if current then
			current:Disconnect()
		end
	end
end

---------------------------------------------------------------- pieces

-- `chip`: hit chips (under RockFxLogic.ChipCap); everything else under RockFxLogic.Cap.
local function spawn(pieces: { RockFxLogic.Piece }, chip: boolean?)
	local now = os.clock()
	local isChip: boolean = chip == true
	for _, piece in pieces do
		if (isChip and chipsAlive >= RockFxLogic.ChipCap) or (not isChip and #live - chipsAlive >= RockFxLogic.Cap) then
			break
		end
		local part = table.remove(idle[piece.Wedge]) or newPart(piece.Wedge)
		if not part.Parent then
			part = newPart(piece.Wedge)
		end
		part.Size = piece.Size * 0.5
		part.Color = piece.Color
		part.Material = if piece.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Transparency = 0
		part.CFrame = (RockFxLogic.sample(piece, 0))
		local item: Live = { Part = part, Piece = piece, Born = now, Scale = 0.5, Fade = 0, Chip = isChip }
		table.insert(live, item)
		if isChip then
			chipsAlive += 1
		end
	end
	if #live > 0 then
		ensureLoop()
	end
end

local function flashAt(position: Vector3, color: Color3, peak: number, range: number, duration: number)
	if #flashes >= MAX_FLASHES then
		return
	end
	local flash = takeFlash()
	flash.Part.CFrame = CFrame.new(position)
	flash.Light.Color = color
	flash.Light.Range = math.min(range, 60)
	flash.Light.Brightness = 0
	flash.Light.Enabled = true
	flash.Born = os.clock()
	flash.Duration = duration
	flash.Peak = peak
	table.insert(flashes, flash)
	ensureLoop()
end

local function ringAt(position: Vector3, color: Color3, r0: number, r1: number, duration: number, width: number)
	if #rings >= MAX_RINGS then
		return
	end
	local ring = takeRing()
	for _, part in ring.Parts do
		part.Color = color
	end
	ring.Center = position
	ring.Width = width
	ring.R0, ring.R1 = r0, r1
	ring.Born = os.clock()
	ring.Duration = duration
	table.insert(rings, ring)
	ensureLoop()
end

---------------------------------------------------------------- helpers

-- The tagged rock whose PrimaryPart is nearest to `position` (within `maxDistance`).
function RockFx.rockNear(position: Vector3, maxDistance: number): Model?
	local best: Model? = nil
	local bestDistance = maxDistance
	for _, rock in CollectionService:GetTagged(ROCK_TAG) do
		if rock:IsA("Model") and rock.PrimaryPart then
			local distance = (rock.PrimaryPart.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = rock, distance
			end
		end
	end
	return best
end

-- Shakes the camera for things happening close to it.
function RockFx.shakeNear(position: Vector3, amount: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	if distance < SHAKE_RANGE then
		CameraShake.add(amount * (1 - distance / SHAKE_RANGE * 0.6))
	end
end

-- MiningController: the local player's beam is on this rock now (the shatter shakes the shooter's camera).
function RockFx.markShooter(rock: Model?)
	local primary = rock and rock.PrimaryPart
	if primary then
		shooterAt = primary.Position
		shooterRock = rock
		shooterClock = os.clock()
	end
end

-- Is the local player's beam on this rock (now or within the last SHOOTER_TIME)?
function RockFx.isMine(rock: Model): boolean
	return shooterRock == rock and os.clock() - shooterClock < SHOOTER_TIME
end

function RockFx.wasMine(position: Vector3, radius: number): boolean
	local at = shooterAt
	return at ~= nil and os.clock() - shooterClock < SHOOTER_TIME and (at - position).Magnitude <= radius + 4
end

-- The ground under a point (the debris bounces on it); `fallback` when nothing is below.
local function groundBelow(position: Vector3, depth: number, fallback: number, ignore: Instance?): number
	local list: { Instance } = { Vfx.folder() }
	for _, name in { "Debris", "Items" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	if ignore then
		table.insert(list, ignore)
	end
	rayParams.FilterDescendantsInstances = list
	local result = Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -(depth + 1), 0), rayParams)
	return if result then result.Position.Y else fallback
end

-- Toward the camera, flat (crack shards spray at the viewer).
local function towardCamera(position: Vector3): Vector3
	local camera = Workspace.CurrentCamera
	local offset = if camera then camera.CFrame.Position - position else Vector3.new(0, 0, 1)
	return Vector3.new(offset.X, 0, offset.Z)
end

---------------------------------------------------------------- effects

--[[
	A tiny tremble of a rock being hit (call it on every hit; it re-kicks
	itself). `fresh` (crack stages) puts the rock back and collects its parts
	again, so the glowing cracks the server just added tremble with it.
]]
function RockFx.shake(rock: Model, strength: number?, duration: number?, fresh: boolean?)
	local now = os.clock()
	local primary = rock.PrimaryPart
	if not primary or not rock.Parent then
		return
	end
	local power = strength or (if rock:GetAttribute("Kind") == "Giant" then 0.1 else 0.07)
	local current: Shake? = shakes[rock]
	if current and fresh then
		placeShake(rock, current, CFrame.identity)
		shakes[rock] = nil
		current = nil
	end
	if current then
		if now - (lastShake[rock] or 0) >= SHAKE_GAP or power > current.Strength then
			lastShake[rock] = now
			current.Born = now
			current.Strength = math.max(power, current.Strength * 0.6)
			current.Duration = duration or SHAKE_TIME
		end
		return
	end
	local count = 0
	for _ in shakes do
		count += 1
	end
	local camera = Workspace.CurrentCamera
	if count >= MAX_SHAKES or (camera and (camera.CFrame.Position - primary.Position).Magnitude > SHAKE_VIEW) then
		return
	end
	local parts: { BasePart } = {}
	local base: { CFrame } = {}
	for _, d in rock:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored then
			table.insert(parts, d)
			table.insert(base, d.CFrame)
		end
	end
	lastShake[rock] = now
	shakes[rock] = {
		Parts = parts,
		Base = base,
		Pivot = rock:GetPivot(),
		Born = now,
		Duration = duration or SHAKE_TIME,
		Strength = power,
		Seed = math.random() * 100,
	}
	ensureLoop()
end

--[[
	A crack stage: (hit position, rock color, stage, ore glow?, stage count?).
	Old servers send only the first three: the glow is then a lighter crust.
]]
function RockFx.crack(position: Vector3, crust: Color3, stage: number, glow: Color3?, stages: number?)
	local glowColor = glow or crust:Lerp(WHITE, 0.5)
	local total = stages or 3
	local last = stage >= total - 1
	local rock = RockFx.rockNear(position, 10)
	local ground = groundBelow(position, 12, position.Y - 2, rock)
	Vfx.burst("Dust", position, if last then 10 else 7, crust)
	Vfx.burst("Glint", position, 6, glowColor:Lerp(WHITE, 0.3))
	Vfx.burst("Sparks", position, 8, glowColor, towardCamera(position) + Vector3.new(0, 2, 0))
	Vfx.flash(position, glowColor, if last then 4 else 3.2)
	flashAt(position, glowColor, if last then 3.5 else 2.6, 14, 0.22)
	spawn(RockFxLogic.crackPlan({
		Position = position,
		Crust = crust,
		Glow = glowColor,
		Stage = stage,
		Stages = total,
		Out = towardCamera(position),
		Ground = ground,
		Alive = #live - chipsAlive,
		Seed = os.clock() * 1000,
	}))
	if rock then
		RockFx.shake(rock, 0.15, 0.28, true)
	end
	Sfx.play("NodeCrack", position, 0.9 + 0.08 * math.clamp(stage, 0, 4))
	RockFx.shakeNear(position, if last then 0.3 else 0.2)
end

--[[
	The shatter: (rock center, rock color, ore glow, floor?, kind?, radius?).
	Old servers send only the first three: colors then come from crust / glow.
]]
function RockFx.shatter(position: Vector3, crust: Color3, glow: Color3, floor: number?, kind: string?, radius: number?)
	local giant = kind == "Giant"
	local r = radius or (if giant then 7 else 2.5)
	local colors = RockFxLogic.colors(floor, kind, crust, glow)
	local ground = groundBelow(position, r * 2 + 8, position.Y - r * 0.6, RockFx.rockNear(position, r + 2))
	spawn(RockFxLogic.shatterPlan({
		Position = position,
		Crust = crust,
		Glow = glow,
		Floor = floor,
		Kind = kind,
		Radius = r,
		Ground = ground,
		Alive = #live - chipsAlive,
		Seed = os.clock() * 1000,
	}))
	local floorPoint = Vector3.new(position.X, ground + 0.2, position.Z)
	Vfx.burst("Dust", position, if giant then 26 else 16, colors.Rock[2])
	Vfx.burst("Dust", floorPoint + Vector3.new(0, 0.6, 0), if giant then 14 else 8, colors.Rock[1])
	Vfx.burst("Burst", position, if giant then 30 else 18, glow)
	Vfx.burst("Glint", position + Vector3.new(0, r * 0.4, 0), if giant then 14 else 8, colors.Crystal[1]:Lerp(WHITE, 0.3))
	Vfx.flash(position, glow:Lerp(WHITE, 0.25), if giant then 16 else 8)
	flashAt(position, glow, if giant then 7 else 4, r * 4 + 6, if giant then 0.45 else 0.3)
	ringAt(
		floorPoint,
		colors.Crystal[1]:Lerp(WHITE, 0.2),
		r * 0.6,
		r * (if giant then 1.9 else 2.2),
		if giant then 0.5 else 0.38,
		if giant then 0.6 else 0.3
	)
	Sfx.play("NodeShatter", position, if giant then 0.7 else 1)
	Sfx.play("RockBreak", position, if giant then 0.75 else 1)
	Sfx.play("Crusher", position, if giant then 0.7 else 1.15)
	if RockFx.wasMine(position, r) then
		CameraShake.add(if giant then 0.6 else 0.4)
	else
		RockFx.shakeNear(position, if giant then 0.45 else 0.28)
	end
end

--[[
	The chips of one hit (MineJuiceController, Config/JuiceConfig Chips): a
	few small chips in the crust colour fly out of the face at `position`
	along `out` (the face normal), from the same pool under their own cap
	(RockFxLogic.ChipCap: never the room of a crack or a break). `rock` (the
	one hit) is left out of the ground ray.
]]
function RockFx.chips(position: Vector3, crust: Color3, out: Vector3?, count: number?, rock: Instance?)
	if chipsAlive >= RockFxLogic.ChipCap then
		return
	end
	spawn(
		RockFxLogic.chipPlan({
			Position = position,
			Crust = crust,
			Out = out,
			Count = count,
			Ground = groundBelow(position, 10, position.Y - 2, rock),
			Alive = chipsAlive,
			Seed = os.clock() * 1000,
		}),
		true
	)
end

-- Debris pieces alive now (tests / debug overlay).
function RockFx.alive(): number
	return #live
end

return RockFx
