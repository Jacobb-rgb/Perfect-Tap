--[[
	THE GREAT FORGE (LOBBY_PLAN 6.3.4, restyled after concept v2), the
	landmark north of the plaza. Footprint x -21..21, z -78..-38 (piece
	GreatForge), front toward the plaza, everything but the chimneys below
	y 32.

	Read like concept v2: the forge stands on a raised stone plinth (porch
	at y 4.9) reached by a monumental flight of ten risers between stone
	cheek walls with dark metal handrails (orange neon undersides, Kenney
	stairs-handrail) and a dark metal lantern pillar on each cheek. Above
	the tall glowing doorway (a busy workshop inside: three furnace mouths
	in dark iron frames, an anvil and a tool rack against the glow, hanging
	lamps) a timber-framed upper floor with two lit windows carries THE
	GREAT FORGE board, which sits at the foot of a wide dark slate cross
	gable framed by brick-red bargeboards; inside the gable a dark metal
	crest carries the big glowing gold crossed hammers. Two lower stone wings
	with dark slate roofs (brick-red eaves) flank it; two tall crimson
	banners with gold hammers hang from under the wing eaves down to the
	porch, left and right of the entrance; braziers stand on the porch
	corners, a gold mine cart and dark metal crates beside the stairs; two
	chimneys at the back corners (x +-18, z -74.5).

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
GreatForge.WingRoofHeight = 6.2 -- wing ridge 20.6, under the nave eave
GreatForge.NaveEave = 21
GreatForge.NaveRoofHeight = 10.3 -- gable apex 31.3
GreatForge.NaveRoofHalf = 12 -- the cross gable spans x -12..12
GreatForge.ChimneyTop = 43
GreatForge.SignY = 22 -- THE GREAT FORGE board center (at the foot of the gable)
GreatForge.EmblemY = 26.3 -- center of the gold crossed hammers inside the gable
GreatForge.EmblemSize = 4.4
GreatForge.StairHalfWidth = 8 -- the flight runs x -8..8 (the door width)
GreatForge.StairSteps = 10 -- risers of 0.45 from the plaza apron (y 0.4) to the porch
GreatForge.DoorTop = 12.9
GreatForge.DoorHalf = 7
GreatForge.BannerX = 12.3 -- banner centers (local x = +-12.3), on the wing fronts
GreatForge.BannerWidth = 3.6

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
local NAVE_ROOF_Z0 = NAVE_FRONT - 1 -- nave roof: front gable .. back
local NAVE_ROOF_Z1 = WALL_BACK + 1.5
local DOOR_HALF = GreatForge.DoorHalf
local DOOR_TOP = GreatForge.DoorTop
local WING_X = NAVE + 5.5 -- wing centers (wings x 9..20)
local FIRELIT = Color3.fromRGB(112, 72, 58) -- hall walls lit by the furnaces
local FIRELIT_DARK = Color3.fromRGB(74, 46, 42) -- the furnace wall and the back wall

-- dark slate roof tiles with brick-red eaves, gable boards (bargeboards) and ridge
local NAVE_ROOF = { Rows = 3, Color = K.RoofSlate, Dark = K.RoofSlateDark, Trim = K.BrickRed, Ridge = false }
local WING_ROOF = { Rows = 2, Color = K.RoofSlate, Dark = K.RoofSlateDark, Trim = K.BrickRed }

function GreatForge.build(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("GreatForge")
	local frame = LobbyLayout.frame(piece)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local m = Style.model("GreatForge", parent)
	local front = -piece.Size.Z / 2

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
		).Name = "StairCheek"
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
		-- dark slate wing roof (ridge along X), brick-red eaves, timber infill in the outer gable end
		local depth = WING_ROOF_Z1 - WING_ROOF_Z0
		local wingRoof = at(s * 15, WING_EAVE, (WING_ROOF_Z0 + WING_ROOF_Z1) / 2)
		Style.gableRoof(m, wingRoof, 11.2, depth, WING_ROOF_H, WING_ROOF)
		roofSeams(wingRoof, 11.2, depth, WING_ROOF_H, { -1 }, 4)
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
	for _, s in { -1, 1 } do
		local bx = s * GreatForge.BannerX
		local bz = WING_FRONT - 0.75
		local banner = Style.model("Banner", m)
		local width = GreatForge.BannerWidth
		-- from just under the wing eave down to the porch (the tail ends above it)
		local clothTop, clothBottom = WING_EAVE - 1, PLINTH_TOP + 1.1
		local clothMid = (clothTop + clothBottom) / 2
		local clothH = clothTop - clothBottom
		-- dark metal header with gold end caps, the cloth hangs from it
		Style.block(banner, at(bx, clothTop + 0.2, bz - 0.1), Vector3.new(width + 0.4, 0.4, 0.45), K.MetalDark, nil, Style.tiny())
		for _, t in { -1, 1 } do
			Style.block(banner, at(bx + t * (width / 2 + 0.35), clothTop + 0.2, bz - 0.1), Vector3.new(0.3, 0.55, 0.55), C.Gold, nil, Style.tiny())
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
				at(bx + t * width / 4, clothBottom - 0.5, bz) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, -t * math.pi / 2, 0),
				Vector3.new(0.14, 1, width / 2),
				K.BannerDark,
				SMOOTH,
				Style.tiny()
			)
		end
		-- gold crossed hammers (matte gold, not neon: they stay gold, no bloom)
		for _, part in Style.icon(banner, at(bx, clothTop - 2.2, bz - 0.2), "CrossedHammers", 2.6, C.Gold, SMOOTH) do
			part.Name = "BannerIcon"
		end
		-- a thin gold band near the foot
		Style.block(banner, at(bx, clothBottom + 0.7, bz - 0.14), Vector3.new(width - 0.5, 0.22, 0.06), C.Gold, nil, Style.tiny())
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
	-- two lit windows over the entrance
	for _, s in { -1, 1 } do
		Style.window(m, at(s * 4.8, DOOR_TOP + 3.7, NAVE_FRONT - 0.5), 2.6, 2.6, { Color = K.WindowGlow })
	end

	-- entrance: stone pillars, a dark timber lintel with knee braces
	for _, s in { -1, 1 } do
		Style.pillar(m, at(s * 8.2, PLINTH_TOP, NAVE_FRONT - 0.4), DOOR_TOP - PLINTH_TOP + 0.2, rng, { Width = 2.4 })
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

	-- THE GREAT FORGE board at the foot of the gable: from the spawn camera
	-- (0, 9, 46) the sight line over the fire crystal's tip (y < 11 at the
	-- plaza center) reaches the forge front at y ~12.5, so the board, the
	-- crest and the upper half of the doorway all read above the crystal
	local sign = Style.sign(m, at(0, GreatForge.SignY, NAVE_FRONT - 1.05), "THE GREAT FORGE", 24, 4.4, { Kind = "Wood", Depth = 0.7 })
	sign.Name = "ForgeSign"

	-- wide dark slate cross gable (ridge along Z) over the nave, framed by
	-- brick-red bargeboards; no ridge beam (nothing pokes up over the apex)
	local naveRoof = at(0, NAVE_EAVE, (NAVE_ROOF_Z0 + NAVE_ROOF_Z1) / 2) * CFrame.Angles(0, math.pi / 2, 0)
	local naveLen = NAVE_ROOF_Z1 - NAVE_ROOF_Z0
	Style.gableRoof(m, naveRoof, naveLen, NAVE_HALF * 2, NAVE_ROOF_H, NAVE_ROOF)
	roofSeams(naveRoof, naveLen, NAVE_HALF * 2, NAVE_ROOF_H, { -1, 1 }, 6)
	-- dark timber gable infill just in front of the roof's end face, inset so
	-- a band of slate and the bargeboards frame it
	local gz = NAVE_ROOF_Z0 - 0.2
	local infillHalf = NAVE_HALF - 0.5
	triangle(at(0, NAVE_EAVE, gz), infillHalf, infillHalf * NAVE_PITCH, 0.3, C.WoodDark)

	-- the crest: a dark metal plate shaped like a small gable (flat foot,
	-- vertical sides, its top parallel to the bargeboards) on a slightly
	-- larger metal border, carrying the big glowing deep-gold crossed hammers
	local crestFoot = GreatForge.SignY + 2.5
	local crestHalf = 2.65
	local crestApex = APEX - 0.7
	local shoulder = crestApex - crestHalf * NAVE_PITCH
	for i, spec in { { Grow = 0.25, Color = K.Metal, Z = gz - 0.3 }, { Grow = 0, Color = K.MetalDark, Z = gz - 0.45 } } do
		local half = crestHalf + spec.Grow
		local foot = crestFoot - spec.Grow
		local top = shoulder + spec.Grow * (1 - NAVE_PITCH)
		local plate = Style.block(
			m,
			at(0, (foot + top) / 2, spec.Z),
			Vector3.new(half * 2, top - foot, 0.15),
			spec.Color,
			nil,
			Style.tiny()
		)
		plate.Name = if i == 1 then "EmblemBorder" else "Emblem"
		triangle(at(0, top, spec.Z), half, half * NAVE_PITCH, 0.15, spec.Color)
	end
	-- a deep-gold neon halo (the same hammers, a size larger) behind solid gold
	-- hammers: the emblem glows at its edges and stays gold, no white blob
	for _, part in Style.icon(m, at(0, GreatForge.EmblemY - 0.05, gz - 0.62), "CrossedHammers", GreatForge.EmblemSize * 1.12, K.EmblemGold, NEON) do
		part.Name = "EmblemGlow"
	end
	for _, part in Style.icon(m, at(0, GreatForge.EmblemY, gz - 0.95), "CrossedHammers", GreatForge.EmblemSize, C.Gold, SMOOTH) do
		part.Name = "EmblemHammers"
	end

	------------------------------------------------------------ interior (seen through the entrance)
	-- a busy workshop: the furnace wall with three big glowing mouths in dark
	-- iron frames (the middle one is ForgeGlow, it pulses on the client), a
	-- hood and flues, glowing seams down the firelit side walls, an anvil and
	-- a tool rack against the glow, hanging lamps
	local fz = 7.7 -- front face of the furnace wall
	Style.block(m, at(0, PLINTH_TOP + 3.4, fz + 0.6), Vector3.new(DOOR_HALF * 2, 6.8, 1.2), FIRELIT_DARK, nil, Style.solid())
	local mouths = {
		{ X = 0, W = 4.4, H = 3.4, Y = 2.5 },
		{ X = -4.6, W = 2.6, H = 2.8, Y = 2.2 },
		{ X = 4.6, W = 2.6, H = 2.8, Y = 2.2 },
	}
	for i, mouth in mouths do
		Style.block(
			m,
			at(mouth.X, PLINTH_TOP + mouth.Y, fz - 0.05),
			Vector3.new(mouth.W + 0.7, mouth.H + 0.7, 0.1),
			C.Iron,
			METAL,
			Style.tiny()
		)
		local glow = Style.block(m, at(mouth.X, PLINTH_TOP + mouth.Y, fz - 0.12), Vector3.new(mouth.W, mouth.H, 0.06), C.Ember, NEON, Style.tiny())
		glow.Name = if i == 1 then "ForgeGlow" else "FurnaceGlow"
		if i == 1 then
			Style.light(glow, C.Fire, 18, 1.8)
			Style.emitter(glow, "Embers", C.Ember, 5)
		end
	end
	-- iron hood over the middle mouth and two flues
	Style.block(m, at(0, PLINTH_TOP + 5.3, fz - 0.5), Vector3.new(5.8, 1.4, 1.2), C.Iron, METAL, Style.tiny())
	for _, x in { -4.6, 4.6 } do
		Style.block(m, at(x, PLINTH_TOP + 5.8, fz - 0.3), Vector3.new(1, 3.4, 1), C.Iron, METAL, Style.tiny())
	end
	-- glowing seams down the side walls of the hall
	for _, s in { -1, 1 } do
		local seam = Style.block(m, at(s * (DOOR_HALF - 0.05), PLINTH_TOP + 3.4, 0.5), Vector3.new(0.15, 0.35, 13), C.Ember, NEON, Style.tiny())
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
	local threshold = Style.block(m, at(0, PLINTH_TOP + 0.06, NAVE_FRONT + 0.7), Vector3.new(DOOR_HALF * 2 - 0.8, 0.12, 0.5), C.Molten, NEON, Style.tiny())
	threshold.Name = "MoltenChannel"
	Style.light(threshold, C.Fire, 10, 1.6)

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
			Style.block(props, base * CFrame.new(0, size / 2, 0), Vector3.new(size, size, size), Style.vary(K.Metal, rng, 0.05), nil, Style.decor())
			Style.block(props, base * CFrame.new(0, size - 0.08, 0), Vector3.new(size + 0.1, 0.2, size + 0.1), K.MetalDark, nil, Style.tiny())
			Style.block(props, base * CFrame.new(0, size * 0.45, 0), Vector3.new(size + 0.06, 0.16, size + 0.06), K.NeonOrange, NEON, Style.tiny())
		end
	end
end

return GreatForge
