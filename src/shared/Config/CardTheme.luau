--[[
	The "Store card" UI look (owner, 2026-10-20: every window like the store
	photos he sent). Dark slate windows with an olive-to-gold striped header
	and a cream title, dark cards with a glowing coloured border, titles in
	a comic font with a colour gradient and a dark edge, a green Robux price
	at the bottom right.

	Designed for 720 design units of screen height like UITheme (the HUD
	controller scales every TerraForge gui).
]]

local rgb = Color3.fromRGB

export type Glow = {
	Edge: Color3, -- the card border
	Top: Color3, -- title gradient, top
	Bottom: Color3, -- title gradient, bottom
	Rainbow: boolean?, -- the border runs through the rainbow (special offers)
}

local function glow(edge: Color3, top: Color3, bottom: Color3, rainbow: boolean?): Glow
	return { Edge = edge, Top = top, Bottom = bottom, Rainbow = rainbow }
end

local CardTheme = {
	Font = Font.fromEnum(Enum.Font.Cartoon), -- Comic Neue Angular, like the photos
	NumberFont = Font.fromEnum(Enum.Font.FredokaOne), -- big round numbers (money)

	Window = rgb(44, 48, 56), -- the window frame
	WindowEdge = rgb(16, 18, 22),
	Body = rgb(22, 24, 29), -- behind the cards
	Card = rgb(24, 26, 32),
	CardTop = rgb(40, 44, 54), -- the card's lighter top (gradient)
	Ink = rgb(250, 248, 236), -- cream white text
	InkSoft = rgb(196, 200, 210),
	Edge = rgb(20, 20, 26), -- text outlines
	Price = rgb(126, 240, 74), -- the green Robux price
	PriceEdge = rgb(22, 70, 12),
	Coin = rgb(255, 206, 64),
	Close = rgb(236, 64, 76),
	CloseEdge = rgb(120, 20, 30),
	-- the header band: olive -> lime -> gold, with faint diagonal stripes
	Header = { rgb(132, 150, 60), rgb(176, 196, 72), rgb(232, 196, 76) },
	HeaderStripe = 0.86, -- stripe transparency

	Corner = 12,
	CardCorner = 8,
	EdgeThickness = 3,
	TextEdge = 2.5,

	Glows = {
		Orange = glow(rgb(240, 138, 40), rgb(255, 226, 110), rgb(246, 132, 36)),
		Green = glow(rgb(76, 214, 72), rgb(224, 255, 120), rgb(70, 206, 60)),
		Red = glow(rgb(236, 52, 64), rgb(255, 140, 150), rgb(226, 36, 56)),
		Blue = glow(rgb(60, 132, 246), rgb(150, 220, 255), rgb(56, 126, 240)),
		Purple = glow(rgb(170, 90, 246), rgb(230, 180, 255), rgb(150, 76, 236)),
		Gold = glow(rgb(255, 196, 46), rgb(255, 244, 150), rgb(240, 170, 20)),
		Rainbow = glow(rgb(255, 255, 255), rgb(255, 240, 120), rgb(110, 230, 90), true),
	} :: { [string]: Glow },
	RainbowKeys = {
		rgb(255, 96, 96),
		rgb(255, 196, 64),
		rgb(120, 230, 90),
		rgb(70, 190, 255),
		rgb(190, 110, 255),
	},

	BaseHeight = 720,
}

return CardTheme
