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
	                          off), grows it to the rock's damage
	                          (CrackLogic.growth) and makes the glints flare, at
	                          most JuiceConfig.GlintFlaresPerSecond a second
	                          (MineJuiceRules.flare). `reduced` (Reduce motion):
	                          the crack still grows, the glints glow steady.
	                          Returns the crack's centre and face normal (the
	                          chips fly from there), nil when the rock gets none.
	  RockCracks.clear(rock)  gives the rock's parts back (the shatter; also
	                          automatic when the rock leaves the workspace)
	  RockCracks.count()      rocks with cracks now (tests / debug)

	The glint colour is JuiceConfig.GlintColor for every rock: never the ore
	colour (dirty ore keeps its rarity secret until it is cleaned).

	Phones: every part is pooled (anchored, no collisions, no queries, no
	touches, no shadows) and parked far below when unused; at most
	JuiceConfig.CrackRocks rocks (CrackRocksPhone on phones, with the smaller
	CrackLogic.PhoneDetail) have cracks at once, the oldest hit gives its parts
	back; parts move only on a hit (one BulkMoveTo); one RenderStepped
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
	FlareAt: number?, -- the glints' last flare (nil = never)
	Reduced: boolean, -- Reduce motion at the last hit: steady glints
	Conn: RBXScriptConnection?,
}

type Kind = "Dark" | "Glint" | "Fleck"

local entries: { [Model]: Entry } = {}
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
	flare(entry, os.clock() - (entry.FlareAt or -math.huge))
end

---------------------------------------------------------------- the glint flare loop

local function step()
	local now = os.clock()
	local hot = false
	for rock, entry in entries do
		local since = now - (entry.FlareAt or -math.huge)
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

-- The rock that was hit least recently gives its parts back.
local function evictOldest()
	local oldest: Model? = nil
	local at = math.huge
	for rock, entry in entries do
		if entry.HitAt < at then
			oldest, at = rock, entry.HitAt
		end
	end
	if oldest then
		RockCracks.clear(oldest)
	end
end

local function make(rock: Model): Entry?
	local camera = Workspace.CurrentCamera
	local box, extents = rock:GetBoundingBox()
	local center = box.Position
	local from = if camera then camera.CFrame.Position else center + Vector3.new(0, 4, 12)
	if (from - center).Magnitude > JuiceConfig.CrackRange then
		return nil
	end
	rayParams.FilterDescendantsInstances = { rock }
	local toward = center - from
	local result = Workspace:Raycast(from, toward.Unit * (toward.Magnitude + extents.Magnitude), rayParams)
	if not result then
		return nil
	end
	local phone = isPhone()
	local limit = if phone then JuiceConfig.CrackRocksPhone else JuiceConfig.CrackRocks
	while RockCracks.count() >= limit do
		evictOldest()
	end
	local detail = if phone then CrackLogic.PhoneDetail else CrackLogic.Detail
	local seed = string.format("%d,%d,%d", math.floor(center.X), math.floor(center.Y), math.floor(center.Z))
	local plan = CrackLogic.plan(seed, CrackLogic.sizeFor(extents), detail)
	local darks, glints, flecks = CrackLogic.counts(detail)
	local normal = result.Normal
	local right, up = CrackLogic.basis(normal)
	local entry: Entry = {
		Rock = rock,
		Plan = plan,
		Origin = result.Position,
		Normal = normal,
		Right = right,
		Up = up,
		Points = {},
		Normals = {},
		OnRock = {},
		Dark = take("Dark", darks),
		Glints = take("Glint", glints),
		Flecks = take("Fleck", flecks),
		Growth = 0,
		Stage = number(rock, "Stage") or 0,
		HitAt = os.clock(),
		FlareAt = nil,
		Reduced = false,
		Conn = nil,
	}
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
	(at most GlintFlaresPerSecond; `reduced`: steady). Returns the crack's
	centre and face normal (nil = no crack on this rock).
]]
function RockCracks.hit(rock: Model, reduced: boolean?): (Vector3?, Vector3?)
	if not JuiceConfig.Mining.Cracks or not rock.Parent or not rock.PrimaryPart then
		return nil, nil
	end
	local growth = CrackLogic.growth(number(rock, "Health"), number(rock, "MaxHealth"))
	if growth <= 0 then
		return nil, nil
	end
	local entry = entries[rock] or make(rock)
	if not entry then
		return nil, nil
	end
	local stage = number(rock, "Stage") or 0
	if stage ~= entry.Stage then
		-- a crack stage broke a chunk off: put the points onto what is left
		entry.Stage = stage
		project(entry)
	end
	local now = os.clock()
	local still = reduced == true
	entry.Growth = math.max(entry.Growth, growth)
	entry.HitAt = now
	entry.Reduced = still
	if MineJuiceRules.flare(now, entry.FlareAt, still) then
		entry.FlareAt = now
	end
	place(entry)
	if not still then
		ensureLoop()
	end
	return entry.Origin, entry.Normal
end

return RockCracks
