--[[
	Owner test place for the studded style (docs/STUD_STYLE.md): copies a baked
	place, switches the style on (Workspace attributes StudStyle = true,
	StudStyleLook = Classic | Custom) and adds the Studio-only script
	tools/studs/TEST_Vystupky.luau (attributes for the uploaded picture ids).

	lune run tools/lune/make_stud_test_place.luau build/TerraForge.rbxl <out.rbxl> Classic|Custom
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local src, dst, look = process.args[1], process.args[2], process.args[3] or "Classic"
assert(src and dst, "usage: lune run tools/lune/make_stud_test_place.luau <in.rbxl> <out.rbxl> Classic|Custom")
assert(look == "Classic" or look == "Custom", "look: Classic or Custom")
local game = roblox.deserializePlace(fs.readFile(src))
local workspace = game:GetService("Workspace")
workspace:SetAttribute("StudStyle", true)
workspace:SetAttribute("StudStyleLook", look)
local sss = game:GetService("ServerScriptService")
local old = sss:FindFirstChild("TEST_Vystupky")
if old then
	old:Destroy()
end
local script = roblox.Instance.new("Script")
script.Name = "TEST_Vystupky"
script.Source = fs.readFile(process.cwd .. "/tools/studs/TEST_Vystupky.luau")
for _, key in { "ColorMap", "NormalMap", "RoughnessMap" } do
	script:SetAttribute(key, "")
end
script.Parent = sss
fs.writeFile(dst, roblox.serializePlace(game))
print(`wrote {dst} (stud style {look})`)
