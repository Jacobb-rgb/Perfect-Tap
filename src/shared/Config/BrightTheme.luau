--[[
	BrightTheme: the bright window style of the owner's clicker-sim video
	(2026-10-29, docs/plans/CLICKER_VIDEO_2026-10-29.md, frames in
	docs/art/clicker_video_2026-10-29/): white panels with a dark navy edge,
	light blue insets, chunky pill buttons with a dark edge, gold titles,
	cards in their rarity's colour. Tokens and text helpers only: the new
	egg panel, the Golden Forge and the side panels (profile, rebirth,
	quests) read these so they match each other. Every other window keeps
	PopTheme until the owner decides.

	Sizes are design units (720 tall, HudController.uiScale scales them).
	Fonts: FredokaOne for titles, buttons and numbers (a Roblox font, already
	used by PopTheme and the loading screen), Montserrat Bold for small text.

	chanceText(chance) is what an odds card shows: "46.33%", "6.5%", "0.1%",
	and under 0.1 % "1 in 3,333" (the video's cards). oneInText(chance) is
	what the egg opening shows under a golem's name: always "1 in N".
]]

local Rarity = require(script.Parent.Rarity)

export type Paint = { Top: Color3, Bottom: Color3, Edge: Color3 }

local BrightTheme = {}

-- panels
BrightTheme.Panel = Color3.fromRGB(255, 255, 255)
BrightTheme.PanelEdge = Color3.fromRGB(26, 44, 82) -- the dark navy rim
BrightTheme.Inset = Color3.fromRGB(230, 241, 255) -- rows and wells inside a panel
BrightTheme.InsetEdge = Color3.fromRGB(165, 198, 236)
BrightTheme.Well = Color3.fromRGB(219, 227, 238) -- a grid's grey-blue floor (the Golden Forge's golem grid)
BrightTheme.Shade = Color3.fromRGB(10, 16, 30) -- drop shadow under a panel (transparency 0.75)

-- text
BrightTheme.Text = Color3.fromRGB(26, 44, 82) -- dark text on white
BrightTheme.TextSoft = Color3.fromRGB(96, 114, 148)
BrightTheme.TextOnColour = Color3.fromRGB(255, 255, 255) -- on buttons and cards, with Outline
BrightTheme.Outline = Color3.fromRGB(22, 28, 44)
BrightTheme.Good = Color3.fromRGB(84, 214, 44) -- "100%", "+20%"
BrightTheme.Bad = Color3.fromRGB(232, 48, 48)

-- buttons and bands: a top-to-bottom gradient and a dark edge
BrightTheme.Paints = {
	Green = { Top = Color3.fromRGB(140, 236, 52), Bottom = Color3.fromRGB(70, 190, 18), Edge = Color3.fromRGB(34, 98, 10) },
	Orange = { Top = Color3.fromRGB(255, 196, 64), Bottom = Color3.fromRGB(255, 136, 0), Edge = Color3.fromRGB(132, 64, 0) },
	Blue = { Top = Color3.fromRGB(70, 190, 255), Bottom = Color3.fromRGB(22, 128, 240), Edge = Color3.fromRGB(12, 60, 128) },
	Purple = { Top = Color3.fromRGB(206, 92, 255), Bottom = Color3.fromRGB(140, 30, 232), Edge = Color3.fromRGB(72, 12, 124) },
	Red = { Top = Color3.fromRGB(255, 92, 92), Bottom = Color3.fromRGB(216, 28, 28), Edge = Color3.fromRGB(110, 10, 10) },
	Grey = { Top = Color3.fromRGB(212, 220, 230), Bottom = Color3.fromRGB(166, 177, 192), Edge = Color3.fromRGB(76, 86, 100) },
	Gold = { Top = Color3.fromRGB(255, 236, 110), Bottom = Color3.fromRGB(255, 166, 30), Edge = Color3.fromRGB(96, 50, 0) },
} :: { [string]: Paint }

-- the title over a window's top-left corner ("Golden Forge"): gold text, dark edge
BrightTheme.Title = BrightTheme.Paints.Gold

-- shapes
BrightTheme.Corner = 18 -- panel corner radius
BrightTheme.CardCorner = 12
BrightTheme.PillCorner = 14
BrightTheme.EdgeThickness = 4 -- panel and button rims
BrightTheme.TextEdge = 3 -- outline of white text

-- fonts
BrightTheme.Font = Font.fromEnum(Enum.Font.FredokaOne)
BrightTheme.SmallFont = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)

-- under this chance an odds card says "1 in N" instead of a percentage
BrightTheme.OneInBelow = 0.001

-- A card in a rarity's colour (egg panel, golem grids): light top, the
-- rarity's colour at the bottom, its dark colour as the rim.
function BrightTheme.rarityPaint(rarityId: string): Paint
	local info = Rarity.ById[rarityId] or Rarity.ById.Common
	return {
		Top = info.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		Bottom = info.Color,
		Edge = info.DarkColor,
	}
end

-- The glow of an egg's cracks (and the flash) for a golem of this rarity:
-- white for Common (the video's common eggs), the rarity's colour above it.
-- Mythic is drawn as a rainbow by the opening; this is its base colour.
function BrightTheme.crackColour(rarityId: string): Color3
	if rarityId == "Common" then
		return Color3.fromRGB(240, 248, 255)
	end
	local info = Rarity.ById[rarityId] or Rarity.ById.Common
	return info.Color
end

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	while true do
		local nextS, count = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		s = nextS
		if count == 0 then
			return s
		end
	end
end

-- "1 in N" (N = 1 / chance rounded, with thousands commas); "-" for no chance
function BrightTheme.oneInText(chance: number): string
	if chance ~= chance or chance <= 0 then
		return "-"
	end
	local n = math.max(1, math.floor(1 / chance + 0.5))
	return "1 in " .. thousands(n)
end

-- an odds card's text: up to two decimals ("46.33%", "30%", "6.5%", "0.1%"),
-- "1 in N" under OneInBelow
function BrightTheme.chanceText(chance: number): string
	if chance ~= chance or chance <= 0 then
		return "-"
	end
	if chance < BrightTheme.OneInBelow then
		return BrightTheme.oneInText(chance)
	end
	local text = string.format("%.2f", math.min(chance, 1) * 100)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text .. "%"
end

return BrightTheme
