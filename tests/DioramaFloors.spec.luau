-- The mine floors from the owner's dioramas (Mine/Diorama, Meshy 2026-11-13): with the upload every floor
-- is its diorama and keeps MineKit's floor contract (spawns, markers, budgets), players stand on its
-- ground boxes, and the lifts move to the diorama's spots. Stand-in templates play the upload.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local MineKit = Loader.requirePath("ServerScriptService.Server.World.Mine.MineKit")
	local Diorama = Loader.requirePath("ServerScriptService.Server.World.Mine.Diorama")
	local DioramaData = Loader.requirePath("ServerScriptService.Server.World.Mine.DioramaData")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local MeshCatalog = Loader.requirePath("ReplicatedStorage.Shared.Config.MeshCatalog")
	local MineAmbience = Loader.requirePath("ReplicatedStorage.Shared.Config.MineAmbience")
	local MODULES = { "Floor1Quarry", "Floor2Ember", "Floor3Lagoon", "Floor4Palace", "Floor5Storm", "Floor6Core" }

	local function count(model, className)
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	T.test("diorama floors: no upload, no diorama (the part floors)", function()
		Fakes.unmount(Loader)
		for index = 1, 6 do
			T.falsy(MineFloors.usesDiorama(index), "floor " .. index)
			T.falsy(Diorama.has(index), "floor " .. index)
		end
	end)

	T.test("diorama floors: the squashed spots are the processing job's", function()
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		local jobs = serde.decode("json", fs.readFile("tools/meshy/jobs_2026-11-14.json"))
		for _, job in jobs.jobs do
			local id = string.match(job.name, "^Floor_(%a+)HD$")
			local floorId = if id == "QuarryB" then "Quarry" else id
			local flat = Diorama.Floors[floorId] and Diorama.Floors[floorId].Flatten
			if job.flatten then
				T.truthy(flat and #flat == #job.flatten, floorId .. " knows every squashed spot")
				for k, b in job.flatten do
					local f = flat[k]
					local same = true
					for n = 1, 6 do
						same = same and math.abs(f[n] - b[n]) < 1e-6
					end
					T.truthy(same, floorId .. " squashed box " .. k .. " as the job's")
				end
			else
				T.eq(flat, nil, floorId .. " nothing squashed")
			end
		end
	end)

	T.test("diorama floors: a flatten box cuts the walk boxes down to its floor, the rest stays", function()
		-- one box 0..10 x 0..10 at 5 high, a flatten box over its middle x 2..4 down to 1
		local out = Diorama.flattenBoxes({ 0, 0, 10, 10, 5 }, { { 2, 1, -1, 4, 9, 11 } })
		local area, cut = 0, false
		for i = 1, #out, 5 do
			local x0, z0, x1, z1, top = out[i], out[i + 1], out[i + 2], out[i + 3], out[i + 4]
			area += (x1 - x0) * (z1 - z0)
			if x0 >= 2 and x1 <= 4 then
				T.eq(top, 1, "cut down inside")
				cut = true
			else
				T.eq(top, 5, "as it was outside")
			end
		end
		T.truthy(cut, "the overlap is there")
		T.near(area, 100, 1e-6, "the same ground, no gaps, no overlaps")
		-- lower ground under a flatten box keeps its own height
		local low = Diorama.flattenBoxes({ 0, 0, 10, 10, 0.5 }, { { -1, 1, -1, 11, 9, 11 } })
		T.eq(low[5], 0.5, "ground under the floor stays")
	end)

	T.test("diorama floors: a walk box ending just short of a mesh-faced wall runs on to its body", function()
		-- an E wall's floor-level piece z -10..10 with its body's front at x 50, a lintel piece over an
		-- opening z 10..20 (no ledge under a lintel), and walk boxes: 2 short (a ledge), 7 short (none),
		-- one reaching past the front (none), one beside the piece (none), one across its end (clipped)
		local bodies = {
			{ Side = "E", From = -10, To = 10, Front = 50, Y0 = Diorama.WallBottom },
			{ Side = "E", From = 10, To = 20, Front = 50, Y0 = 16 },
		}
		local walk = {
			40,
			-4,
			48,
			4,
			20, -- 2 short: x 48..50 at 20
			30,
			-4,
			43,
			4,
			9, -- 7 short: nothing
			44,
			-9,
			50.5,
			-5,
			3, -- reaches the body: nothing
			40,
			12,
			48,
			18,
			6, -- beside the opening's lintel: nothing
			40,
			6,
			48.5,
			14,
			12, -- across the piece's end: z 6..10 only
		}
		local out = Diorama.ledges(walk, bodies)
		T.eq(#out, 10, "two ledges")
		T.eq(out[1], 48)
		T.eq(out[2], -4)
		T.eq(out[3], 50)
		T.eq(out[4], 4)
		T.eq(out[5], 20)
		T.eq(out[6], 48.5)
		T.eq(out[7], 6)
		T.eq(out[8], 50)
		T.eq(out[9], 10)
		T.eq(out[10], 12)
		-- a W wall and an N wall mirror it
		local w = Diorama.ledges({ -48, -4, -40, 4, 20 }, { { Side = "W", From = -10, To = 10, Front = -50, Y0 = Diorama.WallBottom } })
		T.eq(w[1], -50, "W: from the body")
		T.eq(w[3], -48, "W: to the box's edge")
		local n = Diorama.ledges({ -4, -48, 4, -40, 20 }, { { Side = "N", From = -10, To = 10, Front = -50, Y0 = Diorama.WallBottom } })
		T.eq(n[2], -50, "N: from the body")
		T.eq(n[4], -48, "N: to the box's edge")
		T.eq(n[1], -4, "N: along x")
	end)

	T.test("diorama floors: every floor has data and tiles in the catalog", function()
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		for _, floor in MineFloors.List do
			local data = DioramaData[floor.Id]
			T.truthy(data, floor.Id .. " data")
			T.truthy(MeshCatalog.Floors[floor.Id] and #MeshCatalog.Floors[floor.Id] >= 8, floor.Id .. " tiles")
			-- the sharper set of the same diorama (2026-11-14), for the floor once it is uploaded
			local hd = MeshCatalog.FloorsHD[floor.Id]
			T.truthy(hd and #hd >= 8, floor.Id .. " sharper tiles")
			T.eq(#data.Boxes % 5, 0, floor.Id .. " boxes come in fives")
			T.eq(#data.Ramps % 7, 0, floor.Id .. " ramps come in sevens")
			T.le(#data.Ramps / 7, 40, floor.Id .. " at most 40 path ramps")
		end
	end)

	T.test("diorama floors: contract, spawns on the ground, markers and budgets", function()
		Fakes(Loader, true)
		-- (the stand-ins come off even when a check fails: the specs after this one build part looks)
		local ok, err = pcall(function()
			for index, name in MODULES do
				local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine." .. name)
				T.truthy(Diorama.has(index), name .. " is its diorama")
				local folder = roblox.Instance.new("Folder")
				local origin = MineFloors.Placement[index]
				local model = Floor.build(folder, origin, { Cutaway = false })
				local label = name .. " (diorama)"
				T.eq(model.Name, "MineFloor" .. index, label .. " model name")
				T.eq(model:GetAttribute("Diorama"), true, label .. " built from the diorama")
				local tiles = model:FindFirstChild("Diorama")
				T.eq(#tiles:GetChildren(), #(MineFloors.floorTiles(index) :: { string }), label .. " every tile")
				for _, tile in tiles:GetChildren() do
					T.truthy(tile:IsA("MeshPart") and not tile.CanCollide and not tile.CanQuery, label .. " tiles are looks")
				end
				-- spawns: enough, some deep, each over a ground box near its height
				local ground = model:FindFirstChild("Ground"):GetChildren()
				local function groundUnder(p): number?
					local best: number? = nil
					for _, box in ground do
						local local_ = box.CFrame:PointToObjectSpace(p)
						local h = box.Size / 2
						if math.abs(local_.X) <= h.X + 0.01 and math.abs(local_.Z) <= h.Z + 0.01 then
							local top = box.CFrame.Position.Y + h.Y
							if top <= p.Y + 1.5 and (best == nil or top > best) then
								best = top
							end
						end
					end
					return best
				end
				local spawns = model:FindFirstChild("RockSpawns"):GetChildren()
				local deep = 0
				for _, s in spawns do
					if s:GetAttribute("Deep") == true then
						deep += 1
					end
					local p = s.CFrame.Position
					local top = groundUnder(p)
					T.truthy(top ~= nil and p.Y - top < 1.5, label .. " spawn on the ground at " .. tostring(p))
				end
				T.le(18, #spawns, label .. " >= 18 rock spawns")
				T.le(6, deep, label .. " >= 6 deep spawns")
				for _, marker in { "GiantSpawn", "Entrance" } do
					local m = model:FindFirstChild(marker)
					T.truthy(m, label .. " " .. marker)
					local top = groundUnder(m.CFrame.Position)
					T.truthy(top ~= nil and m.CFrame.Position.Y - top < 1.5, label .. " " .. marker .. " on the ground")
				end
				local elevator = model:FindFirstChild("Elevator")
				T.truthy(elevator and elevator:HasTag("MineElevator"), label .. " elevator stop")
				T.eq(elevator:GetAttribute("Floor"), index, label .. " elevator floor")
				-- (owner 2026-11-14: "taller, always from the ground to the ceiling, lit and big")
				local tower = elevator:FindFirstChild("Tower")
				T.truthy(tower, label .. " the elevator's tower")
				local towerTop = tower.CFrame.Position.Y + tower.Size.Y / 2
				local wantTop = origin.Y
					+ math.min(
						MineFloors.CeilingHeight,
						if MineFloors.CeilingFloors[index] then math.huge else DioramaData[MineFloors.ByIndex[index].Id].Top
					)
				T.near(towerTop, wantTop, 0.05, label .. " the tower reaches the ceiling")
				T.le(8, tower.Size.X, label .. " a wide tower")
				local lamps = 0
				for _, d in elevator:GetDescendants() do
					if d:IsA("PointLight") then
						lamps += 1
					end
				end
				T.le(3, lamps, label .. " a lit elevator")
				local gate = model:FindFirstChild("BlasterGate", true)
				if MineFloors.ByIndex[index].MinBlaster <= 1 then
					T.eq(gate, nil, label .. " no gate where every blaster may go")
				else
					T.truthy(gate, label .. " blaster gate")
					T.eq(gate:GetAttribute("MinBlaster"), MineFloors.ByIndex[index].MinBlaster, label .. " gate level")
				end
				-- no ore lift (owner 2026-11-14: "take it out of every location, it really bothers me")
				T.eq(model:FindFirstChild("OreLiftSpot", true), nil, label .. " no ore lift spot")
				T.eq(model:FindFirstChild("LiftDeck", true), nil, label .. " no lift deck")
				for _, d in model:GetDescendants() do
					if d:HasTag("MineLift") then
						error(label .. " a Mine Lift " .. d:GetFullName())
					end
				end
				-- the path ramps (owner 2026-11-13: walk from the elevator without a jump at every edge):
				-- invisible solid wedges, one per DioramaData ramp, their high edge on the higher ground
				local data = DioramaData[MineFloors.ByIndex[index].Id]
				local ramps = 0
				for _, d in model.Ground:GetChildren() do
					if d.Name == "Ramp" then
						ramps += 1
						T.truthy(
							d:IsA("WedgePart") and d.CanCollide and d.Transparency == 1 and d.Anchored,
							label .. " a ramp is an invisible solid wedge"
						)
						local high =
							origin:PointToObjectSpace(d.CFrame:PointToWorldSpace(roblox.Vector3.new(0, d.Size.Y / 2, d.Size.Z / 2)))
						local low =
							origin:PointToObjectSpace(d.CFrame:PointToWorldSpace(roblox.Vector3.new(0, -d.Size.Y / 2, -d.Size.Z / 2)))
						T.truthy(high.Y > low.Y + 0.9, label .. " a ramp rises")
					end
				end
				-- (the sharper tiles squash what stood in the way: no walk box stands above a flatten
				-- box's floor inside it, and no path ramp leads up there)
				local flats = Diorama.Floors[MineFloors.ByIndex[index].Id].Flatten or {}
				local skipped = 0
				for i = 1, #data.Ramps, 7 do
					local x0, z0, x1, z1 = data.Ramps[i], data.Ramps[i + 1], data.Ramps[i + 2], data.Ramps[i + 3]
					for _, f in flats do
						if math.min(x1, f[4]) - math.max(x0, f[1]) > 0.05 and math.min(z1, f[6]) - math.max(z0, f[3]) > 0.05 then
							skipped += 1
							break
						end
					end
				end
				for _, d in model.Ground:GetChildren() do
					if d.Name == "Ground" then
						local p = origin:PointToObjectSpace(d.CFrame.Position)
						local h = d.Size / 2
						for _, f in flats do
							if
								p.X - h.X >= f[1] - 1e-6
								and p.X + h.X <= f[4] + 1e-6
								and p.Z - h.Z >= f[3] - 1e-6
								and p.Z + h.Z <= f[6] + 1e-6
							then
								T.le(p.Y + h.Y, f[2] + 0.01, label .. " nothing to bump into where a squashed thing stood")
							end
						end
					end
				end
				T.eq(ramps, #data.Ramps / 7 - skipped, label .. " every path ramp")
				-- the quarry's extras round the diorama; no rim part left in front of the side walls' slab
				if index == 1 then
					local function box(d)
						local mn, mx = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
						for _, sx in { -1, 1 } do
							for _, sy in { -1, 1 } do
								for _, sz in { -1, 1 } do
									local c = origin:PointToObjectSpace(d.CFrame:PointToWorldSpace(V3.new(sx, sy, sz) * d.Size / 2))
									mn, mx = mn:Min(c), mx:Max(c)
								end
							end
						end
						return mn, mx
					end
					-- (owner 2026-11-17: "remove the VIP mine"; and no train) no VIP door frame and no
					-- mossy linings any more: the side walls run on over the old door and the band
					T.eq(model:FindFirstChild("VipFrame"), nil, label .. " no VIP door frame")
					T.eq(model:FindFirstChild("OpeningLinings"), nil, label .. " no opening linings")
					-- (owner 2026-11-16: "board it up, an earth hill round it") an earth hill in each back
					-- corner in front of the massif's waterfalls, clear of the rock spawns
					local hills = model:FindFirstChild("CornerHills")
					T.truthy(hills ~= nil, label .. " the back corners' earth hills")
					if hills then
						local cores = 0
						for _, d in hills:GetChildren() do
							if d.Name == "HillCore" and d:IsA("BasePart") then
								cores += 1
								T.truthy(d.CanCollide and d.CanQuery, label .. " a hill's core stops the camera")
								local mn, mx = box(d)
								-- (the waterfall's foot, |x| 39.3 .. 48.7 either side at z -52.9 .. -52, inside it)
								local near, far = math.min(math.abs(mn.X), math.abs(mx.X)), math.max(math.abs(mn.X), math.abs(mx.X))
								T.truthy(mn.X * mx.X > 0 and near <= 39.3 and far >= 48.7, label .. " a hill over its waterfall's width")
								T.truthy(mn.Z <= -52.9 and mx.Z >= -52, label .. " a hill stands in front of its waterfall")
								T.truthy(mx.Y >= 28, label .. " a hill as tall as the walls")
								for _, spawn in DioramaData.Quarry.Spawns do
									local inside = spawn[1] > mn.X and spawn[1] < mx.X and spawn[3] > mn.Z and spawn[3] < mx.Z
									T.falsy(inside, label .. " no rock spawn under a hill")
								end
							end
						end
						T.eq(cores, 2, label .. " both back corners")
						-- (owner 2026-11-17: "the walls are still invisible") nobody walks into a hill's
						-- rock: its invisible body from both faces of its mossy cliff
						local hillBodies = 0
						local hill = Floor.CornerHills
						for _, d in hills:GetChildren() do
							if d.Name == "HillBody" and d:IsA("BasePart") then
								hillBodies += 1
								T.truthy(d.CanCollide, label .. " a hill's body is solid")
								T.eq(d.Transparency, 1, label .. " a hill's body is never seen")
								local mn, mx = box(d)
								T.near(mx.Z, hill.Z1 - hill.BodyIn, 0.01, label .. " a hill's body behind its south face")
								T.near(
									math.min(math.abs(mn.X), math.abs(mx.X)),
									hill.X0 + hill.BodyIn,
									0.01,
									label .. " a hill's body behind its inner face"
								)
							elseif d.Name == "HillCliff" then
								T.truthy(
									d.CanCollide and d.CanQuery and d:HasTag(Diorama.CameraTag),
									label .. " a hill's cliff stops the camera only"
								)
							end
						end
						T.eq(hillBodies, 2, label .. " both hills' bodies")
					end
					-- (owner 2026-11-17: no train, "remove all ... rails") the old quarry line modelled
					-- into the diorama's floor (rails up to 0.8 high, x -48 .. 48, z 21 .. 27) is covered:
					-- west of the still train's platform by a sand mound walked over, no rock spawn on it
					local cover = model:FindFirstChild("TrackCover")
					T.truthy(cover ~= nil, label .. " the old track covered")
					if cover then
						local t = Floor.TrackCover
						local mound = cover:FindFirstChild("Mound")
						T.truthy(mound ~= nil and mound.CanCollide, label .. " the mound is walked on")
						if mound then
							local mn, mx = box(mound)
							T.truthy(mn.X <= -48 and mx.X >= 4, label .. " the mound from the rails' west end to the platform")
							T.truthy(mn.Z <= 21 and mx.Z >= 27, label .. " the mound over both rails")
							T.le(0.85, mx.Y, label .. " the mound over the rails' tops")
						end
						for _, spawn in DioramaData.Quarry.Spawns do
							local on = spawn[1] > t.X0 - t.Slope
								and spawn[1] < t.X1
								and spawn[3] > t.Z0 - t.Slope
								and spawn[3] < t.Z1 + t.Slope
							T.falsy(on, label .. " no rock spawn on the mound")
						end
					end
					-- (2026-11-17, the Meshy chat's review: the back wall, the side walls' back ends and
					-- the hills stood up to 6 studs inside the Ember Caves, by its way out) nothing of the
					-- quarry's room, hills, linings, VIP frame or ground reaches past the Ember Caves' thin
					-- south wall, and nothing at all past its line, across the caves' width
					local emberLo, emberHi = Diorama.lines(2)
					local emberOrigin = MineFloors.Placement[2]
					local line = origin:PointToObjectSpace(emberOrigin:PointToWorldSpace(V3.new(0, 0, emberHi.Y))).Z
					local face = origin:PointToObjectSpace(emberOrigin:PointToWorldSpace(V3.new(0, 0, emberHi.Y + Diorama.ThinWall))).Z
					local x0 = origin:PointToObjectSpace(emberOrigin:PointToWorldSpace(V3.new(emberLo.X, 0, 0))).X
					local x1 = origin:PointToObjectSpace(emberOrigin:PointToWorldSpace(V3.new(emberHi.X, 0, 0))).X
					local strict = { Room = true, CornerHills = true, OpeningLinings = true, VipFrame = true, Ground = true }
					local intruders = 0
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") then
							local mn, mx = box(d)
							if mx.X > x0 and mn.X < x1 then
								local top = d
								while top.Parent and top.Parent ~= model do
									top = top.Parent
								end
								local limit = if strict[top.Name] then face else line
								-- (a hundredth: the rim's old top course ends on the caves' line)
								if mn.Z < limit - 0.01 then
									intruders += 1
								end
							end
						end
					end
					T.eq(intruders, 0, label .. " nothing reaches into the Ember Caves")
					local keep = Floor.DioramaKeep
					local fpLo, fpHi = Diorama.footprint(1)
					local lineE = fpHi.X + Diorama.WallGap + Diorama.MeshSlabGap
					local lineW = fpLo.X - Diorama.WallGap - Diorama.MeshSlabGap
					local standing = 0
					for _, d in model:FindFirstChild("QuarryRim"):GetDescendants() do
						if d:IsA("BasePart") then
							local mn, mx = box(d)
							if mn.Z >= keep.Z0 and mx.Z <= keep.Z1 and mn.Y < 28 then
								if (mx.X > keep.X and mn.X < lineE - 0.05) or (mn.X < -keep.X and mx.X > lineW + 0.05) then
									standing += 1
								end
							end
						end
					end
					T.eq(standing, 0, label .. " no rim part in front of the side walls' slab")
				end
				-- budgets
				local budget = if index <= 3 then MineKit.NearPartBudget else MineKit.PartBudget
				T.le(count(model, "BasePart"), budget, label .. " parts")
				T.le(count(model, "PointLight"), MineKit.LightBudget, label .. " lights")
				local ambience = 0
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") and not d.Anchored then
						error(label .. " unanchored part " .. d:GetFullName())
					end
					if d:IsA("Attachment") and d:HasTag(MineAmbience.Tag) then
						ambience += 1
					end
				end
				T.le(4, ambience, label .. " ambience spots")
				T.le(ambience, 8, label .. " ambience spots")
				if index == 6 then
					T.truthy(model:FindFirstChild("VoidCatcher"), label .. " void catcher")
				end
				-- the cave floors' closed room (owner 2026-11-14: "no void behind the walls, all ceilings
				-- the same"): one ceiling at CeilingHeight over the whole diorama, and every side the
				-- floor's look walls is closed up to it but for Land's passages; the open quarry's walls
				-- (owner: "you must not see behind them at all") up to their straight tops
				local room = model:FindFirstChild("Room")
				local look = Diorama.Floors[MineFloors.ByIndex[index].Id]
				local closed = MineFloors.CeilingFloors[index] == true
				T.eq(room ~= nil, closed or look.Walls ~= nil, label .. " walls round the cave floors and the quarry")
				if room then
					local fpLo, fpHi = Diorama.footprint(index)
					local ceiling = room:FindFirstChild("Ceiling")
					T.eq(ceiling ~= nil, closed, label .. " a ceiling on the cave floors only")
					if closed then
						T.near(
							ceiling.CFrame.Position.Y - ceiling.Size.Y / 2,
							origin.Y + MineFloors.CeilingHeight,
							0.01,
							label .. " ceiling height"
						)
						local c0 = origin:PointToObjectSpace(ceiling.CFrame.Position - ceiling.Size / 2)
						local c1 = origin:PointToObjectSpace(ceiling.CFrame.Position + ceiling.Size / 2)
						T.truthy(
							c0.X <= fpLo.X and c0.Z <= fpLo.Y and c1.X >= fpHi.X and c1.Z >= fpHi.Y,
							label .. " the ceiling covers the diorama"
						)
						local data = DioramaData[MineFloors.ByIndex[index].Id]
						T.le(data.Top, MineFloors.CeilingHeight, label .. " the diorama fits under the ceiling")
					end
					-- each side's wall top (open air: look.WallTops)
					local function topOf(side: string): number
						return if closed
							then MineFloors.CeilingHeight
							elseif look.WallTops and look.WallTops[side] then look.WallTops[side]
							else MineFloors.CeilingHeight
					end
					for _, d in room:GetChildren() do
						if d.Name == "WallSlab" and not closed then
							local p = origin:PointToObjectSpace(d.CFrame.Position)
							local side = if math.abs(p.X) > math.abs(p.Z)
								then (if p.X > 0 then "E" else "W")
								else (if p.Z > 0 then "S" else "N")
							T.near(p.Y + d.Size.Y / 2, topOf(side), 0.01, label .. " " .. side .. " wall's straight top")
						end
					end
					-- (the quarry's town-side wall stands in front of the town ground's edge at local
					-- z 58, whose flat face showed once Land's cliff went)
					if index == 1 then
						for _, d in room:GetChildren() do
							if d.Name == "WallSlab" then
								local p = origin:PointToObjectSpace(d.CFrame.Position)
								if p.Z > 50 and math.abs(p.X) < 55 then
									T.lt(p.Z - d.Size.Z / 2, 57.9, label .. " the town-side wall in front of the town's edge")
								end
							end
						end
					end
					local slabs = {}
					for _, d in room:GetChildren() do
						if d.Name == "WallSlab" or d.Name == "Lintel" then
							table.insert(slabs, d)
						end
						-- (owner 2026-11-16, his quarry shots: "you can see behind the 3D object") Roblox's
						-- camera stops only at parts that are CanCollide, CanQuery and near opaque: every
						-- piece of the room's walls and its ceiling is such a stop
						if table.find(Diorama.CameraStops, d.Name) and d:IsA("BasePart") then
							T.truthy(d.CanCollide and d.CanQuery, label .. " " .. d.Name .. " stops the camera")
							T.lt(d.Transparency, 0.25, label .. " " .. d.Name .. " is opaque to the camera")
						end
					end
					local function covered(p): boolean
						for _, slab in slabs do
							local q = slab.CFrame:PointToObjectSpace(p)
							local h = slab.Size / 2
							if math.abs(q.X) <= h.X + 0.01 and math.abs(q.Y) <= h.Y + 0.01 and math.abs(q.Z) <= h.Z + 0.01 then
								return true
							end
						end
						return false
					end
					-- each side's line out of the outline (look.WallGaps, moved in by look.WallLimits:
					-- Diorama.lines) and the probe just behind it
					local lineGap = {}
					local sides = {}
					local lnLo, lnHi = Diorama.lines(index)
					local function gapOut(side: string): number
						return if side == "N"
							then fpLo.Y - lnLo.Y
							elseif side == "S" then lnHi.Y - fpHi.Y
							elseif side == "W" then fpLo.X - lnLo.X
							else lnHi.X - fpHi.X
					end
					for _, side in look.Walls or {} do
						lineGap[side] = gapOut(side)
						-- (a wall faced with the owner's model has its slab further back)
						sides[side] = lineGap[side] + (if Diorama.meshWalls(look, side) then Diorama.MeshSlabGap else 0) + 0.35
					end
					for _, side in look.Thin or {} do
						lineGap[side] = gapOut(side)
						sides[side] = lineGap[side] + 0.05
					end
					-- (a taller wall ends on a lower one's line at a corner: past that line, over the
					-- lower wall, stays open, the way the town shows over the quarry's low south wall)
					local function overLower(side: string, t: number, y: number): boolean
						local alongX = side == "N" or side == "S"
						local startSide = if alongX then "W" else "N"
						local endSide = if alongX then "E" else "S"
						if sides[startSide] and topOf(startSide) < topOf(side) and y >= topOf(startSide) then
							local line = (if alongX then fpLo.X else fpLo.Y) - lineGap[startSide]
							if t < line then
								return true
							end
						end
						if sides[endSide] and topOf(endSide) < topOf(side) and y >= topOf(endSide) then
							local line = (if alongX then fpHi.X else fpHi.Y) + lineGap[endSide]
							if t > line then
								return true
							end
						end
						return false
					end
					local holes = 0
					for side, out in sides do
						local alongX = side == "N" or side == "S"
						local a0 = if alongX then fpLo.X else fpLo.Y
						local a1 = if alongX then fpHi.X else fpHi.Y
						for t = a0, a1, 3 do
							for _, y in { 0.5, 8, 16.5, 25, 33 } do
								if y >= topOf(side) then
									continue
								end
								local open = overLower(side, t, y)
								for _, o in look.Openings or {} do
									if o.Side == side and t > o.From and t < o.To and y < (o.Top or math.huge) then
										open = true
									end
								end
								if not open then
									local p = if side == "N"
										then V3.new(t, y, fpLo.Y - out)
										elseif side == "S" then V3.new(t, y, fpHi.Y + out)
										elseif side == "W" then V3.new(fpLo.X - out, y, t)
										else V3.new(fpHi.X + out, y, t)
									if not covered(origin:PointToWorldSpace(p)) then
										holes += 1
									end
								end
							end
						end
					end
					T.eq(holes, 0, label .. " the room's walls have no holes")
					-- (owner 2026-11-17: "remove all departures, rails and holes in the wall") the
					-- quarry's side walls are closed: no opening on E or W (the VIP door went too)
					if index == 1 then
						local sideOpenings = 0
						for _, o in look.Openings or {} do
							if o.Side == "E" or o.Side == "W" then
								sideOpenings += 1
							end
						end
						T.eq(sideOpenings, 0, label .. " no train band in the side walls")
					end
					-- and Land's passages stay open: no part of the room in an opening's lane (its width
					-- less a stud each side, from the ground up to its top, through the wall)
					for _, o in look.Openings or {} do
						local out = sides[o.Side]
						local alongX = o.Side == "N" or o.Side == "S"
						local line = if o.Side == "N"
							then fpLo.Y
							elseif o.Side == "S" then fpHi.Y
							elseif o.Side == "W" then fpLo.X
							else fpHi.X
						local across0, across1 = line - (Diorama.WallDepth + 3), line + (Diorama.WallDepth + 3)
						local lo3 = if alongX then V3.new(o.From + 1, 0.5, across0) else V3.new(across0, 0.5, o.From + 1)
						local hi3 = if alongX
							then V3.new(o.To - 1, math.min(o.Top or 30, 30) - 0.5, across1)
							else V3.new(across1, math.min(o.Top or 30, 30) - 0.5, o.To - 1)
						local blocked = 0
						for _, d in room:GetDescendants() do
							-- (a veil is walked through: checked below)
							if d:IsA("BasePart") and d.Name ~= "Veil" then
								local mn, mx = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
								for _, sx in { -1, 1 } do
									for _, sy in { -1, 1 } do
										for _, sz in { -1, 1 } do
											local c = origin:PointToObjectSpace(d.CFrame:PointToWorldSpace(V3.new(sx, sy, sz) * d.Size / 2))
											mn, mx = mn:Min(c), mx:Max(c)
										end
									end
								end
								if mn.X < hi3.X and mx.X > lo3.X and mn.Y < hi3.Y and mx.Y > lo3.Y and mn.Z < hi3.Z and mx.Z > lo3.Z then
									blocked += 1
								end
							end
						end
						T.eq(blocked, 0, label .. " the " .. o.Side .. " way through stays open")
						T.truthy(out ~= nil, label .. " an opening on a walled side")
						-- a veiled opening: one glowing curtain over all of it, walked through, never seen through
						if o.Veil then
							local veils = 0
							for _, d in room:GetChildren() do
								if d.Name == "Veil" then
									veils += 1
									T.eq(d.CanCollide, false, label .. " the veil is walked through")
									T.eq(d.CanQuery, false, label .. " the veil takes no clicks or shots")
									T.eq(d.Transparency, 0, label .. " the veil is never seen through")
									-- (its box from its 8 corners: a veil is turned to face into the room)
									local q0 = V3.new(math.huge, math.huge, math.huge)
									local q1 = V3.new(-math.huge, -math.huge, -math.huge)
									for _, sx in { -1, 1 } do
										for _, sy in { -1, 1 } do
											for _, sz in { -1, 1 } do
												local c =
													origin:PointToObjectSpace(d.CFrame:PointToWorldSpace(V3.new(sx, sy, sz) * d.Size / 2))
												q0, q1 = q0:Min(c), q1:Max(c)
											end
										end
									end
									local a0 = if alongX then q0.X else q0.Z
									local a1 = if alongX then q1.X else q1.Z
									T.truthy(a0 <= o.From and a1 >= o.To, label .. " the veil spans the opening")
									T.truthy(q0.Y <= 0 and q1.Y >= (o.Top or 30), label .. " the veil from the ground to the opening's top")
								end
							end
							T.eq(veils, 1, label .. " one veil in the " .. o.Side .. " way through")
						end
					end
					-- the walls faced with the owner's model: its chunks on those sides only
					if look.WallMesh then
						local faced: { [string]: number } = {}
						for _, d in room:GetChildren() do
							if d.Name == "MeshWall" then
								T.eq(d:GetAttribute("Asset"), look.WallMesh, label .. " the wall chunks are the owner's model")
								-- (owner 2026-11-16: a solid chunk's box stood where its ragged rock is not, "a wall
								-- that's there but invisible"; 2026-11-17: the camera looked out from inside the
								-- rock) the chunks stop the camera and nothing else (WorldService's group)
								T.truthy(
									d.CanCollide and d.CanQuery and d:HasTag(Diorama.CameraTag),
									label .. " a wall chunk stops the camera only"
								)
								local p = origin:PointToObjectSpace(d.CFrame.Position)
								local side = if math.abs(p.X) > math.abs(p.Z)
									then (if p.X > 0 then "E" else "W")
									else (if p.Z > 0 then "S" else "N")
								faced[side] = (faced[side] or 0) + 1
							end
						end
						for _, side in look.Walls or {} do
							T.eq(
								(faced[side] or 0) > 0,
								Diorama.meshWalls(look, side),
								label .. " " .. side .. " wall faced with the owner's model"
							)
						end
						-- (owner 2026-11-17: "the walls are still invisible": players walked into the rock
						-- and fell into the wall) every mesh-faced side has its invisible body from the
						-- chunks' fronts, from under the ground to its top, but in its openings
						local bodyParts = {}
						for _, d in room:GetChildren() do
							if d.Name == "WallBody" then
								table.insert(bodyParts, d)
								T.truthy(d.CanCollide, label .. " a wall's body is solid")
								T.eq(d.Transparency, 1, label .. " a wall's body is never seen")
								T.eq(d.CanQuery, false, label .. " a wall's body takes no clicks or shots")
							end
						end
						local function inBody(p): boolean
							for _, body in bodyParts do
								local q = body.CFrame:PointToObjectSpace(p)
								local h = body.Size / 2
								if math.abs(q.X) <= h.X + 0.01 and math.abs(q.Y) <= h.Y + 0.01 and math.abs(q.Z) <= h.Z + 0.01 then
									return true
								end
							end
							return false
						end
						-- (along a side: the room's span, inside the walls at its ends, where a lower one ends it)
						local function span(side: string): (number, number)
							local alongX = side == "N" or side == "S"
							local a0 = if alongX then fpLo.X else fpLo.Y
							local a1 = if alongX then fpHi.X else fpHi.Y
							local s0, s1 = if alongX then "W" else "N", if alongX then "E" else "S"
							if lineGap[s0] then
								a0 = math.max(a0, (if alongX then fpLo.X else fpLo.Y) - lineGap[s0])
							end
							if lineGap[s1] then
								a1 = math.min(a1, (if alongX then fpHi.X else fpHi.Y) + lineGap[s1])
							end
							return a0, a1
						end
						local bodyHoles, bodyAhead = 0, 0
						for _, side in look.Walls or {} do
							if not Diorama.meshWalls(look, side) then
								continue
							end
							local alongX = side == "N" or side == "S"
							local a0, a1 = span(side)
							local line = if side == "N"
								then fpLo.Y - lineGap[side]
								elseif side == "S" then fpHi.Y + lineGap[side]
								elseif side == "W" then fpLo.X - lineGap[side]
								else fpHi.X + lineGap[side]
							local inward = if side == "N" or side == "W" then 1 else -1
							for t = a0, a1, 3 do
								for _, y in { 0.5, 8, 16.5, 25 } do
									if y >= topOf(side) then
										continue
									end
									local open = false
									for _, o in look.Openings or {} do
										if o.Side == side and t > o.From - 0.05 and t < o.To + 0.05 and y < (o.Top or math.huge) then
											open = true
										end
									end
									if open then
										continue
									end
									local function at3(across: number)
										return origin:PointToWorldSpace(if alongX then V3.new(t, y, across) else V3.new(across, y, t))
									end
									-- (just behind its front: solid; just in front: free)
									if not inBody(at3(line + inward * (Diorama.MeshBodyIn - 0.05))) then
										bodyHoles += 1
									end
									-- (a stud off the corners, where the next side's body stands)
									if t > a0 + 1 and t < a1 - 1 and inBody(at3(line + inward * (Diorama.MeshBodyIn + 0.05))) then
										bodyAhead += 1
									end
								end
							end
						end
						T.eq(bodyHoles, 0, label .. " the mesh-faced walls' bodies have no holes")
						T.eq(bodyAhead, 0, label .. " the bodies stand at the rock's front")
						-- and the walk boxes reach them: wherever the ground within LedgeReach of a body
						-- is a terrace, the ground right at the body is at least as high (no gap to fall in)
						local ground = model:FindFirstChild("Ground")
						local boxes = {}
						for _, d in ground:GetChildren() do
							if d:IsA("Part") and (d.Name == "Ground" or d.Name == "Ledge") then
								table.insert(boxes, d)
							end
						end
						-- (a corner hill's body is ground too: the walls run on behind it)
						local cornerHills = model:FindFirstChild("CornerHills")
						if cornerHills then
							for _, d in cornerHills:GetChildren() do
								if d:IsA("Part") and d.Name == "HillBody" then
									table.insert(boxes, d)
								end
							end
						end
						local function topAt(x: number, z: number): number
							local best = -math.huge
							for _, b in boxes do
								local c = origin:PointToObjectSpace(b.CFrame.Position)
								local h = b.Size / 2
								if math.abs(x - c.X) <= h.X + 1e-3 and math.abs(z - c.Z) <= h.Z + 1e-3 then
									best = math.max(best, c.Y + h.Y)
								end
							end
							return best
						end
						local gaps = 0
						for _, side in look.Walls or {} do
							if not Diorama.meshWalls(look, side) then
								continue
							end
							local alongX = side == "N" or side == "S"
							local a0, a1 = span(side)
							local front = if side == "N"
								then fpLo.Y - lineGap[side] + Diorama.MeshBodyIn
								elseif side == "S" then fpHi.Y + lineGap[side] - Diorama.MeshBodyIn
								elseif side == "W" then fpLo.X - lineGap[side] + Diorama.MeshBodyIn
								else fpHi.X + lineGap[side] - Diorama.MeshBodyIn
							local inward = if side == "N" or side == "W" then 1 else -1
							for t = a0 + 0.75, a1 - 0.75, 1.5 do
								local open = false
								for _, o in look.Openings or {} do
									if o.Side == side and t > o.From - 1 and t < o.To + 1 then
										open = true
									end
								end
								if open then
									continue
								end
								local function topIn(d: number): number
									local across = front + inward * d
									return if alongX then topAt(t, across) else topAt(across, t)
								end
								local near = topIn(0.2)
								local far = -math.huge
								for _, d in { 1, 2, 3, 4 } do
									far = math.max(far, topIn(d))
								end
								if far > near + 0.01 then
									gaps += 1
								end
							end
						end
						T.eq(gaps, 0, label .. " no gap between the terraces and the mossy walls")
						-- the ledges keep out of the openings
						for _, d in ground:GetChildren() do
							if d.Name == "Ledge" then
								local c = origin:PointToObjectSpace(d.CFrame.Position)
								local h = d.Size / 2
								for _, o in look.Openings or {} do
									if Diorama.meshWalls(look, o.Side) then
										local alongX = o.Side == "N" or o.Side == "S"
										local m0 = (if alongX then c.X - h.X else c.Z - h.Z)
										local m1 = (if alongX then c.X + h.X else c.Z + h.Z)
										local inside = math.min(m1, o.To) - math.max(m0, o.From) > 0.05
										local fpEdge = if o.Side == "N"
											then c.Z - h.Z < fpLo.Y + Diorama.LedgeReach
											elseif o.Side == "S" then c.Z + h.Z > fpHi.Y - Diorama.LedgeReach
											elseif o.Side == "W" then c.X - h.X < fpLo.X + Diorama.LedgeReach
											else c.X + h.X > fpHi.X - Diorama.LedgeReach
										T.falsy(inside and fpEdge, label .. " no ledge in the " .. o.Side .. " opening")
									end
								end
							end
						end
					end
				end
			end
		end)
		Fakes.unmount(Loader)
		if not ok then
			error(err, 0)
		end
	end)
end
