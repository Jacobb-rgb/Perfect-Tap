--[[
	Machine gallery preview (scene "machines" in tools/lune/export_scene.luau,
	shots in tools/preview/machines_shots.json): every machine from
	MachineBuilder on a plot-like pad, with a short belt line.

	The preview renderer can't draw Beams, particles or SurfaceGui frames, so
	this file paints stand-ins with thin parts:
	  - the water the client animates (MachineFxController): the Beam curve
	    between WaterOut and WaterIn, droplets, mist and ripples, using the
	    same MachineBuilder.Water colours and widths;
	  - the rollers / hazard edges that the belt's SurfaceGui gradients paint.
]]

local roblox = require("@lune/roblox") :: any

local Gallery = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3

-- Plot layout: machine, grid cell of its min corner, rotation.
Gallery.Layout = {
	{ Id = "CleaningStation", X = 0, Z = 2, R = 0 },
	{ Id = "ClayFurnace", X = 4, Z = 2, R = 0 },
	{ Id = "Crusher", X = 7, Z = 2, R = 0 },
	{ Id = "AutoCleaner", X = 10, Z = 2, R = 0 },
	{ Id = "BlastFurnace", X = 0, Z = 6, R = 0 },
	{ Id = "StorageCrate", X = 4, Z = 6, R = 0 },
	{ Id = "Anvil", X = 7, Z = 6, R = 0 },
	{ Id = "SellChute", X = 10, Z = 6, R = 0 },
	-- belts: out of the Auto Cleaner, round a corner, into the Crusher's side
	{ Id = "Conveyor", X = 11, Z = 1, R = 3 },
	{ Id = "Conveyor", X = 10, Z = 1, R = 3 },
	{ Id = "Conveyor", X = 9, Z = 1, R = 2 },
	{ Id = "Conveyor", X = 9, Z = 2, R = 3 },
}

-- Colour of a ColorSequence at time t (linear between keypoints).
local function sample(sequence: any, t: number): any
	local keys = sequence.Keypoints
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t >= a.Time and t <= b.Time then
			local span = b.Time - a.Time
			local f = if span > 0 then (t - a.Time) / span else 0
			return a.Value:Lerp(b.Value, f)
		end
	end
	return keys[#keys].Value
end

-- Bezier point of a Beam between two attachments (Roblox's control points).
local function bezier(p0: any, p1: any, p2: any, p3: any, t: number): any
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

local function tube(Loader: any, parent: any, a: any, b: any, diameter: number, color: any, transparency: number, material: any?)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local CF = Loader.CFrame
	local length = (b - a).Magnitude
	if length < 1e-3 then
		return
	end
	local cf = CF.lookAt((a + b) / 2, b) * CF.Angles(0, math.pi / 2, 0)
	local part = Geo.block(parent, cf, V3.new(length + diameter * 0.3, diameter, diameter), color, material, {
		CanCollide = false,
		CastShadow = false,
		Transparency = transparency,
	})
	part.Shape = roblox.Enum.PartType.Cylinder
end

--[[
	Stand-in for MachineFxController's water rig on a placed machine: a curved
	stream (outer + core) from WaterOut to WaterIn with flowing bands, white
	droplets, mist and pool ripples (or a shower fan for Spray outlets).
]]
function Gallery.water(Loader: any, parent: any, model: any, flow: number)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local W = MachineBuilder.Water
	local base = model.PrimaryPart
	local out = base:FindFirstChild("WaterOut")
	local into = base:FindFirstChild("WaterIn")
	if not out or not into then
		return
	end
	local p0 = base.CFrame:PointToWorldSpace(out.CFrame.Position)
	local p3 = base.CFrame:PointToWorldSpace(into.CFrame.Position)
	local a0 = base.CFrame:VectorToWorldSpace(out.CFrame.RightVector)
	local a1 = base.CFrame:VectorToWorldSpace(into.CFrame.RightVector)
	local p1 = p0 + a0 * out:GetAttribute("Curve")
	local p2 = p3 - a1 * into:GetAttribute("Curve")
	local spray = out:GetAttribute("Spray") == true
	local k = 0.55 + 0.45 * flow
	local white = W.Splash
	local tiny = { CanCollide = false, CastShadow = false }
	if spray then
		-- shower fan: thin jets spreading across the ore
		local across = base.CFrame.RightVector
		for i = -2, 2 do
			local spread = i / 2 * (W.SprayWidthEnd / 2) * k
			local finish = p3 + across * spread
			local start = p0 + across * (i / 2 * W.SprayWidth / 2)
			tube(Loader, parent, start, finish, 0.09, W.Stream, 0.35)
			tube(Loader, parent, start, start:Lerp(finish, 0.5), 0.05, W.Core, 0.2)
		end
		for i = 1, 14 do
			local angle = i * 2.39996
			local r = 0.35 + (i % 4) * 0.22
			local p = p3 + V3.new(math.cos(angle) * r * 1.6, 0.15 + (i % 3) * 0.25, math.sin(angle) * r * 0.7)
			Geo.ball(parent, p, 0.09 + (i % 2) * 0.04, white, nil, tiny)
		end
		Geo.ball(parent, p3 + V3.new(0, 0.35, 0), 1.6, white, nil, { CanCollide = false, CastShadow = false, Transparency = 0.82 })
		return
	end
	-- curved stream: outer ribbon in flowing bands + bright core
	local steps = 16
	local last = p0
	for i = 1, steps do
		local t = i / steps
		local p = bezier(p0, p1, p2, p3, t)
		local width = (W.Width + (W.WidthEnd - W.Width) * t) * k
		local band = if i % 3 == 0 then W.Stream:Lerp(W.Core, 0.35) else W.Stream
		tube(Loader, parent, last, p, width, band, 0.3)
		tube(Loader, parent, last, p, width * 0.38, W.Core, 0.15)
		last = p
	end
	-- splash: droplets jumping out of the pool, a puff of mist
	for i = 1, 12 do
		local angle = i * 2.39996
		local r = 0.25 + (i % 4) * 0.16
		local p = p3 + V3.new(math.cos(angle) * r, 0.12 + (i % 3) * 0.22 + (i % 5) * 0.05, math.sin(angle) * r)
		Geo.ball(parent, p, 0.08 + (i % 2) * 0.04, white, nil, tiny)
	end
	Geo.ball(parent, p3 + V3.new(0, 0.25, 0), 1.0, white, nil, { CanCollide = false, CastShadow = false, Transparency = 0.8 })
	-- ripples on the pool
	local CF = Loader.CFrame
	for i, d in { 0.7, 1.3 } do
		local disc =
			Geo.block(parent, CF.new(p3 + V3.new(0, 0.005 * i, 0)) * CF.Angles(0, 0, math.pi / 2), V3.new(0.02, d, d), white, nil, {
				CanCollide = false,
				CastShadow = false,
				Transparency = 0.55 + i * 0.12,
			})
		disc.Shape = roblox.Enum.PartType.Cylinder
	end
end

-- Thin parts showing what a belt's SurfaceGui gradients paint on its top.
function Gallery.paintBelt(Loader: any, parent: any, model: any)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local CF = Loader.CFrame
	local belt = model:FindFirstChild("Belt")
	local gui = belt and belt:FindFirstChild("BeltFace")
	if not gui then
		return
	end
	local size = belt.Size
	for _, frame in gui:GetChildren() do
		local gradient = frame:FindFirstChildWhichIsA("UIGradient")
		if gradient then
			local x0 = frame.Position.X.Scale
			local width = frame.Size.X.Scale
			local slices = 40
			for s = 0, slices - 1 do
				local t = (s + 0.5) / slices
				local color = sample(gradient.Color, t)
				local local_ = CF.new(-size.X / 2 + (x0 + width / 2) * size.X, size.Y / 2 + 0.006, -size.Z / 2 + t * size.Z)
				Geo.block(parent, belt.CFrame * local_, V3.new(width * size.X, 0.01, size.Z / slices + 0.002), color, nil, {
					CanCollide = false,
					CastShadow = false,
				})
			end
		end
	end
end

function Gallery.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Dummy = require("./dummy")
	local root = roblox.Instance.new("Model")
	root.Name = "MachineGallery"
	root.Parent = parent
	local CELL = GameConfig.CellSize
	local half = GameConfig.PlotCells * CELL / 2

	-- lawn, a gravel plot pad with faint cell lines and a low kerb
	Geo.block(root, CF.new(0, -1.06, 0), V3.new(260, 2, 260), C3.fromRGB(150, 196, 92))
	Geo.block(root, CF.new(0, -0.5, 0), V3.new(half * 2, 1, half * 2), C3.fromRGB(214, 192, 150))
	for i = 1, GameConfig.PlotCells - 1 do
		local p = -half + i * CELL
		Geo.block(root, CF.new(p, 0.005, 0), V3.new(0.08, 0.01, half * 2), C3.fromRGB(196, 174, 134))
		Geo.block(root, CF.new(0, 0.005, p), V3.new(half * 2, 0.01, 0.08), C3.fromRGB(196, 174, 134))
	end
	for _, side in { -1, 1 } do
		Geo.block(root, CF.new(side * (half + 0.4), 0.2, 0), V3.new(0.8, 0.8, half * 2 + 1.6), C3.fromRGB(120, 112, 108))
		Geo.block(root, CF.new(0, 0.2, side * (half + 0.4)), V3.new(half * 2 + 1.6, 0.8, 0.8), C3.fromRGB(120, 112, 108))
	end

	local placed = {}
	local counts = {}
	for _, entry in Gallery.Layout do
		local model = MachineBuilder.build(entry.Id)
		model:PivotTo(Grid.localCFrame(entry.Id, entry.X, entry.Z, entry.R))
		model.Parent = root
		placed[entry.Id] = model
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		counts[entry.Id] = n
		if entry.Id == "Conveyor" then
			Gallery.paintBelt(Loader, root, model)
		end
	end
	-- water as the client shows it: the station idles gently, the cleaner works
	Gallery.water(Loader, root, placed.CleaningStation, 0.4)
	Gallery.water(Loader, root, placed.AutoCleaner, 1)

	-- a forgekeeper at the Cleaning Station for scale
	local station = placed.CleaningStation.PrimaryPart.CFrame
	Dummy.build(root, CF, station * CF.new(-1.2, 0, -5.6) * CF.Angles(0, math.pi, 0), "idle")

	local names = {}
	for id in counts do
		table.insert(names, id)
	end
	table.sort(names)
	for _, id in names do
		print(string.format("  %-16s %3d parts", id, counts[id]))
	end
	return root
end

return Gallery
