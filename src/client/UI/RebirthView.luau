--[[
	RebirthView: the STAR FORGE window (rebirth B, RebirthConfig), a side
	menu panel in the MenuPanel frame. Pure builder + layout math, so the
	Lune previews draw the same thing.

	  tabs      REBIRTH | STAR SHOP | BLASTERS (with your unspent stars: "12 STARS")
	  REBIRTH   three columns, each a coloured chip over short rows (a dot
	            in the column's colour before each):
	            YOU LOSE (red), YOU KEEP (blue), YOU GET (green): the
	            exact lists of RebirthConfig.reset (Head Start's level and
	            Podium Keeper change the rows); under them what a rebirth
	            needs and the big REBIRTH! button (grey until your blaster
	            reaches MinBlaster; the first press turns it red "SURE?")
	  STAR SHOP a card per perk: name, what a level does, the level (2/10),
	            and its BUY button with the star price ("BUY 2 STARS"; MAX at
	            the top, grey without the stars)
	  BLASTERS  a card per STAR blaster (StarBlasterData): its picture (in
	            the game a live ViewportFrame of the gun, fillPicture; the
	            preview draws the icon "star_<id>"), name, damage and the
	            rebirth that opens it; buttons by weaponCard: the star price
	            ("20 STARS") + R$ price (to buy), EQUIP / EQUIPPED, or a grey
	            "LOCKED: REBIRTH n"
	Words only, no emoji (the owner's "text only"; NoEmoji.spec).

	setInfo(refs, info) fills both pages from the State's Rebirth field and
	the blaster level. layout(refs, compact, maxWidth, maxHeight) sizes the
	panel (phones and TVs: the compact metrics, every button at least
	MenuPanel.MinTouch points at the phone scale).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.UITheme)
local UIConfig = require(Shared.Config.UIConfig)
local PopTheme = require(Shared.Config.PopTheme)
local IconAssets = require(Shared.Config.IconAssets)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local BlasterData = require(Shared.Config.BlasterData)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local KenneyBlaster = require(Shared.Builders.KenneyBlaster)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local Geo = require(Shared.Builders.Geo)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local Rng = require(Shared.Util.Rng)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
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
	Start: number?, -- the level a rebirth starts with (RebirthConfig.startFor: Head Start + Robux levels)
	Glow: string?, -- the Plot Glow colour shown ("" = off)
	Weapons: { [string]: boolean }?, -- the STAR blasters owned
	Weapon: string?, -- the one equipped ("" = your own blaster)
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
-- a column row's bullet dot and the room it takes left of the row's text (design units)
RebirthView.Dot = 8
RebirthView.DotRoom = 18

-- The rows of the three columns for a save (Head Start's level, Podium Keeper;
-- `lifted` = the level the rebirth starts with when Robux levels lift it: RebirthConfig.startFor).
function RebirthView.lists(perks: any, lifted: number?): { [string]: { string } }
	local start = lifted or RebirthConfig.startLevel(perks)
	local open = EnchantConfig.unlockedSlots(start)
	local enchantRow = if open < EnchantConfig.MaxSlots
		then `Enchant slots {open + 1}-{EnchantConfig.MaxSlots} for now`
		else "Enchant slots stay open"
	local keepsPodiums = RebirthConfig.levelOf(perks, "PodiumKeeper") > 0
	return {
		Lose = {
			"Earned coins",
			`Blaster back to LV {start}`,
			"Floors and elevator",
			"Machine + furnace upgrades",
			"Train and backpack levels",
			enchantRow,
			if keepsPodiums then "Ore (podiums stay)" else "All your ore",
		},
		Keep = {
			"Your factory, droppers",
			"Golems and enchants",
			"Artifacts and codex",
			"Boards, gear, star blasters",
			"Shards, Robux items",
			"Coins bought with Robux",
			"Stats and records",
		},
		Get = {
			"Forge Stars",
			"A new rebirth",
			"Star Shop perks",
		},
	}
end

-- A star amount on the buttons, by the tabs and over the heads ("1 STAR", "12 STARS").
function RebirthView.starsLabel(count: number): string
	return string.upper(RebirthConfig.starsText(count))
end

-- What the bottom line says (the requirement, or what a rebirth pays now).
function RebirthView.needText(info: Info): string
	local reached = info.Reached or info.Level
	if info.Ready and info.StarsNow <= 0 then
		-- at the top with no level bought with coins this run: a rebirth is allowed, for no stars
		return "Nothing left to buy: a rebirth now pays no stars"
	end
	if info.Ready then
		return `Blaster LV {reached}: a rebirth now pays {RebirthConfig.starsText(info.StarsNow)}`
	end
	if info.Level >= RebirthConfig.MinBlaster then
		return RebirthView.forgeText(info.Level)
	end
	return `Reach blaster LV {RebirthConfig.MinBlaster} to rebirth (you have LV {info.Level})`
end

-- What a run past MinBlaster with no rebirth level bought with coins needs (Robux levels never count).
function RebirthView.forgeText(level: number): string
	return `Buy blaster LV {math.min(level + 1, BlasterData.MaxLevel)} with coins at the Blaster Vault to rebirth (Robux levels don't count)`
end

-- A perk card's level text and BUY button text (and whether it can be bought). `start` =
-- the level a rebirth starts with (RebirthConfig.startFor): Head Start adds nothing at MaxLevel - 1.
function RebirthView.cardText(perks: any, stars: number, id: string, start: number?): (string, string, boolean)
	local perk = RebirthConfig.ById[id]
	local level = RebirthConfig.levelOf(perks, id)
	local top = if perk then #perk.Costs else 0
	local cost = RebirthConfig.nextCost(perks, id)
	if not cost or (id == "HeadStart" and start and start >= BlasterData.MaxLevel - 1) then
		return `{level}/{top}`, "MAX", false
	end
	return `{level}/{top}`, `BUY {RebirthView.starsLabel(cost)}`, stars >= cost
end

-- A STAR blaster card's texts and buttons for the save (Info).
function RebirthView.weaponCard(info: Info, star: StarBlasterData.StarBlaster): WeaponState
	local data = { Rebirths = info.Count, Stars = info.Stars, RebirthWeapons = info.Weapons or {}, StarBlaster = info.Weapon or "" }
	local state = StarBlasterData.cardState(data, star.Id)
	local power = `Damage x{star.Mult}`
	if state == "Locked" then
		return {
			State = state,
			Line = power,
			Main = `LOCKED: REBIRTH {star.Unlock}`,
			Style = "Off",
			RobuxOn = false,
		}
	elseif state == "Waiting" then
		return {
			State = state,
			Line = `Yours! It opens at rebirth {star.Unlock}`,
			Main = `LOCKED: REBIRTH {star.Unlock}`,
			Style = "Off",
			RobuxOn = false,
		}
	elseif state == "Equipped" then
		return { State = state, Line = `{power} · equipped`, Main = "EQUIPPED", Style = "Equipped", RobuxOn = false }
	elseif state == "Owned" then
		return { State = state, Line = `{power} · yours`, Main = "EQUIP", Style = "Equip", RobuxOn = false }
	end
	local entry = MonetizationConfig.get("Star" .. star.Id)
	local live = entry ~= nil and MonetizationConfig.isLive(entry.Id)
	return {
		State = state,
		Line = power,
		Main = RebirthView.starsLabel(star.Stars),
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
	return { Id = perk.Id, Frame = frame, Name = name, Text = text, Level = level, Buy = buy, Pick = pick }
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
	from the side with the barrel to the left, a little from above.
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
	-- from -X the barrel (-Z) points to the left of the picture (like the blaster icons)
	local from = Vector3.new(-1, 0.3, 0.18).Unit * (radius / math.sin(math.rad(15)) * 0.92)
	camera.CFrame = CFrame.lookAt(center + from, center)
	camera.Parent = view
	view.CurrentCamera = camera
end

---------------------------------------------------------------- the Pop look (UIConfig.LightUI)
--[[
	While the light UI is on (it ships on) the window wears the bright Pop
	look of the Robux Shop (UI/Pop; owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"): an indigo header band (the
	window's colour) with shine stripes and studs over a dark studded body
	(MenuPanel's Pop frame without the LightSkin, the same refs), the
	tabs as Pop tabs, YOU LOSE / KEEP / GET as painted red / blue / green
	cards, the star shop's and the blasters' cards bright and painted (the
	live gun in a light burst), the green Robux buttons with the robux
	mark, and a big glowing gold REBIRTH! (grey until ready, red SURE?).
	The buttons keep their state colour in BackgroundColor3 (MenuPanel.style,
	unseen on a Pop button): popRestyle paints the faces from it.
]]

RebirthView.PopPaint = { Top = rgb(176, 160, 255), Bottom = rgb(84, 70, 226), Edge = PopTheme.Outline } :: Pop.Paint
RebirthView.PopColumns = { Lose = "Red", Keep = "Blue", Get = "Green" } :: { [string]: string }
RebirthView.PopCards = { "Blue", "Purple", "Teal", "Pink", "Orange", "Green" } -- the star shop's cards in turn

local GLOW_GOLD = rgb(255, 214, 70)

-- The black edge of a text (its Contextual UIStroke, made when missing).
local function popEdge(label: GuiObject)
	local t: any = label
	local edge: UIStroke? = nil
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			edge = child
		end
	end
	local made = edge or Pop.edge(label)
	made.Color = PopTheme.Outline
	made.Transparency = 0
	made.LineJoinMode = Enum.LineJoinMode.Round
	made.Thickness = Pop.edgeFor(if t.TextScaled then 24 else t.TextSize)
end

-- White chunky words with a black edge.
local function popText(label: GuiObject, font: Font?)
	local t: any = label
	t.FontFace = font or PopTheme.Font
	t.TextColor3 = PopTheme.Ink
	popEdge(label)
end

-- A lip button (UIKit.button) as a Pop button: the holder painted, the button see-through on it.
local function popButton(button: TextButton, paint: string | Pop.Paint, role: string?)
	local holder = MenuPanel.holderOf(button)
	for _, child in holder:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	local corner = holder:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 10)
	end
	Pop.face(holder, paint, 10)
	local rim = holder:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 1
	end
	Pop.studs(holder, 10, 0.45, 28, 1)
	holder:SetAttribute("Pop", true)
	if role then
		holder:SetAttribute("PopRole", role)
	end
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
	button.BackgroundTransparency = 1
	button.Position = UDim2.new()
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 3
	popText(button)
end

-- A painted card face on an old frame (paint, studs, light rim, sparkles); its
-- own children move above the decoration (ZIndex 5+).
local function popCard(frame: Frame, paint: string | Pop.Paint)
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		elseif child:IsA("GuiObject") then
			child.ZIndex = math.max(child.ZIndex, 5)
		end
	end
	local round = frame:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0, 12)
	end
	Pop.face(frame, paint, 12, false)
	frame.ClipsDescendants = true
	Pop.studs(frame, 12, 0.5, 44, 2)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	for i, spot in { { 0.92, 0.18, 16 }, { 0.84, 0.82, 12 }, { 0.5, 0.1, 12 } } do
		Pop.sparkle(frame, UDim2.fromScale(spot[1], spot[2]), spot[3], 3, 0.2 + i * 0.1)
	end
end

-- A chip (UIKit.chip) as a Pop chip: a dark well, a black edge, white words.
local function popChip(chip: TextLabel)
	chip.BackgroundColor3 = PopTheme.Well
	for _, child in chip:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child.Color = PopTheme.Outline
			child.Thickness = 2.5
		end
	end
	popText(chip)
end

-- The face of a button from its state colour (BackgroundColor3, set by MenuPanel.style).
local function popPaintOf(button: TextButton): string | Pop.Paint
	local c = button.BackgroundColor3
	local role = MenuPanel.holderOf(button):GetAttribute("PopRole")
	if c == RebirthView.Colors.Off then
		return if role == "Tab" then "Slate" else PopTheme.Gray
	elseif c == RebirthView.Colors.Rebirth then
		return if role == "Rebirth" then "Yellow" else RebirthView.PopPaint
	elseif c == Theme.Good then
		return if role == "Weapon" then "Yellow" else "Green" -- (a star blaster's star price in gold)
	elseif c == Theme.Bad then
		return "Red"
	elseif c == RebirthView.Colors.Star then
		return if role == "Weapon" then "Green" else "Yellow" -- (EQUIPPED / MAX)
	elseif c == RebirthView.Colors.Equip then
		return "Blue"
	elseif c == RebirthView.Colors.Robux then
		return PopTheme.Price
	end
	-- (Plot Glow's colours)
	return { Top = c:Lerp(Color3.new(1, 1, 1), 0.3), Bottom = c:Lerp(Color3.new(0, 0, 0), 0.25), Edge = PopTheme.Outline }
end

-- The robux mark and the price on a star blaster's R$ button ("R$ 125"), like Pop.price.
local function syncRobux(button: TextButton)
	local amount = string.match(button.Text, "^R%$ (%d+)$")
	local face = button:FindFirstChild("PopFace") :: Frame?
	button.TextTransparency = if amount then 1 else 0
	local edge = button:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Transparency = if amount then 1 else 0
	end
	if not amount then
		if face then
			face.Visible = false
		end
		return
	end
	local holder = MenuPanel.holderOf(button)
	local w, h = holder.Size.X.Offset, holder.Size.Y.Offset
	local key = `{amount}|{w}|{h}`
	if face and face:GetAttribute("Key") == key then
		face.Visible = true
		return
	end
	if face then
		face:Destroy()
	end
	local size = math.clamp(math.floor(math.min(h * 0.55, (w - 16 - h * 0.55) / (#amount * 0.6))), 12, 40)
	local row = UIKit.new("Frame", {
		Name = "PopFace",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, button)
	row:SetAttribute("Key", key)
	UIKit.list(row, Enum.FillDirection.Horizontal, 4, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local mark = UIKit.new("ImageLabel", {
		Name = "Mark",
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size + 2, size + 2),
		ZIndex = 5,
	}, row)
	IconAssets.apply(mark, "robux")
	mark:SetAttribute("Icon", "robux")
	Pop.text(row, amount, size, {
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Pop.textWidth(amount, size), size + 6),
		ZIndex = 6,
	})
end

local function isPop(refs: Refs): boolean
	return refs.Gui:GetAttribute("PopSkin") == true
end

-- The pages in the Pop look (after the dark build made them).
local function popSkin(refs: Refs)
	for _, id in RebirthView.TabIds do
		popButton(refs.Tabs[id], "Slate", "Tab")
	end
	popEdge(refs.Stars)
	refs.Stars.FontFace = PopTheme.Heavy
	-- YOU LOSE / KEEP / GET: painted red / blue / green cards, white dots
	for id, column in refs.Columns do
		column.Frame.ZIndex = 2
		popCard(column.Frame, RebirthView.PopColumns[id] or "Slate")
		popChip(column.Chip)
		for _, row in column.Rows do
			popText(row)
			local dot = row:FindFirstChild("Dot") :: Frame?
			if dot then
				dot.BackgroundColor3 = Color3.new(1, 1, 1)
				UIKit.stroke(dot, 1.5, PopTheme.Outline)
			end
		end
	end
	-- the requirement line and the big glowing REBIRTH! over the YOU GET card
	for _, label in { refs.Need, refs.Message } do
		label.ZIndex = 6
		popText(label)
	end
	local rebirthHolder = MenuPanel.holderOf(refs.Rebirth)
	rebirthHolder.ZIndex = 7
	local glow = UIKit.new("Frame", {
		Name = "PopGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = GLOW_GOLD,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
	}, refs.Pages.Rebirth)
	UIKit.corner(glow, 18)
	UIKit.stroke(glow, 6, rgb(255, 244, 170), 0.25)
	popButton(refs.Rebirth, PopTheme.Gray, "Rebirth")
	refs.Rebirth.FontFace = PopTheme.Heavy
	local forgeStar = UIKit.new("ImageLabel", {
		Name = "PopStar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 6,
	}, refs.Pages.Rebirth)
	IconAssets.apply(forgeStar, "star_token")
	forgeStar:SetAttribute("Icon", "star_token")
	-- the star shop's cards
	for i, card in refs.Cards do
		popCard(card.Frame, RebirthView.PopCards[(i - 1) % #RebirthView.PopCards + 1])
		popText(card.Name)
		popText(card.Text)
		popEdge(card.Level)
		card.Level.FontFace = PopTheme.Heavy
		popButton(card.Buy, PopTheme.Gray)
		local pick = card.Pick
		if pick then
			popButton(pick, PopTheme.Gray)
		end
	end
	-- the blasters' cards: the live gun in a light burst on its glow colour
	for _, card in refs.Weapons do
		local star = StarBlasterData.get(card.Id)
		local glowColor = if star then star.Glow else rgb(160, 168, 255)
		popCard(
			card.Frame,
			{ Top = glowColor:Lerp(Color3.new(1, 1, 1), 0.25), Bottom = glowColor:Lerp(Color3.new(0, 0, 0), 0.4), Edge = PopTheme.Outline }
		)
		local picture = card.Picture
		picture.BackgroundTransparency = 1
		picture.ZIndex = 4
		for _, child in picture:GetChildren() do
			if child:IsA("UIStroke") then
				child:Destroy()
			end
		end
		-- (a sibling under the picture: layoutWeapons puts it at the picture's centre)
		local burst = UIKit.new("Frame", {
			Name = "Burst",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 0),
			ZIndex = 1,
		}, card.Frame)
		local rays = Pop.fx(burst, "fx_rays", {
			Name = "Rays",
			AnchorPoint = Vector2.new(0.5, 0.5),
			ImageTransparency = 0.4,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(300, 300),
			ZIndex = 1,
		})
		if not rays then
			Pop.rays(burst, UDim2.fromScale(0.5, 0.5), 10, 150, 0.65, 1)
		end
		local glowDisc = Pop.fx(burst, "fx_glow", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			ImageTransparency = 0.35,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(130, 130),
			ZIndex = 1,
		})
		if not glowDisc then
			local disc = UIKit.new("Frame", {
				Name = "Glow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.75,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(84, 84),
				ZIndex = 1,
			}, burst)
			UIKit.corner(disc, 999)
		end
		popText(card.Name)
		popText(card.Text)
		popButton(card.Main, PopTheme.Gray, "Weapon")
		popButton(card.Robux, PopTheme.Price)
	end
	for _, page in { refs.Pages.Shop, refs.Pages.Blasters } do
		local scroll = page :: any
		scroll.ScrollBarImageColor3 = rgb(220, 224, 236)
	end
end

-- Paints every button's face from its state colour and the texts that change colour.
local function popRestyle(refs: Refs)
	local buttons = RebirthView.buttons(refs)
	for _, card in refs.Weapons do
		if not card.Robuxed then
			table.insert(buttons, card.Robux)
		end
	end
	for _, button in buttons do
		local holder = MenuPanel.holderOf(button)
		if holder:GetAttribute("Pop") then
			holder.BackgroundColor3 = Color3.new(1, 1, 1)
			Pop.repaint(holder, popPaintOf(button))
			button.TextColor3 = PopTheme.Ink
			local tab = holder:GetAttribute("PopRole") == "Tab"
			button.TextTransparency = if tab and button.BackgroundColor3 == RebirthView.Colors.Off then 0.25 else 0
			popEdge(button)
		end
	end
	for _, card in refs.Weapons do
		syncRobux(card.Robux)
	end
	refs.Need.TextColor3 = if refs.Ready then rgb(255, 250, 200) else PopTheme.Ink
	-- the big gold REBIRTH! glows while it is ready (not while it asks SURE?)
	local glow = refs.Pages.Rebirth:FindFirstChild("PopGlow") :: Frame?
	if glow then
		glow.Visible = refs.Ready and not refs.Confirm and MenuPanel.holderOf(refs.Rebirth).Visible
	end
end

-- Places the Pop pieces after the layout (the band, the title's shadow, the glow).
local function popLayout(refs: Refs)
	local frame = refs.Frame
	local m = if refs.Compact then MenuPanel.Metrics.Compact else MenuPanel.Metrics.Normal
	local band = frame.Panel:FindFirstChild("PopHeader") :: Frame?
	if band then
		band.Size = UDim2.new(1, -8, 0, m.Header - 8)
	end
	popEdge(frame.Title)
	local shade = frame.Panel:FindFirstChild("TitleShadow")
	if shade and shade:IsA("TextLabel") then
		shade.Position = frame.Title.Position + UDim2.fromOffset(0, 4)
		shade.Size = frame.Title.Size
		shade.TextSize = frame.Title.TextSize
	end
	frame.Close.TextSize = math.floor(m.Close * 0.6)
	popEdge(frame.Close)
	-- the big REBIRTH! (a little taller on PC; the requirement line gives the room)
	local metrics = RebirthView.metrics(refs.Compact)
	local holder = MenuPanel.holderOf(refs.Rebirth)
	local tall = math.max(metrics.Button, 60)
	local grow = math.max(0, tall - holder.Size.Y.Offset)
	holder.Position = UDim2.fromOffset(holder.Position.X.Offset, holder.Position.Y.Offset - grow)
	holder.Size = UDim2.fromOffset(holder.Size.X.Offset, holder.Size.Y.Offset + grow)
	for _, label in { refs.Need, refs.Message } do
		-- (6 more: clear of the button's glow)
		label.Size = UDim2.fromOffset(label.Size.X.Offset, math.max(0, label.Size.Y.Offset - grow - 6))
	end
	refs.Rebirth.TextSize = math.floor(tall * 0.62)
	-- the Forge Star (the star_token picture, once uploaded) in the YOU GET card's
	-- free room over the requirement line; without it the line stays in the middle
	local star = refs.Pages.Rebirth:FindFirstChild("PopStar") :: ImageLabel?
	if star then
		local need = refs.Need
		local room = need.Size.Y.Offset - 56
		local size = math.min(120, room)
		local shows = IconAssets.shows("star_token") and size >= 48
		star.Visible = shows
		star.Size = UDim2.fromOffset(size, size)
		star.Position = UDim2.fromOffset(need.Position.X.Offset + need.Size.X.Offset / 2, need.Position.Y.Offset + 4 + size / 2)
		for _, label in { refs.Need, refs.Message } do
			label.TextYAlignment = if shows then Enum.TextYAlignment.Bottom else Enum.TextYAlignment.Center
		end
	end
	local glow = refs.Pages.Rebirth:FindFirstChild("PopGlow") :: Frame?
	if glow then
		glow.Position =
			UDim2.fromOffset(holder.Position.X.Offset + holder.Size.X.Offset / 2, holder.Position.Y.Offset + holder.Size.Y.Offset / 2)
		glow.Size = UDim2.fromOffset(holder.Size.X.Offset + 16, holder.Size.Y.Offset + 16)
	end
	for _, column in refs.Columns do
		popEdge(column.Chip)
		for _, row in column.Rows do
			popEdge(row)
		end
	end
	for _, label in { refs.Need, refs.Message, refs.Stars } do
		popEdge(label)
	end
	for _, card in refs.Cards do
		for _, label in { card.Name, card.Text, card.Level } do
			popEdge(label)
		end
	end
	popRestyle(refs)
end

function RebirthView.build(): Refs
	local title, subtitle = "STAR FORGE", "Rebirth: start over with your factory and earn Forge Stars"
	-- (the light UI: MenuPanel's Pop frame without the LightSkin, which would recolour the Pop faces)
	local frame = MenuPanel.build("TerraForgeRebirth", title, subtitle, nil, UIConfig.lightUI())
	local body = frame.Body
	local tabs: { [string]: TextButton } = {}
	tabs.Rebirth = chunky(body, "REBIRTH", RebirthView.Colors.Rebirth, RebirthView.Colors.RebirthDark, "TabRebirth")
	tabs.Shop = chunky(body, "STAR SHOP", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "TabShop")
	tabs.Blasters = chunky(body, "BLASTERS", RebirthView.Colors.Off, RebirthView.Colors.OffDark, "TabBlasters")
	local stars = UIKit.label(body, RebirthView.starsLabel(0), 24, {
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
	local dotColors: { [string]: Color3 } = { Lose = RebirthView.Colors.Lose, Keep = RebirthView.Colors.Keep, Get = RebirthView.Colors.Get }
	for id: string, column: Column in columns do
		for i = 1, #lists[id] do
			local row = UIKit.label(column.Frame, "", 18, {
				Name = "Row" .. i,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			-- the row's bullet: a dot in the column's colour in the DotRoom left of the text
			local dot = UIKit.new("Frame", {
				Name = "Dot",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, -RebirthView.DotRoom / 2, 0.5, 0),
				Size = UDim2.fromOffset(RebirthView.Dot, RebirthView.Dot),
				BackgroundColor3 = dotColors[id] or Theme.TextDim,
				BorderSizePixel = 0,
			}, row)
			UIKit.corner(dot, RebirthView.Dot / 2)
			table.insert(column.Rows, row)
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

	local refs: Refs = {
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
	if isPop(refs) then
		popSkin(refs)
		popRestyle(refs)
	end
	return refs
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
	-- "12 STARS" in the star room (smaller rather than cut off)
	TechShopView.fitText(refs.Stars, refs.Stars.Size.X.Offset, m.Tab, m.Text + 8, m.Text - 4)
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
		-- the rows' text starts DotRoom right of the column's padding (the bullet dot is there)
		local rowX = 12 + RebirthView.DotRoom
		local rowW = math.floor(colW - rowX - 12) -- (an Offset is whole: fit to what the label gets)
		for i, row in column.Rows do
			rect(row, rowX, 8 + m.Chip + 8 + (i - 1) * m.Row, rowW, m.Row)
			TechShopView.fitText(row, rowW, m.Row, m.Text, m.Text - 6)
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
	-- (no icon: the name and the text start at the card's left padding)
	local pad = 12
	for _, card in refs.Cards do
		rect(card.Name, pad, 8, cardW - pad - 70, 28)
		TechShopView.fitText(card.Name, cardW - pad - 70, 28, m.Text + 2, m.Text - 4)
		rect(card.Level, cardW - 70, 8, 62, 28)
		card.Level.TextSize = m.Text
		rect(card.Text, pad, 38, cardW - pad - 8, m.Card - 38 - m.Button - 14)
		TechShopView.fitText(card.Text, cardW - pad - 8, m.Card - 38 - m.Button - 14, m.Text - 2, m.Text - 6)
		place(card.Buy, cardW - 190, m.Card - m.Button - 8, 182, m.Button)
		-- "BUY 12 STARS" (it shrinks a little before it would leave the button)
		TechShopView.fitText(card.Buy :: any, 182 - 12, m.Button - 6, m.Text + 2, m.Text - 6)
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
	local lists = RebirthView.lists(info.Perks, info.Start)
	lists.Get[1] = if info.Ready then `{info.StarsNow} Forge Stars` else `Stars from LV {RebirthConfig.MinBlaster}`
	lists.Get[2] = `Rebirth #{info.Count + 1}`
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
	refs.Stars.Text = RebirthView.starsLabel(info.Stars)
	if refs.Laid then
		local m = RebirthView.metrics(refs.Compact)
		TechShopView.fitText(refs.Stars, refs.Stars.Size.X.Offset, refs.Stars.Size.Y.Offset, m.Text + 8, m.Text - 4)
	end
	refs.Tabs.Shop.Text = "STAR SHOP"
	for _, card in refs.Cards do
		local level, buy, affordable = RebirthView.cardText(info.Perks, info.Stars, card.Id, info.Start)
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
		-- a plain text star in gold (U+2605 BLACK STAR, not the emoji)
		local star = UIKit.label(gui, "★", rng:int(26, 44), {
			Name = "Star" .. i,
			TextColor3 = RebirthView.Colors.Star,
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

---------------------------------------------------------------- the Pop look: after every state change

local plainLayout = RebirthView.layout
RebirthView.layout = function(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	plainLayout(refs, compact, maxWidth, maxHeight)
	if isPop(refs) then
		popLayout(refs)
	end
end

local plainLayoutWeapons = RebirthView.layoutWeapons
RebirthView.layoutWeapons = function(refs: Refs)
	plainLayoutWeapons(refs)
	if isPop(refs) then
		for _, card in refs.Weapons do
			local picture = card.Picture
			local burst = card.Frame:FindFirstChild("Burst") :: Frame?
			if burst then
				burst.Position = UDim2.fromOffset(
					picture.Position.X.Offset + picture.Size.X.Offset / 2,
					picture.Position.Y.Offset + picture.Size.Y.Offset / 2
				)
			end
			local labels: { GuiObject } = { card.Name, card.Text, card.Main, card.Robux }
			for _, label in labels do
				popEdge(label)
			end
		end
	end
end

local plainSetTab = RebirthView.setTab
RebirthView.setTab = function(refs: Refs, tab: string)
	plainSetTab(refs, tab)
	if isPop(refs) then
		popRestyle(refs)
	end
end

local plainSetConfirm = RebirthView.setConfirm
RebirthView.setConfirm = function(refs: Refs, on: boolean)
	plainSetConfirm(refs, on)
	if isPop(refs) then
		popRestyle(refs)
	end
end

local plainSetInfo = RebirthView.setInfo
RebirthView.setInfo = function(refs: Refs, info: Info)
	plainSetInfo(refs, info)
	if isPop(refs) then
		popRestyle(refs)
	end
end

local plainSetWeapons = RebirthView.setWeapons
RebirthView.setWeapons = function(refs: Refs, info: Info)
	plainSetWeapons(refs, info)
	if isPop(refs) then
		popRestyle(refs)
	end
end

return RebirthView
