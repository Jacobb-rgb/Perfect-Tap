--[[
	TrainController: everyone's ore trains on this screen, your train's HUD
	chip and the Mine Station panel (design v2, docs/plans/STEP2_PLAN.md).

	Trains (client visuals only; the server keeps nothing but times):
	- "TrainTrip" { UserId, PlotId, DepartAt, ArriveAt, Count, Color, Load }
	  (a list of them for a joining player) starts a trip. Every trip is
	  animated from server time (workspace:GetServerTimeNow()) along
	  TrainConfig.Timeline: the quarry leg from TrainConfig.QuarryStop into the
	  quarry wall portal on the plot's side (west plots x < 0: west portal),
	  speeding up; hidden underground; the coast leg out of the south portal
	  north along TrainConfig.lineFor(plot) to TrainConfig.stopFor(plot)
	  (ease in / out); the unload: the wagons' "Hopper" tips about "TipPivot"
	  toward the Ore Pen, a dust puff and ore chunks fly into the pen; then it
	  rolls back south into the tunnel over TrainConfig.ReturnSeconds.
	- A train is a TrainBuilder.locomotive in the trip's color and 1-2
	  TrainBuilder.wagons with the load colors (anchored, no collisions or
	  queries). Only trains within BuildRange studs of the camera are built
	  (and rebuilt when they come back into range); vehicles behind a tunnel
	  mouth are hidden. One RenderStepped loop moves every part with one
	  BulkMoveTo: wheels spin with the distance, steam puffs from the "Smoke"
	  attachment (pooled emitters, more when faster), a soft chuff on the
	  nearest moving train and a whistle when a train sets off or comes out of
	  the south tunnel.
	- Your own train waits at the Mine Station (locomotive Root on
	  QuarryStop, facing your quarry portal) whenever it isn't on a trip; its
	  ore heap grows with Cargo / Capacity from the State snapshot. After a
	  trip it backs out of the quarry portal into the station.

	HUD and panel (TrainView):
	- The chip under the coins: "TRAIN 6/8", the state and SEND (TrainAction
	  "Send"). Click / tap the chip, press T or gamepad L3, or use the
	  station's "Train" prompt to open the panel: cargo, trip time, SEND,
	  Capacity / Speed upgrades with BUY (TrainAction "Upgrade" { Kind }) and
	  the Express perk placeholder. X, B or Backspace (or T / L3 again) close
	  it; gamepads get a selected button. The chip hides with the HUD.
	- Fx "TrainUnload" (plotId, count): dust and glints in that plot's pen;
	  "TrainLoad" (position): a puff and a gulp at a hopper.

	The pure math (ease, legAt, poseAt, parkedPose, quarryPortal, wagonFlip,
	visible, ...) and the consist builder are exported for the Lune tests and
	the preview; the controllers it uses are required in init(), so this
	module also loads outside Roblox.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local TrainConfig = require(Shared.Config.TrainConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Theme = require(Shared.Config.UITheme)
local TrainBuilder = require(Shared.Builders.TrainBuilder)
local Net = require(Shared.Net)
local TrainView = require(script.Parent.Parent.UI.TrainView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)

-- required in init(): they touch Players.LocalPlayer when loaded
type FxControllerModule = typeof(require(script.Parent.FxController))
type HudControllerModule = typeof(require(script.Parent.HudController))
type PromptControllerModule = typeof(require(script.Parent.PromptController))
type StateControllerModule = typeof(require(script.Parent.StateController))
local FxController: FxControllerModule
local HudController: HudControllerModule
local PromptController: PromptControllerModule
local StateController: StateControllerModule

local TrainController = {}

TrainController.BuildRange = 300 -- trains closer than this to the camera are built and animated
TrainController.DropRange = 340 -- ...and dropped again past this
TrainController.HideDepth = 44 -- studs a train runs on inside a tunnel (a locomotive + 2 wagons fit)
TrainController.TipAngle = math.rad(52) -- the hopper at full tip
TrainController.TipShare = 0.6 -- share of the unload leg spent tipping up
TrainController.UnloadHold = 1.2 -- seconds at the stop after arrival (the hopper tips back)
TrainController.RollInSeconds = 3 -- your train backing into the station after a trip
TrainController.WagonSlots = 12 -- cargo one wagon shows; more makes a second wagon
TrainController.MaxBuilt = 6 -- trains built at once (each is ~100 parts)
TrainController.HeapDrop = 1.3 -- how far the ore heap sinks in an almost empty wagon
TrainController.PourThreshold = 0.7 -- tip share at which the ore leaves the wagon
-- your waiting train's load: Dirty Ore colors (the ores stay secret until cleaned)
TrainController.DirtyLoad = { Color3.fromRGB(132, 116, 100), Color3.fromRGB(104, 96, 90), Color3.fromRGB(152, 130, 106) }
-- PlotBuilder's banner colors, for when your plot's Banner part isn't streamed in
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

export type Leg = "Waiting" | "Quarry" | "Underground" | "Coast" | "Unload" | "Return" | "Done" | "Parked"
export type EaseKind = "In" | "Out" | "InOut"

export type Pose = {
	Leg: Leg,
	Position: Vector3, -- the locomotive's Root (on the rails)
	Facing: Vector3, -- where the locomotive's front points (unit, level)
	Odometer: number, -- distance travelled along Facing (wheel spin)
	Speed: number, -- studs per second
	Tip: number, -- hopper tip, 0..1
	Hidden: boolean, -- underground or gone
	Portal: Vector3?, -- the tunnel mouth on this leg (on the rails)
	Normal: Vector3?, -- from that mouth toward the open side
}

export type Trip = {
	UserId: number,
	PlotId: number,
	DepartAt: number,
	ArriveAt: number,
	Count: number,
	Color: Color3,
	Load: { Color3 },
}

export type Vehicle = {
	Model: Model,
	Parts: { BasePart },
	Base: { CFrame }, -- model-space CFrames as built
	Offsets: { CFrame }, -- model-space CFrames now (the heap sinks with the cargo)
	Wheels: { [number]: number }, -- part index -> rolling radius
	Tipping: { [number]: boolean }, -- part index -> tips with the Hopper
	Heap: { [number]: number }, -- part index -> how far it sinks when almost empty
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
	Key: string, -- what it was built from (rebuild when it changes)
	Steam: ParticleEmitter?,
	SteamRate: number,
	LastTip: number,
	Leg: Leg?,
	Load: { Color3 },
	Count: number,
	Dirty: boolean, -- needs placing even when standing still
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

local LEGS: { { Name: Leg, Span: { number } } } = {
	{ Name = "Quarry", Span = TrainConfig.Timeline.QuarryLeg },
	{ Name = "Underground", Span = TrainConfig.Timeline.Underground },
	{ Name = "Coast", Span = TrainConfig.Timeline.CoastLeg },
	{ Name = "Unload", Span = TrainConfig.Timeline.Unload },
}

-- The leg at a share of the trip (0..1), the fraction inside it and the leg's share.
function TrainController.legAt(share: number): (Leg, number, number)
	if share < LEGS[1].Span[1] then
		return "Waiting", 0, 0
	end
	for _, leg in LEGS do
		local a, b = leg.Span[1], leg.Span[2]
		if share < b then
			return leg.Name, (share - a) / math.max(b - a, 1e-6), b - a
		end
	end
	local last = LEGS[#LEGS].Span
	return "Unload", 1, last[2] - last[1]
end

-- The quarry wall portal on a plot's side (west plots x < 0: the west portal).
function TrainController.quarryPortal(plot: WorldLayout.Plot): Vector3
	local best = TrainConfig.QuarryLine[1]
	for _, point in TrainConfig.QuarryLine do
		if (plot.Center.X < 0 and point.X < best.X) or (plot.Center.X >= 0 and point.X > best.X) then
			best = point
		end
	end
	return best
end

-- The south tunnel mouth, the plot's stop and the direction north along the line.
function TrainController.coast(plot: WorldLayout.Plot): (Vector3, Vector3, Vector3)
	local line = TrainConfig.lineFor(plot)
	local mouth = line[1]
	local stop = TrainConfig.stopFor(plot)
	return mouth, stop, level(stop - mouth).Unit
end

function TrainController.penCenter(plot: WorldLayout.Plot): Vector3
	return (WorldLayout.plotCFrame(plot) * CFrame.new(BaseLayout.Pen.Area.Center)).Position
end

-- Wagons tip to their +X side; turn them around when the pen lies on the other side.
function TrainController.wagonFlip(plot: WorldLayout.Plot): boolean
	local _, stop, north = TrainController.coast(plot)
	local right = north:Cross(UP)
	return (TrainController.penCenter(plot) - stop):Dot(right) < 0
end

function TrainController.wagonCount(count: number): number
	return math.clamp(math.ceil(count / TrainController.WagonSlots), 1, 2)
end

-- Load colors shared out over the wagons (up to 3 each; Dirty Ore colors when empty).
function TrainController.splitLoad(load: { Color3 }, wagons: number): { { Color3 } }
	local source = if #load > 0 then load else TrainController.DirtyLoad
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
		Hidden = hidden,
		Portal = portal,
		Normal = normal,
	}
end

-- After arrival: hold at the stop while the hopper tips back, then back south into the tunnel.
local function returnPose(plot: WorldLayout.Plot, since: number): Pose
	local mouth, stop, north = TrainController.coast(plot)
	local total = TrainConfig.ReturnSeconds
	local r = math.max(since, 0)
	local inside = mouth - north * TrainController.HideDepth
	if r >= total then
		return pose("Done", inside + RAIL, north, 0, 0, 0, true, mouth + RAIL, north)
	end
	local hold = math.min(TrainController.UnloadHold, total * 0.4)
	if r < hold then
		local down = (r - hold * 0.35) / (hold * 0.65)
		local tip = if down <= 0 then 1 else 1 - (TrainController.ease("InOut", down))
		return pose("Unload", stop + RAIL, north, 0, 0, tip, false, mouth + RAIL, north)
	end
	local length = (stop - inside).Magnitude
	local e, slope = TrainController.ease("InOut", (r - hold) / (total - hold))
	local s = length * e
	return pose("Return", stop - north * s + RAIL, north, -s, length * slope / (total - hold), 0, false, mouth + RAIL, north)
end

--[[
	Where a plot's train is at `now` (server time) on a trip from departAt to
	arriveAt: the locomotive's Root on the rails, where it faces, how far it
	has rolled, its speed and the hopper's tip.
]]
function TrainController.poseAt(plot: WorldLayout.Plot, departAt: number, arriveAt: number, now: number): Pose
	local duration = arriveAt - departAt
	if now >= arriveAt or duration <= 0 then
		return returnPose(plot, now - arriveAt)
	end
	local leg, f, span = TrainController.legAt((now - departAt) / duration)
	local legSeconds = math.max(duration * span, 1e-3)
	if leg == "Waiting" or leg == "Quarry" or leg == "Underground" then
		local stop = TrainConfig.QuarryStop
		local portal = TrainController.quarryPortal(plot)
		local dir = level(portal - stop).Unit
		local length = (portal - stop).Magnitude + TrainController.HideDepth
		if leg == "Underground" then
			return pose("Underground", stop + dir * length + RAIL, dir, length, 0, 0, true, portal + RAIL, -dir)
		end
		local e, slope = TrainController.ease("In", f)
		local s = length * e
		local speed = if leg == "Waiting" then 0 else length * slope / legSeconds
		return pose(leg, stop + dir * s + RAIL, dir, s, speed, 0, false, portal + RAIL, -dir)
	end
	local mouth, stop, north = TrainController.coast(plot)
	if leg == "Coast" then
		local start = mouth - north * TrainController.HideDepth
		local length = (stop - start).Magnitude
		local e, slope = TrainController.ease("InOut", f)
		local s = length * e
		return pose("Coast", start + north * s + RAIL, north, s - length, length * slope / legSeconds, 0, false, mouth + RAIL, north)
	end
	local tip = TrainController.ease("Out", f / TrainController.TipShare)
	return pose("Unload", stop + RAIL, north, 0, 0, tip, false, mouth + RAIL, north)
end

--[[
	Your train at the Mine Station: the locomotive's Root on QuarryStop,
	facing your quarry portal. `sinceEnd` = seconds since your last trip
	ended: for RollInSeconds it backs out of that portal into the station.
]]
function TrainController.parkedPose(plot: WorldLayout.Plot, sinceEnd: number?): Pose
	local stop = TrainConfig.QuarryStop
	local portal = TrainController.quarryPortal(plot)
	local dir = level(portal - stop).Unit
	local away, speed = 0, 0
	if sinceEnd and sinceEnd >= 0 and sinceEnd < TrainController.RollInSeconds then
		local length = (portal - stop).Magnitude + TrainController.HideDepth
		local e, slope = TrainController.ease("Out", sinceEnd / TrainController.RollInSeconds)
		away = length * (1 - e)
		speed = length * slope / TrainController.RollInSeconds
	end
	return pose("Parked", stop + dir * away + RAIL, dir, away, speed, 0, false, portal + RAIL, -dir)
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

-- How full the wagons of a trip look at a pose: the heap slides out while the
-- hopper tips past PourThreshold and stays out on the way back (nil = as built).
function TrainController.pourFill(p: Pose): number?
	if p.Leg == "Return" or p.Leg == "Done" then
		return 0
	elseif p.Tip >= TrainController.PourThreshold then
		return math.clamp(1 - (p.Tip - TrainController.PourThreshold) / (1 - TrainController.PourThreshold), 0, 1)
	end
	return nil
end

-- Where the ore leaves a tipped wagon `offset` studs behind the locomotive:
-- over the hopper's lip on the pen side.
function TrainController.pourMouth(p: Pose, offset: number, plot: WorldLayout.Plot): Vector3
	local toward = level(TrainController.penCenter(plot) - p.Position).Unit
	return p.Position - p.Facing * offset + toward * 3 + Vector3.new(0, 5, 0)
end

-- A flying ore chunk at t (0..1) of its arc from `from` to `to`, `height` studs over the line.
function TrainController.arc(from: Vector3, to: Vector3, height: number, t: number): Vector3
	local f = math.clamp(t, 0, 1)
	return from:Lerp(to, f) + Vector3.new(0, 4 * height * f * (1 - f), 0)
end

-- A landing spot in a plot's Ore Pen for roll1, roll2 in 0..1 (3 studs inside the fence).
function TrainController.penSpot(plot: WorldLayout.Plot, roll1: number, roll2: number): Vector3
	local area = BaseLayout.Pen.Area
	local inside = area.Center + Vector3.new((roll1 - 0.5) * (area.Size.X - 6), 0.6, (roll2 - 0.5) * (area.Size.Z - 6))
	return (WorldLayout.plotCFrame(plot) * CFrame.new(inside)).Position
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
	}
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
					vehicle.Loaded = true
				elseif d.Name == "OreBed" then
					vehicle.Heap[i] = TrainController.HeapDrop
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

-- Sinks a wagon's ore heap for a fill of 0..1 (1 = the full TrainBuilder heap).
function TrainController.setFill(vehicle: Vehicle, fill: number)
	vehicle.Fill = math.clamp(fill, 0, 1)
	for i, drop in vehicle.Heap do
		vehicle.Offsets[i] = vehicle.Base[i] - Vector3.new(0, drop * (1 - vehicle.Fill), 0)
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
	return {
		Vehicles = vehicles,
		Key = key or "",
		Steam = nil,
		SteamRate = -1,
		LastTip = 0,
		Leg = nil,
		Load = {},
		Count = 0,
		Dirty = true,
	}
end

--[[
	Appends every shown part of a consist and its CFrame for pose `p` (one
	BulkMoveTo for all trains). Vehicles inside a tunnel are unparented,
	shown ones go into `parent`.
]]
function TrainController.placeConsist(consist: Consist, p: Pose, parent: Instance?, parts: { BasePart }, cframes: { CFrame })
	local facing = p.Facing
	local ahead = CFrame.lookAt(Vector3.new(), facing)
	local turned = ahead * CFrame.Angles(0, math.pi, 0)
	local tipAngle = p.Tip * TrainController.TipAngle
	for _, vehicle in consist.Vehicles do
		local center = p.Position - facing * vehicle.Offset
		local shown = TrainController.visible(p, center, vehicle.Half)
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
			TrainController.setFill(wagon, fill)
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
local parked: Consist? = nil
local folder: Folder? = nil
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local bannerCache: { [number]: Color3 } = {}

local snapshot: TrainView.Snapshot? = nil
local coins = 0
local autoAt: number? = nil -- os.clock() when the train leaves by itself
local refs: TrainView.Refs? = nil
local panelOpen = false
local openedAt = -math.huge
local sendLockedUntil = 0
local buyLockedUntil = 0
local pulse: Tween? = nil
local shownKey = ""

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function myPlot(): WorldLayout.Plot?
	local p = player
	local id = p and p:GetAttribute("PlotId")
	return if type(id) == "number" then WorldLayout.Plots[id] else nil
end

-- A plot's banner color (the Banner part when it is streamed in, else PlotBuilder's list).
local function bannerColor(plotId: number): Color3
	local cached = bannerCache[plotId]
	if cached then
		return cached
	end
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. plotId)
	local banner = plot and plot:FindFirstChild("Banner", true)
	if banner and banner:IsA("BasePart") then
		bannerCache[plotId] = banner.Color
		return banner.Color
	end
	return TrainController.BannerColors[(plotId - 1) % #TrainController.BannerColors + 1]
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

---------------------------------------------------------------- steam, chuffs, pour

local STEAM_MAX = 6
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

local function dropConsist(consist: Consist)
	local steam = consist.Steam
	if steam then
		giveSteam(steam)
		consist.Steam = nil
	end
	TrainController.destroyConsist(consist)
end

type Chunk = {
	Part: BasePart,
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

local function freeChunk(): Chunk?
	for _, chunk in chunks do
		if not chunk.Active then
			return chunk
		end
	end
	if #chunks >= CHUNK_MAX then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = "OreChunk"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	local chunk: Chunk = {
		Part = part,
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

-- The ore leaves the tipped wagons: a dust puff at each, chunks arc into the pen.
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
			for i = 1, math.ceil(count / wagons) do
				local chunk = freeChunk()
				if not chunk then
					break
				end
				local size = 0.9 + math.random() * 0.5
				chunk.Part.Size = Vector3.new(size, size * 0.8, size)
				chunk.Part.Color = colors[(i + w) % #colors + 1]
				chunk.From = mouth + p.Facing * ((math.random() - 0.5) * 4)
				chunk.To = TrainController.penSpot(plot, math.random(), math.random())
				chunk.Start = now + (i - 1) * 0.06
				chunk.Duration = 0.75 + math.random() * 0.25
				chunk.Height = 7 + math.random() * 3
				chunk.Spin = Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4)
				chunk.Active = true
				chunk.Lands = i == 1 and w == 2
				chunk.Part.CFrame = CFrame.new(chunk.From)
				chunk.Part.Parent = ensureFolder()
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
				chunk.Part.Parent = nil
				if chunk.Lands then
					Vfx.burst("Dust", chunk.To + Vector3.new(0, 0.5, 0), 8, DUST)
					Sfx.play("Gulp", chunk.To)
				end
			else
				local f = math.max(t, 0)
				local at = TrainController.arc(chunk.From, chunk.To, chunk.Height, f)
				local spin = chunk.Spin * f
				table.insert(moveParts, chunk.Part)
				table.insert(moveCFrames, CFrame.new(at) * CFrame.Angles(spin.X, spin.Y, spin.Z))
			end
		end
	end
end

local CHUFF_RANGE = 120
local nextChuff = 0

---------------------------------------------------------------- trains per frame

local builtCount = 0

-- Before building: does the locomotive or the last wagon show? (TrainBuilder's
-- coupler lengths: locomotive back coupler 7.15, wagons 12 long.)
local function anyVisible(p: Pose, wagons: number): boolean
	if p.Hidden then
		return false
	end
	local last = 7.15 + 6 + (wagons - 1) * 12
	return TrainController.visible(p, p.Position, 7.2) or TrainController.visible(p, p.Position - p.Facing * last, 6.2)
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

-- Builds, moves or drops one trip's train. Returns its pose when the
-- locomotive shows (nil otherwise) and whether it was built this frame.
local function stepTrip(userId: number, trip: Trip, now: number, eye: Vector3, canBuild: boolean): (Pose?, boolean)
	local plot = WorldLayout.Plots[trip.PlotId]
	local p = TrainController.poseAt(plot, trip.DepartAt, trip.ArriveAt, now)
	local wagons = TrainController.wagonCount(trip.Count)
	local consist = built[userId]
	local distance = (p.Position - eye).Magnitude
	if p.Leg == "Done" or not anyVisible(p, wagons) or distance > TrainController.DropRange then
		if consist then
			dropConsist(consist)
			built[userId] = nil
			builtCount -= 1
		end
		return nil, false
	end
	local didBuild = false
	if not consist then
		if not canBuild or distance > TrainController.BuildRange or builtCount >= TrainController.MaxBuilt then
			return nil, false
		end
		local made =
			TrainController.buildConsist(trip.Color, TrainController.splitLoad(trip.Load, wagons), TrainController.wagonFlip(plot), "trip")
		made.Load = trip.Load
		made.Count = trip.Count
		made.LastTip = p.Tip -- a train built mid-unload doesn't pour again
		built[userId] = made
		builtCount += 1
		consist = made
		didBuild = true
	end
	local train = consist :: Consist
	local locoWasShown = train.Vehicles[1].Shown
	TrainController.applyPour(train, p)
	TrainController.placeConsist(train, p, ensureFolder(), moveParts, moveCFrames)
	updateSteam(train, p)
	-- whistle when it sets off, and when it comes out of the south tunnel
	local loco = train.Vehicles[1]
	local portal, normal = p.Portal, p.Normal
	local justOut = portal ~= nil and normal ~= nil and (p.Position - portal):Dot(normal) < 16
	if loco.Shown and not locoWasShown and p.Leg == "Coast" and justOut then
		Sfx.play("TrainWhistle", p.Position)
	elseif p.Leg == "Quarry" and (train.Leg == "Waiting" or (didBuild and now - trip.DepartAt < 1)) then
		Sfx.play("TrainWhistle", p.Position)
	end
	train.Leg = p.Leg
	if p.Tip >= TrainController.PourThreshold and train.LastTip < TrainController.PourThreshold then
		pour(train, p, plot)
	end
	train.LastTip = p.Tip
	return if loco.Shown then p else nil, didBuild
end

-- Your train waiting at the Mine Station (built from the State snapshot).
local function stepParked(now: number, eye: Vector3, canBuild: boolean)
	local plot = myPlot()
	local train = snapshot
	local p = player
	local mine = if p then trips[p.UserId] else nil
	local away = mine ~= nil and now < mine.ArriveAt + TrainConfig.ReturnSeconds
	-- the snapshot knows about a trip before (or without) its TrainTrip event
	local departAt, arriveAt = train and train.DepartAt, train and train.ArriveAt
	if departAt and arriveAt and now >= departAt and now < arriveAt + TrainConfig.ReturnSeconds then
		away = true
	end
	if not plot or not train or away then
		if parked then
			dropConsist(parked)
			parked = nil
		end
		return
	end
	local sinceEnd = if mine then now - (mine.ArriveAt + TrainConfig.ReturnSeconds) else nil
	local standing = TrainController.parkedPose(plot, sinceEnd)
	local distance = (standing.Position - eye).Magnitude
	if distance > TrainController.DropRange then
		if parked then
			dropConsist(parked)
			parked = nil
		end
		return
	end
	local wagons = TrainController.wagonCount(train.Capacity)
	local fills = TrainController.wagonFills(train.Cargo, train.Capacity, wagons)
	local color = bannerColor(plot.Id)
	local key = color:ToHex() .. "/" .. wagons
	for _, fill in fills do
		key ..= if fill > 0 then "L" else "E"
	end
	local consist = parked
	if consist and consist.Key ~= key then
		dropConsist(consist)
		parked = nil
		consist = nil
	end
	if not consist then
		if not canBuild or distance > TrainController.BuildRange then
			return
		end
		local loads: { { Color3 } } = {}
		local split = TrainController.splitLoad({}, wagons)
		for i, fill in fills do
			loads[i] = if fill > 0 then split[i] else {}
		end
		consist = TrainController.buildConsist(color, loads, false, key)
		parked = consist
	end
	local station = consist :: Consist
	for i, fill in fills do
		local wagon = station.Vehicles[i + 1]
		if wagon and wagon.Loaded and math.abs(wagon.Fill - fill) > 1e-3 then
			TrainController.setFill(wagon, fill)
			station.Dirty = true
		end
	end
	if station.Dirty or standing.Speed > 0 then
		TrainController.placeConsist(station, standing, ensureFolder(), moveParts, moveCFrames)
		station.Dirty = standing.Speed > 0 -- once more after it stops, right on QuarryStop
	end
	updateSteam(station, standing)
end

local order: { number } = {}

local function step()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = serverNow()
	table.clear(moveParts)
	table.clear(moveCFrames)
	local canBuild = true -- at most one new train per frame (no hitches)
	local chuffPose: Pose? = nil
	local chuffDistance = CHUFF_RANGE
	local me = player
	local myId = if me then me.UserId else 0
	-- your own trip first: it gets this frame's build (no gap when it leaves the station)
	order[1] = myId
	local n = 1
	for userId in trips do
		if userId ~= myId then
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
		local keep = if userId == myId then TrainController.RollInSeconds + 1 else 1
		if now > trip.ArriveAt + TrainConfig.ReturnSeconds + keep then
			trips[userId] = nil
			local consist = built[userId]
			if consist then
				dropConsist(consist)
				built[userId] = nil
				builtCount -= 1
			end
		else
			local p, didBuild = stepTrip(userId, trip, now, eye, canBuild)
			if didBuild then
				canBuild = false
			end
			if p and p.Speed > 1 then
				local d = (p.Position - eye).Magnitude
				if d < chuffDistance then
					chuffDistance = d
					chuffPose = p
				end
			end
		end
	end
	for userId, consist in built do
		if not trips[userId] then
			dropConsist(consist)
			built[userId] = nil
			builtCount -= 1
		end
	end
	stepParked(now, eye, canBuild)
	moveChunks(os.clock())
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local chuff = chuffPose
	if chuff and os.clock() >= nextChuff then
		-- two chuffs per turn of the big drive wheels (2.7 studs across)
		nextChuff = os.clock() + math.max(0.25, 8.5 / (2 * chuff.Speed))
		Sfx.play("TrainChuff", chuff.Position)
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
	local key = `{current.Title}|{current.Line}|{current.CanSend}|{current.Fill}|{current.Progress or -1}`
	if key ~= shownKey or force then
		shownKey = key
		TrainView.setStatus(view, current)
		setPulse(view, current.Phase == "Full")
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
		if current.Phase == "Moving" then
			deny("Your train is on its way. It comes back after the delivery.")
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
	-- (not while the HUD is hidden: the cleaning close-up and other full-screen modes)
	if not view or not snapshot or not view.Chip.Enabled then
		return
	end
	if panelOpen then
		refreshPanel()
		return
	end
	panelOpen = true
	openedAt = os.clock()
	fit()
	refreshUI(true)
	refreshPanel()
	view.Gui.Enabled = true
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
	if existing and existing.DepartAt == trip.DepartAt and existing.ArriveAt == trip.ArriveAt then
		-- same trip again (join list + event): keep the richer payload
		if #trip.Load == 0 then
			return
		end
	end
	if existing then
		local consist = built[trip.UserId]
		if consist and (existing.DepartAt ~= trip.DepartAt or #existing.Load ~= #trip.Load) then
			dropConsist(consist)
			built[trip.UserId] = nil
			builtCount -= 1
		end
	end
	trips[trip.UserId] = trip
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

-- Your trip from the State snapshot when no TrainTrip event came for it
-- (missed while joining). 2 s of grace first: the event with the load colors
-- normally arrives together with the snapshot.
local function syncSnapshotTrip()
	local train = snapshot
	local me = player
	local plot = myPlot()
	if not train or not me or not plot then
		return
	end
	local departAt, arriveAt = train.DepartAt, train.ArriveAt
	local now = serverNow()
	if departAt and arriveAt and arriveAt > departAt and now > departAt + 2 and now < arriveAt + TrainConfig.ReturnSeconds then
		local known = trips[me.UserId]
		if not known or math.abs(known.ArriveAt - arriveAt) > 0.5 then
			addTrip({
				UserId = me.UserId,
				PlotId = plot.Id,
				DepartAt = departAt,
				ArriveAt = arriveAt,
				Count = math.max(1, train.Moving),
				Color = bannerColor(plot.Id),
				Load = {},
			})
		end
	end
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

local function onUnload(plotId: any, count: any)
	local plot = if type(plotId) == "number" then WorldLayout.Plots[plotId] else nil
	local camera = Workspace.CurrentCamera
	if not plot or not camera then
		return
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
end

---------------------------------------------------------------- station prompt

local function addPrompt(station: Instance)
	local function attach(point: Instance)
		if not point:IsA("Attachment") or point.Name ~= "PromptPoint" or point:FindFirstChild("TrainPrompt") then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TrainPrompt"
		prompt.ActionText = "Train"
		prompt.ObjectText = "Mine Station"
		prompt.KeyboardKeyCode = Enum.KeyCode.T
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonL3
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = point
		prompt.Triggered:Connect(function()
			TrainController.open()
		end)
	end
	for _, d in station:GetDescendants() do
		attach(d)
	end
	-- streaming: the attachment may arrive after the model
	station.DescendantAdded:Connect(attach)
end

---------------------------------------------------------------- lifecycle

function TrainController.init()
	FxController = require(script.Parent.FxController)
	HudController = require(script.Parent.HudController)
	PromptController = require(script.Parent.PromptController)
	StateController = require(script.Parent.StateController)
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
			view.Chip.Enabled = hud.Gui.Enabled
			if not hud.Gui.Enabled then
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

	CollectionService:GetInstanceAddedSignal("TrainStation"):Connect(addPrompt)
	for _, station in CollectionService:GetTagged("TrainStation") do
		addPrompt(station)
	end
	local me = player
	if me then
		me:GetAttributeChangedSignal("PlotId"):Connect(function()
			local plot = myPlot()
			if plot then
				TrainView.setColor(view, bannerColor(plot.Id))
			end
		end)
	end

	-- one loop: every train, your waiting train, the flying ore; the chip text 4x a second
	local uiClock = 0
	RunService.RenderStepped:Connect(function(dt)
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
