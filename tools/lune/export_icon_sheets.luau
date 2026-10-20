--[[
	Writes the icon sprite sheet layout (src/shared/Config/IconAssets.luau) to
	build/preview/icon_sheets.json for tools/preview/icon_sheets.mjs.

	  lune run tools/lune/export_icon_sheets.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
Loader.init(process.cwd)

local IconAssets = Loader.requirePath("ReplicatedStorage.Shared.Config.IconAssets")
local out = { Cell = IconAssets.Cell, Columns = IconAssets.Columns, Sheets = {} }
for _, sheet in IconAssets.Sheets do
	table.insert(out.Sheets, { Name = sheet.Name, File = sheet.File, Icons = sheet.Icons })
end
fs.writeDir(process.cwd .. "/build/preview")
fs.writeFile(process.cwd .. "/build/preview/icon_sheets.json", serde.encode("json", out))
print("Exported " .. #out.Sheets .. " icon sheets")
