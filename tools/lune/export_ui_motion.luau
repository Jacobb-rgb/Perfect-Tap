--[[
	The UI motion preview (UI/Motion, owner 2026-10-21: "perfect animations"):
	exports one UI frame per 1/30 s of a short story, drawn with the game's
	own builders and the very structure Motion puts on them (MotionPop /
	MotionScale UIScales, the shine's gradient, the cash bits), set at each
	moment by Motion's pure curves (popScale, ease, breatheScale,
	shineOffset, countValue, flyAt):

	  0.5 s   the Robux STORE pops in (the dim fades, the tabs slide in), the
	          FEATURED x50 breathes, the green prices shine
	  2.6 s   the mouse on the Money tab: it grows, squashes, bounces back;
	          the list scrolls to MONEY (BEST VALUE breathing)
	  4.6 s   the BEST VALUE card's price: grow, squash, bounce
	  5.8 s   the store closes (shrinks to 0.9, the dim fades)
	  6.2 s   a sale: the money panel pops, the number rolls up, cash bits
	          burst from the screen centre into the pile (it bumps), a toast
	          pops in; 7.6 s a second one (at most one burst a second)
	  8.6 s   SETTINGS pops in, the mouse on the new Reduce motion toggle

	  lune run tools/lune/export_ui_motion.luau
	  -> build/preview/ui_motion/frame_NNNN.json + manifest.json
	  node tools/preview/render_ui_frames.mjs ui_motion shots/motion_backdrop.jpg \
	    docs/screenshots/animations/ui_animace.mp4 docs/screenshots/animations/ui_animace.jpg
	The backdrop is the store's lobby shot without UI (once):
	  lune run tools/lune/export_scene.luau store
	  SHOTS_EXTRA=tools/preview/motion_shots.json node tools/preview/render.mjs store motion_backdrop
	The 3D icons (build/preview/icons) come from tools/preview/render_icons.mjs: every
	name, plus the part icons by name (golem_*, capsule_*, cash_*: the files that
	tools/lune/export_icon_parts.luau writes to build/preview/icon_parts).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true
Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig").LightUI = true
local LightSkin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LightSkin")
UiExport.before = function(gui)
	if gui:GetAttribute("LightSkin") then
		LightSkin.refresh(gui)
	end
end

local Instance = roblox.Instance
local Vector2 = roblox.Vector2
local UDim2 = roblox.UDim2
local Color3 = roblox.Color3

local UI = "StarterPlayer.StarterPlayerScripts.Client.UI."
local Motion = Loader.requirePath(UI .. "Motion")
local UIKit = Loader.requirePath(UI .. "UIKit")
local HudBubble = Loader.requirePath(UI .. "HudBubble")
local HudView = Loader.requirePath(UI .. "HudView")
local TeleportView = Loader.requirePath(UI .. "TeleportView")
local StoreView = Loader.requirePath(UI .. "StoreView")
local SettingsView = Loader.requirePath(UI .. "SettingsView")
local MenuPanel = Loader.requirePath(UI .. "MenuPanel")
local Watcher = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.UIMotionController")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
local SettingsConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SettingsConfig")
local LimitedGolems = Loader.requirePath("ReplicatedStorage.Shared.Config.LimitedGolems")
local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")

local FPS = 30
local DURATION = 11
local SCALE = 1.25 -- 900 px tall render / 720 design height
local W, H = 1600, 900
local DW, DH = W / SCALE, (H - 36) / SCALE -- the screen in design units (under the top bar)

---------------------------------------------------------------- the screens

-- the HUD (as store_preview draws it)
local hud = HudBubble.buildGame(1.25)
TeleportView.build(hud.TopBar, 1.25, W / SCALE)
hud.Gui.Scale.Scale = SCALE
hud.Income.Text = Format.perSecond(1840)
hud.CarryLabel.Text = "CARRYING 0/3"
for i = 1, 3 do
	HudView.slot(hud.CarrySlots, nil, i)
end
hud.Toasts:ClearAllChildren()
local cash = hud.CoinsPanel:FindFirstChild("Cash")
-- (HudController's own pop of the money panel: named here so the preview scales it like Roblox)
local coinScale = UIKit.new("UIScale", { Name = "MotionCoins", Scale = 1 }, hud.CoinsPanel)
local pileScale = UIKit.new("UIScale", { Name = "MotionPop", Scale = 1 }, cash)

-- the store with the limited edition banner (as StoreController shows it)
local store = StoreView.build()
store.Gui.Scale.Scale = SCALE
StoreView.layout(store, DW, DH)
StoreView.setCoins(store, 1840)
local edition = LimitedGolems.current(LimitedGolems.Current.EndsAt - (9 * 86400 + 4 * 3600))
StoreView.setEdition(store, edition)
StoreView.setTimer(store, 9 * 86400 + 4 * 3600)
do
	local odds = {}
	for _, line in CapsuleConfig.odds(edition.CapsuleId, false) do
		odds[line.Golem] = line.Chance
	end
	StoreView.setBannerOdds(store, odds, false)
end
StoreView.setCard(store, "Podiums", "Podiums", "Owned")
local dim = store.Gui:FindFirstChild("Dim")
local dimBase = dim.BackgroundTransparency
local groupScale = UIKit.new("UIScale", { Name = "MotionPop", Scale = 1 }, store.Group)
local tabs = store.Group:FindFirstChild("Tabs")
local tabsAnchor = tabs.AnchorPoint

-- the settings panel (the new Reduce motion row)
local settings = SettingsView.build(false)
settings.Gui.Scale.Scale = SCALE
SettingsView.setShown(settings, "Music", false)
SettingsView.setShown(settings, "Rumble", false)
SettingsView.layout(settings, false, DW, DH)
SettingsView.set(settings, SettingsConfig.sanitize({ Music = 0.6, Sfx = 0.8, Shake = true }))
MenuPanel.setHint(settings.Frame, "Drag a bar or use - and + · Backspace: close", nil)
local panelScale = UIKit.new("UIScale", { Name = "MotionPop", Scale = 1 }, settings.Frame.Panel)

-- the watcher's part: press feel on every button it would take, loops on the marked ones
local shines: { { Gradient: any, Phase: number, Gui: any } } = {}
local breathers: { any } = {}
for _, gui in { hud.Gui, store.Gui, settings.Gui } do
	local n = 0
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiButton") and Watcher.pressKind(d) then
			Watcher.attach(d)
		end
		local mark = d:GetAttribute("Motion")
		if mark == "Shine" then
			n += 1
			local phase = (n * 0.53) % Motion.Shine.Period
			if d == store.Cards.CoinsMega.Price then
				phase = 0.4 -- (the BEST VALUE price: its streak crosses at 4.0 s, for the strip)
			end
			Motion.shine(d, phase)
			local clip = d:FindFirstChild("MotionShine")
			table.insert(shines, { Gradient = clip.Streak.Sweep, Phase = phase, Gui = d })
		elseif mark == "Breathe" then
			Motion.breathe(d)
			table.insert(breathers, d)
		end
	end
end

-- a mouse pointer for the preview (not in the game): a white ring that dips on a press
local cursorGui = UIKit.screen("PreviewCursor", 100)
cursorGui.Scale.Scale = SCALE
local cursor = UIKit.new("Frame", {
	Name = "Cursor",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.15,
	Size = UDim2.fromOffset(26, 26),
	ZIndex = 100,
}, cursorGui)
UIKit.corner(cursor, 13)
UIKit.new("UIStroke", { Color = Color3.fromRGB(14, 14, 18), Thickness = 3 }, cursor)

---------------------------------------------------------------- where things are (design units)

-- A GuiObject's top-left and size in its ScreenGui (Position / AnchorPoint,
-- UIListLayout children, UIPadding, a scrolled ScrollingFrame).
local function rectOf(gui: any): (any, any)
	local chain = {}
	local node = gui
	while node and not node:IsA("ScreenGui") do
		table.insert(chain, 1, node)
		node = node.Parent
	end
	local origin = Vector2.new(0, 0)
	local area = Vector2.new(DW, DH)
	local size = area
	for _, item in chain do
		local parent = item.Parent
		local pad = parent:FindFirstChildOfClass("UIPadding")
		local inner = area
		local offset = Vector2.new(0, 0)
		if pad then
			offset = Vector2.new(pad.PaddingLeft.Offset, pad.PaddingTop.Offset)
			inner = area - Vector2.new(pad.PaddingLeft.Offset + pad.PaddingRight.Offset, pad.PaddingTop.Offset + pad.PaddingBottom.Offset)
		end
		size = Vector2.new(item.Size.X.Scale * inner.X + item.Size.X.Offset, item.Size.Y.Scale * inner.Y + item.Size.Y.Offset)
		local list = parent:FindFirstChildOfClass("UIListLayout")
		local at
		if list then
			local siblings = {}
			for _, s in parent:GetChildren() do
				if s:IsA("GuiObject") and s.Visible then
					table.insert(siblings, s)
				end
			end
			table.sort(siblings, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			local cursorY = 0
			local gap = list.Padding.Offset
			for _, s in siblings do
				if s == item then
					break
				end
				cursorY += s.Size.Y.Scale * inner.Y + s.Size.Y.Offset + gap
			end
			local x = if list.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Center then (inner.X - size.X) / 2 else 0
			at = Vector2.new(x, cursorY)
		else
			at = Vector2.new(
				item.Position.X.Scale * inner.X + item.Position.X.Offset,
				item.Position.Y.Scale * inner.Y + item.Position.Y.Offset
			) - Vector2.new(item.AnchorPoint.X * size.X, item.AnchorPoint.Y * size.Y)
		end
		if parent:IsA("ScrollingFrame") then
			at -= parent.CanvasPosition
		end
		origin += offset + at
		area = size
	end
	return origin, size
end

local function centreOf(gui: any): any
	local at, size = rectOf(gui)
	return at + size * 0.5
end

-- where the pointer rests on a button: lower right, the words stay readable
local function pointOn(gui: any): any
	local at, size = rectOf(gui)
	return at + Vector2.new(size.X * 0.82, size.Y * 0.74)
end

---------------------------------------------------------------- the story

local function ease(style: string, dir: string, t: number): number
	return Motion.ease(style, dir, t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- a button's MotionScale over a hover at `hover`, a press at `press` (and its release)
local function pressScale(t: number, hover: number, press: number?, leave: number?): number
	local p = Motion.Press
	local n = Motion.Profiles.Normal
	if t < hover then
		return 1
	end
	if leave and t >= leave then
		return lerp(n.Hover, 1, ease("Quad", "Out", (t - leave) / p.HoverTime))
	end
	if not press or t < press then
		return lerp(1, n.Hover, ease("Quad", "Out", (t - hover) / p.HoverTime))
	end
	local up = press + p.DownTime + 0.05
	if t < up then
		return lerp(n.Hover, n.Down, ease("Quad", "Out", (t - press) / p.DownTime))
	end
	return lerp(n.Down, n.Hover, ease("Back", "Out", (t - up) / p.UpTime))
end

local T_OPEN = 0.5
local T_TAB_HOVER, T_TAB_PRESS = 2.6, 3.0
local T_SCROLL = T_TAB_PRESS + Motion.Press.DownTime + 0.05
local T_CARD_HOVER, T_CARD_PRESS = 4.6, 5.0
local T_CLOSE = 5.8
local T_GAIN1, T_GAIN2 = 6.2, 7.6
local T_SETTINGS = 8.6
local T_TOGGLE_HOVER = 9.8

local moneyTab = store.Tabs.Money
local megaCard = store.Cards.CoinsMega
local megaPrice = megaCard.Price
local megaAnchor = megaPrice.AnchorPoint -- (bottom right: Motion moves the anchor so it squashes about its middle)
-- the pointer's spot on that price, from where it rests (not the moved anchor)
local function megaPoint(): any
	local now = megaPrice.AnchorPoint
	megaPrice.AnchorPoint = megaAnchor
	local point = pointOn(megaPrice)
	megaPrice.AnchorPoint = now
	return point
end
local toggle = settings.Toggles.ReduceMotion.Button
local scrollTarget = StoreView.sectionTop(store, "Money")

-- the gains: coins before / after, where the money starts
local START = 4.82e6
local GAIN1, GAIN2 = 125000, 38000

-- the cash bits of a burst (the same LCG walk as Motion.flyTo, a fixed seed)
local layer = UIKit.new("Frame", {
	Name = "MotionFly",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 60,
}, hud.Gui)
local seed = 20261021
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
type Bit = { Frame: any, Start: number, Burst: any, Spin0: number, Spin1: number, Spin2: number }
local function burst(at: number): { Bit }
	local f = Motion.Fly
	local bits = {}
	for i = 1, f.Bits do
		local frame = Motion.makeBit(layer, "cash")
		local angle = (i / f.Bits) * math.pi * 2 + rand() * 0.8
		local reach = f.Spread * (0.55 + rand() * 0.45)
		local spin0 = (rand() - 0.5) * 50
		table.insert(bits, {
			Frame = frame,
			Start = at + (i - 1) * f.Gap,
			Burst = Vector2.new(math.cos(angle) * reach, math.sin(angle) * reach),
			Spin0 = spin0,
			Spin1 = spin0 + (rand() - 0.5) * 60,
			Spin2 = (rand() - 0.5) * 20,
		})
	end
	return bits
end
local bursts = { burst(T_GAIN1), burst(T_GAIN2) }
local screenCentre = Vector2.new(DW / 2, DH / 2)
local pileCentre = centreOf(cash)

local toasts = {
	{ At = T_GAIN1, Text = "Sold 12 ores for " .. Format.money(GAIN1) .. "!" },
	{ At = T_GAIN2, Text = "Podiums paid " .. Format.money(GAIN2) .. "!" },
}
for i, toast in toasts do
	local frame = HudBubble.toastColor(hud.Toasts, toast.Text, Color3.fromRGB(80, 200, 90))
	frame.LayoutOrder = i
	frame.Visible = false
	toast.Frame = frame
	toast.Scale = UIKit.new("UIScale", { Name = "MotionPop", Scale = 1 }, frame)
end

local captions = {
	{ 0.5, 2.55, "Okno obchodu vyskočí (pop + tmavé pozadí)" },
	{ 2.55, 3.6, "Tlačítko se zmáčkne a odskočí" },
	{ 3.6, 5.75, "BEST VALUE dýchá, zelené ceny se lesknou" },
	{ 5.75, 6.15, "Okno se zavře" },
	{ 6.15, 8.5, "Peníze naskakují, bankovky letí do počítadla" },
	{ 8.5, 11, "Nastavení: nový přepínač Reduce motion" },
}

-- the mouse path: (time, point) keys, eased between them; nil hides it
local function cursorAt(t: number): any?
	local tab = pointOn(moneyTab)
	local function between(a: any, b: any, t0: number, t1: number): any
		local k = ease("Sine", "InOut", (t - t0) / (t1 - t0))
		return a + (b - a) * k
	end
	if t < 1.4 or (t >= T_CLOSE and t < 8.9) then
		return nil
	end
	if t < T_TAB_HOVER then
		return between(Vector2.new(DW * 0.62, DH * 0.62), tab, 1.4, T_TAB_HOVER)
	elseif t < 3.6 then
		return tab
	elseif t < T_CARD_HOVER then
		return between(tab, megaPoint(), 3.6, T_CARD_HOVER)
	elseif t < T_CLOSE then
		return megaPoint()
	end
	local target = pointOn(toggle)
	if t < T_TOGGLE_HOVER then
		return between(Vector2.new(DW * 0.5, DH * 0.75), target, 8.9, T_TOGGLE_HOVER)
	end
	return target
end

local function frameAt(t: number): ({ any }, string?)
	-- the store: open, scrolled, closing
	local storeOpen = t >= T_OPEN and t < T_CLOSE + Motion.Close.Time
	store.Gui.Enabled = storeOpen
	if storeOpen then
		local since = t - T_OPEN
		if t >= T_CLOSE then
			local k = ease("Quad", "In", (t - T_CLOSE) / Motion.Close.Time)
			groupScale.Scale = lerp(1, Motion.Close.To, k)
			dim.BackgroundTransparency = lerp(dimBase, 1, ease("Quad", "Out", (t - T_CLOSE) / Motion.Close.Time))
		else
			groupScale.Scale = if since < Motion.Pop.Time then Motion.popScale(since) else 1
			dim.BackgroundTransparency = lerp(1, dimBase, ease("Quad", "Out", since / Motion.Pop.DimTime))
		end
		-- the tab column slides in from the right
		local slideFrom = Motion.slideAnchor(tabsAnchor, "Right", 36, Vector2.new(tabs.Size.X.Offset, 400))
		local k = ease("Quart", "Out", since / Motion.Slide.Time)
		tabs.AnchorPoint = slideFrom + (tabsAnchor - slideFrom) * k
		-- scrolled to MONEY by the tab (StoreController: 0.3 s, Quad out)
		local s = if t < T_SCROLL then 0 else ease("Quad", "Out", (t - T_SCROLL) / 0.3)
		store.Scroller.CanvasPosition = Vector2.new(0, scrollTarget * s)
		-- buttons
		moneyTab:FindFirstChildOfClass("UIScale").Scale = pressScale(t, T_TAB_HOVER, T_TAB_PRESS, 3.6)
		local megaScale = pressScale(t, T_CARD_HOVER, T_CARD_PRESS)
		megaPrice:FindFirstChildOfClass("UIScale").Scale = megaScale
		megaPrice.AnchorPoint = Motion.pivotAnchor(megaAnchor, megaScale)
		-- the loops (from the moment the store shows)
		for _, b in breathers do
			b:FindFirstChildOfClass("UIScale").Scale = Motion.breatheScale(since)
		end
		for _, s2 in shines do
			s2.Gradient.Offset = Vector2.new(Motion.shineOffset(since, s2.Phase), 0)
		end
	end
	-- the money: the panel pops, the number rolls up, cash flies in
	local coins = START
	local pop = 1
	for _, g in { { T_GAIN1, START, START + GAIN1 }, { T_GAIN2, START + GAIN1, START + GAIN1 + GAIN2 } } do
		local at, from, to = g[1], g[2], g[3]
		if t >= at then
			local time = Motion.countTime(from, to)
			coins = Motion.countValue(from, to, math.min(1, (t - at) / time))
			if t - at < 0.2 then
				pop = lerp(1.12, 1, ease("Quad", "Out", (t - at) / 0.2))
			end
		end
	end
	hud.Coins.Text = Format.money(coins)
	coinScale.Scale = pop
	local bump = 1
	for _, bits in bursts do
		for i, bit in bits do
			local p, k = Motion.flyAt(screenCentre, screenCentre + bit.Burst, pileCentre, t - bit.Start)
			local frame = bit.Frame
			frame.Visible = t >= bit.Start and p ~= nil
			if p then
				frame.Position = UDim2.fromOffset(p.X, p.Y)
				local size = Motion.Fly.Size
				frame.Size = UDim2.fromOffset(size.X * k, size.Y * k)
				local dt = t - bit.Start
				frame.Rotation = if dt < Motion.Fly.Burst
					then lerp(bit.Spin0, bit.Spin1, dt / Motion.Fly.Burst)
					else lerp(bit.Spin1, bit.Spin2, (dt - Motion.Fly.Burst) / Motion.Fly.Travel)
			end
			if i == 1 then
				local landed = t - (bit.Start + Motion.Fly.Burst + Motion.Fly.Travel)
				local b = Motion.Bump
				if landed >= 0 and landed < b.Time * 2 then
					local x = if landed < b.Time then landed / b.Time else (b.Time * 2 - landed) / b.Time
					bump = 1 + (b.Peak - 1) * ease("Quad", "Out", x)
				end
			end
		end
	end
	pileScale.Scale = bump
	for _, toast in toasts do
		local since = t - toast.At
		toast.Frame.Visible = since >= 0 and since < 3.2
		if since >= 0 then
			toast.Scale.Scale = if since < Motion.PopIn.Time
				then lerp(Motion.PopIn.From, 1, ease("Back", "Out", since / Motion.PopIn.Time))
				else 1
		end
	end
	-- settings
	settings.Gui.Enabled = t >= T_SETTINGS
	if t >= T_SETTINGS then
		local since = t - T_SETTINGS
		panelScale.Scale = if since < Motion.Pop.Time then Motion.popScale(since) else 1
		toggle:FindFirstChildOfClass("UIScale").Scale = pressScale(t, T_TOGGLE_HOVER)
	end
	-- the pointer
	local at = cursorAt(t)
	cursorGui.Enabled = at ~= nil
	if at then
		cursor.Position = UDim2.fromOffset(at.X, at.Y)
		local pressed = (t >= T_TAB_PRESS and t < T_SCROLL) or (t >= T_CARD_PRESS and t < T_CARD_PRESS + 0.12)
		cursor.Size = if pressed then UDim2.fromOffset(20, 20) else UDim2.fromOffset(26, 26)
	end
	local text: string? = nil
	for _, c in captions do
		if t >= c[1] and t < c[2] then
			text = c[3]
		end
	end
	return { hud.Gui, store.Gui, settings.Gui, cursorGui }, text
end

---------------------------------------------------------------- export

local outDir = root .. "/build/preview/ui_motion"
if fs.isDir(outDir) then
	fs.removeDir(outDir)
end
fs.writeDir(outDir)
local frames = {}
local total = math.floor(DURATION * FPS)
for i = 0, total - 1 do
	local t = i / FPS
	local guis, caption = frameAt(t)
	local name = string.format("frame_%04d.json", i)
	fs.writeFile(outDir .. "/" .. name, serde.encode("json", UiExport.export(guis)))
	table.insert(frames, { file = name, caption = caption })
end
-- the strip: the story in six pictures
local function index(t: number): number
	return math.floor(t * FPS + 0.5)
end
local strip = {
	{ index = index(T_OPEN), caption = "1 Okno začíná na 85 % a vyskočí" },
	{ index = index(T_TAB_PRESS + 0.06), caption = "2 Tlačítko zmáčknuté" },
	{ index = index(4.0), caption = "3 BEST VALUE dýchá, cena se leskne" },
	{ index = index(T_GAIN1 + 0.3), caption = "4 Bankovky letí do počítadla" },
	{ index = index(T_GAIN1 + 0.6), caption = "5 Číslo naskakuje" },
	{ index = index(T_SETTINGS + 1.6), caption = "6 Nastavení: Reduce motion" },
}
fs.writeFile(
	outDir .. "/manifest.json",
	serde.encode("json", { fps = FPS, width = W, height = H, frames = frames, strip = strip, columns = 3 })
)
print(`exported {total} frames -> build/preview/ui_motion`)
