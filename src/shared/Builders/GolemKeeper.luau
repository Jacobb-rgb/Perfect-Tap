--[[
	GolemKeeper: a big golem behind a shop counter (owner 2026-10-24: "big
	golems serve our shops, take a golem and just make it bigger, each shop a
	different cool golem, with emotes"). The golem is GolemBuilder's own
	build at a bigger Size (anchored parts, the model tagged NoStuds: no
	Roblox studs on it); the rig remembers where every part sits relative to
	the golem's feet and which way it moves:

	  Right / Left  the arms: Arm, Fist, Bracer, BracerGem and Claw parts of
	                arm 2 (his right, +X) / arm 1; they swing at the shoulder
	  RightHeld /   what the hands hold (a sword, a shield, a spear, a staff
	  LeftHeld      and its orb, a lance) by the side it is on: it goes up and
	                down with the fist but stays upright (a raised sword
	                points at the sky, not at his face)
	  Ground        what stays on the floor when he hops or spins (the aura
	                disc, a cloud floor, a ring of flames)
	  Body          everything else (it hops, spins and leans with him)

	frames(rig, feet, pose, yaw) gives every part's CFrame for a
	Moves/GolemEmotes pose (the client moves them with one BulkMoveTo; the
	previews set them). Pure: Instance creation and math only.

	Lights: a keeper keeps none of its own (a Mythic's gear light goes, as on
	a follower): ShopkeeperController's one soft FaceLight on the nearest
	golem is the only light (phones: the light budget). Its gear's ember
	emitters stay, but slow (at most EmberRate a second).
]]

local GolemBuilder = require(script.Parent.GolemBuilder)
local GolemEmotes = require(script.Parent.Parent.Moves.GolemEmotes)

local GolemKeeper = {}

GolemKeeper.SkipTag = "NoStuds" -- StudStyleConfig.SkipTag
GolemKeeper.EmberRate = 3 -- particles a second, at most, from a keeper's gear embers

export type Group = "Body" | "Right" | "Left" | "RightHeld" | "LeftHeld" | "Ground"

export type Rig = {
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame }, -- each part relative to the feet, at rest
	Groups: { Group },
	ShoulderR: CFrame, -- the shoulders' pivots relative to the feet
	ShoulderL: CFrame,
	FistR: Vector3, -- the fists relative to the feet (what they hold follows them)
	FistL: Vector3,
	Height: number, -- studs, the feet to the top of the gear
}

local ARMS = { "^Arm(%d)$", "^Fist(%d)$", "^Bracer(%d)$", "^BracerGem(%d)$", "^Claw(%d)_" }
local HELD = { "^Blade", "^Guard", "^Pommel", "^Shield", "^Spear", "^Staff", "^Orb$", "^Lance" }
local GROUND = { "^Aura$", "^Floor%d", "^RingFlame" }

-- Which way the part `name` at `x` (studs right of the golem's middle) moves.
function GolemKeeper.group(name: string, x: number): Group
	for _, pattern in GROUND do
		if string.find(name, pattern) then
			return "Ground"
		end
	end
	for _, pattern in ARMS do
		local digit = string.match(name, pattern)
		if digit == "1" then
			return "Left"
		elseif digit == "2" then
			return "Right"
		end
	end
	for _, pattern in HELD do
		if string.find(name, pattern) then
			return if x > 0 then "RightHeld" else "LeftHeld"
		end
	end
	return "Body"
end

-- The shoulder of `arm` (a part's rest offset and size): near the arm's top, upright.
local function shoulder(offset: CFrame?, size: Vector3?, fallback: Vector3): CFrame
	if offset and size then
		return CFrame.new((offset * CFrame.new(0, size.Y * 0.4, 0)).Position)
	end
	return CFrame.new(fallback)
end

-- The golem `kind` at `size` on `feet` (LookVector = the customers), and its rig.
function GolemKeeper.build(kind: string, feet: CFrame, size: number): Rig
	local model = GolemBuilder.build(kind, feet, { Size = size })
	model.Name = "GolemKeeper"
	model:AddTag(GolemKeeper.SkipTag)
	local height = model:GetAttribute("Height")
	local h = if type(height) == "number" and height > 0 then height else 5
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local groups: { Group } = {}
	local arms: { [string]: { Offset: CFrame, Size: Vector3 } } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("PointLight") then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") then
			d.Rate = math.min(d.Rate, GolemKeeper.EmberRate)
		elseif d:IsA("BasePart") then
			local offset = feet:ToObjectSpace(d.CFrame)
			table.insert(parts, d)
			table.insert(offsets, offset)
			table.insert(groups, GolemKeeper.group(d.Name, offset.Position.X))
			if d.Name == "Arm1" or d.Name == "Arm2" or d.Name == "Fist1" or d.Name == "Fist2" then
				arms[d.Name] = { Offset = offset, Size = d.Size }
			end
		end
	end
	local r, l = arms.Arm2, arms.Arm1
	local fr, fl = arms.Fist2, arms.Fist1
	return {
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Groups = groups,
		ShoulderR = shoulder(r and r.Offset, r and r.Size, Vector3.new(h * 0.18, h * 0.4, 0)),
		ShoulderL = shoulder(l and l.Offset, l and l.Size, Vector3.new(-h * 0.18, h * 0.4, 0)),
		FistR = if fr then fr.Offset.Position else Vector3.new(h * 0.2, h * 0.25, 0),
		FistL = if fl then fl.Offset.Position else Vector3.new(-h * 0.2, h * 0.25, 0),
		Height = h,
	}
end

-- Every part's CFrame (in rig.Parts' order) for `pose`, the golem on `feet`
-- turned `yaw` radians (toward the player) on top of the pose's own turn.
function GolemKeeper.frames(rig: Rig, feet: CFrame, pose: GolemEmotes.Pose, yaw: number): { CFrame }
	local root = feet
		* CFrame.Angles(0, yaw + pose.Yaw, 0)
		* CFrame.new(0, pose.Lift * rig.Height, 0)
		* CFrame.Angles(pose.Pitch, 0, pose.Roll)
	local right = rig.ShoulderR * CFrame.Angles(0, 0, pose.Right) * rig.ShoulderR:Inverse()
	local left = rig.ShoulderL * CFrame.Angles(0, 0, -pose.Left) * rig.ShoulderL:Inverse()
	-- what a hand holds moves with the fist, upright
	local heldR = CFrame.new((right * rig.FistR) - rig.FistR)
	local heldL = CFrame.new((left * rig.FistL) - rig.FistL)
	local out = table.create(#rig.Parts)
	for i, offset in rig.Offsets do
		local group = rig.Groups[i]
		if group == "Ground" then
			out[i] = feet * offset
		elseif group == "Right" then
			out[i] = root * right * offset
		elseif group == "Left" then
			out[i] = root * left * offset
		elseif group == "RightHeld" then
			out[i] = root * heldR * offset
		elseif group == "LeftHeld" then
			out[i] = root * heldL * offset
		else
			out[i] = root * offset
		end
	end
	return out
end

return GolemKeeper
