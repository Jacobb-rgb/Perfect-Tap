--[[
	Shared helpers of the Plaza package (src/server/World/Lobby/Plaza):
	the concept v2 palette (dark polished slate, dark machine metal, blue
	and orange neon), the list of road/path strips with their look, the
	plaza entrance test (where the curb opens), placement checks against
	the other packages' footprints, a flat cobble/dirt path strip builder
	(Style.path with a lift and a curb range, so overlapping strips never
	z-fight), the dark neon walkway (three columns of slate floor panels,
	dark metal borders with orange neon edge strips, a dark metal threshold
	ramp where it meets the plaza), flat neon rings and bold (double)
	chevrons, and the dark metal lantern pillar with glowing orange slots
	and an amber lamp in a dark cage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)

local C = Style.C
local NEON = Enum.Material.Neon
local rgb = Color3.fromRGB

local Common = {}

Common.PlazaRadius = 36
Common.CurbRadius = 35.6
Common.FloorTop = 0.4 -- top of the collidable plaza disc
Common.TileTop = 0.43 -- top of the slate tiles (TownSpawn's top is 0.45, the spawn inlay 0.445)
Common.ForgeApproach = 11 -- half width of the open plaza edge in front of the forge
-- (lobby fix round 3: concept v2's polished blue-grey slate, a visible
-- tile grid; the red channel stays low so the sky's pink never turns the
-- floor lilac)
-- (Reflectance: 0.05 is a soft sheen in Roblox; above it the preview, and
-- at 0.15 Roblox too, mirrors the pink sky and the slate turns lilac)
Common.TileReflectance = 0.05 -- polished slate
Common.Seam = 0.28 -- gap between floor tiles (the dark disc shows as a grid)

--[[
	Concept v2 colors of this package (three shades per material, like
	Style.C): dark charcoal blue-grey slate for the plaza and the walkways,
	dark machine metal for the crystal's ring, the curbs and the lantern
	pillars, slate roof tiles with brick-red trim, the forge's crimson
	banners; glows: Fire (orange) and GlowEdge (blue) from Style.C, plus a
	few deeper tones (amber lamps, deep-orange chevrons, deep-gold emblem)
	that stay colored under bloom instead of turning white.
]]
Common.Colors = {
	-- (lobby fix round 3: the round-2 near-black slate read as asphalt; a
	-- polished blue-grey slate with a low red channel, so the pink sky
	-- does not turn it lilac)
	Slate = rgb(60, 68, 92), -- polished floor tiles (mid)
	SlateLight = rgb(76, 84, 110), -- lit / worn tiles
	SlateAccent = rgb(94, 102, 130), -- a few lighter accent slabs (about 4%)
	SlateDark = rgb(14, 16, 24), -- the thin seams between the tiles (only seams and recesses)
	SlateDeep = rgb(9, 10, 16), -- the deepest recesses
	WalkPanel = rgb(50, 57, 78), -- walkway floor panels (a little darker than the plaza)
	Metal = rgb(56, 60, 76), -- machine metal (mid)
	MetalLight = rgb(92, 100, 122), -- small bolts and collars
	MetalDark = rgb(34, 37, 48), -- ribs, plinths, recesses, cap plates
	RoofSlate = rgb(66, 72, 90), -- Great Forge roof slate (grey-blue, not glassy navy)
	RoofSlateDark = rgb(42, 46, 60), -- shingle courses and joints
	BrickRed = rgb(150, 46, 36), -- roof trim: eaves, bargeboards (concept v2)
	Banner = rgb(168, 12, 42), -- crimson banner cloth (a touch of blue: the sunset warms it)
	BannerDark = rgb(92, 8, 28), -- banner border / backing
	EmblemGold = rgb(255, 150, 30), -- deep gold glow of the gable emblem
	Amber = rgb(255, 140, 40), -- lantern glow (amber, not white)
	SlotAmber = rgb(255, 70, 10), -- deep orange lantern slots (they stay orange under bloom, never yellow paint)
	AmberGlass = rgb(255, 150, 62), -- lantern panes
	Chevron = rgb(255, 72, 14), -- deep orange chevrons (bold, they stay orange under bloom)
	RingOrange = rgb(255, 84, 18), -- the bold orange floor rings
	WindowGlow = rgb(255, 150, 58), -- warm lit windows
	NeonOrange = C.Fire,
	NeonBlue = C.GlowEdge,
	-- a deeper, more saturated blue for the wide floor rings: it stays blue
	-- at the player's feet instead of blooming to a white-cyan hoop
	NeonBlueDeep = rgb(10, 90, 255), -- (round 3: deep electric blue, never pastel)
}
local K = Common.Colors

export type Strip = {
	Id: string,
	From: Vector3,
	To: Vector3,
	Width: number,
	Kind: string, -- "Cobble" | "Dirt"
	Lift: number, -- stacking order where strips overlap (cobble over dirt)
	Main: boolean, -- a WorldLayout road (lanterns, curbs near the plaza)
	Neon: boolean, -- paved as a dark neon walkway (concept v2) near the plaza
}

-- Strips paved as dark neon walkways: the roads and paths that leave the
-- plaza, and (owner 2026-10-20: "every road like the ones to the forge")
-- the plot roads, the rim road and every far path too.
Common.NeonStrips = {
	SouthRoad = true,
	EastSpur = true,
	WestSpur = true,
	ForgePathEast = true,
	ForgePathWest = true,
	ToShop = true,
	ToUpgrades = true,
	ToWheel = true,
	ToDroppers = true,
	EastPlotRoad = true,
	WestPlotRoad = true,
	RimRoad = true,
	ToScanner = true,
	MineLane = true,
	ToMine = true,
	HamletLane = true,
	ToMap = true,
	ToNextArea = true,
}

local function roadName(road: WorldLayout.Road): string
	local a, b = road.From, road.To
	if math.abs(a.X - b.X) < 0.01 then
		if math.abs(a.X) < 0.01 then
			return "SouthRoad"
		elseif math.abs(a.X) >= 60 then
			return if a.X > 0 then "EastPlotRoad" else "WestPlotRoad"
		end
		return if a.X > 0 then "ForgePathEast" else "ForgePathWest"
	end
	if a.Z <= -100 then
		return "RimRoad"
	end
	return if a.X + b.X > 0 then "EastSpur" else "WestSpur"
end

local stripCache: { Strip }? = nil

-- Every WorldLayout road and LobbyLayout path with the look the plan gives it:
-- plot roads, the rim road, ToMine and ToNextArea are dirt, the rest cobble.
function Common.strips(): { Strip }
	if stripCache then
		return stripCache
	end
	local list: { Strip } = {}
	for _, road in WorldLayout.Roads do
		local id = roadName(road)
		local dirt = id == "EastPlotRoad" or id == "WestPlotRoad" or id == "RimRoad"
		table.insert(list, {
			Id = id,
			From = road.From,
			To = road.To,
			Width = road.Width,
			Kind = if dirt then "Dirt" else "Cobble",
			Lift = if id == "RimRoad" then 0.012 elseif dirt then 0 else 0.03,
			Main = true,
			Neon = Common.NeonStrips[id] == true,
		})
	end
	for _, path in LobbyLayout.Paths do
		local dirt = path.Kind == "Dirt" or path.Id == "ToNextArea"
		table.insert(list, {
			Id = path.Id,
			From = path.From,
			To = path.To,
			Width = path.Width,
			Kind = if dirt then "Dirt" else "Cobble",
			Lift = if dirt then 0.022 else 0.045,
			Main = false,
			Neon = Common.NeonStrips[path.Id] == true,
		})
	end
	stripCache = list
	return list
end

function Common.strip(id: string): Strip
	for _, s in Common.strips() do
		if s.Id == id then
			return s
		end
	end
	error("unknown strip " .. id)
end

-- Is the plaza edge open at this angle (radians from +X toward +Z)? Open
-- where a road or path enters and in front of the forge.
function Common.isEntrance(angle: number, margin: number?): boolean
	local p = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Common.CurbRadius
	if p.Z < 0 and math.abs(p.X) < Common.ForgeApproach then
		return true
	end
	for _, s in Common.strips() do
		if LobbyLayout.distanceToStrip(s.From, s.To, s.Width, p) < (margin or 0.8) then
			return true
		end
	end
	return false
end

-- Ground point clear of every other package's ground pieces, the ore
-- outcrops, the player bases, the keep-out boxes and the quarry pit.
function Common.isClear(p: Vector3, radius: number): boolean
	for _, piece in LobbyLayout.Pieces do
		if piece.Package ~= "Plaza" and LobbyLayout.isGroundPiece(piece) and LobbyLayout.distanceTo(piece, p) < radius + 0.5 then
			return false
		end
	end
	local flat = Vector3.new(p.X, 0, p.Z)
	for _, spot in WorldLayout.OutcropSpots do
		if (flat - Vector3.new(spot.X, 0, spot.Z)).Magnitude < radius + 6 then
			return false
		end
	end
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, p, radius) then
			return false
		end
	end
	if WorldLayout.isKeepOut(p, radius) then
		return false
	end
	if p.Z < WorldLayout.Quarry.Max.Z + radius + 0.5 then
		return false
	end
	return true
end

-- Ground point off every road and path strip.
function Common.offStrips(p: Vector3, radius: number): boolean
	for _, s in Common.strips() do
		if LobbyLayout.distanceToStrip(s.From, s.To, s.Width, p) < radius + 0.2 then
			return false
		end
	end
	return true
end

export type PathOpts = {
	Kind: string?, -- "Cobble" (default) | "Dirt"
	TileEvery: number?, -- studs between tile rows
	CurbUntil: number?, -- curb stones from the strip start up to this distance (studs)
	CurbEvery: number?,
	Lift: number?, -- extra height so overlapping strips never z-fight
	Name: string?,
	CurbSkip: ((Vector3) -> boolean)?, -- no curb stone where this returns true
}

--[[
	Flat walk-over path strip from `from` to `to` (ground points), extended
	by Width/2 past both ends like the road strips (tests use the same rule).
	Non-collide over the solid ground. One base slab, one tile per row
	(alternating sides), optional curb stones near the start.
]]
function Common.path(parent: Instance, from: Vector3, to: Vector3, width: number, rng: Rng.Rng, opts: PathOpts?): Model
	local o: PathOpts = opts or {}
	local m = Style.model(o.Name or "Path", parent)
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	if length < 0.5 then
		return m
	end
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local lift = o.Lift or 0
	local mid = Vector3.new((from.X + to.X) / 2, lift, (from.Z + to.Z) / 2)
	local frame = CFrame.fromMatrix(mid, right, Vector3.new(0, 1, 0), -dir)
	local kind = o.Kind or "Cobble"
	local dirt = kind == "Dirt"
	local full = length + width
	local base = Style.block(
		m,
		frame * CFrame.new(0, 0.08, 0),
		Vector3.new(width, 0.3, full),
		if dirt then C.DirtLight else C.Cobble,
		nil,
		Style.tiny({ CanQuery = true })
	)
	base.Name = "PathBase"
	local every = o.TileEvery or (if dirt then 7 else 4.5)
	local rows = math.floor(full / every)
	for i = 0, rows - 1 do
		local z = -full / 2 + (i + 0.5) * (full / rows)
		local tw = if dirt then rng:range(1.6, 3) else math.min(width * 0.42, rng:range(2.2, 3.4))
		local side = if i % 2 == 0 then -1 else 1
		local x = side * rng:range(0.15, 0.5) * (width / 2 - tw / 2 - 0.3)
		local shade = if dirt then (if rng:chance(0.6) then C.Dirt else C.Sand) elseif rng:chance(0.5) then C.FlagLight else C.CobbleDark
		Style.block(
			m,
			frame * CFrame.new(x, 0.26, -z),
			Vector3.new(tw, 0.08, rng:range(1.4, 2.2)),
			Style.vary(shade, rng, 0.05),
			nil,
			Style.tiny()
		)
	end
	local curbUntil = o.CurbUntil or 0
	if curbUntil > 0 then
		local curbEvery = o.CurbEvery or 4
		local count = math.floor(math.min(curbUntil, full) / curbEvery)
		for i = 0, count - 1 do
			local side = if i % 2 == 0 then -1 else 1
			-- local -Z runs from `from` to `to`: the strip starts at +full/2
			local z = full / 2 - (i + 0.5) * curbEvery
			local cf = frame * CFrame.new(side * (width / 2 + 0.3), 0.25, z)
			if o.CurbSkip and o.CurbSkip(cf.Position) then
				continue
			end
			Style.block(m, cf, Vector3.new(1.1, 0.5, rng:range(1.6, 2.4)), Style.vary(C.StoneDark, rng, 0.06), nil, Style.tiny())
		end
	end
	return m
end

---------------------------------------------------------------- concept v2 kit

-- A polished slate tile color (mostly mid, some lit, a few light accents;
-- the dark shades are for the seams only).
function Common.slate(rng: Rng.Rng): Color3
	local roll = rng:next()
	local color = if roll < 0.6 then K.Slate elseif roll < 0.96 then K.SlateLight else K.SlateAccent
	return Style.vary(color, rng, 0.03)
end

-- The slate shades of a radial course, alternating tile by tile so the
-- grid reads: course `ring`, tile `i`.
Common.CourseShades = { K.Slate, K.SlateLight, K.SlateAccent }
function Common.courseSlate(ring: number, i: number, rng: Rng.Rng): Color3
	-- mid and lit slabs alternate; about one in 25 is a lighter accent slab
	local k = if rng:chance(0.04) then 3 else (i + ring) % 2 + 1
	return Style.vary(Common.CourseShades[k], rng, 0.025)
end

--[[
	A part with the polished slate finish (SmoothPlastic + a little
	Reflectance). Every slab gets the same sheen (one polished floor, not a
	patchwork of glossy and matte slabs); Common.slate varies the color.
]]
function Common.polish(part: BasePart): BasePart
	part.Reflectance = Common.TileReflectance
	return part
end

--[[
	Flat ring of straight segments lying on the floor (a neon ring, a
	channel). `y` = segment center height. opts: Dash (drawn fraction of
	each segment, default 1.02 = closed ring), Phase (in segments), Skip
	(no segment where it returns true for the segment center), Material.
]]
export type RingOpts = {
	Dash: number?,
	Phase: number?,
	Skip: ((Vector3) -> boolean)?,
	Material: Enum.Material?,
}
function Common.ring(
	parent: Instance,
	center: Vector3,
	radius: number,
	width: number,
	y: number,
	height: number,
	segments: number,
	color: Color3,
	opts: RingOpts?
): { Part }
	local o: RingOpts = opts or {}
	local chord = 2 * radius * math.sin(math.pi / segments)
	local inner = radius * math.cos(math.pi / segments)
	local parts = {}
	for i = 0, segments - 1 do
		local a = (i + (o.Phase or 0)) / segments * 2 * math.pi
		local frame = CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, -a, 0) * CFrame.new(inner, 0, 0)
		if o.Skip and o.Skip(frame.Position) then
			continue
		end
		table.insert(
			parts,
			Style.block(parent, frame, Vector3.new(width, height, chord * (o.Dash or 1.02)), color, o.Material or NEON, Style.tiny())
		)
	end
	return parts
end

--[[
	Flat glowing chevron "^" pointing along the LookVector of `tip` (the
	tip point on the floor): two neon bars of length `size`, each `spread`
	radians off the arrow's axis (default 45 degrees; the concept's wide,
	flat arrows use ~58). A deep orange keeps it orange under bloom. 2 parts.
]]
function Common.chevron(
	parent: Instance,
	tip: CFrame,
	size: number,
	thickness: number,
	color: Color3,
	height: number?,
	spread: number?
): { Part }
	local h = height or 0.06
	local a = spread or math.pi / 4
	local parts = {}
	for _, s in { -1, 1 } do
		-- each arm runs from the tip back (local +Z) and out to one side
		local dir = Vector3.new(s * math.sin(a), 0, math.cos(a))
		local cf = tip * CFrame.new(dir * (size / 2 - thickness / 2)) * CFrame.Angles(0, s * a, 0)
		table.insert(parts, Style.block(parent, cf, Vector3.new(thickness, h, size), color, NEON, Style.tiny()))
	end
	return parts
end

-- The concept v2 arrow: two bold nested chevrons, the second `gap` studs
-- behind the first (along the arrow's axis), wide and flat, each stroke a
-- deep-orange body with a thin bright core line on top (the core blooms,
-- so the arrow glows like a neon tube instead of reading as road paint).
-- Returns the 4 strokes; the 4 cores are named "ChevronCore". 8 parts.
Common.ChevronSpread = math.rad(58)
function Common.doubleChevron(
	parent: Instance,
	tip: CFrame,
	size: number,
	thickness: number,
	gap: number,
	color: Color3,
	height: number?
): { Part }
	local h = height or 0.06
	local parts = Common.chevron(parent, tip, size, thickness, color, h, Common.ChevronSpread)
	for _, part in Common.chevron(parent, tip * CFrame.new(0, 0, gap), size, thickness, color, h, Common.ChevronSpread) do
		table.insert(parts, part)
	end
	for _, stroke in parts do
		local core = Style.block(
			parent,
			stroke.CFrame * CFrame.new(0, h / 2, 0),
			Vector3.new(thickness * 0.3, 0.03, size - thickness),
			K.NeonOrange,
			NEON,
			Style.tiny()
		)
		core.Name = "ChevronCore"
	end
	return parts
end

-- Is this point of a walkway edge in view: off the plaza, off every other
-- road/path strip, off the other packages' ground pieces and the bases?
local function edgeVisible(p: Vector3, selfId: string?): boolean
	if Vector3.new(p.X, 0, p.Z).Magnitude < Common.PlazaRadius + 0.3 then
		return false
	end
	for _, s in Common.strips() do
		if s.Id ~= selfId and LobbyLayout.distanceToStrip(s.From, s.To, s.Width, p) < 0.05 then
			return false
		end
	end
	for _, piece in LobbyLayout.Pieces do
		if piece.Package ~= "Plaza" and LobbyLayout.isGroundPiece(piece) and LobbyLayout.distanceTo(piece, p) < 0.2 then
			return false
		end
	end
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, p, 0.2) then
			return false
		end
	end
	return true
end

-- Does another strip win the junction at p over the walkway `selfId`? A
-- cobble/dirt strip always does; a walkway that lies lower (the plot roads
-- under the spurs, the rim road under the forge paths) or as low and
-- earlier in Common.strips() (two lanes meeting end to end) does too, so
-- slabs never stack or z-fight.
local function covered(p: Vector3, selfId: string?): boolean
	local strips = Common.strips()
	local own: Strip? = nil
	local ownIndex = 0
	for i, s in strips do
		if s.Id == selfId then
			own, ownIndex = s, i
			break
		end
	end
	for i, s in strips do
		if s.Id ~= selfId and LobbyLayout.distanceToStrip(s.From, s.To, s.Width, p) < 0.05 then
			if not s.Neon then
				return true
			end
			if own and (s.Lift < own.Lift - 1e-6 or (math.abs(s.Lift - own.Lift) <= 1e-6 and i < ownIndex)) then
				return true
			end
		end
	end
	return false
end

export type WalkwayOpts = {
	Lift: number?, -- extra height so overlapping strips never z-fight
	Name: string?,
	Self: string?, -- the strip's own Id (its edges ignore its own strip)
	EdgeInset: number?, -- the edge strips stop this far before `to`
	RowScale: number?, -- panel row length / strip width (default 0.65; longer slabs on the long side paths)
	Threshold: boolean?, -- a dark metal ramp where the strip leaves the plaza (bridges the step down)
}

-- Walkway measures (local heights over the lift): slab top, panel top,
-- border top, neon top. All flat (< 0.4: hidden under the plaza floor).
Common.WalkwayTop = { Slab = 0.23, Panel = 0.27, Border = 0.31, Neon = 0.33 }

--[[
	Dark neon walkway (concept v2, Kenney floor-panel) from `from` to `to`
	(ground points), extended by Width/2 past both ends like every strip.
	Flat and non-collide over the solid ground: a dark seam slab, three
	columns of polished slate panels between the borders with thin dark
	seams (a tile grid, none under the plaza floor), and along both edges a
	dark metal border with an orange neon strip, drawn only where the edge
	is in view (not on the plaza, another strip, another package's piece or
	a base). opts.Threshold adds a dark metal ramp where the strip leaves
	the plaza rim, so the plaza floor (0.43) runs down to the panels without
	a lip or a dark trench.
]]
function Common.walkway(parent: Instance, from: Vector3, to: Vector3, width: number, rng: Rng.Rng, opts: WalkwayOpts?): Model
	local o: WalkwayOpts = opts or {}
	local m = Style.model(o.Name or "Walkway", parent)
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	if length < 0.5 then
		return m
	end
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local lift = o.Lift or 0
	local mid = Vector3.new((from.X + to.X) / 2, lift, (from.Z + to.Z) / 2)
	-- local -Z runs from `from` to `to`; t (studs from `from`) sits at z = length/2 - t
	local frame = CFrame.fromMatrix(mid, right, Vector3.new(0, 1, 0), -dir)
	-- both ends stop at the edge of a crossing strip that wins the junction
	-- (no stacked slabs: the spurs end at the plot roads, the forge paths
	-- at the rim road, the far lanes where they leave a road)
	local startT = -width / 2
	while startT < math.min(length, width) and covered(from + dir * startT, o.Self) do
		startT += 0.25
	end
	local endT = length + width / 2
	-- (from where the start overlap ends: a short lane starts and ends on roads)
	local scan = math.max(startT, length - width)
	while scan < endT do
		if covered(from + dir * scan, o.Self) then
			endT = scan
			break
		end
		scan += 0.25
	end
	local full = endT - startT
	local zMid = length / 2 - (startT + endT) / 2 -- local z of the slab center
	local top = Common.WalkwayTop
	local base = Style.block(
		m,
		frame * CFrame.new(0, top.Slab - 0.15, zMid),
		Vector3.new(width, 0.3, full),
		K.SlateDark,
		nil,
		Style.tiny({ CanQuery = true })
	)
	base.Name = "PathBase"
	-- floor panels: three columns between the edge borders, thin seams
	local half = width / 2
	local seam = 0.2
	local inner = width - 1.8
	local colW = inner / 3
	local rows = math.max(1, math.floor(full / (width * (o.RowScale or 0.65)) + 0.5))
	local rowLen = full / rows
	for i = 0, rows - 1 do
		local z = zMid + full / 2 - (i + 0.5) * rowLen
		for c = 0, 2 do
			local cf = frame * CFrame.new(-inner / 2 + (c + 0.5) * colW, top.Panel - 0.03, z)
			if Vector3.new(cf.Position.X, 0, cf.Position.Z).Magnitude > Common.PlazaRadius - 0.5 then
				-- cool slate panels with the plaza's one light polish (the sky
				-- keeps them grey-blue under the warm sunset and the orange
				-- edges), light enough that the dark seams draw a grid
				local panel =
					Style.block(m, cf, Vector3.new(colW - seam, 0.06, rowLen - seam), Common.courseSlate(i, c, rng), nil, Style.tiny())
				panel.Reflectance = Common.TileReflectance
				panel.Name = "WalkPanel"
			end
		end
	end
	-- edge borders with orange neon strips, in runs where the edge is in view
	local stepLen = 0.5
	local stop = length - (o.EdgeInset or 0)
	for _, side in { -1, 1 } do
		local edgeX = side * (half - 0.45)
		local runs: { { number } } = {}
		local runStart: number? = nil
		local t = 0
		while t <= stop + 1e-6 do
			local p = from + dir * t + right * edgeX
			local visible = edgeVisible(p, o.Self)
			if visible and not runStart then
				runStart = t
			elseif not visible and runStart then
				table.insert(runs, { runStart, t - stepLen })
				runStart = nil
			end
			t += stepLen
		end
		if runStart then
			table.insert(runs, { runStart, math.min(t - stepLen, stop) })
		end
		for _, run in runs do
			local t0, t1 = run[1], run[2]
			if t1 - t0 >= 1.5 then
				local z = length / 2 - (t0 + t1) / 2
				local len = t1 - t0
				Style.block(m, frame * CFrame.new(edgeX, top.Border - 0.05, z), Vector3.new(0.65, 0.1, len), K.MetalDark, nil, Style.tiny())
				local glow = Style.block(
					m,
					frame * CFrame.new(edgeX, top.Neon - 0.03, z),
					Vector3.new(0.2, 0.06, len - 0.2),
					K.NeonOrange,
					NEON,
					Style.tiny()
				)
				glow.Name = "EdgeGlow"
			end
		end
	end
	if o.Threshold then
		-- where the centerline crosses the plaza rim (|from + dir t| = PlazaRadius)
		local f = Vector3.new(from.X, 0, from.Z)
		local b = f:Dot(dir)
		local disc = b * b - (f:Dot(f) - Common.PlazaRadius * Common.PlazaRadius)
		if disc >= 0 then
			local t0 = -b + math.sqrt(disc)
			local rampLen = 1.8
			local panelTop = lift + top.Panel
			local high = Common.TileTop - 0.005
			-- WedgePart: tall side at local +Z (toward the plaza), low end sunk under the panels
			local c = from + dir * (t0 + rampLen / 2 - 0.15)
			local h = high - (panelTop - 0.04)
			local center = Vector3.new(c.X, panelTop - 0.04 + h / 2, c.Z)
			-- (lookAt: LookVector = dir, so local +Z = -dir points back to the plaza)
			local ramp = Geo.wedge(m, CFrame.lookAt(center, center + dir), Vector3.new(width, h, rampLen), K.MetalDark, nil, Style.tiny())
			ramp.Name = "Threshold"
		end
	end
	return m
end

export type LanternOpts = {
	Height: number?, -- top of the shaft (default 4.4)
	Light: boolean?,
	Range: number?,
	Brightness: number?,
	Color: Color3?, -- lamp core glow (default Amber)
}

--[[
	Dark metal lantern pillar (concept v2 foreground, Kenney pipe-ring /
	structure look): a dark plinth, a square metal shaft with a glowing
	orange slot on its front and back faces, a blue neon band under a dark
	collar, and the lamp: a small amber neon core inside orange glass panes
	(SmoothPlastic, Transparency 0.25) held by four thick dark corner bars,
	under a dark cap. Only the small core is neon, so the lamp glows amber
	inside a visible dark cage instead of blooming into a white block.
	`base` = ground point, LookVector = the slotted front. 12 parts; the
	plinth is the lowest part, the core ("LanternGlow") the PrimaryPart.
	opts.Light adds a PointLight (count it against the package budget).
]]
function Common.pillarLantern(parent: Instance, base: CFrame, opts: LanternOpts?): Model
	local o: LanternOpts = opts or {}
	local h = o.Height or 4.4
	local glowColor = o.Color or K.Amber
	local m = Style.model("Lantern", parent)
	-- (decorative: it collides, but is never raycast, e.g. by the camera)
	Style.block(m, base * CFrame.new(0, 0.3, 0), Vector3.new(2.2, 0.6, 2.2), K.MetalDark, nil, Style.decor())
	local shaftH = h - 0.6
	Style.block(m, base * CFrame.new(0, 0.6 + shaftH / 2, 0), Vector3.new(1.5, shaftH, 1.5), K.Metal, nil, Style.decor())
	-- the slot panel: a dark metal plate through the shaft (front and back
	-- faces, 0.06 proud) framing one deep-orange neon slot, so it reads as
	-- a glowing slit set in dark metal, not as a yellow paint stripe
	-- (lobby fix round 3: one slot instead of two)
	local slotH = math.max(0.6, shaftH - 1.5)
	Style.block(m, base * CFrame.new(0, 1.2 + slotH / 2, 0), Vector3.new(0.7, slotH + 0.36, 1.62), K.MetalDark, nil, Style.tiny()).Name =
		"SlotPanel"
	local slot = Style.block(m, base * CFrame.new(0, 1.2 + slotH / 2, 0), Vector3.new(0.2, slotH, 1.66), K.SlotAmber, NEON, Style.tiny())
	slot.Name = "LanternSlot"
	Style.block(m, base * CFrame.new(0, h - 0.32, 0), Vector3.new(1.58, 0.14, 1.58), K.NeonBlueDeep, NEON, Style.tiny())
	Style.block(m, base * CFrame.new(0, h + 0.12, 0), Vector3.new(1.9, 0.24, 1.9), K.MetalDark, nil, Style.tiny())
	-- the lamp (lobby fix round 3: no bare glowing cube): a small amber neon
	-- core inside amber glass panes (not neon: they read as glass, the core
	-- shines through), four thin dark corner bars and a dark cap plate that
	-- overhangs the cage by 0.2
	local glowY = h + 0.84
	local glow = Style.block(m, base * CFrame.new(0, glowY, 0), Vector3.new(0.6, 0.72, 0.6), glowColor, NEON, Style.tiny())
	glow.Name = "LanternGlow"
	local glass = Style.block(m, base * CFrame.new(0, glowY, 0), Vector3.new(1.1, 1.16, 1.1), K.AmberGlass, nil, Style.tiny())
	glass.Transparency = 0.3
	glass.Name = "LanternGlass"
	for _, x in { -0.6, 0.6 } do
		for _, z in { -0.6, 0.6 } do
			Style.block(m, base * CFrame.new(x, glowY, z), Vector3.new(0.18, 1.3, 0.18), K.MetalDark, nil, Style.tiny())
		end
	end
	Style.block(m, base * CFrame.new(0, glowY + 0.75, 0), Vector3.new(1.98, 0.24, 1.98), K.MetalDark, nil, Style.tiny()).Name = "LanternCap"
	if o.Light then
		Style.light(glow, glowColor, o.Range or 16, o.Brightness or 1.3)
	end
	m.PrimaryPart = glow
	return m
end

return Common
