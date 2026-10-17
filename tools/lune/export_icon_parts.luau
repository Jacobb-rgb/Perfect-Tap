--[[
	Exports game models that become 3D UI icons (hotbar blaster, ore chunks)
	to build/preview/icon_parts/<name>.json for tools/preview/render_icons.mjs.

	  lune run tools/lune/export_icon_parts.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")

local root = process.cwd
Loader.init(root)

local CF = roblox.CFrame
local Kenney = require("./lib/blaster_kenney")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")

local models: { [string]: any } = {}

models.blaster = Kenney.gun(Loader, 1, "")
models.blaster_copper = Kenney.gun(Loader, 2, "Copper")
models.ore_raw = ItemBuilder.build({ Kind = "Raw", OreId = "Copper" }, CF.new(), 3)
models.ore_copper = ItemBuilder.build({ Kind = "Clean", OreId = "Copper", Grade = "Pristine" }, CF.new(), 4)
models.ore_silver = ItemBuilder.build({ Kind = "Clean", OreId = "Silver", Grade = "Pristine" }, CF.new(), 5)
models.ingot_gold = ItemBuilder.build({ Kind = "Ingot", OreId = "Gold", Grade = "Pristine" }, CF.new(), 6)

fs.writeDir(root .. "/build/preview/icon_parts")
for name, model in models do
	local scene = Export.collect(model)
	fs.writeFile(root .. "/build/preview/icon_parts/" .. name .. ".json", serde.encode("json", scene))
	print(string.format("Exported icon part model %s: %d parts", name, #scene.parts))
end
