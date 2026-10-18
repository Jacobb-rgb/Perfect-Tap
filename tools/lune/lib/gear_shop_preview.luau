--[[
	The Gear shop panel over the game (scene "gear_shop" for
	tools/lune/export_scene.luau: the world, shots in
	tools/preview/gear_shop_shots.json at the SHOP stall), plus two miners in
	front of the stall wearing the Helmet Lamp (the band and lamp parts as
	GearFxController builds them; the preview has no SpotLights, so only the
	Neon lens glows; in town the real light is off anyway) and a miner
	carrying 24 chunks (Backpack V + Strong Back) in CarryService's stack.
	Everything is drawn with the game's own code (GearShopView.build /
	layout / cards / setCards, HudView) from State snapshots.
	UI overlays (build/preview/<name>.json):
	  ui_gear_pc           PC 1600 x 900, mid-game: the Backpack just bought
	                       ("BOUGHT!", the server's toast in the header)
	  ui_gear_new          PC, a new player with $1,200: what they can buy
	  ui_gear_status       PC, a card says why it can't buy (effect box)
	  ui_gear_max          PC, everything at the top level (the footer says so)
	  ui_gear_phone        667 x 375 pt phone (compact layout)
	  ui_gear_phone_small  568 x 320 pt phone (rows dropped to fit)
	  ui_gear_tv           1080p TV (console): compact, the gamepad footer
	                       (A buy, B close), a BUY waits for its answer
	  ui_gear_carry_phone  667 x 375 pt phone HUD carrying 24 of 24 ("+17")
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")
local Dummy = require("./dummy")

local Preview = {}

Preview.Coins = 48250

-- A mid-game player: boots, a lamp, a big backpack, a small magnet.
Preview.State = {
	Coins = Preview.Coins,
	Gear = { Boots = 2, HelmetLamp = 1, Backpack = 3, Gloves = 0, Magnet = 1 },
	Perks = { StrongBack = false },
}

-- Two miners with head lamps in front of the SHOP counter.
local function miners(Loader: any, workspace: any)
	local CFrame = Loader.CFrame
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local GearConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GearConfig")
	local Players = Loader.game:GetService("Players")
	-- a client module: it reads Players.LocalPlayer when it loads
	local hadLocal = rawget(Players, "LocalPlayer")
	rawset(Players, "LocalPlayer", { UserId = 1 })
	local GearFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.GearFxController")
	rawset(Players, "LocalPlayer", hadLocal)
	local counter = nil
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ShopCounter" then
			counter = d
		end
	end
	if not counter then
		return
	end
	local folder = roblox.Instance.new("Folder")
	folder.Name = "GearMiners"
	folder.Parent = workspace
	-- the plaza in front of the counter's customer side (-Z), feet on the ground
	local front = counter.CFrame * CFrame.new(0, 0, -(counter.Size.Z / 2 + 3.2))
	local ground = counter.CFrame.Position.Y - 3.1
	local function miner(offset: any, yaw: number, level: number, colors: any)
		local at = Vector3.new(front.Position.X, ground, front.Position.Z) + offset
		local look = front.LookVector
		local root = CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z)) * CFrame.Angles(0, math.rad(yaw), 0)
		Dummy.build(folder, CFrame, root, "idle", colors)
		-- the head lamp as GearFxController builds it (band + housing + Neon lens)
		local head = root * CFrame.new(0, 4.65, 0)
		local headSize = Vector3.new(1.2, 1.2, 1.2)
		local lampAt = head * GearFx.lampOffset(headSize)
		local bandAt, bandSize = GearFx.band(headSize)
		local function cyl(name: string, size: any, cf: any, color: any, material: any, shape: any?)
			local p = roblox.Instance.new("Part")
			p.Name = name
			p.Shape = shape or roblox.Enum.PartType.Cylinder
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = material
			p.Anchored = true
			p.Parent = folder
		end
		cyl("Band", bandSize, head * bandAt, Color3.fromRGB(255, 196, 18), roblox.Enum.Material.SmoothPlastic, roblox.Enum.PartType.Block)
		cyl("Housing", GearFx.HousingSize, lampAt, Color3.fromRGB(58, 60, 72), roblox.Enum.Material.SmoothPlastic)
		cyl("Lens", GearFx.LensSize, lampAt * CFrame.new(GearFx.LensOffset, 0, 0), GearFx.lensColor(level), roblox.Enum.Material.Neon)
	end
	local right = front.RightVector
	miner(right * 2.2, 18, 1, nil)
	miner(right * -2.4, -22, GearConfig.MaxLevel, {
		shirt = Color3.fromRGB(60, 120, 190),
		pants = Color3.fromRGB(50, 46, 60),
		skin = Color3.fromRGB(150, 104, 76),
		hair = Color3.fromRGB(30, 24, 20),
	})
	-- a miner with Backpack V + Strong Back carrying all 24 chunks across the
	-- plaza: the stack as CarryService builds it (root = feet + 3)
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	-- (behind the stall and miners cameras, out on the plaza)
	local at = Vector3.new(front.Position.X, ground, front.Position.Z) + front.LookVector * 24
	local carrier = CFrame.lookAt(at, at + right)
	Dummy.build(folder, CFrame, carrier, "carry", {
		shirt = Color3.fromRGB(64, 150, 92),
		pants = Color3.fromRGB(56, 50, 66),
	})
	local ores = { "Copper", "Iron", "Silver", "Coal", "Tin", "Gold" }
	local capacity = GearConfig.carryCapacity({ Backpack = GearConfig.MaxLevel }, true)
	for i = 1, capacity do
		local cf = carrier * CFrame.new(0, 3, 0) * CarryService.stackOffset(i)
		local item = ItemBuilder.build({ Kind = "Raw", OreId = ores[(i - 1) % #ores + 1] }, cf, 200 + i)
		item.Parent = folder
	end
end

function Preview.build(Loader: any, workspace: any): { [string]: any }
	local C3 = roblox.Color3
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local GearConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GearConfig")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local GearShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GearShopView")

	miners(Loader, workspace)

	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = GearShopView.PhoneScale * 900 / 375 -- a 667 x 375 pt phone scaled up to the render
	local smallScale = GearShopView.PhoneScale * 900 / 320 -- a 568 x 320 pt phone
	local smallInset = math.floor(58 * 900 / 320) -- its 58 pt top bar, in render pixels

	-- the HUD as HudController draws it (carryLayout: at most 8 squares, "+N")
	local function hud(uiScale: number, coins: number, carry: number, carried: number?): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(coins)
		refs.Income.Text = Format.perSecond(64)
		refs.Income.TextColor3 = C3.fromRGB(110, 214, 92)
		local count = carried or 0
		local squares, shown, more, width = HudView.carryLayout(carry, count)
		refs.CarryLabel.Text = `CARRYING {count}/{carry}`
		for i = 1, squares do
			if more > 0 and i == squares then
				HudView.moreSlot(refs.CarrySlots, more, i)
			else
				HudView.slot(refs.CarrySlots, nil, i, i <= shown)
			end
		end
		refs.CarryPanel.Size = roblox.UDim2.fromOffset(width, HudView.CarryPanelHeight)
		refs.Toasts:ClearAllChildren()
		return refs
	end

	-- the shop as GearShopController shows it (`pad`: a gamepad plays; the
	-- renderer draws no images, so the glyphs' text fallback "A: buy")
	local function view(uiScale: number, compact: boolean, maxWidth: number, maxHeight: number, state: any, coins: number, pad: boolean?): any
		local refs = GearShopView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		GearShopView.layout(refs, compact, maxWidth, maxHeight)
		GearShopView.setCoins(refs, coins)
		local cards = GearShopView.cards(state, coins)
		GearShopView.setCards(refs, cards)
		local done = GearShopView.allDone(cards)
		local input = if pad then "Pad" elseif compact then "Touch" else "Mouse"
		GearShopView.setHint(refs, GearShopView.hintText(input, done, "A", "B"), nil, pad == true, done)
		return refs
	end

	local exports: { [string]: any } = {}
	local pcWidth, pcHeight = 1600 / scale, (900 - 36) / scale

	-- PC, mid-game: the Backpack just bought
	local bought = table.clone(Preview.State)
	bought.Gear = table.clone(Preview.State.Gear)
	local hud1 = hud(scale, Preview.Coins, 5)
	local pc = view(scale, false, pcWidth, pcHeight, bought, Preview.Coins)
	local pack = pc.Slots.Backpack.Button
	pack.Text = "BOUGHT!"
	GearShopView.style(pack, true, Theme.Good, Theme.GoodDark)
	GearShopView.showReceipt(pc, "Ore Backpack III: you can carry 5 items!", Theme.Good)
	exports.ui_gear_pc = UiExport.export({ hud1.Gui, pc.Gui })

	-- PC, a new player with $1,200
	local fresh = { Coins = 1200, Gear = { Boots = 0, HelmetLamp = 0, Backpack = 0, Gloves = 0, Magnet = 0 }, Perks = {} }
	local hud2 = hud(scale, 1200, 1)
	local new = view(scale, false, pcWidth, pcHeight, fresh, 1200)
	exports.ui_gear_new = UiExport.export({ hud2.Gui, new.Gui })

	-- PC, a refused BUY says why in the card
	local hud3 = hud(scale, Preview.Coins, 5)
	local status = view(scale, false, pcWidth, pcHeight, Preview.State, Preview.Coins)
	GearShopView.setStatus(status, "Backpack", GearConfig.Reasons.NoCoins, Theme.Bad)
	exports.ui_gear_status = UiExport.export({ hud3.Gui, status.Gui })

	-- PC, everything at the top level
	local top = { Coins = 9.9e6, Gear = {}, Perks = { StrongBack = true } }
	for _, line in GearConfig.LineIds do
		top.Gear[line] = GearConfig.MaxLevel
	end
	local hud4 = hud(scale, 9.9e6, 24)
	local max = view(scale, false, pcWidth, pcHeight, top, 9.9e6)
	exports.ui_gear_max = UiExport.export({ hud4.Gui, max.Gui })

	-- phones: the compact layout
	local hud5 = hud(phoneScale, Preview.Coins, 5)
	local phone = view(phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, Preview.State, Preview.Coins)
	exports.ui_gear_phone = UiExport.export({ hud5.Gui, phone.Gui })
	local hud6 = hud(smallScale, Preview.Coins, 5)
	local small = view(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale, Preview.State, Preview.Coins)
	exports.ui_gear_phone_small = UiExport.export({ hud6.Gui, small.Gui })

	-- a console on a 1080p TV: compact, the gamepad hint, a BUY waiting for its answer
	local tvScale = 1.25 * 900 / 1080
	local hud7 = hud(tvScale, Preview.Coins, 5)
	local tv = view(tvScale, true, 1600 / tvScale, (900 - 36 * 900 / 1080) / tvScale, Preview.State, Preview.Coins, true)
	local boots = tv.Slots.Boots.Button
	boots:SetAttribute("Busy", true)
	boots.Text = "..."
	GearShopView.setStatus(tv, "Gloves", GearShopView.StatusText.Waiting, Theme.Info)
	exports.ui_gear_tv = UiExport.export({ hud7.Gui, tv.Gui })

	-- a phone HUD carrying 24 of 24 (Backpack V + Strong Back): 8 squares, "+17"
	local hud8 = hud(phoneScale, Preview.Coins, 24, 24)
	exports.ui_gear_carry_phone = UiExport.export({ hud8.Gui })
	return exports
end

return Preview
