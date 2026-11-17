-- The passage between the Ember Caves and the quarry (owner 2026-11-17, walking back out of the caves:
-- "on the way back you still see out: just put a wall there with a way through to the next location,
-- and take the red off"): Floor1Quarry walls it behind the model's mine door, the door the model's own.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local V3 = roblox.Vector3
	local Fakes = require("../tools/lune/lib/mesh_fakes")
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local DioramaData = Loader.requirePath("ServerScriptService.Server.World.Mine.DioramaData")
	local Floor = Loader.requirePath("ServerScriptService.Server.World.Mine.Floor1Quarry")
	local Diorama = Loader.requirePath("ServerScriptService.Server.World.Mine.Diorama")

	-- a part's box in the floor's frame
	local function bounds(origin: any, d: any): (any, any)
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

	local function build(cutaway: boolean): (any, any)
		local folder = roblox.Instance.new("Folder")
		local origin = MineFloors.Placement[1]
		return Floor.build(folder, origin, { Cutaway = cutaway }), origin
	end

	T.test("depths passage: a wall with the model's door, nothing seen out", function()
		Fakes(Loader, true)
		local ok, err = pcall(function()
			T.truthy(MineFloors.usesNextSet(1), "the quarry from its newest set")
			local model, origin = build(false)
			local passage = model:FindFirstChild("DepthsPassage")
			T.truthy(passage ~= nil, "the passage is walled")
			local k = Floor.Passage
			local boxes: { { any } } = {} -- the walls seen
			local bodies: { { any } } = {} -- what a player bumps into
			local fills = 0
			local fillBoxes: { { any } } = {}
			for _, d in passage:GetChildren() do
				T.truthy(d:IsA("BasePart"), "parts only: " .. d.Name)
				local mn, mx = bounds(origin, d)
				-- between the Ember Caves' south wall and the model's cut behind its door (the sand
				-- strip under the doorway's floor seam reaches under the caves' floor)
				T.le(if d.Name == "Threshold" then -60.25 else -59.98, mn.Z, "nothing in the Ember Caves: " .. d.Name)
				T.le(mx.Z, -44.0, "nothing in the model's facade: " .. d.Name)
				if d.Name == "Fill" then
					fills += 1
					T.eq(d.Transparency, 1, "a corner's fill is never seen")
					T.truthy(d.CanCollide and not d.CanQuery, "it holds players, the camera and the blaster pass")
					table.insert(bodies, { mn, mx })
					table.insert(fillBoxes, { mn, mx })
				elseif d.Name == "Threshold" then
					T.truthy(not d.CanCollide and not d.CanQuery, "the sand under the seam is a look")
					T.le(mx.Y, -0.5 + 1e-3, "under the floor")
					T.truthy(mn.X <= -10.2 and mx.X >= 10.2 and mn.Z <= -60 and mx.Z >= -59.9, "under the whole doorway's seam")
				else
					T.eq(d.Transparency, 0, "a wall is seen: " .. d.Name)
					T.truthy(d.CanCollide and d.CanQuery, "solid, and the camera stops on it: " .. d.Name)
					table.insert(boxes, { mn, mx })
					table.insert(bodies, { mn, mx })
				end
			end
			T.eq(fills, 4, "a fill in either corner and either trench")
			local function inside(list: { { any } }, p: any): boolean
				for _, b in list do
					local mn, mx = b[1], b[2]
					if
						p.X >= mn.X - 1e-3
						and p.X <= mx.X + 1e-3
						and p.Y >= mn.Y - 1e-3
						and p.Y <= mx.Y + 1e-3
						and p.Z >= mn.Z - 1e-3
						and p.Z <= mx.Z + 1e-3
					then
						return true
					end
				end
				return false
			end
			local function solid(p: any): boolean
				return inside(boxes, p)
			end
			local function bumps(p: any): boolean
				return inside(bodies, p)
			end
			local door = k.Door[1]
			local zMid = (k.Wall.Z0 + k.Wall.Z1) / 2
			-- the wall closes the cut (x -24 .. 24) from the ground up to its top, all but the door
			for _, s in k.Tops do
				local x = s[1] + 0.05
				while x < s[2] do
					local y = 0.5
					while y < s[3] - 0.05 do
						local inDoor = false
						for _, d in k.Door do
							if x > d[1] and x < d[2] and y < d[3] then
								inDoor = true
							end
						end
						if not inDoor and not solid(V3.new(x, y, zMid)) then
							error(string.format("a gap in the wall at x %.2f, y %.2f", x, y), 0)
						end
						y += 0.5
					end
					x += 0.1
				end
			end
			T.eq(k.Tops[1][1], -24, "the wall from the cut's west side")
			T.eq(k.Tops[#k.Tops][2], 24, "to its east side")
			for i = 2, #k.Tops do
				T.eq(k.Tops[i][1], k.Tops[i - 1][2], "the wall's stretches meet")
			end
			-- the door stays open, as tall as a player and more
			local x = door[1] + 0.05
			while x < door[2] do
				for _, y in { 0.5, 3, 6, 7.5 } do
					for _, z in { k.Wall.Z0 - 1, zMid, k.Wall.Z1 } do
						T.falsy(solid(V3.new(x, y, z)), string.format("the door open at x %.2f, y %.1f, z %.1f", x, y, z))
					end
				end
				x += 0.25
			end
			-- the frame round the door holds the cut's slivers of the model's arch (out to local z -47.3,
			-- up to y 9.8)
			for _, x in { door[1] + 0.1, (door[1] + door[2]) / 2, door[2] - 0.1 } do
				for _, y in { door[3] + 0.1, 8.75, 9.25, 9.85 } do
					T.truthy(solid(V3.new(x, y, -47.35)), string.format("the frame's head over the slivers (y %.2f)", y))
				end
			end
			T.le(k.Frame.Z, -47.35, "the frame out past the slivers")
			-- the way through: from the Ember Caves' wall to the model's door nothing to bump into
			-- under the door's head (7.75 high, as the town's shop doors)
			local z = k.EmberWall + 0.1
			while z < -43.9 do
				for _, x in { door[1] + 0.3, (door[1] + door[2]) / 2, door[2] - 0.3 } do
					local y = 0.5
					while y < door[3] - 0.2 do
						if bumps(V3.new(x, y, z)) then
							error(string.format("something to bump into on the way at x %.2f, y %.2f, z %.2f", x, y, z), 0)
						end
						y += 0.5
					end
				end
				z += 0.5
			end
			-- the corners beside the portal and the trenches behind the model's back cliffs are filled:
			-- no pit to drop into, level with the wall's low ends (where no walk box stands higher)
			local data = DioramaData.QuarryNext
			local function walkTop(x: number, z: number): number
				local top = -math.huge
				for i = 1, #data.Boxes, 5 do
					local b = data.Boxes
					if x >= b[i] and x <= b[i + 2] and z >= b[i + 1] and z <= b[i + 3] then
						top = math.max(top, b[i + 4])
					end
				end
				return top
			end
			local fpLo, fpHi = Diorama.footprint(1)
			for _, side in { -1, 1 } do
				local fillTop = if side < 0 then k.Fill.TopW else k.Fill.TopE
				local edge = if side < 0 then -fpLo.X else fpHi.X
				local ax = k.Fill.X0 + 0.1
				-- (the last strip by his model's edge, between his cliffs' walk boxes (to 57.57) and
				-- smoothSurround's body: under 2 studs wide, nobody fits in it)
				while ax < edge - 2 do
					-- from the back toward the wall: held by a fill until the model's cliffs (walk boxes
					-- as high) start; beside the portal, where no cliff stands, all the way to the wall
					local x = side * ax
					local z = -58.8
					while z < k.Wall.Z0 - 0.1 do
						if walkTop(x, z) >= fillTop - 0.5 then
							break
						end
						if not inside(fillBoxes, V3.new(x, fillTop - 0.2, z)) then
							error(string.format("a pit behind the portal at x %.2f, z %.2f", x, z), 0)
						end
						z += 0.5
					end
					ax += 0.5
				end
			end
			-- the passage's sides close the slits beside the pillars and under the lintel's corners
			for _, side in { -1, 1 } do
				for _, p in { V3.new(side * 16.2, 17.75, -47), V3.new(side * 16.0, 10, -51.1), V3.new(side * 16.3, 20, -50.5) } do
					T.truthy(solid(p), "a side closes " .. tostring(p))
				end
			end
			T.eq(k.Fill.TopW, k.Tops[1][3], "the west fill level with the wall's west end")
			T.eq(k.Fill.TopE, k.Tops[#k.Tops][3], "the east fill level with the wall's east end")
			-- the model's walk floor through its door fits the wall's door (it is the model's)
			local found = false
			for i = 1, #data.Boxes, 5 do
				local x0, z0, x1, z1, top = data.Boxes[i], data.Boxes[i + 1], data.Boxes[i + 2], data.Boxes[i + 3], data.Boxes[i + 4]
				if top <= 1 and x0 <= 0 and x1 >= 0 and z0 <= -43.5 and z1 >= -43.5 then
					found = true
					T.le(door[1], x0, "the walk floor inside the door (west)")
					T.le(x1, door[2], "the walk floor inside the door (east)")
				end
			end
			T.truthy(found, "the model's walk floor through its door")
			-- looking up through the door: the ceiling from the lintel to the wall, under every top
			T.truthy(solid(V3.new(0, k.Lintel.Y - 0.25, (k.Lintel.Z + k.Wall.Z0) / 2)), "a ceiling over the door's way")
			for _, s in k.Tops do
				if s[1] < k.Lintel.X and s[2] > -k.Lintel.X then
					T.le(k.Lintel.Y, s[3], "the wall meets the ceiling")
				end
			end
			-- the slot behind the lintel and the roof over the tunnel, its sides
			T.truthy(solid(V3.new(0, 23, -50.8)), "the slot between the parapet and the lintel")
			T.truthy(solid(V3.new(0, 22.2, -59)), "the roof over the tunnel")
			for _, side in { -1, 1 } do
				T.truthy(solid(V3.new(side * 16.7, 10, -59)), "the tunnel's side")
				T.truthy(solid(V3.new(side * 16.3, 10, -46)), "the side by the door")
			end
			-- previews without the town (no DEPTHS portal) build none
			local cut = build(true)
			T.eq(cut:FindFirstChild("DepthsPassage"), nil, "no passage in a cutaway")
		end)
		Fakes.unmount(Loader)
		if not ok then
			error(err, 0)
		end
	end)
end
