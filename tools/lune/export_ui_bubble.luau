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
