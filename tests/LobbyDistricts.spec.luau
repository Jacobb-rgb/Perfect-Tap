--[[
	Lobby package "Districts" (src/server/World/Lobby/Districts): every
	gameplay hook exists once under Lobby.Districts with the right class,
	children and attributes, every piece stays inside its LobbyLayout
	footprint and height budget (spinning models over their whole sweep),
	the SPIN & WIN frame grows with a bigger footprint and its armored
	housings make it about 1.5 times as wide as the disc, the SHOP and
	UPGRADES modules get lit display bays and showcases for their width (20
	or 28), Tobin's Sell stall stays low in front of the SHOP, the walk lanes
	to the shop counters stay open, the build is deterministic and the
	package stays inside its budget.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")

	local TOLERANCE = 0.25

	local cachedMap = nil
	local function districts()
		if not cachedMap then
			local game = roblox.Instance.new("DataModel")
			cachedMap = WorldBuilder.build(game:GetService("Workspace"))
		end
		local lobby = cachedMap.Emberfall:FindFirstChild("Lobby")
		return cachedMap, lobby and lobby:FindFirstChild("Districts")
	end

	local function hasTag(inst, tag: string): boolean
		return table.find(inst:GetTags(), tag) ~= nil
	end

	local function tagged(root, tag: string): { any }
		local out = {}
		if hasTag(root, tag) then
			table.insert(out, root)
		end
		for _, d in root:GetDescendants() do
			if hasTag(d, tag) then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Points on a part's surface hull: box corners, or rings/axis points for
	-- cylinders and balls (their bounding boxes would overshoot when swept).
	local function corners(part): { any }
		local cf, s = part.CFrame, part.Size / 2
		local out = {}
		local shape = if part:IsA("Part") then part.Shape else nil
		if shape == roblox.Enum.PartType.Cylinder then
			local r = math.min(s.Y, s.Z)
			for _, x in { -s.X, s.X } do
				for k = 0, 15 do
					local a = k * math.pi / 8
					table.insert(out, cf * Vector3.new(x, r * math.cos(a), r * math.sin(a)))
				end
			end
		elseif shape == roblox.Enum.PartType.Ball then
			local r = math.min(s.X, s.Y, s.Z)
			for _, v in { Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) } do
				table.insert(out, cf * (v * r))
				table.insert(out, cf * (v * -r))
			end
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						table.insert(out, cf * (Vector3.new(x, y, z).Unit * r))
					end
				end
			end
		else
			-- a WedgePart has no top-front edge (its tall side is +Z)
			local wedge = part:IsA("WedgePart")
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						if not (wedge and y > 0 and z < 0) then
							table.insert(out, cf * Vector3.new(x * s.X, y * s.Y, z * s.Z))
						end
					end
				end
			end
		end
		return out
	end

	-- the Spin model (if any) a part turns with
	local function spinnerOf(part, root)
		local node = part.Parent
		while node and node ~= root do
			if node:IsA("Model") and hasTag(node, "Spin") then
				return node
			end
			node = node.Parent
		end
		return nil
	end

	-- Every colliding part under `root` as a box in `frame` (min/max per axis).
	type Box = { Name: string, MinX: number, MaxX: number, MinY: number, MaxY: number, MinZ: number, MaxZ: number }
	local function solidBoxes(root, frame): { Box }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				local b: Box = {
					Name = d:GetFullName(),
					MinX = math.huge,
					MaxX = -math.huge,
					MinY = math.huge,
					MaxY = -math.huge,
					MinZ = math.huge,
					MaxZ = -math.huge,
				}
				for _, p in corners(d) do
					local q = frame:PointToObjectSpace(p)
					b.MinX, b.MaxX = math.min(b.MinX, q.X), math.max(b.MaxX, q.X)
					b.MinY, b.MaxY = math.min(b.MinY, q.Y), math.max(b.MaxY, q.Y)
					b.MinZ, b.MaxZ = math.min(b.MinZ, q.Z), math.max(b.MaxZ, q.Z)
				end
				table.insert(out, b)
			end
		end
		return out
	end

	T.test("districts: the package builds every piece as a model under Lobby.Districts", function()
		local _, pkg = districts()
		T.truthy(pkg, "Map.Emberfall.Lobby.Districts exists")
		for _, piece in LobbyLayout.ofPackage("Districts") do
			local m = pkg:FindFirstChild(piece.Id)
			T.truthy(m and m:IsA("Model"), "piece model " .. piece.Id)
		end
		-- the legacy pieces it replaces are gone
		local map = districts()
		for _, name in { "TradingPost", "ToolSmithy" } do
			T.falsy(map.Emberfall:FindFirstChild(name), "legacy " .. name .. " replaced")
		end
	end)

	T.test("districts: gameplay hooks exist once with the right shape", function()
		local map, pkg = districts()
		local function one(tag: string)
			local list = tagged(map, tag)
			T.eq(#list, 1, "exactly one " .. tag)
			T.truthy(list[1]:IsDescendantOf(pkg), tag .. " is built by Districts")
			return list[1]
		end
		local function inside(inst, pieceId: string)
			T.truthy(inst:IsDescendantOf(pkg[pieceId]), inst.Name .. " sits in " .. pieceId)
		end

		local shop = one("ShopCounter")
		T.truthy(shop:IsA("BasePart"), "ShopCounter is a part")
		inside(shop, "Shop")

		local sell = one("SellCounter")
		T.truthy(sell:IsA("BasePart"), "SellCounter is a part")
		inside(sell, "ShopFront")

		local bin = one("SellBin")
		T.truthy(bin:IsA("Model"), "SellBin is a model")
		inside(bin, "ShopFront")
		local intake = bin:FindFirstChild("Intake")
		T.truthy(intake and intake:IsA("BasePart"), "SellBin has a child part Intake")
		T.eq(intake.Transparency, 1, "Intake is invisible")
		T.falsy(intake.CanCollide, "Intake does not collide")
		T.falsy(intake.CanTouch, "Intake does not touch")
		T.falsy(intake.CanQuery, "Intake is not queried")
		for _, axis in { "X", "Y", "Z" } do
			local v = intake.Size[axis]
			T.truthy(v >= 4.5 and v <= 9, "Intake size " .. axis .. " ~8x5x6")
		end

		local upgrade = one("UpgradeCounter")
		T.truthy(upgrade:IsA("BasePart"), "UpgradeCounter is a part")
		inside(upgrade, "Upgrades")

		local chest = one("EmberChest")
		T.truthy(chest:IsA("Model") and chest.PrimaryPart and chest.PrimaryPart.Name == "Chest", "EmberChest model, PrimaryPart Chest")
		T.truthy(chest:FindFirstAncestor("SpinWheel"), "EmberChest sits on the SpinWheel")
		T.truthy(
			chest.PrimaryPart:FindFirstChildWhichIsA("PointLight", true) or chest:FindFirstChildWhichIsA("PointLight", true),
			"chest glows"
		)

		local guild = one("GuildBoard")
		T.truthy(guild:IsA("Model") and guild.PrimaryPart and guild.PrimaryPart.Name == "Board", "GuildBoard model, PrimaryPart Board")

		local codex = one("OreCodex")
		T.truthy(codex:IsA("Model") and codex.PrimaryPart, "OreCodex terminal model with a PrimaryPart")
		inside(codex, "RockScanner")

		local dig = one("FossilDig")
		T.truthy(dig:IsA("Model") and dig.PrimaryPart, "FossilDig model with a PrimaryPart")

		local capsules = one("CapsuleStall")
		T.truthy(capsules:IsA("Model") and capsules.PrimaryPart, "CapsuleStall model with a PrimaryPart")

		local enchant = one("EnchantCounter")
		T.truthy(enchant:IsA("BasePart"), "EnchantCounter is a part")
		inside(enchant, "EnchantShop")

		T.truthy(pkg.ShopFront:FindFirstChild("Tobin"), "Tobin the Miner stands at the Sell stall")
	end)

	T.test("districts: the SPIN & WIN wheel turns around its axle", function()
		local _, pkg = districts()
		local wheel = pkg.SpinWheel:FindFirstChild("Wheel")
		T.truthy(wheel and wheel:IsA("Model"), "SpinWheel has a Wheel sub-model")
		T.truthy(hasTag(wheel, "Spin"), "Wheel is tagged Spin")
		T.truthy(wheel.PrimaryPart, "Wheel has a PrimaryPart (hub)")
		T.eq(wheel.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, "Wheel streams atomically")
		local speed = wheel:GetAttribute("SpinSpeed")
		T.truthy(type(speed) == "number" and speed > 0, "Wheel SpinSpeed > 0")
		T.eq(wheel:GetAttribute("BobHeight"), 0, "Wheel does not bob")
		local frame = LobbyLayout.frame(LobbyLayout.get("SpinWheel"))
		local axle = wheel.PrimaryPart.CFrame.UpVector
		T.truthy(math.abs(axle:Dot(frame.LookVector)) > 0.999, "hub Y axis = the axle (facing the plaza)")
	end)

	T.test("districts: four leaderboards in an arc face the Hall of Fame's front", function()
		local map, pkg = districts()
		local boards = tagged(map, "Leaderboard")
		T.eq(#boards, 4, "four Leaderboard parts")
		-- (round 2: the hall turned toward the koi pond lane and the hero camera;
		-- its boards face the point 30 studs in front of it, the arc's center)
		local hall = LobbyLayout.get("HallOfFame")
		local spawn = hall.Center + hall.Facing.Unit * 30
		for i = 1, 4 do
			local board = pkg.HallOfFame:FindFirstChild("Board" .. i)
			T.truthy(board and board:IsA("BasePart"), "Board" .. i .. " is a part")
			T.truthy(hasTag(board, "Leaderboard"), "Board" .. i .. " tagged Leaderboard")
			T.eq(board:GetAttribute("Board"), i, "Board" .. i .. " attribute")
			T.truthy(board.Size.X >= 4 and board.Size.Y >= 5, "Board" .. i .. " has a big face")
			local at = board.CFrame.Position
			local toSpawn = Vector3.new(spawn.X - at.X, 0, spawn.Z - at.Z).Unit
			T.truthy(board.CFrame.LookVector:Dot(toSpawn) > 0.95, "Board" .. i .. " Front face looks at the arc's center")
		end
	end)

	-- The first part of `root` outside `piece`'s footprint and height (spinning
	-- models are checked over their whole sweep), or nil.
	local function outside(root, piece): string?
		local frame = LobbyLayout.frame(piece)
		local hx, hz, h = piece.Size.X / 2 + TOLERANCE, piece.Size.Z / 2 + TOLERANCE, piece.Size.Y + TOLERANCE
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				local points = corners(d)
				local spinner = spinnerOf(d, root)
				if spinner then
					-- check the whole sweep around the pivot's Y axis (plus the bob)
					local pivot = spinner.PrimaryPart.CFrame
					local bob = spinner:GetAttribute("BobHeight") or 0.4
					local swept = {}
					for _, p in points do
						local localP = pivot:PointToObjectSpace(p)
						for k = 0, 15 do
							local a = k * math.pi / 8
							for _, dy in { -bob, bob } do
								table.insert(swept, pivot * (CFrame.Angles(0, a, 0) * localP + Vector3.new(0, dy, 0)))
							end
						end
					end
					points = swept
				end
				for _, p in points do
					local q = frame:PointToObjectSpace(p)
					if math.abs(q.X) > hx or math.abs(q.Z) > hz or q.Y < -0.3 or q.Y > h then
						return `{d:GetFullName()} at {q}`
					end
				end
			end
		end
		return nil
	end

	T.test("districts: every part stays inside its piece footprint and height", function()
		local _, pkg = districts()
		for _, piece in LobbyLayout.ofPackage("Districts") do
			T.falsy(outside(pkg[piece.Id], piece), piece.Id .. " part outside its footprint/height")
		end
	end)

	T.test("districts: the SPIN & WIN frame grows with a bigger footprint and stays inside it", function()
		local Wheel = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Wheel")
		local piece = LobbyLayout.get("SpinWheel")
		local size = piece.Size
		local function build(): (any, number)
			local m = roblox.Instance.new("Model")
			Wheel.build(m, Rng.new("Lobby/Districts/wheel"))
			local frame = LobbyLayout.frame(piece)
			local top = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					top = math.max(top, frame:PointToObjectSpace(d.CFrame.Position).Y)
				end
			end
			return m, top
		end
		local ok, err = pcall(function()
			-- the layout's 18 x 26 x 10 piece and the requested 26 x 36 x 12 one
			piece.Size = Vector3.new(18, 26, 10)
			local base, baseTop = build()
			T.falsy(outside(base.SpinWheel, piece), "the 18 wide wheel stays inside its footprint")
			piece.Size = Vector3.new(26, 36, 12)
			local big, bigTop = build()
			T.falsy(outside(big.SpinWheel, piece), "the bigger wheel stays inside its footprint")
			T.truthy(bigTop > baseTop * 1.3, `the wheel grows with the footprint ({baseTop} -> {bigTop})`)
			T.truthy(big.SpinWheel:FindFirstChild("EmberChest", true), "the bigger wheel keeps its EmberChest")
		end)
		piece.Size = size
		if not ok then
			error(err, 0)
		end
	end)

	T.test("districts: armored housings make the SPIN & WIN frame much wider than its disc", function()
		local _, pkg = districts()
		local piece = LobbyLayout.get("SpinWheel")
		local frame = LobbyLayout.frame(piece)
		local wheel = pkg.SpinWheel.Wheel
		local axle = wheel.PrimaryPart.CFrame.Position
		-- the disc: the farthest point of the turning wheel from the axle
		local disc = 0
		for _, d in wheel:GetDescendants() do
			if d:IsA("BasePart") then
				for _, p in corners(d) do
					local q = frame:PointToObjectSpace(p) - frame:PointToObjectSpace(axle)
					disc = math.max(disc, math.sqrt(q.X * q.X + q.Y * q.Y))
				end
			end
		end
		-- the frame beside the disc: static parts at the axle's height
		local axleY = frame:PointToObjectSpace(axle).Y
		local half = 0
		for _, d in pkg.SpinWheel:GetDescendants() do
			if d:IsA("BasePart") and not d:IsDescendantOf(wheel) then
				local q = frame:PointToObjectSpace(d.CFrame.Position)
				if math.abs(q.Y - axleY) < disc * 0.35 then
					for _, p in corners(d) do
						half = math.max(half, math.abs(frame:PointToObjectSpace(p).X))
					end
				end
			end
		end
		T.truthy(disc > 4, `the wheel has a disc ({disc})`)
		T.truthy(half >= disc * 1.35, `the frame (half width {half}) is about 1.5 times the disc (radius {disc})`)
	end)

	-- (lobby fix round 3) the giant wheel stands free: from the spawn camera
	-- (lobby_spawn, 0, 13, 58) no ray to the disc's rim passes through the
	-- SHOP (its built parts' box in the SHOP's frame)
	T.test("districts: from the spawn camera the SPIN & WIN disc clears the SHOP", function()
		local _, pkg = districts()
		local shopFrame = LobbyLayout.frame(LobbyLayout.get("Shop"))
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, d in pkg.Shop:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.9 then
				for _, p in corners(d) do
					local q = shopFrame:PointToObjectSpace(p)
					lo = Vector3.new(math.min(lo.X, q.X), math.min(lo.Y, q.Y), math.min(lo.Z, q.Z))
					hi = Vector3.new(math.max(hi.X, q.X), math.max(hi.Y, q.Y), math.max(hi.Z, q.Z))
				end
			end
		end
		local function hitsShop(a: any, b: any): boolean
			local p0 = shopFrame:PointToObjectSpace(a)
			local p1 = shopFrame:PointToObjectSpace(b)
			local t0, t1 = 0, 1
			for _, axis in { "X", "Y", "Z" } do
				local d = p1[axis] - p0[axis]
				if math.abs(d) < 1e-9 then
					if p0[axis] < lo[axis] or p0[axis] > hi[axis] then
						return false
					end
				else
					local u0, u1 = (lo[axis] - p0[axis]) / d, (hi[axis] - p0[axis]) / d
					if u0 > u1 then
						u0, u1 = u1, u0
					end
					t0, t1 = math.max(t0, u0), math.min(t1, u1)
					if t0 > t1 then
						return false
					end
				end
			end
			return true
		end
		local piece = LobbyLayout.get("SpinWheel")
		local frame = LobbyLayout.frame(piece)
		local wheel = pkg.SpinWheel.Wheel
		local axle = wheel.PrimaryPart.CFrame.Position
		local disc = 0
		for _, d in wheel:GetDescendants() do
			if d:IsA("BasePart") then
				for _, p in corners(d) do
					local q = frame:PointToObjectSpace(p) - frame:PointToObjectSpace(axle)
					disc = math.max(disc, math.sqrt(q.X * q.X + q.Y * q.Y))
				end
			end
		end
		T.truthy(disc > 10, `a giant disc ({disc})`)
		local cam = Vector3.new(0, 13, 58)
		for k = 0, 23 do
			local a = k * math.pi / 12
			local p = axle + frame.RightVector * (disc * 0.97 * math.cos(a)) + frame.UpVector * (disc * 0.97 * math.sin(a))
			T.falsy(hitsShop(cam, p), `the SHOP hides the disc's rim at {math.deg(a)} degrees from the spawn camera`)
		end
	end)

	T.test("districts: the SHOP and UPGRADES modules get a second display bay when wider", function()
		local Stalls = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Stalls")
		local function showcases(m): number
			local n = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Showcase" then
					n += 1
				end
			end
			return n
		end
		local function bayCases(m): number
			local n = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "BayCase" then
					n += 1
				end
			end
			return n
		end
		local pieces = { LobbyLayout.get("Shop"), LobbyLayout.get("Upgrades") }
		local sizes = { pieces[1].Size, pieces[2].Size }
		local ok, err = pcall(function()
			for _, width in { 20, 28 } do
				for _, piece in pieces do
					piece.Size = Vector3.new(width, 20, 14)
				end
				local m = roblox.Instance.new("Model")
				Stalls.build(m, Rng.new("Lobby/Districts/stalls"))
				local want = if width >= 27 then 4 else 2
				for _, piece in pieces do
					T.falsy(outside(m[piece.Id], piece), `{piece.Id} ({width} wide) stays inside its footprint`)
					T.eq(showcases(m[piece.Id]), want, `{piece.Id} ({width} wide) porch showcases`)
					T.eq(bayCases(m[piece.Id]), want, `{piece.Id} ({width} wide) lit display bays with a glass case`)
				end
			end
		end)
		for i, piece in pieces do
			piece.Size = sizes[i]
		end
		if not ok then
			error(err, 0)
		end
	end)

	T.test("districts: the Hall of Fame boards show a placeholder table until the leaderboards fill them", function()
		local _, pkg = districts()
		for i = 1, 4 do
			local board = pkg.HallOfFame:FindFirstChild("Board" .. i)
			local ph = board and board:FindFirstChild("Placeholder")
			T.truthy(ph and ph:IsA("Model"), "Board" .. i .. " has a Placeholder model")
			-- (round 3: the rank rows are SurfaceGui labels, no parts)
			local rows = 0
			for _, d in ph:GetDescendants() do
				if d:IsA("TextLabel") then
					rows += 1
				end
			end
			T.truthy(rows >= 5, "Board" .. i .. " placeholder has rank rows")
		end
	end)

	T.test("districts: Tobin's Sell stall stays low and off the SHOP's door lane, Tobin clear of his cart", function()
		local _, pkg = districts()
		local frame = LobbyLayout.frame(LobbyLayout.get("ShopFront"))
		for _, d in pkg.ShopFront:GetDescendants() do
			-- (round 2: the big SELL sign stands high on its own arch, model SellSign)
			local sign = pkg.ShopFront:FindFirstChild("SellSign")
			if d:IsA("BasePart") and not d:IsDescendantOf(pkg.ShopFront.Tobin) and not (sign and d:IsDescendantOf(sign)) and d.Transparency < 1 then
				local top = -math.huge
				for _, p in corners(d) do
					top = math.max(top, frame:PointToObjectSpace(p).Y)
				end
				T.truthy(top <= 5.0, `{d:GetFullName()} rises to {top} (keep the stall under 5 studs)`)
			end
		end
		-- the stall keeps the SHOP's 6-stud door lane open
		local shop = LobbyLayout.get("Shop")
		local shopFrame = LobbyLayout.frame(shop)
		for _, d in pkg.ShopFront:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				for _, p in corners(d) do
					T.truthy(math.abs(shopFrame:PointToObjectSpace(p).X) >= 3, `{d:GetFullName()} stands in the SHOP's door lane`)
				end
			end
		end
		-- Tobin stands a stud clear of his cart
		local cart = nil
		for _, d in pkg.ShopFront:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "SellCounter" then
				cart = d
			end
		end
		local gap = math.huge
		for _, d in pkg.ShopFront.Tobin:GetDescendants() do
			if d:IsA("BasePart") then
				for _, p in corners(d) do
					local q = cart.CFrame:PointToObjectSpace(p)
					local dx = math.max(math.abs(q.X) - cart.Size.X / 2, 0)
					local dz = math.max(math.abs(q.Z) - cart.Size.Z / 2, 0)
					gap = math.min(gap, math.sqrt(dx * dx + dz * dz))
				end
			end
		end
		T.truthy(gap >= 0.9, `Tobin stands {gap} studs from his counter`)
	end)

	T.test("districts: a lane at least 4 studs wide runs clear from the plaza to the SHOP and UPGRADES counters", function()
		local map = districts()
		for _, pair in { { "Shop", "ShopCounter" }, { "Upgrades", "UpgradeCounter" } } do
			local id, counterName = pair[1], pair[2]
			local piece = LobbyLayout.get(id)
			local frame = LobbyLayout.frame(piece)
			local counter = map:FindFirstChild(counterName, true)
			local counterFront = frame:PointToObjectSpace(counter.CFrame.Position).Z - counter.Size.Z / 2
			-- from the plaza rim (the module's front is about 44 studs from the plaza
			-- center: the lane starts 9 studs further out) to the counter
			local laneFront = -piece.Size.Z / 2 - 9
			for _, b in solidBoxes(map.Emberfall, frame) do
				local blocked = b.MaxX > -2
					and b.MinX < 2
					and b.MaxZ > laneFront
					and b.MinZ < counterFront - 0.3
					and b.MaxY > 0.9
					and b.MinY < 6
				T.falsy(blocked, `{b.Name} blocks the lane to the {id} counter`)
			end
		end
	end)

	T.test("districts: the SPIN & WIN stairs climb in small steps up to the EmberChest", function()
		local _, pkg = districts()
		local piece = LobbyLayout.get("SpinWheel")
		local frame = LobbyLayout.frame(piece)
		local boxes = solidBoxes(pkg.SpinWheel, frame)
		local chestFront = math.huge
		for _, b in solidBoxes(pkg.SpinWheel.EmberChest, frame) do
			chestFront = math.min(chestFront, b.MinZ)
		end
		T.truthy(chestFront < piece.Size.Z / 2, "the EmberChest stands on the platform")
		-- walk the stairs' center line from the ground in front up to the chest
		local floor = 0
		local z = -piece.Size.Z / 2 - 0.5
		while z < chestFront - 0.3 do
			local top = 0
			for _, b in boxes do
				if b.MinX <= 0 and b.MaxX >= 0 and b.MinZ <= z and b.MaxZ >= z and b.MinY < floor + 1.1 then
					top = math.max(top, b.MaxY)
				end
			end
			T.truthy(top - floor <= 1.05, `the stairs rise {top - floor} at z {z}`)
			floor = top
			for _, b in boxes do
				local overhead = b.MinX < 1 and b.MaxX > -1 and b.MinZ < z + 0.4 and b.MaxZ > z - 0.4
				T.falsy(overhead and b.MinY > floor + 0.05 and b.MinY < floor + 5, `{b.Name} blocks the stairs at z {z}`)
			end
			z += 0.25
		end
		T.truthy(floor >= 2.0, "the stairs reach the platform in front of the chest")
	end)

	T.test("districts: the SHOP and UPGRADES doors stay open up to the counters", function()
		local _, pkg = districts()
		for _, pair in { { "Shop", "ShopCounter" }, { "Upgrades", "UpgradeCounter" } } do
			local id, counterName = pair[1], pair[2]
			local piece = LobbyLayout.get(id)
			local frame = LobbyLayout.frame(piece)
			local counter = pkg[id]:FindFirstChild(counterName)
			T.truthy(counter and counter:IsA("BasePart"), `{id} counter part`)
			local counterFront = frame:PointToObjectSpace(counter.CFrame.Position).Z - counter.Size.Z / 2
			T.truthy(counterFront > -piece.Size.Z / 2 + 4, `{id} counter sits inside the module`)
			for _, b in solidBoxes(pkg[id], frame) do
				local blocked = b.MaxX > -2.2
					and b.MinX < 2.2
					and b.MaxZ > -piece.Size.Z / 2
					and b.MinZ < counterFront - 0.3
					and b.MaxY > 0.9
					and b.MinY < 6
				T.falsy(blocked, `{b.Name} blocks the way to the {id} counter`)
			end
		end
	end)

	T.test("districts: the big signs keep their words, the capsule stall its odds board", function()
		local _, pkg = districts()
		local want = {
			Shop = "SHOP",
			Upgrades = "UPGRADES",
			SpinWheel = "SPIN & WIN",
			CapsuleStall = "CAPSULES",
			ShopFront = "SELL",
			EnchantShop = "ENCHANT",
			HallOfFame = "HALL OF FAME",
			RockScanner = "ROCK SCANNER",
			FossilDig = "FOSSIL DIG",
			GuildBoard = "FORGEKEEPERS' GUILD",
		}
		for id, text in want do
			local found = false
			for _, d in pkg[id]:GetDescendants() do
				if d:IsA("TextLabel") and string.gsub(d.Text, "\n", " ") == text then
					found = true
					break
				end
			end
			T.truthy(found, `{id} shows "{text}"`)
		end
		local odds = pkg.CapsuleStall:FindFirstChild("OddsBoard", true)
		T.truthy(odds and odds:IsA("BasePart"), "CapsuleStall has an OddsBoard part")
	end)

	T.test("districts: small details cast no shadow", function()
		local _, pkg = districts()
		for _, d in pkg:GetDescendants() do
			if d:IsA("BasePart") and math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 0.5 then
				T.falsy(d.CastShadow, d:GetFullName() .. " (small) casts a shadow")
			end
		end
	end)

	T.test("districts: inside the part and light budget, lights without shadows", function()
		local _, pkg = districts()
		local budget = LobbyLayout.Budget.Packages.Districts
		local parts, lights = 0, 0
		for _, d in pkg:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.truthy(d.Anchored, d:GetFullName() .. " is anchored")
				if d.Material == roblox.Enum.Material.Neon then
					T.falsy(d.CastShadow, d:GetFullName() .. " neon casts no shadow")
				end
			elseif d:IsA("PointLight") or d:IsA("SpotLight") then
				lights += 1
				T.falsy(d.Shadows, "lights have shadows off")
			end
		end
		T.lt(parts, budget.Parts + 1, "Districts parts")
		T.lt(lights, budget.Lights + 1, "Districts lights")
		T.truthy(parts > 600, "Districts is dressed (parts)")
	end)

	T.test("districts: the build is deterministic", function()
		local Districts = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts")
		T.truthy(type(Districts.build) == "function", "build() exported")
		for _, name in { "tradingPost", "toolSmithy", "emberChest", "guildBoard" } do
			T.truthy(table.find(Districts.Replaces, name), "Replaces " .. name)
		end
		local function snapshot(): { string }
			local m = roblox.Instance.new("Model")
			Districts.build(m, Rng.new("Lobby/Districts/test"))
			local out = {}
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					table.insert(out, string.format("%s %.3f %.3f %.3f", d.Name, p.X, p.Y, p.Z))
				end
			end
			return out
		end
		local a, b = snapshot(), snapshot()
		T.eq(#a, #b, "same part count")
		for i = 1, #a do
			if a[i] ~= b[i] then
				T.eq(b[i], a[i], "part " .. i)
				break
			end
		end
	end)
end
