--[[
	The hopper concepts (Config/HopperConfig, Builders/HopperBuilder):
	  scene "hoppers"  the owner's concept picture (docs/art/hoppers_concept.webp):
	                   the seven hopper cabinets, the Money Laser and SELL in a
	                   row on a stone platform, the mine entrance, block cliffs,
	                   trees and a lookout behind, sunset
	  scene "hopper_shop"  the HOPPER WORKS house (Preview.buildShop), a cosy
	                   Sandbox-Tycoon-style brick + plank house in forge colours:
	                   stepped slate roof, shop windows with hoppers inside,
	                   flower boxes, lanterns, a forge chimney, the like board and
	                   a showcase line (Epic Hopper -> 2X laser -> SELL) in the yard
	UI overlays (Preview.ui, drawn with HopperShopView over the stage):
	  ui_hoppers_pc        PC: HOPPERS tab, the Legendary Hopper picked (two
	                       Epic Hoppers owned, Rift / Terra Core locked)
	  ui_hoppers_pc_more   PC: LASERS tab, the 2X Money Laser picked
	  ui_hoppers_phone     667 x 375 pt phone, the locked Terra Core picked
	Shots in tools/preview/hopper_shots.json.
]]

local Preview = {}

-- x of each hopper on the stage (filled by build)
Preview.Spots = {} :: { [string]: number }

function Preview.build(Loader: any, workspace: any)
	local roblox = Loader.roblox
	local Instance = roblox.Instance
	local V3 = roblox.Vector3
	local CF = Loader.CFrame
	local C3 = roblox.Color3
	local Enum = roblox.Enum
	local NEON = Enum.Material.Neon
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local BlockKit = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlockKit")
	local HopperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HopperBuilder")
	local LaserBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.LaserBuilder")
	local HopperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.HopperConfig")
	local rgb = C3.fromRGB

	local stage = Instance.new("Model")
	stage.Name = "HopperStage"
	stage.Parent = workspace
	local function cube(cf: any, size: any, face: any, rim: any, mode: string?): any
		return BlockKit.cube(stage, cf, size, face, rim, mode)
	end
	local GRASS, GRASS_RIM = rgb(84, 168, 60), rgb(56, 124, 42)
	local DIRT, DIRT_RIM = rgb(132, 96, 64), rgb(94, 66, 42)
	local STONE, STONE_RIM = rgb(104, 100, 126), rgb(70, 66, 92)
	local TILE, TILE_RIM = rgb(176, 174, 196), rgb(134, 132, 160)
	local WOOD, WOOD_RIM = rgb(126, 80, 44), rgb(86, 52, 26)

	-- the row: 7 hoppers, the Money Laser and SELL, 8 studs apart
	local spacing = 7.2
	local items = #HopperConfig.List + 2
	local firstX = -(items - 1) * spacing / 2

	-- grass in front, the stone platform with tiles, the glowing dots along its edge
	Geo.block(stage, CF.new(0, -0.5, 20), V3.new(260, 1, 60), GRASS, Enum.Material.Grass)
	cube(CF.new(0, 0.5, 0), V3.new(items * spacing + 6, 1, 16), TILE, TILE_RIM)
	for i = 0, items * 2 + 2 do
		local x = -(items * spacing + 6) / 2 + i * 4 + 1
		Geo.block(stage, CF.new(x, 1.01, 0), V3.new(0.08, 0.02, 16), TILE_RIM)
	end
	for j = -3, 3 do
		Geo.block(stage, CF.new(0, 1.01, j * 4 / 1.0 * 0.5 * 2 / 2 * 2), V3.new(items * spacing + 6, 0.02, 0.08), TILE_RIM)
	end
	cube(CF.new(0, 0.35, 9.5), V3.new(items * spacing + 6, 0.7, 3), TILE, TILE_RIM)
	for i = 1, items do
		local x = firstX + (i - 1) * spacing
		local color = if i <= #HopperConfig.List
			then HopperBuilder.Styles[HopperConfig.List[i].Id].Color
			elseif i == items - 1 then LaserBuilder.Color
			else rgb(0, 160, 255)
		Geo.block(stage, CF.new(x, 0.55, 11.05), V3.new(0.9, 0.5, 0.1), color:Lerp(C3.new(1, 1, 1), 0.3), NEON)
	end
	-- block grass tufts and white flowers along the front
	for i = 1, 16 do
		local x = -58 + i * 7.3 + (i % 3)
		cube(CF.new(x, 0.5, 15 + (i % 4)), V3.new(2, 1, 2), GRASS, GRASS_RIM, "flat")
		if i % 3 == 0 then
			Geo.block(stage, CF.new(x + 0.4, 1.1, 15.5 + (i % 4)), V3.new(0.35, 0.35, 0.35), rgb(255, 255, 240))
		end
	end

	-- the hoppers, the laser and SELL
	for i, hopper in HopperConfig.List do
		local x = firstX + (i - 1) * spacing
		Preview.Spots[hopper.Id] = x
		HopperBuilder.build(hopper.Id, CF.new(x, 1, -1)).Parent = stage
	end
	local laserX = firstX + #HopperConfig.List * spacing
	Preview.Spots.Laser = laserX
	LaserBuilder.build(CF.new(laserX, 1, -1)).Parent = stage
	-- SELL: a blue block machine with a dark screen and an intake slot
	local sellX = laserX + spacing
	Preview.Spots.Collector = sellX
	local blue, blueRim = rgb(30, 110, 230), rgb(14, 56, 130)
	cube(CF.new(sellX, 1.35, -1), V3.new(5.4, 0.7, 5), blue, blueRim)
	Geo.block(stage, CF.new(sellX, 1.73, -1), V3.new(5.1, 0.08, 4.7), rgb(0, 180, 255), NEON)
	cube(CF.new(sellX, 4.0, -1.3), V3.new(4.6, 4.6, 3.8), blue, blueRim)
	cube(CF.new(sellX, 6.6, -1.3), V3.new(5.0, 0.6, 4.2), rgb(70, 150, 255), blueRim)
	BlockKit.text(
		stage,
		CF.new(sellX, 4.9, 0.62),
		V3.new(3.6, 1.8, 0.08),
		"SELL",
		C3.new(1, 1, 1),
		rgb(10, 30, 70),
		rgb(0, 180, 255),
		Enum.Font.LuckiestGuy
	)
	cube(CF.new(sellX, 2.6, 0.9), V3.new(3.6, 1.0, 1.6), rgb(16, 30, 60), rgb(8, 16, 34))
	for k = 1, 3 do
		Geo.block(stage, CF.new(sellX, 2.95, 0.3 + k * 0.4), V3.new(3.2, 0.06, 0.12), rgb(0, 180, 255), NEON)
	end

	-- behind: stone terraces and cliffs with grass on top, the mine entrance, trees, lamps
	for i = 0, 13 do
		local x = -78 + i * 12
		local h = 6 + (i % 3) * 3 + (if i % 4 == 0 then 4 else 0)
		cube(CF.new(x, h / 2, -16 - (i % 2) * 3), V3.new(12.2, h, 10), if i % 2 == 0 then STONE else rgb(90, 86, 114), STONE_RIM)
		cube(CF.new(x, h + 0.5, -16 - (i % 2) * 3), V3.new(12.2, 1, 10), GRASS, GRASS_RIM)
		cube(CF.new(x + 3, h - 1.5, -10.9 - (i % 2) * 3), V3.new(3, 2, 0.4), DIRT, DIRT_RIM, "flat")
	end
	-- the mine entrance (left), wooden frame, the MINE sign, two lanterns
	local mx = firstX + 4
	Geo.block(stage, CF.new(mx, 4.5, -10.7), V3.new(9, 8, 0.4), rgb(14, 12, 22))
	for _, side in { -1, 1 } do
		cube(CF.new(mx + side * 5, 5, -10.2), V3.new(1.2, 10, 1.2), WOOD, WOOD_RIM, "side")
		cube(CF.new(mx + side * 6.2, 6.8, -9.6), V3.new(0.7, 1.0, 0.7), rgb(40, 34, 30), rgb(20, 16, 14), "flat")
		Geo.block(stage, CF.new(mx + side * 6.2, 6.8, -9.6), V3.new(0.5, 0.7, 0.75), rgb(255, 176, 70), NEON)
	end
	cube(CF.new(mx, 10.4, -10.2), V3.new(12.4, 1.2, 1.4), WOOD, WOOD_RIM)
	BlockKit.text(
		stage,
		CF.new(mx, 12.0, -9.9),
		V3.new(6, 1.8, 0.3),
		"MINE",
		rgb(255, 226, 170),
		rgb(92, 58, 32),
		rgb(150, 100, 56),
		Enum.Font.LuckiestGuy
	)
	for k = 1, 3 do
		Geo.block(stage, CF.new(mx - 2 + k * 1.2, 2.4 + k * 0.7, -10.4), V3.new(0.5, 0.5, 0.3), rgb(255, 220, 90), NEON)
	end
	-- block trees on the cliffs
	for _, t in { { -66, 14, -18 }, { -56, 11, -20 }, { -30, 13, -19 }, { -6, 10, -18 }, { 22, 13, -19 }, { 46, 16, -18 }, { 64, 11, -20 } } do
		local x, y, z = t[1], t[2], t[3]
		cube(CF.new(x, y + 2, z), V3.new(1.4, 4, 1.4), WOOD, WOOD_RIM, "side")
		cube(CF.new(x, y + 5, z), V3.new(6, 3, 6), GRASS, GRASS_RIM)
		cube(CF.new(x, y + 7, z), V3.new(4, 1.6, 4), rgb(96, 182, 70), GRASS_RIM)
	end
	-- a wooden lookout on the right cliff
	local wx = 58
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		cube(CF.new(wx + c[1] * 2.4, 16, -19 + c[2] * 2.4), V3.new(0.8, 8, 0.8), WOOD, WOOD_RIM, "side")
	end
	cube(CF.new(wx, 20.2, -19), V3.new(6.4, 0.6, 6.4), WOOD, WOOD_RIM)
	cube(CF.new(wx, 23.6, -19), V3.new(7, 0.8, 7), rgb(150, 92, 52), WOOD_RIM)
	Geo.block(stage, CF.new(wx, 21.4, -15.9), V3.new(0.6, 0.8, 0.2), rgb(255, 176, 70), NEON)
	-- lamps on the platform's ends
	for _, x in { firstX - 6, -(firstX - 6) } do
		cube(CF.new(x, 3, 3), V3.new(0.5, 4, 0.5), rgb(60, 52, 52), rgb(30, 26, 26), "flat")
		local bulb = Geo.block(stage, CF.new(x, 5.4, 3), V3.new(1, 1, 1), rgb(255, 185, 70), NEON)
		local glow = Instance.new("PointLight")
		glow.Color = rgb(255, 185, 70)
		glow.Brightness = 2
		glow.Range = 12
		glow.Parent = bulb
	end
	print(string.format("Hopper row: %d hoppers, laser at x %.1f, SELL at x %.1f", #HopperConfig.List, laserX, sellX))
	return stage
end

function Preview.ui(Loader: any): { [string]: any }
	local UiExport = require("./uiexport")
	local roblox = Loader.roblox
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HopperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.HopperConfig")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local HopperShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HopperShopView")

	local coins, income = 41.6e9, 2.9e6
	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = 0.62 * 900 / 375
	local function hud(uiScale: number): any
		local refs = HudBubble.buildGame(if uiScale > 1.4 then 0.62 else 1.25)
		TeleportView.build(refs.TopBar, if uiScale > 1.4 then 0.62 else 1.25, 1600 / uiScale)
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(coins)
		refs.Income.Text = Format.perSecond(income)
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		refs.Toasts:ClearAllChildren()
		return refs
	end
	local function shop(uiScale: number, w: number, h: number, tab: string, pick: string): any
		local refs = HopperShopView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		HopperShopView.layout(refs, w, h)
		HopperShopView.setTab(refs, tab)
		local states = {}
		for _, hopper in HopperConfig.List do
			states[hopper.Id] = {
				Owned = if hopper.Id == "EpicHopper" then 2 else 0,
				CanAfford = hopper.Price <= coins,
				Locked = if hopper.Order == 6 then "REBIRTH 1" elseif hopper.Order == 7 then "REBIRTH 3" else nil,
			}
		end
		local laser = HopperConfig.Laser
		states[laser.Id] = { Owned = 1, CanAfford = laser.Price <= coins }
		for id, state in states do
			HopperShopView.setTile(refs, id, state)
		end
		HopperShopView.showDetail(refs, pick, states[pick])
		HopperShopView.setCounts(refs, "Hoppers 2/4  ·  Lasers 1/4")
		HopperShopView.setStatus(refs, "Bought Epic Hopper! Place it on a belt in Build mode.")
		return refs
	end
	local exports: { [string]: any } = {}
	local pcW, pcH = 1600 / scale, (900 - 36) / scale
	exports.ui_hoppers_pc = UiExport.export({ hud(scale).Gui, shop(scale, pcW, pcH, "Hoppers", "LegendaryHopper").Gui })
	exports.ui_hoppers_pc_more = UiExport.export({ hud(scale).Gui, shop(scale, pcW, pcH, "Lasers", "MoneyLaser2X").Gui })
	exports.ui_hoppers_phone = UiExport.export({
		hud(phoneScale).Gui,
		shop(phoneScale, 1600 / phoneScale, (900 - 58) / phoneScale, "Hoppers", "TerraCoreHopper").Gui,
	})
	return exports
end

function Preview.buildShop(Loader: any, workspace: any)
	local roblox = Loader.roblox
	local Instance = roblox.Instance
	local V3 = roblox.Vector3
	local CF = Loader.CFrame
	local C3 = roblox.Color3
	local Enum = roblox.Enum
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local BlockKit = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlockKit")
	local HopperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HopperBuilder")
	local LaserBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.LaserBuilder")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local rgb = C3.fromRGB
	local rng = Rng.new(2026)

	local shop = Instance.new("Model")
	shop.Name = "HopperWorks"
	shop.Parent = workspace
	-- the block palette (Sandbox Tycoon's brick + plank + stone house, in forge colours)
	local BRICK, BRICK_DARK, MORTAR = rgb(178, 82, 58), rgb(138, 58, 42), rgb(214, 190, 168)
	local PLANK, PLANK_RIM = rgb(196, 140, 84), rgb(140, 92, 50)
	local LOG, LOG_RIM = rgb(112, 76, 46), rgb(70, 46, 28)
	local STONE, STONE_RIM = rgb(150, 150, 158), rgb(98, 98, 108)
	local SLATE, SLATE_RIM = rgb(70, 78, 96), rgb(42, 46, 60)
	local GLOW = rgb(255, 176, 70)
	local function cube(cf: any, size: any, face: any, rim: any, mode: string?): any
		return BlockKit.cube(shop, cf, size, face, rim, mode)
	end
	local function flat(cf: any, size: any, color: any, material: any?): any
		return Geo.block(shop, cf, size, color, material)
	end

	-- the ground: grass, a tile plaza, a plank path to the door
	flat(CF.new(0, -0.5, 0), V3.new(240, 1, 180), rgb(104, 182, 76), Enum.Material.Grass)
	flat(CF.new(0, 0.05, 10), V3.new(76, 0.1, 30), rgb(226, 232, 242))
	for i = -19, 19 do
		flat(CF.new(i * 2, 0.11, 10), V3.new(0.1, 0.02, 30), rgb(190, 204, 226))
	end
	for j = -7, 7 do
		flat(CF.new(0, 0.11, 10 + j * 2), V3.new(76, 0.02, 0.1), rgb(190, 204, 226))
	end

	-- the house: W wide (x), D deep (z), walls H high; the front faces +Z at z0
	local W, D, H = 34, 20, 11
	local z0 = -5
	local zc = z0 - D / 2
	local foundation = 1.2
	cube(CF.new(0, foundation / 2, zc), V3.new(W + 1, foundation, D + 1), STONE, STONE_RIM)

	-- a brick wall from x1 to x2 at z (front/back) or along z (sides) with mortar lines and darker bricks
	local function brickWall(cf: any, length: number, height: number, thickness: number)
		flat(cf, V3.new(length, height, thickness), BRICK)
		for row = 1, math.floor(height) - 1 do
			flat(cf * CF.new(0, -height / 2 + row, thickness / 2 + 0.01), V3.new(length, 0.1, 0.04), MORTAR)
		end
		for _ = 1, math.floor(length * height / 14) do
			local bx = rng:range(-length / 2 + 1, length / 2 - 1)
			local by = math.floor(rng:range(0, height - 1)) + 0.5 - height / 2
			flat(cf * CF.new(bx, by, thickness / 2 + 0.02), V3.new(1.9, 0.86, 0.04), BRICK_DARK)
		end
	end
	local wallY = foundation + H / 2
	-- the front wall in pieces around the door and the two shop windows
	local door, winW, winH, winY = 5, 7, 5, foundation + 2.2
	local pieces = {
		{ -W / 2 + 1.5, -door / 2 - winW - 3 }, -- left of the left window
		{ -door / 2 - 1.5, -door / 2 }, -- between left window and door (narrow)
		{ door / 2, door / 2 + 1.5 },
		{ door / 2 + winW + 3, W / 2 - 1.5 },
	}
	local lwx = -door / 2 - 1.5 - winW / 2 -- left window centre
	local rwx = -lwx
	pieces[1][2] = lwx - winW / 2
	pieces[2] = { lwx + winW / 2, -door / 2 }
	pieces[3] = { door / 2, rwx - winW / 2 }
	pieces[4] = { rwx + winW / 2, W / 2 - 1.5 }
	for _, piece in pieces do
		local x1, x2 = piece[1], piece[2]
		brickWall(CF.new((x1 + x2) / 2, wallY, z0), x2 - x1, H, 1)
	end
	-- above / below the windows and above the door
	for _, wx in { lwx, rwx } do
		local below = winY - winH / 2 - foundation
		brickWall(CF.new(wx, foundation + below / 2, z0), winW, below, 1)
		local above = foundation + H - (winY + winH / 2)
		brickWall(CF.new(wx, foundation + H - above / 2, z0), winW, above, 1)
	end
	local doorH = 7
	brickWall(CF.new(0, foundation + doorH + (H - doorH) / 2, z0), door, H - doorH, 1)
	-- back and side walls
	brickWall(CF.new(0, wallY, z0 - D), W, H, 1)
	for _, sx in { -1, 1 } do
		brickWall(CF.new(sx * (W / 2 - 0.5), wallY, zc) * CF.Angles(0, sx * math.pi / 2, 0), D, H, 1)
	end
	-- log corner posts and a plank band under the roof
	for _, c in { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } } do
		cube(CF.new(c[1] * (W / 2 - 0.2), foundation + H / 2, zc + c[2] * (D / 2 - 0.2)), V3.new(1.6, H, 1.6), LOG, LOG_RIM, "side")
	end
	cube(CF.new(0, foundation + H - 0.5, z0 + 0.35), V3.new(W + 1.2, 1.0, 0.6), PLANK, PLANK_RIM)
	-- the floor inside (planks) and a warm light along the back wall
	flat(CF.new(0, foundation + 0.05, zc), V3.new(W - 2, 0.1, D - 2), PLANK)
	for i = -7, 7 do
		flat(CF.new(i * 2.2, foundation + 0.11, zc), V3.new(0.08, 0.02, D - 2), PLANK_RIM)
	end
	flat(CF.new(0, foundation + H - 1.4, z0 - D + 0.56), V3.new(W - 6, 0.25, 0.1), GLOW, NEON)

	-- the shop windows: plank frames, a cross, glass; two small hoppers on show inside
	for i, wx in { lwx, rwx } do
		local f = CF.new(wx, winY, z0 + 0.35)
		for _, dy in { -1, 1 } do
			cube(f * CF.new(0, dy * (winH / 2 + 0.25), 0), V3.new(winW + 1, 0.5, 0.7), PLANK, PLANK_RIM, "side")
		end
		for _, dx in { -1, 1 } do
			cube(f * CF.new(dx * (winW / 2 + 0.25), 0, 0), V3.new(0.5, winH, 0.7), PLANK, PLANK_RIM, "side")
		end
		flat(f, V3.new(0.3, winH, 0.3), PLANK_RIM)
		flat(f, V3.new(winW, 0.3, 0.3), PLANK_RIM)
		Geo.block(shop, f * CF.new(0, 0, -0.1), V3.new(winW, winH, 0.1), rgb(200, 236, 255), GLASS, { Transparency = 0.6 })
		-- the flower box under the window
		cube(f * CF.new(0, -winH / 2 - 1.0, 0.5), V3.new(winW, 0.8, 1.0), LOG, LOG_RIM, "side")
		for k = 1, 5 do
			local fx = -winW / 2 + k * winW / 6
			flat(f * CF.new(fx, -winH / 2 - 0.35, 0.5), V3.new(0.9, 0.5, 0.7), rgb(70, 150, 60))
			flat(
				f * CF.new(fx, -winH / 2 + 0.05, 0.5),
				V3.new(0.4, 0.4, 0.4),
				if (k + i) % 2 == 0 then rgb(255, 90, 120) else rgb(255, 214, 60)
			)
		end
		local id = if i == 1 then "HeartHopper" else "StarHopper"
		local show = CF.new(wx, foundation + 0.2, z0 - 4) * CF.Angles(0, if i == 1 then 0.3 else -0.3, 0)
		local model = HopperBuilder.build(id, show)
		BlockKit.scale(model, show, 0.55)
		model.Parent = shop
	end

	-- the door: two plank leaves with handles, a little lantern each side
	for _, dx in { -1, 1 } do
		cube(CF.new(dx * door / 4, foundation + doorH / 2, z0 + 0.1), V3.new(door / 2 - 0.1, doorH, 0.4), PLANK, PLANK_RIM)
		flat(CF.new(dx * 0.5, foundation + doorH / 2, z0 + 0.36), V3.new(0.3, 0.6, 0.2), rgb(250, 200, 60))
		local lx = dx * (door / 2 + 0.9)
		cube(CF.new(lx, foundation + doorH - 0.4, z0 + 0.9), V3.new(0.9, 1.2, 0.9), rgb(40, 40, 48), rgb(20, 20, 26), "flat")
		flat(CF.new(lx, foundation + doorH - 0.4, z0 + 0.9), V3.new(0.62, 0.8, 0.95), GLOW, NEON)
	end
	cube(CF.new(0, foundation + doorH + 0.3, z0 + 0.4), V3.new(door + 1.2, 0.6, 0.8), PLANK, PLANK_RIM)
	-- plank steps up to the door
	for k = 1, 2 do
		cube(CF.new(0, foundation - k * 0.4 + 0.2, z0 + 0.5 + k * 1.0), V3.new(door + 2, 0.4 * (3 - k), 1.0), PLANK, PLANK_RIM)
	end

	-- the stepped roof: slate blocks stepping in toward the ridge (it runs front to back),
	-- the front gable filled with planks and a pixel hopper
	local layers = 8
	local step = (W + 2) / (2 * layers)
	for k = 0, layers - 1 do
		local w = W + 2 - 2 * k * step
		cube(CF.new(0, foundation + H + 0.5 + k, zc), V3.new(w, 1.0, D + 2.4), SLATE, SLATE_RIM, "all")
		local gw = w - 2 * step - 0.4
		if gw > 0.6 then
			cube(CF.new(0, foundation + H + 0.5 + k, z0 + 1.35), V3.new(gw, 1.0, 0.4), PLANK, PLANK_RIM, "side")
		end
	end
	BlockKit.pixelArt(shop, CF.new(0, foundation + H + 3.2, z0 + 1.7), {
		"#######",
		".#ooo#.",
		"..#o#..",
		"...#...",
		"..#.#..",
	}, 0.6, { ["#"] = rgb(250, 196, 64), o = rgb(255, 120, 60) }, 0.3)
	-- a covered porch along the front: log posts, a slate roof, a plank deck
	local porch = 3.4
	cube(CF.new(0, foundation - 0.1, z0 + 0.5 + porch / 2), V3.new(W - 2, 0.4, porch), PLANK, PLANK_RIM)
	for _, px in { -W / 2 + 1.5, -door / 2 - 0.8, door / 2 + 0.8, W / 2 - 1.5 } do
		cube(CF.new(px, foundation + 4.1, z0 + porch), V3.new(0.7, 8.2, 0.7), LOG, LOG_RIM, "side")
	end
	cube(CF.new(0, foundation + 8.45, z0 + porch / 2 + 0.4), V3.new(W + 0.4, 0.5, porch + 1.2), SLATE, SLATE_RIM)
	cube(CF.new(0, foundation + 8.1, z0 + porch + 0.6), V3.new(W + 0.4, 0.3, 0.3), PLANK, PLANK_RIM, "flat")

	-- the HOPPER WORKS board on the porch roof, the small board under it
	BlockKit.text(
		shop,
		CF.new(0, foundation + 10.1, z0 + 3.9),
		V3.new(16, 2.4, 0.3),
		"HOPPER WORKS",
		rgb(255, 238, 190),
		rgb(86, 54, 30),
		GLOW,
		Enum.Font.LuckiestGuy
	)
	BlockKit.text(
		shop,
		CF.new(0, foundation + 7.6, z0 + 3.95),
		V3.new(9, 0.7, 0.12),
		"THE BIGGEST MACHINES IN TERRA",
		rgb(255, 250, 236),
		rgb(40, 30, 26),
		nil
	)

	-- the forge chimney on the right: stone blocks, a glowing top and smoke cubes
	local chx = W / 2 - 5
	for k = 0, 7 do
		cube(
			CF.new(chx, foundation + H + 0.5 + k * 1.0, zc - 3),
			V3.new(2.6, 1.0, 2.6),
			if k % 2 == 0 then STONE else rgb(132, 132, 140),
			STONE_RIM
		)
	end
	flat(CF.new(chx, foundation + H + 8.05, zc - 3), V3.new(1.8, 0.1, 1.8), rgb(255, 110, 30), NEON)
	for k, p in { V3.new(0.2, 9.2, 0), V3.new(-0.5, 10.4, 0.3), V3.new(0.6, 11.8, -0.2) } do
		local size = 0.9 + k * 0.35
		Geo.block(
			shop,
			CF.new(chx + p.X, foundation + H + p.Y, zc - 3 + p.Z) * CF.Angles(0, k * 0.5, 0),
			V3.new(size, size, size),
			rgb(220, 220, 228),
			nil,
			{ Transparency = 0.25 + k * 0.12 }
		)
	end

	-- the like board by the path (the tycoon's "liked plots"): a pixel heart and the count
	local lb = CF.new(11, 0, 9)
	for _, dx in { -2.4, 2.4 } do
		cube(lb * CF.new(dx, 1.6, 0), V3.new(0.6, 3.2, 0.6), LOG, LOG_RIM, "flat")
	end
	BlockKit.text(
		shop,
		lb * CF.new(0, 3.6, 0.1),
		V3.new(6.4, 2.0, 0.3),
		"♥ 12,480 LIKES",
		rgb(255, 130, 170),
		rgb(40, 24, 30),
		rgb(255, 120, 160)
	)
	BlockKit.pixelArt(shop, lb * CF.new(0, 5.6, 0.1), {
		".##.##.",
		"#######",
		".#####.",
		"..###..",
		"...#...",
	}, 0.4, { ["#"] = rgb(255, 80, 130) }, 0.4)

	-- a showcase line in the yard: Epic Hopper -> 2X laser -> SELL
	local lineZ = 6
	local hx = -40
	HopperBuilder.build("EpicHopper", CF.new(hx, 0.1, lineZ)).Parent = shop
	local lx = hx + HopperBuilder.Plate / 2 + LaserBuilder.Length / 2
	LaserBuilder.build(CF.new(lx, 0.1, lineZ)).Parent = shop
	local sx = lx + LaserBuilder.Length / 2 + 2.6
	BlockKit.cube(shop, CF.new(sx, 1.7, lineZ), V3.new(5.2, 3.2, 4.4), rgb(54, 120, 220), rgb(28, 64, 150))
	BlockKit.cube(shop, CF.new(sx, 3.55, lineZ), V3.new(5.6, 0.5, 4.8), rgb(238, 242, 250), rgb(176, 186, 206))
	BlockKit.text(
		shop,
		CF.new(sx, 1.7, lineZ + 2.26),
		V3.new(3.6, 0.9, 0.08),
		"SELL",
		rgb(255, 250, 236),
		rgb(20, 24, 36),
		rgb(90, 255, 110)
	)

	-- lamp posts along the plaza (block lanterns)
	for _, x in { -32, -14, 14, 32 } do
		cube(CF.new(x, 2.2, 22), V3.new(0.6, 4.4, 0.6), rgb(52, 50, 58), rgb(30, 30, 36), "flat")
		cube(CF.new(x, 4.9, 22), V3.new(1.3, 1.4, 1.3), rgb(52, 50, 58), rgb(30, 30, 36), "flat")
		flat(CF.new(x, 4.9, 22), V3.new(0.95, 1.0, 1.35), GLOW, NEON)
	end
	-- block trees on both sides
	for _, t in { { -44, -8 }, { 44, -8 }, { -40, -24 }, { 42, -22 } } do
		cube(CF.new(t[1], 2.5, t[2]), V3.new(1.4, 5, 1.4), LOG, LOG_RIM, "side")
		cube(CF.new(t[1], 6.2, t[2]), V3.new(5, 3.4, 5), rgb(76, 160, 62), rgb(50, 116, 44))
		cube(CF.new(t[1], 8.4, t[2]), V3.new(3, 1.6, 3), rgb(76, 160, 62), rgb(50, 116, 44))
	end
	print("Hopper Works house built")
	return shop
end

return Preview
