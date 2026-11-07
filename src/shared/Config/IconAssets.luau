--[[
	The 3D UI icons (pictures rendered by tools/preview/render_icons.mjs).

	They are uploaded as three sprite sheets (tools/preview/icon_sheets.mjs ->
	NAHRAJ_DO_ROBLOXU/ikony_ui): 6 x 6 cells of Cell px, so the owner uploads 3
	images instead of ~80 and pastes 3 ids into Sheets[*].Id. An ImageLabel
	shows one cell with ImageRectOffset / ImageRectSize (IconAssets.apply).
	A sheet without an id shows nothing: the button's word still shows, and
	never an emoji (owner 2026-10-20: "bez emoji, jenom text").

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
			"coin",
			"coins",
			"backpack",
			"golem",
			"build",
			"shop",
			"more",
			"base",
			"lobby",
			"vault",
			"blaster",
			"blaster_copper",
			"ore_raw",
			"ore_copper",
			"ore_silver",
			"ingot_gold",
			"shard",
			"artifact",
			"medal",
			"podium",
			"moon",
			"train",
			"clover",
			"rainbow",
			"enchant",
			"check",
			"wheel",
			"book",
			"trophy",
			"helmet",
			"cog",
			"lock",
			"lift",
		},
	},
	{
		Name = "Golems",
		File = "ikony_2_golemove.png",
		Id = 0,
		Icons = {
			"golem_PebbleGolem",
			"golem_CopperTinker",
			"golem_CoalChomper",
			"golem_TinTumbler",
			"golem_QuartzSprite",
			"golem_SilverSquire",
			"golem_AmethystAcolyte",
			"golem_JadeGardener",
			"golem_EmberImp",
			"golem_CobaltDiver",
			"golem_GildedPorter",
			"golem_RoseKnight",
			"golem_SapphireSage",
			"golem_DiamondDuke",
			"golem_StormTitan",
			"golem_MoonstoneOracle",
			"golem_CelestialSovereign",
			"golem_HeartstoneColossus",
			"capsule_Stone",
			"capsule_Crystal",
			"capsule_Royal",
			-- the limited Dragonforge edition (Config/LimitedGolems)
			"golem_CinderWhelp",
			"golem_EmberHatchling",
			"golem_ScaleKnight",
			"golem_Flamewing",
			"golem_MagmaWyvern",
			"golem_DragonKing",
			"capsule_Dragonforge",
		},
	},
	{
		Name = "Machines",
		File = "ikony_3_stroje.png",
		Id = 0,
		Icons = {
			"machine_CleaningStation",
			"machine_AutoCleaner",
			"machine_IronBox",
			"machine_Sorter",
			"machine_Polisher",
			"machine_ClayFurnace",
			"machine_BrickFurnace",
			"machine_BlastFurnace",
			"machine_PlasmaFurnace",
			"machine_AlloyFurnace",
			"machine_Crusher",
			"machine_CrystalExtractor",
			"machine_RestorationTable",
			"machine_SellBox",
			"machine_Conveyor",
			"machine_ExpressConveyor",
			"machine_Splitter",
			"machine_BeltLift",
			"machine_Slide",
			"machine_RobotArm",
			"machine_SolarPanel",
			"machine_WindTurbine",
			"machine_FusionReactor",
			"machine_PowerPole",
			"machine_StorageCrate",
			"machine_Anvil",
			"machine_SellChute",
		},
	},
	{
		Name = "Menus",
		File = "ikony_4_menu.png",
		Id = 0,
		Icons = {
			"boots",
			"gloves",
			"magnet",
			"speaker",
			"music",
			"camera",
			"gamepad",
			"enchant_Power",
			"enchant_Swift",
			"enchant_Reach",
			"enchant_Magnetism",
			"enchant_Lucky",
			"enchant_Midas",
			"enchant_TwinDrop",
			"enchant_Overcharge",
			"enchant_Prospector",
			"enchant_GolemBond",
			"enchant_Heartfire",
			"enchant_Starbreaker",
			"rebirth",
			"star_token", -- the blaster chat's rebirth window
			-- the Robux STORE (owner 2026-10-20) and the HUD's Shop pill
			"coin_pile",
			"coin_sack",
			"coin_chest",
			"cart",
			"hoverboard",
			"pass_crown",
			"luck_server",
			-- the Pop shop's money (3D banknotes; in the game live ViewportFrames, CashBuilder)
			"cash_stack",
			"cash_pile",
		},
	},
	{
		Name = "Artifacts",
		File = "ikony_5_artefakty.png",
		Id = 0,
		Icons = {
			"artifact_CrownCoin",
			"artifact_RoyalSeal",
			"artifact_QueensBrooch",
			"artifact_ThroneFinial",
			"artifact_EmberScepter",
			"artifact_EmberCrown",
			"artifact_GoldenSpike",
			"artifact_ConductorWhistle",
			"artifact_RailLantern",
			"artifact_LastTicket",
			"artifact_RoyalTimetable",
			"artifact_LocomotiveCrest",
			"artifact_GolemCog",
			"artifact_GolemBlueprint",
			"artifact_SparkVial",
			"artifact_CoreCasing",
			"artifact_GolemsmithHammer",
			"artifact_FirstGolemEye",
			"artifact_HeartstoneFragment",
			"artifact_EmberRune",
			"artifact_StarMapFragment",
			"artifact_SunlanceLens",
			"artifact_ForgekeeperOath",
			"artifact_ShatteringChronicle",
		},
	},
} :: { Sheet }

--[[
	The Pop UI textures (owner 2026-10-21: "everything must glow: light edges,
	cool backgrounds", the Roblox shop photos). Made by
	tools/preview/make_ui_textures.py into NAHRAJ_DO_ROBLOXU/ikony_ui:
	  ui_studs.png  a 128 px tile of raised studs (ScaleType Tile over any colour)
	  ui_fx.png     rays, glow, sparkle and shine in one sheet
	Paste the uploaded ids here. Until then the Pop kit draws its own
	stand-ins from frames (rays, discs, drawn sparkles) and no studs.
	The preview pictures are fx_rays / fx_glow / fx_sparkle / fx_shine / ui_studs.
]]
export type Texture = { File: string, Id: number, Offset: Vector2?, Size: Vector2? }

IconAssets.Textures = {
	ui_studs = { File = "ui_studs.png", Id = 0 },
	-- the pixel reels' lattice (owner 2026-10-22): one tiled picture instead of Pop.lattice's frames
	ui_lattice = { File = "ui_lattice.png", Id = 0 },
	fx_rays = { File = "ui_fx.png", Id = 0, Offset = Vector2.new(0, 0), Size = Vector2.new(512, 512) },
	fx_glow = { File = "ui_fx.png", Id = 0, Offset = Vector2.new(512, 0), Size = Vector2.new(256, 256) },
	fx_sparkle = { File = "ui_fx.png", Id = 0, Offset = Vector2.new(768, 0), Size = Vector2.new(128, 128) },
	fx_shine = { File = "ui_fx.png", Id = 0, Offset = Vector2.new(512, 256), Size = Vector2.new(512, 128) },
	-- the Terra Forge Custom hoverboard's painted deck (tools/preview/make_board_doodle.py, one
	-- Decal in NAHRAJ_DO_ROBLOXU/hoverboard): until uploaded the board's doodles are flat parts
	board_custom_deck = { File = "hoverboard_custom_deck.png", Id = 0 },
} :: { [string]: Texture }

-- Sets every texture cut from one uploaded file to its id (ui_fx.png's four share one).
function IconAssets.setTextureFile(file: string, id: number)
	for _, texture in IconAssets.Textures do
		if texture.File == file then
			texture.Id = id
		end
	end
end

-- Shows texture `name` on an ImageLabel ("" until uploaded); true when it will show.
function IconAssets.applyTexture(label: ImageLabel, name: string): boolean
	local texture = IconAssets.Textures[name]
	label:SetAttribute("Icon", name)
	if not texture or texture.Id <= 0 then
		label.Image = ""
		return IconAssets.Previewing and texture ~= nil
	end
	label.Image = "rbxassetid://" .. tostring(texture.Id)
	if texture.Offset and texture.Size then
		label.ImageRectOffset = texture.Offset
		label.ImageRectSize = texture.Size
	end
	return true
end

-- Will texture `name` show (uploaded, or in the previews)?
function IconAssets.textureShows(name: string): boolean
	local texture = IconAssets.Textures[name]
	if not texture then
		return false
	end
	return texture.Id > 0 or IconAssets.Previewing
end

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

--[[
	The four top-row buttons' pictures in one image of their own (owner 2026-11-07: "one picture is
	enough"; ../NAHRAJ_DO_ROBLOXU/ikony_ui/horni_lista.png, cut from the sheets): a row of Cell px
	squares. Only the top row reads it (Pop.tabMark), so the left tiles keep waiting for their own
	sheets. Not in Sheets: the sheets' tools and specs want every icon listed once.
]]
IconAssets.TopRow = {
	File = "horni_lista.png",
	Id = 78546060222076,
	Cells = { cart = 0, lobby = 1, base = 2, vault = 3 } :: { [string]: number },
}

-- Does the top row's own image hold icon `name`?
function IconAssets.topRowHas(name: string): boolean
	return IconAssets.TopRow.Id > 0 and IconAssets.TopRow.Cells[name] ~= nil
end

--[[
	The left menu's whole tiles in one image of their own (owner 2026-11-07: "exactly like this, in
	pictures"; ../NAHRAJ_DO_ROBLOXU/ikony_ui/hud_dlazdice.png, from tools/preview/tile_art by
	make_tile_sheet.py): 4 x 3 cells of 256 px, each a finished tile with its word drawn in it; later
	pictures in the second image. Tiles lists which menu tile (HudBubble.tile's Name) shows
	which picture; without one a tile keeps its dark face and word. "Shop" in the menu is the luck
	boosts, so his Shop picture is on Store.
]]
IconAssets.TileArt = {
	File = "hud_dlazdice.png",
	Id = 137469404437333,
	Cell = 256,
	Columns = 4,
	Cells = {
		shop = 0,
		build = 1,
		golems = 2,
		hoverboard = 3,
		index = 4,
		daily = 5,
		inventory = 6,
		rebirth = 7,
		more = 8,
		spin = 9,
		elevator = 10,
	} :: { [string]: number },
	-- the second image (hud_dlazdice_2.png, 3 x 3 cells; 0: not uploaded yet, its tiles keep their
	-- word): Boosts, Settings and Trade, and the potions without a background for the Boosts window
	Second = {
		File = "hud_dlazdice_2.png",
		Id = 0,
		Columns = 3,
		Cells = {
			boosts = 0,
			settings = 1,
			trade = 2,
			potion_lucky = 3,
			potion_coins = 4,
			potion_mining = 5,
			potion_speed = 6,
			potion_strength = 7,
			potion_mythic = 8,
		} :: { [string]: number },
	},
	Tiles = {
		Shop = "boosts", -- (the menu's Shop is the luck boosts)
		Settings = "settings",
		Trade = "trade",
		Store = "shop",
		Build = "build",
		Golems = "golems",
		Ride = "hoverboard",
		Codex = "index",
		Quests = "daily",
		Backpack = "inventory",
		Rebirth = "rebirth",
		More = "more",
		Wheel = "spin",
		Elevator = "elevator",
	} :: { [string]: string },
}

-- The picture of menu tile `tile` (nil: it has none, or the image isn't uploaded).
function IconAssets.tileArt(tile: string): string?
	local t = IconAssets.TileArt
	local art = t.Tiles[tile]
	if not art then
		return nil
	end
	local there = if t.Cells[art] ~= nil then t.Id > 0 else t.Second.Id > 0
	return if there then art else nil
end

-- Shows the whole-tile picture `art` on an ImageLabel.
function IconAssets.applyTileArt(label: ImageLabel, art: string)
	local t = IconAssets.TileArt
	local cell = t.Cells[art]
	local id, columns = t.Id, t.Columns
	if cell == nil then
		cell, id, columns = t.Second.Cells[art], t.Second.Id, t.Second.Columns
	end
	label.Image = "rbxassetid://" .. tostring(id)
	label.ImageRectOffset = Vector2.new((cell % columns) * t.Cell, (cell // columns) * t.Cell)
	label.ImageRectSize = Vector2.new(t.Cell, t.Cell)
end

-- The preview tools set this: they draw every icon from build/preview/icons,
-- so layouts that differ without an uploaded picture use the uploaded look.
IconAssets.Previewing = false

-- Will icon `name` show a picture (its sheet is uploaded, or a preview)?
function IconAssets.shows(name: string): boolean
	if IconAssets.Previewing then
		return IconAssets.has(name)
	end
	local image = IconAssets.find(name)
	return image ~= ""
end

-- Will a top-row button show icon `name` (its own image, or its sheet)?
function IconAssets.topRowShows(name: string): boolean
	return IconAssets.topRowHas(name) or IconAssets.shows(name)
end

-- Shows a top-row button's icon `name`: from the top row's own image, else its sheet.
function IconAssets.applyTopRow(label: ImageLabel, name: string)
	if IconAssets.topRowHas(name) then
		local cell = IconAssets.TopRow.Cells[name]
		label.Image = "rbxassetid://" .. tostring(IconAssets.TopRow.Id)
		label.ImageRectOffset = Vector2.new(cell * IconAssets.Cell, 0)
		label.ImageRectSize = Vector2.new(IconAssets.Cell, IconAssets.Cell)
		return
	end
	IconAssets.apply(label, name)
end

-- Shows icon `name` on an ImageLabel.
function IconAssets.apply(label: ImageLabel, name: string)
	local image, offset, size = IconAssets.find(name)
	label.Image = image
	label.ImageRectOffset = offset
	label.ImageRectSize = size
end

return IconAssets
