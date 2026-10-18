--[[
	The 3D UI icons (pictures rendered by tools/preview/render_icons.mjs).

	They are uploaded as three sprite sheets (tools/preview/icon_sheets.mjs ->
	NAHRAJ_DO_ROBLOXU/ikony_ui): 6 x 6 cells of Cell px, so the owner uploads 3
	images instead of ~80 and pastes 3 ids into Sheets[*].Id. An ImageLabel
	shows one cell with ImageRectOffset / ImageRectSize (IconAssets.apply).
	A sheet without an id shows nothing (the button text still shows).

	Ore Pen items (item_*) are not here: in the game they are live 3D
	ViewportFrames of the item model.
]]

local IconAssets = {}

IconAssets.Cell = 170 -- px per icon in a sheet (6 x 170 = 1020 <= Roblox's 1024)
IconAssets.Columns = 6

export type Sheet = { Name: string, File: string, Id: number, Icons: { string } }

IconAssets.Sheets = {
	{
		Name = "Ui",
		File = "ikony_1_ui.png",
		Id = 0,
		Icons = {
			"coin", "coins", "backpack", "golem", "build", "shop",
			"more", "base", "lobby", "vault", "blaster", "blaster_copper",
			"ore_raw", "ore_copper", "ore_silver", "ingot_gold", "shard", "artifact",
			"medal", "podium", "moon", "train", "clover", "rainbow",
			"enchant", "check", "wheel", "book", "trophy", "helmet",
			"cog", "lock",
		},
	},
	{
		Name = "Golems",
		File = "ikony_2_golemove.png",
		Id = 0,
		Icons = {
			"golem_PebbleGolem", "golem_CopperTinker", "golem_CoalChomper", "golem_TinTumbler",
			"golem_QuartzSprite", "golem_SilverSquire", "golem_AmethystAcolyte", "golem_JadeGardener",
			"golem_EmberImp", "golem_CobaltDiver", "golem_GildedPorter", "golem_RubyKnight",
			"golem_SapphireSage", "golem_DiamondDuke", "golem_StormcoreTitan", "golem_MoonstoneOracle",
			"golem_StarmetalSovereign", "golem_HeartstoneColossus",
			"capsule_Stone", "capsule_Crystal", "capsule_Royal",
		},
	},
	{
		Name = "Machines",
		File = "ikony_3_stroje.png",
		Id = 0,
		Icons = {
			"machine_CleaningStation", "machine_AutoCleaner", "machine_IronBox", "machine_Sorter",
			"machine_Polisher", "machine_ClayFurnace", "machine_BrickFurnace", "machine_BlastFurnace",
			"machine_PlasmaFurnace", "machine_AlloyFurnace", "machine_Crusher", "machine_CrystalExtractor",
			"machine_RestorationTable", "machine_SellBox", "machine_Conveyor", "machine_ExpressConveyor",
			"machine_Splitter", "machine_BeltLift", "machine_Slide", "machine_RobotArm",
			"machine_SolarPanel", "machine_WindTurbine", "machine_FusionReactor", "machine_PowerPole",
		},
	},
} :: { Sheet }

-- Roblox's own images (no upload needed).
IconAssets.BuiltIn = {
	robux = "rbxasset://textures/ui/common/robux.png",
} :: { [string]: string }

-- name -> { sheet, cell index (0-based) }
local where: { [string]: { Sheet: Sheet, Index: number } } = {}
for _, sheet in IconAssets.Sheets do
	for i, name in sheet.Icons do
		where[name] = { Sheet = sheet, Index = i - 1 }
	end
end

-- Is this a known icon (in a sheet or built in)?
function IconAssets.has(name: string): boolean
	return where[name] ~= nil or IconAssets.BuiltIn[name] ~= nil
end

-- The top-left pixel of an icon's cell in its sheet.
function IconAssets.cellOffset(index: number): Vector2
	local col = index % IconAssets.Columns
	local row = index // IconAssets.Columns
	return Vector2.new(col * IconAssets.Cell, row * IconAssets.Cell)
end

-- Image + rect for an icon: ("rbxassetid://..", offset, size), or ("", 0, 0)
-- when its sheet is not uploaded yet / the icon is unknown.
function IconAssets.find(name: string): (string, Vector2, Vector2)
	local builtIn = IconAssets.BuiltIn[name]
	if builtIn then
		return builtIn, Vector2.zero, Vector2.zero
	end
	local spot = where[name]
	if spot and spot.Sheet.Id > 0 then
		return "rbxassetid://" .. tostring(spot.Sheet.Id), IconAssets.cellOffset(spot.Index), Vector2.new(IconAssets.Cell, IconAssets.Cell)
	end
	return "", Vector2.zero, Vector2.zero
end

-- Shows icon `name` on an ImageLabel / ImageButton.
function IconAssets.apply(label: ImageLabel | ImageButton, name: string)
	local image, offset, size = IconAssets.find(name)
	label.Image = image
	label.ImageRectOffset = offset
	label.ImageRectSize = size
end

return IconAssets
