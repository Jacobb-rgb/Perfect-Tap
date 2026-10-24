--[[
	BoardPose: the hoverboard riding pose (owner 2026-10-24: "when I equip it
	there's no cool animation, it looks like I'm bugged onto a flying thing").
	Pure math: a procedural R15 pose for MoveRig (HoverboardController lays it
	over every rider near you with Override on every joint, so the walk / idle
	animation never shows through).

	  Ride   a surfer stance: the body turned side-on (left foot forward),
	         knees bent, arms out for balance, the head looking where you go.
	         It breathes and sways; with speed you crouch lower and lean
	         forward, the front arm points ahead and the back arm sweeps back;
	         in turns you lean into the turn
	  Mount  hopping on (the first MountTime seconds): a crouch, a jump that
	         turns you into the stance while the board flies in under you, a
	         squashy landing
	  Air    in a jump: knees tucked up, arms up and out (the board kickflips)
	  Land   touching down: a short squash

	State (numbers, 0..1 unless said):
	  T      seconds (the sway)
	  Speed  speed / the board's top speed
	  Turn   -1 (hard left) .. 1 (hard right)
	  Mount  hop-on progress (1 = done, riding)
	  Air    airborne amount (0 = on the board, 1 = fully tucked)
	  Land   landing squash (1 = just landed, decays to 0)

	Joint frames as in Config/MoveConfig: x pitch (limbs forward +, knees bend
	-, torso leans BACK +), y yaw (turns LEFT +), z roll (toward the right +;
	the right arm / leg out is +, the left one -). The Root's pose is
	CFrame.new(offset) * tilt * yaw: the body drops by the crouch so the feet
	stay on the deck (the HumanoidRootPart and the physics never move).
]]

local MoveConfig = require(script.Parent.Parent.Config.MoveConfig)

local BoardPose = {}

export type State = {
	T: number,
	Speed: number,
	Turn: number,
	Mount: number,
	Air: number,
	Land: number,
}
export type Pose = { [string]: CFrame }

BoardPose.MountTime = 0.6 -- seconds of the hop-on
BoardPose.LandTime = 0.35 -- seconds the landing squash lasts
BoardPose.Stance = -72 -- degrees the body turns (to the right: left foot forward)
BoardPose.Crouch = 24 -- degrees of knee bend at rest
BoardPose.SpeedCrouch = 12 -- more at top speed
BoardPose.Spread = 15 -- degrees each leg is out (feet apart along the deck)

-- every joint the pose drives (all of them: Override, nothing of the walk shows)
BoardPose.Joints = MoveConfig.Joints

local rad = math.rad
local sin = math.sin

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The hop-on split into its parts: (crouch prep 0..1, jump height 0..1, turn into the stance 0..1, landing squash 0..1).
function BoardPose.mountPhases(u: number): (number, number, number, number)
	local m = math.clamp(u, 0, 1)
	local prep = if m < 0.2 then smooth(m / 0.2) elseif m < 0.3 then 1 - smooth((m - 0.2) / 0.1) else 0
	local jump = if m >= 0.25 and m < 0.75 then sin(math.pi * (m - 0.25) / 0.5) else 0
	local turn = smooth((m - 0.25) / 0.45)
	local land = if m >= 0.72 then 1 - smooth((m - 0.72) / 0.28) else 0
	return prep, jump, turn, land
end

--[[
	Fills `out` (or a new table) with a CFrame for every joint and returns it.
	No tables are made when `out` is passed (the CFrames are new values).
]]
function BoardPose.evaluate(state: State, out: Pose?): Pose
	local pose: Pose = out or {}
	local t = state.T
	local speed = math.clamp(state.Speed, 0, 1)
	local turn = math.clamp(state.Turn, -1, 1)
	local air = math.clamp(state.Air, 0, 1)
	local prep, jump, stanceTurn, mountLand = BoardPose.mountPhases(state.Mount)
	local squash = math.max(math.clamp(state.Land, 0, 1), mountLand)

	-- breathing / balance sway (slower and smaller at speed)
	local sway = sin(t * 2.2)
	local sway2 = sin(t * 1.3 + 1.1)
	local calm = 1 - 0.5 * speed

	-- knees: rest crouch, deeper with speed, a squash on landing, tucked in the air
	local crouch = BoardPose.Crouch + BoardPose.SpeedCrouch * speed + 2.5 * sway * calm
	crouch += 22 * squash + 14 * prep
	crouch = lerp(crouch, 58, air)
	crouch = lerp(crouch, 50, jump)
	local drop = MoveConfig.crouchDrop(crouch)
	-- the hop on: up and over; in a jump the feet come up off the deck so the board can flip
	-- (the whole body, visual only: crouch drop + lift = how high the feet are)
	local lift = 1.5 * jump + 0.75 * air
	-- the forward lean and the turn roll tip the toes and heels down: up a touch so they stay on the deck
	lift += 0.12 * speed + 0.06 * math.abs(turn)

	-- the body: side-on, leaning forward with speed and into turns
	local stance = BoardPose.Stance * stanceTurn
	local lean = -(6 + 14 * speed) * stanceTurn + 4 * sway2 * calm
	local roll = 16 * turn -- the same way the board rolls into the turn
	pose.Root = CFrame.new(0, lift - drop, 0) * angles(lean, 0, roll) * angles(0, stance, 0)
	-- the chest turns a little back toward where you go, the head all the way
	pose.Waist = angles(-4 - 8 * speed + 3 * sway, -0.22 * stance, 3 * sway2 * calm)
	pose.Neck = angles(4 + 10 * speed, -0.62 * stance + 8 * turn, 0)

	-- legs apart along the deck, knees bent (the formula of MoveConfig crouch: thigh a, knee -2a, ankle a)
	local spread = BoardPose.Spread * (0.4 + 0.6 * stanceTurn) * (1 - 0.5 * air)
	local front, back = crouch + 4, crouch - 2
	pose.LeftHip = angles(front, 0, -spread)
	pose.LeftKnee = angles(-2 * front, 0, 0)
	pose.LeftAnkle = angles(front, 0, spread)
	pose.RightHip = angles(back, 0, spread)
	pose.RightKnee = angles(-2 * back, 0, 0)
	pose.RightAnkle = angles(back, 0, -spread)

	-- arms out for balance; with speed the front (left) arm points ahead and the back arm sweeps back;
	-- up and wide in the air, wide on a landing
	local wave = 6 * sway * calm
	local lUp = lerp(lerp(62, 40, speed), 120, air) + 20 * squash + wave
	local rUp = lerp(lerp(62, 30, speed), 120, air) + 20 * squash - wave
	pose.LeftShoulder = angles(lerp(18, 70, speed) * (1 - air), 0, -lUp)
	pose.LeftElbow = angles(lerp(28, 6, speed), 0, 0)
	pose.LeftWrist = angles(0, 0, -6 * sway2)
	pose.RightShoulder = angles(lerp(10, -48, speed) * (1 - air), 0, rUp)
	pose.RightElbow = angles(lerp(30, 12, speed), 0, 0)
	pose.RightWrist = angles(0, 0, 6 * sway2)
	-- the very start of the hop on eases out of the plain standing pose
	local enter = BoardPose.weight(state.Mount)
	if enter < 1 then
		for joint, cf in pose do
			pose[joint] = CFrame.identity:Lerp(cf, enter)
		end
	end
	return pose
end

-- How far the riding pose has taken over (0..1): it eases in at the very start of the hop on.
function BoardPose.weight(mount: number): number
	return smooth(mount / 0.12)
end

-- The board's own move during the hop-on (in its rest frame): rising from below with a spin.
-- (height offset in studs, spin in radians)
function BoardPose.boardMount(u: number): (number, number)
	local m = math.clamp(u / 0.75, 0, 1)
	-- back-out: overshoots a little, then settles
	local c1, c3 = 1.70158, 2.70158
	local x = m - 1
	local e = 1 + c3 * x * x * x + c1 * x * x
	return -2.4 * (1 - e), (1 - smooth(m)) * math.pi * 2
end

-- The kickflip while airborne: the board's roll (radians) at `s` seconds into the jump.
BoardPose.FlipTime = 0.45
BoardPose.FlipPivot = 1.1 -- studs above the board's Root (the ground): it rolls about its own middle
function BoardPose.flip(s: number): number
	return smooth(s / BoardPose.FlipTime) * math.pi * 2
end

-- The kickflip as a turn of the board's frame (about its middle, not the ground under it).
function BoardPose.flipFrame(roll: number): CFrame
	if roll == 0 then
		return CFrame.identity
	end
	return CFrame.new(0, BoardPose.FlipPivot, 0) * CFrame.Angles(0, 0, roll) * CFrame.new(0, -BoardPose.FlipPivot, 0)
end

return BoardPose
