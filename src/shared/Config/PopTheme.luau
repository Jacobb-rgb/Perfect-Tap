--[[
	The bright "Pop" look (owner 2026-10-20 evening, his egg-game photos: "it
	is nicer, easier and clearer"): saturated gradient faces with a thick
	black outline, white chunky text with a black edge, a bright window
	header with diagonal stripes and a red X, a dark grey body, cards painted
	in one bright colour with light rays behind the picture, green Robux
	price buttons. Used by every window, the top teleport bar, the left HUD
	tiles and the money.

	Designed for 720 design units of screen height like UITheme (HudController
	scales every TerraForge gui).

	Two looks, one switch (LOOK below; PopTheme.setLook changes it at run
	time for the specs and the previews):

	"Round" (the default; owner 2026-10-27, the "Advanced UI Pack" reel:
	"here you can see how my UI in our game should look"; pictures in
	docs/art/reels_2026-10-27/ui_*): a heavy round cartoon font (Fredoka
	One) with a thick dark outline for every word (titles, buttons, prices,
	tiles, the money); every window's header band in its own colour
	(PopTheme.Windows: Store red, Codex blue, Golems orange, Quests pink,
	Settings grey, Elevator purple, Star Forge magenta, shops green / blue)
	with diagonal stripes, the window's icon on the left of the title and a
	big faded copy of it in the band; a dark charcoal body with a thin dark
	border; section headings "- FEATURED -"; vivid cards with a sunburst
	behind the picture; dark HUD tiles with a big coloured icon and a
	coloured lip; clean faces (no lattice).

	"Pixel" (owner 2026-10-22, eight Roblox UI reels; pictures in
	docs/art/ui_pixel_refs): a chunky pixel font (Press Start 2P) for every
	short word, a smooth light-to-deep gradient with a darker lip along the
	bottom (depth), a light gradient edge inside the outline, a diagonal
	lattice pattern over the paint, painted HUD tiles with sunburst rays.

	Both: long wrapped text keeps the round font (PopTheme.Font) so it stays
	readable; motion (Controllers/PixelFxController: rays spin, a gleam
	sweeps across buttons, icons lean, hover grows and press squishes).
]]

local rgb = Color3.fromRGB

export type Paint = { Top: Color3, Bottom: Color3, Edge: Color3 }
-- a window's header in the Round look: its paint (a PopTheme.Paints name) and its icon (IconAssets)
export type WindowLook = { Paint: string, Icon: string }

local function paint(top: Color3, bottom: Color3, edge: Color3): Paint
	return { Top = top, Bottom = bottom, Edge = edge }
end

-- THE SWITCH: "Round" (the reel-4 look, 2026-10-27) or "Pixel" (the 10-22 pixel look)
local LOOK = "Round"

local PIXEL = Font.new("rbxasset://fonts/families/PressStart2P.json")
-- the Round look's word font: Fredoka One, the reel's heavy round cartoon font. The family has
-- one face, so Bold draws exactly the sentences' face; the weight only tells a word
-- (Pop.isPixel: shrinks to fit its box) from a sentence (wraps).
local WORD = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local PopTheme = {
	Look = LOOK, -- "Round" | "Pixel" (PopTheme.setLook)
	Font = Font.fromEnum(Enum.Font.FredokaOne), -- long wrapped text (descriptions, hints)
	Pixel = PIXEL, -- the word font: titles, buttons, prices, tiles, labels (the look's: setLook)
	Heavy = PIXEL, -- the money and big headings (the look's: setLook)
	PixelScale = 0.74, -- a word's size next to the round font's (the pixel font is wide: 1 em a letter)
	PixelAdvance = 1.0, -- a word letter's width in em (Fredoka One capitals: about 0.68)
	PixelLine = 1.1, -- a word line's height in em
	PixelMin = 10, -- the smallest a word shrinks to (design units); below it ends in "..."
	PixelMax = 26, -- a longer text is a sentence: it keeps the round font (subtitles, hints)

	Ink = rgb(255, 255, 255),
	Outline = rgb(14, 14, 18), -- borders and text edges
	Shade = rgb(0, 0, 0), -- drop shadows (transparent)

	Body = rgb(58, 60, 70), -- a window's body (the look's: setLook)
	BodyBottom = rgb(44, 46, 54),
	Well = rgb(36, 38, 46), -- an inset behind lists

	Close = paint(rgb(255, 84, 84), rgb(214, 22, 34), rgb(14, 14, 18)),
	Price = paint(rgb(156, 244, 64), rgb(72, 196, 22), rgb(14, 14, 18)),
	Gray = paint(rgb(170, 174, 186), rgb(112, 116, 130), rgb(14, 14, 18)),
	-- the Round look's HUD tile: a dark face (the tile's own colour rides its lip and edge)
	TileDark = paint(rgb(86, 88, 100), rgb(50, 52, 62), rgb(14, 14, 18)),

	-- card and button faces
	Paints = {
		-- (saturated like the Roblox shop photos: a light top, a deep bottom)
		Green = paint(rgb(140, 238, 52), rgb(36, 168, 22), rgb(14, 14, 18)),
		Blue = paint(rgb(70, 196, 255), rgb(12, 110, 232), rgb(14, 14, 18)),
		Teal = paint(rgb(52, 226, 196), rgb(8, 150, 140), rgb(14, 14, 18)),
		Purple = paint(rgb(218, 104, 255), rgb(116, 40, 224), rgb(14, 14, 18)),
		Pink = paint(rgb(255, 118, 206), rgb(214, 36, 146), rgb(14, 14, 18)),
		Yellow = paint(rgb(255, 230, 64), rgb(246, 158, 10), rgb(14, 14, 18)),
		Orange = paint(rgb(255, 176, 56), rgb(236, 92, 12), rgb(14, 14, 18)),
		Red = paint(rgb(255, 96, 92), rgb(200, 20, 40), rgb(14, 14, 18)),
		Night = paint(rgb(170, 60, 200), rgb(46, 22, 102), rgb(14, 14, 18)), -- the limited banner
		Slate = paint(rgb(96, 100, 116), rgb(56, 60, 72), rgb(14, 14, 18)),
		-- the reel's window colours (Round look)
		Magenta = paint(rgb(255, 92, 230), rgb(186, 18, 168), rgb(14, 14, 18)), -- Rebirth
		Steel = paint(rgb(176, 182, 196), rgb(100, 106, 124), rgb(14, 14, 18)), -- Settings
		Amber = paint(rgb(255, 204, 64), rgb(232, 128, 8), rgb(14, 14, 18)), -- Trade
		Crimson = paint(rgb(255, 78, 104), rgb(208, 16, 58), rgb(14, 14, 18)), -- Store
		Royal = paint(rgb(84, 156, 255), rgb(30, 84, 222), rgb(14, 14, 18)), -- Index
		Violet = paint(rgb(176, 112, 255), rgb(104, 46, 222), rgb(14, 14, 18)), -- Teleport
	} :: { [string]: Paint },

	--[[
		The Round look's window headers by ScreenGui name (Pop.dressBand):
		the reel's colour per window (Store red, Index blue, Inventory
		orange, Daily pink, Settings grey, Teleport purple, Rebirth magenta,
		Sell green, Upgrade green, Item Shop blue, Trade amber) and the icon
		on the left of the title and faded in the band. A window not listed
		keeps the colour its view gives it.
	]]
	Windows = {
		TerraForgeStore = { Paint = "Crimson", Icon = "cart" }, -- the Robux Store (reel: Store red)
		TerraForgeStarterPack = { Paint = "Crimson", Icon = "coin_chest" },
		TerraForgeCodex = { Paint = "Royal", Icon = "book" }, -- the ore index (reel: Index blue)
		TerraForgeArtifacts = { Paint = "Royal", Icon = "artifact" }, -- the relic book
		TerraForgeJournal = { Paint = "Royal", Icon = "book" },
		TerraForgeGolems = { Paint = "Orange", Icon = "golem" }, -- the golem inventory (reel: Inventory orange)
		TerraForgeCapsules = { Paint = "Orange", Icon = "capsule_Stone" },
		TerraForgePen = { Paint = "Orange", Icon = "ore_raw" },
		TerraForgeBackpack = { Paint = "Orange", Icon = "backpack" },
		TerraForgeQuests = { Paint = "Pink", Icon = "check" }, -- (reel: Daily pink)
		TerraForgeStreak = { Paint = "Pink", Icon = "medal" },
		TerraForgeSettings = { Paint = "Steel", Icon = "cog" }, -- (reel: Settings grey)
		TerraForgeIronBox = { Paint = "Steel", Icon = "machine_IronBox" },
		TerraForgeElevator = { Paint = "Violet", Icon = "lift" }, -- (reel: Teleport purple)
		TerraForgeEmotes = { Paint = "Violet", Icon = "more" },
		TerraForgeRebirth = { Paint = "Magenta", Icon = "rebirth" }, -- the Star Forge (reel: Rebirth magenta)
		TerraForgeSell = { Paint = "Green", Icon = "coins" }, -- (reel: Sell green)
		TerraForgeTechShop = { Paint = "Green", Icon = "build" }, -- machines + upgrades (reel: Upgrade green)
		TerraForgeDroppers = { Paint = "Green", Icon = "shop" },
		TerraForgeEnchants = { Paint = "Purple", Icon = "enchant" },
		TerraForgeGearShop = { Paint = "Blue", Icon = "helmet" }, -- (reel: Item Shop blue)
		TerraForgeVault = { Paint = "Blue", Icon = "blaster" },
		TerraForgeHoverboards = { Paint = "Blue", Icon = "hoverboard" },
		TerraForgeHallOfFame = { Paint = "Amber", Icon = "trophy" }, -- (reel: Trade amber)
		TerraForgeBoosts = { Paint = "Amber", Icon = "clover" },
		TerraForgeTrainPanel = { Paint = "Amber", Icon = "train" },
		TerraForgeWheel = { Paint = "Teal", Icon = "wheel" },
	} :: { [string]: WindowLook },

	-- the rainbow (special cards): left -> right
	Rainbow = { rgb(255, 92, 92), rgb(255, 190, 60), rgb(250, 240, 80), rgb(96, 226, 90), rgb(70, 186, 255), rgb(196, 110, 255) },

	-- heading text gradients (top -> bottom)
	Titles = {
		Gold = { rgb(255, 246, 120), rgb(255, 176, 20) },
		Cyan = { rgb(150, 248, 255), rgb(24, 168, 255) },
		Magenta = { rgb(255, 150, 250), rgb(222, 40, 200) },
		Green = { rgb(200, 255, 120), rgb(70, 214, 40) },
		Red = { rgb(255, 160, 150), rgb(236, 40, 50) },
		White = { rgb(255, 255, 255), rgb(220, 226, 236) },
	} :: { [string]: { Color3 } },

	Money = rgb(122, 244, 60), -- the green amounts
	MoneyNumber = rgb(130, 255, 70),

	Corner = 8, -- buttons and cards (the reels: radius 10 on a 100 square)
	WindowCorner = 10,
	Edge = 3.5, -- border thickness
	Lip = 0.13, -- the darker band along a face's bottom (a share of its height, 3..9 units)
	Lattice = 0.82, -- the diagonal lattice lines over a paint (transparency; Pixel look)
	LatticeGap = 26, -- design units between two lattice lines
	LatticeBands = 4, -- frames a way (six lines each)
	Stripe = 0.8, -- the header's shine stripes (transparency)
	Stripes = 0.86, -- the Round look's fine diagonal stripes over a header band (transparency)
	StripeGap = 22, -- design units between two of them
	Watermark = 0.7, -- the big faded icon in a Round header band (transparency)

	BaseHeight = 720,
}

-- What changes with the look.
local LOOKS = {
	Round = {
		Word = WORD,
		Scale = 1, -- (round words are drawn at the size the views give)
		Advance = 0.68, -- (Fredoka One: capitals 0.62..0.7 em, digits about 0.55)
		Line = 1.1, -- (a Roblox line is TextSize tall; 1.1 leaves the edge room, like the pixel font's)
		Body = rgb(52, 54, 62), -- the reel's dark charcoal
		BodyBottom = rgb(38, 40, 47),
		Well = rgb(32, 34, 41),
	},
	Pixel = {
		Word = PIXEL,
		Scale = 0.74,
		Advance = 1.0,
		Line = 1.1,
		Body = rgb(58, 60, 70),
		BodyBottom = rgb(44, 46, 54),
		Well = rgb(36, 38, 46),
	},
}

--[[
	Switches the look ("Round" or "Pixel"; anything else is Round). The kit
	reads the theme when it builds, so windows built after the call wear the
	new look (the specs and the previews build both).
]]
function PopTheme.setLook(look: string)
	local name = if look == "Pixel" then "Pixel" else "Round"
	local l = LOOKS[name]
	PopTheme.Look = name
	PopTheme.Pixel = l.Word
	PopTheme.Heavy = l.Word
	PopTheme.PixelScale = l.Scale
	PopTheme.PixelAdvance = l.Advance
	PopTheme.PixelLine = l.Line
	PopTheme.Body = l.Body
	PopTheme.BodyBottom = l.BodyBottom
	PopTheme.Well = l.Well
end

-- Is the Round look on?
function PopTheme.round(): boolean
	return PopTheme.Look == "Round"
end

PopTheme.setLook(LOOK)

return PopTheme
