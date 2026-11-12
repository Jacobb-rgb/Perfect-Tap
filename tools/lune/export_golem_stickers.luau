--[[
	Exports the models of the shop's drawn stickers for
	tools/preview/shop_golem_sheet.mjs (the toon renderer): every name in
	every image of IconAssets.StickerSheets (IconAssets.ShopGolems:
	golem_<Kind>, capsule_<Id>; IconAssets.ShopItems: podium, train,
	board_<Id>) built by PictureModels.build, exactly the model the shop's 3D
	picture shows (a Royal Egg golem in its egg costume, a Dragonforge golem
	in its limited gear, the Royal egg, the Dragonforge shard, the podium
	with its gold ore, the red locomotive, the Custom Hoverboard), with the
	picture's camera direction (`from`). One file: build/preview/golem_stickers.json
	  { sheets = { { name, file, id, cell, columns, order = { names } } },
	    models = { [name] = { from, parts, names } } }
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

-- each image's name in IconAssets (the tool's SHEETS picks images by it)
local sheetNames: { [any]: string } = {}
for key, value in IconAssets do
	if type(value) == "table" and table.find(IconAssets.StickerSheets, value) then
		sheetNames[value] = key
	end
end

local out = { sheets = {}, models = {} :: { [string]: any } }

for _, sheet in IconAssets.StickerSheets do
	local name = sheetNames[sheet]
	assert(name, "every sticker image is an IconAssets field")
	table.insert(out.sheets, {
		name = name,
		file = sheet.File,
		id = sheet.Id,
		cell = sheet.Cell,
		columns = sheet.Columns,
		order = sheet.Icons,
	})
	for _, picture in sheet.Icons do
		local model, from = PictureModels.build(picture)
		if not model then
			error("PictureModels.build has no model for " .. picture)
		end
		local scene = Export.collect(model)
		-- the parts' names, in Export.collect's order (the same walk and the same filter)
		local names = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				table.insert(names, d.Name)
			end
		end
		assert(#names == #scene.parts, picture .. ": the names follow the parts")
		out.models[picture] = { from = { from.X, from.Y, from.Z }, parts = scene.parts, names = names }
		print(string.format("Exported sticker model %s (%s): %d parts", picture, name, #scene.parts))
	end
end

fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/golem_stickers.json", serde.encode("json", out))
print("-> build/preview/golem_stickers.json")
