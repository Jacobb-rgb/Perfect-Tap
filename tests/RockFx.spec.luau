-- The rock breaking animation math (client Effects/RockFxLogic): debris plans, caps, motion, envelopes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Color3 = roblox.Color3
	local Vector3 = roblox.Vector3
	local MineFloors = Loader.requirePath("ReplicatedStorage.Shared.Config.MineFloors")
	local RockBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.RockBuilder")
	local Logic = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RockFxLogic")

	local CRUST = Color3.fromRGB(150, 130, 110)
	local GLOW = Color3.fromRGB(255, 150, 70)
	local KINDS = { "Small", "Big", "Crystal", "Golden", "Geode", "Artifact", "Giant" }

	local function count(pieces, kind)
		local n = 0
		for _, p in pieces do
			if p.Kind == kind then
				n += 1
			end
		end
		return n
	end

	T.test("RockFx: budget never goes over the 30-piece cap and keeps the mix", function()
		T.eq(Logic.Cap, 30, "cap")
		local c, s = Logic.budget(10, 6, 0)
		T.eq(c, 10, "all chunks fit")
		T.eq(s, 6, "all shards fit")
		for alive = 0, 35 do
			for _, want in { { 10, 6 }, { 14, 16 }, { 7, 12 }, { 3, 5 } } do
				local chunks, shards = Logic.budget(want[1], want[2], alive)
				T.le(alive + chunks + shards, math.max(alive, Logic.Cap), "cap at " .. alive)
				T.le(chunks, want[1], "never more chunks than wanted")
				T.le(shards, want[2], "never more shards than wanted")
				if Logic.Cap - alive >= 2 then
					T.truthy(chunks >= 1 and shards >= 1, "both kinds while two fit (alive " .. alive .. ")")
				end
			end
		end
		local full1, full2 = Logic.budget(10, 6, 30)
		T.eq(full1 + full2, 0, "nothing when full")
		local over1, over2 = Logic.budget(10, 6, 40)
		T.eq(over1 + over2, 0, "nothing when over")
		T.eq(Logic.Counts.Giant.Chunks + Logic.Counts.Giant.Shards, Logic.Cap, "a Giant Crystal fills the cap by itself")
	end)

	T.test("RockFx: shatter throws rock chunks in the floor's rock colors and shards in its crystal colors", function()
		for _, floor in MineFloors.List do
			local pal = floor.Palette
			local pieces = Logic.shatterPlan({
				Position = Vector3.new(0, 3, 0),
				Crust = CRUST,
				Glow = GLOW,
				Floor = floor.Index,
				Kind = "Big",
				Radius = 2.5,
				Ground = 0,
				Seed = 1,
			})
			T.eq(count(pieces, "Chunk"), Logic.Counts.Big.Chunks, floor.Id .. " chunks")
			T.eq(count(pieces, "Shard"), Logic.Counts.Big.Shards, floor.Id .. " shards")
			for _, p in pieces do
				if p.Kind == "Chunk" then
					T.truthy(p.Color == pal.Mid or p.Color == pal.Light or p.Color == pal.Dark, floor.Id .. " chunk in rock colors")
					T.eq(p.Neon, false, "rock chunks are not neon")
				else
					T.truthy(p.Color == pal.Crystal or p.Color == pal.Crystal2, floor.Id .. " shard in crystal colors")
				end
				T.le(p.Life, Logic.MaxLife, "gone within 1.5 s")
				T.truthy(p.Size.X > 0.05 and p.Size.Magnitude < 4, "piece size")
				T.truthy(p.Velocity.Y > 0, "pieces fly up first")
			end
		end
		-- special rocks keep their shared colors
		local golden = Logic.shatterPlan({ Position = Vector3.zero, Crust = CRUST, Glow = GLOW, Floor = 3, Kind = "Golden", Seed = 2 })
		local gold = RockBuilder.Special.Gold
		local hasGold = false
		for _, p in golden do
			if p.Kind == "Chunk" and p.Color == gold then
				hasGold = true
			end
		end
		T.truthy(hasGold, "golden rock throws gold chunks")
		T.eq(Logic.Special.Gold, RockBuilder.Special.Gold, "same gold as the rock builder")
		T.eq(Logic.Special.Geode, RockBuilder.Special.Geode, "same geode color")
		T.eq(Logic.Special.GeodeShell, RockBuilder.Special.GeodeShell, "same geode shell")
		T.eq(Logic.Special.Rune, RockBuilder.Special.Rune, "same rune color")
	end)

	T.test("RockFx: Giant Crystal shatters bigger, every kind works, the cap holds with pieces alive", function()
		local small = Logic.shatterPlan({ Position = Vector3.zero, Crust = CRUST, Glow = GLOW, Floor = 2, Kind = "Small", Seed = 3 })
		local giant =
			Logic.shatterPlan({ Position = Vector3.zero, Crust = CRUST, Glow = GLOW, Floor = 2, Kind = "Giant", Radius = 7, Seed = 3 })
		T.lt(#small, #giant, "more pieces")
		local function biggest(pieces)
			local m = 0
			for _, p in pieces do
				m = math.max(m, p.Size.Magnitude)
			end
			return m
		end
		T.lt(biggest(small), biggest(giant), "bigger pieces")
		for _, kind in KINDS do
			for alive = 0, 30, 5 do
				local pieces = Logic.shatterPlan({
					Position = Vector3.zero,
					Crust = CRUST,
					Glow = GLOW,
					Floor = 4,
					Kind = kind,
					Alive = alive,
					Seed = kind,
				})
				T.le(#pieces + alive, math.max(alive, Logic.Cap), kind .. " under the cap with " .. alive .. " alive")
			end
		end
	end)

	T.test("RockFx: old 3-value events (no floor / kind) use the crust and glow colors", function()
		local pieces = Logic.shatterPlan({ Position = Vector3.new(0, 2, 0), Crust = CRUST, Glow = GLOW, Seed = 4 })
		T.eq(count(pieces, "Chunk"), Logic.Counts.Small.Chunks, "small rock by default")
		local colors = Logic.colors(nil, nil, CRUST, GLOW)
		T.eq(colors.Rock[1], CRUST, "crust chunks")
		T.eq(colors.Crystal[1], GLOW, "glow shards")
		for _, p in pieces do
			T.truthy(p.Ground < 2, "ground below the rock")
		end
		local crack = Logic.crackPlan({ Position = Vector3.new(0, 2, 0), Crust = CRUST, Glow = GLOW, Stage = 1, Seed = 5 })
		T.truthy(count(crack, "Shard") >= 4, "crack shards")
		T.truthy(count(crack, "Chunk") >= 2, "crack chips")
		for _, p in crack do
			if p.Kind == "Shard" then
				T.eq(p.Neon, true, "crack shards glow")
				T.truthy(p.Color == GLOW or p.Color == GLOW:Lerp(Color3.new(1, 1, 1), 0.35), "crack shards in the stage glow")
			end
			T.le(p.Life, 1, "crack pieces are short")
		end
		local last = Logic.crackPlan({ Position = Vector3.zero, Crust = CRUST, Glow = GLOW, Stage = 3, Stages = 4, Seed = 5 })
		T.lt(count(crack, "Shard"), count(last, "Shard"), "the last crack before the shatter pops more")
		local full = Logic.crackPlan({ Position = Vector3.zero, Crust = CRUST, Glow = GLOW, Stage = 1, Alive = 30, Seed = 5 })
		T.eq(#full, 0, "no crack debris when the cap is full")
	end)

	T.test("RockFx: pieces fly up, come down, never sink below the ground, shrink and fade out", function()
		local pieces = Logic.shatterPlan({
			Position = Vector3.new(0, 3, 0),
			Crust = CRUST,
			Glow = GLOW,
			Floor = 1,
			Kind = "Big",
			Radius = 2.5,
			Ground = 0,
			Seed = 6,
		})
		for _, p in pieces do
			local cf0, scale0 = Logic.sample(p, 0)
			T.near((cf0.Position - p.Origin).Magnitude, 0, 1e-6, "starts at its origin")
			T.lt(scale0, 1, "pops in")
			local peak = -math.huge
			local lastY = cf0.Position.Y
			local landed = false
			for step = 1, 60 do
				local t = step * p.Life / 60
				local cf, scale, transparency, done = Logic.sample(p, t)
				local y = cf.Position.Y
				peak = math.max(peak, y)
				T.truthy(y >= p.Ground - 1e-6, "above the ground")
				T.truthy(scale > 0 and scale <= 1, "scale in range")
				T.truthy(transparency >= 0 and transparency <= 1, "transparency in range")
				if y <= p.Ground + p.Size.Magnitude then
					landed = true
				end
				if step == 60 then
					T.eq(done, true, "done at the end of its life")
					T.lt(scale, 0.3, "shrunk at the end")
					T.near(transparency, 1, 1e-6, "invisible at the end")
				end
				lastY = y
			end
			T.lt(cf0.Position.Y, peak, "flies up first")
			T.truthy(landed, "comes back down to the ground")
			T.truthy(lastY < peak, "lower at the end than at the peak")
		end
	end)

	T.test("RockFx: flash, ring and shake envelopes", function()
		T.eq(Logic.flash(0, 0.3), 0, "flash starts dark")
		T.near(Logic.flash(0.035, 0.3), 1, 0.05, "flash peaks fast")
		T.lt(Logic.flash(0.2, 0.3), Logic.flash(0.1, 0.3), "flash fades")
		T.eq(Logic.flash(0.3, 0.3), 0, "flash over")
		local d0, t0 = Logic.ring(0, 0.4, 1.5, 7)
		local d1, t1 = Logic.ring(0.4, 0.4, 1.5, 7)
		T.near(d0, 3, 1e-6, "ring starts at r0")
		T.near(d1, 14, 1e-6, "ring ends at r1")
		T.lt(t0, t1, "ring fades")
		T.eq(Logic.shakeOffset(0.3, 0.22, 0.07, 1).Position.Magnitude, 0, "shake over")
		-- the ring is drawn as bars around the circle (a Cylinder part would be a solid disc)
		local frames, length = Logic.ringSegments(Vector3.new(10, 0.2, -4), 8, 16)
		T.eq(#frames, 16, "one frame per bar")
		T.truthy(length > 8 * math.pi / 16 and length < 8 * math.pi / 16 * 1.2, "bars close the circle")
		for _, cf in frames do
			local offset = cf.Position - Vector3.new(10, 0.2, -4)
			T.near(offset.Magnitude, 4, 1e-6, "on the circle")
			T.near(math.abs(cf.LookVector:Dot(offset.Unit)), 0, 1e-6, "bar along the circle (tangent)")
		end
		for step = 0, 21 do
			local offset = Logic.shakeOffset(step / 100, 0.22, 0.07, 2.5)
			T.le(offset.Position.Magnitude, 0.07 * math.sqrt(2) + 1e-6, "tiny tremble")
		end
	end)
end
