--[[
	Stand-in MeshKit templates for previews and specs (no upload): one MeshPart per MeshCatalog
	entry, sized to its Box, with the attribute Asset (the previews draw the processed .glb of that
	name) and Placeholder = true. Mounted at ReplicatedStorage.Shared.Assets.MeshAssets unless the
	owner's real templates are already there (force = true replaces them).

	  require("./lib/mesh_fakes")(Loader, force?, importYaw?)
	  require("./lib/mesh_fakes").unmount(Loader)
	importYaw: the stand-ins carry ImportYaw like a real upload (MeshKit turns their clones back).
]]

local roblox = require("@lune/roblox") :: any

local Fakes = {}

local function make(Loader: any, force: boolean?, importYaw: number?)
	local MeshKit = Loader.requirePath("ReplicatedStorage.Shared.Builders.MeshKit")
	local Catalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local shared = Loader.find("ReplicatedStorage.Shared")
	local holder = shared:FindFirstChild("Assets")
	if not force and holder and holder:FindFirstChild("MeshAssets") then
		return
	end
	local folder = roblox.Instance.new("Folder")
	folder.Name = "MeshAssets"
	for name, entry in Catalog.Assets do
		local p = roblox.Instance.new("MeshPart")
		p.Name = name
		p.Size = entry.Box
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p:SetAttribute("Asset", name)
		p:SetAttribute("Placeholder", true)
		if importYaw then
			p:SetAttribute("ImportYaw", importYaw)
		end
		p.Parent = folder
	end
	Loader.mount("ReplicatedStorage.Shared.Assets.MeshAssets", folder)
	MeshKit.reset()
end

function Fakes.unmount(Loader: any)
	Loader.mount("ReplicatedStorage.Shared.Assets.MeshAssets", nil)
	Loader.requirePath("ReplicatedStorage.Shared.Builders.MeshKit").reset()
end

return setmetatable(Fakes, {
	__call = function(_, Loader: any, force: boolean?, importYaw: number?)
		make(Loader, force, importYaw)
	end,
})
