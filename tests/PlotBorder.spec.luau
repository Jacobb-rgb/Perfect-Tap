-- Plot border: rails, posts, the banner pole and every other decoration
-- stay off the 48x48 build grid, so every cell is free for machines.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")

	T.test("Plot: no decoration inside the build grid", function()
		local half = GameConfig.PlotCells * GameConfig.CellSize / 2
		local folder = roblox.Instance.new("Folder")
		for _, plot in WorldLayout.Plots do
			local model = PlotBuilder.buildPlot(folder, plot, Rng.new(plot.Id))
			local plotCF = WorldLayout.plotCFrame(plot)
			local pad = model:FindFirstChild("Pad")
			T.near(pad.Size.X, half * 2 + 2, 1e-4, "pad has a 1-stud border")
			local tile = model:FindFirstChild("PlotTile")
			T.truthy(tile, "PlotTile")
			T.near(tile.Size.X, half * 2, 1e-4, "tile is exactly the grid")
			T.near(tile.Size.Z, half * 2, 1e-4, "tile is exactly the grid")
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part ~= pad and part ~= tile then
					local cf = plotCF:ToObjectSpace(part.CFrame)
					local size = part.Size
					local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
					local hx = math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2
					local hy = math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2
					local hz = math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
					local p = cf.Position
					local eps = 0.01
					local overGrid = p.X - hx < half - eps and p.X + hx > -half + eps and p.Z - hz < half - eps and p.Z + hz > -half + eps
					-- anything that reaches above the pad surface over the grid is in the way
					T.falsy(overGrid and p.Y + hy > 0.05, `plot {plot.Id}: {part.Name} intrudes into the grid`)
				end
			end
		end
	end)
end
