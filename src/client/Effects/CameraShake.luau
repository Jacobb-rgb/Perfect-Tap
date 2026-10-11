--[[
	Small, juicy camera shake (trauma model). Applied after the default
	camera each frame, so it works with any camera mode.
	CameraShake.add(0.3) -- light hit; 0.6 big crack; 1.0 explosion
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraShake = {}

local trauma = 0
local MAX_ANGLE = math.rad(2.2)
local MAX_OFFSET = 0.35
local DECAY = 2.4 -- trauma lost per second
local t = 0
local bound = false

local function noise(seed: number): number
	return math.noise(t * 22, seed) * 2
end

local function bind()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep("TerraForgeCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if trauma <= 0 then
			return
		end
		t += dt
		trauma = math.max(0, trauma - DECAY * dt)
		local shake = trauma * trauma
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CFrame = camera.CFrame
				* CFrame.new(noise(1) * MAX_OFFSET * shake, noise(2) * MAX_OFFSET * shake, 0)
				* CFrame.Angles(noise(3) * MAX_ANGLE * shake, noise(4) * MAX_ANGLE * shake, noise(5) * MAX_ANGLE * shake)
		end
	end)
end

function CameraShake.add(amount: number)
	bind()
	trauma = math.min(1, trauma + amount)
end

return CameraShake
