--[[
	Terra Forge UI look: chunky, warm forge panels with bold outlines and
	rarity colors. All UI builders read from here.
]]

local rgb = Color3.fromRGB

return {
	Font = Font.fromEnum(Enum.Font.FredokaOne),
	TitleFont = Font.fromEnum(Enum.Font.LuckiestGuy),

	Panel = rgb(46, 32, 28),
	PanelLight = rgb(70, 50, 42),
	PanelDark = rgb(28, 19, 17),
	Outline = rgb(18, 11, 9),
	Text = rgb(255, 240, 220),
	TextDim = rgb(206, 180, 156),
	Accent = rgb(255, 176, 64),
	AccentDark = rgb(196, 106, 26),
	Good = rgb(110, 214, 92),
	GoodDark = rgb(52, 136, 50),
	Bad = rgb(236, 84, 70),
	BadDark = rgb(140, 36, 30),
	Coin = rgb(255, 206, 72),
	Info = rgb(120, 196, 255),

	Corner = 14,
	Stroke = 3,
	BaseHeight = 720, -- UI is designed for this screen height, then scaled
}
