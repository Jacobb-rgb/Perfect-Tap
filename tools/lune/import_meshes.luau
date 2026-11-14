--[[
	The owner's Studio import -> MeshKit templates (docs/plans/MESHY_MODELS_PLAN.md).

	The owner imports every .glb of NAHRAJ_DO_ROBLOXU/3D_modely_<date> with Studio's 3D Importer
	(that uploads the meshes and textures under the owner's account) and saves the place. This tool
	finds each MeshPart named in Config/MeshCatalog (by its own name or the nearest ancestor's: the
	importer puts every glTF mesh in a Model of that name), checks that it was uploaded (an
	rbxassetid mesh and a texture), cleans it into an anchored template at the origin and writes

	  src/shared/Assets/MeshAssets.rbxm   Folder "MeshAssets" of MeshParts (Rojo syncs it into Shared)
	  src/shared/Config/MeshUpload.luau   Uploaded = true, Set = <set>

	Templates already in MeshAssets.rbxm stay for assets the new file lacks (a later set adds to it).
	An asset imported twice (a fixed file imported next to the old one) takes the later copy. A place
	saved by a current Studio is first rewritten by tools/meshy/unpack_place.mjs (Node 22+), since
	Lune 0.8.9 can't read its zstd chunks and Content properties.

	  lune run tools/lune/import_meshes.luau <hotovo.rbxl | .rbxm> [set name]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Loader = require("./lib/loader")

local path = process.args[1]
assert(path, "usage: lune run tools/lune/import_meshes.luau <hotovo.rbxl|.rbxm> [set name]")
local setName = process.args[2] or (path:match("(3D_modely_[%w%-_]+)") or "")

local root = process.cwd
Loader.init(root)
local Catalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")

local OUT = root .. "/src/shared/Assets/MeshAssets.rbxm"
local UPLOAD = root .. "/src/shared/Config/MeshUpload.luau"

local bytes = fs.readFile(path)
local tops: { any }
if path:lower():match("%.rbxlx?$") then
	local ok, game = pcall(roblox.deserializePlace, bytes)
	if not ok then
		-- a place from a current Studio (zstd chunks, Content properties): Lune 0.8.9 can't read it as
		-- it is, tools/meshy/unpack_place.mjs (Node 22+) rewrites it the way old rbx-dom reads
		local unpacked = root .. "/build/import_unpacked.rbxl"
		local result = process.spawn("node", { root .. "/tools/meshy/unpack_place.mjs", path, unpacked })
		assert(result.ok, "Lune can't read " .. path .. " (" .. tostring(game) .. ") and unpack_place.mjs failed: " .. result.stderr)
		print((string.gsub(result.stdout, "%s+$", "")))
		game = roblox.deserializePlace(fs.readFile(unpacked))
	end
	tops = game:GetChildren()
else
	tops = roblox.deserializeModel(bytes)
end

local function assetName(part: any): string?
	local node = part
	for _ = 1, 5 do
		if not node then
			break
		end
		if Catalog.Assets[node.Name] then
			return node.Name
		end
		node = node.Parent
	end
	return nil
end

local function meshIdOk(id: string): boolean
	return id:match("^rbxassetid://%d+") ~= nil or id:match("[?&]id=%d+") ~= nil
end

local function textureOf(part: any): string
	local sa = part:FindFirstChildOfClass("SurfaceAppearance")
	if sa and sa.ColorMap ~= "" then
		return sa.ColorMap
	end
	return part.TextureID
end

local found: { [string]: any } = {}
local doubled: { string } = {}
local notUploaded: { string } = {}
local noTexture: { string } = {}
local sizeOff: { string } = {}
local strays = 0

for _, top in tops do
	local list = top:GetDescendants()
	table.insert(list, top)
	for _, d in list do
		if d.ClassName ~= "MeshPart" then
			continue
		end
		local name = assetName(d)
		if not name then
			strays += 1
			continue
		end
		if not meshIdOk(d.MeshId) then
			table.insert(notUploaded, name .. " (" .. tostring(d.MeshId) .. ")")
			continue
		end
		if found[name] then
			-- imported again later (a fixed file next to the old one): the later copy wins
			table.insert(doubled, name)
		end
		found[name] = d
	end
end

for name, d in found do
	if textureOf(d) == "" then
		table.insert(noTexture, name)
	end
	local box = Catalog.Assets[name].Box
	local s = d.Size
	local function off(a: number, b: number): boolean
		return math.abs(a - b) > math.max(0.03 * b, 0.02)
	end
	if off(s.X, box.X) or off(s.Y, box.Y) or off(s.Z, box.Z) then
		table.insert(sizeOff, string.format("%s %.3f,%.3f,%.3f vs %.3f,%.3f,%.3f", name, s.X, s.Y, s.Z, box.X, box.Y, box.Z))
	end
end

--[[
	The importer's turn about Y (MeshKit: the template's attribute ImportYaw). Studio's 3D Importer
	turned every model half round on 2026-11-13 (glTF's +Z front -> Roblox's -Z front): the vertices
	and the parts' places alike. A floor's tiles show it: their places relative to each other are
	the catalog centres' turned by it. Without a floor in the file: the turn the kept templates
	carry, else Studio's usual 180.
]]
local function yawFromTiles(): (number?, number)
	local votes: { [number]: number } = {}
	local pairsSeen = 0
	local sets = {}
	for _, tiles in Catalog.Floors do
		table.insert(sets, tiles)
	end
	for _, tiles in Catalog.FloorsHD or {} do
		table.insert(sets, tiles)
	end
	for _, tiles in sets do
		local list = {}
		for _, name in tiles do
			if found[name] then
				table.insert(list, name)
			end
		end
		for i = 2, #list do
			local a, b = list[1], list[i]
			local dc = Catalog.Assets[b].Center - Catalog.Assets[a].Center
			local di = found[b].CFrame.Position - found[a].CFrame.Position
			if roblox.Vector3.new(dc.X, 0, dc.Z).Magnitude > 0.5 then
				local best, bestErr = 0, math.huge
				for _, yaw in { 0, 90, 180, 270 } do
					local turned = roblox.CFrame.Angles(0, math.rad(yaw), 0):VectorToWorldSpace(dc)
					local err = (turned - di).Magnitude
					if err < bestErr then
						best, bestErr = yaw, err
					end
				end
				if bestErr < 0.05 * dc.Magnitude + 0.01 then
					votes[best] = (votes[best] or 0) + 1
					pairsSeen += 1
				end
			end
		end
	end
	local yaw, most = nil, 0
	for value, n in votes do
		if n > most then
			yaw, most = value, n
		end
	end
	return yaw, pairsSeen
end

--[[
	How finely Roblox draws a template's clones. Automatic swaps in coarser versions of a mesh with
	distance: across a mine floor the diorama tiles' rock walls melted into blobs ("like warm
	marzipan", the owner 2026-11-14). The floors and the elevator tower always draw at full detail
	(about 160-300k triangles a floor, only one floor around a player at a time).
]]
local function fidelity(t: any)
	if string.match(t.Name, "^Floor_") or t.Name == "Prop_MineElevator" then
		t.RenderFidelity = roblox.Enum.RenderFidelity.Precise
	end
	-- and matte: a tile with only a TextureID draws with its Material's roughness, and Plastic gave
	-- the soft Meshy shapes a waxy sheen ("melted chocolate", 2026-11-14). (A tile with its own
	-- SurfaceAppearance, the sharper set, takes its roughness from that instead.)
	if string.match(t.Name, "^Floor_") then
		t.Material = roblox.Enum.Material.Concrete
	end
end

-- the templates: clean clones at the origin, anchored, nothing else inside but the SurfaceAppearance
local folder = roblox.Instance.new("Folder")
folder.Name = "MeshAssets"
local kept = 0
local keptYaw: number? = nil
if fs.isFile(OUT) then
	local old = roblox.deserializeModel(fs.readFile(OUT))[1]
	if old then
		for _, child in old:GetChildren() do
			if child.ClassName == "MeshPart" and not found[child.Name] and Catalog.Assets[child.Name] then
				fidelity(child)
				child.Parent = folder
				kept += 1
				local yaw = child:GetAttribute("ImportYaw")
				if type(yaw) == "number" then
					keptYaw = yaw
				end
			end
		end
	end
end
local importYaw, yawPairs = yawFromTiles()
if importYaw then
	print(string.format("the importer turned the models by %d degrees (from %d floor tile pairs)", importYaw, yawPairs))
else
	importYaw = keptYaw or 180
	print(string.format("no floor tiles in the file: the models take a turn of %d degrees (%s)", importYaw, if keptYaw then "the kept templates'" else "Studio's usual"))
end
local count = 0
for name, part in found do
	local t = part:Clone()
	for _, child in t:GetChildren() do
		if child.ClassName ~= "SurfaceAppearance" then
			child:Destroy()
		end
	end
	for key in t:GetAttributes() do
		t:SetAttribute(key, nil)
	end
	t.Name = name
	t.CFrame = roblox.CFrame.new()
	t.Anchored = true
	t.CanCollide = false
	t.CanQuery = false
	t.CanTouch = false
	t.CastShadow = true
	t.Locked = false
	t:SetAttribute("Asset", name)
	t:SetAttribute("ImportYaw", importYaw)
	fidelity(t)
	t.Parent = folder
	count += 1
end

local missing: { string } = {}
for name in Catalog.Assets do
	if not folder:FindFirstChild(name) then
		table.insert(missing, name)
	end
end
table.sort(missing)
table.sort(doubled)
table.sort(notUploaded)
table.sort(noTexture)
table.sort(sizeOff)

print(string.format("templates: %d new, %d kept, %d of %d catalog assets missing", count, kept, #missing, 0 + (function()
	local n = 0
	for _ in Catalog.Assets do
		n += 1
	end
	return n
end)()))
local function list(title: string, items: { string })
	if #items > 0 then
		print(title .. " (" .. #items .. "):")
		for _, item in items do
			print("  " .. item)
		end
	end
end
list("MISSING", missing)
list("NOT UPLOADED (skipped)", notUploaded)
list("NO TEXTURE", noTexture)
list("DOUBLED (the later import kept)", doubled)
list("SIZE NOT AS PROCESSED", sizeOff)
if strays > 0 then
	print(strays .. " other MeshParts in the file ignored")
end

if count + kept == 0 then
	print("nothing to write")
	process.exit(1)
end

if not fs.isDir(root .. "/src/shared/Assets") then
	fs.writeDir(root .. "/src/shared/Assets")
end
fs.writeFile(OUT, roblox.serializeModel({ folder }))
fs.writeFile(
	UPLOAD,
	"--!strict\n"
		.. "-- Written by tools/lune/import_meshes.luau: whether Shared/Assets/MeshAssets.rbxm holds the owner's\n"
		.. "-- uploaded meshes (MeshKit), and which processed set (NAHRAJ_DO_ROBLOXU/3D_modely_<date>) they came from.\n"
		.. "return {\n\tUploaded = true,\n\tSet = "
		.. string.format("%q", setName)
		.. ",\n}\n"
)
print("wrote " .. OUT .. " and " .. UPLOAD)
