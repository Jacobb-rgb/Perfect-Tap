--[[
	Exports the light "Bubble" HUD (src/client/UI/HudBubble.luau) with sample
	numbers for preview renders: build/preview/ui_bubble_pc.json and
	ui_bubble_phone.json. Shots: tools/preview/ui_bubble_shots.json (the world
	scene + this overlay; icons from tools/preview/render_icons.mjs).

	  lune run tools/lune/export_ui_bubble.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local UiExport = require("./lib/uiexport")

local root = process.cwd
Loader.init(root)

local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
local Bubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Bubble")

-- uiScale = what HudController picks on that screen; pixels = render pixels per point
local function export(name: string, uiScale: number, pixels: number)
	local refs = HudBubble.build(uiScale)
	refs.Gui.Scale.Scale = uiScale * pixels
	refs.Coins.Text = "$1.25M"
	refs.Income.Text = "+$12.4K/s"
	HudBubble.setSlot(refs.Slots[1], "blaster", true)
	HudBubble.setSlot(refs.Slots[2], "ore_raw")
	HudBubble.setSlot(refs.Slots[3], "ingot_gold")
	refs.CarryLabel.Text = "CARRYING 2/3"
	HudBubble.toast(refs.Toasts, "New ore found: Copper!", "ore_raw", 1)
	local golems = refs.Menu.Golems
	if golems then
		Bubble.badge(golems, "!")
	end
	fs.writeDir(root .. "/build/preview")
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", UiExport.export({ refs.Gui })))
	print("Exported UI " .. name)
end

export("ui_bubble_pc", 1.25, 1)
export("ui_bubble_phone", 0.62, 2)

---------------------------------------------------------------- windows
local roblox = require("@lune/roblox") :: any
local Color3 = roblox.Color3
local UDim2 = roblox.UDim2
local UIKit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.UIKit")
local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
local CapsuleBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleBubble")

-- A window gui over the world: a soft dim, then the window (HUD hidden while it is open).
local function windowGui(uiScale: number, pixels: number)
	local gui = UIKit.screen("TerraForgeWindow", 10)
	gui.IgnoreGuiInset = true -- the dim covers the whole screen
	gui.Scale.Scale = uiScale * pixels
	UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = BubbleTheme.Shadow,
		BackgroundTransparency = 0.62,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	return gui
end

local function write(name: string, gui: any)
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", UiExport.export({ gui })))
	print("Exported UI " .. name)
end

local rarity = {
	Common = Color3.fromRGB(176, 186, 198),
	Uncommon = Color3.fromRGB(70, 206, 92),
	Rare = Color3.fromRGB(61, 165, 255),
	Epic = Color3.fromRGB(180, 92, 255),
	Legendary = Color3.fromRGB(255, 176, 32),
	Mythic = Color3.fromRGB(255, 59, 122),
}
-- the step 7 Stone capsule (CapsuleConfig on worktree-wf_7288c494-51a-8)
local stoneOdds = {
	{ "PebbleGolem", "Pebble Golem", "Common", 0.25 },
	{ "CopperTinker", "Copper Tinker", "Common", 0.22 },
	{ "CoalChomper", "Coal Chomper", "Common", 0.18 },
	{ "TinTumbler", "Tin Tumbler", "Common", 0.15 },
	{ "QuartzSprite", "Quartz Sprite", "Uncommon", 0.06 },
	{ "SilverSquire", "Silver Squire", "Uncommon", 0.05 },
	{ "AmethystAcolyte", "Amethyst Acolyte", "Uncommon", 0.03 },
	{ "JadeGardener", "Jade Gardener", "Uncommon", 0.025 },
	{ "EmberImp", "Ember Imp", "Rare", 0.015 },
	{ "CobaltDiver", "Cobalt Diver", "Rare", 0.01 },
	{ "GildedPorter", "Gilded Porter", "Rare", 0.007 },
	{ "RubyKnight", "Ruby Knight", "Epic", 0.002 },
	{ "SapphireSage", "Sapphire Sage", "Epic", 0.0007 },
	{ "DiamondDuke", "Diamond Duke", "Epic", 0.0003 },
}

local function capsuleData(triple: boolean)
	local golems = {}
	for _, row in stoneOdds do
		local chance = row[4]
		local lucky = triple and (row[3] == "Rare" or row[3] == "Epic")
		table.insert(golems, { Id = row[1], Name = row[2], Color = rarity[row[3]], Chance = chance, Lucky = lucky })
	end
	if triple then
		-- CapsuleConfig: Rare+ x3, the rest scaled by (1 - 3L) / (1 - L)
		local L = 0
		for _, g in golems do
			if g.Lucky then
				L += g.Chance
			end
		end
		for _, g in golems do
			g.Chance = if g.Lucky then g.Chance * 3 else g.Chance * (1 - 3 * L) / (1 - L)
		end
	end
	return {
		Capsules = {
			{ Id = "Stone", Name = "Stone Capsule", Color = Color3.fromRGB(176, 168, 160), Glow = Color3.fromRGB(255, 170, 80), Currency = "Coins", Prices = { "$2.5K", "$7.5K", "$22.5K" } },
			{ Id = "Crystal", Name = "Crystal Capsule", Color = Color3.fromRGB(120, 200, 255), Glow = Color3.fromRGB(170, 120, 255), Currency = "Coins", Prices = { "$750K", "$2.25M", "$6.75M" } },
			{ Id = "Royal", Name = "Royal Capsule", Color = Color3.fromRGB(255, 196, 60), Glow = Color3.fromRGB(255, 120, 160), Currency = "Robux", Prices = { "49", "139", "429" } },
		},
		Selected = "Stone",
		Golems = golems,
		Coins = "$48.2K",
		Owned = 14,
		Cap = 60,
		Boosts = {
			{ Id = "TripleLucky", Label = "TRIPLE LUCKY", Price = "39", Active = triple, TimeLeft = "14:32 LEFT" },
			{ Id = "HexaLucky", Label = "HEXA LUCKY", Price = "39" },
		},
	}
end

for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	CapsuleBubble.build(gui, spec[2], capsuleData(false))
	write("ui_bubble_capsules_" .. spec[1], gui)
end
local luckyGui = windowGui(1.25, 1)
CapsuleBubble.build(luckyGui, 1.25, capsuleData(true))
write("ui_bubble_capsules_lucky_pc", luckyGui)

---------------------------------------------------------------- backpack
local BackpackBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BackpackBubble")
local penItems = {
	{ "Clean", "Diamond", "Epic", "Clean", "$28K" },
	{ "Clean", "Heartstone", "Mythic", "Pristine", "$1.2M" },
	{ "Clean", "Stormcore", "Epic", "Flawless", "$52K" },
	{ "Ingot", "Gold", "Rare", "Pristine", "$9.6K" },
	{ "Clean", "Ruby", "Rare", "Pristine", "$4.8K" },
	{ "Clean", "Emerald", "Rare", "Clean", "$6.1K" },
	{ "Ingot", "Silver", "Uncommon", "Clean", "$3.2K" },
	{ "Clean", "Silver", "Uncommon", "Flawless", "$2.1K" },
	{ "Clean", "Jade", "Uncommon", "Pristine", "$1.4K" },
	{ "Clean", "Amethyst", "Uncommon", "Clean", "$860" },
	{ "Ingot", "Copper", "Common", "Clean", "$640" },
	{ "Crushed", "Iron", "Common", "Clean", "$240" },
	{ "Clean", "Quartz", "Common", "Clean", "$180" },
	{ "Clean", "Copper", "Common", "Rough", "$120" },
	{ "Clean", "Coal", "Common", "Rough", "$60" },
	{ "Raw", "Stormcore", "Epic", nil, "?" },
	{ "Raw", "Silver", "Uncommon", nil, "?" },
	{ "Raw", "Copper", "Common", nil, "?" },
}
local function backpackData()
	local items = {}
	for i, row in penItems do
		local kind, ore, rar, grade, value = row[1], row[2], row[3], row[4], row[5]
		local name = if kind == "Raw" then "Raw " .. ore
			elseif kind == "Ingot" then ore .. " Ingot"
			elseif kind == "Crushed" then "Crushed " .. ore
			else (grade or "") .. " " .. ore
		table.insert(items, {
			Id = "Item" .. i,
			Name = name,
			Icon = "item_" .. kind .. "_" .. ore,
			Color = rarity[rar],
			Rarity = rar,
			Grade = grade,
			Value = value,
		})
	end
	return { Tab = "Ores", Items = items, Selected = "Item1", Coins = "$48.2K", Shards = "120", Used = 18, Capacity = 40 }
end
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	BackpackBubble.build(gui, spec[2], backpackData())
	write("ui_bubble_backpack_" .. spec[1], gui)
end

---------------------------------------------------------------- shop (Robux)
local ShopBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ShopBubble")
-- MonetizationConfig (worktree-wf_7288c494-51a-10) passes
local shopData = {
	Tab = "Passes",
	Hero = {
		Id = "BigPass",
		Name = "Forgemaster's Pass",
		Description = "",
		Icon = "medal",
		Price = "560",
		Tag = "BEST VALUE",
		Perks = { "Podiums 3 and 4", "12 h offline earnings", "Double carrying", "The Glimmer Grotto", "Extra machine slots" },
	},
	Offers = {
		{ Id = "Podiums", Name = "Two More Podiums", Description = "Unlocks podiums 3 and 4 on your base.", Icon = "podium", Price = "100" },
		{ Id = "OfflineExtension", Name = "Night Shift", Description = "Your podiums keep earning while you are away for up to 12 hours instead of 5.", Icon = "moon", Price = "99", Owned = true },
		{ Id = "TrainExpress", Name = "Express Train", Description = "Your ore train runs twice as fast and carries half as much again.", Icon = "train", Price = "199" },
	},
}
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	ShopBubble.build(gui, spec[2], shopData)
	write("ui_bubble_shop_" .. spec[1], gui)
end

-- the BOOSTS tab (random things: the text says the new odds show before buying)
local boostsData = {
	Tab = "Boosts",
	Hero = {
		Id = "TripleLucky15",
		Name = "Triple Lucky",
		Description = "",
		Icon = "clover",
		Price = "39",
		Tag = "15 MIN",
		Perks = { "Rarest golems x3", "In every capsule", "New odds shown first", "Stacks with your golems" },
	},
	Offers = {
		{ Id = "TripleLucky60", Name = "Triple Lucky (1 hour)", Description = "Golem capsules: the rarest golems are 3 times as likely. New odds shown before buying.", Icon = "clover", Price = "129" },
		{ Id = "HexaLucky15", Name = "Hexa Lucky (15 min)", Description = "Mining: ore luck x2.5 (Rare x2.5, Epic x4, Legendary x6.3, Mythic x9.9).", Icon = "rainbow", Price = "39" },
		{ Id = "HexaLucky60", Name = "Hexa Lucky (1 hour)", Description = "The same mining luck for a whole hour. New odds shown before buying.", Icon = "rainbow", Price = "129" },
	},
}
local boostsGui = windowGui(1.25, 1)
ShopBubble.build(boostsGui, 1.25, boostsData)
write("ui_bubble_shop_boosts_pc", boostsGui)

---------------------------------------------------------------- build mode
local BuildBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildBubble")
local function buildData(touch: boolean)
	local owned = {
		{ "Crusher", "Crusher", "Special", 1 },
		{ "ClayFurnace", "Clay Furnace", "Furnaces", 2 },
		{ "BrickFurnace", "Brick Furnace", "Furnaces", 1 },
		{ "CleaningStation", "Cleaning Station", "Cleaning", 1 },
		{ "AutoCleaner", "Cleaning Plant", "Cleaning", 1 },
		{ "Polisher", "Polisher", "Cleaning", 1 },
		{ "Conveyor", "Conveyor", "Transport", 24 },
		{ "Splitter", "Splitter", "Transport", 2 },
		{ "RobotArm", "Robot Arm", "Transport", 1 },
		{ "SolarPanel", "Solar Panel", "Power", 2 },
		{ "WindTurbine", "Wind Turbine", "Power", 1 },
		{ "SellBox", "Sell Box", "Special", 1 },
	}
	local machines = {}
	for _, row in owned do
		table.insert(machines, { Id = row[1], Name = row[2], Group = row[3], Count = row[4] })
	end
	return {
		Machines = machines,
		Selected = "Crusher",
		Group = "All",
		Slots = "MACHINES 6/10  ·  BELTS 24/40",
		Reason = "Needs power: put a Solar Panel nearby",
		Hint = "R rotate  ·  Q cancel  ·  Click to place",
		Touch = touch,
	}
end
for _, spec in { { "pc", 1.25, 1, false }, { "phone", 0.62, 2, true } } do
	local refs = BuildBubble.build(spec[2], buildData(spec[4]))
	refs.Gui.Scale.Scale = spec[2] * spec[3]
	write("ui_bubble_build_" .. spec[1], refs.Gui)
end

---------------------------------------------------------------- HUD with the MORE flyout open
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local refs = HudBubble.build(spec[2])
	refs.Gui.Scale.Scale = spec[2] * spec[3]
	refs.Coins.Text = "$1.25M"
	refs.Income.Text = "+$12.4K/s"
	HudBubble.setSlot(refs.Slots[1], "blaster", true)
	HudBubble.setSlot(refs.Slots[2], "ore_raw")
	refs.CarryLabel.Text = "CARRYING 1/3"
	local more = HudBubble.moreMenu(refs, spec[2])
	Bubble.badge(more.Tiles.Wheel, "!")
	write("ui_bubble_more_" .. spec[1], refs.Gui)
end

---------------------------------------------------------------- MY GOLEMS
local GolemsBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GolemsBubble")
local owned = {
	{ "RubyKnight", "Ruby Knight", "Epic", "+16% Mining speed", "+16% MINING", true, true },
	{ "GildedPorter", "Gilded Porter", "Rare", "+10% Income", "+10% INCOME", true, false },
	{ "CobaltDiver", "Cobalt Diver", "Rare", "+10% Ore luck", "+10% LUCK", true, false },
	{ "EmberImp", "Ember Imp", "Rare", "+10% Mining speed", "+10% MINING", false, false },
	{ "AmethystAcolyte", "Amethyst Acolyte", "Uncommon", "+7% Sell value", "+7% SELL", false, false },
	{ "SilverSquire", "Silver Squire", "Uncommon", "+6% Income", "+6% INCOME", false, true },
	{ "QuartzSprite", "Quartz Sprite", "Uncommon", "+5% Ore luck", "+5% LUCK", false, false },
	{ "JadeGardener", "Jade Gardener", "Uncommon", "+5% Walk speed", "+5% SPEED", false, false },
	{ "CopperTinker", "Copper Tinker", "Common", "+4% Mining speed", "+4% MINING", false, false },
	{ "CoalChomper", "Coal Chomper", "Common", "+4% Sell value", "+4% SELL", false, false },
	{ "PebbleGolem", "Pebble Golem", "Common", "+3% Income", "+3% INCOME", false, false },
	{ "TinTumbler", "Tin Tumbler", "Common", "+3% Walk speed", "+3% SPEED", false, false },
	{ "PebbleGolem", "Pebble Golem", "Common", "+3% Income", "+3% INCOME", false, false },
	{ "CopperTinker", "Copper Tinker", "Common", "+4% Mining speed", "+4% MINING", false, false },
}
local function golemsData()
	local golems = {}
	for i, row in owned do
		table.insert(golems, {
			Id = "G" .. i,
			Kind = row[1],
			Name = row[2],
			Rarity = row[3],
			Color = rarity[row[3]],
			Bonus = row[4],
			Short = row[5],
			Equipped = row[6],
			Locked = row[7],
			Lore = if i == 1 then "Guarded the throne room of the Ember Kings. Now it guards you." else "A loyal little helper.",
		})
	end
	return { Golems = golems, Selected = "G1", Total = "+10% Income · +16% Mining speed · +10% Ore luck", Count = 14, Cap = 60 }
end
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	GolemsBubble.build(gui, spec[2], golemsData())
	write("ui_bubble_golems_" .. spec[1], gui)
end

---------------------------------------------------------------- capsule opening
local OpeningBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.OpeningBubble")
local function openingGui(uiScale: number, pixels: number)
	local gui = windowGui(uiScale, pixels)
	gui.Dim.BackgroundTransparency = 0.45
	return gui
end
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = openingGui(spec[2], spec[3])
	OpeningBubble.single(gui, spec[2], {
		Golems = { { Id = "G1", Kind = "HeartstoneColossus", Name = "Heartstone Colossus", Rarity = "Mythic", Color = rarity.Mythic, Bonus = "+40% Mining speed", New = true } },
		Again = "OPEN 1 AGAIN",
		Price = "$750K",
		Currency = "Coins",
		Lucky = true,
	})
	write("ui_bubble_open1_" .. spec[1], gui)
end
local ten = {
	{ "PebbleGolem", "Pebble Golem", "Common", "+3% Income", false },
	{ "CopperTinker", "Copper Tinker", "Common", "+4% Mining", false },
	{ "QuartzSprite", "Quartz Sprite", "Uncommon", "+5% Ore luck", true },
	{ "CoalChomper", "Coal Chomper", "Common", "+4% Sell value", false },
	{ "EmberImp", "Ember Imp", "Rare", "+10% Mining", true },
	{ "TinTumbler", "Tin Tumbler", "Common", "+3% Walk speed", false },
	{ "PebbleGolem", "Pebble Golem", "Common", "+3% Income", false },
	{ "SilverSquire", "Silver Squire", "Uncommon", "+6% Income", false },
	{ "CopperTinker", "Copper Tinker", "Common", "+4% Mining", false },
	{ "JadeGardener", "Jade Gardener", "Uncommon", "+5% Walk speed", true },
}
local tenGolems = {}
for i, row in ten do
	table.insert(tenGolems, { Id = "T" .. i, Kind = row[1], Name = row[2], Rarity = row[3], Color = rarity[row[3]], Bonus = row[4], New = row[5], Best = row[1] == "EmberImp" })
end
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = openingGui(spec[2], spec[3])
	OpeningBubble.multi(gui, spec[2], { Golems = tenGolems, Again = "OPEN 10 AGAIN", Price = "$22.5K", Currency = "Coins" })
	write("ui_bubble_open10_" .. spec[1], gui)
end

---------------------------------------------------------------- steps 6-7 windows (content from integrate/steps67 89eb9d9)
local WheelBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.WheelBubble")
local CodexBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CodexBubble")
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local wheelData = {
	Ready = true,
	Countdown = "Your free spin is ready!",
	Segments = {
		{ Id = "Coins", Label = "Coins", Detail = "2 min of your podium income, at least $500: $76.8K now", Chance = "30%", Color = rgb(255, 90, 90) },
		{ Id = "TripleLucky", Label = "Triple Lucky 10m", Detail = "+10 min of Triple Lucky: rarer golems from capsules", Chance = "12%", Color = rgb(255, 166, 60) },
		{ Id = "StoneCapsule", Label = "Stone Capsule", Detail = "A free Stone Capsule: Common 80% · Uncommon 16.5%", Chance = "15%", Color = rgb(255, 205, 50) },
		{ Id = "Shards", Label = "25 Shards", Detail = "25 crystal shards for the Enchant shop", Chance = "10%", Color = rgb(61, 205, 120) },
		{ Id = "BigCoins", Label = "Big Coins", Detail = "10 min of your podium income, at least $2.5K: $384K now", Chance = "8%", Color = rgb(34, 190, 200) },
		{ Id = "HexaLucky", Label = "Hexa Lucky 10m", Detail = "+10 min of Hexa Lucky: rarer ores from rocks", Chance = "12%", Color = rgb(77, 130, 255) },
		{ Id = "OrePrize", Label = "Ore Prize", Detail = "A dirty Rare+ ore for your Ore Pen: Sapphire 50%", Chance = "8%", Color = rgb(166, 108, 255) },
		{ Id = "CrystalCapsule", Label = "Crystal Capsule", Detail = "A free Crystal Capsule: Uncommon 63% · Rare 24%", Chance = "5%", Color = rgb(255, 100, 190) },
	},
}
local oreRows = {
	{ "Coal", "Common" }, { "Copper", "Common" }, { "Tin", "Common" }, { "Iron", "Common" }, { "Quartz", "Common" },
	{ "Silver", "Uncommon" }, { "Amethyst", "Uncommon" }, { "Jade", "Uncommon" }, { "Emberite", "Uncommon" }, { "Cobalt", "Uncommon" },
	{ "Gold", "Rare" }, { "Ruby", "Rare" }, { "Azurium", "Rare" }, { "Sapphire", "Rare" }, { "Emerald", "Rare" },
	{ "Diamond", "Epic" }, { "Verdantine", "Epic" }, { "Obsidian", "Epic" }, { "Stormcore", "Epic" }, { "Moonstone", "Epic" },
	{ "Bloodstone", "Epic" }, { "Solarite", "Legendary" }, { "Voidstone", "Legendary" }, { "Magmacore", "Legendary" },
	{ "Skyglass", "Legendary" }, { "RoyalAurum", "Legendary" }, { "Prismite", "Mythic" }, { "Aetherium", "Mythic" },
	{ "Starmetal", "Mythic" }, { "Heartstone", "Mythic" },
}
local codexOres = {}
for i, row in oreRows do
	table.insert(codexOres, {
		Id = row[1],
		Name = if row[1] == "RoyalAurum" then "Royal Aurum" else row[1],
		Rarity = row[2],
		Color = rarity[row[2]],
		Found = i <= 14,
		New = row[1] == "Ruby" or row[1] == "Sapphire",
	})
end
local codexData = {
	Ores = codexOres,
	Selected = "Ruby",
	Found = 14,
	Total = 30,
	Detail = {
		Podium = "+$200/s (Flawless +$480/s)",
		Sells = "$6K (Flawless $14.4K), dirty $2.4K",
		Blaster = "Blaster level 3+",
		FoundIn = "Ember Caves, Deep Hollow, Glimmer Grotto",
		Lore = "A drop of Ember King blood, the miners say. They say a lot of things.",
	},
}
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	WheelBubble.build(gui, spec[2], wheelData)
	write("ui_bubble_wheel_" .. spec[1], gui)
	local gui2 = windowGui(spec[2], spec[3])
	CodexBubble.build(gui2, spec[2], codexData)
	write("ui_bubble_codex_" .. spec[1], gui2)
end
