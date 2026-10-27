--[[
	The player's moves (owner 2026-10-21: "perfect and suitable animations
	for Terra Forge"): procedural R15 poses, no uploaded animation assets.
	Pure data; Moves/MoveMath evaluates them, Moves/MoveRig layers them onto
	any R15 rig's Motor6D.Transform (players: MoveController; quest NPCs can
	use the same moves later), Moves/MoveRules holds the trigger rules.

	A move:
	  Duration  seconds (a loop repeats every Duration)
	  Loop      true = repeats until stopped (Carry, Spray)
	  Slot      "Loop" | "Action" | "Kick": one move per slot on a character;
	            Action plays over the Loop (a Throw while carrying), Kick
	            (Recoil) is a small additive jolt over both
	  BlendIn / BlendOut  seconds to fade in / out (smoothstep weights)
	  Override  joints whose pose REPLACES the walk / idle animation (the
	            arms of a hug stay still while the legs keep walking); every
	            other joint ADDS on top of it (Transform = animated * move)
	  MinGap    the server plays this move at most once per MinGap seconds
	  Priority  a move only replaces a running move of its slot with the same
	            or a lower Priority (a shrug never cuts a celebration short;
	            a throw and the celebrations replace each other)
	  Keys      { T, Ease, Pose, Offset }, T in seconds from 0 (sorted). Ease
	            is the curve INTO that key from the key before (MoveMath
	            Eases: Linear, In, Out, InOut, Sine, Back). Pose = { [joint] =
	            { x, y, z } } in degrees; a joint the move uses but a key
	            leaves out is at rest (0, 0, 0) in that key. Offset = the
	            Root's { x, y, z } in studs (the whole body, a visual hop:
	            the HumanoidRootPart and the physics never move)

	Angles are in the joint's own frame (Motor6D C0: R15 joints have no C0
	rotation, so +X is the character's right, +Y up, -Z forward), applied as
	CFrame.Angles(x, y, z):
	  x  pitch: arms and legs swing FORWARD (+), knees bend with -, ankles
	     point the toes down with -; the torso and head lean BACK with +
	  y  yaw: turns to the character's LEFT (+); on the Root a spin
	  z  roll: toward the character's RIGHT (+): the right arm out, the left
	     arm across the chest; the left arm out is -; torso / head lean
	     LEFT with +
	mirror() turns a right-side pose into the left side (x, -y, -z).

	The Root (the whole body) turns in YXZ order: y spins about the
	vertical, after x tilts it (so a body lying down still spins flat on
	the floor, a windmill or a headspin). Optional, for floor moves and
	emotes (Config/EmoteConfig):
	  RootPivot  { x, y, z } studs from the Root joint: the point the
	             Root turns about (the top of the head for a headspin;
	             default the joint itself, at the hips)
	  LoopFrom   a loop's keys before this time play once (an intro), the
	             loop repeats from the key at LoopFrom to Duration. A loop's
	             last key may sit AT Duration (a spin ending at 360 = its
	             first key), else the loop eases from it back to LoopFrom
	  Outro      keys played once the loop is stopped, T from the stop
	             (the first one eases from the pose at the stop, every
	             angle taken the short way); the last one should be rest
	  NeedsTool  the move needs a held tool (the Blaster Spin)
	ToolJoints are extra pose names MoveRig never finds on a body (the
	held tool's grip, RightGrip: a turn about the hand, for the preview
	and a later grip-weld hook).
]]

export type Euler = { number }
export type Pose = { [string]: Euler }
export type Key = { T: number, Ease: string?, Pose: Pose?, Offset: Euler? }
export type Move = {
	Name: string,
	Duration: number,
	Loop: boolean,
	Slot: string,
	BlendIn: number,
	BlendOut: number,
	Override: { string },
	MinGap: number,
	Priority: number,
	Keys: { Key },
	RootPivot: Euler?,
	LoopFrom: number?,
	Outro: { Key }?,
	NeedsTool: boolean?,
}

local MoveConfig = {}

-- character attribute "<Name>:<seq>" (the server sets it, every client plays it)
MoveConfig.Attribute = "Move"
-- character attribute: the loop the server says this character plays ("Spray"), nil = none
MoveConfig.LoopAttribute = "MoveLoop"
-- the player attribute CarryService keeps (Carry loop while > 0)
MoveConfig.CarryAttribute = "CarryCount"

-- R15 joints, parents before children. JointPart = the part holding that Motor6D.
MoveConfig.Joints = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}
-- pose names that are not R15 Motor6Ds (MoveMath evaluates them, MoveRig never finds them)
MoveConfig.ToolJoints = { "RightGrip" }
MoveConfig.JointPart = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
} :: { [string]: string }

-- Client side
MoveConfig.Range = 70 -- studs from the camera: farther characters get no moves at all
MoveConfig.CheckInterval = 0.25 -- seconds between range / on-screen / state checks
MoveConfig.PendingSeconds = 8 -- a celebration of yours that came during a close-up plays when it ends, if within this
MoveConfig.RecoilRepeat = 0.22 -- seconds between recoil kicks while the beam stays on
MoveConfig.RecoilRepeatWeight = 0.55 -- the repeat kicks are smaller than the first one
MoveConfig.ShrugGap = 2.5 -- seconds: at most one shrug per this (refusals can come in bursts)
-- Reduce Motion (the game's SETTINGS toggle SettingsConfig.ReduceMotion, or Roblox's own
-- GuiService.ReducedMotionEnabled), for what THIS viewer sees: the celebrations become calmer
-- moves (a small bounce, no crouch, no spin), the optional Extras are skipped; Carry, Throw,
-- Recoil and Spray stay (they are the game's feedback)
MoveConfig.ReducedMotion = {
	BigCelebrate = "CelebrateCalm",
	Celebrate = "CelebrateCalm",
	CashToss = "CashTossCalm",
} :: { [string]: string }
-- optional extras: skipped with Reduce Motion, and while a tool is in hand or the blaster
-- fires (they take over the arm holding it: the beam starts at its muzzle)
MoveConfig.Extras = { Wave = true, Shrug = true } :: { [string]: boolean }
MoveConfig.FiringHold = 0.6 -- seconds after another player's last BlastHit their gun arm counts as firing

-- Server side
MoveConfig.ClientMoves = { Wave = true, Shrug = true } :: { [string]: boolean } -- the Net "Move" whitelist (no Throw since the backpacks)
MoveConfig.MaxNameLength = 24
MoveConfig.LoopPoll = 0.4 -- seconds between the server's loop checks (cleaning -> Spray)
MoveConfig.BigSell = { Items = 5, Window = 0.4 } -- a sale of at least Items within Window seconds at Tobin's -> CashToss
MoveConfig.SellRange = 30 -- studs from a SellCounter that count as "at Tobin's"
MoveConfig.BigFrom = "Legendary" -- this rarity and up: BigCelebrate (ores cleaned, golems woken)

local function mirror(e: Euler): Euler
	return { e[1], -e[2], -e[3] }
end
MoveConfig.mirror = mirror

-- both arms from the right arm's pose (and the elbow / wrist)
local function arms(pose: Pose, shoulder: Euler, elbow: Euler?, wrist: Euler?): Pose
	pose.RightShoulder = shoulder
	pose.LeftShoulder = mirror(shoulder)
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

-- legs bent by `a` degrees with the feet still on the ground (thigh forward a,
-- knee -2a, ankle a): with the Root down by about 1.87 * (1 - cos a) studs
local function crouch(pose: Pose, a: number): Pose
	pose.RightHip = { a, 0, 0 }
	pose.LeftHip = { a, 0, 0 }
	pose.RightKnee = { -2 * a, 0, 0 }
	pose.LeftKnee = { -2 * a, 0, 0 }
	pose.RightAnkle = { a, 0, 0 }
	pose.LeftAnkle = { a, 0, 0 }
	return pose
end
MoveConfig.crouchDrop = function(a: number): number
	return 1.87 * (1 - math.cos(math.rad(a)))
end
local drop = MoveConfig.crouchDrop

local ARMS = { "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist" }
local RIGHT_ARM = { "RightShoulder", "RightElbow", "RightWrist" }

local function with(pose: Pose, extra: Pose): Pose
	for joint, value in extra do
		pose[joint] = value
	end
	return pose
end

MoveConfig.Moves = {
	-- carrying ore (CarryCount > 0): both arms forward hugging the chunk, a slight lean back
	Carry = {
		Name = "Carry",
		Duration = 1.2,
		Loop = true,
		Slot = "Loop",
		BlendIn = 0.18,
		BlendOut = 0.22,
		Override = ARMS,
		MinGap = 0,
		Priority = 0,
		Keys = {
			{
				T = 0,
				Ease = "Sine",
				Pose = with(arms({}, { 74, 0, -16 }, { 28, 0, 0 }, { 0, 0, 0 }), { Waist = { 6, 0, 0 }, Neck = { -3, 0, 0 } }),
			},
			{
				T = 0.6,
				Ease = "Sine",
				Pose = with(arms({}, { 78, 0, -16 }, { 24, 0, 0 }, { 0, 0, 0 }), { Waist = { 8, 0, 0 }, Neck = { -2, 0, 0 } }),
			},
		},
	},
	-- the throw input (Q / RB / Throw button): two-arm wind-up overhead, the throw with a twist, follow-through
	Throw = {
		Name = "Throw",
		Duration = 0.45,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.04,
		BlendOut = 0.1,
		Override = ARMS,
		MinGap = 0.2,
		Priority = 2,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.13,
				Ease = "Out",
				Pose = with(arms({}, { 160, 0, -10 }, { 40, 0, 0 }), {
					Waist = { 14, -8, 0 },
					Neck = { 6, 0, 0 },
					Root = { 0, -6, 0 },
				}),
				Offset = { 0, -0.12, 0 },
			},
			{
				T = 0.22,
				Ease = "In",
				Pose = with(arms({}, { 72, 0, -8 }, { 6, 0, 0 }), {
					Waist = { -18, 14, 0 },
					Neck = { -6, 0, 0 },
					Root = { 0, 8, 0 },
				}),
			},
			{
				T = 0.32,
				Ease = "Out",
				Pose = with(arms({}, { 42, 0, -2 }, { 22, 0, 0 }), {
					Waist = { -20, 10, 0 },
					Neck = { -4, 0, 0 },
					Root = { 0, 6, 0 },
				}),
			},
			{ T = 0.45, Ease = "InOut", Pose = {} },
		},
	},
	-- every blaster shot: the gun arm kicks up, a tiny torso jolt (adds on top of the tool hold)
	Recoil = {
		Name = "Recoil",
		Duration = 0.12,
		Loop = false,
		Slot = "Kick",
		BlendIn = 0,
		BlendOut = 0,
		Override = {},
		MinGap = 0,
		Priority = 0,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.03,
				Ease = "Out",
				Pose = {
					RightShoulder = { 5, 0, 0 },
					RightElbow = { 5, 0, 0 },
					RightWrist = { 3, 0, 0 },
					Waist = { 3, 0, 0 },
					Neck = { 1.5, 0, 0 },
				},
			},
			{ T = 0.12, Ease = "InOut", Pose = {} },
		},
	},
	-- cleaning at the station (others see it: your own camera is in the close-up)
	Spray = {
		Name = "Spray",
		Duration = 0.5,
		Loop = true,
		Slot = "Loop",
		BlendIn = 0.2,
		BlendOut = 0.2,
		Override = RIGHT_ARM,
		MinGap = 0,
		Priority = 0,
		Keys = {
			{
				T = 0,
				Ease = "Sine",
				Pose = { RightShoulder = { 72, -12, -6 }, RightElbow = { 14, 0, 0 }, RightWrist = { -10, 0, 0 }, Waist = { 0, -4, 0 } },
			},
			{
				T = 0.25,
				Ease = "Sine",
				Pose = { RightShoulder = { 66, 12, -6 }, RightElbow = { 18, 0, 0 }, RightWrist = { -4, 0, 0 }, Waist = { 0, 4, 0 } },
			},
		},
	},
	-- a new ore or a Flawless grade: a crouch, a hop with both arms up, a fist pump
	Celebrate = {
		Name = "Celebrate",
		Duration = 1.2,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.06,
		BlendOut = 0.16,
		Override = ARMS,
		MinGap = 0.8,
		Priority = 2,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.14,
				Ease = "Out",
				Pose = with(crouch(arms({}, { -22, 0, 12 }, { 20, 0, 0 }), 26), { Waist = { -8, 0, 0 } }),
				Offset = { 0, -drop(26), 0 },
			},
			{
				T = 0.34,
				Ease = "Back",
				Pose = with(arms({}, { 168, 0, 22 }, { 8, 0, 0 }), {
					Waist = { 8, 0, 0 },
					Neck = { 12, 0, 0 },
					RightHip = { 14, 0, 0 },
					LeftHip = { 24, 0, 0 },
					RightKnee = { -24, 0, 0 },
					LeftKnee = { -44, 0, 0 },
					RightAnkle = { -14, 0, 0 },
					LeftAnkle = { -10, 0, 0 },
				}),
				Offset = { 0, 0.85, 0 },
			},
			{
				T = 0.52,
				Ease = "In",
				Pose = with(crouch(arms({}, { 150, 0, 26 }, { 14, 0, 0 }), 18), { Waist = { 4, 0, 0 }, Neck = { 8, 0, 0 } }),
				Offset = { 0, -drop(18), 0 },
			},
			-- the fist pump: the elbow pulled down to the side, the fist by the chest ("yes!")
			{
				T = 0.68,
				Ease = "Out",
				Pose = {
					RightShoulder = { 22, 0, 24 },
					RightElbow = { 118, 0, 0 },
					LeftShoulder = { 6, 0, -10 },
					LeftElbow = { 16, 0, 0 },
					Waist = { -8, 8, 0 },
					Neck = { -6, 4, 0 },
				},
			},
			{
				T = 0.84,
				Ease = "Out",
				Pose = {
					RightShoulder = { 128, 0, 22 },
					RightElbow = { 40, 0, 0 },
					LeftShoulder = { 6, 0, -10 },
					LeftElbow = { 16, 0, 0 },
					Waist = { 2, 4, 0 },
					Neck = { 4, 2, 0 },
				},
			},
			{
				T = 0.98,
				Ease = "Out",
				Pose = {
					RightShoulder = { 22, 0, 24 },
					RightElbow = { 118, 0, 0 },
					LeftShoulder = { 6, 0, -10 },
					LeftElbow = { 16, 0, 0 },
					Waist = { -8, 8, 0 },
					Neck = { -6, 4, 0 },
				},
			},
			{ T = 1.2, Ease = "InOut", Pose = {} },
		},
	},
	-- Legendary / Mythic, a rebirth, a new blaster level: a jump with a full spin, arms out, a ta-da landing
	BigCelebrate = {
		Name = "BigCelebrate",
		Duration = 1.6,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.06,
		BlendOut = 0.2,
		Override = ARMS,
		MinGap = 1.2,
		Priority = 2,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.16,
				Ease = "Out",
				Pose = with(crouch(arms({}, { -36, 0, 14 }, { 15, 0, 0 }), 32), { Waist = { -12, 0, 0 }, Neck = { 4, 0, 0 } }),
				Offset = { 0, -drop(32), 0 },
			},
			{
				T = 0.36,
				Ease = "Out",
				Pose = with(arms({}, { 20, 0, 82 }, { 6, 0, 0 }), {
					Root = { 0, 110, 0 },
					Waist = { 4, 0, 0 },
					Neck = { 6, 0, 0 },
					RightHip = { 30, 0, 0 },
					LeftHip = { 30, 0, 0 },
					RightKnee = { -62, 0, 0 },
					LeftKnee = { -62, 0, 0 },
					RightAnkle = { -10, 0, 0 },
					LeftAnkle = { -10, 0, 0 },
				}),
				Offset = { 0, 1.35, 0 },
			},
			{
				T = 0.62,
				Ease = "Linear",
				Pose = with(arms({}, { 20, 0, 86 }, { 4, 0, 0 }), {
					Root = { 0, 280, 0 },
					Waist = { 4, 0, 0 },
					Neck = { 6, 0, 0 },
					RightHip = { 34, 0, 0 },
					LeftHip = { 34, 0, 0 },
					RightKnee = { -70, 0, 0 },
					LeftKnee = { -70, 0, 0 },
					RightAnkle = { -10, 0, 0 },
					LeftAnkle = { -10, 0, 0 },
				}),
				Offset = { 0, 1.45, 0 },
			},
			{
				T = 0.84,
				Ease = "In",
				Pose = with(crouch(arms({}, { 60, 0, 50 }, { 20, 0, 0 }), 30), { Root = { 0, 360, 0 }, Waist = { -10, 0, 0 } }),
				Offset = { 0, -drop(30), 0 },
			},
			{
				T = 1.08,
				Ease = "Back",
				Pose = with(arms({}, { 160, 0, 38 }, { 6, 0, 0 }, { 0, 0, 0 }), {
					Root = { 0, 360, 0 },
					Waist = { 10, 0, 0 },
					Neck = { 12, 0, 0 },
				}),
			},
			{
				T = 1.36,
				Ease = "Sine",
				Pose = with(arms({}, { 154, 0, 40 }, { 10, 0, 0 }), {
					Root = { 0, 360, 0 },
					Waist = { 8, 0, 0 },
					Neck = { 10, 0, 0 },
				}),
			},
			{ T = 1.6, Ease = "InOut", Pose = { Root = { 0, 360, 0 } } },
		},
	},
	-- a big sell at Tobin's: a scoop down, both arms toss up ("money rain")
	CashToss = {
		Name = "CashToss",
		Duration = 0.9,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.05,
		BlendOut = 0.16,
		Override = ARMS,
		MinGap = 1,
		Priority = 2,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.16,
				Ease = "Out",
				Pose = with(
					crouch(arms({}, { 26, 0, -3 }, { 44, 0, 0 }, { 16, 0, 0 }), 16),
					{ Waist = { -14, 0, 0 }, Neck = { -6, 0, 0 } }
				),
				Offset = { 0, -drop(16), 0 },
			},
			{
				T = 0.32,
				Ease = "Back",
				Pose = with(arms({}, { 170, 0, 28 }, { 0, 0, 0 }, { -10, 0, 0 }), {
					Waist = { 10, 0, 0 },
					Neck = { 18, 0, 0 },
					RightAnkle = { -16, 0, 0 },
					LeftAnkle = { -16, 0, 0 },
				}),
				Offset = { 0, 0.2, 0 },
			},
			{
				T = 0.6,
				Ease = "Sine",
				Pose = with(arms({}, { 164, 0, 34 }, { 8, 0, 0 }, { 14, 0, 0 }), { Waist = { 8, 0, 0 }, Neck = { 16, 0, 0 } }),
			},
			{ T = 0.9, Ease = "InOut", Pose = {} },
		},
	},
	-- a golem equipped: a friendly wave
	Wave = {
		Name = "Wave",
		Duration = 1.2,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.06,
		BlendOut = 0.16,
		Override = RIGHT_ARM,
		MinGap = 1,
		Priority = 1,
		Keys = {
			{ T = 0, Pose = {} },
			{ T = 0.18, Ease = "Out", Pose = { RightShoulder = { 10, 0, 134 }, RightElbow = { 24, 0, 0 }, Neck = { 0, 0, -6 } } },
			{ T = 0.38, Ease = "Sine", Pose = { RightShoulder = { 10, 0, 108 }, RightElbow = { 36, 0, 0 }, Neck = { 0, 0, -6 } } },
			{ T = 0.58, Ease = "Sine", Pose = { RightShoulder = { 10, 0, 136 }, RightElbow = { 22, 0, 0 }, Neck = { 0, 0, -6 } } },
			{ T = 0.78, Ease = "Sine", Pose = { RightShoulder = { 10, 0, 108 }, RightElbow = { 36, 0, 0 }, Neck = { 0, 0, -6 } } },
			{ T = 0.96, Ease = "Sine", Pose = { RightShoulder = { 10, 0, 132 }, RightElbow = { 24, 0, 0 }, Neck = { 0, 0, -6 } } },
			{ T = 1.2, Ease = "InOut", Pose = {} },
		},
	},
	-- a refused action ("Deny"): palms up, head tilted
	Shrug = {
		Name = "Shrug",
		Duration = 0.9,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.05,
		BlendOut = 0.16,
		Override = ARMS,
		MinGap = 1,
		Priority = 1,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.2,
				Ease = "Back",
				Pose = with(arms({}, { 12, 0, 28 }, { 80, 0, 0 }, { 0, 0, 0 }), { Neck = { 0, 0, 14 }, Waist = { 0, 0, -3 } }),
				Offset = { 0, 0.08, 0 },
			},
			{
				T = 0.62,
				Ease = "Sine",
				Pose = with(arms({}, { 10, 0, 30 }, { 76, 0, 0 }, { 0, 0, 0 }), { Neck = { 0, 0, 12 }, Waist = { 0, 0, -3 } }),
				Offset = { 0, 0.06, 0 },
			},
			{ T = 0.9, Ease = "InOut", Pose = {} },
		},
	},
	-- Reduce Motion: Celebrate and BigCelebrate become this (a small bounce, no crouch, no spin)
	CelebrateCalm = {
		Name = "CelebrateCalm",
		Duration = 1.0,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.08,
		BlendOut = 0.18,
		Override = ARMS,
		MinGap = 0.8,
		Priority = 2,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.2,
				Ease = "Out",
				Pose = with(arms({}, { 148, 0, 20 }, { 12, 0, 0 }), {
					Waist = { 5, 0, 0 },
					Neck = { 8, 0, 0 },
					RightAnkle = { -8, 0, 0 },
					LeftAnkle = { -8, 0, 0 },
				}),
				Offset = { 0, 0.22, 0 },
			},
			{ T = 0.38, Ease = "InOut", Pose = with(arms({}, { 138, 0, 22 }, { 14, 0, 0 }), { Waist = { 4, 0, 0 }, Neck = { 6, 0, 0 } }) },
			{
				T = 0.58,
				Ease = "Out",
				Pose = {
					RightShoulder = { 22, 0, 24 },
					RightElbow = { 118, 0, 0 },
					LeftShoulder = { 6, 0, -10 },
					LeftElbow = { 16, 0, 0 },
					Waist = { -4, 6, 0 },
					Neck = { -4, 4, 0 },
				},
			},
			{
				T = 0.8,
				Ease = "Sine",
				Pose = {
					RightShoulder = { 26, 0, 24 },
					RightElbow = { 112, 0, 0 },
					LeftShoulder = { 6, 0, -10 },
					LeftElbow = { 16, 0, 0 },
					Waist = { -3, 5, 0 },
					Neck = { -3, 3, 0 },
				},
			},
			{ T = 1.0, Ease = "InOut", Pose = {} },
		},
	},
	-- Reduce Motion: CashToss becomes this (the arms toss up, no crouch, no hop)
	CashTossCalm = {
		Name = "CashTossCalm",
		Duration = 0.8,
		Loop = false,
		Slot = "Action",
		BlendIn = 0.06,
		BlendOut = 0.16,
		Override = ARMS,
		MinGap = 1,
		Priority = 2,
		Keys = {
			{ T = 0, Pose = {} },
			{ T = 0.16, Ease = "Out", Pose = with(arms({}, { 30, 0, -3 }, { 40, 0, 0 }, { 14, 0, 0 }), { Waist = { -6, 0, 0 } }) },
			{
				T = 0.34,
				Ease = "Out",
				Pose = with(arms({}, { 158, 0, 26 }, { 4, 0, 0 }, { -8, 0, 0 }), { Waist = { 6, 0, 0 }, Neck = { 12, 0, 0 } }),
			},
			{
				T = 0.56,
				Ease = "Sine",
				Pose = with(arms({}, { 152, 0, 30 }, { 8, 0, 0 }, { 10, 0, 0 }), { Waist = { 5, 0, 0 }, Neck = { 10, 0, 0 } }),
			},
			{ T = 0.8, Ease = "InOut", Pose = {} },
		},
	},
} :: { [string]: Move }

-- the order of the preview showreel and the tests
MoveConfig.List = {
	"Carry",
	"Throw",
	"Recoil",
	"Spray",
	"Celebrate",
	"BigCelebrate",
	"CashToss",
	"Wave",
	"Shrug",
	"CelebrateCalm",
	"CashTossCalm",
}

return MoveConfig
