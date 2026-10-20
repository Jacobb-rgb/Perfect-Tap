--[[
	THE GREAT FORGE's blaster gallery (src/server/World/Lobby/Plaza/
	BlasterGallery): every level 1-10 on show with the real gun in its case
	ore's look and the right plates, LV 11 "?" COMING SOON, within its part
	and light budget (~330 parts, one light), mobile-safe (no shadows,
	nothing collides or is raycast), inside the hall and clear of the
	walkway and the tool rack.
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local CFrame = Loader.CFrame
	local Vector3 = roblox.Vector3
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local Gallery = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.BlasterGallery")
	local GreatForge = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.GreatForge")

	local frame = CFrame.new(3, 0, -40) * CFrame.Angles(0, 0.4, 0) -- any frame: the checks are in its local space
	local holder = roblox.Instance.new("Model")
	local built = Gallery.build(holder, frame)

	local function parts(root: any): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function plateText(piece: any, name: string): string
		local plate = piece:FindFirstChild(name)
		local gui = plate and plate:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		return if label then label.Text else ""
	end

	T.test("BlasterGallery: levels 1-10 on show, with their guns and plates", function()
		for level = 1, BlasterData.MaxLevel do
			local piece = built:FindFirstChild("Plaque" .. level)
			T.truthy(piece, "plaque " .. level)
			local ore = Gallery.oreOf(level)
			T.eq(ore, BlasterData.vaultOre(level), "level " .. level .. " in its case ore")
			local gun = piece:FindFirstChild("Blaster" .. level)
			T.truthy(gun, "gun " .. level)
			T.eq(gun:GetAttribute("OreId"), ore, "gun ore")
			-- the real gun at display detail: the tiniest solid bevels and the invisible holders left out
			local full = #parts(BlasterBuilder.build(level, ore))
			T.le(#parts(gun), full, "never more than the real gun")
			T.truthy(#parts(gun) >= full * 0.6, "most of the real gun")
			local solid, lit = 0, 0
			for _, p in parts(gun) do
				T.truthy(p.Transparency < 0.99, "no invisible parts on show")
				if p.Material ~= roblox.Enum.Material.Neon then
					solid += 1
					local _, _, value = p.Color:ToHSV()
					if value >= Gallery.DisplayMinValue - 1e-3 then
						lit += 1
					end
				end
			end
			-- the solid parts read as colored shapes against the dark plaques (not black silhouettes)
			T.eq(lit, solid, "level " .. level .. ": every solid part bright enough on show")
			T.eq(plateText(piece, "LevelPlate"), "LV " .. level, "level plate")
			T.eq(plateText(piece, "NamePlate"), string.upper(BlasterData.displayName(level, ore)), "name plate")
		end
		local soon = built:FindFirstChild("ComingSoon")
		T.truthy(soon, "LV 11")
		T.eq(plateText(soon, "LevelPlate"), "LV 11", "LV 11 plate")
		T.eq(plateText(soon, "NamePlate"), "COMING SOON", "coming soon")
		T.eq(plateText(soon, "Question"), "?", "the question mark")
		for _, p in parts(soon:FindFirstChild("Silhouette")) do
			T.eq(p.Color, Gallery.Silhouette, "a dark silhouette")
		end
	end)

	T.test("BlasterGallery: budget and mobile finish", function()
		local list = parts(built)
		T.le(#list, 540, "parts (the Kenney-shape guns at display detail)")
		local lights = 0
		for _, d in built:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
			end
		end
		T.eq(lights, 1, "one soft light (LV 11)")
		for _, p in list do
			T.falsy(p.CastShadow, p.Name .. " casts no shadow")
			T.falsy(p.CanCollide, p.Name .. " doesn't collide (the hall is a showroom)")
			T.falsy(p.CanQuery, p.Name .. " isn't raycast")
			T.truthy(p.Anchored, p.Name .. " anchored")
		end
	end)

	T.test("BlasterGallery: inside the hall, clear of the walkway and the tool rack", function()
		local floor = Gallery.Floor
		local doorTop = floor + 7.7 -- GreatForge.DoorTop
		T.eq(floor, GreatForge.PlinthTop, "the hall floor")
		T.eq(doorTop, GreatForge.DoorTop, "the door top")
		for _, p in parts(built) do
			local l = frame:PointToObjectSpace(p.CFrame.Position)
			T.truthy(math.abs(l.X) <= 7 and math.abs(l.X) >= 4.4, p.Name .. " on a side wall, the middle stays free (x " .. l.X .. ")")
			T.truthy(l.Y > floor + 0.3 and l.Y < doorTop - 0.6, p.Name .. " between the floor and the beams")
			T.truthy(l.Z > -9 and l.Z < 6, p.Name .. " inside the hall, in front of the furnace")
		end
		-- the tool rack's slot holds no plaque
		local rack = Gallery.toolRackSpot()
		for _, spot in Gallery.spots() do
			local p = spot.Cf.Position
			T.truthy((Vector3.new(p.X, p.Y, p.Z) - rack).Magnitude > 3, "plaque " .. spot.Level .. " clear of the tool rack")
		end
		T.eq(#Gallery.spots(), BlasterData.MaxLevel + 1, "ten plaques and LV 11")
	end)

	T.test("BlasterGallery: the Great Forge builds it (unless it is the open passage)", function()
		local m = roblox.Instance.new("Model")
		GreatForge.build(m, Loader.requirePath("ReplicatedStorage.Shared.Util.Rng").new("Lobby/Plaza"))
		local gallery = m:FindFirstChild("BlasterGallery", true)
		if GreatForge.Passage then
			-- (owner 2026-10-20) the forge is an open passage now: no hall, no gallery
			T.eq(gallery, nil, "no gallery in the passage")
			return
		end
		T.truthy(gallery, "in the forge")
		T.eq(#parts(gallery), #parts(built), "the same gallery")
	end)
end
