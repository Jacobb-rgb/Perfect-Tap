--[[
	Shared helpers of the Plaza package (src/server/World/Lobby/Plaza):
	the concept v2 palette (dark polished slate, dark machine metal, blue
	and orange neon), the list of road/path strips with their look, the
	plaza entrance test (where the curb opens), placement checks against
	the other packages' footprints, a flat cobble/dirt path strip builder
	(Style.path with a lift and a curb range, so overlapping strips never
	z-fight), the dark neon walkway (three columns of slate floor panels,
	dark metal borders with orange neon edge strips), flat neon rings and
	thin chevrons,
	and the dark metal lantern pillar with glowing orange slots and an amber
	lamp in a dark cage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

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
Common.TileReflectance = 0.06 -- polished slate (a hint of sky, the floor stays dark)

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
	Slate = rgb(40, 46, 64), -- polished floor tiles (mid): dark charcoal blue-grey
	SlateLight = rgb(52, 58, 80), -- lit / worn tiles
	SlateDark = rgb(32, 36, 50), -- shaded tiles
	SlateDeep = rgb(22, 25, 37), -- seams and the channels under the neon rings
	WalkPanel = rgb(34, 38, 54), -- walkway floor panels (matte, darker than the plaza)
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
	AmberGlass = rgb(255, 150, 62), -- lantern panes
	Chevron = rgb(255, 120, 30), -- deep orange chevrons
	WindowGlow = rgb(255, 150, 58), -- warm lit windows
	NeonOrange = C.Fire,
	NeonBlue = C.GlowEdge,
	-- a deeper, more saturated blue for the wide floor rings: it stays blue
	-- at the player's feet instead of blooming to a white-cyan hoop
	NeonBlueDeep = rgb(40, 124, 255),
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
-- plaza (the south road only up to the creek bridge, see Roads).
Common.NeonStrips = {
	SouthRoad = true,
	EastSpur = true,
	WestSpur = true,
	ForgePathEast = true,
	ForgePathWest = true,
	ToShop = true,
	ToUpgrades = true,
	ToWheel = true,
	ToFossil = true,
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

-- A polished slate tile color (mostly mid, some lit, some shaded).
function Common.slate(rng: Rng.Rng): Color3
	local roll = rng:next()
	local color = if roll < 0.52 then K.Slate elseif roll < 0.78 then K.SlateLight elseif roll < 0.96 then K.SlateDark else K.Metal
	return Style.vary(color, rng, 0.04)
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
	tip point on the floor): two neon bars of length `size` (keep them thin,
	<= 0.5, and a deep orange, so the arrow stays crisp under bloom). 2 parts.
]]
function Common.chevron(parent: Instance, tip: CFrame, size: number, thickness: number, color: Color3, height: number?): { Part }
	local h = height or 0.06
	local parts = {}
	for _, s in { -1, 1 } do
		-- each arm runs from the tip back (local +Z) and out to one side
		local dir = Vector3.new(s * math.sin(math.pi / 4), 0, math.cos(math.pi / 4))
		local cf = tip * CFrame.new(dir * (size / 2 - thickness / 2)) * CFrame.Angles(0, s * math.pi / 4, 0)
		table.insert(parts, Style.block(parent, cf, Vector3.new(thickness, h, size), color, NEON, Style.tiny()))
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

export type WalkwayOpts = {
	Lift: number?, -- extra height so overlapping strips never z-fight
	Name: string?,
	Self: string?, -- the strip's own Id (its edges ignore its own strip)
	EdgeInset: number?, -- the edge strips stop this far before `to`
}

-- Walkway measures (local heights over the lift): slab top, panel top,
-- border top, neon top. All flat (< 0.4: hidden under the plaza floor).
Common.WalkwayTop = { Slab = 0.23, Panel = 0.27, Border = 0.31, Neon = 0.33 }

--[[
	Dark neon walkway (concept v2, Kenney floor-panel) from `from` to `to`
	(ground points), extended by Width/2 past both ends like every strip.
	Flat and non-collide over the solid ground: a dark seam slab, three
	columns of polished slate panels between the borders with wide dark
	seams (a clear tile grid, none under the plaza floor), and along
	both edges a dark metal border with an orange neon strip, drawn only
	where the edge is in view (not on the plaza, another strip, another
	package's piece or a base).
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
	-- the far end stops at the edge of a crossing cobble/dirt road (no dark
	-- slab over the plot roads and the rim road)
	local endT = length + width / 2
	local scan = math.max(0, length - width)
	while scan < endT do
		local p = from + dir * scan
		local onOther = false
		for _, s in Common.strips() do
			if s.Id ~= o.Self and not s.Neon and LobbyLayout.distanceToStrip(s.From, s.To, s.Width, p) < 0.05 then
				onOther = true
				break
			end
		end
		if onOther then
			endT = scan
			break
		end
		scan += 0.25
	end
	local full = endT + width / 2
	local zMid = length / 2 - (endT - width / 2) / 2 -- local z of the slab center
	local top = Common.WalkwayTop
	local base = Style.block(
		m,
		frame * CFrame.new(0, top.Slab - 0.15, zMid),
		Vector3.new(width, 0.3, full),
		K.SlateDeep,
		nil,
		Style.tiny({ CanQuery = true })
	)
	base.Name = "PathBase"
	-- floor panels: three columns between the edge borders, 0.45 seams
	local half = width / 2
	local seam = 0.45
	local inner = width - 1.8
	local colW = inner / 3
	local rows = math.max(1, math.floor(full / (width * 0.65) + 0.5))
	local rowLen = full / rows
	for i = 0, rows - 1 do
		local z = zMid + full / 2 - (i + 0.5) * rowLen
		for c = 0, 2 do
			local cf = frame * CFrame.new(-inner / 2 + (c + 0.5) * colW, top.Panel - 0.03, z)
			if Vector3.new(cf.Position.X, 0, cf.Position.Z).Magnitude > Common.PlazaRadius - 0.5 then
				-- cool slate panels with the plaza's one light polish (the sky
				-- keeps them grey-blue under the warm sunset and the orange
				-- edges), light enough that the dark seams draw a grid
				local roll = rng:next()
				local shade = if roll < 0.55 then K.Slate elseif roll < 0.9 then K.SlateLight else K.Metal
				local panel =
					Style.block(m, cf, Vector3.new(colW - seam, 0.06, rowLen - seam), Style.vary(shade, rng, 0.03), nil, Style.tiny())
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
				Style.block(m, frame * CFrame.new(edgeX, top.Border - 0.05, z), Vector3.new(0.9, 0.1, len), K.MetalDark, nil, Style.tiny())
				local glow = Style.block(
					m,
					frame * CFrame.new(edgeX, top.Neon - 0.03, z),
					Vector3.new(0.28, 0.06, len - 0.2),
					K.NeonOrange,
					NEON,
					Style.tiny()
				)
				glow.Name = "EdgeGlow"
			end
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
	structure look): a dark plinth, a square metal shaft with two glowing
	orange slots on its front and back faces, a blue neon band under a dark
	collar, and the lamp: a small amber neon core inside orange glass panes
	(SmoothPlastic, Transparency 0.25) held by four thick dark corner bars,
	under a dark cap. Only the small core is neon, so the lamp glows amber
	inside a visible dark cage instead of blooming into a white block.
	`base` = ground point, LookVector = the slotted front. 13 parts; the
	plinth is the lowest part, the core ("LanternGlow") the PrimaryPart.
	opts.Light adds a PointLight (count it against the package budget).
]]
function Common.pillarLantern(parent: Instance, base: CFrame, opts: LanternOpts?): Model
	local o: LanternOpts = opts or {}
	local h = o.Height or 4.4
	local glowColor = o.Color or K.Amber
	local m = Style.model("Lantern", parent)
	Style.block(m, base * CFrame.new(0, 0.3, 0), Vector3.new(2.2, 0.6, 2.2), K.MetalDark)
	local shaftH = h - 0.6
	Style.block(m, base * CFrame.new(0, 0.6 + shaftH / 2, 0), Vector3.new(1.5, shaftH, 1.5), K.Metal)
	-- two neon bars through the shaft: two slots on the front, two on the back
	local slotH = math.max(0.6, shaftH - 1.5)
	for _, x in { -0.34, 0.34 } do
		local slot =
			Style.block(m, base * CFrame.new(x, 1.2 + slotH / 2, 0), Vector3.new(0.24, slotH, 1.56), K.NeonOrange, NEON, Style.tiny())
		slot.Name = "LanternSlot"
	end
	Style.block(m, base * CFrame.new(0, h - 0.32, 0), Vector3.new(1.58, 0.14, 1.58), K.NeonBlue, NEON, Style.tiny())
	Style.block(m, base * CFrame.new(0, h + 0.12, 0), Vector3.new(1.9, 0.24, 1.9), K.MetalDark, nil, Style.tiny())
	local glowY = h + 0.84
	local glow = Style.block(m, base * CFrame.new(0, glowY, 0), Vector3.new(0.6, 0.72, 0.6), glowColor, NEON, Style.tiny())
	glow.Name = "LanternGlow"
	local glass = Style.block(m, base * CFrame.new(0, glowY, 0), Vector3.new(1.12, 1.2, 1.12), K.AmberGlass, nil, Style.tiny())
	glass.Transparency = 0.25
	glass.Name = "LanternGlass"
	-- the cage: four thick dark corner bars
	for _, x in { -0.62, 0.62 } do
		for _, z in { -0.62, 0.62 } do
			Style.block(m, base * CFrame.new(x, glowY, z), Vector3.new(0.3, 1.3, 0.3), K.MetalDark, nil, Style.tiny())
		end
	end
	Style.block(m, base * CFrame.new(0, glowY + 0.75, 0), Vector3.new(1.75, 0.32, 1.75), K.MetalDark, nil, Style.tiny())
	if o.Light then
		Style.light(glow, glowColor, o.Range or 16, o.Brightness or 1.3)
	end
	m.PrimaryPart = glow
	return m
end

return Common
