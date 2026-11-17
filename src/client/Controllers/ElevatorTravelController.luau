--[[
	ElevatorTravelController: the elevator's travel cinematic on the client
	(owner 2026-11-15, "ROBLOX ELEVATOR TRAVEL ANIMATION"; the timeline and the
	mines' looks are Config/ElevatorTravelConfig). The server decides and moves
	(ElevatorService checks the floor, the blaster, the elevator and one ride at
	a time, then moves the character behind the shut doors); this only shows it.
	ElevatorController hands over the ElevatorRide messages:

	  depart(payload)  "Depart" { Floor, From, Name, FromAt, StopAt?, Target }:
	                   the preparation starts at once at the stop the player
	                   stands at (PREPARING ELEVATOR..., the cage lamp turns up,
	                   the warning light flashes, a small shake, a clunk); the
	                   floor window stays up until phase "Enter"
	  arrive(payload)  "Arrive": the character stands at the target stop; the
	                   cabin brakes once the ride's time is up and the stop has
	                   streamed in (or a moment after)
	  cancel(payload)  "Cancel": nothing moved (the rider left, died or
	                   respawned): the game comes back at once behind a short fade

	While a ride plays (isTraveling): the controls, prompts, grab, the blaster,
	the HUD's guis and the touch controls are off; from the dip on the camera is
	scripted (Builders/ElevatorCabinStage.camera), the character hidden, the
	real cage of the stop hidden under the cabin (LocalTransparencyModifier, its
	lights off), the lighting the dark "ElevatorRide" preset until the stop.
	Every way out (the end, Cancel, a respawn, no "Arrive" within
	Timing.FailSafe, an error in a frame) gives everything back: the camera
	(Custom, the player's field of view), the character, the controls, the HUD,
	the real cages, the lighting. The arrival's effects (Builders/ElevatorArrivalFx)
	play on for a moment after the controls are back.

	onPhase(fn(phase, floor)): "Prepare" (Depart), "Enter" (close the floor window
	now: the camera steps into the cabin), "Ride" (the doors meet), "Arrive" (the
	stop), "Done" (the game is back), "Cancel" (cut short).
	Sounds (SoundConfig): ElevatorStart, ElevatorWarn, ElevatorDoorClose,
	DoorThud, the ElevatorHum loop (its pitch follows the speed), ElevatorTick at
	every floor passed, ElevatorBrake, ElevatorDing, ElevatorDoorOpen,
	ElevatorArrive and the mine's own sound (Theme.Sound).
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ElevatorTravelConfig = require(Shared.Config.ElevatorTravelConfig)
local MineFloors = require(Shared.Config.MineFloors)
local Stage = require(Shared.Builders.ElevatorCabinStage)
local ArrivalFx = require(Shared.Builders.ElevatorArrivalFx)
local View = require(script.Parent.Parent.UI.ElevatorTravelView)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HiddenScale = require(script.Parent.Parent.Util.HiddenScale)
local HudController = require(script.Parent.HudController)
local LightingController = require(script.Parent.LightingController)
local PromptController = require(script.Parent.PromptController)
local InteractController = require(script.Parent.InteractController)
local MiningController = require(script.Parent.MiningController)
local CapsuleController = require(script.Parent.CapsuleController)

local ElevatorTravelController = {}

type Plan = ElevatorTravelConfig.Plan
type Theme = ElevatorTravelConfig.Theme

local RENDER_STEP = "TerraForgeElevatorTravel"
local LOCK = "ElevatorTravel"
local STOP_TAG = "MineElevator"
local LIGHTING = "ElevatorRide"
-- the brake waits at most this long after "Arrive" for the target stop to stream in
local STREAM_GRACE = 1.2
-- a stop matches a payload's floor center within this many studs
local MATCH = 0.75
-- where BackpackWearController and RoyalCapeController keep the worn packs and capes (welded to their
-- wearers' torsos): the player's own go with the body while it is hidden
local WORN_FOLDERS = { "ClientBackpacks", "ClientCapes" }

type Hidden = { Saved: { [BasePart]: number }, Lights: { [Instance]: boolean }, Model: Model?, Added: RBXScriptConnection? }
type HiddenGui = { Scale: UIScale, Wanted: number, Connection: RBXScriptConnection }
-- (lists, not tables keyed by the instance: a rescan finds the same part again by ==)
type WornPart = { Item: Instance, Saved: number }
type WornFx = { Item: Instance, Was: boolean }

type Trip = {
	Plan: Plan,
	Floor: number,
	Name: string,
	Theme: Theme,
	FromAt: CFrame,
	StopAt: CFrame?,
	Target: CFrame?,
	Reduced: boolean,
	Clock: number, -- the plan's clock (held at the brake while it waits)
	Last: number, -- os.clock of the last frame
	Travel: number,
	Arrived: boolean,
	ArrivedAt: number?, -- os.clock of "Arrive"
	Waited: number,
	Fired: { [string]: boolean },
	CutAt: number?,
	Taken: boolean, -- the camera is scripted
	SavedFov: number,
	SavedZoom: number,
	ExitZoom: number?, -- how far behind the player the camera ends (less where something stands behind)
	Frozen: boolean, -- we hold the controls lock
	Origin: Hidden,
	Dest: Hidden,
	Lamp: PointLight?,
	LampBrightness: number,
	Character: { Instance }, -- the character's parts and decals (hidden in the cabin)
	PopLighting: (() -> ())?,
	Guis: { [ScreenGui]: HiddenGui }, -- the game's guis put away (by their "Scale" UIScale)
	GuiAdded: RBXScriptConnection?,
	TouchWas: boolean?,
	Pose: Stage.Pose, -- written in place every frame
	CameraInfo: Stage.CameraInfo,
	Worn: { WornPart }, -- the player's own worn pack and cape: their parts' modifiers before the ride
	WornFx: { WornFx }, -- their lights / particles / beams: Enabled before the ride
	WornScan: number, -- the plan time the worn things were last looked for
	Removing: RBXScriptConnection?,
	Done: boolean,
}

local player = Players.LocalPlayer
local stage: Stage.Stage? = nil
local fx: ArrivalFx.Fx? = nil
local view: View.Refs? = nil
local trip: Trip? = nil
local listeners: { (string, number) -> () } = {}
local fxConnection: RBXScriptConnection? = nil
local fxToken = 0

---------------------------------------------------------------- public

-- True from "Depart" until the cinematic is over (the floor window refuses TRAVEL meanwhile).
function ElevatorTravelController.isTraveling(): boolean
	return trip ~= nil
end

-- Listens for the cinematic's phases ("Prepare", "Enter", "Ride", "Arrive", "Done", "Cancel").
function ElevatorTravelController.onPhase(fn: (string, number) -> ())
	table.insert(listeners, fn)
end

local function phase(name: string, floor: number)
	for _, fn in listeners do
		task.spawn(fn, name, floor)
	end
end

---------------------------------------------------------------- the set

local function ensureStage(): Stage.Stage
	local made = stage
	if made then
		return made
	end
	local built = Stage.build()
	built.Bulk = function(parts: { BasePart }, frames: { CFrame })
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	stage = built
	return built
end

local function ensureFx(): ArrivalFx.Fx
	local made = fx
	if made then
		return made
	end
	local built = ArrivalFx.build()
	fx = built
	return built
end

local function ensureView(): View.Refs
	local made = view
	if made then
		return made
	end
	local built = View.build()
	built.Gui.Parent = player:WaitForChild("PlayerGui")
	view = built
	return built
end

-- The stop model whose floor center is `at` (nil while it hasn't streamed in).
local function stopAt(at: CFrame): Model?
	for _, instance in CollectionService:GetTagged(STOP_TAG) do
		if instance:IsA("Model") then
			local base = instance:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				local center = base.CFrame * CFrame.new(0, -base.Size.Y / 2, 0)
				if (center.Position - at.Position).Magnitude < MATCH then
					return instance
				end
			end
		end
	end
	return nil
end

-- Does a part's box reach into the cabin's box (both in the stop's frame)?
local function underCabin(part: BasePart, at: CFrame): boolean
	local cf = at:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local r = cf.RightVector
	local u = cf.UpVector
	local l = cf.LookVector
	local ex = math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z
	local ey = math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z
	local ez = math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
	local p = cf.Position
	local box = Stage.HideBox
	return p.X + ex > box.Min.X
		and p.X - ex < box.Max.X
		and p.Y + ey > box.Min.Y
		and p.Y - ey < box.Max.Y
		and p.Z + ez > box.Min.Z
		and p.Z - ez < box.Max.Z
end

local function hidePart(hidden: Hidden, instance: Instance, at: CFrame)
	if instance:IsA("BasePart") then
		if hidden.Saved[instance] == nil and underCabin(instance, at) then
			hidden.Saved[instance] = instance.LocalTransparencyModifier
			instance.LocalTransparencyModifier = 1
			for _, child in instance:GetChildren() do
				if child:IsA("Light") and hidden.Lights[child] == nil then
					hidden.Lights[child] = child.Enabled
					child.Enabled = false
				end
			end
		end
	end
end

-- Hides the real cage of the stop at `at` under the cabin (and parts of it that stream in later).
local function hideStop(hidden: Hidden, at: CFrame)
	if hidden.Model then
		return
	end
	local model = stopAt(at)
	if not model then
		return
	end
	hidden.Model = model
	for _, d in model:GetDescendants() do
		hidePart(hidden, d, at)
	end
	hidden.Added = model.DescendantAdded:Connect(function(d: Instance)
		hidePart(hidden, d, at)
	end)
end

-- The real cage back: `level` 0 = as it was, 1 = hidden (a cross-fade on the way out).
local function showStop(hidden: Hidden, level: number)
	for part, saved in hidden.Saved do
		part.LocalTransparencyModifier = saved + (1 - saved) * level
	end
	if level <= 0 then
		for lightObject, enabled in hidden.Lights do
			local l: any = lightObject
			l.Enabled = enabled
		end
		table.clear(hidden.Lights)
		table.clear(hidden.Saved)
		if hidden.Added then
			hidden.Added:Disconnect()
			hidden.Added = nil
		end
		hidden.Model = nil
	end
end

local function newHidden(): Hidden
	return { Saved = {}, Lights = {}, Model = nil, Added = nil }
end

---------------------------------------------------------------- the player's character

local function characterParts(): { Instance }
	local out: { Instance } = {}
	local character = player.Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function setCharacter(list: { Instance }, modifier: number)
	for _, d in list do
		if d.Parent then
			local target: any = d
			target.LocalTransparencyModifier = modifier
		end
	end
end

-- Is `model` welded to `character` (a worn backpack or cape)?
local function wornBy(model: Instance, character: Model): boolean
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			local joint: any = d
			local a, b = joint.Part0, joint.Part1
			if (a and a:IsDescendantOf(character)) or (b and b:IsDescendantOf(character)) then
				return true
			end
		end
	end
	return false
end

local EFFECT_CLASSES = { "Light", "ParticleEmitter", "Beam", "Trail" }

local function known(list: { any }, item: Instance): boolean
	for _, entry in list do
		if entry.Item == item then
			return true
		end
	end
	return false
end

-- Finds the player's own worn pack and cape (new ones too: a pack rebuilt meanwhile) and remembers
-- how they were before the ride.
local function collectWorn(t: Trip)
	local character = player.Character
	if not character then
		return
	end
	for _, name in WORN_FOLDERS do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			for _, model in folder:GetChildren() do
				if wornBy(model, character) then
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") or d:IsA("Decal") then
							if not known(t.Worn, d) then
								local target: any = d
								table.insert(t.Worn, { Item = d, Saved = target.LocalTransparencyModifier })
							end
						else
							for _, class in EFFECT_CLASSES do
								if d:IsA(class) and not known(t.WornFx, d) then
									local effect: any = d
									table.insert(t.WornFx, { Item = d, Was = effect.Enabled == true })
								end
							end
						end
					end
				end
			end
		end
	end
end

-- The worn pack and cape as hidden as the body (`level` 1 = gone): their lights and particles are off
-- while they are mostly hidden.
local function setWorn(t: Trip, level: number)
	for _, entry in t.Worn do
		if entry.Item.Parent then
			local target: any = entry.Item
			target.LocalTransparencyModifier = entry.Saved + (1 - entry.Saved) * level
		end
	end
	for _, entry in t.WornFx do
		if entry.Item.Parent then
			local effect: any = entry.Item
			effect.Enabled = entry.Was and level < 0.5
		end
	end
end

-- The worn pack and cape exactly as they were.
local function restoreWorn(t: Trip)
	for _, entry in t.Worn do
		if entry.Item.Parent then
			local target: any = entry.Item
			target.LocalTransparencyModifier = entry.Saved
		end
	end
	for _, entry in t.WornFx do
		if entry.Item.Parent then
			local effect: any = entry.Item
			effect.Enabled = entry.Was
		end
	end
	table.clear(t.Worn)
	table.clear(t.WornFx)
end

--[[
	How far behind the player the camera can end on the way out: the player's
	own zoom, or less where something stands behind them (a wall, the cage's
	roof), as Roblox's camera would push in there anyway once it has the
	camera back (no jump at the hand back). The cabin's parts never count
	(CanQuery off).
]]
local function exitZoom(t: Trip): number
	local target = t.Target
	if not target then
		return t.SavedZoom
	end
	local ok, distance = pcall(function(): number
		local wanted = Stage.exitCamera(target, t.SavedZoom)
		local focus = target.Position + Vector3.new(0, Stage.HeadLift, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local character = player.Character
		params.FilterDescendantsInstances = if character then { character } else {}
		local hit = Workspace:Raycast(focus, wanted.Position - focus, params)
		if hit then
			return math.max(0.5, (hit.Position - focus).Magnitude - 0.6)
		end
		return t.SavedZoom
	end)
	return if ok and type(distance) == "number" then distance else t.SavedZoom
end

-- The camera's distance from the player before the ride (the hand back puts it there again).
local function zoomNow(camera: Camera): number
	local distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	if distance ~= distance or distance > 400 then
		return 12.5
	end
	return math.clamp(distance, 0.5, 40)
end

---------------------------------------------------------------- taking the game and giving it back

--[[
	The game's guis put away for the cinematic the way the egg opening does
	(CapsuleController.hideHud): every TerraForge* ScreenGui with a "Scale"
	UIScale (UIKit.screenGui: the HUD, the menus, the windows) goes to scale 0
	and stays there (a scale written meanwhile, e.g. the HUD following a
	resize, is kept for later); guis made during the ride too. Enabled is
	never touched: an owner may close its gui meanwhile (a banner's timer) or
	open one (it shows after the ride), and that stays theirs. A UIScale reads
	0 back as 1e-07, hence HiddenScale.
]]
local function hideGui(t: Trip, gui: Instance)
	local mine = view and view.Gui
	if not gui:IsA("ScreenGui") or gui == mine or string.sub(gui.Name, 1, 10) ~= "TerraForge" then
		return
	end
	local screen = gui :: ScreenGui
	if t.Guis[screen] then
		return
	end
	local scale = screen:FindFirstChild("Scale")
	if not scale or not scale:IsA("UIScale") then
		return -- (effect layers without the HUD's scale finish as they are)
	end
	local uiScale = scale :: UIScale
	local entry: HiddenGui = { Scale = uiScale, Wanted = uiScale.Scale, Connection = nil :: any }
	t.Guis[screen] = entry
	uiScale.Scale = 0
	entry.Connection = uiScale:GetPropertyChangedSignal("Scale"):Connect(function()
		if not HiddenScale.is(uiScale.Scale) then
			entry.Wanted = uiScale.Scale
			uiScale.Scale = 0
		end
	end)
end

local function hideGuis(t: Trip)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, gui in playerGui:GetChildren() do
		hideGui(t, gui)
	end
	t.GuiAdded = playerGui.ChildAdded:Connect(function(gui: Instance)
		-- (a moment later: a new gui gets its "Scale" after it is parented)
		task.defer(function()
			if not t.Done and t.GuiAdded and gui.Parent then
				hideGui(t, gui)
			end
		end)
	end)
	-- (a gamepad selection on a hidden button would press it unseen)
	GuiService.SelectedObject = nil
	local okTouch, touch = pcall(function(): any
		return GuiService.TouchControlsEnabled
	end)
	if okTouch then
		t.TouchWas = touch == true
		pcall(function()
			GuiService.TouchControlsEnabled = false
		end)
	end
end

local function restoreGuis(t: Trip)
	local added = t.GuiAdded
	t.GuiAdded = nil
	if added then
		added:Disconnect()
	end
	for gui, entry in t.Guis do
		entry.Connection:Disconnect()
		local scale = entry.Scale
		if scale.Parent then
			-- (a scale written after the last watch wins; a hidden one gets the HUD's own)
			local now = scale.Scale
			local wanted = if not HiddenScale.is(now) then now else entry.Wanted
			scale.Scale = if not HiddenScale.is(wanted) then wanted else HudController.uiScale()
		end
		t.Guis[gui] = nil
	end
	if t.TouchWas ~= nil then
		local was = t.TouchWas
		t.TouchWas = nil
		pcall(function()
			GuiService.TouchControlsEnabled = was
		end)
	end
end

local function takeCamera(t: Trip)
	local camera = Workspace.CurrentCamera
	if t.Taken or not camera then
		return
	end
	t.Taken = true
	camera.CameraType = Enum.CameraType.Scriptable
	t.Character = characterParts()
	collectWorn(t)
	hideGuis(t)
	t.PopLighting = LightingController.push(LIGHTING, 0.1)
end

-- `atTarget` = the ride ended at the target (the camera stands behind the player there); a ride cut
-- short leaves the camera to Roblox's own (it goes back to wherever the character is).
local function giveCamera(t: Trip, atTarget: boolean)
	local camera = Workspace.CurrentCamera
	if not t.Taken then
		return
	end
	t.Taken = false
	if camera then
		local target = t.Target
		if atTarget and target and player.Character then
			camera.CFrame = Stage.exitCamera(target, t.ExitZoom or t.SavedZoom)
		end
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = t.SavedFov
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	-- (first person keeps the character hidden, as Roblox's own camera does)
	setCharacter(t.Character, if t.SavedZoom < 1.2 then 1 else 0)
	restoreWorn(t)
	restoreGuis(t)
end

local function popLighting(t: Trip)
	local pop = t.PopLighting
	t.PopLighting = nil
	if pop then
		pop()
	end
end

local function unfreeze(t: Trip)
	if t.Frozen then
		t.Frozen = false
		task.spawn(PlayerControls.set, true)
		PlayerControls.release(LOCK)
	end
	PromptController.setSuppressed(LOCK, false)
	InteractController.resume()
	MiningController.setBusy(false)
end

local function stopFx()
	fxToken += 1
	if fxConnection then
		fxConnection:Disconnect()
		fxConnection = nil
	end
	local effects = fx
	if effects then
		ArrivalFx.hide(effects)
		effects.Folder.Parent = nil
	end
end

-- The arrival's effects keep playing on their own after the game is back, then go away.
local function playFxOn(t: Trip, sinceStop: number)
	local effects = fx
	if not effects or fxConnection then
		return
	end
	fxToken += 1
	local token = fxToken
	local started = os.clock() - sinceStop
	local reduced = t.Reduced
	fxConnection = RunService.Heartbeat:Connect(function()
		if fxToken ~= token then
			return
		end
		local since = os.clock() - started
		if since >= ElevatorTravelConfig.ArrivalTime then
			stopFx()
			return
		end
		ArrivalFx.pose(effects, since, reduced)
		ArrivalFx.rates(effects, since, reduced)
	end)
end

--[[
	Ends the ride: everything back to the player. `cut` = cut short (Cancel, a
	respawn, no "Arrive", an error): the screen comes back from black and the
	arrival's effects stop; otherwise they play on for a moment.
]]
local function finish(t: Trip, cut: boolean)
	if t.Done then
		return
	end
	t.Done = true
	if trip == t then
		trip = nil
	end
	RunService:UnbindFromRenderStep(RENDER_STEP)
	if t.Removing then
		t.Removing:Disconnect()
		t.Removing = nil
	end
	-- every step on its own: one that fails never keeps the others (the camera above all) from coming back
	local function safely(label: string, fn: () -> ())
		local ok, err = pcall(function()
			fn()
		end)
		if not ok then
			warn(`[ElevatorTravelController] giving back {label} failed: {err}`)
		end
	end
	safely("the hum", function()
		Sfx.loop("ElevatorHum", false)
	end)
	safely("the cage lamp", function()
		local lamp = t.Lamp
		t.Lamp = nil
		if lamp then
			lamp.Brightness = t.LampBrightness
		end
	end)
	safely("the cage left", function()
		showStop(t.Origin, 0)
	end)
	safely("the target's cage", function()
		showStop(t.Dest, 0)
	end)
	safely("the lighting", function()
		popLighting(t)
	end)
	safely("the camera", function()
		giveCamera(t, not cut)
	end)
	if t.Taken then
		-- (the hand back above failed: the camera at least is the player's again)
		t.Taken = false
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = t.SavedFov
		end
		safely("the guis", function()
			restoreGuis(t)
		end)
	end
	safely("the set", function()
		local set = stage
		if set then
			set.Folder.Parent = nil
			Stage.reset(set)
		end
	end)
	safely("the controls", function()
		unfreeze(t)
	end)
	local screen = view
	if cut then
		stopFx()
		if screen then
			-- a short fade back from black over whatever the camera jumped to
			screen.Abort = t.Clock
			-- black at once (this frame may show wherever the camera jumped to), then a short fade back
			screen.Dip.Visible = true
			screen.Dip.BackgroundTransparency = 0
			local started = os.clock()
			local info: View.Info =
				{ Name = t.Name, Floor = t.Floor, Glow = t.Theme.Glow, Down = t.Plan.Down, Reduced = t.Reduced, CutAt = nil }
			local connection: RBXScriptConnection? = nil
			connection = RunService.Heartbeat:Connect(function()
				local now = t.Clock + (os.clock() - started)
				if trip ~= nil or now - t.Clock >= 0.4 then
					if connection then
						connection:Disconnect()
					end
					if trip == nil then
						screen.Gui.Enabled = false
						screen.Abort = nil
					end
					return
				end
				screen.Dip.Visible = true
				screen.Dip.BackgroundTransparency = 1 - View.dipAt(t.Plan, now, info, t.Clock)
				screen.Prepare.Visible = false
				screen.Arrived.Visible = false
				screen.TopBar.Visible = false
				screen.BottomBar.Visible = false
			end)
		end
		phase("Cancel", t.Floor)
	else
		if screen then
			screen.Gui.Enabled = false
		end
		phase("Done", t.Floor)
	end
end

---------------------------------------------------------------- every frame

local function fire(t: Trip, key: string): boolean
	if t.Fired[key] then
		return false
	end
	t.Fired[key] = true
	return true
end

-- Sounds, phases and one-off moves when the plan's clock passes their time.
local function cues(t: Trip)
	local plan = t.Plan
	local timing = ElevatorTravelConfig.Timing
	local c = t.Clock
	if fire(t, "start") then
		Sfx.play("ElevatorStart")
	end
	for i, at in timing.Prepare do
		if c >= at and fire(t, "warn" .. i) then
			Sfx.play("ElevatorWarn")
		end
	end
	if c >= plan.Enter and fire(t, "enter") then
		phase("Enter", t.Floor)
	end
	if c >= plan.DipMid and fire(t, "inside") then
		-- behind black: the camera steps into the cabin, the real cage goes under it
		local lamp = t.Lamp
		if lamp then
			lamp.Brightness = t.LampBrightness
			t.Lamp = nil
		end
		takeCamera(t)
		hideStop(t.Origin, t.FromAt)
	end
	if c >= plan.DoorsCloseAt and fire(t, "close") then
		Sfx.play("ElevatorDoorClose")
	end
	if c >= plan.DoorsShut and fire(t, "shut") then
		Sfx.play("DoorThud")
		Sfx.loop("ElevatorHum", true)
		phase("Ride", t.Floor)
	end
	for i, tick in plan.Ticks do
		if c >= tick.Time and fire(t, "tick" .. i) then
			Sfx.play("ElevatorTick")
		end
	end
	if c > plan.BrakeAt and fire(t, "brake") then
		Sfx.play("ElevatorBrake")
	end
	if c >= plan.StopAt and fire(t, "stop") then
		Sfx.loop("ElevatorHum", false)
		Sfx.play("ElevatorDing")
		-- the cabin now stands at the target stop: the cage there goes under it, the one left comes back
		showStop(t.Origin, 0)
		local target = t.StopAt
		if target then
			hideStop(t.Dest, target)
		end
		popLighting(t)
		local effects = ensureFx()
		-- (a floor with no stop: round the character's feet)
		local spot = t.StopAt or (if t.Target then (t.Target :: CFrame) * CFrame.new(0, -3, 4.4) else t.FromAt)
		ArrivalFx.setTheme(effects, t.Theme, spot)
		effects.Folder.Parent = Workspace
		phase("Arrive", t.Floor)
	end
	if c >= plan.DoorsOpenAt and fire(t, "open") then
		t.ExitZoom = exitZoom(t)
		Sfx.play("ElevatorDoorOpen")
		local effects = fx
		if effects then
			ArrivalFx.burst(effects, t.Reduced)
		end
	end
	if c >= plan.DoorsOpenAt + 0.15 and fire(t, "sting") then
		Sfx.play("ElevatorArrive")
		Sfx.play(t.Theme.Sound)
	end
end

-- Is the arrival free to go on? (the character stands at the target, its stop has streamed in)
local function ready(t: Trip): boolean
	if not t.Arrived then
		return false
	end
	local target = t.StopAt
	if not target or t.Dest.Model then
		return true
	end
	hideStop(t.Dest, target)
	if t.Dest.Model then
		return true
	end
	local at = t.ArrivedAt
	return at ~= nil and os.clock() - at >= STREAM_GRACE
end

local function frame(t: Trip)
	local plan = t.Plan
	local now = os.clock()
	local dt = math.clamp(now - t.Last, 0, 0.1)
	t.Last = now
	-- the plan's clock stops at the brake until the arrival is free to go on (the shaft keeps rushing)
	local nextClock = t.Clock + dt
	if nextClock > plan.BrakeAt and t.Clock <= plan.BrakeAt and not ready(t) then
		t.Waited += dt
		if t.Waited >= ElevatorTravelConfig.Timing.FailSafe then
			finish(t, true)
			return
		end
		nextClock = plan.BrakeAt
	end
	t.Clock = nextClock
	local speed = Stage.speedAt(plan, t.Clock)
	t.Travel += dt * speed * ElevatorTravelConfig.ShaftSpeed
	cues(t)
	if t.Done then
		return
	end
	local c = t.Clock
	local reduced = t.Reduced
	-- the set
	local set = ensureStage()
	local pose = t.Pose
	pose.T, pose.Travel, pose.Speed = c, t.Travel, speed
	Stage.pose(set, plan, pose)
	-- PHASE 1: the cage lamp turns up and the game's own camera shakes a little (position only)
	local camera = Workspace.CurrentCamera
	if c < plan.DipMid then
		local lamp = t.Lamp
		if lamp then
			lamp.Brightness = t.LampBrightness * (1 + 1.4 * math.clamp(c / 0.3, 0, 1))
		end
		if camera and not reduced then
			local amp = ElevatorTravelConfig.Shake.Prepare * math.clamp(c / 0.15, 0, 1)
			camera.CFrame = camera.CFrame * CFrame.new(math.sin(c * 47) * amp, math.cos(c * 39) * amp, 0)
		end
	end
	-- the scripted camera from the dip on; the character hidden until it fades back in on the way out
	if t.Taken and camera then
		local info = t.CameraInfo
		info.Zoom, info.Speed = t.ExitZoom or t.SavedZoom, speed
		local cf, fov = Stage.camera(plan, c, info)
		if cf then
			camera.CFrame = cf
			-- (a scripted camera keeps its Focus: Roblox loads detail and lighting round it)
			camera.Focus = cf * CFrame.new(0, 0, -6)
			camera.FieldOfView = fov
		end
		-- (hidden while the doors open: nothing stands between the camera and the new mine)
		local back = if t.CutAt
			then (if c >= (t.CutAt :: number) + ElevatorTravelConfig.Timing.DipOut then 1 else 0)
			else math.clamp((c - plan.ExitAt) / 0.3, 0, 1)
		local hiddenLevel = if t.SavedZoom < 1.2 then 1 else 1 - back
		setCharacter(t.Character, hiddenLevel)
		-- the player's own worn pack and cape go with the body (a pack rebuilt meanwhile is found too)
		if back < 1 and c - t.WornScan >= 0.5 then
			t.WornScan = c
			collectWorn(t)
		end
		setWorn(t, 1 - back)
		-- the target stop streamed in late (after the stop): its cage goes under the cabin as soon as it is here
		local target = t.StopAt
		if target and c >= plan.StopAt and c < plan.ExitAt and not t.Dest.Model then
			hideStop(t.Dest, target)
		end
		-- the real cage fades back in as the cabin fades out
		if c >= plan.ExitAt then
			showStop(t.Dest, 1 - Stage.fadeAt(plan, c))
		end
	end
	-- the hum's pitch follows the speed
	if c >= plan.DoorsShut and c < plan.StopAt then
		Sfx.loopPitch("ElevatorHum", 0.75 + 0.45 * speed)
	end
	-- the arrival's effects
	local effects = fx
	if effects and c >= plan.StopAt then
		local since = c - plan.StopAt
		ArrivalFx.pose(effects, since, reduced)
		ArrivalFx.rates(effects, since, reduced)
	end
	-- the words on screen
	local screen = view
	if screen then
		View.pose(
			screen,
			plan,
			c,
			{ Name = t.Name, Floor = t.Floor, Glow = t.Theme.Glow, Down = plan.Down, Reduced = reduced, CutAt = t.CutAt }
		)
	end
	if c >= plan.EndAt then
		local sinceStop = c - plan.StopAt
		finish(t, false)
		playFxOn(t, sinceStop)
	end
end

local function step()
	local t = trip
	if not t then
		RunService:UnbindFromRenderStep(RENDER_STEP)
		return
	end
	local ok, err = pcall(function()
		frame(t)
	end)
	if not ok then
		warn("[ElevatorTravelController] a frame failed, the ride ends here: " .. tostring(err))
		finish(t, true)
	end
end

---------------------------------------------------------------- the messages

local function floorOf(value: any): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	local n = math.floor(value)
	return if n >= 1 and n <= 99 then n else nil
end

local function cframeOf(value: any): CFrame?
	return if typeof(value) == "CFrame" then value else nil
end

-- "Depart": plays the cinematic from the start (a ride still playing is given back first).
function ElevatorTravelController.depart(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local floorIndex = floorOf(payload.Floor)
	local fromAt = cframeOf(payload.FromAt)
	if not floorIndex or not fromAt then
		return
	end
	local old = trip
	if old then
		finish(old, true)
	end
	stopFx()
	local floor = MineFloors.ByIndex[floorIndex]
	local camera = Workspace.CurrentCamera
	-- (an egg opening's view still easing home: the player's own is saved)
	local ownFov = CapsuleController.settleView()
	local reduced = Motion.reduced()
	local plan = ElevatorTravelConfig.plan(payload.From, floorIndex)
	local stopCf = cframeOf(payload.StopAt)
	local t: Trip = {
		Plan = plan,
		Floor = floorIndex,
		Name = if type(payload.Name) == "string" then payload.Name elseif floor then floor.Name else "Mine",
		Theme = ElevatorTravelConfig.theme(if floor then floor.Id else nil),
		FromAt = fromAt,
		StopAt = stopCf,
		Target = cframeOf(payload.Target),
		Reduced = reduced,
		Clock = 0,
		Last = os.clock(),
		Travel = 0,
		Arrived = false,
		ArrivedAt = nil,
		Waited = 0,
		Fired = {},
		-- the camera cuts behind a dip: at the way out with reduced motion, at the stop when it has no stop
		CutAt = if not stopCf then plan.StopAt elseif reduced then plan.ExitAt else nil,
		Taken = false,
		SavedFov = ownFov or (if camera then camera.FieldOfView else ElevatorTravelConfig.Fov),
		SavedZoom = if camera then zoomNow(camera) else 12.5,
		ExitZoom = nil,
		Frozen = false,
		Origin = newHidden(),
		Dest = newHidden(),
		Lamp = nil,
		LampBrightness = 0,
		Character = {},
		PopLighting = nil,
		Guis = {},
		GuiAdded = nil,
		Pose = nil :: any,
		CameraInfo = nil :: any,
		Worn = {},
		WornFx = {},
		WornScan = -1,
		TouchWas = nil,
		Removing = nil,
		Done = false,
	}
	t.Pose = { T = 0, Travel = 0, Speed = 0, Reduced = reduced, FromAt = fromAt, StopAt = stopCf }
	t.CameraInfo = {
		FromAt = fromAt,
		StopAt = stopCf,
		Target = t.Target,
		Zoom = t.SavedZoom,
		Fov = t.SavedFov,
		Reduced = reduced,
		Speed = 0,
		CutAt = t.CutAt,
	}
	trip = t
	-- the character stands still from the first moment
	if PlayerControls.claim(LOCK) then
		t.Frozen = true
		task.spawn(PlayerControls.set, false)
	end
	PromptController.setSuppressed(LOCK, true)
	InteractController.suspend()
	MiningController.setBusy(true)
	-- the stop's own cage lamp turns up in the preparation
	local origin = stopAt(fromAt)
	local lampPart = origin and origin:FindFirstChild("CageLamp", true)
	local lamp = lampPart and lampPart:FindFirstChildOfClass("PointLight")
	if lamp then
		t.Lamp = lamp
		t.LampBrightness = lamp.Brightness
	end
	local set = ensureStage()
	Stage.reset(set)
	set.Folder.Parent = Workspace
	local screen = ensureView()
	View.layout(screen, HudController.uiScale(), 0)
	View.setRide(screen, { Name = t.Name, Floor = floorIndex, Glow = t.Theme.Glow, Down = plan.Down, Reduced = reduced, CutAt = t.CutAt })
	screen.Gui.Enabled = true
	t.Removing = player.CharacterRemoving:Connect(function()
		finish(t, true)
	end)
	RunService:UnbindFromRenderStep(RENDER_STEP)
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, step)
	phase("Prepare", floorIndex)
	step()
end

-- "Arrive": the character stands at the target stop (the cabin may brake).
function ElevatorTravelController.arrive(payload: any)
	local t = trip
	if not t or type(payload) ~= "table" then
		return
	end
	if payload.Ok == false then
		finish(t, true)
		return
	end
	t.Arrived = true
	t.ArrivedAt = os.clock()
end

-- "Cancel": nothing moved; the game comes back at once.
function ElevatorTravelController.cancel(_payload: any)
	local t = trip
	if t then
		finish(t, true)
	end
end

-- Ends a ride at once (the game back to the player), e.g. when the character goes.
function ElevatorTravelController.stop()
	local t = trip
	if t then
		finish(t, true)
	end
end

-- Internals for the Lune specs.
ElevatorTravelController._test = {
	trip = function(): any
		return trip
	end,
	stage = function(): any
		return stage
	end,
	fx = function(): any
		return fx
	end,
	view = function(): any
		return view
	end,
	underCabin = underCabin,
}

function ElevatorTravelController.init() end

-- The set and the arrival effects are built a little after the game starts (out of the world until a
-- ride), so the first ride never waits for ~280 new parts.
ElevatorTravelController.PrebuildDelay = 8

function ElevatorTravelController.start()
	task.delay(ElevatorTravelController.PrebuildDelay, function()
		if not trip then
			ensureStage()
			ensureFx()
		end
	end)
end

return ElevatorTravelController
