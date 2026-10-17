--[[
	TrainController: everyone's ore trains on this screen, your train's HUD
	chip and the Mine Station panel (design v2, docs/plans/STEP2_PLAN.md).

	Trains (client visuals only; the server keeps nothing but times):
	- "TrainTrip" { UserId, PlotId, DepartAt, ArriveAt, Count, Color, Load }
	  (a list of them for a joining player) starts a trip, animated from
	  server time (workspace:GetServerTimeNow()). The legs follow the shares
	  of TrainConfig.Timeline, but the visible ones never get shorter than
	  MinQuarrySeconds / MinCoastSeconds / MinArriveSeconds: that time comes
	  out of the hidden underground leg, so the train still arrives at
	  ArriveAt (legSpans). The quarry leg runs from the Mine Station into the
	  visible mouth (PortalInset in front of the line's end, like Railway) of
	  the quarry portal on the plot's side (west plots x < 0: west portal);
	  hidden underground; the coast leg comes out of the south portal and runs
	  north along TrainConfig.lineFor(plot) to the plot's stop (ease in /
	  out). At the stop the wagons, not the locomotive, line up with the Ore
	  Pen (stopAt, kept short of the buffer stop).
	- At the stop the train waits for the server to unload it: the Fx
	  "TrainUnload" (plotId, count) or, for your own train, the State
	  snapshot (Waiting false, Moving 0). While an Ore Pen is full (Waiting:
	  your snapshot, or TrainTrip's Waiting for everyone's trains) it keeps
	  standing there loaded. Then only each wagon's "Hopper" tips about its
	  "TipPivot" toward the pen (TipUp / TipHold / TipDown seconds); from
	  PourThreshold to the end of the hold the rocks slide over the lip and
	  sink (the empty hopper keeps only its dark bed as a floor), dust and
	  ore chunks (two-block rocks) arc into the pen (high enough to clear the
	  Foundry), and the empty train rolls back south into the tunnel, at
	  most ReturnSpeed on average (returnSeconds: the far stops take longer
	  than TrainConfig.ReturnSeconds, which only gates the loading). Another
	  player's train that isn't Waiting and whose Fx never comes leaves after
	  HoldLimit seconds without tipping. A late unload the server re-sends
	  with moved times is the same train (mergeTrip: no rebuild).
	  Plot 4 (far north-west): the buffer stop at TrainConfig.BufferZ keeps
	  its train ~15 studs short of the pen centre, so its wagon stands at the
	  pen's south end and the ore flies in a little diagonally (centring it
	  needs a later BufferZ; World / Core config).
	- One track per line: trains never drive through each other on screen.
	  Every shown train is a Body on its track (the quarry line, the west or
	  the east coast line); occlude hides the cars of a lower ranked train
	  where they overlap a higher ranked one (yours first, then standing
	  trains, then moving ones by departure), so another train seems to pass
	  behind yours and comes out at its far end. (Real sidings at the stops
	  and a passing loop at the station need the World package.)
	- A train is a TrainBuilder.locomotive in the trip's color and 1-2
	  wagons with the load colors (dirty ore in the warm DirtyLoad clay;
	  anchored, no collisions or queries). Only trains within BuildRange
	  studs of the camera are built (one per frame, at most MaxBuilt); a
	  train that leaves the range goes into a small pool of spare trains and
	  is reused when the same train comes back. Cars behind a tunnel mouth
	  are hidden. One PreRender loop moves every part with one BulkMoveTo;
	  standing trains are only moved when something changes.
	  Wheels spin with the distance, steam puffs from the "Smoke" attachment
	  (pooled emitters, more when faster). One looping steam sound of this
	  controller follows the nearest moving locomotive and pulses with its
	  wheels (the chuff); a short double toot when a train sets off or leaves
	  the south tunnel (its own sound too: the shared Sfx pool stays free).
	- Your own train waits at the Mine Station whenever it isn't on a trip:
	  its first wagon on TrainConfig.QuarryStop under the station's loading
	  chute (Railway's TrainPoint), the locomotive toward your quarry portal,
	  the ore heap growing with Cargo / Capacity (from a small mound to the
	  full dome). That same train rolls off when it leaves (it is rebuilt for
	  the trip while underground); after a trip it backs out of the portal
	  into the station, parked by the time the server opens loading again
	  (unload + ReturnSeconds).

	HUD and panel (TrainView):
	- The chip under the coins: "TRAIN 6/8", the state and SEND (TrainAction
	  "Send"); while the train is away it counts the ore on board. Click /
	  tap the chip, press T or gamepad L3, or use the "Train" prompt (UIOffset
	  slot 2 under the server's Load / Send prompts on every Mine Station and
	  Mine Lift PromptPoint) to open the panel: cargo, trip time, SEND,
	  Capacity / Speed upgrades with BUY (TrainAction "Upgrade" { Kind }) and
	  the Express perk placeholder; the header shows your coins. X, B or
	  Backspace (or T / L3 again) close it; gamepads get a selected button
	  and the selection stays inside the panel. Opening it closes the Pen and
	  Sell panels; in build mode it says "finish building first"; the chip
	  hides behind it. On phones it sits at the bottom of the screen over the
	  carry bar, under the coins (when it has to cover them, the HUD coins
	  hide while it is open).
	- The server's "Load Train" prompts (tag "TrainPrompt", attribute Action
	  "Load") only show while you carry something (CarryCount).
	- Fx "TrainUnload": starts the unload above (dust and glints in that pen
	  when its train isn't on screen); "TrainLoad" (position): a puff and a
	  gulp at a hopper (and over your waiting wagon at the station).

	The pure math (ease, legSpans, legAt, poseAt, stopAt, parkedPose,
	returnSeconds, quarryMouth, wagonFlip, visible, occlude, pourFill,
	arcHeight, mergeTrip, ...) and the consist builder are exported for the
	Lune tests and the preview; the
	controllers it uses are required in init(), so this module also loads
	outside Roblox.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local SoundConfig = require(Shared.Config.SoundConfig)
local TrainConfig = require(Shared.Config.TrainConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Theme = require(Shared.Config.UITheme)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local TrainBuilder = require(Shared.Builders.TrainBuilder)
local Net = require(Shared.Net)
local TrainView = require(script.Parent.Parent.UI.TrainView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)

-- required in init(): they touch Players.LocalPlayer when loaded
type FxControllerModule = typeof(require(script.Parent.FxController))
type HudControllerModule = typeof(require(script.Parent.HudController))
type PenControllerModule = typeof(require(script.Parent.PenController))
type PromptControllerModule = typeof(require(script.Parent.PromptController))
type SellControllerModule = typeof(require(script.Parent.SellController))
type StateControllerModule = typeof(require(script.Parent.StateController))
type PlayerControlsModule = typeof(require(script.Parent.Parent.Util.PlayerControls))
local FxController: FxControllerModule
local HudController: HudControllerModule
local PenController: PenControllerModule
local PromptController: PromptControllerModule
local SellController: SellControllerModule
local StateController: StateControllerModule
local PlayerControls: PlayerControlsModule

local TrainController = {}

TrainController.BuildRange = 300 -- trains closer than this to the camera are built and animated
TrainController.DropRange = 340 -- ...and dropped again past this
TrainController.HideDepth = 44 -- studs a train runs on inside a tunnel (a locomotive + 2 wagons fit)
TrainController.PortalInset = 6 -- Railway: the quarry mouths stand this far in front of the line's ends
TrainController.BufferGap = 1.7 -- Railway: the coastal buffer stops' face, past the line's end
TrainController.LocoFront = 7.25 -- TrainBuilder: the locomotive's front buffers, ahead of its Root
TrainController.LocoBack = 7.15 -- ...its back coupler, behind the Root
TrainController.WagonLength = 12 -- a wagon, coupler to coupler
TrainController.TipAngle = math.rad(52) -- the hopper at full tip
TrainController.TipUp = 0.6 -- seconds: the hoppers tip up...
TrainController.TipHold = 0.5 -- ...pour...
TrainController.TipDown = 0.6 -- ...and come back down before the train rolls back
TrainController.PourThreshold = 0.7 -- tip at which the ore leaves the wagon
TrainController.MinQuarrySeconds = 3.5 -- the visible legs never run faster than this
TrainController.MinCoastSeconds = 6
TrainController.MinArriveSeconds = 0.6 -- standing at the stop before the arrival
TrainController.MinUndergroundShare = 0.1 -- of a very short trip that stays hidden
TrainController.HoldLimit = 300 -- seconds another player's train (not Waiting) stands at its stop without an unload Fx
TrainController.RollInSeconds = 3 -- your train backing into the station after a trip
TrainController.ReturnSpeed = 30 -- studs per second (average) an empty train backs down the coast line at most
TrainController.WagonSlots = 12 -- cargo one wagon shows; more makes a second wagon
TrainController.MaxBuilt = 6 -- trains built at once (each is ~100 parts)
TrainController.SpareMax = 4 -- built trains kept out of the world for reuse
TrainController.HeapDrop = 2.2 -- how far the ore rocks sink in an almost empty wagon (the end rocks 0.9 more)
TrainController.BedDrop = 1.3 -- ...and the dark bed under them (at 0 it is the empty hopper's floor)
TrainController.PourSlide = 3 -- studs the rocks slide toward the lip while they pour out
TrainController.OcclusionSlack = 0.05 -- cars of two trains may touch by this much before one hides
TrainController.PromptSlot = 2 -- TrainService's prompt slots: Load 0, Send 1, this panel prompt 2
TrainController.PromptSlotHeight = 72 -- UIOffset pixels per slot (TrainService.PromptSlotHeight)
TrainController.PromptDistance = 10 -- as TrainService's prompts
-- dirty ore in a wagon (the ores stay secret until cleaned): Kenney's warm
-- carriage-dirt clay, so a load reads at a glance
TrainController.DirtyLoad = { Color3.fromRGB(196, 134, 88), Color3.fromRGB(170, 112, 76), Color3.fromRGB(218, 160, 112) }
-- PlotBuilder's banner colors, for when a plot's Banner part isn't streamed in
TrainController.BannerColors = {
	Color3.fromRGB(220, 70, 50),
	Color3.fromRGB(240, 170, 40),
	Color3.fromRGB(80, 180, 90),
	Color3.fromRGB(60, 140, 220),
	Color3.fromRGB(160, 90, 220),
	Color3.fromRGB(230, 110, 170),
	Color3.fromRGB(60, 190, 190),
	Color3.fromRGB(240, 230, 210),
}

export type Leg = "Station" | "Quarry" | "Underground" | "Coast" | "Stopped" | "Unload" | "Return" | "Done" | "Parked"
export type EaseKind = "In" | "Out" | "InOut"

export type Pose = {
	Leg: Leg,
	Position: Vector3, -- the locomotive's Root (on the rails)
	Facing: Vector3, -- where the locomotive's front points (unit, level)
	Odometer: number, -- distance travelled along Facing (wheel spin)
	Speed: number, -- studs per second
	Tip: number, -- hopper tip, 0..1
	Pour: number, -- share of the load poured out during the unload, 0..1
	Hidden: boolean, -- underground or gone
	Portal: Vector3?, -- the tunnel mouth on this leg (on the rails)
	Normal: Vector3?, -- from that mouth toward the open side
}

-- A train on its track this frame (occlude): where its cars are along the line.
export type Body = {
	Track: string?, -- "Quarry" | "West" | "East" (nil: underground or gone)
	Offsets: { number }, -- each car's center behind the locomotive's Root
	Halves: { number }, -- each car's half length
	Centers: { number }, -- each car's center along the track
	Open: { boolean }, -- shows by the tunnels (TrainController.visible)
	Shown: { boolean }, -- shows after occlude
	Tier: number, -- 0 yours, 1 standing, 2 moving (lower hides the higher)
	Since: number, -- then the earlier departure first
	Id: number,
}

-- Seconds after the departure at which each leg ends.
export type Spans = { Quarry: number, Underground: number, Coast: number, Trip: number }

export type Trip = {
	UserId: number,
	PlotId: number,
	DepartAt: number,
	ArriveAt: number,
	Count: number,
	Color: Color3,
	Load: { Color3 },
	UnloadAt: number?, -- server time the unload began on this screen (nil: not yet)
	Waiting: boolean?, -- standing at the stop: the Ore Pen is full
	Quiet: boolean?, -- leaves its stop without unloading (no unload ever came)
}

export type Vehicle = {
	Model: Model,
	Parts: { BasePart },
	Base: { CFrame }, -- model-space CFrames as built
	Offsets: { CFrame }, -- model-space CFrames now (the heap sinks with the cargo)
	Wheels: { [number]: number }, -- part index -> rolling radius
	Tipping: { [number]: boolean }, -- part index -> tips with the Hopper
	Heap: { [number]: number }, -- part index -> how far it sinks when almost empty
	Rocks: { [number]: number }, -- part index -> its Transparency as built (the Ore rocks vanish when empty)
	Empty: boolean, -- the rocks are hidden (Fill 0)
	Pivot: CFrame, -- the TipPivot (model space)
	Offset: number, -- Root distance behind the locomotive's Root
	Half: number, -- half the coupler-to-coupler length
	Flip: boolean, -- turned 180 degrees (so the hopper tips toward the pen)
	Shown: boolean,
	Smoke: Attachment?,
	Loaded: boolean,
	Fill: number,
}

export type Consist = {
	Vehicles: { Vehicle },
	Key: string, -- what it was built from (consistKey; spare trains are reused by it)
	Steam: ParticleEmitter?,
	SteamRate: number,
	LastTip: number,
	Leg: Leg?,
	Load: { Color3 }, -- the chunk colors when it pours
	Count: number,
	Dirty: boolean, -- needs placing even when standing still
	PlacedAt: Vector3?, -- the pose it was last placed at (standing trains aren't moved again)
	PlacedTip: number,
	PlacedMask: number, -- which cars showed then (bit per car)
	Parked: boolean, -- your waiting train (also while it leaves the station)
	Body: Body, -- its place on the track this frame
	Pose: Pose?, -- this frame's pose (step)
	Trip: Trip?, -- this frame's trip (nil: your waiting train)
	Fresh: boolean, -- built this frame
}

local RAIL = Vector3.new(0, TrainBuilder.RailTop, 0)
local UP = Vector3.new(0, 1, 0)

---------------------------------------------------------------- pure math

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function level(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Easing value and its slope (per unit of f) for f in 0..1.
function TrainController.ease(kind: EaseKind, f: number): (number, number)
	local x = math.clamp(f, 0, 1)
	if kind == "In" then
		return x * x, 2 * x
	elseif kind == "Out" then
		return 1 - (1 - x) * (1 - x), 2 * (1 - x)
	end
	return x * x * (3 - 2 * x), 6 * x * (1 - x)
end

--[[
	When the legs of a trip of `duration` seconds end. The legs get their
	TrainConfig.Timeline shares, but the visible ones never run shorter than
	their minimum seconds: the time comes out of the hidden underground leg
	(at least MinUndergroundShare of the trip stays hidden; a trip too short
	for all the minimums shares the rest by the minimums).
]]
function TrainController.legSpans(duration: number): Spans
	local tl = TrainConfig.Timeline
	local d = math.max(duration, 0)
	local quarry = math.max(d * (tl.QuarryLeg[2] - tl.QuarryLeg[1]), TrainController.MinQuarrySeconds)
	local coast = math.max(d * (tl.CoastLeg[2] - tl.CoastLeg[1]), TrainController.MinCoastSeconds)
	local arrive = math.max(d * (tl.Unload[2] - tl.Unload[1]), TrainController.MinArriveSeconds)
	local visible = quarry + coast + arrive
	local room = d * (1 - TrainController.MinUndergroundShare)
	if visible > room then
		local k = room / visible
		quarry, coast, arrive = quarry * k, coast * k, arrive * k
	end
	local underground = d - quarry - coast - arrive
	return { Quarry = quarry, Underground = quarry + underground, Coast = quarry + underground + coast, Trip = d }
end

-- The leg `elapsed` seconds into a trip of `duration`, the fraction done and the leg's seconds.
function TrainController.legAt(elapsed: number, duration: number): (Leg, number, number)
	if elapsed < 0 then
		return "Station", 0, 0
	end
	local s = TrainController.legSpans(duration)
	local function within(leg: Leg, from: number, to: number): (Leg, number, number)
		local seconds = to - from
		return leg, math.clamp((elapsed - from) / math.max(seconds, 1e-6), 0, 1), seconds
	end
	if elapsed < s.Quarry then
		return within("Quarry", 0, s.Quarry)
	elseif elapsed < s.Underground then
		return within("Underground", s.Quarry, s.Underground)
	elseif elapsed < s.Coast then
		return within("Coast", s.Underground, s.Coast)
	end
	return within("Stopped", s.Coast, s.Trip)
end

-- The end of the quarry line on a plot's side (west plots x < 0: the west end) and the way back along the line.
local function quarryEnd(plot: WorldLayout.Plot): (Vector3, Vector3)
	local line = TrainConfig.QuarryLine
	local index = 1
	for i, point in line do
		local best = line[index]
		if (plot.Center.X < 0 and point.X < best.X) or (plot.Center.X >= 0 and point.X > best.X) then
			index = i
		end
	end
	local neighbour = if index == 1 then line[2] else line[index - 1]
	return line[index], level(neighbour - line[index]).Unit
end

-- The quarry wall portal on a plot's side (the end of TrainConfig.QuarryLine).
function TrainController.quarryPortal(plot: WorldLayout.Plot): Vector3
	local point = quarryEnd(plot)
	return point
end

-- The visible tunnel mouth of that portal (PortalInset in front of the line's end, as Railway builds it).
function TrainController.quarryMouth(plot: WorldLayout.Plot): Vector3
	local point, inward = quarryEnd(plot)
	return point + inward * TrainController.PortalInset
end

-- Root distances of the wagons behind the locomotive's Root (couplers touching).
function TrainController.wagonOffsets(wagons: number): { number }
	local offsets = {}
	for i = 1, wagons do
		offsets[i] = TrainController.LocoBack + TrainController.WagonLength * (i - 0.5)
	end
	return offsets
end

function TrainController.penCenter(plot: WorldLayout.Plot): Vector3
	return (WorldLayout.plotCFrame(plot) * CFrame.new(BaseLayout.Pen.Area.Center)).Position
end

--[[
	Where a plot's train stands at its stop (the locomotive's Root on the
	line): the wagons centered on the Ore Pen along the line, the
	locomotive's front buffers short of the buffer stop at the line's end.
]]
function TrainController.stopAt(plot: WorldLayout.Plot, wagons: number?): Vector3
	local line = TrainConfig.lineFor(plot)
	local mouth, last = line[1], line[#line]
	local north = level(last - mouth).Unit
	local count = math.clamp(wagons or 1, 1, 2)
	local mean = TrainController.LocoBack + TrainController.WagonLength * count / 2 -- the mean of wagonOffsets(count)
	local along = (TrainController.penCenter(plot) - mouth):Dot(north) + mean
	local nearest = TrainController.LocoBack + TrainController.WagonLength * count + 1 -- the last wagon out of the tunnel
	local farthest = level(last - mouth).Magnitude + TrainController.BufferGap - TrainController.LocoFront - 0.3
	return mouth + north * math.clamp(along, nearest, farthest)
end

-- The south tunnel mouth, the plot's stop and the direction north along the line.
function TrainController.coast(plot: WorldLayout.Plot, wagons: number?): (Vector3, Vector3, Vector3)
	local line = TrainConfig.lineFor(plot)
	local mouth = line[1]
	local stop = TrainController.stopAt(plot, wagons)
	return mouth, stop, level(stop - mouth).Unit
end

-- From the line toward the plot's Ore Pen (level, unit).
function TrainController.penSide(plot: WorldLayout.Plot): Vector3
	local _, stop, north = TrainController.coast(plot)
	local right = north:Cross(UP)
	return if (TrainController.penCenter(plot) - stop):Dot(right) < 0 then -right else right
end

-- Wagons tip to their +X side; turn them around when the pen lies on the other side.
function TrainController.wagonFlip(plot: WorldLayout.Plot): boolean
	local _, _, north = TrainController.coast(plot)
	return TrainController.penSide(plot):Dot(north:Cross(UP)) < 0
end

function TrainController.wagonCount(count: number): number
	return math.clamp(math.ceil(count / TrainController.WagonSlots), 1, 2)
end

-- Is this the server's dirty ore color (ItemBuilder.DirtyCrust)?
local function isDirt(color: Color3): boolean
	local dirt = ItemBuilder.DirtyCrust
	return math.abs(color.R - dirt.R) + math.abs(color.G - dirt.G) + math.abs(color.B - dirt.B) < 0.06
end

-- A trip's load colors as the wagons show them: dirty ore becomes the DirtyLoad shades (up to 6 colors).
function TrainController.displayLoad(load: { Color3 }): { Color3 }
	local out: { Color3 } = {}
	local dirtAdded = false
	for _, color in load do
		if isDirt(color) then
			if not dirtAdded then
				dirtAdded = true
				for _, shade in TrainController.DirtyLoad do
					table.insert(out, shade)
				end
			end
		else
			table.insert(out, color)
		end
	end
	if #out == 0 then
		for _, shade in TrainController.DirtyLoad do
			table.insert(out, shade)
		end
	end
	while #out > 6 do
		table.remove(out)
	end
	return out
end

-- Load colors shared out over the wagons (up to 3 each; Dirty Ore colors when empty).
function TrainController.splitLoad(load: { Color3 }, wagons: number): { { Color3 } }
	local source = TrainController.displayLoad(load)
	local out: { { Color3 } } = {}
	for w = 1, wagons do
		local colors: { Color3 } = {}
		for i = w, #source, wagons do
			if #colors < 3 then
				table.insert(colors, source[i])
			end
		end
		if #colors == 0 then
			for i = 1, math.min(3, #source) do
				table.insert(colors, source[(i + w - 2) % #source + 1])
			end
		end
		out[w] = colors
	end
	return out
end

-- How full each wagon looks (the front one fills first), 0..1.
function TrainController.wagonFills(cargo: number, capacity: number, wagons: number): { number }
	local fills = {}
	local per = capacity / math.max(wagons, 1)
	for i = 1, wagons do
		fills[i] = if per > 0 then math.clamp((cargo - per * (i - 1)) / per, 0, 1) else 0
	end
	return fills
end

local function pose(
	leg: Leg,
	position: Vector3,
	facing: Vector3,
	odometer: number,
	speed: number,
	tip: number,
	hidden: boolean,
	portal: Vector3?,
	normal: Vector3?
): Pose
	return {
		Leg = leg,
		Position = position,
		Facing = facing,
		Odometer = odometer,
		Speed = speed,
		Tip = tip,
		Pour = 0,
		Hidden = hidden,
		Portal = portal,
		Normal = normal,
	}
end

-- Seconds from the start of the unload until the train rolls back (tip up, pour, tip down).
function TrainController.unloadSeconds(): number
	local total = TrainController.TipUp + TrainController.TipHold + TrainController.TipDown
	return math.min(total, TrainConfig.ReturnSeconds * 0.4)
end

-- How far a plot's train backs from its stop into the south tunnel.
local function returnLength(plot: WorldLayout.Plot, wagons: number?): number
	local mouth, stop, north = TrainController.coast(plot, wagons)
	return (stop - (mouth - north * TrainController.HideDepth)).Magnitude
end

--[[
	Seconds from the start of the unload until a plot's empty train is gone
	in the south tunnel: the tipping, then the way back, at least
	TrainConfig.ReturnSeconds in all but never faster than ReturnSpeed on
	average (the far stops take longer; the server's ReturnSeconds only
	gates the loading at the station).
]]
function TrainController.returnSeconds(plot: WorldLayout.Plot, wagons: number?): number
	local tipping = TrainController.unloadSeconds()
	local rolling = math.max(TrainConfig.ReturnSeconds - tipping, returnLength(plot, wagons) / TrainController.ReturnSpeed)
	return tipping + rolling
end

-- `since` seconds after the unload began: the hoppers tip and come back down, then the train backs south into the tunnel.
local function unloadPose(plot: WorldLayout.Plot, wagons: number?, since: number): Pose
	local mouth, stop, north = TrainController.coast(plot, wagons)
	local total = TrainController.returnSeconds(plot, wagons)
	local r = math.max(since, 0)
	local inside = mouth - north * TrainController.HideDepth
	if r >= total then
		return pose("Done", inside + RAIL, north, 0, 0, 0, true, mouth + RAIL, north)
	end
	local tipping = TrainController.unloadSeconds()
	if r < tipping then
		local k = tipping / (TrainController.TipUp + TrainController.TipHold + TrainController.TipDown)
		local up, hold, down = TrainController.TipUp * k, TrainController.TipHold * k, TrainController.TipDown * k
		local tip: number
		if r < up then
			tip = TrainController.ease("Out", r / up)
		elseif r < up + hold then
			tip = 1
		else
			tip = 1 - (TrainController.ease("InOut", (r - up - hold) / down))
		end
		local p = pose("Unload", stop + RAIL, north, 0, 0, tip, false, mouth + RAIL, north)
		-- the load pours from the moment the tip passes PourThreshold (ease Out) to the end of the hold
		local from = up * (1 - math.sqrt(1 - TrainController.PourThreshold))
		p.Pour = math.clamp((r - from) / math.max(up + hold - from, 1e-3), 0, 1)
		return p
	end
	local length = (stop - inside).Magnitude
	local rolling = total - tipping
	local e, slope = TrainController.ease("InOut", (r - tipping) / rolling)
	local s = length * e
	local p = pose("Return", stop - north * s + RAIL, north, -s, length * slope / rolling, 0, false, mouth + RAIL, north)
	p.Pour = 1
	return p
end

-- The quarry leg: where it starts (first wagon on QuarryStop), its direction, its length into the tunnel and the mouth.
local function quarryRun(plot: WorldLayout.Plot): (Vector3, Vector3, number, Vector3)
	local mouth = TrainController.quarryMouth(plot)
	local dir = level(mouth - TrainConfig.QuarryStop).Unit
	local start = TrainConfig.QuarryStop + dir * TrainController.wagonOffsets(1)[1]
	return start, dir, (mouth - start):Dot(dir) + TrainController.HideDepth, mouth
end

--[[
	Where a plot's train is at `now` (server time) on a trip from departAt to
	arriveAt with `wagons` wagons (1 by default): the locomotive's Root on
	the rails, where it faces, how far it has rolled, its speed and the
	hoppers' tip. After the arrival it stands at the stop until `unloadAt`
	(nil: not unloaded yet), then unloads and rolls back.
]]
function TrainController.poseAt(
	plot: WorldLayout.Plot,
	departAt: number,
	arriveAt: number,
	now: number,
	wagons: number?,
	unloadAt: number?
): Pose
	local duration = arriveAt - departAt
	if duration <= 0 then
		local mouth, _, north = TrainController.coast(plot, wagons)
		return pose("Done", mouth - north * TrainController.HideDepth + RAIL, north, 0, 0, 0, true, mouth + RAIL, north)
	end
	if now >= arriveAt and unloadAt and now >= unloadAt then
		return unloadPose(plot, wagons, now - unloadAt)
	end
	local leg, f, legSeconds = TrainController.legAt(now - departAt, duration)
	legSeconds = math.max(legSeconds, 1e-3)
	if leg == "Station" or leg == "Quarry" or leg == "Underground" then
		local start, dir, length, mouth = quarryRun(plot)
		if leg == "Underground" then
			return pose("Underground", start + dir * length + RAIL, dir, length, 0, 0, true, mouth + RAIL, -dir)
		end
		local e, slope = TrainController.ease("In", f)
		local s = length * e
		local speed = if leg == "Station" then 0 else length * slope / legSeconds
		return pose(leg, start + dir * s + RAIL, dir, s, speed, 0, false, mouth + RAIL, -dir)
	end
	local mouth, stop, north = TrainController.coast(plot, wagons)
	if leg == "Coast" then
		local start = mouth - north * TrainController.HideDepth
		local length = (stop - start).Magnitude
		local e, slope = TrainController.ease("InOut", f)
		local s = length * e
		return pose("Coast", start + north * s + RAIL, north, s - length, length * slope / legSeconds, 0, false, mouth + RAIL, north)
	end
	-- at the stop, loaded, until the server unloads it
	return pose("Stopped", stop + RAIL, north, 0, 0, 0, false, mouth + RAIL, north)
end

--[[
	Your train at the Mine Station: its first wagon on QuarryStop (under the
	loading chute), the locomotive toward your quarry portal. `sinceRoll` =
	seconds since it began to roll in after a trip (rollInAt): for
	RollInSeconds it backs out of that portal into the station.
]]
function TrainController.parkedPose(plot: WorldLayout.Plot, sinceRoll: number?): Pose
	local start, dir, length, mouth = quarryRun(plot)
	local away, speed = 0, 0
	if sinceRoll and sinceRoll >= 0 and sinceRoll < TrainController.RollInSeconds then
		local e, slope = TrainController.ease("Out", sinceRoll / TrainController.RollInSeconds)
		away = length * (1 - e)
		speed = length * slope / TrainController.RollInSeconds
	end
	return pose("Parked", start + dir * away + RAIL, dir, away, speed, 0, false, mouth + RAIL, -dir)
end

-- When your train starts backing into the station after an unload at `unloadAt`: parked by the time the server lets it load again.
function TrainController.rollInAt(unloadAt: number): number
	return unloadAt + TrainConfig.ReturnSeconds - TrainController.RollInSeconds
end

-- A vehicle centered at `center` (half its length `half`) shows unless it is all inside a tunnel.
function TrainController.visible(p: Pose, center: Vector3, half: number): boolean
	if p.Hidden then
		return false
	end
	local portal, normal = p.Portal, p.Normal
	if portal and normal then
		return (center - portal):Dot(normal) + half > 0
	end
	return true
end

-- Which track a pose is on (nil: underground or gone): the quarry line, or the west / east coast line.
function TrainController.trackOf(p: Pose): string?
	local leg = p.Leg
	if p.Hidden or leg == "Underground" or leg == "Done" then
		return nil
	elseif leg == "Station" or leg == "Quarry" or leg == "Parked" then
		return "Quarry"
	end
	return if p.Position.X < 0 then "West" else "East"
end

-- How a train ranks on its track: yours (0) before standing trains (1) before moving ones (2).
function TrainController.tierOf(p: Pose, mine: boolean): number
	if mine then
		return 0
	end
	local leg = p.Leg
	return if leg == "Stopped" or leg == "Unload" or leg == "Station" or leg == "Parked" then 1 else 2
end

-- A body for cars at `offsets` behind the locomotive's Root, `halves` long each way.
function TrainController.newBody(offsets: { number }, halves: { number }): Body
	return {
		Track = nil,
		Offsets = offsets,
		Halves = halves,
		Centers = {},
		Open = {},
		Shown = {},
		Tier = 2,
		Since = 0,
		Id = 0,
	}
end

-- The nominal body of a locomotive with `wagons` wagons (as TrainBuilder builds them).
function TrainController.nominalBody(wagons: number): Body
	local offsets, halves = { 0 }, { TrainController.LocoFront }
	for i, offset in TrainController.wagonOffsets(wagons) do
		offsets[i + 1] = offset
		halves[i + 1] = TrainController.WagonLength / 2
	end
	return TrainController.newBody(offsets, halves)
end

-- Puts a body on its track for pose `p` (the cars' centers along the line, which show by the tunnels).
function TrainController.fillBody(body: Body, p: Pose, tier: number, since: number, id: number)
	local track = TrainController.trackOf(p)
	body.Track = track
	body.Tier = tier
	body.Since = since
	body.Id = id
	for i, offset in body.Offsets do
		local center = p.Position - p.Facing * offset
		body.Centers[i] = if track == "Quarry" then center.X else center.Z
		local open = track ~= nil and TrainController.visible(p, center, body.Halves[i])
		body.Open[i] = open
		body.Shown[i] = open
	end
end

local function bodyBefore(a: Body, b: Body): boolean
	if a.Tier ~= b.Tier then
		return a.Tier < b.Tier
	elseif a.Since ~= b.Since then
		return a.Since < b.Since
	end
	return a.Id < b.Id
end

--[[
	One track, no ghosts: in rank order (bodyBefore), a car shows only where
	it doesn't overlap a shown car of a higher ranked train on the same
	track. So another player's train passes behind your train or a standing
	one (it hides at the near end and comes out at the far end). Sorts
	`bodies` in place.
]]
function TrainController.occlude(bodies: { Body })
	table.sort(bodies, bodyBefore)
	local slack = TrainController.OcclusionSlack
	for i, body in bodies do
		local track = body.Track
		for v, center in body.Centers do
			local show = body.Open[v]
			if show and track then
				local half = body.Halves[v]
				for j = 1, i - 1 do
					local other = bodies[j]
					if other.Track == track then
						for w, c in other.Centers do
							if other.Shown[w] and math.abs(center - c) < half + other.Halves[w] - slack then
								show = false
								break
							end
						end
						if not show then
							break
						end
					end
				end
			end
			body.Shown[v] = show
		end
	end
end

-- How full the wagons of a trip look at a pose: the load slides out while the
-- hopper pours (Pour) and stays out on the way back (nil = as built).
function TrainController.pourFill(p: Pose): number?
	if p.Leg == "Return" or p.Leg == "Done" then
		return 0
	elseif p.Leg == "Unload" and p.Pour > 0 then
		return 1 - p.Pour
	end
	return nil
end

-- Where the ore leaves a tipped wagon `offset` studs behind the locomotive:
-- over the hopper's lip on the pen side.
function TrainController.pourMouth(p: Pose, offset: number, plot: WorldLayout.Plot): Vector3
	return p.Position - p.Facing * offset + TrainController.penSide(plot) * 3 + Vector3.new(0, 5, 0)
end

--[[
	A flying ore chunk is a little rock like TrainBuilder's load: two
	slightly flattened blocks of one color turned 45 degrees apart (Kenney's
	octagonal boulder; the turned one a bit narrower and taller, so it reads
	as a chamfered rock, not a star), RockSize studs across, a little dusty.
]]
TrainController.RockSize = { 0.7, 1.0 }
TrainController.RockSquash = 0.78

function TrainController.rockPair(cf: CFrame): (CFrame, CFrame)
	return cf * CFrame.Angles(0.1, 0, 0.12), cf * CFrame.Angles(-0.12, math.pi / 4, 0.05)
end

function TrainController.rockSizes(size: number): (Vector3, Vector3)
	local squash = TrainController.RockSquash
	return Vector3.new(size, size * squash, size), Vector3.new(size * 0.84, size * squash * 1.12, size * 0.84)
end

function TrainController.rockColor(color: Color3, i: number): Color3
	local dirt = TrainController.DirtyLoad
	return color:Lerp(dirt[(i - 1) % #dirt + 1], 0.25)
end

-- A flying ore chunk at t (0..1) of its arc from `from` to `to`, `height` studs over the line.
function TrainController.arc(from: Vector3, to: Vector3, height: number, t: number): Vector3
	local f = math.clamp(t, 0, 1)
	return from:Lerp(to, f) + Vector3.new(0, 4 * height * f * (1 - f), 0)
end

-- An arc height of at least `height` that carries a chunk from `from` to `to` over the plot's Foundry.
function TrainController.arcHeight(plot: WorldLayout.Plot, from: Vector3, to: Vector3, height: number): number
	local rect = BaseLayout.Foundry
	local cf = WorldLayout.plotCFrame(plot)
	local top = cf.Position.Y + rect.Size.Y + 1.5
	local need = height
	for i = 1, 19 do
		local f = i / 20
		local at = from:Lerp(to, f)
		local l = cf:PointToObjectSpace(at) - rect.Center
		if math.abs(l.X) <= rect.Size.X / 2 + 1 and math.abs(l.Z) <= rect.Size.Z / 2 + 1 then
			need = math.max(need, (top - at.Y) / (4 * f * (1 - f)))
		end
	end
	return need
end

--[[
	A landing spot in a plot's Ore Pen for roll1, roll2 in 0..1 (3 studs
	inside the fence). With `near` (a wagon), the spot lies in the pen's
	rail-side half, across from that wagon, so the chunks fly a short way.
]]
function TrainController.penSpot(plot: WorldLayout.Plot, roll1: number, roll2: number, near: Vector3?): Vector3
	local area = BaseLayout.Pen.Area
	local cf = WorldLayout.plotCFrame(plot)
	local hx, hz = area.Size.X / 2 - 3, area.Size.Z / 2 - 3
	local x, z = (roll1 - 0.5) * 2 * hx, (roll2 - 0.5) * 2 * hz
	if near then
		local l = cf:PointToObjectSpace(near) - area.Center
		x = math.clamp(l.X + (roll1 - 0.5) * 8, -hx, hx)
		z = roll2 * hz -- plot-local +Z is the rail (sea) side
	end
	return (cf * CFrame.new(area.Center + Vector3.new(x, 0.6, z))).Position
end

-- Root distances behind the locomotive's Root for a consist (couplers touching).
function TrainController.consistOffsets(locoBack: number, wagonFront: number, wagonBack: number, wagons: number): { number }
	local offsets = { 0 }
	local back = locoBack
	local offset = 0
	for _ = 1, wagons do
		offset += back - wagonFront
		table.insert(offsets, offset)
		back = wagonBack
	end
	return offsets
end

-- A trip from a TrainTrip payload, or nil when it is junk.
function TrainController.parseTrip(raw: any, fallbackColor: ((number) -> Color3)?): Trip?
	if type(raw) ~= "table" then
		return nil
	end
	local userId, plotId = raw.UserId, raw.PlotId
	local departAt, arriveAt = raw.DepartAt, raw.ArriveAt
	if type(userId) ~= "number" or type(plotId) ~= "number" or not WorldLayout.Plots[plotId] then
		return nil
	end
	if not finite(departAt) or not finite(arriveAt) or arriveAt <= departAt or arriveAt - departAt > 600 then
		return nil
	end
	local load: { Color3 } = {}
	if type(raw.Load) == "table" then
		for _, color in raw.Load do
			if typeof(color) == "Color3" and #load < 6 then
				table.insert(load, color)
			end
		end
	end
	local color: Color3
	if typeof(raw.Color) == "Color3" then
		color = raw.Color
	elseif fallbackColor then
		color = fallbackColor(plotId)
	else
		color = TrainController.BannerColors[(plotId - 1) % #TrainController.BannerColors + 1]
	end
	return {
		UserId = userId,
		PlotId = plotId,
		DepartAt = departAt,
		ArriveAt = arriveAt,
		Count = if finite(raw.Count) then math.max(1, math.floor(raw.Count)) else 1,
		Color = color,
		Load = load,
		Waiting = if raw.Waiting == true then true else nil,
	}
end

local function sameColors(a: { Color3 }, b: { Color3 }): boolean
	if #a ~= #b then
		return false
	end
	for i, color in a do
		if color ~= b[i] then
			return false
		end
	end
	return true
end

--[[
	A TrainTrip for a player whose trip we already know (pure). The same
	DepartAt is the same trip again (the join list and the event, the
	Waiting announcement, or the late unload with its new ArriveAt); a moved
	DepartAt on a train that stands at its stop with the same look is the
	late unload after a very long wait (the server shifts DepartAt to stay
	under MaxTripSpan). Both keep what this screen knows (UnloadAt, Quiet),
	take the new times and Waiting (a TrainTrip without it clears it) and
	the richer look. Anything else is a new trip. Returns the trip to keep
	and whether its train must be rebuilt (its look changed).
]]
function TrainController.mergeTrip(existing: Trip?, incoming: Trip, now: number): (Trip, boolean)
	if not existing then
		return incoming, false
	end
	local same = existing.DepartAt == incoming.DepartAt
	local sameLook = existing.PlotId == incoming.PlotId
		and existing.Count == incoming.Count
		and existing.Color == incoming.Color
		and sameColors(existing.Load, incoming.Load)
	-- (TrainService: DepartAt = the unload - the trip's seconds, ArriveAt = the unload, i.e. now;
	-- a new departure arrives in the future)
	local shifted = not same
		and sameLook
		and existing.UnloadAt == nil
		and now >= existing.ArriveAt
		and incoming.ArriveAt >= existing.ArriveAt
		and incoming.ArriveAt <= now + 1
		and math.abs((incoming.ArriveAt - incoming.DepartAt) - (existing.ArriveAt - existing.DepartAt)) < 1e-3
	if not same and not shifted then
		return incoming, true
	end
	-- (a payload without load colors never replaces one with them)
	local look = if #incoming.Load > 0 or #existing.Load == 0 then incoming else existing
	local merged: Trip = {
		UserId = incoming.UserId,
		PlotId = incoming.PlotId,
		DepartAt = incoming.DepartAt,
		ArriveAt = incoming.ArriveAt,
		Count = look.Count,
		Color = look.Color,
		Load = look.Load,
		UnloadAt = existing.UnloadAt,
		Waiting = incoming.Waiting,
		Quiet = existing.Quiet,
	}
	local rebuild = merged.PlotId ~= existing.PlotId
		or merged.Count ~= existing.Count
		or merged.Color ~= existing.Color
		or not sameColors(merged.Load, existing.Load)
	return merged, rebuild
end

--[[
	What the client knows about your trip after a State snapshot (pure):
	"Waiting" (at the stop, pen full), "Unloaded" (the server unloaded it),
	"Gone" (the server has no trip any more: it was delivered without an
	animation) or nil (nothing new).
]]
function TrainController.snapshotNews(trip: Trip, train: TrainView.Snapshot, now: number): ("Waiting" | "Unloaded" | "Gone")?
	if trip.UnloadAt then
		return nil
	end
	local departAt, arriveAt = train.DepartAt, train.ArriveAt
	if not departAt or not arriveAt then
		return if now > trip.ArriveAt + 1 then "Gone" else nil
	end
	if math.abs(departAt - trip.DepartAt) > 0.5 then
		return nil
	end
	if train.Waiting then
		return "Waiting"
	elseif train.Moving == 0 and now >= arriveAt then
		return "Unloaded"
	end
	return nil
end

-- What a consist is built from: spare trains are reused for the same key.
function TrainController.consistKey(color: Color3, loads: { { Color3 } }, flip: boolean): string
	local parts = { color:ToHex(), if flip then "F" else "N" }
	for _, load in loads do
		local hexes = {}
		for _, c in load do
			table.insert(hexes, c:ToHex())
		end
		table.insert(parts, if #hexes > 0 then table.concat(hexes, ",") else "E")
	end
	return table.concat(parts, "|")
end

---------------------------------------------------------------- consists

local function couplerZ(model: Model, name: string): number
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name == name then
			local parent = d.Parent
			if parent and parent:IsA("BasePart") then
				return (parent.CFrame * d.CFrame).Position.Z
			end
		end
	end
	return 0
end

-- Collects a freshly built vehicle (still at the origin) for moving.
local function newVehicle(model: Model, flip: boolean): Vehicle
	local vehicle: Vehicle = {
		Model = model,
		Parts = {},
		Base = {},
		Offsets = {},
		Wheels = {},
		Tipping = {},
		Heap = {},
		Rocks = {},
		Empty = false,
		Pivot = CFrame.new(),
		Offset = 0,
		Half = math.max(math.abs(couplerZ(model, "CouplerFront")), math.abs(couplerZ(model, "CouplerBack"))),
		Flip = flip,
		Shown = false,
		Smoke = nil,
		Loaded = false,
		Fill = 1,
	}
	local hopper = model:FindFirstChild("Hopper")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(vehicle.Parts, d)
			local i = #vehicle.Parts
			vehicle.Base[i] = d.CFrame
			vehicle.Offsets[i] = d.CFrame
			local radius = d:GetAttribute("Radius")
			if d.Name == "Wheel" and type(radius) == "number" and radius > 0 then
				vehicle.Wheels[i] = radius
			end
			if hopper and d:IsDescendantOf(hopper) then
				vehicle.Tipping[i] = true
				if d.Name == "Ore" then
					-- the end chunks sink further: a low load peaks in the middle
					local drop = TrainController.HeapDrop
					vehicle.Heap[i] = if math.abs(d.CFrame.Position.Z) > 1.5 then drop + 0.9 else drop
					vehicle.Rocks[i] = d.Transparency
					vehicle.Loaded = true
				elseif d.Name == "OreBed" then
					vehicle.Heap[i] = TrainController.BedDrop
				end
			end
		elseif d:IsA("Attachment") then
			local parent = d.Parent
			if d.Name == "TipPivot" and parent and parent:IsA("BasePart") then
				vehicle.Pivot = parent.CFrame * d.CFrame
			elseif d.Name == "Smoke" then
				vehicle.Smoke = d
			end
		end
	end
	return vehicle
end

--[[
	Sinks a wagon's ore heap for a fill of 0..1 (1 = the full TrainBuilder
	heap). `pouring`: the rocks also slide toward the tipping side (+X, over
	the lip). At 0 the rocks vanish and only the dark bed stays, deep down
	as the empty hopper's floor; any fill above 0 brings them back.
]]
function TrainController.setFill(vehicle: Vehicle, fill: number, pouring: boolean?)
	local f = math.clamp(fill, 0, 1)
	vehicle.Fill = f
	local slide = if pouring then TrainController.PourSlide * (1 - f) else 0
	for i, drop in vehicle.Heap do
		local x = if vehicle.Rocks[i] then slide else 0
		vehicle.Offsets[i] = vehicle.Base[i] + Vector3.new(x, -drop * (1 - f), 0)
	end
	local empty = f <= 1e-3
	if empty ~= vehicle.Empty then
		vehicle.Empty = empty
		for i, transparency in vehicle.Rocks do
			vehicle.Parts[i].Transparency = if empty then 1 else transparency
		end
	end
end

--[[
	A locomotive in `color` and one wagon per entry of `loads` (an empty list
	builds an empty wagon). Models are built at the origin and not parented;
	placeConsist moves and shows them.
]]
function TrainController.buildConsist(color: Color3, loads: { { Color3 } }, flip: boolean, key: string?): Consist
	local loco = newVehicle(TrainBuilder.locomotive(color), false)
	local vehicles = { loco }
	local back = couplerZ(loco.Model, "CouplerBack")
	local offset = 0
	for _, load in loads do
		local model = TrainBuilder.wagon(color, if #load > 0 then load else nil)
		local wagon = newVehicle(model, flip)
		local front, wagonBack = couplerZ(model, "CouplerFront"), couplerZ(model, "CouplerBack")
		if flip then
			front, wagonBack = -wagonBack, -front
		end
		offset += back - front
		wagon.Offset = offset
		back = wagonBack
		table.insert(vehicles, wagon)
	end
	local offsets, halves = {}, {}
	for i, vehicle in vehicles do
		offsets[i] = vehicle.Offset
		halves[i] = vehicle.Half
	end
	return {
		Vehicles = vehicles,
		Key = key or TrainController.consistKey(color, loads, flip),
		Steam = nil,
		SteamRate = -1,
		LastTip = 0,
		Leg = nil,
		Load = {},
		Count = 0,
		Dirty = true,
		PlacedAt = nil,
		PlacedTip = -1,
		PlacedMask = -1,
		Parked = false,
		Body = TrainController.newBody(offsets, halves),
		Pose = nil,
		Trip = nil,
		Fresh = false,
	}
end

--[[
	Appends every shown part of a consist and its CFrame for pose `p` (one
	BulkMoveTo for all trains). Vehicles inside a tunnel (or, with `shown`,
	the cars occlude hid) are unparented, shown ones go into `parent`.
]]
function TrainController.placeConsist(
	consist: Consist,
	p: Pose,
	parent: Instance?,
	parts: { BasePart },
	cframes: { CFrame },
	shownCars: { boolean }?
)
	local facing = p.Facing
	local ahead = CFrame.lookAt(Vector3.new(), facing)
	local turned = ahead * CFrame.Angles(0, math.pi, 0)
	local tipAngle = p.Tip * TrainController.TipAngle
	for v, vehicle in consist.Vehicles do
		local center = p.Position - facing * vehicle.Offset
		local shown = if shownCars then shownCars[v] == true else TrainController.visible(p, center, vehicle.Half)
		if shown ~= vehicle.Shown then
			vehicle.Shown = shown
			vehicle.Model.Parent = if shown then parent else nil
		end
		if shown then
			local root = (if vehicle.Flip then turned else ahead) + center
			-- rolling forward (its own -Z) turns a wheel by -distance / radius about its axle (X)
			local rolled = if vehicle.Flip then p.Odometer else -p.Odometer
			local tip = if tipAngle > 1e-4 then vehicle.Pivot * CFrame.Angles(0, 0, -tipAngle) * vehicle.Pivot:Inverse() else nil
			for i, part in vehicle.Parts do
				local offset = vehicle.Offsets[i]
				local radius = vehicle.Wheels[i]
				local cf: CFrame
				if radius then
					cf = root * offset * CFrame.Angles(rolled / radius, 0, 0)
				elseif tip and vehicle.Tipping[i] then
					cf = root * tip * offset
				else
					cf = root * offset
				end
				table.insert(parts, part)
				table.insert(cframes, cf)
			end
		end
	end
end

-- Empties a trip's wagons as they pour (never fills them back up). Returns
-- true when a heap moved.
function TrainController.applyPour(consist: Consist, p: Pose): boolean
	local fill = TrainController.pourFill(p)
	if not fill then
		return false
	end
	local changed = false
	for i = 2, #consist.Vehicles do
		local wagon = consist.Vehicles[i]
		if wagon.Loaded and fill < wagon.Fill - 1e-3 then
			TrainController.setFill(wagon, if fill < 1e-3 then 0 else fill, true)
			changed = true
		end
	end
	return changed
end

function TrainController.destroyConsist(consist: Consist)
	for _, vehicle in consist.Vehicles do
		vehicle.Model:Destroy()
	end
	table.clear(consist.Vehicles)
end

---------------------------------------------------------------- runtime state

local player: Player? = nil
local trips: { [number]: Trip } = {}
local built: { [number]: Consist } = {}
local spares: { Consist } = {}
local parked: Consist? = nil
local folder: Folder? = nil
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local bannerCache: { [number]: Color3 } = {}
local bannerTried: { [number]: number } = {} -- os.clock() of the last search for a Banner that wasn't streamed in
local BANNER_RETRY = 2

-- what your waiting train shows, worked out once per snapshot (not every frame)
type ParkedPlan = {
	Snapshot: TrainView.Snapshot,
	PlotId: number,
	Color: Color3,
	Fills: { number },
	Loads: { { Color3 } },
	Key: string,
}
local parkedPlan: ParkedPlan? = nil

local snapshot: TrainView.Snapshot? = nil
local coins = 0
local autoAt: number? = nil -- os.clock() when the train leaves by itself
local refs: TrainView.Refs? = nil
local panelOpen = false
local hudShown = true
local openedAt = -math.huge
local sendLockedUntil = 0
local buyLockedUntil = 0
local pulse: Tween? = nil
local shownKey = ""
local coinsHidden = false -- the compact panel covers the HUD coins: they hide while it is open

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function myId(): number
	local me = player
	return if me then me.UserId else 0
end

local function myPlot(): WorldLayout.Plot?
	local p = player
	local id = p and p:GetAttribute("PlotId")
	return if type(id) == "number" then WorldLayout.Plots[id] else nil
end

-- A plot's banner color (the Banner part when it is streamed in, else PlotBuilder's list;
-- a missing banner is searched for again every BANNER_RETRY seconds at most).
local function bannerColor(plotId: number): Color3
	local cached = bannerCache[plotId]
	if cached then
		return cached
	end
	local fallback = TrainController.BannerColors[(plotId - 1) % #TrainController.BannerColors + 1]
	local clock = os.clock()
	local tried = bannerTried[plotId]
	if tried and clock - tried < BANNER_RETRY then
		return fallback
	end
	bannerTried[plotId] = clock
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. plotId)
	local banner = plot and plot:FindFirstChild("Banner", true)
	if banner and banner:IsA("BasePart") then
		bannerCache[plotId] = banner.Color
		return banner.Color
	end
	return fallback
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function ensureFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ClientTrains"
	made.Parent = Workspace
	folder = made
	return made
end

---------------------------------------------------------------- steam, sounds, pour

local STEAM_MAX = TrainController.MaxBuilt + 1 -- every built trip and your waiting train
local STEAM_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local steamPool: { ParticleEmitter } = {}
local steamMade = 0

local function takeSteam(): ParticleEmitter?
	local reused = table.remove(steamPool)
	if reused then
		return reused
	end
	if steamMade >= STEAM_MAX then
		return nil
	end
	steamMade += 1
	local e = Instance.new("ParticleEmitter")
	e.Name = "Steam"
	e.Texture = STEAM_TEXTURE
	e.Color = ColorSequence.new(Color3.fromRGB(246, 244, 250))
	e.LightInfluence = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.4, 2.4)
	e.Speed = NumberRange.new(3, 5)
	e.SpreadAngle = Vector2.new(8, 8)
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Drag = 1.2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Rate = 2
	return e
end

local function giveSteam(e: ParticleEmitter)
	e.Enabled = false
	e:Clear()
	e.Parent = nil
	table.insert(steamPool, e)
end

-- A train leaves the world: into the spare pool (the oldest spare is destroyed).
local function stash(consist: Consist)
	local steam = consist.Steam
	if steam then
		giveSteam(steam)
		consist.Steam = nil
	end
	for _, vehicle in consist.Vehicles do
		vehicle.Model.Parent = nil
		vehicle.Shown = false
	end
	table.insert(spares, consist)
	while #spares > TrainController.SpareMax do
		TrainController.destroyConsist(table.remove(spares, 1) :: Consist)
	end
end

-- A train for these loads: a matching spare (full again) or a new one.
local function takeConsist(color: Color3, loads: { { Color3 } }, flip: boolean): Consist
	local key = TrainController.consistKey(color, loads, flip)
	for i, spare in spares do
		if spare.Key == key then
			table.remove(spares, i)
			for w = 2, #spare.Vehicles do
				local wagon = spare.Vehicles[w]
				if wagon.Loaded then
					TrainController.setFill(wagon, 1)
				end
			end
			spare.SteamRate = -1
			spare.LastTip = 0
			spare.Leg = nil
			spare.Dirty = true
			spare.PlacedAt = nil
			spare.PlacedTip = -1
			spare.PlacedMask = -1
			spare.Parked = false
			spare.Pose = nil
			spare.Trip = nil
			spare.Fresh = false
			return spare
		end
	end
	return TrainController.buildConsist(color, loads, flip, key)
end

local function dropBuilt(userId: number)
	local consist = built[userId]
	if consist then
		built[userId] = nil
		stash(consist)
	end
end

type Voice = { Part: BasePart, Sound: Sound }

-- A 3D sound of this controller (out of the shared Sfx pool), on an invisible part it moves.
local function newVoice(name: string, range: number): Voice
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = ensureFolder()
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = range
	local group = SoundService:FindFirstChild("TerraForgeSfx")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	sound.Parent = part
	return { Part = part, Sound = sound }
end

local CHUFF_RANGE = 120
local CHUFF_STRIDE = 8.5 / 2 -- studs per chuff: two per turn of the 2.7-stud drive wheels
local WHISTLE_SECONDS = 1.2
-- (soft and short-ranged while SoundConfig's train sounds are the built-in wind stand-in)
local CHUFF_HEARING = 110
local WHISTLE_HEARING = 80
local chuffVoice: Voice? = nil
local whistleVoice: Voice? = nil
local whistleAt = -math.huge

-- The steam sound on the nearest moving locomotive: louder on each chuff, higher when faster.
local function updateChuff(p: Pose?)
	local def = SoundConfig.TrainChuff
	local current = chuffVoice
	if not p or not def then
		if current and current.Sound.IsPlaying then
			current.Sound:Stop()
		end
		return
	end
	local v = current or newVoice("TrainChuff", CHUFF_HEARING)
	chuffVoice = v
	if v.Sound.SoundId ~= def.Id then
		v.Sound.SoundId = def.Id
	end
	v.Sound.Looped = true
	table.insert(moveParts, v.Part)
	table.insert(moveCFrames, CFrame.new(p.Position + Vector3.new(0, 6, 0)))
	local fast = math.clamp(p.Speed / 40, 0, 1)
	v.Sound.PlaybackSpeed = def.Pitch[1] + (def.Pitch[#def.Pitch] - def.Pitch[1]) * fast
	local phase = (math.abs(p.Odometer) / CHUFF_STRIDE) % 1
	local beat = (1 - phase) ^ 3
	v.Sound.Volume = def.Volume * (0.2 + 0.8 * beat) * math.clamp(p.Speed / 6, 0.35, 1)
	if not v.Sound.IsPlaying then
		v.Sound:Play()
	end
end

-- A short double toot at a train (its own sound; faded by updateWhistle).
local function whistle(position: Vector3)
	local def = SoundConfig.TrainWhistle
	if not def or os.clock() - whistleAt < WHISTLE_SECONDS then
		return
	end
	local v = whistleVoice or newVoice("TrainWhistle", WHISTLE_HEARING)
	whistleVoice = v
	v.Sound.SoundId = def.Id
	v.Sound.Looped = def.Looped == true
	v.Sound.PlaybackSpeed = def.Pitch[1] + (def.Pitch[#def.Pitch] - def.Pitch[1]) * math.random()
	v.Sound.Volume = 0
	v.Part.CFrame = CFrame.new(position + Vector3.new(0, 8, 0))
	v.Sound.TimePosition = 0
	v.Sound:Play()
	whistleAt = os.clock()
end

local function updateWhistle()
	local v = whistleVoice
	local def = SoundConfig.TrainWhistle
	if not v or not def or not v.Sound.IsPlaying then
		return
	end
	local t = os.clock() - whistleAt
	if t >= WHISTLE_SECONDS then
		v.Sound:Stop()
		return
	end
	-- toot (0..0.35 s), a breath, toooot (0.5 s..), fading out
	local env = if t < 0.05
		then t / 0.05
		elseif t < 0.35 then 1
		elseif t < 0.5 then math.max(0, 1 - (t - 0.35) / 0.06)
		elseif t < 0.55 then (t - 0.5) / 0.05
		else math.clamp((WHISTLE_SECONDS - t) / 0.4, 0, 1)
	v.Sound.Volume = def.Volume * env
end

type Chunk = {
	Rock: { BasePart }, -- the two blocks of one rock
	From: Vector3,
	To: Vector3,
	Start: number,
	Duration: number,
	Height: number,
	Spin: Vector3,
	Active: boolean,
	Lands: boolean,
}
local CHUNK_MAX = 12
local chunks: { Chunk } = {}
local DUST = Color3.fromRGB(176, 152, 128)

local function rockBlock(): BasePart
	local part = Instance.new("Part")
	part.Name = "OreChunk"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local function freeChunk(): Chunk?
	for _, chunk in chunks do
		if not chunk.Active then
			return chunk
		end
	end
	if #chunks >= CHUNK_MAX then
		return nil
	end
	local chunk: Chunk = {
		Rock = { rockBlock(), rockBlock() },
		From = Vector3.new(),
		To = Vector3.new(),
		Start = 0,
		Duration = 1,
		Height = 6,
		Spin = Vector3.new(),
		Active = false,
		Lands = false,
	}
	table.insert(chunks, chunk)
	return chunk
end

-- The ore leaves the tipped wagons: a dust puff at each, chunks arc into the pen across from it.
local function pour(consist: Consist, p: Pose, plot: WorldLayout.Plot)
	local wagons = #consist.Vehicles - 1
	if wagons < 1 then
		return
	end
	local count = math.clamp(consist.Count, 3, 8)
	local colors = if #consist.Load > 0 then consist.Load else TrainController.DirtyLoad
	local now = os.clock()
	for w = 2, #consist.Vehicles do
		local wagon = consist.Vehicles[w]
		if wagon.Shown then
			local mouth = TrainController.pourMouth(p, wagon.Offset, plot)
			Vfx.burst("Dust", mouth, 10, DUST)
			local per = math.ceil(count / wagons)
			for i = 1, per do
				local chunk = freeChunk()
				if not chunk then
					break
				end
				local size = TrainController.RockSize[1] + math.random() * (TrainController.RockSize[2] - TrainController.RockSize[1])
				local color = TrainController.rockColor(colors[(i + w) % #colors + 1], i + w)
				local sizeA, sizeB = TrainController.rockSizes(size)
				chunk.Rock[1].Size = sizeA
				chunk.Rock[2].Size = sizeB
				for _, block in chunk.Rock do
					block.Color = color
				end
				chunk.From = mouth + p.Facing * ((math.random() - 0.5) * 4)
				chunk.To = TrainController.penSpot(plot, math.random(), math.random(), mouth)
				-- spread over the pour (PourThreshold to the end of the hold)
				chunk.Start = now + (i - 1) * 0.6 / per + (w - 2) * 0.05
				chunk.Duration = 0.75 + math.random() * 0.25
				chunk.Height = TrainController.arcHeight(plot, chunk.From, chunk.To, 5 + math.random() * 3)
				chunk.Spin = Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4)
				chunk.Active = true
				chunk.Lands = i == 1 and w == 2
				local a, b = TrainController.rockPair(CFrame.new(chunk.From))
				chunk.Rock[1].CFrame = a
				chunk.Rock[2].CFrame = b
				-- (shown once it leaves: moveChunks parents it)
			end
		end
	end
	Sfx.play("Drop", p.Position)
end

local function moveChunks(now: number)
	for _, chunk in chunks do
		if chunk.Active then
			local t = (now - chunk.Start) / chunk.Duration
			if t >= 1 then
				chunk.Active = false
				for _, block in chunk.Rock do
					block.Parent = nil
				end
				if chunk.Lands then
					-- the ore is home: dust and glints in the pen
					Vfx.burst("Dust", chunk.To + Vector3.new(0, 0.5, 0), 10, DUST)
					Vfx.burst("Glint", chunk.To + Vector3.new(0, 2, 0), 8, Theme.Coin)
					Sfx.play("Gulp", chunk.To)
				end
			elseif t >= 0 then
				local at = TrainController.arc(chunk.From, chunk.To, chunk.Height, t)
				local spin = chunk.Spin * t
				local a, b = TrainController.rockPair(CFrame.new(at) * CFrame.Angles(spin.X, spin.Y, spin.Z))
				local first, second = chunk.Rock[1], chunk.Rock[2]
				if not first.Parent then
					local parent = ensureFolder()
					first.Parent = parent
					second.Parent = parent
				end
				table.insert(moveParts, first)
				table.insert(moveCFrames, a)
				table.insert(moveParts, second)
				table.insert(moveCFrames, b)
			end
		end
	end
end

---------------------------------------------------------------- trains per frame

local builtCount = 0

-- Before building: does the locomotive or the last wagon show?
local function anyVisible(p: Pose, wagons: number): boolean
	if p.Hidden then
		return false
	end
	local last = TrainController.LocoBack + TrainController.WagonLength * (math.max(wagons, 1) - 0.5)
	return TrainController.visible(p, p.Position, TrainController.LocoFront)
		or TrainController.visible(p, p.Position - p.Facing * last, TrainController.WagonLength / 2)
end

local function updateSteam(consist: Consist, p: Pose)
	local loco = consist.Vehicles[1]
	local smoke = loco and loco.Smoke
	if not smoke then
		return
	end
	local steam = consist.Steam
	if not steam then
		steam = takeSteam()
		if not steam then
			return
		end
		consist.Steam = steam
		steam.Parent = smoke
	end
	local emitter = steam :: ParticleEmitter
	local rate = if p.Speed < 0.5 then 1.2 else math.min(16, 3 + p.Speed * 0.3)
	if math.abs(rate - consist.SteamRate) > 0.5 then
		consist.SteamRate = rate
		emitter.Rate = rate
	end
	if emitter.Enabled ~= loco.Shown then
		emitter.Enabled = loco.Shown
	end
end

-- Which cars of a train show after occlude (a bit per car).
local function shownMask(body: Body): number
	local mask = 0
	for i, shown in body.Shown do
		if shown then
			mask += 2 ^ (i - 1)
		end
	end
	return mask
end

-- Moves a consist to its pose (its cars as occlude left them) unless it already stands like that.
local function place(consist: Consist, p: Pose, force: boolean)
	local mask = shownMask(consist.Body)
	local still = not force
		and not consist.Dirty
		and p.Speed == 0
		and consist.PlacedAt == p.Position
		and consist.PlacedTip == p.Tip
		and consist.PlacedMask == mask
	if still then
		return
	end
	TrainController.placeConsist(consist, p, ensureFolder(), moveParts, moveCFrames, consist.Body.Shown)
	consist.PlacedAt = p.Position
	consist.PlacedTip = p.Tip
	consist.PlacedMask = mask
	consist.Dirty = false
end

-- Builds or drops one trip's train for this frame: the train to show (nil:
-- not on this screen), its pose, and whether it was built just now.
local function prepareTrip(userId: number, trip: Trip, now: number, eye: Vector3, canBuild: boolean): (Consist?, Pose, boolean)
	local plot = WorldLayout.Plots[trip.PlotId]
	local wagons = TrainController.wagonCount(trip.Count)
	local p = TrainController.poseAt(plot, trip.DepartAt, trip.ArriveAt, now, wagons, trip.UnloadAt)
	local consist = built[userId]
	local waiting = parked
	if not consist and waiting and userId == myId() and (p.Leg == "Station" or p.Leg == "Quarry") then
		-- your waiting train is the one that leaves (no pop); it is rebuilt for the trip underground
		parked = nil
		waiting.Leg = "Station"
		waiting.LastTip = 0
		waiting.Dirty = true
		built[userId] = waiting
		builtCount += 1
		consist = waiting
	end
	local cars = if consist then #consist.Vehicles - 1 else wagons
	local distance = (p.Position - eye).Magnitude
	if p.Leg == "Done" or not anyVisible(p, cars) or distance > TrainController.DropRange then
		if consist then
			dropBuilt(userId)
			builtCount -= 1
		end
		return nil, p, false
	end
	if consist then
		return consist, p, false
	end
	if not canBuild or distance > TrainController.BuildRange or builtCount >= TrainController.MaxBuilt then
		return nil, p, false
	end
	local made = takeConsist(trip.Color, TrainController.splitLoad(trip.Load, wagons), TrainController.wagonFlip(plot))
	made.Load = TrainController.displayLoad(trip.Load)
	made.Count = trip.Count
	made.LastTip = p.Tip -- a train built mid-unload doesn't pour again
	made.Leg = p.Leg
	built[userId] = made
	builtCount += 1
	return made, p, true
end

-- Places one trip's train (after occlude): its steam, toots and the pour.
-- Returns its pose while its locomotive shows.
local function finishTrip(trip: Trip, train: Consist, p: Pose, now: number): Pose?
	local plot = WorldLayout.Plots[trip.PlotId]
	local loco = train.Vehicles[1]
	local locoWasShown = loco.Shown
	local poured = if trip.Quiet then false else TrainController.applyPour(train, p)
	place(train, p, poured)
	updateSteam(train, p)
	-- a toot when it sets off, and when it comes out of the south tunnel
	local portal, normal = p.Portal, p.Normal
	local justOut = portal ~= nil and normal ~= nil and (p.Position - portal):Dot(normal) < 16
	if loco.Shown and not locoWasShown and p.Leg == "Coast" and justOut then
		whistle(p.Position)
	elseif p.Leg == "Quarry" and (train.Leg == "Station" or (train.Fresh and now - trip.DepartAt < 1)) then
		whistle(p.Position)
	end
	train.Leg = p.Leg
	if not trip.Quiet and p.Tip >= TrainController.PourThreshold and train.LastTip < TrainController.PourThreshold then
		pour(train, p, plot)
	end
	train.LastTip = p.Tip
	return if loco.Shown then p else nil
end

-- What your waiting train shows for a snapshot (worked out once per snapshot, plot and banner color).
local function planParked(train: TrainView.Snapshot, plot: WorldLayout.Plot, color: Color3): ParkedPlan
	local plan = parkedPlan
	if plan and plan.Snapshot == train and plan.PlotId == plot.Id and plan.Color == color then
		return plan
	end
	local wagons = TrainController.wagonCount(train.Capacity)
	local fills = TrainController.wagonFills(train.Cargo, train.Capacity, wagons)
	local split = TrainController.splitLoad({}, wagons)
	local loads: { { Color3 } } = {}
	for i, fill in fills do
		loads[i] = if fill > 0 then split[i] else {}
	end
	local made: ParkedPlan = {
		Snapshot = train,
		PlotId = plot.Id,
		Color = color,
		Fills = fills,
		Loads = loads,
		Key = TrainController.consistKey(color, loads, false),
	}
	parkedPlan = made
	return made
end

--[[
	Your train at the Mine Station (from the State snapshot) whenever it
	isn't away: on a trip or waiting at a full pen; after an unload it backs
	into the station from rollInAt. When the snapshot says it just left but
	its TrainTrip hasn't come yet, it keeps standing so the trip can take it
	over. Returns the train to show and its pose.
]]
local function prepareParked(now: number, eye: Vector3, canBuild: boolean): (Consist?, Pose?)
	local plot = myPlot()
	local train = snapshot
	local mine = trips[myId()]
	local away = false
	local hold = false
	local rollFrom: number? = nil
	if mine then
		local unloadAt = mine.UnloadAt
		rollFrom = if unloadAt then TrainController.rollInAt(unloadAt) else nil
		away = rollFrom == nil or now < rollFrom
	end
	if train then
		local departAt, arriveAt = train.DepartAt, train.ArriveAt
		if departAt and arriveAt and now >= departAt - 1 then
			if train.Moving > 0 or train.Waiting then
				-- (a trip still rolling home from before is not this one)
				local known = mine ~= nil and math.abs(mine.DepartAt - departAt) < 0.5
				if not known and now < departAt + 3 then
					hold = true
				else
					away = true
				end
			else
				-- unloaded at ArriveAt: it backs into the station from rollInAt
				local from = rollFrom or TrainController.rollInAt(arriveAt)
				rollFrom = from
				if now < from then
					away = true
				end
			end
		end
	end
	local current = parked
	if hold and not away then
		-- (it stands still until its trip takes it over)
		if current and plot then
			return current, TrainController.parkedPose(plot, nil)
		end
		return nil, nil
	end
	if not plot or not train or away then
		if current then
			parked = nil
			stash(current)
		end
		return nil, nil
	end
	local standing = TrainController.parkedPose(plot, if rollFrom then now - rollFrom else nil)
	local distance = (standing.Position - eye).Magnitude
	if distance > TrainController.DropRange then
		if current then
			parked = nil
			stash(current)
		end
		return nil, nil
	end
	local plan = planParked(train, plot, bannerColor(plot.Id))
	if current and current.Key ~= plan.Key then
		parked = nil
		stash(current)
		current = nil
	end
	if not current then
		if not canBuild or distance > TrainController.BuildRange then
			return nil, nil
		end
		local made = takeConsist(plan.Color, plan.Loads, false)
		made.Parked = true
		parked = made
		current = made
	end
	local station = current :: Consist
	for i, fill in plan.Fills do
		local wagon = station.Vehicles[i + 1]
		if wagon and wagon.Loaded and math.abs(wagon.Fill - fill) > 1e-3 then
			TrainController.setFill(wagon, fill)
			station.Dirty = true
		end
	end
	return station, standing
end

-- Places your waiting train (after occlude). Returns its pose while it rolls in.
local function finishParked(station: Consist, standing: Pose): Pose?
	place(station, standing, false)
	updateSteam(station, standing)
	return if standing.Speed > 0 and station.Vehicles[1].Shown then standing else nil
end

local order: { number } = {}
local frame: { Consist } = {} -- the trains shown this frame
local bodies: { Body } = {}

local function step()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = serverNow()
	table.clear(moveParts)
	table.clear(moveCFrames)
	table.clear(frame)
	table.clear(bodies)
	local canBuild = true -- at most one new train per frame (no hitches)
	local mineId = myId()
	-- your own trip first: it takes over your waiting train
	order[1] = mineId
	local n = 1
	for userId in trips do
		if userId ~= mineId then
			n += 1
			order[n] = userId
		end
	end
	for i = 1, n do
		local userId = order[i]
		order[i] = nil
		local trip = trips[userId]
		if not trip then
			continue
		end
		if not trip.UnloadAt and not trip.Waiting and userId ~= mineId and now > trip.ArriveAt + TrainController.HoldLimit then
			-- its unload never came (and the server never said its pen is full): it leaves without tipping
			trip.UnloadAt = now - TrainController.unloadSeconds()
			trip.Quiet = true
		end
		local unloadAt = trip.UnloadAt
		local plot = WorldLayout.Plots[trip.PlotId]
		if unloadAt and now > unloadAt + TrainController.returnSeconds(plot, TrainController.wagonCount(trip.Count)) + 1 then
			trips[userId] = nil
			if built[userId] then
				dropBuilt(userId)
				builtCount -= 1
			end
		else
			local consist, p, didBuild = prepareTrip(userId, trip, now, eye, canBuild)
			if didBuild then
				canBuild = false
			end
			if consist then
				consist.Pose = p
				consist.Trip = trip
				consist.Fresh = didBuild
				TrainController.fillBody(consist.Body, p, TrainController.tierOf(p, userId == mineId), trip.DepartAt, userId)
				table.insert(frame, consist)
				table.insert(bodies, consist.Body)
			end
		end
	end
	for userId in built do
		if not trips[userId] then
			dropBuilt(userId)
			builtCount -= 1
		end
	end
	local station, standing = prepareParked(now, eye, canBuild)
	if station and standing then
		station.Pose = standing
		station.Trip = nil
		station.Fresh = false
		TrainController.fillBody(station.Body, standing, 0, -math.huge, mineId)
		table.insert(frame, station)
		table.insert(bodies, station.Body)
	end
	-- one track per line: lower ranked trains hide where they would run through a higher ranked one
	TrainController.occlude(bodies)
	local chuffPose: Pose? = nil
	local chuffDistance = CHUFF_RANGE
	for _, consist in frame do
		local p = consist.Pose :: Pose
		local trip = consist.Trip
		local shown = if trip then finishTrip(trip, consist, p, now) else finishParked(consist, p)
		-- the steam sound follows the nearest moving locomotive (your train backing in too)
		if shown and shown.Speed > 1 then
			local d = (shown.Position - eye).Magnitude
			if d < chuffDistance then
				chuffDistance = d
				chuffPose = shown
			end
		end
	end
	moveChunks(os.clock())
	updateChuff(chuffPose)
	updateWhistle()
	if #moveParts > 0 then
		-- (FireCFrameChanged is the cheapest mode Roblox has: nothing listens to these parts)
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------- HUD chip and panel

local function status(): TrainView.Status?
	local train = snapshot
	if not train then
		return nil
	end
	local autoLeft = if autoAt then math.max(0, autoAt - os.clock()) else nil
	local result = TrainView.status(train, serverNow(), autoLeft)
	if os.clock() < sendLockedUntil then
		result.CanSend = false
	end
	return result
end

local function setPulse(view: TrainView.Refs, on: boolean)
	local holder = view.ChipSend.Parent :: Frame
	local scale = holder:FindFirstChild("Pulse") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "Pulse"
		made.Parent = holder
		scale = made
	end
	local current = pulse
	if on and not current then
		local tween = TweenService:Create(
			scale :: UIScale,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.08 }
		)
		tween:Play()
		pulse = tween
	elseif not on and current then
		current:Cancel()
		pulse = nil
		local still = scale :: UIScale
		still.Scale = 1
	end
end

-- The chip shows with the HUD, but not behind the open panel (the panel says the same); the HUD
-- coins hide while the compact panel covers them (its header shows your coins).
local function applyChip()
	local view = refs
	if not view then
		return
	end
	view.Chip.Enabled = TrainView.chipVisible(hudShown, panelOpen)
	local hide = panelOpen and view.CoversCoins
	local hud = HudController.refs()
	if hud and hide ~= coinsHidden then
		coinsHidden = hide
		hud.CoinsPanel.Visible = not hide
	end
end

local function refreshUI(force: boolean?)
	local view = refs
	if not view then
		return
	end
	local current = status()
	view.ChipFrame.Visible = current ~= nil
	if not current then
		return
	end
	local key = `{current.Title}|{current.Line}|{current.CanSend}|{current.Fill}|{current.Progress or -1}|{current.Unit}`
	if key ~= shownKey or force then
		shownKey = key
		TrainView.setStatus(view, current)
		setPulse(view, current.Phase == "Full")
	end
	if panelOpen then
		-- the header's coins count along with the HUD's
		TrainView.setCoins(view, HudController.predictedCoins(os.clock()))
	end
end

local function refreshPanel()
	local view = refs
	local train = snapshot
	if view and train and panelOpen then
		TrainView.setUpgrades(view, train, coins)
	end
end

local function hintText(): string
	if usingGamepad() then
		return "L3: open / close   •   B: close"
	elseif isTouch() then
		return "Tap X to close"
	end
	return "T: open / close   •   Backspace: close"
end

local function updateHints()
	local view = refs
	if not view then
		return
	end
	local gamepad = usingGamepad()
	view.ChipKey.Visible = not gamepad and not isTouch() and not view.Compact
	view.ChipGlyph.Visible = gamepad
	if gamepad then
		view.ChipGlyph.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonL3)
	end
	view.Hint.Text = hintText()
end

-- Fits the chip and the panel to the screen (phones get the compact layout).
local function fit()
	local view = refs
	if not view then
		return
	end
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = isTouch() or scale <= 0.75 or size.Y < 520
	TrainView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
	updateHints()
	applyChip()
end

local function deny(text: string)
	HudController.toast(text, "Deny")
end

local function send()
	local current = status()
	if not current or os.clock() < sendLockedUntil then
		return
	end
	if not current.CanSend then
		if current.Phase == "Moving" or current.Phase == "Unloading" then
			deny("Your train is on its way. It comes back after the delivery.")
		elseif current.Phase == "PenFull" then
			deny("Your Ore Pen is full: make room so your train can unload.")
		elseif current.Phase == "Returning" then
			deny("Your train is on its way back to the Mine.")
		else
			deny("Your train is empty: throw ore into the Mine Station hopper!")
		end
		return
	end
	sendLockedUntil = os.clock() + 1.5
	Sfx.play("UIClick")
	Net.send("TrainAction", "Send")
	refreshUI(true)
end

local function buy(kind: TrainView.Kind)
	local train = snapshot
	if not train or os.clock() < buyLockedUntil then
		return
	end
	local info = TrainView.upgrade(train, kind, coins)
	if info.Maxed then
		HudController.toast(`Your train's {string.lower(info.Name)} is at the top level.`, "Info")
		return
	end
	if not info.CanBuy then
		deny(`You need {info.PriceText} for this upgrade.`)
		return
	end
	buyLockedUntil = os.clock() + 0.6
	Sfx.play("UIClick")
	Net.send("TrainAction", "Upgrade", { Kind = kind })
end

local CLOSE_ACTION = "TerraForgeTrainClose"
local TOGGLE_ACTION = "TerraForgeTrainToggle"
-- above the default controls, so B / Backspace close the panel first
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10

local function selectDefault(view: TrainView.Refs)
	if not usingGamepad() then
		return
	end
	local train = snapshot
	local current = status()
	if current and current.CanSend then
		GuiService.SelectedObject = view.Send
		return
	end
	if train then
		if TrainView.upgrade(train, "Capacity", coins).CanBuy then
			GuiService.SelectedObject = view.Rows.Capacity.Buy
			return
		elseif TrainView.upgrade(train, "Speed", coins).CanBuy then
			GuiService.SelectedObject = view.Rows.Speed.Buy
			return
		end
	end
	GuiService.SelectedObject = view.Close
end

function TrainController.isOpen(): boolean
	return panelOpen
end

function TrainController.close()
	local view = refs
	if not panelOpen or not view then
		return
	end
	panelOpen = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) then
		GuiService.SelectedObject = nil
	end
	view.Gui.Enabled = false
	applyChip()
	PromptController.setSuppressed("Train", false)
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not panelOpen then
		return Enum.ContextActionResult.Pass
	end
	TrainController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

function TrainController.open()
	local view = refs
	-- not while the HUD is hidden (the cleaning close-up) or something owns the
	-- screen (build mode, the anvil)
	if not view or not snapshot or not hudShown then
		return
	end
	local owner = PlayerControls.owner()
	if owner ~= nil then
		HudController.toast(if owner == "Build" then "Finish building first." else "Finish what you are doing first.", "Info")
		return
	end
	if panelOpen then
		refreshPanel()
		return
	end
	-- one panel at a time: the Pen and Sell panels close (they bind B / Backspace too)
	if PenController.isOpen() then
		PenController.close()
	end
	if SellController.isOpen() then
		SellController.close()
	end
	panelOpen = true
	openedAt = os.clock()
	fit()
	refreshUI(true)
	refreshPanel()
	view.Gui.Enabled = true
	applyChip()
	PromptController.setSuppressed("Train", true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	GuiService.SelectedObject = nil
	selectDefault(view)
	Sfx.play("UIClick")
	local pop = view.Panel:FindFirstChild("OpenPop") :: UIScale?
	if not pop then
		local made = Instance.new("UIScale")
		made.Name = "OpenPop"
		made.Parent = view.Panel
		pop = made
	end
	local scale = pop :: UIScale
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- T / L3 / the chip: open or close (a press right after opening never closes it,
-- so the station prompt and the key binding can't cancel each other out).
local function toggle()
	if panelOpen then
		if os.clock() - openedAt > 0.3 then
			TrainController.close()
			Sfx.play("UIClick")
		end
	else
		TrainController.open()
	end
end

---------------------------------------------------------------- state, trips, effects

local function addTrip(trip: Trip)
	local existing = trips[trip.UserId]
	local merged, rebuild = TrainController.mergeTrip(existing, trip, serverNow())
	local consist = built[trip.UserId]
	-- (your waiting train that took the trip over is rebuilt underground anyway)
	if existing and rebuild and consist and not consist.Parked then
		dropBuilt(trip.UserId)
		builtCount -= 1
	end
	trips[trip.UserId] = merged
end

local function onTrip(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.UserId ~= nil then
		local trip = TrainController.parseTrip(payload, bannerColor)
		if trip then
			addTrip(trip)
		end
		return
	end
	for _, entry in payload do
		local trip = TrainController.parseTrip(entry, bannerColor)
		if trip then
			addTrip(trip)
		end
	end
end

-- Your trip against the State snapshot: waiting at a full pen, unloaded, or
-- missing (no TrainTrip event came for it: added after 2 s of grace, the event
-- with the load colors normally comes with the snapshot).
local function syncSnapshotTrip()
	local train = snapshot
	local me = player
	local plot = myPlot()
	if not train or not me or not plot then
		return
	end
	local now = serverNow()
	local known = trips[me.UserId]
	if known then
		local news = TrainController.snapshotNews(known, train, now)
		if news == "Waiting" then
			known.Waiting = true
		elseif news == "Unloaded" then
			known.UnloadAt = math.max(now, known.ArriveAt)
			known.Waiting = false
		elseif news == "Gone" then
			trips[me.UserId] = nil
			if built[me.UserId] then
				dropBuilt(me.UserId)
				builtCount -= 1
			end
		end
		local departAt = train.DepartAt
		local newer = departAt ~= nil and known.UnloadAt ~= nil and departAt > known.DepartAt + 0.5
		if not newer then
			return
		end
	end
	local departAt, arriveAt = train.DepartAt, train.ArriveAt
	if not departAt or not arriveAt or arriveAt <= departAt or now <= departAt + 2 then
		return
	end
	local trip: Trip = {
		UserId = me.UserId,
		PlotId = plot.Id,
		DepartAt = departAt,
		ArriveAt = arriveAt,
		Count = math.max(1, train.Moving),
		Color = bannerColor(plot.Id),
		Load = {},
		Waiting = train.Waiting,
	}
	if train.Moving == 0 then
		-- already unloaded (ArriveAt is when): only the way back is left
		if now >= arriveAt + TrainController.returnSeconds(plot, TrainController.wagonCount(trip.Count)) then
			return
		end
		trip.UnloadAt = arriveAt
	end
	addTrip(trip)
end

local function onState(state: { [string]: any })
	local raw = state.Train
	coins = tonumber(state.Coins) or coins
	if type(raw) ~= "table" then
		return
	end
	local train = TrainView.read(raw)
	snapshot = train
	autoAt = if train.AutoDepartIn then os.clock() + train.AutoDepartIn else nil
	local plot = myPlot()
	syncSnapshotTrip()
	sendLockedUntil = 0
	local view = refs
	if view and plot then
		TrainView.setColor(view, bannerColor(plot.Id))
	end
	refreshUI(true)
	refreshPanel()
end

-- The server unloaded a plot's train: its hoppers tip now (or, when it isn't
-- on screen, dust and glints in that pen).
local function onUnload(plotId: any, count: any)
	local plot = if type(plotId) == "number" then WorldLayout.Plots[plotId] else nil
	local camera = Workspace.CurrentCamera
	if not plot or not camera then
		return
	end
	local now = serverNow()
	local shown = false
	for userId, trip in trips do
		if trip.PlotId == plot.Id and not trip.UnloadAt and now >= trip.ArriveAt - 3 then
			trip.UnloadAt = math.max(now, trip.ArriveAt)
			trip.Waiting = false
			local consist = built[userId]
			shown = shown or (consist ~= nil and consist.Vehicles[1].Shown)
		end
	end
	if shown then
		return -- the chunks bring the dust and glints when they land
	end
	local pen = TrainController.penCenter(plot)
	if (pen - camera.CFrame.Position).Magnitude > TrainController.BuildRange then
		return
	end
	local n = if finite(count) then math.clamp(math.floor(count), 1, 40) else 6
	Vfx.burst("Dust", pen + Vector3.new(0, 1, 0), math.clamp(6 + n, 8, 20), DUST)
	Vfx.burst("Glint", pen + Vector3.new(0, 2, 0), math.clamp(n, 4, 12), Theme.Coin)
	Sfx.play("Drop", pen)
end

local function onLoad(position: any)
	if typeof(position) ~= "Vector3" or not finite(position.X) or not finite(position.Y) or not finite(position.Z) then
		return
	end
	Vfx.burst("Dust", position + Vector3.new(0, 1, 0), 6, DUST)
	Vfx.burst("Glint", position + Vector3.new(0, 2, 0), 5, Theme.Accent)
	Sfx.play("Gulp", position)
	-- at the station: a puff over your waiting wagon under the chute
	local standing = parked
	local wagon = standing and standing.Vehicles[2]
	if wagon and wagon.Shown and (position - TrainConfig.Station.Hopper).Magnitude < 12 then
		Vfx.burst("Dust", TrainConfig.QuarryStop + Vector3.new(0, 5, 0), 5, DUST)
	end
end

---------------------------------------------------------------- prompts

local PANEL_PROMPT = "TrainPanelPrompt"

-- The "Train" panel prompt on a station's / lift's PromptPoint (slot 2, under the server's Load and Send).
local function addPrompt(root: Instance, objectText: string)
	local function attach(point: Instance)
		if not point:IsA("Attachment") or point.Name ~= "PromptPoint" or point:FindFirstChild(PANEL_PROMPT) then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PANEL_PROMPT
		prompt.ActionText = "Train"
		prompt.ObjectText = objectText
		prompt.KeyboardKeyCode = Enum.KeyCode.T
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonL3
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = TrainController.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.UIOffset = Vector2.new(0, TrainController.PromptSlot * TrainController.PromptSlotHeight)
		prompt.Parent = point
		prompt.Triggered:Connect(function()
			TrainController.open()
		end)
	end
	for _, d in root:GetDescendants() do
		attach(d)
	end
	-- streaming: the attachment may arrive after the model
	root.DescendantAdded:Connect(attach)
end

local function carrying(): boolean
	local me = player
	local count = me and me:GetAttribute("CarryCount")
	return type(count) == "number" and count > 0
end

-- The server's "Load Train" prompt (tag TrainPrompt, Action "Load") shows while you carry something.
local function showLoadPrompt(instance: Instance, on: boolean)
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("Action") == "Load" then
		instance.Enabled = on
	end
end

local function trackLoadPrompt(instance: Instance)
	showLoadPrompt(instance, carrying())
end

-- (looked up by tag each time: no table of prompts that could miss one or keep a destroyed one)
local function refreshLoadPrompts()
	local on = carrying()
	for _, prompt in CollectionService:GetTagged("TrainPrompt") do
		showLoadPrompt(prompt, on)
	end
end

---------------------------------------------------------------- lifecycle

function TrainController.init()
	FxController = require(script.Parent.FxController)
	HudController = require(script.Parent.HudController)
	PenController = require(script.Parent.PenController)
	PromptController = require(script.Parent.PromptController)
	SellController = require(script.Parent.SellController)
	StateController = require(script.Parent.StateController)
	PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
	local me = Players.LocalPlayer
	player = me

	local view = TrainView.build(false)
	local playerGui = me:WaitForChild("PlayerGui")
	view.Chip.Parent = playerGui
	view.Gui.Parent = playerGui
	view.ChipFrame.Visible = false
	view.ChipOpen.Activated:Connect(toggle)
	view.ChipSend.Activated:Connect(send)
	view.Send.Activated:Connect(send)
	view.Close.Activated:Connect(function()
		TrainController.close()
		Sfx.play("UIClick")
	end)
	view.Rows.Capacity.Buy.Activated:Connect(function()
		buy("Capacity")
	end)
	view.Rows.Speed.Buy.Activated:Connect(function()
		buy("Speed")
	end)
	view.Express.Buy.Activated:Connect(function()
		local train = snapshot
		if train and train.Express then
			HudController.toast("Your Express Train is running: 2x speed, +50% cargo!", "Reward")
		else
			HudController.toast(`The Express Train ({TrainView.ExpressPrice} R$) is coming soon!`, "Info")
		end
	end)
	refs = view

	Net.listen("TrainTrip", onTrip)
	FxController.register("TrainUnload", onUnload)
	FxController.register("TrainLoad", onLoad)
	StateController.onChanged(onState)
	Players.PlayerRemoving:Connect(function(leaving)
		trips[leaving.UserId] = nil
	end)
end

function TrainController.start()
	local view = refs
	if not view then
		return
	end
	-- the chip hides with the HUD (cleaning close-up), and the panel closes
	local hud = HudController.refs()
	if hud then
		local function mirror()
			hudShown = hud.Gui.Enabled
			applyChip()
			if not hudShown then
				TrainController.close()
			end
		end
		hud.Gui:GetPropertyChangedSignal("Enabled"):Connect(mirror)
		mirror()
	end
	fit()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	UserInputService.LastInputTypeChanged:Connect(function()
		updateHints()
		if panelOpen and usingGamepad() and GuiService.SelectedObject == nil then
			selectDefault(view)
		end
	end)
	ContextActionService:BindAction(TOGGLE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			toggle()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.T, Enum.KeyCode.ButtonL3)

	-- the panel prompt on the station and the lifts; the server's Load prompts only with full hands
	CollectionService:GetInstanceAddedSignal("TrainStation"):Connect(function(station)
		addPrompt(station, "Mine Station")
	end)
	for _, station in CollectionService:GetTagged("TrainStation") do
		addPrompt(station, "Mine Station")
	end
	CollectionService:GetInstanceAddedSignal("MineLift"):Connect(function(lift)
		addPrompt(lift, "Mine Lift")
	end)
	for _, lift in CollectionService:GetTagged("MineLift") do
		addPrompt(lift, "Mine Lift")
	end
	CollectionService:GetInstanceAddedSignal("TrainPrompt"):Connect(trackLoadPrompt)
	for _, prompt in CollectionService:GetTagged("TrainPrompt") do
		trackLoadPrompt(prompt)
	end
	local me = player
	if me then
		-- (an item's CarriedBy may arrive a moment after CarryCount: refresh twice, like PromptController)
		me:GetAttributeChangedSignal("CarryCount"):Connect(function()
			refreshLoadPrompts()
			task.delay(0.25, refreshLoadPrompts)
		end)
		me:GetAttributeChangedSignal("PlotId"):Connect(function()
			local plot = myPlot()
			if plot then
				TrainView.setColor(view, bannerColor(plot.Id))
			end
		end)
	end

	-- one loop: every train, your waiting train, the flying ore, the sounds; the chip text 4x a second
	local uiClock = 0
	RunService.PreRender:Connect(function(dt)
		step()
		uiClock += dt
		if uiClock >= 0.25 then
			uiClock = 0
			refreshUI()
			syncSnapshotTrip()
		end
	end)
end

return TrainController
