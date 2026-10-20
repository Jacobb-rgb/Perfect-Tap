--[[
	Proposals for replacing THE GREAT FORGE with the bridge garden (owner
	2026-10-20). Scene "forge_bridge" for tools/lune/export_scene.luau, the
	second argument picks the look (A / B / C, Plaza/BridgeGarden.Styles).
	Builds the world, takes THE GREAT FORGE out (and whatever flora grew in
	the garden's area), then builds the garden.
]]

local roblox = require("@lune/roblox") :: any

local Preview = {}

function Preview.build(Loader: any, workspace: any, styleId: string)
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local BridgeGarden = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.BridgeGarden")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local map = WorldBuilder.build(workspace)
	local lobby = map.Emberfall.Lobby
	local forge = lobby.Plaza:FindFirstChild("GreatForge")
	if forge then
		forge:Destroy()
	end
	-- clear the flora that stood in the garden's area (trees, tufts, fences, beds)
	local a = BridgeGarden.Area
	local function inside(p: any): boolean
		return p.X > a.Min.X and p.X < a.Max.X and p.Z > a.Min.Z and p.Z < a.Max.Z and p.Y < 40
	end
	local doomed = {}
	for _, d in lobby.Flora:GetDescendants() do
		if d:IsA("BasePart") and inside(d.CFrame.Position) then
			local owner = d.Parent
			if owner and owner:IsA("Model") and owner.Name ~= "Meadow" and owner.Name ~= "Flora" then
				table.insert(doomed, owner)
			else
				table.insert(doomed, d)
			end
		end
	end
	for _, d in doomed do
		pcall(function()
			d:Destroy()
		end)
	end
	BridgeGarden.build(lobby.Plaza, Rng.new(`BridgeGarden/{styleId}`), styleId)
	return map
end

return Preview
