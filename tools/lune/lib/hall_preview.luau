--[[
	The giant HALL OF FAME with its champions (scene "hall" for
	tools/lune/export_scene.luau: the world, shots in tools/preview/hall_shots.json).
	Lune can't fetch Roblox avatars, so blocky stand-in miners (Kit.npc) stand
	on the four Champion pedestals where ChampionService puts the #1 players'
	avatars in the game; the boards show sample rows like LeaderboardView.
]]

local Preview = {}

function Preview.build(Loader: any, map: any)
	local Kit = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Kit")
	local ChampionService = Loader.requirePath("ServerScriptService.Server.Services.ChampionService")
	local roblox = require("@lune/roblox") :: any
	local rgb = roblox.Color3.fromRGB
	local looks = {
		{ Shirt = rgb(220, 60, 70), Pants = rgb(40, 44, 60), Hat = rgb(255, 196, 40) },
		{ Shirt = rgb(60, 140, 240), Pants = rgb(30, 34, 50), Goggles = rgb(120, 220, 255) },
		{ Shirt = rgb(150, 80, 230), Pants = rgb(50, 40, 70), Wave = true },
		{ Shirt = rgb(70, 200, 90), Pants = rgb(60, 50, 40), Apron = rgb(140, 90, 50) },
	}
	-- sample rows on the boards (in the game LeaderboardView draws them; the
	-- scene exporter shows one text per part face, so each row is a thin plate)
	local rows = {
		{ "EmberQueen  $8.2Qa/s", "RockyMiner77  $2.6Qa/s", "Forgekeeper_Ola  $853T/s", "CrystalKid  $275T/s", "DeepHollowDan  $88T/s" },
		{ "EmberQueen  $41Qi", "Forgekeeper_Ola  $12Qi", "GolemWhisperer  $3.1Qi", "SparkyStone  $904Qa", "QuarryQuinn  $210Qa" },
		{ "RelicRaider  24", "EmberQueen  23", "CrystalKid  21", "Pickaxe_Pat  19", "SparkyStone  17" },
		{ "Pickaxe_Pat  412 h", "RockyMiner77  388 h", "EmberQueen  351 h", "QuarryQuinn  297 h", "GolemWhisperer  240 h" },
	}
	local medals = { rgb(255, 210, 60), rgb(220, 226, 236), rgb(230, 150, 90), rgb(200, 214, 255), rgb(200, 214, 255) }
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag("Leaderboard") then
			local index = d:GetAttribute("Board")
			for r, text in rows[index] or {} do
				local plate = roblox.Instance.new("Part")
				plate.Name = "SampleRow"
				plate.Anchored = true
				plate.Color = d.Color
				plate.Material = roblox.Enum.Material.Neon
				plate.Size = roblox.Vector3.new(d.Size.X - 0.5, 0.62, 0.05)
				plate.CFrame = d.CFrame * roblox.CFrame.new(0, d.Size.Y / 2 - 1.75 - (r - 1) * 1.0, -d.Size.Z / 2 - 0.03)
				plate.CastShadow = false
				local gui = roblox.Instance.new("SurfaceGui")
				gui.Face = roblox.Enum.NormalId.Front
				gui.LightInfluence = 0
				local label = roblox.Instance.new("TextLabel")
				label.Text = `{r}. {text}`
				label.TextColor3 = medals[r]
				label.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
				label.Parent = gui
				gui.Parent = plate
				plate.Parent = d.Parent
			end
		end
	end
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag("LeaderChampion") then
			local index = d:GetAttribute("Board")
			local board = d.Parent:FindFirstChild("Board" .. index)
			local facing = if board then board.CFrame.LookVector else roblox.Vector3.new(0, 0, -1)
			-- Kit.npc stands with its feet at `base`
			local stand = ChampionService.standCFrame(d, 0, facing)
			local opts = looks[index] or looks[1]
			opts.Name = "ChampionAvatar" .. index
			Kit.npc(d.Parent, stand, opts)
		end
	end
end

return Preview
