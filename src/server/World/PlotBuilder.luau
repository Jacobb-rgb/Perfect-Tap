--[[
	Player plots: a flat pad (12x12 grid of 4-stud cells plus a 1-stud
	border), low border rails, a name sign at the front and a banner.
	Everything decorative stays outside the 48x48 build grid, so every cell
	is free for machines. Machines are added at runtime into the plot's
	"Machines" folder by MachineService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local GameConfig = require(Shared.Config.GameConfig)
local WorldLayout = require(Shared.Config.WorldLayout)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local PlotBuilder = {}

local BANNER_COLORS = {
	Color3.fromRGB(220, 70, 50),
	Color3.fromRGB(240, 170, 40),
	Color3.fromRGB(80, 180, 90),
	Color3.fromRGB(60, 140, 220),
	Color3.fromRGB(160, 90, 220),
	Color3.fromRGB(230, 110, 170),
	Color3.fromRGB(60, 190, 190),
	Color3.fromRGB(240, 230, 210),
}

function PlotBuilder.buildPlot(parent: Instance, plot: WorldLayout.Plot, rng: Rng.Rng): Model
	local size = GameConfig.PlotCells * GameConfig.CellSize
	local half = size / 2
	local cf = WorldLayout.plotCFrame(plot)
	local m = Instance.new("Model")
	m.Name = "Plot_" .. plot.Id
	m:SetAttribute("PlotId", plot.Id)
	m:AddTag("Plot")

	-- the pad has a 1-stud border around the grid for the rails and posts
	local pad = Geo.block(m, cf * CFrame.new(0, -0.6, 0), Vector3.new(size + 2, 1.2, size + 2), Palette.PlotPad, nil, { CanTouch = false })
	pad.Name = "Pad"
	-- slightly darker inner area that is exactly the build grid
	local tile = Geo.block(m, cf * CFrame.new(0, -0.02, 0), Vector3.new(size, 0.06, size), Palette.PlotTile, nil, {
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		CastShadow = false,
	})
	tile.Name = "PlotTile"

	-- rails on the back and sides, on the border; the front (road side, -Z local) stays open
	local edge = half + 0.5
	local railColor = Palette.WoodDark
	local railProps = { CanTouch = false, CanQuery = false }
	Geo.block(m, cf * CFrame.new(0, 0.35, edge), Vector3.new(size + 2, 0.7, 1), railColor, nil, railProps)
	Geo.block(m, cf * CFrame.new(-edge, 0.35, 0), Vector3.new(1, 0.7, size + 2), railColor, nil, railProps)
	Geo.block(m, cf * CFrame.new(edge, 0.35, 0), Vector3.new(1, 0.7, size + 2), railColor, nil, railProps)
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		Geo.block(m, cf * CFrame.new(corner.X * edge, 1, corner.Z * edge), Vector3.new(1, 2, 1), Palette.Wood, nil, railProps)
	end

	-- front lanterns
	Props.lantern(m, cf * CFrame.new(-half + 1, 0, -half - 1.5) * CFrame.Angles(0, -math.pi / 2, 0), true)
	Props.lantern(m, cf * CFrame.new(half - 1, 0, -half - 1.5) * CFrame.Angles(0, math.pi / 2, 0), false)

	-- name sign at the front, facing the road
	local signBase = cf * CFrame.new(-half + 8, 0, -half - 2)
	Geo.block(m, signBase * CFrame.new(-2.6, 2.4, 0), Vector3.new(0.5, 4.8, 0.5), Palette.WoodDark, nil, railProps)
	Geo.block(m, signBase * CFrame.new(2.6, 2.4, 0), Vector3.new(0.5, 4.8, 0.5), Palette.WoodDark, nil, railProps)
	local sign = Props.sign(m, signBase * CFrame.new(0, 3.6, 0), "Free Plot", 6.4, 2.2, Palette.WoodLight, Palette.WoodDark)
	sign.Name = "PlotSign"

	-- banner pole just outside the back corner (owner color); it reaches
	-- down past the pad so it never floats over lower ground
	local pole = cf * CFrame.new(half + 1.5, 0, half + 1.5)
	Geo.block(m, pole * CFrame.new(0, 5.4, 0), Vector3.new(0.5, 13.2, 0.5), Palette.WoodDark, nil, railProps)
	local banner = Geo.block(m, pole * CFrame.new(-1.8, 9.4, 0), Vector3.new(3.4, 4.4, 0.15), BANNER_COLORS[(plot.Id - 1) % #BANNER_COLORS + 1], nil, {
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	banner.Name = "Banner"
	Geo.wedge(m, pole * CFrame.new(-1.8, 6.4, 0) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.15, 1.6, 3.4), banner.Color, nil, {
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})

	local machines = Instance.new("Folder")
	machines.Name = "Machines"
	machines.Parent = m

	m.PrimaryPart = pad
	m.Parent = parent
	local _ = rng
	return m
end

function PlotBuilder.build(map: Model, rng: Rng.Rng): Folder
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = map
	for _, plot in WorldLayout.Plots do
		PlotBuilder.buildPlot(plots, plot, rng)
	end
	return plots
end

return PlotBuilder
