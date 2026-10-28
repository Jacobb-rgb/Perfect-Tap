--[[
	The EGGS temple's egg panels (owner 2026-10-28: "make the UI for pets
	like this", two pictures of other egg games) for the owner, rendered
	without Studio. tools/preview is a three.js approximation of Roblox: the
	lighting, the fonts and the 3D pictures are close, not exact; the stock
	Roblox prompt is drawn by hand here (the game uses Roblox's own) and the
	golems' live 3D pictures are the preview icons (tools/preview/render_icons).

	Built with the game's own code: WorldBuilder (the temple and its eggs),
	UI/EggPanel (laid out and filled the way EggPanelController does, over
	the egg's top: EggPanel.spotOf) and CapsuleView's opening overlay.

	  lune run tools/lune/export_egg_panel.luau [fps=20]
	  -> build/preview/egg_panel_base.json        the world, once
	     build/preview/egg_panel/*.json           the miner (extra parts) and the UI per still / frame
	     build/preview/egg_panel_shots.json       the stills
	     build/preview/egg_video_shots.json       the video's frames
	then (icons first: lune run tools/lune/export_icon_parts.luau; node tools/preview/render_icons.mjs golem_* capsule_*):
	  SHOTS_EXTRA=build/preview/egg_panel_shots.json node tools/preview/render.mjs egg_panel_base
	  node tools/preview/render_shot_frames.mjs build/preview/egg_video_shots.json vejce_e 20
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
local V2 = roblox.Vector2
local UDim2 = roblox.UDim2
local Color3 = roblox.Color3
local Instance = roblox.Instance
local Enum = roblox.Enum
local rgb = Color3.fromRGB
local Font = roblox.Font

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")
local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")

local OUT = root .. "/build/preview/egg_panel"
fs.writeDir(OUT)

---------------------------------------------------------------- the world

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
WorldBuilder.build(workspace)

local stall
for _, d in workspace:GetDescendants() do
	if d:IsA("Model") and d.PrimaryPart and d.PrimaryPart.Name == "CapsuleMachine" then
		stall = d
	end
end
assert(stall, "no EGGS temple in the world")
local frame = LobbyLayout.frame(LobbyLayout.get("CapsuleStall"))
local front = frame.LookVector
local right = frame.RightVector
local up = V3.new(0, 1, 0)
local eggs = EggPanel.eggsIn(stall)
-- the dais' floor: the Royal podium ("CapsuleMachine", 1.8 tall) stands on it;
-- the stall's ground is 1.2 lower (Districts/Capsules: FLOOR)
local floor = stall.PrimaryPart.CFrame.Position.Y - 0.9
local ground = floor - 1.2

type Spot = { Center: any, Top: number, Prompt: any }
local spots: { [string]: Spot } = {}
for id, model in eggs do
	local center, top, prompt = EggPanel.spotOf(model, front)
	spots[id] = { Center = center, Top = top, Prompt = prompt }
end

if process.args[1] == "probe" then
	print("front", front, "right", right, "ground", ground)
	for id, s in spots do
		print(id, s.Center, s.Top, s.Prompt)
	end
	return
end

-- far, small parts don't show: off the scene (faster frames)
local templeAt = frame.Position
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		local size = d.Size
		if (d.CFrame.Position - templeAt).Magnitude > 240 and math.max(size.X, size.Y, size.Z) < 40 then
			d.Transparency = 1
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

local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end
scene.presets = presets
fs.writeFile(root .. "/build/preview/egg_panel_base.json", serde.encode("json", scene))
print(`base scene: {#scene.parts} parts`)

---------------------------------------------------------------- screens

type Screen = { W: number, H: number, Pixel: number, Phone: boolean, Fov: number }
-- PC: 1600 x 900 at the HUD's 1.25; a phone: 844 x 390 pt rendered at 2x (the HUD's 0.62 floor)
local PC: Screen = { W = 1600, H = 900, Pixel = 1.25, Phone = false, Fov = 70 }
local PHONE: Screen = { W = 1688, H = 780, Pixel = 0.62 * 2, Phone = true, Fov = 70 }

type Cam = { Position: any, Target: any }

-- the screen point of a world point (the renderer's three.js camera: vertical fov)
local function project(screen: Screen, cam: Cam, p: any): (number, number)
	local look = CF.lookAt(cam.Position, cam.Target)
	local rel = look:PointToObjectSpace(p)
	local f = 1 / math.tan(math.rad(screen.Fov) / 2)
	local x = (rel.X / -rel.Z) * f * (screen.H / screen.W)
	local y = (rel.Y / -rel.Z) * f
	return (x + 1) / 2 * screen.W, (1 - y) / 2 * screen.H
end

-- A preview player's State: these golems are owned (the rest of a coin egg shows as silhouettes).
local OWNED = { "PebbleGolem", "CopperTinker", "CoalChomper", "QuartzSprite", "EmberImp", "GildedPorter" }
local function knownSet(extra: string?): { [string]: boolean }
	local list = {}
	for i, kind in OWNED do
		list[i] = { Id = i, Kind = kind }
	end
	if extra then
		table.insert(list, { Id = #list + 1, Kind = extra })
	end
	return EggPanel.known({ Golems = { Owned = list, Equipped = {}, Pending = {} } })
end

type PanelSpec = {
	Egg: string,
	Lucky: boolean,
	Auto: boolean,
	Known: { [string]: boolean },
	Coins: number,
	Fade: number?, -- 0 shown .. 1 gone
	Pop: number?, -- the pop-in's scale (1 = done)
}

-- The panel over `spec.Egg` as the game draws it, placed where its billboard would be.
local function panelGui(screen: Screen, cam: Cam, spec: PanelSpec): any
	local gui = UIKit.screen("EggPanelPreview", 1)
	gui.IgnoreGuiInset = true
	gui.Scale.Scale = screen.Pixel
	local refs = EggPanel.build()
	local lines = EggPanel.lines(spec.Egg, spec.Lucky, spec.Known)
	local l = EggPanel.layout(#lines, screen.Phone)
	EggPanel.apply(refs, spec.Egg, l, 1)
	EggPanel.setLines(refs, lines, nil)
	local capsule = CapsuleConfig.ById[spec.Egg]
	if capsule.Currency == "Robux" then
		local product = MonetizationConfig.get(CapsuleConfig.product(spec.Egg, 1))
		EggPanel.setPrice(refs, "Robux", `R$ {product.Robux}`, true)
	else
		local price = CapsuleConfig.price(spec.Egg, 1, 1) or 0
		EggPanel.setPrice(refs, "Coins", EggPanel.priceText(price), spec.Coins >= price)
	end
	local autoShown = EggPanel.autoAllowed(spec.Egg)
	EggPanel.setAuto(refs, autoShown, spec.Auto, if screen.Phone then "" else "G", nil)
	EggPanel.setLucky(refs, spec.Lucky, autoShown)
	EggPanel.setFade(refs, spec.Fade or 0)
	local s = spots[spec.Egg]
	local x, y = project(screen, cam, V3.new(s.Center.X, s.Top + EggPanel.Lift, s.Center.Z))
	local panel = refs.Root
	panel.Parent = gui
	panel.Position = UDim2.fromOffset(x / screen.Pixel, y / screen.Pixel)
	-- (the preview scales a UIScale about the frame's centre; the game about its bottom edge)
	local pop = spec.Pop or 1
	refs.Scale.Scale = pop
	if pop ~= 1 then
		panel.Position = UDim2.fromOffset(x / screen.Pixel, y / screen.Pixel - l.Height * (1 - pop) / 2)
	end
	return gui
end

--[[
	Roblox's stock ProximityPrompt (drawn by hand: the game uses Roblox's
	own), centred on the prompt's point; the second one UIOffset 72 lower:
	a dark see-through box, the key in a white-edged square (a tap mark on
	a phone), the object text small over the action text.
]]
type PromptSpec = { Action: string, Object: string, Key: string, Pressed: boolean? }
local function promptGui(screen: Screen, cam: Cam, egg: string, list: { PromptSpec }, alpha: number?): any
	local gui = UIKit.screen("StockPrompts", 2)
	gui.IgnoreGuiInset = true
	local k = if screen.Phone then 2 else 1 -- (points to render pixels)
	gui.Scale.Scale = k
	local x, y = project(screen, cam, spots[egg].Prompt)
	local a = alpha or 0
	for i, p in list do
		local w = math.max(150, 72 + math.max(#p.Action * 10.5, #p.Object * 7.5) + 18)
		local box = UIKit.new("Frame", {
			Name = "Prompt" .. i,
			AnchorPoint = V2.new(0.5, 0.5),
			BackgroundColor3 = rgb(0, 0, 0),
			BackgroundTransparency = 0.5 + 0.5 * a,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x / k, y / k + (i - 1) * 72),
			Size = UDim2.fromOffset(w, 72),
		}, gui)
		UIKit.corner(box, 10)
		local keyBox = UIKit.new("Frame", {
			Name = "Key",
			AnchorPoint = V2.new(0.5, 0.5),
			BackgroundColor3 = if p.Pressed then rgb(255, 255, 255) else rgb(0, 0, 0),
			BackgroundTransparency = if p.Pressed then 0.2 else 1,
			Position = UDim2.fromOffset(36, 36),
			Size = UDim2.fromOffset(if p.Pressed then 40 else 44, if p.Pressed then 40 else 44),
		}, box)
		UIKit.corner(keyBox, if screen.Phone then 22 else 8)
		UIKit.stroke(keyBox, 2, rgb(255, 255, 255), a)
		UIKit.new("TextLabel", {
			Name = "Letter",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			Size = UDim2.fromScale(1, 1),
			Text = if screen.Phone then "" else p.Key,
			TextColor3 = if p.Pressed then rgb(0, 0, 0) else rgb(255, 255, 255),
			TextSize = 22,
			TextTransparency = a,
		}, keyBox)
		if screen.Phone then
			-- the tap mark (a small filled dot in the ring)
			local dot = UIKit.new("Frame", {
				Name = "Tap",
				AnchorPoint = V2.new(0.5, 0.5),
				BackgroundColor3 = rgb(255, 255, 255),
				BackgroundTransparency = a,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(14, 14),
			}, keyBox)
			UIKit.corner(dot, 7)
		end
		UIKit.new("TextLabel", {
			Name = "Object",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium),
			Position = UDim2.fromOffset(72, 12),
			Size = UDim2.new(1, -80, 0, 18),
			Text = p.Object,
			TextColor3 = rgb(200, 200, 200),
			TextSize = 15,
			TextTransparency = a,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, box)
		UIKit.new("TextLabel", {
			Name = "Action",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			Position = UDim2.fromOffset(72, 32),
			Size = UDim2.new(1, -80, 0, 26),
			Text = p.Action,
			TextColor3 = rgb(255, 255, 255),
			TextSize = 20,
			TextTransparency = a,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, box)
	end
	return gui
end

local function prompts(egg: string, auto: boolean, pressed: boolean?): { PromptSpec }
	local capsule = CapsuleConfig.ById[egg]
	local list: { PromptSpec } = {}
	local object
	if capsule.Currency == "Robux" then
		local product = MonetizationConfig.get(CapsuleConfig.product(egg, 1))
		object = EggPanel.promptText(true, nil, `R$ {product.Robux}`, true)
	else
		object = EggPanel.promptText(false, CapsuleConfig.price(egg, 1, 1), "", true)
	end
	table.insert(list, { Action = "Buy Egg!", Object = object, Key = "E", Pressed = pressed })
	if EggPanel.autoAllowed(egg) then
		table.insert(list, { Action = "Auto", Object = if auto then "On" else "Off", Key = "G" })
	end
	return list
end

-- The miner (a blocky stand-in for the player's avatar) at `feet`, facing `toward`.
local function miner(feet: any, toward: any, step: number?): any
	local m = Instance.new("Model")
	local look = V3.new(toward.X, feet.Y, toward.Z)
	local body = Dummy.build(m, CF, CF.lookAt(feet, look), "idle", { shirt = rgb(70, 120, 200), pants = rgb(50, 50, 64) })
	if step then
		-- a walking bob and the legs apart (the stand-in has no animation)
		local bob = math.abs(math.sin(step)) * 0.18
		for i, part in body:GetChildren() do
			if part:IsA("BasePart") then
				local swing = if i == 1 then math.sin(step) * 0.5 elseif i == 2 then -math.sin(step) * 0.5 else 0
				part.CFrame = CF.new(0, bob, 0) * part.CFrame * CF.Angles(swing, 0, 0)
			end
		end
	end
	return m
end

local stills = {}
local function still(name: string, screen: Screen, cam: Cam, extra: any, guis: { any })
	fs.writeFile(OUT .. "/" .. name .. "_fx.json", serde.encode("json", Export.collect(extra)))
	fs.writeFile(OUT .. "/" .. name .. "_ui.json", serde.encode("json", UiExport.export(guis)))
	stills[name] = {
		scene = "egg_panel_base",
		extra = "egg_panel/" .. name .. "_fx",
		ui = "egg_panel/" .. name .. "_ui",
		width = screen.W,
		height = screen.H,
		uiInset = if screen.Phone then 72 else 36,
		position = { cam.Position.X, cam.Position.Y, cam.Position.Z },
		target = { cam.Target.X, cam.Target.Y, cam.Target.Z },
		fov = screen.Fov,
		preset = "Surface",
		shadowExtent = 120,
	}
end

-- Where the player stands at an egg (on the dais, in front of its prompt) and Roblox's camera behind them.
local function standAt(egg: string, back: number?, aside: number?): (any, Cam)
	local s = spots[egg]
	local flat = V3.new(s.Center.X, floor, s.Center.Z)
	-- (a step to the side of the egg's front: the camera over the other shoulder sees the egg)
	local feet = flat + front * 4.4 - right * 2.6
	local camPos = feet + front * (back or 11) - right * (aside or 6) + up * 7.5
	local target = V3.new(s.Center.X, s.Top + 1.6, s.Center.Z) - right * 0.4
	return feet, { Position = camPos, Target = target }
end

-- the Royal egg's Robux price as it shows once its product id is live (preview-only ids)
local royal1 = MonetizationConfig.Products.RoyalCapsule1
local royalId = royal1.Id
royal1.Id = 1

for _, screen in { PC, PHONE } do
	local tag = if screen.Phone then "phone" else "pc"
	for _, egg in { "Stone", "Crystal", "Royal" } do
		if screen.Phone and egg == "Crystal" then
			continue
		end
		local feet, cam = standAt(egg)
		local lucky = egg == "Crystal"
		local auto = egg == "Crystal"
		local guis = {
			panelGui(screen, cam, { Egg = egg, Lucky = lucky, Auto = auto, Known = knownSet(), Coins = 1e9 }),
			promptGui(screen, cam, egg, prompts(egg, auto)),
		}
		still(`egg_{string.lower(egg)}_{tag}`, screen, cam, miner(feet, spots[egg].Center), guis)
	end
end
royal1.Id = royalId

fs.writeFile(root .. "/build/preview/egg_panel_shots.json", serde.encode("json", stills))
local n = 0
for _ in stills do
	n += 1
end
print(`{n} stills`)

---------------------------------------------------------------- the video

--[[
	Walk up to the Stone egg (its panel pops in at ShowRange, the prompts at
	PromptDistance), press E, the opening (the egg shakes, bursts, a Silver
	Squire wakes: NEW!), OK, and its card on the panel is in colour now.
]]
local VIDEO = PC
local GOLEM = "SilverSquire"
local s = spots.Stone
local endFeet, cam = standAt("Stone", 18, 8)
local startFeet = endFeet + front * 11
local timeline = {
	WalkEnd = 1.6,
	Press = 2.8,
	Open = 3.05,
	Shake = 1.35,
	Ok = 6.9,
	Total = 8.8,
}
local o = CapsuleView.buildOpening(false)
o.Gui.Scale.Scale = VIDEO.Pixel
local designW, designH = VIDEO.W / VIDEO.Pixel, (VIDEO.H - 36) / VIDEO.Pixel
CapsuleView.layoutOpening(o, false, designW, designH)
for _, glow in o.Rays:GetChildren() do
	if glow:IsA("Frame") and string.sub(glow.Name, 1, 4) == "Glow" then
		glow.Visible = false -- (the preview's icon stands in for the hero viewport: no disc over it)
	end
end
local dimBase = o.Dim.BackgroundTransparency
local price = CapsuleConfig.price("Stone", 1, 1) or 0

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end
local function back(x: number): number
	x = math.clamp(x, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local frames = math.floor(timeline.Total * fps)
local shots = {}
local shownAt: number? = nil
local promptAt: number? = nil
for i = 0, frames - 1 do
	local t = i / fps
	-- the walk: from the plaza up the steps to the egg
	local k = math.clamp(t / timeline.WalkEnd, 0, 1) -- (a steady walk)
	local feet = startFeet:Lerp(endFeet, k)
	local onDais = (feet - frame.Position):Dot(front) < 9
	feet = V3.new(feet.X, if onDais then floor else ground, feet.Z)
	local walking = t < timeline.WalkEnd
	local figure = miner(feet, s.Center, if walking then t * 11 else nil)
	-- the panel and the prompts come up where the game shows them
	local distance = (s.Center - feet - V3.new(0, 3, 0)).Magnitude
	if not shownAt and distance <= EggPanel.ShowRange then
		shownAt = t
	end
	if not promptAt and (s.Prompt - feet - V3.new(0, 3, 0)).Magnitude <= EggPanel.PromptDistance then
		promptAt = t
	end
	local guis = { UIKit.screen("Empty", 0) } -- (never an empty list: JSON would make it an object)
	local woke = t >= timeline.Ok
	if shownAt then
		local since = t - shownAt
		table.insert(
			guis,
			panelGui(VIDEO, cam, {
				Egg = "Stone",
				Lucky = false,
				Auto = false,
				Known = knownSet(if woke then GOLEM else nil),
				Coins = 1e9,
				Fade = 1 - ease(since / 0.18),
				Pop = 0.82 + 0.18 * back(since / 0.26),
			})
		)
	end
	if promptAt and t < timeline.Open then
		local since = t - promptAt
		local pressed = t >= timeline.Press and t < timeline.Press + 0.15
		table.insert(guis, promptGui(VIDEO, cam, "Stone", prompts("Stone", false, pressed), 1 - math.clamp(since / 0.12, 0, 1)))
	elseif t >= timeline.Ok + 0.25 then
		table.insert(guis, promptGui(VIDEO, cam, "Stone", prompts("Stone", false)))
	end
	-- the opening (CapsuleView's overlay, posed like CapsuleController plays it)
	local u = t - timeline.Open
	if u >= 0 and t < timeline.Ok then
		o.Gui.Enabled = true
		o.Dim.BackgroundTransparency = dimBase + (1 - dimBase) * (1 - ease(u / 0.15))
		o.Rays.Rotation = u * 14 * 57.3 / 10
		local burstAt = timeline.Shake
		if u < burstAt then
			-- the egg shakes harder and harder
			local p = u / burstAt
			o.Hero:SetAttribute("Icon", "capsule_Stone")
			o.Hero.Rotation = math.sin(u * (16 + 14 * p)) * (3 + 17 * p * p)
			o.Hero.Size = UDim2.fromOffset(300 * (1 + 0.05 * p), 300 * (1 + 0.05 * p))
			o.Rays.Visible = false
			o.Plate.Visible = false
			o.Flash.BackgroundTransparency = 1
			o.Skip.Parent.Visible = true
			o.Ok.Parent.Visible = false
			o.Again.Parent.Visible = false
			o.Hint.Text = `Click or Space to skip{CapsuleView.Separator}Backspace: skip all`
		else
			local v = u - burstAt
			o.Hero:SetAttribute("Icon", "golem_" .. GOLEM)
			o.Hero.Rotation = 0
			local grow = 0.6 + 0.4 * back(v / 0.35)
			o.Hero.Size = UDim2.fromOffset(300 * grow, 300 * grow)
			o.Flash.BackgroundColor3 = CapsuleView.rarityColor(GOLEM):Lerp(Color3.new(1, 1, 1), 0.45)
			o.Flash.BackgroundTransparency = 1 - 0.9 * (1 - ease(v / 0.45))
			o.Rays.Visible = true
			CapsuleView.setRayColor(o, CapsuleView.rarityColor(GOLEM))
			CapsuleView.setPlate(o, GOLEM, true)
			o.Counter.Text = ""
			o.Note.Text = ""
			-- one egg: the end screen comes at once (OK, OPEN 1 AGAIN)
			o.Skip.Parent.Visible = false
			o.Ok.Parent.Visible = true
			o.Again.Parent.Visible = true
			o.Again.Text = `OPEN 1 AGAIN  $` .. EggPanel.priceText(price)
			o.Hint.Text = ""
		end
		table.insert(guis, o.Gui)
	end
	local name = string.format("v_%04d", i)
	fs.writeFile(OUT .. "/" .. name .. "_fx.json", serde.encode("json", Export.collect(figure)))
	fs.writeFile(OUT .. "/" .. name .. "_ui.json", serde.encode("json", UiExport.export(guis)))
	shots[name] = {
		scene = "egg_panel_base",
		extra = "egg_panel/" .. name .. "_fx",
		ui = "egg_panel/" .. name .. "_ui",
		width = VIDEO.W,
		height = VIDEO.H,
		uiInset = 36,
		position = { cam.Position.X, cam.Position.Y, cam.Position.Z },
		target = { cam.Target.X, cam.Target.Y, cam.Target.Z },
		fov = VIDEO.Fov,
		preset = "Surface",
		shadowExtent = 120,
	}
	o.Gui.Enabled = false
end
fs.writeFile(root .. "/build/preview/egg_video_shots.json", serde.encode("json", shots))
print(`{frames} video frames at {fps} fps ({timeline.Total} s); panel at {shownAt} s, prompts at {promptAt} s`)
local _ = PopTheme
