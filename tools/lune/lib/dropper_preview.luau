--[[
	The dropper concepts (Config/DropperConfig, Builders/DropperBuilder):
	  scene "droppers"  the owner's pictures (docs/art/hoppers_concept.webp for the scene,
	                   docs/art/droppers_concept.webp for the droppers):
	                   the seven droppers, the Money Laser and SELL in a
	                   row on a stone platform, the mine entrance, block cliffs,
	                   trees and a lookout behind, sunset
	  scene "dropper_shop"  the DROPPERS house (Preview.buildShop), a cosy
	                   Sandbox-Tycoon-style brick + plank house in forge colours:
	                   stepped slate roof, shop windows with droppers inside,
	                   flower boxes, lanterns, a forge chimney, the like board and
	                   a showcase line (Basic Dropper -> 2X laser -> SELL) in the yard
	UI overlays (Preview.ui, drawn with DropperShopView over the stage):
	  ui_droppers_pc        PC: DROPPERS tab, the Blue Dropper picked (two
	                       Basic Droppers owned, Rainbow / Dark Matter locked)
	  ui_droppers_pc_more   PC: LASERS tab, the 2X Money Laser picked
	  ui_droppers_phone     667 x 375 pt phone, the locked Dark Matter picked
	Shots in tools/preview/dropper_shots.json.
]]

local Preview = {}

-- x of each dropper on the stage (filled by build)
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
	local DropperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.DropperBuilder")
	local LaserBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.LaserBuilder")
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
	local rgb = C3.fromRGB

	local stage = Instance.new("Model")
	stage.Name = "DropperStage"
	stage.Parent = workspace
	local function cube(cf: any, size: any, face: any, rim: any, mode: string?): any
		return BlockKit.cube(stage, cf, size, face, rim, mode)
	end
	local GRASS, GRASS_RIM = rgb(84, 168, 60), rgb(56, 124, 42)
	local DIRT, DIRT_RIM = rgb(132, 96, 64), rgb(94, 66, 42)
	local STONE, STONE_RIM = rgb(104, 100, 126), rgb(70, 66, 92)
	local TILE, TILE_RIM = rgb(176, 174, 196), rgb(134, 132, 160)
	local WOOD, WOOD_RIM = rgb(126, 80, 44), rgb(86, 52, 26)

	-- the row: 7 droppers, the Money Laser and SELL, 8 studs apart
	local spacing = 10
	local items = #DropperConfig.List + 2
	local firstX = -(items - 1) * spacing / 2

	-- grass in front, the stone platform with tiles, the glowing dots along its edge
	Geo.block(stage, CF.new(0, -0.5, 20), V3.new(260, 1, 60), GRASS, Enum.Material.Grass)
	cube(CF.new(0, 0.5, -1), V3.new(items * spacing + 6, 1, 20), TILE, TILE_RIM)
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
		local color = if i <= #DropperConfig.List
			then DropperBuilder.Styles[DropperConfig.List[i].Id].Glow[1]
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

	-- the droppers, the laser and SELL
	for i, dropper in DropperConfig.List do
		local x = firstX + (i - 1) * spacing
		Preview.Spots[dropper.Id] = x
		DropperBuilder.build(dropper.Id, CF.new(x, 1, -1) * CF.Angles(0, 0.3, 0)).Parent = stage
	end
	local laserX = firstX + #DropperConfig.List * spacing
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
	print(string.format("Dropper row: %d droppers, laser at x %.1f, SELL at x %.1f", #DropperConfig.List, laserX, sellX))
	return stage
end

function Preview.ui(Loader: any): { [string]: any }
	local UiExport = require("./uiexport")
	local roblox = Loader.roblox
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local DropperShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.DropperShopView")

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
		local refs = DropperShopView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		DropperShopView.layout(refs, w, h)
		DropperShopView.setTab(refs, tab)
		local states = {}
		for _, dropper in DropperConfig.List do
			states[dropper.Id] = {
				Owned = if dropper.Id == "BasicDropper" then 2 else 0,
				CanAfford = dropper.Price <= coins,
				Locked = if dropper.Order == 6 then "REBIRTH 1" elseif dropper.Order == 7 then "REBIRTH 3" else nil,
			}
		end
		local laser = DropperConfig.Laser
		states[laser.Id] = { Owned = 1, CanAfford = laser.Price <= coins }
		for id, state in states do
			DropperShopView.setTile(refs, id, state)
		end
		DropperShopView.showDetail(refs, pick, states[pick])
		DropperShopView.setCounts(refs, "Droppers 2/4  ·  Lasers 1/4")
		DropperShopView.setStatus(refs, "Bought Basic Dropper! Place it on your plot in Build mode.")
		return refs
	end
	local exports: { [string]: any } = {}
	local pcW, pcH = 1600 / scale, (900 - 36) / scale
	exports.ui_droppers_pc = UiExport.export({ hud(scale).Gui, shop(scale, pcW, pcH, "Droppers", "BlueDropper").Gui })
	exports.ui_droppers_pc_more = UiExport.export({ hud(scale).Gui, shop(scale, pcW, pcH, "Lasers", "MoneyLaser2X").Gui })
	exports.ui_droppers_phone = UiExport.export({
		hud(phoneScale).Gui,
		shop(phoneScale, 1600 / phoneScale, (900 - 58) / phoneScale, "Droppers", "DarkMatterDropper").Gui,
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
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local DropperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.DropperBuilder")
	local LaserBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.LaserBuilder")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	-- the town's own building kit, so the house looks like the rest of the map
	local Style = Loader.requirePath("ServerScriptService.Server.World.Lobby.Style")
	local C = Style.C
	local rgb = C3.fromRGB
	local rng = Rng.new(2026)

	local shop = Instance.new("Model")
	shop.Name = "DroppersHouse"
	shop.Parent = workspace
	-- frames: Style's front is the LookVector; FRONT turns it to world +Z (toward the plaza)
	local FRONT = CF.Angles(0, math.pi, 0)
	local function fr(x: number, y: number, z: number): any
		return CF.new(x, y, z) * FRONT
	end
	local function block(cf: any, size: any, color: any, material: any?, tiny: boolean?): any
		return Style.block(shop, cf, size, color, material, if tiny then Style.tiny() else nil)
	end

	-- the ground: grass, a flagstone yard, a cobble path to the door
	Geo.block(shop, CF.new(0, -0.5, 0), V3.new(240, 1, 180), C.Grass, Enum.Material.Grass)
	block(CF.new(0, 0.05, 10), V3.new(78, 0.1, 32), C.Flag)
	for i = -9, 9 do
		block(CF.new(i * 4.2, 0.11, 10), V3.new(0.18, 0.04, 32), C.FlagDark, nil, true)
	end
	for j = -3, 3 do
		block(CF.new(0, 0.11, 10 + j * 4.5), V3.new(78, 0.04, 0.18), C.FlagDark, nil, true)
	end
	Style.path(shop, V3.new(0, 0.1, -3), V3.new(0, 0.1, 26), 6, rng, { Kind = "Cobble" })

	-- the house: W wide, D deep, a stone ground floor and a timber-framed upper floor
	local W, D = 30, 16
	local z0 = -6 -- the front wall
	local zc = z0 - D / 2
	local plinth, ground, upper = 1.2, 6, 5
	local floor1 = plinth + ground
	local eave = floor1 + upper

	-- plinth: a band of dark cobbles all round
	block(CF.new(0, plinth / 2, zc), V3.new(W + 1.2, plinth, D + 1.2), C.CobbleDark)
	for i = 0, 13 do
		local x = -W / 2 + 1 + i * (W - 2) / 13
		block(CF.new(x, plinth / 2, z0 + 0.62), V3.new(1.6, 0.7, 0.2), Style.vary(C.Cobble, rng, 0.08), nil, true)
	end

	-- ground floor: voxel stone walls with stones and mortar lines (the town's stoneWall)
	Style.stoneWall(shop, fr(0, plinth, z0), V3.new(W, ground, 1), rng, { Cap = false, Density = 0.55 })
	Style.stoneWall(
		shop,
		CF.new(-W / 2 + 0.5, plinth, zc) * CF.Angles(0, math.pi / 2, 0),
		V3.new(D, ground, 1),
		rng,
		{ Cap = false, Density = 0.4 }
	)
	Style.stoneWall(
		shop,
		CF.new(W / 2 - 0.5, plinth, zc) * CF.Angles(0, -math.pi / 2, 0),
		V3.new(D, ground, 1),
		rng,
		{ Cap = false, Density = 0.4 }
	)
	block(CF.new(0, plinth + ground / 2, z0 - D + 0.5), V3.new(W, ground, 1), C.Stone)
	-- corner quoins: big light stones stacked at the corners
	for _, sx in { -1, 1 } do
		for k = 0, 2 do
			local y = plinth + 1 + k * 2
			block(CF.new(sx * (W / 2 - 0.6), y, z0 + 0.2), V3.new(1.6, 1.4, 1.4), Style.vary(C.StoneLight, rng, 0.04))
			block(CF.new(sx * (W / 2 - 0.2), y + 1, z0 - 0.6), V3.new(1.4, 0.9, 1.6), Style.vary(C.StoneLight, rng, 0.04))
		end
	end

	-- upper floor: cream plaster panels in a dark timber frame
	local PLASTER = rgb(238, 222, 190)
	local BEAM = C.WoodDark
	block(CF.new(0, floor1 + upper / 2, zc), V3.new(W, upper, D), PLASTER)
	local function timberFace(cf: any, width: number)
		-- (cf = middle of the face at floor1, LookVector out of the house)
		block(cf * CF.new(0, 0.3, -0.25), V3.new(width + 0.4, 0.6, 0.5), BEAM, nil, true)
		block(cf * CF.new(0, upper - 0.3, -0.25), V3.new(width + 0.4, 0.6, 0.5), BEAM, nil, true)
		local posts = math.floor(width / 5)
		for i = 0, posts do
			local x = -width / 2 + i * width / posts
			block(cf * CF.new(x, upper / 2, -0.25), V3.new(0.6, upper, 0.5), BEAM, nil, true)
			if i < posts and i % 2 == 0 then
				local mid = x + width / posts / 2
				local len = math.sqrt((width / posts) ^ 2 + (upper - 1.2) ^ 2)
				local ang = math.atan2(upper - 1.2, width / posts)
				block(cf * CF.new(mid, upper / 2, -0.22) * CF.Angles(0, 0, ang), V3.new(len, 0.45, 0.4), BEAM, nil, true)
			end
		end
	end
	timberFace(fr(0, floor1, z0 + 0.02), W)
	timberFace(CF.new(-W / 2 - 0.02, floor1, zc) * CF.Angles(0, math.pi / 2, 0), D)
	timberFace(CF.new(W / 2 + 0.02, floor1, zc) * CF.Angles(0, -math.pi / 2, 0), D)
	-- the floor's oversailing beam with little beam ends
	block(CF.new(0, floor1 - 0.1, z0 + 0.4), V3.new(W + 0.8, 0.5, 0.9), BEAM)
	for i = 0, 9 do
		block(CF.new(-W / 2 + 1.5 + i * (W - 3) / 9, floor1 - 0.45, z0 + 0.75), V3.new(0.5, 0.5, 0.6), C.Wood, nil, true)
	end

	-- the roof: terracotta tiles (ridge along x) and a front cross gable over the door
	Style.gableRoof(shop, CF.new(0, eave, zc), W + 2.4, D + 2.4, 7, {
		Color = C.RoofTerracotta,
		Dark = C.RoofTerracottaDark,
		Trim = C.RoofTrim,
		Rows = 4,
	})
	-- gable ends: plank triangles (stepped boards) under the roof at both sides
	for _, sx in { -1, 1 } do
		for k = 0, 5 do
			local h = 7 * (1 - k / 6)
			block(
				CF.new(sx * (W / 2 + 0.1), eave + k * 1.1 + 0.55, zc),
				V3.new(0.4, 1.1, math.max(0.6, (D + 1) * h / 7)),
				Style.vary(C.Plank, rng, 0.05)
			)
		end
	end
	-- the cross gable: a deep front roof over the entrance, the sign under it
	local gw = 12
	Style.gableRoof(shop, CF.new(0, eave - 0.5, z0 + 1.5) * CF.Angles(0, math.pi / 2, 0), 9, gw, 5.5, {
		Color = C.RoofTerracotta,
		Dark = C.RoofTerracottaDark,
		Trim = C.RoofTrim,
		Rows = 3,
	})
	for k = 0, 4 do
		local h = 5.5 * (1 - k / 5)
		block(
			CF.new(0, eave - 0.5 + k * 1.1 + 0.55, z0 + 6.2),
			V3.new(math.max(0.6, (gw - 1) * h / 5.5), 1.1, 0.3),
			Style.vary(C.Plank, rng, 0.05)
		)
	end
	-- the cross gable's posts and the sign
	for _, sx in { -1, 1 } do
		block(CF.new(sx * (gw / 2 - 0.6), (plinth + eave - 0.5) / 2, z0 + 5.6), V3.new(0.9, eave - 0.5 - plinth, 0.9), C.Wood)
		block(CF.new(sx * (gw / 2 - 0.6), plinth + 0.4, z0 + 5.6), V3.new(1.5, 0.8, 1.5), C.StoneDark)
	end
	block(CF.new(0, eave - 0.85, z0 + 5.6), V3.new(gw, 0.7, 0.9), BEAM)
	Style.sign(shop, fr(0, floor1 + 1.9, z0 + 6.2), "DROPPERS", 10.5, 2.8, { Kind = "Glow", DoubleSided = false })
	-- the porch floor: planks between the posts
	Style.planks(shop, fr(0, plinth + 0.05, z0 + 2.9), V3.new(gw - 0.4, 0.3, 5.4), rng)

	-- the door: two plank leaves with iron bands in a stone frame, lanterns each side
	local doorW, doorH = 4.6, 4.8
	for _, sx in { -1, 1 } do
		block(CF.new(sx * doorW / 4, plinth + doorH / 2, z0 + 0.55), V3.new(doorW / 2 - 0.1, doorH, 0.3), Style.vary(C.Wood, rng, 0.04))
		for _, y in { 1.0, doorH - 1.0 } do
			block(CF.new(sx * doorW / 4, plinth + y, z0 + 0.72), V3.new(doorW / 2 - 0.3, 0.25, 0.08), C.Iron, nil, true)
		end
		block(CF.new(sx * 0.45, plinth + doorH / 2, z0 + 0.75), V3.new(0.2, 0.6, 0.15), C.Brass, nil, true)
		block(CF.new(sx * (doorW / 2 + 0.5), plinth + doorH / 2, z0 + 0.6), V3.new(0.9, doorH + 0.4, 0.5), C.StoneLight)
		Style.lantern(shop, fr(sx * (doorW / 2 + 1.6), plinth + doorH - 0.2, z0 + 1.0), { Kind = "Hanging", Light = true })
	end
	block(CF.new(0, plinth + doorH + 0.4, z0 + 0.6), V3.new(doorW + 1.9, 0.8, 0.5), C.StoneLight)

	-- windows: lit, with flower boxes below and striped awnings above (ground floor)
	for _, wx in { -9.5, 9.5 } do
		Style.window(shop, fr(wx, plinth + 3.0, z0 + 0.62), 4.4, 2.8)
		block(CF.new(wx, plinth + 1.15, z0 + 1.05), V3.new(4.8, 0.6, 0.8), C.Wood)
		Style.flowers(shop, V3.new(wx, plinth + 1.5, z0 + 1.05), if wx < 0 then C.FlowerPink else C.FlowerYellow, rng, 5, 2.0)
		Style.awning(shop, fr(wx, plinth + 5.2, z0 + 0.6), 5.4, 1.8, 1.2, C.AwningPurple, C.AwningWhite)
	end
	for _, wx in { -10, 10 } do
		Style.window(shop, fr(wx, floor1 + upper / 2, z0 + 0.3), 2.2, 2.2)
		-- plank shutters each side
		for _, sx in { -1, 1 } do
			block(CF.new(wx + sx * 1.75, floor1 + upper / 2, z0 + 0.55), V3.new(1.1, 2.6, 0.2), C.Wood, nil, true)
			block(CF.new(wx + sx * 1.75, floor1 + upper / 2, z0 + 0.68), V3.new(1.1, 0.2, 0.06), C.WoodDark, nil, true)
		end
	end

	-- the forge chimney: a voxel stone pillar with an ember glow and smoke
	Style.pillar(shop, CF.new(W / 2 - 5, eave + 1, zc - 2), 12, rng, { Width = 2.8, Glow = C.Ember })
	for k, pz in { 0.3, 1.5, 2.9 } do
		local sz = 0.9 + k * 0.4
		Geo.block(
			shop,
			CF.new(W / 2 - 5 + k * 0.3, eave + 13.5 + pz * 1.3, zc - 2),
			V3.new(sz, sz, sz),
			rgb(226, 226, 232),
			nil,
			{ Transparency = 0.2 + k * 0.15, CanCollide = false, CastShadow = false }
		)
	end

	-- props: crates and barrels by the walls, bushes, lanterns along the path, trees
	Style.crate(shop, CF.new(-W / 2 + 1.5, plinth, z0 + 2.2), rng, 2.2)
	Style.crate(shop, CF.new(-W / 2 + 1.6, plinth + 2.2, z0 + 2.3), rng, 1.6)
	Style.barrel(shop, V3.new(W / 2 - 1.6, plinth, z0 + 2.2), rng)
	Style.barrel(shop, V3.new(W / 2 - 3.2, plinth, z0 + 2.0), rng)
	for _, bx in { -13, -6.5, 6.5, 13 } do
		Style.bush(shop, V3.new(bx, 0.1, z0 + 1.6), C.LeafGreen, rng, 1.6)
	end
	for _, side in { -1, 1 } do
		Style.lantern(shop, fr(side * 4.6, 0.1, 20), { Kind = "Ground" })
		Style.lantern(shop, fr(side * 4.6, 0.1, 12), { Kind = "Ground" })
	end
	-- stone steps up to the porch, a bench, flower pots
	for k = 1, 2 do
		block(
			CF.new(0, plinth - k * 0.4 + 0.2, z0 + 5.6 + k * 0.9),
			V3.new(5.6 - k * 0.4, 0.4 * (3 - k), 0.9),
			Style.vary(C.StoneLight, rng, 0.04)
		)
	end
	block(CF.new(-9.5, plinth + 0.9, z0 + 2.6), V3.new(3.6, 0.3, 1.0), C.WoodLight)
	for _, bx in { -10.9, -8.1 } do
		block(CF.new(bx, plinth + 0.45, z0 + 2.6), V3.new(0.4, 0.9, 0.9), C.WoodDark)
	end
	for _, px in { -3.6, 3.6 } do
		block(CF.new(px, plinth + 0.5, z0 + 5.0), V3.new(1.0, 1.0, 1.0), C.Copper)
		Style.flowers(shop, V3.new(px, plinth + 1.1, z0 + 5.0), C.FlowerRed, rng, 3, 0.6)
	end
	Style.tree(shop, CF.new(-26, 0, -10), "Pink", rng, 1.2)
	Style.tree(shop, CF.new(26, 0, -12), "Green", rng, 1.2)
	Style.tree(shop, CF.new(-34, 0, -2), "Yellow", rng, 1.0)
	Style.tree(shop, CF.new(35, 0, -3), "Orange", rng, 1.0)

	-- the seven droppers on show in front of the house (machine size), a Money Laser by them
	-- two rows along the yard's sides, facing the path
	local show = {
		{ "BasicDropper", -30, 2, 1 },
		{ "BlueDropper", -30, 11, 1 },
		{ "RedDropper", -30, 20, 1 },
		{ "DarkMatterDropper", -21, 24, 1 },
		{ "PurpleDropper", 30, 2, -1 },
		{ "GoldDropper", 30, 11, -1 },
		{ "RainbowDropper", 30, 20, -1 },
	}
	for _, spot in show do
		local id, x, z, side = spot[1] :: string, spot[2] :: number, spot[3] :: number, spot[4] :: number
		DropperBuilder.build(id, CF.new(x, 0.1, z) * CF.Angles(0, side * math.pi / 2, 0)).Parent = shop
	end
	LaserBuilder.build(CF.new(21, 0.1, 24) * CF.Angles(0, -math.pi / 2, 0), 0.85).Parent = shop
	print("DROPPERS house built")
	return shop
end

return Preview
