--[[
	The Tech shop panel over the game (scene "tech_shop" for
	tools/lune/export_scene.luau: the world, shots in
	tools/preview/tech_shop_shots.json at the UPGRADES stall).
	Everything is drawn with the game's own code (TechShopView.build /
	layout / cards / setCards, HudView) from a mid-game State snapshot.
	UI overlays (build/preview/<name>.json):
	  ui_tech_machines     PC, MACHINES tab: 5 belts just bought ("BOUGHT!"
	                       on BUY 5, the server's toast in the header)
	  ui_tech_upgrades     PC, UPGRADES tab: one card says why it can't buy
	  ui_tech_automation   PC, AUTOMATION tab: billboard owned, Direct Unload next
	  ui_tech_phone        667 x 375 pt phone (compact layout), MACHINES tab
	  ui_tech_phone_small  568 x 320 pt phone, UPGRADES tab
	  ui_tech_machines_more  PC, MACHINES scrolled down (the 3-line Iron Box
	                       text; the machine slots full: red slot line)
	  ui_tech_upgrades_more  PC, UPGRADES scrolled down (an upgrade for a
	                       machine you don't have; Bellows / Slots)
	  ui_tech_phone_more   568 x 320 pt phone, AUTOMATION tab
	  ui_tech_tv           1080p TV (console, HUD scale 1.25): the compact
	                       layout's bigger texts; BUY 1 waits for its answer
	                       and BUY 5 on the same card says to wait
	(the renderer has no scrolling: "scrolled" hides the rows above)
]]

local roblox = require("@lune/roblox") :: any
local UiExport = require("./uiexport")

local Preview = {}

Preview.Coins = 48250

-- A mid-game player: a few belts and a Cleaning Plant waiting, some upgrades bought.
Preview.State = {
	Coins = Preview.Coins,
	MachineInventory = { Conveyor = 12, AutoCleaner = 1 },
	Placed = {
		{ Id = "CleaningStation" },
		{ Id = "ClayFurnace" },
		{ Id = "Crusher" },
		{ Id = "Conveyor" },
		{ Id = "Conveyor" },
		{ Id = "Conveyor" },
		{ Id = "Conveyor" },
		{ Id = "Conveyor" },
		{ Id = "Conveyor" },
	},
	MachineUpgrades = { AutoCleaner = { Speed = 1, Quality = 2 }, ClayFurnace = { Speed = 2 } },
	Upgrades = { Bellows = 2, ExtraSlots = 1, PenLevel = 1, PenAutomation = 1 },
	Perks = { Workshop = false },
	Build = { MachinesUsed = 3, MachineSlots = 13, ConveyorsUsed = 6, ConveyorSlots = 40 },
}

function Preview.build(Loader: any): { [string]: any }
	local C3 = roblox.Color3
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")

	local scale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = TechShopView.PhoneScale * 900 / 375 -- a 667 x 375 pt phone scaled up to the render
	local smallScale = TechShopView.PhoneScale * 900 / 320 -- a 568 x 320 pt phone
	local smallInset = math.floor(58 * 900 / 320) -- its 58 pt top bar, in render pixels

	local function hud(uiScale: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = uiScale
		refs.Coins.Text = Format.money(Preview.Coins)
		refs.Income.Text = Format.perSecond(64)
		refs.Income.TextColor3 = C3.fromRGB(110, 214, 92)
		refs.CarryLabel.Text = "CARRYING 0/3"
		for i = 1, 3 do
			HudView.slot(refs.CarrySlots, nil, i)
		end
		refs.Toasts:ClearAllChildren()
		return refs
	end

	-- the shop as TechShopController shows it
	local function view(uiScale: number, compact: boolean, maxWidth: number, maxHeight: number, tab: string, state: any?): any
		local refs = TechShopView.build(compact)
		refs.Gui.Scale.Scale = uiScale
		refs.Gui.Enabled = true
		TechShopView.layout(refs, compact, maxWidth, maxHeight)
		TechShopView.setTab(refs, tab)
		TechShopView.setCoins(refs, Preview.Coins)
		TechShopView.setCards(refs, TechShopView.cards(state or Preview.State, Preview.Coins))
		TechShopView.setHint(refs, `Click a tab, then BUY{TechShopView.Separator}Backspace: close`, nil)
		return refs
	end

	-- "scrolls" a tab's list: hides its first `n` rows (and the group headers above them)
	local function scrolled(refs: any, tab: string, n: number)
		for i, row in TechShopView.rowsOf(refs, tab) do
			if i <= n then
				row.Frame.Visible = false
			end
		end
		if tab == "Upgrades" then
			refs.Groups[1].Visible = false
		end
	end

	local exports: { [string]: any } = {}
	local pcWidth, pcHeight = 1600 / scale, (900 - 36) / scale

	-- MACHINES: 5 belts just bought
	local hud1 = hud(scale)
	local machines = view(scale, false, pcWidth, pcHeight, "Machines")
	local belt = machines.Rows.Conveyor
	local five = belt.Buttons[2]
	five.Text = "BOUGHT!"
	TechShopView.style(five, true, Theme.Good, Theme.GoodDark)
	TechShopView.showReceipt(machines, "Bought 5 Conveyors! Place them in Build mode.", Theme.Good)
	exports.ui_tech_machines = UiExport.export({ hud1.Gui, machines.Gui })

	-- UPGRADES: a card that can't be bought says why
	local hud2 = hud(scale)
	local upgrades = view(scale, false, pcWidth, pcHeight, "Upgrades")
	TechShopView.setStatus(upgrades, "Upgrade:AutoCleaner:Quality", "Not enough coins", Theme.Bad)
	exports.ui_tech_upgrades = UiExport.export({ hud2.Gui, upgrades.Gui })

	-- AUTOMATION
	local hud3 = hud(scale)
	local automation = view(scale, false, pcWidth, pcHeight, "Automation")
	exports.ui_tech_automation = UiExport.export({ hud3.Gui, automation.Gui })

	-- phones: the compact layout
	local hud4 = hud(phoneScale)
	local phone = view(phoneScale, true, 1600 / phoneScale, (900 - 58) / phoneScale, "Machines")
	exports.ui_tech_phone = UiExport.export({ hud4.Gui, phone.Gui })
	local hud5 = hud(smallScale)
	local small = view(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale, "Upgrades")
	exports.ui_tech_phone_small = UiExport.export({ hud5.Gui, small.Gui })

	-- MACHINES further down, with the machine slots full (13 placed): the red slot line
	local full = table.clone(Preview.State)
	full.Build = { MachinesUsed = 13, MachineSlots = 13, ConveyorsUsed = 6, ConveyorSlots = 40 }
	local hud6 = hud(scale)
	local more = view(scale, false, pcWidth, pcHeight, "Machines", full)
	scrolled(more, "Machines", 3)
	exports.ui_tech_machines_more = UiExport.export({ hud6.Gui, more.Gui })

	-- UPGRADES further down: no Iron Box / Blast Furnace yet, then Bellows and Slots
	local hud7 = hud(scale)
	local upMore = view(scale, false, pcWidth, pcHeight, "Upgrades")
	scrolled(upMore, "Upgrades", 4)
	exports.ui_tech_upgrades_more = UiExport.export({ hud7.Gui, upMore.Gui })

	-- the small phone's AUTOMATION tab
	local hud8 = hud(smallScale)
	local smallAuto = view(smallScale, true, 1600 / smallScale, (900 - smallInset) / smallScale, "Automation")
	exports.ui_tech_phone_more = UiExport.export({ hud8.Gui, smallAuto.Gui })

	-- a console on a 1080p TV (TechShopView.compactFor): 1920 x 1080 drawn at 1600 x 900
	local tvScale = 1.25 * 900 / 1080
	local hud9 = hud(tvScale)
	local tv = view(tvScale, true, 1600 / tvScale, (900 - 36 * 900 / 1080) / tvScale, "Machines")
	local tvBelt = tv.Rows.Conveyor
	tvBelt.Buttons[1]:SetAttribute("Busy", true)
	tvBelt.Buttons[1].Text = "..."
	TechShopView.setStatus(tv, "Conveyor", TechShopView.StatusText.Waiting, Theme.Info)
	exports.ui_tech_tv = UiExport.export({ hud9.Gui, tv.Gui })
	return exports
end

return Preview
