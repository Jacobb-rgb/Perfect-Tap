--[[
	The elevator's travel cinematic in 3D (owner 2026-11-15; timeline and
	looks in Config/ElevatorTravelConfig). Built once from parts on the client
	and kept for every later ride; nothing is created while a ride plays.

	  cabin    a steel cabin exactly over the real cage of a stop (MineKit.elevator:
	           the cage stands at z 0.2, its floor top 0.9 over the stop's floor
	           center): diamond-plate floor, steel walls with a long window on each
	           side, a ceiling light and two light strips, a hand rail, a button
	           panel, two amber warning lamps, a digital floor screen over the doors
	           (seven-segment digits and flowing chevrons, built from neon parts)
	           and two sliding steel doors with big windows, hazard bars and a
	           glowing seam in the target mine's colour; the doors run outside the
	           front wall and slide away behind its panels
	  shaft    five rings of rock wall around the cabin (slabs, jutting rocks,
	           crystal clusters, support beams, two lamps with lights) that wrap
	           around while they rush past, painted in the colours of the floor
	           being passed (MineFloors palettes); a landing band glows past at
	           every floor; thin light streaks; dust, glowing motes and streak
	           particles in the gaps (pooled emitters, rates follow the speed)
	  beacon   a yellow warning light on the real cage's roof for the preparation

	Stage frame = a stop's floor center (ElevatorService.stopCFrame), front
	(-Z) = the stop's front. The cabin stands at FromAt until the stop, then at
	StopAt. Pure and deterministic: build() makes the parts, pose(stage, plan,
	pose) places and lights everything for a moment of the plan, camera(...)
	gives the camera; the client runs them every frame, the Lune previews
	export frames with the same code. stage.Bulk (set by the client) moves
	parts in one call (Workspace:BulkMoveTo); parts that stay put are not
	touched.
]]

local MineFloors = require(script.Parent.Parent.Config.MineFloors)
local ElevatorTravelConfig = require(script.Parent.Parent.Config.ElevatorTravelConfig)
local Geo = require(script.Parent.Geo)
local Rng = require(script.Parent.Parent.Util.Rng)

local Stage = {}

type Plan = ElevatorTravelConfig.Plan

export type Group = { Parts: { BasePart }, Rest: { CFrame } }

export type Ring = {
	Slot: number, -- 0-based: where the ring sits in the column at rest
	Group: Group,
	Slabs: { BasePart }, -- painted with the floor's rock
	Rocks: { BasePart },
	Crystals: { BasePart },
	Veins: { BasePart }, -- glowing cracks / ore veins in the floor's accent colour
	PaintKey: number, -- the floor it is painted for (0 = never painted)
}

export type Stage = {
	Folder: Folder,
	CabinFolder: Folder,
	ShaftFolder: Folder,
	BeaconFolder: Folder,
	Cabin: Group, -- every cabin part that stays put in the cabin
	DoorLeft: Group,
	DoorRight: Group,
	Rings: { Ring },
	Landing: Group,
	LandingGlow: { BasePart },
	Streaks: Group,
	EmitterParts: { BasePart },
	EmitterRest: { Vector3 }, -- each holder's place in the gap (its height is set per ride)
	Emitters: { ParticleEmitter },
	BeaconGroup: Group,
	Beacon: BasePart,
	Beacons: { BasePart },
	BeaconLight: PointLight,
	CeilingPanel: BasePart,
	CeilingLight: PointLight,
	Strips: { BasePart },
	WarnLamps: { BasePart },
	WarnLights: { PointLight },
	Digits: { { BasePart } }, -- [1] tens, [2] ones: seven segments each (a..g)
	Chevrons: Group, -- the screen's arrow (rest: pointing down)
	Seams: { BasePart },
	Trims: { BasePart },
	ShaftLights: { PointLight },
	WorkLights: { PointLight },
	Fade: { { Part: BasePart, Base: number } }, -- every cabin part and its own transparency
	Bulk: ((parts: { BasePart }, frames: { CFrame }) -> ())?,
	-- what was posed last (only changes are written)
	At: CFrame?,
	DoorShift: number,
	ShaftShown: boolean,
	CabinShown: boolean,
	BeaconShown: boolean,
	FadeLevel: number,
	BeaconAt: CFrame?,
	RateKey: string,
}

export type Pose = {
	T: number, -- the plan's clock (seconds from "Depart"; the client holds it at the brake while it waits)
	Travel: number, -- studs the shaft has run
	Speed: number, -- 0..1 of ElevatorTravelConfig.ShaftSpeed
	Reduced: boolean,
	FromAt: CFrame,
	StopAt: CFrame?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local STEEL = rgb(138, 146, 164)
local STEEL_DARK = rgb(78, 84, 100)
local STEEL_PALE = rgb(168, 176, 192)
local CHROME = rgb(206, 212, 222)
local HAZARD = rgb(255, 196, 52)
local INK = rgb(22, 24, 30)
local AMBER = rgb(255, 170, 40)
local WARM = rgb(255, 236, 206)
local GLASS = rgb(196, 226, 244)
local SEG_OFF = rgb(30, 32, 44) -- a screen segment that is off (no glow)
local TIMBER = rgb(110, 76, 48)

-- Veins in another colour than the palette's Accent, by floor Id: the Stormglass Rift's rock glows
-- with electric yellow lightning (its Accent is the copper of its storm catchers).
Stage.VeinColors = {
	StormglassRift = Color3.fromRGB(255, 226, 90),
} :: { [string]: Color3 }

-- the cabin (stage frame): floor top, ceiling, inner half width, front and back inner faces
Stage.FloorY = 0.9
Stage.CeilingY = 8.1
Stage.HalfWidth = 2.9
Stage.FrontZ = -2.7
Stage.BackZ = 3.1
Stage.DoorTop = 6.7
Stage.DoorHalf = 1.75 -- half the doorway's width: one door's width
Stage.DoorZ = -3.05
-- real parts of a stop inside this box (stop frame) are hidden on the client while a ride plays:
-- the cage's floor, bars, rails, roof, lamp and the cables over it
Stage.HideBox = { Min = Vector3.new(-3.35, 0.68, -3.2), Max = Vector3.new(3.35, 8.7, 3.6) }
-- the shaft: inner faces, the rings' height and how many
Stage.ShaftHalfX = 3.7
Stage.ShaftFrontZ = -3.75
Stage.ShaftBackZ = 4.15
Stage.RingHeight = 8
Stage.RingCount = 5
Stage.RingLow = -14 -- the lowest ring's bottom at rest (the column spans RingLow .. + RingHeight * RingCount)
-- the camera in the cabin: the eye near the back wall, looking at the doors a little down
Stage.Eye = Vector3.new(0, 4.85, 2.6)
Stage.EyeStart = Vector3.new(0, 4.85, 2.85) -- right after the dip (a small push in while the doors close)
Stage.EyeOpen = Vector3.new(0, 4.9, 2.2) -- a lean toward the doors as they open
Stage.LookAt = Vector3.new(0, 5.05, -3.0)
-- the player's camera after the ride: behind the head, a little from above
Stage.HeadLift = 1.5
Stage.ExitPitch = math.rad(18)
-- where the arrival effects stand (stop frame): on the plate in front of the doors
Stage.ArrivalSpot = CFrame.new(0, 0, -4.4)

local DECOR = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
local SHELL = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = true }

local function props(base: { [string]: any }, more: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	for key, value in base do
		out[key] = value
	end
	if more then
		for key, value in more do
			out[key] = value
		end
	end
	return out
end

local function newGroup(): Group
	return { Parts = {}, Rest = {} }
end

local function keep(group: Group, part: BasePart): BasePart
	table.insert(group.Parts, part)
	table.insert(group.Rest, part.CFrame)
	return part
end

local function block(
	group: Group,
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): Part
	local part = Geo.block(parent, cf, size, color, material, props(DECOR, extra))
	keep(group, part)
	return part
end

local function wedge(
	group: Group,
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): WedgePart
	local part = Geo.wedge(parent, cf, size, color, material, props(DECOR, extra))
	keep(group, part)
	return part
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

---------------------------------------------------------------- the seven-segment digits

-- segment boxes of one digit (digit frame: x right, y up, centred), a..g
local SEG_W, SEG_T, DIGIT_H = 0.34, 0.075, 0.78
type Segment = { X: number, Y: number, Flat: boolean }
local SEGMENTS: { Segment } = {
	{ X = 0, Y = DIGIT_H / 2, Flat = true }, -- a top
	{ X = SEG_W / 2, Y = DIGIT_H / 4, Flat = false }, -- b top right
	{ X = SEG_W / 2, Y = -DIGIT_H / 4, Flat = false }, -- c bottom right
	{ X = 0, Y = -DIGIT_H / 2, Flat = true }, -- d bottom
	{ X = -SEG_W / 2, Y = -DIGIT_H / 4, Flat = false }, -- e bottom left
	{ X = -SEG_W / 2, Y = DIGIT_H / 4, Flat = false }, -- f top left
	{ X = 0, Y = 0, Flat = true }, -- g middle
}
-- which segments each number lights (a..g)
Stage.Glyphs = {
	[0] = "abcdef",
	[1] = "bc",
	[2] = "abged",
	[3] = "abgcd",
	[4] = "fgbc",
	[5] = "afgcd",
	[6] = "afgedc",
	[7] = "abc",
	[8] = "abcdefg",
	[9] = "abcfgd",
} :: { [number]: string }

-- Is segment `index` (1 = a .. 7 = g) lit for the digit `n`?
function Stage.segmentOn(n: number, index: number): boolean
	local glyph = Stage.Glyphs[n]
	if not glyph then
		return false
	end
	return string.find(glyph, string.sub("abcdefg", index, index), 1, true) ~= nil
end

---------------------------------------------------------------- building

local function buildCabin(stage: Stage, folder: Folder)
	local cabin = stage.Cabin
	local midZ = (Stage.FrontZ + Stage.BackZ) / 2
	local depth = Stage.BackZ - Stage.FrontZ
	local outer = Stage.HalfWidth * 2 + 0.5
	local wallMidY = (Stage.FloorY + Stage.CeilingY) / 2
	local wallH = Stage.CeilingY - Stage.FloorY
	-- floor and ceiling
	block(
		cabin,
		folder,
		CFrame.new(0, Stage.FloorY - 0.15, midZ),
		Vector3.new(outer, 0.3, depth + 0.5),
		STEEL_DARK,
		Enum.Material.DiamondPlate,
		SHELL
	)
	block(
		cabin,
		folder,
		CFrame.new(0, Stage.CeilingY + 0.15, midZ),
		Vector3.new(outer, 0.3, depth + 0.5),
		STEEL_DARK,
		Enum.Material.Metal,
		SHELL
	)
	-- back wall: a darker inset panel and a chrome hand rail
	block(cabin, folder, CFrame.new(0, wallMidY, Stage.BackZ + 0.125), Vector3.new(outer, wallH, 0.25), STEEL, Enum.Material.Metal, SHELL)
	block(cabin, folder, CFrame.new(0, 4.7, Stage.BackZ - 0.03), Vector3.new(4.6, 4.6, 0.06), STEEL_DARK, Enum.Material.Metal)
	block(
		cabin,
		folder,
		CFrame.new(0, 3.3, Stage.BackZ - 0.2) * CFrame.Angles(0, 0, 0),
		Vector3.new(4.8, 0.14, 0.14),
		CHROME,
		Enum.Material.Metal
	)
	-- side walls with a long window each (glass, a light trim above and below it)
	local winLow, winHigh, winFront, winBack = 2.6, 6.6, -1.4, 1.9
	for _, sx in { -1, 1 } do
		local x = sx * (Stage.HalfWidth + 0.125)
		block(
			cabin,
			folder,
			CFrame.new(x, (Stage.FloorY + winLow) / 2, midZ),
			Vector3.new(0.25, winLow - Stage.FloorY, depth + 0.5),
			STEEL,
			Enum.Material.Metal,
			SHELL
		)
		block(
			cabin,
			folder,
			CFrame.new(x, (winHigh + Stage.CeilingY) / 2, midZ),
			Vector3.new(0.25, Stage.CeilingY - winHigh, depth + 0.5),
			STEEL,
			Enum.Material.Metal,
			SHELL
		)
		local frontLen = winFront - (Stage.FrontZ - 0.25)
		block(
			cabin,
			folder,
			CFrame.new(x, (winLow + winHigh) / 2, (Stage.FrontZ - 0.25 + winFront) / 2),
			Vector3.new(0.25, winHigh - winLow, frontLen),
			STEEL,
			Enum.Material.Metal,
			SHELL
		)
		local backLen = (Stage.BackZ + 0.25) - winBack
		block(
			cabin,
			folder,
			CFrame.new(x, (winLow + winHigh) / 2, (winBack + Stage.BackZ + 0.25) / 2),
			Vector3.new(0.25, winHigh - winLow, backLen),
			STEEL,
			Enum.Material.Metal,
			SHELL
		)
		local glass = block(
			cabin,
			folder,
			CFrame.new(sx * (Stage.HalfWidth + 0.1), (winLow + winHigh) / 2, (winFront + winBack) / 2),
			Vector3.new(0.06, winHigh - winLow, winBack - winFront),
			GLASS,
			Enum.Material.SmoothPlastic,
			{
				Transparency = 0.82,
			}
		)
		glass.Name = "Window"
		for _, y in { winLow + 0.04, winHigh - 0.04 } do
			local trim = block(
				cabin,
				folder,
				CFrame.new(sx * (Stage.HalfWidth - 0.02), y, (winFront + winBack) / 2),
				Vector3.new(0.08, 0.08, winBack - winFront),
				WHITE,
				Enum.Material.Neon
			)
			trim.Name = "Trim"
			table.insert(stage.Trims, trim)
		end
	end
	-- front wall: two panels beside the doorway and the header over it
	local panelW = (Stage.HalfWidth + 0.25) - Stage.DoorHalf
	for _, sx in { -1, 1 } do
		block(
			cabin,
			folder,
			CFrame.new(sx * (Stage.DoorHalf + panelW / 2), wallMidY, Stage.FrontZ - 0.125),
			Vector3.new(panelW, wallH, 0.25),
			STEEL,
			Enum.Material.Metal,
			SHELL
		)
		-- chrome jamb
		block(
			cabin,
			folder,
			CFrame.new(sx * (Stage.DoorHalf + 0.05), (Stage.FloorY + Stage.DoorTop) / 2, Stage.FrontZ + 0.02),
			Vector3.new(0.12, Stage.DoorTop - Stage.FloorY, 0.12),
			CHROME,
			Enum.Material.Metal
		)
	end
	local headerH = Stage.CeilingY - Stage.DoorTop
	block(
		cabin,
		folder,
		CFrame.new(0, Stage.DoorTop + headerH / 2, Stage.FrontZ - 0.125),
		Vector3.new(Stage.DoorHalf * 2, headerH, 0.25),
		STEEL,
		Enum.Material.Metal,
		SHELL
	)
	block(
		cabin,
		folder,
		CFrame.new(0, Stage.DoorTop + 0.05, Stage.FrontZ + 0.02),
		Vector3.new(Stage.DoorHalf * 2 + 0.2, 0.1, 0.12),
		CHROME,
		Enum.Material.Metal
	)
	-- hazard threshold
	for i = 0, 5 do
		local color = if i % 2 == 0 then HAZARD else INK
		block(
			cabin,
			folder,
			CFrame.new(-Stage.DoorHalf + 0.29 + i * 0.58, Stage.FloorY + 0.02, Stage.FrontZ + 0.2),
			Vector3.new(0.58, 0.04, 0.36),
			color,
			Enum.Material.SmoothPlastic
		)
	end
	-- the floor screen over the doors: a dark glass panel, chevrons on the left, two digits on the right
	local screenY = Stage.DoorTop + headerH / 2
	local screenZ = Stage.FrontZ + 0.04
	block(cabin, folder, CFrame.new(0, screenY, screenZ), Vector3.new(2.7, 1.06, 0.06), rgb(12, 14, 22), Enum.Material.SmoothPlastic)
	block(cabin, folder, CFrame.new(0, screenY, screenZ - 0.01), Vector3.new(2.86, 1.2, 0.04), STEEL_DARK, Enum.Material.Metal)
	local face = screenZ + 0.04
	for k = 1, 3 do
		local cy = screenY + 0.3 - (k - 1) * 0.3
		for _, side in { -1, 1 } do
			-- a "V": two bars leaning in (riding up turns the whole arrow, pose)
			local bar = block(
				stage.Chevrons,
				folder,
				CFrame.new(-0.92 + side * 0.11, cy, face) * CFrame.Angles(0, 0, side * math.rad(40)),
				Vector3.new(0.3, 0.07, 0.03),
				WHITE,
				Enum.Material.Neon
			)
			bar.Name = "Chevron"
		end
	end
	for d = 1, 2 do
		local digit: { BasePart } = {}
		local cx = if d == 1 then 0.18 else 0.72
		for s, spec in SEGMENTS do
			local size = if spec.Flat then Vector3.new(SEG_W, SEG_T, 0.03) else Vector3.new(SEG_T, DIGIT_H / 2, 0.03)
			local seg = block(cabin, folder, CFrame.new(cx + spec.X, screenY + spec.Y, face), size, WHITE, Enum.Material.Neon)
			seg.Name = "Segment" .. string.sub("abcdefg", s, s)
			table.insert(digit, seg)
		end
		table.insert(stage.Digits, digit)
	end
	-- the ceiling light and two light strips
	local panel =
		block(cabin, folder, CFrame.new(0, Stage.CeilingY - 0.04, midZ + 0.3), Vector3.new(3, 0.08, 2.4), WARM, Enum.Material.Neon)
	panel.Name = "CeilingLight"
	stage.CeilingPanel = panel
	stage.CeilingLight = light(panel, WARM, 16, 2.6)
	for _, sx in { -1, 1 } do
		local strip =
			block(cabin, folder, CFrame.new(sx * 2.55, Stage.CeilingY - 0.04, midZ), Vector3.new(0.12, 0.06, 4.6), WARM, Enum.Material.Neon)
		strip.Name = "Strip"
		table.insert(stage.Strips, strip)
	end
	-- the amber warning lamps at the doorway's top corners
	for _, sx in { -1, 1 } do
		local lamp = block(
			cabin,
			folder,
			CFrame.new(sx * (Stage.DoorHalf + 0.35), Stage.DoorTop + 0.25, Stage.FrontZ + 0.08),
			Vector3.new(0.24, 0.24, 0.12),
			AMBER,
			Enum.Material.Neon
		)
		lamp.Name = "WarnLamp"
		table.insert(stage.WarnLamps, lamp)
		table.insert(stage.WarnLights, light(lamp, AMBER, 7, 0))
	end
	-- the cage's work lights outside, in the gaps to the shaft walls (front, left, right): the rock
	-- lights up as it rushes past (on only while the cabin rides)
	for _, spot in { Vector3.new(0, 6.4, -3.45), Vector3.new(-3.45, 5.2, 0.2), Vector3.new(3.45, 5.2, 0.2) } do
		local holder =
			block(cabin, folder, CFrame.new(spot), Vector3.new(0.2, 0.2, 0.2), WARM, Enum.Material.SmoothPlastic, { Transparency = 1 })
		holder.Name = "WorkLight"
		table.insert(stage.WorkLights, light(holder, WARM, 12, 0))
	end
	-- a button panel on the right
	block(cabin, folder, CFrame.new(2.3, 4.2, Stage.FrontZ + 0.04), Vector3.new(0.5, 1.3, 0.06), STEEL_DARK, Enum.Material.Metal)
	local buttonColors =
		{ rgb(255, 120, 80), rgb(120, 220, 255), rgb(255, 214, 90), rgb(140, 255, 160), rgb(255, 120, 200), rgb(220, 220, 230) }
	for i, color in buttonColors do
		local bx = 2.3 + (if i % 2 == 0 then 0.1 else -0.1)
		local by = 4.65 - math.floor((i - 1) / 2) * 0.32
		local button = block(
			cabin,
			folder,
			CFrame.new(bx, by, Stage.FrontZ + 0.08) * CFrame.Angles(math.pi / 2, 0, 0),
			Vector3.new(0.14, 0.04, 0.14),
			color,
			Enum.Material.Neon,
			{
				Shape = Enum.PartType.Cylinder,
			}
		)
		button.Name = "Button"
	end
end

-- One door half (`side` -1 = left, +1 = right) at its closed place: steel with a big window,
-- hazard bars and a glowing seam (the target mine's colour).
local function buildDoor(stage: Stage, folder: Folder, side: number): Group
	local g = newGroup()
	local w = Stage.DoorHalf
	local cx = side * w / 2
	local z = Stage.DoorZ
	local low, winLow, winHigh, top = Stage.FloorY, 2.5, 6.15, Stage.DoorTop
	block(g, folder, CFrame.new(cx, (low + winLow) / 2, z), Vector3.new(w, winLow - low, 0.18), STEEL_PALE, Enum.Material.Metal, SHELL)
	block(g, folder, CFrame.new(cx, (winHigh + top) / 2, z), Vector3.new(w, top - winHigh, 0.18), STEEL_PALE, Enum.Material.Metal, SHELL)
	-- the stiles around the window (outer edge, seam edge)
	block(
		g,
		folder,
		CFrame.new(side * (w - 0.2), (winLow + winHigh) / 2, z),
		Vector3.new(0.4, winHigh - winLow, 0.18),
		STEEL_PALE,
		Enum.Material.Metal,
		SHELL
	)
	block(
		g,
		folder,
		CFrame.new(side * 0.125, (winLow + winHigh) / 2, z),
		Vector3.new(0.25, winHigh - winLow, 0.18),
		STEEL_PALE,
		Enum.Material.Metal,
		SHELL
	)
	local glass = block(
		g,
		folder,
		CFrame.new(side * (0.25 + (w - 0.65) / 2), (winLow + winHigh) / 2, z),
		Vector3.new(w - 0.65, winHigh - winLow, 0.06),
		GLASS,
		Enum.Material.SmoothPlastic,
		{
			Transparency = 0.8,
		}
	)
	glass.Name = "Window"
	-- brushed band and hazard bars on the inside
	block(g, folder, CFrame.new(cx, winLow + 0.06, z + 0.1), Vector3.new(w - 0.1, 0.06, 0.02), CHROME, Enum.Material.Metal)
	for _, y in { low + 0.35, low + 0.75 } do
		block(g, folder, CFrame.new(cx, y, z + 0.1), Vector3.new(w - 0.2, 0.16, 0.02), HAZARD, Enum.Material.SmoothPlastic)
	end
	local seam =
		block(g, folder, CFrame.new(side * 0.03, (low + top) / 2, z + 0.1), Vector3.new(0.06, top - low, 0.03), WHITE, Enum.Material.Neon)
	seam.Name = "Seam"
	table.insert(stage.Seams, seam)
	return g
end

-- One ring of shaft wall (slot 0..RingCount-1), centred on y = 0 at rest (it is placed every frame).
local function buildRing(folder: Folder, slot: number): Ring
	local g = newGroup()
	local rng = Rng.new(9100 + slot * 37)
	local h = Stage.RingHeight
	local hx, fz, bz = Stage.ShaftHalfX, Stage.ShaftFrontZ, Stage.ShaftBackZ
	local width = hx * 2 + 2.4
	local depthZ = bz - fz
	local slabs: { BasePart } = {}
	local rocks: { BasePart } = {}
	local crystals: { BasePart } = {}
	local veins: { BasePart } = {}
	local function slab(cf: CFrame, size: Vector3): BasePart
		local part = block(g, folder, cf, size, STEEL, Enum.Material.Slate, SHELL)
		part.Name = "Wall"
		table.insert(slabs, part)
		return part
	end
	slab(CFrame.new(0, 0, fz - 0.6), Vector3.new(width, h + 0.02, 1.2))
	slab(CFrame.new(0, 0, bz + 0.6), Vector3.new(width, h + 0.02, 1.2))
	slab(CFrame.new(-hx - 0.6, 0, (fz + bz) / 2), Vector3.new(1.2, h + 0.02, depthZ))
	slab(CFrame.new(hx + 0.6, 0, (fz + bz) / 2), Vector3.new(1.2, h + 0.02, depthZ))
	-- jutting rocks on the three walls the cabin's windows see (front, left, right)
	-- (a point on each face, its +Z into the shaft, and how far its rocks spread along it)
	local faces: { { Cf: CFrame, Spread: number } } = {
		{ Cf = CFrame.new(0, 0, fz), Spread = hx * 1.6 },
		{ Cf = CFrame.new(-hx, 0, (fz + bz) / 2) * CFrame.Angles(0, math.pi / 2, 0), Spread = depthZ * 0.8 },
		{ Cf = CFrame.new(hx, 0, (fz + bz) / 2) * CFrame.Angles(0, -math.pi / 2, 0), Spread = depthZ * 0.8 },
	}
	for f, spec in faces do
		local faceCf = spec.Cf
		local spread = spec.Spread
		for k = 1, 2 do
			local x = rng:range(-spread / 2, spread / 2)
			local y = rng:range(-h / 2 + 1, h / 2 - 1)
			-- (a rock never reaches past 0.45 studs out of the wall: the gap to the cabin is 0.55)
			local s = Vector3.new(rng:range(1.1, 2.2), rng:range(0.9, 1.9), rng:range(0.4, 0.7))
			local cf = faceCf
				* CFrame.new(x, y, -s.Z * 0.15)
				* CFrame.Angles(rng:range(-0.2, 0.2), rng:range(-0.2, 0.2), rng:range(-0.6, 0.6))
			local rock: BasePart = if k == 1
				then block(g, folder, cf, s, STEEL, Enum.Material.Slate)
				else wedge(g, folder, cf * CFrame.Angles(0, if f == 1 then math.pi else 0, 0), s, STEEL, Enum.Material.Slate)
			rock.Name = "Rock"
			table.insert(rocks, rock)
		end
		-- glowing veins in the rock (lava cracks, copper, gold ...): they streak past the windows
		for _ = 1, 2 do
			local len = rng:range(2.2, 4.2)
			local cf = faceCf
				* CFrame.new(rng:range(-spread / 2, spread / 2), rng:range(-h / 2 + 0.8, h / 2 - 0.8), 0.03)
				* CFrame.Angles(0, 0, rng:range(-0.9, 0.9))
			local vein = block(g, folder, cf, Vector3.new(len, 0.16, 0.08), WHITE, Enum.Material.Neon)
			vein.Name = "Vein"
			table.insert(veins, vein)
		end
		-- a crystal cluster (three shards fanning out of one root)
		do
			local x = rng:range(-spread / 2.4, spread / 2.4)
			local y = rng:range(-h / 2 + 1.4, h / 2 - 1.4)
			for c = 1, 3 do
				local len = rng:range(0.6, 1.0)
				local tilt = (c - 2) * 0.45 + rng:range(-0.15, 0.15)
				local cf = faceCf * CFrame.new(x, y, 0.05) * CFrame.Angles(0.35, 0, tilt) * CFrame.new(0, len / 2, 0)
				local shard = block(g, folder, cf, Vector3.new(0.24, len, 0.24), WHITE, Enum.Material.Neon)
				shard.Name = "Crystal"
				table.insert(crystals, shard)
			end
		end
		-- a support beam along the ring's top edge
		local beamLen = if f == 1 then hx * 2 else depthZ
		local beam =
			block(g, folder, faceCf * CFrame.new(0, h / 2 - 0.3, 0.18), Vector3.new(beamLen, 0.36, 0.36), TIMBER, Enum.Material.Wood)
		beam.Name = "Beam"
	end
	return { Slot = slot, Group = g, Slabs = slabs, Rocks = rocks, Crystals = crystals, Veins = veins, PaintKey = 0 }
end

local function emitter(parent: BasePart, name: string, texture: string, settings: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Rate = 0
	e.Enabled = true
	e.EmissionDirection = Enum.NormalId.Top
	e.LockedToPart = false
	local target: any = e
	for key, value in settings do
		target[key] = value
	end
	e.Parent = parent
	return e
end

Stage.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Square = "rbxasset://textures/particles/SquareParticle.png",
}

local function buildShaft(stage: Stage, folder: Folder)
	for slot = 0, Stage.RingCount - 1 do
		table.insert(stage.Rings, buildRing(folder, slot))
	end
	-- two lamps on the front wall (rings 1 and 3), their lights sweep over the doors
	for _, slot in { 1, 3 } do
		local ring = stage.Rings[slot + 1]
		local lamp = block(
			ring.Group,
			folder,
			CFrame.new(-1.6 + slot * 0.6, 1.2, Stage.ShaftFrontZ + 0.12),
			Vector3.new(0.7, 0.32, 0.24),
			WARM,
			Enum.Material.Neon
		)
		lamp.Name = "ShaftLamp"
		table.insert(stage.ShaftLights, light(lamp, WARM, 10, 1.3))
	end
	-- the landing band of a floor passed: a dark opening framed by glowing strips
	local landing = stage.Landing
	local hx, fz = Stage.ShaftHalfX, Stage.ShaftFrontZ
	block(landing, folder, CFrame.new(0, 0, fz + 0.05), Vector3.new(hx * 2 - 0.4, 2.6, 0.12), INK, Enum.Material.SmoothPlastic)
	for _, y in { 1.36, -1.36 } do
		local strip = block(landing, folder, CFrame.new(0, y, fz + 0.12), Vector3.new(hx * 2 - 0.2, 0.14, 0.12), WHITE, Enum.Material.Neon)
		table.insert(stage.LandingGlow, strip)
	end
	for _, sx in { -1, 1 } do
		local strip =
			block(landing, folder, CFrame.new(sx * (hx - 0.08), 1.36, 0.2), Vector3.new(0.12, 0.14, 7.4), WHITE, Enum.Material.Neon)
		table.insert(stage.LandingGlow, strip)
	end
	-- light streaks in the gaps between the cabin and the walls
	local streaks = stage.Streaks
	local spots = { { -2.2, -3.4 }, { 1.4, -3.45 }, { 0.3, -3.5 }, { -3.4, -1.0 }, { 3.35, -0.6 }, { 3.4, 0.6 } }
	for _, spot in spots do
		local streak = block(streaks, folder, CFrame.new(spot[1], 0, spot[2]), Vector3.new(0.05, 2.6, 0.05), WHITE, Enum.Material.Neon, {
			Transparency = 1,
		})
		streak.Name = "Streak"
	end
	-- the particle holders in the gaps (front, left, right), at the bottom while riding down
	local holders: { { At: Vector3, Size: Vector3 } } = {
		{ At = Vector3.new(0, 0, (Stage.DoorZ - 0.1 + Stage.ShaftFrontZ) / 2), Size = Vector3.new(hx * 2 - 0.4, 0.2, 0.4) },
		{ At = Vector3.new(-(Stage.HalfWidth + 0.25 + hx) / 2, 0, 0.2), Size = Vector3.new(0.4, 0.2, 6.6) },
		{ At = Vector3.new((Stage.HalfWidth + 0.25 + hx) / 2, 0, 0.2), Size = Vector3.new(0.4, 0.2, 6.6) },
	}
	for i, spec in holders do
		local holder = block(newGroup(), folder, CFrame.new(spec.At), spec.Size, WHITE, Enum.Material.SmoothPlastic, { Transparency = 1 })
		holder.Name = "Particles" .. i
		table.insert(stage.EmitterParts, holder)
		table.insert(stage.EmitterRest, spec.At)
		table.insert(
			stage.Emitters,
			emitter(holder, "Motes", Stage.Textures.Sparkle, {
				Size = NumberSequence.new(0.16, 0.06),
				Transparency = NumberSequence.new(0.15, 1),
				LightEmission = 0.7,
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(28, 46),
				SpreadAngle = Vector2.new(6, 6),
			})
		)
		table.insert(
			stage.Emitters,
			emitter(holder, "Dust", Stage.Textures.Smoke, {
				Size = NumberSequence.new(0.8, 1.8),
				Transparency = NumberSequence.new(0.78, 1),
				LightEmission = 0,
				Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(20, 30),
				SpreadAngle = Vector2.new(10, 10),
			})
		)
		table.insert(
			stage.Emitters,
			emitter(holder, "Streaks", Stage.Textures.Square, {
				Size = NumberSequence.new(0.07),
				Squash = NumberSequence.new(-2.6),
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Transparency = NumberSequence.new(0.2, 1),
				LightEmission = 1,
				Lifetime = NumberRange.new(0.22, 0.32),
				Speed = NumberRange.new(70, 92),
				SpreadAngle = Vector2.new(2, 2),
			})
		)
	end
end

-- Makes every part of the set once (nothing is parented to the world yet).
function Stage.build(): Stage
	local folder = Instance.new("Folder")
	folder.Name = "ElevatorTravel"
	local cabinFolder = Instance.new("Folder")
	cabinFolder.Name = "Cabin"
	local shaftFolder = Instance.new("Folder")
	shaftFolder.Name = "Shaft"
	local beaconFolder = Instance.new("Folder")
	beaconFolder.Name = "Beacon"
	local stage: Stage = {
		Folder = folder,
		CabinFolder = cabinFolder,
		ShaftFolder = shaftFolder,
		BeaconFolder = beaconFolder,
		Cabin = newGroup(),
		DoorLeft = newGroup(),
		DoorRight = newGroup(),
		Rings = {},
		Landing = newGroup(),
		LandingGlow = {},
		Streaks = newGroup(),
		EmitterParts = {},
		EmitterRest = {},
		Emitters = {},
		BeaconGroup = newGroup(),
		Beacon = nil :: any,
		Beacons = {},
		BeaconLight = nil :: any,
		CeilingPanel = nil :: any,
		CeilingLight = nil :: any,
		Strips = {},
		WarnLamps = {},
		WarnLights = {},
		Digits = {},
		Chevrons = newGroup(),
		Seams = {},
		Trims = {},
		ShaftLights = {},
		WorkLights = {},
		Fade = {},
		Bulk = nil,
		At = nil,
		DoorShift = -1,
		ShaftShown = false,
		CabinShown = false,
		BeaconShown = false,
		FadeLevel = 0,
		BeaconAt = nil,
		RateKey = "",
	}
	buildCabin(stage, cabinFolder)
	stage.DoorLeft = buildDoor(stage, cabinFolder, -1)
	stage.DoorRight = buildDoor(stage, cabinFolder, 1)
	buildShaft(stage, shaftFolder)
	-- the yellow warning beacons on the real cage's front corner posts (under its ELEVATOR sign)
	for _, sx in { -1, 1 } do
		local beacon = block(
			stage.BeaconGroup,
			beaconFolder,
			CFrame.new(sx * 2.85, 7.15, -3.0),
			Vector3.new(0.5, 0.5, 0.36),
			HAZARD,
			Enum.Material.Neon
		)
		beacon.Name = "WarningBeacon"
		table.insert(stage.Beacons, beacon)
		if sx < 0 then
			stage.Beacon = beacon
			stage.BeaconLight = light(beacon, AMBER, 14, 0)
		end
	end
	for _, group in { stage.Cabin, stage.Chevrons, stage.DoorLeft, stage.DoorRight } do
		for _, part in group.Parts do
			table.insert(stage.Fade, { Part = part, Base = part.Transparency })
		end
	end
	return stage
end

-- Every part of the set (the tests count them against the phone budget).
function Stage.parts(stage: Stage): { BasePart }
	local out: { BasePart } = {}
	for _, d in stage.Folder:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	for _, folder in { stage.CabinFolder, stage.ShaftFolder, stage.BeaconFolder } do
		if folder.Parent ~= stage.Folder then
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(out, d)
				end
			end
		end
	end
	return out
end

---------------------------------------------------------------- pure timing

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	local u = clamp01(x)
	return u * u * (3 - 2 * u)
end

local function easeOut(x: number): number
	local u = clamp01(x)
	return 1 - (1 - u) * (1 - u)
end

-- How shut the doors are at `t` (0 open .. 1 shut).
function Stage.closedness(plan: Plan, t: number): number
	local timing = ElevatorTravelConfig.Timing
	if t < plan.DoorsCloseAt then
		return 0
	end
	if t < plan.DoorsShut then
		return smooth((t - plan.DoorsCloseAt) / (plan.DoorsShut - plan.DoorsCloseAt))
	end
	if t < plan.DoorsOpenAt then
		return 1
	end
	return 1 - smooth((t - plan.DoorsOpenAt) / timing.DoorsOpen)
end

-- The shaft's speed at `t` (0..1): it gets going after the doors meet and slows to a stop in the brake.
function Stage.speedAt(plan: Plan, t: number): number
	local timing = ElevatorTravelConfig.Timing
	if t < plan.TravelStart then
		return 0
	end
	if t < plan.TravelStart + timing.SpeedUp then
		local u = (t - plan.TravelStart) / timing.SpeedUp
		return u * u
	end
	if t < plan.BrakeAt then
		return 1
	end
	return 1 - smooth((t - plan.BrakeAt) / timing.Brake)
end

-- Studs the shaft has run by `t` (the integral of speedAt; the client integrates itself while it waits).
function Stage.travelAt(plan: Plan, t: number): number
	local timing = ElevatorTravelConfig.Timing
	local speed = ElevatorTravelConfig.ShaftSpeed
	if t <= plan.TravelStart then
		return 0
	end
	local up = timing.SpeedUp
	local u1 = math.min((t - plan.TravelStart) / up, 1)
	local distance = up * u1 * u1 * u1 / 3
	if t > plan.TravelStart + up then
		distance += math.min(t, plan.BrakeAt) - (plan.TravelStart + up)
	end
	if t > plan.BrakeAt then
		local u = math.min((t - plan.BrakeAt) / timing.Brake, 1)
		-- integral of 1 - (3u^2 - 2u^3)
		distance += timing.Brake * (u - u * u * u + u * u * u * u / 2)
	end
	return distance * speed
end

-- The floor whose rock the shaft shows `t` seconds in (the floor left, then each floor passed).
function Stage.paintFloorAt(plan: Plan, t: number): number
	return ElevatorTravelConfig.floorAt(plan, t)
end

-- 0..1 how bright the cabin's lights are at `t` (a flicker dims them; reduced motion: never).
function Stage.lightLevel(plan: Plan, t: number, reduced: boolean): number
	if not reduced then
		for _, at in plan.Flickers do
			if t >= at and t < at + ElevatorTravelConfig.Timing.Flicker then
				return 0.25
			end
		end
		-- the doors meet: a short dip of the lights with the thud
		if t >= plan.DoorsShut and t < plan.DoorsShut + 0.07 then
			return 0.4
		end
	end
	return 1
end

-- How much the stop's flash lights the cabin at `t` (1 + extra): one flash; reduced motion a soft swell.
function Stage.flashAt(plan: Plan, t: number, reduced: boolean): number
	local since = t - plan.StopAt
	if since < 0 then
		return 0
	end
	if reduced then
		return 0.6 * math.sin(math.pi * clamp01(since / 0.6))
	end
	if since < 0.05 then
		return 2.5 * since / 0.05
	end
	return 2.5 * (1 - clamp01((since - 0.05) / 0.3))
end

-- Is a warning lamp lit at `t`? The beacon flashes twice in the preparation, the cabin's lamps while the
-- doors close and once as they open. Reduced motion: a steady glow instead of flashes.
function Stage.warnAt(plan: Plan, t: number, reduced: boolean, beacon: boolean): number
	local timing = ElevatorTravelConfig.Timing
	if beacon then
		if t >= plan.Enter then
			return 0
		end
		if reduced then
			return if t >= timing.Prepare[1] then 0.7 else 0
		end
		for _, at in timing.Prepare do
			if t >= at and t < at + timing.FlashOn then
				return 1
			end
		end
		return 0
	end
	local closing = t >= plan.DoorsCloseAt and t < plan.DoorsShut
	local opening = t >= plan.DoorsOpenAt and t < plan.DoorsOpenAt + timing.DoorsOpen
	if reduced then
		return if closing or opening then 0.7 else 0
	end
	for _, at in { plan.DoorsCloseAt, plan.DoorsCloseAt + 0.3, plan.DoorsOpenAt } do
		if t >= at and t < at + timing.FlashOn then
			return 1
		end
	end
	return 0
end

-- The cabin's see-through-ness on the way out (0 solid .. 1 gone): it fades as the camera leaves.
function Stage.fadeAt(plan: Plan, t: number): number
	return smooth((t - plan.ExitAt) / 0.35)
end

-- The colour a floor shows on the screen and the seams.
function Stage.floorGlow(floorIndex: number): Color3
	local floor = MineFloors.ByIndex[floorIndex]
	return ElevatorTravelConfig.theme(if floor then floor.Id else nil).Glow
end

---------------------------------------------------------------- posing

local function move(stage: Stage, parts: { BasePart }, frames: { CFrame })
	local bulk = stage.Bulk
	if bulk then
		bulk(parts, frames)
	else
		for i, part in parts do
			part.CFrame = frames[i]
		end
	end
end

local function placeGroup(stage: Stage, group: Group, at: CFrame)
	local frames = table.create(#group.Rest)
	for i, rest in group.Rest do
		frames[i] = at * rest
	end
	move(stage, group.Parts, frames)
end

-- The floor's rock on a ring: the walls in its rock colours, the jutting rocks lighter, the crystals glowing.
local function paintRing(ring: Ring, floorIndex: number)
	if ring.PaintKey == floorIndex then
		return
	end
	ring.PaintKey = floorIndex
	local list = MineFloors.List
	local palette = list[math.clamp(floorIndex, 1, #list)].Palette
	-- (lighter than the floors' own rock: the work lights and the lamps carry the shaft)
	local tone =
		{ palette.Mid:Lerp(palette.Light, 0.3), palette.Mid, palette.Mid:Lerp(palette.Light, 0.5), palette.Mid:Lerp(palette.Dark, 0.2) }
	for i, slab in ring.Slabs do
		slab.Color = tone[(i + ring.Slot) % #tone + 1]
	end
	for i, rock in ring.Rocks do
		rock.Color = if i % 2 == 0 then palette.Light:Lerp(palette.Mid, 0.35) else palette.Mid:Lerp(palette.Light, 0.25)
	end
	local vein = Stage.VeinColors[list[math.clamp(floorIndex, 1, #list)].Id] or palette.Accent
	for _, part in ring.Veins do
		part.Color = vein
	end
	for i, shard in ring.Crystals do
		shard.Color = if i % 3 == 0 then palette.Crystal2 else palette.Crystal
	end
end

local function setTransparency(part: BasePart, value: number)
	if part.Transparency ~= value then
		part.Transparency = value
	end
end

local function setColor(part: BasePart, color: Color3)
	if part.Color ~= color then
		part.Color = color
	end
end

-- Paints one digit: lit segments in `color`, the others nearly gone (a faint ghost like a real screen).
local function paintDigit(segments: { BasePart }, n: number?, color: Color3, glow: number)
	for _, seg in segments do
		setTransparency(seg, if n == nil then 1 else 0)
	end
	for s, seg in segments do
		local on = n ~= nil and Stage.segmentOn(n, s)
		setColor(seg, if on then color:Lerp(WHITE, glow * 0.6) else SEG_OFF)
		local material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		if seg.Material ~= material then
			seg.Material = material
		end
	end
end

--[[
	Poses the whole set for one moment of a ride: where the cabin stands, the
	doors, the shaft (rings, landing band, streaks, emitters), every light, the
	screen and the fade on the way out. Writes only what changed.
]]
function Stage.pose(stage: Stage, plan: Plan, pose: Pose)
	local t = pose.T
	local reduced = pose.Reduced
	-- which parts of the set are in the world now
	local cabinShown = t >= plan.DipMid and t < plan.EndAt
	local arrived = t >= plan.StopAt and pose.StopAt ~= nil
	local shaftShown = cabinShown and t >= plan.DoorsShut and t < plan.StopAt
	local beaconShown = t < plan.Enter
	if cabinShown ~= stage.CabinShown then
		stage.CabinShown = cabinShown
		stage.CabinFolder.Parent = if cabinShown then stage.Folder else nil
	end
	if shaftShown ~= stage.ShaftShown then
		stage.ShaftShown = shaftShown
		stage.ShaftFolder.Parent = if shaftShown then stage.Folder else nil
		if not shaftShown then
			Stage.quiet(stage)
		end
	end
	if beaconShown ~= stage.BeaconShown then
		stage.BeaconShown = beaconShown
		stage.BeaconFolder.Parent = if beaconShown then stage.Folder else nil
	end
	-- the beacon on the real cage in the preparation
	if beaconShown then
		if stage.BeaconAt ~= pose.FromAt then
			stage.BeaconAt = pose.FromAt
			placeGroup(stage, stage.BeaconGroup, pose.FromAt)
		end
		local glow = Stage.warnAt(plan, t, reduced, true)
		for _, beacon in stage.Beacons do
			setColor(beacon, if glow > 0 then HAZARD else HAZARD:Lerp(INK, 0.55))
			local material = if glow > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
			if beacon.Material ~= material then
				beacon.Material = material
			end
		end
		stage.BeaconLight.Brightness = 3 * glow
	end
	if not cabinShown then
		return
	end
	local at: CFrame = if arrived then pose.StopAt :: CFrame else pose.FromAt
	-- the cabin: placed again only when it moves (into the cabin, then the swap to the target stop);
	-- the screen's arrow turns over for a ride up
	if stage.At ~= at then
		stage.At = at
		stage.DoorShift = -1
		placeGroup(stage, stage.Cabin, at)
		local screen = CFrame.new(-0.92, Stage.DoorTop + (Stage.CeilingY - Stage.DoorTop) / 2, 0)
		local turn = if plan.Down then CFrame.identity else CFrame.Angles(0, 0, math.pi)
		placeGroup(stage, stage.Chevrons, at * screen * turn * screen:Inverse())
	end
	-- the doors slide sideways outside the front wall
	local shift = Stage.DoorHalf * (1 - Stage.closedness(plan, t))
	if math.abs(shift - stage.DoorShift) > 1e-4 then
		stage.DoorShift = shift
		placeGroup(stage, stage.DoorLeft, at * CFrame.new(-shift, 0, 0))
		placeGroup(stage, stage.DoorRight, at * CFrame.new(shift, 0, 0))
	end
	-- lights: warm in the ride, the target mine's light from the stop on, a flicker, the stop's flash;
	-- everything dims away with the cabin on the way out
	local toFloor = MineFloors.ByIndex[plan.To]
	local theme = ElevatorTravelConfig.theme(if toFloor then toFloor.Id else nil)
	local glowTarget = theme.Glow
	local fade = Stage.fadeAt(plan, t)
	local level = Stage.lightLevel(plan, t, reduced)
	local flash = Stage.flashAt(plan, t, reduced)
	local tint = if t >= plan.StopAt then smooth((t - plan.StopAt) / 0.3) else 0
	local lightColor = WARM:Lerp(theme.Light:Lerp(WHITE, 0.35), tint)
	stage.CeilingLight.Brightness = (2.6 * level + 2.4 * flash) * (1 - fade)
	stage.CeilingLight.Color = lightColor
	setColor(stage.CeilingPanel, lightColor:Lerp(WHITE, math.min(flash, 1) * 0.5))
	setTransparency(stage.CeilingPanel, if level < 0.5 then 0.6 else 0)
	for _, strip in stage.Strips do
		setColor(strip, lightColor)
		setTransparency(strip, if level < 0.5 then 0.7 else 0)
	end
	local work = if t >= plan.DoorsShut and t < plan.StopAt then 3.4 * level else 0
	for _, workLight in stage.WorkLights do
		workLight.Brightness = work
	end
	local warn = Stage.warnAt(plan, t, reduced, false)
	for i, lamp in stage.WarnLamps do
		setTransparency(lamp, if warn > 0 then 0 else 0.6)
		stage.WarnLights[i].Brightness = 2.4 * warn * (1 - fade)
	end
	-- the seams and the window trims glow in the target mine's colour (a slow breath in the ride)
	local breath = if reduced then 0 else 0.5 + 0.5 * math.sin(t * 5)
	for _, seam in stage.Seams do
		setColor(seam, glowTarget:Lerp(WHITE, 0.15 * breath))
	end
	for _, trim in stage.Trims do
		setColor(trim, glowTarget)
	end
	-- the screen: the floor the cabin is at, in that floor's colour; it pops at every tick and at the stop
	local shown = ElevatorTravelConfig.floorAt(plan, t)
	local pop = 0
	for _, tick in plan.Ticks do
		if t >= tick.Time and t < tick.Time + 0.25 then
			pop = 1 - (t - tick.Time) / 0.25
		end
	end
	pop = math.max(pop, math.min(flash, 1))
	local digitColor = Stage.floorGlow(shown)
	paintDigit(stage.Digits[1], if shown >= 10 then math.floor(shown / 10) % 10 else nil, digitColor, pop)
	paintDigit(stage.Digits[2], shown % 10, digitColor, pop)
	-- the chevrons point the way and flow while the cabin moves
	local riding = t >= plan.TravelStart and t < plan.StopAt
	local wave = math.floor(t * 7) % 3
	for i, bar in stage.Chevrons.Parts do
		local row = math.floor((i - 1) / 2) -- 0 top .. 2 bottom (before a ride up turns them)
		local lit = not riding or reduced or row == wave
		setColor(bar, if lit then digitColor else digitColor:Lerp(rgb(12, 14, 22), 0.75))
	end
	-- the shaft
	if shaftShown then
		local dirSign = if plan.Down then 1 else -1
		local span = Stage.RingHeight * Stage.RingCount
		local paintAhead = Stage.paintFloorAt(plan, t + 0.25)
		local parts: { BasePart } = {}
		local frames: { CFrame } = {}
		for _, ring in stage.Rings do
			local raw = Stage.RingLow + Stage.RingHeight * (ring.Slot + 0.5) + dirSign * pose.Travel
			local y = ((raw - Stage.RingLow) % span) + Stage.RingLow
			-- a ring coming back round (out of sight at the far end) takes the next floor's rock
			local farEnd = if plan.Down then y < Stage.RingLow + Stage.RingHeight else y > Stage.RingLow + span - Stage.RingHeight
			if farEnd or ring.PaintKey == 0 then
				paintRing(ring, paintAhead)
			end
			local ringCf = at * CFrame.new(0, y, 0)
			for i, part in ring.Group.Parts do
				table.insert(parts, part)
				table.insert(frames, ringCf * ring.Group.Rest[i])
			end
		end
		-- the landing band of the floor passed nearest to now (it runs with the walls)
		local middle = (Stage.FloorY + Stage.CeilingY) / 2
		local bandY = math.huge
		for _, tick in plan.Ticks do
			local y = middle + dirSign * (pose.Travel - Stage.travelAt(plan, tick.Time))
			if math.abs(y - middle) < math.abs(bandY - middle) then
				bandY = y
			end
		end
		local bandCf = at * CFrame.new(0, if math.abs(bandY - middle) < 24 then bandY else -400, 0)
		for i, part in stage.Landing.Parts do
			table.insert(parts, part)
			table.insert(frames, bandCf * stage.Landing.Rest[i])
		end
		local accent = Stage.floorGlow(paintAhead)
		for _, strip in stage.LandingGlow do
			setColor(strip, accent)
		end
		-- light streaks: faster than the walls, only at speed (never with reduced motion)
		for i, part in stage.Streaks.Parts do
			local cycle = 30
			local y = (((i * 7.3) + dirSign * pose.Travel * 1.5) % cycle) - 8
			table.insert(parts, part)
			table.insert(frames, at * CFrame.new(0, y, 0) * stage.Streaks.Rest[i])
			setTransparency(part, if reduced or pose.Speed < 0.55 then 1 else 0.35 + 0.65 * (1 - pose.Speed))
			setColor(part, accent:Lerp(WHITE, 0.4))
		end
		-- the particle holders sit at the far end the walls come from
		local holderY = if plan.Down then -2.5 else 12
		local direction = if plan.Down then Enum.NormalId.Top else Enum.NormalId.Bottom
		for i, holder in stage.EmitterParts do
			local rest = stage.EmitterRest[i]
			table.insert(parts, holder)
			table.insert(frames, at * CFrame.new(rest.X, holderY, rest.Z))
			for k = 1, 3 do
				local e = stage.Emitters[(i - 1) * 3 + k]
				if e.EmissionDirection ~= direction then
					e.EmissionDirection = direction
				end
			end
		end
		move(stage, parts, frames)
		Stage.setRates(stage, pose.Speed, reduced, paintAhead)
	end
	-- on the way out the cabin fades (the client fades the real cage back in): every frame while it
	-- fades, as the lines above may have lit a part again
	if fade > 0 then
		stage.FadeLevel = fade
		for _, entry in stage.Fade do
			local wanted = entry.Base + (1 - entry.Base) * fade
			if entry.Part.Transparency < wanted then
				entry.Part.Transparency = wanted
			end
		end
	end
end

-- The shaft's particle rates for a speed (0..1); colours follow the floor being passed.
function Stage.setRates(stage: Stage, speed: number, reduced: boolean, floorIndex: number)
	local key = `{math.floor(speed * 20 + 0.5)}:{floorIndex}:{reduced}`
	if key == stage.RateKey then
		return
	end
	local colorsChanged = string.match(stage.RateKey, ":(%d+):") ~= tostring(floorIndex)
	stage.RateKey = key
	local list = MineFloors.List
	local palette = list[math.clamp(floorIndex, 1, #list)].Palette
	for i, e in stage.Emitters do
		local kind = (i - 1) % 3 + 1
		local rate = 0
		if kind == 1 then
			rate = 24 * speed * (if reduced then 0.4 else 1)
			if colorsChanged then
				e.Color = ColorSequence.new(palette.Crystal:Lerp(WHITE, 0.4))
			end
		elseif kind == 2 then
			rate = 8 * speed * (if reduced then 0.5 else 1)
			if colorsChanged then
				e.Color = ColorSequence.new(palette.Light:Lerp(palette.Ground, 0.4))
			end
		else
			rate = if reduced or speed < 0.55 then 0 else 14 * speed
			if colorsChanged then
				e.Color = ColorSequence.new(palette.Accent:Lerp(WHITE, 0.5))
			end
		end
		e.Rate = rate
	end
end

-- Every emitter off (the ride is over or the shaft left the world).
function Stage.quiet(stage: Stage)
	stage.RateKey = ""
	for _, e in stage.Emitters do
		e.Rate = 0
	end
end

-- Puts the set back to how build() left it for the next ride (doors open, nothing shown, solid).
function Stage.reset(stage: Stage)
	Stage.quiet(stage)
	stage.At = nil
	stage.BeaconAt = nil
	stage.DoorShift = -1
	stage.FadeLevel = 0
	for _, entry in stage.Fade do
		entry.Part.Transparency = entry.Base
	end
	for _, ring in stage.Rings do
		ring.PaintKey = 0
	end
	stage.CabinShown = false
	stage.ShaftShown = false
	stage.BeaconShown = false
	stage.CabinFolder.Parent = nil
	stage.ShaftFolder.Parent = nil
	stage.BeaconFolder.Parent = nil
end

---------------------------------------------------------------- the camera

export type CameraInfo = {
	FromAt: CFrame,
	StopAt: CFrame?,
	Target: CFrame?, -- where the character stands after the ride
	Zoom: number, -- the player's camera distance before the ride
	Fov: number, -- the player's field of view before the ride
	Reduced: boolean,
	Speed: number, -- 0..1 (the rumble)
	CutAt: number?, -- the camera cuts here (behind a dip) instead of gliding: reduced motion, no target stop
}

-- The camera where the game hands it back: behind the head at the player's zoom, a little from above.
function Stage.exitCamera(target: CFrame, zoom: number): CFrame
	local focus = target.Position + Vector3.new(0, Stage.HeadLift, 0)
	local flat = Vector3.new(target.LookVector.X, 0, target.LookVector.Z)
	local look = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local dir = look * math.cos(Stage.ExitPitch) - Vector3.new(0, math.sin(Stage.ExitPitch), 0)
	local distance = math.clamp(zoom, 0.5, 40)
	return CFrame.lookAt(focus - dir * distance, focus)
end

local function noise(t: number, a: number, b: number): number
	return math.sin(t * a) * 0.6 + math.sin(t * b + 1.3) * 0.4
end

-- The camera's shake offset in the cabin at `t` (studs), from the rumble, the jolt and the stop's bump.
function Stage.shakeAt(plan: Plan, t: number, speed: number, reduced: boolean): (number, number)
	if reduced then
		return 0, 0
	end
	local shake = ElevatorTravelConfig.Shake
	local amp = shake.Ride * speed
	local dip = 0
	local jolt = t - plan.DoorsShut
	if jolt >= 0 and jolt < 0.35 then
		dip -= shake.Jolt * math.sin(math.pi * jolt / 0.35) * (1 - jolt / 0.35)
	end
	local bump = t - plan.StopAt
	if bump >= 0 and bump < 0.3 then
		dip -= shake.Bump * math.sin(math.pi * bump / 0.3) * (1 - bump / 0.3)
	end
	return noise(t, 23.1, 37.7) * amp, noise(t, 29.3, 41.9) * amp + dip
end

--[[
	The camera at `t`: nil before the dip (the game's own camera, the client
	shakes it), then in the cabin (a small push in while the doors close, the
	rumble, a lean as they open), then the glide back behind the player (or a
	cut at CutAt). Returns the frame and the field of view.
]]
function Stage.camera(plan: Plan, t: number, info: CameraInfo): (CFrame?, number)
	local fov = ElevatorTravelConfig.Fov
	if t < plan.DipMid then
		return nil, info.Fov
	end
	local at = if t >= plan.StopAt and info.StopAt then info.StopAt :: CFrame else info.FromAt
	local eye = Stage.Eye
	if t < plan.DoorsShut then
		eye = Stage.EyeStart:Lerp(Stage.Eye, easeOut((t - plan.DipMid) / (plan.DoorsShut - plan.DipMid)))
	elseif t >= plan.DoorsOpenAt then
		eye = Stage.Eye:Lerp(Stage.EyeOpen, smooth((t - plan.DoorsOpenAt) / ElevatorTravelConfig.Timing.DoorsOpen))
	end
	local sx, sy = Stage.shakeAt(plan, t, info.Speed, info.Reduced)
	local roll = math.rad(ElevatorTravelConfig.Shake.Turn) * sx / math.max(ElevatorTravelConfig.Shake.Ride, 1e-3)
	local inside = at * CFrame.lookAt(eye + Vector3.new(sx, sy, 0), Stage.LookAt) * CFrame.Angles(0, 0, roll * 0.15)
	local target = info.Target
	if not target then
		return inside, fov
	end
	local final = Stage.exitCamera(target, info.Zoom)
	local cutAt = info.CutAt
	if cutAt then
		if t >= cutAt + ElevatorTravelConfig.Timing.DipOut then
			return final, info.Fov
		end
		return inside, fov
	end
	if t < plan.ExitAt then
		return inside, fov
	end
	local u = clamp01((t - plan.ExitAt) / ElevatorTravelConfig.Timing.Exit)
	-- ease in-out (cubic)
	local k = if u < 0.5 then 4 * u * u * u else 1 - (-2 * u + 2) ^ 3 / 2
	return inside:Lerp(final, k), fov + (info.Fov - fov) * k
end

return Stage
