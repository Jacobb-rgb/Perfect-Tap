--[[
	The game UI's "Bubble" kit tokens. 2026-10-20 night: the bright "Pop" look
	of the Robux Shop for every window (owner after his Studio playtest: "upgrade
	all the UI"): grey bodies, white text with black edges, black outlines,
	bright headers per window. History: 2026-10-18 the owner picked a light,
	playful look (white panels); 2026-10-20 he asked for every window in the
	dark "Store card" style of his store photos (Config/CardTheme): dark slate
	panels and cards, cream text, chunky coloured buttons and tiles with a dark
	outline, a darker lip underneath and a soft gloss on top; 3D picture icons
	(Config/IconAssets). Every window keeps its own colour (Roles): its header
	band and the glow of its cards.

	Designed for 720 design units of screen height like UITheme (the HUD
	controller scales every TerraForge gui).
]]

local rgb = Color3.fromRGB

export type Role = {
	Top: Color3, -- gradient top (lighter)
	Base: Color3, -- main fill
	Lip: Color3, -- the darker 3D edge under a tile or button
}

local function role(top: Color3, base: Color3, lip: Color3): Role
	return { Top = top, Base = base, Lip = lip }
end

local BubbleTheme = {
	Font = Font.fromEnum(Enum.Font.FredokaOne),
	TitleFont = Font.fromEnum(Enum.Font.LuckiestGuy),
	CardFont = Font.fromEnum(Enum.Font.FredokaOne), -- window titles: white with a thick black edge (the Pop look)

	Outline = rgb(14, 14, 18), -- black edges (the Pop look)
	Shadow = rgb(6, 7, 10),
	ShadowTransparency = 0.72,
	Panel = rgb(52, 55, 66), -- the window body: the Pop shop's grey (PopTheme.Body)
	PanelTint = rgb(68, 72, 86), -- slot and row backgrounds inside panels (a shade lighter)
	Ink = rgb(255, 255, 255), -- white text with a black edge
	DarkInk = rgb(38, 48, 79), -- dark text on light faces (yellow buttons)
	InkSoft = rgb(210, 216, 230),
	White = rgb(255, 255, 255),
	Gold = rgb(255, 203, 46),
	Good = rgb(62, 214, 98),
	Bad = rgb(255, 77, 92),

	Corner = 18,
	Stroke = 3.5,
	TextStroke = 2.5,
	Lip = 5, -- how far the lip shows under a tile/button
	GlossTransparency = 0.72,

	-- Window / button colours: each window has its own (owner: colour per window).
	Roles = {
		Backpack = role(rgb(124, 200, 255), rgb(47, 149, 245), rgb(28, 100, 184)),
		Golems = role(rgb(197, 146, 255), rgb(143, 82, 242), rgb(94, 47, 179)),
		Build = role(rgb(255, 226, 102), rgb(255, 189, 26), rgb(208, 138, 0)),
		Shop = role(rgb(128, 240, 140), rgb(47, 201, 90), rgb(27, 143, 60)),
		More = role(rgb(150, 160, 184), rgb(100, 110, 136), rgb(52, 58, 76)),
		Vault = role(rgb(255, 182, 102), rgb(255, 138, 31), rgb(196, 90, 0)),
		Lobby = role(rgb(130, 216, 255), rgb(51, 180, 245), rgb(27, 127, 192)),
		Base = role(rgb(120, 236, 205), rgb(34, 199, 169), rgb(18, 140, 118)),
		Go = role(rgb(128, 240, 140), rgb(47, 201, 90), rgb(27, 143, 60)),
		Danger = role(rgb(255, 140, 140), rgb(255, 77, 92), rgb(188, 34, 52)),
		Plain = role(rgb(60, 65, 78), rgb(40, 44, 54), rgb(14, 16, 22)), -- dark slate (windows, plain buttons)
		Wheel = role(rgb(255, 150, 190), rgb(255, 79, 139), rgb(184, 40, 94)),
		Codex = role(rgb(120, 236, 205), rgb(34, 199, 169), rgb(18, 140, 118)),
		Artifacts = role(rgb(255, 226, 102), rgb(255, 189, 26), rgb(208, 138, 0)),
		Boards = role(rgb(255, 182, 102), rgb(255, 138, 31), rgb(196, 90, 0)),
		Gear = role(rgb(130, 216, 255), rgb(51, 180, 245), rgb(27, 127, 192)),
		Settings = role(rgb(160, 176, 204), rgb(110, 126, 160), rgb(70, 84, 114)),
		Enchant = role(rgb(255, 140, 222), rgb(222, 72, 184), rgb(150, 30, 122)),
		Boosts = role(rgb(128, 240, 140), rgb(47, 201, 90), rgb(27, 143, 60)),
		Rebirth = role(rgb(160, 168, 255), rgb(102, 110, 242), rgb(60, 64, 172)), -- the blaster chat's rebirth window
	} :: { [string]: Role },

	BaseHeight = 720,
}

return BubbleTheme
