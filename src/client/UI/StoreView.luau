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
	once uploaded, the shop icon sheet (IconAssets.Shop); the golems, the
	eggs and the pass items (podium, train, hoverboard) their drawn stickers
	once those images are uploaded (IconAssets.StickerSheets: an image
	instead of a 3D view); drawn pictures
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
StoreView.DimTransparency = 0.45 -- the backdrop over the world while the window is open

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
	Owned: Frame?, -- the OWNED tag (a game pass's card only: nothing else can be owned)
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
	Icon: GuiObject?, -- its picture (it pops when the tab is picked and wiggles while it is open)
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
	Banner: BannerRefs?, -- the limited edition (FEATURED), nil when none runs or FEATURED isn't built
	Royal: RoyalRefs?, -- the Royal Egg's golems (GOLEMS, once built)
	Fx: { Instance }, -- the window's own effects (the motion's fixed roots; the title's light band too)
	Front: Frame, -- the layer over the window (its sparkles; a purchase's stars fly in it)
	Burst: GuiObject, -- the rays that flash out behind the window as it opens
	Current: string, -- the open tab
	Fit: number, -- the last layout's fit scale
	Compact: boolean,
	-- the motion skips the ambient marks (the pages' particles, the cards' gloss, the small pictures'
	-- idling): a phone or a tablet; StoreController keeps them for a TV (compact, but not lean)
	Lean: boolean,
	Metrics: Metrics,
	-- (pages are built lazily: the open one, the others on their first visit; what the
	-- controller says is kept here and shown when a page is built)
	Built: { [string]: boolean },
	Fresh: { string }, -- pages built since the controller last asked (takeBuilt)
	States: { [string]: CardState }, -- every card's product, state and lines, built or not
	Edition: Edition?,
	EditionLeft: number?,
	EditionOdds: { [string]: number }?,
	EditionLucky: boolean,
	RoyalShown: boolean,
	RoyalOdds: { [string]: number }?,
	RoyalLucky: boolean,
	Income: number?,
	-- bumped when what moves on a page changes (a card shown or hidden, the BEST VALUE moved,
	-- a banner came or went): the controller starts the open page's loops again
	Marks: number,
}

-- What the controller said about a card (kept for a page that isn't built yet).
export type CardState = { Key: string, State: string, Note: string?, Big: string? }

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

-- How big a drawn sticker shows, as a share of the 3D picture it stands in for.
StoreView.StickerFill = 1.04
-- How far the Custom Hoverboard's picture bobs (design units: it hovers; the others ShopFx.IdleRise).
StoreView.HoverRise = 9

--[[
	A live 3D picture `size` square with its middle at `at` (nil: no model).
	The model itself is built when its page first shows (fillModels): the
	shop opens with only the open tab's models built (cheap on phones).
	`props` adds to the picture's. A golem, an egg, the podium, the train or
	the hoverboard shows its drawn sticker instead once its image is uploaded
	(IconAssets.StickerSheets: one image, no 3D view, nothing to build).
]]
local function livePicture(parent: Instance, model: string?, icon: string, size: number, props: { [string]: any }): ImageLabel?
	if not model then
		return nil
	end
	local sticker = ShopFx.stickerPicture(parent, model, math.floor(size * StoreView.StickerFill + 0.5), props)
	if sticker then
		return sticker
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

-- The box round every part of a model (min and max corners; a turned part by its corners).
local function boxOf(model: Instance): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local cf = part.CFrame
			local half = part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local at = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						lo = Vector3.new(math.min(lo.X, at.X), math.min(lo.Y, at.Y), math.min(lo.Z, at.Z))
						hi = Vector3.new(math.max(hi.X, at.X), math.max(hi.Y, at.Y), math.max(hi.Z, at.Z))
					end
				end
			end
		end
	end
	if lo.X > hi.X then
		return Vector3.zero, Vector3.zero
	end
	return lo, hi
end

StoreView.ModelView = Vector3.new(-0.55, 0.42, -1) -- (Pop.show's default way in)
StoreView.ModelFill = 0.94 -- how much of its picture a model fills (the previews' pictures: 0.96)

--[[
	Puts `model` in `view` with a camera from `from` (Pop.show's way in)
	that backs off until every part's corners fit the picture (`size`: its
	30 degree height and its width), the model filling ModelFill of it.
	(Pop.show frames a model's whole sphere: it shows smaller than the
	previews' pictures of it; the shop's models fill theirs like those.)
]]
local function frame(view: ViewportFrame, model: Model, from: Vector3?, size: Vector2)
	for _, old in view:GetChildren() do
		if old:IsA("Model") or old:IsA("Camera") then
			old:Destroy()
		end
	end
	model.Parent = view
	local dir = (from or StoreView.ModelView).Unit
	local cross = Vector3.yAxis:Cross(dir)
	local right = if cross.Magnitude > 1e-3 then cross.Unit else Vector3.xAxis
	local up = dir:Cross(right).Unit
	local lo, hi = boxOf(model)
	local center = (lo + hi) / 2
	local tall = math.tan(math.rad(15)) * StoreView.ModelFill
	local wide = tall * (if size.X > 0 and size.Y > 0 then size.X / size.Y else 1)
	local distance = 0.1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local cf = part.CFrame
			local h = part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local at = cf * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz) - center
						local need = at:Dot(dir) + math.max(math.abs(at:Dot(up)) / tall, math.abs(at:Dot(right)) / wide)
						distance = math.max(distance, need)
					end
				end
			end
		end
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(center + dir * distance, center)
	camera.Parent = view
	pcall(function()
		view.CurrentCamera = camera
	end)
end

--[[
	Three of model `name` in ONE view (an egg pack's pile: one ViewportFrame
	instead of three), the middle one in front, the two others a little back
	and down at its sides, framed to the picture's shape (wider than tall).
]]
local function pile(view: ViewportFrame, name: string, first: Model, from: Vector3?, size: Vector2)
	local dir = (from or StoreView.ModelView).Unit
	local cross = Vector3.yAxis:Cross(dir)
	local right = if cross.Magnitude > 1e-3 then cross.Unit else Vector3.xAxis
	local lo, hi = boxOf(first)
	local radius = math.max((hi - lo).Magnitude / 2, 0.1)
	local group = Instance.new("Model")
	group.Name = name .. "Pile"
	-- (across, up, toward the camera: in radii of one)
	local places = { { -0.72, -0.1, -0.45 }, { 0.72, -0.1, -0.45 }, { 0, 0, 0.35 } }
	for i, p in places do
		local copy = if i == 1 then first else PictureModels.build(name)
		if copy then
			local offset = right * (p[1] * radius) + Vector3.yAxis * (p[2] * radius) + dir * (p[3] * radius)
			for _, part in copy:GetDescendants() do
				if part:IsA("BasePart") then
					part.CFrame = part.CFrame + offset
				end
			end
			copy.Parent = group
		end
	end
	frame(view, group, from, size)
end

-- Builds one waiting picture's model (attribute Copies 3: a pile of three in its one view).
local function fillOne(picture: ImageLabel)
	local name = picture:GetAttribute("Model")
	if type(name) ~= "string" then
		return
	end
	picture:SetAttribute("Model", nil)
	local view = picture:FindFirstChild("View")
	if not view or not view:IsA("ViewportFrame") then
		return
	end
	local model, from = PictureModels.build(name)
	if not model then
		return
	end
	local size = Vector2.new(picture.Size.X.Offset, picture.Size.Y.Offset)
	if picture:GetAttribute("Copies") == 3 then
		pile(view, name, model, from, size)
	else
		frame(view, model, from, size)
	end
end

-- Builds the 3D models of every picture under `root` that waits for one (livePicture).
function StoreView.fillModels(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("ImageLabel") then
			fillOne(d)
		end
	end
end

-- (the game sets it, StoreController) a page's models are built one a frame after it shows, so a
-- tab's first visit never stalls its slide and pop; off: all at once (the specs, the previews)
StoreView.SpreadModels = false

-- The models under `root`: all now, or one a frame (SpreadModels).
local function fill(root: Instance)
	if not StoreView.SpreadModels then
		StoreView.fillModels(root)
		return
	end
	local waiting: { ImageLabel } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("ImageLabel") and type(d:GetAttribute("Model")) == "string" then
			table.insert(waiting, d)
		end
	end
	task.spawn(function()
		for _, picture in waiting do
			if picture.Parent then
				fillOne(picture)
				task.wait()
			end
		end
	end)
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

-- Will this card show a picture in the game (a live model, a STAR gun, a drawn wheel, an uploaded icon or sticker)?
function StoreView.hasPicture(spec: StoreConfig.CardSpec): boolean
	if spec.Sheet and IconAssets.shopShows(spec.Sheet) then
		return true
	end
	if spec.Model and IconAssets.shopStickerShows(spec.Model) then
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
	target; it clips its light), the sunburst (one sprite, it turns) and a
	glow behind where the picture goes, the gloss, the light edge; the
	Mythic rim when asked; a gloss band over the whole card that sweeps
	across now and then (ShopFx.sheen). A one-price card's face grows, rises
	and brightens under the mouse or the gamepad's selection and squashes
	on a press (ShopFx.bindPress on its holder). Returns the face.
]]
StoreView.SheenZ = 11 -- the cards' gloss band: over the picture, the words and the price, under the stickers
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
		-- (a rainbow card's rays run warm gold; the paint itself carries the rainbow)
		local tint = if o.Rainbow then Color3.fromRGB(255, 236, 170) else WHITE
		ShopFx.rays(face, o.Rays, (o.RayLength or 180) * 2, o.RayFade or 0.62, 2, tint, 30)
	end
	local glow: GuiObject? = nil
	if o.Glow then
		glow = ShopFx.glow(face, o.Glow, o.GlowRadius or 80, o.GlowColor or WHITE, 2)
	end
	ShopFx.gloss(face, CORNER, 3)
	local rim = ShopFx.rim(face, CORNER, 3)
	if o.Mythic then
		ShopFx.mythicRim(face, 5)
	end
	ShopFx.sheen(holder, CORNER, StoreView.SheenZ)
	if selectable then
		local light = rim:FindFirstChild("Light")
		ShopFx.bindPress(face, holder, {
			Lift = ShopFx.Lift,
			Light = if light and light:IsA("UIStroke") then light else nil,
			Glow = glow,
		})
	else
		face:SetAttribute("Motion", "None")
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

-- The tab's hero picture floats up and down (mark "Float": one per tab, a slow bob).
local function float(picture: GuiObject?)
	if picture then
		picture:SetAttribute("ShopFx", "Float")
	end
end

-- A golem's or an egg's picture idles: a soft bob and a small sway (mark "Idle"; `ambient`: a phone keeps it still).
local function idle(picture: GuiObject?, ambient: boolean?)
	if picture then
		picture:SetAttribute("ShopFx", "Idle")
		if ambient then
			picture:SetAttribute("Ambient", true)
		end
	end
end

-- A hero egg floats and now and then wobbles as if about to hatch (Float with Wobble).
local function hatch(picture: GuiObject?, rise: number?)
	if picture then
		picture:SetAttribute("ShopFx", "Float")
		picture:SetAttribute("Wobble", ShopFx.WobbleSwing)
		if rise then
			picture:SetAttribute("Rise", rise)
		end
	end
end

-- A gentle wiggle about its tilt (mark "Wiggle"; `swing` degrees each way, `ambient`: a phone keeps it still).
local function wiggle(gui: GuiObject?, swing: number?, ambient: boolean?)
	if gui then
		gui:SetAttribute("ShopFx", "Wiggle")
		if swing then
			gui:SetAttribute("Swing", swing)
		end
		if ambient then
			gui:SetAttribute("Ambient", true)
		end
	end
end

-- A drifting particle of a page's theme: where it starts (x, y), its drift (dx, dy), its size and seconds a round.
type Mote = { number }

--[[
	A tab's theme particles in `parent` (ShopFx.particle: PC and TV only,
	at most StoreView.MaxMotes, invisible at rest): rising embers over the
	Dragonforge, gold sparkles round the Royal Egg, sparks off the next
	blaster, coins down the gaps of the Cash page.
]]
StoreView.MaxMotes = 8
local function motes(parent: Instance, list: { Mote }, picture: string, colors: { Color3 }, peak: number, z: number)
	for i, m in list do
		if i > StoreView.MaxMotes then
			break
		end
		ShopFx.particle(
			parent,
			picture,
			UDim2.fromOffset(m[1], m[2]),
			m[5],
			Vector2.new(m[3], m[4]),
			m[6],
			colors[(i - 1) % #colors + 1],
			peak,
			z
		)
	end
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
		Owned = nil,
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
		if product.Kind == "GamePass" then
			refs.Owned = ownedTag(refs.Holder, size, props)
		end
	end
	return button
end

-- A BEST VALUE button breathes (mark "Pulse": a UIScale on its holder; `on` false keeps it still).
-- Returns whether the mark changed.
local function pulse(face: GuiObject, on: boolean): boolean
	local holder = face.Parent
	if not holder or not holder:IsA("GuiObject") then
		return false
	end
	if not holder:FindFirstChild("Pulse") then
		UIKit.new("UIScale", { Name = "Pulse", Scale = 1 }, holder)
	end
	local was = holder:GetAttribute("ShopFx") == "Pulse"
	holder:SetAttribute("ShopFx", if on then "Pulse" else nil)
	return was ~= on
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
	-- (the coins: the icon sheet's, like the Cash tab's coin stack; the golem and the podium: their stickers)
	local sheets: { [number]: string } = { [2] = "coins" }
	for i = 1, 3 do
		local slot = UIKit.new("Frame", {
			Name = "Slot" .. i,
			Position = UDim2.fromOffset(x0 + (i - 1) * (slotW + plus), y),
			Size = UDim2.fromOffset(slotW, slotH),
			ZIndex = 5,
		}, holder)
		ShopFx.face(slot, { hex("#3a2a6a"), hex("#1e1440") }, 12, 3)
		local at = UDim2.new(0.5, 0, 0, 40)
		local pic: GuiObject? = if sheets[i]
			then ShopFx.icon(slot, sheets[i], 62, { Name = "Picture", AnchorPoint = Vector2.new(0.5, 0.5), Position = at, ZIndex = 6 })
			else nil
		pic = pic or modelPicture(slot, models[i], models[i], 62, at, 6)
		if i == 1 then
			idle(pic, true) -- (its golem lives a little)
		end
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
	local product = MonetizationConfig.Products[spec.Keys[1]]
	cardTitle(refs, spec.Title or product.Name, 21, 10, 2)
	local size = math.min(math.floor(math.min(w - 40, 140) * (spec.PictureScale or 1)), w - 24)
	local pic = picture(holder, spec, size, UDim2.new(0.5, 0, 0, picY), 5)
	refs.Picture = pic
	-- (owner 2026-11-12 "add more things": the picture lives a little like the golems, the
	-- hoverboard hovers higher)
	idle(pic, true)
	if pic and string.sub(spec.Model or "", 1, 6) == "board_" then
		pic:SetAttribute("Rise", StoreView.HoverRise)
	end
	if spec.Id == "DoubleMoney" then
		-- (on the picture: it bobs with it)
		local on: Instance = pic or holder
		local at = if pic then UDim2.new(0.5, 44, 0.5, -48) else UDim2.new(0.5, 44, 0, picY - 48)
		ShopFx.x2(on, 62, { AnchorPoint = Vector2.new(0.5, 0.5), Position = at, ZIndex = 9 })
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
	ShopFx.bolt(face, UDim2.fromOffset(math.floor(w * 0.3), h - 70), 210, 68, hex("#ffd84a"), 1, 3, 6.4, false)
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
	float(refs.Picture)
	-- sparks fly off the gun now and then (the Blasters tab's particles: PC and TV)
	local gx, gy = w - 96, math.floor(h * 0.48)
	motes(holder, {
		{ gx + 46, gy - 20, 40, -78, 16, 1.5 },
		{ gx + 30, gy + 8, 58, -60, 12, 1.25 },
		{ gx + 52, gy - 4, 22, -92, 14, 1.75 },
		{ gx + 12, gy - 30, 50, -70, 11, 1.4 },
		{ gx + 40, gy + 14, 34, -84, 13, 1.6 },
	}, "sparkle", { hex("#bff6ff"), WHITE, hex("#ffe27a") }, 0.1, 6)
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
		ShopFx.bolt(face, UDim2.fromOffset(math.floor(w * 0.42), math.floor(h * 0.42)), 260, -22, hex("#ff8ab0"), 2, 3, 5.6, false)
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
	elseif spec.Model and IconAssets.shopStickerShows(spec.Model) then
		-- a pile of three drawn eggs: the two behind a little smaller and lower at the sides
		local pile = UIKit.new("Frame", {
			Name = "Picture",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(mid, y + 2),
			Size = UDim2.fromOffset(math.min(w - 36, 232), 116),
			ZIndex = 5,
		}, holder)
		local size = math.floor(112 * StoreView.StickerFill + 0.5)
		for i, place in { { 0.21, 0.58 }, { 0.79, 0.58 }, { 0.5, 0.5 } } do
			ShopFx.stickerPicture(pile, spec.Model, if i == 3 then size else math.floor(size * 0.84), {
				Name = "Egg" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(place[1], place[2]),
				ZIndex = if i == 3 then 6 else 5,
			})
		end
		refs.Picture = pile
	else
		-- a pile of three in one picture (one 3D view, not three: StoreView.fillModels)
		local pic = modelPicture(holder, spec.Model, spec.Icon, 112, UDim2.fromOffset(mid, y + 2), 5)
		if pic then
			pic.Size = UDim2.fromOffset(math.min(w - 36, 232), 116)
			pic:SetAttribute("Copies", 3)
		end
		refs.Picture = pic
	end
	idle(refs.Picture, true) -- (the egg, or the pile of three as one)
	-- the count in a box held by its middle (it and its dark copy wiggle as one)
	local countBox = UIKit.new("Frame", {
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -67, 0, y + 26),
		Size = UDim2.fromOffset(110, 50),
		ZIndex = 9,
	}, holder)
	ShopFx.title(countBox, spec.Big or `x{count}`, 43, { WHITE, WHITE, hex("#ffe07a") }, {
		Name = "Big",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 9,
	})
	if count > 1 then
		wiggle(countBox, 4, true)
	end
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
	ShopFx.bolt(face, UDim2.fromOffset(math.floor(w * 0.56), math.floor(h * 0.5)), h + 30, 12, hex("#fff27a"), 3, 3, 4.6, false)
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
	float(refs.Picture)
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
		pulse(refs.Buys[best], true)
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
	ShopFx.bolt(face, UDim2.fromOffset(w - 150, math.floor(h / 2)), 260, 64, WHITE, 2, 3, 7, false)
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
	local rays = ShopFx.rays(
		face,
		UDim2.new(0.5, 0, 0.45, 0),
		math.floor(size.X * 1.8),
		if rare then 0.45 else 0.68,
		z + 1,
		if mythic then Color3.fromRGB(255, 200, 230) else WHITE,
		40
	)
	if rays and not rare then
		rays:SetAttribute("ShopFx", nil) -- (only the Legendary and the Mythic's turn: the rarest stand out)
	end
	local picY = if named then math.floor(size.Y * 0.42) else math.floor(size.Y * 0.46)
	local pic = math.floor(math.min(size.X - 12, size.Y * (if named then 0.52 else 0.7)))
	if named and golem.Rarity == "Epic" then
		-- (the Royal Egg's Epic: a soft glow breathes behind it)
		local glow = ShopFx.glow(face, UDim2.new(0.5, 0, 0, picY), math.floor(pic * 0.62), hex("#f4d8ff"), z + 1, 0.85)
		glow:SetAttribute("ShopFx", "Glow")
	end
	ShopFx.gloss(face, 14, z + 2, 0.3)
	ShopFx.rim(face, 14, z + 2)
	if mythic then
		ShopFx.mythicRim(face, 4)
	end
	-- the golem bobs and rocks (the Royal Egg's always; the small Dragonforge tiles' not on a phone)
	idle(
		livePicture(holder, "golem_" .. golem.Id, "golem_" .. golem.Id, pic, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, picY),
			ZIndex = z + 3,
		}),
		not named
	)
	if named and rare then
		-- (the Royal Egg's Legendary and Mythic: two sparkles twinkle by the golem)
		local tint = if mythic then hex("#ffd0f0") else hex("#fff4b0")
		for k, place in { { 0.2, -0.36, 22 }, { 0.82, 0.02, 15 } } do
			local sparkle = ShopFx.sparkle(
				holder,
				UDim2.new(place[1], 0, 0, picY + math.floor(place[2] * pic)),
				place[3],
				tint,
				z + 4,
				k + (if mythic then 2 else 0)
			)
			sparkle:SetAttribute("Ambient", true)
		end
	end
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
		local word = ShopFx.text(holder, string.upper(golem.Rarity), 14, {
			Name = "Rarity",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -6, 0, 18),
			TextColor3 = if mythic then hex("#ff8ab0") else hex("#fff3a0"),
			ZIndex = z + 5,
		}, nil, 1)
		if mythic then
			-- MYTHIC in a rainbow that runs (the rim's own colours and motion)
			word.TextColor3 = WHITE
			local rainbow = UIKit.new("UIGradient", {
				Name = "Rainbow",
				Color = ShopFx.sequence(ShopFx.RainbowRim),
				Rotation = ShopFx.RimRest,
			}, word)
			rainbow:SetAttribute("ShopFx", "Rim")
		end
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
	ShopFx.rays(face, UDim2.fromOffset(510, 110), 640, 0.55, 2, hex("#ffe68c"), 36)
	-- the flames along the bottom and the embers rising
	local rand = ShopFx.random(11)
	for i = 0, 7 do
		local fw = 120 + math.floor(rand() * 50)
		local fh = 90 + math.floor(rand() * 70)
		ShopFx.flame(
			face,
			UDim2.new(0, i * 146 + math.floor(rand() * 30), 1, 6),
			fw,
			fh,
			if i % 2 == 0 then hex("#ff8a2e") else hex("#ff5a1a"),
			0.35,
			2
		)
	end
	ShopFx.bolt(face, UDim2.fromOffset(500, 70), 230, 18, hex("#ffd84a"), 1, 3, 5.2, false)
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
				pulse(button.Face, true)
			end
		end
	end
	-- the rarest golem big, the shard egg, its chance
	local count = #edition.Golems
	local hero = edition.Golems[count]
	ShopFx.glow(face, UDim2.fromOffset(512, math.floor(h * 0.5)), 150, hex("#ffdc78"), 2, 1)
	if hero then
		local heroPicture = livePicture(frame, "golem_" .. hero.Id, "golem_" .. hero.Id, 226, {
			Name = "Hero",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(510, math.floor(h * 0.44)),
			ZIndex = 6,
		})
		float(heroPicture)
		if heroPicture then
			heroPicture:SetAttribute("Swing", 2.5) -- (it rocks a little as it floats)
		end
	end
	if edition.CapsuleId then
		-- the shard egg glows and now and then wobbles as if about to hatch
		local glow = ShopFx.glow(face, UDim2.fromOffset(430, h - 70), 78, hex("#ffeaa0"), 2, 1)
		glow:SetAttribute("ShopFx", "Glow")
		local shardName = "capsule_" .. edition.CapsuleId
		hatch(
			livePicture(frame, shardName, shardName, 100, {
				Name = "Shard",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(430, h - 70),
				Rotation = -12,
				ZIndex = 7,
			}),
			4
		)
	end
	local heroChip = ShopFx.chip(frame, "", 190, 30, 16, {
		Name = "HeroChance",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(560, h - 44),
	}, { hex("#ff3a6a"), hex("#8a0a3a") })
	wiggle(heroChip, 2)
	local heroLabel = ShopFx.chipLabel(heroChip) :: TextLabel
	-- embers rise from the flames in front of the dragon king (PC and TV)
	motes(frame, {
		{ 412, h - 6, 14, -196, 24, 3.1 },
		{ 462, h - 12, -10, -224, 18, 3.7 },
		{ 520, h - 4, 18, -176, 28, 2.8 },
		{ 574, h - 10, -16, -232, 20, 3.9 },
		{ 616, h - 6, 10, -204, 23, 3.4 },
		{ 448, h - 2, 22, -160, 17, 2.5 },
	}, "glow", { hex("#fff1a8"), hex("#ffd36a"), WHITE }, 0, 7)
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
	ShopFx.rays(face, UDim2.fromOffset(150, 196), 700, 0.45, 2, WHITE, 32)
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
	ShopFx.bolt(face, UDim2.fromOffset(300, math.floor(h / 2)), h + 40, 8, WHITE, 3, 3, 4.8, false)
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
	-- the egg floats, its glow breathes, and now and then it wobbles as if about to hatch
	local glow = ShopFx.glow(face, UDim2.fromOffset(150, 200), 110, WHITE, 2, 1)
	glow:SetAttribute("ShopFx", "Glow")
	local egg = livePicture(frame, "capsule_Royal", "capsule_Royal", 160, {
		Name = "Egg",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(150, 196),
		ZIndex = 6,
	})
	hatch(egg)
	-- gold sparkles rise round it (PC and TV)
	motes(frame, {
		{ 76, h - 16, 10, -150, 20, 3.4 },
		{ 118, h - 6, -8, -122, 14, 2.8 },
		{ 182, h - 12, 12, -168, 23, 3.9 },
		{ 226, h - 22, -14, -132, 16, 3.1 },
		{ 254, h - 8, 6, -150, 13, 2.6 },
	}, "sparkle", { hex("#ffe27a"), hex("#fff6c2"), hex("#ffd04a") }, 0.1, 7)
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

-- (forward: StoreView.selectTab builds a page the first time it opens)
local buildPage: (refs: Refs, id: string) -> boolean

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
				-- (held by its middle: it pops in, grows and squashes about its centre)
				card.Holder.Position = UDim2.fromOffset(x + math.floor(widths[i] / 2), y + math.floor(h / 2))
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

-- Does a tab have anything to show (a banner, a card not hidden)? From what the controller said: built or not.
function StoreView.hasContent(refs: Refs, section: StoreConfig.Section): boolean
	if section.Banner == "Limited" and refs.Edition ~= nil then
		return true
	end
	if section.Banner == "Royal" and refs.RoyalShown and CapsuleConfig.ById.Royal ~= nil then
		return true
	end
	for _, spec in StoreConfig.Cards do
		local state = refs.States[spec.Id]
		if spec.Section == section.Id and (state == nil or state.State ~= "Hidden") then
			return true
		end
	end
	return false
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
		if refs.Built[section.Id] then
			placePage(refs, section)
		end
		local tab = refs.TabRefs[section.Id]
		if tab then
			tab.Holder.Visible = StoreView.hasContent(refs, section)
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

-- A face's gradient colours (its "Paint").
local function paintOn(frame: Instance): UIGradient?
	local paint = frame:FindFirstChild("Paint")
	return if paint and paint:IsA("UIGradient") then paint else nil
end

--[[
	Paints the header, the body and the window's light in tab `id`'s colour
	world. `animate`: the old colours stay on a layer over the new ones and
	fade out, the glow and the bolts change colour smoothly (ShopFx.fadeOut,
	ShopFx.recolor); else at once.
]]
local function paintWorld(refs: Refs, id: string, animate: boolean)
	local theme = ShopFx.Themes[id] or ShopFx.Themes.Featured
	local root = refs.Window.Root
	local header, body = refs.Window.Header, refs.Window.Body
	local fill = root:FindFirstChild("HeaderFill")
	local layers: { { GuiObject } } = {}
	local overHeader = root:FindFirstChild("HeaderOver")
	local overFill = root:FindFirstChild("HeaderOverFill")
	local overBody = body:FindFirstChild("BodyOver")
	for _, pair in { { overHeader, header }, { overFill, fill }, { overBody, body } } do
		local over, under = pair[1], pair[2]
		if over and over:IsA("GuiObject") and under and under:IsA("GuiObject") then
			table.insert(layers, { over, under })
		end
	end
	if animate then
		-- the look as it is now goes on the layers over, which then fade out
		for _, pair in layers do
			local overPaint, underPaint = paintOn(pair[1]), paintOn(pair[2])
			if overPaint and underPaint then
				overPaint.Color = underPaint.Color
			end
		end
	end
	ShopFx.repaint(header, theme.Head)
	-- (the band's lower half: its gradient from the middle down)
	local lower = ShopFx.sequence({ theme.Head[1]:Lerp(theme.Head[2], 0.9), theme.Head[2], theme.Head[3] }, { 0, 0.1, 1 })
	local fillPaint = if fill then paintOn(fill) else nil
	if fillPaint then
		fillPaint.Color = lower
	end
	ShopFx.repaint(body, theme.Body)
	for _, pair in layers do
		if animate then
			ShopFx.fadeOut(pair[1])
		else
			pair[1].BackgroundTransparency = 1
		end
	end
	local title = refs.Window.Title
	local fillGradient = title:FindFirstChild("Fill")
	if fillGradient and fillGradient:IsA("UIGradient") then
		fillGradient.Color = ShopFx.sequence({ WHITE, WHITE, theme.Title }, { 0, 0.4, 1 })
	end
	for _, fxRoot in refs.Fx do
		for _, d in fxRoot:GetDescendants() do
			if d:IsA("GuiObject") then
				local color: Color3? = nil
				local property = "ImageColor3"
				if d:GetAttribute("WorldGlow") then
					color, property = theme.Glow, "BackgroundColor3"
				elseif d.Name == "Bolt" and d:IsA("ImageLabel") and d:GetAttribute("Icon") ~= "shop_bolt" then
					color = if d:GetAttribute("Second") == true then theme.Bolt2 else theme.Bolt
				elseif d.Name == "Dots" or d.Name == "Burst" then
					color = theme.Bolt2
					if d:IsA("Frame") then
						color = nil
					end
				elseif d.Name == "Sparkle" and d:IsA("ImageLabel") and d:GetAttribute("Icon") == "shopfx_sparkle" then
					color = if d:GetAttribute("Second") then theme.Bolt2 else WHITE
				end
				if color then
					if animate then
						ShopFx.recolor(d, property, color)
					else
						(d :: any)[property] = color
					end
				end
			end
		end
	end
end

--[[
	Shows tab `id`'s page and its colours, building the page the first time
	(lazy). `animate`: the colours fade over, the page slides in, its cards
	pop in one after another. Returns whether the open tab changed and
	whether its page was built just now (the controller wires it).
]]
function StoreView.selectTab(refs: Refs, id: string, animate: boolean?): (boolean, boolean)
	if not refs.Pages[id] then
		return false, false
	end
	local built = buildPage(refs, id)
	local changed = refs.Current ~= id
	refs.Current = id
	for pageId, page in refs.Pages do
		page.Visible = pageId == id
	end
	-- its 3D pictures, the first time it shows
	local page = refs.Pages[id]
	if page:GetAttribute("Filled") ~= true then
		page:SetAttribute("Filled", true)
		fill(page)
	end
	if built then
		StoreView.relayout(refs)
		if refs.Current ~= id then
			return true, true -- (its page had nothing to show: relayout opened the first that has)
		end
	end
	local moving = animate == true and changed
	paintWorld(refs, id, moving)
	placeTabs(refs)
	sizeCanvas(refs)
	if changed then
		refs.Scroller.CanvasPosition = Vector2.new(0, 0)
	end
	if moving then
		ShopFx.slideIn(page, UDim2.fromOffset(StoreView.Pad, StoreView.PadTop), 40)
		local holders: { GuiObject } = {}
		for _, specId in refs.Order do
			local card = refs.Cards[specId]
			if card and card.Spec.Section == id and card.Holder.Visible then
				table.insert(holders, card.Holder)
			end
		end
		ShopFx.popIn(holders)
		-- the picked tab's picture pops
		local tab = refs.TabRefs[id]
		local icon = if tab then tab.Icon else nil
		if icon then
			ShopFx.popIcon(icon)
		end
	end
	return changed, built
end

--[[
	The header comes in as the window opens (ShopFx.cascade): the SHOP title
	(its dark copy and its light band) drops into place, the basket and the
	shown tabs pop in left to right, the X spins in.
]]
function StoreView.cascade(refs: Refs)
	local root = refs.Window.Root
	local drops: { GuiObject } = {}
	local title = refs.Window.Title
	if title.Visible then
		table.insert(drops, title)
		for _, suffix in { "Shadow", "Glint" } do
			local copy = root:FindFirstChild(title.Name .. suffix)
			if copy and copy:IsA("GuiObject") then
				table.insert(drops, copy)
			end
		end
	end
	local pops: { GuiObject } = {}
	local basket = root:FindFirstChild("Basket")
	if basket and basket:IsA("GuiObject") then
		table.insert(pops, basket)
	end
	for _, id in StoreView.visibleTabs(refs) do
		table.insert(pops, refs.TabRefs[id].Lift)
	end
	local close = refs.Window.Close.Parent
	ShopFx.cascade({ Drops = drops, Pops = pops, Spin = if close and close:IsA("GuiObject") then close else nil })
end

-- Where `gui`'s middle is in the window group's units (its front layer's): a card on the open page
-- or a banner's buy button, from the layout's own numbers (the page's scroll included).
local function inFront(refs: Refs, gui: GuiObject): UDim2
	local page = refs.Pages[refs.Current]
	local x = gui.Position.X.Offset + (0.5 - gui.AnchorPoint.X) * gui.Size.X.Offset
	local y = gui.Position.Y.Offset + (0.5 - gui.AnchorPoint.Y) * gui.Size.Y.Offset
	local parent = gui.Parent
	-- (a banner's button: the banner sits at the page's top-left)
	if parent and parent ~= page and parent:IsA("GuiObject") and parent.Parent == page then
		x += parent.Position.X.Offset
		y += parent.Position.Y.Offset
	end
	local rim = StoreView.Rim
	local scroll = refs.Scroller.CanvasPosition
	return UDim2.fromOffset(rim + StoreView.Pad + x - scroll.X, rim + (refs.Metrics.Header - rim) + StoreView.PadTop + y - scroll.Y)
end

--[[
	A purchase of `key` went through (StoreController: Roblox's prompt
	finished with a purchase the shop asked for): the card that sells it
	(or the limited banner's button) flashes and pops, stars fly out of it
	(coins for a coin pack) over the window (ShopFx.celebrate). Returns
	whether it showed (its page is open and built). Quiet: nothing moves.
]]
function StoreView.celebrate(refs: Refs, key: string): boolean
	local front = refs.Front
	local product = MonetizationConfig.Products[key]
	local picture = if product and product.CoinPack then "coin" else "star"
	for _, id in refs.Order do
		local card = refs.Cards[id]
		if card and card.Spec.Section == refs.Current and card.Holder.Visible and card.Buys[key] then
			ShopFx.celebrate(card.Holder, CORNER, front, inFront(refs, card.Holder), picture, #id)
			return true
		end
	end
	local banner = refs.Banner
	if banner and refs.Current == "Featured" then
		for _, face in banner.Buys do
			local holder = face.Parent
			if face:GetAttribute("Key") == key and holder and holder:IsA("GuiObject") then
				ShopFx.celebrate(face, ShopFx.ButtonCorner, front, inFront(refs, holder), picture, 3)
				return true
			end
		end
	end
	return false
end

-- The pages built since the last call (the controller wires their buttons).
function StoreView.takeBuilt(refs: Refs): { string }
	local fresh = refs.Fresh
	refs.Fresh = {}
	return fresh
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
	-- (held by its middle: the open tab bobs it, a press squashes it about its centre)
	local lift = UIKit.new("Frame", {
		Name = "Lift",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	}, holder)
	lift:SetAttribute("ShopFx", "Bob")
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = theme.TabGlow,
		BackgroundTransparency = 0.62,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 18, 1, 18),
		Visible = false,
		ZIndex = 6,
	}, lift)
	UIKit.corner(glow, 25)
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
	ShopFx.studs(face, width, h, 17, 0.25, 7)
	ShopFx.bindPress(face, lift)
	-- the picture: the sheet's once uploaded, else the live model (the open tab's wiggles)
	local pictureAt = UDim2.fromOffset(math.floor(icon * 0.32), math.floor(h * 0.42))
	local image: GuiObject? = ShopFx.icon(lift, section.TabIcon, icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pictureAt,
		ZIndex = 9,
	})
	if not image and section.TabModel then
		image = modelPicture(lift, section.TabModel, section.TabModel, icon, pictureAt, 9)
	end
	wiggle(image, 6)
	local label = ShopFx.text(lift, section.Tab, word, {
		Name = "Word",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, room + 2, 0.5, -1),
		Size = UDim2.new(1, -(room + 6), 0, word + 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	}, nil, 2)
	ShopFx.limit(label, word, 10)
	return { Holder = holder, Lift = lift, Face = face, Scale = scale, Ring = ring, Glow = glow, Icon = image, Width = width }
end

-- A lightning bolt in the window's world: its middle, length and turn (Second: the theme's second colour).
type BoltSpec = { At: Vector2, Length: number, Rotation: number, Variant: number, Second: boolean, Period: number }

--[[
	The window's world: the glow round it, the open burst (hidden until the
	window opens), bolts striking past its edges and sparkles on its frame
	(a phone: neither, the ambient effects stay off small screens).
	Returns the effects' roots and the burst.
]]
local function buildWorld(group: Frame, size: Vector2, m: Metrics): ({ Instance }, GuiObject)
	local back = UIKit.new("Frame", {
		Name = "Back",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, group)
	for i, s in { { 56, 0.9 }, { 20, 0.8 } } do
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
	-- the burst of rays behind the window as it opens (ShopFx.open); a soft flash before the upload
	local burst: GuiObject? = ShopFx.sprite(back, "rays", {
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = ShopFx.Themes.Featured.Bolt,
		ImageTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1500, 1500),
		Visible = false,
		ZIndex = 0,
	})
	if not burst then
		local flash = UIKit.new("Frame", {
			Name = "Burst",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 60, 1, 60),
			Visible = false,
			ZIndex = 0,
		}, back)
		UIKit.corner(flash, StoreView.Corner + 30)
		burst = flash
	end
	local w, h = size.X, size.Y
	local front = UIKit.new("Frame", {
		Name = "Front",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	}, group)
	if not m.Compact then
		local bolts: { BoltSpec } = {
			{ At = Vector2.new(-16, 110), Length = 300, Rotation = 17, Variant = 1, Second = false, Period = 5 },
			{ At = Vector2.new(w + 20, 143), Length = 346, Rotation = -15, Variant = 2, Second = false, Period = 6.2 },
			{ At = Vector2.new(w - 5, h - 110), Length = 309, Rotation = -155, Variant = 3, Second = true, Period = 7 },
			{ At = Vector2.new(-10, h - 70), Length = 233, Rotation = 149, Variant = 1, Second = true, Period = 5.6 },
		}
		for _, b in bolts do
			local bolt = ShopFx.bolt(
				back,
				UDim2.fromOffset(b.At.X, b.At.Y),
				b.Length,
				b.Rotation,
				ShopFx.Themes.Featured.Bolt,
				b.Variant,
				0,
				b.Period
			)
			if bolt then
				bolt:SetAttribute("Second", b.Second)
				bolt:SetAttribute("Ambient", true)
			end
		end
		local sparkles: { { X: number, Y: number, Size: number, Second: boolean } } = {
			{ X = w - 14, Y = 11, Size = 40, Second = false },
			{ X = w - 34, Y = 44, Size = 18, Second = true },
			{ X = 8, Y = h - 14, Size = 34, Second = false },
			{ X = 36, Y = h - 26, Size = 14, Second = true },
			{ X = math.floor(w * 0.38), Y = 2, Size = 24, Second = false },
			{ X = math.floor(w * 0.78), Y = h - 2, Size = 20, Second = true },
		}
		for i, sp in sparkles do
			local sparkle = ShopFx.sparkle(front, UDim2.fromOffset(sp.X, sp.Y), sp.Size, WHITE, 20, i)
			sparkle:SetAttribute("Second", sp.Second)
			sparkle:SetAttribute("Ambient", true)
		end
	end
	return { back, front }, burst :: GuiObject
end

---------------------------------------------------------------- what the cards show (kept, shown once built)

-- A card shows what the controller said about it: its product (the blaster's band), its state, its lines.
local function applyCard(refs: Refs, id: string)
	local card = refs.Cards[id]
	local record = refs.States[id]
	if not card or not record then
		return
	end
	local key, state = record.Key, record.State
	local product = MonetizationConfig.Products[key]
	if not product then
		return
	end
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
	local moved = card.Holder.Visible ~= (state ~= "Hidden")
	card.Holder.Visible = state ~= "Hidden"
	local shows = state == "Buy" or state == "Pending" or state == "Locked"
	for _, face in card.Buys do
		local priceHolder = face.Parent
		if priceHolder and priceHolder:IsA("GuiObject") then
			moved = moved or priceHolder.Visible ~= shows
			priceHolder.Visible = shows
		end
		face.Active = state == "Buy"
	end
	if moved then
		refs.Marks += 1 -- (its shine and rays stop or start with it)
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
	local owned = card.Owned
	if owned then
		owned.Visible = state == "Owned"
	end
	card.Button.Active = state == "Buy" and card.Button.Selectable
	card.Shade.Visible = state == "Pending" or (state == "Locked" and card.Spec.Look ~= "Star")
	if record.Note and card.Note then
		ShopFx.setText(card.Note, record.Note)
	end
	if record.Big and card.Big then
		ShopFx.setText(card.Big, record.Big)
	end
end

-- The coin amounts at the income the controller gave; the best pack gold with its sticker, breathing.
local function applyCoins(refs: Refs)
	local income = refs.Income
	if income == nil then
		return
	end
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
			if pulse(card.Price, isBest) then
				refs.Marks += 1
			end
		end
	end
end

-- The Royal Egg banner as the controller set it (shown or not, the chances, Triple Lucky).
local function applyRoyal(refs: Refs)
	local royal = refs.Royal
	if not royal then
		return
	end
	if royal.Frame.Visible ~= refs.RoyalShown then
		refs.Marks += 1
	end
	royal.Frame.Visible = refs.RoyalShown
	local odds = refs.RoyalOdds
	if odds then
		for id, label in royal.Chances do
			ShopFx.setText(label, StoreView.percent(odds[id] or 0))
		end
	end
	local chip = royal.Lucky.Parent
	if chip and chip:IsA("GuiObject") then
		chip.Visible = refs.RoyalLucky
	end
end

-- The limited banner's chances, the big one's chip, Triple Lucky and the time left.
local function applyBanner(refs: Refs)
	local banner = refs.Banner
	if not banner then
		return
	end
	local odds = refs.EditionOdds
	if odds then
		for id, label in banner.Chances do
			ShopFx.setText(label, StoreView.percent(odds[id] or 0))
		end
		local golems = banner.Edition.Golems
		local hero = golems[#golems]
		if hero then
			ShopFx.setText(banner.Hero, `{hero.Name} {StoreView.percent(odds[hero.Id] or 0)}`)
		end
	end
	local tag = banner.Lucky.Parent
	if tag and tag:IsA("GuiObject") then
		tag.Visible = refs.EditionLucky
	end
	local left = refs.EditionLeft
	if left then
		ShopFx.setText(banner.Timer, `{StoreView.endsOn(banner.Edition.EndsAt)} · {StoreView.countdown(left)}`)
	end
end

-- The limited banner as the controller set it, once FEATURED is built: made, replaced or removed.
local function makeBanner(refs: Refs)
	local edition = refs.Edition
	local old = refs.Banner
	if old and (not edition or old.Edition.Id ~= edition.Id) then
		old.Frame:Destroy()
		refs.Banner = nil
		refs.Marks += 1
	end
	if edition and not refs.Banner and refs.Built.Featured then
		local banner = buildBanner(refs.Pages.Featured, edition, refs.Metrics)
		refs.Banner = banner
		refs.Marks += 1
		if refs.Pages.Featured:GetAttribute("Filled") == true then
			fill(banner.Frame)
		end
	end
	applyBanner(refs)
end

-- Builds a tab's page (once): its banner, its cards, then what the controller already said about them.
buildPage = function(refs: Refs, sectionId: string): boolean
	local section = StoreConfig.SectionById[sectionId]
	local page = refs.Pages[sectionId]
	if refs.Built[sectionId] or not section or not page then
		return false
	end
	refs.Built[sectionId] = true
	table.insert(refs.Fresh, sectionId)
	local m = refs.Metrics
	if section.Banner == "Royal" then
		refs.Royal = buildRoyal(page)
		applyRoyal(refs)
	end
	for r, row in StoreConfig.rows(sectionId) do
		local h = rowHeight(section, r, m)
		local widths = rowWidths(row)
		for i, spec in row do
			local cardHolder = UIKit.new("Frame", {
				Name = spec.Id,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(widths[i], h),
				ZIndex = 4,
			}, page)
			UIKit.new("UIScale", { Name = "Scale", Scale = 1 }, cardHolder)
			local build = Looks[spec.Look] or Looks.Pass
			refs.Cards[spec.Id] = build(cardHolder, spec, widths[i], h, m)
		end
	end
	if sectionId == "Cash" then
		-- coins drift down the gaps between the first row's packs, over the cards (PC and TV)
		local row = StoreConfig.rows(sectionId)[1]
		if row and #row > 1 then
			local widths = rowWidths(row)
			local fall = rowHeight(section, 1, m) - 70
			local list: { Mote } = {}
			local x = 0
			for i = 1, #widths - 1 do
				x += widths[i]
				local gap = x + (i - 1) * StoreView.Gap + StoreView.Gap / 2
				table.insert(list, { math.floor(gap), 18 + (i % 2) * 26, (if i % 2 == 0 then 8 else -8), fall, 24, 3.6 + 0.35 * i })
			end
			motes(page, list, "shop_coin", { WHITE }, 0.05, 13)
		end
	end
	-- the Royal eggs' BEST VALUE (prices only: they never change)
	local royal: { string } = {}
	for _, spec in StoreConfig.Cards do
		if spec.Look == "Egg" then
			table.insert(royal, spec.Keys[1])
		end
	end
	local bestEgg = StoreView.bestValue(royal)
	for _, card in refs.Cards do
		if card.Spec.Look == "Egg" and card.Spec.Section == sectionId and card.Sticker then
			local best = card.Spec.Keys[1] == bestEgg
			card.Sticker.Visible = best
			if best then
				ShopFx.setStyle(card.Price, "Gold")
				pulse(card.Price, true)
			end
		end
	end
	for _, spec in StoreConfig.Cards do
		if spec.Section == sectionId then
			applyCard(refs, spec.Id)
		end
	end
	applyCoins(refs)
	if section.Banner == "Limited" then
		makeBanner(refs)
	end
	return true
end

--[[
	Builds the window for `metrics` (a PC's when nil; StoreController
	rebuilds it when the screen asks for other sizes: needsRebuild).
	`lazy` (the game): only the open tab's page now, every other page the
	first time it opens (selectTab); else every page at once (the specs,
	the previews).
]]
function StoreView.build(metrics: Metrics?, lazy: boolean?): Refs
	local m = metrics or StoreView.metricsFor(false, 1)
	local gui = UIKit.screen("TerraForgeStore", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("MotionSkip", true) -- (the shop pops itself: ShopFx.open; the motion watcher leaves it)
	gui:SetAttribute("Metrics", StoreView.metricsKey(m))
	-- a dim backdrop over the world
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = hex("#08041e"),
		BackgroundTransparency = StoreView.DimTransparency,
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
	local fx, burst = buildWorld(group, size, m)
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
	-- the body: the tab's colour world, its rays and bolts behind the cards
	local body = UIKit.new("Frame", {
		Name = "Body",
		ClipsDescendants = true,
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 1, -2 * rim),
		ZIndex = 2,
	}, root)
	ShopFx.face(body, theme.Body, StoreView.Corner - rim, 0, 90)
	-- (a tab's old colours fade out over its new ones: ShopFx.fadeOut)
	local bodyOver = UIKit.new("Frame", {
		Name = "BodyOver",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, body)
	ShopFx.face(bodyOver, theme.Body, StoreView.Corner - rim, 0, 90)
	bodyOver.BackgroundTransparency = 1
	local bodyFx = UIKit.new("Frame", {
		Name = "Fx",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, body)
	table.insert(fx, bodyFx)
	local bw = size.X - 2 * rim
	ShopFx.rays(bodyFx, UDim2.new(0.5, 0, 0, m.Header - 90), 900, 0.86, 2, WHITE, 60)
	local H = m.Header
	local inner: { BoltSpec } = {
		{ At = Vector2.new(96, H - 7), Length = 229, Rotation = -102, Variant = 2, Second = false, Period = 5.4 },
		{ At = Vector2.new(bw - 103, H + 410), Length = 277, Rotation = 55, Variant = 3, Second = false, Period = 6.6 },
		{ At = Vector2.new(bw - 78, H + 70), Length = 229, Rotation = 46, Variant = 1, Second = true, Period = 7.4 },
		{ At = Vector2.new(116, H + 437), Length = 259, Rotation = -107, Variant = 2, Second = true, Period = 6 },
	}
	for _, b in inner do
		local bolt = ShopFx.bolt(bodyFx, UDim2.fromOffset(b.At.X, b.At.Y), b.Length, b.Rotation, theme.Bolt, b.Variant, 2, b.Period, false)
		if bolt then
			bolt:SetAttribute("Second", b.Second)
		end
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
	-- the old colours' layers (they fade out when a tab changes)
	local headerOver = UIKit.new("Frame", {
		Name = "HeaderOver",
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 0, m.Header - rim),
		ZIndex = 4,
	}, root)
	ShopFx.face(headerOver, theme.Head, StoreView.Corner - rim, 0, 90)
	headerOver.BackgroundTransparency = 1
	local fillOver = UIKit.new("Frame", {
		Name = "HeaderOverFill",
		Position = UDim2.fromOffset(rim, rim + math.floor((m.Header - rim) / 2)),
		Size = UDim2.new(1, -2 * rim, 0, math.ceil((m.Header - rim) / 2)),
		ZIndex = 4,
	}, root)
	ShopFx.face(fillOver, theme.Head, 0, 0, 90)
	fillOver.BackgroundTransparency = 1
	local band = UIKit.new("Frame", {
		Name = "Band",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 0, m.Header - rim),
		ZIndex = 5,
	}, root)
	ShopFx.studs(band, bw, m.Header - rim, 28, 0.15, 5)
	ShopFx.shards(band, 5)
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
	-- a warm light band slides across it now and then (its copy's mark "Glint": a window loop)
	local glint = ShopFx.glint(title)
	table.insert(fx, glint)
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
	ShopFx.studs(close, m.Close, m.Close, 18, 0.2, 9)
	ShopFx.bindPress(close, closeHolder)
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
		Front = fx[2] :: Frame,
		Burst = burst,
		Current = StoreConfig.Sections[1].Id,
		Fit = 1,
		Compact = m.Compact,
		Lean = m.Compact,
		Metrics = m,
		Built = {},
		Fresh = {},
		States = {},
		Edition = nil,
		EditionLeft = nil,
		EditionOdds = nil,
		EditionLucky = false,
		RoyalShown = true,
		RoyalOdds = nil,
		RoyalLucky = false,
		Income = nil,
		Marks = 0,
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
	end
	for _, spec in StoreConfig.Cards do
		table.insert(refs.Order, spec.Id)
		refs.States[spec.Id] = { Key = spec.Keys[1], State = "Buy", Note = nil, Big = nil }
	end
	if lazy then
		buildPage(refs, refs.Current)
	else
		for _, section in StoreConfig.Sections do
			buildPage(refs, section.Id)
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
-- Kept for a page that isn't built yet (it shows it when it is).
function StoreView.setCard(refs: Refs, id: string, key: string, state: string)
	local record = refs.States[id]
	if not record or not MonetizationConfig.Products[key] then
		return
	end
	local wasHidden = record.State == "Hidden"
	record.Key = key
	record.State = state
	applyCard(refs, id)
	if wasHidden ~= (state == "Hidden") then
		StoreView.relayout(refs)
	end
end

-- A card's note ("Opens at rebirth 3", the blaster's rebirth rule, Server Luck running).
function StoreView.setNote(refs: Refs, id: string, text: string)
	local record = refs.States[id]
	if record then
		record.Note = text
	end
	local card = refs.Cards[id]
	local note = if card then card.Note else nil
	if note then
		ShopFx.setText(note, text)
	end
end

-- A card's big line ("LV 4 > LV 5" on the blaster card).
function StoreView.setBig(refs: Refs, id: string, text: string)
	local record = refs.States[id]
	if record then
		record.Big = text
	end
	local card = refs.Cards[id]
	local big = if card then card.Big else nil
	if big then
		ShopFx.setText(big, text)
	end
end

-- The coin amounts at a podium income of `income` coins per second (and the best pack's sticker).
function StoreView.setCoins(refs: Refs, income: number)
	refs.Income = income
	applyCoins(refs)
end

-- The Royal Egg's tiles: the chances a buy rolls now (with Triple Lucky while it runs).
function StoreView.setRoyalOdds(refs: Refs, odds: { [string]: number }, lucky: boolean)
	refs.RoyalOdds = odds
	refs.RoyalLucky = lucky
	applyRoyal(refs)
end

-- Shows or hides the Royal Egg banner (paid random: hidden where restricted).
function StoreView.setRoyalShown(refs: Refs, shown: boolean)
	if refs.RoyalShown ~= shown then
		refs.RoyalShown = shown
		applyRoyal(refs)
		StoreView.relayout(refs)
	end
end

--[[
	Shows the limited edition at the top of FEATURED (nil removes it).
	Returns its refs once FEATURED is built (the controller wires the
	buttons and the timer); nil before.
]]
function StoreView.setEdition(refs: Refs, edition: Edition?): BannerRefs?
	local before = refs.Edition
	local same = before ~= nil and edition ~= nil and before.Id == edition.Id
	local had = refs.Banner
	refs.Edition = edition
	makeBanner(refs)
	if not same or refs.Banner ~= had then
		StoreView.relayout(refs)
	end
	return refs.Banner
end

-- The chances on the banner's tiles (the capsule's odds now: with Triple
-- Lucky while it runs, so they match the odds panel and what a buy rolls).
function StoreView.setBannerOdds(refs: Refs, odds: { [string]: number }, lucky: boolean)
	refs.EditionOdds = odds
	refs.EditionLucky = lucky
	applyBanner(refs)
end

-- The banner's end date and time left (seconds; 0 = ended).
function StoreView.setTimer(refs: Refs, secondsLeft: number)
	refs.EditionLeft = secondsLeft
	applyBanner(refs)
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
