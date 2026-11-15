--[[
	Applies tools/lune/lib/mesh_looks.luau to the templates already in src/shared/Assets/MeshAssets.rbxm
	(import_meshes.luau does the same for every new import): each template's fallback colour, and
	the sharper floors' colour maps as TextureIDs (their texture packs were never saved).

	  lune run tools/lune/mesh_looks.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local MeshLooks = require("./lib/mesh_looks")

local root = process.cwd
local OUT = root .. "/src/shared/Assets/MeshAssets.rbxm"
local albedo, packs = MeshLooks.load(root)

local tops = roblox.deserializeModel(fs.readFile(OUT))
local folder = tops[1]
assert(folder and folder.Name == "MeshAssets", "MeshAssets.rbxm holds one Folder MeshAssets")

local coloured, textured, noAlbedo = 0, {}, {}
for _, t in folder:GetChildren() do
	if t.ClassName ~= "MeshPart" then
		continue
	end
	local r = MeshLooks.apply(t, albedo, packs)
	if r.Colour then
		coloured += 1
	else
		table.insert(noAlbedo, t.Name)
	end
	if r.ToTexture then
		table.insert(textured, t.Name)
	end
end
table.sort(textured)
table.sort(noAlbedo)
print(string.format("%d templates: %d take their texture's colour, %d draw their colour map as a TextureID", #folder:GetChildren(), coloured, #textured))
if #noAlbedo > 0 then
	print("NO ALBEDO (run tools/meshy/glb_albedo.py on their .glb): " .. table.concat(noAlbedo, ", "))
end
fs.writeFile(OUT, roblox.serializeModel(tops))
print("wrote " .. OUT)
