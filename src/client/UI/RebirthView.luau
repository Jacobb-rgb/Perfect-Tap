--[[
	RebirthView: the STAR FORGE window (rebirth B, RebirthConfig), a side
	menu panel in the MenuPanel frame. Pure builder + layout math, so the
	Lune previews draw the same thing.

	  tabs      REBIRTH | STAR SHOP | BLASTERS (with your unspent stars)
	  REBIRTH   three columns, each a coloured chip over short rows:
	            YOU LOSE (red), YOU KEEP (blue), YOU GET (green): the
	            exact lists of RebirthConfig.reset (Head Start's level and
	            Podium Keeper change the rows); under them what a rebirth
	            needs and the big REBIRTH! button (grey until your blaster
	            reaches MinBlaster; the first press turns it red "SURE?")
	  STAR SHOP a card per perk: icon, name, what a level does, the level
	            (2/10), and its BUY button with the star price (MAX at the top,
	            grey without the stars)
	  BLASTERS  a card per STAR blaster (StarBlasterData): its picture (in
	            the game a live ViewportFrame of the gun, fillPicture; the
	            preview draws the icon "star_<id>"), name, damage and the
	            rebirth that opens it; buttons by weaponCard: ⭐ price + R$
	            price (to buy), EQUIP / EQUIPPED, or a grey 🔒 REBIRTH n

	setInfo(refs, info) fills both pages from the State's Rebirth field and
	the blaster level. layout(refs, compact, maxWidth, maxHeight) sizes the
	panel (phones and TVs: the compact metrics, every button at least
	MenuPanel.MinTouch points at the phone scale).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local KenneyBlaster = require(Shared.Builders.KenneyBlaster)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local Geo = require(Shared.Builders.Geo)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local Rng = require(Shared.Util.Rng)
local UIKit = require(script.Parent.UIKit)
local MenuPanel = require(script.Parent.MenuPanel)
local TechShopView = require(script.Parent.TechShopView)

local RebirthView = {}

local rgb = Color3.fromRGB

export type Info = {
	Count: number, -- rebirths so far
	Stars: number, -- unspent
	Perks: { [string]: any },
	Level: number, -- the blaster level now
	Ready: boolean,
	StarsNow: number, -- what a rebirth now pays
	Reached: number?, -- the level this run counts (RebirthConfig.reachedOf)
	Glow: string?, -- the Plot Glow colour shown ("" = off)
	Weapons: { [string]: boolean }?, -- the STAR blasters owned
	Weapon: string?, -- the one equipped ("" = the forged blaster)
	RobuxOn: boolean?, -- Robux sales are on (the receipts gate)
}

-- What a STAR blaster's card shows (weaponCard).
export type WeaponState = {
	State: string, -- StarBlasterData.cardState
	Line: string, -- under the name
	Main: string, -- the big button
	Style: string, -- its colour: "Buy" | "Off" | "Equip" | "Equipped"
	Robux: string?, -- the R$ button (nil = hidden)
	RobuxOn: boolean, -- it can prompt now (else grey: "soon")
}

export type Column = { Frame: Frame, Chip: TextLabel, Rows: { TextLabel } }
export type Card = {
	Id: string,
	Frame: Frame,
	Icon: TextLabel,
	Name: TextLabel,
	Text: TextLabel,
	Level: TextLabel,
	Buy: TextButton,
	Pick: TextButton?, -- Plot Glow: the colour shown (a tap picks the next unlocked one)
}

export type WeaponCard = {
	Id: string,
	Frame: Frame,
	Picture: ImageLabel, -- the icon "star_<id>" in previews; a dark sky in the game
	View: ViewportFrame, -- the live gun (fillPicture)
	Name: TextLabel,
	Text: TextLabel,
	Main: TextButton,
	Robux: TextButton,
	Robuxed: boolean, -- the R$ button shows (layout)
}

export type Refs = {
	Gui: ScreenGui,
	Frame: MenuPanel.Refs,
	Tabs: { [string]: TextButton },
	Pages: { [string]: Frame },
	Columns: { [string]: Column },
	Need: TextLabel,
	Rebirth: TextButton,
	Message: TextLabel,
	Stars: TextLabel,
	Cards: { Card },
	Weapons: { WeaponCard },
	Tab: string,
	Confirm: boolean,
	Ready: boolean,
	Compact: boolean,
	Laid: boolean, -- layout ran (texts refit when they change)
}

RebirthView.Colors = {
	Rebirth = rgb(160, 168, 255), -- the indigo of the proposal's Rebirth role
	RebirthDark = rgb(60, 64, 172),
	Lose = rgb(236, 84, 70),
	Keep = rgb(96, 186, 255),
	Get = rgb(110, 214, 92),
	Star = rgb(255, 206, 72),
	Equip = rgb(96, 186, 255),
	EquipDark = rgb(40, 96, 170),
	Robux = rgb(76, 214, 72),
	RobuxDark = rgb(22, 106, 34),
	Sky = rgb(18, 16, 38), -- the weapon pictures' night sky (the light skin keeps it)
	Off = rgb(120, 108, 100),
	OffDark = rgb(70, 62, 58),
}

RebirthView.Metrics = {
	-- design units: the wanted panel, a column row, the tab row, the REBIRTH! bar
	Normal = { Width = 980, Height = 650, Row = 34, Text = 18, Chip = 34, Tab = 46, Bar = 86, Card = 134, Button = 46 },
	Compact = { Width = 1180, Height = 600, Row = 38, Text = 21, Chip = 40, Tab = 76, Bar = 96, Card = 176, Button = 76 },
}

RebirthView.TabIds = { "Rebirth", "Shop", "Blasters" }
-- compact layouts: the tabs start this far into the body (right of the "STAR FORGE" title)
RebirthView.TitleRoom = 250
-- the star count's room right of the tabs (design units)
RebirthView.StarsRoom = 120

-- The rows of the three columns for a save (Head Start's level, Podium Keeper).
function RebirthView.lists(perks: any): { [string]: { string } }
	local start = RebirthConfig.startLevel(perks)
	local open = EnchantConfig.unlockedSlots(start)
	local enchantRow = if open < EnchantConfig.MaxSlots
		then `✨  Enchant slots {open + 1}-{EnchantConfig.MaxSlots} for now`
		else "✨  Enchant slots stay open"
	local keepsPodiums = RebirthConfig.levelOf(perks, "PodiumKeeper") > 0
	return {
		Lose = {
			"💰  Your coins",
			`🔫  Blaster back to LV {start}`,
			"⛏️  Floors and elevator",
			"⚙️  Machine speed",
			"🚂  Train and backpack levels",
			enchantRow,
			if keepsPodiums then "🪨  Ore (podiums stay)" else "🪨  All your ore",
		},
		Keep = {
			"🏭  Your whole factory",
			"🤖  Golems and enchants",
			"🏺  Artifacts and codex",
			"🛹  Boards and gear",
			"💎  Shards, Robux items",
			"🏆  Stats and records",
		},
		Get = {
			"⭐  Forge Stars",
			"🔁  A new rebirth",
			"🛒  Star Shop perks",
		},
	}
end

-- What the bottom line says (the requirement, or what a rebirth pays now).
function RebirthView.needText(info: Info): string
	local reached = info.Reached or info.Level
	if info.Ready then
		return `Blaster LV {reached}: a rebirth now pays ⭐ {info.StarsNow}`
	end
	if info.Level >= RebirthConfig.MinBlaster then
		-- a level from the Vault: after the first rebirth the stars want a forged one
		return `Forge blaster LV {RebirthConfig.MinBlaster} at the Foundry to rebirth (Vault cases don't count)`
	end
	return `Reach blaster LV {RebirthConfig.MinBlaster} to rebirth (you have LV {info.Level})`
end

-- A perk card's level text and BUY button text (and whether it can be bought).
function RebirthView.cardText(perks: any, stars: number, id: string): (string, string, boolean)
	local perk = RebirthConfig.ById[id]
	local level = RebirthConfig.levelOf(perks, id)
	local top = if perk then #perk.Costs else 0
	local cost = RebirthConfig.nextCost(perks, id)
	if not cost then
		return `{level}/{top}`, "MAX", false
	end
	return `{level}/{top}`, `⭐ {cost}  BUY`, stars >= cost
end

-- A STAR blaster card's texts and buttons for the save (Info).
function RebirthView.weaponCard(info: Info, star: StarBlasterData.StarBlaster): WeaponState
	local data = { Rebirths = info.Count, Stars = info.Stars, RebirthWeapons = info.Weapons or {}, StarBlaster = info.Weapon or "" }
	local state = StarBlasterData.cardState(data, star.Id)
	local power = `⚡ x{star.Mult} damage`
	if state == "Locked" then
		return {
			State = state,
			Line = `{power} · opens at rebirth {star.Unlock}`,
			Main = `🔒 REBIRTH {star.Unlock}`,
			Style = "Off",
			RobuxOn = false,
		}
	elseif state == "Waiting" then
		return {
			State = state,
			Line = `Yours! It opens at rebirth {star.Unlock}`,
			Main = `🔒 REBIRTH {star.Unlock}`,
			Style = "Off",
			RobuxOn = false,
		}
	elseif state == "Equipped" then
		return { State = state, Line = `{power} · in your hand`, Main = "EQUIPPED ✓", Style = "Equipped", RobuxOn = false }
	elseif state == "Owned" then
		return { State = state, Line = `{power} · yours`, Main = "EQUIP", Style = "Equip", RobuxOn = false }
	end
	local entry = MonetizationConfig.get("Star" .. star.Id)
	local live = entry ~= nil and MonetizationConfig.isLive(entry.Id)
	return {
		State = state,
		Line = power,
		Main = `⭐ {star.Stars}`,
		Style = if info.Stars >= star.Stars then "Buy" else "Off",
		Robux = `R$ {star.Robux}`,
		RobuxOn = live and info.RobuxOn == true,
	}
end

---------------------------------------------------------------- build

local function chunky(parent: Instance, text: string, color: Color3, dark: Color3, name: string): TextButton
	local button = UIKit.button(parent, text, color, dark, { Name = name, TextSize = 22 })
	return button
end

local function newColumn(parent: Instance, id: string, title: string, color: Color3): Column
	local frame = UIKit.new("Frame", {
		Name = id,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2, color)
	local chip = UIKit.chip(frame, title, color, { Name = "Chip" })
	return { Frame = frame, Chip = chip, Rows = {} }
end

local function newCard(parent: Instance, perk: RebirthConfig.Perk, order: number): Card
	local frame = UIKit.new("Frame", {
		Name = "Perk" .. perk.Id,
		LayoutOrder = order,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2, RebirthView.Colors.RebirthDark)
	local icon = UIKit.label(frame, perk.Icon, 34, { Name = "Icon", TextWrapped = false })
	local name = UIKit.label(frame, perk.Name, 20, {
		Name = "PerkName",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local text = UIKit.label(frame, perk.Text, 15, {
		Name = "Text",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})
	local level = UIKit.label(frame, "0/0", 16, { Name = "Level", TextColor3 = RebirthView.Colors.Star, TextWrapped = false })
	local buy = chunky(frame, "BUY", Theme.Good, Theme.GoodDark, "Buy")
	local pick = if perk.Id == "PlotGlow" then chunky(frame, "OFF", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "Pick") else nil
	return { Id = perk.Id, Frame = frame, Icon = icon, Name = name, Text = text, Level = level, Buy = buy, Pick = pick }
end

local function newWeaponCard(parent: Instance, star: StarBlasterData.StarBlaster): WeaponCard
	local frame = UIKit.new("Frame", {
		Name = "Weapon" .. star.Id,
		LayoutOrder = star.Index,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2, star.Glow:Lerp(Color3.new(0, 0, 0), 0.25))
	local picture = UIKit.new("ImageLabel", {
		Name = "Picture",
		BackgroundColor3 = RebirthView.Colors.Sky,
		BorderSizePixel = 0,
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
	}, frame)
	picture:SetAttribute("Icon", "star_" .. star.Id) -- the preview's rendered icon (tools/preview/icons)
	UIKit.corner(picture, 10)
	UIKit.stroke(picture, 2, star.Glow)
	local view = UIKit.new("ViewportFrame", {
		Name = "View",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = rgb(150, 150, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -0.4),
	}, picture)
	local name = UIKit.label(frame, string.upper(star.Name), 20, {
		Name = "WeaponName",
		TextColor3 = star.Glow:Lerp(Color3.new(1, 1, 1), 0.35),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local text = UIKit.label(frame, "", 15, {
		Name = "Text",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TextDim,
	})
	local main = chunky(frame, "EQUIP", Theme.Good, Theme.GoodDark, "Main")
	local robux = chunky(frame, "R$", RebirthView.Colors.Robux, RebirthView.Colors.RobuxDark, "Robux")
	return {
		Id = star.Id,
		Frame = frame,
		Picture = picture,
		View = view,
		Name = name,
		Text = text,
		Main = main,
		Robux = robux,
		Robuxed = true,
	}
end

--[[
	Builds the live gun into a weapon card's ViewportFrame (once; the
	controller calls it when the BLASTERS page first shows): the game's own
	star blaster parts (BlasterBuilder.starSkin, KenneyBlaster.parts), seen
	from the side with the barrel to the right, a little from above.
]]
function RebirthView.fillPicture(card: WeaponCard)
	local star = StarBlasterData.get(card.Id)
	local view = card.View
	if not star or view:FindFirstChild("Gun") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Gun"
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local level, ore, skin = BlasterBuilder.starSkin(star)
	KenneyBlaster.parts(level, ore, skin, function(name, cf, size, color, material, className)
		local part = Geo.make(className or "Part", {
			Name = name,
			CFrame = cf,
			Size = size,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
			CastShadow = false,
		}, model)
		local at = cf.Position
		local half = size * 0.5
		lo = Vector3.new(math.min(lo.X, at.X - half.X), math.min(lo.Y, at.Y - half.Y), math.min(lo.Z, at.Z - half.Z))
		hi = Vector3.new(math.max(hi.X, at.X + half.X), math.max(hi.Y, at.Y + half.Y), math.max(hi.Z, at.Z + half.Z))
		return part
	end)
	model.Parent = view
	local center = (lo + hi) * 0.5
	local radius = math.max(0.5, (hi - lo).Magnitude * 0.5)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	-- from +X the barrel (-Z) points to the right of the picture
	local from = Vector3.new(1, 0.3, 0.18).Unit * (radius / math.sin(math.rad(15)) * 0.92)
	camera.CFrame = CFrame.lookAt(center + from, center)
	camera.Parent = view
	view.CurrentCamera = camera
end

function RebirthView.build(): Refs
	local frame = MenuPanel.build("TerraForgeRebirth", "STAR FORGE", "Rebirth: start over with your factory and earn Forge Stars")
	local body = frame.Body
	local tabs: { [string]: TextButton } = {}
	tabs.Rebirth = chunky(body, "REBIRTH", RebirthView.Colors.Rebirth, RebirthView.Colors.RebirthDark, "TabRebirth")
	tabs.Shop = chunky(body, "STAR SHOP", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "TabShop")
	tabs.Blasters = chunky(body, "BLASTERS", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "TabBlasters")
	local stars = UIKit.label(body, "⭐ 0", 24, {
		Name = "Stars",
		TextColor3 = RebirthView.Colors.Star,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})

	local rebirthPage = UIKit.new("Frame", { Name = "RebirthPage", BackgroundTransparency = 1 }, body)
	local columns: { [string]: Column } = {
		Lose = newColumn(rebirthPage, "Lose", "YOU LOSE", RebirthView.Colors.Lose),
		Keep = newColumn(rebirthPage, "Keep", "YOU KEEP", RebirthView.Colors.Keep),
		Get = newColumn(rebirthPage, "Get", "YOU GET", RebirthView.Colors.Get),
	}
	local lists = RebirthView.lists(nil)
	for id: string, column: Column in columns do
		for i = 1, #lists[id] do
			table.insert(
				column.Rows,
				UIKit.label(column.Frame, "", 18, {
					Name = "Row" .. i,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
				})
			)
		end
	end
	local need = UIKit.label(rebirthPage, "", 18, {
		Name = "Need",
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
	})
	local rebirth = chunky(rebirthPage, "REBIRTH!", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "RebirthButton")
	local message = UIKit.label(rebirthPage, "", 16, { Name = "Message", TextColor3 = Theme.Bad, TextWrapped = true, Visible = false })

	local shopPage = UIKit.new("ScrollingFrame", {
		Name = "ShopPage",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, body)
	UIKit.new("UIGridLayout", {
		Name = "Grid",
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellPadding = UDim2.fromOffset(10, 10),
		CellSize = UDim2.fromOffset(300, 116),
	}, shopPage)
	local cards = {}
	for i, perk in RebirthConfig.Perks do
		table.insert(cards, newCard(shopPage, perk, i))
	end

	local weaponPage = UIKit.new("ScrollingFrame", {
		Name = "BlastersPage",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, body)
	UIKit.new("UIGridLayout", {
		Name = "Grid",
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellPadding = UDim2.fromOffset(10, 10),
		CellSize = UDim2.fromOffset(300, 116),
	}, weaponPage)
	local weapons = {}
	for _, star in StarBlasterData.List do
		table.insert(weapons, newWeaponCard(weaponPage, star))
	end

	return {
		Gui = frame.Gui,
		Frame = frame,
		Tabs = tabs,
		Pages = { Rebirth = rebirthPage, Shop = shopPage, Blasters = weaponPage },
		Columns = columns,
		Need = need,
		Rebirth = rebirth,
		Message = message,
		Stars = stars,
		Cards = cards,
		Weapons = weapons,
		Tab = "Rebirth",
		Confirm = false,
		Ready = false,
		Compact = false,
		Laid = false,
	}
end

---------------------------------------------------------------- layout

local function rect(object: GuiObject, x: number, y: number, w: number, h: number)
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
end

local function place(button: TextButton, x: number, y: number, w: number, h: number)
	rect(MenuPanel.holderOf(button), x, y, w, h)
end

-- The metrics of a layout.
function RebirthView.metrics(compact: boolean): typeof(RebirthView.Metrics.Normal)
	return if compact then RebirthView.Metrics.Compact else RebirthView.Metrics.Normal
end

-- Sizes and places everything in the room the panel gets (design units).
-- Normal: the tabs and the star count on top of the body. Compact (phones,
-- TVs): they sit in the header's free room right of the title, so the
-- columns get the whole body. The requirement line and REBIRTH! sit in the
-- YOU GET column (it has the fewest rows).
function RebirthView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	local m = RebirthView.metrics(compact)
	refs.Compact = compact
	refs.Laid = true
	local body = MenuPanel.layout(refs.Frame, compact, m.Width, m.Height, maxWidth, maxHeight)
	local w, h = body.X, body.Y
	-- tabs and the star count (it keeps StarsRoom on the right)
	local tabs = #RebirthView.TabIds
	local top: number
	local tabX, tabY, tabW
	if compact then
		local header = MenuPanel.Metrics.Compact.Header
		tabY = -header + (header - m.Tab) / 2
		tabX = RebirthView.TitleRoom
		-- up to the X button (it hangs MenuPanel.Pad - 4 from the panel's right edge)
		local starsRight = w + MenuPanel.Pad - (MenuPanel.Pad - 4) - MenuPanel.Metrics.Compact.Close - 8
		tabW = math.min(220, (starsRight - tabX - RebirthView.StarsRoom - tabs * 10) / tabs)
		local starsX = tabX + (tabW + 10) * tabs
		rect(refs.Stars, starsX, tabY, math.max(0, starsRight - starsX), m.Tab)
		top = 0
	else
		-- (8 down: the buttons' lip rises 5 toward the subtitle)
		tabX, tabY = 0, 8
		tabW = math.min(200, (w - RebirthView.StarsRoom - tabs * 10) / tabs)
		local starsX = (tabW + 10) * tabs
		rect(refs.Stars, starsX, 8, w - starsX, m.Tab)
		top = m.Tab + 18
	end
	for i, id in RebirthView.TabIds do
		local tab = refs.Tabs[id]
		place(tab, tabX + (i - 1) * (tabW + 10), tabY, tabW, m.Tab)
		TechShopView.fitText(tab :: any, tabW - 12, m.Tab, m.Text + 4, m.Text - 6)
	end
	refs.Stars.TextSize = m.Text + 8
	local pageH = h - top
	rect(refs.Pages.Rebirth, 0, top, w, pageH)
	rect(refs.Pages.Shop, 0, top, w, pageH)
	rect(refs.Pages.Blasters, 0, top, w, pageH)
	-- the three columns
	local gap = 10
	local colW = (w - gap * 2) / 3
	local x = 0
	local getX = 0
	local rowsEnd = 0
	for _, id in { "Lose", "Keep", "Get" } do
		local column = refs.Columns[id]
		rect(column.Frame, x, 0, colW, pageH)
		rect(column.Chip, 10, 8, colW - 20, m.Chip)
		column.Chip.TextSize = m.Text + 2
		for i, row in column.Rows do
			rect(row, 12, 8 + m.Chip + 8 + (i - 1) * m.Row, colW - 24, m.Row)
			TechShopView.fitText(row, colW - 24, m.Row, m.Text, m.Text - 6)
			if id == "Get" then
				rowsEnd = 8 + m.Chip + 8 + i * m.Row
			end
		end
		if id == "Get" then
			getX = x
		end
		x += colW + gap
	end
	-- the requirement line and the button at the bottom of YOU GET
	local buttonY = pageH - m.Button - 12
	local lineY = rowsEnd + 6
	local lineH = math.max(0, buttonY - 8 - lineY)
	rect(refs.Need, getX + 12, lineY, colW - 24, lineH)
	refs.Need.TextSize = m.Text - 1
	rect(refs.Message, getX + 12, lineY, colW - 24, lineH)
	refs.Message.TextSize = m.Text - 1
	place(refs.Rebirth, getX + 12, buttonY, colW - 24, m.Button)
	refs.Rebirth.TextSize = m.Text + 10
	-- the shop's cards: two or three columns
	local columns = if w >= 3 * 300 + 2 * 10 + 8 then 3 else 2
	local cardW = math.floor((w - 8 - (columns - 1) * 10) / columns)
	local grid = refs.Pages.Shop:FindFirstChild("Grid") :: UIGridLayout
	grid.CellSize = UDim2.fromOffset(cardW, m.Card)
	for _, card in refs.Cards do
		rect(card.Icon, 8, 8, 48, 48)
		rect(card.Name, 62, 8, cardW - 62 - 70, 28)
		TechShopView.fitText(card.Name, cardW - 62 - 70, 28, m.Text + 2, m.Text - 4)
		rect(card.Level, cardW - 70, 8, 62, 28)
		card.Level.TextSize = m.Text
		rect(card.Text, 62, 38, cardW - 70, m.Card - 38 - m.Button - 14)
		TechShopView.fitText(card.Text, cardW - 70, m.Card - 38 - m.Button - 14, m.Text - 2, m.Text - 6)
		place(card.Buy, cardW - 190, m.Card - m.Button - 8, 182, m.Button)
		card.Buy.TextSize = m.Text + 2
		local pick = card.Pick
		if pick then
			place(pick, 8, m.Card - m.Button - 8, cardW - 190 - 16, m.Button)
			pick.TextSize = m.Text
		end
	end
	RebirthView.layoutWeapons(refs)
end

-- The BLASTERS cards (two columns): the picture on the left, the name and
-- the line, the buttons at the bottom (the R$ one only while it shows).
function RebirthView.layoutWeapons(refs: Refs)
	local m = RebirthView.metrics(refs.Compact)
	local page = refs.Pages.Blasters
	local w = page.Size.X.Offset
	local cardW = math.floor((w - 8 - 10) / 2)
	local cardH = m.Card
	local grid = page:FindFirstChild("Grid") :: UIGridLayout
	grid.CellSize = UDim2.fromOffset(cardW, cardH)
	local pic = cardH - 16
	local x = pic + 18
	local right = cardW - x - 8
	for _, card in refs.Weapons do
		rect(card.Picture, 8, 8, pic, pic)
		rect(card.Name, x, 8, right, 28)
		TechShopView.fitText(card.Name, right, 28, m.Text + 2, m.Text - 6)
		local buttonY = cardH - m.Button - 8
		rect(card.Text, x, 38, right, math.max(0, buttonY - 38 - 4))
		TechShopView.fitText(card.Text, right, math.max(0, buttonY - 38 - 4), m.Text - 2, m.Text - 7)
		local robuxW = if card.Robuxed then math.floor(right * 0.45) else 0
		local mainW = if card.Robuxed then right - robuxW - 8 else right
		place(card.Main, x, buttonY, mainW, m.Button)
		TechShopView.fitText(card.Main :: any, mainW - 10, m.Button - 6, m.Text + 2, m.Text - 6)
		MenuPanel.holderOf(card.Robux).Visible = card.Robuxed
		if card.Robuxed then
			place(card.Robux, x + mainW + 8, buttonY, robuxW, m.Button)
			TechShopView.fitText(card.Robux :: any, robuxW - 10, m.Button - 6, m.Text + 2, m.Text - 6)
		end
	end
end

---------------------------------------------------------------- state

-- Shows one page (and lights its tab).
function RebirthView.setTab(refs: Refs, tab: string)
	refs.Tab = if tab == "Shop" or tab == "Blasters" then tab else "Rebirth"
	for _, id in RebirthView.TabIds do
		local on = id == refs.Tab
		refs.Pages[id].Visible = on
		local color = if on then RebirthView.Colors.Rebirth else RebirthView.Colors.Off
		local dark = if on then RebirthView.Colors.RebirthDark else RebirthView.Colors.OffDark
		MenuPanel.style(refs.Tabs[id], color, dark)
	end
end

-- The REBIRTH! button: grey (not ready), indigo, or red "SURE?" (waiting for the second press).
function RebirthView.setConfirm(refs: Refs, on: boolean)
	refs.Confirm = on and refs.Ready
	local button = refs.Rebirth
	if not refs.Ready then
		button.Text = "REBIRTH!"
		MenuPanel.style(button, RebirthView.Colors.Off, RebirthView.Colors.OffDark)
	elseif refs.Confirm then
		button.Text = "SURE?"
		MenuPanel.style(button, Theme.Bad, Theme.BadDark)
	else
		button.Text = "REBIRTH!"
		MenuPanel.style(button, RebirthView.Colors.Rebirth, RebirthView.Colors.RebirthDark)
	end
end

-- A short line in place of the requirement (a refusal), or nil to hide it.
function RebirthView.setMessage(refs: Refs, text: string?)
	refs.Message.Visible = text ~= nil and text ~= ""
	refs.Message.Text = text or ""
	refs.Need.Visible = not refs.Message.Visible
end

-- Fills both pages.
function RebirthView.setInfo(refs: Refs, info: Info)
	local lists = RebirthView.lists(info.Perks)
	lists.Get[1] = if info.Ready then `⭐  {info.StarsNow} Forge Stars` else `⭐  Stars from LV {RebirthConfig.MinBlaster}`
	lists.Get[2] = `🔁  Rebirth #{info.Count + 1}`
	for id, column in refs.Columns do
		for i, row in column.Rows do
			row.Text = lists[id][i] or ""
			if refs.Laid then
				local m = RebirthView.metrics(refs.Compact)
				TechShopView.fitText(row, row.Size.X.Offset, row.Size.Y.Offset, m.Text, m.Text - 6)
			end
		end
	end
	refs.Need.Text = RebirthView.needText(info)
	refs.Need.TextColor3 = if info.Ready then RebirthView.Colors.Get else Theme.TextDim
	refs.Ready = info.Ready
	RebirthView.setConfirm(refs, refs.Confirm)
	refs.Stars.Text = `⭐ {info.Stars}`
	refs.Tabs.Shop.Text = "STAR SHOP"
	for _, card in refs.Cards do
		local level, buy, affordable = RebirthView.cardText(info.Perks, info.Stars, card.Id)
		card.Level.Text = level
		card.Buy.Text = buy
		local pick = card.Pick
		if pick then
			local shown = info.Glow or ""
			local color: RebirthConfig.GlowColor? = nil
			for _, c in RebirthConfig.GlowColors do
				if c.Id == shown then
					color = c
				end
			end
			local picked = color
			if picked then
				pick.Text = string.upper(picked.Name)
				MenuPanel.style(pick, picked.Color:Lerp(Color3.new(0, 0, 0), 0.15), picked.Color:Lerp(Color3.new(0, 0, 0), 0.5))
			else
				pick.Text = "OFF"
				MenuPanel.style(pick, RebirthView.Colors.Off, RebirthView.Colors.OffDark)
			end
			MenuPanel.holderOf(pick).Visible = RebirthConfig.levelOf(info.Perks, card.Id) > 0
		end
		if buy == "MAX" then
			MenuPanel.style(card.Buy, RebirthView.Colors.Star, Theme.AccentDark)
		elseif affordable then
			MenuPanel.style(card.Buy, Theme.Good, Theme.GoodDark)
		else
			MenuPanel.style(card.Buy, RebirthView.Colors.Off, RebirthView.Colors.OffDark)
		end
	end
	RebirthView.setWeapons(refs, info)
end

local WEAPON_STYLES = {
	Buy = { Theme.Good, Theme.GoodDark },
	Off = { RebirthView.Colors.Off, RebirthView.Colors.OffDark },
	Equip = { RebirthView.Colors.Equip, RebirthView.Colors.EquipDark },
	Equipped = { RebirthView.Colors.Star, Theme.AccentDark },
}

-- Fills the BLASTERS cards (weaponCard) and fits them again (the R$ button may have come or gone).
function RebirthView.setWeapons(refs: Refs, info: Info)
	for _, card in refs.Weapons do
		local star = StarBlasterData.get(card.Id)
		if star then
			local shown = RebirthView.weaponCard(info, star)
			card.Text.Text = shown.Line
			card.Main.Text = shown.Main
			local style = WEAPON_STYLES[shown.Style] or WEAPON_STYLES.Off
			MenuPanel.style(card.Main, style[1], style[2])
			card.Robuxed = shown.Robux ~= nil
			card.Robux.Text = shown.Robux or ""
			if shown.RobuxOn then
				MenuPanel.style(card.Robux, RebirthView.Colors.Robux, RebirthView.Colors.RobuxDark)
			else
				MenuPanel.style(card.Robux, RebirthView.Colors.Off, RebirthView.Colors.OffDark)
			end
		end
	end
	if refs.Laid then
		RebirthView.layoutWeapons(refs)
	end
end

---------------------------------------------------------------- the moment

export type Moment = { Gui: ScreenGui, Flash: Frame, Banner: TextLabel, Paid: TextLabel, Stars: { TextLabel } }

-- The rebirth moment's overlay: a white flash, the banner "REBIRTH n!", the
-- stars it paid and a handful of falling stars (RebirthController animates
-- it; `seed` places the stars).
function RebirthView.buildMoment(count: number, stars: number, seed: number?): Moment
	local gui = UIKit.screen("TerraForgeRebirthMoment", 40)
	gui.IgnoreGuiInset = true
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	}, gui)
	local banner = UIKit.label(gui, `REBIRTH {count}!`, 72, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(900, 110),
		FontFace = Theme.TitleFont,
		TextColor3 = RebirthView.Colors.Star,
		TextWrapped = false,
	})
	UIKit.textStroke(banner, 4)
	local paid = UIKit.label(gui, `+{stars} Forge Stars`, 40, {
		Name = "Paid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(700, 60),
		TextColor3 = Theme.Text,
		TextWrapped = false,
	})
	UIKit.textStroke(paid, 3)
	local rng = Rng.new(seed or 7)
	local list = {}
	for i = 1, 18 do
		local star = UIKit.label(gui, "⭐", rng:int(26, 44), {
			Name = "Star" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rng:range(0.1, 0.9), rng:range(0.05, 0.95)),
			Size = UDim2.fromOffset(50, 50),
			Rotation = rng:range(-60, 60),
			TextWrapped = false,
		})
		table.insert(list, star)
	end
	return { Gui = gui, Flash = flash, Banner = banner, Paid = paid, Stars = list }
end

-- Every button (touch-size tests: MenuPanel.MinTouch at MenuPanel.PhoneScale).
function RebirthView.buttons(refs: Refs): { TextButton }
	local list = { refs.Tabs.Rebirth, refs.Tabs.Shop, refs.Tabs.Blasters, refs.Rebirth }
	for _, card in refs.Cards do
		table.insert(list, card.Buy)
		if card.Pick then
			table.insert(list, card.Pick)
		end
	end
	for _, card in refs.Weapons do
		table.insert(list, card.Main)
		if card.Robuxed then
			table.insert(list, card.Robux)
		end
	end
	return list
end

return RebirthView
