--[[
	The ELEVATOR window's motion as frames (owner 2026-11-15: "smooth
	animations": open, hover, purchase, locked, travel, close), every tween
	UI/ElevatorWindow and UI/ShopFx make played back here (useTweens: the same
	calls, times and easings as TweenService in the game; no per-frame Lua in
	the game).

	  lune run tools/lune/export_elevator_motion.luau [phone]
	  node tools/preview/render_ui_frames.mjs elevator_motion[_phone] <backdrop.jpg> <out.mp4> <strip.jpg>

	The tour (frames in build/preview/elevator_motion[_phone]), the owner's
	picture: blaster 8 at floor 1, floor 4 bought, floor 5 to buy, floor 6
	locked:
	  0.0 s it opens: the dim, the window grows from 0.94, the header drops
	        in, the X spins in, the cards pop in one after another; the
	        buttons' shine, the gold halo, the "?" and the clock run
	  1.5 s the mouse over EMBER CAVES (it rises, its button brightens, its
	        picture pans), away at 2.4 s
	  2.8 s PURCHASE on the STORMGLASS RIFT: pressed, let go; 3.1 s bought:
	        a gold flash, coins fly out, the coin pops, the coins count down,
	        the card turns to TRAVEL
	  4.6 s LOCKED on the HEARTSTONE CORE: it shakes, its lock flashes, the
	        requirement lights up, the message says which blaster
	  6.0 s TRAVEL to DEEP HOLLOW: its card lights up, the others dim
	  7.2 s it closes (the ride would start here)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox") :: any

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)
Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets").Previewing = true
local UI = "StarterPlayer.StarterPlayerScripts.Client.UI."
local ShopFx = Loader.requirePath(UI .. "ShopFx")
local ElevatorWindow = Loader.requirePath(UI .. "ElevatorWindow")
local Motion = Loader.requirePath(UI .. "Motion")
local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")

local phone = false
for _, arg in process.args do
	if arg == "phone" then
		phone = true
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

-- Its value now and whether it is over (its repeats, reversing when asked, Roblox's curves).
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
ElevatorWindow.useTweens(maker)

local timers: { { At: number, Fn: () -> () } } = {}
local function delayer(seconds: number, fn: () -> ())
	table.insert(timers, { At = clock + seconds, Fn = fn })
end
ShopFx.useDelays(delayer)
ElevatorWindow.useDelays(delayer)

-- Every running tween's value at the clock, then the timers due.
local function apply()
	for _, run in runs do
		if run.Stopped == nil then
			local alive, parent = pcall(function()
				return run.Target.Parent
			end)
			if not alive or (parent == nil and run.Target.ClassName ~= "NumberValue") then
				run.Stopped = clock
			else
				local now, over = valueAt(run, clock)
				if now then
					for property, value in now do
						run.Target[property] = value
					end
				end
				if over then
					run.Stopped = clock
				end
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
	end
end

---------------------------------------------------------------- the window as the controller drives it

local rift = MineFloors.get(5)
local palace = MineFloors.get(4)
local riftPrice = MineFloors.priceOf(5)
local coins = riftPrice + 1.25e6
local bought = { [palace.Id] = true }

local refs = ElevatorWindow.build(phone)
refs.Gui.Enabled = true
refs.Gui.Scale.Scale = SCALE
if phone then
	ElevatorWindow.layout(refs, 667 / 0.62, (375 - 36) / 0.62)
	ElevatorWindow.setHint(refs, "")
else
	ElevatorWindow.layout(refs, 1280, (900 - 36) / SCALE)
	ElevatorWindow.setHint(refs, "Click a floor  ·  Backspace: close")
end
ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, bought, coins))
ElevatorWindow.setStatus(refs, 8, coins)

local playing
local function restartLoops()
	ShopFx.stop(playing)
	playing = ShopFx.play(ElevatorWindow.loops(refs))
end

-- (ElevatorController.bindCard: the mouse over a card, its button pressed)
local function hover(index: number, on: boolean)
	ElevatorWindow.hover(refs.Cards[index], on)
end
local function press(index: number, held: boolean)
	local card = refs.Cards[index]
	ShopFx.hover(card.ButtonHolder, true, held)
end

type Event = { At: number, Do: () -> () }
local events: { Event } = {
	{
		At = 0,
		Do = function()
			ElevatorWindow.playOpen(refs)
			restartLoops()
		end,
	},
	{
		At = 1.5,
		Do = function()
			hover(2, true)
		end,
	},
	{
		At = 2.4,
		Do = function()
			hover(2, false)
		end,
	},
	{
		At = 2.8,
		Do = function()
			hover(5, true)
			press(5, true)
		end,
	},
	{
		At = 2.95,
		Do = function()
			press(5, false)
		end,
	},
	{
		At = 3.1,
		Do = function()
			-- the State has the Rift bought: ElevatorController.refresh
			bought[rift.Id] = true
			coins -= riftPrice
			ElevatorWindow.setFloors(refs, ElevatorWindow.entries(8, 1, bought, coins))
			ElevatorWindow.countCoins(refs, coins)
			ElevatorWindow.unlock(refs, refs.Cards[5])
			restartLoops()
		end,
	},
	{
		At = 3.9,
		Do = function()
			hover(5, false)
			ShopFx.hover(refs.Cards[5].ButtonHolder, false, false)
		end,
	},
	{
		At = 4.6,
		Do = function()
			ElevatorWindow.shake(refs.Cards[6])
			ElevatorWindow.showMessage(
				refs,
				`{MineFloors.get(6).Name} needs Blaster {MineFloors.get(6).MinBlaster}+. Buy a better blaster at the Blaster Vault.`,
				roblox.Color3.fromRGB(255, 96, 96)
			)
		end,
	},
	{
		At = 5.6,
		Do = function()
			ElevatorWindow.hideMessage(refs)
			hover(3, true)
		end,
	},
	{
		At = 6.0,
		Do = function()
			press(3, true)
		end,
	},
	{
		At = 6.15,
		Do = function()
			press(3, false)
			ElevatorWindow.pick(refs, 3)
		end,
	},
	{
		At = 7.2,
		Do = function()
			ElevatorWindow.playClose(refs, function() end)
		end,
	},
}
local LENGTH = 7.6
local stripTimes = { 0.12, 0.6, 1.9, 3.25, 3.6, 4.7, 6.4, 7.35 }

---------------------------------------------------------------- frames

local dirName = if phone then "elevator_motion_phone" else "elevator_motion"
local outDir = root .. "/build/preview/" .. dirName
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
	-- (ElevatorWindow.countCoins: the game's NumberValue.Changed writes the amount; here the frame does)
	local counter = refs.CoinAmount:FindFirstChild("CoinCount")
	if counter then
		ShopFx.setText(refs.CoinAmount, Format.short(math.floor(counter.Value)))
	end
	local name = string.format("frame_%04d.json", i)
	fs.writeFile(outDir .. "/" .. name, serde.encode("json", UiExport.export({ refs.Gui })))
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
