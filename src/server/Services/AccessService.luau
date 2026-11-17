--[[
	AccessService: the VIP cave behind every yard (World/PlotCave, owner 2026-11-17: "it opens only
	with the pass"; only the plot's owner goes in) is its owner's, with the Forgemaster's Pass.
	- Its door is solid for everyone on the server; the owner's client makes their own door
	  passable (AccessController). A client could do that without the pass, so every second the
	  server moves anyone else found in a cave back into the yard in front of its door.
	- Its 5 rocks grow only while the plot's owner has the pass (MiningService's spawn gate: phones
	  carry no rocks in caves nobody may enter), and only the owner mines them (the mine gate).
	(The old Glimmer Grotto at the quarry went the same day; its zone's ore, VIP rule and lighting
	are the plot caves' now.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local Perks = require(script.Parent.Parent.Perks)
local PlotCave = require(script.Parent.Parent.World.PlotCave)
local MovementService = require(script.Parent.MovementService)
local MiningService = require(script.Parent.MiningService)
local PlotService = require(script.Parent.PlotService)

local AccessService = {}

AccessService.Deny = "This Glimmer Grotto is its plot owner's, with the Forgemaster's Pass."
AccessService.MineDeny = "Only this plot's owner mines its Glimmer Grotto."

-- plots being released this moment (PlotService.onReleased runs before the owner is cleared)
local releasing: { [number]: boolean } = {}
local perkWatch: { [Player]: RBXScriptConnection } = {}
local rooms: { { Id: number, CFrame: CFrame, Half: Vector3 } } = {}

-- May `player` be in plot `plotId`'s cave and mine there? (its owner, with the pass)
function AccessService.mayEnter(player: Player, plotId: number): boolean
	return not releasing[plotId] and PlotService.ownerOf(plotId) == player and Perks.has(player, "ForgeVip")
end

-- The plot whose cave room holds `position`, if any.
function AccessService.caveAt(position: Vector3): number?
	if #rooms == 0 then
		for _, plot in WorldLayout.Plots do
			local cf, size = PlotCave.roomBox(plot)
			table.insert(rooms, { Id = plot.Id, CFrame = cf, Half = size / 2 })
		end
	end
	for _, room in rooms do
		local q = room.CFrame:PointToObjectSpace(position)
		if math.abs(q.X) <= room.Half.X and math.abs(q.Y) <= room.Half.Y and math.abs(q.Z) <= room.Half.Z then
			return room.Id
		end
	end
	return nil
end

local function plotOfMarker(marker: BasePart): number?
	local id = marker:GetAttribute("PlotId")
	return if type(id) == "number" then id else nil
end

-- May `marker`'s rock grow now? (a cave's only while its plot's owner has the pass)
function AccessService.spawnAllowed(marker: BasePart): boolean
	local plotId = plotOfMarker(marker)
	if not plotId then
		return true
	end
	local owner = PlotService.ownerOf(plotId)
	return owner ~= nil and AccessService.mayEnter(owner, plotId)
end

-- Why `player` may not mine `marker`'s rock (another plot's cave), or nil.
function AccessService.mineRefusal(player: Player, marker: BasePart): string?
	local plotId = plotOfMarker(marker)
	if plotId and PlotService.ownerOf(plotId) ~= player then
		return AccessService.MineDeny
	end
	return nil
end

-- Grows or takes away one plot's cave rocks for who owns it now.
local function refresh(plotId: number)
	MiningService.refreshMarkers(function(marker: BasePart): boolean
		return plotOfMarker(marker) == plotId
	end)
end

function AccessService.init()
	MiningService.setSpawnGate(AccessService.spawnAllowed)
	MiningService.setMineGate(AccessService.mineRefusal)
end

function AccessService.start()
	PlotService.onAssigned(function(player: Player, plotId: number)
		refresh(plotId)
		if not perkWatch[player] then
			perkWatch[player] = player:GetAttributeChangedSignal("Perk_ForgeVip"):Connect(function()
				local id = PlotService.plotOf(player)
				if id then
					refresh(id)
				end
			end)
		end
	end)
	PlotService.onReleased(function(_player: Player, plotId: number)
		releasing[plotId] = true
		refresh(plotId)
		task.defer(function()
			releasing[plotId] = nil
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local watch = perkWatch[player]
		if watch then
			watch:Disconnect()
			perkWatch[player] = nil
		end
	end)
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and character then
				local plotId = AccessService.caveAt(root.Position)
				if plotId and not AccessService.mayEnter(player, plotId) then
					character:PivotTo(PlotCave.outside(WorldLayout.Plots[plotId]))
					MovementService.serverMoved(player)
					Net.fire("Notify", player, { Text = AccessService.Deny, Kind = "Deny" })
				end
			end
		end
	end
end

return AccessService
