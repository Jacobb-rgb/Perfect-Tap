-- The shopkeeper golems (owner 2026-10-24: a big golem behind every shop counter, a
-- different one per shop, with emotes; none at the EGGS temple) under Lune:
-- ShopkeeperConfig's golems, lines, show / hide distances and turn math; GolemEmotes'
-- poses; GolemKeeper's rig (which parts swing with which arm, what stays on the floor)
-- and its frames (the rest pose is the build, a wave raises the right fist and holds a
-- sword up over the head, upright, a hop leaves the aura on the floor); the lobby marks exactly one
-- spot per shop, behind its counter facing the customers, with the golem's head clear of
-- the counter, and the old blocky keepers are gone. The controller's thanks (only for a sale at the
-- Sell golem's counter or bin, or a bought item at that shop; once per sale), Reduce Motion (no
-- Spin / Hop / Dance, a cheer without its jump, a smaller burst) and the queue behind a big move;
-- a keeper has no light of its own.
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

	local SHOPS = { "Gear", "Tech", "Sell", "Enchant", "Vault", "Droppers", "Backpacks" }
	-- the counter tag each shop's spot hangs on
	local COUNTERS = {
		Gear = "ShopCounter",
		Tech = "UpgradeCounter",
		Sell = "SellCounter",
		Enchant = "EnchantCounter",
		Vault = "VaultCounter",
		Droppers = "DropperCounter",
		Backpacks = "BackpackCounter",
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
			for _, d in rig.Model:GetDescendants() do
				T.falsy(d:IsA("PointLight"), `{shop}: no light of its own ({d:GetFullName()}): FaceLight is the only one`)
				if d:IsA("ParticleEmitter") then
					T.le(d.Rate, GolemKeeper.EmberRate, `{shop}: {d.Name} stays calm`)
				end
			end
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
			-- (ENCHANT's stands beside its rune table, level with it, clear of the hut's
			-- facade: the table on its front left)
			local ahead = if shop == "Enchant" then 0.15 else 0.3
			T.truthy(flat.Magnitude > 0.5 and flat.Unit:Dot(look) > ahead, `{shop}: the counter is in front of it`)
			T.truthy(feet.Position.Y < holder.CFrame.Position.Y, `{shop}: its feet below the counter top (the counter hides its step)`)
			local kind, size = ShopkeeperConfig.golem(shop)
			local rig = GolemKeeper.build(kind, feet, size)
			local i = byName(rig)
			local head = rig.Parts[i.Head]
			T.falsy(poking(head, holder), `{shop}: the golem's head clear of the counter`)
			T.truthy(head.CFrame.Position.Y > holder.CFrame.Position.Y, `{shop}: its head over the counter top`)
		end
	end)

	-- How deep two boxes (CFrame, Size) overlap: 0 when apart (separating axes).
	local function overlap(ca: any, sa: any, cb: any, sb: any): number
		local A = { ca.RightVector, ca.UpVector, -ca.LookVector }
		local B = { cb.RightVector, cb.UpVector, -cb.LookVector }
		local ea = { sa.X / 2, sa.Y / 2, sa.Z / 2 }
		local eb = { sb.X / 2, sb.Y / 2, sb.Z / 2 }
		local t = cb.Position - ca.Position
		local axes = { A[1], A[2], A[3], B[1], B[2], B[3] }
		for i = 1, 3 do
			for j = 1, 3 do
				local c = A[i]:Cross(B[j])
				if c.Magnitude > 1e-4 then
					table.insert(axes, c.Unit)
				end
			end
		end
		local depth = math.huge
		for _, L in axes do
			local ra, rb = 0, 0
			for i = 1, 3 do
				ra += ea[i] * math.abs(A[i]:Dot(L))
				rb += eb[i] * math.abs(B[i]:Dot(L))
			end
			local d = ra + rb - math.abs(t:Dot(L))
			if d <= 0 then
				return 0
			end
			depth = math.min(depth, d)
		end
		return depth
	end

	-- The shop's own model (the stall or hut its counter is part of).
	local function shopModel(counter: any): any
		local a = counter
		while a.Parent and a.Parent.Name ~= "Districts" and a.Parent.Name ~= "Vault" do
			a = a.Parent
		end
		return a
	end

	-- Golem parts (posed by `frames`) inside map parts near `feet` (floors and walkways
	-- under its feet aside): { "MapPart/GolemPart" }; `keep(mapPart)` picks the map parts.
	local function clips(rig: any, frames: any, feet: any, keep: (any) -> boolean): { string }
		local out = {}
		for _, mp in map():GetDescendants() do
			if
				mp:IsA("BasePart")
				and mp.Transparency < 1
				and (mp.CFrame.Position - feet.Position).Magnitude < 16 + mp.Size.Magnitude / 2
				and keep(mp)
			then
				local h = mp.Size / 2
				local top = -math.huge
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							top = math.max(top, (mp.CFrame * Vector3.new(h.X * x, h.Y * y, h.Z * z)).Y)
						end
					end
				end
				if top > feet.Position.Y + 0.45 then
					for i, part in rig.Parts do
						if overlap(frames[i], part.Size, mp.CFrame, mp.Size) > 0.06 then
							table.insert(out, mp:GetFullName() .. "/" .. part.Name)
						end
					end
				end
			end
		end
		return out
	end

	T.test("Shopkeepers: no golem inside the map round its shop, the Sell one off the lantern, Enchant's head off its hut", function()
		for _, shop in SHOPS do
			local feet, counter = nil, nil
			for _, d in map():GetDescendants() do
				if hasTag(d, ShopkeeperConfig.Tag) and d:GetAttribute("Shop") == shop then
					feet, counter = d.Parent.CFrame * d.CFrame, d.Parent
				end
			end
			local own = shopModel(counter)
			local kind, size = ShopkeeperConfig.golem(shop)
			local rig = GolemKeeper.build(kind, feet, size)
			local rest = GolemKeeper.frames(rig, feet, GolemEmotes.neutral(), 0)
			local outside = clips(rig, rest, feet, function(mp)
				return not mp:IsDescendantOf(own)
			end)
			T.eq(#outside, 0, `{shop}: inside a map part outside its shop at rest: {table.concat(outside, ", ")}`)
			if shop == "Sell" then
				-- (the entrance lantern beside the stall, also when the golem turns toward a player)
				for _, yaw in { ShopkeeperConfig.LookYaw, -ShopkeeperConfig.LookYaw } do
					local turned = GolemKeeper.frames(rig, feet, GolemEmotes.neutral(), yaw)
					local lantern = clips(rig, turned, feet, function(mp)
						return string.find(mp:GetFullName(), "EntranceLanterns", 1, true) ~= nil
					end)
					T.eq(#lantern, 0, `Sell turned {yaw}: inside the plaza lantern: {table.concat(lantern, ", ")}`)
				end
			elseif shop == "Enchant" then
				-- (its head, helm, halo, crown and wings: out of the facade, the door frame and the pillars)
				local top = {}
				for _, hit in
					clips(rig, rest, feet, function()
						return true
					end)
				do
					local name = string.match(hit, "/([^/]+)$") or ""
					for _, prefix in { "Head", "Helm", "Halo", "Crown", "Feather", "Wing" } do
						if string.sub(name, 1, #prefix) == prefix then
							table.insert(top, hit)
						end
					end
				end
				T.eq(#top, 0, `Enchant: head or wings inside the hut: {table.concat(top, ", ")}`)
			end
		end
	end)

	-- the spot `shop` marks on the map: its golem's feet and the counter it hangs on
	local function spotOf(shop: string): (any, any)
		for _, d in map():GetDescendants() do
			if hasTag(d, ShopkeeperConfig.Tag) and d:GetAttribute("Shop") == shop then
				return d.Parent.CFrame * d.CFrame, d.Parent
			end
		end
		error("no spot for " .. shop)
	end

	-- A stand-in golem for the controller (no parts: its burst counts, no bubble without a head).
	local function standIn(shop: string, feet: any, bursts: { number }): any
		return {
			Shop = shop,
			Feet = feet,
			ThankedAt = -math.huge,
			Emote = nil,
			EmoteAt = 0,
			NextEmote = 0,
			Queued = nil,
			Pose = nil,
			BlendFrom = nil,
			BlendAt = 0,
			Lines = 1,
			Head = nil,
			Burst = {
				Emit = function(_, n: number)
					table.insert(bursts, n)
				end,
			},
		}
	end

	-- Runs `body(Controller, keepers)` with stand-ins for the Sell and Gear golems on their map
	-- spots and the local player's character at `standAt` (nil: none), putting everything back.
	local function withKeepers(standAt: any, body: (any, any) -> ())
		local Players = Loader.game:GetService("Players")
		local hadLocal = rawget(Players, "LocalPlayer")
		local character = nil
		if standAt then
			character = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = CFrame.new(standAt)
			root.Parent = character
		end
		rawset(Players, "LocalPlayer", { Name = "Me", UserId = 1, Character = character })
		local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.ShopkeeperController")
		local keys = {}
		local ok, err = pcall(function()
			local sellFeet = spotOf("Sell")
			local gearFeet = spotOf("Gear")
			local list = {
				Sell = { Bursts = {} },
				Gear = { Bursts = {} },
			}
			list.Sell.Keeper = standIn("Sell", sellFeet, list.Sell.Bursts)
			list.Gear.Keeper = standIn("Gear", gearFeet, list.Gear.Bursts)
			for _, entry in list do
				local key = {}
				table.insert(keys, key)
				Controller.keepers[key] = entry.Keeper
			end
			body(Controller, list)
		end)
		for _, key in keys do
			Controller.keepers[key] = nil
		end
		rawset(Players, "LocalPlayer", hadLocal)
		if not ok then
			error(err, 0)
		end
	end

	T.test("Shopkeepers: the Sell golem thanks for a sale at its counter or bin, once; never for a Sell Box far away", function()
		-- where SellService puts the popups: over the counter's prompt point, on top of the SellBin
		local _, counter = spotOf("Sell")
		local atCounter = (counter.CFrame * CFrame.new(0, counter.Size.Y / 2 + 0.6, -counter.Size.Z / 2)).Position + Vector3.new(0, 1, 0)
		local intake = nil
		for _, d in map():GetDescendants() do
			if hasTag(d, "SellBin") then
				intake = d:FindFirstChild("Intake")
			end
		end
		T.truthy(intake, "the SellBin's intake")
		local atBin = intake.CFrame.Position + Vector3.new(0, intake.Size.Y / 2, 0)
		withKeepers(nil, function(Controller, k)
			local sell, gear = k.Sell, k.Gear
			-- a Sell Box on a plot sells every 2 s: its popups carry the box's position, far away
			local plotBox = sell.Keeper.Feet.Position + Vector3.new(90, 0, 40)
			Controller.onEarned({ Amount = 40, Source = "Sell", Position = plotBox, Count = 3 }, 10)
			Controller.onEarned({ Amount = 40, Source = "Sell", Count = 3 }, 12) -- (no Position: nowhere)
			Controller.onEarned({ Amount = 40, Source = "Offline", Position = atCounter }, 14)
			T.eq(#sell.Bursts, 0, "a Sell Box far away, a popup with no place or another source: no thanks")
			T.eq(sell.Keeper.Emote, nil, "and no cheer")
			-- a sale at the counter: one cheer, one burst, one line (the same sale's echo is no second one)
			Controller.onEarned({ Amount = 120, Source = "Sell", Position = atCounter, Count = 4 }, 20)
			Controller.onEarned({ Amount = 120, Source = "Sell", Position = atCounter, Count = 4 }, 20.2)
			T.eq(#sell.Bursts, 1, "a counter sale thanks once")
			T.eq(sell.Bursts[1], ShopkeeperConfig.BurstCount, "with the full burst")
			T.eq(sell.Keeper.Emote, "Cheer", "the Sell golem cheers")
			T.eq(sell.Keeper.Lines, 2, "one thanks line")
			T.eq(#gear.Bursts, 0, "the SHOP's golem is not the one sold to")
			-- the next sale (past the cooldown), then one into the SellBin
			Controller.onEarned(
				{ Amount = 30, Source = "Sell", Position = atCounter, Count = 1 },
				20 + ShopkeeperConfig.ThanksCooldown + 0.1
			)
			T.eq(#sell.Bursts, 2, "the next sale thanks again")
			Controller.onEarned({ Amount = 30, Source = "Sell", Position = atBin, Count = 1 }, 30)
			T.eq(#sell.Bursts, 3, "a SellBin sale thanks too")
			T.truthy((sell.Keeper.Feet.Position - atBin).Magnitude <= ShopkeeperConfig.ThanksDistance, "the bin is the Sell golem's")
		end)
	end)

	T.test("Shopkeepers: a buy thanks only at that shop's golem, only for a bought item", function()
		T.eq(ShopkeeperConfig.buyShops("ActionResult", { Action = "Gear", Op = "Buy", Ok = true })[1], "Gear")
		T.eq(ShopkeeperConfig.buyShops("ActionResult", { Action = "Enchant", Op = "Buy", Ok = true })[1], "Enchant")
		T.eq(ShopkeeperConfig.buyShops("VaultResult", { Level = 3, Ok = true })[1], "Vault")
		local tech = ShopkeeperConfig.buyShops("ShopResult", { Item = "Crusher", Ok = true })
		T.truthy(table.find(tech, "Tech") and table.find(tech, "Droppers"), "UPGRADES and DROPPERS both open the Tech shop")
		T.eq(ShopkeeperConfig.buyShops("ShopResult", { Item = "Crusher", Ok = false, Reason = "NoCoins" }), nil, "a refusal")
		T.eq(ShopkeeperConfig.buyShops("ActionResult", { Action = "Enchant", Op = "Slot", Ok = true }), nil, "a rune slotted: no buy")
		T.eq(ShopkeeperConfig.buyShops("ActionResult", { Action = "Boost", Op = "Buy", Ok = true }), nil, "a boost: no shop counter")
		T.eq(ShopkeeperConfig.buyShops("ActionResult", { Action = "Wheel", Op = "Spin", Ok = true }), nil, "a wheel spin")
		T.eq(ShopkeeperConfig.buyShops("Notify", { Kind = "Reward", Ok = true }), nil, "a Reward toast is no buy")
		-- the player at the SHOP counter: a gear buy makes its golem cheer, nothing else does
		local gearFeet = spotOf("Gear")
		local standAt = (gearFeet * CFrame.new(0, 3, -6)).Position
		withKeepers(standAt, function(Controller, k)
			Controller.onBought("ActionResult", { Action = "Gear", Op = "Buy", Ok = false, Reason = "NoCoins" }, 40)
			Controller.onBought("ShopResult", { Item = "Crusher", Ok = true }, 41)
			Controller.onBought("ActionResult", { Action = "Boost", Op = "Buy", Ok = true }, 42)
			T.eq(#k.Gear.Bursts + #k.Sell.Bursts, 0, "a refusal, another shop's buy, a boost: no thanks")
			Controller.onBought("ActionResult", { Action = "Gear", Op = "Buy", Ok = true, Id = "Boots", Level = 2 }, 50)
			T.eq(#k.Gear.Bursts, 1, "a gear buy at the SHOP: its golem thanks")
			T.eq(k.Gear.Keeper.Emote, "Cheer")
			T.eq(#k.Sell.Bursts, 0, "the Sell golem does not")
		end)
		-- away from the counter (a Robux lift bought anywhere): no golem near
		withKeepers((gearFeet * CFrame.new(0, 3, -60)).Position, function(Controller, k)
			Controller.onBought("ActionResult", { Action = "Gear", Op = "Buy", Ok = true }, 60)
			T.eq(#k.Gear.Bursts, 0, "too far from the SHOP's golem")
		end)
	end)

	T.test("Shopkeepers: Reduce Motion: no Spin, Hop or Dance, a cheer without its jump, a smaller burst", function()
		local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")
		local Controller = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.ShopkeeperController")
		local big = { Spin = true, Hop = true, Dance = true }
		local ok, err = pcall(function()
			Motion.setReduced(true)
			local seen = {}
			for _ = 1, 400 do
				local move = Controller.pickMove()
				T.falsy(big[move], `Reduce Motion picked {move}`)
				seen[move] = true
			end
			T.truthy(seen.Bow and seen.Wave, "it still bows and waves")
			-- the cheer keeps its arms up but stays on the floor (the idle's breath only)
			for _, t in { 0.2, 0.4, 0.8, 1.2 } do
				local calm = GolemEmotes.pose("Cheer", t, 2.5, true)
				T.near(calm.Lift, GolemEmotes.idle(2.5).Lift, 1e-9, `no jump at {t} s`)
			end
			T.truthy(GolemEmotes.pose("Cheer", 0.8, 2.5, true).Right > 2.5, "both arms still go up")
			T.truthy(GolemEmotes.pose("Cheer", 0.4, 2.5).Lift > GolemEmotes.idle(2.5).Lift + 0.05, "(without it: a jump)")
			withKeepers(nil, function(_, k)
				local feet = k.Sell.Keeper.Feet
				Controller.onEarned({ Amount = 5, Source = "Sell", Position = feet.Position, Count = 1 }, 70)
				T.eq(k.Sell.Bursts[1], ShopkeeperConfig.BurstCalm, "a smaller burst")
				T.truthy(ShopkeeperConfig.BurstCalm < ShopkeeperConfig.BurstCount)
			end)
		end)
		Motion.setReduced(false)
		if not ok then
			error(err, 0)
		end
		local seen = {}
		for _ = 1, 400 do
			seen[Controller.pickMove()] = true
		end
		T.truthy(seen.Spin and seen.Hop and seen.Dance, "with it off every move comes back")
	end)

	T.test("Shopkeepers: a thanks during a Spin waits for it; one during a Wave blends in", function()
		local wave = GolemEmotes.pose("Wave", 1.0, 0)
		local mid = GolemEmotes.mix(wave, GolemEmotes.neutral(), 0.5)
		T.near(mid.Right, wave.Right / 2, 1e-9, "mix: half way")
		T.near(GolemEmotes.mix(wave, GolemEmotes.neutral(), 2).Right, 0, 1e-9, "mix: clamped")
		withKeepers(nil, function(Controller, k)
			local sell = k.Sell.Keeper
			local at = sell.Feet.Position
			sell.Emote, sell.EmoteAt = "Spin", 79.6
			Controller.onEarned({ Amount = 5, Source = "Sell", Position = at, Count = 1 }, 80)
			T.eq(sell.Emote, "Spin", "the spin goes on (no snap back to the front)")
			T.eq(sell.Queued, "Cheer", "the cheer waits for it")
			T.eq(#k.Sell.Bursts, 1, "the burst and the line come at once")
			-- a Wave running: the cheer cuts in, blending from the pose shown
			sell.Queued, sell.Emote, sell.EmoteAt, sell.Pose = nil, "Wave", 89, wave
			Controller.onEarned({ Amount = 5, Source = "Sell", Position = at, Count = 1 }, 90)
			T.eq(sell.Emote, "Cheer", "the cheer starts")
			T.eq(sell.BlendFrom, wave, "from the wave's pose")
			T.eq(sell.BlendAt, 90)
		end)
		for emote in GolemEmotes.Big do
			T.falsy(table.find(GolemEmotes.Calm, emote), emote .. " is no calm move")
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
