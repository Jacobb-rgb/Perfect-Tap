--[[
	WeatherController: the weather over Emberfall (owner reel 2026-10-27,
	Config/WeatherConfig). Rain, thunderstorms, hail, snow, wind, the
	heatwave and a rainbow after a shower, the same for every player with
	no network at all: Weather/WeatherLogic computes the weather from
	Workspace:GetServerTimeNow() and the config's seed. Effects/WeatherFx
	holds the instances, Effects/WeatherSway bends the trees.

	- Every CheckEvery seconds: the weather now (WeatherLogic.at, or the
	  Workspace attribute WeatherForce in Studio), the gate (weather shows
	  only on the surface: WeatherLogic.isSurface for the character, not
	  inside a LightingZone like the Blaster Vault, not during the elevator
	  ride, the cleaning close-up or the loading screen; it fades out in
	  GateFade seconds), the emitter rates (capped on phones and with Reduce
	  motion), the loop volumes, the ground pads (a couple of raycasts per
	  check, never closer than Ground.Clear to the camera), hail clacks, the
	  sky field's clear hole for the kind (WeatherLogic.hole).
	- One RenderStepped connection, only while there is weather (or its tint
	  is still fading): the boxes follow the camera, the tint eases toward
	  its target, the lightning strikes on time (a flash in WeatherTint, at
	  most one per Lightning.MinFlashGap, the thunder a beat later; no flash
	  with Reduce motion, no heat puffs either), the rainbow stays
	  opposite the sun, the trees near you sway (30 times a second at most).
	- Nothing is built until the first weather comes; the server does
	  nothing at all.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeatherConfig = require(Shared.Config.WeatherConfig)
local WeatherLogic = require(Shared.Weather.WeatherLogic)
local WeatherFx = require(script.Parent.Parent.Effects.WeatherFx)
local WeatherSway = require(script.Parent.Parent.Effects.WeatherSway)
local Motion = require(script.Parent.Parent.UI.Motion)
local Loading = require(script.Parent.Parent.Util.Loading)
local CleaningController = require(script.Parent.CleaningController)

local WeatherController = {}

WeatherController.RideGui = "TerraForgeElevatorRide" -- ElevatorRideView's ScreenGui (enabled during the ride)
WeatherController.ZoneTag = "LightingZone" -- LightingController's interior boxes (the Blaster Vault)

local player = Players.LocalPlayer
local fx: WeatherFx.Fx? = nil
local connection: RBXScriptConnection? = nil
local current: WeatherLogic.State? = nil
local look: WeatherConfig.Look? = nil

local gate = 0 -- 0..1: weather allowed here (eases)
local intensity = 0 -- the weather's strength x gate
local rainbowAlpha = 0
local busy = false -- anything to show (particles, sound, rainbow)
local phone = false
local reduced = false

local windYaw = 0
local slant = 0
local groundY = 0
local sunDirection = Vector3.new(-0.965, 0.225, 0.136).Unit

-- the tint shown now (eased every frame toward target; numbers, no allocation)
local target: WeatherLogic.Tint = WeatherLogic.Neutral
local shown: WeatherLogic.Tint = {
	Color = Color3.new(1, 1, 1),
	Brightness = 0,
	Contrast = 0,
	Saturation = 0,
}
local tintR, tintG, tintB = 1, 1, 1
local settled = true

-- lightning
local strikeEvent: WeatherLogic.Event? = nil
local nextStrike: WeatherLogic.Strike? = nil
local flashStart: number? = nil
local lastFlash: number? = nil

local rng = Random.new()
local rates: { [string]: number } = {}
local padIndex = 0
local clackDebt = 0
local swayAt = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false
local filteredCharacter: Model? = nil

-- The weather now (nil before the first check).
function WeatherController.current(): WeatherLogic.State?
	return current
end

-- True while weather shows (particles, sound, the rainbow).
function WeatherController.isActive(): boolean
	return busy
end

---------------------------------------------------------------- where weather shows

local function isPhone(): boolean
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return true
	end
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.min(size.X, size.Y) < 500
end

local function rideShowing(): boolean
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local ride = gui and gui:FindFirstChild(WeatherController.RideGui)
	return ride ~= nil and ride:IsA("ScreenGui") and ride.Enabled
end

-- Inside one of LightingController's interior boxes (the Blaster Vault).
local function indoors(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged(WeatherController.ZoneTag) do
		if zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function allowedHere(): boolean
	if CleaningController.isActive() or rideShowing() then
		return false
	end
	local camera = Workspace.CurrentCamera
	local position = rootPosition() or (if camera then camera.CFrame.Position else nil)
	if not position then
		return false
	end
	return WeatherLogic.isSurface(position) and not indoors(position)
end

---------------------------------------------------------------- the instances

local function ensureFx(): WeatherFx.Fx
	local existing = fx
	if existing and existing.Folder.Parent then
		return existing
	end
	local made = WeatherFx.build()
	fx = made
	return made
end

local function updateFilter(f: WeatherFx.Fx)
	local character = player.Character
	if character ~= filteredCharacter then
		filteredCharacter = character
		rayParams.FilterDescendantsInstances = if character then { f.Folder, character } else { f.Folder }
	end
end

-- The rates for this check (particles per second by emitter key).
local function applyRates(f: WeatherFx.Fx, l: WeatherConfig.Look?)
	table.clear(rates)
	if l then
		local function rate(base: number?): number
			return WeatherLogic.rate(base, intensity, phone, reduced)
		end
		rates.Rain = rate(l.Rain)
		rates.Hail = rate(l.Hail)
		rates.Snow = rate(l.Snow)
		local leaves = rate(l.Leaves) / 2
		rates.Leaves = leaves
		rates.Leaves2 = leaves
		rates.Heat = if reduced and not WeatherConfig.Reduced.Heat then 0 else rate(l.Heat)
		rates.Ripple = rate(l.Splash)
		rates.Drop = rate(l.Splash) * 0.6
		rates.Bounce = rate(l.Bounce)
		rates.Settle = rate(l.Settle)
	end
	WeatherFx.setRates(f, rates)
end

local function applySounds(f: WeatherFx.Fx, l: WeatherConfig.Look?)
	local loops = l and l.Loops
	for name in f.Loops do
		WeatherFx.setLoop(f, name, (if loops then loops[name] or 0 else 0) * intensity)
	end
end

-- Moves a couple of ground pads to new raycast spots near the camera; finds the ground's height.
local function movePads(f: WeatherFx.Fx, l: WeatherConfig.Look?, camera: Camera)
	local ground = WeatherConfig.Ground
	local wanted = l ~= nil and ((l.Splash or 0) > 0 or (l.Bounce or 0) > 0 or (l.Settle or 0) > 0)
	local count = if wanted then #f.Pads else 0
	if phone then
		count = math.min(count, WeatherConfig.Phone.GroundPoints)
	end
	for i = count + 1, #f.Pads do
		WeatherFx.placePad(f, i, nil)
	end
	updateFilter(f)
	local cf = camera.CFrame
	local down = Vector3.new(0, -ground.RayLength, 0)
	local below = rootPosition() or cf.Position
	local hit = Workspace:Raycast(below + Vector3.new(0, 2, 0), down, rayParams)
	groundY = if hit then hit.Position.Y else below.Y - 6
	if count == 0 then
		return
	end
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local focus = cf.Position + (if flat.Magnitude > 1e-3 then flat.Unit * ground.Ahead else Vector3.zero)
	for _ = 1, ground.PerTick do
		padIndex = padIndex % count + 1
		-- clear view: a spot too close to the camera is tried again (else the pad rests)
		local placed: Vector3? = nil
		for _ = 1, ground.Tries do
			local spot = focus + WeatherLogic.scatter(rng:NextNumber(), rng:NextNumber(), ground.Radius)
			local from = Vector3.new(spot.X, cf.Position.Y + ground.RayHeight, spot.Z)
			local result = Workspace:Raycast(from, down, rayParams)
			if result and WeatherLogic.padClear(result.Position, cf.Position) then
				placed = result.Position
				break
			end
		end
		WeatherFx.placePad(f, padIndex, placed)
	end
end

local function clacks(f: WeatherFx.Fx, l: WeatherConfig.Look?, dt: number)
	local per = if l then l.Clack or 0 else 0
	if per <= 0 or intensity <= 0 then
		clackDebt = 0
		return
	end
	clackDebt = math.min(clackDebt + per * intensity * dt * (if phone then 0.6 else 1), 4)
	local count = if phone then math.min(WeatherConfig.Phone.GroundPoints, #f.Pads) else #f.Pads
	while clackDebt >= 1 do
		clackDebt -= 1
		WeatherFx.clack(f, rng:NextInteger(1, math.max(1, count)), 0.6 + 0.4 * rng:NextNumber())
	end
end

---------------------------------------------------------------- lightning

local function strike(s: WeatherLogic.Strike, elapsed: number)
	-- a strike found late (the gate just opened) is skipped; so is one in a weak storm
	if elapsed - s.At > 1 or intensity < WeatherConfig.Lightning.MinIntensity then
		return
	end
	local now = os.clock()
	if (WeatherConfig.Reduced.Flash or not reduced) and WeatherLogic.flashAllowed(lastFlash, now) then
		flashStart = now
		lastFlash = now
	end
	local level = WeatherLogic.thunderLevel(s.Delay)
	local close = s.Delay < WeatherConfig.Lightning.CrackBelow
	task.delay(s.Delay, function()
		local f = fx
		if f and gate > 0.5 then
			WeatherFx.play(f, "Thunder", level)
			if close then
				WeatherFx.play(f, "Crack", level)
			end
		end
	end)
end

---------------------------------------------------------------- every frame

local function stopFrames()
	local c = connection
	if c then
		c:Disconnect()
		connection = nil
	end
	WeatherSway.stop()
	local f = fx
	if f then
		WeatherFx.hide(f)
	end
end

local function easeTint(dt: number): boolean
	local k = 1 - math.exp(-dt * WeatherConfig.TintSmooth)
	local c = target.Color
	tintR += (c.R - tintR) * k
	tintG += (c.G - tintG) * k
	tintB += (c.B - tintB) * k
	shown.Brightness += (target.Brightness - shown.Brightness) * k
	shown.Contrast += (target.Contrast - shown.Contrast) * k
	shown.Saturation += (target.Saturation - shown.Saturation) * k
	local gap = math.abs(c.R - tintR)
		+ math.abs(c.G - tintG)
		+ math.abs(c.B - tintB)
		+ math.abs(target.Brightness - shown.Brightness)
		+ math.abs(target.Contrast - shown.Contrast)
		+ math.abs(target.Saturation - shown.Saturation)
	return gap < 0.002
end

local function frame(dt: number)
	local f = fx
	local camera = Workspace.CurrentCamera
	if not f or not camera then
		return
	end
	local cf = camera.CFrame
	if busy then
		WeatherFx.place(f, cf, windYaw, slant, groundY)
	end

	-- lightning: strike on time, the flash eases off on its own curve
	local event = strikeEvent
	local s = nextStrike
	if event and s then
		local elapsed = Workspace:GetServerTimeNow() - event.Start
		if elapsed >= s.At then
			strike(s, elapsed)
			nextStrike = WeatherLogic.nextStrike(event, elapsed)
		end
	end
	local flash = 0
	local started = flashStart
	if started then
		local t = os.clock() - started
		flash = WeatherLogic.flash(t)
		if t >= WeatherConfig.Lightning.Length then
			flashStart = nil
		end
	end

	-- the tint: written while it moves or flashes
	local wasSettled = settled
	settled = easeTint(dt)
	if not (settled and wasSettled) or flash > 0 or started then
		shown.Color = Color3.new(tintR, tintG, tintB)
		WeatherFx.setTint(f, shown, flash)
	end

	-- the rainbow opposite the sun, at a fixed distance from the camera
	if rainbowAlpha > 0.005 then
		WeatherFx.setRainbow(f, rainbowAlpha, WeatherLogic.rainbowFrame(cf.Position, sunDirection))
	else
		WeatherFx.setRainbow(f, 0, nil)
	end

	-- trees lean with the wind (capped, 30 times a second at most)
	local l = look
	local amount = if l and l.Sway then l.Sway * intensity else 0
	local swayOn = WeatherConfig.TreeSway.On and (WeatherConfig.Reduced.Sway or not reduced)
	if amount > 0.002 and swayOn then
		local now = os.clock()
		if now >= swayAt then
			swayAt = now + 1 / 30
			local cap = if phone then WeatherConfig.Phone.TreeSway else WeatherConfig.TreeSway.Max
			WeatherSway.step(now, cf.Position, amount, WeatherLogic.windDirection(windYaw), cap)
		end
	elseif WeatherSway.active() then
		WeatherSway.stop()
	end

	if not busy and settled and not flashStart and WeatherLogic.isNeutral(target) then
		stopFrames()
	end
end

local function startFrames()
	if not connection then
		settled = false
		connection = RunService.RenderStepped:Connect(frame)
	end
end

---------------------------------------------------------------- every check

local function check(dt: number)
	local now = Workspace:GetServerTimeNow()
	local state = WeatherLogic.at(now, Workspace:GetAttribute(WeatherConfig.ForceAttribute))
	current = state
	local open = allowedHere()
	local was = gate
	local step = dt / math.max(WeatherConfig.GateFade, 0.05)
	gate = if open then math.min(1, gate + step) else math.max(0, gate - step)
	phone = isPhone()
	reduced = Motion.reduced()
	intensity = state.Intensity * gate
	rainbowAlpha = state.Rainbow * gate
	look = if state.Kind ~= "Clear" then WeatherConfig.Kinds[state.Kind] else nil
	target = WeatherLogic.tint(state.Kind, intensity, rainbowAlpha)
	windYaw = state.WindYaw
	slant = WeatherLogic.lookSlant(look)
	busy = intensity > 0.001 or rainbowAlpha > 0.001

	local f = fx
	if was > 0 and gate == 0 and f then
		WeatherFx.clear(f) -- went down / indoors: what still flies goes too
	end
	-- (at() makes a new Event table every check: compare by slot and start, or a strike due
	-- between this check and the next frame would be skipped)
	local event = state.Event
	local old = strikeEvent
	local same = old ~= nil and event ~= nil and old.Slot == event.Slot and old.Start == event.Start
	if not same then
		strikeEvent = event
		nextStrike = if event then WeatherLogic.nextStrike(event, state.Elapsed) else nil
	end

	local camera = Workspace.CurrentCamera
	if busy and camera then
		local made = ensureFx()
		WeatherFx.setHole(made, WeatherLogic.hole(look))
		sunDirection = Lighting:GetSunDirection()
		applyRates(made, look)
		applySounds(made, look)
		movePads(made, look, camera)
		clacks(made, look, dt)
		startFrames()
	elseif f then
		applyRates(f, nil)
		applySounds(f, nil)
		for i in f.Pads do
			WeatherFx.placePad(f, i, nil)
		end
		if not WeatherLogic.isNeutral(target) or not settled then
			startFrames()
		end
	end
end

function WeatherController.init() end

function WeatherController.start()
	if not WeatherConfig.Enabled then
		return
	end
	Loading.wait()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local f = fx
		if f then
			WeatherFx.tintParent(f)
		end
	end)
	local function failed(err: any)
		warn("[TerraForge] weather check failed: " .. tostring(err))
	end
	local last = os.clock()
	while true do
		local now = os.clock()
		xpcall(check, failed, math.min(now - last, 1))
		last = now
		task.wait(WeatherConfig.CheckEvery)
	end
end

return WeatherController
