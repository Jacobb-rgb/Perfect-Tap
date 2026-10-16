--[[
	THE GREAT FORGE (LOBBY_PLAN 6.3.4, restyled after concept v2), the
	landmark north of the plaza. Footprint x -21..21, z -78..-38 (piece
	GreatForge), front toward the plaza, everything but the chimneys below
	y 32.

	Read like concept v2: a tall central nave whose steep dark slate cross
	gable faces the plaza (warm timber infill, a big glowing crossed-hammers
	emblem at the apex), flanked by two lower stone wings with dark slate
	roofs, warm timber bands and lantern pillars on the roofs; THE GREAT
	FORGE board mounted high on the gable (so it reads above the fire
	crystal from the spawn), a timber-framed upper floor with two lit
	windows over the open entrance between stone pillars, two tall red
	banners with gold crossed hammers hanging left and right of the
	entrance, wide stone stairs (with stone cheeks, dark metal handrails
	and orange neon strips) up to the raised porch, the glowing workshop
	inside (ForgeGlow hearth, furnaces, anvils, a molten channel); two tall
	chimneys at the back corners (x +-17, z -72).

	Local frame (LobbyLayout.frame): origin at the piece center on the
	ground, front = -Z (toward the plaza), local +X = the viewer's left
	when seen from the plaza. Two PointLights: the hearth and the threshold.
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
GreatForge.PlinthTop = 2.5 -- the raised porch and hall floor
GreatForge.WingEave = 13.5
GreatForge.WingRoofHeight = 8.5
GreatForge.NaveEave = 17.5
GreatForge.NaveRoofHeight = 13.5
GreatForge.ChimneyTop = 40
GreatForge.SignY = 22 -- THE GREAT FORGE board center (on the nave gable)
GreatForge.EmblemY = 27.5 -- the glowing crossed-hammers emblem at the gable apex
GreatForge.EmblemDiameter = 6.6
GreatForge.StairHalfWidth = 11 -- the stairs run x -11..11
GreatForge.StairSteps = 5 -- risers from the plaza apron (y 0.4) to the porch
GreatForge.BannerX = 12.3 -- banner centers (local x = +-12.3), between the entrance pillars and the wing windows
GreatForge.BannerWidth = 3.6

local PLINTH_TOP = GreatForge.PlinthTop
local DY = PLINTH_TOP - 1.5 -- interior props sit this much higher than on the old 1.5 plinth
local NAVE = 9 -- nave half width
local NAVE_FRONT = -15
local WING_FRONT = -13
local WALL_BACK = 16
local PORCH_FRONT = -17 -- the plinth front (top of the stairs)
local WING_EAVE = GreatForge.WingEave
local NAVE_EAVE = GreatForge.NaveEave
local WING_ROOF_H = GreatForge.WingRoofHeight
local NAVE_ROOF_H = GreatForge.NaveRoofHeight
local WING_ROOF_DEPTH = 31
local WING_ROOF_Z = 2
local DOOR_HALF = 7
local DOOR_TOP = 11.5

-- dark slate roof tiles with warm timber eaves, gable boards and ridge
local ROOF = { Rows = 3, Color = K.RoofSlate, Dark = K.RoofSlateDark, Trim = C.WoodDark }

function GreatForge.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("GreatForge")
	local frame = LobbyLayout.frame(piece)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local m = Style.model("GreatForge", parent)
	local front = -piece.Size.Z / 2

	-- the wing roofs' front slope height at local z (for things standing on it)
	local function wingRoofY(z: number): number
		local eaveZ = WING_ROOF_Z - WING_ROOF_DEPTH / 2
		return WING_EAVE + (z - eaveZ) * WING_ROOF_H / (WING_ROOF_DEPTH / 2)
	end

	-- vertical tile seams down the given slopes of a Style.gableRoof (same
	-- frame and measures), so the slate roofs read as tiles like the concept
	local function roofSeams(cf: CFrame, width: number, depth: number, height: number, sides: { number }, count: number)
		local half = depth / 2
		local slope = math.atan2(height, half)
		local slopeLen = math.sqrt(height * height + half * half)
		for _, side in sides do
			for i = 1, count do
				local x = -width / 2 + width * i / (count + 1)
				local mid = Vector3.new(x, height / 2 + 0.14, side * half / 2)
				Style.block(
					m,
					cf * CFrame.new(mid) * CFrame.Angles(side * slope, 0, 0),
					Vector3.new(0.3, 0.3, slopeLen - 0.4),
					K.RoofSlateDark,
					nil,
					Style.tiny()
				)
			end
		end
	end

	-- dark timber infill of a gable end: two wedges (local -Z faces out)
	local function gableInfill(cf: CFrame, halfWidth: number, height: number)
		Geo.wedge(
			m,
			cf * CFrame.new(-halfWidth / 2, height / 2, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Vector3.new(0.3, height, halfWidth),
			C.WoodDark,
			SMOOTH,
			Style.tiny()
		)
		Geo.wedge(
			m,
			cf * CFrame.new(halfWidth / 2, height / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			Vector3.new(0.3, height, halfWidth),
			C.WoodDark,
			SMOOTH,
			Style.tiny()
		)
	end

	-- a disc facing the plaza (Roblox cylinders run along local X)
	local function disc(cf: CFrame, diameter: number, thickness: number, color: Color3, material: Enum.Material?): Part
		return Geo.make(
			"Part",
			Style.tiny({
				Shape = Enum.PartType.Cylinder,
				CFrame = cf * CFrame.Angles(0, math.pi / 2, 0),
				Size = Vector3.new(thickness, diameter, diameter),
				Color = color,
				Material = material or SMOOTH,
			}),
			m
		)
	end

	------------------------------------------------------------ plinth and the wide stairs
	Style.block(
		m,
		at(0, PLINTH_TOP / 2, (PORCH_FRONT + 20) / 2),
		Vector3.new(42, PLINTH_TOP, 20 - PORCH_FRONT),
		Style.vary(C.StoneDark, rng, 0.03),
		nil,
		Style.solid()
	)
	Style.block(m, at(0, PLINTH_TOP - 0.15, PORCH_FRONT - 0.1), Vector3.new(42, 0.3, 0.4), C.StoneLight, nil, Style.tiny())
	-- risers of ~0.42 from the plaza apron (y 0.4) to the porch, treads 0.75 deep
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
		-- light nosing along each tread edge
		Style.block(m, at(0, top - 0.06, z0 + 0.14), Vector3.new(stairHalf * 2 - 0.3, 0.14, 0.3), C.StoneLight, nil, Style.tiny())
	end
	-- stone cheeks with a light cap, an orange neon strip along the steps and a lantern pillar
	for _, s in { -1, 1 } do
		local cx = s * (stairHalf + 0.7)
		local cheekTop = PLINTH_TOP + 0.6
		Style.block(
			m,
			at(cx, cheekTop / 2, (front + PORCH_FRONT) / 2),
			Vector3.new(1.4, cheekTop, PORCH_FRONT - front),
			Style.vary(C.Stone, rng, 0.03),
			nil,
			Style.solid()
		)
		Style.block(
			m,
			at(cx, cheekTop + 0.15, (front + PORCH_FRONT) / 2),
			Vector3.new(1.7, 0.3, PORCH_FRONT - front),
			C.StoneLight,
			nil,
			Style.tiny()
		)
		local glow = Style.block(
			m,
			at(cx - s * 0.72, cheekTop - 0.5, (front + PORCH_FRONT) / 2),
			Vector3.new(0.1, 0.3, PORCH_FRONT - front - 0.4),
			K.NeonOrange,
			NEON,
			Style.tiny()
		)
		glow.Name = "StairGlow"
	end

	------------------------------------------------------------ wings
	for _, s in { -1, 1 } do
		local wingX = s * (NAVE + 5.5)
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
			{ Density = 0.28, Cap = false }
		)
		-- corner pillars (front: stacked pillar, back: plain block)
		Style.pillar(m, at(s * 19.2, PLINTH_TOP, WING_FRONT + 0.7), WING_EAVE - PLINTH_TOP + 0.4, rng, { Width = 2.4 })
		Style.block(m, at(s * 19.5, PLINTH_TOP + 6, WALL_BACK - 0.7), Vector3.new(2.6, 12, 2.6), Style.vary(C.StoneDark, rng, 0.03))
		-- warm timber band under the eave (a wood panel on a dark beam)
		Style.block(
			m,
			at(wingX - s * 0.4, 11.95, WING_FRONT - 0.2),
			Vector3.new(9.6, 2.9, 0.3),
			Style.vary(C.Wood, rng, 0.04),
			nil,
			Style.tiny()
		)
		Style.block(m, at(wingX - s * 0.4, 10.4, WING_FRONT - 0.3), Vector3.new(10.2, 0.5, 0.4), C.WoodDark, nil, Style.tiny())
		Style.block(m, at(s * 14.6, 11.95, WING_FRONT - 0.32), Vector3.new(0.5, 2.9, 0.3), C.WoodDark, nil, Style.tiny())
		-- lit windows: one on the front (outside the banner), two on the outer side
		Style.window(m, at(s * 16.4, 6.8, WING_FRONT - 0.45), 2.2, 3.4)
		for _, z in { -4, 8 } do
			Style.window(m, at(s * 20.45, 7.4, z) * CFrame.Angles(0, -s * math.pi / 2, 0), 2.6, 3.4)
		end
		-- dark slate wing roof (ridge along X) and a lantern pillar by the gable
		local wingRoof = at(s * 15, WING_EAVE, WING_ROOF_Z)
		Style.gableRoof(m, wingRoof, 11.2, WING_ROOF_DEPTH, WING_ROOF_H, ROOF)
		roofSeams(wingRoof, 11.2, WING_ROOF_DEPTH, WING_ROOF_H, { -1 }, 4)
		-- timber infill in the outer gable end (faces sideways, inset from the roof edge)
		local infillHalf = WING_ROOF_DEPTH / 2 - 2.2
		gableInfill(
			at(s * 20.65, WING_EAVE, WING_ROOF_Z) * CFrame.Angles(0, -s * math.pi / 2, 0),
			infillHalf,
			infillHalf * WING_ROOF_H / (WING_ROOF_DEPTH / 2)
		)
		Common.pillarLantern(m, at(s * 11.6, wingRoofY(-7) - 0.4, -7), { Height = 3 })

		-- chimney at the back corner (world x +-17, z -72)
		local chimney = Style.model("Chimney", m)
		local cz = 14
		local cx = s * 17
		local shaftTop = GreatForge.ChimneyTop - 1.6
		Style.block(
			chimney,
			at(cx, (PLINTH_TOP + shaftTop) / 2, cz),
			Vector3.new(5.6, shaftTop - PLINTH_TOP, 5.6),
			Style.vary(C.Stone, rng, 0.03),
			nil,
			Style.solid()
		)
		-- dark bands and a stepped light crown (caps light, recesses dark)
		Style.block(chimney, at(cx, 27, cz), Vector3.new(6.1, 1, 6.1), Style.vary(C.StoneDark, rng, 0.04))
		Style.block(chimney, at(cx, shaftTop - 1.2, cz), Vector3.new(6.1, 1, 6.1), Style.vary(C.StoneDark, rng, 0.04))
		Style.block(chimney, at(cx, shaftTop + 0.6, cz), Vector3.new(6.6, 1.2, 6.6), Style.vary(C.StoneLight, rng, 0.04))
		for _, y in { 22.5, 32.5 } do
			Style.block(
				chimney,
				at(cx + s * rng:range(-1, 1), y, cz - 2.95),
				Vector3.new(1.8, 1, 0.4),
				Style.vary(C.StoneLight, rng, 0.05),
				nil,
				Style.tiny()
			)
		end
		local top = Style.block(chimney, at(cx, shaftTop + 1.4, cz), Vector3.new(4.4, 0.4, 4.4), C.Ember, NEON, Style.tiny())
		top.Name = "ChimneyGlow"
		Style.emitter(top, "Smoke", nil, 3)
		Style.emitter(top, "Embers", C.Ember, 2)
	end

	------------------------------------------------------------ red banners beside the entrance
	for _, s in { -1, 1 } do
		local bx = s * GreatForge.BannerX
		local bz = WING_FRONT - 0.75
		local banner = Style.model("Banner", m)
		local width = GreatForge.BannerWidth
		local clothTop, clothBottom = 12.8, 4.4
		local clothMid = (clothTop + clothBottom) / 2
		local clothH = clothTop - clothBottom
		-- gold rod
		Style.block(banner, at(bx, clothTop + 0.15, bz - 0.1), Vector3.new(width + 0.5, 0.3, 0.3), C.Gold, nil, Style.tiny())
		-- dark red backing (the border) and the red cloth
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
		-- gold band under the rod, gold side trims and the pointed tail (two
		-- wedges, upside down, their tall sides meeting at the banner's middle)
		Style.block(banner, at(bx, clothTop - 0.55, bz - 0.14), Vector3.new(width - 0.5, 0.25, 0.06), C.Gold, nil, Style.tiny())
		for _, t in { -1, 1 } do
			Style.block(
				banner,
				at(bx + t * (width / 2 - 0.4), clothMid, bz - 0.06),
				Vector3.new(0.16, clothH - 0.3, 0.1),
				C.Brass,
				nil,
				Style.tiny()
			)
		end
		for _, t in { -1, 1 } do
			Geo.wedge(
				banner,
				at(bx + t * width / 4, clothBottom - 0.75, bz) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, -t * math.pi / 2, 0),
				Vector3.new(0.14, 1.5, width / 2),
				K.BannerDark,
				SMOOTH,
				Style.tiny()
			)
		end
		-- gold crossed hammers on the cloth
		Style.icon(banner, at(bx, clothMid + 1.4, bz - 0.2), "CrossedHammers", 2.8, C.Gold, NEON)
	end

	------------------------------------------------------------ nave
	-- upper floor mass over the entrance, side jambs (dark interior walls), back wall
	Style.block(
		m,
		at(0, (DOOR_TOP + NAVE_EAVE) / 2, (NAVE_FRONT + WALL_BACK) / 2),
		Vector3.new(NAVE * 2, NAVE_EAVE - DOOR_TOP, WALL_BACK - NAVE_FRONT),
		Style.vary(C.Stone, rng, 0.03),
		nil,
		Style.solid()
	)
	for _, s in { -1, 1 } do
		Style.block(
			m,
			at(s * (DOOR_HALF + 1), (PLINTH_TOP + DOOR_TOP) / 2, (NAVE_FRONT + WALL_BACK) / 2),
			Vector3.new(2, DOOR_TOP - PLINTH_TOP, WALL_BACK - NAVE_FRONT),
			C.StoneDark,
			nil,
			Style.solid()
		)
	end
	Style.block(
		m,
		at(0, (PLINTH_TOP + DOOR_TOP) / 2, 12),
		Vector3.new(DOOR_HALF * 2, DOOR_TOP - PLINTH_TOP, 8),
		C.StoneDeep,
		nil,
		Style.solid()
	)
	Style.block(m, at(0, PLINTH_TOP + 0.05, -2.5), Vector3.new(DOOR_HALF * 2, 0.1, 21), C.FlagDark, nil, Style.tiny())

	-- timber-framed upper floor over the entrance (warm wood, dark posts)
	local timberY = (DOOR_TOP + 1.2 + NAVE_EAVE) / 2
	local timberH = NAVE_EAVE - DOOR_TOP - 1.2
	Style.block(
		m,
		at(0, timberY, NAVE_FRONT - 0.12),
		Vector3.new(NAVE * 2 - 0.4, timberH, 0.24),
		Style.vary(C.WoodLight, rng, 0.04),
		nil,
		Style.tiny()
	)
	for _, x in { -8.6, -2, 2, 8.6 } do
		Style.block(m, at(x, timberY, NAVE_FRONT - 0.3), Vector3.new(0.6, timberH, 0.3), C.WoodDark, nil, Style.tiny())
	end
	Style.block(m, at(0, NAVE_EAVE - 0.3, NAVE_FRONT - 0.3), Vector3.new(NAVE * 2, 0.5, 0.35), C.WoodDark, nil, Style.tiny())

	-- entrance: stone pillars, a dark timber lintel with knee braces
	for _, s in { -1, 1 } do
		Style.pillar(m, at(s * 8.2, PLINTH_TOP, NAVE_FRONT - 0.6), DOOR_TOP - PLINTH_TOP + 0.2, rng, { Width = 2.4 })
		Style.block(
			m,
			at(s * 6.1, DOOR_TOP - 1.3, NAVE_FRONT - 0.5) * CFrame.Angles(0, 0, s * math.pi / 4),
			Vector3.new(0.7, 3.2, 0.7),
			C.WoodDark,
			nil,
			Style.tiny()
		)
	end
	Style.block(m, at(0, DOOR_TOP + 0.55, NAVE_FRONT - 0.7), Vector3.new(19.4, 1.3, 1.4), C.WoodDark, nil, Style.decor())

	-- THE GREAT FORGE board, mounted high on the gable: from the spawn camera
	-- (0, 9, 46) the sight line over the fire crystal's tip (y <= 14 at the
	-- plaza center) reaches the nave front at y ~19.5, so the board starts above it
	local sign = Style.sign(m, at(0, GreatForge.SignY, NAVE_FRONT - 1.05), "THE GREAT FORGE", 24, 4.4, { Kind = "Wood", Depth = 0.7 })
	sign.Name = "ForgeSign"
	-- two lit windows over the entrance
	for _, s in { -1, 1 } do
		Style.window(m, at(s * 4.6, 14.9, NAVE_FRONT - 0.5), 2.6, 2.6)
	end

	-- steep dark slate cross gable (ridge along Z) over the nave
	local navePitch = NAVE_ROOF_H / 10.2
	local naveRoof = at(0, NAVE_EAVE, 1) * CFrame.Angles(0, math.pi / 2, 0)
	Style.gableRoof(m, naveRoof, 33, 20.4, NAVE_ROOF_H, ROOF)
	roofSeams(naveRoof, 33, 20.4, NAVE_ROOF_H, { -1, 1 }, 8)
	-- dark timber gable infill, inset so a band of slate roof frames it
	local infillHalf = 8.7
	local infillH = infillHalf * navePitch
	local gz = NAVE_FRONT - 0.65
	gableInfill(at(0, NAVE_EAVE, gz), infillHalf, infillH)
	Style.block(m, at(0, NAVE_EAVE + 0.3, gz - 0.2), Vector3.new(infillHalf * 2, 0.6, 0.4), C.Wood, nil, Style.tiny())

	-- the big glowing crossed-hammers emblem at the apex: a dark metal rim,
	-- a dark face ringed by thin orange neon segments, and big gold neon
	-- hammers (only thin parts glow, so the bloom keeps the hammers readable)
	local ey = GreatForge.EmblemY
	local d = GreatForge.EmblemDiameter
	disc(at(0, ey, gz - 0.35), d, 0.3, K.Metal).Name = "Emblem"
	disc(at(0, ey, gz - 0.6), d - 0.6, 0.3, K.MetalDark).Name = "EmblemFace"
	local ringR = d / 2 - 0.62
	local ringSegments = 12
	for i = 0, ringSegments - 1 do
		local a = (i + 0.5) / ringSegments * 2 * math.pi
		local chord = 2 * ringR * math.sin(math.pi / ringSegments)
		local seg = Style.block(
			m,
			at(0, ey, gz - 0.8) * CFrame.Angles(0, 0, a) * CFrame.new(ringR, 0, 0),
			Vector3.new(0.2, chord * 0.8, 0.12),
			C.Fire,
			NEON,
			Style.tiny()
		)
		seg.Name = "EmblemGlow"
	end
	for _, part in Style.icon(m, at(0, ey, gz - 1.0), "CrossedHammers", 4.4, C.Gold, NEON) do
		part.Name = "EmblemHammers"
	end

	------------------------------------------------------------ interior (seen through the entrance)
	-- the big furnace on the back wall (ForgeGlow pulses on the client)
	local glow = Style.block(m, at(0, 6 + DY, 7.8), Vector3.new(10, 5, 0.3), C.Molten, NEON, Style.tiny())
	glow.Name = "ForgeGlow"
	Style.block(m, at(0, 2.5 + DY, 6.4), Vector3.new(12, 2, 3), C.StoneDark, nil, Style.solid())
	local coals = Style.block(m, at(0, 3.65 + DY, 6.4), Vector3.new(10.4, 0.3, 2.2), C.Ember, NEON, Style.tiny())
	coals.Name = "HearthCoals"
	Style.emitter(coals, "Embers", C.Ember, 5)
	Style.block(m, at(0, 10 + DY, 6.3), Vector3.new(13, 3, 3.4), C.StoneDark)
	-- glowing seams down the side walls of the hall
	for _, s in { -1, 1 } do
		Style.block(m, at(s * (DOOR_HALF - 0.05), PLINTH_TOP + 3.2, 0), Vector3.new(0.15, 0.4, 14), C.Molten, NEON, Style.tiny())
	end
	-- the open fire pit in the middle of the hall (seen from above through the door)
	Style.block(m, at(0, PLINTH_TOP + 0.6, -3), Vector3.new(5, 1.2, 3.8), C.StoneDark, nil, Style.solid())
	local pit = Style.block(m, at(0, PLINTH_TOP + 1.3, -3), Vector3.new(4.2, 0.25, 3), C.Ember, NEON, Style.tiny())
	pit.Name = "FirePit"
	Style.light(pit, C.Fire, 36, 2)
	Style.emitter(pit, "Fire", C.Fire, 12)
	for _, s in { -1, 1 } do
		-- furnace with an Ember mouth and an iron flue
		Style.block(m, at(s * 5.2, 4 + DY, 2.5), Vector3.new(3.4, 5, 3.4), Style.vary(C.StoneDark, rng, 0.04), nil, Style.solid())
		Style.block(m, at(s * 5.2, 3.4 + DY, 0.7), Vector3.new(2, 1.6, 0.25), C.Ember, NEON, Style.tiny())
		Style.block(m, at(s * 5.2, 9 + DY, 2.5), Vector3.new(1.2, 5, 1.2), C.Iron, nil, Style.tiny())
		-- anvil on a stump
		Style.block(m, at(s * 3.4, PLINTH_TOP + 0.9, -8.5), Vector3.new(1.4, 1.8, 1.4), C.WoodDark, nil, Style.solid())
		Style.block(m, at(s * 3.4, PLINTH_TOP + 2.2, -8.5), Vector3.new(1.1, 0.8, 2.6), C.IronLight, METAL, Style.tiny())
		-- hanging chain
		Style.block(m, at(s * 3.6, 9.9, -4), Vector3.new(0.3, 3.2, 0.3), C.Iron, METAL, Style.tiny())
	end
	for _, z in { -10, -3, 3 } do
		Style.block(m, at(0, DOOR_TOP - 0.4, z), Vector3.new(DOOR_HALF * 2, 0.8, 0.8), C.WoodDark, nil, Style.tiny())
	end
	-- a molten channel from the pit to the threshold
	local channel = Style.block(m, at(0, PLINTH_TOP + 0.12, -9), Vector3.new(1.2, 0.12, 8.4), C.Molten, NEON, Style.tiny())
	channel.Name = "MoltenChannel"
	local threshold = Style.block(m, at(0, PLINTH_TOP + 0.12, NAVE_FRONT + 1.4), Vector3.new(2.4, 0.14, 1.6), C.Molten, NEON, Style.tiny())
	threshold.Name = "MoltenChannel"
	Style.light(threshold, C.Fire, 24, 1.6)

	------------------------------------------------------------ porch props
	-- dark metal braziers in front of the wing windows (clear of the banners), crates at the corners
	for _, s in { -1, 1 } do
		local bx = s * 16.4
		Style.block(m, at(bx, PLINTH_TOP + 0.8, -15.6), Vector3.new(2, 1.6, 2), K.MetalDark, nil, Style.solid())
		Style.block(m, at(bx, PLINTH_TOP + 1.9, -15.6), Vector3.new(2.6, 0.6, 2.6), K.Metal, nil, Style.tiny())
		Style.block(m, at(bx, PLINTH_TOP + 0.9, -16.63), Vector3.new(1.2, 0.9, 0.1), K.NeonOrange, NEON, Style.tiny())
		local fire = Style.block(m, at(bx, PLINTH_TOP + 2.25, -15.6), Vector3.new(2, 0.3, 2), C.Ember, NEON, Style.tiny())
		fire.Name = "BrazierCoals"
		Style.emitter(fire, "Fire", C.Fire, 10)
		Style.crate(m, at(s * 19.4, PLINTH_TOP, -15.6), rng, 2)
	end
end

return GreatForge
