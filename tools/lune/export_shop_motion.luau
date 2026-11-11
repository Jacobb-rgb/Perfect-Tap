--[[
	The shop v3's motion as frames (owner 2026-11-11: "cool and smooth, not
	laggy"): the window as StoreController moves it, every tween UI/ShopFx
	makes played back here (ShopFx.useTweens: the same calls, times and
	easings as TweenService in the game; no per-frame Lua in the game):

	  0.0 s  it opens: the pop (0.82 -> 1, Back out), the dim fades in, a
	         burst of rays flashes out behind the window
	  ...    FEATURED: the rays turn slowly, the buy buttons' shine sweeps,
	         the bolts flash now and then, the sparkles twinkle, the hero
	         floats, the BEST VALUE button breathes, the open tab bobs
	  3.0 s  the GOLEMS tab: the header and body fade to its colours, the
	         page slides in, its cards pop in one after another
	  4.7 s  the mouse over the x10 pack (1.04), a press (0.94), let go
	  6.2 s  it closes: it shrinks a little as the dim fades, then goes

	  lune run tools/lune/export_shop_motion.luau [phone]
	  node tools/preview/render_ui_frames.mjs shop_motion shots/q_sky.jpg <out.mp4> <strip.jpg>
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
local StoreView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoreView")
local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")

local phone = process.args[1] == "phone"
local W, H, FPS = 1600, 900, 30
local SCALE = if phone then 0.62 * 900 / 375 else H / 720
local TAB_AT, HOVER_AT, PRESS_AT, RELEASE_AT, LEAVE_AT, CLOSE_AT, LENGTH = 3, 4.7, 5.3, 5.45, 5.95, 6.2, 6.6

---------------------------------------------------------------- a small TweenService

type Run = {
	Target: any,
	From: { [string]: any },
	Goal: { [string]: any },
	Time: number,
	Style: string,
	Direction: string,
	Repeats: number,
	Reverses: boolean,
	Start: number, -- (clock + delay)
	Stopped: number?,
}

local clock = 0
local runs: { Run } = {}

local function lerp(a: any, b: any, u: number): any
	if type(a) == "number" then
		return a + (b - a) * u
	end
	return a:Lerp(b, u)
end

-- Its value now and whether it is over: a run plays its repeats (-1: forever), reversing when
-- asked, on Roblox's curves (Motion.ease); nil while it waits for its delay.
local function valueAt(run: Run, t: number): ({ [string]: any }?, boolean)
	local local_ = t - run.Start
	if local_ < 0 then
		return nil, false
	end
	local time = math.max(run.Time, 1e-6)
	local legs = if run.Reverses then 2 else 1
	local cycle = time * legs
	local done = run.Repeats >= 0 and local_ >= cycle * (run.Repeats + 1)
	local k: number
	if done then
		k = if run.Reverses then 0 else 1
	else
		local within = local_ % cycle
		k = if within <= time then within / time else 2 - within / time
	end
	local u = Motion.ease(run.Style, run.Direction, k)
	local out = {}
	for property, goal in run.Goal do
		out[property] = lerp(run.From[property], goal, u)
	end
	return out, done
end

local function maker(
	instance: any,
	time: number,
	style: string,
	direction: string,
	goal: { [string]: any },
	repeats: number,
	reverses: boolean,
	delay: number
): any
	-- (a newer tween of a property stops the older one, as TweenService does)
	for _, other in runs do
		if other.Stopped == nil and other.Target == instance then
			for property in goal do
				if other.Goal[property] ~= nil then
					other.Stopped = clock
				end
			end
		end
	end
	local from = {}
	for property in goal do
		from[property] = instance[property]
	end
	local run: Run = {
		Target = instance,
		From = from,
		Goal = goal,
		Time = time,
		Style = style,
		Direction = direction,
		Repeats = repeats,
		Reverses = reverses,
		Start = clock + delay,
		Stopped = nil,
	}
	table.insert(runs, run)
	return {
		Play = function() end,
		Cancel = function()
			if run.Stopped == nil then
				-- (it stays where it got to)
				local now = valueAt(run, clock)
				if now then
					for property, value in now do
						run.Target[property] = value
					end
				end
				run.Stopped = clock
			end
		end,
	}
end
ShopFx.useTweens(maker)

-- Every running tween's value at the clock.
local function apply()
	for _, run in runs do
		if run.Stopped == nil then
			local now, over = valueAt(run, clock)
			if now then
				for property, value in now do
					run.Target[property] = value
				end
			end
			if over then
				run.Stopped = clock -- (it rests at its end)
			end
		end
	end
end

---------------------------------------------------------------- the window as the controller drives it

local hud = Preview.hud(Loader, SCALE)
local w, h = W / SCALE, (H - (if phone then 58 else 36)) / SCALE
local store = Preview.store(Loader, SCALE, w, h, "Featured", phone)
local dim = store.Gui:FindFirstChild("Dim")
local windowLoops, tabLoops
local function playTab()
	ShopFx.stop(tabLoops)
	tabLoops = ShopFx.play(ShopFx.loopsUnder({ store.Pages[store.Current], store.TabRefs[store.Current].Lift }, store.Compact))
end
local hovered = store.Cards.Royal10.Holder:FindFirstChild("Scale")

-- ShopFx.bindPress's tween: the mouse over a card (1.04), a press (0.94), let go, away
local function press(goal: number)
	maker(hovered, ShopFx.PressTime, "Quad", "Out", { Scale = goal }, 0, false, 0)
end

local events: { { At: number, Do: () -> () } } = {
	{
		At = 0,
		Do = function()
			-- StoreController.open: the loops, then ShopFx.open
			windowLoops = ShopFx.play(ShopFx.loopsUnder(store.Fx, store.Compact))
			playTab()
			ShopFx.open(store.Group, dim, StoreView.DimTransparency, store.Burst)
		end,
	},
	{
		At = TAB_AT,
		Do = function()
			-- StoreController.showTab: the colours, the slide, the cards' pop; the new tab's loops
			StoreView.selectTab(store, "Golems", true)
			Preview.liveEggs(store) -- (its egg piles, built just now)
			playTab()
		end,
	},
	{
		At = HOVER_AT,
		Do = function()
			press(ShopFx.Hover)
		end,
	},
	{
		At = PRESS_AT,
		Do = function()
			press(ShopFx.Press)
		end,
	},
	{
		At = RELEASE_AT,
		Do = function()
			press(ShopFx.Hover)
		end,
	},
	{
		At = LEAVE_AT,
		Do = function()
			press(1)
		end,
	},
	{
		At = CLOSE_AT,
		Do = function()
			-- StoreController.close: the window shrinks as the dim fades
			ShopFx.close(store.Group, dim, function() end)
		end,
	},
	{
		At = CLOSE_AT + 0.15,
		Do = function()
			-- (ShopFx.close's done: the window goes, then its loops stop)
			store.Gui.Enabled = false
			ShopFx.stop(windowLoops)
			ShopFx.stop(tabLoops)
		end,
	},
}

---------------------------------------------------------------- frames

local outDir = root .. "/build/preview/shop_motion"
if fs.isDir(outDir) then
	fs.removeDir(outDir)
end
fs.writeDir(outDir)
local frames = {}
local total = math.floor(LENGTH * FPS)
local fired: { [number]: boolean } = {}
for i = 0, total - 1 do
	clock = i / FPS
	for k, event in events do
		if not fired[k] and clock >= event.At - 1e-9 then
			fired[k] = true
			event.Do()
		end
	end
	apply()
	local name = string.format("frame_%04d.json", i)
	fs.writeFile(outDir .. "/" .. name, serde.encode("json", UiExport.export({ hud.Gui, store.Gui })))
	table.insert(frames, { file = name })
end
local strip = {}
for k, t in { 0.1, 0.25, 1.5, 3.1, 3.3, 4.4, 5.35, 6.3 } do
	table.insert(strip, { index = math.floor(t * FPS + 0.5), caption = string.format("%d  %.2f s", k, t) })
end
fs.writeFile(
	outDir .. "/manifest.json",
	serde.encode("json", { fps = FPS, width = W, height = H, frames = frames, strip = strip, columns = 4 })
)
print(`exported {total} frames -> build/preview/shop_motion`)
