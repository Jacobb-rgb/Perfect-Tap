--[[
	The dropper belt reel (owner 2026-10-24: "send me a VIDEO of how it works
	and looks"), frame by frame for tools/preview/world_anim.html
	(?data=dropper_belts): on a plot, a Heaven Dropper at the start of a belt
	and a Lava Dropper standing beside it, both nozzles over the belt; their
	Drops fall onto the belt, ride it (GameConfig.ConveyorSpeed), go through
	the little Money Laser gate (doubled once, "2X"), and sell in the Sell Box
	("+$"). Every model is the game's own (MachineBuilder, ItemBuilder: the
	Drops' look), placed with the game's Grid (Grid.localCFrame,
	Grid.outputLocal, Grid.outputCell), the Drops' values from DropperConfig.

	  lune run tools/lune/export_world_motion.luau 30 dropper_belts
	  node tools/preview/render_world_anim.mjs 1280 720 6000000 - dropper_belts droppery_pas
]]

local roblox = require("@lune/roblox") :: any

local Reel = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Instance = roblox.Instance

local GRAVITY = 196.2

function Reel.build(Loader, opts)
	local CF = Loader.CFrame
	local H = require("./world_motion_preview").helpers
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local fps = opts and opts.fps or 30
	local dt = 1 / fps
	local CELL = GameConfig.CellSize
	local SPEED = GameConfig.ConveyorSpeed
	local LASER = DropperConfig.Laser.Id

	-- the facing whose front is +X (the belt's way) and +Z (the side dropper's)
	local function facing(dx: number, dz: number): number
		for r = 0, 3 do
			local x, z = Grid.dir(r)
			if x == dx and z == dz then
				return r
			end
		end
		error("no facing")
	end
	local rX, rZ = facing(1, 0), facing(0, 1)

	-- where a machine's min cell must be so that its Output cell is (ox, oz)
	local function placeFor(id: string, r: number, ox: number, oz: number): (number, number)
		for gx = 0, 15 do
			for gz = 0, 15 do
				local x, z = Grid.outputCell(id, gx, gz, r)
				if x == ox and z == oz then
					return gx, gz
				end
			end
		end
		error("no place for " .. id)
	end

	-- the layout (plot cells): the belt row z0, belts from x 3, the laser, the Sell Box
	local z0 = 8
	local heaven, lava = "GoldDropper", "RedDropper"
	local ax, az = placeFor(heaven, rX, 3, z0)
	local bx, bz = placeFor(lava, rZ, 5, z0)
	local belts = { 3, 4, 5, 6, 8, 9, 10 }
	local laserX = 7
	local sellX = 11

	local root = Instance.new("Model")
	-- the plot floor: light metal tiles with seams (the plot's look)
	Geo.block(root, CF.new(0, -0.5, 0), V3.new(90, 1, 90), C3.fromRGB(188, 192, 204))
	for i = -11, 11 do
		Geo.block(root, CF.new(i * CELL, 0.01, 0), V3.new(0.08, 0.02, 90), C3.fromRGB(150, 154, 170))
		Geo.block(root, CF.new(0, 0.01, i * CELL), V3.new(90, 0.02, 0.08), C3.fromRGB(150, 154, 170))
	end
	local placed: { [string]: any } = {}
	local function put(key: string, id: string, gx: number, gz: number, r: number)
		local model = MachineBuilder.build(id)
		local cf = Grid.localCFrame(id, gx, gz, r)
		model:PivotTo(cf)
		model.Parent = root
		placed[key] = { Model = model, CFrame = cf, Id = id }
	end
	put("A", heaven, ax, az, rX)
	put("B", lava, bx, bz, rZ)
	for _, x in belts do
		put("belt" .. x, "Conveyor", x, z0, rX)
	end
	put("laser", LASER, laserX, z0, rX)
	-- (the Sell Box's 2 x 2 covers the belt's row and the one beside it)
	-- (its front, the coin and the SELL screen, toward the camera: the belt feeds its side)
	put("sell", "SellBox", sellX, z0 - 1, rZ)

	-- the studded style every client gives the plot and its machines (owner 2026-10-24: "A")
	local StudStyle = Loader.requirePath("ReplicatedStorage.Shared.StudStyle")
	for _, d in root:GetDescendants() do
		-- Lune cannot read an unset MaterialVariant (an alias of MaterialVariantSerialized)
		if d:IsA("BasePart") and not pcall(function()
			return d.MaterialVariant
		end) then
			d.MaterialVariant = ""
		end
	end
	StudStyle.applyTree(root, "Classic")

	local parts = {}
	for _, d in H.visibleParts(root) do
		table.insert(parts, H.partEntry(d))
	end

	-- world points: a cell's centre, an Output
	local function cellCenter(gx: number, gz: number): any
		return Grid.localCFrame("Conveyor", gx, gz, rX).Position
	end
	local function outputOf(key: string): any
		local p = placed[key]
		return (p.CFrame * CF.new(Grid.outputLocal(p.Id))).Position
	end
	local beltY = 0.8 -- the belt surface
	local laserIn = cellCenter(laserX, z0).X - CELL / 2 - 0.4
	local laserOut = outputOf("laser")
	local laserCell = cellCenter(laserX, z0)
	-- (a Drop rides off the belt's end into the Sell Box's side curtain)
	local sellIn = placed.sell.CFrame.Position.X - 3.0
	local rowZ = cellCenter(3, z0).Z

	-- the Drops' looks: one rigid group per dropper and mark (a few seeds each)
	local data = {
		fps = fps,
		scenes = { { id = "plot", parts = parts, lights = {}, look = "day", decals = H.surfaceDecals(root) } },
		groups = {},
		frames = {},
		sheetTitle = "droppery sypou rudu na pás",
		picks = { 1.2, 3.4, 6.0, 7.6, 9.6, 12.2, 14.4, 16.5, 19.0, 21.5 },
		segments = {
			{ title = "DROPPER SYPE RUDU NA PÁS", sub = "kohoutek míří nad pás: ruda padá rovnou na něj", cut = false },
			{ title = "DROPPER VEDLE PÁSU", sub = "postav ho bokem k pásu, kohoutkem nad pás", cut = false },
			{ title = "MONEY LASER 2X", sub = "malá brána na pásu: ruda projede a její cena se zdvojnásobí", cut = false },
			{ title = "SELL BOX", sub = "ruda dojede do Sell Boxu a prodá se", cut = false },
			{ title = "CELÁ LINKA", sub = "Heaven + Lava Dropper, laser, Sell Box", cut = false },
		},
	}
	local looks: { [string]: { number } } = {}
	local function lookOf(id: string, marked: boolean, seed: number): number
		local key = id .. (if marked then "X" else "") .. seed
		local index = looks[key]
		if index then
			return index[1]
		end
		local model = ItemBuilder.build({
			Kind = "Drop",
			OreId = id,
			Recipe = if marked then DropperConfig.LaserMark else nil,
		}, CF.new(), seed)
		local inv = model.PrimaryPart.CFrame:Inverse()
		local gparts = {}
		for _, d in H.visibleParts(model) do
			table.insert(gparts, H.partEntry(d, inv * d.CFrame))
		end
		table.insert(data.groups, { parts = gparts })
		local i = #data.groups - 1
		looks[key] = { i }
		return i
	end

	-- the simulation: Drops fall, ride, pass the laser, sell
	type Drop = { Id: string, Pos: any, Vel: any, Yaw: number, Seed: number, Marked: boolean, State: string, Wait: number }
	local drops: { Drop } = {}
	local pops: { { Text: string, Line: string?, Pos: any, Born: number } } = {}
	local spawners = {
		{ Key = "A", Id = heaven, Next = 0.3 },
		{ Key = "B", Id = lava, Next = 2.95 }, -- (half a cycle behind on the laser: one "2X" at a time)
	}
	local seedN = 0
	local duration = 23.5
	local prewarm = 6 -- seconds simulated before the first frame (the belt has ore on it)
	local frames = math.floor(duration * fps + 0.5)
	local function stepSim(t: number)
		for _, s in spawners do
			if t >= s.Next then
				s.Next += DropperConfig.DropEvery
				seedN += 1
				table.insert(drops, {
					Id = s.Id,
					Pos = outputOf(s.Key),
					Vel = V3.new(0, -2, 0),
					Yaw = seedN * 1.3,
					Seed = 1 + seedN % 3,
					Marked = false,
					State = "Fall",
					Wait = 0,
				})
			end
		end
		local keep = {}
		for _, d in drops do
			local rest = beltY + 0.55
			if d.State == "Fall" then
				d.Vel = d.Vel - V3.new(0, GRAVITY * dt, 0)
				d.Pos = d.Pos + d.Vel * dt
				if d.Pos.Y <= rest then
					d.Pos = V3.new(d.Pos.X, rest, d.Pos.Z)
					d.State = "Ride"
				end
			elseif d.State == "Ride" then
				-- the belt carries it toward +X, and toward the middle of the belt
				local x = d.Pos.X + SPEED * dt
				local z = d.Pos.Z + (rowZ - d.Pos.Z) * math.min(1, dt * 4)
				d.Pos = V3.new(x, rest, z)
				d.Yaw += dt * 0.6
				if not d.Marked and x >= laserIn then
					d.State = "Laser"
					d.Wait = 0.15
				elseif x >= sellIn then
					d.State = "Sold"
					local value = DropperConfig.dropValue(d.Id, d.Marked)
					table.insert(pops, { Text = "+" .. Format.money(value), Line = nil, Pos = d.Pos + V3.new(1.5, 3.4, 0), Born = t })
				end
			elseif d.State == "Laser" then
				d.Wait -= dt
				if d.Wait <= 0 then
					d.Marked = true
					d.State = "Fall"
					d.Pos = laserOut
					d.Vel = V3.new(GameConfig.OutputPop.Forward, GameConfig.OutputPop.Up, 0)
					local lift = 0
					for _, p in pops do
						if p.Text == "2X" and t - p.Born < 0.8 then
							lift = math.max(lift, 1.4 - (t - p.Born) * 1.6)
						end
					end
					table.insert(pops, { Text = "2X", Line = nil, Pos = laserOut + V3.new(0, 2.4 + lift, 0), Born = t })
				end
			end
			if d.State == "Fall" and d.Marked then
				-- (out of the laser it pops forward and lands on the belt in front)
				local x = d.Pos.X + 0
				d.Pos = V3.new(x, d.Pos.Y, d.Pos.Z)
			end
			if d.State ~= "Sold" then
				table.insert(keep, d)
			end
		end
		drops = keep
	end

	for _, sp in spawners do
		sp.Next -= prewarm
	end
	local t = -prewarm
	while t < 0 do
		stepSim(t)
		t += dt
	end
	local center = (placed.A.CFrame.Position + placed.sell.CFrame.Position) / 2
	local aOut, bOut = outputOf("A"), outputOf("B")
	local sellAt = placed.sell.CFrame.Position
	for i = 0, frames - 1 do
		local now = i * dt
		stepSim(now)
		local camPos, camTarget, fov = H.cameraAt({
			{ 0, aOut + V3.new(-6, 5, 16), aOut + V3.new(1.5, -3.5, 0), 46 },
			{ 4.2, aOut + V3.new(-3, 4, 15), aOut + V3.new(2.5, -3.5, 0), 44 },
			{ 5.4, bOut + V3.new(-9, 6, 14), bOut + V3.new(1, -3.6, 0), 46 },
			{ 9.2, bOut + V3.new(-5, 5, 15), bOut + V3.new(2, -3.6, 0), 44 },
			{ 10.4, laserCell + V3.new(-9, 7, 11), laserCell + V3.new(1, 1.2, 0), 44 },
			{ 14.2, laserCell + V3.new(-5, 6, 10), laserCell + V3.new(1.5, 1.2, 0), 42 },
			{ 15.4, sellAt + V3.new(-11, 7, 15), sellAt + V3.new(-2.5, 2.2, 0), 46 },
			{ 18.6, sellAt + V3.new(-6, 6, 14), sellAt + V3.new(-1.5, 2.4, 0), 44 },
			{ 19.8, center + V3.new(-4, 26, 30), center + V3.new(0, 0, -2), 48 },
			{ duration, center + V3.new(4, 24, 30), center + V3.new(0, 0, -2), 48 },
		}, now)
		local seg = if now < 5 then 0 elseif now < 9.8 then 1 elseif now < 15 then 2 elseif now < 19.4 then 3 else 4
		local frame = {
			s = 0,
			seg = seg,
			cam = { H.r3(camPos.X), H.r3(camPos.Y), H.r3(camPos.Z), H.r3(camTarget.X), H.r3(camTarget.Y), H.r3(camTarget.Z), H.r3(fov) },
			g = {},
			p = {},
			o = {},
		}
		for _, d in drops do
			if d.State ~= "Laser" then
				local list = H.cfList(CF.new(d.Pos) * CF.Angles(0, d.Yaw, 0))
				table.insert(list, 1, lookOf(d.Id, d.Marked, d.Seed))
				table.insert(frame.g, list)
			end
		end
		-- the laser's flash while a Drop is inside
		for _, d in drops do
			if d.State == "Laser" then
				local k = d.Wait / 0.15
				table.insert(
					frame.p,
					H.entry(
						H.SHAPES.Block,
						V3.new(0.6, 2.5, 2.7),
						CF.new(laserCell + V3.new(0, 1.6, 0)),
						C3.fromRGB(124, 255, 150),
						"Neon",
						0.3 + 0.5 * (1 - k),
						false
					)
				)
			end
		end
		local keepPops = {}
		for _, p in pops do
			local age = now - p.Born
			if age < 1.4 then
				local alpha = math.clamp(1 - (age - 0.9) / 0.5, 0, 1)
				local pos = p.Pos + V3.new(0, age * 1.6, 0)
				table.insert(
					frame.o,
					{ p.Text, p.Line or "", H.r3(pos.X), H.r3(pos.Y), H.r3(pos.Z), H.r3(alpha), H.r3(0.9 + math.min(age, 0.2)) }
				)
				table.insert(keepPops, p)
			end
		end
		pops = keepPops
		table.insert(data.frames, frame)
	end
	data.duration = #data.frames / fps
	return data
end

return Reel
