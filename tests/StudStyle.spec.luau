--[[
	The studded style (Shared/StudStyle, StudStyleConfig): which parts are
	suitable, the Classic and Custom looks change only the look (never the
	position, size, colour or collision), a second run changes nothing, the
	restore puts every part back exactly, the custom stud materials are made
	once per material, and on the whole built map nothing new appears.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local Color3 = roblox.Color3
	local Enum = roblox.Enum
	local StudStyle = Loader.requirePath("ReplicatedStorage.Shared.StudStyle")
	local StudStyleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StudStyleConfig")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	-- Lune cannot read an unset BasePart.MaterialVariant (an alias of MaterialVariantSerialized)
	local function prime(root: any)
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and not pcall(function()
				return d.MaterialVariant
			end) then
				d.MaterialVariant = ""
			end
		end
	end

	local function newPart(parent: any, props: { [string]: any }?, className: string?): any
		local p = Instance.new(className or "Part")
		p.Anchored = true
		p.Size = Vector3.new(4, 1, 4)
		p.CFrame = CFrame.new(3, 2, 1) * CFrame.Angles(0, 0.4, 0)
		p.Color = Color3.fromRGB(80, 170, 60)
		p.Material = Enum.Material.SmoothPlastic
		for _, face in { "Top", "Bottom", "Front", "Back", "Left", "Right" } do
			p[face .. "Surface"] = Enum.SurfaceType.Smooth
		end
		p.MaterialVariant = ""
		for key, value in props or {} do
			p[key] = value
		end
		p.Parent = parent
		return p
	end

	local function newWorld(): (any, any)
		local game = Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		local folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = workspace
		return workspace, folder
	end

	-- every config switch back as the specs found it
	local function withPreview(on: boolean, fn: () -> ())
		local before = StudStyleConfig.Previewing
		StudStyleConfig.Previewing = on
		local ok, err = pcall(fn)
		StudStyleConfig.Previewing = before
		if not ok then
			error(err, 0)
		end
	end

	T.test("stud style: the config is whole", function()
		T.truthy(StudStyleConfig.Look == "Classic" or StudStyleConfig.Look == "Custom", "a known look")
		T.eq(StudStyleConfig.StudsPerTile, 2, "the pictures hold 2 x 2 studs: one stud per stud")
		for key, id in StudStyleConfig.Assets do
			T.truthy(type(id) == "number" and id >= 0 and id == math.floor(id), key .. " id")
		end
		for _, never in { "Neon", "Glass", "ForceField", "Foil", "Water", "Air" } do
			T.falsy(StudStyleConfig.Materials[never], never .. " never gets studs")
		end
		for name in StudStyleConfig.Materials do
			T.truthy(
				pcall(function()
					return Enum.Material[name]
				end),
				name .. " is a Roblox material"
			)
		end
		for face, surface in StudStyleConfig.Classic.Faces do
			T.truthy(
				pcall(function()
					return Enum.SurfaceType[surface]
				end),
				face .. " surface"
			)
		end
		T.truthy(StudStyleConfig.BudgetMs > 0 and StudStyleConfig.BudgetMs <= 4, "a small slice of each frame")
		T.truthy(StudStyleConfig.MinPerFrame >= 10, "always goes on")
		T.falsy(StudStyleConfig.Shapes.Ball, "balls stay smooth")
		for name, on in StudStyleConfig.Materials do
			T.eq(StudStyleConfig.Classic.Convert[name] == true, on, name .. ": Classic studs every stud material")
		end
	end)

	T.test("stud style: suitable parts and the ones that keep their look", function()
		local workspace, map = newWorld()
		local model = Instance.new("Model")
		model.Parent = map
		T.eq(StudStyle.skipReason(newPart(model)), nil, "a plastic floor plate")
		T.eq(StudStyle.skipReason(newPart(model, { Size = Vector3.new(0.35, 0.45, 8) })), nil, "a fence board")
		T.eq(StudStyle.skipReason(newPart(model, { Size = Vector3.new(0.8, 3, 0.8) })), nil, "a fence post")
		T.eq(StudStyle.skipReason(newPart(model, { Material = Enum.Material.Slate })), nil, "slate paving")
		T.eq(StudStyle.skipReason(newPart(model, {}, "WedgePart")), nil, "a roof wedge")
		T.eq(StudStyle.skipReason(newPart(model, { Reflectance = 0.05 })), nil, "the wet slate shine")

		T.eq(StudStyle.skipReason(newPart(model, { Material = Enum.Material.Neon })), "material Neon", "glow")
		T.eq(StudStyle.skipReason(newPart(model, { Material = Enum.Material.Glass })), "material Glass", "windows")
		T.eq(StudStyle.skipReason(newPart(model, { Material = Enum.Material.Metal })), "material Metal", "metal stays metal")
		T.eq(StudStyle.skipReason(newPart(model, { Transparency = 0.5 })), "transparent", "water / holograms")
		T.eq(StudStyle.skipReason(newPart(model, { Reflectance = 0.2 })), "reflective", "the sea")
		T.eq(StudStyle.skipReason(newPart(model, { Size = Vector3.new(0.5, 0.4, 0.6) })), "small", "a pebble")
		T.eq(StudStyle.skipReason(newPart(model, { Size = Vector3.new(0.2, 0.2, 3) })), "small", "thin trim")
		T.eq(StudStyle.skipReason(newPart(model, { Shape = Enum.PartType.Ball })), "shape Ball", "a ball")
		T.eq(StudStyle.skipReason(newPart(model, {}, "TrussPart")), "class TrussPart", "a truss")
		T.eq(StudStyle.skipReason(newPart(model, { MaterialVariant = "Marble2" })), "own material", "another custom material")
		T.eq(StudStyle.skipReason(newPart(model, { Name = "Water" })), "name Water", "a part named water")
		T.eq(StudStyle.skipReason(newPart(model, { Name = "OuterSea" })), "name Sea$", "the outer sea")
		T.eq(StudStyle.skipReason(newPart(model, { Name = "BenchSeat" })), nil, "a bench seat is no sea")

		local sign = newPart(model)
		local gui = Instance.new("SurfaceGui")
		gui.Parent = sign
		local frame = Instance.new("Frame")
		frame.Parent = gui
		T.eq(StudStyle.skipReason(sign), nil, "a SurfaceGui of plain frames (tile seams)")
		Instance.new("TextLabel").Parent = frame
		T.eq(StudStyle.skipReason(sign), "picture", "a sign with words")
		local decal = newPart(model)
		Instance.new("Decal").Parent = decal
		T.eq(StudStyle.skipReason(decal), "picture", "a decal")
		local board = newPart(model)
		Instance.new("SurfaceGui").Parent = board
		T.eq(StudStyle.skipReason(board), "picture", "an empty SurfaceGui: a board filled in later (SKY EGG odds)")
		local egg = newPart(model)
		Instance.new("SpecialMesh").Parent = egg
		T.eq(StudStyle.skipReason(egg), "mesh", "a sphere-meshed egg")
		T.eq(StudStyle.skipReason(newPart(model, { Name = "RailL" })), "part RailL", "a belt's side rail")
		T.eq(StudStyle.skipReason(newPart(model, { Name = "RailR" })), "part RailR", "the other rail")
		T.eq(StudStyle.skipReason(newPart(model, { Name = "Rail" })), nil, "a plain rail (the railway)")

		StudStyle.clearCache()
		local character = Instance.new("Model")
		Instance.new("Humanoid").Parent = character
		character.Parent = workspace
		T.eq(StudStyle.skipReason(newPart(character)), "character", "a character's body")
		local accessory = Instance.new("Accessory")
		accessory.Parent = character
		T.eq(StudStyle.skipReason(newPart(accessory, {}, "Part")), "worn", "an accessory")
		local tool = Instance.new("Tool")
		tool.Parent = workspace
		T.eq(StudStyle.skipReason(newPart(tool)), "worn", "a tool")
		local items = Instance.new("Folder")
		items.Name = "Items"
		items.Parent = workspace
		T.eq(StudStyle.skipReason(newPart(items)), "root Items", "carried ore")
		local cloud = Instance.new("Model")
		cloud.Name = "Cloud5"
		cloud.Parent = map
		local puff = Instance.new("Model")
		puff.Parent = cloud
		T.eq(StudStyle.skipReason(newPart(puff)), "name Cloud", "a cloud's parts")
		local plain = Instance.new("Model")
		plain:AddTag("NoStuds")
		plain.Parent = map
		T.eq(StudStyle.skipReason(newPart(plain)), "tagged", "tagged NoStuds")
		local podium = Instance.new("Model")
		podium.Name = "Podium3"
		podium.Parent = map
		T.eq(StudStyle.skipReason(newPart(podium, { Name = "Rim" })), "part Rim", "a podium's rim")
		T.eq(StudStyle.skipReason(newPart(podium, { Name = "Column" })), nil, "the podium's column")
		T.eq(StudStyle.skipReason(newPart(model, { Name = "Rim" })), nil, "a rim elsewhere")
		for name, want in
			{
				CrystalCluster = false,
				Crystals = false,
				Crystal3 = false,
				CrystalFacet = false,
				EggCrystal = false,
				Display_Clean_Copper = false,
				Display = false,
				Artifact = false,
				ClientTrains = false,
				CleaningClient = false,
				CrateOpening = false,
				FireCrystalRing = true,
				CrystalFloor = true,
				CrystalIsle = true,
				ArtifactMuseum = true,
			}
		do
			local holder = Instance.new("Model")
			holder.Name = name
			holder.Parent = map
			StudStyle.clearCache()
			local reason = StudStyle.skipReason(newPart(holder))
			T.eq(reason == nil, want, `{name}: {if want then "gets studs" else "stays smooth"} ({reason})`)
		end
		StudStyle.clearCache()
	end)

	T.test("stud style: Classic changes the look only, once, and restores exactly", function()
		local _, map = newWorld()
		local part = newPart(map)
		local cframe, size, color = part.CFrame, part.Size, part.Color
		T.truthy(StudStyle.applyPart(part, "Classic"), "styled")
		T.eq(part.Material, Enum.Material.Plastic, "surfaces show on Plastic")
		T.eq(part.TopSurface, Enum.SurfaceType.Studs, "studs on top")
		T.eq(part.FrontSurface, Enum.SurfaceType.Studs, "studs on the walls")
		T.eq(part.BottomSurface, Enum.SurfaceType.Inlet, "inlets underneath")
		local physics = part.CustomPhysicalProperties
		local smooth = roblox.PhysicalProperties.new(Enum.Material.SmoothPlastic)
		T.truthy(physics ~= nil, "physics pinned")
		T.near(physics.Friction, smooth.Friction, 1e-6, "SmoothPlastic's friction")
		T.near(physics.Density, smooth.Density, 1e-6, "SmoothPlastic's density")
		T.eq(part.CFrame, cframe, "CFrame")
		T.eq(part.Size, size, "Size")
		T.eq(part.Color, color, "Color")
		T.truthy(part.Anchored and part.CanCollide and part.CanTouch and part.CanQuery, "collision untouched")
		T.eq(part.Transparency, 0, "Transparency")
		T.falsy(StudStyle.applyPart(part, "Classic"), "a second run changes nothing")
		T.falsy(StudStyle.applyPart(part, "Custom"), "nor does another look over it")
		T.eq(#part:GetChildren(), 0, "no new instances")

		T.truthy(StudStyle.restorePart(part), "restored")
		T.eq(part.Material, Enum.Material.SmoothPlastic, "material back")
		T.eq(part.TopSurface, Enum.SurfaceType.Smooth, "surface back")
		T.eq(part.BottomSurface, Enum.SurfaceType.Smooth, "bottom back")
		T.eq(part.CustomPhysicalProperties, nil, "physics back")
		T.eq(part:GetAttribute("StudStyle"), nil, "record gone")
		T.falsy(StudStyle.restorePart(part), "restoring twice is a no-op")

		-- a part with its own physics keeps them
		local own = roblox.PhysicalProperties.new(2, 0.9, 0.1)
		local heavy = newPart(map, { CustomPhysicalProperties = own })
		StudStyle.applyPart(heavy, "Classic")
		T.eq(heavy.CustomPhysicalProperties, own, "own physics kept")
		StudStyle.restorePart(heavy)
		T.eq(heavy.CustomPhysicalProperties, own, "own physics still there after the restore")

		-- another script turned it Neon meanwhile: that stays
		local flash = newPart(map)
		StudStyle.applyPart(flash, "Classic")
		flash.Material = Enum.Material.Neon
		StudStyle.restorePart(flash)
		T.eq(flash.Material, Enum.Material.Neon, "a later material change is not undone")
	end)

	T.test("stud style: Classic studs slate too, with slate's physics; Custom keeps the material", function()
		local _, map = newWorld()
		local slate = newPart(map, { Material = Enum.Material.Slate })
		T.truthy(StudStyle.applyPart(slate, "Classic"), "slate in the Classic look")
		T.eq(slate.Material, Enum.Material.Plastic, "Roblox's studs need Plastic")
		T.eq(slate.TopSurface, Enum.SurfaceType.Studs, "studs on the paving")
		local slatePhysics = roblox.PhysicalProperties.new(Enum.Material.Slate)
		T.near(slate.CustomPhysicalProperties.Friction, slatePhysics.Friction, 1e-6, "slate's friction")
		T.near(slate.CustomPhysicalProperties.Density, slatePhysics.Density, 1e-6, "slate's weight")
		T.truthy(StudStyle.restorePart(slate), "restored")
		T.eq(slate.Material, Enum.Material.Slate, "slate again")
		T.eq(slate.CustomPhysicalProperties, nil, "physics back")
		-- a material whose physics cannot be read (Lune has no Plaster table) stays untouched
		local plaster = newPart(map, { Material = Enum.Material.Plaster })
		if StudStyle.applyPart(plaster, "Classic") then
			T.truthy(plaster.CustomPhysicalProperties ~= nil, "plaster's physics pinned")
		else
			T.eq(plaster.Material, Enum.Material.Plaster, "plaster untouched")
			T.eq(plaster.TopSurface, Enum.SurfaceType.Smooth, "no surfaces")
			T.eq(plaster:GetAttribute("StudStyle"), nil, "no record")
		end

		withPreview(false, function()
			if StudStyleConfig.customReady() then
				return -- the pictures are uploaded: covered below
			end
			local part = newPart(map)
			T.falsy(StudStyle.applyPart(part, "Custom"), "no custom studs without pictures")
			T.eq(part.MaterialVariant, "", "untouched")
		end)
		withPreview(true, function()
			local part = newPart(map)
			T.truthy(StudStyle.applyPart(part, "Custom"), "styled")
			T.eq(part.Material, Enum.Material.SmoothPlastic, "material kept")
			T.eq(part.MaterialVariant, StudStyle.VariantName, "the stud material")
			T.eq(part.TopSurface, Enum.SurfaceType.Smooth, "surfaces untouched")
			T.eq(part.CustomPhysicalProperties, nil, "physics untouched")
			T.truthy(StudStyle.restorePart(part), "restored")
			T.eq(part.MaterialVariant, "", "no material variant again")

			local wood = newPart(map, { Material = Enum.Material.Wood })
			T.truthy(StudStyle.applyPart(wood, "Custom"), "wood in the Custom look")
			T.eq(wood.Material, Enum.Material.Wood, "wood stays wood")
		end)
	end)

	T.test("stud style: a client takes the custom studs once the server made them", function()
		local _, map = newWorld()
		withPreview(false, function()
			if StudStyleConfig.customReady() then
				return -- the pictures are in the config already
			end
			-- the MaterialService StudStyle sees (the loader's virtual game)
			local service = Loader.game:GetService("MaterialService")
			local part = newPart(map)
			T.falsy(StudStyle.applyPart(part, "Custom"), "nothing before the server's stud materials")
			local folder = Loader._newNode(StudStyle.FolderName, "Folder", service)
			local ok, err = pcall(function()
				T.truthy(StudStyle.customReady(), "ready from MaterialService")
				T.truthy(StudStyle.applyPart(part, "Custom"), "styled once they are there")
			end)
			rawget(service, "Children")[StudStyle.FolderName] = nil
			local list = rawget(service, "ChildList")
			table.remove(list, table.find(list, folder) :: number)
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.test("stud style: one custom stud material per material, made once", function()
		local game = Instance.new("DataModel")
		local service = game:GetService("MaterialService")
		withPreview(false, function()
			if not StudStyleConfig.customReady() then
				T.eq(StudStyle.ensureVariants(service), nil, "nothing without pictures")
				T.eq(service:FindFirstChild(StudStyle.FolderName), nil, "no folder")
			end
		end)
		withPreview(true, function()
			local folder = StudStyle.ensureVariants(service)
			T.truthy(folder, "made")
			local wanted, seen = 0, {}
			for name, on in StudStyleConfig.Materials do
				if on then
					wanted += 1
				end
			end
			for _, variant in folder:GetChildren() do
				T.eq(variant.ClassName, "MaterialVariant", "class")
				T.eq(variant.Name, StudStyle.VariantName, "name")
				T.eq(variant.StudsPerTile, StudStyleConfig.StudsPerTile, "studs per tile")
				T.falsy(seen[variant.BaseMaterial.Name], "one per material: " .. variant.BaseMaterial.Name)
				seen[variant.BaseMaterial.Name] = true
			end
			T.eq(#folder:GetChildren(), wanted, "every stud material")
			StudStyle.ensureVariants(service)
			T.eq(#folder:GetChildren(), wanted, "a second run adds none")
			local before = StudStyleConfig.Assets.NormalMap
			StudStyleConfig.Assets.NormalMap = 123
			StudStyle.ensureVariants(service)
			StudStyleConfig.Assets.NormalMap = before
			T.eq(folder:GetChildren()[1].NormalMap, "rbxassetid://123", "the uploaded picture")
			StudStyle.removeVariants(service)
			T.eq(service:FindFirstChild(StudStyle.FolderName), nil, "removed")
		end)
	end)

	T.test("stud style: watch styles now and later, skips removed parts, stops", function()
		local task = require("@lune/task")
		local _, map = newWorld()
		local parts = {}
		for i = 1, 240 do
			parts[i] = newPart(map, { CFrame = CFrame.new(i * 5, 0, 0) })
		end
		local gone = newPart(map)
		-- the specs' own "DescendantAdded" (Lune's instances have no real signals)
		local fire: ((any) -> ())? = nil
		local added = StudStyle.added
		StudStyle.added = function(): any
			return {
				Connect = function(_, fn)
					fire = fn
					return {
						Disconnect = function()
							fire = nil
						end,
					}
				end,
			}
		end
		local budget = StudStyleConfig.BudgetMs
		StudStyleConfig.BudgetMs = 0 -- yield after every MinPerFrame parts
		local ok, err = pcall(function()
			local stop = StudStyle.watch(map, "Classic")
			T.eq(parts[1]:GetAttribute("StudStyle"), nil, "deferred: a builder may still set the look")
			-- streamed out / removed before its turn (Lune errors on reading a destroyed
			-- part's Parent; Roblox gives nil, so unparenting stands in for Destroy)
			gone.Parent = nil
			for _ = 1, 20 do
				task.wait()
			end
			for i, part in parts do
				T.truthy(part:GetAttribute("StudStyle"), `part {i} styled in slices`)
			end
			T.eq(gone:GetAttribute("StudStyle"), nil, "a removed part is skipped")
			local late = newPart(map)
			assert(fire, "connected")(late)
			for _ = 1, 3 do
				task.wait()
			end
			T.truthy(late:GetAttribute("StudStyle"), "a part added later gets studs")
			stop()
			T.eq(fire, nil, "stop disconnects")
			T.eq(StudStyle.restoreTree(map), #parts + 1, "restore takes them all back")
		end)
		StudStyle.added = added
		StudStyleConfig.BudgetMs = budget
		if not ok then
			error(err, 0)
		end
	end)

	T.test("stud style: the whole map, nothing new, all back", function()
		local game = Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		local map = WorldBuilder.build(workspace)
		prime(map)
		local snapshot = {}
		local count = 0
		for _, d in map:GetDescendants() do
			count += 1
			if d:IsA("BasePart") then
				snapshot[d] = {
					d.Material,
					{ d.TopSurface, d.BottomSurface, d.FrontSurface, d.BackSurface, d.LeftSurface, d.RightSurface },
					d.CustomPhysicalProperties,
					d.CFrame,
					d.Size,
					d.Color,
					d.CanCollide,
				}
			end
		end
		withPreview(true, function()
			local styled = StudStyle.applyTree(workspace, "Classic")
			-- the podium rims PodiumService flips to Neon and back keep their look
			local rims = 0
			for _, plot in map.Plots:GetChildren() do
				local yard = plot:FindFirstChild("Yard")
				for slot = 1, 8 do
					local podium = yard and yard:FindFirstChild("Podium" .. slot)
					local rim = podium and podium:FindFirstChild("Rim")
					if rim then
						rims += 1
						T.eq(rim:GetAttribute("StudStyle"), nil, `{plot.Name} podium {slot} rim untouched`)
						T.eq(rim.TopSurface, Enum.SurfaceType.Smooth, "no surfaces on the rim")
					end
				end
			end
			T.truthy(rims >= 8 * 2, `every plot's podium rims found ({rims})`)
			T.truthy(styled > 15000, `most of the map has studs ({styled})`)
			T.eq(#map:GetDescendants(), count, "no new instances")
			for part, was in snapshot do
				if part:GetAttribute("StudStyle") then
					T.truthy(was[1] ~= Enum.Material.Neon and was[1] ~= Enum.Material.Glass, "no glow or glass styled")
				end
				T.eq(part.CFrame, was[4], "CFrame")
				T.eq(part.Size, was[5], "Size")
				T.eq(part.Color, was[6], "Color")
				T.eq(part.CanCollide, was[7], "CanCollide")
				if part:GetAttribute("StudStyle") and was[3] == nil then
					local own = roblox.PhysicalProperties.new(was[1])
					T.near(part.CustomPhysicalProperties.Friction, own.Friction, 1e-6, "its own friction pinned")
				end
			end
			T.eq(StudStyle.applyTree(workspace, "Classic"), 0, "a second run changes nothing")
			T.eq(StudStyle.restoreTree(workspace), styled, "every styled part restored")
			for part, was in snapshot do
				T.eq(part.Material, was[1], "material back")
				local faces =
					{ part.TopSurface, part.BottomSurface, part.FrontSurface, part.BackSurface, part.LeftSurface, part.RightSurface }
				for i, surface in faces do
					T.eq(surface, was[2][i], `surface {i} back`)
				end
				T.eq(part.CustomPhysicalProperties, was[3], "physics back")
				T.eq(part:GetAttribute("StudStyle"), nil, "record gone")
			end
		end)
	end)
end
