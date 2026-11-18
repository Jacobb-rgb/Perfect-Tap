--[[
	What ships of the owner's mesh templates (Shared/Assets/MeshAssets.rbxm; integrator review
	2026-11-17: it sent every client ~4.7 MB of collision hulls at join): only the templates whose
	clones collide keep their collision hull (`collides`), every other one is CollisionFidelity Box
	without its hull. Lune can't write that (it writes no CollisionFidelity and can't clear a
	SharedString), tools/meshy/strip_hulls.mjs does: every tool that writes MeshAssets.rbxm with Lune
	(import_meshes.luau, mesh_looks.luau) runs MeshStrip.run right after it, as its last write.
]]

local process = require("@lune/process")

local MeshStrip = {}

-- The templates whose clones collide or answer raycasts by their shape (RockBuilder's Rock1,
-- Diorama.meshFill's walls); every other clone is a look only (or a click target, where its box
-- will do: the ore items) and needs no collision hull.
function MeshStrip.collides(name: string): boolean
	return string.match(name, "^Rock_") ~= nil or name == "Prop_MossyCliff"
end

-- Strips `file` (just written by Lune from `folder`, the MeshAssets Folder) in place; errors when
-- strip_hulls.mjs fails (a colliding template without a hull fails it too).
function MeshStrip.run(root: string, file: string, folder: any)
	local args = { root .. "/tools/meshy/strip_hulls.mjs", "strip", file }
	for _, t in folder:GetChildren() do
		if MeshStrip.collides(t.Name) then
			table.insert(args, t.Name)
		end
	end
	local result = process.spawn("node", args)
	assert(result.ok, "strip_hulls.mjs failed: " .. result.stdout .. result.stderr)
	print((string.gsub(result.stdout, "%s+$", "")))
end

return MeshStrip
