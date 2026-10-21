--[[
	Video frames of the player LEVEL UP (owner 2026-10-21), posed with the
	game's own code: LevelView (the bar, the orbs, the glow, LEVEL UP!, the
	reward rows) and Effects/LevelBurst (the world burst), the way
	LevelController plays them. A miner stands on the plaza in front of the
	HALL OF FAME (its fifth board, LEVEL, in the back, sample rows like
	hall_preview), the camera behind them like Roblox's.

	  lune run tools/lune/export_levelup.luau [fps=20]
	-> build/preview/levelup_base.json (the world, once)
	   build/preview/levelup/fx_NNNN.json + ui_NNNN.json per frame
	   build/preview/levelup_shots.json (one shot per frame, "extra" = the burst parts)
	then: node tools/preview/render_levelup.mjs
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local UiExport = require("./lib/uiexport")
local Dummy = require("./lib/dummy")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true

local fps = tonumber(process.args[1]) or 20
local CF = Loader.CFrame
local V3 = roblox.Vector3

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local LevelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LevelConfig")
local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
local LevelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LevelView")
local LevelBurst = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.LevelBurst")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")

local W, H, INSET, SCALE, FOV = 1600, 900, 36, 1.25, 70

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
WorldBuilder.build(workspace)
local map = workspace:FindFirstChild("Map") or workspace
require("./lib/hall_preview").build(Loader, map)

-- the miner on the plaza in front of the hall, facing it
local board3
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "Board3" then
		board3 = d
	end
end
assert(board3, "no HALL OF FAME")
local out = board3.CFrame.LookVector * V3.new(1, 0, 1)
out = out.Unit
local hallBase = board3.CFrame.Position - V3.new(0, board3.CFrame.Position.Y, 0)
local groundY = board3.CFrame.Position.Y - (1.2 + 0.3 + 7.2 / 2) -- the hall stands on the plaza (Hall: PLINTH, board centre)
local feet = V3.new(hallBase.X, groundY, hallBase.Z) + out * 15
local props = roblox.Instance.new("Folder")
props.Name = "Props"
props.Parent = workspace
Dummy.build(
	props,
	CF,
	CF.lookAt(feet, feet - out),
	"idle",
	{ shirt = roblox.Color3.fromRGB(70, 120, 200), pants = roblox.Color3.fromRGB(50, 50, 64) }
)

local camPos = feet + out * 13 + V3.new(0, 7.5, 0)
local camTarget = feet + V3.new(0, 6.5, 0) - out * 6

-- what is far away and small doesn't show: off the scene (faster frames)
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		local size = d.Size
		local far = (d.CFrame.Position - feet).Magnitude > 260 and math.max(size.X, size.Y, size.Z) < 40
		local inLens = (d.CFrame.Position - camPos).Magnitude < 8 and math.max(size.X, size.Y, size.Z) < 12 -- props right at the camera
		if far or inLens then
			d.Transparency = 1 -- the exporter skips it
		end
	end
end

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

fs.writeDir(root .. "/build/preview/levelup")
local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end
scene.presets = presets
fs.writeFile(root .. "/build/preview/levelup_base.json", serde.encode("json", scene))
print(`base scene: {#scene.parts} parts`)

-- the screen point of a world point (the renderer's camera)
local look = CF.lookAt(camPos, camTarget)
local function screen(p: any): any
	local rel = look:PointToObjectSpace(p)
	local f = 1 / math.tan(math.rad(FOV) / 2)
	local x = (rel.X / -rel.Z) * f * (H / W)
	local y = (rel.Y / -rel.Z) * f
	return roblox.Vector2.new((x + 1) / 2 * W, (1 - y) / 2 * H)
end
local orbFrom = screen(feet + V3.new(0, 4.5, 0)) - roblox.Vector2.new(0, INSET)

-- the HUD under it (coins, carry) as in the game
local hud = HudView.build()
hud.Gui.Scale.Scale = SCALE
hud.Coins.Text = "$12.4K"
hud.Zone.Text = ""
hud.Toasts:ClearAllChildren()

-- the timeline (seconds): three XP gains fill the bar, the glow builds, LEVEL UP!, a gain after
local level = 11
local need = LevelConfig.need(level)
local up = { Level = level + 1, Coins = 1350, Bonus = LevelConfig.bonusFor(level + 1), Milestone = false }
local gains = {
	{ At = 0.3, From = 0.5, To = 0.7, Orbs = 4 },
	{ At = 1.1, From = 0.7, To = 0.88, Orbs = 5 },
	{ At = 1.9, From = 0.88, To = 1.0, Orbs = 6 },
}
local momentAt = 2.85
local after = { At = momentAt + 4.0, From = 0, To = 0.14, Orbs = 3 }
local total = after.At + 1.6
local ORB = 0.6

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end

-- where the bar's fill end is on screen (the orbs fly there)
local function barEnd(shown: number): any
	local trackLeft = W / 2 + SCALE * (LevelView.Badge / 2 - LevelView.BarWidth / 2)
	local y = INSET + (H - INSET) - SCALE * (LevelView.BarBottom + LevelView.BarHeight / 2)
	return roblox.Vector2.new(trackLeft + SCALE * LevelView.BarWidth * math.max(shown, 0.04), y - INSET)
end

local frames = math.floor(total * fps)
local shots = {}
for i = 0, frames - 1 do
	local t = i / fps
	local view = LevelView.build()
	view.Gui.Scale.Scale = SCALE
	-- the fill and the level shown
	local shown, lvl, barNeed = 0.5, level, need
	local list = table.clone(gains)
	table.insert(list, after)
	for _, g in list do
		if t >= g.At + ORB * 0.85 then
			shown = g.From + (g.To - g.From) * smooth((t - g.At - ORB * 0.85) / 0.5)
		end
	end
	if t >= momentAt then
		lvl, barNeed = level + 1, LevelConfig.need(level + 1)
		if t < after.At + ORB * 0.85 then
			shown = 0
		end
	end
	LevelView.setBar(view, lvl, shown, shown * barNeed, barNeed)
	LevelView.poseGlow(view, shown, t)
	-- the orbs in flight
	local n = 0
	for gi, g in list do
		for k = 1, g.Orbs do
			local u = (t - g.At - (k - 1) * 0.06) / ORB
			if u > 0 and u < 1 then
				n += 1
				local orb = view.OrbList[(n - 1) % #view.OrbList + 1]
				LevelView.poseOrb(orb, orbFrom, barEnd(shown), u, 1, gi * 3.1 + k * 1.7)
			end
		end
	end
	-- the moment
	local burstModel = roblox.Instance.new("Model")
	if t >= momentAt then
		LevelView.poseMoment(view, t - momentAt, up)
		local burst = LevelBurst.build(burstModel, CF.lookAt(feet, feet - out), false)
		LevelBurst.pose(burst, t - momentAt)
	else
		LevelView.hideMoment(view)
	end
	local name = string.format("%04d", i)
	fs.writeFile(root .. "/build/preview/levelup/fx_" .. name .. ".json", serde.encode("json", Export.collect(burstModel)))
	fs.writeFile(
		root .. "/build/preview/levelup/ui_" .. name .. ".json",
		serde.encode("json", UiExport.export({ hud.Gui, view.Gui, view.Orbs }))
	)
	shots["levelup_" .. name] = {
		scene = "levelup_base",
		extra = "levelup/fx_" .. name,
		ui = "levelup/ui_" .. name,
		position = { camPos.X, camPos.Y, camPos.Z },
		target = { camTarget.X, camTarget.Y, camTarget.Z },
		fov = FOV,
		preset = "Surface",
		shadowExtent = 120,
	}
end
fs.writeFile(root .. "/build/preview/levelup_shots.json", serde.encode("json", shots))
print(`{frames} frames at {fps} fps ({total} s)`)
