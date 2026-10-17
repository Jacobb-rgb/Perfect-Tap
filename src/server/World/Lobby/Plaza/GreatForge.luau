--[[
	THE GREAT FORGE (LOBBY_PLAN 6.3.4, restyled after concept v2), the
	landmark north of the plaza. Footprint x -21..21, z -78..-38 (piece
	GreatForge), front toward the plaza, everything but the chimneys below
	y 32.

	Read like concept v2: a low, wide hall under one big gable. The forge
	stands on a raised stone plinth (porch at y 4.9) reached by a monumental
	flight of ten risers between stone cheek walls with dark metal handrails
	(orange neon undersides, Kenney stairs-handrail) and a dark metal lantern
	pillar on each cheek. The tall arched doorway (a stone arch under a dark
	timber lintel) opens on a glowing workshop: three furnace mouths recessed
	in dark iron boxes behind grate bars in a warm-orange furnace wall, an
	anvil and a tool rack, hanging lamps. Right over the lintel a 2-stud
	timber beam band carries THE GREAT FORGE board (iron straps at its ends)
	at the foot of a big, steep dark slate cross gable (eave 16.5, apex
	31.3: the gable is nearly half the facade) framed by brick-red
	bargeboards; inside the gable a dark metal crest carries the big glowing
	gold crossed hammers. Two lower stone wings with dark slate roofs
	(thin shingle courses, brick-red eaves) flank it; two long crimson
	banners with gold hammers hang from dark metal arms at the nave corners,
	from just under the gable's eave down to the porch, right beside the
	door pillars; a gold mine cart and dark metal crates beside the stairs;
	two chimneys at the back corners (x +-18, z -74.5).

	Local frame (LobbyLayout.frame): origin at the piece center on the
	ground, front = -Z (toward the plaza), local +X = the viewer's left
	when seen from the plaza. Four PointLights: the furnace, the threshold
	and the two stair lanterns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local C = Style.C
local K = Common.Colors
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic

local GreatForge = {}

-- Main measures (local frame, studs). Exposed for the spec.
GreatForge.HalfWidth = 21
GreatForge.PlinthTop = 4.9 -- the raised porch and hall floor
GreatForge.WingEave = 14.4
GreatForge.WingRoofHeight = 5.2 -- wing ridge 19.6: it dies into the nave roof's slope
GreatForge.NaveEave = 16.5 -- the gable starts right over the entrance's beam band
GreatForge.NaveRoofHeight = 14.8 -- gable apex 31.3 (47% of the facade)
GreatForge.NaveRoofHalf = 12 -- the cross gable spans x -12..12
GreatForge.ChimneyTop = 43
GreatForge.SignY = 18.2 -- THE GREAT FORGE board center (at the foot of the gable)
GreatForge.SignWidth = 19.5 -- (the nave walls span x -9..9: the ends hang on iron straps)
GreatForge.SignHeight = 4
GreatForge.EmblemY = 24.25 -- center of the gold crossed hammers inside the gable
GreatForge.EmblemSize = 7.2 -- ~35% of the gable's width, like the concept's emblem
GreatForge.StairHalfWidth = 8 -- the flight runs x -8..8 (the door width)
GreatForge.StairSteps = 10 -- risers of 0.45 from the plaza apron (y 0.4) to the porch
GreatForge.DoorTop = 12.9
GreatForge.DoorHalf = 7
GreatForge.BannerX = 11.3 -- banner centers (local x = +-11.3), right beside the door pillars (x +-8.2)
GreatForge.BannerWidth = 3.4

local PLINTH_TOP = GreatForge.PlinthTop
local NAVE = 9 -- nave wall half width
local NAVE_FRONT = -9
local WING_FRONT = -7
local WALL_BACK = 16
local PORCH_FRONT = -11 -- the plinth front (top of the stairs)
local WING_EAVE = GreatForge.WingEave
local NAVE_EAVE = GreatForge.NaveEave
local WING_ROOF_H = GreatForge.WingRoofHeight
local NAVE_ROOF_H = GreatForge.NaveRoofHeight
local NAVE_HALF = GreatForge.NaveRoofHalf
local NAVE_PITCH = NAVE_ROOF_H / NAVE_HALF
local APEX = NAVE_EAVE + NAVE_ROOF_H
local WING_ROOF_Z0 = WING_FRONT - 0.5 -- wing roofs: front eave .. back eave
local WING_ROOF_Z1 = WALL_BACK + 1.5
local WING_ROOF_X0 = NAVE -- wing roofs: x 9..20.6 (the inner end hides under the nave roof)
local WING_ROOF_X1 = 20.6
local NAVE_ROOF_Z0 = NAVE_FRONT - 1 -- nave roof: front gable .. back
local NAVE_ROOF_Z1 = WALL_BACK + 1.5
local DOOR_HALF = GreatForge.DoorHalf
local DOOR_TOP = GreatForge.DoorTop
local LINTEL_TOP = DOOR_TOP + 1.2 -- the dark timber lintel over the door (y 12.8 .. 14.1)
local WING_X = NAVE + 5.5 -- wing centers (wings x 9..20)
local FIRELIT = Color3.fromRGB(158, 98, 64) -- hall walls lit by the furnaces
local FIRELIT_DARK = Color3.fromRGB(100, 58, 42) -- the back wall over the furnaces
local HEARTH = Color3.fromRGB(204, 108, 46) -- the furnace wall: the whole hall glows warm orange
local IRON_DARK = Color3.fromRGB(38, 36, 40) -- furnace boxes and grates

-- dark slate roofs with brick-red eaves and gable boards (bargeboards); the
-- shingle courses are drawn here (thin lines, no thick Style rows)
local NAVE_ROOF = { Rows = 0, Color = K.RoofSlate, Dark = K.RoofSlateDark, Trim = K.BrickRed, Ridge = false }
local WING_ROOF = { Rows = 0, Color = K.RoofSlate, Dark = K.RoofSlateDark, Trim = K.BrickRed }

function GreatForge.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("GreatForge")
	local frame = LobbyLayout.frame(piece)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local m = Style.model("GreatForge", parent)
	local front = -piece.Size.Z / 2

	-- slate shingle courses on the given slopes of a Style.gableRoof (same
	-- frame and measures): thin horizontal course lines and, with `stubs`,
	-- short staggered joints in every course (1 more on odd courses), so the
	-- roofs read as narrow rows of slate shingles (not a grid of panels)
	local function roofCourses(cf: CFrame, width: number, depth: number, height: number, sides: { number }, rows: number, stubs: number?)
		local half = depth / 2
		local slope = math.atan2(height, half)
		local slopeLen = math.sqrt(height * height + half * half)
		local band = slopeLen / (rows + 1)
		for _, side in sides do
			local rot = CFrame.Angles(side * slope, 0, 0)
			-- t = 0 at the ridge, 1 at the eave (along the slope)
			local function onSlope(x: number, t: number): CFrame
				return cf * CFrame.new(x, height * (1 - t) + 0.05, side * half * t) * rot
			end
			for r = 1, rows do
				Style.block(m, onSlope(0, r / (rows + 1)), Vector3.new(width - 0.1, 0.15, 0.16), K.RoofSlateDark, nil, Style.tiny())
			end
			if stubs then
				for r = 0, rows do
					local n = stubs + (r % 2)
					for i = 1, n do
						local x = -width / 2 + width * (i - 0.5) / n
						Style.block(
							m,
							onSlope(x, (r + 0.5) / (rows + 1)),
							Vector3.new(0.15, 0.15, band - 0.35),
							K.RoofSlateDark,
							nil,
							Style.tiny()
						)
					end
				end
			end
		end
	end

	-- a vertical triangle facing local -Z (two wedges): gable infills, the crest top
	local function triangle(cf: CFrame, halfWidth: number, height: number, thickness: number, color: Color3, material: Enum.Material?)
		for _, s in { -1, 1 } do
			Geo.wedge(
				m,
				cf * CFrame.new(s * halfWidth / 2, height / 2, 0) * CFrame.Angles(0, -s * math.pi / 2, 0),
				Vector3.new(thickness, height, halfWidth),
				color,
				material or SMOOTH,
				Style.tiny()
			)
		end
	end

	------------------------------------------------------------ plinth and the monumental stairs
	Style.block(
		m,
		at(0, PLINTH_TOP / 2, (PORCH_FRONT + 20) / 2),
		Vector3.new(42, PLINTH_TOP, 20 - PORCH_FRONT),
		Style.vary(C.StoneDark, rng, 0.03),
		nil,
		Style.solid()
	)
	-- light coping along the porch edge, a dark base course under it
	Style.block(m, at(0, PLINTH_TOP - 0.15, PORCH_FRONT - 0.1), Vector3.new(42, 0.3, 0.4), C.StoneLight, nil, Style.tiny())
	for _, s in { -1, 1 } do
		Style.block(m, at(s * 15.3, 0.6, PORCH_FRONT - 0.1), Vector3.new(11.4, 1.2, 0.3), C.StoneDeep, nil, Style.tiny())
	end
	-- ten risers of 0.45 from the plaza apron (y 0.4) to the porch, treads 1 deep
	local steps = GreatForge.StairSteps
	local tread = (PORCH_FRONT - front) / (steps - 1)
	local rise = (PLINTH_TOP - 0.4) / steps
	local stairHalf = GreatForge.StairHalfWidth
	for k = 1, steps - 1 do
		local z0 = front + (k - 1) * tread
		local top = 0.4 + k * rise
		local step = Style.block(
			m,
			at(0, top / 2, (z0 + PORCH_FRONT) / 2),
			Vector3.new(stairHalf * 2, top, PORCH_FRONT - z0),
			Style.vary(if k % 2 == 0 then C.Stone else C.StoneLight, rng, 0.03),
			nil,
			Style.solid()
		)
		step.Name = "Stair"
		-- dark shadow line at the foot of each riser (the steps read from afar)
		if k > 1 then
			Style.block(m, at(0, top - rise + 0.06, z0 - 0.02), Vector3.new(stairHalf * 2 - 0.2, 0.12, 0.1), C.StoneDeep, nil, Style.tiny())
		end
	end
	-- stone cheek walls: a newel block at the foot with a lantern pillar, a
	-- wall sloping up with the stairs, a light coping and a dark metal
	-- handrail on three posts with an orange neon underside
	local newelLen, newelH = 1.8, 2.4
	local slopeZ0 = front + newelLen
	local slopeLen = PORCH_FRONT - slopeZ0
	local slopeTop = PLINTH_TOP + 1
	local wedgeH = slopeTop - newelH
	local slopeAngle = math.atan2(wedgeH, slopeLen)
	local coping = math.sqrt(wedgeH * wedgeH + slopeLen * slopeLen)
	for _, s in { -1, 1 } do
		local cx = s * (stairHalf + 0.8)
		local newel = Style.block(
			m,
			at(cx, newelH / 2, front + newelLen / 2),
			Vector3.new(1.8, newelH, newelLen),
			Style.vary(C.Stone, rng, 0.03),
			nil,
			Style.solid()
		)
		newel.Name = "StairCheek"
		Style.block(m, at(cx, newelH + 0.15, front + newelLen / 2), Vector3.new(2.1, 0.3, newelLen), C.StoneLight, nil, Style.tiny())
		Style.block(
			m,
			at(cx, newelH / 2, (slopeZ0 + PORCH_FRONT) / 2),
			Vector3.new(1.6, newelH, slopeLen),
			Style.vary(C.Stone, rng, 0.03),
			nil,
			Style.solid()
		).Name =
			"StairCheek"
		-- WedgePart: the tall side at local +Z (toward the porch)
		Geo.wedge(
			m,
			at(cx, newelH + wedgeH / 2, (slopeZ0 + PORCH_FRONT) / 2),
			Vector3.new(1.6, wedgeH, slopeLen),
			Style.vary(C.Stone, rng, 0.03),
			SMOOTH,
			Style.solid()
		)
		local slopeMid = at(cx, newelH + wedgeH / 2 + 0.12, (slopeZ0 + PORCH_FRONT) / 2) * CFrame.Angles(-slopeAngle, 0, 0)
		Style.block(m, slopeMid, Vector3.new(1.9, 0.3, coping + 0.3), C.StoneLight, nil, Style.tiny())
		-- handrail (Kenney stairs-handrail): posts, a sloped dark rail, neon underside
		for _, t in { 0.15, 0.5, 0.85 } do
			local z = slopeZ0 + t * slopeLen
			local y = newelH + t * wedgeH + 0.27
			Style.block(m, at(cx, y + 0.5, z), Vector3.new(0.3, 1, 0.3), K.MetalDark, nil, Style.tiny())
		end
		local rail = slopeMid * CFrame.new(0, 1.15, 0)
		Style.block(m, rail, Vector3.new(0.4, 0.3, coping), K.MetalDark, nil, Style.tiny())
		local glow = Style.block(m, rail * CFrame.new(0, -0.19, 0), Vector3.new(0.2, 0.08, coping - 0.6), K.NeonOrange, NEON, Style.tiny())
		glow.Name = "StairGlow"
		-- the lantern pillar on the newel (lit: the forge's stair lights)
		-- (short range: it lights the stairs, not the banners)
		Common.pillarLantern(m, CFrame.lookAt(at(cx, newelH + 0.3, front + 1.15).Position, at(cx, newelH + 0.3, front - 5).Position), {
			Height = 3.8,
			Light = true,
			Range = 10,
			Brightness = 1,
		})
	end

	------------------------------------------------------------ wings
	for _, s in { -1, 1 } do
		local wingX = s * WING_X
		local wingDepth = WALL_BACK - (WING_FRONT + 2)
		Style.block(
			m,
			at(wingX, PLINTH_TOP + (WING_EAVE - PLINTH_TOP) / 2, (WING_FRONT + 2 + WALL_BACK) / 2),
			Vector3.new(11, WING_EAVE - PLINTH_TOP, wingDepth),
			Style.vary(C.Stone, rng, 0.03),
			nil,
			Style.solid()
		)
		Style.stoneWall(m, at(wingX, PLINTH_TOP, WING_FRONT + 1), Vector3.new(11, WING_EAVE - PLINTH_TOP, 2), rng, { Density = 0.3 })
		Style.stoneWall(
			m,
			at(s * 19.9, PLINTH_TOP, (WING_FRONT + 2 + WALL_BACK) / 2) * CFrame.Angles(0, -s * math.pi / 2, 0),
			Vector3.new(wingDepth, WING_EAVE - PLINTH_TOP, 1),
			rng,
			{ Density = 0.22, Cap = false }
		)
		-- front corner pillar
		Style.pillar(m, at(s * 19.2, PLINTH_TOP, WING_FRONT + 0.7), WING_EAVE - PLINTH_TOP + 0.4, rng, { Width = 2.4 })
		-- warm timber band under the eave (a wood panel on a dark beam)
		Style.block(
			m,
			at(wingX - s * 0.4, WING_EAVE - 1.05, WING_FRONT - 0.2),
			Vector3.new(9.6, 1.9, 0.3),
			Style.vary(C.Wood, rng, 0.04),
			nil,
			Style.tiny()
		)
		Style.block(m, at(wingX - s * 0.4, WING_EAVE - 2.1, WING_FRONT - 0.3), Vector3.new(10.2, 0.5, 0.4), C.WoodDark, nil, Style.tiny())
		-- lit windows: one on the front (outside the banner), one on the outer side
		Style.window(m, at(s * 16.6, PLINTH_TOP + 4.6, WING_FRONT - 0.45), 2.2, 3.2, { Color = K.WindowGlow })
		Style.window(m, at(s * 20.45, PLINTH_TOP + 4.8, 4) * CFrame.Angles(0, -s * math.pi / 2, 0), 2.6, 3.2, { Color = K.WindowGlow })
		-- dark slate wing roof (ridge along X), brick-red eaves, timber infill in
		-- the outer gable end; its inner end and ridge stay under the nave roof
		local depth = WING_ROOF_Z1 - WING_ROOF_Z0
		local roofW = WING_ROOF_X1 - WING_ROOF_X0
		local wingRoof = at(s * (WING_ROOF_X0 + WING_ROOF_X1) / 2, WING_EAVE, (WING_ROOF_Z0 + WING_ROOF_Z1) / 2)
		Style.gableRoof(m, wingRoof, roofW, depth, WING_ROOF_H, WING_ROOF)
		-- shingle joints on the front slope (seen from the plaza), courses only at the back
		roofCourses(wingRoof, roofW, depth, WING_ROOF_H, { -1 }, 4, 3)
		roofCourses(wingRoof, roofW, depth, WING_ROOF_H, { 1 }, 4)
		local infillHalf = depth / 2 - 1.8
		triangle(
			at(s * 20.65, WING_EAVE, (WING_ROOF_Z0 + WING_ROOF_Z1) / 2) * CFrame.Angles(0, -s * math.pi / 2, 0),
			infillHalf,
			infillHalf * WING_ROOF_H / (depth / 2),
			0.3,
			C.WoodDark
		)

		-- tall slim chimney stack at the back corner (world x +-18, z -74.5): it
		-- rises beside the wide gable like the concept's chimney towers
		local chimney = Style.model("Chimney", m)
		local cz = 16.5
		local cx = s * 18
		local shaftTop = GreatForge.ChimneyTop - 1.6
		Style.block(
			chimney,
			at(cx, (PLINTH_TOP + shaftTop) / 2, cz),
			Vector3.new(3.8, shaftTop - PLINTH_TOP, 3.8),
			Style.vary(C.Stone, rng, 0.03),
			nil,
			Style.solid()
		)
		-- dark bands and a stepped light crown (caps light, recesses dark)
		Style.block(chimney, at(cx, 29, cz), Vector3.new(4.2, 1, 4.2), Style.vary(C.StoneDark, rng, 0.04))
		Style.block(chimney, at(cx, shaftTop - 1.2, cz), Vector3.new(4.2, 1, 4.2), Style.vary(C.StoneDark, rng, 0.04))
		Style.block(chimney, at(cx, shaftTop + 0.6, cz), Vector3.new(4.8, 1.2, 4.8), Style.vary(C.StoneLight, rng, 0.04))
		local top = Style.block(chimney, at(cx, shaftTop + 1.4, cz), Vector3.new(3, 0.4, 3), C.Ember, NEON, Style.tiny())
		top.Name = "ChimneyGlow"
		Style.emitter(top, "Smoke", nil, 3)
		Style.emitter(top, "Embers", C.Ember, 2)
	end

	------------------------------------------------------------ crimson banners beside the entrance
	-- long banners (about 3.3 : 1 with the tail) right beside the door
	-- pillars, in front of the wing fronts and the wing roofs' eaves: each
	-- hangs from a dark metal arm bolted to the nave corner, just under the
	-- gable's eave board, down to the porch (the tail ends just above it)
	for _, s in { -1, 1 } do
		local bx = s * GreatForge.BannerX
		local bz = WING_FRONT - 1.3
		local banner = Style.model("Banner", m)
		local width = GreatForge.BannerWidth
		local tail = 0.7
		local clothTop, clothBottom = NAVE_EAVE - 1.2, PLINTH_TOP + 0.8
		local clothMid = (clothTop + clothBottom) / 2
		local clothH = clothTop - clothBottom
		-- the dark metal arm: from the nave corner out past the banner, a
		-- bolt plate on the nave wall and gold end caps
		local armX0, armX1 = NAVE, GreatForge.BannerX + width / 2 + 0.3
		Style.block(
			banner,
			at(s * (armX0 + armX1) / 2, clothTop + 0.22, bz - 0.1),
			Vector3.new(armX1 - armX0, 0.42, 0.42),
			K.MetalDark,
			nil,
			Style.tiny()
		)
		Style.block(banner, at(s * (NAVE + 0.1), clothTop + 0.1, bz - 0.1), Vector3.new(0.2, 1.1, 0.9), K.Metal, nil, Style.tiny())
		for _, t in { -1, 1 } do
			Style.block(
				banner,
				at(bx + t * (width / 2 + 0.2), clothTop + 0.22, bz - 0.1),
				Vector3.new(0.28, 0.56, 0.56),
				C.Gold,
				nil,
				Style.tiny()
			)
		end
		-- dark crimson backing (the border) and the crimson cloth
		Style.block(banner, at(bx, clothMid, bz + 0.05), Vector3.new(width, clothH, 0.12), K.BannerDark, nil, Style.tiny())
		local cloth = Style.block(
			banner,
			at(bx, clothMid + 0.1, bz - 0.05),
			Vector3.new(width - 0.5, clothH - 0.2, 0.14),
			K.Banner,
			nil,
			Style.tiny()
		)
		cloth.Name = "BannerCloth"
		-- the pointed tail (two wedges, upside down, their tall sides meeting at the banner's middle)
		for _, t in { -1, 1 } do
			Geo.wedge(
				banner,
				at(bx + t * width / 4, clothBottom - tail / 2, bz) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, -t * math.pi / 2, 0),
				Vector3.new(0.14, tail, width / 2),
				K.BannerDark,
				SMOOTH,
				Style.tiny()
			)
		end
		-- gold crossed hammers about 3 studs under the arm (matte gold, not
		-- neon: they stay gold, no bloom) and two thin gold bands near the foot
		for _, part in Style.icon(banner, at(bx, clothTop - 2.6, bz - 0.2), "CrossedHammers", 2.6, C.Gold, SMOOTH) do
			part.Name = "BannerIcon"
		end
		for _, y in { clothTop - 0.55, clothBottom + 0.7 } do
			Style.block(banner, at(bx, y, bz - 0.14), Vector3.new(width - 0.5, 0.22, 0.06), C.Gold, nil, Style.tiny())
		end
	end

	------------------------------------------------------------ nave
	-- the nave mass over the entrance, side jambs (firelit hall walls), back wall
	Style.block(
		m,
		at(0, (DOOR_TOP + NAVE_EAVE) / 2, (NAVE_FRONT + WALL_BACK) / 2),
		Vector3.new(NAVE * 2, NAVE_EAVE - DOOR_TOP, WALL_BACK - NAVE_FRONT),
		Style.vary(C.Stone, rng, 0.03),
		nil,
		Style.solid()
	)
	-- (the hall walls are a warm, firelit stone: the doorway reads as glowing)
	for _, s in { -1, 1 } do
		Style.block(
			m,
			at(s * (DOOR_HALF + 1), (PLINTH_TOP + DOOR_TOP) / 2, (NAVE_FRONT + WALL_BACK) / 2),
			Vector3.new(2, DOOR_TOP - PLINTH_TOP, WALL_BACK - NAVE_FRONT),
			FIRELIT,
			nil,
			Style.solid()
		)
	end
	Style.block(
		m,
		at(0, (PLINTH_TOP + DOOR_TOP) / 2, 12),
		Vector3.new(DOOR_HALF * 2, DOOR_TOP - PLINTH_TOP, 8),
		FIRELIT_DARK,
		nil,
		Style.solid()
	)
	Style.block(m, at(0, PLINTH_TOP + 0.05, -1), Vector3.new(DOOR_HALF * 2, 0.1, 16), C.FlagDark, nil, Style.tiny())

	-- entrance: stone pillars, a dark timber lintel and under it a wide stone
	-- arch (two haunches: the opening reads as an arch, it glows from within)
	for _, s in { -1, 1 } do
		Style.pillar(m, at(s * 8.2, PLINTH_TOP, NAVE_FRONT - 0.4), DOOR_TOP - PLINTH_TOP + 0.2, rng, { Width = 2.4 })
		-- haunch: a wedge with its right angle in the door's top corner (local
		-- Y down, local Z out to the jamb: the slope faces down and inward)
		local hw, hh = 3.6, 2.3
		Geo.wedge(
			m,
			CFrame.fromMatrix(
				at(s * (DOOR_HALF - hw / 2), DOOR_TOP - 0.1 - hh / 2, NAVE_FRONT + 0.1).Position,
				frame:VectorToWorldSpace(Vector3.new(0, 0, s)),
				frame:VectorToWorldSpace(Vector3.new(0, -1, 0)),
				frame:VectorToWorldSpace(Vector3.new(s, 0, 0))
			),
			Vector3.new(1.2, hh, hw),
			Style.vary(C.StoneDark, rng, 0.03),
			SMOOTH,
			Style.decor()
		).Name =
			"DoorArch"
	end
	Style.block(m, at(0, DOOR_TOP + 0.55, NAVE_FRONT - 0.7), Vector3.new(19.4, 1.3, 1.4), C.WoodDark, nil, Style.decor())

	-- the timber beam band over the lintel (warm wood between dark posts):
	-- it carries THE GREAT FORGE board at the foot of the gable
	local bandY = (LINTEL_TOP + NAVE_EAVE) / 2
	local bandH = NAVE_EAVE - LINTEL_TOP
	Style.block(
		m,
		at(0, bandY, NAVE_FRONT - 0.12),
		Vector3.new(NAVE * 2 - 0.4, bandH, 0.24),
		Style.vary(C.WoodLight, rng, 0.04),
		nil,
		Style.tiny()
	)
	for _, x in { -8.6, -4.4, 4.4, 8.6 } do
		Style.block(m, at(x, bandY, NAVE_FRONT - 0.3), Vector3.new(0.6, bandH, 0.3), C.WoodDark, nil, Style.tiny())
	end

	-- THE GREAT FORGE board at the foot of the gable, no wider than the nave
	-- roof's front: its ends hang on dark iron straps from the lintel. From
	-- the spawn camera (0, 9, 46) the sight line over the fire crystal's tip
	-- (y < 9.5 at the plaza center) reaches the forge front at y ~10, so the
	-- board, the crest and the upper half of the glowing doorway all read
	-- above the crystal
	local signZ = NAVE_FRONT - 1.6
	local signW = GreatForge.SignWidth
	local sign =
		Style.sign(m, at(0, GreatForge.SignY, signZ), "THE GREAT FORGE", signW, GreatForge.SignHeight, { Kind = "Wood", Depth = 0.7 })
	sign.Name = "ForgeSign"
	local signBottom = GreatForge.SignY - GreatForge.SignHeight / 2
	for _, s in { -1, 1 } do
		Style.block(
			m,
			at(s * (signW / 2 - 0.7), (LINTEL_TOP + signBottom) / 2 + 0.2, signZ + 0.05),
			Vector3.new(0.35, signBottom - LINTEL_TOP + 0.4, 0.5),
			IRON_DARK,
			nil,
			Style.tiny()
		).Name =
			"SignStrap"
	end

	-- big, steep dark slate cross gable (ridge along Z) over the nave, framed
	-- by brick-red bargeboards; no ridge beam (nothing pokes up over the
	-- apex); thin shingle courses only (no rafter seams: no moire from afar)
	local naveRoof = at(0, NAVE_EAVE, (NAVE_ROOF_Z0 + NAVE_ROOF_Z1) / 2) * CFrame.Angles(0, math.pi / 2, 0)
	local naveLen = NAVE_ROOF_Z1 - NAVE_ROOF_Z0
	Style.gableRoof(m, naveRoof, naveLen, NAVE_HALF * 2, NAVE_ROOF_H, NAVE_ROOF)
	roofCourses(naveRoof, naveLen, NAVE_HALF * 2, NAVE_ROOF_H, { -1, 1 }, 6)
	-- dark timber gable infill just in front of the roof's end face, inset so
	-- a band of slate and the bargeboards frame it
	local gz = NAVE_ROOF_Z0 - 0.2
	local infillHalf = NAVE_HALF - 0.5
	triangle(at(0, NAVE_EAVE, gz), infillHalf, infillHalf * NAVE_PITCH, 0.3, C.WoodDark)
	-- chunky brick-red bargeboards on the gable front (concept v2's thick red
	-- frame), stopping short of the apex so nothing pokes over it
	local rake = math.atan2(NAVE_ROOF_H, NAVE_HALF)
	local rakeLen = math.sqrt(NAVE_HALF * NAVE_HALF + NAVE_ROOF_H * NAVE_ROOF_H) - 1.2
	for _, s in { -1, 1 } do
		local mid =
			Vector3.new(s * (NAVE_HALF - math.cos(rake) * rakeLen / 2), NAVE_EAVE + math.sin(rake) * rakeLen / 2, NAVE_ROOF_Z0 - 0.4)
		Style.block(
			m,
			at(mid.X, mid.Y, mid.Z) * CFrame.Angles(0, 0, -s * rake) * CFrame.new(0, 0.25, 0),
			Vector3.new(rakeLen, 0.9, 0.7),
			K.BrickRed,
			nil,
			Style.tiny()
		).Name =
			"Bargeboard"
	end

	-- the crest: a dark metal plate shaped like a small gable (flat foot,
	-- vertical sides, its top parallel to the bargeboards) on a slightly
	-- larger metal border, carrying the big glowing deep-gold crossed hammers
	local crestFoot = GreatForge.SignY + GreatForge.SignHeight / 2 + 0.5
	local crestHalf = 4.3
	local crestApex = APEX - 0.45
	local shoulder = crestApex - crestHalf * NAVE_PITCH
	for i, spec in { { Grow = 0.25, Color = K.Metal, Z = gz - 0.3 }, { Grow = 0, Color = K.MetalDark, Z = gz - 0.45 } } do
		local half = crestHalf + spec.Grow
		local foot = crestFoot - spec.Grow
		local top = shoulder + spec.Grow * (1 - NAVE_PITCH)
		local plate =
			Style.block(m, at(0, (foot + top) / 2, spec.Z), Vector3.new(half * 2, top - foot, 0.15), spec.Color, nil, Style.tiny())
		plate.Name = if i == 1 then "EmblemBorder" else "Emblem"
		triangle(at(0, top, spec.Z), half, half * NAVE_PITCH, 0.15, spec.Color)
	end
	-- a deep-gold neon halo (the same hammers, a size larger) behind solid gold
	-- hammers: the emblem glows at its edges and stays gold, no white blob
	for _, part in
		Style.icon(m, at(0, GreatForge.EmblemY - 0.05, gz - 0.62), "CrossedHammers", GreatForge.EmblemSize * 1.12, K.EmblemGold, NEON)
	do
		part.Name = "EmblemGlow"
	end
	for _, part in Style.icon(m, at(0, GreatForge.EmblemY, gz - 0.95), "CrossedHammers", GreatForge.EmblemSize, C.Gold, SMOOTH) do
		part.Name = "EmblemHammers"
	end

	------------------------------------------------------------ interior (seen through the entrance)
	-- a busy workshop: a warm-orange furnace wall (the whole hall glows) with
	-- three furnace mouths recessed in dark iron boxes behind grate bars (the
	-- middle one is ForgeGlow, it pulses on the client, flames lick out of
	-- it; the side ones glow molten round a thin neon coal bed), a hood and
	-- flues, glowing seams down the firelit side walls, an anvil and a tool
	-- rack against the glow, hanging lamps
	local fz = 7.7 -- front face of the furnace wall
	Style.block(m, at(0, PLINTH_TOP + 3.4, fz + 0.6), Vector3.new(DOOR_HALF * 2, 6.8, 1.2), HEARTH, nil, Style.solid()).Name = "FurnaceWall"
	local mouths = {
		{ X = 0, W = 4.4, H = 3.4, Y = 2.5, Bars = { -1.1, 0, 1.1 } },
		{ X = -4.6, W = 2.6, H = 2.8, Y = 2.2, Bars = { -0.45, 0.45 } },
		{ X = 4.6, W = 2.6, H = 2.8, Y = 2.2, Bars = { -0.45, 0.45 } },
	}
	local boxDepth, wall = 1, 0.35
	for i, mouth in mouths do
		local x, y = mouth.X, PLINTH_TOP + mouth.Y
		local bz = fz - boxDepth / 2
		-- the iron box round the mouth: top, sill and two cheeks, 1 stud deep
		for _, t in { -1, 1 } do
			Style.block(
				m,
				at(x, y + t * (mouth.H + wall) / 2, bz),
				Vector3.new(mouth.W + wall * 2, wall, boxDepth),
				IRON_DARK,
				nil,
				Style.tiny()
			)
			Style.block(m, at(x + t * (mouth.W + wall) / 2, y, bz), Vector3.new(wall, mouth.H, boxDepth), IRON_DARK, nil, Style.tiny())
		end
		if i == 1 then
			local glow = Style.block(m, at(x, y, fz - 0.04), Vector3.new(mouth.W, mouth.H, 0.06), C.Ember, NEON, Style.tiny())
			glow.Name = "ForgeGlow"
			Style.light(glow, C.Fire, 18, 1.8)
			Style.emitter(glow, "Fire", C.Fire, 6)
			Style.emitter(glow, "Embers", C.Ember, 5)
		else
			-- a molten (not neon) mouth round a thin glowing coal bed
			local mouthPart = Style.block(m, at(x, y, fz - 0.04), Vector3.new(mouth.W, mouth.H, 0.06), C.Molten, SMOOTH, Style.tiny())
			mouthPart.Name = "FurnaceMouth"
			local core =
				Style.block(m, at(x, y - mouth.H / 2 + 0.35, fz - 0.2), Vector3.new(mouth.W - 0.3, 0.32, 0.25), C.Ember, NEON, Style.tiny())
			core.Name = "FurnaceGlow"
		end
		-- dark vertical grate bars across the front of the box
		for _, bx in mouth.Bars do
			Style.block(m, at(x + bx, y, fz - boxDepth + 0.08), Vector3.new(0.2, mouth.H, 0.16), IRON_DARK, nil, Style.tiny()).Name =
				"FurnaceGrate"
		end
	end
	-- iron hood over the middle mouth and two flues
	Style.block(m, at(0, PLINTH_TOP + 5.3, fz - 0.5), Vector3.new(5.8, 1.4, 1.2), C.Iron, METAL, Style.tiny())
	for _, x in { -4.6, 4.6 } do
		Style.block(m, at(x, PLINTH_TOP + 5.8, fz - 0.3), Vector3.new(1, 3.4, 1), C.Iron, METAL, Style.tiny())
	end
	-- glowing seams down the side walls of the hall
	for _, s in { -1, 1 } do
		local seam =
			Style.block(m, at(s * (DOOR_HALF - 0.05), PLINTH_TOP + 3.4, 0.5), Vector3.new(0.15, 0.35, 13), C.Ember, NEON, Style.tiny())
		seam.Name = "HallGlow"
	end
	-- anvil on a stump in front of the middle mouth (a dark silhouette against the glow)
	Style.block(m, at(0, PLINTH_TOP + 0.6, 3.6), Vector3.new(1.4, 1.2, 1.4), C.WoodDark, nil, Style.solid())
	Style.block(m, at(0, PLINTH_TOP + 1.55, 3.6), Vector3.new(2.6, 0.7, 1.1), C.Iron, METAL, Style.tiny())
	Style.block(m, at(-1.6, PLINTH_TOP + 1.65, 3.6), Vector3.new(0.8, 0.4, 0.6), C.Iron, METAL, Style.tiny())
	-- tool rack on the right wall (viewer's right = local -X): a board with hammers and a pick
	Style.block(m, at(-(DOOR_HALF - 0.12), PLINTH_TOP + 4.4, -2.5), Vector3.new(0.2, 2.2, 4.4), C.Wood, nil, Style.tiny())
	for k, z in { -4.1, -2.5, -0.9 } do
		local tool = Style.icon(
			m,
			at(-(DOOR_HALF - 0.35), PLINTH_TOP + 4.2, z) * CFrame.Angles(0, -math.pi / 2, 0),
			if k == 2 then "Pickaxe" else "Hammer",
			1.6,
			C.IronLight,
			METAL
		)
		for _, part in tool do
			part.Name = "RackTool"
		end
	end
	-- two hanging lamps from the hall beams (amber core under a dark cap)
	for _, s in { -1, 1 } do
		Style.block(m, at(s * 3.4, DOOR_TOP - 0.95, -3), Vector3.new(0.15, 1.9, 0.15), C.Iron, nil, Style.tiny())
		Style.block(m, at(s * 3.4, DOOR_TOP - 2.05, -3), Vector3.new(0.9, 0.3, 0.9), K.MetalDark, nil, Style.tiny())
		Style.block(m, at(s * 3.4, DOOR_TOP - 2.55, -3), Vector3.new(0.55, 0.7, 0.55), K.Amber, NEON, Style.tiny()).Name = "HallLamp"
	end
	for _, z in { -6, 0, 5 } do
		Style.block(m, at(0, DOOR_TOP - 0.4, z), Vector3.new(DOOR_HALF * 2, 0.8, 0.8), C.WoodDark, nil, Style.tiny())
	end
	-- a molten sill glowing across the threshold (short-range light: it
	-- lights the doorway, not the banners)
	local threshold = Style.block(
		m,
		at(0, PLINTH_TOP + 0.06, NAVE_FRONT + 0.7),
		Vector3.new(DOOR_HALF * 2 - 0.8, 0.12, 0.5),
		C.Molten,
		NEON,
		Style.tiny()
	)
	threshold.Name = "MoltenChannel"
	Style.light(threshold, C.Fire, 8.5, 1.6)

	------------------------------------------------------------ porch and stair props
	-- beside the stairs (north-east / north-west of the plaza): a gold mine
	-- cart and dark metal crates with orange glowing straps (no braziers: the
	-- lantern pillars and the doorway are the only fires out front)
	local props = Style.model("StairProps", m)
	for _, s in { -1, 1 } do
		local cart = at(s * 14.5, 0, front + 4.5)
		local cartModel = Style.mineCart(props, cart * CFrame.Angles(0, math.pi / 2 + s * 0.25, 0), rng, { Load = "Gold" })
		-- matte gold load (no glowing blobs beside the stairs)
		for _, d in cartModel:GetDescendants() do
			if d:IsA("BasePart") and d.Material == NEON then
				d.Material = SMOOTH
			end
		end
		for i, spec in { { X = 19, Z = front + 2.6, S = 2.2 }, { X = 18.6, Z = front + 5.6, S = 1.7 } } do
			local base = at(s * spec.X, 0, spec.Z) * CFrame.Angles(0, s * (0.2 + i * 0.3), 0)
			local size = spec.S
			Style.block(
				props,
				base * CFrame.new(0, size / 2, 0),
				Vector3.new(size, size, size),
				Style.vary(K.Metal, rng, 0.05),
				nil,
				Style.decor()
			)
			Style.block(
				props,
				base * CFrame.new(0, size - 0.08, 0),
				Vector3.new(size + 0.1, 0.2, size + 0.1),
				K.MetalDark,
				nil,
				Style.tiny()
			)
			Style.block(
				props,
				base * CFrame.new(0, size * 0.45, 0),
				Vector3.new(size + 0.06, 0.16, size + 0.06),
				K.NeonOrange,
				NEON,
				Style.tiny()
			)
		end
	end
end

return GreatForge
