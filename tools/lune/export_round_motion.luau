--[[
	The round look's motions (AnimConfig.RoundMotion, the UI pack reel's,
	2026-10-28): one UI frame per 1/30 s of a short story, drawn with the
	game's own builders and set at each moment by Motion's pure curves with
	the reel's tuning (Motion.RoundTuning):

	  0.3 s   the mouse on the red Shop tab: it grows 5 % in 0.1 s
	  0.7 s   a press: 0.93 for 0.1 s, back
	  1.0 s   the Store pops: half size, past full (1.1) at 0.09 s, settled by 0.2 s
	  2.0 s   a cash card's price: hover, press
	  3.0 s   the Store closes (0.9, the dim fading)

	  lune run tools/lune/export_round_motion.luau
	  -> build/preview/round_motion/frame_NNNN.json + manifest.json
	  node tools/preview/render_ui_frames.mjs round_motion shots/motion_backdrop.jpg <out.mp4> <strip.jpg>
	The backdrop: lune run tools/lune/export_scene.luau store, then
	  SHOTS_EXTRA=tools/preview/motion_shots.json node tools/preview/render.mjs store motion_backdrop
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox") :: any
local Vector2 = roblox.Vector2

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true
Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig").LightUI = true
local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
PopTheme.setLook("Round")

local UI = "StarterPlayer.StarterPlayerScripts.Client.UI."
local Motion = Loader.requirePath(UI .. "Motion")
Motion.setEnabled(true) -- (the preview shows the round motions on, whatever Config/AnimConfig ships)
Motion.tune(true)
local UIKit = Loader.requirePath(UI .. "UIKit")
local HudBubble = Loader.requirePath(UI .. "HudBubble")
local HudView = Loader.requirePath(UI .. "HudView")
local TeleportView = Loader.requirePath(UI .. "TeleportView")
local StoreView = Loader.requirePath(UI .. "StoreView")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")

local FPS = 30
local DURATION = 3.6
local SCALE = 1.25 -- 900 px tall render / 720 design height
local W, H = 1600, 900
local DW, DH = W / SCALE, (H - 36) / SCALE

-- the HUD (as the store preview draws it), its left tiles claimed
local hud = HudBubble.buildGame(SCALE, W)
TeleportView.build(hud.TopBar, SCALE, W / SCALE)
hud.Gui.Scale.Scale = SCALE
hud.Income.Text = Format.perSecond(1840)
hud.Coins.Text = Format.money(4820000)
for _, entry in HudBubble.gameMenu() do
	HudBubble.claimTile(hud.Menu, entry.Id)
end
HudView.setBackpack(hud, 12, 30)
hud.Toasts:ClearAllChildren()

local store = StoreView.build()
store.Gui.Scale.Scale = SCALE
StoreView.layout(store, DW, DH)
StoreView.setCoins(store, 1840)
store.Scroller.CanvasPosition = Vector2.new(0, StoreView.sectionTop(store, "Money"))
local dim = store.Gui:FindFirstChild("Dim") :: any
local dimBase = dim.BackgroundTransparency
local groupScale = UIKit.new("UIScale", { Name = "MotionPop", Scale = 1 }, store.Group)

-- the buttons the mouse visits: their own scale (Motion's MotionScale)
local function scaled(button: any): any
	return UIKit.new("UIScale", { Name = "MotionScale", Scale = 1 }, button)
end
local shop = hud.TopBar:FindFirstChild("ShopPill")
local shopScale = scaled(shop)
local price = store.Cards.CoinsSmall.Price
local priceScale = scaled(price)

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * math.clamp(k, 0, 1)
end

local function ease(style: string, direction: string, t: number): number
	return Motion.ease(style, direction, math.clamp(t, 0, 1))
end

-- hover (+5 % in 0.1 s), a press (0.93 in 0.1 s, held, back in 0.1 s), the mouse leaving
local function pressScale(t: number, hover: number, press: number, leave: number): number
	local p = Motion.Press
	local n = Motion.Profiles.Normal
	if t < hover then
		return 1
	end
	if t >= leave then
		return lerp(n.Hover, 1, ease("Quad", "Out", (t - leave) / p.HoverTime))
	end
	if t < press then
		return lerp(1, n.Hover, ease("Quad", "Out", (t - hover) / p.HoverTime))
	end
	local up = press + p.DownTime
	if t < up then
		return lerp(n.Hover, n.Down, ease("Quad", "Out", (t - press) / p.DownTime))
	end
	return lerp(n.Down, n.Hover, ease("Quad", "Out", (t - up) / p.UpTime))
end

local T_SHOP_HOVER, T_SHOP_PRESS, T_SHOP_LEAVE = 0.3, 0.7, 0.95
local T_OPEN = 1.0
local T_PRICE_HOVER, T_PRICE_PRESS, T_PRICE_LEAVE = 2.0, 2.4, 2.75
local T_CLOSE = 3.0

local function frameAt(t: number): ({ any }, string?)
	shopScale.Scale = pressScale(t, T_SHOP_HOVER, T_SHOP_PRESS, T_SHOP_LEAVE)
	local open = t >= T_OPEN and t < T_CLOSE + Motion.Close.Time
	store.Gui.Enabled = open
	if open then
		local since = t - T_OPEN
		if t >= T_CLOSE then
			local k = (t - T_CLOSE) / Motion.Close.Time
			groupScale.Scale = lerp(1, Motion.Close.To, ease("Quad", "In", k))
			dim.BackgroundTransparency = lerp(dimBase, 1, ease("Quad", "Out", k))
		else
			groupScale.Scale = Motion.roundPopScale(since)
			dim.BackgroundTransparency = lerp(1, dimBase, ease("Quad", "Out", since / Motion.Pop.DimTime))
		end
		priceScale.Scale = pressScale(t, T_PRICE_HOVER, T_PRICE_PRESS, T_PRICE_LEAVE)
	end
	local caption = if t < T_SHOP_PRESS
		then "Shop: +5 % under the mouse"
		elseif t < T_OPEN then "Shop: pressed to 93 %"
		elseif t < T_OPEN + 0.25 then "Store: 50 % -> 110 % -> 100 % in 0.2 s"
		elseif t < T_PRICE_HOVER then "Store open"
		elseif t < T_CLOSE then "R$19: hover, press"
		else "Store closes"
	return { hud.Gui, store.Gui }, caption
end

local outDir = root .. "/build/preview/round_motion"
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
local function index(t: number): number
	return math.floor(t * FPS + 0.5)
end
local strip = {
	{ index = index(T_SHOP_HOVER + 0.15), caption = "1 Shop +5 %" },
	{ index = index(T_SHOP_PRESS + 0.1), caption = "2 Shop 93 %" },
	{ index = index(T_OPEN + 0.0), caption = "3 Store 50 %" },
	{ index = index(T_OPEN + 0.1), caption = "4 Store 110 %" },
	{ index = index(T_OPEN + 0.3), caption = "5 Store 100 %" },
	{ index = index(T_PRICE_PRESS + 0.1), caption = "6 R$19 93 %" },
}
fs.writeFile(
	outDir .. "/manifest.json",
	serde.encode("json", { fps = FPS, width = W, height = H, frames = frames, strip = strip, columns = 3 })
)
print(`exported {total} frames -> build/preview/round_motion`)
