--[[
	PlacementController: build mode on the client.

	Open it with B, gamepad D-pad Up or the BUILD button in the HUD menu, on
	your own plot (within BuildRange of it) and not while cleaning or
	forging. The camera flies to an overview of the plot, the grid appears
	and a tray lists the machines you can place. Pick one and a ghost
	follows the cursor: green where it fits, red with the reason where it
	doesn't, plus yellow warnings (blocked output, belts facing each other,
	a belt into a side that takes nothing). The amber plate shows where the
	machine's results come out. Placed machines can be selected, moved
	(their contents and running jobs stay) or packed up.

	  PC       mouse cursor. Click places (drag lays a line of belts),
	           R rotates. Click one of your machines to select it, then
	           M moves it and X / Delete packs it up. Right-click or C
	           cancels. WASD or right-drag pans, the wheel zooms, B closes.
	  Touch    tap a cell to put the ghost there (or tap one of your
	           machines), then use the big buttons. One finger pans,
	           pinch zooms.
	  Gamepad  the left stick moves the cursor (the machine under it is
	           selected). A places or picks the selection up to move it,
	           X rotates, hold Y packs it up, LB / RB pick from the tray,
	           the right stick pans, LT / RT zoom, B goes back or closes.

	The ghost uses the same Placement rules as the server, checked on the
	latest State snapshot plus our own requests still in flight (Seq
	numbered, at most SEND_RATE a second). The server always decides: a
	refused request shakes the ghost and says why. A placed belt moves the
	cursor one cell forward, so pressing Place again lays a line.

	Chutes (step 3, BaseLayout.Chutes): the three chute cells on the back
	row get a plate in their colour with their label floating over it (PEN,
	TRAIN, FOUNDRY; "turn the belt" in red while a belt on a Source chute
	runs off the grid into the yard). Only belts go there (Placement says
	"Chute"); the reason line shows the chute's Hint when the cursor or a
	belt ghost is on one, and warns "Turn the belt away from the yard" for
	a belt ghost on a Source chute that faces SinkRotation.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local WorldLayout = require(Shared.Config.WorldLayout)
local MachineBuilder = require(Shared.Builders.MachineBuilder)
local Grid = require(Shared.Machines.Grid)
local Placement = require(Shared.Machines.Placement)
local ConveyorLogic = require(Shared.Machines.ConveyorLogic)
local Net = require(Shared.Net)
local BuildView = require(script.Parent.Parent.UI.BuildView)
local GridOverlay = require(script.Parent.Parent.Effects.GridOverlay)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local StateController = require(script.Parent.StateController)
local HudController = require(script.Parent.HudController)
local FxController = require(script.Parent.FxController)
local InteractController = require(script.Parent.InteractController)
local MiningController = require(script.Parent.MiningController)
local PromptController = require(script.Parent.PromptController)
local CleaningController = require(script.Parent.CleaningController)

local PlacementController = {}

type Entry = Placement.Entry
type Mode = BuildView.Mode
type Kind = "Mouse" | "Touch" | "Gamepad"
type Op = "Place" | "Move" | "Pickup"

-- One build request: queued, sent, then answered (Done = the server said
-- yes, and we keep counting it until a State snapshot includes it).
type Request = {
	Seq: number,
	Op: Op,
	Id: string,
	X: number,
	Z: number,
	R: number,
	From: Entry?, -- Move / Pickup: where the machine stood
	Model: Model?,
	Sent: boolean,
	Done: boolean,
	At: number, -- os.clock() when sent or answered
}

type Pointer = { Start: Vector2, Last: Vector2, Began: number, Moved: boolean }
type Stroke = { X: number, Z: number, Moved: boolean }

local CELL = GameConfig.CellSize
local CELLS = GameConfig.PlotCells
local HALF = CELLS * CELL / 2

-- camera: a road-side overview of the plot
local PITCH = math.rad(55)
local FOV = 50
local ZOOM_DEFAULT, ZOOM_MIN, ZOOM_MAX = 60, 40, 80
local PAN_START_Z = -3 -- a little toward the road, so the tray hides less of the plot
local FLY_TIME = 0.6
local RETURN_TIME = 0.4
local FOLLOW = 14 -- camera smoothing per second
local PAN_SPEED = 36 -- studs per second (keys, right stick) at the default zoom
local ZOOM_SPEED = 40 -- studs per second (LT / RT)
local WHEEL_STEP = 6
local CURSOR_MARGIN = 14 -- gamepad: the camera follows a cursor further than this from its centre

-- ghost and plates
local GHOST_TRANSPARENCY = 0.5
local GHOST_LERP = 18
local SHAKE_TIME = 0.2
local SHAKE_SPEED = 70
local SHAKE_AMOUNT = 0.4
local OTHERS_FADE = 0.4
local MOVING_FADE = 0.75
local OK_COLOR = Color3.fromRGB(80, 220, 120)
local BAD_COLOR = Color3.fromRGB(235, 80, 70)
local WARN_COLOR = Color3.fromRGB(255, 210, 80)
local OUT_COLOR = Color3.fromRGB(255, 160, 40)
local CURSOR_COLOR = Color3.fromRGB(255, 255, 255)
local SELECT_COLOR = Color3.fromRGB(255, 214, 90)
local CHUTE_LIFT = 0.05 -- chute plates float a bit above the others (no flicker where they overlap)
local YARD_TEXT = "Turn the belt away from the yard"

-- input
local TAP_PIXELS = 12
local TAP_TIME = 0.3
local RIGHT_CLICK_PIXELS = 6
local OFF_PLOT_CELLS = 3 -- a pointer further off the plot than this doesn't move the cursor
local STICK_DEADZONE = 0.35
local STICK_DELAY = 0.25
local STICK_REPEAT = 0.12
local TRIGGER_DEADZONE = 0.15
local TRIGGER_MIN = 0.3 -- a pressed trigger zooms at least this fast (some pads report 0 on press)
local HOLD_TIME = 0.5 -- hold Y this long to pack up
local RAY_LENGTH = 400
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value

-- requests
local SEND_RATE = 6 -- requests per second (the server allows a little more)
local RESULT_TIMEOUT = 5 -- seconds before an unanswered request is forgotten
local DENY_REPEAT = 1.2 -- the same refusal toasts at most this often (belt painting)
local MAX_SEQ = 2 ^ 31 - 1
local RANGE_CHECK = 0.5

local ENTER_TEXT = "Go to your forge to build!"
local BUSY_TEXT = "Finish what you're doing first!"

local HINTS: { [string]: { [string]: string } } = {
	Mouse = {
		Idle = "Pick a machine below, or click one of yours   •   WASD: pan   •   Wheel: zoom   •   B: done",
		Placing = "Click: place   •   R: rotate   •   Right-click: cancel",
		PlacingBelt = "Click or drag: lay belts   •   R: rotate   •   Right-click: cancel",
		Selected = "M: move   •   X: pack up   •   Right-click: cancel",
		Moving = "Click: put it here   •   R: rotate   •   X: pack up   •   Right-click: cancel",
	},
	Gamepad = {
		Idle = "LB / RB: pick a machine   •   Left stick: move   •   B: done",
		Placing = "A: place   •   X: rotate   •   LB / RB: change   •   B: cancel",
		Selected = "A: move   •   Hold Y: pack up   •   B: back",
		Moving = "A: put it here   •   X: rotate   •   Hold Y: pack up   •   B: cancel",
	},
	Touch = {
		Idle = "Tap a machine below, or tap one of yours",
		Placing = "Tap where it goes, then PLACE",
		Moving = "Tap where it goes, then PLACE",
	},
}

local player = Players.LocalPlayer

local active = false
local mode: Mode = "Idle"
local kind: Kind = "Mouse"
local view: BuildView.Refs? = nil
local buildButton: TextButton? = nil
local pulse: Tween? = nil
local dirty = true

local plotId: number? = nil
local plotCF = CFrame.identity

local pickId: string? = nil -- machine being placed (Placing)
local selected: Model? = nil -- placed machine (Selected / Moving)
local rotation = 0
local cursorX, cursorZ = math.floor(CELLS / 2), math.floor(CELLS / 2)
-- mouse: the cursor stays put (an auto-advanced belt cell, a machine
-- picked up to move) while the mouse is still over this cell
local holdCell: Vector2? = nil
local painting: Stroke? = nil

local panX, panZ = 0, PAN_START_Z
local zoom = ZOOM_DEFAULT
local camCF: CFrame? = nil
local flyFrom: CFrame? = nil
local flyStart = 0
local savedCF: CFrame? = nil
local savedFov = 70
local savedBackpack: boolean? = nil
local savedHud: { [GuiObject]: boolean } = {}

local requests: { Request } = {}
local queue: { Request } = {}
local pumping = false
local tokens = SEND_RATE
local lastRefill = 0
local nextSeq = 1
local lastDeny = ""
local lastDenyAt = -math.huge

local connections: { RBXScriptConnection } = {}
local ghosts: { [string]: Model } = {}
local ghost: Model? = nil
local ghostCF: CFrame? = nil
local ghostTarget: CFrame? = nil
local ghostPivot: CFrame? = nil
local shakeUntil = 0
local ghostHighlight: Highlight? = nil
local selectHighlight: Highlight? = nil
local faded: { [BasePart]: boolean } = {}

local touches: { [InputObject]: Pointer } = {}
local pinch: { Distance: number, Zoom: number }? = nil
local rightDrag: Pointer? = nil
local stick1, stick2 = Vector2.zero, Vector2.zero
local triggerL, triggerR = 0, 0
local heldX, heldZ = 0, 0
local stickNext = 0
local yDown: number? = nil
local nextRangeCheck = 0

local function camera(): Camera
	return Workspace.CurrentCamera
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function myPlotId(): number?
	local id = player:GetAttribute("PlotId")
	return if type(id) == "number" and WorldLayout.Plots[id] then id else nil
end

-- Same test as the server's PlotService.isNear (horizontal distance).
local function isNearPlot(id: number): boolean
	local plot = WorldLayout.Plots[id]
	local root = rootPart()
	if not plot or not root then
		return false
	end
	local offset = root.Position - plot.Center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= GameConfig.BuildRange
end

local function kindOf(inputType: Enum.UserInputType): Kind?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
		or inputType.Name:sub(1, 11) == "MouseButton"
	then
		return "Mouse"
	end
	return nil
end

local function currentKind(): Kind
	local known: Kind? = kindOf(UserInputService:GetLastInputType())
	if known then
		return known
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		return "Gamepad"
	end
	return "Mouse"
end

local function onPlot(x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < CELLS and z < CELLS
end

local function info(id: any): MachineData.Machine?
	return if type(id) == "string" then MachineData.ById[id] else nil
end

---------------------------------------------------------------- layout (snapshot + our requests)

local function sameSpot(entry: Entry, spot: Entry): boolean
	return entry.Id == spot.Id and entry.X == spot.X and entry.Z == spot.Z and entry.R == spot.R
end

local function findSpot(entries: { Entry }, spot: Entry): number?
	for i, entry in entries do
		if sameSpot(entry, spot) then
			return i
		end
	end
	return nil
end

--[[
	The layout, inventory and slot limits the server will have once our
	requests land: the last State snapshot with every request that isn't in
	a snapshot yet applied on top (queued, in flight, or answered).
]]
local function layout(): ({ Entry }, { [string]: number }, Placement.Limits?)
	local state = StateController.get()
	local entries: { Entry } = {}
	local inventory: { [string]: number } = {}
	local limits: Placement.Limits? = nil
	if state then
		if type(state.Placed) == "table" then
			for _, e in state.Placed do
				if
					type(e) == "table"
					and type(e.Id) == "string"
					and type(e.X) == "number"
					and type(e.Z) == "number"
					and type(e.R) == "number"
				then
					table.insert(entries, { Id = e.Id, X = e.X, Z = e.Z, R = e.R })
				end
			end
		end
		if type(state.MachineInventory) == "table" then
			for id, count in state.MachineInventory do
				if type(id) == "string" and type(count) == "number" then
					inventory[id] = count
				end
			end
		end
		local build = state.Build
		if type(build) == "table" and type(build.MachineSlots) == "number" and type(build.ConveyorSlots) == "number" then
			limits = { Machines = build.MachineSlots, Conveyors = build.ConveyorSlots }
		end
	end
	for _, request in requests do
		if request.Op == "Place" then
			table.insert(entries, { Id = request.Id, X = request.X, Z = request.Z, R = request.R })
			inventory[request.Id] = (inventory[request.Id] or 0) - 1
		else
			local from = request.From
			local index = if from then findSpot(entries, from) else nil
			if index then
				if request.Op == "Move" then
					entries[index] = { Id = request.Id, X = request.X, Z = request.Z, R = request.R }
				else
					table.remove(entries, index)
					inventory[request.Id] = (inventory[request.Id] or 0) + 1
				end
			end
		end
	end
	return entries, inventory, limits
end

local function inventoryOf(id: string): number
	local _, inventory = layout()
	return inventory[id] or 0
end

local function pendingPickup(model: Model): boolean
	for _, request in requests do
		if request.Model == model and request.Op == "Pickup" then
			return true
		end
	end
	return false
end

-- Your placed machine models (the server tags them "Machine").
local function myMachines(includePacking: boolean?): { Model }
	local list: { Model } = {}
	for _, instance in CollectionService:GetTagged("Machine") do
		if instance:IsA("Model") and instance:GetAttribute("Owner") == player.UserId then
			if includePacking or not pendingPickup(instance) then
				table.insert(list, instance)
			end
		end
	end
	return list
end

-- Where a placed machine stands, as far as we know (a move we asked for
-- counts already).
local function spotOf(model: Model): Entry?
	local id, x, z, r =
		model:GetAttribute("MachineId"), model:GetAttribute("GridX"), model:GetAttribute("GridZ"), model:GetAttribute("Rotation")
	if type(id) ~= "string" or type(x) ~= "number" or type(z) ~= "number" or type(r) ~= "number" then
		return nil
	end
	local spot: Entry = { Id = id, X = x, Z = z, R = r }
	for _, request in requests do
		if request.Model == model and request.Op == "Move" then
			spot = { Id = request.Id, X = request.X, Z = request.Z, R = request.R }
		end
	end
	return spot
end

local function covers(spot: Entry, gx: number, gz: number): boolean
	if not info(spot.Id) then
		return false
	end
	local w, d = Grid.footprint(spot.Id, spot.R)
	return gx >= spot.X and gx < spot.X + w and gz >= spot.Z and gz < spot.Z + d
end

local function modelAtCell(gx: number, gz: number): Model?
	for _, model in myMachines() do
		local spot = spotOf(model)
		if spot and covers(spot, gx, gz) then
			return model
		end
	end
	return nil
end

---------------------------------------------------------------- screen to plot

local function footprintCFrame(id: string, x: number, z: number, r: number): CFrame
	return plotCF * Grid.localCFrame(id, x, z, r)
end

-- Plot surface point at the middle of a block of cells.
local function cellsCFrame(x: number, z: number, w: number, d: number): CFrame
	return plotCF * CFrame.new(-HALF + (x + w / 2) * CELL, 0, -HALF + (z + d / 2) * CELL)
end

-- Plot-local point where a screen ray meets the plot surface.
local function groundAt(screen: Vector2): Vector3?
	local ray = camera():ViewportPointToRay(screen.X, screen.Y)
	local origin = plotCF:PointToObjectSpace(ray.Origin)
	local direction = plotCF:VectorToObjectSpace(ray.Direction)
	if direction.Y > -1e-3 then
		return nil
	end
	return origin + direction * (-origin.Y / direction.Y)
end

-- Grid cell under a screen point (raw: may be off the plot).
local function rawCellAt(screen: Vector2): (number?, number?)
	local p = groundAt(screen)
	if not p then
		return nil, nil
	end
	return math.floor((p.X + HALF) / CELL), math.floor((p.Z + HALF) / CELL)
end

-- Cursor cell for a screen point: clamped onto the plot, nil far off it.
local function cursorCellAt(screen: Vector2): (number?, number?)
	local gx, gz = rawCellAt(screen)
	if not gx or not gz then
		return nil, nil
	end
	if gx < -OFF_PLOT_CELLS or gz < -OFF_PLOT_CELLS or gx >= CELLS + OFF_PLOT_CELLS or gz >= CELLS + OFF_PLOT_CELLS then
		return nil, nil
	end
	return math.clamp(gx, 0, CELLS - 1), math.clamp(gz, 0, CELLS - 1)
end

-- One of your machines under a screen point: its parts first, then the
-- cell under the pointer (belts are low and easy to miss).
local function machineUnder(screen: Vector2): Model?
	local mine = myMachines()
	if #mine == 0 then
		return nil
	end
	local filter: { Instance } = {}
	for _, model in mine do
		table.insert(filter, model)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = filter
	local ray = camera():ViewportPointToRay(screen.X, screen.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	local node: Instance? = if hit then hit.Instance else nil
	while node do
		if node:IsA("Model") and table.find(mine, node :: Model) then
			return node :: Model
		end
		node = node.Parent
	end
	local gx, gz = rawCellAt(screen)
	if gx and gz and onPlot(gx, gz) then
		return modelAtCell(gx, gz)
	end
	return nil
end

-- Touch positions leave out the top bar; viewport rays need it.
local function touchPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
end

---------------------------------------------------------------- camera

local function cameraGoal(): CFrame
	local focus = plotCF:PointToWorldSpace(Vector3.new(panX, 0, panZ))
	local back = plotCF:VectorToWorldSpace(Vector3.new(0, math.sin(PITCH), -math.cos(PITCH)))
	return CFrame.lookAt(focus + back * zoom, focus)
end

-- Plot-local ground directions of the screen's right and up.
local function screenAxes(): (Vector3, Vector3)
	local goal = cameraGoal()
	local right = plotCF:VectorToObjectSpace(goal.RightVector)
	local look = plotCF:VectorToObjectSpace(goal.LookVector)
	local flatRight = Vector3.new(right.X, 0, right.Z)
	local flatLook = Vector3.new(look.X, 0, look.Z)
	return if flatRight.Magnitude > 1e-3 then flatRight.Unit else Vector3.new(-1, 0, 0),
		if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.new(0, 0, 1)
end

local function panBy(dx: number, dz: number)
	panX = math.clamp(panX + dx, -HALF, HALF)
	panZ = math.clamp(panZ + dz, -HALF, HALF)
end

-- Dragging the ground (finger or right mouse button) moves it with the pointer.
local function dragPan(delta: Vector2)
	local height = math.max(camera().ViewportSize.Y, 1)
	local studsPerPixel = 2 * zoom * math.tan(math.rad(FOV) / 2) / height
	local right, forward = screenAxes()
	local move = right * (-delta.X * studsPerPixel) + forward * (delta.Y * studsPerPixel / math.sin(PITCH))
	panBy(move.X, move.Z)
end

local function zoomBy(amount: number)
	zoom = math.clamp(zoom + amount, ZOOM_MIN, ZOOM_MAX)
end

-- Gamepad: keep the cursor cell near the middle of the view.
local function followCursor()
	local cx = -HALF + (cursorX + 0.5) * CELL
	local cz = -HALF + (cursorZ + 0.5) * CELL
	panX = math.clamp(math.clamp(panX, cx - CURSOR_MARGIN, cx + CURSOR_MARGIN), -HALF, HALF)
	panZ = math.clamp(math.clamp(panZ, cz - CURSOR_MARGIN, cz + CURSOR_MARGIN), -HALF, HALF)
end

local function updateCamera(dt: number)
	local cam = camera()
	local goal = cameraGoal()
	local from = flyFrom
	local cf: CFrame
	if from then
		local t = (os.clock() - flyStart) / FLY_TIME
		if t < 1 then
			local a = 1 - (1 - t) ^ 3
			cf = from:Lerp(goal, a)
			cam.FieldOfView = savedFov + (FOV - savedFov) * a
		else
			flyFrom = nil
			cf = goal
			cam.FieldOfView = FOV
		end
	else
		cf = (camCF or goal):Lerp(goal, 1 - math.exp(-FOLLOW * dt))
	end
	camCF = cf
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	cam.CFrame = cf
	-- shift lock would pin the mouse to the middle of the screen
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

---------------------------------------------------------------- ghost, plates, fading

local function newHighlight(name: string, color: Color3, fill: number): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = fill
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = GridOverlay.folder()
	return highlight
end

-- A see-through copy of a machine (built once per machine type).
local function ghostFor(id: string): Model
	local cached = ghosts[id]
	if cached then
		return cached
	end
	local model = MachineBuilder.build(id)
	model.Name = "Ghost_" .. id
	model:SetAttribute("MachineId", nil)
	model:SetAttribute("Ghost", true)
	for _, d in model:GetDescendants() do
		for _, tag in d:GetTags() do
			d:RemoveTag(tag) -- client effects must not mistake it for a real belt or machine
		end
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, GHOST_TRANSPARENCY)
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") then
			local effect: any = d
			effect.Enabled = false
		elseif d:IsA("LayerCollector") then
			d.Enabled = false
		end
	end
	ghosts[id] = model
	return model
end

local function showGhost(id: string?)
	local wanted = if id then ghostFor(id) else nil
	if ghost == wanted then
		return
	end
	local old = ghost
	if old then
		old.Parent = nil
	end
	ghost = wanted
	ghostCF = nil
	ghostPivot = nil
	local highlight = ghostHighlight
	if wanted then
		wanted.Parent = GridOverlay.folder()
	end
	if highlight then
		highlight.Adornee = wanted
	end
end

local function updateGhost(dt: number)
	local model, target = ghost, ghostTarget
	if not model or not target then
		return
	end
	local cf: CFrame = target
	local last = ghostCF
	if last then
		cf = last:Lerp(target, 1 - math.exp(-GHOST_LERP * dt))
		if (cf.Position - target.Position).Magnitude < 0.01 and cf.LookVector:Dot(target.LookVector) > 0.9999 then
			cf = target
		end
	end
	ghostCF = cf
	local shown: CFrame = cf
	local now = os.clock()
	if now < shakeUntil then
		local strength = (shakeUntil - now) / SHAKE_TIME
		shown = cf * CFrame.new(math.sin(now * SHAKE_SPEED) * SHAKE_AMOUNT * strength, 0, 0)
	end
	if shown ~= ghostPivot then
		ghostPivot = shown
		model:PivotTo(shown)
	end
end

-- While a ghost shows, your other machines turn see-through (the one
-- being moved even more).
local function fadeModel(model: Model)
	local amount = if mode == "Moving" and model == selected then MOVING_FADE else OTHERS_FADE
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = amount
			faded[d] = true
		end
	end
end

local function setFaded(on: boolean)
	for part in faded do
		part.LocalTransparencyModifier = 0
	end
	table.clear(faded)
	if not on then
		return
	end
	for _, model in myMachines(true) do
		fadeModel(model)
	end
end

local function showOutput(name: string, id: string, x: number, z: number, r: number)
	local ox, oz = Grid.outputCell(id, x, z, r)
	if ox and oz then
		GridOverlay.plate(name, cellsCFrame(ox, oz, 1, 1), CELL, CELL, OUT_COLOR)
	else
		GridOverlay.hidePlate(name)
	end
end

---------------------------------------------------------------- checks

-- Yellow notes for a spot that is allowed but probably not what you want.
local function warningFor(entries: { Entry }, id: string, x: number, z: number, r: number, ignore: Entry?): string?
	local me: Entry = { Id = id, X = x, Z = z, R = r }
	local others: { Entry } = {}
	for _, entry in entries do
		if entry ~= ignore and info(entry.Id) then
			table.insert(others, entry)
		end
	end
	local occupied = Placement.occupancy(others)
	local myInfo = MachineData.ById[id]
	-- my results go into a machine side that takes nothing
	local ox, oz = Grid.outputCell(id, x, z, r)
	if ox and oz and onPlot(ox, oz) then
		local target = occupied[Grid.key(ox, oz)]
		local targetInfo = target and MachineData.ById[target.Id]
		if target and targetInfo and not targetInfo.IsConveyor then
			local dx, dz = Grid.dir(r)
			if not ConveyorLogic.faceAllowed(target, ox - dx, oz - dz) then
				return "Output blocked"
			end
		end
	end
	for _, other in others do
		local otherInfo = MachineData.ById[other.Id]
		if otherInfo.IsConveyor then
			-- a belt that runs into a side of mine that takes nothing
			local dx, dz = Grid.dir(other.R)
			local fx, fz = other.X + dx, other.Z + dz
			if not myInfo.IsConveyor and covers(me, fx, fz) and not ConveyorLogic.faceAllowed(me, other.X, other.Z) then
				return "A belt runs into a side that takes nothing"
			end
		else
			-- another machine's results would land on a side of mine that takes nothing
			local px, pz = Grid.outputCell(other.Id, other.X, other.Z, other.R)
			if px and pz and not myInfo.IsConveyor and covers(me, px, pz) then
				local dx, dz = Grid.dir(other.R)
				if not ConveyorLogic.faceAllowed(me, px - dx, pz - dz) then
					return `Blocks the {otherInfo.Name}'s output`
				end
			end
		end
	end
	if myInfo.IsConveyor then
		-- a Source chute's belt must not run off the grid (its item would fall into the yard)
		local chute = BaseLayout.chuteAt(x, z)
		if chute and BaseLayout.Chutes[chute].Kind == "Source" and not BaseLayout.sourceFeeds(r) then
			return YARD_TEXT
		end
		local test = table.clone(others)
		table.insert(test, me)
		for _, pair in ConveyorLogic.headOn(test) do
			if pair[1] == me or pair[2] == me then
				return "Belts face each other"
			end
		end
		local dx, dz = Grid.dir(r)
		local fx, fz = x + dx, z + dz
		local front = if onPlot(fx, fz) then occupied[Grid.key(fx, fz)] else nil
		local frontInfo = front and MachineData.ById[front.Id]
		if front and frontInfo and not frontInfo.IsConveyor and not ConveyorLogic.faceAllowed(front, x, z) then
			return "That side takes nothing"
		end
	end
	return nil
end

--[[
	Can `id` go at (x, z, r) right now? Same rules as the server
	(Placement.validate) on our layout. `ignore` is the spot of a machine
	being moved (moves never fail on slots or inventory).
	Returns (ok, reason code, warning text).
]]
local function check(id: string, x: number, z: number, r: number, ignore: Entry?): (boolean, string?, string?)
	local entries, inventory, limits = layout()
	local ignoreEntry: Entry? = nil
	if ignore then
		local index = findSpot(entries, ignore)
		ignoreEntry = if index then entries[index] else nil
	elseif (inventory[id] or 0) < 1 then
		return false, "NoneOwned", nil
	end
	local ok, code = Placement.validate(entries, id, x, z, r, if ignore then nil else limits, ignoreEntry)
	if not ok then
		return false, code, nil
	end
	return true, nil, warningFor(entries, id, x, z, r, ignoreEntry)
end

---------------------------------------------------------------- visuals

local function hintFor(): string?
	local hints = HINTS[kind]
	if not hints then
		return nil
	end
	if mode == "Placing" then
		local placing = info(pickId)
		if placing and placing.IsConveyor and hints.PlacingBelt then
			return hints.PlacingBelt
		end
	end
	return hints[mode]
end

local function refreshUI()
	local refs = view
	if not refs or not active then
		return
	end
	local entries, inventory, limits = layout()
	BuildView.setInventory(refs, inventory, if mode == "Placing" then pickId else nil, function(id: string)
		PlacementController.pick(id)
	end)
	local machines, conveyors = Placement.counts(entries)
	BuildView.setCounts(refs, machines, if limits then limits.Machines else 0, conveyors, if limits then limits.Conveyors else 0)
	BuildView.setMode(refs, mode, kind == "Touch")
	BuildView.setHint(refs, hintFor())
end

-- The chute under a cell (plot grid), if any.
local function chuteInfo(gx: number, gz: number): BaseLayout.Chute?
	local name = BaseLayout.chuteAt(gx, gz)
	return if name then BaseLayout.Chutes[name] else nil
end

-- The chute cells: their plates and labels (red while a Source's belt faces the yard).
local function updateChutes(entries: { Entry })
	local occupied = Placement.occupancy(entries)
	for _, name in BaseLayout.ChuteNames do
		local chute = BaseLayout.Chutes[name]
		local plateName = "Chute" .. name
		GridOverlay.plate(plateName, cellsCFrame(chute.X, chute.Z, 1, 1) * CFrame.new(0, CHUTE_LIFT, 0), CELL, CELL, chute.Color)
		local belt = occupied[Grid.key(chute.X, chute.Z)]
		local beltInfo = belt and info(belt.Id)
		local yard = chute.Kind == "Source"
			and belt ~= nil
			and beltInfo ~= nil
			and beltInfo.IsConveyor == true
			and not BaseLayout.sourceFeeds(belt.R)
		GridOverlay.tag(plateName, if yard then `{chute.Label}: TURN THE BELT` else chute.Label, if yard then BAD_COLOR else chute.Color)
	end
end

-- Ghost, plates, highlight colours and the reason line for the current
-- mode, cursor and layout. Runs only after something changed.
local function updateVisuals()
	local refs = view
	if not active or not refs then
		return
	end
	updateChutes((layout()))
	local id: string? = nil
	local ignore: Entry? = nil
	if mode == "Placing" then
		id = pickId
	elseif mode == "Moving" and selected then
		local spot = spotOf(selected)
		if spot then
			id = spot.Id
			ignore = spot
		end
	end
	if id and info(id) then
		showGhost(id)
		local x, z = Placement.clampOrigin(id, cursorX, cursorZ, rotation)
		local ok, code, warning = check(id, x, z, rotation, ignore)
		ghostTarget = footprintCFrame(id, x, z, rotation)
		local w, d = Grid.footprint(id, rotation)
		local color = if not ok then BAD_COLOR elseif warning then WARN_COLOR else OK_COLOR
		GridOverlay.plate("Footprint", cellsCFrame(x, z, w, d), w * CELL, d * CELL, color)
		showOutput("Out", id, x, z, rotation)
		GridOverlay.hidePlate("Cursor")
		GridOverlay.hidePlate("Selected")
		GridOverlay.hidePlate("SelectedOut")
		local highlight = ghostHighlight
		if highlight then
			highlight.FillColor = if ok then OK_COLOR else BAD_COLOR
			highlight.OutlineColor = if ok then OK_COLOR else BAD_COLOR
		end
		local chute = chuteInfo(cursorX, cursorZ)
		if not ok then
			BuildView.setReason(refs, Placement.Reasons[code or "Invalid"] or Placement.Reasons.Invalid, "Bad")
		elseif warning then
			BuildView.setReason(refs, warning, "Warn")
		elseif chute then
			BuildView.setReason(refs, chute.Hint, "Info")
		else
			BuildView.setReason(refs, nil)
		end
		return
	end
	showGhost(nil)
	ghostTarget = nil
	GridOverlay.hidePlate("Footprint")
	GridOverlay.hidePlate("Out")
	GridOverlay.plate("Cursor", cellsCFrame(cursorX, cursorZ, 1, 1), CELL, CELL, CURSOR_COLOR)
	local model = selected
	local spot = if mode == "Selected" and model then spotOf(model) else nil
	local spotInfo = spot and info(spot.Id)
	if model and spot and spotInfo then
		local w, d = Grid.footprint(spot.Id, spot.R)
		GridOverlay.plate("Selected", cellsCFrame(spot.X, spot.Z, w, d), w * CELL, d * CELL, SELECT_COLOR)
		showOutput("SelectedOut", spot.Id, spot.X, spot.Z, spot.R)
		if model:GetAttribute("Busy") == true then
			BuildView.setReason(refs, `{spotInfo.Name}: {Placement.Reasons.Busy}`, "Warn")
		else
			BuildView.setReason(refs, spotInfo.Name, "Info")
		end
	else
		GridOverlay.hidePlate("Selected")
		GridOverlay.hidePlate("SelectedOut")
		local chute = chuteInfo(cursorX, cursorZ)
		BuildView.setReason(refs, if chute then `{chute.Label} chute: {chute.Hint}` else nil, "Info")
	end
end

local function shake()
	shakeUntil = os.clock() + SHAKE_TIME
end

-- A refusal: shake the ghost and say why (the same text at most every DENY_REPEAT).
local function deny(code: string?)
	shake()
	local text = Placement.Reasons[code or "Invalid"] or Placement.Reasons.Invalid
	local now = os.clock()
	if text ~= lastDeny or now - lastDenyAt > DENY_REPEAT then
		lastDeny, lastDenyAt = text, now
		HudController.toast(text, "Deny")
	else
		Sfx.play("UIDeny")
	end
end

---------------------------------------------------------------- requests

local function send(request: Request)
	request.Sent = true
	request.At = os.clock()
	if request.Op == "Place" then
		Net.send("BuildPlace", request.Seq, request.Id, request.X, request.Z, request.R)
	elseif request.Op == "Move" then
		Net.send("BuildMove", request.Seq, request.Model, request.X, request.Z, request.R)
	else
		Net.send("BuildPickup", request.Seq, request.Model)
	end
end

-- Sends queued requests, at most SEND_RATE a second (bursts of SEND_RATE).
local function pump()
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		while #queue > 0 do
			local now = os.clock()
			tokens = math.min(SEND_RATE, tokens + (now - lastRefill) * SEND_RATE)
			lastRefill = now
			if tokens >= 1 then
				tokens -= 1
				send(table.remove(queue, 1) :: Request)
			else
				task.wait((1 - tokens) / SEND_RATE)
			end
		end
		pumping = false
	end)
end

local function request(op: Op, id: string, x: number, z: number, r: number, from: Entry?, model: Model?)
	local seq = nextSeq
	nextSeq = if nextSeq >= MAX_SEQ then 1 else nextSeq + 1
	local entry: Request = {
		Seq = seq,
		Op = op,
		Id = id,
		X = x,
		Z = z,
		R = r,
		From = from,
		Model = model,
		Sent = false,
		Done = false,
		At = os.clock(),
	}
	table.insert(requests, entry)
	table.insert(queue, entry)
	dirty = true
	pump()
end

local function effectPosition(id: string, x: number, z: number, r: number): Vector3
	return footprintCFrame(id, x, z, r).Position + Vector3.new(0, 1, 0)
end

local function onResult(result: any)
	if type(result) ~= "table" or type(result.Seq) ~= "number" then
		return
	end
	local index: number? = nil
	for i, entry in requests do
		if entry.Seq == result.Seq then
			index = i
			break
		end
	end
	if not index then
		return
	end
	local entry = requests[index]
	if result.Ok == true then
		entry.Done = true
		entry.At = os.clock()
		if info(entry.Id) then
			local position = effectPosition(entry.Id, entry.X, entry.Z, entry.R)
			if entry.Op == "Pickup" then
				Sfx.play("Place", position, 1.35)
				Vfx.burst("Dust", position, 8)
			else
				Sfx.play("Place", position)
				Vfx.burst("Dust", position, 10)
			end
		end
	else
		table.remove(requests, index)
		if active then
			deny(if type(result.Reason) == "string" then result.Reason else nil)
		end
	end
	dirty = true
	refreshUI()
end

-- Requests the server answered are in this snapshot now.
local function onState(_: { [string]: any })
	for i = #requests, 1, -1 do
		if requests[i].Done then
			table.remove(requests, i)
		end
	end
	dirty = true
	refreshUI()
	PlacementController.refreshButton()
end

local function expireRequests(now: number)
	local changed = false
	for i = #requests, 1, -1 do
		local entry = requests[i]
		if entry.Sent and now - entry.At > RESULT_TIMEOUT then
			table.remove(requests, i)
			changed = true
		end
	end
	if changed then
		dirty = true
		refreshUI()
	end
end

---------------------------------------------------------------- actions

local function setMode(newMode: Mode)
	mode = newMode
	if newMode ~= "Placing" then
		pickId = nil
	end
	if newMode == "Idle" then
		selected = nil
	end
	painting = nil
	yDown = nil
	local highlight = selectHighlight
	if highlight then
		highlight.Adornee = if newMode == "Selected" then selected else nil
	end
	setFaded(newMode == "Placing" or newMode == "Moving")
	dirty = true
	refreshUI()
end

local function selectModel(model: Model)
	selected = model
	setMode("Selected")
end

local function setCursor(gx: number, gz: number)
	if gx ~= cursorX or gz ~= cursorZ then
		cursorX, cursorZ = gx, gz
		dirty = true
	end
end

-- Mouse: keep the cursor where we just put it until the mouse leaves the
-- cell it is over now (so clicking again without moving continues a belt line).
local function holdMouseCell()
	local gx, gz = cursorCellAt(UserInputService:GetMouseLocation())
	holdCell = if gx and gz then Vector2.new(gx, gz) else nil
end

-- Gamepad: the machine under the cursor is the selection.
local function hoverSelect()
	if mode ~= "Idle" and mode ~= "Selected" then
		return
	end
	local model = modelAtCell(cursorX, cursorZ)
	if model then
		if model ~= selected or mode ~= "Selected" then
			selectModel(model)
		end
	elseif mode ~= "Idle" then
		setMode("Idle")
	end
end

local function moveCursor(dx: number, dz: number)
	setCursor(math.clamp(cursorX + dx, 0, CELLS - 1), math.clamp(cursorZ + dz, 0, CELLS - 1))
	followCursor()
	hoverSelect()
end

-- After a belt: the cursor steps one cell the way it points.
local function advance(x: number, z: number, r: number)
	local dx, dz = Grid.dir(r)
	local nx, nz = x + dx, z + dz
	if not onPlot(nx, nz) then
		return
	end
	setCursor(nx, nz)
	if kind == "Mouse" then
		holdMouseCell()
	elseif kind == "Gamepad" then
		followCursor()
	end
end

local function rotationOf(dx: number, dz: number): number
	if dx > 0 then
		return 1
	elseif dx < 0 then
		return 3
	elseif dz > 0 then
		return 2
	end
	return 0
end

-- Asks for a placement if our layout allows it. `quiet` only shakes the
-- ghost on refusal (belt painting over occupied cells).
local function tryPlace(id: string, x: number, z: number, r: number, quiet: boolean): (boolean, string?)
	local ok, code = check(id, x, z, r, nil)
	if not ok then
		if quiet then
			shake()
		else
			deny(code)
		end
		return false, code
	end
	request("Place", id, x, z, r, nil, nil)
	return true, nil
end

-- Out of this machine, or of slots for it? Back to idle.
local function afterPlace(id: string)
	local entries, inventory, limits = layout()
	local placing = info(id)
	local full = false
	if limits and placing then
		local machines, conveyors = Placement.counts(entries)
		if placing.IsConveyor then
			full = conveyors >= limits.Conveyors
		elseif not placing.SlotFree then
			full = machines >= limits.Machines
		end
	end
	if full or (inventory[id] or 0) < 1 then
		setMode("Idle")
	end
end

local function startMove()
	local model = selected
	if mode ~= "Selected" or not model then
		return
	end
	local spot = spotOf(model)
	if not spot or not info(spot.Id) then
		return
	end
	if model:GetAttribute("Busy") == true then
		deny("Busy")
		return
	end
	rotation = spot.R
	local w, d = Grid.footprint(spot.Id, spot.R)
	setCursor(spot.X + math.floor((w - 1) / 2), spot.Z + math.floor((d - 1) / 2))
	if kind == "Mouse" then
		holdMouseCell()
	end
	Sfx.play("UIClick")
	setMode("Moving")
end

local function packUp()
	local model = selected
	if (mode ~= "Selected" and mode ~= "Moving") or not model then
		return
	end
	local spot = spotOf(model)
	if not spot or not info(spot.Id) then
		return
	end
	if model:GetAttribute("Busy") == true then
		deny("Busy")
		return
	end
	request("Pickup", spot.Id, spot.X, spot.Z, spot.R, spot, model)
	setMode("Idle")
end

-- Place / put down / pick up for moving, depending on the mode.
local function commit()
	if mode == "Placing" then
		local id = pickId
		local placing = info(id)
		if not id or not placing then
			return
		end
		local x, z = Placement.clampOrigin(id, cursorX, cursorZ, rotation)
		if not tryPlace(id, x, z, rotation, false) then
			return
		end
		if placing.IsConveyor then
			advance(x, z, rotation)
			afterPlace(id)
		else
			setMode("Idle")
		end
	elseif mode == "Moving" then
		local model = selected
		local spot = if model then spotOf(model) else nil
		if not model or not spot or not info(spot.Id) then
			setMode("Idle")
			return
		end
		local x, z = Placement.clampOrigin(spot.Id, cursorX, cursorZ, rotation)
		if x == spot.X and z == spot.Z and rotation == spot.R then
			setMode("Selected")
			return
		end
		if model:GetAttribute("Busy") == true then
			deny("Busy")
			return
		end
		local ok, code = check(spot.Id, x, z, rotation, spot)
		if not ok then
			deny(code)
			return
		end
		request("Move", spot.Id, x, z, rotation, spot, model)
		setMode("Selected")
	elseif mode == "Selected" then
		startMove()
	end
end

local function rotate()
	if mode ~= "Placing" and mode ~= "Moving" then
		return
	end
	rotation = (rotation + 1) % 4
	Sfx.play("BuildRotate")
	dirty = true
end

-- Steps back one level. False when there was nothing to cancel.
local function cancel(): boolean
	if mode == "Moving" then
		setMode("Selected")
		return true
	elseif mode == "Placing" or mode == "Selected" then
		setMode("Idle")
		return true
	end
	return false
end

-- Picks a machine from the tray (again on the same card: put it away).
function PlacementController.pick(id: string)
	if not active or not info(id) or inventoryOf(id) < 1 then
		return
	end
	Sfx.play("UIClick")
	if mode == "Placing" and pickId == id then
		setMode("Idle")
		return
	end
	pickId = id
	setMode("Placing")
end

-- LB / RB: the previous or next machine in the tray.
local function cycleTray(step: number)
	local _, inventory = layout()
	local ids: { string } = {}
	local ordered = table.clone(MachineData.List)
	table.sort(ordered, function(a, b)
		return a.Order < b.Order
	end)
	for _, machine in ordered do
		if (inventory[machine.Id] or 0) > 0 then
			table.insert(ids, machine.Id)
		end
	end
	if #ids == 0 then
		return
	end
	local current = if mode == "Placing" and pickId then table.find(ids, pickId) else nil
	local index = if current then (current - 1 + step) % #ids + 1 elseif step > 0 then 1 else #ids
	pickId = ids[index]
	Sfx.play("UIClick")
	setMode("Placing")
end

---------------------------------------------------------------- belt painting (mouse)

local function paintTo(gx: number, gz: number)
	local stroke = painting
	local id = pickId
	if not stroke or mode ~= "Placing" or not id then
		painting = nil
		return
	end
	while stroke.X ~= gx or stroke.Z ~= gz do
		local dx = if gx > stroke.X then 1 elseif gx < stroke.X then -1 else 0
		local dz = if dx ~= 0 then 0 elseif gz > stroke.Z then 1 else -1
		rotation = rotationOf(dx, dz)
		local _, code = tryPlace(id, stroke.X, stroke.Z, rotation, true)
		if code == "NoneOwned" or code == "NoConveyorSlots" then
			deny(code)
			painting = nil
			setMode("Idle")
			return
		end
		stroke.X += dx
		stroke.Z += dz
		stroke.Moved = true
	end
	dirty = true
end

local function paintEnd()
	local stroke = painting
	painting = nil
	local id = pickId
	if not stroke or mode ~= "Placing" or not id then
		return
	end
	local ok = tryPlace(id, stroke.X, stroke.Z, rotation, stroke.Moved)
	if ok then
		advance(stroke.X, stroke.Z, rotation)
	end
	afterPlace(id)
end

---------------------------------------------------------------- pointer input

local function onPrimaryDown(position: Vector2)
	if (mode == "Placing" or mode == "Moving") and not holdCell and not cursorCellAt(position) then
		return -- clicked well off the plot: the cursor there is stale
	end
	if mode == "Placing" then
		local placing = info(pickId)
		if placing and placing.IsConveyor then
			painting = { X = cursorX, Z = cursorZ, Moved = false }
		else
			commit()
		end
	elseif mode == "Moving" then
		commit()
	else
		local model = machineUnder(position)
		if model then
			selectModel(model)
		elseif mode ~= "Idle" then
			setMode("Idle")
		end
	end
end

local function tap(position: Vector2)
	local gx, gz = cursorCellAt(position)
	if mode == "Placing" or mode == "Moving" then
		if gx and gz then
			setCursor(gx, gz)
		end
		return
	end
	local model = machineUnder(position)
	if model then
		selectModel(model)
		return
	end
	if mode ~= "Idle" then
		setMode("Idle")
	end
	if gx and gz then
		setCursor(gx, gz)
	end
end

local function touchCount(): number
	local n = 0
	for _ in touches do
		n += 1
	end
	return n
end

local function twoTouches(): (Pointer?, Pointer?)
	local a, b = nil, nil
	for _, pointer in touches do
		if not a then
			a = pointer
		elseif not b then
			b = pointer
		end
	end
	return a, b
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 then
		onPrimaryDown(UserInputService:GetMouseLocation())
	elseif inputType == Enum.UserInputType.MouseButton2 then
		local position = UserInputService:GetMouseLocation()
		rightDrag = { Start = position, Last = position, Began = os.clock(), Moved = false }
	elseif inputType == Enum.UserInputType.Touch then
		local position = touchPosition(input)
		touches[input] = { Start = position, Last = position, Began = os.clock(), Moved = false }
		if touchCount() == 2 then
			local a, b = twoTouches()
			if a and b then
				pinch = { Distance = math.max((a.Last - b.Last).Magnitude, 1), Zoom = zoom }
				a.Moved, b.Moved = true, true -- a pinch is never a tap
			end
		end
	end
end

local function onInputChanged(input: InputObject, processed: boolean)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseMovement then
		local drag = rightDrag
		if drag then
			local position = UserInputService:GetMouseLocation()
			local delta = position - drag.Last
			drag.Last = position
			if (position - drag.Start).Magnitude > RIGHT_CLICK_PIXELS then
				drag.Moved = true
			end
			if drag.Moved then
				dragPan(delta)
			end
		end
	elseif inputType == Enum.UserInputType.MouseWheel then
		if not processed then
			zoomBy(-input.Position.Z * WHEEL_STEP)
		end
	elseif inputType == Enum.UserInputType.Touch then
		local pointer = touches[input]
		if not pointer then
			return
		end
		local position = touchPosition(input)
		local delta = position - pointer.Last
		pointer.Last = position
		if (position - pointer.Start).Magnitude > TAP_PIXELS then
			pointer.Moved = true
		end
		local current = pinch
		if current then
			local a, b = twoTouches()
			if a and b then
				local distance = math.max((a.Last - b.Last).Magnitude, 1)
				zoom = math.clamp(current.Zoom * current.Distance / distance, ZOOM_MIN, ZOOM_MAX)
			end
		elseif pointer.Moved then
			dragPan(delta)
		end
	end
end

local function onInputEnded(input: InputObject, _: boolean)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 then
		if painting then
			paintEnd()
		end
	elseif inputType == Enum.UserInputType.MouseButton2 then
		local drag = rightDrag
		rightDrag = nil
		if drag and not drag.Moved and os.clock() - drag.Began <= TAP_TIME * 2 then
			cancel()
		end
	elseif inputType == Enum.UserInputType.Touch then
		local pointer = touches[input]
		if not pointer then
			return
		end
		touches[input] = nil
		if pinch and touchCount() < 2 then
			pinch = nil
		end
		if not pointer.Moved and os.clock() - pointer.Began <= TAP_TIME then
			tap(pointer.Last)
		end
	end
end

local function updateMouseCursor()
	local gx, gz = cursorCellAt(UserInputService:GetMouseLocation())
	local hold = holdCell
	if hold then
		if gx == hold.X and gz == hold.Y then
			return
		end
		holdCell = nil
	end
	if gx and gz then
		setCursor(gx, gz)
		if painting then
			paintTo(gx, gz)
		end
	end
end

-- Left stick: one cell per push, repeating while held.
local function updateStickCursor(now: number)
	local dx, dz = 0, 0
	if stick1.Magnitude >= STICK_DEADZONE then
		local right, forward = screenAxes()
		local move = right * stick1.X + forward * stick1.Y
		if math.abs(move.X) >= math.abs(move.Z) then
			dx = if move.X > 0 then 1 else -1
		else
			dz = if move.Z > 0 then 1 else -1
		end
	end
	if dx == 0 and dz == 0 then
		heldX, heldZ = 0, 0
		return
	end
	if dx ~= heldX or dz ~= heldZ then
		heldX, heldZ = dx, dz
		stickNext = now + STICK_DELAY
		moveCursor(dx, dz)
	elseif now >= stickNext then
		stickNext = now + STICK_REPEAT
		moveCursor(dx, dz)
	end
end

---------------------------------------------------------------- action bindings

local function onPad(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local key = input.KeyCode
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	if key == Enum.KeyCode.Thumbstick1 then
		stick1 = if ended then Vector2.zero else Vector2.new(input.Position.X, input.Position.Y)
	elseif key == Enum.KeyCode.Thumbstick2 then
		stick2 = if ended then Vector2.zero else Vector2.new(input.Position.X, input.Position.Y)
	elseif key == Enum.KeyCode.ButtonL2 then
		triggerL = if ended then 0 else math.clamp(input.Position.Z, TRIGGER_MIN, 1)
	elseif key == Enum.KeyCode.ButtonR2 then
		triggerR = if ended then 0 else math.clamp(input.Position.Z, TRIGGER_MIN, 1)
	elseif state == Enum.UserInputState.Begin then
		if key == Enum.KeyCode.ButtonA then
			commit()
		elseif key == Enum.KeyCode.ButtonX then
			rotate()
		elseif key == Enum.KeyCode.ButtonY then
			if mode == "Selected" or mode == "Moving" then
				yDown = os.clock()
			end
		elseif key == Enum.KeyCode.ButtonB then
			if not cancel() then
				PlacementController.exit()
			end
		elseif key == Enum.KeyCode.ButtonL1 then
			cycleTray(-1)
		elseif key == Enum.KeyCode.ButtonR1 then
			cycleTray(1)
		end
	elseif ended and key == Enum.KeyCode.ButtonY then
		-- a short press on a selected machine picks it up to move it
		if yDown and mode == "Selected" then
			startMove()
		end
		yDown = nil
	end
	return Enum.ContextActionResult.Sink
end

local function onKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.R then
		rotate()
	elseif key == Enum.KeyCode.M then
		startMove()
	elseif key == Enum.KeyCode.X or key == Enum.KeyCode.Delete then
		packUp()
	elseif key == Enum.KeyCode.C then
		cancel()
	end
	return Enum.ContextActionResult.Sink
end

-- B / D-pad Up, bound all the time: open or close build mode.
local function onToggle(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if active then
		PlacementController.exit()
		return Enum.ContextActionResult.Sink
	end
	if CleaningController.isActive() then
		return Enum.ContextActionResult.Pass
	end
	task.spawn(PlacementController.enter)
	return Enum.ContextActionResult.Sink
end

---------------------------------------------------------------- frame

local function keyAxis(positive: { Enum.KeyCode }, negative: { Enum.KeyCode }): number
	if UserInputService:GetFocusedTextBox() then
		return 0 -- typing in the chat
	end
	local value = 0
	for _, key in positive do
		if UserInputService:IsKeyDown(key) then
			value += 1
			break
		end
	end
	for _, key in negative do
		if UserInputService:IsKeyDown(key) then
			value -= 1
			break
		end
	end
	return value
end

local UP_KEYS = { Enum.KeyCode.W, Enum.KeyCode.Up }
local DOWN_KEYS = { Enum.KeyCode.S, Enum.KeyCode.Down }
local RIGHT_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }
local LEFT_KEYS = { Enum.KeyCode.A, Enum.KeyCode.Left }

local function checkStillHere()
	local id = plotId
	if not id or myPlotId() ~= id or not isNearPlot(id) or CleaningController.isActive() then
		PlacementController.exit()
		return
	end
	local model = selected
	if model and not model:IsDescendantOf(Workspace) then
		setMode("Idle")
	end
end

local function step(dt: number)
	if not active then
		return
	end
	local now = os.clock()
	local speed = PAN_SPEED * zoom / ZOOM_DEFAULT * dt
	local right, forward = screenAxes()
	local ws = keyAxis(UP_KEYS, DOWN_KEYS)
	local ad = keyAxis(RIGHT_KEYS, LEFT_KEYS)
	if ws ~= 0 or ad ~= 0 then
		local move = (right * ad + forward * ws) * speed
		panBy(move.X, move.Z)
	end
	if stick2.Magnitude >= STICK_DEADZONE then
		local move = (right * stick2.X + forward * stick2.Y) * speed
		panBy(move.X, move.Z)
	end
	if triggerL > TRIGGER_DEADZONE then
		zoomBy(ZOOM_SPEED * triggerL * dt)
	end
	if triggerR > TRIGGER_DEADZONE then
		zoomBy(-ZOOM_SPEED * triggerR * dt)
	end
	if kind == "Mouse" then
		updateMouseCursor()
	elseif kind == "Gamepad" then
		updateStickCursor(now)
	end
	local held = yDown
	if held and now - held >= HOLD_TIME then
		yDown = nil
		packUp()
	end
	updateCamera(dt)
	if dirty then
		dirty = false
		updateVisuals()
	end
	updateGhost(dt)
	if now >= nextRangeCheck then
		nextRangeCheck = now + RANGE_CHECK
		expireRequests(now)
		checkStillHere()
	end
end

---------------------------------------------------------------- enter / exit

local function hideHud(on: boolean)
	local hud = HudController.refs()
	if not hud then
		return
	end
	if on then
		for _, gui in { hud.CarryPanel :: GuiObject, hud.Menu :: GuiObject } do
			savedHud[gui] = gui.Visible
			gui.Visible = false
		end
	else
		for gui, wasVisible in savedHud do
			gui.Visible = wasVisible
		end
		table.clear(savedHud)
	end
end

local function connect(signal: RBXScriptSignal, handler: (...any) -> ())
	table.insert(connections, signal:Connect(handler))
end

-- Opens build mode (B, D-pad Up, the BUILD button). Refuses with a toast
-- when you're away from your plot or busy with something else.
function PlacementController.enter()
	if active then
		return
	end
	local id = myPlotId()
	if not id or not isNearPlot(id) then
		HudController.toast(ENTER_TEXT, "Deny")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local owner = PlayerControls.owner()
	if CleaningController.isActive() or (owner ~= nil and owner ~= "Build") or not PlayerControls.claim("Build") then
		HudController.toast(BUSY_TEXT, "Deny")
		return
	end
	active = true
	plotId = id
	plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[id])
	kind = currentKind()
	mode = "Idle"
	pickId = nil
	selected = nil
	painting = nil
	holdCell = nil
	panX, panZ = 0, PAN_START_Z
	zoom = ZOOM_DEFAULT
	-- the cursor starts under you
	local root = rootPart()
	if root then
		local p = plotCF:PointToObjectSpace(root.Position)
		cursorX = math.clamp(math.floor((p.X + HALF) / CELL), 0, CELLS - 1)
		cursorZ = math.clamp(math.floor((p.Z + HALF) / CELL), 0, CELLS - 1)
	end

	-- hands and HUD out of the way
	humanoid:UnequipTools()
	MiningController.setBusy(true)
	InteractController.suspend()
	PromptController.setSuppressed("Build", true)
	pcall(function()
		GuiService.TouchControlsEnabled = false
	end)
	local okBackpack, backpackEnabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
	savedBackpack = if okBackpack then backpackEnabled else nil
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	hideHud(true)

	-- camera flies to the overview
	local cam = camera()
	savedCF = cam.CFrame
	savedFov = cam.FieldOfView
	camCF = cam.CFrame
	flyFrom = cam.CFrame
	flyStart = os.clock()
	cam.CameraType = Enum.CameraType.Scriptable

	GridOverlay.show(plotCF)
	if not ghostHighlight then
		ghostHighlight = newHighlight("BuildGhostHighlight", OK_COLOR, 0.7)
	end
	if not selectHighlight then
		selectHighlight = newHighlight("BuildSelectHighlight", SELECT_COLOR, 0.85)
	end
	local refs = view
	if refs then
		refs.Gui.Enabled = true
	end

	RunService:BindToRenderStep("TerraForgeBuild", Enum.RenderPriority.Camera.Value + 2, step)
	ContextActionService:BindActionAtPriority(
		"TerraForgeBuildPad",
		onPad,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.Thumbstick1,
		Enum.KeyCode.Thumbstick2
	)
	ContextActionService:BindActionAtPriority(
		"TerraForgeBuildKeys",
		onKey,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.R,
		Enum.KeyCode.M,
		Enum.KeyCode.X,
		Enum.KeyCode.Delete,
		Enum.KeyCode.C
	)
	connect(UserInputService.InputBegan, onInputBegan)
	connect(UserInputService.InputChanged, onInputChanged)
	connect(UserInputService.InputEnded, onInputEnded)
	connect(UserInputService.LastInputTypeChanged, function(inputType: Enum.UserInputType)
		local newKind: Kind? = kindOf(inputType)
		if newKind and newKind ~= kind then
			kind = newKind
			holdCell = nil
			refreshUI()
		end
	end)
	connect(humanoid.Died, function()
		PlacementController.exit()
	end)
	connect(player.CharacterAdded, function()
		PlacementController.exit()
	end)
	connect(player:GetAttributeChangedSignal("PlotId"), function()
		PlacementController.exit()
	end)
	connect(CollectionService:GetInstanceAddedSignal("Machine"), function(instance: Instance)
		if instance:IsA("Model") and instance:GetAttribute("Owner") == player.UserId then
			dirty = true
			if mode == "Placing" or mode == "Moving" then
				fadeModel(instance)
			end
		end
	end)
	connect(CollectionService:GetInstanceRemovedSignal("Machine"), function(instance: Instance)
		if instance == selected then
			setMode("Idle")
		end
		dirty = true
	end)

	expireRequests(os.clock())
	dirty = true
	refreshUI()
	if kind == "Gamepad" then
		hoverSelect()
	end
	PlacementController.refreshButton()
	Sfx.play("UIClick")
	-- may wait for the PlayerModule the first time
	PlayerControls.set(false)
	if not active then
		PlayerControls.set(true)
	end
end

-- Closes build mode and gives the camera, controls and HUD back.
function PlacementController.exit()
	if not active then
		return
	end
	active = false
	painting = nil
	yDown = nil
	rightDrag = nil
	pinch = nil
	table.clear(touches)
	stick1, stick2 = Vector2.zero, Vector2.zero
	triggerL, triggerR = 0, 0
	heldX, heldZ = 0, 0
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	RunService:UnbindFromRenderStep("TerraForgeBuild")
	ContextActionService:UnbindAction("TerraForgeBuildPad")
	ContextActionService:UnbindAction("TerraForgeBuildKeys")

	mode = "Idle"
	pickId = nil
	selected = nil
	setFaded(false)
	showGhost(nil)
	ghostTarget = nil
	local highlight = selectHighlight
	if highlight then
		highlight.Adornee = nil
	end
	GridOverlay.hide()
	local refs = view
	if refs then
		refs.Gui.Enabled = false
	end

	-- camera back to the character
	local cam = camera()
	local back, fov = savedCF, savedFov
	camCF, flyFrom, savedCF = nil, nil, nil
	if back then
		TweenService:Create(cam, TweenInfo.new(RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			CFrame = back,
			FieldOfView = fov,
		}):Play()
	end
	task.delay(RETURN_TIME, function()
		if not active then
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = fov
		end
	end)

	hideHud(false)
	if savedBackpack ~= nil then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, savedBackpack)
		savedBackpack = nil
	end
	pcall(function()
		GuiService.TouchControlsEnabled = true
	end)
	PromptController.setSuppressed("Build", false)
	InteractController.resume()
	MiningController.setBusy(false)
	task.spawn(PlayerControls.set, true)
	PlayerControls.release("Build")
	PlacementController.refreshButton()
end

function PlacementController.isActive(): boolean
	return active
end

-- The HUD's BUILD button pulses while your Cleaning Station waits in the
-- inventory (it's the first thing to place after packing it up).
function PlacementController.refreshButton()
	local button = buildButton
	local holder = button and button.Parent
	if not button or not holder then
		return
	end
	local state = StateController.get()
	local inventory = state and state.MachineInventory
	local count = if type(inventory) == "table" then tonumber(inventory.CleaningStation) or 0 else 0
	local wanted = not active and count > 0
	local scale = holder:FindFirstChild("Pulse")
	if wanted and not pulse then
		if not scale then
			local created = Instance.new("UIScale")
			created.Name = "Pulse"
			created.Parent = holder
			scale = created
		end
		local tween = TweenService:Create(
			scale :: UIScale,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.12 }
		)
		tween:Play()
		pulse = tween
	elseif not wanted and pulse then
		pulse:Cancel()
		pulse = nil
		if scale and scale:IsA("UIScale") then
			scale.Scale = 1
		end
	end
end

---------------------------------------------------------------- lifecycle

function PlacementController.init()
	Net.listen("BuildResult", onResult)
	StateController.onChanged(onState)
	-- other players' building (your own plays locally when the server says yes)
	FxController.register("Placed", function(position: any)
		if typeof(position) == "Vector3" then
			Sfx.play("Place", position)
			Vfx.burst("Dust", position, 10)
		end
	end)
	FxController.register("PackedUp", function(position: any)
		if typeof(position) == "Vector3" then
			Sfx.play("Place", position, 1.35)
			Vfx.burst("Dust", position, 8)
		end
	end)
end

function PlacementController.start()
	local refs = BuildView.build()
	refs.Gui.Parent = player:WaitForChild("PlayerGui")
	view = refs
	refs.Done.Activated:Connect(PlacementController.exit)
	refs.Cancel.Activated:Connect(function()
		cancel()
	end)
	refs.Rotate.Activated:Connect(rotate)
	refs.Place.Activated:Connect(commit)
	refs.Move.Activated:Connect(startMove)
	refs.PackUp.Activated:Connect(packUp)

	local hud = HudController.refs()
	if hud then
		local button = BuildView.menuButton(hud.Menu)
		buildButton = button
		button.Activated:Connect(function()
			if active then
				PlacementController.exit()
			else
				PlacementController.enter()
			end
		end)
	end
	ContextActionService:BindAction("TerraForgeBuildToggle", onToggle, false, Enum.KeyCode.B, Enum.KeyCode.DPadUp)
	PlacementController.refreshButton()
end

return PlacementController
