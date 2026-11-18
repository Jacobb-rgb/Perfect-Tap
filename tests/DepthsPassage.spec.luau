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
			local fills, ramps = 0, 0
			local fillBoxes: { { any } } = {}
			for _, d in passage:GetChildren() do
				T.truthy(d:IsA("BasePart"), "parts only: " .. d.Name)
				local mn, mx = bounds(origin, d)
				-- between the Ember Caves' south wall (or in its 0.12 thickness, local -60.09 .. -59.97)
				-- and the model's cut behind its door; the sill's ramp runs on into the caves' doorway,
				-- the door's frame into the model's door
				if d.Name == "SillRamp" and mn.Z < -60.08 then
					T.le(-60.03 - k.Sill.InRun - 0.01, mn.Z, "the ramp into the caves no longer than its run")
					T.le(mx.X, 10, "the ramp into the caves within their doorway")
				else
					T.le(-60.08, mn.Z, "nothing in the Ember Caves: " .. d.Name)
				end
				T.le(mx.Z, if d.Name == "Frame" then k.Frame.Z1 + 1e-3 else -44.0, "nothing in the model's facade: " .. d.Name)
				-- (a post never through the wall: its side would share the wall's door side's plane)
				if d.Name == "Frame" then
					T.falsy(mn.Z < k.Wall.Z0 - 1e-3 and mx.Z > k.Wall.Z1 + 1e-3, "a frame part through the wall")
				end
				if d.Name == "Sill" or d.Name == "SillRamp" then
					T.truthy(d:HasTag("NoStuds"), "smooth sand, no studs")
				end
				if d.Name == "Fill" then
					fills += 1
					T.eq(d.Transparency, 1, "a corner's fill is never seen")
					T.truthy(d.CanCollide and not d.CanQuery, "it holds players, the camera and the blaster pass")
					table.insert(bodies, { mn, mx })
					table.insert(fillBoxes, { mn, mx })
				else
					T.eq(d.Transparency, 0, "a wall is seen: " .. d.Name)
					T.truthy(d.CanCollide and d.CanQuery, "solid, and the camera stops on it: " .. d.Name)
					-- (a ramp is a wedge: its box over the slope is air, its slope is checked below)
					if d.Name == "SillRamp" then
						T.truthy(d:IsA("WedgePart"), "a sand ramp")
						ramps += 1
						-- (a wedge slopes down toward its front, LookVector: away from the sill)
						local look = origin:VectorToObjectSpace(d.CFrame.LookVector)
						local outward = if (mn.Z + mx.Z) / 2 > k.Sill.Z1 - 1 then 1 else -1
						T.near(look.Z, outward, 1e-3, "a ramp's high side at the sill")
					else
						table.insert(boxes, { mn, mx })
						table.insert(bodies, { mn, mx })
					end
				end
			end
			-- (two corner fills at the wall's height, the back's fills strip by strip at 40)
			local corners = 0
			for _, b in fillBoxes do
				if b[2].Y < 20 then
					corners += 1
				end
			end
			T.eq(corners, 2, "a fill in either corner")
			T.le(4, fills, "and the back's behind either buttress and trench")
			T.eq(ramps, 2, "the sill's two ramps")
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
			-- the door's top at x (its steps)
			local function doorTop(x: number): number
				local top = 0
				for _, d in k.Door do
					if x > d[1] and x < d[2] then
						top = math.max(top, d[3])
					end
				end
				return top
			end
			local zMid = (k.Wall.Z0 + k.Wall.Z1) / 2
			-- the wall closes the cut (x -24 .. 24) from the ground up to its top, all but the door
			for _, s in k.Tops do
				-- (capped at the lintel's underside where the lintel and the ceiling are over it)
				local top = if s[1] >= -k.Lintel.X and s[2] <= k.Lintel.X then math.min(s[3], k.Lintel.Y) else s[3]
				local x = s[1] + 0.05
				while x < s[2] do
					local y = 0.5
					while y < top - 0.05 do
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
			-- the door stays open, as tall as a player and more (8.25 over the most of it: a tall rider
			-- on a hoverboard)
			local x = door[1] + 0.05
			while x < door[2] do
				for _, y in { 0.5, 3, 6, 7.5, doorTop(x) - 0.1 } do
					for _, z in { k.Wall.Z0 - 1, zMid, k.Wall.Z1, k.Frame.Z1 - 0.1 } do
						T.falsy(solid(V3.new(x, y, z)), string.format("the door open at x %.2f, y %.1f, z %.1f", x, y, z))
					end
				end
				x += 0.25
			end
			T.le(8.25, doorTop(-1), "the door 8.25 high over the walk floor")
			-- the frame round the door holds the cut's slivers of the model's arch (out to local z -47.3,
			-- up to y 9.8), its posts close the model's door sides on to Frame.Z1, its head over the model's
			-- door ceiling
			for _, x in { door[1] + 0.1, -2.65, (door[1] + door[2]) / 2, door[2] - 0.1 } do
				for _, y in { doorTop(x) + 0.05, 8.75, 9.25, 9.85 } do
					T.truthy(solid(V3.new(x, y, -47.35)), string.format("the frame's head over the slivers (x %.2f, y %.2f)", x, y))
				end
				T.truthy(solid(V3.new(x, 10.5, -42)), "a head over the model's door ceiling")
			end
			for _, z in { -46, -43, -41.6 } do
				T.truthy(solid(V3.new(door[1] - 0.5, 4, z)) and solid(V3.new(door[2] + 0.5, 4, z)), "the posts at z " .. z)
			end
			T.le(k.Frame.Z, -47.35, "the frame out past the slivers")
			-- the sand sill over the model's back edge (its teeth up to 1.75, z -58.9 .. -57.7, |x| <= 18.8,
			-- the part beyond 17.2 behind the buttresses' sides) and the floor seam along the wall
			local sill = k.Sill
			T.le(1.75 + 0.1, sill.Top, "the sill over the teeth")
			T.le(sill.Z1, -57.6, "on past them")
			for _, sx in { -17.1, -10, 0, 10, 17.1 } do
				for _, sz in { -59.95, -58.9, -58.3, -57.7 } do
					T.truthy(solid(V3.new(sx, sill.Top - 0.05, sz)), string.format("the sill at x %.1f, z %.2f", sx, sz))
				end
			end
			-- its ramps walkable (under 40 degrees), down to the sand and to the caves' floor
			T.le(math.deg(math.atan((sill.Top - sill.Low) / sill.Run)), 40, "the ramp to the sand")
			T.le(math.deg(math.atan((sill.Top - sill.InLow) / sill.InRun)), 40, "the ramp into the caves")
			T.le(sill.Low, -0.45, "the ramp's foot under the sand")
			T.le(sill.InLow, 0, "the ramp's foot under the caves' floor")
			-- the way through: from the caves' floor over the sill to the model's door nothing to bump
			-- into from a hair over the floor to under the door's head
			local function floorAt(z: number): number
				if z <= sill.Z1 then
					return sill.Top
				elseif z <= sill.Z1 + sill.Run then
					return sill.Top - (z - sill.Z1) / sill.Run * (sill.Top - sill.Low)
				end
				return 0
			end
			local z = k.EmberWall + 0.1
			while z < -43.9 do
				for _, wx in { door[1] + 0.3, -1, door[2] - 0.3 } do
					local y = math.max(floorAt(z), 0) + 0.6
					while y < doorTop(wx) - 0.2 do
						if bumps(V3.new(wx, y, z)) then
							error(string.format("something to bump into on the way at x %.2f, y %.2f, z %.2f", wx, y, z), 0)
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
			-- a player on the fill behind the buttresses and the back cliffs jumps back onto the cliffs
			local tallest = 0
			for i = 1, #data.Boxes, 5 do
				if data.Boxes[i + 1] <= k.Fill.TrenchZ + 2 and math.abs(data.Boxes[i]) < 60 then
					tallest = math.max(tallest, data.Boxes[i + 4])
				end
			end
			-- (as high as smoothSurround's walls: nobody stands on air over a trench)
			T.le(tallest + 7.5, k.Fill.BackTop, "over the tallest cliff beside it and a jump")
			T.eq(k.Fill.BackTop, Floor.Smooth.Top, "as high as smoothSurround's walls")
			-- and never over his walk boxes (an invisible wall before a cliff top's visible edge)
			for _, b in fillBoxes do
				local mn, mx = b[1], b[2]
				if mx.Y > 20 then
					for i = 1, #data.Boxes, 5 do
						local x0, z0, x1, z1 = data.Boxes[i], data.Boxes[i + 1], data.Boxes[i + 2], data.Boxes[i + 3]
						local over = mn.X < x1 - 0.01 and mx.X > x0 + 0.01 and mn.Z < z1 - 0.01 and mx.Z > z0 + 0.01
						if over then
							error(string.format("a back fill over a walk box at x %.2f .. %.2f, z %.2f .. %.2f", x0, x1, z0, z1), 0)
						end
					end
				end
			end
			for _, side in { -1, 1 } do
				T.truthy(inside(fillBoxes, V3.new(side * 20, k.Fill.BackTop - 0.5, -59)), "behind the buttress up to the cliffs")
			end
			-- the passage's sides close the slits beside the pillars, under the lintel's corners and
			-- under the buttresses (they stand on y 0, the sand at -0.45)
			for _, side in { -1, 1 } do
				for _, p in
					{
						V3.new(side * 16.2, 17.75, -47),
						V3.new(side * 16.0, 10, -51.1),
						V3.new(side * 16.3, 20, -50.5),
						V3.new(side * 16.7, -0.2, -55),
						V3.new(side * 16.7, 10, -60.0),
					}
				do
					T.truthy(solid(p), "a side closes " .. tostring(p))
				end
			end
			-- under the lintel the wall stops at its underside: the keystone, its arrow and the
			-- lintel's lamps stay in view from the quarry
			for _, d in passage:GetChildren() do
				if d.Name == "Wall" then
					local mn, mx = bounds(origin, d)
					if mn.X >= -k.Lintel.X - 1e-3 and mx.X <= k.Lintel.X + 1e-3 then
						T.le(mx.Y, k.Lintel.Y + 1e-3, "the wall under the lintel's underside")
					end
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
