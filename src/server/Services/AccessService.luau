--[[
	AccessService: keeps non-VIP players out of the Glimmer Grotto.
	The door is solid for everyone on the server; VIP clients make it
	passable locally (AccessController). Because a client could also do that
	without the pass, the server checks positions and moves intruders out.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local Perks = require(script.Parent.Parent.Perks)
local MovementService = require(script.Parent.MovementService)

local AccessService = {}

-- just outside the grotto tunnel, on the quarry floor, facing the quarry
local OUTSIDE = CFrame.lookAt(Vector3.new(64, -9, -182), Vector3.new(40, -9, -182))

function AccessService.start()
	local grotto = WorldLayout.ZoneById.Grotto
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and character and not Perks.has(player, "ForgeVip") then
				-- inside the grotto room or past the door in the tunnel
				local p = root.Position
				local pastDoor = p.X > 81 and p.X < 90 and math.abs(p.Z + 182) < 8 and p.Y < 2
				if WorldLayout.isInBox(p, grotto.Min, grotto.Max) or pastDoor then
					character:PivotTo(OUTSIDE)
					MovementService.serverMoved(player)
					Net.fire("Notify", player, { Text = "The Glimmer Grotto is for VIPs.", Kind = "Deny" })
				end
			end
		end
	end
end

return AccessService
