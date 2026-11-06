--[[
	Video frames of the mining reel (owner 2026-10-27, "How do games make MINING
	feel satisfying?"; Config/JuiceConfig.Mining) in our game, posed with the
	game's own code: a player holding the minigun at the hip (MoveConfig's
	BlasterHold) fires at a rock on mine floor 1; the barrels spin up and the
	separate energy shots get faster with them (BlasterFeel.shotStep), each with
	its trail, muzzle flash and small impact; every hit (a Health drop, about 3 a
	second) grows the crack (Effects/CrackLogic laid out like
	RockCracks) and its gold glints flare, chips fly (RockFxLogic.chipPlan), the
	rock trembles (RockFxLogic.shakeOffset); at each crack stage the server's
	cracks open (RockBuilder.applyStage), a chunk breaks off, RockFx pops and an
	ore drops; the last hit shatters it (RockFx: RockFxLogic.shatterPlan, dust,
	the ground ring; no comic word: the owner turned it down); the dirty ores
	are picked up: each 3D chunk lifts off as big as it lies there and tumbles
	into the backpack button (UI/BagFly's viewports, drawn live by ui.js; the
	HUD since feat/backpack) with its bump and +N. A caption
	line at the top (preview only) names the reel's steps and the sounds.

	  lune run tools/lune/export_mine_juice.luau [fps=20]
	-> build/preview/minejuice_base.json (the floor, the miner: once)
	   build/preview/minejuice/fx_NNNN.json + ui_NNNN.json per frame
	   build/preview/minejuice_shots.json, build/preview/minejuice_board.json
	then: node tools/preview/render_reel.mjs minejuice
	(three.js approximation of Roblox: no physics, the chunks fly on simple arcs,
	no camera shake, sounds are named in the caption. The camera starts behind the
	player like in the game, then swings to the side.)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local UiExport = require("./lib/uiexport")
local Juice = require("./lib/mine_juice_preview")
local Gallery = require("./lib/blaster_gallery")
local R15 = require("./lib/dummy_r15")
local MovePose = require("./lib/move_pose")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true

local fps = tonumber(process.args[1]) or 60
local CF = Loader.CFrame
local V3 = roblox.Vector3
local V2 = roblox.Vector2
local C3 = roblox.Color3
local Instance = roblox.Instance
local WHITE = C3.new(1, 1, 1)
local GRAVITY = 196.2

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local JuiceConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.JuiceConfig")
local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local BlasterFeel = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterFeel")
local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
local BarrelSpin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.BarrelSpin")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local CrackLogic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.CrackLogic")
local Rules = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.MineJuiceRules")
local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RockFxLogic")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local BagFly = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BagFly")
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

local W, H, INSET, SCALE, FOV = 1600, 900, 36, 1.25, 62
local tag = "minejuice"
local FLOOR = 1
local floor = MineFloors.get(FLOOR)
local pal = floor.Palette

---------------------------------------------------------------- the scene

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
-- a corner of the quarry (floor 1's palette): the ground, a back wall, two more rocks, lamps
local area = Instance.new("Model")
area.Name = "Quarry"
area.Parent = workspace
Geo.block(area, CF.new(0, -0.5, 0), V3.new(90, 1, 80), pal.Ground)
Geo.block(area, CF.new(0, 9, -17), V3.new(90, 20, 3), pal.Dark)
Geo.block(area, CF.new(-26, 6, -4), V3.new(3, 14, 30), pal.Mid)
for k, spot in { V3.new(-11, 0, -9), V3.new(10, 0, -10), V3.new(17, 0, 2) } do
	local kind = if k == 2 then "Crystal" else "Small"
	RockBuilder.build(FLOOR, kind, { "Coal", "Tin", "Quartz" }, CF.new(spot), 300 + k).Parent = area
end
for _, at in { V3.new(-10, 12, 8), V3.new(12, 12, 9), V3.new(0, 10, -12) } do
	local holder = Geo.block(area, CF.new(at), V3.new(0.2, 0.2, 0.2), WHITE, nil, { Transparency = 1, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = C3.fromRGB(255, 236, 214)
	light.Range = 36
	light.Brightness = 0.7
	light.Parent = holder
end

-- the blasted rock: a Big one (4 ores: 3 crack stages, then the break)
local ORES = { "Coal", "Copper", "Tin", "Iron" }
local pristine = RockBuilder.build(FLOOR, "Big", ORES, CF.new(0, 0, 0), 4242)
pristine:SetAttribute("Kind", "Big")
local stages = MineFloors.OreCount.Big
local center, size = Juice.bounds(pristine)
local radius = math.max(size.X, size.Z) / 2 * 0.8
local ground = 0
print(`rock Big at {center}, size {size}, {stages} stages`)

-- the player 16 studs off, firing at it (the shots need room to be seen)
local LEVEL = 10
local away = V3.new(-6.5, 0, 5).Unit
local feet = V3.new(center.X, ground, center.Z) + away * 16
local aimPoint = Gallery.surface(pristine, feet, 0.6)
local shotGlow = BlasterBuilder.look(LEVEL, BlasterData.vaultOre(LEVEL)).Glow
local tier = BlasterFeel.tier(LEVEL)

-- the game's camera behind the player, then swinging to the side: the player left, the rock big on the right
local facing = -away
local right = V3.new(-facing.Z, 0, facing.X)
local middle = (feet + V3.new(center.X, ground, center.Z)) / 2
local sidePos = middle + right * 16 + facing * 1.5 + V3.new(0, 5.6, 0)
local sideTarget = middle + facing * 1 + V3.new(0, 2.6, 0)
local behindPos = feet - facing * 6.5 + right * 8.5 + V3.new(0, 4.4, 0)
local behindTarget = feet + facing * 7.5 + V3.new(0, 3, 0)
local SWING_FROM, SWING_TO = 2.6, 4.2
local function cameraAt(t: number): (any, any)
	local u = math.clamp((t - SWING_FROM) / (SWING_TO - SWING_FROM), 0, 1)
	u = u * u * (3 - 2 * u)
	local mid = (behindTarget + sideTarget) / 2
	local from, to = behindPos - mid, sidePos - mid
	-- round the rock's side, not through the player: an arc about the middle
	local flat = from * V3.new(1, 0, 1)
	local goal = to * V3.new(1, 0, 1)
	local angle = math.atan2(flat:Cross(goal).Y, flat:Dot(goal)) * u
	local radius_ = flat.Magnitude + (goal.Magnitude - flat.Magnitude) * u
	local dir = CF.Angles(0, angle, 0):VectorToWorldSpace(flat.Unit)
	local pos = mid + dir * radius_ + V3.new(0, from.Y + (to.Y - from.Y) * u, 0)
	return pos, behindTarget + (sideTarget - behindTarget) * u
end
local camPos, camTarget = sidePos, sideTarget

local function presetToJson(preset)
	local o = {}
	for group, values in preset do
		o[group] = {}
		for key, value in values do
			o[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
		end
	end
	return o
end

fs.writeDir(root .. "/build/preview/" .. tag)
local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end
scene.presets = presets
fs.writeFile(root .. "/build/preview/" .. tag .. "_base.json", serde.encode("json", scene))
print(`base scene: {#scene.parts} parts`)

-- the screen point (overlay pixels, under the top inset) of a world point
local look = CF.lookAt(camPos, camTarget) -- (the side view: the ores fly into the bag after the swing)
local function screen(p): any
	local rel = look:PointToObjectSpace(p)
	local f = 1 / math.tan(math.rad(FOV) / 2)
	local x = (rel.X / -rel.Z) * f * (H / W)
	local y = (rel.Y / -rel.Z) * f
	return V2.new((x + 1) / 2 * W, (1 - y) / 2 * H - INSET)
end

---------------------------------------------------------------- the timeline (seconds)

local FIRE = 0.9
local HITS = 16
local HIT_GAP = 0.34
local hitTimes = {}
for k = 1, HITS do
	hitTimes[k] = FIRE + 0.1 + (k - 1) * HIT_GAP
end
local SHATTER = hitTimes[HITS]
local maxHealth = 100
-- the crack stage a hit reaches (MiningService.stageAt)
local function stageOf(k: number): number
	return math.clamp(math.floor(k / HITS * stages + 1e-6), 0, stages)
end
local stageTimes = {}
for k = 1, HITS do
	local s = stageOf(k)
	if s > stageOf(k - 1) then
		stageTimes[s] = hitTimes[k]
	end
end
-- the ores: one per stage (floor rocks: every stage drops one, the last at the break)
local drops = {}
for s = 1, stages do
	local turn = ({ -0.55, 0.5, 0.05, -0.2 })[s] or 0
	local out = CF.Angles(0, turn, 0):VectorToWorldSpace(away)
	drops[s] = {
		At = stageTimes[s],
		Ore = ORES[s],
		Origin = center + V3.new(0, radius * 0.5 + 1.5, 0) + out * 0.8,
		-- (the server throws it out at 7..11 studs/s and it rolls off the rock; here it simply lands clear of it)
		Velocity = out * (12 + 1.5 * s) + V3.new(0, 16, 0),
		Pick = SHATTER + 1.05 + (s - 1) * 0.36,
	}
end
local FLIGHT = BagFly.Rise + BagFly.Fly
local total = drops[stages].Pick + FLIGHT + BagFly.BumpSeconds + 0.3

-- a chunk's spot at time t (an arc, then it lies on the ground)
local function chunkAt(d, t: number): any
	local dt = t - d.At
	local o, v = d.Origin, d.Velocity
	local rest = ground + 0.5
	local land = (v.Y + math.sqrt(v.Y * v.Y + 2 * GRAVITY * math.max(0, o.Y - rest))) / GRAVITY
	local tl = math.min(dt, land)
	local p = o + v * tl - V3.new(0, 0.5 * GRAVITY * tl * tl, 0)
	if dt > land then
		p += V3.new(v.X, 0, v.Z) * math.min(dt - land, 0.12) * 0.3 -- a short slide
	end
	return p
end

---------------------------------------------------------------- the UI (built once, posed per frame)

local hud = HudView.build()
hud.Gui.Scale.Scale = SCALE
hud.Coins.Text = "$3.4K"
hud.Zone.Text = ""
hud.Toasts:ClearAllChildren()
local CAPACITY = 24
-- the backpack button (feat/backpack): "n / 24", right of the blaster's hotbar slot, as HudController places it
HudView.placeBackpack(hud, SCALE)
local function setCarry(count: number)
	HudView.setBackpack(hud, count, CAPACITY)
end
setCarry(0)
-- the button's middle and size (overlay pixels): its holder hangs from the bottom centre, the
-- "Backpack" button sits in it (MineJuiceController.hudTarget flies there; else the whole holder)
local holder = hud.CarryPanel
local holderSize = V2.new(holder.Size.X.Offset, holder.Size.Y.Offset) * SCALE
local holderCorner = V2.new(W / 2 + holder.Position.X.Offset * SCALE, (H - INSET) + holder.Position.Y.Offset * SCALE)
	- V2.new(holder.AnchorPoint.X, holder.AnchorPoint.Y) * holderSize
local button = holder:FindFirstChild("Backpack")
local packSize, packAt = holderSize, holderCorner + holderSize / 2
if button then
	packSize = V2.new(button.Size.X.Offset, button.Size.Y.Offset) * SCALE
	local at = V2.new(
		button.Position.X.Scale * holderSize.X + button.Position.X.Offset * SCALE,
		button.Position.Y.Scale * holderSize.Y + button.Position.Y.Offset * SCALE
	)
	packAt = holderCorner + at - V2.new(button.AnchorPoint.X, button.AnchorPoint.Y) * packSize + packSize / 2
end

local juice = BagFly.build()
for _, flyer in juice.Flyers do
	flyer.View:SetAttribute("PreviewLive", true) -- ui.js draws the viewport's 3D chunk (uiexport)
end

-- the caption line (preview only: what the reel's step is, which sound plays)
local caption = Instance.new("ScreenGui")
caption.Name = "Caption"
caption.IgnoreGuiInset = false
local box = UIKit.new("Frame", {
	Name = "Box",
	AnchorPoint = V2.new(0.5, 0),
	Position = roblox.UDim2.new(0.5, 0, 0, 60),
	Size = roblox.UDim2.fromOffset(980, 50),
	BackgroundColor3 = C3.fromRGB(20, 22, 30),
	BackgroundTransparency = 0.25,
}, caption)
UIKit.corner(box, 14)
local captionText = UIKit.new("TextLabel", {
	Name = "Text",
	BackgroundTransparency = 1,
	Size = roblox.UDim2.fromScale(1, 1),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 28,
	TextColor3 = WHITE,
	Text = "",
}, box)
local soundTag = UIKit.new("TextLabel", {
	Name = "Sound",
	AnchorPoint = V2.new(0.5, 0),
	BackgroundTransparency = 1,
	Position = roblox.UDim2.new(0.5, 0, 0, 114),
	Size = roblox.UDim2.fromOffset(600, 30),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 24,
	TextColor3 = C3.fromRGB(255, 226, 150),
	Text = "",
}, caption)

local function captionFor(t: number): string
	if t < FIRE then
		return "Hráč míří s minigunem u pasu"
	elseif t < SHATTER - 0.02 then
		local spin = math.clamp((t - FIRE) / BlasterFeel.Shots.SpinUp, 0, 1)
		local rate = math.floor(BlasterFeel.shotRate(spin) + 0.5)
		if spin >= 1 then
			return `Plné otáčky · {rate} střel za sekundu`
		end
		return `Kotouč se roztáčí · {rate} střel za sekundu`
	elseif t < drops[1].Pick then
		return "Poslední zásah: kámen se rozletí na kusy"
	end
	return "Ruda se zvedne ze země a letí do batohu: +1"
end

-- the sound playing now (named, the video has none)
local function soundFor(t: number): string
	if t >= SHATTER and t < SHATTER + 0.45 then
		return "zvuk: rozbití kamene"
	end
	for s = 1, stages - 1 do
		local at = stageTimes[s]
		if at and t >= at and t < at + 0.3 then
			return "zvuk: KŘUP! (prasknutí)"
		end
	end
	for _, d in drops do
		if t >= d.Pick + FLIGHT and t < d.Pick + FLIGHT + 0.25 then
			return "zvuk: pop (do batohu)"
		end
	end
	if t >= FIRE and t < SHATTER then
		return "zvuk: střely, hučení roste s kotoučem"
	end
	return ""
end

---------------------------------------------------------------- frames

local plan = CrackLogic.plan(
	string.format("%d,%d,%d", math.floor(center.X), math.floor(center.Y), math.floor(center.Z)),
	CrackLogic.sizeFor(size),
	CrackLogic.Detail
)
-- the crack's face: the first hit's ray from the camera at the rock (RockCracks.make)
local origin, normal = Juice.cast(pristine, camPos, center - camPos, (center - camPos).Magnitude + size.Magnitude)
assert(origin and normal, "the camera ray misses the rock")
local cRight, cUp = CrackLogic.basis(normal)
local frameInfo = { Origin = origin, Normal = normal, Right = cRight, Up = cUp }

local crust = pristine.PrimaryPart.Color
local frames = math.floor(total * fps)

---------------------------------------------------------------- the player and the gun

local NEON = roblox.Enum.Material.Neon
local FX = { CanCollide = false, CastShadow = false }
local function fxProps(transparency: number)
	return { CanCollide = false, CastShadow = false, Transparency = transparency }
end
local hold = MoveConfig.Moves[MoveConfig.Hold]
local GRIP = CF.new(0, -0.15, 0) * CF.Angles(math.rad(-90), 0, 0)
-- turned a little so the gun at the hip points at the rock
local stand = CF.lookAt(feet, V3.new(center.X, ground, center.Z)) * CF.Angles(0, math.rad(-8), 0)
local holdBase = function(joint: string)
	return if joint == "RightShoulder" then CF.Angles(math.rad(90), 0, 0) else CF.identity
end
local function posed(t: number): any
	local parts, pose = MovePose.solve(Loader, hold, 0.4 + t, nil, holdBase)
	return parts, parts.RightHand * GRIP * (pose.RightGrip or CF.identity)
end
local body = Instance.new("Model")
local bodyPieces = {}
for _, partName in R15.Order do
	for _, piece in R15.pieces(partName) do
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = piece.Size
		p.Color = piece.Color
		p.Material = roblox.Enum.Material[piece.Material]
		if piece.Shape == 1 then
			p.Shape = roblox.Enum.PartType.Ball
		elseif piece.Shape == 2 then
			p.Shape = roblox.Enum.PartType.Cylinder
		end
		p.Parent = body
		table.insert(bodyPieces, { Part = p, Name = partName, At = piece.CFrame })
	end
end
local gun = BlasterBuilder.build(LEVEL, BlasterData.vaultOre(LEVEL))
local handle = gun:FindFirstChild("Handle")
local hub = gun:FindFirstChild(BlasterBuilder.SpinHub)
local muzzleAt = handle:FindFirstChild("Muzzle").Position
local axis = handle.CFrame:Inverse() * hub.CFrame
local gunPieces = {}
for _, d in gun:GetDescendants() do
	if d:IsA("BasePart") then
		local weld = d:FindFirstChildOfClass("WeldConstraint")
		local spins = weld ~= nil and weld.Part0 == hub
		local from = if spins then hub.CFrame else handle.CFrame
		table.insert(gunPieces, { Part = d, Spins = spins, At = from:Inverse() * d.CFrame })
	end
end
-- the barrels' angle per frame and the recoil's kicks (BarrelSpin.speed, BlasterFx.fired)
local angles = {}
do
	local speed, angle = 0, 0
	for i = 0, frames - 1 do
		local firing = i / fps >= FIRE and i / fps < SHATTER
		speed = BarrelSpin.speed(speed, firing, 1 / fps, BarrelSpin.Full)
		angle = (angle + speed / fps) % (math.pi * 2)
		angles[i] = angle
	end
end

---------------------------------------------------------------- the shots (Effects/BlasterShots)

local Shots = BlasterFeel.Shots
local shotList = {}
do
	local spin, due, step = 0, 1, 1 / 120
	local at = FIRE
	while at < SHATTER do
		local count
		spin, due, count = BlasterFeel.shotStep(spin, due, step, true)
		for _ = 1, count do
			table.insert(shotList, { At = at, Barrel = #shotList % Shots.Barrels + 1, Spin = spin })
		end
		at += step
	end
end
print(`{#shotList} shots`)
-- the kick left at t (at most one kick every BlasterFeel.Pulse)
local kicks = {}
do
	local last = -math.huge
	for _, shot in shotList do
		if shot.At - last >= BlasterFeel.Pulse then
			last = shot.At
			table.insert(kicks, last)
		end
	end
end
local function kickAt(t: number): number
	local amount = 0
	for _, at in kicks do
		if at <= t then
			amount = BlasterFeel.settle(t - at)
		end
	end
	return amount
end
local function handleAt(t: number): any
	local _, grip = posed(t)
	local recoil = BlasterFeel.Recoil
	local amount = kickAt(t)
	return stand * grip * CF.new(0, 0, recoil.GunBack * amount) * CF.Angles(recoil.GunLift * amount, 0, 0)
end
-- where a shot starts: the muzzle at that moment, a little off the axis (the next barrel)
for _, shot in shotList do
	local origin = handleAt(shot.At) * muzzleAt
	local line = CF.lookAt(origin, aimPoint)
	local a = shot.Barrel / Shots.Barrels * math.pi * 2
	local start = origin + line.RightVector * (math.cos(a) * Shots.Spiral) + line.UpVector * (math.sin(a) * Shots.Spiral)
	shot.Start = start
	shot.Dir = (aimPoint - start).Unit
	shot.Length = (aimPoint - start).Magnitude
end

local function round(parent, a: any, b: any, width: number, color: any, transparency: number)
	-- a cylinder from a to b (it runs along its X)
	local cf = CF.lookAt((a + b) / 2, b) * CF.Angles(0, math.pi / 2, 0)
	local p = Geo.block(parent, cf, V3.new((b - a).Magnitude, width, width), color, NEON, fxProps(transparency))
	p.Shape = roblox.Enum.PartType.Cylinder
	return p
end

local TRAIL_STEPS = 5
local function drawShots(parent, t: number)
	local width = tier.ShotWidth
	local hot = shotGlow:Lerp(WHITE, 0.35)
	local glare = 0
	for k, shot in shotList do
		local age = t - shot.At
		if age >= 0 then
			local travelled = age * Shots.Speed
			if travelled < shot.Length then
				-- the head and the fading trail, the white core in it (BlasterShots: a ball and two Beams)
				local head = shot.Start + shot.Dir * travelled
				Geo.ball(parent, head, width * 0.85, hot, NEON, FX)
				for i = 1, TRAIL_STEPS do
					local u0, u1 = (i - 1) / TRAIL_STEPS, i / TRAIL_STEPS
					local a = head - shot.Dir * math.min(travelled, Shots.Trail * u0)
					local b = head - shot.Dir * math.min(travelled, Shots.Trail * u1)
					if (b - a).Magnitude > 0.01 then
						round(parent, a, b, width * (1 - 0.85 * u0), shotGlow:Lerp(hot, 1 - u0), 0.15 + 0.8 * u0)
						if u1 <= 0.6 then
							round(parent, a, b, tier.ShotCore * (1 - 0.8 * u0 / 0.6), WHITE, 0.05)
						end
					end
				end
			else
				local since = age - shot.Length / Shots.Speed
				if since < 0.5 then
					-- the small impact: the hot flash and a spark or two back at the shooter
					glare = math.max(glare, 1 - since * Shots.LightFade)
					if since < 0.14 then
						local f = 1 - since / 0.14
						Geo.ball(parent, aimPoint, 0.2 + 0.7 * f, shotGlow:Lerp(WHITE, 0.35), NEON, fxProps(1 - f * 0.75))
					end
					local rng = Rng.new("spark" .. k)
					local sparks = BlasterFeel.resolve(LEVEL, false).Sparks
					for _ = 1, sparks do
						local life = rng:range(0.25, 0.5)
						local out = (-shot.Dir + V3.new(rng:range(-0.9, 0.9), rng:range(-0.5, 0.9), rng:range(-0.9, 0.9))).Unit
						local speed = rng:range(16, 30)
						if since < life then
							-- (Drag 3, Acceleration -60: Vfx's Sparks)
							local p = aimPoint + out * (speed / 3 * (1 - math.exp(-3 * since))) - V3.new(0, 30 * since * since, 0)
							local size = 0.3 * (1 - since / life)
							Geo.ball(parent, p, math.max(size, 0.03), shotGlow:Lerp(WHITE, 0.5), NEON, FX)
						end
					end
				end
			end
			-- the muzzle flash on the gun, a moment per shot
			if age < 0.06 then
				local f = 1 - age / 0.06
				local origin = handleAt(t) * muzzleAt
				Geo.ball(parent, origin, tier.Flash * (0.2 + 0.35 * f), shotGlow:Lerp(WHITE, 0.45), NEON, fxProps(1 - f * 0.7))
			end
		end
	end
	if glare > 0 then
		local holder = Geo.block(
			parent,
			CF.new(aimPoint - (shotList[1].Dir * 0.8)),
			V3.new(0.1, 0.1, 0.1),
			WHITE,
			nil,
			{ Transparency = 1, CanCollide = false }
		)
		local light = Instance.new("PointLight")
		light.Color = shotGlow
		light.Range = 14
		light.Brightness = tier.Light * glare
		light.Parent = holder
	end
end
local shots = {}
for i = 0, frames - 1 do
	local t = i / fps
	local extra = Instance.new("Model")
	local rng = Rng.new("frame" .. i)
	-- hits so far
	local hits, lastHit = 0, -math.huge
	local lastFlare: number? = nil -- the glints flare at most GlintFlaresPerSecond (MineJuiceRules.flare)
	for k, at in hitTimes do
		if t >= at then
			hits, lastHit = k, at
			if Rules.flare(at, lastFlare, false) then
				lastFlare = at
			end
		end
	end
	local stage = stageOf(hits)
	local health = maxHealth * (1 - hits / HITS)

	if t < SHATTER then
		-- the rock: the server's crack stages so far, its broken-off chunks tumbling away
		local rock = pristine:Clone()
		rock.Parent = extra
		for s = 1, math.min(stage, stages - 1) do
			local broken = RockBuilder.applyStage(rock, s, 9)
			local dt = t - stageTimes[s]
			for _, piece in broken do
				if dt > 1.4 then
					piece:Destroy()
				else
					local out = (piece.CFrame.Position - center) * V3.new(1, 0, 1)
					local dir = if out.Magnitude > 0.1 then out.Unit else away
					local v = dir * 10 + V3.new(0, 14, 0)
					-- (unanchored with CanCollide off by the server: it falls through the floor)
					local p = piece.CFrame.Position + v * dt - V3.new(0, 0.5 * GRAVITY * dt * dt, 0)
					piece.CFrame = CF.new(p) * (piece.CFrame - piece.CFrame.Position) * CF.Angles(dt * 6, dt * 4, dt * 5)
				end
			end
		end
		-- the crack on the rock as it is now (projected before the tremble, like the game)
		if hits > 0 then
			Juice.crack(
				Loader,
				extra,
				rock,
				plan,
				frameInfo,
				CrackLogic.growth(health, maxHealth),
				t - (lastFlare or -math.huge),
				JuiceConfig.Mining.Glints
			)
		end
		-- the tremble of the last hit (RockFx.shake; a crack stage kicks harder)
		if hits > 0 then
			local isStage = stageOf(hits) > stageOf(hits - 1)
			local offset = Logic.shakeOffset(t - lastHit, if isStage then 0.28 else 0.22, if isStage then 0.15 else 0.07, hits * 1.7)
			local pivot = CF.new(center)
			local m = pivot * offset * pivot:Inverse()
			for _, d in rock:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = m * d.CFrame
				end
			end
		end
	end

	-- the player at the hip with both hands (the game's BlasterHold), the barrels turning
	do
		local parts = posed(t)
		for _, piece in bodyPieces do
			piece.Part.CFrame = stand * parts[piece.Name] * piece.At
		end
		body.Parent = extra
		local handleCF = handleAt(t)
		local spinCF = handleCF * axis * CF.Angles(0, 0, angles[i])
		for _, piece in gunPieces do
			piece.Part.CFrame = (if piece.Spins then spinCF else handleCF) * piece.At
		end
		gun.Parent = extra
	end

	-- the shots
	drawShots(extra, t)

	-- every hit: chips out of the crack (the game's soft dust puff would be a hard ball here: left out)
	for k = 1, math.min(hits, HITS - 1) do
		local dt = t - hitTimes[k]
		if dt < 0.8 then
			local pieces = Logic.chipPlan({ Position = origin, Crust = crust, Out = normal, Count = 3, Ground = ground, Seed = k * 31 })
			Juice.debris(Geo, extra, pieces, dt, Logic)
		end
	end

	-- the crack stages: RockFx.crack (shards in the dropped ore's glow, chips, flash) + the gold sparkle
	for s = 1, stages - 1 do
		local at = stageTimes[s]
		local dt = if at then t - at else -1
		if dt >= 0 and dt < 1.0 then
			local ore = OreData.ById[drops[s].Ore]
			local glow = if ore then ore.Glow else C3.fromRGB(255, 150, 70)
			Juice.debris(
				Geo,
				extra,
				Logic.crackPlan({
					Position = origin,
					Crust = pal.Mid,
					Glow = glow,
					Stage = s,
					Stages = stages,
					Out = normal,
					Ground = ground,
					Seed = 77 + s,
				}),
				dt,
				Logic
			)
			Juice.particles(Geo, extra, Rng.new("cd" .. s), "Dust", origin, 7, pal.Light, dt)
			Juice.particles(Geo, extra, Rng.new("cg" .. s), "Glint", origin, 6, glow:Lerp(WHITE, 0.3), dt)
			Juice.particles(Geo, extra, Rng.new("gold" .. s), "Glint", origin + normal * 0.3, 5, JuiceConfig.GlintColor, dt)
			Juice.flashBall(Geo, extra, origin, glow, 3.2, dt)
		end
	end

	-- the break: RockFx.shatter
	local st = t - SHATTER
	if st >= 0 and st < 1.6 then
		local ore = OreData.ById[drops[stages].Ore]
		local glow = if ore then ore.Glow else C3.fromRGB(255, 150, 70)
		local pieces = Logic.shatterPlan({
			Position = center,
			Crust = pal.Mid,
			Glow = glow,
			Floor = FLOOR,
			Kind = pristine:GetAttribute("Kind"),
			Radius = radius,
			Ground = ground,
			Seed = 5,
		})
		Juice.debris(Geo, extra, pieces, st, Logic)
		local colors = Logic.colors(FLOOR, pristine:GetAttribute("Kind"), pal.Mid, glow)
		Juice.particles(Geo, extra, Rng.new("sd"), "Dust", center, 8, colors.Rock[2], st)
		Juice.particles(Geo, extra, Rng.new("sf"), "Dust", V3.new(center.X, ground + 0.8, center.Z), 4, colors.Rock[1], st)
		Juice.particles(Geo, extra, Rng.new("sb"), "Burst", center, 18, glow, st)
		Juice.particles(Geo, extra, Rng.new("sg"), "Glint", center + V3.new(0, radius * 0.4, 0), 8, colors.Crystal[1]:Lerp(WHITE, 0.3), st)
		Juice.flashBall(Geo, extra, center, glow:Lerp(WHITE, 0.25), 8, st)
		if st < 0.38 then
			local diameter, transparency = Logic.ring(st, 0.38, radius * 0.6, radius * 2.2)
			local bars, length = Logic.ringSegments(V3.new(center.X, ground + 0.2, center.Z), diameter, 16)
			for _, cf in bars do
				Geo.block(
					extra,
					cf,
					V3.new(0.3, 0.12, length),
					colors.Crystal[1]:Lerp(WHITE, 0.2),
					roblox.Enum.Material.Neon,
					{ CastShadow = false, CanCollide = false, Transparency = transparency }
				)
			end
		end
	end

	-- the dropped ores: fly out, lie there until picked up
	for s, d in drops do
		if d.At and t >= d.At and t < d.Pick then
			local p = chunkAt(d, t)
			ItemBuilder.build({ Kind = "Raw", OreId = d.Ore }, CF.new(p) * CF.Angles(0.4, (t - d.At) * 3 + s, 0.2), 7 + s).Parent = extra
		end
	end

	-- the UI: the 3D ores flying into the backpack button (MineJuiceController.pickup: from the
	-- chunk's middle, as big as it looked there), its bump (MineJuiceController.land: an ore
	-- landing while the bump shows only raises its +N; a new bump flashes at most once per flareGap)
	local landed = 0
	for s, d in drops do
		local flyer = juice.Flyers[s]
		BagFly.setOre(flyer, nil)
		local lying = chunkAt(d, d.Pick)
		local from = screen(lying)
		local lift = (screen(lying + look.RightVector * BagFly.ChunkStuds) - from).Magnitude
		BagFly.poseFlyer(flyer, from, packAt, t - d.Pick, SCALE, s * 1.37, lift)
		if t - d.Pick - FLIGHT >= 0 then
			landed += 1
		end
	end
	local live = {} -- the controller's landings, replayed up to now: { Bump, Start, PlusAt, Count, Flash }
	local lastFlash: number? = nil
	for _, d in drops do
		local at = d.Pick + FLIGHT
		if at > t then
			break
		end
		for k = #live, 1, -1 do
			if at - live[k].PlusAt >= BagFly.BumpSeconds then
				table.remove(live, k)
			end
		end
		local last = live[#live]
		local merge, flash = Rules.land(at, last ~= nil, lastFlash)
		if merge and last then
			last.Count += 1
			last.PlusAt = at
		else
			if flash then
				lastFlash = at
			end
			local used = {}
			for _, l in live do
				used[l.Bump] = true
			end
			local bump = nil
			for _, b in juice.Bumps do
				if not used[b] then
					bump = b
					break
				end
			end
			if not bump then
				bump = table.remove(live, 1).Bump
			end
			table.insert(live, { Bump = bump, Start = at, PlusAt = at, Count = 1, Flash = flash })
		end
	end
	for _, bump in juice.Bumps do
		local entry = nil
		for _, l in live do
			if l.Bump == bump then
				entry = l
			end
		end
		bump.Plus.Label.Text = if entry then "+" .. entry.Count else "+1"
		BagFly.poseBump(
			bump,
			packAt,
			packSize,
			if entry then t - entry.Start else -1,
			SCALE,
			false,
			if entry then entry.Flash else true,
			if entry then t - entry.PlusAt else -1
		)
	end
	setCarry(landed)
	captionText.Text = captionFor(t)
	soundTag.Text = soundFor(t)

	local name = string.format("%04d", i)
	fs.writeFile(root .. "/build/preview/" .. tag .. "/fx_" .. name .. ".json", serde.encode("json", Export.collect(extra)))
	body.Parent = nil
	gun.Parent = nil
	local framePos, frameTarget = cameraAt(t)
	fs.writeFile(
		root .. "/build/preview/" .. tag .. "/ui_" .. name .. ".json",
		serde.encode("json", UiExport.export({ hud.Gui, juice.Gui, caption }))
	)
	shots[tag .. "_" .. name] = {
		scene = tag .. "_base",
		extra = tag .. "/fx_" .. name,
		ui = tag .. "/ui_" .. name,
		width = W,
		height = H,
		uiInset = INSET,
		position = { camPos.X, camPos.Y, camPos.Z },
		target = { camTarget.X, camTarget.Y, camTarget.Z },
		cam = { position = { framePos.X, framePos.Y, framePos.Z }, target = { frameTarget.X, frameTarget.Y, frameTarget.Z }, fov = FOV },
		fov = FOV,
		preset = floor.Lighting,
		shadowExtent = 90,
		maxLights = 24,
		sunDir = { -0.5, 0.72, 0.48 },
	}
end
fs.writeFile(root .. "/build/preview/" .. tag .. "_shots.json", serde.encode("json", shots))

-- the storyboard (tools/preview/render_reel.mjs): Czech captions for the owner
local function frameAt(seconds: number): number
	return math.clamp(math.floor(seconds * fps + 0.5), 0, frames - 1)
end
local fullSpin = FIRE + Shots.SpinUp
local board = {
	title = "STŘELBA A TĚŽBA (6. 11.)",
	fps = fps,
	cells = {
		{ frame = frameAt(FIRE + 0.25), caption = "Začátek: pomalé střely, kotouč se rozjíždí" },
		{ frame = frameAt(FIRE + 1), caption = "Zrychluje: 14 střel za sekundu" },
		{ frame = frameAt(fullSpin + 0.1), caption = "Plné otáčky: 24 střel za sekundu" },
		{ frame = frameAt((stageTimes[2] or fullSpin) + 0.08), caption = "Prasknutí: kus kamene odpadne, vypadne ruda" },
		{ frame = frameAt(hitTimes[HITS - 1] + 0.05), caption = "Velká prasklina, střely pořád jednotlivě" },
		{ frame = frameAt(SHATTER + 0.12), caption = "Poslední zásah: kámen se rozletí" },
		{ frame = frameAt(drops[1].Pick + 0.25), caption = "Ruda se zvedne ze země" },
		{ frame = frameAt(drops[stages].Pick + FLIGHT + 0.12), caption = "+1 v batohu" },
	},
}
fs.writeFile(root .. "/build/preview/" .. tag .. "_board.json", serde.encode("json", board))
print(`{frames} frames at {fps} fps ({total} s)`)
