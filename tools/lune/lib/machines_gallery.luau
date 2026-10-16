--[[
	Machine gallery preview (scene "machines" in tools/lune/export_scene.luau,
	shots in tools/preview/machines_shots.json): every machine from
	MachineBuilder on a plot-like pad, straight belt runs into and out of the
	Auto Cleaner, and ore on the way.

	The preview renderer can't draw Beams, particles or SurfaceGui frames, so
	this file paints stand-ins with thin parts:
	  - the water the client animates (MachineFxController): one smooth,
	    tapering, see-through stream along the Beam curve between WaterOut and
	    WaterIn, a few droplets and ripples on the pool; for a shower, fanned
	    see-through sheets onto the ore. Same MachineBuilder.Water colours and
	    widths as the client;
	  - what the conveyor SurfaceGuis paint: the rollers / hazard edges on the
	    belt, the cap strip and axle caps on the rails.
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
	-- belts: a straight run into the Auto Cleaner's back, and out of its front
	{ Id = "Conveyor", X = 11, Z = 5, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 4, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 1, R = 0 },
	{ Id = "Conveyor", X = 11, Z = 0, R = 0 },
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

local GLASS = roblox.Enum.Material.Glass

local function decor(transparency: number?): any
	return { CanCollide = false, CastShadow = false, Transparency = transparency or 0 }
end

--[[
	Stand-in for MachineFxController's water rig on a placed machine. A pour:
	one smooth stream of 6 see-through glass segments along the Beam curve,
	tapering from Width to WidthEnd, a few droplets and two faint ripples. A
	shower (Spray): three thin see-through sheets fanned from the shower head
	onto the ore, and a few droplets around it.
]]
function Gallery.water(Loader: any, parent: any, model: any, flow: number, hitY: number?)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local CF = Loader.CFrame
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
	local k = 0.55 + 0.45 * flow

	local function droplets(center: any, count: number, radius: number, height: number)
		for i = 1, count do
			local angle = i * 2.39996
			local r = radius * (0.55 + (i % 3) * 0.25)
			local p = center + V3.new(math.cos(angle) * r, 0.1 + (i % 3) * height, math.sin(angle) * r)
			Geo.ball(parent, p, 0.08 + (i % 2) * 0.04, W.Splash:Lerp(W.Stream, 0.5), GLASS, decor(0.4))
		end
	end

	if out:GetAttribute("Spray") == true then
		-- three sheets fanned front / middle / back, each a trapezoid of two
		-- triangles from the shower head down to where it hits (the ore top;
		-- in game the Beam runs on into the ore, hidden by it)
		local across = base.CFrame.RightVector
		local ahead = base.CFrame.LookVector
		local hit = V3.new(p3.X, hitY or p3.Y, p3.Z)
		for _, fan in { -1, 0, 1 } do
			local top = p0 + ahead * (fan * 0.1)
			local bottom = hit + ahead * (fan * 0.45)
			local halfTop = W.SprayWidth / 2 * k
			local halfBottom = W.SprayWidthEnd / 2 * k * (1 - math.abs(fan) * 0.12)
			local a, b = top - across * halfTop, top + across * halfTop
			local c, d = bottom + across * halfBottom, bottom - across * halfBottom
			local color = if fan == 0 then W.Stream else W.Stream:Lerp(W.Deep, 0.5)
			local transparency = if fan == 0 then 0.58 else 0.68
			local props = decor(transparency)
			Geo.triangle(parent, a, b, c, 0.03, color, GLASS, nil, props)
			Geo.triangle(parent, a, c, d, 0.03, color, GLASS, nil, props)
		end
		droplets(hit, 6, 0.75, 0.16)
		return
	end

	-- the stream: 6 segments end to end (no overlap), tapering, light blue
	-- at the outlet, deeper blue where it lands
	local steps = 6
	local last = p0
	for i = 1, steps do
		local t = i / steps
		local p = bezier(p0, p1, p2, p3, t)
		local length = (p - last).Magnitude
		if length > 1e-3 then
			local mid = (t - 0.5 / steps)
			local width = (W.Width + (W.WidthEnd - W.Width) * mid) * k
			local cf = CF.lookAt((last + p) / 2, p) * CF.Angles(0, math.pi / 2, 0)
			local seg = Geo.block(parent, cf, V3.new(length, width, width), W.Stream:Lerp(W.Deep, mid), GLASS, decor(0.45 + 0.1 * mid))
			seg.Shape = roblox.Enum.PartType.Cylinder
		end
		last = p
	end
	-- splash: a few droplets and a faint ripple on the pool
	droplets(p3, 6, 0.42, 0.16)
	local ripple = Geo.block(parent, CF.new(p3 + V3.new(0, 0.005, 0)) * CF.Angles(0, 0, math.pi / 2), V3.new(0.02, 1.1, 1.1), W.Splash:Lerp(W.Stream, 0.5), nil, decor(0.86))
	ripple.Shape = roblox.Enum.PartType.Cylinder
end

-- Face frames of a SurfaceGui in part space: centre, normal, the GUI's x and
-- y (down) directions and the face size along them.
local function faceFrame(face: string, size: any): (any, any, any, any, number, number)
	if face == "Top" then
		return V3.new(0, size.Y / 2, 0), V3.new(0, 1, 0), V3.new(1, 0, 0), V3.new(0, 0, 1), size.X, size.Z
	elseif face == "Left" then
		return V3.new(-size.X / 2, 0, 0), V3.new(-1, 0, 0), V3.new(0, 0, 1), V3.new(0, -1, 0), size.Z, size.Y
	elseif face == "Right" then
		return V3.new(size.X / 2, 0, 0), V3.new(1, 0, 0), V3.new(0, 0, -1), V3.new(0, -1, 0), size.Z, size.Y
	end
	return V3.new(0, 0, -size.Z / 2), V3.new(0, 0, -1), V3.new(-1, 0, 0), V3.new(0, -1, 0), size.X, size.Y
end

local function absVector(v: any): any
	return V3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

-- Thin parts showing what a part's SurfaceGui frames paint: gradients in
-- slices, plain frames as plates, round frames (UICorner) as discs.
local function paintGui(Loader: any, parent: any, part: any, gui: any)
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local CF = Loader.CFrame
	local center, normal, ux, vy, width, height = faceFrame(gui.Face.Name, part.Size)
	local function point(x: number, y: number, lift: number): any
		return center + ux * ((x - 0.5) * width) + vy * ((y - 0.5) * height) + normal * lift
	end
	for i, frame in gui:GetChildren() do
		if frame:IsA("Frame") then
			local fw, fh = frame.Size.X.Scale, frame.Size.Y.Scale
			local x0 = frame.Position.X.Scale - frame.AnchorPoint.X * fw
			local y0 = frame.Position.Y.Scale - frame.AnchorPoint.Y * fh
			local lift = 0.006 + 0.002 * i
			local gradient = frame:FindFirstChildWhichIsA("UIGradient")
			if gradient then
				local slices = 40
				for s = 0, slices - 1 do
					local t = (s + 0.5) / slices
					local size = absVector(ux) * (fw * width) + absVector(vy) * (fh * height / slices + 0.002) + absVector(normal) * 0.01
					Geo.block(parent, part.CFrame * CF.new(point(x0 + fw / 2, y0 + t * fh, lift)), size, sample(gradient.Color, t), nil, decor())
				end
			elseif frame:FindFirstChildWhichIsA("UICorner") then
				local d = math.min(fw * width, fh * height)
				local disc = Geo.block(
					parent,
					part.CFrame * CF.lookAt(point(x0 + fw / 2, y0 + fh / 2, lift), point(x0 + fw / 2, y0 + fh / 2, 1)) * CF.Angles(0, math.pi / 2, 0),
					V3.new(0.012, d, d),
					frame.BackgroundColor3,
					nil,
					decor()
				)
				disc.Shape = roblox.Enum.PartType.Cylinder
			else
				local size = absVector(ux) * (fw * width) + absVector(vy) * (fh * height) + absVector(normal) * 0.01
				Geo.block(parent, part.CFrame * CF.new(point(x0 + fw / 2, y0 + fh / 2, lift)), size, frame.BackgroundColor3, nil, decor())
			end
		end
	end
end

-- Paints a conveyor's SurfaceGuis (belt top, rail sides).
function Gallery.paintBelt(Loader: any, parent: any, model: any)
	for _, name in { "Belt", "RailL", "RailR" } do
		local part = model:FindFirstChild(name)
		if part then
			for _, gui in part:GetChildren() do
				if gui:IsA("SurfaceGui") then
					paintGui(Loader, parent, part, gui)
				end
			end
		end
	end
end

function Gallery.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
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
	local belts = {}
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
			table.insert(belts, model)
		end
	end

	-- ore on the way: dirty ore riding in, one under the shower, clean ore out
	-- (each item is dropped so its lowest point rests on `surface`)
	local function ore(kind: string, oreId: string, cf: any, surface: number, seed: number)
		local item = ItemBuilder.build({ Kind = kind, OreId = oreId, Grade = "Clean" }, cf, seed)
		local low = math.huge
		for _, d in item:GetDescendants() do
			if d:IsA("BasePart") then
				local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
				local half = math.abs(r10) * d.Size.X / 2 + math.abs(r11) * d.Size.Y / 2 + math.abs(r12) * d.Size.Z / 2
				low = math.min(low, d.CFrame.Position.Y - half)
			end
		end
		for _, d in item:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + V3.new(0, surface - low, 0)
			end
		end
		item.Parent = root
	end
	local cleaner = placed.AutoCleaner.PrimaryPart
	local shower = cleaner.CFrame:PointToWorldSpace(cleaner:FindFirstChild("WaterIn").CFrame.Position)
	local rollerTop = cleaner.CFrame:PointToWorldSpace(V3.new(0, 2.16 - 0.15, 0)).Y
	ore("Raw", "Copper", CF.new(shower.X, rollerTop + 1, shower.Z) * CF.Angles(0, 0.4, 0), rollerTop, 7)
	-- water as the client shows it: the station idles gently, the cleaner
	-- works and its shower hits the dirty ore (about 1.1 tall)
	Gallery.water(Loader, root, placed.CleaningStation, 0.4)
	Gallery.water(Loader, root, placed.AutoCleaner, 1, rollerTop + 1.05)
	local function onBelt(belt: any, x: number, z: number): (any, number)
		local cf = belt:GetPivot() * CF.new(x, 1.5, z)
		return cf, belt:FindFirstChild("Belt").CFrame.Position.Y + 0.25
	end
	local cf1, top1 = onBelt(belts[1], 0.1, 0.6)
	ore("Raw", "Iron", cf1 * CF.Angles(0, 1.1, 0), top1, 11)
	local cf3, top3 = onBelt(belts[3], -0.1, -0.4)
	ore("Clean", "Copper", cf3 * CF.Angles(0, 0.7, 0), top3, 5)
	local cf4, top4 = onBelt(belts[4], 0.2, 0.8)
	ore("Clean", "Silver", cf4 * CF.Angles(0, 2.1, 0), top4, 9)

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
