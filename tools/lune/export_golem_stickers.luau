--[[
	Exports the models of the shop's golem and egg stickers for
	tools/preview/shop_golem_sheet.mjs (the toon renderer): every name in
	IconAssets.ShopGolems.Icons (golem_<Kind>, capsule_<Id>) built by
	PictureModels.build, exactly the model the shop's 3D picture shows (a
	Royal Egg golem in its egg costume, a Dragonforge golem in its limited
	gear, the Royal egg, the Dragonforge shard), with the picture's camera
	direction (`from`). One file: build/preview/golem_stickers.json
	  { cell, columns, order = { names }, models = { [name] = { from, parts, names } } }
	parts are tools/lune/lib/export's ([shape, sx, sy, sz, cf(12), colorHex, material,
	transparency, ...]); names[i] is part i's Name (the renderer finds the head, the
	body and the gems by them).

	  lune run tools/lune/export_golem_stickers.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")

local root = process.cwd
Loader.init(root)

local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
local PictureModels = Loader.requirePath("ReplicatedStorage.Shared.Builders.PictureModels")

local sheet = IconAssets.ShopGolems
local out = { cell = sheet.Cell, columns = sheet.Columns, order = sheet.Icons, models = {} :: { [string]: any } }

for _, name in sheet.Icons do
	local model, from = PictureModels.build(name)
	if not model then
		error("PictureModels.build has no model for " .. name)
	end
	local scene = Export.collect(model)
	-- the parts' names, in Export.collect's order (the same walk and the same filter)
	local names = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			table.insert(names, d.Name)
		end
	end
	assert(#names == #scene.parts, name .. ": the names follow the parts")
	out.models[name] = { from = { from.X, from.Y, from.Z }, parts = scene.parts, names = names }
	print(string.format("Exported sticker model %s: %d parts", name, #scene.parts))
end

fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/golem_stickers.json", serde.encode("json", out))
print("-> build/preview/golem_stickers.json")
