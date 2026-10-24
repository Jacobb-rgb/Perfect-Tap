--[[
	The world animations showreel (owner 2026-10-21: "perfect animations in
	the game world"), frame by frame, for tools/preview/world_anim.html:

	  A golems  the real lobby around Tobin's stall (WorldBuilder): you walk,
	            your golems hop after you (GolemController's follower walk,
	            numbers copied below, plus WorldMotionLogic.golemPose: the
	            wiggle, the nod, the sway, the idle hops), then two golems are
	            equipped: a Rare one jumps and spins, a Legendary one (it
	            hovers) rises and spins
	  B hit     a Deep Hollow rock blasted: every hit a white flash, a star of
	            spikes and cubes in the rock's crystal colour (hitPlan), the
	            rock trembling (RockFxLogic.shakeOffset)
	  C pop     the rock cracks (RockFxLogic.crackPlan: the existing debris),
	            the ore chunk pops out (the real flight is simulated like
	            Roblox physics; its look follows WorldMotionLogic.popPose with
	            the dust of dustPlan), then once more in slow motion
	  D sell    at Tobin's counter: two sales (cashPlan), banknotes flutter,
	            coins fly into you, the +$ popup as SellController shows it

	Every frame lists the moving parts (Export's part encoding) and the
	matrices of the rigid groups (golems, rocks); the static scenes are sent
	once. Only for the preview video (no Studio needed).
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}
local surfaceAlong: (any, any, any) -> any

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance

local GRAVITY = 196.2 -- Roblox physics (the real chunk's flight)
local WHITE = C3.new(1, 1, 1)
local SHAPES = { Block = 0, Ball = 1, Cylinder = 2, Wedge = 3 }

-- GolemController's follower numbers (the preview walks them the same way)
local FOLLOW = {
	Size = 0.85,
	HopStride = 1.7,
	Slots = { V3.new(-3.1, 0, 3.0), V3.new(3.1, 0, 3.0), V3.new(0, 0, 5.2) },
}

---------------------------------------------------------------- encoding

local function r3(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end

local function hex(c): string
	return string.format(
		"%02x%02x%02x",
		math.clamp(math.floor(c.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
	)
end

local function cfList(cf): { number }
	local x, y, z, a, b, c, d, e, f, g, h, i = cf:GetComponents()
	return { r3(x), r3(y), r3(z), r3(a), r3(b), r3(c), r3(d), r3(e), r3(f), r3(g), r3(h), r3(i) }
end

local function shapeOf(part): number
	if part.ClassName == "WedgePart" then
		return SHAPES.Wedge
	elseif part.ClassName == "Part" then
		local s = part.Shape
		if s == Enum.PartType.Ball then
			return SHAPES.Ball
		elseif s == Enum.PartType.Cylinder then
			return SHAPES.Cylinder
		end
	end
	return SHAPES.Block
end

local function entry(shape: number, size, cf, color, material: string, transparency: number, shadow: boolean)
	return { shape, r3(size.X), r3(size.Y), r3(size.Z), cfList(cf), hex(color), material, r3(transparency), 0, if shadow then 1 else 0 }
end

local function partEntry(part, cf: any?, size: any?, transparency: number?)
	return entry(
		shapeOf(part),
		size or part.Size,
		cf or part.CFrame,
		part.Color,
		part.Material.Name,
		transparency or part.Transparency,
		part.CastShadow
	)
end

local function visibleParts(root): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			table.insert(out, d)
		end
	end
	return out
end

local function lightsOf(root, out)
	for _, d in root:GetDescendants() do
		if (d:IsA("PointLight") or d:IsA("SpotLight")) and d.Parent and d.Parent:IsA("BasePart") and d.Enabled then
			local p = d.Parent.CFrame.Position
			table.insert(out, { r3(p.X), r3(p.Y), r3(p.Z), hex(d.Color), d.Range, d.Brightness })
		end
	end
end

-- The SurfaceGuis on the parts under `root` (KitMachines' painted frames, round
-- dots, hazard stripes, text labels) as flat decals for world_anim.js: { face
-- frame (x = the gui's right, y = its up, z = out of the face), width,
-- height, light influence, items { kind ("r" rect, "o" round, "t" text), x, y,
-- w, h (0..1 of the face, y down), colour, text, font } }.
local function faceFrame(face: string, s): (any, number, number)
	local CF = roblox.CFrame
	if face == "Front" then
		return CF.new(0, 0, -s.Z / 2) * CF.Angles(0, math.pi, 0), s.X, s.Y
	elseif face == "Back" then
		return CF.new(0, 0, s.Z / 2), s.X, s.Y
	elseif face == "Right" then
		return CF.new(s.X / 2, 0, 0) * CF.Angles(0, math.pi / 2, 0), s.Z, s.Y
	elseif face == "Left" then
		return CF.new(-s.X / 2, 0, 0) * CF.Angles(0, -math.pi / 2, 0), s.Z, s.Y
	elseif face == "Top" then
		return CF.new(0, s.Y / 2, 0) * CF.Angles(-math.pi / 2, 0, 0), s.X, s.Z
	end
	return CF.new(0, -s.Y / 2, 0) * CF.Angles(math.pi / 2, 0, 0), s.X, s.Z
end

local function surfaceDecals(root): { any }
	local out = {}
	for _, gui in root:GetDescendants() do
		local part = gui.Parent
		if gui:IsA("SurfaceGui") and part and part:IsA("BasePart") and part.Transparency < 0.99 then
			local frame, w, h = faceFrame(gui.Face.Name, part.Size)
			local items = {}
			local function add(kind: string, r, color, text: string?, font: string?)
				table.insert(items, { kind, r3(r[1]), r3(r[2]), r3(r[3]), r3(r[4]), hex(color), text or "", font or "" })
			end
			-- each gui object's rect in face fractions (scale only, like the builders);
			-- (Lune hands out a new reference per access: walk down, never key by instance)
			local function walk(holder, pr)
				for _, o in holder:GetChildren() do
					if not (o:IsA("GuiObject") and o.Visible) then
						continue
					end
					local r = {
						pr[1] + o.Position.X.Scale * pr[3],
						pr[2] + o.Position.Y.Scale * pr[4],
						o.Size.X.Scale * pr[3],
						o.Size.Y.Scale * pr[4],
					}
					local gradient = o:FindFirstChildWhichIsA("UIGradient")
					if gradient and o.BackgroundTransparency < 1 then
						-- hard stripes: two keypoints per stripe, side by side
						local keys = gradient.Color.Keypoints
						for k = 1, #keys, 2 do
							local a = keys[k].Time
							local b = if keys[k + 2] then keys[k + 2].Time else 1
							add("r", { r[1] + a * r[3], r[2], (b - a) * r[3], r[4] }, keys[k].Value)
						end
					elseif o.BackgroundTransparency < 1 then
						add(if o:FindFirstChildWhichIsA("UICorner") then "o" else "r", r, o.BackgroundColor3)
					end
					if o:IsA("TextLabel") and o.Text ~= "" then
						add("t", r, o.TextColor3, o.Text, o.FontFace.Family)
					end
					walk(o, r)
				end
			end
			walk(gui, { 0, 0, 1, 1 })
			if #items > 0 then
				local ok, influence = pcall(function()
					return gui.LightInfluence
				end)
				local cf = part.CFrame * frame * roblox.CFrame.new(0, 0, 0.012)
				table.insert(out, { cfList(cf), r3(w), r3(h), if ok then r3(influence) else 1, items })
			end
		end
	end
	return out
end

---------------------------------------------------------------- small helpers

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- A camera path: keys { t, position, target, fov }, eased between keys.
local function cameraAt(keys, t: number)
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i][1] and t <= keys[i + 1][1] then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	if t <= keys[1][1] then
		b = a
	end
	local span = b[1] - a[1]
	local k = if span > 0 then smooth((t - a[1]) / span) else 0
	return a[2]:Lerp(b[2], k), a[3]:Lerp(b[3], k), a[4] + (b[4] - a[4]) * k
end

-- The camera basis (right, up) for a camera at `position` looking at `target`.
local function basis(CF, position, target)
	local cf = CF.lookAt(position, target)
	return cf.RightVector, cf.UpVector
end

---------------------------------------------------------------- a blocky player

local SKIN = C3.fromRGB(236, 190, 150)

-- A Roblox-like blocky character at `root` (the feet, facing LookVector), legs and arms swinging by `swing`.
local function character(CF, out, root, swing: number, colors)
	local shirt = colors.shirt
	local pants = colors.pants
	local function add(cf, size, color)
		table.insert(out, entry(SHAPES.Block, size, cf, color, "SmoothPlastic", 0, true))
	end
	for _, side in { -1, 1 } do
		local hip = root * CF.new(side * 0.5, 2, 0)
		add(hip * CF.Angles(swing * side, 0, 0) * CF.new(0, -1, 0), V3.new(0.95, 2, 0.95), pants)
		local shoulder = root * CF.new(side * 1.5, 3.9, 0)
		local arm = if colors.hold and side == 1 then -math.pi / 2 else -swing * side * 0.8
		add(shoulder * CF.Angles(arm, 0, side * 0.04) * CF.new(0, -0.9, 0), V3.new(0.95, 2, 0.95), shirt)
	end
	add(root * CF.new(0, 3, 0), V3.new(2, 2, 1), shirt)
	add(root * CF.new(0, 2.7, -0.53), V3.new(1.6, 2.3, 0.08), C3.fromRGB(110, 70, 40)) -- apron
	add(root * CF.new(0, 4.65, 0), V3.new(1.2, 1.2, 1.2), SKIN)
	add(root * CF.new(0, 5.3, 0.1), V3.new(1.28, 0.32, 1.28), colors.hair)
	add(root * CF.new(-0.27, 4.75, -0.61), V3.new(0.16, 0.26, 0.04), C3.fromRGB(40, 30, 30))
	add(root * CF.new(0.27, 4.75, -0.61), V3.new(0.16, 0.26, 0.04), C3.fromRGB(40, 30, 30))
	add(root * CF.new(0, 4.42, -0.61), V3.new(0.42, 0.08, 0.04), C3.fromRGB(120, 60, 50)) -- smile
end

---------------------------------------------------------------- the data

type Ctx = {
	Loader: any,
	CF: any,
	Logic: any,
	fps: number,
	data: any,
	scenes: { [string]: number },
}

local function addScene(ctx: Ctx, id: string, parts, lights, look: string)
	table.insert(ctx.data.scenes, { id = id, parts = parts, lights = lights, look = look })
	ctx.scenes[id] = #ctx.data.scenes - 1
end

local function addGroup(ctx: Ctx, model, pivot): number
	local inv = pivot:Inverse()
	local parts = {}
	for _, d in visibleParts(model) do
		table.insert(parts, partEntry(d, inv * d.CFrame))
	end
	table.insert(ctx.data.groups, { parts = parts })
	return #ctx.data.groups - 1
end

local function newFrame(ctx: Ctx, scene: string, position, target, fov: number, segment: number)
	local frame = {
		s = ctx.scenes[scene],
		seg = segment,
		cam = { r3(position.X), r3(position.Y), r3(position.Z), r3(target.X), r3(target.Y), r3(target.Z), r3(fov) },
		g = {},
		p = {},
		o = {},
	}
	table.insert(ctx.data.frames, frame)
	return frame
end

local function putGroup(frame, index: number, cf)
	local list = cfList(cf)
	table.insert(list, 1, index)
	table.insert(frame.g, list)
end

-- The live bits of WorldMotionLogic at `t` into the frame (those still alive); returns the ones kept.
local function drawBits(ctx: Ctx, frame, bits, t: number)
	local keep = {}
	for _, bit in bits do
		local cf, size, transparency, done = ctx.Logic.sample(bit, t - bit.Born)
		if not done and t >= bit.Born then
			local shape = if bit.Shape == "Ball" then SHAPES.Ball elseif bit.Shape == "Cylinder" then SHAPES.Cylinder else SHAPES.Block
			table.insert(frame.p, entry(shape, size, cf, bit.Color, if bit.Neon then "Neon" else "SmoothPlastic", transparency, false))
			table.insert(keep, bit)
		elseif t < bit.Born then
			table.insert(keep, bit)
		end
	end
	return keep
end

local function spawn(bits, list, born: number, alive: number, cap: number)
	for _, bit in list do
		if alive >= cap then
			break
		end
		bit.Born = born
		table.insert(bits, bit)
		alive += 1
	end
end

---------------------------------------------------------------- golem followers

type Pet = {
	Kind: string,
	Group: number,
	RootHeight: number,
	Slot: number,
	Pos: any,
	Yaw: number,
	Phase: number,
	Seed: number,
	Floats: boolean,
	Celebrate: number?,
	Born: number,
}

local function newPet(ctx: Ctx, kind: string, slot: number, ownerCF, born: number, celebrate: boolean): Pet
	local GolemBuilder = ctx.Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local CF = ctx.CF
	local model = GolemBuilder.build(kind, CF.new(), { Size = FOLLOW.Size })
	local body = model.PrimaryPart
	local _, yaw = ownerCF:ToEulerAnglesYXZ()
	local feet = (ownerCF * CF.new(FOLLOW.Slots[slot])).Position
	return {
		Kind = kind,
		Group = addGroup(ctx, model, body.CFrame),
		RootHeight = model:GetAttribute("RootHeight") or 1,
		Slot = slot,
		Pos = V3.new(feet.X, 0, feet.Z),
		Yaw = yaw,
		Phase = 0,
		Seed = slot * 1.7 + 41 * 0.13,
		Floats = (model:GetAttribute("Hover") or 0) > 0,
		Celebrate = if celebrate then born else nil,
		Born = born,
	}
end

-- One frame of GolemController.stepPets for a pet (ground y = groundY), times the WorldMotion hook. Returns its Body CFrame.
local function stepPet(ctx: Ctx, pet: Pet, ownerCF, now: number, dt: number, groundY: number)
	local CF = ctx.CF
	local Logic = ctx.Logic
	local _, ownerYaw = ownerCF:ToEulerAnglesYXZ()
	local flatYaw = CF.new(ownerCF.Position) * CF.Angles(0, ownerYaw, 0)
	local target = (flatYaw * CF.new(FOLLOW.Slots[pet.Slot])).Position
	local flat = V3.new(target.X - pet.Pos.X, 0, target.Z - pet.Pos.Z)
	local step = flat * (1 - math.exp(-dt * 3.2))
	local moved = step.Magnitude
	pet.Pos = V3.new(pet.Pos.X + step.X, groundY, pet.Pos.Z + step.Z)
	local speed = moved / math.max(dt, 1e-3)
	local walking = speed > 0.8
	local wantYaw = if walking then math.atan2(-flat.X, -flat.Z) else ownerYaw
	pet.Yaw = lerpAngle(pet.Yaw, wantYaw, 1 - math.exp(-dt * (if walking then 9 else 3)))
	local y = groundY
	local pitch, roll = 0, 0
	if pet.Floats then
		local k = if walking then math.clamp(speed / 10, 0, 1) else 0
		y += math.sin(now * 2.2 + pet.Seed) * 0.08
		pitch = -0.08 * k
	elseif walking then
		pet.Phase += moved / FOLLOW.HopStride * math.pi
		local k = math.clamp(speed / 10, 0, 1)
		y += math.abs(math.sin(pet.Phase)) * 0.55 * k
		pitch = -0.12 * k
		roll = math.sin(pet.Phase) * 0.08 * k
	else
		y += math.sin(now * 2.2 + pet.Seed) * 0.05
	end
	-- the hook (WorldMotionController.golemOffset)
	local since = if pet.Celebrate then now - pet.Celebrate else nil
	if since and since > Logic.Golem.JumpTime then
		pet.Celebrate = nil
		since = nil
	end
	local lift, p2, yaw2, r2 = Logic.golemPose(now, pet.Phase, pet.Seed, walking, true, pet.Floats, since, false)
	return CF.new(pet.Pos.X, y + pet.RootHeight, pet.Pos.Z)
		* CF.Angles(0, pet.Yaw, 0)
		* CF.Angles(pitch, 0, roll)
		* CF.new(0, lift, 0)
		* CF.fromEulerAnglesYXZ(p2, yaw2, r2)
end

---------------------------------------------------------------- scenes

-- The real lobby around Tobin's stall: (parts, lights, counter part, the plaza point in front of it).
local function lobbyScene(ctx: Ctx)
	local WorldBuilder = ctx.Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local game = Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local map = WorldBuilder.build(workspace)
	local counter = nil
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "SellCounter" then
			counter = d
			break
		end
	end
	assert(counter, "no SellCounter in the lobby")
	local focus = counter.CFrame.Position
	local parts = {}
	for _, d in visibleParts(map) do
		local p = d.CFrame.Position
		local dx, dz = p.X - focus.X, p.Z - focus.Z
		local reach = 150 + d.Size.Magnitude / 2
		if dx * dx + dz * dz <= reach * reach then
			table.insert(parts, partEntry(d))
		end
	end
	local lights = {}
	lightsOf(map, lights)
	table.sort(lights, function(a, b)
		local da = (a[1] - focus.X) ^ 2 + (a[3] - focus.Z) ^ 2
		local db = (b[1] - focus.X) ^ 2 + (b[3] - focus.Z) ^ 2
		return da < db
	end)
	local near = {}
	for i = 1, math.min(10, #lights) do
		table.insert(near, lights[i])
	end
	return parts, near, counter
end

-- A Deep Hollow mine stage: ground, walls, lamps, a few side rocks, and the main rock (separately, as a group).
local function mineScene(ctx: Ctx, floorIndex: number)
	local CF = ctx.CF
	local Geo = ctx.Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local MineFloors = ctx.Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = ctx.Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local floor = MineFloors.get(floorIndex)
	local pal = floor.Palette
	local root = Instance.new("Model")
	Geo.block(root, CF.new(0, -0.5, 0), V3.new(120, 1, 120), pal.Ground)
	Geo.block(root, CF.new(0, 14, -26), V3.new(120, 30, 3), pal.Dark)
	Geo.block(root, CF.new(-40, 14, 0), V3.new(3, 30, 80), pal.Dark)
	Geo.block(root, CF.new(40, 14, 0), V3.new(3, 30, 80), pal.Dark)
	-- a few pebbles and side rocks so the floor reads as the mine
	local ores = { "Sapphire", "Jade", "Gold" }
	for i, spot in { V3.new(-15, 0, -12), V3.new(14, 0, -14), V3.new(-22, 0, 8), V3.new(24, 0, 6), V3.new(4, 0, -20) } do
		RockBuilder.build(floorIndex, if i % 2 == 0 then "Small" else "Crystal", ores, CF.new(spot) * CF.Angles(0, i * 1.3, 0), 900 + i).Parent =
			root
	end
	for i = 1, 26 do
		local a = i * 2.39
		local r = 9 + (i * 7.3) % 22
		local s = 0.4 + (i % 4) * 0.25
		Geo.block(
			root,
			CF.new(math.cos(a) * r, s * 0.3, math.sin(a) * r - 4) * CF.Angles(0.3 * i, a, 0.2),
			V3.new(s, s * 0.6, s),
			pal.Mid:Lerp(pal.Dark, (i % 3) * 0.3)
		)
	end
	-- glowing crystal clusters on the back wall
	for i = 1, 7 do
		local x = -30 + i * 8.5
		local h = 2 + (i % 3) * 2.5
		Geo.block(
			root,
			CF.new(x, h, -24.2) * CF.Angles(0, 0, 0.3 * ((i % 3) - 1)),
			V3.new(0.7, 2.2 + (i % 2), 0.7),
			pal.Crystal,
			Enum.Material.Neon
		)
	end
	local lights = {
		{ -12, 12, 10, hex(C3.fromRGB(255, 236, 214)), 40, 1.6 },
		{ 12, 12, 10, hex(C3.fromRGB(255, 236, 214)), 40, 1.6 },
		{ 0, 6, -18, hex(pal.Crystal), 30, 1.4 },
	}
	local parts = {}
	for _, d in visibleParts(root) do
		table.insert(parts, partEntry(d))
	end
	return parts, lights, floor
end

-- The first point on the line from `from` to `to` inside one of the model's visible parts (a raycast stand-in).
surfaceAlong = function(model, from, to)
	local parts = visibleParts(model)
	local length = (to - from).Magnitude
	local dir = (to - from).Unit
	local d = 0
	while d <= length do
		local p = from + dir * d
		for _, part in parts do
			local rel = part.CFrame:PointToObjectSpace(p)
			local h = part.Size / 2
			if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
				return p
			end
		end
		d += 0.05
	end
	return to
end

---------------------------------------------------------------- the segments

local function segmentGolems(ctx: Ctx, t0: number, duration: number, lobby)
	local CF = ctx.CF
	local counter = lobby.counter
	local front = counter.CFrame.LookVector * V3.new(1, 0, 1)
	front = front.Unit
	local side = V3.new(-front.Z, 0, front.X)
	local focus = counter.CFrame.Position * V3.new(1, 0, 1)
	-- the walk: along the stall's front, across the camera
	local walkFrom = focus + front * 14 - side * 16
	local walkTo = focus + front * 14 + side * 6
	local dir = (walkTo - walkFrom).Unit
	local walkEnd = 2.3
	local startCF = CF.lookAt(walkFrom, walkFrom + dir)
	local pets = { newPet(ctx, "PebbleGolem", 1, startCF, 0, false) }
	local equips = { { At = 3.0, Kind = "EmberImp", Slot = 2 }, { At = 4.25, Kind = "StormTitan", Slot = 3 } }
	local dt = 1 / ctx.fps
	local frames = math.floor(duration * ctx.fps + 0.5)
	local last = walkFrom
	local walkPhase = 0
	for i = 0, frames - 1 do
		local t = i * dt
		local k = smooth(math.clamp((t - 0.2) / (walkEnd - 0.2), 0, 1))
		local p = walkFrom:Lerp(walkTo, k)
		local speed = (p - last).Magnitude / dt
		last = p
		walkPhase += speed * dt * 0.55
		local turn = math.clamp((t - walkEnd - 0.3) / 0.6, 0, 1)
		-- after the walk, turn a little toward the camera
		local look = dir:Lerp(front, smooth(turn) * 0.15).Unit
		local ownerCF = CF.lookAt(p, p + look)
		for _, e in equips do
			if not e.Done and t >= e.At then
				e.Done = true
				table.insert(pets, newPet(ctx, e.Kind, e.Slot, ownerCF, 1000 + t, true))
			end
		end
		-- the camera on the plaza side follows you and your golems (they trail behind you)
		local group = p - dir * 3 + V3.new(0, 1.6, 0)
		local camPos, camTarget, fov = cameraAt({
			{ 0, group + front * 21 - dir * 7 + V3.new(0, 10, 0), group, 40 },
			{ walkEnd, group + front * 19 - dir * 5 + V3.new(0, 9.5, 0), group, 38 },
			{ 3.6, group + front * 15 - dir * 3 + V3.new(0, 8, 0), group + V3.new(0, 0.6, 0), 38 },
			{ duration, group + front * 14 - dir * 1 + V3.new(0, 7.2, 0), group + V3.new(0, 0.8, 0), 38 },
		}, t)
		local frame = newFrame(ctx, "lobby", camPos, camTarget, fov, 0)
		character(CF, frame.p, ownerCF, math.sin(walkPhase) * 0.7 * math.min(1, speed / 6), {
			shirt = C3.fromRGB(64, 120, 200),
			pants = C3.fromRGB(52, 50, 66),
			hair = C3.fromRGB(70, 44, 26),
		})
		for _, pet in pets do
			putGroup(frame, pet.Group, stepPet(ctx, pet, ownerCF, 1000 + t, dt, 0))
		end
	end
	return pets
end

local function segmentHit(ctx: Ctx, duration: number, mine)
	local CF = ctx.CF
	local Logic = ctx.Logic
	local Gallery = require("./blaster_gallery")
	local BlasterBuilder = ctx.Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local RockFxLogic = ctx.Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RockFxLogic")
	local rockPivot = mine.rockPivot
	local aim = mine.aim
	local muzzle = mine.muzzle
	local crystal = RockFxLogic.colors(mine.floor.Index, "Big", mine.floor.Palette.Mid, mine.glow).Crystal[1]
	local dt = 1 / ctx.fps
	local frames = math.floor(duration * ctx.fps + 0.5)
	local bits = {}
	local nextHit = 0.35
	local lastHit = -10
	local caps = Logic.caps(false, false)
	local _ = Gallery
	local _b = BlasterBuilder
	for i = 0, frames - 1 do
		local t = i * dt
		local camPos, camTarget, fov = cameraAt({
			{ 0, aim + V3.new(3.5, 3.4, 12.5), aim + V3.new(-2.2, 0.2, 0), 44 },
			{ duration, aim + V3.new(2.8, 2.2, 8), aim + V3.new(-1, 0.1, 0), 40 },
		}, t)
		local right, up = basis(CF, camPos, camTarget)
		if t >= nextHit and t < duration - 0.4 then
			nextHit += 0.3
			lastHit = t
			spawn(
				bits,
				Logic.hitPlan({
					Position = aim,
					Back = muzzle - aim,
					Color = crystal,
					Right = right,
					Up = up,
					Ground = 0,
					Seed = 11 + i,
					Room = caps.Bits - #bits,
				}),
				t,
				#bits,
				caps.Bits
			)
		end
		local frame = newFrame(ctx, "mine_beam", camPos, camTarget, fov, 1)
		putGroup(frame, mine.rockGroup, rockPivot * RockFxLogic.shakeOffset(t - lastHit, 0.22, 0.12, 3))
		bits = drawBits(ctx, frame, bits, t)
	end
end

-- Roblox-like flight of a dirty ore chunk: ballistic, bounces (elasticity 0.25), settles flat.
local function chunkFlight(ctx: Ctx, origin, velocity, spin, startRot, seconds: number, dt: number)
	local CF = ctx.CF
	local states = {}
	local p, v, w = origin, velocity, spin
	local rot = startRot
	local half = 0.62
	local sub = 6
	local t = 0
	while t <= seconds + 1e-6 do
		table.insert(states, { CF = CF.new(p) * rot, Vy = v.Y })
		for _ = 1, sub do
			local h = dt / sub
			v = v - V3.new(0, GRAVITY * h, 0)
			p = p + v * h
			if w.Magnitude > 1e-3 then
				rot = CF.fromAxisAngle(w.Unit, w.Magnitude * h) * rot
			end
			if p.Y - half < 0 then
				p = V3.new(p.X, half, p.Z)
				if v.Y < -4 then
					v = V3.new(v.X * 0.7, -v.Y * 0.25, v.Z * 0.7)
					w = w * 0.55
				else
					v = V3.new(v.X * 0.86, 0, v.Z * 0.86)
					w = w * 0.8
					-- settle onto its nearest face
					local cf = CF.new() * rot
					local upLocal = cf:VectorToObjectSpace(V3.new(0, 1, 0))
					local ax = { math.abs(upLocal.X), math.abs(upLocal.Y), math.abs(upLocal.Z) }
					local axis = if ax[2] >= ax[1] and ax[2] >= ax[3]
						then V3.new(0, 1, 0)
						elseif ax[1] >= ax[3] then V3.new(1, 0, 0)
						else V3.new(0, 0, 1)
					local world = cf:VectorToWorldSpace(axis)
					if world.Y < 0 then
						world = -world
					end
					local cross = world:Cross(V3.new(0, 1, 0))
					local angle = math.acos(math.clamp(world.Y, -1, 1))
					if cross.Magnitude > 1e-4 and angle > 1e-3 then
						rot = CF.fromAxisAngle(cross.Unit, angle * math.min(1, 10 * h)) * rot
					end
				end
			end
		end
		t += dt
	end
	return states
end

local function segmentPop(ctx: Ctx, duration: number, mine)
	local CF = ctx.CF
	local Logic = ctx.Logic
	local ItemBuilder = ctx.Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local RockFxLogic = ctx.Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RockFxLogic")
	local Pop = Logic.Pop
	local pal = mine.floor.Palette
	local rockPivot = mine.rockPivot
	local aim = mine.aim
	local center = rockPivot.Position
	local out = (mine.camFlat).Unit
	-- the chunk's look (all Raw chunks look the same; parts relative to the Body)
	local chunk = ItemBuilder.build({ Kind = "Raw", OreId = "Sapphire" }, CF.new(), 7)
	local body = chunk.PrimaryPart
	local look = {}
	local inv = body.CFrame:Inverse()
	for _, d in visibleParts(chunk) do
		table.insert(look, { Part = d, Offset = inv * d.CFrame, Size = d.Size })
	end
	local dust = body.Color:Lerp(C3.fromRGB(176, 156, 134), 0.45)
	local crackGlow = ctx.Loader.requirePath("ReplicatedStorage.Shared.Config.OreData").ById.Sapphire.Glow
	-- two pops: one at normal speed, then one in slow motion
	local runs = {
		{ Start = 0.0, Crack = 0.3, Scale = 1, Out = CF.Angles(0, 0.35, 0):VectorToWorldSpace(out), Seed = 3, Until = 2.1 },
		{ Start = 2.1, Crack = 2.25, Scale = 0.3, Out = CF.Angles(0, -0.3, 0):VectorToWorldSpace(out), Seed = 9, Until = duration },
	}
	local dt = 1 / ctx.fps
	local frames = math.floor(duration * ctx.fps + 0.5)
	for _, run in runs do
		-- the real flight (game time), sampled at the frame's game-time step
		local gdt = dt * run.Scale
		local origin = center + V3.new(0, mine.radius * 0.5 + 1.5, 0) + run.Out * 0.8
		local velocity = run.Out * 9 + V3.new(0, 16, 0)
		run.Flight = chunkFlight(ctx, origin, velocity, V3.new(4, 6, -3), CF.Angles(0.4, 1.1, 0.2), 3, gdt)
		run.GameDt = gdt
		local first = run.Flight[1].CF
		run.Predicted = Logic.landTime(velocity.Y, first.Position.Y - body.Size.Y / 2, GRAVITY)
		run.Pieces = RockFxLogic.crackPlan({
			Position = aim,
			Crust = pal.Mid,
			Glow = crackGlow,
			Stage = 2,
			Stages = 4,
			Out = mine.camFlat,
			Ground = 0,
			Seed = run.Seed,
		})
	end
	local caps = Logic.caps(false, false)
	for i = 0, frames - 1 do
		local t = i * dt
		local run = if t < runs[2].Start then runs[1] else runs[2]
		local slow = run.Scale < 1
		local camPos, camTarget, fov
		if slow then
			camPos, camTarget, fov = cameraAt({
				{ run.Start, center + V3.new(11, 4.6, 13.5), center + run.Out * 2.6 + V3.new(0, 2.4, 0), 42 },
				{ duration, center + V3.new(9.5, 3.4, 11.5), center + run.Out * 3.4 + V3.new(0, 1.2, 0), 39 },
			}, t)
		else
			camPos, camTarget, fov = cameraAt({
				{ 0, center + V3.new(10.5, 5.5, 13), center + V3.new(0, 2, 0) + run.Out * 1.8, 42 },
				{ run.Until, center + V3.new(9, 4.2, 11.5), center + V3.new(0, 1.4, 0) + run.Out * 2.6, 40 },
			}, t)
		end
		-- game time in this run since its start
		local g = (t - run.Start) * run.Scale
		local crackAt = (run.Crack - run.Start) * run.Scale
		local cracked = g >= crackAt
		-- the beam stays on the rock until it cracks
		local frame = newFrame(ctx, if cracked then "mine" else "mine_beam", camPos, camTarget, fov, if slow then 3 else 2)
		putGroup(
			frame,
			if cracked then mine.crackedGroup else mine.rockGroup,
			rockPivot * RockFxLogic.shakeOffset(g - crackAt, 0.22, 0.25, 5)
		)
		if cracked then
			local age = g - crackAt
			-- the existing crack debris (RockFx) and a soft flash
			for _, piece in run.Pieces do
				local cf, scale, transparency, done = RockFxLogic.sample(piece, age)
				if not done then
					table.insert(
						frame.p,
						entry(
							if piece.Wedge then SHAPES.Wedge else SHAPES.Block,
							piece.Size * scale,
							cf,
							piece.Color,
							if piece.Neon then "Neon" else "SmoothPlastic",
							transparency,
							false
						)
					)
				end
			end
			-- the chunk: its real flight, and the pop look-alike on top
			local index = math.clamp(math.floor(age / run.GameDt + 0.5) + 1, 1, #run.Flight)
			local state = run.Flight[index]
			local bodyCF = state.CF
			run.Bits = run.Bits or {}
			if not run.Popped then
				run.Popped = true
				run.LastVy = state.Vy
				spawn(
					run.Bits,
					Logic.dustPlan({
						Position = bodyCF.Position,
						Color = dust,
						Ground = 0,
						Seed = run.Seed,
						Landing = false,
						Count = Logic.dustCount(false, false, false),
					}),
					age,
					0,
					caps.Bits
				)
			end
			if run.Landed == nil and age > 0.04 and Logic.landed(run.LastVy, state.Vy, age, run.Predicted) then
				run.Landed = age
				spawn(
					run.Bits,
					Logic.dustPlan({
						Position = bodyCF.Position,
						Color = dust,
						Ground = 0,
						Seed = run.Seed + 3,
						Landing = true,
						Count = Logic.dustCount(false, false, true),
					}),
					age,
					#run.Bits,
					caps.Bits
				)
			end
			run.LastVy = state.Vy
			local lift, spin, wide, tall, done = Logic.popPose(age, run.Predicted, run.Landed)
			if done then
				for _, item in look do
					table.insert(frame.p, partEntry(item.Part, bodyCF * item.Offset))
				end
			else
				local scale = Logic.squashAxes(bodyCF, wide, tall)
				local drop = if run.Landed then (1 - tall) * body.Size.Y / 2 else 0
				local root = Logic.popRoot(bodyCF, lift, spin, drop)
				for _, item in look do
					local cf, size = Logic.popPart(root, scale, item.Offset, item.Size)
					table.insert(frame.p, partEntry(item.Part, cf, size))
				end
			end
			run.Bits = drawBits(ctx, frame, run.Bits, age)
		end
		if slow then
			frame.label = "slow"
		end
	end
end

local function segmentSell(ctx: Ctx, duration: number, lobby, pets)
	local CF = ctx.CF
	local Logic = ctx.Logic
	local counter = lobby.counter
	local front = (counter.CFrame.LookVector * V3.new(1, 0, 1)).Unit
	local side = V3.new(-front.Z, 0, front.X)
	local top = counter.CFrame.Position + V3.new(0, counter.Size.Y / 2, 0)
	local sellAt = top + V3.new(0, 1.5, 0) -- SellService's popup point (no SellPromptPoint)
	local feet = V3.new(top.X, 0, top.Z) + front * 2.8
	local ownerCF = CF.lookAt(feet, feet - front)
	local root = feet + V3.new(0, 3, 0)
	local sales = { { At = 0.35, Count = 4, Amount = 180 }, { At = 1.6, Count = 12, Amount = 640 }, { At = 1.95, Count = 3, Amount = 150 } }
	local dt = 1 / ctx.fps
	local frames = math.floor(duration * ctx.fps + 0.5)
	local bits = {}
	local caps = Logic.caps(false, false)
	local popups = {}
	-- the golems take their places behind you first (they were following)
	for _, pet in pets do
		local target = (ownerCF * CF.new(FOLLOW.Slots[pet.Slot])).Position
		pet.Pos = V3.new(target.X, 0, target.Z)
		local _, yaw = ownerCF:ToEulerAnglesYXZ()
		pet.Yaw = yaw
		pet.Celebrate = nil
	end
	for i = 0, frames - 1 do
		local t = i * dt
		local camPos, camTarget, fov = cameraAt({
			{ 0, feet + front * 9 + side * 6 + V3.new(0, 7.5, 0), sellAt + front * 1.8 + V3.new(0, 1.2, 0), 46 },
			{ duration, feet + front * 8 + side * 5 + V3.new(0, 7, 0), sellAt + front * 1.8 + V3.new(0, 1.2, 0), 44 },
		}, t)
		for _, sale in sales do
			if not sale.Done and t >= sale.At then
				sale.Done = true
				spawn(
					bits,
					Logic.cashPlan({
						Position = sellAt,
						Ground = 0,
						Home = root + V3.new(0, 1, 0),
						Seed = 5 + sale.Count,
						Items = sale.Count,
						Room = caps.Bits - #bits,
					}),
					t,
					#bits,
					caps.Bits
				)
				-- SellController's popup: sales within the combo window pump the same one
				local last = popups[#popups]
				if last and t - last.LastAt <= 0.8 then
					last.Total += sale.Amount
					last.Sales += 1
					last.LastAt = t
					last.Born = t
				else
					table.insert(popups, { Born = t, LastAt = t, Total = sale.Amount, Sales = 1, Items = sale.Count })
				end
			end
		end
		local frame = newFrame(ctx, "lobby", camPos, camTarget, fov, 4)
		character(CF, frame.p, ownerCF, 0, {
			shirt = C3.fromRGB(64, 120, 200),
			pants = C3.fromRGB(52, 50, 66),
			hair = C3.fromRGB(70, 44, 26),
		})
		for _, pet in pets do
			putGroup(frame, pet.Group, stepPet(ctx, pet, ownerCF, 2000 + t, dt, 0))
		end
		bits = drawBits(ctx, frame, bits, t)
		for _, popup in popups do
			local age = t - popup.Born
			if age >= 0 and age <= 1.1 then
				-- pop in (Back, 0.18 s), rise 3.5 studs (Quad out, 1.1 s), fade the last 0.35 s
				local k = math.clamp(age / 0.18, 0, 1)
				local c1 = 1.70158
				local back = 1 + (c1 + 1) * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
				local start = 1.4 + 0.05 * math.min(popup.Sales, 8)
				local scale = start + (1 - start) * back
				local rise = 3.5 * (1 - (1 - age / 1.1) ^ 2)
				local alpha = if age < 0.75 then 1 else 1 - (age - 0.75) / 0.35
				local p = sellAt + V3.new(0, 1.5 + rise, 0)
				local text = "+$" .. tostring(popup.Total)
				local line = if popup.Sales > 1 then "COMBO x" .. popup.Sales else popup.Items .. " items"
				table.insert(frame.o, { text, line, r3(p.X), r3(p.Y), r3(p.Z), r3(alpha), r3(scale) })
			end
		end
	end
end

---------------------------------------------------------------- build

function Preview.build(Loader, opts)
	local CF = Loader.CFrame
	local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.WorldMotionLogic")
	local fps = opts and opts.fps or 30
	local data = {
		fps = fps,
		scenes = {},
		groups = {},
		frames = {},
		segments = {
			{ title = "GOLEMOVÉ HOPSAJÍ ZA TEBOU", sub = "houpání, mávání a radostný skok s otočkou, když ho nasadíš" },
			{ title = "ZÁSAH: BÍLÝ ZÁBLESK A KOSTIČKY RUDY", sub = "každý zásah blasteru, kostičky v barvě krystalů kamene" },
			{ title = "RUDA VYSKOČÍ Z KAMENE", sub = "otočka, dopad se zmáčknutím a obláček prachu" },
			{ title = "RUDA VYSKOČÍ Z KAMENE", sub = "zpomaleně" },
			{ title = "PRODEJ: PENÍZE LÍTAJÍ", sub = "bankovky vyletí z pultu, mince letí k tobě" },
		},
	}
	local ctx: Ctx = { Loader = Loader, CF = CF, Logic = Logic, fps = fps, data = data, scenes = {} }

	-- the lobby
	local lobbyParts, lobbyLights, counter = lobbyScene(ctx)
	addScene(ctx, "lobby", lobbyParts, lobbyLights, "day")
	local lobby = { counter = counter }

	-- the mine (Deep Hollow: azure crystals)
	local Gallery = require("./blaster_gallery")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local mineParts, mineLights, floor = mineScene(ctx, 3)
	local rock = RockBuilder.build(3, "Big", { "Sapphire", "Jade", "Gold" }, CF.new(0, 0, 0), 4242)
	local cracked = RockBuilder.build(3, "Big", { "Sapphire", "Jade", "Gold" }, CF.new(0, 0, 0), 4242)
	for stage = 1, 2 do
		for _, piece in RockBuilder.applyStage(cracked, stage, 9) do
			piece:Destroy()
		end
	end
	local rockPivot = rock.PrimaryPart.CFrame
	local radius = math.max(rock.PrimaryPart.Size.X, rock.PrimaryPart.Size.Z) * 0.45
	local feet = V3.new(-9, 0, 7)
	local aim0 = Gallery.surface(rock, feet, 0.6)
	-- the shooter with a Lv 6 blaster, its beam on the rock: a static scene of its own
	local shooter = Instance.new("Model")
	local _, muzzle = Gallery.forgekeeper(Loader, shooter, CF.lookAt(feet, V3.new(0, 0, 0)), aim0, 6, "Sapphire")
	local aim = surfaceAlong(rock, muzzle, aim0 + (aim0 - muzzle).Unit * 3)
	local glow = BlasterBuilder.look(6, "Sapphire").Glow
	local beamModel = Instance.new("Model")
	Gallery.beam(Loader, beamModel, muzzle, aim, glow)
	local beamParts = table.clone(mineParts)
	for _, d in visibleParts(shooter) do
		table.insert(beamParts, partEntry(d))
	end
	for _, d in visibleParts(beamModel) do
		table.insert(beamParts, partEntry(d))
	end
	local beamLights = table.clone(mineLights)
	lightsOf(beamModel, beamLights)
	addScene(ctx, "mine_beam", beamParts, beamLights, "mine")
	local mineWithShooter = table.clone(mineParts)
	for _, d in visibleParts(shooter) do
		table.insert(mineWithShooter, partEntry(d))
	end
	addScene(ctx, "mine", mineWithShooter, mineLights, "mine")
	local mine = {
		floor = floor,
		rockGroup = addGroup(ctx, rock, rockPivot),
		crackedGroup = addGroup(ctx, cracked, rockPivot),
		rockPivot = rockPivot,
		radius = radius,
		aim = aim,
		muzzle = muzzle,
		glow = glow,
		camFlat = (feet - rockPivot.Position) * V3.new(1, 0, 1) + V3.new(6, 0, 4),
	}

	-- the timeline
	local durations = { 6.4, 3.4, 4.6, 3.6 }
	local pets = segmentGolems(ctx, 0, durations[1], lobby)
	segmentHit(ctx, durations[2], mine)
	segmentPop(ctx, durations[3], mine)
	-- (the golems stay out of this shot: it is about the cash)
	local _ = pets
	segmentSell(ctx, durations[4], lobby, {})
	data.duration = #data.frames / fps
	return data
end

-- helpers the golem run reel shares (tools/lune/lib/golem_run_preview.luau)
Preview.helpers = {
	entry = entry,
	partEntry = partEntry,
	cfList = cfList,
	character = character,
	cameraAt = cameraAt,
	visibleParts = visibleParts,
	surfaceDecals = surfaceDecals,
	SHAPES = SHAPES,
	FOLLOW = FOLLOW,
	r3 = r3,
	lerpAngle = lerpAngle,
	smooth = smooth,
}

return Preview
