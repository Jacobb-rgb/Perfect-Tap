--[[
	WorldMotionController: the world animations (owner 2026-10-21: "perfect
	animations in the game world"). Client only; the math is in
	Effects/WorldMotionLogic, which the showreel preview runs too.

	- Golem followers: GolemController calls golemOffset(pet, owner, now,
	  walking, near) once per follower per frame (one line in its step) and
	  multiplies the CFrame onto the golem: rounder hops with a wiggle and a
	  nod while walking; a sway and now and then a little hop in place,
	  turning left and right ("waving"), while standing; the happy jump with
	  a spin when the golem was just equipped (its owner's EquippedGolems
	  attribute gained that kind and the model was built within EquipWindow
	  seconds; a golem built because you walked up to its owner doesn't
	  jump). Premium golems (Legendary, Mythic) keep their hover: they rise
	  and spin, never hop.
	- Ore popping out of a rock: a Raw chunk that appears in Workspace.Items
	  within MatchWindow seconds and MatchRange studs of a NodeCrack /
	  NodeShatter Fx (whichever arrives first) pops: dust cubes puff out, its
	  real parts are hidden on this client only (LocalTransparencyModifier)
	  and a pooled look-alike follows the real body with a visual arc on
	  top, one extra spin, a pop-in scale and a squash when it lands (more
	  dust). The physics are never touched: the look-alike is anchored and
	  collides with nothing, and the real chunk shows again the moment the
	  pop ends, it is picked up or it goes.
	- Hit: a short white impact flash, a star of white spikes and small
	  cubes in the rock's ore colour (the crystal colour the rock shows:
	  never the secret ores inside). Your own hits: each Health drop of the
	  rock your beam is on (RockLabels.onHealthDrop, about 3 a second) at
	  the beam's end; other players' hits: their BlastHit Fx. BlasterFx keeps
	  its sparks, glints, crust chips, rings and sounds: this only adds what
	  was missing.
	- Sell: Earned { Source = "Sell" } (SellService, LogisticsService):
	  green banknotes flutter out of the sell spot and gold coins burst up
	  and fly into you when you're near (SellController keeps its +$ popup).

	Perf (phones first): every part is pooled (anchored, no collisions, no
	queries, no touches, no shadows) and moved with one BulkMoveTo from one
	RenderStepped connection that only runs while something moves; at most
	Caps.Bits bits, Caps.Pops pops and Caps.Flashes flashes at once (half on
	phones); effects farther than their range from the camera or off screen
	are skipped; the frame loop makes no tables. Reduce motion (the SETTINGS
	ReduceMotion toggle when SettingsConfig has one, or Roblox's own
	GuiService.ReducedMotionEnabled): half the bits, no pop look-alike, no
	spikes, no spins, golems only do a small hop on equip.
	No inputs are bound here.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig)
local Net = require(Shared.Net)
local Logic = require(script.Parent.Parent.Effects.WorldMotionLogic)
local RockFxLogic = require(script.Parent.Parent.Effects.RockFxLogic)
local BlasterFx = require(script.Parent.Parent.Effects.BlasterFx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)

local WorldMotionController = {}

WorldMotionController.EquipWindow = 3 -- seconds: a follower built this soon after its kind was equipped jumps
WorldMotionController.MatchWindow = 1.2 -- seconds between a crack / shatter and its chunk appearing
WorldMotionController.MatchRange = 16 -- studs between them
WorldMotionController.PopRange = 90 -- studs from the camera
WorldMotionController.HitRange = 80
WorldMotionController.SellRange = 110
WorldMotionController.OwnRange = 70 -- your beam's reach plus a margin
WorldMotionController.MaxPopParts = 8 -- a look with more parts only gets the dust

-- a test or preview rig instead of the camera, the device and the clock
export type Rig = {
	Folder: Instance,
	Eye: Vector3,
	Right: Vector3,
	Up: Vector3,
	Ground: number,
	Clock: number,
	Phone: boolean,
	Reduce: boolean,
	Firing: boolean,
	Root: Vector3?, -- the local player's position (coins fly there)
	Gravity: number,
	Rocks: { Model }?, -- the tagged rocks (stand-in for the Rock tag)
}

-- the fields of GolemController's follower it reads
export type GolemPet = { Kind: string, Phase: number, Seed: number, Floats: boolean }

type Live = { Bit: Logic.Bit, Part: BasePart, Pool: Logic.Pool, Size: Vector3, Transparency: number }
type Proxy = { Part: BasePart, Pool: Logic.Pool, Offset: CFrame, Size: Vector3 }
type Pop = {
	Model: Model,
	Body: BasePart,
	Real: { BasePart },
	Saved: { number }, -- their LocalTransparencyModifier before the pop (put back after)
	Proxies: { Proxy },
	Born: number,
	Flight: number,
	Landed: number?,
	LastVy: number,
	Half: number, -- half the look's height (the squash keeps its bottom on the ground)
	Dust: Color3,
	Seed: number,
	Scaled: boolean, -- sizes were written last frame (scale ~= 1)
}
type Drop = { At: number, Position: Vector3, Crust: Color3? }
type Fresh = { At: number, Model: Model? }
type PetState = { Celebrate: number? }

local PARK = CFrame.new(0, -5000, 0)
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local DUST = Color3.fromRGB(176, 156, 134)
local DEFAULT_ORE = Color3.fromRGB(120, 200, 255)
local RING = 8 -- crack / chunk records kept for matching

local rig: Rig? = nil
local caps: Logic.Caps = Logic.caps(false, false)
local reduceOn = false
local reduceAt = -math.huge
local phoneOn: boolean? = nil
local settingsModule: any = nil
local settingsTried = false
local folder: Instance? = nil

local pools: { [string]: Logic.Pool } = {}
local live: { Live } = {}
local pops: { Pop } = {}
local flashes = 0
local connection: RBXScriptConnection? = nil
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local seedCounter = 0

local drops: { Drop } = {}
local fresh: { Fresh } = {}
local nextDrop, nextFresh = 1, 1
local popped: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local rockColours: { [Model]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
local lastHit: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local petStates: { [any]: PetState } = setmetatable({}, { __mode = "k" }) :: any
local equipTimes: { [Player]: { [string]: { number } } } = setmetatable({}, { __mode = "k" }) :: any
local equipCounts: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local homing = 0 -- coins alive that fly into the player
-- the tagged rocks, kept by the Rock tag's added / removed signals (no GetTagged per hit)
local rockSet: { [Model]: boolean } = {}
local rockScans = 0 -- how often rockNear ran (tests: only after the cheap checks)
local rayParams: RaycastParams? = nil
local includeParams: RaycastParams? = nil

for i = 1, RING do
	drops[i] = { At = -math.huge, Position = Vector3.zero, Crust = nil }
	fresh[i] = { At = -math.huge, Model = nil }
end

---------------------------------------------------------------- environment

local function now(): number
	local r = rig
	return if r then r.Clock else os.clock()
end

local function isPhone(): boolean
	local r = rig
	if r then
		return r.Phone
	end
	local cached = phoneOn
	if cached == nil then
		cached = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		phoneOn = cached
	end
	return cached == true
end

-- The SETTINGS ReduceMotion toggle (when SettingsConfig has one) or Roblox's own reduced motion; read once a second.
local function reduceMotion(): boolean
	local r = rig
	if r then
		return r.Reduce
	end
	local t = os.clock()
	if t - reduceAt < 1 then
		return reduceOn
	end
	reduceAt = t
	if not settingsTried then
		settingsTried = true
		local module = script.Parent:FindFirstChild("SettingsController")
		if module and module:IsA("ModuleScript") then
			local ok, controller = pcall(require, module :: any)
			if ok and type(controller) == "table" and type((controller :: any).get) == "function" then
				settingsModule = controller
			end
		end
	end
	local on = false
	local settings = settingsModule
	if settings then
		local ok, value = pcall(function()
			return (settings.get() :: any).ReduceMotion
		end)
		on = ok and value == true
	end
	if not on then
		local ok, value = pcall(function()
			return GuiService.ReducedMotionEnabled
		end)
		on = ok and value == true
	end
	reduceOn = on
	return on
end

local function refreshCaps(): Logic.Caps
	caps = Logic.caps(isPhone(), reduceMotion())
	return caps
end

local function fxFolder(): Instance
	local r = rig
	if r then
		return r.Folder
	end
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Vfx.folder()
	folder = made
	return made
end

local function localPlayer(): Player?
	return Players.LocalPlayer
end

local function rootPosition(): Vector3?
	local r = rig
	if r then
		return r.Root
	end
	local p = localPlayer()
	local character = p and p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Is `position` within `range` of the camera and on screen (with a margin)?
local function visible(position: Vector3, range: number): boolean
	local r = rig
	if r then
		return (position - r.Eye).Magnitude <= range
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	if (camera.CFrame.Position - position).Magnitude > range then
		return false
	end
	local screen, onScreen = camera:WorldToViewportPoint(position)
	if onScreen then
		return true
	end
	if screen.Z <= 0 then
		return false
	end
	local size = camera.ViewportSize
	local mx, my = size.X * 0.15, size.Y * 0.15
	return screen.X > -mx and screen.X < size.X + mx and screen.Y > -my and screen.Y < size.Y + my
end

-- The camera's right and up (the hit star faces the viewer).
local function cameraBasis(): (Vector3, Vector3)
	local r = rig
	if r then
		return r.Right, r.Up
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return Vector3.xAxis, Vector3.yAxis
	end
	return camera.CFrame.RightVector, camera.CFrame.UpVector
end

-- The ground under a point (bits bounce on it); a few studs down when nothing is there.
local function groundBelow(position: Vector3): number
	local r = rig
	if r then
		return r.Ground
	end
	local params = rayParams
	if not params then
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Exclude
		made.RespectCanCollide = true
		params = made
		rayParams = made
	end
	local list: { Instance } = { fxFolder() }
	local items = Workspace:FindFirstChild("Items")
	if items then
		table.insert(list, items)
	end
	local p = localPlayer()
	if p and p.Character then
		table.insert(list, p.Character)
	end
	local ray = params :: RaycastParams
	ray.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(position + Vector3.new(0, 0.5, 0), Vector3.new(0, -14, 0), ray)
	return if hit then hit.Position.Y else position.Y - 3
end

local function gravity(): number
	local r = rig
	if r then
		return r.Gravity
	end
	return Workspace.Gravity
end

local function nextSeed(): number
	seedCounter += 1
	return seedCounter * 7.31 + (now() % 100)
end

---------------------------------------------------------------- pools

local function maker(shape: Enum.PartType): () -> BasePart
	return function(): BasePart
		local part = Instance.new("Part")
		part.Name = "WorldMotion"
		part.Shape = shape
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = SMOOTH
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = 1
		part.CFrame = PARK
		part.Parent = fxFolder()
		return part
	end
end

local function poolOf(shape: string): Logic.Pool
	local pool = pools[shape]
	if pool then
		return pool
	end
	local pc = Logic.Caps.PC
	local made: Logic.Pool
	if shape == "Ball" then
		made = Logic.newPool(maker(Enum.PartType.Ball), pc.Flashes + 2)
	elseif shape == "Cylinder" then
		made = Logic.newPool(maker(Enum.PartType.Cylinder), Logic.Cash.Coins[2] * 2)
	else
		-- bits plus the pop look-alikes
		made = Logic.newPool(maker(Enum.PartType.Block), pc.Bits + pc.Pops * WorldMotionController.MaxPopParts)
	end
	pools[shape] = made
	return made
end

local function park(part: BasePart, pool: Logic.Pool)
	part.Transparency = 1
	part.CFrame = PARK
	Logic.give(pool, part)
end

---------------------------------------------------------------- the loop

local step: (dt: number) -> boolean

local function ensureLoop()
	if connection or rig then
		return -- a rig steps by hand
	end
	connection = RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[WorldMotionController] " .. tostring(err))
		end
	end)
end

local function spawnBits(bits: { Logic.Bit })
	local t = now()
	for _, bit in bits do
		if #live >= caps.Bits then
			break
		end
		if bit.Kind == "Flash" and flashes >= caps.Flashes then
			continue
		end
		local pool = poolOf(bit.Shape)
		local part = Logic.take(pool) :: BasePart?
		if not part then
			continue
		end
		if not part.Parent then
			-- the folder went (a test, a reset): make it again
			part.Parent = fxFolder()
		end
		bit.Born = t
		part.Color = bit.Color
		part.Material = if bit.Neon then NEON else SMOOTH
		part.Size = bit.Size
		part.Transparency = 0
		part.CastShadow = false
		if bit.Kind == "Flash" then
			flashes += 1
		elseif bit.Kind == "Coin" and bit.Home ~= nil then
			homing += 1
		end
		table.insert(live, { Bit = bit, Part = part, Pool = pool, Size = bit.Size, Transparency = 0 })
	end
	ensureLoop()
end

local function endPop(index: number)
	local pop = pops[index]
	for _, proxy in pop.Proxies do
		park(proxy.Part, proxy.Pool)
	end
	for i, real in pop.Real do
		if real.Parent then
			real.LocalTransparencyModifier = pop.Saved[i] or 0
		end
	end
	pops[index] = pops[#pops]
	pops[#pops] = nil
end

-- One frame of the look-alike of a popping chunk; false when the pop is over.
local function stepPop(pop: Pop, t: number): boolean
	local body = pop.Body
	local model = pop.Model
	if not body.Parent or not model.Parent or model:GetAttribute("State") ~= "Loose" then
		return false -- gone or picked up: the real chunk shows again
	end
	local age = t - pop.Born
	local vy = body.AssemblyLinearVelocity.Y
	if pop.Landed == nil and age > 0.04 and Logic.landed(pop.LastVy, vy, age, pop.Flight) then
		pop.Landed = age
		local position = body.CFrame.Position
		local ground = position.Y - pop.Half
		spawnBits(Logic.dustPlan({
			Position = position,
			Color = pop.Dust,
			Ground = ground,
			Seed = pop.Seed + 3,
			Landing = true,
			Count = Logic.dustCount(isPhone(), reduceMotion(), true),
			Room = caps.Bits - #live,
		}))
	end
	pop.LastVy = vy
	local lift, spin, wide, tall, done = Logic.popPose(age, pop.Flight, pop.Landed)
	if done then
		return false
	end
	local cf = body.CFrame
	-- squash along the body axis nearest to world up, keeping the bottom down
	local scale = Logic.squashAxes(cf, wide, tall)
	local drop = if pop.Landed then (1 - tall) * pop.Half else 0
	local root = Logic.popRoot(cf, lift, spin, drop)
	local scaled = math.abs(wide - 1) > 0.002 or math.abs(tall - 1) > 0.002
	for _, proxy in pop.Proxies do
		local frame, size = Logic.popPart(root, scale, proxy.Offset, proxy.Size)
		table.insert(moveParts, proxy.Part)
		table.insert(moveFrames, frame)
		if scaled or pop.Scaled then
			proxy.Part.Size = size
		end
	end
	pop.Scaled = scaled
	return true
end

-- (returns true for the pcall in the frame connection)
step = function(_dt: number): boolean
	local t = now()
	table.clear(moveParts)
	table.clear(moveFrames)
	local home = if homing > 0 then rootPosition() else nil
	local i = #live
	while i >= 1 do
		local item = live[i]
		local bit = item.Bit
		if home and bit.Home then
			bit.Home = home + Vector3.new(0, 1, 0)
		end
		local cf, size, transparency, done = Logic.sample(bit, t - bit.Born)
		if done or not item.Part.Parent then
			if bit.Kind == "Flash" then
				flashes -= 1
			elseif bit.Kind == "Coin" and bit.Home ~= nil then
				homing -= 1
			end
			park(item.Part, item.Pool)
			live[i] = live[#live]
			live[#live] = nil
		else
			table.insert(moveParts, item.Part)
			table.insert(moveFrames, cf)
			if (size - item.Size).Magnitude > 0.004 then
				item.Size = size
				item.Part.Size = size
			end
			if math.abs(transparency - item.Transparency) > 0.01 then
				item.Transparency = transparency
				item.Part.Transparency = transparency
			end
		end
		i -= 1
	end
	local p = #pops
	while p >= 1 do
		if not stepPop(pops[p], t) then
			endPop(p)
		end
		p -= 1
	end
	if #moveParts > 0 then
		if rig then
			for k, part in moveParts do
				part.CFrame = moveFrames[k]
			end
		else
			Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	if #live == 0 and #pops == 0 then
		local c = connection
		if c then
			c:Disconnect()
			connection = nil
		end
	end
	return true
end

---------------------------------------------------------------- golems

local function countKinds(value: any): { [string]: number }
	local counts: { [string]: number } = {}
	if type(value) ~= "string" or value == "" then
		return counts
	end
	for i, kind in string.split(value, ",") do
		if i > GolemConfig.EquipSlots then
			break
		end
		counts[kind] = (counts[kind] or 0) + 1
	end
	return counts
end

--[[
	A player's EquippedGolems changed: every kind that gained a golem gets
	an equip time (the next model of that kind GolemController builds
	jumps). The first value seen for a player only counts (joining players
	and golems that were already on don't jump).
]]
function WorldMotionController.noteEquipped(owner: Player, value: any, at: number?)
	local counts = countKinds(value)
	local before = equipCounts[owner]
	equipCounts[owner] = counts
	if not before then
		return
	end
	local t = at or os.clock()
	local times = equipTimes[owner]
	if not times then
		times = {}
		equipTimes[owner] = times
	end
	for kind, n in counts do
		for _ = 1, n - (before[kind] or 0) do
			local list = times[kind]
			if not list then
				list = {}
				times[kind] = list
			end
			table.insert(list, t)
		end
	end
end

-- An equip time of `kind` for `owner` within EquipWindow before `at` (used up), else nil.
local function takeEquip(owner: Player, kind: string, at: number): number?
	local times = equipTimes[owner]
	local list = times and times[kind]
	if not list then
		return nil
	end
	while #list > 0 do
		local t = table.remove(list, 1) :: number
		if at - t <= WorldMotionController.EquipWindow and at >= t - 0.05 then
			return t
		end
	end
	return nil
end

--[[
	The GolemController hook: the extra pose of one follower this frame, to
	multiply onto its CFrame. `pet` is GolemController's follower record
	that reads Kind, Phase, Seed, Floats; `owner` its player, `now` os.clock().
	CFrame.identity when there is nothing to add (far golems, Reduce motion).
]]
function WorldMotionController.golemOffset(pet: GolemPet, owner: Player?, now: number, walking: boolean, near: boolean): CFrame
	local state = petStates[pet]
	if not state then
		local celebrate: number? = nil
		if owner and takeEquip(owner, pet.Kind, now) then
			celebrate = now
		end
		state = { Celebrate = celebrate }
		petStates[pet] = state
	end
	local s = state :: PetState
	local since: number? = nil
	local started = s.Celebrate
	if started then
		since = now - started
		if since > Logic.Golem.JumpTime then
			s.Celebrate = nil
			since = nil
		end
	end
	if not near and since == nil then
		return CFrame.identity
	end
	local lift, pitch, yaw, roll = Logic.golemPose(now, pet.Phase, pet.Seed, walking, near, pet.Floats, since, reduceMotion())
	if lift == 0 and pitch == 0 and yaw == 0 and roll == 0 then
		return CFrame.identity
	end
	return CFrame.new(0, lift, 0) * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)
end

---------------------------------------------------------------- ore pops

local function colourOfDust(model: Model, crust: Color3?): Color3
	local body = model.PrimaryPart
	local base = crust or (if body then body.Color else DUST)
	return base:Lerp(DUST, 0.45)
end

-- Starts the pop of a fresh Raw chunk (once per model).
local function startPop(model: Model, crust: Color3?)
	if popped[model] then
		return
	end
	popped[model] = true
	local body = model.PrimaryPart
	if not body or not model.Parent then
		return
	end
	local position = body.CFrame.Position
	if not visible(position, WorldMotionController.PopRange) then
		return
	end
	refreshCaps()
	local reduce = reduceMotion()
	local seed = nextSeed()
	local dust = colourOfDust(model, crust)
	local ground = groundBelow(position)
	spawnBits(Logic.dustPlan({
		Position = position,
		Color = dust,
		Ground = ground,
		Seed = seed,
		Landing = false,
		Count = Logic.dustCount(isPhone(), reduce, false),
		Room = caps.Bits - #live,
	}))
	if not rig then
		Sfx.play("DirtPop", position)
	end
	if #pops >= caps.Pops then
		return -- Reduce motion (no look-alikes) or enough pops at once: dust only
	end
	local real: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if not d:IsA("Part") or #real >= WorldMotionController.MaxPopParts then
				return -- a look the copy can't follow: dust only
			end
			table.insert(real, d)
		end
	end
	local proxies: { Proxy } = {}
	local cf = body.CFrame
	for _, part in real do
		local shape = (part :: Part).Shape
		local key = if shape == Enum.PartType.Ball then "Ball" elseif shape == Enum.PartType.Cylinder then "Cylinder" else "Block"
		local pool = poolOf(key)
		local copy = Logic.take(pool) :: BasePart?
		if not copy then
			for _, made in proxies do
				park(made.Part, made.Pool)
			end
			return
		end
		if not copy.Parent then
			copy.Parent = fxFolder()
		end
		copy.Color = part.Color
		copy.Material = part.Material
		copy.Size = part.Size
		copy.Transparency = part.Transparency
		copy.Reflectance = part.Reflectance
		copy.CastShadow = part.CastShadow
		copy.CFrame = part.CFrame
		table.insert(proxies, { Part = copy, Pool = pool, Offset = cf:ToObjectSpace(part.CFrame), Size = part.Size })
	end
	local saved: { number } = {}
	for i, part in real do
		saved[i] = part.LocalTransparencyModifier
		part.LocalTransparencyModifier = 1
	end
	local vy = body.AssemblyLinearVelocity.Y
	local half = body.Size.Y / 2
	local flight = Logic.landTime(vy, position.Y - half - ground, gravity())
	table.insert(pops, {
		Model = model,
		Body = body,
		Real = real,
		Saved = saved,
		Proxies = proxies,
		Born = now(),
		Flight = flight,
		Landed = nil,
		LastVy = vy,
		Half = half,
		Dust = dust,
		Seed = seed,
		Scaled = true,
	})
	ensureLoop()
end

-- A crack or shatter at `position`: chunks that appear near it soon pop (and ones already there).
local function noteDrop(position: Vector3, crust: Color3?)
	local t = now()
	local record = drops[nextDrop]
	nextDrop = nextDrop % RING + 1
	record.At, record.Position, record.Crust = t, position, crust
	for _, f in fresh do
		local model = f.Model
		if model and t - f.At <= WorldMotionController.MatchWindow then
			local body = model.PrimaryPart
			if body and (body.CFrame.Position - position).Magnitude <= WorldMotionController.MatchRange then
				f.Model = nil
				startPop(model, crust)
			end
		end
	end
end

-- A new item in Workspace.Items: a Raw chunk near a fresh crack pops; others wait a moment for theirs.
function WorldMotionController.onItemAdded(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("Kind") ~= "Raw" then
		return
	end
	local body = model.PrimaryPart
	if not body then
		return
	end
	local t = now()
	for _, d in drops do
		if
			t - d.At <= WorldMotionController.MatchWindow
			and (body.CFrame.Position - d.Position).Magnitude <= WorldMotionController.MatchRange
		then
			startPop(model, d.Crust)
			return
		end
	end
	local record = fresh[nextFresh]
	nextFresh = nextFresh % RING + 1
	record.At, record.Model = t, model
end

---------------------------------------------------------------- hits

-- The ore colour a rock shows: its floor's crystal colour, else its first glowing part, else `fallback`.
local function oreColour(rock: Model?, fallback: Color3): Color3
	if not rock then
		return fallback
	end
	local cached = rockColours[rock]
	if cached then
		return cached
	end
	local colour: Color3? = nil
	local floor = rock:GetAttribute("Floor")
	local kind = rock:GetAttribute("Kind")
	if type(floor) == "number" then
		local primary = rock.PrimaryPart
		local colors =
			RockFxLogic.colors(floor, if type(kind) == "string" then kind else nil, if primary then primary.Color else DUST, fallback)
		colour = colors.Crystal[1]
	else
		for _, d in rock:GetDescendants() do
			if d:IsA("BasePart") and d.Material == NEON then
				colour = d.Color
				break
			end
		end
	end
	local result = colour or fallback
	rockColours[rock] = result
	return result
end

-- The cached rock nearest to `position` (within `range`).
local function rockNear(position: Vector3, range: number): Model?
	rockScans += 1
	local best: Model? = nil
	local bestDistance = range
	for rock in rockSet do
		local primary = rock.PrimaryPart
		if primary then
			local distance = (primary.CFrame.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = rock, distance
			end
		end
	end
	return best
end

local function addRock(rock: Instance)
	if rock:IsA("Model") then
		rockSet[rock] = true
	end
end

local function removeRock(rock: Instance)
	if rock:IsA("Model") then
		rockSet[rock] = nil
	end
end

--[[
	The white flash, its star and the ore cubes at `position` (`back` toward
	the shooter). The cheap checks (on screen, in range, the flash cap) come
	first; only then the rock's colour: `rock` when known, else the nearest
	cached rock when `search`, else `glow`.
]]
local function hitAt(position: Vector3, back: Vector3?, glow: Color3, rock: Model?, search: boolean, small: boolean)
	if not visible(position, WorldMotionController.HitRange) then
		return
	end
	refreshCaps()
	if flashes >= caps.Flashes then
		return
	end
	local target = rock
	if not target and search then
		target = rockNear(position, 14)
	end
	local colour = oreColour(target, glow)
	local right, up = cameraBasis()
	local out = if back and back.Magnitude > 0.01 then back.Unit * 0.6 else Vector3.zero
	spawnBits(Logic.hitPlan({
		Position = position,
		Back = back,
		Color = colour,
		Right = right,
		Up = up,
		Ground = groundBelow(position + out),
		Seed = nextSeed(),
		Small = small,
		Phone = isPhone(),
		Reduce = reduceMotion(),
		Room = caps.Bits - #live,
	}))
end

local function firing(): boolean
	local r = rig
	if r then
		return r.Firing
	end
	return BlasterFx.isFiring()
end

-- Where your beam meets the rock: a ray from the muzzle, else the rock's side toward you.
local function beamEnd(rock: Model, from: Vector3, center: Vector3): Vector3
	if not rig then
		local params = includeParams
		if not params then
			local made = RaycastParams.new()
			made.FilterType = Enum.RaycastFilterType.Include
			params = made
			includeParams = made
		end
		local ray = params :: RaycastParams
		ray.FilterDescendantsInstances = { rock }
		local hit = Workspace:Raycast(from, (center - from) * 1.2, ray)
		if hit then
			return hit.Position
		end
	end
	local primary = rock.PrimaryPart
	local radius = if primary then math.max(primary.Size.X, primary.Size.Z) * 0.45 else 1.5
	local flat = (from - center) * Vector3.new(1, 0, 1)
	return center + (if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis) * radius
end

-- A rock lost HP: when your beam is on it, a hit at the beam's end (other players' hits come as BlastHit).
function WorldMotionController.onHealthDrop(rock: Model)
	if not firing() then
		return
	end
	local t = now()
	local last = lastHit[rock]
	if last and t - last < Logic.Hit.Gap then
		return
	end
	local primary = rock.PrimaryPart
	if not primary then
		return
	end
	local center = primary.CFrame.Position
	local from: Vector3
	local tool: Instance? = nil
	local r = rig
	if r then
		from = r.Root or r.Eye
	else
		local p = localPlayer()
		local character = p and p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root or not root:IsA("BasePart") then
			return
		end
		local to = (center - root.Position) * Vector3.new(1, 0, 1)
		if to.Magnitude > WorldMotionController.OwnRange then
			return
		end
		-- only the rock you face (MiningController turns you to the beam's end)
		if to.Magnitude > 0.5 and root.CFrame.LookVector:Dot(to.Unit) < 0.5 then
			return
		end
		tool = character:FindFirstChild("Blaster")
		local handle = tool and tool:FindFirstChild("Handle")
		local muzzle = handle and handle:FindFirstChild("Muzzle")
		from = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else root.Position + Vector3.new(0, 1.5, 0)
	end
	lastHit[rock] = t
	local glow = tool and tool:GetAttribute("Glow")
	local point = beamEnd(rock, from, center)
	hitAt(point, from - point, if typeof(glow) == "Color3" then glow else DEFAULT_ORE, rock, false, false)
end

local function shooterPosition(shooter: any): Vector3?
	if typeof(shooter) ~= "Instance" or not shooter:IsA("Player") then
		return nil
	end
	local character = (shooter :: Player).Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- The Fx remote: other players' BlastHit, and the cracks / shatters that drop chunks.
function WorldMotionController.onFx(kind: any, a: any, b: any, _stage: any, d: any)
	if typeof(a) ~= "Vector3" or a.X ~= a.X or a.Y ~= a.Y or a.Z ~= a.Z then
		return
	end
	if kind == "BlastHit" then
		-- (position, glow, stage, shooter): your own hits come from the Health drops
		if d ~= nil and d == localPlayer() then
			return
		end
		local key = if d ~= nil then d else "other"
		local t = now()
		local last = lastHit[key]
		if last and t - last < Logic.Hit.Gap then
			return
		end
		lastHit[key] = t
		local glow = if typeof(b) == "Color3" then b else DEFAULT_ORE
		local from = shooterPosition(d)
		hitAt(a, if from then from - a else nil, glow, nil, true, true)
	elseif kind == "NodeCrack" or kind == "NodeShatter" then
		noteDrop(a, if typeof(b) == "Color3" then b else nil)
	end
end

---------------------------------------------------------------- sell

-- Earned { Source = "Sell", Position, Count }: banknotes and coins burst out of the sell spot.
function WorldMotionController.onEarned(payload: any)
	if type(payload) ~= "table" or payload.Source ~= "Sell" then
		return
	end
	local position = payload.Position
	if typeof(position) ~= "Vector3" or position.X ~= position.X then
		return
	end
	local root = rootPosition()
	local near = root ~= nil and (root - position).Magnitude <= Logic.Cash.HomeRange
	if not near and not visible(position, WorldMotionController.SellRange) then
		return
	end
	refreshCaps()
	local count = if type(payload.Count) == "number" and payload.Count == payload.Count then payload.Count else 1
	spawnBits(Logic.cashPlan({
		Position = position,
		-- the floor you stand on (a ray under the counter would stop on its top)
		Ground = groundBelow(if near and root then root else position + Vector3.new(0, 1, 0)),
		Home = if near and root then root + Vector3.new(0, 1, 0) else nil,
		Seed = nextSeed(),
		Items = count,
		Phone = isPhone(),
		Reduce = reduceMotion(),
		Room = caps.Bits - #live,
	}))
end

---------------------------------------------------------------- tests and lifecycle

-- Tests and previews: a rig instead of the camera, the device and the clock (nil = the real ones).
function WorldMotionController.useRig(value: Rig?)
	rig = value
	table.clear(rockSet)
	if value then
		-- idle pooled parts move into the rig's folder
		for _, pool in pools do
			for _, item in pool.Idle do
				local part: BasePart = item
				part.Parent = value.Folder
			end
		end
		local rocks = value.Rocks
		if rocks then
			for _, rock in rocks do
				addRock(rock)
			end
		end
		refreshCaps()
	else
		-- back to the real device (read again on the next effect)
		phoneOn = nil
		reduceAt = -math.huge
		caps = Logic.caps(false, false)
	end
end

-- One frame by hand (with a rig).
function WorldMotionController.step(dt: number)
	step(dt)
end

-- Live counts: (bits, pops, flashes, parts made by the pools, rock scans so far).
function WorldMotionController.stats(): (number, number, number, number, number)
	local made = 0
	for _, pool in pools do
		made += pool.Made
	end
	return #live, #pops, flashes, made, rockScans
end

local function track(owner: Player)
	WorldMotionController.noteEquipped(owner, owner:GetAttribute(GolemConfig.EquippedAttribute))
	owner:GetAttributeChangedSignal(GolemConfig.EquippedAttribute):Connect(function()
		WorldMotionController.noteEquipped(owner, owner:GetAttribute(GolemConfig.EquippedAttribute))
	end)
end

function WorldMotionController.init()
	Net.listen("Fx", function(kind, ...)
		WorldMotionController.onFx(kind, ...)
	end)
	Net.listen("Earned", WorldMotionController.onEarned)
end

function WorldMotionController.start()
	refreshCaps()
	-- the rocks (other players' hits take their crystal colour from the nearest one)
	for _, rock in CollectionService:GetTagged("Rock") do
		addRock(rock)
	end
	CollectionService:GetInstanceAddedSignal("Rock"):Connect(addRock)
	CollectionService:GetInstanceRemovedSignal("Rock"):Connect(removeRock)
	-- the SETTINGS Reduce motion toggle applies at once (not only on the next once-a-second read)
	reduceMotion()
	local settings = settingsModule
	if settings and type(settings.onChanged) == "function" then
		settings.onChanged(function()
			reduceAt = -math.huge
		end)
	end
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	-- your own hits: the Health drops of the rocks near you (RockLabels watches them)
	local labels = script.Parent.Parent.UI:FindFirstChild("RockLabels")
	if labels and labels:IsA("ModuleScript") then
		local ok, module = pcall(require, labels :: any)
		local rockLabels = if ok then module :: any else nil
		if type(rockLabels) == "table" and type(rockLabels.onHealthDrop) == "function" then
			rockLabels.onHealthDrop(function(rock: Model)
				local fine, err = pcall(function()
					WorldMotionController.onHealthDrop(rock)
				end)
				if not fine then
					warn("[WorldMotionController] hit: " .. tostring(err))
				end
			end)
		end
	end
	-- fresh chunks
	local items = Workspace:WaitForChild("Items", 30)
	if items then
		items.ChildAdded:Connect(function(child: Instance)
			local ok, err = pcall(function()
				WorldMotionController.onItemAdded(child)
			end)
			if not ok then
				warn("[WorldMotionController] pop: " .. tostring(err))
			end
		end)
	end
end

return WorldMotionController
