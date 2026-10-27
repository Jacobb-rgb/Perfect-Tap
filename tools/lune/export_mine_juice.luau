--[[
	Video frames of the mining reel (owner 2026-10-27, "How do games make MINING
	feel satisfying?"; Config/JuiceConfig.Mining) in our game, posed with the
	game's own code: a miner on mine floor 1 blasts a rock; every hit (a Health
	drop, about 3 a second) grows the crack (Effects/CrackLogic laid out like
	RockCracks) and its gold glints flare, chips fly (RockFxLogic.chipPlan), the
	rock trembles (RockFxLogic.shakeOffset); at each crack stage the server's
	cracks open (RockBuilder.applyStage), a chunk breaks off, RockFx pops and an
	ore drops; the last hit shatters it (RockFx: RockFxLogic.shatterPlan, dust,
	the ground ring; no comic word: the owner turned it down); the dirty ores are picked up and fly into the
	carry slots (UI/BagFly, the HUD of today's game) with a +1 each. A caption
	line at the top (preview only) names the reel's steps and the sounds.

	  lune run tools/lune/export_mine_juice.luau [fps=20]
	-> build/preview/minejuice_base.json (the floor, the miner: once)
	   build/preview/minejuice/fx_NNNN.json + ui_NNNN.json per frame
	   build/preview/minejuice_shots.json, build/preview/minejuice_board.json
	then: node tools/preview/render_reel.mjs minejuice
	(three.js approximation of Roblox: no physics, the chunks fly on simple arcs,
	no camera shake, sounds are named in the caption.)
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

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true

local fps = tonumber(process.args[1]) or 20
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

-- the miner 8 studs off, blasting it
local away = V3.new(-6.5, 0, 5).Unit
local feet = V3.new(center.X, ground, center.Z) + away * 8
local aimPoint = Gallery.surface(pristine, feet, 0.6)
local _, muzzle = Gallery.forgekeeper(Loader, area, CF.lookAt(feet, V3.new(center.X, ground, center.Z)), aimPoint, 3, "Copper")
local beamGlow = BlasterBuilder.look(3, "Copper").Glow

-- the camera from the side, like the reel: the miner on the left, the rock big on the right
local facing = -away
local right = V3.new(-facing.Z, 0, facing.X)
local middle = (feet + V3.new(center.X, ground, center.Z)) / 2
local camPos = middle + right * 12.5 + facing * 1.5 + V3.new(0, 5.2, 0)
local camTarget = middle + facing * 2 + V3.new(0, 2.6, 0)

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
local look = CF.lookAt(camPos, camTarget)
local function screen(p): any
	local rel = look:PointToObjectSpace(p)
	local f = 1 / math.tan(math.rad(FOV) / 2)
	local x = (rel.X / -rel.Z) * f * (H / W)
	local y = (rel.Y / -rel.Z) * f
	return V2.new((x + 1) / 2 * W, (1 - y) / 2 * H - INSET)
end

---------------------------------------------------------------- the timeline (seconds)

local FIRE = 0.5
local HITS = 12
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
local function setCarry(count: number)
	local squares, shown, more, width = HudView.carryLayout(CAPACITY, count)
	for i = 1, squares do
		if more > 0 and i == squares then
			HudView.carrySlot(hud.CarrySlots, i, nil, false, more)
		else
			HudView.carrySlot(hud.CarrySlots, i, nil, i <= shown, 0)
		end
	end
	HudView.trimSlots(hud.CarrySlots, squares)
	hud.CarryLabel.Text = `CARRYING {count}/{CAPACITY}`
	hud.CarryPanel.Size = roblox.UDim2.fromOffset(width, HudView.CarryPanelHeight)
	return squares
end
local squares = setCarry(0)
-- the n-th carry slot's middle (overlay pixels): the row is centred at the bottom
local SLOT, GAP, LIP = 70, 10, 5
local function slotCenter(n: number): any
	local x = W / 2 + ((n - 1) - (squares - 1) / 2) * (SLOT + GAP) * SCALE
	local y = (H - INSET) - (16 + (SLOT + LIP) / 2) * SCALE
	return x, y
end

local juice = BagFly.build()

-- the caption line (preview only: what the reel's step is, which sound plays)
local caption = Instance.new("ScreenGui")
caption.Name = "Caption"
caption.IgnoreGuiInset = false
local box = UIKit.new("Frame", {
	Name = "Box",
	AnchorPoint = V2.new(0.5, 0),
	Position = roblox.UDim2.new(0.5, 0, 0, 44),
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
	Position = roblox.UDim2.new(0.5, 0, 0, 98),
	Size = roblox.UDim2.fromOffset(600, 30),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 24,
	TextColor3 = C3.fromRGB(255, 226, 150),
	Text = "",
}, caption)

local function captionFor(t: number): string
	if t < FIRE then
		return "Těžba podle videa: laser míří na kámen"
	elseif t < (stageTimes[2] or SHATTER) - 0.05 then
		return "1 PRASKLINY: každý zásah tmavou prasklinu prodlouží"
	elseif t < (stageTimes[3] or SHATTER) - 0.05 then
		return "2 ÚLOMKY odletují  ·  4 kámen se při zásahu otřese"
	elseif t < SHATTER - 0.02 then
		return "BONUS: zlaté jiskry v prasklinách (stejné u každé rudy)"
	elseif t < drops[1].Pick then
		return "5 POSLEDNÍ ZÁSAH: kámen se rozletí na kusy, prach"
	end
	return "5 Ruda vyskočí, zazáří a letí do batohu: +1"
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
	for _, at in hitTimes do
		if t >= at and t < at + 0.14 and t < SHATTER then
			return "zvuk: ťuk"
		end
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
		-- the beam
		if t >= FIRE then
			Gallery.beam(Loader, extra, muzzle, aimPoint, beamGlow)
		end
	end

	-- every hit: chips out of the crack, a puff of dust
	for k = 1, math.min(hits, HITS - 1) do
		local dt = t - hitTimes[k]
		if dt < 0.8 then
			local pieces = Logic.chipPlan({ Position = origin, Crust = crust, Out = normal, Count = 3, Ground = ground, Seed = k * 31 })
			Juice.debris(Geo, extra, pieces, dt, Logic)
			Juice.particles(Geo, extra, Rng.new("dust" .. k), "Dust", aimPoint, 1, pal.Light, dt)
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
		Juice.particles(Geo, extra, Rng.new("sd"), "Dust", center, 16, colors.Rock[2], st)
		Juice.particles(Geo, extra, Rng.new("sf"), "Dust", V3.new(center.X, ground + 0.8, center.Z), 8, colors.Rock[1], st)
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

	-- the UI: the ores flying into the carry slots, the +1 bumps, the count
	local landed = 0
	local bumpOf = {} -- bump -> the drop that landed on it last
	for s, d in drops do
		local flyer = juice.Flyers[s]
		BagFly.setOre(flyer, nil)
		local from = screen(chunkAt(d, d.Pick) + V3.new(0, 0.6, 0))
		local x, y = slotCenter(s)
		BagFly.poseFlyer(flyer, from, V2.new(x, y), t - d.Pick, SCALE, s * 1.37)
		local b = (s - 1) % #juice.Bumps + 1
		if t - d.Pick - FLIGHT >= 0 then
			landed += 1
			bumpOf[b] = s
		end
	end
	for b, bump in juice.Bumps do
		local s = bumpOf[b]
		local x, y = slotCenter(s or 1)
		bump.Plus.Label.Text = "+1"
		BagFly.poseBump(bump, V2.new(x, y), V2.new(SLOT, SLOT) * SCALE, if s then t - drops[s].Pick - FLIGHT else -1, SCALE)
	end
	setCarry(landed)
	captionText.Text = captionFor(t)
	soundTag.Text = soundFor(t)

	local name = string.format("%04d", i)
	fs.writeFile(root .. "/build/preview/" .. tag .. "/fx_" .. name .. ".json", serde.encode("json", Export.collect(extra)))
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
local board = {
	title = "TĚŽBA podle videa (27. 10.)",
	fps = fps,
	cells = {
		{ frame = frameAt(hitTimes[1] + 0.1), caption = "1 První zásah: malá tmavá prasklina, ťuk" },
		{ frame = frameAt(hitTimes[2] + 0.06), caption = "1+2 Další zásah: prasklina roste, odletují úlomky" },
		{ frame = frameAt((stageTimes[2] or 1) + 0.08), caption = "3 Prasknutí: křup, kus kamene odpadne, vypadne ruda" },
		{ frame = frameAt(hitTimes[HITS - 1] + 0.05), caption = "BONUS Velká prasklina se zlatými jiskrami" },
		{ frame = frameAt(SHATTER + 0.12), caption = "5 Poslední zásah: kámen se rozletí, prach a kusy" },
		{ frame = frameAt(drops[1].Pick + 0.25), caption = "5 Ruda vyskočí a zazáří" },
		{ frame = frameAt(drops[2].Pick + 0.55), caption = "5 ... letí do batohu (sloty dole)" },
		{ frame = frameAt(drops[stages].Pick + FLIGHT + 0.12), caption = "5 +1 v batohu, počet naskočí" },
	},
}
fs.writeFile(root .. "/build/preview/" .. tag .. "_board.json", serde.encode("json", board))
print(`{frames} frames at {fps} fps ({total} s)`)
