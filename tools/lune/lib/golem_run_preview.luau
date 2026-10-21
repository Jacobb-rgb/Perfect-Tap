--[[
	The golem run reel (owner 2026-10-21: "the golems should really RUN after
	the characters"), frame by frame for tools/preview/world_anim.html
	(?data=golem_run): on a plain meadow you walk, run, dash ahead and stop;
	three followers keep up: a small Pebble Golem, the crowned Diamond Duke
	and the flying Dragon King (Mythic: it hovers, so it flies).

	Every golem is a real GolemBuilder follower (Welded) moved the way
	GolemController moves it (its follower numbers, copied below) times the
	real hook WorldMotionController.golemOffset; the limbs are placed by the
	real WorldMotionController.step (on a rig: the camera and the clock are
	the reel's). So the reel shows the game's own gait code.
]]

local roblox = require("@lune/roblox") :: any

local GolemRun = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Instance = roblox.Instance

local KINDS = { "PebbleGolem", "DiamondDuke", "DragonKing" }

-- the player's speed (studs / s) over the reel: stand, walk, run, dash ahead, run, stop, idle
local SPEEDS = {
	{ 0, 0 },
	{ 1.2, 0 },
	{ 1.8, 6 },
	{ 4.0, 6 },
	{ 4.5, 16 },
	{ 7.3, 16 },
	{ 7.6, 32 },
	{ 8.8, 32 },
	{ 9.1, 16 },
	{ 10.0, 16 },
	{ 10.2, 0 },
	{ 14.5, 0 },
}

local function speedAt(t: number): number
	for i = 1, #SPEEDS - 1 do
		local a, b = SPEEDS[i], SPEEDS[i + 1]
		if t >= a[1] and t <= b[1] then
			local k = (t - a[1]) / math.max(1e-6, b[1] - a[1])
			return a[2] + (b[2] - a[2]) * k
		end
	end
	return 0
end

-- A meadow with a stone path along +X, trees and bushes behind it.
local function meadow(Loader, H)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local root = Instance.new("Model")
	Geo.block(root, CF.new(70, -0.5, 10), V3.new(300, 1, 140), C3.fromRGB(104, 168, 76))
	Geo.block(root, CF.new(70, 0.02, 0), V3.new(300, 0.06, 7), C3.fromRGB(196, 178, 140))
	for i = 0, 40 do
		local x = -40 + i * 6.5
		Geo.block(root, CF.new(x, 0.06, 3.7) * CF.Angles(0, (i % 3) * 0.2, 0), V3.new(2.4, 0.1, 0.6), C3.fromRGB(170, 150, 116))
	end
	for i = 0, 22 do
		local x = -30 + i * 9 + (i % 3) * 2
		local z = 16 + (i * 7) % 14
		local h = 4 + (i % 4)
		Geo.block(root, CF.new(x, h / 2, z), V3.new(0.9, h, 0.9), C3.fromRGB(112, 78, 52))
		Geo.block(root, CF.new(x, h + 1.6, z), V3.new(4.2, 3.4, 4.2), C3.fromRGB(70 + (i % 3) * 14, 140 + (i % 2) * 20, 64))
		Geo.block(root, CF.new(x + 0.4, h + 3.4, z - 0.3), V3.new(2.6, 1.6, 2.6), C3.fromRGB(96, 170, 80))
	end
	for i = 0, 30 do
		local x = -35 + i * 7.3
		local z = 7 + (i * 3) % 6
		local s = 0.8 + (i % 3) * 0.4
		Geo.block(root, CF.new(x, s / 2, z) * CF.Angles(0, i, 0), V3.new(s * 1.6, s, s * 1.3), C3.fromRGB(80, 150, 70))
		if i % 4 == 0 then
			Geo.block(root, CF.new(x + 3, 0.3, -6 - (i % 3)) * CF.Angles(0.2, i, 0.1), V3.new(1.0, 0.6, 0.8), C3.fromRGB(150, 146, 138))
		end
	end
	local parts = {}
	for _, d in H.visibleParts(root) do
		table.insert(parts, H.partEntry(d))
	end
	return parts
end

function GolemRun.build(Loader, opts)
	local CF = Loader.CFrame
	local H = require("./world_motion_preview").helpers
	local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.WorldMotionLogic")
	local Gait = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.GolemGait")
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local Players = Loader.game:GetService("Players")
	rawset(Players, "LocalPlayer", { Name = "Preview", UserId = 41 })
	local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldMotionController")
	local fps = opts and opts.fps or 30
	local dt = 1 / fps
	local duration = SPEEDS[#SPEEDS][1]
	local frames = math.floor(duration * fps + 0.5)

	local data = {
		fps = fps,
		scenes = { { id = "meadow", parts = meadow(Loader, H), lights = {}, look = "day" } },
		groups = {},
		frames = {},
		sheetTitle = "golemové běhají",
		picks = { 0.6, 2.6, 3.4, 5.4, 5.75, 6.6, 8.2, 8.6, 9.5, 10.35, 11.6, 12.5 },
		segments = {
			{
				title = "GOLEMOVÉ BĚHAJÍ ZA TEBOU",
				sub = "jdeš pomalu: golemové jdou, malý Pebble dělá rychlé krůčky",
				cut = false,
			},
			{
				title = "BĚH",
				sub = "nohy a ruce se střídají, tělo se nakloní a pruží; Dragon King letí jako superhrdina",
				cut = false,
			},
			{ title = "SPRINT, KDYŽ ZAOSTÁVAJÍ", sub = "delší kroky a víc předklonu, dokud tě nedoženou", cut = false },
			{ title = "ZASTAVENÍ A ODPOČINEK", sub = "přibrzdí, dýchají, rozhlížejí se a zamávají", cut = false },
		},
	}

	-- the reel's clock: chosen so the Pebble Golem waves while everyone rests
	local wave = Gait.WaveEvery
	local function waveStart(seed: number, base: number): number?
		local every = wave[1] + (wave[2] - wave[1]) * ((seed * 0.618) % 1)
		for t = 10.6, 13.2, 0.05 do
			if (base + t + seed * 2.3) % every < 0.06 then
				return t
			end
		end
		return nil
	end
	local base = 1000
	for b = 1000, 1060, 0.1 do
		local at = waveStart(1 * 1.7 + 41 % 97 * 0.13, b)
		if at and at > 11 and at < 12 then
			base = b
			data.waveAt = at
			break
		end
	end

	local folder = Instance.new("Folder")
	local rig = {
		Folder = folder,
		Eye = V3.new(0, 6, -17),
		Right = V3.new(1, 0, 0),
		Up = V3.new(0, 1, 0),
		Ground = 0,
		Clock = base,
		Phone = false,
		Reduce = false,
		Firing = false,
		Root = nil,
		Gravity = 196.2,
	}
	Controller.useRig(rig)

	-- the followers, built as GolemController builds them, at their slots behind you
	local start = CF.lookAt(V3.new(0, 0, 0), V3.new(1, 0, 0))
	local pets = {}
	for i, kind in KINDS do
		local slot = H.FOLLOW.Slots[i]
		local feet = (start * CF.new(slot)).Position
		local model =
			GolemBuilder.build(kind, CF.new(feet.X, 0, feet.Z) * CF.Angles(0, -math.pi / 2, 0), { Welded = true, Size = H.FOLLOW.Size })
		model.Parent = folder
		local body = model.PrimaryPart
		local rest = {}
		for _, d in H.visibleParts(model) do
			table.insert(rest, { Part = d, Rest = body.CFrame:ToObjectSpace(d.CFrame) })
		end
		table.insert(pets, {
			Kind = kind,
			Phase = 0,
			Seed = i * 1.7 + 41 % 97 * 0.13,
			Floats = (model:GetAttribute("Hover") or 0) > 0,
			Yaw = -math.pi / 2,
			Model = model,
			Root = body,
			Pos = V3.new(feet.X, 0, feet.Z),
			RootHeight = model:GetAttribute("RootHeight") or 1,
			Slot = i,
			Parts = rest,
		})
	end

	local x = 0
	local walkPhase = 0
	local follow: any = nil
	local lastSpeed = 0
	for i = 0, frames - 1 do
		local t = i * dt
		local now = base + t
		local speed = speedAt(t)
		x += speed * dt
		walkPhase += speed * dt * 0.42
		local p = V3.new(x, 0, 0)
		local accel = (speed - lastSpeed) / dt
		lastSpeed = speed
		-- you: running leans forward a little
		local lean = -math.clamp(speed / 16, 0, 1) * 0.12 + math.clamp(-accel / 200, 0, 0.1)
		local ownerCF = CF.lookAt(p, p + V3.new(1, 0, 0))
		local ownerYaw = select(2, ownerCF:ToEulerAnglesYXZ())
		-- the golems: GolemController's follower walk, times the hook
		for _, pet in pets do
			local flatYaw = CF.new(ownerCF.Position) * CF.Angles(0, ownerYaw, 0)
			local target = (flatYaw * CF.new(H.FOLLOW.Slots[pet.Slot])).Position
			local flat = V3.new(target.X - pet.Pos.X, 0, target.Z - pet.Pos.Z)
			local step = flat * (1 - math.exp(-dt * 3.2))
			local moved = step.Magnitude
			pet.Pos = V3.new(pet.Pos.X + step.X, 0, pet.Pos.Z + step.Z)
			local v = moved / math.max(dt, 1e-3)
			local walking = v > 0.8
			local wantYaw = if walking then math.atan2(-flat.X, -flat.Z) else ownerYaw
			pet.Yaw = H.lerpAngle(pet.Yaw, wantYaw, 1 - math.exp(-dt * (if walking then 9 else 3)))
			local y = 0
			local pitch, roll = 0, 0
			if pet.Floats then
				local k = if walking then math.clamp(v / 10, 0, 1) else 0
				y += math.sin(now * 2.2 + pet.Seed) * 0.08
				pitch = -0.08 * k
			elseif walking then
				pet.Phase += moved / H.FOLLOW.HopStride * math.pi
				local k = math.clamp(v / 10, 0, 1)
				y += math.abs(math.sin(pet.Phase)) * 0.55 * k
				pitch = -0.12 * k
				roll = math.sin(pet.Phase) * 0.08 * k
			else
				y += math.sin(now * 2.2 + pet.Seed) * 0.05
			end
			pet.Root.CFrame = CF.new(pet.Pos.X, y + pet.RootHeight, pet.Pos.Z)
				* CF.Angles(0, pet.Yaw, 0)
				* CF.Angles(pitch, 0, roll)
				* Controller.golemOffset(pet, nil, now, walking, true, v)
		end
		-- the camera follows the golems from the side (smoothed), wider while they sprint, to the front at the rest
		local sum = V3.new(0, 0, 0)
		for _, pet in pets do
			sum += pet.Pos
		end
		-- (between your golems and you: you stay in the picture while they chase you)
		local centroid = (sum / #pets):Lerp(p, 0.5) + V3.new(0, 1.4, 0)
		follow = if follow then follow:Lerp(centroid, 1 - math.exp(-dt * 4)) else centroid
		local gc = follow :: any
		local camPos, camTarget, fov = H.cameraAt({
			{ 0, gc + V3.new(5, 5, -15), gc + V3.new(0, -0.3, 0), 38 },
			{ 4.2, gc + V3.new(4, 5, -15.5), gc + V3.new(0, -0.3, 0), 42 },
			{ 7.3, gc + V3.new(4, 5, -15.5), gc + V3.new(0, -0.3, 0), 44 },
			{ 9.6, gc + V3.new(3, 6.5, -18), gc + V3.new(0, -0.3, 0), 48 },
			{ 11.0, gc + V3.new(10, 4.2, -11.5), gc + V3.new(0.8, -0.4, 0), 32 },
			{ duration, gc + V3.new(10.5, 3.8, -10), gc + V3.new(0.8, -0.5, 0), 30 },
		}, t)
		local focus = opts and opts.focus
		if focus and pets[focus] then
			-- (checking one golem up close: its side, at its height)
			local target = pets[focus].Root.CFrame.Position
			camPos, camTarget, fov = target + V3.new(5.5, 3.2, -3), target, 38
		end
		rig.Eye = camPos
		rig.Clock = now
		Controller.step(dt)
		local seg = if t < 4.2 then 0 elseif t < 7.4 then 1 elseif t < 10.0 then 2 else 3
		local frame = {
			s = 0,
			seg = seg,
			cam = { H.r3(camPos.X), H.r3(camPos.Y), H.r3(camPos.Z), H.r3(camTarget.X), H.r3(camTarget.Y), H.r3(camTarget.Z), H.r3(fov) },
			g = {},
			p = {},
			o = {},
		}
		H.character(CF, frame.p, ownerCF * CF.Angles(lean, 0, 0), math.sin(walkPhase) * math.min(1.1, 0.25 + speed / 18), {
			shirt = C3.fromRGB(64, 120, 200),
			pants = C3.fromRGB(52, 50, 66),
			hair = C3.fromRGB(70, 44, 26),
		})
		-- every golem part: the running limbs where the controller put them, the rest on the Body
		for _, pet in pets do
			local body = pet.Root.CFrame
			for _, item in pet.Parts do
				local part = item.Part
				local cf = if part == pet.Root then body elseif part.Anchored then part.CFrame else body * item.Rest
				table.insert(frame.p, H.partEntry(part, cf))
			end
		end
		table.insert(data.frames, frame)
	end
	local _, running = Controller.golemStats()
	Controller.useRig(nil)
	data.duration = #data.frames / fps
	data.running = running
	local _ = Logic
	return data
end

return GolemRun
