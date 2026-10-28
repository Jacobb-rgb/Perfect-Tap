--[[
	Small client-only animations for world decoration (no network cost):
	- parts/models tagged "Spin" rotate about their pivot's Y axis and bob
	  (the plaza's fire crystal, the SPIN & WIN wheel, the balloon, the airship).
	  Optional attributes on the tagged instance:
	    SpinSpeed  radians per second (default 0.8; 0 = no spin)
	    BobHeight  studs (default 0.4; 0 = no bob)
	    BobSpeed   (default 1.4)
	    Hop        true: hops up from its place instead of bobbing round it
	               (the HALL OF FAME champions, ChampionService)
	  A wheel spins around its axle when its pivot's Y axis is the axle.
	  Each spinner keeps its own angle (dt x SpinSpeed per frame), so another
	  controller can take it over: hold(instance) stops the idle turn and
	  returns the angle, setAngle(instance, radians) turns it there,
	  release(instance) lets the idle turn go on from that angle
	  (WheelController lands the lobby wheel on the player's own prize).
	  bounce(instance) gives a spinner one happy hop with a little wobble
	  on top of its turn (bounceAt: BounceSeconds; the EGGS temple's egg
	  when you walk up to it, EggPanelController, never with Reduce motion).
	- Cheap on phones: a spinner with no spin and no bob is never touched;
	  every CheckSeconds each spinner is sorted by its distance to the camera
	  and whether its bounding sphere is on screen (tier): near ones move
	  every frame, mid-range ones every 2nd frame, far or off-screen ones not
	  at all (they jump to their angle when they come back). A model's parts
	  move in one Workspace:BulkMoveTo call.
	- neon parts named "ForgeGlow" / "Lava" / "MoltenChannel" pulse gently
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DecorController = {}

DecorController.NearDistance = 120 -- studs: every frame
DecorController.FarDistance = 250 -- studs: past this (or off screen) not at all
DecorController.CheckSeconds = 0.25 -- how often the tiers are worked out again
DecorController.BounceSeconds = 0.7 -- one happy hop (bounce)
DecorController.BounceHeight = 0.55 -- studs at its top
DecorController.BounceTilt = 0.14 -- radians: the wobble at its start

-- A spinner is a part or a whole model (all parts turn around the model's pivot).
type Spinner = {
	pivot: CFrame,
	parts: { BasePart },
	offsets: { CFrame },
	cframes: { CFrame }, -- reused every move (BulkMoveTo)
	radius: number, -- the bounding sphere round the pivot
	phase: number,
	speed: number,
	bob: number,
	bobSpeed: number,
	hop: boolean, -- hops up from its place (abs of the wave) instead of bobbing round it
	angle: number, -- radians, about the pivot's Y axis
	held: boolean, -- another controller drives the angle (hold / setAngle)
	bounceAt: number?, -- os.clock() of a running bounce (bounce)
	tier: number, -- 0 = skip, 1 = every frame, 2 = every 2nd frame
}

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local spinners: { [Instance]: Spinner } = {}
local pulsers: { [BasePart]: { base: Color3, phase: number } } = {}

--[[
	How often a spinner moves (pure, for the tests): 1 every frame, 2 every
	2nd frame, 0 not at all. `distance` = camera to pivot (studs), `onScreen`
	= its bounding sphere is in view, `held` = another controller drives it.
]]
function DecorController.tier(distance: number, onScreen: boolean, held: boolean?): number
	if distance > DecorController.FarDistance or not onScreen then
		return 0
	end
	if held or distance <= DecorController.NearDistance then
		return 1
	end
	return 2
end

--[[
	Is a sphere (`center`, `radius`) on screen for a camera (pure, for the
	tests)? `point` = camera:WorldToViewportPoint(center) (x, y in pixels,
	z = depth), `viewport` its size in pixels, `fov` the vertical field of
	view in degrees.
]]
function DecorController.sphereInView(point: Vector3, radius: number, viewport: Vector2, fov: number): boolean
	if point.Z < -radius then
		return false -- behind the camera
	end
	local focal = viewport.Y / (2 * math.tan(math.rad(fov) / 2))
	local margin = radius * focal / math.max(point.Z, 1)
	return point.X >= -margin and point.X <= viewport.X + margin and point.Y >= -margin and point.Y <= viewport.Y + margin
end

local function addSpinner(instance: Instance)
	if spinners[instance] then
		return
	end
	local speed = numberAttribute(instance, "SpinSpeed", 0.8)
	local bob = numberAttribute(instance, "BobHeight", 0.4)
	local pivot: CFrame
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	if instance:IsA("BasePart") then
		pivot = instance.CFrame
		table.insert(parts, instance)
		table.insert(offsets, CFrame.identity)
	elseif instance:IsA("Model") then
		pivot = instance:GetPivot()
		for _, d in instance:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
			end
		end
	else
		return
	end
	local radius = 0
	for i, part in parts do
		radius = math.max(radius, offsets[i].Position.Magnitude + part.Size.Magnitude / 2)
	end
	local isWheel = instance:IsA("Model") and instance.Name == "Wheel"
	if speed == 0 and bob == 0 and not isWheel then
		return -- nothing to animate: never touched
	end
	spinners[instance] = {
		pivot = pivot,
		parts = parts,
		offsets = offsets,
		cframes = table.clone(offsets),
		radius = radius,
		phase = math.random() * 6,
		speed = speed,
		bob = bob,
		bobSpeed = numberAttribute(instance, "BobSpeed", 1.4),
		hop = instance:GetAttribute("Hop") == true,
		angle = 0,
		held = false,
		tier = 1,
	}
end

--[[
	A bounce `dt` seconds in: the lift (studs) and the wobble (radians round
	the spinner's own Z) to add; both 0 before it and from BounceSeconds on.
	A high hop, a small one after it, the wobble dying away (pure: tests).
]]
function DecorController.bounceAt(dt: number): (number, number)
	local d = DecorController.BounceSeconds
	if dt <= 0 or dt >= d then
		return 0, 0
	end
	local k = dt / d
	-- two hops: the first 60 % of the time full height, then a third of it
	local hop = if k < 0.6 then math.sin(k / 0.6 * math.pi) else math.sin((k - 0.6) / 0.4 * math.pi) / 3
	local wobble = math.sin(dt * 22) * DecorController.BounceTilt * (1 - k)
	return hop * DecorController.BounceHeight, wobble
end

-- One happy hop for a spinner (nothing when it isn't one, e.g. not streamed in yet).
function DecorController.bounce(instance: Instance)
	local s = spinners[instance]
	if s then
		s.bounceAt = os.clock()
	end
end

-- Moves a spinner's parts to its angle and bob at time `t`.
local function place(s: Spinner, t: number)
	local wave = math.sin(t * s.bobSpeed + s.phase)
	local lift = if s.hop then math.abs(wave) * s.bob else wave * s.bob
	local tilt = 0
	local at = s.bounceAt
	if at then
		local hop, wobble = DecorController.bounceAt(os.clock() - at)
		if os.clock() - at >= DecorController.BounceSeconds then
			s.bounceAt = nil
		end
		lift += hop
		tilt = wobble
	end
	local cf = s.pivot * CFrame.new(0, lift, 0) * CFrame.Angles(0, s.angle, tilt)
	local cframes = s.cframes
	for i, offset in s.offsets do
		cframes[i] = cf * offset
	end
	local ok = pcall(Workspace.BulkMoveTo, Workspace, s.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if not ok then
		-- (a part streamed out on its own: move the others one by one)
		for i, part in s.parts do
			if part.Parent then
				part.CFrame = cframes[i]
			end
		end
	end
end

-- Stops the idle turn of a spinner (another controller drives it now);
-- returns its angle (radians), or nil when it isn't a spinner (yet).
function DecorController.hold(instance: Instance): number?
	local s = spinners[instance]
	if not s then
		return nil
	end
	s.held = true
	return s.angle
end

-- Turns a held (or any) spinner to `angle` radians; it moves on the next frame.
function DecorController.setAngle(instance: Instance, angle: number)
	local s = spinners[instance]
	if s and angle == angle and angle > -math.huge and angle < math.huge then
		s.angle = angle
	end
end

-- The idle turn goes on from the angle it has now.
function DecorController.release(instance: Instance)
	local s = spinners[instance]
	if s then
		s.held = false
	end
end

local function addPulser(d: Instance)
	-- only the first time: a part seen again must not take the dimmed color as the new base
	if not pulsers[d :: BasePart] and d:IsA("BasePart") and (d.Name == "ForgeGlow" or d.Name == "Lava" or d.Name == "MoltenChannel") then
		pulsers[d] = { base = d.Color, phase = math.random() * 6 }
	end
end

local function scanPulsers(root: Instance)
	for _, d in root:GetDescendants() do
		addPulser(d)
	end
end

-- Works out every spinner's tier from the camera (CheckSeconds).
local function updateTiers()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local from = camera.CFrame.Position
	local viewport = camera.ViewportSize
	local fov = camera.FieldOfView
	for instance, s in spinners do
		if not instance.Parent then
			spinners[instance] = nil
		else
			local center = s.pivot.Position
			local point = camera:WorldToViewportPoint(center)
			local distance = (center - from).Magnitude - s.radius
			s.tier = DecorController.tier(math.max(0, distance), DecorController.sphereInView(point, s.radius, viewport, fov), s.held)
		end
	end
end

function DecorController.start()
	for _, instance in CollectionService:GetTagged("Spin") do
		addSpinner(instance)
	end
	CollectionService:GetInstanceAddedSignal("Spin"):Connect(addSpinner)
	CollectionService:GetInstanceRemovedSignal("Spin"):Connect(function(instance)
		spinners[instance] = nil
	end)

	-- StreamingEnabled: parts arrive over time. One full scan per Map, then only the parts
	-- that stream in (a full GetDescendants every 5 s was a regular hitch on phones).
	task.spawn(function()
		local watched: Instance? = nil
		local added: RBXScriptConnection? = nil
		while true do
			local map = Workspace:FindFirstChild("Map")
			if map and map ~= watched then
				if added then
					added:Disconnect()
				end
				watched = map
				added = map.DescendantAdded:Connect(addPulser)
				scanPulsers(map)
			end
			for part in pulsers do
				if not part.Parent then
					pulsers[part] = nil
				end
			end
			task.wait(5)
		end
	end)

	local t = 0
	local frame = 0
	local sinceCheck = math.huge
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		frame += 1
		sinceCheck += dt
		if sinceCheck >= DecorController.CheckSeconds then
			sinceCheck = 0
			updateTiers()
		end
		for _, s in spinners do
			if not s.held then
				s.angle = (s.angle + dt * s.speed) % (2 * math.pi)
			end
			if s.tier == 1 or (s.tier == 2 and frame % 2 == 0) then
				place(s, t)
			end
		end
		local pulse = 0.88 + math.sin(t * 2.1) * 0.12
		for part, p in pulsers do
			local k = pulse + math.sin(t * 3.3 + p.phase) * 0.04
			part.Color = Color3.new(math.min(1, p.base.R * k), math.min(1, p.base.G * k), math.min(1, p.base.B * k))
		end
	end)
end

return DecorController
