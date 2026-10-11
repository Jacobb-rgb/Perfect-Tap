--[[
	FxController: plays effects the server announces (other players' hits,
	node cracks and shatters, pickups, throws). Your own pickaxe hits are
	predicted locally by MiningController so they feel instant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)

local FxController = {}

local function oreColors(oreId: any): (Color3, Color3, number)
	local ore = if type(oreId) == "string" then OreData.ById[oreId] else nil
	if not ore then
		return Color3.fromRGB(150, 130, 110), Color3.fromRGB(255, 200, 120), 1
	end
	return ore.Crust, ore.Glow, Rarity.get(ore.Rarity).Order
end

local handlers: { [string]: (...any) -> () } = {}

-- position, oreId, stage
handlers.MineHit = function(position: Vector3, oreId: any)
	local crust = oreColors(oreId)
	Vfx.burst("Sparks", position, 8)
	Vfx.burst("Dust", position, 2, crust)
	Sfx.play("PickHit", position)
end

handlers.MineBounce = function(position: Vector3)
	Vfx.burst("Sparks", position, 4, Color3.fromRGB(200, 200, 220))
	Sfx.play("PickBounce", position)
end

handlers.NodeCrack = function(position: Vector3, oreId: any, stage: any)
	local crust, glow = oreColors(oreId)
	Vfx.burst("Dust", position, 6, crust)
	Vfx.burst("Glint", position + Vector3.new(0, 1, 0), 6, glow)
	Vfx.chips(position + Vector3.new(0, 1.5, 0), if stage == 2 then 6 else 3, crust)
	Sfx.play("NodeCrack", position)
	CameraShake.add(if stage == 2 then 0.32 else 0.2)
end

handlers.NodeShatter = function(position: Vector3, oreId: any)
	local crust, glow, order = oreColors(oreId)
	Vfx.burst("Dust", position, 14, crust)
	Vfx.burst("Burst", position + Vector3.new(0, 1, 0), 10 + order * 4, glow)
	Vfx.chips(position + Vector3.new(0, 2, 0), 10, crust, 1.3)
	Sfx.play("NodeShatter", position)
	CameraShake.add(0.45)
end

handlers.Pickup = function(position: Vector3, oreId: any)
	local _, glow = oreColors(oreId)
	Vfx.burst("Glint", position, 5, glow)
	Sfx.play("Pickup")
end

handlers.Throw = function(position: Vector3)
	Sfx.play("Throw", position)
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
end

return FxController
