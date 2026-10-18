--[[
	FxController: plays effects the server announces (other players' laser
	beams, rock cracks and shatters, pickups, throws). Your own beam is drawn
	locally by MiningController every frame so it feels instant.
	Feature controllers add their own Fx kinds with FxController.register.

	Rock effects never name the ores inside (they stay secret until cleaned):
	they carry the rock's crust color and the beam's glow color instead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local BlasterFx = require(script.Parent.Parent.Effects.BlasterFx)

local FxController = {}

local DEFAULT_CRUST = Color3.fromRGB(150, 130, 110)
local DEFAULT_GLOW = Color3.fromRGB(255, 150, 70)
local OTHER_BEAM_HOLD = 0.35 -- seconds an other player's beam stays without a new BlastHit
local SHAKE_RANGE = 30 -- cracks farther from the camera than this don't shake it

local function isVector(value: any): boolean
	return typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z
end

-- A Color3 from the payload, or an ore id (old payloads), or the fallback.
local function colorOf(value: any, fallback: Color3, glow: boolean?): Color3
	if typeof(value) == "Color3" then
		return value
	end
	local ore = if type(value) == "string" then OreData.ById[value] else nil
	if ore then
		return if glow then ore.Glow else ore.Crust
	end
	return fallback
end

-- Shake the camera only for things happening close to it.
local function shakeNear(position: Vector3, amount: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	if distance < SHAKE_RANGE then
		CameraShake.add(amount * (1 - distance / SHAKE_RANGE * 0.6))
	end
end

-- The Muzzle attachment of a player's blaster, if they hold it.
local function muzzleOf(shooter: any): (Attachment?, Vector3?)
	if typeof(shooter) ~= "Instance" or not shooter:IsA("Player") then
		return nil, nil
	end
	local character = (shooter :: Player).Character
	if not character then
		return nil, nil
	end
	local tool = character:FindFirstChild("Blaster")
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle, muzzle.WorldPosition
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return nil, root.Position + Vector3.new(0, 1, 0)
	end
	return nil, nil
end

local handlers: { [string]: (...any) -> () } = {}

-- Another player's beam hits a rock: (position, glowColor, stage, shooter)
handlers.BlastHit = function(position: any, glow: any, _stage: any, shooter: any)
	if not isVector(position) then
		return
	end
	local color = colorOf(glow, DEFAULT_GLOW, true)
	local muzzle, from = muzzleOf(shooter)
	local mine = shooter == Players.LocalPlayer
	if from and not mine then
		-- their blaster's tier look (thickness, the Lv7+ energy stream)
		local tool = muzzle and muzzle.Parent and muzzle.Parent.Parent
		local level = if tool then tool:GetAttribute("Level") else nil
		Vfx.setBeam(shooter, muzzle, from, position, color, OTHER_BEAM_HOLD, BlasterFx.styleFor(level))
	end
	Vfx.impact(position, color, if from then from - position else nil, if mine then 2 else 5)
	if not mine then
		Sfx.play("BlastHit", position) -- your own hits crackle locally, in time (Effects/BlasterFx)
	end
end

-- Your beam bounced off a rock you can't mine yet: (position)
handlers.MineBounce = function(position: any)
	if not isVector(position) then
		return
	end
	Vfx.burst("Sparks", position, 6, Color3.fromRGB(200, 200, 220))
	Sfx.play("BlastBounce", position)
end

-- (position, crustColor, stage)
handlers.NodeCrack = function(position: any, crust: any, stage: any)
	if not isVector(position) then
		return
	end
	local color = colorOf(crust, DEFAULT_CRUST)
	Vfx.burst("Dust", position, 6, color)
	Vfx.burst("Glint", position + Vector3.new(0, 1, 0), 5, color:Lerp(Color3.new(1, 1, 1), 0.5))
	Vfx.chips(position + Vector3.new(0, 1.5, 0), if stage == 2 then 6 else 3, color)
	Sfx.play("NodeCrack", position)
	shakeNear(position, if stage == 2 then 0.32 else 0.2)
end

-- (position, crustColor, glowColor)
handlers.NodeShatter = function(position: any, crust: any, glow: any)
	if not isVector(position) then
		return
	end
	local color = colorOf(crust, DEFAULT_CRUST)
	Vfx.burst("Dust", position, 14, color)
	Vfx.burst("Burst", position + Vector3.new(0, 1, 0), 18, colorOf(glow, DEFAULT_GLOW, true))
	Vfx.chips(position + Vector3.new(0, 2, 0), 10, color, 1.3)
	Sfx.play("NodeShatter", position)
	shakeNear(position, 0.45)
end

handlers.Pickup = function(position: Vector3, oreId: any)
	Vfx.burst("Glint", position, 5, colorOf(oreId, DEFAULT_GLOW, true))
	Sfx.play("Pickup")
end

handlers.Throw = function(position: Vector3)
	Sfx.play("Throw", position)
end

-- Adds a handler for an Fx kind (e.g. 'Sold', 'Reject'). One handler per kind.
function FxController.register(kind: string, handler: (...any) -> ())
	if handlers[kind] then
		warn("[FxController] Fx kind registered twice: " .. kind)
	end
	handlers[kind] = handler
end

function FxController.play(kind: string, ...: any)
	local handler = handlers[kind]
	if handler then
		handler(...)
	end
end

function FxController.init()
	Net.listen("Fx", function(kind, ...)
		if type(kind) == "string" then
			FxController.play(kind, ...)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		Vfx.releaseBeam(player)
	end)
end

return FxController
