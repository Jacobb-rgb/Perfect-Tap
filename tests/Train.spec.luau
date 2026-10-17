-- Ore train models (TrainBuilder): part budgets for phones, PrimaryPart at the
-- bottom center, couplers, spinning wheels, the smoke point, determinism and
-- client-visual parts (nothing collides).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local Color3 = roblox.Color3
	local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")

	-- the plot banner colors (PlotBuilder) + an ore mix
	local COLORS = {
		Color3.fromRGB(220, 70, 50),
		Color3.fromRGB(240, 170, 40),
		Color3.fromRGB(80, 180, 90),
		Color3.fromRGB(60, 140, 220),
		Color3.fromRGB(160, 90, 220),
		Color3.fromRGB(230, 110, 170),
		Color3.fromRGB(60, 190, 190),
		Color3.fromRGB(240, 230, 210),
	}
	local ORES = { Color3.fromRGB(222, 120, 60), Color3.fromRGB(150, 156, 170), Color3.fromRGB(58, 54, 60) }

	local function hex(c: any): string
		return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end

	local function parts(model: any): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function find(model: any, className: string, name: string): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA(className) and d.Name == name then
				table.insert(list, d)
			end
		end
		return list
	end

	-- model-space position of an attachment (models are built at the origin)
	local function worldOf(a: any): any
		return (a.Parent.CFrame * a.CFrame).Position
	end

	local function bounds(model: any): (any, any)
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		for _, p in parts(model) do
			if p.Transparency < 1 then
				local half = p.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local c = (p.CFrame * roblox.CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
							lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
							hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z))
						end
					end
				end
			end
		end
		return lo, hi
	end

	local function vehicles(): { { any } }
		local list = {}
		for _, color in COLORS do
			table.insert(list, { "locomotive", TrainBuilder.locomotive(color) })
			table.insert(list, { "wagon", TrainBuilder.wagon(color, ORES) })
			table.insert(list, { "empty wagon", TrainBuilder.wagon(color) })
		end
		table.insert(list, { "locomotive (trim)", TrainBuilder.locomotive(COLORS[1], COLORS[8]) })
		table.insert(list, { "wagon (1 ore)", TrainBuilder.wagon(COLORS[2], { ORES[1] }) })
		table.insert(list, { "wagon (8 ores)", TrainBuilder.wagon(COLORS[3], COLORS) })
		table.insert(list, { "wagon ({})", TrainBuilder.wagon(COLORS[4], {}) })
		return list
	end

	T.test("Train: part budgets (locomotive <= 60, wagon <= 20, track 4 + 1 per sleeper)", function()
		for _, entry in vehicles() do
			local count = #parts(entry[2])
			local max = if entry[1]:find("locomotive") then TrainBuilder.MaxLocomotiveParts else TrainBuilder.MaxWagonParts
			T.le(count, max, entry[1] .. " parts")
		end
		T.eq(TrainBuilder.MaxLocomotiveParts, 60)
		T.eq(TrainBuilder.MaxWagonParts, 20)
		for _, length in { 1, 6, 12, 47, 48, 120, 200 } do
			local track = TrainBuilder.track(length)
			local sleepers = #find(track, "BasePart", "Sleeper")
			T.truthy(sleepers >= 1, "a track has sleepers")
			T.le(#parts(track), 4 + sleepers, `track {length} parts`)
		end
	end)

	T.test("Train: PrimaryPart Root at the bottom center, models sit on y = 0", function()
		for _, entry in vehicles() do
			local model = entry[2]
			local root = model.PrimaryPart
			T.truthy(root, entry[1] .. " PrimaryPart")
			T.eq(root.Name, "Root", entry[1] .. " PrimaryPart name")
			T.eq(root.Transparency, 1, entry[1] .. " Root is invisible")
			T.truthy((root.CFrame.Position - Vector3.new(0, 0, 0)).Magnitude < 1e-6, entry[1] .. " Root at the origin")
			local lo, hi = bounds(model)
			T.near(lo.Y, 0, 0.02, entry[1] .. " wheels touch y = 0")
			T.near((lo.X + hi.X) / 2, 0, 0.05, entry[1] .. " centered in X")
		end
		local track = TrainBuilder.track(48)
		T.eq(track.PrimaryPart.Name, "Root")
		local lo, hi = bounds(track)
		T.near(lo.Y, 0, 1e-3, "track bottom at y = 0")
		T.near(hi.Y, TrainBuilder.RailTop, 1e-3, "rail top")
		T.near(lo.Z, -24, 1e-3, "track starts at -length/2")
		T.near(hi.Z, 24, 1e-3, "track ends at +length/2")
	end)

	T.test("Train: sizes next to a 5-stud character (locomotive ~6 x 8 x 14)", function()
		local lo, hi = bounds(TrainBuilder.locomotive(COLORS[1]))
		local size = hi - lo
		T.truthy(size.X >= 5.5 and size.X <= 7, `locomotive width {size.X}`)
		T.truthy(size.Y >= 7.5 and size.Y <= 9, `locomotive height {size.Y}`)
		T.truthy(size.Z >= 13 and size.Z <= 15.5, `locomotive length {size.Z}`)
		local wlo, whi = bounds(TrainBuilder.wagon(COLORS[1], ORES))
		local wsize = whi - wlo
		T.truthy(wsize.X <= size.X + 0.2, "wagon not wider than the locomotive")
		T.truthy(wsize.Y <= size.Y + 0.6, `loaded wagon not much taller than the locomotive ({wsize.Y} vs {size.Y})`)
		-- the front is -Z: the chimney and the cow-catcher are in the front half
		local chimney = find(TrainBuilder.locomotive(COLORS[1]), "BasePart", "Chimney")[1]
		T.truthy(chimney.CFrame.Position.Z < 0, "chimney at the front (-Z)")
		local cab = find(TrainBuilder.locomotive(COLORS[1]), "BasePart", "Cab")[1]
		T.truthy(cab.CFrame.Position.Z > 0, "cab at the back (+Z)")
	end)

	T.test("Train: couplers on the bogies at the ends, chained trains touch", function()
		for _, entry in vehicles() do
			local model = entry[2]
			local front = find(model, "Attachment", "CouplerFront")
			local back = find(model, "Attachment", "CouplerBack")
			T.eq(#front, 1, entry[1] .. " one CouplerFront")
			T.eq(#back, 1, entry[1] .. " one CouplerBack")
			T.eq(front[1].Parent.Name, "BogieFront", entry[1] .. " CouplerFront on BogieFront")
			T.eq(back[1].Parent.Name, "BogieBack", entry[1] .. " CouplerBack on BogieBack")
			local f, b = worldOf(front[1]), worldOf(back[1])
			T.near(f.X, 0, 1e-4)
			T.near(b.X, 0, 1e-4)
			T.near(f.Y, TrainBuilder.CouplerHeight, 1e-4, entry[1] .. " coupler height")
			T.near(b.Y, TrainBuilder.CouplerHeight, 1e-4, entry[1] .. " coupler height")
			T.truthy(f.Z < 0 and b.Z > 0, entry[1] .. " front coupler at -Z, back at +Z")
			T.near(model:GetAttribute("Length"), b.Z - f.Z, 1e-4, entry[1] .. " Length attribute")
			-- couplers sit at the ends: no visible part reaches past them except the cow-catcher
			local lo, hi = bounds(model)
			T.truthy(hi.Z <= b.Z + 1e-3, entry[1] .. " nothing behind CouplerBack")
			if entry[1]:find("wagon") then
				T.truthy(lo.Z >= f.Z - 1e-3, entry[1] .. " nothing in front of CouplerFront")
			else
				T.truthy(lo.Z >= f.Z - 0.6, "only the cow-catcher reaches past the front buffers")
			end
			-- attachments keep the model's orientation (the controller chains by position)
			local rot = (front[1].Parent.CFrame * front[1].CFrame).LookVector
			T.near(rot.Z, -1, 1e-4, entry[1] .. " CouplerFront faces -Z")
		end
	end)

	T.test("Train: wheels are named Wheel, centered on their axles with a Radius", function()
		for _, entry in vehicles() do
			local wheels = find(entry[2], "BasePart", "Wheel")
			T.truthy(#wheels >= 4, entry[1] .. " has wheels")
			local axles = {}
			for _, wheel in wheels do
				local radius = wheel:GetAttribute("Radius")
				T.eq(typeof(radius), "number", entry[1] .. " wheel Radius")
				local p = wheel.CFrame.Position
				-- on the axle: centered in X, the center one radius above the rails
				T.near(p.X, 0, 1e-4, entry[1] .. " wheel centered on the axle")
				T.near(p.Y, radius, 1e-4, entry[1] .. " wheel center at its radius")
				-- the local X axis runs along the axle (spin about it)
				T.near(math.abs(wheel.CFrame.RightVector.X), 1, 1e-4, entry[1] .. " wheel X axis along the axle")
				axles[math.floor(p.Z * 100 + 0.5)] = true
			end
			local count = 0
			for _ in axles do
				count += 1
			end
			T.truthy(count >= 4, entry[1] .. " at least 4 axles")
		end
		-- the locomotive has big drive wheels and small front wheels
		local radii = {}
		for _, wheel in find(TrainBuilder.locomotive(COLORS[1]), "BasePart", "Wheel") do
			radii[wheel:GetAttribute("Radius")] = true
		end
		local sizes = 0
		for _ in radii do
			sizes += 1
		end
		T.eq(sizes, 2, "two wheel sizes on the locomotive")
	end)

	T.test("Train: Smoke at the chimney top, TipPivot on the wagon, hopper sub-model", function()
		local loco = TrainBuilder.locomotive(COLORS[4])
		local smoke = find(loco, "Attachment", "Smoke")
		T.eq(#smoke, 1, "one Smoke attachment")
		local p = worldOf(smoke[1])
		local chimney = find(loco, "BasePart", "Chimney")[1]
		T.near(p.X, 0, 1e-4)
		T.near(p.Z, chimney.CFrame.Position.Z, 1e-3, "Smoke above the chimney")
		local _, hi = bounds(loco)
		local top = -math.huge
		for _, part in parts(loco) do
			if part.Name:find("Chimney") then
				top = math.max(top, part.CFrame.Position.Y + part.Size.X / 2)
			end
		end
		T.truthy(p.Y >= top - 1e-3, "Smoke at the chimney top")
		T.truthy(p.Y <= hi.Y + 0.5, "Smoke near the top of the model")
		local up = (smoke[1].Parent.CFrame * smoke[1].CFrame).UpVector
		T.near(up.Y, 1, 1e-4, "Smoke points up")

		local wagon = TrainBuilder.wagon(COLORS[4], ORES)
		T.eq(#find(wagon, "Attachment", "TipPivot"), 1, "TipPivot")
		local hopper = wagon:FindFirstChild("Hopper")
		T.truthy(hopper and hopper:IsA("Model") and hopper.PrimaryPart, "Hopper model with a PrimaryPart")
		T.eq(#find(hopper, "BasePart", "Ore"), 4, "4 ore rocks in the hopper")
		T.eq(#find(TrainBuilder.wagon(COLORS[4]), "BasePart", "Ore"), 0, "empty wagon has no ore")
	end)

	T.test("Train: tipping the Hopper 40 degrees leaves the bogies, wheels and chassis in place", function()
		local CFrame = roblox.CFrame
		for _, wagon in { TrainBuilder.wagon(COLORS[2], ORES), TrainBuilder.wagon(COLORS[2]) } do
			local hopper = wagon:FindFirstChild("Hopper")
			T.eq(hopper.PrimaryPart.Name, "Rim", "the Hopper's PrimaryPart is a rim piece")
			-- the hopper holds only the tipping body and its load
			for _, p in parts(hopper) do
				T.truthy(
					p.Name ~= "BogieFront" and p.Name ~= "BogieBack" and p.Name ~= "Wheel" and p.Name ~= "Chassis",
					`{p.Name} is not running gear`
				)
			end
			local chassis = find(wagon, "BasePart", "Chassis")
			T.eq(#chassis, 1, "one chassis plate")
			T.truthy(chassis[1].Parent == wagon, "the chassis stays in the main model")
			local chassisTop = chassis[1].CFrame.Position.Y + chassis[1].Size.Y / 2
			local pivotAttachment = find(wagon, "Attachment", "TipPivot")[1]
			local pivot = pivotAttachment.Parent.CFrame * pivotAttachment.CFrame
			T.near(pivot.Position.Y, chassisTop, 1e-4, "the hinge sits on the chassis")
			local before = {}
			for _, p in parts(wagon) do
				if not p:IsDescendantOf(hopper) then
					before[p] = p.CFrame
				end
			end
			local rimBefore = hopper.PrimaryPart.CFrame.Position
			-- the client's dump: rotate about the hinge so the top goes to +X
			local tilt = pivot * CFrame.Angles(0, 0, -math.rad(40)) * pivot:Inverse()
			hopper:PivotTo(tilt * hopper:GetPivot())
			for p, cf in before do
				T.truthy((p.CFrame.Position - cf.Position).Magnitude < 1e-4, `{p.Name} did not move`)
			end
			T.truthy(hopper.PrimaryPart.CFrame.Position.X > rimBefore.X + 1, "the hopper tips toward +X")
			-- the tipped body rolls over the hinge: nothing sinks into the chassis
			local lowest = math.huge
			for _, p in parts(hopper) do
				local half = p.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							lowest = math.min(lowest, (p.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position.Y)
						end
					end
				end
			end
			T.truthy(lowest >= chassisTop - 1e-3, `tipped hopper stays above the chassis ({lowest} vs {chassisTop})`)
		end
	end)

	T.test("Train: hopper shape (open and deep when empty, a dome of upright rocks above the rim, narrower than the locomotive)", function()
		local function top(p: any): number
			return p.CFrame.Position.Y + p.Size.Y / 2
		end
		local empty = TrainBuilder.wagon(COLORS[2])
		local rimTop = -math.huge
		local rimX = 0
		for _, rim in find(empty, "BasePart", "Rim") do
			rimTop = math.max(rimTop, top(rim))
			rimX = math.max(rimX, math.abs(rim.CFrame.Position.X) + rim.Size.X / 2)
		end
		local inside = find(empty, "BasePart", "Inside")
		T.eq(#inside, 1, "empty hopper has a floor plate")
		T.truthy(rimTop - top(inside[1]) >= 2.5, `empty hopper is deep ({rimTop - top(inside[1])} studs)`)
		-- the hopper walls: the flanks' inner faces (the opening) and their sloped
		-- outer faces (bottom edge -> top edge); the end walls close the ends
		local flank = find(empty, "BasePart", "Flank")[1]
		local inner = math.abs(flank.CFrame.Position.X) - flank.Size.Z / 2
		local outerTop = math.abs(flank.CFrame.Position.X) + flank.Size.Z / 2
		local floorY = flank.CFrame.Position.Y - flank.Size.Y / 2
		local brimY = flank.CFrame.Position.Y + flank.Size.Y / 2
		local walls = find(empty, "BasePart", "EndWall")
		T.eq(#walls, 2, "two end walls")
		local innerZ, endZ = math.huge, 0
		for _, wall in walls do
			innerZ = math.min(innerZ, math.abs(wall.CFrame.Position.Z) - wall.Size.Z / 2)
			endZ = math.max(endZ, math.abs(wall.CFrame.Position.Z) + wall.Size.Z / 2)
			-- one clean block per end, as wide as the flanks' top edge (no body-colored
			-- flank wings beside it)
			T.near(wall.Size.X / 2, outerTop, 1e-4, "end wall as wide as the flank tops")
		end
		T.near(flank.Size.X / 2, innerZ, 1e-4, "the flanks stop at the end walls")
		local function wallX(y: number): number
			return inner + (outerTop - inner) * (y - floorY) / (brimY - floorY)
		end
		-- loaded: the bed sits just under the rim; four blocks (no balls), mostly
		-- upright, stay inside the walls, stand mostly above the bed and make one
		-- dome that is highest in the middle and lower toward the ends
		local loaded = TrainBuilder.wagon(COLORS[2], ORES)
		local bed = find(loaded, "BasePart", "OreBed")
		T.eq(#bed, 1, "loaded hopper has an ore bed")
		local bedTop = top(bed[1])
		T.truthy(bedTop < rimTop and bedTop > rimTop - 0.5, "ore bed just under the rim")
		local lo, hi = bounds(loaded)
		local peaks = {}
		local turned = {}
		for _, ore in find(loaded, "BasePart", "Ore") do
			T.eq(ore.ClassName, "Part", "ore rock is a Part")
			T.eq(ore.Shape, roblox.Enum.PartType.Block, "ore rock is a faceted block, not a ball")
			T.eq(ore.Material, roblox.Enum.Material.SmoothPlastic, "ore rock is SmoothPlastic")
			local up = ore.CFrame.UpVector
			-- a broad, slightly tipped top facet: tilted by about 6 to 25 degrees
			T.truthy(up.Y > 0.9 and up.Y < 0.995, `ore rock mostly upright, slightly tipped (up.Y {up.Y})`)
			turned[string.format("%.2f,%.2f,%.2f", up.X, up.Y, up.Z)] = true
			local half = ore.Size / 2
			local peak, low = -math.huge, math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = (ore.CFrame * roblox.CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
						peak = math.max(peak, c.Y)
						low = math.min(low, c.Y)
						T.truthy(c.Y >= floorY, "rock stays above the hopper floor")
						if c.Y > rimTop then
							-- above the rim: over the opening (may rest on the rim's inner edge)
							T.truthy(math.abs(c.X) <= inner + 0.45, `rock above the rim stays over the opening (x {c.X})`)
							T.truthy(math.abs(c.Z) <= innerZ + 0.45, `rock above the rim stays over the opening (z {c.Z})`)
						else
							T.truthy(math.abs(c.X) <= wallX(c.Y) + 1e-3, `rock corner inside the flank (x {c.X} at y {c.Y})`)
							T.truthy(math.abs(c.Z) <= endZ + 1e-3, `rock corner inside the end wall (z {c.Z})`)
						end
					end
				end
			end
			T.truthy(peak > rimTop + 0.8, "rock peaks above the rim")
			local shown = (peak - bedTop) / (peak - low)
			T.truthy(shown >= 0.5 and shown <= 0.7, `rock stands mostly above the bed ({shown})`)
			table.insert(peaks, { Z = ore.CFrame.Position.Z, Peak = peak })
		end
		T.eq(#peaks, 4, "four ore rocks")
		local distinct = 0
		for _ in turned do
			distinct += 1
		end
		T.eq(distinct, 4, "every rock is turned its own way")
		table.sort(peaks, function(a, b)
			return a.Peak > b.Peak
		end)
		T.truthy(math.abs(peaks[1].Z) < 1, "the mound peaks in the middle")
		for _, p in peaks do
			if math.abs(p.Z) > 2 then
				T.truthy(p.Peak < peaks[1].Peak - 0.2, `the heap is lower toward the ends ({p.Peak} vs {peaks[1].Peak})`)
			end
		end
		T.truthy(math.abs(hi.Z - lo.Z) <= 12.01, "nothing sticks out past the couplers")
		local llo, lhi = bounds(TrainBuilder.locomotive(COLORS[2]))
		local ratio = (hi.X - lo.X) / (lhi.X - llo.X)
		T.truthy(ratio >= 0.75 and ratio <= 0.92, `wagon about 85 % of the locomotive width ({ratio})`)
		T.truthy(rimX <= 2.9, "rim narrower than the locomotive")
	end)

	T.test("Train: wagon running gear (dark side frames outboard of the wheels, over their upper half)", function()
		for _, wagon in { TrainBuilder.wagon(COLORS[5], ORES), TrainBuilder.wagon(COLORS[5]) } do
			local wheels = find(wagon, "BasePart", "Wheel")
			for _, name in { "BogieFront", "BogieBack" } do
				local bogie = find(wagon, "BasePart", name)[1]
				local bz0 = bogie.CFrame.Position.Z - bogie.Size.Z / 2
				local bz1 = bogie.CFrame.Position.Z + bogie.Size.Z / 2
				local bottom = bogie.CFrame.Position.Y - bogie.Size.Y / 2
				local covered = 0
				for _, wheel in wheels do
					local z = wheel.CFrame.Position.Z
					if z > bz0 and z < bz1 then
						covered += 1
						T.truthy(bogie.Size.X / 2 > wheel.Size.X / 2 + 0.1, `{name} side frame outboard of the wheel ends`)
						T.near(bottom, wheel.CFrame.Position.Y, 0.15, `{name} bottom at axle height`)
					end
				end
				T.eq(covered, 2, `{name} carries two axles`)
				local frame, wheel = bogie.Color, wheels[1].Color
				T.truthy(frame.R + frame.G + frame.B < wheel.R + wheel.G + wheel.B - 0.6, `{name} frame darker than the wheels`)
			end
		end
	end)

	T.test("Train: wagons in a consist show a gap between the hoppers and under the middle", function()
		for _, wagon in { TrainBuilder.wagon(COLORS[3], ORES), TrainBuilder.wagon(COLORS[3]) } do
			local front = worldOf(find(wagon, "Attachment", "CouplerFront")[1])
			local back = worldOf(find(wagon, "Attachment", "CouplerBack")[1])
			-- rims are axis-aligned blocks; a flank wedge runs along Z with its length in Size.X
			local hopperZ = 0
			for _, rim in find(wagon, "BasePart", "Rim") do
				hopperZ = math.max(hopperZ, math.abs(rim.CFrame.Position.Z) + rim.Size.Z / 2)
			end
			for _, flank in find(wagon, "BasePart", "Flank") do
				hopperZ = math.max(hopperZ, math.abs(flank.CFrame.Position.Z) + flank.Size.X / 2)
			end
			for _, wall in find(wagon, "BasePart", "EndWall") do
				hopperZ = math.max(hopperZ, math.abs(wall.CFrame.Position.Z) + wall.Size.Z / 2)
			end
			T.truthy(hopperZ <= back.Z - 0.6 + 1e-4, `hopper rim ends 0.6 before CouplerBack ({hopperZ} vs {back.Z})`)
			T.truthy(hopperZ <= -front.Z - 0.6 + 1e-4, `hopper rim ends 0.6 before CouplerFront ({hopperZ} vs {front.Z})`)
			T.near(TrainBuilder.HopperEndZ, hopperZ, 1e-4, "HopperEndZ")
			-- Kenney's end plates in the body color stand out of both end walls; the
			-- loaded wagon's single through-plate stays hidden under the ore bed
			local plates = find(wagon, "BasePart", "EndPlate")
			T.truthy(#plates >= 1, "end plates")
			local plateLo, plateHi = math.huge, -math.huge
			for _, plate in plates do
				T.eq(hex(plate.Color), hex(COLORS[3]), "end plate in the body color")
				plateLo = math.min(plateLo, plate.CFrame.Position.Z - plate.Size.Z / 2)
				plateHi = math.max(plateHi, plate.CFrame.Position.Z + plate.Size.Z / 2)
				local bed = find(wagon, "BasePart", "OreBed")[1]
				if bed then
					T.truthy(
						plate.CFrame.Position.Y + plate.Size.Y / 2 < bed.CFrame.Position.Y - bed.Size.Y / 2,
						"through-plate under the bed"
					)
				end
			end
			T.truthy(plateHi >= hopperZ + 0.15 and plateHi < back.Z, "end plate on the back wall")
			T.truthy(plateLo <= -hopperZ - 0.15 and plateLo > front.Z, "end plate on the front wall")
			-- the two bogies are apart: the ground shows under the middle of the hopper
			local frontBogie = find(wagon, "BasePart", "BogieFront")[1]
			local backBogie = find(wagon, "BasePart", "BogieBack")[1]
			local frontEnd = frontBogie.CFrame.Position.Z + frontBogie.Size.Z / 2
			local backStart = backBogie.CFrame.Position.Z - backBogie.Size.Z / 2
			T.truthy(backStart - frontEnd >= 2.5, `gap between the bogies ({backStart - frontEnd})`)
			for _, p in parts(wagon) do
				if p.Transparency < 1 and p.Name ~= "Wheel" then
					local bottom = p.CFrame.Position.Y - p.Size.Y / 2
					local z0 = p.CFrame.Position.Z - p.Size.Z / 2
					local z1 = p.CFrame.Position.Z + p.Size.Z / 2
					if z0 < 0.5 and z1 > -0.5 then
						T.truthy(bottom >= 1.5, `{p.Name} leaves the middle under the hopper open`)
					end
				end
			end
		end
	end)

	T.test("Train: colors (body, trim, load colors cycle)", function()
		local red, white = COLORS[1], COLORS[8]
		local loco = TrainBuilder.locomotive(red)
		T.eq(hex(find(loco, "BasePart", "Cab")[1].Color), hex(red), "cab in the body color")
		T.eq(hex(find(loco, "BasePart", "Boiler")[1].Color), hex(red), "boiler in the body color")
		local trimmed = TrainBuilder.locomotive(red, white)
		T.eq(hex(find(trimmed, "BasePart", "CabBand")[1].Color), hex(white), "trim color")
		local brass = TrainBuilder.Colors.Brass
		T.eq(hex(find(loco, "BasePart", "CabBand")[1].Color), hex(brass), "default brass trim")
		-- a brass-like body (the amber banner) gets a contrasting trim; every banner
		-- color's trim stands apart from the body
		local amber = TrainBuilder.locomotive(COLORS[2])
		T.truthy(hex(find(amber, "BasePart", "CabBand")[1].Color) ~= hex(brass), "amber body: no brass trim")
		T.eq(hex(TrainBuilder.locomotive(COLORS[8]):FindFirstChild("CabBand").Color), hex(brass), "cream body keeps brass")
		for _, color in COLORS do
			local band = TrainBuilder.locomotive(color):FindFirstChild("CabBand").Color
			local diff = math.abs(band.R - color.R) + math.abs(band.G - color.G) + math.abs(band.B - color.B)
			T.truthy(diff >= 0.3, `trim stands apart from the body {hex(color)} ({diff})`)
		end
		-- Kenney's slate roof: a cool grey (it stays slate, not brown, under the warm
		-- golden-hour light) that is darker than the light bodies (cream, amber,
		-- pink, teal, green), so they keep a cab/roof edge
		local function luma(c: any): number
			return 0.3 * c.R + 0.59 * c.G + 0.11 * c.B
		end
		local roof = find(loco, "BasePart", "Roof")[1].Color
		local _, roofSat = roof:ToHSV()
		T.truthy(roof.B > roof.R and roof.B > roof.G and roofSat < 0.35, "roof is a cool slate grey")
		for _, color in COLORS do
			if luma(color) > 0.54 then
				T.truthy(luma(roof) < luma(color) - 0.08, `roof darker than {hex(color)}`)
			end
		end
		-- the front corner parts on every body color: the buffer beam is clearly
		-- darker than the body and the steam cylinders a shade darker
		for _, color in COLORS do
			local l = TrainBuilder.locomotive(color)
			for _, beam in find(l, "BasePart", "BufferBeam") do
				T.truthy(luma(beam.Color) < luma(color) - 0.1, `buffer beam darker than the body {hex(color)}`)
			end
			for _, cylinder in find(l, "BasePart", "SteamCylinder") do
				T.truthy(luma(cylinder.Color) < luma(color) - 0.03, `steam cylinder a shade darker than {hex(color)}`)
			end
		end
		-- the rubble bed under the rocks is the same neutral dark rock for every load
		-- (a teal or gold first ore never turns the gaps into water or slime)
		local beds = {}
		for _, load in { ORES, { COLORS[7] }, { COLORS[2], ORES[1] } } do
			local bed = find(TrainBuilder.wagon(red, load), "BasePart", "OreBed")[1].Color
			beds[hex(bed)] = true
			local _, sat, val = bed:ToHSV()
			T.truthy(sat < 0.3 and val < 0.4, "ore bed is dark neutral rubble")
		end
		local bedShades = 0
		for _ in beds do
			bedShades += 1
		end
		T.eq(bedShades, 1, "one bed color for every load")
		local wagon = TrainBuilder.wagon(red, ORES)
		for _, flank in find(wagon, "BasePart", "Flank") do
			T.eq(hex(flank.Color), hex(red), "hopper sides in the body color")
		end
		for _, load in { ORES, { ORES[1], ORES[3] }, { ORES[2] } } do
			local seen = {}
			for _, ore in find(TrainBuilder.wagon(red, load), "BasePart", "Ore") do
				seen[hex(ore.Color)] = (seen[hex(ore.Color)] or 0) + 1
			end
			for _, c in load do
				T.truthy(seen[hex(c)], "every load color shows exactly")
			end
		end
		-- one ore color: alternate rocks are a shade darker so the facets read
		local shades = {}
		for _, ore in find(TrainBuilder.wagon(red, { ORES[1] }), "BasePart", "Ore") do
			shades[hex(ore.Color)] = true
		end
		local count = 0
		for _ in shades do
			count += 1
		end
		T.eq(count, 2, "a one-color load shows two shades")
	end)

	T.test("Train: locomotive details (rods on the drive wheels, cab openings, chimney crown, tucked cow-catcher)", function()
		local loco = TrainBuilder.locomotive(COLORS[1])
		-- the drive wheels: the big axles (the largest Radius)
		local driveR, driveZ = 0, {}
		for _, wheel in find(loco, "BasePart", "Wheel") do
			driveR = math.max(driveR, wheel:GetAttribute("Radius"))
		end
		for _, wheel in find(loco, "BasePart", "Wheel") do
			if wheel:GetAttribute("Radius") == driveR then
				driveZ[math.floor(wheel.CFrame.Position.Z * 100 + 0.5)] = wheel.CFrame.Position.Z
			end
		end
		local z0, z1 = math.huge, -math.huge
		for _, z in driveZ do
			z0, z1 = math.min(z0, z), math.max(z1, z)
		end
		T.truthy(z1 - z0 > 2, "two drive axles")
		-- per side a level coupling rod below the hubs across both drive wheels and
		-- a main rod from the steam cylinder down to the front crank
		local level, main = 0, 0
		for _, rod in find(loco, "BasePart", "Rod") do
			local p, look = rod.CFrame.Position, rod.CFrame.LookVector
			local half = rod.Size.Z / 2
			if math.abs(look.Y) < 1e-3 then
				level += 1
				T.truthy(p.Y < driveR and p.Y > driveR - 0.6, `coupling rod at crank-pin height ({p.Y})`)
				T.truthy(p.Z - half <= z0 and p.Z + half >= z1, "coupling rod spans both drive axles")
			else
				main += 1
				local front = p - look * half
				local back = p + look * half
				local cylinderTop, rear = math.min(front.Y, back.Y), math.max(front.Z, back.Z)
				T.truthy(math.max(front.Y, back.Y) > driveR, "main rod starts up at the cylinder")
				T.truthy(math.abs(rear - z0) < 0.3 and cylinderTop < driveR, "main rod ends at the front crank")
			end
		end
		T.eq(level, 2, "one coupling rod per side")
		T.eq(main, 2, "one main rod per side")
		-- the cab side shows a framed window at the front and a dark entrance at the back
		local cab = find(loco, "BasePart", "Cab")[1]
		local doors = find(loco, "BasePart", "CabDoor")
		T.eq(#doors, 2, "a cab entrance per side")
		for _, door in doors do
			T.truthy(door.CFrame.Position.Z > cab.CFrame.Position.Z, "the entrance is in the back half of the cab")
			T.truthy(math.abs(door.CFrame.Position.X) + door.Size.X / 2 > cab.Size.X / 2 + 0.06, "the entrance stands out of the cab side")
		end
		-- chimney: a lighter flared crown with the sooty stack standing just out of it
		local stack = find(loco, "BasePart", "Chimney")[1]
		local crown = find(loco, "BasePart", "ChimneyCap")[1]
		local stackTop = stack.CFrame.Position.Y + stack.Size.X / 2
		local crownTop = crown.CFrame.Position.Y + crown.Size.X / 2
		T.truthy(stackTop - crownTop >= 0.05 and stackTop - crownTop <= 0.1, "the stack top is the opening in the crown")
		T.truthy(crown.Size.Y > stack.Size.Y + 0.4, "the crown flares out")
		local function value(c: any): number
			return c.R + c.G + c.B
		end
		T.truthy(value(crown.Color) > value(stack.Color) + 0.3, "crown lighter than the sooty opening")
		-- the cow-catcher stays under the front buffer beam and inside the buffers
		local beamZ = math.huge
		for _, beam in find(loco, "BasePart", "BufferBeam") do
			beamZ = math.min(beamZ, beam.CFrame.Position.Z + beam.Size.Z / 2)
		end
		for _, plow in find(loco, "BasePart", "CowCatcher") do
			local half = plow.Size / 2
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = (plow.CFrame * roblox.CFrame.new(half.X * sx, 0, half.Z * sz)).Position
					T.truthy(c.Z <= beamZ + 1e-3, `cow-catcher ends under the beam (z {c.Z})`)
					T.truthy(math.abs(c.X) <= 2.6 + 1e-3, `cow-catcher inside the buffers (x {c.X})`)
				end
			end
		end
	end)

	T.test("Train: client visuals (anchored, no collide/touch/query, neon only for the lamp)", function()
		local list = vehicles()
		table.insert(list, { "track", TrainBuilder.track(60) })
		for _, entry in list do
			for _, p in parts(entry[2]) do
				local label = entry[1] .. " " .. p.Name
				T.truthy(p.Anchored, label .. " anchored")
				T.falsy(p.CanCollide, label .. " CanCollide")
				T.falsy(p.CanTouch, label .. " CanTouch")
				T.falsy(p.CanQuery, label .. " CanQuery")
				if p.Material == roblox.Enum.Material.Neon then
					T.eq(p.Name, "LampGlass", label .. " is the only Neon part")
				end
				-- small parts never cast shadows
				if p.Size.X * p.Size.Y * p.Size.Z < 1.5 then
					T.falsy(p.CastShadow, label .. " small part casts no shadow")
				end
			end
		end
	end)

	T.test("Train: deterministic (same input -> same parts)", function()
		local function signature(model: any): string
			local out = {}
			for _, p in parts(model) do
				local cf = p.CFrame
				table.insert(
					out,
					string.format(
						"%s|%s|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%s",
						p.Name,
						p.ClassName,
						cf.Position.X,
						cf.Position.Y,
						cf.Position.Z,
						cf.LookVector.X,
						cf.LookVector.Y,
						cf.LookVector.Z,
						p.Size.X,
						p.Size.Y,
						p.Size.Z,
						hex(p.Color)
					)
				)
			end
			return table.concat(out, ";")
		end
		T.eq(signature(TrainBuilder.locomotive(COLORS[5])), signature(TrainBuilder.locomotive(COLORS[5])), "locomotive")
		T.eq(signature(TrainBuilder.wagon(COLORS[5], ORES)), signature(TrainBuilder.wagon(COLORS[5], ORES)), "wagon")
		T.eq(signature(TrainBuilder.track(66)), signature(TrainBuilder.track(66)), "track")
		T.truthy(signature(TrainBuilder.wagon(COLORS[5], ORES)) ~= signature(TrainBuilder.wagon(COLORS[5])), "load changes the wagon")
	end)

	T.test("Train: track rails on the gauge, sleepers every ~6 studs", function()
		for _, length in { 6, 30, 48, 120 } do
			local track = TrainBuilder.track(length)
			local rails = find(track, "BasePart", "Rail")
			T.eq(#rails, 2, "two rails")
			for _, rail in rails do
				T.near(math.abs(rail.CFrame.Position.X), TrainBuilder.Gauge / 2, 1e-4, "rail on the gauge")
				T.near(rail.Size.Z, length, 1e-4, "rail runs the whole length")
			end
			local sleepers = find(track, "BasePart", "Sleeper")
			table.sort(sleepers, function(a, b)
				return a.CFrame.Position.Z < b.CFrame.Position.Z
			end)
			T.eq(#sleepers, math.max(1, math.floor(length / 6 + 0.5)), `sleeper count for {length}`)
			for i = 2, #sleepers do
				local gap = sleepers[i].CFrame.Position.Z - sleepers[i - 1].CFrame.Position.Z
				T.truthy(gap >= 5 and gap <= 7, `sleeper spacing {gap}`)
			end
			-- pieces join seamlessly: half a spacing at each end
			if #sleepers >= 2 then
				local spacing = sleepers[2].CFrame.Position.Z - sleepers[1].CFrame.Position.Z
				T.near(sleepers[1].CFrame.Position.Z + length / 2, spacing / 2, 1e-4, "half spacing at the start")
			end
		end
		-- Kenney's tight tie rhythm: deep sleepers; cool lavender rails
		for _, sleeper in find(TrainBuilder.track(48), "BasePart", "Sleeper") do
			T.truthy(sleeper.Size.Z >= 2.3, `deep sleepers ({sleeper.Size.Z})`)
		end
		local rail = find(TrainBuilder.track(48), "BasePart", "Rail")[1].Color
		T.truthy(rail.B > rail.G and rail.G > rail.R, "rails are a cool lavender blue")
		-- wheels sit on the rails
		local loco = TrainBuilder.locomotive(COLORS[1])
		local found = false
		for _, wheel in find(loco, "BasePart", "Wheel") do
			local half = wheel.Size.X / 2
			if half >= TrainBuilder.Gauge / 2 then
				found = true
			end
		end
		T.truthy(found, "wheel treads reach the rails")
	end)
end
