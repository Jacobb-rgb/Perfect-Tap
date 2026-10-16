-- PlotService grid helpers: footprint CFrames match the old maths, cells
-- round-trip, and plotAt / isNear find the right plot.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")

	local CELL = GameConfig.CellSize
	local CELLS = GameConfig.PlotCells
	local HALF = CELLS * CELL / 2

	local function sameCFrame(a: any, b: any, label: string)
		local ac, bc = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do
			T.near(ac[i], bc[i], 1e-4, label .. " component " .. i)
		end
	end

	T.test("PlotService: footprintCFrame matches the step c formula", function()
		for _, plot in WorldLayout.Plots do
			for _, machine in MachineData.List do
				for r = 0, 3 do
					local gx, gz = 2, 3
					local w, d = MachineData.footprint(machine, r)
					local old = PlotService.plotCFrame(plot.Id)
						* CFrame.new(-HALF + (gx + w / 2) * CELL, 0, -HALF + (gz + d / 2) * CELL)
						* CFrame.Angles(0, -r * math.pi / 2, 0)
					sameCFrame(PlotService.footprintCFrame(plot.Id, machine.Id, gx, gz, r), old, `{machine.Id} r{r}`)
				end
			end
		end
	end)

	T.test("PlotService: cellAt round-trips every cell centre", function()
		for _, plot in WorldLayout.Plots do
			local cf = PlotService.plotCFrame(plot.Id)
			for z = 0, CELLS - 1 do
				for x = 0, CELLS - 1 do
					local world = cf:PointToWorldSpace(Vector3.new(-HALF + (x + 0.5) * CELL, 1, -HALF + (z + 0.5) * CELL))
					local cx, cz = PlotService.cellAt(plot.Id, world)
					T.eq(cx, x, "cell x")
					T.eq(cz, z, "cell z")
				end
			end
			local outside = cf:PointToWorldSpace(Vector3.new(HALF + 0.5, 1, 0))
			T.eq(PlotService.cellAt(plot.Id, outside), nil, "border is not a cell")
		end
	end)

	T.test("PlotService: plotAt finds the plot and its local position", function()
		for _, plot in WorldLayout.Plots do
			local cf = PlotService.plotCFrame(plot.Id)
			for _, p in { Vector3.new(0, 1, 0), Vector3.new(HALF - 0.1, 0.5, -HALF + 0.1), Vector3.new(-HALF + 0.1, 20, HALF - 0.1) } do
				local id, localPos = PlotService.plotAt(cf:PointToWorldSpace(p))
				T.eq(id, plot.Id, "plot id")
				T.near((localPos - p).Magnitude, 0, 1e-3, "local position")
			end
			-- too high, too low, or beyond the pad
			T.eq(PlotService.plotAt(cf:PointToWorldSpace(Vector3.new(0, 30, 0))), nil, "far above")
			T.eq(PlotService.plotAt(cf:PointToWorldSpace(Vector3.new(0, -5, 0))), nil, "below")
			T.eq(PlotService.plotAt(cf:PointToWorldSpace(Vector3.new(HALF + 3, 1, 0))), nil, "beside the pad")
		end
		T.eq(PlotService.plotAt(Vector3.new(0, 1, 0)), nil, "town square")
	end)

	T.test("PlotService: plot grids line up with Grid.localCFrame", function()
		-- a machine's footprint centre is over its own min cell's plot
		for _, plot in WorldLayout.Plots do
			local world = PlotService.footprintCFrame(plot.Id, "ClayFurnace", 0, 0, 0).Position
			local id, localPos = PlotService.plotAt(world + Vector3.new(0, 1, 0))
			T.eq(id, plot.Id, "plot")
			local x, z = Grid.cellFromLocal(localPos - Vector3.new(CELL / 2, 0, CELL / 2))
			T.eq(x, 0, "min cell x")
			T.eq(z, 0, "min cell z")
		end
	end)

	T.test("PlotService: isNear measures from the plot centre, flat", function()
		local plot = WorldLayout.Plots[3]
		local function playerAt(position: any): any
			local root = { Position = position }
			return {
				Character = {
					FindFirstChild = function(_, name: string)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
			}
		end
		T.truthy(PlotService.isNear(playerAt(plot.Center + Vector3.new(30, 50, 40)), plot.Id, 70), "50 studs flat, high up")
		T.falsy(PlotService.isNear(playerAt(plot.Center + Vector3.new(60, 0, 40)), plot.Id, 70), "72 studs away")
		T.falsy(PlotService.isNear({ Character = nil }, plot.Id, 70), "no character")
	end)

	---------------------------------------------------------------- base yard (WP-Base)

	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local EconomyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EconomyConfig")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	local function buildPlot(plot: any): any
		local folder = roblox.Instance.new("Folder")
		return PlotBuilder.buildPlot(folder, plot, Rng.new(plot.Id))
	end

	local function localPoint(plot: any, part: any, attachment: any): any
		local world = part.CFrame * attachment.CFrame
		return WorldLayout.plotCFrame(plot):PointToObjectSpace(world.Position)
	end

	T.test("Yard: every plot has the pen, 4 podiums, foundry and train stop, named for the services", function()
		for _, plot in WorldLayout.Plots do
			local model = buildPlot(plot)
			local yard = model:FindFirstChild("Yard")
			T.truthy(yard, "Yard")
			for _, name in { "Ground", "Fence", "Pen", "Foundry", "TrainStop" } do
				T.truthy(yard:FindFirstChild(name), `plot {plot.Id} {name}`)
			end
			local intake = yard.Pen:FindFirstChild("Intake")
			T.truthy(intake and intake:IsA("BasePart"), "Pen.Intake part")
			T.eq(intake.Transparency, 1, "intake invisible")
			T.falsy(intake.CanCollide, "intake doesn't collide")
			T.falsy(intake.CanQuery, "intake not queryable")
			local box = BaseLayout.Pen.Intake
			local center = WorldLayout.plotCFrame(plot):PointToObjectSpace(intake.CFrame.Position)
			T.near(center.X, box.Center.X, 1e-3, "intake x")
			T.near(center.Z, box.Center.Z, 1e-3, "intake z")
			T.near(intake.Size.X, box.Size.X, 1e-3, "intake width")
			T.near(intake.Size.Z, box.Size.Z, 1e-3, "intake depth")
			T.le(center.Y - intake.Size.Y / 2, 0, "intake reaches the ground")
			T.le(box.Size.Y, center.Y + intake.Size.Y / 2, "intake is tall enough")
			local prompt = intake:FindFirstChild("Prompt")
			T.truthy(prompt and prompt:IsA("Attachment"), "pen Prompt attachment")
			local p = localPoint(plot, intake, prompt)
			T.near((p - BaseLayout.Pen.PromptPoint).Magnitude, 0, 1e-3, "prompt at Pen.PromptPoint")
			for slot, rect in BaseLayout.Podiums do
				local podium = yard:FindFirstChild("Podium" .. slot)
				T.truthy(podium, "Podium" .. slot)
				local top = podium:FindFirstChild("Top")
				T.truthy(top and top:IsA("BasePart"), "Top part")
				local orePoint = top:FindFirstChild("OrePoint")
				T.truthy(orePoint and orePoint:IsA("Attachment"), "OrePoint")
				local op = localPoint(plot, top, orePoint)
				T.near(op.X, rect.Center.X, 1e-3, "ore point x")
				T.near(op.Z, rect.Center.Z, 1e-3, "ore point z")
				T.near(op.Y, BaseLayout.PodiumOreHeight, 1e-3, "ore point height")
				T.truthy(top:FindFirstChild("Prompt"), "podium Prompt attachment")
				local locked = slot > EconomyConfig.Podiums.Free
				T.eq(podium:FindFirstChild("Lock") ~= nil, locked, "lock on slot " .. slot)
				T.eq(podium:FindFirstChild("PricePlate") ~= nil, locked, "price plate on slot " .. slot)
				if locked then
					local label = podium.PricePlate:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
					T.eq(label.Text, "100 R$", "price text")
				end
			end
		end
	end)

	-- Plot-local axis-aligned bounds of a part: (min, max).
	local function localBounds(plotCF: any, part: any): (any, any)
		local cf = plotCF:ToObjectSpace(part.CFrame)
		local size = part.Size
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local half = Vector3.new(
			math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2,
			math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2,
			math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		)
		return cf.Position - half, cf.Position + half
	end

	T.test("Plot: part budget (pad + yard), one light, shadows", function()
		for _, plot in WorldLayout.Plots do
			local model = buildPlot(plot)
			local parts, collide, lights = 0, 0, 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					if d.CanCollide then
						collide += 1
					end
					local s = d.Size
					if s.X * s.Y * s.Z < 1 and d.Transparency < 1 then
						T.falsy(d.CastShadow, `small part {d:GetFullName()} casts a shadow`)
					end
				elseif d:IsA("Light") then
					lights += 1
				end
			end
			-- mobile budget: 8 plots stream in with the lobby (LobbyLayout.Budget)
			T.le(parts, 300, `plot {plot.Id} parts (pad + yard)`)
			T.le(lights, 1, `plot {plot.Id} lights`)
			T.lt(collide, parts, "decoration doesn't collide")
		end
	end)

	T.test("Plot: the road entrance and the YardGate stay open", function()
		local plot = WorldLayout.Plots[1]
		local model = buildPlot(plot)
		local plotCF = WorldLayout.plotCFrame(plot)
		local line = PlotBuilder.WallLine
		local gate = BaseLayout.YardGate
		-- walkable corridors (plot-local x range, z range), from the ground to head height
		local corridors = {
			{ Name = "road entrance", X0 = -PlotBuilder.EntranceHalf, X1 = PlotBuilder.EntranceHalf, Z0 = -line - 3, Z1 = -line + 2 },
			{ Name = "yard gate", X0 = gate.CenterX - gate.Width / 2, X1 = gate.CenterX + gate.Width / 2, Z0 = line - 2, Z1 = line + 2 },
		}
		T.lt(gate.Width - 0.1, PlotBuilder.EntranceHalf * 2, "the entrance is at least as wide as the yard gate")
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				local min, max = localBounds(plotCF, d)
				if max.Y > 0.05 and min.Y < 6 then
					for _, c in corridors do
						local blocks = min.X < c.X1 - 0.01 and max.X > c.X0 + 0.01 and min.Z < c.Z1 and max.Z > c.Z0
						T.falsy(blocks, `{d:GetFullName()} blocks the {c.Name}`)
					end
				end
			end
		end
	end)

	T.test("Plot: brick walls close the border of pad and yard, except the openings", function()
		local plot = WorldLayout.Plots[2]
		local model = buildPlot(plot)
		local plotCF = WorldLayout.plotCFrame(plot)
		T.truthy(model:FindFirstChild("Walls"), "pad walls")
		local solids = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d.Transparency < 1 then
				table.insert(solids, d)
			end
		end
		local function blocked(p: any): boolean
			local world = plotCF:PointToWorldSpace(p)
			for _, part in solids do
				local q = part.CFrame:PointToObjectSpace(world)
				local h = part.Size / 2
				if math.abs(q.X) <= h.X + 0.01 and math.abs(q.Y) <= h.Y + 0.01 and math.abs(q.Z) <= h.Z + 0.01 then
					return true
				end
			end
			return false
		end
		local line = PlotBuilder.WallLine
		local back = PlotBuilder.BackWallZ
		local gate = BaseLayout.YardGate
		local stopHalf = BaseLayout.TrainStop.Size.X / 2
		local samples = 0
		local function check(x: number, z: number, label: string)
			samples += 1
			T.truthy(blocked(Vector3.new(x, 1, z)), `gap in the {label} wall at x {x}, z {z}`)
		end
		for _, s in { -1, 1 } do
			for z = -line, back, 1 do
				check(s * line, z, "side")
			end
			for x = PlotBuilder.EntranceHalf + 0.6, line, 1 do
				check(s * x, -line, "front")
			end
			for x = gate.Width / 2 + 0.6, line, 1 do
				check(gate.CenterX + s * x, line, "pad/yard")
			end
			for x = stopHalf + 1, line, 1 do
				check(s * x, back, "back")
			end
			-- the square back corner (a brick-wall-end pillar)
			check(s * line, back, "corner")
		end
		T.lt(150, samples, "border samples")
		-- every wall segment is brick: plinth, red band, a cap slab overhanging both faces
		local caps = 0
		for _, d in model.Walls:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Cap" then
				caps += 1
				T.lt(PlotBuilder.WallBand + 0.2, d.Size.X, "cap overhangs the brick band")
				T.lt(d.Size.Y, d.Size.X, "cap is a low slab")
			end
		end
		T.lt(9, caps, "pad wall segments")
	end)

	T.test("Podiums: showpiece pedestals keep what PodiumService and PodiumController read", function()
		local plot = WorldLayout.Plots[1]
		local model = buildPlot(plot)
		for slot, rect in BaseLayout.Podiums do
			local podium = model.Yard:FindFirstChild("Podium" .. slot)
			T.eq(podium:GetAttribute("Slot"), slot, "Slot attribute")
			T.truthy(podium.PrimaryPart and podium.PrimaryPart.Name == "Base", "PrimaryPart Base")
			local rim = podium:FindFirstChild("Rim")
			T.truthy(rim and rim:IsA("BasePart"), "Rim part")
			local locked = slot > EconomyConfig.Podiums.Free
			T.eq(rim.Material, if locked then roblox.Enum.Material.SmoothPlastic else roblox.Enum.Material.Neon, "rim look")
			T.eq(rim.Color, if locked then PlotBuilder.RimLocked else PlotBuilder.RimGold, "rim color")
			-- no glass case any more: a holo-ring around the ore that never blocks or
			-- catches the mouse, and an invisible hover box over the ore that does
			local top = podium.Top
			local orePoint = (top.CFrame * top.OrePoint.CFrame).Position
			T.falsy(podium:FindFirstChild("Dome"), "no glass dome")
			local bars = 0
			for _, d in podium:GetChildren() do
				if d:IsA("BasePart") and d.Name == "HoloRing" then
					bars += 1
					T.falsy(d.CanCollide, "ring doesn't collide")
					T.falsy(d.CanQuery, "ring doesn't catch the mouse")
					T.eq(d.Material, roblox.Enum.Material.Neon, "ring glows")
				end
			end
			T.eq(bars, PlotBuilder.HoloRing.Sides, "a closed holo-ring")
			local hover = podium:FindFirstChild("Hover")
			T.truthy(hover and hover:IsA("BasePart"), "hover box")
			T.eq(hover.Transparency, 1, "hover box is invisible")
			T.truthy(hover.CanQuery, "hover box catches the mouse")
			T.falsy(hover.CanCollide, "hover box doesn't collide")
			T.falsy(hover.CanTouch, "hover box doesn't touch")
			local q = hover.CFrame:PointToObjectSpace(orePoint + Vector3.new(0, 1, 0))
			T.truthy(
				math.abs(q.X) < hover.Size.X / 2 and math.abs(q.Y) < hover.Size.Y / 2 and math.abs(q.Z) < hover.Size.Z / 2,
				"hover box holds the ore"
			)
			T.lt(top.CFrame.Position.Y + top.Size.X / 2, orePoint.Y, "ore floats above the top plate")
			-- inside the slot's rect
			local min, max = localBounds(WorldLayout.plotCFrame(plot), podium.PrimaryPart)
			T.le(rect.Center.X - rect.Size.X / 2 - 0.01, min.X, "base inside the slot")
			T.le(max.X, rect.Center.X + rect.Size.X / 2 + 0.01, "base inside the slot")
			if locked then
				-- PodiumService hides the lock by making it transparent: all of it starts opaque
				for _, d in podium.Lock:GetDescendants() do
					if d:IsA("BasePart") then
						T.eq(d.Transparency, 0, "lock part opaque")
					end
				end
			end
		end
	end)

	T.test("Podiums: every ore and the lock fit inside the holo-ring, below the income tag", function()
		local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
		local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
		local plot = WorldLayout.Plots[1]
		local plotCF = WorldLayout.plotCFrame(plot)
		local built = buildPlot(plot)
		-- PodiumService's income tag: TAG_HEIGHT 2.6 over the ore point, 1.7 studs tall
		local tagBottom = BaseLayout.PodiumOreHeight + 2.6 - 1.7 / 2
		-- points of a part (corners, or the extremes of a ball) in plot space
		local function points(part: any): { any }
			local list = {}
			local h = part.Size / 2
			if part.ClassName == "Part" and part.Shape == roblox.Enum.PartType.Ball then
				local c = part.CFrame.Position
				for _, off in
					{
						Vector3.new(h.X, 0, 0),
						Vector3.new(-h.X, 0, 0),
						Vector3.new(0, h.X, 0),
						Vector3.new(0, -h.X, 0),
						Vector3.new(0, 0, h.X),
						Vector3.new(0, 0, -h.X),
					}
				do
					table.insert(list, c + off)
				end
			else
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							table.insert(list, (part.CFrame * CFrame.new(sx * h.X, sy * h.Y, sz * h.Z)).Position)
						end
					end
				end
			end
			return list
		end
		for slot, rect in BaseLayout.Podiums do
			local axis = plotCF * CFrame.new(rect.Center.X, 0, rect.Center.Z)
			local function flat(p: any): (number, number)
				local q = axis:PointToObjectSpace(p)
				return math.sqrt(q.X * q.X + q.Z * q.Z), q.Y
			end
			-- the ring's inner edge (nearest point to the podium's axis) and its top
			local bars, size = PlotBuilder.holoRingBars(axis)
			local inner, ringTop = math.huge, -math.huge
			for _, bar in bars do
				for i = 0, 20 do
					local p = (bar * CFrame.new((i / 20 - 0.5) * size.X, 0, 0)).Position
					local r, y = flat(p)
					inner = math.min(inner, r - size.Y / 2)
					ringTop = math.max(ringTop, y + size.Y / 2)
				end
			end
			T.lt(ringTop, tagBottom, "holo-ring stays below the income tag")
			T.lt(BaseLayout.PodiumOreHeight, ringTop, "holo-ring goes round the ore")
			-- every ore as PodiumService shows it (it turns about the axis, so only its radius counts)
			local widest, widestId = 0, ""
			for _, ore in OreData.List do
				for _, grade in { "Clean", "Flawless" } do
					local display = ItemBuilder.display(
						{ K = "Clean", O = ore.Id, G = grade },
						axis * CFrame.new(0, BaseLayout.PodiumOreHeight, 0),
						`{plot.Id}/{slot}/{ore.Id}`
					)
					for _, d in display:GetDescendants() do
						if d:IsA("BasePart") and d.Transparency < 1 then
							for _, p in points(d) do
								local r = flat(p)
								if r > widest then
									widest, widestId = r, ore.Id
								end
							end
						end
					end
				end
			end
			T.lt(widest + 0.05, inner, `{widestId} fits inside the holo-ring of podium {slot}`)
			local podium = built.Yard:FindFirstChild("Podium" .. slot)
			local lockModel = podium:FindFirstChild("Lock")
			if lockModel then
				for _, d in lockModel:GetDescendants() do
					if d:IsA("BasePart") then
						for _, p in points(d) do
							local r, y = flat(p)
							T.lt(r, inner, "lock inside the holo-ring")
							T.lt(BaseLayout.PodiumOreHeight - 0.3, y, "lock floats where the ore would be")
						end
					end
				end
			end
		end
	end)

	T.test("Yard: rocks, trees, grass patches and ore nodes stay out of every yard", function()
		for _, s in WorldBuilder.generateNodeSpawns() do
			T.falsy(PlotBuilder.isInYard(s.Position), "node spawn in a yard")
		end
		for _, plot in WorldLayout.Plots do
			local cf = WorldLayout.plotCFrame(plot)
			T.truthy(PlotBuilder.isInYard(cf:PointToWorldSpace(BaseLayout.Pen.Area.Center)), "pen is in the yard")
			T.truthy(PlotBuilder.isInYard(cf:PointToWorldSpace(Vector3.new(0, 0, BaseLayout.RailZ))), "the rail behind it too")
			T.falsy(PlotBuilder.isInYard(plot.Center), "the machine grid is not the yard")
		end
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local checked = 0
		for _, folderName in { "Land", "Emberfall" } do
			for _, d in map:FindFirstChild(folderName):GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					-- flat decoration near the ground: grass patches, trees, rocks, bushes, flowers
					if p.Y > -2 and p.Y < 20 and d.Size.X < 40 and d.Size.Z < 40 then
						checked += 1
						T.falsy(PlotBuilder.isInYard(p), `{d:GetFullName()} lies in a yard`)
					end
				end
			end
		end
		T.lt(100, checked, "decoration was checked")
	end)
end
