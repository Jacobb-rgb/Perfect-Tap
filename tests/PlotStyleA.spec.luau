--[[
	The plot pieces in the machines' style A "Soft" (owner 2026-10-20, ported
	from the preview on art/plot-style-a): the pad walls and the yard fence,
	the Ore Pen, the podiums and the train stop (PlotBuilder), the Foundry
	building and the FOUNDRY chute receiver (FoundryBuilder). They keep every
	name, attribute and attachment the services and controllers read
	(PlotService, PenService, PodiumService / PodiumController,
	ArtifactService's podium skins, FoundryService / FoundryController,
	IntakeService, the railway) and use no more parts than the brick / Kenney
	look did (PlotBuilder.PieceParts, FoundryBuilder.BuildingParts).
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Enum = roblox.Enum
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
	local SoftKit = Loader.requirePath("ReplicatedStorage.Shared.Builders.SoftKit")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local FoundryBuilder = Loader.requirePath("ServerScriptService.Server.World.FoundryBuilder")
	local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")

	local P = KitMachines.Palette

	local function buildPlot(plot: any): any
		return PlotBuilder.buildPlot(roblox.Instance.new("Folder"), plot, Rng.new(plot.Id))
	end

	-- BaseParts under `root` (without the rack's Silhouette, which setRack rebuilds)
	local function partsOf(root: any): { any }
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and not d:FindFirstAncestor("Silhouette") then
				table.insert(list, d)
			end
		end
		return list
	end

	-- every part in a palette role shows that role's colour (KitMachines.style)
	local function checkRoles(root: any)
		local roles = 0
		for _, d in partsOf(root) do
			local role = d:GetAttribute("Kit")
			if role then
				roles += 1
				T.truthy(P[role] ~= nil, `{d:GetFullName()}: Kit role {role} is a KitMachines.Palette key`)
				T.eq(d.Color, P[role], `{d:GetFullName()} in the {role} colour`)
			end
		end
		T.lt(0, roles, `{root.Name}: parts in palette roles`)
	end

	local function labelOf(part: any): any
		local gui = part and part:FindFirstChildWhichIsA("SurfaceGui")
		return gui and gui:FindFirstChild("Text")
	end

	T.test("Style A: every plot piece stays at or under the brick look's part count", function()
		local budget = PlotBuilder.PieceParts
		for _, plot in WorldLayout.Plots do
			local model = buildPlot(plot)
			local yard = model.Yard
			T.le(#partsOf(model.Walls), budget.Walls, `plot {plot.Id} pad walls`)
			T.le(#partsOf(yard.Fence), budget.Fence, `plot {plot.Id} yard fence`)
			T.le(#partsOf(yard.Pen), budget.Pen, `plot {plot.Id} Ore Pen`)
			for slot = 1, #BaseLayout.Podiums do
				local locked = slot > EconomyConfig.Podiums.Free
				local n = #partsOf(yard:FindFirstChild("Podium" .. slot))
				T.le(n, if locked then budget.PodiumLocked else budget.Podium, `plot {plot.Id} podium {slot}`)
			end
			T.le(#partsOf(yard.TrainStop), budget.TrainStop, `plot {plot.Id} train stop (with the Track placeholder)`)
			-- the whole plot: 300 before style A, now with room to spare
			T.le(#partsOf(model), 260, `plot {plot.Id} parts`)
		end
	end)

	T.test("Style A: the plot pieces keep the names, attributes and attachments the services read", function()
		local plot = WorldLayout.Plots[3]
		local model = buildPlot(plot)
		local plotCF = WorldLayout.plotCFrame(plot)
		local yard = model.Yard
		-- PlotService.setSignText: the PlotSign's Text label; TrainService: the Banner
		local sign = model:FindFirstChild("PlotSign")
		T.truthy(sign and sign:IsA("BasePart"), "PlotSign")
		local text = sign:FindFirstChild("Text", true)
		T.truthy(text and text:IsA("TextLabel") and text.Text == "Free Plot", "the sign's Text label")
		T.eq(sign.Color, P.Frame, "a slate sign")
		T.truthy(model:FindFirstChild("Banner", true), "the banner (the trains' colour)")
		-- the plot's only light hangs in the left road entrance post's lamp ball
		local lights = {}
		for _, d in model:GetDescendants() do
			if d:IsA("Light") then
				table.insert(lights, d)
			end
		end
		T.eq(#lights, 1, "one light")
		local lamp = lights[1].Parent
		T.eq(lamp.Name, "Lamp", "in a lamp ball")
		T.eq(lamp.Parent, model.Walls, "on the pad walls")
		local at = plotCF:PointToObjectSpace(lamp.CFrame.Position)
		T.lt(at.X, -PlotBuilder.EntranceHalf, "the left entrance post")
		T.lt(at.Z, -PlotBuilder.WallLine, "on the road side")
		-- the Ore Pen (PenService): the invisible Intake with its Prompt attachment
		local intake = yard.Pen:FindFirstChild("Intake")
		T.truthy(intake and intake:IsA("BasePart") and intake.Transparency == 1, "Pen.Intake")
		T.truthy(intake:FindFirstChild("Prompt") and intake.Prompt:IsA("Attachment"), "Pen.Intake.Prompt")
		T.truthy(labelOf(yard.Pen:FindFirstChild("Sign")).Text == "ORE PEN", "the ORE PEN sign")
		-- the podiums (PodiumService, PodiumController, ArtifactService)
		for slot = 1, #BaseLayout.Podiums do
			local podium = yard:FindFirstChild("Podium" .. slot)
			local locked = slot > EconomyConfig.Podiums.Free
			T.eq(podium:GetAttribute("Slot"), slot, "Slot attribute")
			T.eq(podium.PrimaryPart, podium:FindFirstChild("Base"), "PrimaryPart Base")
			for _, name in { "Base", "Column", "Top", "Rim", "Hover" } do
				local part = podium:FindFirstChild(name)
				T.truthy(part and part:IsA("BasePart") and part.Parent == podium, `podium {slot} {name} (a direct child)`)
			end
			T.truthy(podium.Top:FindFirstChild("OrePoint") and podium.Top:FindFirstChild("Prompt"), "OrePoint and Prompt on the Top")
			local bars = 0
			for _, d in podium:GetChildren() do
				if d.Name == "HoloRing" then
					bars += 1
				end
			end
			T.eq(bars, if locked then 0 else PlotBuilder.HoloRing.Sides, "the holo-ring bars (none on a locked slot)")
			T.eq(podium:FindFirstChild("Lock") ~= nil, locked, "Lock on the locked slots")
			if locked then
				T.truthy(podium.Lock:FindFirstChild("LockedLight"), "the lock's red light")
				T.truthy(podium.Lock:FindFirstChild("PriceFrame"), "the price frame hides with the lock")
				local plate = podium:FindFirstChild("PricePlate")
				T.truthy(plate and plate:FindFirstChildOfClass("SurfaceGui"), "PricePlate with its SurfaceGui")
				T.eq(labelOf(plate).Text, "100 R$", "the price")
			end
			-- ArtifactService tells the skin roles of Base, Column and Top apart by their own colours
			local a, b, c = podium.Base.Color, podium.Column.Color, podium.Top.Color
			T.truthy(a ~= b and b ~= c and a ~= c, "Base, Column and Top in three colours")
		end
		-- the train stop: a solid platform, the TRAIN STOP sign, the railway's placeholder track
		local stop = yard.TrainStop
		local platform = stop:FindFirstChild("Platform")
		T.truthy(platform and platform.CanCollide and platform.CanQuery, "a solid platform")
		local stopSign = stop:FindFirstChild("Sign")
		T.eq(labelOf(stopSign).Text, "TRAIN STOP", "the TRAIN STOP sign")
		local track = stop:FindFirstChild("Track")
		T.truthy(track and track:GetAttribute("RailwayPlaceholder") == true and track:FindFirstChild("BufferStop"), "the Track placeholder")
		-- the walls and pieces in KitMachines' palette roles
		for _, root in { model.Walls, yard.Fence, yard.Pen, yard.Podium1, stop } do
			checkRoles(root)
		end
	end)

	T.test("Style A: ArtifactService paints the podium skins on the soft podiums and takes them off", function()
		local model = buildPlot(WorldLayout.Plots[2])
		local yard = model.Yard
		-- a free podium (the holo-ring) and a locked one (the padlock, no ring)
		local podium = yard["Podium" .. EconomyConfig.Podiums.Free]
		local lockedPodium = yard["Podium" .. EconomyConfig.Podiums.Free + 1]
		-- (a list: Lune hands out a new wrapper per lookup, so instances make poor table keys)
		local own: { { Part: any, Color: any } } = {}
		local rimColor, lockColors = podium.Rim.Color, {}
		for _, root in { podium, lockedPodium } do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(own, { Part = d, Color = d.Color })
					if d:FindFirstAncestor("Lock") then
						table.insert(lockColors, { Part = d, Color = d.Color })
					end
				end
			end
		end
		local skin = ArtifactConfig.PodiumSkins.Golemworks
		T.lt(0, ArtifactService.paintYard(yard, "Golemworks"), "parts painted")
		T.eq(podium.Base.Color, skin.Base, "the base in the skin's base")
		T.eq(podium.Top.Color, skin.Trim, "the top in the skin's trim")
		T.eq(podium.Column.Color, skin.Base:Lerp(roblox.Color3.new(1, 1, 1), 0.12), "the drum a little lighter")
		T.eq(podium.Band.Color, skin.Trim, "the orange band takes the trim")
		T.eq(podium.BaseGlow.Color, skin.Glow, "the glow ring takes the glow")
		for _, d in podium:GetChildren() do
			if d.Name == "HoloRing" then
				T.eq(d.Color, PlotBuilder.holoTone(skin.Glow), "the holo-ring in the skin's glow, toned")
			end
		end
		T.eq(podium.Rim.Color, rimColor, "the Rim stays PodiumService's")
		T.lt(0, #lockColors, "the lock's parts")
		for _, entry in lockColors do
			T.eq(entry.Part.Color, entry.Color, "the lock keeps its colours")
		end
		ArtifactService.paintYard(yard, nil)
		for _, entry in own do
			T.eq(entry.Part.Color, entry.Color, `{entry.Part.Name}: its own colour back`)
		end
	end)

	T.test("Style A: the Foundry keeps FoundryService's contract with no more parts than the Kenney look", function()
		local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[4])
		local building = FoundryBuilder.build(plotCF, 2)
		T.le(#partsOf(building), FoundryBuilder.BuildingParts, "the building without the silhouette")
		local base = building.PrimaryPart
		T.eq(base and base.Name, "Base", "PrimaryPart Base")
		for _, name in { "AnvilPoint", "CamPoint", "Prompt", "HopperIn", "HopperOut", "RackMount" } do
			T.truthy(base:FindFirstChild(name) and base[name]:IsA("Attachment"), "attachment " .. name)
		end
		for _, name in { "Intake", "RackBoard", "RackSign", "HopperFloor", "Anvil", "Sign" } do
			T.truthy(building:FindFirstChild(name), name)
		end
		T.truthy(building.RackBoard:FindFirstChild("Mystery"), "the rack's ? (COMING SOON)")
		T.eq(labelOf(building.RackSign).Text, "NEXT: LV 2", "the rack sign")
		local faces = 0
		for _, gui in building.Sign:GetChildren() do
			if gui:IsA("SurfaceGui") and gui:FindFirstChild("Text") and gui.Text.Text == "FOUNDRY" then
				faces += 1
			end
		end
		T.eq(faces, 2, "FOUNDRY on both faces (the yard and the trains)")
		-- what FoundryController pulses and blinks
		local warn, glow, molten = 0, 0, 0
		for _, d in partsOf(building) do
			if d.Name == "WarnLight" then
				warn += 1
			elseif d.Name == "Glow" then
				glow += 1
			elseif d.Name == "Molten" then
				molten += 1
			end
			if d.Name == "WarnLight" or d.Name == "Glow" or d.Name == "Molten" then
				T.eq(d.Material, Enum.Material.Neon, d.Name .. " glows")
			end
		end
		T.eq(warn, 2, "two warning beacons")
		T.le(2, glow, "the furnace door glows")
		T.le(6, molten, "molten metal in the pipes, the channel and the mould")
		local chimney = building:FindFirstChild("ChimneyTop", true)
		T.truthy(chimney and chimney:FindFirstChild("Smoke") and chimney.Smoke:IsA("ParticleEmitter"), "the chimney smokes")
		checkRoles(building)
		-- setRack still rebuilds the silhouette and the sign on the style A rack
		FoundryBuilder.setRack(building, 3)
		T.truthy(building:FindFirstChild("Silhouette"), "the next blaster's silhouette")
		T.eq(labelOf(building.RackSign).Text, "NEXT: LV 3")
		FoundryBuilder.setRack(building, BlasterData.MaxLevel + 1)
		T.eq(labelOf(building.RackSign).Text, "COMING SOON")
	end)

	T.test("Style A: the FOUNDRY chute receiver keeps its Hood, Mouth and PenFull sign, no more parts", function()
		local receiver = FoundryBuilder.receiver(WorldLayout.plotCFrame(WorldLayout.Plots[4]))
		T.le(#partsOf(receiver), 8, "receiver parts (8 before style A)")
		local hood = receiver.PrimaryPart
		T.eq(hood and hood.Name, "Hood", "PrimaryPart Hood")
		T.eq(hood.Color, P.Frame, "a slate hood")
		T.truthy(hood:FindFirstChild("Mouth") and hood.Mouth:IsA("Attachment"), "the Mouth attachment")
		T.truthy(hood:FindFirstChild("PenFull") and hood.PenFull:IsA("BillboardGui"), "the PenFull sign")
		local throat = receiver:FindFirstChild("Glow")
		T.truthy(throat and throat.Material == Enum.Material.Neon, "the glowing throat")
		checkRoles(receiver)
	end)

	T.test("SoftKit: hazard stripes keep each gradient within a ColorSequence's 20 keypoints, from 0 to 1", function()
		local board = roblox.Instance.new("Part")
		local gui = SoftKit.paint(board, Enum.NormalId.Top, { { x = 0, y = 0, w = 1, h = 1, color = P.Trim, stripes = 68 } })
		local stripes, width = 0, 0
		for _, frame in gui:GetChildren() do
			local gradient = frame:FindFirstChildOfClass("UIGradient")
			T.truthy(gradient, "a gradient per stripes frame")
			local keys = gradient.Color.Keypoints
			T.le(#keys, 20, "at most 20 keypoints")
			T.eq(keys[1].Time, 0, "from 0")
			T.eq(keys[#keys].Time, 1, "to 1")
			stripes += #keys / 2
			width += frame.Size.X.Scale
		end
		T.eq(stripes, 68, "every stripe drawn")
		T.near(width, 1, 1e-6, "the frames cover the face")
	end)
end
