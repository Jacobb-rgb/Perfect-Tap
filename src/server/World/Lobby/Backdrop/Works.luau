--[[
	ForgeWorks, Crane and Beacon (LOBBY_PLAN 6.2 items 4, 8, 9).

	ForgeWorks sits on the cave roof right of the DEPTHS portal: a stone and
	iron block house with lit windows (no name board: "The Forge" is another
	game's title, owner 2026-10-20), a lattice derrick with a red beacon and the PWR board, an
	ore conveyor and chute down to the quarry floor, flanged pipes, and the
	lower step of the summit cascade feeding the sluice of QuarryFallsEast.
	The Crane stands on the massif's crane ledge, its jib over the cart track;
	the Beacon tower stands on the peak column.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Massif = require(script.Parent.Massif)

local C = Style.C
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

local Works = {}

-- rotation part of a frame
local function rot(cf: CFrame): CFrame
	return cf - cf.Position
end

local SOUTH = Vector3.new(0, 0, 1)
local DECK = 27 -- ForgeWorks deck top (the cave roof is at 26)

Works.House = { Min = Vector3.new(20, DECK, -256), Max = Vector3.new(34, DECK + 10, -246) }
Works.Sluice = { X0 = 40.6, X1 = 47.4, Z0 = -244.4, Z1 = -238.6, Top = 31.6 }

function Works.buildForgeWorks(parent: Instance, rng: Rng.Rng): Model
	local m = Kit.piece(parent, "ForgeWorks")
	-- deck on the cave roof
	Kit.box(
		m,
		Vector3.new(17, 25.6, Massif.WorksBackZ),
		Vector3.new(51, DECK, -241),
		Style.vary(C.StoneDark, rng, 0.04),
		nil,
		Style.solid()
	)
	Kit.box(
		m,
		Vector3.new(17, DECK - 0.6, -241.4),
		Vector3.new(51, DECK + 0.2, -240.6),
		Style.vary(C.StoneLight, rng, 0.04),
		nil,
		Style.tiny()
	)

	---------------------------------------------------------------- block house
	local h = Works.House
	Kit.box(m, h.Min, Vector3.new(h.Max.X, DECK + 5, h.Max.Z), Style.vary(C.Stone, rng, 0.04), nil, Style.solid())
	Kit.box(
		m,
		Vector3.new(h.Min.X + 0.2, DECK + 5, h.Min.Z + 0.2),
		Vector3.new(h.Max.X - 0.2, h.Max.Y, h.Max.Z - 0.2),
		C.Iron,
		nil,
		Style.solid()
	)
	Kit.box(
		m,
		Vector3.new(h.Min.X, DECK + 4.8, h.Max.Z - 0.1),
		Vector3.new(h.Max.X, DECK + 5.3, h.Max.Z + 0.15),
		C.Hazard,
		nil,
		Style.tiny()
	)
	for _, cx in { h.Min.X, h.Max.X } do
		for _, cz in { h.Min.Z, h.Max.Z } do
			Kit.box(
				m,
				Vector3.new(cx - 0.4, DECK, cz - 0.4),
				Vector3.new(cx + 0.4, h.Max.Y + 0.2, cz + 0.4),
				C.IronLight,
				METAL,
				Style.tiny()
			)
		end
	end
	Kit.box(
		m,
		Vector3.new(h.Min.X - 0.5, h.Max.Y, h.Min.Z - 0.5),
		Vector3.new(h.Max.X + 0.5, h.Max.Y + 0.8, h.Max.Z + 0.5),
		C.Iron,
		nil,
		Style.solid()
	)
	Kit.box(
		m,
		Vector3.new(h.Min.X + 2, h.Max.Y + 0.8, h.Min.Z + 2),
		Vector3.new(h.Max.X - 2, h.Max.Y + 2, h.Max.Z - 2),
		C.IronLight,
		nil,
		Style.solid()
	)
	-- door (warm glow, the works' one light) and three windows
	Kit.box(m, Vector3.new(25.4, DECK, h.Max.Z - 0.05), Vector3.new(28.6, DECK + 4.6, h.Max.Z + 0.25), C.WoodDark, nil, Style.tiny())
	local door = Kit.box(m, Vector3.new(26, DECK, h.Max.Z + 0.2), Vector3.new(28, DECK + 4, h.Max.Z + 0.35), C.Molten, NEON, Style.tiny())
	door.Name = "WorksDoor"
	Style.light(door, C.Lamp, 18, 1.4)
	for _, x in { 22.6, 27, 31.4 } do
		Style.window(m, Kit.facing(Vector3.new(x, DECK + 7.6, h.Max.Z + 0.05), SOUTH), 2.4, 2.2, { Frame = C.IronLight })
	end

	---------------------------------------------------------------- derrick with beacon and the PWR board
	local derrickBase = CFrame.new(31, h.Max.Y + 0.8, -251.5)
	local top = Kit.lattice(m, derrickBase, 4, 1.6, 19, 4.75, C.Iron, { Thickness = 0.45, Faces = { { 3, 4 }, { 4, 1 } } })
	Style.block(m, top * CFrame.new(0, 0.3, 0), Vector3.new(2.2, 0.6, 2.2), C.IronLight, METAL, Style.tiny())
	local beacon = Style.block(m, top * CFrame.new(0, 1.2, 0), Vector3.new(1.2, 1.2, 1.2), C.FlowerRed, NEON, Style.tiny())
	beacon.Name = "WorksBeacon"
	local pwrY = 50.6
	Style.sign(m, Kit.facing(Vector3.new(30.4, pwrY, -249.6), SOUTH), "PWR", 4.8, 2.4, { Kind = "Glow" })
	Kit.box(m, Vector3.new(33.2, pwrY - 1.8, -250.1), Vector3.new(34.4, pwrY + 1.8, -249.3), C.GlowBoard, nil, Style.tiny())
	Kit.box(m, Vector3.new(33.5, pwrY - 1.5, -249.4), Vector3.new(34.1, pwrY + 0.9, -249.2), C.Fire, NEON, Style.tiny())

	---------------------------------------------------------------- summit cascade, channel and sluice
	local cascadeX = (Massif.WorksCascade.X0 + Massif.WorksCascade.X1) / 2
	local lipY = Massif.WorksCascade.Top + 1.0
	local lip = CFrame.lookAt(Vector3.new(cascadeX, lipY, Massif.WorksBackZ + 0.6), Vector3.new(cascadeX, lipY, Massif.WorksBackZ + 2))
	Style.waterfall(Style.model("Cascade", m), lip, lipY - (DECK + 0.4), 6, rng, { Mist = false })
	local s = Works.Sluice
	Style.water(m, CFrame.new(cascadeX, DECK + 0.2, (Massif.WorksBackZ + s.Z0) / 2), Vector3.new(5.2, 0.4, s.Z0 - Massif.WorksBackZ))
	for _, side in { -1, 1 } do
		Kit.box(
			m,
			Vector3.new(cascadeX + side * 2.6, DECK, Massif.WorksBackZ),
			Vector3.new(cascadeX + side * 3.3, DECK + 0.9, s.Z0),
			Style.vary(C.Stone, rng, 0.05),
			nil,
			Style.tiny()
		)
	end
	Kit.box(m, Vector3.new(s.X0, DECK, s.Z0), Vector3.new(s.X1, s.Top, s.Z1), Style.vary(C.Stone, rng, 0.04), nil, Style.solid())
	Kit.box(
		m,
		Vector3.new(s.X0 - 0.1, s.Top - 1.2, s.Z0 - 0.1),
		Vector3.new(s.X1 + 0.1, s.Top - 0.7, s.Z1 + 0.1),
		C.Hazard,
		nil,
		Style.tiny()
	)
	Style.water(m, CFrame.new((s.X0 + s.X1) / 2, s.Top - 0.1, (s.Z0 + s.Z1) / 2), Vector3.new(s.X1 - s.X0 - 1, 0.4, s.Z1 - s.Z0 - 1))

	---------------------------------------------------------------- flanged pipes
	Kit.pipe(m, Vector3.new(22.6, h.Max.Y + 0.8, -253), Vector3.new(22.6, h.Max.Y + 7.5, -253), 1.4, C.Copper, { "b" })
	Kit.pipe(m, Vector3.new(h.Max.X + 0.2, DECK + 3.4, -250), Vector3.new(cascadeX - 3.4, DECK + 3.4, -250), 1.2, C.Copper, { "a", "b" })

	---------------------------------------------------------------- ore conveyor and chute down to the quarry floor
	local chute = Style.model("Chute", m)
	local cx = 24
	local beltA, beltB = Vector3.new(cx, DECK, h.Max.Z + 0.6), Vector3.new(cx, DECK, -232.6)
	Kit.box(chute, Vector3.new(cx - 1.4, DECK - 1.4, beltB.Z), Vector3.new(cx + 1.4, DECK + 0.8, beltA.Z), C.Iron, nil, Style.solid())
	Kit.box(chute, Vector3.new(cx - 1.1, DECK + 0.8, beltB.Z), Vector3.new(cx + 1.1, DECK + 1.0, beltA.Z), C.HazardDark, nil, Style.tiny())
	for _, side in { -1, 1 } do
		Kit.box(
			chute,
			Vector3.new(cx + side * 1.2, DECK + 0.8, beltB.Z),
			Vector3.new(cx + side * 1.6, DECK + 1.5, beltA.Z),
			C.Hazard,
			nil,
			Style.tiny()
		)
	end
	for _, z in { -243, -237.5 } do
		Style.block(
			chute,
			CFrame.new(cx + rng:range(-0.4, 0.4), DECK + 1.5, z),
			Vector3.new(0.9, 0.8, 0.9),
			C.StoneLight,
			nil,
			Style.tiny()
		)
	end
	local chuteTop = Vector3.new(cx, DECK + 0.6, -232.2)
	local chuteEnd = Vector3.new(cx, -9.2, -220.8)
	Kit.slab(chute, chuteTop, chuteEnd, 3, 0.4, C.Iron, nil, Style.decor())
	for _, side in { -1, 1 } do
		Kit.slab(chute, chuteTop, chuteEnd, 0.4, 1.4, C.Hazard, nil, Style.tiny(), Vector3.new(side * 1.6, 0.6, 0))
	end
	Kit.beam(chute, (chuteTop + chuteEnd) / 2, Vector3.new(cx, 4, -234.5), 0.5, C.Iron)
	Style.crate(chute, CFrame.new(cx, -12, -218.6), rng, 3)
	Style.block(chute, CFrame.new(cx, -8.7, -218.6), Vector3.new(1.4, 1, 1.4), C.StoneLight, nil, Style.tiny())

	---------------------------------------------------------------- props
	Style.crate(m, CFrame.new(48.6, DECK, -255.5), rng, 2.6)
	Style.crate(m, CFrame.new(48.8, DECK + 2.6, -255.4), rng, 1.8)
	Style.barrel(m, Vector3.new(48.5, DECK, -251.5), rng, C.Copper)
	Style.lantern(m, CFrame.new(18.6, DECK, -243.4), { Kind = "Post", Height = 6 })
	return m
end

function Works.buildCrane(parent: Instance, rng: Rng.Rng): Model
	local m, _, frame = Kit.piece(parent, "Crane")
	local base = frame * CFrame.new(0, 0.8, 0) -- on the grass of the crane ledge
	local towerH = 15
	Style.block(m, base * CFrame.new(0, 0.3, 0), Vector3.new(5, 1.2, 5), C.StoneDark, nil, Style.solid())
	local top =
		Kit.lattice(m, base * CFrame.new(0, 0.9, 0), 3, 3, towerH, 5, C.Hazard, { Thickness = 0.45, Faces = { { 1, 2 }, { 4, 1 } } })
	-- turntable and cab
	Style.block(m, top * CFrame.new(0, 0.3, 0), Vector3.new(4, 0.6, 4), C.IronLight, METAL, Style.decor())
	Style.block(m, top * CFrame.new(0.6, 1.8, -1.2), Vector3.new(2.6, 2.4, 2.4), C.Hazard, nil, Style.decor())
	Style.block(m, top * CFrame.new(0.6, 2.1, -2.45), Vector3.new(1.8, 1, 0.12), C.Lamp, NEON, Style.tiny())
	-- jib toward the viewer's right (local -X), counter-jib behind (local +X)
	local jibY = 2.4
	local jibEnd = -20
	local a = (top * CFrame.new(1.2, jibY, 0)).Position
	local b = (top * CFrame.new(jibEnd, jibY, 0)).Position
	local up = Vector3.new(0, 2, 0)
	Kit.beam(m, a + (top.LookVector * 0.7), b + (top.LookVector * 0.7), 0.45, C.Hazard)
	Kit.beam(m, a - (top.LookVector * 0.7), b - (top.LookVector * 0.7), 0.45, C.Hazard)
	Kit.beam(m, a + up, b + up * 0.4, 0.45, C.Hazard)
	local n = 4
	for i = 0, n - 1 do
		local p0 = a + (b - a) * (i / n)
		local p1 = a + (b - a) * ((i + 1) / n)
		local hi0 = p0 + up * (1 - 0.6 * i / n)
		Kit.beam(m, hi0, p1, 0.35, C.Iron)
	end
	local c = (top * CFrame.new(8, jibY, 0)).Position
	Kit.beam(m, a, c, 0.9, C.Iron)
	Style.block(
		m,
		CFrame.new(c - Vector3.new(0, 1.2, 0)) * rot(top) * CFrame.new(-0.8, 0, 0),
		Vector3.new(2.4, 2.4, 2.4),
		C.StoneDark,
		nil,
		Style.decor()
	)
	-- mast and tie cables
	local mastTop = (top * CFrame.new(0, jibY + 7, 0)).Position
	Kit.beam(m, (top * CFrame.new(0, jibY, 0)).Position, mastTop, 0.6, C.Hazard)
	Kit.beam(m, mastTop, b + up * 0.4, 0.18, C.Iron)
	Kit.beam(m, mastTop, c, 0.18, C.Iron)
	-- trolley, cable, hook and the hanging crate
	local trolley = (top * CFrame.new(jibEnd + 4, jibY - 0.6, 0)).Position
	Style.block(m, CFrame.new(trolley) * rot(top), Vector3.new(1.6, 0.8, 1.8), C.Iron, nil, Style.tiny())
	local hook = trolley - Vector3.new(0, 9.5, 0)
	Kit.beam(m, trolley, hook, 0.15, C.Iron)
	Style.block(m, CFrame.new(hook), Vector3.new(0.8, 0.6, 0.8), C.Brass, nil, Style.tiny())
	Style.crate(m, CFrame.new(hook - Vector3.new(0, 3.3, 0)) * rot(top), rng, 3)
	return m
end

function Works.buildBeacon(parent: Instance, rng: Rng.Rng): Model
	local m, piece = Kit.piece(parent, "Beacon")
	local base = CFrame.new(piece.Center)
	Style.block(m, base * CFrame.new(0, 0.6, 0), Vector3.new(6, 1.2, 6), Style.vary(C.StoneLight, rng, 0.04), nil, Style.solid())
	local top =
		Kit.lattice(m, base * CFrame.new(0, 1.2, 0), 4.5, 1.6, 23, 5.75, C.Iron, { Thickness = 0.5, Faces = { { 3, 4 }, { 4, 1 } } })
	Style.block(m, top * CFrame.new(0, 0.2, 0), Vector3.new(2.8, 0.4, 2.8), C.IronLight, METAL, Style.tiny())
	local lamp = Style.block(m, top * CFrame.new(0, 1.1, 0), Vector3.new(1.4, 1.4, 1.4), C.FlowerRed, NEON, Style.tiny())
	lamp.Name = "BeaconLight"
	Style.light(lamp, C.FlowerRed, 30, 2)
	Style.block(m, top * CFrame.new(0, 2, 0), Vector3.new(1.8, 0.4, 1.8), C.Iron, nil, Style.tiny())
	Style.block(m, top * CFrame.new(0, 3.6, 0), Vector3.new(0.25, 2.8, 0.25), C.Iron, nil, Style.tiny())
	return m
end

return Works
