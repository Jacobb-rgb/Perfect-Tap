--[[
	Sky package: the airship of concept v2 (docs/art/lobby_concept_v2.webp,
	top right): a long rounded copper bullet cruising over the mountain's
	right shoulder, between the peak and the east floating island, pitched a
	little nose-down like the concept.

	The envelope is a sunlit copper-bronze cylinder closed by Balls, not
	stepped drums: a full-width copper ball makes the round nose (one dark
	band around it) with a smaller ball pushed out in front as the tip and
	the lamp on it; a slightly narrower ball rounds the tail off into a
	two-drum cone that carries the stern propeller. A light brass strip runs
	along the sunlit top, brass ribs band the body, four thin copper-brown
	gore strips run along it, two portholes glow on each flank. On top a
	small engine (a cylinder housing with a brass cap and a glowing exhaust),
	at the tail four wedge fins with red/green navigation lamps, behind the
	stern a three-blade propeller and a long glowing exhaust streak (three
	Neon segments, each longer, wider and fainter). Two engine pods hang on
	pylons with big dark three-blade propellers on brass hubs and glowing
	exhausts, and under the belly a timber gondola with a thin windscreen
	strip and lit windows.

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

-- local tones: sunlit copper-bronze body, steel pods, copper-brown gores
local Bronze = rgb(190, 120, 72)
local Steel = rgb(150, 140, 136)
local Gore = rgb(112, 64, 40)
local Band = rgb(58, 40, 34)
local TopStrip = rgb(236, 182, 112)
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
-- the rounded nose: a full-width ball on the body's front end and a smaller
-- tip ball pushed out in front of it ({ diameter, center z })
local NOSE = { BODY_D, -BODY_LEN / 2 }
local TIP = { 10, -23.2 }
-- the rounded tail: a slightly narrower ball and a two-drum cone
-- ({ diameter, center z, length }) into the stern propeller
local TAIL = { 13, BODY_LEN / 2 }
local CONE = { { 8, 26.6, 4 }, { 5, 29.8, 3 } }

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
	-- a ball (diameter in ship units)
	local function orb(cf: CFrame, diameter: number, color: Color3): Part
		return Style.block(m, cf, size(diameter, diameter, diameter), color, nil, Kit.far({ Shape = BALL }))
	end
	-- a three-blade propeller facing along the ship's axis on a brass hub
	-- disc; `span` = tip to tip
	local function propeller(cf: CFrame, span: number)
		drum(cf, 2.2, 0.8, C.Brass)
		local twist = rng:range(0, math.pi * 2 / 3)
		for k = 0, 2 do
			local spin = cf * CFrame.Angles(0, 0, twist + k * math.pi * 2 / 3)
			box(spin * CFrame.new(0, span / 4 * S, 0) * CFrame.Angles(0, math.rad(18), 0), size(1.1, span / 2, 0.25), C.Iron)
		end
	end

	-- the envelope: a copper-bronze body closed by balls, a copper nose with
	-- one dark band, a small tip ball with the lamp, a ball tail and a cone
	local bronze = Style.vary(Bronze, rng, 0.03)
	local body = drum(at(0, 0, 0), BODY_D, BODY_LEN, bronze)
	body.Name = "Envelope"
	local nose = orb(at(0, 0, NOSE[2]), NOSE[1], C.Copper)
	nose.Name = "Nose"
	-- the dark band: a thin disc around the nose ball just in front of the
	-- body, so from the front the nose stays one clean dome
	local bandZ = NOSE[2] - 1.6
	drum(at(0, 0, bandZ), 2 * math.sqrt((NOSE[1] / 2) ^ 2 - 1.6 ^ 2) + 0.3, 0.9, Band)
	orb(at(0, 0, TIP[2]), TIP[1], C.Copper)
	glow(at(0, 0, TIP[2] - TIP[1] / 2 - 0.1), size(1.8, 1.8, 0.6), C.Lamp)
	local tail = orb(at(0, 0, TAIL[2]), TAIL[1], bronze)
	tail.Name = "Tail"
	for _, t in CONE do
		drum(at(0, 0, t[2]), t[1], t[3], C.Copper)
	end

	-- brass ribs where the balls meet the body and around the belly
	drum(at(0, 0, -BODY_LEN / 2 + 0.4), BODY_D + 0.5, 1.2, C.Brass)
	drum(at(0, 0, BODY_LEN / 2 - 0.4), BODY_D + 0.5, 1.2, C.Brass)
	for _, rz in { -7, 7 } do
		drum(at(0, 0, rz), BODY_D + 0.4, 0.8, C.Brass)
	end
	-- the light brass strip along the sunlit top (0.25 above the skin)
	box(at(0, BODY_D / 2 + 0.05, 0), size(2.6, 0.6, BODY_LEN - 1), TopStrip)
	-- four thin copper-brown gore strips along the envelope
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
	local finR = 4.2
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

	-- stern propeller and the long glowing exhaust streak behind it: three
	-- Neon segments, each longer, wider and fainter (ember into pink)
	local last = CONE[#CONE]
	local sternZ = last[2] + last[3] / 2 + 0.5
	propeller(at(0, 0, sternZ), 12)
	local z = sternZ + 1
	type Segment = { Width: number, Length: number, Transparency: number, Color: Color3 }
	local trail: { Segment } = {
		{ Width = 2.6, Length = 5, Transparency = 0.3, Color = C.Ember },
		{ Width = 3.2, Length = 9, Transparency = 0.5, Color = Trail },
		{ Width = 3.8, Length = 14, Transparency = 0.7, Color = Trail },
	}
	for i, seg in trail do
		glow(at(0, 0.25 * i, z + seg.Length / 2), size(seg.Width, seg.Width * 0.8, seg.Length), seg.Color, seg.Transparency)
		z += seg.Length - 0.4
	end

	-- engine pods on pylons, low on both flanks
	for _, side in { -1, 1 } do
		local podX = side * (BODY_D / 2 + 3.6)
		local podY = -3.4
		local podZ = 2
		box(at(side * (BODY_D / 2 + 1.1), -2.6, podZ), size(4.2, 0.7, 2.6), C.Iron)
		drum(at(podX, podY, podZ), 3.4, 8, Steel)
		drum(at(podX, podY, podZ - 4.2), 2.6, 0.8, C.Brass)
		propeller(at(podX, podY, podZ - 4.9), 12)
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
