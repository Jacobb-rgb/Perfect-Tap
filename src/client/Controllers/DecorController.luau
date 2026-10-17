--[[
	Small client-only animations for world decoration (no network cost):
	- parts/models tagged "Spin" rotate about their pivot's Y axis and bob
	  (the plaza's fire crystal, the SPIN & WIN wheel, the balloon).
	  Optional attributes on the tagged instance:
	    SpinSpeed  radians per second (default 0.8; 0 = no spin)
	    BobHeight  studs (default 0.4; 0 = no bob)
	    BobSpeed   (default 1.4)
	  A wheel spins around its axle when its pivot's Y axis is the axle.
	- neon parts named "ForgeGlow" / "Lava" / "MoltenChannel" pulse gently
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DecorController = {}

-- A spinner is a part or a whole model (all parts turn around the model's pivot).
type Spinner = {
	pivot: CFrame,
	parts: { { part: BasePart, offset: CFrame } },
	phase: number,
	speed: number,
	bob: number,
	bobSpeed: number,
}

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local spinners: { [Instance]: Spinner } = {}
local pulsers: { [BasePart]: { base: Color3, phase: number } } = {}

local function addSpinner(instance: Instance)
	if spinners[instance] then
		return
	end
	local pivot: CFrame
	local parts = {}
	if instance:IsA("BasePart") then
		pivot = instance.CFrame
		table.insert(parts, { part = instance, offset = CFrame.identity })
	elseif instance:IsA("Model") then
		pivot = instance:GetPivot()
		for _, d in instance:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, { part = d, offset = pivot:ToObjectSpace(d.CFrame) })
			end
		end
	else
		return
	end
	spinners[instance] = {
		pivot = pivot,
		parts = parts,
		phase = math.random() * 6,
		speed = numberAttribute(instance, "SpinSpeed", 0.8),
		bob = numberAttribute(instance, "BobHeight", 0.4),
		bobSpeed = numberAttribute(instance, "BobSpeed", 1.4),
	}
end

local function scanPulsers(root: Instance)
	for _, d in root:GetDescendants() do
		-- only the first time: later scans must not take the dimmed color as the new base
		if
			not pulsers[d :: BasePart]
			and d:IsA("BasePart")
			and (d.Name == "ForgeGlow" or d.Name == "Lava" or d.Name == "MoltenChannel")
		then
			pulsers[d] = { base = d.Color, phase = math.random() * 6 }
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

	-- StreamingEnabled: parts arrive over time, so rescan now and then.
	task.spawn(function()
		while true do
			local map = Workspace:FindFirstChild("Map")
			if map then
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
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		for instance, s in spinners do
			if instance.Parent then
				local cf = s.pivot * CFrame.new(0, math.sin(t * s.bobSpeed + s.phase) * s.bob, 0) * CFrame.Angles(0, t * s.speed, 0)
				for _, entry in s.parts do
					entry.part.CFrame = cf * entry.offset
				end
			else
				spinners[instance] = nil
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
