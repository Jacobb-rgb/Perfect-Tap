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
