--[[
	ROCK SCANNER: the Ore Codex of the 30 ores, at the end of the ToScanner
	path, in the concept v2 metal and neon language. A floor-panel platform
	with blue neon edges, a terminal (computer-screen look: cabinet, bezel,
	glowing screen, slanted console with buttons; Model tag OreCodex,
	PrimaryPart = the cabinet), a thick mechanical scanner ring (blue neon
	inner edge, orange studs) standing on clamp feet with a sample rock and
	a scan line, sample rocks on table-display-planet pedestals and the ROCK
	SCANNER sign box with a scan-ring icon on a frame, raised over the ring so
	the words read from the terminal side. One blue PointLight.
	Local frame: 12 wide, 10 tall, 10 deep, front = -Z (south-west).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Scanner = {}

local C = Kit.C

local TOP = 1.0 -- platform top

-- A sample rock with a glowing ore vein. `base` = bottom center.
local function sampleRock(parent: Instance, base: CFrame, size: number, ore: Color3, rng: Rng.Rng)
	Kit.block(
		parent,
		base * CFrame.new(0, size * 0.4, 0) * Geo.randomTilt(rng, 0.25),
		Vector3.new(size, size * 0.8, size * 0.9),
		Style.vary(C.Stone, rng, 0.05),
		nil,
		Style.decor()
	)
	Kit.glow(
		parent,
		base * CFrame.new(size * 0.18, size * 0.62, -size * 0.3) * CFrame.Angles(0.4, 0.5, 0.2),
		Vector3.new(size * 0.35, size * 0.3, size * 0.35),
		ore
	)
end

function Scanner.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("RockScanner")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- floor-panel platform: dark slab, inset plate with corner bolts, neon edges
	Style.block(m, at(0, 0.3, 0), Vector3.new(12, 0.6, 10), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Style.block(m, at(0, 0.8, 0), Vector3.new(11, 0.4, 9), Style.vary(Tech.Metal, rng, 0.03), nil, Style.solid())
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.bit(m, at(sx * 5.0, TOP + 0.06, sz * 4.0), Vector3.new(0.4, 0.14, 0.4), Tech.MetalLight)
		end
	end
	-- the plate's edge tubes in dark channels on its side faces
	for _, side in { -1, 1 } do
		Tech.channel(m, at(0, 0.8, side * 4.66) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), 11.0, 0.26, nil, nil, 0.06)
		Tech.channel(m, at(side * 5.66, 0.8, 0) * CFrame.Angles(0, -side * math.pi / 2, 0), 9.0, 0.26, nil, nil, 0.06)
	end
	Tech.glow(m, at(0, 0.45, -5.02), Vector3.new(11.6, 0.14, 0.08), Tech.Warm)

	-- the Ore Codex terminal (viewer's left): cabinet, bezel, screen, console
	local terminal = Style.model("Terminal", m)
	local tx, tz = 3.1, 1.3
	local cabinet = Style.block(terminal, at(tx, TOP + 2.7, tz), Vector3.new(4, 5.4, 2.5), Tech.Metal, nil, Style.solid())
	cabinet.Name = "Cabinet"
	Kit.bit(terminal, at(tx, TOP + 5.6, tz), Vector3.new(4.3, 0.4, 2.8), Tech.MetalLight)
	Kit.bit(terminal, at(tx, TOP + 0.3, tz), Vector3.new(4.3, 0.6, 2.8), Tech.MetalDark)
	local front = tz - 1.25
	Kit.bit(terminal, at(tx, TOP + 4.0, front - 0.12), Vector3.new(3.6, 2.5, 0.24), Tech.MetalDark)
	local screen = Kit.glow(terminal, at(tx, TOP + 4.0, front - 0.27), Vector3.new(3.0, 1.9, 0.06), Tech.Screen)
	screen.Name = "Screen"
	for i, w in { 2.0, 1.4, 1.7 } do
		Kit.bit(terminal, at(tx + 0.3, TOP + 4.6 - i * 0.42, front - 0.31), Vector3.new(w, 0.16, 0.03), C.GlowText)
	end
	Kit.glow(
		terminal,
		at(tx - 1.0, TOP + 3.75, front - 0.31) * CFrame.Angles(0, 0, math.pi / 4),
		Vector3.new(0.6, 0.6, 0.03),
		C.CrystalPurple
	)
	Geo.wedge(terminal, at(tx, TOP + 2.3, front - 0.7), Vector3.new(4, 0.9, 1.4), Tech.MetalLight, Kit.SMOOTH, Style.decor())
	for i, color in { C.CrystalCyan, C.LeafYellow, C.AwningRed } do
		Kit.glow(terminal, at(tx - 1.6 + i * 0.8, TOP + 2.42, front - 0.6) * CFrame.Angles(-0.57, 0, 0), Vector3.new(0.4, 0.12, 0.4), color)
	end
	Kit.bit(terminal, at(tx, TOP + 1.3, front - 0.04), Vector3.new(4.0, 0.5, 0.1), Tech.Band)
	for _, side in { -1, 1 } do
		Tech.glow(terminal, at(tx + side * 2.0, TOP + 3.0, front - 0.06), Vector3.new(0.3, 4.2, 0.14), Tech.Tube)
	end
	terminal.PrimaryPart = cabinet
	Kit.tag(terminal, "OreCodex")

	-- the scanner ring (viewer's right): a thick mechanical ring standing on
	-- the platform in two clamp feet, low enough that it never covers the
	-- sign from the terminal side
	local rx, rz = -2.4, 1.4
	local ringOut = 3.0
	local ringY = TOP + ringOut / math.cos(math.pi / 8) + 0.05
	local ringCf = at(rx, ringY, rz)
	Tech.ring(m, ringCf, 2.15, ringOut, 8, { Depth = 1.0, Studs = C.Fire, Lip = false })
	local topSeg = Kit.glow(m, ringCf * CFrame.new(0, ringOut + 0.05, 0), Vector3.new(1.6, 0.14, 0.7), Tech.Tube)
	Style.light(topSeg, C.CrystalBlue, 14, 1.5)
	for _, side in { -1, 1 } do
		Style.block(m, at(rx + side * 1.9, TOP + 0.45, rz), Vector3.new(1.2, 0.9, 1.5), Tech.MetalDark, nil, Style.solid())
		Tech.glow(m, at(rx + side * 1.9, TOP + 0.6, rz - 0.77), Vector3.new(0.9, 0.2, 0.06), C.Fire)
	end
	-- sample rock on a little stand inside the ring, and the scan line
	Kit.bit(m, at(rx, ringY - 2.0, rz), Vector3.new(1.0, 0.3, 0.8), Tech.MetalLight)
	sampleRock(m, at(rx, ringY - 1.85, rz), 1.3, C.CrystalPurple, rng)
	Kit.block(m, at(rx, ringY - 0.3, rz - 0.1), Vector3.new(4.0, 0.1, 0.4), C.CrystalCyan, Kit.NEON, Style.tiny({ Transparency = 0.35 }))

	-- sample rocks on table-display-planet pedestals along the front
	for i, ore in { C.Copper, C.Gold, C.CrystalBlue } do
		local x = -4.3 + (i - 1) * 1.9
		local top = Tech.pedestal(m, at(x, TOP, -3.4), 1.6, 0.9)
		sampleRock(m, top, rng:range(0.95, 1.2), ore, rng)
	end

	-- ROCK SCANNER sign box with a scan-ring icon on a frame at the back
	-- (raised over the ring's top: seen from the front at eye height the ring
	-- stays under the letters)
	local sz = 3.9
	local signY, signH = 8.75, 1.7
	local postTop = signY - signH / 2 - 0.55
	for _, x in { -5.1, 5.1 } do
		Style.block(m, at(x, (TOP + postTop) / 2, sz + 0.3), Vector3.new(0.6, postTop - TOP, 0.6), Tech.MetalLight)
		Tech.disc(m, at(x, TOP + 0.5, sz + 0.3).Position, 1.0, 0.9, Tech.Band)
	end
	local _, iconAt = Tech.sign(m, at(0, signY, sz - 0.4), "ROCK SCANNER", 9.4, signH, {
		Icon = 2.0,
		IconLeft = true,
		Margin = 0.35,
		Lip = 0.2,
		Back = true,
	})
	if iconAt then
		-- a scan ring with a crosshair (the machine's octagon ring) in blue neon
		Tech.scanIcon(m, iconAt, 1.65, Tech.Tube)
	end
end

return Scanner
