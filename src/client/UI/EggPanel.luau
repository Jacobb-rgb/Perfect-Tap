--[[
	EggPanel: the clean panel over the egg you stand at in the EGGS temple
	(owner 2026-10-28, two pictures of other egg games: "what we have now I
	almost don't like at all; I want it like this, it feels cleaner"). We
	copy the look and the flow, never their pictures: our golems, our coin.

	         Stone Egg                    the egg's name, big, white, a dark edge
	  +----------------------------+
	  | (coin) 2,500     [Auto  G] |      the price chip, Auto (coin eggs only)
	  | [pic ] [pic ] [pic ] ...   |      a card per golem: its rarity's paint,
	  | [ 45%] [ 30%] [ 20%]       |      its live 3D picture, its exact chance
	  | Pebble Copper Coal  ...    |      and its NAME (a silhouette's too)
	  | [Open 1 E][Open 3 R][Open 10 X] | the opens with their prices (owner
	  +----------------------------+      round 2: "add opening by 10 etc.")

	- A BillboardGui (PlayerGui, AlwaysOnTop) its bottom edge at the egg's
	  top; one alive at a time (EggPanelController moves it to the nearest
	  egg). Laid out in design units (720 high, like every window) and scaled
	  by the HUD's scale: at the phone floor (0.62) the touch layout's Auto
	  and opens are 72 units, 44 pt. On touch the layout is compact (no head
	  row: the opens show the price; Auto as a fourth button in the opens'
	  row) and the panel FLOATS beside the egg on the screen (floatAt): its
	  opens' row out of the thumbstick's start zone and off the touch
	  buttons, the HUD's buttons, the boost corner and the tutorial bubble
	  (Hard), its cards visible (Odds), inside the notch-safe frame, so a
	  thumb that starts a walk never lands on a buy and no odd hides under
	  the HUD. On the smallest phones (568 x 320) the narrow layout puts
	  the row on top, right-aligned.
	- Cards: CapsuleConfig.odds order (the server's roll table, rarer last),
	  the chance in at most three significant digits and three decimals
	  ("45%", "20.5%", "0.28%"); with Triple Lucky on, its odds and an "x3"
	  on every golem it triples. Every card names its golem: the eggs are
	  paid random items (coins can be bought), so each chance belongs to a
	  golem the player can tell before buying. A golem the player has none
	  of is a black silhouette on a coin egg, its name under it all the same
	  (silhouettes: the inventory, State Golems Owned + Pending, is what we
	  know; a Robux egg always shows its golems in colour).
	- The pictures: ViewportFrames, one per card slot, made once; the
	  controller lends each slot a cached golem model (setLines' `modelFor`).
	  In the Lune previews the "Picture" ImageLabel's Icon attribute stands in.
	- Fade: every transparency in the panel is listed once at build
	  (refs.Fades); setFade(alpha) lerps them all toward 1 (no allocation).
	- Open 1 / 3 / 10 (CapsuleConfig.Counts): the capsule window's own buys
	  (opens(): CapsuleView.cards' Buys), green with the coin price, lime
	  with the Robux price, grey when they can't be bought (no coins, no
	  room, a Robux product not live yet: the click still says why); a key
	  badge on each (E / R / X on a keyboard, the main prompt's glyph on
	  Open 1 and the focus button's on Open 3 / 10 for a gamepad, none on
	  touch), shown only where the keys work: within the "Buy Egg!"
	  prompt's reach (inReach).
	- The "even cooler" parts the controller animates (never with Reduce
	  motion): each card's PopScale (they pop in one after another), a ray
	  burst behind Epic+ golems (Rays), a soft glow behind Legendary+ cards
	  (Glow, under the card) and the price chip's red Alert (two flashes,
	  AlertFlashes in AlertSeconds: under 3 a second).

	Pure: only Instance creation and math (the Lune specs and previews run it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local PopTheme = require(Shared.Config.PopTheme)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local BoostView = require(script.Parent.BoostView)

local EggPanel = {}

EggPanel.ShowRange = 13 -- studs from an egg's centre: its panel shows (the nearest egg only)
EggPanel.HideRange = 15 -- past this it fades out (a little hysteresis: no flicker at the edge)
EggPanel.SwitchMargin = 1.5 -- another egg takes the panel when it is this much nearer
EggPanel.PromptDistance = 8 -- the "Buy Egg!" prompt's MaxActivationDistance (the panel shows first)
EggPanel.Lift = 0.4 -- studs between the egg's top and the panel's bottom edge
EggPanel.MaxColumns = 7
EggPanel.PhoneScale = 0.62 -- HudController.uiScale's floor (phones)
EggPanel.MinTouch = 44 -- points
-- a coin egg shows the golems the player has none of as black silhouettes
EggPanel.Silhouettes = true
-- THE SWITCH for the eggs' prompts (the owner hasn't picked yet: "a big E" in one
-- chat, "normal Roblox" in the other): true, they draw their own big round E
-- (UI/EggPrompt; ProximityPrompt Style Custom on these prompts only:
-- tests/PromptKeys.spec.luau allows exactly this one besides UIConfig.CustomPrompts);
-- false, Roblox's stock prompts (Buy Egg! and Auto drawn by Roblox, as in round 1).
EggPanel.BigE = true
-- the keyboard keys of the opens (E is the prompt's; R and X are bound only in
-- build mode, on the plot, so they are free at the temple; see EggPanelController)
EggPanel.OpenKeys = { [1] = "E", [3] = "R", [10] = "X" } :: { [number]: string }
-- the motion (EggPanelController; none of it with Reduce motion)
EggPanel.CardStagger = 0.035 -- seconds between two cards popping in
EggPanel.RaysFrom = 4 -- Rarity Order: Epic and up get a turning ray burst
EggPanel.GlowFrom = 5 -- Legendary and up: a soft glow behind the card, the golem bobs
EggPanel.RaySpeed = 8 -- seconds per turn of a ray burst
EggPanel.GlowPeriod = 1.8 -- seconds for one glow pulse (in and out)
EggPanel.AlertFlashes = 2 -- the price chip flashes red this many times...
EggPanel.AlertSeconds = 0.8 -- ...in this long (2.5 a second: under the 3 a second limit)
-- the most golems an egg of the stall holds (the card slots made at build)
EggPanel.MaxCards = 1
for _, capsule in CapsuleConfig.Stall do
	local n = 0
	for _ in capsule.Odds do
		n += 1
	end
	EggPanel.MaxCards = math.max(EggPanel.MaxCards, n)
end

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = PopTheme.Outline
-- the panel's white face and the price chip's (a clean white, a soft cool shade at the foot)
local PANEL_PAINT: Pop.Paint = { Top = rgb(255, 255, 255), Bottom = rgb(236, 240, 247), Edge = INK }
local CHIP_PAINT: Pop.Paint = { Top = rgb(250, 251, 254), Bottom = rgb(226, 232, 242), Edge = INK }
local LUCKY_GOLD = rgb(255, 214, 64)
local SHORT = rgb(255, 120, 120) -- a price the player can't pay yet
local CARD_CORNER = 10
local PANEL_CORNER = 16

---------------------------------------------------------------- pure helpers

local function num(v: any): number
	return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else 0
end

local function trim(text: string): string
	if text:find("%.") then
		text = text:gsub("0+$", "")
		text = text:gsub("%.$", "")
	end
	return text
end

--[[
	A card's chance: three significant digits at most and three decimals at
	most, trailing zeros cut: 0.45 -> "45%", 0.205 -> "20.5%", 0.0255 ->
	"2.55%", 0.0028 -> "0.28%", 0.0003 -> "0.03%". Never "0%" for a golem
	that can come out.
]]
function EggPanel.chanceText(chance: number): string
	local p = num(chance) * 100
	if p <= 0 then
		return "0%"
	end
	local decimals = if p >= 10 then 1 elseif p >= 1 then 2 else 3
	local text = trim(string.format(`%.{decimals}f`, p))
	if text == "0" then
		return "<0.001%"
	end
	return text .. "%"
end

-- The price on the chip: "2,500", "750K", "1.13B" (the coin beside it says it is money).
function EggPanel.priceText(price: number): string
	return Format.short(math.max(0, math.floor(num(price) + 0.5)))
end

-- Auto opens coin eggs only, never a Robux egg (or an unknown one).
function EggPanel.autoAllowed(capsuleId: string): boolean
	local capsule = CapsuleConfig.ById[capsuleId]
	return capsule ~= nil and capsule.Currency == "Coins"
end

-- Does this egg show the golems the player has none of as silhouettes? Coin
-- eggs only: a Robux egg always shows exactly what can come out of it. (A
-- silhouette keeps its golem's name under it: coin eggs are paid random items too.)
function EggPanel.silhouettes(capsuleId: string): boolean
	local capsule = CapsuleConfig.ById[capsuleId]
	return EggPanel.Silhouettes and capsule ~= nil and capsule.Currency == "Coins"
end

-- The golem kinds the player has (State Golems: Owned, and Pending paid golems waiting for room).
function EggPanel.known(state: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local golems = if type(state) == "table" then state.Golems else nil
	if type(golems) ~= "table" then
		return out
	end
	for _, field in { "Owned", "Pending" } do
		local list = golems[field]
		if type(list) == "table" then
			for _, entry in list do
				if type(entry) == "table" and type(entry.Kind) == "string" then
					out[entry.Kind] = true
				end
			end
		end
	end
	return out
end

export type Line = {
	Golem: string,
	Name: string, -- the golem's name (on its card under the picture: a silhouette names its golem)
	Rarity: string,
	Chance: number,
	Text: string,
	Lucky: boolean, -- tripled by Triple Lucky (only while it runs)
	Silhouette: boolean,
}

--[[
	The cards of an egg: CapsuleConfig.odds(capsuleId, lucky) line by line
	(the table the server rolls, in its order), each with its chance text,
	whether Triple Lucky triples it and whether it shows as a silhouette
	(`known`: EggPanel.known).
]]
function EggPanel.lines(capsuleId: string, lucky: boolean, known: { [string]: boolean }): { Line }
	local capsule = CapsuleConfig.ById[capsuleId]
	local lines: { Line } = {}
	if not capsule then
		return lines
	end
	local from = Rarity.ById[capsule.LuckyFrom].Order
	local shadows = EggPanel.silhouettes(capsuleId)
	for _, line in CapsuleConfig.odds(capsuleId, lucky) do
		local golem = GolemConfig.ById[line.Golem]
		if golem then
			table.insert(lines, {
				Golem = line.Golem,
				Name = golem.Name,
				Rarity = golem.Rarity,
				Chance = line.Chance,
				Text = EggPanel.chanceText(line.Chance),
				Lucky = lucky and GolemConfig.order(line.Golem) >= from,
				Silhouette = shadows and not known[line.Golem],
			})
		end
	end
	return lines
end

export type Spot = { Id: string, Center: Vector3 }

--[[
	The egg whose panel shows for a player at `position`: the nearest one
	within ShowRange; the one showing now (`current`) keeps it up to
	HideRange and until another is SwitchMargin nearer. nil: none.
]]
function EggPanel.nearest(spots: { Spot }, position: Vector3, current: string?): string?
	local best: string? = nil
	local bestDistance = math.huge
	local currentDistance = math.huge
	for _, spot in spots do
		local d = (spot.Center - position).Magnitude
		if spot.Id == current then
			currentDistance = d
		end
		if d < bestDistance then
			best, bestDistance = spot.Id, d
		end
	end
	if current and currentDistance <= EggPanel.HideRange and bestDistance > currentDistance - EggPanel.SwitchMargin then
		return current
	end
	if best and bestDistance <= EggPanel.ShowRange then
		return best
	end
	return nil
end

--[[
	Is a player at `position` within the "Buy Egg!" prompt's reach (its
	point `point`, MaxActivationDistance PromptDistance)? Only there do the
	keys open (E / Y by the prompt, R / X and the gamepad's focus here) and
	their badges show: the panel itself shows from further away.
]]
function EggPanel.inReach(position: Vector3, point: Vector3): boolean
	return (position - point).Magnitude <= EggPanel.PromptDistance
end

-- May the price chip flash red again (`last`: when it last did)? Not while it flashes: mashing stays at 2.5 a second.
function EggPanel.alertOk(last: number, now: number): boolean
	return now - last >= EggPanel.AlertSeconds
end

--[[
	Do the cards wait (the golems the player has, their silhouettes) while
	an opening goes on (CapsuleController.openingState)? While an open waits
	for its answer or the egg hatches: a card that lights up there would
	tell the new golem before the reveal. On the end screen the golem is
	out: its card may light up.
]]
function EggPanel.holdCards(opening: string): boolean
	return opening == "Waiting" or opening == "Playing"
end

--[[
	The capsule id of a temple egg (a Model whose Capsule attribute names a
	capsule of the stall: GolemBuilder.capsule sets it), or nil: not a
	limited edition's capsule and not a podium-only egg (the SKY EGG keeps
	its own podium prompt and board, display-only here until the owner says).
]]
function EggPanel.eggId(instance: Instance): string?
	if not instance:IsA("Model") then
		return nil
	end
	local id = instance:GetAttribute("Capsule")
	local capsule = if type(id) == "string" then CapsuleConfig.ById[id] else nil
	if not capsule or capsule.Limited ~= nil or capsule.Podium then
		return nil
	end
	return capsule.Id
end

-- The temple's eggs in `stall` (the CapsuleStall model), one per capsule id.
function EggPanel.eggsIn(stall: Instance): { [string]: Model }
	local out: { [string]: Model } = {}
	for _, d in stall:GetDescendants() do
		local id = EggPanel.eggId(d)
		if id and not out[id] then
			out[id] = d :: Model
		end
	end
	return out
end

-- The low and high corners of a model's visible parts' box.
local function box(model: Instance): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf = part.CFrame
			local h = part.Size * 0.5
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cf * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end
				end
			end
		end
	end
	return lo, hi
end

--[[
	An egg's spot from its model: its centre, the height of its top (the
	panel's bottom edge sits Lift above it), where its prompts go (in front
	of the shell toward `front`, the stall's front, at its middle), the
	height of its foot (the light ring on the podium) and its half width.
]]
function EggPanel.spotOf(model: Instance, front: Vector3): (Vector3, number, Vector3, number, number)
	local lo, hi = box(model)
	if lo.X > hi.X then
		local at = if model:IsA("Model") then model:GetPivot().Position else Vector3.zero
		return at, at.Y + 2, at, at.Y - 2, 1
	end
	local center = (lo + hi) * 0.5
	local flat = Vector3.new(front.X, 0, front.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local half = math.max(hi.X - lo.X, hi.Z - lo.Z) * 0.5
	return center, hi.Y, center + dir * (half + 0.5), lo.Y, half
end

--[[
	The object text of an egg's "Buy Egg!" prompt from its quote (the
	capsule window's card for one egg: CapsuleView.Buy): "$2,500", "R$ 49",
	or "Coming soon" while a Robux product isn't live.
]]
function EggPanel.promptText(robux: boolean, price: number?, priceText: string, live: boolean): string
	if robux then
		return if live then priceText else "Coming soon"
	end
	return "$" .. EggPanel.priceText(price or 0)
end

---------------------------------------------------------------- layout

-- A rectangle on the screen (px): its top-left and bottom-right corners.
export type Box = { Min: Vector2, Max: Vector2 }

export type Layout = {
	Touch: boolean,
	Count: number,
	Columns: number,
	Rows: number,
	Card: number, -- a card's width (room for the golem's longest word, "Moonstone", at NameSize)
	CardH: number, -- its height (the picture, its chance and the name's two lines under it)
	Gap: number,
	Pad: number,
	Head: number, -- the row of the price chip and Auto (PC; none on touch: the opens show the price)
	HeadGap: number,
	Title: number, -- the egg's name above the white panel
	TitleSize: number,
	ChanceSize: number,
	NameSize: number, -- the golem's name on its card (8 pt at least on a phone, 18 px on a TV)
	NameH: number, -- the name's two lines at the card's foot
	LuckySize: number, -- the "x3" on a card Triple Lucky triples
	Chip: number, -- the price chip's height
	Toggle: Vector2, -- Auto
	Open: Vector2, -- one Open 1 / 3 / 10 button
	OpenGap: number, -- between them (and above their row)
	OpenY: number, -- their row's top in the white panel
	RowX: number, -- its left end (narrow: the row keeps right, out of the thumbstick's zone)
	RowFirst: boolean, -- narrow phones: the opens' row over the cards (it stays clear of the touch buttons)
	AutoInRow: boolean, -- Auto is the opens' row's last button (touch), not in the head row
	Beside: boolean, -- touch: the panel floats beside the egg, kept clear of the thumbstick (floatAt)
	TenFoot: boolean, -- a TV (bigger names and marks: 18 px at 1080p)
	Width: number,
	Body: number, -- the white panel's height
	Height: number, -- Title + Body (the billboard, in design units)
}

-- Columns for `count` cards: one row up to 5, two rows up to 10, then MaxColumns a row.
function EggPanel.columns(count: number): number
	local n = math.max(1, math.floor(count))
	if n <= 5 then
		return n
	elseif n <= 10 then
		return math.ceil(n / 2)
	end
	return EggPanel.MaxColumns
end

export type LayoutOptions = {
	TenFoot: boolean?, -- a TV (GuiService:IsTenFootInterface)
	Narrow: boolean?, -- touch: the panel is wider than the screen right of the thumbstick's zone
}

--[[
	The panel's sizes for `count` cards (design units). Every card names its
	golem under the picture (two lines; the longest name, "Heartstone
	Colossus", wraps after its first word; its longest word, "Moonstone",
	is 77 units at 13 in the round font: the cards are 80 wide). `touch`:
	phones and tablets: compact, so it fits right of the thumbstick between
	the top bar and the touch buttons (floatAt): no head row (the opens
	show the price), a low title, the opens (and Auto, the row's last
	button when the egg has it: `auto`, default true) 72 units tall, 44 pt
	at the phone scale (0.62), the names 13 units (8 pt). PC: the price
	chip and Auto in a head row, the panel over the egg. `opts.TenFoot`: a
	TV, names 15 units and a bigger "x3" (18 px and more at 1080p, the
	HUD's 1.25), the cards wider for them. `opts.Narrow` (touch, a phone
	too narrow for the panel right of the thumbstick, 568 x 320): the opens'
	row on top, right-aligned and as short as the buttons allow, so it
	stays out of the zone and over the touch buttons; the cards under it.
]]
function EggPanel.layout(count: number, touch: boolean, auto: boolean?, opts: LayoutOptions?): Layout
	local tenFoot = not touch and opts ~= nil and opts.TenFoot == true
	local narrow = touch and opts ~= nil and opts.Narrow == true
	local columns = EggPanel.columns(count)
	local rows = math.max(1, math.ceil(math.max(1, count) / columns))
	local nameSize = if tenFoot then 15 else 13 -- (8 pt at the phone scale; 18.75 px on a 1080p TV)
	local card = if tenFoot then 92 else 80 -- ("Moonstone" is 89 units at 15)
	local cardH = if tenFoot then 92 elseif touch then 70 else 80
	local gap = if touch then 4 else 6
	local pad = if touch then 8 else 12
	local head = if touch then 0 else 40
	local headGap = if touch then 0 else 10
	local chip = if touch then 40 else 34
	local openH = if touch then 72 else 56 -- (72 units: 44 pt at the phone scale)
	local openGap = if touch then 6 else 8
	local inRow = touch and auto ~= false
	local slots = #CapsuleConfig.Counts + (if inRow then 1 else 0)
	local grid = pad * 2 + columns * card + (columns - 1) * gap
	-- the head row needs the chip and Auto (PC); the opens 110 (touch) / 136 (PC: the key badge too) units each
	local headMin = if touch then 0 else pad * 2 + 160 + (if inRow then 0 else 12 + 112)
	local openMin = if touch then 110 else 136
	local rowMin = slots * openMin + (slots - 1) * openGap
	local width = math.max(grid, headMin, pad * 2 + rowMin)
	local openW = if narrow then openMin else math.floor((width - pad * 2 - (slots - 1) * openGap) / slots)
	local rowWidth = slots * openW + (slots - 1) * openGap
	local toggle = if inRow then Vector2.new(openW, openH) else Vector2.new(112, 36)
	local cardsH = rows * cardH + (rows - 1) * gap
	local openY, body
	if narrow then
		openY = pad
		body = pad + openH + openGap + cardsH + pad
	else
		openY = pad + head + headGap + cardsH + openGap + (if touch then 0 else 2)
		body = openY + openH + pad
	end
	local title = if touch then 30 else 50
	return {
		Touch = touch,
		Count = count,
		Columns = columns,
		Rows = rows,
		Card = card,
		CardH = cardH,
		Gap = gap,
		Pad = pad,
		Head = head,
		HeadGap = headGap,
		Title = title,
		TitleSize = if touch then 30 else 40,
		ChanceSize = if touch then 19 else 21,
		NameSize = nameSize,
		NameH = nameSize * 2 + 2,
		LuckySize = if tenFoot then 20 else 14,
		Chip = chip,
		Toggle = toggle,
		Open = Vector2.new(openW, openH),
		OpenGap = openGap,
		OpenY = openY,
		RowX = if narrow then width - pad - rowWidth else pad,
		RowFirst = narrow,
		AutoInRow = inRow,
		Beside = touch,
		TenFoot = tenFoot,
		Width = width,
		Body = body,
		Height = title + body,
	}
end

-- Where Open button `i` (1-based, CapsuleConfig.Counts order) sits in the white panel (its top-left).
function EggPanel.openAt(l: Layout, i: number): Vector2
	return Vector2.new(l.RowX + (i - 1) * (l.Open.X + l.OpenGap), l.OpenY)
end

-- Where card `i` (1-based) sits in the white panel (its top-left, design units).
function EggPanel.cardAt(l: Layout, i: number): Vector2
	local col = (i - 1) % l.Columns
	local row = (i - 1) // l.Columns
	-- a short last row is centred under the full ones
	local inRow = if row == l.Rows - 1 then l.Count - row * l.Columns else l.Columns
	local rowWidth = inRow * l.Card + (inRow - 1) * l.Gap
	local x0 = (l.Width - rowWidth) / 2
	local top = if l.RowFirst then l.Pad + l.Open.Y + l.OpenGap else l.Pad + l.Head + l.HeadGap
	return Vector2.new(x0 + col * (l.Card + l.Gap), top + row * (l.CardH + l.Gap))
end

-- The opens' row (with Auto) on the billboard, from its top-left, at `scale` (px): what must stay pressable.
function EggPanel.rowBox(l: Layout, scale: number): Box
	local slots = #CapsuleConfig.Counts + (if l.AutoInRow then 1 else 0)
	local w = slots * l.Open.X + (slots - 1) * l.OpenGap
	local y = l.Title + l.OpenY
	return { Min = Vector2.new(l.RowX, y) * scale, Max = Vector2.new(l.RowX + w, y + l.Open.Y) * scale }
end

-- The cards (their pictures, chances and names) on the billboard, from its top-left, at `scale` (px): the odds.
function EggPanel.oddsBox(l: Layout, scale: number): Box
	local first = EggPanel.cardAt(l, 1)
	local cardsW = l.Columns * l.Card + (l.Columns - 1) * l.Gap
	local x = (l.Width - cardsW) / 2
	local y = l.Title + first.Y
	return {
		Min = Vector2.new(x, y) * scale,
		Max = Vector2.new(x + cardsW, y + l.Rows * l.CardH + (l.Rows - 1) * l.Gap) * scale,
	}
end

---------------------------------------------------------------- builder

export type Fade = { Target: Instance, Property: string, Base: number }

export type Card = {
	Frame: Frame,
	PopScale: UIScale, -- the pop-in (EggPanelController)
	Picture: ImageLabel,
	View: ViewportFrame,
	Camera: Camera,
	Rays: Frame, -- a ray burst behind the golem (Epic and up)
	Glow: Frame, -- a soft glow under the card (Legendary and up; not in the fade list)
	Chance: TextLabel,
	Name: TextLabel, -- the golem's name at the card's foot (under the picture, a silhouette's too)
	Lucky: TextLabel,
	Kind: string?, -- the golem whose model the card's view holds (nil: none, setLines lends one)
	Order: number, -- the golem's Rarity Order (0: none)
}

-- One Open 1 / 3 / 10 button.
export type Open = {
	Count: number,
	Button: TextButton,
	Label: TextLabel,
	Coin: Frame,
	Amount: TextLabel,
	Key: Frame,
	KeyText: TextLabel,
	Glyph: ImageLabel,
}

-- What an Open button shows (opens()).
export type OpenSpec = {
	Count: number,
	Robux: boolean,
	Price: string, -- "7,500", "R$ 129", "Coming soon"
	Enabled: boolean, -- can be bought now (else grey; a click still answers why)
	Reason: string?,
}

export type Refs = {
	Gui: BillboardGui,
	Root: Frame,
	Scale: UIScale,
	Title: TextLabel,
	Body: Frame,
	Chip: Frame,
	Coin: Frame,
	Price: TextLabel,
	Alert: Frame, -- the chip's red flash (not in the fade list)
	LuckyTag: Frame,
	Toggle: TextButton,
	ToggleLabel: TextLabel,
	Key: Frame,
	KeyText: TextLabel,
	Glyph: ImageLabel,
	Cards: { Card },
	Opens: { Open },
	Fades: { Fade },
	Layout: Layout?,
	Egg: string?,
}

local function newCard(body: Frame, i: number): Card
	-- (the glow first: a sibling under the card, it rides along in apply())
	local glow = UIKit.new("Frame", {
		Name = "Glow" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(78, 78),
		Visible = false,
		ZIndex = 2,
	}, body) :: Frame
	glow:SetAttribute("NoFade", true)
	UIKit.corner(glow, CARD_CORNER + 6)
	local frame = UIKit.new("Frame", {
		Name = "Card" .. i,
		ClipsDescendants = true, -- (the ray burst stays inside)
		Size = UDim2.fromOffset(66, 66),
		ZIndex = 3,
	}, body) :: Frame
	Pop.face(frame, Pop.rarityPaint("Common"), CARD_CORNER)
	local popScale = UIKit.new("UIScale", { Name = "PopScale", Scale = 1 }, frame) :: UIScale
	local rays = Pop.rays(frame, UDim2.fromScale(0.5, 0.44), 8, 60, 0.45, 3)
	rays:SetAttribute("PixelFx", nil) -- (turned here, EggPanelController; PixelFx leaves world guis alone anyway)
	rays.Visible = false
	local picture = UIKit.new("ImageLabel", {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = "",
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 4,
	}, frame) :: ImageLabel
	local view = UIKit.new("ViewportFrame", {
		Name = "View",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = rgb(170, 170, 180),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 4,
	}, picture) :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = view
	pcall(function()
		view.CurrentCamera = camera
	end)
	local chance = Pop.text(frame, "", 21, {
		Name = "Chance",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -30),
		Size = UDim2.new(1, -4, 0, 25),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
	})
	-- (wrapped: the round font, two lines at most; apply() sizes it)
	local name = Pop.text(frame, "", 14, {
		Name = "GolemName",
		AnchorPoint = Vector2.new(0.5, 1),
		LineHeight = 0.9,
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.new(1, -2, 0, 30),
		TextWrapped = true,
		ZIndex = 6,
	})
	local lucky = Pop.text(frame, "x3", 14, {
		Name = "Lucky",
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.fromOffset(30, 18),
		TextColor3 = LUCKY_GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 6,
	})
	return {
		Frame = frame,
		PopScale = popScale,
		Picture = picture,
		View = view,
		Camera = camera,
		Rays = rays,
		Glow = glow,
		Chance = chance,
		Name = name,
		Lucky = lucky,
		Kind = nil,
		Order = 0,
	}
end

-- An Open button: "Open 3" over the price (a coin, or "R$"), a key badge on its corner.
local function newOpen(body: Frame, count: number): Open
	local button = UIKit.new("TextButton", {
		Name = "Open" .. count,
		AutoButtonColor = true,
		Selectable = true,
		Size = UDim2.fromOffset(120, 56),
		Text = "",
		ZIndex = 3,
	}, body) :: TextButton
	Pop.face(button, "Green", 10)
	Pop.fxTag(button, "Press")
	local label = Pop.text(button, `Open {count}`, 22, {
		Name = "Label",
		Position = UDim2.fromScale(0, 0.04),
		Size = UDim2.fromScale(1, 0.46),
		ZIndex = 5,
	})
	local coin = Pop.coin(button, 18, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -20, 0.7, 0),
		ZIndex = 6,
	})
	local amount = Pop.text(button, "0", 18, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, -16, 0.7, 0),
		Size = UDim2.new(0.5, 10, 0.34, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	})
	local key = UIKit.new("Frame", {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -3, 0, 3), -- (on the corner, half outside: clear of the words)
		Size = UDim2.fromOffset(24, 24),
		ZIndex = 7,
	}, button) :: Frame
	UIKit.corner(key, 6)
	Pop.border(key, 2)
	local keyText = UIKit.new("TextLabel", {
		Name = "Letter",
		BackgroundTransparency = 1,
		FontFace = PopTheme.Pixel,
		Size = UDim2.fromScale(1, 1),
		Text = EggPanel.OpenKeys[count] or "",
		TextColor3 = INK,
		TextSize = 16,
		ZIndex = 8,
	}, key) :: TextLabel
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Image = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 8,
	}, key) :: ImageLabel
	return {
		Count = count,
		Button = button,
		Label = label,
		Coin = coin,
		Amount = amount,
		Key = key,
		KeyText = keyText,
		Glyph = glyph,
	}
end

-- Every transparency inside `root` as it is now (setFade lerps them toward 1).
local function collectFades(root: Instance): { Fade }
	local list: { Fade } = {}
	local function add(target: Instance, property: string, base: number)
		if base < 1 then
			table.insert(list, { Target = target, Property = property, Base = base })
		end
	end
	local function visit(d: Instance)
		if d:GetAttribute("NoFade") == true or (d.Parent ~= nil and d.Parent:GetAttribute("NoFade") == true) then
			return -- (animated on its own: the cards' glow, the chip's red flash)
		end
		if d:IsA("GuiObject") then
			add(d, "BackgroundTransparency", d.BackgroundTransparency)
		end
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			add(d, "TextTransparency", (d :: any).TextTransparency)
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("ViewportFrame") then
			add(d, "ImageTransparency", (d :: any).ImageTransparency)
		elseif d:IsA("UIStroke") then
			add(d, "Transparency", d.Transparency)
		end
	end
	visit(root)
	for _, d in root:GetDescendants() do
		visit(d)
	end
	return list
end

-- Builds the one panel (with MaxCards card slots; apply() lays it out for an egg).
function EggPanel.build(): Refs
	local gui = UIKit.new("BillboardGui", {
		Name = "TerraForgeEggPanel",
		Active = true,
		AlwaysOnTop = true,
		ClipsDescendants = false,
		Enabled = false,
		LightInfluence = 0,
		MaxDistance = 1000,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(560, 300),
		SizeOffset = Vector2.new(0, 0.5), -- (its bottom edge at the anchor: the egg's top)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: BillboardGui
	local root = UIKit.new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(560, 300),
	}, gui) :: Frame
	local scale = UIKit.new("UIScale", { Name = "Fit", Scale = 1 }, root) :: UIScale
	local title = Pop.text(root, "Egg", 40, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 50),
		ZIndex = 6,
	})
	local body = UIKit.new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 250),
		ZIndex = 2,
	}, root) :: Frame
	Pop.face(body, PANEL_PAINT, PANEL_CORNER, false, false)
	-- the price chip: a coin and the amount (a Robux egg: "R$ 49" on lime, no coin)
	local chip = UIKit.new("Frame", {
		Name = "Chip",
		Position = UDim2.fromOffset(12, 15),
		Size = UDim2.fromOffset(150, 34),
		ZIndex = 3,
	}, body) :: Frame
	Pop.face(chip, CHIP_PAINT, 17, false, false)
	local coin = Pop.coin(chip, 26, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		ZIndex = 5,
	})
	local price = Pop.text(chip, "0", 22, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 36, 0.5, 0),
		Size = UDim2.new(1, -42, 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	-- the red flash over the chip when the player can't pay (under the amount)
	local alert = UIKit.new("Frame", {
		Name = "Alert",
		BackgroundColor3 = rgb(255, 60, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, chip) :: Frame
	alert:SetAttribute("NoFade", true)
	UIKit.corner(alert, 999)
	-- "Triple Lucky" while its odds show
	local luckyTag = Pop.chip(body, "Triple Lucky", "Yellow", Vector2.new(140, 28), {
		Name = "LuckyTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 3,
	})
	-- Auto: a painted toggle (grey off, green on) with its key on a white badge
	local toggle = UIKit.new("TextButton", {
		Name = "Auto",
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = true,
		Position = UDim2.new(1, -12, 0, 14),
		Selectable = true,
		Size = UDim2.fromOffset(112, 36),
		Text = "",
		ZIndex = 3,
	}, body) :: TextButton
	Pop.face(toggle, PopTheme.Gray, 10)
	Pop.fxTag(toggle, "Press")
	local toggleLabel = Pop.text(toggle, "Auto", 22, {
		Name = "Label",
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -44, 0.9, 0),
		ZIndex = 5,
	})
	local key = UIKit.new("Frame", {
		Name = "Key",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -6, 0.45, 0),
		Size = UDim2.fromOffset(26, 26),
		ZIndex = 5,
	}, toggle) :: Frame
	UIKit.corner(key, 6)
	Pop.border(key, 2)
	local keyText = UIKit.new("TextLabel", {
		Name = "Letter",
		BackgroundTransparency = 1,
		FontFace = PopTheme.Pixel,
		Size = UDim2.fromScale(1, 1),
		Text = "G",
		TextColor3 = INK,
		TextSize = 18,
		ZIndex = 6,
	}, key) :: TextLabel
	local glyph = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Image = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 6,
	}, key) :: ImageLabel
	local cards: { Card } = {}
	for i = 1, EggPanel.MaxCards do
		table.insert(cards, newCard(body, i))
	end
	local opens: { Open } = {}
	for _, count in CapsuleConfig.Counts do
		table.insert(opens, newOpen(body, count))
	end
	for i, open in opens do
		-- (Roblox's gamepad UI navigation walks the row left / right)
		if i > 1 then
			open.Button.NextSelectionLeft = opens[i - 1].Button
		end
		if i < #opens then
			open.Button.NextSelectionRight = opens[i + 1].Button
		end
	end
	return {
		Gui = gui,
		Root = root,
		Scale = scale,
		Title = title,
		Body = body,
		Chip = chip,
		Coin = coin,
		Price = price,
		Alert = alert,
		LuckyTag = luckyTag,
		Toggle = toggle,
		ToggleLabel = toggleLabel,
		Key = key,
		KeyText = keyText,
		Glyph = glyph,
		Cards = cards,
		Opens = opens,
		Fades = collectFades(root),
		Layout = nil,
		Egg = nil,
	}
end

--[[
	Lays the panel out for an egg (`capsuleId`, its card count and the
	device: EggPanel.layout) and returns the layout; the billboard's size
	is the layout's times `scale` (the HUD's), the root's UIScale is `scale`.
]]
function EggPanel.apply(refs: Refs, capsuleId: string, l: Layout, scale: number)
	local capsule = CapsuleConfig.ById[capsuleId]
	refs.Egg = capsuleId
	refs.Layout = l
	refs.Gui.Size = UDim2.fromOffset(math.ceil(l.Width * scale), math.ceil(l.Height * scale))
	refs.Root.Size = UDim2.fromOffset(l.Width, l.Height)
	refs.Scale.Scale = scale
	refs.Title.Text = if capsule then capsule.Name else capsuleId
	refs.Title.Size = UDim2.new(1, 0, 0, l.Title)
	refs.Body.Size = UDim2.new(1, 0, 0, l.Body)
	-- the head row: the chip on the left, Auto on the right, the lucky tag between
	local headY = l.Pad + l.Head / 2
	refs.Chip.AnchorPoint = Vector2.new(0, 0.5)
	refs.Chip.Position = UDim2.fromOffset(l.Pad, headY)
	refs.Chip.Size = UDim2.fromOffset(refs.Chip.Size.X.Offset, l.Chip)
	local chipCorner = refs.Chip:FindFirstChildOfClass("UICorner")
	if chipCorner then
		chipCorner.CornerRadius = UDim.new(0, l.Chip // 2)
	end
	refs.Coin.Size = UDim2.fromOffset(l.Chip - 8, l.Chip - 8)
	refs.Price.Position = UDim2.new(0, l.Chip + 2, 0.5, 0)
	refs.Price.Size = UDim2.new(1, -(l.Chip + 8), 1, -4)
	if l.AutoInRow then
		-- (touch: the last button of the opens' row)
		local at = EggPanel.openAt(l, #CapsuleConfig.Counts + 1)
		refs.Toggle.AnchorPoint = Vector2.zero
		refs.Toggle.Position = UDim2.fromOffset(at.X, at.Y)
	else
		refs.Toggle.AnchorPoint = Vector2.new(1, 0.5)
		refs.Toggle.Position = UDim2.new(1, -l.Pad, 0, headY)
	end
	refs.Toggle.Size = UDim2.fromOffset(l.Toggle.X, l.Toggle.Y)
	-- over the egg: its bottom edge at the anchor (touch: floatOffset moves it every frame)
	refs.Gui.SizeOffset = Vector2.new(0, 0.5)
	-- (touch: no head row, the chip only says "Not available" in the opens' row: setPrice)
	refs.Chip.Visible = l.Head > 0
	local keySize = math.floor(l.Toggle.Y * 0.7)
	refs.Key.Size = UDim2.fromOffset(keySize, keySize)
	refs.ToggleLabel.Size = UDim2.new(1, -(keySize + 16), 0.9, 0)
	Pop.limit(refs.ToggleLabel, math.floor(l.Toggle.Y * 0.56))
	Pop.limit(refs.Price, math.floor(l.Chip * 0.62))
	refs.KeyText.TextSize = math.floor(keySize * 0.66)
	if l.Head > 0 then
		refs.LuckyTag.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.LuckyTag.Position = UDim2.fromOffset(l.Width / 2, headY)
	else
		-- (touch: a sticker on the white panel's top edge, at its right)
		refs.LuckyTag.AnchorPoint = Vector2.new(1, 0.5)
		refs.LuckyTag.Position = UDim2.fromOffset(l.Width - l.Pad, 0)
	end
	-- a card: the golem's picture, its chance over the picture's foot, its name under it
	local picture = l.CardH - l.NameH + 10
	for i, card in refs.Cards do
		local shown = i <= l.Count
		card.Frame.Visible = shown
		if shown then
			local at = EggPanel.cardAt(l, i)
			card.Frame.Position = UDim2.fromOffset(at.X, at.Y)
			card.Frame.Size = UDim2.fromOffset(l.Card, l.CardH)
			card.Glow.Position = UDim2.fromOffset(at.X + l.Card / 2, at.Y + l.CardH / 2)
			card.Glow.Size = UDim2.fromOffset(l.Card + 12, l.CardH + 12)
		end
		card.Picture.Position = UDim2.fromOffset(l.Card / 2, picture / 2)
		card.Picture.Size = UDim2.fromOffset(picture, picture)
		card.Picture:SetAttribute("Rest", picture / 2) -- (EggPanelController's bob starts from here)
		card.Rays.Position = UDim2.fromOffset(l.Card / 2, picture / 2)
		card.Chance.Position = UDim2.new(1, -3, 0, l.CardH - l.NameH + 2)
		card.Chance.Size = UDim2.new(1, -4, 0, l.ChanceSize + 4)
		Pop.limit(card.Chance, l.ChanceSize)
		card.Name.Size = UDim2.new(1, -2, 0, l.NameH)
		card.Name.TextSize = l.NameSize
		card.Lucky.Size = UDim2.fromOffset(l.LuckySize * 2 + 4, l.LuckySize + 4)
		Pop.limit(card.Lucky, l.LuckySize)
		card.Glow.Visible = false
	end
	for i, open in refs.Opens do
		local at = EggPanel.openAt(l, i)
		open.Button.Position = UDim2.fromOffset(at.X, at.Y)
		open.Button.Size = UDim2.fromOffset(l.Open.X, l.Open.Y)
		local badge = math.floor(math.clamp(l.Open.Y * 0.42, 22, 30))
		open.Key.Size = UDim2.fromOffset(badge, badge)
		open.KeyText.TextSize = math.floor(badge * 0.66)
		Pop.limit(open.Label, math.floor(l.Open.Y * 0.4))
		Pop.limit(open.Amount, math.floor(l.Open.Y * 0.32))
		open.Coin.Size = UDim2.fromOffset(math.floor(l.Open.Y * 0.32), math.floor(l.Open.Y * 0.32))
	end
end

--[[
	Where the billboard's anchor stands for an egg whose anchor is `drop`
	studs over its middle (top + Lift - centre): PC, over the egg (no
	offsets: SizeOffset puts its bottom edge on the anchor); touch, back
	down at the egg's middle (floatOffset then moves the panel on the
	screen, every frame).
]]
function EggPanel.place(refs: Refs, drop: number)
	local l = refs.Layout
	refs.Gui.StudsOffset = Vector3.zero
	refs.Gui.StudsOffsetWorldSpace = if l and l.Beside then Vector3.new(0, -drop, 0) else Vector3.zero
end

--[[
	A touch screen as the floating panel sees it (px, the viewport's: the
	controller measures it every frame, in the frames the HUD draws in).
]]
export type Screen = {
	View: Vector2, -- the viewport's size
	Safe: Box, -- the notch-safe part (CoreUISafeInsets)
	Zone: Box, -- the thumbstick's start zone (the left 40 %, lower two thirds)
	Keep: { Box }, -- the opens' row never goes under these: the touch buttons, the HUD's buttons, the boost corner, the tutorial bubble
	Avoid: { Box }, -- the panel keeps its odds (then itself) clear of these where it can: the same, and Roblox's top bar row
	Edges: { Box }, -- what the docked places line up with (dockAt: the touch buttons as one block, the rest)
}

-- What the controller measured (px, the viewport's).
export type ScreenInput = {
	View: Vector2,
	Safe: Box?, -- (default: the whole view)
	TopInset: number?, -- Roblox's top bar row
	Hud: { Box }?, -- the HUD's buttons the panel could meet: the teleport bar, the left tiles, the TRAIN chip
	Corner: Box?, -- the boost corner's tiles (BoostView.cornerSpot, live)
	Bubble: Box?, -- the touch tutorial bubble (live)
}

EggPanel.Margin = 8 -- px between the floating panel and what it keeps clear of
EggPanel.ZoneWidth = 0.4 -- Roblox's dynamic thumbstick starts in the left 40 % of the screen...
EggPanel.ZoneTop = 1 / 3 -- ...below its top third

local function area(a: Box, b: Box): number
	local w = math.min(a.Max.X, b.Max.X) - math.max(a.Min.X, b.Min.X)
	local h = math.min(a.Max.Y, b.Max.Y) - math.max(a.Min.Y, b.Min.Y)
	return if w > 0 and h > 0 then w * h else 0
end

local function shift(b: Box, by: Vector2): Box
	return { Min = b.Min + by, Max = b.Max + by }
end

local function boxArea(b: Box): number
	return math.max(0, b.Max.X - b.Min.X) * math.max(0, b.Max.Y - b.Min.Y)
end

-- The width (px) right of the thumbstick's zone a `viewX` wide screen leaves the floating panel.
function EggPanel.freeWidth(viewX: number): number
	return viewX * (1 - EggPanel.ZoneWidth) - 2 * EggPanel.Margin
end

--[[
	Does the floating panel of `count` cards take the narrow layout on `s`
	(its row on top, right-aligned: LayoutOptions.Narrow)? When the usual
	one is wider than the room right of the thumbstick's zone, or fits
	worse (its row or its odds hidden somewhere) with the egg in the
	screen's middle: the smallest phones (568 x 320).
]]
function EggPanel.pickNarrow(s: Screen, scale: number, count: number, auto: boolean): boolean
	local usual = EggPanel.layout(count, true, auto)
	if usual.Width * scale > EggPanel.freeWidth(s.View.X) then
		return true
	end
	local function fit(l: Layout): Fit
		local size_ = Vector2.new(math.ceil(l.Width * scale), math.ceil(l.Height * scale))
		local _, f = EggPanel.floatAt(s, size_, EggPanel.rowBox(l, scale), EggPanel.oddsBox(l, scale), s.View / 2, 0)
		return f
	end
	local a = fit(usual)
	if a.Hard == 0 and a.Odds == 0 then
		return false
	end
	local b = fit(EggPanel.layout(count, true, auto, { Narrow = true }))
	return b.Hard < a.Hard or (b.Hard == a.Hard and b.Odds < a.Odds)
end

-- How much two screen boxes overlap (px²).
EggPanel.overlap = area

--[[
	The touch screen from what the controller measured: the touch buttons
	in the bottom right of the safe frame (BoostView.TouchButtons, px from
	its bottom-right corner: small on a screen whose shorter side is 500 px
	or less), the top bar, the boost corner and the tutorial bubble.
]]
function EggPanel.screen(input: ScreenInput): Screen
	local view = input.View
	local safe = input.Safe or { Min = Vector2.zero, Max = view }
	local keep: { Box } = {}
	local avoid: { Box } = {}
	local edges: { Box } = {}
	local small = math.min(view.X, view.Y) <= 500
	local buttons: Box? = nil
	for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
		local box = {
			Min = Vector2.new(safe.Max.X - b.Left, safe.Max.Y - b.Top),
			Max = Vector2.new(safe.Max.X - b.Right, safe.Max.Y - b.Bottom),
		}
		table.insert(keep, box)
		table.insert(avoid, box)
		local u = buttons
		buttons = if u then { Min = u.Min:Min(box.Min), Max = u.Max:Max(box.Max) } else box
	end
	if buttons then
		table.insert(edges, buttons)
	end
	local blocks: { Box } = table.clone(input.Hud or {})
	local corner, bubble = input.Corner, input.Bubble
	if corner then
		table.insert(blocks, corner)
	end
	if bubble then
		table.insert(blocks, bubble)
	end
	for _, box in blocks do
		table.insert(keep, box)
		table.insert(avoid, box)
		table.insert(edges, box)
	end
	if input.TopInset and input.TopInset > 0 then
		-- (Roblox's own row: its buttons sit at its ends, the HUD's teleport bar in its middle)
		local strip = { Min = Vector2.zero, Max = Vector2.new(view.X, input.TopInset) }
		table.insert(avoid, strip)
		table.insert(edges, strip)
	end
	local zone = math.max(view.X, safe.Max.X - safe.Min.X) * EggPanel.ZoneWidth
	return {
		View = view,
		Safe = safe,
		Zone = { Min = Vector2.new(0, view.Y * EggPanel.ZoneTop), Max = Vector2.new(safe.Min.X + zone, view.Y) },
		Keep = keep,
		Avoid = avoid,
		Edges = edges,
	}
end

-- What a floating panel's place costs: Hard (px² of its opens' row in the thumbstick's zone, under a
-- touch button, the top bar, the corner or the bubble, out of the safe frame; of the panel off the
-- screen), Odds (px² of its cards hidden), Panel (px² of the rest hidden).
export type Fit = { Hard: number, Odds: number, Panel: number }

--[[
	How a `size` panel whose opens' row is `row` and whose cards are `odds`
	(both from its top-left: rowBox, oddsBox) fits at `at` on `s`.
]]
function EggPanel.fitAt(s: Screen, at: Vector2, size: Vector2, row: Box, odds: Box): Fit
	local panel = { Min = at, Max = at + size }
	local r = shift(row, at)
	local o = shift(odds, at)
	local view = { Min = Vector2.zero, Max = s.View }
	local hard = boxArea(panel) - area(panel, view) + boxArea(r) - area(r, s.Safe) + area(r, s.Zone)
	for _, k in s.Keep do
		hard += area(r, k)
	end
	local hidden = boxArea(o) - area(o, s.Safe)
	local rest = 0
	for _, b in s.Avoid do
		hidden += area(o, b)
		rest += area(panel, b)
	end
	return { Hard = hard, Odds = hidden, Panel = rest }
end

--[[
	The floating panel's top-left (px) on a touch screen, and how it fits.
	Wanted: right of the egg (`egg`: its middle on the screen, `reach`: how
	far right of it the panel starts, px: the egg's half width or the big
	E's, the wider), its middle level with the egg. Then the best place
	from a few candidates (the wanted one clamped, and each one flush with
	an edge of the zone, the safe frame or something to keep clear of):
	first its opens' row out of the thumbstick's zone and off every touch
	button, the top bar, the corner and the bubble, and the panel on the
	screen (Hard); then every card visible (Odds); then the rest of the
	panel (Panel); then nearest the wanted place. Cheap when the wanted
	place is clear (the usual case); the controller only searches again
	when something moved.
]]
function EggPanel.floatAt(s: Screen, size_: Vector2, row: Box, odds: Box, egg: Vector2, reach: number): (Vector2, Fit)
	local want = EggPanel.wantAt(s, size_, row, egg, reach)
	local wantFit = EggPanel.fitAt(s, want, size_, row, odds)
	if wantFit.Hard == 0 and wantFit.Odds == 0 and wantFit.Panel == 0 then
		return want, wantFit
	end
	return EggPanel.dockAt(s, size_, row, odds, want)
end

-- The wanted place (px, top-left): right of the egg, its middle level with it, on the screen.
function EggPanel.wantAt(s: Screen, size_: Vector2, row: Box, egg: Vector2, reach: number): Vector2
	local m = EggPanel.Margin
	local x = math.max(math.min(egg.X + reach + m, s.Safe.Max.X - m - size_.X), s.Zone.Max.X + m - row.Min.X)
	local y = egg.Y - size_.Y / 2
	x = math.max(math.min(x, s.View.X - 2 - size_.X), 2)
	y = math.max(math.min(y, s.View.Y - 2 - size_.Y), 2)
	return Vector2.new(math.floor(x + 0.5), math.floor(y + 0.5))
end

--[[
	The best place when the wanted one isn't clear (floatAt): a few
	candidates, each flush with an edge of the zone, the safe frame or
	something to keep clear of (the touch buttons count as one block),
	nearest `near` on a tie.
]]
function EggPanel.dockAt(s: Screen, size_: Vector2, row: Box, odds: Box, near: Vector2): (Vector2, Fit)
	local m = EggPanel.Margin
	local view = s.View
	local function score(fit: Fit, at: Vector2): number
		return fit.Hard * 1e6 + fit.Odds * 100 + fit.Panel + (at - near).Magnitude * 0.5
	end
	local xs = { near.X, s.Zone.Max.X + m - row.Min.X, s.Safe.Max.X - m - size_.X, s.Safe.Max.X - m - row.Max.X }
	local ys = { near.Y, s.Safe.Min.Y + 2, s.Safe.Max.Y - 2 - size_.Y, s.Zone.Min.Y - m - row.Max.Y }
	for _, b in s.Edges do
		table.insert(xs, b.Min.X - m - size_.X)
		table.insert(xs, b.Max.X + m)
		table.insert(ys, b.Max.Y + m - odds.Min.Y) -- (the cards just under it)
		table.insert(ys, b.Min.Y - m - row.Max.Y) -- (the row just over it)
		table.insert(ys, b.Min.Y - m - size_.Y)
	end
	local best = near
	local bestFit = EggPanel.fitAt(s, near, size_, row, odds)
	local bestScore = score(bestFit, near)
	local seen: { [number]: boolean } = {}
	for _, x0 in xs do
		local x = math.floor(math.max(math.min(x0, view.X - 2 - size_.X), 2) + 0.5)
		for _, y0 in ys do
			local y = math.floor(math.max(math.min(y0, view.Y - 2 - size_.Y), 2) + 0.5)
			local id = x * 100000 + y
			if not seen[id] then
				seen[id] = true
				local at = Vector2.new(x, y)
				local fit = EggPanel.fitAt(s, at, size_, row, odds)
				local value = score(fit, at)
				if value < bestScore then
					best, bestFit, bestScore = at, fit, value
				end
			end
		end
	end
	return best, bestFit
end

local function better(a: Fit, b: Fit): boolean
	return a.Hard < b.Hard or (a.Hard == b.Hard and a.Odds < b.Odds)
end

--[[
	Must the boost corner and / or the tutorial bubble step aside (hide) for
	the floating panel? When the best place with them on the screen still
	hides the opens' row or a card, and without one of them (the corner
	first, then the bubble, then both) it fits better. A phone mostly (its
	bubble sits where the odds go); an iPad's corner has room beside it.
]]
function EggPanel.asides(input: ScreenInput, size_: Vector2, row: Box, odds: Box, egg: Vector2, reach: number): (boolean, boolean)
	local _, fit = EggPanel.floatAt(EggPanel.screen(input), size_, row, odds, egg, reach)
	if fit.Hard == 0 and fit.Odds == 0 then
		return false, false
	end
	local best, corner, bubble = fit, false, false
	for _, option in { { true, false }, { false, true }, { true, true } } do
		local dropCorner, dropBubble = option[1], option[2]
		if (dropCorner and input.Corner == nil) or (dropBubble and input.Bubble == nil) then
			continue
		end
		local without = table.clone(input)
		if dropCorner then
			without.Corner = nil
		end
		if dropBubble then
			without.Bubble = nil
		end
		local _, f = EggPanel.floatAt(EggPanel.screen(without), size_, row, odds, egg, reach)
		if better(f, best) then
			best, corner, bubble = f, dropCorner, dropBubble
		end
	end
	return corner, bubble
end

--[[
	The SizeOffset that draws a `size` billboard whose anchor is at
	`anchor` on the screen (px) with its top-left at `at` (SizeOffset moves
	a billboard by its own size: x to the right, y up).
]]
function EggPanel.floatOffset(anchor: Vector2, at: Vector2, size: Vector2): Vector2
	local center = at + size / 2
	return Vector2.new((center.X - anchor.X) / math.max(size.X, 1), (anchor.Y - center.Y) / math.max(size.Y, 1))
end

-- A golem model's framing for a card (centre, radius of its parts' box).
function EggPanel.bounds(model: Instance): (Vector3, number)
	local lo, hi = box(model)
	if lo.X > hi.X then
		return Vector3.zero, 1
	end
	return (lo + hi) * 0.5, math.max(0.5, (hi - lo).Magnitude * 0.5)
end

local FROM = Vector3.new(-0.3, 0.22, -1).Unit -- a golem's picture: from the front-left, a bit above (PictureModels)

-- What setLines asks the controller for a kind: its cached model and framing (nil: no 3D picture).
export type ModelFor = (kind: string) -> (Model?, Vector3, number)

-- Takes every golem model out of a card's view (they are the controller's cached models: let go, not destroyed).
local function emptyView(card: Card)
	for _, child in card.View:GetChildren() do
		if child:IsA("Model") then
			child.Parent = nil
		end
	end
	card.Kind = nil
end

--[[
	Fills the cards: each line's rarity paint, chance, "x3" when Triple
	Lucky triples it, the golem's name and its picture (a silhouette:
	black, its name under it all the same). `modelFor` lends each card its
	golem's cached model (moved into the card's own viewport, the card's
	camera framed on it); nil in the previews. A model is in one view at a
	time and a view holds one model at most: first every card lets go of a
	model it shouldn't show any more (its slot hides, or it shows another
	golem now: the walk from one egg to the next moves the shared models
	between slots), then the cards without one take theirs.
]]
function EggPanel.setLines(refs: Refs, lines: { Line }, modelFor: ModelFor?)
	for i, card in refs.Cards do
		local line = lines[i]
		if not line or card.Kind ~= line.Golem then
			emptyView(card)
		end
	end
	for i, card in refs.Cards do
		local line = lines[i]
		if not line then
			card.Frame.Visible = false
			continue
		end
		card.Frame.Visible = true
		Pop.repaint(card.Frame, Pop.rarityPaint(line.Rarity))
		card.Chance.Text = line.Text
		card.Name.Text = line.Name
		card.Lucky.Visible = line.Lucky
		local info = Rarity.ById[line.Rarity]
		card.Order = if info then info.Order else 0
		card.Rays.Visible = card.Order >= EggPanel.RaysFrom
		card.Glow.Visible = card.Order >= EggPanel.GlowFrom
		card.Glow.BackgroundColor3 = if info then info.Color:Lerp(WHITE, 0.25) else WHITE
		local black = if line.Silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
		card.View.ImageColor3 = black
		card.Picture.ImageColor3 = black -- (the previews' stand-in picture; the game's Image is empty)
		card.Picture:SetAttribute("Icon", "golem_" .. line.Golem)
		if card.Kind == nil then
			if modelFor then
				local model, center, radius = modelFor(line.Golem)
				if model then
					emptyView(card) -- (never two in one view)
					model.Parent = card.View
					local at = center + FROM * (radius / math.sin(math.rad(15)) * 0.95)
					card.Camera.CFrame = CFrame.lookAt(at, center)
				end
			end
			card.Kind = line.Golem
		end
	end
end

--[[
	The price chip: `kind` "Coins" (the coin and the amount; red when the
	player can't pay it yet), "Robux" ("R$ 49" on lime) or "Off" (a grey
	chip with a word: "Coming soon", "Not available").
]]
function EggPanel.setPrice(refs: Refs, kind: string, text: string, affordable: boolean)
	local l = refs.Layout
	local h = if l then l.Chip else 34
	local coin = kind == "Coins"
	refs.Coin.Visible = coin
	refs.Price.Text = text
	refs.Price.TextColor3 = if coin and not affordable then SHORT else WHITE
	local textSize = math.floor(h * 0.6)
	local left = if coin then h + 2 else 14
	refs.Price.Position = UDim2.new(0, left, 0.5, 0)
	refs.Price.Size = UDim2.new(1, -(left + 8), 1, -4)
	refs.Price.TextXAlignment = if coin then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	local width = left + Pop.textWidth(text, textSize) + 12
	refs.Chip.Size = UDim2.fromOffset(math.clamp(math.ceil(width), h + 40, 220), h)
	Pop.repaint(refs.Chip, if kind == "Robux" then "Lime" elseif kind == "Off" then PopTheme.Gray else CHIP_PAINT, false)
	if l and l.Head <= 0 then
		-- touch (no head row: the opens show the price): only "Not available" / "Coming
		-- soon" shows, where the opens' row would be
		refs.Chip.Visible = kind == "Off"
		refs.Chip.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.Chip.Position = UDim2.fromOffset(l.Width / 2, l.OpenY + l.Open.Y / 2)
	end
end

-- The "Triple Lucky" tag in the head row (hidden when there is no room for it).
function EggPanel.setLucky(refs: Refs, on: boolean, autoShown: boolean)
	local l = refs.Layout
	if not l then
		refs.LuckyTag.Visible = false
		return
	end
	if l.Head <= 0 then
		refs.LuckyTag.Visible = on -- (touch: the sticker on the panel's top edge, apply())
		return
	end
	local right = if autoShown and not l.AutoInRow then l.Toggle.X else 0
	local free = l.Width - 2 * l.Pad - refs.Chip.Size.X.Offset - right - 24
	refs.LuckyTag.Visible = on and free >= 120
	local x = l.Pad + refs.Chip.Size.X.Offset + 12 + free / 2
	refs.LuckyTag.Position = UDim2.fromOffset(x, l.Pad + l.Head / 2)
end

--[[
	Auto: shown on coin eggs, green when on. The key badge shows the
	keyboard key's letter, a gamepad glyph (`image`), or nothing on touch
	(`text` "" and no image: the badge hides).
]]
function EggPanel.setAuto(refs: Refs, visible: boolean, on: boolean, text: string, image: string?)
	refs.Toggle.Visible = visible
	Pop.repaint(refs.Toggle, if on then "Green" else PopTheme.Gray)
	local hasImage = image ~= nil and image ~= ""
	refs.Key.Visible = hasImage or text ~= ""
	refs.KeyText.Text = text
	refs.KeyText.Visible = not hasImage
	refs.Glyph.Image = image or ""
	refs.Glyph.Visible = hasImage
	local keyRoom = if refs.Key.Visible then refs.Key.Size.X.Offset + 16 else 16
	refs.ToggleLabel.Size = UDim2.new(1, -keyRoom, 0.9, 0)
end

-- Every transparency under `root` as built (setFade / applyFades lerp them; EggPrompt uses it too).
function EggPanel.fadesOf(root: Instance): { Fade }
	return collectFades(root)
end

-- 0 = fully shown, 1 = gone, for a fade list.
function EggPanel.applyFades(list: { Fade }, alpha: number)
	local a = math.clamp(alpha, 0, 1)
	for _, fade in list do
		(fade.Target :: any)[fade.Property] = fade.Base + (1 - fade.Base) * a
	end
end

-- 0 = fully shown, 1 = gone (every transparency lerped from its built value).
function EggPanel.setFade(refs: Refs, alpha: number)
	EggPanel.applyFades(refs.Fades, alpha)
end

--[[
	What the Open 1 / 3 / 10 buttons show, from the capsule window's buys
	for this egg (CapsuleView.cards: Count, Price, PriceText, CanBuy,
	Reason), in CapsuleConfig.Counts order: a coin price ("7,500"), a Robux
	price ("R$ 129") or "Coming soon" while the product isn't live; enabled
	only when the window's button would be.
]]
function EggPanel.opens(buys: { any }, robux: boolean): { OpenSpec }
	local out: { OpenSpec } = {}
	for _, count in CapsuleConfig.Counts do
		local buy: any = nil
		for _, b in buys do
			if type(b) == "table" and b.Count == count then
				buy = b
			end
		end
		if buy then
			local price = if robux
				then (if buy.Reason == "ComingSoon" then "Coming soon" else tostring(buy.PriceText))
				else EggPanel.priceText(buy.Price or 0)
			table.insert(out, { Count = count, Robux = robux, Price = price, Enabled = buy.CanBuy == true, Reason = buy.Reason })
		end
	end
	return out
end

--[[
	Paints the Open buttons (`specs`: opens()): green with the coin price,
	lime with the Robux price, grey when they can't be bought. `keys` gives
	each count's key badge text (nil / "": no badge); `glyphs` each count's
	badge image instead (a gamepad: the main prompt's button on Open 1, the
	panel's focus button on Open 3 and Open 10).
]]
function EggPanel.setOpens(refs: Refs, specs: { OpenSpec }, keys: { [number]: string }?, glyphs: { [number]: string }?)
	for _, open in refs.Opens do
		local spec: OpenSpec? = nil
		for _, s in specs do
			if s.Count == open.Count then
				spec = s
			end
		end
		open.Button.Visible = spec ~= nil
		if spec then
			open.Amount.Text = spec.Price
			open.Coin.Visible = not spec.Robux
			open.Amount.Position = if spec.Robux then UDim2.new(0, 6, 0.7, 0) else UDim2.new(0.5, -16, 0.7, 0)
			open.Amount.Size = if spec.Robux then UDim2.new(1, -12, 0.34, 0) else UDim2.new(0.5, 10, 0.34, 0)
			open.Amount.TextXAlignment = if spec.Robux then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
			local paint: string | Pop.Paint = if not spec.Enabled then PopTheme.Gray elseif spec.Robux then "Lime" else "Green"
			Pop.repaint(open.Button, paint)
		end
		local text = if keys then keys[open.Count] else nil
		local image = if glyphs then glyphs[open.Count] else nil
		local hasImage = image ~= nil and image ~= ""
		open.Key.Visible = hasImage or (text ~= nil and text ~= "")
		open.KeyText.Text = text or ""
		open.KeyText.Visible = not hasImage
		open.Glyph.Image = image or ""
		open.Glyph.Visible = hasImage
	end
end

-- The touch targets on the panel (the specs check 44 pt on phones).
function EggPanel.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = { refs.Toggle }
	for _, open in refs.Opens do
		table.insert(list, open.Button)
	end
	return list
end

return EggPanel
