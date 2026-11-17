--[[
	The shop v3's motion as frames (owner 2026-11-11: "cool and smooth, not
	laggy"; 2026-11-12: "improve the animations, add more things"): the
	window as StoreController moves it, every tween UI/ShopFx makes played
	back here (ShopFx.useTweens: the same calls, times and easings as
	TweenService in the game; no per-frame Lua in the game).

	  lune run tools/lune/export_shop_motion.luau [phone] [tour|open|golems|featured|blasters|passes|boosts|cash]
	  node tools/preview/render_ui_frames.mjs shop_motion[_<scenario>] shots/q_sky.jpg <out.mp4> <strip.jpg>

	Scenarios (frames in build/preview/shop_motion[_phone][_<scenario>]):
	  tour      (default) 0.0 s it opens: the pop (0.82 -> 1, Back out), the dim
	            fades in, a burst of rays flashes out, the header cascades in;
	            FEATURED's loops; 3.0 s the GOLEMS tab: its colours fade over,
	            its page slides in, its cards pop in; 4.7 s the mouse over the
	            x10 pack (1.04, it rises and brightens), a press (0.94), let go;
	            6.2 s it closes: it shrinks a little as the dim fades, then goes
	  open      the window opening (pop, burst, the title drops in, the tabs pop
	            in one after another, the X spins in), FEATURED for a moment,
	            then the GOLEMS tab picked (its icon pops)
	  golems    GOLEMS, already open (its loops running a while): the golems
	            bob and rock, the egg wobbles now and then, the rare tiles'
	            rays and sparkles, MYTHIC's rainbow, the Epic glow, the
	            sparkles rising round the egg, the cards' gloss one after
	            another, the counts and BEST VALUE wiggle, the title's light
	            band; the mouse over the x5 pack, then the x10 pack bought
	            (it flashes, pops, stars fly out)
	  featured  FEATURED the same way: embers over the Dragonforge, the dragon
	            king rocking, the shard wobbling over its breathing glow, the
	            tiles' golems, the stickers; the mouse over the pass, then the
	            Starter Pack bought
	  blasters / passes / boosts / cash  that tab open a while (4 s)
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

local phone = false
local scenario = "tour"
for _, arg in process.args do
	if arg == "phone" then
		phone = true
	else
		scenario = arg
	end
end
local W, H, FPS = 1600, 900, 30
local SCALE = if phone then 0.62 * 900 / 375 else H / 720

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

-- ShopFx's one-off timers (the open burst hidden, a celebration cleared) on this clock
local timers: { { At: number, Fn: () -> () } } = {}
ShopFx.useDelays(function(seconds: number, fn: () -> ())
	table.insert(timers, { At = clock + seconds, Fn = fn })
end)

-- Every running tween's value at the clock (a run whose thing is gone stops), then the timers due.
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
	local due = {}
	for i = #timers, 1, -1 do
		if timers[i].At <= clock + 1e-9 then
			table.insert(due, timers[i].Fn)
			table.remove(timers, i)
		end
	end
	for _, fn in due do
		fn()
		-- (a celebration's prizes are destroyed: their runs end with them)
		for _, run in runs do
			local alive, parent = pcall(function()
				return run.Target.Parent
			end)
			if run.Stopped == nil and (not alive or parent == nil) then
				run.Stopped = clock
			end
		end
	end
end

---------------------------------------------------------------- the window as the controller drives it

-- (a tab's own name: that tab open, its loops running a while: a quick look at its motion)
local TABS = { featured = "Featured", golems = "Golems", blasters = "Blasters", passes = "Passes", boosts = "Boosts", cash = "Cash" }
local start = TABS[scenario] or "Featured"
local hud = Preview.hud(Loader, SCALE)
local w, h = W / SCALE, (H - (if phone then 58 else 36)) / SCALE
local store = Preview.store(Loader, SCALE, w, h, start, phone)
local dim = store.Gui:FindFirstChild("Dim")
local windowLoops, tabLoops
local function playTab()
	ShopFx.stop(tabLoops)
	tabLoops = ShopFx.play(ShopFx.loopsUnder({ store.Pages[store.Current], store.TabRefs[store.Current].Lift }, store.Lean))
end
local function startLoops()
	windowLoops = ShopFx.play(ShopFx.loopsUnder(store.Fx, store.Lean))
	playTab()
end

-- A card's hover look as StoreView's shell binds it (ShopFx.bindPress): its light edge and glow.
local function lookOf(holder: any): any
	local face = holder:FindFirstChild("Face")
	local rim = if face then face:FindFirstChild("Rim") else nil
	return {
		Lift = ShopFx.Lift,
		Light = if rim then rim:FindFirstChild("Light") else nil,
		Glow = if face then face:FindFirstChild("Glow") else nil,
	}
end

-- ShopFx.bindPress: the mouse over a card (1.04, it rises and brightens), a press (0.94), let go, away
local function hover(cardId: string, hovered: boolean, held: boolean)
	local holder = store.Cards[cardId].Holder
	ShopFx.hover(holder, hovered, held, lookOf(holder))
end

type Event = { At: number, Do: () -> () }
local events: { Event }
local LENGTH: number
local WARM = 0 -- seconds the loops run before the first frame (an already open window)
local stripTimes: { number }

if scenario == "open" then
	LENGTH = 3.6
	stripTimes = { 0.03, 0.1, 0.17, 0.27, 1.2, 1.9, 2.05, 3.0 }
	events = {
		{
			At = 0,
			Do = function()
				-- StoreController.open: the loops, then ShopFx.open and the header's cascade
				startLoops()
				ShopFx.open(store.Group, dim, StoreView.DimTransparency, store.Burst)
				StoreView.cascade(store)
			end,
		},
		{
			At = 1.8,
			Do = function()
				-- StoreController.showTab: the colours, the slide, the cards' pop, the icon's pop; the new loops
				StoreView.selectTab(store, "Golems", true)
				Preview.liveEggs(store)
				playTab()
			end,
		},
	}
elseif scenario == "golems" or scenario == "featured" then
	LENGTH = 9
	WARM = 1.6
	local hovered = if scenario == "golems" then "Royal5" else "BigPass"
	local bought = if scenario == "golems" then "Royal10" else "StarterPack"
	stripTimes = { 0.4, 1.4, 2.4, 3.4, 4.2, 5.75, 6.0, 7.6 }
	events = {
		{
			At = -WARM,
			Do = function()
				startLoops()
			end,
		},
		{
			At = 3.3,
			Do = function()
				hover(hovered, true, false)
			end,
		},
		{
			At = 4.6,
			Do = function()
				hover(hovered, false, false)
			end,
		},
		{
			At = 5.6,
			Do = function()
				-- Roblox's prompt ended with a purchase: StoreController -> StoreView.celebrate
				StoreView.celebrate(store, store.Cards[bought].Key)
			end,
		},
	}
elseif TABS[scenario] then
	LENGTH = 4
	WARM = 1.6
	stripTimes = { 0.5, 1.5, 2.5, 3.5 }
	events = {
		{
			At = -WARM,
			Do = function()
				startLoops()
			end,
		},
	}
else
	-- (the tour: open, FEATURED, GOLEMS, a hover and a press, close)
	local TAB_AT, HOVER_AT, PRESS_AT, RELEASE_AT, LEAVE_AT, CLOSE_AT = 3, 4.7, 5.3, 5.45, 5.95, 6.2
	LENGTH = 6.6
	stripTimes = { 0.1, 0.25, 1.5, 3.1, 3.3, 4.4, 5.35, 6.3 }
	events = {
		{
			At = 0,
			Do = function()
				startLoops()
				ShopFx.open(store.Group, dim, StoreView.DimTransparency, store.Burst)
				StoreView.cascade(store)
			end,
		},
		{
			At = TAB_AT,
			Do = function()
				StoreView.selectTab(store, "Golems", true)
				Preview.liveEggs(store) -- (its egg piles, built just now)
				playTab()
			end,
		},
		{
			At = HOVER_AT,
			Do = function()
				hover("Royal10", true, false)
			end,
		},
		{
			At = PRESS_AT,
			Do = function()
				hover("Royal10", true, true)
			end,
		},
		{
			At = RELEASE_AT,
			Do = function()
				hover("Royal10", true, false)
			end,
		},
		{
			At = LEAVE_AT,
			Do = function()
				hover("Royal10", false, false)
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
end

---------------------------------------------------------------- frames

local dirName = (if phone then "shop_motion_phone" else "shop_motion") .. (if scenario == "tour" then "" else "_" .. scenario)
local outDir = root .. "/build/preview/" .. dirName
if fs.isDir(outDir) then
	fs.removeDir(outDir)
end
fs.writeDir(outDir)
local frames = {}
local total = math.floor(LENGTH * FPS)
local fired: { [number]: boolean } = {}
local function step(t: number)
	clock = t
	for k, event in events do
		if not fired[k] and clock >= event.At - 1e-9 then
			fired[k] = true
			event.Do()
		end
	end
	apply()
end
-- (an already open window: its loops ran a while before the first frame)
for i = math.floor(-WARM * FPS), -1 do
	step(i / FPS)
end
for i = 0, total - 1 do
	step(i / FPS)
	local name = string.format("frame_%04d.json", i)
	fs.writeFile(outDir .. "/" .. name, serde.encode("json", UiExport.export({ hud.Gui, store.Gui })))
	table.insert(frames, { file = name })
end
local strip = {}
for k, t in stripTimes do
	table.insert(strip, { index = math.min(total - 1, math.floor(t * FPS + 0.5)), caption = string.format("%d  %.2f s", k, t) })
end
fs.writeFile(
	outDir .. "/manifest.json",
	serde.encode("json", { fps = FPS, width = W, height = H, frames = frames, strip = strip, columns = 4 })
)
print(`exported {total} frames -> build/preview/{dirName}`)
