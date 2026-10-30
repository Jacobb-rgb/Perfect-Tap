--[[
	Video frames of a SECRET ore's jackpot at the Cleaning Station (owner
	2026-10-29: the jackpot plays when the player cleans the sparkly ore,
	"udělej to ještě mnohem mnohem víc cool"), posed with the game's code:
	the station on plot 1, the clump of dirt (OreShellBuilder: rainbow specks
	in the dirt), a good player spraying it (SprayScoring tracker, the wand,
	the jet). As the dirt washes off, rainbow light leaks out through the
	holes, longer the cleaner it gets, and the clump shakes harder; the last
	bit: everything holds, the leaking light goes white-hot, three
	heartbeats (a ring off the clump each), the camera pushes in. BOOM: the
	rest of the dirt flies off, a shockwave ring, a column of rainbow light
	shoots into the sky, the camera kicks back and shakes, and the jackpot
	screen (Effects/SecretReveal) plays. Then the result card (Flawless) and
	a wide shot: the column of light stands over the plot (everyone near
	sees it) and the chat line for the whole server. A caption at the top
	right (preview only) names the steps and the sounds.

	  lune run tools/lune/export_secret_clean.luau [fps=20] [ore=HollowEye] [tag=secretclean]
	-> build/preview/<tag>_base.json, build/preview/<tag>/fx_NNNN.json + ui_NNNN.json,
	   build/preview/<tag>_shots.json (a camera per frame), build/preview/<tag>_board.json
	then: node tools/preview/render_reel.mjs <tag>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true

local fps = tonumber(process.args[1]) or 20
local SECRET = process.args[2] or "HollowEye"
local tag = process.args[3] or "secretclean"
local CF = Loader.CFrame
local V3 = roblox.Vector3
local V2 = roblox.Vector2
local C3 = roblox.Color3
local Instance = roblox.Instance
local WHITE = C3.new(1, 1, 1)
local NEON = roblox.Enum.Material.Neon
local W, H, INSET = 1600, 900, 36

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
local Scoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.SprayScoring")
local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
local SecretOreFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreFx")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
local CleaningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CleaningView")
local CardLook = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CardLook")
local SprayParts = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.SprayParts")
local CameraFit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CameraFit")
local SecretReveal = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.SecretReveal")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local BagFly = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BagFly")
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
local Players = require("./lib/spray_players")(Loader)

local secret = SecretOreConfig.ByOre[SECRET]
assert(secret, "not a secret ore: " .. SECRET)
local ore = OreData.get(SECRET)
local chanceText = SecretOreConfig.chanceText(secret.OneIn)
local floorName = if secret.Floor then MineFloors.ById[secret.Floor].Name else "every floor"
local RAINBOW = SecretOreConfig.Rainbow

---------------------------------------------------------------- the world + the station

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
WorldBuilder.build(workspace)
local plot = WorldLayout.Plots[1]
local plotCf = WorldLayout.plotCFrame(plot)
local stationCf
local kitShiftX, kitShiftZ = (GameConfig.PlotCells - 12) / 2, GameConfig.PlotCells - 12
local layout = { { Id = "CleaningStation", X = 4 + kitShiftX, Z = 4 + kitShiftZ, R = 0 } }
for _, entry in MachineData.StarterKit do
	table.insert(layout, entry)
end
for _, entry in layout do
	local machine = MachineData.ById[entry.Id]
	local w, d = MachineData.footprint(machine, entry.R)
	local half = GameConfig.PlotCells * GameConfig.CellSize / 2
	local cf = plotCf
		* CF.new(-half + (entry.X + w / 2) * GameConfig.CellSize, 0, -half + (entry.Z + d / 2) * GameConfig.CellSize)
		* CF.Angles(0, -entry.R * math.pi / 2, 0)
	local model = MachineBuilder.build(entry.Id)
	model:PivotTo(cf)
	model.Parent = workspace
	if entry.Id == "CleaningStation" then
		stationCf = cf
	end
end
local orePoint = stationCf * CF.new(0, 3.4 + 1.95, 0.3)
local camPos = (stationCf * CF.new(0, 3.4 + 5.4, -4.6)).Position
local pattern = Patterns.generate(SECRET, 4242)
local workCf = CF.lookAt(orePoint.Position, orePoint.Position - (camPos - orePoint.Position).Unit)
local center = orePoint.Position

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

---------------------------------------------------------------- the UI

local view = CleaningView.build({ Touch = false })
view.Gui.Scale.Scale = 1.25
CleaningView.setCompact(view, false, 48)
CardLook.styleBar(view)
local camCf, camFov = CameraFit.compute({
	ViewportHeight = H,
	InsetTop = INSET,
	FreeTop = CleaningView.BannerBottom,
	FreeBottom = CleaningView.BottomReserved,
	UiScale = 1.25,
	Outline = pattern.Outline,
	FaceScale = OreShellBuilder.Scale,
	CamPoint = CF.lookAt(camPos, center + V3.new(0, 0.1, 0)),
	OrePoint = center,
})

local reveal = SecretReveal.build()
SecretReveal.setOre(reveal, SECRET, { Chance = chanceText, New = true })
reveal.View:SetAttribute("PreviewLive", true)

local hud = HudView.build()
hud.Gui.Scale.Scale = 1.25
hud.Coins.Text = "$1.2M"
hud.Zone.Text = ""
hud.Toasts:ClearAllChildren()
HudView.placeBackpack(hud, 1.25)
HudView.setBackpack(hud, 14, 60)
local juice = BagFly.build()

-- a stand-in for Roblox's chat box: the server's line for everyone on the server
local chat = Instance.new("ScreenGui")
chat.Name = "Chat"
chat.IgnoreGuiInset = false
chat.DisplayOrder = 99
local chatBox = UIKit.new("Frame", {
	Name = "Box",
	Position = roblox.UDim2.fromOffset(14, 128), -- under the cleaning's Leave button
	Size = roblox.UDim2.fromOffset(520, 120),
	BackgroundColor3 = C3.fromRGB(20, 22, 30),
	BackgroundTransparency = 0.45,
}, chat)
UIKit.corner(chatBox, 10)
local function chatLine(y: number, text: string, color: any): any
	return UIKit.new("TextLabel", {
		Name = "Line",
		BackgroundTransparency = 1,
		Position = roblox.UDim2.fromOffset(12, y),
		Size = roblox.UDim2.fromOffset(496, 26),
		FontFace = roblox.Font.fromEnum(roblox.Enum.Font.GothamBold),
		TextSize = 17,
		TextXAlignment = roblox.Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = text,
	}, chatBox)
end
chatLine(10, "Mia: anyone got the elevator?", C3.fromRGB(230, 230, 236))
chatLine(36, "Leo: whats that light??", C3.fromRGB(230, 230, 236))
local secretLine = chatLine(62, "", C3.fromRGB(255, 150, 236))
local secretLine2 = chatLine(86, "", C3.fromRGB(255, 150, 236))

local caption = Instance.new("ScreenGui")
caption.Name = "Caption"
caption.IgnoreGuiInset = false
caption.DisplayOrder = 100
local box = UIKit.new("Frame", {
	Name = "Box",
	AnchorPoint = V2.new(1, 1),
	Position = roblox.UDim2.new(1, -14, 1, -14),
	Size = roblox.UDim2.fromOffset(560, 84),
	BackgroundColor3 = C3.fromRGB(20, 22, 30),
	BackgroundTransparency = 0.25,
}, caption)
UIKit.corner(box, 14)
local captionText = UIKit.new("TextLabel", {
	Name = "Text",
	BackgroundTransparency = 1,
	Size = roblox.UDim2.fromScale(1, 1),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 24,
	TextWrapped = true,
	TextColor3 = WHITE,
	Text = "",
}, box)
local soundTag = UIKit.new("TextLabel", {
	Name = "Sound",
	AnchorPoint = V2.new(1, 1),
	BackgroundTransparency = 1,
	Position = roblox.UDim2.new(1, -14, 1, -104),
	Size = roblox.UDim2.fromOffset(560, 30),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 22,
	TextColor3 = C3.fromRGB(255, 226, 150),
	Text = "",
}, caption)

---------------------------------------------------------------- the timeline (seconds)

local SPRAY = 3.8 -- washing the dirt off
local HOLD = 0.9 -- the last bit: everything holds, three heartbeats
local BOOM = SPRAY + HOLD
local THUMPS = { SPRAY + 0.12, SPRAY + 0.42, SPRAY + 0.68 }
local SHOW = SecretReveal.total(secret.Stars) - SecretReveal.Fly - 0.1 -- the jackpot until it would fly
local CARD = BOOM + SHOW + 0.35 -- the result card
local WIDE = CARD + 1.4 -- the wide shot: the light over the plot
local total = WIDE + 2.6

-- the player: rows across the clump, replayed as the video's clock runs
local _, full = Players.sweep(pattern, { Speed = 1.6 })
local sub = Players.sweep(pattern, { Speed = 1.6, Input = "Mouse" })
local samples = {}
for _, stroke in sub.Strokes do
	for i = 1, #stroke, 3 do
		table.insert(samples, { stroke[i], stroke[i + 1], stroke[i + 2] })
	end
	table.insert(samples, false) -- the spray let go
end
local tracker = Scoring.SprayTracker.new(pattern, "Mouse")
local cursor = 1
local cleanedAt: { [number]: number } = {}
local nozzle = V2.new(0, 0)
local function sprayTo(stopAt: number, videoT: number)
	while cursor <= #samples do
		local s = samples[cursor]
		if s == false then
			tracker:lift()
		elseif s[3] <= stopAt then
			local cleaned = tracker:add(s[1], s[2], s[3])
			for _, index in cleaned do
				cleanedAt[index] = videoT
			end
			nozzle = V2.new(s[1], s[2])
		else
			return
		end
		cursor += 1
	end
end
local sprayStart, sprayEnd = full.firstT, full.doneT

---------------------------------------------------------------- frame pieces

local function face(u: number, v: number, z: number): any
	return workCf:PointToWorldSpace(V3.new(u * OreShellBuilder.Scale, v * OreShellBuilder.Scale, z))
end

-- a ring of rainbow bars in the clump's face, `radius` studs out
local function faceRing(parent: any, radius: number, bars: number, width: number, transparency: number, spin: number)
	local chord = 2 * radius * math.sin(math.pi / bars)
	for k = 1, bars do
		local a = (k - 0.5) * math.pi * 2 / bars + spin
		local at = workCf:PointToWorldSpace(V3.new(math.cos(a) * radius, math.sin(a) * radius, 0.3))
		local tangent = workCf:VectorToWorldSpace(V3.new(-math.sin(a), math.cos(a), 0))
		Geo.block(
			parent,
			CF.lookAt(at, at + tangent, workCf.LookVector),
			V3.new(width, width, chord * 0.9),
			RAINBOW[(k - 1) % #RAINBOW + 1],
			NEON,
			{ CanCollide = false, CastShadow = false, Transparency = transparency }
		)
	end
end

-- light leaking out of the cleaned holes: rays from the ore outwards, rainbow (white-hot at the end)
local leakCells = {}
for _, cell in pattern.Cells do
	if cell.Index % 4 == 1 then
		table.insert(leakCells, cell)
	end
end
local function leaks(parent: any, t: number, progress: number, hot: number, beat: number)
	local shown = 0
	for k, cell in leakCells do
		local at = cleanedAt[cell.Index]
		if at and t >= at then
			shown += 1
			local grow = math.min((t - at) / 0.25, 1)
			local dir = workCf:VectorToWorldSpace(V3.new(cell.Center.X, cell.Center.Y, 0.55).Unit)
			local from = face(cell.Center.X, cell.Center.Y, OreShellBuilder.CoreFront)
			local length = (0.7 + 1.5 * progress + 0.4 * hot + 0.6 * beat) * grow
			local flick = ((math.floor(t * 14) + k * 3) % 5) / 10
			local color = RAINBOW[(k - 1) % #RAINBOW + 1]
			Geo.block(
				parent,
				CF.lookAt(from + dir * length / 2, from + dir * length),
				V3.new(0.06 + 0.03 * hot, 0.06 + 0.03 * hot, length),
				color,
				NEON,
				{ CanCollide = false, CastShadow = false, Transparency = 0.15 + flick * (1 - hot) }
			)
		end
	end
	return shown
end

-- the column of rainbow light over the station (everyone near sees it)
local function pillar(parent: any, st: number, life: number, close: boolean)
	local up = math.min(st / 0.25, 1)
	local fade = math.clamp((st - (life - 0.8)) / 0.8, 0, 1)
	local height = 120 * up
	local base = V3.new(center.X, stationCf.Position.Y + 3.4, center.Z)
	for k, color in RAINBOW do
		local a = k * math.pi / 3 + st * 1.6
		local at = base + V3.new(math.cos(a) * 1.3, height / 2, math.sin(a) * 1.3)
		Geo.block(parent, CF.new(at), V3.new(0.7, height, 0.7), color, NEON, {
			CanCollide = false,
			CastShadow = false,
			Transparency = if close then 0.6 else 0.25 + 0.75 * fade,
		})
	end
	-- (the white core only from afar: next to the camera it would cover the ore)
	if not close then
		Geo.block(parent, CF.new(base + V3.new(0, height / 2, 0)), V3.new(1.4, height, 1.4), WHITE, NEON, {
			CanCollide = false,
			CastShadow = false,
			Transparency = 0.15 + 0.85 * fade,
		})
	end
	-- rings climbing the column
	for k = 1, 3 do
		local u = (st * 0.7 + k / 3) % 1
		local y = base.Y + 4 + u * 50
		local r = 2.6 + 1.5 * math.sin(u * math.pi)
		for j = 1, 12 do
			local a = j * math.pi / 6 + st
			local at = V3.new(base.X + math.cos(a) * r, y, base.Z + math.sin(a) * r)
			local tangent = V3.new(-math.sin(a), 0, math.cos(a))
			Geo.block(parent, CF.lookAt(at, at + tangent), V3.new(0.25, 0.25, r * 0.5), RAINBOW[(j + k) % #RAINBOW + 1], NEON, {
				CanCollide = false,
				CastShadow = false,
				Transparency = math.max(fade, u * 0.8),
			})
		end
	end
end

---------------------------------------------------------------- captions

local function captionFor(t: number): string
	if t < 1.8 then
		return "Čistíš třpytivou rudu... zpod špíny prosvítá duhové světlo"
	elseif t < SPRAY then
		return "Čím míň špíny, tím víc to svítí a třese se"
	elseif t < BOOM then
		return "Poslední kousek: všechno ztichne, tři údery srdce..."
	elseif t < BOOM + 0.9 then
		return "BUM! Tlaková vlna, záblesk, sloup světla do nebe"
	elseif t < CARD then
		return `SECRET! {ore.Name}, {chanceText}, NEW!`
	elseif t < WIDE then
		return "Ruda je čistá: Flawless, jde rovnou do batohu"
	end
	return "Sloup světla vidí všichni kolem a celý server to vidí v chatu"
end

local function soundFor(t: number): string
	if t < SPRAY then
		return if t > 1.8 then "zvuk: šplouchání + cinkání + srdce, zrychluje" else "zvuk: šplouchání + cinkání třpytek"
	elseif t < BOOM then
		return "zvuk: buch... buch... BUCH + stoupající tón"
	elseif t < BOOM + 0.9 then
		return "zvuk: hluboké BUM + sbor „ááá“ + třpyt"
	elseif t < CARD then
		return "zvuk: jackpot fanfára"
	elseif t < WIDE then
		return "zvuk: pop"
	end
	return ""
end

---------------------------------------------------------------- frames

local function frameCam(t: number): (any, any, number)
	local look = camCf.LookVector
	local pos = camCf.Position
	local fov = camFov
	if t >= WIDE then
		-- the wide shot: the plot, the station and the light over it
		local station = stationCf.Position
		local u = math.clamp((t - WIDE) / 2.6, 0, 1)
		local from = station + V3.new(-26 + 6 * u, 14 + 3 * u, 30 - 4 * u)
		return from, station + V3.new(0, 16, 0), 60
	end
	-- the push in while it holds, the kick back at the BOOM, the shake after
	local push = 0
	if t >= SPRAY and t < BOOM then
		local u = (t - SPRAY) / HOLD
		push = 1.1 * (1 - (1 - u) ^ 2)
	elseif t >= BOOM then
		local u = math.clamp((t - BOOM) / 0.35, 0, 1)
		push = 1.1 - 2.0 * (1 - (1 - u) ^ 3)
	end
	pos = pos + look * push
	local trauma = if t >= BOOM then SecretReveal.shake(t - BOOM, secret.Stars) else 0
	if t >= 2.2 and t < BOOM then
		trauma = math.max(trauma, 0.12 * (t - 2.2) / (BOOM - 2.2))
	end
	if trauma > 0 then
		local r = Rng.new(math.floor(t * fps) + 7)
		pos = pos + V3.new(r:range(-1, 1), r:range(-1, 1), r:range(-1, 1)) * trauma * 0.35
	end
	return pos, pos + look * 10, fov
end

local frames = math.floor(total * fps)
local shots = {}
local rng = Rng.new(11)
local seeds = {}
for k = 1, 60 do
	seeds[k] = { rng:range(-1, 1), rng:range(-1, 1), rng:range(0.2, 1), rng:range(0, 6) }
end
for i = 0, frames - 1 do
	local t = i / fps
	local extra = Instance.new("Model")
	local guis = {}

	-- the spray (the tracker's clock runs with the video's until the last bit)
	local sprayU = math.clamp(t / SPRAY, 0, 1)
	sprayTo(sprayStart + (sprayEnd - sprayStart) * (sprayU ^ 0.9) - (if t < SPRAY then 0.05 else 0), t)
	local progress = tracker:progress()
	local hot = if t >= SPRAY then math.clamp((t - SPRAY) / HOLD, 0, 1) else 0
	local beat = 0
	for _, at in THUMPS do
		local u = (t - at) / 0.22
		if u > 0 and u < 1 then
			beat = math.max(beat, math.sin(u * math.pi))
		end
	end

	if t < BOOM then
		-- the clump: dirt left as it is now, shaking more the cleaner it gets
		local shell = OreShellBuilder.build(pattern, workCf, extra)
		for index, block in shell.Dirt do
			local left = tracker:left(index)
			if tracker.cleaned[index] then
				block:Destroy()
			elseif left < 1 then
				SprayParts.thin(block, left)
			end
			if not tracker.cleaned[index] and hot > 0 then
				-- the last dirt glows from inside
				block.Color = block.Color:Lerp(C3.fromRGB(255, 190, 120), hot * 0.5)
			end
		end
		-- the ore's moving parts are alive under the dirt
		local treasure = shell.Treasure
		local tc = treasure:GetAttribute("Center")
		if tc then
			local pivot = CF.new(tc)
			SecretOreFx.pose(SecretOreFx.rig(treasure, pivot), pivot, t)
		end
		local shake = (0.015 + 0.05 * progress + 0.07 * hot + 0.05 * beat) * (if progress > 0.05 then 1 else 0)
		if shake > 0 then
			local r = Rng.new(i + 1)
			local offset = workCf:VectorToWorldSpace(V3.new(r:range(-1, 1), r:range(-1, 1), 0)) * shake
			local s = 1 + 0.05 * beat
			for _, d in shell.Model:GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					d.CFrame = CF.new(center + (p - center) * s + offset) * d.CFrame.Rotation
					d.Size = d.Size * s
				end
			end
		end
		leaks(extra, t, progress, hot, beat)
		-- a ring off the clump on every heartbeat
		for k, at in THUMPS do
			local u = (t - at) / 0.5
			if u > 0 and u < 1 then
				faceRing(extra, 1.6 + 3.2 * u, 16, 0.09, u, k)
			end
		end
		-- the wand and its jet while spraying
		if t < SPRAY - 0.05 then
			local hit = workCf:PointToWorldSpace(
				V3.new(nozzle.X * OreShellBuilder.Scale, nozzle.Y * OreShellBuilder.Scale, OreShellBuilder.DirtFront)
			)
			local wand = SprayParts.wand(extra)
			local wandCf, tip = SprayParts.wandFrame(workCf, hit, true)
			SprayParts.placeWand(wand, wandCf)
			SprayParts.placeJet(SprayParts.jet(extra), tip, hit)
			SprayParts.placeSpot(SprayParts.spot(extra), workCf, hit, tracker.radius * OreShellBuilder.Scale)
		end
		-- rainbow sparkles pop out of every hole as it opens
		for index, at in cleanedAt do
			local dt = t - at
			if dt >= 0 and dt < 0.45 and index % 2 == 0 then
				local cell = pattern.Cells[index]
				local from = face(cell.Center.X, cell.Center.Y, OreShellBuilder.DirtFront)
				for k = 1, 3 do
					local sd = seeds[(index * 3 + k) % #seeds + 1]
					local v = workCf:VectorToWorldSpace(V3.new(sd[1] * 3, sd[2] * 3 + 2, sd[3] * 4))
					local p = from + v * dt - V3.new(0, 9 * dt * dt, 0)
					Geo.ball(extra, p, 0.12 * (1 - dt / 0.45) + 0.03, RAINBOW[(index + k) % #RAINBOW + 1], NEON, { CanCollide = false })
				end
			end
		end
		-- the cleaning screen (the dirt % and the quality meter)
		view.Gui.Enabled = true
		view.Instruction.Text = if progress > 0.15
			then "Something is glowing inside..."
			else "Wash the dirt off. Don't blast the glowing crystals!"
		CleaningView.setClean(view, progress)
		CleaningView.setMeter(view, tracker:parts(sprayEnd).Score)
		view.Hint.Text = if t < SPRAY then "Hold the left mouse button to spray" else ""
		table.insert(guis, view.Gui)
	else
		local bt = t - BOOM
		-- BOOM: the rest of the dirt and the clump fly off
		if bt < 1.4 then
			local shell = OreShellBuilder.build(pattern, workCf, extra)
			shell.Treasure:Destroy()
			for _, d in shell.Model:GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					local out = workCf:VectorToObjectSpace(p - center)
					local dir = workCf:VectorToWorldSpace(V3.new(out.X, out.Y, 0.8).Unit)
					local k = (#d.Name + math.floor(p.X * 13)) % 7
					local v = dir * (10 + k * 1.5) + V3.new(0, 6, 0)
					local q = p + v * bt - V3.new(0, 30 * bt * bt, 0)
					d.CFrame = CF.new(q) * d.CFrame.Rotation * CF.Angles(bt * (3 + k), bt * 4, bt * 2)
				end
			end
		end
		if bt < 0.6 then
			faceRing(extra, 1.2 + 9 * (1 - (1 - bt / 0.6) ^ 3), 24, 0.16 * (1 - bt / 0.6) + 0.04, bt / 0.6, 0)
		end
		pillar(extra, bt, total - BOOM + 0.8, t < WIDE)
		-- after the jackpot: the clean ore stands on the station again, the card under it
		if t >= CARD - 0.2 then
			local item = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder").display(
				{ K = "Clean", O = SECRET, G = SecretOreConfig.Grade },
				workCf * CF.new(0, -0.9, 0.2) * CF.Angles(0, math.pi + 0.3, 0),
				SECRET
			)
			local pivot = CF.new(item:GetAttribute("Center"))
			SecretOreFx.pose(SecretOreFx.rig(item, pivot), pivot, t)
			item.Parent = extra
		end
		if t >= CARD and t < WIDE then
			view.Gui.Enabled = true
			CleaningView.setReveal(view, "A SECRET ore!")
			view.Leave.Parent.Visible = false
			view.CardGrade.Text = "FLAWLESS"
			view.CardGrade.TextColor3 = ItemData.GradeById.Flawless.Color
			view.CardStars.Text = "★★★★"
			view.CardOre.Text = ore.Name .. "  (Secret)"
			view.CardOre.TextColor3 = C3.fromRGB(255, 120, 230)
			view.CardValue.Text = "Earns " .. Format.perSecond(ore.Income) .. " on a podium"
			view.CardDetail.Text = chanceText .. "  ·  " .. floorName
			view.Card.Visible = true
			view.CleanBar.Visible = false
			CardLook.glowCard(view, C3.fromRGB(255, 120, 230))
			table.insert(guis, view.Gui)
		end
		SecretReveal.pose(reveal, bt, { Screen = V2.new(W, H), Scale = 1.25, Target = nil, Reduced = false })
		table.insert(guis, reveal.Gui)
		if t >= WIDE then
			table.insert(guis, hud.Gui)
			table.insert(guis, juice.Gui)
			local bump = juice.Bumps[1]
			bump.Plus.Label.Text = "+1"
			local holder = hud.CarryPanel
			local size = V2.new(holder.Size.X.Offset, holder.Size.Y.Offset) * 1.25
			local at = V2.new(W / 2 + holder.Position.X.Offset * 1.25, (H - INSET) + holder.Position.Y.Offset * 1.25)
				- V2.new(holder.AnchorPoint.X, holder.AnchorPoint.Y) * size
			BagFly.poseBump(bump, at + size / 2, size, t - WIDE, 1.25, false, true, t - WIDE)
			HudView.setBackpack(hud, 15, 60)
		end
	end
	local said = t >= BOOM + 0.4
	secretLine.Text = if said then `[SECRET] Kuba found {ore.Name}!` else ""
	secretLine2.Text = if said then `    ({chanceText}, {floorName})` else ""
	table.insert(guis, chat)
	captionText.Text = captionFor(t)
	soundTag.Text = soundFor(t)
	table.insert(guis, caption)

	local name = string.format("%04d", i)
	fs.writeFile(root .. "/build/preview/" .. tag .. "/fx_" .. name .. ".json", serde.encode("json", Export.collect(extra)))
	fs.writeFile(root .. "/build/preview/" .. tag .. "/ui_" .. name .. ".json", serde.encode("json", UiExport.export(guis)))
	local pos, target, fov = frameCam(t)
	shots[tag .. "_" .. name] = {
		scene = tag .. "_base",
		extra = tag .. "/fx_" .. name,
		ui = tag .. "/ui_" .. name,
		width = W,
		height = H,
		uiInset = INSET,
		position = { camPos.X, camPos.Y, camPos.Z },
		target = { center.X, center.Y, center.Z },
		fov = camFov,
		cam = { position = { pos.X, pos.Y, pos.Z }, target = { target.X, target.Y, target.Z }, fov = fov },
		preset = "Workbench",
		shadowExtent = 60,
		maxLights = 24,
	}
	if i % 40 == 0 then
		print(`frame {i}/{frames}`)
	end
end
fs.writeFile(root .. "/build/preview/" .. tag .. "_shots.json", serde.encode("json", shots))

local function frameAt(seconds: number): number
	return math.clamp(math.floor(seconds * fps + 0.5), 0, frames - 1)
end
local board = {
	title = "TAJNÁ RUDA (SECRET) při čištění: " .. ore.Name,
	fps = fps,
	cells = {
		{ frame = frameAt(1.2), caption = "1 Třpytivá ruda: zpod špíny prosvítá duhové světlo" },
		{ frame = frameAt(SPRAY - 0.4), caption = "2 Míň špíny = víc světla, ruda se třese" },
		{ frame = frameAt(THUMPS[3] + 0.08), caption = "3 Poslední kousek: srdce buch, kamera najíždí" },
		{ frame = frameAt(BOOM + 0.08), caption = "4 BUM! Záblesk a tlaková vlna" },
		{ frame = frameAt(BOOM + 0.75), caption = "5 SECRET! Ruda se točí a hýbe" },
		{ frame = frameAt(BOOM + SHOW - 0.8), caption = `6 Jméno, ★ podle vzácnosti, {chanceText}, NEW!` },
		{ frame = frameAt(CARD + 0.5), caption = "7 Flawless, rovnou do batohu" },
		{ frame = frameAt(WIDE + 1.6), caption = "8 Sloup světla vidí všichni, zpráva v chatu" },
	},
}
fs.writeFile(root .. "/build/preview/" .. tag .. "_board.json", serde.encode("json", board))
print(`{frames} frames at {fps} fps ({total} s)`)
