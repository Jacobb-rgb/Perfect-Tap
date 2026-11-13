-- The owner's ore models (MeshKit, docs/plans/MESHY_MODELS_PLAN.md package A) with stand-in templates
-- (tools/lune/lib/mesh_fakes): cleaned ores wear Ore_<Id>_Low in the world and on belts and Ore_<Id> on
-- display copies, close-ups and the cleaning reveal, at the old look's size; physics stays on one
-- primitive Body; the Dirty Ore, crushed, ingots, gear, alloys, relics and the ores without a model keep
-- their parts exactly. (Without templates the part looks are covered by Ores / OreLooks*.spec.)
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local CF = Loader.CFrame
	local Vector3 = roblox.Vector3
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local MeshCatalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local MeshKit = Loader.requirePath("ReplicatedStorage.Shared.Builders.MeshKit")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreShellBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreShellBuilder")
	local PictureModels = Loader.requirePath("ReplicatedStorage.Shared.Builders.PictureModels")
	local Patterns = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.CleaningPatterns")

	local MESH_PATH = "ReplicatedStorage.Shared.Assets.MeshAssets"
	local GRADES = { "Rough", "Clean", "Pristine", "Flawless" }

	local modelOres = {}
	for id in MeshCatalog.Ores do
		table.insert(modelOres, id)
	end
	table.sort(modelOres)
	local plainOres = {}
	for _, ore in OreData.List do
		if not MeshCatalog.Ores[ore.Id] then
			table.insert(plainOres, ore.Id)
		end
	end

	local function orderOf(id: string): number
		return Rarity.get(OreData.get(id).Rarity).Order
	end

	local function partsOf(model: any): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function meshesOf(model: any): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function countClass(model: any, className: string): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	-- the visible parts' world box (no motes): min, max
	local function boxOf(model: any): (any, any)
		local mn = { math.huge, math.huge, math.huge }
		local mx = { -math.huge, -math.huge, -math.huge }
		for _, part in partsOf(model) do
			if part.Transparency < 1 and part.Name ~= "Mote" then
				local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
				local h = part.Size / 2
				local p = part.CFrame.Position
				local half = {
					math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
					math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
					math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z,
				}
				local pos = { p.X, p.Y, p.Z }
				for axis = 1, 3 do
					mn[axis] = math.min(mn[axis], pos[axis] - half[axis])
					mx[axis] = math.max(mx[axis], pos[axis] + half[axis])
				end
			end
		end
		return Vector3.new(mn[1], mn[2], mn[3]), Vector3.new(mx[1], mx[2], mx[3])
	end

	local function sizeOf(model: any): any
		local mn, mx = boxOf(model)
		return mx - mn
	end

	-- every part, light and emitter of a look, in build order (equal strings = the same look)
	local function signature(model: any): string
		local rows = { model.Name }
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local p, s, c = d.CFrame.Position, d.Size, d.Color
				table.insert(
					rows,
					string.format(
						"%s %s %.4f %.4f %.4f @ %.4f %.4f %.4f %.3f %.3f %.3f %s %.2f %s",
						d.ClassName,
						d.Name,
						s.X,
						s.Y,
						s.Z,
						p.X,
						p.Y,
						p.Z,
						c.R,
						c.G,
						c.B,
						tostring(d.Material),
						d.Transparency,
						tostring(d.CanCollide)
					)
				)
			elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("WeldConstraint") then
				table.insert(rows, d.ClassName .. " " .. d.Name)
			end
		end
		return table.concat(rows, "\n")
	end

	local function isWelded(model: any, body: any, part: any): boolean
		for _, d in model:GetDescendants() do
			if d:IsA("WeldConstraint") and d.Part0 == body and d.Part1 == part then
				return true
			end
		end
		return false
	end

	local CF_ITEM = CF.new(2, 3, 4) * CF.Angles(0, 0.4, 0)
	local CF_SHOW = CF.new(3, 5, -2) * CF.Angles(0, 0.7, 0)

	-- every look that must stay the part look, built before the stand-ins come (the fallback)
	local function plainLooks(): { [string]: string }
		local looks = {}
		for _, ore in OreData.List do
			looks["raw/" .. ore.Id] = signature(ItemBuilder.build({ Kind = "Raw", OreId = ore.Id }, CF_ITEM, 7))
			looks["rawLight/" .. ore.Id] = signature(ItemBuilder.buildLight({ Kind = "Raw", OreId = ore.Id }, CF_ITEM, 7))
			looks["rawShown/" .. ore.Id] = signature(ItemBuilder.display({ K = "Raw", O = ore.Id }, CF_SHOW, 7))
		end
		for _, id in { "Coal", "Gold", "Heartstone" } do
			for _, kind in { "Crushed", "Ingot", "Alloy" } do
				looks[kind .. "/" .. id] = signature(ItemBuilder.build({ Kind = kind, OreId = id, Grade = "Flawless" }, CF_ITEM, 3))
				looks[kind .. "Light/" .. id] =
					signature(ItemBuilder.buildLight({ Kind = kind, OreId = id, Grade = "Flawless" }, CF_ITEM, 3))
			end
			for _, recipe in { "Dagger", "Helm" } do
				looks["Gear" .. recipe .. "/" .. id] =
					signature(ItemBuilder.build({ Kind = "Gear", OreId = id, Recipe = recipe }, CF_ITEM, 3))
			end
		end
		for _, id in plainOres do
			looks["clean/" .. id] = signature(ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = "Flawless" }, CF_ITEM, 5))
			looks["close/" .. id] = signature(ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = "Flawless" }, CF_ITEM, 5, true))
			looks["light/" .. id] = signature(ItemBuilder.buildLight({ Kind = "Clean", OreId = id, Grade = "Flawless" }, CF_ITEM, 5))
			looks["shown/" .. id] = signature(ItemBuilder.display({ K = "Clean", O = id, G = "Flawless" }, CF_SHOW, 5))
		end
		local relic = ArtifactConfig.List[1].Id
		looks["relic"] = signature(ItemBuilder.build({ Kind = "Relic", OreId = relic }, CF_ITEM, 1))
		looks["relicLight"] = signature(ItemBuilder.buildLight({ Kind = "Relic", OreId = relic }, CF_ITEM, 1))
		return looks
	end

	-- the old part look's sizes of the ores with a model (studs): the models keep them
	local function oldSizes(): { [string]: { Clean: any, Shown: any } }
		local sizes = {}
		for _, id in modelOres do
			sizes[id] = {
				Clean = sizeOf(ItemBuilder.build({ Kind = "Clean", OreId = id }, CF.new(), 1)),
				Shown = sizeOf(ItemBuilder.display({ K = "Clean", O = id }, CF.new(), 1)),
			}
		end
		return sizes
	end

	-- the references in the part look (also once the owner's templates are uploaded), then the models
	local meshesWere = ItemBuilder.Meshes
	ItemBuilder.Meshes = false
	local before = plainLooks()
	local cleanBefore = signature(ItemBuilder.build({ Kind = "Clean", OreId = "Gold", Grade = "Flawless" }, CF_ITEM, 5))
	local sizes = oldSizes()
	ItemBuilder.Meshes = true
	-- the stand-ins replace whatever is mounted (the owner's templates once uploaded); put back at the end
	local hadTemplates, templates = pcall(Loader.find, MESH_PATH)
	Fakes(Loader, true)

	T.test("ore meshes: a stand-in template for both looks of every ore with a model, none for the others", function()
		T.eq(#modelOres, 31, "31 ores with a model (the owner's 28 + Crystal Rose, Storm Pearl, Galaxy Stone)")
		for _, id in modelOres do
			T.truthy(OreData.get(id), id .. " is an ore")
			T.truthy(MeshKit.has("Ore_" .. id), id .. " hero model")
			T.truthy(MeshKit.has("Ore_" .. id .. "_Low"), id .. " crowd model")
		end
		for _, id in plainOres do
			T.falsy(MeshKit.has("Ore_" .. id), id .. " has no model")
		end
	end)

	T.test("ore meshes: clean items wear Ore_<Id>_Low welded to one invisible primitive Body", function()
		for _, id in modelOres do
			for _, grade in GRADES do
				local label = `{id} {grade}`
				local model = ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = grade }, CF_ITEM, id)
				T.eq(model.Name, "Clean_" .. id, label .. " model name")
				local body = model.PrimaryPart
				T.truthy(body, label .. " PrimaryPart")
				T.eq(body.Name, "Body", label .. " PrimaryPart is Body")
				T.eq(body.ClassName, "Part", label .. " the Body is a primitive Part (ItemService.transplant)")
				T.eq(body.Shape, roblox.Enum.PartType.Block, label .. " a box")
				T.eq(body.Transparency, 1, label .. " the Body is invisible")
				T.falsy(body.Anchored, label .. " unanchored")
				T.truthy(body.CanCollide and body.CanTouch and body.CanQuery, label .. " the Body collides, touches, is clicked")
				T.truthy(body.CustomPhysicalProperties ~= nil, label .. " light and bouncy")
				local parts = partsOf(model)
				T.eq(#parts, 2, label .. " the Body and the model")
				T.le(#parts, ItemBuilder.Budget.Clean, label .. " budget")
				local meshes = meshesOf(model)
				T.eq(#meshes, 1, label .. " one model")
				local mesh = meshes[1]
				T.eq(mesh:GetAttribute("Asset"), "Ore_" .. id .. "_Low", label .. " the crowd model")
				T.eq(mesh.Name, "OreMesh", label .. " named OreMesh")
				T.falsy(mesh.Anchored, label .. " model unanchored")
				T.falsy(mesh.CanCollide, label .. " the model never collides")
				T.falsy(mesh.CanTouch, label .. " no touch")
				T.truthy(mesh.CanQuery, label .. " clicking the model targets the item")
				T.truthy(mesh.Massless, label .. " massless")
				T.truthy(isWelded(model, body, mesh), label .. " welded to the Body")
				T.eq(countClass(model, "WeldConstraint"), 1, label .. " one weld")
				-- the Body wraps the model: a little inside its box, at least MeshBodyMin thick, same middle
				local min = ItemBuilder.MeshBodyMin
				T.near(body.Size.X, math.max(mesh.Size.X - 0.08, min), 1e-4, label .. " Body X")
				T.near(body.Size.Y, math.max(mesh.Size.Y - 0.08, min), 1e-4, label .. " Body Y")
				T.near(body.Size.Z, math.max(mesh.Size.Z - 0.08, min), 1e-4, label .. " Body Z")
				T.near((mesh.CFrame.Position - body.CFrame.Position).Magnitude, 0, 1e-4, label .. " centred on the Body")
				T.near((mesh.CFrame.LookVector - body.CFrame.LookVector).Magnitude, 0, 1e-4, label .. " turned like the Body")
				-- one sparkle at most (grade or Epic+), never a light
				T.eq(countClass(model, "PointLight"), 0, label .. " no lights on loose items")
				local emitters = countClass(model, "ParticleEmitter")
				local sparkles = grade == "Flawless" or grade == "Pristine" or orderOf(id) >= 4
				T.eq(emitters, if sparkles then 1 else 0, label .. " sparkle")
				if sparkles then
					T.truthy(body:FindFirstChild("GradeSparkle"), label .. " the sparkle sits on the Body")
				end
			end
		end
	end)

	T.test("ore meshes: the belt look is the same Body and model (no sparkle), within LightBudget", function()
		for _, id in modelOres do
			for _, grade in { "Rough", "Flawless" } do
				local label = `{id} {grade}`
				local info = { Kind = "Clean", OreId = id, Grade = grade }
				local light = ItemBuilder.buildLight(info, CF_ITEM, 7)
				local full = ItemBuilder.build(info, CF_ITEM, 7)
				T.le(#partsOf(light), ItemBuilder.LightBudget, label .. " light parts")
				T.eq(countClass(light, "ParticleEmitter") + countClass(light, "Light"), 0, label .. " no sparkles or lights on belts")
				local a, b = light.PrimaryPart, full.PrimaryPart
				T.eq(a.Name, "Body", label .. " a Body")
				T.eq(a.ClassName, "Part", label .. " a primitive Body")
				T.near((a.Size - b.Size).Magnitude, 0, 1e-6, label .. " the same Body size")
				T.near((a.CFrame.Position - b.CFrame.Position).Magnitude, 0, 1e-6, label .. " at the same spot")
				T.eq(a.Transparency, 1, label .. " invisible Body")
				local mesh = meshesOf(light)[1]
				T.truthy(mesh, label .. " the model")
				T.eq(mesh:GetAttribute("Asset"), "Ore_" .. id .. "_Low", label .. " the crowd model")
				T.near((mesh.Size - meshesOf(full)[1].Size).Magnitude, 0, 1e-6, label .. " the same model size")
				T.truthy(isWelded(light, a, mesh), label .. " welded")
				T.truthy(mesh.Massless and not mesh.CanCollide, label .. " decor")
			end
		end
	end)

	T.test("ore meshes: the models keep the old look's size (same sum of sides, never longer, own proportions)", function()
		for _, id in modelOres do
			local old = sizes[id]
			local hero = MeshKit.box("Ore_" .. id)
			for _, case in
				{
					{ "clean", ItemBuilder.build({ Kind = "Clean", OreId = id }, CF.new(), 1), old.Clean },
					{ "display", ItemBuilder.display({ K = "Clean", O = id }, CF.new(), 1), old.Shown },
				}
			do
				local label = `{id} {case[1]}`
				local mesh = meshesOf(case[2])[1]
				local own = MeshKit.box(mesh:GetAttribute("Asset"))
				local s = mesh.Size
				local was = case[3]
				local longest, wasLongest = math.max(s.X, s.Y, s.Z), math.max(was.X, was.Y, was.Z)
				local sum, wasSum = s.X + s.Y + s.Z, was.X + was.Y + was.Z
				-- (scaled from the hero model: the crowd model may be a little smaller)
				local k = s.X / own.X
				T.near(s.Y / own.Y, k, 1e-4, label .. " in proportion (Y)")
				T.near(s.Z / own.Z, k, 1e-4, label .. " in proportion (Z)")
				local heroSize = hero * k
				local heroLongest = math.max(heroSize.X, heroSize.Y, heroSize.Z)
				local heroSum = heroSize.X + heroSize.Y + heroSize.Z
				T.truthy(heroLongest <= wasLongest + 1e-3, `{label}: never longer than the old look ({heroLongest} > {wasLongest})`)
				T.truthy(heroSum <= wasSum + 1e-3, `{label}: never bigger than the old look ({heroSum} > {wasSum})`)
				T.truthy(
					math.abs(heroLongest - wasLongest) < 1e-3 or math.abs(heroSum - wasSum) < 1e-3,
					`{label}: the old look's size ({heroSum} / {wasSum}, {heroLongest} / {wasLongest})`
				)
				T.truthy(longest >= 0.6 * wasLongest, `{label}: not tiny ({longest} vs {wasLongest})`)
				T.truthy(sum > 0, label)
			end
			-- a display fills its plinth like the old look and never hangs over it (OreLooksLow: 3-stud plinth)
			local shown = sizeOf(ItemBuilder.display({ K = "Clean", O = id }, CF.new(), 1))
			T.truthy(shown.X <= 2.7 and shown.Z <= 2.7, `{id} fits its plinth ({shown.X}, {shown.Z})`)
			if orderOf(id) <= 3 then
				T.truthy(shown.Y <= 2.5, `{id} is not too tall ({shown.Y})`)
				T.truthy(math.max(shown.X, shown.Y, shown.Z) >= 1.9, `{id} fills its plinth`)
			end
		end
	end)

	T.test("ore meshes: display copies wear Ore_<Id>, stand on cf and keep the rarity extras", function()
		for _, id in modelOres do
			local order = orderOf(id)
			for _, grade in { "Rough", "Flawless" } do
				local label = `{id} {grade} display`
				local model = ItemBuilder.display({ K = "Clean", O = id, G = grade }, CF_SHOW, 9)
				T.eq(model.Name, "Display_Clean_" .. id, label .. " name")
				local meshes = meshesOf(model)
				T.eq(#meshes, 1, label .. " one model")
				local mesh = meshes[1]
				T.eq(mesh:GetAttribute("Asset"), "Ore_" .. id, label .. " the hero model")
				T.eq(model.PrimaryPart, mesh, label .. " PrimaryPart = the model")
				T.le(#partsOf(model), ItemBuilder.Budget.Display, label .. " budget")
				T.eq(countClass(model, "WeldConstraint") + countClass(model, "Weld"), 0, label .. " no welds")
				for _, part in partsOf(model) do
					T.truthy(part.Anchored, label .. " anchored")
					T.falsy(part.CanCollide, label .. " no collision")
					T.falsy(part.CanTouch, label .. " no touch")
					T.falsy(part.CanQuery, label .. " no query")
				end
				local mn, mx = boxOf(model)
				T.near(mn.Y, 5, 1e-3, label .. " stands on cf")
				local flat = Vector3.new(mesh.CFrame.Position.X - 3, 0, mesh.CFrame.Position.Z + 2)
				T.near(flat.Magnitude, 0, 1e-3, label .. " centred over cf")
				local center = model:GetAttribute("Center")
				T.truthy(typeof(center) == "Vector3", label .. " Center")
				T.near((center - mesh.CFrame.Position).Magnitude, 0, 1e-3, label .. " Center = the model's middle")
				T.truthy(mx.Y > mn.Y, label)
				T.eq(countClass(model, "PointLight"), if order >= 5 then 1 else 0, label .. " light (Legendary+)")
				local sparkle = mesh:FindFirstChild("Sparkle")
				T.eq(sparkle ~= nil, order >= 4 or grade == "Flawless", label .. " sparkle (Epic+ or Flawless)")
				local motes = 0
				for _, part in partsOf(model) do
					if part.Name == "Mote" then
						motes += 1
						T.eq(part.Material, roblox.Enum.Material.Neon, label .. " glowing motes")
					end
				end
				T.eq(motes, if order >= 6 then 3 else 0, label .. " motes (Mythic)")
				T.eq(model:GetAttribute("Pulse") == true, order >= 6, label .. " Pulse attribute (Mythic)")
				T.eq(mesh:FindFirstChild("Pulse") ~= nil, order >= 6, label .. " pulse on the model")
			end
		end
	end)

	T.test("ore meshes: the Ore Pen's pile (display with crowd) wears the light model at the same size", function()
		for _, id in modelOres do
			local label = `{id} pile copy`
			local hero = meshesOf(ItemBuilder.display({ K = "Clean", O = id, G = "Clean" }, CF_SHOW, 9))[1]
			local model = ItemBuilder.display({ K = "Clean", O = id, G = "Clean" }, CF_SHOW, 9, true)
			local meshes = meshesOf(model)
			T.eq(#meshes, 1, label .. " one model")
			T.eq(meshes[1]:GetAttribute("Asset"), "Ore_" .. id .. "_Low", label .. " the light model")
			T.eq(model.PrimaryPart, meshes[1], label .. " PrimaryPart = the model")
			local a, b = math.max(hero.Size.X, hero.Size.Y, hero.Size.Z), math.max(meshes[1].Size.X, meshes[1].Size.Y, meshes[1].Size.Z)
			T.near(b, a, a * 0.25, label .. " about the hero's size")
		end
	end)

	T.test("ore meshes: close-ups wear the hero model, the world never does", function()
		for _, id in modelOres do
			local close = ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = "Pristine" }, CF.new(), id, true)
			local mesh = meshesOf(close)[1]
			T.eq(mesh:GetAttribute("Asset"), "Ore_" .. id, id .. " close-up: the hero model")
			T.eq(close.PrimaryPart.Name, "Body", id .. " close-up: still an item model")
			T.eq(close.PrimaryPart.ClassName, "Part", id .. " close-up: a primitive Body")
			local world = ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = "Pristine" }, CF.new(), id)
			T.eq(meshesOf(world)[1]:GetAttribute("Asset"), "Ore_" .. id .. "_Low", id .. " world: the crowd model")
		end
		-- a dropper's Drop is its ore: the crowd model in the world, the hero one up close and on display
		local drop = { Kind = "Drop", OreId = "DarkMatterDropper" }
		T.eq(meshesOf(ItemBuilder.build(drop, CF_ITEM, 3))[1]:GetAttribute("Asset"), "Ore_Heartstone_Low", "Drop in the world")
		T.eq(meshesOf(ItemBuilder.buildLight(drop, CF_ITEM, 3))[1]:GetAttribute("Asset"), "Ore_Heartstone_Low", "Drop on a belt")
		T.eq(meshesOf(ItemBuilder.build(drop, CF_ITEM, 3, true))[1]:GetAttribute("Asset"), "Ore_Heartstone", "Drop close-up")
		local shownDrop = ItemBuilder.display({ K = "Drop", O = "DarkMatterDropper" }, CF_SHOW, 3)
		T.eq(meshesOf(shownDrop)[1]:GetAttribute("Asset"), "Ore_Heartstone", "Drop on display")
		local lowest = boxOf(shownDrop)
		T.near(lowest.Y, 5, 1e-3, "the Drop display stands on cf")
		-- the UI's ore pictures (PictureModels: the luck / night / enchant cards and the podium picture)
		local picture = PictureModels.build("item_Gold")
		T.eq(meshesOf(picture)[1]:GetAttribute("Asset"), "Ore_Gold", "item_Gold picture")
		T.eq(meshesOf(PictureModels.podium())[1]:GetAttribute("Asset"), "Ore_Gold", "podium picture")
	end)

	T.test("ore meshes: BagFly flies the hero model and keeps its SurfaceAppearance", function()
		local BagFly = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BagFly")
		local template = MeshKit.template("Ore_Gold")
		local look = roblox.Instance.new("SurfaceAppearance")
		look.Name = "Look"
		look.Parent = template
		local view = BagFly.build()
		local f = view.Flyers[1]
		BagFly.setOre(f, "Gold")
		look:Destroy()
		T.falsy(f.Dirty, "a cleaned ore")
		local meshes = meshesOf(f.Model)
		T.eq(#meshes, 1, "the model flies")
		T.eq(meshes[1]:GetAttribute("Asset"), "Ore_Gold", "the hero model")
		T.truthy(meshes[1]:FindFirstChildOfClass("SurfaceAppearance"), "its textures stay")
		for _, part in partsOf(f.Model) do
			T.truthy(part.Transparency < 0.99, "the invisible Body is left out")
			T.truthy(part.Anchored and not part.CanCollide and not part.CanQuery, "still, no collisions")
		end
		T.eq(countClass(f.Model, "WeldConstraint") + countClass(f.Model, "ParticleEmitter"), 0, "no welds or sparkles")
	end)

	T.test("ore meshes: the cleaning reveal shows the hero model behind the dirt", function()
		for _, id in modelOres do
			local pattern = Patterns.generate(id, 131)
			local work = CF.new(0, 5, 0)
			local shell = OreShellBuilder.build(pattern, work)
			local meshes = meshesOf(shell.Treasure)
			T.eq(#meshes, 1, id .. " one model in the treasure")
			local mesh = meshes[1]
			T.eq(mesh:GetAttribute("Asset"), "Ore_" .. id, id .. " the hero model")
			local inCore = false
			for _, part in shell.Core do
				inCore = inCore or part == mesh
			end
			T.truthy(inCore, id .. " rises and turns in the reveal (Core)")
			local at = work:PointToObjectSpace(mesh.CFrame.Position)
			T.truthy(at.Z < OreShellBuilder.CoreFront, id .. " behind the dirt")
			T.truthy(math.sqrt(at.X * at.X + at.Y * at.Y) < 1.3 * OreShellBuilder.Scale, id .. " inside the clump")
			-- scaled to the treasure size (TreasureSize across at most)
			local biggest = math.max(mesh.Size.X, mesh.Size.Y, mesh.Size.Z)
			T.truthy(biggest <= OreShellBuilder.TreasureSize * 1.5, `{id} treasure size ({biggest})`)
			T.truthy(biggest >= 0.8, `{id} not tiny ({biggest})`)
		end
	end)

	T.test("ore meshes: the Dirty Ore, crushed, ingots, gear, alloys, relics and ores without a model are unchanged", function()
		local after = plainLooks()
		local count = 0
		for key, look in before do
			count += 1
			T.eq(after[key], look, key .. " is the same look")
		end
		T.truthy(count > 100, "every look compared")
		for _, ore in OreData.List do
			T.eq(#meshesOf(ItemBuilder.build({ Kind = "Raw", OreId = ore.Id }, CF_ITEM, 7)), 0, ore.Id .. " raw: no model")
		end
	end)

	T.test("ore meshes: ItemService switches a belt item's look in place, keeping its primitive Body", function()
		local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
		local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
		local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
		local Players = Loader.game:GetService("Players")
		local HttpService = Loader.game:GetService("HttpService")
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function()
			return nil
		end)
		patch(DataService, "changed", function() end)
		patch(Net, "fire", function() end)
		patch(Players, "GetPlayerByUserId", function()
			return nil
		end)
		local guids = 0
		patch(HttpService, "GenerateGUID", function()
			guids += 1
			return "guid-" .. guids
		end)
		ItemService._test.reset()
		local ok, err = pcall(function()
			for _, id in { "Gold", "Heartstone", "Sunstone" } do
				local label = id
				local desc = { K = "Clean", O = id, G = "Flawless" }
				local belt = ItemService.spawnDesc(desc, 301, CF.new(0, 5, 0), nil, true)
				T.truthy(belt and belt.Light, label .. ": a belt spawn wears the light look")
				local body = belt.Body
				local size = body.Size
				T.le(#partsOf(belt.Model), ItemBuilder.LightBudget, label .. ": light parts")
				T.eq(meshesOf(belt.Model)[1]:GetAttribute("Asset"), "Ore_" .. id .. "_Low", label .. ": the crowd model on the belt")
				-- picked up: the full look on the same model and Body
				T.truthy(ItemService.dress(belt, false), label .. ": dressed")
				T.truthy(belt.Body == body and belt.Model.PrimaryPart == body, label .. ": the same Body")
				T.eq(body.ClassName, "Part", label .. ": a primitive Body")
				T.near((body.Size - size).Magnitude, 0, 1e-4, label .. ": the same physics box")
				T.eq(body.Transparency, 1, label .. ": the Body stays invisible")
				local full = ItemBuilder.build({ Kind = "Clean", OreId = id, Grade = "Flawless" }, CF.new(), belt.Id)
				T.eq(#partsOf(belt.Model), #partsOf(full), label .. ": every part of the full look")
				local mesh = meshesOf(belt.Model)[1]
				T.truthy(mesh and isWelded(belt.Model, body, mesh), label .. ": the model welded to the Body")
				T.eq(mesh.CollisionGroup, ItemService.ItemGroup, label .. ": items group")
				T.truthy(body:FindFirstChild("GradeSparkle"), label .. ": the sparkle came with the full look")
				-- back on a belt
				T.truthy(ItemService.dress(belt, true), label .. ": light again")
				T.truthy(belt.Body == body, label .. ": still the same Body")
				T.eq(countClass(belt.Model, "ParticleEmitter"), 0, label .. ": no sparkle on belts")
				T.le(#partsOf(belt.Model), ItemBuilder.LightBudget, label .. ": light parts again")
				ItemService.destroy(belt)
			end
		end)
		ItemService._test.reset()
		for i = #saved, 1, -1 do
			rawset(saved[i][1], saved[i][2], saved[i][3])
		end
		if not ok then
			error(err, 0)
		end
	end)

	T.test("ore meshes: one model missing uses the other one; none (or Meshes off) is the part look", function()
		local folder = Loader.find(MESH_PATH)
		local low = folder:FindFirstChild("Ore_Gold_Low")
		low.Parent = nil
		MeshKit.reset()
		local info = { Kind = "Clean", OreId = "Gold", Grade = "Flawless" }
		local item = ItemBuilder.build(info, CF_ITEM, 5)
		T.eq(meshesOf(item)[1]:GetAttribute("Asset"), "Ore_Gold", "no crowd model: the hero one in the world")
		T.near((item.PrimaryPart.Size - ItemBuilder.buildLight(info, CF_ITEM, 5).PrimaryPart.Size).Magnitude, 0, 1e-6, "same Body")
		local hero = folder:FindFirstChild("Ore_Gold")
		hero.Parent = nil
		low.Parent = folder
		MeshKit.reset()
		T.eq(
			meshesOf(ItemBuilder.display({ K = "Clean", O = "Gold" }, CF_SHOW, 1))[1]:GetAttribute("Asset"),
			"Ore_Gold_Low",
			"no hero: the crowd one shows"
		)
		low.Parent = nil
		MeshKit.reset()
		T.eq(signature(ItemBuilder.build(info, CF_ITEM, 5)), cleanBefore, "no model at all: the recipe, exactly as before")
		hero.Parent = folder
		low.Parent = folder
		MeshKit.reset()
		ItemBuilder.Meshes = false
		local off = signature(ItemBuilder.build(info, CF_ITEM, 5))
		ItemBuilder.Meshes = true
		T.eq(off, cleanBefore, "Meshes off: the recipe, exactly as before")
		T.eq(#meshesOf(ItemBuilder.build(info, CF_ITEM, 5)), 1, "on again")
	end)

	if hadTemplates then
		Loader.mount(MESH_PATH, templates)
		MeshKit.reset()
	else
		Fakes.unmount(Loader)
	end
	ItemBuilder.Meshes = meshesWere
end
