--[[
	RevealFx: the "you got it" moment, shared by the reveals in the game so
	they look like one family: the secret ores' jackpot (Effects/SecretReveal,
	the "Návrhy strojů" chat) and, later, the Vault's cases. The egg opening
	(owner 2026-10-29, the clicker-sim video: UI/HatchStage) has its own clean
	look now and shares the flash cap and RevealKit's rings and flash. Our own
	look: no picture or sound of another game.

	A thin wrapper over Effects/RevealKit (the drawing parts every reveal
	shares, owned by the secret ores' chat): the flash gap is RevealKit's ONE
	tracker (claimFlash / flash: RevealKit.takeFlash), the flash frame is
	RevealKit.flash / poseFlash, the rays are RevealKit.rays / poseRays (the
	"Secret" tier exactly RevealKit's secret look; the other tiers its bars in
	their rarity's colours: poseRays' Paint). RevealFx adds the tiers, the
	palette, the banner (name, rarity pill, chance, NEW!), the headline, the
	glow, the sparkles and the confetti.

	API
	  RevealFx.show(kind, itemId, rarity, opts?) -> Handle
	    kind     "Golem" | "Ore" | any: only picks the default name
	    itemId   the golem kind / the ore id
	    rarity   a Rarity id (Common .. Mythic) or "Secret"
	    opts (every field optional):
	      Parent   GuiObject | ScreenGui to draw in (default: its own ScreenGui
	               "TerraForgeReveal", DisplayOrder 45, IgnoreGuiInset)
	      Center   UDim2: the reveal's middle in Parent (default 0.5, 0.42)
	      Size     the rays' diameter, design units (default 620)
	      Scale    design units -> px (the caller's HUD scale; default 1)
	      Name     the banner's big line (default: the item's name)
	      Chance   the line under the rarity ("2.5%", "1 in 25,000"); nil: none
	      Headline the big word over the item (default per tier: none,
	               "EPIC!", "LEGENDARY!", "MYTHIC!", "SECRET!")
	      Tier     "Normal" | "Rare" | "Jackpot" | "Secret" (default: tierOf(rarity))
	      New      the NEW! sticker
	      Banner   false: no name / rarity / chance banner
	      Flash    false: no flash;  Sound false: silent;  Shake false: no nudge
	      Reduced  (default Motion.reduced()): still, faded, no flash or shake
	      ZIndex   the rays' base: the caller's picture goes at ZIndex + 2, the
	               banner and the headline are at ZIndex + 4
	      Manual   true: no frame loop (the caller poses: handle:pose(t))
	      Phone    true: fewer rays and pieces (default: a touch screen)
	  Handle: handle:close() fades it and frees it (back to the pool),
	          handle:setCenter(UDim2), handle:pose(t) (seconds since show),
	          handle.Root (the Frame it draws in), handle.Tier
	  Helpers: RevealFx.tierOf(rarity), RevealFx.palette(rarity),
	           RevealFx.rayColor(rarity, i, n, t), RevealFx.flash(parent,
	           color, strength) -> boolean (the shared cap), RevealFx.flashOk,
	           RevealFx.FlashGap = 0.4

	LOOK
	  Rays (RevealKit's bars through the middle, its speeds; a soft round glow behind):
	    Normal  (Common, Uncommon)   6 bars (12 rays), the rarity's colour 35 % to white
	    Rare    (Rare, Epic)         8 bars, the colour and its dark shade; 12 sparkles
	    Jackpot (Legendary, Mythic)  10 bars and RevealKit's back layer; Legendary gold
	                                 (255,214,64)/(255,176,32), Mythic a rainbow drifting 0.2 turn/s;
	                                 confetti 40 (phones 24), a camera nudge, the headline
	    Secret  ("Secret")           exactly RevealKit's secret look (near-black and its rainbow,
	                                 the back and gold layers); gold-white flash
	    Phones: RevealKit's 6 front bars (12 rays), no back layer; sparkles 10, confetti 24.
	  Banner (under the item; design units; the Round look's Montserrat):
	    name 46 Heavy white with a 4-unit dark edge; the rarity pill 34 tall,
	    round ends, the rarity's colour (top 15 % to white, bottom its dark
	    shade), a 3-unit dark border, "LEGENDARY" 22 Heavy; the chance 22 Bold
	    white with a 2-unit edge; NEW! a lime sticker. The headline 64 Heavy:
	    the LETTERS carry the colour (a UIGradient on the label: Legendary gold,
	    Mythic and Secret "SECRET!" a drifting rainbow) on a plain 5-unit
	    PopTheme.Outline edge (a gradient on a stroke smudges inside the letters). 18 px and more at 1080p (the HUD's 1.25), 8 pt on phones.
	  Flash: one shared clock, never sooner than FlashGap (0.4 s: 2.5 a
	    second) after the last anywhere; peak 0.9 opaque, gone in 0.45 s;
	    none with Reduce motion. It sits UNDER the caller's picture (ZIndex
	    + 1): the item is never covered (golems stay solid).
	Pure parts (tierOf, palette, rayColor, flashOk, the pose curves) are
	specced in tests/RevealShow.spec.luau.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig)
local OreData = require(Shared.Config.OreData)
local PopTheme = require(Shared.Config.PopTheme)
local Rarity = require(Shared.Config.Rarity)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Pop = require(script.Parent.Parent.UI.Pop)
local Confetti = require(script.Parent.Parent.UI.Confetti)
local Motion = require(script.Parent.Parent.UI.Motion)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local CameraShake = require(script.Parent.CameraShake)
local RevealKit = require(script.Parent.RevealKit)
local Sfx = require(script.Parent.Sfx)

local RevealFx = {}

RevealFx.FlashGap = RevealKit.FlashGap -- seconds between two flashes, anywhere (2.5 a second at most: RevealKit's one tracker)
RevealFx.FlashPeak = RevealKit.Style.FlashPeak -- the flash's strongest (1 - BackgroundTransparency)
RevealFx.FlashTime = RevealKit.Style.FlashTime -- its fade
RevealFx.Size = 620 -- the rays' diameter (design units)
RevealFx.PhoneRays = RevealKit.Style.Rays.Phone * 2 -- (RevealKit's front bars on a phone: two rays a bar)
RevealFx.PhoneSparkles = 10
RevealFx.PhoneConfetti = 24
RevealFx.BannerIn = 0.15 -- seconds after show: the name comes in, the pill and the chance after it

export type Tier = {
	Name: string,
	Rays: number,
	Speed: number, -- degrees a second
	Back: number, -- the second layer's (0: one layer)
	Sparkles: number,
	Confetti: number,
	Shake: number, -- CameraShake trauma
	Headline: boolean,
}

RevealFx.Tiers = {
	Normal = { Name = "Normal", Rays = 12, Speed = 20, Back = 0, Sparkles = 0, Confetti = 0, Shake = 0, Headline = false },
	Rare = { Name = "Rare", Rays = 16, Speed = 30, Back = 0, Sparkles = 12, Confetti = 0, Shake = 0, Headline = false },
	Jackpot = { Name = "Jackpot", Rays = 20, Speed = 40, Back = -25, Sparkles = 18, Confetti = 40, Shake = 0.55, Headline = true },
	Secret = { Name = "Secret", Rays = 20, Speed = 45, Back = -30, Sparkles = 18, Confetti = 40, Shake = 0.65, Headline = true },
} :: { [string]: Tier }

export type Palette = {
	Light: Color3, -- the rays' bright tone
	Dark: Color3, -- their second tone
	Glow: Color3, -- the soft disc behind the item
	Flash: Color3,
	Text: Color3, -- the rarity pill's paint
	TextDark: Color3,
	Rainbow: number, -- hue drift (turns a second; 0: none)
	Black: boolean, -- every other ray near-black (Secret)
}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local GOLD = rgb(255, 214, 64)
local GOLD_DEEP = rgb(255, 176, 32)
local SECRET_BLACK = rgb(14, 10, 22)
local SECRET_FLASH = rgb(255, 240, 200)

---------------------------------------------------------------- pure

-- The tier of a rarity: Common / Uncommon Normal, Rare / Epic Rare, Legendary / Mythic Jackpot, "Secret" Secret.
function RevealFx.tierOf(rarity: string): string
	if rarity == "Secret" then
		return "Secret"
	end
	local info = Rarity.ById[rarity]
	local order = if info then info.Order else 1
	return if order >= 5 then "Jackpot" elseif order >= 3 then "Rare" else "Normal"
end

-- The colours of a rarity's reveal.
function RevealFx.palette(rarity: string): Palette
	if rarity == "Secret" then
		return {
			Light = WHITE,
			Dark = SECRET_BLACK,
			Glow = rgb(255, 230, 160),
			Flash = SECRET_FLASH,
			Text = rgb(30, 24, 40),
			TextDark = SECRET_BLACK,
			Rainbow = 0.25,
			Black = true,
		}
	end
	local info = Rarity.ById[rarity] or Rarity.ById.Common
	if info.Id == "Legendary" then
		return {
			Light = GOLD,
			Dark = GOLD_DEEP,
			Glow = rgb(255, 228, 120),
			Flash = rgb(255, 244, 200),
			Text = info.Color,
			TextDark = info.DarkColor,
			Rainbow = 0,
			Black = false,
		}
	elseif info.Id == "Mythic" then
		return {
			Light = info.Color:Lerp(WHITE, 0.3),
			Dark = info.Color,
			Glow = info.Color:Lerp(WHITE, 0.45),
			Flash = info.Color:Lerp(WHITE, 0.6),
			Text = info.Color,
			TextDark = info.DarkColor,
			Rainbow = 0.2,
			Black = false,
		}
	end
	local rare = info.Order >= 3
	return {
		Light = info.Color:Lerp(WHITE, 0.35),
		Dark = if rare then info.Color:Lerp(info.DarkColor, 0.35) else info.Color:Lerp(WHITE, 0.6),
		Glow = info.Color:Lerp(WHITE, 0.4),
		Flash = info.Color:Lerp(WHITE, 0.55),
		Text = info.Color,
		TextDark = info.DarkColor,
		Rainbow = 0,
		Black = false,
	}
end

-- Ray `i` of `n` at `t` seconds: two tones, or a drifting rainbow (Mythic), or black and rainbow (Secret).
function RevealFx.rayColor(rarity: string, i: number, n: number, t: number): Color3
	local p = RevealFx.palette(rarity)
	if p.Black and i % 2 == 0 then
		return p.Dark
	end
	if p.Rainbow > 0 then
		local hue = ((i - 1) / math.max(1, n) + t * p.Rainbow) % 1
		return Color3.fromHSV(hue, 0.7, 1)
	end
	return if i % 2 == 1 then p.Light else p.Dark
end

-- May a flash go off now (`last`: the last one, anywhere)? Never sooner than FlashGap.
function RevealFx.flashOk(last: number, now: number): boolean
	return now - last >= RevealFx.FlashGap
end

-- The rays' scale `t` seconds in: a quick swell past full size, then full (Back ease, 0.3 s).
function RevealFx.swellAt(t: number): number
	local k = math.clamp(t / 0.3, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 0.4 + 0.6 * (1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2)
end

-- A banner part's appear (0 hidden .. 1 in place) `t` seconds after show, `delay` its turn.
function RevealFx.inAt(t: number, delay: number): number
	return math.clamp((t - RevealFx.BannerIn - delay) / 0.2, 0, 1)
end

-- The headline's scale `t` seconds in: a big pop (0.3 -> 1.15 -> 1 in 0.4 s).
function RevealFx.headlineAt(t: number): number
	local k = math.clamp(t / 0.4, 0, 1)
	if k < 0.6 then
		return 0.3 + (1.15 - 0.3) * (k / 0.6)
	end
	return 1.15 - 0.15 * ((k - 0.6) / 0.4)
end

-- The default headline of a tier and rarity (nil: none).
function RevealFx.headlineFor(tier: string, rarity: string): string?
	if tier == "Secret" then
		return "SECRET!"
	elseif tier == "Jackpot" then
		local info = Rarity.ById[rarity]
		return string.upper(if info then info.Name else rarity) .. "!"
	elseif rarity == "Epic" then
		return "EPIC!"
	end
	return nil
end

-- An item's default name.
local function nameOf(kind: string, itemId: string): string
	if kind == "Golem" then
		local golem = GolemConfig.ById[itemId]
		return if golem then golem.Name else itemId
	elseif kind == "Ore" then
		local ore = OreData.ById[itemId]
		return if ore then ore.Name else itemId
	end
	return itemId
end

---------------------------------------------------------------- the flash (shared)

-- Claims the shared flash clock (RevealKit.takeFlash, the game's one tracker): false when a flash
-- went off anywhere less than FlashGap ago, or with Reduce motion. (The egg opening asks here: HatchStage's Claim.)
function RevealFx.claimFlash(): boolean
	if Motion.reduced() then
		return false
	end
	return RevealKit.takeFlash(os.clock())
end

--[[
	A flash in `parent` (RevealKit.flash, made once per parent: "RevealFlash"),
	`color` at `strength` (0..1, never past FlashPeak), fading in FlashTime.
	Returns false when it didn't go off: too soon after the last one
	anywhere (FlashGap: RevealKit's tracker), or Reduce motion.
]]
function RevealFx.flash(parent: Instance, color: Color3, strength: number?, z: number?): boolean
	if not RevealFx.claimFlash() then
		return false
	end
	local frame = parent:FindFirstChild("RevealFlash")
	if not frame or not frame:IsA("Frame") then
		local made = RevealKit.flash(parent, z or 1)
		made.Name = "RevealFlash"
		frame = made
	end
	local f = frame :: Frame
	f.BackgroundColor3 = color
	-- (RevealKit's fade, frame by frame, gone in FlashTime)
	local start = os.clock()
	RevealKit.poseFlash(f, 0, strength)
	task.spawn(function()
		while f.Parent do
			task.wait()
			local u = (os.clock() - start) / RevealFx.FlashTime
			RevealKit.poseFlash(f, u, strength)
			if u >= 1 then
				break
			end
		end
	end)
	return true
end

---------------------------------------------------------------- the pieces

export type Options = {
	Parent: Instance?,
	Center: UDim2?,
	Size: number?,
	Scale: number?,
	Name: string?,
	Chance: string?,
	Headline: string?,
	Tier: string?,
	New: boolean?,
	Banner: boolean?,
	Flash: boolean?,
	Sound: boolean?,
	Shake: boolean?,
	Reduced: boolean?,
	ZIndex: number?,
	Manual: boolean?,
	Phone: boolean?,
}

export type Handle = {
	Root: Frame,
	Tier: string,
	Rarity: string,
	Layers: { Frame }, -- the rays' holder (RevealKit's bars in it)
	RayFrames: { { Frame } }, -- RevealKit's front and back bars
	Kit: RevealKit.Rays, -- RevealKit.rays (posed by RevealKit.poseRays)
	Glow: Frame,
	Banner: Frame,
	NameLabel: TextLabel,
	Pill: Frame,
	PillLabel: TextLabel,
	ChanceLabel: TextLabel,
	NewLabel: TextLabel,
	Headline: TextLabel,
	HeadlineGradient: UIGradient,
	Sparkles: { Frame },
	Confetti: { Frame },
	Spec: Tier,
	Reduced: boolean,
	Phone: boolean,
	Started: number,
	Seed: number,
	Gui: ScreenGui?, -- (its own, when no Parent was given)
	Connection: RBXScriptConnection?,
	Closed: boolean,
	pose: (self: Handle, t: number) -> (),
	close: (self: Handle) -> (),
	setCenter: (self: Handle, center: UDim2) -> (),
}

local function text(parent: Instance, name: string, size: number, z: number, font: Font): TextLabel
	local label = UIKit.new("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = font,
		Size = UDim2.fromOffset(600, size + 10),
		Text = "",
		TextColor3 = WHITE,
		TextSize = size,
		ZIndex = z,
	}, parent) :: TextLabel
	return label
end

local function edge(label: TextLabel, thickness: number): UIStroke
	local stroke = Pop.edge(label, thickness)
	return stroke
end

local seeds = 0

local function phoneNow(): boolean
	local ok, touch = pcall(MenuPanels.isTouch)
	return ok and touch == true
end

-- The frame loop's poses (Handle.pose).
local function pose(self: Handle, t: number)
	local spec = self.Spec
	local still = self.Reduced
	local swell = if still then 1 else RevealFx.swellAt(t)
	-- the rays: RevealKit's bars (Secret: its own secret look; the others in their rarity's colours)
	local rarity = self.Rarity
	local secret = self.Tier == "Secret"
	RevealKit.poseRays(self.Kit, if still then 0 else t, swell, 0, {
		Phone = self.Phone,
		Reduced = still,
		Gold = secret,
		Count = if secret then nil else math.max(1, math.floor(spec.Rays / 2)),
		Back = spec.Back ~= 0,
		Paint = if secret
			then nil
			else function(layer: string, k: number, count: number, at: number): Color3
				return RevealFx.rayColor(rarity, k + (if layer == "Back" then 1 else 0), count, at)
			end,
	})
	-- the glow breathes
	self.Glow.BackgroundTransparency = if still then 0.55 else 0.5 + 0.12 * math.sin(t * 3)
	-- the headline pops, its rainbow turns
	if self.Headline.Visible then
		local scale = self.Headline:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = if still then 1 else RevealFx.headlineAt(t)
		end
		if not still then
			self.HeadlineGradient.Offset = Vector2.new(math.sin(t * 2) * 0.3, 0)
		end
	end
	-- the banner comes in: the name, the pill, the chance
	local name = if still then 1 else RevealFx.inAt(t, 0)
	local pill = if still then 1 else RevealFx.inAt(t, 0.1)
	local chance = if still then 1 else RevealFx.inAt(t, 0.2)
	self.NameLabel.TextTransparency = 1 - name
	local nameEdge = self.NameLabel:FindFirstChildOfClass("UIStroke")
	if nameEdge then
		nameEdge.Transparency = 1 - name
	end
	self.NameLabel.Position = UDim2.new(0.5, 0, 0, 24 + (1 - name) * 14)
	self.Pill.BackgroundTransparency = 1 - pill
	self.PillLabel.TextTransparency = 1 - pill
	local pillEdge = self.Pill:FindFirstChildOfClass("UIStroke")
	if pillEdge then
		pillEdge.Transparency = 1 - pill
	end
	self.ChanceLabel.TextTransparency = 1 - chance
	local chanceEdge = self.ChanceLabel:FindFirstChildOfClass("UIStroke")
	if chanceEdge then
		chanceEdge.Transparency = 1 - chance
	end
	-- sparkles and confetti (none with Reduce motion)
	if not still then
		if #self.Sparkles > 0 then
			Confetti.pose(self.Sparkles, Vector2.new(0.5, 0.5), self.Seed, t * 0.9)
		end
		if #self.Confetti > 0 then
			Confetti.pose(self.Confetti, Vector2.new(0.5, 0.45), self.Seed + 7, t - 0.05)
		end
	end
end

local pool: { Handle } = {}

local function close(self: Handle)
	if self.Closed then
		return
	end
	self.Closed = true
	local connection = self.Connection
	if connection then
		connection:Disconnect()
		self.Connection = nil
	end
	self.Root.Visible = false
	self.Root.Parent = nil
	local gui = self.Gui
	if gui then
		gui:Destroy()
	end
	if #pool < 2 then
		table.insert(pool, self)
	else
		self.Root:Destroy()
	end
end

local function setCenter(self: Handle, center: UDim2)
	self.Root.Position = center
end

-- Builds a reveal's frames (once; pooled by close()).
local function build(): Handle
	local root = UIKit.new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(RevealFx.Size, RevealFx.Size),
	}) :: Frame
	UIKit.new("UIScale", { Name = "Fit", Scale = 1 }, root)
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
	}, root) :: Frame
	UIKit.corner(glow, 999)
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, glow)
	local banner = UIKit.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0.78, 0),
		Size = UDim2.fromOffset(600, 150),
	}, root) :: Frame
	local nameLabel = text(banner, "Name", 46, 1, PopTheme.Pixel)
	edge(nameLabel, 4)
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(190, 34),
	}, banner) :: Frame
	UIKit.corner(pill, 17)
	Pop.border(pill, 3)
	UIKit.new("UIGradient", { Name = "Paint", Rotation = 90 }, pill)
	local pillLabel = text(pill, "Rarity", 22, 1, PopTheme.Pixel)
	pillLabel.Position = UDim2.fromScale(0.5, 0.5)
	pillLabel.Size = UDim2.fromScale(1, 1)
	edge(pillLabel, 2.2)
	local chance = text(banner, "Chance", 22, 1, PopTheme.Font)
	chance.Position = UDim2.new(0.5, 0, 0, 112)
	edge(chance, 2)
	local new = text(banner, "New", 20, 1, PopTheme.Pixel)
	new.AnchorPoint = Vector2.new(0, 0.5)
	new.Size = UDim2.fromOffset(84, 30)
	new.Text = "NEW!"
	new.BackgroundColor3 = rgb(132, 214, 60)
	new.BackgroundTransparency = 0
	new.Rotation = -8
	UIKit.corner(new, 8)
	Pop.border(new, 2.5)
	edge(new, 2)
	local headline = text(root, "Headline", 64, 1, PopTheme.Pixel)
	headline.Position = UDim2.fromScale(0.5, 0.1)
	headline.Size = UDim2.fromOffset(700, 80)
	UIKit.new("UIScale", { Scale = 1 }, headline)
	edge(headline, 5) -- (a plain dark edge: a gradient on a text's stroke smudges inside the letters)
	local gradient = UIKit.new("UIGradient", { Name = "Paint" }, headline) :: UIGradient
	-- the rays: RevealKit's bars round the middle (a zero-size holder: their middle is its point)
	local holder = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
	}, root) :: Frame
	local kit = RevealKit.rays(holder, 2)
	local self = {
		Root = root,
		Tier = "Normal",
		Rarity = "Common",
		Layers = { holder },
		RayFrames = { kit.Front, kit.Back },
		Kit = kit,
		Glow = glow,
		Banner = banner,
		NameLabel = nameLabel,
		Pill = pill,
		PillLabel = pillLabel,
		ChanceLabel = chance,
		NewLabel = new,
		Headline = headline,
		HeadlineGradient = gradient,
		Sparkles = {},
		Confetti = {},
		Spec = RevealFx.Tiers.Normal,
		Reduced = false,
		Phone = false,
		Started = 0,
		Seed = 1,
		Gui = nil,
		Connection = nil,
		Closed = true,
		pose = pose,
		close = close,
		setCenter = setCenter,
	} :: Handle
	return self
end

local function pieces(parent: Instance, count: number, z: number, existing: { Frame }): { Frame }
	for _, piece in existing do
		piece:Destroy()
	end
	if count <= 0 then
		return {}
	end
	return Confetti.build(parent, count, z)
end

local function paintGradient(gradient: UIGradient, rarity: string, tier: string)
	if tier == "Secret" then
		gradient.Color = RevealKit.rainbow(0) -- (the secret look's own rainbow)
		gradient.Rotation = 0
	elseif rarity == "Mythic" then
		local stops = {}
		for i = 0, 6 do
			table.insert(stops, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.55, 1)))
		end
		gradient.Color = ColorSequence.new(stops)
		gradient.Rotation = 0
	elseif rarity == "Legendary" then
		gradient.Color = ColorSequence.new(rgb(255, 236, 140), rgb(255, 170, 20))
		gradient.Rotation = 90
	else
		local p = RevealFx.palette(rarity)
		gradient.Color = ColorSequence.new(p.Text:Lerp(WHITE, 0.4), p.Text)
		gradient.Rotation = 90
	end
end

local function playSound(tier: string, rarity: string)
	if tier == "Secret" then
		Sfx.play("Discovery")
		Sfx.play("CaseBoom")
	elseif tier == "Jackpot" then
		Sfx.play("Discovery")
		if rarity == "Mythic" then
			Sfx.play("CaseRise")
		end
	elseif tier == "Rare" then
		Sfx.play("Reveal")
		Sfx.play("CoinBurst")
	else
		Sfx.play("Reveal")
	end
end

--[[
	Shows a reveal (see the header). In the game it runs its own frame loop
	(RenderStepped) until close(); `opts.Manual` leaves the posing to the
	caller (the Lune previews: handle:pose(t)).
]]
function RevealFx.show(kind: string, itemId: string, rarity: string, opts: Options?): Handle
	local o: Options = opts or {}
	local self = table.remove(pool) or build()
	self.Closed = false
	local tier = o.Tier or RevealFx.tierOf(rarity)
	local spec = RevealFx.Tiers[tier] or RevealFx.Tiers.Normal
	local reduced = if o.Reduced ~= nil then o.Reduced else Motion.reduced()
	local phone = if o.Phone ~= nil then o.Phone else phoneNow()
	local z = o.ZIndex or 2
	seeds += 1
	self.Seed = seeds
	self.Tier = tier
	self.Rarity = rarity
	self.Spec = spec
	self.Reduced = reduced
	-- where it draws
	local parent: Instance
	local given = o.Parent
	if given then
		parent = given
		self.Gui = nil
	else
		local gui = Instance.new("ScreenGui")
		gui.Name = "TerraForgeReveal"
		gui.DisplayOrder = 45
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		local player = Players.LocalPlayer
		gui.Parent = if player then player:FindFirstChildOfClass("PlayerGui") else nil
		self.Gui = gui
		parent = gui
	end
	local size = o.Size or RevealFx.Size
	self.Root.Size = UDim2.fromOffset(size, size)
	self.Root.Position = o.Center or UDim2.fromScale(0.5, 0.42)
	local fit = self.Root:FindFirstChild("Fit") :: UIScale
	fit.Scale = (o.Scale or 1) * size / RevealFx.Size
	self.Root.Size = UDim2.fromOffset(RevealFx.Size, RevealFx.Size)
	-- the rays (RevealKit's: on a phone its fewer front bars, no back layer) and the glow, under the caller's picture
	self.Phone = phone
	for _, list in { self.Kit.Front, self.Kit.Back, self.Kit.Gold } do
		for _, bar in list do
			bar.ZIndex = z
		end
	end
	local p = RevealFx.palette(rarity)
	self.Glow.BackgroundColor3 = p.Glow
	self.Glow.ZIndex = z
	-- the banner and the headline (over the picture)
	local bannerZ = z + 4
	self.Banner.Visible = o.Banner ~= false
	for _, d in self.Banner:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = bannerZ
		end
	end
	self.NameLabel.Text = o.Name or nameOf(kind, itemId)
	local info = Rarity.ById[rarity]
	self.PillLabel.Text = if rarity == "Secret" then "SECRET" else string.upper(if info then info.Name else rarity)
	self.Pill.BackgroundColor3 = WHITE
	local paint = self.Pill:FindFirstChild("Paint") :: UIGradient
	paint.Color = ColorSequence.new(p.Text:Lerp(WHITE, 0.15), p.TextDark)
	self.Pill.Size = UDim2.fromOffset(math.max(150, #self.PillLabel.Text * 17 + 40), 34)
	self.ChanceLabel.Text = o.Chance or ""
	self.ChanceLabel.Visible = o.Chance ~= nil
	self.NewLabel.Visible = o.New == true
	self.NewLabel.Position = UDim2.new(0.5, math.min(260, #self.NameLabel.Text * 13 + 14), 0, 20)
	local headline = o.Headline or RevealFx.headlineFor(tier, rarity)
	self.Headline.Visible = headline ~= nil
	self.Headline.Text = headline or ""
	self.Headline.ZIndex = bannerZ
	-- the letters carry the colour (Legendary gold, Mythic and Secret a drifting rainbow), the edge stays plain
	paintGradient(self.HeadlineGradient, rarity, tier)
	-- sparkles and confetti (none with Reduce motion; fewer on phones)
	local sparkles = if reduced then 0 elseif phone then math.min(spec.Sparkles, RevealFx.PhoneSparkles) else spec.Sparkles
	local confetti = if reduced then 0 elseif phone then math.min(spec.Confetti, RevealFx.PhoneConfetti) else spec.Confetti
	self.Sparkles = pieces(self.Root, sparkles, bannerZ - 1, self.Sparkles)
	for _, piece in self.Sparkles do
		piece.BackgroundColor3 = p.Light:Lerp(WHITE, 0.3)
		UIKit.corner(piece, 999)
	end
	self.Confetti = pieces(self.Root, confetti, bannerZ - 1, self.Confetti)
	self.Root.Visible = true
	self.Root.Parent = parent
	self:pose(0)
	-- the moment: a flash (under the picture), the sound, a nudge
	if o.Flash ~= false and not reduced then
		RevealFx.flash(parent, p.Flash, if tier == "Normal" then 0.6 else RevealFx.FlashPeak, z + 1)
	end
	if o.Sound ~= false then
		playSound(tier, rarity)
	end
	if o.Shake ~= false and not reduced and spec.Shake > 0 then
		CameraShake.add(spec.Shake)
	end
	self.Started = os.clock()
	if not o.Manual then
		self.Connection = RunService.RenderStepped:Connect(function()
			if not self.Closed then
				self:pose(os.clock() - self.Started)
			end
		end)
	end
	return self
end

return RevealFx
