--[[
	FxController: plays effects the server announces (other players' laser
	beams, rock cracks and shatters, pickups, throws). Your own beam is drawn
	locally by MiningController every frame so it feels instant.
	Feature controllers add their own Fx kinds with FxController.register.

	Rock effects never name the ores inside (they stay secret until cleaned):
	they carry the rock's crust color and the beam's / dropped ore's glow
	color instead. Cracks and shatters play the breaking animation of
	Effects/RockFx (debris, flash, ring, sound, camera shake); the newer
	payloads add the stage count and the rock's floor, kind and radius, the
	old 3-value payloads still work.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared.Config.JuiceConfig)
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local RockFx = require(script.Parent.Parent.Effects.RockFx)
local BlasterFx = require(script.Parent.Parent.Effects.BlasterFx)

local FxController = {}

local DEFAULT_CRUST = Color3.fromRGB(150, 130, 110)
local DEFAULT_GLOW = Color3.fromRGB(255, 150, 70)
local OTHER_BEAM_HOLD = 0.35 -- seconds an other player's beam stays without a new BlastHit

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

-- A whole number in [low, high] from the payload, else nil.
local function countOf(value: any, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(math.floor(value + 0.5), low, high)
end

local ROCK_KINDS = { Small = true, Big = true, Crystal = true, Golden = true, Geode = true, Artifact = true, Giant = true }

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
		local level = if tool then BlasterFx.levelOf(tool) else nil
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

-- A crack stage: (position, crustColor, stage, glowColor?, stages?)
handlers.NodeCrack = function(position: any, crust: any, stage: any, glow: any, stages: any)
	if not isVector(position) then
		return
	end
	local glowColor = if glow ~= nil then colorOf(glow, DEFAULT_GLOW, true) else nil
	RockFx.crack(position, colorOf(crust, DEFAULT_CRUST), countOf(stage, 1, 20) or 1, glowColor, countOf(stages, 1, 20))
end

-- The rock breaks: (position, crustColor, glowColor, floor?, kind?, radius?)
handlers.NodeShatter = function(position: any, crust: any, glow: any, floor: any, kind: any, radius: any)
	if not isVector(position) then
		return
	end
	local size = if type(radius) == "number" and radius == radius then math.clamp(radius, 0.5, 30) else nil
	RockFx.shatter(
		position,
		colorOf(crust, DEFAULT_CRUST),
		colorOf(glow, DEFAULT_GLOW, true),
		countOf(floor, 1, 99),
		if type(kind) == "string" and ROCK_KINDS[kind] then kind else nil,
		size
	)
end

-- (the backpack's auto-pickup takes several items in one pass: one click per JuiceConfig.SoundGap)
local pickupSoundAt = -math.huge
handlers.Pickup = function(position: Vector3, oreId: any)
	Vfx.burst("Glint", position, 5, colorOf(oreId, DEFAULT_GLOW, true))
	local now = os.clock()
	if now - pickupSoundAt >= JuiceConfig.SoundGap then
		pickupSoundAt = now
		Sfx.play("Pickup")
	end
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
