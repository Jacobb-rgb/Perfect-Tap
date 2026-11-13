-- The owner's uploaded models as they ship (Shared/Assets/MeshAssets.rbxm, written by
-- tools/lune/import_meshes.luau from his Studio import). The test runner sets them aside
-- (Loader.RealMeshAssets) so every other spec builds the parts looks or mounts stand-ins.
return function(T, Loader)
	local Catalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local MeshUpload = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshUpload")
	local real = Loader.RealMeshAssets

	-- catalog assets not uploaded yet (owner 2026-11-13: the three epic ores he sent last and the open
	-- museum; his next import of NAHRAJ_DO_ROBLOXU/3D_doplnit_7_souboru_2026-11-13 brings them):
	-- those ores and the museum keep the parts look until then
	local WAITING = {
		Ore_CrystalRose = true,
		Ore_CrystalRose_Low = true,
		Ore_GalaxyStone = true,
		Ore_GalaxyStone_Low = true,
		Ore_StormPearl = true,
		Ore_StormPearl_Low = true,
		Prop_MuseumOpen = true, -- the museum without its painted glass boxes (the game's glass instead)
	}

	local function uploaded(id: any): boolean
		return type(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil
	end

	T.test("MeshAssets: the uploaded templates are catalog models, uploaded, textured and as processed", function()
		T.eq(real ~= nil, MeshUpload.Uploaded == true, "MeshUpload.Uploaded says whether MeshAssets.rbxm is in")
		if not real then
			return
		end
		T.truthy(type(MeshUpload.Set) == "string" and MeshUpload.Set ~= "", "the processed set they came from")
		local count = 0
		for _, t in real:GetChildren() do
			count += 1
			local entry = Catalog.Assets[t.Name]
			T.truthy(entry ~= nil, t.Name .. " is in the catalog")
			T.eq(t.ClassName, "MeshPart", t.Name .. " is a MeshPart")
			T.truthy(uploaded(t.MeshId), t.Name .. " is uploaded (" .. tostring(t.MeshId) .. ")")
			local look = t:FindFirstChildOfClass("SurfaceAppearance")
			T.truthy(uploaded(if look then look.ColorMap else t.TextureID), t.Name .. " has its texture")
			T.eq(t:GetAttribute("Asset"), t.Name, t.Name .. " Asset attribute (the previews)")
			-- Studio's importer turned it (MeshKit turns the clones back; import_meshes found the turn)
			local yaw = t:GetAttribute("ImportYaw")
			T.truthy(type(yaw) == "number" and yaw % 90 == 0, t.Name .. " carries the import's turn")
			T.truthy(t.Anchored and not t.CanCollide and not t.CanQuery and not t.CanTouch, t.Name .. " a clean template")
			for _, child in t:GetChildren() do
				T.eq(child.ClassName, "SurfaceAppearance", t.Name .. " holds nothing but its SurfaceAppearance")
			end
			-- MeshKit fits a template into the catalog's box: a mesh of another size would stretch
			local box, size = entry.Box, t.Size
			for _, axis in { "X", "Y", "Z" } do
				local want, got = box[axis], size[axis]
				T.truthy(math.abs(got - want) <= math.max(0.03 * want, 0.02), `{t.Name} {axis}: {got} vs the catalog's {want}`)
			end
		end
		T.truthy(count > 0, "templates")
		for name in Catalog.Assets do
			T.truthy(real:FindFirstChild(name) ~= nil or WAITING[name], name .. " is uploaded (or waits for his next import)")
		end
	end)
end
