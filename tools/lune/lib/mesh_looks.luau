--[[
	How the owner's uploaded models look when Roblox can't draw their textures, and how their PBR
	looks ship (tools/lune/mesh_looks.luau, tools/lune/import_meshes.luau).

	1. Fallback colour. A template's own Color is what Roblox draws while its texture can't show (an
	   image not processed yet, a failed upload, a slow phone still loading). Studio's importer leaves
	   it at the default grey (163, 162, 165), which is how half the mines looked grey or, in their
	   bright light, white (owner 2026-11-15). Every template takes its texture's average colour
	   (tools/meshy/albedo.json, from tools/meshy/glb_albedo.py). With the texture drawn, it doesn't
	   show: an opaque TextureID covers it and a SurfaceAppearance doesn't use it.

	2. A SurfaceAppearance needs its texture pack (tools/meshy/texture_packs.mjs explains it). A
	   template whose maps have a known pack keeps its SurfaceAppearance (the pack goes into each
	   finished place file). One without (the sharper floors: their Studio import was never saved, so
	   their packs are lost) draws its colour map as a classic TextureID instead: that one never needs
	   a pack, and it shows in Studio and in the published game alike.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox") :: any

local MeshLooks = {}

MeshLooks.Albedo = "tools/meshy/albedo.json"
MeshLooks.Packs = "tools/meshy/texture_packs.json"
-- what Studio's importer leaves a MeshPart's Color at
MeshLooks.DefaultGrey = { 163, 162, 165 }

local function json(path: string): { [string]: any }
	if not fs.isFile(path) then
		return {}
	end
	return serde.decode("json", fs.readFile(path))
end

function MeshLooks.load(root: string): ({ [string]: { number } }, { [string]: string })
	return json(root .. "/" .. MeshLooks.Albedo), json(root .. "/" .. MeshLooks.Packs)
end

local function idOf(s: string?): string
	return if type(s) == "string" then string.match(s, "(%d+)%s*$") or "" else ""
end

-- The table key of a SurfaceAppearance: its maps' asset ids, "ColorMap|NormalMap|RoughnessMap|MetalnessMap".
function MeshLooks.key(sa: any): string
	return table.concat({ idOf(sa.ColorMap), idOf(sa.NormalMap), idOf(sa.RoughnessMap), idOf(sa.MetalnessMap) }, "|")
end

export type Result = { Colour: boolean, ToTexture: boolean }

-- Applies both rules to one template; says what it did.
function MeshLooks.apply(t: any, albedo: { [string]: { number } }, packs: { [string]: string }): Result
	local result = { Colour = false, ToTexture = false }
	local c = albedo[t.Name]
	if c then
		t.Color = roblox.Color3.new(c[1], c[2], c[3])
		result.Colour = true
	end
	local sa = t:FindFirstChildOfClass("SurfaceAppearance")
	if sa and not packs[MeshLooks.key(sa)] and sa.ColorMap ~= "" then
		t.TextureID = sa.ColorMap
		sa:Destroy()
		result.ToTexture = true
	end
	return result
end

return MeshLooks
