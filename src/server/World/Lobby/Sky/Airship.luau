--[[
	Sky package: the airship of concept v2 (docs/art/lobby_concept_v2.webp,
	top right), cruising over the sea right of the east floating island.

	A long rounded copper envelope (a capsule: a fat cylinder with a ball
	nose, a narrower tail cylinder with a ball end and a brass tail cap),
	a brass nose tip with a lamp, brass ribs around the belly, a red stripe
	along the spine, a row of lit portholes on each flank, a small top
	engine with a glowing exhaust, four tail fins with red/green navigation
	lamps, a stern propeller with a glowing exhaust, two engine pods on
	pylons with propellers and glowing exhausts, and a timber gondola under
	the belly with a row of lit windows on each side and a lit windscreen.

	Tagged Spin with SpinSpeed 0 (it never turns) and a slow bob; Atomic
	streaming, PrimaryPart = the main envelope cylinder. <= 70 parts, no
	lights (neon windows and exhausts glow on their own). Pure builder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- local tones (Style.C has no darker copper)
local CopperDark = rgb(150, 78, 44)
local NavRed = rgb(255, 64, 64)
local NavGreen = rgb(80, 255, 140)

local Airship = {}

-- Where it flies: right of the east floating island, seen from the spawn
-- and the hero camera (not a LobbyLayout piece: it hangs outside the lobby
-- area box, x 244 / z -236, so it never touches a footprint).
Airship.Center = Vector3.new(244, 104, -236)
-- the nose points west: the town sees it three-quarter from the front-left
-- like concept v2 (nose to the left, tail and exhaust to the right)
Airship.Heading = 268
-- the design below is in "ship units" (envelope ~54 long, 14 wide); Scale
-- turns them into studs
Airship.Scale = 1.25
Airship.MaxParts = 70

-- envelope (ship units, the nose toward -Z)
local BODY_D = 14 -- main cylinder diameter
local BODY_LEN = 30 -- main cylinder length (z -15 .. 15)
local TAIL_D = 11 -- tail cylinder diameter
local TAIL_LEN = 8 -- tail cylinder length (z 15 .. 23)

function Airship.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Airship", parent)
	local S = Airship.Scale
	local a = math.rad(Airship.Heading)
	local forward = Vector3.new(math.sin(a), 0, -math.cos(a))
	-- frame: envelope center, LookVector = the nose
	local frame = CFrame.lookAt(Airship.Center, Airship.Center + forward)

	-- ship units -> studs
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x * S, y * S, z * S)
	end
	local function size(x: number, y: number, z: number): Vector3
		return Vector3.new(x * S, y * S, z * S)
	end
	local function box(cf: CFrame, s: Vector3, color: Color3): Part
		return Style.block(m, cf, s, color, nil, Kit.far())
	end
	local function glow(cf: CFrame, s: Vector3, color: Color3, transparency: number?): Part
		return Kit.glow(m, cf, s, color, transparency)
	end
	-- a cylinder along the ship's axis (Roblox cylinders run along X)
	local function drum(z: number, diameter: number, length: number, color: Color3): Part
		return Style.block(
			m,
			at(0, 0, z) * CFrame.Angles(0, math.pi / 2, 0),
			size(length, diameter, diameter),
			color,
			nil,
			Kit.far({ Shape = CYLINDER })
		)
	end
	local function ball(z: number, diameter: number, color: Color3): Part
		return Style.block(m, at(0, 0, z), size(diameter, diameter, diameter), color, nil, Kit.far({ Shape = BALL }))
	end
	-- a propeller: hub + two crossed blades, facing along the ship's axis
	local function propeller(cf: CFrame, span: number)
		box(cf, size(0.9, 0.9, 0.8), C.Iron)
		local twist = rng:range(0, math.pi / 2)
		for k = 0, 1 do
			box(cf * CFrame.Angles(0, 0, twist + k * math.pi / 2), size(0.45, span, 0.25), C.WoodLight)
		end
	end

	-- the envelope: a capsule that narrows into the tail
	local copper = Style.vary(C.Copper, rng, 0.03)
	local body = drum(0, BODY_D, BODY_LEN, copper)
	body.Name = "Envelope"
	ball(-BODY_LEN / 2, BODY_D, copper)
	local tailZ0 = BODY_LEN / 2
	local tailEnd = tailZ0 + TAIL_LEN
	drum(tailZ0 + TAIL_LEN / 2, TAIL_D, TAIL_LEN, Style.vary(CopperDark, rng, 0.03))
	ball(tailEnd, TAIL_D, Style.vary(CopperDark, rng, 0.03))
	drum(tailEnd + TAIL_D / 2 - 0.4, 4, 2.4, C.Brass)
	-- brass nose tip with the lamp
	local noseZ = -BODY_LEN / 2 - BODY_D / 2
	ball(noseZ + 1.2, 4.6, C.Brass)
	glow(at(0, 0, noseZ - 1.15), size(1.6, 1.6, 0.6), C.Lamp)

	-- brass ribs around the belly and over the step into the tail
	for _, rz in { -9, 0, 9 } do
		drum(rz, BODY_D + 0.5, 0.8, C.Brass)
	end
	drum(tailZ0, TAIL_D + 0.6, 1, C.Brass)
	-- red stripe along the spine
	box(at(0, BODY_D / 2, 0), size(1.6, 0.4, BODY_LEN), C.AwningRed)
	-- lit portholes along both flanks
	local portY = 1.6
	local portX = math.sqrt((BODY_D / 2) ^ 2 - portY ^ 2) + 0.05
	for _, side in { -1, 1 } do
		for k = -1, 1 do
			glow(at(side * portX, portY, k * 6 - 2), size(0.3, 1, 1), C.Lamp)
		end
	end
	-- small top engine with a glowing exhaust (concept v2)
	box(at(0, BODY_D / 2 + 0.9, 6), size(2.4, 1.8, 5), C.IronLight)
	glow(at(0, BODY_D / 2 + 0.9, 8.9), size(1.6, 1.2, 0.8), C.Fire, 0.1)

	-- tail fins (top, bottom, sides) on the tail cylinder (a wedge's tall
	-- face is its +Z side: the slope faces forward and up, which sweeps the
	-- top fin's leading edge back)
	local finZ = tailZ0 + TAIL_LEN / 2 + 1
	local finR = TAIL_D / 2
	box(at(0, finR + 2.8, finZ), size(0.6, 6, 7), C.AwningRed)
	Geo.wedge(m, at(0, finR + 2.8, finZ - 5), size(0.6, 6, 3), C.AwningRed, nil, Kit.far())
	box(at(0, -finR - 2.2, finZ + 0.5), size(0.6, 5, 6), C.RoofTrim)
	for _, side in { -1, 1 } do
		box(at(side * (finR + 2.8), 0, finZ), size(6, 0.6, 7), C.AwningRed)
		-- navigation lamps on the fin tips (red to port, green to starboard)
		glow(at(side * (finR + 6.1), 0, finZ + 1), size(0.7, 0.7, 0.7), if side < 0 then NavRed else NavGreen)
	end

	-- stern propeller and the glowing exhaust behind it
	local sternZ = tailEnd + TAIL_D / 2 + 0.8
	propeller(at(0, 0, sternZ + 0.6), 6.5)
	glow(at(0, 0, sternZ + 2.4), size(1.4, 1.4, 2.4), C.Ember, 0.15)

	-- engine pods on pylons, low on both flanks
	for _, side in { -1, 1 } do
		local podX = side * (BODY_D / 2 + 3.2)
		local podY = -3.2
		local podZ = 3
		box(at(side * (BODY_D / 2 + 0.9), -2.2, podZ), size(3.6, 0.6, 2.4), C.Iron)
		box(at(podX, podY, podZ), size(2.8, 2.8, 7), C.IronLight)
		box(at(podX, podY, podZ - 3.9), size(2, 2, 0.8), C.Brass)
		propeller(at(podX, podY, podZ - 4.7), 5)
		glow(at(podX, podY, podZ + 3.9), size(1.6, 1.6, 0.8), C.Fire, 0.1)
	end

	-- gondola under the belly: timber cabin, brass roof trim, iron keel,
	-- slanted windscreen, a row of lit windows on each side
	local gy = -BODY_D / 2 - 2.6
	local gz = -3
	local cabin = box(at(0, gy, gz), size(5, 3.6, 15), Style.vary(C.WoodDark, rng, 0.03))
	cabin.Name = "Gondola"
	box(at(0, gy + 2, gz), size(5.4, 0.5, 15.4), C.Brass)
	box(at(0, gy - 2.1, gz + 0.5), size(3.6, 0.7, 13), C.Iron)
	-- slanted nose: the wedge's slope faces forward and up
	Geo.wedge(m, at(0, gy, gz - 9), size(5, 3.6, 3), Style.vary(C.WoodDark, rng, 0.03), nil, Kit.far())
	-- windscreen glow lying on that slope (upper part)
	local tilt = -math.atan2(3.6, 3)
	glow(at(0, gy, gz - 9) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 0.12 * S, 0.7 * S), size(3.8, 0.2, 2.4), C.Lamp)
	box(at(0, gy - 0.2, gz + 8.4), size(4, 3, 1.8), C.Wood)
	for _, side in { -1, 1 } do
		for k = 0, 3 do
			glow(at(side * 2.55, gy + 0.3, gz - 5.4 + k * 3.6), size(0.2, 1.3, 2.2), C.Lamp)
		end
	end
	-- struts from the cabin roof up into the envelope
	for _, sz in { -6, 3 } do
		box(at(0, gy + 3.5, gz + sz), size(0.6, 2.4, 0.6), C.Iron)
	end

	m.PrimaryPart = body
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", 0)
	m:SetAttribute("BobHeight", 3)
	m:SetAttribute("BobSpeed", 0.35)
	Style.streaming(m, "Atomic")
	return m
end

return Airship
