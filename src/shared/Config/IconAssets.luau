--[[
	The 3D UI icons (pictures rendered by tools/preview/render_icons.mjs and
	uploaded to Roblox by the owner). Fill in each image asset id after the
	upload; an icon without an id shows nothing (the button text still shows).
]]

local IconAssets = {}

IconAssets.Ids = {
	coin = 0,
	coins = 0,
	backpack = 0,
	golem = 0,
	build = 0,
	shop = 0,
	more = 0,
	base = 0,
	lobby = 0,
	vault = 0,
	blaster = 0,
	blaster_copper = 0,
	ore_raw = 0,
	ore_copper = 0,
	ore_silver = 0,
	ingot_gold = 0,
	shard = 0,
	artifact = 0,
	medal = 0,
	podium = 0,
	moon = 0,
	train = 0,
	clover = 0,
	rainbow = 0,
	enchant = 0,
	check = 0,
	-- golems and capsules (step 7 GolemBuilder models)
	golem_PebbleGolem = 0,
	golem_CopperTinker = 0,
	golem_CoalChomper = 0,
	golem_TinTumbler = 0,
	golem_QuartzSprite = 0,
	golem_SilverSquire = 0,
	golem_AmethystAcolyte = 0,
	golem_JadeGardener = 0,
	golem_EmberImp = 0,
	golem_CobaltDiver = 0,
	golem_GildedPorter = 0,
	golem_RubyKnight = 0,
	golem_SapphireSage = 0,
	golem_DiamondDuke = 0,
	golem_StormcoreTitan = 0,
	golem_MoonstoneOracle = 0,
	golem_StarmetalSovereign = 0,
	golem_HeartstoneColossus = 0,
	capsule_Stone = 0,
	capsule_Crystal = 0,
	capsule_Royal = 0,
} :: { [string]: number }

-- Roblox's own images (no upload needed).
IconAssets.BuiltIn = {
	robux = "rbxasset://textures/ui/common/robux.png",
} :: { [string]: string }

-- "rbxassetid://<id>" for an icon, or "" when it has not been uploaded yet.
function IconAssets.image(name: string): string
	local builtIn = IconAssets.BuiltIn[name]
	if builtIn then
		return builtIn
	end
	local id = IconAssets.Ids[name]
	if id and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return ""
end

return IconAssets
