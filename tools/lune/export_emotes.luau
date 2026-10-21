--[[
	Exports the emote-concept showreel (Config/EmoteConfig) for the video
	renderer (tools/preview/moves.html?scene=anim_emotes, render_anim.mjs)
	and the sheet (moves_sheet.mjs): the R15 block dummy plays each emote
	with the game's MoveMath + MoveRig layering over an idle stand-in for the
	Animate script: the intro, about one pass of the loop, then the stop
	and the finishing pose. The Blaster Spin holds the real level-4
	blaster, turned by the RightGrip pose; the Gem Juggle shows three gems
	(preview only: in the game they would be invisible or new parts).

	  lune run tools/lune/export_emotes.luau [fps=30] [only=EmoteName]
	-> build/preview/anim_emotes.json (same format as anim_moves.json)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local R15 = require("./lib/dummy_r15")
local MovePose = require("./lib/move_pose")

local root = process.cwd
Loader.init(root)

local CFrame, Vector3 = Loader.CFrame, roblox.Vector3
local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
local EmoteConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EmoteConfig")
local MoveMath = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveMath")
local MoveRig = Loader.requirePath("ReplicatedStorage.Shared.Moves.MoveRig")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")

local fps = tonumber(process.args[1]) or 30
local only = process.args[2]
local rad = math.rad

---------------------------------------------------------------- the idle stand-in (the Animate script)

local function idle(t: number, out: { [string]: any })
	local breath = math.sin(t * 2 * math.pi / 3)
	for _, name in MoveConfig.Joints do
		out[name] = CFrame.identity
	end
	out.Waist = CFrame.Angles(rad(1.2 * breath), 0, 0)
	out.RightShoulder = CFrame.Angles(rad(2 * breath), 0, rad(4))
	out.LeftShoulder = CFrame.Angles(rad(2 * breath), 0, rad(-4))
end

---------------------------------------------------------------- shots and titles

type Shot = { Yaw: number, Distance: number, Height: number, Look: number, Fov: number }
local FRONT = { Yaw = 30, Distance = 13, Height = 4.6, Look = 2.8, Fov = 40 }
local FLOOR = { Yaw = 38, Distance = 12.5, Height = 6.6, Look = 1.5, Fov = 40 }
local HIGH = { Yaw = 26, Distance = 15, Height = 5.6, Look = 3.2, Fov = 40 }
local SIDE = { Yaw = 70, Distance = 13, Height = 4.2, Look = 2.6, Fov = 40 }
local GUN = { Yaw = 40, Distance = 13, Height = 5.2, Look = 3.9, Fov = 40 }

local SHOTS: { [string]: Shot } = {
	Breakdance = FLOOR,
	Headspin = HIGH,
	Robot = FRONT,
	DiscoPoint = FRONT,
	BackGlide = SIDE,
	Worm = FLOOR,
	Victory = HIGH,
	AirGuitar = FRONT,
	ForgeHammer = SIDE,
	GolemStomp = FRONT,
	GemJuggle = HIGH,
	BlasterSpin = GUN,
}
local TITLES: { [string]: string } = {
	Breakdance = "BREAKDANCE",
	Headspin = "HEADSPIN",
	Robot = "ROBOT",
	DiscoPoint = "DISCO POINT",
	BackGlide = "BACK GLIDE",
	Worm = "WORM",
	Victory = "VICTORY DANCE",
	AirGuitar = "AIR GUITAR",
	ForgeHammer = "FORGE HAMMER",
	GolemStomp = "GOLEM STOMP",
	GemJuggle = "GEM JUGGLE",
	BlasterSpin = "BLASTER SPIN",
}

---------------------------------------------------------------- groups

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
local blaster = BlasterBuilder.build(4, "Copper")
local handle = blaster:FindFirstChild("Handle")
addGroup("Blaster", modelParts(blaster, handle.CFrame))
-- R15 RightGripAttachment (Tool.Grip = identity): the Handle = hand * grip * the RightGrip pose
local GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(rad(-90), 0, 0)

local GEM_COLORS = { "ff4d6d", "4dffb0", "5aa8ff" }
for i, color in GEM_COLORS do
	local diamond = CFrame.Angles(rad(45), 0, rad(45))
	addGroup("Gem" .. i, {
		{ 0, 0.42, 0.42, 0.42, cf12(diamond), color, "Neon", 0 },
		{ 0, 0.52, 0.52, 0.52, cf12(diamond), color, "Glass", 0.5 },
	})
end

---------------------------------------------------------------- the reel

local motors: { [string]: any } = {}
for _, name in MoveConfig.Joints do
	motors[name] = { Transform = CFrame.identity, Parent = true, Name = name }
end
local rig = MoveRig.fromMotors(motors)
local layerPose = {}
local layers = { { Pose = layerPose, Weight = 0, Override = {} } }

local ROOT_CF = CFrame.new(0, R15.RootHeight, 0)
local LEAD = 0.15
local TAIL = 0.3

local frames = {}
local segmentsOut = {}
local base: { [string]: any } = {}
local clock = 0
local report = {}

for index, name in EmoteConfig.List do
	if only and only ~= name then
		continue
	end
	local move = EmoteConfig.Emotes[name]
	local loopFrom = move.LoopFrom or 0
	local loopLength = move.Duration - loopFrom
	local shown = math.clamp(loopLength, 1.2, 2.0)
	if name == "GemJuggle" then
		shown = loopLength * 2 -- two passes: the gems need a moment
	end
	local stopAt = loopFrom + shown
	local outroEnd = 0
	for _, k in move.Outro or {} do
		outroEnd = math.max(outroEnd, k.T)
	end
	local length = LEAD + stopAt + outroEnd + TAIL
	local shot = SHOTS[name] or FRONT
	local yaw = rad(shot.Yaw)
	local camPos = Vector3.new(math.sin(yaw) * shot.Distance, shot.Height, -math.cos(yaw) * shot.Distance)
	-- three frames for the sheet: the intro done, the loop, the finishing pose
	local outroHold = outroEnd * 0.55
	table.insert(segmentsOut, {
		start = round(clock),
		stop = round(clock + length),
		title = TITLES[name] or string.upper(name),
		subtitle = EmoteConfig.Captions[name] or name,
		move = name,
		number = `{index}/{#EmoteConfig.List}`,
		camera = { position = { round(camPos.X), round(camPos.Y), round(camPos.Z) }, target = { 0, shot.Look, 0 }, fov = shot.Fov },
		picks = {
			{ round(LEAD + loopFrom + loopLength * 0.12), "začátek smyčky" },
			{ round(LEAD + loopFrom + loopLength * 0.55), "smyčka" },
			{ round(LEAD + stopAt + outroHold), "konec" },
		},
	})
	local low, clip = math.huge, 0
	local frameCount = math.floor(length * fps + 0.5)
	for f = 0, frameCount - 1 do
		local t = f / fps
		local mt = t - LEAD
		idle(clock + t, base)
		for joint, motor in motors do
			motor.Transform = base[joint]
		end
		local stop = if mt >= stopAt then stopAt else nil
		local layer = layers[1]
		if mt >= 0 and not MoveMath.done(move, mt, stop) then
			local w = MoveMath.weight(move, mt, stop)
			MoveMath.evaluate(move, mt, w, layerPose, stop)
			layer.Weight = w
			layer.Override = MoveMath.overrides(move)
		else
			layer.Weight = 0
		end
		MoveRig.step(rig, layers, 1)
		local transforms = {}
		for joint, motor in motors do
			transforms[joint] = motor.Transform
		end
		local parts = R15.solve(ROOT_CF, transforms)
		low = math.min(low, (MovePose.lowest(parts)))
		clip = math.max(clip, (MovePose.clip(parts)))

		local row = {}
		for _, group in groups do
			local cf = parts[group.name]
			table.insert(row, if cf then cf12(cf) else 0)
		end
		-- the blaster: in the right hand, turned by the RightGrip pose
		if move.NeedsTool then
			local grip = if layer.Weight > 0 then layerPose.RightGrip else nil
			local handleCF = parts.RightHand * GRIP * (grip or CFrame.identity)
			row[groupIndex.Blaster] = cf12(handleCF)
		else
			row[groupIndex.Blaster] = 0
		end
		-- the gems: a three-gem cascade. A throw every 0.3 s, right and left in turn (the
		-- arms' toss keys); each gem flies 0.6 s to the other hand and waits there 0.3 s.
		for i = 1, 3 do
			local gi = groupIndex["Gem" .. i]
			row[gi] = 0
			if name == "GemJuggle" and mt >= loopFrom - 0.1 and mt < stopAt + 0.4 then
				local function palm(hand: any): any
					return (hand * CFrame.new(0, -0.35, -0.1)).Position
				end
				local s = mt - loopFrom - (i - 1) * 0.3
				local p: any
				if mt >= stopAt then
					-- caught: a little stack in the hands
					p = (palm(parts.RightHand) + palm(parts.LeftHand)) / 2 + Vector3.new(0, 0.35 * (i - 1), 0)
				elseif s < 0 then
					-- waiting in the hand that throws it first
					p = palm(if (i - 1) % 2 == 0 then parts.RightHand else parts.LeftHand)
				else
					local k = math.floor(s / 0.9)
					local ph = s - k * 0.9
					local fromRight = ((i - 1) + 3 * k) % 2 == 0
					local a = palm(if fromRight then parts.RightHand else parts.LeftHand)
					local b = palm(if fromRight then parts.LeftHand else parts.RightHand)
					if ph < 0.6 then
						local x = ph / 0.6
						p = a:Lerp(b, x) + Vector3.new(0, 3.2 * 4 * x * (1 - x), 0)
					else
						p = b
					end
				end
				row[gi] = cf12(CFrame.new(p) * CFrame.Angles(mt * 4 + i, mt * 3, 0))
			end
		end
		table.insert(frames, row)
	end
	table.insert(report, string.format("  %-12s %4.1f s  lowest %6.2f  clip %.2f", name, length, low, clip))
	clock += length
end

local out = {
	fps = fps,
	duration = round(clock),
	brandNote = "emoty: návrh k výběru · náhled z herního kódu (MoveMath na R15 postavičce)",
	groups = groups,
	frames = frames,
	segments = segmentsOut,
}
fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/anim_emotes.json", serde.encode("json", out))
print(string.format("Exported anim_emotes: %d emotes, %d frames (%.1f s)", #segmentsOut, #frames, clock))
for _, line in report do
	print(line)
end
