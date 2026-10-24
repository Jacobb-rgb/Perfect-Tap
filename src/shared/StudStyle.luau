--[[
	The studded style: puts classic Roblox studs on the map's parts without new
	parts or textures, and takes them off again exactly (StudStyleConfig, docs/STUD_STYLE.md).

	How a part gets studs (StudStyleConfig.Look):
	- Classic: Roblox's own square studs. SurfaceType.Studs on every face (Inlet
	  under it); a part of a Classic.Convert material (every stud material)
	  turns Plastic (surfaces only show on Plastic) and gets its own material's
	  PhysicalProperties, so it slides and weighs the same. A material left out
	  of Classic.Convert takes the custom studs below.
	- Custom: BasePart.MaterialVariant = "TFStuds", our stud MaterialVariant for
	  the part's own base material (StudStyle.ensureVariants, one per material in
	  MaterialService.TFStudStyle). Material, Color and physics stay.
	Position, Size, CFrame, Anchored, CanCollide, CanTouch, CanQuery, Color and
	Transparency are never written.

	Every restyled part carries the attribute "StudStyle" with what it was:
	  "C;<Material>;<Top>,<Bottom>,<Front>,<Back>,<Left>,<Right>;<1 = physics set>"
	  "V;<the MaterialVariant it had>"
	A part with the attribute is never restyled twice; restorePart / restoreTree
	put back exactly that and remove the attribute.

	Who calls it: StudStyleController (every client restyles what streams to it,
	so the server's map is never touched), StudStyleService (the variants), the
	preview export (STUD_STYLE=...), and Studio's command bar for a quick look:
	  local S = require(game.ReplicatedStorage.Shared.StudStyle)
	  S.ensureVariants(game.MaterialService) S.applyTree(workspace, "Classic")
	  S.restoreTree(workspace) S.removeVariants(game.MaterialService) -- before saving
]]

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StudStyleConfig = require(Shared.Config.StudStyleConfig)

local StudStyle = {}

StudStyle.Attribute = "StudStyle"
StudStyle.VariantName = "TFStuds"
StudStyle.FolderName = "TFStudStyle"

-- The face order of the "C" record.
local FACES = { "Top", "Bottom", "Front", "Back", "Left", "Right" }

-- Materials that never get studs, whatever the config says.
local NEVER = { Neon = true, Glass = true, ForceField = true, Foil = true, Water = true, Air = true }

local SHAPE_OF_CLASS = { WedgePart = "Wedge", CornerWedgePart = "CornerWedge" }

-- Per pass: the verdict for each model / folder above the parts ("" = fine).
local ancestorCache: { [Instance]: string } = {}

local function enumItem(enum: any, name: string): any
	local ok, item = pcall(function()
		return enum[name]
	end)
	return if ok then item else nil
end

local function nameSkip(name: string): string?
	for _, pattern in StudStyleConfig.SkipNames do
		if string.find(name, pattern) then
			return "name " .. pattern
		end
	end
	return nil
end

local function flagged(instance: Instance): boolean
	return instance:HasTag(StudStyleConfig.SkipTag) or instance:GetAttribute(StudStyleConfig.SkipTag) == true
end

-- Why a model / folder (and everything in it) keeps its look, or "" when it is fine.
local function ancestorVerdict(instance: Instance): string
	local cached = ancestorCache[instance]
	if cached then
		return cached
	end
	local verdict = ""
	local parent = instance.Parent
	if instance:IsA("Accoutrement") or instance:IsA("Tool") then
		verdict = "worn"
	elseif instance:IsA("Camera") then
		verdict = "camera"
	elseif instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") then
		verdict = "character"
	elseif flagged(instance) then
		verdict = "tagged"
	elseif parent and parent:IsA("Workspace") and StudStyleConfig.SkipRoots[instance.Name] then
		verdict = "root " .. instance.Name
	else
		verdict = nameSkip(instance.Name) or ""
	end
	if verdict == "" and parent and not parent:IsA("Workspace") and parent ~= game then
		verdict = ancestorVerdict(parent)
	end
	ancestorCache[instance] = verdict
	return verdict
end

-- A sign: a SurfaceGui with words or a picture on the part, or an empty one (a
-- board filled in later); a SurfaceGui of plain frames, like the plot plates'
-- tile seams, keeps its studs under it.
local function showsPicture(part: BasePart): boolean
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceGui") then
			-- empty: a board a script fills in later (the SKY EGG odds board)
			if #child:GetChildren() == 0 then
				return true
			end
			for _, d in child:GetDescendants() do
				if
					d:IsA("TextLabel")
					or d:IsA("TextButton")
					or d:IsA("TextBox")
					or d:IsA("ImageLabel")
					or d:IsA("ImageButton")
					or d:IsA("ViewportFrame")
				then
					return true
				end
			end
		end
	end
	return false
end

-- Forget the cached ancestor verdicts (start of every pass / batch).
function StudStyle.clearCache()
	table.clear(ancestorCache)
end

--[[
	Why `part` must keep its own look, or nil when it is suitable for studs.
	Suitable: a Part / WedgePart / CornerWedgePart (no meshes, unions, trusses)
	of a block, wedge or cylinder shape, of a stud material, opaque, not a
	mirror, big enough (middle size >= MinSide, longest >= MinLength), with no
	sign (a SurfaceGui with words or pictures, or an empty one), decal,
	texture, surface appearance or mesh on it and no custom material of
	its own, and not on a character, a worn accessory or tool, the camera, in a
	skipped root (Nodes, Items, Debris), under a skipped name (clouds, water),
	one of the SkipParts (the podium rims) or tagged NoStuds.
]]
function StudStyle.skipReason(part: BasePart): string?
	if not StudStyleConfig.Classes[part.ClassName] then
		return "class " .. part.ClassName
	end
	local shape = SHAPE_OF_CLASS[part.ClassName] or (part :: Part).Shape.Name
	if not StudStyleConfig.Shapes[shape] then
		return "shape " .. shape
	end
	local material = part.Material.Name
	if NEVER[material] or not StudStyleConfig.Materials[material] then
		return "material " .. material
	end
	if part.Transparency > StudStyleConfig.MaxTransparency then
		return "transparent"
	end
	if part.Reflectance > StudStyleConfig.MaxReflectance then
		return "reflective"
	end
	local size = part.Size
	local a, b, c = size.X, size.Y, size.Z
	local longest = math.max(a, b, c)
	local middle = a + b + c - longest - math.min(a, b, c)
	if longest < StudStyleConfig.MinLength or middle < StudStyleConfig.MinSide then
		return "small"
	end
	if part.MaterialVariant ~= "" and part.MaterialVariant ~= StudStyle.VariantName then
		return "own material"
	end
	if part:FindFirstChildWhichIsA("Decal") or part:FindFirstChildWhichIsA("SurfaceAppearance") or showsPicture(part) then
		return "picture"
	end
	-- a SpecialMesh / BlockMesh reshapes the part and Roblox draws no surfaces on it
	if part:FindFirstChildWhichIsA("DataModelMesh") then
		return "mesh"
	end
	if flagged(part) then
		return "tagged"
	end
	local name = nameSkip(part.Name)
	if name then
		return name
	end
	local parent = part.Parent
	if parent then
		for _, rule in StudStyleConfig.SkipParts do
			if string.find(part.Name, rule.Name) and string.find(parent.Name, rule.Parent) then
				return "part " .. part.Name
			end
		end
	end
	if parent and not parent:IsA("Workspace") and parent ~= game then
		local verdict = ancestorVerdict(parent)
		if verdict ~= "" then
			return verdict
		end
	end
	return nil
end

-- A look from a config value or an attribute (anything but "Custom" is Classic).
function StudStyle.look(value: any): StudStyleConfig.Look
	return if value == "Custom" then "Custom" else "Classic"
end

--[[
	Can parts take the custom stud material? Yes when this side's config has
	the pictures (StudStyleConfig.customReady), or when the server already made
	the stud materials (StudStyleService: clients learn it from MaterialService,
	so ids set on the server alone, like a Studio test script's, are enough).
]]
function StudStyle.customReady(): boolean
	return StudStyleConfig.customReady() or MaterialService:FindFirstChild(StudStyle.FolderName) ~= nil
end

-- Does this part's material take Roblox's own studs in the Classic look?
local function classicMaterial(material: string): boolean
	return material == "Plastic" or StudStyleConfig.Classic.Convert[material] == true
end

-- Returns false (and changes nothing) when the material's own physics cannot be
-- read, so a part never slides or weighs differently.
local function applyClassic(part: BasePart): boolean
	local material = part.Material
	local pinned: PhysicalProperties? = nil
	local own: PhysicalProperties? = part.CustomPhysicalProperties
	if material ~= Enum.Material.Plastic and own == nil then
		-- the material's own physics, so the part slides and weighs as before
		local ok, physics = pcall(PhysicalProperties.new, material)
		if not ok then
			return false
		end
		pinned = physics
	end
	local faces = table.create(#FACES)
	local source: any = part
	for i, face in FACES do
		faces[i] = (source[face .. "Surface"] :: EnumItem).Name
	end
	if pinned then
		part.CustomPhysicalProperties = pinned
	end
	if material ~= Enum.Material.Plastic then
		part.Material = Enum.Material.Plastic
	end
	local target: any = part
	for _, face in FACES do
		local surface = enumItem(Enum.SurfaceType, StudStyleConfig.Classic.Faces[face] or "Studs")
		if surface then
			target[face .. "Surface"] = surface
		end
	end
	part:SetAttribute(StudStyle.Attribute, `C;{material.Name};{table.concat(faces, ",")};{if pinned then "1" else "0"}`)
	return true
end

local function applyVariant(part: BasePart)
	local previous = part.MaterialVariant
	part.MaterialVariant = StudStyle.VariantName
	part:SetAttribute(StudStyle.Attribute, "V;" .. previous)
end

--[[
	Gives one part studs in `look` (StudStyleConfig.Look by default). Returns
	true when it changed the part: false for an unsuitable part, a part that
	already has studs (any look), or a material with no stud look yet (no
	uploaded pictures for the custom studs).
]]
function StudStyle.applyPart(part: BasePart, look: StudStyleConfig.Look?): boolean
	if part:GetAttribute(StudStyle.Attribute) ~= nil then
		return false
	end
	if StudStyle.skipReason(part) then
		return false
	end
	local wanted = look or StudStyle.look(StudStyleConfig.Look)
	if wanted == "Classic" and classicMaterial(part.Material.Name) then
		return applyClassic(part)
	end
	if StudStyle.customReady() then
		applyVariant(part)
		return true
	end
	return false
end

-- Puts one restyled part back the way it was. Returns true if it had studs.
function StudStyle.restorePart(part: BasePart): boolean
	local record = part:GetAttribute(StudStyle.Attribute)
	if type(record) ~= "string" then
		return false
	end
	local kind = string.sub(record, 1, 2)
	if kind == "C;" then
		local fields = string.split(record, ";")
		local material = enumItem(Enum.Material, fields[2] or "")
		-- another script may have changed it since (a glow flash): then that stays
		if material and part.Material == Enum.Material.Plastic then
			part.Material = material
		end
		local faces = string.split(fields[3] or "", ",")
		local target: any = part
		for i, face in FACES do
			target[face .. "Surface"] = enumItem(Enum.SurfaceType, faces[i] or "Smooth") or Enum.SurfaceType.Smooth
		end
		if fields[4] == "1" then
			target.CustomPhysicalProperties = nil
		end
	elseif kind == "V;" then
		if part.MaterialVariant == StudStyle.VariantName then
			part.MaterialVariant = string.sub(record, 3)
		end
	end
	part:SetAttribute(StudStyle.Attribute, nil)
	return true
end

local function eachPart(root: Instance, fn: (BasePart) -> ())
	if root:IsA("BasePart") then
		fn(root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

-- Gives every suitable part under `root` (and `root` itself) studs at once.
-- Returns how many parts changed.
function StudStyle.applyTree(root: Instance, look: StudStyleConfig.Look?): number
	StudStyle.clearCache()
	local count = 0
	eachPart(root, function(part)
		if StudStyle.applyPart(part, look) then
			count += 1
		end
	end)
	StudStyle.clearCache()
	return count
end

-- Takes the studs off every part under `root` that has them. Returns how many.
function StudStyle.restoreTree(root: Instance): number
	local count = 0
	eachPart(root, function(part)
		if StudStyle.restorePart(part) then
			count += 1
		end
	end)
	return count
end

--[[
	Restyles `root`'s parts now and every part added under it later (streamed
	in, built, placed), about StudStyleConfig.BudgetMs of each frame (at
	least MinPerFrame parts) so a big stream-in never stalls a frame. Returns a function that stops watching (it does not take
	the studs off: restoreTree does).
]]
-- The signal watch listens to for new parts (the specs hand in their own).
function StudStyle.added(root: Instance): RBXScriptSignal
	return root.DescendantAdded
end

function StudStyle.watch(root: Instance, look: StudStyleConfig.Look?): () -> ()
	local pending: { BasePart } = {}
	local scheduled = false
	local alive = true

	local function flush()
		StudStyle.clearCache()
		-- one budget across the batches: parts queued meanwhile wait for the next frame too
		local frameStart = os.clock()
		local done = 0
		while alive and #pending > 0 do
			local batch = pending
			pending = {}
			for _, part in batch do
				if not alive then
					break
				end
				-- a part that left in the meantime (streamed out, destroyed) is skipped
				if part.Parent and part:IsDescendantOf(root) then
					StudStyle.applyPart(part, look)
				end
				done += 1
				if done % StudStyleConfig.MinPerFrame == 0 and os.clock() - frameStart >= StudStyleConfig.BudgetMs / 1000 then
					task.wait()
					StudStyle.clearCache()
					frameStart = os.clock()
				end
			end
		end
		StudStyle.clearCache()
		scheduled = false
	end

	local function queue(part: BasePart)
		table.insert(pending, part)
		if not scheduled then
			scheduled = true
			-- deferred: a builder sets a new part's look after parenting it
			task.defer(flush)
		end
	end

	eachPart(root, queue)
	local connection = StudStyle.added(root):Connect(function(d: Instance)
		if d:IsA("BasePart") then
			queue(d)
		end
	end)
	return function()
		alive = false
		connection:Disconnect()
	end
end

--[[
	Makes the custom stud MaterialVariants in `materialService` (one per stud
	material, all named VariantName, in the folder FolderName) when the stud
	pictures are uploaded (StudStyleConfig.customReady). Run where they
	replicate from: the server. Returns the folder, or nil when not ready.
	Running it again updates the variants in place (no duplicates).
]]
function StudStyle.ensureVariants(materialService: Instance): Folder?
	if not StudStyleConfig.customReady() then
		return nil
	end
	local folder = materialService:FindFirstChild(StudStyle.FolderName) :: Folder?
	if not folder then
		local made = Instance.new("Folder")
		made.Name = StudStyle.FolderName
		made:SetAttribute(StudStyle.Attribute, true)
		made.Parent = materialService
		folder = made
	end
	assert(folder, "folder")
	local existing: { [string]: MaterialVariant } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("MaterialVariant") then
			existing[child.BaseMaterial.Name] = child
		end
	end
	local assets = StudStyleConfig.Assets
	local function asset(id: number): string
		return if id > 0 then "rbxassetid://" .. id else ""
	end
	for name, on in StudStyleConfig.Materials do
		local material = enumItem(Enum.Material, name)
		if on and material and not NEVER[name] then
			local variant = existing[name] or Instance.new("MaterialVariant")
			variant.Name = StudStyle.VariantName
			variant.BaseMaterial = material
			variant.StudsPerTile = StudStyleConfig.StudsPerTile
			variant.MaterialPattern = Enum.MaterialPattern.Regular
			variant.ColorMap = asset(assets.ColorMap)
			variant.NormalMap = asset(assets.NormalMap)
			variant.RoughnessMap = asset(assets.RoughnessMap)
			variant:SetAttribute(StudStyle.Attribute, true)
			variant.Parent = folder
		end
	end
	return folder
end

-- Removes the custom stud MaterialVariants (parts that still name them fall back to their own material).
function StudStyle.removeVariants(materialService: Instance)
	local folder = materialService:FindFirstChild(StudStyle.FolderName)
	if folder then
		folder:Destroy()
	end
end

return StudStyle
