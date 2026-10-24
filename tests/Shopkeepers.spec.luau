-- The shopkeeper golems (owner 2026-10-24: a big golem behind every shop counter, a
-- different one per shop, with emotes; none at the EGGS temple) under Lune:
-- ShopkeeperConfig's golems, lines, show / hide distances and turn math; GolemEmotes'
-- poses; GolemKeeper's rig (which parts swing with which arm, what stays on the floor)
-- and its frames (the rest pose is the build, a wave raises the right fist and holds a
-- sword up over the head, upright, a hop leaves the aura on the floor); the lobby marks exactly one
-- spot per shop, behind its counter facing the customers, with the golem's head clear of
-- the counter, and the old blocky keepers are gone.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local ShopkeeperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ShopkeeperConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local GolemEmotes = Loader.requirePath("ReplicatedStorage.Shared.Moves.GolemEmotes")
	local GolemKeeper = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemKeeper")
	local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")

	local SHOPS = { "Gear", "Tech", "Sell", "Enchant", "Vault", "Droppers" }
	-- the counter tag each shop's spot hangs on
	local COUNTERS = {
		Gear = "ShopCounter",
		Tech = "UpgradeCounter",
		Sell = "SellCounter",
		Enchant = "EnchantCounter",
		Vault = "VaultCounter",
		Droppers = "DropperCounter",
	}

	local function hasTag(inst: any, tag: string): boolean
		return table.find(inst:GetTags(), tag) ~= nil
	end

	T.test("Shopkeepers: a different golem at every shop, lines that fit the bubble", function()
		local seen = {}
		for _, shop in { "Gear", "Tech", "Sell", "Enchant", "Vault", "Droppers", "Backpacks" } do
			local s = ShopkeeperConfig.Shops[shop]
			T.truthy(s, shop)
			T.truthy(GolemConfig.ById[s.Golem], `{shop}: {s.Golem} is a golem of the game`)
			T.eq(seen[s.Golem], nil, `{shop}: {s.Golem} serves only one shop`)
			seen[s.Golem] = shop
			T.truthy(s.Size >= 1 and s.Size <= 2, `{shop} size {s.Size}`)
			for _, kind in { "Hello", "Thanks" } do
				T.truthy(#s[kind] >= 1, `{shop} {kind}`)
				for _, line in s[kind] do
					T.le(#line, 30, `{shop}: "{line}" fits the bubble`)
				end
			end
		end
		T.eq(ShopkeeperConfig.Shops.Eggs, nil, "no keeper at the EGGS temple (owner)")
		T.truthy(ShopkeeperConfig.lit("Vault"), "a dark shop's golem gets the soft light")
		T.falsy(ShopkeeperConfig.lit("Droppers"), "the bright DROPPERS shop's does not")
		local kind, size = ShopkeeperConfig.golem("Nowhere")
		T.eq(kind, ShopkeeperConfig.Shops.Gear.Golem, "an unknown shop gets the Gear golem")
		T.eq(size, ShopkeeperConfig.Shops.Gear.Size, "and its size")
		local hello = ShopkeeperConfig.Shops.Gear.Hello
		T.eq(ShopkeeperConfig.line("Gear", "Hello", #hello + 1), hello[1], "lines wrap round")
		T.eq(ShopkeeperConfig.line("Nowhere", "Thanks", 1), "Thanks!", "an unknown shop says thanks")
	end)

	T.test("Shopkeepers: built near the player, gone far away, steady in between", function()
		local show, hide = ShopkeeperConfig.ShowDistance, ShopkeeperConfig.HideDistance
		T.truthy(hide > show, "a gap between showing and hiding")
		T.truthy(ShopkeeperConfig.wanted(show - 1, false), "near: built")
		T.falsy(ShopkeeperConfig.wanted(show + 1, false), "not yet in the gap")
		T.truthy(ShopkeeperConfig.wanted(show + 1, true), "stays in the gap")
		T.falsy(ShopkeeperConfig.wanted(hide + 1, true), "far: gone")
		T.truthy(ShopkeeperConfig.AnimateDistance <= show, "only built golems move")
	end)

	T.test("Shopkeepers: the golem turns toward the player, clamped, never backwards", function()
		local body = CFrame.new(0, 0, 0) -- faces -Z
		T.near(ShopkeeperConfig.lookYaw(body, Vector3.new(0, 3, -10)), 0, 1e-6, "straight ahead")
		local yaw = ShopkeeperConfig.lookYaw(body, Vector3.new(3, 3, -10))
		T.truthy(yaw < 0, "a player on its right turns it right (negative yaw)")
		T.near((CFrame.Angles(0, yaw, 0)).LookVector:Dot(Vector3.new(3, 0, -10).Unit), 1, 1e-6, "it faces him")
		T.near(ShopkeeperConfig.lookYaw(body, Vector3.new(-30, 3, -1)), ShopkeeperConfig.LookYaw, 1e-6, "far left: clamped")
		T.eq(ShopkeeperConfig.lookYaw(body, Vector3.new(2, 3, 6)), 0, "behind it: looks ahead")
	end)

	T.test("Shopkeepers: the emotes", function()
		for _, emote in GolemEmotes.OnTheirOwn do
			T.truthy(GolemEmotes.Duration[emote], emote .. " has a length")
		end
		for emote, d in GolemEmotes.Duration do
			local after = GolemEmotes.move(emote, d + 0.01)
			T.eq(after.Lift + after.Yaw + after.Pitch + after.Roll + after.Right + after.Left, 0, emote .. " ends at rest")
			local start = GolemEmotes.move(emote, 0)
			T.near(start.Lift, 0, 1e-6, emote .. " starts on the floor")
		end
		local idle = GolemEmotes.pose(nil, 0, 1.7)
		T.truthy(math.abs(idle.Lift) < 0.01 and idle.Right < 0.2, "the idle barely moves")
		T.truthy(GolemEmotes.move("Wave", 1.0).Right > 2, "a wave: the right arm over the head")
		T.near(GolemEmotes.move("Wave", 1.0).Left, 0, 1e-6, "the left arm stays down")
		local cheer = GolemEmotes.move("Cheer", 0.8)
		T.truthy(cheer.Right > 2.5 and cheer.Left > 2.5, "a cheer: both arms up")
		T.near(GolemEmotes.move("Hop", 0.35).Lift, 0.12, 1e-6, "a hop's top")
		T.near(GolemEmotes.move("Spin", GolemEmotes.Duration.Spin).Yaw, 2 * math.pi, 1e-6, "a spin turns all the way round")
		T.truthy(GolemEmotes.move("Bow", 0.8).Pitch < -0.3, "a bow leans forward")
	end)

	T.test("Shopkeepers: which parts swing with which arm, what stays on the floor", function()
		local cases = {
			{ "Arm2", 1, "Right" },
			{ "Fist1", -1, "Left" },
			{ "Claw2_1", 1, "Right" },
			{ "BracerGem1", -1, "Left" },
			{ "Bracer2", 1, "Right" },
			{ "Blade", 1, "RightHeld" },
			{ "Staff", 1, "RightHeld" },
			{ "Shield", -1, "LeftHeld" },
			{ "Aura", 0, "Ground" },
			{ "Floor3", -0.7, "Ground" },
			{ "RingFlame1", 1.2, "Ground" },
			{ "Head", 0, "Body" },
			{ "Wing1_1A", -2, "Body" },
			{ "Armor", 0.5, "Body" },
		}
		for _, c in cases do
			T.eq(GolemKeeper.group(c[1], c[2]), c[3], c[1])
		end
	end)

	local function byName(rig: any): { [string]: number }
		local out = {}
		for i, part in rig.Parts do
			out[part.Name] = i
		end
		return out
	end

	T.test("Shopkeepers: every shop golem's rig holds the build at rest, no studs", function()
		local feet = CFrame.new(5, 2, -3) * CFrame.Angles(0, 0.6, 0)
		for _, shop in SHOPS do
			local kind, size = ShopkeeperConfig.golem(shop)
			local rig = GolemKeeper.build(kind, feet, size)
			T.truthy(hasTag(rig.Model, GolemKeeper.SkipTag), `{shop}: tagged NoStuds (no Roblox studs)`)
			T.truthy(rig.Height >= 5.5 and rig.Height <= 8.5, `{shop}: a big golem ({rig.Height} studs)`)
			T.eq(#rig.Parts, #rig.Offsets, "an offset per part")
			local frames = GolemKeeper.frames(rig, feet, GolemEmotes.neutral(), 0)
			for i, part in rig.Parts do
				T.near((frames[i].Position - part.CFrame.Position).Magnitude, 0, 1e-4, `{shop}: {part.Name} at rest`)
				T.truthy(part.Anchored and not part.CanCollide and not part.CanQuery, `{shop}: {part.Name} still and harmless`)
			end
		end
	end)

	T.test("Shopkeepers: a wave raises the right fist, a held sword stays upright, a hop leaves the aura", function()
		local feet = CFrame.new()
		local kind, size = ShopkeeperConfig.golem("Gear") -- the knight: a sword in his right hand, a shield in his left
		local rig = GolemKeeper.build(kind, feet, size)
		local i = byName(rig)
		local wave = GolemKeeper.frames(rig, feet, GolemEmotes.pose("Wave", 1.0, 0), 0)
		local rest = GolemKeeper.frames(rig, feet, GolemEmotes.neutral(), 0)
		-- (stubby golem arms under a big head: the fist comes up beside the head)
		T.truthy(wave[i.Fist2].Position.Y > rig.ShoulderR.Position.Y, "the right fist goes over the shoulder")
		T.truthy(wave[i.Fist2].Position.Y > rest[i.Fist2].Position.Y + 0.15 * rig.Height, "well up")
		T.truthy(wave[i.Blade].Position.Y > rest[i.Head].Position.Y, "the sword goes over the head")
		T.near((wave[i.Fist1].Position - rest[i.Fist1].Position).Magnitude, 0, 0.15, "the left fist stays down")
		T.truthy(wave[i.Blade].Position.Y > rest[i.Blade].Position.Y + 1, "the sword goes up with the hand")
		T.near(wave[i.Blade].UpVector:Dot(rest[i.Blade].UpVector), 1, 1e-3, "and stays upright")
		-- a hop: the body up, the aura on the floor (the Tech golem hovers on one)
		local tKind, tSize = ShopkeeperConfig.golem("Tech")
		local hover = GolemKeeper.build(tKind, feet, tSize)
		local h = byName(hover)
		T.truthy(h.Aura, "the Tech golem has an aura")
		local hop = GolemKeeper.frames(hover, feet, GolemEmotes.move("Hop", 0.35), 0)
		local still = GolemKeeper.frames(hover, feet, GolemEmotes.neutral(), 0)
		T.near(hop[h.Body].Position.Y - still[h.Body].Position.Y, 0.12 * hover.Height, 1e-3, "the body hops")
		T.near((hop[h.Aura].Position - still[h.Aura].Position).Magnitude, 0, 1e-6, "the aura stays on the floor")
		-- turned toward the player: the whole golem turns about its feet
		local turned = GolemKeeper.frames(rig, feet, GolemEmotes.neutral(), 0.4)
		T.near(turned[i.Head].Position.Y, rest[i.Head].Position.Y, 1e-4, "a turn keeps its height")
	end)

	local cachedMap = nil
	local function map(): any
		if not cachedMap then
			local game = Instance.new("DataModel")
			cachedMap = WorldBuilder.build(game:GetService("Workspace"))
		end
		return cachedMap
	end

	-- Is any corner of `part` inside `box` (a part)?
	local function poking(part: any, box: any): boolean
		local half = part.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local p = box.CFrame:PointToObjectSpace(part.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z))
					local b = box.Size / 2
					if math.abs(p.X) < b.X and math.abs(p.Y) < b.Y and math.abs(p.Z) < b.Z then
						return true
					end
				end
			end
		end
		return false
	end

	T.test("Shopkeepers: one spot per shop, behind its counter, the golem's head clear of it", function()
		local spots = {}
		for _, d in map():GetDescendants() do
			if hasTag(d, ShopkeeperConfig.Tag) then
				T.truthy(d:IsA("Attachment"), d:GetFullName() .. " is an Attachment (no part)")
				local shop = d:GetAttribute("Shop")
				T.eq(spots[shop], nil, `one spot for {shop}`)
				T.truthy(ShopkeeperConfig.Shops[shop], `{shop} is a known shop`)
				spots[shop] = d
			end
		end
		T.eq(spots.Eggs, nil, "none at the EGGS temple (owner)")
		for _, shop in SHOPS do
			local spot = spots[shop]
			T.truthy(spot, `{shop} has a keeper spot`)
			local holder = spot.Parent
			T.truthy(holder:IsA("BasePart") and hasTag(holder, COUNTERS[shop]), `{shop}: on the {COUNTERS[shop]}`)
			local feet = holder.CFrame * spot.CFrame
			local look = feet.LookVector
			T.near(look.Y, 0, 1e-4, `{shop}: stands upright`)
			local toCounter = holder.CFrame.Position - feet.Position
			local flat = Vector3.new(toCounter.X, 0, toCounter.Z)
			-- (the gap from its feet to the counter's box: right behind it, or by its end)
			local q = holder.CFrame:PointToObjectSpace(feet.Position)
			local gx = math.max(math.abs(q.X) - holder.Size.X / 2, 0)
			local gz = math.max(math.abs(q.Z) - holder.Size.Z / 2, 0)
			local gap = math.sqrt(gx * gx + gz * gz)
			T.truthy(gap < 4.5, `{shop}: at the counter ({gap} studs from it)`)
			T.truthy(flat.Magnitude > 0.5 and flat.Unit:Dot(look) > 0.3, `{shop}: the counter is in front of it`)
			T.truthy(feet.Position.Y < holder.CFrame.Position.Y, `{shop}: its feet below the counter top (the counter hides its step)`)
			local kind, size = ShopkeeperConfig.golem(shop)
			local rig = GolemKeeper.build(kind, feet, size)
			local i = byName(rig)
			local head = rig.Parts[i.Head]
			T.falsy(poking(head, holder), `{shop}: the golem's head clear of the counter`)
			T.truthy(head.CFrame.Position.Y > holder.CFrame.Position.Y, `{shop}: its head over the counter top`)
		end
	end)

	T.test("Shopkeepers: the old blocky keepers are gone", function()
		for _, d in map():GetDescendants() do
			if d:IsA("Model") then
				for _, name in { "Tobin", "Outfitter", "Forgemaster Ulda", "Enchanter" } do
					T.truthy(d.Name ~= name, `{name} left the map`)
				end
			end
		end
	end)
end
