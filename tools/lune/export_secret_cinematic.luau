--[[
	Video frames of the SECRET ore cinematic (owner 2026-10-30), posed with the game's code
	(Effects/SecretCinematic, the same pose the client plays every frame): the cleaning
	close-up at the Cleaning Station on plot 1 behind it (the clean ore on the station,
	the world blurred: the viewer's DoF stands in for the client's BlurEffect), then the
	whole show: discovery, charging, the burst, the reveal, CONTINUE pressed at PRESS
	seconds, the ore flying into the bag. A caption (preview only, Czech) names the phase
	and the sounds.

	  lune run tools/lune/export_secret_cinematic.luau [fps=20] [ore=HollowEye] [tag=secretcine] [screen=desktop|phone] [reduced]
	-> build/preview/<tag>_base.json, build/preview/<tag>/fx_NNNN.json + ui_NNNN.json,
	   build/preview/<tag>_shots.json (a camera per frame), build/preview/<tag>_board.json
	then: node tools/preview/render_reel.mjs <tag>   (or with stills=i,j,... for single frames)
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
local tag = process.args[3] or "secretcine"
local phone = process.args[4] == "phone"
local reduced = process.args[5] == "reduced"
local CF = Loader.CFrame
local V3 = roblox.Vector3
local V2 = roblox.Vector2
local C3 = roblox.Color3
local Instance = roblox.Instance
local WHITE = C3.new(1, 1, 1)
local W, H, INSET = 1600, 900, 36
if phone then
	W, H, INSET = 812, 375, 58
end

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")
local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
local SecretOreFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreFx")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
local CleaningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CleaningView")
local CameraFit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CameraFit")
local SecretCinematic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.SecretCinematic")
local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.SecretRevealController")
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")

local secret = SecretOreConfig.ByOre[SECRET]
assert(secret, "not a secret ore: " .. SECRET)
local ore = OreData.get(SECRET)
local tm = SecretCinematic.Timing
local PRESS = 8.6 -- the player presses CONTINUE here

---------------------------------------------------------------- the world + the station

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
WorldBuilder.build(workspace)
local plot = WorldLayout.Plots[1]
local plotCf = WorldLayout.plotCFrame(plot)
local stationCf
local kitShiftX, kitShiftZ = (GameConfig.PlotCells - 12) / 2, GameConfig.PlotCells - 12
local layoutList = { { Id = "CleaningStation", X = 4 + kitShiftX, Z = 4 + kitShiftZ, R = 0 } }
for _, entry in MachineData.StarterKit do
	table.insert(layoutList, entry)
end
for _, entry in layoutList do
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

local camCf, camFov = CameraFit.compute({
	ViewportHeight = H,
	InsetTop = INSET,
	FreeTop = CleaningView.BannerBottom,
	FreeBottom = CleaningView.BottomReserved,
	UiScale = if phone then 0.62 else 1.25,
	Outline = pattern.Outline,
	FaceScale = OreShellBuilder.Scale,
	CamPoint = CF.lookAt(camPos, center + V3.new(0, 0.1, 0)),
	OrePoint = center,
})

---------------------------------------------------------------- the UI

local view = SecretCinematic.build()
SecretCinematic.setOre(view, SECRET)
SecretCinematic.setInfo(view, {
	Name = ore.Name,
	Stars = secret.Stars,
	Chance = SecretOreConfig.chanceText(secret.OneIn),
	Value = Format.money(Controller.valueOf(SECRET, nil)),
	New = true,
})
view.Port:SetAttribute("PreviewLive", true)
local target = Controller.flyTo("Backpack", V2.new(W, H), nil)

local caption = Instance.new("ScreenGui")
caption.Name = "Caption"
caption.IgnoreGuiInset = false
caption.DisplayOrder = 100
local box = UIKit.new("Frame", {
	Name = "Box",
	AnchorPoint = V2.new(1, 0),
	Position = roblox.UDim2.new(1, -14, 0, 10),
	Size = roblox.UDim2.fromOffset(470, 74),
	BackgroundColor3 = C3.fromRGB(20, 22, 30),
	BackgroundTransparency = 0.3,
}, caption)
UIKit.corner(box, 14)
local captionText = UIKit.new("TextLabel", {
	Name = "Text",
	BackgroundTransparency = 1,
	Size = roblox.UDim2.new(1, -16, 1, 0),
	Position = roblox.UDim2.fromOffset(8, 0),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 21,
	TextWrapped = true,
	TextColor3 = WHITE,
	Text = "",
}, box)
local soundTag = UIKit.new("TextLabel", {
	Name = "Sound",
	AnchorPoint = V2.new(1, 0),
	BackgroundTransparency = 1,
	Position = roblox.UDim2.new(1, -14, 0, 88),
	Size = roblox.UDim2.fromOffset(470, 26),
	FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
	TextSize = 20,
	TextXAlignment = roblox.Enum.TextXAlignment.Right,
	TextColor3 = C3.fromRGB(255, 226, 150),
	Text = "",
}, caption)

local function captionFor(t: number): string
	if t < tm.Charge then
		return "1 Objev: svět ztmavne a rozmaže se, z tmy svítí jen tajemná ruda"
	elseif t < tm.Explosion then
		return "2 Nabíjení: prstence energie, krystaly se stopou, paprsky, světlo sílí"
	elseif t < tm.Reveal then
		return "3 Výbuch: jeden jemný záblesk, rázové vlny, jiskry, otřes"
	elseif t < tm.ContinueAt then
		return "4 S E C R E T: jméno, vzácnost, šance a hodnota"
	elseif t < PRESS then
		return "Ruda se dál točí, POKRAČOVAT (samo za " .. math.floor(tm.AutoContinue) .. " s)"
	end
	return "Pokračovat: ruda letí do batohu"
end

local SOUND_WORDS = {
	SecretMystery = "zvuk: tajemný hluboký tón",
	SecretRise = "zvuk: nabíjecí hukot sílí",
	SecretSparkle = "zvuk: cinkání krystalů",
	SecretThump = "zvuk: úder",
	SecretBoom = "zvuk: BUM! + zvonění",
	SecretChime = "zvuk: zvonění",
	SecretFanfare = "zvuk: fanfára",
}
local cues = SecretCinematic.cues(tm, secret.Stars)
local function soundFor(t: number): string
	local said = ""
	for _, cue in cues do
		if t >= cue.At and t < cue.At + 0.7 then
			said = SOUND_WORDS[cue.Sound] or said
		end
	end
	if said == "" and t >= tm.Charge and t < tm.Explosion then
		said = SOUND_WORDS.SecretRise
	end
	if t >= PRESS and t < PRESS + 0.4 then
		said = "zvuk: klik"
	end
	return said
end

---------------------------------------------------------------- frames

local function frameCam(t: number): (any, any, number)
	local look = camCf.LookVector
	local pos = camCf.Position
	-- CameraShake's kick at the burst (the trauma dies out fast)
	if not reduced and t >= tm.Explosion and t < tm.Explosion + 0.7 then
		local trauma = SecretCinematic.tierOf(secret.Stars).Shake * (1 - (t - tm.Explosion) / 0.7) ^ 2
		local r = Rng.new(math.floor(t * fps) + 7)
		pos = pos + V3.new(r:range(-1, 1), r:range(-1, 1), r:range(-1, 1)) * trauma * 0.35
	end
	return pos, pos + look * 10, camFov
end

local total = PRESS + tm.Close + 0.25
local frames = math.floor(total * fps)
local shots = {}
local display = ItemBuilder.display(
	{ K = "Clean", O = SECRET, G = SecretOreConfig.Grade },
	workCf * CF.new(0, -0.9, 0.2) * CF.Angles(0, math.pi + 0.3, 0),
	SECRET
)
local displayPivot = CF.new(display:GetAttribute("Center"))
local displayRig = SecretOreFx.rig(display, displayPivot)
for i = 0, frames - 1 do
	local t = i / fps
	local extra = Instance.new("Model")
	-- the clean ore on the station (the cleaning lifted it out), alive
	SecretOreFx.pose(displayRig, displayPivot, t, reduced)
	local copy = display:Clone()
	copy.Parent = extra
	SecretCinematic.pose(view, t, {
		Screen = V2.new(W, H),
		TopInset = INSET,
		Reduced = reduced,
		Phone = phone,
		Touch = phone,
		Input = if phone then "Touch" else "Mouse",
		FlashAt = tm.Explosion,
		ContinuedAt = if t >= PRESS then PRESS else nil,
		Target = target,
	})
	captionText.Text = captionFor(t)
	soundTag.Text = soundFor(t)
	local guis = { view.Gui }
	if not phone then
		table.insert(guis, caption)
	end
	local name = string.format("%04d", i)
	fs.writeFile(root .. "/build/preview/" .. tag .. "/fx_" .. name .. ".json", serde.encode("json", Export.collect(extra)))
	fs.writeFile(root .. "/build/preview/" .. tag .. "/ui_" .. name .. ".json", serde.encode("json", UiExport.export(guis)))
	local pos, lookAt, fov = frameCam(t)
	-- (the shot's target sits just in front of the camera: the viewer's DoF focuses there, so the
	-- whole world behind is soft like the client's BlurEffect)
	local near = camCf.Position + camCf.LookVector * 0.6
	shots[tag .. "_" .. name] = {
		scene = tag .. "_base",
		extra = tag .. "/fx_" .. name,
		ui = tag .. "/ui_" .. name,
		width = W,
		height = H,
		uiInset = INSET,
		position = { camCf.Position.X, camCf.Position.Y, camCf.Position.Z },
		target = { near.X, near.Y, near.Z },
		fov = camFov,
		cam = { position = { pos.X, pos.Y, pos.Z }, target = { lookAt.X, lookAt.Y, lookAt.Z }, fov = fov },
		preset = "Workbench",
		shadowExtent = 60,
		maxLights = 24,
		dof = { aperture = 0.03, maxblur = 0.012 },
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
	title = "TAJNÁ RUDA: filmové odhalení (" .. ore.Name .. ")",
	fps = fps,
	cells = {
		{ frame = frameAt(1.0), caption = "1 Objev: tma, rozmazaný svět, ruda svítí ze tmy" },
		{ frame = frameAt(3.0), caption = "2 Nabíjení: prstence, krystaly, paprsky" },
		{ frame = frameAt(tm.Explosion + 0.12), caption = "3 Výbuch: záblesk, vlny, jiskry, otřes" },
		{ frame = frameAt(tm.Reveal + 0.5), caption = "4 S E C R E T padá písmeno po písmenu" },
		{ frame = frameAt(7.4), caption = "5 Jméno, vzácnost, šance, hodnota, POKRAČOVAT" },
		{ frame = frameAt(PRESS + 0.4), caption = "6 Pokračovat: ruda letí do batohu" },
	},
}
fs.writeFile(root .. "/build/preview/" .. tag .. "_board.json", serde.encode("json", board))
print(`{frames} frames at {fps} fps ({total} s)`)
