--[[
	THE GREAT FORGE (LOBBY_PLAN 6.3.4), the landmark north of the plaza.
	Footprint x -21..21, z -78..-38 (piece GreatForge), front toward the
	plaza, everything but the chimneys below y 32.

	Read like the concept: a tall central nave whose steep red cross gable
	faces the plaza (dark timber infill, a stone roundel with glowing
	crossed hammers), flanked by two lower stone wings with red roofs and
	lantern turrets; THE GREAT FORGE board mounted high on the gable (so it
	reads above the fire crystal from the spawn), the hammer roundel at the
	apex, two lit windows over the open entrance between stone pillars with the
	glowing workshop inside (ForgeGlow hearth, furnaces, anvils, a molten
	channel); two tall chimneys at the back corners (x +-17, z -72).

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

local C = Style.C
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic

local GreatForge = {}

-- Main measures (local frame, studs). Exposed for the spec.
GreatForge.HalfWidth = 21
GreatForge.PlinthTop = 1.5
GreatForge.WingEave = 13.5
GreatForge.WingRoofHeight = 8.5
GreatForge.NaveEave = 17.5
GreatForge.NaveRoofHeight = 12.5
GreatForge.ChimneyTop = 40
GreatForge.SignY = 22 -- THE GREAT FORGE board center (on the nave gable)
GreatForge.RoundelY = 26.9 -- the crossed-hammers roundel at the gable apex

local PLINTH_TOP = GreatForge.PlinthTop
local NAVE = 9 -- nave half width
local NAVE_FRONT = -15
local WING_FRONT = -13
local WALL_BACK = 16
local WING_EAVE = GreatForge.WingEave
local NAVE_EAVE = GreatForge.NaveEave
local WING_ROOF_H = GreatForge.WingRoofHeight
local NAVE_ROOF_H = GreatForge.NaveRoofHeight
local WING_ROOF_DEPTH = 31
local WING_ROOF_Z = 2
local DOOR_HALF = 7
local DOOR_TOP = 11.5

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
	-- frame and measures), so the red roofs read as tiles like the concept
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
					C.RoofDark,
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

	------------------------------------------------------------ plinth and steps
	Style.block(m, at(0, PLINTH_TOP / 2, 1.5), Vector3.new(42, PLINTH_TOP, 37), Style.vary(C.StoneDark, rng, 0.03), nil, Style.solid())
	Style.block(m, at(0, PLINTH_TOP - 0.15, -17.1), Vector3.new(42, 0.3, 0.4), C.StoneLight, nil, Style.tiny())
	Style.block(m, at(0, 0.75 / 2, front + 1.5), Vector3.new(24, 0.75, 3), Style.vary(C.Stone, rng, 0.03), nil, Style.solid())
	Style.block(m, at(0, 1.12 / 2, front + 2), Vector3.new(24, 1.12, 2), Style.vary(C.StoneLight, rng, 0.03), nil, Style.solid())
	for _, s in { -1, 1 } do
		Style.lantern(m, at(s * 12.8, 0, front + 0.8), { Kind = "Ground" })
		Style.lantern(m, at(s * 12.8, 0, front + 2.4), { Kind = "Ground" })
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
		Style.stoneWall(m, at(wingX, PLINTH_TOP, WING_FRONT + 1), Vector3.new(11, WING_EAVE - PLINTH_TOP, 2), rng, { Density = 0.35 })
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
		-- lit windows: one on the front, two on the outer side
		Style.window(m, at(wingX + s * 0.5, 7.2, WING_FRONT - 0.45), 2.8, 3.6)
		for _, z in { -4, 8 } do
			Style.window(m, at(s * 20.45, 7.2, z) * CFrame.Angles(0, -s * math.pi / 2, 0), 2.6, 3.4)
		end
		-- wall lantern on a bracket beside the entrance
		Style.block(m, at(s * 10.6, 10.8, WING_FRONT - 0.6), Vector3.new(0.4, 0.4, 1.4), C.Iron, nil, Style.tiny())
		Style.lantern(m, at(s * 10.6, 10.8, WING_FRONT - 1.2), { Kind = "Hanging" })
		-- red wing roof (ridge along X) and a lantern turret by the gable
		local wingRoof = at(s * 15, WING_EAVE, WING_ROOF_Z)
		Style.gableRoof(m, wingRoof, 11.2, WING_ROOF_DEPTH, WING_ROOF_H, { Rows = 3 })
		roofSeams(wingRoof, 11.2, WING_ROOF_DEPTH, WING_ROOF_H, { -1 }, 3)
		-- timber infill in the outer gable end (faces sideways, inset from the roof edge)
		local infillHalf = WING_ROOF_DEPTH / 2 - 2.2
		gableInfill(
			at(s * 20.65, WING_EAVE, WING_ROOF_Z) * CFrame.Angles(0, -s * math.pi / 2, 0),
			infillHalf,
			infillHalf * WING_ROOF_H / (WING_ROOF_DEPTH / 2)
		)
		Style.lantern(m, at(s * 11.6, wingRoofY(-7) - 0.4, -7), { Kind = "Pillar", Height = 4 })

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
	-- two lit windows over the entrance, lantern brackets at the corners
	for _, s in { -1, 1 } do
		Style.window(m, at(s * 4.6, 14.6, NAVE_FRONT - 0.45), 2.6, 2.6)
		Style.block(m, at(s * 10.8, 13.3, -14.2), Vector3.new(1, 1, 2.5), C.WoodDark, nil, Style.tiny())
		Style.lantern(m, at(s * 11.2, 12.7, NAVE_FRONT - 1.1), { Kind = "Hanging" })
	end

	-- steep red cross gable (ridge along Z) over the nave
	local navePitch = NAVE_ROOF_H / 10.2
	local naveRoof = at(0, NAVE_EAVE, 1) * CFrame.Angles(0, math.pi / 2, 0)
	Style.gableRoof(m, naveRoof, 33, 20.4, NAVE_ROOF_H, { Rows = 3 })
	roofSeams(naveRoof, 33, 20.4, NAVE_ROOF_H, { -1, 1 }, 7)
	-- dark timber gable infill, inset so a band of red roof frames it
	local infillHalf = 8.7
	local infillH = infillHalf * navePitch
	local gz = NAVE_FRONT - 0.65
	gableInfill(at(0, NAVE_EAVE, gz), infillHalf, infillH)
	Style.block(m, at(0, NAVE_EAVE + 0.3, gz - 0.2), Vector3.new(infillHalf * 2, 0.6, 0.4), C.Wood, nil, Style.tiny())
	-- stone roundel (a diamond) with the glowing crossed hammers at the apex
	local ry = GreatForge.RoundelY
	Style.block(m, at(0, ry, gz - 0.3) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(4.2, 4.2, 0.4), C.StoneLight, nil, Style.tiny())
	Style.block(m, at(0, ry, gz - 0.5) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(3.4, 3.4, 0.3), C.SignBoard, nil, Style.tiny())
	Style.icon(m, at(0, ry, gz - 0.85), "CrossedHammers", 3.6, C.Gold, NEON)

	------------------------------------------------------------ interior (seen through the entrance)
	-- the big furnace on the back wall (ForgeGlow pulses on the client)
	local glow = Style.block(m, at(0, 6, 7.8), Vector3.new(10, 5, 0.3), C.Molten, NEON, Style.tiny())
	glow.Name = "ForgeGlow"
	Style.block(m, at(0, 2.5, 6.4), Vector3.new(12, 2, 3), C.StoneDark, nil, Style.solid())
	local coals = Style.block(m, at(0, 3.65, 6.4), Vector3.new(10.4, 0.3, 2.2), C.Ember, NEON, Style.tiny())
	coals.Name = "HearthCoals"
	Style.emitter(coals, "Embers", C.Ember, 5)
	Style.block(m, at(0, 10, 6.3), Vector3.new(13, 3, 3.4), C.StoneDark)
	-- the open fire pit in the middle of the hall (seen from above through the door)
	Style.block(m, at(0, PLINTH_TOP + 0.6, -3), Vector3.new(5, 1.2, 3.8), C.StoneDark, nil, Style.solid())
	local pit = Style.block(m, at(0, PLINTH_TOP + 1.3, -3), Vector3.new(4.2, 0.25, 3), C.Ember, NEON, Style.tiny())
	pit.Name = "FirePit"
	Style.light(pit, C.Fire, 36, 2)
	Style.emitter(pit, "Fire", C.Fire, 12)
	for _, s in { -1, 1 } do
		-- furnace with an Ember mouth and an iron flue
		Style.block(m, at(s * 5.2, 4, 2.5), Vector3.new(3.4, 5, 3.4), Style.vary(C.StoneDark, rng, 0.04), nil, Style.solid())
		Style.block(m, at(s * 5.2, 3.4, 0.7), Vector3.new(2, 1.6, 0.25), C.Ember, NEON, Style.tiny())
		Style.block(m, at(s * 5.2, 9, 2.5), Vector3.new(1.2, 5, 1.2), C.Iron, nil, Style.tiny())
		-- anvil on a stump
		Style.block(m, at(s * 3.4, PLINTH_TOP + 0.9, -8.5), Vector3.new(1.4, 1.8, 1.4), C.WoodDark, nil, Style.solid())
		Style.block(m, at(s * 3.4, PLINTH_TOP + 2.2, -8.5), Vector3.new(1.1, 0.8, 2.6), C.IronLight, METAL, Style.tiny())
		-- hanging chain
		Style.block(m, at(s * 3.6, 9.7, -4), Vector3.new(0.3, 3.6, 0.3), C.Iron, METAL, Style.tiny())
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
	for _, s in { -1, 1 } do
		Style.block(m, at(s * 13.6, PLINTH_TOP + 0.8, -15.6), Vector3.new(2, 1.6, 2), C.StoneDark, nil, Style.solid())
		Style.block(m, at(s * 13.6, PLINTH_TOP + 1.9, -15.6), Vector3.new(2.6, 0.6, 2.6), C.Iron, nil, Style.tiny())
		local fire = Style.block(m, at(s * 13.6, PLINTH_TOP + 2.25, -15.6), Vector3.new(2, 0.3, 2), C.Ember, NEON, Style.tiny())
		fire.Name = "BrazierCoals"
		Style.emitter(fire, "Fire", C.Fire, 10)
		Style.crate(m, at(s * 17.2, PLINTH_TOP, -15.4), rng, 2.2)
		Style.barrel(m, at(s * 19.6, PLINTH_TOP, -15.2).Position, rng)
	end
end

return GreatForge
