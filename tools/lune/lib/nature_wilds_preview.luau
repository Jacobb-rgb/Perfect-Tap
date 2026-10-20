--[[
	Proposals for the nature chat (owner 2026-10-20: "a few pebbles, flowers,
	small bushes or some secrets on the green places", Flora/Wilds.luau).
	  scene "nature_kit"    every piece and secret on a flat meadow, one row per
	                        group (shots nature_kit_* in tools/preview/nature_shots.json)
	  scene "nature_world"  the world with the wilds scattered over the free lawns
	                        (prints where each secret went)
]]

local roblox = require("@lune/roblox") :: any
local process = require("@lune/process")
local process_env_dump = process.env.WILDS_DUMP == "1"

local Preview = {}

-- Rows of the catalogue: z, then the pieces from left to right.
Preview.Rows = {
	{ Z = 0, Step = 5.5, Pieces = { "Pebbles", "Pebbles", "MossRock", "MossRock", "StandingStone" } },
	{ Z = 30, Step = 3.6, Pieces = { "TallGrass", "TallGrass", "TallGrass", "FlowerGrass", "FlowerGrass", "FlowerGrass" } },
	{ Z = 60, Step = 3.8, Pieces = { "Tulips", "Daisies", "Bluebells", "Lavender", "Wildflowers", "Wildflowers" } },
	{ Z = 90, Step = 4.6, Pieces = { "BerryBush", "BerryBush", "BlossomBush", "BlossomBush", "Fern", "Fern" } },
	{ Z = 120, Step = 4.8, Pieces = { "Stump", "Stump", "Log", "Mushrooms", "Mushrooms", "Mushrooms" } },
}
Preview.SecretZ = 170
Preview.SecretSpacing = 30

function Preview.kit(Loader: any, parent: any)
	local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
	local Wilds = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Wilds")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local root = roblox.Instance.new("Model")
	root.Name = "NatureKit"
	root.Parent = parent
	Style.block(root, CF.new(60, -1, 100), V3.new(300, 2, 300), Style.C.Grass, nil, Style.solid())
	for _, row in Preview.Rows do
		for i, name in row.Pieces do
			Wilds.Pieces[name](root, V3.new((i - 1) * row.Step, 0, row.Z), Rng.new(`kit/{name}/{i}`))
		end
	end
	for i, name in Wilds.SecretOrder do
		Wilds.Secrets[name](root, V3.new((i - 1) * Preview.SecretSpacing, 0, Preview.SecretZ), Rng.new(`kit/{name}`))
	end
	return root
end

function Preview.addWilds(Loader: any, map: any)
	local Wilds = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Wilds")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local wilds, secrets = Wilds.build(map, Rng.new("Wilds/preview"))
	local parts = 0
	local kinds: { [string]: number } = {}
	for _, d in wilds:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	for _, group in { wilds.Pieces, wilds.Mountains } do
		for _, piece in group:GetChildren() do
			kinds[piece.Name] = (kinds[piece.Name] or 0) + 1
		end
	end
	print(`Wilds: {parts} parts, {#wilds.Pieces:GetChildren()} pieces in the town, {#wilds.Mountains:GetChildren()} on the mountains`)
	for _, s in wilds.Secrets:GetChildren() do
		local n = 0
		for _, d in s:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		print(`  secret {s.Name}: {n} parts`)
	end
	for name, n in kinds do
		print(`  {name}: {n}`)
	end
	if process_env_dump then
		for _, group in { wilds.Pieces, wilds.Mountains } do
			for _, piece in group:GetChildren() do
				local first = piece:FindFirstChildWhichIsA("BasePart")
				local p = if first then first.CFrame.Position else roblox.Vector3.new(0, 0, 0)
				print(`  piece {group.Name} {piece.Name} {math.floor(p.X)} {math.floor(p.Y)} {math.floor(p.Z)}`)
			end
		end
	end
	for name, p in secrets do
		print(`  secret {name} at {math.floor(p.X)}, {math.floor(p.Y * 10) / 10}, {math.floor(p.Z)}`)
	end
	return map
end

return Preview
