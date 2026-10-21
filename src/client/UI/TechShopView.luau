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
	  footer   the control hint (not on phones); with a gamepad the
	           platform's own button glyphs (TechShopView.setHint)

	Where it was opened (TechShopView.Where, setWhere): at the lobby's
	UPGRADES counter everything is sold; from your base (build mode's SHOP
	button: TechShopController.openMachines) only machines are (ShopService
	sells them at your own plot), so the other tabs' BUYs are greyed out
	and say "at the UPGRADES stall". A note at the top of each list says
	so, and the MACHINES note says where a machine you buy goes (your BUILD
	menu) and how to place it from there (every layout: the subtitle is
	not shown on phones), with the key of the device in use (setDevice:
	B, D-pad Up or a tap on BUILD; TechShopView.BuildKey).

	A row shows the server's answer for a moment (the controller sets its
	status line and button text). Designed for 720 design units of height
	(HudController.uiScale); the compact layout (phones, uiScale 0.62) makes
	every button at least 44 pt (TechShopView.touchTargets lists them for the
	tests) and puts the price above the buttons, so the text keeps its room;
	there the tab bar ends left of the X button, so no two buttons overlap.
	Row texts fit their boxes: TechShopView.fitText shrinks a text a little
	when a generous guess of its size (TechShopView.textWidth / textLines,
	never smaller than the real text) says it would not fit.
	Machine cards show the slot use (snapshot.Build) and turn red when the
	slots are full; upgrade cards warn when you have none of that machine.
	The panel fits the space it gets (TechShopView.layout) and sits below
	the HUD coins when there is room (on phones it covers them whole; its
	header shows your coins).
	Prices and levels come from EconomyConfig (techPrice / techLevel), read
	from the State snapshot (it carries MachineInventory, MachineUpgrades,
	Upgrades, Placed, Build, Perks with the same shapes as the save), so the
	cards always show what the server will quote.

	The look is the Robux Shop's Pop kit (owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"; Pop.luau, PopTheme): a black
	frame, the yellow header band (LightSkin.BandRoles "Build") with the
	title, your coins and the red X, bright tabs (the picked one painted,
	the others slate), every card painted in its machine's category colour
	with the machine's live 3D picture (the build tray's BuildView.picture,
	built when its tab first shows in the open shop: fillPicture) on a light
	burst, the size / level chip, the detail line on a dark strip, the price
	in gold and gold coin BUY buttons (MAX / OWNED / BOUGHT!: a green tag).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MachineData = require(Shared.Config.MachineData)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local PictureModels = require(Shared.Builders.PictureModels)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local HudView = require(script.Parent.HudView)
local TrainView = require(script.Parent.TrainView)
local BuildView = require(script.Parent.BuildView)

local TechShopView = {}

export type Tab = "Machines" | "Upgrades" | "Automation"
--[[
	Where the window was opened (TechShopController):
	  Counter  the lobby's UPGRADES counter: everything is for sale
	  Base     TechShopController.openMachines outside build mode: machines
	           only (bought at your own plot)
	  Build    the same from build mode's SHOP button: closing the shop
	           goes back to build mode
]]
export type Where = "Counter" | "Base" | "Build"
-- The device in use, for the key the notes name (TechShopView.setDevice).
export type Device = "Keyboard" | "Gamepad" | "Touch"

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
	PriceSub: string, -- "each" / "level 3" / "5 for $125" (belts: the BUY 5 total)
	PriceColor: Color3, -- red when you can't afford it
	PriceSubColor: Color3, -- red when you can't afford the BUY 5 total
	Done: boolean, -- top level / owned: nothing more to buy
	Buys: { Buy },
	Icon: string, -- TechShopView.icon kind
	Badge: string?, -- "Speed" | "Quality": a small badge on the icon
	Note: string?, -- why a row is locked
}

-- The room a row's texts get (design units) and their sizes (TechShopView.fitText).
export type Boxes = {
	TitleWidth: number,
	DescriptionWidth: number,
	DescriptionHeight: number,
	DetailWidth: number,
	DetailHeight: number,
	PriceWidth: number,
	Title: number, -- the full text sizes (the layout's metrics)
	Description: number,
	Detail: number,
	PriceSub: number,
	TitleMin: number, -- the smallest they may shrink to
	DescriptionMin: number,
	DetailMin: number,
}

export type Row = {
	Id: string,
	Tab: Tab,
	Item: string,
	Boxes: Boxes,
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
	ReceiptBox: Vector2, -- the room the header message gets (design units), set by layout
	Balance: Frame,
	BalanceAmount: TextLabel,
	Close: TextButton,
	TabBar: Frame,
	Tabs: { [string]: TextButton }, -- by Tab
	TabGlyphs: { ImageLabel }, -- LB (left) and RB (right), shown with a gamepad
	Lists: { [string]: ScrollingFrame }, -- by Tab
	Notes: { [string]: TextLabel }, -- by Tab: the note at the top of each list (TechShopView.setWhere)
	NoteBox: Vector2, -- the room a note's text gets (design units), set by layout
	Where: Where,
	Device: Device, -- whose BUILD key the notes name (TechShopView.setDevice)
	Groups: { TextLabel }, -- the group headers in the UPGRADES list
	Rows: { [string]: Row },
	RowList: { Row }, -- every row in catalog order
	Hint: TextLabel,
	PadHint: Frame, -- gamepad hint: [LB][RB] switch tab  [A] buy  [B] close, the platform's glyphs
	PadGlyphs: { ImageLabel }, -- LB, RB, A, B
	PadMode: boolean, -- the gamepad hint shows (TechShopView.setHint)
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
-- studs from the counter's surface at which the open shop closes: under the
-- server's ShopService.Range (30), so lag never gets an open shop's BUY refused
TechShopView.CloseRange = 24
-- horizontal studs from your plot's centre at which a shop opened there
-- closes: under the server's GameConfig.BuildRange (ShopService.nearOwnPlot)
TechShopView.BaseCloseRange = GameConfig.BuildRange - 6
TechShopView.BaseCloseSlack = 2 -- studs past where it opened, when that was further out

--[[
	The walk-away range of a shop with no counter, from your distance to
	your plot's centre when it opened: BaseCloseRange, or just past where
	it opened when that was further (build mode opens up to BuildRange
	away), never beyond BuildRange. Every opening gets one, so walking away
	always closes it.
]]
function TechShopView.baseCloseRange(distanceAtOpen: number): number
	return math.min(GameConfig.BuildRange, math.max(TechShopView.BaseCloseRange, distanceAtOpen + TechShopView.BaseCloseSlack))
end

--[[
	Pen automation steps (EconomyConfig.PenAutomation levels), as PenService
	runs them (WP-Belts): level 1 sends everything MachineData.keeps doesn't
	keep (dirty and crushed ore, ingots, clean ore off the Keep List) out of
	the PEN chute as it lands in the pen, while a belt feeds from there, and
	unlocks "Send unkept"; level 2 sends the train's dirty ore out of the
	TRAIN chute after it unloaded into the pen as before (same capacity rule).
	Where the Keep List is set: the pen's board (WP-CleanerBox's sorting
	board has a "Keep List" prompt) or an Iron Box. ShopService.boughtText
	says the same.
]]
TechShopView.Automation = {
	{
		Name = "Auto-Sort Billboard",
		Icon = "Billboard",
		Description = 'Everything you don\'t keep rides out of your PEN chute by itself (when a belt is there): dirty ore, ingots and clean ore off your Keep List. Unlocks "Send unkept".',
		Next = "Mark what to keep at the pen board or an Iron Box",
		Active = "Active: mark what to keep at the pen board or an Iron Box",
	},
	{
		Name = "Train Direct Unload",
		Icon = "Train",
		Description = "Your train's dirty ore pours out of the TRAIN chute onto your belts (it still unloads into the pen first; no belt there: it stays in the pen).",
		Next = "Put a belt on your TRAIN chute to use it",
		Active = "Active: train ore pours out of the TRAIN chute",
	},
}

-- Status lines the controller shows on a card (here so the tests can check they fit).
TechShopView.StatusText = {
	-- a levelled BUY with no answer: safe to try again (the server refuses a repeat as Stale)
	NoAnswer = "No answer, try again",
	-- a machine BUY with no answer: it may still have gone through (a repeat buys again)
	NoAnswerMachine = "No answer yet: check your Build menu",
	-- an answer that came after the BUY was given up on
	LateBought = "Bought!",
	-- the card's other button while one BUY waits for its answer
	Waiting = "Wait for your last buy",
	-- a machine BUY refused as "TooFar": machines are sold at your base too
	TooFarMachine = "Go to your BASE or the UPGRADES stall",
	-- a greyed-out upgrade BUY in a shop opened at your base (TechShopView.cards with Where "Base" / "Build")
	CounterOnly = "Buy this at the UPGRADES stall",
}

-- How each device opens build mode, for "{build}" in the notes (the HUD
-- BUILD tile's key: B, D-pad Up, or the tile itself on touch).
TechShopView.BuildKey = {
	Keyboard = "press B (BUILD)",
	Gamepad = "press D-pad Up (BUILD)",
	Touch = "tap BUILD",
} :: { [Device]: string }

-- The subtitle (PC) and the notes at the top of the lists for each Where
-- (TechShopView.setWhere; nil: no note; "{build}": TechShopView.BuildKey).
TechShopView.WhereText = {
	Counter = {
		Subtitle = "Machines and upgrades for your base. Machines you buy wait in your Build menu.",
		Machines = "Machines you buy go to your BUILD menu. Go to your BASE and {build} to place them.",
	},
	Base = {
		Subtitle = "Machines for your base. Upgrades are sold at the UPGRADES stall in the lobby.",
		Machines = "Machines you buy go to your BUILD menu. At your BASE, {build} to place them.",
		Upgrades = "Upgrades are sold at the UPGRADES stall in the lobby.",
		Automation = "Pen automation is sold at the UPGRADES stall in the lobby.",
	},
	Build = {
		Subtitle = "Machines for your base. Upgrades are sold at the UPGRADES stall in the lobby.",
		Machines = "Machines you buy go straight to your BUILD menu. Close the shop to place them.",
		Upgrades = "Upgrades are sold at the UPGRADES stall in the lobby.",
		Automation = "Pen automation is sold at the UPGRADES stall in the lobby.",
	},
} :: { [string]: { [string]: string } }

-- Where from a plain string (the counter for anything else).
function TechShopView.toWhere(name: any): Where
	if name == "Base" then
		return "Base"
	elseif name == "Build" then
		return "Build"
	end
	return "Counter"
end

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
	Selling = rgb(240, 196, 60),
	Power = rgb(120, 220, 120),
	Droppers = rgb(190, 110, 255),
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
	-- the smallest a row text may shrink to (TechShopView.fitText)
	TitleMin: number,
	DescriptionMin: number,
	DetailMin: number,
	Close: number,
	Band: number, -- the header band's height (the title, your coins and the X sit in it)
	TabGap: number, -- room between the tab bar's end and the X button (0: the X sits in the band)
	Note: number, -- the list notes' text size, and the smallest it may shrink to
	NoteMin: number,
}

local PAD = 16
local SCROLLBAR = 10
local GAP = 8
local NOTE_PAD = 12 -- a list note's text inset (left and right)

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 920,
		Height = 600,
		Header = 98, -- the band, then the line under it (the subtitle or the last buy)
		TabBar = 62,
		TabHeight = 48,
		Footer = 30,
		-- three lines of description (16 units) above the detail line
		Row = 132,
		Icon = 94,
		Button = 54,
		BuyWidth = 112,
		PackWidth = 96,
		PriceWidth = 104,
		ChipWidth = 92,
		Title = 24,
		Description = 16,
		Detail = 18,
		TitleMin = 18,
		DescriptionMin = 13,
		DetailMin = 14,
		Close = 54,
		Band = 66,
		TabGap = 0,
		Note = 17,
		NoteMin = 14,
	},
	-- phones: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1080,
		Height = 580,
		Header = 84, -- the band (the last buy sits next to the title)
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
		TitleMin = 20,
		DescriptionMin = 15,
		DetailMin = 16,
		Close = 72,
		Band = 84,
		-- (the X sits in the band: the tab bar spans the panel)
		TabGap = 0,
		Note = 20,
		NoteMin = 16,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

--[[
	Which layout a screen gets (TechShopController.fit): the compact one,
	with its bigger texts and buttons, on touch screens, on TVs (consoles:
	read from a sofa) and on small or low screens; the normal one on PC.
]]
function TechShopView.compactFor(touch: boolean, tenFoot: boolean, scale: number, viewportHeight: number): boolean
	return touch or tenFoot or scale <= 0.75 or viewportHeight < 520
end

---------------------------------------------------------------- measuring text

--[[
	A generous guess of how big a text is in the game's fonts (FredokaOne,
	LuckiestGuy), with no TextService: the same in the game, the tests and
	the preview. Each character counts at least as wide as it really is
	(widths in em, measured from the fonts and rounded up), and lines at
	TechShopView.LineHeight of the text size (Roblox puts them 1.0 apart),
	so a text that fits by this guess fits on screen.
]]
TechShopView.LineHeight = 1.1

local function charWidth(code: number): number
	if code == 32 then
		return 0.3 -- space
	elseif code >= 65 and code <= 90 then
		return 0.7 -- A-Z
	elseif code >= 97 and code <= 122 then
		return 0.56 -- a-z
	elseif code >= 48 and code <= 57 then
		return 0.6 -- 0-9
	elseif code == 46 or code == 44 or code == 58 or code == 59 or code == 39 or code == 33 then
		return 0.32 -- . , : ; ' !
	elseif code < 128 then
		return 0.7 -- other ASCII: $ % ( ) / - + ? "
	end
	return 1 -- the rest (→ •): a whole em
end

-- Width of one line of `text` at `size` (design units).
function TechShopView.textWidth(text: string, size: number): number
	local em = 0
	for _, code in utf8.codes(text) do
		em += charWidth(code)
	end
	return em * size
end

-- Lines `text` wraps to in a box `width` wide at `size` (word wrap, like a TextLabel with TextWrapped).
function TechShopView.textLines(text: string, width: number, size: number): number
	local lines = 0
	local space = charWidth(32) * size
	for _, paragraph in string.split(text, "\n") do
		local count = 1
		local line = 0
		for word in paragraph:gmatch("%S+") do
			local w = TechShopView.textWidth(word, size)
			if line > 0 and line + space + w <= width then
				line += space + w
			else
				if line > 0 then
					count += 1
				end
				-- a word wider than the box is broken over several lines
				local extra = math.max(0, math.ceil(w / math.max(width, 1)) - 1)
				count += extra
				line = w - extra * width
			end
		end
		lines += count
	end
	return lines
end

-- Does `text` fit a `width` x `height` box at `size` (one line when not `wrapped`)?
function TechShopView.fits(text: string, width: number, height: number, size: number, wrapped: boolean): boolean
	if wrapped then
		return TechShopView.textLines(text, width, size) * size * TechShopView.LineHeight <= height
	end
	return TechShopView.textWidth(text, size) <= width and size * TechShopView.LineHeight <= height
end

--[[
	Sets `label.TextSize` to the biggest size from `max` down to `min` at
	which its text fits `width` x `height` (TechShopView.fits; one line when
	the label doesn't wrap). Nothing fits: `min` (the label clips or cuts
	the rest). Returns whether it fits. The cards refresh every second: a
	label whose text and box didn't change keeps its size unmeasured.
]]
local fitted: { [TextLabel]: { Key: string, Size: number, Fits: boolean } } = setmetatable({}, { __mode = "k" }) :: any

function TechShopView.fitText(label: TextLabel, width: number, height: number, max: number, min: number): boolean
	local key = `{width}|{height}|{max}|{min}|{label.TextWrapped}|{label.Text}`
	local last = fitted[label]
	if last and last.Key == key then
		label.TextSize = last.Size
		return last.Fits
	end
	local size, fits = min, false
	for s = max, min, -1 do
		if TechShopView.fits(label.Text, width, height, s, label.TextWrapped) then
			size, fits = s, true
			break
		end
	end
	label.TextSize = size
	fitted[label] = { Key = key, Size = size, Fits = fits }
	return fits
end

---------------------------------------------------------------- pure helpers

local SEP = "  •  "
TechShopView.Separator = SEP

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

local function inventoryOf(state: { [string]: any }): { [string]: any }
	local inventory = state.MachineInventory
	return if type(inventory) == "table" then inventory else {}
end

-- Slot use as BuildService's State field `Build` has it.
export type Slots = { MachinesUsed: number, MachineSlots: number, ConveyorsUsed: number, ConveyorSlots: number }

--[[
	Slot use from a State snapshot: its `Build` field (BuildService), else
	worked out the same way from Placed, Upgrades.ExtraSlots and the
	Workshop pass. Like Placement.counts, belts use belt slots and every
	other machine without SlotFree a machine slot.
]]
function TechShopView.slots(rawState: any): Slots
	local state = safeState(rawState)
	local build = state.Build
	if
		type(build) == "table"
		and type(build.MachinesUsed) == "number"
		and type(build.MachineSlots) == "number"
		and type(build.ConveyorsUsed) == "number"
		and type(build.ConveyorSlots) == "number"
	then
		return {
			MachinesUsed = num(build.MachinesUsed),
			MachineSlots = num(build.MachineSlots),
			ConveyorsUsed = num(build.ConveyorsUsed),
			ConveyorSlots = num(build.ConveyorSlots),
		}
	end
	local machines, conveyors = 0, 0
	local placed = state.Placed
	if type(placed) == "table" then
		for _, entry in placed do
			local info = if type(entry) == "table" and type(entry.Id) == "string" then MachineData.ById[entry.Id] else nil
			if info and info.IsConveyor then
				conveyors += 1
			elseif info and not info.SlotFree then
				machines += 1
			end
		end
	end
	local bought = state.Upgrades
	local extra = if type(bought) == "table" then num(bought.ExtraSlots) else 0
	local shop = workshop(state)
	return {
		MachinesUsed = machines,
		MachineSlots = MachineData.machineSlots(extra, shop),
		ConveyorsUsed = conveyors,
		ConveyorSlots = MachineData.conveyorSlots(shop),
	}
end

-- Machines waiting in the Build menu that will need a slot of `belts` (true: belt slots) kind.
local function waitingFor(state: { [string]: any }, belts: boolean): number
	local n = 0
	for id in inventoryOf(state) do
		local info = if type(id) == "string" then MachineData.ById[id] else nil
		if info and not info.Retired and (if belts then info.IsConveyor == true else not info.IsConveyor and not info.SlotFree) then
			n += EconomyConfig.inventoryCount(state, info.Id)
		end
	end
	return n
end

--[[
	The slot part of a machine card's detail line ("Slots 8/10", "Belt
	slots 38/40") and whether those slots are full: what is placed plus
	what waits in the Build menu fills them, so one more would not fit (the
	card turns red; "Slots full 10/10"; "Slots 8/10 (+2 waiting)" when
	other machine types wait, the card's own "Build menu" count says the
	rest). nil for a machine that needs no slot. A warning only: buying is
	still allowed.
]]
function TechShopView.slotText(rawState: any, machine: MachineData.Machine): (string?, boolean)
	if machine.SlotFree and not machine.IsConveyor then
		return nil, false
	end
	local state = safeState(rawState)
	local slots = TechShopView.slots(state)
	local belts = machine.IsConveyor == true
	local label = if belts then "Belt slots" else "Slots"
	local used = if belts then slots.ConveyorsUsed else slots.MachinesUsed
	local total = if belts then slots.ConveyorSlots else slots.MachineSlots
	local waiting = waitingFor(state, belts)
	if used + waiting < total then
		return `{label} {used}/{total}`, false
	elseif used >= total then
		return `{label} full {used}/{total}`, true
	elseif waiting > EconomyConfig.inventoryCount(state, machine.Id) then
		return `{label} {used}/{total} (+{waiting} waiting)`, true
	end
	return `{label} {used}/{total}`, true
end

-- How many of a machine type you have: in the Build menu plus placed.
function TechShopView.haveCount(rawState: any, machineId: string): number
	local state = safeState(rawState)
	return EconomyConfig.inventoryCount(state, machineId) + TechShopView.placedCount(state, machineId)
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

-- " Needs 10 power." / " Makes 40 power." after a machine's description (MachineData Power / PowerOut).
local function powerNote(machine: MachineData.Machine): string
	if (machine.PowerOut or 0) > 0 then
		return ` Makes {machine.PowerOut} power.`
	elseif (machine.Power or 0) > 0 then
		return ` Needs {machine.Power} power.`
	end
	return ""
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
	-- the slot use, red when one more would not fit (a warning: buying still works)
	local slotText, slotsFull = TechShopView.slotText(state, machine)
	-- (a belt type you don't have yet with other belts waiting says it short: that slot text is long)
	local short = machine.IsConveyor and slotText ~= nil and string.find(slotText, "waiting", 1, true) ~= nil
	local detail = if owned == 0 and placed == 0
		then (if short then "None yet" else "You don't have one yet")
		else `Build menu: {Format.commas(owned)}{SEP}Placed: {Format.commas(placed)}`
	if slotText then
		detail ..= SEP .. slotText
	end
	local full = owned >= EconomyConfig.TechShop.MaxOwned
	-- the price column shows what the server charges (EconomyConfig.techPrice,
	-- as the BUY buttons); only a refused quote (MaxOwned) falls back to the list price
	local first = buys[1]
	local unitPrice = first.Price or machine.Price
	-- two buttons (belts): the price column says what BUY 5 costs in all
	local pack = if #counts > 1 then counts[#counts] else nil
	local packTotal = if pack then buys[#buys].Price or machine.Price * pack else nil
	return {
		Id = entry.Item,
		Item = entry.Item,
		Tab = "Machines",
		Order = order,
		Title = machine.Name,
		Description = machine.Description .. powerNote(machine),
		Detail = if full then EconomyConfig.TechShop.Reasons.MaxOwned else detail,
		DetailColor = if full or slotsFull then Theme.Bad elseif owned > 0 or placed > 0 then Theme.Text else Theme.TextDim,
		Chip = `{machine.Size[1]}x{machine.Size[2]}`,
		ChipColor = TechShopView.CategoryColors[machine.Category] or Theme.PanelDark,
		PriceText = Format.money(unitPrice),
		PriceSub = if pack and packTotal then `{pack} for {Format.money(packTotal)}` else "each",
		PriceColor = if coins >= unitPrice then Theme.Coin else Theme.Bad,
		PriceSubColor = if packTotal and coins < packTotal then Theme.Bad else Theme.TextDim,
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
				return `Pristine {percent(now.Pristine)}{SEP}Flawless {percent(now.Flawless)}  (top level)`
			end
			-- only the grades that change: the better ones, and fewer Rough while
			-- just one better grade moves (level 1: Rough 60% -> 50%, Pristine 0% -> 5%)
			local nextOdds = MachineData.gradeOdds(level + 1)
			local parts: { string } = {}
			for _, grade in { "Pristine", "Flawless" } do
				if (now[grade] or 0) ~= (nextOdds[grade] or 0) then
					table.insert(parts, `{grade} {percent(now[grade])} → {percent(nextOdds[grade])}`)
				end
			end
			if #parts < 2 and (now.Rough or 0) ~= (nextOdds.Rough or 0) then
				table.insert(parts, 1, `Rough {percent(now.Rough)} → {percent(nextOdds.Rough)}`)
			end
			return table.concat(parts, SEP)
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
	local detail = levelDetail(entry, state, level, max)
	-- a machine upgrade for a type you have none of: say so (a warning: buying still works)
	local missing = not done and entry.Kind == "Upgrade" and TechShopView.haveCount(state, entry.Machine :: string) == 0
	if missing then
		detail = `No {MachineData.ById[entry.Machine :: string].Name} yet{SEP}{detail}`
	end
	return {
		Id = entry.Item,
		Item = entry.Item,
		Tab = "Upgrades",
		Order = order,
		Title = levelTitle(entry),
		Description = levelDescription(entry),
		Detail = detail,
		DetailColor = if done then Theme.Good elseif missing then Theme.Bad else Theme.Accent,
		Chip = `LV {level}/{max}`,
		ChipColor = if done then Theme.GoodDark else Theme.PanelDark,
		PriceText = if price then Format.money(price) else "",
		PriceSub = if done then "" else `level {level + 1}`,
		PriceColor = if price and coins < price then Theme.Bad else Theme.Coin,
		PriceSubColor = Theme.TextDim,
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
		PriceSubColor = Theme.TextDim,
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
	Quality), Bellows, Slots, then the two pen automation steps. `where`
	(nil = "Counter"): in a shop opened at your base only machines are
	sold, so every other BUY not yet done is greyed out ("Locked", with
	StatusText.CounterOnly as its note); the server would refuse it as
	"TooFar".
]]
function TechShopView.cards(rawState: any, coins: number, where: Where?): { Card }
	local state = safeState(rawState)
	local cash = num(coins)
	local list: { Card } = {}
	local order = 0
	local machinesOnly = where == "Base" or where == "Build"
	local function add(card: Card)
		if machinesOnly and card.Tab ~= "Machines" and not card.Done then
			for _, offer in card.Buys do
				offer.CanBuy = false
				offer.Reason = "Locked"
			end
			card.Note = TechShopView.StatusText.CounterOnly
		end
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
	-- the machine roster (KitMachines Soft style: cream bodies, slate, orange)
	ExpressConveyor = function(a: Frame)
		bit(a, "Rail", 0.04, 0.62, 0.96, 0.74, C.Gem, 0.4)
		bit(a, "Belt", 0.06, 0.4, 0.94, 0.64, C.Belt, 0.5)
		glyph(a, ">>>", 0.18, 0.42, 0.82, 0.62, C.Gem)
		bit(a, "Leg", 0.14, 0.74, 0.22, 0.9, C.HousingDark)
		bit(a, "Leg", 0.78, 0.74, 0.86, 0.9, C.HousingDark)
	end,
	Splitter = function(a: Frame)
		bit(a, "Base", 0.08, 0.62, 0.92, 0.82, C.HousingDark, 0.3)
		bit(a, "Platform", 0.2, 0.36, 0.8, 0.7, C.Belt, 0.5)
		bit(a, "Flipper", 0.44, 0.3, 0.56, 0.62, C.Hazard, 0.3)
		glyph(a, "<", 0.0, 0.36, 0.22, 0.62, C.Hazard)
		glyph(a, ">", 0.78, 0.36, 1.0, 0.62, C.Hazard)
	end,
	Sorter = function(a: Frame)
		bit(a, "Belt", 0.06, 0.62, 0.94, 0.8, C.Belt, 0.3)
		bit(a, "PostL", 0.1, 0.24, 0.24, 0.66, C.HousingLight, 0.3)
		bit(a, "PostR", 0.76, 0.24, 0.9, 0.66, C.HousingLight, 0.3)
		bit(a, "Gate", 0.08, 0.16, 0.92, 0.32, C.HousingLight, 0.5)
		bit(a, "Dot", 0.3, 0.2, 0.4, 0.28, C.Green, 0.5)
		bit(a, "Dot", 0.45, 0.2, 0.55, 0.28, C.Gem, 0.5)
		bit(a, "Dot", 0.6, 0.2, 0.7, 0.28, C.Gold, 0.5)
	end,
	BrickFurnace = function(a: Frame)
		bit(a, "Dome", 0.16, 0.08, 0.84, 0.6, C.ClayTop, 0.5)
		bit(a, "Body", 0.1, 0.4, 0.9, 0.9, C.HousingLight, 0.2)
		bit(a, "Mouth", 0.34, 0.54, 0.66, 0.86, C.Recess, 0.4)
		bit(a, "Glow", 0.4, 0.62, 0.6, 0.86, C.Glow, 0.4)
		bit(a, "Trim", 0.08, 0.86, 0.92, 0.96, C.Hazard)
	end,
	RestorationTable = function(a: Frame)
		bit(a, "Body", 0.1, 0.56, 0.9, 0.9, C.HousingLight, 0.2)
		bit(a, "Top", 0.06, 0.5, 0.94, 0.6, C.HousingDark, 0.3)
		bit(a, "Bell", 0.3, 0.16, 0.7, 0.5, rgb(170, 220, 255), 0.5)
		bit(a, "Relic", 0.42, 0.3, 0.58, 0.48, rgb(146, 128, 108), 0.3)
		bit(a, "Lamp", 0.74, 0.08, 0.86, 0.2, C.Glow, 0.5)
		bit(a, "Trim", 0.08, 0.86, 0.92, 0.96, C.Hazard)
	end,
	Polisher = function(a: Frame)
		bit(a, "Body", 0.1, 0.5, 0.9, 0.9, C.HousingLight, 0.2)
		bit(a, "Table", 0.2, 0.42, 0.8, 0.52, C.Hazard, 0.5)
		bit(a, "Arm", 0.72, 0.06, 0.8, 0.4, C.HousingDark)
		bit(a, "Wheel", 0.3, 0.18, 0.7, 0.32, rgb(255, 172, 204), 0.5)
		bit(a, "Trim", 0.08, 0.86, 0.92, 0.96, C.Hazard)
	end,
	RobotArm = function(a: Frame)
		bit(a, "Base", 0.2, 0.78, 0.6, 0.94, C.HousingDark, 0.3)
		bit(a, "Turret", 0.28, 0.62, 0.52, 0.8, C.Hazard, 0.3)
		bit(a, "Upper", 0.36, 0.22, 0.46, 0.66, C.Hazard, 0.4)
		bit(a, "Fore", 0.4, 0.18, 0.84, 0.28, C.Hazard, 0.4)
		bit(a, "Claw", 0.76, 0.26, 0.9, 0.44, C.HousingDark, 0.2)
	end,
	SellBox = function(a: Frame)
		bit(a, "Body", 0.1, 0.3, 0.9, 0.9, C.HousingLight, 0.25)
		bit(a, "Coin", 0.3, 0.4, 0.7, 0.8, C.Gold, 0.5)
		glyph(a, "$", 0.36, 0.44, 0.64, 0.76, C.WoodDark)
		bit(a, "Lid", 0.18, 0.2, 0.82, 0.32, C.HousingDark, 0.3)
	end,
	CrystalExtractor = function(a: Frame)
		bit(a, "Body", 0.1, 0.52, 0.9, 0.92, C.HousingLight, 0.2)
		bit(a, "Glass", 0.26, 0.08, 0.74, 0.54, C.Water, 0.3)
		bit(a, "Gem", 0.4, 0.2, 0.6, 0.44, C.Gem, 0.2).Rotation = 45
		bit(a, "Trim", 0.08, 0.86, 0.92, 0.96, C.Hazard)
	end,
	AlloyFurnace = function(a: Frame)
		bit(a, "HopperL", 0.1, 0.16, 0.36, 0.34, C.Hazard, 0.4)
		bit(a, "HopperR", 0.64, 0.16, 0.9, 0.34, C.Gem, 0.4)
		bit(a, "Body", 0.04, 0.34, 0.96, 0.9, C.HousingLight, 0.2)
		bit(a, "Glow", 0.36, 0.56, 0.64, 0.88, C.Glow, 0.4)
		bit(a, "Trim", 0.04, 0.86, 0.96, 0.96, C.Hazard)
	end,
	PlasmaFurnace = function(a: Frame)
		bit(a, "Sphere", 0.32, 0.04, 0.68, 0.38, rgb(186, 110, 255), 0.5)
		bit(a, "Body", 0.1, 0.36, 0.9, 0.9, C.HousingLight, 0.2)
		bit(a, "Glow", 0.36, 0.56, 0.64, 0.88, rgb(186, 110, 255), 0.4)
		bit(a, "Trim", 0.08, 0.86, 0.92, 0.96, rgb(186, 110, 255))
	end,
	-- platforms (docs/plans/PLATFORMS_PLAN.md): a deck on legs, a belt up, a belt down
	Platform = function(a: Frame)
		bit(a, "Deck", 0.06, 0.24, 0.94, 0.38, C.HousingLight, 0.3)
		bit(a, "Glow", 0.1, 0.38, 0.9, 0.43, C.Hazard)
		bit(a, "LegL", 0.14, 0.42, 0.24, 0.88, C.HousingDark)
		bit(a, "LegR", 0.76, 0.42, 0.86, 0.88, C.HousingDark)
		bit(a, "FootL", 0.1, 0.86, 0.28, 0.94, C.Hazard, 0.4)
		bit(a, "FootR", 0.72, 0.86, 0.9, 0.94, C.Hazard, 0.4)
		bit(a, "Belt", 0.3, 0.72, 0.7, 0.86, C.Belt, 0.4)
	end,
	BeltLift = function(a: Frame)
		bit(a, "Deck", 0.62, 0.22, 0.98, 0.32, C.HousingLight, 0.3)
		local belt = bit(a, "Belt", 0.04, 0.48, 0.96, 0.62, C.Belt, 0.5)
		belt.Rotation = -32
		bit(a, "Leg", 0.62, 0.32, 0.7, 0.9, C.HousingDark)
		glyph(a, "^", 0.06, 0.62, 0.36, 0.94, C.Green)
	end,
	Slide = function(a: Frame)
		bit(a, "Deck", 0.02, 0.22, 0.38, 0.32, C.HousingLight, 0.3)
		local belt = bit(a, "Belt", 0.04, 0.48, 0.96, 0.62, C.Belt, 0.5)
		belt.Rotation = 32
		bit(a, "Leg", 0.3, 0.32, 0.38, 0.9, C.HousingDark)
		glyph(a, "v", 0.64, 0.62, 0.94, 0.94, rgb(255, 110, 90))
	end,
	PowerPole = function(a: Frame)
		bit(a, "Pole", 0.45, 0.2, 0.55, 0.9, C.HousingDark)
		bit(a, "Arm", 0.2, 0.24, 0.8, 0.3, C.HousingDark)
		bit(a, "Ins", 0.18, 0.14, 0.26, 0.24, C.Hazard, 0.5)
		bit(a, "Ins", 0.74, 0.14, 0.82, 0.24, C.Hazard, 0.5)
		bit(a, "Lamp", 0.42, 0.04, 0.58, 0.18, C.Green, 0.5)
	end,
	SolarPanel = function(a: Frame)
		local panel = bit(a, "Panel", 0.08, 0.2, 0.92, 0.56, rgb(44, 78, 160), 0.1)
		panel.Rotation = -8
		bit(a, "Post", 0.45, 0.54, 0.55, 0.86, C.HousingDark)
		bit(a, "Base", 0.24, 0.84, 0.76, 0.94, C.HousingDark, 0.3)
		glyph(a, "+", 0.4, 0.26, 0.6, 0.5, rgb(140, 190, 255))
	end,
	WindTurbine = function(a: Frame)
		bit(a, "Tower", 0.45, 0.34, 0.55, 0.94, C.HousingLight)
		bit(a, "BladeA", 0.47, 0.02, 0.53, 0.34, C.HousingLight, 0.5)
		local b = bit(a, "BladeB", 0.47, 0.18, 0.53, 0.5, C.HousingLight, 0.5)
		b.Rotation = 120
		local c = bit(a, "BladeC", 0.47, 0.18, 0.53, 0.5, C.HousingLight, 0.5)
		c.Rotation = -120
		bit(a, "Hub", 0.42, 0.28, 0.58, 0.4, C.Hazard, 0.5)
	end,
	FusionReactor = function(a: Frame)
		bit(a, "Base", 0.08, 0.7, 0.92, 0.92, C.HousingLight, 0.3)
		bit(a, "Ring", 0.2, 0.22, 0.8, 0.72, C.HousingDark, 0.5)
		bit(a, "Core", 0.34, 0.34, 0.66, 0.62, rgb(70, 228, 255), 0.5)
		bit(a, "PylonL", 0.06, 0.2, 0.14, 0.7, C.HousingLight)
		bit(a, "PylonR", 0.86, 0.2, 0.94, 0.7, C.HousingLight)
	end,
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
	The kind's live 3D picture (the Pop look): a machine id is the build
	tray's own picture (BuildView.picture: the placed model; an uploaded
	machine icon when there is one), "Train" the shop's locomotive
	(PictureModels); nil for the kinds drawn from frames (DRAW: Bellows,
	Slots, Billboard).
]]
local function pictureName(kind: string): string?
	if MachineData.ById[kind] then
		return if BuildView.hasIcon(kind) then BuildView.iconFor(kind) else "machine_" .. kind
	elseif kind == "Train" then
		return "train"
	end
	return nil
end

--[[
	A square icon (`size` design units): a light burst and a soft glow with
	the picture of `kind` on them: a machine's (or the train's) live 3D
	picture (pictureName; the model is built once the card first shows:
	TechShopView.fillPicture), else a little picture drawn from frames
	("Bellows", "Slots", "Billboard"; an unknown kind gets a plain tile).
	`badge` "Speed" | "Quality" adds a small badge in the bottom right corner.
]]
function TechShopView.icon(parent: Instance, size: number, kind: string, badge: string?): Frame
	local tile = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
	Pop.rays(tile, UDim2.fromScale(0.5, 0.5), 10, math.floor(size * 0.95), 0.45, 1)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.68,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		ZIndex = 2,
	}, tile)
	UIKit.corner(glow, 999)
	Pop.sparkle(tile, UDim2.fromScale(0.88, 0.12), 18, 5, 0.15)
	Pop.sparkle(tile, UDim2.fromScale(0.1, 0.84), 13, 5, 0.35)
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
	for _, name in { "Art", "Picture" } do
		local old = tile:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local art = UIKit.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, tile)
	local picture = pictureName(kind)
	if picture then
		-- the live 3D picture (an empty view until fillPicture builds its model)
		Pop.model(tile, picture, 10, nil, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.08, 1.08),
			ZIndex = 3,
		})
		if BuildView.hasIcon(kind) then
			local image = tile:FindFirstChild("Picture") :: ImageLabel
			image.ScaleType = Enum.ScaleType.Fit
			IconAssets.apply(image, picture)
		end
	else
		local draw = DRAW[kind]
		if draw then
			draw(art)
		else
			bit(art, "Plain", 0.2, 0.2, 0.8, 0.8, C.Housing, 0.2)
		end
	end
	if badge == "Speed" then
		local b = bit(art, "Badge", 0.7, 0.72, 1.1, 1.12, PopTheme.Paints.Orange.Bottom, 0.5)
		b.ZIndex = 6
		glyph(b, ">>", 0.12, 0.18, 0.88, 0.82, Theme.Text)
	elseif badge == "Quality" then
		local b = bit(art, "Badge", 0.74, 0.76, 1.08, 1.1, C.Gem, 0.2)
		b.Rotation = 45
		b.ZIndex = 6
	end
end

--[[
	Builds an icon tile's live 3D model (once: a tile that has one keeps it,
	until setIcon gives it another kind). The shop calls it for the cards of
	the shown tab while the window is open (TechShopView.setCards), so a
	closed shop builds no models.
]]
function TechShopView.fillPicture(tile: Frame)
	local image = tile:FindFirstChild("Picture")
	local view = if image then image:FindFirstChild("View") else nil
	if not view or not view:IsA("ViewportFrame") or view:FindFirstChildOfClass("Model") then
		return
	end
	local kind = tile:GetAttribute("Kind")
	if type(kind) ~= "string" or BuildView.hasIcon(kind) then
		return
	end
	if MachineData.ById[kind] then
		local ok, model, cf = pcall(BuildView.picture, kind)
		if ok then
			local camera = Instance.new("Camera")
			camera.FieldOfView = 30
			camera.CFrame = cf
			camera.Parent = view
			pcall(function()
				view.CurrentCamera = camera
			end)
			model.Parent = view
		end
	elseif kind == "Train" then
		local model, from = PictureModels.build("train")
		if model then
			Pop.show(view, model, from)
		end
	end
end

---------------------------------------------------------------- the Pop look (the kit pieces this window needs)

TechShopView.Paint = "Yellow" -- the header band: the shop's colour (LightSkin.BandRoles TerraForgeTechShop = "Build")
-- each tab's paint (the picked tab is painted, the others slate: Pop.selectTab)
TechShopView.TabPaints = { Machines = "Orange", Upgrades = "Blue", Automation = "Purple" } :: { [string]: string }
-- the cards' paints: a machine (and its upgrades) by category, the rest by item
TechShopView.CategoryPaints =
	{ Processing = "Orange", Logistics = "Blue", Selling = "Green", Power = "Teal", Droppers = "Purple" } :: { [string]: string }
TechShopView.ItemPaints = { Bellows = "Pink", Slots = "Purple", Billboard = "Purple", Train = "Pink" } :: { [string]: string }

local WHITE = Color3.new(1, 1, 1)
local SOFT = Color3.fromRGB(214, 220, 232) -- quieter white text (hints)
local ROW_CORNER = 12
local DETAIL_PAD = 8 -- the detail strip's text inset (left and right)
local HOLDER_KEYS = { Size = true, Position = true, AnchorPoint = true, LayoutOrder = true, Visible = true }
local HOVER = Color3.fromRGB(236, 236, 236)
local PRESS = Color3.fromRGB(200, 200, 200)

-- The paint of a row: its machine's category, else its item's (Bellows, Slots, the automation steps).
function TechShopView.rowPaint(kind: string): string
	local machine = MachineData.ById[kind]
	if machine then
		return TechShopView.CategoryPaints[machine.Category] or "Orange"
	end
	return TechShopView.ItemPaints[kind] or "Purple"
end

-- A text's black edge (its Contextual UIStroke, made when missing).
local function edgeOf(label: GuiObject): UIStroke
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			return child
		end
	end
	return Pop.edge(label)
end

-- White chunky text with a black edge (a UIKit label or button), or `color`.
local function ink(label: GuiObject, color: Color3?, font: Font?)
	local text: any = label
	text.FontFace = font or PopTheme.Font
	text.TextColor3 = color or PopTheme.Ink
	local edge = edgeOf(label)
	edge.Color = PopTheme.Outline
	edge.Thickness = Pop.edgeFor(text.TextSize)
	edge.Transparency = 0
	edge.LineJoinMode = Enum.LineJoinMode.Round
end

-- A text in a Pop title gradient (PopTheme.Titles; it colours the glyphs).
local function titleGradient(label: GuiObject, colors: string)
	local keys = PopTheme.Titles[colors] or PopTheme.Titles.White
	local gradient = label:FindFirstChild("Titles") :: UIGradient?
	if not gradient then
		gradient = UIKit.new("UIGradient", { Name = "Titles", Rotation = 90 }, label)
	end
	local g = gradient :: UIGradient
	g.Color = ColorSequence.new(keys[1], keys[#keys])
end

--[[
	A Pop button that keeps UIKit.button's shape: the returned TextButton
	(clear, its own word: controllers and views set its Text, TextSize and
	TextTransparency) fills its holder, and the holder is the painted face
	(Pop.face: the glossy paint, the black border, the light rim, studs).
	(A UIGradient on the button itself would tint its word too.) Size /
	Position / AnchorPoint / LayoutOrder / Visible go on the holder (layouts
	move it), the rest on the button. paintButton recolours the face.
]]
local function popButton(parent: Instance, text: string, paint: string | Pop.Paint, props: { [string]: any }?): TextButton
	local name = if props and type(props.Name) == "string" then props.Name else text
	local face = UIKit.new("Frame", {
		Name = name .. "Holder",
		Size = UDim2.fromOffset(160, 52),
		ZIndex = 4,
	}, parent)
	Pop.face(face, paint)
	Pop.studs(face, PopTheme.Corner, 0.45, 28, 4)
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		FontFace = PopTheme.Font,
		TextColor3 = PopTheme.Ink,
		TextSize = 22,
		Selectable = true,
		ZIndex = 6,
	}, face)
	Pop.edge(button, 2.5)
	if props then
		for key, value in props do
			local target: any = if HOLDER_KEYS[key] then face else button
			if key ~= "Name" then
				target[key] = value
			end
		end
	end
	-- hover / press darken the face (AutoButtonColor would only darken the clear button)
	pcall(function()
		local b: any = button
		b:GetPropertyChangedSignal("GuiState"):Connect(function()
			local state = b.GuiState
			face.BackgroundColor3 = if state == Enum.GuiState.Press then PRESS elseif state == Enum.GuiState.Hover then HOVER else WHITE
		end)
	end)
	return button
end

-- Recolours a popButton's face.
local function paintButton(button: TextButton, paint: string | Pop.Paint)
	local face = button.Parent
	if face and face:IsA("GuiObject") then
		Pop.repaint(face, paint)
	end
end

--[[
	The gold coin BUY button (Pop.coinButton's look on a popButton): the
	yellow face with a drawn coin left of the word ("BUY", "BUY 5"); the
	word's room starts right of the coin (CoinPad). setCoin shows / hides
	the coin (a done card's MAX / OWNED, a BOUGHT! flash: no coin).
]]
local function coinButton(parent: Instance, props: { [string]: any }): TextButton
	local button = popButton(parent, "BUY", "Yellow", props)
	local face = button.Parent :: Frame
	Pop.coin(face, 24, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		ZIndex = 5,
	})
	UIKit.new("UIPadding", { Name = "CoinPad", PaddingLeft = UDim.new(0, 30), PaddingRight = UDim.new(0, 4) }, button)
	return button
end

-- Shows or hides a coin button's coin (`size` units across).
local function setCoin(button: TextButton, show: boolean, size: number?)
	local face = button.Parent
	local coin = if face then face:FindFirstChild("Coin") else nil
	if coin and coin:IsA("GuiObject") then
		coin.Visible = show
		if size then
			coin.Size = UDim2.fromOffset(size, size)
			local mark = coin:FindFirstChild("Mark")
			if mark and mark:IsA("TextLabel") then
				mark.TextSize = math.floor(size * 0.62)
			end
		end
	end
	local pad = button:FindFirstChild("CoinPad") :: UIPadding?
	if pad then
		local room = if coin and coin:IsA("GuiObject") then coin.Size.X.Offset + 10 else 30
		pad.PaddingLeft = UDim.new(0, if show then room else 4)
	end
end

--[[
	The window's chrome on an old panel: the black frame, a dark studded
	body and the bright header band (shine stripes, studs); both sit under
	everything else (ZIndex 0). setBand sizes them for a band `band` tall.
]]
local function chrome(panel: Frame, paint: string | Pop.Paint)
	panel.BackgroundColor3 = PopTheme.Outline
	local old = panel:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	local corner = panel:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, PopTheme.WindowCorner)
	end
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = PopTheme.Outline
		stroke.Thickness = 4
	end
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, panel)
	UIKit.corner(body, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, body)
	Pop.studs(body, 4, 0.5, 36, 0)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 0,
	}, body)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, shade)
	local head = UIKit.new("Frame", {
		Name = "Header",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		ClipsDescendants = true,
		ZIndex = 0,
	}, panel)
	Pop.face(head, paint, 4, false)
	local headBorder = head:FindFirstChild("Border") :: UIStroke
	headBorder.Thickness = 3
	Pop.studs(head, 4, 0.35, 40, 0)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 0,
	}, head)
	for i, s in { { 0.62, 46 }, { 0.7, 22 }, { 0.8, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.4, 0),
			ZIndex = 0,
		}, head)
	end
end

-- Sizes the header band (`band` units tall, the frame included) and the body under it.
local function setBand(panel: Frame, band: number)
	local head = panel:FindFirstChild("Header") :: Frame?
	local body = panel:FindFirstChild("Body") :: Frame?
	if head and body then
		head.Size = UDim2.new(1, -8, 0, band - 8)
		body.Position = UDim2.fromOffset(4, band)
		body.Size = UDim2.new(1, -8, 1, -(band + 4))
	end
end

-- The title's 3D drop shadow (Pop.shadow), kept on the title as layouts move it.
local function syncShadow(title: TextLabel)
	local parent = title.Parent
	local found = if parent then parent:FindFirstChild(title.Name .. "Shadow") else nil
	local shade: TextLabel = if found and found:IsA("TextLabel") then found else Pop.shadow(title)
	shade.Position = title.Position + UDim2.fromOffset(0, 4)
	shade.Size = title.Size
	shade.AnchorPoint = title.AnchorPoint
	shade.Text = title.Text
	shade.TextSize = title.TextSize
	shade.TextXAlignment = title.TextXAlignment
	shade.Visible = title.Visible
	shade.ZIndex = math.max(1, title.ZIndex - 1)
end

---------------------------------------------------------------- building

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

--[[
	Colours a button: enabled in its own colours, or greyed out. (The Pop
	look: the colour picks the face's paint: Theme.Accent a gold coin BUY,
	Theme.Good green, Theme.Bad red, Theme.Info blue; greyed out: grey.)
]]
local function style(button: TextButton, enabled: boolean, color: Color3, _dark: Color3)
	local buy = color == Theme.Accent
	local paint: string | Pop.Paint = if not enabled
		then PopTheme.Gray
		elseif color == Theme.Good then "Green"
		elseif color == Theme.Bad then "Red"
		elseif color == Theme.Info then "Blue"
		else "Yellow"
	paintButton(button, paint)
	setCoin(button, buy)
	button.TextColor3 = PopTheme.Ink
	button.TextTransparency = if enabled then 0 else 0.25
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
	-- a painted Pop card (its machine's category colour) that clips its light burst
	local frame = UIKit.new("Frame", {
		Name = spec.Id,
		LayoutOrder = spec.Order,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, refs.Lists[spec.Tab])
	Pop.face(frame, TechShopView.rowPaint(spec.Icon), ROW_CORNER, false)
	Pop.studs(frame, ROW_CORNER, 0.5, 44, 1)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	local icon = TechShopView.icon(frame, m.Icon, spec.Icon, spec.Badge)
	local title = UIKit.label(frame, "", m.Title, {
		Name = "ItemName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	ink(title)
	-- the chip: one bright colour (a gradient would tint its word), a black border
	local chip = UIKit.chip(frame, "", Theme.PanelDark, { Name = "Chip", ZIndex = 4 })
	for _, child in chip:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child:Destroy()
		end
	end
	Pop.border(chip, 2)
	ink(chip)
	local description = UIKit.label(frame, "", m.Description, {
		Name = "Description",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		-- a longer text never runs into the detail line
		ClipsDescendants = true,
		ZIndex = 4,
	})
	ink(description)
	-- the detail and status lines: a dark strip, so every colour reads on every paint
	local function strip(name: string, visible: boolean): TextLabel
		local line = UIKit.label(frame, "", m.Detail, {
			Name = name,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundColor3 = PopTheme.Well,
			BackgroundTransparency = 0.25,
			Visible = visible,
			ZIndex = 4,
		})
		UIKit.corner(line, 8)
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, DETAIL_PAD), PaddingRight = UDim.new(0, DETAIL_PAD) }, line)
		ink(line)
		return line
	end
	local detail = strip("Detail", true)
	local status = strip("Status", false)
	local price = UIKit.label(frame, "", 22, {
		Name = "Price",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		ZIndex = 4,
	})
	ink(price, WHITE, PopTheme.Heavy)
	titleGradient(price, "Gold")
	local priceSub = UIKit.label(frame, "", 14, {
		Name = "PriceSub",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		ZIndex = 4,
	})
	ink(priceSub)
	local buttons: { TextButton } = {}
	for i = 1, math.max(1, spec.Buttons) do
		table.insert(buttons, coinButton(frame, { Name = "Buy" .. i }))
	end
	local row: Row = {
		Id = spec.Id,
		Tab = spec.Tab,
		Item = spec.Item,
		-- set by placeRow
		Boxes = {
			TitleWidth = 0,
			DescriptionWidth = 0,
			DescriptionHeight = 0,
			DetailWidth = 0,
			DetailHeight = 0,
			PriceWidth = 0,
			Title = m.Title,
			Description = m.Description,
			Detail = m.Detail,
			PriceSub = 14,
			TitleMin = m.TitleMin,
			DescriptionMin = m.DescriptionMin,
			DetailMin = m.DetailMin,
		},
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

-- The note at the top of a list (TechShopView.setWhere fills it): a dark well with white words.
local function listNote(list: ScrollingFrame): TextLabel
	local note = UIKit.label(list, "", 17, {
		Name = "Note",
		LayoutOrder = -1,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = PopTheme.Well,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 3,
	})
	UIKit.corner(note, 10)
	Pop.border(note, 2.5)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, NOTE_PAD), PaddingRight = UDim.new(0, NOTE_PAD) }, note)
	ink(note)
	return note
end

local function groupHeader(list: ScrollingFrame, text: string, order: number): TextLabel
	local header = UIKit.label(list, text, 22, {
		Name = "Group",
		LayoutOrder = order,
		Size = UDim2.new(1, -SCROLLBAR, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = 3,
	})
	ink(header, WHITE, PopTheme.Heavy)
	titleGradient(header, "Gold")
	return header
end

function TechShopView.build(compact: boolean?): Refs
	local gui = UIKit.screen("TerraForgeTechShop", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("Pop", true)

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
	chrome(panel, TechShopView.Paint)
	local title = UIKit.label(panel, "TECH SHOP", 34, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 3,
	})
	ink(title)
	local subtitle = UIKit.label(panel, "Machines and upgrades for your base. Machines you buy wait in your Build menu.", 16, {
		Name = "Subtitle",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	ink(subtitle, SOFT)
	local receipt = UIKit.label(panel, "", 17, {
		Name = "Receipt",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		ZIndex = 3,
		-- a dark pill behind it: any message colour reads on the band or the body
		BackgroundColor3 = PopTheme.Well,
		BackgroundTransparency = 0.2,
	})
	UIKit.corner(receipt, 8)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, receipt)
	ink(receipt, Theme.Good)
	local close = popButton(panel, "X", PopTheme.Close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 32,
		FontFace = PopTheme.Heavy,
	})
	-- your coins, next to the close button (the HUD's may be covered on phones): a dark well
	local balance = UIKit.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, panel)
	UIKit.corner(balance, 10)
	Pop.border(balance, 3)
	Pop.coin(balance, 28, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		ZIndex = 4,
	})
	local balanceAmount = UIKit.label(balance, "$0", 24, {
		Name = "Amount",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -50, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	ink(balanceAmount, PopTheme.Money, PopTheme.Heavy)

	-- tabs: bright Pop tabs (the picked one painted, the others slate)
	local tabBar = UIKit.new("Frame", {
		Name = "TabBar",
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, panel)
	local tabs: { [string]: TextButton } = {}
	for _, tab in TABS do
		tabs[tab] = popButton(tabBar, TechShopView.TabTitles[tab], TechShopView.TabPaints[tab], {
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
				ZIndex = 7,
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
			ScrollBarImageColor3 = Color3.fromRGB(196, 200, 212),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Selectable = false,
			Visible = tab == "Machines",
			ZIndex = 2,
		}, panel)
		UIKit.list(list, Enum.FillDirection.Vertical, GAP)
		UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10) }, list)
		lists[tab] = list
	end
	local notes: { [string]: TextLabel } = {}
	for _, tab in TABS do
		notes[tab] = listNote(lists[tab])
	end
	local groups = {
		groupHeader(lists.Upgrades, "MACHINE UPGRADES", 0),
		groupHeader(lists.Upgrades, "FOR ALL MACHINES", TechShopView.AllMachinesOrder),
	}

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextWrapped = false,
		ZIndex = 3,
	})
	ink(hint, SOFT)
	-- gamepads: the platform's own button glyphs (Xbox or PlayStation), set by the controller
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(460, 24),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, panel)
	UIKit.list(padHint, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local padGlyphs: { ImageLabel } = {}
	local order = 0
	local function padGlyph(name: string)
		order += 1
		table.insert(
			padGlyphs,
			UIKit.new("ImageLabel", {
				Name = "Glyph" .. name,
				LayoutOrder = order,
				Size = UDim2.fromOffset(24, 24),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, padHint)
		)
	end
	local function padWord(text: string, width: number)
		order += 1
		local word = UIKit.label(padHint, text, 15, {
			Name = "Word",
			LayoutOrder = order,
			Size = UDim2.fromOffset(width, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			ZIndex = 3,
		})
		ink(word, SOFT)
	end
	padGlyph("L")
	padGlyph("R")
	padWord("switch tab", 92)
	padGlyph("A")
	padWord("buy", 44)
	padGlyph("B")
	padWord("close", 52)

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Subtitle = subtitle,
		Receipt = receipt,
		ReceiptBox = Vector2.zero,
		Balance = balance,
		BalanceAmount = balanceAmount,
		Close = close,
		TabBar = tabBar,
		Tabs = tabs,
		TabGlyphs = glyphs,
		Lists = lists,
		Notes = notes,
		NoteBox = Vector2.zero,
		Where = "Counter",
		Device = "Keyboard",
		Groups = groups,
		Rows = {},
		RowList = {},
		Hint = hint,
		PadHint = padHint,
		PadGlyphs = padGlyphs,
		PadMode = false,
		Tab = "Machines",
		Compact = compact == true,
	}
	local m = metrics(refs.Compact)
	for _, spec in TechShopView.rowSpecs() do
		newRow(refs, spec, m)
	end
	TechShopView.setTab(refs, "Machines")
	TechShopView.setWhere(refs, "Counter")
	TechShopView.layout(refs, refs.Compact, math.huge, math.huge)
	-- (the light UI: an open window hides the touch thumbstick)
	if UIConfig.lightUI() then
		TouchControls.follow(gui)
	end
	return refs
end

---------------------------------------------------------------- layout

-- The width the buttons of a row take (with their gaps).
local function buttonsWidth(row: Row, m: Metrics): number
	local n = #row.Buttons
	local each = if n > 1 then m.PackWidth else m.BuyWidth
	return n * each + (n - 1) * GAP
end

-- Fits a row's texts into their boxes (TechShopView.fitText): a long text
-- gets a little smaller instead of running out of its box.
local function fitRow(row: Row)
	local b = row.Boxes
	if b.DescriptionWidth <= 0 then
		return -- not placed yet
	end
	TechShopView.fitText(row.Title, b.TitleWidth, 32, b.Title, b.TitleMin)
	TechShopView.fitText(row.Description, b.DescriptionWidth, b.DescriptionHeight, b.Description, b.DescriptionMin)
	TechShopView.fitText(row.Detail, b.DetailWidth, b.DetailHeight, b.Detail, b.DetailMin)
	TechShopView.fitText(row.Status, b.DetailWidth, b.DetailHeight, b.Detail, b.DetailMin)
	TechShopView.fitText(row.PriceSub, b.PriceWidth, 18, b.PriceSub, 11)
end
TechShopView.fitRow = fitRow

-- Fits the header message into its room (a long buy toast gets a little
-- smaller; on phones it wraps to two lines next to the title).
local function fitReceipt(refs: Refs)
	local box = refs.ReceiptBox
	if box.X > 0 and refs.Receipt.Text ~= "" then
		TechShopView.fitText(refs.Receipt, box.X, box.Y, if refs.Compact then 18 else 17, 13)
	end
end

-- Fits the list notes' texts into the room layout gave them.
local function fitNotes(refs: Refs)
	local box = refs.NoteBox
	if box.X <= 0 then
		return -- not laid out yet
	end
	local m = metrics(refs.Compact)
	for _, note in refs.Notes do
		TechShopView.fitText(note, box.X, box.Y, m.Note, m.NoteMin)
	end
end

--[[
	One row (`rowWidth` design units wide): picture | title + chip,
	description (three lines), the detail strip | price | buttons. Normal:
	the price sits left of the buttons, both centred. Compact (phones): the
	buttons sit at the bottom right with the price above them, so the text
	gets the price column's room.
]]
local function placeRow(row: Row, m: Metrics, compact: boolean, rowWidth: number)
	local h = m.Row
	row.Frame.Size = UDim2.new(1, -SCROLLBAR, 0, h)
	row.Icon.Size = UDim2.fromOffset(m.Icon, m.Icon)
	row.Icon.Position = UDim2.fromOffset(10, (h - m.Icon) / 2)
	local n = #row.Buttons
	local each = if n > 1 then m.PackWidth else m.BuyWidth
	local buttons = buttonsWidth(row, m)
	local buttonTop = if compact then h - m.Button - 10 else (h - m.Button) / 2
	local coin = math.floor(m.Button * 0.44)
	for i, button in row.Buttons do
		local holder = holderOf(button)
		holder.AnchorPoint = Vector2.new(1, 0)
		holder.Position = UDim2.new(1, -(10 + (n - i) * (each + GAP)), 0, buttonTop)
		holder.Size = UDim2.fromOffset(each, m.Button)
		button.TextSize = if compact then 22 else 20
		local face = holderOf(button)
		local mark = face:FindFirstChild("Coin")
		setCoin(button, mark ~= nil and mark:IsA("GuiObject") and mark.Visible, coin)
	end
	local textRight: number
	local priceWidth: number
	row.Price.AnchorPoint = Vector2.new(1, 0)
	row.PriceSub.AnchorPoint = Vector2.new(1, 0)
	if compact then
		priceWidth = buttons
		row.Price.Position = UDim2.new(1, -12, 0, 6)
		row.Price.Size = UDim2.fromOffset(buttons, 30)
		row.PriceSub.Position = UDim2.new(1, -12, 0, 36)
		row.PriceSub.Size = UDim2.fromOffset(buttons, 18)
		textRight = 10 + buttons + 14
	else
		priceWidth = m.PriceWidth
		local right = 10 + buttons + 10
		row.Price.Position = UDim2.new(1, -right, 0, h / 2 - 24)
		row.Price.Size = UDim2.fromOffset(m.PriceWidth, 28)
		row.PriceSub.Position = UDim2.new(1, -right, 0, h / 2 + 4)
		row.PriceSub.Size = UDim2.fromOffset(m.PriceWidth, 18)
		textRight = right + m.PriceWidth + 10
	end
	row.Price.TextSize = if compact then 26 else 24
	local left = m.Icon + 22
	local chipWidth = m.ChipWidth
	row.Chip.AnchorPoint = Vector2.new(1, 0)
	row.Chip.Position = UDim2.new(1, -textRight, 0, 12)
	row.Chip.Size = UDim2.fromOffset(chipWidth, if compact then 28 else 24)
	row.Chip.TextSize = if compact then 16 else 14
	local titleInset = left + textRight + chipWidth + 8
	row.Title.Position = UDim2.fromOffset(left, 8)
	row.Title.Size = UDim2.new(1, -titleInset, 0, 32)
	local detailHeight = m.Detail + 6
	local descriptionHeight = h - 42 - detailHeight - 10
	row.Description.Position = UDim2.fromOffset(left, 42)
	row.Description.Size = UDim2.new(1, -(left + textRight), 0, descriptionHeight)
	-- up to the buttons
	local detailInset = left + (if compact then textRight else 10 + buttons + 14)
	for _, line in { row.Detail, row.Status } do
		line.Position = UDim2.fromOffset(left - 6, h - detailHeight - 8)
		line.Size = UDim2.new(1, -(detailInset - 6), 0, detailHeight)
	end
	row.Boxes = {
		TitleWidth = rowWidth - titleInset,
		DescriptionWidth = rowWidth - (left + textRight),
		DescriptionHeight = descriptionHeight,
		-- (the strip's text inset off its width)
		DetailWidth = rowWidth - (detailInset - 6) - DETAIL_PAD * 2,
		DetailHeight = detailHeight,
		PriceWidth = priceWidth,
		Title = m.Title,
		Description = m.Description,
		Detail = m.Detail,
		PriceSub = if compact then 15 else 14,
		TitleMin = m.TitleMin,
		DescriptionMin = m.DescriptionMin,
		DetailMin = m.DetailMin,
	}
	fitRow(row)
end

--[[
	Sizes everything for the normal or compact (phone) layout and fits the
	panel into `maxWidth` x `maxHeight` design units (the screen divided by
	the UI scale; math.huge = no limit). The header band holds the title,
	your coins and the X; the line under it (the subtitle or the last buy)
	sits on the body (phones: the last buy next to the title, in the band).
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
	setBand(refs.Panel, m.Band)

	-- the X and your coins, centred in the band
	local close = holderOf(refs.Close)
	close.Size = UDim2.fromOffset(m.Close, m.Close)
	close.Position = UDim2.new(1, -12, 0, math.floor((m.Band - m.Close) / 2))
	refs.Close.TextSize = math.floor(m.Close * 0.62)
	local balanceWidth = if compact then 196 else 182
	local balanceHeight = if compact then 48 else 42
	refs.Balance.Size = UDim2.fromOffset(balanceWidth, balanceHeight)
	refs.Balance.Position = UDim2.new(1, -(12 + m.Close + 12), 0, math.floor((m.Band - balanceHeight) / 2))
	refs.BalanceAmount.TextSize = if compact then 28 else 26
	local headRight = 12 + m.Close + 12 + balanceWidth + 12
	refs.Title.TextSize = if compact then 32 else 36
	refs.Title.Position = UDim2.fromOffset(PAD, 0)
	refs.Title.Size = UDim2.new(1, -(PAD + headRight), 0, m.Band)
	refs.Subtitle.Position = UDim2.fromOffset(PAD, m.Band + 4)
	refs.Subtitle.Size = UDim2.new(1, -PAD * 2, 0, 24)
	refs.Subtitle.Visible = not compact and not refs.Receipt.Visible
	if compact then
		-- next to the title, in the band (no room for a second header line)
		local titleWidth = 250
		refs.Title.Size = UDim2.fromOffset(titleWidth, m.Band)
		refs.Receipt.Position = UDim2.fromOffset(PAD + titleWidth, 10)
		refs.Receipt.Size = UDim2.new(1, -(PAD + titleWidth + headRight), 0, m.Band - 20)
		refs.Receipt.TextWrapped = true
		refs.Receipt.TextTruncate = Enum.TextTruncate.None
		refs.Receipt.TextSize = 18
		refs.ReceiptBox = Vector2.new(width - (PAD + titleWidth + headRight) - 16, m.Band - 20)
	else
		refs.Receipt.Position = UDim2.fromOffset(PAD, m.Band + 3)
		refs.Receipt.Size = UDim2.new(1, -PAD * 2, 0, 26)
		refs.Receipt.TextWrapped = false
		refs.Receipt.TextTruncate = Enum.TextTruncate.AtEnd
		refs.Receipt.TextSize = 17
		refs.ReceiptBox = Vector2.new(width - PAD * 2 - 16, 24)
	end
	syncShadow(refs.Title)

	-- tabs: three equal buttons, room for the LB / RB glyphs at the ends;
	-- compact: the bar ends left of the X button (TabGap)
	refs.TabBar.Position = UDim2.fromOffset(PAD, m.Header)
	refs.TabBar.Size = UDim2.new(1, -(PAD * 2 + m.TabGap), 0, m.TabBar)
	-- each tab: share * W - fixed; tab i starts at inset + (i - 1) * (its width + GAP)
	local count = #TABS
	local inset = 26
	local share = 1 / count
	local fixed = (2 * inset + GAP * (count - 1)) / count
	for i, tab in TABS do
		local holder = holderOf(refs.Tabs[tab])
		holder.Position = UDim2.new(share * (i - 1), inset + (i - 1) * (GAP - fixed), 0, 6)
		holder.Size = UDim2.new(share, -fixed, 0, m.TabHeight)
		refs.Tabs[tab].TextSize = if compact then 26 else 24
	end
	refs.TabGlyphs[1].Position = UDim2.new(0, 12, 0, 6 + m.TabHeight / 2)
	refs.TabGlyphs[2].Position = UDim2.new(1, -12, 0, 6 + m.TabHeight / 2)

	local listTop = m.Header + m.TabBar
	for _, list in refs.Lists do
		list.Position = UDim2.fromOffset(PAD, listTop)
		list.Size = UDim2.new(1, -PAD, 1, -(listTop + m.Footer))
	end
	refs.Hint.Visible = not compact and not refs.PadMode
	refs.Hint.Position = UDim2.new(0.5, 0, 1, -6)
	refs.Hint.Size = UDim2.new(1, -PAD * 2, 0, 20)
	refs.PadHint.Visible = not compact and refs.PadMode
	refs.PadHint.Position = UDim2.new(0.5, 0, 1, -4)
	local rowWidth = width - PAD - SCROLLBAR
	for _, row in refs.RowList do
		placeRow(row, m, compact, rowWidth)
	end
	-- the notes: two lines of text over the rows' width
	local noteHeight = math.ceil(m.Note * TechShopView.LineHeight * 2) + 10
	refs.NoteBox = Vector2.new(rowWidth - NOTE_PAD * 2, noteHeight - 6)
	for _, note in refs.Notes do
		note.Size = UDim2.new(1, -SCROLLBAR, 0, noteHeight)
	end
	fitNotes(refs)
	fitReceipt(refs)
end

---------------------------------------------------------------- filling in

-- Shows one tab's list and paints its tab button (the others slate).
function TechShopView.setTab(refs: Refs, tab: string)
	refs.Tab = tab
	for _, name in TABS do
		local on = name == tab
		refs.Lists[name].Visible = on
		local button = refs.Tabs[name]
		paintButton(button, if on then TechShopView.TabPaints[name] else "Slate")
		button.TextTransparency = if on then 0 else 0.25
	end
end

-- A note's text for a device ("{build}" filled in from TechShopView.BuildKey).
function TechShopView.noteText(text: string, device: Device): string
	local key = TechShopView.BuildKey[device] or TechShopView.BuildKey["Keyboard" :: Device]
	return (string.gsub(text, "{build}", key))
end

--[[
	Says where the shop was opened (TechShopView.Where): the subtitle and
	the notes at the top of the lists (TechShopView.WhereText, with
	refs.Device's key). The cards follow with TechShopView.cards(state,
	coins, where).
]]
function TechShopView.setWhere(refs: Refs, where: Where)
	refs.Where = where
	local texts = TechShopView.WhereText[where]
	refs.Subtitle.Text = texts.Subtitle
	for tab, note in refs.Notes do
		local text = texts[tab]
		note.Text = if text then TechShopView.noteText(text, refs.Device) else ""
		note.Visible = text ~= nil
	end
	fitNotes(refs)
end

-- The device in use changed: the notes name its BUILD key (no work when it is the same).
function TechShopView.setDevice(refs: Refs, device: Device)
	if refs.Device == device then
		return
	end
	refs.Device = device
	TechShopView.setWhere(refs, refs.Where)
end

-- A card colour (Theme) as a colour that reads on the dark strip.
local function bright(color: Color3): Color3
	if color == Theme.Bad then
		return PopTheme.Titles.Red[1]
	elseif color == Theme.Good or color == Theme.GoodDark then
		return PopTheme.Money
	elseif color == Theme.Accent or color == Theme.Coin then
		return PopTheme.Titles.Gold[1]
	elseif color == Theme.TextDim then
		return SOFT
	end
	return PopTheme.Ink
end

local function fillRow(row: Row, card: Card)
	row.Card = card
	row.Frame.LayoutOrder = card.Order
	row.Title.Text = string.upper(card.Title)
	row.Chip.Text = card.Chip
	row.Chip.BackgroundColor3 = if card.ChipColor == Theme.PanelDark then PopTheme.Paints.Slate.Bottom else card.ChipColor
	row.Description.Text = card.Description
	row.Detail.Text = card.Detail
	row.Detail.TextColor3 = bright(card.DetailColor)
	row.Price.Text = card.PriceText
	titleGradient(row.Price, if card.PriceColor == Theme.Bad then "Red" else "Gold")
	row.PriceSub.Text = card.PriceSub
	row.PriceSub.TextColor3 = if card.PriceSubColor == Theme.Bad then PopTheme.Titles.Red[1] else PopTheme.Ink
	TechShopView.setIcon(row.Icon, card.Icon, card.Badge)
	for i, button in row.Buttons do
		local buy = card.Buys[i]
		holderOf(button).Visible = buy ~= nil
		-- a button showing an answer ("BOUGHT!", "...") keeps its text and
		-- colors until the controller frees it (and refreshes the card)
		if buy and button:GetAttribute("Busy") ~= true then
			button.Text = buy.Text
			if card.Done then
				-- MAX / OWNED: a green tag
				style(button, true, Theme.Good, Theme.GoodDark)
			else
				style(button, buy.CanBuy, Theme.Accent, Theme.AccentDark)
			end
		end
	end
	fitRow(row)
end

-- Fills every row from TechShopView.cards (rows with no card keep their
-- last content); while the window is open the shown tab's cards get their
-- live 3D pictures (TechShopView.fillPicture, built once).
function TechShopView.setCards(refs: Refs, cards: { Card })
	for _, card in cards do
		local row = refs.Rows[card.Id]
		if row then
			fillRow(row, card)
			if refs.Gui.Enabled and row.Tab == refs.Tab then
				TechShopView.fillPicture(row.Icon)
			end
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
	row.Status.TextColor3 = if color then bright(color) else PopTheme.Ink
	if color == Theme.Info then
		row.Status.TextColor3 = PopTheme.Titles.Cyan[1]
	end
	local b = row.Boxes
	if b.DetailWidth > 0 then
		TechShopView.fitText(row.Status, b.DetailWidth, b.DetailHeight, b.Detail, b.DetailMin)
	end
end

--[[
	The footer hint: `text` (mouse / touch), or with `glyphs` (the images of
	the platform's LB, RB, A and B buttons, from GetImageForKeyCode) the
	gamepad hint "[LB][RB] switch tab  [A] buy  [B] close". Phones show no
	footer.
]]
function TechShopView.setHint(refs: Refs, text: string, glyphs: { string }?)
	refs.Hint.Text = text
	refs.PadMode = glyphs ~= nil
	if glyphs then
		for i, image in refs.PadGlyphs do
			image.Image = glyphs[i] or ""
		end
	end
	refs.Hint.Visible = not refs.Compact and not refs.PadMode
	refs.PadHint.Visible = not refs.Compact and refs.PadMode
end

-- Shows a message (instead of the subtitle).
function TechShopView.showReceipt(refs: Refs, text: string, color: Color3)
	refs.Receipt.Text = text
	refs.Receipt.TextColor3 = color
	refs.Receipt.Visible = true
	fitReceipt(refs)
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
