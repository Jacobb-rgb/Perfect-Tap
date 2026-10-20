--[[
	The wilds kit (owner 2026-10-20, nature chat: "a few pebbles, flowers, small
	bushes or some secrets on the green places", Flora/Wilds.luau): scene
	"nature_kit" lays every piece and secret on a flat meadow, one row per group
	(shots nature_kit_* in tools/preview/nature_shots.json). The scattered wilds
	are part of scene "world" (shots wilds_* in the same file).
]]

local roblox = require("@lune/roblox") :: any

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

return Preview
