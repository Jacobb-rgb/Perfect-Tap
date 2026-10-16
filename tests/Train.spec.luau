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
		T.eq(#find(hopper, "BasePart", "Ore"), 4, "4 ore lumps in the hopper")
		T.eq(#find(TrainBuilder.wagon(COLORS[4]), "BasePart", "Ore"), 0, "empty wagon has no ore")
	end)

	T.test("Train: colors (body, trim, load colors cycle)", function()
		local red, white = COLORS[1], COLORS[8]
		local loco = TrainBuilder.locomotive(red)
		T.eq(hex(find(loco, "BasePart", "Cab")[1].Color), hex(red), "cab in the body color")
		T.eq(hex(find(loco, "BasePart", "Boiler")[1].Color), hex(red), "boiler in the body color")
		local trimmed = TrainBuilder.locomotive(red, white)
		T.eq(hex(find(trimmed, "BasePart", "CabBand")[1].Color), hex(white), "trim color")
		T.truthy(hex(find(loco, "BasePart", "CabBand")[1].Color) ~= hex(white), "default brass trim")
		local wagon = TrainBuilder.wagon(red, ORES)
		T.eq(hex(find(wagon, "BasePart", "Body")[1].Color), hex(red), "hopper in the body color")
		local seen = {}
		for _, ore in find(wagon, "BasePart", "Ore") do
			seen[hex(ore.Color)] = true
		end
		for _, c in ORES do
			T.truthy(seen[hex(c)], "every load color shows")
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
