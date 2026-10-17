--[[
	Sky package: the airship of concept v2 (docs/art/lobby_concept_v2.webp,
	top right): a long copper cigar cruising over the mountain's right
	shoulder, between the peak and the east floating island, pitched a
	little nose-down like the concept.

	The envelope tapers continuously from a bulbous nose to the finned tail:
	a full-width copper nose ball (one dark band around it) with a smaller
	tip ball and lamp pushed out in front, then three drums stepping down
	14 -> 12.5 -> 10.5 (brass ribs hide every step), a ball tail and a
	three-step cone (8.5 -> 6 -> 3.5) into the stern propeller. A light brass
	strip runs along the sunlit top and four thin copper-brown gore strips
	run along the flanks, each one tilted to follow the taper; two portholes
	glow on each flank. On top a small engine (a cylinder housing with a
	brass cap and a glowing exhaust), at the tail four wedge fins with
	red/green navigation lamps, behind the stern a three-blade propeller and
	a thin bright magenta jet: three Neon cylinders shrinking 2.2 -> 1.4 ->
	0.8 wide and fading out. Two engine pods hang on pylons with big dark
	three-blade propellers on brass hubs and glowing exhausts, and under the
	belly a timber gondola with a thin windscreen strip and lit windows.

	Tagged Spin with SpinSpeed 0 (it never turns) and a slow bob. Persistent
	streaming: it hangs ~400 studs from the plaza, right at the 384-stud
	StreamingTargetRadius, so an Atomic model would pop in and out as players
	walk around. PrimaryPart = the front envelope drum. <= 70 parts, no
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
-- the exhaust jet: saturated magenta like the concept's
local Trail = rgb(255, 80, 200)

local Airship = {}

-- Where it flies: over the mountain's right shoulder, behind its back edge,
-- between the peak and the east floating island in the hero and spawn shots
-- (not a LobbyLayout piece: it hangs outside the lobby area box).
Airship.Center = Vector3.new(232, 186, -336) -- the spawn view's top right
-- the nose points west-south-west: the town sees it three-quarter from the
-- front-left like concept v2 (nose to the left, tail and exhaust to the right)
Airship.Heading = 252
-- nose down (degrees), like the concept
Airship.Pitch = 7
-- the design below is in "ship units" (envelope ~66 long, 14 wide); Scale
-- turns them into studs
Airship.Scale = 1.25
Airship.MaxParts = 70

-- envelope (ship units, the nose toward -Z): three drums stepping down
-- toward the tail ({ diameter, front z, back z }); the front one is the
-- widest and carries the nose
local DRUMS = { { 14, -20, -6 }, { 12.5, -6, 8 }, { 10.5, 8, 20 } }
local BODY_D = DRUMS[1][1]
-- the rounded nose: a full-width ball on the front drum's end and a smaller
-- tip ball pushed out in front of it ({ diameter, center z })
local NOSE = { BODY_D, DRUMS[1][2] }
local TIP = { 10, -23.2 }
-- the rounded tail: a ball as wide as the last drum and a three-step cone
-- ({ diameter, center z, length }) into the stern propeller
local TAIL = { DRUMS[#DRUMS][1], DRUMS[#DRUMS][3] }
local CONE = { { 8.5, 23.6, 3.2 }, { 6, 26.6, 3 }, { 3.5, 29.3, 2.6 } }

-- radius of the envelope at ship-z `z` (along the drums)
local function radiusAt(z: number): number
	for _, d in DRUMS do
		if z <= d[3] then
			return d[1] / 2
		end
	end
	return DRUMS[#DRUMS][1] / 2
end

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

	-- the envelope: three copper-bronze drums stepping down toward the tail,
	-- a copper nose with one dark band, a small tip ball with the lamp, a
	-- ball tail and a three-step cone
	local bronze = Style.vary(Bronze, rng, 0.03)
	local body: Part? = nil
	for i, d in DRUMS do
		local drumPart = drum(at(0, 0, (d[2] + d[3]) / 2), d[1], d[3] - d[2], bronze)
		if i == 1 then
			drumPart.Name = "Envelope"
			body = drumPart
		end
	end
	local nose = orb(at(0, 0, NOSE[2]), NOSE[1], C.Copper)
	nose.Name = "Nose"
	-- the dark band: a thin disc around the nose ball just in front of the
	-- body, so from the front the nose stays one clean dome
	local bandZ = NOSE[2] - 1.6
	drum(at(0, 0, bandZ), 2 * math.sqrt((NOSE[1] / 2) ^ 2 - 1.6 ^ 2) + 0.3, 0.9, Band)
	orb(at(0, 0, TIP[2]), TIP[1], C.Copper)
	glow(at(0, 0, TIP[2] - TIP[1] / 2 - 0.1), size(1.8, 1.8, 0.6), C.LampAmber)
	local tail = orb(at(0, 0, TAIL[2]), TAIL[1], bronze)
	tail.Name = "Tail"
	for _, t in CONE do
		drum(at(0, 0, t[2]), t[1], t[3], C.Copper)
	end

	-- brass ribs where the nose meets the body and over every drum step
	drum(at(0, 0, DRUMS[1][2] + 0.4), BODY_D + 0.5, 1.2, C.Brass)
	for i = 2, #DRUMS do
		drum(at(0, 0, DRUMS[i][2]), DRUMS[i - 1][1] + 0.4, 1, C.Brass)
	end
	-- the light brass strip along the sunlit top and four thin copper-brown
	-- gore strips, each tilted to follow the taper from the front drum to
	-- the last (0.25-0.6 above the skin)
	local front, back = DRUMS[1][2] + 1, DRUMS[#DRUMS][3] - 1
	local rFront, rBack = radiusAt(front), radiusAt(back)
	local taper = math.atan2(rFront - rBack, back - front)
	local function strip(angle: number, w: number, h: number, color: Color3)
		local r = (rFront + rBack) / 2 + 0.25
		local mid = at(math.cos(angle) * r, math.sin(angle) * r, (front + back) / 2)
		-- local X points outward; the strip tilts inward toward the tail
		box(mid * CFrame.Angles(0, 0, angle) * CFrame.Angles(0, -taper, 0), size(h, w, back - front), color)
	end
	strip(math.pi / 2, 2.6, 0.6, TopStrip)
	for k = 0, 3 do
		strip(math.rad(45 + k * 90), 0.9, 0.5, Gore)
	end
	-- lit portholes on both flanks
	local portY = 1.4
	local portX = math.sqrt(radiusAt(-12) ^ 2 - portY ^ 2) + 0.05
	for _, side in { -1, 1 } do
		for _, pz in { -15, -9 } do
			glow(at(side * portX, portY, pz), size(0.3, 1.1, 1.1), C.LampAmber)
		end
	end

	-- small top engine: a cylinder housing with a brass cap and a glowing exhaust
	local topY = radiusAt(9) + 1.2
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

	-- stern propeller and the thin bright magenta jet behind it: three Neon
	-- cylinders, each longer, thinner and fainter
	local last = CONE[#CONE]
	local sternZ = last[2] + last[3] / 2 + 0.5
	propeller(at(0, 0, sternZ), 12)
	local z = sternZ + 1
	type Segment = { Width: number, Length: number, Transparency: number }
	local trail: { Segment } = {
		{ Width = 2.2, Length = 6, Transparency = 0.2 },
		{ Width = 1.4, Length = 10, Transparency = 0.45 },
		{ Width = 0.8, Length = 14, Transparency = 0.7 },
	}
	for _, seg in trail do
		local jet = drum(at(0, 0, z + seg.Length / 2), seg.Width, seg.Length, Trail, Enum.Material.Neon)
		jet.Transparency = seg.Transparency
		jet.Name = "Jet"
		z += seg.Length - 0.3
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
			glow(at(side * 2.55, gy + 0.3, gz - 5 + k * 4.6), size(0.2, 1.3, 2.4), C.LampAmber)
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
