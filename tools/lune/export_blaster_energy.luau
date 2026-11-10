--[[
	The minigun blasters (Builders/MinigunBlaster, owner 2026-10-31) for the
	preview renderer, as the game builds them:

	  lune run tools/lune/export_blaster_energy.luau board     every level and STAR blaster in its own
	      cell -> build/preview/<NAME>.json + _shots.json (NAME=blaster_energy; SHAPE=Kenney: the old guns)
	  lune run tools/lune/export_blaster_energy.luau held      players holding them low at the hip
	      with both hands (MoveConfig.Moves.BlasterHold) -> blaster_energy_held.json + _shots.json
	  lune run tools/lune/export_blaster_energy.luau minigun   the video -> minigun_reel.json
	      node tools/preview/render_world_anim.mjs 1280 720 6000000 - minigun_reel minigun_blastery
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")

local root = process.cwd
Loader.init(root)

local CF = Loader.CFrame
local V3 = roblox.Vector3
local C3 = roblox.Color3
local Instance = roblox.Instance
local rgb = C3.fromRGB

local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local StarBlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.StarBlasterData")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")

local mode = process.args[1] or "board"
local T = tonumber(process.args[2]) or 0.6
-- SHAPE=Kenney: the guns before the minigun; NAME=<scene name>: the files and shot names follow it
if process.env.SHAPE then
	BlasterBuilder.Shape = process.env.SHAPE
end
local NAME = process.env.NAME or "blaster_energy"

local function presetsJson()
	local out = {}
	for name, preset in LightingConfig.Presets do
		local p = {}
		for group, values in preset do
			p[group] = {}
			for key, value in values do
				p[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
			end
		end
		out[name] = p
	end
	return out
end

-- world box of the visible parts under `model` (onlyBody: the gun's Body / Bevel parts)
local function bounds(model: any, onlyBody: boolean?): (any, any)
	local lo = V3.new(math.huge, math.huge, math.huge)
	local hi = V3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 and (not onlyBody or d.Name == "Body" or d.Name == "Bevel") then
			local r = d.CFrame
			local s = d.Size / 2
			local e = V3.new(
				math.abs(r.RightVector.X) * s.X + math.abs(r.UpVector.X) * s.Y + math.abs(r.LookVector.X) * s.Z,
				math.abs(r.RightVector.Y) * s.X + math.abs(r.UpVector.Y) * s.Y + math.abs(r.LookVector.Y) * s.Z,
				math.abs(r.RightVector.Z) * s.X + math.abs(r.UpVector.Z) * s.Y + math.abs(r.LookVector.Z) * s.Z
			)
			lo = lo:Min(r.Position - e)
			hi = hi:Max(r.Position + e)
		end
	end
	return lo, hi
end

local function move(model: any, cf: any)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
			d.Anchored = true
		end
	end
end

local function v3(p: any)
	return { p.X, p.Y, p.Z }
end

fs.writeDir(root .. "/build/preview")
local presets = presetsJson()

if mode == "board" then
	local shots = {}
	local game = Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local entries = {}
	for level = 1, 10 do
		table.insert(entries, { key = "lv" .. level, tool = BlasterBuilder.build(level, BlasterData.vaultOre(level)), star = false })
	end
	for _, star in StarBlasterData.List do
		table.insert(
			entries,
			{ key = "star_" .. star.Id, tool = BlasterBuilder.buildStar(star, 10, BlasterData.vaultOre(10)), star = true }
		)
	end
	local VFOV = 30
	local tanV = math.tan(math.rad(VFOV / 2))
	local ASPECT = 1.4
	for i, entry in entries do
		local cell = CF.new((i - 1) * 120, 200, 0)
		local stage = Instance.new("Model")
		stage.Name = entry.key
		stage.Parent = workspace
		local tool = entry.tool
		-- the gun: barrel to the right, turned a little to the camera, its body centred in the cell
		move(tool, CF.Angles(0, -math.pi / 2 + 0.35, 0) * CF.Angles(0.05, 0, 0))
		local blo, bhi = bounds(tool, true)
		move(tool, cell * CF.new(-(blo + bhi) / 2))
		tool.Parent = stage
		local lo, hi = bounds(tool)
		local size = hi - lo
		local target = (lo + hi) / 2
		local fit = math.max(size.Y * 1.12 / 2 / tanV, size.X * 1.1 / 2 / (tanV * ASPECT)) + size.Z / 2
		local camPos = target + V3.new(0, fit * 0.12, fit)
		local dist = (camPos - target).Magnitude
		local wallColor = if entry.star then rgb(20, 16, 40) else rgb(30, 32, 46)
		Geo.make(
			"Part",
			{ Name = "Wall", CFrame = cell * CF.new(0, 0, -6), Size = V3.new(110, 80, 0.5), Color = wallColor, Anchored = true },
			stage
		)
		if entry.star then
			math.randomseed(i * 77)
			for k = 1, 34 do
				local s = (0.02 + math.random() * 0.025) * dist * 0.25
				Geo.make("Part", {
					Name = "SkyStar" .. k,
					CFrame = cell
						* CF.new((math.random() * 2 - 1) * dist * 0.75, (math.random() * 2 - 1) * dist * 0.42, -5.6)
						* CF.Angles(0, 0, math.pi / 4),
					Size = V3.new(s, s, 0.05),
					Color = rgb(190, 186, 230),
					Anchored = true,
					CastShadow = false,
				}, stage)
			end
		end
		local lamp = Geo.make("Part", {
			Name = "Fill",
			CFrame = CF.new(target + V3.new(0, dist * 0.3, dist * 0.6)),
			Size = V3.new(0.1, 0.1, 0.1),
			Transparency = 1,
			Anchored = true,
		}, stage)
		local fill = Instance.new("PointLight")
		fill.Color = C3.new(1, 1, 1)
		fill.Range = dist * 1.4
		fill.Brightness = 1.1
		fill.Parent = lamp
		shots[NAME .. "_" .. entry.key] = {
			scene = NAME,
			position = v3(camPos),
			target = v3(target),
			fov = VFOV,
			preset = "Workbench",
			sunDir = { 0.25, 0.6, 0.8 },
			sunColor = { 1, 1, 1 },
			exposure = 1.1,
			shadowExtent = 20,
			maxLights = 6,
		}
	end
	local scene = Export.collect(workspace)
	scene.presets = presets
	fs.writeFile(root .. "/build/preview/" .. NAME .. ".json", serde.encode("json", scene))
	fs.writeFile(root .. "/build/preview/" .. NAME .. "_shots.json", serde.encode("json", shots))
	print(string.format(NAME .. ": %d parts, %d lights, %d emitters", #scene.parts, #scene.lights, #scene.emitters))
elseif mode == "held" then
	-- players holding LV 9, LV 10 and the Comet with the game's own pose (MoveConfig.Moves.BlasterHold)
	local R15 = require("./lib/dummy_r15")
	local MovePose = require("./lib/move_pose")
	local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
	local rad = math.rad
	local GRIP = CF.new(0, -0.15, 0) * CF.Angles(rad(-90), 0, 0)
	local game = Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local stage = Instance.new("Model")
	stage.Name = "HeldStage"
	stage.Parent = workspace
	Geo.make(
		"Part",
		{ Name = "Floor", CFrame = CF.new(0, -0.5, 0), Size = V3.new(120, 1, 50), Color = rgb(64, 66, 84), Anchored = true },
		stage
	)
	Geo.make(
		"Part",
		{ Name = "Wall", CFrame = CF.new(0, 12, -12), Size = V3.new(120, 26, 1), Color = rgb(30, 28, 50), Anchored = true },
		stage
	)
	local parts0, pose = MovePose.solve(Loader, MoveConfig.Moves[MoveConfig.Hold], 0.8, nil, function(joint)
		return if joint == "RightShoulder" then CF.Angles(rad(90), 0, 0) else CF.identity
	end)
	-- HELD=10,Supernova,Singularity: levels and STAR blaster ids (default LV 9, LV 10, the Comet)
	local picks = {}
	for key in string.gmatch(process.env.HELD or "9,10,Comet", "[^,]+") do
		local star = StarBlasterData.ById[key]
		local level = tonumber(key)
		table.insert(
			picks,
			if star then BlasterBuilder.buildStar(star, 10, "Heartstone") else BlasterBuilder.build(level, BlasterData.vaultOre(level))
		)
	end
	local aims = {}
	for i, tool in picks do
		local at = CF.new((i - (#picks + 1) / 2) * 9 - 2.5, 0, 0) * CF.Angles(0, -3 * math.pi / 4 + 0.3, 0)
		for partName, cf in parts0 do
			for _, piece in R15.pieces(partName) do
				local p = Instance.new("Part")
				p.Anchored = true
				p.Size = piece.Size
				p.CFrame = at * cf * piece.CFrame
				p.Color = piece.Color
				p.Material = roblox.Enum.Material[piece.Material]
				if piece.Shape == 1 then
					p.Shape = roblox.Enum.PartType.Ball
				elseif piece.Shape == 2 then
					p.Shape = roblox.Enum.PartType.Cylinder
				end
				p.Parent = stage
			end
		end
		move(tool, at * parts0.RightHand * GRIP * (pose.RightGrip or CF.identity))
		tool.Parent = stage
		local handle = tool:FindFirstChild("Handle")
		local muzzleAt = handle.CFrame * handle:FindFirstChild("Muzzle").Position
		local hand = handle.CFrame.Position
		local aim = (muzzleAt - hand) * V3.new(1, 0, 1)
		aims[i] = { Hand = hand, Ahead = aim.Unit }
	end
	for _, x in { -10, 0, 10 } do
		local lamp = Geo.make(
			"Part",
			{ Name = "Fill", CFrame = CF.new(x, 9, 10), Size = V3.new(0.1, 0.1, 0.1), Transparency = 1, Anchored = true },
			stage
		)
		local fill = Instance.new("PointLight")
		fill.Color = C3.new(1, 1, 1)
		fill.Range = 26
		fill.Brightness = 1.1
		fill.Parent = lamp
	end
	local held = Export.collect(workspace)
	held.presets = presets
	fs.writeFile(root .. "/build/preview/blaster_energy_held.json", serde.encode("json", held))
	local shots = {
		be_held = {
			scene = "blaster_energy_held",
			position = { 5, 6.2, 21 + math.max(0, #picks - 3) * 6 },
			target = { 1, 3.4, 0 },
			fov = if #picks > 3 then 38 else 50,
			preset = "Surface",
			sunDir = { 0.3, 0.8, 0.5 },
			exposure = 1.45,
			shadowExtent = 40,
			maxLights = 8,
		},
	}
	-- over each one's shoulder: what the player sees while playing (be_held_back_<n>)
	for i, aim in aims do
		local feet, facing = aim.Hand * V3.new(1, 0, 1), aim.Ahead
		shots["be_held_back_" .. i] = {
			scene = "blaster_energy_held",
			position = v3(feet - facing * 7 + V3.new(0, 10, 0) + facing:Cross(V3.yAxis) * 4),
			target = v3(feet + facing * 3 + V3.new(0, 2.2, 0)),
			fov = 50,
			preset = "Surface",
			sunDir = { 0.3, 0.8, 0.5 },
			exposure = 1.45,
			shadowExtent = 40,
			maxLights = 8,
		}
	end
	fs.writeFile(root .. "/build/preview/blaster_energy_held_shots.json", serde.encode("json", shots))
	print(string.format("blaster_energy_held: %d parts, %d lights", #held.parts, #held.lights))
elseif mode == "minigun" then
	-- the minigun video (owner 2026-10-31): the barrels spin up as it fires at a crystal rock, a
	-- player holding it low at the hip with both hands, then the new looks side by side
	local H = require("./lib/world_motion_preview").helpers
	local R15 = require("./lib/dummy_r15")
	local MovePose = require("./lib/move_pose")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
	local BarrelSpin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.BarrelSpin")
	local BlasterFeel = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterFeel")
	local rad = math.rad
	local fps = 60 -- (the shots are too quick for 30: they would seem to crawl backward)
	local game = Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local room = Instance.new("Model")
	room.Parent = workspace
	Geo.make(
		"Part",
		{ Name = "Floor", CFrame = CF.new(40, -0.5, -6), Size = V3.new(160, 1, 60), Color = rgb(40, 38, 54), Anchored = true },
		room
	)
	Geo.make(
		"Part",
		{ Name = "Wall", CFrame = CF.new(40, 15, -26), Size = V3.new(160, 32, 1), Color = rgb(24, 22, 38), Anchored = true },
		room
	)
	local ROCK_AT = V3.new(0, 0, -11)
	local rock = RockBuilder.build(4, "Crystal", { "Amethyst", "Sapphire" }, CF.new(ROCK_AT), 7)
	rock.Parent = room
	local HIT = ROCK_AT + V3.new(0, 1.6, 1.6)
	local roomParts = {}
	for _, d in H.visibleParts(room) do
		table.insert(roomParts, H.partEntry(d))
	end
	local lights = { { 6, 9, 4, "ffffff", 26, 2.2 }, { -6, 6, -2, "c8d2ff", 22, 1.2 }, { 70, 9, 4, "ffffff", 40, 2.6 } }
	local data = {
		fps = fps,
		scenes = { { id = "room", parts = roomParts, lights = lights, look = "mine" } },
		groups = {},
		frames = {},
		segments = {
			{
				title = "MINIGUN: STŘELY SE ZRYCHLUJÍ S KOTOUČEM",
				sub = "4 střely za sekundu na začátku, 24 při plných otáčkách, po puštění kotouč doběhne",
				cut = true,
			},
			{ title = "DRŽENÍ U PASU OBĚMA RUKAMA", sub = "pravá ruka na rukojeti, levá na horním držadle", cut = true },
			{ title = "NOVÉ VZHLEDY", sub = "kulaté miniguny, krystaly, duhové kroužky a blesky", cut = true },
		},
		sheetTitle = "minigun blastery v pohybu",
		picks = { 3.5, 10.2, 15.5 },
		caption = "náhled z herního kódu · Terra Forge",
		bloom = { 0.6, 0.45, 0.72 },
	}
	-- a gun as two groups: the body (handle frame) and the barrels (hub frame)
	local function gunGroups(tool: any): (number, number, any, any)
		local handle = tool:FindFirstChild("Handle")
		local hub = tool:FindFirstChild(BlasterBuilder.SpinHub)
		local body, spin = {}, {}
		for _, d in H.visibleParts(tool) do
			local weld = d:FindFirstChildOfClass("WeldConstraint")
			if hub and weld and weld.Part0 == hub then
				table.insert(spin, H.partEntry(d, hub.CFrame:Inverse() * d.CFrame))
			else
				table.insert(body, H.partEntry(d, handle.CFrame:Inverse() * d.CFrame))
			end
		end
		table.insert(data.groups, { parts = body })
		local bi = #data.groups - 1
		table.insert(data.groups, { parts = spin })
		local muzzle = handle:FindFirstChild("Muzzle")
		return bi, #data.groups - 1, if hub then hub.CFrame else CF.new(), muzzle.Position
	end
	local function cf(gi: number, at: any)
		return { gi, table.unpack(H.cfList(at)) }
	end
	local glowColor = BlasterBuilder.look(10, BlasterData.vaultOre(10)).Glow
	local scratch = Instance.new("Part")
	scratch.Anchored = true
	scratch.Material = roblox.Enum.Material.Neon
	local function addPart(list, shape: any, at: any, size: any, color: any, transparency: number)
		scratch.Shape = shape
		scratch.Size = size
		scratch.CFrame = at
		scratch.Color = color
		scratch.Transparency = transparency
		table.insert(list, H.partEntry(scratch))
	end
	local function lookAt(from: any, to: any): any
		local look = (to - from).Unit
		local hint = if math.abs(look.Y) > 0.98 then V3.new(1, 0, 0) else V3.new(0, 1, 0)
		local right = look:Cross(hint).Unit
		return CF.fromMatrix((from + to) / 2, right, right:Cross(look))
	end
	-- the shots (a stand-in for Effects/BlasterShots: the game's fire rate, a head, a fading trail) with
	-- their small impacts, for a run firing from t0 to t1
	local Shots = BlasterFeel.Shots
	local function shotTimes(t0: number, t1: number): { number }
		local times, spin, due, at = {}, 0, 1, t0
		while at < t1 do
			local count
			spin, due, count = BlasterFeel.shotStep(spin, due, 1 / 120, true)
			for _ = 1, count do
				table.insert(times, at)
			end
			at += 1 / 120
		end
		return times
	end
	local function shots(list, times: { number }, from: any, to: any, t: number)
		local hot = glowColor:Lerp(rgb(255, 255, 255), 0.35)
		local line = to - from
		local dir, length = line.Unit, line.Magnitude
		for k, at in times do
			local age = t - at
			if age >= 0 then
				local travelled = age * Shots.Speed
				if travelled < length then
					local head = from + dir * travelled
					addPart(list, roblox.Enum.PartType.Ball, CF.new(head), V3.new(0.42, 0.42, 0.42), hot, 0)
					for i = 1, 4 do
						local a = head - dir * math.min(travelled, Shots.Trail * (i - 1) / 4)
						local b = head - dir * math.min(travelled, Shots.Trail * i / 4)
						if (a - b).Magnitude > 0.01 then
							local width = 0.5 * (1 - 0.2 * (i - 1))
							local along = lookAt(a, b) * CF.Angles(0, math.pi / 2, 0) -- (a cylinder runs along X)
							addPart(
								list,
								roblox.Enum.PartType.Cylinder,
								along,
								V3.new((a - b).Magnitude, width, width),
								glowColor:Lerp(hot, 1 - i / 4),
								0.15 + 0.2 * i
							)
						end
					end
				else
					local since = age - length / Shots.Speed
					if since < 0.14 then
						local f = 1 - since / 0.14
						addPart(list, roblox.Enum.PartType.Ball, CF.new(to), V3.new(1, 1, 1) * (0.2 + 0.7 * f), hot, 1 - f * 0.75)
					end
					if since < 0.4 then
						-- a spark
						local h = math.sin(k * 12.9898) * 43758.5453
						local a = (h - math.floor(h)) * math.pi * 2
						local p = to
							+ V3.new(math.cos(a) * 4, 3, math.sin(a) * 4) * since
							+ V3.new(0, -9, 0) * (0.5 * since * since)
							- dir * since * 4
						addPart(list, roblox.Enum.PartType.Ball, CF.new(p), V3.new(0.12, 0.12, 0.12), hot, since / 0.45)
					end
				end
			end
		end
	end
	local function spinState(state, firing: boolean, dt: number)
		state.speed = BarrelSpin.speed(state.speed, firing, dt, BarrelSpin.Full)
		state.angle = (state.angle + state.speed * dt) % (math.pi * 2)
	end
	local dt = 1 / fps

	-- 1. the gun alone, firing at the rock (LV 10)
	do
		local tool = BlasterBuilder.build(10, BlasterData.vaultOre(10))
		local bodyG, spinG, axis, muzzle = gunGroups(tool)
		local state = { speed = 0, angle = 0 }
		local DUR = 6.4
		local times = shotTimes(0.9, 4.9)
		for f = 0, math.floor(DUR * fps) - 1 do
			local t = f / fps
			local firing = t >= 0.9 and t < 4.9
			spinState(state, firing, dt)
			local yaw = 0.18 * math.sin(t * 0.7)
			local gunCF = CF.lookAt(V3.new(0.6, 3.6, 0), HIT) * CF.Angles(0, yaw * 0.2, 0)
			local frame = { s = 0, seg = 0, cam = { 9.5, 5.6, 2.6, -0.4, 3.0, -4.6, 42 }, g = {}, p = {}, o = {} }
			table.insert(frame.g, cf(bodyG, gunCF))
			table.insert(frame.g, cf(spinG, gunCF * axis * CF.Angles(0, 0, state.angle)))
			shots(frame.p, times, gunCF * muzzle, HIT, t)
			table.insert(data.frames, frame)
		end
	end

	-- 2. a player holding LV 9 at the hip with both hands (the game's BlasterHold), firing
	do
		local move = MoveConfig.Moves[MoveConfig.Hold]
		local GRIP = CF.new(0, -0.15, 0) * CF.Angles(rad(-90), 0, 0)
		local partGroups = {}
		for _, partName in R15.Order do
			local list = {}
			for _, piece in R15.pieces(partName) do
				scratch.Shape = if piece.Shape == 1
					then roblox.Enum.PartType.Ball
					elseif piece.Shape == 2 then roblox.Enum.PartType.Cylinder
					else roblox.Enum.PartType.Block
				scratch.Size = piece.Size
				scratch.CFrame = piece.CFrame
				scratch.Color = piece.Color
				scratch.Material = roblox.Enum.Material[piece.Material]
				scratch.Transparency = 0
				table.insert(list, H.partEntry(scratch))
			end
			scratch.Material = roblox.Enum.Material.Neon
			if #list > 0 then
				table.insert(data.groups, { parts = list })
				partGroups[partName] = #data.groups - 1
			end
		end
		local tool = BlasterBuilder.build(9, BlasterData.vaultOre(9))
		local bodyG, spinG, axis, muzzle = gunGroups(tool)
		local state = { speed = 0, angle = 0 }
		local start = #data.frames
		local DUR = 6.6
		local times = shotTimes(1.1, 5.4)
		-- the character stands 7 studs from the rock, facing it, turned so the hip gun points at it
		local stand = CF.lookAt(V3.new(1.4, 0, -2.6), V3.new(ROCK_AT.X + 1.4, 0, ROCK_AT.Z)) * CF.Angles(0, rad(-8), 0)
		for f = 0, math.floor(DUR * fps) - 1 do
			local t = f / fps
			local firing = t >= 1.1 and t < 5.4
			spinState(state, firing, dt)
			local parts, pose = MovePose.solve(Loader, move, 0.2 + t, nil, function(joint)
				return if joint == "RightShoulder" then CF.Angles(rad(90), 0, 0) else CF.identity
			end)
			local frame = { s = 0, seg = 1, cam = { 11, 5.2, -2.6, 0.6, 2.8, -6.6, 48 }, g = {}, p = {}, o = {} }
			for partName, gi in partGroups do
				if parts[partName] then
					table.insert(frame.g, cf(gi, stand * parts[partName]))
				end
			end
			local handleCF = stand * parts.RightHand * GRIP * (pose.RightGrip or CF.identity)
			table.insert(frame.g, cf(bodyG, handleCF))
			table.insert(frame.g, cf(spinG, handleCF * axis * CF.Angles(0, 0, state.angle)))
			shots(frame.p, times, handleCF * muzzle, HIT, t)
			table.insert(data.frames, frame)
		end
		local _ = start
	end

	-- 3. the new looks side by side, the barrels turning slowly, the camera gliding along
	do
		local picks = { 1, 3, 5, 7, 9, 10 }
		local guns = {}
		for i, level in picks do
			local tool = BlasterBuilder.build(level, BlasterData.vaultOre(level))
			local bodyG, spinG, axis = gunGroups(tool)
			table.insert(
				guns,
				{ body = bodyG, spin = spinG, axis = axis, at = CF.new(52 + (i - 1) * 7.5, 3.6, -8) * CF.Angles(0, rad(-90), 0) }
			)
		end
		local star = BlasterBuilder.buildStar(StarBlasterData.ById.Comet, 10, "Heartstone")
		local bodyG, spinG, axis = gunGroups(star)
		table.insert(guns, { body = bodyG, spin = spinG, axis = axis, at = CF.new(52 + #picks * 7.5, 3.6, -8) * CF.Angles(0, rad(-90), 0) })
		local DUR = 6.4
		for f = 0, math.floor(DUR * fps) - 1 do
			local t = f / fps
			local x = 50 + t / DUR * (#guns - 1) * 7.5
			local frame = { s = 0, seg = 2, cam = { x + 3.2, 5.2, 0.4, x + 3.6, 3.6, -8, 44 }, g = {}, p = {}, o = {} }
			for i, gun in guns do
				local turn = gun.at * CF.Angles(0, 0.35 * math.sin(t * 0.9 + i), 0)
				table.insert(frame.g, cf(gun.body, turn))
				table.insert(frame.g, cf(gun.spin, turn * gun.axis * CF.Angles(0, 0, t * 4 + i)))
			end
			table.insert(data.frames, frame)
		end
	end

	data.duration = #data.frames / fps
	fs.writeFile(root .. "/build/preview/minigun_reel.json", serde.encode("json", data))
	print(string.format("minigun_reel: %d frames (%.1f s), %d groups", #data.frames, data.duration, #data.groups))
end
