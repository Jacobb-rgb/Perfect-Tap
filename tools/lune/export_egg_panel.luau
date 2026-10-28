--[[
	The EGGS temple's egg panels (owner 2026-10-28: "make the UI for pets
	like this", two pictures of other egg games; round 2: "yes, a big E;
	make it even cooler; add opening by 10") for the owner, rendered without
	Studio. tools/preview is a three.js approximation of Roblox: the
	lighting, the fonts and the 3D pictures are close, not exact; the
	golems' live 3D pictures are the preview icons (tools/preview/render_icons).

	Built with the game's own code: WorldBuilder (the temple and its eggs),
	UI/EggPanel (laid out and filled the way EggPanelController does, over
	the egg's top: EggPanel.spotOf), UI/EggPrompt (the big round E at the
	prompt's point), CapsuleView's opening overlay with UI/Confetti, and the
	egg's hop (DecorController.bounceAt). The tweens the game plays are posed
	here frame by frame with the same numbers.

	  lune run tools/lune/export_egg_panel.luau [fps=20] [video=hatch|walk]
	  -> build/preview/egg_panel_base.json        the world, once (without the Stone egg: it hops)
	     build/preview/egg_panel/*.json           the egg, the miner and the ring (extra parts) and the UI per still / frame
	     build/preview/egg_panel_shots.json       the stills (round 4, egg4_*: the names under the
	                                              silhouettes; touch at 667 x 375 and 844 x 390 with the
	                                              thumbstick zone, the touch buttons and the top bar outlined;
	                                              the walk Stone -> Crystal -> Royal -> Stone with real models)
	     build/preview/egg_video_shots.json       the round 2 video's frames (video "walk")
	     build/preview/egg_hatch_{stone,crystal}_shots.json   the hatch video's two parts (video "hatch",
	                                              the default: a Common hatch, Open 10, a Mythic hatch)
	then (icons first: lune run tools/lune/export_icon_parts.luau; node tools/preview/render_icons.mjs golem_* capsule_*):
	  SHOTS_EXTRA=build/preview/egg_panel_shots.json node tools/preview/render.mjs egg_panel_base
	  node tools/preview/render_shot_frames.mjs build/preview/egg_video_shots.json vejce_e2 20
	  node tools/preview/render_shot_frames.mjs build/preview/egg_hatch_stone_shots.json vejce_hatch_a 20
	  node tools/preview/render_shot_frames.mjs build/preview/egg_hatch_crystal_shots.json vejce_hatch_b 20
	The hatch (UI/HatchFx) poses a real 3D egg (and the golem) in the world
	where the opening's hero viewport shows it, in front of a dark see-through
	plane standing in for the overlay's dim (the renderer draws no viewports).
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
local videoMode = process.args[2] or "hatch"
local CF = Loader.CFrame
local V3 = roblox.Vector3
local V2 = roblox.Vector2
local UDim2 = roblox.UDim2
local Color3 = roblox.Color3
local Instance = roblox.Instance
local Enum = roblox.Enum
local rgb = Color3.fromRGB

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")
local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")
local EggPrompt = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPrompt")
local Confetti = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Confetti")
local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
local DecorController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.DecorController")
local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
local Font = roblox.Font

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

type Spot = { Center: any, Top: number, Prompt: any, Bottom: number, Half: number }
local spots: { [string]: Spot } = {}
for id, model in eggs do
	local center, top, prompt, bottom, half = EggPanel.spotOf(model, front)
	spots[id] = { Center = center, Top = top, Prompt = prompt, Bottom = bottom, Half = half }
end

if process.args[1] == "probe" then
	print("front", front, "right", right, "ground", ground)
	for id, s in spots do
		print(id, s.Center, s.Top, s.Prompt, s.Bottom, s.Half)
	end
	return
end

-- the Stone egg leaves the base world: it hops in the frames (extra parts)
local stoneEgg = eggs.Stone
local stoneParts: { { Part: any, CFrame: any } } = {}
for _, d in stoneEgg:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(stoneParts, { Part = d, CFrame = d.CFrame })
	end
end
stoneEgg.Parent = nil

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
-- the small phone: 667 x 375 pt (an iPhone SE / 8) at 2x
local PHONE_SMALL: Screen = { W = 1334, H = 750, Pixel = 0.62 * 2, Phone = true, Fov = 70 }

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
local function knownSet(extra: { string }?): { [string]: boolean }
	local list = {}
	for i, kind in OWNED do
		list[i] = { Id = i, Kind = kind }
	end
	for _, kind in extra or {} do
		table.insert(list, { Id = #list + 1, Kind = kind })
	end
	return EggPanel.known({ Golems = { Owned = list, Equipped = {}, Pending = {} } })
end

-- The opens as the window's buys would make them (level 1, rich enough, room).
local function opensOf(egg: string): { any }
	local capsule = CapsuleConfig.ById[egg]
	local buys = {}
	for _, count in CapsuleConfig.Counts do
		if capsule.Currency == "Robux" then
			local key = CapsuleConfig.product(egg, count)
			local product = if key then MonetizationConfig.get(key) else nil
			local live = key ~= nil and MonetizationConfig.keyLive(key)
			table.insert(buys, {
				Count = count,
				PriceText = if live and product then `R$ {product.Robux}` else "Coming soon",
				CanBuy = live,
				Reason = if live then nil else "ComingSoon",
			})
		else
			table.insert(buys, { Count = count, Price = CapsuleConfig.price(egg, count, 1), CanBuy = true })
		end
	end
	return EggPanel.opens(buys, capsule.Currency == "Robux")
end

type PanelSpec = {
	Egg: string,
	Lucky: boolean,
	Auto: boolean,
	Known: { [string]: boolean },
	Coins: number,
	Fade: number?, -- 0 shown .. 1 gone
	Pop: number?, -- the pop-in's scale (1 = done)
	Since: number?, -- seconds since it came up (the cards' pop-in, the rays, the glows; nil: at rest)
	PopCard: { [string]: number }?, -- a card that lit up: seconds since
	Pressed: number?, -- an Open button pressed (its count)
	Walk: { string }?, -- eggs the panel showed before this one: the cards get their golems' real models
}

-- The controller's modelFor (EggPanelController): one golem model per kind, built once, lent to the cards.
local models: { [string]: any } = {}
local function modelFor(kind: string): (any, any, number)
	local model = models[kind]
	if not model then
		model = GolemBuilder.build(kind)
		model:SetAttribute("Kind", kind)
		models[kind] = model
	end
	local center, radius = EggPanel.bounds(model)
	return model, center, radius
end

local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")

-- A phone's free part for the floating panel, in points (EggPanel.screen: under the HUD's teleport bar).
local function phoneScreen(screen: Screen): any
	local view = V2.new(screen.W / 2, screen.H / 2)
	local scale = screen.Pixel / 2
	local inset = HudBubble.PreviewInset
	local bar = HudBubble.topBarSize(HudBubble.layout(scale, view.X, true, false))
	return EggPanel.screen(view, inset + (HudBubble.topBarY(inset, scale) + bar.Y) * scale)
end

local function back(x: number): number
	x = math.clamp(x, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end
local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end

-- The panel over `spec.Egg` as the game draws it, placed where its billboard would be.
local function panelGui(screen: Screen, cam: Cam, spec: PanelSpec): any
	local gui = UIKit.screen("EggPanelPreview", 1)
	gui.IgnoreGuiInset = true
	gui.Scale.Scale = screen.Pixel
	local refs = EggPanel.build()
	local lines = EggPanel.lines(spec.Egg, spec.Lucky, spec.Known)
	local l = EggPanel.layout(#lines, screen.Phone, EggPanel.autoAllowed(spec.Egg))
	if spec.Walk then
		-- the eggs before: their golems' models go into the cards and move on (EggPanel.setLines)
		for _, before in spec.Walk do
			local earlier = EggPanel.lines(before, false, spec.Known)
			EggPanel.apply(refs, before, EggPanel.layout(#earlier, screen.Phone, EggPanel.autoAllowed(before)), 1)
			EggPanel.setLines(refs, earlier, modelFor)
		end
	end
	EggPanel.apply(refs, spec.Egg, l, 1)
	EggPanel.setLines(refs, lines, if spec.Walk then modelFor else nil)
	if spec.Walk then
		-- each card's picture: the golem model really in its view (the renderer draws no viewports)
		for i, card in refs.Cards do
			local kinds = {}
			for _, child in card.View:GetChildren() do
				if child:IsA("Model") then
					table.insert(kinds, child:GetAttribute("Kind"))
				end
			end
			if lines[i] then
				assert(#kinds == 1 and kinds[1] == lines[i].Golem, `{spec.Egg} card {i}: {table.concat(kinds, "+")}`)
			end
			card.Picture:SetAttribute("Icon", if #kinds == 1 then "golem_" .. kinds[1] else nil)
		end
	end
	local capsule = CapsuleConfig.ById[spec.Egg]
	if capsule.Currency == "Robux" then
		local product = MonetizationConfig.get(CapsuleConfig.product(spec.Egg, 1))
		EggPanel.setPrice(refs, "Robux", `R$ {product.Robux}`, true)
	else
		local price = CapsuleConfig.price(spec.Egg, 1, 1) or 0
		EggPanel.setPrice(refs, "Coins", EggPanel.priceText(price), spec.Coins >= price)
	end
	EggPanel.setOpens(refs, opensOf(spec.Egg), if screen.Phone then nil else EggPanel.OpenKeys, nil)
	local autoShown = EggPanel.autoAllowed(spec.Egg)
	EggPanel.setAuto(refs, autoShown, spec.Auto, if screen.Phone then "" else "G", nil)
	EggPanel.setLucky(refs, spec.Lucky, autoShown)
	EggPanel.setFade(refs, spec.Fade or 0)
	-- the controller's loops and pops, posed at `since` (EggPanelController.startLoops / popCards)
	local since = spec.Since or 10
	local n = 0
	for i, card in refs.Cards do
		if card.Frame.Visible then
			local delay = 0.08 + n * EggPanel.CardStagger
			n += 1
			card.PopScale.Scale = if since < delay then 0.3 else 0.3 + 0.7 * back((since - delay) / 0.24)
			if spec.PopCard and lines[i] and spec.PopCard[lines[i].Golem] then
				local u = spec.PopCard[lines[i].Golem]
				card.PopScale.Scale = 1.35 - 0.35 * back(u / 0.35)
			end
			card.Rays.Rotation = (since / EggPanel.RaySpeed) * 360 + i * 9
			if card.Glow.Visible then
				local wave = 0.5 - 0.5 * math.cos(since / (EggPanel.GlowPeriod / 2) * math.pi)
				card.Glow.BackgroundTransparency = 0.55 + (0.82 - 0.55) * wave
				local rest = card.Picture:GetAttribute("Rest") :: number
				card.Picture.Position = UDim2.fromOffset(l.Card / 2, rest - 3 * (0.5 - 0.5 * math.cos(since / 0.9 * math.pi)))
			end
		end
	end
	for _, open in refs.Opens do
		if spec.Pressed == open.Count then
			local s = Instance.new("UIScale")
			s.Scale = 0.9
			s.Parent = open.Button
		end
	end
	local s = spots[spec.Egg]
	local panel = refs.Root
	panel.Parent = gui
	local pop = spec.Pop or 1
	refs.Scale.Scale = pop
	if l.Beside then
		-- (touch: floating beside the egg, clear of the thumbstick, the touch buttons and the top bar:
		-- EggPanelController.float with EggPanel.floatAt, in points)
		local look = (cam.Target - cam.Position).Unit
		local camRight = look:Cross(up).Unit
		local mx, my = project(screen, cam, s.Center)
		local sx = project(screen, cam, s.Center + camRight * s.Half)
		local px = project(screen, cam, s.Prompt)
		local scale = screen.Pixel / 2
		local reach = math.max(math.abs(sx - mx), px - mx + EggPrompt.Width * screen.Pixel / 2) / 2
		local size = V2.new(math.ceil(l.Width * scale), math.ceil(l.Height * scale))
		local at = EggPanel.floatAt(phoneScreen(screen), size, V2.new(mx / 2, my / 2), reach)
		panel.AnchorPoint = V2.new(0, 0)
		panel.Position = UDim2.fromOffset(at.X * 2 / screen.Pixel, at.Y * 2 / screen.Pixel)
		gui:SetAttribute("FloatX", at.X)
		gui:SetAttribute("FloatY", at.Y)
		gui:SetAttribute("FloatW", size.X)
		gui:SetAttribute("FloatH", size.Y)
	else
		local x, y = project(screen, cam, V3.new(s.Center.X, s.Top + EggPanel.Lift, s.Center.Z))
		-- (the preview scales a UIScale about the frame's centre; the game about its bottom edge)
		panel.Position = UDim2.fromOffset(x / screen.Pixel, y / screen.Pixel - l.Height * (1 - pop) / 2)
	end
	return gui
end

type PromptSpec = { Egg: string, Fade: number?, Since: number?, Pressed: number?, Key: string? }

-- The big round E (UI/EggPrompt) at the egg's prompt point, posed `Since` seconds after it showed.
local function promptGui(screen: Screen, cam: Cam, spec: PromptSpec): any
	local gui = UIKit.screen("EggPromptPreview", 2)
	gui.IgnoreGuiInset = true
	gui.Scale.Scale = screen.Pixel
	local p = EggPrompt.build()
	local capsule = CapsuleConfig.ById[spec.Egg]
	local price
	if capsule.Currency == "Robux" then
		local product = MonetizationConfig.get(CapsuleConfig.product(spec.Egg, 1))
		price = EggPanel.promptText(true, nil, `R$ {product.Robux}`, true)
	else
		price = EggPanel.promptText(false, CapsuleConfig.price(spec.Egg, 1, 1), "", true)
	end
	EggPrompt.setText(p, "Buy Egg!", price, true)
	EggPrompt.setKey(p, spec.Key or (if screen.Phone then "Tap" else "E"), nil)
	EggPrompt.setGlow(p, capsule.Glow)
	EggPrompt.setFade(p, spec.Fade or 0)
	local since = spec.Since or 0.45
	-- the ring breathes, the light band sweeps now and then, the disc squashes when pressed
	p.GlowScale.Scale = 1 + 0.14 * (0.5 - 0.5 * math.cos(since / (EggPanel.GlowPeriod / 2) * math.pi))
	local cycle = since % EggPrompt.ShineEvery
	local sweep = (cycle - (EggPrompt.ShineEvery - EggPrompt.ShineTime)) / EggPrompt.ShineTime
	p.Shine.Offset = V2.new(if sweep >= 0 then -1 + 2 * sweep else -1, 0)
	if spec.Pressed then
		p.Press.Scale = 0.84 + 0.16 * back(spec.Pressed / 0.22)
	end
	local x, y = project(screen, cam, spots[spec.Egg].Prompt)
	p.Root.Parent = gui
	p.Root.Position = UDim2.fromOffset(x / screen.Pixel, y / screen.Pixel)
	return gui
end

--[[
	A phone's reserved parts, outlined (the HUD isn't drawn here): the
	thumbstick's start zone (left 40 %, lower two thirds), the touch
	buttons in the bottom right (BoostView.TouchButtons) and the teleport
	bar's foot; the floating panel keeps its buttons out of them.
]]
local function zonesGui(screen: Screen): any
	local gui = UIKit.screen("PhoneZones", 3)
	gui.IgnoreGuiInset = true
	gui.Scale.Scale = 2 -- (points)
	local w, h = screen.W / 2, screen.H / 2
	local free = phoneScreen(screen)
	local function box(name: string, x: number, y: number, bw: number, bh: number, color: any, text: string, round: boolean?)
		local f = UIKit.new("Frame", {
			Name = name,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(bw, bh),
		}, gui)
		UIKit.corner(f, if round then 999 else 6)
		UIKit.stroke(f, 1.5, color, 0.1)
		UIKit.new("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.new(1, -8, 0, 12),
			Text = text,
			TextColor3 = rgb(255, 255, 255),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, f)
	end
	box("Thumbstick", 0, h / 3, w * EggPanel.ZoneWidth, h * 2 / 3, rgb(255, 80, 80), "thumbstick zone (left 40 %)")
	box("TopBar", 0, 0, w, free.Top, rgb(90, 160, 255), "top bar (Roblox + teleport bar)")
	local small = math.min(w, h) <= 500
	for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
		box(b.Name, w - b.Left, h - b.Top, b.Left - b.Right, b.Top - b.Bottom, rgb(255, 200, 60), b.Name, true)
	end
	return gui
end

-- Does the floating panel (panelGui's attributes, points) cover the big E at the egg's prompt? (the game hides it then)
local function covers(screen: Screen, cam: Cam, panel: any, egg: string): boolean
	local x = panel:GetAttribute("FloatX")
	if x == nil then
		return false
	end
	local px, py = project(screen, cam, spots[egg].Prompt)
	local size = V2.new(EggPrompt.Width, EggPrompt.Height) * (screen.Pixel / 2)
	return EggPanel.overlaps(
		V2.new(x, panel:GetAttribute("FloatY")),
		V2.new(panel:GetAttribute("FloatW"), panel:GetAttribute("FloatH")),
		V2.new(px / 2, py / 2) - size / 2,
		size
	)
end

-- The miner (a blocky stand-in for the player's avatar) at `feet`, facing `toward`.
local function miner(parent: any, feet: any, toward: any, step: number?)
	local look = V3.new(toward.X, feet.Y, toward.Z)
	local body = Dummy.build(parent, CF, CF.lookAt(feet, look), "idle", { shirt = rgb(70, 120, 200), pants = rgb(50, 50, 64) })
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
end

-- The Stone egg (out of the base world) turned `angle` and hopping `t` seconds into its bounce.
local function stone(parent: any, angle: number, t: number?)
	local s = spots.Stone
	local lift, tilt = 0, 0
	if t then
		lift, tilt = DecorController.bounceAt(t)
	end
	local pivot = CF.new(s.Center.X, s.Center.Y, s.Center.Z)
	local move = pivot * CF.new(0, lift, 0) * CF.Angles(0, angle, tilt) * pivot:Inverse()
	local m = Instance.new("Model")
	m.Name = "StoneEgg"
	m.Parent = parent
	for _, entry in stoneParts do
		local copy = entry.Part:Clone()
		copy.CFrame = move * entry.CFrame
		copy.Parent = m
	end
end

-- The soft ring of light on an egg's podium (EggPanelController.placeRing), `transparency` as it breathes.
local function ringAt(parent: any, egg: string, transparency: number)
	local s = spots[egg]
	local d = math.clamp(s.Half * 1.15, 2.6, 5)
	local part = Instance.new("Part")
	part.Name = "EggLightRing"
	part.Anchored = true
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = CapsuleConfig.ById[egg].Glow
	part.Transparency = transparency
	part.Size = V3.new(0.08, d, d)
	part.CFrame = CF.new(s.Center.X, s.Bottom + 0.06, s.Center.Z) * CF.Angles(0, 0, math.pi / 2)
	part.Parent = parent
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
local function standAt(egg: string, back_: number?, aside: number?): (any, Cam)
	local s = spots[egg]
	local flat = V3.new(s.Center.X, floor, s.Center.Z)
	-- (a step to the side of the egg's front: the camera over the other shoulder sees the egg)
	local feet = flat + front * 4.4 - right * 2.6
	local camPos = feet + front * (back_ or 11) - right * (aside or 6) + up * 7.5
	local target = V3.new(s.Center.X, s.Top + 1.6, s.Center.Z) - right * 0.4
	return feet, { Position = camPos, Target = target }
end

--[[
	Roblox's stock ProximityPrompts (drawn by hand: EggPanel.BigE false, the
	game then uses Roblox's own), centred on the prompt's point; Auto
	UIOffset 72 lower: a dark see-through box, the key in a white-edged
	square, the object text small over the action text.
]]
local function stockGui(screen: Screen, cam: Cam, egg: string): any
	local gui = UIKit.screen("StockPrompts", 2)
	gui.IgnoreGuiInset = true
	local k = if screen.Phone then 2 else 1 -- (points to render pixels)
	gui.Scale.Scale = k
	local x, y = project(screen, cam, spots[egg].Prompt)
	local price = EggPanel.promptText(false, CapsuleConfig.price(egg, 1, 1), "", true)
	local list = { { "Buy Egg!", price, "E" } }
	if EggPanel.autoAllowed(egg) then
		table.insert(list, { "Auto", "Off", "G" })
	end
	for i, p in list do
		local box = UIKit.new("Frame", {
			Name = "Prompt" .. i,
			AnchorPoint = V2.new(0.5, 0.5),
			BackgroundColor3 = rgb(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x / k, y / k + (i - 1) * 72),
			Size = UDim2.fromOffset(170, 72),
		}, gui)
		UIKit.corner(box, 10)
		local keyBox = UIKit.new("Frame", {
			Name = "Key",
			AnchorPoint = V2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(36, 36),
			Size = UDim2.fromOffset(44, 44),
		}, box)
		UIKit.corner(keyBox, 8)
		UIKit.stroke(keyBox, 2, rgb(255, 255, 255), 0)
		UIKit.new("TextLabel", {
			Name = "Letter",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			Size = UDim2.fromScale(1, 1),
			Text = p[3],
			TextColor3 = rgb(255, 255, 255),
			TextSize = 22,
		}, keyBox)
		UIKit.new("TextLabel", {
			Name = "Object",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium),
			Position = UDim2.fromOffset(72, 12),
			Size = UDim2.new(1, -80, 0, 18),
			Text = p[2],
			TextColor3 = rgb(200, 200, 200),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, box)
		UIKit.new("TextLabel", {
			Name = "Action",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			Position = UDim2.fromOffset(72, 32),
			Size = UDim2.new(1, -80, 0, 26),
			Text = p[1],
			TextColor3 = rgb(255, 255, 255),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, box)
	end
	return gui
end

-- the same egg, the big round E (EggPanel.BigE true) and Roblox's stock prompt (false): for the owner to pick
do
	local feet, cam = standAt("Stone")
	for _, look in { "bige", "stock" } do
		local extra = Instance.new("Model")
		miner(extra, feet, spots.Stone.Center)
		stone(extra, 0.3, nil)
		ringAt(extra, "Stone", 0.5)
		local panel = panelGui(PC, cam, { Egg = "Stone", Lucky = false, Auto = false, Known = knownSet(), Coins = 1e9, Since = 2.3 })
		local prompt = if look == "bige" then promptGui(PC, cam, { Egg = "Stone", Since = 0.45 }) else stockGui(PC, cam, "Stone")
		still(`egg3_stone_pc_{look}`, PC, cam, extra, { panel, prompt })
	end
end

-- the Royal egg's Robux prices as they show once its product ids are live (preview-only ids)
local royalIds = {}
for _, count in CapsuleConfig.Counts do
	local product = MonetizationConfig.get(CapsuleConfig.product("Royal", count))
	royalIds[product] = product.Id
	product.Id = count
end

for _, screen in { PC, PHONE, PHONE_SMALL } do
	local tag = if screen == PHONE_SMALL then "phone667" elseif screen.Phone then "phone844" else "pc"
	for _, egg in { "Stone", "Crystal", "Royal" } do
		if screen.Phone and egg == "Crystal" then
			continue
		end
		local feet, cam = standAt(egg)
		local lucky = egg == "Crystal"
		local auto = egg == "Crystal"
		local extra = Instance.new("Model")
		miner(extra, feet, spots[egg].Center)
		stone(extra, 0.3, nil)
		ringAt(extra, egg, 0.5)
		local panel = panelGui(screen, cam, { Egg = egg, Lucky = lucky, Auto = auto, Known = knownSet(), Coins = 1e9, Since = 2.3 })
		local guis = { panel }
		if not covers(screen, cam, panel, egg) then
			table.insert(guis, promptGui(screen, cam, { Egg = egg, Since = 0.45 }))
		end
		if screen.Phone then
			table.insert(guis, zonesGui(screen))
		end
		still(`egg4_{string.lower(egg)}_{tag}`, screen, cam, extra, guis)
	end
end

-- walking from egg to egg (Stone, Crystal, Royal, Stone): every card shows its own golem's model
do
	local walk = { "Stone", "Crystal", "Royal", "Stone" }
	for i, egg in walk do
		local feet, cam = standAt(egg)
		local extra = Instance.new("Model")
		miner(extra, feet, spots[egg].Center)
		stone(extra, 0.3, nil)
		ringAt(extra, egg, 0.5)
		local before = table.move(walk, 1, i - 1, 1, {})
		local panel =
			panelGui(PC, cam, { Egg = egg, Lucky = false, Auto = false, Known = knownSet(), Coins = 1e9, Since = 2.3, Walk = before })
		still(`egg4_walk{i}_{string.lower(egg)}`, PC, cam, extra, { panel, promptGui(PC, cam, { Egg = egg, Since = 0.45 }) })
	end
end

fs.writeFile(root .. "/build/preview/egg_panel_shots.json", serde.encode("json", stills))
local n = 0
for _ in stills do
	n += 1
end
print(`{n} stills`)

---------------------------------------------------------------- the round 2 video (video "walk")

if videoMode == "walk" then
	--[[
	Walk up to the Stone egg (it hops, its ring lights, its panel pops in
	card by card, the big E comes up), press E, the opening (the egg shakes,
	bursts, a Silver Squire wakes: NEW! and confetti), OK (its card lights
	up), then a click on Open 10: the grid of ten, more confetti.
]]
	for product, id in royalIds do
		product.Id = id
	end
	local VIDEO = PC
	local GOLEM = "SilverSquire"
	local TEN = {
		"PebbleGolem",
		"CopperTinker",
		"TinTumbler",
		"CoalChomper",
		"QuartzSprite",
		"PebbleGolem",
		"JadeGardener",
		"CopperTinker",
		"SilverSquire",
		"AmethystAcolyte",
	}
	local TEN_NEW = { [3] = true, [7] = true, [10] = true }
	local s = spots.Stone
	local endFeet, cam = standAt("Stone", 18, 8)
	local startFeet = endFeet + front * 11
	local T = {
		WalkEnd = 1.6,
		Press = 2.9,
		Open = 3.15,
		Shake = 1.35,
		Ok = 6.7,
		Click10 = 7.9,
		Open10 = 8.15,
		Total = 12.4,
	}
	local price = CapsuleConfig.price("Stone", 1, 1) or 0
	local price10 = CapsuleConfig.price("Stone", 10, 1) or 0

	local function opening(): any
		local o = CapsuleView.buildOpening(false)
		o.Gui.Scale.Scale = VIDEO.Pixel
		local designW, designH = VIDEO.W / VIDEO.Pixel, (VIDEO.H - 36) / VIDEO.Pixel
		CapsuleView.layoutOpening(o, false, designW, designH)
		for _, glow in o.Rays:GetChildren() do
			if glow:IsA("Frame") and string.sub(glow.Name, 1, 4) == "Glow" then
				glow.Visible = false -- (the preview's icon stands in for the hero viewport: no disc over it)
			end
		end
		return o
	end

	-- the overlay posed `u` seconds into an opening of `kinds` (one: the hero; ten: the grid)
	local function poseOpening(u: number, kinds: { string }, new: { [number]: boolean }, again: string): any
		local o = opening()
		local pieces = Confetti.build(o.Gui, Confetti.Count, 8)
		local dimBase = o.Dim.BackgroundTransparency
		o.Gui.Enabled = true
		o.Dim.BackgroundTransparency = dimBase + (1 - dimBase) * (1 - ease(u / 0.15))
		o.Rays.Rotation = u * 80
		local burstAt = T.Shake
		if u < burstAt then
			local p = u / burstAt
			o.Hero:SetAttribute("Icon", "capsule_Stone")
			o.Hero.Rotation = math.sin(u * (16 + 14 * p)) * (3 + 17 * p * p)
			o.Hero.Size = UDim2.fromOffset(300 * (1 + 0.05 * p), 300 * (1 + 0.05 * p))
			o.Rays.Visible = false
			o.Plate.Visible = false
			o.Skip.Parent.Visible = true
			o.Ok.Parent.Visible = false
			o.Again.Parent.Visible = false
			o.Hint.Text = `Click or Space to skip{CapsuleView.Separator}Backspace: skip all`
			return o
		end
		local v = u - burstAt
		o.Skip.Parent.Visible = false
		o.Ok.Parent.Visible = true
		o.Again.Parent.Visible = true
		o.Again.Text = again
		o.Hint.Text = ""
		o.Note.Text = ""
		if #kinds == 1 then
			local kind = kinds[1]
			o.Hero:SetAttribute("Icon", "golem_" .. kind)
			o.Hero.Rotation = 0
			local grow = 0.6 + 0.4 * back(v / 0.35)
			o.Hero.Size = UDim2.fromOffset(300 * grow, 300 * grow)
			o.Flash.BackgroundColor3 = CapsuleView.rarityColor(kind):Lerp(Color3.new(1, 1, 1), 0.45)
			o.Flash.BackgroundTransparency = 1 - 0.9 * (1 - ease(v / 0.45))
			o.Rays.Visible = true
			CapsuleView.setRayColor(o, CapsuleView.rarityColor(kind))
			CapsuleView.setPlate(o, kind, new[1] == true)
			o.Counter.Text = ""
			if new[1] then
				Confetti.pose(pieces, V2.new(0.5, o.Hero.Position.Y.Scale), 11, v)
			end
		else
			o.Hero:SetAttribute("Icon", nil)
			o.Hero.Visible = false
			o.Plate.Visible = false
			o.Flash.BackgroundColor3 = Color3.new(1, 1, 1)
			o.Flash.BackgroundTransparency = 1 - 0.6 * (1 - ease(v / 0.45))
			o.Counter.Text = `{#kinds} GOLEMS WOKE UP!`
			local best = CapsuleView.best(kinds)
			CapsuleView.setGrid(o, kinds, new, table.find(kinds, best), nil)
			o.Grid.Visible = true
			o.Rays.Visible = false
			for i, cell in o.Cells do
				local at = (i - 1) * 0.09
				cell.Frame.Visible = v >= at
				cell.Scale.Scale = if v >= at then 0.3 + 0.7 * back((v - at) / 0.25) else 0.3
			end
			Confetti.pose(pieces, V2.new(0.5, 0.45), 23, v)
		end
		return o
	end

	local frames = math.floor(T.Total * fps)
	local shots = {}
	local shownAt: number? = nil
	local promptAt: number? = nil
	for i = 0, frames - 1 do
		local t = i / fps
		local extra = Instance.new("Model")
		-- the walk: from the plaza up the steps to the egg
		local k = math.clamp(t / T.WalkEnd, 0, 1) -- (a steady walk)
		local feet = startFeet:Lerp(endFeet, k)
		local onDais = (feet - frame.Position):Dot(front) < 9
		feet = V3.new(feet.X, if onDais then floor else ground, feet.Z)
		local walking = t < T.WalkEnd
		miner(extra, feet, s.Center, if walking then t * 11 else nil)
		-- the panel, the ring, the egg's hop and the big E come up where the game shows them
		local distance = (s.Center - feet - V3.new(0, 3, 0)).Magnitude
		if not shownAt and distance <= EggPanel.ShowRange then
			shownAt = t
		end
		if not promptAt and (s.Prompt - feet - V3.new(0, 3, 0)).Magnitude <= EggPanel.PromptDistance then
			promptAt = t
		end
		stone(extra, 0.3 + t * 0.5, if shownAt then t - shownAt else nil)
		if shownAt then
			ringAt(extra, "Stone", 0.45 + 0.27 * (0.5 - 0.5 * math.cos((t - shownAt) / 1.2 * math.pi)))
		end
		local guis = { UIKit.screen("Empty", 0) } -- (never an empty list: JSON would make it an object)
		local woke1 = t >= T.Ok
		local known = knownSet(if woke1 then { GOLEM } else nil)
		if shownAt then
			local since = t - shownAt
			table.insert(
				guis,
				panelGui(VIDEO, cam, {
					Egg = "Stone",
					Lucky = false,
					Auto = false,
					Known = known,
					Coins = 1e9,
					Fade = 1 - ease(since / 0.18),
					Pop = 0.82 + 0.18 * back(since / 0.26),
					Since = since,
					PopCard = if woke1 and t < T.Ok + 0.6 then { [GOLEM] = t - T.Ok - 0.15 } else nil,
					Pressed = if t >= T.Click10 and t < T.Click10 + 0.15 then 10 else nil,
				})
			)
		end
		local overlay = (t >= T.Open and t < T.Ok) or t >= T.Open10
		if promptAt and not overlay then
			local since = t - promptAt
			table.insert(
				guis,
				promptGui(VIDEO, cam, {
					Egg = "Stone",
					Fade = 1 - math.clamp(since / 0.12, 0, 1),
					Since = since,
					Pressed = if t >= T.Press and t < T.Press + 0.25 then t - T.Press else nil,
				})
			)
		end
		-- the openings (CapsuleView's overlay, posed like CapsuleController plays them)
		if t >= T.Open and t < T.Ok then
			table.insert(guis, poseOpening(t - T.Open, { GOLEM }, { [1] = true }, "OPEN 1 AGAIN  $" .. EggPanel.priceText(price)).Gui)
		elseif t >= T.Open10 then
			table.insert(guis, poseOpening(t - T.Open10, TEN, TEN_NEW, "OPEN 10 AGAIN  $" .. EggPanel.priceText(price10)).Gui)
		end
		local name = string.format("v2_%04d", i)
		fs.writeFile(OUT .. "/" .. name .. "_fx.json", serde.encode("json", Export.collect(extra)))
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
	end
	fs.writeFile(root .. "/build/preview/egg_video_shots.json", serde.encode("json", shots))
	print(`{frames} video frames at {fps} fps ({T.Total} s); panel at {shownAt} s, the E at {promptAt} s`)
end

---------------------------------------------------------------- the hatch video (video "hatch")

--[[
	Two parts (a fixed camera each): at the Stone egg, walk up, press E: a
	Common hatch (a NEW Tin Tumbler), OK, then Open 10 (ten eggs wobble
	together, burst one after another, the grid); at the Crystal egg, press
	E: a Mythic hatch (Heartstone Colossus: the longest build-up, the most
	light, sparkles and the screen's tint).
]]
if videoMode == "hatch" then
	local VIDEO = PC
	local W, H = VIDEO.W, VIDEO.H
	local designW, designH = W / VIDEO.Pixel, (H - 36) / VIDEO.Pixel
	-- the hero viewport on screen (CapsuleView.layoutOpening's rule)
	local heroSize = math.clamp(math.floor(designH * 0.5), 220, 460)
	local heroY = math.max(heroSize / 2 + 40, designH * 0.36)
	local heroPx = heroSize * VIDEO.Pixel
	local heroX, heroYpx = W / 2, 36 + heroY * VIDEO.Pixel
	local D = 12 -- studs from the camera where the hero stands in the world
	local TAN35 = math.tan(math.rad(35))
	local TAN15 = math.tan(math.rad(15))

	-- the hero's place in the world: on the camera's ray through the viewport's centre, facing the camera
	local function heroFrame(cam: Cam, depth: number): any
		local look = CF.lookAt(cam.Position, cam.Target)
		local x = (heroX / W * 2 - 1) * TAN35 * (W / H)
		local y = (1 - heroYpx / H * 2) * TAN35
		local dir = ((look * CF.new(x, y, -1)).Position - cam.Position).Unit
		local at = cam.Position + dir * depth
		return CF.lookAt(at, cam.Position) * CF.Angles(0, math.pi, 0) * CF.Angles(0, -0.32, 0)
	end
	-- how big a stud of the viewport (its camera `dist` away, FOV 30) is against a stud of the world at `depth`
	local function scaleFor(dist: number, depth: number): number
		local viewport = heroPx / (2 * dist * TAN15)
		local world = H / (2 * depth * TAN35)
		return viewport / world
	end
	-- a model's parts scaled by k about its origin (as built)
	local function scaled(model: any, k: number): any
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local cf = d.CFrame
				d.CFrame = CF.new(cf.Position * k) * (cf - cf.Position)
				d.Size *= k
			end
		end
		return model
	end
	-- the overlay's dim, as a dark see-through plane behind the hero (tinted for a Mythic)
	local function dimPlane(parent: any, cam: Cam, alpha: number, tint: any?, tintAmount: number?)
		local look = (cam.Target - cam.Position).Unit
		local at = cam.Position + look * (D + 7)
		local plane = Instance.new("Part")
		plane.Name = "DimPlane"
		plane.Anchored = true
		plane.Size = V3.new(140, 90, 0.1)
		plane.CFrame = CF.lookAt(at, at + look)
		local base = rgb(12, 8, 16)
		plane.Color = if tint then base:Lerp(tint, tintAmount or 0) else base
		plane.Material = Enum.Material.Neon -- (unlit: as dark as the overlay's dim)
		plane.Color = plane.Color:Lerp(Color3.new(0, 0, 0), 0.2)
		plane.Transparency = 1 - 0.82 * alpha
		plane.Parent = parent
	end
	local function overlay(): (any, any)
		local o = CapsuleView.buildOpening(false)
		o.Gui.Scale.Scale = VIDEO.Pixel
		CapsuleView.layoutOpening(o, false, designW, designH)
		o.Dim.BackgroundTransparency = 1 -- (the world's dim plane stands in for it)
		for _, glow in o.Rays:GetChildren() do
			if glow:IsA("Frame") and string.sub(glow.Name, 1, 4) == "Glow" then
				glow.Visible = false -- (the soft discs would cover the 3D golem in the preview)
			end
		end
		o.Gui.Enabled = true
		local fx = HatchFx.overlay(o.Gui)
		HatchFx.place(fx, o.Hero.Position, o.Hero.Size.X.Offset)
		return o, fx
	end
	local function some(list: { any }, n: number): { any }
		local out = {}
		for i = 1, math.min(n, #list) do
			out[i] = list[i]
		end
		return out
	end

	type Hatch = { Kinds: { string }, New: { [number]: boolean }, Egg: string, Again: string }

	--[[
		One opening `t` seconds in, posed like CapsuleController plays it:
		the eggs (HatchFx.pose) and the golem in the world, the overlay
		(the leak, the flash, the shards, the sparkles, the aura, the rays,
		the plate or the grid, the buttons). Returns the overlay's gui.
	]]
	local function poseHatch(parent: any, cam: Cam, t: number, h: Hatch): any
		local o, fx = overlay()
		local best = CapsuleView.best(h.Kinds) or h.Kinds[1]
		local order = GolemConfig.order(best)
		local plan = HatchFx.plan(order)
		local color = CapsuleView.rarityColor(best)
		local capsule = CapsuleConfig.ById[h.Egg]
		HatchFx.paint(fx, capsule.Shell or capsule.Color, color)
		local n = #h.Kinds
		local spotsOf, dist = HatchFx.arrange(n)
		local last = plan.Shake + (n - 1) * HatchFx.Sequence
		local golemAt = last + HatchFx.BurstTime
		local tint = nil
		local tintAmount = 0
		-- the dim comes in fast
		o.Rays.Rotation = t * 80
		if t < golemAt then
			-- the eggs: wobbling together, bursting one after another
			local lean = 1 - 0.12 * math.clamp(t / plan.Shake, 0, 1)
			local depth = D * lean
			local k = scaleFor(dist, D)
			local frame = heroFrame(cam, depth)
			for i, spot in spotsOf do
				local model = scaled(GolemBuilder.capsule(h.Egg), k)
				local rec = HatchFx.record(model)
				HatchFx.pose(rec, frame * CF.new(spot * k), t, plan.Shake + (i - 1) * HatchFx.Sequence, plan, color, n == 1)
				model.Parent = parent
			end
			HatchFx.setLeak(fx, if t < plan.Shake then t else nil, plan, color)
			o.Rays.Visible = false
			o.Plate.Visible = false
			o.Skip.Parent.Visible = true
			o.Ok.Parent.Visible = false
			o.Again.Parent.Visible = false
			o.Hint.Text = `Click or Space to skip{CapsuleView.Separator}Backspace: skip all`
			local u = t - plan.Shake
			if u >= 0 then
				o.Flash.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45)
				o.Flash.BackgroundTransparency = 1 - 0.9 * (1 - ease(u / 0.45))
				Confetti.pose(fx.Shards, V2.new(0.5, 0.5), 5, u)
			end
		else
			local v = t - golemAt
			o.Skip.Parent.Visible = false
			o.Ok.Parent.Visible = true
			o.Again.Parent.Visible = true
			o.Again.Text = h.Again
			o.Hint.Text = ""
			o.Note.Text = ""
			Confetti.pose(fx.Shards, V2.new(0.5, 0.5), 5, v + HatchFx.BurstTime)
			if n == 1 then
				local kind = h.Kinds[1]
				-- the golem: the camera rushes in, it hops and turns, it pops with a bounce
				local golem = GolemBuilder.build(kind)
				local height = golem:GetAttribute("Height") or 3
				local hd = height * 2.9 + 1
				local kk = math.clamp(v / 0.35, 0, 1)
				local backK = 1 + 2.2 * (kk - 1) ^ 3 + 1.2 * (kk - 1) ^ 2
				local rush = 1 / (2.4 - 1.4 * backK)
				local s = scaleFor(hd, D) * rush * HatchFx.popAt(v)
				local hop = math.max(0, math.sin(math.clamp(v / 0.45, 0, 1) * math.pi)) * 0.6
				scaled(golem, s)
				local place = heroFrame(cam, D) * CF.new(0, (hop - height / 2) * s, 0) * CF.Angles(0, math.sin(v * 0.9) * 0.6, 0)
				for _, d in golem:GetDescendants() do
					if d:IsA("BasePart") then
						d.CFrame = place * d.CFrame
					end
				end
				golem.Parent = parent
				-- SOLID (owner 2026-10-28): no flash over the golem; the rays, the aura and the
				-- tint sit UNDER the hero in the game, so here they are drawn behind the 3D
				-- golem (plain plastic: no bloom bleeding over it)
				o.Flash.BackgroundTransparency = 1
				o.Rays.Visible = false
				HatchFx.setAura(fx, color, 0)
				local behind = heroFrame(cam, D + 3)
				local glowColor = color:Lerp(Color3.new(1, 1, 1), 0.25)
				local pulse = 0.4 + 0.6 * back(v / 0.5)
				local r = height * scaleFor(hd, D) * 1.25 * pulse
				local aura = Instance.new("Part")
				aura.Name = "Aura"
				aura.Anchored = true
				aura.Shape = Enum.PartType.Cylinder
				aura.Material = Enum.Material.SmoothPlastic
				aura.Color = glowColor
				aura.Transparency = if order >= 4 then 0.35 else 0.6
				aura.Size = V3.new(0.05, r, r)
				aura.CFrame = behind * CF.Angles(0, math.pi / 2, 0)
				aura.Parent = parent
				for i = 1, 12 do
					local ray = Instance.new("Part")
					ray.Name = "Ray"
					ray.Anchored = true
					ray.Material = Enum.Material.SmoothPlastic
					ray.Color = glowColor
					ray.Transparency = if order >= 4 then 0.45 else 0.65
					local long = r * 1.6
					ray.Size = V3.new(long, 0.25 * r / 3, 0.04)
					ray.CFrame = behind * CF.new(0, 0, 0.3) * CF.Angles(0, 0, (i - 1) * math.pi / 6 + v * 0.25) * CF.new(long / 2, 0, 0)
					ray.Parent = parent
				end
				CapsuleView.setPlate(o, kind, h.New[1] == true)
				o.Counter.Text = ""
				if plan.Sparkles > 0 then
					Confetti.pose(some(fx.Sparkles, plan.Sparkles), V2.new(0.5, 0.5), 9, v)
				end
				if h.New[1] then
					Confetti.pose(fx.Confetti, V2.new(0.5, 0.5), 13, v)
				end
				if plan.Tint and v < HatchFx.TintTime then
					tint, tintAmount = color, 0.35 * (1 - v / HatchFx.TintTime) -- (the backdrop only)
				end
			else
				o.Hero.Visible = false
				o.Plate.Visible = false
				o.Counter.Text = `{n} GOLEMS WOKE UP!`
				CapsuleView.setGrid(o, h.Kinds, h.New, table.find(h.Kinds, best), nil)
				o.Grid.Visible = true
				o.Rays.Visible = order >= 4
				for i, cell in o.Cells do
					local at = (i - 1) * 0.09
					cell.Frame.Visible = v >= at
					cell.Scale.Scale = if v >= at then 0.3 + 0.7 * back((v - at) / 0.25) else 0.3
				end
				Confetti.pose(fx.Confetti, V2.new(0.5, 0.5), 17, v)
				o.Flash.BackgroundTransparency = 1 -- (no flash over the grid's golems)
			end
		end
		dimPlane(parent, cam, ease(t / 0.15), tint, tintAmount)
		return o.Gui
	end

	local function writeFrames(prefix: string, cam: Cam, total: number, frameAt: (number, any) -> { any }): any
		local shots = {}
		local frames = math.floor(total * fps)
		for i = 0, frames - 1 do
			local t = i / fps
			local extra = Instance.new("Model")
			local guis = { UIKit.screen("Empty", 0) }
			for _, gui in frameAt(t, extra) do
				table.insert(guis, gui)
			end
			local name = string.format("%s_%04d", prefix, i)
			fs.writeFile(OUT .. "/" .. name .. "_fx.json", serde.encode("json", Export.collect(extra)))
			fs.writeFile(OUT .. "/" .. name .. "_ui.json", serde.encode("json", UiExport.export(guis)))
			shots[name] = {
				scene = "egg_panel_base",
				extra = "egg_panel/" .. name .. "_fx",
				ui = "egg_panel/" .. name .. "_ui",
				width = W,
				height = H,
				uiInset = 36,
				position = { cam.Position.X, cam.Position.Y, cam.Position.Z },
				target = { cam.Target.X, cam.Target.Y, cam.Target.Z },
				fov = VIDEO.Fov,
				preset = "Surface",
				shadowExtent = 120,
				-- (the sun from behind the camera: the golem's front lit like the hero view's key light)
				sunDir = { front.X * 0.7 + right.X * 0.2, 0.68, front.Z * 0.7 + right.Z * 0.2 },
			}
		end
		print(`{prefix}: {frames} frames ({total} s)`)
		return shots
	end

	local price1 = CapsuleConfig.price("Stone", 1, 1) or 0
	local price10 = CapsuleConfig.price("Stone", 10, 1) or 0
	local COMMON = "TinTumbler"
	local TEN = {
		"PebbleGolem",
		"CopperTinker",
		"CoalChomper",
		"QuartzSprite",
		"PebbleGolem",
		"JadeGardener",
		"CopperTinker",
		"SilverSquire",
		"AmethystAcolyte",
		"EmberImp",
	}
	local TEN_NEW = { [6] = true, [8] = true, [9] = true }

	-- part A: the Stone egg
	do
		local endFeet, cam = standAt("Stone", 18, 8)
		local startFeet = endFeet + front * 10
		local A = { WalkEnd = 1.4, Press = 1.8, Hatch = 2.0, Ok = 0, Click10 = 0, Ten = 0, Total = 0 }
		local commonPlan = HatchFx.plan(GolemConfig.order(COMMON))
		local commonEnd = A.Hatch + commonPlan.Shake + HatchFx.BurstTime + 1.6
		A.Ok = commonEnd
		A.Click10 = A.Ok + 0.5
		A.Ten = A.Click10 + 0.25
		local tenBest = CapsuleView.best(TEN) or TEN[1]
		local tenPlan = HatchFx.plan(GolemConfig.order(tenBest))
		A.Total = A.Ten + tenPlan.Shake + 9 * HatchFx.Sequence + HatchFx.BurstTime + 2.2
		local shownAt: number? = nil
		local promptAt: number? = nil
		local shots = writeFrames("ha", cam, A.Total, function(t: number, extra: any): { any }
			local k = math.clamp(t / A.WalkEnd, 0, 1)
			local feet = startFeet:Lerp(endFeet, k)
			local onDais = (feet - frame.Position):Dot(front) < 9
			feet = V3.new(feet.X, if onDais then floor else ground, feet.Z)
			miner(extra, feet, spots.Stone.Center, if t < A.WalkEnd then t * 11 else nil)
			if not shownAt and (spots.Stone.Center - feet - V3.new(0, 3, 0)).Magnitude <= EggPanel.ShowRange then
				shownAt = t
			end
			if not promptAt and (spots.Stone.Prompt - feet - V3.new(0, 3, 0)).Magnitude <= EggPanel.PromptDistance then
				promptAt = t
			end
			stone(extra, 0.3 + t * 0.5, if shownAt then t - shownAt else nil)
			local guis = {}
			local woke = t >= A.Ok
			-- (while the opening is up the panel is a world billboard under its dim: left out here)
			local inHatch = (t >= A.Hatch and t < A.Ok) or t >= A.Ten
			if shownAt then
				local since = t - shownAt
				ringAt(extra, "Stone", 0.45 + 0.27 * (0.5 - 0.5 * math.cos(since / 1.2 * math.pi)))
			end
			if shownAt and not inHatch then
				local since = t - shownAt
				table.insert(
					guis,
					panelGui(VIDEO, cam, {
						Egg = "Stone",
						Lucky = false,
						Auto = false,
						Known = knownSet(if woke then { COMMON } else nil),
						Coins = 1e9,
						Fade = 1 - ease(since / 0.18),
						Pop = 0.82 + 0.18 * back(since / 0.26),
						Since = since,
						PopCard = if woke and t < A.Ok + 0.6 then { [COMMON] = t - A.Ok - 0.1 } else nil,
						Pressed = if t >= A.Click10 and t < A.Click10 + 0.15 then 10 else nil,
					})
				)
			end
			if promptAt and not inHatch then
				table.insert(
					guis,
					promptGui(VIDEO, cam, {
						Egg = "Stone",
						Fade = 1 - math.clamp((t - promptAt) / 0.12, 0, 1),
						Since = t - promptAt,
						Pressed = if t >= A.Press and t < A.Press + 0.25 then t - A.Press else nil,
					})
				)
			end
			if t >= A.Hatch and t < A.Ok then
				table.insert(
					guis,
					poseHatch(extra, cam, t - A.Hatch, {
						Kinds = { COMMON },
						New = { [1] = true },
						Egg = "Stone",
						Again = "OPEN 1 AGAIN  $" .. EggPanel.priceText(price1),
					})
				)
			elseif t >= A.Ten then
				table.insert(
					guis,
					poseHatch(
						extra,
						cam,
						t - A.Ten,
						{ Kinds = TEN, New = TEN_NEW, Egg = "Stone", Again = "OPEN 10 AGAIN  $" .. EggPanel.priceText(price10) }
					)
				)
			end
			return guis
		end)
		fs.writeFile(root .. "/build/preview/egg_hatch_stone_shots.json", serde.encode("json", shots))
	end

	-- part B: the Crystal egg, a Mythic
	do
		local feet, cam = standAt("Crystal", 18, 8)
		local MYTHIC = "HeartstoneColossus"
		local plan = HatchFx.plan(GolemConfig.order(MYTHIC))
		local B = { Press = 0.6, Hatch = 0.85, Total = 0 }
		B.Total = B.Hatch + plan.Shake + HatchFx.BurstTime + 2.6
		local price = CapsuleConfig.price("Crystal", 1, 1) or 0
		local shots = writeFrames("hb", cam, B.Total, function(t: number, extra: any): { any }
			miner(extra, feet, spots.Crystal.Center, nil)
			stone(extra, 0.3 + t * 0.5, nil)
			ringAt(extra, "Crystal", 0.45 + 0.27 * (0.5 - 0.5 * math.cos((t + 2) / 1.2 * math.pi)))
			local guis = {}
			if t < B.Hatch then
				table.insert(
					guis,
					panelGui(VIDEO, cam, {
						Egg = "Crystal",
						Lucky = false,
						Auto = false,
						Known = knownSet(),
						Coins = 1e9,
						Since = 2 + t,
					})
				)
				table.insert(
					guis,
					promptGui(VIDEO, cam, {
						Egg = "Crystal",
						Since = 1 + t,
						Pressed = if t >= B.Press and t < B.Press + 0.25 then t - B.Press else nil,
					})
				)
			else
				table.insert(
					guis,
					poseHatch(extra, cam, t - B.Hatch, {
						Kinds = { MYTHIC },
						New = { [1] = true },
						Egg = "Crystal",
						Again = "OPEN 1 AGAIN  $" .. EggPanel.priceText(price),
					})
				)
			end
			return guis
		end)
		fs.writeFile(root .. "/build/preview/egg_hatch_crystal_shots.json", serde.encode("json", shots))
	end
end
