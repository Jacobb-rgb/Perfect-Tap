--[[
	The HUD in the pixel reels' look (owner 2026-10-22) with nothing else on
	screen (scene "hud_quick" for tools/lune/export_scene.luau: no world, fast
	UI iteration). Drawn with the game's own code (HudBubble, TeleportView,
	TrainView, BoostView, WheelView). UI overlays (build/preview/<name>.json):
	  ui_hud_pixel_pc       PC: the top bar, the left tiles with the TRAIN and
	                        boost chips, the FREE SPIN chip, a full hotbar
	  ui_hud_pixel_phone    667 x 375 pt phone (uiScale 0.62)
	  ui_hud_pixel_narrow   568 x 320 pt phone (the narrow top bar)
	  ui_hud_round_studio   the owner's Studio window (995 x 485 pt, a mouse: the
	                        tall block of tiles, owner 2026-10-28)
	  ui_hud_round_pc720    1280 x 720 PC; ui_hud_round_tablet 1024 x 768 (touch);
	                        ui_hud_round_phone640 / _phone568 (touch), ui_hud_round_tv
	The round look (PopTheme.Look, the default since 2026-10-27): the tiles
	are claimed as the controllers do (the reel's eight: Inventory by
	BackpackController, Spin with its FREE! sticker by WheelController's badge,
	the side menu's Store / Rebirth / Golems / Daily; the rest behind More).
	  ui_hud_corner_*       the boost corner on phones under a 58 px top bar
	  ui_blaster_slot_*     the BLASTER slot + the backpack button centred
	                        (owner 2026-10-28): pc (1280 x 720), pc_tv
	                        (1920 x 1080), 568 / 667 / 844 phones, each _off
	                        (in the backpack) and _on (in hand: the gold ring)
]]

local UiExport = require("./uiexport")

local Preview = {}

function Preview.build(Loader: any): { [string]: any }
	local roblox = require("@lune/roblox") :: any
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
	local HoverboardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HoverboardView")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
	local SideMenuView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SideMenuView")
	local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
	local TrainView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TrainView")
	local WheelView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelView")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local NOW = 1.7e9

	-- `renderScale` px per design unit, `uiScale` the game's scale (0.62 phones), `screen` in pt
	local function hud(
		renderScale: number,
		uiScale: number,
		screen: Vector2,
		boostCount: number?,
		touchButtons: boolean?,
		equipped: boolean?,
		input: ("Mouse" | "Touch" | "TV")?
	): { any }
		local boosts = boostCount or 1
		local compact = uiScale <= 0.75
		-- (phones are touch screens: `input` nil = touch when compact; `screen` is the gui's size)
		local touch = if input then input == "Touch" else compact
		local refs = HudBubble.buildGame(uiScale, screen.X, touch, input == "TV", screen.Y)
		-- (as HudController does: on phones the boost chips stop before the Shop pill)
		BoostView.HudChipsRight = HudBubble.chipsRight(refs.Gui, screen.X / uiScale)
		TeleportView.build(refs.TopBar, uiScale, screen.X)
		refs.Gui.Scale.Scale = renderScale
		refs.Coins.Text = Format.money(4.82e6)
		refs.Income.Text = Format.perSecond(1840)
		refs.Toasts:ClearAllChildren()
		local round = PopTheme.round()
		HudBubble.claimTile(refs.Menu, "Build")
		for _, entry in SideMenuView.sorted() do
			local spec = { Label = entry.Label, IconName = entry.IconName, Order = entry.Order }
			-- (SideMenuController.groupOf: the round look's left tiles are HudBubble.RoundMain)
			local main = if round then HudBubble.RoundMain[entry.Id] == true else entry.Group == "Main"
			if main then
				HudBubble.claimTile(refs.Menu, entry.Id, spec)
			else
				HudBubble.addMore(refs.Menu, entry.Id, spec)
			end
		end
		if round then
			-- (BackpackController: the Inventory tile; the Spin tile below, as WheelController claims it;
			-- HoverboardController: the Ride tile with its H key on a keyboard)
			HudBubble.claimTile(refs.Menu, "Backpack")
			local ride = HoverboardView.rideTile(refs.Menu)
			if ride then
				HoverboardView.setRiding(ride, false, if touch then "" else "H", nil)
			end
		end
		-- the backpack button as HudController fills it (12 of 30) with the PC key hint
		HudView.setBackpack(refs, 12, 30)
		HudView.setBackpackKey(refs, if compact then nil else "Q", nil)
		-- the BLASTER slot as BlasterSlotController fills it: "1" with a keyboard, the gold ring in hand
		HudView.setBlasterKey(refs, if compact then nil else "1")
		HudView.setBlasterEquipped(refs, equipped == true)
		local list = { refs.Gui }
		-- the TRAIN chip and the boost chips (TrainController / BoostController place them)
		TrainView.useHud(refs.Gui) -- (HudController: under the tiles, as wide as them)
		-- (TrainController: the compact chip on a touch screen or a small one)
		local chipCompact = compact or touch
		local train = TrainView.build(chipCompact)
		train.Chip.Scale.Scale = renderScale
		train.Gui.Scale.Scale = renderScale
		TrainView.layout(train, chipCompact, screen.X / uiScale, screen.Y / uiScale)
		train.ChipKey.Visible = not chipCompact
		TrainView.setStatus(train, TrainView.status(TrainView.read({ Cargo = 5, Capacity = 8, Moving = 0 }), NOW, nil))
		train.Gui.Enabled = false
		train.Chip.Enabled = true
		table.insert(list, train.Chip)
		local boost = BoostView.buildChips()
		boost.Gui.Scale.Scale = renderScale
		BoostView.placeChips(boost, BoostView.chipsTop(train.ChipFrame, compact), BoostView.chipsLeft(train.ChipFrame))
		if boost.Row:GetAttribute("Corner") then
			-- the boost corner as BoostController puts it (the owner's photo: Triple Lucky running)
			local pill = refs.Gui:FindFirstChild("ShopPill") :: any
			local w = screen.X / uiScale
			local rect = if pill
					and pill.AnchorPoint.Y == 0
					and pill.Position.Y.Scale == 0
				then {
					Left = w * pill.Position.X.Scale + pill.Position.X.Offset - pill.AnchorPoint.X * pill.Size.X.Offset,
					Bottom = pill.Position.Y.Offset + pill.Size.Y.Offset,
				}
				else nil
			-- (`screen` is already the gui under the top bar: the export's height)
			BoostView.placeCorner(
				boost,
				BoostView.cornerSpot({
					Screen = screen,
					Gui = screen,
					Scale = uiScale,
					Touch = compact,
					Count = boosts,
					Pill = rect,
				})
			)
		end
		local state = { Boosts = { TripleLuckyUntil = NOW + 584, HexaLuckyUntil = if boosts > 1 then NOW + 3900 else nil } }
		BoostView.setChips(boost, BoostView.chips(state, NOW), false)
		boost.Gui.Enabled = true
		table.insert(list, boost.Gui)
		if touchButtons then
			-- stand-ins for the touch buttons the preview can't draw (Roblox's jump, the game's
			-- Grab and FIRE while mining), where BoostView.TouchButtons says they are
			local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
			local pad = UIKit.screen("TouchStandIns", 4)
			pad.Scale.Scale = renderScale
			local small = math.min(screen.X, screen.Y + 58) <= 500
			for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
				local button = UIKit.new("Frame", {
					Name = b.Name,
					AnchorPoint = roblox.Vector2.new(1, 1),
					Position = roblox.UDim2.new(1, -b.Right / uiScale, 1, -b.Bottom / uiScale),
					Size = roblox.UDim2.fromOffset((b.Left - b.Right) / uiScale, (b.Top - b.Bottom) / uiScale),
					BackgroundColor3 = roblox.Color3.fromRGB(20, 20, 26),
					BackgroundTransparency = 0.45,
				}, pad)
				UIKit.corner(button, 999)
				UIKit.label(button, string.upper(b.Name), 22, { Size = roblox.UDim2.fromScale(1, 1), TextWrapped = false })
			end
			pad.Enabled = true
			table.insert(list, pad)
		end
		if refs.Menu:FindFirstChild("Wheel") then
			-- the SPIN tile next to MORE (WheelController claims it on the light HUD; badge: a free spin ready)
			HudBubble.setTileBadge(HudBubble.claimTile(refs.Menu, "Wheel"), 1)
		else
			-- the FREE SPIN chip right of the top bar
			local spin = WheelView.buildChip(uiScale, screen.X)
			spin.Gui.Scale.Scale = renderScale
			spin.Gui.Enabled = true
			table.insert(list, spin.Gui)
		end
		return list
	end

	local exports: { [string]: any } = {}
	exports.ui_hud_pixel_pc = UiExport.export(hud(1.25, 1.25, roblox.Vector2.new(1600, 864)))
	exports.ui_hud_pixel_phone = UiExport.export(hud(0.62 * 900 / 375, 0.62, roblox.Vector2.new(667, 375 - 58 * 375 / 900)))
	exports.ui_hud_pixel_narrow = UiExport.export(hud(0.62 * 900 / 320, 0.62, roblox.Vector2.new(568, 320 - 58 * 320 / 900)))
	-- the round look's tall block (owner 2026-10-28): his Studio window (a mouse), a 1280 x 720 PC,
	-- a touch tablet; renders 900 px tall under a 58 px top bar
	local studioScale = HudBubble.scaleFor(roblox.Vector2.new(995, 485))
	exports.ui_hud_round_studio =
		UiExport.export(hud(studioScale * 900 / 485, studioScale, roblox.Vector2.new(995, 485 - 58 * 485 / 900), 1, false, false, "Mouse"))
	exports.ui_hud_round_pc720 = UiExport.export(hud(900 / 720, 1, roblox.Vector2.new(1280, 720 - 58 * 720 / 900)))
	local tabletScale = HudBubble.scaleFor(roblox.Vector2.new(1024, 768))
	exports.ui_hud_round_tablet =
		UiExport.export(hud(tabletScale * 900 / 768, tabletScale, roblox.Vector2.new(1024, 768 - 58 * 768 / 900), 1, true, false, "Touch"))
	for _, phone in { { 640, 360 }, { 568, 320 } } do
		exports[`ui_hud_round_phone{phone[1]}`] = UiExport.export(
			hud(0.62 * 900 / phone[2], 0.62, roblox.Vector2.new(phone[1], phone[2] - 58 * phone[2] / 900), 1, true, false, "Touch")
		)
	end
	exports.ui_hud_round_tv =
		UiExport.export(hud(900 / 1080 * 1.25, 1.25, roblox.Vector2.new(1920, 1080 - 58 * 1080 / 900), 1, false, false, "TV"))
	TrainView.useHud(nil)
	-- the boost corner on phones under a real 58 px top bar (review 2026-10-28): one and two boosts
	for _, phone in { { 568, 320 }, { 800, 360 }, { 844, 390 } } do
		for _, count in { 1, 2 } do
			local gui = roblox.Vector2.new(phone[1], phone[2] - 58)
			exports[`ui_hud_corner_{phone[1]}_{count}`] = UiExport.export(hud(0.62 * 900 / phone[2], 0.62, gui, count, true))
		end
	end
	-- the BLASTER slot left of the backpack, the pair centred (owner 2026-10-28), before and
	-- after equipping: PC (the render is 900 px tall; the gui under a 36 / 58 px top bar) and
	-- phones under a 58 px top bar with the touch buttons' stand-ins
	for _, state in { { "off", false }, { "on", true } } do
		local on = state[2] :: boolean
		exports[`ui_blaster_slot_pc_{state[1]}`] = UiExport.export(hud(900 / 720, 1, roblox.Vector2.new(1280, 720 - 36), 1, false, on))
		exports[`ui_blaster_slot_pc_tv_{state[1]}`] =
			UiExport.export(hud(900 / 1080 * 1.25, 1.25, roblox.Vector2.new(1920, 1080 - 58), 1, false, on))
		for _, phone in { { 568, 320 }, { 667, 375 }, { 844, 390 } } do
			local gui = roblox.Vector2.new(phone[1], phone[2] - 58)
			exports[`ui_blaster_slot_{phone[1]}_{state[1]}`] = UiExport.export(hud(0.62 * 900 / phone[2], 0.62, gui, 1, true, on))
		end
	end
	return exports
end

return Preview
