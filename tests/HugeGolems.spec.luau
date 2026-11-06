-- The HUGE golems (owner 2026-10-30, his Sky egg concept): the Sky Titan and the Cloud Colossus wear their costumes
-- (Builders/LimitedGear/Sky: TitanArmor, CloudStorm) within GolemConfig.HugeMaxParts, stand on their base with the
-- right RootHeight / Height / Hover and tower over the other golems, keep their one light only off the followers,
-- run their limbs in sane groups (wings and floating rocks on the body, the halo and the storm ring on the head, the
-- staff in the right hand). As followers (Util/GolemFit) they walk beside and further back, never overlapping their
-- player or the other followers and never straight behind the player (the default camera keeps the player in view),
-- while ordinary golems keep their old slots; the inventory's 3D portrait frames them whole as they turn.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs")
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local GolemFit = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.GolemFit")
	local Gait = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.GolemGait")

	local HUGE = { "SkyTitan", "CloudColossus" }
	local FOLLOWER = 0.85 -- GolemController.FollowerSize
	-- a follower's size: a HUGE golem follows smaller than its reveal (GolemFit.HugeFollowerSize)
	local function followerSize(kind: string): number
		return if GolemConfig.ById[kind].Huge then GolemFit.HugeFollowerSize else FOLLOWER
	end
	local PLAYER_HEIGHT = 5.2 -- studs: a Roblox avatar
	local CAMERA_ZOOM = 12.5 -- studs: Roblox's default camera distance behind the player

	local function parts(model: any): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function count(model: any, prefix: string, class: string?): number
		local n = 0
		for _, p in parts(model) do
			if string.sub(p.Name, 1, #prefix) == prefix and (class == nil or p:IsA(class)) then
				n += 1
			end
		end
		return n
	end

	local function ofClass(model: any, class: string): { any }
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA(class) then
				table.insert(out, d)
			end
		end
		return out
	end

	-- the world-space Y extent of a part (its box, rotated)
	local function yExtent(part: any): (number, number)
		local cf = part.CFrame
		local h = part.Size / 2
		local up = math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z
		return cf.Position.Y - up, cf.Position.Y + up
	end

	T.test("HugeGolems: both are HUGE Sky golems that wear their costumes within HugeMaxParts", function()
		for _, kind in HUGE do
			local golem = GolemConfig.ById[kind]
			T.truthy(golem and golem.Huge == true, kind .. " is HUGE")
			T.eq(golem.Edition, "Sky", kind .. " wears a Sky costume")
			T.eq(GolemBuilder.budget(kind), GolemConfig.HugeMaxParts, kind .. " budget")
			local model = GolemBuilder.build(kind)
			local n = GolemBuilder.partCount(model)
			T.le(n, GolemConfig.HugeMaxParts, kind .. " parts")
			T.truthy(n > GolemConfig.LimitedMaxParts.Mythic, `{kind}: richer than a Mythic ({n} parts)`)
			local king = GolemBuilder.partCount(GolemBuilder.build("AetherKing"))
			T.truthy(n >= king * 1.5, `{kind}: clearly more detailed than the Aether King ({n} vs {king} parts)`)
			T.eq(model.PrimaryPart.Name, "Body", kind .. " PrimaryPart")
			T.eq(model:FindFirstChild("Brow"), nil, kind .. ": a closed helm, no stone brow")
			T.truthy(model:FindFirstChild("Helm") and model:FindFirstChild("Aura"), kind .. ": its helm and its aura")
			for _, p in parts(model) do
				T.truthy(not p.CanCollide and not p.CanTouch and not p.CanQuery, kind .. " " .. p.Name .. " is decor")
			end
		end
		local titan = GolemBuilder.build("SkyTitan")
		T.eq(count(titan, "Halo", "Part"), 16, "the Sky Titan's great golden halo")
		T.truthy(count(titan, "Wing", "WedgePart") >= 16, "its crystal wings of ice shards")
		T.truthy(count(titan, "CrownPoint") == 7 and titan:FindFirstChild("CrownBand"), "its crowned helm")
		T.truthy(titan:FindFirstChild("Staff") and titan:FindFirstChild("StaffGem"), "its gold staff with the ice crystal")
		T.eq(titan:FindFirstChild("StaffGem").Material, roblox.Enum.Material.Neon, "the staff's crystal glows")
		T.truthy(titan:FindFirstChild("Pauldron1_1") and titan:FindFirstChild("Pauldron2_1"), "its gold pauldrons")
		local colossus = GolemBuilder.build("CloudColossus")
		T.eq(count(colossus, "StormRing", "Part"), 14, "the Cloud Colossus's storm ring")
		T.truthy(count(colossus, "Pauldron") >= 10, "its huge cloud shoulders")
		T.truthy(count(colossus, "BoulderRock") >= 8, "rocks floating round it")
		T.truthy(count(colossus, "Bolt") + count(colossus, "ArmBolt") + count(colossus, "LegBolt") >= 8, "its lightning veins")
		T.truthy(count(colossus, "Spike", "WedgePart") >= 6, "its crown of rock shards")
		-- (owner 2026-11-06: more lightning on both, the clouds on the Titan too)
		T.truthy(count(colossus, "BodyStorm") >= 8 and count(colossus, "BoulderArc") >= 8, "the Colossus's great bolts and arcs")
		T.truthy(count(titan, "BodyStorm") >= 7 and count(titan, "Pauldron2_StaffBolt") >= 4, "the Titan's lightning")
		T.truthy(count(titan, "BodyCloud") + count(titan, "BodyMist") + count(titan, "HaloCloud") >= 12, "the Titan's clouds")
		T.truthy(count(titan, "Pauldron1_Cloud") >= 4 and count(titan, "Pauldron2_Wrap") >= 3, "clouds on its shoulders and arms")
	end)

	T.test("HugeGolems: on their base, RootHeight, Height and Hover right; they tower over the other golems", function()
		for _, size in { 1, FOLLOWER, GolemFit.HugeFollowerSize } do
			for _, kind in HUGE do
				local base = CFrame.new(10, 4, -6) * CFrame.Angles(0, 1.1, 0)
				local model = GolemBuilder.build(kind, base, { Size = size })
				local lowest, highest = math.huge, -math.huge
				for _, p in parts(model) do
					local lo, hi = yExtent(p)
					lowest = math.min(lowest, lo)
					highest = math.max(highest, hi)
				end
				T.near(lowest, 4, 0.02, `{kind} x{size}: on its base (the aura under its floating feet)`)
				local height = model:GetAttribute("Height")
				T.near(highest, 4 + height, 0.05, `{kind} x{size}: Height is its real top (the halo / the storm ring)`)
				local scale = GolemConfig.ById[kind].Scale * size
				T.near(model:GetAttribute("Hover"), GolemBuilder.Hover * scale, 1e-4, kind .. " Hover")
				local body = base:PointToObjectSpace(model.PrimaryPart.CFrame.Position)
				T.near(body.Y, model:GetAttribute("RootHeight"), 1e-3, kind .. " RootHeight")
			end
		end
		-- the reveal (its own size): two to three Aether Kings tall
		local king = GolemBuilder.build("AetherKing"):GetAttribute("Height")
		local tallest = 0 -- the tallest ordinary follower
		for _, golem in GolemConfig.List do
			if not golem.Huge then
				tallest = math.max(tallest, GolemBuilder.build(golem.Id, nil, { Size = FOLLOWER }):GetAttribute("Height"))
			end
		end
		for _, kind in HUGE do
			local height = GolemBuilder.build(kind):GetAttribute("Height")
			T.truthy(height / king >= 2 and height / king <= 3.2, `{kind}: two to three Aether Kings tall ({height} vs {king})`)
			-- as a follower: its helm top about 1.2 players tall, still far bigger than any other follower
			local follower = GolemBuilder.build(kind, nil, { Size = GolemFit.HugeFollowerSize })
			local _, helmTop = yExtent(follower:FindFirstChild("Helm"))
			T.truthy(
				helmTop >= PLAYER_HEIGHT * 1.15 and helmTop <= PLAYER_HEIGHT * 1.25,
				`{kind} follower: helm top about 1.2 players tall ({helmTop})`
			)
			local followerHeight = follower:GetAttribute("Height")
			T.truthy(
				followerHeight >= tallest * 1.5,
				`{kind} follower: clearly bigger than every other follower ({followerHeight} vs {tallest})`
			)
		end
	end)

	T.test("HugeGolems: followers carry no PointLight (the reveal keeps one), one slow emitter, welded to the Body", function()
		for _, kind in HUGE do
			local shown = GolemBuilder.build(kind)
			local lights = ofClass(shown, "PointLight")
			T.eq(#lights, 1, kind .. ": its one light in the reveal and the pictures")
			T.falsy(lights[1].Shadows, kind .. ": a light without shadows")
			local start = CFrame.new(3, 0, -2) * CFrame.Angles(0, 0.4, 0)
			local follower = GolemBuilder.build(kind, start, { Welded = true, Size = followerSize(kind) })
			T.eq(#ofClass(follower, "PointLight"), 0, kind .. " follower: no PointLight")
			local emitters = ofClass(follower, "ParticleEmitter")
			T.eq(#emitters, 1, kind .. ": one emitter")
			T.le(emitters[1].Rate, 8, kind .. ": a slow one")
			local body = follower.PrimaryPart
			T.truthy(body.Anchored, kind .. ": the Body is anchored")
			for _, p in parts(follower) do
				if p ~= body then
					T.falsy(p.Anchored, kind .. " " .. p.Name .. " unanchored")
					local weld = p:FindFirstChildOfClass("WeldConstraint")
					T.truthy(weld and weld.Part0 == body and weld.Part1 == p, kind .. " " .. p.Name .. " welded to the Body")
				end
			end
		end
	end)

	T.test("HugeGolems: running limbs: wings and floating rocks on the body, halo and storm ring on the head", function()
		for _, kind in HUGE do
			local model =
				GolemBuilder.build(kind, CFrame.new(5, 0, 3) * CFrame.Angles(0, 0.7, 0), { Welded = true, Size = followerSize(kind) })
			local rig = Gait.classify(model)
			T.truthy(rig, kind .. " rig")
			T.near(
				rig.Scale,
				GolemConfig.ById[kind].Scale * followerSize(kind),
				1e-4,
				kind .. ": studs per golem unit (its Body is not resized)"
			)
			local where: { [string]: string } = {}
			for _, key in { "LegL", "LegR", "ArmL", "ArmR", "Head" } do
				for _, p in rig[key].Parts do
					where[p.Name] = key
				end
			end
			for _, p in parts(model) do
				for _, prefix in { "Wing", "BoulderRock", "Core", "Body" } do
					if string.sub(p.Name, 1, #prefix) == prefix then
						T.eq(where[p.Name], nil, kind .. " " .. p.Name .. " stays on the body")
					end
				end
				for _, prefix in { "Halo", "StormRing", "RingCloud", "Crown", "Spike", "Helm" } do
					if string.sub(p.Name, 1, #prefix) == prefix then
						T.eq(where[p.Name], "Head", kind .. " " .. p.Name .. " rides on the head")
					end
				end
				if string.sub(p.Name, 1, 9) == "Pauldron1" then
					T.eq(where[p.Name], "ArmL", kind .. " " .. p.Name .. " on the left shoulder")
				end
			end
		end
		local titan = GolemBuilder.build("SkyTitan", CFrame.new(), { Welded = true, Size = followerSize("SkyTitan") })
		local rig = Gait.classify(titan)
		local inHand = false
		for _, p in rig.ArmR.Parts do
			inHand = inHand or p.Name == "Staff"
		end
		T.truthy(inHand, "the Sky Titan's staff swings with its right arm")
	end)

	-- the followers' sizes as GolemController measures them (its welded models at their start)
	local function sizeOf(kind: string): any
		local start = CFrame.new(2, 0, -1) * CFrame.Angles(0, 0.6, 0)
		local model = GolemBuilder.build(kind, start, { Welded = true, Size = followerSize(kind) })
		return {
			Radius = GolemFit.radius(model, start),
			Low = GolemFit.radius(model, start, GolemFit.PlayerHeight),
			Huge = GolemConfig.ById[kind].Huge == true,
		}
	end

	T.test("GolemFit: the reach of a golem covers all its parts, whichever way it turns (Low: those under a player's head)", function()
		for _, kind in { "PebbleGolem", "AetherKing", "SkyTitan", "CloudColossus" } do
			local start = CFrame.new(4, 1, -3) * CFrame.Angles(0, 0.9, 0)
			local model = GolemBuilder.build(kind, start, { Welded = true, Size = followerSize(kind) })
			local r = GolemFit.radius(model, start)
			local low = GolemFit.radius(model, start, GolemFit.PlayerHeight)
			T.le(low, r, kind .. ": the low reach is part of the whole one")
			for _, p in parts(model) do
				local h = p.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner = start:PointToObjectSpace((p.CFrame * CFrame.new(sx * h.X, sy * h.Y, sz * h.Z)).Position)
							local d = math.sqrt(corner.X ^ 2 + corner.Z ^ 2)
							T.truthy(d <= r + 1e-4, kind .. " " .. p.Name .. " inside its reach")
							if corner.Y < GolemFit.PlayerHeight then
								T.truthy(d <= low + 1e-4, kind .. " " .. p.Name .. " (down at a player's height) inside its low reach")
							end
						end
					end
				end
			end
		end
		local titan, king = sizeOf("SkyTitan"), sizeOf("AetherKing")
		T.truthy(titan.Radius > king.Radius * 1.6, "a huge golem reaches much further (its wings)")
		-- every ordinary golem is no taller than a player: its whole reach is its low reach
		for _, golem in GolemConfig.List do
			if not golem.Huge then
				local height = GolemBuilder.build(golem.Id, nil, { Size = FOLLOWER }):GetAttribute("Height")
				T.le(height, GolemFit.PlayerHeight, golem.Id .. " is no taller than a player")
			end
		end
	end)

	T.test("GolemFit: ordinary golems keep their slots; huge ones walk beside, further back, clear of everyone", function()
		local kinds = { "PebbleGolem", "AetherKing", "SkyTitan", "CloudColossus" }
		local sizes: { [string]: any } = {}
		for _, kind in kinds do
			sizes[kind] = sizeOf(kind)
		end
		-- ordinary golems: the old slots exactly
		for _, combo in { { "PebbleGolem", "AetherKing", "AetherKing" }, { "AetherKing" }, { "PebbleGolem", "PebbleGolem" } } do
			local list = {}
			for slot, kind in combo do
				list[slot] = sizes[kind]
			end
			local out = GolemFit.slots(list)
			for slot in combo do
				T.eq(out[slot], GolemFit.Base[slot], `ordinary golems keep slot {slot}`)
			end
		end
		-- every 1, 2 and 3 golem line-up with huge ones (and holes left by unknown kinds)
		local lineups = {}
		for _, a in kinds do
			table.insert(lineups, { a })
			for _, b in kinds do
				table.insert(lineups, { a, b })
				table.insert(lineups, { [1] = a, [3] = b })
				for _, c in kinds do
					table.insert(lineups, { a, b, c })
				end
			end
		end
		local sideZ = GolemFit.Base[1].Z
		for _, lineup in lineups do
			local list = {}
			local names = {}
			for slot = 1, 3 do
				local kind = lineup[slot]
				if kind then
					list[slot] = sizes[kind]
					table.insert(names, kind)
				end
			end
			local label = table.concat(names, "+")
			local out = GolemFit.slots(list)
			for slot, size in list do
				local at = out[slot]
				T.truthy(at ~= nil, `{label}: slot {slot} has a spot`)
				T.eq(at.Y, 0, label .. ": on the ground")
				if not size.Huge and at.X == 0 then
					T.le(at.Z, GolemFit.BackMax, label .. ": the back slot stays out of the camera's lap")
				end
				if size.Huge then
					-- clear of its player (and so never straight behind it), a bit further back
					T.truthy(
						math.abs(at.X) - size.Low >= GolemFit.PlayerRadius + GolemFit.Gap - 1e-6,
						`{label}: huge slot {slot} clears its player`
					)
					T.truthy(at.Z >= sideZ + GolemFit.HugeBack - 1e-6, `{label}: huge slot {slot} walks further back`)
					-- the default camera (behind the player, CAMERA_ZOOM away) still sees the player past it
					local depth = CAMERA_ZOOM - at.Z
					if depth > 0 then
						local edge = (math.abs(at.X) - size.Low) / depth
						T.truthy(edge > GolemFit.PlayerRadius / CAMERA_ZOOM, `{label}: huge slot {slot} leaves the player in view`)
					end
				end
				for other, otherSize in list do
					if other > slot and (size.Huge or otherSize.Huge) then
						-- (two huge golems: their whole reach; a huge one by an ordinary one, no taller
						-- than a player: the huge one's low reach)
						local need = if size.Huge and otherSize.Huge
							then size.Radius + otherSize.Radius
							elseif size.Huge then size.Low + otherSize.Radius
							else size.Radius + otherSize.Low
						local d = (Vector3.new(at.X, 0, at.Z) - Vector3.new(out[other].X, 0, out[other].Z)).Magnitude
						T.truthy(d >= need - 1e-6, `{label}: slots {slot} and {other} don't overlap ({d})`)
					end
				end
			end
		end
		-- a huge golem equipped third swaps with a side golem; the ordinary one walks behind
		local out = GolemFit.slots({ sizes.AetherKing, sizes.PebbleGolem, sizes.SkyTitan })
		T.eq(out[1], GolemFit.Base[1], "the first golem keeps the left")
		T.truthy(out[3].X > 0, "the huge third golem walks on the right")
		T.eq(out[2].X, 0, "the ordinary second golem walks behind")
	end)

	T.test("GolemFit: at the default camera huge followers keep out of the middle third (the player and the path ahead)", function()
		-- Roblox's default camera behind a player at the origin who faces -Z (owner space: +Z behind),
		-- looking at the head; a 16:9 screen (the narrowest: a phone in landscape is wider)
		local pitch = GolemFit.CameraPitch
		local head = Vector3.new(0, 4.5, 0)
		local cam = CFrame.lookAt(head + Vector3.new(0, math.sin(pitch), math.cos(pitch)) * GolemFit.CameraDistance, head)
		local tanY = math.tan(math.rad(70) / 2)
		local tanX = tanY * 16 / 9
		local corridor = tanX / 3 -- the middle third of the screen's width
		-- every follower's part corners, its feet at the origin, at its follower size
		local kinds = { "AetherKing", "SkyTitan", "CloudColossus" }
		local corners: { [string]: { any } } = {}
		local sizes: { [string]: any } = {}
		for _, kind in kinds do
			sizes[kind] = sizeOf(kind)
			local list = {}
			for _, p in parts(GolemBuilder.build(kind, CFrame.new(), { Size = followerSize(kind) })) do
				local h = p.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							table.insert(list, (p.CFrame * CFrame.new(sx * h.X, sy * h.Y, sz * h.Z)).Position)
						end
					end
				end
			end
			corners[kind] = list
		end
		local lineups = {}
		for _, a in kinds do
			table.insert(lineups, { a })
			for _, b in kinds do
				table.insert(lineups, { a, b })
				for _, c in kinds do
					table.insert(lineups, { a, b, c })
				end
			end
		end
		local checked = 0
		for _, lineup in lineups do
			local list = {}
			for slot, kind in lineup do
				list[slot] = sizes[kind]
			end
			local out = GolemFit.slots(list)
			local label = table.concat(lineup, "+")
			for slot, kind in lineup do
				if sizes[kind].Huge then
					-- standing or looking round (GolemController.LookAround)
					for _, yaw in { -1.3, 0, 1.3 } do
						local turn = CFrame.new(out[slot]) * CFrame.Angles(0, yaw, 0)
						local nearest = math.huge
						for _, corner in corners[kind] do
							local v = cam:PointToObjectSpace(turn * corner)
							local depth = -v.Z
							if depth > 0.05 and math.abs(v.Y / depth) <= tanY then
								nearest = math.min(nearest, math.abs(v.X) / depth)
							end
						end
						checked += 1
						T.truthy(
							nearest >= corridor,
							`{label}: slot {slot} ({kind}) keeps out of the middle third ({nearest} vs {corridor})`
						)
					end
				end
			end
		end
		T.truthy(checked > 50, "huge followers checked in many line-ups")
	end)

	T.test("GolemFit: the inventory portrait frames a huge golem whole as it turns; others keep their framing", function()
		local aspect = (180 + 30) / (180 + 16) -- GolemView: the Viewport is (portrait + 30) x (portrait + 16)
		local tanY = math.tan(math.rad(GolemFit.ViewFov) / 2)
		local tanX = tanY * aspect
		for _, kind in { "PebbleGolem", "AetherKing", "SkyTitan", "CloudColossus" } do
			local model = GolemBuilder.build(kind)
			local height = model:GetAttribute("Height")
			local radius = GolemFit.radius(model, CFrame.new())
			local cam = GolemFit.view(height, radius, aspect)
			local target = Vector3.new(0, height * 0.48, 0)
			local distance = (cam.Position - target).Magnitude / math.sqrt(1 + 0.15 ^ 2)
			if not GolemConfig.ById[kind].Huge then
				T.near(distance, height * 2.6 + 1, 1e-3, kind .. " keeps its framing")
			end
			for _, spin in { -GolemFit.ViewSpin, 0, GolemFit.ViewSpin } do
				local turn = CFrame.Angles(0, spin, 0)
				for _, p in parts(model) do
					local h = p.Size / 2
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local world = turn * (p.CFrame * CFrame.new(sx * h.X, sy * h.Y, sz * h.Z)).Position
								local v = cam:PointToObjectSpace(world)
								local depth = -v.Z
								T.truthy(depth > 0, kind .. " in front of the camera")
								T.truthy(
									math.abs(v.X / depth) <= tanX and math.abs(v.Y / depth) <= tanY,
									`{kind} {p.Name} turned {spin}: inside the portrait`
								)
							end
						end
					end
				end
			end
		end
	end)

	T.test("GolemFit: GolemController walks its followers to GolemFit.slots and frames its portrait with GolemFit.view", function()
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/GolemController.luau")
		for _, expr in
			{
				"GolemController.Slots = GolemFit.Base",
				"f.Offsets = GolemFit.slots(sizes)",
				"local slot = f.Offsets[pet.Slot] or GolemController.Slots[pet.Slot] or Vector3.zero",
				"Radius = GolemFit.radius(model, start)",
				"cam.CFrame = GolemFit.view(height, GolemFit.radius(model, CFrame.new()), aspect)",
			}
		do
			T.truthy(string.find(source, expr, 1, true) ~= nil, "GolemController: " .. expr)
		end
	end)
end
