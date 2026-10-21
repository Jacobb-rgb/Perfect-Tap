--[[
	Emote CONCEPTS (owner 2026-10-21: "mega cool emotes ... come up with
	something and I'll decide"). Pure data in the MoveConfig format
	(MoveMath / MoveRig play them; the angle conventions are in
	MoveConfig). NOT wired into the game yet: no emote menu, no binding,
	not in MoveConfig.Moves nor the Net "Move" whitelist. Wiring one later:
	add an emote slot to MoveController, the names to
	MoveConfig.ClientMoves and MoveRules.decode, and an emote button.

	Every emote is a loop that runs until stopped: an intro once (keys
	before LoopFrom), the loop (LoopFrom to Duration), and an Outro (a
	finishing pose, then standing) when stopped. Full body: every R15
	joint replaces the walk / idle (Override = all). Root offsets and
	turns are looks only (the HumanoidRootPart and the physics never
	move) and keep the whole body above the floor (tests/Emotes.spec).
	RightGrip (MoveConfig.ToolJoints) turns the held tool about the hand:
	the Blaster Spin (NeedsTool) twirls the blaster.

	List = the order of the preview showreel (docs/screenshots/animations/
	emoty.mp4); Captions = the owner's Czech names for it.
]]

local MoveConfig = require(script.Parent.MoveConfig)

type Euler = MoveConfig.Euler
type Pose = MoveConfig.Pose
type Key = MoveConfig.Key
type Move = MoveConfig.Move

local EmoteConfig = {}

local mirror = MoveConfig.mirror

-- every R15 joint: an emote owns the whole body
local ALL: { string } = table.clone(MoveConfig.Joints)

-- a pose built from parts (later tables win)
local function P(...: Pose): Pose
	local out: Pose = {}
	for i = 1, select("#", ...) do
		local part = select(i, ...)
		for joint, e in part do
			out[joint] = e
		end
	end
	return out
end

-- both arms from the right arm (the left is the mirror)
local function arms(shoulder: Euler, elbow: Euler?, wrist: Euler?): Pose
	local pose: Pose = { RightShoulder = shoulder, LeftShoulder = mirror(shoulder) }
	if elbow then
		pose.RightElbow = elbow
		pose.LeftElbow = mirror(elbow)
	end
	if wrist then
		pose.RightWrist = wrist
		pose.LeftWrist = mirror(wrist)
	end
	return pose
end

local function rightArm(shoulder: Euler, elbow: Euler?, wrist: Euler?): Pose
	return { RightShoulder = shoulder, RightElbow = elbow or { 0, 0, 0 }, RightWrist = wrist or { 0, 0, 0 } }
end
local function leftArm(shoulder: Euler, elbow: Euler?, wrist: Euler?): Pose
	return { LeftShoulder = shoulder, LeftElbow = elbow or { 0, 0, 0 }, LeftWrist = wrist or { 0, 0, 0 } }
end
local function rightLeg(hip: Euler, knee: Euler?, ankle: Euler?): Pose
	return { RightHip = hip, RightKnee = knee or { 0, 0, 0 }, RightAnkle = ankle or { 0, 0, 0 } }
end
local function leftLeg(hip: Euler, knee: Euler?, ankle: Euler?): Pose
	return { LeftHip = hip, LeftKnee = knee or { 0, 0, 0 }, LeftAnkle = ankle or { 0, 0, 0 } }
end

-- both legs bent by `a` with the feet still flat on the floor (see MoveConfig: Root down by drop(a))
local function crouch(a: number): Pose
	return P(rightLeg({ a, 0, 0 }, { -2 * a, 0, 0 }, { a, 0, 0 }), leftLeg({ a, 0, 0 }, { -2 * a, 0, 0 }, { a, 0, 0 }))
end
local drop = MoveConfig.crouchDrop

local function key(t: number, ease: string?, pose: Pose, offset: Euler?): Key
	return { T = t, Ease = ease, Pose = pose, Offset = offset }
end

-- snappy beats: each pose snaps in over `snap` seconds, then holds until the next beat
local function beats(start: number, beat: number, snap: number, poses: { { pose: Pose, offset: Euler? } }): { Key }
	local keys: { Key } = {}
	for i, b in poses do
		local t = start + (i - 1) * beat
		if i > 1 then
			-- hold the pose before until the snap
			local before = poses[i - 1]
			table.insert(keys, key(t - snap, "Linear", before.pose, before.offset))
		end
		table.insert(keys, key(t, "Out", b.pose, b.offset))
	end
	return keys
end

local function emote(fields: { [string]: any }): Move
	local move = {
		Name = fields.Name,
		Duration = fields.Duration,
		Loop = true,
		Slot = "Emote",
		BlendIn = fields.BlendIn or 0.12,
		BlendOut = fields.BlendOut or 0.15,
		Override = ALL,
		MinGap = 1,
		Priority = 2,
		Keys = fields.Keys,
		RootPivot = fields.RootPivot,
		LoopFrom = fields.LoopFrom,
		Outro = fields.Outro,
		NeedsTool = fields.NeedsTool,
	}
	return move :: any
end

local STAND: Pose = {}
local TADA: Pose = P(arms({ 158, 0, 34 }, { 8, 0, 0 }), { Waist = { 8, 0, 0 }, Neck = { 10, 0, 0 } })

---------------------------------------------------------------- 1 Breakdance: windmill + freeze

-- lying on the upper back, hips up, legs in a wide V circling while the body spins flat
local function windmill(spin: number, phase: number): Pose
	local s = math.sin(phase)
	local c = math.cos(phase)
	return P(
		arms({ -20, 0, 66 }, { 16, 0, 0 }),
		rightLeg({ 30 + 28 * s, 0, 52 }, { -8, 0, 0 }, { -25, 0, 0 }),
		leftLeg({ 30 - 28 * s, 0, -52 }, { -8, 0, 0 }, { -25, 0, 0 }),
		{ Root = { 134, spin, 22 * c }, Neck = { -46, 0, 0 }, Waist = { -8, 0, 0 } }
	)
end
local WINDMILL_DOWN = { 0, -2.22, 0 }
local WINDMILL_FROM = 0.8
local breakdanceKeys: { Key } = {
	key(0, nil, STAND),
	key(0.24, "Out", P(crouch(28), rightArm({ 60, 0, 10 }, { 10, 0, 0 }), { Waist = { -20, 0, 0 } }), { 0, -drop(28) + 0.04, 0 }),
	-- spring up, then sit back onto the floor with the legs up
	key(0.36, "Out", P(crouch(8), arms({ 40, 0, 30 }, { 10, 0, 0 }), { Root = { 20, 0, 0 } }), { 0, 0.25, 0 }),
	key(
		0.56,
		"InOut",
		P(rightLeg({ 85, 0, 20 }, { -30, 0, 0 }), leftLeg({ 85, 0, -20 }, { -30, 0, 0 }), arms({ -30, 0, 30 }, { 10, 0, 0 }), {
			Root = { 70, 0, 0 },
			Neck = { -20, 0, 0 },
		}),
		{ 0, -1.8, 0 }
	),
	key(WINDMILL_FROM, "InOut", windmill(0, 0), WINDMILL_DOWN),
}
for i = 1, 8 do
	-- two spins: 8 keys of 90 degrees, the legs pumping twice per spin
	table.insert(breakdanceKeys, key(WINDMILL_FROM + i * 0.225, "Linear", windmill(i * 90, i * math.pi / 2), WINDMILL_DOWN))
end

-- the freeze: on the right hand, body sideways in the air, legs bent like a running man
local FREEZE: Pose = P(
	rightArm({ 0, 0, 72 }, { 0, 0, 0 }),
	leftArm({ 0, 0, -112 }, { 8, 0, 0 }),
	rightLeg({ 30, 0, 0 }, { -105, 0, 0 }, { 20, 0, 0 }),
	leftLeg({ 75, 0, 0 }, { -30, 0, 0 }),
	{ Root = { 18, 0, -70 }, Neck = { 0, 0, 22 }, Waist = { 0, 0, -8 } }
)

EmoteConfig.Breakdance = emote({
	Name = "Breakdance",
	RootPivot = { 0, 1.4, 0 },
	LoopFrom = WINDMILL_FROM,
	Duration = WINDMILL_FROM + 8 * 0.225,
	Keys = breakdanceKeys,
	Outro = {
		key(0.38, "Out", FREEZE, { 0, -0.47, 0 }),
		key(1.15, "Sine", FREEZE, { 0, -0.44, 0 }),
		key(1.42, "Out", P(crouch(25), arms({ 40, 0, 30 }, { 20, 0, 0 }), { Root = { 0, 0, -15 } }), { 0, -drop(25) + 0.3, 0 }),
		key(1.55, "In", P(crouch(25), arms({ 40, 0, 20 }, { 20, 0, 0 })), { 0, -drop(25), 0 }),
		key(1.85, "InOut", STAND),
	},
})

---------------------------------------------------------------- 2 Headspin

-- upside down on the top of the head (RootPivot), legs in a V, arms out
local HEAD_DOWN = { 0, -5.2, 0 }
local function headstand(spin: number, open: number): Pose
	return P(
		arms({ 0, 0, 96 }, { 6, 0, 0 }),
		rightLeg({ 6, 0, 18 + open }, { -10, 0, 0 }, { -25, 0, 0 }),
		leftLeg({ 6, 0, -18 - open }, { -10, 0, 0 }, { -25, 0, 0 }),
		{ Root = { 180, spin, 0 } }
	)
end
local headspinKeys: { Key } = {
	key(0, nil, STAND),
	key(0.24, "Out", P(crouch(32), arms({ 72, 0, 8 }, { 18, 0, 0 }), { Waist = { -28, 0, 0 }, Neck = { -10, 0, 0 } }), {
		0,
		-drop(32),
		0,
	}),
	key(0.34, "Out", P(crouch(8), arms({ 120, 0, 10 }, { 4, 0, 0 }), { Root = { 18, 0, 0 } }), { 0, 0.2, 0 }),
	key(0.48, "InOut", P(arms({ 150, 0, 10 }, { 4, 0, 0 }), { Root = { 90, 0, 0 } }), { 0, -2.0, 0 }),
	key(0.68, "Out", headstand(0, 0), HEAD_DOWN),
}
for i = 1, 6 do
	-- three spins in 1.8 s, the legs opening and closing
	table.insert(headspinKeys, key(0.68 + i * 0.3, "Linear", headstand(i * 180, if i % 2 == 1 then 22 else 0), HEAD_DOWN))
end

EmoteConfig.Headspin = emote({
	Name = "Headspin",
	RootPivot = { 0, 3.25, 0 },
	LoopFrom = 0.68,
	Duration = 0.68 + 6 * 0.3,
	Keys = headspinKeys,
	Outro = {
		-- tuck and flip back up over the head
		key(
			0.22,
			"Out",
			P(rightLeg({ 70, 0, 10 }, { -100, 0, 0 }), leftLeg({ 70, 0, -10 }, { -100, 0, 0 }), arms({ 20, 0, 60 }), {
				Root = { -95, 0, 0 },
			}),
			{ 0, -2.2, 0 }
		),
		key(0.36, "Out", P(crouch(30), arms({ 30, 0, 50 }, { 10, 0, 0 }), { Root = { -25, 0, 0 } }), { 0, -drop(30) + 0.35, 0 }),
		key(0.48, "In", P(crouch(30), arms({ 30, 0, 40 }, { 10, 0, 0 })), { 0, -drop(30), 0 }),
		key(0.78, "Back", TADA),
		key(1.18, "Sine", TADA),
		key(1.48, "InOut", STAND),
	},
})

---------------------------------------------------------------- 3 Robot

local ROBOT_ARMS = arms({ 0, 0, 88 }, { 88, 0, 0 })
local robotPoses = {
	{ pose = P(ROBOT_ARMS, { Neck = { 0, -32, 0 } }) },
	{ pose = P(rightArm({ 90, 0, 0 }), leftArm({ 0, 0, -88 }, { 88, 0, 0 }), { Neck = { 0, 30, 0 }, Waist = { 0, 14, 0 } }) },
	{ pose = P(arms({ 90, 0, 0 }, { 90, 0, 0 }), crouch(14), { Neck = { -8, 0, 0 } }), offset = { 0, -drop(14), 0 } },
	{
		pose = P(
			rightArm({ 90, 0, 0 }, { 90, 0, 0 }),
			leftArm({ 0, 0, -6 }, { 90, 0, 0 }),
			{ Waist = { 0, -34, 0 }, Neck = { 0, -36, 0 } }
		),
	},
	{ pose = P(leftArm({ 90, 0, 0 }, { 90, 0, 0 }), rightArm({ 0, 0, 6 }, { 90, 0, 0 }), { Waist = { 0, 34, 0 }, Neck = { 0, 36, 0 } }) },
	{ pose = P(arms({ 0, 0, 90 }), { Neck = { 0, 0, 16 } }) },
	{
		pose = P(
			rightArm({ 0, 0, 90 }, { 88, 0, 0 }),
			leftArm({ 0, 0, -90 }),
			rightLeg({ 28, 0, 0 }, { -30, 0, 0 }),
			{ Neck = { 0, -20, -12 } }
		),
	},
	{ pose = P(ROBOT_ARMS, crouch(10), { Neck = { 0, 20, 0 } }), offset = { 0, -drop(10), 0 } },
}
local robotKeys: { Key } = { key(0, nil, STAND) }
for _, k in beats(0.2, 0.4, 0.07, robotPoses) do
	table.insert(robotKeys, k)
end
-- hold the last pose until the snap back to the first
local lastRobot = robotPoses[#robotPoses]
table.insert(robotKeys, key(0.2 + 8 * 0.4 - 0.07, "Linear", lastRobot.pose, lastRobot.offset))

local POWER_DOWN: Pose = P(arms({ 18, 0, 6 }, { 30, 0, 0 }, { 20, 0, 0 }), crouch(12), { Neck = { -38, 0, 0 }, Waist = { -18, 0, 0 } })
EmoteConfig.Robot = emote({
	Name = "Robot",
	LoopFrom = 0.2,
	Duration = 0.2 + 8 * 0.4,
	Keys = robotKeys,
	Outro = {
		-- power down, a pause, then a snappy reboot to standing
		key(0.3, "InOut", POWER_DOWN, { 0, -drop(12), 0 }),
		key(0.85, "Linear", POWER_DOWN, { 0, -drop(12), 0 }),
		key(0.95, "Out", P(ROBOT_ARMS, { Neck = { 6, 0, 0 } })),
		key(1.3, "Linear", P(ROBOT_ARMS, { Neck = { 6, 0, 0 } })),
		key(1.42, "Out", STAND),
	},
})

---------------------------------------------------------------- 4 Disco point

local DISCO_UP: Pose = P(
	rightArm({ 26, 0, 132 }, { 0, 0, 0 }),
	leftArm({ -12, 0, -34 }, { 70, 0, 0 }),
	rightLeg({ 0, 0, 4 }),
	leftLeg({ 12, 0, -4 }, { -26, 0, 0 }, { 12, 0, 0 }),
	{ Root = { 0, 0, 5 }, Waist = { 0, -10, -8 }, Neck = { 14, -22, 0 } }
)
local DISCO_DOWN: Pose = P(
	rightArm({ 60, 0, -8 }, { 0, 0, 0 }),
	leftArm({ -12, 0, -34 }, { 70, 0, 0 }),
	rightLeg({ 12, 0, 4 }, { -26, 0, 0 }, { 12, 0, 0 }),
	leftLeg({ 0, 0, -4 }),
	{ Root = { 0, 0, -5 }, Waist = { 0, 22, 6 }, Neck = { -16, 18, 0 } }
)
EmoteConfig.DiscoPoint = emote({
	Name = "DiscoPoint",
	LoopFrom = 0.25,
	Duration = 0.25 + 1.6,
	Keys = {
		key(0, nil, STAND),
		key(0.25, "Out", DISCO_UP, { 0, -0.05, 0 }),
		key(0.55, "Sine", DISCO_UP, { 0, -0.05, 0 }),
		key(0.65, "Out", DISCO_DOWN, { 0, -0.06, 0 }),
		key(0.95, "Sine", DISCO_DOWN, { 0, -0.06, 0 }),
		key(1.05, "Out", DISCO_UP, { 0, -0.05, 0 }),
		key(1.35, "Sine", DISCO_UP, { 0, -0.05, 0 }),
		key(1.45, "Out", DISCO_DOWN, { 0, -0.06, 0 }),
		key(1.75, "Sine", DISCO_DOWN, { 0, -0.06, 0 }),
	},
	Outro = {
		key(0.22, "Out", DISCO_UP),
		key(0.85, "Sine", DISCO_UP),
		key(1.15, "InOut", STAND),
	},
})

---------------------------------------------------------------- 5 Back Glide (a backward glide, in place)

-- one foot flat sliding back, the other on its toes with the knee bent
local function glide(flatHip: number, toeHip: number, flatIsRight: boolean): Pose
	local flat = { { flatHip, 0, 0 }, { 0, 0, 0 }, { -flatHip, 0, 0 } }
	local toe = { { toeHip, 0, 0 }, { -2 * toeHip - 4, 0, 0 }, { 4, 0, 0 } }
	local right = if flatIsRight then flat else toe
	local left = if flatIsRight then toe else flat
	return P(
		rightLeg(right[1], right[2], right[3]),
		leftLeg(left[1], left[2], left[3]),
		rightArm({ 34, 0, -2 }, { 80, 0, 0 }),
		leftArm({ if flatIsRight then -14 else 8, 0, -8 }, { 18, 0, 0 }),
		{ Neck = { -4, if flatIsRight then 10 else -10, 0 }, Waist = { 2, if flatIsRight then -5 else 5, 0 } }
	)
end
local GLIDE_DOWN = { 0, -0.07, 0 }
local TIPTOE: Pose = P(
	rightArm({ 150, 0, 8 }, { 105, 0, 0 }),
	leftArm({ 4, 0, -10 }, { 10, 0, 0 }),
	rightLeg({ 0, 0, 2 }, { 0, 0, 0 }, { -32, 0, 0 }),
	leftLeg({ 0, 0, -2 }, { 0, 0, 0 }, { -32, 0, 0 }),
	{ Neck = { -8, 0, 0 } }
)
EmoteConfig.BackGlide = emote({
	Name = "BackGlide",
	LoopFrom = 0.25,
	Duration = 0.25 + 2.0,
	Keys = {
		key(0, nil, STAND),
		key(0.25, "Out", glide(10, 26, true), GLIDE_DOWN),
		key(0.7, "Linear", glide(-16, 22, true), GLIDE_DOWN),
		key(0.75, "Out", glide(10, 26, false), GLIDE_DOWN),
		key(1.2, "Linear", glide(-16, 22, false), GLIDE_DOWN),
		key(1.25, "Out", glide(10, 26, true), GLIDE_DOWN),
		key(1.7, "Linear", glide(-16, 22, true), GLIDE_DOWN),
		key(1.75, "Out", glide(10, 26, false), GLIDE_DOWN),
		key(2.2, "Linear", glide(-16, 22, false), GLIDE_DOWN),
	},
	Outro = {
		key(0.2, "Out", TIPTOE, { 0, 0.32, 0 }),
		key(0.8, "Linear", TIPTOE, { 0, 0.32, 0 }),
		key(1.1, "InOut", STAND),
	},
})

---------------------------------------------------------------- 6 The Worm

-- face down on the floor (Root -90 about the chest), a wave running from the feet to the head
local WORM_DOWN = { 0, -2.62, 0 }
local function worm(root: number, waist: number, neck: number, hip: number, knee: number, arm: number): Pose
	return P(
		arms({ arm, 0, 12 }, { 0, 0, 0 }),
		rightLeg({ hip, 0, 4 }, { knee, 0, 0 }, { 10, 0, 0 }),
		leftLeg({ hip, 0, -4 }, { knee, 0, 0 }, { 10, 0, 0 }),
		{ Root = { root, 0, 0 }, Waist = { waist, 0, 0 }, Neck = { neck, 0, 0 } }
	)
end
local WORM_FLAT = worm(-90, 4, 18, 0, -8, 0)
EmoteConfig.Worm = emote({
	Name = "Worm",
	RootPivot = { 0, 1.2, 0 },
	LoopFrom = 0.6,
	Duration = 0.6 + 1.4,
	Keys = {
		key(0, nil, STAND),
		key(0.2, "Out", P(crouch(28), arms({ 70, 0, 14 }, { 10, 0, 0 }), { Waist = { -26, 0, 0 } }), { 0, -drop(28) + 0.04, 0 }),
		-- spring and dive forward onto the chest
		key(0.32, "Out", P(crouch(8), arms({ 120, 0, 14 }), { Root = { -20, 0, 0 } }), { 0, 0.25, 0 }),
		key(
			0.46,
			"InOut",
			P(arms({ 20, 0, 30 }), rightLeg({ -15, 0, 0 }), leftLeg({ -15, 0, 0 }), { Root = { -60, 0, 0 } }),
			{ 0, -1.1, 0 }
		),
		key(0.6, "Out", WORM_FLAT, WORM_DOWN),
		-- the feet kick up, the hips rise, the chest lifts, the head comes up
		key(0.95, "Sine", worm(-90, 0, 16, -18, -96, -6), WORM_DOWN),
		key(1.3, "Sine", worm(-101, 14, 42, 8, -30, 0), { 0, -2.3, 0 }),
		key(1.65, "Sine", worm(-87, 44, 40, 0, -6, -24), { 0, -2.55, 0 }),
	},
	Outro = {
		-- pop up: a push and a hop to the feet
		key(
			0.25,
			"Out",
			P(rightLeg({ 50, 0, 0 }, { -100, 0, 0 }), leftLeg({ 50, 0, 0 }, { -100, 0, 0 }), arms({ 40, 0, 20 }), {
				Root = { -45, 0, 0 },
			}),
			{ 0, -0.7, 0 }
		),
		key(0.4, "Out", P(crouch(26), arms({ 50, 0, 14 }, { 10, 0, 0 }), { Root = { -15, 0, 0 }, Waist = { -20, 0, 0 } }), {
			0,
			-drop(26) + 0.3,
			0,
		}),
		key(0.52, "In", P(crouch(26), arms({ 50, 0, 14 }, { 10, 0, 0 }), { Waist = { -20, 0, 0 } }), { 0, -drop(26), 0 }),
		key(0.8, "Back", TADA),
		key(1.1, "Sine", TADA),
		key(1.4, "InOut", STAND),
	},
})

---------------------------------------------------------------- 7 Victory dance

local HOP_UP: Pose = P(arms({ 160, 0, 24 }, { 6, 0, 0 }), rightLeg({ 24, 0, 0 }, { -46, 0, 0 }), leftLeg({ 24, 0, 0 }, { -46, 0, 0 }), {
	Neck = { 12, 0, 0 },
	Waist = { 6, 0, 0 },
})
local function landPull(spin: number): Pose
	return P(crouch(20), arms({ 28, 0, 26 }, { 112, 0, 0 }), { Root = { 0, spin, 0 }, Waist = { -8, 0, 0 }, Neck = { -6, 0, 0 } })
end
local function hop(spin: number): Pose
	return P(HOP_UP, { Root = { 0, spin, 0 } })
end
local SKY_POINT: Pose = P(crouch(14), rightArm({ 162, 0, 14 }), leftArm({ 26, 0, -24 }, { 110, 0, 0 }), { Neck = { 16, -8, 0 } })
EmoteConfig.Victory = emote({
	Name = "Victory",
	LoopFrom = 0.2,
	Duration = 0.2 + 2.2,
	Keys = {
		key(0, nil, STAND),
		key(0.2, "Out", hop(0), { 0, 0.5, 0 }),
		key(0.45, "In", landPull(0), { 0, -drop(20), 0 }),
		key(0.7, "Out", hop(0), { 0, 0.5, 0 }),
		key(0.95, "In", landPull(0), { 0, -drop(20), 0 }),
		key(
			1.25,
			"Out",
			P(arms({ 30, 0, 80 }, { 6, 0, 0 }), rightLeg({ 28, 0, 0 }, { -56, 0, 0 }), leftLeg({ 28, 0, 0 }, { -56, 0, 0 }), {
				Root = { 0, 120, 0 },
			}),
			{ 0, 0.7, 0 }
		),
		key(
			1.55,
			"Linear",
			P(arms({ 30, 0, 84 }, { 6, 0, 0 }), rightLeg({ 28, 0, 0 }, { -56, 0, 0 }), leftLeg({ 28, 0, 0 }, { -56, 0, 0 }), {
				Root = { 0, 300, 0 },
			}),
			{ 0, 0.7, 0 }
		),
		key(1.75, "In", P(SKY_POINT, { Root = { 0, 360, 0 } }), { 0, -drop(14), 0 }),
		key(2.1, "Sine", P(SKY_POINT, { Root = { 0, 360, 0 } }), { 0, -drop(14), 0 }),
		key(2.4, "Out", hop(360), { 0, 0.5, 0 }),
	},
	Outro = {
		key(0.25, "In", P(crouch(16), TADA), { 0, -drop(16), 0 }),
		key(0.5, "Back", TADA),
		key(1.0, "Sine", TADA),
		key(1.3, "InOut", STAND),
	},
})

---------------------------------------------------------------- 8 Air guitar

local STANCE: Pose = P(
	rightLeg({ 10, 0, 12 }, { -20, 0, 0 }, { 10, 0, -12 }),
	leftLeg({ 10, 0, -12 }, { -20, 0, 0 }, { 10, 0, 12 }),
	leftArm({ 66, 0, -34 }, { 26, 0, 0 })
)
local function guitar(strum: number, bang: number, down: number): Pose
	return P(STANCE, rightArm({ 34 + 8 * strum, 0, -6 }, { 84 + 14 * strum, 0, 0 }, { 10 * strum, 0, 0 }), {
		Waist = { 10 - 4 * down, -14, 0 },
		Neck = { bang, 8, 0 },
	})
end
local GUITAR_DOWN = { 0, -0.14, 0 }
local guitarKeys: { Key } = { key(0, nil, STAND), key(0.25, "Out", guitar(0, 4, 0), GUITAR_DOWN) }
for i = 1, 5 do
	-- strum and headbang on every beat
	local t = 0.25 + i * 0.2
	local even = i % 2 == 0
	table.insert(guitarKeys, key(t, "Sine", guitar(if even then 0 else 1, if even then 4 else -24, if even then 0 else 1), GUITAR_DOWN))
end
-- the big arm windmill: the strumming arm goes once round (X + 360)
table.insert(guitarKeys, key(1.5, "Out", P(guitar(0, 10, 0), rightArm({ 140, 0, 16 }), { Waist = { 16, -14, 0 } }), { 0, -0.06, 0 }))
-- ends where the loop starts (X 384 = 24): seamless
table.insert(guitarKeys, key(1.9, "In", P(guitar(0, 4, 0), rightArm({ 394, 0, -6 }, { 84, 0, 0 })), GUITAR_DOWN))
EmoteConfig.AirGuitar = emote({
	Name = "AirGuitar",
	LoopFrom = 0.25,
	Duration = 1.9,
	Keys = guitarKeys,
	Outro = {
		key(
			0.3,
			"Out",
			P(STANCE, rightArm({ 165, 0, 20 }), leftArm({ 120, 0, -20 }, { 20, 0, 0 }), { Waist = { 18, 0, 0 }, Neck = { 24, 0, 0 } }),
			{
				0,
				-0.1,
				0,
			}
		),
		key(
			0.85,
			"Sine",
			P(STANCE, rightArm({ 165, 0, 20 }), leftArm({ 120, 0, -20 }, { 20, 0, 0 }), { Waist = { 18, 0, 0 }, Neck = { 24, 0, 0 } }),
			{
				0,
				-0.1,
				0,
			}
		),
		key(1.15, "InOut", STAND),
	},
})

---------------------------------------------------------------- 9 Forge Hammer (game original: stomp and hammer)

local function hammerUp(rightKnee: boolean): Pose
	local up = { { 74, 0, 0 }, { -96, 0, 0 }, { 12, 0, 0 } }
	return P(
		arms({ 166, 0, -12 }, { 30, 0, 0 }),
		if rightKnee then rightLeg(up[1], up[2], up[3]) else leftLeg(up[1], up[2], up[3]),
		{ Waist = { 10, 0, 0 }, Neck = { 6, 0, 0 } }
	)
end
local HAMMER_SLAM: Pose = P(crouch(22), arms({ 58, 0, -10 }, { 4, 0, 0 }), { Waist = { -22, 0, 0 }, Neck = { -12, 0, 0 } })
local HAMMER_BOUNCE: Pose = P(crouch(12), arms({ 72, 0, -10 }, { 12, 0, 0 }), { Waist = { -14, 0, 0 }, Neck = { -6, 0, 0 } })
EmoteConfig.ForgeHammer = emote({
	Name = "ForgeHammer",
	LoopFrom = 0.3,
	Duration = 0.3 + 1.6,
	Keys = {
		key(0, nil, STAND),
		key(0.3, "Out", hammerUp(true)),
		key(0.68, "In", HAMMER_SLAM, { 0, -drop(22), 0 }),
		key(0.82, "Out", HAMMER_BOUNCE, { 0, -drop(12), 0 }),
		key(1.1, "InOut", hammerUp(false)),
		key(1.48, "In", HAMMER_SLAM, { 0, -drop(22), 0 }),
		key(1.62, "Out", HAMMER_BOUNCE, { 0, -drop(12), 0 }),
	},
	Outro = {
		-- one last big strike, held
		key(0.3, "Out", P(arms({ 170, 0, -10 }, { 24, 0, 0 }), { Waist = { 14, 0, 0 }, Neck = { 8, 0, 0 } })),
		key(
			0.55,
			"In",
			P(crouch(32), arms({ 64, 0, -8 }, { 0, 0, 0 }), { Waist = { -30, 0, 0 }, Neck = { -6, 0, 0 } }),
			{ 0, -drop(32), 0 }
		),
		key(
			1.05,
			"Linear",
			P(crouch(32), arms({ 64, 0, -8 }, { 0, 0, 0 }), { Waist = { -30, 0, 0 }, Neck = { -6, 0, 0 } }),
			{ 0, -drop(32), 0 }
		),
		key(1.4, "InOut", STAND),
	},
})

---------------------------------------------------------------- 10 Golem Stomp (game original)

local function golem(lean: number, lift: string?, bend: number): Pose
	local base = P(
		rightLeg({ bend, 0, 16 }, { -2 * bend, 0, 0 }, { bend, 0, -16 }),
		leftLeg({ bend, 0, -16 }, { -2 * bend, 0, 0 }, { bend, 0, 16 }),
		arms({ 16 + lean * 0.6, 0, 30 }, { 26, 0, 0 }),
		{ Root = { 0, -lean * 0.8, -lean }, Waist = { -14, 0, 0 }, Neck = { 12, 0, 0 } }
	)
	if lift == "Left" then
		return P(base, leftLeg({ 30, 0, -34 }, { -50, 0, 0 }, { 10, 0, 0 }))
	elseif lift == "Right" then
		return P(base, rightLeg({ 30, 0, 34 }, { -50, 0, 0 }, { 10, 0, 0 }))
	end
	return base
end
local GOLEM_POUND_BEND = 26
local CHEST_BEAT_R: Pose =
	P(crouch(12), rightArm({ 58, 0, -6 }, { 92, 0, 0 }), leftArm({ 40, 0, -6 }, { 66, 0, 0 }), { Waist = { 8, 0, 0 }, Neck = { 26, 0, 0 } })
local CHEST_BEAT_L: Pose =
	P(crouch(12), leftArm({ 58, 0, 6 }, { 92, 0, 0 }), rightArm({ 40, 0, 6 }, { 66, 0, 0 }), { Waist = { 8, 0, 0 }, Neck = { 26, 0, 0 } })
local GOLEM_DOWN = function(bend: number): Euler
	return { 0, -drop(bend) - 0.04, 0 }
end
local GOLEM_POUND: Pose =
	P(golem(0, nil, GOLEM_POUND_BEND), arms({ 74, 0, 14 }, { 0, 0, 0 }), { Waist = { -38, 0, 0 }, Neck = { 22, 0, 0 } })
EmoteConfig.GolemStomp = emote({
	Name = "GolemStomp",
	LoopFrom = 0.3,
	Duration = 0.3 + 2.4,
	Keys = {
		key(0, nil, STAND),
		key(0.3, "Out", golem(8, "Left", 16), { 0, -drop(16) + 0.08, 0 }),
		key(0.72, "In", golem(0, nil, 24), GOLEM_DOWN(24)),
		key(0.9, "Out", golem(0, nil, 16), GOLEM_DOWN(16)),
		key(1.2, "InOut", golem(-8, "Right", 16), { 0, -drop(16) + 0.08, 0 }),
		key(1.62, "In", golem(0, nil, 24), GOLEM_DOWN(24)),
		key(1.8, "Out", golem(0, nil, 16), GOLEM_DOWN(16)),
		key(2.15, "Out", P(golem(0, nil, 8), arms({ 162, 0, 22 }, { 10, 0, 0 }), { Waist = { 10, 0, 0 } }), GOLEM_DOWN(8)),
		key(2.42, "In", GOLEM_POUND, GOLEM_DOWN(GOLEM_POUND_BEND)),
	},
	Outro = {
		-- beat the chest and roar
		key(0.25, "Out", CHEST_BEAT_R, { 0, -drop(12), 0 }),
		key(0.45, "Out", CHEST_BEAT_L, { 0, -drop(12), 0 }),
		key(0.65, "Out", CHEST_BEAT_R, { 0, -drop(12), 0 }),
		key(0.85, "Out", CHEST_BEAT_L, { 0, -drop(12), 0 }),
		key(1.25, "Sine", P(CHEST_BEAT_L, { Neck = { 32, 0, 0 } }), { 0, -drop(12), 0 }),
		key(1.55, "InOut", STAND),
	},
})

---------------------------------------------------------------- 11 Gem Juggle (game original)

-- hands toss in turn (right, left, right, left) and catch on the outside
local function juggle(rightUp: boolean, look: number): Pose
	local toss = { { 58, 0, -6 }, { 64, 0, 0 }, { -16, 0, 0 } }
	local catch = { { 34, 0, 12 }, { 92, 0, 0 }, { 6, 0, 0 } }
	local r = if rightUp then toss else catch
	local l = if rightUp then catch else toss
	return P(
		rightArm(r[1], r[2], r[3]),
		leftArm(mirror(l[1]), mirror(l[2]), mirror(l[3])),
		crouch(6),
		{ Neck = { 18, look, 0 }, Waist = { 2, -look * 0.3, 0 } }
	)
end
local JUGGLE_DOWN = { 0, -drop(6), 0 }
local BOW: Pose = P(arms({ 30, 0, 2 }, { 58, 0, 0 }), { Waist = { -34, 0, 0 }, Neck = { -14, 0, 0 } })
EmoteConfig.GemJuggle = emote({
	Name = "GemJuggle",
	LoopFrom = 0.2,
	Duration = 0.2 + 1.2,
	Keys = {
		key(0, nil, STAND),
		key(0.2, "Out", juggle(true, -10), JUGGLE_DOWN),
		key(0.5, "Sine", juggle(false, 10), JUGGLE_DOWN),
		key(0.8, "Sine", juggle(true, -10), JUGGLE_DOWN),
		key(1.1, "Sine", juggle(false, 10), JUGGLE_DOWN),
	},
	Outro = {
		-- catch them all, then a bow
		key(0.25, "Out", P(arms({ 50, 0, 2 }, { 62, 0, 0 }), { Neck = { 4, 0, 0 } })),
		key(0.6, "InOut", BOW),
		key(1.0, "Sine", BOW),
		key(1.3, "InOut", STAND),
	},
})

---------------------------------------------------------------- 12 Blaster Spin (game original, needs the blaster in hand)

local COWBOY: Pose = P(
	rightLeg({ 0, 0, 8 }),
	leftLeg({ 6, 0, -8 }, { -10, 0, 0 }, { 4, 0, 0 }),
	leftArm({ -6, 0, -26 }, { 64, 0, 0 }),
	{ Waist = { 0, -8, 0 } }
)
local function blaster(shoulder: Euler, elbow: Euler, grip: number, extra: Pose?): Pose
	return P(COWBOY, rightArm(shoulder, elbow), { RightGrip = { grip, 0, 0 } }, extra or {})
end
local HIP = { 14, 0, 12 }
local HIP_ELBOW = { 34, 0, 0 }
EmoteConfig.BlasterSpin = emote({
	Name = "BlasterSpin",
	NeedsTool = true,
	LoopFrom = 0.2,
	Duration = 0.2 + 2.4,
	Keys = {
		key(0, nil, STAND),
		key(0.2, "Out", blaster(HIP, HIP_ELBOW, 0)),
		key(0.35, "Out", blaster({ 40, 0, 26 }, { 10, 0, 0 }, 0)),
		-- two fast twirls round the finger
		key(0.85, "Linear", blaster({ 46, 0, 28 }, { 14, 0, 0 }, -720)),
		-- flip it up: pointing at the sky
		key(1.05, "Out", blaster({ 160, 0, 14 }, { 0, 0, 0 }, -720, { Waist = { 8, -8, 0 }, Neck = { 16, -10, 0 } })),
		key(1.45, "Sine", blaster({ 156, 0, 16 }, { 4, 0, 0 }, -720, { Waist = { 6, -8, 0 }, Neck = { 14, -10, 0 } })),
		-- down to aim
		key(1.7, "InOut", blaster({ 90, 0, 0 }, { 0, 0, 0 }, -720, { Waist = { 0, 10, 0 }, Neck = { 0, 8, 0 } })),
		key(1.95, "Sine", blaster({ 92, 0, 0 }, { 0, 0, 0 }, -720, { Waist = { 2, 10, 0 }, Neck = { 2, 8, 0 } })),
		-- one more twirl back to the hip
		key(2.4, "Linear", blaster({ 30, 0, 18 }, { 20, 0, 0 }, -1080)),
		key(2.6, "Out", blaster(HIP, HIP_ELBOW, -1080)),
	},
	Outro = {
		-- holster it and tip the hat
		key(0.3, "Out", P(COWBOY, rightArm({ 4, 0, 8 }, { 10, 0, 0 }), leftArm({ 152, 0, -8 }, { 104, 0, 0 }), { Neck = { -8, 0, 0 } })),
		key(0.9, "Sine", P(COWBOY, rightArm({ 4, 0, 8 }, { 10, 0, 0 }), leftArm({ 152, 0, -8 }, { 104, 0, 0 }), { Neck = { -10, 0, 0 } })),
		key(1.2, "InOut", STAND),
	},
})

---------------------------------------------------------------- the list

EmoteConfig.List = {
	"Breakdance",
	"Headspin",
	"Robot",
	"DiscoPoint",
	"BackGlide",
	"Worm",
	"Victory",
	"AirGuitar",
	"ForgeHammer",
	"GolemStomp",
	"GemJuggle",
	"BlasterSpin",
}

-- name -> the emote (also EmoteConfig[name])
EmoteConfig.Emotes = {} :: { [string]: Move }
for _, name in EmoteConfig.List do
	EmoteConfig.Emotes[name] = (EmoteConfig :: any)[name]
end

-- the owner's Czech captions (the preview video and sheet)
EmoteConfig.Captions = {
	Breakdance = "Breakdance: větrník + freeze",
	Headspin = "Točení na hlavě",
	Robot = "Robot: trhaný robotí tanec",
	DiscoPoint = "Disko: ukazování nahoru a dolů",
	BackGlide = "Klouzání pozpátku + špičky",
	Worm = "Červík: vlna po zemi",
	Victory = "Vítězný tanec: skoky + otočka",
	AirGuitar = "Vzdušná kytara + headbang",
	ForgeHammer = "Kovářský dupák: dupnutí a úder kladivem",
	GolemStomp = "Golemí dupání: těžké kroky + bušení do hrudi",
	GemJuggle = "Žonglování se třemi drahokamy",
	BlasterSpin = "Kovbojské točení blasterem (jen s blasterem v ruce)",
} :: { [string]: string }

return EmoteConfig
