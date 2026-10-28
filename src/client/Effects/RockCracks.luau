--[[
	RockCracks: dark zig-zag cracks that grow on a rock with every hit, with
	warm gold glints and flecks in them (the owner's mining reel 2026-10-27,
	step 1 "cracks" and the bonus "ore glints"; Config/JuiceConfig Cracks /
	Glints). Client only; the math is in Effects/CrackLogic.

	  RockCracks.hit(rock, reduced)
	                          the rock lost HP (MineJuiceController calls it on
	                          every Health drop): plans its crack on the face
	                          toward the camera the first time (one raycast at
	                          the rock, then one per plan point onto its
	                          surface; again when a crack stage broke a chunk
	                          off, and on a face toward you again when your view
	                          of it turned away: MineJuiceRules.tryFace /
	                          betterFace, at most once per KeepHit, only to a
	                          clearly better face),
	                          grows it to the rock's damage
	                          (CrackLogic.growth) and makes the glints flare, at
	                          most JuiceConfig.GlintFlaresPerSecond a second
	                          (MineJuiceRules.flare). `reduced` (Reduce motion):
	                          the crack still grows, the glints glow steady.
	                          Returns the crack's centre and face normal (the
	                          chips fly from there), nil when the rock gets none.
	  RockCracks.clear(rock)  gives the rock's parts back (the shatter; also
	                          automatic when the rock leaves the workspace)
	  RockCracks.face(rock)   the crack face a rock has or remembers (origin,
	                          normal), nil when it never had one
	  RockCracks.setKeep(fn)  fn(rock) = true for the rocks that must keep their
	                          crack (MineJuiceController: your own and your
	                          focused rock)
	  RockCracks.count()      rocks with cracks now (tests / debug)

	The glint colour is JuiceConfig.GlintColor for every rock: never the ore
	colour (dirty ore keeps its rarity secret until it is cleaned).

	Phones: every part is pooled (anchored, no collisions, no queries, no
	touches, no shadows) and parked far below when unused; at most
	JuiceConfig.CrackRocks rocks (CrackRocksPhone on phones, with the smaller
	CrackLogic.PhoneDetail) have cracks at once. A new rock takes the slot of
	the rock hit least recently, never your own or focused rock and never one
	hit in the last KeepHit seconds (then the new rock simply gets none:
	MineJuiceRules.evict), so busy floors don't swap cracks back and forth. A
	rock remembers its face, its plan and its glints' last flare in a weak
	table, so losing and getting back a slot neither moves the crack nor
	flares it early. Parts move only on a hit (one BulkMoveTo); one RenderStepped
	connection runs only while a glint is still cooling (CrackLogic.Heat
	seconds after its last flare; never with Reduce motion) and makes no
	tables. The cracks don't follow
	RockFx's tiny tremble (0.07 studs, a fifth of a second).
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JuiceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("JuiceConfig"))
local CrackLogic = require(script.Parent.CrackLogic)
local MineJuiceRules = require(script.Parent.MineJuiceRules)
local Vfx = require(script.Parent.Vfx)

local RockCracks = {}

local PARK = CFrame.new(0, -5000, 0)

type Entry = {
	Rock: Model,
	Center: Vector3, -- the rock's bounding box middle (when the crack was made)
	Reach: number, -- a ray at the rock from the camera goes this far past the middle
	Plan: CrackLogic.Plan,
	Origin: Vector3,
	Normal: Vector3,
	Right: Vector3,
	Up: Vector3,
	Points: { Vector3 }, -- every plan point on the surface (or in the face plane when off the rock)
	Normals: { Vector3 },
	OnRock: { boolean },
	Dark: { BasePart },
	Glints: { BasePart },
	Flecks: { BasePart },
	Growth: number,
	Stage: number,
	HitAt: number, -- the last hit (the oldest hit gives its parts back first)
	FaceTry: number?, -- the last look for a better face (MineJuiceRules.tryFace)
	Reduced: boolean, -- Reduce motion at the last hit: steady glints
	Conn: RBXScriptConnection?,
}

-- What a rock keeps while it has no crack slot (weak keys: it goes with the rock).
type Memory = { FlareAt: number?, Plan: CrackLogic.Plan?, Origin: Vector3?, Normal: Vector3? }

type Kind = "Dark" | "Glint" | "Fleck"

local entries: { [Model]: Entry } = {}
local memory: { [Model]: Memory } = setmetatable({}, { __mode = "k" }) :: any
local keep: (Model) -> boolean = function()
	return false
end
local idle: { [Kind]: { BasePart } } = { Dark = {}, Glint = {}, Fleck = {} }
local connection: RBXScriptConnection? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function number(rock: Model, name: string): number?
	local value = rock:GetAttribute(name)
	return if type(value) == "number" and value == value then value else nil
end

---------------------------------------------------------------- pool

local function newPart(kind: Kind): BasePart
	local part = Instance.new("Part")
	part.Name = "Crack" .. kind
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = if kind == "Dark" then Enum.Material.SmoothPlastic else Enum.Material.Neon
	part.Color = if kind == "Dark" then JuiceConfig.CrackColor else JuiceConfig.GlintColor
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = PARK
	part:SetAttribute("NoStuds", true) -- (StudStyleController: keep it smooth)
	part.Parent = Vfx.folder()
	return part
end

local function take(kind: Kind, count: number): { BasePart }
	local list: { BasePart } = {}
	local pool = idle[kind]
	for _ = 1, count do
		local part = table.remove(pool)
		if not part or not part.Parent then
			part = newPart(kind)
		end
		table.insert(list, part :: BasePart)
	end
	return list
end

local function giveBack(kind: Kind, parts: { BasePart })
	for _, part in parts do
		if part.Parent then
			part.Transparency = 1
			part.CFrame = PARK
			table.insert(idle[kind], part)
		end
	end
end

function RockCracks.clear(rock: Model)
	local entry = entries[rock]
	if not entry then
		return
	end
	entries[rock] = nil
	local mem: Memory = memory[rock] or { FlareAt = nil, Plan = nil, Origin = nil, Normal = nil }
	mem.Plan, mem.Origin, mem.Normal = entry.Plan, entry.Origin, entry.Normal
	memory[rock] = mem
	local conn = entry.Conn
	if conn then
		conn:Disconnect()
	end
	giveBack("Dark", entry.Dark)
	giveBack("Glint", entry.Glints)
	giveBack("Fleck", entry.Flecks)
end

-- Rocks with cracks now.
function RockCracks.count(): number
	local n = 0
	for _ in entries do
		n += 1
	end
	return n
end

---------------------------------------------------------------- placing

-- When the rock's glints last flared (kept across losing the crack slot).
local function flareAt(rock: Model): number?
	local mem = memory[rock]
	return if mem then mem.FlareAt else nil
end

-- Puts every plan point onto the rock's surface (a ray along the face normal).
local function project(entry: Entry)
	rayParams.FilterDescendantsInstances = { entry.Rock }
	local plan = entry.Plan
	local reach = plan.Size * 1.5 + 2
	for i, p in plan.Points do
		local flat = CrackLogic.flatPoint(entry.Origin, entry.Right, entry.Up, p)
		local result = Workspace:Raycast(flat + entry.Normal * (reach * 0.5), entry.Normal * -reach, rayParams)
		-- (a surface far behind the face plane is the rock's edge falling away: the crack stops there)
		local onRock = result ~= nil and (result.Position - flat):Dot(entry.Normal) > -plan.Size * 0.8
		entry.Points[i] = if result and onRock then result.Position else flat
		entry.Normals[i] = if result and onRock then result.Normal else entry.Normal
		entry.OnRock[i] = onRock
	end
end

local function hide(part: BasePart)
	if part.Transparency < 1 then
		part.Transparency = 1
	end
	table.insert(moveParts, part)
	table.insert(moveFrames, PARK)
end

-- The glints' and flecks' transparency `since` seconds after their last flare.
local function flare(entry: Entry, since: number)
	local glow = CrackLogic.glint(since, entry.Reduced)
	local plan = entry.Plan
	local glints = JuiceConfig.Mining.Glints
	local g = 0
	for _, seg in plan.Segs do
		if seg.Main then
			g += 1
			local part = entry.Glints[g]
			if part and part.CFrame ~= PARK then
				part.Transparency = if glints then glow else 1
			end
		end
	end
	for i, part in entry.Flecks do
		if part.CFrame ~= PARK then
			part.Transparency = if glints and entry.Growth >= plan.FleckFrom[i] then glow * 0.6 else 1
		end
	end
end

-- Lays the crack's parts out for its growth now.
local function place(entry: Entry)
	table.clear(moveParts)
	table.clear(moveFrames)
	local plan = entry.Plan
	local glints = JuiceConfig.Mining.Glints and entry.Growth >= CrackLogic.GlintFrom
	local g = 0
	for k, seg in plan.Segs do
		local dark = entry.Dark[k]
		local glint: BasePart? = nil
		if seg.Main then
			g += 1
			glint = entry.Glints[g]
		end
		local f = CrackLogic.fraction(seg, entry.Growth)
		local ok = f > 0 and entry.OnRock[seg.I] and entry.OnRock[seg.J]
		if not ok then
			hide(dark)
			if glint then
				hide(glint)
			end
			continue
		end
		local a = entry.Points[seg.I]
		local tip = a:Lerp(entry.Points[seg.J], f)
		local normal = entry.Normals[seg.I] + entry.Normals[seg.J]
		normal = if normal.Magnitude > 1e-3 then normal.Unit else entry.Normal
		local cf, length = CrackLogic.segmentFrame(a, tip, normal, CrackLogic.Lift)
		dark.Size = Vector3.new(seg.Width, CrackLogic.Thickness, length + seg.Width * 0.6)
		dark.Transparency = 0
		table.insert(moveParts, dark)
		table.insert(moveFrames, cf)
		if glint then
			if glints and length > seg.Width * 0.4 then
				glint.Size = Vector3.new(seg.Width * CrackLogic.GlintWidth, CrackLogic.Thickness * 1.3, length - seg.Width * 0.2)
				table.insert(moveParts, glint)
				table.insert(moveFrames, cf * CFrame.new(0, CrackLogic.Thickness * 0.3, 0))
			else
				hide(glint)
			end
		end
	end
	for i, fleck in entry.Flecks do
		local index = plan.Flecks[i]
		if JuiceConfig.Mining.Glints and entry.Growth >= plan.FleckFrom[i] and entry.OnRock[index] then
			local s = CrackLogic.FleckSize * math.clamp(plan.Size / 2, 0.7, 1.6)
			fleck.Size = Vector3.new(s, s, s)
			table.insert(moveParts, fleck)
			table.insert(moveFrames, CFrame.new(entry.Points[index] + entry.Normals[index] * 0.04) * CFrame.Angles(0.6, 0.785, 0.4))
		else
			hide(fleck)
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	flare(entry, os.clock() - (flareAt(entry.Rock) or -math.huge))
end

---------------------------------------------------------------- the glint flare loop

local function step()
	local now = os.clock()
	local hot = false
	for rock, entry in entries do
		local since = now - (flareAt(rock) or -math.huge)
		if since <= CrackLogic.Heat + 0.05 and not entry.Reduced then
			hot = true
			if rock.Parent then
				flare(entry, since)
			end
		end
	end
	if not hot then
		local current = connection
		connection = nil
		if current then
			current:Disconnect()
		end
	end
end

local function ensureLoop()
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

---------------------------------------------------------------- hits

-- The crack face `rock` has now or remembers from a lost slot (origin, normal); nil = none yet.
function RockCracks.face(rock: Model): (Vector3?, Vector3?)
	local entry = entries[rock]
	if entry then
		return entry.Origin, entry.Normal
	end
	local mem = memory[rock]
	if mem then
		return mem.Origin, mem.Normal
	end
	return nil, nil
end

-- The rocks that must keep their crack: `fn(rock)` (your own and your focused rock).
function RockCracks.setKeep(fn: (Model) -> boolean)
	keep = fn
end

--[[
	Frees a slot for a new rock (`incomingKept`: it is yours): the rock hit
	least recently that isn't yours and wasn't hit in the last KeepHit seconds
	(MineJuiceRules.evict). False when none may go: the new rock waits.
]]
local function freeSlot(now: number, incomingKept: boolean): boolean
	local slots: { [Model]: MineJuiceRules.Slot } = {}
	for rock, entry in entries do
		slots[rock] = { HitAt = entry.HitAt, Kept = keep(rock) }
	end
	local victim = MineJuiceRules.evict(slots, now, incomingKept)
	if not victim then
		return false
	end
	RockCracks.clear(victim)
	return true
end

-- Aims the crack at the rock's face toward the camera (one ray at its middle). False when the ray misses.
-- The face toward the camera (one ray at the rock's middle): its point and normal, nil when it misses.
local function cast(entry: Entry): (Vector3?, Vector3?)
	local camera = Workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else entry.Center + Vector3.new(0, 4, 12)
	rayParams.FilterDescendantsInstances = { entry.Rock }
	local toward = entry.Center - from
	if toward.Magnitude < 0.1 then
		return nil, nil
	end
	local result = Workspace:Raycast(from, toward.Unit * (toward.Magnitude + entry.Reach), rayParams)
	if not result then
		return nil, nil
	end
	return result.Position, result.Normal
end

-- Puts the crack on a face (its point and normal).
local function setFace(entry: Entry, origin: Vector3, normal: Vector3)
	entry.Origin = origin
	entry.Normal = normal
	entry.Right, entry.Up = CrackLogic.basis(normal)
end

-- Aims the crack at the face toward the camera. False when the ray misses.
local function aim(entry: Entry): boolean
	local origin, normal = cast(entry)
	if not origin or not normal then
		return false
	end
	setFace(entry, origin, normal)
	return true
end

-- Your view of the crack's face (1 = straight at it); 1 without a camera.
local function facing(entry: Entry): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local view = camera.CFrame.Position - entry.Center
	return if view.Magnitude > 0.1 then view.Unit:Dot(entry.Normal) else 1
end

local function make(rock: Model, now: number): Entry?
	local camera = Workspace.CurrentCamera
	local primary = rock.PrimaryPart :: BasePart
	if camera and (camera.CFrame.Position - primary.Position).Magnitude > JuiceConfig.CrackRange then
		return nil
	end
	local phone = isPhone()
	local limit = if phone then JuiceConfig.CrackRocksPhone else JuiceConfig.CrackRocks
	local kept = keep(rock)
	while RockCracks.count() >= limit do
		if not freeSlot(now, kept) then
			return nil -- every slot is busy with a fresh or kept rock: this one waits
		end
	end
	local box, extents = rock:GetBoundingBox()
	local center = box.Position
	local detail = if phone then CrackLogic.PhoneDetail else CrackLogic.Detail
	local darks, glints, flecks = CrackLogic.counts(detail)
	local mem = memory[rock]
	local plan = mem and mem.Plan
	if not plan or #plan.Segs ~= darks then
		local seed = string.format("%d,%d,%d", math.floor(center.X), math.floor(center.Y), math.floor(center.Z))
		plan = CrackLogic.plan(seed, CrackLogic.sizeFor(extents), detail)
	end
	local entry: Entry = {
		Rock = rock,
		Center = center,
		Reach = extents.Magnitude,
		Plan = plan :: CrackLogic.Plan,
		Origin = center,
		Normal = Vector3.new(0, 1, 0),
		Right = Vector3.new(1, 0, 0),
		Up = Vector3.new(0, 0, 1),
		Points = {},
		Normals = {},
		OnRock = {},
		Dark = {},
		Glints = {},
		Flecks = {},
		Growth = 0,
		Stage = number(rock, "Stage") or 0,
		HitAt = now,
		FaceTry = nil,
		Reduced = false,
		Conn = nil,
	}
	-- the face it had before it lost its slot, else the one toward you
	local origin, normal = mem and mem.Origin, mem and mem.Normal
	if origin and normal then
		entry.Origin, entry.Normal = origin, normal
		entry.Right, entry.Up = CrackLogic.basis(normal)
	elseif not aim(entry) then
		return nil
	end
	entry.Dark = take("Dark", darks)
	entry.Glints = take("Glint", glints)
	entry.Flecks = take("Fleck", flecks)
	entries[rock] = entry
	entry.Conn = rock.AncestryChanged:Connect(function()
		if not rock:IsDescendantOf(Workspace) then
			RockCracks.clear(rock)
		end
	end)
	project(entry)
	return entry
end

--[[
	The rock lost HP: its crack grows to the damage now and the glints flare
	(at most GlintFlaresPerSecond per rock, also across losing its slot;
	`reduced`: steady). Returns the crack's centre and face normal (nil = no
	crack on this rock now).
]]
function RockCracks.hit(rock: Model, reduced: boolean?): (Vector3?, Vector3?)
	if not JuiceConfig.Mining.Cracks or not rock.Parent or not rock.PrimaryPart then
		return nil, nil
	end
	local growth = CrackLogic.growth(number(rock, "Health"), number(rock, "MaxHealth"))
	if growth <= 0 then
		return nil, nil
	end
	local now = os.clock()
	local entry = entries[rock] or make(rock, now)
	if not entry then
		return nil, nil
	end
	local stage = number(rock, "Stage") or 0
	local moved = false
	local old = facing(entry)
	if MineJuiceRules.tryFace(now, entry.FaceTry, old) then
		-- you look at the rock from another side now (another player's first hit planned it,
		-- or you walked round it): the crack moves to the face toward you, if it is clearly better
		entry.FaceTry = now
		local origin, normal = cast(entry)
		if origin and normal then
			local camera = Workspace.CurrentCamera
			local view = if camera then camera.CFrame.Position - entry.Center else normal
			local new = if view.Magnitude > 0.1 then view.Unit:Dot(normal) else 1
			if MineJuiceRules.betterFace(old, new) then
				setFace(entry, origin, normal)
				moved = true
			end
		end
	end
	if moved then
		entry.Stage = stage
		project(entry)
	elseif stage ~= entry.Stage then
		-- a crack stage broke a chunk off: put the points onto what is left
		entry.Stage = stage
		project(entry)
	end
	local still = reduced == true
	entry.Growth = math.max(entry.Growth, growth)
	entry.HitAt = now
	entry.Reduced = still
	local mem: Memory = memory[rock] or { FlareAt = nil, Plan = nil, Origin = nil, Normal = nil }
	memory[rock] = mem
	if MineJuiceRules.flare(now, mem.FlareAt, still) then
		mem.FlareAt = now
	end
	place(entry)
	if not still then
		ensureLoop()
	end
	return entry.Origin, entry.Normal
end

return RockCracks
