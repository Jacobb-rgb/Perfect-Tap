--[[
	Pictures and video frames of the elevator's travel cinematic (owner
	2026-11-15), posed with the game's own code: Builders/ElevatorCabinStage
	(the cabin, the shaft, the camera), Builders/ElevatorArrivalFx (the mines'
	arrivals) and UI/ElevatorTravelView (the words), on the real mine floors
	(their stops are MineKit.elevator; the real cage under the cabin is left out
	of the base scene and drawn per frame while it shows, as the client hides
	it with LocalTransparencyModifier). A blocky stand-in plays the player.

	  lune run tools/lune/export_elevator_travel.luau reel [from=1] [to=4] [fps=20] [reduced]
	    -> build/preview/elevtravel_base.json, build/preview/elevtravel/fx_NNNN.json + ui_NNNN.json,
	       three reels with their own lighting (the preview draws one preset a reel):
	       elevtravel_a (the stop: the floor's preset), elevtravel_b (in the cabin: ElevatorRide),
	       elevtravel_c (the arrival: the target floor's preset), plus elevtravel_shots.json and
	       elevtravel_board.json for the storyboard; tools/preview/elevator_travel_reel.sh renders,
	       joins and encodes them
	  lune run tools/lune/export_elevator_travel.luau arrivals
	    -> one still a mine (elevarrive_<Id>): the doors open on its floor with its effects
	  lune run tools/lune/export_elevator_travel.luau phone [from=1] [to=4]
	    -> elevphone_*: the words at key moments on a 812 x 375 phone
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

local mode = process.args[1] or "reel"
local FROM = tonumber(process.args[2]) or 1
local TO = tonumber(process.args[3]) or 4
local fps = tonumber(process.args[4]) or 20
local reduced = process.args[5] == "reduced"
local CF = Loader.CFrame
local V3 = roblox.Vector3
local V2 = roblox.Vector2
local C3 = roblox.Color3
local Instance = roblox.Instance
local WHITE = C3.new(1, 1, 1)

local Config = Loader.requirePath("ReplicatedStorage.Shared.Config.ElevatorTravelConfig")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.ElevatorCabinStage")
local Fx = Loader.requirePath("ReplicatedStorage.Shared.Builders.ElevatorArrivalFx")
local View = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ElevatorTravelView")
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
local MineFloorScene = require("./lib/mine_floor_scene")
local Dummy = require("./lib/dummy")

local OUT = root .. "/build/preview/"
fs.writeDir(OUT)
local ARRIVAL_OFFSET = CF.new(0, 3.6, -3.9) -- ElevatorService.ArrivalOffset

---------------------------------------------------------------- the world

local function presetsJson(): any
	local out = {}
	for name, preset in LightingConfig.Presets do
		local o = {}
		for group, values in preset do
			o[group] = {}
			for key, value in values do
				o[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
			end
		end
		out[name] = o
	end
	return out
end

-- A floor at its place in the world, with rocks on its spawns (the game spawns them at run time).
local function buildFloor(parent: any, index: number): any
	local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. MineFloorScene.Modules[index])
	local floor = MineFloors.get(index)
	local model = Floor.build(parent, MineFloors.Placement[index], { Cutaway = false })
	local spawns = model:FindFirstChild("RockSpawns")
	if spawns then
		for i, p in spawns:GetChildren() do
			local rng = Rng.new(index * 1000 + i)
			local roll = rng:next()
			local kind = if roll < 0.15 then "Crystal" elseif roll < 0.45 then "Big" else "Small"
			local weights = if kind == "Crystal" then floor.CrystalOres else floor.Ores
			local ores = {}
			for _ = 1, MineFloors.OreCount[kind] do
				table.insert(ores, rng:weighted(weights))
			end
			local pos = p.CFrame.Position
			RockBuilder.build(floor.Id, kind, ores, CF.new(pos.X, pos.Y, pos.Z), index * 77 + i).Parent = model
		end
		spawns:Destroy()
	end
	return model
end

local function stopOf(model: any, index: number): any
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and d.Name == "Elevator" and d:GetAttribute("Floor") == index then
			return d
		end
	end
	error("no elevator stop on floor " .. index)
end

local function stopCFrame(stop: any): any
	local base = stop:FindFirstChild("Base")
	return base.CFrame * CF.new(0, -base.Size.Y / 2, 0)
end

local function arrivalCFrame(at: any): any
	local pos = (at * ARRIVAL_OFFSET).Position
	local look = at.LookVector
	return CF.lookAt(pos, pos + V3.new(look.X, 0, look.Z).Unit)
end

-- Takes the real cage parts (under the cabin) out of the world; they are drawn per frame while they show.
local function takeCage(stop: any, at: any): { any }
	local box = Stage.HideBox
	local taken = {}
	for _, d in stop:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = at:ToObjectSpace(d.CFrame)
			local half = d.Size / 2
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z
			local ey = math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z
			local ez = math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
			local p = cf.Position
			if
				p.X + ex > box.Min.X
				and p.X - ex < box.Max.X
				and p.Y + ey > box.Min.Y
				and p.Y - ey < box.Max.Y
				and p.Z + ez > box.Min.Z
				and p.Z - ez < box.Max.Z
			then
				table.insert(taken, d)
			end
		end
	end
	for _, part in taken do
		part.Parent = nil
	end
	return taken
end

local function writeJson(path: string, value: any)
	fs.writeFile(OUT .. path, serde.encode("json", value))
end

---------------------------------------------------------------- one ride's frames

type Ride = {
	Plan: any,
	FromAt: any,
	StopAt: any,
	Target: any,
	Theme: any,
	Name: string,
	OriginCage: { any },
	TargetCage: { any },
	Stage: any,
	Fx: any,
	View: any,
	Info: any,
	Caption: any,
	CaptionText: any,
	SoundText: any,
}

local function newRide(from: number, to: number, fromModel: any, toModel: any, screen: any): Ride
	local plan = Config.plan(from, to)
	local fromStop, toStop = stopOf(fromModel, from), stopOf(toModel, to)
	local fromAt, stopAt = stopCFrame(fromStop), stopCFrame(toStop)
	local floor = MineFloors.get(to)
	local theme = Config.theme(floor.Id)
	local view = View.build()
	view.Gui.Enabled = true
	View.layout(view, screen.UiScale, 0)
	local info = {
		Name = floor.Name,
		Floor = to,
		Glow = theme.Glow,
		Down = plan.Down,
		Reduced = reduced,
		CutAt = if reduced then plan.ExitAt else nil,
	}
	View.setRide(view, info)
	-- a caption (preview only, Czech): what the moment is and which sound plays
	local caption = Instance.new("ScreenGui")
	caption.Name = "Caption"
	caption.IgnoreGuiInset = false
	caption.DisplayOrder = 100
	local box = UIKit.new("Frame", {
		Name = "Box",
		AnchorPoint = V2.new(1, 0),
		Position = roblox.UDim2.new(1, -14, 0, 62),
		Size = roblox.UDim2.fromOffset(480, 74),
		BackgroundColor3 = C3.fromRGB(20, 22, 30),
		BackgroundTransparency = 0.3,
	}, caption)
	UIKit.corner(box, 14)
	local text = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = roblox.UDim2.new(1, -16, 1, 0),
		Position = roblox.UDim2.fromOffset(8, 0),
		FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = WHITE,
		Text = "",
	}, box)
	local sound = UIKit.new("TextLabel", {
		Name = "Sound",
		AnchorPoint = V2.new(1, 0),
		BackgroundTransparency = 1,
		Position = roblox.UDim2.new(1, -14, 0, 140),
		Size = roblox.UDim2.fromOffset(480, 26),
		FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne),
		TextSize = 19,
		TextXAlignment = roblox.Enum.TextXAlignment.Right,
		TextColor3 = C3.fromRGB(255, 226, 150),
		Text = "",
	}, caption)
	return {
		Plan = plan,
		FromAt = fromAt,
		StopAt = stopAt,
		Target = arrivalCFrame(stopAt),
		Theme = theme,
		Name = floor.Name,
		OriginCage = takeCage(fromStop, fromAt),
		TargetCage = takeCage(toStop, stopAt),
		Stage = Stage.build(),
		Fx = Fx.build(),
		View = view,
		Info = info,
		Caption = caption,
		CaptionText = text,
		SoundText = sound,
	}
end

local function captionFor(r: Ride, t: number): string
	local plan = r.Plan
	if t < plan.Enter then
		return "1 Příprava: karta patra svítí, PREPARING ELEVATOR..., výstražné světlo 2×, lehké otřesy"
	elseif t < plan.DoorsShut then
		return "2 Uvnitř kabiny: krátké zatmění, ocelové dveře se zavírají, displej ukazuje patro"
	elseif t < plan.BrakeAt then
		return "3 Jízda šachtou: skála, krystaly, trámy, lampy, prach, světelné pruhy, počítadlo pater"
	elseif t < plan.StopAt then
		return "4 Brzdění: šachta zpomaluje, skřípění brzd"
	elseif t < plan.ExitAt then
		return "4 Příjezd: jeden záblesk, ARRIVED!, jméno dolu, dveře se otevírají do skutečného dolu"
	end
	return "Kamera se vrací za hráče, ovládání je zpět"
end

local SOUNDS = {
	{ "start", "zvuk: mechanické cvaknutí + pípnutí" },
	{ "close", "zvuk: kovové zavírání dveří" },
	{ "shut", "zvuk: dunivý úder dveří, hučení šachty" },
	{ "tick", "zvuk: cvaknutí počítadla" },
	{ "brake", "zvuk: skřípění brzd" },
	{ "stop", "zvuk: cink!" },
	{ "open", "zvuk: dveře se otevírají + znělka dolu" },
}

local function soundFor(r: Ride, t: number): string
	local plan = r.Plan
	local cues = {
		start = 0,
		close = plan.DoorsCloseAt,
		shut = plan.DoorsShut,
		brake = plan.BrakeAt,
		stop = plan.StopAt,
		open = plan.DoorsOpenAt,
	}
	local said = ""
	for _, entry in SOUNDS do
		local at = cues[entry[1]]
		if at and t >= at and t < at + 0.45 then
			said = entry[2]
		end
	end
	for _, tick in plan.Ticks do
		if t >= tick.Time and t < tick.Time + 0.3 then
			said = "zvuk: cvaknutí počítadla (patro " .. tick.Floor .. ")"
		end
	end
	if said == "" and t >= plan.DoorsShut and t < plan.StopAt then
		said = "zvuk: hučení šachty"
	end
	return said
end

-- The camera in the preparation: the game's third-person camera behind the player at the stop.
local function prepareCamera(r: Ride, t: number): (any, any)
	local eye = r.FromAt * CF.new(7, 8.5, -19)
	local look = (r.FromAt * CF.new(0, 4.5, 0)).Position
	local pos = eye.Position
	if not reduced then
		local amp = Config.Shake.Prepare * math.clamp(t / 0.15, 0, 1)
		pos += V3.new(math.sin(t * 47) * amp, math.cos(t * 39) * amp, 0)
	end
	return pos, look
end

-- Everything that moves at `t`, as a model of its own (cloned out of the live set).
local function frameModel(r: Ride, t: number, cutAt: number?): any
	local plan = r.Plan
	local extra = Instance.new("Model")
	local travel, speed = Stage.travelAt(plan, t), Stage.speedAt(plan, t)
	Stage.pose(r.Stage, plan, { T = t, Travel = travel, Speed = speed, Reduced = reduced, FromAt = r.FromAt, StopAt = r.StopAt })
	r.Stage.Folder:Clone().Parent = extra
	-- the real cage: the one left before the dip, the target's as the cabin fades out
	if t < plan.DipMid then
		for _, part in r.OriginCage do
			part:Clone().Parent = extra
		end
	end
	local fade = Stage.fadeAt(plan, t)
	if fade > 0 or t >= plan.EndAt then
		for _, part in r.TargetCage do
			local copy = part:Clone()
			copy.Transparency = part.Transparency + (1 - part.Transparency) * (1 - fade)
			copy.Parent = extra
		end
	end
	-- the stand-in player: at the stop before the dip, at the target once the doors open
	if t < plan.DipMid then
		local feet = r.FromAt * CF.new(2.2, 0.6, -6.6) * CF.Angles(0, math.pi, 0)
		Dummy.build(extra, CF, feet, "idle")
	elseif t >= plan.ExitAt + 0.15 then
		-- (the game fades the player in as the camera starts back; hidden while the doors open)
		local feet = r.Target * CF.new(0, -3, 0)
		Dummy.build(extra, CF, feet, "idle")
	end
	-- the arrival effects (their emitters only while they emit)
	if t >= plan.StopAt then
		local since = t - plan.StopAt
		if r.Fx.Theme == nil then
			Fx.setTheme(r.Fx, r.Theme, r.StopAt)
		end
		Fx.pose(r.Fx, since, reduced)
		local copy = r.Fx.Folder:Clone()
		local emitting = since >= Config.Timing.OpenDelay and since < 1.8
		for _, d in copy:GetDescendants() do
			if d:IsA("ParticleEmitter") and not emitting then
				d:Destroy()
			elseif d:IsA("BasePart") and d.Transparency >= 1 and #d:GetChildren() == 0 then
				d:Destroy()
			end
		end
		copy.Parent = extra
	end
	local _ = cutAt
	return extra
end

local function cameraFor(r: Ride, t: number, info: any): (any, any, number)
	local cf, fov = Stage.camera(r.Plan, t, info)
	if not cf then
		local pos, look = prepareCamera(r, t)
		return pos, look, 70
	end
	return cf.Position, cf.Position + cf.LookVector * 10, fov
end

---------------------------------------------------------------- modes

local function screenOf(phone: boolean): any
	if phone then
		return { W = 812, H = 375, Inset = 58, UiScale = 0.62 * 375 / 375 }
	end
	return { W = 1600, H = 900, Inset = 36, UiScale = 1.25 }
end

local function shotOf(tag: string, base: string, name: string, screen: any, pos: any, lookAt: any, fov: number, preset: string): any
	return {
		scene = base,
		extra = tag .. "/fx_" .. name,
		ui = tag .. "/ui_" .. name,
		width = screen.W,
		height = screen.H,
		uiInset = screen.Inset,
		position = { pos.X, pos.Y, pos.Z },
		target = { lookAt.X, lookAt.Y, lookAt.Z },
		fov = fov,
		cam = { position = { pos.X, pos.Y, pos.Z }, target = { lookAt.X, lookAt.Y, lookAt.Z }, fov = fov },
		preset = preset,
		shadowExtent = 70,
		maxLights = 24,
	}
end

local function buildWorld(floors: { number }): (any, { [number]: any })
	local game = Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local models = {}
	for _, index in floors do
		if not models[index] then
			models[index] = buildFloor(map, index)
		end
	end
	return workspace, models
end

local function exportBase(workspace: any, name: string)
	local scene = Export.collect(workspace)
	scene.presets = presetsJson()
	writeJson(name .. ".json", scene)
	print(`{name}: {#scene.parts} parts`)
end

if mode == "reel" or mode == "phone" then
	local phone = mode == "phone"
	local screen = screenOf(phone)
	local tag = if phone then "elevphone" else "elevtravel"
	local workspace, models = buildWorld({ FROM, TO })
	local r = newRide(FROM, TO, models[FROM], models[TO], screen)
	exportBase(workspace, tag .. "_base")
	fs.writeDir(OUT .. tag)
	local plan = r.Plan
	local info = {
		FromAt = r.FromAt,
		StopAt = r.StopAt,
		Target = r.Target,
		Zoom = 10, -- (the game: the player's zoom, less where something stands behind them)
		Fov = 70,
		Reduced = reduced,
		Speed = 0,
		CutAt = if reduced then plan.ExitAt else nil,
	}
	local fromPreset = MineFloors.get(FROM).Lighting
	local toPreset = MineFloors.get(TO).Lighting
	local segments = { a = {}, b = {}, c = {} }
	local all = {}
	local times: { number } = {}
	if phone then
		times = { 0.3, plan.DoorsShut + 0.6, plan.StopAt + 0.5, plan.ExitAt - 0.05 }
	else
		local frames = math.floor((plan.EndAt + 0.35) * fps)
		for i = 0, frames - 1 do
			table.insert(times, i / fps)
		end
	end
	for i, t in times do
		local name = string.format("%04d", i - 1)
		info.Speed = Stage.speedAt(plan, t)
		local extra = frameModel(r, t, info.CutAt)
		View.pose(r.View, plan, t, r.Info)
		r.CaptionText.Text = captionFor(r, t)
		r.SoundText.Text = soundFor(r, t)
		local guis = { r.View.Gui }
		if not phone then
			table.insert(guis, r.Caption)
		end
		writeJson(tag .. "/fx_" .. name .. ".json", Export.collect(extra))
		writeJson(tag .. "/ui_" .. name .. ".json", UiExport.export(guis))
		local pos, lookAt, fov = cameraFor(r, t, info)
		local segment = if t < plan.DipMid then "a" elseif t < plan.StopAt then "b" else "c"
		local preset = if segment == "a" then fromPreset elseif segment == "b" then "ElevatorRide" else toPreset
		local shot = shotOf(tag, tag .. "_base", name, screen, pos, lookAt, fov, preset)
		segments[segment][tag .. "_" .. segment .. "_" .. name] = shot
		all[tag .. "_" .. name] = shot
		if i % 20 == 0 then
			print(`frame {i}/{#times}`)
		end
	end
	for key, list in segments do
		writeJson(tag .. "_" .. key .. "_shots.json", list)
	end
	writeJson(tag .. "_shots.json", all)
	local function frameAt(seconds: number): number
		return math.clamp(math.floor(seconds * fps + 0.5), 0, #times - 1)
	end
	if not phone then
		writeJson(tag .. "_board.json", {
			title = `VÝTAH: jízda z patra {FROM} do patra {TO} ({MineFloors.get(TO).Name})`,
			fps = fps,
			cells = {
				{ frame = frameAt(0.3), caption = "1 Příprava: PREPARING ELEVATOR..., výstražné světlo, otřesy" },
				{ frame = frameAt(plan.DoorsCloseAt + 0.25), caption = "2 V kabině: dveře se zavírají nad dolem, který opouštíš" },
				{ frame = frameAt(plan.TravelStart + 0.9), caption = "3 Jízda šachtou: skála, krystaly, prach, světelné pruhy" },
				{ frame = frameAt(plan.Ticks[#plan.Ticks].Time + 0.1), caption = "3 Počítadlo pater dojede na cílové patro" },
				{ frame = frameAt(plan.StopAt + 0.08), caption = "4 Zastavení: záblesk, ARRIVED!, jméno dolu" },
				{ frame = frameAt(plan.DoorsOpenAt + 0.4), caption = "4 Dveře se otevírají do skutečného dolu + jeho efekty" },
				{ frame = frameAt(plan.ExitAt + 0.35), caption = "Kamera se vrací za hráče" },
				{ frame = frameAt(plan.EndAt + 0.2), caption = "Konec: ovládání zpět, efekty dohrávají" },
			},
		})
	end
	print(`{#times} frames ({plan.EndAt} s ride)`)
elseif mode == "arrivals" then
	-- one still a mine: the doors fully open on its floor, its effects at their best moment
	-- (seconds after the stop: the doors are open by 0.9 and the camera leaves at 0.95; the Rift's third arc at 1.0)
	local best = { Quarry = 0.92, EmberCaves = 0.92, DeepHollow = 0.92, SunkenPalace = 0.92, StormglassRift = 1.01, HeartstoneCore = 0.92 }
	for _, floor in MineFloors.List do
		local to = floor.Index
		local from = if to == 1 then 2 else to - 1
		local tag = "elevarrive_" .. floor.Id
		local screen = screenOf(false)
		local workspace, models = buildWorld({ from, to })
		local r = newRide(from, to, models[from], models[to], screen)
		exportBase(workspace, tag .. "_base")
		fs.writeDir(OUT .. tag)
		local plan = r.Plan
		local t = plan.StopAt + (best[floor.Id] or 0.95)
		local extra = frameModel(r, t, nil)
		View.pose(r.View, plan, t, r.Info)
		writeJson(tag .. "/fx_0000.json", Export.collect(extra))
		writeJson(tag .. "/ui_0000.json", UiExport.export({ r.View.Gui }))
		-- the camera stays in the cabin and looks out through the open doors
		local info =
			{ FromAt = r.FromAt, StopAt = r.StopAt, Target = r.Target, Zoom = 12.5, Fov = 70, Reduced = false, Speed = 0, CutAt = 99 }
		local pos, lookAt, fov = cameraFor(r, t, info)
		writeJson(
			tag .. "_shots.json",
			{ [tag .. "_0000"] = shotOf(tag, tag .. "_base", "0000", screen, pos, lookAt, fov, floor.Lighting) }
		)
		print(tag .. " ready")
	end
else
	error("mode: reel | arrivals | phone")
end
