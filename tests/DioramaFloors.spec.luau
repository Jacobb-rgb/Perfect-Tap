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
					local cx, cz = (data.Ramps[i] + data.Ramps[i + 2]) / 2, (data.Ramps[i + 1] + data.Ramps[i + 3]) / 2
					for _, f in flats do
						if cx > f[1] and cx < f[4] and cz > f[3] and cz < f[6] then
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
					local slabs = {}
					for _, d in room:GetChildren() do
						if d.Name == "WallSlab" or d.Name == "Lintel" then
							table.insert(slabs, d)
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
					local sides = {}
					for _, side in look.Walls or {} do
						sides[side] = Diorama.WallGap + 0.35
					end
					for _, side in look.Thin or {} do
						sides[side] = Diorama.ThinGap + 0.05
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
								local open = false
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
							if d:IsA("BasePart") then
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
