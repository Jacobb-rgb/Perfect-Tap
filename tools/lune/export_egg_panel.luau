--[[
	The EGGS temple's egg panels (owner 2026-10-28: "make the UI for pets
	like this", two pictures of other egg games; round 2: "yes, a big E;
	make it even cooler; add opening by 10") for the owner, rendered without
	Studio. tools/preview is a three.js approximation of Roblox: the
	lighting, the fonts and the 3D pictures are close, not exact; the
	golems' live 3D pictures are the preview icons (tools/preview/render_icons).

	Built with the game's own code: WorldBuilder (the temple and its eggs),
	UI/EggPanel (laid out and filled the way EggPanelController does, over
	the egg's top: EggPanel.spotOf), UI/EggPrompt (the big round E and the
	opens round it, at the prompt's point), the egg opening (CapsuleView's
	pieces posed by UI/HatchStage) and the egg's hop (DecorController.bounceAt).
	The tweens the game plays are posed here frame by frame with the same
	numbers.

	  lune run tools/lune/export_egg_panel.luau [fps=20] [redo] [all|stills|video]
	  -> build/preview/egg_panel_base.json        the world, once (without the Stone egg: it hops)
	     build/preview/egg_panel/*.json           the egg, the miner and the ring (extra parts) and the UI per still / frame
	     build/preview/egg_panel_shots.json       the panel's stills, always: egg3_* (the big E or Roblox's
	                                              prompt), egg4_* (PC), egg5_* (phones and an iPad with the
	                                              thumbstick zone, the touch buttons and the top bar outlined),
	                                              egg6_* (a TV, the trash and the opens round the E at 2x)
	     build/preview/egg_redo_stills_shots.json the egg opening's key moments, PC ("redo", the default;
	     build/preview/egg_redo_phone_shots.json  "stills" or "all"), the phone's (844 x 390) in their own file
	     build/preview/egg_redo_video_shots.json  an Open 3 and Auto's fast one, frame by frame ("video" or "all")
	then (icons first: lune run tools/lune/export_icon_parts.luau; node tools/preview/render_icons.mjs golem_* capsule_*):
	  SHOTS_EXTRA=build/preview/egg_panel_shots.json node tools/preview/render.mjs egg_panel_base <names>
	  node tools/preview/render_shot_frames.mjs build/preview/egg_redo_stills_shots.json egg_redo_stills 15 <names>
	  node tools/preview/render_shot_frames.mjs build/preview/egg_redo_phone_shots.json egg_redo_phone 15 <names>
	  node tools/preview/render_shot_frames.mjs build/preview/egg_redo_video_shots.json egg_redo_open3 15
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
local videoMode = process.args[2] or "redo"
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

type Screen = { W: number, H: number, Pixel: number, Phone: boolean, Fov: number, K: number?, Ui: number?, TenFoot: boolean? }
-- PC: 1600 x 900 at the HUD's 1.25; a phone: 844 x 390 pt rendered at 2x (the HUD's 0.62 floor)
local PC: Screen = { W = 1600, H = 900, Pixel = 1.25, Phone = false, Fov = 70 }
local PHONE: Screen = { W = 1688, H = 780, Pixel = 0.62 * 2, Phone = true, Fov = 70 }
-- a TV: 1920 x 1080 (the HUD's 1.25 there), the ten-foot layout and a gamepad's keys
local TV: Screen = { W = 1920, H = 1080, Pixel = 1.25, Phone = false, Fov = 70, TenFoot = true }
-- PC at twice the pixels (the opens round the big E, close up: a crop of it)
local PC2: Screen = { W = 3200, H = 1800, Pixel = 2.5, Phone = false, Fov = 70 }
-- the small phone: 667 x 375 pt (an iPhone SE / 8) at 2x
local PHONE_SMALL: Screen = { W = 1334, H = 750, Pixel = 0.62 * 2, Phone = true, Fov = 70 }
-- the smallest phone the game supports: 568 x 320 pt (iPhone SE 1st gen) at 2x
local PHONE_TINY: Screen = { W = 1136, H = 640, Pixel = 0.62 * 2, Phone = true, Fov = 70 }
-- an iPad: 1024 x 768 pt at 1.5x (HudController's scale: min(768 / 720, 1024 / 1100))
local IPAD_UI = math.min(768 / 720, 1024 / 1100)
local IPAD: Screen = { W = 1536, H = 1152, Pixel = IPAD_UI * 1.5, Phone = true, Fov = 70, K = 1.5, Ui = IPAD_UI }
local LIVE_INSET = 58 -- Roblox's top bar row on a device (pt; the previews' 36 is the old one)

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
	Touch: Touch?, -- (touch) what else is on the screen
	Deleting: { [string]: boolean }?, -- the kinds the player auto-deletes (their trash red)
	Ask: string?, -- a card whose trash asks "AUTO-DELETE?"
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

local TutorialView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TutorialView")
local TutorialConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TutorialConfig")
local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")

-- A touch screen's numbers: render px per point, the HUD's scale, the size in points.
local function kOf(screen: Screen): number
	return screen.K or 2
end
local function uiOf(screen: Screen): number
	return screen.Ui or screen.Pixel / kOf(screen)
end
local function viewOf(screen: Screen): any
	return V2.new(screen.W / kOf(screen), screen.H / kOf(screen))
end

-- What's on a touch still besides the egg's guis: boost tiles running, the tutorial bubble, held ones.
type Touch = { Boosts: number?, Tutorial: boolean?, Held: boolean? }

local function box(x0: number, y0: number, x1: number, y1: number): any
	return { Min = V2.new(x0, y0), Max = V2.new(x1, y1) }
end

--[[
	A touch screen as EggPanelController measures it (points): Roblox's top
	bar row (LIVE_INSET), the HUD's teleport bar (HudBubble: centred), the
	boost corner's tiles (BoostView.cornerSpot, as BoostController places
	them) and the tutorial bubble (TutorialView.layout's touch bubble),
	unless `touch.Held` (the panel made them step aside).
]]
local function touchScreen(screen: Screen, touch: Touch?): (any, any, any?)
	local view, ui = viewOf(screen), uiOf(screen)
	local inset = LIVE_INSET
	local gui = V2.new(view.X, view.Y - inset) -- (the HUD's guis: under the top bar)
	local bar = HudBubble.topBarSize(HudBubble.layout(ui, view.X, true, false)) * ui
	local y0 = inset + HudBubble.topBarY(inset, ui) * ui
	local topBar = box(view.X / 2 - bar.X / 2, y0, view.X / 2 + bar.X / 2, y0 + bar.Y)
	local corner, bubble = nil, nil
	local t = touch or {}
	local boosts = t.Boosts or 0
	if boosts > 0 then
		local right, bottom, stacked = BoostView.cornerSpot({ Screen = gui, Gui = gui, Scale = ui, Touch = true, Count = boosts })
		local w, h = gui.X / ui, gui.Y / ui
		local tile = BoostView.cornerHeight()
		local gap = BoostView.CornerGap
		local x1, y1 = w - right, h - bottom
		local x0 = if stacked then x1 - BoostView.CornerWidth else x1 - boosts * BoostView.CornerWidth - (boosts - 1) * gap
		local y0c = if stacked then y1 - boosts * tile - (boosts - 1) * gap else y1 - tile
		corner = box(x0 * ui, inset + y0c * ui, x1 * ui, inset + y1 * ui)
	end
	if t.Tutorial then
		local l = TutorialView.layout(ui, gui, true, false)
		local x1, y0b = l.Position.X, l.Position.Y
		bubble = box((x1 - l.Width) * ui, inset + y0b * ui, x1 * ui, inset + (y0b + l.Height) * ui)
	end
	-- the left column: the tiles and the TRAIN chip under them (HudBubble)
	local layout = HudBubble.layout(ui, view.X, true, false)
	local m = HudBubble.menuMetrics(layout, #HudBubble.gameMenu())
	local left = box(
		0,
		inset + m.Origin.Y.Offset * ui,
		(m.Origin.X.Offset + m.Width) * ui,
		inset + (HudBubble.chipTop(layout) + HudBubble.TouchChipHeight) * ui
	)
	local input = {
		View = view,
		Safe = box(0, inset, view.X, view.Y),
		TopInset = inset,
		Hud = { topBar, left },
		Corner = corner,
		Bubble = bubble,
	}
	local shown = table.clone(input)
	if t.Held then
		shown.Corner, shown.Bubble = nil, nil
	end
	return EggPanel.screen(shown), input, nil
end

-- The HUD the player sees on a touch still (the game's own code, as tools/lune/lib/hud_pixel_preview
-- draws it): the top bar, the left tiles, the train chip, the boost corner, the tutorial bubble.
local function hudGuis(screen: Screen, touch: Touch?): { any }
	local t = touch or {}
	local view, ui, k = viewOf(screen), uiOf(screen), kOf(screen)
	local gui = V2.new(view.X, view.Y - LIVE_INSET)
	local render = ui * k
	local refs = HudBubble.buildGame(ui, gui.X, true, false)
	BoostView.HudChipsRight = HudBubble.chipsRight(refs.Gui, gui.X / ui)
	TeleportView.build(refs.TopBar, ui, gui.X)
	-- (HudController.placeTopBar: lifted into Roblox's row by the live inset, not the previews' 36)
	refs.TopBar.Position = UDim2.new(0.5, 0, 0, HudBubble.topBarY(LIVE_INSET, ui))
	refs.Gui.Scale.Scale = render
	refs.Coins.Text = Format.money(4.82e6)
	refs.Income.Text = Format.perSecond(1840)
	refs.Toasts:ClearAllChildren()
	local round = PopTheme.round()
	HudBubble.claimTile(refs.Menu, "Build")
	for _, entry in SideMenuView.sorted() do
		local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
		local main = if round then HudBubble.RoundMain[entry.Id] == true else entry.Group == "Main"
		if main then
			HudBubble.claimTile(refs.Menu, entry.Id, spec)
		else
			HudBubble.addMore(refs.Menu, entry.Id, spec)
		end
	end
	if round then
		HudBubble.claimTile(refs.Menu, "Backpack")
	end
	HudView.setBackpack(refs, 12, 30)
	local list = { refs.Gui }
	local boosts = t.Boosts or 0
	if boosts > 0 and not t.Held then
		local chips = BoostView.buildChips()
		chips.Gui.Scale.Scale = render
		if chips.Row:GetAttribute("Corner") then
			BoostView.placeCorner(chips, BoostView.cornerSpot({ Screen = gui, Gui = gui, Scale = ui, Touch = true, Count = boosts }))
		end
		local NOW = 1.7e9
		local state = { Boosts = { TripleLuckyUntil = NOW + 584, HexaLuckyUntil = if boosts > 1 then NOW + 3900 else nil } }
		BoostView.setChips(chips, BoostView.chips(state, NOW), false)
		chips.Gui.Enabled = true
		table.insert(list, chips.Gui)
	end
	if t.Tutorial and not t.Held then
		local tutorial = TutorialView.build()
		tutorial.Gui.Scale.Scale = render
		TutorialView.apply(tutorial, TutorialView.layout(ui, gui, true, false))
		local index = 1
		for i, step in TutorialConfig.Steps do
			if step.Id == "Golems" then
				index = i
			end
		end
		local step = TutorialConfig.get(index)
		TutorialView.setStep(tutorial, index, step, if step and step.Hint then step.Hint.Touch else nil)
		tutorial.Bubble.Visible = true
		table.insert(list, tutorial.Gui)
	end
	return list
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
	local lines = EggPanel.lines(spec.Egg, spec.Lucky, spec.Known, spec.Deleting)
	local narrow = false
	if screen.Phone then
		narrow = EggPanel.pickNarrow((touchScreen(screen, spec.Touch)), uiOf(screen), #lines, EggPanel.autoAllowed(spec.Egg))
	end
	local l = EggPanel.layout(#lines, screen.Phone, EggPanel.autoAllowed(spec.Egg), { Narrow = narrow, TenFoot = screen.TenFoot })
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
	EggPanel.setAuto(refs, autoShown, spec.Auto, if screen.Phone then "" elseif screen.TenFoot then "B" else "G", nil)
	-- the trash icons as EggPanelController.syncTrash leaves them (red: auto-deleted; one asking)
	for i, card in refs.Cards do
		local line = lines[i]
		if line and line.Trash then
			local state = if spec.Ask == line.Golem then "Ask" elseif line.Deleting then "On" else "Off"
			EggPanel.setTrash(card, state)
		end
	end
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
		local k = kOf(screen)
		local mx, my = project(screen, cam, s.Center)
		local sx = project(screen, cam, s.Center + camRight * s.Half)
		local px = project(screen, cam, s.Prompt)
		local scale = uiOf(screen)
		local reach = math.max(math.abs(sx - mx), px - mx + EggPrompt.size(false).X * screen.Pixel / 2) / k
		local size = V2.new(math.ceil(l.Width * scale), math.ceil(l.Height * scale))
		local touchS, input = touchScreen(screen, spec.Touch)
		local row, odds = EggPanel.rowBox(l, scale), EggPanel.oddsBox(l, scale)
		local egg = V2.new(mx / k, my / k)
		local at, fit = EggPanel.floatAt(touchS, size, row, odds, egg, reach)
		-- (EggPanelController.float: the corner / the bubble step aside where the panel can't keep clear of them)
		local held = spec.Touch ~= nil and spec.Touch.Held == true
		if not held and (fit.Hard > 0 or fit.Odds > 0) then
			local corner, bubble = EggPanel.asides(input, size, row, odds, egg, reach)
			gui:SetAttribute("Holds", corner or bubble)
		end
		print(
			`  float {spec.Egg} {screen.W / k}x{screen.H / k}: at {at}, hard {fit.Hard}, odds {fit.Odds}, panel {fit.Panel}, narrow {narrow}`
		)
		panel.AnchorPoint = V2.new(0, 0)
		panel.Position = UDim2.fromOffset(at.X * k / screen.Pixel, at.Y * k / screen.Pixel)
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

-- The opens' key badges round the big E: a keyboard's E / R / X, a gamepad's (the TV) Y and D-pad Up.
local function promptKeys(screen: Screen): { [number]: string }?
	if screen.Phone then
		return nil
	elseif screen.TenFoot then
		return { [1] = "Y", [3] = "Up", [10] = "Up" }
	end
	return EggPanel.OpenKeys
end

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
	EggPrompt.setKey(p, spec.Key or (if screen.Phone then "Tap" elseif screen.TenFoot then "Y" else "E"), nil)
	EggPrompt.setGlow(p, capsule.Glow)
	-- PC and gamepads: the opens round the disc (EggPanelController.refreshPanel); touch: the disc alone
	EggPrompt.setCluster(p, not screen.Phone)
	EggPrompt.setOpens(p, opensOf(spec.Egg), promptKeys(screen), nil)
	if spec.Pressed and spec.Pressed > 1 then
		for _, open in p.Opens do
			if open.Count == spec.Pressed then
				local s = Instance.new("UIScale")
				s.Scale = 0.9
				s.Parent = open.Button
			end
		end
	end
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
	What the preview can't draw, outlined: the thumbstick's start zone
	(left 40 %, lower two thirds) and the touch buttons in the bottom right
	(BoostView.TouchButtons: Roblox's jump, Grab, the blaster's FIRE); the
	floating panel keeps its buttons out of them.
]]
local function zonesGui(screen: Screen): any
	local gui = UIKit.screen("PhoneZones", 3)
	gui.IgnoreGuiInset = true
	gui.Scale.Scale = kOf(screen) -- (points)
	local view = viewOf(screen)
	local w, h = view.X, view.Y
	local function outline(name: string, x: number, y: number, bw: number, bh: number, color: any, text: string, round: boolean?)
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
	outline("Thumbstick", 0, h / 3, w * EggPanel.ZoneWidth, h * 2 / 3, rgb(255, 80, 80), "thumbstick zone (left 40 %)")
	local s = touchScreen(screen, nil)
	local small = math.min(w, h) <= 500
	for i, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
		local k = s.Keep[i]
		outline(b.Name, k.Min.X, k.Min.Y, k.Max.X - k.Min.X, k.Max.Y - k.Min.Y, rgb(255, 200, 60), b.Name, true)
	end
	return gui
end

-- Does the floating panel (panelGui's attributes, points) cover the big E at the egg's prompt? (the game hides it then)
local function covers(screen: Screen, cam: Cam, panel: any, egg: string): boolean
	local x = panel:GetAttribute("FloatX")
	if x == nil then
		return false
	end
	local k = kOf(screen)
	local px, py = project(screen, cam, spots[egg].Prompt)
	local size = EggPrompt.size(false) * uiOf(screen) -- (touch: the disc alone)
	local at = V2.new(x, panel:GetAttribute("FloatY"))
	local prompt = V2.new(px / k, py / k) - size / 2
	return EggPanel.overlap(
		{ Min = at, Max = at + V2.new(panel:GetAttribute("FloatW"), panel:GetAttribute("FloatH")) },
		{ Min = prompt, Max = prompt + size }
	) > 0
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
		uiInset = if screen.Phone then LIVE_INSET * kOf(screen) else 36,
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

for _, egg in { "Stone", "Crystal", "Royal" } do
	local feet, cam = standAt(egg)
	local extra = Instance.new("Model")
	miner(extra, feet, spots[egg].Center)
	stone(extra, 0.3, nil)
	ringAt(extra, egg, 0.5)
	local panel =
		panelGui(PC, cam, { Egg = egg, Lucky = egg == "Crystal", Auto = egg == "Crystal", Known = knownSet(), Coins = 1e9, Since = 2.3 })
	still(`egg4_{string.lower(egg)}_pc`, PC, cam, extra, { panel, promptGui(PC, cam, { Egg = egg, Since = 0.45 }) })
end

-- the clean panel (owner's clicker video, A2): a TV at 1080p (the ten-foot layout, a gamepad's keys)
do
	local feet, cam = standAt("Crystal")
	local extra = Instance.new("Model")
	miner(extra, feet, spots.Crystal.Center)
	stone(extra, 0.3, nil)
	ringAt(extra, "Crystal", 0.5)
	local panel = panelGui(TV, cam, { Egg = "Crystal", Lucky = false, Auto = false, Known = knownSet(), Coins = 1e9, Since = 2.3 })
	still("egg6_crystal_tv", TV, cam, extra, { panel, promptGui(TV, cam, { Egg = "Crystal", Since = 0.45 }) })
end
-- the trash (PebbleGolem auto-deleted: red; CopperTinker asking) and the opens round the E, at twice the pixels
-- (close-ups are crops of it: the crop boxes are printed)
do
	local feet, cam = standAt("Stone")
	local extra = Instance.new("Model")
	miner(extra, feet, spots.Stone.Center)
	stone(extra, 0.3, nil)
	ringAt(extra, "Stone", 0.5)
	local panel = panelGui(PC2, cam, {
		Egg = "Stone",
		Lucky = false,
		Auto = false,
		Known = knownSet(),
		Coins = 1e9,
		Since = 2.3,
		Deleting = { PebbleGolem = true },
		Ask = "CopperTinker",
	})
	still("egg6_stone_trash_pc2", PC2, cam, extra, { panel, promptGui(PC2, cam, { Egg = "Stone", Since = 0.45 }) })
	local px, py = project(PC2, cam, spots.Stone.Prompt)
	local ax, ay = project(PC2, cam, V3.new(spots.Stone.Center.X, spots.Stone.Top + EggPanel.Lift, spots.Stone.Center.Z))
	local cluster = EggPrompt.size(true) * PC2.Pixel
	print(`  crop: the opens round the E {math.floor(px - cluster.X / 2)} {math.floor(py - cluster.Y / 2)} {cluster.X} {cluster.Y}`)
	print(`  crop: the panel's bottom middle at {math.floor(ax)} {math.floor(ay)}`)
end

--[[
	A touch still with the HUD drawn (the game's code): the panel floats as
	EggPanelController.float puts it; where the boost corner or the tutorial
	bubble would cover its row or a card they step aside (held: not drawn),
	as in the game. `walk`: further back, the panel not up yet (the bubble
	still shows).
]]
local function touchStill(name: string, screen: Screen, egg: string, touch: Touch, lucky: boolean?, walk: boolean?)
	local feet, cam = standAt(egg, if walk then 17 else nil)
	local extra = Instance.new("Model")
	miner(extra, if walk then feet + front * 5 else feet, spots[egg].Center)
	stone(extra, 0.3, nil)
	ringAt(extra, egg, if walk then 1 else 0.5)
	local t: Touch = table.clone(touch)
	local guis = {}
	if not walk then
		local spec = { Egg = egg, Lucky = lucky == true, Auto = false, Known = knownSet(), Coins = 1e9, Since = 2.3, Touch = t }
		local panel = panelGui(screen, cam, spec)
		if panel:GetAttribute("Holds") then
			t.Held = true
			panel = panelGui(screen, cam, spec)
		end
		table.insert(guis, panel)
		if not covers(screen, cam, panel, egg) then
			table.insert(guis, promptGui(screen, cam, { Egg = egg, Since = 0.45, Key = "Tap" }))
		end
	end
	for _, g in hudGuis(screen, t) do
		table.insert(guis, g)
	end
	table.insert(guis, zonesGui(screen))
	still(name, screen, cam, extra, guis)
end

for _, case in { { PHONE_SMALL, "667" }, { PHONE, "844" }, { PHONE_TINY, "568" } } do
	for _, egg in { "Stone", "Royal" } do
		touchStill(`egg5_{string.lower(egg)}_{case[2]}`, case[1], egg, {})
	end
end
-- the tutorial's "Golem helpers" step (its bubble top right): walking up, then at the egg (the bubble steps aside)
touchStill("egg5_tutorial_walk_667", PHONE_SMALL, "Stone", { Tutorial = true }, false, true)
touchStill("egg5_tutorial_egg_667", PHONE_SMALL, "Stone", { Tutorial = true })
touchStill("egg5_tutorial_egg_844", PHONE, "Stone", { Tutorial = true })
-- Triple Lucky running: an iPad (the clover tile stays, the panel above it), a phone with both boosts (they step aside)
touchStill("egg5_ipad_triple_lucky", IPAD, "Stone", { Boosts = 1 }, true)
touchStill("egg5_ipad_triple_lucky_crystal", IPAD, "Crystal", { Boosts = 1 }, true)
touchStill("egg5_two_boosts_667", PHONE_SMALL, "Stone", { Boosts = 2 }, true)

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

---------------------------------------------------------------- the egg redo (video "redo", owner 2026-10-29)

--[[
	The new egg opening (the owner's clicker-sim video:
	docs/plans/CLICKER_VIDEO_2026-10-29.md, section 1), posed by the game's
	own HatchStage on the game's own opening (CapsuleView.buildOpening), with
	the eggs and golems GolemBuilder builds. Its full-screen stage
	ViewportFrame is drawn live by the preview's UI layer (PreviewLive: its
	parts through its own camera and light, Neon flat as in Roblox) between
	the flash and the names, over the world softly blurred (the shot's depth
	of field stands in for the opening's BlurEffect). The HUD steps away as
	in the game: only the Auto button shows.
	  lune run tools/lune/export_egg_panel.luau 15 redo
	  -> build/preview/egg_redo_stills_shots.json   the key moments of each case (PC)
	     build/preview/egg_redo_phone_shots.json    the phone's (844 x 390 pt at 2x)
	     build/preview/egg_redo_video_shots.json    an Open 3 (and Auto's fast one), frame by frame
	  node tools/preview/render_shot_frames.mjs build/preview/egg_redo_stills_shots.json egg_redo_stills 15 <names>
	  node tools/preview/render_shot_frames.mjs build/preview/egg_redo_video_shots.json egg_redo_open3 15
]]
if videoMode == "redo" then
	local HatchStage = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchStage")
	local which = process.args[3] or "all"

	type Redo = {
		Egg: string,
		Kinds: { string },
		Lucky: boolean?,
		Fast: boolean?,
		Reduced: boolean?,
		Auto: boolean?, -- Auto on (the button green)
		Deleted: { [number]: boolean }?, -- the result's golems the player auto-deletes (greyed, DELETED, they stay)
		Waiting: { [number]: boolean }?, -- won past the inventory's hard cap ("Waiting: inventory full")
		Batch: number?, -- a big pack's opening `Batch` of `Batches` ("2 / 5" at the top)
		Batches: number?,
		Caption: string,
	}

	-- a golem as the game builds it for the stage (its height, its pivot over its feet)
	local function golemOf(kind: string): (any, number, number)
		local model = GolemBuilder.build(kind)
		return model, model:GetAttribute("Height") or 3, model:GetAttribute("RootHeight") or 1
	end

	-- the opening on `screen`, `case` posed by HatchStage to each of `times` in turn (one run)
	local function opening(screen: Screen, case: Redo): (any, any)
		local compact = screen.Phone
		local o = CapsuleView.buildOpening(compact)
		local ui = if screen.Phone then uiOf(screen) * kOf(screen) else screen.Pixel
		o.Gui.Scale.Scale = ui
		o.Controls.Scale.Scale = ui
		local insetPx = if screen.Phone then LIVE_INSET * kOf(screen) else 36
		CapsuleView.layoutOpening(o, compact, screen.W / ui, screen.H / ui, {
			Touch = screen.Phone,
			Inset = insetPx / ui,
		})
		o.Gui.Enabled = true
		o.Controls.Enabled = true
		CapsuleView.setAuto(o, true, case.Auto == true, if screen.Phone then "" else "G", nil)
		CapsuleView.setChain(o, case.Batch, case.Batches)
		o.Stage:SetAttribute("PreviewLive", true)
		local eggs = {}
		local n = #case.Kinds
		for _ = 1, n do
			local model = GolemBuilder.capsule(case.Egg)
			HatchFx.addCracks(model, if screen.Phone and n > 3 then 2 else 3)
			model:SetAttribute("Pooled", true)
			table.insert(eggs, HatchFx.record(model))
		end
		local run = HatchStage.new({
			Refs = o,
			Capsule = case.Egg,
			Lucky = case.Lucky == true,
			Kinds = case.Kinds,
			Eggs = eggs,
			Fast = case.Fast == true,
			Reduced = case.Reduced == true,
			Phone = screen.Phone,
			Target = V2.new(0.5, 0.86),
			Golem = golemOf,
			Claim = function(): boolean
				return true
			end,
			Deleted = case.Deleted,
			Waiting = case.Waiting,
		})
		return o, run
	end

	-- the video's caption (not the game's): bottom right, clear of the Auto button
	local function caption(screen: Screen, text: string): any
		local cap = UIKit.screen("Caption", 50)
		cap.IgnoreGuiInset = true
		cap.Scale.Scale = 1
		local label = UIKit.new("TextLabel", {
			Name = "Caption",
			AnchorPoint = V2.new(1, 1),
			BackgroundColor3 = rgb(0, 0, 0),
			BackgroundTransparency = 0.35,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			Position = UDim2.fromOffset(screen.W - 16, screen.H - 16),
			Size = UDim2.fromOffset(math.min(screen.W - 32, 620), 40),
			Text = "  " .. text .. "  ",
			TextColor3 = rgb(255, 255, 255),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, cap)
		UIKit.corner(label, 10)
		return cap
	end

	-- the thumbstick's zone outlined (phones: the Auto button must stay clear of it) and Roblox's jump
	local function zones(screen: Screen): any
		local gui = UIKit.screen("PhoneZones", 3)
		gui.IgnoreGuiInset = true
		gui.Scale.Scale = kOf(screen) -- (points)
		local view = viewOf(screen)
		local zone = UIKit.new("Frame", {
			Name = "Thumbstick",
			BackgroundColor3 = rgb(255, 80, 80),
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, view.Y / 3),
			Size = UDim2.fromOffset(view.X * CapsuleView.ThumbZone.Width, view.Y * 2 / 3),
		}, gui)
		UIKit.stroke(zone, 1.5, rgb(255, 80, 80), 0.1)
		UIKit.new("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 12),
			Text = "thumbstick zone (left 40 %, lower 2/3): free to walk",
			TextColor3 = rgb(255, 255, 255),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, zone)
		for _, c in { { 35, 90 }, { 60, 40 } } do
			local stick = UIKit.new("Frame", {
				Name = "Stick",
				BackgroundColor3 = rgb(0, 0, 0),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(c[1], view.Y - 20 - (c[2] == 90 and 90 or 65)),
				Size = UDim2.fromOffset(c[2], c[2]),
			}, gui)
			UIKit.corner(stick, 999)
			UIKit.stroke(stick, 2, rgb(255, 255, 255), 0.5)
		end
		local jump = UIKit.new("Frame", {
			Name = "Jump",
			BackgroundColor3 = rgb(0, 0, 0),
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(view.X - 25 - 70, view.Y - 20 - 70),
			Size = UDim2.fromOffset(70, 70),
		}, gui)
		UIKit.corner(jump, 999)
		UIKit.stroke(jump, 2, rgb(255, 255, 255), 0.5)
		return gui
	end

	-- the player at the Stone egg (the golems fly to them) and the camera behind them
	local feet, cam = standAt("Stone", 13, 4)
	local pc = table.clone(cam)
	-- (the depth of field stands in for the opening's blur: the focus just in front of the camera,
	-- the whole world behind blurred; the look stays the same)
	local look = (cam.Target - cam.Position).Unit
	local focus = { Position = cam.Position, Target = cam.Position + look * 3 }

	local function shotOf(name: string, screen: Screen, o: any, run: any, case: Redo, extraGuis: { any }?): any
		-- (Reduce motion's fades of the whole stage: folded into its parts, the preview draws no viewport fade)
		local fade = o.Stage.ImageTransparency
		local saved = {}
		if fade > 0 then
			for _, d in o.Stage:GetDescendants() do
				if d:IsA("BasePart") then
					saved[d] = d.Transparency
					d.Transparency = 1 - (1 - d.Transparency) * (1 - fade)
				end
			end
		end
		local extra = Instance.new("Model")
		miner(extra, feet, spots.Stone.Center)
		local guis = { o.Gui, o.Controls }
		for _, gui in extraGuis or {} do
			table.insert(guis, gui)
		end
		table.insert(guis, caption(screen, case.Caption))
		fs.writeFile(OUT .. "/" .. name .. "_fx.json", serde.encode("json", Export.collect(extra)))
		fs.writeFile(OUT .. "/" .. name .. "_ui.json", serde.encode("json", UiExport.export(guis)))
		for part, t in saved do
			part.Transparency = t
		end
		return {
			scene = "egg_panel_base",
			extra = "egg_panel/" .. name .. "_fx",
			ui = "egg_panel/" .. name .. "_ui",
			width = screen.W,
			height = screen.H,
			uiInset = if screen.Phone then LIVE_INSET * kOf(screen) else 36,
			position = { focus.Position.X, focus.Position.Y, focus.Position.Z },
			target = { focus.Target.X, focus.Target.Y, focus.Target.Z },
			fov = screen.Fov,
			preset = "Surface",
			shadowExtent = 120,
			dof = { aperture = 0.02, maxblur = 0.011 },
			sunDir = { front.X * 0.7 + right.X * 0.2, 0.68, front.Z * 0.7 + right.Z * 0.2 },
		}
	end
	local _ = pc

	local OPEN3 = { "RoseKnight", "QuartzSprite", "CopperTinker" } -- (purple, green and white cracks, like the video)
	-- ten golems of the Dragonforge egg, its odds' golems in turn
	local DRAGON10 = {}
	local dragonOdds = CapsuleConfig.odds("Dragonforge", false)
	for i = 1, 10 do
		DRAGON10[i] = dragonOdds[(i - 1) % #dragonOdds + 1].Golem
	end
	local cases: { [string]: Redo } = {
		common = { Egg = "Stone", Kinds = { "TinTumbler" }, Caption = "Open 1: a Common (white cracks)" },
		open3 = { Egg = "Stone", Kinds = OPEN3, Caption = "Open 3: an Epic, an Uncommon, a Common" },
		open10 = {
			Egg = "Crystal",
			Kinds = {
				"QuartzSprite",
				"SilverSquire",
				"EmberImp",
				"JadeGardener",
				"CobaltDiver",
				"AmethystAcolyte",
				"MoonstoneOracle",
				"QuartzSprite",
				"RoseKnight",
				"SilverSquire",
			},
			Caption = "Open 10 with a Legendary (centred, bigger)",
		},
		mythic = { Egg = "Crystal", Kinds = { "HeartstoneColossus" }, Caption = "A Mythic: rainbow cracks, the suspense" },
		calm = { Egg = "Stone", Kinds = OPEN3, Reduced = true, Caption = "Reduce Motion: fades, no shake, rings or flash" },
		deleted = {
			Egg = "Stone",
			Kinds = OPEN3,
			Deleted = { [3] = true },
			Caption = "Auto-delete on for Copper Tinker: greyed, DELETED, it stays",
		},
		-- a x50 limited pack: five openings of 10 one after another (the later ones in the fast timings)
		x50 = {
			Egg = "Dragonforge",
			Kinds = DRAGON10,
			Fast = true,
			Batch = 2,
			Batches = 5,
			Caption = "Dragonforge x50: opening 2 of 5, every golem shown and named",
		},
		-- the pack's last opening with the inventory full: the golems past the cap shown won, waiting
		waiting = {
			Egg = "Dragonforge",
			Kinds = DRAGON10,
			Fast = true,
			Batch = 5,
			Batches = 5,
			Waiting = { [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true },
			Caption = "Inventory full: the last 6 shown won, they wake when there is room",
		},
		fast = {
			Egg = "Stone",
			Kinds = { "PebbleGolem", "SilverSquire", "CoalChomper" },
			Fast = true,
			Auto = true,
			Caption = "Auto: the fast opening (about 2 s)",
		},
	}

	-- the stills: each case at its key moments (seconds into its timeline)
	local function moments(run: any): { { any } }
		local tl = run.Timeline
		local list = {
			{ "a_pop", 0.1 },
			{ "b_wobble_rings", tl.Rings + 0.1 },
			{ "c_cracks", tl.Steps[2] + 0.12 },
			{ "d_cracks_full", tl.Silhouette - 0.08 },
			{ "e_silhouette", tl.Silhouette + tl.Times.Silhouette * 0.7 },
			{ "f_flash", tl.Burst + 0.06 },
			{ "g_reveal", tl.Reveal + tl.Times.GolemPop + 0.35 },
			{ "h_fly", tl.Fly + tl.Times.Fly * 0.45 },
		}
		if tl.Suspense > 0 then
			table.insert(list, 5, { "d2_suspense", tl.Steps[3] + tl.Suspense * 0.8 })
		end
		return list
	end

	for product, id in royalIds do
		product.Id = id
	end
	local stillShots = {}
	local phoneShots = {} -- (a render batch takes its size from its first shot: the phone's go in their own file)
	local function stillsOf(prefix: string, screen: Screen, caseName: string, only: { string }?)
		local case = cases[caseName]
		local o, run = opening(screen, case)
		local t = 0
		for _, m in moments(run) do
			local at = m[2] :: number
			if at ~= at or at == math.huge or (only and not table.find(only, m[1])) then
				continue -- (a moment this case doesn't have: Reduce motion has no rings)
			end
			-- (posed forward in small steps to `at`: the run's events and the sunburst's turn as in the game)
			while t < at do
				t = math.min(at, t + 1 / 30)
				HatchStage.pose(run, t)
			end
			local name = `{prefix}_{m[1]}`
			local list = if screen.Phone then phoneShots else stillShots
			list[name] = shotOf(name, screen, o, run, case, if screen.Phone then { zones(screen) } else nil)
		end
	end
	if which == "all" or which == "stills" then
		stillsOf("redo_common", PC, "common")
		stillsOf("redo_open3", PC, "open3")
		stillsOf("redo_open10", PC, "open10", { "a_pop", "c_cracks", "d2_suspense", "f_flash", "g_reveal" })
		stillsOf("redo_mythic", PC, "mythic", { "c_cracks", "d2_suspense", "e_silhouette", "f_flash", "g_reveal" })
		stillsOf("redo_calm", PC, "calm", { "a_pop", "c_cracks", "d_cracks_full", "g_reveal" })
		stillsOf("redo_phone", PHONE, "open3", { "c_cracks", "g_reveal" })
		stillsOf("redo_deleted", PC, "deleted", { "g_reveal", "h_fly" })
		stillsOf("redo_x50", PC, "x50", { "c_cracks", "g_reveal" })
		stillsOf("redo_waiting", PC, "waiting", { "g_reveal" })
		stillsOf("redo_waiting_phone", PHONE, "waiting", { "g_reveal" })
		fs.writeFile(root .. "/build/preview/egg_redo_stills_shots.json", serde.encode("json", stillShots))
		fs.writeFile(root .. "/build/preview/egg_redo_phone_shots.json", serde.encode("json", phoneShots))
		local n = 0
		for _ in stillShots do
			n += 1
		end
		print(`redo stills: {n}`)
	end
	if which == "all" or which == "video" then
		-- the video: an Open 3 (then Auto's fast one), frame by frame at `fps`
		local videoShots = {}
		local index = 0
		for _, caseName in { "open3", "fast" } do
			local case = cases[caseName]
			local o, run = opening(PC, case)
			local tl = run.Timeline
			-- (to its end: the renderer keeps one world, its blur, for every frame)
			local frames = math.floor(tl.Total * fps) + 1
			for i = 0, frames - 1 do
				local t = i / fps
				HatchStage.pose(run, math.min(t, tl.Total))
				local name = string.format("redo_v_%04d", index)
				index += 1
				videoShots[name] = shotOf(name, PC, o, run, case)
			end
		end
		fs.writeFile(root .. "/build/preview/egg_redo_video_shots.json", serde.encode("json", videoShots))
		print(`redo video: {index} frames`)
	end
end
