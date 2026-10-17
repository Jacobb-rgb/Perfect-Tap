--[[
	THE GREAT FORGE (LOBBY_PLAN 6.3.4, restyled after concept v2), the
	landmark north of the plaza. Footprint x -21..21, z -78..-38 (piece
	GreatForge), front toward the plaza, everything below y 32.

	Read like concept v2: a low, wide hall under one big gable. The forge
	stands on a raised stone plinth (porch at y 6.5) reached by a monumental
	flight of thirteen risers between stone cheek walls with dark metal handrails
	(orange neon undersides, Kenney stairs-handrail) and a dark metal lantern
	pillar on each cheek; a thin orange glow line on the top step's lip and
	a warm pool of light on the porch show the light spilling out. The tall
	arched doorway (a stone arch under a dark timber lintel, dark stone hall
	walls) opens on a glowing workshop: a dark brick back wall with narrow
	glowing window strips, the dark silhouette of the furnace (its glowing
	mouth pulses), coal beds, two anvils and a tool rack, hanging lamps. Right over the lintel a
	2-stud timber beam band carries THE GREAT FORGE board (iron straps at its
	ends) at the foot of a big, steep dark slate cross gable (eave 16.5, apex
	31.3: the gable is nearly half the facade) framed by brick-red
	bargeboards; in the gable warm timber beams (a collar beam and two
	braces) frame a dark crest plate with a glowing orange edge that carries
	the big glowing gold crossed hammers. Two lower stone wings with dark
	slate roofs (thin shingle courses, brick-red eaves and ridge shoulders,
	big lit windows) flank it; two crimson banners (gold border, gold
	crossed hammers, a dark rod with gold finials, a swallow-tail foot) hang
	0.3 in front of their own dark piers just outside the stairs, from the
	sign's level down to the door's middle;
	a gold mine cart and dark metal crates beside the stairs; two short
	dark slate chimneys behind the wing ridges (x +-15, z -71.5).

	Local frame (LobbyLayout.frame): origin at the piece center on the
	ground, front = -Z (toward the plaza), local +X = the viewer's left
	when seen from the plaza. Four PointLights: the furnace, the threshold
	and the two stair lanterns (short range: no light reaches the banners).
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
-- (the forge paths, WorldLayout roads at x +-26, 9 wide, run along both
-- sides: the hall fills its footprint up to them, x -21..21)
-- (lobby fix round 2: grown upward and deeper, not wider: a plinth 3.5
-- higher with a longer stair, so the lit door stays above the fire crystal,
-- eaves, gable, ridge and emblem about 1.1-1.2x, the hall 4 studs deeper)
GreatForge.HalfWidth = 21
GreatForge.PlinthTop = 10 -- the raised porch and hall floor (the door shows over the fire crystal)
GreatForge.WingEave = 19.5
GreatForge.WingRoofHeight = 6.2 -- wing ridge 25.7: it dies into the nave roof's slope
GreatForge.NaveEave = 21.1 -- the gable starts right over the entrance's beam band
GreatForge.NaveRoofHeight = 15.4 -- gable apex 36.5 (the DEPTHS sign still shows over it from the hero camera)
GreatForge.NaveRoofHalf = 14.6 -- the cross gable spans x -14.6..14.6: slate shows both sides of the gable
GreatForge.ChimneyTop = 33 -- short chimneys behind the wing ridges (under the gable's apex)
GreatForge.SignY = 22.8 -- THE GREAT FORGE board center (at the foot of the gable)
GreatForge.SignWidth = 18.4 -- (between the banner rods' inner finials; the ends sit on iron brackets)
GreatForge.SignHeight = 4.2
GreatForge.EmblemY = 30.1 -- center of the gold crossed hammers inside the gable
GreatForge.EmblemSize = 7.9 -- ~a quarter of the gable's width
GreatForge.StairHalfWidth = 8 -- the flight runs x -8..8 (the door width)
GreatForge.StairSteps = 20 -- risers of 0.48 from the plaza apron (y 0.4) to the porch
GreatForge.DoorTop = 17.7
GreatForge.DoorHalf = 7
GreatForge.BannerX = 11.9 -- banner centers (local x = +-11.9), just outside the stair cheeks (x +-9.75)
GreatForge.BannerWidth = 3.4 -- the border plate (the crimson cloth is 0.4 narrower)
GreatForge.BannerTop = 23.8 -- the cloth hangs from the sign's level ...
GreatForge.BannerBottom = 13.9 -- ... down to the door's middle (about 60% of a full-height banner), a V-notched foot
-- (lobby fix round 3) the gable's front planes, back to front: the infill
-- (GableZ), the bargeboards (GableZ - 0.2) and THE GREAT FORGE board in
-- front of both (SignZ: its back face clears the bargeboards' front face)
GreatForge.GableZ = -9 - 2.2 - 0.2
GreatForge.SignZ = GreatForge.GableZ - 0.95
GreatForge.SignDepth = 0.7

local PLINTH_TOP = GreatForge.PlinthTop
local NAVE = 9 -- nave wall half width
local NAVE_FRONT = -9
local WING_FRONT = -7
local WALL_BACK = 20
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
local NAVE_ROOF_Z0 = NAVE_FRONT - 2.2 -- nave roof: front gable (the slopes reach forward over the sign) .. back
local NAVE_ROOF_Z1 = WALL_BACK + 1.5
local DOOR_HALF = GreatForge.DoorHalf
local DOOR_TOP = GreatForge.DoorTop
local LINTEL_TOP = DOOR_TOP + 1.2 -- the dark timber lintel over the door (y 12.8 .. 14.1)
local WING_X = NAVE + 5.5 -- wing centers (wings x 9..20)
local FIRELIT_DARK = Color3.fromRGB(100, 58, 42) -- the back wall of the hall
local IRON_DARK = Color3.fromRGB(38, 36, 40) -- the furnace, sign straps
local TIMBER = Color3.fromRGB(170, 106, 58) -- warm timber beams in the gable (light enough to read on the shaded gable)
local BACK_BRICK = Color3.fromRGB(60, 32, 24) -- the dark brick back wall of the hall (the hearth glows in front of it)
local FORGE_BOARD = Color3.fromRGB(40, 24, 18) -- THE GREAT FORGE board: near-black timber under gold letters
local PIER_FRONT = PORCH_FRONT - 0.9 -- the banner piers stand in front of the plinth (z -11.9 .. -11)
local WIDTH = 2 * GreatForge.HalfWidth

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
				Style.block(m, onSlope(0, r / (rows + 1)), Vector3.new(width - 0.1, 0.2, 0.32), K.RoofSlateDark, nil, Style.tiny())
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
		at(0, PLINTH_TOP / 2, (PORCH_FRONT + 23.5) / 2),
		Vector3.new(WIDTH, PLINTH_TOP, 23.5 - PORCH_FRONT),
		Style.vary(C.StoneDark, rng, 0.03),
		nil,
		Style.solid()
	)
	-- light coping along the porch edge, a dark base course under it
	Style.block(m, at(0, PLINTH_TOP - 0.15, PORCH_FRONT - 0.1), Vector3.new(WIDTH, 0.3, 0.4), C.StoneLight, nil, Style.tiny())
	local courseW = GreatForge.HalfWidth - 9.6
	for _, s in { -1, 1 } do
		Style.block(m, at(s * (9.6 + courseW / 2), 0.6, PORCH_FRONT - 0.1), Vector3.new(courseW, 1.2, 0.3), C.StoneDeep, nil, Style.tiny())
		-- a second, lighter stone course halfway up the raised plinth
		Style.block(
			m,
			at(s * (9.6 + courseW / 2), PLINTH_TOP * 0.55, PORCH_FRONT - 0.1),
			Vector3.new(courseW, 0.35, 0.3),
			C.StoneLight,
			nil,
			Style.tiny()
		)
	end
	-- the light spilling out of the doorway: a thin orange glow line on the
	-- lip of the top step and a warm pool of light on the porch floor
	local lip = Style.block(
		m,
		at(0, PLINTH_TOP - 0.12, PORCH_FRONT - 0.33),
		Vector3.new(GreatForge.StairHalfWidth * 2 - 0.4, 0.12, 0.08),
		C.Ember,
		NEON,
		Style.tiny()
	)
	lip.Name = "StairLipGlow"
	local spill = Style.block(
		m,
		at(0, PLINTH_TOP + 0.02, (PORCH_FRONT + NAVE_FRONT) / 2 - 0.1),
		Vector3.new(GreatForge.DoorHalf * 2 + 1, 0.04, NAVE_FRONT - PORCH_FRONT - 0.2),
		K.Amber,
		nil,
		Style.tiny()
	)
	spill.Transparency = 0.55
	spill.Name = "LightSpill"
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
		-- (lobby fix round 3) a thin warm glow line along the coping's inner
		-- edge: the light of the hall runs down the stairs
		Style.block(m, slopeMid * CFrame.new(-s * 0.78, 0.18, 0), Vector3.new(0.18, 0.08, coping - 0.2), K.Amber, NEON, Style.tiny()).Name =
			"CheekGlow"
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
		-- (short range: it lights the stairs, not the banners beside them)
		Common.pillarLantern(m, CFrame.lookAt(at(cx, newelH + 0.3, front + 1.15).Position, at(cx, newelH + 0.3, front - 5).Position), {
			Height = 3.8,
			Light = true,
			Range = 6,
			Brightness = 1.2,
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
		-- (lobby fix round 3: a bigger lit window and a wall lantern on the
		-- corner pillar: the wings glow too)
		Style.window(m, at(s * 16.2, PLINTH_TOP + 4.6, WING_FRONT - 0.45), 3, 4.4, { Color = K.WindowGlow })
		local lampY = PLINTH_TOP + 6.3
		local lampZ = WING_FRONT + 0.7 - 1.2 -- the corner pillar's front face
		Style.block(m, at(s * 19.2, lampY + 0.85, lampZ - 0.3), Vector3.new(0.3, 0.3, 1.2), K.MetalDark, nil, Style.tiny())
		Style.block(m, at(s * 19.2, lampY, lampZ - 0.85), Vector3.new(0.9, 1.3, 0.9), K.MetalDark, nil, Style.tiny())
		Style.block(m, at(s * 19.2, lampY + 0.75, lampZ - 0.85), Vector3.new(1.2, 0.2, 1.2), K.Metal, nil, Style.tiny())
		Style.block(m, at(s * 19.2, lampY, lampZ - 1.33), Vector3.new(0.32, 0.9, 0.06), K.SlotAmber, NEON, Style.tiny()).Name = "WingLantern"
		for _, wz in { 1, 10 } do
			Style.window(m, at(s * 20.45, PLINTH_TOP + 4.6, wz) * CFrame.Angles(0, -s * math.pi / 2, 0), 2.6, 3.4, { Color = K.WindowGlow })
		end
		-- dark slate wing roof (ridge along X), brick-red eaves, timber infill in
		-- the outer gable end; its inner end and ridge stay under the nave roof
		local depth = WING_ROOF_Z1 - WING_ROOF_Z0
		local roofW = WING_ROOF_X1 - WING_ROOF_X0
		local wingRoof = at(s * (WING_ROOF_X0 + WING_ROOF_X1) / 2, WING_EAVE, (WING_ROOF_Z0 + WING_ROOF_Z1) / 2)
		Style.gableRoof(m, wingRoof, roofW, depth, WING_ROOF_H, WING_ROOF)
		-- shingle joints on the front slope (seen from the plaza), courses only at the back
		roofCourses(wingRoof, roofW, depth, WING_ROOF_H, { -1 }, 4, 3)
		roofCourses(wingRoof, roofW, depth, WING_ROOF_H, { 1 }, 4)
		-- the brick-red shoulder: a ridge cap along the wing roof up to the nave roof
		Style.block(
			m,
			at(s * (WING_ROOF_X0 + WING_ROOF_X1) / 2, WING_EAVE + WING_ROOF_H + 0.12, (WING_ROOF_Z0 + WING_ROOF_Z1) / 2),
			Vector3.new(roofW + 0.2, 0.5, 1.1),
			K.BrickRed,
			nil,
			Style.tiny()
		).Name =
			"RoofShoulder"
		local infillHalf = depth / 2 - 1.8
		triangle(
			at(s * 20.65, WING_EAVE, (WING_ROOF_Z0 + WING_ROOF_Z1) / 2) * CFrame.Angles(0, -s * math.pi / 2, 0),
			infillHalf,
			infillHalf * WING_ROOF_H / (depth / 2),
			0.3,
			C.WoodDark
		)

		-- a short dark slate chimney behind the wing's ridge (world x +-15,
		-- z -71.5): from the plaza only its top shows over the wing roof, under
		-- the gable's apex, so the roof line stays clean round the emblem
		local chimney = Style.model("Chimney", m)
		local cz = 13.5
		local cx = s * 15
		local shaftTop = GreatForge.ChimneyTop - 1.6
		Style.block(
			chimney,
			at(cx, (PLINTH_TOP + shaftTop) / 2, cz),
			Vector3.new(3.4, shaftTop - PLINTH_TOP, 3.4),
			Style.vary(K.RoofSlateDark, rng, 0.03),
			nil,
			Style.solid()
		)
		-- a brick-red cap band and a dark crown
		Style.block(chimney, at(cx, shaftTop - 0.9, cz), Vector3.new(3.7, 1, 3.7), K.BrickRed)
		Style.block(chimney, at(cx, shaftTop + 0.6, cz), Vector3.new(4.1, 1.2, 4.1), Style.vary(K.MetalDark, rng, 0.04))
		local top = Style.block(chimney, at(cx, shaftTop + 1.4, cz), Vector3.new(2.6, 0.4, 2.6), C.Ember, NEON, Style.tiny())
		top.Name = "ChimneyGlow"
		Style.emitter(top, "Smoke", nil, 3)
		Style.emitter(top, "Embers", C.Ember, 2)
	end

	------------------------------------------------------------ crimson banners beside the entrance
	-- concept v2: two long crimson banners flank the sign and the stairs.
	-- Each hangs 0.6 in front of its own dark metal pier (standing on the
	-- ground in front of the plinth, just outside the stair cheek) from a
	-- dark rod with gold finials at the sign's level down to just over the
	-- ground: a gold border plate, the crimson cloth with big gold crossed
	-- hammers in its upper middle, two gold bands and a pointed foot
	for _, s in { -1, 1 } do
		local bx = s * GreatForge.BannerX
		local banner = Style.model("Banner", m)
		local width = GreatForge.BannerWidth
		local clothW = width - 0.4
		local clothTop, clothBottom = GreatForge.BannerTop, GreatForge.BannerBottom
		local clothMid = (clothTop + clothBottom) / 2
		local clothH = clothTop - clothBottom
		local tail = 1.2
		-- a slim dark pier (narrower than the banner: the cloth hangs free in
		-- front of it, it does not read as paint on a pillar)
		local pierW = 1.4
		local pierTop = clothTop + 0.9
		local bz = PIER_FRONT - 0.45 -- the cloth plane (0.45 off the pier)
		-- the dark pier and its cap with a small amber lamp
		Style.block(
			banner,
			at(bx, pierTop / 2, (PORCH_FRONT + PIER_FRONT) / 2),
			Vector3.new(pierW, pierTop, PORCH_FRONT - PIER_FRONT),
			Style.vary(K.MetalDark, rng, 0.03),
			nil,
			Style.decor()
		).Name =
			"BannerPier"
		Style.block(
			banner,
			at(bx, pierTop + 0.2, (PORCH_FRONT + PIER_FRONT) / 2 - 0.1),
			Vector3.new(pierW + 0.4, 0.4, PORCH_FRONT - PIER_FRONT + 0.4),
			K.Metal,
			nil,
			Style.tiny()
		)
		Style.block(
			banner,
			at(bx, pierTop + 0.7, (PORCH_FRONT + PIER_FRONT) / 2 - 0.1),
			Vector3.new(0.6, 0.6, 0.6),
			K.Amber,
			NEON,
			Style.tiny()
		).Name =
			"PierLamp"
		-- the gold rod across the cloth's top, on a dark bracket from the pier, gold finials
		local rodY = clothTop + 0.3
		Style.block(banner, at(bx, rodY, bz - 0.05), Vector3.new(width + 0.5, 0.3, 0.3), C.Gold, nil, Style.tiny()).Name = "BannerRod"
		Style.block(
			banner,
			at(bx, rodY + 0.02, (bz + PIER_FRONT) / 2 - 0.1),
			Vector3.new(0.34, 0.34, PIER_FRONT - bz + 0.1),
			K.MetalDark,
			nil,
			Style.tiny()
		).Name =
			"BannerBracket"
		for _, t in { -1, 1 } do
			Style.block(banner, at(bx + t * (width / 2 + 0.35), rodY, bz - 0.05), Vector3.new(0.5, 0.5, 0.5), C.Gold, nil, Style.tiny()).Name =
				"BannerFinial"
		end
		-- the dark crimson border plate behind the cloth (also behind its notched foot)
		Style.block(banner, at(bx, clothMid, bz + 0.06), Vector3.new(width, clothH + 0.3, 0.1), K.BannerDark, nil, Style.tiny()).Name =
			"BannerBorder"
		local cloth = Style.block(banner, at(bx, clothMid, bz - 0.03), Vector3.new(clothW, clothH, 0.12), K.Banner, nil, Style.tiny())
		cloth.Name = "BannerCloth"
		-- the swallow-tail foot (two wedges, upside down, their tall sides at the
		-- outer edges: two tails with a notch between them) on slightly larger
		-- gold wedges: a gold edge round the tails
		for _, spec in
			{ { W = clothW, T = tail, Z = bz - 0.03, Color = K.Banner }, { W = width, T = tail + 0.3, Z = bz + 0.06, Color = K.BannerDark } }
		do
			for _, t in { -1, 1 } do
				Geo.wedge(
					banner,
					at(bx + t * spec.W / 4, clothBottom - spec.T / 2 + 0.01, spec.Z)
						* CFrame.Angles(math.pi, 0, 0)
						* CFrame.Angles(0, t * math.pi / 2, 0),
					Vector3.new(0.1, spec.T, spec.W / 2),
					spec.Color,
					SMOOTH,
					Style.tiny()
				)
			end
		end
		-- big gold crossed hammers in the upper middle (matte gold, not neon:
		-- they stay gold, no bloom) and two thin gold bands
		local iconY = clothTop - clothH * 0.36
		for _, part in Style.icon(banner, at(bx, iconY, bz - 0.2), "CrossedHammersV2", 3.5, C.Gold, SMOOTH) do
			part.Name = "BannerIcon"
		end
		for _, y in { clothTop - 1.1, clothBottom + 1.2 } do
			Style.block(banner, at(bx, y, bz - 0.11), Vector3.new(clothW, 0.24, 0.06), C.Gold, nil, Style.tiny())
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
	-- (dark stone hall walls: the bright back of the hall reads against them)
	for _, s in { -1, 1 } do
		Style.block(
			m,
			at(s * (DOOR_HALF + 1), (PLINTH_TOP + DOOR_TOP) / 2, (NAVE_FRONT + WALL_BACK) / 2),
			Vector3.new(2, DOOR_TOP - PLINTH_TOP, WALL_BACK - NAVE_FRONT),
			C.StoneDeep,
			nil,
			Style.solid()
		).Name =
			"HallWall"
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
	-- (lobby fix round 3: the board hung behind the gable infill and never
	-- showed; now it hangs in front of the whole gable, the infill at
	-- GableZ and the bargeboards just in front of it)
	local gz = GreatForge.GableZ
	local signZ = GreatForge.SignZ
	local signW = GreatForge.SignWidth
	local sign = Style.sign(
		m,
		at(0, GreatForge.SignY, signZ),
		"THE GREAT FORGE",
		signW,
		GreatForge.SignHeight,
		{ Kind = "Wood", Depth = GreatForge.SignDepth, BoardColor = FORGE_BOARD }
	)
	sign.Name = "ForgeSign"
	-- dark board, gold letters that ignore the shade of the gable (concept v2)
	for _, gui in sign:GetChildren() do
		if gui:IsA("SurfaceGui") then
			gui.LightInfluence = 0
		end
	end
	local signBottom = GreatForge.SignY - GreatForge.SignHeight / 2
	-- iron bracket plates from the timber band out to the board's back (a
	-- strap from the front, a bracket from the side: nothing floats)
	local bandFront = NAVE_FRONT - 0.24
	for _, s in { -1, 1 } do
		Style.block(
			m,
			at(s * (signW / 2 - 0.7), (LINTEL_TOP + signBottom) / 2 + 0.2, (signZ + 0.05 + bandFront) / 2),
			Vector3.new(0.35, signBottom - LINTEL_TOP + 0.4, bandFront - signZ + 0.2),
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
	roofCourses(naveRoof, naveLen, NAVE_HALF * 2, NAVE_ROOF_H, { -1, 1 }, 7)
	-- a brick-red ridge trim along the nave's ridge (from the gable's apex back)
	Style.block(
		m,
		at(0, APEX + 0.05, (NAVE_ROOF_Z0 + NAVE_ROOF_Z1) / 2 + 0.6),
		Vector3.new(0.9, 0.5, naveLen - 1.4),
		K.BrickRed,
		nil,
		Style.tiny()
	).Name =
		"RidgeTrim"
	-- dark timber gable infill just in front of the roof's end face, inset so
	-- a band of slate and the bargeboards frame it
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

	-- warm timber framing in the gable round the crest (lighter than the
	-- dark infill): a collar beam over the board and two braces rising to
	-- the crest's shoulders
	local collarY = GreatForge.SignY + GreatForge.SignHeight / 2 + 0.75
	local collarHalf = (APEX - 0.6 - collarY) / NAVE_PITCH - 0.3
	Style.block(m, at(0, collarY, gz - 0.24), Vector3.new(collarHalf * 2, 0.9, 0.2), TIMBER, nil, Style.tiny()).Name = "GableBeam"
	for _, s in { -1, 1 } do
		local x0, y0 = s * (collarHalf - 0.9), collarY + 0.2
		local x1, y1 = s * 5.8, collarY + 4.3
		local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
		Style.block(
			m,
			at((x0 + x1) / 2, (y0 + y1) / 2, gz - 0.24) * CFrame.Angles(0, 0, math.atan2(y1 - y0, x1 - x0)),
			Vector3.new(len, 0.75, 0.2),
			TIMBER,
			nil,
			Style.tiny()
		).Name =
			"GableBeam"
	end
	-- the crest: a dark metal plate shaped like a small gable (flat foot,
	-- vertical sides, its top parallel to the bargeboards) on a slightly
	-- larger glowing orange border, carrying the big glowing deep-gold
	-- crossed hammers
	local crestFoot = GreatForge.SignY + GreatForge.SignHeight / 2 + 0.5
	local crestHalf = 5.2
	local crestApex = APEX - 0.45
	local shoulder = crestApex - crestHalf * NAVE_PITCH
	for i, spec in
		{
			{ Grow = 0.28, Color = C.Ember, Material = NEON, Z = gz - 0.3 },
			{ Grow = 0, Color = K.MetalDark, Material = SMOOTH, Z = gz - 0.45 },
		}
	do
		local half = crestHalf + spec.Grow
		local foot = crestFoot - spec.Grow
		local top = shoulder + spec.Grow * (1 - NAVE_PITCH)
		local plate = Style.block(
			m,
			at(0, (foot + top) / 2, spec.Z),
			Vector3.new(half * 2, top - foot, 0.15),
			spec.Color,
			spec.Material,
			Style.tiny()
		)
		plate.Name = if i == 1 then "EmblemBorder" else "Emblem"
		triangle(at(0, top, spec.Z), half, half * NAVE_PITCH, 0.15, spec.Color, spec.Material)
	end
	-- a deep-gold neon halo (the same hammers, a size larger) behind solid gold
	-- hammers: the emblem glows at its edges and stays gold, no white blob
	for _, part in
		Style.icon(m, at(0, GreatForge.EmblemY - 0.05, gz - 0.62), "CrossedHammersV2", GreatForge.EmblemSize * 1.12, K.EmblemGold, NEON)
	do
		part.Name = "EmblemGlow"
	end
	for _, part in Style.icon(m, at(0, GreatForge.EmblemY, gz - 0.95), "CrossedHammersV2", GreatForge.EmblemSize, C.Gold, SMOOTH) do
		part.Name = "EmblemHammers"
	end

	------------------------------------------------------------ interior (seen through the entrance)
	-- a glowing workshop (concept v2: warm light in the arched doorway): a
	-- dark brick back wall (BackWall) with a few narrow glowing window
	-- strips, and against it the dark silhouette of the furnace, its mouth
	-- (ForgeGlow) pulsing on the client with flames licking out, two
	-- glowing coal beds at its feet, dark glowing seams down the hall
	-- walls, two anvils and a tool rack, hanging lamps
	local fz = 7.7 -- the back wall (just in front of the back block)
	local back = Style.block(
		m,
		at(0, (PLINTH_TOP + DOOR_TOP) / 2, fz + 0.15),
		Vector3.new(DOOR_HALF * 2, DOOR_TOP - PLINTH_TOP, 0.3),
		BACK_BRICK,
		nil,
		Style.tiny()
	)
	back.Name = "BackWall"
	-- (lobby fix round 3: the hall glows like concept v2's furnace hall) a
	-- wide furnace fills the back of the hall: a dark iron body with a wide
	-- deep-amber glowing band and a molten core line across it, a big
	-- hearth mouth (ForgeGlow) between two smaller mouths, a hood and a flue
	local furnaceH = 5.6
	local furnaceD = 1.6
	local furnaceZ = fz - furnaceD / 2 - 0.02
	local furnaceFront = furnaceZ - furnaceD / 2
	Style.block(
		m,
		at(0, PLINTH_TOP + furnaceH / 2, furnaceZ),
		Vector3.new(DOOR_HALF * 2 - 2.4, furnaceH, furnaceD),
		IRON_DARK,
		nil,
		Style.solid()
	).Name =
		"Furnace"
	local band =
		Style.block(m, at(0, PLINTH_TOP + 4.3, furnaceFront - 0.03), Vector3.new(DOOR_HALF * 2 - 3.4, 1.7, 0.06), K.SlotAmber, NEON, Style.tiny())
	band.Name = "FurnaceGlow"
	local core = Style.block(m, at(0, PLINTH_TOP + 4.3, furnaceFront - 0.08), Vector3.new(DOOR_HALF * 2 - 3.6, 0.45, 0.06), C.Molten, NEON, Style.tiny())
	core.Name = "FurnaceGlow"
	local glow = Style.block(m, at(0, PLINTH_TOP + 1.5, furnaceFront - 0.03), Vector3.new(4.2, 2.6, 0.06), C.Ember, NEON, Style.tiny())
	glow.Name = "ForgeGlow"
	Style.light(glow, C.Fire, 18, 1.8)
	Style.emitter(glow, "Fire", C.Fire, 6)
	Style.emitter(glow, "Embers", C.Ember, 5)
	for _, x in { -3.75, 3.75 } do
		local mouth = Style.block(m, at(x, PLINTH_TOP + 1.25, furnaceFront - 0.03), Vector3.new(2, 1.7, 0.06), K.SlotAmber, NEON, Style.tiny())
		mouth.Name = "FurnaceGlow"
	end
	-- glowing coal beds in front of the side mouths
	for _, x in { -4.2, 4.2 } do
		local coal = Style.block(m, at(x, PLINTH_TOP + 0.18, furnaceFront - 0.9), Vector3.new(2.4, 0.35, 1.2), C.Ember, NEON, Style.tiny())
		coal.Name = "FurnaceGlow"
	end
	-- the hood over the whole furnace and the flue up to the beams
	Style.block(m, at(0, PLINTH_TOP + furnaceH + 0.4, furnaceZ - 0.2), Vector3.new(DOOR_HALF * 2 - 1.6, 0.8, furnaceD + 0.6), IRON_DARK, nil, Style.tiny())
	Style.block(
		m,
		at(0, (PLINTH_TOP + furnaceH + 0.8 + DOOR_TOP) / 2, furnaceZ),
		Vector3.new(2, DOOR_TOP - PLINTH_TOP - furnaceH - 0.8, 1.2),
		IRON_DARK,
		nil,
		Style.tiny()
	)
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
	-- a second anvil to the side (a dark silhouette against the coal bed's glow)
	Style.block(m, at(3.6, PLINTH_TOP + 0.5, 1.4), Vector3.new(1.1, 1.0, 1.1), C.WoodDark, nil, Style.solid())
	Style.block(m, at(3.6, PLINTH_TOP + 1.3, 1.4), Vector3.new(2.0, 0.6, 0.9), IRON_DARK, nil, Style.tiny())
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
		at(0, PLINTH_TOP + 0.1, NAVE_FRONT + 0.6),
		Vector3.new(DOOR_HALF * 2 - 0.8, 0.2, 0.6),
		C.Molten,
		NEON,
		Style.tiny()
	)
	threshold.Name = "MoltenChannel"
	-- (lobby fix round 3: the threshold's PointLight became this SurfaceLight)
	-- warm light spilling out of the hall down the stairs: a narrow emitter
	-- plate under the lintel, tilted 30 degrees down toward the stairs; its
	-- 70 degree beam stays well inside the banners
	local spillPlate = Style.block(
		m,
		at(0, DOOR_TOP - 0.15, NAVE_FRONT - 0.9) * CFrame.Angles(-math.rad(30), 0, 0),
		Vector3.new(6, 0.25, 0.6),
		K.MetalDark,
		nil,
		Style.tiny()
	)
	spillPlate.Name = "HallSpillLight"
	local spillLight = Instance.new("SurfaceLight")
	spillLight.Face = Enum.NormalId.Front
	spillLight.Color = Color3.fromRGB(255, 150, 60)
	spillLight.Range = 24
	spillLight.Brightness = 1.6
	spillLight.Angle = 70
	spillLight.Shadows = false
	spillLight.Parent = spillPlate

	------------------------------------------------------------ porch and stair props
	-- beside the stairs (north-east / north-west of the plaza): a gold mine
	-- cart and dark metal crates with orange glowing straps (no braziers: the
	-- lantern pillars and the doorway are the only fires out front)
	local props = Style.model("StairProps", m)
	-- (out beside the banners: nothing stands in front of their pointed feet)
	for _, s in { -1, 1 } do
		local cart = at(s * 17.2, 0, front + 5.6)
		local cartModel = Style.mineCart(props, cart * CFrame.Angles(0, math.pi / 2 + s * 0.25, 0), rng, { Load = "Gold" })
		-- matte gold load (no glowing blobs beside the stairs)
		for _, d in cartModel:GetDescendants() do
			if d:IsA("BasePart") and d.Material == NEON then
				d.Material = SMOOTH
			end
		end
		for i, spec in { { X = 19.2, Z = front + 2.4, S = 2.2 }, { X = 16.4, Z = front + 2.0, S = 1.7 } } do
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
