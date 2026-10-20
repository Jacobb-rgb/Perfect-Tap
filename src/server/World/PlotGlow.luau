--[[
	PlotGlow: the rebirth Star Shop's Plot Glow (RebirthConfig.GlowColors):
	a glowing ribbon on the lids of the pad's walls and a crystal beacon on
	each corner post, in the colour the owner picked (Prism: a rainbow,
	each run in its own hue). Cosmetic only.

	Built in plot-local space from PlotBuilder's wall lines (WallLine, the
	entrance gap, the pillar line): the two long side runs, the two front
	runs either side of the entrance, the four corner beacons = 8 parts,
	all Neon, anchored, nothing collides, touches, is raycast or casts a
	shadow (phones: no lights). RebirthService builds it into the plot model
	as "RebirthGlow" and takes it away for "" (off) or when the plot is freed.
	Pure: Instance creation only (the Lune preview builds it too).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local PlotBuilder = require(script.Parent.PlotBuilder)

local PlotGlow = {}

PlotGlow.Name = "RebirthGlow"
PlotGlow.MaxParts = 8
PlotGlow.RibbonY = 2.62 -- on the walls' round lids (PLOT_WALL BodyTop 1.95 + Lid / 2)
PlotGlow.RibbonSize = Vector2.new(0.36, 0.16) -- width x height of a ribbon
PlotGlow.BeaconY = 4.05 -- over the corner posts' caps
PlotGlow.BeaconSize = Vector3.new(0.7, 1.3, 0.7)
-- Prism: one hue per run, round the plot
PlotGlow.Prism = {
	Color3.fromRGB(255, 96, 96),
	Color3.fromRGB(255, 196, 72),
	Color3.fromRGB(110, 230, 110),
	Color3.fromRGB(96, 196, 255),
	Color3.fromRGB(200, 120, 255),
	Color3.fromRGB(255, 120, 210),
	Color3.fromRGB(120, 255, 230),
	Color3.fromRGB(255, 236, 140),
}

-- The colour of the i-th part for a colour id (nil for "" or an unknown id).
function PlotGlow.colorOf(colorId: string, i: number): Color3?
	if colorId == "Prism" then
		return PlotGlow.Prism[(i - 1) % #PlotGlow.Prism + 1]
	end
	for _, color in RebirthConfig.GlowColors do
		if color.Id == colorId then
			return color.Color
		end
	end
	return nil
end

local function decor(parent: Instance, cf: CFrame, size: Vector3, color: Color3, name: string): Part
	local part = Geo.block(parent, cf, size, color, Enum.Material.Neon, {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
	})
	return part
end

--[[
	Builds the glow for `colorId` into `parent` at the plot frame `plotCf`
	(PlotService.plotCFrame). Returns the Model, or nil for "" / an
	unknown colour (nothing is built).
]]
function PlotGlow.build(parent: Instance, plotCf: CFrame, colorId: string): Model?
	if PlotGlow.colorOf(colorId, 1) == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = PlotGlow.Name
	model:SetAttribute("Color", colorId)
	local L = PlotBuilder.WallLine
	local Pl = L + 0.1
	local ex = PlotBuilder.EntranceHalf + 1.05 -- the entrance posts' caps
	local w, h = PlotGlow.RibbonSize.X, PlotGlow.RibbonSize.Y
	local i = 0
	local function ribbon(a: Vector3, b: Vector3, name: string)
		i += 1
		local mid = (a + b) / 2
		local length = (b - a).Magnitude
		local cf = plotCf * CFrame.lookAt(Vector3.new(mid.X, PlotGlow.RibbonY, mid.Z), Vector3.new(b.X, PlotGlow.RibbonY, b.Z))
		decor(model, cf, Vector3.new(w, h, length), PlotGlow.colorOf(colorId, i) :: Color3, name)
	end
	for _, s in { -1, 1 } do
		-- the long side run (road corner .. the pad / yard corner)
		ribbon(Vector3.new(s * L, 0, -Pl + 0.6), Vector3.new(s * L, 0, Pl - 0.6), if s < 0 then "SideLeft" else "SideRight")
		-- the front run, corner .. the entrance post
		ribbon(Vector3.new(s * (Pl - 0.6), 0, -L), Vector3.new(s * (ex + 0.4), 0, -L), if s < 0 then "FrontLeft" else "FrontRight")
	end
	for _, corner in { Vector3.new(-Pl, 0, -Pl), Vector3.new(Pl, 0, -Pl), Vector3.new(-Pl, 0, Pl), Vector3.new(Pl, 0, Pl) } do
		i += 1
		local cf = plotCf * CFrame.new(corner.X, PlotGlow.BeaconY, corner.Z) * CFrame.Angles(0, math.pi / 4, 0)
		decor(model, cf, PlotGlow.BeaconSize, PlotGlow.colorOf(colorId, i) :: Color3, "Beacon")
	end
	model.Parent = parent
	return model
end

return PlotGlow
