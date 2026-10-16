--[[
	Lobby blockout: a translucent, color-coded box (with a name label) for
	every set piece in LobbyLayout, plus the lobby paths, so the layout can
	be judged from the hero cameras before the real builds exist.
	Scene "lobby_blockout" in tools/lune/export_scene.luau.
]]

local roblox = require("@lune/roblox") :: any

local Blockout = {}

local PACKAGE_COLORS = {
	Sky = { 120, 170, 255 },
	Backdrop = { 150, 110, 200 },
	Plaza = { 255, 170, 60 },
	Districts = { 255, 90, 150 },
	Flora = { 90, 220, 110 },
}

function Blockout.build(Loader: any, parent: any)
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local rng = Rng.new("blockout")
	local root = roblox.Instance.new("Model")
	root.Name = "LobbyBlockout"
	root.Parent = parent
	for _, piece in LobbyLayout.Pieces do
		local c = PACKAGE_COLORS[piece.Package]
		local color = roblox.Color3.fromRGB(c[1], c[2], c[3])
		local frame = LobbyLayout.frame(piece)
		local size = piece.Size
		if piece.Id ~= "CloudBanks" and piece.Id ~= "SunGlitter" then
			local box = Style.block(root, frame * CF.new(0, size.Y / 2, 0), size, color, roblox.Enum.Material.SmoothPlastic, Style.tiny())
			box.Transparency = if piece.Walkable then 0.75 else 0.55
			if piece.Radius then
				box.Shape = roblox.Enum.PartType.Cylinder
				box.Size = V3.new(size.Y, piece.Radius * 2, piece.Radius * 2)
				box.CFrame = CF.new(piece.Center + V3.new(0, size.Y / 2, 0)) * CF.Angles(0, 0, math.pi / 2)
			end
			-- front marker and a label facing the front
			Style.block(
				root,
				frame * CF.new(0, 0.6, -size.Z / 2 - 0.6),
				V3.new(math.min(size.X, 4), 1.2, 1.2),
				roblox.Color3.new(1, 1, 1),
				roblox.Enum.Material.Neon,
				Style.tiny()
			)
			local labelWidth = math.clamp(#piece.Id * 1.1, 6, 40)
			Style.sign(
				root,
				frame * CF.new(0, size.Y + 2.5, 0),
				piece.Id,
				labelWidth,
				3,
				{ Kind = "Glow", Frame = false, DoubleSided = true }
			)
		end
	end
	for _, path in LobbyLayout.Paths do
		Style.path(root, path.From, path.To, path.Width, rng, { Kind = path.Kind, TileEvery = 0 })
	end
	return root
end

return Blockout
