--[[
	Preview scene "vault_game": the world with the in-game Vault lobby package
	(src/server/World/Lobby/Vault) built at its place, before the package is
	registered in LobbyLayout. Lobby decorations inside the vault's footprint
	(trees, flowers, lamps, the mine yard) are hidden in the picture only;
	the lobby session moves them when the package goes in.
]]

local roblox = require("@lune/roblox") :: any

local VaultGame = {}

function VaultGame.build(Loader: any, parent: any)
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Vault = Loader.requirePath("ServerScriptService.Server.World.Lobby.Vault")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	WorldBuilder.build(parent)
	-- the reserved areas: the vault footprint, the statue pedestals, the trees
	local boxes = { { 0, 112.4, 36, 34 }, { -43, 92, 13, 13 }, { 43, 92, 13, 13 } }
	local origin = Vault.origin()
	for _, t in Vault.Trees do
		local p = (origin * Loader.CFrame.new(t[1], 0, t[2])).Position
		table.insert(boxes, { p.X, p.Z, 9, 9 })
	end
	local hidden = 0
	for _, d in parent:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			local top = p.Y + d.Size.Y / 2
			if top > 0.45 and p.Y < 40 and d.Size.X < 60 and d.Size.Z < 60 then
				for _, b in boxes do
					if math.abs(p.X - b[1]) < b[3] and math.abs(p.Z - b[2]) < b[4] then
						d.Transparency = 1
						hidden += 1
						break
					end
				end
			end
		end
	end
	print(string.format("vault_game: hid %d lobby parts in the reserved areas", hidden))
	local m = roblox.Instance.new("Model")
	m.Name = "Vault"
	m.Parent = parent
	Vault.build(m, Rng.new("Lobby/Vault"))
	return m
end

return VaultGame
