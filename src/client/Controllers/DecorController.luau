--[[
	Small client-only animations for world decoration (no network cost):
	- parts tagged "Spin" rotate and bob (the Heartstone shard in the plaza)
	- neon parts named "ForgeGlow" / "Lava" pulse gently
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DecorController = {}

type Spinner = { part: BasePart, base: CFrame, phase: number }

local spinners: { [BasePart]: Spinner } = {}
local pulsers: { [BasePart]: { base: Color3, phase: number } } = {}

local function addSpinner(instance: Instance)
	if instance:IsA("BasePart") and not spinners[instance] then
		spinners[instance] = { part = instance, base = instance.CFrame, phase = math.random() * 6 }
	end
end

local function scanPulsers(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "ForgeGlow" or d.Name == "Lava" or d.Name == "MoltenChannel") then
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
		spinners[instance :: BasePart] = nil
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
		for part, s in spinners do
			if part.Parent then
				part.CFrame = s.base * CFrame.new(0, math.sin(t * 1.4 + s.phase) * 0.4, 0) * CFrame.Angles(0, t * 0.8, 0)
			else
				spinners[part] = nil
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
