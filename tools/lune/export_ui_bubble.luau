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

local ArtifactsBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.ArtifactsBubble")
local artifactsData = {
	Collections = {
		{ Id = "CrownOfKaldrum", Name = "The Crown of Kaldrum", Found = 6, Total = 6, New = true },
		{ Id = "RoyalRailway", Name = "The Royal Railway", Found = 4, Total = 6 },
		{ Id = "Golemworks", Name = "The Golemworks", Found = 2, Total = 6 },
		{ Id = "HeartstoneLore", Name = "The Heartstone Lore", Found = 3, Total = 6 },
	},
	Selected = "RoyalRailway",
	Artifacts = {
		{ Id = "GoldenSpike", Name = "Golden Rail Spike", Rarity = "Common", Color = rarity.Common, Found = 2 },
		{ Id = "ConductorWhistle", Name = "Conductor's Whistle", Rarity = "Common", Color = rarity.Common, Found = 1 },
		{ Id = "RailLantern", Name = "Rail Lantern", Rarity = "Uncommon", Color = rarity.Uncommon, Found = 1 },
		{ Id = "LastTicket", Name = "Last Train Ticket", Rarity = "Uncommon", Color = rarity.Uncommon, Found = 0 },
		{ Id = "RoyalTimetable", Name = "Royal Timetable", Rarity = "Rare", Color = rarity.Rare, Found = 1 },
		{ Id = "LocomotiveCrest", Name = "Locomotive Crest", Rarity = "Epic", Color = rarity.Epic, Found = 0 },
	},
	Artifact = "RailLantern",
	Lore = "It hung on the last car of the night trains so the tunnels never felt empty.",
	Where = "Most often in Deep Hollow: 1 in 1,357 broken rocks",
	Reward = "title Royal Conductor · Brass Rails podium skin · +10% sell value",
	Button = "FIND ALL 6 TO UNLOCK CHAPTER 2",
	Found = 15,
	Total = 24,
}
local journalData = {
	Chapters = {
		{ Id = "Prologue", Name = "Prologue: The Apprentice" },
		{ Id = "Chapter1", Name = "Chapter 1: The Ember Kings", New = true },
		{ Id = "Chapter2", Name = "Chapter 2: Rails Under the Mountain", Locked = true },
		{ Id = "Chapter3", Name = "Chapter 3: The Sleeping Helpers", Locked = true },
		{ Id = "Chapter4", Name = "Chapter 4: The Shattering", Locked = true },
	},
	Selected = "Chapter1",
	Kicker = "Chapter 1: The Ember Kings",
	Title = "The Crown and the Flame",
	Text = "The Ember Kings ruled from a throne carved over the Heartstone. At every coronation the scepter was raised over the stone, and the stone glowed brighter for its new king.",
	Page = 2,
	Pages = 4,
}
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	ArtifactsBubble.build(gui, spec[2], artifactsData)
	write("ui_bubble_artifacts_" .. spec[1], gui)
	local gui2 = windowGui(spec[2], spec[3])
	ArtifactsBubble.journal(gui2, spec[2], journalData)
	write("ui_bubble_journal_" .. spec[1], gui2)
end

local BoardsBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoardsBubble")
local boardEntries = {}
for i, row in {
	{ "EmberQueen", "$8.2Qa" }, { "RockyMiner77", "$2.65Qa" }, { "Forgekeeper_Ola", "$853T" }, { "CrystalKid", "$275T" },
	{ "DeepHollowDan", "$88.8T" }, { "Pickaxe_Pat", "$28.6T" }, { "You_TerraFan", "$9.24T" }, { "GolemWhisperer", "$2.98T" },
	{ "SparkyStone", "$961B" }, { "QuarryQuinn", "$310B" },
} do
	table.insert(boardEntries, { Rank = i, Name = row[1], Value = row[2], You = i == 7 })
end
local boardsData = {
	Tab = "TotalEarned",
	Entries = boardEntries,
	You = { Rank = 7, Name = "YOU", Value = "$9.24T", You = true },
	Note = "The best Forgekeepers of all servers. Updated every minute.",
}
local settingsRows = {
	{ Id = "Sounds", Name = "Sounds", Hint = "Every game sound", Icon = "speaker", Kind = "Slider", Value = 0.8 },
	{ Id = "Music", Name = "Music", Hint = "Soundtrack coming soon", Icon = "music", Kind = "Soon" },
	{ Id = "CameraShake", Name = "Camera shake", Hint = "When rocks crack", Icon = "camera", Kind = "Toggle", On = true },
	{ Id = "Rumble", Name = "Gamepad rumble", Hint = "Vibration while you blast", Icon = "gamepad", Kind = "Toggle", On = false },
}
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	BoardsBubble.boards(gui, spec[2], boardsData)
	write("ui_bubble_boards_" .. spec[1], gui)
	local gui2 = windowGui(spec[2], spec[3])
	BoardsBubble.settings(gui2, spec[2], settingsRows, "Saved to your profile: they follow you to every device.")
	write("ui_bubble_settings_" .. spec[1], gui2)
end

local GearBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.GearBubble")
local EnchantBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EnchantBubble")
local gearData = {
	Coins = "$48.2K",
	Note = "Ore Backpack III: you can carry 5 items!",
	Gear = {
		{ Id = "Boots", Name = "Miner's Boots", Icon = "boots", Level = 2, MaxLevel = 5, Text = "Walk faster everywhere.", From = "20", To = "22", Unit = "walk speed", Price = "$18K", State = "Buy", Color = rgb(255, 110, 110) },
		{ Id = "Lamp", Name = "Helmet Lamp", Icon = "helmet", Level = 1, MaxLevel = 5, Text = "A head lamp that lights up dark caves.", From = "18", To = "26", Unit = "studs of light", Price = "$2.4K", State = "Buy", Color = rgb(255, 196, 40) },
		{ Id = "Backpack", Name = "Ore Backpack", Icon = "backpack", Level = 3, MaxLevel = 5, Text = "Carry more ore chunks at once.", From = "5", To = "8", Unit = "items you can carry", Price = "$180K", State = "Bought", Color = rgb(61, 205, 120) },
		{ Id = "Gloves", Name = "Grip Gloves", Icon = "gloves", Level = 0, MaxLevel = 5, Text = "Grab ore from further away, throw harder.", From = "11", To = "13", Unit = "studs reach", Price = "$600", State = "Buy", Color = rgb(255, 150, 60) },
		{ Id = "Magnet", Name = "Ore Magnet", Icon = "magnet", Level = 1, MaxLevel = 5, Text = "Mined ore flies into your hands.", From = "14", To = "18", Unit = "studs pull", Price = "$9K", State = "Buy", Color = rgb(77, 150, 255) },
	},
}
local enchantData = {
	Header = "YOUR BLASTER · LEVEL 5 · 2 OF 4 SLOTS",
	Coins = "$4.82M",
	ShardCount = "135",
	Slots = {
		{ Id = "Power", Name = "POWER II", Effect = "+20% damage" },
		{ Id = "Lucky", Name = "LUCKY I", Effect = "+15% ore luck" },
		{ Id = "Slot3", Locked = "Blaster level 7" },
		{ Id = "Slot4", Locked = "Blaster level 10" },
	},
	Enchants = {
		{ Id = "Power", Name = "Power", Rarity = "Common", Color = rarity.Common, Effect = "+20% blaster damage", Price = "next $72K", Level = "II/III" },
		{ Id = "Swift", Name = "Swift", Rarity = "Common", Color = rarity.Common, Effect = "+1 walk speed", Price = "$1.5K", New = true },
		{ Id = "Reach", Name = "Reach", Rarity = "Uncommon", Color = rarity.Uncommon, Effect = "+2 studs blaster range", Price = "$20K", New = true },
		{ Id = "Magnetism", Name = "Magnetism", Rarity = "Uncommon", Color = rarity.Uncommon, Effect = "Ore flies to you from further", Price = "$45K" },
		{ Id = "Lucky", Name = "Lucky", Rarity = "Rare", Color = rarity.Rare, Effect = "+15% ore luck", Price = "next $1.2M", Level = "I/III" },
		{ Id = "Midas", Name = "Midas", Rarity = "Rare", Color = rarity.Rare, Effect = "+10% sell value", Price = "$2.5M" },
		{ Id = "TwinDrop", Name = "Twin Drop", Rarity = "Epic", Color = rarity.Epic, Effect = "Sometimes an ore drops twice", Price = "$30M", Level = "I/III" },
		{ Id = "Overcharge", Name = "Overcharge", Rarity = "Epic", Color = rarity.Epic, Effect = "Faster beam after 3 s", Price = "$60M" },
		{ Id = "Prospector", Name = "Prospector", Rarity = "Legendary", Color = rarity.Legendary, Effect = "Rare rocks show on the map", Price = "$900M" },
		{ Id = "GolemBond", Name = "Golem Bond", Rarity = "Legendary", Color = rarity.Legendary, Effect = "+25% golem bonuses", Price = "$1.5B" },
		{ Id = "Heartfire", Name = "Heartfire", Rarity = "Mythic", Color = rarity.Mythic, Effect = "Burning beam", Price = "20 Robux" },
		{ Id = "Starbreaker", Name = "Starbreaker", Rarity = "Mythic", Color = rarity.Mythic, Effect = "+75% ore luck", Price = "20 Robux" },
	},
	Selected = "TwinDrop",
	Description = "Sometimes an ore drops twice.",
	Now = "+5% chance of a twin chunk",
	Next = "+10% chance of a twin chunk",
	Tiers = { "I: +5% chance of a twin chunk (yours)", "II: +10% chance of a twin chunk", "III: +15% chance of a twin chunk" },
	Buy = "$30M",
	Shards = "120",
}
local dark = {
	Common = rgb(110, 118, 130), Uncommon = rgb(40, 150, 60), Rare = rgb(30, 110, 210),
	Epic = rgb(130, 60, 210), Legendary = rgb(210, 120, 0), Mythic = rgb(220, 30, 90),
}
local boostData = {
	Tab = "TripleLucky",
	Name = "Triple Lucky",
	Icon = "clover",
	Active = "3:42 left",
	Text = "Golem capsules: the rarest golems in every capsule are 3x as likely.",
	Offers = {
		{ Text = "+5 MIN", Price = "$7.5M" },
		{ Text = "+15 MIN", Soon = true },
		{ Text = "+1 HOUR", Soon = true },
	},
	Note = "Coins top a boost up below 10 min left. At most 2 h at once.",
	Capsule = "Crystal Capsule",
	Coins = "$4.82M",
	Odds = {
		{ Name = "Epic or better", Color = dark.Epic, Without = "13%", With = "39%" },
		{ Name = "Starmetal Sovereign", Icon = "golem_StarmetalSovereign", Color = dark.Mythic, Without = "0.07%", With = "0.21%" },
		{ Name = "Heartstone Colossus", Icon = "golem_HeartstoneColossus", Color = dark.Mythic, Without = "0.03%", With = "0.09%" },
		{ Name = "Stormcore Titan", Icon = "golem_StormcoreTitan", Color = dark.Legendary, Without = "1.2%", With = "3.6%" },
		{ Name = "Moonstone Oracle", Icon = "golem_MoonstoneOracle", Color = dark.Legendary, Without = "0.7%", With = "2.1%" },
		{ Name = "Ruby Knight", Icon = "golem_RubyKnight", Color = dark.Epic, Without = "5%", With = "15%" },
		{ Name = "Sapphire Sage", Icon = "golem_SapphireSage", Color = dark.Epic, Without = "3.5%", With = "10.5%" },
		{ Name = "Diamond Duke", Icon = "golem_DiamondDuke", Color = dark.Epic, Without = "2.5%", With = "7.5%" },
	},
}
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local gui = windowGui(spec[2], spec[3])
	GearBubble.build(gui, spec[2], gearData)
	write("ui_bubble_gear_" .. spec[1], gui)
	local gui2 = windowGui(spec[2], spec[3])
	EnchantBubble.enchants(gui2, spec[2], enchantData)
	write("ui_bubble_enchants_" .. spec[1], gui2)
	local gui3 = windowGui(spec[2], spec[3])
	EnchantBubble.boosts(gui3, spec[2], boostData)
	write("ui_bubble_boosts_" .. spec[1], gui3)
end

---------------------------------------------------------------- the game HUD behind the switch (UIConfig.LightUI on)
local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")
local BuildView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BuildView")
UIConfig.LightUI = true
for _, spec in { { "pc", 1.25, 1 }, { "phone", 0.62, 2 } } do
	local refs = HudBubble.buildGame(spec[2])
	refs.Gui.Scale.Scale = spec[2] * spec[3]
	TeleportView.build(refs.TopBar, refs.Menu, spec[2])
	BuildView.menuButton(refs.Menu)
	refs.Coins.Text = "$48.2K"
	refs.Income.Text = "+$186/s"
	HudView.slot(refs.CarrySlots, Color3.fromRGB(61, 165, 255), 1, false)
	HudView.slot(refs.CarrySlots, nil, 2, true)
	HudView.slot(refs.CarrySlots, nil, 3, false)
	refs.CarryLabel.Text = "CARRYING 2/3"
	HudView.toast(refs.Toasts, "New ore discovered: Sapphire!", Color3.fromRGB(61, 165, 255))
	write("ui_bubble_game_" .. spec[1], refs.Gui)
end

-- build mode with the switch on (BuildView's own light refs + the HUD it leaves on screen)
for _, spec in { { "pc", 1.25, 1, false }, { "phone", 0.62, 2, true } } do
	local hud = HudBubble.buildGame(spec[2])
	hud.Gui.Scale.Scale = spec[2] * spec[3]
	hud.Coins.Text = "$48.2K"
	hud.Income.Text = "+$186/s"
	hud.CarryPanel.Visible = false
	hud.Menu.Visible = false
	hud.TopBar.Visible = false
	local view = BuildView.build()
	view.Gui.Scale.Scale = spec[2] * spec[3]
	view.Gui.Enabled = true
	BuildView.setInventory(view, { ClayFurnace = 2, Crusher = 1, CleaningStation = 1, Conveyor = 24, Splitter = 2, StorageCrate = 1, AutoCleaner = 1, SolarPanel = 2 }, "Crusher", function() end)
	BuildView.setCounts(view, 6, 10, 24, 40)
	BuildView.setReason(view, "Needs power: put a Solar Panel nearby", "Warn")
	BuildView.setHint(view, if spec[4] then nil else "R rotate  ·  Q cancel  ·  Click to place")
	BuildView.setMode(view, "Placing", spec[4])
	fs.writeFile(root .. "/build/preview/ui_light_build_" .. spec[1] .. ".json", serde.encode("json", UiExport.export({ hud.Gui, view.Gui })))
	print("Exported UI ui_light_build_" .. spec[1])
end
UIConfig.LightUI = false

---------------------------------------------------------------- Tobin's Sell window (SellView) with the switch on and off
local SellView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SellView")
local LightSkin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LightSkin")
local penSummary = {
	["Raw|Copper||"] = 3,
	["Raw|Silver||"] = 1,
	["Clean|Gold|Pristine|"] = 2,
	["Clean|Silver|Clean|"] = 4,
	["Clean|Copper|Rough|"] = 6,
	["Ingot|Iron|Clean|"] = 2,
}
local handsSummary = { ["Clean|Amethyst|Flawless|"] = 1 }
for _, light in { false, true } do
	UIConfig.LightUI = light
	for _, spec in { { "pc", 1.25, 1, false, 1280, 690 }, { "phone", 0.62, 2, true, 1000, 520 } } do
		local hud = if light then HudBubble.buildGame(spec[2]) else HudView.build()
		hud.Gui.Scale.Scale = spec[2] * spec[3]
		hud.Coins.Text = "$12.5K"
		hud.Income.Text = "+$412/s"
		local view = SellView.build(spec[4])
		view.Gui.Scale.Scale = spec[2] * spec[3]
		view.Gui.Enabled = true
		SellView.layout(view, spec[4], spec[5], spec[6])
		SellView.setEntries(view, "Pen", SellView.entries(penSummary, "Pen"))
		SellView.setEntries(view, "Hands", SellView.entries(handsSummary, "Hands"))
		SellView.setFooter(view, SellView.plan(penSummary, handsSummary, "Dirty"), SellView.plan(penSummary, handsSummary, "AllButBest"))
		if light then
			LightSkin.refresh(view.Gui)
		end
		local name = "ui_sell_" .. spec[1] .. (if light then "_light" else "")
		fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", UiExport.export({ hud.Gui, view.Gui })))
		print("Exported UI " .. name)
	end
end
UIConfig.LightUI = false

---------------------------------------------------------------- device sweep (switch on): HUD + the Tech Shop on every screen
local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
local TechPreview = require("./lib/tech_shop_preview")
local DEVICES = {
	-- name, width pt, height pt, render pixels per pt, touch, ten-foot
	{ "phone_tiny", 568, 320, 2.2, true, false },
	{ "phone_small", 667, 375, 2, true, false },
	{ "phone_big", 932, 430, 1.6, true, false },
	{ "tablet", 1024, 768, 1.5, true, false },
	{ "pc", 1920, 1080, 1, false, false },
	{ "tv", 1920, 1080, 1, false, true },
}
local INSET = 58 -- Roblox's top bar (pt)
local Vector2 = roblox.Vector2
UIConfig.LightUI = true
for _, d in DEVICES do
	local name, w, h, px, touch, tenFoot = d[1], d[2], d[3], d[4], d[5], d[6]
	local uiScale = HudBubble.scaleFor(Vector2.new(w, h))
	local hud = HudBubble.buildGame(uiScale, w)
	hud.Gui.Scale.Scale = uiScale * px
	TeleportView.build(hud.TopBar, hud.Menu, uiScale, w)
	BuildView.menuButton(hud.Menu)
	hud.Coins.Text = "$48.2K"
	hud.Income.Text = "+$64/s"
	for i = 1, 3 do
		HudView.slot(hud.CarrySlots, nil, i)
	end
	hud.CarryLabel.Text = "CARRYING 0/3"
	write("ui_dev_hud_" .. name, hud.Gui)
	local compact = TechShopView.compactFor(touch, tenFoot, uiScale, h)
	local view = TechShopView.build(compact)
	view.Gui.Scale.Scale = uiScale * px
	view.Gui.Enabled = true
	TechShopView.layout(view, compact, w / uiScale, (h - INSET) / uiScale)
	TechShopView.setTab(view, "Machines")
	TechShopView.setCoins(view, 48250)
	TechShopView.setCards(view, TechShopView.cards(TechPreview.State, 48250))
	TechShopView.setHint(view, if tenFoot then "A: buy   B: close" elseif touch then "Tap BUY" else "Click a tab, then BUY · Backspace: close", nil)
	LightSkin.refresh(view.Gui)
	fs.writeFile(root .. "/build/preview/ui_dev_tech_" .. name .. ".json", serde.encode("json", UiExport.export({ hud.Gui, view.Gui })))
	print("Exported UI ui_dev_tech_" .. name)
end
UIConfig.LightUI = false
