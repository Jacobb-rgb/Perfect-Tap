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
} :: { [string]: number }

-- "rbxassetid://<id>" for an icon, or "" when it has not been uploaded yet.
function IconAssets.image(name: string): string
	local id = IconAssets.Ids[name]
	if id and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return ""
end

return IconAssets
