--[[
	GolemGait: the running animation of golem followers (owner 2026-10-21:
	"the golems should really RUN after the characters"). The maths is pure:
	the client (Controllers/WorldMotionController) and the showreel preview
	run the same code.

	- classify(model): the follower's limb groups, worked out once per model.
	  GolemBuilder names its core parts (Body, Leg1/2, Arm1/2, Fist1/2, Head);
	  everything else (the gear of every accessory and limited edition, up to
	  any part count) goes by name family first (Core, Vein, Boulder, Crystal*,
	  Wing*, Tail*, Aura, Crack*: they stay on the body), then by geometry in
	  the golem's own units (feet at 0, -X = its left): at or above the neck
	  -> the head; out at the sides below the shoulders -> that arm (a shield);
	  low and off-centre -> that leg; the rest -> the body. Each group swings
	  around its pivot: the hips, the shoulders, the neck.
	- step(gait, now, speed, yaw): the gait clock: the step phase advances by
	  the cadence (steps get quicker and longer with speed, and quicker for
	  small golems), the smoothed speed, the turn rate, braking.
	- pose(...): the limb angles and the body's lift / lean / bank for this
	  frame: walk (legs and arms swing opposite, a hip waddle), run (bigger
	  swing, the body leans forward and bounces once per step, the head looks
	  into the turn), sprint (catching up: longer strides, more lean), braking
	  (a lean back with the arms forward), idle (breathing, looking around, a
	  wave now and then), the equip jump (arms up, legs tucked); Premium
	  golems that hover fly instead: arms swept back, legs trailing, a tilt
	  into turns and a gentle bob. Reduce motion halves the swing and drops
	  the sprint lean and the bank.
	- controllerHop(...): GolemController's own whole-body hop (lift, pitch,
	  roll) for the same follower, so the hook can swap it for the gait.
	- lod / fits: full limbs only within LimbRange of the camera, on screen,
	  while the per-frame part cap allows (phones less).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemBuilder = require(Shared:WaitForChild("Builders"):WaitForChild("GolemBuilder"))

local GolemGait = {}

local TAU = math.pi * 2

export type Group = {
	Parts: { BasePart },
	Rest: { CFrame }, -- each part in the Body's frame
	Welds: { [BasePart]: WeldConstraint }, -- the weld that holds each part to the Body
	Pivot: CFrame, -- the joint in the Body's frame (studs)
	PivotInv: CFrame,
}

export type Rig = {
	Body: BasePart,
	Scale: number, -- studs per golem unit (FollowerSize x the golem's Scale)
	LegL: Group,
	LegR: Group,
	ArmL: Group,
	ArmR: Group,
	Head: Group,
	Count: number, -- parts the limbs move
}

export type Gait = {
	Phase: number, -- radians: one stride (two steps) per 2 pi
	Speed: number, -- smoothed studs per second
	Accel: number, -- smoothed studs per second per second
	YawRate: number, -- smoothed radians per second
	LastNow: number,
	LastYaw: number,
	LastSpeed: number,
}

export type Pose = {
	LegL: number, -- hip pitch (radians, + = forward)
	LegR: number,
	LiftL: number, -- the swinging leg's lift (studs): the knee is implied
	LiftR: number,
	ArmL: number, -- shoulder pitch (+ = forward, up)
	ArmR: number,
	RollL: number, -- shoulder roll away from the body (radians)
	RollR: number,
	HeadPitch: number,
	HeadYaw: number,
	Lift: number, -- the body (studs)
	Pitch: number, -- (- = leaning forward)
	Roll: number,
}

-- Speeds (studs per second; a player walks 16)
GolemGait.Walk = 4 -- running starts here
GolemGait.Run = 12 -- full run from here
GolemGait.Sprint = 19 -- catching up from here
GolemGait.SprintFull = 28
GolemGait.Cadence = 3.0 -- strides per second at most for a golem of scale 1 (smaller: quicker)
GolemGait.LimbRange = 50 -- studs from the camera for the full limb animation
GolemGait.Cap = { PC = 160, Phone = 60 } -- limb parts moved per frame
GolemGait.WaveTime = 1.2 -- the idle wave
GolemGait.WaveEvery = { 6, 10 }

-- joints in golem units (feet at 0, front -Z, -X = the golem's left)
GolemGait.Hip = Vector3.new(0.3, 0.5, 0.02)
GolemGait.Shoulder = Vector3.new(0.78, 1.38, 0)
GolemGait.Neck = Vector3.new(0, GolemBuilder.HeadBottom, 0)

-- names that stay on the body whatever their height (prefixes)
GolemGait.BodyNames = { "Body", "Core", "Vein", "Boulder", "Crystal", "Wing", "Tail", "Aura", "Crack" }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function frac(x: number): number
	return x - math.floor(x)
end

---------------------------------------------------------------- limb groups

-- Which group a part belongs to: "LegL" | "LegR" | "ArmL" | "ArmR" | "Head" | "Body", from its name
-- and its spot `p` in golem units (feet at 0).
function GolemGait.groupOf(name: string, p: Vector3): string
	local family = string.match(name, "^(%a+)") or name
	if family == "Leg" then
		return if p.X < 0 then "LegL" else "LegR"
	elseif family == "Arm" or family == "Fist" then
		return if p.X < 0 then "ArmL" else "ArmR"
	elseif family == "Head" then
		return "Head"
	end
	for _, prefix in GolemGait.BodyNames do
		if string.sub(name, 1, #prefix) == prefix then
			return "Body"
		end
	end
	-- geometry: anything else (helmets, crowns, horns, shields, boots, new gear)
	if p.Y >= GolemGait.Neck.Y - 0.05 then
		return "Head"
	elseif math.abs(p.X) >= 0.62 and p.Y < GolemGait.Shoulder.Y + 0.1 then
		return if p.X < 0 then "ArmL" else "ArmR"
	elseif p.Y < GolemBuilder.LegHeight + 0.05 and math.abs(p.X) >= 0.08 then
		return if p.X < 0 then "LegL" else "LegR"
	end
	return "Body"
end

local function newGroup(pivot: CFrame): Group
	return { Parts = {}, Rest = {}, Welds = {}, Pivot = pivot, PivotInv = pivot:Inverse() }
end

--[[
	The limb groups of a follower model (GolemBuilder.build, any opts): nil
	when it has no Body. The Body's frame is the golem's: its centre sits
	LegHeight + BodySize.Y / 2 units over the feet.
]]
function GolemGait.classify(model: Model): Rig?
	local body = model.PrimaryPart
	if not body then
		return nil
	end
	local s = body.Size.X / GolemBuilder.BodySize.X
	local bodyY = GolemBuilder.LegHeight + GolemBuilder.BodySize.Y / 2
	local function joint(v: Vector3): CFrame
		return CFrame.new(v.X * s, (v.Y - bodyY) * s, v.Z * s)
	end
	local h, sh, n = GolemGait.Hip, GolemGait.Shoulder, GolemGait.Neck
	local rig: Rig = {
		Body = body,
		Scale = s,
		LegL = newGroup(joint(Vector3.new(-h.X, h.Y, h.Z))),
		LegR = newGroup(joint(h)),
		ArmL = newGroup(joint(Vector3.new(-sh.X, sh.Y, sh.Z))),
		ArmR = newGroup(joint(sh)),
		Head = newGroup(joint(n)),
		Count = 0,
	}
	local cf = body.CFrame
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= body then
			local rest = cf:ToObjectSpace(d.CFrame)
			local p = rest.Position / s + Vector3.new(0, bodyY, 0)
			local key = GolemGait.groupOf(d.Name, p)
			if key ~= "Body" then
				local group = (rig :: any)[key] :: Group
				table.insert(group.Parts, d)
				table.insert(group.Rest, rest)
				local weld = d:FindFirstChildOfClass("WeldConstraint")
				if weld then
					group.Welds[d] = weld
				end
				rig.Count += 1
			end
		end
	end
	return rig
end

---------------------------------------------------------------- the gait clock

function GolemGait.newGait(now: number, yaw: number): Gait
	return { Phase = 0, Speed = 0, Accel = 0, YawRate = 0, LastNow = now, LastYaw = yaw, LastSpeed = 0 }
end

-- Strides (two steps) per second at `speed` for a golem of `scale`: quicker with speed, quicker for small golems.
function GolemGait.cadence(speed: number, scale: number): number
	local s = math.max(0.3, scale)
	return GolemGait.Cadence / math.sqrt(s) * (1 - math.exp(-math.max(0, speed) / (5 * s)))
end

-- Studs per stride: longer with speed (the cadence levels off), shorter for small golems.
function GolemGait.stride(speed: number, scale: number): number
	local c = GolemGait.cadence(speed, scale)
	if c < 1e-4 then
		return 5 * math.max(0.3, scale) / (GolemGait.Cadence / math.sqrt(math.max(0.3, scale)))
	end
	return speed / c
end

-- (move, run, sprint) 0..1 for a speed.
function GolemGait.levels(speed: number): (number, number, number)
	return clamp01(speed / 1.5),
		clamp01((speed - GolemGait.Walk) / (GolemGait.Run - GolemGait.Walk)),
		clamp01((speed - GolemGait.Sprint) / (GolemGait.SprintFull - GolemGait.Sprint))
end

-- One frame of the gait clock (`speed` = GolemController's follower speed, `yaw` its facing).
function GolemGait.step(g: Gait, now: number, speed: number, yaw: number, scale: number)
	local dt = math.clamp(now - g.LastNow, 0, 0.1)
	g.LastNow = now
	if dt <= 0 then
		return
	end
	local k = 1 - math.exp(-dt * 10)
	local target = if speed == speed then math.clamp(speed, 0, 80) else 0
	g.Speed += (target - g.Speed) * k
	local accel = (g.Speed - g.LastSpeed) / dt
	g.LastSpeed = g.Speed
	g.Accel += (accel - g.Accel) * (1 - math.exp(-dt * 6))
	local turn = (yaw - g.LastYaw + math.pi) % TAU - math.pi
	g.LastYaw = yaw
	g.YawRate += (turn / dt - g.YawRate) * (1 - math.exp(-dt * 8))
	g.Phase = (g.Phase + TAU * GolemGait.cadence(g.Speed, scale) * dt) % (TAU * 64)
end

---------------------------------------------------------------- the pose

function GolemGait.newPose(): Pose
	return {
		LegL = 0,
		LegR = 0,
		LiftL = 0,
		LiftR = 0,
		ArmL = 0,
		ArmR = 0,
		RollL = 0,
		RollR = 0,
		HeadPitch = 0,
		HeadYaw = 0,
		Lift = 0,
		Pitch = 0,
		Roll = 0,
	}
end

-- The idle wave `w` seconds into it (0..WaveTime): 0..1, eased in and out.
local function waveEnvelope(w: number): number
	local k = w / GolemGait.WaveTime
	if k <= 0 or k >= 1 then
		return 0
	end
	return math.sin(math.pi * k) ^ 0.6
end

--[[
	Fills `pose` for this frame. `scale` = studs per golem unit, `floats` =
	a Premium golem (it flies), `celebrate` = seconds into the equip jump
	(nil = none, Golem.JumpTime long: see WorldMotionLogic), `jumpTime` its
	length.
]]
function GolemGait.pose(
	pose: Pose,
	g: Gait,
	now: number,
	scale: number,
	floats: boolean,
	seed: number,
	celebrate: number?,
	jumpTime: number,
	reduce: boolean
)
	local speed = g.Speed
	local move, run, sprint = GolemGait.levels(speed)
	local r = if reduce then 0.5 else 1
	local turn = math.clamp(g.YawRate * 0.12, -0.45, 0.45)
	if floats then
		-- flying: arms swept back, legs trailing, a tilt into the motion and the turns, a gentle bob
		local k = clamp01(speed / 8)
		local swayA = math.sin(now * 1.7 + seed)
		local back = if reduce then -0.8 else -1.25
		pose.ArmL = lerp(-0.12 + 0.08 * swayA, back, k)
		pose.ArmR = lerp(-0.12 - 0.08 * swayA, back, k)
		pose.RollL = lerp(0.2, 0.14, k)
		pose.RollR = pose.RollL
		local dangle = math.sin(now * 1.6 + seed) * 0.12
		local flutter = 0.07 * k * r
		pose.LegL = lerp(dangle, -0.55 * r, k) + flutter * math.sin(now * 5.2 + seed)
		pose.LegR = lerp(-dangle, -0.5 * r, k) + flutter * math.sin(now * 5.2 + seed + 2)
		pose.LiftL, pose.LiftR = 0, 0
		pose.Lift = scale * 0.06 * math.sin(now * 2.6 + seed)
		pose.Pitch = -0.32 * k * r
		-- (a left turn turns the yaw up: roll left into it)
		pose.Roll = if reduce then 0 else math.clamp(g.YawRate * 0.1, -0.35, 0.35) * k
		pose.HeadPitch = 0.2 * k * r
		pose.HeadYaw = turn * (1 - 0.5 * k) + 0.3 * math.sin(now * 0.45 + seed * 1.3) * (1 - k)
	else
		local swing = math.sin(g.Phase)
		local c = math.cos(g.Phase)
		local legAmp = (0.38 + 0.42 * run + 0.3 * sprint) * move * r
		local armAmp = legAmp * 1.2
		pose.LegL = legAmp * swing
		pose.LegR = -legAmp * swing
		-- the leg swinging forward lifts (a bent knee)
		local lift = scale * (0.05 + 0.08 * run) * move * r
		pose.LiftL = lift * math.max(0, c)
		pose.LiftR = lift * math.max(0, -c)
		-- arms pump opposite to the legs, held a little forward when running
		local hold = 0.25 * run * r
		pose.ArmL = hold - armAmp * swing
		pose.ArmR = hold + armAmp * swing
		pose.RollL = 0.06 + 0.1 * sprint * r
		pose.RollR = pose.RollL
		-- the body: highest with the legs together when walking, in the air between steps when running
		local bounce = scale * (0.05 + 0.13 * run + 0.08 * sprint) * move * r
		local a = math.abs(swing)
		pose.Lift = bounce * lerp(1 - a, a, run)
		local brake = clamp01(-g.Accel / 30) * run
		local lean = 0.04 * move + 0.18 * run + (if reduce then 0 else 0.16 * sprint)
		pose.Pitch = -lean * r + 0.2 * brake * r
		pose.Roll = (if reduce then 0 else math.clamp(g.YawRate * 0.05, -0.2, 0.2) * run) + math.sin(g.Phase) * 0.04 * move * (1 - run)
		pose.ArmL += 0.5 * brake
		pose.ArmR += 0.5 * brake
		pose.HeadPitch = lean * 0.5 * r + 0.04 * math.sin(2 * g.Phase) * run * r
		pose.HeadYaw = turn
		-- idle: breathing, looking around, now and then a wave with the right arm
		local idle = 1 - move
		if idle > 0 then
			local breath = math.sin(now * 1.9 + seed)
			pose.ArmL += 0.05 * breath * idle
			pose.ArmR -= 0.05 * breath * idle
			pose.Lift += scale * 0.015 * breath * idle
			pose.HeadYaw += 0.35 * math.sin(now * 0.45 + seed * 1.3) * idle
			local every = GolemGait.WaveEvery[1] + (GolemGait.WaveEvery[2] - GolemGait.WaveEvery[1]) * frac(seed * 0.618)
			local w = (now + seed * 2.3) % every
			local wave = waveEnvelope(w) * idle
			if wave > 0 then
				-- the arm goes out to the side and a little forward (clear of the big head) and waves;
				-- each golem waves with its own hand
				local roll = (1.9 + 0.4 * math.sin(w * 13)) * wave * r
				if frac(seed * 0.29) < 0.5 then
					pose.RollL += roll
					pose.ArmL += 0.7 * wave
				else
					pose.RollR += roll
					pose.ArmR += 0.7 * wave
				end
				pose.HeadYaw *= 1 - wave
			end
		end
	end
	-- the equip jump: arms up, legs tucked
	if celebrate and celebrate >= 0 and celebrate < jumpTime then
		local e = math.sin(math.pi * celebrate / jumpTime)
		pose.ArmL += (2.6 - pose.ArmL) * e
		pose.ArmR += (2.6 - pose.ArmR) * e
		if not floats then
			pose.LegL += (0.6 - pose.LegL) * e
			pose.LegR += (0.45 - pose.LegR) * e
		end
	end
end

---------------------------------------------------------------- GolemController's own hop

--[[
	The whole-body hop GolemController puts on a follower (its stepPets):
	(lift, pitch, roll). With the limbs running, the hook takes it back out
	and puts the gait's body pose in. Keep in step with GolemController.
]]
function GolemGait.controllerHop(phase: number, speed: number, walking: boolean, near: boolean, floats: boolean): (number, number, number)
	if not walking then
		return 0, 0, 0
	end
	local k = math.clamp(speed / 10, 0, 1)
	if floats then
		return 0, if near then -0.08 * k else 0, 0
	end
	return math.abs(math.sin(phase)) * 0.55 * k, if near then -0.12 * k else 0, if near then math.sin(phase) * 0.08 * k else 0
end

---------------------------------------------------------------- level of detail

-- Full limb animation for a golem `distance` studs from the camera?
function GolemGait.lod(distance: number, onScreen: boolean): boolean
	return onScreen and distance <= GolemGait.LimbRange
end

-- Do `need` more limb parts fit when `used` of this device's cap are taken?
function GolemGait.fits(used: number, need: number, phone: boolean): boolean
	return used + need <= (if phone then GolemGait.Cap.Phone else GolemGait.Cap.PC)
end

-- A group's frame this frame: the Body's frame turned around the joint (pitch, yaw, roll) and lifted.
function GolemGait.jointFrame(body: CFrame, group: Group, pitch: number, yaw: number, roll: number, lift: number): CFrame
	return body * CFrame.new(0, lift, 0) * group.Pivot * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll) * group.PivotInv
end

return GolemGait
