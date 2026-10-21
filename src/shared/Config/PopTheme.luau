--[[
	The bright "Pop" look (owner 2026-10-20 evening, his egg-game photos: "it
	is nicer, easier and clearer"): saturated gradient faces with a thick
	black outline, white chunky text with a black edge, a bright green
	window header with diagonal shine stripes and a red X, a dark grey body,
	cards painted in one bright colour with light rays behind the picture,
	green Robux price buttons. Used by the Robux Shop, the Spin & Win wheel,
	the top teleport bar, the left HUD tiles and the money.

	Designed for 720 design units of screen height like UITheme (HudController
	scales every TerraForge gui).
]]

local rgb = Color3.fromRGB

export type Paint = { Top: Color3, Bottom: Color3, Edge: Color3 }

local function paint(top: Color3, bottom: Color3, edge: Color3): Paint
	return { Top = top, Bottom = bottom, Edge = edge }
end

local PopTheme = {
	Font = Font.fromEnum(Enum.Font.FredokaOne), -- every word
	Heavy = Font.fromEnum(Enum.Font.LuckiestGuy), -- the money and big headings

	Ink = rgb(255, 255, 255),
	Outline = rgb(14, 14, 18), -- borders and text edges
	Shade = rgb(0, 0, 0), -- drop shadows (transparent)

	Body = rgb(58, 60, 70), -- a window's body
	BodyBottom = rgb(44, 46, 54),
	Well = rgb(36, 38, 46), -- an inset behind lists

	Close = paint(rgb(255, 84, 84), rgb(214, 22, 34), rgb(14, 14, 18)),
	Price = paint(rgb(156, 244, 64), rgb(72, 196, 22), rgb(14, 14, 18)),
	Gray = paint(rgb(170, 174, 186), rgb(112, 116, 130), rgb(14, 14, 18)),

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
	} :: { [string]: Paint },

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

	Corner = 6, -- buttons and cards
	WindowCorner = 8,
	Edge = 3, -- border thickness
	Stripe = 0.8, -- the header's shine stripes (transparency)

	BaseHeight = 720,
}

return PopTheme
