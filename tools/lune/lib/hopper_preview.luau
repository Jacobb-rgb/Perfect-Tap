--[[
	The hopper concepts (Config/HopperConfig, Builders/HopperBuilder):
	  scene "hoppers"  the seven hoppers in a row on a showroom stage, small
	                   to big, each with a price plate in front
	  scene "hopper_shop"  the HOPPER WORKS shop building (Preview.buildShop): a
	                   factory hall with a saw-tooth roof, a giant golden funnel
	                   the Terra Core Hopper on the roof as the landmark, the sign,
	                   the counter with a Legendary Hopper behind it and two
	                   hoppers on pedestals out front
	UI overlays (Preview.ui, drawn with HopperShopView over the stage):
	  ui_hoppers_pc        PC: the first cards (one Epic Hopper owned, the
	                       Legendary one affordable)
	  ui_hoppers_pc_more   PC: scrolled to the end (Star, Rift, Terra Core)
	  ui_hoppers_phone     667 x 375 pt phone
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
	local NEON = roblox.Enum.Material.Neon
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local HopperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HopperBuilder")
	local HopperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.HopperConfig")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local rgb = C3.fromRGB

	local stage = Instance.new("Model")
	stage.Name = "HopperStage"
	stage.Parent = workspace

	local function label(cf: any, size: any, text: string, ink: any, edge: any)
		Geo.block(stage, cf * CF.new(0, 0, -0.04), size + V3.new(0.14, 0.14, -0.04), edge, NEON)
		local plate = Geo.block(stage, cf, size, rgb(16, 18, 24))
		local gui = Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Back
		gui.Parent = plate
		local t = Instance.new("TextLabel")
		t.Text = text
		t.TextColor3 = ink
		t.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
		t.Parent = gui
	end

	-- floor and back wall: a dark showroom so the trims glow
	Geo.block(stage, CF.new(0, -0.5, -6), V3.new(260, 1, 120), rgb(34, 36, 46))
	Geo.block(stage, CF.new(0, 30, -34), V3.new(260, 62, 1), rgb(18, 18, 26))
	-- the stage: one long low step with a glowing front edge
	local x = 0
	local gap = 3.2
	local total = 0
	for _, hopper in HopperConfig.List do
		total += HopperBuilder.Plate * HopperBuilder.Styles[hopper.Id].Scale + gap
	end
	total -= gap
	Geo.block(stage, CF.new(0, 0.3, -2), V3.new(total + 8, 0.6, 22), rgb(46, 48, 62))
	Geo.block(stage, CF.new(0, 0.58, 9), V3.new(total + 8, 0.06, 0.06), rgb(200, 140, 60), NEON)

	x = -total / 2
	for _, hopper in HopperConfig.List do
		local s = HopperBuilder.Styles[hopper.Id].Scale
		local w = HopperBuilder.Plate * s
		local cx = x + w / 2
		Preview.Spots[hopper.Id] = cx
		local model = HopperBuilder.build(hopper.Id, CF.new(cx, 0.6, -2))
		model.Parent = stage
		-- the price plate on the stage's front
		local trim = HopperBuilder.Styles[hopper.Id].Trim[1]
		label(CF.new(cx, 1.15, 6.6), V3.new(math.min(w - 0.4, 6.6), 0.75, 0.1), Format.money(hopper.Price), rgb(255, 214, 80), trim)
		x += w + gap
	end
	print(string.format("Hopper stage: %d hoppers, %.0f studs wide", #HopperConfig.List, total))
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
	local function shop(uiScale: number, w: number, h: number, scroll: number?): any
		local refs = HopperShopView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		HopperShopView.layout(refs, w, h)
		for _, hopper in HopperConfig.List do
			HopperShopView.setCard(refs, hopper.Id, {
				Owned = if hopper.Id == "EpicHopper" then 2 else 0,
				CanAfford = hopper.Price <= coins,
				Locked = hopper.Order >= 6,
			})
		end
		HopperShopView.setInfo(refs, "Your hoppers: 2 / 4 spots  ·  they pour ores into their chest, you earn every second")
		HopperShopView.setStatus(refs, "Bought Epic Hopper! Place it in your base with Build mode.")
		if scroll then
			refs.Scroller.CanvasPosition = roblox.Vector2.new(scroll, 0)
		end
		return refs
	end
	local exports: { [string]: any } = {}
	local pcW, pcH = 1600 / scale, (900 - 36) / scale
	exports.ui_hoppers_pc = UiExport.export({ hud(scale).Gui, shop(scale, pcW, pcH).Gui })
	exports.ui_hoppers_pc_more = UiExport.export({ hud(scale).Gui, shop(scale, pcW, pcH, 900).Gui })
	exports.ui_hoppers_phone = UiExport.export({ hud(phoneScale).Gui, shop(phoneScale, 1600 / phoneScale, (900 - 58) / phoneScale).Gui })
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
	local HopperBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HopperBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local rgb = C3.fromRGB

	local shop = Instance.new("Model")
	shop.Name = "HopperWorks"
	shop.Parent = workspace
	local WALL = rgb(176, 104, 72) -- warm brick
	local WALL_DARK = rgb(120, 66, 48)
	local IRON = rgb(52, 50, 58)
	local ROOF = rgb(70, 120, 132) -- copper patina
	local GOLD = rgb(240, 180, 64)
	local STONE = rgb(196, 186, 168)
	local function block(cf: any, size: any, color: any, material: any?): any
		return Geo.block(shop, cf, size, color, material)
	end
	local function text(cf: any, size: any, words: string, ink: any, board: any, edge: any)
		Geo.block(shop, cf * CF.new(0, 0, -0.06), size + V3.new(0.5, 0.5, -0.04), edge, NEON)
		local plate = Geo.block(shop, cf, size, board)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.Parent = plate
		local t = Instance.new("TextLabel")
		t.Text = words
		t.TextColor3 = ink
		t.FontFace = roblox.Font.fromEnum(Enum.Font.LuckiestGuy)
		t.Parent = gui
	end

	-- the plaza: grass around, a paved square in front
	block(CF.new(0, -0.5, 0), V3.new(220, 1, 160), rgb(110, 176, 84), Enum.Material.Grass)
	block(CF.new(0, 0.05, 6), V3.new(60, 0.1, 44), STONE)
	for i = -5, 5 do
		block(CF.new(i * 5.4, 0.11, 6), V3.new(0.2, 0.04, 44), rgb(170, 160, 144))
	end
	for j = -4, 4 do
		block(CF.new(0, 0.11, 6 + j * 5), V3.new(60, 0.04, 0.2), rgb(170, 160, 144))
	end

	-- the hall: back wall, side walls, the front with a wide opening
	local W, D, H = 40, 18, 15
	local z0 = -8 -- the front wall's z
	local back = z0 - D
	block(CF.new(0, H / 2, back), V3.new(W, H, 1.2), WALL)
	for _, x in { -W / 2, W / 2 } do
		block(CF.new(x, H / 2, z0 - D / 2), V3.new(1.2, H, D), WALL)
	end
	local opening, openH = 22, 9
	local side = (W - opening) / 2
	for _, sx in { -1, 1 } do
		block(CF.new(sx * (opening / 2 + side / 2), H / 2, z0), V3.new(side, H, 1.2), WALL)
	end
	block(CF.new(0, (openH + H) / 2, z0), V3.new(opening, H - openH, 1.2), WALL)
	-- dark brick bands, iron pillars at the corners and around the opening
	block(CF.new(0, 0.6, z0 + 0.05), V3.new(W + 0.2, 1.2, 1.3), WALL_DARK)
	for _, x in { -W / 2, -opening / 2 - 0.4, opening / 2 + 0.4, W / 2 } do
		block(CF.new(x, H / 2, z0 + 0.4), V3.new(1.3, H + 0.4, 1.3), IRON)
		Geo.ball(shop, V3.new(x, H + 0.6, z0 + 0.4), 1.2, GOLD)
	end
	block(CF.new(0, openH + 0.4, z0 + 0.4), V3.new(opening + 1.6, 0.8, 1.3), IRON)
	-- hazard stripes along the opening's top
	for i = 0, 10 do
		local x = -opening / 2 + 1 + i * 2
		block(
			CF.new(x, openH - 0.15, z0 + 0.62) * CF.Angles(0, 0, 0.6),
			V3.new(0.6, 0.9, 0.08),
			if i % 2 == 0 then rgb(250, 196, 40) else rgb(30, 30, 34)
		)
	end
	-- the floor inside and the back wall's warm light
	block(CF.new(0, 0.12, z0 - D / 2), V3.new(W - 1, 0.1, D - 1), rgb(64, 60, 66))
	block(CF.new(0, 7, back + 0.65), V3.new(W - 6, 0.3, 0.1), rgb(255, 170, 70), NEON)

	-- the saw-tooth roof: four teeth with glowing skylights
	local teeth = 4
	local tooth = D / teeth
	for i = 0, teeth - 1 do
		local zc = z0 - tooth * (i + 0.5)
		Geo.wedge(shop, CF.new(0, H + 1.6, zc) * CF.Angles(0, math.pi, 0), V3.new(W + 1, 3.2, tooth), ROOF)
		block(CF.new(0, H + 1.6, zc - tooth / 2 + 0.1), V3.new(W + 0.8, 3.0, 0.2), rgb(255, 214, 140), NEON)
	end
	block(CF.new(0, H + 0.1, z0 - D / 2), V3.new(W + 1.4, 0.3, D + 1.2), IRON)

	-- the prize on the roof: the Terra Core Hopper on a turntable, seen from the whole lobby
	Geo.cylinder(shop, V3.new(0, H + 0.7, z0 - D / 2), 0.9, 15, rgb(40, 40, 48))
	Geo.cylinder(shop, V3.new(0, H + 1.18, z0 - D / 2), 0.1, 15.4, rgb(255, 196, 80), NEON)
	HopperBuilder.build("TerraCoreHopper", CF.new(0, H + 1.15, z0 - D / 2)).Parent = shop

	-- the sign over the opening, and a glowing hopper mark beside the words
	text(CF.new(2, H - 1.8, z0 + 0.9), V3.new(24, 3.2, 0.3), "HOPPER WORKS", rgb(255, 236, 170), rgb(40, 30, 30), rgb(255, 160, 40))
	local mx, my = -13.5, H - 1.8
	Geo.triangle(
		shop,
		V3.new(mx - 1.6, my + 1.3, z0 + 1.1),
		V3.new(mx + 1.6, my + 1.3, z0 + 1.1),
		V3.new(mx, my - 1.1, z0 + 1.1),
		0.3,
		GOLD,
		NEON,
		V3.new(0, 0, 1)
	)
	text(
		CF.new(0, openH + 1.5, z0 + 0.9),
		V3.new(15, 1.2, 0.2),
		"THE BIGGEST MACHINES IN TERRA",
		rgb(255, 250, 236),
		rgb(30, 30, 36),
		rgb(120, 200, 255)
	)

	-- inside: the counter and a Legendary Hopper on a turntable behind it
	block(CF.new(0, 1.6, z0 - 3.5), V3.new(14, 3, 2), rgb(96, 64, 46))
	block(CF.new(0, 3.2, z0 - 3.5), V3.new(14.6, 0.3, 2.6), rgb(150, 104, 66))
	block(CF.new(0, 1.3, z0 - 2.45), V3.new(13, 0.2, 0.1), rgb(255, 196, 80), NEON)
	Geo.cylinder(shop, V3.new(0, 0.5, z0 - 11), 0.8, 10, rgb(40, 40, 48))
	Geo.cylinder(shop, V3.new(0, 0.92, z0 - 11), 0.1, 10.4, rgb(255, 196, 80), NEON)
	HopperBuilder.build("LegendaryHopper", CF.new(0, 0.9, z0 - 11)).Parent = shop

	-- out front: two hoppers on pedestals and four lamps
	for _, spot in { { "EpicHopper", -21 }, { "HeartHopper", 21 } } do
		local x = spot[2] :: number
		Geo.cylinder(shop, V3.new(x, 0.6, 2), 1.2, 12, rgb(80, 76, 86))
		Geo.cylinder(shop, V3.new(x, 1.22, 2), 0.1, 12.3, if spot[1] == "EpicHopper" then rgb(180, 92, 255) else rgb(255, 120, 180), NEON)
		HopperBuilder.build(spot[1] :: string, CF.new(x, 1.2, 2) * CF.Angles(0, if x < 0 then 0.35 else -0.35, 0)).Parent = shop
	end
	for _, x in { -13, -5, 5, 13 } do
		block(CF.new(x, 2.5, 13), V3.new(0.4, 5, 0.4), IRON)
		Geo.ball(shop, V3.new(x, 5.3, 13), 1.0, rgb(255, 214, 120), NEON)
	end
	print("Hopper Works shop built")
	return shop
end

return Preview
