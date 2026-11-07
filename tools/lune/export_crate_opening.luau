--[[
	Preview frames of the IN-GAME crate opening (Builders/CrateOpeningStage,
	the code VaultController plays): the stage posed at chosen times, each as
	its own scene, with the cinematic's own camera.

	  lune run tools/lune/export_crate_opening.luau [level] [t1,t2,...]   (default: 10, a set of key moments)
	-> build/preview/crate_open_<level>_<i>.json + build/preview/crate_open_shots.json
	  SHOTS_EXTRA=build/preview/crate_open_shots.json node tools/preview/render.mjs crate_open_10_1 crate_open_10_1
	(tools/preview/render_crate_opening.sh renders them all)

	  lune run tools/lune/export_crate_opening.luau reel [level] [fps=60] [calm]   the whole opening as a video,
	      waiting a moment at the reveal as if AWESOME! was pressed then (calm: with Reduce motion, voidcrate_<level>_calm):
	-> build/preview/voidcrate_<level>_base.json, voidcrate_<level>/fx_NNNN.json + ui_NNNN.json,
	   voidcrate_<level>_shots.json, voidcrate_<level>_board.json
	then: node tools/preview/render_reel.mjs voidcrate_<level> 60 9000000

	  lune run tools/lune/export_crate_opening.luau tiers   crates in the blasters' colours side by side
	-> build/preview/crate_tiers.json + crate_tiers_shots.json
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

local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.CrateOpeningStage")
local CrateOpeningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CrateOpeningView")
local CF = Loader.CFrame

local mode = process.args[1]
local level = tonumber(if mode == "reel" then process.args[2] else mode) or 10
local times = {}
for t in string.gmatch((mode ~= "reel" and process.args[2]) or "0.25,0.8,1.1,1.8,2.6,3.0,3.6,4.2,4.8,5.8,6.3,7", "[^,]+") do
	table.insert(times, tonumber(t))
end

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

local ORIGIN = CF.new(0, 3000, 0)
local ore = BlasterData.vaultOre(level)
local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")

if mode == "tiers" then
	-- crates in a row on their platforms, each in the colour of the blaster inside
	local CaseBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.CaseBuilder")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local V3, C3 = roblox.Vector3, roblox.Color3
	local stage = roblox.Instance.new("Model")
	stage.Name = "Tiers"
	stage.Parent = workspace
	local neon = roblox.Enum.Material.Neon
	Geo.block(stage, CF.new(28, -0.6, 0), V3.new(140, 1, 70), C3.fromRGB(12, 6, 26), neon)
	Geo.block(stage, CF.new(28, 15, -14), V3.new(140, 32, 1), C3.fromRGB(18, 8, 40), neon)
	for i, pick in { 2, 5, 6, 8, 10 } do
		local x = (i - 1) * 14
		local model = roblox.Instance.new("Model")
		model.Parent = stage
		-- turned so the core on the front (+X) looks at the camera
		local at = CF.new(x, 0.3, 0) * CF.Angles(0, -math.pi / 2 + 0.28, 0)
		local case = CaseBuilder.build(
			model,
			at,
			pick,
			Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder").colors(pick, BlasterData.vaultOre(pick)).Color
		)
		Geo.block(stage, CF.new(x, 0.15, 0), V3.new(9.6, 0.3, 7.6), C3.fromRGB(26, 24, 36))
		for k = 1, 12 do
			local a = math.rad(k * 30)
			Geo.block(
				stage,
				CF.new(x + math.cos(a) * 4.5, 0.34, math.sin(a) * 3.5) * CF.Angles(0, -a, 0),
				V3.new(1.3, 0.1, 0.18),
				case.Glow,
				neon
			)
		end
		local lamp = Geo.block(stage, CF.new(x, 6, 6), V3.new(0.1, 0.1, 0.1), case.Glow, nil, { Transparency = 1 })
		local light = roblox.Instance.new("PointLight")
		light.Color = case.Glow:Lerp(C3.new(1, 1, 1), 0.5)
		light.Range = 20
		light.Brightness = 3
		light.Parent = lamp
	end
	local scene = Export.collect(workspace)
	scene.presets = presetsJson()
	fs.writeDir(root .. "/build/preview")
	fs.writeFile(root .. "/build/preview/crate_tiers.json", serde.encode("json", scene))
	fs.writeFile(
		root .. "/build/preview/crate_tiers_shots.json",
		serde.encode("json", {
			crate_tiers = {
				scene = "crate_tiers",
				position = { 28, 12, 76 },
				target = { 28, 2.2, 0 },
				fov = 28,
				preset = "CrateOpening",
				maxLights = 6,
				shadowExtent = 60,
			},
		})
	)
	print(`crate_tiers: {#scene.parts} parts`)
	process.exit(0)
end

local calm = mode == "reel" and process.args[4] == "calm"
local stage = Stage.build(workspace, ORIGIN, level, ore, Stage.blasterModel(level, ore), calm)
-- the overlay ("NEW BLASTER!", the flash, AWESOME!) at the render's 1.25 UI scale
local view = CrateOpeningView.build()
view.Gui.Scale.Scale = 1.25
CrateOpeningView.fit(view, 1280, 720)
CrateOpeningView.setBlaster(view, level, ore)
view.Calm = calm

fs.writeDir(root .. "/build/preview")

if mode == "reel" then
	local fps = tonumber(process.args[3]) or 60
	local tag = "voidcrate_" .. level .. (if calm then "_calm" else "")
	local WAIT = 1.2 -- how long the reveal waits for AWESOME! here
	local W, H = 1600, 900
	-- the room never moves: the base scene; everything else per frame
	local room = stage.Root:FindFirstChild("Room")
	local base = Export.collect(room)
	base.presets = presetsJson()
	fs.writeFile(root .. "/build/preview/" .. tag .. "_base.json", serde.encode("json", base))
	room.Parent = nil
	fs.writeDir(root .. "/build/preview/" .. tag)
	local shots = {}
	local total = Stage.Duration + WAIT
	local frames = math.floor(total * fps)
	for i = 0, frames - 1 do
		local real = i / fps
		local t = if real < Stage.T_HOLD then real elseif real < Stage.T_HOLD + WAIT then Stage.T_HOLD else real - WAIT
		local idle = math.clamp(real - Stage.T_HOLD, 0, WAIT)
		stage.update(t, idle)
		local cam, fov = stage.camera(t, idle)
		local scene = Export.collect(stage.Root)
		-- (the parts parked below the world are not drawn)
		local shown = {}
		for _, entry in scene.parts do
			if entry[5][2] > -1000 then
				table.insert(shown, entry)
			end
		end
		scene.parts = shown
		CrateOpeningView.update(view, t, stage.Burst, stage.Reveal)
		local name = string.format("%04d", i)
		fs.writeFile(root .. "/build/preview/" .. tag .. "/fx_" .. name .. ".json", serde.encode("json", scene))
		fs.writeFile(root .. "/build/preview/" .. tag .. "/ui_" .. name .. ".json", serde.encode("json", UiExport.export({ view.Gui })))
		local p, look = cam.Position, cam.Position + cam.LookVector * 20
		shots[tag .. "_" .. name] = {
			scene = tag .. "_base",
			extra = tag .. "/fx_" .. name,
			ui = tag .. "/ui_" .. name,
			width = W,
			height = H,
			position = { p.X, p.Y, p.Z },
			target = { look.X, look.Y, look.Z },
			cam = { position = { p.X, p.Y, p.Z }, target = { look.X, look.Y, look.Z }, fov = fov },
			fov = fov,
			preset = "CrateOpening",
			maxLights = 4,
			shadowExtent = 60,
		}
	end
	fs.writeFile(root .. "/build/preview/" .. tag .. "_shots.json", serde.encode("json", shots))
	local function frameAt(t: number): number
		return math.floor((if t > Stage.T_HOLD then t + WAIT else t) * fps)
	end
	local cells = {}
	for k, cell in
		{
			{ 0.85, "Portál se otevře, bedna letí dolů" },
			{ 1.85, "Kamera obíhá, bedna se vznáší" },
			{ 2.65, "Nabíjení: paprsky, malé portály" },
			{ 2.95, "Výbuch: víko letí nahoru, paprsek" },
			{ 4.12, "Záblesk: kamera letí těsně k blasteru" },
			{ 4.5, "NEW BLASTER! a dávka střel" },
			{ 5.0, "Blaster se pomalu otáčí, kotouč se točí" },
			{ 6.0, "Blaster vlevo, nápisy přilétají" },
			{ 6.3, "Čeká na AWESOME! jako secret ruda" },
			{ 7.0, "COLLECTED! Blaster letí do inventáře" },
		}
	do
		cells[k] = { frame = frameAt(cell[1]), caption = cell[2] }
	end
	fs.writeFile(
		root .. "/build/preview/" .. tag .. "_board.json",
		serde.encode("json", { title = "OTEVÍRÁNÍ VOID BEDNY (6. 11.)", fps = fps, cells = cells })
	)
	print(`{tag}: {frames} frames at {fps} fps`)
	process.exit(0)
end

local shotsPath = root .. "/build/preview/crate_open_shots.json"
local shots = if fs.isFile(shotsPath) then serde.decode("json", fs.readFile(shotsPath)) else {}
local presets = presetsJson()
for i, t in times do
	stage.update(t)
	local cam, fov = stage.camera(t)
	local scene = Export.collect(workspace)
	scene.presets = presets
	local name = string.format("crate_open_%d_%d", level, i)
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", scene))
	CrateOpeningView.update(view, t, stage.Burst, stage.Reveal)
	fs.writeFile(root .. "/build/preview/ui_" .. name .. ".json", serde.encode("json", UiExport.export({ view.Gui })))
	local p, look = cam.Position, cam.Position + cam.LookVector * 20
	shots[name] = {
		scene = name,
		position = { p.X, p.Y, p.Z },
		target = { look.X, look.Y, look.Z },
		fov = fov,
		preset = "CrateOpening",
		maxLights = 4,
		ui = "ui_" .. name,
	}
	print(string.format("Exported %s (t = %.2f): %d parts, %d lights", name, t, #scene.parts, #scene.lights))
end
fs.writeFile(shotsPath, serde.encode("json", shots, true))
