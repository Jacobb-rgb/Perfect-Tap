--[[
	EggPanel: the clean panel over the egg you stand at in the EGGS temple
	(owner 2026-10-28, two pictures of other egg games: "what we have now I
	almost don't like at all; I want it like this, it feels cleaner"). We
	copy the look and the flow, never their pictures: our golems, our coin.

	         Stone Egg                    the egg's name, big, white, a dark edge
	  +----------------------------+
	  | (coin) 2,500     [Auto  G] |      the price chip, Auto (coin eggs only)
	  | [45%] [30%] [20%] [5%] ... |      a card per golem: its rarity's paint,
	  | [ ..% ] ...                |      its live 3D picture, its exact chance
	  +----------------------------+

	- A BillboardGui (PlayerGui, AlwaysOnTop) its bottom edge at the egg's
	  top; one alive at a time (EggPanelController moves it to the nearest
	  egg). Laid out in design units (720 high, like every window) and scaled
	  by the HUD's scale: at the phone floor (0.62) the touch layout's Auto
	  is 72 units, 44 pt.
	- Cards: CapsuleConfig.odds order (the server's roll table, rarer last),
	  the chance in at most three significant digits and three decimals
	  ("45%", "20.5%", "0.28%"); with Triple Lucky on, its odds and an "x3"
	  on every golem it triples. A golem the player has none of is a black
	  silhouette on a coin egg (silhouettes: the inventory, State Golems
	  Owned + Pending, is what we know; a Robux egg always shows its golems).
	- The pictures: ViewportFrames, one per card slot, made once; the
	  controller lends each slot a cached golem model (setLines' `modelFor`).
	  In the Lune previews the "Picture" ImageLabel's Icon attribute stands in.
	- Fade: every transparency in the panel is listed once at build
	  (refs.Fades); setFade(alpha) lerps them all toward 1 (no allocation).

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
-- eggs only: a Robux egg always shows exactly what can come out of it.
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
	panel's bottom edge sits Lift above it) and where its prompts go: in
	front of the shell toward `front` (the stall's front), at its middle.
]]
function EggPanel.spotOf(model: Instance, front: Vector3): (Vector3, number, Vector3)
	local lo, hi = box(model)
	if lo.X > hi.X then
		local at = if model:IsA("Model") then model:GetPivot().Position else Vector3.zero
		return at, at.Y + 2, at
	end
	local center = (lo + hi) * 0.5
	local flat = Vector3.new(front.X, 0, front.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local half = math.max(hi.X - lo.X, hi.Z - lo.Z) * 0.5
	return center, hi.Y, center + dir * (half + 0.5)
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

export type Layout = {
	Touch: boolean,
	Count: number,
	Columns: number,
	Rows: number,
	Card: number,
	Gap: number,
	Pad: number,
	Head: number, -- the row of the price chip and Auto
	HeadGap: number,
	Title: number, -- the egg's name above the white panel
	TitleSize: number,
	ChanceSize: number,
	Chip: number, -- the price chip's height
	Toggle: Vector2, -- Auto
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

--[[
	The panel's sizes for `count` cards (design units). `touch`: phones and
	tablets: Auto is 72 units tall, 44 pt at the phone scale (0.62); the
	cards stay as big as on PC (a bigger head row, not a bigger panel).
]]
function EggPanel.layout(count: number, touch: boolean): Layout
	local columns = EggPanel.columns(count)
	local rows = math.max(1, math.ceil(math.max(1, count) / columns))
	local card, gap, pad = 66, 6, 12
	local head = if touch then 72 else 40
	local toggle = if touch then Vector2.new(150, 72) else Vector2.new(112, 36)
	local chip = if touch then 52 else 34
	local grid = pad * 2 + columns * card + (columns - 1) * gap
	-- the head row needs the chip, Auto and a gap at least
	local width = math.max(grid, pad * 2 + 160 + 12 + toggle.X)
	local body = pad + head + 10 + rows * card + (rows - 1) * gap + pad
	local title = 50
	return {
		Touch = touch,
		Count = count,
		Columns = columns,
		Rows = rows,
		Card = card,
		Gap = gap,
		Pad = pad,
		Head = head,
		HeadGap = 10,
		Title = title,
		TitleSize = 40,
		ChanceSize = 21,
		Chip = chip,
		Toggle = toggle,
		Width = width,
		Body = body,
		Height = title + body,
	}
end

-- Where card `i` (1-based) sits in the white panel (its top-left, design units).
function EggPanel.cardAt(l: Layout, i: number): Vector2
	local col = (i - 1) % l.Columns
	local row = (i - 1) // l.Columns
	-- a short last row is centred under the full ones
	local inRow = if row == l.Rows - 1 then l.Count - row * l.Columns else l.Columns
	local rowWidth = inRow * l.Card + (inRow - 1) * l.Gap
	local x0 = (l.Width - rowWidth) / 2
	return Vector2.new(x0 + col * (l.Card + l.Gap), l.Pad + l.Head + l.HeadGap + row * (l.Card + l.Gap))
end

---------------------------------------------------------------- builder

export type Fade = { Target: Instance, Property: string, Base: number }

export type Card = {
	Frame: Frame,
	Picture: ImageLabel,
	View: ViewportFrame,
	Camera: Camera,
	Chance: TextLabel,
	Lucky: TextLabel,
	Kind: string?,
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
	LuckyTag: Frame,
	Toggle: TextButton,
	ToggleLabel: TextLabel,
	Key: Frame,
	KeyText: TextLabel,
	Glyph: ImageLabel,
	Cards: { Card },
	Fades: { Fade },
	Layout: Layout?,
	Egg: string?,
}

local function newCard(body: Frame, i: number): Card
	local frame = UIKit.new("Frame", {
		Name = "Card" .. i,
		ClipsDescendants = false,
		Size = UDim2.fromOffset(66, 66),
		ZIndex = 3,
	}, body) :: Frame
	Pop.face(frame, Pop.rarityPaint("Common"), CARD_CORNER)
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
		Position = UDim2.new(1, -3, 1, -1),
		Size = UDim2.new(1, -4, 0, 27),
		TextXAlignment = Enum.TextXAlignment.Right,
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
	return { Frame = frame, Picture = picture, View = view, Camera = camera, Chance = chance, Lucky = lucky, Kind = nil }
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
	return {
		Gui = gui,
		Root = root,
		Scale = scale,
		Title = title,
		Body = body,
		Chip = chip,
		Coin = coin,
		Price = price,
		LuckyTag = luckyTag,
		Toggle = toggle,
		ToggleLabel = toggleLabel,
		Key = key,
		KeyText = keyText,
		Glyph = glyph,
		Cards = cards,
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
	refs.Toggle.AnchorPoint = Vector2.new(1, 0.5)
	refs.Toggle.Position = UDim2.new(1, -l.Pad, 0, headY)
	refs.Toggle.Size = UDim2.fromOffset(l.Toggle.X, l.Toggle.Y)
	local keySize = math.floor(l.Toggle.Y * 0.7)
	refs.Key.Size = UDim2.fromOffset(keySize, keySize)
	refs.ToggleLabel.Size = UDim2.new(1, -(keySize + 16), 0.9, 0)
	Pop.limit(refs.ToggleLabel, math.floor(l.Toggle.Y * 0.56))
	Pop.limit(refs.Price, math.floor(l.Chip * 0.62))
	refs.KeyText.TextSize = math.floor(keySize * 0.66)
	refs.LuckyTag.Position = UDim2.fromOffset(l.Width / 2, headY)
	for i, card in refs.Cards do
		local shown = i <= l.Count
		card.Frame.Visible = shown
		if shown then
			local at = EggPanel.cardAt(l, i)
			card.Frame.Position = UDim2.fromOffset(at.X, at.Y)
			card.Frame.Size = UDim2.fromOffset(l.Card, l.Card)
		end
	end
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

--[[
	Fills the cards: each line's rarity paint, chance, "x3" when Triple
	Lucky triples it, and its picture (a silhouette: black). `modelFor`
	lends each card its golem model (moved into the card's own viewport,
	the card's camera framed on it); nil in the previews.
]]
function EggPanel.setLines(refs: Refs, lines: { Line }, modelFor: ModelFor?)
	for i, card in refs.Cards do
		local line = lines[i]
		if not line then
			card.Frame.Visible = false
			continue
		end
		card.Frame.Visible = true
		Pop.repaint(card.Frame, Pop.rarityPaint(line.Rarity))
		card.Chance.Text = line.Text
		card.Lucky.Visible = line.Lucky
		local black = if line.Silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
		card.View.ImageColor3 = black
		card.Picture.ImageColor3 = black -- (the previews' stand-in picture; the game's Image is empty)
		card.Picture:SetAttribute("Icon", "golem_" .. line.Golem)
		if card.Kind ~= line.Golem and modelFor then
			local model, center, radius = modelFor(line.Golem)
			if model then
				model.Parent = card.View
				local at = center + FROM * (radius / math.sin(math.rad(15)) * 0.95)
				card.Camera.CFrame = CFrame.lookAt(at, center)
			end
		end
		card.Kind = line.Golem
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
end

-- The "Triple Lucky" tag in the head row (hidden when there is no room for it).
function EggPanel.setLucky(refs: Refs, on: boolean, autoShown: boolean)
	local l = refs.Layout
	if not l then
		refs.LuckyTag.Visible = false
		return
	end
	local right = if autoShown then l.Toggle.X else 0
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

-- 0 = fully shown, 1 = gone (every transparency lerped from its built value).
function EggPanel.setFade(refs: Refs, alpha: number)
	local a = math.clamp(alpha, 0, 1)
	for _, fade in refs.Fades do
		(fade.Target :: any)[fade.Property] = fade.Base + (1 - fade.Base) * a
	end
end

-- The touch targets on the panel (the specs check 44 pt on phones).
function EggPanel.touchTargets(refs: Refs): { GuiObject }
	return { refs.Toggle }
end

return EggPanel
