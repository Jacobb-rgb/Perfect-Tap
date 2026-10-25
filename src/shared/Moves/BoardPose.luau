--[[
	BoardPose: the hoverboard riding pose (owner 2026-10-24: "when I equip it
	there's no cool animation, it looks like I'm bugged onto a flying thing").
	Pure math: a procedural R15 pose for MoveRig (HoverboardController lays it
	over every rider near you with Override on every joint, so the walk / idle
	animation never shows through).

	  Ride   (owner 2026-10-25: "not riding facing forward along it, like Pet
	         Simulator 99") the board lies ACROSS under you (BoardPose.Across:
	         its nose to your right) and you face where you go: feet wide
	         apart along the deck, knees bent, arms out and down for balance.
	         It breathes and sways; with speed you crouch lower and lean
	         forward with the arms swept back; in turns you lean into the turn
	  Mount  hopping on (the first MountTime seconds): a crouch, a jump while
	         the board flies in under you, a squashy landing
	  Air    in a jump: knees tucked up, arms up and out (the board kickflips)
	  Land   touching down: a short squash

	State (numbers, 0..1 unless said):
	  T      seconds (the sway)
	  Speed  speed / the board's top speed
	  Turn   -1 (hard left) .. 1 (hard right)
	  Mount  hop-on progress (1 = done, riding)
	  Air    airborne amount (0 = on the board, 1 = fully tucked)
	  Land   landing squash (1 = just landed, decays to 0)
	  Leg    optional: the rider's leg length / the block rig's (legScale), so
	         taller avatars crouch onto the deck too (default 1)
	  Tool   optional: a tool (the blaster) is in hand (the controller masks
	         the arms: the Animator's hold shows; you already face forward)

	Joint frames as in Config/MoveConfig: x pitch (limbs forward +, knees bend
	-, torso leans BACK +), y yaw (turns LEFT +), z roll (toward the right +;
	the right arm / leg out is +, the left one -). The Root's pose is
	CFrame.new(offset) * tilt: the body drops by the crouch so the feet stay on
	the deck (the HumanoidRootPart and the physics never move).
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
	Leg: number?,
	Tool: boolean?,
}
export type Pose = { [string]: CFrame }

BoardPose.MountTime = 0.6 -- seconds of the hop-on
BoardPose.LandTime = 0.35 -- seconds the landing squash lasts
BoardPose.Crouch = 18 -- degrees of knee bend at rest
BoardPose.SpeedCrouch = 12 -- more at top speed
BoardPose.Spread = 24 -- degrees each leg is out (feet wide apart along the deck)
BoardPose.MaxRoll = 0.22 -- radians: the board's roll into a hard turn (HoverboardController); Turn = roll / MaxRoll
BoardPose.HipToSole = 2 -- the block rig's Root joint above its soles (standing)
BoardPose.DeckHeight = 1.5 -- the deck above the board's Root, its roll pivot (HoverboardBuilder.DeckHeight)
-- the board lies across under the rider (Pet Simulator 99 style): its nose (-Z) to the rider's right (+X)
BoardPose.Across = CFrame.Angles(0, -math.pi / 2, 0)

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

-- The hop-on split into its parts: (crouch prep 0..1, jump height 0..1, done-ness 0..1, landing squash 0..1).
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
	local prep, jump, _, mountLand = BoardPose.mountPhases(state.Mount)
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
	local leg = math.clamp(state.Leg or 1, 0.5, 2)
	local drop = MoveConfig.crouchDrop(crouch) * leg
	-- legs wide apart: the hips open out and the ankles keep the feet flat on the deck
	local spread = BoardPose.Spread * (1 - 0.4 * air)
	-- the hop on: up and over; in a jump the feet come up off the deck so the board can flip
	-- (the whole body, visual only: crouch drop + lift = how high the feet are); open legs
	-- lift the feet a touch, the body comes down by as much
	local lift = 1.5 * jump + 0.75 * air - BoardPose.BlockLeg * leg * (1 - math.cos(rad(spread)))
	-- the forward lean tips the toes down: up a touch so they stay on the deck
	lift += 0.08 * speed

	-- the body faces where you go, leaning forward with speed; in turns it rolls exactly like
	-- the board (HoverboardController: Turn = board roll / MaxRoll) about the same point, the
	-- ground under the deck (hips -> soles -> deck), so both feet stay on the tilted deck
	local lean = -(4 + 12 * speed) + 3 * sway2 * calm
	local pivot = CFrame.new(0, -(BoardPose.HipToSole * leg + BoardPose.DeckHeight), 0)
	local rollTurn = pivot * CFrame.Angles(0, 0, BoardPose.MaxRoll * turn) * pivot:Inverse()
	pose.Root = rollTurn * CFrame.new(0, lift - drop, 0) * angles(lean, 0, 0)
	pose.Waist = angles(-3 - 6 * speed + 2.5 * sway, 4 * turn, 2.5 * sway2 * calm)
	pose.Neck = angles(3 + 8 * speed, 8 * turn, 0)

	-- (the formula of MoveConfig crouch: thigh a, knee -2a, ankle a)
	pose.LeftHip = angles(crouch, 0, -spread)
	pose.LeftKnee = angles(-2 * crouch, 0, 0)
	pose.LeftAnkle = angles(crouch, 0, spread)
	pose.RightHip = angles(crouch, 0, spread)
	pose.RightKnee = angles(-2 * crouch, 0, 0)
	pose.RightAnkle = angles(crouch, 0, -spread)

	-- arms out and down for balance; swept back at speed; up and wide in the air, wide on a landing
	local wave = 5 * sway * calm
	local armOut = lerp(lerp(40, 52, speed), 120, air) + 22 * squash
	local swing = lerp(14, -22, speed) * (1 - air)
	pose.LeftShoulder = angles(swing, 0, -(armOut + wave))
	pose.LeftElbow = angles(lerp(26, 14, speed), 0, 0)
	pose.LeftWrist = angles(0, 0, -6 * sway2)
	pose.RightShoulder = angles(swing, 0, armOut - wave)
	pose.RightElbow = angles(lerp(26, 14, speed), 0, 0)
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

--[[
	The kickflip's clock, one step per frame: `flipAt` = when the running flip
	started (nil = none), `launched` = the rider jumped this frame (a real
	jump, not a fall off a ledge). A flip starts only on a launch and always
	runs to its end (also after landing), so the roll never snaps.
	Returns the new flipAt and the board's roll (radians).
]]
function BoardPose.stepFlip(flipAt: number?, now: number, launched: boolean): (number?, number)
	local at = flipAt
	if at and now - at >= BoardPose.FlipTime then
		at = nil
	end
	if not at and launched then
		at = now
	end
	if at then
		return at, BoardPose.flip(now - at)
	end
	return nil, 0
end

-- The block rig's thigh + shin (hip to knee to ankle, from the Motor6D pivots).
BoardPose.BlockLeg = 1.75

--[[
	The rider's leg length / the block rig's, from the hip, knee and ankle
	Motor6Ds (anything with C0 / C1): thigh = the knee's C0 to the hip's C1
	(both in the upper leg), shin = the ankle's C0 to the knee's C1 (both in
	the lower leg). 1 for the block rig, more for tall (Rthro) legs.
]]
function BoardPose.legScale(hip: any, knee: any, ankle: any): number
	local ok, length = pcall(function(): number
		local thigh = (knee.C0.Position - hip.C1.Position).Magnitude
		local shin = (ankle.C0.Position - knee.C1.Position).Magnitude
		return thigh + shin
	end)
	if not ok or type(length) ~= "number" or length ~= length or length <= 0 then
		return 1
	end
	return math.clamp(length / BoardPose.BlockLeg, 0.5, 2)
end

-- The kickflip as a turn of the board's frame (about its middle, not the ground under it).
function BoardPose.flipFrame(roll: number): CFrame
	if roll == 0 then
		return CFrame.identity
	end
	return CFrame.new(0, BoardPose.FlipPivot, 0) * CFrame.Angles(0, 0, roll) * CFrame.new(0, -BoardPose.FlipPivot, 0)
end

return BoardPose
