--[[
	The Robux Shop window, shop v3 (owner 2026-11-11, the "WOW" concept
	docs/art/shop_v3_concept/shop_wow.html; its pictures in
	obrazky/novy_obchod_wow_2026-11-11): a studded header band with the
	basket over its corner, a big outlined SHOP, six tabs with pictures (the
	open one bigger, with a white rim and a glow) and a red X; under it the
	open tab's page of bright cards (thick dark outlines, a dark lip, gloss,
	rays behind the pictures, 3D price buttons with the Robux mark), every
	tab its own colour world (ShopFx.Themes) with lightning, rays and
	sparkles behind the cards. Config/StoreConfig places the cards; UI/ShopFx
	draws the effects and moves them (StoreController starts it).

	  build(metrics?)          the window (hidden); Refs.Cards[id] per StoreConfig card
	  metricsFor(compact, fit) the sizes for a PC, or a phone / tablet / TV
	                           (buy buttons and tabs at least 44 pt: the pages scroll)
	  needsRebuild(refs, w, h, compact) the window was built for other sizes
	  layout(refs, w, h, compact?) fits the window into w x h design units
	  selectTab(refs, id)      shows tab `id`'s page (and its colours)
	  setCard(refs, id, key, state) which product a card shows now and its
	                           state ("Buy" | "Owned" | "Pending" | "Locked" |
	                           "Hidden"); hidden cards close their row up and a
	                           tab with nothing to show hides
	  setCoins(refs, income)   the coin amounts at this podium income
	  setEdition / setBannerOdds / setTimer   the limited golem edition (Featured)
	  setRoyalOdds(refs, odds, lucky)          the Royal Egg's golems (Golems)
	  showDetail(refs, detail?) the odds panel shown before a paid random buy
	  setStatus(refs, text?)   a line at the bottom of the window

	Real data only (owner rule 2026-11-11): every name, price, chance,
	amount and date comes from the configs and the player's live data;
	"BEST VALUE!" only on the option whose price per item really is the
	lowest (bestValue). Pictures are live 3D models (PictureModels) or,
	once uploaded, the shop icon sheet (IconAssets.Shop); drawn pictures
	(the wheel, the x2 badge) or words otherwise, never an emoji.

	Pure builder + layout, no services: the Lune previews build it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreConfig = require(Shared.Config.StoreConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local CapsuleConfig = require(Shared.Config.CapsuleConfig)
local GolemConfig = require(Shared.Config.GolemConfig)
local EnchantConfig = require(Shared.Config.EnchantConfig)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local IconAssets = require(Shared.Config.IconAssets)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)
local PictureModels = require(Shared.Builders.PictureModels)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local ShopFx = require(script.Parent.ShopFx)
local BoostView = require(script.Parent.BoostView)

local StoreView = {}

local hex = Color3.fromHex
local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------- sizes (design units: the concept's px / 1.25)

StoreView.Width = 1060
StoreView.MaxHeight = 672
StoreView.MinHeight = 440 -- a shorter screen shrinks the whole window (fit < 1)
StoreView.Rim = 5 -- the dark frame round the window
StoreView.Corner = 22
StoreView.Pad = 16 -- the page's sides
StoreView.PadTop = 22 -- (room for the stickers over the first row)
StoreView.PadBottom = 16
StoreView.Gap = 13 -- between two cards
StoreView.RowGap = 20 -- between two rows
StoreView.CardCorner = 18
StoreView.ContentWidth = StoreView.Width - 2 * StoreView.Rim - 2 * StoreView.Pad
StoreView.ButtonH = 46 -- a price button on a PC
StoreView.MinTouch = 44 -- points: the smallest tap target (all-platforms rule)
StoreView.PhoneScale = 0.62 -- HudController's UI scale on phones
StoreView.HudRoom = 200 -- the left HUD column the window keeps clear when the screen is wide enough

export type Metrics = {
	Compact: boolean,
	Button: number, -- a price button's height
	Tab: number, -- a tab's height
	Header: number, -- the header band's height
	Close: number, -- the X
	Word: number, -- a tab's word size
	Extra: number, -- how much taller a row of buttons is than on a PC (cards grow by it)
	Lines: number, -- the odds panel's text
	Status: number,
	Detail: Vector2, -- the odds panel
	DetailButton: Vector2, -- its BACK and BUY
}

-- Design units a tap target needs to be 44 pt on a phone through the fit shrink.
function StoreView.minTouch(fit: number): number
	return math.ceil(StoreView.MinTouch / (StoreView.PhoneScale * math.max(fit, 0.3)))
end

-- The sizes for a PC (compact false) or a phone / tablet / TV at the window's fit.
function StoreView.metricsFor(compact: boolean?, fit: number?): Metrics
	if not compact then
		return {
			Compact = false,
			Button = StoreView.ButtonH,
			Tab = 50,
			Header = 86,
			Close = 58,
			Word = 18,
			Extra = 0,
			Lines = 18,
			Status = 20,
			Detail = Vector2.new(640, 470),
			DetailButton = Vector2.new(200, 54),
		}
	end
	local touch = StoreView.minTouch(fit or 1)
	local button = math.max(StoreView.ButtonH, math.ceil(touch / 4) * 4)
	return {
		Compact = true,
		Button = button,
		Tab = button,
		Header = button + 28,
		Close = button,
		Word = 21,
		Extra = button - StoreView.ButtonH,
		Lines = 24,
		Status = 24,
		Detail = Vector2.new(820, 520),
		DetailButton = Vector2.new(250, button),
	}
end

-- A key that changes when the sizes do (the controller rebuilds the window then).
function StoreView.metricsKey(m: Metrics): string
	return `{if m.Compact then "C" else "N"}{m.Button}`
end

-- The window's size and fit scale for a w x h design-unit screen: the window
-- keeps its width and gets as tall as the screen allows (at most MaxHeight);
-- a screen too narrow or shorter than MinHeight shrinks it all (fit < 1).
function StoreView.windowSize(w: number, h: number): (Vector2, number)
	local fit = math.min(1, (w - 24) / StoreView.Width, (h - 16) / StoreView.MinHeight)
	local height = math.min(StoreView.MaxHeight, (h - 16) / fit)
	return Vector2.new(StoreView.Width, math.floor(height)), fit
end

---------------------------------------------------------------- types

export type CardRefs = {
	Spec: StoreConfig.CardSpec,
	Holder: Frame, -- the card: the page places it
	Button: TextButton, -- its face: the click and gamepad stop of a one-price card
	Title: TextLabel?,
	Amount: TextLabel?, -- Coins / Starter: the coins it gives
	Description: TextLabel?,
	Note: TextLabel?, -- a line the controller changes (a STAR blaster's state, the blaster's rule)
	Big: TextLabel?, -- the big line (the blaster's levels)
	Picture: GuiObject?, -- its picture (a STAR blaster's live gun goes in its View)
	Price: TextButton, -- the (first) price button's face
	PriceAmount: TextLabel,
	Buys: { [string]: TextButton }, -- product key -> its price button's face
	Owned: Frame,
	Shade: Frame,
	Sticker: Frame?, -- BEST VALUE! (setCoins moves it to the best pack)
	Key: string, -- the product it shows now
	State: string,
}

export type Detail = {
	Title: string,
	Lines: { string },
	Robux: number,
	Paint: string?,
}

-- The limited edition in the FEATURED banner (LimitedGolems.current: the
-- golem chat's config; this view only reads these fields).
export type Edition = {
	Id: string,
	Title: string,
	Tagline: string,
	Backdrop: { SkyTop: Color3, SkyHorizon: Color3, Ground: Color3, Accent: Color3, Title: { Color3 }, Image: number? },
	Golems: { { Id: string, Name: string, Rarity: string } }, -- the set's order (the rarest last)
	CapsuleId: string?, -- its capsule (the shard egg shown on the banner)
	Odds: { [string]: number },
	Products: { [number]: string }, -- count -> MonetizationConfig key
	EndsAt: number,
}

export type BannerRefs = {
	Frame: Frame,
	Timer: TextLabel, -- "ENDS NOV 30 · 19d 4h left"
	Buys: { [number]: TextButton }, -- count -> its price button's face
	Chances: { [string]: TextLabel }, -- golem id -> its tile's chance
	Lucky: TextLabel, -- "WITH TRIPLE LUCKY" while the boost runs
	Hero: TextLabel, -- "Dragon King 1%": the rarest golem's chance
	Edition: Edition,
}

export type RoyalRefs = {
	Frame: Frame,
	Chances: { [string]: TextLabel }, -- golem id -> its tile's chance
	Lucky: TextLabel,
}

export type TabRefs = {
	Holder: Frame,
	Lift: Frame, -- (the motion bobs it)
	Face: TextButton,
	Scale: UIScale,
	Ring: Frame,
	Glow: Frame,
	Width: number,
}

export type Window = {
	Root: Frame,
	Header: Frame,
	Title: TextLabel,
	Close: TextButton,
	Body: Frame,
}

export type Refs = {
	Gui: ScreenGui,
	Group: Frame, -- the window and its glow (the motion pops it)
	Window: Window,
	Scroller: ScrollingFrame, -- the open page scrolls in it
	Pages: { [string]: Frame },
	Sections: { [string]: Frame }, -- (= Pages)
	Tabs: { [string]: TextButton }, -- tab id -> its face
	TabRefs: { [string]: TabRefs },
	Cards: { [string]: CardRefs },
	Order: { string }, -- card ids in the configs' order (gamepad order)
	Status: TextLabel,
	Detail: Frame,
	DetailTitle: TextLabel,
	DetailLines: TextLabel,
	DetailBuy: TextButton,
	DetailBack: TextButton,
	Banner: BannerRefs?, -- the limited edition (FEATURED), nil when none runs
	Royal: RoyalRefs?, -- the Royal Egg's golems (GOLEMS)
	Fx: { Instance }, -- the window's own effects (the motion's fixed roots)
	Current: string, -- the open tab
	Fit: number, -- the last layout's fit scale
	Compact: boolean,
	Metrics: Metrics,
}

---------------------------------------------------------------- data (pure)

-- "12.5%" / "0.5%" / "1%" (the odds on the tiles).
function StoreView.percent(chance: number): string
	local text = string.format("%.2f", chance * 100)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
end

-- The quiet time left: "29d 21h left" / "21h 15m left" (no ticking seconds:
-- COMPLIANCE "a calm ends-on line, no rush").
function StoreView.countdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d, h, m = s // 86400, (s // 3600) % 24, (s // 60) % 60
	if d > 0 then
		return `{d}d {h}h left`
	end
	return `{h}h {m}m left`
end

local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

-- "ENDS NOV 30" (the edition's real end date, UTC).
function StoreView.endsOn(endsAt: number): string
	local t = os.date("!*t", math.floor(endsAt)) :: any
	return `ENDS {MONTHS[t.month] or ""} {t.day}`
end

-- "5 min" / "1 hour" / "2 hours" (a pack's seconds).
function StoreView.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 and s % 3600 == 0 then
		local h = s // 3600
		return `{h} hour{if h == 1 then "" else "s"}`
	end
	return `{math.floor(s / 60 + 0.5)} min`
end

-- What one buy button says over its price ("1 spin", "15 min", "3 Golems").
function StoreView.optionLabel(key: string): string
	local product = MonetizationConfig.Products[key]
	if not product then
		return ""
	end
	if product.Spins then
		return `{product.Spins} spin{if product.Spins == 1 then "" else "s"}`
	end
	if product.Boost and product.Seconds then
		return StoreView.duration(product.Seconds)
	end
	if product.Count then
		return `{product.Count} Golem{if product.Count == 1 then "" else "s"}`
	end
	return ""
end

-- How many of the thing a product gives (eggs, spins, boost seconds; coins at `income`).
function StoreView.amountOf(key: string, income: number?): number
	local product = MonetizationConfig.Products[key]
	if not product then
		return 0
	end
	if product.CoinSeconds then
		return MonetizationConfig.coinPackAmount(key, income or 0) or 0
	end
	return product.Count or product.Spins or product.Seconds or 1
end

--[[
	The BEST VALUE among `keys`: the product with the lowest Robux per item
	(amountOf), and only when it is strictly the lowest (nil for a tie or a
	single option). The stickers never claim more than this.
]]
function StoreView.bestValue(keys: { string }, income: number?): string?
	local best: string? = nil
	local bestRate = math.huge
	local tie = false
	for _, key in keys do
		local product = MonetizationConfig.Products[key]
		local amount = StoreView.amountOf(key, income)
		if product and amount > 0 then
			local rate = product.Robux / amount
			if rate < bestRate - 1e-9 then
				best, bestRate, tie = key, rate, false
			elseif math.abs(rate - bestRate) <= 1e-9 then
				tie = true
			end
		end
	end
	if #keys < 2 or tie then
		return nil
	end
	return best
end

-- Does buying `key` from `spec`'s card show the odds first? (Paid random products always do.)
function StoreView.needsOdds(spec: StoreConfig.CardSpec?, key: string): boolean
	local product = MonetizationConfig.Products[key]
	return (product ~= nil and product.PaidRandom == true) or (spec ~= nil and spec.Odds == true)
end

-- The STAR blaster with the most power (its card says STRONGEST! and wears the running rim).
function StoreView.strongest(): string?
	local best: string? = nil
	local most = -math.huge
	for _, star in StarBlasterData.List do
		if star.Mult > most then
			best, most = star.Id, star.Mult
		end
	end
	return best
end

-- An enchant's effect lines from EnchantConfig ("+75% ore luck, +50% artifact chance").
function StoreView.enchantLine(enchantId: string?): string
	if not enchantId then
		return ""
	end
	return table.concat(EnchantConfig.describe(enchantId, 1), ", ")
end

---------------------------------------------------------------- pictures

--[[
	A live 3D picture `size` square with its middle at `at` (nil: no model).
	The model itself is built when its page first shows (fillModels): the
	shop opens with only the open tab's models built (cheap on phones).
	`props` adds to the picture's.
]]
local function livePicture(parent: Instance, model: string?, icon: string, size: number, props: { [string]: any }): ImageLabel?
	if not model then
		return nil
	end
	local picture = Pop.model(parent, icon, size, nil, props)
	if string.sub(model, 1, 5) ~= "star_" then
		picture:SetAttribute("Model", model) -- (a STAR gun: StoreController fills it, RebirthView.fillPicture)
	end
	return picture
end

local function modelPicture(
	parent: Instance,
	model: string?,
	icon: string,
	size: number,
	at: UDim2,
	z: number,
	rotation: number?
): GuiObject?
	return livePicture(parent, model, icon, size, {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at,
		Rotation = rotation or 0,
		ZIndex = z,
	})
end

-- Builds the 3D models of every picture under `root` that waits for one (livePicture).
function StoreView.fillModels(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("ImageLabel") then
			local name = d:GetAttribute("Model")
			if type(name) == "string" then
				d:SetAttribute("Model", nil)
				local view = d:FindFirstChild("View")
				local model, from = PictureModels.build(name)
				if model and view and view:IsA("ViewportFrame") then
					Pop.show(view, model, from)
				end
			end
		end
	end
end

-- A card's picture: the shop sheet's once uploaded, else its live model (nil when neither shows).
local function picture(parent: Instance, spec: StoreConfig.CardSpec, size: number, at: UDim2, z: number, rotation: number?): GuiObject?
	local sheet = spec.Sheet
	if sheet then
		local icon = ShopFx.icon(parent, sheet, size, {
			Name = "Picture",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at,
			Rotation = rotation or 0,
			ZIndex = z,
		})
		if icon then
			return icon
		end
	end
	if spec.Look == "Wheel" then
		local wheel = ShopFx.wheel(parent, size, { Name = "Picture", AnchorPoint = Vector2.new(0.5, 0.5), Position = at, ZIndex = z })
		return wheel
	end
	return modelPicture(parent, spec.Model, spec.Icon, size, at, z, rotation)
end

-- Will this card show a picture in the game (a live model, a STAR gun, a drawn wheel, an uploaded icon)?
function StoreView.hasPicture(spec: StoreConfig.CardSpec): boolean
	if spec.Sheet and IconAssets.shopShows(spec.Sheet) then
		return true
	end
	if spec.Look == "Wheel" then
		return true
	end
	local name = spec.Model
	if name and string.sub(name, 1, 5) == "star_" then
		return true
	end
	return name ~= nil and PictureModels.build(name) ~= nil
end

---------------------------------------------------------------- card pieces

local CORNER = StoreView.CardCorner

-- The card's colours (a STAR blaster's from its light).
local function paintOf(spec: StoreConfig.CardSpec): { Color3 }
	local glow = spec.GlowColor
	if glow and spec.Paint ~= "Mythic" then
		return { glow:Lerp(WHITE, 0.45), glow:Lerp(Color3.new(0, 0, 0), 0.25), glow:Lerp(Color3.new(0, 0, 0), 0.62) }
	end
	return ShopFx.Cards[spec.Paint] or ShopFx.Cards.Purple
end

type ShellOptions = {
	Rays: UDim2?,
	RayLength: number?,
	RayFade: number?,
	Rainbow: boolean?,
	Glow: UDim2?,
	GlowRadius: number?,
	GlowColor: Color3?,
	Mythic: boolean?,
	Selectable: boolean?,
	Rotation: number?,
}

--[[
	A card's body in its holder: the dark slab under it, the face (the click
	target; it clips its light), rays and a glow behind where the picture
	goes, the gloss, the light edge, a darker band along the bottom; the
	Mythic rim when asked. Returns the face.
]]
local function shell(holder: Frame, colors: { Color3 }, h: number, o: ShellOptions): TextButton
	ShopFx.drop(holder, CORNER, 7, 1)
	local selectable = o.Selectable ~= false
	local face = UIKit.new("TextButton", {
		Name = "Face",
		Active = selectable,
		AutoButtonColor = false,
		ClipsDescendants = true,
		Selectable = selectable,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 2,
	}, holder)
	ShopFx.face(face, colors, CORNER, 4, o.Rotation or 70)
	if #colors > 3 then
		local paint = face:FindFirstChild("Paint")
		if paint and paint:IsA("UIGradient") then
			paint.Rotation = o.Rotation or 30
		end
	end
	if o.Rays then
		ShopFx.rays(face, o.Rays, 6, o.RayLength or 180, o.RayFade or 0.62, 2, if o.Rainbow then ShopFx.Cards.Rainbow else nil)
	end
	if o.Glow then
		ShopFx.glow(face, o.Glow, o.GlowRadius or 80, o.GlowColor or WHITE, 2)
	end
	ShopFx.gloss(face, CORNER, 3)
	ShopFx.rim(face, CORNER, 3)
	-- the darker band along the bottom (inset 0 -8px 0): its corners follow the face's
	local band = UIKit.new("Frame", {
		Name = "Band",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, face)
	UIKit.corner(band, CORNER)
	local cut = 1 - 7 / math.max(h, 40)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(cut - 0.002, 1),
			NumberSequenceKeypoint.new(cut, 0.8),
			NumberSequenceKeypoint.new(1, 0.8),
		}),
	}, band)
	if o.Mythic then
		ShopFx.mythicRim(face, 5)
	end
	return face
end

-- The dark cover over a card that waits (a buy on its way) or is locked.
local function shade(holder: Frame): Frame
	local cover = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = ShopFx.Outline,
		BackgroundTransparency = 0.42,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 14,
	}, holder)
	UIKit.corner(cover, CORNER)
	return cover
end

-- The grey OWNED button that takes a pass's price's place once it is bought.
local function ownedTag(holder: Frame, size: Vector2, props: { [string]: any }): Frame
	local owned = ShopFx.buttonTag(holder, "OWNED", size, "Grey", props)
	owned.Name = "Owned"
	owned.Visible = false
	return owned
end

-- A card's bare refs (the looks fill them in).
local function newRefs(spec: StoreConfig.CardSpec, holder: Frame, face: TextButton): CardRefs
	return {
		Spec = spec,
		Holder = holder,
		Button = face,
		Title = nil,
		Amount = nil,
		Description = nil,
		Note = nil,
		Big = nil,
		Picture = nil,
		Price = face, -- (set by addPrice)
		PriceAmount = (nil :: any) :: TextLabel,
		Buys = {},
		Owned = (nil :: any) :: Frame,
		Shade = shade(holder),
		Sticker = nil,
		Key = spec.Keys[1],
		State = "Buy",
	}
end

--[[
	A price button for `key` on the card (`size`, placed by `props`), its
	OWNED tag in the same place for the first one. One-price cards: the
	face is the gamepad stop, so the button is not (Selectable false).
]]
local function addPrice(
	refs: CardRefs,
	key: string,
	size: Vector2,
	style: string,
	props: { [string]: any },
	label: string?
): ShopFx.PriceButton
	local product = MonetizationConfig.Products[key]
	local button = ShopFx.priceButton(refs.Holder, product.Robux, size, style, props, label)
	button.Holder.Name = "Price" .. key
	button.Face:SetAttribute("Key", key)
	button.Face:SetAttribute("Odds", StoreView.needsOdds(refs.Spec, key))
	local multi = refs.Spec.Options ~= nil and #(refs.Spec.Options :: { string }) > 1
	button.Face.Selectable = multi
	local first = next(refs.Buys) == nil
	refs.Buys[key] = button.Face
	if first then
		refs.Price = button.Face
		refs.PriceAmount = button.Amount
		refs.Owned = ownedTag(refs.Holder, size, props)
	end
	return button
end

-- A sticker over the card's top edge (`x` its middle as a share of the width).
local function cardSticker(refs: CardRefs, text: string, style: string, x: number, size: number?): Frame
	local sticker = ShopFx.sticker(refs.Holder, text, style, UDim2.new(x, 0, 0, -9), size or 15, -4, 12)
	refs.Sticker = sticker
	return sticker
end

-- A card's title across its top.
local function cardTitle(refs: CardRefs, text: string, size: number, top: number, lines: number?): TextLabel
	local title = ShopFx.text(refs.Holder, text, size, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top),
		Size = UDim2.new(1, -16, 0, math.floor(size * 1.12 * (lines or 1)) + 4),
		TextWrapped = (lines or 1) > 1,
		ZIndex = 7,
	})
	ShopFx.limit(title, size, math.floor(size * 0.6))
	refs.Title = title
	return title
end

-- A short white line (centre aligned, wrapping) `height` units tall.
local function cardLine(refs: CardRefs, text: string, size: number, props: { [string]: any }, name: string?): TextLabel
	props.Name = name or "Description"
	local line = ShopFx.text(refs.Holder, text, size, props, nil, 1)
	line.TextWrapped = true
	local copy = ShopFx.shadowOf(line)
	if copy then
		copy.TextWrapped = true
	end
	ShopFx.limit(line, size, math.floor(size * 0.7))
	return line
end

---------------------------------------------------------------- the card looks

type Build = (holder: Frame, spec: StoreConfig.CardSpec, w: number, h: number, m: Metrics) -> CardRefs

local Looks: { [string]: Build } = {}

-- The Forgemaster's Pass: the crown, the gradient title, its lines, a gold price (wide: two columns).
Looks.Bundle = function(holder, spec, w, h, m)
	local short = h < 200 + m.Extra
	local crown = if short then math.min(h - 24, 146) else math.min(h - 46 - m.Extra, 168)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.fromOffset(70, 40),
		RayLength = 210,
		RayFade = 0.66,
		Glow = UDim2.fromOffset(16 + math.floor(crown / 2), math.floor(h / 2)),
		GlowRadius = math.floor(crown * 0.62),
		GlowColor = hex("#ffdc5a"),
	})
	local refs = newRefs(spec, holder, face)
	refs.Picture = picture(holder, spec, crown, UDim2.fromOffset(16 + math.floor(crown / 2), math.floor(h / 2) - 4), 5)
	local left = crown + 30
	local product = MonetizationConfig.Products[spec.Keys[1]]
	local titleSize = if short then 40 else 35
	local title = ShopFx.title(holder, spec.Title or product.Name, titleSize, { WHITE, WHITE, hex("#ffe07a") }, {
		Name = "Title",
		Position = UDim2.fromOffset(left, if short then 12 else 12),
		Size = UDim2.new(1, -(left + 16), 0, titleSize + 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, hex("#2a0a5a"))
	ShopFx.limit(title, titleSize, 20)
	refs.Title = title
	local lines: { string } = spec.Lines or {}
	local icons: { string } = spec.LineIcons or {}
	local lineSize = if short then 18 else 17
	local priceW, priceH = if short then 190 else 168, m.Button + (if short then 12 else 6)
	for i, text in lines do
		local col = if short then (i - 1) % 2 else 0
		local row = if short then (i - 1) // 2 else i - 1
		local x = left + col * 300
		local y = (if short then 66 else 56) + row * (lineSize + (if short then 8 else 6))
		local icon = ShopFx.icon(holder, icons[i] or "", lineSize + 6, {
			Name = "LineIcon" .. i,
			Position = UDim2.fromOffset(x, y - 3),
			ZIndex = 7,
		})
		local tx = if icon then x + lineSize + 10 else x
		local label = ShopFx.text(holder, (if icon then "" else "+ ") .. text, lineSize, {
			Name = "Line" .. i,
			Position = UDim2.fromOffset(tx, y),
			Size = UDim2.fromOffset(if short then 290 - (tx - x) else math.max(120, w - tx - 16), lineSize + 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		}, nil, 2)
		if not short then
			-- (the lines keep clear of the price button in the bottom-right corner)
			local bottom = y + lineSize + 4
			if bottom > h - 16 - priceH then
				label.Size = UDim2.fromOffset(math.max(120, w - tx - priceW - 30), lineSize + 4)
			end
		end
		ShopFx.limit(label, lineSize, 11)
	end
	local at: { [string]: any } = if short
		then { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0), ZIndex = 8 }
		else { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), ZIndex = 8 }
	addPrice(refs, spec.Keys[1], Vector2.new(priceW, priceH), if spec.Gold then "Gold" else "Green", at)
	return refs
end

-- The Starter Pack: its golem, its coins and its podium skin in slots, the price.
Looks.Starter = function(holder, spec, w, h, m)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, 30),
		RayLength = 190,
		RayFade = 0.7,
	})
	local refs = newRefs(spec, holder, face)
	cardTitle(refs, spec.Title or "Starter Pack", 26, 8)
	local product = MonetizationConfig.Products[spec.Keys[1]]
	local slotW, slotH, plus = 84, 96, 26
	local x0 = math.floor((w - (3 * slotW + 2 * plus)) / 2)
	local y = 46
	local golem = GolemConfig.ById[product.Golem or ""]
	local words = {
		if golem then `{golem.Rarity} golem` else "Golem",
		"$0",
		"Podium skin",
	}
	local models = { "golem_" .. (product.Golem or "GildedPorter"), "cash_stack", "podium" }
	for i = 1, 3 do
		local slot = UIKit.new("Frame", {
			Name = "Slot" .. i,
			Position = UDim2.fromOffset(x0 + (i - 1) * (slotW + plus), y),
			Size = UDim2.fromOffset(slotW, slotH),
			ZIndex = 5,
		}, holder)
		ShopFx.face(slot, { hex("#3a2a6a"), hex("#1e1440") }, 12, 3)
		modelPicture(slot, models[i], models[i], 62, UDim2.new(0.5, 0, 0, 40), 6)
		ShopFx.text(slot, "x1", 14, {
			Name = "Count",
			Position = UDim2.fromOffset(0, -3),
			Size = UDim2.new(1, 0, 0, 18),
			ZIndex = 8,
		}, nil, 1)
		local word = ShopFx.text(slot, words[i], 12, {
			Name = "Word",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, -6, 0, 16),
			ZIndex = 8,
		}, nil, 1)
		ShopFx.limit(word, 13, 8)
		if i == 2 then
			refs.Amount = word
		end
		if i < 3 then
			ShopFx.text(holder, "+", 36, {
				Name = "Plus" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x0 + i * slotW + (i - 1) * plus + math.floor(plus / 2), y + math.floor(slotH / 2)),
				Size = UDim2.fromOffset(plus + 10, 40),
				ZIndex = 8,
			})
		end
	end
	local priceH = m.Button + 4
	addPrice(refs, spec.Keys[1], Vector2.new(150, priceH), "Green", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		ZIndex = 8,
	})
	-- (Once = true: one per player, StarterPackService)
	local once = ShopFx.text(holder, "Once per player", 15, {
		Name = "Once",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 1, -(14 + math.floor(priceH / 2))),
		Size = UDim2.new(1, -190, 0, 20),
		TextColor3 = hex("#fff27a"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	ShopFx.limit(once, 15, 10)
	return refs
end

-- A coin pack: the coins at the player's income (setCoins), its name, picture, how long, price.
Looks.Coins = function(holder, spec, w, h, m)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, math.floor(h * 0.47)),
		RayLength = 200,
		RayFade = 0.66,
		Glow = UDim2.new(0.5, 0, 0, math.floor(h * 0.47)),
		GlowRadius = 84,
	})
	local refs = newRefs(spec, holder, face)
	local product = MonetizationConfig.Products[spec.Keys[1]]
	local amount = ShopFx.title(holder, "$0", 37, { WHITE, WHITE, hex("#d8ffb0") }, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -12, 0, 44),
		ZIndex = 7,
	}, hex("#0d3b06"))
	ShopFx.limit(amount, 37, 18)
	refs.Amount = amount
	local name = ShopFx.text(holder, product.Name, 15, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(1, -12, 0, 20),
		ZIndex = 7,
	}, nil, 1)
	ShopFx.limit(name, 15, 10)
	refs.Title = name
	refs.Picture = picture(holder, spec, 128, UDim2.new(0.5, 0, 0, math.floor(h * 0.47)), 5)
	local chipY = h - 14 - (m.Button + 4) - 12 - 28
	ShopFx.chip(holder, `{StoreView.duration(product.CoinSeconds or 0)} of income`, w - 28, 28, 15, {
		Name = "Time",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, chipY),
	})
	addPrice(refs, spec.Keys[1], Vector2.new(w - 28, m.Button + 4), "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		ZIndex = 8,
	})
	local sticker = cardSticker(refs, "BEST VALUE!", "Red", 0.5, 14)
	sticker.Visible = false
	return refs
end

-- A game pass: its title, picture, short line, the price (OWNED after).
Looks.Pass = function(holder, spec, w, h, m)
	local rainbow = spec.Paint == "Rainbow"
	local picY = math.floor(h * 0.42)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, picY),
		RayLength = 200,
		RayFade = if spec.Paint == "Night" then 0.82 else 0.66,
		Glow = UDim2.new(0.5, 0, 0, picY),
		GlowRadius = 80,
		Rotation = if rainbow then 30 else nil,
	})
	local refs = newRefs(spec, holder, face)
	if spec.Paint == "Night" then
		ShopFx.dots(face, 16, w, h - 60, { WHITE, hex("#fff27a") }, 41, 3, 3)
	end
	local product = MonetizationConfig.Products[spec.Keys[1]]
	cardTitle(refs, spec.Title or product.Name, 21, 10, 2)
	local size = math.min(w - 40, 140)
	refs.Picture = picture(holder, spec, size, UDim2.new(0.5, 0, 0, picY), 5)
	if spec.Id == "DoubleMoney" then
		ShopFx.x2(holder, 62, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 44, 0, picY - 48), ZIndex = 9 })
	end
	local priceH = m.Button + 4
	refs.Description = cardLine(refs, spec.Short or product.Description, 14, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(14 + priceH + 10)),
		Size = UDim2.new(1, -16, 0, 40),
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = 7,
	})
	addPrice(refs, spec.Keys[1], Vector2.new(w - 28, priceH), "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		ZIndex = 8,
	})
	return refs
end

-- The next blaster level: the levels (setBig), the gun, the price.
Looks.Blaster = function(holder, spec, w, h, m)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(1, -96, 0, math.floor(h * 0.48)),
		RayLength = 200,
		RayFade = 0.62,
		Glow = UDim2.new(1, -96, 0, math.floor(h * 0.48)),
		GlowRadius = 100,
		GlowColor = hex("#ffe68c"),
	})
	local refs = newRefs(spec, holder, face)
	ShopFx.bolt(face, Vector2.new(-8, h - 50), Vector2.new(math.floor(w * 0.5), h - 110), hex("#ffd84a"), 3.4, 71, 1, 3, 0.31, 3, false)
	local product = MonetizationConfig.Products[spec.Keys[1]]
	local title = ShopFx.title(holder, spec.Title or product.Name, 36, { WHITE, WHITE, hex("#ffe07a") }, {
		Name = "Title",
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -30, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, hex("#3a0610"))
	ShopFx.limit(title, 36, 20)
	refs.Title = title
	refs.Description = cardLine(refs, spec.Short or "", 16, {
		Position = UDim2.fromOffset(20, 58),
		Size = UDim2.new(0.62, -20, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 7,
	})
	local chip = ShopFx.chip(holder, spec.Big or "", 168, 40, 25, {
		Name = "Levels",
		Position = UDim2.fromOffset(18, 100),
	}, { hex("#3a0a1a"), hex("#1a0410") })
	refs.Big = ShopFx.chipLabel(chip)
	refs.Picture = picture(holder, spec, 150, UDim2.new(1, -96, 0, math.floor(h * 0.48)), 5, -10)
	refs.Note = ShopFx.text(holder, spec.Note or "", 13, {
		Name = "Note",
		Position = UDim2.fromOffset(20, 146),
		Size = UDim2.new(0.6, -20, 0, 18),
		TextColor3 = hex("#ffe8a0"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, nil, 1)
	ShopFx.limit(refs.Note :: TextLabel, 13, 9)
	addPrice(refs, spec.Keys[1], Vector2.new(math.min(184, w - 40), m.Button + 6), "Green", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -16),
		ZIndex = 8,
	})
	return refs
end

-- A STAR blaster: its name, its power, the live gun, "Opens at rebirth N" while locked, the price.
Looks.Star = function(holder, spec, w, h, m)
	local strongest = spec.Star ~= nil and spec.Star == StoreView.strongest()
	local picY = math.floor(h * 0.47)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, picY),
		RayLength = 210,
		RayFade = if strongest then 0.55 else 0.68,
		Rainbow = strongest,
		Glow = UDim2.new(0.5, 0, 0, picY),
		GlowRadius = 90,
		GlowColor = if strongest then hex("#ff78a0") else hex("#a0f0ff"),
		Mythic = strongest,
	})
	local refs = newRefs(spec, holder, face)
	if strongest then
		ShopFx.bolt(
			face,
			Vector2.new(math.floor(w * 0.12), -8),
			Vector2.new(math.floor(w * 0.72), h - 70),
			hex("#ff8ab0"),
			2.6,
			90,
			1,
			3,
			0.57,
			3,
			false
		)
	end
	cardTitle(refs, spec.Title or spec.Id, 22, 8)
	local chip = ShopFx.chip(holder, spec.Big or "", 150, 28, 17, {
		Name = "Power",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
	}, { hex("#ffe07a"), hex("#f0960a") })
	local label = ShopFx.chipLabel(chip)
	if label then
		local edge = label:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			edge.Color = hex("#5a2c00")
		end
	end
	refs.Picture = picture(holder, spec, math.min(w - 50, 190), UDim2.new(0.5, 0, 0, picY + 6), 5)
	ShopFx.icon(holder, "lock", 70, {
		Name = "Lock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, picY),
		Visible = false,
		ZIndex = 15,
	})
	local priceH = m.Button + 4
	local note = ShopFx.chip(holder, spec.Note or "", w - 28, 26, 14, {
		Name = "State",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(14 + priceH + 10)),
		ZIndex = 15,
	})
	local noteLabel = ShopFx.chipLabel(note)
	if noteLabel then
		noteLabel.TextColor3 = hex("#ffe48a")
		ShopFx.limit(noteLabel, 14, 9)
		refs.Note = noteLabel
		refs.Description = noteLabel
	end
	addPrice(refs, spec.Keys[1], Vector2.new(w - 28, priceH), "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		ZIndex = 8,
	})
	if strongest then
		cardSticker(refs, "STRONGEST!", "Gold", 0.3, 15)
	end
	return refs
end

-- A Royal egg pack: "Royal Egg", one or three eggs, the count, the price (the odds first).
Looks.Egg = function(holder, spec, w, h, m)
	local count = spec.Count or 1
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, math.floor(h * 0.46)),
		RayLength = 190,
		RayFade = if count >= 10 then 0.52 else 0.66,
		Rainbow = count >= 10,
		Glow = UDim2.new(0.5, 0, 0, math.floor(h * 0.46)),
		GlowRadius = 72,
	})
	local refs = newRefs(spec, holder, face)
	local product = MonetizationConfig.Products[spec.Keys[1]]
	local capsule = CapsuleConfig.ById[product.Capsule or ""]
	cardTitle(refs, spec.Title or (if capsule then capsule.Name else product.Name), 24, 10)
	local mid = math.floor(w / 2) - 8
	local y = math.floor(h * 0.46)
	if count == 1 then
		refs.Picture = modelPicture(holder, spec.Model, spec.Icon, 112, UDim2.fromOffset(mid, y), 5)
	else
		for k, dx in { -56, 56, 0 } do
			local big = dx == 0
			local pic = modelPicture(
				holder,
				spec.Model,
				spec.Icon,
				if big then 106 else 88,
				UDim2.fromOffset(mid + dx, y + (if big then -4 else 10)),
				if big then 6 else 5
			)
			if k == 3 then
				refs.Picture = pic
			end
		end
	end
	ShopFx.title(holder, spec.Big or `x{count}`, 43, { WHITE, WHITE, hex("#ffe07a") }, {
		Name = "Big",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0, y + 26),
		Size = UDim2.fromOffset(110, 50),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 9,
	})
	addPrice(refs, spec.Keys[1], Vector2.new(w - 26, m.Button + 4), "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -13),
		ZIndex = 8,
	})
	local sticker = cardSticker(refs, "BEST VALUE!", "Gold", 0.62, 14)
	sticker.Visible = false
	return refs
end

-- Server Luck: x1 -> x2 ore luck for the whole server, the clover, the price.
Looks.ServerLuck = function(holder, spec, w, h, m)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.fromOffset(130, math.floor(h * 0.58)),
		RayLength = 240,
		RayFade = 0.6,
		Glow = UDim2.fromOffset(120, math.floor(h * 0.58)),
		GlowRadius = 112,
	})
	local refs = newRefs(spec, holder, face)
	ShopFx.bolt(
		face,
		Vector2.new(math.floor(w * 0.5), -10),
		Vector2.new(math.floor(w * 0.62), h + 4),
		hex("#fff27a"),
		3.4,
		53,
		2,
		3,
		0.11,
		3,
		false
	)
	ShopFx.dots(face, 14, w, h, { WHITE, hex("#fff27a") }, 77, 3, 3)
	local product = MonetizationConfig.Products[spec.Keys[1]]
	cardTitle(refs, spec.Title or product.Name, 35, 8)
	local minutes = math.floor((product.Seconds or 0) / 60 + 0.5)
	local mult = BoostView.ServerLuckMult
	refs.Description = cardLine(refs, `x{mult} ore luck for everyone on this server, +{minutes} min a buy`, 16, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.new(1, -24, 0, 22),
		ZIndex = 7,
	})
	refs.Picture = picture(holder, spec, math.min(h - 80, 176), UDim2.fromOffset(120, math.floor(h * 0.6)), 5)
	local y = math.floor(h * 0.6)
	ShopFx.title(holder, "x1", 70, { WHITE, hex("#d8ffc0") }, {
		Name = "From",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(282, y),
		Size = UDim2.fromOffset(120, 80),
		ZIndex = 8,
	})
	local arrow = ShopFx.icon(holder, "bolt", 60, {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(372, y),
		ZIndex = 8,
	})
	if not arrow then
		ShopFx.text(holder, ">", 56, {
			Name = "Arrow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(372, y),
			Size = UDim2.fromOffset(60, 70),
			TextColor3 = hex("#ffe05a"),
			ZIndex = 8,
		})
	end
	ShopFx.title(holder, `x{mult}`, 90, { hex("#fffbd0"), hex("#ffd23a"), hex("#ff9a1a") }, {
		Name = "To",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(468, y - 6),
		Size = UDim2.fromOffset(160, 100),
		ZIndex = 8,
	})
	refs.Note = ShopFx.text(holder, "", 15, {
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -16),
		Size = UDim2.new(1, -230, 0, 20),
		TextColor3 = hex("#fff27a"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, nil, 1)
	addPrice(refs, spec.Keys[1], Vector2.new(170, m.Button + 8), "Green", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		ZIndex = 8,
	})
	return refs
end

-- A card with an option row (wheel spins, the luck packs): two-line buttons, the best value gold.
local function options(refs: CardRefs, w: number, m: Metrics, sticker: boolean)
	local keys: { string } = refs.Spec.Options or refs.Spec.Keys
	local gap = 8
	local bw = math.floor((w - 24 - gap * (#keys - 1)) / #keys)
	local best = StoreView.bestValue(keys)
	for i, key in keys do
		local look = if key == best then "Gold" else "Green"
		addPrice(refs, key, Vector2.new(bw, m.Button + 14), look, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12 + (i - 1) * (bw + gap), 1, -13),
			ZIndex = 8,
		}, StoreView.optionLabel(key))
	end
	if best and sticker then
		local index = table.find(keys, best) or 1
		local x = (12 + (index - 1) * (bw + gap) + bw / 2) / w
		local tag = ShopFx.sticker(refs.Holder, "BEST VALUE!", "Gold", UDim2.new(x, 0, 1, -(13 + m.Button + 14 + 13)), 11, 5, 12)
		tag.Name = "Best"
	end
end

-- Spin & Win spins: the wheel, three option buttons (the odds first).
Looks.Wheel = function(holder, spec, w, h, m)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, 98),
		RayLength = 190,
		RayFade = 0.64,
		Glow = UDim2.new(0.5, 0, 0, 98),
		GlowRadius = 80,
	})
	local refs = newRefs(spec, holder, face)
	face.Selectable = false
	face.Active = false
	cardTitle(refs, spec.Title or "Wheel Spins", 26, 8)
	refs.Picture = picture(holder, spec, math.min(124, h - 130 - m.Extra), UDim2.new(0.5, 0, 0, 100), 5)
	options(refs, w, m, true)
	return refs
end

-- Triple / Hexa Lucky: the clover, the multiplier, a line, 15 min / 1 hour (the new odds first).
Looks.Luck = function(holder, spec, w, h, m)
	local picY = math.floor(h * 0.38)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, picY),
		RayLength = 190,
		RayFade = 0.64,
		Glow = UDim2.new(0.5, 0, 0, picY),
		GlowRadius = 72,
	})
	local refs = newRefs(spec, holder, face)
	face.Selectable = false
	face.Active = false
	local product = MonetizationConfig.Products[spec.Keys[1]]
	cardTitle(refs, spec.Title or product.Name, 24, 8)
	refs.Picture = picture(holder, spec, 104, UDim2.new(0.5, -14, 0, picY), 5)
	ShopFx.title(holder, spec.Big or "", 42, { hex("#fffbd0"), hex("#ffd23a"), hex("#ff9a1a") }, {
		Name = "Big",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, picY + 30),
		Size = UDim2.fromOffset(100, 50),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 9,
	})
	refs.Description = cardLine(refs, spec.Short or "", 14, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(13 + m.Button + 14 + 18)),
		Size = UDim2.new(1, -16, 0, 20),
		ZIndex = 7,
	})
	options(refs, w, m, false)
	return refs
end

-- A Mythic enchant's pass: the gem, its effects (EnchantConfig), the price.
Looks.Enchant = function(holder, spec, w, h, m)
	local product = MonetizationConfig.Products[spec.Keys[1]]
	local enchant = EnchantConfig.ById[product.Enchant or ""]
	local mythic = enchant ~= nil and enchant.Rarity == "Mythic"
	local picY = math.floor(h * 0.4)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.new(0.5, 0, 0, picY),
		RayLength = 200,
		RayFade = if mythic then 0.55 else 0.64,
		Rainbow = mythic,
		Glow = UDim2.new(0.5, 0, 0, picY),
		GlowRadius = 78,
		GlowColor = if enchant then enchant.Color:Lerp(WHITE, 0.4) else WHITE,
		Mythic = mythic,
	})
	local refs = newRefs(spec, holder, face)
	cardTitle(refs, spec.Title or (if enchant then enchant.Name else product.Name), 24, 8)
	refs.Picture = picture(holder, spec, 112, UDim2.new(0.5, 0, 0, picY), 5)
	local priceH = m.Button + 4
	refs.Description = cardLine(refs, StoreView.enchantLine(product.Enchant), 14, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(13 + priceH + 8)),
		Size = UDim2.new(1, -16, 0, 36),
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = 7,
	})
	addPrice(refs, spec.Keys[1], Vector2.new(w - 26, priceH), "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -13),
		ZIndex = 8,
	})
	if enchant then
		cardSticker(refs, `{string.upper(enchant.Rarity)}!`, if mythic then "Gold" else "Pink", 0.32, 14)
	end
	return refs
end

-- The 2x Money pass as a wide band: the cash and x2, the title, its line, the price.
Looks.MoneyWide = function(holder, spec, w, h, m)
	local face = shell(holder, paintOf(spec), h, {
		Rays = UDim2.fromOffset(80, 40),
		RayLength = 260,
		RayFade = 0.62,
		Glow = UDim2.fromOffset(80, math.floor(h / 2)),
		GlowRadius = 80,
	})
	local refs = newRefs(spec, holder, face)
	ShopFx.bolt(face, Vector2.new(w + 6, 8), Vector2.new(w - 300, h - 10), WHITE, 2.6, 67, 1, 3, 0.83, 3, false)
	refs.Picture = picture(holder, spec, h - 30, UDim2.fromOffset(16 + math.floor((h - 30) / 2), math.floor(h / 2) + 2), 5)
	ShopFx.x2(holder, 58, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(h - 4, 30), ZIndex = 9 })
	local product = MonetizationConfig.Products[spec.Keys[1]]
	local left = h + 34
	local title = ShopFx.title(holder, spec.Title or product.Name, 40, { WHITE, WHITE, hex("#fff2a0") }, {
		Name = "Title",
		Position = UDim2.fromOffset(left, 16),
		Size = UDim2.new(1, -(left + 240), 0, 48),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, hex("#5a2c00"))
	ShopFx.limit(title, 40, 20)
	refs.Title = title
	refs.Description = cardLine(refs, spec.Short or product.Description, 17, {
		Position = UDim2.fromOffset(left + 2, 70),
		Size = UDim2.new(1, -(left + 250), 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 7,
	})
	addPrice(refs, spec.Keys[1], Vector2.new(190, m.Button + 12), "Green", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.5, 0),
		ZIndex = 8,
	})
	return refs
end

---------------------------------------------------------------- banners

-- A golem tile: its rarity's colours, rays, the live golem, its rarity and chance.
local function golemTile(
	parent: Instance,
	golem: { Id: string, Name: string, Rarity: string },
	at: UDim2,
	size: Vector2,
	z: number,
	named: boolean
): TextLabel
	local rarity = Rarity.get(golem.Rarity)
	local mythic = golem.Rarity == "Mythic"
	local paints = {
		Uncommon = ShopFx.Cards.Green,
		Rare = ShopFx.Cards.Blue,
		Epic = ShopFx.Cards.Purple,
		Legendary = ShopFx.Cards.Gold,
		Mythic = ShopFx.Cards.Mythic,
	} :: { [string]: { Color3 } }
	local holder = UIKit.new("Frame", {
		Name = "Golem" .. golem.Id,
		BackgroundTransparency = 1,
		Position = at,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = z,
	}, parent)
	ShopFx.drop(holder, 14, 5, z)
	local face = UIKit.new("Frame", {
		Name = "Face",
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
	}, holder)
	ShopFx.face(face, paints[golem.Rarity] or { rarity.Color, rarity.DarkColor }, 14, 4, 70)
	local rare = mythic or golem.Rarity == "Legendary"
	ShopFx.rays(
		face,
		UDim2.new(0.5, 0, 0.45, 0),
		6,
		math.floor(size.X * 0.9),
		if rare then 0.5 else 0.7,
		z + 1,
		if mythic then ShopFx.Cards.Rainbow else nil
	)
	ShopFx.gloss(face, 14, z + 2, 0.3)
	ShopFx.rim(face, 14, z + 2)
	if mythic then
		ShopFx.mythicRim(face, 4)
	end
	local pic = math.floor(math.min(size.X - 12, size.Y * (if named then 0.52 else 0.7)))
	livePicture(holder, "golem_" .. golem.Id, "golem_" .. golem.Id, pic, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, if named then math.floor(size.Y * 0.42) else math.floor(size.Y * 0.46)),
		ZIndex = z + 3,
	})
	local chance: TextLabel
	if named then
		-- (the Royal Egg's tiles: the chance on top, the name and the rarity under the golem)
		chance = ShopFx.text(holder, "", 19, {
			Name = "Chance",
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 24),
			ZIndex = z + 5,
		})
		local name = ShopFx.text(holder, golem.Name, 15, {
			Name = "GolemName",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, math.floor(size.Y * 0.68)),
			Size = UDim2.new(1, -8, 0, 36),
			TextWrapped = true,
			ZIndex = z + 5,
		}, nil, 1)
		ShopFx.limit(name, 15, 9)
		ShopFx.text(holder, string.upper(golem.Rarity), 14, {
			Name = "Rarity",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -6, 0, 18),
			TextColor3 = if mythic then hex("#ff8ab0") else hex("#fff3a0"),
			ZIndex = z + 5,
		}, nil, 1)
	else
		ShopFx.text(holder, golem.Rarity, 12, {
			Name = "Rarity",
			Position = UDim2.fromOffset(6, 2),
			Size = UDim2.new(1, -8, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = z + 5,
		}, nil, 1)
		chance = ShopFx.text(holder, "", 24, {
			Name = "Chance",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -6, 1, -2),
			Size = UDim2.new(1, -8, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = z + 5,
		})
	end
	return chance
end

--[[
	The limited edition banner (owner 2026-10-20 "like the Halloween egg"; the
	WOW concept's DRAGONFORGE): flames and embers along the bottom, rays
	behind the rarest golem, LIMITED EDITION GOLEMS and the edition's title,
	its tagline, the real end date and a quiet time left, the four buy
	buttons (1 / 3 / 10 / 50, the odds first), the rarest golem big with its
	chance, the shard egg, and a tile per golem with its chance.
]]
local function buildBanner(page: Frame, edition: Edition, m: Metrics): BannerRefs
	local section = StoreConfig.SectionById.Featured
	local w = StoreView.ContentWidth
	local h = (section.BannerHeight or 306) + 2 * m.Extra
	local frame = UIKit.new("Frame", {
		Name = "Limited",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h),
		ZIndex = 2,
	}, page)
	ShopFx.drop(frame, CORNER, 7, 1)
	local face = UIKit.new("Frame", {
		Name = "Face",
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, frame)
	ShopFx.face(face, ShopFx.Cards.Fire, CORNER, 4, 90)
	ShopFx.rays(face, UDim2.fromOffset(560, 70), 10, 300, 0.62, 2, { hex("#ffe68c") })
	-- the flames along the bottom and the embers rising
	local rand = ShopFx.random(11)
	for i = 0, 13 do
		local fw = 70 + math.floor(rand() * 40)
		local fh = 50 + math.floor(rand() * 70)
		local flame = UIKit.new("Frame", {
			Name = "Flame",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = if i % 2 == 0 then hex("#ff7a1e") else hex("#ff4a1a"),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Position = UDim2.new(0, i * 76 + math.floor(rand() * 20), 1, 20),
			Size = UDim2.fromOffset(fw, fh + 20),
			ZIndex = 2,
		}, face)
		UIKit.corner(flame, math.floor(fw / 2))
	end
	ShopFx.dots(face, 30, w, h, { hex("#ffd84a"), hex("#ff9a3a"), WHITE }, 12, 2, 3)
	ShopFx.bolt(face, Vector2.new(470, -10), Vector2.new(540, 170), hex("#ffd84a"), 3.8, 23, 2, 3, 0.07, 3, false)
	ShopFx.gloss(face, CORNER, 3, 0.22)
	ShopFx.rim(face, CORNER, 3)
	-- the set's painted background over the drawn one, once the owner has uploaded it
	local image = edition.Backdrop.Image
	if type(image) == "number" and image > 0 then
		local painted = UIKit.new("ImageLabel", {
			Name = "Painted",
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. tostring(image),
			ScaleType = Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}, face)
		painted:SetAttribute("Icon", "banner_" .. edition.Id)
		UIKit.corner(painted, CORNER)
	end
	-- the words (top-left)
	ShopFx.sticker(frame, "LIMITED!", "Pink", UDim2.fromOffset(62, 18), 20, -10, 12)
	ShopFx.text(frame, "LIMITED EDITION GOLEMS", 18, {
		Name = "Kind",
		Position = UDim2.fromOffset(124, 10),
		Size = UDim2.fromOffset(330, 24),
		TextColor3 = hex("#ffe9a0"),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
	}, nil, 2)
	local colors = edition.Backdrop.Title
	local title = ShopFx.title(
		frame,
		edition.Title,
		52,
		{ hex("#fffbd0"), colors[1] or hex("#ffd23a"), colors[#colors] or hex("#ff7a1a") },
		{
			Name = "Title",
			Position = UDim2.fromOffset(16, 32),
			Rotation = -3,
			Size = UDim2.fromOffset(440, 62),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 8,
		},
		hex("#3a0600")
	)
	ShopFx.limit(title, 52, 26)
	local tagline = ShopFx.text(frame, edition.Tagline, 18, {
		Name = "Tagline",
		Position = UDim2.fromOffset(24, 92),
		Size = UDim2.fromOffset(420, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
	}, nil, 2)
	ShopFx.limit(tagline, 18, 11)
	local ends = ShopFx.chip(frame, StoreView.endsOn(edition.EndsAt), 352, 28, 17, {
		Name = "Ends",
		Position = UDim2.fromOffset(26, 118),
	}, { hex("#5a0a2a"), hex("#2a0418") })
	local clock = ShopFx.icon(ends, "clock", 38, {
		Name = "Clock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(4, 14),
		ZIndex = 12,
	})
	local timer = ShopFx.chipLabel(ends) :: TextLabel
	if clock then
		ShopFx.place(timer, UDim2.fromOffset(26, 0), UDim2.new(1, -32, 1, 0))
	end
	ShopFx.limit(timer, 17, 10)
	-- the four buy buttons (two rows of two), the count over each price
	local buys: { [number]: TextButton } = {}
	local counts = { 1, 3, 10, 50 }
	local keys: { string } = {}
	for _, n in counts do
		local key = edition.Products[n]
		if key and MonetizationConfig.Products[key] then
			table.insert(keys, key)
		end
	end
	local best = StoreView.bestValue(keys)
	local styles = { [1] = "Green", [3] = "Green", [10] = "Purple", [50] = "Red" } :: { [number]: string }
	local bw, bh = 172, m.Button + 10
	for i, n in counts do
		local key = edition.Products[n]
		local product = if key then MonetizationConfig.Products[key] else nil
		if key and product then
			local col, row = (i - 1) % 2, (i - 1) // 2
			local x = 20 + col * (bw + 14)
			local y = h - 16 - (2 - row) * bh - (1 - row) * 26
			local button = ShopFx.priceButton(frame, product.Robux, Vector2.new(bw, bh), styles[n] or "Green", {
				Name = "Buy" .. n,
				Position = UDim2.fromOffset(x, y),
				ZIndex = 8,
			}, `{n} Golem{if n == 1 then "" else "s"}`)
			button.Face:SetAttribute("Key", key)
			button.Face:SetAttribute("Odds", true) -- (a paid random capsule: the odds first)
			buys[n] = button.Face
			if key == best then
				-- (in the gap over its button: the count on the button stays clear)
				ShopFx.sticker(frame, "BEST VALUE!", "Gold", UDim2.fromOffset(x + math.floor(bw / 2), y - 13), 12, -3, 13)
			end
		end
	end
	-- the rarest golem big, the shard egg, its chance
	local count = #edition.Golems
	local hero = edition.Golems[count]
	ShopFx.glow(face, UDim2.fromOffset(512, math.floor(h * 0.5)), 150, hex("#ffdc78"), 2, 1)
	if hero then
		livePicture(frame, "golem_" .. hero.Id, "golem_" .. hero.Id, 226, {
			Name = "Hero",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(510, math.floor(h * 0.44)),
			ZIndex = 6,
		})
	end
	if edition.CapsuleId then
		local shardName = "capsule_" .. edition.CapsuleId
		livePicture(frame, shardName, shardName, 100, {
			Name = "Shard",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(430, h - 70),
			Rotation = -12,
			ZIndex = 7,
		})
	end
	local heroChip = ShopFx.chip(frame, "", 190, 30, 16, {
		Name = "HeroChance",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(560, h - 44),
	}, { hex("#ff3a6a"), hex("#8a0a3a") })
	local heroLabel = ShopFx.chipLabel(heroChip) :: TextLabel
	-- a tile per golem: three a row, two rows, with its chance
	local chances: { [string]: TextLabel } = {}
	local tileW, gap = 112, 10
	local x0 = w - 14 - (3 * tileW + 2 * gap)
	local tileH = math.floor((h - 28 - gap) / 2)
	for i, golem in edition.Golems do
		local col, row = (i - 1) % 3, (i - 1) // 3
		chances[golem.Id] = golemTile(
			frame,
			golem,
			UDim2.fromOffset(x0 + col * (tileW + gap), 14 + row * (tileH + gap)),
			Vector2.new(tileW, tileH),
			6,
			false
		)
	end
	local lucky = ShopFx.chip(frame, "WITH TRIPLE LUCKY", 210, 26, 14, {
		Name = "Lucky",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(x0 - 10, 14),
		Visible = false,
	}, { hex("#b4ff6a"), hex("#3fd02a") })
	return {
		Frame = frame,
		Timer = timer,
		Buys = buys,
		Chances = chances,
		Lucky = ShopFx.chipLabel(lucky) :: TextLabel,
		Hero = heroLabel,
		Edition = edition,
	}
end

--[[
	The Royal Egg banner (the WOW concept's GOLEMS page): the egg, "=", and its
	golems with their chances (the odds a buy rolls now: Triple Lucky
	included), names and rarities; the line under the title counts them.
]]
local function buildRoyal(page: Frame): RoyalRefs?
	local capsule = CapsuleConfig.ById.Royal
	if not capsule then
		return nil
	end
	local section = StoreConfig.SectionById.Golems
	local w = StoreView.ContentWidth
	local h = section.BannerHeight or 292
	local frame = UIKit.new("Frame", {
		Name = "Royal",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h),
		ZIndex = 2,
	}, page)
	ShopFx.drop(frame, CORNER, 7, 1)
	local face = UIKit.new("Frame", {
		Name = "Face",
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, frame)
	ShopFx.face(face, ShopFx.Cards.Rainbow, CORNER, 4, 20)
	ShopFx.rays(face, UDim2.fromOffset(190, 170), 10, 320, 0.5, 2, ShopFx.Cards.Rainbow)
	-- the dark veil behind the tiles (linear-gradient 90deg: clear -> 0.55 at 30% -> 0.75)
	local veil = UIKit.new("Frame", {
		Name = "Veil",
		BackgroundColor3 = hex("#280a5a"),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, face)
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
	}, veil)
	ShopFx.bolt(face, Vector2.new(264, -10), Vector2.new(330, h + 6), WHITE, 3.2, 37, 3, 3, 0.47, 4, false)
	ShopFx.dots(face, 24, w, h, { WHITE, hex("#ffe07a"), hex("#7ff4ff") }, 29, 3, 3)
	ShopFx.gloss(face, CORNER, 3, 0.22)
	ShopFx.rim(face, CORNER, 3)
	local title = ShopFx.title(frame, capsule.Name, 50, { WHITE, WHITE, hex("#ffe07a") }, {
		Name = "Title",
		Position = UDim2.fromOffset(22, 8),
		Size = UDim2.fromOffset(300, 58),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
	}, hex("#2a0a5a"))
	ShopFx.limit(title, 50, 26)
	-- the golems inside, rarest last (the capsule's odds)
	local golems: { { Id: string, Name: string, Rarity: string } } = {}
	for _, line in CapsuleConfig.odds("Royal", false) do
		local golem = GolemConfig.ById[line.Golem]
		if golem then
			table.insert(golems, golem)
		end
	end
	local rarest = if #golems > 0 then golems[#golems].Rarity else ""
	local count = #golems
	ShopFx.text(frame, `{count} golems inside,\nup to a {string.upper(rarest)}!`, 18, {
		Name = "Tagline",
		Position = UDim2.fromOffset(26, 64),
		Size = UDim2.fromOffset(300, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 8,
	}, nil, 2)
	ShopFx.glow(face, UDim2.fromOffset(150, 200), 110, WHITE, 2, 1)
	livePicture(frame, "capsule_Royal", "capsule_Royal", 160, {
		Name = "Egg",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(150, 196),
		ZIndex = 6,
	})
	ShopFx.text(frame, "=", 72, {
		Name = "Equals",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(282, 176),
		Size = UDim2.fromOffset(70, 80),
		ZIndex = 8,
	})
	local chances: { [string]: TextLabel } = {}
	local x0, gap = 334, 10
	local tileW = math.floor((w - 16 - x0 - gap * (count - 1)) / math.max(count, 1))
	local tileH = h - 40
	for i, golem in golems do
		chances[golem.Id] = golemTile(frame, golem, UDim2.fromOffset(x0 + (i - 1) * (tileW + gap), 20), Vector2.new(tileW, tileH), 6, true)
	end
	local lucky = ShopFx.chip(frame, "WITH TRIPLE LUCKY", 210, 26, 14, {
		Name = "Lucky",
		Position = UDim2.fromOffset(26, h - 40),
		Visible = false,
	}, { hex("#b4ff6a"), hex("#3fd02a") })
	return { Frame = frame, Chances = chances, Lucky = ShopFx.chipLabel(lucky) :: TextLabel }
end

---------------------------------------------------------------- the window

-- A row's height on a page (a PC's, plus the taller buttons of a phone).
local function rowHeight(section: StoreConfig.Section, row: number, m: Metrics): number
	return (section.RowHeights[row] or section.RowHeights[#section.RowHeights] or 240) + m.Extra
end

-- The banner that opens a page (nil when it has none or it is gone).
local function bannerOf(refs: Refs, sectionId: string): Frame?
	if sectionId == "Featured" then
		local banner = refs.Banner
		return if banner then banner.Frame else nil
	elseif sectionId == "Golems" then
		local royal = refs.Royal
		return if royal and royal.Frame.Visible then royal.Frame else nil
	end
	return nil
end

-- The widths of a row's cards (the shown ones share the row by their Span).
local function rowWidths(specs: { StoreConfig.CardSpec }): { number }
	local spans = 0
	for _, spec in specs do
		spans += spec.Span or 1
	end
	local unit = (StoreView.ContentWidth - (#specs - 1) * StoreView.Gap) / math.max(spans, 1)
	local out = {}
	for _, spec in specs do
		table.insert(out, math.floor(unit * (spec.Span or 1)))
	end
	return out
end

--[[
	Places a page's banner and rows from the top: hidden cards close their
	row up, a row with nothing to show folds away. Returns the page's height
	and whether anything shows.
]]
local function placePage(refs: Refs, section: StoreConfig.Section): (number, boolean)
	local page = refs.Pages[section.Id]
	local m = refs.Metrics
	local y = 0
	local any = false
	local banner = bannerOf(refs, section.Id)
	if banner then
		banner.Position = UDim2.fromOffset(0, 0)
		y += banner.Size.Y.Offset + StoreView.RowGap
		any = true
	end
	for r, row in StoreConfig.rows(section.Id) do
		local shown: { CardRefs } = {}
		local specs: { StoreConfig.CardSpec } = {}
		for _, spec in row do
			local card = refs.Cards[spec.Id]
			if card and card.State ~= "Hidden" then
				table.insert(shown, card)
				table.insert(specs, spec)
			end
		end
		if #shown > 0 then
			any = true
			local h = rowHeight(section, r, m)
			local widths = rowWidths(specs)
			local x = 0
			for i, card in shown do
				card.Holder.Position = UDim2.fromOffset(x, y)
				card.Holder.Size = UDim2.fromOffset(widths[i], h)
				x += widths[i] + StoreView.Gap
			end
			y += h + StoreView.RowGap
		end
	end
	local height = math.max(0, y - StoreView.RowGap)
	page.Size = UDim2.fromOffset(StoreView.ContentWidth, height)
	return height, any
end

-- The ids of the tabs that show, in order.
function StoreView.visibleTabs(refs: Refs): { string }
	local out: { string } = {}
	for _, section in StoreConfig.Sections do
		local tab = refs.TabRefs[section.Id]
		if tab and tab.Holder.Visible then
			table.insert(out, section.Id)
		end
	end
	return out
end

-- Is tab `id` shown (it has something to sell)?
function StoreView.tabShown(refs: Refs, id: string): boolean
	local tab = refs.TabRefs[id]
	return tab ~= nil and tab.Holder.Visible
end

-- The open page's scroll room (its height plus the paddings).
local function sizeCanvas(refs: Refs)
	local page = refs.Pages[refs.Current]
	local h = if page then page.Size.Y.Offset else 0
	refs.Scroller.CanvasSize = UDim2.fromOffset(0, StoreView.PadTop + h + StoreView.PadBottom + 8)
end

StoreView.TabGap = 8
StoreView.TabMinWord = 14

-- Where the tabs start across the header (a PC's header has the big SHOP first).
local function tabsLeft(m: Metrics): number
	return if m.Compact then 78 else 240
end

-- A tab's width at word size `word`.
local function tabWidth(section: StoreConfig.Section, m: Metrics, word: number): number
	local icon = if m.Compact then math.floor(m.Tab * 0.86) else 46
	return math.floor(icon * 0.72) + ShopFx.textWidth(section.Tab, word) + 10
end

-- The tabs' word size: the metrics' when the six fit between SHOP and the X, else smaller (a small phone).
function StoreView.tabWord(m: Metrics): number
	local room = StoreView.Width - tabsLeft(m) - (m.Close + 14) - 12
	local word = m.Word
	while word > StoreView.TabMinWord do
		local total = (#StoreConfig.Sections - 1) * StoreView.TabGap
		for _, section in StoreConfig.Sections do
			total += tabWidth(section, m, word)
		end
		if total <= room then
			break
		end
		word -= 1
	end
	return word
end

-- The tabs' places across the header: the open one bigger and lifted (its white rim and glow on).
local function placeTabs(refs: Refs)
	local m = refs.Metrics
	local x = tabsLeft(m)
	for _, section in StoreConfig.Sections do
		local tab = refs.TabRefs[section.Id]
		if tab and tab.Holder.Visible then
			local open = section.Id == refs.Current
			tab.Holder.Position = UDim2.fromOffset(x + math.floor(tab.Width / 2), math.floor(m.Header / 2) + (if open then -3 else 1))
			-- (a phone's tabs never shrink under their 44 pt)
			tab.Scale.Scale = if open then 1.08 elseif m.Compact then 1 else 0.94
			tab.Ring.Visible = open
			tab.Glow.Visible = open
			tab.Holder.ZIndex = if open then 7 else 6
			local theme = ShopFx.Themes[section.Id] or ShopFx.Themes.Featured
			ShopFx.repaint(tab.Face, if open then theme.Tab else ShopFx.darker(theme.Tab, 0.2))
			x += tab.Width + StoreView.TabGap
		end
	end
end

--[[
	Places every page and hides the tabs with nothing to sell (a restricted
	player's GOLEMS: every egg is a paid random item); the open tab moves to
	the first one that shows if its own went.
]]
function StoreView.relayout(refs: Refs)
	for _, section in StoreConfig.Sections do
		local _, any = placePage(refs, section)
		local tab = refs.TabRefs[section.Id]
		if tab then
			tab.Holder.Visible = any
		end
	end
	if not StoreView.tabShown(refs, refs.Current) then
		local first = StoreView.visibleTabs(refs)[1]
		if first then
			StoreView.selectTab(refs, first)
			return
		end
	end
	placeTabs(refs)
	sizeCanvas(refs)
end

-- Paints the header, the body and the window's light in tab `id`'s colour world.
local function paintWorld(refs: Refs, id: string)
	local theme = ShopFx.Themes[id] or ShopFx.Themes.Featured
	ShopFx.repaint(refs.Window.Header, theme.Head)
	local fill = refs.Window.Root:FindFirstChild("HeaderFill")
	if fill and fill:IsA("GuiObject") then
		local paint = fill:FindFirstChild("Paint")
		if paint and paint:IsA("UIGradient") then
			-- (the band's lower half: its gradient from the middle down)
			paint.Color = ShopFx.sequence({ theme.Head[1]:Lerp(theme.Head[2], 0.9), theme.Head[2], theme.Head[3] }, { 0, 0.1, 1 })
		end
	end
	ShopFx.repaint(refs.Window.Body, theme.Body)
	local title = refs.Window.Title
	local fillGradient = title:FindFirstChild("Fill")
	if fillGradient and fillGradient:IsA("UIGradient") then
		fillGradient.Color = ShopFx.sequence({ WHITE, WHITE, theme.Title }, { 0, 0.4, 1 })
	end
	for _, fxRoot in refs.Fx do
		for _, bolt in fxRoot:GetDescendants() do
			if bolt:IsA("Frame") and bolt:GetAttribute("WorldGlow") then
				bolt.BackgroundColor3 = theme.Glow
			elseif bolt.Name == "Bolt" then
				local second = bolt:GetAttribute("Second") == true
				ShopFx.tintBolt(bolt, if second then theme.Bolt2 else theme.Bolt)
			elseif bolt.Name == "Dot" and bolt:IsA("Frame") and bolt:GetAttribute("Tint") then
				local which = bolt:GetAttribute("Tint")
				bolt.BackgroundColor3 = if which == 1 then theme.Bolt elseif which == 2 then theme.Bolt2 else WHITE
			elseif bolt.Name == "Sparkle" then
				local tint = if bolt:GetAttribute("Second") then theme.Bolt2 else WHITE
				for _, part in bolt:GetChildren() do
					if part:IsA("Frame") and part.Name ~= "Core" then
						part.BackgroundColor3 = tint
					end
				end
			end
		end
	end
end

-- Shows tab `id`'s page (and its colours). Returns true when the open tab changed.
function StoreView.selectTab(refs: Refs, id: string): boolean
	if not refs.Pages[id] then
		return false
	end
	local changed = refs.Current ~= id
	refs.Current = id
	for pageId, page in refs.Pages do
		page.Visible = pageId == id
	end
	-- its 3D pictures, the first time it shows
	local page = refs.Pages[id]
	if page:GetAttribute("Filled") ~= true then
		page:SetAttribute("Filled", true)
		StoreView.fillModels(page)
	end
	paintWorld(refs, id)
	placeTabs(refs)
	sizeCanvas(refs)
	if changed then
		refs.Scroller.CanvasPosition = Vector2.new(0, 0)
	end
	return changed
end

-- The first thing a gamepad lands on in the open page (a card or an option button).
function StoreView.firstSelectable(refs: Refs): GuiObject?
	-- (FEATURED opens with the limited banner: its first button)
	local banner = refs.Banner
	if refs.Current == "Featured" and banner and banner.Buys[1] then
		return banner.Buys[1]
	end
	for _, id in refs.Order do
		local card = refs.Cards[id]
		if card and card.Spec.Section == refs.Current and card.State ~= "Hidden" then
			if card.Button.Selectable then
				return card.Button
			end
			local keys = card.Spec.Options or card.Spec.Keys
			local first = card.Buys[keys[1]]
			if first and first.Selectable then
				return first
			end
		end
	end
	return refs.Tabs[refs.Current]
end

-- A tab: its face, its picture over the left end, its word; the open one gets the rim and glow.
local function buildTab(parent: Instance, section: StoreConfig.Section, m: Metrics, word: number): TabRefs
	local theme = ShopFx.Themes[section.Id] or ShopFx.Themes.Featured
	local icon = if m.Compact then math.floor(m.Tab * 0.86) else 46
	local room = math.floor(icon * 0.72)
	local width = tabWidth(section, m, word)
	local h = m.Tab
	local holder = UIKit.new("Frame", {
		Name = section.Id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, h),
		ZIndex = 6,
	}, parent)
	local scale = UIKit.new("UIScale", { Name = "Size", Scale = 1 }, holder)
	local lift = UIKit.new("Frame", {
		Name = "Lift",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	}, holder)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 6,
	}, lift)
	for i, grow in { 26, 14 } do
		local disc = UIKit.new("Frame", {
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = theme.TabGlow,
			BackgroundTransparency = if i == 1 then 0.78 else 0.6,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, grow, 1, grow),
			ZIndex = 6,
		}, glow)
		UIKit.corner(disc, 16 + math.floor(grow / 2))
	end
	ShopFx.drop(lift, 16, 5, 6)
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
		Visible = false,
		ZIndex = 7,
	}, lift)
	UIKit.corner(ring, 20)
	UIKit.new("UIStroke", { Name = "White", Color = WHITE, Thickness = 3.5, LineJoinMode = Enum.LineJoinMode.Round }, ring)
	local face = UIKit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Selectable = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 7,
	}, lift)
	ShopFx.face(face, theme.Tab, 16, 4, 90)
	ShopFx.studs(face, width, h, 17, 0.6, 7)
	local top = UIKit.new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -14, 0, 3),
		ZIndex = 7,
	}, face)
	UIKit.corner(top, 999)
	-- the picture: the sheet's once uploaded, else the live model
	local pictureAt = UDim2.fromOffset(math.floor(icon * 0.32), math.floor(h * 0.42))
	local image = ShopFx.icon(lift, section.TabIcon, icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pictureAt,
		ZIndex = 9,
	})
	if not image and section.TabModel then
		modelPicture(lift, section.TabModel, section.TabModel, icon, pictureAt, 9)
	end
	local label = ShopFx.text(lift, section.Tab, word, {
		Name = "Word",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, room + 2, 0.5, -1),
		Size = UDim2.new(1, -(room + 6), 0, word + 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	}, nil, 2)
	ShopFx.limit(label, word, 10)
	return { Holder = holder, Lift = lift, Face = face, Scale = scale, Ring = ring, Glow = glow, Width = width }
end

-- A lightning bolt's place in the window's world (Second: the theme's second bolt colour).
type BoltSpec = { From: Vector2, To: Vector2, Width: number, Forks: number, Second: boolean, Phase: number }

-- The window's world: the glow round it, bolts striking past its edges, sparkles on its frame.
local function buildWorld(group: Frame, size: Vector2): ({ Instance }, Frame, Frame)
	local back = UIKit.new("Frame", {
		Name = "Back",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, group)
	for i, s in { { 70, 0.93 }, { 40, 0.88 }, { 18, 0.8 } } do
		local glow = UIKit.new("Frame", {
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = ShopFx.Themes.Featured.Glow,
			BackgroundTransparency = s[2],
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, s[1] * 2, 1, s[1] * 2),
			ZIndex = 0,
		}, back)
		glow:SetAttribute("WorldGlow", true)
		UIKit.corner(glow, StoreView.Corner + s[1])
	end
	local w, h = size.X, size.Y
	local bolts: { BoltSpec } = {
		{ From = Vector2.new(27, -30), To = Vector2.new(-60, 250), Width = 6.2, Forks = 4, Second = false, Phase = 0 },
		{ From = Vector2.new(w - 25, -24), To = Vector2.new(w + 66, 310), Width = 5.8, Forks = 3, Second = false, Phase = 0.43 },
		{ From = Vector2.new(w - 70, h + 30), To = Vector2.new(w + 60, h - 250), Width = 4.8, Forks = 3, Second = true, Phase = 0.86 },
		{ From = Vector2.new(50, h + 30), To = Vector2.new(-70, h - 170), Width = 4.4, Forks = 2, Second = true, Phase = 0.29 },
	}
	for i, b in bolts do
		local bolt = ShopFx.bolt(back, b.From, b.To, ShopFx.Themes.Featured.Bolt, b.Width, 100 + i * 17, b.Forks, 0, b.Phase)
		bolt:SetAttribute("Second", b.Second)
	end
	local front = UIKit.new("Frame", {
		Name = "Front",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	}, group)
	local sparkles: { { X: number, Y: number, Size: number, Second: boolean } } = {
		{ X = w - 14, Y = 11, Size = 40, Second = false },
		{ X = w - 34, Y = 44, Size = 18, Second = true },
		{ X = 8, Y = h - 14, Size = 34, Second = false },
		{ X = 36, Y = h - 26, Size = 14, Second = true },
		{ X = math.floor(w * 0.38), Y = 2, Size = 24, Second = false },
		{ X = math.floor(w * 0.78), Y = h - 2, Size = 20, Second = true },
	}
	for i, s in sparkles do
		local sparkle = ShopFx.sparkle(front, UDim2.fromOffset(s.X, s.Y), s.Size, WHITE, 20, i)
		sparkle:SetAttribute("Second", s.Second)
	end
	return { back, front }, back, front
end

--[[
	Builds the window for `metrics` (a PC's when nil; StoreController
	rebuilds it when the screen asks for other sizes: needsRebuild).
]]
function StoreView.build(metrics: Metrics?): Refs
	local m = metrics or StoreView.metricsFor(false, 1)
	local gui = UIKit.screen("TerraForgeStore", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("Metrics", StoreView.metricsKey(m))
	-- a dim backdrop over the world
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = hex("#08041e"),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, gui)
	-- the window sits in a full-screen holder whose UIScale fits it to small screens
	local holder = UIKit.new("Frame", {
		Name = "Fit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	UIKit.new("UIScale", { Name = "FitScale", Scale = 1 }, holder)
	local size = StoreView.windowSize(1280, 720)
	local group = UIKit.new("Frame", {
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		-- a gamepad selection never wanders out to the HUD
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, holder)
	local fx, _, _ = buildWorld(group, size)
	ShopFx.drop(group, StoreView.Corner, 9, 1, { Name = "WindowDrop" })
	-- the window: a dark frame round the header band and the body
	local rim = StoreView.Rim
	local root = UIKit.new("Frame", {
		Name = "Window",
		Active = true,
		BackgroundColor3 = ShopFx.Outline,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, group)
	UIKit.corner(root, StoreView.Corner)
	UIKit.new("UIStroke", {
		Name = "Light",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = WHITE,
		Thickness = 2.5,
		Transparency = 0.8,
	}, root)
	local theme = ShopFx.Themes.Featured
	-- the body: the tab's colour world, its rays, bolts and dots behind the cards
	local body = UIKit.new("Frame", {
		Name = "Body",
		ClipsDescendants = true,
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 1, -2 * rim),
		ZIndex = 2,
	}, root)
	ShopFx.face(body, theme.Body, StoreView.Corner - rim, 0, 90)
	local bodyFx = UIKit.new("Frame", {
		Name = "Fx",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, body)
	table.insert(fx, bodyFx)
	local bw = size.X - 2 * rim
	ShopFx.rays(bodyFx, UDim2.new(0.5, 0, 0, m.Header - 90), 14, 430, 0.86, 2)
	local inner: { BoltSpec } = {
		{
			From = Vector2.new(-16, m.Header + 16),
			To = Vector2.new(208, m.Header - 30),
			Width = 3.8,
			Forks = 2,
			Second = false,
			Phase = 0.13,
		},
		{
			From = Vector2.new(bw + 10, m.Header + 330),
			To = Vector2.new(bw - 216, m.Header + 490),
			Width = 3.8,
			Forks = 2,
			Second = false,
			Phase = 0.61,
		},
		{
			From = Vector2.new(bw + 4, m.Header - 10),
			To = Vector2.new(bw - 160, m.Header + 150),
			Width = 2.9,
			Forks = 2,
			Second = true,
			Phase = 0.37,
		},
		{
			From = Vector2.new(-8, m.Header + 474),
			To = Vector2.new(240, m.Header + 400),
			Width = 2.9,
			Forks = 2,
			Second = true,
			Phase = 0.79,
		},
	}
	for i, b in inner do
		local bolt = ShopFx.bolt(bodyFx, b.From, b.To, theme.Bolt, b.Width, 200 + i * 13, b.Forks, 2, b.Phase, 3)
		bolt:SetAttribute("Second", b.Second)
	end
	local dots = ShopFx.dots(bodyFx, 32, bw, size.Y, { WHITE, theme.Bolt, theme.Bolt2 }, 61, 2, 3)
	for i, dot in dots:GetChildren() do
		dot:SetAttribute("Tint", (i - 1) % 3)
	end
	-- the header band (its lower half square: the body meets it straight)
	local header = UIKit.new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 0, m.Header - rim),
		ZIndex = 3,
	}, root)
	ShopFx.face(header, theme.Head, StoreView.Corner - rim, 0, 90)
	local fill = UIKit.new("Frame", {
		Name = "HeaderFill",
		Position = UDim2.fromOffset(rim, rim + math.floor((m.Header - rim) / 2)),
		Size = UDim2.new(1, -2 * rim, 0, math.ceil((m.Header - rim) / 2)),
		ZIndex = 3,
	}, root)
	ShopFx.face(fill, theme.Head, 0, 0, 90)
	local band = UIKit.new("Frame", {
		Name = "Band",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 0, m.Header - rim),
		ZIndex = 4,
	}, root)
	ShopFx.studs(band, bw, m.Header - rim, 28, 0.55, 4)
	ShopFx.shards(band, 4)
	UIKit.new("Frame", {
		Name = "HeaderLine",
		BackgroundColor3 = ShopFx.Outline,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, m.Header - 5),
		Size = UDim2.new(1, 0, 0, 5),
		ZIndex = 5,
	}, root)
	-- the big outlined SHOP (a PC's header has room for it)
	local title = ShopFx.title(root, string.upper(StoreConfig.Title), 56, { WHITE, WHITE, theme.Title }, {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(84, math.floor(m.Header / 2) - 2),
		Rotation = -3,
		Size = UDim2.fromOffset(150, 66),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = not m.Compact,
		ZIndex = 6,
	}, nil, 5)
	local titleEdge = title:FindFirstChild("Edge")
	if titleEdge and titleEdge:IsA("UIStroke") then
		titleEdge.Thickness = 5
	end
	-- the basket over the top-left corner: the sheet's once uploaded, else the live cart
	local basket = if m.Compact then math.floor(m.Header * 0.95) else 112
	local basketAt = UDim2.fromOffset(math.floor(basket * 0.2), math.floor(basket * 0.2))
	local icon = ShopFx.icon(root, "basket", basket, {
		Name = "Basket",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = basketAt,
		Rotation = -12,
		ZIndex = 9,
	})
	if not icon then
		Pop.model(root, "cart", basket, PictureModels.build("cart"), {
			Name = "Basket",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = basketAt,
			Rotation = -12,
			ZIndex = 9,
		}, Vector3.new(-0.7, 0.45, -1))
	end
	-- the tabs
	local tabs = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	}, root)
	local tabRefs: { [string]: TabRefs } = {}
	local tabFaces: { [string]: TextButton } = {}
	local word = StoreView.tabWord(m)
	for _, section in StoreConfig.Sections do
		local tab = buildTab(tabs, section, m, word)
		tabRefs[section.Id] = tab
		tabFaces[section.Id] = tab.Face
	end
	StoreView.fillModels(tabs) -- (the tabs' live pictures until the icon sheet is uploaded)
	-- the red X
	local closeHolder = UIKit.new("Frame", {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -(14 + math.floor(m.Close / 2)), 0, math.floor(m.Header / 2)),
		Rotation = 4,
		Size = UDim2.fromOffset(m.Close, m.Close),
		ZIndex = 8,
	}, root)
	ShopFx.drop(closeHolder, 15, 5, 8)
	local close = UIKit.new("TextButton", {
		Name = "Close",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Selectable = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 9,
	}, closeHolder)
	ShopFx.face(close, { hex("#ff7a7a"), hex("#e0262f"), hex("#b4141e") }, 15, 4, 90)
	ShopFx.studs(close, m.Close, m.Close, 18, 0.62, 9)
	ShopFx.text(close, "X", math.floor(m.Close * 0.72), {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 11,
	})

	-- the pages
	local scroller = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, m.Header - rim),
		Size = UDim2.new(1, 0, 1, -(m.Header - rim)),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = if m.Compact then 10 else 8,
		ScrollBarImageColor3 = hex("#f0e8ff"),
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 4,
	}, body)
	local refs: Refs = {
		Gui = gui,
		Group = group,
		Window = { Root = root, Header = header, Title = title, Close = close, Body = body },
		Scroller = scroller,
		Pages = {},
		Sections = {},
		Tabs = tabFaces,
		TabRefs = tabRefs,
		Cards = {},
		Order = {},
		Status = (nil :: any) :: TextLabel,
		Detail = (nil :: any) :: Frame,
		DetailTitle = (nil :: any) :: TextLabel,
		DetailLines = (nil :: any) :: TextLabel,
		DetailBuy = (nil :: any) :: TextButton,
		DetailBack = (nil :: any) :: TextButton,
		Banner = nil,
		Royal = nil,
		Fx = fx,
		Current = StoreConfig.Sections[1].Id,
		Fit = 1,
		Compact = m.Compact,
		Metrics = m,
	}
	for _, section in StoreConfig.Sections do
		local page = UIKit.new("Frame", {
			Name = section.Id,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(StoreView.Pad, StoreView.PadTop),
			Size = UDim2.fromOffset(StoreView.ContentWidth, 100),
			Visible = false,
			ZIndex = 4,
		}, scroller)
		refs.Pages[section.Id] = page
		refs.Sections[section.Id] = page
		if section.Banner == "Royal" then
			refs.Royal = buildRoyal(page)
		end
		for r, row in StoreConfig.rows(section.Id) do
			local h = rowHeight(section, r, m)
			local widths = rowWidths(row)
			for i, spec in row do
				local cardHolder = UIKit.new("Frame", {
					Name = spec.Id,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(widths[i], h),
					ZIndex = 4,
				}, page)
				local build = Looks[spec.Look] or Looks.Pass
				refs.Cards[spec.Id] = build(cardHolder, spec, widths[i], h, m)
			end
		end
	end
	for _, spec in StoreConfig.Cards do
		table.insert(refs.Order, spec.Id)
	end
	-- the Royal eggs' and the wheel's BEST VALUE (prices only: they never change)
	local royal: { string } = {}
	for _, spec in StoreConfig.Cards do
		if spec.Look == "Egg" then
			table.insert(royal, spec.Keys[1])
		end
	end
	local bestEgg = StoreView.bestValue(royal)
	for _, card in refs.Cards do
		if card.Spec.Look == "Egg" and card.Sticker then
			local best = card.Spec.Keys[1] == bestEgg
			card.Sticker.Visible = best
			if best then
				ShopFx.setStyle(card.Price, "Gold")
			end
		end
	end

	-- the line at the bottom
	local status = ShopFx.text(body, "", m.Status, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = ShopFx.Outline,
		BackgroundTransparency = 0.2,
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(600, m.Status + 14),
		Visible = false,
		ZIndex = 26,
	}, nil, 0)
	UIKit.corner(status, 10)
	refs.Status = status

	-- the odds panel (paid random items show their odds before the buy); a
	-- dim blocker under it keeps taps and the D-pad off the cards behind
	local blocker = UIKit.new("TextButton", {
		Name = "Blocker",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Selectable = false,
		Visible = false,
		ZIndex = 29,
	}, body)
	UIKit.corner(blocker, StoreView.Corner - rim)
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0.5, math.floor((m.Header - rim) / 2)),
		Size = UDim2.fromOffset(m.Detail.X, m.Detail.Y),
		Visible = false,
		ZIndex = 30,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, body)
	ShopFx.drop(detail, CORNER, 8, 30)
	local panel = UIKit.new("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 31,
	}, detail)
	ShopFx.face(panel, { hex("#3a1a7a"), hex("#1e0c48"), hex("#120628") }, CORNER, 5, 90)
	ShopFx.rim(panel, CORNER, 31)
	local detailBand = UIKit.new("Frame", {
		Name = "Band",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 58),
		ZIndex = 32,
	}, detail)
	ShopFx.face(detailBand, theme.Head, 14, 4, 90)
	local detailTitle = ShopFx.text(detailBand, "", 30, {
		Name = "Title",
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		ZIndex = 34,
	}, nil, 3)
	ShopFx.limit(detailTitle, 30, 14)
	-- the odds can run long (Triple Lucky: every capsule): they scroll
	local linesScroll = UIKit.new("ScrollingFrame", {
		Name = "LinesScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(22, 80),
		Size = UDim2.new(1, -36, 1, -(80 + m.DetailButton.Y + 34)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = hex("#d8c8ff"),
		ZIndex = 32,
	}, detail)
	local detailLines = UIKit.new("TextLabel", {
		Name = "Lines",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = ShopFx.Font,
		Size = UDim2.new(1, -12, 0, 0),
		Text = "",
		TextColor3 = WHITE,
		TextSize = m.Lines,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 33,
	}, linesScroll)
	UIKit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = ShopFx.Outline,
		Thickness = 1.5,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, detailLines)
	local backButton = ShopFx.priceButton(detail, nil, m.DetailButton, "Grey", {
		Name = "Back",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.28, 0, 1, -18),
		ZIndex = 33,
	}, nil, "BACK")
	local backShine = backButton.Face:FindFirstChild("Shine")
	if backShine then
		backShine:Destroy()
	end
	local buyButton = ShopFx.priceButton(detail, 0, m.DetailButton, "Green", {
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.72, 0, 1, -18),
		ZIndex = 33,
	})
	refs.Detail = detail
	refs.DetailTitle = detailTitle
	refs.DetailLines = detailLines
	refs.DetailBuy = buyButton.Face
	refs.DetailBack = backButton.Face

	StoreView.relayout(refs)
	StoreView.selectTab(refs, refs.Current)
	StoreView.layout(refs, 1280, 720, m.Compact)
	return refs
end

-- Does the window need building again for a w x h screen (its sizes changed)?
function StoreView.needsRebuild(refs: Refs, w: number, h: number, compact: boolean?): boolean
	local _, fit = StoreView.windowSize(w, h)
	return StoreView.metricsKey(StoreView.metricsFor(compact, fit)) ~= StoreView.metricsKey(refs.Metrics)
end

-- A price button's size (its holder's: the face fills it).
function StoreView.buttonSize(face: GuiObject): Vector2
	local holder = face.Parent
	if holder and holder:IsA("GuiObject") then
		return Vector2.new(holder.Size.X.Offset, holder.Size.Y.Offset)
	end
	return Vector2.new(face.Size.X.Offset, face.Size.Y.Offset)
end

--[[
	Fits the window into a w x h design-unit screen (compact: a phone /
	tablet / TV). Wide screens keep the left HUD column clear (HudRoom): the
	window moves right as far as the screen allows.
]]
function StoreView.layout(refs: Refs, w: number, h: number, compact: boolean?)
	local m = refs.Metrics
	local size, fit = StoreView.windowSize(w, h)
	refs.Group.Size = UDim2.fromOffset(size.X, size.Y)
	local holder = refs.Group.Parent
	local scale = if holder then holder:FindFirstChild("FitScale") else nil
	if scale and scale:IsA("UIScale") then
		scale.Scale = fit
	end
	local left = (w - size.X * fit) / 2
	local shift = math.clamp(StoreView.HudRoom - left, 0, math.max(0, left - 12))
	refs.Group.Position = UDim2.new(0.5, math.floor(shift / math.max(fit, 0.1)), 0.5, 0)
	refs.Fit = fit
	refs.Compact = compact == true
	local panel = Vector2.new(math.min(m.Detail.X, size.X - 40), math.min(m.Detail.Y, size.Y - m.Header - 24))
	refs.Detail.Size = UDim2.fromOffset(panel.X, panel.Y)
	refs.DetailLines.TextSize = m.Lines
	refs.Status.Size = UDim2.fromOffset(math.min(760, size.X - 60), m.Status + 14)
	sizeCanvas(refs)
end

---------------------------------------------------------------- what the cards show

-- Which product a card shows and how: "Buy" (the price), "Owned" (a pass the
-- player has: the OWNED tag), "Pending" (a purchase on its way: shaded),
-- "Locked" (not yet: a STAR blaster before its rebirth; a grey price),
-- "Hidden" (nothing to sell: the blaster at the top level; its row closes up).
function StoreView.setCard(refs: Refs, id: string, key: string, state: string)
	local card = refs.Cards[id]
	local product = MonetizationConfig.Products[key]
	if not card or not product then
		return
	end
	local wasHidden = card.State == "Hidden"
	card.State = state
	if card.Key ~= key then
		-- (the blaster's band: one price button, the product it buys changes)
		local old = card.Buys[card.Key]
		card.Buys[card.Key] = nil
		if old then
			card.Buys[key] = old
			old:SetAttribute("Key", key)
			old:SetAttribute("Odds", StoreView.needsOdds(card.Spec, key))
		end
		card.Key = key
	end
	if not (card.Spec.Options and #(card.Spec.Options :: { string }) > 1) then
		ShopFx.setPrice(card.Price, product.Robux)
	end
	card.Holder.Visible = state ~= "Hidden"
	local shows = state == "Buy" or state == "Pending" or state == "Locked"
	for _, face in card.Buys do
		local priceHolder = face.Parent
		if priceHolder and priceHolder:IsA("GuiObject") then
			priceHolder.Visible = shows
		end
		face.Active = state == "Buy"
	end
	if card.Spec.Look == "Star" then
		ShopFx.setStyle(card.Price, if state == "Locked" then "Grey" else "Green")
		local lock = card.Holder:FindFirstChild("Lock")
		if lock and lock:IsA("GuiObject") then
			lock.Visible = state == "Locked"
		end
		-- (a locked one's gun dims under its lock; the card stays bright)
		local pic = card.Picture
		if pic and pic:IsA("ImageLabel") then
			pic.ImageTransparency = if state == "Locked" then 0.45 else 0
			local view = pic:FindFirstChild("View")
			if view and view:IsA("ViewportFrame") then
				view.ImageColor3 = if state == "Locked" then Color3.fromRGB(96, 96, 116) else WHITE
			end
		end
	end
	card.Owned.Visible = state == "Owned"
	card.Button.Active = state == "Buy" and card.Button.Selectable
	card.Shade.Visible = state == "Pending" or (state == "Locked" and card.Spec.Look ~= "Star")
	if wasHidden ~= (state == "Hidden") then
		StoreView.relayout(refs)
	end
end

-- A card's note ("Opens at rebirth 3", the blaster's rebirth rule, Server Luck running).
function StoreView.setNote(refs: Refs, id: string, text: string)
	local card = refs.Cards[id]
	local note = if card then card.Note else nil
	if note then
		ShopFx.setText(note, text)
	end
end

-- A card's big line ("LV 4 > LV 5" on the blaster card).
function StoreView.setBig(refs: Refs, id: string, text: string)
	local card = refs.Cards[id]
	local big = if card then card.Big else nil
	if big then
		ShopFx.setText(big, text)
	end
end

-- The coin amounts at a podium income of `income` coins per second (and the best pack's sticker).
function StoreView.setCoins(refs: Refs, income: number)
	local packs: { string } = {}
	for _, card in refs.Cards do
		local amount = card.Amount
		if amount then
			local coins = MonetizationConfig.coinPackAmount(card.Key, income) or 0
			ShopFx.setText(amount, "$" .. Format.big(coins))
		end
		if card.Spec.Look == "Coins" then
			table.insert(packs, card.Key)
		end
	end
	local best = StoreView.bestValue(packs, income)
	for _, card in refs.Cards do
		if card.Spec.Look == "Coins" then
			local isBest = card.Key == best
			if card.Sticker then
				card.Sticker.Visible = isBest
			end
			ShopFx.repaint(card.Button, if isBest then ShopFx.Cards.Gold else ShopFx.Cards.Green)
			ShopFx.setStyle(card.Price, if isBest then "Gold" else "Green")
		end
	end
end

-- The Royal Egg's tiles: the chances a buy rolls now (with Triple Lucky while it runs).
function StoreView.setRoyalOdds(refs: Refs, odds: { [string]: number }, lucky: boolean)
	local royal = refs.Royal
	if not royal then
		return
	end
	for id, label in royal.Chances do
		ShopFx.setText(label, StoreView.percent(odds[id] or 0))
	end
	local chip = royal.Lucky.Parent
	if chip and chip:IsA("GuiObject") then
		chip.Visible = lucky
	end
end

-- Shows or hides the Royal Egg banner (paid random: hidden where restricted).
function StoreView.setRoyalShown(refs: Refs, shown: boolean)
	local royal = refs.Royal
	if royal and royal.Frame.Visible ~= shown then
		royal.Frame.Visible = shown
		StoreView.relayout(refs)
	end
end

--[[
	Shows the limited edition at the top of FEATURED (nil removes it).
	Returns its refs (the controller wires the buttons and the timer).
]]
function StoreView.setEdition(refs: Refs, edition: Edition?): BannerRefs?
	local old = refs.Banner
	if old and edition and old.Edition.Id == edition.Id then
		return old
	end
	if old then
		old.Frame:Destroy()
		refs.Banner = nil
	end
	if edition then
		local banner = buildBanner(refs.Pages.Featured, edition, refs.Metrics)
		refs.Banner = banner
		if refs.Pages.Featured:GetAttribute("Filled") == true then
			StoreView.fillModels(banner.Frame)
		end
	end
	StoreView.relayout(refs)
	return refs.Banner
end

-- The chances on the banner's tiles (the capsule's odds now: with Triple
-- Lucky while it runs, so they match the odds panel and what a buy rolls).
function StoreView.setBannerOdds(refs: Refs, odds: { [string]: number }, lucky: boolean)
	local banner = refs.Banner
	if not banner then
		return
	end
	for id, label in banner.Chances do
		ShopFx.setText(label, StoreView.percent(odds[id] or 0))
	end
	local golems = banner.Edition.Golems
	local hero = golems[#golems]
	if hero then
		ShopFx.setText(banner.Hero, `{hero.Name} {StoreView.percent(odds[hero.Id] or 0)}`)
	end
	local tag = banner.Lucky.Parent
	if tag and tag:IsA("GuiObject") then
		tag.Visible = lucky
	end
end

-- The banner's end date and time left (seconds; 0 = ended).
function StoreView.setTimer(refs: Refs, secondsLeft: number)
	local banner = refs.Banner
	if banner then
		ShopFx.setText(banner.Timer, `{StoreView.endsOn(banner.Edition.EndsAt)} · {StoreView.countdown(secondsLeft)}`)
	end
end

-- The odds panel before a paid random buy (nil hides it).
function StoreView.showDetail(refs: Refs, detail: Detail?)
	refs.Detail.Visible = detail ~= nil
	local blocker = refs.Window.Body:FindFirstChild("Blocker")
	if blocker and blocker:IsA("GuiObject") then
		blocker.Visible = detail ~= nil
	end
	if not detail then
		return
	end
	ShopFx.setText(refs.DetailTitle, detail.Title)
	local band = refs.Detail:FindFirstChild("Band")
	if band and band:IsA("GuiObject") then
		local theme = ShopFx.Themes[refs.Current] or ShopFx.Themes.Featured
		ShopFx.repaint(band, theme.Head)
	end
	refs.DetailLines.Text = table.concat(detail.Lines, "\n")
	-- (AutomaticSize grows it in the game; the height also from the lines for the previews)
	refs.DetailLines.Size = UDim2.new(1, -12, 0, #detail.Lines * math.ceil(refs.DetailLines.TextSize * 1.3) + 8)
	ShopFx.setPrice(refs.DetailBuy, detail.Robux)
end

-- The line at the bottom of the window (nil / "" hides it).
function StoreView.setStatus(refs: Refs, text: string?)
	refs.Status.Text = text or ""
	refs.Status.Visible = text ~= nil and text ~= ""
end

return StoreView
