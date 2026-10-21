--[[
	Exports the player-move showreel for the video renderer
	(tools/preview/moves.html, tools/preview/render_anim.mjs): an R15 block
	dummy (lib/dummy_r15) plays every MoveConfig move, frame by frame, with
	the game's own MoveMath + MoveRig layering on top of a stand-in for the
	default Animate script (idle breathing, the walk, the tool hold).
	Props are the game's real ones: raw ore chunks in CarryService's stack
	slots (the top one flies off on the throw) and the blaster in the hand.

	  lune run tools/lune/export_moves.luau [fps=30] [only=MoveName]
	-> build/preview/anim_moves.json
	   { fps, duration, groups = { { name, parts } }, frames = { { cf12 | 0 per group } },
	     segments = { { start, stop, title, subtitle, move, camera } } }
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local R15 = require("./lib/dummy_r15")

local root = process.cwd
Loader.init(root)

local CFrame, Vector3 = Loader.CFrame, roblox.Vector3
local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
local MoveMath = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveMath")
local MoveRig = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRig")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")

local fps = tonumber(process.args[1]) or 30
local only = process.args[2]

local rad = math.rad

---------------------------------------------------------------- the stand-in Animate script

-- What the default R15 Animate script would write this frame (Transform per joint).
local function idle(t: number, out: { [string]: any })
	local breath = math.sin(t * 2 * math.pi / 3)
	out.Waist = CFrame.Angles(rad(1.2 * breath), 0, 0)
	out.Neck = CFrame.Angles(rad(-1 * breath), 0, 0)
	out.RightShoulder = CFrame.Angles(rad(2 * breath), 0, rad(4))
	out.LeftShoulder = CFrame.Angles(rad(2 * breath), 0, rad(-4))
	out.RightElbow = CFrame.Angles(rad(6), 0, 0)
	out.LeftElbow = CFrame.Angles(rad(6), 0, 0)
	for _, name in { "Root", "RightWrist", "LeftWrist", "RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle" } do
		out[name] = CFrame.identity
	end
end

local WALK_PERIOD = 0.78
local function walk(t: number, out: { [string]: any })
	local p = t / WALK_PERIOD * 2 * math.pi
	local s = math.sin(p)
	local c = math.cos(p)
	-- legs: thigh swing, the knee bends while the leg comes forward, the foot rolls
	local function leg(phase: number): (number, number, number)
		local sw = math.sin(p + phase)
		local lift = math.max(0, math.cos(p + phase))
		return rad(30 * sw), rad(-12 - 48 * lift), rad(-8 * sw + 10 * lift)
	end
	local rh, rk, ra = leg(0)
	local lh, lk, la = leg(math.pi)
	out.RightHip = CFrame.Angles(rh, 0, 0)
	out.RightKnee = CFrame.Angles(rk, 0, 0)
	out.RightAnkle = CFrame.Angles(ra, 0, 0)
	out.LeftHip = CFrame.Angles(lh, 0, 0)
	out.LeftKnee = CFrame.Angles(lk, 0, 0)
	out.LeftAnkle = CFrame.Angles(la, 0, 0)
	out.Root = CFrame.new(0, -0.06 + 0.07 * math.abs(c), 0) * CFrame.Angles(0, rad(5 * s), 0)
	out.Waist = CFrame.Angles(rad(-3), rad(-7 * s), 0)
	out.Neck = CFrame.Angles(0, rad(4 * s), 0)
	out.RightShoulder = CFrame.Angles(rad(-26 * s), 0, rad(4))
	out.LeftShoulder = CFrame.Angles(rad(26 * s), 0, rad(-4))
	out.RightElbow = CFrame.Angles(rad(14 + 10 * math.max(0, -s)), 0, 0)
	out.LeftElbow = CFrame.Angles(rad(14 + 10 * math.max(0, s)), 0, 0)
	out.RightWrist = CFrame.identity
	out.LeftWrist = CFrame.identity
end

-- the tool hold (Animate's "toolnone"): the right arm forward over the idle
local function tool(t: number, out: { [string]: any })
	idle(t, out)
	out.RightShoulder = CFrame.Angles(rad(90), 0, 0)
	out.RightElbow = CFrame.identity
end

local BASES = { Idle = idle, Walk = walk, Tool = tool }

---------------------------------------------------------------- the showreel

-- camera: yaw around the dummy (0 = in front of its face), distance, height, look-at height, fov
type Shot = { Yaw: number, Distance: number, Height: number, Look: number, Fov: number, LookZ: number? }
local FRONT = { Yaw = 28, Distance = 13, Height = 4.4, Look = 2.9, Fov = 40 }
local SIDE = { Yaw = 60, Distance = 14, Height = 4.2, Look = 3.0, Fov = 40 }
local THREEQ = { Yaw = 46, Distance = 13, Height = 4.8, Look = 2.9, Fov = 40 }
local RANGE = { Yaw = 84, Distance = 17, Height = 4.6, Look = 2.8, Fov = 40, LookZ = -7.5 } -- the blaster and its rock
local HIGH = { Yaw = 22, Distance = 15, Height = 5.4, Look = 3.4, Fov = 40 }

type Play = { Move: string, At: number, Stop: number?, Scale: number? }
type Segment = {
	Title: string,
	Subtitle: string,
	Base: string,
	Length: number,
	Plays: { Play },
	Ore: number?, -- chunks carried (CarryService stack slots)
	ThrowAt: number?, -- the top chunk leaves the hands at this local time
	Blaster: boolean?,
	Prop: string?, -- "Station" (the Cleaning Station in front) | "Anvil" (the Foundry anvil)
	Beam: { number }?, -- { from, to } local seconds the beam is on (the Recoil segment)
	Shot: Shot,
	MoveName: string,
}

local function recoilPlays(from: number, to: number): { Play }
	local list: { Play } = { { Move = "Recoil", At = from, Scale = 1 } }
	local t = from + MoveConfig.RecoilRepeat
	while t < to do
		table.insert(list, { Move = "Recoil", At = t, Scale = MoveConfig.RecoilRepeatWeight })
		t += MoveConfig.RecoilRepeat
	end
	return list
end

local SEGMENTS: { Segment } = {
	{
		MoveName = "Carry",
		Title = "CARRY",
		Subtitle = "Nesení rudy: ruce drží kus, nohy dál chodí",
		Base = "Walk",
		Length = 3.4,
		Plays = { { Move = "Carry", At = 0.2, Stop = 3.0 } },
		Ore = 2,
		Shot = THREEQ,
	},
	{
		MoveName = "Throw",
		Title = "THROW",
		Subtitle = "Hod rudy: Q / RB / tlačítko Throw",
		Base = "Idle",
		Length = 2.4,
		Plays = { { Move = "Carry", At = 0, Stop = 1.0 }, { Move = "Throw", At = 0.6 }, { Move = "Throw", At = 1.6 } },
		Ore = 2,
		ThrowAt = 0.6 + 0.22,
		Shot = SIDE,
	},
	{
		MoveName = "Recoil",
		Title = "RECOIL",
		Subtitle = "Zpětný ráz blasteru při každé ráně",
		Base = "Tool",
		Length = 2.4,
		Plays = recoilPlays(0.4, 2.0),
		Blaster = true,
		Beam = { 0.4, 2.05 },
		Shot = RANGE,
	},
	{
		MoveName = "Spray",
		Title = "SPRAY",
		Subtitle = "Čištění rudy u stanice (vidí to ostatní hráči)",
		Base = "Idle",
		Length = 2.6,
		Plays = { { Move = "Spray", At = 0.2, Stop = 2.2 } },
		Prop = "Station",
		Shot = THREEQ,
	},
	{
		MoveName = "Hammer",
		Title = "HAMMER",
		Subtitle = "Kování blasteru ve Foundry (vidí to ostatní hráči)",
		Base = "Idle",
		Length = 3.0,
		Plays = { { Move = "Hammer", At = 0.2, Stop = 2.6 } },
		Prop = "Anvil",
		Shot = SIDE,
	},
	{
		MoveName = "Celebrate",
		Title = "CELEBRATE",
		Subtitle = "Radost: nová ruda nebo Flawless",
		Base = "Idle",
		Length = 1.9,
		Plays = { { Move = "Celebrate", At = 0.3 } },
		Shot = FRONT,
	},
	{
		MoveName = "BigCelebrate",
		Title = "BIG CELEBRATE",
		Subtitle = "Velká radost: Legendary / Mythic, rebirth, nový blaster",
		Base = "Idle",
		Length = 2.3,
		Plays = { { Move = "BigCelebrate", At = 0.3 } },
		Shot = HIGH,
	},
	{
		MoveName = "CashToss",
		Title = "CASH TOSS",
		Subtitle = "Velký prodej u Tobina: déšť peněz",
		Base = "Idle",
		Length = 1.7,
		Plays = { { Move = "CashToss", At = 0.3 } },
		Shot = FRONT,
	},
	{
		MoveName = "Wave",
		Title = "WAVE",
		Subtitle = "Zamávání: nasadil jsi golema",
		Base = "Idle",
		Length = 1.9,
		Plays = { { Move = "Wave", At = 0.3 } },
		Shot = FRONT,
	},
	{
		MoveName = "Shrug",
		Title = "SHRUG",
		Subtitle = "Pokrčení ramen: tohle teď nejde",
		Base = "Idle",
		Length = 1.6,
		Plays = { { Move = "Shrug", At = 0.3 } },
		Shot = FRONT,
	},
}

if only then
	local kept = {}
	for _, segment in SEGMENTS do
		if segment.MoveName == only then
			table.insert(kept, segment)
		end
	end
	SEGMENTS = kept
end

---------------------------------------------------------------- groups (static parts in group frames)

local function hex(c: any): string
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end
local function cf12(cf: any): { number }
	local list = { cf:GetComponents() }
	for i, v in list do
		list[i] = round(v)
	end
	return list
end

local groups = {}
local groupIndex: { [string]: number } = {}
local function addGroup(name: string, parts: { any })
	table.insert(groups, { name = name, parts = parts })
	groupIndex[name] = #groups
end

for _, partName in R15.Order do
	local list = {}
	for _, piece in R15.pieces(partName) do
		table.insert(list, {
			piece.Shape,
			round(piece.Size.X),
			round(piece.Size.Y),
			round(piece.Size.Z),
			cf12(piece.CFrame),
			hex(piece.Color),
			piece.Material,
			0,
		})
	end
	if #list > 0 then
		addGroup(partName, list)
	end
end

-- a model's parts in the frame of `origin` (the welded body / the Handle)
local function modelParts(model: any, origin: any): { any }
	local scene = Export.collect(model)
	local inverse = origin:Inverse()
	local list = {}
	for _, p in scene.parts do
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = table.unpack(p[5])
		local world = CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		table.insert(list, { p[1], p[2], p[3], p[4], cf12(inverse * world), p[6], p[7], p[8] })
	end
	return list
end

local MAX_ORE = 3
local ORES = { "Copper", "Iron", "Coal" }
for i = 1, MAX_ORE do
	local chunk = ItemBuilder.build({ Kind = "Raw", OreId = ORES[i] }, CFrame.identity, "move" .. i)
	local body = chunk.PrimaryPart or chunk:FindFirstChildWhichIsA("BasePart", true)
	addGroup("Ore" .. i, modelParts(chunk, body.CFrame))
end

local blaster = BlasterBuilder.build(4, "Copper")
local handle = blaster:FindFirstChild("Handle")
addGroup("Blaster", modelParts(blaster, handle.CFrame))
local muzzle = handle:FindFirstChild("Muzzle")
local muzzleLocal = if muzzle then CFrame.new(muzzle.Position) else CFrame.new(0, 0, -2)
-- the laser beam stub (a neon block the renderer stretches along -Z of its frame)
addGroup("Beam", { { 0, 0.22, 0.22, 1, cf12(CFrame.new(0, 0, -0.5)), "ff9a4a", "Neon", 0 } })

-- world props in front of the dummy (simple stand-ins for the Cleaning Station and the anvil)
local function block(size: any, cf: any, color: string, material: string?): any
	return { 0, round(size.X), round(size.Y), round(size.Z), cf12(cf), color, material or "SmoothPlastic", 0 }
end
addGroup("Station", {
	block(Vector3.new(1.9, 2.3, 1.5), CFrame.new(0, 1.15, 0), "8f8a84"),
	block(Vector3.new(2.1, 0.25, 1.7), CFrame.new(0, 2.38, 0), "5d6470", "Metal"),
	block(Vector3.new(0.3, 0.7, 1.0), CFrame.new(-0.8, 2.85, 0), "3e434c", "Metal"),
	block(Vector3.new(0.3, 0.7, 1.0), CFrame.new(0.8, 2.85, 0), "3e434c", "Metal"),
	block(Vector3.new(1.4, 0.12, 0.12), CFrame.new(0, 3.1, 0.45), "e0a040", "Metal"),
})
local stationOre = ItemBuilder.build({ Kind = "Raw", OreId = "Iron" }, CFrame.identity, "station")
local stationBody = stationOre.PrimaryPart or stationOre:FindFirstChildWhichIsA("BasePart", true)
addGroup("StationOre", modelParts(stationOre, stationBody.CFrame))
addGroup("Anvil", {
	block(Vector3.new(1.5, 0.8, 1.2), CFrame.new(0, 0.4, 0), "3b3f47", "Metal"),
	block(Vector3.new(0.8, 0.8, 0.7), CFrame.new(0, 1.2, 0), "4a4f58", "Metal"),
	block(Vector3.new(2.3, 0.7, 1.0), CFrame.new(0, 1.95, 0), "5a606b", "Metal"),
	block(Vector3.new(0.7, 0.4, 0.6), CFrame.new(1.45, 2.05, 0), "5a606b", "Metal"),
	block(Vector3.new(0.9, 0.18, 0.5), CFrame.new(-0.2, 2.36, 0), "ff8a2a", "Neon"),
})
-- the rock the Recoil segment's beam hits (the game's own rock builder, mine floor 1)
local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
local ROCK_CF = CFrame.new(0, 0, -16)
local rockOk, rock = pcall(RockBuilder.build, 1, "Small", { "Copper" }, ROCK_CF, "moves")
if rockOk and rock then
	addGroup("Rock", modelParts(rock, ROCK_CF))
else
	addGroup("Rock", {
		block(Vector3.new(4.5, 3.6, 4), CFrame.new(0, 1.8, 0), "8a7a6c"),
		block(Vector3.new(3, 2, 3), CFrame.new(0.6, 4, 0.3), "7c6d60"),
	})
end
local BEAM_TARGET = Vector3.new(0, 2.4, -14.6)
local STATION_CF = CFrame.new(0, 0, -3.1)
local ANVIL_CF = CFrame.new(0, 0, -2.3)

-- R15 RightGripAttachment: the Handle = hand * grip (Tool.Grip = identity)
local GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(rad(-90), 0, 0)

---------------------------------------------------------------- frames

-- fake motors for MoveRig: the "Animator" writes Transform every frame like the game's does
local motors: { [string]: any } = {}
for _, name in MoveConfig.Joints do
	motors[name] = { Transform = CFrame.identity, Parent = true, Name = name }
end
local rig = MoveRig.fromMotors(motors)

type SlotState = { Move: any, Start: number, Stop: number?, Scale: number, Pose: { [string]: any } }
local slots: { [string]: SlotState } = {
	Loop = { Move = nil, Start = 0, Scale = 1, Pose = {} },
	Action = { Move = nil, Start = 0, Scale = 1, Pose = {} },
	Kick = { Move = nil, Start = 0, Scale = 1, Pose = {} },
}
local SLOT_ORDER = { "Loop", "Action", "Kick" }
local layers = {
	{ Pose = slots.Loop.Pose, Weight = 0, Override = {} },
	{ Pose = slots.Action.Pose, Weight = 0, Override = {} },
	{ Pose = slots.Kick.Pose, Weight = 0, Override = {} },
}

local frames = {}
local segmentsOut = {}
local base: { [string]: any } = {}
local clock = 0
local frameIndex = 0
local ROOT_CF = CFrame.new(0, R15.RootHeight, 0)
local maxClip = { depth = 0, at = "" }
local clipByMove: { [string]: number } = {}

for _, segment in SEGMENTS do
	local start = clock
	local yaw = rad(segment.Shot.Yaw)
	-- the dummy faces -Z; the camera sits in front of it, turned by yaw
	local lookZ = segment.Shot.LookZ or 0
	local camPos = Vector3.new(math.sin(yaw) * segment.Shot.Distance, segment.Shot.Height, lookZ - math.cos(yaw) * segment.Shot.Distance)
	table.insert(segmentsOut, {
		start = round(start),
		stop = round(start + segment.Length),
		title = segment.Title,
		subtitle = segment.Subtitle,
		move = segment.MoveName,
		camera = {
			position = { round(camPos.X), round(camPos.Y), round(camPos.Z) },
			target = { 0, segment.Shot.Look, lookZ },
			fov = segment.Shot.Fov,
		},
	})
	for _, slot in slots do
		slot.Move = nil
		table.clear(slot.Pose)
	end
	local played: { [Play]: boolean } = {}
	local frameCount = math.floor(segment.Length * fps + 0.5)
	for f = 0, frameCount - 1 do
		local t = f / fps
		-- start the plays due by now (a newer move in a slot replaces the old one)
		for _, play in segment.Plays do
			if not played[play] and t >= play.At then
				played[play] = true
				local move = MoveConfig.Moves[play.Move]
				local slot = slots[move.Slot]
				slot.Move = move
				slot.Start = play.At
				slot.Stop = play.Stop
				slot.Scale = play.Scale or 1
				table.clear(slot.Pose)
			end
		end
		-- the "Animator"
		BASES[segment.Base](start + t, base)
		for name, motor in motors do
			motor.Transform = base[name] or CFrame.identity
		end
		-- the game's layering
		for i, slotName in SLOT_ORDER do
			local slot = slots[slotName]
			local layer = layers[i]
			local move = slot.Move
			if move then
				local local_t = t - slot.Start
				if MoveMath.done(move, local_t, if slot.Stop then slot.Stop - slot.Start else nil) then
					slot.Move = nil
					table.clear(slot.Pose)
					layer.Weight = 0
				else
					local w = MoveMath.weight(move, local_t, if slot.Stop then slot.Stop - slot.Start else nil) * slot.Scale
					MoveMath.evaluate(move, local_t, w, slot.Pose)
					layer.Weight = w
					layer.Override = MoveMath.overrides(move)
				end
			else
				layer.Weight = 0
			end
		end
		MoveRig.step(rig, layers, #layers)
		local transforms = {}
		for name, motor in motors do
			transforms[name] = motor.Transform
		end
		local parts = R15.solve(ROOT_CF, transforms)

		-- clipping check: no corner of a hand or a forearm deep inside the torso or the head
		for _, limb in { "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm" } do
			local limbCF = parts[limb]
			local half = R15.Parts[limb].Size * 0.42
			for _, body in { "UpperTorso", "Head", "LowerTorso" } do
				local bodyCF = parts[body]
				local size = R15.Parts[body].Size
				for cx = -1, 1, 2 do
					for cy = -1, 1, 2 do
						for cz = -1, 1, 2 do
							local point = limbCF * Vector3.new(cx * half.X, cy * half.Y, cz * half.Z)
							local inBody = bodyCF:PointToObjectSpace(point)
							local depth =
								math.min(size.X / 2 - math.abs(inBody.X), size.Y / 2 - math.abs(inBody.Y), size.Z / 2 - math.abs(inBody.Z))
							if depth > maxClip.depth then
								maxClip.depth = depth
								maxClip.at = `{segment.MoveName} t={string.format("%.2f", t)} {limb} in {body}`
							end
							if depth > (clipByMove[segment.MoveName] or 0) then
								clipByMove[segment.MoveName] = depth
							end
						end
					end
				end
			end
		end

		local row = {}
		for _, group in groups do
			local cf = parts[group.name]
			if cf then
				table.insert(row, cf12(cf))
			else
				table.insert(row, 0)
			end
		end
		-- props
		local carrying = segment.Ore or 0
		local thrown = segment.ThrowAt ~= nil and t >= segment.ThrowAt
		for i = 1, MAX_ORE do
			local cf: any = nil
			if i <= carrying then
				local slotCF = ROOT_CF * CarryService.stackOffset(i)
				if i == carrying and thrown then
					-- the top chunk flies off (the server throws it: speed, + 8 up)
					local dt = t - (segment.ThrowAt :: number)
					local velocity = Vector3.new(0, 12, -24)
					local position = slotCF.Position + velocity * dt + Vector3.new(0, -0.5 * 70 * dt * dt, 0)
					if position.Y > -2 and dt < 1.2 then
						cf = CFrame.new(position) * CFrame.Angles(dt * 7, dt * 3, 0)
					end
				elseif i < carrying and thrown and t >= (segment.ThrowAt :: number) + 1.0 then
					-- the second throw takes the next one
					local dt = t - ((segment.ThrowAt :: number) + 1.0)
					local velocity = Vector3.new(0, 12, -24)
					local position = slotCF.Position + velocity * dt + Vector3.new(0, -0.5 * 70 * dt * dt, 0)
					if position.Y > -2 and dt < 1.2 then
						cf = CFrame.new(position) * CFrame.Angles(dt * 7, dt * 3, 0)
					end
				else
					cf = slotCF
				end
			end
			row[groupIndex["Ore" .. i]] = if cf then cf12(cf) else 0
		end
		local handCF = parts.RightHand
		local handleCF = handCF * GRIP
		row[groupIndex.Blaster] = if segment.Blaster then cf12(handleCF) else 0
		row[groupIndex.Station] = if segment.Prop == "Station" then cf12(STATION_CF) else 0
		row[groupIndex.StationOre] = if segment.Prop == "Station" then cf12(STATION_CF * CFrame.new(0, 2.95, 0)) else 0
		row[groupIndex.Anvil] = if segment.Prop == "Anvil" then cf12(ANVIL_CF) else 0
		local beamOn = segment.Beam ~= nil and t >= segment.Beam[1] and t < segment.Beam[2]
		if beamOn then
			-- like the game: the beam runs from the muzzle to the hit point on the rock
			local from = (handleCF * muzzleLocal).Position
			local list = cf12(CFrame.lookAt(from, BEAM_TARGET))
			table.insert(list, round((BEAM_TARGET - from).Magnitude))
			row[groupIndex.Beam] = list
		else
			row[groupIndex.Beam] = 0
		end
		row[groupIndex.Rock] = if segment.Blaster then cf12(ROCK_CF) else 0
		table.insert(frames, row)
		frameIndex += 1
	end
	clock += segment.Length
end

local out = {
	fps = fps,
	duration = round(clock),
	groups = groups,
	frames = frames,
	segments = segmentsOut,
}
fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/anim_moves.json", serde.encode("json", out))
print(string.format("Exported anim_moves: %d segments, %d frames (%.1f s), %d groups", #segmentsOut, #frames, clock, #groups))
print(string.format("deepest hand / forearm inside the body: %.2f studs (%s)", maxClip.depth, maxClip.at))
for _, segment in SEGMENTS do
	print(string.format("  %-13s %.2f", segment.MoveName, clipByMove[segment.MoveName] or 0))
end
