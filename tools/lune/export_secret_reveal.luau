--[[
	Video frames of the SECRET ore reveal (owner 2026-10-29: secret ores with
	"cool animace", Pet Simulator style), posed with the game's own code: a
	miner on mine floor 3 (Deep Hollow) blasts a rock; its crack stages drop
	two dirty ores (RockBuilder.applyStage); the last hit shatters it
	(RockFxLogic.shatterPlan) and instead of a dirty chunk a column of
	rainbow light shoots up out of it (everyone near sees it) with the secret
	ore spinning in it; then the jackpot screen (Effects/SecretReveal: the
	dark, the black silhouette's three heartbeats, the flash, rays, confetti,
	SECRET!, Hollow Eye, the chance, NEW!) and the ore flies into the
	backpack button (UI/BagFly's bump and +1). The server's chat line for
	everyone shows in a stand-in chat box at the top left. A caption line at
	the top (preview only) names the steps and the sounds.

	  lune run tools/lune/export_secret_reveal.luau [fps=20] [ore=HollowEye]
	-> build/preview/secretreveal_base.json, build/preview/secretreveal/fx_NNNN.json + ui_NNNN.json,
	   build/preview/secretreveal_shots.json, build/preview/secretreveal_board.json
	then: node tools/preview/render_reel.mjs secretreveal
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
local SECRET = process.args[2] or "HollowEye"
local CF = Loader.CFrame
local V3 = roblox.Vector3
local V2 = roblox.Vector2
local C3 = roblox.Color3
local Instance = roblox.Instance
local WHITE = C3.new(1, 1, 1)
local GRAVITY = 196.2
local NEON = roblox.Enum.Material.Neon

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
local SecretOreShapes = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreShapes")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RockFxLogic")
local SecretReveal = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.SecretReveal")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local BagFly = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BagFly")
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

local W, H, INSET, SCALE, FOV = 1600, 900, 36, 1.25, 62
local tag = "secretreveal"
local secret = SecretOreConfig.ByOre[SECRET]
assert(secret, "not a secret ore: " .. SECRET)
local floor = MineFloors.get(if secret.Floor then secret.Floor else 3)
local FLOOR = floor.Index
local pal = floor.Palette
local secretOre = OreData.get(SECRET)
local chanceText = SecretOreConfig.chanceText(secret.OneIn)

---------------------------------------------------------------- the scene

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local area = Instance.new("Model")
area.Name = floor.Id
area.Parent = workspace
Geo.block(area, CF.new(0, -0.5, 0), V3.new(90, 1, 80), pal.Ground)
Geo.block(area, CF.new(0, 9, -17), V3.new(90, 20, 3), pal.Dark)
Geo.block(area, CF.new(-26, 6, -4), V3.new(3, 14, 30), pal.Mid)
local weights = {}
for oreId in floor.Ores do
	table.insert(weights, oreId)
end
table.sort(weights)
for k, spot in { V3.new(-11, 0, -9), V3.new(10, 0, -10), V3.new(17, 0, 2) } do
	local kind = if k == 2 then "Crystal" else "Small"
	RockBuilder.build(FLOOR, kind, { weights[1], weights[2], weights[3] }, CF.new(spot), 300 + k).Parent = area
end
for _, at in { V3.new(-10, 12, 8), V3.new(12, 12, 9), V3.new(0, 10, -12) } do
	local holder = Geo.block(area, CF.new(at), V3.new(0.2, 0.2, 0.2), WHITE, nil, { Transparency = 1, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = C3.fromRGB(236, 246, 255)
	light.Range = 36
	light.Brightness = 0.7
	light.Parent = holder
end

-- the blasted rock: a Small one (3 ores: 2 crack stages, then the break); the last ore is the secret
local ORES = { weights[1], weights[2], weights[3] }
local pristine = RockBuilder.build(FLOOR, "Small", ORES, CF.new(0, 0, 0), 4242)
pristine:SetAttribute("Kind", "Small")
local stages = MineFloors.OreCount.Small
local center, size = Juice.bounds(pristine)
local radius = math.max(size.X, size.Z) / 2 * 0.8
local ground = 0

local away = V3.new(-6.5, 0, 5).Unit
local feet = V3.new(center.X, ground, center.Z) + away * 8
local aimPoint = Gallery.surface(pristine, feet, 0.6)
local level = math.max(floor.MinBlaster, 1)
local _, muzzle = Gallery.forgekeeper(Loader, area, CF.lookAt(feet, V3.new(center.X, ground, center.Z)), aimPoint, level, "Gold")
local beamGlow = BlasterBuilder.look(level, "Gold").Glow

local facing = -away
local right = V3.new(-facing.Z, 0, facing.X)
local middle = (feet + V3.new(center.X, ground, center.Z)) / 2
local camPos = middle + right * 13 + facing * 1.5 + V3.new(0, 5.6, 0)
local camTarget = middle + facing * 2 + V3.new(0, 3.4, 0)

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

---------------------------------------------------------------- the timeline (seconds)

local FIRE = 0.3
local HITS = 6
local HIT_GAP = 0.3
local hitTimes = {}
for k = 1, HITS do
	hitTimes[k] = FIRE + 0.1 + (k - 1) * HIT_GAP
end
local SHATTER = hitTimes[HITS]
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
-- the two dirty ores of the crack stages (they stay on the ground in this clip)
local drops = {}
for s = 1, stages - 1 do
	local turn = ({ -0.7, 0.6 })[s] or 0
	local out = CF.Angles(0, turn, 0):VectorToWorldSpace(away)
	drops[s] = {
		At = stageTimes[s],
		Ore = ORES[s],
		Origin = center + V3.new(0, radius * 0.5 + 1.2, 0) + out * 0.8,
		Velocity = out * (11 + 1.5 * s) + V3.new(0, 15, 0),
	}
end
local REVEAL = SHATTER + 0.45 -- the jackpot screen starts (the column of light has shot up)
local reveal = function(t: number): number
	return t - REVEAL
end
local LAND = REVEAL + SecretReveal.Hold + SecretReveal.Fly
local total = LAND + BagFly.BumpSeconds + 0.9

local function chunkAt(d, t: number): any
	local dt = t - d.At
	local o, v = d.Origin, d.Velocity
	local rest = ground + 0.5
	local land = (v.Y + math.sqrt(v.Y * v.Y + 2 * GRAVITY * math.max(0, o.Y - rest))) / GRAVITY
	local tl = math.min(dt, land)
	return o + v * tl - V3.new(0, 0.5 * GRAVITY * tl * tl, 0)
end

---------------------------------------------------------------- the UI

local hud = HudView.build()
hud.Gui.Scale.Scale = SCALE
hud.Coins.Text = "$1.2M"
hud.Zone.Text = ""
hud.Toasts:ClearAllChildren()
local CAPACITY = 60
HudView.placeBackpack(hud, SCALE)
local carried = 14
HudView.setBackpack(hud, carried, CAPACITY)
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
-- (the secret screen ignores the top inset: the bag's middle in its full-screen pixels)
local packFull = packAt + V2.new(0, INSET)

local juice = BagFly.build()
local view = SecretReveal.build()
SecretReveal.setOre(view, SECRET, { Chance = chanceText, New = true })
view.View:SetAttribute("PreviewLive", true)

-- a stand-in for Roblox's chat box: the server's line for everyone on the server
local chat = Instance.new("ScreenGui")
chat.Name = "Chat"
chat.IgnoreGuiInset = false
chat.DisplayOrder = 99 -- (Roblox draws its chat over the game's screens)
local chatBox = UIKit.new("Frame", {
	Name = "Box",
	Position = roblox.UDim2.fromOffset(14, 14),
	Size = roblox.UDim2.fromOffset(500, 120),
	BackgroundColor3 = C3.fromRGB(20, 22, 30),
	BackgroundTransparency = 0.45,
}, chat)
UIKit.corner(chatBox, 10)
local function chatLine(y: number, text: string, color: any): any
	return UIKit.new("TextLabel", {
		Name = "Line",
		BackgroundTransparency = 1,
		Position = roblox.UDim2.fromOffset(12, y),
		Size = roblox.UDim2.fromOffset(476, 26),
		FontFace = roblox.Font.fromEnum(roblox.Enum.Font.GothamBold),
		TextSize = 17,
		TextXAlignment = roblox.Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = text,
	}, chatBox)
end
chatLine(10, "Mia: anyone got the elevator?", C3.fromRGB(230, 230, 236))
chatLine(36, "Leo: deep hollow is so good", C3.fromRGB(230, 230, 236))
local secretLine = chatLine(62, "", C3.fromRGB(255, 150, 236))
local secretLine2 = chatLine(86, "", C3.fromRGB(255, 150, 236))

local caption = Instance.new("ScreenGui")
caption.Name = "Caption"
caption.IgnoreGuiInset = false
caption.DisplayOrder = 100
local box = UIKit.new("Frame", {
	Name = "Box",
	AnchorPoint = V2.new(1, 0),
	Position = roblox.UDim2.new(1, -14, 0, 14),
	Size = roblox.UDim2.fromOffset(600, 84),
	BackgroundColor3 = C3.fromRGB(20, 22, 30),
	BackgroundTransparency = 0.25,
}, caption)
UIKit.corner(box, 14)
local captionText = UIKit.new("TextLabel", {
	Name = "Text",
	BackgroundTransparency = 1,
	Size = roblox.UDim2.fromScale(1, 1),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 25,
	TextWrapped = true,
	TextColor3 = WHITE,
	Text = "",
}, box)
local soundTag = UIKit.new("TextLabel", {
	Name = "Sound",
	AnchorPoint = V2.new(1, 0),
	BackgroundTransparency = 1,
	Position = roblox.UDim2.new(1, -14, 0, 104),
	Size = roblox.UDim2.fromOffset(600, 30),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 24,
	TextColor3 = C3.fromRGB(255, 226, 150),
	Text = "",
}, caption)

local burstAt = REVEAL + SecretReveal.Burst
local function captionFor(t: number): string
	if t < SHATTER then
		return "Těžíš úplně normálně..."
	elseif t < REVEAL + 0.1 then
		return "Z kamene vystřelí duhový sloup světla: všichni kolem ho vidí"
	elseif t < burstAt then
		return "Obrazovka ztmavne: černý stín rudy, tři údery srdce"
	elseif t < REVEAL + SecretReveal.Hold then
		return "SECRET! Záblesk, paprsky, konfety, jméno a šance"
	elseif t < LAND + 0.1 then
		return "Tajná ruda letí do batohu"
	end
	return "+1 v batohu. A celý server to vidí v chatu"
end

local function soundFor(t: number): string
	if t >= SHATTER and t < SHATTER + 0.5 then
		return "zvuk: hluboké BUM + zvonivý třpyt"
	elseif t >= REVEAL + SecretReveal.Thumps[1] and t < burstAt then
		return "zvuk: buch... buch... BUCH (srdce)"
	elseif t >= burstAt and t < burstAt + 1.2 then
		return "zvuk: jackpot fanfára + cinkání"
	elseif t >= LAND and t < LAND + 0.4 then
		return "zvuk: pop (do batohu)"
	end
	for _, at in hitTimes do
		if t >= at and t < at + 0.14 and t < SHATTER then
			return "zvuk: ťuk"
		end
	end
	return ""
end

---------------------------------------------------------------- frames

local crust = pristine.PrimaryPart.Color
local frames = math.floor(total * fps)
local shots = {}
for i = 0, frames - 1 do
	local t = i / fps
	local extra = Instance.new("Model")
	local hits, lastHit = 0, -math.huge
	for k, at in hitTimes do
		if t >= at then
			hits, lastHit = k, at
		end
	end
	local stage = stageOf(hits)

	if t < SHATTER then
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
					local p = piece.CFrame.Position + v * dt - V3.new(0, 0.5 * GRAVITY * dt * dt, 0)
					piece.CFrame = CF.new(p) * (piece.CFrame - piece.CFrame.Position) * CF.Angles(dt * 6, dt * 4, dt * 5)
				end
			end
		end
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
		if t >= FIRE then
			Gallery.beam(Loader, extra, muzzle, aimPoint, beamGlow)
		end
	end

	for k = 1, math.min(hits, HITS - 1) do
		local dt = t - hitTimes[k]
		if dt < 0.8 then
			local pieces = Logic.chipPlan({
				Position = aimPoint,
				Crust = crust,
				Out = (feet - center).Unit,
				Count = 3,
				Ground = ground,
				Seed = k * 31,
			})
			Juice.debris(Geo, extra, pieces, dt, Logic)
			Juice.particles(Geo, extra, Rng.new("dust" .. k), "Dust", aimPoint, 1, pal.Light, dt)
		end
	end

	-- the break: RockFx.shatter, in the secret's glow
	local st = t - SHATTER
	if st >= 0 and st < 1.6 then
		local glow = secretOre.Glow
		local pieces = Logic.shatterPlan({
			Position = center,
			Crust = pal.Mid,
			Glow = glow,
			Floor = FLOOR,
			Kind = "Small",
			Radius = radius,
			Ground = ground,
			Seed = 5,
		})
		Juice.debris(Geo, extra, pieces, st, Logic)
		Juice.particles(Geo, extra, Rng.new("sd"), "Dust", center, 14, pal.Light, st)
		Juice.particles(Geo, extra, Rng.new("sb"), "Burst", center, 22, glow, st)
		Juice.particles(Geo, extra, Rng.new("sg"), "Glint", center + V3.new(0, radius * 0.4, 0), 12, WHITE, st)
		Juice.flashBall(Geo, extra, center, WHITE, 9, st)
	end

	-- the column of rainbow light (SecretService's world beam: 3 s, everyone near sees it)
	if st >= 0 and st < 3.2 then
		local up = math.min(st / 0.25, 1)
		local fade = math.clamp((st - 2.4) / 0.8, 0, 1)
		local height = 46 * up
		local base = V3.new(center.X, ground, center.Z)
		for k, color in SecretOreShapes.Rainbow do
			-- six thin coloured shafts round a white core, slowly turning
			local a = k * math.pi / 3 + st * 1.6
			local at = base + V3.new(math.cos(a) * 0.9, height / 2, math.sin(a) * 0.9)
			Geo.block(
				extra,
				CF.new(at),
				V3.new(0.5, height, 0.5),
				color,
				NEON,
				{ CastShadow = false, CanCollide = false, Transparency = 0.25 + 0.75 * fade }
			)
		end
		Geo.block(
			extra,
			CF.new(base + V3.new(0, height / 2, 0)),
			V3.new(1.1, height, 1.1),
			WHITE,
			NEON,
			{ CastShadow = false, CanCollide = false, Transparency = 0.15 + 0.85 * fade }
		)
		if st < 0.6 then
			local diameter, transparency = Logic.ring(st, 0.6, radius * 0.6, radius * 3.2)
			local bars, length = Logic.ringSegments(V3.new(center.X, ground + 0.2, center.Z), diameter, 18)
			for k, cf in bars do
				local color = SecretOreShapes.Rainbow[(k - 1) % #SecretOreShapes.Rainbow + 1]
				Geo.block(
					extra,
					cf,
					V3.new(0.35, 0.14, length),
					color,
					NEON,
					{ CastShadow = false, CanCollide = false, Transparency = transparency }
				)
			end
		end
		-- the secret ore itself rises in the light until the jackpot screen takes it
		if t < REVEAL then
			local lift = math.min(st / 0.4, 1)
			local item = ItemBuilder.display(
				{ K = "Clean", O = SECRET, G = SecretOreConfig.Grade },
				CF.new(center.X, ground + 1.2 + 2.4 * lift, center.Z) * CF.Angles(0, st * 5, 0),
				SECRET
			)
			item.Parent = extra
		end
	end

	-- the dirty ores of the crack stages
	for s, d in drops do
		if t >= d.At then
			local p = chunkAt(d, t)
			ItemBuilder.build({ Kind = "Raw", OreId = d.Ore }, CF.new(p) * CF.Angles(0.4, math.min(t - d.At, 0.6) * 3 + s, 0.2), 7 + s).Parent =
				extra
		end
	end

	-- the jackpot screen, then the bump at the bag
	SecretReveal.pose(view, reveal(t), { Screen = V2.new(W, H), Scale = SCALE, Target = packFull, Reduced = false })
	if t < REVEAL then
		view.Gui.Enabled = false
	end
	local bump = juice.Bumps[1]
	bump.Plus.Label.Text = "+1"
	BagFly.poseBump(bump, packAt, packSize, t - LAND, SCALE, false, true, t - LAND)
	HudView.setBackpack(hud, carried + (if t >= LAND then 1 else 0), CAPACITY)
	local said = t >= burstAt
	secretLine.Text = if said then "[SECRET] Kuba found Hollow Eye!" else ""
	secretLine2.Text = if said then `    ({chanceText}, Deep Hollow)` else ""
	if SECRET ~= "HollowEye" then
		secretLine.Text = if said then `[SECRET] Kuba found {secretOre.Name}!` else ""
	end
	captionText.Text = captionFor(t)
	soundTag.Text = soundFor(t)

	local name = string.format("%04d", i)
	fs.writeFile(root .. "/build/preview/" .. tag .. "/fx_" .. name .. ".json", serde.encode("json", Export.collect(extra)))
	fs.writeFile(
		root .. "/build/preview/" .. tag .. "/ui_" .. name .. ".json",
		serde.encode("json", UiExport.export({ hud.Gui, juice.Gui, chat, view.Gui, caption }))
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

local function frameAt(seconds: number): number
	return math.clamp(math.floor(seconds * fps + 0.5), 0, frames - 1)
end
local board = {
	title = "TAJNÁ RUDA (SECRET): jak vypadá, když padne",
	fps = fps,
	cells = {
		{ frame = frameAt(hitTimes[3]), caption = "1 Těžíš normálně, padají špinavé rudy" },
		{ frame = frameAt(SHATTER + 0.3), caption = "2 Poslední zásah: duhový sloup světla" },
		{ frame = frameAt(REVEAL + SecretReveal.Thumps[2] + 0.1), caption = "3 Tma, černý stín rudy, údery srdce" },
		{ frame = frameAt(burstAt + 0.12), caption = "4 ZÁBLESK: tajná ruda se ukáže" },
		{ frame = frameAt(burstAt + 0.9), caption = "5 SECRET! Jméno, šance 1 z 4 000, NEW!" },
		{ frame = frameAt(REVEAL + SecretReveal.Hold - 0.6), caption = "6 Paprsky se točí, ruda se točí" },
		{ frame = frameAt(REVEAL + SecretReveal.Hold + 0.45), caption = "7 Letí do batohu" },
		{ frame = frameAt(LAND + 0.3), caption = "8 +1 v batohu, celý server to vidí v chatu" },
	},
}
fs.writeFile(root .. "/build/preview/" .. tag .. "_board.json", serde.encode("json", board))
print(`{frames} frames at {fps} fps ({total} s)`)
