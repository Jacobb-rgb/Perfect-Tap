--[[
	The ore trains' railway (src/server/World/Railway.luau): the hooks of the
	shared contract (TrainService finds the hoppers and prompts, the client
	animates trains along TrainConfig's lines), the coastal lines passing
	every plot's train stop, nothing of the railway in the base yards, roads,
	island rim, NEXT AREA boardwalk or town sites, the trains' clearance, the
	part budget and determinism.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local TrainConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TrainConfig")
	local TrainBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.TrainBuilder")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Railway = Loader.requirePath("ServerScriptService.Server.World.Railway")
	local Town = Loader.requirePath("ServerScriptService.Server.World.Lobby.Flora.Town")

	local game = roblox.Instance.new("DataModel")
	local map = WorldBuilder.build(game:GetService("Workspace"))
	local railway = map:FindFirstChild("Railway")

	-- World axis-aligned bounds of a (possibly rotated) part.
	local function bounds(part: any): (any, any)
		local cf, size = part.CFrame, part.Size
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local h = Vector3.new(
			math.abs(r00) * size.X / 2 + math.abs(r01) * size.Y / 2 + math.abs(r02) * size.Z / 2,
			math.abs(r10) * size.X / 2 + math.abs(r11) * size.Y / 2 + math.abs(r12) * size.Z / 2,
			math.abs(r20) * size.X / 2 + math.abs(r21) * size.Y / 2 + math.abs(r22) * size.Z / 2
		)
		return cf.Position - h, cf.Position + h
	end

	local function overlaps(aMin: any, aMax: any, bMin: any, bMax: any, eps: number): boolean
		return aMin.X < bMax.X - eps
			and aMax.X > bMin.X + eps
			and aMin.Y < bMax.Y - eps
			and aMax.Y > bMin.Y + eps
			and aMin.Z < bMax.Z - eps
			and aMax.Z > bMin.Z + eps
	end

	local function partsOf(root: any): { any }
		local list = {}
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
			end
		end
		return list
	end

	local function worldPoint(attachment: any): any
		return (attachment.Parent.CFrame * attachment.CFrame).Position
	end

	local function near(a: any, b: any, eps: number): boolean
		return (a - b).Magnitude <= eps
	end

	local function hasText(model: any, text: string): boolean
		for _, d in model:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == text then
				return true
			end
		end
		return false
	end

	local function lightsIn(model: any): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("PointLight") or d:IsA("SpotLight") then
				n += 1
			end
		end
		return n
	end

	local rail = partsOf(railway)

	T.test("railway: Map.Railway holds the lines, the station, four portals and the lifts", function()
		T.truthy(railway, "Map.Railway exists")
		for _, name in { "QuarryLine", "CoastWest", "CoastEast", "MineStation", "Portals" } do
			T.truthy(railway:FindFirstChild(name), "Railway." .. name)
		end
		for _, name in { "West", "East", "SouthWest", "SouthEast" } do
			local portal = railway.Portals:FindFirstChild(name)
			T.truthy(portal and portal:IsA("Model"), "portal " .. name)
			T.truthy(portal:FindFirstChild("Mouth"), name .. " has a dark mouth")
		end
		for _, lift in TrainConfig.Lifts do
			T.truthy(railway:FindFirstChild(lift.Id), "lift " .. lift.Id)
		end
		for _, d in map.Plots:GetDescendants() do
			T.falsy(d:GetAttribute("RailwayPlaceholder"), d:GetFullName() .. " (placeholder track) is gone")
		end
	end)

	T.test("railway: Mine Station hooks match the contract", function()
		local cfg = TrainConfig.Station
		local stations = {}
		for _, d in map:GetDescendants() do
			if d:HasTag("TrainStation") then
				table.insert(stations, d)
			end
		end
		T.eq(#stations, 1, "one TrainStation")
		local station = railway:FindFirstChild("MineStation")
		T.eq(stations[1], station, "the tagged station is Railway.MineStation")
		T.truthy(station:IsA("Model"), "MineStation is a Model")
		local intake = station:FindFirstChild("Intake")
		T.truthy(intake and intake:IsA("BasePart"), "Intake is a direct child part")
		T.truthy(intake:HasTag("TrainHopper"), "Intake tagged TrainHopper")
		T.eq(intake.Transparency, 1, "Intake invisible")
		T.falsy(intake.CanCollide, "Intake CanCollide")
		T.falsy(intake.CanTouch, "Intake CanTouch")
		T.falsy(intake.CanQuery, "Intake CanQuery")
		T.truthy(intake.Anchored, "Intake anchored")
		T.truthy(near(intake.Size, cfg.HopperSize, 1e-4), "Intake size = HopperSize")
		T.truthy(
			near(intake.CFrame.Position, cfg.Hopper + Vector3.new(0, cfg.HopperSize.Y / 2, 0), 1e-4),
			"Intake at Hopper + half its height"
		)
		T.eq(intake:FindFirstAncestorWhichIsA("Model"), station, "TrainService finds the station from the Intake")
		local prompt = station:FindFirstChild("PromptPoint", true)
		T.truthy(prompt and prompt:IsA("Attachment"), "PromptPoint attachment")
		T.truthy(near(worldPoint(prompt), cfg.PromptPoint, 1e-3), "PromptPoint at Station.PromptPoint")
		local trainPoint = station:FindFirstChild("TrainPoint", true)
		T.truthy(trainPoint and trainPoint:IsA("Attachment"), "TrainPoint attachment")
		T.truthy(near(worldPoint(trainPoint), TrainConfig.QuarryStop, 1e-3), "TrainPoint at QuarryStop")
		T.truthy(hasText(station, "MINE STATION"), "MINE STATION sign")
		T.lt(lightsIn(station), 2, "at most one PointLight at the station")
	end)

	T.test("railway: Mine Lift hooks match the contract", function()
		local tagged = {}
		local hoppers = 0
		for _, d in map:GetDescendants() do
			if d:HasTag("MineLift") then
				table.insert(tagged, d)
			end
			if d:HasTag("TrainHopper") then
				hoppers += 1
				T.truthy(d:IsDescendantOf(railway), d:GetFullName() .. " (TrainHopper) is under Map.Railway")
			end
		end
		T.eq(#tagged, #TrainConfig.Lifts, "one MineLift per TrainConfig lift")
		T.eq(hoppers, 1 + #TrainConfig.Lifts, "station + lift hoppers")
		for _, cfg in TrainConfig.Lifts do
			local lift = railway:FindFirstChild(cfg.Id)
			T.truthy(lift:IsA("Model") and lift:HasTag("MineLift"), cfg.Id .. " is a MineLift model")
			T.eq(lift:GetAttribute("LiftId"), cfg.Id, cfg.Id .. " LiftId")
			local intake = lift:FindFirstChild("Intake")
			T.truthy(intake and intake:IsA("BasePart"), cfg.Id .. " Intake part")
			T.truthy(intake:HasTag("TrainHopper"), cfg.Id .. " Intake tagged TrainHopper")
			T.eq(intake:GetAttribute("LiftId"), cfg.Id, cfg.Id .. " Intake LiftId")
			T.eq(intake.Transparency, 1, cfg.Id .. " Intake invisible")
			T.falsy(intake.CanCollide or intake.CanTouch or intake.CanQuery, cfg.Id .. " Intake collides/touches/queries")
			T.truthy(near(intake.Size, cfg.Size, 1e-4), cfg.Id .. " Intake size")
			T.truthy(near(intake.CFrame.Position, cfg.Position + Vector3.new(0, cfg.Size.Y / 2, 0), 1e-4), cfg.Id .. " Intake position")
			T.eq(intake:FindFirstAncestorWhichIsA("Model"), lift, cfg.Id .. " TrainService finds the lift from the Intake")
			local prompt = lift:FindFirstChild("PromptPoint", true)
			T.truthy(prompt and prompt:IsA("Attachment"), cfg.Id .. " PromptPoint")
			local p = worldPoint(prompt)
			local flat = Vector3.new(p.X - cfg.Position.X, 0, p.Z - cfg.Position.Z).Magnitude
			T.truthy(flat > cfg.Size.X / 2 and flat < 10, cfg.Id .. " PromptPoint in front of the hopper")
			T.truthy(hasText(lift, "LIFT"), cfg.Id .. " LIFT sign")
			T.lt(lightsIn(lift), 2, cfg.Id .. " at most one PointLight")
			local cable = lift:FindFirstChild("Cable", true)
			local cave = WorldLayout.Caves[cfg.Id]
			local _, top = bounds(cable)
			T.truthy(cave and top.Y >= cave.Max.Y, cfg.Id .. " cable reaches the ceiling")
		end
	end)

	T.test("railway: items can drop into every intake", function()
		local intakes = {}
		for _, d in railway:GetDescendants() do
			if d:HasTag("TrainHopper") then
				table.insert(intakes, d)
			end
		end
		for _, intake in intakes do
			local lo, hi = bounds(intake)
			-- the opening and the tub under it: nothing solid inside (the tub
			-- walls stand on the box edges)
			local colMin = Vector3.new(lo.X + 0.3, hi.Y - 1.2, lo.Z + 0.3)
			local colMax = Vector3.new(hi.X - 0.3, hi.Y + 6, hi.Z - 0.3)
			for _, part in rail do
				if part.CanCollide and part ~= intake then
					local a, b = bounds(part)
					T.falsy(overlaps(a, b, colMin, colMax, 0.01), part:GetFullName() .. " blocks " .. intake:GetFullName())
				end
			end
		end
	end)

	-- Rail parts of a line that cover the point's position along the line.
	local function railsAt(line: any, at: any): { any }
		local list = {}
		for _, part in partsOf(line) do
			if part.Name == "Rail" then
				local lo, hi = bounds(part)
				if at.Z >= lo.Z - 1e-3 and at.Z <= hi.Z + 1e-3 and at.X >= lo.X - 3 and at.X <= hi.X + 3 then
					table.insert(list, part)
				end
			end
		end
		return list
	end

	T.test("railway: the coastal lines pass behind every plot's train stop", function()
		for _, plot in WorldLayout.Plots do
			local stop = TrainConfig.stopFor(plot)
			local points = TrainConfig.lineFor(plot)
			local name = if points == TrainConfig.CoastWest then "CoastWest" else "CoastEast"
			-- the configured polyline itself runs through the stop
			local a, b = points[1], points[#points]
			local t = math.clamp((stop - a):Dot(b - a) / (b - a):Dot(b - a), 0, 1)
			T.truthy((a + (b - a) * t - stop).Magnitude <= 1, `plot {plot.Id}: the {name} polyline passes its stop`)
			-- the built rails: the sea-side rail runs past the stop at the gauge, its
			-- top where the trains' wheels are (the platform side gives way to the stop)
			local outward = if stop.X < 0 then -1 else 1
			local found = false
			for _, part in railsAt(railway[name], stop) do
				local center = part.CFrame.Position.X - outward * TrainBuilder.Gauge / 2
				local _, hi = bounds(part)
				if math.abs(center - stop.X) <= 1 and math.abs(hi.Y - (stop.Y + TrainBuilder.RailTop)) < 0.01 then
					found = true
				end
			end
			T.truthy(found, `plot {plot.Id}: a {name} rail runs past the stop within 1 stud`)
			local sleeper = false
			for _, part in partsOf(railway[name]) do
				if part.Name == "Sleeper" and math.abs(part.CFrame.Position.Z - stop.Z) <= TrainBuilder.SleeperSpacing then
					local lo, hi = bounds(part)
					local farRail = stop.X + outward * TrainBuilder.Gauge / 2
					sleeper = sleeper or (lo.X < farRail and hi.X > farRail)
				end
			end
			T.truthy(sleeper, `plot {plot.Id}: sleepers under the rail at the stop`)
		end
	end)

	T.test("railway: the rails run unbroken between the portal mouths and the buffers", function()
		-- (on the coast the platform-side rail gives way to the stops, so the sea-side one is checked)
		local checks = {
			{ Line = "QuarryLine", Axis = "X", Offsets = { -1, 1 } },
			{ Line = "CoastWest", Axis = "Z", Offsets = { -1 } },
			{ Line = "CoastEast", Axis = "Z", Offsets = { 1 } },
		}
		local visible = Railway.visibleLines()
		for _, check in checks do
			local points = visible[check.Line]
			local a, b = points[1], points[#points]
			local from = math.min(a[check.Axis], b[check.Axis])
			local to = math.max(a[check.Axis], b[check.Axis])
			for _, offset in check.Offsets do
				local spans = {}
				for _, part in partsOf(railway[check.Line]) do
					if part.Name == "Rail" then
						local lateral = if check.Axis == "X" then part.CFrame.Position.Z - a.Z else part.CFrame.Position.X - a.X
						if math.abs(lateral - offset * TrainBuilder.Gauge / 2) < 0.05 then
							local lo, hi = bounds(part)
							table.insert(spans, { lo[check.Axis], hi[check.Axis] })
							T.truthy(
								hi[check.Axis] - lo[check.Axis] <= Railway.RunLength + 1e-3,
								part:GetFullName() .. " longer than a run"
							)
						end
					end
				end
				table.sort(spans, function(x, y)
					return x[1] < y[1]
				end)
				T.truthy(#spans > 0 and spans[1][1] <= from + 1e-3, `{check.Line} rail {offset} starts at the mouth`)
				local reach = spans[1] and spans[1][2] or from
				for i = 2, #spans do
					T.truthy(spans[i][1] <= reach + 1e-3, `{check.Line} rail {offset} has a gap at {reach}`)
					reach = math.max(reach, spans[i][2])
				end
				T.truthy(reach >= to - 1e-3, `{check.Line} rail {offset} reaches the end`)
			end
		end
	end)

	T.test("railway: nothing intrudes into the yards, roads, rim, boardwalk or town", function()
		-- railway parts near the surface (the caves and the quarry lie below)
		local surface = {}
		for _, part in rail do
			local lo, hi = bounds(part)
			if hi.Y > -2 then
				table.insert(surface, { part = part, lo = lo, hi = hi })
			end
		end
		T.truthy(#surface > 0, "railway parts on the surface")
		local function against(parts: { any }, what: string)
			for _, other in parts do
				local a, b = bounds(other)
				for _, s in surface do
					if overlaps(s.lo, s.hi, a, b, 0.01) then
						T.truthy(false, `{s.part:GetFullName()} intrudes into {what} ({other:GetFullName()})`)
						return
					end
				end
			end
		end
		against(partsOf(map.Plots), "a base")
		against(partsOf(map.Land:FindFirstChild("Cliffs")), "the island rim")
		local flora = map.Emberfall:FindFirstChild("Lobby") and map.Emberfall.Lobby:FindFirstChild("Flora")
		local boardwalk = {}
		for _, d in (if flora then flora:GetDescendants() else {}) do
			if d:IsA("Model") and (d.Name == "NextArea" or d.Name == "NextAreaBoardwalk") then
				for _, p in partsOf(d) do
					table.insert(boardwalk, p)
				end
			end
		end
		against(boardwalk, "the NEXT AREA boardwalk")
		for _, s in surface do
			local name = s.part:GetFullName()
			-- the boardwalk strip and the rim's inner face
			T.falsy(s.hi.X > 140 and s.lo.Z < -112 and s.hi.Z > -118, name .. " is on the NEXT AREA boardwalk strip")
			if s.hi.Z > LobbyLayout.Area.Min.Z then
				T.truthy(math.max(math.abs(s.lo.X), math.abs(s.hi.X)) <= 171.7, name .. " reaches into the island rim")
				-- the town keeps west/east of Town.RailMinX, the railway outside it
				T.truthy(math.min(math.abs(s.lo.X), math.abs(s.hi.X)) >= Town.RailMinX, name .. " is in the town's ground")
			end
			for _, site in Town.Sites do
				T.falsy(
					s.lo.X < site.Max.X and s.hi.X > site.Min.X and s.lo.Z < site.Max.Y and s.hi.Z > site.Min.Y,
					`{name} is on the town site {site.Id}`
				)
			end
			if s.lo.Y < 1 then
				for _, road in WorldLayout.Roads do
					local w = road.Width / 2
					local rMin = Vector3.new(math.min(road.From.X, road.To.X) - w, 0, math.min(road.From.Z, road.To.Z) - w)
					local rMax = Vector3.new(math.max(road.From.X, road.To.X) + w, 0, math.max(road.From.Z, road.To.Z) + w)
					T.falsy(s.lo.X < rMax.X and s.hi.X > rMin.X and s.lo.Z < rMax.Z and s.hi.Z > rMin.Z, name .. " is on a road")
				end
				for _, path in LobbyLayout.Paths do
					local mid = (Vector3.new(s.lo.X, 0, s.lo.Z) + Vector3.new(s.hi.X, 0, s.hi.Z)) / 2
					local radius = (Vector3.new(s.hi.X, 0, s.hi.Z) - Vector3.new(s.lo.X, 0, s.lo.Z)).Magnitude / 2
					T.truthy(LobbyLayout.distanceToStrip(path.From, path.To, path.Width, mid) >= radius, `{name} is on the path {path.Id}`)
				end
			end
		end
	end)

	T.test("railway: the trains' clearance stays free between the portal mouths", function()
		local c = Railway.Clearance
		for lineName, points in Railway.visibleLines() do
			for i = 1, #points - 1 do
				local a, b = points[i], points[i + 1]
				-- the lines are axis-aligned: one box per segment
				local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
				local lo = Vector3.new(
					if alongX then math.min(a.X, b.X) else a.X - c.HalfWidth,
					a.Y + c.Bottom,
					if alongX then a.Z - c.HalfWidth else math.min(a.Z, b.Z)
				)
				local hi = Vector3.new(
					if alongX then math.max(a.X, b.X) else a.X + c.HalfWidth,
					a.Y + c.Top,
					if alongX then a.Z + c.HalfWidth else math.max(a.Z, b.Z)
				)
				for _, part in rail do
					if part.Name ~= "Rail" and part.Name ~= "Sleeper" and part.Name ~= "Mouth" then
						local pLo, pHi = bounds(part)
						T.falsy(overlaps(pLo, pHi, lo, hi, 0.01), `{part:GetFullName()} stands in the {lineName} trains' way`)
					end
				end
			end
		end
		-- no other package's piece (trees, rocks, backdrop) stands on the visible
		-- lines; flat ground patches lie under the sleepers (the yards' train
		-- stops are built around the line by PlotBuilder)
		for lineName, points in Railway.visibleLines() do
			for i = 1, #points - 1 do
				local a, b = points[i], points[i + 1]
				local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
				local w = 4.2
				local lo =
					Vector3.new(if alongX then math.min(a.X, b.X) else a.X - w, a.Y + 0.3, if alongX then a.Z - w else math.min(a.Z, b.Z))
				local hi =
					Vector3.new(if alongX then math.max(a.X, b.X) else a.X + w, a.Y + c.Top, if alongX then a.Z + w else math.max(a.Z, b.Z))
				for _, d in map:GetDescendants() do
					if d:IsA("BasePart") and d.Transparency < 1 and not d:IsDescendantOf(railway) and not d:IsDescendantOf(map.Plots) then
						local pLo, pHi = bounds(d)
						T.falsy(overlaps(pLo, pHi, lo, hi, 0.01), `{d:GetFullName()} stands on the {lineName}`)
					end
				end
			end
		end
		-- the trains' real size fits the clearance
		local loco = TrainBuilder.locomotive(roblox.Color3.new(1, 0, 0))
		local wagon = TrainBuilder.wagon(roblox.Color3.new(1, 0, 0), { roblox.Color3.new(0, 0, 0) })
		for _, model in { loco, wagon } do
			for _, part in partsOf(model) do
				local lo, hi = bounds(part)
				T.truthy(math.max(math.abs(lo.X), math.abs(hi.X)) <= c.HalfWidth, part.Name .. " fits the clearance width")
				T.truthy(hi.Y + TrainBuilder.RailTop <= c.Top, part.Name .. " fits under the clearance top")
			end
		end
	end)

	T.test("railway: part budget, lights, shadows, collisions and streaming", function()
		T.truthy(#rail <= Railway.MaxParts, `railway parts {#rail} <= {Railway.MaxParts}`)
		local lights = 0
		for _, d in railway:GetDescendants() do
			if d:IsA("PointLight") or d:IsA("SpotLight") then
				lights += 1
				T.falsy(LobbyLayout.inArea(d.Parent.CFrame.Position), d:GetFullName() .. " is a light in the lobby")
			end
		end
		T.truthy(lights <= 1 + #TrainConfig.Lifts, "one light at the station and one per lift")
		for _, part in rail do
			local name = part:GetFullName()
			T.truthy(part.Anchored, name .. " anchored")
			local s = part.Size
			if math.max(s.X, s.Y, s.Z) < 2.5 then
				T.falsy(part.CastShadow, name .. " is small and casts a shadow")
			end
			if part.Name == "Rail" or part.Name == "Sleeper" then
				T.falsy(part.CanCollide or part.CanTouch or part.CanQuery or part.CastShadow, name .. " track part is not a plain ghost")
			end
		end
		for _, portal in railway.Portals:GetChildren() do
			T.eq(portal.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, portal.Name .. " streams atomically")
			T.eq(portal.LevelOfDetail, roblox.Enum.ModelLevelOfDetail.StreamingMesh, portal.Name .. " keeps a far mesh")
		end
		T.eq(railway.MineStation.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, "station streams atomically")
		for _, cfg in TrainConfig.Lifts do
			T.eq(railway[cfg.Id].ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, cfg.Id .. " streams atomically")
		end
	end)

	T.test("railway: the build is deterministic and replaces an old railway", function()
		-- every instance with its path (relative to the railway), class,
		-- placement, size, color and tags, in build order
		local function fingerprint(root: any): { string }
			local prefix = #root:GetFullName() + 2
			local list = {}
			for _, d in root:GetDescendants() do
				local line = d:GetFullName():sub(prefix) .. "|" .. d.ClassName .. "|" .. table.concat(d:GetTags(), ",")
				if d:IsA("BasePart") then
					line ..= "|" .. tostring(d.CFrame) .. "|" .. tostring(d.Size) .. "|" .. tostring(d.Color)
				elseif d:IsA("Attachment") then
					line ..= "|" .. tostring(d.CFrame)
				end
				table.insert(list, line)
			end
			return list
		end
		local a = roblox.Instance.new("Model")
		local b = roblox.Instance.new("Model")
		Railway.build(a)
		Railway.build(b)
		for _, other in { fingerprint(b.Railway), fingerprint(railway) } do
			local fa = fingerprint(a.Railway)
			T.eq(#other, #fa, "same instance count")
			for i = 1, #fa do
				if fa[i] ~= other[i] then
					T.eq(other[i], fa[i], "instance " .. i)
				end
			end
		end
		Railway.build(a)
		local railways = 0
		for _, child in a:GetChildren() do
			if child.Name == "Railway" then
				railways += 1
			end
		end
		T.eq(railways, 1, "a second build replaces the first")
	end)
end
