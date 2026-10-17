--[[
	The Tech shop view at the UPGRADES stall (pure builder + pure helpers;
	TechShopController fills it in). One ScreenGui:

	  header   TECH SHOP, a line about the shop (or the last message: HUD
	           toasts hide behind the panel), your coins, the X button
	  tabs     MACHINES · UPGRADES · AUTOMATION (LB / RB on a gamepad)
	  lists    one scrolling list per tab, one row per thing you can buy:
	           an icon drawn from frames (Factory Kit colors), the name, a
	           chip (footprint / level), what it does, what you have or what
	           the next level gives, the price and the BUY button(s)
	    MACHINES    every MachineData.Buildable machine: price each, how many
	                wait in your Build menu and how many are placed, BUY
	                (conveyors: BUY 1 and BUY 5)
	    UPGRADES    every machine type's Speed (and the Cleaning Plant's
	                Quality) level with the next price, then Bellows and
	                machine Slots (they work on all machines)
	    AUTOMATION  pen automation level 1 "Auto-Sort Billboard" and level 2
	                "Train Direct Unload" (level 2 needs level 1)
	  footer   the control hint (not on phones)

	A row shows the server's answer for a moment (the controller sets its
	status line and button text). Designed for 720 design units of height
	(HudController.uiScale); the compact layout (phones, uiScale 0.62) makes
	every button at least 44 pt (TechShopView.touchTargets lists them for the
	tests) and puts the price above the buttons, so the text keeps its room.
	The panel fits the space it gets (TechShopView.layout) and sits below
	the HUD coins when there is room (on phones it covers them whole; its
	header shows your coins).
	Prices and levels come from EconomyConfig (techPrice / techLevel), read
	from the State snapshot (it carries MachineInventory, MachineUpgrades,
	Upgrades, Placed, Build, Perks with the same shapes as the save), so the
	cards always show what the server will quote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MachineData = require(Shared.Config.MachineData)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local HudView = require(script.Parent.HudView)
local TrainView = require(script.Parent.TrainView)

local TechShopView = {}

export type Tab = "Machines" | "Upgrades" | "Automation"

-- One BUY button on a card.
export type Buy = {
	Text: string, -- the button text ("BUY", "BUY 5", "MAX", "OWNED", "LOCKED")
	Count: number?, -- ShopBuy Count (machines)
	Level: number?, -- ShopBuy Level (levelled items: the level being bought)
	Price: number?, -- nil when it can't be bought (Reason says why)
	Reason: string?, -- why it can't be bought now: a TechShop.Reasons code or "Locked"
	CanBuy: boolean, -- for sale and affordable
}

-- What one row shows (TechShopView.cards).
export type Card = {
	Id: string, -- row id: the Item string, or "PenAutomation:<level>"
	Item: string, -- ShopBuy Item
	Tab: Tab,
	Order: number,
	Title: string,
	Description: string,
	Detail: string, -- what you have / what the next level gives
	DetailColor: Color3,
	Chip: string, -- footprint ("2x2") or level ("LV 2/5"), "ACTIVE"
	ChipColor: Color3,
	PriceText: string, -- "$25K"; "" when done
	PriceSub: string, -- "each" / "level 3"
	PriceColor: Color3, -- red when you can't afford it
	Done: boolean, -- top level / owned: nothing more to buy
	Buys: { Buy },
	Icon: string, -- TechShopView.icon kind
	Badge: string?, -- "Speed" | "Quality": a small badge on the icon
	Note: string?, -- why a row is locked
}

export type Row = {
	Id: string,
	Tab: Tab,
	Item: string,
	Frame: Frame,
	Icon: Frame,
	Title: TextLabel,
	Chip: TextLabel,
	Description: TextLabel,
	Detail: TextLabel,
	Status: TextLabel, -- the server's answer for a moment (replaces Detail)
	Price: TextLabel,
	PriceSub: TextLabel,
	Buttons: { TextButton },
	Card: Card?,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Receipt: TextLabel,
	Balance: Frame,
	BalanceAmount: TextLabel,
	Close: TextButton,
	TabBar: Frame,
	Tabs: { [string]: TextButton }, -- by Tab
	TabGlyphs: { ImageLabel }, -- LB (left) and RB (right), shown with a gamepad
	Lists: { [string]: ScrollingFrame }, -- by Tab
	Groups: { TextLabel }, -- the group headers in the UPGRADES list
	Rows: { [string]: Row },
	RowList: { Row }, -- every row in catalog order
	Hint: TextLabel,
	Tab: string, -- the shown Tab
	Compact: boolean,
}

local TABS: { Tab } = { "Machines", "Upgrades", "Automation" }
TechShopView.Tabs = TABS

-- The Tab named `name`, or nil (a Tab from a plain string).
function TechShopView.toTab(name: any): Tab?
	if name == "Machines" then
		return "Machines"
	elseif name == "Upgrades" then
		return "Upgrades"
	elseif name == "Automation" then
		return "Automation"
	end
	return nil
end
TechShopView.TabTitles = { Machines = "MACHINES", Upgrades = "UPGRADES", Automation = "AUTOMATION" } :: { [string]: string }
TechShopView.PhoneScale = 0.62 -- HudController's floor (phones)
TechShopView.MinTouch = 44 -- points
TechShopView.ConveyorPack = 5 -- the second button on conveyors: BUY 5
-- where the "FOR ALL MACHINES" header sits in the UPGRADES list (Bellows / Slots come after it)
TechShopView.AllMachinesOrder = 1000
TechShopView.MinHeight = 380 -- the panel never gets shorter (header, tabs and one row)
TechShopView.CoinsBottom = 96 -- HudView's coins panel (16..90) and a gap: a panel below this leaves it clear

-- Pen automation steps (EconomyConfig.PenAutomation levels).
TechShopView.Automation = {
	{
		Name = "Auto-Sort Billboard",
		Icon = "Billboard",
		Description = 'A sorting billboard at your Ore Pen: mark the ore types you always keep. "Send unkept" puts the rest on your belts.',
		Next = 'Unlocks "Send unkept" at your Ore Pen',
		Active = "Active: mark ores to keep at your Ore Pen or Iron Box",
	},
	{
		Name = "Train Direct Unload",
		Icon = "Train",
		Description = "Your train unloads dirty ore onto your TRAIN chute belt, straight to your Cleaning Plant (no belt there: into the Ore Pen).",
		Next = "Put a belt on your TRAIN chute to use it",
		Active = "Active: your train feeds the TRAIN chute belt",
	},
}

local rgb = Color3.fromRGB

-- Factory Kit colors (MachineBuilder's palette) for the icons.
local C = {
	Housing = rgb(122, 128, 146),
	HousingTop = rgb(156, 162, 180),
	HousingLight = rgb(184, 188, 200),
	HousingDark = rgb(86, 90, 106),
	Recess = rgb(40, 40, 50),
	Copper = rgb(198, 112, 62),
	Brass = rgb(225, 185, 90),
	Hazard = rgb(255, 150, 36),
	Glow = rgb(255, 120, 30),
	Clay = rgb(150, 92, 76),
	ClayTop = rgb(178, 112, 94),
	Wood = rgb(176, 120, 70),
	WoodDark = rgb(110, 70, 40),
	Leather = rgb(96, 58, 40),
	Belt = rgb(46, 44, 52),
	Water = rgb(120, 200, 240),
	Iron = rgb(96, 100, 106),
	IronTop = rgb(134, 138, 144),
	Steel = rgb(206, 210, 216),
	Screen = rgb(36, 150, 132),
	Green = rgb(90, 220, 110),
	Gold = rgb(255, 200, 70),
	Dirt = rgb(132, 96, 70),
	Gem = rgb(110, 230, 255),
}

TechShopView.CategoryColors = {
	Processing = rgb(236, 128, 56),
	Logistics = rgb(90, 160, 230),
} :: { [string]: Color3 }

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	TabBar: number,
	TabHeight: number,
	Footer: number,
	Row: number,
	Icon: number,
	Button: number,
	BuyWidth: number, -- one-button rows
	PackWidth: number, -- each button of two-button rows
	PriceWidth: number,
	ChipWidth: number,
	Title: number,
	Description: number,
	Detail: number,
	Close: number,
}

local PAD = 16
local SCROLLBAR = 10
local GAP = 8

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 920,
		Height = 600,
		Header = 82,
		TabBar = 62,
		TabHeight = 48,
		Footer = 30,
		Row = 118,
		Icon = 94,
		Button = 54,
		BuyWidth = 112,
		PackWidth = 96,
		PriceWidth = 104,
		ChipWidth = 92,
		Title = 24,
		Description = 16,
		Detail = 18,
		Close = 54,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1080,
		Height = 580,
		Header = 64,
		TabBar = 84,
		TabHeight = 72,
		Footer = 6,
		Row = 140,
		Icon = 104,
		Button = 72,
		BuyWidth = 124,
		PackWidth = 112,
		PriceWidth = 112,
		ChipWidth = 104,
		Title = 26,
		Description = 18,
		Detail = 20,
		Close = 72,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

-- "8 s", "6.4 s"
function TechShopView.seconds(t: number): string
	local text = string.format("%.1f", t)
	text = text:gsub("%.0$", "")
	return text .. " s"
end

local function percent(share: number?): string
	return `{math.floor((share or 0) * 100 + 0.5)}%`
end

-- The tab after (dir = 1) or before (dir = -1) `tab`, wrapping around.
function TechShopView.nextTab(tab: string, dir: number): Tab
	local index = 1
	for i, name in TABS do
		if name == tab then
			index = i
		end
	end
	return TABS[(index - 1 + (if dir < 0 then -1 else 1)) % #TABS + 1]
end

local function num(value: any): number
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end

-- Placed machines of one type in a State snapshot's Placed list.
function TechShopView.placedCount(state: any, machineId: string): number
	local placed = if type(state) == "table" then state.Placed else nil
	local n = 0
	if type(placed) == "table" then
		for _, entry in placed do
			if type(entry) == "table" and entry.Id == machineId then
				n += 1
			end
		end
	end
	return n
end

local function safeState(state: any): { [string]: any }
	return if type(state) == "table" then state else {}
end

local function workshop(state: { [string]: any }): boolean
	local perks = state.Perks
	return type(perks) == "table" and perks.Workshop == true
end

local function bellowsLevel(state: { [string]: any }): number
	local bought = state.Upgrades
	return if type(bought) == "table" then num(bought.Bellows) else 0
end

-- One BUY button for a price (nil price: `reason` says why).
local function buyOf(text: string, price: number?, reason: string?, coins: number, count: number?, level: number?): Buy
	local why = reason
	if price ~= nil and coins < price then
		why = "NoCoins"
	end
	return {
		Text = text,
		Count = count,
		Level = level,
		Price = price,
		Reason = if price ~= nil and coins >= price then nil else why,
		CanBuy = price ~= nil and coins >= price,
	}
end

local function doneBuy(text: string): Buy
	return { Text = text, Price = nil, Reason = "Max", CanBuy = false }
end

local function machineCard(entry: EconomyConfig.TechItem, state: { [string]: any }, coins: number, order: number): Card
	local machine = MachineData.ById[entry.Machine :: string]
	local owned = EconomyConfig.inventoryCount(state, machine.Id)
	local placed = TechShopView.placedCount(state, machine.Id)
	local counts: { number } = if machine.IsConveyor then { 1, TechShopView.ConveyorPack } else { 1 }
	local buys: { Buy } = {}
	for _, n in counts do
		local price, reason = EconomyConfig.techPrice(entry, state, n)
		local text = if #counts > 1 then `BUY {n}` else "BUY"
		table.insert(buys, buyOf(text, price, reason, coins, n, nil))
	end
	local detail = if owned == 0 and placed == 0
		then "You don't have one yet"
		else `In your Build menu: {Format.commas(owned)}   •   Placed: {Format.commas(placed)}`
	local full = owned >= EconomyConfig.TechShop.MaxOwned
	return {
		Id = entry.Item,
		Item = entry.Item,
		Tab = "Machines",
		Order = order,
		Title = machine.Name,
		Description = machine.Description,
		Detail = if full then EconomyConfig.TechShop.Reasons.MaxOwned else detail,
		DetailColor = if full then Theme.Bad elseif owned > 0 or placed > 0 then Theme.Text else Theme.TextDim,
		Chip = `{machine.Size[1]}x{machine.Size[2]}`,
		ChipColor = TechShopView.CategoryColors[machine.Category] or Theme.PanelDark,
		PriceText = Format.money(machine.Price),
		PriceSub = "each",
		PriceColor = if coins >= machine.Price then Theme.Coin else Theme.Bad,
		Done = false,
		Buys = buys,
		Icon = machine.Id,
		Badge = nil,
		Note = nil,
	}
end

-- What the current level has and the next one gives (Detail line).
local function levelDetail(entry: EconomyConfig.TechItem, state: { [string]: any }, level: number, max: number): string
	local done = level >= max
	if entry.Kind == "Upgrade" then
		local machine = MachineData.ById[entry.Machine :: string]
		if entry.Upgrade == "Quality" then
			local now = MachineData.gradeOdds(level)
			if done then
				return `Pristine {percent(now.Pristine)}   •   Flawless {percent(now.Flawless)}   (top level)`
			end
			local nextOdds = MachineData.gradeOdds(level + 1)
			local pristine = `Pristine {percent(now.Pristine)} → {percent(nextOdds.Pristine)}`
			return `{pristine}   •   Flawless {percent(now.Flawless)} → {percent(nextOdds.Flawless)}`
		end
		local bellows = bellowsLevel(state)
		local now = TechShopView.seconds(MachineData.processTime(machine, bellows, level))
		if done then
			return `Per item: {now} (top level)`
		end
		return `Per item: {now} → {TechShopView.seconds(MachineData.processTime(machine, bellows, level + 1))}`
	elseif entry.Kind == "Bellows" then
		local step = MachineData.Bellows.SpeedPerLevel
		local now = percent(1 - step * level)
		if done then
			return `Job time {now} (top level)`
		end
		return `Job time {now} → {percent(1 - step * (level + 1))}`
	end
	local shop = workshop(state)
	local now = MachineData.machineSlots(level, shop)
	if done then
		return `Machine slots: {now} (top level)`
	end
	return `Machine slots: {now} → {MachineData.machineSlots(level + 1, shop)}`
end

local function levelDescription(entry: EconomyConfig.TechItem): string
	if entry.Kind == "Upgrade" then
		local machine = MachineData.ById[entry.Machine :: string]
		if entry.Upgrade == "Quality" then
			return `Every {machine.Name} cleans better: more Pristine and Flawless ore, which earns more on your podiums.`
		end
		return `Every {machine.Name} you place works faster: each level takes {percent(MachineData.SpeedPerLevel)} off the time per item.`
	elseif entry.Kind == "Bellows" then
		return `Pumps air into every machine on your plot: each level takes {percent(MachineData.Bellows.SpeedPerLevel)} off every job.`
	end
	return `Room for {MachineData.SlotUpgrade.Amount} more machines on your plot. Belts don't use machine slots.`
end

local function levelTitle(entry: EconomyConfig.TechItem): string
	if entry.Kind == "Upgrade" then
		return `{MachineData.ById[entry.Machine :: string].Name} {entry.Upgrade}`
	elseif entry.Kind == "Bellows" then
		return "Bellows"
	end
	return "Machine Slots"
end

local function levelCard(entry: EconomyConfig.TechItem, state: { [string]: any }, coins: number, order: number): Card
	local level, max = EconomyConfig.techLevel(entry, state)
	local done = level >= max
	local price = if done then nil else (entry.Prices :: { number })[level + 1]
	local buys = if done then { doneBuy("MAX") } else { buyOf("BUY", price, nil, coins, nil, level + 1) }
	return {
		Id = entry.Item,
		Item = entry.Item,
		Tab = "Upgrades",
		Order = order,
		Title = levelTitle(entry),
		Description = levelDescription(entry),
		Detail = levelDetail(entry, state, level, max),
		DetailColor = if done then Theme.Good else Theme.Accent,
		Chip = `LV {level}/{max}`,
		ChipColor = if done then Theme.GoodDark else Theme.PanelDark,
		PriceText = if price then Format.money(price) else "",
		PriceSub = if done then "" else `level {level + 1}`,
		PriceColor = if price and coins < price then Theme.Bad else Theme.Coin,
		Done = done,
		Buys = buys,
		Icon = if entry.Kind == "Upgrade" then entry.Machine :: string else entry.Kind,
		Badge = if entry.Kind == "Upgrade" then entry.Upgrade else nil,
		Note = nil,
	}
end

local function automationCard(entry: EconomyConfig.TechItem, state: { [string]: any }, coins: number, step: number, order: number): Card
	local info = TechShopView.Automation[step]
	local level = EconomyConfig.techLevel(entry, state)
	local prices = entry.Prices :: { number }
	local price = prices[step]
	local owned = level >= step
	local locked = level < step - 1
	local note: string? = nil
	local buys: { Buy }
	if owned then
		buys = { doneBuy("OWNED") }
	elseif locked then
		local before = TechShopView.Automation[step - 1]
		note = `Needs the {if before then before.Name else "step before"} first`
		buys = { { Text = "LOCKED", Price = nil, Reason = "Locked", CanBuy = false } }
	else
		buys = { buyOf("BUY", price, nil, coins, nil, step) }
	end
	return {
		Id = `{entry.Item}:{step}`,
		Item = entry.Item,
		Tab = "Automation",
		Order = order,
		Title = info.Name,
		Description = info.Description,
		Detail = if owned then info.Active elseif note then note else info.Next,
		DetailColor = if owned then Theme.Good elseif note then Theme.TextDim else Theme.Accent,
		Chip = if owned then "ACTIVE" else `LEVEL {step}`,
		ChipColor = if owned then Theme.GoodDark else Theme.PanelDark,
		PriceText = if owned then "" else Format.money(price),
		PriceSub = "",
		PriceColor = if not owned and not locked and coins < price then Theme.Bad else Theme.Coin,
		Done = owned,
		Buys = buys,
		Icon = info.Icon,
		Badge = nil,
		Note = note,
	}
end

--[[
	Every card of the shop from a State snapshot and your coins, in catalog
	order: the machines, the machine upgrades (by machine, Speed then
	Quality), Bellows, Slots, then the two pen automation steps.
]]
function TechShopView.cards(rawState: any, coins: number): { Card }
	local state = safeState(rawState)
	local cash = num(coins)
	local list: { Card } = {}
	local order = 0
	local function add(card: Card)
		table.insert(list, card)
	end
	-- machines first, then the per-machine upgrades, then Bellows and Slots
	for _, entry in EconomyConfig.TechShop.Items do
		order += 1
		if entry.Kind == "Machine" then
			add(machineCard(entry, state, cash, order))
		end
	end
	for _, entry in EconomyConfig.TechShop.Items do
		order += 1
		if entry.Kind == "Upgrade" then
			add(levelCard(entry, state, cash, order))
		end
	end
	for _, entry in EconomyConfig.TechShop.Items do
		order += 1
		if entry.Kind == "Bellows" or entry.Kind == "Slots" then
			-- after the "FOR ALL MACHINES" header
			add(levelCard(entry, state, cash, order + TechShopView.AllMachinesOrder))
		end
	end
	local automation = EconomyConfig.techItem("PenAutomation")
	if automation then
		for step = 1, #TechShopView.Automation do
			order += 1
			add(automationCard(automation, state, cash, step, order))
		end
	end
	return list
end

---------------------------------------------------------------- icons

-- A rectangle in scale units of the icon (x0, y0 top left .. x1, y1 bottom right).
local function bit(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number, color: Color3, round: number?): Frame
	local frame = UIKit.new("Frame", {
		Name = name,
		Position = UDim2.fromScale(x0, y0),
		Size = UDim2.fromScale(x1 - x0, y1 - y0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent)
	if round then
		UIKit.new("UICorner", { CornerRadius = UDim.new(round, 0) }, frame)
	end
	UIKit.stroke(frame, 1.5)
	return frame
end

local function glyph(parent: Instance, text: string, x0: number, y0: number, x1: number, y1: number, color: Color3)
	UIKit.label(parent, text, 18, {
		Name = "Glyph",
		Position = UDim2.fromScale(x0, y0),
		Size = UDim2.fromScale(x1 - x0, y1 - y0),
		TextColor3 = color,
		TextScaled = true,
		TextWrapped = false,
		FontFace = Theme.TitleFont,
	})
end

local DRAW: { [string]: (Frame) -> () } = {
	Conveyor = function(a: Frame)
		bit(a, "Rail", 0.04, 0.62, 0.96, 0.74, C.HousingLight, 0.4)
		bit(a, "Belt", 0.06, 0.4, 0.94, 0.64, C.Belt, 0.5)
		bit(a, "Roller", 0.06, 0.4, 0.3, 0.64, C.Housing, 0.5)
		bit(a, "Roller", 0.7, 0.4, 0.94, 0.64, C.Housing, 0.5)
		glyph(a, ">>", 0.32, 0.42, 0.68, 0.62, C.Hazard)
		bit(a, "Ore", 0.36, 0.2, 0.6, 0.42, C.Dirt, 0.35)
		bit(a, "Leg", 0.14, 0.74, 0.22, 0.9, C.HousingDark)
		bit(a, "Leg", 0.78, 0.74, 0.86, 0.9, C.HousingDark)
	end,
	CleaningStation = function(a: Frame)
		bit(a, "Tap", 0.78, 0.12, 0.86, 0.4, C.Copper)
		bit(a, "Basin", 0.56, 0.32, 0.92, 0.48, C.Water, 0.3)
		bit(a, "Gem", 0.16, 0.24, 0.42, 0.46, C.Gold, 0.35)
		bit(a, "Top", 0.04, 0.46, 0.96, 0.6, C.HousingTop, 0.2)
		bit(a, "Body", 0.1, 0.58, 0.9, 0.86, C.Housing)
		bit(a, "Drawer", 0.2, 0.64, 0.44, 0.76, C.HousingLight)
		bit(a, "Trim", 0.06, 0.84, 0.94, 0.94, C.Hazard)
	end,
	ClayFurnace = function(a: Frame)
		bit(a, "Chimney", 0.62, 0.06, 0.78, 0.3, C.Copper)
		bit(a, "Rim", 0.58, 0.02, 0.82, 0.1, C.HousingLight)
		bit(a, "Body", 0.14, 0.3, 0.86, 0.9, C.Clay, 0.12)
		bit(a, "Top", 0.1, 0.24, 0.9, 0.36, C.ClayTop, 0.2)
		bit(a, "Mouth", 0.3, 0.5, 0.7, 0.86, C.Recess, 0.25)
		bit(a, "Glow", 0.36, 0.62, 0.64, 0.86, C.Glow, 0.25)
		bit(a, "Trim", 0.1, 0.86, 0.9, 0.96, C.Hazard)
	end,
	Crusher = function(a: Frame)
		bit(a, "Hopper", 0.04, 0.14, 0.96, 0.34, C.HousingTop, 0.1)
		bit(a, "Mouth", 0.14, 0.18, 0.86, 0.3, C.Recess)
		bit(a, "Body", 0.12, 0.32, 0.84, 0.9, C.Housing, 0.08)
		bit(a, "Cog", 0.66, 0.44, 0.98, 0.76, C.Gold, 0.5)
		bit(a, "Hub", 0.77, 0.55, 0.87, 0.65, C.HousingDark, 0.5)
		bit(a, "Slot", 0.2, 0.62, 0.5, 0.82, C.Recess)
		bit(a, "Trim", 0.08, 0.88, 0.88, 0.96, C.Hazard)
	end,
	AutoCleaner = function(a: Frame)
		bit(a, "Lamp", 0.78, 0.04, 0.92, 0.18, C.Green, 0.5)
		bit(a, "Leg", 0.1, 0.28, 0.24, 0.86, C.Hazard)
		bit(a, "Leg", 0.76, 0.28, 0.9, 0.86, C.Hazard)
		bit(a, "Beam", 0.04, 0.18, 0.96, 0.32, C.HousingLight, 0.2)
		bit(a, "Nozzle", 0.4, 0.3, 0.6, 0.42, C.Brass)
		bit(a, "Jet", 0.45, 0.42, 0.55, 0.68, C.Water)
		bit(a, "Ore", 0.36, 0.62, 0.64, 0.8, C.Gem, 0.35)
		bit(a, "Bed", 0.02, 0.8, 0.98, 0.92, C.Belt, 0.4)
	end,
	IronBox = function(a: Frame)
		bit(a, "Body", 0.1, 0.28, 0.9, 0.9, C.Iron, 0.08)
		bit(a, "Lid", 0.06, 0.18, 0.94, 0.32, C.IronTop, 0.15)
		bit(a, "Strap", 0.2, 0.18, 0.28, 0.9, C.Steel)
		bit(a, "Strap", 0.72, 0.18, 0.8, 0.9, C.Steel)
		bit(a, "Screen", 0.34, 0.42, 0.66, 0.62, C.Screen, 0.15)
		bit(a, "Slot", 0.36, 0.72, 0.64, 0.8, C.Recess)
	end,
	BlastFurnace = function(a: Frame)
		bit(a, "Chimney", 0.42, 0.02, 0.58, 0.16, C.Copper)
		bit(a, "Pipe", 0.02, 0.48, 0.18, 0.58, C.Copper)
		bit(a, "Top", 0.24, 0.14, 0.76, 0.28, C.HousingDark, 0.1)
		bit(a, "Body", 0.16, 0.26, 0.84, 0.9, C.Housing, 0.08)
		bit(a, "Window", 0.28, 0.42, 0.72, 0.76, C.Recess, 0.1)
		for i, x in { 0.33, 0.46, 0.59 } do
			bit(a, "Bar" .. i, x, 0.47, x + 0.08, 0.71, C.Glow)
		end
		bit(a, "Trim", 0.12, 0.88, 0.88, 0.96, C.Hazard)
	end,
	Bellows = function(a: Frame)
		bit(a, "Nozzle", 0.6, 0.44, 0.9, 0.56, C.Brass)
		bit(a, "Tip", 0.86, 0.4, 0.96, 0.6, C.Copper, 0.3)
		bit(a, "Leather", 0.2, 0.24, 0.66, 0.76, C.Leather, 0.2)
		for i, y in { 0.34, 0.47, 0.6 } do
			bit(a, "Pleat" .. i, 0.18, y, 0.66, y + 0.05, C.WoodDark)
		end
		bit(a, "Board", 0.1, 0.14, 0.68, 0.26, C.Wood, 0.3)
		bit(a, "Board", 0.1, 0.74, 0.68, 0.86, C.Wood, 0.3)
		bit(a, "Handle", 0.02, 0.1, 0.16, 0.3, C.WoodDark, 0.3)
		bit(a, "Handle", 0.02, 0.7, 0.16, 0.9, C.WoodDark, 0.3)
	end,
	Slots = function(a: Frame)
		bit(a, "Cell", 0.06, 0.06, 0.46, 0.46, C.Housing, 0.12)
		bit(a, "Cell", 0.54, 0.06, 0.94, 0.46, C.Clay, 0.12)
		bit(a, "Cell", 0.06, 0.54, 0.46, 0.94, C.Iron, 0.12)
		bit(a, "Free", 0.54, 0.54, 0.94, 0.94, C.Belt, 0.12)
		bit(a, "Plus", 0.7, 0.6, 0.78, 0.88, C.Green)
		bit(a, "Plus", 0.6, 0.7, 0.88, 0.78, C.Green)
	end,
	Billboard = function(a: Frame)
		bit(a, "Post", 0.2, 0.56, 0.28, 0.96, C.WoodDark)
		bit(a, "Post", 0.72, 0.56, 0.8, 0.96, C.WoodDark)
		bit(a, "Board", 0.04, 0.04, 0.96, 0.64, C.Wood, 0.08)
		bit(a, "Face", 0.1, 0.1, 0.9, 0.58, Theme.PanelLight, 0.06)
		local ores = { C.Gem, C.Gold, rgb(200, 90, 255) }
		for i, y in { 0.14, 0.29, 0.44 } do
			bit(a, "Ore" .. i, 0.15, y, 0.27, y + 0.11, ores[i], 0.5)
			bit(a, "Line" .. i, 0.31, y + 0.03, 0.66, y + 0.08, Theme.TextDim)
			bit(a, "Keep" .. i, 0.71, y, 0.84, y + 0.11, if i == 2 then Theme.PanelDark else C.Green, 0.2)
		end
	end,
	Train = function(a: Frame)
		local icon = TrainView.icon(a, 10)
		icon.Size = UDim2.fromScale(0.86, 0.86 / 1.36)
		icon.Position = UDim2.fromScale(0.07, 0.06)
		bit(a, "Belt", 0.04, 0.76, 0.96, 0.94, C.Belt, 0.5)
		glyph(a, ">>", 0.3, 0.77, 0.7, 0.93, C.Hazard)
	end,
}

--[[
	A square icon (`size` design units): a dark tile with a little picture
	of `kind` (a machine id, "Bellows", "Slots", "Billboard", "Train"; an
	unknown kind gets a plain gear tile). `badge` "Speed" | "Quality" adds a
	small badge in the bottom right corner.
]]
function TechShopView.icon(parent: Instance, size: number, kind: string, badge: string?): Frame
	local tile = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(tile, 12)
	UIKit.stroke(tile, 2.5)
	TechShopView.setIcon(tile, kind, badge)
	return tile
end

-- Redraws an icon tile for another kind / badge.
function TechShopView.setIcon(tile: Frame, kind: string, badge: string?)
	if tile:GetAttribute("Kind") == kind and tile:GetAttribute("Badge") == (badge or "") then
		return
	end
	tile:SetAttribute("Kind", kind)
	tile:SetAttribute("Badge", badge or "")
	local old = tile:FindFirstChild("Art")
	if old then
		old:Destroy()
	end
	local art = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundTransparency = 1,
	}, tile)
	local draw = DRAW[kind]
	if draw then
		draw(art)
	else
		bit(art, "Plain", 0.2, 0.2, 0.8, 0.8, C.Housing, 0.2)
	end
	if badge == "Speed" then
		local b = bit(art, "Badge", 0.62, 0.66, 1.06, 1.1, Theme.Accent, 0.5)
		glyph(b, ">>", 0.12, 0.18, 0.88, 0.82, Theme.Text)
	elseif badge == "Quality" then
		local b = bit(art, "Badge", 0.64, 0.68, 1.04, 1.08, C.Gem, 0.2)
		b.Rotation = 45
	end
end

---------------------------------------------------------------- building

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

-- Colors a button: enabled in its own colors, or greyed out.
local function style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	button.BackgroundColor3 = if enabled then color else Theme.PanelLight
	holderOf(button).BackgroundColor3 = if enabled then dark else Theme.PanelDark
	button.TextColor3 = if enabled then Theme.Text else Theme.TextDim
end
TechShopView.style = style

type RowSpec = { Id: string, Tab: Tab, Item: string, Order: number, Buttons: number, Icon: string, Badge: string? }

-- The rows the shop always has (the catalog is fixed), in catalog order.
function TechShopView.rowSpecs(): { RowSpec }
	local specs: { RowSpec } = {}
	for _, card in TechShopView.cards({}, 0) do
		table.insert(specs, {
			Id = card.Id,
			Tab = card.Tab,
			Item = card.Item,
			Order = card.Order,
			Buttons = #card.Buys,
			Icon = card.Icon,
			Badge = card.Badge,
		})
	end
	return specs
end

local function newRow(refs: Refs, spec: RowSpec, m: Metrics): Row
	local frame = UIKit.new("Frame", {
		Name = spec.Id,
		LayoutOrder = spec.Order,
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
	}, refs.Lists[spec.Tab])
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2.5)
	local icon = TechShopView.icon(frame, m.Icon, spec.Icon, spec.Badge)
	local title = UIKit.label(frame, "", m.Title, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local chip = UIKit.chip(frame, "", Theme.PanelDark, { Name = "Chip" })
	local description = UIKit.label(frame, "", m.Description, {
		Name = "Description",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
		-- a longer text never runs into the detail line
		ClipsDescendants = true,
	})
	local detail = UIKit.label(frame, "", m.Detail, {
		Name = "Detail",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local status = UIKit.label(frame, "", m.Detail, {
		Name = "Status",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
	})
	local price = UIKit.label(frame, "", 22, {
		Name = "Price",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
	})
	local priceSub = UIKit.label(frame, "", 14, {
		Name = "PriceSub",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local buttons: { TextButton } = {}
	for i = 1, math.max(1, spec.Buttons) do
		table.insert(buttons, UIKit.button(frame, "BUY", Theme.Accent, Theme.AccentDark, { Name = "Buy" .. i }))
	end
	local row: Row = {
		Id = spec.Id,
		Tab = spec.Tab,
		Item = spec.Item,
		Frame = frame,
		Icon = icon,
		Title = title,
		Chip = chip,
		Description = description,
		Detail = detail,
		Status = status,
		Price = price,
		PriceSub = priceSub,
		Buttons = buttons,
		Card = nil,
	}
	refs.Rows[spec.Id] = row
	table.insert(refs.RowList, row)
	return row
end

local function groupHeader(list: ScrollingFrame, text: string, order: number): TextLabel
	return UIKit.label(list, text, 20, {
		Name = "Group",
		LayoutOrder = order,
		Size = UDim2.new(1, -SCROLLBAR, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
	})
end

function TechShopView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeTechShop", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(METRICS.Normal.Width, METRICS.Normal.Height),
		Active = true,
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	local title = UIKit.label(panel, "TECH SHOP", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local subtitle = UIKit.label(panel, "Machines and upgrades for your base. Machines you buy wait in your Build menu.", 16, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local receipt = UIKit.label(panel, "", 17, {
		Name = "Receipt",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Good,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
	})
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
	})
	-- your coins, next to the close button (the HUD's may be covered on phones)
	local balance = UIKit.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(balance, 10)
	UIKit.stroke(balance, 2)
	local coin = HudView.coinIcon(balance, 26)
	coin.Position = UDim2.fromOffset(8, 7)
	local balanceAmount = UIKit.label(balance, "$0", 24, {
		Name = "Amount",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -50, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Coin,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- tabs
	local tabBar = UIKit.new("Frame", {
		Name = "TabBar",
		BackgroundTransparency = 1,
	}, panel)
	local tabs: { [string]: TextButton } = {}
	for _, tab in TABS do
		tabs[tab] = UIKit.button(tabBar, TechShopView.TabTitles[tab], Theme.Accent, Theme.AccentDark, {
			Name = "Tab" .. tab,
			TextSize = 22,
		})
	end
	local glyphs: { ImageLabel } = {}
	for _, name in { "GlyphL", "GlyphR" } do
		table.insert(
			glyphs,
			UIKit.new("ImageLabel", {
				Name = name,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(34, 34),
				Visible = false,
				ZIndex = 4,
			}, tabBar)
		)
	end

	-- one list per tab
	local lists: { [string]: ScrollingFrame } = {}
	for _, tab in TABS do
		local list = UIKit.new("ScrollingFrame", {
			Name = "List" .. tab,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = Theme.Accent,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Selectable = false,
			Visible = tab == "Machines",
		}, panel)
		UIKit.list(list, Enum.FillDirection.Vertical, GAP)
		UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10) }, list)
		lists[tab] = list
	end
	local groups = {
		groupHeader(lists.Upgrades, "MACHINE UPGRADES", 0),
		groupHeader(lists.Upgrades, "FOR ALL MACHINES", TechShopView.AllMachinesOrder),
	}

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Receipt = receipt,
		Balance = balance,
		BalanceAmount = balanceAmount,
		Close = close,
		TabBar = tabBar,
		Tabs = tabs,
		TabGlyphs = glyphs,
		Lists = lists,
		Groups = groups,
		Rows = {},
		RowList = {},
		Hint = hint,
		Tab = "Machines",
		Compact = compact == true,
	}
	local m = metrics(refs.Compact)
	for _, spec in TechShopView.rowSpecs() do
		newRow(refs, spec, m)
	end
	TechShopView.setTab(refs, "Machines")
	TechShopView.layout(refs, refs.Compact, math.huge, math.huge)
	return refs
end

---------------------------------------------------------------- layout

-- The width the buttons of a row take (with their gaps).
local function buttonsWidth(row: Row, m: Metrics): number
	local n = #row.Buttons
	local each = if n > 1 then m.PackWidth else m.BuyWidth
	return n * each + (n - 1) * GAP
end

--[[
	One row: icon | title + chip, description, detail | price | buttons.
	Normal: the price sits left of the buttons, both centred. Compact
	(phones): the buttons sit at the bottom right with the price above them,
	so the text gets the price column's room.
]]
local function placeRow(row: Row, m: Metrics, compact: boolean)
	local h = m.Row
	row.Frame.Size = UDim2.new(1, -SCROLLBAR, 0, h)
	row.Icon.Size = UDim2.fromOffset(m.Icon, m.Icon)
	row.Icon.Position = UDim2.fromOffset(10, (h - m.Icon) / 2)
	local n = #row.Buttons
	local each = if n > 1 then m.PackWidth else m.BuyWidth
	local buttons = buttonsWidth(row, m)
	-- the face sits 5 units above its lip
	local buttonTop = if compact then h - m.Button - 8 else (h - m.Button) / 2 + 2
	for i, button in row.Buttons do
		local holder = holderOf(button)
		holder.AnchorPoint = Vector2.new(1, 0)
		holder.Position = UDim2.new(1, -(10 + (n - i) * (each + GAP)), 0, buttonTop)
		holder.Size = UDim2.fromOffset(each, m.Button)
		button.TextSize = if compact then 22 else 20
	end
	local textRight: number
	row.Price.AnchorPoint = Vector2.new(1, 0)
	row.PriceSub.AnchorPoint = Vector2.new(1, 0)
	if compact then
		row.Price.Position = UDim2.new(1, -12, 0, 6)
		row.Price.Size = UDim2.fromOffset(buttons, 26)
		row.PriceSub.Position = UDim2.new(1, -12, 0, 32)
		row.PriceSub.Size = UDim2.fromOffset(buttons, 16)
		textRight = 10 + buttons + 14
	else
		local right = 10 + buttons + 10
		row.Price.Position = UDim2.new(1, -right, 0, h / 2 - 22)
		row.Price.Size = UDim2.fromOffset(m.PriceWidth, 26)
		row.PriceSub.Position = UDim2.new(1, -right, 0, h / 2 + 4)
		row.PriceSub.Size = UDim2.fromOffset(m.PriceWidth, 18)
		textRight = right + m.PriceWidth + 10
	end
	row.Price.TextSize = if compact then 24 else 22
	row.PriceSub.TextSize = if compact then 15 else 14
	local left = m.Icon + 22
	local chipWidth = m.ChipWidth
	row.Chip.AnchorPoint = Vector2.new(1, 0)
	row.Chip.Position = UDim2.new(1, -textRight, 0, 12)
	row.Chip.Size = UDim2.fromOffset(chipWidth, if compact then 28 else 24)
	row.Chip.TextSize = if compact then 16 else 14
	row.Title.Position = UDim2.fromOffset(left, 8)
	row.Title.Size = UDim2.new(1, -(left + textRight + chipWidth + 8), 0, 32)
	row.Title.TextSize = m.Title
	local detailHeight = m.Detail + 6
	row.Description.Position = UDim2.fromOffset(left, 42)
	row.Description.Size = UDim2.new(1, -(left + textRight), 0, h - 42 - detailHeight - 10)
	row.Description.TextSize = m.Description
	for _, line in { row.Detail, row.Status } do
		line.Position = UDim2.fromOffset(left, h - detailHeight - 8)
		-- up to the buttons
		line.Size = UDim2.new(1, -(left + (if compact then textRight else 10 + buttons + 14)), 0, detailHeight)
		line.TextSize = m.Detail
	end
end

--[[
	Sizes everything for the normal or compact (phone) layout and fits the
	panel into `maxWidth` x `maxHeight` design units (the screen divided by
	the UI scale; math.huge = no limit).
]]
function TechShopView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	refs.Compact = compact
	local m = metrics(compact)
	local width = math.max(560, math.min(m.Width, maxWidth - 24))
	local height = math.max(TechShopView.MinHeight, math.min(m.Height, maxHeight - 16))
	-- the HUD coins panel (top left) would peek out beside the panel: move
	-- the panel below it when there is room (on PC it may get a bit shorter
	-- for that, never on phones); a phone panel covers it whole (its header
	-- shows your coins)
	local left = (maxWidth - width) / 2
	local top = (maxHeight - height) / 2
	if maxWidth < 1e6 and maxHeight < 1e6 then
		if left < 16 + HudView.CoinsWidth and top < TechShopView.CoinsBottom then
			local below = maxHeight - TechShopView.CoinsBottom - 8
			if below >= (if compact then height else TechShopView.MinHeight) then
				height = math.min(height, below)
				top = TechShopView.CoinsBottom + (below - height) / 2
			end
		end
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0)
		refs.Panel.Position = UDim2.new(0.5, 0, 0, top)
	else
		refs.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Panel.Position = UDim2.fromScale(0.5, 0.5)
	end
	refs.Panel.Size = UDim2.fromOffset(width, height)

	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -PAD, 0, if compact then 6 else 14)
	local balanceWidth = if compact then 190 else 176
	refs.Balance.Size = UDim2.fromOffset(balanceWidth, 40)
	refs.Balance.Position = UDim2.new(1, -(PAD + m.Close + 12), 0, if compact then 14 else 16)
	local headRight = PAD + m.Close + 12 + balanceWidth + 12
	refs.Title.TextSize = if compact then 30 else 34
	refs.Title.Position = UDim2.fromOffset(PAD, if compact then 10 else 8)
	refs.Title.Size = UDim2.new(1, -(PAD + headRight), 0, 40)
	refs.Subtitle.Position = UDim2.fromOffset(PAD, 50)
	refs.Subtitle.Size = UDim2.new(1, -(PAD * 2 + m.Close), 0, 22)
	refs.Subtitle.Visible = not compact and not refs.Receipt.Visible
	if compact then
		-- next to the title (no room for a second header line)
		local titleWidth = 250
		refs.Title.Size = UDim2.fromOffset(titleWidth, 40)
		refs.Receipt.Position = UDim2.fromOffset(PAD + titleWidth, 4)
		refs.Receipt.Size = UDim2.new(1, -(PAD + titleWidth + headRight), 0, 56)
		refs.Receipt.TextWrapped = true
		refs.Receipt.TextTruncate = Enum.TextTruncate.None
		refs.Receipt.TextSize = 18
	else
		refs.Receipt.Position = UDim2.fromOffset(PAD, 50)
		refs.Receipt.Size = UDim2.new(1, -(PAD * 2 + m.Close), 0, 24)
		refs.Receipt.TextWrapped = false
		refs.Receipt.TextTruncate = Enum.TextTruncate.AtEnd
		refs.Receipt.TextSize = 17
	end

	-- tabs: three equal buttons, room for the LB / RB glyphs at the ends
	refs.TabBar.Position = UDim2.fromOffset(PAD, m.Header)
	refs.TabBar.Size = UDim2.new(1, -PAD * 2, 0, m.TabBar)
	-- each tab: share * W - fixed; tab i starts at inset + (i - 1) * (its width + GAP)
	local count = #TABS
	local inset = 26
	local share = 1 / count
	local fixed = (2 * inset + GAP * (count - 1)) / count
	for i, tab in TABS do
		local holder = holderOf(refs.Tabs[tab])
		holder.Position = UDim2.new(share * (i - 1), inset + (i - 1) * (GAP - fixed), 0, 6)
		holder.Size = UDim2.new(share, -fixed, 0, m.TabHeight)
		refs.Tabs[tab].TextSize = if compact then 24 else 22
	end
	refs.TabGlyphs[1].Position = UDim2.new(0, 12, 0, 6 + m.TabHeight / 2 - 3)
	refs.TabGlyphs[2].Position = UDim2.new(1, -12, 0, 6 + m.TabHeight / 2 - 3)

	local listTop = m.Header + m.TabBar
	for _, list in refs.Lists do
		list.Position = UDim2.fromOffset(PAD, listTop)
		list.Size = UDim2.new(1, -PAD, 1, -(listTop + m.Footer))
	end
	refs.Hint.Visible = not compact
	refs.Hint.Position = UDim2.new(0.5, 0, 1, -6)
	refs.Hint.Size = UDim2.new(1, -PAD * 2, 0, 20)
	for _, row in refs.RowList do
		placeRow(row, m, compact)
	end
end

---------------------------------------------------------------- filling in

-- Shows one tab's list and marks its tab button.
function TechShopView.setTab(refs: Refs, tab: string)
	refs.Tab = tab
	for _, name in TABS do
		local on = name == tab
		refs.Lists[name].Visible = on
		local button = refs.Tabs[name]
		button.BackgroundColor3 = if on then Theme.Accent else Theme.PanelLight
		holderOf(button).BackgroundColor3 = if on then Theme.AccentDark else Theme.PanelDark
		button.TextColor3 = if on then Theme.Text else Theme.TextDim
	end
end

local function fillRow(row: Row, card: Card)
	row.Card = card
	row.Frame.LayoutOrder = card.Order
	row.Title.Text = string.upper(card.Title)
	row.Chip.Text = card.Chip
	row.Chip.BackgroundColor3 = card.ChipColor
	row.Description.Text = card.Description
	row.Detail.Text = card.Detail
	row.Detail.TextColor3 = card.DetailColor
	row.Price.Text = card.PriceText
	row.Price.TextColor3 = card.PriceColor
	row.PriceSub.Text = card.PriceSub
	TechShopView.setIcon(row.Icon, card.Icon, card.Badge)
	for i, button in row.Buttons do
		local buy = card.Buys[i]
		holderOf(button).Visible = buy ~= nil
		if buy then
			-- a button showing an answer ("BOUGHT!", "...") keeps its text until the controller resets it
			if button:GetAttribute("Busy") ~= true then
				button.Text = buy.Text
			end
			if card.Done then
				style(button, false, Theme.Good, Theme.GoodDark)
				button.TextColor3 = Theme.Good
			else
				style(button, buy.CanBuy, Theme.Accent, Theme.AccentDark)
			end
		end
	end
end

-- Fills every row from TechShopView.cards (rows with no card keep their last content).
function TechShopView.setCards(refs: Refs, cards: { Card })
	for _, card in cards do
		local row = refs.Rows[card.Id]
		if row then
			fillRow(row, card)
		end
	end
end

function TechShopView.setCoins(refs: Refs, coins: number)
	refs.BalanceAmount.Text = Format.money(math.max(0, num(coins)))
end

-- A row's status line (the server's answer): text in `color`, or nil to show the Detail line again.
function TechShopView.setStatus(refs: Refs, rowId: string, text: string?, color: Color3?)
	local row = refs.Rows[rowId]
	if not row then
		return
	end
	row.Status.Visible = text ~= nil
	row.Detail.Visible = text == nil
	row.Status.Text = text or ""
	row.Status.TextColor3 = color or Theme.Text
end

-- Shows a message in the header (instead of the subtitle).
function TechShopView.showReceipt(refs: Refs, text: string, color: Color3)
	refs.Receipt.Text = text
	refs.Receipt.TextColor3 = color
	refs.Receipt.Visible = true
	refs.Subtitle.Visible = false
end

function TechShopView.hideReceipt(refs: Refs)
	refs.Receipt.Visible = false
	refs.Subtitle.Visible = not refs.Compact
end

-- The rows of one tab in list order.
function TechShopView.rowsOf(refs: Refs, tab: string): { Row }
	local list: { Row } = {}
	for _, row in refs.RowList do
		if row.Tab == tab then
			table.insert(list, row)
		end
	end
	table.sort(list, function(a, b)
		return a.Frame.LayoutOrder < b.Frame.LayoutOrder
	end)
	return list
end

-- The button a gamepad starts on in a tab: the first one that can buy,
-- else the first shown button, else the tab's own button.
function TechShopView.firstButton(refs: Refs, tab: string): TextButton
	local fallback: TextButton? = nil
	for _, row in TechShopView.rowsOf(refs, tab) do
		local card = row.Card
		for i, button in row.Buttons do
			local buy = card and card.Buys[i]
			if buy and holderOf(button).Visible then
				if buy.CanBuy then
					return button
				end
				fallback = fallback or button
			end
		end
	end
	return fallback or refs.Tabs[tab]
end

-- Every button a finger must hit (for the touch-size tests).
function TechShopView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { holderOf(refs.Close) }
	for _, tab in TABS do
		table.insert(list, holderOf(refs.Tabs[tab]))
	end
	for _, row in refs.RowList do
		for _, button in row.Buttons do
			table.insert(list, holderOf(button))
		end
	end
	return list
end

return TechShopView
