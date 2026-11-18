-- The owner's uploaded models as they ship (Shared/Assets/MeshAssets.rbxm, written by
-- tools/lune/import_meshes.luau from his Studio import). The test runner sets them aside
-- (Loader.RealMeshAssets) so every other spec builds the parts looks or mounts stand-ins.
return function(T, Loader)
	local Catalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local MeshUpload = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshUpload")
	local real = Loader.RealMeshAssets
	local roblox = require("@lune/roblox") :: any

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
			-- the floors and the elevator tower at full detail from afar (Automatic melted the walls)
			if string.match(t.Name, "^Floor_") or t.Name == "Prop_MineElevator" then
				T.eq(t.RenderFidelity, roblox.Enum.RenderFidelity.Precise, t.Name .. " draws at full detail")
			end
			-- the floors matte (Plastic's sheen made them look melted)
			if string.match(t.Name, "^Floor_") then
				T.eq(t.Material, roblox.Enum.Material.Concrete, t.Name .. " matte")
			end
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
		-- (owner 2026-11-15: grey and white models) every template shows its texture's own colour while
		-- the texture can't draw, never Studio's default grey; a SurfaceAppearance only ships with its
		-- texture pack (tools/meshy/texture_packs.mjs puts it in every place file), else its colour map
		-- draws as a TextureID (tools/lune/lib/mesh_looks.luau)
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		local packs = serde.decode("json", fs.readFile("tools/meshy/texture_packs.json"))
		local function id(s: string): string
			return string.match(s, "(%d+)%s*$") or ""
		end
		for _, t in real:GetChildren() do
			local c = t.Color
			local grey = math.floor(c.R * 255 + 0.5) == 163 and math.floor(c.G * 255 + 0.5) == 162 and math.floor(c.B * 255 + 0.5) == 165
			T.truthy(not grey, t.Name .. " has its fallback colour (not the importer's grey)")
			local look = t:FindFirstChildOfClass("SurfaceAppearance")
			if look then
				local key = table.concat({ id(look.ColorMap), id(look.NormalMap), id(look.RoughnessMap), id(look.MetalnessMap) }, "|")
				T.truthy(packs[key] ~= nil, t.Name .. "'s SurfaceAppearance has a known texture pack")
			end
		end
		-- a floor's older tile sets stay out once a newer one is in whole (MineFloors.floorTiles never
		-- builds them; integrator review 2026-11-17: 119 of them loaded on every client)
		local superseded: { [string]: boolean } = {}
		for id, first in Catalog.Floors do
			local inUse = false
			for _, tiles in { Catalog.FloorsNext[id] or {}, Catalog.FloorsHD[id] or {}, first } do
				local whole = #tiles > 0
				for _, name in tiles do
					whole = whole and real:FindFirstChild(name) ~= nil
					superseded[name] = inUse or nil
				end
				inUse = inUse or whole
			end
		end
		for name in Catalog.Assets do
			if superseded[name] then
				T.eq(real:FindFirstChild(name), nil, name .. " stays out (a newer set of its floor is in)")
			else
				-- (the sharper floors, NAHRAJ_DO_ROBLOXU/3D_modely_2026-11-14_ostre_patra, wait for his import
				-- too: MineFloors.floorTiles keeps the first set until every one of a floor's is in)
				local waiting = WAITING[name] or string.match(name, "^Floor_%a+HD_%d+$") ~= nil
				T.truthy(real:FindFirstChild(name) ~= nil or waiting, name .. " is uploaded (or waits for his next import)")
			end
		end
	end)

	-- Every MeshPart of a binary model file, in the file's order: its CollisionFidelity value and the
	-- size of its collision hull (PhysicalConfigData), from the chunks tools/meshy/strip_hulls.mjs
	-- writes uncompressed (Lune can read neither property). nil without them.
	local function meshHulls(bytes: string): ({ number }?, { number }?)
		local function u32s(at: number, n: number): { number }
			local out = {}
			for i = 0, n - 1 do
				out[i + 1] = string.byte(bytes, at + i) * 16777216
					+ string.byte(bytes, at + n + i) * 65536
					+ string.byte(bytes, at + 2 * n + i) * 256
					+ string.byte(bytes, at + 3 * n + i)
			end
			return out
		end
		local modes: { number }? = nil
		local hullIndex: { number }? = nil
		local shared: { number }? = nil
		local off = 33
		while off < #bytes do
			local name = string.sub(bytes, off, off + 3)
			local packed, size = string.unpack("<I4I4", bytes, off + 4)
			local start = off + 16
			off = start + (if packed > 0 then packed else size)
			if packed == 0 and name == "PROP" then
				local len = string.unpack("<I4", bytes, start + 4)
				local prop = string.sub(bytes, start + 8, start + 7 + len)
				local at = start + 9 + len
				if prop == "CollisionFidelity" then
					modes = u32s(at, (off - at) // 4)
				elseif prop == "PhysicalConfigData" then
					hullIndex = u32s(at, (off - at) // 4)
				end
			elseif packed == 0 and name == "SSTR" then
				local count = string.unpack("<I4", bytes, start + 4)
				local list = {}
				local p = start + 8
				for i = 1, count do
					local n = string.unpack("<I4", bytes, p + 16)
					list[i] = n
					p += 20 + n
				end
				shared = list
			end
		end
		if not modes or not hullIndex or not shared then
			return nil, nil
		end
		local hulls = {}
		for i, index in hullIndex do
			hulls[i] = shared[index + 1]
		end
		return modes, hulls
	end

	T.test("MeshAssets: only the templates that collide carry a collision hull", function()
		-- (integrator review 2026-11-17: the file sent every client ~4.7 MB of hulls at join; only
		-- RockBuilder's rocks and Diorama.meshFill's mossy cliff walls collide, everything else is a look
		-- or a click target its box will do for)
		if not real then
			return
		end
		local fs = require("@lune/fs")
		local bytes = fs.readFile("src/shared/Assets/MeshAssets.rbxm")
		T.truthy(#bytes < 1.5e6, `MeshAssets.rbxm stays small ({#bytes} bytes; a hull for every template made it 4.7 MB)`)
		local colliding, total = 0, 0
		for _, t in real:GetChildren() do
			total += 1
			if string.match(t.Name, "^Rock_") or t.Name == "Prop_MossyCliff" then
				colliding += 1
			end
		end
		local modes, hulls = meshHulls(bytes)
		T.truthy(modes and hulls and #modes == total and #hulls == total, "every template's collision fidelity and hull")
		local boxes, kept = 0, 0
		for i = 1, total do
			local mode, hull = (modes :: { number })[i], (hulls :: { number })[i]
			if mode == 2 then -- Box
				boxes += 1
				T.eq(hull, 0, `template {i}: a Box carries no hull`)
			else
				-- (integrator review 2026-11-18) the ones kept for colliding still carry theirs
				T.eq(mode, 0, `template {i}: Default fidelity or Box`)
				T.truthy(hull ~= nil and hull > 0, `template {i}: a colliding template keeps its hull`)
				kept += 1
			end
		end
		T.eq(boxes, total - colliding, "every template that never collides is CollisionFidelity Box")
		T.eq(kept, colliding, "the rocks and the mossy cliff keep their hulls")
	end)
end
