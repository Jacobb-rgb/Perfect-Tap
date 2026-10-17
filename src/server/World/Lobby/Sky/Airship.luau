--[[
	Sky package: the airship of concept v2 (docs/art/lobby_concept_v2.webp,
	top right): a long tapered dark-bronze cigar cruising over the mountain's
	right shoulder, between the peak and the east floating island, pitched a
	little nose-down like the concept.

	The envelope is a long bronze cylinder with a steel nose (four shrinking
	cylinders and a brass cap with the lamp) and a steel tail (four
	shrinking cylinders into the stern propeller), so the silhouette tapers
	at both ends; brass ribs hide the steps at the nose and the tail and band
	the belly, four thin dark gore strips run along it, two portholes glow on
	each flank. On top a small engine (a cylinder housing with a brass cap
	and a glowing exhaust), at the tail four wedge fins with red/green
	navigation lamps, behind the stern a three-blade propeller and a pink-
	ember exhaust trail. Two engine pods hang on pylons with three-blade
	propellers and glowing exhausts, and under the belly a timber gondola
	with a thin windscreen strip and lit windows.

	Tagged Spin with SpinSpeed 0 (it never turns) and a slow bob. Persistent
	streaming: it hangs ~400 studs from the plaza, right at the 384-stud
	StreamingTargetRadius, so an Atomic model would pop in and out as players
	walk around. PrimaryPart = the main envelope cylinder. <= 70 parts, no
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

-- local tones: dark bronze body, steel nose/tail and pods, dark gores
local Bronze = rgb(150, 92, 60)
local Steel = rgb(150, 140, 136)
local Gore = rgb(52, 38, 34)
local NavRed = rgb(255, 64, 64)
local NavGreen = rgb(80, 255, 140)
local Screen = rgb(255, 170, 90)
local Trail = rgb(255, 120, 150)

local Airship = {}

-- Where it flies: over the mountain's right shoulder, behind its back edge,
-- between the peak and the east floating island in the hero and spawn shots
-- (not a LobbyLayout piece: it hangs outside the lobby area box).
Airship.Center = Vector3.new(139, 147, -371)
-- the nose points west-south-west: the town sees it three-quarter from the
-- front-left like concept v2 (nose to the left, tail and exhaust to the right)
Airship.Heading = 252
-- nose down (degrees), like the concept
Airship.Pitch = 7
-- the design below is in "ship units" (envelope ~66 long, 14 wide); Scale
-- turns them into studs
Airship.Scale = 1.25
Airship.MaxParts = 70

-- envelope (ship units, the nose toward -Z)
local BODY_D = 14 -- main cylinder diameter
local BODY_LEN = 40 -- main cylinder length (z -20 .. 20)
-- nose and tail tapers: { diameter, center z, length } (each overlaps the
-- last; small steps read as one smooth taper at a distance)
local NOSE = { { 12.6, -21.8, 4.4 }, { 10.8, -24.8, 3.6 }, { 8.6, -27.4, 3.2 }, { 6, -29.6, 2.8 } }
local TAIL = { { 12.4, 22, 5 }, { 10.2, 25.4, 4 }, { 7.6, 28.4, 3.6 }, { 4.8, 31, 3.2 } }

function Airship.build(parent: Instance, rng: Rng.Rng): Model
	local m = Style.model("Airship", parent)
	local S = Airship.Scale
	local a = math.rad(Airship.Heading)
	local forward = Vector3.new(math.sin(a), 0, -math.cos(a))
	-- frame: envelope center, LookVector = the nose, pitched nose-down
	local frame = CFrame.lookAt(Airship.Center, Airship.Center + forward) * CFrame.Angles(math.rad(-Airship.Pitch), 0, 0)

	-- ship units -> studs
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x * S, y * S, z * S)
	end
	local function size(x: number, y: number, z: number): Vector3
		return Vector3.new(x * S, y * S, z * S)
	end
	local function box(cf: CFrame, s: Vector3, color: Color3, material: Enum.Material?): Part
		return Style.block(m, cf, s, color, material, Kit.far())
	end
	local function glow(cf: CFrame, s: Vector3, color: Color3, transparency: number?): Part
		return Kit.glow(m, cf, s, color, transparency)
	end
	-- a cylinder along the ship's axis (Roblox cylinders run along X)
	local function drum(cf: CFrame, diameter: number, length: number, color: Color3, material: Enum.Material?): Part
		return Style.block(
			m,
			cf * CFrame.Angles(0, math.pi / 2, 0),
			size(length, diameter, diameter),
			color,
			material,
			Kit.far({ Shape = CYLINDER })
		)
	end
	-- a three-blade propeller facing along the ship's axis; `span` = tip to tip
	local function propeller(cf: CFrame, span: number)
		box(cf, size(1.1, 1.1, 0.9), C.Iron)
		local twist = rng:range(0, math.pi * 2 / 3)
		for k = 0, 2 do
			local spin = cf * CFrame.Angles(0, 0, twist + k * math.pi * 2 / 3)
			box(spin * CFrame.new(0, span / 4 * S, 0) * CFrame.Angles(0, math.rad(18), 0), size(0.7, span / 2, 0.2), C.WoodLight)
		end
	end

	-- the envelope: bronze body, steel nose and tail tapers, a brass nose cap
	local bronze = Style.vary(Bronze, rng, 0.03)
	local body = drum(at(0, 0, 0), BODY_D, BODY_LEN, bronze)
	body.Name = "Envelope"
	for _, t in NOSE do
		drum(at(0, 0, t[2]), t[1], t[3], Steel)
	end
	for _, t in TAIL do
		drum(at(0, 0, t[2]), t[1], t[3], Steel)
	end
	local tip = NOSE[4][2] - NOSE[4][3] / 2
	Style.block(m, at(0, 0, tip + 0.6), size(4.6, 4.6, 4.6), C.Brass, nil, Kit.far({ Shape = BALL }))
	glow(at(0, 0, tip - 1.4), size(1.8, 1.8, 0.6), C.Lamp)

	-- brass ribs: over the nose and tail steps (no visible seam) and around the belly
	drum(at(0, 0, -BODY_LEN / 2 + 0.4), BODY_D + 0.6, 1.2, C.Brass)
	drum(at(0, 0, BODY_LEN / 2 - 0.4), BODY_D + 0.6, 1.2, C.Brass)
	for _, rz in { -7, 7 } do
		drum(at(0, 0, rz), BODY_D + 0.5, 0.8, C.Brass)
	end
	-- four thin dark gore strips along the envelope
	for k = 0, 3 do
		local angle = math.rad(45 + k * 90)
		local r = BODY_D / 2 + 0.1
		-- local X points outward: 0.5 thick (0.35 above the skin), 0.9 wide
		box(at(math.cos(angle) * r, math.sin(angle) * r, 0) * CFrame.Angles(0, 0, angle), size(0.5, 0.9, BODY_LEN - 2), Gore)
	end
	-- lit portholes on both flanks
	local portY = 1.4
	local portX = math.sqrt((BODY_D / 2) ^ 2 - portY ^ 2) + 0.05
	for _, side in { -1, 1 } do
		for _, pz in { -12, -2 } do
			glow(at(side * portX, portY, pz), size(0.3, 1.1, 1.1), C.Lamp)
		end
	end

	-- small top engine: a cylinder housing with a brass cap and a glowing exhaust
	local topY = BODY_D / 2 + 1.2
	drum(at(0, topY, 9), 3.4, 7, Steel)
	drum(at(0, topY, 5.2), 2.6, 0.8, C.Brass)
	glow(at(0, topY, 12.9), size(2, 2, 0.8), C.Fire, 0.1)

	-- wedge fins on the tail: the slope faces forward (a wedge's tall face is
	-- its +Z side), so every fin's leading edge sweeps back
	local finZ = 25
	local finR = 5
	Geo.wedge(m, at(0, finR + 3, finZ), size(0.8, 6, 8), C.AwningRed, nil, Kit.far())
	Geo.wedge(m, at(0, -finR - 2.5, finZ) * CFrame.Angles(0, 0, math.pi), size(0.8, 5, 7), C.RoofTrim, nil, Kit.far())
	for _, side in { -1, 1 } do
		Geo.wedge(
			m,
			at(side * (finR + 3), 0, finZ) * CFrame.Angles(0, 0, -side * math.pi / 2),
			size(0.8, 6, 8),
			C.AwningRed,
			nil,
			Kit.far()
		)
		-- navigation lamps on the fin tips (red to port, green to starboard)
		glow(at(side * (finR + 6.2), 0, finZ + 3.2), size(0.8, 0.8, 0.8), if side < 0 then NavRed else NavGreen)
	end

	-- stern propeller and the exhaust trail behind it (pink-ember, fading)
	local sternZ = TAIL[4][2] + TAIL[4][3] / 2 + 0.6
	propeller(at(0, 0, sternZ), 9)
	glow(at(0, 0, sternZ + 3.4), size(1.6, 1.6, 4), C.Ember, 0.2)
	glow(at(0, 0.3, sternZ + 9), size(1.2, 1.2, 8), Trail, 0.55)

	-- engine pods on pylons, low on both flanks
	for _, side in { -1, 1 } do
		local podX = side * (BODY_D / 2 + 3.6)
		local podY = -3.4
		local podZ = 2
		box(at(side * (BODY_D / 2 + 1.1), -2.6, podZ), size(4.2, 0.7, 2.6), C.Iron)
		drum(at(podX, podY, podZ), 3.4, 8, Steel)
		drum(at(podX, podY, podZ - 4.2), 2.6, 0.8, C.Brass)
		propeller(at(podX, podY, podZ - 5), 9)
		glow(at(podX, podY, podZ + 4.4), size(1.8, 1.8, 0.8), C.Fire, 0.1)
	end

	-- gondola under the belly: timber cabin, brass roof trim, iron keel,
	-- slanted nose with a thin windscreen strip, a row of lit windows a side
	local gy = -BODY_D / 2 - 2.4
	local gz = -2
	local cabin = box(at(0, gy, gz), size(5, 3.6, 16), Style.vary(C.WoodDark, rng, 0.03))
	cabin.Name = "Gondola"
	box(at(0, gy + 2, gz), size(5.4, 0.5, 16.4), C.Brass)
	box(at(0, gy - 2.1, gz + 0.5), size(3.6, 0.7, 14), C.Iron)
	-- slanted nose: the wedge's slope faces forward and up
	Geo.wedge(m, at(0, gy, gz - 9.5), size(5, 3.6, 3), Style.vary(C.WoodDark, rng, 0.03), nil, Kit.far())
	-- a thin windscreen strip lying on that slope
	local tilt = -math.atan2(3.6, 3)
	glow(at(0, gy, gz - 9.5) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 0.12 * S, 0.5 * S), size(4, 0.2, 0.9), Screen, 0.35)
	box(at(0, gy - 0.2, gz + 8.9), size(4, 3, 1.8), C.Wood)
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			glow(at(side * 2.55, gy + 0.3, gz - 5 + k * 4.6), size(0.2, 1.3, 2.4), C.Lamp)
		end
	end
	-- struts from the cabin roof up into the envelope
	for _, sz in { -6, 4 } do
		box(at(0, gy + 3.4, gz + sz), size(0.6, 2.4, 0.6), C.Iron)
	end

	m.PrimaryPart = body
	m:AddTag("Spin")
	m:SetAttribute("SpinSpeed", 0)
	m:SetAttribute("BobHeight", 3)
	m:SetAttribute("BobSpeed", 0.35)
	Style.streaming(m, "Persistent")
	return m
end

return Airship
