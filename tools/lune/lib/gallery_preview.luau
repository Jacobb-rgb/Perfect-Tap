--[[
	Preview scene "blaster_gallery" (tools/lune/export_scene.luau): the world
	with THE GREAT FORGE's blaster gallery (src/server/World/Lobby/Plaza/
	BlasterGallery, built by GreatForge.luau). Shots:
	tools/preview/blaster_gallery_shots.json (the hero and spawn views, the
	stairs, inside the hall).
]]

local Gallery = {}

function Gallery.build(Loader: any, parent: any)
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	WorldBuilder.build(parent)
	local gallery = parent:FindFirstChild("BlasterGallery", true)
	local parts = 0
	if gallery then
		for _, d in gallery:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	print(string.format("[blaster_gallery] gallery %d parts", parts))
	return gallery
end

return Gallery
