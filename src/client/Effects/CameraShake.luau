--[[
	Small, juicy camera shake (trauma model). Applied after the default
	camera each frame, so it works with any camera mode.
	CameraShake.add(0.3) -- light hit; 0.6 big crack; 1.0 explosion
	CameraShake.kick(math.rad(0.5)) -- recoil: the view tips up and settles back
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
local applied = CFrame.identity -- offset added last frame, removed before the camera updates
local kickAngle = 0 -- recoil pitch (radians), settles back to 0
local KICK_RECOVER = 14 -- per second
local MAX_KICK = math.rad(3)

local function noise(seed: number): number
	return math.noise(t * 22, seed) * 2
end

local function bind()
	if bound then
		return
	end
	bound = true
	-- undo last frame's offset before the camera scripts run (no slow drift)...
	RunService:BindToRenderStep("TerraForgeCameraUnshake", Enum.RenderPriority.Camera.Value - 1, function()
		local camera = Workspace.CurrentCamera
		if camera and applied ~= CFrame.identity then
			camera.CFrame = camera.CFrame * applied:Inverse()
			applied = CFrame.identity
		end
	end)
	-- ...and add this frame's offset after they ran
	RunService:BindToRenderStep("TerraForgeCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if trauma <= 0 and kickAngle <= 0 then
			return
		end
		t += dt
		trauma = math.max(0, trauma - DECAY * dt)
		kickAngle = if kickAngle > 1e-4 then kickAngle * math.exp(-KICK_RECOVER * dt) else 0
		local shake = trauma * trauma
		local camera = Workspace.CurrentCamera
		if camera then
			applied = CFrame.new(noise(1) * MAX_OFFSET * shake, noise(2) * MAX_OFFSET * shake, 0)
				* CFrame.Angles(noise(3) * MAX_ANGLE * shake + kickAngle, noise(4) * MAX_ANGLE * shake, noise(5) * MAX_ANGLE * shake)
			camera.CFrame = camera.CFrame * applied
		end
	end)
end

function CameraShake.add(amount: number)
	bind()
	trauma = math.min(1, trauma + amount)
end

-- Recoil: tips the view up by `angle` radians (adds up, capped), settling back quickly.
function CameraShake.kick(angle: number)
	if angle <= 0 or angle ~= angle then
		return
	end
	bind()
	kickAngle = math.min(MAX_KICK, kickAngle + angle)
end

return CameraShake
