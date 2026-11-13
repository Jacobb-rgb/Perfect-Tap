--[[
	The owner's Meshy models on the plot (docs/plans/MESHY_MODELS_PLAN.md, package C): the plot
	floor (Prop_PlotBase), the podiums (Prop_DisplayPedestal), the museum (Prop_Museum) and the
	cleaning station (Prop_CleaningStation), built with stand-in templates mounted
	(tools/lune/lib/mesh_fakes). Every contract the services and controllers read stays:
	names, PrimaryParts, attributes, tags, attachments and their heights, colliders, budgets.
	(Without an upload the part-built looks are unchanged: PlotService, PlotBorder, PlotStyleA,
	Artifacts, Machines and KitMachines specs.)
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local Enum = roblox.Enum
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local MuseumBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MuseumBuilder")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")
	local CameraFit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Cleaning.CameraFit")

	local CELL = GameConfig.CellSize
	local HALF = GameConfig.PlotCells * CELL / 2

	-- Runs `fn` with the stand-in templates mounted; always takes them away again.
	local function withMeshes(fn: () -> ())
		Fakes(Loader, true)
		local ok, err = pcall(fn)
		Fakes.unmount(Loader)
		if not ok then
			error(err, 0)
		end
	end

	local function meshTest(name: string, fn: () -> ())
		T.test(name, function()
			withMeshes(fn)
		end)
	end

	local function partsOf(root: any): { any }
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function attachment(model: any, name: string): any
		local a = model.PrimaryPart:FindFirstChild(name)
		return if a and a:IsA("Attachment") then a else nil
	end

	-- A part's local box (min, max) in `frame`'s space.
	local function bounds(frame: any, part: any): (any, any)
		local cf = frame:ToObjectSpace(part.CFrame)
		local size = part.Size
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
		local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
		local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		local p = cf.Position
		return p - Vector3.new(hx, hy, hz), p + Vector3.new(hx, hy, hz)
	end

	local function isLook(part: any, asset: string): boolean
		return part:IsA("MeshPart") and part:GetAttribute("Asset") == asset
	end

	-- a look never collides, never takes a ray or a touch
	local function lookOnly(part: any, label: string)
		T.falsy(part.CanCollide, label .. " collides")
		T.falsy(part.CanQuery, label .. " takes rays")
		T.falsy(part.CanTouch, label .. " touches")
		T.truthy(part.Anchored, label .. " anchored")
	end

	local function buildPlot(id: number): any
		local plot = WorldLayout.Plots[id]
		return PlotBuilder.buildPlot(roblox.Instance.new("Folder"), plot, Rng.new(plot.Id)), WorldLayout.plotCFrame(plot)
	end

	---------------------------------------------------------------- the plot floor

	meshTest("PlotMeshes: the plot floor is the owner's model over the pad, the pad stays the collider", function()
		for _, plot in WorldLayout.Plots do
			local model, plotCF = buildPlot(plot.Id)
			T.eq(model.Name, "Plot_" .. plot.Id)
			T.eq(model:GetAttribute("PlotId"), plot.Id, "PlotId")
			T.truthy(model:HasTag("Plot"), "tag Plot")
			local pad = model:FindFirstChild("Pad")
			T.truthy(pad and model.PrimaryPart == pad, "PrimaryPart Pad")
			T.near(pad.Size.X, HALF * 2 + 2, 1e-4, "pad 66 wide")
			T.near(pad.Size.Y, 1.2, 1e-4, "pad 1.2 thick")
			local padMin, padMax = bounds(plotCF, pad)
			T.near(padMax.Y, 0, 1e-4, "pad top at the plot centre")
			T.truthy(pad.CanCollide, "the pad is the collider")
			T.eq(pad.Transparency, 1, "the pad is invisible under the model")
			local floor = model:FindFirstChild("PlotFloor")
			T.truthy(floor and isLook(floor, PlotBuilder.FloorMesh.Name), "the floor model")
			lookOnly(floor, "floor")
			T.falsy(floor.CastShadow, "the floor casts no shadow")
			local min, max = bounds(plotCF, floor)
			T.near(min.X, padMin.X, 1e-3, "covers the pad (x)")
			T.near(max.Z, padMax.Z, 1e-3, "covers the pad (z)")
			-- its inner floor (FloorAt of its height) is level with the pad's top
			local spec = PlotBuilder.FloorMesh
			T.near(min.Y + spec.FloorAt * floor.Size.Y, 0, 1e-3, "inner floor at the pad top")
			-- the frame (0.57 of the model) and the posts (its top) stand low over the grid's outer cells
			local rim = max.Y - (min.Y + spec.FloorAt * floor.Size.Y)
			T.le(rim, 0.45, "the corner posts stay low (a machine's base plate is 0.3)")
			T.lt(0.25, rim, "the frame stands proud of the floor")
			for _, name in { "PlotTile", "Plate", "FloorGlow" } do
				T.falsy(model:FindFirstChild(name), "no flat metal floor: " .. name)
			end
			T.truthy(model:FindFirstChild("Yard"), "the yard")
			T.truthy(model:FindFirstChild("Machines"), "the Machines folder")
			-- nothing else reaches into the build grid (PlotBorder's rule)
			for _, part in partsOf(model) do
				if part ~= pad and part ~= floor then
					local a, b = bounds(plotCF, part)
					local over = a.X < HALF - 0.01 and b.X > -HALF + 0.01 and a.Z < HALF - 0.01 and b.Z > -HALF + 0.01
					T.falsy(over and b.Y > 0.05, `plot {plot.Id}: {part.Name} intrudes into the grid`)
				end
			end
		end
	end)

	meshTest("PlotMeshes: plot and podium budgets hold with the models", function()
		local budget = PlotBuilder.PieceParts
		for _, plot in WorldLayout.Plots do
			local model = buildPlot(plot.Id)
			T.le(#partsOf(model), 300, `plot {plot.Id} parts`)
			for slot = 1, #BaseLayout.Podiums do
				local locked = slot > EconomyConfig.Podiums.Free
				local n = #partsOf(model.Yard:FindFirstChild("Podium" .. slot))
				T.le(n, if locked then budget.PodiumLocked else budget.Podium, `plot {plot.Id} podium {slot}`)
			end
			local seeThrough = 0
			for _, d in partsOf(model) do
				if d.Transparency > 0 and d.Transparency < 1 then
					seeThrough += 1
				end
			end
			T.eq(seeThrough, 0, "nothing see-through")
		end
	end)

	---------------------------------------------------------------- the podiums

	meshTest("PlotMeshes: the podiums stand on the pedestal model and keep what the services read", function()
		local model, plotCF = buildPlot(1)
		local spec = PlotBuilder.PodiumMesh
		for slot, rect in BaseLayout.Podiums do
			local podium = model.Yard:FindFirstChild("Podium" .. slot)
			local locked = slot > EconomyConfig.Podiums.Free
			T.eq(podium:GetAttribute("Slot"), slot, "Slot")
			local base = podium.PrimaryPart
			T.truthy(base and base.Name == "Base" and base:IsA("Part"), "PrimaryPart Base")
			T.eq(base.Shape, Enum.PartType.Cylinder, "a round base")
			T.truthy(base.CanCollide, "the base collides")
			T.eq(base.Transparency, 1, "the base hides inside the model")
			-- the look: the pedestal model, its foot on the yard, as wide as the old base
			local look = podium:FindFirstChild("Pedestal")
			T.truthy(look and isLook(look, spec.Name), "the pedestal model")
			lookOnly(look, "pedestal")
			local min, max = bounds(plotCF, look)
			T.near(min.Y, 0, 1e-3, "stands on the yard")
			T.near((min.X + max.X) / 2, rect.Center.X, 1e-3, "on its slot (x)")
			T.near((min.Z + max.Z) / 2, rect.Center.Z, 1e-3, "on its slot (z)")
			T.le(max.X - min.X, rect.Size.X + 0.01, "inside the slot")
			-- colliders and attachments
			local column, top = podium:FindFirstChild("Column"), podium:FindFirstChild("Top")
			T.truthy(column and column.CanCollide and column.Transparency == 1, "an invisible drum collider")
			T.truthy(top and top:IsA("BasePart") and top.CanCollide and top.Transparency == 1, "an invisible Top collider")
			local _, topMax = bounds(plotCF, top)
			T.near(topMax.Y, max.Y, 0.05, "the Top at the dish's lip")
			local orePoint = (top.CFrame * top.OrePoint.CFrame).Position
			T.near(plotCF:PointToObjectSpace(orePoint).Y, BaseLayout.PodiumOreHeight, 1e-3, "OrePoint height")
			T.truthy(orePoint.Y - (plotCF.Position.Y + topMax.Y) > 0.8, "the ore floats over the dish")
			T.truthy(orePoint.Y - (plotCF.Position.Y + topMax.Y) < 1.4, "not far over it")
			T.truthy(top:FindFirstChild("Prompt"), "Prompt attachment")
			-- the glows the model is painted with: the base ring and the collar Rim
			local glow, rim = podium:FindFirstChild("BaseGlow"), podium:FindFirstChild("Rim")
			T.truthy(glow and glow.Material == Enum.Material.Neon, "BaseGlow")
			T.truthy(rim and rim:IsA("BasePart"), "Rim")
			T.eq(rim.Color, if locked then PlotBuilder.RimLocked else PlotBuilder.RimGold, "rim colour")
			T.eq(rim.Material, if locked then Enum.Material.SmoothPlastic else Enum.Material.Neon, "rim look")
			local rimMin, rimMax = bounds(plotCF, rim)
			T.truthy(rimMax.X - rimMin.X < max.X - min.X, "the rim hugs the collar, inside the model's width")
			T.falsy(podium:FindFirstChild("Band"), "no band (the model has its own)")
			local hover = podium:FindFirstChild("Hover")
			T.truthy(hover and hover.CanQuery and not hover.CanCollide and hover.Transparency == 1, "Hover box")
			local bars = 0
			for _, d in podium:GetChildren() do
				if d.Name == "HoloRing" then
					bars += 1
				end
			end
			T.eq(bars, if locked then 0 else PlotBuilder.HoloRing.Sides, "holo-ring on the free slots")
			if locked then
				local lock = podium:FindFirstChild("Lock")
				T.truthy(lock and lock:FindFirstChild("LockedLight") and lock:FindFirstChild("PriceFrame"), "Lock")
				local plate = podium:FindFirstChild("PricePlate")
				T.truthy(plate, "PricePlate")
				-- in front of the model's lower drum (radius 0.84 of the half width), on its base disc
				local p = plotCF:PointToObjectSpace(plate.CFrame.Position)
				T.truthy(rect.Center.Z - p.Z > 0.84 * spec.Width / 2 + 0.05, "the plate stands clear of the drum")
				T.truthy(rect.Center.Z - p.Z < spec.Width / 2, "on the base disc")
			end
		end
	end)

	meshTest("PlotMeshes: a podium skin paints the glows, PodiumService keeps the Rim", function()
		local model = buildPlot(2)
		local yard = model.Yard
		local podium = yard["Podium1"]
		local rimColor = podium.Rim.Color
		local glowColor = podium.BaseGlow.Color
		local skin = ArtifactConfig.PodiumSkins.Golemworks
		T.lt(0, ArtifactService.paintYard(yard, "Golemworks"), "parts painted")
		T.eq(podium.BaseGlow.Color, skin.Glow, "the base ring in the skin's glow")
		for _, d in podium:GetChildren() do
			if d.Name == "HoloRing" then
				T.eq(d.Color, PlotBuilder.holoTone(skin.Glow), "the holo-ring in the skin's glow")
			end
		end
		T.eq(podium.Rim.Color, rimColor, "the Rim stays PodiumService's")
		ArtifactService.paintYard(yard, nil)
		T.eq(podium.BaseGlow.Color, glowColor, "its own glow back")
	end)

	---------------------------------------------------------------- the museum

	meshTest("PlotMeshes: the museum is the booth model holding the four glass cases", function()
		local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[3])
		local museum = MuseumBuilder.build(plotCF)
		T.eq(museum.Name, MuseumBuilder.Name)
		T.truthy(museum:HasTag(MuseumBuilder.Tag), "tag Museum")
		T.eq(museum:GetAttribute(MuseumBuilder.FoundAttribute), "", "Found")
		local floor = museum.PrimaryPart
		T.truthy(floor and floor.Name == "Floor" and floor:FindFirstChild(MuseumBuilder.PromptName), "Floor with the Prompt")
		local booth = museum:FindFirstChild("Booth")
		T.truthy(booth and isLook(booth, MuseumBuilder.Mesh.Name), "the booth model")
		lookOnly(booth, "booth")
		for _, name in { "Wall", "Roof", "Sign" } do
			T.truthy(museum:FindFirstChild(name), name)
		end
		T.truthy(museum.Wall.CanCollide and museum.Wall.Transparency == 1, "the back wall is an invisible collider")
		local columns = 0
		for _, d in museum:GetChildren() do
			if d.Name == "Column" then
				columns += 1
				T.truthy(d.CanCollide and d.Transparency == 1, "a side wall collider")
			end
		end
		T.eq(columns, 2, "the booth's two side walls collide")
		T.truthy(museum:FindFirstChild("Pieces"), "Pieces")
		local list = partsOf(museum)
		T.le(#list, MuseumBuilder.MaxStructureParts, "structure parts")
		-- inside its yard spot (the booth reaches a little past it on x), under the height budget
		local rect = BaseLayout.Museum
		local boothMin, boothMax = bounds(plotCF, booth)
		for _, part in list do
			local a, b = bounds(plotCF, part)
			-- (the booth and its side wall colliders reach about a stud past the spot on the lane side)
			local slackX = if part == booth or part.Name == "Column" then 1.2 else 0.5
			T.truthy(a.X >= rect.Center.X - rect.Size.X / 2 - slackX and b.X <= rect.Center.X + rect.Size.X / 2 + slackX, part.Name .. " x")
			T.truthy(a.Z >= rect.Center.Z - rect.Size.Z / 2 - 0.5 and b.Z <= rect.Center.Z + rect.Size.Z / 2 + 0.5, part.Name .. " z")
			T.truthy(b.Y <= rect.Size.Y, part.Name .. " height")
		end
		-- the Roof hides inside the booth's roof, the Sign stands on it
		local roofMin, roofMax = bounds(plotCF, museum.Roof)
		T.lt(MuseumBuilder.Mesh.CeilingY, roofMin.Y, "the roof slab over the ceiling")
		T.lt(roofMax.Y, boothMax.Y, "inside the booth's roof")
		local signMin = bounds(plotCF, museum.Sign)
		T.near(signMin.Y, boothMax.Y + 0.15, 0.01, "the sign on the booth's roof")
		-- the four cases: one per collection, in collection order, their pedestals one counter
		local cases = MuseumBuilder.cases()
		T.eq(#cases, #ArtifactConfig.Collections, "a case per collection")
		local penBack = BaseLayout.Pen.Area.Center.Z + BaseLayout.Pen.Area.Size.Z / 2
		local counterTop = -math.huge
		local edges = {}
		for i, info in cases do
			local case = museum:FindFirstChild("Case" .. i)
			T.truthy(case, "Case" .. i)
			T.eq(case:GetAttribute("Collection"), info.Collection, "Collection")
			local pedestal = case.PrimaryPart
			T.truthy(pedestal and pedestal.Name == "Pedestal" and pedestal.CanCollide, "Pedestal")
			for _, name in { "Strip", "Shelf", "Glass", "Cap" } do
				T.truthy(case:FindFirstChild(name), name)
			end
			local label = case.Plaque.FaceFront.Text
			T.truthy(label:IsA("TextLabel") and label.Text:find("0 / 6", 1, true), "the plaque")
			local a, b = bounds(plotCF, pedestal)
			counterTop = math.max(counterTop, b.Y)
			table.insert(edges, { a.X, b.X })
			T.near(a.Z - penBack, 4, 1e-3, "the walkway: 4 studs from the pen to the counter")
			T.near(b.Y, info.Center.Y, 1e-3, "the case stands on its pedestal")
			-- the cases' glass and caps stay inside the booth's side walls and under its ceiling
			local ga, gb = bounds(plotCF, case.Cap)
			T.lt(gb.Y, MuseumBuilder.Mesh.CeilingY, "the cap under the ceiling")
			T.truthy(ga.X > boothMin.X and gb.X < boothMax.X, "inside the booth")
		end
		for i = 2, #edges do
			T.near(edges[i][2], edges[i - 1][1], 1e-3, "the pedestals meet as one counter")
		end
		-- the booth's own three cases (their tops at 1.53 of 2.4595 of its height) hide in the counter
		local caseTop = boothMin.Y + 1.53 / 2.4595 * (boothMax.Y - boothMin.Y)
		T.lt(caseTop, counterTop, "the booth's cases end under the counter's top")
		-- the relics on their spots, inside their glass, facing the visitors
		local all = { Found = {}, Chapters = {} }
		for _, art in ArtifactConfig.List do
			all.Found[art.Id] = 1
		end
		T.eq(MuseumBuilder.show(museum, plotCF, all), #ArtifactConfig.List, "every relic shows")
		for _, piece in museum.Pieces:GetChildren() do
			local p = plotCF:PointToObjectSpace(piece:GetPivot().Position)
			T.truthy(p.Y >= counterTop - 1e-3, piece.Name .. " on the counter")
			T.truthy(p.X > boothMin.X and p.X < boothMax.X, piece.Name .. " inside the booth")
		end
		-- the prompt on the walkway, in front of the counter
		local point = floor:FindFirstChild(MuseumBuilder.PromptName)
		local prompt = plotCF:PointToObjectSpace((floor.CFrame * point.CFrame).Position)
		T.truthy(prompt.Z > penBack and prompt.Z < penBack + 4, "the prompt on the walkway")
	end)

	---------------------------------------------------------------- the cleaning station

	meshTest("PlotMeshes: the cleaning station is the owner's model with every machine point", function()
		local info = MachineData.ById.CleaningStation
		local hw, hd = info.Size[1] * CELL / 2, info.Size[2] * CELL / 2
		local spec = KitMachines.StationMesh
		for level = 0, KitMachines.MaxLevel do
			local model = KitMachines.build("CleaningStation", level)
			local tag = "L" .. level
			T.eq(model:GetAttribute("MachineId"), "CleaningStation", tag)
			local base = model.PrimaryPart
			T.truthy(base and base.Name == "Base", tag .. " PrimaryPart Base")
			local look = model:FindFirstChild("Station")
			T.truthy(look and isLook(look, spec.Name), tag .. " the station model")
			lookOnly(look, tag .. " station")
			for _, name in { "OrePoint", "CamPoint", "Output", "Prompt", "Intake", "WaterOut", "WaterIn", "Status" } do
				T.truthy(attachment(model, name), tag .. " " .. name)
			end
			T.eq(typeof(attachment(model, "Intake"):GetAttribute("IntakeSize")), "Vector3", tag .. " IntakeSize")
			for _, part in partsOf(model) do
				T.truthy(part.Anchored, tag .. " " .. part.Name .. " anchored")
				T.truthy(part:GetAttribute("Kit") ~= nil, tag .. " " .. part.Name .. " has a Kit role")
				local a, b = bounds(CFrame.new(), part)
				if part:GetAttribute("Kit") ~= "Crystal" then
					T.truthy(
						math.max(-a.X, b.X) <= hw + 0.35 and math.max(-a.Z, b.Z) <= hd + 0.35,
						tag .. " " .. part.Name .. " in the footprint"
					)
				end
			end
		end
	end)

	meshTest("PlotMeshes: the station's minigame: the ore on the conveyor, the camera in front of it", function()
		local model = MachineBuilder.build("CleaningStation", 0, 0)
		local base = model.PrimaryPart
		local ore = attachment(model, "OrePoint").CFrame.Position
		local cam = attachment(model, "CamPoint").CFrame
		-- the conveyor's top is the Bench collider's top; the mounted raw ore (0.55 under the
		-- point) and the minigame clump (radius ~1.25) rest on it
		local bench = model:FindFirstChild("Bench")
		T.truthy(bench and bench.CanCollide and bench.Transparency == 1, "an invisible bench collider")
		local _, benchMax = bounds(base.CFrame, bench)
		T.near(ore.Y - benchMax.Y, 1.3, 0.05, "the ore sits on the conveyor")
		local benchMin = bounds(base.CFrame, bench)
		T.truthy(ore.Z > benchMin.Z and ore.Z < benchMax.Z, "over the bench")
		-- the close-up: looking at the ore from the front, as far as on the part-built station
		local toOre = (ore + Vector3.new(0, 0.1, 0)) - cam.Position
		T.near(cam.LookVector:Dot(toOre.Unit), 1, 1e-4, "the camera looks at the ore")
		T.near((cam.Position - ore).Magnitude, math.sqrt(3.45 ^ 2 + 4.9 ^ 2), 1e-3, "the camera's distance")
		T.truthy(cam.Position.Z < ore.Z - 4 and cam.Position.Y > ore.Y + 3, "out in front, above")
		T.truthy(cam.Position.Z < -bench.Size.Z / 2, "in front of the bench")
		-- the camera fit puts the ore in the middle of the screen's free area
		local fitCF, fov = CameraFit.compute({
			ViewportHeight = 900,
			InsetTop = 36,
			FreeTop = 60,
			FreeBottom = 120,
			UiScale = 1,
			Outline = { roblox.Vector2.new(-1, -1), roblox.Vector2.new(1, -1), roblox.Vector2.new(1, 1), roblox.Vector2.new(-1, 1) },
			FaceScale = 1.25,
			CamPoint = base.CFrame * cam,
			OrePoint = (base.CFrame * CFrame.new(ore)).Position,
		})
		local sx, sy = CameraFit.screenPoint(fitCF, fov, 1600, 900, (base.CFrame * CFrame.new(ore)).Position)
		T.truthy(sx > 600 and sx < 1000 and sy > 250 and sy < 650, `the ore on screen ({sx}, {sy})`)
		-- the vise's intake round the ore point
		T.truthy((attachment(model, "Intake").CFrame.Position - ore).Magnitude < 1e-4, "the intake at the ore")
		-- the washer's shower: it falls onto the belt behind the ore, never between it and the camera
		local out, into = attachment(model, "WaterOut"), attachment(model, "WaterIn")
		local a, b = out.CFrame.Position, into.CFrame.Position
		T.truthy(a.Y > b.Y + 0.8, "the water falls")
		T.eq(out:GetAttribute("Spray"), true, "the washer sprays")
		T.eq(type(out:GetAttribute("Curve")), "number", "WaterOut Curve")
		T.eq(type(into:GetAttribute("Curve")), "number", "WaterIn Curve")
		T.truthy(b.Z > ore.Z + 0.5, "the shower is behind the ore")
		T.near(b.Y, benchMax.Y, 0.1, "it lands on the belt")
		-- a kept clean ore drops from Output onto the trays' collider
		local output = attachment(model, "Output").CFrame.Position
		local tray = model:FindFirstChild("Tray")
		T.truthy(tray and tray.CanCollide, "a tray collider")
		local ta, tb = bounds(base.CFrame, tray)
		T.truthy(output.X > ta.X and output.X < tb.X and output.Z > ta.Z and output.Z < tb.Z, "Output over the tray")
		T.truthy(output.Y > tb.Y, "Output above the tray's floor")
		-- the prompt in front of the bench
		local prompt = attachment(model, "Prompt").CFrame.Position
		T.truthy(prompt.Z < benchMin.Z, "the prompt in front of the bench")
	end)

	meshTest("PlotMeshes: the station's upgrades still grow crystals and turn its glow", function()
		local previous = -1
		local theme = KitMachines.Themes[KitMachines.DefaultTheme]
		for level = 0, KitMachines.MaxLevel do
			local model = KitMachines.build("CleaningStation", level)
			local crystals = 0
			for _, part in partsOf(model) do
				if part:GetAttribute("Kit") == "Crystal" then
					crystals += 1
				end
			end
			if level == 0 then
				T.eq(crystals, 0, "L0 plain")
			else
				T.lt(previous, crystals, "L" .. level .. " more crystals")
			end
			previous = crystals
			local glow = model:FindFirstChild("FootGlow")
			T.truthy(glow and glow.Material == Enum.Material.Neon, "the glowing strip at its foot")
			if level >= 2 then
				T.eq(glow.Color, theme.Main, "L" .. level .. " the glow turns crystal")
			else
				T.eq(glow.Color, KitMachines.Palette.Neon, "L" .. level .. " the orange glow")
			end
		end
	end)

	---------------------------------------------------------------- no upload: the old looks

	T.test("PlotMeshes: without the templates every builder keeps its part-built look", function()
		local model = buildPlot(1)
		T.falsy(model:FindFirstChild("PlotFloor"), "no floor model")
		T.truthy(model:FindFirstChild("PlotTile"), "the metal floor")
		T.eq(model.Pad.Transparency, 0, "the pad shows")
		T.falsy(model.Yard.Podium1:FindFirstChild("Pedestal"), "no pedestal model")
		T.truthy(model.Yard.Podium1:FindFirstChild("Band"), "the part-built podium")
		local museum = MuseumBuilder.build(WorldLayout.plotCFrame(WorldLayout.Plots[1]))
		T.falsy(museum:FindFirstChild("Booth"), "no booth model")
		T.truthy(museum:FindFirstChild("Backdrop"), "the lean-to")
		local station = KitMachines.build("CleaningStation", 0)
		T.falsy(station:FindFirstChild("Station"), "no station model")
		T.truthy(station:FindFirstChild("WaterPool"), "the part-built station")
	end)
end
