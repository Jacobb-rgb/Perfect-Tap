--[[
	ROCK SCANNER: the Ore Codex of the 30 ores, at the end of the ToScanner
	path. A stone platform with violet neon edges, a terminal cabinet with
	a blue screen (Model tag OreCodex, PrimaryPart = the cabinet), a cyan
	neon scanner ring in an iron casing with a sample rock and a scan line,
	sample rocks on display plates and the ROCK SCANNER sign with a target
	icon. One blue PointLight.
	Local frame: 12 wide, 10 tall, 10 deep, front = -Z (south-west).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

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

	-- platform with violet neon edges
	Style.block(m, at(0, 0.3, 0), Vector3.new(12, 0.6, 10), Style.vary(C.StoneDark, rng, 0.03), nil, Style.solid())
	Style.block(m, at(0, 0.8, 0), Vector3.new(11, 0.4, 9), Style.vary(C.Stone, rng, 0.03), nil, Style.solid())
	for _, side in { -1, 1 } do
		Kit.glow(m, at(0, TOP, side * 4.55), Vector3.new(11.1, 0.16, 0.16), C.CrystalViolet)
		Kit.glow(m, at(side * 5.55, TOP, 0), Vector3.new(0.16, 0.16, 9.1), C.CrystalViolet)
	end

	-- the Ore Codex terminal (viewer's left): iron cabinet, slanted desk, blue screen
	local terminal = Style.model("Terminal", m)
	local tx, tz = 3.1, 1.3
	local cabinet = Style.block(terminal, at(tx, TOP + 3.0, tz), Vector3.new(4, 6, 2.5), C.Iron, nil, Style.solid())
	cabinet.Name = "Cabinet"
	Kit.bit(terminal, at(tx, TOP + 6.2, tz), Vector3.new(4.2, 0.4, 2.7), C.IronLight)
	local front = tz - 1.25
	Kit.bit(terminal, at(tx, TOP + 4.4, front - 0.03), Vector3.new(3.4, 2.5, 0.06), Kit.Dark)
	local screen = Kit.glow(terminal, at(tx, TOP + 4.4, front - 0.08), Vector3.new(3.0, 2.1, 0.06), C.CrystalBlue)
	screen.Name = "Screen"
	Kit.bit(terminal, at(tx, TOP + 5.95, front - 0.05), Vector3.new(2.4, 0.4, 0.08), C.Brass)
	Geo.wedge(terminal, at(tx, TOP + 2.3, front - 0.7), Vector3.new(4, 0.9, 1.4), C.IronLight, Kit.SMOOTH, Style.decor())
	for i, color in { C.CrystalCyan, C.LeafYellow, C.AwningRed } do
		Kit.glow(terminal, at(tx - 1.6 + i * 0.8, TOP + 2.42, front - 0.6) * CFrame.Angles(-0.57, 0, 0), Vector3.new(0.4, 0.12, 0.4), color)
	end
	for _, side in { -1, 1 } do
		Kit.bit(terminal, at(tx + side * 2.02, TOP + 1.0, tz), Vector3.new(0.06, 0.5, 2.5), C.Hazard)
	end
	terminal.PrimaryPart = cabinet
	Kit.tag(terminal, "OreCodex")

	-- the scanner ring (viewer's right): iron casing, cyan neon octagon, sample rock, scan line
	local rx, rz = -2.5, 0.9
	local apothem = 2.9 -- a big glowing blue frame that reads from the hero camera
	local ringY = TOP + apothem + 0.8
	local center = at(rx, ringY, rz)
	local ring: { BasePart } = {}
	for k = 0, 7 do
		local a = k * math.pi / 4
		local seg = center * CFrame.Angles(0, 0, a) * CFrame.new(0, -apothem, 0)
		table.insert(ring, Kit.glow(m, seg, Vector3.new(2.45, 0.55, 0.6), C.GlowEdge))
		Kit.block(
			m,
			center * CFrame.Angles(0, 0, a) * CFrame.new(0, -apothem - 0.45, 0.15),
			Vector3.new(2.85, 0.5, 0.75),
			C.Iron,
			nil,
			Style.decor()
		)
	end
	for _, side in { -1, 1 } do
		Style.block(m, at(rx + side * 1.3, TOP + 0.3, rz), Vector3.new(0.9, 0.6, 1.4), C.IronLight)
	end
	Kit.bit(m, at(rx, ringY - apothem + 0.38, rz), Vector3.new(1.0, 0.3, 0.8), C.Iron)
	sampleRock(m, at(rx, ringY - apothem + 0.5, rz), 1.4, C.CrystalPurple, rng)
	Kit.block(m, at(rx, ringY - 0.6, rz), Vector3.new(5.8, 0.1, 0.4), C.CrystalCyan, Kit.NEON, Style.tiny({ Transparency = 0.35 }))
	local topSeg = ring[5]
	Style.light(topSeg, C.CrystalBlue, 14, 1.5)

	-- sample rocks on display plates along the front
	for i, ore in { C.Copper, C.Gold, C.CrystalBlue } do
		local x = -4.4 + (i - 1) * 1.9
		local plate = at(x, TOP, -3.3)
		Kit.bit(m, plate * CFrame.new(0, 0.1, 0), Vector3.new(1.6, 0.2, 1.6), C.IronLight)
		sampleRock(m, plate * CFrame.new(0, 0.2, 0), rng:range(1.0, 1.3), ore, rng)
	end

	-- ROCK SCANNER sign with a target icon on two posts at the back
	local sz = 3.9
	for _, x in { -5.1, 5.1 } do
		Style.block(m, at(x, (TOP + 9.6) / 2, sz), Vector3.new(0.7, 9.6 - TOP, 0.7), C.WoodDark)
	end
	Kit.bit(m, at(0, 9.8, sz), Vector3.new(10.8, 0.4, 0.5), C.WoodDark)
	Style.sign(m, at(-1.25, 8.55, sz - 0.55), "ROCK SCANNER", 6.9, 2.2, { Kind = "Stone", Depth = 0.4 })
	local iconBoard = at(3.45, 8.55, sz - 0.55)
	Style.block(m, iconBoard, Vector3.new(2.4, 2.4, 0.4), C.StoneDeep)
	Style.icon(m, iconBoard * CFrame.new(0, 0, -0.4), "Target", 2.0, C.SignText)
end

return Scanner
