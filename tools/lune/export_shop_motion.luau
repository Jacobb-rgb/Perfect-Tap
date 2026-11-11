--[[
	The shop v3's motion as frames (owner 2026-11-11: the concept's 2 s loop,
	obrazky/novy_obchod_wow_2026-11-11/08_animace_featured.webp): the window as
	StoreController opens it, UI/ShopFx's driver stepped through two loops (the
	rays turn, the bolts flash, the shine sweeps the buy buttons, the open tab
	bobs, the Mythic rims run, the sparkles pulse), for render_ui_frames.mjs:

	  lune run tools/lune/export_shop_motion.luau [tab]          (default Featured)
	  node tools/preview/render_ui_frames.mjs shop_motion shots/<backdrop>.jpg <out.mp4> <strip.jpg>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")
local Preview = require("./lib/store_preview")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true
local ShopFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ShopFx")

local W, H, FPS = 1600, 900, 15
local SCALE = H / 720
local tab = process.args[1] or "Featured"

local hud = Preview.hud(Loader, SCALE)
local store = Preview.store(Loader, SCALE, W / SCALE, (H - 36) / SCALE, tab)
local tabRefs = store.TabRefs[store.Current]
local driver = ShopFx.start(store.Fx, store.Pages[store.Current], tabRefs.Lift, nil)

local outDir = root .. "/build/preview/shop_motion"
if fs.isDir(outDir) then
	fs.removeDir(outDir)
end
fs.writeDir(outDir)
local frames = {}
local total = math.floor(2 * ShopFx.Loop * FPS)
for i = 0, total - 1 do
	local t = i / FPS
	driver.step(t)
	local name = string.format("frame_%04d.json", i)
	fs.writeFile(outDir .. "/" .. name, serde.encode("json", UiExport.export({ hud.Gui, store.Gui })))
	table.insert(frames, { file = name })
end
driver.stop()
local strip = {}
for k, t in { 0, 0.33, 0.67, 1, 1.33, 1.67 } do
	table.insert(strip, { index = math.floor(t * FPS + 0.5), caption = string.format("%d  %.2f s", k, t) })
end
fs.writeFile(
	outDir .. "/manifest.json",
	serde.encode("json", { fps = FPS, width = W, height = H, frames = frames, strip = strip, columns = 3 })
)
print(`exported {total} frames ({tab}) -> build/preview/shop_motion`)
