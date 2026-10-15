--[[
	Style kit gallery: one of every lobby Style helper on a flat meadow, so
	tests can run them and the preview can show them (scene "style",
	shots style_* in tools/preview/lobby_shots.json).
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

function Gallery.build(Loader: any, parent: any)
	local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C = Style.C
	local rng = Rng.new("style-gallery")

	local root = roblox.Instance.new("Model")
	root.Name = "StyleGallery"
	root.Parent = parent
	Style.block(root, CF.new(60, -1, 80), V3.new(260, 2, 260), C.Grass, nil, Style.solid())

	-- row 1: trees, bush, flowers
	local kinds = { "Green", "Pink", "Red", "Yellow", "Orange" }
	for i, kind in kinds do
		Style.tree(root, CF.new((i - 1) * 20, 0, 0), kind, rng, if i == 2 then 1.25 else 1)
	end
	Style.bush(root, V3.new(100, 0, 0), C.LeafGreenDark, rng)
	Style.flowers(root, V3.new(110, 0, 0), C.FlowerPurple, rng, 6)
	Style.flowers(root, V3.new(116, 0, 0), C.FlowerYellow, rng, 6)

	-- row 2: lanterns and signs with icons
	Style.lantern(root, CF.new(0, 0, 40), { Kind = "Post", Light = true })
	Style.lantern(root, CF.new(8, 0, 40), { Kind = "Pillar" })
	Style.block(root, CF.new(16, 7, 40), V3.new(4, 0.6, 0.6), C.WoodDark)
	Style.lantern(root, CF.new(16, 6.7, 40), { Kind = "Hanging" })
	Style.lantern(root, CF.new(22, 0, 40), { Kind = "Ground" })
	local wood = Style.sign(root, CF.new(40, 6, 40) * CF.Angles(0, math.pi, 0), "THE GREAT FORGE", 16, 3.4, { Kind = "Wood" })
	local glow = Style.sign(root, CF.new(62, 6, 40) * CF.Angles(0, math.pi, 0), "UPGRADES", 12, 3.4, { Kind = "Glow" })
	Style.sign(root, CF.new(82, 6, 40) * CF.Angles(0, math.pi, 0), "DEPTHS", 10, 3.4, { Kind = "Stone" })
	local _ = wood
	local _g = glow
	local icons = { "CrossedHammers", "CrossedPickaxes", "Gear", "House", "Compass", "Arrow", "ArrowDown", "Coin", "Bone", "Target", "Pickaxe", "Hammer" }
	for i, kind in icons do
		local x = (i - 1) * 7
		local board = Style.sign(root, CF.new(x, 13, 40) * CF.Angles(0, math.pi, 0), "", 6, 6, { Kind = "Wood" })
		Style.icon(root, board.CFrame * CF.new(0, 0, -0.55), kind, 4.5, C.SignText)
	end

	-- row 3: stone ring, wall, roof, awning
	Style.stoneRing(root, V3.new(0, 0, 80), 10, rng, { Glow = C.Fire, Gaps = { { -0.3, 0.3 } } })
	Style.crystal(root, CF.new(0, 1, 80), 12, 3.2, C.Fire)
	Style.stoneWall(root, CF.new(30, 0, 80) * CF.Angles(0, math.pi, 0), V3.new(16, 8, 2), rng)
	Style.block(root, CF.new(58, 5, 80), V3.new(16, 10, 12), C.Stone)
	Style.gableRoof(root, CF.new(58, 10, 80), 18, 14, 7)
	Style.block(root, CF.new(86, 5, 80), V3.new(16, 10, 1), C.WoodLight)
	Style.awning(root, CF.new(86, 10, 80.5) * CF.Angles(0, math.pi, 0), 16, 6, 2.5, C.AwningPink, C.AwningWhite)

	-- row 4: crystals, cliff with waterfall into a pond, fence
	Style.crystalCluster(root, CF.new(0, 0, 120), 9, C.CrystalPurple, rng, { Light = true })
	Style.crystalCluster(root, CF.new(12, 0, 124), 6, C.CrystalBlue, rng)
	Style.voxelCliff(root, CF.new(44, 0, 128) * CF.Angles(0, math.pi, 0), V3.new(30, 18, 10), rng)
	Style.waterfall(root, CF.new(44, 15, 133.6) * CF.Angles(0, math.pi, 0), 15, 5, rng)
	Style.pond(root, V3.new(44, 0, 141), 22, 10, rng, { LilyPads = 4, Koi = 4 })
	Style.fence(root, V3.new(70, 0, 110), V3.new(100, 0, 110), { Caps = true })

	-- row 5: rails, cart, bridge, planks, paths, small props
	Style.rails(root, V3.new(-6, 0, 160), V3.new(24, 0, 160))
	Style.mineCart(root, CF.new(4, 0, 160) * CF.Angles(0, math.pi / 2, 0), rng, { Load = "Gold" })
	Style.mineCart(root, CF.new(14, 0, 160) * CF.Angles(0, math.pi / 2, 0), rng, { Load = "Ore" })
	Style.archBridge(root, V3.new(40, 0, 152), V3.new(40, 0, 168), 8, 2.2, rng)
	Style.planks(root, CF.new(58, 1, 160), V3.new(6, 1, 14), rng)
	Style.path(root, V3.new(70, 0, 150), V3.new(70, 0, 170), 6, rng, { Kind = "Cobble", CurbEvery = 3 })
	Style.path(root, V3.new(80, 0, 150), V3.new(80, 0, 170), 6, rng, { Kind = "Dirt" })
	Style.path(root, V3.new(90, 0, 150), V3.new(90, 0, 170), 6, rng, { Kind = "Plank" })
	Style.crate(root, CF.new(100, 0, 158), rng)
	Style.barrel(root, V3.new(104, 0, 162), rng)
	return root
end

return Gallery
