--[[
	The lobby style kit (src/server/World/Lobby/Style.luau) builds every
	helper without errors and follows the look rules.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Gallery = require("../tools/lune/lib/style_gallery")

	T.test("style kit: every helper builds", function()
		local game = roblox.Instance.new("DataModel")
		local root = Gallery.build(Loader, game:GetService("Workspace"))
		local parts, neon, lights = 0, 0, 0
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.truthy(d.Anchored, d:GetFullName() .. " is anchored")
				if d.Material == roblox.Enum.Material.Neon then
					neon += 1
					T.falsy(d.CastShadow, d:GetFullName() .. " neon casts no shadow")
				end
			elseif d:IsA("PointLight") then
				lights += 1
				T.falsy(d.Shadows, "lights have shadows off")
			end
		end
		T.truthy(parts > 300, "gallery has parts")
		T.truthy(neon > 10, "gallery has neon glows")
		T.lt(lights, 4, "gallery uses few lights")
	end)

	T.test("style kit: signs carry readable SurfaceGui text", function()
		local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
		local game = roblox.Instance.new("DataModel")
		local ws = game:GetService("Workspace")
		local board = Style.sign(ws, roblox.CFrame.new(), "SHOP", 8, 3, { Kind = "Glow", DoubleSided = true })
		T.eq(board.Name, "Sign")
		local guis = 0
		for _, child in board:GetChildren() do
			if child:IsA("SurfaceGui") then
				guis += 1
				local label = child:FindFirstChildWhichIsA("TextLabel")
				T.truthy(label and label.Text == "SHOP" and label.TextScaled, "sign label")
				T.eq(child.LightInfluence, 0, "glow signs are unlit")
			end
		end
		T.eq(guis, 2, "double-sided sign has two faces")
	end)
end
