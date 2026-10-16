--[[
	ForgeMountain: the dark stepped voxel massif behind the Great Forge
	- LOBBY_PLAN 6.2 item 2, concept: docs/art/lobby_concept.webp.

	The massif is a grid of voxel stone columns in four depth bands:
	  B1  z -242..-258  tier 1, y 22..~56, front face right above the quarry
	  B2  z -258..-275  tier 2, up to ~90, with lower front steps
	  B3  z -275..-300  tier 3 (x 20..96) / back fill elsewhere
	  B4  z -300..-340  tier 3 summit (the Beacon column is 104 high)
	Over the caves (x -74..74) columns start at y 22 (the cave roof); outside
	they reach down to y -20. The B1 band leaves the DEPTHS portal ledge
	at x -22..17 (top < 28) and the ForgeWorks deck (x 17..51) open.
	Decoration: grass ledges with trees, crystal clusters (two lit), a
	cascade from the summit toward ForgeWorks, the west cascade feeding
	QuarryFallsWest, a zig-zag timber walkway with ladders, a cart track with
	an ore cart under the crane, lanterns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

local Massif = {}

Massif.FrontZ = -242
Massif.Bands = { B1 = { -242, -258 }, B2 = { -258, -275 }, B3 = { -275, -300 }, B4 = { -300, -340 } }
-- Fixed column heights other Backdrop pieces rely on (top of the stone; grass adds 0.8).
Massif.WestNotch = { X0 = -50, X1 = -38, Top = 44 } -- B1: QuarryFallsWest pours from here
Massif.WestCascade = { X0 = -50, X1 = -38, Top = 80 } -- B2 above the notch
Massif.WorksCascade = { X0 = 40, X1 = 48, Top = 80, Summit = 102 } -- B2 / B3 behind ForgeWorks
Massif.CraneLedge = { X0 = 96, X1 = 118, Top = 64 } -- B2 (the Crane stands here)
Massif.CartLedge = { X0 = 66, X1 = 118, Top = 48 } -- B1 (cart track)
Massif.EastFall = { X0 = 122, X1 = 134, Top = 84, Pool = 52 } -- B2 -> B1
Massif.Peak = { X0 = 52, X1 = 68, Top = 104 } -- B3 + B4 (the Beacon stands here)
Massif.PortalLedge = { X0 = -22, X1 = 17, Top = 27 } -- B1 over the DEPTHS portal (< 28 with grass)
Massif.WorksDeck = { X0 = 17, X1 = 51 } -- B1 left to ForgeWorks
Massif.WorksBackZ = -259.5 -- B2 front face behind ForgeWorks

local X_MIN, X_MAX = -80, 162
local CAVE_HALF = 74
local CAVE_ROOF = 22

type Column = { x0: number, x1: number, z0: number, z1: number, top: number, band: string }

local function within(x0: number, x1: number, range: { X0: number, X1: number }): boolean
	return x0 >= range.X0 - 0.01 and x1 <= range.X1 + 0.01
end

local function bottomFor(x0: number, x1: number): number
	if x1 > -CAVE_HALF + 0.01 and x0 < CAVE_HALF - 0.01 then
		return CAVE_ROOF
	end
	return -20
end

local function shade(rng: Rng.Rng): Color3
	local r = rng:next()
	if r < 0.7 then
		return C.StoneDeep
	elseif r < 0.95 then
		return C.StoneDark
	end
	return C.Stone:Lerp(C.StoneDark, 0.5)
end

function Massif.build(parent: Instance, rng: Rng.Rng): Model
	local m = Kit.piece(parent, "ForgeMountain")
	local rock = Style.model("Rock", m)
	local decor = Style.model("Ledges", m)
	local columns: { Column } = {}
	local south = Vector3.new(0, 0, 1)

	local function column(x0: number, x1: number, z0: number, z1: number, top: number, band: string, cap: string?, accents: number?)
		Kit.column(rock, x0, z0, x1, z1, bottomFor(x0, x1), top, rng, {
			Color = shade(rng),
			Cap = cap or "Grass",
			Band = band ~= "B3" and band ~= "B4",
			Front = if (accents or 0) > 0 then south else nil,
			Accents = accents,
		})
		table.insert(columns, { x0 = x0, x1 = x1, z0 = math.max(z0, z1), z1 = math.min(z0, z1), top = top, band = band })
	end

	---------------------------------------------------------------- B1 (tier 1)
	local b1Breaks = { -74, -50, -38, -22, 17, 51, 66, 74, 118, 122, 134, 140 }
	for _, span in Kit.partition(X_MIN, X_MAX, b1Breaks, 9, 13, rng) do
		local x0, x1 = span[1], span[2]
		local front = Massif.FrontZ + math.floor(rng:range(-1.5, 0.6) * 2) / 2
		local back = Massif.Bands.B1[2] - 1.5
		if within(x0, x1, Massif.PortalLedge) then
			column(x0, x1, Massif.FrontZ, back, Massif.PortalLedge.Top, "B1", "Grass", 0)
		elseif within(x0, x1, Massif.WorksDeck) then
			-- left open: ForgeWorks builds its deck here
		else
			local top = math.floor(rng:range(48, 58))
			if within(x0, x1, Massif.WestNotch) then
				top = Massif.WestNotch.Top
			elseif within(x0, x1, Massif.CartLedge) then
				top = Massif.CartLedge.Top
			elseif within(x0, x1, Massif.EastFall) then
				top = Massif.EastFall.Pool
			end
			column(x0, x1, front, back, top, "B1", "Grass", if x1 - x0 > 6 then 2 else 1)
			-- a lower step in front of some columns (stepped base)
			local free = not within(x0, x1, Massif.WestNotch) and not within(x0, x1, Massif.CartLedge)
			if free and x1 - x0 > 6 and rng:chance(0.35) then
				local stepTop = math.floor(rng:range(30, 40))
				column(x0 + 1, x1 - 1, front + math.floor(rng:range(3, 5)), front - 1, stepTop, "B1s", "Grass", 0)
			end
		end
	end

	---------------------------------------------------------------- B2 (tier 2)
	local b2Breaks = { -74, -50, -38, -22, 17, 40, 48, 51, 74, 96, 118, 122, 134, 140 }
	for _, span in Kit.partition(X_MIN, X_MAX, b2Breaks, 10, 14, rng) do
		local x0, x1 = span[1], span[2]
		local front = Massif.Bands.B2[1] + math.floor(rng:range(-2, 2) * 2) / 2
		if x0 >= Massif.WorksDeck.X0 - 0.01 and x1 <= Massif.WorksDeck.X1 + 0.01 then
			front = Massif.WorksBackZ
		end
		local back = Massif.Bands.B2[2] - 1.5
		local mid = (x0 + x1) / 2
		local top: number
		local fixed = true
		if within(x0, x1, Massif.WestCascade) then
			top = Massif.WestCascade.Top
		elseif within(x0, x1, Massif.WorksCascade) then
			top = Massif.WorksCascade.Top
		elseif within(x0, x1, Massif.CraneLedge) then
			top = Massif.CraneLedge.Top
			back = Massif.Bands.B3[1] - 6 -- the crane's counter-jib swings over B3
		elseif within(x0, x1, Massif.EastFall) then
			top = Massif.EastFall.Top
		else
			fixed = false
			if mid < -50 then
				top = math.floor(rng:range(62, 70))
			elseif mid > 140 then
				top = math.floor(rng:range(62, 72))
			else
				top = math.floor(rng:range(78, 92))
			end
		end
		if not fixed and x1 - x0 > 6 and rng:chance(0.45) then
			-- front step: a lower block, the high part set back behind it
			local stepDepth = math.floor(rng:range(5, 8))
			local stepTop = math.floor(top - rng:range(12, 22))
			column(x0, x1, front, front - stepDepth - 0.5, stepTop, "B2s", "Grass", 1)
			column(x0, x1, front - stepDepth, back, top, "B2", "Grass", 0)
		else
			column(x0, x1, front, back, top, "B2", "Grass", if fixed then 0 else 1)
		end
	end

	---------------------------------------------------------------- B3 + B4 (tier 3 and back)
	local t3: { X0: number, X1: number } = { X0 = 20, X1 = 96 }
	for _, span in Kit.partition(t3.X0, t3.X1, { 40, 48, 52, 68 }, 10, 15, rng) do
		local x0, x1 = span[1], span[2]
		local b3Front = Massif.Bands.B3[1] + math.floor(rng:range(-1.5, 1.5) * 2) / 2
		local b3Top: number
		local b4Top: number
		if within(x0, x1, Massif.Peak) then
			b3Top, b4Top = Massif.Peak.Top, Massif.Peak.Top
		elseif within(x0, x1, Massif.WorksCascade) then
			b3Top, b4Top = Massif.WorksCascade.Summit, math.floor(rng:range(108, 114))
		else
			b3Top = math.floor(rng:range(99, 108))
			b4Top = math.floor(rng:range(107, 117))
		end
		local peak = within(x0, x1, Massif.Peak)
		column(x0, x1, b3Front, Massif.Bands.B3[2] - 1, b3Top, "B3", if peak then "None" else "Grass", 0)
		column(x0, x1, Massif.Bands.B4[1], Massif.Bands.B4[2] - 1, b4Top, "B4", if peak then "None" else "Stone", 0)
	end
	local backSpans: { { number } } = {}
	for _, span in Kit.partition(X_MIN, t3.X0, { -74, -50, -22 }, 14, 20, rng) do
		table.insert(backSpans, span)
	end
	for _, span in Kit.partition(t3.X1, X_MAX, { 118, 140 }, 12, 18, rng) do
		table.insert(backSpans, span)
	end
	for _, span in backSpans do
		local x0, x1 = span[1], span[2]
		local mid = (x0 + x1) / 2
		local front = Massif.Bands.B3[1] + math.floor(rng:range(-1.5, 1.5) * 2) / 2
		if within(x0, x1, Massif.CraneLedge) then
			-- low behind the crane, higher at the back
			column(x0, x1, front, Massif.Bands.B4[1], math.floor(rng:range(66, 70)), "B3", "Grass", 0)
			column(x0, x1, Massif.Bands.B4[1] + 1, Massif.Bands.B4[2] - 1, math.floor(rng:range(80, 88)), "B4", "Grass", 0)
		else
			local top: number
			if mid < -50 then
				top = math.floor(rng:range(68, 76))
			elseif mid < t3.X0 then
				top = math.floor(rng:range(88, 96))
			elseif mid < 140 then
				top = math.floor(rng:range(80, 90))
			else
				top = math.floor(rng:range(70, 78))
			end
			column(x0, x1, front, Massif.Bands.B4[2] - 1, top, "B3", "Grass", 0)
		end
	end

	---------------------------------------------------------------- ledge decoration
	-- the frontmost column of a band containing x (nil if none)
	local function at(x: number, band: string): Column?
		local best: Column? = nil
		for _, col in columns do
			if col.band == band and x >= col.x0 and x <= col.x1 then
				if not best or col.z0 > best.z0 then
					best = col
				end
			end
		end
		return best
	end
	local function onTop(x: number, band: string, dz: number?): Vector3?
		local col = at(x, band)
		if not col and (band == "B2s" or band == "B1s") then
			col = at(x, string.sub(band, 1, 2))
		end
		if not col then
			return nil
		end
		local z = (col.z0 + col.z1) / 2 + (dz or 0)
		z = math.clamp(z, col.z1 + 2, col.z0 - 2)
		return Vector3.new(x, col.top + 0.8, z)
	end

	-- warm dots on the faces: little lit windows of old mine tunnels
	local lit = 0
	for _, col in columns do
		local face = col.band == "B1" or col.band == "B2" or col.band == "B2s"
		if face and col.top > 40 and lit < 10 and rng:chance(0.3) then
			local y = rng:range(col.top - 14, col.top - 4)
			local x = rng:range(col.x0 + 1.5, col.x1 - 1.5)
			Style.block(decor, CFrame.new(x, y, col.z0 + 0.3), Vector3.new(1.2, 1.5, 0.5), C.Lamp, Enum.Material.Neon, Style.tiny())
			lit += 1
		end
	end

	-- trees on the ledges (the concept mixes green, yellow, orange, pink, red)
	local trees: { { Kind: string, X: number, Band: string, Scale: number, Dz: number } } = {
		{ Kind = "Green", X = -66, Band = "B1", Scale = 1.15, Dz = 0 },
		{ Kind = "Yellow", X = -29, Band = "B1", Scale = 1.0, Dz = 1 },
		{ Kind = "Orange", X = 58, Band = "B1", Scale = 1.05, Dz = 0 },
		{ Kind = "Green", X = 148, Band = "B1", Scale = 1.2, Dz = 0 },
		{ Kind = "Pink", X = -4, Band = "B2s", Scale = 1.0, Dz = 0 },
		{ Kind = "Green", X = 86, Band = "B2s", Scale = 1.1, Dz = 0 },
		{ Kind = "Red", X = 26, Band = "B3", Scale = 1.0, Dz = 2 },
		{ Kind = "Yellow", X = -36, Band = "B3", Scale = 1.1, Dz = 6 },
		{ Kind = "Green", X = 152, Band = "B2", Scale = 1.0, Dz = 0 },
		{ Kind = "Orange", X = -62, Band = "B2", Scale = 1.0, Dz = 0 },
		{ Kind = "Green", X = 6, Band = "B3", Scale = 1.1, Dz = 4 },
		{ Kind = "Pink", X = 66, Band = "B2s", Scale = 0.95, Dz = 0 },
	}
	for _, t in trees do
		local p = onTop(t.X, t.Band, t.Dz)
		if p then
			Style.tree(decor, CFrame.new(p), t.Kind, rng, t.Scale)
		end
	end

	-- crystal clusters: 4 purple, 3 blue, 1 pink; two carry a light
	local crystals: { { Color: Color3, X: number, Band: string, Size: number, Light: boolean, Dz: number } } = {
		{ Color = C.CrystalPurple, X = 57, Band = "B1", Size = 12, Light = true, Dz = -3 },
		{ Color = C.CrystalBlue, X = 104, Band = "B1", Size = 10, Light = false, Dz = -4 },
		{ Color = C.CrystalPurple, X = -16, Band = "B1", Size = 9, Light = false, Dz = 2 },
		{ Color = C.CrystalBlue, X = 30, Band = "B2", Size = 12, Light = true, Dz = 0 },
		{ Color = C.CrystalPink, X = -60, Band = "B1", Size = 8, Light = false, Dz = 0 },
		{ Color = C.CrystalPurple, X = 80, Band = "B3", Size = 11, Light = false, Dz = 0 },
		{ Color = C.CrystalBlue, X = 145, Band = "B1", Size = 10, Light = false, Dz = 2 },
		{ Color = C.CrystalPurple, X = -70, Band = "B2", Size = 9, Light = false, Dz = 0 },
	}
	for _, c in crystals do
		local p = onTop(c.X, c.Band, c.Dz)
		if p then
			Style.crystalCluster(decor, CFrame.new(p) * CFrame.Angles(0, rng:range(0, 6.28), 0), c.Size, c.Color, rng, {
				Count = 3,
				Light = c.Light,
				Range = 24,
				Brightness = 1.6,
			})
		end
	end

	-- west cascade: from tier 2 down onto the tier-1 notch, a channel to the lip
	do
		local x = (Massif.WestCascade.X0 + Massif.WestCascade.X1) / 2
		local col = at(x, "B2")
		if col then
			local lip = CFrame.lookAt(Vector3.new(x, col.top + 0.4, col.z0 + 0.6), Vector3.new(x, col.top + 0.4, col.z0 + 2))
			Style.waterfall(decor, lip, col.top + 0.4 - (Massif.WestNotch.Top + 0.8), 7, rng, { Mist = false })
			Style.water(
				decor,
				CFrame.new(x, Massif.WestNotch.Top + 1.0, (col.z0 + Massif.FrontZ) / 2),
				Vector3.new(7.4, 0.4, math.abs(col.z0 - Massif.FrontZ) + 1)
			)
		end
	end
	-- summit cascade: tier 3 down onto tier 2 behind ForgeWorks (the works'
	-- own fall continues it down to the deck)
	do
		local x = (Massif.WorksCascade.X0 + Massif.WorksCascade.X1) / 2
		local col = at(x, "B3")
		local below = at(x, "B2")
		if col and below then
			local lip = CFrame.lookAt(Vector3.new(x, col.top + 0.4, col.z0 + 0.6), Vector3.new(x, col.top + 0.4, col.z0 + 2))
			Style.waterfall(decor, lip, col.top + 0.4 - (below.top + 0.8), 6, rng, { Mist = false })
			Style.water(
				decor,
				CFrame.new(x, below.top + 1.0, (col.z0 + below.z0) / 2),
				Vector3.new(6, 0.4, math.abs(col.z0 - below.z0) + 1)
			)
		end
	end
	-- east fall: tier 2 into a pool on tier 1
	do
		local x = (Massif.EastFall.X0 + Massif.EastFall.X1) / 2
		local col = at(x, "B2")
		local pool = at(x, "B1")
		if col and pool then
			local lip = CFrame.lookAt(Vector3.new(x, col.top + 0.4, col.z0 + 0.6), Vector3.new(x, col.top + 0.4, col.z0 + 2))
			Style.waterfall(decor, lip, col.top + 0.4 - (pool.top + 0.8), 6.5, rng, { Mist = false })
			local center = Vector3.new(x, pool.top + 1.0, (pool.z0 + pool.z1) / 2 - 1)
			Style.water(decor, CFrame.new(center), Vector3.new(9, 0.4, 9))
			for _, off in { Vector3.new(-5, 0, 0), Vector3.new(5, 0, 0), Vector3.new(0, 0, 5) } do
				local size = if off.X ~= 0 then Vector3.new(1.4, 1.2, 10) else Vector3.new(11, 1.2, 1.4)
				Style.block(
					decor,
					CFrame.new(center + off + Vector3.new(0, 0.2, 0)),
					size,
					Style.vary(C.Stone, rng, 0.05),
					nil,
					Style.solid()
				)
			end
		end
	end

	---------------------------------------------------------------- timber walkway (tier 1, west of the portal)
	do
		local wz = Massif.FrontZ + 1.2 -- deck center, in front of the tier-1 face
		local function deck(x0: number, x1: number, y: number)
			Kit.box(
				decor,
				Vector3.new(x0, y - 0.5, wz - 1.4),
				Vector3.new(x1, y, wz + 1.4),
				Style.vary(C.Plank, rng, 0.04),
				nil,
				Style.solid()
			)
			local n = math.max(1, math.floor((x1 - x0) / 8))
			for i = 0, n do
				local x = x0 + (x1 - x0) * i / n
				-- bracket strut from the cliff face under the deck
				Kit.beam(decor, Vector3.new(x, y - 3.2, Massif.FrontZ), Vector3.new(x, y - 0.5, wz + 1.2), 0.5, C.WoodDark)
			end
			Kit.railing(decor, Vector3.new(x0, y, wz + 1.25), Vector3.new(x1, y, wz + 1.25), 2.2, 6)
		end
		deck(-37, -24, 32)
		deck(-72, -37, 38)
		Kit.ladder(decor, CFrame.new(-25, 26, wz + 1.6), 6, 1.8, 2.2)
		Kit.ladder(decor, CFrame.new(-36, 32, wz + 1.6), 6, 1.8, 2.2)
		local westTop = at(-70, "B1")
		if westTop then
			Kit.ladder(decor, CFrame.new(-70.5, 38, wz + 1.6), westTop.top + 0.8 - 38, 1.8, 2.2)
		end
		-- lanterns hanging from arms out of the cliff face
		for _, spot in { Vector3.new(-30, 37.5, 0), Vector3.new(-58, 43.5, 0) } do
			local hook = Vector3.new(spot.X, spot.Y, wz + 1.0)
			Kit.beam(decor, Vector3.new(spot.X, spot.Y, Massif.FrontZ), hook + Vector3.new(0, 0, 0.3), 0.4, C.WoodDark)
			Style.lantern(decor, CFrame.new(hook), { Kind = "Hanging" })
		end
	end

	---------------------------------------------------------------- cart track on the cart ledge
	do
		local y = Massif.CartLedge.Top + 0.8
		local z = -251
		local x0, x1 = Massif.CartLedge.X0 + 4, Massif.CartLedge.X1 - 3
		Style.rails(decor, Vector3.new(x0, y, z), Vector3.new(x1, y, z), { SleeperEvery = 3 })
		Style.mineCart(decor, CFrame.lookAt(Vector3.new(84, y, z), Vector3.new(90, y, z)), rng, { Load = "Ore" })
		-- buffer stop
		Kit.box(decor, Vector3.new(x1 - 0.6, y, z - 2.2), Vector3.new(x1 + 0.4, y + 2.4, z - 1.4), C.WoodDark, nil, Style.decor())
		Kit.box(decor, Vector3.new(x1 - 0.6, y, z + 1.4), Vector3.new(x1 + 0.4, y + 2.4, z + 2.2), C.WoodDark, nil, Style.decor())
		Kit.box(decor, Vector3.new(x1 - 0.9, y + 1.3, z - 2.4), Vector3.new(x1 + 0.1, y + 2.3, z + 2.4), C.Hazard, nil, Style.tiny())
		Kit.railing(decor, Vector3.new(x0 - 2, y, Massif.FrontZ - 0.8), Vector3.new(x1 + 1, y, Massif.FrontZ - 0.8), 2.4, 7)
		Style.lantern(decor, CFrame.new(x0 - 1, y, z + 4), { Kind = "Post", Height = 6 })
		Style.lantern(decor, CFrame.new(100, y, z + 4), { Kind = "Post", Height = 6 })
		Style.crate(decor, CFrame.new(x0 + 2, y, z - 4), rng, 2.4)
	end

	Style.streaming(m, "Lod")
	return m
end

return Massif
