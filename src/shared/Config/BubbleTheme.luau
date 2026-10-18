--[[
	The light "Bubble" UI look (owner's pick, 2026-10-18: light and playful like
	popular pet simulators). White rounded panels and chunky coloured tiles with a
	thick dark outline, a darker lip underneath and a soft gloss on top; 3D
	picture icons (Config/IconAssets). Every window has its own colour (Roles).

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

	Outline = rgb(27, 29, 51), -- the same navy as the icon outlines
	Shadow = rgb(15, 18, 40),
	ShadowTransparency = 0.72,
	Panel = rgb(255, 255, 255),
	PanelTint = rgb(234, 241, 251), -- slot and row backgrounds inside panels
	Ink = rgb(38, 48, 79), -- dark text on white
	InkSoft = rgb(104, 117, 150),
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
		More = role(rgb(255, 255, 255), rgb(223, 230, 242), rgb(169, 181, 201)),
		Vault = role(rgb(255, 182, 102), rgb(255, 138, 31), rgb(196, 90, 0)),
		Lobby = role(rgb(130, 216, 255), rgb(51, 180, 245), rgb(27, 127, 192)),
		Base = role(rgb(120, 236, 205), rgb(34, 199, 169), rgb(18, 140, 118)),
		Go = role(rgb(128, 240, 140), rgb(47, 201, 90), rgb(27, 143, 60)),
		Danger = role(rgb(255, 140, 140), rgb(255, 77, 92), rgb(188, 34, 52)),
		Plain = role(rgb(255, 255, 255), rgb(236, 241, 249), rgb(176, 188, 208)),
		Wheel = role(rgb(255, 150, 190), rgb(255, 79, 139), rgb(184, 40, 94)),
		Codex = role(rgb(120, 236, 205), rgb(34, 199, 169), rgb(18, 140, 118)),
		Artifacts = role(rgb(255, 226, 102), rgb(255, 189, 26), rgb(208, 138, 0)),
		Boards = role(rgb(255, 182, 102), rgb(255, 138, 31), rgb(196, 90, 0)),
		Gear = role(rgb(130, 216, 255), rgb(51, 180, 245), rgb(27, 127, 192)),
		Settings = role(rgb(160, 176, 204), rgb(110, 126, 160), rgb(70, 84, 114)),
		Enchant = role(rgb(255, 140, 222), rgb(222, 72, 184), rgb(150, 30, 122)),
		Boosts = role(rgb(128, 240, 140), rgb(47, 201, 90), rgb(27, 143, 60)),
	} :: { [string]: Role },

	BaseHeight = 720,
}

return BubbleTheme
